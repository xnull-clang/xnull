package xfront

import (
	"strings"

	"xnull.dev/xnull/internal/diag"
)

// ---------- 编译单元 AST（S1 §3—§4、附录 A CompilationUnit） ----------

// CompilationUnit = [ PackageDecl ] { ImportDecl } { TopLevelDecl } EOF ;
// 类型声明（class/struct/…）属第 2 部分，解析到即报 SYN-110（待 S2 切片实现）。
type CompilationUnit struct {
	P       Pos
	Package *PackageDecl // 可空：默认包（§3.1）
	Imports []*ImportDecl
	Decls   []TopDecl
}

// PackageDecl = "package" QualifiedName [ ";" ] ;
type PackageDecl struct {
	P    Pos
	Name []string // 点分段
}

// ImportDecl = "import" QualifiedName [ "as" Identifier ] [ ";" ] ;
// Alias 为空表示包导入或无消歧需求的符号导入（§3.2）。
type ImportDecl struct {
	P     Pos
	Path  []string
	Alias string
}

// Annotation = "@" Identifier [ "(" [ ArgList ] ")" ] ;（附录 A）
type AnnotationNode struct {
	P    Pos
	Name string
	Args []Expr // 可空
}

// Param = { Annotation } [ "final" ] Type Identifier ;（附录 A）
type Param struct {
	P     Pos
	Annos []*AnnotationNode
	Final bool
	Type  TypeRef
	Name  string
}

// TopDecl 是顶层声明统一接口。
type TopDecl interface {
	topDecl()
	Pos() Pos
}

// TopFunc = { Annotation } { TopLevelModifier } Type Identifier
//
//	[ GenericParams ] "(" [ ParamList ] ")" Block ;
//
// §4.1：顶层函数默认静态，`static` 可写可省略；必须有函数体。
type TopFunc struct {
	P         Pos
	Annos     []*AnnotationNode
	Public    bool
	Protected bool
	Private   bool
	Static    bool
	Void      bool // 返回类型为 void
	Ret       TypeRef
	Name      string
	TypePars  []string
	Params    []*Param
	Body      *Block
}

// TopField = { Annotation } { TopLevelModifier } [ "static" ] [ "final" | "const" ]
//
//	Type Identifier [ "=" Expression ] [ ";" ] ;
//
// §4.2：可变字段可省略初始化式（取零值）；final/const 必须初始化（语义层检查）。
type TopField struct {
	P         Pos
	Annos     []*AnnotationNode
	Public    bool
	Protected bool
	Private   bool
	Static    bool
	Final     bool
	Const     bool
	Type      TypeRef
	Name      string
	Init      Expr // 可空
}

func (*PackageDecl) topDecl() {}
func (*ImportDecl) topDecl()  {}
func (*TopFunc) topDecl()     {}
func (*TopField) topDecl()    {}

func (n *PackageDecl) Pos() Pos { return n.P }
func (n *ImportDecl) Pos() Pos  { return n.P }
func (n *TopFunc) Pos() Pos     { return n.P }
func (n *TopField) Pos() Pos    { return n.P }

// ---------- 解析 ----------

// ParseUnit 解析整个编译单元（4d 入口；词法 + 语法诊断全部返回，不中断）。
func ParseUnit(file, src string) (*CompilationUnit, []diag.Diagnostic) {
	toks, diags := Lex(file, src)
	toks = dropSemiInAnnotation(toks)
	p := &parser{file: file, toks: toks, errs: diags}
	u := &CompilationUnit{P: p.cur().Pos}
	if p.atKw("package") {
		u.Package = p.parsePackageDecl()
	}
	for p.atKw("import") {
		u.Imports = append(u.Imports, p.parseImportDecl())
	}
	for !p.at(EOF) {
		if p.at(Semi) { // `}` 后词法自动插入的分号在顶层无害，跳过
			p.i++
			continue
		}
		u.Decls = append(u.Decls, p.parseTopDecl())
	}
	return u, p.errs
}

