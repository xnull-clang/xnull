package sema

import (
	"fmt"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M2-C 类型检查（S1 §2.6 可赋值性 / §2.10 字面量适配 / §6.1 条件与返回） ----------
//
// 诊断码段位 TY-1xx：
//   TY-101 可赋值性失败（含隐式数值转换、void 位置错误、装箱未显式）
//   TY-103 null 赋给非可空值类型（§2.6 禁止项）
//   TY-104 条件必须是 Bool（§6.1）
//   TY-105 无效运算操作数（§7.2/§9.2）
//
// 已知边界（不做静默承诺，见 m2-sema-plan.md）：
//   - 泛型实参不深度检查（单态化属后续切片），Result/List/Map/Set 按声明骨架检查；
//   - 类/协议子类型（S2）不在本遍；
//   - 方法调用的接收者多态按 S2 切片扩展。

// 诊断码。
const (
	TyAssignability = "TY-101" // 可赋值性失败（§2.6）
	TyNullToValue   = "TY-103" // null → 非可空值类型（§2.6 禁止）
	TyCondNotBool   = "TY-104" // 条件必须是 Bool（§6.1）
	TyBadOperand    = "TY-105" // 无效运算操作数（§7.2/§9.2）
	TyTuple         = "TY-106" // 元组规则（S1 §2.11：越界/成员/switch/const/插值/as）
	TyMapKey        = "TY-107" // Map 键类型不支持（§9.5）
)

// texpr 是表达式的静态类型：key 是规范化类型串；lit 标记未定型字面量。
type texpr struct {
	key   string  // "" = 未知/void 语义上有别：void 用 "void"，未知用 ""
	lit   int     // 0 普通；1 整数字面量；2 浮点字面量；3 字符串字面量；4 null
	elems []texpr // 元组字面量的逐元素类型（保留字面量标记，§2.11 目标适配）

	hasInt  bool   // 整数字面量的值已知（M6-B0-07a 范围检查）
	intVal  int64  // 有符号值
	uintVal uint64 // 无符号值（仅 isUInt 时有效）
	isUInt  bool
	intBad  bool // 字面量运算后无法用 int64 表达（负向越界，禁止回绕）
}

var intTypeNames = map[string]bool{
	"Int": true, "Long": true, "Byte": true, "Short": true, "UByte": true,
	"UShort": true, "UInt": true, "ULong": true, "Int128": true, "UInt128": true,
	// FFI 定宽整数（S7 §3.2 标量映射）；S1 §2.6 字面量适配按目标宽度检查。
	"Int8": true, "Int16": true, "Int32": true, "Int64": true,
	"UInt8": true, "UInt16": true, "UInt32": true, "UInt64": true,
}

var refTypeNames = map[string]bool{ // §2.6 空值规则：引用类型
	"String": true, "Object": true, "Any": true, "Text": true,
	"StringBuilder": true, "Bytes": true,
}

// typeKey 把 TypeRef 规范化为类型串。
func typeKey(t xfront.TypeRef) string {
	switch ty := t.(type) {
	case nil:
		return ""
	case *xfront.NamedType:
		name := ty.Qual[len(ty.Qual)-1]
		if len(ty.Args) == 0 {
			return name
		}
		parts := make([]string, len(ty.Args))
		for i, a := range ty.Args {
			parts[i] = typeKey(a)
		}
		return name + "<" + strings.Join(parts, ",") + ">"
	case *xfront.SuffixedType:
		k := typeKey(ty.Base)
		for _, s := range ty.Suffixes {
			k += s
		}
		return k
	case *xfront.FuncTypeRef:
		ps := make([]string, len(ty.Params))
		for i, p := range ty.Params {
			ps[i] = typeKey(p)
		}
		return typeKey(ty.Ret) + "(" + strings.Join(ps, ",") + ")"
	case *xfront.TupleTypeRef:
		ps := make([]string, len(ty.Elems))
		for i, e := range ty.Elems {
			ps[i] = typeKey(e)
		}
		return "(" + strings.Join(ps, ",") + ")"
	}
	return ""
}

// splitTupleKey 拆分元组类型串 `(T1,T2,...)`；嵌套括号/尖括号/方括号内的逗号不切分。
// 返回 false 表示不是元组类型（§2.11 元组至少两个元素）。
func splitTupleKey(key string) ([]string, bool) {
	key = unwrapOpt(key)
	if !strings.HasPrefix(key, "(") || !strings.HasSuffix(key, ")") {
		return nil, false
	}
	inner := key[1 : len(key)-1]
	if inner == "" {
		return nil, false
	}
	depth := 0
	start := 0
	var parts []string
	for i, r := range inner {
		switch r {
		case '(', '<', '[':
			depth++
		case ')', '>', ']':
			depth--
		case ',':
			if depth == 0 {
				parts = append(parts, strings.TrimSpace(inner[start:i]))
				start = i + 1
			}
		}
	}
	parts = append(parts, strings.TrimSpace(inner[start:]))
	if len(parts) < 2 {
		return nil, false
	}
	return parts, true
}

func isOptional(key string) bool { return strings.HasSuffix(key, "?") }

func unwrapOpt(key string) string {
	if isOptional(key) {
		return key[:len(key)-1]
	}
	return key
}

// mapKeyAllowed 判定 Map 键类型是否合法（§9.5）：String、整数类型、简单枚举。
// 未知命名类型按“可能是简单枚举”放行（枚举集合在 typedecl 遍，本遍不误报）。
func mapKeyAllowed(k string) bool {
	base := unwrapOpt(k)
	if base == "String" || isIntType(base) {
		return true
	}
	switch base {
	case "Bool", "Float", "Double", "Char", "Any", "Object", "void", "":
		return false
	}
	if isRefType(base) || strings.HasSuffix(base, "]") ||
		strings.HasPrefix(base, "List<") || strings.HasPrefix(base, "Map<") ||
		strings.HasPrefix(base, "Set<") || strings.HasPrefix(base, "(") {
		return false
	}
	return true
}

// checkMapKey 对声明类型 Map<K,V> 的 K 做 §9.5 检查（非 Map 类型不动作）。
func (e *tyenv) checkMapKey(p xfront.Pos, key string) {
	if !strings.HasPrefix(key, "Map<") || !strings.HasSuffix(key, ">") {
		return
	}
	parts := splitTypeArgs(key[len("Map<") : len(key)-1])
	if len(parts) == 0 {
		return
	}
	k := strings.TrimSpace(parts[0])
	if !mapKeyAllowed(k) {
		e.errf(p, TyMapKey,
			fmt.Sprintf("Map 键类型 %s 不被支持（§9.5：只允许 String、整数类型和简单枚举）", k),
			"改用 String 或整数键，或把键编码为 String")
	}
}

// isRefType 判断类型串是否引用类型（§2.6 空值规则）。
func isRefType(key string) bool {
	base := unwrapOpt(key)
	if strings.HasSuffix(base, "[]") {
		return true
	}
	if strings.HasPrefix(base, "List<") || strings.HasPrefix(base, "Map<") ||
		strings.HasPrefix(base, "Set<") {
		return true
	}
	if strings.Contains(base, "<") || strings.Contains(base, "(") || strings.HasPrefix(base, "(") {
		return false
	}
	return refTypeNames[base]
}

// isIntType / isFloatType 按类型串判断。
func isIntType(key string) bool { return intTypeNames[unwrapOpt(key)] }
func isFloatType(key string) bool {
	b := unwrapOpt(key)
	return b == "Float" || b == "Double"
}

// canAssign 在 assignable 基础上补类/协议层次（S2 §5.2）：
// 子类 → 祖先类、类 → 其实现（含祖先实现）的协议、协议 → 父协议。
func (e *tyenv) canAssign(from texpr, to string) bool {
	if assignable(from, to) {
		return true
	}
	if e.a == nil || e.a.tc == nil || from.key == "" || to == "" {
		return false
	}
	f := unwrapOpt(from.key)
	t := unwrapOpt(to)
	if f == t {
		return true
	}
	fi := e.a.tc.types[f]
	ti := e.a.tc.types[t]
	if fi == nil || ti == nil {
		return false
	}
	if fi.kind == "class" {
		for cur := fi.class; cur != nil; {
			if cur.Name == t {
				return true
			}
			if ti.kind == "protocol" {
				for _, pr := range cur.Protocols {
					if lastSeg(pr.Qual) == t {
						return true
					}
				}
			}
			b := baseRefName(cur.Base)
			ni := e.a.tc.types[b]
			if ni == nil || ni.kind != "class" {
				break
			}
			cur = ni.class
		}
	}
	if fi.kind == "protocol" && ti.kind == "protocol" {
		for cur := fi.proto; cur != nil; {
			found := false
			for _, ex := range cur.Extends {
				if lastSeg(ex.Qual) == t {
					return true
				}
				if ni := e.a.tc.types[lastSeg(ex.Qual)]; ni != nil && ni.kind == "protocol" {
					cur = ni.proto
					found = true
					break
				}
			}
			if !found {
				break
			}
		}
	}
	return false
}

// assignable 判断 from 是否可赋给 to（§2.6；lit 提供字面量适配规则）。
func assignable(from texpr, to string) bool {
	if to == "" || from.key == "" {
		return true // 未知类型不误报（边界：推断不出时放行，静默面由后续切片收敛）
	}
	if from.key == to {
		return true
	}
	// 可选提升：from 可赋给 T 即可赋给 T?（§2.6；含 null、字面量与容器字面量）。
	// 先于字面量分支，避免 `String? s = "x"` 被字面量规则短路成 TY-101。
	if isOptional(to) {
		if from.lit == 4 {
			return true
		}
		if assignable(from, unwrapOpt(to)) {
			return true
		}
	}
	// 元组字面量按目标元素类型逐项适配（§2.11）：长度相同且元素逐一可赋值。
	if len(from.elems) > 0 {
		toElems, ok := splitTupleKey(to)
		if !ok || len(toElems) != len(from.elems) {
			return false
		}
		for i := range from.elems {
			if !assignable(from.elems[i], toElems[i]) {
				return false
			}
		}
		return true
	}
	// 字面量规则（§2.6）。
	switch from.lit {
	case 1: // 整数字面量可表示在目标整数类型中（§2.6）
		if !isIntType(to) {
			return false
		}
		return intLiteralFits(from, to)
	case 2:
		return isFloatType(to)
	case 3:
		return to == "String"
	case 4: // null → 引用类型或 T?（§2.6）
		if isRefType(to) || isOptional(to) {
			return true
		}
		return false
	}
	// 容器字面量：数组形态初始化式 → List<X>/Set<X>（目标给元素类型，§2.6）
	if strings.HasSuffix(from.key, "[]") {
		elem := from.key[:len(from.key)-2]
		for _, pre := range []string{"List<", "Set<"} {
			if strings.HasPrefix(to, pre) && strings.HasSuffix(to, ">") {
				x := to[len(pre) : len(to)-1]
				return assignable(texpr{key: elem}, x)
			}
		}
	}
	// 闭包字面量 → 函数类型（§2.6；参数匹配与返回值检查按函数字面量逐参进行——
	// 此处按骨架放行，逐参检查在闭包类型绑定切片）
	if from.lit == 5 {
		base := unwrapOpt(to)
		if i := strings.Index(base, "("); i > 0 && strings.HasSuffix(base, ")") {
			return true
		}
	}
	// Result 骨架：构造器 Result<,>（泛型实参由目标适配，§2.6 错误值规则）
	if strings.HasPrefix(from.key, "Result<") && strings.Contains(from.key, ",,") == false {
		ff := from.key[len("Result<") : len(from.key)-1]
		tt := strings.TrimPrefix(to, "Result<")
		tt = strings.TrimSuffix(tt, ">")
		if strings.HasPrefix(to, "Result<") && (ff == "," || tt == ",") {
			return true
		}
	}
	return false
}

// intLiteralFits 检查整数字面量的值能否表示在目标整数类型中（§2.6）。
// 仅对 S7 定宽整数（Int8..Int64 / UInt8..UInt64）做范围检查；
// Byte/Short/Int/Long 等既有类型保持历史行为，避免扩大本卡语义面。
func intLiteralFits(t texpr, to string) bool {
	if !t.hasInt {
		return true
	}
	if t.intBad {
		return false
	}
	switch unwrapOpt(to) {
	case "Int8":
		return signedFits(t, -1<<7, 1<<7-1)
	case "Int16":
		return signedFits(t, -1<<15, 1<<15-1)
	case "Int32":
		return signedFits(t, -1<<31, 1<<31-1)
	case "Int64":
		return signedFits(t, -1<<63, 1<<63-1)
	case "UInt8":
		return unsignedFits(t, 1<<8-1)
	case "UInt16":
		return unsignedFits(t, 1<<16-1)
	case "UInt32":
		return unsignedFits(t, 1<<32-1)
	case "UInt64":
		return unsignedFits(t, ^uint64(0))
	}
	return true
}

// adaptIntLiteralKeys 让比较中的整数字面量按另一侧整数类型适配（§2.6）；
// 返回两侧共同类型。非字面量或越界时不放宽。
func adaptIntLiteralKeys(lt, rt texpr) (string, string, bool) {
	if lt.key != "" && rt.key != "" && lt.key == rt.key {
		return lt.key, rt.key, true
	}
	// 仅无后缀整数字面量（默认 Int）按另一侧适配；显式后缀类型不隐式转换。
	if lt.lit == 1 && lt.key == "Int" && rt.key != "" && isIntType(rt.key) && intLiteralFits(lt, rt.key) {
		return rt.key, rt.key, true
	}
	if rt.lit == 1 && rt.key == "Int" && lt.key != "" && isIntType(lt.key) && intLiteralFits(rt, lt.key) {
		return lt.key, lt.key, true
	}
	return lt.key, rt.key, false
}

func signedFits(t texpr, min, max int64) bool {
	if t.isUInt {
		return t.uintVal <= uint64(max)
	}
	return t.intVal >= min && t.intVal <= max
}

func unsignedFits(t texpr, max uint64) bool {
	if t.isUInt {
		return t.uintVal <= max
	}
	return t.intVal >= 0 && uint64(t.intVal) <= max
}

// checkValueInstantiation 校验泛型结构体实例实参（BND-04）。
func (e *tyenv) checkValueInstantiation(t xfront.TypeRef, p xfront.Pos) {
	if e.a.tc != nil {
		e.a.tc.checkValueInstantiation(t, p, e.typePars)
	}
}

// checkSwitchDefaultLast：default 最多一个且必须位于 switch 最后（§8.5）。
func (e *tyenv) checkSwitchDefaultLast(n *xfront.SwitchStmt) {
	if n.Default == nil {
		return
	}
	for _, c := range n.Cases {
		if c.P.Line > n.Default.P.Line || (c.P.Line == n.Default.P.Line && c.P.Col > n.Default.P.Col) {
			e.errf(n.Default.P, TyEnumSwitch, "default 子句必须位于 switch 最后（§8.5）", "把 default 移到所有 case 之后")
			return
		}
	}
}

// checkEnumSwitch 校验枚举 switch 的项合法性/重复/穷尽性（§8.5）。
func (e *tyenv) checkEnumSwitch(n *xfront.SwitchStmt, key string) {
	if e.a.tc == nil || key == "" {
		return
	}
	info, ok := e.a.tc.types[key]
	if !ok || info.kind != "enum" || info.enum == nil {
		return // 非枚举 switch 不检查穷尽性
	}
	items := map[string]bool{}
	var order []string
	for _, it := range info.enum.Items {
		items[it.Name] = true
		order = append(order, it.Name)
	}
	seen := map[string]bool{}
	for _, c := range n.Cases {
		mem, ok := c.Expr.(*xfront.Member)
		recv, ok2 := (*xfront.IdentExpr)(nil), false
		if ok {
			recv, ok2 = mem.X.(*xfront.IdentExpr)
		}
		if !ok || !ok2 || recv.Name != key {
			e.errf(c.Expr.Pos(), TyEnumSwitch,
				"枚举 switch 的 case 必须是 `"+key+".<项>` 项常量（§8.5）", "改用该枚举的项")
			continue
		}
		name := mem.Name
		if !items[name] {
			e.errf(c.Expr.Pos(), TyEnumSwitch,
				"枚举 `"+key+"` 没有项 `"+name+"`（§8.5）", "检查项名")
			continue
		}
		if seen[name] {
			e.errf(c.Expr.Pos(), TyEnumSwitch,
				"枚举项 `"+name+"` 在 switch 中重复（§8.5）", "删除重复 case")
			continue
		}
		seen[name] = true
	}
	if n.Default != nil {
		return // default 覆盖剩余项
	}
	var missing []string
	for _, name := range order {
		if !seen[name] {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		e.errf(n.P, TyEnumSwitch,
			"枚举 switch 未覆盖全部项（§8.5）：遗漏 "+strings.Join(missing, "、"), "补 case，或加 default")
	}
}

// ---------- BND-01：成员可见性（§7.3） ----------

func fieldVisibility(f *xfront.FieldDecl) string {
	if f.Mod.Vis == "private" || strings.HasPrefix(f.Name, "_") {
		return "private"
	}
	if f.Mod.Vis == "protected" {
		return "protected"
	}
	return "public"
}

// findField 在类继承链中查找字段，返回字段类型、可见性、声明类。
func (c *typeCheckCtx) findField(className, name string) (string, string, string, bool) {
	cur := className
	for i := 0; i < 64 && cur != ""; i++ {
		info, ok := c.types[cur]
		if !ok || info.kind != "class" || info.class == nil {
			break
		}
		for _, f := range info.class.Fields {
			if f.Name == name || f.Canonical == name {
				return typeKey(f.Type), fieldVisibility(f), cur, true
			}
		}
		if info.class.Base == nil {
			break
		}
		cur = baseRefName(info.class.Base)
	}
	return "", "", "", false
}

// findMethodVisibility 在继承链中查找方法可见性；任一公开同名重载即视为公开。
func (c *typeCheckCtx) findMethodVisibility(className, name string) (string, string, bool) {
	cur := className
	best, owner := "", ""
	for i := 0; i < 64 && cur != ""; i++ {
		info, ok := c.types[cur]
		if !ok || info.kind != "class" || info.class == nil {
			break
		}
		for _, m := range info.class.Methods {
			if m.IsDeinit || m.Name != name {
				continue
			}
			v := "public"
			if m.Mod.Vis == "private" {
				v = "private"
			} else if m.Mod.Vis == "protected" {
				v = "protected"
			}
			if v == "public" {
				return "public", cur, true
			}
			if best == "" {
				best, owner = v, cur
			}
		}
		if info.class.Base == nil {
			break
		}
		cur = baseRefName(info.class.Base)
	}
	if best != "" {
		return best, owner, true
	}
	return "", "", false
}

func (c *typeCheckCtx) isSubclass(sub, base string) bool {
	if sub == base {
		return true
	}
	info, ok := c.types[sub]
	if !ok || info.kind != "class" || info.class == nil {
		return false
	}
	for _, a := range c.ancestorClasses(info.class) {
		if a.class.Name == base {
			return true
		}
	}
	return false
}

// canAccessProtected：protected 只能由声明类/子类经 self、super 或当前类/子类静态类型访问。
func (e *tyenv) canAccessProtected(recvKey, owner string) bool {
	if e.cls == nil || e.a.tc == nil {
		return false
	}
	cur := e.cls.className
	if !e.a.tc.isSubclass(cur, owner) {
		return false
	}
	return e.a.tc.isSubclass(recvKey, cur)
}

// checkMethodVisibility 检查类方法调用的可见性。
func (e *tyenv) checkMethodVisibility(recvKey, name string, p xfront.Pos) {
	if e.a.tc == nil {
		return
	}
	info, ok := e.a.tc.types[recvKey]
	if !ok || info.kind != "class" || info.class == nil {
		return
	}
	vis, owner, ok := e.a.tc.findMethodVisibility(recvKey, name)
	if !ok || vis == "public" {
		return
	}
	if vis == "protected" {
		if e.canAccessProtected(recvKey, owner) {
			return
		}
		e.errf(p, TyVisibility, "受保护方法 `"+name+"` 不可访问（§7.3：仅声明类/子类经 self 或当前类/子类静态类型访问）", "")
		return
	}
	if e.cls != nil && e.cls.className == owner {
		return
	}
	e.errf(p, TyVisibility, "私有方法 `"+name+"` 不可访问（§7.3：仅声明类内部）", "")
}

// tyenv 是一个函数的类型环境。
type tyenv struct {
	a      *analyzer
	vars   map[string]string // 局部/参数/类字段（规范名）→ 类型串
	funcs  map[string][]*xfront.TopFunc
	fields map[string]string // 顶层字段 → 类型串
	cls    *classCtx         // 类方法体上下文（nil = 顶层函数）

	// ERR-01：当前所在的函数/闭包上下文（§10.2/§10.3）。
	ret       string // 当前函数/闭包返回类型串（"void" 或具体类型）
	fnKind    string // func/main/method/ctor/deinit/lambda/fieldinit
	inCleanup bool   // 正在检查 defer/errdefer 清理体

	// GEN-01：泛型函数上下文（§8）。
	curFunc   string          // 当前泛型函数名（自递归展开检测）
	typePars  map[string]bool // 当前函数/闭包可见的类型参数
	quietCtor bool            // 重载选择预推断阶段：Ok/Err 无目标类型不立即报错
}

func (e *tyenv) errf(p xfront.Pos, code, msg, hint string) {
	e.a.errf(p, code, msg, hint)
}

// analyzeTypes 对整个编译单元做类型检查。
func (a *analyzer) analyzeTypes(file string, u *xfront.CompilationUnit) {
	e := &tyenv{a: a, vars: map[string]string{}, funcs: map[string][]*xfront.TopFunc{}, fields: map[string]string{}, typePars: map[string]bool{}}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			e.funcs[n.Name] = append(e.funcs[n.Name], n)
			// void 参数/返回之外的参数类型 void 检查
			e.checkResultType(n.Ret, n.P)
			for _, p := range n.Params {
				e.checkResultType(p.Type, p.P)
				if typeKey(p.Type) == "void" {
					a.errf(p.P, TyAssignability, "void 不能作为参数类型（§2）", "参数类型必须是具体类型")
				}
			}
		case *xfront.TopField:
			k := typeKey(n.Type)
			e.checkMapKey(n.P, k)
			e.checkResultType(n.Type, n.P)
			e.checkTypeParamRef(n.Type, n.P)
			e.checkValueInstantiation(n.Type, n.P)
			if k == "void" {
				a.errf(n.P, TyAssignability, "void 不能作为字段类型（§2）", "字段类型必须是具体类型")
				continue
			}
			e.fields[n.Name] = k
			if n.Init != nil {
				oldKind, oldRet := e.fnKind, e.ret
				e.fnKind, e.ret = "fieldinit", ""
				it := e.inferExpected(n.Init, k)
				e.fnKind, e.ret = oldKind, oldRet
				if !e.canAssign(it, k) {
					e.a.errf(n.Init.Pos(), assignDiag(it, k),
						fmt.Sprintf("顶层字段 `%s` 的初始化式类型 %s 不能赋给 %s（§2.6）", n.Name, describeKey(it), k),
						hintFor(it, k))
				}
			}
		}
	}
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			retKey := "void"
			if !fn.Void && fn.Ret != nil {
				retKey = typeKey(fn.Ret)
			}
			e.fnKind, e.ret = "func", retKey
			if fn.Name == "main" {
				e.fnKind = "main"
			}
			e.curFunc = fn.Name
			e.typePars = map[string]bool{}
			for _, tp := range fn.TypePars {
				e.typePars[tp] = true
			}
			e.checkTypeParamRef(fn.Ret, fn.P)
			e.checkValueInstantiation(fn.Ret, fn.P)
			for _, p := range fn.Params {
				e.checkMapKey(p.P, typeKey(p.Type))
				e.checkTypeParamRef(p.Type, p.P)
				e.checkValueInstantiation(p.Type, p.P)
				e.vars[p.Name] = typeKey(p.Type)
			}
			e.walkFunc(fn.Body, retKey)
			// 清理局部（函数间隔离）
			for _, p := range fn.Params {
				delete(e.vars, p.Name)
			}
		}
	}
}

