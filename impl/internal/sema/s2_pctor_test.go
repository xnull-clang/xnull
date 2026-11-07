package sema

import "testing"

// PCTOR-01：主构造器三条 sema 规则。
func TestS2PCTORRules(t *testing.T) {
	// final 字段恰好赋值一次：初始化式 + 构造器重复赋值拒绝。
	expectCode(t, `
class C {
    final Int x = 1;
    C() { x = 2 }
}
static Int main() { return 0 }`, TyPCTOR)

	// 主构造器与普通构造器混用拒绝。
	expectCode(t, `
class C(final Int x) {
    C() { x = 0 }
}
static Int main() { return 0 }`, TyPCTOR)

	// 主构造器参数必须 final。
	expectCode(t, `
class C(Int x) {
}
static Int main() { return 0 }`, TyPCTOR)

	// 正例：主构造器 final 参数。
	expectNone(t, `
class C(final Int x) {
}
static Int main() {
    C c = new C(1)
    return 0
}`)

	// 正例：显式 final 字段在构造器中赋值一次。
	expectNone(t, `
class D {
    final Int x;
    D() { x = 1 }
}
static Int main() {
    D d = new D()
    return 0
}`)
}