// dropSemiInAnnotation 丢弃注解应用与所附声明之间的自动分号：
// `@Range(0, 100)\nInt pct = 50` 中 `)` 后的换行会触发分号插入，
// 但注解总是附着到下一个声明（§1.6 语句终止不适用于注解行）。
// 从 Annotation token 起进入注解态；遇到声明起始关键字退出；注解态内的 Semi 丢弃。
func dropSemiInAnnotation(toks []Token) []Token {
	out := toks[:0:0]
	pending := false
	for _, tk := range toks {
		if tk.Kind == Annotation {
			pending = true
			out = append(out, tk)
			continue
		}
		if pending {
			if tk.Kind == Semi {
				continue // 丢弃
			}
			if tk.Kind == Keyword && annoDeclStart[tk.Text] {
				pending = false
			}
		}
		out = append(out, tk)
	}
	return out
}

var annoDeclStart = map[string]bool{
	"package": true, "import": true, "static": true, "final": true, "const": true,
	"public": true, "protected": true, "private": true, "void": true,
	"class": true, "struct": true, "protocol": true, "enum": true,
	"singleton": true, "extension": true, "annotation": true,
}

func (p *parser) parseQualifiedName(what string) []string {
	var segs []string
	if !p.at(Ident) {
		t := p.cur()
		p.err(t.Pos, synExpect, what+"应为点分隔标识符，遇到 "+describe(t), "")
		return []string{"<err>"}
	}
	segs = append(segs, p.next().Text)
	for p.atOp(".") {
		p.i++
		if !p.at(Ident) {
			t := p.cur()
			p.err(t.Pos, synExpect, "包名段不得为空（§3.1），遇到 "+describe(t), "")
			segs = append(segs, "<err>")
			break
		}
		segs = append(segs, p.next().Text)
	}
	return segs
}

func (p *parser) parsePackageDecl() *PackageDecl {
	t := p.next() // package
	d := &PackageDecl{P: t.Pos, Name: p.parseQualifiedName("包名")}
	if p.at(Semi) {
		p.i++
	}
	// §3.1：用户包名不得以 xdk 开头（xdk. 是保留命名空间）。
	if len(d.Name) > 0 && d.Name[0] == "xdk" {
		p.err(d.P, synXdkPackage, "用户包名不得以 `xdk` 开头（`xdk.` 是保留命名空间，§3.1）", "")
	}
	return d
}

func (p *parser) parseImportDecl() *ImportDecl {
	t := p.next() // import
	d := &ImportDecl{P: t.Pos, Path: p.parseQualifiedName("导入路径")}
	if p.atKw("as") {
		p.i++
		d.Alias = p.expectKind(Ident, "消歧别名").Text
	}
	if p.at(Semi) {
		p.i++
	}
	return d
}

var typeDeclKeywords = map[string]bool{
	"class": true, "struct": true, "protocol": true, "enum": true,
	"singleton": true, "extension": true, "annotation": true,
}

