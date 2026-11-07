// classes_expr.go：类实例在表达式/语句层的生成（M4.4b）。
package codegen

import (
	"fmt"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

func isClassPtr(c string) bool { return strings.HasPrefix(c, "xn_Cls_") }

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
	m, ok := s.self.ci.methodOf(name)
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
		return recvName + "->" + f.cname, true, nil
	}
	if m, ok := ci.methodOf(mem.Name); ok {
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
	// 容器字段是值结构（本层未做引用语义容器）：浅拷贝会双释放，显式拒绝。
	if f.isArr {
		return nil, fmt.Errorf("codegen：容器字段 %s 的赋值需要引用语义容器（B2 范围，显式拒绝）", f.name)
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
		return append(out, dst+" = "+v+";"), nil
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
