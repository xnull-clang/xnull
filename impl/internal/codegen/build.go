package codegen

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"xnull.dev/xnull/internal/sema"
)

// resolveFFIRoot 决定构建时加载 .xfb 的根目录（P-09）：
//  1. 入口目录（含子目录）有 .xfb：保持原行为，返回入口目录；
//  2. 否则自入口目录向上逐级查找 bindings，找到即停：
//     bindings 下有 .xfb 则返回 bindings（仓库级 canonical 绑定，
//     供 impl/lib/* 下 import xdk.* 的入口使用）；没有则返回入口目录；
//  3. 到仓库根（存在 .git）或文件系统根仍未找到 bindings：返回入口目录。
//
// 绑定查找只影响 Go 侧 sema/codegen 的声明注入，不改变无绑定工程的既有行为。
func resolveFFIRoot(start string) (root string, ascended bool) {
	dir, err := filepath.Abs(start)
	if err != nil {
		return start, false
	}
	if hasXfbFiles(dir) {
		return start, false
	}
	for cur := dir; ; {
		b := filepath.Join(cur, "bindings")
		if st, err := os.Stat(b); err == nil && st.IsDir() {
			if hasXfbFiles(b) {
				return b, true
			}
			return start, false
		}
		if _, err := os.Stat(filepath.Join(cur, ".git")); err == nil {
			return start, false
		}
		parent := filepath.Dir(cur)
		if parent == cur {
			return start, false
		}
		cur = parent
	}
}

// hasXfbFiles 报告 root 下是否存在 .xfb（跳过隐藏目录与 target，与 ffi.Load 一致）。
func hasXfbFiles(root string) bool {
	found := false
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if path != root {
				name := d.Name()
				if strings.HasPrefix(name, ".") || name == "target" {
					return fs.SkipDir
				}
			}
			return nil
		}
		if strings.HasSuffix(d.Name(), ".xfb") {
			found = true
			return fs.SkipAll
		}
		return nil
	})
	return found
}

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
	// EmitOnly 只生成 C（写 <out>.c），不生成资源表、不调用 cc（B3-00 差分）。
	EmitOnly bool
	// SrcPath 用于 #line 诊断映射（装配处填写；空则只写行号）。
	SrcPath string
	// Mode 是清单 build.mode（S8 §5.2）：""/"release" = -O2，"debug" = -O0 -g，"size" = -Os。
	Mode string
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
	"rt_std_net.c",
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
	// FFI 绑定（P-09）：入口目录优先；入口目录无 .xfb 时向上找仓库 bindings/
	// （B4b：impl/lib/* 入口 import xdk.*，绑定在仓库根 bindings/xdk/*.xfb）。
	// 向上找到的绑定只保留编译单元实际引用的入口，避免给无关入口注入全量 XDK
	// 绑定而改变既有 C 输出（入口目录本地 .xfb 仍全量加载，保持原行为）。
	ffiRoot, ascended := resolveFFIRoot(filepath.Dir(srcPath))
	reg, fdiags, ferr := LoadFFI(ffiRoot)
	if ferr == nil && ascended {
		// 仓库级绑定只用于“纯 FFI”入口。若编译单元同时依赖 codegen 内建
		// 降级的 xdk 入口（env/nowMono/diagnose/S6-03/S6-04/S6-09），canonical
		// .xfb 签名与语言面内建签名可能冲突（例：nowMono Int64 vs Int），
		// 回退入口目录的空绑定，保持内建路径与既有输出不变。
		if usesBuiltinXDK(u, reg) {
			reg, fdiags, ferr = LoadFFI(filepath.Dir(srcPath))
			ascended = false
		} else {
			reg = FilterFFIRegistryByUse(u, reg)
		}
	}
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
	// 向上找到的绑定只用于 codegen 的 FFI 发射（g.ffiEntries）；不再注入声明，
	// 语言面签名继续由 sema 的 xdk 内建表提供。否则 canonical .xfb 的签名
	// （如 fileClose/fileOpenRead 的 Int32 形态）会覆盖语言面签名，改变既有
	// sema 判定与 C 输出（B3-09 负例会被意外放行）。
	if !ascended {
		if err := InjectFFI(u, reg); err != nil {
			fmt.Fprintf(stderr, "xnull: %v\n", err)
			return 1
		}
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
	// S6-09：net Async/HTTP 内建（Context 首参）。
	if regHasHandle(reg, "Socket") {
		if err := InjectNet609(u); err != nil {
			fmt.Fprintf(stderr, "xnull: %v\n", err)
			return 1
		}
	}
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
	opts.SrcPath = srcPath
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
	if opts.EmitOnly {
		return 0
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
	cc := exec.Command("cc", buildCCArgs(outPath, cfile, runtimeDir, resC, opts.LinkArgs, opts.Mode)...)
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
func buildCCArgs(outPath, cfile, runtimeDir, resC string, linkArgs []string, mode string) []string {
	opt := []string{"-O2"}
	switch mode {
	case "debug":
		opt = []string{"-O0", "-g"}
	case "size":
		opt = []string{"-Os"}
	}
	args := append([]string{"-std=c11"}, opt...)
	args = append(args, "-pthread", "-I", runtimeDir, "-o", outPath, cfile)
	for _, src := range runtimeCSources {
		args = append(args, filepath.Join(runtimeDir, src))
	}
	if resC != "" {
		args = append(args, resC)
	}
	args = append(args, linkArgs...)
	return args
}
