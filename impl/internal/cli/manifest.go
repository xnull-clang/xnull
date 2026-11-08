// manifest.go：S8-04 清单模式生命周期（validate→compile→test→package→install）。
package cli

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"xnull.dev/xnull/internal/codegen"
	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/exitcode"
	"xnull.dev/xnull/internal/xfront"
	"xnull.dev/xnull/internal/xpd"
)

const manifestFile = "xnull.project"

// buildSpec 是 build 段中 S8-04 消费的字段（S8 §5.2）。
type buildSpec struct {
	Mode         string
	Warnings     string
	SourceRoot   string
	TestRoot     string
	EntryFile    string
	EntryPackage string
}

// projectManifest 是清单模式的最小语义视图（S8-01 负责完整 schema）。
type projectManifest struct {
	Root       string
	Path       string
	Raw        []byte
	GroupID    string
	ArtifactID string
	Version    string
	Packaging  string
	Build      buildSpec
	Properties map[string]string
}

func manifestDiag(path string, p xpd.Pos, code, msg string) *diag.Diagnostic {
	return &diag.Diagnostic{File: path, Line: p.Line, Col: p.Col, Code: code, Message: msg}
}

func blockField(b *xpd.Block, name string) (*xpd.Field, *xpd.Field) {
	var first, dup *xpd.Field
	if b == nil {
		return nil, nil
	}
	for _, n := range b.Children {
		f, ok := n.(*xpd.Field)
		if !ok || f.Name != name {
			continue
		}
		if first == nil {
			first = f
		} else if dup == nil {
			dup = f
		}
	}
	return first, dup
}

func childBlock(b *xpd.Block, name string) *xpd.Block {
	if b == nil {
		return nil
	}
	for _, n := range b.Children {
		if cb, ok := n.(*xpd.Block); ok && cb.Name == name {
			return cb
		}
	}
	return nil
}

func valueText(v xpd.Value) string {
	switch v.Kind {
	case xpd.StringValue, xpd.BareValue:
		return v.Text
	default:
		return v.Raw()
	}
}

// loadProjectManifest 读取并校验 S8-04 所需清单字段。
func loadProjectManifest(root string) (*projectManifest, *diag.Diagnostic) {
	path := filepath.Join(root, manifestFile)
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, &diag.Diagnostic{File: "xnull", Line: 1, Col: 1, Code: codeManifestAbsent,
			Message: "找不到 xnull.project", Hint: "在进程内向上查找清单；确认当前目录属于某个工程"}
	}
	f, diags := xpd.Parse(manifestFile, string(raw))
	if len(diags) > 0 {
		return nil, &diags[0]
	}
	m := &projectManifest{Root: root, Path: path, Raw: raw, Properties: map[string]string{}}
	proj := f.Find("project")
	if proj == nil {
		return nil, manifestDiag(manifestFile, xpd.Pos{Line: 1, Col: 1}, "XPD-201", "清单缺少 project 块")
	}
	coords := []struct {
		name string
		dst  *string
	}{
		{"groupId", &m.GroupID}, {"artifactId", &m.ArtifactID},
		{"version", &m.Version}, {"packaging", &m.Packaging},
	}
	for _, c := range coords {
		fld, dup := blockField(proj, c.name)
		if dup != nil {
			return nil, manifestDiag(manifestFile, dup.Pos, "XPD-201", "字段 "+c.name+" 重复声明")
		}
		if fld == nil || strings.TrimSpace(valueText(fld.Value)) == "" {
			return nil, manifestDiag(manifestFile, proj.Pos, "XPD-301", "缺少坐标字段 "+c.name)
		}
		*c.dst = valueText(fld.Value)
	}
	switch m.Packaging {
	case "app", "library", "pom", "starter":
	default:
		return nil, manifestDiag(manifestFile, proj.Pos, "XPD-201", "packaging 非法："+m.Packaging+"（限 app/library/pom/starter）")
	}
	if props := childBlock(proj, "properties"); props != nil {
		for _, n := range props.Children {
			fld, ok := n.(*xpd.Field)
			if !ok {
				continue
			}
			m.Properties[fld.Name] = valueText(fld.Value)
		}
	}
	m.Build = buildSpec{Mode: "debug", Warnings: "default", SourceRoot: "src/main/x", TestRoot: "src/test/x"}
	build := childBlock(proj, "build")
	if build != nil {
		if d := parseBuildSpec(m, build); d != nil {
			return nil, d
		}
	}
	if d := validateBuildSpec(m); d != nil {
		return nil, d
	}
	return m, nil
}

