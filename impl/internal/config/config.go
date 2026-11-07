// Package config 实现 S8 §6 服务运行时配置：
//
//   - application.properties（层 2）与 application-<profile>.properties（层 3）加载；
//   - 五层覆盖（0 configuration / 1 builtin / 2 application / 3 profile /
//     4 白名单环境变量 / 5 命令行）；
//   - 严格键名、类型、必需键、未知键与疑似密钥校验（XPD-6xx）。
//
// 本包只负责“配置快照”的加载与校验，不读取清单；S8-02/04 把 configuration、
// profile id、packaging 与绑定代码声明的键表传给 Load。
package config

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"

	"xnull.dev/xnull/internal/diag"
)

// XPD-6xx 配置诊断码（S8 §6 / 附录 C 段位）。
const (
	CodeFormat          = "XPD-600" // 配置文件格式/编码错误
	CodeKeyInvalid      = "XPD-601" // 键名非法
	CodeDuplicateKey    = "XPD-602" // 同层重复键
	CodeUnknownKey      = "XPD-603" // 未知键
	CodeMissingRequired = "XPD-604" // 缺失必需键
	CodeTypeMismatch    = "XPD-605" // 值类型解析失败
	CodeSecretLiteral   = "XPD-606" // 疑似密钥写入配置
	CodeProfileMismatch = "XPD-607" // profile 文件名与清单不符
	CodeConfigPlacement = "XPD-608" // 非 app 工程出现配置文件
)

// Layer 是五层覆盖的来源层（S8 §6.4，低 → 高）。
type Layer int

const (
	LayerConfiguration Layer = 0
	LayerBuiltin       Layer = 1
	LayerApplication   Layer = 2
	LayerProfile       Layer = 3
	LayerEnv           Layer = 4
	LayerCLI           Layer = 5
)

func (l Layer) String() string {
	switch l {
	case LayerConfiguration:
		return "configuration"
	case LayerBuiltin:
		return "builtin"
	case LayerApplication:
		return "application"
	case LayerProfile:
		return "profile"
	case LayerEnv:
		return "env"
	case LayerCLI:
		return "cli"
	default:
		return "unknown"
	}
}

// Kind 是值类型（值一律按字符串读入，类型由绑定代码声明）。
type Kind int

const (
	KindString Kind = iota
	KindInt
	KindBool
	KindFloat
)

func (k Kind) String() string {
	switch k {
	case KindInt:
		return "Int"
	case KindBool:
		return "Bool"
	case KindFloat:
		return "Float"
	default:
		return "String"
	}
}

// KeySpec 是绑定代码声明的配置键。
type KeySpec struct {
	Kind     Kind
	Required bool
}

// Spec 是本次加载的配置合同。
type Spec struct {
	Keys         map[string]KeySpec
	Profiles     []string // 清单 profiles.profile 的 id 列表
	EnvWhitelist []string // configuration.envOverrides
}

// Options 是配置加载输入；ResourcesDir 是资源根（含 application*.properties）。
type Options struct {
	ResourcesDir  string
	Profile       string
	Packaging     string            // "app" 或其它；空按 app 处理
	Configuration map[string]string // 层 0（父 pom configuration）
	Builtin       map[string]string // 层 1（绑定代码/XDK 缺省）
	Environ       []string          // 层 4；nil = os.Environ()
	CLI           map[string]string // 层 5（已解析的 --key=value）
	Spec          Spec
	Audit         io.Writer // 命令行覆盖审计输出（可选）
}

// Origin 是最终值的来源（层 + 文件/命令行 + 行号）。
type Origin struct {
	Layer  Layer
	Source string
	Line   int
}

// Result 是合并后的配置快照。
type Result struct {
	Values  map[string]string
	Origins map[string]Origin
	Audit   []string
}

type valueEntry struct {
	value  string
	origin Origin
}

type loader struct {
	opts     Options
	entries  map[string]valueEntry
	diags    []diag.Diagnostic
	cliAudit []string
}

