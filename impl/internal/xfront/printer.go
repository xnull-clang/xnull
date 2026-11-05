package xfront

import (
	"fmt"
	"strconv"
	"strings"
)

// PrintExpr 把表达式打印为 S 表达式（--emit ast 形态；诊断与结构断言共用）。
func PrintExpr(e Expr) string {
	var b strings.Builder
	writeExpr(&b, e)
	return b.String()
}

func writeExpr(b *strings.Builder, e Expr) {
	switch n := e.(type) {
	case *IdentExpr:
		fmt.Fprintf(b, "(ident %s)", n.Name)
	case *IntLitExpr:
		fmt.Fprintf(b, "(int %s)", n.Text)
	case *FloatLitExpr:
		fmt.Fprintf(b, "(float %s)", n.Text)
	case *CharLitExpr:
		fmt.Fprintf(b, "(char %q)", string(n.Rune))
	case *BoolLit:
		fmt.Fprintf(b, "(bool %v)", n.V)
	case *NullLit:
		b.WriteString("(null)")
	case *StrLitExpr:
		b.WriteString("(string")
		for _, part := range n.Parts {
			if part.Expr != nil {
				b.WriteByte(' ')
				writeExpr(b, part.Expr)
			} else {
				fmt.Fprintf(b, " %q", part.Text)
			}
		}
		b.WriteString(")")
	case *Paren:
		b.WriteString("(paren ")
		writeExpr(b, n.X)
		b.WriteString(")")
	case *Tuple:
		writeList(b, "tuple", n.Elems)
	case *ArrayLit:
		writeList(b, "array", n.Elems)
	case *MapLit:
		b.WriteString("(map")
		for i := range n.Keys {
			b.WriteString(" (")
			writeExpr(b, n.Keys[i])
			b.WriteByte(':')
			writeExpr(b, n.Vals[i])
			b.WriteByte(')')
		}
		b.WriteString(")")
	case *Unary:
		fmt.Fprintf(b, "(unary %s ", n.Op)
		writeExpr(b, n.X)
		b.WriteString(")")
	case *Binary:
		fmt.Fprintf(b, "(binary %s ", n.Op)
		writeExpr(b, n.L)
		b.WriteByte(' ')
		if ta, ok := n.R.(*TypeAsExpr); ok {
			writeTypeAs(b, n.Op, ta)
		} else {
			writeExpr(b, n.R)
		}
		b.WriteString(")")
	case *Ternary:
		b.WriteString("(ternary ")
		writeExpr(b, n.Cond)
		b.WriteByte(' ')
		writeExpr(b, n.Then)
		b.WriteByte(' ')
		writeExpr(b, n.Else)
		b.WriteString(")")
	case *Member:
		fmt.Fprintf(b, "(%s ", memberOp(n.NullSafe))
		writeExpr(b, n.X)
		fmt.Fprintf(b, " %s)", n.Name)
	case *TupleMember:
		if n.NullSafe {
			b.WriteString("(opttuplemember ")
		} else {
			b.WriteString("(tuplemember ")
		}
		writeExpr(b, n.X)
		fmt.Fprintf(b, " %d)", n.Index)
	case *Call:
		b.WriteString("(call ")
		writeExpr(b, n.Callee)
		if len(n.TypeArgs) > 0 {
			b.WriteString(" <")
			for i, ta := range n.TypeArgs {
				if i > 0 {
					b.WriteString(", ")
				}
				writeType(b, ta)
			}
			b.WriteString(">")
		}
		for _, a := range n.Args {
			b.WriteByte(' ')
			writeExpr(b, a)
		}
		b.WriteString(")")
	case *Index:
		b.WriteString("(index ")
		writeExpr(b, n.X)
		b.WriteByte(' ')
		writeExpr(b, n.Idx)
		b.WriteString(")")
	case *New:
		b.WriteString("(new ")
		writeType(b, n.Type)
		for _, a := range n.Args {
			b.WriteByte(' ')
			writeExpr(b, a)
		}
		b.WriteString(")")
	case *NewArray:
		b.WriteString("(newarray ")
		writeType(b, n.Type)
		b.WriteByte(' ')
		writeExpr(b, n.Count)
		b.WriteString(")")
	case *Lambda:
		b.WriteString("(lambda")
		for _, p := range n.Params {
			if p.Final {
				b.WriteString(" (final ")
				writeType(b, p.Type)
				fmt.Fprintf(b, " %s)", p.Name)
			} else {
				b.WriteString(" (")
				writeType(b, p.Type)
				fmt.Fprintf(b, " %s)", p.Name)
			}
		}
		b.WriteString(" ->")
		if n.Single {
			b.WriteByte(' ')
			writeExpr(b, n.ExprB)
		} else {
			b.WriteString(" (block")
			for _, s := range n.Block.Stmts {
				b.WriteByte(' ')
				writeStmt(b, s)
			}
			b.WriteString(")")
		}
		b.WriteString(")")
	default:
		fmt.Fprintf(b, "(unknown %T)", e)
	}
}

