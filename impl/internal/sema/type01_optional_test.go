package sema

import "testing"

// ---------- M1 / TYPE-01 假绿复核：可选提升（S1 §2.6） ----------
// NEG-01 上报：`String? s = "x"` 初始化式不做可选提升（TY-101），而 `s = "x"` 赋值通过。
// 本文件只新增用例，不修改既有测试期望。

// 正向：任意可赋给 T 的初始化式都应可赋给 T?（含字面量与容器字面量）。
func TestTYPE01OptionalPromotionLiterals(t *testing.T) {
	expectNone(t, `
static Int main() {
    String? s = "x"
    Int? i = 5
    Char? c = 'a'
    Bool? b = true
    Double? d = 1.5
    Float? f = 1.5f
    List<Int>? xs = [1]
    Map<String, Int>? m = ["a": 1]
    return 0
}`)

	// 变量赋值路径与初始化路径必须一致（NEG-01 的对照面）。
	expectNone(t, `
static Int main() {
    String plain = "z"
    String? fromVar = plain
    String? assigned
    assigned = "y"
    assigned = plain
    return 0
}`)

	// null 规则保持：null → 任意引用类型或 T?；非可空值类型拒绝。
	expectNone(t, `
static Int main() {
    String? a = null
    Int? b = null
    String c = null
    return 0
}`)
}

// 负向：不可赋给 T 的值仍不得因 T? 而放行。
func TestTYPE01OptionalPromotionNegative(t *testing.T) {
	cases := []struct{ name, src string }{
		{"String? 收 Int 字面量", `
static Int main() {
    String? s = 5
    return 0
}`},
		{"Int? 收字符串字面量", `
static Int main() {
    Int? i = "x"
    return 0
}`},
		{"Bool? 收整数字面量", `
static Int main() {
    Bool? b = 1
    return 0
}`},
		{"非可空 Int 收 null", `
static Int main() {
    Int i = null
    return 0
}`},
		{"Double? 收 Int 字面量", `
static Int main() {
    Double? d = 1
    return 0
}`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			code := "TY-101"
			if c.name == "非可空 Int 收 null" {
				code = "TY-103"
			}
			expectCode(t, c.src, code)
		})
	}
}
