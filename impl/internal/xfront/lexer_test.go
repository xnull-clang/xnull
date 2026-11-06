package xfront

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
)

func lex(t *testing.T, src string) ([]Token, []diag.Diagnostic) {
	t.Helper()
	toks, errs := Lex("t.x", src)
	return toks, errs
}

func codes(errs []diag.Diagnostic) []string {
	var out []string
	for _, e := range errs {
		out = append(out, e.Code)
	}
	return out
}

func hasCode(errs []diag.Diagnostic, code string) bool {
	for _, e := range errs {
		if e.Code == code {
			return true
		}
	}
	return false
}

func wantErr(t *testing.T, src, code string) {
	t.Helper()
	_, errs := lex(t, src)
	if !hasCode(errs, code) {
		t.Fatalf("期望诊断 %s，实际 %v（源：%q）", code, codes(errs), src)
	}
}

func wantNoErr(t *testing.T, src string) []Token {
	t.Helper()
	toks, errs := lex(t, src)
	if len(errs) != 0 {
		t.Fatalf("不应有诊断：%v（源：%q）", codes(errs), src)
	}
	return toks
}

// ---- LEX-01：字面量矩阵 ----

func TestIntegerLiterals(t *testing.T) {
	toks := wantNoErr(t, "0 42 1_000_000 0xFF 0b1010 0o755 42L 42U 42UL 0xFFU 0b1_0 0o7_7")
	want := []struct {
		text   string
		base   int
		suffix string
	}{
		{"0", 10, ""}, {"42", 10, ""}, {"1_000_000", 10, ""},
		{"0xFF", 16, ""}, {"0b1010", 2, ""}, {"0o755", 8, ""},
		{"42L", 10, "L"}, {"42U", 10, "U"}, {"42UL", 10, "UL"},
		{"0xFFU", 16, "U"}, {"0b1_0", 2, ""}, {"0o7_7", 8, ""},
	}
	for i, w := range want {
		got := toks[i]
		if got.Kind != IntLit || got.Text != w.text || got.Base != w.base || got.Suffix != w.suffix {
			t.Fatalf("第 %d 个整数字面量不符：got %+v want %+v", i+1, got, w)
		}
	}
}

func TestIntegerLiteralErrors(t *testing.T) {
	cases := []struct {
		src  string
		code string
	}{
		{"1_ ", lexBadNumber},   // 下划线后无数位
		{"1__0", lexBadNumber},  // 连续下划线
		{"0x_FF", lexBadNumber}, // 前缀后下划线
		{"0x", lexBadNumber},    // 缺数位
		{"0b12", lexBadNumber},  // 二进制数位非法
		{"0o8", lexBadNumber},   // 八进制数位非法
		{"0x1G", lexBadNumber},  // 十六进制数位非法
		{"42ULL", lexBadNumber}, // 后缀冲突
		{"42LU", lexBadNumber},  // 非法组合
		{"123abc", lexBadNumber},
		{"0x1.5", lexBadNumber}, // 十六进制浮点
	}
	for _, c := range cases {
		wantErr(t, c.src, c.code)
	}
}

func TestFloatLiterals(t *testing.T) {
	toks := wantNoErr(t, "1.0 3.14159 1.0e9 2.5e-3 1.0f 1e9 1.5E+2 1_000.5")
	want := []struct {
		text  string
		hasF  bool
		float bool
	}{
		{"1.0", false, true}, {"3.14159", false, true}, {"1.0e9", false, true},
		{"2.5e-3", false, true}, {"1.0f", true, true}, {"1e9", false, true},
		{"1.5E+2", false, true}, {"1_000.5", false, true},
	}
	for i, w := range want {
		got := toks[i]
		kind := Kind(FloatLit)
		if !w.float {
			kind = IntLit
		}
		if got.Kind != kind || got.Text != w.text || got.HasSuffixF != w.hasF {
			t.Fatalf("第 %d 个浮点不符：got %+v want %+v", i+1, got, w)
		}
	}
}

func TestFloatLiteralErrors(t *testing.T) {
	wantErr(t, "1.0e", lexBadNumber)  // 指数缺数位
	wantErr(t, "1.0e+", lexBadNumber) // 同上
	wantErr(t, "1.0ff", lexBadNumber) // 后缀冲突
	wantErr(t, "1e9x", lexBadNumber)  // 紧跟非法字符
}

