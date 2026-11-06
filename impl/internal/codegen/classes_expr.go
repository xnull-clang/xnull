// classes_expr.go：类实例在表达式/语句层的生成（M4.4b）。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

func isClassPtr(c string) bool { return strings.HasPrefix(c, "xn_Cls_") }

// classOfC 由 C 类型名反查类信息。
func (g *gen) classOfC(c string) (*classInfo, bool) {
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

// classMethodOf 查方法生成信息。
func (ci *classInfo) methodOf(name string) (*classInfo_m, bool) {
	m, ok := ci.methods[name]
	return m, ok
}

// methodRetC 方法返回 C 类型。
func (g *gen) methodRetC(m *classInfo_m) (string, error) {
	if m.decl.Void {
		return "void", nil
	}
	return g.cType(m.decl.Ret)
}

// recvCName 接收者表达式（局部变量 / self）。
func recvCName(e xfront.Expr, s *scope) (string, string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		c, ok := s.localCType(n.Name)
		if !ok {
			return "", "", fmt.Errorf("codegen：未登记标识符 %s", n.Name)
		}
		name := n.Name
		if s.params != nil && s.params[name] {
			name = "xn_p_" + name
		}
		return name, c, nil
	case *xfront.Member:
		// 字段链（self.kids / a.b.c）：递归解析基址，字段类型给出段类型
		base, baseC, err := recvCName(n.X, s)
		if err != nil {
			return "", "", err
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
		return "", fmt.Errorf("codegen：未定义的类 %s", lastQualName(nt))
	}
	if len(n.Args) > 0 {
		return "", fmt.Errorf("codegen：类 %s 带参构造暂未支持（M4.4b 范围：无参构造）", ci.decl.Name)
	}
	return ci.cname + "_new()", nil
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

// emitFieldAssign 生成字段赋值（String 字段先释放旧值再取得新引用）。
func (s *scope) emitFieldAssign(mem *xfront.Member, val xfront.Expr) ([]string, error) {
	recvName, recvC, err := recvCName(mem.X, s)
	if err != nil {
		return nil, err
	}
	ci, ok := s.g.classOfC(recvC)
	if !ok {
		return nil, fmt.Errorf("codegen：成员赋值的接收者不是类实例（M4.4b 范围）")
	}
	f, ok := ci.fieldOf(mem.Name)
	if !ok {
		return nil, fmt.Errorf("codegen：类 %s 没有字段 %s（或方法不可赋值）", ci.decl.Name, mem.Name)
	}
	if f.isStr {
		lines, err := s.strExpr(val)
		if err != nil {
			return nil, err
		}
		t := lastVar(lines)
		out := append([]string{}, lines...)
		out = append(out, fmt.Sprintf("rt_release(%s->%s);", recvName, f.cname))
		out = append(out, fmt.Sprintf("%s->%s = %s;", recvName, f.cname, t))
		return out, nil
	}
	v, err := s.intExpr(val)
	if err != nil {
		return nil, err
	}
	return []string{fmt.Sprintf("%s->%s = %s;", recvName, f.cname, v)}, nil
}

func lastQualName(nt *xfront.NamedType) string {
	if len(nt.Qual) == 0 {
		return ""
	}
	return nt.Qual[len(nt.Qual)-1]
}
