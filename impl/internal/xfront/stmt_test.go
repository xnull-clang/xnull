package xfront

import (
	"strings"
	"testing"
)

// ss 解析语句序列并返回 S 表达式串（语句间以 \n 连接）。
func ss(t *testing.T, src string) string {
	t.Helper()
	out, diags := ParseStmts("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("源 `%s` 不应有诊断：%v", src, render(diags))
	}
	var parts []string
	for _, s := range out {
		parts = append(parts, PrintStmt(s))
	}
	return strings.Join(parts, "\n")
}

// ssFail 解析必须产生含指定码的诊断。
func ssFail(t *testing.T, src, code string) {
	t.Helper()
	_, diags := ParseStmts("t.x", src)
	for _, d := range diags {
		if d.Code == code {
			return
		}
	}
	t.Fatalf("源 `%s` 期望诊断 %s，实际：%v", src, code, render(diags))
}

// ---------- §5.1 局部声明四形态 ----------

func TestLocalDecls(t *testing.T) {
	cases := []struct{ src, want string }{
		{"Int total = 0", "(decl Int total (int 0))"},
		{"final Int answer = 42", "(decl final Int answer (int 42))"},
		{"const Int limit = 10", "(decl const Int limit (int 10))"},
		{"var count = 1", "(decl var count (int 1))"},
		{"Int x", "(decl Int x)"}, // 确定赋值之后补（§5.1）
		{"final Int y", "(decl final Int y)"},
		{"List<Int> xs = [1, 2]", "(decl List<Int> xs (array (int 1) (int 2)))"},
		{"Int(Int) f = g", "(decl Int(Int) f (ident g))"}, // 函数类型声明
		{"T? maybe = null", "(decl T? maybe (null))"},
	}
	for _, c := range cases {
		if got := ss(t, c.src); got != c.want {
			t.Errorf("`%s`\n  got  %s\n  want %s", c.src, got, c.want)
		}
	}
	// 类型后跟 `.` 是表达式不是声明（歧义判定）
	if got := ss(t, "Int.valueOf(3)"); got != "(expr (call (member (ident Int) valueOf) (int 3)))" {
		t.Errorf("类型限定表达式误判为声明：%s", got)
	}
}

// ---------- §6.4 赋值与自增/自减（只作为语句） ----------

func TestAssignments(t *testing.T) {
	cases := []struct{ src, want string }{
		{"total = total + 1", "(assign = (ident total) (binary + (ident total) (int 1)))"},
		{"total += 1", "(assign += (ident total) (int 1))"},
		{"values[0] = 1", "(assign = (index (ident values) (int 0)) (int 1))"},
		{"list[0] = 2", "(assign = (index (ident list) (int 0)) (int 2))"},
		{"obj.field >>= 2", "(assign >>= (member (ident obj) field) (int 2))"},
		{"t.0 = 5", "(assign = (tuplemember (ident t) 0) (int 5))"},
		{"i++", "(incdec ++ (ident i))"},
		{"--i", "(incdec pre -- (ident i))"},
		{"m[k] += v", "(assign += (index (ident m) (ident k)) (ident v))"},
	}
	for _, c := range cases {
		if got := ss(t, c.src); got != c.want {
			t.Errorf("`%s`\n  got  %s\n  want %s", c.src, got, c.want)
		}
	}
	// 不可赋值目标
	ssFail(t, "f() = 1", synAssignTarget)
	ssFail(t, "(a) = 1", synAssignTarget)  // 括号不是 Assignable
	ssFail(t, "a?.b = 1", synAssignTarget) // 可空链不在 Assignable 集
	// 赋值不是表达式：不得串联
	ssFail(t, "a = b = c", synStmtTerm) // 第二个 = 成了同行未终止
}

// ---------- §6.5—§6.7 控制流 ----------

func TestControlFlow(t *testing.T) {
	// if / else-if / else（体强制花括号，条件无括号）
	if got := ss(t, "if ready { handle(1) } else if other { handle(2) } else { handle(3) }"); got !=
		"(if (ident ready) (block (expr (call (ident handle) (int 1)))) (else (if (ident other) (block (expr (call (ident handle) (int 2)))) (else (block (expr (call (ident handle) (int 3))))))))" {
		t.Errorf("if/else-if/else：%s", got)
	}
	// while
	if got := ss(t, "while x < 3 { x++ }"); got !=
		"(while (binary < (ident x) (int 3)) (block (incdec ++ (ident x))))" {
		t.Errorf("while：%s", got)
	}
	// do-while
	if got := ss(t, "do { step() } while go"); got !=
		"(dowhile (block (expr (call (ident step)))) (ident go))" {
		t.Errorf("do-while：%s", got)
	}
	// for-in 容器与区间
	if got := ss(t, "for item in items { handle(item) }"); got !=
		"(for item in (ident items) (block (expr (call (ident handle) (ident item)))))" {
		t.Errorf("for-in：%s", got)
	}
	if got := ss(t, "for i in 0..<n { total += i }"); got !=
		"(for i in (binary ..< (int 0) (ident n)) (block (assign += (ident total) (ident i))))" {
		t.Errorf("区间 for：%s", got)
	}
	if got := ss(t, "for i in 0...n { }"); got != "(for i in (binary ... (int 0) (ident n)) (block))" {
		t.Errorf("闭区间 for：%s", got)
	}
	// 体不是花括号体被拒绝（§6.12）
	ssFail(t, "if x return 1", synExpect)
	ssFail(t, "while x y = 1", synExpect)
}

