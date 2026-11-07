package codegen

import (
	"strings"
	"testing"
)

// S3-05 P0-7：协议字段指向 GC 对象时纳入 scan；GC 类 deinit 不直接 release。
func TestS3_05ProtoFieldScan(t *testing.T) {
	src := `protocol P { Int f(); }
class Impl implements P { Int f() { return 7 } }
class Holder {
    P p;
    Holder(P q) { self.p = q }
}
static Int main() {
    Holder h = new Holder(new Impl())
    print(h.p.f())
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xn_Cls_Holder_gc_scan") || !strings.Contains(csrc, "visit(o->p);") {
		t.Fatalf("协议字段未纳入 scan：\n%s", csrc)
	}
	if strings.Contains(csrc, "rt_release(o->p);") {
		t.Fatalf("GC 类 deinit 不应直接 release 协议字段：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	if want := "7\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// S3-05：Any/Object 装箱（GC 盒）与 is/as? 拆箱。
func TestS3_05AnyBoxing(t *testing.T) {
	src := `static Int main() {
    Any a = 42 as Any
    print(a is Int)
    print(a as? Int)
    print(a is String)
    Any b = "hi" as Any
    print(b is String)
    print(b as? String)
    Any c = true as Any
    print(c is Bool)
    print(c as? Bool)
    return 0
}`
	csrc := emitWithPolicy(t, src)
	for _, want := range []string{"rt_gc_new(&RT_TYPE_XN_ANY)", "xn_box_int(", "xn_box_bool(", "xn_box_str(", "xn_any_is(", "xn_any_get_int("} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("缺少 Any 装箱产物 %q：\n%s", want, csrc)
		}
	}
	got, code := compileAndRunPolicy(t, src)
	want := "true\n42\nfalse\ntrue\nhi\ntrue\ntrue\n"
	if got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// S3-05：Any 字段（拥有者 GC）纳入 scan；对象拆箱到类。
func TestS3_05AnyFieldAndUnboxClass(t *testing.T) {
	src := `class C { Int x = 7; }
class Holder {
    Any v;
    Holder(Any x) { self.v = x }
}
static Int main() {
    Holder h = new Holder(42 as Any)
    print(h.v is Int)
    print(h.v as? Int)
    C c = new C()
    Any a = c as Any
    print(a is C)
    C? c2 = a as? C
    print(c2 != null)
    print(c2.x)
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xn_Any * v;") {
		t.Fatalf("Any 字段应为 xn_Any * 槽：\n%s", csrc)
	}
	if !strings.Contains(csrc, "visit(o->v);") {
		t.Fatalf("Any 字段未纳入 scan：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	want := "true\n42\ntrue\ntrue\n7\n"
	if got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// S3-05：含引用元素的元组字段——GC 类 scan 访问类引用，deinit 释放 String 元素。
func TestS3_05TupleRefScanDeinit(t *testing.T) {
	src := `class C { Int x = 3; }
class TH {
    (Int, String) p = (1, "x")
}
class TC {
    (Int, C) q = (2, new C())
}
static Int main() {
    TH h = new TH()
    print(h.p.0)
    print(h.p.1)
    TC t = new TC()
    print(t.q.0)
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xn_Cls_TH_deinit_hook") {
		t.Fatalf("含引用元组的类应有 deinit 钩子：\n%s", csrc)
	}
	if !strings.Contains(csrc, "rt_release((o->p).f1);") {
		t.Fatalf("元组 String 元素应由 deinit 释放：\n%s", csrc)
	}
	if !strings.Contains(csrc, "xn_Cls_TC_gc_scan") || !strings.Contains(csrc, "visit((o->q).f1);") {
		t.Fatalf("元组类引用元素应按路径纳入 scan：\n%s", csrc)
	}
	if strings.Contains(csrc, "rt_release((o->q).f1);") {
		t.Fatalf("GC 类元组中的类引用不应由 deinit 直接释放：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	want := "1\nx\n2\n"
	if got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}