func TestCharLiterals(t *testing.T) {
	toks := wantNoErr(t, `'a' '\n' '\'' '\\' '\u{1F600}' '\x41' '\u0041' '\0'`)
	want := []rune{'a', '\n', '\'', '\\', 0x1F600, 'A', 'A', 0}
	for i, w := range want {
		if toks[i].Kind != CharLit || toks[i].Char != w {
			t.Fatalf("第 %d 个字符不符：got %q want %q", i+1, string(toks[i].Char), string(w))
		}
	}
}

func TestCharLiteralErrors(t *testing.T) {
	cases := []struct {
		src  string
		code string
	}{
		{"''", lexCharContents},      // 空
		{"'ab'", lexCharContents},    // 多字符
		{"'a\n'", lexCharContents},   // 跨行（多字符路径）
		{`\u{D800}`, lexIllegalChar}, // 代理区（不在引号内 → 非法字符）
	}
	for _, c := range cases {
		wantErr(t, c.src, c.code)
	}
	wantErr(t, `'\q'`, lexBadEscape)         // 未知转义
	wantErr(t, `'\x4'`, lexBadEscape)        // 位数不足
	wantErr(t, `'\u{}'`, lexBadEscape)       // 空花括号
	wantErr(t, `'\u{110000}'`, lexBadEscape) // 超范围
	wantErr(t, `'\u{D800}'`, lexBadEscape)   // 代理区
	wantErr(t, `'a`, lexUnterminated)        // 未闭合
}

func TestStringForms(t *testing.T) {
	// 普通：转义生效。
	toks := wantNoErr(t, `"a\nb"`)
	if toks[0].Str != StrNormal || toks[0].Value != "a\nb" {
		t.Fatalf("普通字符串不符：%+v", toks[0])
	}
	// 原始：反斜杠按普通字符保存。
	toks = wantNoErr(t, `r"a\nb"`)
	if toks[0].Str != StrRaw || toks[0].Value != `a\nb` {
		t.Fatalf("原始字符串不符：%+v", toks[0])
	}
	// 多行：内容原样保存（含换行与缩进）。
	toks = wantNoErr(t, "\"\"\"line1\n  line2\"\"\"")
	if toks[0].Str != StrMultiline || toks[0].Value != "line1\n  line2" {
		t.Fatalf("多行字符串不符：%q", toks[0].Value)
	}
	// 原始多行。
	toks = wantNoErr(t, "r\"\"\"a\\nb\"\"\"")
	if toks[0].Str != StrRawMultiline || toks[0].Value != `a\nb` {
		t.Fatalf("原始多行字符串不符：%q", toks[0].Value)
	}
	// 插值：静态文本 + 表达式按源码顺序。
	toks = wantNoErr(t, `"x {a + b} y {{lit}} z"`)
	if toks[0].Str != StrNormal {
		t.Fatalf("无 $ 前缀不得识别为插值串")
	}
	toks = wantNoErr(t, `$"x {a + b} y {{lit}} z"`)
	if toks[0].Str != StrInterp {
		t.Fatalf("应为插值串：%+v", toks[0])
	}
	if toks[0].Value != "x  y {lit}} z" {
		t.Fatalf("插值静态文本不符：%q", toks[0].Value)
	}
	if len(toks[0].Interps) != 1 || toks[0].Interps[0] != "a + b" {
		t.Fatalf("插值表达式不符：%v", toks[0].Interps)
	}
	// 插值内括号嵌套。
	toks = wantNoErr(t, `$"{f(a, {b: 1})}"`)
	if len(toks[0].Interps) != 1 || toks[0].Interps[0] != "f(a, {b: 1})" {
		t.Fatalf("嵌套插值不符：%v", toks[0].Interps)
	}
}

func TestStringErrors(t *testing.T) {
	wantErr(t, `"未闭合`, lexUnterminated)
	wantErr(t, `"跨\n行`+"\n", lexUnterminated) // 单行字符串不能跨行（这里 \n 是真换行）
	wantErr(t, `r"未闭合`, lexUnterminated)
	wantErr(t, "\"\"\"未闭合", lexUnterminated)
	wantErr(t, `"a\u{D800}b"`, lexBadEscape) // 字符串内非法标量
	wantErr(t, `$"a {b`, lexBadInterp)       // 插值未闭合
	wantErr(t, `$"a {b}"`+"\n"+`$"c {d`+"\n", lexBadInterp)
}

