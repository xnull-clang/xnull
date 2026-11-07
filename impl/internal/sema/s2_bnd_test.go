package sema

import "testing"

// ---------- BND-01 成员可见性矩阵 ----------

func TestS2BND01VisibilityMatrix(t *testing.T) {
	// 同类内部可访问 public/protected/private 字段与方法。
	expectNone(t, `
class C {
    private Int a = 1;
    protected Int b = 2;
    public Int c = 3;

    private Int pa() { return _a }
    protected Int pb() { return b }
    public Int pc() { return c }

    Int all() { return _a + b + c + pa() + pb() + pc() }
}

static Int main() { return 0 }`)

	// 外部访问 protected/private 字段/方法必须报 TY-209。
	expectCode(t, `
class C {
    protected Int x = 1;
}
static Int main() {
    C c = new C()
    print(c.x)
    return 0
}`, "TY-209")
	expectCode(t, `
class C {
    private Int f() { return 1 }
}
static Int main() {
    C c = new C()
    print(c.f())
    return 0
}`, "TY-209")
	expectCode(t, `
class C {
    protected Int f() { return 1 }
}
static Int main() {
    C c = new C()
    print(c.f())
    return 0
}`, "TY-209")

	// 子类可通过 self 访问继承的 protected 成员。
	expectNone(t, `
class B {
    protected Int x = 7;
    protected Int f() { return x }
}
class D : B {
    Int g() { return self.x + self.f() }
}
static Int main() { return 0 }`)

	// 子类不能访问父类 private 成员。
	expectCode(t, `
class B {
    private Int x = 7;
}
class D : B {
    Int g() { return self.x }
}
static Int main() { return 0 }`, "TY-209")

	// 子类不能通过父类类型引用访问另一个实例的 protected 成员。
	expectCode(t, `
class B {
    protected Int x = 7;
}
class D : B {
    Int g(B other) { return other.x }
}
static Int main() { return 0 }`, "TY-209")
}

// ---------- BND-05 协议实现检查 ----------

func TestS2BND05ProtocolImplementation(t *testing.T) {
	// 完整实现通过。
	expectNone(t, `
protocol Ready {
    Bool ready();
}
class C implements Ready {
    Bool ready() { return true }
}
static Int main() { return 0 }`)

	// 缺方法。
	expectCode(t, `
protocol Ready {
    Bool ready();
}
class C implements Ready {
}
static Int main() { return 0 }`, "TY-208")

	// 签名/返回类型不符。
	expectCode(t, `
protocol Ready {
    Bool ready();
}
class C implements Ready {
    Int ready() { return 1 }
}
static Int main() { return 0 }`, "TY-208")

	// 父协议的方法也必须实现。
	expectCode(t, `
protocol Base {
    Bool base();
}
protocol Ready : Base {
    Bool ready();
}
class C implements Ready {
    Bool ready() { return true }
}
static Int main() { return 0 }`, "TY-208")

	// 实现方法必须公开：private/protected 不满足协议。
	expectCode(t, `
protocol Ready {
    Bool ready();
}
class C implements Ready {
    private Bool ready() { return true }
}
static Int main() { return 0 }`, "TY-208")

	// 继承的公开实例方法可以满足协议。
	expectNone(t, `
protocol Ready {
    Bool ready();
}
class B {
    Bool ready() { return true }
}
class C : B implements Ready {
}
static Int main() { return 0 }`)

	// @Override 对应协议方法：通过。
	expectNone(t, `
protocol Ready {
    Bool ready();
}
class C implements Ready {
    @Override
    Bool ready() { return true }
}
static Int main() { return 0 }`)

	// @Override 找不到协议方法：拒绝。
	expectCode(t, `
protocol Ready {
    Bool ready();
}
class C implements Ready {
    Bool ready() { return true }
    @Override
    Bool nope() { return false }
}
static Int main() { return 0 }`, "TY-208")

	// 两个协议同名同参但返回类型不同：无法同时实现。
	expectCode(t, `
protocol A {
    Bool f();
}
protocol B {
    Int f();
}
class C implements A, B {
    Bool f() { return true }
}
static Int main() { return 0 }`, "TY-208")
}
