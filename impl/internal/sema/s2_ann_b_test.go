package sema

import "testing"

// ANN 补口：常量/参数/类型/值/new/未知位置。
func TestS2ANNbRules(t *testing.T) {
	// 注解字段初始化式必须常量。
	expectCode(t, `
static Int f() { return 1 }
@annotation A { final Int x = f(); }
static Int main() { return 0 }`, TyAnnotation)

	// 参数个数过多。
	expectCode(t, `
@annotation A { final Int x = 0; }
@A(1, 2)
class C { Int y = 0; }
static Int main() { return 0 }`, TyAnnotation)

	// 参数类型不匹配。
	expectCode(t, `
@annotation A { final Int x = 0; }
@A("s")
class C { Int y = 0; }
static Int main() { return 0 }`, TyAnnotation)

	// 注解不能作类型。
	expectCode(t, `
@annotation A { final Int x = 0; }
static Int main() {
    A a
    return 0
}`, TyAnnotation)

	// 注解不能 new。
	expectCode(t, `
@annotation A { final Int x = 0; }
static Int main() {
    A a = new A()
    return 0
}`, TyAnnotation)

	// 枚举项未知注解。
	expectCode(t, `
enum E { @Nope A, B }
static Int main() { return 0 }`, TyAnnotation)

	// 顶层函数参数未知注解。
	expectCode(t, `
static Int f(@Nope Int x) { return x }
static Int main() { return 0 }`, TyAnnotation)
}
