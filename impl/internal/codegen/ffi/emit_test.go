package ffi

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// 本测试验证 M4.5b/c 的生成面：.xfb → 校验 → 包装 C 代码 → cc 编译 → 运行。
// 原生侧是测试内自建的确定性小库（含越界写诱饵与句柄计数），不依赖系统库。

const nativeXfb = `ffi native {
  layout(c) struct Pair {
    Int64 a
    Int32 b
  }

  handle Conn { close = ffiConnClose }

  errorMap {
    5 = NotFound
  }

  @ffiEntry(cName = "native_add")
  @lease(a = .borrow, b = .borrow)
  @blocking(.aware)
  Int64 ffiAdd(Int64 a, Int64 b);

  @ffiEntry(cName = "native_strlen")
  @lease(s = .borrow, code = .borrow)
  @errorCode(codeParam = .code)
  @blocking(.aware)
  Int64 ffiStrLen(String s, Int32 code);

  @ffiEntry(cName = "native_open")
  @lease(name = .borrow, out = .transfer)
  @errorCode(codeParam = .result)
  @blocking(.unaware)
  Int32 ffiOpen(String name, Conn out);

  @ffiEntry(cName = "native_fill")
  @lease(buf = .borrow)
  @blocking(.aware)
  Int64 ffiFill(Bytes buf);

  @ffiEntry(cName = "native_conn_read")
  @lease(c = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.unaware)
  Int32 ffiConnRead(Conn c);

  @ffiEntry(cName = "native_conn_reclaim")
  @lease(c = .reclaim)
  @errorCode(codeParam = .result)
  @blocking(.aware)
  Int32 ffiConnReclaim(Conn c);

  @ffiEntry(cName = "native_conn_close")
  @lease(c = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.aware)
  Int32 ffiConnClose(Conn c);
}
`

// nativeC 是原生侧实现：句柄以 0x1234 魔数代表，close 计数供幂等断言。
const nativeC = `#include <stdint.h>
#include <stddef.h>
#include <string.h>

static int g_close_total = 0;

int64_t native_add(int64_t a, int64_t b) { return a + b; }

int64_t native_strlen(const char *s, size_t n) { (void)s; return (int64_t)n; }

int32_t native_fill(void *buf, size_t n) {
    memset(buf, 'x', n + 2); /* 故意越界写：canary 必须检出 */
    return (int32_t)n;
}

int32_t native_open(const char *name, size_t n, void **out) {
    (void)name; (void)n;
    *out = (void *)0x1234;
    return 0;
}

int32_t native_conn_read(void *c) { return c == (void *)0x1234 ? 5 : 99; }

int32_t native_conn_close(void *c) { (void)c; g_close_total++; return 0; }

static int g_reclaim_total = 0;

int32_t native_conn_reclaim(void *c) {
    if (c == (void *)0x1234) {
        g_reclaim_total++; /* 原生接管所有权 */
        return 0;
    }
    return 99;
}

int g_native_reclaim_total(void) { return g_reclaim_total; }

int g_native_close_total(void) { return g_close_total; }
`

// harnessMain 消费生成包装：覆盖标量往返、String 借出、句柄移交/关闭幂等、
// 错误码分类（已知/未知）、布局尺寸核对与 canary 越界（子进程模式）。
const harnessMain = `
#include <stdio.h>
#include <string.h>

extern int g_native_close_total(void);
extern int g_native_reclaim_total(void);

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "canary") == 0) {
        uint8_t buf[4] = {0};
        int64_t v = 0;
        (void)xn_ffi_ffiFill(buf, 4, &v);
        printf("canary-missed\n");
        return 0;
    }
    if (argc > 1 && strcmp(argv[1], "layout") == 0) {
        xn_layout_Pair_check(sizeof(xn_layout_Pair) + 1);
        printf("layout-missed\n");
        return 0;
    }

    int64_t v = 0;
    int32_t rc = xn_ffi_ffiAdd(2, 3, &v);
    printf("add rc=%d v=%lld\n", rc, (long long)v);

    int64_t n = 0;
    rc = xn_ffi_ffiStrLen("hello", 5, &n);
    printf("strlen rc=%d n=%lld\n", rc, (long long)n);

    xrt_handle *h = NULL;
    rc = xn_ffi_ffiOpen("conn-1", 6, &h);
    printf("open rc=%d handle=%d\n", rc, h != NULL);

    rc = xn_ffi_ffiConnRead(h);
    printf("read rc=%d kind=%s\n", rc, xn_ffi_native_error_kind(rc));

    printf("close1 rc=%d\n", xn_ffi_ffiConnClose(h));
    printf("close2 rc=%d\n", xn_ffi_ffiConnClose(h));
    printf("close_total=%d\n", g_native_close_total());
    printf("unknown=%s\n", xn_ffi_native_error_kind(99));

    /* 归还（.reclaim）：所有权移交回原生，包装对象登记关闭 */
    xrt_handle *h2 = NULL;
    if (xn_ffi_ffiOpen("conn-2", 6, &h2) != 0 || h2 == NULL) {
        printf("open2-fail\n");
        return 1;
    }
    printf("reclaim=%d reclaim_total=%d closed=%d\n",
           xn_ffi_ffiConnReclaim(h2), g_native_reclaim_total(), xrt_handle_is_closed(h2));

    xn_layout_Pair_check(sizeof(xn_layout_Pair));
    printf("layout_ok=1\n");
    return 0;
}
`

