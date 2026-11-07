package interp

import "testing"

// S2 §6.3：显式构造器必须执行；字段初始化式在构造器体前。
func TestS2ExplicitConstructorRuntime(t *testing.T) {
	t.Run("NoArg", func(t *testing.T) {
		out, err := runSrc(t, `
class E {
    Int v = 1;
    E() { self.v = 5 }
}
static Int main() { E e = new E(); print(e.v); return 0 }
`)
		if err != nil || out != "5\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "5\n", err)
		}
	})
	t.Run("WithParam", func(t *testing.T) {
		out, err := runSrc(t, `
class D {
    Int v;
    D(Int x) { self.v = x }
}
static Int main() { D d = new D(5); print(d.v); return 0 }
`)
		if err != nil || out != "5\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "5\n", err)
		}
	})
	t.Run("OverloadByArity", func(t *testing.T) {
		out, err := runSrc(t, `
class O {
    Int v = 0;
    O() { self.v = 1 }
    O(Int x) { self.v = x + 1 }
}
static Int main() {
    O a = new O()
    O b = new O(9)
    print(a.v)
    print(b.v)
    return 0
}
`)
		if err != nil || out != "1\n10\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "1\n10\n", err)
		}
	})
	t.Run("FieldInitBeforeBody", func(t *testing.T) {
		out, err := runSrc(t, `
class F {
    Int a = 1;
    F() { self.a = self.a + 1 }
}
static Int main() { F f = new F(); print(f.a); return 0 }
`)
		if err != nil || out != "2\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "2\n", err)
		}
	})
}

// S2 §5.8：方法/字段初值中的裸字段名按 self 字段解析。
func TestS2BareFieldResolution(t *testing.T) {
	t.Run("ReadAndWrite", func(t *testing.T) {
		out, err := runSrc(t, `
class A {
    Int x = 1;
    Int get() { return x }
    void inc() { x = x + 1 }
}
static Int main() {
    A a = new A()
    a.inc()
    print(a.get())
    return 0
}
`)
		if err != nil || out != "2\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "2\n", err)
		}
	})
	t.Run("FieldInitializer", func(t *testing.T) {
		out, err := runSrc(t, `
class C {
    Int a = 1;
    Int b = a + 1;
}
static Int main() { C c = new C(); print(c.b); return 0 }
`)
		if err != nil || out != "2\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "2\n", err)
		}
	})
}

// S2 §6.3/§6.5：super(...) 先于当前类字段初值与构造器体；父构造器体先完成。
func TestS2SuperConstructorOrder(t *testing.T) {
	t.Run("ExplicitSuper", func(t *testing.T) {
		out, err := runSrc(t, `
class B {
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
static Int main() {
    D d = new D(5)
    print(d.x)
    print(d.y)
    return 0
}`)
		if err != nil || out != "5\n6\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "5\n6\n", err)
		}
	})
	t.Run("ImplicitSuper", func(t *testing.T) {
		out, err := runSrc(t, `
class B {
    Int x = 1;
    B() { self.x = 2 }
}
class D : B {
    Int y = 3;
}
static Int main() {
    D d = new D()
    print(d.x)
    print(d.y)
    return 0
}`)
		if err != nil || out != "2\n3\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "2\n3\n", err)
		}
	})
	t.Run("ParentBodyBeforeChildFieldInit", func(t *testing.T) {
		out, err := runSrc(t, `
class B {
    Int x = 1;
    B() { x = 2 }
}
class D : B {
    Int y = x + 1;
}
static Int main() {
    D d = new D()
    print(d.x)
    print(d.y)
    return 0
}`)
		if err != nil || out != "2\n3\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "2\n3\n", err)
		}
	})
}
