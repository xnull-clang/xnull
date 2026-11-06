package xfront

import (
	"fmt"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/diag"
)

// 语法诊断码（实现侧 SYN-1xx 段位，本包内稳定；S1 §1.7 的行列要求适用于全部诊断）。
const (
	synExpect       = "SYN-101" // 期望某 token 却遇到其他
	synChainCompare = "SYN-102" // 比较运算不可链式（S1 §7.2）
	synChainRange   = "SYN-103" // 范围运算不可链式（S1 §7.2）
	synTupleArity   = "SYN-104" // 元组字面量/类型至少两个元素
	synNewForm      = "SYN-105" // new 后必须是 ( 或 [
	synTrailing     = "SYN-106" // 表达式结束后存在未消费的输入
	synRangeContext = "SYN-107" // 范围只允许出现在 for-in 源位置（此约束语义层执行，解析不报）
	synStmtTerm     = "SYN-108" // 同一行缺分号（S1 §1.6、STMT-01）
	synAssignTarget = "SYN-109" // 赋值/自增目标不在 Assignable 集（附录 A）
	synTypeDecl     = "SYN-110" // 类型声明属第 2 部分（S2 切片实现）
	synXdkPackage   = "SYN-111" // 用户包名使用保留命名空间 xdk（§3.1）
)

// ParseExpr 解析一个完整表达式（S1 附录 A：Expression）。
// 输入为源文本；先词法后语法，返回表达式与全部诊断（词法 + 语法，不中断）。
func ParseExpr(file, src string) (Expr, []diag.Diagnostic) {
	toks, diags := Lex(file, src)
	p := &parser{file: file, toks: toks, errs: diags}
	e := p.parseExpr()
	p.expectKind(EOF, "表达式结束")
	return e, p.errs
}

// ParseStmts 解析语句序列（等价于块体内部；4d 的 CompilationUnit 复用同一套解析器）。
func ParseStmts(file, src string) ([]Stmt, []diag.Diagnostic) {
	toks, diags := Lex(file, src)
	p := &parser{file: file, toks: toks, errs: diags}
	var out []Stmt
	for !p.at(EOF) {
		out = append(out, p.parseStmt())
		p.endStatement()
	}
	return out, p.errs
}

// PrintStmt 把语句打印为 S 表达式。
func PrintStmt(s Stmt) string {
	var b strings.Builder
	writeStmt(&b, s)
	return b.String()
}

type parser struct {
	file     string
	toks     []Token
	i        int
	errs     []diag.Diagnostic
	lastLine int // 最近消费 token 的行号（语句终止检查用）
}

func (p *parser) cur() Token {
	if p.i >= len(p.toks) {
		return p.toks[len(p.toks)-1] // EOF
	}
	return p.toks[p.i]
}

func (p *parser) next() Token {
	t := p.cur()
	if p.i < len(p.toks)-1 {
		p.i++
	}
	p.lastLine = t.Pos.Line
	return t
}

func (p *parser) at(kind Kind) bool { return p.cur().Kind == kind }

func (p *parser) atOp(op string) bool {
	return p.cur().Kind == Op && p.cur().Text == op
}

func (p *parser) atKw(word string) bool {
	return p.cur().Kind == Keyword && p.cur().Text == word
}

func (p *parser) err(pos Pos, code, msg, hint string) {
	p.errs = append(p.errs, diag.Diagnostic{File: p.file, Line: pos.Line, Col: pos.Col, Code: code, Message: msg, Hint: hint})
}

// expectKind 消费期望类别的 token；否则报错并返回占位 token（不推进）。
func (p *parser) expectKind(kind Kind, what string) Token {
	if p.at(kind) {
		return p.next()
	}
	t := p.cur()
	p.err(t.Pos, synExpect, fmt.Sprintf("期望%s，遇到 %s", what, describe(t)), "")
	return t
}

// expectOp 按文本消费期望的 token（覆盖运算符、括号、逗号、分号——
// 词法把 `;` 归 Semi、`,` 归 Comma、括号归独立类别，S1 §1.5）。
func (p *parser) expectOp(op string) bool {
	if p.atOp(op) || punctKind[op] == p.cur().Kind && punctKind[op] != Op {
		p.i++
		return true
	}
	t := p.cur()
	p.err(t.Pos, synExpect, fmt.Sprintf("期望 `%s`，遇到 %s", op, describe(t)), "")
	return false
}

var punctKind = map[string]Kind{
	"(": LParen, ")": RParen, "{": LBrace, "}": RBrace,
	"[": LBrack, "]": RBrack, ",": Comma, ";": Semi,
}

func describe(t Token) string {
	switch t.Kind {
	case EOF:
		return "文件结束"
	case Ident, Keyword, Op:
		return "`" + t.Text + "`"
	case IntLit, FloatLit, CharLit, StrLit:
		return t.Kind.String()
	default:
		return t.Kind.String()
	}
}

// ---------- 文法链（与附录 A 逐行对应） ----------

// Expression = TernaryExpr ;
func (p *parser) parseExpr() Expr { return p.parseTernary() }

