// Package plugin 实现 S8 §5.5 构建期插件的合同面：`.xplugin` 元数据校验、
// 清单声明一致性（phase/goal/configKeys）、执行策略（target 外写拒绝、禁网、非零退出）。
// 诊断码限定 XPD-5xx。
package plugin

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xpd"
)

const (
	codePhase    = "XPD-501" // phase/goal/configKeys/版本形态非法
	codeWriteOut = "XPD-502" // target 之外写
	codeExit     = "XPD-503" // 插件非零退出
	codeMeta     = "XPD-504" // .xplugin 缺失或字段不符
	codeNetwork  = "XPD-505" // 网络访问（或无法禁网时拒绝执行）
)

// lifecycle 是固定的 5 个阶段（不得新增）。
var lifecycle = map[string]bool{
	"validate": true, "compile": true, "test": true, "package": true, "install": true,
}

// Goal 是插件元数据声明的一个 goal。
type Goal struct {
	Name       string
	Phase      string
	ConfigKeys []string
}

// Metadata 是 `.xplugin` 的内存形态。
type Metadata struct {
	GroupID          string
	ArtifactID       string
	Version          string
	ToolchainVersion string
	Goals            map[string]Goal
}

// Decl 是工程清单中的一条插件声明。
type Decl struct {
	Coordinate string // groupId:artifactId
	Version    string
	Phase      string
	Goal       string
	Config     map[string]string
}

// LoadMetadata 读取并校验 `.xplugin`（缺失/字段不全 → XPD-504，phase 非法 → XPD-501）。
func LoadMetadata(path string) (*Metadata, []diag.Diagnostic, error) {
	src, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, []diag.Diagnostic{{File: path, Line: 1, Col: 1, Code: codeMeta,
				Message: "插件缺少 .xplugin 元数据（S8 §5.5）"}}, nil
		}
		return nil, nil, err
	}
	f, sdiags := xpd.Parse(path, string(src))
	if len(sdiags) > 0 {
		return nil, sdiags, nil
	}
	root := f.Find("plugin")
	if root == nil {
		return nil, []diag.Diagnostic{{File: path, Line: 1, Col: 1, Code: codeMeta,
			Message: ".xplugin 缺少 plugin 块（S8 §5.5）"}}, nil
	}
	md := &Metadata{Goals: map[string]Goal{}}
	var ds []diag.Diagnostic
	for _, n := range root.Children {
		switch node := n.(type) {
		case *xpd.Field:
			switch node.Name {
			case "groupId":
				md.GroupID = node.Value.Text
			case "artifactId":
				md.ArtifactID = node.Value.Text
			case "version":
				md.Version = node.Value.Text
			case "toolchainVersion":
				md.ToolchainVersion = node.Value.Text
			}
		case *xpd.Block:
			if node.Name != "goals" {
				ds = append(ds, diag.Diagnostic{File: path, Line: node.Pos.Line, Col: node.Pos.Col, Code: codeMeta,
					Message: fmt.Sprintf(".xplugin 未知段落 %q（S8 §5.5）", node.Name)})
				continue
			}
			for _, g := range node.Children {
				gb, ok := g.(*xpd.Block)
				if !ok || gb.Name != "goal" || len(gb.Args) == 0 {
					continue
				}
				goal := Goal{Name: gb.Args[0].Text}
				for _, gc := range gb.Children {
					fld, ok := gc.(*xpd.Field)
					if !ok {
						continue
					}
					switch fld.Name {
					case "phase":
						goal.Phase = fld.Value.Text
					case "configKeys":
						if fld.Value.Kind != xpd.ListValue {
							ds = append(ds, diag.Diagnostic{File: path, Line: fld.Pos.Line, Col: fld.Pos.Col, Code: codeMeta,
								Message: fmt.Sprintf("goal %s 的 configKeys 必须是列表（S8 §5.5）", goal.Name)})
							continue
						}
						for _, e := range fld.Value.Elems {
							goal.ConfigKeys = append(goal.ConfigKeys, e.Text)
						}
					}
				}
				if goal.Phase == "" {
					ds = append(ds, diag.Diagnostic{File: path, Line: gb.Pos.Line, Col: gb.Pos.Col, Code: codeMeta,
						Message: fmt.Sprintf("goal %s 缺少 phase 字段（S8 §5.5）", goal.Name)})
				} else if !lifecycle[goal.Phase] {
					ds = append(ds, diag.Diagnostic{File: path, Line: gb.Pos.Line, Col: gb.Pos.Col, Code: codePhase,
						Message: fmt.Sprintf("goal %s 的 phase %q 非法（只允许 validate/compile/test/package/install，S8 §5.5）", goal.Name, goal.Phase)})
				}
				md.Goals[goal.Name] = goal
			}
		}
	}
	for _, missing := range []struct {
		name string
		val  string
	}{{"groupId", md.GroupID}, {"artifactId", md.ArtifactID}, {"version", md.Version}, {"toolchainVersion", md.ToolchainVersion}} {
		if missing.val == "" {
			ds = append(ds, diag.Diagnostic{File: path, Line: 1, Col: 1, Code: codeMeta,
				Message: fmt.Sprintf(".xplugin 缺少字段 %s（S8 §5.5）", missing.name)})
		}
	}
	if len(md.Goals) == 0 {
		ds = append(ds, diag.Diagnostic{File: path, Line: 1, Col: 1, Code: codeMeta,
			Message: ".xplugin 未声明任何 goal（S8 §5.5）"})
	}
	if len(ds) > 0 {
		return nil, ds, nil
	}
	return md, nil, nil
}

