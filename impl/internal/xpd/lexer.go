package xpd

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/diag"
)

const (
	codeIllegalChar  = "XPD-001"
	codeUntermString = "XPD-002"
	codeBadEscape    = "XPD-003"
	codeBOM          = "XPD-004"
	codeEmptyValue   = "XPD-005"
	codeUntermVar    = "XPD-006"
)

type lexer struct {
	file string
	src  []rune
	i    int
	line int
	col  int
}

func newLexer(file, src string) *lexer {
	return &lexer{file: file, src: []rune(src), line: 1, col: 1}
}

func (l *lexer) pos() Pos { return Pos{Line: l.line, Col: l.col} }

func (l *lexer) atEnd() bool { return l.i >= len(l.src) }

func (l *lexer) peek(offset int) rune {
	if l.i+offset >= len(l.src) {
		return 0
	}
	return l.src[l.i+offset]
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

func isSpace(r rune) bool { return r == ' ' || r == '\t' || r == '\r' }

func isDigit(r rune) bool { return r >= '0' && r <= '9' }

func isAlpha(r rune) bool { return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') }

// isBareRune 是裸词允许的字符：字母、数字、`-` `.` `_` `:` `/` `\`。
func isBareRune(r rune) bool {
	return isAlpha(r) || isDigit(r) || r == '-' || r == '.' || r == '_' || r == ':' ||
		r == '/' || r == '\\' || r == '*' || r == '?'
}

func isIdentText(s string) bool {
	if s == "" || !isAlpha(rune(s[0])) {
		return false
	}
	for _, r := range s {
		if !isAlpha(r) && !isDigit(r) && r != '-' {
			return false
		}
	}
	return true
}

// Next 返回下一个词法单元；遇到词法错误时返回错误并跳过该字符。
func (l *lexer) Next() (Token, *diag.Diagnostic) {
	for !l.atEnd() {
		r := l.peek(0)
		switch {
		case r == '\n':
			// 换行是字段与条目的终止符（C.1），必须作为独立单元交给语法层。
			p := l.pos()
			l.advance()
			return Token{Kind: Newline, Text: "\n", Pos: p}, nil
		case isSpace(r):
			l.advance()
			continue
		case r == '#':
			for !l.atEnd() && l.peek(0) != '\n' {
				l.advance()
			}
			continue
		case r == '\ufeff':
			p := l.pos()
			l.advance()
			return Token{Kind: EOF, Pos: p}, &diag.Diagnostic{
				File: l.file, Line: p.Line, Col: p.Col, Code: codeBOM,
				Message: "不允许 BOM", Hint: "文件必须以 UTF-8（无 BOM）保存",
			}
		}
		break
	}

	if l.atEnd() {
		return Token{Kind: EOF, Pos: l.pos()}, nil
	}

	start := l.pos()
	r := l.peek(0)

	switch r {
	case '{':
		l.advance()
		return Token{Kind: LBrace, Text: "{", Pos: start}, nil
	case '}':
		l.advance()
		return Token{Kind: RBrace, Text: "}", Pos: start}, nil
	case '[':
		l.advance()
		return Token{Kind: LBrack, Text: "[", Pos: start}, nil
	case ']':
		l.advance()
		return Token{Kind: RBrack, Text: "]", Pos: start}, nil
	case '(':
		l.advance()
		return Token{Kind: LParen, Text: "(", Pos: start}, nil
	case ')':
		l.advance()
		return Token{Kind: RParen, Text: ")", Pos: start}, nil
	case ',':
		l.advance()
		return Token{Kind: Comma, Text: ",", Pos: start}, nil
	case '=':
		l.advance()
		return Token{Kind: Equal, Text: "=", Pos: start}, nil
	case '"':
		return l.lexString(start)
	}

	if isBareRune(r) || (r == '$' && l.peek(1) == '{') {
		return l.lexBare(start)
	}

	l.advance()
	return Token{Kind: EOF, Pos: start}, &diag.Diagnostic{
		File: l.file, Line: start.Line, Col: start.Col, Code: codeIllegalChar,
		Message: fmt.Sprintf("非法字符 %q", string(r)),
		Hint:    "合法字符：字母、数字、`-` `.` `_` `:` `/` `\\` `*` `?` `${}` 与标点 `{ } = [ ] ( ) ,`",
	}
}

func (l *lexer) lexString(start Pos) (Token, *diag.Diagnostic) {
	l.advance() // 开引号
	var b strings.Builder
	for {
		if l.atEnd() || l.peek(0) == '\n' {
			return Token{Kind: Str, Pos: start}, &diag.Diagnostic{
				File: l.file, Line: start.Line, Col: start.Col, Code: codeUntermString,
				Message: "字符串未闭合", Hint: "字符串不得跨行",
			}
		}
		r := l.advance()
		if r == '"' {
			return Token{Kind: Str, Text: b.String(), Pos: start}, nil
		}
		if r == '\\' {
			if l.atEnd() {
				return Token{Kind: Str, Pos: start}, &diag.Diagnostic{
					File: l.file, Line: start.Line, Col: start.Col, Code: codeUntermString,
					Message: "字符串未闭合",
				}
			}
			e := l.advance()
			switch e {
			case '"':
				b.WriteRune('"')
			case '\\':
				b.WriteRune('\\')
			default:
				p := Pos{Line: l.line, Col: l.col - 1}
				return Token{Kind: Str, Pos: start}, &diag.Diagnostic{
					File: l.file, Line: p.Line, Col: p.Col, Code: codeBadEscape,
					Message: fmt.Sprintf("非法转义 %q", "\\"+string(e)),
					Hint:    `只允许 \" 与 \\`,
				}
			}
			continue
		}
		b.WriteRune(r)
	}
}

func (l *lexer) lexBare(start Pos) (Token, *diag.Diagnostic) {
	var b strings.Builder
	for !l.atEnd() {
		r := l.peek(0)
		if r == '$' && l.peek(1) == '{' {
			l.advance()
			l.advance()
			b.WriteString("${")
			closed := false
			for !l.atEnd() {
				c := l.advance()
				if c == '}' {
					b.WriteRune('}')
					closed = true
					break
				}
				b.WriteRune(c)
			}
			if !closed {
				return Token{Kind: Bare, Text: b.String(), Pos: start}, &diag.Diagnostic{
					File: l.file, Line: start.Line, Col: start.Col, Code: codeUntermVar,
					Message: "变量未闭合", Hint: "写法为 ${name}",
				}
			}
			continue
		}
		if !isBareRune(r) {
			break
		}
		b.WriteRune(l.advance())
	}
	text := b.String()
	kind := Bare
	if isIdentText(text) {
		kind = Ident
	}
	return Token{Kind: kind, Text: text, Pos: start}, nil
}