// ---- 注释（S1 §1.2） ----

func TestComments(t *testing.T) {
	toks := wantNoErr(t, "a // 行注释\nb /* 块\n注释 */ c")
	if len(toks) != 5 { // a ; b c EOF（换行在 a 后插入分号）
		t.Fatalf("注释应等价于空白：%v", toks)
	}
	// 块注释不嵌套：第一个 */ 结束，随后的 */ 是普通运算符 token。
	toks = wantNoErr(t, "/* /* */ */")
	if toks[0].Kind != Op || toks[0].Text != "*" {
		t.Fatalf("首个 */ 应结束注释，其后 */ 应为运算符：%+v", toks[0])
	}
	// 未闭合块注释。
	wantErr(t, "a /* 未闭合", lexUnterminated)
	// 文档注释按普通块注释处理。
	toks = wantNoErr(t, "/** doc */ a")
	if len(toks) != 2 {
		t.Fatalf("文档注释应被跳过")
	}
}

// ---- 标识符、关键字、注解（S1 §1.3） ----

func TestIdentifiersAndKeywords(t *testing.T) {
	toks := wantNoErr(t, "package import class _x x1 PascalCase UPPER_CASE")
	if toks[0].Kind != Keyword || toks[1].Kind != Keyword || toks[2].Kind != Keyword {
		t.Fatalf("关键字识别不符")
	}
	if toks[3].Kind != Ident || toks[3].Text != "_x" {
		t.Fatalf("下划线开头应为标识符")
	}
	toks = wantNoErr(t, "@Hello @x_1")
	if toks[0].Kind != Annotation || toks[0].Text != "Hello" {
		t.Fatalf("注解识别不符：%+v", toks[0])
	}
	// true/false/null 是字面量常量，不是关键字。
	toks = wantNoErr(t, "true false null")
	for i, w := range []string{"true", "false", "null"} {
		if toks[i].Kind != Ident || toks[i].Text != w {
			t.Fatalf("%s 应为标识符（字面量常量），got %+v", w, toks[i])
		}
	}
}

// ---- 运算符最长匹配（S1 §1.5） ----

func TestOperatorsLongestMatch(t *testing.T) {
	toks := wantNoErr(t, "<<= >>= ... ..< === !== == != <= >= << >> && || ?? ?. += ++ -- -> as?")
	want := []string{"<<=", ">>=", "...", "..<", "===", "!==", "==", "!=", "<=", ">=",
		"<<", ">>", "&&", "||", "??", "?.", "+=", "++", "--", "->", "as?"}
	for i, w := range want {
		if toks[i].Kind != Op || toks[i].Text != w {
			t.Fatalf("第 %d 个运算符应为 %q，got %+v", i+1, w, toks[i])
		}
	}
}

// ---- 自动分号插入（S1 §1.6） ----

func TestAutomaticSemis(t *testing.T) {
	toks := wantNoErr(t, "Int a = 1\nInt b = 2\na = a + b\n")
	// 期望：Int a = 1 ; Int b = 2 ; a = a + b ; EOF
	semis := 0
	for _, tk := range toks {
		if tk.Kind == Semi {
			semis++
		}
	}
	if semis != 3 {
		t.Fatalf("应插入 3 个分号（含 EOF 前），实际 %d：%v", semis, toks)
	}
	// 显式分号。
	toks = wantNoErr(t, "Int c = 1; Int d = 2\n")
	semis = 0
	for _, tk := range toks {
		if tk.Kind == Semi {
			semis++
		}
	}
	if semis != 2 {
		t.Fatalf("显式+自动应为 2 个分号，实际 %d", semis)
	}
}

