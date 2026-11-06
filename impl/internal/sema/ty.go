package sema

import (
	"fmt"
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
)

// texpr 是表达式的静态类型：key 是规范化类型串；lit 标记未定型字面量。
type texpr struct {
	key string // "" = 未知/void 语义上有别：void 用 "void"，未知用 ""
	lit int    // 0 普通；1 整数字面量；2 浮点字面量；3 字符串字面量；4 null
}

var intTypeNames = map[string]bool{
	"Int": true, "Long": true, "Byte": true, "Short": true, "UByte": true,
	"UShort": true, "UInt": true, "ULong": true, "Int128": true, "UInt128": true,
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

func isOptional(key string) bool { return strings.HasSuffix(key, "?") }

func unwrapOpt(key string) string {
	if isOptional(key) {
		return key[:len(key)-1]
	}
	return key
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

// assignable 判断 from 是否可赋给 to（§2.6；lit 提供字面量适配规则）。
func assignable(from texpr, to string) bool {
	if to == "" || from.key == "" {
		return true // 未知类型不误报（边界：推断不出时放行，静默面由后续切片收敛）
	}
	if from.key == to {
		return true
	}
	// 字面量规则（§2.6）。
	switch from.lit {
	case 1: // 整数字面量可表示在目标整数类型中（表示性检查在常量求值切片，此处按类型接受）
		return isIntType(to)
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
	// 可选提升：T → T?（§2.6）
	if isOptional(to) && unwrapOpt(to) == from.key {
		return true
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

// tyenv 是一个函数的类型环境。
type tyenv struct {
	a      *analyzer
	vars   map[string]string // 局部/参数/类字段（规范名）→ 类型串
	funcs  map[string][]*xfront.TopFunc
	fields map[string]string // 顶层字段 → 类型串
	cls    *classCtx         // 类方法体上下文（nil = 顶层函数）
}

func (e *tyenv) errf(p xfront.Pos, code, msg, hint string) {
	e.a.errf(p, code, msg, hint)
}

// analyzeTypes 对整个编译单元做类型检查。
func (a *analyzer) analyzeTypes(file string, u *xfront.CompilationUnit) {
	e := &tyenv{a: a, vars: map[string]string{}, funcs: map[string][]*xfront.TopFunc{}, fields: map[string]string{}}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			e.funcs[n.Name] = append(e.funcs[n.Name], n)
			// void 参数/返回之外的参数类型 void 检查
			for _, p := range n.Params {
				if typeKey(p.Type) == "void" {
					a.errf(p.P, TyAssignability, "void 不能作为参数类型（§2）", "参数类型必须是具体类型")
				}
			}
		case *xfront.TopField:
			k := typeKey(n.Type)
			if k == "void" {
				a.errf(n.P, TyAssignability, "void 不能作为字段类型（§2）", "字段类型必须是具体类型")
				continue
			}
			e.fields[n.Name] = k
			if n.Init != nil {
				it := e.infer(n.Init)
				if !assignable(it, k) {
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
			for _, p := range fn.Params {
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
		if n.Init != nil {
			it := e.infer(n.Init)
			if n.Type != nil {
				k := typeKey(n.Type)
				if k == "void" {
					e.errf(n.P, TyAssignability, "void 不能作为变量类型（§2）", "变量类型必须是具体类型")
					e.vars[n.Name] = ""
				} else {
					if !assignable(it, k) {
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
		vt := e.infer(n.Value)
		if id, ok := n.Target.(*xfront.IdentExpr); ok {
			if tt, known := e.vars[id.Name]; known && tt != "" {
				if n.Op != "=" {
					e.checkOperand(id.Name, tt, n.Op) // 复合赋值要求操作数合法
				}
				if !assignable(vt, tt) {
					e.errf(n.P, assignDiag(vt, tt),
						fmt.Sprintf("赋值类型不符：%s 不能赋给 `%s` 的声明类型 %s（§2.6）", describeKey(vt), id.Name, tt),
						hintFor(vt, tt))
				}
			}
		} else if mem, ok := n.Target.(*xfront.Member); ok {
			vt := e.infer(n.Value)
			ft := e.inferMember(mem) // 完成私有字段访问校验
			if ft.key != "" && !assignable(vt, ft.key) {
				e.errf(n.P, assignDiag(vt, ft.key),
					fmt.Sprintf("字段赋值类型不符：%s 不能赋给字段类型 %s（§2.6）", describeKey(vt), ft.key), "")
			}
		} else if ix, ok := n.Target.(*xfront.Index); ok {
			xt := e.infer(ix.X)
			elem := elemTypeOf(xt.key)
			if elem != "" && !assignable(vt, elem) {
				e.errf(n.P, assignDiag(vt, elem),
					fmt.Sprintf("下标赋值类型不符：%s 不能赋给元素类型 %s（§2.6）", describeKey(vt), elem), "")
			}
		}
		e.infer(n.Target) // 目标子表达式的读取检查（越界等留给运行时）
	case *xfront.IncDecStmt:
		if id, ok := n.Target.(*xfront.IdentExpr); ok {
			e.checkOperand(id.Name, e.vars[id.Name], n.Op)
		}
	case *xfront.ExprStmt:
		e.infer(n.X)
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
		vt := e.infer(n.Value)
		if !assignable(vt, retKey) {
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
		e.infer(n.Value)
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
		if n.Block != nil {
			e.walkFunc(n.Block, retKey)
		} else if n.Stmt != nil {
			e.walkStmt(n.Stmt, retKey)
		}
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
	case *xfront.NullLit:
		return texpr{key: "null", lit: 4}
	case *xfront.StrLitExpr:
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
		}
		return texpr{}
	case *xfront.Paren:
		return e.infer(n.X)
	case *xfront.Unary:
		t := e.infer(n.X)
		switch n.Op {
		case "try": // try 传播：Result<T,E> → T（§10.2）
			if strings.HasPrefix(t.key, "Result<") && strings.HasSuffix(t.key, ">") {
				inner := t.key[len("Result<") : len(t.key)-1]
				if i := strings.Index(inner, ","); i >= 0 {
					return texpr{key: strings.TrimSpace(inner[:i])}
				}
			}
			return texpr{}
		case "!":
			if t.key != "Bool" && t.key != "" {
				e.errf(n.P, TyBadOperand, "`!` 操作数必须是 Bool（§7.2），得到 "+describeKey(t), "")
			}
			return texpr{key: "Bool"}
		case "-":
			if t.key != "" && !isIntType(t.key) && !isFloatType(t.key) {
				e.errf(n.P, TyBadOperand, "一元 `-` 操作数必须是数值（§7.2），得到 "+describeKey(t), "")
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
		for i, el := range n.Elems {
			parts[i] = e.infer(el).key
		}
		return texpr{key: "(" + strings.Join(parts, ",") + ")"}
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
		if strings.HasPrefix(xt.key, "(") && strings.HasSuffix(xt.key, ")") {
			inner := xt.key[1 : len(xt.key)-1]
			parts := strings.Split(inner, ",")
			if n.Index < len(parts) {
				return texpr{key: strings.TrimSpace(parts[n.Index])}
			}
		}
		return texpr{}
	case *xfront.NewArray:
		return texpr{key: typeKey(n.Type) + "[]"}
	case *xfront.Lambda:
		return texpr{key: "fn", lit: 5} // 闭包字面量：按 §2.6 闭包字面量规则对函数类型目标放行
	case *xfront.Member:
		return e.inferMember(n)
	case *xfront.New:
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
		return texpr{}
	}
	// 其他接收者：类类型变量的成员访问（外部私有访问检查，§7.4）
	rt := e.infer(n.X)
	if c := e.a.tc; c != nil {
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
			for _, a := range n.Args {
				e.infer(a)
			}
			return texpr{key: "Result<,>"} // 泛型实参由目标类型适配（§2.6 错误值规则骨架）
		}
	}
	// 方法调用：recv.method(args)
	if mem, ok := n.Callee.(*xfront.Member); ok {
		rt := e.infer(mem.X)
		args := make([]texpr, len(n.Args))
		for i, a := range n.Args {
			args[i] = e.infer(a)
		}
		return e.methodRet(rt, mem.Name, args, n.P)
	}
	// 顶层函数调用：按实参数选重载，检查实参可赋值性。
	if id, ok := n.Callee.(*xfront.IdentExpr); ok {
		if fns, found := e.funcs[id.Name]; found {
			for _, f := range fns {
				if len(f.Params) != len(n.Args) {
					continue
				}
				for i, p := range f.Params {
					at := e.infer(n.Args[i])
					pk := typeKey(p.Type)
					if !assignable(at, pk) {
						e.errf(n.Args[i].Pos(), TyAssignability,
							fmt.Sprintf("实参 %d 类型 %s 不能赋给形参 %s（§2.6）", i+1, describeKey(at), pk),
							hintFor(at, pk))
					}
				}
				if f.Void {
					return texpr{key: "void"}
				}
				return texpr{key: typeKey(f.Ret)}
			}
			return texpr{}
		}
	}
	for _, a := range n.Args {
		e.infer(a)
	}
	return texpr{}
}

// methodRet 按接收者类型与成员表推断方法返回类型（§9.1 总表）。
func (e *tyenv) methodRet(rt texpr, name string, args []texpr, p xfront.Pos) texpr {
	k := rt.key
	genericArg := func(key, prefix string) string {
		if strings.HasPrefix(key, prefix) && strings.HasSuffix(key, ">") {
			inner := key[len(prefix) : len(key)-1]
			parts := strings.Split(inner, ",")
			return strings.TrimSpace(parts[0])
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
		case "get":
			return texpr{key: genericArg(k, "List<")}
		case "length":
			return texpr{key: "Int"}
		case "push", "insert", "set", "remove", "clear":
			return texpr{key: "void"}
		}
	case strings.HasPrefix(k, "Map<"):
		switch name {
		case "get", "getOr":
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
		case "add", "has":
			return texpr{key: "Bool"}
		case "at":
			return texpr{key: genericArg(k, "Set<")}
		case "length":
			return texpr{key: "Int"}
		case "remove", "clear":
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
	if _, isTypeAs := n.R.(*xfront.TypeAsExpr); isTypeAs {
		switch n.Op {
		case "is":
			e.infer(n.L)
			return texpr{key: "Bool"}
		case "as":
			e.infer(n.L)
			return texpr{key: typeKey(n.R.(*xfront.TypeAsExpr).Type)}
		case "as?":
			e.infer(n.L)
			return texpr{key: typeKey(n.R.(*xfront.TypeAsExpr).Type) + "?"}
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
	case "==", "!=":
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
			e.errf(n.P, TyBadOperand, "比较运算两侧类型必须相同（§2.6 结构化匹配禁止）："+
				lt.key+" vs "+rt.key, "")
		}
		return texpr{key: "Bool"}
	case "<", ">", "<=", ">=":
		if lt.key != "" && rt.key != "" {
			num := (isIntType(lt.key) && isIntType(rt.key)) || (isFloatType(lt.key) && isFloatType(rt.key)) ||
				(lt.key == "Char" && rt.key == "Char")
			if !num {
				e.errf(n.P, TyBadOperand, "比较运算只用于同族数值或 Char（§2.6 禁止隐式转换）："+
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
