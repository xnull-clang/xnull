package sema

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M2.5.1：类型声明语义检查（S2 §1/§2/§3/§4/§6/§7/§8） ----------
//
// 诊断码段位 TY-2xx（对象编程语义）：
//   TY-201 修饰符非法（位置错误、static 用 self、struct abstract/final 等）
//   TY-202 继承/协议结构错误（环、final 父类、父类种类错误、implements 目标错误）
//   TY-203 同签名方法冲突 / 字段隐藏（继承链唯一性，§2.5）
//   TY-204 结构体值规则（值字段限制 §3.2、递归值包含 §1.5、deinit 禁止 §3.1）
//   TY-205 协议形式错误（修饰符/字段/泛型，§4）
//   TY-206 枚举规则（项唯一/值唯一/形式混合/成员形式，§8）
//   TY-207 私有字段规范名（§7.4：private _name 拒绝、self._name 拒绝、裸 name 拒绝等）
//
// 本批次范围：声明级检查 + 类方法体的字段解析规则。switch 穷尽性、
// factory/singleton/extension、协议实现检查（§4.3）属后续批次。

// 诊断码。
const (
	TyModifier      = "TY-201"
	TyInherit       = "TY-202"
	TyOverride      = "TY-203"
	TyStructVal     = "TY-204"
	TyProtoForm     = "TY-205"
	TyEnumRule      = "TY-206"
	TyPrivField     = "TY-207"
	TyProtoImpl     = "TY-208" // 协议实现检查（§4.3）
	TyVisibility    = "TY-209" // 成员可见性（§7.3）
	TyNewAbstract   = "TY-210" // new abstract 类（§2.6）
	TyProtoMember   = "TY-211" // 协议变量只能调用协议方法（§4.4）
	TyPCTOR         = "TY-212" // 主构造器/final 字段赋值规则（§6.1/§6.3）
	TyEnumSwitch    = "TY-213" // 枚举 switch 穷尽性/项合法性（§8.5）
	TyStaticGen     = "TY-214" // 静态成员不得使用类类型参数（§13.4）
	TySingletonRO   = "TY-215" // singleton.instance 只读（§9）
	TySingletonNew  = "TY-216" // singleton/factory 不能 new（§9.4/§10.5）
	TyFactory       = "TY-217" // factory Target/命名规则（§10）
	TyEnumImmutable = "TY-218" // 数据枚举项不可变/不可 new（§8.3）
)

// builtinTypeNames 是预定义类型名（§1.1：类型名不得与之冲突）。
var builtinTypeNames = map[string]bool{
	"Bool": true, "Byte": true, "Short": true, "Int": true, "Long": true,
	"UByte": true, "UShort": true, "UInt": true, "ULong": true,
	"Int128": true, "UInt128": true, "Float": true, "Double": true, "Char": true,
	// S7 定宽标量（FFI 面）：作为类型名合法，避免签名/局部位置被误报未定义。
	"Int8": true, "Int16": true, "Int32": true, "Int64": true,
	"UInt8": true, "UInt16": true, "UInt32": true, "UInt64": true,
	"Float32": true, "Float64": true,
	"String": true, "Text": true, "Bytes": true, "StringBuilder": true,
	"Any": true, "Object": true, "List": true, "Map": true, "Set": true,
	"Result": true, "Range": true,
}

// typeInfo 是包内类型声明登记。
type typeInfo struct {
	kind    string // class/struct/protocol/enum
	mod     xfront.TypeModifiers
	class   *xfront.ClassDecl
	strct   *xfront.StructDecl
	proto   *xfront.ProtocolDecl
	enum    *xfront.EnumDecl
	single  *xfront.SingletonDecl
	factory *xfront.FactoryDecl
	fields  []*xfront.FieldDecl

	// 类成员缓存（首访填充；外部访问检查用，§7.4）
	canonPriv    map[string]bool
	srcToCanon   map[string]string
	publicFields map[string]string
}

// rejectInternalPolicyAnnos 拒绝 @arc/@gc（§15.1.2：实现内部注解，非源码入口）。
func (c *typeCheckCtx) rejectInternalPolicyAnnos(annos []*xfront.AnnotationNode) {
	for _, an := range annos {
		if an.Name == "arc" || an.Name == "gc" {
			c.errf(an.P, TyModifier, "源码不得使用 @"+an.Name+"（§15.1.2：实现内部策略注解，不是语言特性）", "")
		}
	}
}

// scalarValueType 判断内建标量是否值字段类型（§3.2）。
func scalarValueType(name string) bool {
	switch name {
	case "Bool", "Byte", "Short", "Int", "Long", "UByte", "UShort", "UInt",
		"ULong", "Int128", "UInt128", "Float", "Double", "Char":
		return true
	}
	return false
}

// typeCheckCtx 是类型声明检查上下文。
type typeCheckCtx struct {
	a            *analyzer
	types        map[string]*typeInfo
	topFuncs     map[string][]*xfront.TopFunc
	hasDeinit    map[string]bool
	selfCaptured map[string]bool
}

