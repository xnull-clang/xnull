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
			mainSrc := "import xdk.errors\n\nstatic Int main() {\n    Result<Int32, ErrorKind> r = stubFail()\n    print(str(r.error() == ErrorKind." + c.want + "))\n    return 0\n}\n"
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
			// S7-02：映射函数由支撑代码提供；调用点不再 fatal，原始码回写调用点。
			// 已知码必须在生成的 switch 中有稳定枚举；未知码走 default → Internal。
			if !strings.Contains(csrc, "xn_ffi_t_error_kind_id(") {
				t.Fatalf("支撑代码缺少 ErrorKind 映射函数：\n%s", csrc)
			}
			ret := map[string]string{
				"Io": "XRT_ERR_IO", "Cancelled": "XRT_ERR_CANCELLED", "Timeout": "XRT_ERR_TIMEOUT",
			}[c.want]
			if ret != "" {
				if !strings.Contains(csrc, "case "+c.code+": return "+ret+";") {
					t.Fatalf("错误码 %s 未映射到 %s：\n%s", c.code, ret, csrc)
				}
			} else if !strings.Contains(csrc, "default: return XRT_ERR_INTERNAL;") {
				t.Fatalf("未知码未走 Internal：\n%s", csrc)
			}
			if strings.Contains(csrc, "fatal: FFI 入口") {
				t.Fatalf("调用点仍保留 FFI fatal（S7-02）：\n%s", csrc)
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
			if code != 0 {
				t.Fatalf("退出码 %d，期望 0（S7-02：不再 fatal；stderr=%s）", code, errb.String())
			}
			if got, want := out.String(), "true\n"; got != want {
				t.Fatalf("stdout=%q，期望 Err(ErrorKind.%s) 为 true", got, c.want)
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
