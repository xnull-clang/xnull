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
	TyModifier       = "TY-201"
	TyInherit        = "TY-202"
	TyOverride       = "TY-203"
	TyStructVal      = "TY-204"
	TyProtoForm      = "TY-205"
	TyEnumRule       = "TY-206"
	TyPrivField      = "TY-207"
	TyProtoImpl      = "TY-208" // 协议实现检查（§4.3）
	TyVisibility     = "TY-209" // 成员可见性（§7.3）
	TyNewAbstract    = "TY-210" // new abstract 类（§2.6）
	TyProtoMember    = "TY-211" // 协议变量只能调用协议方法（§4.4）
	TyPCTOR          = "TY-212" // 主构造器/final 字段赋值规则（§6.1/§6.3）
	TyEnumSwitch     = "TY-213" // 枚举 switch 穷尽性/项合法性（§8.5）
	TyStaticGen      = "TY-214" // 静态成员不得使用类类型参数（§13.4）
	TySingletonRO    = "TY-215" // singleton.instance 只读（§9）
	TySingletonNew   = "TY-216" // singleton/factory 不能 new（§9.4/§10.5）
	TyFactory        = "TY-217" // factory Target/命名规则（§10）
	TyEnumImmutable  = "TY-218" // 数据枚举项不可变/不可 new（§8.3）
	TyFactoryAccess  = "TY-219" // 跨包 factory 私有成员访问（§10.3）
	TyFactoryRet     = "TY-220" // factory 方法返回类型（§10.2）
	TyFactorySelf    = "TY-221" // factory 方法禁用 self/super（§10.2）
	TySingletonRule  = "TY-222" // singleton abstract/前向引用（§9）
	TyAnnotation     = "TY-223" // 注解声明/使用/目标（§12）
	TyFinalWrite     = "TY-224" // final 字段构造后写入（§6.1）
	TyExtension      = "TY-225" // extension 目标限制（§11）
	TyNewKind        = "TY-226" // new 非 class 类型（§2.7/§4.1/§8.3）
	TyTasksBlock     = "TY-227" // 任务 API 必须在 @tasks 块内（S5 §2.3）
	TySyncRule       = "TY-228" // 同步原语约束（S5 §7/SYNC-01）
	TyXdkUnsupported = "TY-229" // XDK API 未实现/签名未冻结（S6 §4）
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
	anno    *xfront.AnnotationDecl
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
		"ULong", "Int128", "UInt128", "Float", "Double", "Char",
		// S7 §3.2 标量映射：定宽标量同样是值字段类型（layout(c) 字段使用）。
		"Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64",
		"Float32", "Float64":
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
	singleOrder  map[string]int
}