func memberOp(nullSafe bool) string {
	if nullSafe {
		return "optmember"
	}
	return "member"
}

func writeTypeAs(b *strings.Builder, op string, ta *TypeAsExpr) {
	if ta.Is {
		fmt.Fprintf(b, "(is ")
	} else if ta.NullSafe {
		fmt.Fprintf(b, "(as? ")
	} else {
		fmt.Fprintf(b, "(as ")
	}
	writeType(b, ta.Type)
	b.WriteString(")")
	_ = op
}

func writeList(b *strings.Builder, name string, elems []Expr) {
	b.WriteString("(" + name)
	for _, el := range elems {
		b.WriteByte(' ')
		writeExpr(b, el)
	}
	b.WriteString(")")
}

func writeStmt(b *strings.Builder, s Stmt) {
	switch n := s.(type) {
	case *ReturnStmt:
		if n.Value == nil {
			b.WriteString("(return)")
			return
		}
		b.WriteString("(return ")
		writeExpr(b, n.Value)
		b.WriteString(")")
	case *ExprStmt:
		b.WriteString("(expr ")
		writeExpr(b, n.X)
		b.WriteString(")")
	case *LocalDeclStmt:
		switch {
		case n.Var:
			fmt.Fprintf(b, "(decl var %s ", n.Name)
			writeExpr(b, n.Init)
		case n.Const:
			b.WriteString("(decl const ")
			writeType(b, n.Type)
			fmt.Fprintf(b, " %s", n.Name)
			writeOptExpr(b, n.Init)
		case n.Final:
			b.WriteString("(decl final ")
			writeType(b, n.Type)
			fmt.Fprintf(b, " %s", n.Name)
			writeOptExpr(b, n.Init)
		default:
			b.WriteString("(decl ")
			writeType(b, n.Type)
			fmt.Fprintf(b, " %s", n.Name)
			writeOptExpr(b, n.Init)
		}
		b.WriteString(")")
	case *AssignStmt:
		fmt.Fprintf(b, "(assign %s ", n.Op)
		writeExpr(b, n.Target)
		b.WriteByte(' ')
		writeExpr(b, n.Value)
		b.WriteString(")")
	case *IncDecStmt:
		if n.Prefix {
			b.WriteString("(incdec pre ")
		} else {
			b.WriteString("(incdec ")
		}
		fmt.Fprintf(b, "%s ", n.Op)
		writeExpr(b, n.Target)
		b.WriteString(")")
	case *IfStmt:
		b.WriteString("(if ")
		writeExpr(b, n.Cond)
		b.WriteByte(' ')
		writeBlock(b, n.Then)
		if n.Else != nil {
			b.WriteString(" (else ")
			writeStmt(b, n.Else)
			b.WriteString(")")
		}
		b.WriteString(")")
	case *WhileStmt:
		b.WriteString("(while ")
		writeExpr(b, n.Cond)
		b.WriteByte(' ')
		writeBlock(b, n.Body)
		b.WriteString(")")
	case *DoWhileStmt:
		b.WriteString("(dowhile ")
		writeBlock(b, n.Body)
		b.WriteByte(' ')
		writeExpr(b, n.Cond)
		b.WriteString(")")
	case *ForStmt:
		fmt.Fprintf(b, "(for %s in ", n.Var)
		writeExpr(b, n.Src)
		b.WriteByte(' ')
		writeBlock(b, n.Body)
		b.WriteString(")")
	case *SwitchStmt:
		b.WriteString("(switch ")
		writeExpr(b, n.Value)
		for _, c := range n.Cases {
			b.WriteString(" (case ")
			writeExpr(b, c.Expr)
			writeStmts(b, c.Stmts)
			b.WriteString(")")
		}
		if n.Default != nil {
			b.WriteString(" (default")
			writeStmts(b, n.Default.Stmts)
			b.WriteString(")")
		}
		b.WriteString(")")
	case *DeferStmt:
		if n.Errdefer {
			b.WriteString("(errdefer ")
		} else {
			b.WriteString("(defer ")
		}
		if n.Block != nil {
			writeBlock(b, n.Block)
		} else {
			writeStmt(b, n.Stmt)
		}
		b.WriteString(")")
	case *BreakStmt:
		writeJump(b, "break", n.Label)
	case *ContinueStmt:
		writeJump(b, "continue", n.Label)
	case *GotoStmt:
		fmt.Fprintf(b, "(goto %s)", n.Label)
	case *LabeledStmt:
		fmt.Fprintf(b, "(label %s ", n.Label)
		writeStmt(b, n.Stmt)
		b.WriteString(")")
	case *ThrowStmt:
		b.WriteString("(throw ")
		writeExpr(b, n.Value)
		b.WriteString(")")
	case *EmptyStmt:
		b.WriteString("(empty)")
	case *Block:
		writeBlock(b, n)
	default:
		fmt.Fprintf(b, "(unknown-stmt %T)", s)
	}
}