// Load 加载并校验服务配置；诊断非空时调用方应按启动失败处理。
func Load(opts Options) (*Result, []diag.Diagnostic) {
	l := &loader{opts: opts, entries: map[string]valueEntry{}}
	if opts.Packaging == "" {
		l.opts.Packaging = "app"
	}

	l.applyMap(LayerConfiguration, "configuration", opts.Configuration)
	l.applyMap(LayerBuiltin, "builtin", opts.Builtin)
	l.loadFiles()
	l.applyEnv()
	l.applyCLI()

	l.checkUnknown()
	l.checkRequired()
	l.checkTypes()
	l.sortDiags()

	res := &Result{
		Values:  make(map[string]string, len(l.entries)),
		Origins: make(map[string]Origin, len(l.entries)),
		Audit:   append([]string{}, l.auditLines()...),
	}
	for k, e := range l.entries {
		res.Values[k] = e.value
		res.Origins[k] = e.origin
	}
	return res, l.diags
}

func (l *loader) addDiag(source string, line int, code, msg string) {
	l.diags = append(l.diags, diag.Diagnostic{
		File: source, Line: line, Col: 1, Code: code, Message: msg,
	})
}

func (l *loader) applyMap(layer Layer, source string, m map[string]string) {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		l.applyValue(layer, source, 0, k, m[k])
	}
}

func (l *loader) applyValue(layer Layer, source string, line int, key, value string) {
	if !ValidKey(key) {
		l.addDiag(source, line, CodeKeyInvalid,
			fmt.Sprintf("配置键名非法（小写字母/数字/点/连字符，≤128，无连续/首尾点）：%s", key))
		return
	}
	if e, ok := l.entries[key]; ok && e.origin.Layer == layer {
		l.addDiag(source, line, CodeDuplicateKey,
			fmt.Sprintf("同层重复配置键：%s（层 %s，来源 %s）", key, layer, source))
		return
	}
	if (layer == LayerConfiguration || layer == LayerApplication || layer == LayerProfile) &&
		isSecretKey(key) && !isPlaceholder(value) {
		l.addDiag(source, line, CodeSecretLiteral,
			fmt.Sprintf("疑似密钥键 %s 不得写入配置（层 %s，来源 %s）；请走白名单环境变量",
				key, layer, source))
	}
	l.entries[key] = valueEntry{value: value, origin: Origin{Layer: layer, Source: source, Line: line}}
}

func (l *loader) loadFiles() {
	dir := l.opts.ResourcesDir
	if dir == "" {
		return
	}
	l.checkPlacement(dir)
	app := filepath.Join(dir, "application.properties")
	if fileExists(app) {
		if l.opts.Packaging != "app" {
			l.addDiag(app, 1, CodeConfigPlacement,
				fmt.Sprintf("非 app 工程不得包含配置文件：%s（packaging=%s）", app, l.opts.Packaging))
		} else {
			l.loadFile(LayerApplication, app)
		}
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, ent := range entries {
		if ent.IsDir() {
			continue
		}
		name := ent.Name()
		if !strings.HasPrefix(name, "application-") || !strings.HasSuffix(name, ".properties") {
			continue
		}
		profile := strings.TrimSuffix(strings.TrimPrefix(name, "application-"), ".properties")
		path := filepath.Join(dir, name)
		if profile == "" || !contains(l.opts.Spec.Profiles, profile) {
			l.addDiag(path, 1, CodeProfileMismatch,
				fmt.Sprintf("profile 文件名与清单 profiles 不符：%s（profile=%q）", path, profile))
			continue
		}
		if l.opts.Packaging != "app" {
			l.addDiag(path, 1, CodeConfigPlacement,
				fmt.Sprintf("非 app 工程不得包含配置文件：%s（packaging=%s）", path, l.opts.Packaging))
			continue
		}
		if l.opts.Profile == profile {
			l.loadFile(LayerProfile, path)
		}
	}
	if l.opts.Profile != "" && !contains(l.opts.Spec.Profiles, l.opts.Profile) {
		l.addDiag("--profile", 1, CodeProfileMismatch,
			fmt.Sprintf("profile %q 不在清单 profiles 中（可用：%s）",
				l.opts.Profile, strings.Join(l.opts.Spec.Profiles, ", ")))
	}
}

// checkPlacement：application*.properties 只允许位于资源根顶层（S8 §6.1）。
func (l *loader) checkPlacement(dir string) {
	_ = filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		name := d.Name()
		isConfig := name == "application.properties" ||
			(strings.HasPrefix(name, "application-") && strings.HasSuffix(name, ".properties"))
		if isConfig && filepath.Dir(path) != dir {
			l.addDiag(path, 1, CodeConfigPlacement,
				fmt.Sprintf("配置文件必须位于资源根顶层，不得放在子目录：%s", path))
		}
		return nil
	})
}

