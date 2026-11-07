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
	// MemPolicy 是 §23 的 GC 策略选择："" / "auto"（缺省）按 §15.1 判定；
	// "arc" / "gc" 强制全部类的分配种类（数据枚举/单例仍按规范为 GC）。
	MemPolicy string
	// Stats 打开运行期分配统计与 GC 指标（§21/§23）；报告写 stderr。
	Stats bool
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
	"rt_std_bytes.c",
	"rt_task.c",
	"rt_sync.c",
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
	// FFI 绑定（P-09）：工程根（入口文件所在目录）的 .xfb 入口注入为包级声明。
	reg, fdiags, ferr := LoadFFI(filepath.Dir(srcPath))
	if ferr != nil {
		fmt.Fprintf(stderr, "xnull: 读取 .xfb 绑定失败：%v\n", ferr)
		return 1
	}
	if len(fdiags) > 0 {
		for _, d := range fdiags {
			fmt.Fprintln(stderr, d)
		}
		return 1
	}
	if err := InjectFFI(u, reg); err != nil {
		fmt.Fprintf(stderr, "xnull: %v\n", err)
		return 1
	}
	// 句柄类型（File/Dir…）由绑定层注入，不在源码中声明；
	// 登记后再做 sema 的签名类型可见性检查。
	sema.RegisterExternalTypes(FFIHandleTypes(reg)...)
	for _, note := range UnsupportedFFIEntries(reg) {
		fmt.Fprintf(stderr, "xnull: 提示：%s（调用将报未定义标识符）\n", note)
	}
	res, sd := sema.AnalyzeWith(srcPath, u)
	if len(sd) > 0 {
		for _, d := range sd {
			fmt.Fprintln(stderr, d)
		}
		return 1
	}
	// BND-10：策略判定随编译单元一起交给 codegen（类分配种类 arc/gc）。
	var strategies []sema.Strategy
	if res != nil {
		strategies = res.Strategies(u)
	}
	// 入口校验（§11.2/§11.4）：缺失/重复/签名非法都是编译错误，不落到 cc。
	if err := RequireEntry(u); err != nil {
		fmt.Fprintf(stderr, "xnull: %v\n", err)
		return 1
	}
	csrc, err := EmitCWithBuildOptions(u, reg, strategies, opts)
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
	args := []string{"-std=c11", "-O2", "-pthread", "-I", runtimeDir, "-o", outPath, cfile}
	for _, src := range runtimeCSources {
		args = append(args, filepath.Join(runtimeDir, src))
	}
	args = append(args, linkArgs...)
	return args
}
