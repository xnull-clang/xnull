package xfront

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
)

// ok 解析成功并返回 S 表达式形态。
func ok(t *testing.T, src string) string {
	t.Helper()
	e, diags := ParseExpr("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("源 `%s` 不应有诊断：%v", src, render(diags))
	}
	return PrintExpr(e)
}

// fail 解析必须产生含指定码的诊断。
func fail(t *testing.T, src, code string) {
	t.Helper()
	_, diags := ParseExpr("t.x", src)
	for _, d := range diags {
		if d.Code == code {
			return
		}
	}
	t.Fatalf("源 `%s` 期望诊断 %s，实际：%v", src, code, render(diags))
}

func render(ds []diag.Diagnostic) string {
	var parts []string
	for _, d := range ds {
		parts = append(parts, d.Code+"@"+strings.TrimSpace(d.String()))
	}
	return strings.Join(parts, "; ")
}

// ---------- §7.2 优先级表：逐行 ----------

func TestPrecedenceTable(t *testing.T) {
	cases := []struct{ src, want string }{
		// 后缀 / 调用 / 下标 / 成员（最高）
		{"a.b.c", "(member (member (ident a) b) c)"},
		{"f(1)[0].g(2)", "(call (member (index (call (ident f) (int 1)) (int 0)) g) (int 2))"},
		// 乘除模 > 加减
		{"1 + 2 * 3", "(binary + (int 1) (binary * (int 2) (int 3)))"},
		{"(1 + 2) * 3", "(binary * (paren (binary + (int 1) (int 2))) (int 3))"},
		// 移位 > 加减：`a << b + c` = a << (b+c)
		{"a << b + c", "(binary << (ident a) (binary + (ident b) (ident c)))"},
		// 范围 > 移位
		{"0 ..< n + 1", "(binary ..< (int 0) (binary + (ident n) (int 1)))"},
		// 比较 > 范围
		{"a < b ..< c", "(binary < (ident a) (binary ..< (ident b) (ident c)))"},
		// 相等 > 比较
		{"a == b < c", "(binary == (ident a) (binary < (ident b) (ident c)))"},
		// & > ^ > |（优先级从高到低）
		{"a | b ^ c & d", "(binary | (ident a) (binary ^ (ident b) (binary & (ident c) (ident d))))"},
		// && > |
		{"a && b | c", "(binary && (ident a) (binary | (ident b) (ident c)))"},
		// || > &&
		{"a || b && c", "(binary || (ident a) (binary && (ident b) (ident c)))"},
		// ?? > ||
		{"a ?? b || c", "(binary ?? (ident a) (binary || (ident b) (ident c)))"},
		// 三元最低
		{"a || b ? c : d", "(ternary (binary || (ident a) (ident b)) (ident c) (ident d))"},
		// 一元高于乘
		{"-a * b", "(binary * (unary - (ident a)) (ident b))"},
		{"!f()", "(unary ! (call (ident f)))"},
	}
	for _, c := range cases {
		if got := ok(t, c.src); got != c.want {
			t.Errorf("`%s`\n  got  %s\n  want %s", c.src, got, c.want)
		}
	}
}

// ---------- §7.2 结合性 ----------

func TestAssociativity(t *testing.T) {
	cases := []struct{ src, want string }{
		{"a - b - c", "(binary - (binary - (ident a) (ident b)) (ident c))"},
		{"a / b / c", "(binary / (binary / (ident a) (ident b)) (ident c))"},
		{"a ?? b ?? c", "(binary ?? (ident a) (binary ?? (ident b) (ident c)))"}, // 右结合
		{"a ? b : c ? d : e", "(ternary (ident a) (ident b) (ternary (ident c) (ident d) (ident e)))"},
		{"a ? b ? c : d : e", "(ternary (ident a) (ternary (ident b) (ident c) (ident d)) (ident e))"},
		{"a << b << c", "(binary << (binary << (ident a) (ident b)) (ident c))"},
	}
	for _, c := range cases {
		if got := ok(t, c.src); got != c.want {
			t.Errorf("`%s`\n  got  %s\n  want %s", c.src, got, c.want)
		}
	}
}

// ---------- §7.2 规则：不链式 / 短路结构 / try ----------

func TestNonChainable(t *testing.T) {
	fail(t, "a < b < c", synChainCompare)
	fail(t, "a ..< b ..< c", synChainRange)
}

