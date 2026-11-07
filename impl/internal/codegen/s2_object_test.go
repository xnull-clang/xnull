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

// S2 §6.3/§6.5：显式构造器内 self 绑定（A02/A03）与 super(...) 首位（A05）。
func TestS2PctorSelfAndSuper(t *testing.T) {
	cases := []struct{ name, src, want string }{
		{"A02 无参构造器 self", `class E {
    Int v = 1;
    E() { self.v = 5 }
}
static Int main() { E e = new E(); print(e.v); return 0 }`, "5\n"},
		{"A03 带参构造器 self", `class D {
    Int v;
    D(Int x) { self.v = x }
}
static Int main() { D d = new D(5); print(d.v); return 0 }`, "5\n"},
		{"A05 super 首位 + 带参父构造", `class B {
    Int x;
    B(Int v) { self.x = v }
}
class D : B {
    Int y;
    D(Int v) {
        super(v)
        self.y = v + 1
    }
}
static Int main() { D d = new D(5); print(d.x); print(d.y); return 0 }`, "5\n6\n"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, code := compileAndRun(t, c.src)
			if code != 0 || got != c.want {
				t.Fatalf("out=%q code=%d，期望 %q / 0", got, code, c.want)
			}
		})
	}
}

// S2 §8：简单枚举格式化 + 穷尽 switch（A01/A02）。
func TestS2EnumSimpleAndSwitch(t *testing.T) {
	src := `enum Color { Red, Green, Blue }
static Int main() {
    Color c = Color.Green
    print(c)
    switch (c) {
        case Color.Red: print("r")
        case Color.Green: print("g")
        case Color.Blue: print("b")
    }
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "Green\ng\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// S2 §8.3：数据枚举项单例、字段访问与格式化（A03）。
func TestS2EnumDataSingleton(t *testing.T) {
	src := `enum Status {
    Ready(0), Failed(1);
    final Int code;
    Status(Int c) { self.code = c }
    Int get() { return self.code }
}
static Int main() {
    print(Status.Ready)
    print(Status.Ready.code)
    print(Status.Failed.get())
    print(Status.Ready == Status.Ready)
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "Ready\n0\n1\ntrue\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// S2 §3.3：struct 布局/值复制（A01）与嵌套值（A02）。
func TestS2StructValueCopy(t *testing.T) {
	src := `struct Point {
    Int x;
    Int y;
}
struct Inner { Int v; }
struct Outer { Inner inner; Int k; }
static Int copyOf(Point p) { p.x = 9; return p.x }
static Int main() {
    Point a = new Point()
    a.x = 1
    a.y = 2
    Point b = a
    b.x = 9
    print(a.x)
    print(b.x)
    print(copyOf(a))
    print(a.x)

    Outer o = new Outer()
    o.inner.v = 7
    o.k = 3
    Outer c = o
    c.inner.v = 9
    print(o.inner.v)
    print(c.inner.v)
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "1\n9\n9\n1\n7\n9\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}