func (l *loader) loadFile(layer Layer, path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		l.addDiag(path, 1, CodeConfigPlacement, fmt.Sprintf("读取配置文件失败：%v", err))
		return
	}
	if !utf8.Valid(data) {
		l.addDiag(path, 1, CodeFormat, "配置文件不是合法 UTF-8")
		return
	}
	for _, e := range parseProperties(path, data) {
		if e.code != "" {
			l.diags = append(l.diags, e.diag)
			continue
		}
		l.applyValue(layer, path, e.line, e.key, e.value)
	}
}

type parsedEntry struct {
	key   string
	value string
	line  int
	code  string
	diag  diag.Diagnostic
}

// parseProperties 解析 flat properties：一行一键、# 注释、值一律字符串。
func parseProperties(path string, data []byte) []parsedEntry {
	var out []parsedEntry
	seen := map[string]int{}
	lines := strings.Split(string(data), "\n")
	for i, raw := range lines {
		lineNo := i + 1
		raw = strings.TrimSuffix(raw, "\r")
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if idx := strings.IndexByte(raw, '#'); idx >= 0 {
			raw = raw[:idx]
		}
		eq := strings.IndexByte(raw, '=')
		if eq < 0 {
			out = append(out, parsedEntry{
				line: lineNo, code: CodeKeyInvalid,
				diag: diag.Diagnostic{File: path, Line: lineNo, Col: 1, Code: CodeKeyInvalid,
					Message: "配置行缺少 =：键值未分隔"},
			})
			continue
		}
		keyPart := raw[:eq]
		key := strings.TrimSpace(keyPart)
		value := strings.TrimSpace(raw[eq+1:])
		col := 1
		for col-1 < len(keyPart) && (keyPart[col-1] == ' ' || keyPart[col-1] == '\t') {
			col++
		}
		if !ValidKey(key) {
			out = append(out, parsedEntry{
				line: lineNo, code: CodeKeyInvalid,
				diag: diag.Diagnostic{File: path, Line: lineNo, Col: col, Code: CodeKeyInvalid,
					Message: fmt.Sprintf("配置键名非法（小写字母/数字/点/连字符，≤128，无连续/首尾点）：%s", key)},
			})
			continue
		}
		if first, ok := seen[key]; ok {
			out = append(out, parsedEntry{
				line: lineNo, code: CodeDuplicateKey,
				diag: diag.Diagnostic{File: path, Line: lineNo, Col: col, Code: CodeDuplicateKey,
					Message: fmt.Sprintf("同层重复配置键：%s（首次出现于第 %d 行）", key, first)},
			})
			continue
		}
		seen[key] = lineNo
		out = append(out, parsedEntry{key: key, value: value, line: lineNo})
	}
	return out
}

func (l *loader) applyEnv() {
	env := l.opts.Environ
	if env == nil {
		env = os.Environ()
	}
	m := parseEnviron(env)
	for _, key := range l.opts.Spec.EnvWhitelist {
		if !ValidKey(key) {
			l.addDiag("envOverrides", 1, CodeKeyInvalid,
				fmt.Sprintf("envOverrides 键名非法：%s", key))
			continue
		}
		name := envName(key)
		if v, ok := m[name]; ok {
			l.applyValue(LayerEnv, name, 0, key, v)
		}
	}
}

func (l *loader) applyCLI() {
	keys := make([]string, 0, len(l.opts.CLI))
	for k := range l.opts.CLI {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		l.applyValue(LayerCLI, "命令行", 0, k, l.opts.CLI[k])
		if ValidKey(k) {
			line := fmt.Sprintf("config: layer=5 key=%s source=命令行", k)
			l.cliAudit = append(l.cliAudit, line)
			if l.opts.Audit != nil {
				fmt.Fprintln(l.opts.Audit, line)
			}
		}
	}
}

func (l *loader) auditLines() []string { return l.cliAudit }

func (l *loader) checkUnknown() {
	for k, e := range l.entries {
		if _, ok := l.opts.Spec.Keys[k]; ok {
			continue
		}
		l.addDiag(e.origin.Source, e.origin.Line, CodeUnknownKey,
			fmt.Sprintf("未知配置键：%s（层 %s，来源 %s）", k, e.origin.Layer, e.origin.Source))
	}
}