// TernaryExpr = CoalesceExpr [ "?" Expression ":" Expression ] ;
// 三元右结合：分支走完整 Expression。
func (p *parser) parseTernary() Expr {
	cond := p.parseCoalesce()
	if p.atOp("?") {
		pos := p.next().Pos
		then := p.parseExpr()
		p.expectOp(":")
		els := p.parseExpr()
		return &Ternary{P: pos, Cond: cond, Then: then, Else: els}
	}
	return cond
}

// CoalesceExpr = LogicalOrExpr [ "??" CoalesceExpr ] ; 右结合（S1 §7.2）。
func (p *parser) parseCoalesce() Expr {
	l := p.parseLogicalOr()
	if p.atOp("??") {
		pos := p.next().Pos
		r := p.parseCoalesce()
		return &Binary{P: pos, Op: "??", L: l, R: r}
	}
	return l
}

// LogicalOrExpr = LogicalAndExpr { "||" LogicalAndExpr } ;
func (p *parser) parseLogicalOr() Expr {
	l := p.parseLogicalAnd()
	for p.atOp("||") {
		pos := p.next().Pos
		l = &Binary{P: pos, Op: "||", L: l, R: p.parseLogicalAnd()}
	}
	return l
}

// LogicalAndExpr = BitOrExpr { "&&" BitOrExpr } ;
func (p *parser) parseLogicalAnd() Expr {
	l := p.parseBitOr()
	for p.atOp("&&") {
		pos := p.next().Pos
		l = &Binary{P: pos, Op: "&&", L: l, R: p.parseBitOr()}
	}
	return l
}

// BitOrExpr = BitXorExpr { "|" BitXorExpr } ;
func (p *parser) parseBitOr() Expr {
	l := p.parseBitXor()
	for p.atOp("|") {
		pos := p.next().Pos
		l = &Binary{P: pos, Op: "|", L: l, R: p.parseBitXor()}
	}
	return l
}

// BitXorExpr = BitAndExpr { "^" BitAndExpr } ;
func (p *parser) parseBitXor() Expr {
	l := p.parseBitAnd()
	for p.atOp("^") {
		pos := p.next().Pos
		l = &Binary{P: pos, Op: "^", L: l, R: p.parseBitAnd()}
	}
	return l
}

// BitAndExpr = EqualityExpr { "&" EqualityExpr } ;
func (p *parser) parseBitAnd() Expr {
	l := p.parseEquality()
	for p.atOp("&") {
		pos := p.next().Pos
		l = &Binary{P: pos, Op: "&", L: l, R: p.parseEquality()}
	}
	return l
}

// EqualityExpr = ComparisonExpr { ( "==" | "!=" | "===" | "!==" ) ComparisonExpr } ;
func (p *parser) parseEquality() Expr {
	l := p.parseComparison()
	for p.cur().Kind == Op && (p.cur().Text == "==" || p.cur().Text == "!=" ||
		p.cur().Text == "===" || p.cur().Text == "!==") {
		op := p.next()
		l = &Binary{P: op.Pos, Op: op.Text, L: l, R: p.parseComparison()}
	}
	return l
}

// ComparisonExpr = RangeExpr [ ( "<" | "<=" | ">" | ">=" ) RangeExpr
//
//	| ( "is" | "as" | "as?" ) TypeRef ] ;
//
// 每层至多一次比较/类型运算 → 链式使用必然语法错误（S1 §7.2）。
func (p *parser) parseComparison() Expr {
	l := p.parseRange()
	switch {
	case p.atOp("<") || p.atOp("<=") || p.atOp(">") || p.atOp(">="):
		op := p.next()
		r := p.parseRange()
		if p.atOp("<") || p.atOp("<=") || p.atOp(">") || p.atOp(">=") {
			p.err(p.cur().Pos, synChainCompare, "比较运算不可链式使用", "必须显式加括号并写出意图，如 (a < b) && (b < c)")
			return &Binary{P: op.Pos, Op: op.Text, L: l, R: r}
		}
		return &Binary{P: op.Pos, Op: op.Text, L: l, R: r}
	case p.atKw("is") || p.atKw("as"):
		op := p.next()
		t := p.parseTypeRef()
		return &Binary{P: op.Pos, Op: op.Text, L: l, R: &TypeAsExpr{Type: t, Is: op.Text == "is"}}
	case p.atOp("as?"):
		op := p.next()
		t := p.parseTypeRef()
		return &Binary{P: op.Pos, Op: "as?", L: l, R: &TypeAsExpr{Type: t, Is: false, NullSafe: true}}
	}
	return l
}

// TypeAsExpr 承载 is / as / as? 的类型右操作数（S1 §7.6：右操作数必须是类型）。
type TypeAsExpr struct {
	P        Pos
	Type     TypeRef
	Is       bool
	NullSafe bool
}

func (n *TypeAsExpr) Pos() Pos { return n.P }
func (*TypeAsExpr) exprNode()  {}

