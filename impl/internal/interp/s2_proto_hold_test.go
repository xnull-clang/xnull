package interp

import "testing"

// S2 §4.4：协议变量强持有具体对象；返回/字段生命周期与编译路径一致。
func TestS2ProtocolStrongHold(t *testing.T) {
	t.Run("ReturnValue", func(t *testing.T) {
		out, err := runSrc(t, `
protocol P { Int f(); }
class C implements P { Int f(){ return 7 } void deinit(){ print("dC") } }
static P make() { C c = new C(); return c }
static Int main() { P p = make(); print(p.f()); print("after"); return 0 }`)
		want := "7\nafter\ndC\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("FieldHold", func(t *testing.T) {
		out, err := runSrc(t, `
protocol P { Int f(); }
class C implements P { Int f(){ return 7 } void deinit(){ print("dC") } }
class H { P p; }
static Int main() {
    H h = new H()
    h.p = new C()
    print(h.p.f())
    print("after")
    return 0
}`)
		want := "7\nafter\ndC\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("A02Alignment", func(t *testing.T) {
		out, err := runSrc(t, `
protocol P { Int f(); }
class C implements P { Int f(){ return 7 } void deinit(){ print("dC") } }
class H { P p; }
static P make() { C c = new C(); return c }
static Int main() {
    P p = make()
    print(p.f())
    H h = new H()
    h.p = new C()
    print(h.p.f())
    P q = new C()
    if true { C c = new C(); q = c }
    print(q.f())
    return 0
}`)
		want := "7\n7\ndC\n7\ndC\ndC\ndC\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
}
