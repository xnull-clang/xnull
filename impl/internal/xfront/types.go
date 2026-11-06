package xfront

// —— S2 对象编程：类型声明（M2.5.1 批次：class/struct/protocol/enum）——
// 规范依据：S2 §1（声明总览/修饰符）、§2（类）、§3（结构体）、§4（协议）、§6（成员）、§8（枚举）。
// singleton/factory/extension/@annotation 声明仍按 SYN-110 拒绝（后续批次）。

// TypeModifiers 是类型与成员修饰符（S2 §1.6）。可见性互斥与重复修饰符在解析期拒绝。
type TypeModifiers struct {
	Vis      string // "public" / "protected" / "private" / ""（默认 public）
	Abstract bool
	Final    bool
	Static   bool
	Const    bool
}

// FieldDecl 类/结构体/数据枚举字段（S2 §6.1）。
type FieldDecl struct {
	P         Pos
	Mod       TypeModifiers
	Type      TypeRef
	Name      string // 声明名
	Canonical string // 规范名：私有字段统一 _name（S2 §7.4）
	Init      Expr   // 可空
}

// MethodDecl 实例/静态方法；void deinit() 归一为 IsDeinit（S2 §6.2/§6.4）。
type MethodDecl struct {
	P        Pos
	Mod      TypeModifiers
	Name     string
	Void     bool
	Ret      TypeRef
	Params   []*Param
	Body     *Block
	IsDeinit bool
}

// CtorDecl 构造器：与类同名、不写返回类型（S2 §6.3）。
type CtorDecl struct {
	P      Pos
	Mod    TypeModifiers
	Params []*Param
	Body   *Block
}

// ProtocolSig 协议方法签名：以 ; 结束，无方法体（S2 §4.2）。
type ProtocolSig struct {
	P      Pos
	Mod    TypeModifiers
	Name   string
	Void   bool
	Ret    TypeRef
	Params []*Param
}

// ClassDecl 引用类型：单继承 + 多协议（S2 §2）。
type ClassDecl struct {
	P         Pos
	Annos     []*AnnotationNode
	Mod       TypeModifiers
	Name      string
	TypePars  []string
	Primary   *CtorDecl // 主构造器：class Worker(final Int id) { }（§6.1，声明并绑定同名字段）
	Base      TypeRef   // 可空
	Protocols []*NamedType
	Fields    []*FieldDecl
	Methods   []*MethodDecl
	Ctors     []*CtorDecl
}

// StructDecl 纯值类型：不继承、不实现协议、无 deinit（S2 §3）。
type StructDecl struct {
	P        Pos
	Annos    []*AnnotationNode
	Mod      TypeModifiers
	Name     string
	TypePars []string
	Primary  *CtorDecl // 主构造器（§3.5）
	Fields   []*FieldDecl
	Methods  []*MethodDecl
	Ctors    []*CtorDecl
}

// ProtocolDecl 名义方法签名合同（S2 §4）。
type ProtocolDecl struct {
	P       Pos
	Annos   []*AnnotationNode
	Name    string
	Extends []*NamedType
	Sigs    []*ProtocolSig
}

// EnumItem 枚举项：简单枚举带 Value（整数字面量），数据枚举带 Args。
type EnumItem struct {
	P     Pos
	Name  string
	Value Expr   // 简单枚举
	Args  []Expr // 数据枚举
}

// EnumDecl 封闭枚举（S2 §8）：简单枚举只有项；数据枚举带字段/构造器/方法。
type EnumDecl struct {
	P       Pos
	Annos   []*AnnotationNode
	Mod     TypeModifiers
	Name    string
	Items   []*EnumItem
	IsData  bool
	Fields  []*FieldDecl
	Methods []*MethodDecl
	Ctors   []*CtorDecl
}

func (d *ClassDecl) topDecl()    {}
func (d *ClassDecl) Pos() Pos    { return d.P }
func (d *StructDecl) topDecl()   {}
func (d *StructDecl) Pos() Pos   { return d.P }
func (d *ProtocolDecl) topDecl() {}
func (d *ProtocolDecl) Pos() Pos { return d.P }
func (d *EnumDecl) topDecl()     {}
func (d *EnumDecl) Pos() Pos     { return d.P }

