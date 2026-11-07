package sema

import "testing"

// BND-09：继承链基名唯一/私有字段/受保护子类访问/字段隐藏。
func TestS2BND09FieldRules(t *testing.T) {
	// 公开 x 与子类 _x 基名冲突。
	expectCode(t, `
class B { Int x = 0; }
class D : B { Int _x = 1; }
static Int main() { return 0 }`, TyOverride)

	// private x 与子类 x 基名冲突。
	expectCode(t, `
class B { private Int x = 0; }
class D : B { Int x = 1; }
static Int main() { return 0 }`, TyOverride)

	// 同类内 x 与 _x 基名冲突。
	expectCode(t, `
class C { Int x = 0; Int _x = 1; }
static Int main() { return 0 }`, TyOverride)

	// 外部访问私有字段拒绝。
	expectCode(t, `
class C { private Int x = 0; }
static Int main() {
    C c = new C()
    print(c.x)
    return 0
}`, TyPrivField)

	// 受保护字段：子类 self 访问通过。
	expectNone(t, `
class B { protected Int x = 1; }
class D : B { Int get() { return self.x } }
static Int main() { return 0 }`)

	// 受保护字段：外部访问拒绝。
	expectCode(t, `
class B { protected Int x = 1; }
static Int main() {
    B b = new B()
    print(b.x)
    return 0
}`, TyVisibility)
}
