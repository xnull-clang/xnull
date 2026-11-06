package sema

import "testing"

// ---------- TYPE-01：可赋值性（§2.6） ----------

func TestTyAssignableOK(t *testing.T) {
	// 同一类型、字面量适配、可选提升
	expectNone(t, `
static Int main() {
    Int i = 5
    Long l = 5
    Byte b = 200
    Double d = 1.5
    Float f = 1.5f
    String s = "x"
    Int? opt = i
    String? sopt = null
    Char c = 'x'
    Bool flag = true
    return 0
}`)
	// String[] 与数组字面量；List/Set 目标给元素类型适配（§2.6 容器字面量）
	expectNone(t, `
static Int main() {
    String[] parts = ["a", "b"]
    List<Int> xs = [1, 2]
    Set<Int> ys = [1]
    Map<String, Int> m = ["a": 1]
    return 0
}`)
	// 闭包字面量 → 函数类型（§2.6 闭包字面量）
	expectNone(t, `
static Int main() {
    Int(Int) inc = (Int x) -> x + 1
    return inc(1)
}`)
	// try 解包：Result<T,E> → T（§10.2）
	expectNone(t, `
static Result<Int, String> g() {
    return Err("e")
}

static Result<Int, String> f() {
    Int v = try g()
    return Ok(v)
}

static Int main() { return 0 }`)
	// 元组字面量按目标元素适配（§2.6 元组规则）
	expectNone(t, `
static Int main() {
    (Int, String) pair = (1, "one")
    return pair.0
}`)
}

func TestTyAssignableFail(t *testing.T) {
	// 数值隐式转换禁止（§2.6）
	expectCode(t, "static Int main() {\n    Int i = 1.5\n    return 0\n}", TyAssignability)
	expectCode(t, "static Int main() {\n    Double d = 1\n    return 0\n}", TyAssignability)
	expectCode(t, "static Int main() {\n    Int i = 5\n    Long l = i\n    return 0\n}", TyAssignability)
	// String + 数值禁止（§9.2）
	expectCode(t, "static Int main() {\n    String s = \"n=\" + 5\n    return 0\n}", TyBadOperand)
	// Bool 与整数互转禁止
	expectCode(t, "static Int main() {\n    Int i = true\n    return 0\n}", TyAssignability)
	// 元组长度不匹配
	expectCode(t, "static Int main() {\n    (Int, String) pair = (1, \"a\", 2)\n    return 0\n}", TyAssignability)
	// 返回类型不符
	expectCode(t, "static Int f() {\n    return \"x\"\n}\n\nstatic Int main() { return 0 }", TyAssignability)
	// void 函数返回值
	expectCode(t, "static void f() {\n    return 1\n}\n\nstatic Int main() { return 0 }", TyAssignability)
	// void 不能作为变量类型（§2）
	expectCode(t, "static Int main() {\n    void x\n    return 0\n}", TyAssignability)
	// 实参类型不符
	expectCode(t, `
static Int f(Int n) {
    return n
}

static Int main() {
    return f("x")
}`, TyAssignability)
}

// ---------- TYPE-02：可空（§2.6 空值规则） ----------

func TestTyNullRules(t *testing.T) {
	// null → 引用类型 / T?：通过
	expectNone(t, `
static Int main() {
    String? s = null
    String t = null
    return 0
}`)
	// null → 非可空值类型：TY-103 语义走 TY-101 通道（禁止项），码为 TY-101；
	// 这里验证 Int?/String? 与 Result 的区别
	expectNone(t, `
static Int main() {
    Int? x = null
    List<Int>? xs = null
    return 0
}`)
	// null 赋给 Result（值类型，非引用）→ 禁止
	expectCode(t, `
static Int main() {
    Result<Int, String> r = null
    return 0
}`, TyNullToValue)
	// null 与非引用比较 → TY-105
	expectCode(t, "static Int main() {\n    if 1 == null {\n        print(\"x\")\n    }\n    return 0\n}", TyBadOperand)
}

// ---------- TY-104 / TY-105 ----------

func TestTyConditionsAndOperands(t *testing.T) {
	// 条件必须 Bool
	expectCode(t, "static Int main() {\n    if 1 {\n        print(\"x\")\n    }\n    return 0\n}", TyCondNotBool)
	expectCode(t, "static Int main() {\n    while \"x\" {\n        break\n    }\n    return 0\n}", TyCondNotBool)
	// 自增只用于整数
	expectCode(t, "static Int main() {\n    String s = \"a\"\n    s++\n    return 0\n}", TyBadOperand)
	// 数值混算禁止
	expectCode(t, "static Int main() {\n    Int i = 1\n    Double d = 2.0\n    Double x = i + d\n    return 0\n}", TyBadOperand)
	// Result 无 ==
	expectCode(t, `
static Int main() {
    Result<Int, String> r = Err("e")
    if r == Err("e") {
        print("x")
    }
    return 0
}`, TyBadOperand)
	// 合法短路/??/区间
	expectNone(t, `
static Int f() {
    return 1
}

static Int main() {
    Bool a = true && false || (1 < 2)
    String c = "x"
    Int n = 0
    Int v = n ?? f()
    for i in 0..<3 {
        print(str(i))
    }
    return 0
}`)
}

// TYPE-01：Any 装箱必须显式 as（§2.6 装箱规则）；Object 引用根。
func TestTyAnyBoxing(t *testing.T) {
	expectCode(t, "static Int main() {\n    Any a = 42\n    return 0\n}", TyAssignability)
	expectNone(t, "static Int main() {\n    Any a = 42 as Any\n    Any b = \"x\" as Any\n    return 0\n}")
	expectNone(t, "static Int main() {\n    Any a = 42 as Any\n    print(a is Int)\n    return 0\n}")
}
