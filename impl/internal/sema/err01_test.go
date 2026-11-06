package sema

import "testing"

// ---------- M1 / ERR-01：错误处理（S1 §10）红→绿用例 ----------
// 检查表：evidence/M1-ERR-01/checklist.md
// 说明：本文件只新增用例，不修改既有测试期望。

// ERR01-01/05：Result 构造与错误类型，正向。
func TestERR01ResultConstructionPositive(t *testing.T) {
	expectNone(t, `
static Result<Int, String> f() {
    Result<Int, String> a = Ok(1)
    Result<Int, String> b = Err("e")
    Result<void, String> c = Ok()
    return Ok(1)
}

static Int take(Result<Int, String> r) {
    return 0
}

static Int main() {
    Result<Int, String> x = Ok(2)
    Int n = take(Ok(3))
    List<Result<Int, String> > xs = [Ok(4)]
    return n
}`)
}

// ERR01-01/05：Result 构造与错误类型，负向。
func TestERR01ResultConstructionNegative(t *testing.T) {
	cases := []struct{ name, src string }{
		{"Ok 成功值类型不符", `
static Int main() {
    Result<Int, String> r = Ok("x")
    return 0
}`},
		{"Ok() 用于非 void T", `
static Int main() {
    Result<Int, String> r = Ok()
    return 0
}`},
		{"Ok(value) 用于 void T", `
static Int main() {
    Result<void, String> r = Ok(1)
    return 0
}`},
		{"Err 错误值类型不符", `
static Int main() {
    Result<Int, String> r = Err(1)
    return 0
}`},
		{"Err 缺错误值", `
static Int main() {
    Result<Int, String> r = Err()
    return 0
}`},
		{"Ok 参数过多", `
static Int main() {
    Result<Int, String> r = Ok(1, 2)
    return 0
}`},
		{"无目标类型无法推断", `
static Int main() {
    var r = Ok(1)
    return 0
}`},
		{"Result 实参数量不足", `
static Int main() {
    Result<Int> r
    return 0
}`},
		{"Result 错误类型为 void", `
static Int main() {
    Result<Int, void> r
    return 0
}`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { expectCode(t, c.src, "ERR-202") })
	}
}

// ERR01-02/09—12：Result 成员，正向。
func TestERR01ResultMembersPositive(t *testing.T) {
	expectNone(t, `
static Result<Int, String> f() {
    Result<Int, String> r = Ok(1)
    Bool a = r.isOk()
    Bool b = r.isErr()
    if a {
        Int v = r.value()
        print(str(v))
    }
    if b {
        String e = r.error()
        print(e)
    }
    Int n = r.unwrapOr(0)
    return Ok(n)
}

static Int main() { return 0 }`)
}

// ERR01-02/09—12：Result 成员，负向。
func TestERR01ResultMembersNegative(t *testing.T) {
	cases := []struct{ name, src string }{
		{"isOk 带参", `
static Int main() {
    Result<Int, String> r = Ok(1)
    Bool b = r.isOk(1)
    return 0
}`},
		{"value 带参", `
static Int main() {
    Result<Int, String> r = Ok(1)
    Int v = r.value(1)
    return 0
}`},
		{"error 带参", `
static Int main() {
    Result<Int, String> r = Ok(1)
    String e = r.error(1)
    return 0
}`},
		{"unwrapOr 缺参", `
static Int main() {
    Result<Int, String> r = Ok(1)
    Int v = r.unwrapOr()
    return 0
}`},
		{"unwrapOr 参数类型不符", `
static Int main() {
    Result<Int, String> r = Ok(1)
    Int v = r.unwrapOr("x")
    return 0
}`},
		{"unwrapOr 参数过多", `
static Int main() {
    Result<Int, String> r = Ok(1)
    Int v = r.unwrapOr(1, 2)
    return 0
}`},
		{"未知成员", `
static Int main() {
    Result<Int, String> r = Ok(1)
    Bool b = r.boom()
    return 0
}`},
		{"void T 不可 value", `
static Int main() {
    Result<void, String> r = Ok()
    r.value()
    return 0
}`},
		{"void T 不可 unwrapOr", `
static Int main() {
    Result<void, String> r = Ok()
    r.unwrapOr(0)
    return 0
}`},
		{"成员必须调用", `
static Int main() {
    Result<Int, String> r = Ok(1)
    Int v = r.value
    return 0
}`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { expectCode(t, c.src, "ERR-203") })
	}
}

// ERR01-03：@mustUse。
func TestERR01MustUse(t *testing.T) {
	negatives := []struct{ name, src string }{
		{"裸 Result 变量", `
static Result<Int, String> f() {
    Result<Int, String> r = Ok(1)
    r
    return Ok(2)
}
static Int main() { return 0 }`},
		{"裸 Result 调用", `
static Result<Int, String> g() { return Ok(1) }
static Int main() {
    g()
    return 0
}`},
		{"裸 Ok 构造", `
static Int main() {
    Ok(1)
    return 0
}`},
		{"defer 内未处理 Result", `
static Result<Int, String> g() { return Ok(1) }
static Int main() {
    defer g()
    return 0
}`},
	}
	for _, c := range negatives {
		t.Run(c.name, func(t *testing.T) { expectCode(t, c.src, "ERR-201") })
	}

	expectNone(t, `
static Result<Int, String> g() { return Ok(1) }

static Result<Int, String> f() {
    Result<Int, String> r = g()
    Int v = try g()
    r.isOk()
    List<Result<Int, String> > xs = [r]
    return Ok(v)
}

static Int main() { return 0 }`)
}

