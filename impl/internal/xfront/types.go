package xfront

// —— S2 对象编程：类型声明（M2.5.1 批次：class/struct/protocol/enum）——
// 规范依据：S2 §1（声明总览/修饰符）、§2（类）、§3（结构体）、§4（协议）、§6（成员）、§8（枚举）。
// S2 §9—§12 的 singleton / factory / extension / @annotation 与注解使用也在此文件解析。

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
	Annos     []*AnnotationNode // S2 §12.2：字段可带注解
	Mod       TypeModifiers
	Type      TypeRef
	Name      string // 声明名
	Canonical string // 规范名：私有字段统一 _name（S2 §7.4）
	Init      Expr   // 可空
}

// MethodDecl 实例/静态方法；void deinit() 归一为 IsDeinit（S2 §6.2/§6.4）。
type MethodDecl struct {
	P        Pos
	Annos    []*AnnotationNode // S2 §12.2：方法可带注解（含 @Override）
	Mod      TypeModifiers
	Name     string
	TypePars []string // 方法级泛型参数（S2 §13；factory 方法可用）
	Void     bool
	Ret      TypeRef
	Params   []*Param
	Body     *Block
	IsDeinit bool
}

// CtorDecl 构造器：与类同名、不写返回类型（S2 §6.3）。
type CtorDecl struct {
	P      Pos
	Annos  []*AnnotationNode
	Mod    TypeModifiers
	Params []*Param
	Body   *Block
}

// ProtocolSig 协议方法签名：以 ; 结束，无方法体（S2 §4.2）。
type ProtocolSig struct {
	P      Pos
	Annos  []*AnnotationNode
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
	Annos []*AnnotationNode // S2 §12.2：枚举项可带注解
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

// SingletonDecl 单例（S2 §9）：全局唯一实例；不能泛型/继承/实现协议/声明构造器。
// 文法上 Member 与 class 相同（附录 A），构造器等限制由语义层拒绝。
type SingletonDecl struct {
	P       Pos
	Annos   []*AnnotationNode
	Mod     TypeModifiers
	Name    string
	Fields  []*FieldDecl
	Methods []*MethodDecl
	Ctors   []*CtorDecl
}

// FactoryDecl 工厂（S2 §10）：绑定目标类型的创建命名空间，不是类型。
type FactoryDecl struct {
	P       Pos
	Annos   []*AnnotationNode
	Mod     TypeModifiers
	Name    string
	Target  TypeRef
	Methods []*MethodDecl
}

// ExtensionDecl 扩展（S2 §11）：只能给已有类型添加方法。
type ExtensionDecl struct {
	P       Pos
	Annos   []*AnnotationNode
	Mod     TypeModifiers
	Target  TypeRef
	Methods []*MethodDecl
}

// AnnotationDecl 注解声明（S2 §12）：只含 final 字段，编译期存在。
type AnnotationDecl struct {
	P      Pos
	Annos  []*AnnotationNode
	Mod    TypeModifiers
	Name   string
	Fields []*FieldDecl
}

func (d *SingletonDecl) topDecl()  {}
func (d *SingletonDecl) Pos() Pos  { return d.P }
func (d *FactoryDecl) topDecl()    {}
func (d *FactoryDecl) Pos() Pos    { return d.P }
func (d *ExtensionDecl) topDecl()  {}
func (d *ExtensionDecl) Pos() Pos  { return d.P }
func (d *AnnotationDecl) topDecl() {}
func (d *AnnotationDecl) Pos() Pos { return d.P }

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
	case "singleton":
		sd := p.parseSingletonDecl(mod)
		sd.Annos = annos
		d = sd
	case "factory":
		fd := p.parseFactoryDecl(mod)
		fd.Annos = annos
		d = fd
	case "extension":
		ed := p.parseExtensionDecl(mod)
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
	p.splitAngleClose()
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
		p.splitAngleClose()
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
		p.parseMember(memberTarget{name: d.Name, fields: &d.Fields, methods: &d.Methods, ctors: &d.Ctors, what: "类"})
	}
	p.expectKind(RBrace, "类体结束")
	if p.at(Semi) {
		p.i++
	}
	return d
}