// checkTypeDecls 对整个编译单元做类型声明检查。
func (a *analyzer) checkTypeDecls(u *xfront.CompilationUnit) {
	c := &typeCheckCtx{a: a, types: map[string]*typeInfo{}, topFuncs: map[string][]*xfront.TopFunc{},
		hasDeinit: map[string]bool{}, selfCaptured: map[string]bool{}}
	a.tc = c
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			c.topFuncs[fn.Name] = append(c.topFuncs[fn.Name], fn)
		}
	}
	// 1) 登记 + 唯一性（§1.1）
	for _, d := range u.Decls {
		var info *typeInfo
		switch n := d.(type) {
		case *xfront.ClassDecl:
			info = &typeInfo{kind: "class", mod: n.Mod, class: n}
		case *xfront.StructDecl:
			info = &typeInfo{kind: "struct", mod: n.Mod, strct: n}
		case *xfront.ProtocolDecl:
			info = &typeInfo{kind: "protocol", proto: n}
		case *xfront.EnumDecl:
			info = &typeInfo{kind: "enum", enum: n}
		case *xfront.SingletonDecl:
			info = &typeInfo{kind: "singleton", mod: n.Mod, single: n}
		case *xfront.FactoryDecl:
			info = &typeInfo{kind: "factory", mod: n.Mod, factory: n}
		default:
			continue
		}
		name := c.declName(d)
		a.tops[name] = true // 类型名进入当前包顶层名空间（§3.3 第 2 级）
		switch n := d.(type) {
		case *xfront.ClassDecl:
			c.rejectInternalPolicyAnnos(n.Annos)
			for _, m := range n.Methods {
				if m.IsDeinit {
					c.hasDeinit[name] = true
				}
				if scanSelfCapture(m.Body) {
					c.selfCaptured[name] = true
				}
			}
			for _, ct := range n.Ctors {
				if scanSelfCapture(ct.Body) {
					c.selfCaptured[name] = true
				}
			}
		case *xfront.StructDecl:
			c.rejectInternalPolicyAnnos(n.Annos)
			// 结构体方法/构造器在闭包中捕获 self 被拒绝（§3.1）
			for _, m := range n.Methods {
				if scanSelfCapture(m.Body) {
					c.errf(n.P, TyStructVal, "结构体方法不得在闭包中捕获 self（§3.1：需要捕获接收者时改用 class）", "")
				}
			}
			for _, ct := range n.Ctors {
				if scanSelfCapture(ct.Body) {
					c.errf(n.P, TyStructVal, "结构体构造器不得在闭包中捕获 self（§3.1）", "")
				}
			}
		case *xfront.ProtocolDecl:
			c.rejectInternalPolicyAnnos(n.Annos)
		case *xfront.EnumDecl:
			c.rejectInternalPolicyAnnos(n.Annos)
		}
		if builtinTypeNames[name] {
			a.errf(d.Pos(), ResRedecl, "类型 `"+name+"` 与预定义类型名冲突（§1.1）", "换一个类型名")
			continue
		}
		if prev, dup := c.types[name]; dup {
			a.errf(d.Pos(), ResRedecl, "类型 `"+name+"` 在包内重复声明（已有 "+prev.kind+"，§1.1）", "换一个类型名")
			continue
		}
		c.types[name] = info
	}
	// 2) 逐声明检查
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.ClassDecl:
			c.checkClass(n)
		case *xfront.StructDecl:
			c.checkStruct(n)
		case *xfront.ProtocolDecl:
			c.checkProtocol(n)
		case *xfront.EnumDecl:
			c.checkEnum(n)
		case *xfront.SingletonDecl:
			c.checkSingleton(n)
		case *xfront.FactoryDecl:
			c.checkFactory(n)
		}
	}
}

func (c *typeCheckCtx) declName(d xfront.TopDecl) string {
	switch n := d.(type) {
	case *xfront.ClassDecl:
		return n.Name
	case *xfront.StructDecl:
		return n.Name
	case *xfront.ProtocolDecl:
		return n.Name
	case *xfront.EnumDecl:
		return n.Name
	case *xfront.SingletonDecl:
		return n.Name
	case *xfront.FactoryDecl:
		return n.Name
	}
	return ""
}

// errf 转发诊断。
func (c *typeCheckCtx) errf(p xfront.Pos, code, msg, hint string) { c.a.errf(p, code, msg, hint) }

// checkModifiers 检查修饰符位置合法性（§1.6）。
func (c *typeCheckCtx) checkModifiers(p xfront.Pos, m xfront.TypeModifiers, what string) {
	if m.Abstract && what != "class" {
		c.errf(p, TyModifier, what+" 不能是 abstract（§1.6：abstract 只修饰类）", "")
	}
	if m.Abstract && m.Final {
		c.errf(p, TyModifier, "abstract final 组合非法（§1.6）", "")
	}
}

// checkFieldDecl 检查字段声明级规则（§6.1/§7.4），返回规范化后的字段信息。
func (c *typeCheckCtx) checkFieldDecl(f *xfront.FieldDecl, owner string) {
	name := f.Name
	if strings.HasPrefix(name, "_") {
		// `_name` 形式（§7.4）
		if f.Mod.Vis == "private" {
			c.errf(f.P, TyPrivField, "`private` 与 `_` 前缀不能同时使用：`"+owner+"."+name+"`（§7.4）", "写 `private "+strings.TrimPrefix(name, "_")+"` 或裸 `_name`")
		}
		if f.Mod.Vis == "public" || f.Mod.Vis == "protected" {
			c.errf(f.P, TyPrivField, "`public`/`protected` 与 `_name` 同时出现是编译错误（§7.4）", "去掉可见性修饰符或改用 private name 形式")
		}
		if !validPrivateName(name) {
			c.errf(f.P, TyPrivField, "私有字段名 `"+name+"` 非法：`_` 后必须是 lowerCamelCase（§7.4）", "")
		}
		f.Canonical = name
	} else {
		if f.Mod.Vis == "private" {
			f.Canonical = "_" + name // 规范名统一 _name（§7.4）
		} else {
			f.Canonical = name
		}
	}
	if f.Mod.Const && f.Mod.Final {
		c.errf(f.P, TyModifier, "`const` 字段不能与 `final` 重复修饰（§1.6）", "")
	}
}

// validPrivateName 检查 `_name`：`_` 后首字符小写字母，且不含第二个 `_` 前缀段（§7.4）。
func validPrivateName(name string) bool {
	if len(name) < 2 {
		return false
	}
	r := []rune(name[1:])
	if !(r[0] >= 'a' && r[0] <= 'z') {
		return false // `_1`、`_X` 非法
	}
	if len(r) > 1 && r[1] == '_' {
		return false // `__x` 非法
	}
	return true
}

// materializePrimary 把主构造器参数物化为字段并作为构造器纳入检查（§6.1）。
func materializePrimary(pr *xfront.CtorDecl, fields *[]*xfront.FieldDecl, ctors *[]*xfront.CtorDecl) {
	if pr == nil {
		return
	}
	for _, p := range pr.Params {
		*fields = append([]*xfront.FieldDecl{{P: p.P, Type: p.Type, Name: p.Name,
			Canonical: p.Name, Mod: xfront.TypeModifiers{Final: p.Final}}}, *fields...)
	}
	*ctors = append(*ctors, pr)
}