// assignDiag 返回可赋值性失败时应使用的诊断码：null → 非可空值类型走 TY-103。
func assignDiag(from texpr, to string) string {
	if from.lit == 4 && !isRefType(to) && !isOptional(to) {
		return TyNullToValue
	}
	return TyAssignability
}

// checkTupleInterp 校验元组插值的每个元素可格式化（§2.11 + §1.4.4）。
func (e *tyenv) checkTupleInterp(p xfront.Pos, t texpr) {
	parts, ok := splitTupleKey(t.key)
	if !ok {
		return
	}
	for _, part := range parts {
		if !e.formattableKey(part) {
			e.errf(p, TyTuple, "元组插值元素类型 "+part+" 不可格式化（§2.11/§1.4.4）", "")
		}
	}
}

// formattableKey 判断类型串是否属于 §1.4.4 允许的插值格式化值。
func (e *tyenv) formattableKey(key string) bool {
	if key == "" || key == "null" {
		return true
	}
	if parts, ok := splitTupleKey(key); ok {
		for _, part := range parts {
			if !e.formattableKey(part) {
				return false
			}
		}
		return true
	}
	base := unwrapOpt(key)
	switch base {
	case "String", "Bool", "Char":
		return true
	}
	if isIntType(base) || isFloatType(base) {
		return true
	}
	if e.a.tc != nil {
		if info, ok := e.a.tc.types[base]; ok {
			if info.kind == "enum" && !info.enum.IsData {
				return true
			}
			if info.kind == "class" {
				for _, m := range info.class.Methods {
					if m.Name == "toString" && !m.Void && len(m.Params) == 0 && typeKey(m.Ret) == "String" {
						return true
					}
				}
			}
		}
	}
	return false
}

