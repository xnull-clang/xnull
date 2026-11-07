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