// checkClass 类检查（§2）。
func (c *typeCheckCtx) checkClass(d *xfront.ClassDecl) {
	primaryFields := map[string]bool{}
	if d.Primary != nil {
		for _, p := range d.Primary.Params {
			primaryFields[p.Name] = true
			if !p.Final {
				c.errf(p.P, TyPCTOR,
					"主构造器参数 `"+p.Name+"` 必须是 final（§6.3）", "写成 final "+p.Name+"，或改用普通构造器")
			}
		}
		if len(d.Ctors) > 0 {
			c.errf(d.Primary.P, TyPCTOR,
				"主构造器不能与普通构造器混用（§6.3）", "删除主构造器或普通构造器其一")
		}
	}
	materializePrimary(d.Primary, &d.Fields, &d.Ctors)
	c.checkModifiers(d.P, d.Mod, "class")
	if d.Mod.Abstract && d.Mod.Final {
		return // 已报
	}
	// 父类
	if d.Base != nil {
		if !c.checkRefTarget(d.Base, "父类", true) {
			return
		}
		baseName := baseRefName(d.Base)
		if info, ok := c.types[baseName]; ok {
			if info.kind != "class" {
				c.errf(d.P, TyInherit, "父类 `"+baseName+"` 必须是 class（得到 "+info.kind+"，§2.5）", "")
			} else if info.mod.Final {
				c.errf(d.P, TyInherit, "父类 `"+baseName+"` 是 final，不能被继承（§2.5）", "")
			}
		}
		if c.hasInheritCycle(d.Name, baseName) {
			c.errf(d.P, TyInherit, "继承环：`"+d.Name+"` 与 `"+baseName+"` 互相继承（§1.5）", "")
		}
	}
	c.checkSuperOrder(d)
	// 协议目标
	for _, pr := range d.Protocols {
		if info, ok := c.types[lastSeg(pr.Qual)]; ok && info.kind != "protocol" {
			c.errf(d.P, TyInherit, "implements 目标 `"+lastSeg(pr.Qual)+"` 必须是 protocol（§2.1）", "")
		}
	}
	// 字段
	for _, f := range d.Fields {
		c.checkFieldDecl(f, d.Name)
	}
	// 继承链唯一性：字段隐藏、同签名方法（§2.5）
	ancestors := c.ancestorClasses(d)
	ownFields := map[string]bool{}
	for _, f := range d.Fields {
		ownFields[f.Canonical] = true
	}
	for _, anc := range ancestors {
		for _, af := range anc.class.Fields {
			if ownFields[af.Canonical] {
				c.errf(d.P, TyOverride, "字段 `"+af.Canonical+"` 在父类 `"+anc.class.Name+"` 中已声明：字段隐藏被拒绝（§2.5）", "")
			}
		}
		for _, am := range anc.class.Methods {
			for _, m := range d.Methods {
				if m.IsDeinit {
					continue // §6.4：派生类 deinit 合法，按链自动/显式调用父类
				}
				if m.Name == am.Name && m.IsDeinit == am.IsDeinit && sameSig(m.Params, am.Params) {
					c.errf(m.P, TyOverride, "方法 `"+m.Name+"` 与祖先类 `"+anc.class.Name+"` 的实例方法同签名：子类覆写被拒绝（§2.5）",
						"改用不同参数列表构成重载")
				}
			}
		}
	}
	c.checkFinalFieldAssignments(d, primaryFields)
	c.checkProtocolImpl(d)
	// deinit 规则（§6.4）：最多一个；不能 static；不能有参；不能有可见性
	deinits := 0
	for _, m := range d.Methods {
		if !m.IsDeinit {
			continue
		}
		deinits++
		if m.Mod.Static {
			c.errf(m.P, TyModifier, "deinit 不能是 static（§6.4）", "")
		}
		if len(m.Params) > 0 {
			c.errf(m.P, TyModifier, "deinit 不能有参数（§6.4）", "")
		}
		if !m.Void {
			c.errf(m.P, TyModifier, "deinit 必须返回 void（§6.4）", "")
		}
		if m.Mod.Vis != "" {
			c.errf(m.P, TyModifier, "deinit 不能有可见性修饰符（§6.4）", "")
		}
	}
	if deinits > 1 {
		c.errf(d.P, TyModifier, "每个类最多一个 deinit（§6.4）", "")
	}
	// 方法体
	c.walkClassBodies(d.Name, d.TypePars, d.Fields, d.Methods, d.Ctors)
}

// checkStruct 结构体检查（§3）。
func (c *typeCheckCtx) checkStruct(d *xfront.StructDecl) {
	if d.Primary != nil {
		c.errf(d.Primary.P, TyPCTOR, "结构体不能使用主构造器（§3.5/§6.3）", "改用普通结构体构造器")
	}
	materializePrimary(d.Primary, &d.Fields, &d.Ctors)
	c.checkModifiers(d.P, d.Mod, "struct")
	for _, f := range d.Fields {
		c.checkFieldDecl(f, d.Name)
		c.checkValueField(f, d.Name)
	}
	for _, m := range d.Methods {
		if m.IsDeinit {
			c.errf(m.P, TyStructVal, "结构体不能声明 deinit（§3.1）", "需要终结动作时使用 class")
		}
		if m.Mod.Static && !m.IsDeinit {
			// static 方法不能使用 self（§1.6）——walkClassBodies 中拦截
			_ = m
		}
	}
	c.walkClassBodies(d.Name, d.TypePars, d.Fields, d.Methods, d.Ctors)
}

// typeRefUsesParam 判断类型引用是否直接/嵌套使用给定类型参数（§13.4）。
func typeRefUsesParam(t xfront.TypeRef, pars map[string]bool) bool {
	switch ty := t.(type) {
	case nil:
		return false
	case *xfront.NamedType:
		if len(ty.Args) == 0 && len(ty.Qual) == 1 && pars[ty.Qual[0]] {
			return true
		}
		for _, a := range ty.Args {
			if typeRefUsesParam(a, pars) {
				return true
			}
		}
	case *xfront.SuffixedType:
		return typeRefUsesParam(ty.Base, pars)
	case *xfront.FuncTypeRef:
		if typeRefUsesParam(ty.Ret, pars) {
			return true
		}
		for _, p := range ty.Params {
			if typeRefUsesParam(p, pars) {
				return true
			}
		}
	case *xfront.TupleTypeRef:
		for _, e := range ty.Elems {
			if typeRefUsesParam(e, pars) {
				return true
			}
		}
	}
	return false
}

func (c *typeCheckCtx) isOwnerTypeParam(owner, name string) bool {
	info, ok := c.types[owner]
	if !ok || info.strct == nil {
		return false
	}
	for _, tp := range info.strct.TypePars {
		if tp == name {
			return true
		}
	}
	return false
}