func describeKey(t texpr) string {
	if t.key == "" {
		return "<未知>"
	}
	return t.key
}

func hintFor(from texpr, to string) string {
	switch {
	case from.lit == 4:
		return "null 只能赋给引用类型或 T?（§2.6）"
	case isIntType(from.key) && isIntType(to) || isFloatType(from.key) && isFloatType(to):
		return "数值类型之间的隐式转换被禁止（§2.6）；如需转换请显式书写目标类型的字面量后缀"
	case from.key == "Any":
		return "Any 拆箱必须显式 as / as?（§2.6）"
	default:
		return "检查类型声明与初始化式是否一致"
	}
}

// walkFunc 遍历函数体做类型检查。
func (e *tyenv) walkFunc(b *xfront.Block, retKey string) {
	e.ret = retKey
	if b == nil {
		return
	}
	for _, st := range b.Stmts {
		e.walkStmt(st, retKey)
	}
}

func (e *tyenv) walkStmt(st xfront.Stmt, retKey string) {
	switch n := st.(type) {
	case *xfront.LocalDeclStmt:
		if e.cls != nil && e.cls.canonPriv[n.Name] {
			e.errf(n.P, TyPrivField, "局部变量 `"+n.Name+"` 与类私有字段规范名冲突（§7.4：局部变量、参数不能声明为 _name）", "")
		}
		if n.Type != nil {
			e.checkResultType(n.Type, n.P)
			e.checkTypeParamRef(n.Type, n.P)
			e.checkValueInstantiation(n.Type, n.P)
		}
		if n.Init != nil {
			it := e.inferExpected(n.Init, typeKey(n.Type))
			if n.Type != nil {
				k := typeKey(n.Type)
				e.checkMapKey(n.P, k)
				if k == "void" {
					e.errf(n.P, TyAssignability, "void 不能作为变量类型（§2）", "变量类型必须是具体类型")
					e.vars[n.Name] = ""
				} else {
					if !e.canAssign(it, k) {
						e.errf(n.Init.Pos(), assignDiag(it, k),
							fmt.Sprintf("变量 `%s` 的初始化式类型 %s 不能赋给 %s（§2.6）", n.Name, describeKey(it), k),
							hintFor(it, k))
					}
					e.vars[n.Name] = k
				}
			} else {
				// var 推断：整数字面量 → Int、浮点 → Double（§2.10 默认绑定）
				k := it.key
				switch it.lit {
				case 1:
					k = "Int"
				case 2:
					k = "Double"
				}
				e.vars[n.Name] = k
			}
		} else if n.Type != nil {
			k := typeKey(n.Type)
			if k == "void" {
				e.errf(n.P, TyAssignability, "void 不能作为变量类型（§2）", "变量类型必须是具体类型")
				e.vars[n.Name] = ""
			} else {
				e.vars[n.Name] = k
			}
		} else {
			e.vars[n.Name] = ""
		}
	case *xfront.AssignStmt:
		if id, ok := n.Target.(*xfront.IdentExpr); ok {
			tt, known := e.vars[id.Name]
			vt := e.inferExpected(n.Value, tt)
			if known && tt != "" {
				if n.Op != "=" {
					e.checkOperand(id.Name, tt, n.Op) // 复合赋值要求操作数合法
				}
				if !e.canAssign(vt, tt) {
					e.errf(n.P, assignDiag(vt, tt),
						fmt.Sprintf("赋值类型不符：%s 不能赋给 `%s` 的声明类型 %s（§2.6）", describeKey(vt), id.Name, tt),
						hintFor(vt, tt))
				}
			}
		} else if mem, ok := n.Target.(*xfront.Member); ok {
			ft := e.inferMember(mem) // 完成私有字段访问校验
			vt := e.inferExpected(n.Value, ft.key)
			if ft.key != "" && !e.canAssign(vt, ft.key) {
				e.errf(n.P, assignDiag(vt, ft.key),
					fmt.Sprintf("字段赋值类型不符：%s 不能赋给字段类型 %s（§2.6）", describeKey(vt), ft.key), "")
			}
		} else if ix, ok := n.Target.(*xfront.Index); ok {
			xt := e.infer(ix.X)
			elem := elemTypeOf(xt.key)
			vt := e.inferExpected(n.Value, elem)
			if elem != "" && !assignable(vt, elem) {
				e.errf(n.P, assignDiag(vt, elem),
					fmt.Sprintf("下标赋值类型不符：%s 不能赋给元素类型 %s（§2.6）", describeKey(vt), elem), "")
			}
		} else if tm, ok := n.Target.(*xfront.TupleMember); ok {
			tt := e.infer(tm)
			vt := e.inferExpected(n.Value, tt.key)
			if tt.key != "" && !assignable(vt, tt.key) {
				e.errf(n.P, assignDiag(vt, tt.key),
					fmt.Sprintf("元组元素赋值类型不符：%s 不能赋给元素类型 %s（§2.11）", describeKey(vt), tt.key), "")
			}
		} else {
			e.infer(n.Value)
		}
		e.infer(n.Target) // 目标子表达式的读取检查（越界等留给运行时）
	case *xfront.IncDecStmt:
		if id, ok := n.Target.(*xfront.IdentExpr); ok {
			e.checkOperand(id.Name, e.vars[id.Name], n.Op)
		}
	case *xfront.ExprStmt:
		t := e.infer(n.X)
		if isResultKey(t.key) {
			e.errf(n.X.Pos(), ErResultMustUse,
				"Result 是 @mustUse：不得作为裸表达式语句丢弃（§10.1）",
				"返回、赋给变量/字段/容器、用 try 传播，或调用其成员")
		}
	case *xfront.ReturnStmt:
		if retKey == "void" {
			if n.Value != nil {
				e.errf(n.P, TyAssignability, "void 函数不得返回值（§6.1）", "去掉返回值，或把返回类型改为具体类型")
			}
			return
		}
		if n.Value == nil {
			e.errf(n.P, TyAssignability, "非 void 函数必须返回值（§6.1）", "补充返回值")
			return
		}
		vt := e.inferExpected(n.Value, retKey)
		if !e.canAssign(vt, retKey) {
			e.errf(n.Value.Pos(), assignDiag(vt, retKey),
				fmt.Sprintf("返回类型不符：%s 不能赋给声明的返回类型 %s（§2.6）", describeKey(vt), retKey),
				hintFor(vt, retKey))
		}
	case *xfront.ThrowStmt:
		e.infer(n.Value)
	case *xfront.IfStmt:
		e.checkCond(n.Cond)
		e.walkFunc(n.Then, retKey)
		if eb, ok := n.Else.(*xfront.Block); ok {
			e.walkFunc(eb, retKey)
		} else if n.Else != nil {
			e.walkStmt(n.Else, retKey)
		}
	case *xfront.WhileStmt:
		e.checkCond(n.Cond)
		e.walkFunc(n.Body, retKey)
	case *xfront.DoWhileStmt:
		e.walkFunc(n.Body, retKey)
		e.checkCond(n.Cond)
	case *xfront.ForStmt:
		e.infer(n.Src)
		e.walkFunc(n.Body, retKey)
	case *xfront.SwitchStmt:
		vt := e.infer(n.Value)
		if _, isTuple := splitTupleKey(vt.key); isTuple {
			e.errf(n.P, TyTuple, "元组不能作为 switch 值（§2.11）", "")
		}
		e.checkEnumSwitch(n, vt.key)
		e.checkSwitchDefaultLast(n)
		for _, c := range n.Cases {
			if c.Expr != nil {
				e.infer(c.Expr)
			}
			e.walkFunc(&xfront.Block{P: n.P, Stmts: c.Stmts}, retKey)
		}
		if n.Default != nil {
			e.walkFunc(&xfront.Block{P: n.P, Stmts: n.Default.Stmts}, retKey)
		}
	case *xfront.DeferStmt:
		if n.Errdefer && !isResultKey(e.ret) {
			e.errf(n.P, ErErrdeferContext,
				"errdefer 只能出现在返回 Result 的函数或闭包中（§10.3）", "改用 defer，或把函数返回类型改为 Result")
		}
		e.checkCleanup(n)
		oldCleanup := e.inCleanup
		e.inCleanup = true
		if n.Block != nil {
			e.walkFunc(n.Block, retKey)
		} else if n.Stmt != nil {
			e.walkStmt(n.Stmt, retKey)
		}
		e.inCleanup = oldCleanup
	case *xfront.LabeledStmt:
		if n.Stmt != nil {
			e.walkStmt(n.Stmt, retKey)
		}
	case *xfront.Block:
		e.walkFunc(n, retKey)
	case *xfront.BreakStmt, *xfront.ContinueStmt, *xfront.GotoStmt, *xfront.EmptyStmt:
	}
}

