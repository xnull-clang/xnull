// Package xpd 实现 XPD 文法的词法与文法分析（S9 附录 C）。
package xpd

// Kind 是词法单元类别。
type Kind int

const (
	EOF Kind = iota
	Newline
	Ident
	Bare
	Str
	LBrace
	RBrace
	LBrack
	RBrack
	LParen
	RParen
	Comma
	Equal
)

func (k Kind) String() string {
	switch k {
	case EOF:
		return "文件结束"
	case Newline:
		return "换行"
	case Ident:
		return "标识符"
	case Bare:
		return "裸词"
	case Str:
		return "字符串"
	case LBrace:
		return "`{`"
	case RBrace:
		return "`}`"
	case LBrack:
		return "`[`"
	case RBrack:
		return "`]`"
	case LParen:
		return "`(`"
	case RParen:
		return "`)`"
	case Comma:
		return "`,`"
	case Equal:
		return "`=`"
	}
	return "未知"
}

// Pos 是源位置（1 基）。
type Pos struct {
	Line int
	Col  int
}

// Token 是一个词法单元；Text 对字符串保存已解转义的正文。
type Token struct {
	Kind Kind
	Text string
	Pos  Pos
}
