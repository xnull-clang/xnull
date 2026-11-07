package sema

import "testing"

// BND-07 补口：abstract/前向引用/静态成员。
func TestS2BND07SingletonRules(t *testing.T) {
	expectCode(t, `
abstract singleton AppInfo { Int x = 1; }
static Int main() { return 0 }`, TySingletonRule)

	expectCode(t, `
singleton A { B b = B.instance; }
singleton B { Int x = 1; }
static Int main() { return 0 }`, TySingletonRule)

	expectNone(t, `
singleton AppInfo {
    static Int count = 1;
    static Int twice() { return count * 2 }
    Int id = 0;
}
static Int main() { return 0 }`)
}
