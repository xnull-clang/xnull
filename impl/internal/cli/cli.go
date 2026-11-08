// Package cli 是 xnull 命令行的入口分派与用法校验。
package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/codegen"
	"xnull.dev/xnull/internal/codegen/ffi"
	"xnull.dev/xnull/internal/devtool"
	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/exitcode"
	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/manifest"
	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/version"
	"xnull.dev/xnull/internal/xfront"
	"xnull.dev/xnull/internal/xnfmt"
	"xnull.dev/xnull/internal/xpd"
)

// Version 工具链完整版本（含 commit 短哈希；由 internal/version 提供）。
var Version = version.Full()

const (
	codeUnknownCommand = "CLI-001"
	codeUnknownFlag    = "CLI-002"
	codeManifestAbsent = "CLI-003"
	codeNotImplemented = "CLI-901"

	// 入口诊断（ENTRY-01；S1 §11.2/§11.4）。
	codeEntryMissing   = "ENTRY-001"
	codeEntryDuplicate = "ENTRY-002"
	codeEntrySignature = "ENTRY-003"
)

// Env 承载一次调用的输入输出与环境，便于测试注入。
type Env struct {
	Stdout io.Writer
	Stderr io.Writer
	Args   []string
	// Dir 是清单模式的工作目录（空 = 进程当前目录）。
	Dir string
}

// Run 执行一次命令行调用并返回进程退出码。
func Run(env Env) int {
	if len(env.Args) == 0 {
		writeUsage(env.Stdout)
		return exitcode.Success
	}

	name := env.Args[0]
	rest := env.Args[1:]

	switch name {
	case "-h", "--help", "help":
		writeUsage(env.Stdout)
		return exitcode.Success
	case "-v", "--version", "version":
		fmt.Fprintf(env.Stdout, "xnull %s", version.Info())
		return exitcode.Success
	}

	if _, ok := commands[name]; !ok {
		if len(name) > 0 && name[0] == '-' {
			return fail(env, diag.Diagnostic{
				File: "xnull", Line: 1, Col: 1, Code: codeUnknownFlag,
				Message: fmt.Sprintf("unknown flag %q", name),
				Hint:    "可用命令：" + commandList(),
			})
		}
		return fail(env, diag.Diagnostic{
			File: "xnull", Line: 1, Col: 1, Code: codeUnknownCommand,
			Message: fmt.Sprintf("unknown command %q", name),
			Hint:    "可用命令：" + commandList(),
		})
	}

	if err := parseFlags(rest); err != nil {
		return fail(env, *err)
	}

	// 内部维护工具：规范守门、台账生成、资源表生成（不进入语言用户 CLI 面）。
	if name == "dev" {
		return runDev(env, rest)
	}
	// S8-03：锁文件生成/校验（唯一重生成入口 --update-lock）。
	if name == "lock" {
		return runLock(env, rest)
	}
	// IDE 支持：工程模板创建与结构化检查。
	if name == "new" {
		return runNew(env, rest)
	}
	if name == "check" {
		return runCheck(env, rest)
	}
	// S8-10/S8-16：清单类与 .x 源码格式化。
	if name == "fmt" {
		return runFmtDispatch(env, rest)
	}
	// S8-16：清理与自检。
	if name == "clean" {
		return runClean(env, rest)
	}
	if name == "doctor" {
		return runDoctor(env, rest)
	}
	// 最小可运行闭环：`xnull run path/to/file.x [--] [程序参数...]` 直接执行单文件
	//（不依赖工程清单；清单模式后续接入）。`--` 之后的参数原样交给 main(String[])。
	if name == "run" {
		opts := parseRunArgs(rest)
		if opts.path != "" {
			return runFile(env, opts)
		}
	}
	// 编译路径（M4.2）：`xnull build file.x [-o bin]` → C → cc → 可执行。
	if name == "build" && len(rest) > 0 && strings.HasSuffix(rest[0], ".x") {
		if hasFlag(rest, "--json") {
			return buildFileJSON(env, rest, rest[0])
		}
		return buildFile(env, rest, rest[0])
	}
	// 内存策略判定（S2 §15.1）：`xnull policy file.x` 输出 JSON（M3.2 判定表执行器消费）。
	if name == "policy" && len(rest) > 0 && strings.HasSuffix(rest[0], ".x") {
		return policyFile(env, rest[0])
	}

	dir := env.Dir
	if dir == "" {
		dir = "."
	}
	switch name {
	case "build":
		out, code := buildManifest(env, rest, dir)
		if code == exitcode.Success && out != "" {
			fmt.Fprintln(env.Stdout, out)
		}
		return code
	case "run":
		return runManifest(env, rest, dir)
	case "test":
		return testManifest(env, rest, dir)
	case "lock":
		if findManifestRoot(dir) == "" {
			return fail(env, diag.Diagnostic{
				File: "xnull", Line: 1, Col: 1, Code: codeManifestAbsent,
				Message: "找不到 xnull.project",
				Hint:    "在进程内向上查找清单；确认当前目录属于某个工程",
			})
		}
	}

	return notImplemented(env, name)
}

