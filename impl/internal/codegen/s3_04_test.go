package codegen

import (
	"strings"
	"testing"
)

// S3-04：String/Text/Bytes/StringBuilder 全部 GC 化，且 codegen 对齐 E2 的内建签名。
func TestS3_04GCTextBytesSB(t *testing.T) {
	src := `
import xdk.text
static Int main() {
    StringBuilder b = StringBuilder()
    b.append("x")
    b.append(1)
    String s = b.toString()
    Int n = b.length()

    Text t = Text.fromString("hello")
    Int tl = t.length()
    Int cp = t.codePointCount()
    String ts = t.toString()

    Bytes by = Bytes.fromString("abc")
    by.set(1, 90)
    Int v = by.get(0)
    by.push(1)
    by.append(by)
    Bytes sl = by.slice(0, 2)
    Int bl = by.length()
    print(s)
    print(n + tl + cp + v + bl)
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if code != 0 || got != "x1\n117\n" {
		t.Fatalf("输出 %q(code %d)，期望 \"x1\\n117\\n\"", got, code)
	}
}

// S3-04：String 字段是 GC 引用——持有者的 scan 必须访问它（否则收集期间悬挂）。
func TestS3_04StringFieldScanned(t *testing.T) {
	src := `
class Holder {
    String s = "kept"
    void deinit() { print("holder:" + self.s) }
}
static Int main() {
    Holder h = new Holder()
    print("main")
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "if (o->s) { visit(o->s); }") {
		t.Fatalf("String 字段未进入 scan：\\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	if code != 0 || !strings.Contains(got, "holder:kept") {
		t.Fatalf("deinit 读到 String 字段失败：%q(code %d)", got, code)
	}
}

// S3-04：String/Bytes/Text/SB 的 runtime GC 属性由 TestS304GC* 覆盖（test_std.c）。

// S3-04：Text/StringBuilder 的 C 类型与构造/方法降级。
func TestS3_04TextSBTypes(t *testing.T) {
	src := `
import xdk.text
static Int main() {
    Text t = Text.fromString("abc")
    StringBuilder b = StringBuilder()
    b.append(t.toString())
    print(b.toString())
    print(t.compareTo(t))
    return 0
}`
	csrc := emitWithPolicy(t, src)
	for _, sym := range []string{"xrt_text_from_string", "xrt_sb_new", "xrt_sb_append_str", "xrt_text_compare_to"} {
		if !strings.Contains(csrc, sym) {
			t.Fatalf("生成代码缺少 %q", sym)
		}
	}
	got, code := compileAndRunPolicy(t, src)
	if code != 0 || got != "abc\n0\n" {
		t.Fatalf("输出 %q(code %d)，期望 \"abc\\n0\\n\"", got, code)
	}
}
