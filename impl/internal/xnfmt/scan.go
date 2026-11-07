// Package xnfmt 实现 xnfmt 格式化规范 v1.0.0（B1-01 Go 版 oracle）。
//
// 处理模型：解码 → 词法（注释/字面量整体成 token）→ 行记录 → 头部区 → 正文 → 输出。
// 规范条款以 R3–R13 编号标注在实现处；token 文本逐字节保留，不折行、不合并行。
package xnfmt

import (
	"fmt"
	"strings"
)

// Diagnostic 是格式化诊断（FMT-1xx）。
type Diagnostic struct {
	File    string
	Line    int
	Col     int
	Code    string
	Message string
}

func (d Diagnostic) Error() string {
	file := d.File
	if file == "" {
		file = "<input>"
	}
	return fmt.Sprintf("%s:%d:%d: error[%s]: %s", file, d.Line, d.Col, d.Code, d.Message)
}

const (
	fmtLex   = "FMT-101" // 词法错误
	fmtEnc   = "FMT-102" // 编码错误
	fmtIO    = "FMT-103" // 读写/rename 失败
	fmtUsage = "FMT-104" // 参数错误
)

type tokKind int

const (
	tkIdent tokKind = iota
	tkKeyword
	tkNumber
	tkString
	tkChar
	tkComment
	tkPunct
)

type token struct {
	text    string
	kind    tokKind
	line    int // 1 基起始行
	endLine int // 最后一行（跨行注释/多行字面量 > line）
	col     int

	// 角色判定（§7/§8），在整文件 token 序列上预先计算。
	unaryPrefix  bool
	unaryPostfix bool
	nullableQ    bool
	ternaryQ     bool
	ternaryColon bool
	genericOpen  bool
	genericClose bool
}

func (t token) isComment() bool { return t.kind == tkComment }
func (t token) isKeyword(kw string) bool {
	return t.kind == tkKeyword && t.text == kw
}

// operators 与 xfront 词法一致（S1 §1.5；按长度降序做最长匹配）。
var operators = []string{
	"<<=", ">>=", "...", "..<", "===", "!==", "==", "!=", "<=", ">=", "<<", ">>",
	"&&", "||", "??", "?.", "->", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
	"++", "--",
	"+", "-", "*", "/", "%", "=", "<", ">", "!", "?", ":", "&", "|", "^", "~",
	".", ",", ";", "@",
	"(", ")", "{", "}", "[", "]",
}

var keywords = map[string]bool{
	"package": true, "import": true, "as": true,
	"public": true, "protected": true, "private": true, "final": true, "static": true,
	"const": true, "var": true, "abstract": true,
	"class": true, "struct": true, "protocol": true, "enum": true, "singleton": true,
	"factory": true, "extension": true, "implements": true, "new": true, "self": true,
	"super": true, "out": true, "in": true,
	"if": true, "else": true, "while": true, "do": true, "for": true, "switch": true,
	"case": true, "default": true, "break": true, "continue": true, "return": true,
	"throw": true, "try": true, "goto": true, "defer": true, "errdefer": true,
	"is": true, "true": true, "false": true, "null": true,
}

func isIdentStart(b byte) bool {
	return b == '_' || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')
}

func isIdentRune(b byte) bool { return isIdentStart(b) || (b >= '0' && b <= '9') }
func isDigit(b byte) bool     { return b >= '0' && b <= '9' }

