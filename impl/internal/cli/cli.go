// Package cli 是 xnull 命令行的入口分派与用法校验。
package cli

import (
	"fmt"
	"io"
	"os"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/exitcode"
)

// Version 工具链版本；与清单 properties.xdk-version 的校验在 M3 接入。
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
	"build": "校验清单并构建产物（阶段：validate→compile→test→package→install）",
	"run":   "构建并运行 app 入口",
	"test":  "运行测试入口（src/test/x）",
	"fmt":   "格式化 xnull.project / .xmeta / .xplugin / xnull.lock",
	"lock":  "校验或重生成锁文件（--update-lock 为唯一重生成入口）",
}

func commandList() string {
	out := ""
	for _, name := range []string{"build", "run", "test", "fmt", "lock"} {
		if out != "" {
			out += "、"
		}
		out += name
	}
	return out
}

func writeUsage(w io.Writer) {
	fmt.Fprintf(w, "xnull %s —— XNull 工具链\n\n用法：xnull <command> [flags]\n\n命令：\n", Version)
	for _, name := range []string{"build", "run", "test", "fmt", "lock"} {
		fmt.Fprintf(w, "  %-6s %s\n", name, commands[name])
	}
	fmt.Fprintf(w, "\n退出码：0 成功 / 1 构建失败 / 2 清单或用法错误 / 130 中断\n")
}

// parseFlags 只校验形态：M0 阶段命令参数集尚未冻结，未知长参数即用法错误。
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
}

// manifestExists 从当前目录向上查找 xnull.project。
func manifestExists(args []string) bool {
	if _, err := os.Stat("xnull.project"); err == nil {
		return true
	}
	return false
}

func notImplemented(env Env, name string) int {
	msg := fmt.Sprintf("命令 %q 尚未实现（M0 骨架）", name)
	fmt.Fprintf(env.Stderr, "xnull: %s\n", msg)
	return exitcode.Usage
}

func fail(env Env, d diag.Diagnostic) int {
	fmt.Fprintln(env.Stderr, d.String())
	return exitcode.Usage
}