// checkValueInstantiation 校验泛型结构体实例的每个实参都是值字段类型（§13.1/§3.2）。
func (c *typeCheckCtx) checkValueInstantiation(t xfront.TypeRef, p xfront.Pos, typePars map[string]bool) {
	switch ty := t.(type) {
	case nil:
		return
	case *xfront.NamedType:
		name := ty.Qual[len(ty.Qual)-1]
		if info, ok := c.types[name]; ok && info.kind == "struct" && len(ty.Args) > 0 {
			if len(ty.Args) != len(info.strct.TypePars) {
				c.errf(p, TyStructVal, "泛型结构体 `"+name+"` 类型实参数量不符（§13.1）", "")
			} else {
				for _, a := range ty.Args {
					if nt, ok := a.(*xfront.NamedType); ok && len(nt.Args) == 0 && len(nt.Qual) == 1 && typePars[nt.Qual[0]] {
						continue // 泛型上下文中的类型参数：实例化后检查
					}
					if !c.isValueTypeRef(a, name, map[string]bool{}) {
						c.errf(p, TyStructVal, "泛型结构体 `"+name+"` 的类型实参必须是值字段类型（§13.1/§3.2）", "")
					}
				}
			}
		}
		for _, a := range ty.Args {
			c.checkValueInstantiation(a, p, typePars)
		}
	case *xfront.SuffixedType:
		c.checkValueInstantiation(ty.Base, p, typePars)
	case *xfront.TupleTypeRef:
		for _, el := range ty.Elems {
			c.checkValueInstantiation(el, p, typePars)
		}
	}
}

// checkValueField 检查值字段限制与递归值包含（§3.2/§1.5）。
func (c *typeCheckCtx) checkValueField(f *xfront.FieldDecl, owner string) {
	if c.isValueTypeRef(f.Type, owner, map[string]bool{}) {
		return
	}
	c.errf(f.P, TyStructVal,
		fmt.Sprintf("结构体 `%s` 的字段 `%s` 不是值字段类型（§3.2：只允许标量/简单枚举/结构体/值元组及其可空形式）", owner, f.Name), "")
}

// isValueTypeRef 判断 TypeRef 是否值字段类型（§3.2）。
// visiting 防结构体互含环（值包含环 = 无限大小，§1.5）。
func (c *typeCheckCtx) isValueTypeRef(t xfront.TypeRef, owner string, visiting map[string]bool) bool {
	switch ty := t.(type) {
	case nil:
		return false
	case *xfront.NamedType:
		name := ty.Qual[len(ty.Qual)-1]
		if len(ty.Args) == 0 && c.isOwnerTypeParam(owner, name) {
			return true // 泛型结构体字段引用本声明的类型参数（§13.1，实例化时再查）
		}
		if len(ty.Args) > 0 {
			info, ok := c.types[name]
			if !ok || info.kind != "struct" || info.strct == nil || len(ty.Args) != len(info.strct.TypePars) {
				return false // List<T> 等非值字段类型，或泛型实参数量不符
			}
			for _, a := range ty.Args {
				if !c.isValueTypeRef(a, owner, visiting) {
					return false
				}
			}
			return true
		}
		if scalarValueType(name) {
			return true
		}
		if info, ok := c.types[name]; ok && info.kind == "struct" {
			if visiting[name] {
				return false // 值包含环（§1.5 无限大小）
			}
			visiting[name] = true
			for _, f := range info.strct.Fields {
				if !c.isValueTypeRef(f.Type, owner, visiting) {
					return false
				}
			}
			return true
		}
		if info, ok := c.types[name]; ok && info.kind == "enum" && !info.enum.IsData {
			return true // 简单枚举是值字段（§3.2）
		}
		return false
	case *xfront.SuffixedType:
		for _, s := range ty.Suffixes {
			if s == "[]" {
				return false
			}
		}
		return c.isValueTypeRef(ty.Base, owner, visiting) // T? 值可空内联（§3.2）
	case *xfront.TupleTypeRef:
		for _, el := range ty.Elems {
			if !c.isValueTypeRef(el, owner, visiting) {
				return false
			}
		}
		return true
	}
	return false
}

// checkProtocol 协议检查（§4）。
func (c *typeCheckCtx) checkProtocol(d *xfront.ProtocolDecl) {
	for _, ex := range d.Extends {
		if info, ok := c.types[lastSeg(ex.Qual)]; ok && info.kind != "protocol" {
			c.errf(d.P, TyInherit, "协议继承目标 `"+lastSeg(ex.Qual)+"` 必须是 protocol（§4.1）", "")
		}
	}
	if c.hasProtoCycle(d.Name, map[string]bool{}) {
		c.errf(d.P, TyInherit, "协议继承环：`"+d.Name+"`（§4.1）", "")
	}
	for _, sig := range d.Sigs {
		if sig.Mod.Vis == "private" || sig.Mod.Vis == "protected" {
			c.errf(sig.P, TyProtoForm, "协议方法不能是 private/protected（§4.2：默认公开）", "")
		}
		if sig.Mod.Static || sig.Mod.Final || sig.Mod.Abstract {
			c.errf(sig.P, TyProtoForm, "协议方法不能是 static/final/abstract（§4.2）", "")
		}
	}
}

