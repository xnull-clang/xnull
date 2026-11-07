package sema

import "testing"

// GATE-01 补口：new 非 class 类型在 check 阶段拒绝。
func TestS2GATENewKinds(t *testing.T) {
	expectCode(t, `
protocol P { void go(); }
static Int main() {
    P p = new P()
    return 0
}`, TyNewKind)

	expectCode(t, `
enum E { A, B }
static Int main() {
    E e = new E()
    return 0
}`, TyNewKind)
}