// scan 把（已归一的）源文本切成 token：注释与字面量整体成 token（R10.6）。
func scan(file, src string) ([]token, []Diagnostic) {
	var toks []token
	var diags []Diagnostic
	line, col := 1, 1
	i := 0
	adv := func(n int) {
		for k := 0; k < n; k++ {
			if src[i+k] == '\n' {
				line++
				col = 1
			} else {
				col++
			}
		}
		i += n
	}
	for i < len(src) {
		b := src[i]
		switch {
		case b == '\n':
			adv(1)
			continue
		case b == ' ' || b == '\t' || b == '\r':
			adv(1)
			continue
		}
		startLine, startCol, start := line, col, i

		// 注释（R10）
		if b == '/' && i+1 < len(src) && src[i+1] == '/' {
			for i < len(src) && src[i] != '\n' {
				adv(1)
			}
			toks = append(toks, token{text: src[start:i], kind: tkComment, line: startLine, endLine: line, col: startCol})
			continue
		}
		if b == '/' && i+1 < len(src) && src[i+1] == '*' {
			closed := false
			adv(2)
			for i < len(src) {
				if src[i] == '*' && i+1 < len(src) && src[i+1] == '/' {
					adv(2)
					closed = true
					break
				}
				adv(1)
			}
			if !closed {
				diags = append(diags, Diagnostic{File: file, Line: startLine, Col: startCol, Code: fmtLex,
					Message: "块注释未闭合"})
			}
			toks = append(toks, token{text: src[start:i], kind: tkComment, line: startLine, endLine: line, col: startCol})
			continue
		}

		// 字符串（含多行/原始/插值前缀；整体成 token）
		if b == '"' || (b == 'r' && i+1 < len(src) && src[i+1] == '"') || (b == '$' && i+1 < len(src) && src[i+1] == '"') {
			end, ok := scanString(src, i)
			if !ok {
				diags = append(diags, Diagnostic{File: file, Line: startLine, Col: startCol, Code: fmtLex,
					Message: "字符串未闭合"})
			}
			adv(end - i)
			toks = append(toks, token{text: src[start:i], kind: tkString, line: startLine, endLine: line, col: startCol})
			continue
		}

		// 字符字面量
		if b == '\'' {
			end, ok := scanChar(src, i)
			if !ok {
				diags = append(diags, Diagnostic{File: file, Line: startLine, Col: startCol, Code: fmtLex,
					Message: "字符字面量未闭合"})
			}
			adv(end - i)
			toks = append(toks, token{text: src[start:i], kind: tkChar, line: startLine, endLine: line, col: startCol})
			continue
		}

		// 数字
		if isDigit(b) {
			end := scanNumber(src, i)
			adv(end - i)
			toks = append(toks, token{text: src[start:i], kind: tkNumber, line: startLine, endLine: line, col: startCol})
			continue
		}

		// 注解 @name
		if b == '@' && i+1 < len(src) && isIdentStart(src[i+1]) {
			j := i + 1
			for j < len(src) && isIdentRune(src[j]) {
				j++
			}
			adv(j - i)
			toks = append(toks, token{text: src[start:i], kind: tkPunct, line: startLine, endLine: line, col: startCol})
			continue
		}

		// 标识符 / 关键字 / as?
		if isIdentStart(b) {
			j := i
			for j < len(src) && isIdentRune(src[j]) {
				j++
			}
			word := src[i:j]
			if word == "as" && j < len(src) && src[j] == '?' {
				j++
				adv(j - i)
				toks = append(toks, token{text: src[start:j], kind: tkPunct, line: startLine, endLine: line, col: startCol})
				continue
			}
			adv(j - i)
			kind := tkIdent
			if keywords[word] {
				kind = tkKeyword
			}
			toks = append(toks, token{text: src[start:i], kind: kind, line: startLine, endLine: line, col: startCol})
			continue
		}

		// 运算符/标点：最长匹配
		matched := ""
		for _, op := range operators {
			if strings.HasPrefix(src[i:], op) {
				matched = op
				break
			}
		}
		if matched == "" {
			r := []rune(src[i:])
			ch := ""
			if len(r) > 0 {
				ch = string(r[0])
			}
			diags = append(diags, Diagnostic{File: file, Line: startLine, Col: startCol, Code: fmtLex,
				Message: fmt.Sprintf("无法识别的字符 %q", ch)})
			adv(len(ch))
			continue
		}
		adv(len(matched))
		toks = append(toks, token{text: src[start:i], kind: tkPunct, line: startLine, endLine: line, col: startCol})
	}
	return toks, diags
}

// scanString 返回字符串结束后的下标（不含）。
// 支持 "…"、"""…"""、r"…"、r"""…"""、$"…{expr}…"（插值内部按括号深度与嵌套字符串跳过）。
func scanString(src string, i int) (int, bool) {
	raw := false
	multiline := false
	interp := false
	switch {
	case src[i] == 'r' && strings.HasPrefix(src[i+1:], `"""`):
		raw, multiline = true, true
		i += 4
	case src[i] == 'r' && i+1 < len(src) && src[i+1] == '"':
		raw = true
		i += 2
	case src[i] == '$' && i+1 < len(src) && src[i+1] == '"':
		interp = true
		i += 2
	case strings.HasPrefix(src[i:], `"""`):
		multiline = true
		i += 3
	default:
		i++
	}
	if multiline {
		for i < len(src) {
			if strings.HasPrefix(src[i:], `"""`) {
				return i + 3, true
			}
			i++
		}
		return len(src), false
	}
	depth := 0
	for i < len(src) {
		c := src[i]
		if !raw && c == '\\' && i+1 < len(src) {
			i += 2
			continue
		}
		if c == '\n' {
			return i, false
		}
		if interp {
			switch c {
			case '{':
				depth++
			case '}':
				if depth > 0 {
					depth--
				}
			case '"':
				if depth > 0 {
					end, ok := scanString(src, i)
					if !ok {
						return end, false
					}
					i = end
					continue
				}
			}
		}
		if c == '"' && (!interp || depth == 0) {
			return i + 1, true
		}
		i++
	}
	return len(src), false
}

func scanChar(src string, i int) (int, bool) {
	i++ // 开引号
	for i < len(src) {
		c := src[i]
		if c == '\\' {
			i += 2
			continue
		}
		if c == '\n' {
			return i, false
		}
		if c == '\'' {
			return i + 1, true
		}
		i++
	}
	return len(src), false
}

// scanNumber 消费数字字面量；`1..<3` 的 `..` 不可被吞入（§R6.18）。
func scanNumber(src string, i int) int {
	j := i
	if j+1 < len(src) && src[j] == '0' {
		switch src[j+1] {
		case 'x', 'X', 'b', 'B', 'o', 'O':
			j += 2
			for j < len(src) && (isIdentRune(src[j])) {
				j++
			}
			return j
		}
	}
	for j < len(src) && (isDigit(src[j]) || src[j] == '_') {
		j++
	}
	if j < len(src) && src[j] == '.' && !(j+1 < len(src) && src[j+1] == '.') {
		j++
		for j < len(src) && (isDigit(src[j]) || src[j] == '_') {
			j++
		}
	}
	if j < len(src) && (src[j] == 'e' || src[j] == 'E') {
		k := j + 1
		if k < len(src) && (src[k] == '+' || src[k] == '-') {
			k++
		}
		if k < len(src) && isDigit(src[k]) {
			j = k
			for j < len(src) && (isDigit(src[j]) || src[j] == '_') {
				j++
			}
		}
	}
	// 后缀 F/L/U/UL
	for j < len(src) && (src[j] == 'F' || src[j] == 'L' || src[j] == 'U') {
		j++
	}
	return j
}
