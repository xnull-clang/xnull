// classes_expr.go：类实例在表达式/语句层的生成（M4.4b）。
package codegen

import (
	"fmt"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

func isClassPtr(c string) bool { return strings.HasPrefix(c, "xn_Cls_") }

// classPtrName 从 C 类型名取类名（"xn_Cls_X *" → "X"）。
func classPtrName(c string) (string, bool) {
	if !isClassPtr(c) {
		return "", false
	}
	name := strings.TrimSuffix(strings.TrimPrefix(c, "xn_Cls_"), " *")
	return name, name != ""
}

// classIsGC 判断类引用 C 类型是否按策略归 GC（BND-10）。缺省为 false（ARC）。
func (g *gen) classIsGC(c string) bool {
	name, ok := classPtrName(c)
	if !ok {
		return false
	}
	return g.policy[name] == "gc"
}

// isGCRootC 判断 C 类型是否需要在栈槽位登记 GC 根（S3-02 根集合）。
func (g *gen) isGCRootC(c string) bool {
	if c == "" {
		return false
	}
	// S3-04：String/Bytes/Text/SB 为 GC 对象；容器/数据枚举/类按判定。
	if g.isAnyC(c) || g.isProtoC(c) || isContainerC(c) {
		return true
	}
	return g.isGCTypeC(c)
}

// classIsStack 判断类引用 C 类型是否按逃逸分类可栈分配（S3-03：Escape=none）。
// 防御性校验：类必须无引用字段、无 deinit、无协议 vtable（协议上转需要堆分配头）。
func (g *gen) classIsStack(c string) bool {
	name, ok := classPtrName(c)
	if !ok || !g.stack[name] || g.policy[name] == "gc" {
		return false
	}
	ci, ok := g.classes[name]
	if !ok {
		return false
	}
	for b := ci; b != nil; b = b.base {
		if b.deinit != nil || b.vptr {
			return false
		}
	}
	for _, f := range ci.fields {
		if f.isRefField() || f.isAny || f.isCls || f.isArr {
			return false
		}
		if g.isTupleC(f.ctype) && len(g.tupleRefPaths("o->"+f.cname, f.ctype)) > 0 {
			return false
		}
	}
	return true
}

// isGCTypeC 判断类/数据枚举/单例 C 类型是否 GC 管理（BND-10b）。
func (g *gen) isGCTypeC(c string) bool {
	// S3-04 / ADR-007：String/Text/Bytes/SB 全部 GC 化。
	switch c {
	case "rt_string *", "xrt_bytes_obj *", "xrt_text *", "xrt_sb *":
		return true
	}
	if g.classIsGC(c) {
		return true
	}
	if strings.HasPrefix(c, "xn_Enum_") && strings.HasSuffix(c, " *") {
		name := strings.TrimSuffix(strings.TrimPrefix(c, "xn_Enum_"), " *")
		if ei, ok := g.enums[name]; ok && ei.cls != nil && ei.cls.isGC {
			return true
		}
	}
	if ci, ok := g.singletonOfC(c); ok && ci.isGC {
		return true
	}
	return false
}

// classOfC 由 C 类型名反查类信息（含数据枚举的类结构）。
func (g *gen) classOfC(c string) (*classInfo, bool) {
	if ci, ok := g.singletonOfC(c); ok {
		return ci, true
	}
	if strings.HasPrefix(c, "xn_Enum_") && strings.HasSuffix(c, " *") {
		name := strings.TrimSuffix(strings.TrimPrefix(c, "xn_Enum_"), " *")
		if ei, ok := g.enums[name]; ok && ei.cls != nil {
			return ei.cls, true
		}
	}
	name := strings.TrimSuffix(strings.TrimPrefix(c, "xn_Cls_"), " *")
	ci, ok := g.classes[name]
	return ci, ok
}

// classFieldOf 查字段生成信息。
func (ci *classInfo) fieldOf(name string) (classField, bool) {
	for _, f := range ci.fields {
		if f.name == name || f.cname == name {
			return f, true
		}
	}
	return classField{}, false
}

// selfMethodCall 解析实例方法非限定调用（S2 §5.8 第 3 级）。
// 返回 hit=false 时调用方回退顶层函数；局部/参数同名时按变量优先，不解析为方法。
func (s *scope) selfMethodCall(name string, args []xfront.Expr) (string, bool, error) {
	if s.self == nil {
		return "", false, nil
	}
	if s.params != nil && s.params[name] {
		return "", false, nil
	}
	if _, ok := s.locals[name]; ok {
		return "", false, nil
	}
	m, ok := s.methodFor(s.self.ci, name, args)
	if !ok || m.decl.IsDeinit {
		return "", false, nil
	}
	expr, err := s.methodCall(s.self.ci, m, s.self.cvar, args)
	if err != nil {
		return "", true, err
	}
	return expr, true, nil
}

// classMethodOf 查方法生成信息（含继承链；S2 §5.3 子类不覆写）。
func (ci *classInfo) methodOf(name string) (*classInfo_m, bool) {
	if m, ok := ci.methods[name]; ok {
		return m, true
	}
	if name == "deinit" && ci.deinit != nil {
		return ci.deinit, true
	}
	if ci.base != nil {
		return ci.base.methodOf(name)
	}
	return nil, false
}

// methodFor 按方法名 + 实参个数/类型选择（扩展合法重载）。
func (s *scope) methodFor(ci *classInfo, name string, args []xfront.Expr) (*classInfo_m, bool) {
	argc := len(args)
	if list := ci.overloads[name]; len(list) > 0 {
		var cands []*classInfo_m
		for _, m := range list {
			if len(m.decl.Params) == argc {
				cands = append(cands, m)
			}
		}
		if len(cands) == 1 {
			return cands[0], true
		}
		if len(cands) > 1 {
			argCs := make([]string, 0, argc)
			okTypes := true
			for _, a := range args {
				t, err := s.exprType(a)
				if err != nil {
					okTypes = false
					break
				}
				argCs = append(argCs, t)
			}
			if okTypes {
				for _, m := range cands {
					match := true
					for i, p := range m.decl.Params {
						pc, err := s.g.cType(p.Type)
						if err != nil || pc != argCs[i] {
							match = false
							break
						}
					}
					if match {
						return m, true
					}
				}
			}
			return cands[0], true
		}
	}
	if m, ok := ci.methods[name]; ok && len(m.decl.Params) == argc {
		return m, true
	}
	if name == "deinit" && ci.deinit != nil {
		return ci.deinit, true
	}
	if ci.base != nil {
		return s.methodFor(ci.base, name, args)
	}
	return nil, false
}

// methodOfArgs 按方法名 + 实参个数选择（扩展合法重载；vtable 等无实参处使用）。
func (ci *classInfo) methodOfArgs(name string, argc int) (*classInfo_m, bool) {
	if list := ci.overloads[name]; len(list) > 0 {
		for _, m := range list {
			if len(m.decl.Params) == argc {
				return m, true
			}
		}
	}
	if m, ok := ci.methods[name]; ok && len(m.decl.Params) == argc {
		return m, true
	}
	if name == "deinit" && ci.deinit != nil {
		return ci.deinit, true
	}
	if ci.base != nil {
		return ci.base.methodOfArgs(name, argc)
	}
	return nil, false
}

// methodRetC 方法返回 C 类型。
func (g *gen) methodRetC(m *classInfo_m) (string, error) {
	saved := g.subst
	if m.owner != nil && len(m.owner.subst) > 0 {
		g.subst = mergeSubst(saved, m.owner.subst)
	}
	defer func() { g.subst = saved }()
	if m.decl.Void {
		return "void", nil
	}
	return g.cType(m.decl.Ret)
}

// recvCName 接收者表达式（局部变量 / self）。
func recvCName(e xfront.Expr, s *scope) (string, string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		if n.Name == "self" && s.self != nil {
			return s.cRef("self"), s.self.ctype, nil
		}
		if n.Name == "super" && s.superT != "" {
			return s.cRef("super"), s.superT, nil
		}
		c, ok := s.localCType(n.Name)
		if !ok {
			if gc, isGlobal := s.g.globals[n.Name]; isGlobal {
				return s.cRef(n.Name), gc, nil
			}
			return "", "", fmt.Errorf("codegen：未登记标识符 %s", n.Name)
		}
		return s.cRef(n.Name), c, nil
	case *xfront.Member:
		if ci, varName, ok := s.g.singletonInstance(n); ok {
			return varName, ci.cname + " *", nil
		}
		if ei, it, ok := s.g.enumItem(n); ok {
			if ei.simple {
				return strconv.FormatInt(it.value, 10), ei.ctype, nil
			}
			return it.varName, ei.ctype, nil
		}
		// 字段链（self.kids / a.b.c）：递归解析基址，字段类型给出段类型
		base, baseC, err := recvCName(n.X, s)
		if err != nil {
			return "", "", err
		}
		if s.g.isStructC(baseC) {
			ci, ok := s.g.structOfC(baseC)
			if !ok {
				return "", "", fmt.Errorf("codegen：未知结构体类型 %s", baseC)
			}
			f, ok := ci.fieldOf(n.Name)
			if !ok {
				return "", "", fmt.Errorf("codegen：结构体 %s 没有字段 %s", ci.decl.Name, n.Name)
			}
			return base + structSep(baseC) + f.cname, f.ctype, nil
		}
		ci, ok := s.g.classOfC(baseC)
		if !ok {
			return "", "", fmt.Errorf("codegen：成员链接收者类型 %s 不可判定（M5.1-b 范围）", baseC)
		}
		f, ok := ci.fieldOf(n.Name)
		if !ok {
			return "", "", fmt.Errorf("codegen：类 %s 没有字段 %s（成员链）", ci.decl.Name, n.Name)
		}
		return base + "->" + f.cname, f.ctype, nil
	}
	return "", "", fmt.Errorf("codegen：类成员接收者 %T 未支持（M5.1-b 范围：局部变量/self/字段链）", e)
}

