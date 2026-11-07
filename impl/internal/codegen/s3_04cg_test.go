package codegen

import (
	"os"
	"strings"
	"testing"
)

// S3-04cg：Text / StringBuilder 发射对齐 E5 运行时 API（xrt_text_* / xrt_sb_*）。
func TestS3_04cgTextSBStringEmission(t *testing.T) {
	src := `import xdk.text
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
    return n + tl + cp
}`
	csrc := emitWithPolicy(t, src)
	for _, want := range []string{
		"xrt_sb_new();",
		"xrt_sb_append_str(b,",
		"xrt_sb_append_int(b,",
		"xrt_sb_to_string(b)",
		"xrt_sb_length(b)",
		"xrt_text_from_string(",
		"xrt_text_length(t)",
		"xrt_text_code_point_count(t)",
		"xrt_text_to_string(t)",
	} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("缺少 S3-04 发射产物 %q：\n%s", want, csrc)
		}
	}
	main := funcBody(csrc, "int64_t xn_main() {")
	for _, want := range []string{"xn_root_add(b);", "xn_root_add(s);", "xn_root_add(t);", "xn_root_add(ts);"} {
		if !strings.Contains(main, want) {
			t.Fatalf("Text/StringBuilder/String 局部未登记 GC 根 %q：\n%s", want, main)
		}
	}
}

// S3-04cg：String/Bytes 局部根登记；中途收集中不丢失（运行验证）。
func TestS3_04cgStringBytesRoots(t *testing.T) {
	src := `class N { N? next; Int x = 0; }
static Int main() {
    String s = "keep"
    Bytes b = Bytes.fromString("abc")
    Int i = 0
    while (i < 3000) {
        N tmp = new N()
        String t = $"v{i}"
        i = i + 1
    }
    print(s)
    print(b.length())
    return 0
}`
	csrc := emitWithPolicy(t, src)
	main := funcBody(csrc, "int64_t xn_main() {")
	if !strings.Contains(main, "xn_root_add(s);") || !strings.Contains(main, "xn_root_add(b);") {
		t.Fatalf("String/Bytes 局部未登记 GC 根：\n%s", main)
	}
	got, code := compileAndRunPolicy(t, src)
	if want := "keep\n3\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// S3-04cg：含 String/Bytes/Text/SB 字段的类纳入 scan（GC 可达性）。
func TestS3_04cgFieldScan(t *testing.T) {
	src := `class Holder {
    String s = "a"
    Bytes b;
    Holder() { self.b = Bytes.fromString("x") }
}
static Int main() {
    Holder h = new Holder()
    print(h.s)
    print(h.b.length())
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xn_Cls_Holder_gc_scan") {
		t.Fatalf("含 GC 引用字段的类应生成 scan：\n%s", csrc)
	}
	for _, want := range []string{"visit(o->s);", "visit(o->b);"} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("String/Bytes 字段未纳入 scan（%s）：\n%s", want, csrc)
		}
	}
	if !strings.Contains(csrc, "xn_gc_new(&RT_TYPE_XN_Holder)") {
		t.Fatalf("含 GC 引用字段的类应按 GC 分配：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	if want := "a\n1\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// S3-04cg：Text/StringBuilder 运行期（需 E5 S3-04 运行时：xrt_text_*/xrt_sb_*）。
// main 运行时尚无这些符号时跳过；在 E5 分支上必须通过。
func TestS3_04cgTextSBRun(t *testing.T) {
	hdr, err := os.ReadFile("../../../impl/runtime/xrt.h")
	if err != nil || !strings.Contains(string(hdr), "xrt_sb_new") {
		t.Skip("当前运行时未包含 S3-04 Text/StringBuilder API（等待 E5 合并）")
	}
	src := `import xdk.text
static Int main() {
    StringBuilder b = StringBuilder()
    b.append("n=")
    b.append(42)
    String s = b.toString()
    Text t = Text.fromString(s)
    print(t.toString())
    print(t.length())
    print(t.codePointCount())
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if want := "n=42\n4\n4\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}
