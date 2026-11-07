package sema

import "testing"

// EXT 补口：singleton/数据 enum 扩展允许；跨包扩展拒绝。
func TestS2EXTbTargets(t *testing.T) {
	expectNone(t, `
singleton AppInfo { Int x = 1; }
extension AppInfo { Int twice() { return self.x * 2 } }
static Int main() { return 0 }`)

	expectNone(t, `
enum Status {
    Ready(0);
    final Int code;
    Status(Int c) { self.code = c }
}
extension Status { Int get() { return self.code } }
static Int main() { return 0 }`)

	expectCode(t, `
import lib.device
class Device { Int x = 0; }
extension Device { Int f() { return 1 } }
static Int main() { return 0 }`, TyExtension)
}