// RangeExpr = ShiftExpr [ ( "..<" | "..." ) ShiftExpr ] ;
// 至多一次 → 链式是语法错误；"只允许出现在 for-in 源位置"由语义层拒绝
// （附录 A 文法说明最后一条：文法接受、语义拒绝）。
func (p *parser) parseRange() Expr {
	l := p.parseShift()
	if p.atOp("..<") || p.atOp("...") {
		op := p.next()
		r := p.parseShift()
		if p.atOp("..<") || p.atOp("...") {
			p.err(p.cur().Pos, synChainRange, "范围运算不可链式使用", "")
			return &Binary{P: op.Pos, Op: op.Text, L: l, R: r}
		}
		return &Binary{P: op.Pos, Op: op.Text, L: l, R: r}
	}
	return l
}

// ShiftExpr = AdditiveExpr { ( "<<" | ">>" ) AdditiveExpr } ;
func (p *parser) parseShift() Expr {
	l := p.parseAdditive()
	for p.atOp("<<") || p.atOp(">>") {
		op := p.next()
		l = &Binary{P: op.Pos, Op: op.Text, L: l, R: p.parseAdditive()}
	}
	return l
}

// AdditiveExpr = MultiplicativeExpr { ( "+" | "-" ) MultiplicativeExpr } ;
func (p *parser) parseAdditive() Expr {
	l := p.parseMultiplicative()
	for p.atOp("+") || p.atOp("-") {
		op := p.next()
		l = &Binary{P: op.Pos, Op: op.Text, L: l, R: p.parseMultiplicative()}
	}
	return l
}

// MultiplicativeExpr = UnaryExpr { ( "*" | "/" | "%" ) UnaryExpr } ;
func (p *parser) parseMultiplicative() Expr {
	l := p.parseUnary()
	for p.atOp("*") || p.atOp("/") || p.atOp("%") {
		op := p.next()
		l = &Binary{P: op.Pos, Op: op.Text, L: l, R: p.parseUnary()}
	}
	return l
}

// UnaryExpr = ( "!" | "-" | "+" | "~" | "try" ) UnaryExpr | PostfixExpr ;
// 前缀右结合。
func (p *parser) parseUnary() Expr {
	t := p.cur()
	if t.Kind == Op && (t.Text == "!" || t.Text == "-" || t.Text == "+" || t.Text == "~") {
		p.i++
		return &Unary{P: t.Pos, Op: t.Text, X: p.parseUnary()}
	}
	if t.Kind == Keyword && t.Text == "try" {
		p.i++
		return &Unary{P: t.Pos, Op: "try", X: p.parseUnary()}
	}
	return p.parsePostfix()
}

// PostfixExpr = PrimaryExpr { PostfixSuffix } ;
// PostfixSuffix = "." Ident | "." IntegerLiteral | "?." Ident | "?." IntegerLiteral
//
//	| [ "<" TypeArgList ">" ] "(" [ ArgList ] ")" | "[" Expression "]" ;
func (p *parser) parsePostfix() Expr {
	x := p.parsePrimary()
	for {
		switch {
		case p.atOp(".") || p.atOp("?."):
			nullSafe := p.cur().Text == "?."
			dot := p.next()
			switch {
			case p.at(Ident):
				x = &Member{P: dot.Pos, X: x, Name: p.next().Text, NullSafe: nullSafe}
			case p.at(IntLit):
				lit := p.next()
				idx, err := strconv.ParseInt(lit.Text, lit.Base, 64)
				if err != nil || idx < 0 {
					p.err(lit.Pos, synExpect, "元组元素下标必须是非负十进制整数字面量", "")
					idx = 0
				}
				x = &TupleMember{P: dot.Pos, X: x, Index: int(idx), NullSafe: nullSafe}
			default:
				p.err(p.cur().Pos, synExpect, "`.` 后必须是成员名或元组下标", "")
				return x
			}
		case p.atOp("<"):
			if ta, ok := p.tryTypeArgs(); ok {
				if p.expectOp("(") {
					x = p.finishCall(x, ta)
				} else {
					return x
				}
			} else {
				return x // `<` 交给外层比较层
			}
		case p.at(LParen):
			p.next()
			x = p.finishCall(x, nil)
		case p.at(LBrack):
			p.next()
			idx := p.parseExpr()
			p.expectOp("]")
			x = &Index{P: x.Pos(), X: x, Idx: idx}
		default:
			return x
		}
	}
}

func (p *parser) finishCall(callee Expr, typeArgs []TypeRef) Expr {
	var args []Expr
	if !p.at(RParen) {
		for {
			args = append(args, p.parseExpr())
			if !p.at(Comma) {
				break
			}
			p.i++
		}
	}
	p.expectKind(RParen, "`)`")
	return &Call{P: callee.Pos(), Callee: callee, TypeArgs: typeArgs, Args: args}
}

// tryTypeArgs 尝试 `< TypeArgList >` 且其后紧跟 `(`（附录 A 文法说明第一条）；
// 失败时回退 token 与误报的诊断，`<` 留给比较层。
func (p *parser) tryTypeArgs() ([]TypeRef, bool) {
	save := p.i
	errLen := len(p.errs)
	p.i++ // "<"
	var args []TypeRef
	for {
		if p.at(EOF) || p.at(RParen) || p.at(RBrack) {
			p.i, p.errs = save, p.errs[:errLen]
			return nil, false
		}
		args = append(args, p.parseTypeRef())
		if p.at(Comma) {
			p.i++
			continue
		}
		break
	}
	if !p.atOp(">") || !p.toks[min(p.i+1, len(p.toks)-1)].at(LParen) {
		p.i, p.errs = save, p.errs[:errLen]
		return nil, false
	}
	p.i++ // ">"
	return args, true
}