func TestEqualityChaining(t *testing.T) {
	// 相等运算在文法里是循环（EqualityExpr = ... { ... }），允许 a == b == c；
	// 比较层（< <= > >= is as）每层至多一次。
	if got := ok(t, "a == b == c"); got != "(binary == (binary == (ident a) (ident b)) (ident c))" {
		t.Errorf("相等运算应可循环：%s", got)
	}
	// 比较后接相等不触发链式误报
	if got := ok(t, "a < b == c"); got != "(binary == (binary < (ident a) (ident b)) (ident c))" {
		t.Errorf("`a < b == c` 应合法：%s", got)
	}
}

func TestTypeOps(t *testing.T) {
	cases := []struct{ src, want string }{
		{"boxed is Int", `(binary is (ident boxed) (is Int))`},
		{"x as Int?", `(binary as (ident x) (as Int?))`},
		{"maybe as? Int", `(binary as? (ident maybe) (as? Int))`},
		{"x is List<Int>", `(binary is (ident x) (is List<Int>))`},
		{"a != null && a.f()", `(binary && (binary != (ident a) (null)) (call (member (ident a) f)))`},
		{"try risky()", "(unary try (call (ident risky)))"},
		{"try fetch() + 1", "(binary + (unary try (call (ident fetch))) (int 1))"},
	}
	for _, c := range cases {
		if got := ok(t, c.src); got != c.want {
			t.Errorf("`%s`\n  got  %s\n  want %s", c.src, got, c.want)
		}
	}
}

// ---------- 后缀与主表达式 ----------

func TestPostfix(t *testing.T) {
	cases := []struct{ src, want string }{
		{"user?.name", "(optmember (ident user) name)"},
		{"name?.length() ?? 0", "(binary ?? (call (optmember (ident name) length)) (int 0))"},
		{"pair.0", "(tuplemember (ident pair) 0)"},
		{"maybe?.0", "(opttuplemember (ident maybe) 0)"},
		{"xs[0][1]", "(index (index (ident xs) (int 0)) (int 1))"},
		{"identity<Int>(1)", "(call (ident identity) <Int> (int 1))"},
		{"m.get<Int, String>(k)", "(call (member (ident m) get) <Int, String> (ident k))"},
		{"a < b", "(binary < (ident a) (ident b))"}, // `<` 是比较，不是泛型
	}
	for _, c := range cases {
		if got := ok(t, c.src); got != c.want {
			t.Errorf("`%s`\n  got  %s\n  want %s", c.src, got, c.want)
		}
	}
}

func TestLiteralsAndCollections(t *testing.T) {
	cases := []struct{ src, want string }{
		{"true", "(bool true)"},
		{"null", "(null)"},
		{"0xFF", "(int 0xFF)"},
		{"1_000_000L", "(int 1_000_000L)"},
		{"1.5f", "(float 1.5f)"},
		{"'a'", "(char \"a\")"},
		{"(1)", "(paren (int 1))"},
		{"(1, \"a\")", `(tuple (int 1) (string "a"))`},
		{"[1, 2, 3]", "(array (int 1) (int 2) (int 3))"},
		{"[]", "(array)"},
		{`["a": 1, "b": 2]`, `(map ((string "a"):(int 1)) ((string "b"):(int 2)))`},
		{"[:]", "(map)"},
		{"new Type(1, 2)", "(new Type (int 1) (int 2))"},
		{"new Byte[4096]", "(newarray Byte (int 4096))"},
		{"newpkg.Type.m()", "(call (member (member (ident newpkg) Type) m))"},
		{"-42", "(unary - (int 42))"},
		{"~-x", "(unary ~ (unary - (ident x)))"},
	}
	for _, c := range cases {
		if got := ok(t, c.src); got != c.want {
			t.Errorf("`%s`\n  got  %s\n  want %s", c.src, got, c.want)
		}
	}
}

// ---------- 闭包（§7.7） ----------

