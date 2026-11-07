// Package manifest 实现 S8 §3 清单语义：继承链（§3.3）、属性替换（§3.4）、
// profile 激活与合并（§3.8）。诊断码限定在 XPD-3xx（坐标与继承段位）。
package manifest

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xpd"
)

// XPD-3xx 诊断码（坐标与继承段位，S8 附录 C.6）。
const (
	codeCoords        = "XPD-301"
	codeCoordsDup     = "XPD-302"
	codeDepth         = "XPD-303"
	codeCycle         = "XPD-304"
	codeParentMissing = "XPD-305"
	codeParentNotPOM  = "XPD-306"
	codeUnresolvedVar = "XPD-307"
	codeEnumVar       = "XPD-308"
	codeProfile       = "XPD-309"
	codeDepVersion    = "XPD-401" // 依赖缺版本
	codeVersionForm   = "XPD-402" // 版本形态非法（范围/SNAPSHOT/LATEST）
	codeDepConflict   = "XPD-403" // 同层坐标冲突/管理表重复
	codeLockMismatch  = "XPD-404" // 锁与清单不一致/缺条目
	codeLockExtra     = "XPD-405" // 锁定坐标多余
	codeLockDigest    = "XPD-406" // 摘要格式/内容不符/排序不稳
	codeManagedField  = "XPD-407" // 管理表出现 scope/optional
)

const maxParentDepth = 8

// Options 是清单解析的构建期输入。
type Options struct {
	Profiles         []string // -P 显式激活
	Platform         string   // 当前构建平台（macos/linux/windows…）
	ToolchainVersion string   // 内置变量 xnull.version
}

// Resolved 是继承与 profile 合并后的清单视图（值已完成单次变量替换）。
type Resolved struct {
	GroupID    string
	ArtifactID string
	Version    string
	Packaging  string

	Properties    map[string]string
	Dependencies  map[string]string // 坐标 → 版本
	Build         map[string]string // build 段标量字段
	Configuration map[string]string

	ActiveProfiles []string
	Chain          []string // 根 → 子 的清单绝对路径

	// Plugins 是 build.plugins 的声明（供 S8-05 插件合同校验）。
	Plugins []PluginRef
	// Managed 是合并后的 dependencyManagement（坐标→版本，子优先）。
	Managed map[string]string
	// Warnings 是构建警告（如依赖显式版本覆盖管理版本）。
	Warnings []string
}

type parentRef struct {
	groupID, artifactID, version, relativePath string
	pos                                        xpd.Pos
}

type profileData struct {
	id         string
	platform   string
	properties map[string]string
	deps       map[string]string
	build      map[string]string
	config     map[string]string
}

type fileData struct {
	path      string
	groupID   string
	artifact  string
	version   string
	packaging string
	parent    *parentRef
	props     map[string]string
	deps      map[string]string
	build     map[string]string
	config    map[string]string
	profiles  []profileData
	managed   map[string]managedEntry
	plugins   []PluginRef
}

type managedEntry struct {
	version string
}

// PluginRef 是清单中的一条插件声明（build.plugins.plugin）。
type PluginRef struct {
	Coordinate string // groupId:artifactId
	Version    string // 块头第二参数（精确版本）
	Phase      string
	Goal       string
	Config     map[string]string
}

