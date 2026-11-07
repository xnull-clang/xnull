package interp

import "testing"

// S2 §6.4：块作用域结束时执行 deinit；派生→父类链，显式 super.deinit 接管。
func TestS2DeinitChain(t *testing.T) {
	t.Run("SingleScope", func(t *testing.T) {
		out, err := runSrc(t, `
class D {
    void deinit() { print("dD") }
}
static Int main() {
    if true {
        D d = new D()
    }
    print("after")
    return 0
}`)
		if err != nil || out != "dD\nafter\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "dD\nafter\n", err)
		}
	})
	t.Run("ExplicitSuper", func(t *testing.T) {
		out, err := runSrc(t, `
class B {
    Int f() { return 1 }
    B() { print("B") }
    void deinit() { print("dB") }
}
class D : B {
    D() { print("D") }
    void deinit() { print("dD"); super.deinit() }
}
static Int main() {
    if true {
        D d = new D()
        print(d.f())
    }
    print("after")
    return 0
}`)
		want := "B\nD\n1\ndD\ndB\nafter\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("AutoParent", func(t *testing.T) {
		out, err := runSrc(t, `
class B {
    void deinit() { print("dB") }
}
class D : B {
}
static Int main() {
    if true {
        D d = new D()
    }
    print("after")
    return 0
}`)
		if err != nil || out != "dB\nafter\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "dB\nafter\n", err)
		}
	})
}