func findCC(t *testing.T) string {
	t.Helper()
	for _, name := range []string{"cc", "clang", "gcc"} {
		if p, err := exec.LookPath(name); err == nil {
			return p
		}
	}
	t.Skip("无 C 编译器，跳过生成面端到端测试")
	return ""
}

func runtimeDir(t *testing.T) string {
	t.Helper()
	p, err := filepath.Abs(filepath.Join("..", "..", "..", "runtime"))
	if err != nil {
		t.Fatalf("runtime 目录解析失败：%v", err)
	}
	if _, err := os.Stat(filepath.Join(p, "xrt.h")); err != nil {
		t.Skipf("运行时目录不可用（%s），跳过", p)
	}
	return p
}

func loadNative(t *testing.T) *Registry {
	t.Helper()
	root := t.TempDir()
	writeXfb(t, root, "bindings/native.xfb", nativeXfb)
	reg, diags, err := Load(root)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(diags) != 0 {
		t.Fatalf("正例不应有诊断：%v", codeList(diags))
	}
	return reg
}

func TestEmitSupportEndToEnd(t *testing.T) {
	cc := findCC(t)
	rtDir := runtimeDir(t)
	reg := loadNative(t)

	sup := reg.EmitSupport()
	if len(sup.Problems) != 0 {
		t.Fatalf("支撑代码生成有问题：%v", sup.Problems)
	}
	for _, sym := range []string{
		"xn_ffi_ffiAdd", "xn_ffi_ffiStrLen", "xn_ffi_ffiOpen",
		"xn_ffi_ffiConnRead", "xn_ffi_ffiConnClose",
		"xn_ffi_native_error_kind", "xn_layout_Pair",
	} {
		if !strings.Contains(sup.Text, sym) {
			t.Fatalf("支撑代码缺少 %s", sym)
		}
	}

	dir := t.TempDir()
	prog := filepath.Join(dir, "prog.c")
	src := sup.Text + harnessMain
	if err := os.WriteFile(prog, []byte(src), 0o644); err != nil {
		t.Fatalf("写 prog.c：%v", err)
	}
	nativePath := filepath.Join(dir, "native.c")
	if err := os.WriteFile(nativePath, []byte(nativeC), 0o644); err != nil {
		t.Fatalf("写 native.c：%v", err)
	}
	exe := filepath.Join(dir, "prog")
	args := []string{"-std=c11", "-O2", "-Wall", "-Wno-unused-function", "-I", rtDir, "-o", exe, prog, nativePath}
	for _, f := range []string{"rt.c", "rt_gc.c", "rt_policy.c", "rt_weak.c", "xrt_abi.c"} {
		args = append(args, filepath.Join(rtDir, f))
	}
	build := exec.Command(cc, args...)
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("cc 失败：%v\n%s", err, out)
	}

	run := exec.Command(exe)
	out, err := run.CombinedOutput()
	if err != nil {
		t.Fatalf("运行失败：%v\n%s", err, out)
	}
	want := strings.Join([]string{
		"add rc=0 v=5",
		"strlen rc=0 n=5",
		"open rc=0 handle=1",
		"read rc=5 kind=NotFound",
		"close1 rc=0",
		"close2 rc=0",
		"close_total=1",
		"unknown=Internal",
		"reclaim=0 reclaim_total=1 closed=1",
		"layout_ok=1",
	}, "\n")
	if got := strings.TrimSpace(string(out)); got != want {
		t.Fatalf("输出不符\n got:\n%s\nwant:\n%s", got, want)
	}

	// canary：原生越界写必须终止进程（S7 §9 INV-FFI-5），不得静默通过
	for _, mode := range []string{"canary", "layout"} {
		c := exec.Command(exe, mode)
		o, err := c.CombinedOutput()
		if err == nil {
			t.Fatalf("%s 模式应终止进程（合同违规），实际通过：%s", mode, o)
		}
		if strings.Contains(string(o), mode+"-missed") {
			t.Fatalf("%s 模式未检出违规：%s", mode, o)
		}
	}
}