func (t Token) at(k Kind) bool { return t.Kind == k }

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// ---------- 主表达式 ----------

// PrimaryExpr = Literal | Identifier | "self" | "super"
//
//	| "(" Expression ")" | TupleLiteral | ArrayLiteral | MapLiteral
//	| NewExpr | LambdaExpr | InterpolatedString ;
func (p *parser) parsePrimary() Expr {
	t := p.cur()
	switch t.Kind {
	case IntLit:
		p.i++
		return &IntLitExpr{P: t.Pos, Text: t.Text, Base: t.Base, Suffix: t.Suffix}
	case FloatLit:
		p.i++
		return &FloatLitExpr{P: t.Pos, Text: t.Text, HasSuffixF: t.HasSuffixF}
	case CharLit:
		p.i++
		return &CharLitExpr{P: t.Pos, Rune: t.Char}
	case StrLit:
		p.i++
		return p.finishString(t)
	case Ident:
		// true/false/null 是字面量常量（S1 §1.3），词法按 Ident 返回。
		switch t.Text {
		case "true", "false":
			p.i++
			return &BoolLit{P: t.Pos, V: t.Text == "true"}
		case "null":
			p.i++
			return &NullLit{P: t.Pos}
		}
		p.i++
		return &IdentExpr{P: t.Pos, Name: t.Text}
	case Keyword:
		switch t.Text {
		case "self", "super":
			p.i++
			return &IdentExpr{P: t.Pos, Name: t.Text}
		case "new":
			return p.parseNew()
		}
	case LParen:
		return p.parseParenOrTupleOrLambda()
	case LBrack:
		return p.parseArrayOrMap()
	}
	p.err(t.Pos, synExpect, "期望表达式，遇到 "+describe(t), "")
	if t.Kind != EOF {
		p.i++ // 前进避免死循环
	}
	return &IdentExpr{P: t.Pos, Name: "<err>"}
}

// finishString 解析插值串的各部分（S1 §1.4.4、§7.8）：
// 词法已把插值表达式原文按序存入 Token.Interps，这里对每段做子解析。
func (p *parser) finishString(t Token) Expr {
	s := &StrLitExpr{P: t.Pos, Kind: t.Str}
	if t.Str != StrInterp {
		s.Parts = append(s.Parts, StrPart{Text: t.Value})
		return s
	}
	// Segs 与 Interps 交错：len(Segs) == len(Interps)+1（词法按插值边界切分）。
	segs := t.Segs
	for i, raw := range t.Interps {
		if i < len(segs) && segs[i] != "" {
			s.Parts = append(s.Parts, StrPart{Text: segs[i]})
		}
		s.Parts = append(s.Parts, StrPart{Expr: p.parseInterpText(t.Pos, raw)})
	}
	if len(segs) > len(t.Interps) && segs[len(t.Interps)] != "" {
		s.Parts = append(s.Parts, StrPart{Text: segs[len(t.Interps)]})
	}
	return s
}

// parseInterpText 对插值片段做词法 + 表达式解析。
// 片段的列号从 1 起算（相对片段自身），诊断仍指向宿主文件。
func (p *parser) parseInterpText(host Pos, text string) Expr {
	sub, diags := ParseExpr(p.file, text)
	for i := range diags {
		diags[i].Hint = strings.TrimSpace(diags[i].Hint + "（插值表达式）")
		_ = host
	}
	p.errs = append(p.errs, diags...)
	return sub
}

// parseNewType 解析 new 的类型：命名类型（含泛型）+ `[]`/`?` 后缀；
// 不做函数类型探测——`new Type(` 的 `(` 是构造实参表（S1 §7.1）。
func (p *parser) parseNewType() TypeRef {
	base := p.parseNamedType()
	var suffixes []string
	for {
		if p.at(LBrack) && p.toks[min(p.i+1, len(p.toks)-1)].at(RBrack) {
			p.i += 2
			suffixes = append(suffixes, "[]")
			continue
		}
		if p.atOp("?") {
			p.i++
			suffixes = append(suffixes, "?")
			continue
		}
		break
	}
	if suffixes == nil {
		return base
	}
	return &SuffixedType{P: base.Pos(), Base: base, Suffixes: suffixes}
}

// parseNew = "new" TypeRef "(" [ArgList] ")" | "new" TypeRef "[" Expression "]" ;
func (p *parser) parseNew() Expr {
	pos := p.next().Pos // new
	ty := p.parseNewType()
	switch {
	case p.at(LParen):
		p.next()
		var args []Expr
		if !p.at(RParen) {
			for {
				args = append(args, p.parseExpr())
				if !p.at(Comma) {
					break
				}
				p.i++
			}
		}
		p.expectKind(RParen, "`)`")
		return &New{P: pos, Type: ty, Args: args}
	case p.at(LBrack):
		p.next()
		count := p.parseExpr()
		p.expectOp("]")
		return &NewArray{P: pos, Type: ty, Count: count}
	}
	t := p.cur()
	p.err(t.Pos, synNewForm, "`new` 后必须是 `(`（构造）或 `[`（定长数组）", "遇到 "+describe(t))
	return &New{P: pos, Type: ty}
}