func (e *tyenv) checkCond(c xfront.Expr) {
	t := e.infer(c)
	if t.key != "" && t.key != "Bool" {
		e.errf(c.Pos(), TyCondNotBool, "条件必须是 Bool（§6.1），得到 "+describeKey(t), "")
	}
}

func (e *tyenv) checkOperand(name, tt, op string) {
	if tt == "" {
		return
	}
	if !isIntType(tt) {
		e.errf(xfront.Pos{}, TyBadOperand, "`"+op+"` 只用于整数类型，`"+name+"` 的类型是 "+tt+"（§6.1）", "")
	}
}

// elemTypeOf 从容器类型串提取元素类型（"X[]"→X、"List<X>"→X、"Map<K,V>"→V）。
func elemTypeOf(key string) string {
	if strings.HasSuffix(key, "[]") {
		return key[:len(key)-2]
	}
	if strings.HasPrefix(key, "List<") && strings.HasSuffix(key, ">") {
		return key[5 : len(key)-1]
	}
	if strings.HasPrefix(key, "Map<") && strings.HasSuffix(key, ">") {
		inner := key[4 : len(key)-1]
		depth := 0
		for i, r := range inner {
			switch r {
			case '<':
				depth++
			case '>':
				depth--
			case ',':
				if depth == 0 {
					return strings.TrimSpace(inner[i+1:])
				}
			}
		}
	}
	return ""
}