var commands = map[string]string{
	"new":    "创建 XNull 工程模板（app / library）",
	"check":  "检查源文件并输出诊断（--json 为 IDE/CI 机器接口）",
	"policy": "输出单文件内存策略判定 JSON（S2 §15.1；开发预览命令）",
	"build":  "校验清单并构建产物（阶段：validate→compile→test→package→install）",
	"run":    "构建并运行 app 入口",
	"test":   "运行测试入口（src/test/x）",
	"fmt":    "格式化 .x 源码或 xnull.project / .xmeta / .xplugin / xnull.lock（--check 只检查）",
	"clean":  "清理 target/ 与缓存（--all 含本地仓库缓存）",
	"doctor": "环境自检：cc / runtime / 本地仓库 / 清单 / 锁",
	"lock":   "校验或重生成锁文件（--update-lock 为唯一重生成入口）",
	"dev":    "内部维护工具（check / ledger / res / board）",
}

func commandList() string {
	out := ""
	for _, name := range []string{"new", "check", "build", "run", "test", "fmt", "lock", "policy", "dev"} {
		if out != "" {
			out += "、"
		}
		out += name
	}
	return out
}

func writeUsage(w io.Writer) {
	fmt.Fprintf(w, "xnull %s —— XNull 工具链\n\n用法：xnull <command> [flags]\n\n命令：\n", Version)
	for _, name := range []string{"new", "check", "build", "run", "test", "fmt", "lock", "policy", "dev"} {
		fmt.Fprintf(w, "  %-6s %s\n", name, commands[name])
	}
	fmt.Fprintf(w, "\n退出码：0 成功 / 1 构建失败 / 2 清单或用法错误 / 130 中断\n")
}

// parseFlags 只校验形态：当前阶段命令参数集尚未冻结，未知长参数即用法错误。
// `--` 是命令参数与程序参数的分界；其后的内容不属于工具链，不再按 flag 校验。
func parseFlags(args []string) *diag.Diagnostic {
	for _, a := range args {
		if a == "--" {
			break
		}
		if len(a) > 1 && a[0] == '-' && a[1] == '-' {
			if strings.HasPrefix(a, "--mem=") || strings.HasPrefix(a, "--skip=") {
				continue
			}
			if _, ok := knownFlags[a]; !ok {
				return &diag.Diagnostic{
					File: "xnull", Line: 1, Col: 1, Code: codeUnknownFlag,
					Message: fmt.Sprintf("unknown flag %q", a),
				}
			}
		}
	}
	return nil
}

// runOptions 是一次 `xnull run` 的解析结果：入口文件、执行模式与程序参数。
// 程序参数与工具链 flag 分离，`--` 之后一律视为程序参数（S1 §11.2）。
type runOptions struct {
	path       string
	interp     bool
	runtimeDir string
	progArgs   []string
}

