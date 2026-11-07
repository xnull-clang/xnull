package codegen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// B0-07c codegen 面（不依赖 sema 的 Bytes 成员面，先锁住发射形态）：
//   - CG-BYTES-ARG：Bytes 形参按 (data, len) 借出；
//   - CG-ERRORCODE：包装签名不含 code，调用点把归一 rc 回写 code；
//   - CG-INT32-RET：Int32 返回按 int32_t 出参。
const b007cXfb = `ffi xdkc_sys {
  handle File { close = fileClose }

  errorMap {
    1 = Invalid
    2 = Internal
  }

  @ffiEntry(cName = "xdkc_file_open_read")
  @lease(path = .borrow)
  @blocking(.unaware)
  File fileOpenRead(String path);

  @ffiEntry(cName = "xdkc_file_read")
  @lease(f = .borrow, buf = .borrow, code = .borrow)
  @errorCode(codeParam = .code)
  @blocking(.unaware)
  Int64 fileRead(File f, Bytes buf, Int32 code);

  @ffiEntry(cName = "xdkc_file_write")
  @lease(f = .borrow, buf = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.unaware)
  Int32 fileWrite(File f, Bytes buf);

  @ffiEntry(cName = "xdkc_file_close")
  @lease(f = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.aware)
  Int32 fileClose(File f);
}
`

const b007cSrc = `import xdk.sys

static Int main() {
    File? g = fileOpenRead("in.txt")
    if (g == null) {
        return 1
    }
    File f = fileOpenRead("in.txt")
    Bytes b = Bytes.fromString("AB")
    Int32 code = 7
    Int64 got = fileRead(f, b, code)
    Int32 wc = fileWrite(f, b)
    return 0
}
`

func TestB007CNumericCodegenSurface(t *testing.T) {
	dir := t.TempDir()
	mainPath := filepath.Join(dir, "main.x")
	if err := os.WriteFile(mainPath, []byte(b007cSrc), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "bindings", "xdk"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "bindings", "xdk", "sys.xfb"), []byte(b007cXfb), 0o644); err != nil {
		t.Fatal(err)
	}
	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	u, pdiags := xfront.ParseUnit(mainPath, b007cSrc)
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	if err := InjectFFI(u, reg); err != nil {
		t.Fatalf("InjectFFI: %v", err)
	}
	csrc, err := EmitCWithFFI(u, reg)
	if err != nil {
		t.Fatalf("EmitCWithFFI: %v", err)
	}
	for _, want := range []string{
		"xrt_bytes_from_string(",
		"int64_t got = ",
		"xn_ffi_fileRead(f, b->data, b->len, &xn_t",
		"code = ",
		"int32_t wc = ",
		"xn_ffi_fileWrite(f, b->data, b->len)",
		"int64_t *xn_out",
		"xrt_handle *g = ",
		"(g == NULL)",
	} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("生成代码缺少 %q：\n%s", want, csrc)
		}
	}
	// 包装签名不得含 code 形参（ffi-contract §5.1）。
	if strings.Contains(csrc, "xn_ffi_fileRead(xrt_handle *f, void *buf, size_t buf_len, int32_t *code") {
		t.Fatalf("fileRead 包装签名不应暴露 code 形参：\n%s", csrc)
	}
}