var buildFieldNames = map[string]bool{
	"mode": true, "warnings": true, "sourceRoot": true, "testRoot": true,
	"entryFile": true, "entryPackage": true, "resources": true, "plugins": true,
}

func parseBuildSpec(m *projectManifest, build *xpd.Block) *diag.Diagnostic {
	type dst struct {
		name string
		val  *string
	}
	fields := []dst{
		{"mode", &m.Build.Mode}, {"warnings", &m.Build.Warnings},
		{"sourceRoot", &m.Build.SourceRoot}, {"testRoot", &m.Build.TestRoot},
		{"entryFile", &m.Build.EntryFile}, {"entryPackage", &m.Build.EntryPackage},
	}
	seen := map[string]bool{}
	for _, n := range build.Children {
		switch it := n.(type) {
		case *xpd.Field:
			if !buildFieldNames[it.Name] {
				return manifestDiag(manifestFile, it.Pos, "XPD-201", "未知 build 字段 "+it.Name)
			}
			if seen[it.Name] {
				return manifestDiag(manifestFile, it.Pos, "XPD-201", "build 字段 "+it.Name+" 重复声明")
			}
			seen[it.Name] = true
			for _, f := range fields {
				if f.name == it.Name {
					*f.val = valueText(it.Value)
				}
			}
		case *xpd.Block:
			if it.Name != "resources" && it.Name != "plugins" {
				return manifestDiag(manifestFile, it.Pos, "XPD-201", "未知 build 段 "+it.Name)
			}
		}
	}
	return nil
}

func validateBuildSpec(m *projectManifest) *diag.Diagnostic {
	pos := xpd.Pos{Line: 1, Col: 1}
	switch m.Build.Mode {
	case "debug", "release", "size":
	default:
		return manifestDiag(manifestFile, pos, "XPD-201", "build.mode 非法："+m.Build.Mode+"（限 debug/release/size）")
	}
	switch m.Build.Warnings {
	case "default", "strict":
	default:
		return manifestDiag(manifestFile, pos, "XPD-201", "build.warnings 非法："+m.Build.Warnings+"（限 default/strict）")
	}
	for _, p := range []struct {
		name string
		val  string
	}{{"sourceRoot", m.Build.SourceRoot}, {"testRoot", m.Build.TestRoot}} {
		clean := filepath.ToSlash(filepath.Clean(p.val))
		if clean == "target" || strings.HasPrefix(clean, "target/") {
			return manifestDiag(manifestFile, pos, "XPD-201", "build."+p.name+" 不得等于或包含 target/")
		}
		if filepath.IsAbs(p.val) {
			return manifestDiag(manifestFile, pos, "XPD-201", "build."+p.name+" 必须是工程内相对路径")
		}
	}
	if m.Packaging != "app" {
		if m.Build.EntryFile != "" || m.Build.EntryPackage != "" {
			return manifestDiag(manifestFile, pos, "XPD-201", "非 app 工程不得声明 entryFile/entryPackage（S8 §5.2）")
		}
	}
	return nil
}

