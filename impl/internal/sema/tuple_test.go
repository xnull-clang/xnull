package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// TUPLE-01 验收检查表（台账 §2.11）：
// T1 类型身份、T2 字面量、T3 元素访问、T4 推断、T5 可赋值性、
// T6 相等与插值、T7 越界选择器、T8 单元素/零元元组、
// T9 解构、T10 元组 switch、T11 元组 const。

// T1 + T5：类型身份按长度与元素类型逐一判定；嵌套元组合法。
func TestTupleIdentity(t *testing.T) {
	expectNone(t, `
static Int main() {
    (Int, String) a = (1, "x")
    (Int, String) b = a
    ((Int, String), Bool) nested = ((1, "a"), true)
    (Int, String) inner = nested.0
    Int n = inner.0
    return n
}`)
	// 元素类型不同不是同一类型
	expectCode(t, `
static Int main() {
    (Int, String) a = (1, "x")
    (Int, Int) b = a
    return 0
}`, TyAssignability)
	// 长度不同不是同一类型
	expectCode(t, `
static Int main() {
    (Int, String) a = (1, "x")
    (Int, String, Int) b = a
    return 0
}`, TyAssignability)
}

// T2：元组字面量按目标元素类型适配各元素。
func TestTupleLiteralAdaptation(t *testing.T) {
	expectNone(t, `
static Int main() {
    (Long, Byte, Double, String) t = (1, 2, 3.0, "a")
    return 0
}`)
}

// T3：元素访问 `.N` 在范围内合法；元组没有方法/属性。
func TestTupleElementAccess(t *testing.T) {
	expectNone(t, `
static Int main() {
    (Int, String) pair = (1, "a")
    Int first = pair.0
    String second = pair.1
    Int? safe = pair?.0
    return first
}`)
	expectCode(t, `
static Int main() {
    (Int, String) pair = (1, "a")
    print(pair.length)
    return 0
}`, "TY-106")
}

// T4：var 推断元组类型。
func TestTupleInference(t *testing.T) {
	expectNone(t, `
static Int main() {
    var inferred = (1, "a")
    Int first = inferred.0
    String second = inferred.1
    return first
}`)
}

// T5：元组之间没有子类型关系；可赋值当且仅当同一类型。
func TestTupleAssignability(t *testing.T) {
	expectNone(t, `
static Int main() {
    (Int, String) a = (1, "a")
    (Int, String) b = a
    b = (2, "b")
    return b.0
}`)
	expectCode(t, `
static Int main() {
    (Int, String) a = (1, "a")
    (String, Int) b = a
    return 0
}`, TyAssignability)
}

// T6：== / != / === / !== 与插值按 §2.11。
func TestTupleEqualityAndInterpolation(t *testing.T) {
	expectNone(t, `
static Int main() {
    (Int, String) a = (1, "x")
    (Int, String) b = (1, "x")
    Bool eq = a == b
    Bool ne = a != b
    Bool same = a === b
    Bool diff = a !== b
    print($"pair={a}")
    return 0
}`)
	// 插值元素必须可格式化：数组元素不可格式化。
	expectCode(t, `
static Int main() {
    (Int[], Int) pair = ([1, 2], 3)
    print($"pair={pair}")
    return 0
}`, "TY-106")
	// 两侧必须是相同元组类型。
	expectCode(t, `
static Int main() {
    (Int, Int) a = (1, 2)
    (Int, String) b = (1, "x")
    Bool eq = a == b
    return 0
}`, TyBadOperand)
}

// T7：越界选择器是编译错误。
func TestTupleOutOfRangeSelector(t *testing.T) {
	expectCode(t, `
static Int main() {
    (Int, String) pair = (1, "a")
    print(pair.2)
    return 0
}`, "TY-106")
	expectCode(t, `
static Int main() {
    (Int, String) pair = (1, "a")
    pair.5 = 2
    return 0
}`, "TY-106")
}

// T8：单元素/零元元组被拒绝（语法层）。
func TestTupleArityRejected(t *testing.T) {
	if _, diags := xfront.ParseUnit("t.x", "static Int main() { Tuple t = ()\n    return 0 }"); len(diags) == 0 {
		t.Fatalf("零元元组应被拒绝")
	}
	if _, diags := xfront.ParseUnit("t.x", "static Int main() { Int x = (1,)\n    return 0 }"); len(diags) == 0 {
		t.Fatalf("单元素元组应被拒绝")
	}
}

// T9：解构被拒绝（语法层）。
func TestTupleDestructuringRejected(t *testing.T) {
	if _, diags := xfront.ParseUnit("t.x", `
static Int main() {
    (Int, Int) p = (1, 2)
    (Int a, Int b) = p
    return 0
}`); len(diags) == 0 {
		t.Fatalf("元组解构应被拒绝")
	}
}

// T10：元组不能作为 switch 值。
func TestTupleSwitchRejected(t *testing.T) {
	expectCode(t, `
static Int main() {
    (Int, Int) p = (1, 2)
    switch (p) {
        case (1, 2):
            print("x")
    }
    return 0
}`, "TY-106")
}

// T11：元组不能作为 const 类型或常量表达式（语法层）。
func TestTupleConstRejected(t *testing.T) {
	if _, diags := xfront.ParseUnit("t.x", `
const (Int, Int) P = (1, 2)
static Int main() { return 0 }`); len(diags) == 0 {
		t.Fatalf("元组 const 类型应被拒绝")
	}
}

// T3 + T5：元组元素是可赋值位置，且赋值类型按元素类型检查。
func TestTupleElementAssignment(t *testing.T) {
	expectNone(t, `
static Int main() {
    (Int, String) pair = (1, "a")
    pair.0 = 2
    return pair.0
}`)
	expectCode(t, `
static Int main() {
    (Int, String) pair = (1, "a")
    pair.0 = "x"
    return 0
}`, TyAssignability)
}

// §2.11：同型 as 恒等，异型 as 编译错误。
func TestTupleTypeAs(t *testing.T) {
	expectNone(t, `
static Int main() {
    (Int, Int) p = (1, 2)
    (Int, Int) q = p as (Int, Int)
    return q.0
}`)
	expectCode(t, `
static Int main() {
    (Int, Int) p = (1, 2)
    (Int, String) q = p as (Int, String)
    return 0
}`, "TY-106")
}
