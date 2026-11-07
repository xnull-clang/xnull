// tuple.go：元组代码生成（S1 §2.11）。
//
// 表示：每个结构化元组类型生成一个按值 C 结构体（字段 f0/f1/...）。
// 赋值、传参、返回与容器写入都是 C 结构体赋值——天然满足 §2.11 的整值复制。
// 元素顺序有意义；类型身份由元素 C 类型序列决定，嵌套元组按内层结构体字段排列。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// tupleInfo 是一个元组 C 结构体的生成信息。
type tupleInfo struct {
	cname string
	elems []string // 元素 C 类型（顺序即字段 f0/f1/...）
}

// tupleCName 由元素 C 类型生成确定的元组结构体名。
func tupleCName(elems []string) string {
	var b strings.Builder
	b.WriteString("xn_tup")
	for _, e := range elems {
		b.WriteByte('_')
		for _, r := range e {
			switch {
			case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
				b.WriteRune(r)
			default:
				b.WriteByte('_')
			}
		}
	}
	return b.String()
}

// tupleOf 登记（幂等）并返回元组 C 类型名。内层元组由 cType 递归先登记。
func (g *gen) tupleOf(elems []string) string {
	cname := tupleCName(elems)
	if _, ok := g.tuples[cname]; !ok {
		g.tuples[cname] = &tupleInfo{cname: cname, elems: elems}
		g.tupleOrder = append(g.tupleOrder, cname)
	}
	return cname
}

// isTupleC 判断 C 类型是否为已登记的元组结构体。
func (g *gen) isTupleC(c string) bool {
	_, ok := g.tuples[c]
	return ok
}

// tupleElems 返回元组 C 类型的元素类型序列。
func (g *gen) tupleElems(c string) ([]string, bool) {
	ti, ok := g.tuples[c]
	if !ok {
		return nil, false
	}
	return ti.elems, true
}

// emitTupleTypes 输出全部元组结构体定义（按登记顺序，内层先于外层）。
func (g *gen) emitTupleTypes(b *strings.Builder) {
	if len(g.tupleOrder) == 0 {
		return
	}
	for _, cn := range g.tupleOrder {
		ti := g.tuples[cn]
		b.WriteString("typedef struct {\n")
		for i, e := range ti.elems {
			fmt.Fprintf(b, "    %s f%d;\n", e, i)
		}
		fmt.Fprintf(b, "} %s;\n", cn)
	}
	b.WriteString("\n")
}

// tupleTypeFromElems 把类型引用序列解析为元组 C 类型（供 cType/exprType 复用）。
func (g *gen) tupleTypeFromElems(elems []xfront.TypeRef) (string, error) {
	if len(elems) < 2 {
		return "", fmt.Errorf("codegen：元组至少需要两个元素（S1 §2.11）")
	}
	cs := make([]string, 0, len(elems))
	for _, e := range elems {
		c, err := g.cType(e)
		if err != nil {
			return "", err
		}
		cs = append(cs, c)
	}
	return g.tupleOf(cs), nil
}

// tupleExpr 生成元组值表达式（右值）；tc 为目标元组 C 类型。
func (s *scope) tupleExpr(e xfront.Expr, tc string) ([]string, string, error) {
	elems, ok := s.g.tupleElems(tc)
	if !ok {
		return nil, "", fmt.Errorf("codegen：%s 不是元组类型", tc)
	}
	switch n := e.(type) {
	case *xfront.Tuple:
		if len(n.Elems) != len(elems) {
			return nil, "", fmt.Errorf("codegen：元组元素个数不符（got %d, want %d）", len(n.Elems), len(elems))
		}
		var lines []string
		var parts []string
		for i, el := range n.Elems {
			ls, v, err := s.tupleElemExpr(el, elems[i])
			if err != nil {
				return nil, "", err
			}
			lines = append(lines, ls...)
			parts = append(parts, fmt.Sprintf(".f%d = %s", i, v))
		}
		return lines, "(" + tc + "){" + strings.Join(parts, ", ") + "}", nil
	case *xfront.Paren:
		return s.tupleExpr(n.X, tc)
	case *xfront.IdentExpr:
		return nil, s.cRef(n.Name), nil
	case *xfront.TupleMember:
		baseT, err := s.exprType(n.X)
		if err != nil {
			return nil, "", err
		}
		ls, base, err := s.tupleExpr(n.X, baseT)
		if err != nil {
			return nil, "", err
		}
		return ls, "(" + base + ").f" + fmt.Sprintf("%d", n.Index), nil
	case *xfront.Member:
		// 类字段（元组值字段）。
		recvName, recvC, err := recvCName(n.X, s)
		if err != nil {
			return nil, "", err
		}
		ci, ok := s.g.classOfC(recvC)
		if !ok {
			return nil, "", fmt.Errorf("codegen：元组成员接收者 %s 不支持（M4.4b 范围）", recvC)
		}
		f, ok := ci.fieldOf(n.Name)
		if !ok {
			return nil, "", fmt.Errorf("codegen：类 %s 没有字段 %s", ci.decl.Name, n.Name)
		}
		return nil, recvName + "->" + f.cname, nil
	case *xfront.Index:
		v, err := s.indexRead(n)
		if err != nil {
			return nil, "", err
		}
		return nil, v, nil
	case *xfront.Call:
		return s.tupleCallExpr(n, tc)
	}
	return nil, "", fmt.Errorf("codegen：元组表达式 %T 未支持（M4.1 范围）", e)
}

