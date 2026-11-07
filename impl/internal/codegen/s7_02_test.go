package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

const s702Xfb = `ffi native {
  @ffiEntry(cName = "native_read")
  @lease(path = .borrow, code = .borrow)
  @errorCode(codeParam = .code)
  @blocking(.aware)
  Int64 ffiRead(String path, Int32 code);
}
`

const s702NativeC = `#include <stdint.h>
#include <stddef.h>

int64_t native_read(const char *path, size_t n, int32_t *code) {
    (void)path;
    (void)n;
    *code = 5; /* 已知码：NotFound */
    return -1;
}
`

const s702Src = `static Int main() {
    Int32 code = 0
    Int64 n = ffiRead("x", code)
    print(str(code))
    print(str(n))
    return 0
}
`

// S7-02：FFI 错误码不再在调用点 exit(134)，原始码回写调用点变量。
func TestS7_02ErrorCodeNoFatal(t *testing.T) {
	dir := t.TempDir()
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, s702Src)
	writeFFIFile(t, filepath.Join(dir, "bindings", "native.xfb"), s702Xfb)
	nativePath := filepath.Join(dir, "native.c")
	writeFFIFile(t, nativePath, s702NativeC)

	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	u, pdiags := xfront.ParseUnit(mainPath, s702Src)
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	if err := InjectFFI(u, reg); err != nil {
		t.Fatalf("InjectFFI: %v", err)
	}
	if sd := sema.Analyze(mainPath, u); len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitCWithFFI(u, reg)
	if err != nil {
		t.Fatalf("EmitCWithFFI: %v", err)
	}
	if strings.Contains(csrc, "exit(134)") && strings.Contains(csrc, "FFI 入口") {
		t.Fatalf("调用点仍含 FFI exit(134)：\n%s", csrc)
	}

	cc, err := exec.LookPath("cc")
	if err != nil {
		t.Skip("无 C 编译器")
	}
	rt := filepath.Join("..", "..", "runtime")
	if _, err := os.Stat(filepath.Join(rt, "xrt.h")); err != nil {
		t.Skipf("运行时目录不可用：%v", err)
	}
	cfile := filepath.Join(dir, "prog.c")
	writeFFIFile(t, cfile, csrc)
	bin := filepath.Join(dir, "prog")
	args := []string{"-std=c11", "-O2", "-Wno-unused-function", "-I", rt, "-o", bin, cfile, nativePath}
	for _, f := range []string{"rt.c", "rt_gc.c", "rt_policy.c", "rt_weak.c", "xrt_abi.c"} {
		args = append(args, filepath.Join(rt, f))
	}
	var ccErr bytes.Buffer
	cmd := exec.Command(cc, args...)
	cmd.Stderr = &ccErr
	if err := cmd.Run(); err != nil {
		t.Fatalf("cc 失败：%v\n%s", err, ccErr.String())
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	if err := run.Run(); err != nil {
		t.Fatalf("运行失败：%v（stdout=%q）", err, out.String())
	}
	if got, want := out.String(), "5\n0\n"; got != want {
		t.Fatalf("stdout=%q，期望 %q", got, want)
	}
}

// S7-02：E4 调用点改造的对接表达式（区域错误码 → ErrorKind）。
func TestS7_02ErrorKindExpr(t *testing.T) {
	if got, want := ffiErrorKindExpr("native", "rc"), "xn_ffi_native_error_kind_id(rc)"; got != want {
		t.Fatalf("ffiErrorKindExpr=%q，期望 %q", got, want)
	}
}

const s702RetXfb = `ffi native {
  @ffiEntry(cName = "native_write")
  @lease(v = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.aware)
  Int32 ffiWrite(Int32 v);
}
`

const s702RetNativeC = `#include <stdint.h>

int32_t native_write(int32_t v) {
    (void)v;
    return 7; /* 错误码即返回值 */
}
`

const s702RetSrc = `static Int main() {
    Int32 rc = ffiWrite(1)
    print(str(rc))
    return 0
}
`

// S7-02：错误码即返回值的入口也不 fatal；原始码交付调用点。
func TestS7_02ErrorCodeReturnNoFatal(t *testing.T) {
	dir := t.TempDir()
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, s702RetSrc)
	writeFFIFile(t, filepath.Join(dir, "bindings", "native.xfb"), s702RetXfb)
	nativePath := filepath.Join(dir, "native.c")
	writeFFIFile(t, nativePath, s702RetNativeC)

	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	u, pdiags := xfront.ParseUnit(mainPath, s702RetSrc)
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	if err := InjectFFI(u, reg); err != nil {
		t.Fatalf("InjectFFI: %v", err)
	}
	if sd := sema.Analyze(mainPath, u); len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitCWithFFI(u, reg)
	if err != nil {
		t.Fatalf("EmitCWithFFI: %v", err)
	}
	if strings.Contains(csrc, "fatal: FFI 入口") {
		t.Fatalf("错误码即返回值入口仍 fatal（S7-02）：\n%s", csrc)
	}

	cc, err := exec.LookPath("cc")
	if err != nil {
		t.Skip("无 C 编译器")
	}
	rt := filepath.Join("..", "..", "runtime")
	if _, err := os.Stat(filepath.Join(rt, "xrt.h")); err != nil {
		t.Skipf("运行时目录不可用：%v", err)
	}
	cfile := filepath.Join(dir, "prog.c")
	writeFFIFile(t, cfile, csrc)
	bin := filepath.Join(dir, "prog")
	args := []string{"-std=c11", "-O2", "-Wno-unused-function", "-I", rt, "-o", bin, cfile, nativePath}
	for _, f := range []string{"rt.c", "rt_gc.c", "rt_policy.c", "rt_weak.c", "xrt_abi.c"} {
		args = append(args, filepath.Join(rt, f))
	}
	var ccErr bytes.Buffer
	cmd := exec.Command(cc, args...)
	cmd.Stderr = &ccErr
	if err := cmd.Run(); err != nil {
		t.Fatalf("cc 失败：%v\n%s", err, ccErr.String())
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	if err := run.Run(); err != nil {
		t.Fatalf("运行失败：%v（stdout=%q）", err, out.String())
	}
	if got, want := out.String(), "7\n"; got != want {
		t.Fatalf("stdout=%q，期望 %q", got, want)
	}
}