// ERR01-04：try 传播，正向（含 Result<void,E> 语句与嵌套 try）。
func TestERR01TryPositive(t *testing.T) {
	expectNone(t, `
static Result<Int, String> g() { return Ok(1) }
static Result<void, String> h() { return Ok() }
static Result<Result<Int, String>, String> nested() { return Ok(Ok(1)) }

static Result<Int, String> f() {
    Int v = try g()
    try h()
    Int w = try try nested()
    return Ok(v + w)
}

static Int main() { return 0 }`)
}

// ERR01-04/05：try 负向与错误类型不匹配。
func TestERR01TryNegative(t *testing.T) {
	cases := []struct{ name, src string }{
		{"try 非 Result", `
static Int main() {
    Int v = try 1
    return v
}`},
		{"外层不返回 Result", `
static Result<Int, String> g() { return Ok(1) }
static Int f() {
    Int v = try g()
    return v
}
static Int main() { return 0 }`},
		{"错误类型不可赋", `
static Result<Int, Object> g() { return Err("x" as Object) }
static Result<Int, String> f() {
    Int v = try g()
    return Ok(v)
}
static Int main() { return 0 }`},
		{"main 禁止 try", `
static Result<Int, String> g() { return Ok(1) }
static Int main() {
    Int v = try g()
    return v
}`},
		{"构造器禁止 try", `
static Result<Int, String> g() { return Ok(1) }
class C {
    C() {
        Int v = try g()
    }
}
static Int main() { return 0 }`},
		{"deinit 禁止 try", `
static Result<Int, String> g() { return Ok(1) }
class C {
    Int x = 0;
    void deinit() {
        Int v = try g()
    }
}
static Int main() { return 0 }`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { expectCode(t, c.src, "ERR-204") })
	}
}

// ERR01-05：错误类型实参在参数/返回/字段位置均为 void 时拒绝。
func TestERR01ErrorTypeVoid(t *testing.T) {
	cases := []struct{ name, src string }{
		{"参数 E=void", `
static Int f(Result<Int, void> r) { return 0 }
static Int main() { return 0 }`},
		{"返回 E=void", `
static Result<Int, void> f() { return Ok(1) }
static Int main() { return 0 }`},
		{"字段 E=void", `
class C {
    Result<Int, void> r;
}
static Int main() { return 0 }`},
		{"局部 E=void", `
static Int main() {
    Result<Int, void> r
    return 0
}`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { expectCode(t, c.src, "ERR-202") })
	}
}

// ERR01-08：清理体限制。
func TestERR01CleanupRestrictions(t *testing.T) {
	srcs := []struct{ name, src string }{
		{"return", `
static Int main() {
    defer { return }
    return 0
}`},
		{"break", `
static Int main() {
    defer { break }
    return 0
}`},
		{"continue", `
static Int main() {
    defer { continue }
    return 0
}`},
		{"goto", `
static Int main() {
    defer { goto L }
    return 0
}`},
		{"throw", `
static Int main() {
    defer { throw "x" }
    return 0
}`},
		{"try", `
static Result<Int, String> g() { return Ok(1) }
static Int main() {
    defer { Int v = try g() }
    return 0
}`},
		{"嵌套 defer", `
static Int main() {
    defer { defer print("x") }
    return 0
}`},
		{"嵌套 errdefer", `
static Result<Int, String> f() {
    defer { errdefer print("x") }
    return Ok(1)
}
static Int main() { return 0 }`},
		{"闭包", `
static Int main() {
    defer { var h = () -> { return 1 } }
    return 0
}`},
		{"单条局部声明", `
static Int main() {
    defer Int x = 1
    return 0
}`},
	}
	for _, c := range srcs {
		t.Run(c.name, func(t *testing.T) { expectCode(t, c.src, "ERR-205") })
	}

	expectNone(t, `
static void cleanup() { print("c") }
static Int main() {
    defer cleanup()
    defer {
        Int x = 1
        print(str(x))
    }
    return 0
}`)
}

// ERR01-07：errdefer 的编译期上下文。
func TestERR01ErrdeferContext(t *testing.T) {
	expectCode(t, `
static Int main() {
    errdefer print("e")
    return 0
}`, "ERR-206")

	expectCode(t, `
class C {
    C() {
        errdefer print("e")
    }
}
static Int main() { return 0 }`, "ERR-206")

	expectNone(t, `
static Result<Int, String> f() {
    errdefer print("e")
    return Ok(1)
}
static Int main() { return 0 }`)
}

// ERR01-04：闭包内 try 的目标返回类型必须是 Result。
func TestERR01LambdaTry(t *testing.T) {
	expectCode(t, `
static Result<Int, String> g(Int x) { return Ok(x) }
static Int main() {
    Int(Int) f = (Int x) -> { return try g(x) }
    return 0
}`, "ERR-204")

	expectNone(t, `
static Result<Int, String> g(Int x) { return Ok(x) }
static Int main() {
    Result<Int, String>(Int) f = (Int x) -> {
        Int v = try g(x)
        return Ok(v)
    }
    return 0
}`)
}