// Validate 校验清单声明与元数据一致（坐标/版本/phase/goal/configKeys/工具链主版本）。
func Validate(md *Metadata, decl Decl, toolchainVersion string) []diag.Diagnostic {
	var ds []diag.Diagnostic
	want := md.GroupID + ":" + md.ArtifactID
	if decl.Coordinate != want {
		ds = append(ds, diag.Diagnostic{File: "xnull.project", Line: 1, Col: 1, Code: codeMeta,
			Message: fmt.Sprintf("插件坐标不符：清单 %s，.xplugin %s（S8 §5.5）", decl.Coordinate, want)})
	}
	if decl.Version != md.Version {
		ds = append(ds, diag.Diagnostic{File: "xnull.project", Line: 1, Col: 1, Code: codeMeta,
			Message: fmt.Sprintf("插件版本不符：清单 %s，.xplugin %s（S8 §5.5）", decl.Version, md.Version)})
	}
	if !exactVersion(decl.Version) {
		ds = append(ds, diag.Diagnostic{File: "xnull.project", Line: 1, Col: 1, Code: codePhase,
			Message: fmt.Sprintf("插件版本必须是精确版本（S8 §4.3）：%s", decl.Version)})
	}
	if !lifecycle[decl.Phase] {
		ds = append(ds, diag.Diagnostic{File: "xnull.project", Line: 1, Col: 1, Code: codePhase,
			Message: fmt.Sprintf("插件 phase %q 非法（S8 §5.5）", decl.Phase)})
	}
	goal, ok := md.Goals[decl.Goal]
	if !ok {
		ds = append(ds, diag.Diagnostic{File: "xnull.project", Line: 1, Col: 1, Code: codePhase,
			Message: fmt.Sprintf("插件未声明 goal %q（S8 §5.5）", decl.Goal)})
	} else if decl.Phase != "" && goal.Phase != decl.Phase {
		ds = append(ds, diag.Diagnostic{File: "xnull.project", Line: 1, Col: 1, Code: codePhase,
			Message: fmt.Sprintf("goal %s 的 phase 为 %s，清单写 %s（S8 §5.5）", decl.Goal, goal.Phase, decl.Phase)})
	}
	allowed := map[string]bool{}
	if ok {
		for _, k := range goal.ConfigKeys {
			allowed[k] = true
		}
	}
	keys := make([]string, 0, len(decl.Config))
	for k := range decl.Config {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if ok && !allowed[k] {
			ds = append(ds, diag.Diagnostic{File: "xnull.project", Line: 1, Col: 1, Code: codePhase,
				Message: fmt.Sprintf("插件 configuration 键 %q 未在 goal %s 的 configKeys 中声明（S8 §5.5）", k, decl.Goal)})
		}
	}
	if major(md.ToolchainVersion) != major(toolchainVersion) && major(toolchainVersion) != "" {
		ds = append(ds, diag.Diagnostic{File: "xnull.project", Line: 1, Col: 1, Code: codeMeta,
			Message: fmt.Sprintf("插件要求工具链 %s，当前 %s（主版本须一致，S8 §5.5）", md.ToolchainVersion, toolchainVersion)})
	}
	return ds
}