// parseTopDecl = { Annotation } { TopLevelModifier } 顶层函数 | 顶层字段。
// 类型声明关键字在此报 SYN-110（第 2 部分范围，S2 切片实现）。
func (p *parser) parseTopDecl() TopDecl {
	t := p.cur()
	var annos []*AnnotationNode
	for p.at(Annotation) {
		annos = append(annos, p.parseAnnotation())
	}
	vis, static := p.parseTopModifiers()
	// 类型声明（M2.5.1）：class/struct/protocol/enum 走正式解析；
	// abstract/final 前缀先并入修饰符再判断；singleton/factory/extension/@annotation
	// 声明仍属后续批次，报 SYN-110 并跳过整个声明。
	if p.atKw("abstract") || p.atKw("final") {
		if kw, off := p.typeKeywordAhead(); kw != "" {
			mod := TypeModifiers{}
			switch {
			case vis[0]:
				mod.Vis = "public"
			case vis[1]:
				mod.Vis = "protected"
			case vis[2]:
				mod.Vis = "private"
			}
			mod.Static = static
			for k := 0; k < off; k++ {
				mod2 := p.parseTypeModifiers()
				if mod2.Vis != "" {
					mod.Vis = mod2.Vis
				}
				mod.Abstract = mod.Abstract || mod2.Abstract
				mod.Final = mod.Final || mod2.Final
				mod.Static = mod.Static || mod2.Static
				mod.Const = mod.Const || mod2.Const
			}
			if typeDeclKeywords[kw] && kw != "singleton" && kw != "extension" && kw != "annotation" {
				kwt := p.next().Text
				return p.parseTypeDecl(annos, kwt, mod)
			}
		}
	}
	if p.at(Keyword) && typeDeclKeywords[p.cur().Text] {
		kw := p.next().Text
		if kw == "class" || kw == "struct" || kw == "protocol" || kw == "enum" {
			mod := TypeModifiers{}
			switch {
			case vis[0]:
				mod.Vis = "public"
			case vis[1]:
				mod.Vis = "protected"
			case vis[2]:
				mod.Vis = "private"
			}
			mod.Static = static
			return p.parseTypeDecl(annos, kw, mod)
		}
		// singleton/factory/extension/@annotation：待后续批次
		p.err(t.Pos, synTypeDecl, "类型声明（"+kw+"）属第 2 部分，语法层待 S2 切片实现", "")
		depth := 0
		for !p.at(EOF) {
			if p.at(LBrace) {
				depth++
			} else if p.at(RBrace) {
				depth--
				if depth <= 0 {
					p.i++
					break
				}
			}
			p.i++
		}
		return &TopField{P: t.Pos, Annos: annos, Name: "<err>"}
	}
	// final/const 只出现在字段（函数返回类型不会是 final）。
	if p.atKw("final") || p.atKw("const") {
		f := &TopField{P: t.Pos, Annos: annos, Static: static,
			Public: vis[0], Protected: vis[1], Private: vis[2]}
		if p.atKw("final") {
			p.i++
			f.Final = true
		} else {
			p.i++
			f.Const = true
		}
		f.Type = p.parseTopType()
		f.Name = p.expectKind(Ident, "声明名").Text
		if p.atOp("=") {
			p.i++
			f.Init = p.parseExpr()
		}
		if p.at(Semi) {
			p.i++
		}
		return f
	}
	// `void` 是空类型（§2，不是关键字，词法按 Ident 返回），只能作为返回类型：
	// 顶层声明以 void 开头必为函数声明（§4.1）。此前用 atKw("void") 判断永不命中，
	// 导致 Void 标志丢失（DA-103 误报 void 函数缺 return）。
	if p.at(Ident) && p.cur().Text == "void" {
		p.i++
		return p.parseTopFuncRest(t.Pos, annos, vis, static, true, nil)
	}
	// 其余以类型开头：Type Identifier 后按 `(` 分函数/字段。
	ty := p.tryTypeRefQuietTop()
	if ty == nil {
		p.err(p.cur().Pos, synExpect, "期望顶层声明（函数、字段或类型），遇到 "+describe(p.cur()), "")
		if !p.at(EOF) {
			p.i++
		}
		return &TopField{P: t.Pos, Annos: annos, Name: "<err>"}
	}
	if !p.at(Ident) {
		p.err(p.cur().Pos, synExpect, "期望声明名，遇到 "+describe(p.cur()), "")
		return &TopField{P: t.Pos, Annos: annos, Type: ty, Name: "<err>"}
	}
	name := p.next()
	if p.at(LParen) || (p.atOp("<") && p.genericParamsFollows()) { // 函数（泛型参数在名字后）
		return p.parseTopFuncRest(t.Pos, annos, vis, static, false, ty, name.Text)
	}
	// 字段
	f := &TopField{P: t.Pos, Annos: annos, Static: static, Type: ty, Name: name.Text,
		Public: vis[0], Protected: vis[1], Private: vis[2]}
	if p.atKw("static") { // TopLevelField 文法允许 static 重复出现（与 §4.2 等价表述）
		p.i++
		f.Static = true
	}
	if p.atOp("=") {
		p.i++
		f.Init = p.parseExpr()
	}
	if p.at(Semi) {
		p.i++
	}
	return f
}