// resolveEntry 按 S8 §5.4 解析入口文件并校验 main。
func resolveEntry(m *projectManifest) (string, *diag.Diagnostic) {
	if m.Packaging != "app" {
		return "", manifestDiag(manifestFile, xpd.Pos{Line: 1, Col: 1}, "XPD-201", "当前构建仅支持 packaging=app（library/pom/starter 后续卡）")
	}
	rel := m.Build.EntryFile
	if rel == "" {
		rel = filepath.ToSlash(filepath.Join(m.Build.SourceRoot, "main.x"))
	}
	path := rel
	if !filepath.IsAbs(path) {
		path = filepath.Join(m.Root, filepath.FromSlash(rel))
	}
	if st, err := os.Stat(path); err != nil || st.IsDir() {
		return "", &diag.Diagnostic{File: rel, Line: 1, Col: 1, Code: "XPD-202", Message: "入口文件不存在：" + rel}
	}
	if m.Build.EntryPackage != "" {
		src, err := os.ReadFile(path)
		if err != nil {
			return "", &diag.Diagnostic{File: rel, Line: 1, Col: 1, Code: "XPD-202", Message: "入口文件不可读：" + rel}
		}
		u, pdiags := xfront.ParseUnit(path, string(src))
		if len(pdiags) == 0 && u != nil && u.Package != nil {
			got := strings.Join(u.Package.Name, ".")
			if got != m.Build.EntryPackage {
				return "", &diag.Diagnostic{File: rel, Line: 1, Col: 1, Code: "XPD-202",
					Message: fmt.Sprintf("入口文件 package %q 与 entryPackage %q 不匹配（S8 §5.4）", got, m.Build.EntryPackage)}
			}
		}
	}
	if d := checkEntry(path); d != nil {
		return "", d
	}
	return path, nil
}

// xmeta 生成 .xmeta（XPD）内容；字段顺序固定保证可复现（S8 §5.3）。
func (m *projectManifest) xmeta(lockSHA, inputsSHA string, integ *integrationState) string {
	platform := runtime.GOOS
	if platform == "darwin" {
		platform = "macos"
	}
	xdk := m.Properties["xdk-version"]
	lang := m.Properties["language-version"]
	toolchain := m.Properties["xnull.version"]
	if toolchain == "" {
		toolchain = Version
	}
	var b strings.Builder
	b.WriteString("xmeta {\n")
	fmt.Fprintf(&b, "  groupId          = %s\n", m.GroupID)
	fmt.Fprintf(&b, "  artifactId       = %s\n", m.ArtifactID)
	fmt.Fprintf(&b, "  version          = %s\n", m.Version)
	fmt.Fprintf(&b, "  packaging        = %s\n", m.Packaging)
	fmt.Fprintf(&b, "  platform         = %s\n", platform)
	fmt.Fprintf(&b, "  xdkVersion       = %s\n", fallback(xdk, "unknown"))
	fmt.Fprintf(&b, "  languageVersion  = %s\n", fallback(lang, "unknown"))
	fmt.Fprintf(&b, "  toolchainVersion = %s\n", toolchain)
	profiles, plugins := "[]", "[]"
	cfgSHA, resSHA, pluginSHA := "", "", ""
	if integ != nil {
		if len(integ.profiles) > 0 {
			profiles = "[" + strings.Join(integ.profiles, ", ") + "]"
		}
		if len(integ.plugins) > 0 {
			plugins = "[" + strings.Join(integ.plugins, ", ") + "]"
		}
		cfgSHA, resSHA, pluginSHA = integ.cfgDigest, integ.resDigest, integ.pluginDigest
	}
	fmt.Fprintf(&b, "  profiles         = %s\n", profiles)
	fmt.Fprintf(&b, "  plugins          = %s\n", plugins)
	fmt.Fprintf(&b, "  configSha256     = %s\n", cfgSHA)
	fmt.Fprintf(&b, "  resourcesSha256  = %s\n", resSHA)
	fmt.Fprintf(&b, "  pluginsSha256    = %s\n", pluginSHA)
	fmt.Fprintf(&b, "  lockSha256       = %s\n", lockSHA)
	fmt.Fprintf(&b, "  inputs           = %s\n", inputsSHA)
	b.WriteString("}\n")
	return b.String()
}

