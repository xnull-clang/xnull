// Package xfront 实现 XNull 语言前端（S1 §1：词法）。
//
// 词法诊断码采用 LEX-1xx 段位（实现侧编号；S1 §1.7 只规定"必须报错并带
// 文件/行/列范围"，未固定码值，故码值归实现并在本包内保持稳定）。
package xfront

// Kind 是词法单元类别。
type Kind int

const (
	EOF Kind = iota
	Semi
	Ident
	Keyword
	Annotation // @name
	IntLit
	FloatLit
	CharLit
	StrLit
	Op
	LParen
	RParen
	LBrace
	RBrace
	LBrack
	RBrack
	Comma
)

func (k Kind) String() string {
	switch k {
	case EOF:
		return "文件结束"
	case Semi:
		return "`;`"
	case Ident:
		return "标识符"
	case Keyword:
		return "关键字"
	case Annotation:
		return "注解"
	case IntLit:
		return "整数字面量"
	case FloatLit:
		return "浮点字面量"
	case CharLit:
		return "字符字面量"
	case StrLit:
		return "字符串字面量"
	case Op:
		return "运算符"
	case LParen:
		return "`(`"
	case RParen:
		return "`)`"
	case LBrace:
		return "`{`"
	case RBrace:
		return "`}`"
	case LBrack:
		return "`[`"
	case RBrack:
		return "`]`"
	case Comma:
		return "`,`"
	}
	return "未知"
}

// Pos 是源位置（1 基，列按 Unicode 标量计数，S1 §1.1）。
type Pos struct {
	Line int
	Col  int
}

// StrKind 是字符串的五种形态（S1 §1.4.4）。
type StrKind int

const (
	StrNormal StrKind = iota
	StrRaw
	StrMultiline
	StrRawMultiline
	StrInterp
)

// Token 是一个词法单元。
type Token struct {
	Kind Kind
	Text string // Ident/Keyword/Op/Annotation 的原文；字面量的源文本
	Pos  Pos

	// 字符串
	Str     StrKind
	Value   string   // 解码后内容（普通/原始/多行）；插值串为拼接后的静态文本
	Segs    []string // 插值串的静态段，与 Interps 交错：len(Segs) == len(Interps)+1
	Interps []string // 插值表达式原文（StrInterp 时按源码顺序）

	// 字符
	Char rune

	// 整数
	Base   int    // 10 / 16 / 2 / 8
	Suffix string // "" / "L" / "U" / "UL"（规范形）
	// 浮点
	HasSuffixF bool
}

var keywords = map[string]struct{}{
	"package": {}, "import": {}, "as": {},
	"public": {}, "protected": {}, "private": {}, "final": {}, "static": {},
	"const": {}, "var": {}, "abstract": {},
	"class": {}, "struct": {}, "protocol": {}, "enum": {}, "singleton": {},
	"factory": {}, "extension": {}, "implements": {}, "new": {}, "self": {},
	"super": {}, "out": {}, "in": {},
	"if": {}, "else": {}, "while": {}, "do": {}, "for": {}, "switch": {},
	"case": {}, "default": {}, "break": {}, "continue": {}, "return": {},
	"throw": {}, "try": {}, "goto": {}, "defer": {}, "errdefer": {},
	"is": {},
}

// Reserved 是保留给未来版本与未支持能力的名称（S1 §1.3）；
// 词法按标识符返回，由语义层拒绝（词法不知道出现位置是否为声明名）。
var Reserved = map[string]struct{}{
	"async": {}, "await": {}, "yield": {}, "unsafe": {}, "extern": {}, "macro": {},
}

// operators 按长度降序做最长匹配（S1 §1.5）。
var operators = []string{
	"<<=", ">>=", "...", "..<", "===", "!==", "==", "!=", "<=", ">=", "<<", ">>",
	"&&", "||", "??", "?.", "->", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
	"++", "--",
	"+", "-", "*", "/", "%", "=", "<", ">", "!", "?", ":", "&", "|", "^", "~",
	".", ",", ";", "@",
	"(", ")", "{", "}", "[", "]",
}
