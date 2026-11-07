package sema

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// ===== 独立验收（CEO3-QA1）TUPLE-01 / S1 §2.11 =====
// 本文件不复用实现者的 tuple_test.go 用例；只使用包内公开入口 ParseUnit + Analyze。

func qaCodes(t *testing.T, src string) []string {
	t.Helper()
	u, pd := xfront.ParseUnit("qa.x", src)
	if len(pd) != 0 {
		t.Fatalf("解析诊断（用例应为可解析输入）：%v", pd)
	}
	var out []string
	for _, d := range Analyze("qa.x", u) {
		out = append(out, d.Code+"@"+strings.TrimSpace(d.Message))
	}
	return out
}

func qaNone(t *testing.T, src string) {
	t.Helper()
	if got := qaCodes(t, src); len(got) != 0 {
		t.Fatalf("不应有语义诊断：%v", got)
	}
}

func qaCode(t *testing.T, src, code string) {
	t.Helper()
	for _, c := range qaCodes(t, src) {
		if strings.HasPrefix(c, code) {
			return
		}
	}
	t.Fatalf("期望诊断 %s，实际：%v", code, qaCodes(t, src))
}

// T1 类型身份：同长同元素逐一相同 = 同型；换序/换长/换元素 = 异型；嵌套同型。
func TestQATupleTypeIdentity(t *testing.T) {
	qaNone(t, `static Int main() {
    (Int, String) a = (1, "a")
    (Int, String) b = a
    ((Int, String), Bool) n1 = ((1, "a"), true)
    ((Int, String), Bool) n2 = n1
    return b.0
}`)
	qaCode(t, `static Int main() {
    (Int, String) a = (1, "a")
    (String, Int) b = a
    return 0
}`, TyAssignability)
	qaCode(t, `static Int main() {
    (Int, String) a = (1, "a")
    (Int, String, Int) b = a
    return 0
}`, TyAssignability)
	qaCode(t, `static Int main() {
    (Int, String) a = (1, "a")
    (Int, Int) b = a
    return 0
}`, TyAssignability)
	// 嵌套结构不同：( (Int,String), Bool ) 与 ( Int, (String,Bool) ) 不是同型。
	qaCode(t, `static Int main() {
    ((Int, String), Bool) a = ((1, "a"), true)
    (Int, (String, Bool)) b = a
    return 0
}`, TyAssignability)
}

// T2 字面量：按目标元素类型适配；元数/元素类型不符必须拒绝。
func TestQATupleLiteral(t *testing.T) {
	qaNone(t, `static Int main() {
    (Int, String) a = (1, "a")
    (Long, Byte, Double, Bool, Char) b = (1, 2, 3.0, true, 'x')
    ((Int, String), Bool) n = ((1, "a"), true)
    return 0
}`)
	qaCode(t, `static Int main() {
    (Int, String) a = (1, "a", true)
    return 0
}`, TyAssignability)
	qaCode(t, `static Int main() {
    (Int, String) a = ("a", 1)
    return 0
}`, TyAssignability)
	// `(1)` 是括号表达式，不是单元素元组；赋给元组类型必须被拒绝。
	qaCode(t, `static Int main() {
    (Int, String) a = (1)
    return 0
}`, TyAssignability)
}

// T3 元素访问：.0/.1 类型正确、可赋值、可链式；?.N 非空可读；无成员/越界拒绝。
func TestQATupleElementAccess(t *testing.T) {
	qaNone(t, `static Int main() {
    (Int, String) p = (1, "a")
    Int a = p.0
    String b = p.1
    p.0 = 2
    Int? c = p?.0
    ((Int, String), Bool) n = ((3, "b"), true)
    Int d = (n.0).0
    return a + d
}`)
	qaCode(t, `static Int main() {
    (Int, String) p = (1, "a")
    print(p.length)
    return 0
}`, "TY-106")
	qaCode(t, `static Int main() {
    (Int, String) p = (1, "a")
    print(p.2)
    return 0
}`, "TY-106")
	qaCode(t, `static Int main() {
    (Int, String) p = (1, "a")
    p.2 = 9
    return 0
}`, "TY-106")
	qaCode(t, `static Int main() {
    (Int, String) p = (1, "a")
    print(p?.2)
    return 0
}`, "TY-106")
	// 元素赋值的类型必须匹配元素类型。
	qaCode(t, `static Int main() {
    (Int, String) p = (1, "a")
    p.0 = "x"
    return 0
}`, TyAssignability)
	// .N 只能用于元组。
	qaCode(t, `static Int main() {
    Int x = 1
    print(x.0)
    return 0
}`, "TY-106")
}

