package sema

import "testing"

// BND-09/14 补口：super 私有、final 二次赋值、extension 目标。
func TestS2BND0914b(t *testing.T) {
	expectCode(t, `
class B { private Int x = 0; }
class D : B {
    Int get() { return super._x }
}
static Int main() { return 0 }`, TyPrivField)

	expectCode(t, `
class C { final Int x = 1; }
static Int main() {
    C c = new C()
    c.x = 2
    return 0
}`, TyFinalWrite)

	expectCode(t, `
extension Int {
    Int f() { return 1 }
}
static Int main() { return 0 }`, TyExtension)

	expectCode(t, `
class Box<T> { T v; }
extension Box<Int> {
    Int f() { return 1 }
}
static Int main() { return 0 }`, TyExtension)

	expectNone(t, `
class C { Int x = 0; }
extension C {
    Int f() { return 1 }
}
static Int main() { return 0 }`)

	// 构造器内 final 赋值一次仍合法。
	expectNone(t, `
class C {
    final Int x;
    C() { x = 1 }
}
static Int main() { return 0 }`)
}
