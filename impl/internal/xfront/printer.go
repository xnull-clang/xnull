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

// PrintUnit 把编译单元打印为 S 表达式（--emit ast 用）。
func PrintUnit(u *CompilationUnit) string {
	var b strings.Builder
	b.WriteString("(unit")
	if u.Package != nil {
		fmt.Fprintf(&b, " (package %s)", strings.Join(u.Package.Name, "."))
	}
	for _, im := range u.Imports {
		fmt.Fprintf(&b, " (import %s", strings.Join(im.Path, "."))
		if im.Alias != "" {
			fmt.Fprintf(&b, " as %s", im.Alias)
		}
		b.WriteString(")")
	}
	for _, d := range u.Decls {
		b.WriteByte(' ')
		writeTopDecl(&b, d)
	}
	b.WriteString(")")
	return b.String()
}

func writeTopDecl(b *strings.Builder, d TopDecl) {
	switch n := d.(type) {
	case *PackageDecl:
		fmt.Fprintf(b, "(package %s)", strings.Join(n.Name, "."))
	case *ImportDecl:
		fmt.Fprintf(b, "(import %s", strings.Join(n.Path, "."))
		if n.Alias != "" {
			fmt.Fprintf(b, " as %s", n.Alias)
		}
		b.WriteString(")")
	case *TopFunc:
		b.WriteString("(func")
		writeMods(b, n.Public, n.Protected, n.Private, n.Static)
		writeAnnos(b, n.Annos)
		if n.Void {
			b.WriteString(" void")
		} else {
			b.WriteString(" ")
			writeType(b, n.Ret)
		}
		fmt.Fprintf(b, " %s", n.Name)
		for _, tp := range n.TypePars {
			fmt.Fprintf(b, " <%s>", tp)
		}
		b.WriteString(" (params")
		for _, pr := range n.Params {
			b.WriteString(" (param")
			writeAnnos(b, pr.Annos)
			if pr.Final {
				b.WriteString(" final")
			}
			b.WriteString(" ")
			writeType(b, pr.Type)
			fmt.Fprintf(b, " %s)", pr.Name)
		}
		b.WriteString(")")
		b.WriteByte(' ')
		writeBlock(b, n.Body)
		b.WriteString(")")
	case *TopField:
		b.WriteString("(field")
		writeMods(b, n.Public, n.Protected, n.Private, n.Static)
		writeAnnos(b, n.Annos)
		if n.Final {
			b.WriteString(" final")
		}
		if n.Const {
			b.WriteString(" const")
		}
		b.WriteString(" ")
		writeType(b, n.Type)
		fmt.Fprintf(b, " %s", n.Name)
		if n.Init != nil {
			b.WriteByte(' ')
			writeExpr(b, n.Init)
		}
		b.WriteString(")")
	case *ClassDecl:
		b.WriteString("(class")
		writeTypeMods(b, n.Mod)
		writeAnnos(b, n.Annos)
		fmt.Fprintf(b, " %s", n.Name)
		writeTypePars(b, n.TypePars)
		if n.Primary != nil {
			b.WriteString(" (primary ")
			writeParams(b, n.Primary.Params)
			b.WriteString(")")
		}
		if n.Base != nil {
			b.WriteString(" (: ")
			writeType(b, n.Base)
			b.WriteString(")")
		}
		if len(n.Protocols) > 0 {
			b.WriteString(" (implements")
			for _, p := range n.Protocols {
				b.WriteByte(' ')
				writeType(b, p)
			}
			b.WriteString(")")
		}
		writeMembers(b, n.Fields, n.Methods, n.Ctors)
		b.WriteString(")")
	case *StructDecl:
		b.WriteString("(struct")
		writeTypeMods(b, n.Mod)
		writeAnnos(b, n.Annos)
		fmt.Fprintf(b, " %s", n.Name)
		writeTypePars(b, n.TypePars)
		if n.Primary != nil {
			b.WriteString(" (primary ")
			writeParams(b, n.Primary.Params)
			b.WriteString(")")
		}
		writeMembers(b, n.Fields, n.Methods, n.Ctors)
		b.WriteString(")")
	case *ProtocolDecl:
		b.WriteString("(protocol")
		writeAnnos(b, n.Annos)
		fmt.Fprintf(b, " %s", n.Name)
		if len(n.Extends) > 0 {
			b.WriteString(" (:")
			for _, p := range n.Extends {
				b.WriteByte(' ')
				writeType(b, p)
			}
			b.WriteString(")")
		}
		for _, sg := range n.Sigs {
			b.WriteString(" (sig")
			writeTypeMods(b, sg.Mod)
			writeAnnos(b, sg.Annos)
			if sg.Void {
				b.WriteString(" void")
			} else {
				b.WriteString(" ")
				writeType(b, sg.Ret)
			}
			fmt.Fprintf(b, " %s ", sg.Name)
			writeParams(b, sg.Params)
			b.WriteString(")")
		}
		b.WriteString(")")
	case *EnumDecl:
		b.WriteString("(enum")
		writeTypeMods(b, n.Mod)
		writeAnnos(b, n.Annos)
		fmt.Fprintf(b, " %s", n.Name)
		for _, it := range n.Items {
			b.WriteString(" (item")
			writeAnnos(b, it.Annos)
			fmt.Fprintf(b, " %s", it.Name)
			if it.Value != nil {
				b.WriteString(" = ")
				writeExpr(b, it.Value)
			}
			if it.Args != nil {
				b.WriteString(" (args")
				for _, a := range it.Args {
					b.WriteByte(' ')
					writeExpr(b, a)
				}
				b.WriteString(")")
			}
			b.WriteString(")")
		}
		writeMembers(b, n.Fields, n.Methods, n.Ctors)
		b.WriteString(")")
	case *SingletonDecl:
		b.WriteString("(singleton")
		writeTypeMods(b, n.Mod)
		writeAnnos(b, n.Annos)
		fmt.Fprintf(b, " %s", n.Name)
		writeMembers(b, n.Fields, n.Methods, n.Ctors)
		b.WriteString(")")
	case *FactoryDecl:
		b.WriteString("(factory")
		writeTypeMods(b, n.Mod)
		writeAnnos(b, n.Annos)
		fmt.Fprintf(b, " %s (for ", n.Name)
		writeType(b, n.Target)
		b.WriteString(")")
		for _, m := range n.Methods {
			writeMethod(b, m)
		}
		b.WriteString(")")
	case *ExtensionDecl:
		b.WriteString("(extension")
		writeTypeMods(b, n.Mod)
		writeAnnos(b, n.Annos)
		b.WriteString(" ")
		writeType(b, n.Target)
		for _, m := range n.Methods {
			writeMethod(b, m)
		}
		b.WriteString(")")
	case *AnnotationDecl:
		b.WriteString("(annotation")
		writeTypeMods(b, n.Mod)
		writeAnnos(b, n.Annos)
		fmt.Fprintf(b, " %s", n.Name)
		for _, f := range n.Fields {
			writeField(b, f)
		}
		b.WriteString(")")
	}
}