// parseAnnotations 消费连续的注解应用（S2 §12.2）。
// 注解总是附着到其后的成员；注解行末的自动分号不终止声明（与 §1.6 一致）。
func (p *parser) parseAnnotations() []*AnnotationNode {
	var annos []*AnnotationNode
	for p.at(Annotation) {
		annos = append(annos, p.parseAnnotation())
		if p.at(Semi) {
			p.i++
		}
	}
	return annos
}

// memberTarget 把成员写入目标解耦，class/struct/singleton/enum 共用一套成员解析。
type memberTarget struct {
	name    string // 构造器名（类型名）
	fields  *[]*FieldDecl
	methods *[]*MethodDecl
	ctors   *[]*CtorDecl
	what    string // "类" / "结构体" / "单例" / "枚举"
}

// parseMember 解析字段/方法/构造器/deinit（S2 §6，附录 A Member）。
func (p *parser) parseMember(t memberTarget) {
	annos := p.parseAnnotations()
	mod := p.parseTypeModifiers()
	save := p.i
	ty := p.tryTypeRefQuiet()
	if ty != nil && p.at(Ident) {
		nameTok := p.next()
		if p.at(LParen) || (p.atOp("<") && p.genericParamsFollows()) { // 方法（void deinit() 归一为 deinit）
			*t.methods = append(*t.methods, p.parseMethodRest(annos, mod, ty, nameTok))
			return
		}
		// 字段
		f := &FieldDecl{P: nameTok.Pos, Annos: annos, Mod: mod, Type: ty, Name: nameTok.Text}
		if p.atOp("=") {
			p.i++
			f.Init = p.parseExpr()
		}
		p.expectKind(Semi, "字段声明结束 `;`")
		*t.fields = append(*t.fields, f)
		return
	}
	// 构造器：与类型同名、不写返回类型（§6.3）
	p.i = save
	if p.at(Ident) && p.cur().Text == t.name && p.toks[p.i+1].Kind == LParen {
		p.i++
		c := &CtorDecl{P: p.cur().Pos, Annos: annos, Mod: mod}
		c.Params = p.parseParamList()
		c.Body = p.parseBlock()
		if p.at(Semi) {
			p.i++
		}
		*t.ctors = append(*t.ctors, c)
		return
	}
	p.err(p.cur().Pos, synExpect, "期望"+t.what+"成员（字段、方法或构造器），遇到 "+describe(p.cur()), "")
	if !p.at(EOF) && !p.at(RBrace) {
		p.i++
	}
}