// declKind 返回声明种类名（诊断用）。
func (d *ClassDecl) declKind() string    { return "class" }
func (d *StructDecl) declKind() string   { return "struct" }
func (d *ProtocolDecl) declKind() string { return "protocol" }
func (d *EnumDecl) declKind() string     { return "enum" }

// ---------- 解析 ----------

// parseTypeModifiers 解析类型/成员修饰符；重复与可见性互斥立即报错（S2 §1.6）。
func (p *parser) parseTypeModifiers() TypeModifiers {
	var m TypeModifiers
	seen := map[string]bool{}
	setVis := func(v string) {
		if m.Vis != "" {
			p.err(p.cur().Pos, synExpect, "可见性修饰符互斥（§1.6），已写 "+m.Vis, "")
		} else if seen[v] {
			p.err(p.cur().Pos, synExpect, "修饰符 `"+v+"` 重复出现（§1.6）", "")
		} else {
			m.Vis = v
			seen[v] = true
		}
		p.i++
	}
	setFlag := func(name string, slot *bool) {
		if seen[name] {
			p.err(p.cur().Pos, synExpect, "修饰符 `"+name+"` 重复出现（§1.6）", "")
		} else {
			*slot = true
			seen[name] = true
		}
		p.i++
	}
	for {
		t := p.cur()
		if t.Kind != Keyword {
			break
		}
		switch t.Text {
		case "public":
			setVis("public")
		case "protected":
			setVis("protected")
		case "private":
			setVis("private")
		case "abstract":
			setFlag("abstract", &m.Abstract)
		case "final":
			setFlag("final", &m.Final)
		case "static":
			setFlag("static", &m.Static)
		case "const":
			setFlag("const", &m.Const)
		default:
			return m
		}
	}
	return m
}

// parseTypeDecl 解析 class/struct/protocol/enum（kw 已消费）。
func (p *parser) parseTypeDecl(annos []*AnnotationNode, kw string, mod TypeModifiers) TopDecl {
	var d TopDecl
	switch kw {
	case "class":
		cd := p.parseClassDecl(mod)
		cd.Annos = annos
		d = cd
	case "struct":
		sd := p.parseStructDecl(mod)
		sd.Annos = annos
		d = sd
	case "protocol":
		pd := p.parseProtocolDecl()
		pd.Annos = annos
		d = pd
	case "enum":
		ed := p.parseEnumDecl(mod)
		ed.Annos = annos
		d = ed
	}
	return d
}

// parseGenericPars 解析 `<T, out U>` 形式的类型参数表（§1.6 out/in 仅类允许）。
func (p *parser) parseGenericPars(allowVariance bool) []string {
	if !p.atOp("<") {
		return nil
	}
	p.i++
	var pars []string
	for {
		if p.atKw("out") || p.atKw("in") {
			if !allowVariance {
				p.err(p.cur().Pos, synExpect, "型变修饰 out/in 只允许用于类的泛型参数（§3.1）", "")
			}
			p.i++
		}
		pars = append(pars, p.expectKind(Ident, "类型参数名").Text)
		if p.at(Comma) {
			p.i++
			continue
		}
		break
	}
	p.expectOp(">")
	return pars
}

