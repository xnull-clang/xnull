package codegen

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"xnull.dev/xnull/internal/sema"
)

// Options 是构建可选参数。
type Options struct {
	// LinkArgs 追加在全部 C 目标文件之后（链接顺序敏感；S8 §7 / P-10 条件 3）。
	// 调用方应使用 ffi.LinkArgs 生成（去重 + 升序）；本包不再排序。
	LinkArgs []string
}

// runtimeCSources 是构建时必须一起编译/链接的 C 源（相对运行时目录，顺序固定）。
// M6-B0-02（P-10）：纳入 xrt_abi.c 与 rt_std_*.c；顺序固定保证确定性（P-10 条件 1/2）。
var runtimeCSources = []string{
	"rt.c",
	"rt_gc.c",
	"rt_policy.c",
	"rt_weak.c",
	"xrt_abi.c",
	"rt_std_runtime.c",
	"rt_std_text.c",
	"rt_std_sys.c",
}

// Build 端到端构建：XNull 源文件 → C → cc → 可执行文件（M4.2）。
// 返回进程退出码；诊断写 stderr。
func Build(srcPath, outPath, runtimeDir string, stderr io.Writer) int {
	return BuildWithOptions(srcPath, outPath, runtimeDir, Options{}, stderr)
}

// BuildWithOptions 同 Build，额外接受构建参数（P-10：LinkArgs 注入）。
func BuildWithOptions(srcPath, outPath, runtimeDir string, opts Options, stderr io.Writer) int {
	// 多文件编译单元（M5.2 前置）：入口 + import 闭包，合并为单一单元。
	u, pdiags := LoadUnits(srcPath)
	if u == nil && len(pdiags) == 0 {
		fmt.Fprintf(stderr, "xnull: 无法读取文件 %s\n", srcPath)
		return 2
	}
	if len(pdiags) > 0 {
		for _, d := range pdiags {
			fmt.Fprintln(stderr, d)
		}
		return 1
	}
	if sd := sema.Analyze(srcPath, u); len(sd) > 0 {
		for _, d := range sd {
			fmt.Fprintln(stderr, d)
		}
		return 1
	}
	csrc, err := EmitC(u)
	if err != nil {
		fmt.Fprintf(stderr, "xnull: 代码生成失败：%v\n", err)
		return 1
	}
	cfile := outPath + ".c"
	if err := os.WriteFile(cfile, []byte(csrc), 0o644); err != nil {
		fmt.Fprintf(stderr, "xnull: 无法写出 %s：%v\n", cfile, err)
		return 1
	}
	cc := exec.Command("cc", buildCCArgs(outPath, cfile, runtimeDir, opts.LinkArgs)...)
	cc.Stderr = stderr
	cc.Stdout = stderr
	if err := cc.Run(); err != nil {
		fmt.Fprintf(stderr, "xnull: C 编译失败：%v\n", err)
		return 1
	}
	return 0
}

// buildCCArgs 组装 cc 参数：旗标 → 输出 → 生成源 → 运行时 C 源 → LinkArgs。
// LinkArgs 必须排在全部目标文件之后（链接顺序敏感，P-10 条件 3）。
func buildCCArgs(outPath, cfile, runtimeDir string, linkArgs []string) []string {
	args := []string{"-std=c11", "-O2", "-I", runtimeDir, "-o", outPath, cfile}
	for _, src := range runtimeCSources {
		args = append(args, filepath.Join(runtimeDir, src))
	}
	args = append(args, linkArgs...)
	return args
}
