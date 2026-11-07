package sema

import "testing"

// BND-12 R01：静态成员不得使用类类型参数（§13.4）。
func TestS2BND12StaticTypeParam(t *testing.T) {
	expectCode(t, `
class Box<T> {
    static T value;
}
static Int main() { return 0 }`, TyStaticGen)

	expectCode(t, `
class Box<T> {
    static T get() { T z = 0; return z }
}
static Int main() { return 0 }`, TyStaticGen)

	// 实例字段/方法使用 T 合法。
	expectNone(t, `
class Box<T> {
    T value;
    T get() { return value }
}
static Int main() { return 0 }`)

	// 静态成员使用具体类型合法。
	expectNone(t, `
class Box<T> {
    static Int count = 0;
}
static Int main() { return 0 }`)
}