// parseRunArgs 解析 run 的位置参数：
//   - 第一个以 .x 结尾的位置参数是入口文件；
//   - `--` 之后全部是程序参数；
//   - `--interp` / `--runtime <dir>` 是工具链选项，不进入程序参数；
//   - 其余非 flag 位置参数作为程序参数（保持“源文件可在参数中任意位置”的既有行为）。
func parseRunArgs(rest []string) runOptions {
	var opts runOptions
	afterSep := false
	for i := 0; i < len(rest); i++ {
		a := rest[i]
		if afterSep {
			opts.progArgs = append(opts.progArgs, a)
			continue
		}
		switch {
		case a == "--":
			afterSep = true
		case a == "--interp":
			opts.interp = true
		case a == "--runtime":
			if i+1 < len(rest) {
				opts.runtimeDir = rest[i+1]
				i++
			}
		case strings.HasPrefix(a, "--"):
			// 其余已知长 flag 当前对 run 无语义（如 --profile/--verbose），保持既有“接受但不生效”行为。
			// 单横线参数不是工具链 flag，按程序参数处理。
		default:
			if opts.path == "" && strings.HasSuffix(a, ".x") {
				opts.path = a
				continue
			}
			opts.progArgs = append(opts.progArgs, a)
		}
	}
	return opts
}

var knownFlags = map[string]struct{}{
	"--update-lock": {}, "--skip": {}, "--profile": {}, "--check": {},
	"--emit": {}, "--offline": {}, "--verbose": {},
	"--interp": {}, "--runtime": {}, "--json": {}, "-o": {},
	"--no-test": {}, "--record-green": {}, "--since": {}, "--write": {},
	"--resources": {}, "--all": {},
	"--mem": {}, "--stats": {},
}

func notImplemented(env Env, name string) int {
	msg := fmt.Sprintf("命令 %q 尚未实现", name)
	fmt.Fprintf(env.Stderr, "xnull: %s\n", msg)
	return exitcode.Usage
}

// runFile 执行单个 .x 文件：先做入口前置检查，再按模式执行。
// 退出码：0 成功；1 入口/语法/运行错误（含 fatal）；2 文件不可读。
func runFile(env Env, opts runOptions) int {
	if d := checkEntry(opts.path); d != nil {
		return failEntry(env, *d)
	}
	// --interp：解释器调试模式（M4.3）；默认走编译路径（正式路径）。
	if opts.interp {
		return interpFile(env, opts.path, opts.progArgs)
	}
	return runCompiled(env, opts.path, opts.progArgs, opts.runtimeDir)
}

// runCompiled 编译路径：临时目录构建可执行并运行，透传退出码与程序参数（M4.2/4.3）。
func runCompiled(env Env, path string, progArgs []string, flagRuntime string) int {
	runtimeDir := flagRuntime
	if runtimeDir == "" {
		for _, cand := range []string{"impl/runtime", "../impl/runtime", "../../impl/runtime", "../../runtime", "runtime"} {
			if st, err := os.Stat(filepath.Join(cand, "rt.h")); err == nil && !st.IsDir() {
				runtimeDir = cand
				break
			}
		}
	}
	if runtimeDir == "" {
		if runtimeDir = os.Getenv("XNULL_RUNTIME"); runtimeDir == "" {
			fmt.Fprintln(env.Stderr, "xnull: 找不到运行时源码目录（rt.h）；用 --runtime 或 XNULL_RUNTIME 指定")
			return exitcode.Usage
		}
	}
	dir, err := os.MkdirTemp("", "xnull-run-")
	if err != nil {
		fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
		return exitcode.BuildFail
	}
	defer os.RemoveAll(dir)
	bin := filepath.Join(dir, "prog")
	if code := codegen.Build(path, bin, runtimeDir, env.Stderr); code != 0 {
		return code
	}
	cmd := exec.Command(bin, progArgs...)
	cmd.Stdout = env.Stdout
	cmd.Stderr = env.Stderr
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode()
		}
		fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
		return exitcode.BuildFail
	}
	return exitcode.Success
}