// emitNewClass 生成 new 表达式。
func (s *scope) emitNewClass(n *xfront.New) (string, error) {
	nt, ok := n.Type.(*xfront.NamedType)
	if !ok {
		return "", fmt.Errorf("codegen：new 的类型必须是命名类（M4.1/M4.4b 范围）")
	}
	ci, ok := s.g.classOf(lastQualName(nt))
	if !ok {
		if sc, isSingleton := s.g.singletons[lastQualName(nt)]; isSingleton {
			return "", fmt.Errorf("codegen：单例 %s 不能用 new（S2 §9.1）", sc.decl.Name)
		}
		if decl, isGen := s.g.classDecls[lastQualName(nt)]; isGen && len(decl.TypePars) > 0 {
			ct, err := s.g.cType(nt)
			if err != nil {
				return "", err
			}
			ci, ok = s.g.classOfC(ct)
		}
	}
	if ok {
		if len(n.Args) > 0 {
			c := ci.ctorByArity(len(n.Args))
			if c == nil {
				return "", fmt.Errorf("codegen：类 %s 没有 %d 个参数的构造器（S2 §6.3）", ci.decl.Name, len(n.Args))
			}
			args, err := s.callArgs(n.Args)
			if err != nil {
				return "", err
			}
			return ci.ctorName[c] + "(" + strings.Join(args, ", ") + ")", nil
		}
		return ci.cname + "_new()", nil
	}
	if sc, ok := s.g.structs[lastQualName(nt)]; ok {
		args, err := s.callArgs(n.Args)
		if err != nil {
			return "", err
		}
		return s.g.structCtorCall(sc, len(n.Args), args)
	}
	return "", fmt.Errorf("codegen：未定义的类 %s", lastQualName(nt))
}