func TestLambda(t *testing.T) {
	cases := []struct{ src, want string }{
		{"() -> 1", "(lambda -> (int 1))"},
		{"(Int x) -> x + 1", "(lambda (Int x) -> (binary + (ident x) (int 1)))"},
		{"(final Int x) -> x", "(lambda (final Int x) -> (ident x))"},
		{"(Int a, Int b) -> a + b",
			"(lambda (Int a) (Int b) -> (binary + (ident a) (ident b)))"},
		{"() -> { return 1; }", "(lambda -> (block (return (int 1))))"},
		{"(Int x) -> { Int y = x * 2; return y; }",
			"(lambda (Int x) -> (block (decl Int y (binary * (ident x) (int 2))) (return (ident y))))"},
		{"((Int x) -> { return x + 1; })(1)",
			"(call (paren (lambda (Int x) -> (block (return (binary + (ident x) (int 1)))))) (int 1))"},
		{"f(() -> 1)", "(call (ident f) (lambda -> (int 1)))"},
	}
	for _, c := range cases {
		if got := ok(t, c.src); got != c.want {
			t.Errorf("`%s`\n  got  %s\n  want %s", c.src, got, c.want)
		}
	}
}

// ---------- 插值串（§7.8） ----------

func TestInterpolatedString(t *testing.T) {
	if got := ok(t, `$"value={total}"`); got != `(string "value=" (ident total))` {
		t.Errorf("插值：%s", got)
	}
	if got := ok(t, `$"x {a + b} y {{lit}} z"`); got != `(string "x " (binary + (ident a) (ident b)) " y {lit}} z")` {
		t.Errorf("插值多段：%s", got)
	}
	if got := ok(t, `$"嵌套 {f(g(1), [2])}"`); got != `(string "嵌套 " (call (ident f) (call (ident g) (int 1)) (array (int 2))))` {
		t.Errorf("插值嵌套：%s", got)
	}
	// 普通串无插值部分
	if got := ok(t, `"plain"`); got != `(string "plain")` {
		t.Errorf("普通串：%s", got)
	}
}

// ---------- 类型引用 ----------

func TestTypeRefs(t *testing.T) {
	cases := []struct {
		src, want string
	}{
		{"Int", "Int"},
		{"pkg.Outer.Inner", "pkg.Outer.Inner"},
		{"List<Int>", "List<Int>"},
		{"Map<String, List<Int>>", "Map<String, List<Int>>"},
		{"Int?", "Int?"},
		{"Int?[]", "Int?[]"},
		{"Int[]?", "Int[]?"},
		{"Int(Int, String)", "Int(Int, String)"},
		{"void()", "void()"},
		{"(Int, String)(Int)", "(Int, String)(Int)"},
		{"(Int, String)?", "(Int, String)?"},
		{"List<Int>[]?", "List<Int>[]?"},
	}
	for _, c := range cases {
		toks, diags := Lex("t.x", c.src)
		if len(diags) != 0 {
			t.Fatalf("`%s` 词法诊断：%v", c.src, diags)
		}
		p := &parser{file: "t.x", toks: toks}
		ty := p.parseTypeRef()
		if got := PrintType(ty); got != c.want {
			t.Errorf("类型 `%s`\n  got  %s\n  want %s", c.src, got, c.want)
		}
	}
}

// ---------- 错误与恢复 ----------

func TestErrors(t *testing.T) {
	fail(t, "a < b < c", synChainCompare)
	fail(t, "a ..< b ..< c", synChainRange)
	fail(t, "()", synTupleArity) // 空括号既非括号表达式也非元组
	fail(t, "new Int 3", synNewForm)
	fail(t, "1 + ", synExpect)
	fail(t, "a ? b", synExpect) // 三元缺 `:`
	// 多错误不中断
	_, diags := ParseExpr("t.x", "(1) + (2)")
	// `(1)`、`(2)` 是合法括号表达式，此例应零诊断
	if len(diags) != 0 {
		t.Fatalf("括号表达式不应报元组错误：%v", render(diags))
	}
	fail(t, "f(1, ", synExpect)
}

func TestSpecExamplesExpr(t *testing.T) {
	// S1 §7.5 与 §7.7 的完整示例（表达式与闭包层面零诊断）。
	specs := []string{
		`user?.name`,
		`name?.length() ?? 0`,
		`(Int x) -> x + 1`,
		`x is Int`,
		`boxed as? Int`,
		`missing ?? 0`,
		`$"value={total}"`,
		`new Byte[4096]`,
		`identity<Int>(1)`,
	}
	for _, src := range specs {
		e, diags := ParseExpr("t.x", src)
		if len(diags) != 0 {
			t.Errorf("规范示例 `%s` 应零诊断：%v", src, render(diags))
		}
		if e == nil {
			t.Errorf("规范示例 `%s` 未产出 AST", src)
		}
	}
}