// interpFile 解释执行（调试模式；M4.3 降级）。
func interpFile(env Env, path string, progArgs []string) int {
	// 多文件编译单元：解释路径与编译路径共用同一加载器（保证双路径看到同一组声明）。
	u, diags := codegen.LoadUnits(path)
	if u == nil && len(diags) == 0 {
		fmt.Fprintf(env.Stderr, "xnull: 无法读取文件 %s\n", path)
		return exitcode.Usage
	}
	if len(diags) > 0 {
		for _, d := range diags {
			fmt.Fprintln(env.Stderr, d.String())
		}
		return exitcode.BuildFail
	}
	// 语义分析（名称解析先行；诊断码 RES-1xx）。
	if sd := sema.Analyze(path, u); len(sd) > 0 {
		for _, d := range sd {
			fmt.Fprintln(env.Stderr, d.String())
		}
		return exitcode.BuildFail
	}
	code, err := interp.RunWithDiag(u, env.Stdout, env.Stderr, progArgs)
	if err != nil {
		fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
	}
	return code
}

// checkEntry 在编译/解释之前校验入口（S1 §11.2/§11.4）：
// 缺失、重复、非法签名都给出带位置的明确诊断，不落到 C 编译错误或静默执行。
// 解析/导入诊断由既有路径报告，这里不重复。
func checkEntry(path string) *diag.Diagnostic {
	u, diags := codegen.LoadUnits(path)
	if u == nil || len(diags) > 0 {
		return nil
	}
	var mains []*xfront.TopFunc
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok && fn.Name == "main" {
			mains = append(mains, fn)
		}
	}
	switch len(mains) {
	case 0:
		return &diag.Diagnostic{
			File: path, Line: 1, Col: 1, Code: codeEntryMissing,
			Message: "找不到入口 main",
			Hint:    "入口文件必须包含唯一入口 main；签名：main() 或 main(String[] args)，返回 void 或 Int（S1 §11.4）",
		}
	}
	// §11.2：只有匹配入口签名的 main 才是入口；其余 main 重载是普通函数。
	var matched []*xfront.TopFunc
	for _, fn := range mains {
		if entrySignatureProblem(fn) == "" {
			matched = append(matched, fn)
		}
	}
	if len(matched) == 0 {
		fn := mains[0]
		return &diag.Diagnostic{
			File: path, Line: fn.P.Line, Col: fn.P.Col, Code: codeEntrySignature,
			Message: "入口 main 的签名不合法：" + entrySignatureProblem(fn),
			Hint:    "入口签名：main() 或 main(String[] args)，返回 void 或 Int（S1 §11.2）",
		}
	}
	if len(matched) > 1 {
		dup := matched[1]
		return &diag.Diagnostic{
			File: path, Line: dup.P.Line, Col: dup.P.Col, Code: codeEntryDuplicate,
			Message: fmt.Sprintf("重复入口 main：发现 %d 个匹配签名的 main 声明", len(matched)),
			Hint:    "一个程序只能有一个匹配签名的入口；其余 main 重载不得与入口同签名（S1 §11.2）",
		}
	}
	return nil
}

// entrySignatureProblem 返回入口签名问题；空串表示合法。
func entrySignatureProblem(fn *xfront.TopFunc) string {
	if len(fn.TypePars) > 0 {
		return "不能是泛型函数"
	}
	if fn.Private || fn.Protected {
		return "必须是公开的"
	}
	if !fn.Void && !isIntType(fn.Ret) {
		return "返回类型必须是 void 或 Int"
	}
	if len(fn.Params) == 0 {
		return ""
	}
	if len(fn.Params) != 1 {
		return "只能接收 0 个参数或 1 个 String[] 参数"
	}
	if !isStringArrayType(fn.Params[0].Type) {
		return "参数类型必须是 String[]"
	}
	return ""
}

func isIntType(t xfront.TypeRef) bool {
	nt, ok := t.(*xfront.NamedType)
	return ok && lastQualified(nt) == "Int"
}

func isStringArrayType(t xfront.TypeRef) bool {
	st, ok := t.(*xfront.SuffixedType)
	if !ok || len(st.Suffixes) != 1 || st.Suffixes[0] != "[]" {
		return false
	}
	nt, ok := st.Base.(*xfront.NamedType)
	return ok && lastQualified(nt) == "String"
}