// classMemberValue 生成类成员值（字段读 / 方法调用）。
func (s *scope) classMemberValue(recvC, recvName string, mem *xfront.Member, args []xfront.Expr) (string, bool, error) {
	ci, ok := s.g.classOfC(recvC)
	if !ok {
		return "", false, nil
	}
	if f, ok := ci.fieldOf(mem.Name); ok {
		return s.g.fieldReadExpr(f, recvName+"->"+f.cname), true, nil
	}
	if m, ok := s.methodFor(ci, mem.Name, args); ok {
		call, err := s.methodCall(ci, m, recvName, args)
		return call, true, err
	}
	return "", true, fmt.Errorf("codegen：类 %s 没有成员 %s（M4.4b 范围）", ci.decl.Name, mem.Name)
}

// methodCall 生成方法调用实参序列（self 前置）。
func (s *scope) methodCall(ci *classInfo, m *classInfo_m, recvName string, args []xfront.Expr) (string, error) {
	saved := s.g.subst
	if len(ci.subst) > 0 {
		s.g.subst = mergeSubst(saved, ci.subst)
	}
	defer func() { s.g.subst = saved }()
	// 继承方法：接收者静态类型可能是子类，调用父类实现时按父类指针转型
	//（扁平布局保证字段偏移一致）。
	if m.owner != nil && ci.cname != m.owner.cname {
		recvName = "(" + m.owner.cname + " *)" + recvName
	}
	parts := []string{recvName}
	for i, p := range m.decl.Params {
		if i >= len(args) {
			return "", fmt.Errorf("codegen：方法 %s.%s 缺少实参（sema 应拒绝）", ci.decl.Name, m.decl.Name)
		}
		pc, err := s.g.cType(p.Type)
		if err != nil {
			return "", err
		}
		if pc == "rt_string *" {
			lines, err := s.strExpr(args[i])
			if err != nil {
				return "", err
			}
			s.pending = append(s.pending, lines...)
			parts = append(parts, lastVar(lines))
			continue
		}
		if s.g.isProtoC(pc) {
			lines, expr, _, err := s.protoValue(args[i])
			if err != nil {
				return "", err
			}
			s.pending = append(s.pending, lines...)
			parts = append(parts, expr)
			continue
		}
		if s.g.isStructC(pc) {
			lines, expr, err := s.structValue(args[i], pc)
			if err != nil {
				return "", err
			}
			s.pending = append(s.pending, lines...)
			parts = append(parts, expr)
			continue
		}
		v, err := s.intExpr(args[i])
		if err != nil {
			return "", err
		}
		parts = append(parts, v)
	}
	if len(args) > len(m.decl.Params) {
		return "", fmt.Errorf("codegen：方法 %s.%s 实参过多（sema 应拒绝）", ci.decl.Name, m.decl.Name)
	}
	return m.cname + "(" + strings.Join(parts, ", ") + ")", nil
}