// parseNamedTypeRef 解析单个命名类型（限定名 + 可选泛型实参），用于父类/协议表。
func (p *parser) parseNamedTypeRef(what string) *NamedType {
	t := p.cur()
	if t.Kind != Ident && t.Kind != Keyword {
		p.err(t.Pos, synExpect, "期望"+what+"类型名，遇到 "+describe(t), "")
		return &NamedType{P: t.Pos, Qual: []string{"<err>"}}
	}
	nt := &NamedType{P: t.Pos}
	nt.Qual = append(nt.Qual, p.next().Text)
	for p.atOp(".") {
		p.i++
		nt.Qual = append(nt.Qual, p.expectKind(Ident, "限定名段").Text)
	}
	if p.atOp("<") {
		p.i++
		for {
			arg := p.tryTypeRefQuiet()
			if arg == nil {
				p.err(p.cur().Pos, synExpect, "期望泛型实参，遇到 "+describe(p.cur()), "")
				break
			}
			nt.Args = append(nt.Args, arg)
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

func (p *parser) parseClassDecl(mod TypeModifiers) *ClassDecl {
	d := &ClassDecl{P: p.cur().Pos, Mod: mod}
	d.Name = p.expectKind(Ident, "类名").Text
	d.TypePars = p.parseGenericPars(true)
	if p.at(LParen) { // 主构造器（§6.1）
		d.Primary = &CtorDecl{P: p.cur().Pos}
		d.Primary.Params = p.parseParamList()
	}
	if p.atOp(":") {
		p.i++
		d.Base = p.parseNamedTypeRef("父类")
	}
	if p.atKw("implements") {
		p.i++
		for {
			d.Protocols = append(d.Protocols, p.parseNamedTypeRef("协议"))
			if p.at(Comma) {
				p.i++
				continue
			}
			break
		}
	}
	p.expectKind(LBrace, "类体 `{`（必须与类头同一行，§1.1）")
	for !p.at(RBrace) && !p.at(EOF) {
		p.parseClassMember(d)
	}
	p.expectKind(RBrace, "类体结束")
	if p.at(Semi) {
		p.i++
	}
	return d
}

// parseClassMember 解析字段/方法/构造器/deinit（S2 §6）。
func (p *parser) parseClassMember(d *ClassDecl) {
	mod := p.parseTypeModifiers()
	save := p.i
	ty := p.tryTypeRefQuiet()
	if ty != nil && p.at(Ident) {
		nameTok := p.next()
		if p.at(LParen) { // 方法（void deinit() 归一为 deinit）
			m := p.parseMethodRest(mod, ty, nameTok)
			d.Methods = append(d.Methods, m)
			return
		}
		// 字段
		f := &FieldDecl{P: nameTok.Pos, Mod: mod, Type: ty, Name: nameTok.Text}
		if p.atOp("=") {
			p.i++
			f.Init = p.parseExpr()
		}
		p.expectKind(Semi, "字段声明结束 `;`")
		d.Fields = append(d.Fields, f)
		return
	}
	// 构造器：与类同名、不写返回类型（§6.3）
	p.i = save
	if p.at(Ident) && p.cur().Text == d.Name && p.toks[p.i+1].Kind == LParen {
		p.i++
		c := &CtorDecl{P: p.cur().Pos, Mod: mod}
		c.Params = p.parseParamList()
		c.Body = p.parseBlock()
		if p.at(Semi) {
			p.i++
		}
		d.Ctors = append(d.Ctors, c)
		return
	}
	p.err(p.cur().Pos, synExpect, "期望类成员（字段、方法或构造器），遇到 "+describe(p.cur()), "")
	if !p.at(EOF) && !p.at(RBrace) {
		p.i++
	}
}

// parseMethodRest 解析方法参数与体；deinit 归一（§6.4：void、无参）。
func (p *parser) parseMethodRest(mod TypeModifiers, ret TypeRef, name Token) *MethodDecl {
	m := &MethodDecl{P: name.Pos, Mod: mod, Name: name.Text}
	if nt, ok := ret.(*NamedType); ok && len(nt.Qual) == 1 && nt.Qual[0] == "void" && len(nt.Args) == 0 {
		m.Void = true
	} else {
		m.Ret = ret
	}
	m.Params = p.parseParamList()
	m.Body = p.parseBlock()
	if m.Name == "deinit" {
		m.IsDeinit = true
	}
	if p.at(Semi) {
		p.i++
	}
	return m
}

func (p *parser) parseStructDecl(mod TypeModifiers) *StructDecl {
	d := &StructDecl{P: p.cur().Pos, Mod: mod}
	d.Name = p.expectKind(Ident, "结构体名").Text
	d.TypePars = p.parseGenericPars(false)
	if p.at(LParen) {
		d.Primary = &CtorDecl{P: p.cur().Pos}
		d.Primary.Params = p.parseParamList()
	}
	if p.atOp(":") {
		p.err(p.cur().Pos, synExpect, "结构体不能继承（§3.1）", "")
		p.i++
		p.parseNamedTypeRef("父类")
	}
	if p.atKw("implements") {
		p.err(p.cur().Pos, synExpect, "结构体不能实现协议（§3.1）", "")
		p.i++
		for p.tryTypeRefQuiet() != nil && p.at(Comma) {
			p.i++
		}
	}
	p.expectKind(LBrace, "结构体体 `{`（必须与头部同一行，§1.1）")
	for !p.at(RBrace) && !p.at(EOF) {
		mod2 := p.parseTypeModifiers()
		save := p.i
		ty := p.tryTypeRefQuiet()
		if ty != nil && p.at(Ident) {
			nameTok := p.next()
			if p.at(LParen) {
				d.Methods = append(d.Methods, p.parseMethodRest(mod2, ty, nameTok))
				continue
			}
			f := &FieldDecl{P: nameTok.Pos, Mod: mod2, Type: ty, Name: nameTok.Text}
			if p.atOp("=") {
				p.i++
				f.Init = p.parseExpr()
			}
			p.expectKind(Semi, "字段声明结束 `;`")
			d.Fields = append(d.Fields, f)
			continue
		}
		p.i = save
		if p.at(Ident) && p.cur().Text == d.Name && p.toks[p.i+1].Kind == LParen {
			p.i++
			c := &CtorDecl{P: p.cur().Pos, Mod: mod2}
			c.Params = p.parseParamList()
			c.Body = p.parseBlock()
			if p.at(Semi) {
				p.i++
			}
			d.Ctors = append(d.Ctors, c)
			continue
		}
		p.err(p.cur().Pos, synExpect, "期望结构体成员，遇到 "+describe(p.cur()), "")
		if !p.at(EOF) && !p.at(RBrace) {
			p.i++
		}
	}
	p.expectKind(RBrace, "结构体体结束")
	if p.at(Semi) {
		p.i++
	}
	return d
}

func (p *parser) parseProtocolDecl() *ProtocolDecl {
	d := &ProtocolDecl{P: p.cur().Pos}
	d.Name = p.expectKind(Ident, "协议名").Text
	if p.atOp(":") {
		p.i++
		for {
			d.Extends = append(d.Extends, p.parseNamedTypeRef("父协议"))
			if p.at(Comma) {
				p.i++
				continue
			}
			break
		}
	}
	p.expectKind(LBrace, "协议体 `{`（必须与头部同一行，§1.1）")
	for !p.at(RBrace) && !p.at(EOF) {
		mod := p.parseTypeModifiers()
		ty := p.tryTypeRefQuiet()
		if ty == nil || !p.at(Ident) {
			p.err(p.cur().Pos, synExpect, "协议体只能声明方法签名（§4.1：没有字段/方法体/构造器），遇到 "+describe(p.cur()), "")
			if !p.at(EOF) && !p.at(RBrace) {
				p.i++
			}
			continue
		}
		nameTok := p.next()
		if !p.at(LParen) {
			p.err(p.cur().Pos, synExpect, "协议不能声明字段（§4.2）", "")
			if p.at(Semi) {
				p.i++
			}
			continue
		}
		sig := &ProtocolSig{P: nameTok.Pos, Mod: mod, Name: nameTok.Text}
		if nt, ok := ty.(*NamedType); ok && len(nt.Qual) == 1 && nt.Qual[0] == "void" && len(nt.Args) == 0 {
			sig.Void = true
		} else {
			sig.Ret = ty
		}
		sig.Params = p.parseParamList()
		if p.at(LBrace) {
			p.err(p.cur().Pos, synExpect, "协议方法不能有方法体（§4.2：只写签名）", "")
			p.parseBlock() // 消费体，继续分析
		} else {
			p.expectKind(Semi, "协议签名结束 `;`")
		}
		d.Sigs = append(d.Sigs, sig)
	}
	p.expectKind(RBrace, "协议体结束")
	if p.at(Semi) {
		p.i++
	}
	return d
}

func (p *parser) parseEnumDecl(mod TypeModifiers) *EnumDecl {
	d := &EnumDecl{P: p.cur().Pos, Mod: mod}
	d.Name = p.expectKind(Ident, "枚举名").Text
	if p.atOp("<") {
		p.err(p.cur().Pos, synExpect, "枚举不能是泛型（§8.1）", "")
		p.parseGenericPars(false)
	}
	p.expectKind(LBrace, "枚举体 `{`（必须与头部同一行，§1.1）")
	for !p.at(RBrace) && !p.at(EOF) && !p.at(Semi) {
		nameTok := p.expectKind(Ident, "枚举项名")
		item := &EnumItem{P: nameTok.Pos, Name: nameTok.Text}
		if p.atOp("=") {
			p.i++
			if p.atOp("-") {
				minus := p.cur()
				p.i++
				lit := p.expectKind(IntLit, "整数字面量")
				item.Value = &Unary{P: minus.Pos, Op: "-", X: &IntLitExpr{P: lit.Pos, Text: lit.Text}}
			} else {
				lit := p.expectKind(IntLit, "整数字面量")
				item.Value = &IntLitExpr{P: lit.Pos, Text: lit.Text}
			}
		}
		if p.at(LParen) {
			p.i++
			for !p.at(RParen) && !p.at(EOF) {
				item.Args = append(item.Args, p.parseExpr())
				if p.at(Comma) {
					p.i++
					continue
				}
				break
			}
			p.expectKind(RParen, "枚举项参数表结束")
			d.IsData = true
		}
		d.Items = append(d.Items, item)
		if p.at(Comma) {
			p.i++
			continue
		}
		break
	}
	if p.at(Semi) { // 数据枚举：项后跟成员
		p.i++
		if !d.IsData {
			d.IsData = len(d.Items) > 0 && d.Items[0].Args != nil
		}
		for !p.at(RBrace) && !p.at(EOF) {
			mod := p.parseTypeModifiers()
			save := p.i
			ty := p.tryTypeRefQuiet()
			if ty != nil && p.at(Ident) {
				nameTok := p.next()
				if p.at(LParen) {
					d.Methods = append(d.Methods, p.parseMethodRest(mod, ty, nameTok))
					continue
				}
				f := &FieldDecl{P: nameTok.Pos, Mod: mod, Type: ty, Name: nameTok.Text}
				if p.atOp("=") {
					p.i++
					f.Init = p.parseExpr()
				}
				p.expectKind(Semi, "字段声明结束 `;`")
				d.Fields = append(d.Fields, f)
				continue
			}
			p.i = save
			if p.at(Ident) && p.cur().Text == d.Name && p.toks[p.i+1].Kind == LParen {
				p.i++
				c := &CtorDecl{P: p.cur().Pos, Mod: mod}
				c.Params = p.parseParamList()
				c.Body = p.parseBlock()
				if p.at(Semi) {
					p.i++
				}
				d.Ctors = append(d.Ctors, c)
				continue
			}
			p.err(p.cur().Pos, synExpect, "期望枚举成员（字段、方法或构造器），遇到 "+describe(p.cur()), "")
			if !p.at(EOF) && !p.at(RBrace) {
				p.i++
			}
		}
	}
	p.expectKind(RBrace, "枚举体结束")
	if p.at(Semi) {
		p.i++
	}
	return d
}

// parseParamList 解析参数表（与顶层函数同一套参数语法，S2 §6.2）。
func (p *parser) parseParamList() []*Param {
	var ps []*Param
	p.expectKind(LParen, "`(`")
	if !p.at(RParen) {
		for {
			ps = append(ps, p.parseParam())
			if p.at(Comma) {
				p.i++
				continue
			}
			break
		}
	}
	p.expectKind(RParen, "`)`")
	return ps
}

// typeKeywordAhead 向前扫描：跳过 abstract/final 修饰符后是否为类型声明关键字。
// 返回关键字文本与跳过的修饰符个数（不含当前）。
func (p *parser) typeKeywordAhead() (string, int) {
	off := 0
	for k := 0; p.i+k < len(p.toks); k++ {
		t := p.toks[p.i+k]
		if t.Kind == Keyword && (t.Text == "abstract" || t.Text == "final") {
			off = k + 1
			continue
		}
		if t.Kind == Keyword && typeDeclKeywords[t.Text] {
			return t.Text, off
		}
		return "", 0
	}
	return "", 0
}
