package sema

import "testing"

// M6-B0-07a：Int32/Int64 的整数字面量目标适配与同族同宽比较。
func TestNumericVariantLiteralAdaptation(t *testing.T) {
	// B0-06 主程序形态：Int32/Int64 目标 + 整数字面量。
	expectNone(t, `
static Int main() {
    Int32 code = 0
    Int64 got = 0
    if (code != 0 || got < 0) {
        return 1
    }
    return 0
}`)
	// 边界值：Int32 min/max 可表示。
	expectNone(t, `
static Int main() {
    Int32 lo = -2147483648
    Int32 hi = 2147483647
    Int64 lo64 = -9223372036854775808
    Int64 hi64 = 9223372036854775807
    return 0
}`)
}

func TestNumericVariantOutOfRange(t *testing.T) {
	// 越界字面量必须报错，不得放宽。
	expectCode(t, "static Int main() {\n    Int32 v = 2147483648\n    return 0\n}", TyAssignability)
	expectCode(t, "static Int main() {\n    Int32 v = -2147483649\n    return 0\n}", TyAssignability)
	expectCode(t, "static Int main() {\n    Int64 v = 9223372036854775808\n    return 0\n}", TyAssignability)
	// 越界字面量参与比较也必须报错。
	expectCode(t, "static Int main() {\n    Int32 v = 0\n    if (v < 2147483648) { return 1 }\n    return 0\n}", TyBadOperand)
}

func TestNumericVariantComparisonWidth(t *testing.T) {
	// 字面量按另一侧类型适配：Int32/Int64 与 0 比较合法。
	expectNone(t, `
static Int main() {
    Int32 a = 0
    Int64 b = 0
    Bool x = a == 0
    Bool y = b >= 0
    return 0
}`)
	// 不同宽度/不同数值类型之间仍禁止比较（不放宽为隐式转换）。
	expectCode(t, `
static Int main() {
    Int32 a = 0
    Int64 b = 0
    if (a < b) { return 1 }
    return 0
}`, TyBadOperand)
	expectCode(t, `
static Int main() {
    Int32 a = 0
    Int d = 0
    if (a != d) { return 1 }
    return 0
}`, TyBadOperand)
	// 显式后缀字面量不参与隐式适配。
	expectCode(t, `
static Int main() {
    Int32 a = 0
    if (a < 5L) { return 1 }
    return 0
}`, TyBadOperand)
}
