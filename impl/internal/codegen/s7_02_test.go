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
  errorMap {
    5 = NotFound
  }
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

const s702Src = `import xdk.errors

static Int main() {
    Result<Int64, ErrorKind> r = ffiRead("x")
    print(r.isErr())
    print(r.error() == ErrorKind.NotFound)
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
	if !strings.Contains(csrc, "xn_Result_Int64_ErrorKind") ||
		!strings.Contains(csrc, "xn_ffi_native_error_kind_id(") {
		t.Fatalf("调用点未构造 Result<T, ErrorKind>：\n%s", csrc)
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
		t.Fatalf("cc 失败：%v\n%s\n---- C ----\n%s", err, ccErr.String(), csrc)
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	if err := run.Run(); err != nil {
		t.Fatalf("运行失败：%v（stdout=%q）", err, out.String())
	}
	if got, want := out.String(), "true\ntrue\n"; got != want {
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
  errorMap {
    7 = NotFound
    99 = Internal
    14 = Cancelled
    15 = Timeout
  }
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

const s702RetSrc = `import xdk.errors

static Int main() {
    Result<void, ErrorKind> r = ffiWrite(1)
    print(r.isErr())
    print(r.error() == ErrorKind.NotFound)
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
	if !strings.Contains(csrc, "xn_Result_void_ErrorKind") {
		t.Fatalf("错误码即返回值入口未构造 Result<void, ErrorKind>：\n%s", csrc)
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
		t.Fatalf("cc 失败：%v\n%s\n---- C ----\n%s", err, ccErr.String(), csrc)
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	if err := run.Run(); err != nil {
		t.Fatalf("运行失败：%v（stdout=%q）", err, out.String())
	}
	if got, want := out.String(), "true\ntrue\n"; got != want {
		t.Fatalf("stdout=%q，期望 %q", got, want)
	}
}

// S7-02/FFI-01：Result 映射矩阵——Ok(值)、已知码、未知码 → Internal、
// Cancelled/Timeout 不降级（QA A01–A04）。
func TestS7_02ResultMapping(t *testing.T) {
	cases := []struct {
		name string
		code string
		want string
	}{
		{"Ok", "0", "ok 42\n"},
		{"已知码 5", "5", "err true\n"},
		{"未知码 99", "99", "err true\n"},
		{"Cancelled", "14", "err true\n"},
		{"Timeout", "15", "err true\n"},
	}
	// 每种情况的期望比较项：已知码比较对应 ErrorKind 项；未知码/取消/超时分开写。
	kindOf := map[string]string{
		"0":  "Internal", // Ok 分支不引用；占位避免生成空成员名
		"5":  "NotFound",
		"99": "Internal",
		"14": "Cancelled",
		"15": "Timeout",
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			xfb := `ffi native {
  errorMap {
    5 = NotFound
    14 = Cancelled
    15 = Timeout
  }
  @ffiEntry(cName = "native_read")
  @lease(path = .borrow, code = .borrow)
  @errorCode(codeParam = .code)
  @blocking(.aware)
  Int64 ffiRead(String path, Int32 code);
}
`
			writeFFIFile(t, filepath.Join(dir, "bindings", "native.xfb"), xfb)
			src := `import xdk.errors

static Int main() {
    Result<Int64, ErrorKind> r = ffiRead("x")
    if (r.isOk()) {
        print("ok " + str(r.value()))
    } else {
        print("err " + str(r.error() == ErrorKind.` + kindOf[tc.code] + `))
    }
    return 0
}
`
			mainPath := filepath.Join(dir, "main.x")
			writeFFIFile(t, mainPath, src)
			nativePath := filepath.Join(dir, "native.c")
			writeFFIFile(t, nativePath, `#include <stdint.h>
#include <stddef.h>
int64_t native_read(const char *path, size_t n, int32_t *code) {
    (void)path; (void)n;
    *code = `+tc.code+`;
    return 42;
}
`)
			reg, diags, err := LoadFFI(dir)
			if err != nil || len(diags) != 0 {
				t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
			}
			u, pdiags := xfront.ParseUnit(mainPath, src)
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
				t.Fatalf("Result 通道不应 fatal：\n%s", csrc)
			}
			cc, err := exec.LookPath("cc")
			if err != nil {
				t.Skip("无 C 编译器")
			}
			rt := filepath.Join("..", "..", "runtime")
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
			if got := out.String(); got != tc.want {
				t.Fatalf("stdout=%q，期望 %q", got, tc.want)
			}
		})
	}
}
