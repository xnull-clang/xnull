package xpd

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/diag"
)

const (
	codeUnexpected  = "XPD-101" // 语法位置不符 / 多余 `}`
	codeNeedEqOrBlk = "XPD-102" // 名称之后既不是 `=` 也不是 `{`
	codeNeedValue   = "XPD-103" // 缺值
	codeUntermBlock = "XPD-104" // 块未闭合
	codeRangeArity  = "XPD-105" // 范围端点个数不为 2
	codeOneLine     = "XPD-106" // 列表/范围不得跨行
	codeTerminator  = "XPD-107" // 条目未以换行或 `}` 收尾
)

type parser struct {
	file  string
	lines []string
	lex   *lexer
	tok   Token
	errs  []diag.Diagnostic
}

// Parse 解析一个 XPD 文件；语法错误不中断解析，返回已收集的全部诊断。
func Parse(file, src string) (*File, []diag.Diagnostic) {
	p := &parser{file: file, lines: strings.Split(src, "\n"), lex: newLexer(file, src)}
	p.advance()
	f := &File{Path: file}

	for {
		p.skipNewlines()
		if p.tok.Kind == EOF {
			return f, p.errs
		}
		if p.tok.Kind == RBrace {
			p.errorAt(p.tok.Pos, codeUnexpected, "多余的 `}`", 1, "根层不允许闭合括号")
			p.advance()
			continue
		}
		if node := p.parseNode(); node != nil {
			f.Items = append(f.Items, node)
		}
	}
}

func (p *parser) advance() {
	t, d := p.lex.Next()
	for d != nil {
		p.errs = append(p.errs, *d)
		t, d = p.lex.Next()
	}
	p.tok = t
}

func (p *parser) skipNewlines() {
	for p.tok.Kind == Newline {
		p.advance()
	}
}

func (p *parser) snippet(pos Pos) string {
	if pos.Line-1 >= 0 && pos.Line-1 < len(p.lines) {
		return strings.TrimRight(p.lines[pos.Line-1], "\r")
	}
	return ""
}

func (p *parser) errorAt(pos Pos, code, msg string, width int, hint string) {
	p.errs = append(p.errs, diag.Diagnostic{
		File: p.file, Line: pos.Line, Col: pos.Col, Code: code,
		Message: msg, Snippet: p.snippet(pos), Width: width, Hint: hint,
	})
}

// parseNode 解析一个条目：字段、带体块或无体条目（叶子）。
func (p *parser) parseNode() Node {
	if p.tok.Kind != Ident && p.tok.Kind != Bare {
		p.errorAt(p.tok.Pos, codeUnexpected, fmt.Sprintf("此处应为名称，实际为%s", p.tok.Kind), 1, "")
		p.advance()
		return nil
	}
	name := p.tok.Text
	pos := p.tok.Pos
	p.advance()

	if p.tok.Kind == Equal {
		p.advance()
		v, ok := p.parseValue()
		if !ok {
			return nil
		}
		if p.tok.Kind != Newline && p.tok.Kind != RBrace && p.tok.Kind != EOF {
			p.errorAt(p.tok.Pos, codeTerminator,
				fmt.Sprintf("字段后应为换行或 `}`，实际为%s", p.tok.Kind), 1, "")
			p.skipToLineEnd()
		}
		return &Field{Name: name, Value: v, Pos: pos}
	}

	blk := &Block{Name: name, Pos: pos, Leaf: true}
	for p.tok.Kind == Str || p.tok.Kind == Bare || p.tok.Kind == Ident ||
		p.tok.Kind == LBrack || p.tok.Kind == LParen {
		v, ok := p.parseValue()
		if !ok {
			return nil
		}
		blk.Args = append(blk.Args, v)
	}

	if p.tok.Kind == Newline || p.tok.Kind == EOF || p.tok.Kind == RBrace {
		p.skipNewlines()
		if p.tok.Kind != LBrace {
			return blk // 无体条目：`module platform`、`exclusion org.old:legacy`
		}
	} else if p.tok.Kind != LBrace {
		p.errorAt(p.tok.Pos, codeNeedEqOrBlk,
			fmt.Sprintf("%q 之后应为 `=`、`{` 或换行，实际为%s", name, p.tok.Kind), 1,
			"字段写作 `名称 = 值`；块写作 `名称 { }`；叶子条目写作 `名称 参数`")
		p.skipToLineEnd()
		return nil
	}

	blk.Leaf = false
	p.advance() // 消费 `{`

	for {
		p.skipNewlines()
		if p.tok.Kind == RBrace || p.tok.Kind == EOF {
			break
		}
		if child := p.parseNode(); child != nil {
			blk.Children = append(blk.Children, child)
		}
	}

	if p.tok.Kind == EOF {
		p.errorAt(pos, codeUntermBlock, fmt.Sprintf("块 %q 未闭合", name), len([]rune(name)), "补上 `}`")
		return blk
	}
	p.advance() // 消费 `}`
	return blk
}

