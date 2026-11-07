package codegen

import (
	"strings"
	"testing"
)

// S3-RESULT 1：Result 变量复制（内联值整值复制）。
func TestS3_RESULTCopy(t *testing.T) {
	src := `static Result<Int, String> mk(Int v) { return Ok(v) }
static Int take(Result<Int, String> r) { return r.unwrapOr(-1) }
static Int main() {
    Result<Int, String> a = mk(5)
    Result<Int, String> b = a
    print(b.unwrapOr(0))
    print(take(a))
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if want := "5\n5\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xn_Result_Int_String") {
		t.Fatalf("Result 应内联为结构体：\n%s", csrc)
	}
	if strings.Contains(csrc, "RT_TYPE_XN_RESULT") || strings.Contains(csrc, "Result 盒") {
		t.Fatalf("Result 不应有堆盒身份：\n%s", csrc)
	}
}

// S3-RESULT 2：Ok/Err 作类字段初始化式；字段 receiver 的 unwrapOr/isErr；
// 字段赋值（Ok/Err 构造）。
func TestS3_RESULTFieldInitAndReceiver(t *testing.T) {
	src := `class C {
    Result<Int, String> r = Ok(5)
    Result<Int, String> e = Err("bad")
}
static Int main() {
    C c = new C()
    print(c.r.unwrapOr(0))
    print(c.e.isErr())
    c.r = Ok(7)
    print(c.r.unwrapOr(0))
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if want := "5\ntrue\n7\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
	csrc := emitWithPolicy(t, src)
	for _, want := range []string{
		"typedef struct { int ok; int64_t v; rt_string *err; } xn_Result_Int_String;",
		"xn_Result_Int_String r;",
		"xn_Result_Int_String e;",
	} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("Result 字段未按内联结构体发射（缺 %q）：\n%s", want, csrc)
		}
	}
	if strings.Contains(csrc, "rt_gc_new(&RT_TYPE_XN_Result") {
		t.Fatalf("Result 字段不应分配 GC 盒：\n%s", csrc)
	}
}

// S3-RESULT 3：Result 字段复制/构造器内赋值（值语义，无盒身份）。
func TestS3_RESULTFieldCopyInCtor(t *testing.T) {
	src := `class C {
    Result<Int, String> r = Ok(3)
    Result<Int, String> copy;
    C() { self.copy = self.r }
}
static Int main() {
    C c = new C()
    print(c.copy.unwrapOr(0))
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if code != 0 || got != "3\n" {
		t.Fatalf("out=%q code=%d，期望 3", got, code)
	}
}