// checkTypeDecls 对整个编译单元做类型声明检查。
func (a *analyzer) checkTypeDecls(u *xfront.CompilationUnit) {
	c := &typeCheckCtx{a: a, types: map[string]*typeInfo{}, topFuncs: map[string][]*xfront.TopFunc{},
		hasDeinit: map[string]bool{}, selfCaptured: map[string]bool{}, singleOrder: map[string]int{}}
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
		case *xfront.AnnotationDecl:
			info = &typeInfo{kind: "annotation", mod: n.Mod, anno: n}
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
	c.registerXdkErrors()
	c.registerXdkConcurrency()
	for i, d := range u.Decls {
		if s, ok := d.(*xfront.SingletonDecl); ok {
			c.singleOrder[s.Name] = i
		}
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
		case *xfront.AnnotationDecl:
			c.checkAnnotationDecl(n)
		case *xfront.ExtensionDecl:
			c.checkExtension(n)
		}
	}
	c.checkAllAnnotations(u)
	c.checkExtensions(u)
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
	case *xfront.AnnotationDecl:
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
		base := fieldBaseName(f)
		if ownFields[base] {
			c.errf(f.P, TyOverride, "字段基名 `"+base+"` 在同一类中重复（§7.4：基名唯一）", "")
		}
		ownFields[base] = true
	}
	for _, anc := range ancestors {
		for _, af := range anc.class.Fields {
			if ownFields[fieldBaseName(af)] {
				c.errf(d.P, TyOverride, "字段基名 `"+fieldBaseName(af)+"` 在父类 `"+anc.class.Name+"` 中已声明：字段隐藏被拒绝（§2.5/§7.4）", "")
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

func fieldBaseName(f *xfront.FieldDecl) string {
	n := f.Canonical
	if n == "" {
		n = f.Name
	}
	return strings.TrimPrefix(n, "_")
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
func (c *typeCheckCtx) checkExtension(d *xfront.ExtensionDecl) {
	nt, ok := d.Target.(*xfront.NamedType)
	if !ok || len(nt.Qual) != 1 {
		c.errf(d.P, TyExtension, "extension Target 必须是裸类型名（§11.1）", "")
		return
	}
	if len(nt.Args) > 0 {
		c.errf(d.P, TyExtension, "extension Target 不能写泛型实参（§11.1）", "写裸类型名")
		return
	}
	name := nt.Qual[0]
	if builtinTypeNames[name] || scalarValueType(name) {
		c.errf(nt.P, TyExtension, "extension 不能扩展预定义类型 `"+name+"`（§11.1）", "改为同包 class/struct")
		return
	}
	info, found := c.types[name]
	if !found {
		c.errf(nt.P, TyExtension, "extension 不能跨包扩展或 Target `"+name+"` 未声明（§11.1/§11.4）", "")
		return
	}
	// 跨包扩展拒绝（导入路径末段与 Target 同名视为跨包来源）。
	for _, p := range c.a.importPaths {
		if len(p) > 0 && strings.EqualFold(p[len(p)-1], name) {
			c.errf(nt.P, TyExtension, "extension 不能跨包扩展 `"+name+"`（§11.4）", "在目标所在包内声明 extension")
			return
		}
	}
	allowed := info.kind == "class" || info.kind == "struct" || info.kind == "singleton" ||
		(info.kind == "enum" && info.enum != nil && info.enum.IsData)
	if !allowed {
		c.errf(nt.P, TyExtension, "extension Target 必须是同包非泛型 class/struct/singleton/数据 enum（得到 "+info.kind+"，§11.1）", "")
	}
}

func (c *typeCheckCtx) extensionMethodKeys(info *typeInfo) map[string]bool {
	out := map[string]bool{}
	if info.class != nil {
		for _, m := range info.class.Methods {
			if !m.IsDeinit {
				out[methodSigKey(m.Name, m.Params)] = true
			}
		}
		for _, anc := range c.ancestorClasses(info.class) {
			for _, m := range anc.class.Methods {
				if !m.IsDeinit {
					out[methodSigKey(m.Name, m.Params)] = true
				}
			}
		}
	}
	if info.strct != nil {
		for _, m := range info.strct.Methods {
			out[methodSigKey(m.Name, m.Params)] = true
		}
	}
	return out
}

func (c *typeCheckCtx) extensionDenied(info *typeInfo) map[string]bool {
	denied := map[string]bool{}
	if info.class != nil {
		for _, f := range info.class.Fields {
			if fieldVisibility(f) != "public" {
				denied[f.Name] = true
				denied[f.Canonical] = true
			}
		}
		for _, m := range info.class.Methods {
			if m.Mod.Vis == "private" || m.Mod.Vis == "protected" {
				denied[m.Name] = true
			}
		}
	}
	return denied
}

func (c *typeCheckCtx) checkExtensions(u *xfront.CompilationUnit) {
	seen := map[string]bool{}
	extMethods := map[string]map[string]bool{}
	for _, d := range u.Decls {
		ext, ok := d.(*xfront.ExtensionDecl)
		if !ok {
			continue
		}
		nt, ok := ext.Target.(*xfront.NamedType)
		if !ok || len(nt.Qual) != 1 || len(nt.Args) > 0 {
			continue
		}
		name := nt.Qual[0]
		info, found := c.types[name]
		if !found {
			continue
		}
		if seen[name] {
			c.errf(ext.P, TyExtension, "同一类型 `"+name+"` 存在重复 extension 声明（§11.1）", "合并到一个 extension")
		}
		seen[name] = true
		if extMethods[name] == nil {
			extMethods[name] = map[string]bool{}
		}
		existing := c.extensionMethodKeys(info)
		denied := c.extensionDenied(info)
		for _, m := range ext.Methods {
			key := methodSigKey(m.Name, m.Params)
			if existing[key] || extMethods[name][key] {
				c.errf(m.P, TyExtension, "extension 方法 `"+m.Name+"` 与已有/继承/其他扩展同签名（§11.1/§11.2）", "改名或改参数列表")
			}
			extMethods[name][key] = true
			if stmtUsesDeniedMember(m.Body, denied) {
				c.errf(m.P, TyExtension, "extension 方法只能访问目标公开成员（§11.3）", "")
			}
		}
	}
	// 子类不能声明与扩展方法同签名的方法（§11.2）。
	for _, d := range u.Decls {
		cls, ok := d.(*xfront.ClassDecl)
		if !ok {
			continue
		}
		for _, anc := range c.ancestorClasses(cls) {
			keys := extMethods[anc.class.Name]
			if keys == nil {
				continue
			}
			for _, m := range cls.Methods {
				if keys[methodSigKey(m.Name, m.Params)] {
					c.errf(m.P, TyOverride, "子类方法 `"+m.Name+"` 覆写了扩展方法（§11.2）", "改名或改参数列表")
				}
			}
		}
	}
}

func stmtUsesDeniedMember(s xfront.Stmt, denied map[string]bool) bool {
	switch st := s.(type) {
	case nil:
		return false
	case *xfront.ExprStmt:
		return exprUsesDeniedMember(st.X, denied)
	case *xfront.AssignStmt:
		return exprUsesDeniedMember(st.Target, denied) || exprUsesDeniedMember(st.Value, denied)
	case *xfront.LocalDeclStmt:
		return exprUsesDeniedMember(st.Init, denied)
	case *xfront.ReturnStmt:
		return exprUsesDeniedMember(st.Value, denied)
	case *xfront.Block:
		for _, x := range st.Stmts {
			if stmtUsesDeniedMember(x, denied) {
				return true
			}
		}
	case *xfront.IfStmt:
		return stmtUsesDeniedMember(st.Then, denied) || stmtUsesDeniedMember(st.Else, denied)
	case *xfront.WhileStmt:
		return stmtUsesDeniedMember(st.Body, denied)
	case *xfront.DoWhileStmt:
		return stmtUsesDeniedMember(st.Body, denied)
	case *xfront.ForStmt:
		return stmtUsesDeniedMember(st.Body, denied)
	case *xfront.DeferStmt:
		if st.Block != nil {
			return stmtUsesDeniedMember(st.Block, denied)
		}
		return stmtUsesDeniedMember(st.Stmt, denied)
	case *xfront.LabeledStmt:
		return stmtUsesDeniedMember(st.Stmt, denied)
	}
	return false
}

func exprUsesDeniedMember(e xfront.Expr, denied map[string]bool) bool {
	switch n := e.(type) {
	case nil:
		return false
	case *xfront.Member:
		if isSelfIdent(n.X) && denied[n.Name] {
			return true
		}
		return exprUsesDeniedMember(n.X, denied)
	case *xfront.Paren:
		return exprUsesDeniedMember(n.X, denied)
	case *xfront.Unary:
		return exprUsesDeniedMember(n.X, denied)
	case *xfront.Binary:
		return exprUsesDeniedMember(n.L, denied) || exprUsesDeniedMember(n.R, denied)
	case *xfront.Call:
		if exprUsesDeniedMember(n.Callee, denied) {
			return true
		}
		for _, a := range n.Args {
			if exprUsesDeniedMember(a, denied) {
				return true
			}
		}
	case *xfront.Tuple:
		for _, el := range n.Elems {
			if exprUsesDeniedMember(el, denied) {
				return true
			}
		}
	case *xfront.Index:
		return exprUsesDeniedMember(n.X, denied) || exprUsesDeniedMember(n.Idx, denied)
	case *xfront.StrLitExpr:
		for _, p := range n.Parts {
			if p.Expr != nil && exprUsesDeniedMember(p.Expr, denied) {
				return true
			}
		}
	}
	return false
}

// registerXdkErrors 注册 xdk.errors 的 ErrorKind 枚举与 Error 协议（S4 §2/§3）。
func (c *typeCheckCtx) registerXdkErrors() {
	if !c.a.imported["Error"] && !c.a.imported["ErrorKind"] {
		return
	}
	if _, ok := c.types["ErrorKind"]; !ok {
		items := []string{
			"InvalidArgument", "NotFound", "AlreadyExists", "PermissionDenied",
			"Io", "Network", "Timeout", "Cancelled", "Busy", "Unavailable",
			"DataCorrupted", "Unsupported", "OutOfMemory", "Internal",
		}
		e := &xfront.EnumDecl{Name: "ErrorKind"}
		for _, n := range items {
			e.Items = append(e.Items, &xfront.EnumItem{Name: n})
		}
		c.types["ErrorKind"] = &typeInfo{kind: "enum", enum: e}
		c.a.tops["ErrorKind"] = true
	}
	if _, ok := c.types["Error"]; !ok {
		p := &xfront.ProtocolDecl{Name: "Error"}
		p.Sigs = []*xfront.ProtocolSig{
			{Name: "kind", Ret: &xfront.NamedType{Qual: []string{"ErrorKind"}}},
			{Name: "describe", Ret: &xfront.NamedType{Qual: []string{"String"}}},
		}
		c.types["Error"] = &typeInfo{kind: "protocol", proto: p}
		c.a.tops["Error"] = true
	}
}

// registerXdkConcurrency 注册 xdk.tasks/xdk.sync 语言面类型（S5 §3/§7）。
func (c *typeCheckCtx) registerXdkConcurrency() {
	names := []string{"Task", "TaskGroup", "Context", "CancelToken", "TaskError", "CancelledError",
		"Channel", "Mutex", "AtomicInt", "AtomicBool", "AtomicRef"}
	for _, n := range names {
		if !c.a.imported[n] {
			continue
		}
		if _, ok := c.types[n]; ok {
			continue
		}
		c.types[n] = &typeInfo{kind: "xdk"}
		c.a.tops[n] = true
	}
}

// checkSyncTypeRef 校验 Mutex<T>/AtomicRef<T> 的类型实参（S5 §7.2）。
func (c *typeCheckCtx) checkSyncTypeRef(ty *xfront.NamedType) {
	name := ty.Qual[len(ty.Qual)-1]
	if len(ty.Args) != 1 {
		return
	}
	c.checkSyncTypeArg(name, typeKey(ty.Args[0]), ty.P)
}

// checkSyncTypeArg 校验同步原语类型实参；构造器调用与类型位置共用。
func (c *typeCheckCtx) checkSyncTypeArg(name, arg string, p xfront.Pos) {
	switch name {
	case "Mutex":
		if info, ok := c.types[arg]; ok && info.kind == "struct" {
			c.errf(p, TySyncRule, "Mutex<T> 的 T 不能是 struct（S5 §7.2：值复制会绕过互斥）", "改用 class 或标量")
		}
	case "AtomicRef":
		if !isReferenceTypeKey(arg, c.types) {
			c.errf(p, TySyncRule, "AtomicRef<T> 的 T 必须是引用类型（S6 §3-c-1）", "改用 class/协议/容器等引用类型")
		}
	}
}

func isReferenceTypeKey(key string, types map[string]*typeInfo) bool {
	k := unwrapTypeKey(key)
	switch k {
	case "String", "Text", "Bytes", "StringBuilder", "Any", "Object":
		return true
	}
	if strings.HasSuffix(k, "[]") || strings.HasPrefix(k, "List<") ||
		strings.HasPrefix(k, "Map<") || strings.HasPrefix(k, "Set<") ||
		strings.HasPrefix(k, "Result<") || strings.HasPrefix(k, "(") {
		return true
	}
	if info, ok := types[k]; ok {
		switch info.kind {
		case "class", "protocol", "singleton", "annotation":
			return true
		case "enum":
			return info.enum != nil && info.enum.IsData
		}
	}
	return false
}

// ---------- ANN-01：注解声明与使用（§12） ----------

var builtinAnnotations = map[string]bool{
	"ReadOnly": true, "Override": true, "WriteOnly": true, "Target": true,
	"Retention": true, "Repeatable": true, "Deprecated": true, "SuppressWarnings": true,
	"tasks": true, "arena": true, "Immediate": true, "NoAlloc": true, "Pure": true, "Sendable": true,
}

func isConstExpr(e xfront.Expr) bool {
	switch n := e.(type) {
	case *xfront.IntLitExpr, *xfront.FloatLitExpr, *xfront.CharLitExpr, *xfront.BoolLit, *xfront.StrLitExpr:
		return true
	case *xfront.Paren:
		return isConstExpr(n.X)
	case *xfront.Unary:
		return isConstExpr(n.X)
	case *xfront.Binary:
		return isConstExpr(n.L) && isConstExpr(n.R)
	case *xfront.Member:
		_, ok := n.X.(*xfront.IdentExpr)
		return ok // 简单枚举项常量
	}
	return false
}

func constExprType(e xfront.Expr) texpr {
	switch n := e.(type) {
	case *xfront.IntLitExpr:
		k := "Int"
		switch n.Suffix {
		case "L":
			k = "Long"
		case "U":
			k = "UInt"
		case "UL":
			k = "ULong"
		}
		return texpr{key: k, lit: 1}
	case *xfront.FloatLitExpr:
		if n.HasSuffixF {
			return texpr{key: "Float", lit: 2}
		}
		return texpr{key: "Double", lit: 2}
	case *xfront.CharLitExpr:
		return texpr{key: "Char"}
	case *xfront.BoolLit:
		return texpr{key: "Bool"}
	case *xfront.StrLitExpr:
		return texpr{key: "String", lit: 3}
	case *xfront.Paren:
		return constExprType(n.X)
	case *xfront.Unary:
		return constExprType(n.X)
	}
	return texpr{}
}

func (c *typeCheckCtx) checkAnnotationDecl(d *xfront.AnnotationDecl) {
	for _, f := range d.Fields {
		if !f.Mod.Final {
			c.errf(f.P, TyAnnotation, "注解字段必须 final（§12.1）", "")
		}
		if f.Init == nil {
			c.errf(f.P, TyAnnotation, "注解字段必须有编译期常量初始化式（§12.1）", "")
		} else if !isConstExpr(f.Init) {
			c.errf(f.Init.Pos(), TyAnnotation, "注解字段初始化式必须是编译期常量（§12.1）", "")
		}
		k := typeKey(f.Type)
		allowed := scalarValueType(k) || k == "Bool" || k == "String" || k == "Char"
		if info, ok := c.types[k]; ok && info.kind == "enum" && !info.enum.IsData {
			allowed = true
		}
		if !allowed {
			c.errf(f.P, TyAnnotation, "注解字段类型 `"+k+"` 不是编译期常量类型（§12.1）", "")
		}
	}
}

func (c *typeCheckCtx) checkAnnos(target string, annos []*xfront.AnnotationNode) {
	seen := map[string]bool{}
	for _, a := range annos {
		if seen[a.Name] {
			c.errf(a.P, TyAnnotation, "同一目标重复使用注解 `@"+a.Name+"`（§12.2）", "删除重复注解")
		}
		seen[a.Name] = true
		switch a.Name {
		case "Override":
			if target != "method" {
				c.errf(a.P, TyAnnotation, "@Override 只能用于方法（§12.3）", "")
			}
		case "ReadOnly":
			if target != "field" {
				c.errf(a.P, TyAnnotation, "@ReadOnly 只能用于字段（§12.3）", "")
			}
		default:
			if builtinAnnotations[a.Name] {
				continue
			}
			info, ok := c.types[a.Name]
			if !ok || info.kind != "annotation" || info.anno == nil {
				c.errf(a.P, TyAnnotation, "未知注解 `@"+a.Name+"`（§12.2）", "先声明 @annotation，或使用内建注解")
				continue
			}
			fields := info.anno.Fields
			if len(a.Args) > len(fields) {
				c.errf(a.P, TyAnnotation, "注解 `@"+a.Name+"` 参数过多（§12.2）", "")
			}
			for i, arg := range a.Args {
				if i >= len(fields) {
					break
				}
				if !isConstExpr(arg) {
					c.errf(arg.Pos(), TyAnnotation, "注解参数必须是编译期常量（§12.2）", "")
					continue
				}
				if !assignable(constExprType(arg), typeKey(fields[i].Type)) {
					c.errf(arg.Pos(), TyAnnotation, "注解参数类型不匹配字段 `"+fields[i].Name+"`（§12.2）", "")
				}
			}
		}
	}
}

func (c *typeCheckCtx) checkAllAnnotations(u *xfront.CompilationUnit) {
	checkParams := func(ps []*xfront.Param) {
		for _, p := range ps {
			c.checkAnnos("param", p.Annos)
		}
	}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			c.checkAnnos("decl", n.Annos)
			checkParams(n.Params)
		case *xfront.TopField:
			c.checkAnnos("field", n.Annos)
		case *xfront.ClassDecl:
			c.checkAnnos("type", n.Annos)
			for _, f := range n.Fields {
				c.checkAnnos("field", f.Annos)
			}
			for _, m := range n.Methods {
				c.checkAnnos("method", m.Annos)
				checkParams(m.Params)
			}
			for _, ct := range n.Ctors {
				c.checkAnnos("ctor", ct.Annos)
				checkParams(ct.Params)
			}
		case *xfront.StructDecl:
			c.checkAnnos("type", n.Annos)
			for _, f := range n.Fields {
				c.checkAnnos("field", f.Annos)
			}
			for _, m := range n.Methods {
				c.checkAnnos("method", m.Annos)
				checkParams(m.Params)
			}
		case *xfront.ProtocolDecl:
			c.checkAnnos("type", n.Annos)
		case *xfront.EnumDecl:
			c.checkAnnos("type", n.Annos)
			for _, it := range n.Items {
				c.checkAnnos("enumitem", it.Annos)
			}
		case *xfront.SingletonDecl:
			c.checkAnnos("type", n.Annos)
			for _, f := range n.Fields {
				c.checkAnnos("field", f.Annos)
			}
			for _, m := range n.Methods {
				c.checkAnnos("method", m.Annos)
			}
		case *xfront.FactoryDecl:
			c.checkAnnos("type", n.Annos)
			for _, m := range n.Methods {
				c.checkAnnos("method", m.Annos)
			}
		case *xfront.AnnotationDecl:
			c.checkAnnos("type", n.Annos)
			for _, f := range n.Fields {
				c.checkAnnos("field", f.Annos)
			}
		}
	}
}

// ---------- BND-07/08：singleton / factory 登记与规则 ----------

func (c *typeCheckCtx) checkSingleton(d *xfront.SingletonDecl) {
	if d.Mod.Abstract {
		c.errf(d.P, TySingletonRule, "singleton 不能是 abstract（§9.1/§9.4）", "去掉 abstract")
	}
	for _, f := range d.Fields {
		if f.Canonical == "" {
			f.Canonical = f.Name
		}
		if f.Init != nil {
			if ref := singletonForwardRef(f.Init); ref != "" && c.singleOrder[ref] > c.singleOrder[d.Name] {
				c.errf(f.Init.Pos(), TySingletonRule,
					"单例 `"+d.Name+"` 不能前向引用后面的单例 `"+ref+"`（§9.2/§9.4）", "调整声明顺序")
			}
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
	cross := false
	for _, p := range c.a.importPaths {
		if len(p) > 0 && strings.EqualFold(p[len(p)-1], name) {
			cross = true
		}
	}
	info, found := c.types[name]
	if !found {
		if c.a.imported[name] {
			cross = true // 跨包可见 Target：具体成员可见性由跨包访问检查承担
		} else {
			c.errf(d.P, TyFactory, "factory Target `"+name+"` 未在本包声明或不可见（§10.1）", "检查 Target 名称与可见性")
			return
		}
	}
	if found && info.kind != "class" && info.kind != "struct" {
		c.errf(d.P, TyFactory, "factory Target 必须是 class 或 struct（得到 "+info.kind+"，§10.1）", "")
		return
	}

	for _, m := range d.Methods {
		// 工厂方法禁用 self/super。
		if stmtUsesIdent(m.Body, "self") || stmtUsesIdent(m.Body, "super") {
			c.errf(m.P, TyFactorySelf, "factory 方法不能使用 self / super（§10.2）", "改用参数和局部变量")
		}
		// 返回类型必须可归到 Target（或其父类/协议/Object/可空/Result 包装）。
		key := "void"
		if !m.Void && m.Ret != nil {
			key = typeKey(m.Ret)
		}
		if found && !c.factoryRetAllowed(info, key) {
			c.errf(m.P, TyFactoryRet,
				"factory 方法 `"+m.Name+"` 返回类型 `"+key+"` 不能归到 Target `"+name+"`（§10.2）", "返回 Target/父类/协议/Object 或 Result 包装")
		}
		// 跨包 factory 不得调用 Target 的非公开构造器。
		if cross && found && info.class != nil && stmtUsesNewTarget(m.Body, name) {
			for _, ct := range info.class.Ctors {
				if ct.Mod.Vis == "private" || ct.Mod.Vis == "protected" {
					c.errf(m.P, TyFactoryAccess,
						"跨包 factory 不能调用 Target `"+name+"` 的非公开构造器（§10.3）", "改用公开静态工厂/公开构造器")
					break
				}
			}
		}
	}
}

func singletonForwardRef(e xfront.Expr) string {
	switch n := e.(type) {
	case nil:
		return ""
	case *xfront.Member:
		if n.Name == "instance" {
			if id, ok := n.X.(*xfront.IdentExpr); ok {
				return id.Name
			}
		}
		return singletonForwardRef(n.X)
	case *xfront.Paren:
		return singletonForwardRef(n.X)
	case *xfront.Unary:
		return singletonForwardRef(n.X)
	case *xfront.Binary:
		if r := singletonForwardRef(n.L); r != "" {
			return r
		}
		return singletonForwardRef(n.R)
	case *xfront.Ternary:
		if r := singletonForwardRef(n.Cond); r != "" {
			return r
		}
		return singletonForwardRef(n.Then)
	case *xfront.Call:
		for _, a := range n.Args {
			if r := singletonForwardRef(a); r != "" {
				return r
			}
		}
	case *xfront.Tuple:
		for _, el := range n.Elems {
			if r := singletonForwardRef(el); r != "" {
				return r
			}
		}
	}
	return ""
}

func (c *typeCheckCtx) factoryRetAllowed(info *typeInfo, key string) bool {
	k := unwrapTypeKey(key)
	if k == "" {
		return false
	}
	if strings.HasPrefix(k, "Result<") {
		inner := strings.TrimSuffix(strings.TrimPrefix(k, "Result<"), ">")
		parts := splitTypeArgs(inner)
		if len(parts) != 2 || parts[1] == "void" {
			return false
		}
		return c.factoryRetAllowed(info, parts[0])
	}
	if k == "Object" {
		return true
	}
	if info.class != nil {
		if info.class.Name == k {
			return true
		}
		for _, anc := range c.ancestorClasses(info.class) {
			if anc.class.Name == k {
				return true
			}
		}
		for _, pr := range info.class.Protocols {
			if lastSeg(pr.Qual) == k {
				return true
			}
		}
		return false
	}
	return info.strct != nil && info.strct.Name == k
}

func unwrapTypeKey(k string) string {
	for strings.HasSuffix(k, "?") {
		k = strings.TrimSuffix(k, "?")
	}
	return k
}

func stmtUsesIdent(s xfront.Stmt, name string) bool {
	if s == nil {
		return false
	}
	switch st := s.(type) {
	case *xfront.ExprStmt:
		return exprUsesIdent(st.X, name)
	case *xfront.AssignStmt:
		return exprUsesIdent(st.Target, name) || exprUsesIdent(st.Value, name)
	case *xfront.LocalDeclStmt:
		return exprUsesIdent(st.Init, name)
	case *xfront.ReturnStmt:
		return exprUsesIdent(st.Value, name)
	case *xfront.Block:
		for _, x := range st.Stmts {
			if stmtUsesIdent(x, name) {
				return true
			}
		}
	case *xfront.IfStmt:
		return stmtUsesIdent(st.Then, name) || stmtUsesIdent(st.Else, name)
	case *xfront.WhileStmt:
		return stmtUsesIdent(st.Body, name)
	case *xfront.DoWhileStmt:
		return stmtUsesIdent(st.Body, name)
	case *xfront.ForStmt:
		return stmtUsesIdent(st.Body, name)
	case *xfront.SwitchStmt:
		for _, c := range st.Cases {
			for _, x := range c.Stmts {
				if stmtUsesIdent(x, name) {
					return true
				}
			}
		}
		if st.Default != nil {
			for _, x := range st.Default.Stmts {
				if stmtUsesIdent(x, name) {
					return true
				}
			}
		}
	case *xfront.DeferStmt:
		if st.Block != nil {
			return stmtUsesIdent(st.Block, name)
		}
		return stmtUsesIdent(st.Stmt, name)
	case *xfront.LabeledStmt:
		return stmtUsesIdent(st.Stmt, name)
	}
	return false
}

func exprUsesIdent(e xfront.Expr, name string) bool {
	switch n := e.(type) {
	case nil:
		return false
	case *xfront.IdentExpr:
		return n.Name == name
	case *xfront.Paren:
		return exprUsesIdent(n.X, name)
	case *xfront.Unary:
		return exprUsesIdent(n.X, name)
	case *xfront.Binary:
		return exprUsesIdent(n.L, name) || exprUsesIdent(n.R, name)
	case *xfront.Ternary:
		return exprUsesIdent(n.Cond, name) || exprUsesIdent(n.Then, name) || exprUsesIdent(n.Else, name)
	case *xfront.Call:
		if exprUsesIdent(n.Callee, name) {
			return true
		}
		for _, a := range n.Args {
			if exprUsesIdent(a, name) {
				return true
			}
		}
	case *xfront.Member:
		return exprUsesIdent(n.X, name)
	case *xfront.TupleMember:
		return exprUsesIdent(n.X, name)
	case *xfront.Index:
		return exprUsesIdent(n.X, name) || exprUsesIdent(n.Idx, name)
	}
	return false
}

func stmtUsesNewTarget(s xfront.Stmt, target string) bool {
	if s == nil {
		return false
	}
	switch st := s.(type) {
	case *xfront.ExprStmt:
		return exprUsesNewTarget(st.X, target)
	case *xfront.AssignStmt:
		return exprUsesNewTarget(st.Value, target)
	case *xfront.LocalDeclStmt:
		return exprUsesNewTarget(st.Init, target)
	case *xfront.ReturnStmt:
		return exprUsesNewTarget(st.Value, target)
	case *xfront.Block:
		for _, x := range st.Stmts {
			if stmtUsesNewTarget(x, target) {
				return true
			}
		}
	case *xfront.IfStmt:
		return stmtUsesNewTarget(st.Then, target) || stmtUsesNewTarget(st.Else, target)
	case *xfront.WhileStmt:
		return stmtUsesNewTarget(st.Body, target)
	case *xfront.DoWhileStmt:
		return stmtUsesNewTarget(st.Body, target)
	case *xfront.ForStmt:
		return stmtUsesNewTarget(st.Body, target)
	case *xfront.DeferStmt:
		if st.Block != nil {
			return stmtUsesNewTarget(st.Block, target)
		}
		return stmtUsesNewTarget(st.Stmt, target)
	case *xfront.LabeledStmt:
		return stmtUsesNewTarget(st.Stmt, target)
	}
	return false
}

func exprUsesNewTarget(e xfront.Expr, target string) bool {
	switch n := e.(type) {
	case nil:
		return false
	case *xfront.New:
		if nt, ok := n.Type.(*xfront.NamedType); ok && len(nt.Qual) == 1 && nt.Qual[0] == target {
			return true
		}
	case *xfront.Paren:
		return exprUsesNewTarget(n.X, target)
	case *xfront.Unary:
		return exprUsesNewTarget(n.X, target)
	case *xfront.Binary:
		return exprUsesNewTarget(n.L, target) || exprUsesNewTarget(n.R, target)
	case *xfront.Call:
		if exprUsesNewTarget(n.Callee, target) {
			return true
		}
		for _, a := range n.Args {
			if exprUsesNewTarget(a, target) {
				return true
			}
		}
	case *xfront.Member:
		return exprUsesNewTarget(n.X, target)
	case *xfront.Tuple:
		for _, el := range n.Elems {
			if exprUsesNewTarget(el, target) {
				return true
			}
		}
	}
	return false
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

// findClassMethod 在类继承链中查找方法，并按接收者的泛型实参建立类型参数替换表。
// 供 sema 的方法调用返回类型/实参检查使用（XDK collections 等源码单元类）。
// hasFieldNamed 判断用户声明的 class 是否有该字段（字段闭包调用不落 TY-229）。
func (c *typeCheckCtx) hasFieldNamed(recvKey, name string) bool {
	base := unwrapOpt(recvKey)
	if i := strings.Index(base, "<"); i > 0 {
		base = base[:i]
	}
	info := c.types[base]
	if info == nil || info.kind != "class" || info.class == nil {
		return false
	}
	for _, f := range info.class.Fields {
		if f.Name == name || f.Canonical == name {
			return true
		}
	}
	return false
}

// hasClassNamed 判断用户是否声明了同名 class（同名时优先类方法表，不套用 XDK 内建签名）。
func (c *typeCheckCtx) hasClassNamed(name string) bool {
	info := c.types[name]
	return info != nil && info.kind == "class" && info.class != nil
}

func (c *typeCheckCtx) findClassMethod(recvKey, name string) (*xfront.MethodDecl, map[string]string, bool) {
	base := unwrapOpt(recvKey)
	var args []string
	if i := strings.Index(base, "<"); i > 0 && strings.HasSuffix(base, ">") {
		args = splitTopLevel(base[i+1 : len(base)-1])
		base = base[:i]
	}
	info := c.types[base]
	if info == nil || info.kind != "class" || info.class == nil {
		return nil, nil, false
	}
	subst := map[string]string{}
	for i, tp := range info.class.TypePars {
		if i < len(args) && args[i] != "" {
			subst[tp] = args[i]
		}
	}
	seen := map[string]bool{}
	for cur := info.class; cur != nil; {
		if seen[cur.Name] {
			break
		}
		seen[cur.Name] = true
		for _, m := range cur.Methods {
			if m.Name == name {
				return m, subst, true
			}
		}
		b := baseRefName(cur.Base)
		if b == "" {
			break
		}
		ni := c.types[b]
		if ni == nil || ni.kind != "class" {
			break
		}
		cur = ni.class
	}
	return nil, nil, false
}

// findClassField 在类继承链中查找字段类型，并按接收者泛型实参替换类型参数。
func (c *typeCheckCtx) findClassField(recvKey, name string) (string, bool) {
	base := unwrapOpt(recvKey)
	var args []string
	if i := strings.Index(base, "<"); i > 0 && strings.HasSuffix(base, ">") {
		args = splitTopLevel(base[i+1 : len(base)-1])
		base = base[:i]
	}
	info := c.types[base]
	if info == nil || info.kind != "class" || info.class == nil {
		return "", false
	}
	subst := map[string]string{}
	for i, tp := range info.class.TypePars {
		if i < len(args) && args[i] != "" {
			subst[tp] = args[i]
		}
	}
	seen := map[string]bool{}
	for cur := info.class; cur != nil; {
		if seen[cur.Name] {
			break
		}
		seen[cur.Name] = true
		for _, f := range cur.Fields {
			if f.Name == name || f.Canonical == name {
				return substKey(typeKey(f.Type), subst), true
			}
		}
		b := baseRefName(cur.Base)
		if b == "" {
			break
		}
		ni := c.types[b]
		if ni == nil || ni.kind != "class" {
			break
		}
		cur = ni.class
	}
	return "", false
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
	className   string
	srcToCanon  map[string]string // 声明名 → 规范名（仅 private name 形式；规范名 != 声明名）
	canonPriv   map[string]bool   // 私有字段规范名集合（含 _name 形式）
	finalFields map[string]bool   // final 字段名（声明名与规范名）
	instance    bool              // 是否实例方法（static 方法禁用 self）
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
	ctx := &classCtx{className: className, srcToCanon: map[string]string{}, canonPriv: map[string]bool{}, finalFields: map[string]bool{}}
	for _, f := range fields {
		if f.Canonical != f.Name {
			ctx.srcToCanon[f.Name] = f.Canonical
		}
		if f.Mod.Vis == "private" || strings.HasPrefix(f.Name, "_") {
			ctx.canonPriv[f.Canonical] = true
		}
		if f.Mod.Final {
			ctx.finalFields[f.Name] = true
			ctx.finalFields[f.Canonical] = true
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
		e.tasksBlock = hasAnnotation(m.Annos, "tasks")
		e.closedChannels = map[string]bool{}
		e.lockHeld = map[string]bool{}
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
		e.closedChannels = map[string]bool{}
		e.lockHeld = map[string]bool{}
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
