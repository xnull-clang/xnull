package interp

import "testing"

// S2 §5.6：协议接收者按运行时实际类动态派发；类接收者按静态类型静态派发。
func TestS2DispatchModel(t *testing.T) {
	t.Run("ProtocolDynamic", func(t *testing.T) {
		out, err := runSrc(t, `
protocol Value { Int get(); }
class One implements Value { Int get() { return 1 } }
class Two implements Value { Int get() { return 2 } }
static Int main() {
    Value a = new One()
    Value b = new Two()
    print(a.get())
    print(b.get())
    return 0
}`)
		if err != nil || out != "1\n2\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "1\n2\n", err)
		}
	})
	t.Run("ClassStaticInherited", func(t *testing.T) {
		out, err := runSrc(t, `
class Base { Int f() { return 1 } }
class Derived : Base { Int g() { return 2 } }
static Int main() {
    Base value = new Derived()
    print(value.f())
    return 0
}`)
		if err != nil || out != "1\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "1\n", err)
		}
	})
	t.Run("ClassStaticRejectsDerivedOnlyMethod", func(t *testing.T) {
		_, code, err := runSrcCode(t, `
class Base { Int f() { return 1 } }
class Derived : Base { Int g() { return 2 } }
static Int main() {
    Base value = new Derived()
    print(value.g())
    return 0
}`)
		if err == nil || code == 0 {
			t.Fatalf("类静态类型不得调用派生类独有方法：code=%d err=%v", code, err)
		}
	})
	t.Run("ProtocolRejectsNonProtocolMethod", func(t *testing.T) {
		_, code, err := runSrcCode(t, `
protocol P { Int f(); }
class C implements P {
    Int f() { return 1 }
    Int g() { return 2 }
}
static Int main() {
    P p = new C()
    print(p.g())
    return 0
}`)
		if err == nil || code == 0 {
			t.Fatalf("协议接收者不得调用协议外方法：code=%d err=%v", code, err)
		}
	})
}