// Load 解析 path 指向的工程清单：展开继承链、执行变量替换、合并激活的 profile。
// IO 错误通过 error 返回；清单语义问题通过诊断返回（此时 Resolved 为 nil）。
func Load(path string, opts Options) (*Resolved, []diag.Diagnostic, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return nil, nil, err
	}
	// 1. 自底向上收集继承链
	var chainFiles []*fileData // 子 → 根
	var diags []diag.Diagnostic
	seen := map[string]bool{}
	cur := abs
	depth := 0
	for {
		if seen[cur] {
			diags = append(diags, diag.Diagnostic{File: cur, Line: 1, Col: 1, Code: codeCycle,
				Message: fmt.Sprintf("继承链成环或 self-parent：%s", cur)})
			break
		}
		seen[cur] = true
		fd, ds, err := parseFile(cur)
		if err != nil {
			return nil, nil, err
		}
		diags = append(diags, ds...)
		if fd == nil {
			break
		}
		chainFiles = append(chainFiles, fd)
		if fd.parent == nil {
			break
		}
		if depth+1 > maxParentDepth {
			diags = append(diags, diag.Diagnostic{File: cur, Line: fd.parent.pos.Line, Col: fd.parent.pos.Col,
				Code: codeDepth, Message: fmt.Sprintf("继承深度超过上限 %d（S8 §3.3）", maxParentDepth)})
			break
		}
		next := fd.parent.relativePath
		if next == "" {
			next = "../xnull.project"
		}
		nextAbs, perr := filepath.Abs(filepath.Join(filepath.Dir(cur), next))
		if perr != nil {
			return nil, nil, perr
		}
		if st, serr := os.Stat(nextAbs); serr != nil || st.IsDir() {
			diags = append(diags, diag.Diagnostic{File: cur, Line: fd.parent.pos.Line, Col: fd.parent.pos.Col,
				Code: codeParentMissing, Message: fmt.Sprintf("parent 缺失：%s（S8 §3.3）", nextAbs)})
			break
		}
		pfd, pds, err := parseFile(nextAbs)
		if err != nil {
			return nil, nil, err
		}
		diags = append(diags, pds...)
		if pfd == nil || pfd.packaging != "pom" {
			diags = append(diags, diag.Diagnostic{File: nextAbs, Line: 1, Col: 1, Code: codeParentNotPOM,
				Message: "parent 必须是 packaging = pom（S8 §3.3）"})
			break
		}
		depth++
		cur = nextAbs
	}
	if len(diags) > 0 {
		return nil, diags, nil
	}
	if len(chainFiles) == 0 {
		return nil, []diag.Diagnostic{{File: abs, Line: 1, Col: 1, Code: codeCoords, Message: "清单缺少 project 块（S8 §3.2）"}}, nil
	}

	// 2. 坐标：只认子工程自身（不从父继承）
	child := chainFiles[0]
	for _, fld := range []struct {
		name, val string
	}{{"groupId", child.groupID}, {"artifactId", child.artifact}, {"version", child.version}, {"packaging", child.packaging}} {
		if fld.val == "" {
			diags = append(diags, diag.Diagnostic{File: child.path, Line: 1, Col: 1, Code: codeCoords,
				Message: fmt.Sprintf("缺少坐标字段 %s（坐标不从 parent 继承，S8 §3.3）", fld.name)})
		}
	}
	if len(diags) > 0 {
		return nil, diags, nil
	}

	// 3. 合并（根 → 子）：properties 子覆盖父；deps/build/config 同理
	rootToChild := make([]*fileData, len(chainFiles))
	for i := range chainFiles {
		rootToChild[len(chainFiles)-1-i] = chainFiles[i]
	}
	rawProps := map[string]string{}
	for _, fd := range rootToChild {
		for k, v := range fd.props {
			rawProps[k] = v
		}
	}
	// 内置变量（只读）
	builtins := map[string]string{
		"project.groupId":    child.groupID,
		"project.artifactId": child.artifact,
		"project.version":    child.version,
		"project.basedir":    filepath.Dir(child.path),
		"xnull.version":      opts.ToolchainVersion,
	}

	// 4. profile 激活（父的 profiles 不继承）
	active, pdiags := activeProfiles(child, opts)
	diags = append(diags, pdiags...)
	if len(diags) > 0 {
		return nil, diags, nil
	}

	// 5. 合并 profile 覆盖（profile 之间同键冲突 → 失败）
	profProps := map[string]string{}
	profDeps := map[string]string{}
	profBuild := map[string]string{}
	profConfig := map[string]string{}
	origin := map[string]string{}
	conflict := func(kind, key, id string) {
		if prev, ok := origin[kind+"\x00"+key]; ok && prev != id {
			diags = append(diags, diag.Diagnostic{File: child.path, Line: 1, Col: 1, Code: codeProfile,
				Message: fmt.Sprintf("profile %s 与 %s 同时修改 %s %q（不允许静默取后者，S8 §3.8）", prev, id, kind, key)})
		}
		origin[kind+"\x00"+key] = id
	}
	for _, p := range active {
		for k, v := range p.properties {
			conflict("properties", k, p.id)
			profProps[k] = v
		}
		for k, v := range p.deps {
			conflict("dependencies", k, p.id)
			profDeps[k] = v
		}
		for k, v := range p.build {
			conflict("build", k, p.id)
			profBuild[k] = v
		}
		for k, v := range p.config {
			conflict("configuration", k, p.id)
			profConfig[k] = v
		}
	}
	if len(diags) > 0 {
		return nil, diags, nil
	}
	for k, v := range profProps {
		rawProps[k] = v
	}

	res := &Resolved{
		GroupID: child.groupID, ArtifactID: child.artifact,
		Version: child.version, Packaging: child.packaging,
		Properties: map[string]string{}, Dependencies: map[string]string{},
		Build: map[string]string{}, Configuration: map[string]string{},
		Managed: map[string]string{},
	}
	for _, p := range active {
		res.ActiveProfiles = append(res.ActiveProfiles, p.id)
	}
	sort.Strings(res.ActiveProfiles)
	for _, fd := range rootToChild {
		res.Chain = append(res.Chain, fd.path)
		for coord, m := range fd.managed {
			res.Managed[coord] = m.version
		}
		res.Plugins = append(res.Plugins, fd.plugins...)
	}

	// 6. 变量替换（单次；查找用未替换的原始表）
	lookup := func(name string) (string, bool) {
		if v, ok := builtins[name]; ok {
			return v, true
		}
		v, ok := rawProps[name]
		return v, ok
	}
	subst := func(where string, pos xpd.Pos, v string) (string, bool) {
		if !strings.Contains(v, "${") {
			return v, true
		}
		var b strings.Builder
		rest := v
		for {
			i := strings.Index(rest, "${")
			if i < 0 {
				b.WriteString(rest)
				break
			}
			j := strings.Index(rest[i:], "}")
			if j < 0 {
				diags = append(diags, diag.Diagnostic{File: child.path, Line: pos.Line, Col: pos.Col, Code: codeUnresolvedVar,
					Message: fmt.Sprintf("%s：变量未闭合 %q（S8 §3.4）", where, rest[i:])})
				return "", false
			}
			name := rest[i+2 : i+j]
			val, ok := lookup(name)
			if !ok {
				diags = append(diags, diag.Diagnostic{File: child.path, Line: pos.Line, Col: pos.Col, Code: codeUnresolvedVar,
					Message: fmt.Sprintf("%s：未解析变量 ${%s}（S8 §3.4）", where, name)})
				return "", false
			}
			b.WriteString(rest[:i])
			b.WriteString(val)
			rest = rest[i+j+1:]
		}
		return b.String(), true
	}

	for name := range rawProps {
		v, ok := subst("properties."+name, posOf(child, name), rawProps[name])
		if !ok {
			continue
		}
		res.Properties[name] = v
	}
	// 枚举字段不得变量化（packaging/scope/phase/kind）
	if strings.Contains(child.packaging, "${") {
		diags = append(diags, diag.Diagnostic{File: child.path, Line: 1, Col: 1, Code: codeEnumVar,
			Message: "packaging 是枚举字段，不得使用变量（S8 §3.4）"})
	}
	for _, fd := range rootToChild {
		for coord, ver := range fd.deps {
			v, ok := subst("dependencies."+coord, xpd.Pos{Line: 1, Col: 1}, ver)
			if ok && v != "" {
				res.Dependencies[coord] = v
			} else if ok {
				res.Dependencies[coord] = ""
			}
		}
		for k, v := range fd.build {
			if s, ok := subst("build."+k, xpd.Pos{Line: 1, Col: 1}, v); ok {
				res.Build[k] = s
			}
		}
		for k, v := range fd.config {
			if s, ok := subst("configuration."+k, xpd.Pos{Line: 1, Col: 1}, v); ok {
				res.Configuration[k] = s
			}
		}
	}
	for coord, ver := range profDeps {
		if v, ok := subst("dependencies."+coord, xpd.Pos{Line: 1, Col: 1}, ver); ok {
			res.Dependencies[coord] = v
		}
	}
	for k, v := range profBuild {
		if s, ok := subst("build."+k, xpd.Pos{Line: 1, Col: 1}, v); ok {
			res.Build[k] = s
		}
	}
	for k, v := range profConfig {
		if s, ok := subst("configuration."+k, xpd.Pos{Line: 1, Col: 1}, v); ok {
			res.Configuration[k] = s
		}
	}
	if len(diags) > 0 {
		return nil, diags, nil
	}
	return res, nil, nil
}