func (l *loader) checkRequired() {
	for k, spec := range l.opts.Spec.Keys {
		if spec.Required {
			if _, ok := l.entries[k]; !ok {
				l.addDiag("config", 1, CodeMissingRequired,
					fmt.Sprintf("缺少必需配置键：%s", k))
			}
		}
	}
}

func (l *loader) checkTypes() {
	for k, e := range l.entries {
		spec, ok := l.opts.Spec.Keys[k]
		if !ok {
			continue
		}
		if err := checkKind(e.value, spec.Kind); err != nil {
			l.addDiag(e.origin.Source, e.origin.Line, CodeTypeMismatch,
				fmt.Sprintf("配置值类型错误：%s=%q（期望 %s，层 %s，来源 %s）：%v",
					k, e.value, spec.Kind, e.origin.Layer, e.origin.Source, err))
		}
	}
}

func (l *loader) sortDiags() {
	sort.SliceStable(l.diags, func(i, j int) bool {
		a, b := l.diags[i], l.diags[j]
		if a.File != b.File {
			return a.File < b.File
		}
		if a.Line != b.Line {
			return a.Line < b.Line
		}
		if a.Col != b.Col {
			return a.Col < b.Col
		}
		if a.Code != b.Code {
			return a.Code < b.Code
		}
		return a.Message < b.Message
	})
}

func checkKind(v string, k Kind) error {
	switch k {
	case KindInt:
		_, err := strconv.ParseInt(v, 10, 64)
		return err
	case KindBool:
		if v != "true" && v != "false" {
			return fmt.Errorf("只接受 true/false")
		}
		return nil
	case KindFloat:
		_, err := strconv.ParseFloat(v, 64)
		return err
	default:
		return nil
	}
}

// ValidKey 校验 S8 §6.3 配置键名。
func ValidKey(s string) bool {
	if s == "" || len(s) > 128 {
		return false
	}
	if s[0] == '.' || s[len(s)-1] == '.' || strings.Contains(s, "..") {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '-' {
			continue
		}
		return false
	}
	return true
}

func isSecretKey(key string) bool {
	words := []string{"password", "secret", "token", "key"}
	for _, seg := range strings.Split(key, ".") {
		for _, w := range words {
			if seg == w || strings.HasSuffix(seg, "-"+w) {
				return true
			}
		}
	}
	return false
}

func isPlaceholder(v string) bool {
	return strings.Contains(v, "${") && strings.Contains(v, "}")
}

func envName(key string) string {
	r := strings.NewReplacer(".", "_", "-", "_")
	return "XNULL_OVERRIDE_" + strings.ToUpper(r.Replace(key))
}

func parseEnviron(env []string) map[string]string {
	m := make(map[string]string, len(env))
	for _, kv := range env {
		if i := strings.IndexByte(kv, '='); i >= 0 {
			m[kv[:i]] = kv[i+1:]
		}
	}
	return m
}

func contains(xs []string, v string) bool {
	for _, x := range xs {
		if x == v {
			return true
		}
	}
	return false
}

func fileExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && !st.IsDir()
}

// ParseCLIOverrides 从已剥离工具参数的参数列表提取 --key=value。
// 无 = 的项按工具参数忽略；非法键返回 XPD-601；重复键返回 XPD-602。
func ParseCLIOverrides(args []string) (map[string]string, []diag.Diagnostic) {
	out := map[string]string{}
	var ds []diag.Diagnostic
	for _, arg := range args {
		if !strings.HasPrefix(arg, "--") {
			continue
		}
		body := arg[2:]
		eq := strings.IndexByte(body, '=')
		if eq < 0 {
			continue
		}
		key, value := body[:eq], body[eq+1:]
		if !ValidKey(key) {
			ds = append(ds, diag.Diagnostic{
				File: "命令行", Line: 1, Col: 1, Code: CodeKeyInvalid,
				Message: fmt.Sprintf("命令行配置覆盖键名非法：%s（参数 %s）", key, arg),
			})
			continue
		}
		if _, ok := out[key]; ok {
			ds = append(ds, diag.Diagnostic{
				File: "命令行", Line: 1, Col: 1, Code: CodeDuplicateKey,
				Message: fmt.Sprintf("命令行重复配置键：%s", key),
			})
			continue
		}
		out[key] = value
	}
	sort.SliceStable(ds, func(i, j int) bool {
		if ds[i].Code != ds[j].Code {
			return ds[i].Code < ds[j].Code
		}
		return ds[i].Message < ds[j].Message
	})
	return out, ds
}
