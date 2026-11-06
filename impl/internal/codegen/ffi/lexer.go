package ffi

import "strings"

// tokKind 是 .xfb 方言的词法类别。
type tokKind int

const (
	tokEOF tokKind = iota
	tokIdent
	tokNumber
	tokString
	tokPunct
)

// token 是一个词法单元。
type token struct {
	kind tokKind
	text string
	pos  pos
}

// lexer 是 .xfb 的最小词法分析器（不复用语言词法，避免与文法耦合）。
type lexer struct {
	file  string
	src   []rune
	i     int
	line  int
	col   int
	toks  []token
	diags []Diagnostic
}

func newLexer(src, file string) *lexer {
	return &lexer{file: file, src: []rune(src), line: 1, col: 1}
}

func (l *lexer) atEOF() bool { return l.i >= len(l.src) }

func (l *lexer) peek() rune {
	if l.atEOF() {
		return 0
	}
	return l.src[l.i]
}

func (l *lexer) peekAt(n int) rune {
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

func (l *lexer) errf(p pos, msg string) {
	l.diags = append(l.diags, Diagnostic{
		File: l.file, Line: p.Line, Col: p.Col, Code: "FFI-100", Message: msg,
	})
}

func isIdentStart(r rune) bool {
	return r == '_' || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')
}

func isIdentPart(r rune) bool {
	return isIdentStart(r) || (r >= '0' && r <= '9')
}

func isDigit(r rune) bool { return r >= '0' && r <= '9' }

func (l *lexer) run() []token {
	for !l.atEOF() {
		r := l.peek()
		start := pos{l.line, l.col}
		switch {
		case r == ' ' || r == '\t' || r == '\r' || r == '\n':
			l.advance()
		case r == '/' && l.peekAt(1) == '/':
			for !l.atEOF() && l.peek() != '\n' {
				l.advance()
			}
		case r == '/' && l.peekAt(1) == '*':
			l.advance()
			l.advance()
			closed := false
			for !l.atEOF() {
				if l.peek() == '*' && l.peekAt(1) == '/' {
					l.advance()
					l.advance()
					closed = true
					break
				}
				l.advance()
			}
			if !closed {
				l.errf(start, "块注释未闭合")
			}
		case isIdentStart(r):
			var b strings.Builder
			for !l.atEOF() && isIdentPart(l.peek()) {
				b.WriteRune(l.advance())
			}
			l.toks = append(l.toks, token{tokIdent, b.String(), start})
		case isDigit(r):
			var b strings.Builder
			for !l.atEOF() && isDigit(l.peek()) {
				b.WriteRune(l.advance())
			}
			l.toks = append(l.toks, token{tokNumber, b.String(), start})
		case r == '"':
			l.advance()
			var b strings.Builder
			closed := false
			for !l.atEOF() {
				c := l.advance()
				if c == '"' {
					closed = true
					break
				}
				if c == '\\' && !l.atEOF() {
					e := l.advance()
					switch e {
					case 'n':
						b.WriteRune('\n')
					case 't':
						b.WriteRune('\t')
					default:
						b.WriteRune(e)
					}
					continue
				}
				b.WriteRune(c)
			}
			if !closed {
				l.errf(start, "字符串未闭合")
			}
			l.toks = append(l.toks, token{tokString, b.String(), start})
		case strings.ContainsRune("{}()[],;=@.?:*", r):
			l.advance()
			l.toks = append(l.toks, token{tokPunct, string(r), start})
		default:
			l.advance()
			l.errf(start, "非法字符 "+string(r))
		}
	}
	l.toks = append(l.toks, token{tokEOF, "", pos{l.line, l.col}})
	return l.toks
}