func lastQualified(nt *xfront.NamedType) string {
	if len(nt.Qual) == 0 {
		return ""
	}
	return nt.Qual[len(nt.Qual)-1]
}

func failEntry(env Env, d diag.Diagnostic) int {
	fmt.Fprintln(env.Stderr, d.String())
	return exitcode.BuildFail
}

func fail(env Env, d diag.Diagnostic) int {
	fmt.Fprintln(env.Stderr, d.String())
	return exitcode.Usage
}

// policyFile 解析单文件并输出策略判定 JSON（§15.1；结果按声明名排序，确定性）。
func policyFile(env Env, path string) int {
	src, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(env.Stderr, "xnull: 无法读取文件 %s：%v\n", path, err)
		return exitcode.Usage
	}
	u, pdiags := xfront.ParseUnit(path, string(src))
	if len(pdiags) > 0 {
		for _, d := range pdiags {
			fmt.Fprintln(env.Stderr, d.String())
		}
		return exitcode.BuildFail
	}
	res, sd := sema.AnalyzeWith(path, u)
	if len(sd) > 0 {
		for _, d := range sd {
			fmt.Fprintln(env.Stderr, d.String())
		}
		return exitcode.BuildFail
	}
	out, _ := json.MarshalIndent(res.Strategies(u), "", "  ")
	fmt.Fprintln(env.Stdout, string(out))
	return exitcode.Success
}

// buildFile 编译路径：解析→语义→C→cc→可执行（M4.2）。
// 运行时源码目录解析顺序：XNULL_RUNTIME 环境变量 → 相对探测 impl/runtime。
func buildFile(env Env, rest []string, srcPath string) int {
	if d := checkEntry(srcPath); d != nil {
		return failEntry(env, *d)
	}
	out := "prog"
	runtimeDir := ""
	memPolicy := ""
	stats := false
	var libs []ffi.LinkLib
	var libDirs []string
	resDir := ""
	for i := 1; i < len(rest)-1; i++ {
		switch {
		case rest[i] == "-o":
			out = rest[i+1]
		case rest[i] == "--runtime":
			runtimeDir = rest[i+1]
		case rest[i] == "-l":
			libs = append(libs, ffi.LinkLib{Name: rest[i+1]})
		case rest[i] == "-L":
			libDirs = append(libDirs, rest[i+1])
		case rest[i] == "--resources":
			resDir = rest[i+1]
		case strings.HasPrefix(rest[i], "--mem="):
			memPolicy = strings.TrimPrefix(rest[i], "--mem=")
		case rest[i] == "--stats":
			stats = true
		}
	}
	if memPolicy != "" && memPolicy != "auto" && memPolicy != "arc" && memPolicy != "gc" {
		fmt.Fprintf(env.Stderr, "xnull: --mem 只接受 auto/arc/gc，got %q\n", memPolicy)
		return exitcode.Usage
	}
	if runtimeDir == "" {
		runtimeDir = os.Getenv("XNULL_RUNTIME")
	}
	if runtimeDir == "" {
		for _, cand := range []string{"impl/runtime", "../impl/runtime", "../../impl/runtime", "../../runtime", "runtime"} {
			if st, err := os.Stat(filepath.Join(cand, "rt.h")); err == nil && !st.IsDir() {
				runtimeDir = cand
				break
			}
		}
	}
	if runtimeDir == "" {
		fmt.Fprintln(env.Stderr, "xnull: 找不到运行时源码目录（rt.h）；用 --runtime 或 XNULL_RUNTIME 指定")
		return exitcode.Usage
	}
	// P-10：link.libraries → LinkArgs（去重 + 升序）；-L/-l 一律排在全部目标文件之后。
	opts := codegen.Options{LinkArgs: linkArgs(libs, libDirs), MemPolicy: memPolicy, Stats: stats}
	// S6-04：工程资源目录 → 资源表 C（缺省由 codegen 写零资源空表）。
	if resDir != "" {
		resC := out + ".res.c"
		if err := devtool.GenerateResources(resDir, resC); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return exitcode.BuildFail
		}
		opts.ResC = resC
	}
	return codegen.BuildWithOptions(srcPath, out, runtimeDir, opts, env.Stderr)
}

