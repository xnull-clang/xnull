package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

const s701Xfb = `ffi native701 {
  handle File { close = ffiClose }

  layout(c) struct Pair {
    Int64 a;
    Int32 b;
  }

  @ffiEntry(cName = "native_text")
  @lease(t = .borrow)
  @blocking(.aware)
  Int64 ffiText(Text t);

  @ffiEntry(cName = "native_layout")
  @lease(p = .borrow)
  @blocking(.aware)
  Int64 ffiLayout(Pair p);

  @ffiEntry(cName = "native_arr")
  @lease(a = .borrow)
  @blocking(.aware)
  Int64 ffiArr(Int[] a);

  @ffiEntry(cName = "native_float")
  @lease(f = .borrow)
  @blocking(.aware)
  Float ffiFloat(Float f);

  @ffiEntry(cName = "native_char")
  @lease(c = .borrow)
  @blocking(.aware)
  Char ffiChar(Char c);

  @ffiEntry(cName = "native_uint")
  @lease(u = .borrow)
  @blocking(.aware)
  UInt ffiUInt(UInt u);

  @ffiEntry(cName = "native_fill")
  @lease(b = .transfer)
  @blocking(.aware)
  Int64 ffiFill(Bytes b);

  @ffiEntry(cName = "native_reclaim")
  @lease(b = .reclaim)
  @blocking(.aware)
  Int64 ffiReclaim(Bytes b);

  @ffiEntry(cName = "native_open")
  @lease(name = .borrow, out = .transfer)
  @blocking(.aware)
  Int64 ffiOpen(String name, File out);

  @ffiEntry(cName = "native_close")
  @lease(h = .borrow)
  @blocking(.aware)
  Int32 ffiClose(File h);
}
`

const s701Native = `#include <stdint.h>
#include <stddef.h>
typedef struct { int64_t a; int32_t b; } xn_layout_Pair;
int64_t native_text(const char *b, size_t n) { (void)b; return (int64_t)n; }
int64_t native_layout(xn_layout_Pair *p) { return p->a + p->b; }
int64_t native_arr(int64_t *a, size_t n) { int64_t s = 0; for (size_t i = 0; i < n; i++) s += a[i]; return s; }
double native_float(double f) { return f * 2.0; }
uint32_t native_char(uint32_t c) { return c + 1; }
uint64_t native_uint(uint64_t u) { return u + 3; }
int64_t native_fill(void *b, size_t n) { (void)b; return (int64_t)n; }
int64_t native_reclaim(void *b, size_t n) { (void)b; return (int64_t)n; }
int64_t native_open(const char *b, size_t n, void **out) { (void)b; (void)n; *out = (void *)1; return 0; }
int32_t native_close(void *h) { (void)h; return 0; }
`

func TestS701CallSiteMarshalling(t *testing.T) {
	dir := t.TempDir()
	writeFFIFile(t, filepath.Join(dir, "bindings", "native701.xfb"), s701Xfb)
	native := filepath.Join(dir, "native.c")
	writeFFIFile(t, native, s701Native)
	src := `struct Pair {
    Int64 a;
    Int32 b;
    Pair(Int64 x, Int32 y) { self.a = x; self.b = y }
}
static Int main() {
    Text t = Text.fromString("abc")
    print(ffiText(t))
    Pair p = new Pair(7, 2)
    print(ffiLayout(p))
    print(ffiArr([1, 2, 3]))
    Float f = ffiFloat(1.5)
    print(f)
    Char c = ffiChar('a')
    print(c == 'b')
    UInt u = ffiUInt(2)
    print(u)
    Bytes b = Bytes.fromString("xy")
    print(ffiFill(b))
    print(ffiReclaim(b))
    File? h = null
    print(ffiOpen("p", h))
    print(h != null)
    return 0
}`
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, src)
	bin := filepath.Join(dir, "prog")
	var stderr bytes.Buffer
	if code := BuildWithOptions(mainPath, bin, filepath.Join("..", "..", "runtime"), Options{LinkArgs: []string{native}}, &stderr); code != 0 {
		t.Fatalf("构建失败 code=%d\n%s", code, stderr.String())
	}
	// layout(c) 尺寸检查（编译期断言）应出现在生成 C。
	cres, err := os.ReadFile(bin + ".c")
	if err != nil {
		t.Fatalf("读取生成 C：%v", err)
	}
	if !strings.Contains(string(cres), "_Static_assert(sizeof(xn_layout_Pair) == 16") {
		t.Fatalf("缺少 layout(c) 尺寸检查：\n%s", string(cres))
	}
	var out bytes.Buffer
	cmd := exec.Command(bin)
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("运行失败：%v（stdout=%q）", err, out.String())
	}
	if want := "3\n9\n6\n3\ntrue\n5\n2\n2\n0\ntrue\n"; out.String() != want {
		t.Fatalf("stdout=%q，期望 %q", out.String(), want)
	}
}
