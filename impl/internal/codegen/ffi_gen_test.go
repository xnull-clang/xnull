package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// M6-B0-01 / P-09：.xfb 入口注入为包级可调用声明，调用点走 xn_ffi_<entry>。

const ffiSampleXfb = `ffi native {
  @ffiEntry(cName = "native_add")
  @lease(a = .borrow, b = .borrow)
  @blocking(.aware)
  Int64 ffiAdd(Int64 a, Int64 b);

  @ffiEntry(cName = "native_strlen2")
  @lease(s = .borrow)
  @blocking(.aware)
  Int64 ffiByteLen(String s);
}
`

const ffiSampleNativeC = `#include <stdint.h>
#include <stddef.h>

int64_t native_add(int64_t a, int64_t b) { return a + b; }
int64_t native_strlen2(const char *bytes, size_t len) { return (int64_t)len; }
`

const ffiSampleSrc = `static Int main() {
    String label = "hello"
    print(str(ffiAdd(2, 3)))
    print(str(ffiByteLen(label)))
    return 0
}
`

// 纯 XNull 等价程序：解释路径的对照 oracle（解释器无 FFI 面，属 E3 域）。
const ffiSampleOracle = `static Int add(Int a, Int b) { return a + b }
static Int byteLen(String s) { return s.length() }
static Int main() {
    String label = "hello"
    print(str(add(2, 3)))
    print(str(byteLen(label)))
    return 0
}
`

func writeFFIFile(t *testing.T, path, src string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestFFIEntryInjectedAndCompiles(t *testing.T) {
	dir := t.TempDir()
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, ffiSampleSrc)
	writeFFIFile(t, filepath.Join(dir, "bindings", "native.xfb"), ffiSampleXfb)
	nativePath := filepath.Join(dir, "native.c")
	writeFFIFile(t, nativePath, ffiSampleNativeC)

	reg, diags, err := LoadFFI(dir)
	if err != nil {
		t.Fatalf("LoadFFI: %v", err)
	}
	if len(diags) != 0 {
		t.Fatalf(".xfb 诊断：%v", diags)
	}

	u, pdiags := xfront.ParseUnit(mainPath, ffiSampleSrc)
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	if err := InjectFFI(u, reg); err != nil {
		t.Fatalf("InjectFFI: %v", err)
	}
	if sd := sema.Analyze(mainPath, u); len(sd) != 0 {
		t.Fatalf("注入后语义诊断：%v", sd)
	}
	csrc, err := EmitCWithFFI(u, reg)
	if err != nil {
		t.Fatalf("EmitCWithFFI: %v", err)
	}
	if !strings.Contains(csrc, "xn_ffi_ffiAdd(") || !strings.Contains(csrc, "xn_ffi_ffiByteLen(") {
		t.Fatalf("调用点未走 xn_ffi_<entry>：\n%s", csrc)
	}
	if strings.Contains(csrc, "static int64_t xn_ffiAdd(") {
		t.Fatalf("注入声明被当作普通函数生成：\n%s", csrc)
	}

	// 编译：运行时 + xrt_abi + 原生符号。
	cc := ""
	for _, name := range []string{"cc", "clang", "gcc"} {
		if p, err := exec.LookPath(name); err == nil {
			cc = p
			break
		}
	}
	if cc == "" {
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
	var got bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &got
	if err := run.Run(); err != nil {
		t.Fatalf("运行失败：%v", err)
	}

	// 解释路径 oracle（等价纯 XNull 程序）。
	ou, odiags := xfront.ParseUnit("oracle.x", ffiSampleOracle)
	if len(odiags) != 0 {
		t.Fatalf("oracle 解析诊断：%v", odiags)
	}
	var want strings.Builder
	if _, err := interp.Run(ou, &want, nil); err != nil {
		t.Fatalf("oracle 解释失败：%v", err)
	}
	if got.String() != want.String() {
		t.Fatalf("编译路径 %q 与解释 oracle %q 不一致", got.String(), want.String())
	}
}

// 注入必须防御编译单元内重名（P-09 条件 1）。
func TestFFIInjectionDuplicateNameRejected(t *testing.T) {
	dir := t.TempDir()
	writeFFIFile(t, filepath.Join(dir, "bindings", "native.xfb"), ffiSampleXfb)
	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	src := "static Int ffiAdd() { return 0 }\nstatic Int main() { return 0 }"
	u, pdiags := xfront.ParseUnit("dup.x", src)
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	if err := InjectFFI(u, reg); err == nil || !strings.Contains(err.Error(), "重名") {
		t.Fatalf("注入重名应显式报错，实际：%v", err)
	}
}