// ---------- §6.8 switch ----------

func TestSwitch(t *testing.T) {
	src := "switch value { case 1: one() case 2: two() default: other() }"
	want := "(switch (ident value) (case (int 1) (expr (call (ident one)))) (case (int 2) (expr (call (ident two)))) (default (expr (call (ident other)))))"
	if got := ss(t, src); got != want {
		t.Errorf("switch：\n  got  %s\n  want %s", got, want)
	}
	// case 内多条语句、子句独立作用域（结构层面）
	src = "switch v { case 1: Int a = 1; use(a) }"
	want = "(switch (ident v) (case (int 1) (decl Int a (int 1)) (expr (call (ident use) (ident a)))))"
	if got := ss(t, src); got != want {
		t.Errorf("switch case 体：\n  got  %s\n  want %s", got, want)
	}
	// switch 条件带闭包/泛型（值只求值一次，结构层面）
	ss(t, "switch m.get<Int>(k) { case 0: break }")
}

// ---------- §6.9—§6.11 break/continue/return/throw/label/goto/空语句 ----------

func TestJumps(t *testing.T) {
	cases := []struct{ src, want string }{
		{"break", "(break)"},
		{"break outer", "(break outer)"},
		{"continue", "(continue)"},
		{"continue inner", "(continue inner)"},
		{"return", "(return)"},
		{"return value", "(return (ident value))"},
		{"throw \"boom\"", `(throw (string "boom"))`},
		{"goto start", "(goto start)"},
		{";", "(empty)"},
		{"name: ;", "(label name (empty))"},
	}
	for _, c := range cases {
		if got := ss(t, c.src); got != c.want {
			t.Errorf("`%s`\n  got  %s\n  want %s", c.src, got, c.want)
		}
	}
	// 标签 + 循环 + goto（§6.10 示例）
	src := "Int i = 0\nstart:\ni++\nif i < 3 {\n    goto start\n}"
	want := "(decl Int i (int 0))\n(label start (incdec ++ (ident i)))\n(if (binary < (ident i) (int 3)) (block (goto start)))"
	if got := ss(t, src); got != want {
		t.Errorf("goto 示例：\n  got  %s\n  want %s", got, want)
	}
}

// ---------- defer / errdefer（§6.1、附录 A Body = Block | Statement） ----------

func TestDefer(t *testing.T) {
	if got := ss(t, "defer { cleanup() }"); got != "(defer (block (expr (call (ident cleanup)))))" {
		t.Errorf("defer 块体：%s", got)
	}
	if got := ss(t, "defer cleanup()"); got != "(defer (expr (call (ident cleanup))))" {
		t.Errorf("defer 单语句体：%s", got)
	}
	if got := ss(t, "errdefer { log() }"); got != "(errdefer (block (expr (call (ident log)))))" {
		t.Errorf("errdefer：%s", got)
	}
}

// ---------- 语句终止（STMT-01 语法侧：同一行缺分号被拒绝） ----------

func TestStatementTermination(t *testing.T) {
	// 换行终止：无需分号
	ss(t, "Int a = 1\nInt b = 2")
	// 显式分号同行多条
	if got := ss(t, "a = 1; b = 2;"); got != "(assign = (ident a) (int 1))\n(assign = (ident b) (int 2))" {
		t.Errorf("同行分号分隔：%s", got)
	}
	// 同行缺分号
	ssFail(t, "Int a = 1 Int b = 2", synStmtTerm)
	ssFail(t, "f() g()", synStmtTerm)
	// `}` 前不需要分号
	ss(t, "if x { break }")
	// 独立块不是语句（§6.2、§6.12）
	ssFail(t, "{ x = 1 }", synExpect)
}

// ---------- §7.7 闭包在语句中的完整形态 ----------

func TestClosureStatements(t *testing.T) {
	// §7.7 counter 示例（语句骨架）
	src := "Int() counter = () -> {\n    Int value = 0\n    return () -> {\n        value = value + 1\n        return value\n    }\n}"
	out, diags := ParseStmts("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("counter 示例应零诊断：%v", render(diags))
	}
	if !strings.Contains(PrintStmt(out[0]), "(decl Int() counter (lambda -> (block (decl Int value (int 0)) (return (lambda -> (block (assign = (ident value) (binary + (ident value) (int 1))) (return (ident value))))))))") {
		t.Errorf("counter 示例结构不符：%s", PrintStmt(out[0]))
	}
	// 单表达式体
	if got := ss(t, "Int(Int) inc = (Int x) -> x + 1"); got !=
		"(decl Int(Int) inc (lambda (Int x) -> (binary + (ident x) (int 1))))" {
		t.Errorf("单表达式体闭包：%s", got)
	}
}