func writeJump(b *strings.Builder, kw, label string) {
	if label == "" {
		b.WriteString("(" + kw + ")")
		return
	}
	fmt.Fprintf(b, "(%s %s)", kw, label)
}

func writeOptExpr(b *strings.Builder, e Expr) {
	if e != nil {
		b.WriteByte(' ')
		writeExpr(b, e)
	}
}

func writeBlock(b *strings.Builder, bl *Block) {
	b.WriteString("(block")
	writeStmts(b, bl.Stmts)
	b.WriteString(")")
}

func writeStmts(b *strings.Builder, stmts []Stmt) {
	for _, st := range stmts {
		b.WriteByte(' ')
		writeStmt(b, st)
	}
}

// PrintType 把类型引用打印为 S1 附录 A 的书写形式。
func PrintType(t TypeRef) string {
	var b strings.Builder
	writeType(&b, t)
	return b.String()
}

func writeType(b *strings.Builder, t TypeRef) {
	switch n := t.(type) {
	case *NamedType:
		b.WriteString(strings.Join(n.Qual, "."))
		if len(n.Args) > 0 {
			b.WriteString("<")
			for i, a := range n.Args {
				if i > 0 {
					b.WriteString(", ")
				}
				writeType(b, a)
			}
			b.WriteString(">")
		}
	case *SuffixedType:
		writeType(b, n.Base)
		for _, s := range n.Suffixes {
			b.WriteString(s)
		}
	case *FuncTypeRef:
		writeType(b, n.Ret)
		b.WriteString("(")
		for i, p := range n.Params {
			if i > 0 {
				b.WriteString(", ")
			}
			writeType(b, p)
		}
		b.WriteString(")")
	case *TupleTypeRef:
		b.WriteString("(")
		for i, e := range n.Elems {
			if i > 0 {
				b.WriteString(", ")
			}
			writeType(b, e)
		}
		b.WriteString(")")
	default:
		fmt.Fprintf(b, "<unknown %T>", t)
	}
}

// 帮助函数：整数下标转十进制文本（元组访问打印）。
func itoa(i int) string { return strconv.Itoa(i) }
