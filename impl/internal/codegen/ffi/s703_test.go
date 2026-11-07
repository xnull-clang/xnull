package ffi

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// S7-03：回调声明 → typed trampoline → env 根生命周期/注销后调用/回调 panic。
// 运行时面（xrt_callback_env_*）由 E5 提供；本卡只消费，不重复实现。

const s703Xfb = `ffi native {
  callback LogCb(Int32, Int64) -> Int64;
  callback Notify(Int64) -> Void;

  @ffiEntry(cName = "native_ping")
  @lease(x = .borrow)
  @blocking(.aware)
  Int64 ffiPing(Int64 x);
}
`

const s703Native = `#include <stdint.h>
int64_t native_ping(int64_t x) { return x + 1; }
`

const s703Harness = `
#include <stdio.h>
#include <string.h>

static int32_t s703_log_fn(void *caps, const xn_tramp_LogCb_args *a, int64_t *res) {
    int64_t *n = (int64_t *)caps;
    (*n)++;
    *res = (int64_t)a->p0 + a->p1;
    return 0;
}

static int32_t s703_notify_fn(void *caps, const xn_tramp_Notify_args *a) {
    int64_t *n = (int64_t *)caps;
    *n = a->p0;
    return 0;
}

static int32_t s703_panic_fn(void *caps, const xn_tramp_LogCb_args *a, int64_t *res) {
    (void)caps; (void)a; (void)res;
    return 7; /* 回调内 panic：非 0 状态由 trampoline 转 fatal（S7 §5.3） */
}

int main(int argc, char **argv) {
    int64_t n = 0;
    xn_tramp_LogCb_closure lc = { s703_log_fn, &n };
    xrt_callback_env *env = xn_tramp_LogCb_new(&lc);
    xn_tramp_LogCb_args a = { 3, 4 };
    int64_t r = 0;
    int32_t st = xn_tramp_LogCb_invoke(env, &a, &r);
    printf("log st=%d r=%lld n=%lld alive=%d\n", (int)st, (long long)r, (long long)n,
           xrt_callback_env_alive(env));

    xn_tramp_Notify_closure nc = { s703_notify_fn, &n };
    xrt_callback_env *nenv = xn_tramp_Notify_new(&nc);
    xn_tramp_Notify_args na = { 9 };
    st = xn_tramp_Notify_invoke(nenv, &na);
    printf("notify st=%d n=%lld\n", (int)st, (long long)n);
    xn_tramp_Notify_destroy(nenv);

    xn_tramp_LogCb_destroy(env);
    printf("destroyed alive=%d\n", xrt_callback_env_alive(env));

    if (argc > 1 && strcmp(argv[1], "destroyed") == 0) {
        xn_tramp_LogCb_invoke(env, &a, &r);
        printf("destroyed-missed\n");
        return 0;
    }
    if (argc > 1 && strcmp(argv[1], "panic") == 0) {
        xn_tramp_LogCb_closure pc = { s703_panic_fn, NULL };
        xrt_callback_env *pe = xn_tramp_LogCb_new(&pc);
        xn_tramp_LogCb_invoke(pe, &a, &r);
        printf("panic-missed\n");
        return 0;
    }
    return 0;
}
`