// checkEnum 枚举检查（§8）。
func (c *typeCheckCtx) checkEnum(d *xfront.EnumDecl) {
	c.checkModifiers(d.P, d.Mod, "enum")
	if len(d.Items) == 0 {
		c.errf(d.P, TyEnumRule, "枚举至少一个项（§8.1）", "")
		return
	}
	itemNames := map[string]bool{}
	valueSeen := map[int64]bool{}
	next := int64(0)
	simpleCount, dataCount := 0, 0
	for _, it := range d.Items {
		if itemNames[it.Name] {
			c.errf(it.P, TyEnumRule, "枚举项 `"+it.Name+"` 重复（§8.4：项名唯一）", "")
			continue
		}
		itemNames[it.Name] = true
		if it.Args != nil {
			dataCount++
			continue
		}
		simpleCount++
		v := next
		if it.Value != nil {
			if iv, ok := constInt64(it.Value); ok {
				v = iv
			}
		}
		if valueSeen[v] {
			c.errf(it.P, TyEnumRule, "简单枚举底层值重复（§8.2：值唯一）", "")
		}
		valueSeen[v] = true
		next = v + 1 // 显式值设置当前项，后续裸项继续递增（§8.2）
	}
	if simpleCount > 0 && dataCount > 0 {
		c.errf(d.P, TyEnumRule, "同一枚举不能混合 `Item` 与 `Item(args)` 形式（§8.1）", "")
	}
	if d.IsData {
		if simpleCount > 0 {
			return // 混合形式已报
		}
		if len(d.Ctors) == 0 {
			c.errf(d.P, TyEnumRule, "数据枚举必须声明构造器（§8.3）", "")
		} else if len(d.Ctors) > 1 {
			c.errf(d.P, TyEnumRule, "数据枚举构造器与枚举同名且唯一（§8.3）", "")
		} else {
			// 项参数数量必须匹配构造器签名（§8.4）
			for _, it := range d.Items {
				if len(it.Args) != len(d.Ctors[0].Params) {
					c.errf(it.P, TyEnumRule,
						fmt.Sprintf("枚举项 `%s` 构造参数数量 %d 与构造器签名 %d 不匹配（§8.4）",
							it.Name, len(it.Args), len(d.Ctors[0].Params)), "")
				}
			}
		}
		enumFields := map[string]bool{}
		for _, f := range d.Fields {
			c.checkFieldDecl(f, d.Name)
			enumFields[f.Name] = true
			enumFields[f.Canonical] = true
			if !f.Mod.Final {
				c.errf(f.P, TyEnumRule, "数据枚举字段必须 final（§8.3：实例不可变）", "")
			}
		}
		for _, m := range d.Methods {
			if m.IsDeinit {
				continue
			}
			if enumWritesField(m.Body, enumFields) {
				c.errf(m.P, TyEnumImmutable, "数据枚举方法不能写字段（§8.3：实例不可变）", "")
			}
		}
	} else {
		if len(d.Fields) > 0 || len(d.Methods) > 0 || len(d.Ctors) > 0 {
			c.errf(d.P, TyEnumRule, "简单枚举只有项：不能声明字段、方法、构造器或 deinit（§8.2）", "")
		}
	}
}

// constInt64 求简单枚举项的整数字面量值（含前导 -）。
// ---------- BND-07/08：singleton / factory 登记与规则 ----------

func (c *typeCheckCtx) checkSingleton(d *xfront.SingletonDecl) {
	for _, f := range d.Fields {
		if f.Canonical == "" {
			f.Canonical = f.Name
		}
		if f.Name == "instance" || f.Canonical == "instance" {
			c.errf(f.P, TySingletonRO, "单例不得手动声明 `instance`（§9.4：自动提供）", "删除该字段")
		}
	}
	if len(d.Ctors) > 0 {
		c.errf(d.Ctors[0].P, TyModifier, "单例不能声明构造器（§9.4）", "改为字段初始化式")
	}
	c.walkClassBodies(d.Name, nil, d.Fields, d.Methods, d.Ctors)
}

func (c *typeCheckCtx) checkFactory(d *xfront.FactoryDecl) {
	nt, ok := d.Target.(*xfront.NamedType)
	if !ok || len(nt.Qual) != 1 {
		c.errf(d.P, TyFactory, "factory Target 必须是裸类型名（§10.1）", "写 `factory F for Type`")
		return
	}
	if len(nt.Args) > 0 {
		c.errf(d.P, TyFactory, "factory Target 不能写泛型实参（§10.1）", "写裸名，实参由工厂方法决定")
		return
	}
	name := nt.Qual[0]
	info, found := c.types[name]
	if !found {
		if c.a.imported[name] {
			return // 跨包可见 Target：具体成员可见性由跨包访问检查承担
		}
		c.errf(d.P, TyFactory, "factory Target `"+name+"` 未在本包声明或不可见（§10.1）", "检查 Target 名称与可见性")
		return
	}
	if info.kind != "class" && info.kind != "struct" {
		c.errf(d.P, TyFactory, "factory Target 必须是 class 或 struct（得到 "+info.kind+"，§10.1）", "")
	}
}

// ---------- PCTOR-01：super(...) 必须是构造器首个动作（§6.3） ----------

func isSuperCallStmt(s xfront.Stmt) bool {
	es, ok := s.(*xfront.ExprStmt)
	if !ok {
		return false
	}
	call, ok := es.X.(*xfront.Call)
	if !ok {
		return false
	}
	id, ok := call.Callee.(*xfront.IdentExpr)
	return ok && id.Name == "super"
}

func firstActionIsSuper(b *xfront.Block) bool {
	if b == nil {
		return false
	}
	for _, s := range b.Stmts {
		if _, empty := s.(*xfront.EmptyStmt); empty {
			continue
		}
		return isSuperCallStmt(s)
	}
	return false
}

func containsSuperCall(s xfront.Stmt) bool {
	if s == nil {
		return false
	}
	switch st := s.(type) {
	case *xfront.ExprStmt:
		return isSuperCallStmt(st)
	case *xfront.Block:
		if st != nil {
			for _, x := range st.Stmts {
				if containsSuperCall(x) {
					return true
				}
			}
		}
	case *xfront.IfStmt:
		return containsSuperCall(st.Then) || containsSuperCall(st.Else)
	case *xfront.WhileStmt:
		return containsSuperCall(st.Body)
	case *xfront.DoWhileStmt:
		return containsSuperCall(st.Body)
	case *xfront.ForStmt:
		return containsSuperCall(st.Body)
	case *xfront.SwitchStmt:
		for _, c := range st.Cases {
			for _, x := range c.Stmts {
				if containsSuperCall(x) {
					return true
				}
			}
		}
		if st.Default != nil {
			for _, x := range st.Default.Stmts {
				if containsSuperCall(x) {
					return true
				}
			}
		}
	case *xfront.DeferStmt:
		if st.Block != nil {
			return containsSuperCall(st.Block)
		}
		return containsSuperCall(st.Stmt)
	case *xfront.LabeledStmt:
		return containsSuperCall(st.Stmt)
	}
	return false
}

func (c *typeCheckCtx) checkSuperOrder(d *xfront.ClassDecl) {
	for _, ct := range d.Ctors {
		if ct == nil || ct.Body == nil {
			continue
		}
		if !containsSuperCall(ct.Body) {
			continue
		}
		if d.Base == nil {
			c.errf(ct.P, TyPCTOR, "没有显式父类时不能调用 super(...)（§6.3）", "删除 super(...) 调用")
			continue
		}
		if !firstActionIsSuper(ct.Body) {
			c.errf(ct.P, TyPCTOR, "super(...) 必须是构造器的首个动作（§6.3）", "把 super(...) 移到构造器体第一句")
		}
	}
}

// ---------- PCTOR-01：final 字段恰好赋值一次（§6.1/§6.3） ----------

