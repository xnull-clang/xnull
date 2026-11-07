package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/codegen"
	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/sema"
)

// machineDiag 是 IDE/CI 消费的稳定诊断投影。
type machineDiag struct {
	File    string `json:"file"`
	Line    int    `json:"line"`
	Column  int    `json:"column"`
	Code    string `json:"code"`
	Message string `json:"message"`
	Hint    string `json:"hint,omitempty"`
	Snippet string `json:"snippet,omitempty"`
	Width   int    `json:"width,omitempty"`
}

type checkJSONResult struct {
	OK          bool          `json:"ok"`
	File        string        `json:"file"`
	Diagnostics []machineDiag `json:"diagnostics"`
}

type buildJSONResult struct {
	OK          bool          `json:"ok"`
	File        string        `json:"file"`
	Output      string        `json:"output,omitempty"`
	ExitCode    int           `json:"exitCode"`
	Diagnostics []machineDiag `json:"diagnostics"`
	Log         string        `json:"log,omitempty"`
}

type newJSONResult struct {
	OK        bool     `json:"ok"`
	Template  string   `json:"template,omitempty"`
	Directory string   `json:"directory,omitempty"`
	Files     []string `json:"files,omitempty"`
	Error     string   `json:"error,omitempty"`
}

func writeJSON(w interface{ Write([]byte) (int, error) }, v any) {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return
	}
	_, _ = w.Write(append(data, '\n'))
}

func toMachineDiags(ds []diag.Diagnostic) []machineDiag {
	out := make([]machineDiag, 0, len(ds))
	for _, d := range ds {
		out = append(out, machineDiag{
			File:    d.File,
			Line:    d.Line,
			Column:  d.Col,
			Code:    d.Code,
			Message: d.Message,
			Hint:    d.Hint,
			Snippet: d.Snippet,
			Width:   d.Width,
		})
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].File != out[j].File {
			return out[i].File < out[j].File
		}
		if out[i].Line != out[j].Line {
			return out[i].Line < out[j].Line
		}
		if out[i].Column != out[j].Column {
			return out[i].Column < out[j].Column
		}
		return out[i].Code < out[j].Code
	})
	return out
}

// collectDiagnostics 执行装载 + 语义；requireEntry 为 true 时再校验入口。
// check 不要求 main（库文件也可检查）；build 要求入口。
func collectDiagnostics(path string, requireEntry bool) []diag.Diagnostic {
	u, ds := codegen.LoadUnits(path)
	if u == nil && len(ds) == 0 {
		return []diag.Diagnostic{{
			File: path, Line: 1, Col: 1, Code: "CLI-004",
			Message: "无法读取源文件",
			Hint:    "确认路径存在且是 .x 源文件",
		}}
	}
	if len(ds) > 0 {
		return ds
	}
	if sd := sema.Analyze(path, u); len(sd) > 0 {
		return sd
	}
	if requireEntry {
		if d := checkEntry(path); d != nil {
			return []diag.Diagnostic{*d}
		}
	}
	return nil
}

// hasFlag 判断参数中是否出现某长旗标（`--` 之后不算工具链旗标）。
func hasFlag(args []string, flag string) bool {
	for _, a := range args {
		if a == "--" {
			return false
		}
		if a == flag {
			return true
		}
	}
	return false
}

func runCheck(env Env, rest []string) int {
	jsonOut := hasFlag(rest, "--json")
	path := ""
	for _, a := range rest {
		if a == "--" {
			break
		}
		if strings.HasPrefix(a, "-") {
			continue
		}
		if path == "" {
			path = a
		}
	}
	if path == "" {
		if fileExists("src/main/x/main.x") {
			path = "src/main/x/main.x"
		} else {
			fmt.Fprintln(env.Stderr, "xnull: check 需要 .x 文件，或当前工程含 src/main/x/main.x")
			return 2
		}
	}
	if st, err := os.Stat(path); err != nil || st.IsDir() {
		d := diag.Diagnostic{
			File: path, Line: 1, Col: 1, Code: "CLI-004",
			Message: "无法读取源文件",
			Hint:    "确认路径存在且是 .x 源文件",
		}
		if jsonOut {
			writeJSON(env.Stdout, checkJSONResult{OK: false, File: path, Diagnostics: toMachineDiags([]diag.Diagnostic{d})})
		} else {
			fmt.Fprintln(env.Stderr, d.String())
		}
		return 2
	}
	ds := collectDiagnostics(path, false)
	if jsonOut {
		writeJSON(env.Stdout, checkJSONResult{
			OK:          len(ds) == 0,
			File:        path,
			Diagnostics: toMachineDiags(ds),
		})
	} else {
		for _, d := range ds {
			fmt.Fprintln(env.Stderr, d.String())
		}
	}
	if len(ds) > 0 {
		return 1
	}
	return 0
}