// emitFieldAssign 生成字段赋值（S2-E5-01）。
// 引用字段：先求值（可能与旧值别名）→ 新值持 +1 → 释放旧值 → 写入。
func (s *scope) emitFieldAssign(mem *xfront.Member, val xfront.Expr) ([]string, error) {
	recvName, recvC, err := recvCName(mem.X, s)
	if err != nil {
		return nil, err
	}
	if s.g.isStructC(recvC) {
		ci, ok := s.g.structOfC(recvC)
		if !ok {
			return nil, fmt.Errorf("codegen：未知结构体类型 %s", recvC)
		}
		f, ok := ci.fieldOf(mem.Name)
		if !ok {
			return nil, fmt.Errorf("codegen：结构体 %s 没有字段 %s", ci.decl.Name, mem.Name)
		}
		dst := recvName + structSep(recvC) + f.cname
		if strings.HasPrefix(f.ctype, "xn_opt_") {
			lines, v, err := s.optExpr(val, f.ctype)
			if err != nil {
				return nil, err
			}
			return append(lines, dst+" = "+v+";"), nil
		}
		if s.g.isStructC(f.ctype) {
			lines, v, err := s.structValue(val, f.ctype)
			if err != nil {
				return nil, err
			}
			return append(lines, dst+" = "+v+";"), nil
		}
		if f.ctype == "rt_string *" {
			lines, err := s.strExpr(val)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, lines...)
			out = append(out, "rt_release("+dst+");", dst+" = "+lastVar(lines)+";")
			return out, nil
		}
		v, err := s.intExpr(val)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return append(out, dst+" = "+v+";"), nil
	}
	ci, ok := s.g.classOfC(recvC)
	if !ok {
		return nil, fmt.Errorf("codegen：成员赋值的接收者不是类实例（M4.4b 范围）")
	}
	f, ok := ci.fieldOf(mem.Name)
	if !ok {
		return nil, fmt.Errorf("codegen：类 %s 没有字段 %s（或方法不可赋值）", ci.decl.Name, mem.Name)
	}
	dst := recvName + "->" + f.cname
	if strings.HasPrefix(f.ctype, "xn_opt_") {
		lines, v, err := s.optExpr(val, f.ctype)
		if err != nil {
			return nil, err
		}
		return append(lines, dst+" = "+v+";"), nil
	}
	// S3-04：Text/StringBuilder 字段是 GC 引用，赋值不计数。
	if f.ctype == "xrt_text *" || f.ctype == "xrt_sb *" {
		var lines []string
		var v string
		var err error
		if f.ctype == "xrt_text *" {
			lines, v, err = s.textExpr(val)
		} else {
			lines, v, err = s.sbExpr(val)
		}
		if err != nil {
			return nil, err
		}
		return append(lines, dst+" = "+v+";"), nil
	}
	// Any/Object 字段：GC 盒引用，赋值不 retain/release（旧盒由 GC 回收）。
	if f.isAny {
		lines, v, err := s.anyExpr(val)
		if err != nil {
			return nil, err
		}
		return append(lines, dst+" = "+v+";"), nil
	}
	// 容器字段是 GC 对象（S3 §10）：引用赋值，不做 ARC 计数。
	if f.isArr {
		lines, v, err := s.valExpr(val, f.ctype)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, lines...)
		out = append(out, dst+" = "+v+";")
		return out, nil
	}
	if f.isProto {
		if _, isNull := val.(*xfront.NullLit); isNull {
			return []string{"rt_release((void *)" + dst + ");", dst + " = NULL;"}, nil
		}
		lines, expr, owned, err := s.protoValue(val)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, lines...)
		if !owned {
			t := s.tmp()
			out = append(out, "void *"+t+" = rt_retain((void *)"+expr+");")
			expr = t
		}
		out = append(out, "rt_release((void *)"+dst+");", dst+" = "+expr+";")
		return out, nil
	}
	if !f.isRefField() {
		v, err := s.intExpr(val)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return append(out, dst+" = "+s.g.fieldStoreExpr(f, v)+";"), nil
	}
	switch {
	case f.isStr:
		if _, isNull := val.(*xfront.NullLit); isNull {
			return []string{"rt_release(" + dst + ");", dst + " = NULL;"}, nil
		}
		lines, err := s.strExpr(val) // 始终 +1
		if err != nil {
			return nil, err
		}
		t := lastVar(lines)
		out := append([]string{}, lines...)
		out = append(out, "rt_release("+dst+");", dst+" = "+t+";")
		return out, nil
	case f.isHandle, f.isBytes:
		if _, isNull := val.(*xfront.NullLit); isNull {
			return []string{"rt_release(" + dst + ");", dst + " = NULL;"}, nil
		}
		var lines []string
		var expr string
		switch val.(type) {
		case *xfront.Call, *xfront.IdentExpr, *xfront.Paren:
			if f.isHandle {
				lines, expr, err = s.handleExpr(val) // +1
			} else {
				lines, expr, err = s.bytesExpr(val) // +1
			}
		default:
			// 成员/下标读是借用：取 +1。
			expr, err = s.intExpr(val)
			if err == nil {
				t := s.tmp()
				lines = []string{f.ctype + " " + t + " = rt_retain(" + expr + ");"}
				expr = t
			}
		}
		if err != nil {
			return nil, err
		}
		out := append([]string{}, lines...)
		out = append(out, "rt_release("+dst+");", dst+" = "+expr+";")
		return out, nil
	case f.isCls:
		if f.isGC {
			lines, v, _, err := s.classValueExpr(val)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, lines...)
			return append(out, dst+" = "+v+";"), nil
		}
		switch v := val.(type) {
		case *xfront.NullLit:
			return []string{"rt_release(" + dst + ");", dst + " = NULL;"}, nil
		case *xfront.New:
			ctor, err := s.emitNewClass(v)
			if err != nil {
				return nil, err
			}
			t := s.tmp()
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, f.ctype+" "+t+" = "+ctor+";")
			out = append(out, "rt_release("+dst+");", dst+" = "+t+";")
			return out, nil
		case *xfront.Call:
			expr, owns, err := s.classCallExpr(v)
			if err != nil {
				return nil, err
			}
			t := s.tmp()
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, f.ctype+" "+t+" = "+expr+";")
			if !owns {
				out = append(out, "rt_retain("+t+");")
			}
			out = append(out, "rt_release("+dst+");", dst+" = "+t+";")
			return out, nil
		case *xfront.IdentExpr:
			r := s.cRef(v.Name)
			return []string{
				"rt_retain(" + r + ");",
				"rt_release(" + dst + ");",
				dst + " = " + r + ";",
			}, nil
		default:
			// 成员/下标/括号读是借用：先落临时并 retain（支持 h.a = h.a）。
			expr, err := s.intExpr(val)
			if err != nil {
				return nil, err
			}
			t := s.tmp()
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, f.ctype+" "+t+" = "+expr+";")
			out = append(out, "rt_retain("+t+");")
			out = append(out, "rt_release("+dst+");", dst+" = "+t+";")
			return out, nil
		}
	}
	return nil, fmt.Errorf("codegen：字段 %s 的赋值形态未支持（S2-E5-01 范围）", f.name)
}

