package sema

import "testing"

// ENUM-01：switch default 必须位于最后。
func TestS2EnumDefaultLast(t *testing.T) {
	expectCode(t, `
enum Color { Red, Green }
static Int main() {
    Color c = Color.Red
    switch (c) {
        default:
            print("x")
        case Color.Red:
            print("r")
        case Color.Green:
            print("g")
    }
    return 0
}`, TyEnumSwitch)

	expectNone(t, `
enum Color { Red, Green }
static Int main() {
    Color c = Color.Red
    switch (c) {
        case Color.Red:
            print("r")
        case Color.Green:
            print("g")
        default:
            print("x")
    }
    return 0
}`)

	// 非枚举 switch 同样要求 default 最后。
	expectCode(t, `
static Int main() {
    Int x = 1
    switch (x) {
        default:
            print("x")
        case 1:
            print("one")
    }
    return 0
}`, TyEnumSwitch)
}