// linkArgs 把构建命令行/清单的链接库与搜索目录翻译为确定性链接参数。
// 顺序：-L 在前、-l 在后，各自去重 + 升序（ffi.LinkArgs 负责 -l）。
func linkArgs(libs []ffi.LinkLib, libDirs []string) []string {
	args := make([]string, 0, len(libDirs)+len(libs))
	seen := map[string]bool{}
	dirs := make([]string, 0, len(libDirs))
	for _, d := range libDirs {
		if d == "" || seen[d] {
			continue
		}
		seen[d] = true
		dirs = append(dirs, "-L"+d)
	}
	sort.Strings(dirs)
	args = append(args, dirs...)
	return append(args, ffi.LinkArgs(libs)...)
}

// runManifest 构建清单工程并运行产物；`--` 之后透传程序参数。
func runManifest(env Env, rest []string, dir string) int {
	var progArgs []string
	buildArgs := rest
	for i, a := range rest {
		if a == "--" {
			buildArgs = rest[:i]
			progArgs = rest[i+1:]
			break
		}
	}
	out, code := buildManifest(env, buildArgs, dir)
	if code != exitcode.Success {
		return code
	}
	cmd := exec.Command(out, progArgs...)
	cmd.Stdout = env.Stdout
	cmd.Stderr = env.Stderr
	cmd.Stdin = os.Stdin
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode()
		}
		fmt.Fprintf(env.Stderr, "xnull: 运行产物失败：%v\n", err)
		return exitcode.BuildFail
	}
	return exitcode.Success
}

// testManifest 执行 validate→compile→test（跳过 package/install）。
func testManifest(env Env, rest []string, dir string) int {
	args := append([]string{}, rest...)
	args = append(args, "--skip", "package", "--skip", "install")
	_, code := buildManifest(env, args, dir)
	return code
}

// runFmtDispatch：显式 `.x` 路径走源码格式化，其余走清单/锁/元数据格式化。
func runFmtDispatch(env Env, rest []string) int {
	for _, a := range rest {
		if !strings.HasPrefix(a, "-") && strings.HasSuffix(a, ".x") {
			return runFmtSources(env, rest)
		}
	}
	return runFmt(env, rest)
}

// runFmtSources 用 internal/xnfmt 格式化 `.x`；--check 只检查、不写文件。
func runFmtSources(env Env, rest []string) int {
	check := hasFlag(rest, "--check")
	var paths []string
	for _, a := range rest {
		if strings.HasPrefix(a, "-") {
			continue
		}
		paths = append(paths, a)
	}
	if len(paths) == 0 {
		fmt.Fprintln(env.Stderr, "xnull: fmt 需要 .x 文件路径")
		return exitcode.Usage
	}
	failed := false
	for _, p := range paths {
		src, err := os.ReadFile(p)
		if err != nil {
			fmt.Fprintf(env.Stderr, "xnull: 无法读取 %s：%v\n", p, err)
			failed = true
			continue
		}
		out, ds := xnfmt.Format(p, string(src))
		if len(ds) > 0 {
			for _, d := range ds {
				fmt.Fprintln(env.Stderr, d.Error())
			}
			failed = true
			continue
		}
		if out == string(src) {
			continue
		}
		if check {
			fmt.Fprintf(env.Stderr, "xnull: 需要格式化 %s\n", p)
			failed = true
			continue
		}
		if err := os.WriteFile(p, []byte(out), 0o644); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: 无法写入 %s：%v\n", p, err)
			failed = true
		}
	}
	if failed {
		return exitcode.BuildFail
	}
	return exitcode.Success
}

