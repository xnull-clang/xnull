package sema

import "testing"

// BND-13/EXT-01：extension 目标/冲突/私有访问。
func TestS2EXT01(t *testing.T) {
	// 同包非泛型 class 扩展公开成员：通过。
	expectNone(t, `
class C { Int x = 1; }
extension C {
    Int twice() { return self.x * 2 }
}
static Int main() { return 0 }`)

	// 重复 extension。
	expectCode(t, `
class C { Int x = 1; }
extension C { Int a() { return 1 } }
extension C { Int b() { return 2 } }
static Int main() { return 0 }`, TyExtension)

	// 与目标已有方法同签名。
	expectCode(t, `
class C { Int f(Int n) { return n } }
extension C { Int f(Int n) { return n } }
static Int main() { return 0 }`, TyExtension)

	// 与继承方法同签名。
	expectCode(t, `
class B { Int f(Int n) { return n } }
class C : B { }
extension C { Int f(Int n) { return n } }
static Int main() { return 0 }`, TyExtension)

	// 子类覆写扩展方法。
	expectCode(t, `
class C { Int x = 1; }
extension C { Int f() { return 1 } }
class D : C { Int f() { return 2 } }
static Int main() { return 0 }`, TyOverride)

	// 泛型目标拒绝。
	expectCode(t, `
class Box<T> { T v; }
extension Box<Int> { Int f() { return 1 } }
static Int main() { return 0 }`, TyExtension)

	// 跨包/不存在目标拒绝。
	expectCode(t, `
import lib.device
extension Device { Int f() { return 1 } }
static Int main() { return 0 }`, TyExtension)

	// 扩展方法访问 private 字段拒绝。
	expectCode(t, `
class C { private Int x = 1; }
extension C { Int f() { return self._x } }
static Int main() { return 0 }`, TyExtension)

	// 扩展方法访问 protected 字段拒绝。
	expectCode(t, `
class C { protected Int x = 1; }
extension C { Int f() { return self.x } }
static Int main() { return 0 }`, TyExtension)
}