// parseMethodRest 解析方法泛型参数、参数与体；deinit 归一（§6.4：void、无参）。
func (p *parser) parseMethodRest(annos []*AnnotationNode, mod TypeModifiers, ret TypeRef, name Token) *MethodDecl {
	m := &MethodDecl{P: name.Pos, Annos: annos, Mod: mod, Name: name.Text}
	if p.atOp("<") {
		m.TypePars = p.parseGenericPars(false)
	}
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
		p.parseMember(memberTarget{name: d.Name, fields: &d.Fields, methods: &d.Methods, ctors: &d.Ctors, what: "结构体"})
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
		annos := p.parseAnnotations()
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
		sig := &ProtocolSig{P: nameTok.Pos, Annos: annos, Mod: mod, Name: nameTok.Text}
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
		annos := p.parseAnnotations()
		nameTok := p.expectKind(Ident, "枚举项名")
		item := &EnumItem{P: nameTok.Pos, Annos: annos, Name: nameTok.Text}
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
			p.parseMember(memberTarget{name: d.Name, fields: &d.Fields, methods: &d.Methods, ctors: &d.Ctors, what: "枚举"})
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

// ---------- S2 §9—§12：singleton / factory / extension / @annotation ----------

// parseSingletonDecl 解析 `singleton Name { Member* }`（S2 §9、附录 A）。
// 泛型、继承、协议、构造器等限制由语义层拒绝；文法层只接受 Member。
func (p *parser) parseSingletonDecl(mod TypeModifiers) *SingletonDecl {
	d := &SingletonDecl{P: p.cur().Pos, Mod: mod}
	d.Name = p.expectKind(Ident, "单例名").Text
	if !p.at(LBrace) {
		p.err(p.cur().Pos, synExpect, "单例头部不能带参数或继承（§9.1、§6.3）", "写 `singleton Name {`")
		for !p.at(LBrace) && !p.at(EOF) {
			p.i++
		}
	}
	p.expectKind(LBrace, "单例体 `{`（必须与头部同一行，§1.1）")
	for !p.at(RBrace) && !p.at(EOF) {
		p.parseMember(memberTarget{name: d.Name, fields: &d.Fields, methods: &d.Methods, ctors: &d.Ctors, what: "单例"})
	}
	p.expectKind(RBrace, "单例体结束")
	if p.at(Semi) {
		p.i++
	}
	return d
}

// parseFactoryDecl 解析 `factory Name for Target { FactoryMember* }`（S2 §10）。
func (p *parser) parseFactoryDecl(mod TypeModifiers) *FactoryDecl {
	d := &FactoryDecl{P: p.cur().Pos, Mod: mod}
	d.Name = p.expectKind(Ident, "工厂名").Text
	if p.atKw("for") {
		p.i++
	} else {
		p.err(p.cur().Pos, synExpect, "factory 头缺少 `for Target`（§10.1）", "写 `factory F for Type {`")
	}
	d.Target = p.parseTypeRef()
	p.expectKind(LBrace, "工厂体 `{`（必须与头部同一行，§1.1）")
	for !p.at(RBrace) && !p.at(EOF) {
		p.parseFactoryMember(d)
	}
	p.expectKind(RBrace, "工厂体结束")
	if p.at(Semi) {
		p.i++
	}
	return d
}

// parseFactoryMember 解析工厂方法：{Annotation} [可见性] "static" Type Ident [GenericParams] (...) Block。
func (p *parser) parseFactoryMember(d *FactoryDecl) {
	annos := p.parseAnnotations()
	mod := p.parseTypeModifiers()
	if mod.Abstract || mod.Final || mod.Const {
		p.err(p.cur().Pos, synExpect, "工厂方法不能写 abstract / final / const（§10.2）", "")
	}
	if !mod.Static {
		p.err(p.cur().Pos, synExpect, "工厂方法必须写 static（§10.1）", "")
	}
	ty := p.parseTypeRef()
	nameTok := p.expectKind(Ident, "工厂方法名")
	m := p.parseMethodRest(annos, mod, ty, nameTok)
	d.Methods = append(d.Methods, m)
}

// parseExtensionDecl 解析 `extension TypeRef { MethodDecl* }`（S2 §11）。
func (p *parser) parseExtensionDecl(mod TypeModifiers) *ExtensionDecl {
	d := &ExtensionDecl{P: p.cur().Pos, Mod: mod}
	d.Target = p.parseTypeRef()
	p.expectKind(LBrace, "扩展体 `{`（必须与头部同一行，§1.1）")
	for !p.at(RBrace) && !p.at(EOF) {
		p.parseExtensionMember(d)
	}
	p.expectKind(RBrace, "扩展体结束")
	if p.at(Semi) {
		p.i++
	}
	return d
}

// parseExtensionMember 解析扩展方法：只能加方法，不能有字段/构造器/deinit/静态方法（§11.1）。
func (p *parser) parseExtensionMember(d *ExtensionDecl) {
	annos := p.parseAnnotations()
	if p.cur().Kind == Keyword && isMemberModifier(p.cur().Text) {
		p.err(p.cur().Pos, synExpect, "扩展方法不能写可见性/static/final 修饰符（§11.1、附录 A ExtensionMember）", "")
		p.parseTypeModifiers()
	}
	ty := p.parseTypeRef()
	nameTok := p.expectKind(Ident, "扩展方法名")
	m := p.parseMethodRest(annos, TypeModifiers{}, ty, nameTok)
	d.Methods = append(d.Methods, m)
}

func isMemberModifier(s string) bool {
	switch s {
	case "public", "protected", "private", "static", "final", "abstract", "const":
		return true
	}
	return false
}

// annotationDeclFollows 判断当前 `@annotation` token 是否为声明：
// 形如 `@annotation Name {`（S2 附录 A AnnotationDecl）。
func (p *parser) annotationDeclFollows() bool {
	if p.cur().Kind != Annotation || p.cur().Text != "annotation" {
		return false
	}
	return p.toks[min(p.i+1, len(p.toks)-1)].Kind == Ident &&
		p.toks[min(p.i+2, len(p.toks)-1)].Kind == LBrace
}

// modFromVis 把顶层可见性/static 位转换为 TypeModifiers。
func modFromVis(vis [3]bool, static bool) TypeModifiers {
	m := TypeModifiers{Static: static}
	switch {
	case vis[0]:
		m.Vis = "public"
	case vis[1]:
		m.Vis = "protected"
	case vis[2]:
		m.Vis = "private"
	}
	return m
}

// merge 合并同一类型头出现的前后两组修饰符（§1.6）。
func (m *TypeModifiers) merge(o TypeModifiers) {
	if o.Vis != "" {
		m.Vis = o.Vis
	}
	m.Abstract = m.Abstract || o.Abstract
	m.Final = m.Final || o.Final
	m.Static = m.Static || o.Static
	m.Const = m.Const || o.Const
}

// parseAnnotationDecl 解析 `@annotation Name { AnnotationField* }`（S2 §12.1）。
func (p *parser) parseAnnotationDecl(annos []*AnnotationNode, mod TypeModifiers) *AnnotationDecl {
	at := p.next() // @annotation
	d := &AnnotationDecl{P: at.Pos, Annos: annos, Mod: mod}
	d.Name = p.expectKind(Ident, "注解名").Text
	p.expectKind(LBrace, "注解体 `{`（必须与头部同一行，§1.1）")
	for !p.at(RBrace) && !p.at(EOF) {
		fp := p.cur().Pos
		if !p.atKw("final") {
			p.err(fp, synExpect, "注解体只能声明 `final` 字段（§12.1）", "")
			p.skipMember()
			continue
		}
		p.i++
		ty := p.parseTypeRef()
		nameTok := p.expectKind(Ident, "注解字段名")
		f := &FieldDecl{P: fp, Mod: TypeModifiers{Final: true}, Type: ty, Name: nameTok.Text}
		if p.atOp("=") {
			p.i++
			f.Init = p.parseExpr()
		} else {
			p.err(fp, synExpect, "注解字段必须有编译期常量初始化式（§12.1）", "")
		}
		if p.at(Semi) {
			p.i++
		}
		d.Fields = append(d.Fields, f)
	}
	p.expectKind(RBrace, "注解体结束")
	if p.at(Semi) {
		p.i++
	}
	return d
}

// skipMember 在注解体误写方法/字段时跳过整个成员，避免级联诊断。
func (p *parser) skipMember() {
	for !p.at(EOF) && !p.at(RBrace) {
		switch {
		case p.at(Semi):
			p.i++
			return
		case p.at(LBrace):
			depth := 0
			for !p.at(EOF) {
				if p.at(LBrace) {
					depth++
				} else if p.at(RBrace) {
					depth--
					if depth == 0 {
						p.i++
						break
					}
				}
				p.i++
			}
			if p.at(Semi) {
				p.i++
			}
			return
		default:
			p.i++
		}
	}
}