// infer 推断表达式静态类型（不修改环境；未知返回 ""）。
func (e *tyenv) infer(x xfront.Expr) texpr {
	switch n := x.(type) {
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
		t := texpr{key: k, lit: 1}
		txt := strings.ReplaceAll(n.Text, "_", "")
		if txt != "" {
			if iv, err := strconv.ParseInt(txt, n.Base, 64); err == nil {
				t.hasInt, t.intVal = true, iv
			} else if uv, err := strconv.ParseUint(txt, n.Base, 64); err == nil {
				t.hasInt, t.isUInt, t.uintVal = true, true, uv
			}
		}
		return t
	case *xfront.FloatLitExpr:
		if n.HasSuffixF {
			return texpr{key: "Float", lit: 2}
		}
		return texpr{key: "Double", lit: 2}
	case *xfront.CharLitExpr:
		return texpr{key: "Char"}
	case *xfront.BoolLit:
		return texpr{key: "Bool"}
	case *xfront.NullLit:
		return texpr{key: "null", lit: 4}
	case *xfront.StrLitExpr:
		for _, p := range n.Parts {
			if p.Expr != nil {
				e.checkTupleInterp(p.Expr.Pos(), e.infer(p.Expr))
			}
		}
		return texpr{key: "String", lit: 3}
	case *xfront.IdentExpr:
		if k, ok := e.vars[n.Name]; ok {
			return texpr{key: k}
		}
		if k, ok := e.fields[n.Name]; ok {
			return texpr{key: k}
		}
		if e.cls != nil {
			if n.Name == "self" && !e.cls.instance {
				e.errf(n.P, TyModifier, "static 方法不能使用 self（§1.6）", "")
				return texpr{}
			}
			if canon, isPriv := e.cls.srcToCanon[n.Name]; isPriv {
				e.errf(n.P, TyPrivField, "裸 `"+n.Name+"` 引用私有字段：类内只能写 `"+canon+"`（§7.4）", "")
				return texpr{key: e.vars[canon]}
			}
			// 继承字段的裸名访问（§7.3/§7.4）。
			if e.cls.instance && e.a.tc != nil {
				if fk, vis, owner, ok := e.a.tc.findField(e.cls.className, n.Name); ok {
					if vis == "private" {
						e.errf(n.P, TyVisibility, "裸 `"+n.Name+"` 访问父类私有字段被拒绝（§7.3/§7.4）", "")
						return texpr{}
					}
					if vis == "protected" && !e.canAccessProtected(e.cls.className, owner) {
						e.errf(n.P, TyVisibility, "裸 `"+n.Name+"` 访问受保护字段被拒绝（§7.3）", "")
						return texpr{}
					}
					return texpr{key: fk}
				}
			}
		}
		return texpr{}
	case *xfront.Paren:
		return e.infer(n.X)
	case *xfront.Unary:
		t := e.infer(n.X)
		switch n.Op {
		case "try": // try 传播：Result<T,E> → T（§10.2）
			if e.inCleanup {
				e.errf(n.P, ErTryContext, "try 不能用于 defer/errdefer 清理体（§10.3）", "清理必须非抛出")
			}
			if e.fnKind == "ctor" || e.fnKind == "deinit" || e.fnKind == "main" {
				e.errf(n.P, ErTryContext, "try 不能用于构造器、deinit 或 main（§10.2）", "把错误处理移到返回 Result 的函数中")
			}
			if t.key != "" && !isResultKey(t.key) {
				e.errf(n.P, ErTryContext, "try 只能作用于 Result（§10.2），得到 "+describeKey(t), "")
				return texpr{}
			}
			if !isResultKey(t.key) {
				return texpr{}
			}
			tk, ek, ok := resultArgs(t.key)
			if !ok || tk == "" || ek == "" {
				e.errf(n.P, ErResultCtor, "Result 类型实参不完整：try 需要 Result<T,E>（§10.1）", "")
				return texpr{}
			}
			if !isResultKey(e.ret) {
				e.errf(n.P, ErTryContext, "使用 try 的函数或闭包必须返回 Result<_,E2>（§10.2）", "把外层返回类型改为 Result")
			} else if _, e2, ok2 := resultArgs(e.ret); ok2 && e2 != "" && !assignableError(ek, e2) {
				e.errf(n.P, ErTryContext, "try 的错误类型 "+ek+" 不能赋给外层错误类型 "+e2+"（§10.2）", "禁止隐式字符串化；改用可赋值的错误类型")
			}
			if tk == "void" {
				return texpr{key: "void"}
			}
			return texpr{key: tk}
		case "!":
			if t.key != "Bool" && t.key != "" {
				e.errf(n.P, TyBadOperand, "`!` 操作数必须是 Bool（§7.2），得到 "+describeKey(t), "")
			}
			return texpr{key: "Bool"}
		case "-":
			if t.key != "" && !isIntType(t.key) && !isFloatType(t.key) {
				e.errf(n.P, TyBadOperand, "一元 `-` 操作数必须是数值（§7.2），得到 "+describeKey(t), "")
			}
			if t.hasInt {
				if t.isUInt {
					// 仅 2^63 可经负号表示为 MinInt64；更大的量级禁止 int64 回绕。
					if t.uintVal == 1<<63 {
						t.intVal, t.isUInt = -1<<63, false
					} else {
						t.intBad = true
					}
				} else if t.intVal == -1<<63 {
					t.intBad = true // -MinInt64 不可表示
				} else {
					t.intVal = -t.intVal
				}
			}
			return t
		}
		return t
	case *xfront.Binary:
		return e.inferBinary(n)
	case *xfront.Ternary:
		e.checkCond(n.Cond)
		a := e.infer(n.Then)
		b := e.infer(n.Else)
		if a.key == b.key {
			return a
		}
		return texpr{}
	case *xfront.Call:
		return e.inferCall(n)
	case *xfront.Tuple:
		parts := make([]string, len(n.Elems))
		elems := make([]texpr, len(n.Elems))
		for i, el := range n.Elems {
			elems[i] = e.infer(el)
			parts[i] = elems[i].key
		}
		return texpr{key: "(" + strings.Join(parts, ",") + ")", elems: elems}
	case *xfront.ArrayLit:
		if len(n.Elems) == 0 {
			return texpr{}
		}
		k := e.infer(n.Elems[0]).key
		for _, el := range n.Elems[1:] {
			if e.infer(el).key != k {
				return texpr{}
			}
		}
		if k == "" {
			return texpr{}
		}
		return texpr{key: k + "[]"}
	case *xfront.MapLit:
		if len(n.Keys) == 0 {
			return texpr{}
		}
		kk := e.infer(n.Keys[0]).key
		vv := e.infer(n.Vals[0]).key
		if kk == "" || vv == "" {
			return texpr{}
		}
		return texpr{key: "Map<" + kk + "," + vv + ">"}
	case *xfront.Index:
		xt := e.infer(n.X)
		if el := elemTypeOf(xt.key); el != "" {
			return texpr{key: el}
		}
		return texpr{}
	case *xfront.TupleMember:
		xt := e.infer(n.X)
		if xt.key == "" {
			return texpr{}
		}
		parts, ok := splitTupleKey(xt.key)
		if !ok {
			e.errf(n.P, TyTuple, "`.N` 元素访问只用于元组（§2.11），得到 "+describeKey(xt), "")
			return texpr{}
		}
		if n.Index >= len(parts) {
			e.errf(n.P, TyTuple,
				fmt.Sprintf("元组下标越界：%s 只有 %d 个元素，选择器 .%d（§2.11）", xt.key, len(parts), n.Index), "")
			return texpr{}
		}
		elem := parts[n.Index]
		if (isOptional(xt.key) || n.NullSafe) && !isOptional(elem) {
			elem += "?"
		}
		return texpr{key: elem}
	case *xfront.NewArray:
		return texpr{key: typeKey(n.Type) + "[]"}
	case *xfront.Lambda:
		return texpr{key: "fn", lit: 5} // 闭包字面量：按 §2.6 闭包字面量规则对函数类型目标放行
	case *xfront.Member:
		return e.inferMember(n)
	case *xfront.New:
		// §8.3：泛型函数内不能写 new T()（类型参数不是可构造的运行时类型）。
		if nt, ok := n.Type.(*xfront.NamedType); ok && len(nt.Args) == 0 && len(nt.Qual) == 1 && e.typePars[nt.Qual[0]] {
			e.errf(n.P, GenScope, "泛型函数内不能写 new "+nt.Qual[0]+"()：类型参数不是可构造的运行时类型（§8.3）", "改为具体类型，或由调用方传入构造好的值")
		}
		if nt, ok := n.Type.(*xfront.NamedType); ok && len(nt.Qual) == 1 && e.a.tc != nil {
			if info, found := e.a.tc.types[nt.Qual[0]]; found {
				if info.kind == "class" && info.mod.Abstract {
					e.errf(n.P, TyNewAbstract, "抽象类 `"+nt.Qual[0]+"` 不能实例化（§2.6）", "由具体子类实例化，或去掉 abstract")
				}
			}
		}
		for _, a := range n.Args {
			e.infer(a)
		}
		return texpr{}
	}
	return texpr{}
}

