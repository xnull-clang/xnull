package codegen

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"xnull.dev/xnull/internal/sema"
)

// Build 端到端构建：XNull 源文件 → C → cc → 可执行文件（M4.2）。
// 返回进程退出码；诊断写 stderr。
func Build(srcPath, outPath, runtimeDir string, stderr io.Writer) int {
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
	cc := exec.Command("cc", "-std=c11", "-O2", "-I", runtimeDir, "-o", outPath, cfile,
		filepath.Join(runtimeDir, "rt.c"),
		filepath.Join(runtimeDir, "rt_gc.c"),
		filepath.Join(runtimeDir, "rt_policy.c"),
		filepath.Join(runtimeDir, "rt_weak.c"))
	cc.Stderr = stderr
	cc.Stdout = stderr
	if err := cc.Run(); err != nil {
		fmt.Fprintf(stderr, "xnull: C 编译失败：%v\n", err)
		return 1
	}
	return 0
}
