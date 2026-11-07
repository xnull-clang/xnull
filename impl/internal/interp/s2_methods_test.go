package interp

import "testing"

// S2 §6.8：实例方法重载按实参类型/个数选择。
func TestS2MethodOverload(t *testing.T) {
	t.Run("ByType", func(t *testing.T) {
		out, err := runSrc(t, `
class M {
    Int f(Int x) { return x * 2 }
    Int f(String s) { return s.length() }
}
static Int main() {
    M m = new M()
    print(m.f(7))
    print(m.f("abc"))
    return 0
}`)
		if err != nil || out != "14\n3\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "14\n3\n", err)
		}
	})
	t.Run("ByArity", func(t *testing.T) {
		out, err := runSrc(t, `
class M {
    Int f(Int a) { return a }
    Int f(Int a, Int b) { return a + b }
}
static Int main() {
    M m = new M()
    print(m.f(1))
    print(m.f(1, 2))
    return 0
}`)
		if err != nil || out != "1\n3\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "1\n3\n", err)
		}
	})
	t.Run("InheritedOverload", func(t *testing.T) {
		out, err := runSrc(t, `
class A {
    Int f(Int x) { return x + 1 }
}
class B : A {
    Int f(String s) { return s.length() + 10 }
}
static Int main() {
    B b = new B()
    print(b.f(1))
    print(b.f("xy"))
    return 0
}`)
		if err != nil || out != "2\n12\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "2\n12\n", err)
		}
	})
}

// S2 §7.1/§7.2：静态字段/静态方法（类型名访问、类内裸名、静态重载、隐藏）。
func TestS2StaticMembers(t *testing.T) {
	t.Run("FieldAndMethod", func(t *testing.T) {
		out, err := runSrc(t, `
class C {
    static Int n = 4;
    static Int f() { return n + 1 }
    static Int g(Int x) { return x * 2 }
    static Int g(String s) { return s.length() }
}
static Int main() {
    print(C.n)
    print(C.f())
    print(C.g(3))
    print(C.g("abcd"))
    return 0
}`)
		if err != nil || out != "4\n5\n6\n4\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "4\n5\n6\n4\n", err)
		}
	})
	t.Run("ChildHidesParent", func(t *testing.T) {
		out, err := runSrc(t, `
class A {
    static Int f() { return 1 }
}
class B : A {
    static Int f() { return 2 }
}
static Int main() {
    print(A.f())
    print(B.f())
    return 0
}`)
		if err != nil || out != "1\n2\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "1\n2\n", err)
		}
	})
}