func (e *tyenv) inferMember(n *xfront.Member) texpr {
	// self.x：私有字段访问规则（§7.4）；其他接收者的裸成员静态层不推断
	if e.cls != nil && isSelfIdent(n.X) {
		if e.cls.canonPriv[n.Name] {
			e.errf(n.P, TyPrivField, "`self."+n.Name+"` 非法：类内引用私有字段只能写裸 `"+n.Name+"`（§7.4）", "")
			return texpr{key: e.vars[n.Name]}
		}
		if canon, isPriv := e.cls.srcToCanon[n.Name]; isPriv {
			e.errf(n.P, TyPrivField, "`self."+n.Name+"` 引用私有字段（规范名 `"+canon+"`）：类内只能写裸 `"+canon+"`（§7.4）", "")
			return texpr{key: e.vars[canon]}
		}
		if k, ok := e.vars[n.Name]; ok && e.cls.instance {
			return texpr{key: k} // 公开实例字段
		}
		// 继承字段：self.<name>（§7.3/§7.4）。
		if e.cls.instance && e.a.tc != nil {
			if fk, vis, owner, ok := e.a.tc.findField(e.cls.className, n.Name); ok {
				if vis == "private" {
					e.errf(n.P, TyVisibility, "`self."+n.Name+"` 访问父类私有字段被拒绝（§7.3/§7.4）", "")
					return texpr{}
				}
				if vis == "protected" && !e.canAccessProtected(e.cls.className, owner) {
					e.errf(n.P, TyVisibility, "`self."+n.Name+"` 访问受保护字段被拒绝（§7.3）", "")
					return texpr{}
				}
				return texpr{key: fk}
			}
		}
		return texpr{}
	}
	// 其他接收者：类类型变量的成员访问（外部私有访问检查，§7.4）
	rt := e.infer(n.X)
	if _, isTuple := splitTupleKey(rt.key); isTuple {
		e.errf(n.P, TyTuple, "元组没有成员或方法（§2.11：元素只能写作 `.0`、`.1`，不能写 `."+n.Name+"`）", "")
		return texpr{}
	}
	if isResultKey(rt.key) {
		e.errf(n.P, ErResultMember, "Result 成员必须调用：写 `"+n.Name+"()`（§10.1）", "成员全部是方法")
		return texpr{}
	}
	if c := e.a.tc; c != nil {
		if info, ok := c.types[rt.key]; ok && info.kind == "protocol" {
			e.errf(n.P, TyProtoMember, "协议变量没有字段或属性（§4.4）：`"+n.Name+"`", "协议只暴露声明的方法")
			return texpr{}
		}
		if info, ok := c.types[rt.key]; ok && info.kind == "class" {
			if info.canonPriv == nil {
				canon := map[string]bool{}
				src := map[string]string{}
				pub := map[string]string{}
				for _, f := range info.class.Fields {
					if f.Mod.Vis == "private" || strings.HasPrefix(f.Name, "_") {
						canon[f.Canonical] = true
						if f.Canonical != f.Name {
							src[f.Name] = f.Canonical
						}
					} else {
						pub[f.Canonical] = typeKey(f.Type)
					}
				}
				info.canonPriv = canon
				info.srcToCanon = src
				info.publicFields = pub
			}
			if info.canonPriv[n.Name] {
				e.errf(n.P, TyPrivField, "外部访问私有字段 `"+n.Name+"`：`"+rt.key+"` 的私有字段只能类内裸写（§7.4）", "")
				return texpr{}
			}
			if canon, isPriv := info.srcToCanon[n.Name]; isPriv {
				e.errf(n.P, TyPrivField, "外部访问私有字段 `"+n.Name+"`（规范名 `"+canon+"`）：私有访问错误（§7.4）", "")
				return texpr{}
			}
			if fk, vis, owner, ok := c.findField(rt.key, n.Name); ok {
				switch vis {
				case "private":
					e.errf(n.P, TyVisibility, "外部访问私有字段 `"+n.Name+"` 被拒绝（§7.3）", "")
					return texpr{}
				case "protected":
					if !e.canAccessProtected(rt.key, owner) {
						e.errf(n.P, TyVisibility, "受保护字段 `"+n.Name+"` 不可访问（§7.3：需 self/super 或当前类/子类静态类型）", "")
						return texpr{}
					}
					return texpr{key: fk}
				default:
					return texpr{key: fk}
				}
			}
			if k, ok := info.publicFields[n.Name]; ok {
				return texpr{key: k}
			}
		}
	}
	return texpr{}
}

