package sema

import "testing"

// BND-06：枚举 switch 穷尽性/未知项/重复项/任意表达式。
func TestS2BND06EnumSwitch(t *testing.T) {
	// 穷尽：通过。
	expectNone(t, `
enum Color { Red, Green }
static Int main() {
    Color c = Color.Red
    switch (c) {
        case Color.Red:
            print("r")
        case Color.Green:
            print("g")
    }
    return 0
}`)

	// 遗漏项：拒绝。
	expectCode(t, `
enum Color { Red, Green }
static Int main() {
    Color c = Color.Red
    switch (c) {
        case Color.Red:
            print("r")
    }
    return 0
}`, TyEnumSwitch)

	// 未知项：拒绝。
	expectCode(t, `
enum Color { Red, Green }
static Int main() {
    Color c = Color.Red
    switch (c) {
        case Color.Red:
            print("r")
        case Color.Blue:
            print("b")
        case Color.Green:
            print("g")
    }
    return 0
}`, TyEnumSwitch)

	// 重复项：拒绝。
	expectCode(t, `
enum Color { Red, Green }
static Int main() {
    Color c = Color.Red
    switch (c) {
        case Color.Red:
            print("r")
        case Color.Red:
            print("r2")
        case Color.Green:
            print("g")
    }
    return 0
}`, TyEnumSwitch)

	// 有 default：不做穷尽性要求。
	expectNone(t, `
enum Color { Red, Green, Blue }
static Int main() {
    Color c = Color.Red
    switch (c) {
        case Color.Red:
            print("r")
        default:
            print("other")
    }
    return 0
}`)

	// 非枚举 switch 不做穷尽性检查。
	expectNone(t, `
static Int main() {
    Int x = 1
    switch (x) {
        case 1:
            print("one")
    }
    return 0
}`)

	// 枚举 case 必须是项常量，任意表达式拒绝。
	expectCode(t, `
enum Color { Red, Green }
static Int main() {
    Color c = Color.Red
    Int n = 0
    switch (c) {
        case n:
            print("n")
        case Color.Green:
            print("g")
    }
    return 0
}`, TyEnumSwitch)
}
