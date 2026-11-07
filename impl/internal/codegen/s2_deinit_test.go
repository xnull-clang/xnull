package codegen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// S2-E5-01/02/04/05：deinit 发射契约。
//   - 用户 deinit 体先执行，再做字段释放；
//   - 引用字段赋值 = 求值 → 新值 +1 → 释放旧值 → 写入；
//   - 句柄/Bytes 字段也由 deinit 释放（句柄仍须显式 close）。

func TestS2DeinitUserBodyBeforeFieldRelease(t *testing.T) {
	src := `class Box {
    String name = "init"
    void deinit() {
        print("deinit:" + self.name)
    }
}
static Int main() {
    Box b = new Box()
    b.name = "one"
    b.name = "two"
    print(b.name)
    return 0
}
`
	out, code := compileAndRun(t, src)
	if code != 0 || out != "two\ndeinit:two\n" {
		t.Fatalf("out=%q code=%d，期望 \"two\\ndeinit:two\\n\" / 0", out, code)
	}

	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	csrc, err := EmitC(u)
	if err != nil {
		t.Fatalf("EmitC: %v", err)
	}
	iUser := strings.Index(csrc, "_deinit_user(o);")
	iRel := strings.Index(csrc, "rt_release(o->name);")
	if iUser < 0 || iRel < 0 || iUser > iRel {
		t.Fatalf("deinit 顺序错误：user=%d release=%d\n%s", iUser, iRel, csrc)
	}
}

func TestS2FieldAssignClassRefRetainRelease(t *testing.T) {
	src := `class Inner {
    String v = "i"
}
class Outer {
    Inner inner = new Inner()
}
static Int main() {
    Outer o = new Outer()
    Inner x = new Inner()
    x.v = "x"
    o.inner = x
    print(o.inner.v)
    return 0
}
`
	out, code := compileAndRun(t, src)
	if code != 0 || out != "x\n" {
		t.Fatalf("out=%q code=%d，期望 \"x\\n\" / 0", out, code)
	}
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	csrc, err := EmitC(u)
	if err != nil {
		t.Fatalf("EmitC: %v", err)
	}
	for _, want := range []string{
		"rt_retain(x);",
		"rt_release(o->inner);",
		"o->inner = x;",
	} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("类引用字段赋值缺少 %q：\n%s", want, csrc)
		}
	}
}

// Bytes.fromString 的 sema 成员面属 E2；本用例绕过 sema 验证发射面。
func TestS2DeinitReleasesHandleAndBytes(t *testing.T) {
	xfb := `ffi xdkc_sys {
  handle File { close = fileClose }

  @ffiEntry(cName = "xdkc_file_close")
  @lease(f = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.aware)
  Int32 fileClose(File f);
}
`
	src := `class H {
    File f
    Bytes b
    void deinit() {
        print("bye")
    }
}
static Int main() { return 0 }
`
	dir := t.TempDir()
	mainPath := filepath.Join(dir, "main.x")
	if err := os.WriteFile(mainPath, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "bindings", "xdk"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "bindings", "xdk", "sys.xfb"), []byte(xfb), 0o644); err != nil {
		t.Fatal(err)
	}
	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	u, pdiags := xfront.ParseUnit(mainPath, src)
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	csrc, err := EmitCWithFFI(u, reg)
	if err != nil {
		t.Fatalf("EmitCWithFFI: %v", err)
	}
	iUser := strings.Index(csrc, "_deinit_user(o);")
	iH := strings.Index(csrc, "rt_release(o->f);")
	iB := strings.Index(csrc, "rt_release(o->b);")
	if iUser < 0 || iH < 0 || iB < 0 {
		t.Fatalf("deinit 未覆盖句柄/Bytes 字段或用户体：user=%d handle=%d bytes=%d\n%s", iUser, iH, iB, csrc)
	}
	if iUser > iH || iUser > iB {
		t.Fatalf("用户 deinit 体必须在字段释放之前：user=%d handle=%d bytes=%d", iUser, iH, iB)
	}
}