func (e *tyenv) inferCall(n *xfront.Call) texpr {
	// 内置函数（impl/README）。
	if id, ok := n.Callee.(*xfront.IdentExpr); ok {
		switch id.Name {
		case "print":
			for _, a := range n.Args {
				e.infer(a)
			}
			return texpr{key: "void"}
		case "str":
			if len(n.Args) == 1 {
				e.infer(n.Args[0])
			}
			return texpr{key: "String"}
		case "Ok", "Err":
			// 无目标类型：按 §10.1 报错（有目标类型时由 inferExpected 先行拦截）。
			return e.inferResultCtor(n, id.Name, "")
		}
	}
	// 方法调用：recv.method(args)
	if mem, ok := n.Callee.(*xfront.Member); ok {
		rt := e.infer(mem.X)
		if isResultKey(rt.key) {
			return e.resultMember(rt, mem, n.Args, n.P)
		}
		if e.a.tc != nil {
			if info, ok := e.a.tc.types[rt.key]; ok && info.kind == "protocol" {
				if !e.a.tc.protocolHasMethod(rt.key, mem.Name) {
					e.errf(n.P, TyProtoMember,
						"协议变量只能调用协议声明的方法（§4.4）：`"+mem.Name+"` 不在协议合同中", "改用协议声明的方法，或先 `as` 到具体类")
				}
			}
		}
		e.checkMethodVisibility(rt.key, mem.Name, n.P)
		args := make([]texpr, len(n.Args))
		for i, a := range n.Args {
			args[i] = e.infer(a)
		}
		return e.methodRet(rt, mem.Name, args, n.P)
	}
	// 顶层函数调用：普通/泛型候选解析（§8.2 重载与推断）。
	if id, ok := n.Callee.(*xfront.IdentExpr); ok {
		if _, found := e.funcs[id.Name]; found {
			return e.resolveUserCall(n, id.Name)
		}
	}
	for _, a := range n.Args {
		e.infer(a)
	}
	return texpr{}
}

// splitTopLevel 按顶层逗号切分泛型实参串；括号/尖括号/方括号内的逗号不切分。
func splitTopLevel(inner string) []string {
	var parts []string
	depth := 0
	start := 0
	for i, r := range inner {
		switch r {
		case '(', '<', '[':
			depth++
		case ')', '>', ']':
			depth--
		case ',':
			if depth == 0 {
				parts = append(parts, strings.TrimSpace(inner[start:i]))
				start = i + 1
			}
		}
	}
	if start <= len(inner) {
		parts = append(parts, strings.TrimSpace(inner[start:]))
	}
	return parts
}