// runClean 清理 target/ 与缓存；--all 连本地仓库缓存一起清理。
func runClean(env Env, rest []string) int {
	all := hasFlag(rest, "--all")
	root := env.Dir
	if root == "" {
		root = "."
	}
	for _, a := range rest {
		if !strings.HasPrefix(a, "-") {
			root = a
		}
	}
	target := filepath.Join(root, "target")
	if err := os.RemoveAll(target); err != nil {
		fmt.Fprintf(env.Stderr, "xnull: 清理 %s 失败：%v\n", target, err)
		return exitcode.BuildFail
	}
	fmt.Fprintf(env.Stdout, "已清理 %s\n", target)
	if all {
		repo := os.Getenv("XNULL_REPO")
		if repo == "" {
			if home, err := os.UserHomeDir(); err == nil {
				repo = filepath.Join(home, ".xnull", "repository")
			}
		}
		if repo != "" {
			if err := os.RemoveAll(repo); err != nil {
				fmt.Fprintf(env.Stderr, "xnull: 清理本地仓库 %s 失败：%v\n", repo, err)
				return exitcode.BuildFail
			}
			fmt.Fprintf(env.Stdout, "已清理本地仓库缓存 %s\n", repo)
		}
	}
	return exitcode.Success
}

// runDoctor 环境自检：cc / runtime / 本地仓库 / 清单 / 锁。fail 级才算失败。
func runDoctor(env Env, rest []string) int {
	root := env.Dir
	if root == "" {
		root = "."
	}
	for _, a := range rest {
		if !strings.HasPrefix(a, "-") {
			root = a
		}
	}
	failed := false
	report := func(level, name, detail string) {
		fmt.Fprintf(env.Stdout, "[%s] %s：%s\n", level, name, detail)
		if level == "fail" {
			failed = true
		}
	}

	if cc, err := exec.LookPath("cc"); err == nil {
		report("ok", "cc", cc)
	} else {
		report("fail", "cc", "未找到 C 编译器（cc）")
	}

	rt := manifestRuntimeDir(root)
	if rt == "" {
		rt = os.Getenv("XNULL_RUNTIME")
	}
	if rt != "" {
		if st, err := os.Stat(filepath.Join(rt, "rt.h")); err == nil && !st.IsDir() {
			report("ok", "runtime", rt)
		} else {
			report("fail", "runtime", "rt.h 不存在："+rt)
		}
	} else {
		report("fail", "runtime", "找不到运行时源码目录（rt.h）")
	}

	repo := os.Getenv("XNULL_REPO")
	if repo == "" {
		if home, err := os.UserHomeDir(); err == nil {
			repo = filepath.Join(home, ".xnull", "repository")
		}
	}
	if repo == "" {
		report("warn", "repo", "未设置本地仓库")
	} else if st, err := os.Stat(repo); err == nil && st.IsDir() {
		report("ok", "repo", repo)
	} else {
		report("warn", "repo", "本地仓库尚未创建："+repo)
	}

	projectRoot := findManifestRoot(root)
	if projectRoot == "" {
		report("warn", "manifest", "当前目录不在工程内（无 xnull.project）")
	} else {
		src, err := os.ReadFile(filepath.Join(projectRoot, "xnull.project"))
		if err != nil {
			report("fail", "manifest", "读取失败："+err.Error())
		} else if f, ds := xpd.Parse("xnull.project", string(src)); len(ds) > 0 {
			report("fail", "manifest", ds[0].Message)
		} else if f.Find("project") == nil {
			report("fail", "manifest", "缺少 project 块")
		} else {
			report("ok", "manifest", projectRoot)
		}
	}

	lockPath := filepath.Join(root, "xnull.lock")
	if projectRoot != "" {
		lockPath = filepath.Join(projectRoot, "xnull.lock")
	}
	if _, err := os.Stat(lockPath); err != nil {
		report("warn", "lock", "未找到 xnull.lock（首次构建后可生成）")
	} else if lock, ds, lerr := manifest.LoadLock(lockPath); lerr != nil {
		report("fail", "lock", "读取失败："+lerr.Error())
	} else if len(ds) > 0 {
		report("fail", "lock", ds[0].Message)
	} else {
		report("ok", "lock", fmt.Sprintf("%s（%d 条）", lockPath, len(lock.Entries)))
	}

	if failed {
		return exitcode.BuildFail
	}
	return exitcode.Success
}
