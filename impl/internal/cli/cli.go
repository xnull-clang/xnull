// Package cli 是 xnull 命令行的入口分派与用法校验。
package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"xnull.dev/xnull/internal/codegen"
	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/exitcode"
	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// Version 工具链版本；与清单 properties.xdk-version 的校验后续接入。
const Version = "0.1.0-dev"

const (
	codeUnknownCommand = "CLI-001"
	codeUnknownFlag    = "CLI-002"
	codeManifestAbsent = "CLI-003"
	codeNotImplemented = "CLI-901"
)

// Env 承载一次调用的输入输出与环境，便于测试注入。
type Env struct {
	Stdout io.Writer
	Stderr io.Writer
	Args   []string
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
		fmt.Fprintf(env.Stdout, "xnull %s\n", Version)
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

	// 最小可运行闭环：`xnull run path/to/file.xn` 直接执行单文件（不依赖工程清单；清单模式后续接入）。
	if name == "run" {
		for i, a := range rest {
			if strings.HasSuffix(a, ".xn") {
				return runFile(env, a, append(append([]string{}, rest[:i]...), rest[i+1:]...))
			}
		}
	}
	// 编译路径（M4.2）：`xnull build file.xn [-o bin]` → C → cc → 可执行。
	if name == "build" && len(rest) > 0 && strings.HasSuffix(rest[0], ".xn") {
		return buildFile(env, rest, rest[0])
	}
	// 内存策略判定（S2 §15.1）：`xnull policy file.xn` 输出 JSON（M3.2 判定表执行器消费）。
	if name == "policy" && len(rest) > 0 && strings.HasSuffix(rest[0], ".xn") {
		return policyFile(env, rest[0])
	}

	switch name {
	case "build", "run", "test", "lock":
		if !manifestExists(rest) {
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
	"policy": "输出单文件内存策略判定 JSON（S2 §15.1；开发预览命令）",
	"build":  "校验清单并构建产物（阶段：validate→compile→test→package→install）",
	"run":    "构建并运行 app 入口",
	"test":   "运行测试入口（src/test/x）",
	"fmt":    "格式化 xnull.project / .xmeta / .xplugin / xnull.lock",
	"lock":   "校验或重生成锁文件（--update-lock 为唯一重生成入口）",
}

func commandList() string {
	out := ""
	for _, name := range []string{"build", "run", "test", "fmt", "lock", "policy"} {
		if out != "" {
			out += "、"
		}
		out += name
	}
	return out
}

func writeUsage(w io.Writer) {
	fmt.Fprintf(w, "xnull %s —— XNull 工具链\n\n用法：xnull <command> [flags]\n\n命令：\n", Version)
	for _, name := range []string{"build", "run", "test", "fmt", "lock", "policy"} {
		fmt.Fprintf(w, "  %-6s %s\n", name, commands[name])
	}
	fmt.Fprintf(w, "\n退出码：0 成功 / 1 构建失败 / 2 清单或用法错误 / 130 中断\n")
}

// parseFlags 只校验形态：当前阶段命令参数集尚未冻结，未知长参数即用法错误。
func parseFlags(args []string) *diag.Diagnostic {
	for _, a := range args {
		if len(a) > 1 && a[0] == '-' && a[1] == '-' {
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

var knownFlags = map[string]struct{}{
	"--update-lock": {}, "--skip": {}, "--profile": {}, "--check": {},
	"--emit": {}, "--offline": {}, "--verbose": {},
	"--interp": {}, "--runtime": {}, "-o": {},
}

// manifestExists 从当前目录向上查找 xnull.project。
func manifestExists(args []string) bool {
	if _, err := os.Stat("xnull.project"); err == nil {
		return true
	}
	return false
}

func notImplemented(env Env, name string) int {
	msg := fmt.Sprintf("命令 %q 尚未实现", name)
	fmt.Fprintf(env.Stderr, "xnull: %s\n", msg)
	return exitcode.Usage
}

// runFile 执行单个 .xn 文件：解析 → 解释执行。
// 退出码：0 成功；1 语法/运行错误（含 fatal）；2 文件不可读。
func runFile(env Env, path string, extraArgs []string) int {
	// --interp：解释器调试模式（M4.3）；默认走编译路径（正式路径）。
	for _, a := range extraArgs {
		if a == "--interp" {
			return interpFile(env, path, extraArgs)
		}
	}
	return runCompiled(env, path)
}

// runCompiled 编译路径：临时目录构建可执行并运行，透传退出码（M4.2/4.3）。
func runCompiled(env Env, path string) int {
	runtimeDir := ""
	for _, cand := range []string{"impl/runtime", "../impl/runtime", "../../impl/runtime", "../../runtime", "runtime"} {
		if st, err := os.Stat(filepath.Join(cand, "rt.h")); err == nil && !st.IsDir() {
			runtimeDir = cand
			break
		}
	}
	if runtimeDir == "" {
		if runtimeDir = os.Getenv("XNULL_RUNTIME"); runtimeDir == "" {
			fmt.Fprintln(env.Stderr, "xnull: 找不到运行时源码目录（rt.h）；用 XNULL_RUNTIME 指定")
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
	cmd := exec.Command(bin)
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
func interpFile(env Env, path string, extraArgs []string) int {
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
	code, err := interp.Run(u, env.Stdout, extraArgs)
	if err != nil {
		fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
	}
	return code
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
	out := "prog"
	runtimeDir := ""
	for i := 1; i < len(rest)-1; i++ {
		switch rest[i] {
		case "-o":
			out = rest[i+1]
		case "--runtime":
			runtimeDir = rest[i+1]
		}
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
	return codegen.Build(srcPath, out, runtimeDir, env.Stderr)
}