func (p *parser) skipToLineEnd() {
	for p.tok.Kind != Newline && p.tok.Kind != EOF && p.tok.Kind != RBrace {
		p.advance()
	}
}

func (p *parser) parseValue() (Value, bool) {
	switch p.tok.Kind {
	case Str:
		v := Value{Kind: StringValue, Text: p.tok.Text, Pos: p.tok.Pos}
		p.advance()
		return v, true
	case Bare, Ident:
		v := Value{Kind: BareValue, Text: p.tok.Text, Pos: p.tok.Pos}
		p.advance()
		return v, true
	case LBrack:
		return p.parseBracketList()
	case LParen:
		return p.parseRange()
	}
	p.errorAt(p.tok.Pos, codeNeedValue, fmt.Sprintf("缺少值，实际为%s", p.tok.Kind), 1, "")
	return Value{}, false
}

// parseBracketList 解析 `[ ... ]`；以 `)` 收尾且恰有两个端点时视为范围。
func (p *parser) parseBracketList() (Value, bool) {
	start := p.tok.Pos
	p.advance()
	v := Value{Kind: ListValue, Pos: start}

	if p.tok.Kind == RBrack {
		p.advance()
		return v, true
	}

	for {
		if p.tok.Kind == Newline {
			p.errorAt(p.tok.Pos, codeOneLine, "列表不得跨行", 1, "")
			return Value{}, false
		}
		e, ok := p.parseValue()
		if !ok {
			return Value{}, false
		}
		v.Elems = append(v.Elems, e)

		switch p.tok.Kind {
		case Comma:
			p.advance()
		case RBrack:
			p.advance()
			return v, true
		case RParen:
			if len(v.Elems) != 2 {
				p.errorAt(p.tok.Pos, codeRangeArity,
					fmt.Sprintf("范围必须有两个端点，实际 %d 个", len(v.Elems)), 1, "写作 `[3.3, 4.0)`")
				return Value{}, false
			}
			p.advance()
			v.Kind = RangeValue
			v.LoIncl, v.HiIncl = true, false
			return v, true
		case Newline:
			p.errorAt(p.tok.Pos, codeOneLine, "列表不得跨行", 1, "")
			return Value{}, false
		default:
			p.errorAt(p.tok.Pos, codeUnexpected,
				fmt.Sprintf("列表内应为 `,` `]` 或 `)`，实际为%s", p.tok.Kind), 1, "")
			return Value{}, false
		}
	}
}

func (p *parser) parseRange() (Value, bool) {
	start := p.tok.Pos
	p.advance()
	v := Value{Kind: RangeValue, Pos: start, LoIncl: false}

	for i := 0; i < 2; i++ {
		e, ok := p.parseValue()
		if !ok {
			return Value{}, false
		}
		v.Elems = append(v.Elems, e)
		if i == 0 {
			if p.tok.Kind != Comma {
				p.errorAt(p.tok.Pos, codeUnexpected, "范围两端之间应为 `,`", 1, "写作 `(3.3, 4.0]`")
				return Value{}, false
			}
			p.advance()
		}
	}

	switch p.tok.Kind {
	case RParen, RBrack:
		v.HiIncl = p.tok.Kind == RBrack
		p.advance()
		return v, true
	}
	p.errorAt(p.tok.Pos, codeUnexpected, "范围应以 `]` 或 `)` 收尾", 1, "")
	return Value{}, false
}
