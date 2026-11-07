package interp

import "testing"

// S2 §5.4：super.m() 从父类起点静态查找；super.x 读写父类字段。
func TestS2SuperMethodAndField(t *testing.T) {
	t.Run("SuperMethod", func(t *testing.T) {
		out, err := runSrc(t, `
class A {
    Int f() { return 1 }
}
class B : A {
    Int g() { return super.f() + 1 }
}
static Int main() {
    B b = new B()
    print(b.g())
    return 0
}`)
		if err != nil || out != "2\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "2\n", err)
		}
	})
	t.Run("SuperFieldRead", func(t *testing.T) {
		out, err := runSrc(t, `
class A {
    Int x = 3;
}
class B : A {
    Int g() { return super.x + 1 }
}
static Int main() {
    B b = new B()
    print(b.g())
    return 0
}`)
		if err != nil || out != "4\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "4\n", err)
		}
	})
	t.Run("SuperFieldWrite", func(t *testing.T) {
		out, err := runSrc(t, `
class A {
    Int x = 1;
}
class B : A {
    void inc() { super.x = super.x + 1 }
}
static Int main() {
    B b = new B()
    b.inc()
    print(b.x)
    return 0
}`)
		if err != nil || out != "2\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "2\n", err)
		}
	})
	t.Run("MultiLevel", func(t *testing.T) {
		out, err := runSrc(t, `
class A {
    Int x = 1;
    Int f() { return 10 }
}
class B : A {
    Int g() { return super.f() + super.x }
}
class C : B {
    Int h() { return super.g() + 100 }
}
static Int main() {
    C c = new C()
    print(c.h())
    return 0
}`)
		if err != nil || out != "111\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "111\n", err)
		}
	})
}
