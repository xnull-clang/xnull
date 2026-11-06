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
	TyModifier  = "TY-201"
	TyInherit   = "TY-202"
	TyOverride  = "TY-203"
	TyStructVal = "TY-204"
	TyProtoForm = "TY-205"
	TyEnumRule  = "TY-206"
	TyPrivField = "TY-207"
)

// builtinTypeNames 是预定义类型名（§1.1：类型名不得与之冲突）。
var builtinTypeNames = map[string]bool{
	"Bool": true, "Byte": true, "Short": true, "Int": true, "Long": true,
	"UByte": true, "UShort": true, "UInt": true, "ULong": true,
	"Int128": true, "UInt128": true, "Float": true, "Double": true, "Char": true,
	"String": true, "Text": true, "Bytes": true, "StringBuilder": true,
	"Any": true, "Object": true, "List": true, "Map": true, "Set": true,
	"Result": true, "Range": true,
}

// typeInfo 是包内类型声明登记。
type typeInfo struct {
	kind   string // class/struct/protocol/enum
	mod    xfront.TypeModifiers
	class  *xfront.ClassDecl
	strct  *xfront.StructDecl
	proto  *xfront.ProtocolDecl
	enum   *xfront.EnumDecl
	fields []*xfront.FieldDecl

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
				if m.Name == am.Name && m.IsDeinit == am.IsDeinit && sameSig(m.Params, am.Params) {
					c.errf(m.P, TyOverride, "方法 `"+m.Name+"` 与祖先类 `"+anc.class.Name+"` 的实例方法同签名：子类覆写被拒绝（§2.5）",
						"改用不同参数列表构成重载")
				}
			}
		}
	}
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
	c.walkClassBodies(d.Name, d.Fields, d.Methods, d.Ctors)
}

// checkStruct 结构体检查（§3）。
func (c *typeCheckCtx) checkStruct(d *xfront.StructDecl) {
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
	c.walkClassBodies(d.Name, d.Fields, d.Methods, d.Ctors)
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
		if len(ty.Args) > 0 {
			return false // 泛型实例（List<T> 等）不是值字段（§3.2）
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
		for _, f := range d.Fields {
			c.checkFieldDecl(f, d.Name)
			if !f.Mod.Final {
				c.errf(f.P, TyEnumRule, "数据枚举字段必须 final（§8.3：实例不可变）", "")
			}
		}
	} else {
		if len(d.Fields) > 0 || len(d.Methods) > 0 || len(d.Ctors) > 0 {
			c.errf(d.P, TyEnumRule, "简单枚举只有项：不能声明字段、方法、构造器或 deinit（§8.2）", "")
		}
	}
}

// constInt64 求简单枚举项的整数字面量值（含前导 -）。
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
func (c *typeCheckCtx) walkClassBodies(className string, fields []*xfront.FieldDecl,
	methods []*xfront.MethodDecl, ctors []*xfront.CtorDecl) {
	e := &tyenv{a: c.a, vars: map[string]string{}, funcs: c.topFuncs, fields: map[string]string{}}
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
	// 实例方法与构造器
	for _, m := range methods {
		if m.IsDeinit {
			continue
		}
		ctx.instance = !m.Mod.Static
		e.cls = ctx
		retKey := "void"
		if !m.Void && m.Ret != nil {
			retKey = typeKey(m.Ret)
		}
		e.vars = map[string]string{}
		if ctx.instance {
			e.vars["self"] = className
		}
		for name, tk := range fieldType {
			e.vars[name] = tk
		}
		for _, p := range m.Params {
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
		e.vars = map[string]string{"self": className}
		for name, tk := range fieldType {
			e.vars[name] = tk
		}
		for _, p := range ct.Params {
			if ctx.canonPriv[p.Name] {
				c.errf(p.P, TyPrivField, "参数 `"+p.Name+"` 与类私有字段规范名冲突（§7.4）", "")
			}
			e.vars[p.Name] = typeKey(p.Type)
		}
		e.walkFunc(ct.Body, "void")
	}
	e.cls = nil
}
