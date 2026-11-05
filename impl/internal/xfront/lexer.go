package xfront

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/diag"
)

// 词法诊断码（实现侧 LEX-1xx 段位，本包内稳定）。
const (
	lexIllegalChar  = "LEX-101" // 无法识别的字符
	lexUnterminated = "LEX-102" // 未闭合的注释/字符串/字符字面量
	lexBadEscape    = "LEX-103" // 未知转义、位数不足、非法标量值
	lexBadNumber    = "LEX-104" // 非法数字格式、下划线位置错误、后缀冲突
	lexBadInterp    = "LEX-105" // 非法插值表达式边界
	lexCharContents = "LEX-106" // 空字符字面量、多字符、跨行
)

type lexer struct {
	file      string
	src       []rune
	i         int
	line      int
	col       int
	sawNL     bool
	last      *Token
	stash     *Token
	badNumber bool
	errs      []diag.Diagnostic
}

// Lex 对源文件做词法分析（S1 §1）。
// CRLF 归一化为 LF；BOM 只允许出现在文件开头且不参与列号。
// 词法错误不中断扫描，可返回多个错误；错误 token 附带诊断，不被静默当作合法 token。
func Lex(file, src string) ([]Token, []diag.Diagnostic) {
	l := &lexer{file: file, src: []rune(src), line: 1, col: 1}
	if len(l.src) > 0 && l.src[0] == '\ufeff' {
		l.i = 1 // BOM 不参与列号计数
	}
	var toks []Token
	for {
		t := l.Next()
		toks = append(toks, t)
		if t.Kind == EOF {
			return toks, l.errs
		}
	}
}

func (l *lexer) pos() Pos { return Pos{Line: l.line, Col: l.col} }

func (l *lexer) atEnd() bool { return l.i >= len(l.src) }

func (l *lexer) peek(n int) rune {
	if l.i+n >= len(l.src) {
		return 0
	}
	return l.src[l.i+n]
}

func (l *lexer) advance() rune {
	r := l.src[l.i]
	l.i++
	if r == '\n' {
		l.line++
		l.col = 1
	} else {
		l.col++
	}
	return r
}

func (l *lexer) err(pos Pos, code, msg, hint string) {
	l.errs = append(l.errs, diag.Diagnostic{File: l.file, Line: pos.Line, Col: pos.Col, Code: code, Message: msg, Hint: hint})
}