func buildS703(t *testing.T) string {
	t.Helper()
	cc := findCC(t)
	rtDir := runtimeDir(t)

	root := t.TempDir()
	writeXfb(t, root, "bindings/native.xfb", s703Xfb)
	reg, diags, err := Load(root)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(diags) != 0 {
		t.Fatalf("正例不应有诊断：%v", codeList(diags))
	}
	if len(reg.Callbacks) != 2 {
		t.Fatalf("应登记 2 个回调，得到 %d", len(reg.Callbacks))
	}

	sup := reg.EmitSupport()
	if len(sup.Problems) != 0 {
		t.Fatalf("支撑代码生成有问题：%v", sup.Problems)
	}
	for _, sym := range []string{
		"xn_tramp_LogCb_args", "xn_tramp_LogCb_closure", "xn_tramp_LogCb_adapt",
		"xn_tramp_LogCb_new", "xn_tramp_LogCb_destroy", "xn_tramp_LogCb_invoke",
		"xn_tramp_Notify_invoke", "xrt_callback_env_new", "xrt_callback_env_destroy",
		"xrt_callback_env_invoke",
	} {
		if !strings.Contains(sup.Text, sym) {
			t.Fatalf("trampoline 支撑代码缺少 %q：\n%s", sym, sup.Text)
		}
	}
	if strings.Contains(sup.Text, "xn_tramp_ffiPing_args") {
		t.Fatalf("回调 trampoline 不应按入口名生成参数结构")
	}

	dir := t.TempDir()
	prog := filepath.Join(dir, "prog.c")
	if err := os.WriteFile(prog, []byte(sup.Text+s703Harness), 0o644); err != nil {
		t.Fatalf("写 prog.c：%v", err)
	}
	native := filepath.Join(dir, "native.c")
	if err := os.WriteFile(native, []byte(s703Native), 0o644); err != nil {
		t.Fatalf("写 native.c：%v", err)
	}
	exe := filepath.Join(dir, "prog")
	args := []string{"-std=c11", "-O2", "-Wall", "-Wno-unused-function", "-I", rtDir, "-o", exe, prog, native}
	for _, f := range []string{"rt.c", "rt_gc.c", "rt_policy.c", "rt_weak.c", "xrt_abi.c"} {
		args = append(args, filepath.Join(rtDir, f))
	}
	build := exec.Command(cc, args...)
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("cc 失败：%v\n%s", err, out)
	}
	return exe
}

func TestS703CallbackTrampolineEndToEnd(t *testing.T) {
	exe := buildS703(t)

	out, err := exec.Command(exe).CombinedOutput()
	if err != nil {
		t.Fatalf("运行失败：%v\n%s", err, out)
	}
	want := strings.Join([]string{
		"log st=0 r=7 n=1 alive=1",
		"notify st=0 n=9",
		"destroyed alive=0",
	}, "\n")
	if got := strings.TrimSpace(string(out)); got != want {
		t.Fatalf("输出不符\n got:\n%s\nwant:\n%s", got, want)
	}

	// 注销后调用：运行时 xrt_fatal → abort（S7 §5.2 合同违规，不得静默）。
	for _, mode := range []string{"destroyed", "panic"} {
		c := exec.Command(exe, mode)
		o, err := c.CombinedOutput()
		if err == nil {
			t.Fatalf("%s 模式应终止进程，实际通过：%s", mode, o)
		}
		if strings.Contains(string(o), mode+"-missed") {
			t.Fatalf("%s 模式未检出违规：%s", mode, o)
		}
	}
}

func TestS703CallbackValidation(t *testing.T) {
	// 参数含 Bytes：不可跨回调边界（S7 §5.1/§5.3）。
	_, diags := loadSrc(t, "bindings/bad.xfb", `ffi bad {
  callback Bad(Bytes) -> Int64;
}
`)
	if len(diags) == 0 || !strings.Contains(strings.Join(codeList(diags), ","), "FFI-112") {
		t.Fatalf("Bytes 回调参数应报 FFI-112，得到 %v", codeList(diags))
	}

	// 返回 layout：回调返回限标量或 Void。
	_, diags = loadSrc(t, "bindings/bad2.xfb", `ffi bad2 {
  layout(c) struct Pair { Int64 a; }
  callback Bad(Pair) -> Pair;
}
`)
	if len(diags) == 0 || !strings.Contains(strings.Join(codeList(diags), ","), "FFI-112") {
		t.Fatalf("layout 回调返回应报 FFI-112，得到 %v", codeList(diags))
	}

	// 重名回调。
	_, diags = loadSrc(t, "bindings/bad3.xfb", `ffi bad3 {
  callback Dup(Int64) -> Int64;
  callback Dup(Int64) -> Int64;
}
`)
	if len(diags) == 0 || !strings.Contains(strings.Join(codeList(diags), ","), "FFI-111") {
		t.Fatalf("重复回调应报 FFI-111，得到 %v", codeList(diags))
	}
}
