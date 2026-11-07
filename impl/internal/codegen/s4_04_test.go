package codegen

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// S4-04：errorMap 接受 S4 §3.1 规范分类名，生成稳定 ErrorKind 枚举映射。
func TestS4_04ErrorKindCanonicalNames(t *testing.T) {
	dir := t.TempDir()
	xfb := `ffi t {
  errorMap {
    1 = InvalidArgument
    2 = NotFound
    3 = AlreadyExists
    4 = PermissionDenied
    5 = Io
    6 = Network
    7 = Timeout
    8 = Cancelled
    9 = Busy
    10 = Unavailable
    11 = DataCorrupted
    12 = Unsupported
    13 = OutOfMemory
    14 = Internal
  }
  @ffiEntry(cName = "stub_fail")
  @lease(code = .borrow)
  @errorCode(codeParam = .code)
  @blocking(.aware)
  Int32 stubFail(Int32 code);
}
`
	writeFFIFile(t, filepath.Join(dir, "bindings", "t.xfb"), xfb)
	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	sup := reg.EmitSupport()
	for _, want := range []string{
		"case 1: return XRT_ERR_INVALID_ARGUMENT;",
		"case 5: return XRT_ERR_IO;",
		"case 6: return XRT_ERR_NETWORK;",
		"case 7: return XRT_ERR_TIMEOUT;",
		"case 8: return XRT_ERR_CANCELLED;",
		"case 11: return XRT_ERR_DATA_CORRUPTED;",
		"case 12: return XRT_ERR_UNSUPPORTED;",
		"case 13: return XRT_ERR_OUT_OF_MEMORY;",
		"case 14: return XRT_ERR_INTERNAL;",
		"default: return XRT_ERR_INTERNAL;",
		"xn_ffi_t_error_kind_id",
	} {
		if !strings.Contains(sup.Text, want) {
			t.Fatalf("错误码分类发射缺 %q：\n%s", want, sup.Text)
		}
	}
}

// S4-04：取消/超时不降级；未知码 → Internal（绝不当 Ok）；调用点分类使用
// ErrorKind 枚举（xrt_error_kind_name）。
func TestS4_04FFIErrorKindRuntime(t *testing.T) {
	cases := []struct {
		name string
		code string
		want string
	}{
		{"Io", "5", "Io"},
		{"Cancelled", "8", "Cancelled"},
		{"Timeout", "7", "Timeout"},
		{"未知码", "99", "Internal"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			xfb := `ffi t {
  errorMap {
    5 = Io
    7 = Timeout
    8 = Cancelled
  }
  @ffiEntry(cName = "stub_fail")
  @lease(code = .borrow)
  @errorCode(codeParam = .code)
  @blocking(.aware)
  Int32 stubFail(Int32 code);
}
`
			writeFFIFile(t, filepath.Join(dir, "bindings", "t.xfb"), xfb)
			mainSrc := "static Int main() {\n    Int32 code = 0\n    stubFail(code)\n    print(\"MAIN-SHOULD-NOT-RUN\")\n    return 0\n}\n"
			mainPath := filepath.Join(dir, "main.x")
			writeFFIFile(t, mainPath, mainSrc)
			nativePath := filepath.Join(dir, "stub.c")
			writeFFIFile(t, nativePath, "#include <stdint.h>\nint32_t stub_fail(int32_t *code) { *code = "+c.code+"; return 0; }\n")

			reg, diags, err := LoadFFI(dir)
			if err != nil || len(diags) != 0 {
				t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
			}
			u, pdiags := xfront.ParseUnit(mainPath, mainSrc)
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
			if !strings.Contains(csrc, "xrt_error_kind_name(xn_ffi_t_error_kind_id(") {
				t.Fatalf("调用点未使用 ErrorKind 枚举分类：\n%s", csrc)
			}
			rt := filepath.Join("..", "..", "runtime")
			cfile := filepath.Join(dir, "prog.c")
			writeFFIFile(t, cfile, csrc)
			bin := filepath.Join(dir, "prog")
			args := []string{"-std=c11", "-O2", "-I", rt, "-o", bin, cfile, nativePath}
			for _, s := range runtimeCSources {
				args = append(args, filepath.Join(rt, s))
			}
			var cerr bytes.Buffer
			cc := exec.Command("cc", args...)
			cc.Stderr = &cerr
			if err := cc.Run(); err != nil {
				t.Fatalf("cc 失败：%v\n%s\n---- C ----\n%s", err, cerr.String(), csrc)
			}
			var out, errb bytes.Buffer
			run := exec.Command(bin)
			run.Stdout = &out
			run.Stderr = &errb
			code := 0
			if err := run.Run(); err != nil {
				if ee, ok := err.(*exec.ExitError); ok {
					code = ee.ExitCode()
				} else {
					t.Fatal(err)
				}
			}
			if code != 134 {
				t.Fatalf("退出码 %d，期望 134（stderr=%s）", code, errb.String())
			}
			if out.String() != "" {
				t.Fatalf("错误码非零后入口仍执行：stdout=%q", out.String())
			}
			if !strings.Contains(errb.String(), c.want) {
				t.Fatalf("stderr 未含分类 %q：%s", c.want, errb.String())
			}
		})
	}
}

// S4-04：历史短名别名兼容（既有 xdk 绑定不回归）。
func TestS4_04LegacyKindAliases(t *testing.T) {
	dir := t.TempDir()
	xfb := `ffi t {
  errorMap {
    1 = Invalid
    2 = Conflict
    3 = Permission
    4 = Limit
  }
  @ffiEntry(cName = "stub")
  @lease(v = .borrow)
  @blocking(.aware)
  Int32 stub(Int32 v);
}
`
	writeFFIFile(t, filepath.Join(dir, "bindings", "t.xfb"), xfb)
	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	sup := reg.EmitSupport()
	for _, want := range []string{
		"case 1: return XRT_ERR_INVALID_ARGUMENT;",
		"case 2: return XRT_ERR_ALREADY_EXISTS;",
		"case 3: return XRT_ERR_PERMISSION_DENIED;",
		"case 4: return XRT_ERR_BUSY;",
	} {
		if !strings.Contains(sup.Text, want) {
			t.Fatalf("短名别名为未映射 %q：\n%s", want, sup.Text)
		}
	}
}