func TestNoSemiBeforeElseAndDoWhile(t *testing.T) {
	// } 之后、else 之前不插入。
	toks := wantNoErr(t, "if x {\n} \nelse {\n}\n")
	for i, tk := range toks {
		if tk.Kind == Keyword && tk.Text == "else" {
			if toks[i-1].Kind != RBrace {
				t.Fatalf("else 前应为 }，got %+v", toks[i-1])
			}
			continue
		}
		if i > 0 && tk.Kind == Keyword && tk.Text == "else" && toks[i-1].Kind == Semi {
			t.Fatalf("else 之前不得插入分号")
		}
	}
	// do-while：} 之后、while 之前不插入。
	toks = wantNoErr(t, "do {\n} \nwhile cond\n")
	for i, tk := range toks {
		if tk.Kind == Keyword && tk.Text == "while" && toks[i-1].Kind == Semi {
			t.Fatalf("do 的 while 之前不得插入分号")
		}
	}
	// 但普通语句后的 while 语句必须插分号。
	toks = wantNoErr(t, "x = y\nwhile cond {\n}\n")
	found := false
	for i, tk := range toks {
		if tk.Kind == Keyword && tk.Text == "while" && i > 0 && toks[i-1].Kind == Semi {
			found = true
		}
	}
	if !found {
		t.Fatalf("独立 while 语句前应有分号")
	}
}

func TestSemiAfterLiteralsAndCalls(t *testing.T) {
	toks := wantNoErr(t, "f(1)\n\"s\"\n'c'\nxs[0]\n")
	semis := 0
	for _, tk := range toks {
		if tk.Kind == Semi {
			semis++
		}
	}
	if semis != 4 {
		t.Fatalf(")、字符串、字符、] 后都应插分号，实际 %d", semis)
	}
}

// ---- 源文件（S1 §1.1） ----

func TestSourceFileRules(t *testing.T) {
	// CRLF 归一化：不报错、正常插分号。
	toks := wantNoErr(t, "a = 1\r\nb = 2\r\n")
	semis := 0
	for _, tk := range toks {
		if tk.Kind == Semi {
			semis++
		}
	}
	if semis != 2 {
		t.Fatalf("CRLF 应等价 LF，实际分号 %d", semis)
	}
	// BOM 只在文件开头允许，且不参与列号。
	toks = wantNoErr(t, "\ufeffa")
	if toks[0].Pos.Col != 1 {
		t.Fatalf("BOM 后首 token 列应为 1，got %d", toks[0].Pos.Col)
	}
	// 空行与注释行不触发语句结束：a = 1 之后的分号只插一次。
	toks = wantNoErr(t, "a = 1\n\n\n// 注释行\nb = 2\n")
	semis = 0
	for _, tk := range toks {
		if tk.Kind == Semi {
			semis++
		}
	}
	if semis != 2 {
		t.Fatalf("空行与注释行不应额外触发语句结束，实际 %d", semis)
	}
}

// ---- 多错误与诊断位置（S1 §1.7） ----

func TestMultipleErrorsWithPosition(t *testing.T) {
	_, errs := lex(t, "a = 1\nb = `\nc = 0b2\n")
	if len(errs) < 2 {
		t.Fatalf("应报多个错误，实际 %d", len(errs))
	}
	for _, e := range errs {
		if e.File != "t.x" || e.Line < 1 || e.Col < 1 {
			t.Fatalf("诊断缺位置：%+v", e)
		}
	}
}

func TestReservedListed(t *testing.T) {
	// 保留名由语义层拒绝；词法按标识符返回且不报错（S1 §1.3）。
	toks := wantNoErr(t, "async await yield unsafe extern macro")
	for _, tk := range toks[:len(toks)-1] {
		if tk.Kind != Ident {
			t.Fatalf("保留名应按标识符返回：%+v", tk)
		}
		if _, ok := Reserved[tk.Text]; !ok {
			t.Fatalf("%q 应在保留名表", tk.Text)
		}
	}
}

func TestAdjacentStringsNoConcat(t *testing.T) {
	// 相邻字符串不自动拼接：两个独立 StrLit（S1 §1.4.4）。
	toks := wantNoErr(t, `"a" "b"`)
	if toks[0].Kind != StrLit || toks[1].Kind != StrLit || toks[2].Kind != EOF {
		t.Fatalf("应为两个独立字符串 token")
	}
	if strings.Join([]string{toks[0].Value, toks[1].Value}, "|") != "a|b" {
		t.Fatalf("字符串内容不符")
	}
}