// genericParamsFollows 前瞻：从当前 `<` 出发做尖括号配平，检查匹配 `>` 之后
// 是否紧跟 `(`（附录 A GenericParams = "<" GenericParam { "," GenericParam } ">"，
// 泛型参数只有标识符，判定无歧义）。
func (p *parser) genericParamsFollows() bool {
	depth := 0
	for j := p.i; j < len(p.toks); j++ {
		tk := p.toks[j]
		switch {
		case tk.Kind == Op && tk.Text == "<":
			depth++
		case tk.Kind == Op && tk.Text == ">":
			depth--
			if depth == 0 {
				return j+1 < len(p.toks) && p.toks[j+1].at(LParen)
			}
		case tk.Kind == Ident || (tk.Kind == Op && tk.Text == ","):
		default:
			return false
		}
	}
	return false
}

// parseTopModifiers 消费可见性与 static 修饰符；返回 [public, protected, private] 与 static。
func (p *parser) parseTopModifiers() ([3]bool, bool) {
	var vis [3]bool
	static := false
	for {
		switch {
		case p.atKw("public"):
			p.i++
			vis[0] = true
		case p.atKw("protected"):
			p.i++
			vis[1] = true
		case p.atKw("private"):
			p.i++
			vis[2] = true
		case p.atKw("static"):
			p.i++
			static = true
		default:
			return vis, static
		}
	}
}

// parseTopFuncRest 解析函数名之后的完整函数（调用方已消费返回类型）。
func (p *parser) parseTopFuncRest(pos Pos, annos []*AnnotationNode, vis [3]bool, static, void bool, ret TypeRef, name ...string) *TopFunc {
	f := &TopFunc{P: pos, Annos: annos, Public: vis[0], Protected: vis[1], Private: vis[2],
		Static: static, Void: void, Ret: ret}
	if len(name) > 0 {
		f.Name = name[0]
	} else {
		f.Name = p.expectKind(Ident, "函数名").Text
	}
	// 泛型参数：< Ident { "," Ident } ">"，顶层声明位置无歧义。
	if p.atOp("<") {
		p.i++
		for {
			f.TypePars = append(f.TypePars, p.expectKind(Ident, "类型参数").Text)
			if p.atOp(",") {
				p.i++
				continue
			}
			break
		}
		p.expectOp(">")
	}
	p.expectKind(LParen, "`(`")
	if !p.at(RParen) {
		for {
			f.Params = append(f.Params, p.parseParam())
			if p.at(Comma) {
				p.i++
				continue
			}
			break
		}
	}
	p.expectKind(RParen, "`)`")
	f.Body = p.parseBlock()
	return f
}

func (p *parser) parseParam() *Param {
	t := p.cur()
	pr := &Param{P: t.Pos}
	for p.at(Annotation) {
		pr.Annos = append(pr.Annos, p.parseAnnotation())
	}
	if p.atKw("final") {
		p.i++
		pr.Final = true
	}
	pr.Type = p.parseTypeRef()
	pr.Name = p.expectKind(Ident, "参数名").Text
	return pr
}

func (p *parser) parseAnnotation() *AnnotationNode {
	t := p.next() // @name（词法把 @ 与名字合为一个 Annotation token）
	a := &AnnotationNode{P: t.Pos, Name: strings.TrimPrefix(t.Text, "@")}
	if p.at(LParen) {
		p.i++
		if !p.at(RParen) {
			for {
				a.Args = append(a.Args, p.parseExpr())
				if p.at(Comma) {
					p.i++
					continue
				}
				break
			}
		}
		p.expectKind(RParen, "`)`")
	}
	return a
}

// tryTypeRefQuietTop 顶层声明位置的类型解析：不吞 `(`（函数实参表归函数，
// 与 new 的处理同理），失败回退。
func (p *parser) tryTypeRefQuietTop() TypeRef {
	save, errLen := p.i, len(p.errs)
	ty := p.parseTopType()
	if len(p.errs) > errLen || !p.at(Ident) {
		p.rollback(save, errLen)
		return nil
	}
	return ty
}

// parseTopType 解析顶层声明的类型：命名类型 + 后缀；`(` 不构成函数类型
// （顶层 `static Type name(` 的 `(` 永远是参数表，附录 A 文法说明同理）。
func (p *parser) parseTopType() TypeRef {
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