func lastQualName(nt *xfront.NamedType) string {
	if len(nt.Qual) == 0 {
		return ""
	}
	return nt.Qual[len(nt.Qual)-1]
}

// staticClassCall 解析 `ClassName.staticMethod(...)`（S2 §7.2/§10.3）。
func (s *scope) staticClassCall(mem *xfront.Member, call *xfront.Call) (string, string, bool, error) {
	id, ok := mem.X.(*xfront.IdentExpr)
	if !ok {
		return "", "", false, nil
	}
	if s.params != nil && s.params[id.Name] {
		return "", "", false, nil
	}
	if _, local := s.locals[id.Name]; local {
		return "", "", false, nil
	}
	var ci *classInfo
	if c, ok := s.g.classOf(id.Name); ok {
		ci = c
	} else if c, ok := s.g.structs[id.Name]; ok {
		ci = c
	} else if c, ok := s.g.singletons[id.Name]; ok {
		ci = c
	} else if ei, ok := s.g.enums[id.Name]; ok && ei.cls != nil {
		ci = ei.cls
	}
	if ci == nil {
		return "", "", false, nil
	}
	m, ok := s.methodFor(ci, mem.Name, call.Args)
	if !ok || !m.static {
		return "", "", false, nil
	}
	args, err := s.callArgs(call.Args)
	if err != nil {
		return "", "", true, err
	}
	retC, err := s.g.methodRetC(m)
	if err != nil {
		return "", "", true, err
	}
	return m.cname + "(" + strings.Join(args, ", ") + ")", retC, true, nil
}

// slotCType 把标量字段存储加宽到 8 字节槽（S3 §2：标量值字段占一个 8 字节槽）。
func (g *gen) slotCType(c string) string {
	switch c {
	case "int32_t", "int":
		return "int64_t"
	}
	return c
}

// fieldStoreExpr 写入字段时按声明语义宽度截断后再存入 8 字节槽。
func (g *gen) fieldStoreExpr(f classField, expr string) string {
	if f.semC == "" || f.semC == f.ctype {
		return expr
	}
	return "(" + f.ctype + ")((" + f.semC + ")(" + expr + "))"
}

// fieldReadExpr 读取字段时按声明语义宽度转换（槽存储可能加宽）。
func (g *gen) fieldReadExpr(f classField, expr string) string {
	if f.semC == "" || f.semC == f.ctype {
		return expr
	}
	return "((" + f.semC + ")(" + expr + "))"
}
