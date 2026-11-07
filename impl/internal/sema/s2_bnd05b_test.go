package sema

import "testing"

// BND-05 补口：协议变量只能调用协议声明的方法（§4.4）。
func TestS2BND05ProtocolMemberRestriction(t *testing.T) {
	// 协议外方法拒绝。
	expectCode(t, `
protocol P { void go(); }
class C implements P {
    void go() { }
    void extra() { }
}
static Int use(P p) {
    p.extra()
    return 0
}
static Int main() { return 0 }`, "TY-211")

	// 协议声明的方法允许。
	expectNone(t, `
protocol P { void go(); }
class C implements P { void go() { } }
static Int use(P p) {
    p.go()
    return 0
}
static Int main() { return 0 }`)

	// 协议变量字段访问拒绝。
	expectCode(t, `
protocol P { void go(); }
static Int use(P p) {
    print(p.x)
    return 0
}
static Int main() { return 0 }`, "TY-211")
}