func major(v string) string {
	if i := strings.Index(v, "."); i > 0 {
		return v[:i]
	}
	return v
}

func exactVersion(v string) bool {
	parts := strings.SplitN(v, ".", 3)
	if len(parts) != 3 {
		return false
	}
	for _, p := range parts {
		if p == "" {
			return false
		}
	}
	for _, bad := range []string{"*", "[", "]", "(", ")", ",", "SNAPSHOT", "LATEST", "RELEASE"} {
		if strings.Contains(strings.ToUpper(v), bad) {
			return false
		}
	}
	return true
}

// RunSpec 是一次插件执行请求。
type RunSpec struct {
	ProjectDir string
	TargetDir  string
	Command    []string
	Env        map[string]string // 仅白名单（XNULL_REPO 等），不继承宿主环境
	NoSandbox  bool              // 测试/无沙箱平台：拒绝执行（不得裸跑）
	Stdout     io.Writer
	Stderr     io.Writer
}

// Run 在受限环境执行插件：禁网（sandbox-exec）、只写 target、非零退出即失败。
func Run(spec RunSpec) []diag.Diagnostic {
	report := func(code, msg string) []diag.Diagnostic {
		return []diag.Diagnostic{{File: spec.ProjectDir, Line: 1, Col: 1, Code: code, Message: msg}}
	}
	sandbox, err := exec.LookPath("sandbox-exec")
	if spec.NoSandbox || err != nil {
		return report(codeNetwork, "无法启用网络隔离（sandbox-exec 不可用）：拒绝执行插件（S8 §5.5 禁网）")
	}
	before, err := snapshot(spec.ProjectDir, spec.TargetDir)
	if err != nil {
		return report(codeMeta, fmt.Sprintf("扫描工程目录失败：%v", err))
	}
	args := []string{"-p", "(version 1)(allow default)(deny network*)", "--"}
	args = append(args, spec.Command...)
	cmd := exec.Command(sandbox, args...)
	cmd.Dir = spec.ProjectDir
	var env []string
	for k, v := range spec.Env {
		env = append(env, k+"="+v)
	}
	cmd.Env = env
	if spec.Stdout != nil {
		cmd.Stdout = spec.Stdout
	}
	if spec.Stderr != nil {
		cmd.Stderr = spec.Stderr
	}
	runErr := cmd.Run()
	after, err := snapshot(spec.ProjectDir, spec.TargetDir)
	if err != nil {
		return report(codeMeta, fmt.Sprintf("扫描工程目录失败：%v", err))
	}
	var ds []diag.Diagnostic
	for path, h := range after {
		if old, ok := before[path]; !ok || old != h {
			ds = append(ds, diag.Diagnostic{File: filepath.Join(spec.ProjectDir, path), Line: 1, Col: 1, Code: codeWriteOut,
				Message: fmt.Sprintf("插件写了 target/ 之外的文件：%s（S8 §5.5）", path)})
		}
	}
	for path := range before {
		if _, ok := after[path]; !ok {
			ds = append(ds, diag.Diagnostic{File: filepath.Join(spec.ProjectDir, path), Line: 1, Col: 1, Code: codeWriteOut,
				Message: fmt.Sprintf("插件删除了 target/ 之外的文件：%s（S8 §5.5）", path)})
		}
	}
	sort.Slice(ds, func(i, j int) bool { return ds[i].File < ds[j].File })
	if runErr != nil {
		ds = append(ds, diag.Diagnostic{File: spec.ProjectDir, Line: 1, Col: 1, Code: codeExit,
			Message: fmt.Sprintf("插件非零退出：%v（S8 §5.5）", runErr)})
	}
	return ds
}

// snapshot 记录 target 之外的文件摘要（用于越界写检测）。
func snapshot(projectDir, targetDir string) (map[string]string, error) {
	out := map[string]string{}
	targetAbs, _ := filepath.Abs(targetDir)
	err := filepath.WalkDir(projectDir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			name := d.Name()
			if name == ".git" {
				return filepath.SkipDir
			}
			if abs, _ := filepath.Abs(path); abs == targetAbs {
				return filepath.SkipDir
			}
			return nil
		}
		rel, _ := filepath.Rel(projectDir, path)
		data, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		sum := sha256.Sum256(data)
		out[rel] = hex.EncodeToString(sum[:])
		return nil
	})
	return out, err
}