func (c *typeCheckCtx) checkFinalFieldAssignments(d *xfront.ClassDecl, primaryFields map[string]bool) {
	checkCtor := func(ct *xfront.CtorDecl) {
		for _, f := range d.Fields {
			if !f.Mod.Final {
				continue
			}
			names := map[string]bool{f.Name: true, f.Canonical: true}
			n := 0
			if ct == d.Primary && primaryFields[f.Name] {
				n++
			}
			if f.Init != nil {
				n++
			}
			n += countFieldAssign(ct.Body, names)
			if n != 1 {
				c.errf(ct.P, TyPCTOR,
					"final 字段 `"+f.Name+"` 必须在构造器中恰好赋值一次（实际 "+itoa(n)+" 次，§6.1）", "删除重复赋值，或补上缺失赋值")
			}
		}
	}
	if len(d.Ctors) == 0 {
		for _, f := range d.Fields {
			if f.Mod.Final && f.Init == nil {
				c.errf(f.P, TyPCTOR, "final 字段 `"+f.Name+"` 必须初始化（§6.1）", "添加初始化式，或声明构造器赋值")
			}
		}
		return
	}
	for _, ct := range d.Ctors {
		checkCtor(ct)
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	if n < 0 {
		return "-" + itoa(-n)
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}

func targetIsField(t xfront.Expr, names map[string]bool) bool {
	switch n := t.(type) {
	case *xfront.IdentExpr:
		return names[n.Name]
	case *xfront.Member:
		return isSelfIdent(n.X) && names[n.Name]
	}
	return false
}

func enumWritesField(s xfront.Stmt, names map[string]bool) bool {
	if s == nil {
		return false
	}
	switch st := s.(type) {
	case *xfront.AssignStmt:
		return targetIsField(st.Target, names)
	case *xfront.IncDecStmt:
		return targetIsField(st.Target, names)
	case *xfront.Block:
		if st == nil {
			return false
		}
		for _, x := range st.Stmts {
			if enumWritesField(x, names) {
				return true
			}
		}
	case *xfront.IfStmt:
		return enumWritesField(st.Then, names) || enumWritesField(st.Else, names)
	case *xfront.WhileStmt:
		return enumWritesField(st.Body, names)
	case *xfront.DoWhileStmt:
		return enumWritesField(st.Body, names)
	case *xfront.ForStmt:
		return enumWritesField(st.Body, names)
	case *xfront.SwitchStmt:
		for _, c := range st.Cases {
			for _, x := range c.Stmts {
				if enumWritesField(x, names) {
					return true
				}
			}
		}
		if st.Default != nil {
			for _, x := range st.Default.Stmts {
				if enumWritesField(x, names) {
					return true
				}
			}
		}
	case *xfront.DeferStmt:
		if st.Block != nil {
			return enumWritesField(st.Block, names)
		}
		return enumWritesField(st.Stmt, names)
	case *xfront.LabeledStmt:
		return enumWritesField(st.Stmt, names)
	}
	return false
}

func countFieldAssign(s xfront.Stmt, names map[string]bool) int {
	if s == nil {
		return 0
	}
	n := 0
	switch st := s.(type) {
	case *xfront.AssignStmt:
		if targetIsField(st.Target, names) {
			n++
		}
	case *xfront.IncDecStmt:
		if targetIsField(st.Target, names) {
			n++
		}
	case *xfront.Block:
		if st == nil {
			return 0
		}
		for _, x := range st.Stmts {
			n += countFieldAssign(x, names)
		}
	case *xfront.IfStmt:
		if st == nil {
			return 0
		}
		n += countFieldAssign(st.Then, names)
		if st.Else != nil {
			n += countFieldAssign(st.Else, names)
		}
	case *xfront.WhileStmt:
		if st == nil {
			return 0
		}
		n += countFieldAssign(st.Body, names)
	case *xfront.DoWhileStmt:
		if st == nil {
			return 0
		}
		n += countFieldAssign(st.Body, names)
	case *xfront.ForStmt:
		if st == nil {
			return 0
		}
		n += countFieldAssign(st.Body, names)
	case *xfront.SwitchStmt:
		for _, c := range st.Cases {
			for _, x := range c.Stmts {
				n += countFieldAssign(x, names)
			}
		}
		if st.Default != nil {
			for _, x := range st.Default.Stmts {
				n += countFieldAssign(x, names)
			}
		}
	case *xfront.DeferStmt:
		if st == nil {
			return 0
		}
		if st.Block != nil {
			n += countFieldAssign(st.Block, names)
		} else if st.Stmt != nil {
			n += countFieldAssign(st.Stmt, names)
		}
	case *xfront.LabeledStmt:
		if st == nil {
			return 0
		}
		n += countFieldAssign(st.Stmt, names)
	}
	return n
}

// ---------- BND-05：协议实现检查（§4.3） ----------

type protoReq struct {
	owner string
	sig   *xfront.ProtocolSig
}

func methodParamsKey(params []*xfront.Param) string {
	parts := make([]string, len(params))
	for i, p := range params {
		parts[i] = typeKey(p.Type)
	}
	return strings.Join(parts, ",")
}

func methodSigKey(name string, params []*xfront.Param) string {
	return name + "(" + methodParamsKey(params) + ")"
}

func protoRetKey(sig *xfront.ProtocolSig) string {
	if sig.Void {
		return "void"
	}
	return typeKey(sig.Ret)
}

func methodRetKey(m *xfront.MethodDecl) string {
	if m.Void {
		return "void"
	}
	return typeKey(m.Ret)
}

func hasAnnotation(annos []*xfront.AnnotationNode, name string) bool {
	for _, a := range annos {
		if a.Name == name {
			return true
		}
	}
	return false
}

// checkProtocolImpl 校验 class 实现协议的全部方法（含父协议、签名、可见性、@Override）。
func (c *typeCheckCtx) checkProtocolImpl(d *xfront.ClassDecl) {
	reqs := map[string]protoReq{}
	var collect func(p *xfront.ProtocolDecl)
	collect = func(p *xfront.ProtocolDecl) {
		if p == nil {
			return
		}
		for _, ex := range p.Extends {
			if info, ok := c.types[lastSeg(ex.Qual)]; ok && info.kind == "protocol" {
				if info.proto != nil {
					collect(info.proto)
				}
			}
		}
		for _, sig := range p.Sigs {
			key := methodSigKey(sig.Name, sig.Params)
			if prev, ok := reqs[key]; ok {
				if protoRetKey(prev.sig) != protoRetKey(sig) {
					c.errf(d.P, TyProtoImpl,
						"协议方法 `"+sig.Name+"` 的返回类型冲突（"+prev.owner+" vs "+p.Name+"，§4.3）", "统一返回类型或拆分协议")
				}
				continue
			}
			reqs[key] = protoReq{owner: p.Name, sig: sig}
		}
	}
	for _, pr := range d.Protocols {
		if info, ok := c.types[lastSeg(pr.Qual)]; ok && info.kind == "protocol" && info.proto != nil {
			collect(info.proto)
		}
	}
	// @Override 不能标记类继承方法（类继承只复用，不存在覆写，§5.3）。
	for _, anc := range c.ancestorClasses(d) {
		for _, am := range anc.class.Methods {
			for _, m := range d.Methods {
				if hasAnnotation(m.Annos, "Override") && m.Name == am.Name && sameSig(m.Params, am.Params) {
					c.errf(m.P, TyProtoImpl,
						"@Override 不能标记父类方法 `"+am.Name+"`：类继承只复用，不存在覆写（§5.3）", "删除注解")
				}
			}
		}
	}
	if len(reqs) == 0 {
		// 无协议实现时 @Override 仍非法（类继承不存在覆写）。
		for _, m := range d.Methods {
			if hasAnnotation(m.Annos, "Override") {
				c.errf(m.P, TyProtoImpl, "@Override 没有对应的协议方法（§4.3）", "删除注解，或声明 implements 并提供同签名方法")
			}
		}
		return
	}

	type implMethod struct {
		m     *xfront.MethodDecl
		owner string
	}
	methods := map[string]implMethod{}
	for _, m := range d.Methods {
		if m.IsDeinit {
			continue
		}
		methods[methodSigKey(m.Name, m.Params)] = implMethod{m: m, owner: d.Name}
	}
	for _, anc := range c.ancestorClasses(d) {
		for _, m := range anc.class.Methods {
			if m.IsDeinit || m.Mod.Vis == "private" {
				continue
			}
			key := methodSigKey(m.Name, m.Params)
			if _, exists := methods[key]; !exists {
				methods[key] = implMethod{m: m, owner: anc.class.Name}
			}
		}
	}

	for key, req := range reqs {
		im, ok := methods[key]
		if !ok {
			c.errf(d.P, TyProtoImpl,
				"类 `"+d.Name+"` 未实现协议 `"+req.owner+"` 的方法 `"+req.sig.Name+"`（§4.3）", "补充同签名公开实例方法")
			continue
		}
		if im.m.Mod.Static || im.m.IsDeinit {
			c.errf(im.m.P, TyProtoImpl,
				"协议方法 `"+req.sig.Name+"` 必须由实例方法实现（§4.3）", "去掉 static")
			continue
		}
		if im.m.Mod.Vis != "" && im.m.Mod.Vis != "public" {
			c.errf(im.m.P, TyProtoImpl,
				"协议方法 `"+req.sig.Name+"` 的实现必须公开（§4.3）", "去掉 private/protected")
			continue
		}
		if methodRetKey(im.m) != protoRetKey(req.sig) {
			c.errf(im.m.P, TyProtoImpl,
				"协议方法 `"+req.sig.Name+"` 返回类型不符：期望 "+protoRetKey(req.sig)+"，实际 "+methodRetKey(im.m)+"（§4.3）", "")
		}
	}

	for _, m := range d.Methods {
		if !hasAnnotation(m.Annos, "Override") {
			continue
		}
		key := methodSigKey(m.Name, m.Params)
		req, ok := reqs[key]
		if !ok {
			c.errf(m.P, TyProtoImpl, "@Override 未对应任何协议方法（§4.3）", "删除注解，或改为正确的协议方法签名")
			continue
		}
		if methodRetKey(m) != protoRetKey(req.sig) {
			c.errf(m.P, TyProtoImpl,
				"@Override 方法 `"+m.Name+"` 返回类型与协议不符（§4.3）", "")
		}
	}
}

// protocolHasMethod 判断协议（含父协议）是否声明了该方法（§4.4）。
func (c *typeCheckCtx) protocolHasMethod(name, method string) bool {
	seen := map[string]bool{}
	var visit func(string) bool
	visit = func(n string) bool {
		if seen[n] {
			return false
		}
		seen[n] = true
		info, ok := c.types[n]
		if !ok || info.kind != "protocol" || info.proto == nil {
			return false
		}
		for _, sig := range info.proto.Sigs {
			if sig.Name == method {
				return true
			}
		}
		for _, ex := range info.proto.Extends {
			if visit(lastSeg(ex.Qual)) {
				return true
			}
		}
		return false
	}
	return visit(name)
}

func constInt64(e xfront.Expr) (int64, bool) {
	switch n := e.(type) {
	case *xfront.IntLitExpr:
		var v int64
		_, err := fmt.Sscanf(n.Text, "%d", &v)
		return v, err == nil
	case *xfront.Unary:
		if n.Op == "-" {
			if v, ok := constInt64(n.X); ok {
				return -v, true
			}
		}
	}
	return 0, false
}

// checkRefTarget 解析继承目标存在性与种类（返回 false 表示已报错）。
func (c *typeCheckCtx) checkRefTarget(t xfront.TypeRef, what string, mustClass bool) bool {
	name := baseRefName(t)
	if builtinTypeNames[name] {
		c.errf(t.Pos(), TyInherit, what+" `"+name+"` 是预定义类型，不能作为继承目标（§2.1：Object 是隐式引用根）", "")
		return false
	}
	if _, ok := c.types[name]; !ok {
		c.errf(t.Pos(), ResUndefined, what+" `"+name+"` 未在本包声明（跨包继承需 import，§1.4）", "")
		return false
	}
	return true
}

func baseRefName(t xfront.TypeRef) string {
	if nt, ok := t.(*xfront.NamedType); ok {
		return lastSeg(nt.Qual)
	}
	return "<err>"
}

func lastSeg(q []string) string { return q[len(q)-1] }

func sameSig(a, b []*xfront.Param) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if typeKey(a[i].Type) != typeKey(b[i].Type) {
			return false
		}
	}
	return true
}