// writeTypeMods 打印类型/成员修饰符（S2 §1.6）。
func writeTypeMods(b *strings.Builder, m TypeModifiers) {
	if m.Vis != "" {
		b.WriteString(" " + m.Vis)
	}
	if m.Abstract {
		b.WriteString(" abstract")
	}
	if m.Final {
		b.WriteString(" final")
	}
	if m.Static {
		b.WriteString(" static")
	}
	if m.Const {
		b.WriteString(" const")
	}
}

func writeTypePars(b *strings.Builder, pars []string) {
	if len(pars) == 0 {
		return
	}
	b.WriteString(" <")
	b.WriteString(strings.Join(pars, ", "))
	b.WriteString(">")
}

func writeMembers(b *strings.Builder, fields []*FieldDecl, methods []*MethodDecl, ctors []*CtorDecl) {
	for _, f := range fields {
		writeField(b, f)
	}
	for _, m := range methods {
		writeMethod(b, m)
	}
	for _, c := range ctors {
		b.WriteString(" (ctor")
		writeTypeMods(b, c.Mod)
		writeAnnos(b, c.Annos)
		b.WriteString(" ")
		writeParams(b, c.Params)
		b.WriteByte(' ')
		writeBlock(b, c.Body)
		b.WriteString(")")
	}
}

func writeField(b *strings.Builder, f *FieldDecl) {
	b.WriteString(" (field")
	writeTypeMods(b, f.Mod)
	writeAnnos(b, f.Annos)
	b.WriteString(" ")
	writeType(b, f.Type)
	fmt.Fprintf(b, " %s", f.Name)
	if f.Init != nil {
		b.WriteByte(' ')
		writeExpr(b, f.Init)
	}
	b.WriteString(")")
}

func writeMethod(b *strings.Builder, m *MethodDecl) {
	b.WriteString(" (method")
	writeTypeMods(b, m.Mod)
	writeAnnos(b, m.Annos)
	if m.Void {
		b.WriteString(" void")
	} else {
		b.WriteString(" ")
		writeType(b, m.Ret)
	}
	fmt.Fprintf(b, " %s", m.Name)
	writeTypePars(b, m.TypePars)
	b.WriteString(" ")
	writeParams(b, m.Params)
	b.WriteByte(' ')
	writeBlock(b, m.Body)
	b.WriteString(")")
}

func writeParams(b *strings.Builder, ps []*Param) {
	b.WriteString("(params")
	for _, p := range ps {
		b.WriteString(" (param")
		writeAnnos(b, p.Annos)
		if p.Final {
			b.WriteString(" final")
		}
		b.WriteString(" ")
		writeType(b, p.Type)
		fmt.Fprintf(b, " %s)", p.Name)
	}
	b.WriteString(")")
}

func writeMods(b *strings.Builder, pub, prot, priv, static bool) {
	if pub {
		b.WriteString(" public")
	}
	if prot {
		b.WriteString(" protected")
	}
	if priv {
		b.WriteString(" private")
	}
	if static {
		b.WriteString(" static")
	}
}

func writeAnnos(b *strings.Builder, annos []*AnnotationNode) {
	for _, a := range annos {
		fmt.Fprintf(b, " (@%s", a.Name)
		for _, arg := range a.Args {
			b.WriteByte(' ')
			writeExpr(b, arg)
		}
		b.WriteString(")")
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