// parseParenOrTupleOrLambda 区分三种 `(` 开头形态（附录 A 文法说明第 10 条）：
//   - 括号表达式 `(e)`
//   - 元组字面量 `(e1, e2, ...)`（至少两元素）
//   - 闭包 `(参数列表) -> 体`
func (p *parser) parseParenOrTupleOrLambda() Expr {
	open := p.next() // "("

	// 先尝试 lambda：`(` [LambdaParam {"," LambdaParam}] ")" "->"。
	if lam, ok := p.tryLambda(open); ok {
		return lam
	}

	// `()` 且无 `->`：空元组不合法。
	if p.at(RParen) {
		p.err(open.Pos, synTupleArity, "元组字面量至少需要两个元素", "单元素括号 `(e)` 是括号表达式")
		p.i++
		return &Tuple{P: open.Pos}
	}

	first := p.parseExpr()
	if p.at(Comma) {
		elems := []Expr{first}
		for p.at(Comma) {
			p.i++
			elems = append(elems, p.parseExpr())
		}
		p.expectKind(RParen, "`)`")
		return &Tuple{P: open.Pos, Elems: elems}
	}
	p.expectKind(RParen, "`)`")
	return &Paren{P: open.Pos, X: first}
}

// tryLambda 带回溯地解析闭包参数表；失败回退全部状态。
func (p *parser) tryLambda(open Token) (*Lambda, bool) {
	save, errLen := p.i, len(p.errs)
	var params []LambdaParam

	if p.at(RParen) { // 零参数 `()`
		p.i++
	} else {
		for {
			if p.at(EOF) || p.at(RParen) {
				p.rollback(save, errLen)
				return nil, false
			}
			var lp LambdaParam
			lp.P = p.cur().Pos
			if p.atKw("final") {
				lp.Final = true
				p.i++
			}
			lp.Type = p.parseTypeRef()
			if !p.at(Ident) {
				p.rollback(save, errLen)
				return nil, false
			}
			lp.Name = p.next().Text
			params = append(params, lp)
			if p.at(Comma) {
				p.i++
				continue
			}
			break
		}
		if !p.expectKind(RParen, "`)`").at(RParen) && params == nil {
			p.rollback(save, errLen)
			return nil, false
		}
	}
	if !p.atOp("->") {
		p.rollback(save, errLen)
		return nil, false
	}
	arrow := p.next()
	lam := &Lambda{P: open.Pos, Params: params}
	if p.at(LBrace) {
		lam.Block = p.parseBlock()
	} else {
		lam.Single = true
		lam.ExprB = p.parseExpr()
	}
	_ = arrow
	return lam, true
}

func (p *parser) rollback(i, errLen int) {
	p.i, p.errs = i, p.errs[:errLen]
}

// parseBlock 解析 `{ { Statement } }`（附录 A Block）。
// 独立 `{}` 不是语句——本函数只在体位置被调用（S1 §6.2、文法说明第 5 条）。
func (p *parser) parseBlock() *Block {
	open := p.expectKind(LBrace, "`{`")
	b := &Block{P: open.Pos}
	for !p.at(RBrace) && !p.at(EOF) {
		b.Stmts = append(b.Stmts, p.parseStmt())
		p.endStatement()
	}
	p.expectKind(RBrace, "`}`")
	return b
}

// endStatement 执行语句终止检查（S1 §1.6、STMT-01：换行或 `;` 终止；
// 同一行缺分号被拒绝）。`;` 可选显式（附录 A `[ ";" ]`）。
func (p *parser) endStatement() {
	if p.at(Semi) {
		p.i++
		return
	}
	if p.at(RBrace) || p.at(EOF) {
		return
	}
	if p.atKw("case") || p.atKw("default") { // switch 子句标签不是语句
		return
	}
	// 同一行还有后续 token → 缺终止符。
	if p.cur().Pos.Line == p.lastLine {
		p.err(p.cur().Pos, synStmtTerm, "语句未终止（同一行的下一条语句前缺少 `;`）", "")
		// 恢复：跳到行尾或终止符
		for !p.at(EOF) && !p.at(Semi) && p.cur().Pos.Line == p.lastLine {
			p.i++
		}
		if p.at(Semi) {
			p.i++
		}
	}
}

var assignOps = map[string]bool{
	"=": true, "+=": true, "-=": true, "*=": true, "/=": true, "%=": true,
	"&=": true, "|=": true, "^=": true, "<<=": true, ">>=": true,
}