func isDigit(r rune) bool      { return r >= '0' && r <= '9' }
func isHexDigit(r rune) bool   { return isDigit(r) || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F') }
func isIdentStart(r rune) bool { return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_' }
func isIdentRune(r rune) bool  { return isIdentStart(r) || isDigit(r) }

// Next 返回下一个词法单元，按需插入自动分号（S1 §1.6）。
func (l *lexer) Next() Token {
	if l.stash != nil {
		t := *l.stash
		l.stash = nil
		l.last = &t
		return t
	}

	for {
		l.skipTrivia()
		if l.atEnd() {
			if l.sawNL && l.last != nil && insertable(l.last) {
				l.sawNL = false
				l.stash = &Token{Kind: EOF, Pos: l.pos()}
				return Token{Kind: Semi, Pos: l.last.Pos}
			}
			return Token{Kind: EOF, Pos: l.pos()}
		}
		t, ok := l.scanToken()
		if !ok {
			continue // 非法字符已报错并跳过，继续扫描
		}
		if l.sawNL && l.last != nil && insertable(l.last) && !blocksSemi(t, l.last) {
			l.stash = &t
			l.sawNL = false
			return Token{Kind: Semi, Pos: l.last.Pos}
		}
		l.last = &t
		l.sawNL = false
		return t
	}
}

// skipTrivia 跳过空白与注释，记录是否跨过换行。
func (l *lexer) skipTrivia() {
	for !l.atEnd() {
		r := l.peek(0)
		switch {
		case r == ' ' || r == '\t' || r == '\r':
			l.advance()
		case r == '\n':
			l.sawNL = true
			l.advance()
		case r == '/' && l.peek(1) == '/':
			for !l.atEnd() && l.peek(0) != '\n' {
				l.advance()
			}
		case r == '/' && l.peek(1) == '*':
			start := l.pos()
			l.advance()
			l.advance()
			closed := false
			for !l.atEnd() {
				if l.peek(0) == '*' && l.peek(1) == '/' {
					l.advance()
					l.advance()
					closed = true
					break
				}
				l.advance()
			}
			if !closed {
				l.err(start, lexUnterminated, "块注释未闭合", "块注释不嵌套，以 `*/` 结束")
				return
			}
		default:
			return
		}
	}
}

func insertable(t *Token) bool {
	switch t.Kind {
	case Ident, IntLit, FloatLit, CharLit, StrLit, RParen, RBrack, RBrace:
		return true
	case Annotation: // `@注解` 总是附着到其后的声明，注解行换行不终止（§1.6）
		return false
	case Op:
		return t.Text == "++" || t.Text == "--"
	case Keyword:
		return t.Text == "return" || t.Text == "break" || t.Text == "continue" || t.Text == "throw"
	}
	return false
}

// blocksSemi 报告该 token 之前不得插入语句结束：
// 仅限 `}` 之后的 `else` 与 `while`（else 分支、do-while 续行，S1 §1.6）。
func blocksSemi(t Token, last *Token) bool {
	if last.Kind != RBrace {
		return false
	}
	return t.Kind == Keyword && (t.Text == "else" || t.Text == "while")
}

func (l *lexer) scanToken() (Token, bool) {
	start := l.pos()
	r := l.peek(0)

	// 字符串前缀判定（先多行后单行；在标识符扫描之前）。
	if r == '"' && l.peek(1) == '"' && l.peek(2) == '"' {
		return l.lexString(start, false, true, false), true
	}
	if r == 'r' && l.peek(1) == '"' && l.peek(2) == '"' && l.peek(3) == '"' {
		return l.lexString(start, true, true, false), true
	}
	if r == '$' && l.peek(1) == '"' {
		return l.lexString(start, false, false, true), true
	}
	if r == 'r' && l.peek(1) == '"' {
		return l.lexString(start, true, false, false), true
	}
	if r == '"' {
		return l.lexString(start, false, false, false), true
	}

	if isDigit(r) {
		return l.lexNumber(start), true
	}
	if r == '\'' {
		return l.lexChar(start), true
	}
	if r == '@' && isIdentStart(l.peek(1)) {
		l.advance()
		var b strings.Builder
		for !l.atEnd() && isIdentRune(l.peek(0)) {
			b.WriteRune(l.advance())
		}
		return Token{Kind: Annotation, Text: b.String(), Pos: start}, true
	}
	if isIdentStart(r) {
		var b strings.Builder
		for !l.atEnd() && isIdentRune(l.peek(0)) {
			b.WriteRune(l.advance())
		}
		text := b.String()
		// `as?` 是一个 token（S1 §1.5）。
		if text == "as" && l.peek(0) == '?' {
			l.advance()
			return Token{Kind: Op, Text: "as?", Pos: start}, true
		}
		if _, ok := keywords[text]; ok {
			return Token{Kind: Keyword, Text: text, Pos: start}, true
		}
		return Token{Kind: Ident, Text: text, Pos: start}, true
	}
	return l.lexOperator(start)
}

func (l *lexer) lexOperator(start Pos) (Token, bool) {
	for _, op := range operators {
		rs := []rune(op)
		if l.matchRunes(rs) {
			kind := Op
			switch op {
			case "(":
				kind = LParen
			case ")":
				kind = RParen
			case "{":
				kind = LBrace
			case "}":
				kind = RBrace
			case "[":
				kind = LBrack
			case "]":
				kind = RBrack
			case ",":
				kind = Comma
			case ";":
				kind = Semi
			}
			return Token{Kind: kind, Text: op, Pos: start}, true
		}
	}
	// 无法识别的字符（S1 §1.7）。
	r := l.advance()
	l.err(start, lexIllegalChar, fmt.Sprintf("无法识别的字符 %q", string(r)), "")
	return Token{}, false
}

func (l *lexer) matchRunes(rs []rune) bool {
	for j, want := range rs {
		if l.peek(j) != want {
			return false
		}
	}
	for range rs {
		l.advance()
	}
	return true
}

// ---- 数字（S1 §1.4.1 / §1.4.2） ----

func (l *lexer) lexNumber(start Pos) Token {
	beg := l.i
	if l.peek(0) == '0' {
		switch l.peek(1) {
		case 'x', 'X':
			return l.lexBased(start, 16)
		case 'b', 'B':
			return l.lexBased(start, 2)
		case 'o', 'O':
			return l.lexBased(start, 8)
		}
	}

	l.scanDigitRun(10, start)
	if l.badNumber {
		l.badNumber = false
		return Token{Kind: IntLit, Pos: start}
	}

	// 浮点：小数部分（小数点前后都必须有数字，S1 §1.4.2）。
	if l.peek(0) == '.' && isDigit(l.peek(1)) {
		l.advance()
		l.scanDigitRun(10, start)
		l.badNumber = false
		l.scanExponent(start)
		return l.finishFloat(start, beg)
	}
	// 浮点：指数形式。
	if (l.peek(0) == 'e' || l.peek(0) == 'E') && exponentFollows(l) {
		l.scanExponent(start)
		return l.finishFloat(start, beg)
	}
	return l.finishInt(start, beg)
}

// scanExponent 消费可选的指数部分（e/E ± 数位）。
func (l *lexer) scanExponent(start Pos) {
	if !((l.peek(0) == 'e' || l.peek(0) == 'E') && exponentFollows(l)) {
		return
	}
	l.advance()
	if l.peek(0) == '+' || l.peek(0) == '-' {
		l.advance()
	}
	l.scanDigitRun(10, start)
	l.badNumber = false
}

func exponentFollows(l *lexer) bool {
	if isDigit(l.peek(1)) {
		return true
	}
	return (l.peek(1) == '+' || l.peek(1) == '-') && isDigit(l.peek(2))
}

// scanDigitRun 消费一串数位；下划线只能出现在两个数位之间（S1 §1.4.1）。
func (l *lexer) scanDigitRun(base int, start Pos) {
	valid := digitValid(base)
	sawDigit := false
	for !l.atEnd() {
		r := l.peek(0)
		if r == '_' {
			if !sawDigit || !valid(l.peek(1)) {
				l.err(l.pos(), lexBadNumber, "下划线位置错误", "下划线只能出现在两个数位之间")
				l.badNumber = true
				return
			}
			l.advance()
			continue
		}
		if !valid(r) {
			// 非十进制遇到写错的数位 → 明确报进制错；后缀字母（L/U）结束数位串。
			if base != 10 && (isHexDigit(r) || isIdentRune(r)) && !isSuffixStart(r) {
				l.err(l.pos(), lexBadNumber, baseName(base)+"数位非法", "")
				l.badNumber = true
				return
			}
			return
		}
		sawDigit = true
		l.advance()
	}
	if !sawDigit {
		l.err(start, lexBadNumber, "缺少数位", "")
		l.badNumber = true
	}
}

func digitValid(base int) func(rune) bool {
	switch base {
	case 16:
		return isHexDigit
	case 2:
		return func(r rune) bool { return r == '0' || r == '1' }
	case 8:
		return func(r rune) bool { return r >= '0' && r <= '7' }
	}
	return isDigit
}

func baseName(base int) string {
	switch base {
	case 2:
		return "二进制"
	case 8:
		return "八进制"
	case 16:
		return "十六进制"
	}
	return "十进制"
}

func isSuffixStart(r rune) bool {
	return r == 'L' || r == 'l' || r == 'U' || r == 'u'
}

// finishInt 处理整数后缀（L / U / UL，不区分大小写，S1 §1.4.1）。
func (l *lexer) finishInt(start Pos, beg int) Token {
	t := Token{Kind: IntLit, Pos: start, Base: 10}
	t.Suffix = l.intSuffix()
	t.Text = string(l.src[beg:l.i])
	if l.trailingJunk() {
		l.err(l.pos(), lexBadNumber, "数字字面量后紧跟非法字符", "后缀只能是 L、U、UL（不区分大小写）")
	}
	return t
}

func (l *lexer) intSuffix() string {
	r := l.peek(0)
	if r != 'L' && r != 'l' && r != 'U' && r != 'u' {
		return ""
	}
	first := l.advance()
	if first == 'U' || first == 'u' {
		if n := l.peek(0); n == 'L' || n == 'l' {
			l.advance()
			return "UL"
		}
		return "U"
	}
	return "L"
}

func (l *lexer) lexBased(start Pos, base int) Token {
	beg := l.i
	l.advance() // 0
	l.advance() // x / b / o
	t := Token{Kind: IntLit, Pos: start, Base: base}
	l.scanDigitRun(base, start)
	if l.badNumber {
		l.badNumber = false
		return t
	}
	// 十六进制浮点不支持（S1 §1.4.2）。
	if base == 16 && l.peek(0) == '.' {
		l.err(l.pos(), lexBadNumber, "浮点仅支持十进制", "")
		return t
	}
	t.Suffix = l.intSuffix()
	t.Text = string(l.src[beg:l.i])
	if l.trailingJunk() {
		l.err(l.pos(), lexBadNumber, "数字字面量后紧跟非法字符", "")
	}
	return t
}

// trailingJunk 报告数字字面量后是否紧跟标识符字符或数位（后缀冲突等，S1 §1.7）。
func (l *lexer) trailingJunk() bool {
	r := l.peek(0)
	return isIdentStart(r) || isDigit(r)
}

// finishFloat 处理浮点后缀 f（S1 §1.4.2）。
func (l *lexer) finishFloat(start Pos, beg int) Token {
	t := Token{Kind: FloatLit, Pos: start}
	if l.peek(0) == 'f' {
		l.advance()
		t.HasSuffixF = true
	}
	t.Text = string(l.src[beg:l.i])
	if l.trailingJunk() {
		l.err(l.pos(), lexBadNumber, "数字字面量后紧跟非法字符", "浮点后缀只有 f")
	}
	return t
}

// ---- 字符（S1 §1.4.3） ----

func (l *lexer) lexChar(start Pos) Token {
	l.advance() // '
	t := Token{Kind: CharLit, Pos: start}
	if l.atEnd() || l.peek(0) == '\n' {
		l.err(start, lexUnterminated, "字符字面量未闭合", "字符字面量不得跨行")
		return t
	}
	if l.peek(0) == '\'' {
		l.advance()
		l.err(start, lexCharContents, "空字符字面量", "内容必须恰好一个标量值或一个转义序列")
		return t
	}
	var r rune
	if l.peek(0) == '\\' {
		esc, ok := l.scanEscape()
		if !ok {
			return t
		}
		r = esc
	} else {
		r = l.advance()
		if r == '\n' {
			l.err(start, lexCharContents, "字符字面量跨行", "")
			return t
		}
	}
	if !validScalar(r) {
		l.err(start, lexBadEscape, "非法标量值", fmt.Sprintf("U+%04X 不在合法标量范围", r))
		return t
	}
	if l.atEnd() {
		l.err(start, lexUnterminated, "字符字面量未闭合", "字符字面量不得跨行")
		return t
	}
	if l.peek(0) != '\'' {
		l.err(start, lexCharContents, "多字符字面量", "内容必须恰好一个标量值或一个转义序列")
		for !l.atEnd() && l.peek(0) != '\n' && l.peek(0) != '\'' {
			l.advance()
		}
		if l.peek(0) == '\'' {
			l.advance()
		}
		return t
	}
	l.advance()
	t.Char = r
	return t
}

func validScalar(r rune) bool {
	return r >= 0 && r <= 0x10FFFF && !(r >= 0xD800 && r <= 0xDFFF)
}

// scanEscape 消费一个转义序列（S1 §1.4.3 转义表），返回对应标量值。
func (l *lexer) scanEscape() (rune, bool) {
	start := l.pos()
	l.advance() // 反斜杠
	r := l.advance()
	switch r {
	case '\\':
		return '\\', true
	case '\'':
		return '\'', true
	case '"':
		return '"', true
	case 'n':
		return '\n', true
	case 'r':
		return '\r', true
	case 't':
		return '\t', true
	case '0':
		return 0, true
	case 'x':
		return l.hexEscape(start, 2, false)
	case 'u':
		if l.peek(0) == '{' {
			return l.hexEscape(start, 0, true)
		}
		return l.hexEscape(start, 4, false)
	}
	l.err(start, lexBadEscape, fmt.Sprintf("未知转义 %q", "\\"+string(r)), "可用：\\\\ \\' \\\" \\n \\r \\t \\0 \\xHH \\uHHHH \\u{H…}")
	return 0, false
}

// hexEscape 消费定长（fixed>0）或花括号变长（braces）十六进制转义。
func (l *lexer) hexEscape(start Pos, fixed int, braces bool) (rune, bool) {
	if braces {
		l.advance() // {
		var v rune
		n := 0
		for !l.atEnd() && isHexDigit(l.peek(0)) {
			v = v*16 + hexVal(l.advance())
			n++
			if n > 6 {
				l.err(start, lexBadEscape, "\\u{…} 超过 6 位十六进制", "")
				return 0, false
			}
		}
		if n < 1 || l.peek(0) != '}' {
			l.err(start, lexBadEscape, "\\u{…} 形式非法", "1 到 6 位十六进制，以 } 结束")
			return 0, false
		}
		l.advance()
		if !validScalar(v) {
			l.err(start, lexBadEscape, "非法标量值", fmt.Sprintf("U+%X 不在合法标量范围", v))
			return 0, false
		}
		return v, true
	}
	var v rune
	for i := 0; i < fixed; i++ {
		if !isHexDigit(l.peek(0)) {
			l.err(start, lexBadEscape, "十六进制位数不足", "")
			return 0, false
		}
		v = v*16 + hexVal(l.advance())
	}
	if !validScalar(v) {
		l.err(start, lexBadEscape, "非法标量值", fmt.Sprintf("U+%04X 不在合法标量范围", v))
		return 0, false
	}
	return v, true
}

func hexVal(r rune) rune {
	switch {
	case r >= '0' && r <= '9':
		return r - '0'
	case r >= 'a' && r <= 'f':
		return r - 'a' + 10
	default:
		return r - 'A' + 10
	}
}

// ---- 字符串（S1 §1.4.4） ----

func (l *lexer) lexString(start Pos, raw, multiline, interp bool) Token {
	if raw || interp {
		l.advance() // r / $
	}
	l.advance() // 开引号
	if multiline {
		l.advance()
		l.advance()
	}

	var val strings.Builder
	var segs []string
	var interps []string
	depth := 0
	var expr strings.Builder
	pushSeg := func() { segs = append(segs, val.String()); val.Reset() }

	fail := func(code, msg, hint string) Token {
		l.err(start, code, msg, hint)
		return Token{Kind: StrLit, Str: strKindOf(raw, multiline, interp), Value: val.String(), Interps: interps, Pos: start}
	}

	for {
		if l.atEnd() {
			if depth > 0 {
				return fail(lexBadInterp, "插值表达式未闭合", "插值以 } 结束")
			}
			return fail(lexUnterminated, "字符串未闭合", "")
		}
		r := l.peek(0)

		if !multiline && r == '\n' {
			if depth > 0 {
				return fail(lexBadInterp, "插值表达式未闭合", "插值以 } 结束")
			}
			return fail(lexUnterminated, "字符串未闭合", "单行字符串不得跨行")
		}

		// 结束定界符。
		if r == '"' {
			if multiline {
				if l.peek(1) == '"' && l.peek(2) == '"' {
					l.advance()
					l.advance()
					l.advance()
					if depth > 0 {
						l.err(start, lexBadInterp, "插值表达式未闭合", "插值以 } 结束")
					}
					pushSeg()
					return Token{Kind: StrLit, Str: strKindOf(raw, multiline, interp), Value: concatSegs(segs, val.String()), Segs: segs, Interps: interps, Pos: start}
				}
			} else if depth == 0 {
				l.advance()
				pushSeg()
				return Token{Kind: StrLit, Str: strKindOf(raw, multiline, interp), Value: concatSegs(segs, val.String()), Segs: segs, Interps: interps, Pos: start}
			}
		}

		if depth > 0 {
			// 插值表达式内部：跟踪括号嵌套与边界。
			switch r {
			case '{', '(', '[':
				depth++
				expr.WriteRune(l.advance())
			case '}', ')', ']':
				if r == '}' && depth == 1 {
					l.advance()
					interps = append(interps, expr.String())
					expr.Reset()
					depth = 0
					continue
				}
				if r == '}' || r == ')' || r == ']' {
					depth--
				}
				expr.WriteRune(l.advance())
			default:
				expr.WriteRune(l.advance())
			}
			continue
		}

		// 插值开始；`{{` 产生字面量 `{`。
		if interp && r == '{' {
			if l.peek(1) == '{' {
				l.advance()
				l.advance()
				val.WriteRune('{')
				continue
			}
			pushSeg()
			l.advance()
			depth = 1
			expr.Reset()
			continue
		}

		// 普通与多行（非原始）处理转义；原始字符串反斜杠按普通字符保存。
		if !raw && r == '\\' {
			if c, ok := l.scanEscape(); ok {
				val.WriteRune(c)
				continue
			}
			return Token{Kind: StrLit, Str: strKindOf(raw, multiline, interp), Value: val.String(), Interps: interps, Pos: start}
		}

		val.WriteRune(l.advance())
	}
}

func strKindOf(raw, multiline, interp bool) StrKind {
	switch {
	case interp:
		return StrInterp
	case raw && multiline:
		return StrRawMultiline
	case raw:
		return StrRaw
	case multiline:
		return StrMultiline
	}
	return StrNormal
}

// concatSegs 拼接静态段（插值串 Value 保持旧行为：全部静态文本连写）。
func concatSegs(segs []string, last string) string {
	all := append(append([]string{}, segs...), last)
	return strings.Join(all, "")
}