func posOf(fd *fileData, key string) xpd.Pos { return xpd.Pos{Line: 1, Col: 1} }

// activeProfiles 计算 -P 与 platform 的并集；未知 -P、不可覆盖段一律报 XPD-309。
func activeProfiles(fd *fileData, opts Options) ([]profileData, []diag.Diagnostic) {
	byID := map[string]profileData{}
	for _, p := range fd.profiles {
		byID[p.id] = p
	}
	var diags []diag.Diagnostic
	want := map[string]bool{}
	for _, id := range opts.Profiles {
		if _, ok := byID[id]; !ok {
			diags = append(diags, diag.Diagnostic{File: fd.path, Line: 1, Col: 1, Code: codeProfile,
				Message: fmt.Sprintf("-P 指定的 profile %q 未在清单中声明（S8 §3.8）", id)})
			continue
		}
		want[id] = true
	}
	if opts.Platform != "" {
		for _, p := range fd.profiles {
			if p.platform != "" && p.platform == opts.Platform {
				want[p.id] = true
			}
		}
	}
	var ids []string
	for id := range want {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	var out []profileData
	for _, id := range ids {
		out = append(out, byID[id])
	}
	return out, diags
}

// parseFile 解析单个清单并提取本节需要的字段（不做变量替换）。
func parseFile(path string) (*fileData, []diag.Diagnostic, error) {
	src, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil, nil
		}
		return nil, nil, err
	}
	f, sdiags := xpd.Parse(path, string(src))
	if len(sdiags) > 0 {
		return nil, sdiags, nil
	}
	if vdiags := validateSchema(path, f); len(vdiags) > 0 {
		return nil, vdiags, nil
	}
	proj := f.Find("project")
	if proj == nil {
		return nil, []diag.Diagnostic{{File: path, Line: 1, Col: 1, Code: codeCoords, Message: "清单缺少 project 块（S8 §3.2）"}}, nil
	}
	fd := &fileData{path: path, props: map[string]string{}, deps: map[string]string{},
		build: map[string]string{}, config: map[string]string{}}
	diags := []diag.Diagnostic{}
	for _, n := range proj.Children {
		switch node := n.(type) {
		case *xpd.Field:
			switch node.Name {
			case "groupId":
				fd.groupID = node.Value.Text
			case "artifactId":
				fd.artifact = node.Value.Text
			case "version":
				fd.version = node.Value.Text
			case "packaging":
				fd.packaging = node.Value.Text
			}
		case *xpd.Block:
			switch node.Name {
			case "parent":
				ref := &parentRef{pos: node.Pos}
				for _, c := range node.Children {
					fld, ok := c.(*xpd.Field)
					if !ok {
						continue
					}
					switch fld.Name {
					case "groupId":
						ref.groupID = fld.Value.Text
					case "artifactId":
						ref.artifactID = fld.Value.Text
					case "version":
						ref.version = fld.Value.Text
					case "relativePath":
						ref.relativePath = fld.Value.Text
					}
				}
				fd.parent = ref
			case "properties":
				for _, c := range node.Children {
					if fld, ok := c.(*xpd.Field); ok {
						fd.props[fld.Name] = fld.Value.Raw()
						if fld.Value.Kind == xpd.StringValue || fld.Value.Kind == xpd.BareValue {
							fd.props[fld.Name] = fld.Value.Text
						}
					}
				}
			case "dependencies":
				for _, c := range node.Children {
					dep, ok := c.(*xpd.Block)
					if !ok || dep.Name != "dependency" || len(dep.Args) == 0 {
						continue
					}
					coord := dep.Args[0].Text
					ver := ""
					for _, dc := range dep.Children {
						if fld, ok := dc.(*xpd.Field); ok && fld.Name == "version" {
							ver = fld.Value.Text
						}
					}
					fd.deps[coord] = ver
				}
			case "build":
				for _, c := range node.Children {
					if fld, ok := c.(*xpd.Field); ok {
						fd.build[fld.Name] = fld.Value.Raw()
						if fld.Value.Kind == xpd.StringValue || fld.Value.Kind == xpd.BareValue {
							fd.build[fld.Name] = fld.Value.Text
						}
						continue
					}
					if plugins, ok := c.(*xpd.Block); ok && plugins.Name == "plugins" {
						for _, pc := range plugins.Children {
							pb, ok := pc.(*xpd.Block)
							if !ok || pb.Name != "plugin" || len(pb.Args) == 0 {
								continue
							}
							ref := PluginRef{Coordinate: pb.Args[0].Text, Config: map[string]string{}}
							if len(pb.Args) > 1 {
								ref.Version = pb.Args[1].Text
							}
							for _, pcc := range pb.Children {
								switch pn := pcc.(type) {
								case *xpd.Field:
									switch pn.Name {
									case "version":
										ref.Version = pn.Value.Text
									case "phase":
										ref.Phase = pn.Value.Text
									case "goal":
										ref.Goal = pn.Value.Text
									}
								case *xpd.Block:
									if pn.Name == "configuration" {
										for _, cc := range pn.Children {
											if fld, ok := cc.(*xpd.Field); ok {
												ref.Config[fld.Name] = fld.Value.Text
											}
										}
									}
								}
							}
							fd.plugins = append(fd.plugins, ref)
						}
					}
				}
			case "configuration":
				for _, c := range node.Children {
					if fld, ok := c.(*xpd.Field); ok {
						fd.config[fld.Name] = fld.Value.Text
					}
				}
			case "dependencyManagement":
				seen := map[string]bool{}
				for _, c := range node.Children {
					deps, ok := c.(*xpd.Block)
					if !ok || deps.Name != "dependencies" {
						continue
					}
					for _, dc := range deps.Children {
						dep, ok := dc.(*xpd.Block)
						if !ok || dep.Name != "dependency" || len(dep.Args) == 0 {
							continue
						}
						coord := dep.Args[0].Text
						if seen[coord] {
							diags = append(diags, diag.Diagnostic{File: path, Line: dep.Pos.Line, Col: dep.Pos.Col,
								Code: codeCoordsDup, Message: fmt.Sprintf("dependencyManagement 坐标重复：%s（S8 §3.5）", coord)})
						}
						seen[coord] = true
						ver := ""
						for _, f := range dep.Children {
							fld, ok := f.(*xpd.Field)
							if !ok {
								continue
							}
							switch fld.Name {
							case "version":
								ver = fld.Value.Text
							case "scope", "optional":
								diags = append(diags, diag.Diagnostic{File: path, Line: fld.Pos.Line, Col: fld.Pos.Col,
									Code: codeManagedField, Message: fmt.Sprintf("dependencyManagement 不得声明 %s（S8 §3.5）：%s", fld.Name, coord)})
							}
						}
						if fd.managed == nil {
							fd.managed = map[string]managedEntry{}
						}
						fd.managed[coord] = managedEntry{version: ver}
					}
				}
			case "profiles":
				for _, c := range node.Children {
					pb, ok := c.(*xpd.Block)
					if !ok || pb.Name != "profile" || len(pb.Args) == 0 {
						continue
					}
					p := profileData{id: pb.Args[0].Text, properties: map[string]string{},
						deps: map[string]string{}, build: map[string]string{}, config: map[string]string{}}
					for _, pc := range pb.Children {
						switch child := pc.(type) {
						case *xpd.Field:
							// 不可覆盖字段 → 失败
							switch child.Name {
							case "groupId", "artifactId", "version", "packaging":
								diags = append(diags, diag.Diagnostic{File: path, Line: child.Pos.Line, Col: child.Pos.Col,
									Code: codeProfile, Message: fmt.Sprintf("profile %s 不得覆盖 %s（S8 §3.8）", p.id, child.Name)})
							}
						case *xpd.Block:
							switch child.Name {
							case "activation":
								for _, ac := range child.Children {
									if fld, ok := ac.(*xpd.Field); ok && fld.Name == "platform" {
										p.platform = fld.Value.Text
									}
								}
							case "properties":
								for _, ac := range child.Children {
									if fld, ok := ac.(*xpd.Field); ok {
										p.properties[fld.Name] = fld.Value.Text
									}
								}
							case "dependencies":
								for _, ac := range child.Children {
									dep, ok := ac.(*xpd.Block)
									if !ok || dep.Name != "dependency" || len(dep.Args) == 0 {
										continue
									}
									ver := ""
									for _, dc := range dep.Children {
										if fld, ok := dc.(*xpd.Field); ok && fld.Name == "version" {
											ver = fld.Value.Text
										}
									}
									p.deps[dep.Args[0].Text] = ver
								}
							case "build":
								for _, ac := range child.Children {
									if fld, ok := ac.(*xpd.Field); ok {
										p.build[fld.Name] = fld.Value.Text
									}
								}
							case "configuration":
								for _, ac := range child.Children {
									if fld, ok := ac.(*xpd.Field); ok {
										p.config[fld.Name] = fld.Value.Text
									}
								}
							case "parent", "modules", "repositories":
								diags = append(diags, diag.Diagnostic{File: path, Line: child.Pos.Line, Col: child.Pos.Col,
									Code: codeProfile, Message: fmt.Sprintf("profile %s 不得覆盖段落 %s（S8 §3.8）", p.id, child.Name)})
							}
						}
					}
					fd.profiles = append(fd.profiles, p)
				}
			}
		}
	}
	return fd, diags, nil
}