// parseStmt 按附录 A Statement 全集分派。
func (p *parser) parseStmt() Stmt {
	t := p.cur()
	switch {
	case p.at(Semi): // EmptyStatement
		p.i++
		return &EmptyStmt{P: t.Pos}
	case t.Kind == Keyword:
		switch t.Text {
		case "if":
			return p.parseIf()
		case "while":
			p.i++
			cond := p.parseExpr()
			return &WhileStmt{P: t.Pos, Cond: cond, Body: p.parseBlock()}
		case "do":
			p.i++
			body := p.parseBlock()
			if !p.atKw("while") {
				p.err(p.cur().Pos, synExpect, "do 体之后期望 `while`", "")
				return &DoWhileStmt{P: t.Pos, Body: body, Cond: &IdentExpr{P: t.Pos, Name: "<err>"}}
			}
			p.i++
			cond := p.parseExpr()
			return &DoWhileStmt{P: t.Pos, Body: body, Cond: cond}
		case "for":
			return p.parseFor()
		case "switch":
			return p.parseSwitch()
		case "defer", "errdefer":
			p.i++
			d := &DeferStmt{P: t.Pos, Errdefer: t.Text == "errdefer"}
			if p.at(LBrace) {
				d.Block = p.parseBlock()
			} else {
				d.Stmt = p.parseStmt() // Body = Block | Statement
			}
			return d
		case "break", "continue":
			p.i++
			if t.Text == "continue" {
				c := &ContinueStmt{P: t.Pos}
				if p.at(Ident) {
					c.Label = p.next().Text
				}
				return c
			}
			b := &BreakStmt{P: t.Pos}
			if p.at(Ident) {
				b.Label = p.next().Text
			}
			return b
		case "return":
			p.i++
			if p.at(EOF) || p.at(RBrace) || p.at(Semi) {
				return &ReturnStmt{P: t.Pos}
			}
			v := p.parseExpr()
			return &ReturnStmt{P: t.Pos, Value: v}
		case "throw":
			p.i++
			v := p.parseExpr()
			return &ThrowStmt{P: t.Pos, Value: v}
		case "goto":
			p.i++
			lb := p.expectKind(Ident, "标签名")
			return &GotoStmt{P: t.Pos, Label: lb.Text}
		case "var", "final", "const":
			return p.parseLocalDecl()
		}
	case t.Kind == Op && (t.Text == "++" || t.Text == "--"): // 前缀自增/自减
		p.i++
		target := p.parseExpr()
		p.checkAssignable(target, t.Text)
		return &IncDecStmt{P: t.Pos, Target: target, Op: t.Text, Prefix: true}
	case t.Kind == LParen:
		// `(T1, T2) name = ...` 元组类型声明尝试（§2.11；失败按表达式处理）。
		if s, ok := p.tryTupleTypeDecl(); ok {
			return s
		}
	case t.Kind == Ident:
		// `name:` → 标签语句（标签与变量不同命名空间，S1 §6.10）。
		if p.toks[min(p.i+1, len(p.toks)-1)].Kind == Op && p.toks[min(p.i+1, len(p.toks)-1)].Text == ":" {
			p.i += 2
			return &LabeledStmt{P: t.Pos, Label: t.Text, Stmt: p.parseStmt()}
		}
		// `Type name` 开头 → 局部声明尝试（回溯，失败按表达式处理）。
		if s, ok := p.tryLocalDecl(); ok {
			return s
		}
	}
	// 表达式语句 / 赋值 / 后缀自增自减（附录 A：三者同以表达式开头）。
	x := p.parseExpr()
	switch {
	case p.atOp("++") || p.atOp("--"):
		op := p.next().Text
		p.checkAssignable(x, op)
		return &IncDecStmt{P: x.Pos(), Target: x, Op: op}
	case p.cur().Kind == Op && assignOps[p.cur().Text]:
		op := p.next().Text
		p.checkAssignable(x, op)
		v := p.parseExpr()
		return &AssignStmt{P: x.Pos(), Target: x, Op: op, Value: v}
	}
	return &ExprStmt{P: t.Pos, X: x}
}

// checkAssignable 校验赋值/自增目标属于 Assignable（Identifier | MemberExpr | IndexExpr）。
// 可空链目标（`?.`）不在 Assignable 集内（附录 A），语法即拒绝。
func (p *parser) checkAssignable(x Expr, op string) {
	bad := false
	switch n := x.(type) {
	case *IdentExpr:
	case *Member:
		bad = n.NullSafe // `?.` 目标不在 Assignable 集（附录 A MemberExpr 无 ?.)
	case *Index:
	case *TupleMember: // 可赋值元组的元素（S1 §6.4；越界/不可赋值由语义层判定）
	default:
		bad = true
	}
	if bad {
		p.err(x.Pos(), synAssignTarget, "`"+op+"` 的目标必须可赋值（标识符、成员或下标）", "")
	}
}

// tryLocalDecl 回溯尝试 `Type Identifier` 声明头；失败回退 token 与误报。
func (p *parser) tryLocalDecl() (Stmt, bool) {
	save, errLen := p.i, len(p.errs)
	if s, ok := p.tryTupleTypeDecl(); ok {
		return s, true
	}
	p.rollback(save, errLen)
	s := p.parseLocalDeclHead()
	if s != nil {
		return s, true
	}
	p.rollback(save, errLen)
	return nil, false
}