func fileExists(path string) bool {
	st, err := os.Stat(path)
	return err == nil && !st.IsDir()
}

func runNew(env Env, rest []string) int {
	jsonOut := hasFlag(rest, "--json")
	var pos []string
	for _, a := range rest {
		if strings.HasPrefix(a, "-") {
			continue
		}
		pos = append(pos, a)
	}
	if len(pos) < 1 || len(pos) > 2 {
		fmt.Fprintln(env.Stderr, "xnull: 用法：xnull new <app|library> <目录> [--json]")
		return 2
	}
	template := pos[0]
	dir := ""
	if len(pos) == 2 {
		dir = pos[1]
	} else {
		dir = "."
	}
	if template != "app" && template != "library" {
		fmt.Fprintf(env.Stderr, "xnull: 未知模板 %q（可用：app、library）\n", template)
		return 2
	}
	files, err := createProject(template, dir)
	if err != nil {
		if jsonOut {
			writeJSON(env.Stdout, newJSONResult{OK: false, Template: template, Directory: dir, Error: err.Error()})
		} else {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
		}
		return 1
	}
	if jsonOut {
		writeJSON(env.Stdout, newJSONResult{OK: true, Template: template, Directory: dir, Files: files})
	} else {
		fmt.Fprintf(env.Stdout, "已创建 %s 工程：%s\n", template, dir)
		for _, f := range files {
			fmt.Fprintf(env.Stdout, "  %s\n", f)
		}
	}
	return 0
}

