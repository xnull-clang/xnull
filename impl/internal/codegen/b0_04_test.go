// b0_04_test.go —— M6-B0-04 类字段初值（S2 §6.3 L678-679）。
//
// 条款：字段初始化式在父类构造完成后、构造器体之前按声明顺序执行；
// 不能引用 self、其他实例字段或构造器参数；可以引用常量、静态成员和顶层函数。
//
// 本文件先红后绿：合法形态必须双路径逐字节一致；非法形态必须被拒绝。
package codegen

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// TestB0_04FieldInitForms 合法初始化式全形态：标量表达式、String 表达式/str()/顶层调用、
// 非空容器字面量、new 引用。
func TestB0_04FieldInitForms(t *testing.T) {
	src := `
class Node {
    Int v = 0;
}
static String mk() {
    return "mk"
}
class C {
    Int a = 1 + 2;
    Bool b = 1 < 2;
    String s = "x" + "y";
    String t = str(42);
    String u = mk();
    List<Int> xs = [1, 2];
    Map<String, Int> m = ["k": 7];
    Set<Int> st = [1, 2, 2];
    Node n2 = new Node();
}
static Int main() {
    C c = new C();
    print(c.a)
    print(c.b)
    print(c.s)
    print(c.t)
    print(c.u)
    print(c.xs.length())
    print(c.xs.get(1))
    print(c.m.getOr("k", 0))
    print(c.st.length())
    print(c.n2.v)
    return 0
}`
	want := "3\ntrue\nxy\n42\nmk\n2\n2\n7\n2\n0\n"
	got, code := compileAndRun(t, src)
	igot, icode := interpRun(t, src)
	if igot != want || icode != 0 {
		t.Fatalf("解释路径期望 %q，实际 %q(code %d)", want, igot, icode)
	}
	if got != want || code != 0 {
		t.Fatalf("编译路径输出 %q(code %d)，期望 %q", got, code, want)
	}
}

// TestB0_04FieldInitOrder 声明顺序执行，且在构造器体之前。
func TestB0_04FieldInitOrder(t *testing.T) {
	src := `
static Int tick(Int v) {
    print(v)
    return v
}
class C {
    Int a = tick(1);
    Int b = tick(2);
}
static Int main() {
    print("before")
    C c = new C();
    print(c.a + c.b)
    return 0
}`
	want := "before\n1\n2\n3\n"
	got, code := compileAndRun(t, src)
	igot, icode := interpRun(t, src)
	if igot != want || icode != 0 {
		t.Fatalf("解释路径期望 %q，实际 %q(code %d)", want, igot, icode)
	}
	if got != want || code != 0 {
		t.Fatalf("编译路径输出 %q(code %d)，期望 %q", got, code, want)
	}
}

// TestB0_04EmptySetField 空 Set 字段（回归 N-08：曾生成 xn_set_*_new(0), C 编译失败）。
func TestB0_04EmptySetField(t *testing.T) {
	src := `
class C {
    Set<String> tags = [];
    List<Int> xs = [];
    Map<String, Int> m = [];
}
static Int main() {
    C c = new C();
    print(c.tags.length())
    print(c.xs.length())
    print(c.m.length())
    return 0
}`
	want := "0\n0\n0\n"
	got, code := compileAndRun(t, src)
	igot, icode := interpRun(t, src)
	if igot != want || icode != 0 {
		t.Fatalf("解释路径期望 %q，实际 %q(code %d)", want, igot, icode)
	}
	if got != want || code != 0 {
		t.Fatalf("编译路径输出 %q(code %d)，期望 %q", got, code, want)
	}
}

// TestB0_04ClassFieldForward 字段初值 new 了「后声明」的类：构造器原型必须先于使用（S1-06 同族）。
func TestB0_04ClassFieldForward(t *testing.T) {
	src := `
class A {
    B b = new B();
    Int n = 1;
}
class B {
    Int v = 5;
}
static Int main() {
    A a = new A();
    print(a.n)
    print(a.b.v)
    return 0
}`
	want := "1\n5\n"
	got, code := compileAndRun(t, src)
	igot, icode := interpRun(t, src)
	if igot != want || icode != 0 {
		t.Fatalf("解释路径期望 %q，实际 %q(code %d)", want, igot, icode)
	}
	if got != want || code != 0 {
		t.Fatalf("编译路径输出 %q(code %d)，期望 %q", got, code, want)
	}
}

// TestB0_04RejectSelfInFieldInit S2 §6.3 L679：字段初值不得引用 self / 其他实例字段。
// 合法拒绝即可（诊断归 sema；codegen 至少不得生成非法 C）。
func TestB0_04RejectSelfInFieldInit(t *testing.T) {
	cases := []struct{ id, src string }{
		{"self", `class C {
    Int a = 1;
    Int b = self.a + 1;
}
static Int main() { C c = new C(); print(c.b); return 0 }`},
		{"bareField", `class C {
    Int a = 1;
    Int b = a + 1;
}
static Int main() { C c = new C(); print(c.b); return 0 }`},
	}
	for _, c := range cases {
		c := c
		t.Run(c.id, func(t *testing.T) {
			u, diags := xfront.ParseUnit("g.x", c.src)
			if len(diags) != 0 {
				t.Fatalf("解析诊断：%v", diags)
			}
			// sema 若拒绝即算达标；否则 codegen 必须显式拒绝且不得产出非法 C。
			if sd := sema.Analyze("g.x", u); len(sd) != 0 {
				return
			}
			if _, err := EmitC(u); err == nil {
				t.Fatal("字段初值引用 self/字段被静默接受（S2 §6.3 L679）")
			} else if !strings.Contains(err.Error(), "初值") {
				t.Fatalf("拒绝原因不明确：%v", err)
			}
		})
	}
}