// tryTupleTypeDecl 静默尝试元组类型声明形态（§2.11）：`(T1, T2) name = ...`。
// 与表达式 `(a, b)` 的区分：类型位置后必须紧跟声明名与 `=`。
func (p *parser) tryTupleTypeDecl() (Stmt, bool) {
	if !p.at(LParen) {
		return nil, false
	}
	save, errLen := p.i, len(p.errs)
	p.i++ // (
	var elems []TypeRef
	for {
		ty := p.tryTypeRefQuietNoName()
		if ty == nil {
			p.rollback(save, errLen)
			return nil, false
		}
		elems = append(elems, ty)
		if p.at(Comma) {
			p.i++
			continue
		}
		break
	}
	if len(elems) < 2 || !p.at(RParen) {
		p.rollback(save, errLen)
		return nil, false
	}
	p.i++ // )
	if !p.at(Ident) {
		p.rollback(save, errLen)
		return nil, false
	}
	name := p.next().Text
	if !p.atOp("=") {
		p.rollback(save, errLen)
		return nil, false
	}
	p.i++
	s := &LocalDeclStmt{P: save2pos(p, save), Type: &TupleTypeRef{P: p.cur().Pos, Elems: elems}, Name: name}
	s.Init = p.parseExpr()
	return s, true
}

// tryTypeRefQuietNoName 静默解析一个类型（不要求后跟声明名）。
func (p *parser) tryTypeRefQuietNoName() TypeRef {
	save, errLen := p.i, len(p.errs)
	ty := p.parseTypeRef()
	if len(p.errs) > errLen {
		p.rollback(save, errLen)
		return nil
	}
	return ty
}

func save2pos(p *parser, save int) Pos {
	if save < len(p.toks) {
		return p.toks[save].Pos
	}
	return Pos{}
}

// parseLocalDeclHead 解析声明头与可选初始化；形态不符返回 nil。
func (p *parser) parseLocalDeclHead() Stmt {
	t := p.cur()
	s := &LocalDeclStmt{P: t.Pos}
	if t.Text == "var" {
		p.i++
		s.Var = true
		if !p.at(Ident) {
			return nil
		}
		s.Name = p.next().Text
		if !p.atOp("=") {
			return nil // var 必须有初始化式（文法强制）
		}
		p.i++
		s.Init = p.parseExpr()
		return s
	}
	if t.Text == "final" || t.Text == "const" {
		p.i++
		s.Final, s.Const = t.Text == "final", t.Text == "const"
		if p.atKw("var") { // `final var`（S1 §5.1 推断形态）
			p.i++
			s.Var = true
			if !p.at(Ident) {
				return nil
			}
			s.Name = p.next().Text
			if !p.atOp("=") {
				return nil
			}
			p.i++
			s.Init = p.parseExpr()
			return s
		}
		s.Type = p.tryTypeRefQuiet()
		if s.Type == nil {
			return nil
		}
	} else {
		// 纯 `Type name` 形态：类型解析失败或后面不是名字 → 不是声明。
		ty := p.tryTypeRefQuiet()
		if ty == nil {
			return nil
		}
		s.Type = ty
	}
	if !p.at(Ident) {
		return nil
	}
	s.Name = p.next().Text
	if p.atOp("=") {
		p.i++
		s.Init = p.parseExpr()
	}
	return s
}

// tryTypeRefQuiet 静默尝试类型解析；失败回退返回 nil。
func (p *parser) tryTypeRefQuiet() TypeRef {
	save, errLen := p.i, len(p.errs)
	ty := p.parseTypeRef()
	if len(p.errs) > errLen {
		p.rollback(save, errLen)
		return nil
	}
	// 类型后必须紧跟声明名才是声明（否则如 `Int.valueOf` 属表达式）。
	if !p.at(Ident) {
		p.rollback(save, errLen)
		return nil
	}
	return ty
}

func (p *parser) parseLocalDecl() Stmt {
	s := p.parseLocalDeclHead()
	if s == nil {
		t := p.cur()
		p.err(t.Pos, synExpect, "期望局部声明", "")
		p.i++
		return &EmptyStmt{P: t.Pos}
	}
	return s
}

func (p *parser) parseIf() Stmt {
	t := p.next() // if
	cond := p.parseExpr()
	s := &IfStmt{P: t.Pos, Cond: cond, Then: p.parseBlock()}
	if p.atKw("else") {
		p.i++
		if p.atKw("if") { // else if 是嵌套 if 的语法糖（S1 §6.5）
			s.Else = p.parseIf()
		} else {
			s.Else = p.parseBlock()
		}
	}
	return s
}

func (p *parser) parseFor() Stmt {
	t := p.next() // for
	v := p.expectKind(Ident, "循环变量")
	if !p.atKw("in") {
		p.err(p.cur().Pos, synExpect, "期望 `in`", "")
	} else {
		p.i++
	}
	src := p.parseExpr()
	return &ForStmt{P: t.Pos, Var: v.Text, Src: src, Body: p.parseBlock()}
}

func (p *parser) parseSwitch() Stmt {
	t := p.next() // switch
	val := p.parseExpr()
	p.expectKind(LBrace, "`{`")
	s := &SwitchStmt{P: t.Pos, Value: val}
	for p.atKw("case") || p.atKw("default") {
		c := &SwitchCase{}
		if p.atKw("default") {
			p.i++
			c.Default = true
		} else {
			p.i++
			c.Expr = p.parseExpr()
		}
		p.expectOp(":")
		for !p.at(RBrace) && !p.at(EOF) && !p.atKw("case") && !p.atKw("default") {
			c.Stmts = append(c.Stmts, p.parseStmt())
			p.endStatement()
		}
		if c.Default {
			if s.Default != nil {
				p.err(t.Pos, synExpect, "default 子句最多一个", "")
			}
			s.Default = c
		} else {
			s.Cases = append(s.Cases, c)
		}
	}
	p.expectKind(RBrace, "`}`")
	return s
}

