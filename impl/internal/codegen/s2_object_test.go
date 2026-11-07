package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
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

// S2 §2.8/§3.3/§5.7/§3.6（BND-11）：对象身份、结构体复制、vtable 槽位、sret 值语义。
func TestS2BND11ClassIdentity(t *testing.T) {
	src := `class C { Int v; }
static Int main() {
    C a = new C()
    C b = a
    C c = new C()
    print(a == b)
    print(a === b)
    print(a == c)
    print(a === c)
    print(a !== c)
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "true\ntrue\nfalse\nfalse\ntrue\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// BND-11：struct 返回值（sret）不暴露共享身份；副本独立。
func TestS2BND11StructSretCopy(t *testing.T) {
	src := `struct P { Int x; Int y; }
static P make(Int v) {
    P p = new P()
    p.x = v
    p.y = v + 1
    return p
}
static P pass(P p) { return p }
static Int main() {
    P a = make(1)
    P b = pass(a)
    b.x = 9
    print(a.x)
    print(b.x)
    print(a.y)
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "1\n9\n2\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// BND-11：协议 vtable 只含协议槽位，普通类方法不进入 vtable。
func TestS2BND11VtableOnlyProtocolSlots(t *testing.T) {
	src := `protocol P { Int f(); }
class C implements P {
    Int f() { return 1 }
    Int g() { return 2 }
}
static Int main() { C c = new C(); print(c.g()); return 0 }`
	u, diags := xfront.ParseUnit("vt.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	csrc, err := EmitC(u)
	if err != nil {
		t.Fatalf("EmitC: %v", err)
	}
	if !strings.Contains(csrc, "xn_vt_C[") {
		t.Fatalf("缺少 vtable 定义：\n%s", csrc)
	}
	if !strings.Contains(csrc, "xn_vt_C[0] = (void *)&xn_Cls_C_f;") {
		t.Fatalf("vtable 未填充协议槽 f：\n%s", csrc)
	}
	if strings.Contains(csrc, "&xn_Cls_C_g") {
		t.Fatalf("普通方法 g 进入了 vtable：\n%s", csrc)
	}
	got, code := compileAndRun(t, src)
	if got != "2\n" || code != 0 {
		t.Fatalf("out=%q code=%d，期望 2", got, code)
	}
}

// BND-02：多级继承 + 协议实现时字段/vtable 偏移一致（A02 回归）。
func TestS2BND02MultiInheritanceProtocol(t *testing.T) {
	src := `protocol Ready { Bool ready(); }
class A { Int a = 1; Int fa() { return 2 } }
class B : A { Int b = 3; Int fb() { return 4 } }
class C : B implements Ready {
    Int c = 5;
    Bool ready() { return true }
}
static Int main() {
    C x = new C()
    print(x.a)
    print(x.fa())
    print(x.b)
    print(x.fb())
    print(x.c)
    print(x.ready())
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "1\n2\n3\n4\n5\ntrue\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// BND-03：可空协议字段（P? peer = null）与 deinit 链。
func TestS2BND03NullableProtocolAndDeinit(t *testing.T) {
	src := `protocol P { Int f(); }
class Ref implements P {
    P? peer = null;
    Int x = 7;
    Int f() { return x }
}
class B { void deinit() { print("dB") } }
class D : B {
    void deinit() { print("dD"); super.deinit() }
}
static Int main() {
    Ref r = new Ref()
    print(r.f())
    D d = new D()
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "7\ndD\ndB\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// DISP-01：is / as? / 类变量隐式上转到协议。
func TestS2DISP01IsAsUpcast(t *testing.T) {
	src := `protocol P { Int f(); }
class C implements P { Int f() { return 1 } }
static Int main() {
    C c = new C()
    print(c is P)
    P p = new C()
    print(p is C)
    C? c2 = p as? C
    print(c2 != null)
    P p2 = c
    print(p2.f())
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "true\ntrue\ntrue\n1\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// BND-12：泛型类单态化（实例化、字段替换、方法实例名）。
func TestS2BND12GenericClassBasic(t *testing.T) {
	src := `class Box<T> {
    T v;
    Box(T value) { self.v = value }
    T get() { return self.v }
}
static Int main() {
    Box<Int> b = new Box<Int>(7)
    print(b.get())
    Box<String> s = new Box<String>("x")
    print(s.get())
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "7\nx\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
	u, diags := xfront.ParseUnit("g.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	csrc, err := EmitC(u)
	if err != nil {
		t.Fatalf("EmitC: %v", err)
	}
	for _, want := range []string{"xn_Cls_Box_i_get", "xn_Cls_Box_s_get", "int64_t v;", "rt_string * v;"} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("缺少实例化产物 %q：\n%s", want, csrc)
		}
	}
}

// BND-12：嵌套泛型（泛型类字段为另一泛型实例）与多类型参数。
func TestS2BND12GenericClassNested(t *testing.T) {
	src := `class Box<T> {
    T v;
    Box(T value) { self.v = value }
    T get() { return self.v }
}
class Nest<T> {
    Box<T> inner;
    Nest(T v) { self.inner = new Box<T>(v) }
    T get() { return self.inner.get() }
}
class Pair<A, B> {
    A a;
    B b;
    Pair(A x, B y) { self.a = x; self.b = y }
    A first() { return self.a }
    B second() { return self.b }
}
static Int main() {
    Nest<Int> n = new Nest<Int>(5)
    print(n.get())
    Pair<Int, String> p = new Pair<Int, String>(3, "y")
    print(p.first())
    print(p.second())
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "5\n3\ny\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// emitAndRunNoSema 绕过 sema 验证 codegen 发射面（sema 支持由 E2 并行接入）。
func emitAndRunNoSema(t *testing.T, src string) (string, int) {
	t.Helper()
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	csrc, err := EmitC(u)
	if err != nil {
		t.Fatalf("EmitC: %v", err)
	}
	dir := t.TempDir()
	cf := filepath.Join(dir, "p.c")
	if err := os.WriteFile(cf, []byte(csrc), 0o644); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "p")
	rt := filepath.Join("..", "..", "..", "impl", "runtime")
	args := []string{"-std=c11", "-O2", "-I", rt, "-o", bin, cf}
	for _, s := range runtimeCSources {
		args = append(args, filepath.Join(rt, s))
	}
	cc := exec.Command("cc", args...)
	var cerr bytes.Buffer
	cc.Stderr = &cerr
	if err := cc.Run(); err != nil {
		t.Fatalf("cc 失败：%v\n%s\n---- C ----\n%s", err, cerr.String(), csrc)
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	code := 0
	if err := run.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			t.Fatalf("运行失败：%v", err)
		}
	}
	return out.String(), code
}

// BND-07：单例 instance 访问/字段初始化/方法调用（codegen 面）。
func TestS2BND07Singleton(t *testing.T) {
	src := `singleton AppInfo {
    final String name = "XNull"
    Int n = 3
    Int twice() { return self.n * 2 }
}
static Int main() {
    print(AppInfo.instance.name)
    print(AppInfo.instance.twice())
    AppInfo.instance.n = 4
    print(AppInfo.instance.twice())
    return 0
}`
	got, code := emitAndRunNoSema(t, src)
	if want := "XNull\n6\n8\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// BND-08：工厂静态方法发射（非泛型）。
func TestS2BND08Factory(t *testing.T) {
	src := `class Device {
    String name;
    Device(String n) { self.name = n }
}
factory DeviceFactory for Device {
    static Device create(String name) {
        return new Device(name)
    }
}
static Int main() {
    Device d = DeviceFactory.create("A")
    print(d.name)
    return 0
}`
	got, code := emitAndRunNoSema(t, src)
	if want := "A\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// BND-08：工厂泛型方法（显式类型实参）与泛型目标。
func TestS2BND08FactoryGeneric(t *testing.T) {
	src := `class Box<T> {
    T v;
    Box(T value) { self.v = value }
    T get() { return self.v }
}
factory BoxFactory for Box {
    static Box<T> create<T>(T value) {
        return new Box<T>(value)
    }
}
static Int main() {
    Box<Int> b = BoxFactory.create<Int>(9)
    print(b.get())
    return 0
}`
	got, code := emitAndRunNoSema(t, src)
	if want := "9\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// STRUCT-01 A02：嵌套值 struct + 可空值字段（Int?）成员读写。
func TestS2STRUCT01NestedNullable(t *testing.T) {
	src := `struct Inner {
    Int v = 1;
}
struct Outer {
    Inner inner = new Inner();
    Int? opt = null;
}
static Int main() {
    Outer o = new Outer()
    print(o.inner.v)
    o.opt = 5
    print(o.opt)
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "1\n5\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// STRUCT-01：可空值字段初始化式（Int? v = 1）与 null 清空。
func TestS2STRUCT01NullableInit(t *testing.T) {
	src := `struct S { Int? v = 1; }
static Int main() {
    S s = new S()
    print(s.v)
    s.v = null
    print(s.v)
    return 0
}`
	got, code := compileAndRun(t, src)
	if want := "1\nnull\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}