// ancestorClasses 沿父类链收集祖先（环已另行报错，此处防死循环）。
func (c *typeCheckCtx) ancestorClasses(d *xfront.ClassDecl) []*typeInfo {
	var out []*typeInfo
	seen := map[string]bool{d.Name: true}
	base := d.Base
	for base != nil {
		name := baseRefName(base)
		if seen[name] {
			break
		}
		seen[name] = true
		info, ok := c.types[name]
		if !ok || info.kind != "class" {
			break
		}
		out = append(out, info)
		base = info.class.Base
	}
	return out
}

// hasInheritCycle 判断 baseName 的继承链是否回到 name。
func (c *typeCheckCtx) hasInheritCycle(name, baseName string) bool {
	cur := baseName
	for i := 0; i < 64; i++ {
		if cur == "" {
			return false
		}
		if cur == name {
			return true
		}
		info, ok := c.types[cur]
		if !ok || info.kind != "class" || info.class.Base == nil {
			return false
		}
		cur = baseRefName(info.class.Base)
	}
	return false
}

// hasProtoCycle 协议继承环检测（§4.1）。
func (c *typeCheckCtx) hasProtoCycle(name string, visiting map[string]bool) bool {
	if visiting[name] {
		return true
	}
	info, ok := c.types[name]
	if !ok || info.kind != "protocol" {
		return false
	}
	visiting[name] = true
	for _, ex := range info.proto.Extends {
		if c.hasProtoCycle(lastSeg(ex.Qual), visiting) {
			return true
		}
	}
	delete(visiting, name)
	return false
}

