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
	// ResC 是工程资源表 C 源（由 `xnull dev res` 生成）；为空时使用内置空表。
	// S6-04：资源表与 rt_std_res.c 一起进入产物链接。
	ResC string
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
	"rt_std_res.c",
	"rt_std_res_empty.c",
}

// emptyResourceTableC 是零资源工程的资源表：count=0、get 恒失败、at 恒失败。
// 保证 rt_std_res.c 引用的 xrt_resource_* 符号在任何产物中都有定义（S8 §5.6 空表零成本）。
const emptyResourceTableC = `/* 由 xnull build 生成：零资源工程空表（S8 §5.6） */
#include <stddef.h>
#include <string.h>

size_t xrt_resource_count(void) { return 0; }

int xrt_resource_get(const char *name, size_t nlen,
                     const unsigned char **out, size_t *out_len) {
    (void)name; (void)nlen;
    *out = 0; *out_len = 0;
    return 1;
}

int xrt_resource_at(size_t i, const char **name, size_t *nlen,
                    const unsigned char **out, size_t *out_len) {
    (void)i;
    *name = 0; *nlen = 0; *out = 0; *out_len = 0;
    return 1;
}
`

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
	// S7-04：@unsafe 受控入口需要工程清单 link.unsafe = true（S7 §8 / S8 §7）。
	if err := checkUnsafeGate(filepath.Dir(srcPath), reg, stderr); err != nil {
		fmt.Fprintf(stderr, "xnull: %v\n", err)
		return 1
	}
	// S8-07：读取 link.libraries，交叉校验 FFI 区域，并并入链接参数。
	if root := findProjectRoot(filepath.Dir(srcPath)); root != "" {
		libs, hasLibraries, lerr := readLinkLibraries(root)
		if lerr != nil {
			fmt.Fprintf(stderr, "xnull: %v\n", lerr)
			return 1
		}
		if hasLibraries {
			if err := checkFFILibraries(reg, libs, true); err != nil {
				fmt.Fprintf(stderr, "xnull: %v\n", err)
				return 1
			}
			opts.LinkArgs = mergeLinkArgs(opts.LinkArgs, libs)
		}
	}
	if err := InjectFFI(u, reg); err != nil {
		fmt.Fprintf(stderr, "xnull: %v\n", err)
		return 1
	}
	// 句柄类型（File/Dir…）由绑定层注入，不在源码中声明；
	// 登记后再做 sema 的签名类型可见性检查。
	sema.RegisterExternalTypes(FFIHandleTypes(reg)...)
	// FFI-01：同步 FFI 以 Result<T, ErrorKind> 暴露，ErrorKind 需对 sema 可见。
	for _, e := range reg.Entries {
		if ffiReturnsResult(e) {
			sema.RegisterExternalTypes("ErrorKind")
			break
		}
	}
	// S7-01：把 .xfb 的 layout/入口签名投射给 sema（调用点类型检查）。
	if err := RegisterFFIProjection(reg); err != nil {
		fmt.Fprintf(stderr, "xnull: FFI 投射失败：%v\n", err)
		return 1
	}
	sema.RegisterExternalTypes("Process")
	// S6-03：sys *Async / Process 入口（Context 与出参形态无法写进 .xfb）。
	// 仅当工程绑定层已有 File/Dir 句柄时注入，避免无 sys 绑定的工程被塞入未用声明。
	if regHasHandle(reg, "File") && regHasHandle(reg, "Dir") {
		if err := InjectSys603(u); err != nil {
			fmt.Fprintf(stderr, "xnull: %v\n", err)
			return 1
		}
		// S6-04：内嵌资源读取（Result/Bytes/Text/List 形态无法写进 .xfb）。
		if err := InjectS604(u); err != nil {
			fmt.Fprintf(stderr, "xnull: %v\n", err)
			return 1
		}
	}
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
	// 资源表（S6-04）：工程表由调用方生成；缺省写零资源空表，保证 xrt_resource_* 符号闭合。
	resC := opts.ResC
	if resC == "" {
		resC = outPath + ".res.c"
		if err := os.WriteFile(resC, []byte(emptyResourceTableC), 0o644); err != nil {
			fmt.Fprintf(stderr, "xnull: 无法写出资源表 %s：%v\n", resC, err)
			return 1
		}
	}
	cc := exec.Command("cc", buildCCArgs(outPath, cfile, runtimeDir, resC, opts.LinkArgs)...)
	cc.Stderr = stderr
	cc.Stdout = stderr
	if err := cc.Run(); err != nil {
		fmt.Fprintf(stderr, "xnull: C 编译失败：%v\n", err)
		return 1
	}
	return 0
}

// buildCCArgs 组装 cc 参数：旗标 → 输出 → 生成源 → 运行时 C 源 → 资源表 → LinkArgs。
// LinkArgs 必须排在全部目标文件之后（链接顺序敏感，P-10 条件 3）。
func buildCCArgs(outPath, cfile, runtimeDir, resC string, linkArgs []string) []string {
	args := []string{"-std=c11", "-O2", "-pthread", "-I", runtimeDir, "-o", outPath, cfile}
	for _, src := range runtimeCSources {
		args = append(args, filepath.Join(runtimeDir, src))
	}
	if resC != "" {
		args = append(args, resC)
	}
	args = append(args, linkArgs...)
	return args
}