// T4 推断：var 得元组类型；后续赋值仍按该类型检查。
func TestQATupleInference(t *testing.T) {
	qaNone(t, `static Int main() {
    var a = (1, "x")
    Int i = a.0
    String s = a.1
    a = (2, "y")
    var b = (true, 3.0)
    Bool f = b.0
    return i
}`)
	qaCode(t, `static Int main() {
    var a = (1, "x")
    a = (2, 3)
    return 0
}`, TyAssignability)
}

// T5 可赋值性：仅长度相同且元素类型逐一相同；元组无子类型；字面量按目标适配。
func TestQATupleAssignability(t *testing.T) {
	qaNone(t, `static Int main() {
    (Int, String) a = (1, "a")
    (Int, String) b = a
    b = (2, "b")
    (Long, String) c = (1, "a")
    return b.0
}`)
	// 元素类型不同（即使 Int 可扩宽到 Long）也不是同一元组类型。
	qaCode(t, `static Int main() {
    (Int, String) a = (1, "a")
    (Long, String) b = a
    return 0
}`, TyAssignability)
	// 元组参数是可赋值位置，传参类型必须精确匹配。
	qaNone(t, `static Int take((Int, String) p) { return p.0 }
static Int main() {
    (Int, String) a = (1, "a")
    return take(a)
}`)
	qaCode(t, `static Int take((Int, String) p) { return p.0 }
static Int main() {
    (Int, String, Bool) a = (1, "a", true)
    return take(a)
}`, TyAssignability)
}

// T6a 相等（静态）：两侧必须同型；==/!=/===/!== 均可用。
func TestQATupleEqualityStatic(t *testing.T) {
	qaNone(t, `static Int main() {
    (Int, String) a = (1, "a")
    (Int, String) b = (1, "a")
    Bool x = a == b
    Bool y = a != b
    Bool z = a === b
    Bool w = a !== b
    Bool n = ((1, "a"), true) == ((1, "a"), true)
    return 0
}`)
	qaCode(t, `static Int main() {
    (Int, Int) a = (1, 2)
    (Int, String) b = (1, "x")
    Bool x = a == b
    return 0
}`, TyBadOperand)
}

// T6b 插值：元组可插值、嵌套递归；不可格式化元素必须拒绝。
func TestQATupleInterpolationStatic(t *testing.T) {
	qaNone(t, `static Int main() {
    (Int, String) a = (1, "a")
    ((Int, String), Bool) n = ((1, "a"), true)
    print($"a={a}")
    print($"n={n}")
    return 0
}`)
	qaCode(t, `static Int main() {
    (Int[], Int) p = ([1, 2], 3)
    print($"p={p}")
    return 0
}`, "TY-106")
}

// T7-T11 负向：越界/元数/解构/switch/const 必须被拒绝（语法或语义层）。
func TestQATupleRejections(t *testing.T) {
	// 零元、单元素：语法层拒绝。
	if _, pd := xfront.ParseUnit("qa.x", `static Int main() { Tuple t = ()
    return 0 }`); len(pd) == 0 {
		t.Fatalf("零元元组应被拒绝")
	}
	if _, pd := xfront.ParseUnit("qa.x", `static Int main() { Int x = (1,)
    return 0 }`); len(pd) == 0 {
		t.Fatalf("单元素元组字面量应被拒绝")
	}
	// 解构：语法层拒绝。
	if _, pd := xfront.ParseUnit("qa.x", `static Int main() {
    (Int, Int) p = (1, 2)
    (Int a, Int b) = p
    return 0 }`); len(pd) == 0 {
		t.Fatalf("元组解构应被拒绝")
	}
	// 元组 const：语法层拒绝。
	if _, pd := xfront.ParseUnit("qa.x", `const (Int, Int) P = (1, 2)
static Int main() { return 0 }`); len(pd) == 0 {
		t.Fatalf("元组 const 应被拒绝")
	}
	// 元组 switch：语义层拒绝。
	qaCode(t, `static Int main() {
    (Int, Int) p = (1, 2)
    switch (p) { case (1, 2): print("x") }
    return 0
}`, "TY-106")
	// 异型 as / as? 拒绝；同型 as 恒等。
	qaCode(t, `static Int main() {
    (Int, Int) p = (1, 2)
    (Int, String) q = p as (Int, String)
    return 0
}`, "TY-106")
	qaNone(t, `static Int main() {
    (Int, Int) p = (1, 2)
    (Int, Int) q = p as (Int, Int)
    return q.0
}`)
}

// T1/T3/T4 附加：括号表达式不是单元素元组；元组作为参数类型合法（§2.11 允许参数）。
func TestQATupleParenAndParam(t *testing.T) {
	qaNone(t, `static Int f((Int, Int) p) { return p.0 }
static Int main() {
    Int x = (1)
    (Int, Int) p = (2, 3)
    return f(p) + x
}`)
}