func fallback(v, def string) string {
	if strings.TrimSpace(v) == "" {
		return def
	}
	return v
}

func sha256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// hashInputs 汇总模型输入摘要：清单、入口源码、锁文件、工具链版本。
func hashInputs(parts ...[]byte) string {
	h := sha256.New()
	for _, p := range parts {
		h.Write(p)
		h.Write([]byte{0})
	}
	return hex.EncodeToString(h.Sum(nil))
}

// manifestPipeline 执行 5 阶段生命周期；返回产物路径与退出码。
type manifestPipeline struct {
	m       *projectManifest
	skip    map[string]bool
	entry   string
	rtDir   string
	out     string
	env     Env
	profile string
	integ   *integrationState
}

func (p *manifestPipeline) artifactPath() string {
	ext := ""
	if runtime.GOOS == "windows" {
		ext = ".exe"
	}
	return filepath.Join(p.m.Root, "target", p.m.ArtifactID+"-"+p.m.Version+ext)
}

func (p *manifestPipeline) compileTo(src, dst string) int {
	opts := codegen.Options{Mode: p.m.Build.Mode}
	if p.integ != nil && p.integ.resC != "" {
		opts.ResC = p.integ.resC
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		fmt.Fprintf(p.env.Stderr, "xnull: %v\n", err)
		return exitcode.BuildFail
	}
	return codegen.BuildWithOptions(src, dst, p.rtDir, opts, p.env.Stderr)
}

func (p *manifestPipeline) run(env Env) (string, int) {
	// validate
	entry, d := resolveEntry(p.m)
	if d != nil {
		fmt.Fprintln(env.Stderr, d.String())
		return "", exitcode.Usage
	}
	p.entry = entry

	// S8 集成：锁 → 配置 → 资源 → 插件（失败即停，诊断带 XPD 码与位置）。
	// 资源表在 compile 阶段作为 opts.ResC 传入。
	integ, ok := p.validateIntegrations(p.profile)
	if !ok {
		return "", exitcode.BuildFail
	}
	p.integ = integ

	// compile
	cache := filepath.Join(p.m.Root, "target", ".cache", p.m.ArtifactID+"-"+p.m.Version)
	if !p.skip["compile"] {
		if code := p.compileTo(entry, cache); code != 0 {
			return "", exitcode.BuildFail
		}
	}

	// test
	if !p.skip["test"] {
		testMain := filepath.Join(p.m.Root, filepath.FromSlash(p.m.Build.TestRoot), "main.x")
		if _, err := os.Stat(testMain); err == nil {
			tbin := filepath.Join(p.m.Root, "target", ".cache", "test-"+p.m.ArtifactID)
			if code := p.compileTo(testMain, tbin); code != 0 {
				return "", exitcode.BuildFail
			}
			cmd := exec.Command(tbin)
			cmd.Stdout = env.Stdout
			cmd.Stderr = env.Stderr
			if err := cmd.Run(); err != nil {
				return "", exitcode.BuildFail
			}
		}
	}

	// package
	final := p.artifactPath()
	if !p.skip["package"] {
		if err := os.MkdirAll(filepath.Dir(final), 0o755); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return "", exitcode.BuildFail
		}
		if err := copyFile(cache, final); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return "", exitcode.BuildFail
		}
		lock, _ := os.ReadFile(filepath.Join(p.m.Root, "xnull.lock"))
		entrySrc, _ := os.ReadFile(entry)
		resBytes := []byte{}
		if p.integ != nil {
			resBytes = []byte(p.integ.resDigest + p.integ.cfgDigest + p.integ.pluginDigest)
		}
		inputs := hashInputs(p.m.Raw, entrySrc, lock, []byte(Version), resBytes)
		meta := p.m.xmeta(sha256Hex(lock), inputs, p.integ)
		metaPath := final + ".xmeta"
		if err := os.WriteFile(metaPath, []byte(meta), 0o644); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return "", exitcode.BuildFail
		}
	}
	// install：1.x 可跳过；当前为本地空操作。
	return final, exitcode.Success
}

func copyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, 0o755)
}

// parseSkipStages 解析 --skip <stage> / --skip=<stage>。
func parseSkipStages(args []string) (map[string]bool, *diag.Diagnostic) {
	allowed := map[string]bool{"validate": true, "compile": true, "test": true, "package": true, "install": true}
	skip := map[string]bool{}
	for i := 0; i < len(args); i++ {
		a := args[i]
		var v string
		switch {
		case a == "--skip":
			if i+1 >= len(args) {
				return nil, &diag.Diagnostic{File: "xnull", Line: 1, Col: 1, Code: codeUnknownFlag, Message: "--skip 缺少阶段名"}
			}
			v = args[i+1]
			i++
		case strings.HasPrefix(a, "--skip="):
			v = strings.TrimPrefix(a, "--skip=")
		default:
			continue
		}
		if !allowed[v] {
			return nil, &diag.Diagnostic{File: "xnull", Line: 1, Col: 1, Code: codeUnknownFlag,
				Message: "--skip 阶段非法：" + v + "（限 validate/compile/test/package/install）"}
		}
		skip[v] = true
	}
	return skip, nil
}

func flagValue(args []string, name string) string {
	for i := 0; i < len(args); i++ {
		if args[i] == name && i+1 < len(args) {
			return args[i+1]
		}
		if strings.HasPrefix(args[i], name+"=") {
			return strings.TrimPrefix(args[i], name+"=")
		}
	}
	return ""
}

// manifestRuntimeDir 优先使用工程根的相对探测，再回落到进程 cwd。
func manifestRuntimeDir(root string) string {
	if v := os.Getenv("XNULL_RUNTIME"); v != "" {
		return v
	}
	cands := []string{
		filepath.Join(root, "impl", "runtime"),
		filepath.Join(root, "..", "impl", "runtime"),
		filepath.Join(root, "..", "..", "impl", "runtime"),
		filepath.Join(root, "..", "..", "runtime"),
		filepath.Join(root, "runtime"),
	}
	cands = append(cands, "impl/runtime", "../impl/runtime", "../../impl/runtime", "../../runtime", "runtime")
	for _, cand := range cands {
		if st, err := os.Stat(filepath.Join(cand, "rt.h")); err == nil && !st.IsDir() {
			return cand
		}
	}
	return ""
}

// buildManifest 是 `xnull build`（清单模式）入口。
func buildManifest(env Env, rest []string, dir string) (string, int) {
	root := findManifestRoot(dir)
	if root == "" {
		fmt.Fprintln(env.Stderr, (&diag.Diagnostic{File: "xnull", Line: 1, Col: 1, Code: codeManifestAbsent, Message: "找不到 xnull.project"}).String())
		return "", exitcode.Usage
	}
	m, d := loadProjectManifest(root)
	if d != nil {
		fmt.Fprintln(env.Stderr, d.String())
		return "", exitcode.Usage
	}
	skip, d := parseSkipStages(rest)
	if d != nil {
		fmt.Fprintln(env.Stderr, d.String())
		return "", exitcode.Usage
	}
	rt := manifestRuntimeDir(root)
	if v := flagValue(rest, "--runtime"); v != "" {
		rt = v
	}
	if rt == "" {
		fmt.Fprintln(env.Stderr, "xnull: 找不到运行时源码目录（rt.h）；用 --runtime 或 XNULL_RUNTIME 指定")
		return "", exitcode.Usage
	}
	p := &manifestPipeline{m: m, skip: skip, rtDir: rt, env: env, profile: flagValue(rest, "--profile")}
	return p.run(env)
}