func TestEmitSupportReportsUnsupported(t *testing.T) {
	root := t.TempDir()
	writeXfb(t, root, "bindings/sqlite.xfb", positiveSrc)
	reg, diags, err := Load(root)
	if err != nil || len(diags) != 0 {
		t.Fatalf("Load 失败：%v %v", err, codeList(diags))
	}
	sup := reg.EmitSupport()
	if len(sup.Problems) == 0 {
		t.Fatalf("Bytes 移交形态应记为未覆盖，实际无 Problems")
	}
	joined := strings.Join(sup.Problems, "；")
	if !strings.Contains(joined, "ffiSqliteExec") {
		t.Fatalf("未覆盖入口应在 Problems 中指明：%v", sup.Problems)
	}
	if strings.Contains(sup.Text, "xn_ffi_ffiSqliteExec(") {
		t.Fatalf("未覆盖入口不得生成静默占位函数")
	}
}

func TestTrampolineReserved(t *testing.T) {
	root := t.TempDir()
	writeXfb(t, root, "bindings/native.xfb", nativeXfb)
	reg, diags, err := Load(root)
	if err != nil || len(diags) != 0 {
		t.Fatalf("Load 失败：%v %v", err, codeList(diags))
	}
	sn, err := reg.EmitTrampoline("ffiConnRead")
	if err == nil || !errors.Is(err, ErrTrampolineReserved) {
		t.Fatalf("trampoline 应显式预留（不硬做）：%v", err)
	}
	if sn.Text != "" {
		t.Fatalf("预留形态不得产出代码")
	}
	if _, err := reg.EmitTrampoline("nope"); err == nil {
		t.Fatalf("未声明入口应返回错误")
	}
}

func TestLinkArgsAndManifest(t *testing.T) {
	libs := []LinkLib{
		{Name: "z", Kind: "static"},
		{Name: "sqlite3", Kind: "dynamic", System: true},
		{Name: "z", Kind: "static"}, // 重复声明：去重（P-10 条件 3）
	}
	if got, want := LinkArgs(libs), []string{"-lsqlite3", "-lz"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("LinkArgs 应去重且升序：%v，want %v", got, want)
	}
	if got := LinkArgs(nil); len(got) != 0 {
		t.Fatalf("无库时应为空（空路径零成本）")
	}

	root := t.TempDir()
	writeXfb(t, root, "bindings/sqlite.xfb", positiveSrc)
	reg, diags, err := Load(root)
	if err != nil || len(diags) != 0 {
		t.Fatalf("Load 失败：%v %v", err, codeList(diags))
	}
	rows := reg.BlockingManifest()
	if len(rows) != len(reg.Entries) {
		t.Fatalf("清单行数 %d != 入口数 %d", len(rows), len(reg.Entries))
	}
	for i := 1; i < len(rows); i++ {
		if rows[i-1].Entry > rows[i].Entry {
			t.Fatalf("清单未按入口名排序")
		}
	}
	seen := false
	for _, r := range rows {
		if r.Entry == "ffiSqliteExec" {
			seen = true
			if r.Class != ".unaware" || !r.LongRunning || r.Companion != "submitffiSqliteExec" {
				t.Fatalf("长阻塞行不符：%+v", r)
			}
		}
	}
	if !seen {
		t.Fatalf("清单缺少 ffiSqliteExec")
	}
}