// parseArrayOrMap 区分 `[a, b]` / `["k": v, ...]` / `[:]`（S1 §7.1）。
func (p *parser) parseArrayOrMap() Expr {
	open := p.next() // "["
	if p.atOp(":") { // [:]
		p.i++
		p.expectKind(RBrack, "`]`")
		return &MapLit{P: open.Pos}
	}
	if p.at(RBrack) { // []：空数组字面量
		p.i++
		return &ArrayLit{P: open.Pos}
	}
	first := p.parseExpr()
	if p.atOp(":") { // Map
		p.i++
		m := &MapLit{P: open.Pos, Keys: []Expr{first}, Vals: []Expr{p.parseExpr()}}
		for p.at(Comma) {
			p.i++
			k := p.parseExpr()
			p.expectOp(":")
			m.Keys = append(m.Keys, k)
			m.Vals = append(m.Vals, p.parseExpr())
		}
		p.expectKind(RBrack, "`]`")
		return m
	}
	arr := &ArrayLit{P: open.Pos, Elems: []Expr{first}}
	for p.at(Comma) {
		p.i++
		arr.Elems = append(arr.Elems, p.parseExpr())
	}
	p.expectKind(RBrack, "`]`")
	return arr
}

// ---------- 类型引用 ----------

// TypeRef = PrimaryType { "[]" | "?" } ;
func (p *parser) parseTypeRef() TypeRef {
	base := p.parsePrimaryType()
	var suffixes []string
	for {
		if p.at(LBrack) && p.toks[min(p.i+1, len(p.toks)-1)].at(RBrack) {
			p.i += 2
			suffixes = append(suffixes, "[]")
			continue
		}
		if p.atOp("?") {
			p.i++
			suffixes = append(suffixes, "?")
			continue
		}
		break
	}
	if suffixes == nil {
		return base
	}
	return &SuffixedType{P: base.Pos(), Base: base, Suffixes: suffixes}
}

// PrimaryType = FunctionType | NamedType | TupleType ;
// FunctionType = ReturnType "(" [ TypeRef {"," TypeRef} ] ")" ——
// ReturnType 后紧跟 `(` 时按函数类型解析（附录 A 文法说明第二条）。
func (p *parser) parsePrimaryType() TypeRef {
	var ret TypeRef
	switch {
	case p.at(LParen): // 元组类型（作为 ReturnType 或独立元组类型）
		open := p.next()
		if !p.at(LParen) && !p.at(Ident) && !p.at(Keyword) {
			p.err(p.cur().Pos, synTupleArity, "元组类型至少需要两个元素", "")
			return &TupleTypeRef{P: open.Pos}
		}
		e1 := p.parseTypeRef()
		p.expectOp(",")
		elems := []TypeRef{e1, p.parseTypeRef()}
		for p.at(Comma) {
			p.i++
			elems = append(elems, p.parseTypeRef())
		}
		p.expectKind(RParen, "`)`")
		ret = &TupleTypeRef{P: open.Pos, Elems: elems}
	case p.at(Ident):
		ret = p.parseNamedType()
	case p.atKw("void"):
		t := p.next()
		ret = &NamedType{P: t.Pos, Qual: []string{"void"}}
	default:
		t := p.cur()
		p.err(t.Pos, synExpect, "期望类型，遇到 "+describe(t), "")
		p.i++
		return &NamedType{P: t.Pos, Qual: []string{"<err>"}}
	}
	if p.at(LParen) { // 函数类型：返回类型后紧跟 (
		p.next()
		var params []TypeRef
		if !p.at(RParen) {
			for {
				params = append(params, p.parseTypeRef())
				if !p.at(Comma) {
					break
				}
				p.i++
			}
		}
		p.expectKind(RParen, "`)`")
		return &FuncTypeRef{P: ret.Pos(), Ret: ret, Params: params}
	}
	return ret
}

// NamedType = QualifiedName [ "<" TypeArgList ">" ] ;
func (p *parser) parseNamedType() TypeRef {
	first := p.expectKind(Ident, "类型名")
	qual := []string{first.Text}
	for p.atOp(".") {
		p.i++
		qual = append(qual, p.expectKind(Ident, "类型名").Text)
	}
	nt := &NamedType{P: first.Pos, Qual: qual}
	if p.atOp("<") {
		p.i++
		for {
			if p.at(EOF) || p.at(RParen) || p.at(LParen) || p.at(RBrack) {
				p.err(p.cur().Pos, synExpect, "泛型实参列表未闭合", "期望类型或 `>`")
				return nt
			}
			nt.Args = append(nt.Args, p.parseTypeRef())
			if p.at(Comma) {
				p.i++
				continue
			}
			break
		}
		p.expectOp(">")
	}
	return nt
}
