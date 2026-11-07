package codegen

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// S2 §6.3 / PCTOR-01：构造器体必须执行（无参 / 带参 / 主构造器），不再静默丢弃。
func TestS2CtorBodies(t *testing.T) {
	src := `
class NoArg {
    Int x;
    NoArg() { x = 7 }
}
class WithArg {
    Int x;
    WithArg(Int v) { x = v }
}
class Worker(final Int id) { }
static Int main() {
    NoArg a = new NoArg()
    print(a.x)
    WithArg b = new WithArg(9)
    print(b.x)
    Worker w = new Worker(5)
    print(w.id)
    return 0
}`
	want := "7\n9\n5\n"
	got, code := compileAndRun(t, src)
	if got != want || code != 0 {
		t.Fatalf("编译路径输出 %q(code %d)，期望 %q", got, code, want)
	}
}

// S2 §2.5/§5.1：单继承布局（父类字段/方法复用、静态派发、deinit 链）。
func TestS2InheritanceLayout(t *testing.T) {
	src := `
class Base {
    Int x = 1;
    Int f() { return x + 10 }
    void deinit() { print("base-deinit") }
}
class Derived : Base {
    Int y = 2;
    Int g() { return f() + y }
}
static Int main() {
    Derived d = new Derived()
    print(d.x)
    print(d.y)
    print(d.f())
    print(d.g())
    return 0
}`
	want := "1\n2\n11\n13\nbase-deinit\n"
	got, code := compileAndRun(t, src)
	if got != want || code != 0 {
		t.Fatalf("编译路径输出 %q(code %d)，期望 %q", got, code, want)
	}
}

// S2 §5.7：实现协议的类在载荷起始位置带 vtable 指针槽。
func TestS2ProtocolVtableLayout(t *testing.T) {
	src := `
protocol V { Int get(); }
class One implements V { Int get() { return 1 } }
static Int main() { One o = new One(); print(o.get()); return 0 }`
	u, diags := xfront.ParseUnit("v.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	csrc, err := EmitC(u)
	if err != nil {
		t.Fatalf("EmitC: %v", err)
	}
	if !strings.Contains(csrc, "void **__vtable;") {
		t.Fatalf("协议实现类缺少 vtable 指针槽：\n%s", csrc)
	}
	got, code := compileAndRun(t, src)
	if got != "1\n" || code != 0 {
		t.Fatalf("编译路径输出 %q(code %d)，期望 1", got, code)
	}
}

func TestS2DeinitBody(t *testing.T) {
	src := `
class D {
    String s = "a";
    Int n = 1;
    void deinit() {
        print("bye")
        self.s = null
        self.n = 2
    }
}
static Int main() {
    D d = new D()
    print(d.n)
    return 0
}`
	got, code := compileAndRun(t, src)
	if got != "1\nbye\n" || code != 0 {
		t.Fatalf("编译路径输出 %q(code %d)，期望 %q", got, code, "1\nbye\n")
	}
}