func createProject(template, dir string) ([]string, error) {
	if dir == "" {
		dir = "."
	}
	abs, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	if st, err := os.Stat(abs); err == nil {
		if !st.IsDir() {
			return nil, fmt.Errorf("目标已存在且不是目录：%s", abs)
		}
		entries, err := os.ReadDir(abs)
		if err != nil {
			return nil, err
		}
		if len(entries) > 0 {
			return nil, fmt.Errorf("目标目录非空，拒绝覆盖：%s", abs)
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	if err := os.MkdirAll(abs, 0o755); err != nil {
		return nil, err
	}
	base := filepath.Base(abs)
	artifact := sanitizeArtifact(base)
	pkg := sanitizePackage(base)
	project := projectTemplate(template, artifact, pkg)
	mainFile := mainTemplate(template, artifact)
	if err := os.MkdirAll(filepath.Join(abs, "src", "main", "resources"), 0o755); err != nil {
		return nil, err
	}
	files := map[string]string{
		"xnull.project": project,
		".gitignore":    "target/\n*.c\n",
	}
	if template == "app" {
		files["src/main/x/main.x"] = mainFile
	} else {
		files["src/main/x/lib.x"] = mainFile
	}
	var written []string
	for name, content := range files {
		path := filepath.Join(abs, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return nil, err
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			return nil, err
		}
		written = append(written, name)
	}
	sort.Strings(written)
	return written, nil
}

func sanitizeArtifact(s string) string {
	s = strings.ToLower(s)
	var b strings.Builder
	prevDash := false
	for _, r := range s {
		ok := (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9')
		if ok {
			b.WriteRune(r)
			prevDash = false
		} else if !prevDash {
			b.WriteByte('-')
			prevDash = true
		}
	}
	out := strings.Trim(b.String(), "-")
	if out == "" {
		return "app"
	}
	return out
}

func sanitizePackage(s string) string {
	s = sanitizeArtifact(s)
	s = strings.ReplaceAll(s, "-", "_")
	if s == "" || (s[0] >= '0' && s[0] <= '9') {
		s = "app_" + s
	}
	return s
}

func projectTemplate(template, artifact, pkg string) string {
	packaging := "app"
	entry := ""
	if template == "app" {
		entry = fmt.Sprintf(`    entryFile    = src/main/x/main.x
    entryPackage = com.example.%s
`, pkg)
	} else {
		packaging = "library"
	}
	return fmt.Sprintf(`project {
  groupId    = com.example
  artifactId = %s
  version    = 0.1.0
  packaging  = %s

  properties {
    xdk-version      = 1.1.0
    language-version = [3.3, 4.0)
  }

  build {
    mode         = debug
%s  }

  link {
    unsafe = false
  }
}
`, artifact, packaging, entry)
}

func mainTemplate(template, artifact string) string {
	if template == "library" {
		return fmt.Sprintf(`// %s library
static Int add(Int a, Int b) {
    return a + b
}
`, artifact)
	}
	return `static Int main() {
    print("hello, XNull")
    return 0
}
`
}

// buildFileJSON 输出 IDE/CI 可消费的构建结果；stdout 只放 JSON。
func buildFileJSON(env Env, rest []string, srcPath string) int {
	ds := collectDiagnostics(srcPath, true)
	if len(ds) > 0 {
		writeJSON(env.Stdout, buildJSONResult{
			OK: false, File: srcPath, ExitCode: 1,
			Diagnostics: toMachineDiags(ds),
		})
		return 1
	}
	out := "prog"
	runtimeDir := ""
	var libs []string
	var libDirs []string
	for i := 1; i < len(rest); i++ {
		a := rest[i]
		switch a {
		case "-o":
			if i+1 < len(rest) {
				out = rest[i+1]
				i++
			}
		case "--runtime":
			if i+1 < len(rest) {
				runtimeDir = rest[i+1]
				i++
			}
		case "-l":
			if i+1 < len(rest) {
				libs = append(libs, rest[i+1])
				i++
			}
		case "-L":
			if i+1 < len(rest) {
				libDirs = append(libDirs, rest[i+1])
				i++
			}
		}
	}
	if runtimeDir == "" {
		runtimeDir = resolveRuntimeDir()
	}
	if runtimeDir == "" {
		writeJSON(env.Stdout, buildJSONResult{
			OK: false, File: srcPath, Output: out, ExitCode: 2,
			Diagnostics: []machineDiag{{File: "xnull", Line: 1, Column: 1, Code: "CLI-005", Message: "找不到运行时源码目录（rt.h）"}},
			Log:         "用 --runtime 或 XNULL_RUNTIME 指定",
		})
		return 2
	}
	if d := filepath.Dir(out); d != "." && d != "" {
		_ = os.MkdirAll(d, 0o755)
	}
	var buf bytes.Buffer
	code := codegen.BuildWithOptions(srcPath, out, runtimeDir, codegen.Options{
		LinkArgs: linkArgsFromNames(libs, libDirs),
	}, &buf)
	res := buildJSONResult{
		OK: code == 0, File: srcPath, Output: out,
		ExitCode: code, Diagnostics: []machineDiag{},
	}
	if code != 0 {
		res.Log = buf.String()
		writeJSON(env.Stdout, res)
		return code
	}
	writeJSON(env.Stdout, res)
	return 0
}

func resolveRuntimeDir() string {
	for _, cand := range []string{"impl/runtime", "../impl/runtime", "../../impl/runtime", "../../runtime", "runtime"} {
		if st, err := os.Stat(filepath.Join(cand, "rt.h")); err == nil && !st.IsDir() {
			return cand
		}
	}
	return os.Getenv("XNULL_RUNTIME")
}

func linkArgsFromNames(libs, dirs []string) []string {
	args := make([]string, 0, len(libs)+len(dirs))
	seen := map[string]bool{}
	var ds []string
	for _, d := range dirs {
		if d == "" || seen[d] {
			continue
		}
		seen[d] = true
		ds = append(ds, "-L"+d)
	}
	sort.Strings(ds)
	args = append(args, ds...)
	seen = map[string]bool{}
	var ls []string
	for _, l := range libs {
		if l == "" || seen[l] {
			continue
		}
		seen[l] = true
		ls = append(ls, "-l"+l)
	}
	sort.Strings(ls)
	return append(args, ls...)
}
