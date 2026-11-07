package sema

import "testing"

// BND-04：结构体值字段 + 泛型结构体实参值类型。
func TestS2BND04StructValueRules(t *testing.T) {
	// 泛型结构体声明本身合法（类型参数延后到实例化检查）。
	expectNone(t, `
struct Pair<A, B> {
    A a;
    B b;
}
static Int main() { return 0 }`)

	// 值类型实参合法。
	expectNone(t, `
struct Pair<A, B> { A a; B b; }
struct Holder { Pair<Int, Int> p; }
static Int main() {
    Pair<Int, Int> q
    return 0
}`)

	// 引用类型实参拒绝（字段位置）。
	expectCode(t, `
struct Pair<A, B> { A a; B b; }
struct Holder { Pair<String, Int> p; }
static Int main() { return 0 }`, TyStructVal)

	// 引用类型实参拒绝（局部位置）。
	expectCode(t, `
struct Pair<A, B> { A a; B b; }
static Int main() {
    Pair<String, Int> p
    return 0
}`, TyStructVal)

	// 嵌套值元组/标量实参合法。
	expectNone(t, `
struct Pair<A, B> { A a; B b; }
struct Holder { Pair<(Int, Int), Bool> p; }
static Int main() { return 0 }`)

	// 泛型字段只能引用本声明类型参数；List<T> 仍非值字段。
	expectCode(t, `
struct Box<T> {
    List<T> xs;
}
static Int main() { return 0 }`, TyStructVal)
}