// tupleElemExpr 按元素 C 类型生成元素右值。
func (s *scope) tupleElemExpr(e xfront.Expr, ec string) ([]string, string, error) {
	if s.g.isTupleC(ec) {
		return s.tupleExpr(e, ec)
	}
	switch ec {
	case "rt_string *":
		lines, err := s.strExpr(e)
		if err != nil {
			return nil, "", err
		}
		return lines, lastVar(lines), nil
	case "int":
		v, err := s.boolExpr(e)
		if err != nil {
			return nil, "", err
		}
		return nil, v, nil
	default:
		v, err := s.intExpr(e)
		if err != nil {
			return nil, "", err
		}
		lines := append([]string{}, s.pending...)
		s.pending = nil
		return lines, v, nil
	}
}

// tupleCallExpr 生成返回元组的调用表达式（顶层函数/容器 get/类方法）。
func (s *scope) tupleCallExpr(cl *xfront.Call, tc string) ([]string, string, error) {
	if mem, ok := cl.Callee.(*xfront.Member); ok {
		rn, rc, err := recvCName(mem.X, s)
		if err != nil {
			return nil, "", err
		}
		if isContainerC(rc) {
			v, hit, err := s.containerMemberValue(rc, rn, mem.Name, cl.Args)
			if err != nil {
				return nil, "", err
			}
			if hit {
				lines := append([]string{}, s.pending...)
				s.pending = nil
				return lines, v, nil
			}
		}
		if isClassPtr(rc) {
			v, hit, err := s.classMemberValue(rc, rn, mem, cl.Args)
			if err != nil {
				return nil, "", err
			}
			if hit {
				lines := append([]string{}, s.pending...)
				s.pending = nil
				return lines, v, nil
			}
		}
		return nil, "", fmt.Errorf("codegen：元组成员调用 %s 未支持", mem.Name)
	}
	id, ok := cl.Callee.(*xfront.IdentExpr)
	if !ok {
		return nil, "", fmt.Errorf("codegen：元组调用目标 %T 未支持", cl.Callee)
	}
	if expr, hit, err := s.selfMethodCall(id.Name, cl.Args); err != nil {
		return nil, "", err
	} else if hit {
		lines := append([]string{}, s.pending...)
		s.pending = nil
		return lines, expr, nil
	}
	args, err := s.callArgs(cl.Args)
	if err != nil {
		return nil, "", err
	}
	cn, err := s.g.callName(id.Name, cl.TypeArgs, len(cl.Args))
	if err != nil {
		return nil, "", err
	}
	lines := append([]string{}, s.pending...)
	s.pending = nil
	_ = tc
	return lines, cn + "(" + strings.Join(args, ", ") + ")", nil
}

// tupleLValue 生成可赋值元组的 C 左值（标识符/元组成员/类字段）。
func (s *scope) tupleLValue(e xfront.Expr) (string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		return s.cRef(n.Name), nil
	case *xfront.Paren:
		return s.tupleLValue(n.X)
	case *xfront.TupleMember:
		base, err := s.tupleLValue(n.X)
		if err != nil {
			return "", err
		}
		return base + ".f" + fmt.Sprintf("%d", n.Index), nil
	case *xfront.Member:
		recvName, recvC, err := recvCName(n.X, s)
		if err != nil {
			return "", err
		}
		ci, ok := s.g.classOfC(recvC)
		if !ok {
			return "", fmt.Errorf("codegen：元组成员接收者 %s 不支持（M4.4b 范围）", recvC)
		}
		f, ok := ci.fieldOf(n.Name)
		if !ok {
			return "", fmt.Errorf("codegen：类 %s 没有字段 %s", ci.decl.Name, n.Name)
		}
		return recvName + "->" + f.cname, nil
	}
	return "", fmt.Errorf("codegen：元组赋值目标 %T 未支持", e)
}