// ---------- 类方法体的字段解析规则（§5.8/§7.4） ----------

// classCtx 是方法体遍历的类上下文。
type classCtx struct {
	className  string
	srcToCanon map[string]string // 声明名 → 规范名（仅 private name 形式；规范名 != 声明名）
	canonPriv  map[string]bool   // 私有字段规范名集合（含 _name 形式）
	instance   bool              // 是否实例方法（static 方法禁用 self）
}

// isSelfIdent 判断表达式是否为 `self`。
func isSelfIdent(x xfront.Expr) bool {
	id, ok := x.(*xfront.IdentExpr)
	return ok && id.Name == "self"
}

// walkClassBodies 遍历类的全部方法体与构造器体（含字段解析规则）。
func (c *typeCheckCtx) walkClassBodies(className string, typeParams []string, fields []*xfront.FieldDecl,
	methods []*xfront.MethodDecl, ctors []*xfront.CtorDecl) {
	e := &tyenv{a: c.a, vars: map[string]string{}, funcs: c.topFuncs, fields: map[string]string{}, typePars: map[string]bool{}}
	e.curFunc = ""
	for _, tp := range typeParams {
		e.typePars[tp] = true
	}
	// 类字段表：裸规范名解析（实例与静态上下文都可引用静态字段；实例字段仅实例方法）
	fieldType := map[string]string{}
	for _, f := range fields {
		fieldType[f.Canonical] = typeKey(f.Type)
	}
	ctx := &classCtx{className: className, srcToCanon: map[string]string{}, canonPriv: map[string]bool{}}
	for _, f := range fields {
		if f.Canonical != f.Name {
			ctx.srcToCanon[f.Name] = f.Canonical
		}
		if f.Mod.Vis == "private" || strings.HasPrefix(f.Name, "_") {
			ctx.canonPriv[f.Canonical] = true
		}
	}
	// 字段类型与初始化式（§6.1/§10.1：Result 可以出现在字段）。
	e.fnKind, e.ret = "fieldinit", ""
	for _, f := range fields {
		e.checkResultType(f.Type, f.P)
		e.checkTypeParamRef(f.Type, f.P)
		if f.Mod.Static && typeRefUsesParam(f.Type, e.typePars) {
			c.errf(f.P, TyStaticGen, "静态字段 `"+f.Name+"` 不得使用类类型参数（§13.4）", "改用实例字段，或实例化具体类型")
		}
		if f.Init == nil {
			continue
		}
		k := typeKey(f.Type)
		it := e.inferExpected(f.Init, k)
		if k != "" && !assignable(it, k) {
			e.errf(f.Init.Pos(), assignDiag(it, k),
				fmt.Sprintf("字段 `%s` 的初始化式类型 %s 不能赋给 %s（§2.6）", f.Name, describeKey(it), k),
				hintFor(it, k))
		}
	}
	// 实例方法、deinit 与构造器
	for _, m := range methods {
		ctx.instance = !m.Mod.Static
		e.cls = ctx
		retKey := "void"
		if !m.Void && m.Ret != nil {
			retKey = typeKey(m.Ret)
		}
		e.fnKind, e.ret = "method", retKey
		if m.IsDeinit {
			e.fnKind, e.ret = "deinit", "void"
		}
		e.checkResultType(m.Ret, m.P)
		e.checkTypeParamRef(m.Ret, m.P)
		if m.Mod.Static && typeRefUsesParam(m.Ret, e.typePars) {
			c.errf(m.P, TyStaticGen, "静态方法 `"+m.Name+"` 不得使用类类型参数（§13.4）", "改用实例方法，或实例化具体类型")
		}
		e.vars = map[string]string{}
		if ctx.instance {
			e.vars["self"] = className
		}
		for name, tk := range fieldType {
			e.vars[name] = tk
		}
		for _, p := range m.Params {
			e.checkResultType(p.Type, p.P)
			e.checkTypeParamRef(p.Type, p.P)
			if m.Mod.Static && typeRefUsesParam(p.Type, e.typePars) {
				c.errf(p.P, TyStaticGen, "静态方法 `"+m.Name+"` 的参数不得使用类类型参数（§13.4）", "")
			}
			if ctx.canonPriv[p.Name] {
				c.errf(p.P, TyPrivField, "参数 `"+p.Name+"` 与类私有字段规范名冲突（§7.4：局部变量、参数不能声明为 _name）", "")
			}
			e.vars[p.Name] = typeKey(p.Type)
		}
		e.walkFunc(m.Body, retKey)
	}
	for _, ct := range ctors {
		ctx.instance = true
		e.cls = ctx
		e.fnKind, e.ret = "ctor", "void"
		e.vars = map[string]string{"self": className}
		for name, tk := range fieldType {
			e.vars[name] = tk
		}
		for _, p := range ct.Params {
			e.checkResultType(p.Type, p.P)
			e.checkTypeParamRef(p.Type, p.P)
			if ctx.canonPriv[p.Name] {
				c.errf(p.P, TyPrivField, "参数 `"+p.Name+"` 与类私有字段规范名冲突（§7.4）", "")
			}
			e.vars[p.Name] = typeKey(p.Type)
		}
		e.walkFunc(ct.Body, "void")
	}
	e.cls = nil
}
