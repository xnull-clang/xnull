package sema

import "testing"

// BND-02：继承禁止面 + 方法静态复用。
func TestS2BND02InheritanceForbidden(t *testing.T) {
	// new abstract 类拒绝。
	expectCode(t, `
abstract class A { Int x = 0; }
static Int main() {
    A a = new A()
    return 0
}`, TyNewAbstract)

	// 继承 final 类拒绝。
	expectCode(t, `
final class B { Int x = 0; }
class D : B { }
static Int main() { return 0 }`, TyInherit)

	// @Override 禁止标记类继承方法。
	expectCode(t, `
class B { void go() { } }
class D : B {
    @Override
    void go() { }
}
static Int main() { return 0 }`, TyProtoImpl)

	// 子类继承父类方法（静态复用），不声明同签名也合法。
	expectNone(t, `
class B {
    Int go() { return 1 }
}
class D : B { }
static Int main() {
    D d = new D()
    return d.go()
}`)

	// 子类不同参数列表构成重载，合法。
	expectNone(t, `
class B { Int go(Int n) { return n } }
class D : B { Int go(String s) { return 1 } }
static Int main() { return 0 }`)
}