// tupleStr 生成元组插值/打印文本（"(a, b)"，元素递归格式化，S1 §2.11）。
func (s *scope) tupleStr(e xfront.Expr, tc string) ([]string, string, error) {
	lines, base, err := s.tupleExpr(e, tc)
	if err != nil {
		return nil, "", err
	}
	t := s.tmp()
	out := append(lines, tc+" "+t+" = "+base+";")
	more, v, err := s.tupleStrFields(t, tc)
	if err != nil {
		return nil, "", err
	}
	return append(out, more...), v, nil
}

// tupleStrFields 对已在 C 变量 base 中的元组生成格式化串。
func (s *scope) tupleStrFields(base string, tc string) ([]string, string, error) {
	elems, ok := s.g.tupleElems(tc)
	if !ok {
		return nil, "", fmt.Errorf("codegen：%s 不是元组类型", tc)
	}
	var lines []string
	acc := s.tmp()
	lines = append(lines, "rt_string *"+acc+" = rt_string_from_c(\"(\");")
	for i, ec := range elems {
		if i > 0 {
			n := s.tmp()
			lines = append(lines, "rt_string *"+n+" = xn_concat("+acc+", rt_string_from_c(\", \"));")
			acc = n
		}
		field := fmt.Sprintf("(%s).f%d", base, i)
		var v string
		var more []string
		var err error
		switch {
		case s.g.isTupleC(ec):
			more, v, err = s.tupleStrFields(field, ec)
		case ec == "rt_string *":
			v = s.tmp()
			more = []string{"rt_string *" + v + " = rt_retain(" + field + ");"}
		case ec == "int":
			v = s.tmp()
			more = []string{"rt_string *" + v + " = xn_str_bool(" + field + ");"}
		default:
			v = s.tmp()
			more = []string{"rt_string *" + v + " = xn_str_int(" + field + ");"}
		}
		if err != nil {
			return nil, "", err
		}
		lines = append(lines, more...)
		n := s.tmp()
		lines = append(lines, "rt_string *"+n+" = xn_concat("+acc+", "+v+");")
		acc = n
	}
	last := s.tmp()
	lines = append(lines, "rt_string *"+last+" = xn_concat("+acc+", rt_string_from_c(\")\"));")
	return lines, last, nil
}

// tupleEq 生成元组相等/同一性比较（返回 C 布尔表达式）。
func (s *scope) tupleEq(l, r xfront.Expr, tc string, identity bool) (string, error) {
	ls, lv, err := s.tupleExpr(l, tc)
	if err != nil {
		return "", err
	}
	rs, rv, err := s.tupleExpr(r, tc)
	if err != nil {
		return "", err
	}
	lt, rt := s.tmp(), s.tmp()
	s.pending = append(s.pending, ls...)
	s.pending = append(s.pending, rs...)
	s.pending = append(s.pending, tc+" "+lt+" = "+lv+";", tc+" "+rt+" = "+rv+";")
	return s.tupleCmp(lt, rt, tc, identity)
}

// tupleCmp 递归构造元组逐元素比较表达式。
func (s *scope) tupleCmp(l, r, tc string, identity bool) (string, error) {
	elems, ok := s.g.tupleElems(tc)
	if !ok {
		return "", fmt.Errorf("codegen：%s 不是元组类型", tc)
	}
	parts := make([]string, 0, len(elems))
	for i, ec := range elems {
		lf := fmt.Sprintf("(%s).f%d", l, i)
		rf := fmt.Sprintf("(%s).f%d", r, i)
		if s.g.isTupleC(ec) {
			sub, err := s.tupleCmp(lf, rf, ec, identity)
			if err != nil {
				return "", err
			}
			parts = append(parts, "("+sub+")")
			continue
		}
		if ec == "rt_string *" && !identity {
			parts = append(parts, "xn_str_eq("+lf+", "+rf+")")
			continue
		}
		parts = append(parts, "("+lf+" == "+rf+")")
	}
	return "(" + strings.Join(parts, " && ") + ")", nil
}