// methodRet 按接收者类型与成员表推断方法返回类型（§9.1 总表）。
func (e *tyenv) methodRet(rt texpr, name string, args []texpr, p xfront.Pos) texpr {
	k := rt.key
	genericArg := func(key, prefix string) string {
		if strings.HasPrefix(key, prefix) && strings.HasSuffix(key, ">") {
			inner := key[len(prefix) : len(key)-1]
			parts := splitTopLevel(inner)
			if len(parts) > 0 {
				return parts[0]
			}
		}
		return ""
	}
	mapVal := func(key string) string {
		if strings.HasPrefix(key, "Map<") && strings.HasSuffix(key, ">") {
			inner := key[4 : len(key)-1]
			for i, r := 0, rune(0); i < len(inner); i++ {
				_ = r
			}
			depth := 0
			for i, r := range inner {
				switch r {
				case '<':
					depth++
				case '>':
					depth--
				case ',':
					if depth == 0 {
						return strings.TrimSpace(inner[i+1:])
					}
				}
			}
		}
		return ""
	}
	switch {
	case k == "String":
		switch name {
		case "length", "indexOf":
			return texpr{key: "Int"}
		case "substring", "trim", "replace", "toUpper", "toLower":
			return texpr{key: "String"}
		case "split":
			return texpr{key: "String[]"}
		case "startsWith", "endsWith":
			return texpr{key: "Bool"}
		}
	case strings.HasSuffix(k, "[]"):
		switch name {
		case "length":
			return texpr{key: "Int"}
		case "join":
			return texpr{key: "String"}
		}
	case strings.HasPrefix(k, "List<"):
		switch name {
		case "get", "remove": // §9.4：remove(index) 删除并返回被删元素
			return texpr{key: genericArg(k, "List<")}
		case "length":
			return texpr{key: "Int"}
		case "push", "insert", "set", "clear":
			return texpr{key: "void"}
		}
	case strings.HasPrefix(k, "Map<"):
		switch name {
		case "get": // §9.5：get 返回 V?（缺失键 null）
			return texpr{key: mapVal(k) + "?"}
		case "getOr":
			return texpr{key: mapVal(k)}
		case "has":
			return texpr{key: "Bool"}
		case "length":
			return texpr{key: "Int"}
		case "put", "remove", "clear":
			return texpr{key: "void"}
		case "keys":
			return texpr{key: genericArg(k, "Map<") + "[]"}
		case "values":
			return texpr{key: mapVal(k) + "[]"}
		}
	case strings.HasPrefix(k, "Set<"):
		switch name {
		case "add", "has", "remove":
			return texpr{key: "Bool"}
		case "at":
			return texpr{key: genericArg(k, "Set<")}
		case "length":
			return texpr{key: "Int"}
		case "clear":
			return texpr{key: "void"}
		}
	case strings.HasPrefix(k, "Result<"):
		inner := k[len("Result<") : len(k)-1]
		parts := strings.Split(inner, ",")
		tk, ek := "", ""
		if len(parts) > 0 {
			tk = strings.TrimSpace(parts[0])
		}
		if len(parts) > 1 {
			ek = strings.TrimSpace(parts[1])
		}
		switch name {
		case "isOk", "isErr":
			return texpr{key: "Bool"}
		case "value", "unwrapOr":
			return texpr{key: tk}
		case "error":
			return texpr{key: ek}
		}
	}
	// 未知接收者（动态分派后续切片）：放行，返回未知
	for _, a := range args {
		_ = a
	}
	_ = p
	return texpr{}
}

func (e *tyenv) inferBinary(n *xfront.Binary) texpr {
	if ta, isTypeAs := n.R.(*xfront.TypeAsExpr); isTypeAs {
		e.checkTypeParamRef(ta.Type, n.P)
		lt := e.infer(n.L)
		rhs := typeKey(ta.Type)
		_, lTuple := splitTupleKey(lt.key)
		_, rTuple := splitTupleKey(rhs)
		switch n.Op {
		case "is":
			if (lTuple || rTuple) && lt.key != rhs {
				e.errf(n.P, TyTuple, "元组不参与有意义的 is 转换（§2.11）："+describeKey(lt)+" vs "+rhs, "")
			}
			return texpr{key: "Bool"}
		case "as":
			if (lTuple || rTuple) && lt.key != rhs {
				e.errf(n.P, TyTuple, "元组 as 只允许同型恒等（§2.11）："+describeKey(lt)+" vs "+rhs, "")
			}
			return texpr{key: rhs}
		case "as?":
			if (lTuple || rTuple) && lt.key != rhs {
				e.errf(n.P, TyTuple, "元组 as? 只允许同型恒等（§2.11）："+describeKey(lt)+" vs "+rhs, "")
			}
			return texpr{key: rhs + "?"}
		}
	}
	lt := e.infer(n.L)
	rt := e.infer(n.R)
	switch n.Op {
	case "&&", "||":
		if (lt.key != "" && lt.key != "Bool") || (rt.key != "" && rt.key != "Bool") {
			e.errf(n.P, TyCondNotBool, "`"+n.Op+"` 操作数必须是 Bool（§7.2）", "")
		}
		return texpr{key: "Bool"}
	case "==", "!=", "===", "!==":
		// §10.1：Result 无 ==
		if strings.HasPrefix(lt.key, "Result<") || strings.HasPrefix(rt.key, "Result<") {
			e.errf(n.P, TyBadOperand, "Result 没有 ==（§10.1：用 isOk/isErr 成员检查）", "")
			return texpr{key: "Bool"}
		}
		if lt.key == "null" || rt.key == "null" {
			other := lt.key
			if other == "null" {
				other = rt.key
			}
			if other != "null" && other != "" && !isRefType(other) && !isOptional(other) {
				e.errf(n.P, TyBadOperand, "null 只与引用类型或 T? 比较（§2.6），对方类型是 "+other, "")
			}
			return texpr{key: "Bool"}
		}
		if lt.key != "" && rt.key != "" && lt.key != rt.key {
			if _, _, ok := adaptIntLiteralKeys(lt, rt); !ok {
				e.errf(n.P, TyBadOperand, "比较运算两侧类型必须相同（§2.6 结构化匹配禁止）："+
					lt.key+" vs "+rt.key, "")
			}
		}
		return texpr{key: "Bool"}
	case "<", ">", "<=", ">=":
		if lt.key != "" && rt.key != "" {
			lk, rk := lt.key, rt.key
			if lk != rk {
				a, b, ok := adaptIntLiteralKeys(lt, rt)
				if !ok {
					e.errf(n.P, TyBadOperand, "比较运算要求同族同宽（§2.6 禁止隐式转换）："+
						lt.key+" vs "+rt.key, "")
					return texpr{key: "Bool"}
				}
				lk, rk = a, b
			}
			num := (isIntType(lk) && isIntType(rk)) || (isFloatType(lk) && isFloatType(rk)) ||
				(lk == "Char" && rk == "Char")
			if !num {
				e.errf(n.P, TyBadOperand, "比较运算只用于同族同宽数值或 Char（§2.6 禁止隐式转换）："+
					lt.key+" vs "+rt.key, "")
			}
		}
		return texpr{key: "Bool"}
	case "+":
		if lt.key == "String" || rt.key == "String" {
			// §9.2：String + String 产生新字符串；String 与数值不能直接 +
			if lt.key == "String" && rt.key == "String" {
				return texpr{key: "String"}
			}
			if lt.lit == 3 || rt.lit == 3 { // 字符串字面量拼接？规范只允许 String+String
				e.errf(n.P, TyBadOperand, "String 与非 String 不能直接 +（§9.2）；用 str() 转换", "")
				return texpr{key: "String"}
			}
			e.errf(n.P, TyBadOperand, "String 与非 String 不能直接 +（§9.2）；用 str() 转换", "")
			return texpr{key: "String"}
		}
		return e.arith(n, lt, rt)
	case "-", "*", "/", "%":
		return e.arith(n, lt, rt)
	case "??":
		// 结果类型 = 左侧去 ? 后的类型（§7.2）
		return texpr{key: unwrapOpt(lt.key)}
	case "..<", "...":
		if (lt.key != "" && !isIntType(lt.key)) || (rt.key != "" && !isIntType(rt.key)) {
			e.errf(n.P, TyBadOperand, "区间端点必须是 Int（§6.7）", "")
		}
		return texpr{key: "Range"}
	}
	return texpr{}
}

func (e *tyenv) arith(n *xfront.Binary, lt, rt texpr) texpr {
	if lt.key == "" || rt.key == "" {
		return texpr{}
	}
	li, lf := isIntType(lt.key), isFloatType(lt.key)
	ri, rf := isIntType(rt.key), isFloatType(rt.key)
	switch {
	case li && ri:
		return texpr{key: lt.key} // 同为整数：结果按左侧类型（混合整数宽度属 §2.6 禁止——见下）
	case lf && rf:
		return texpr{key: lt.key}
	case (li || lf) && (ri || rf):
		e.errf(n.P, TyBadOperand, "数值类型混合运算被禁止（§2.6 隐式 widen/narrow 禁止）："+
			lt.key+" "+n.Op+" "+rt.key, "先统一类型再运算")
		return texpr{}
	default:
		e.errf(n.P, TyBadOperand, "算术运算操作数必须是数值（§7.2）："+
			lt.key+" "+n.Op+" "+rt.key, "")
		return texpr{}
	}
}
