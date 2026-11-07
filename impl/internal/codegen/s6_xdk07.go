// s6_xdk07.go：XDK-07 特化容器（collections.x）的 codegen 支持。
//
// 覆盖：函数类型字段/参数与间接调用；T? 可空方法返回；new T[n] 定长数组
// 与数组返回；类方法返回容器（keysArray/valuesArray）。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

func sanitizeCName(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
	}
	return b.String()
}

// funcTypeC 生成函数指针 typedef（按签名去重），返回 typedef 名。
func (g *gen) funcTypeC(ft *xfront.FuncTypeRef) (string, error) {
	ret, err := g.cType(ft.Ret)
	if err != nil {
		return "", err
	}
	parts := make([]string, 0, len(ft.Params))
	for _, p := range ft.Params {
		pc, err := g.cType(p)
		if err != nil {
			return "", err
		}
		parts = append(parts, pc)
	}
	name := "xn_fn_" + sanitizeCName(ret+"_"+strings.Join(parts, "_"))
	if !g.fnTypes[name] {
		g.fnTypes[name] = true
		g.fnTypeSig[name] = ret + "|" + strings.Join(parts, ", ")
	}
	return name, nil
}

// lambdaFuncType 推断闭包（函数类型字段实参）的 C 函数指针类型。
func (s *scope) lambdaFuncType(lam *xfront.Lambda) (string, error) {
	params := make([]xfront.TypeRef, 0, len(lam.Params))
	for _, p := range lam.Params {
		params = append(params, p.Type)
	}
	var ret xfront.TypeRef
	if lam.ExprB != nil {
		t, err := s.exprType(lam.ExprB)
		if err != nil {
			return "", err
		}
		ret = cTypeToTypeRef(t)
	} else {
		// 从 return 语句推断返回 C 类型。
		var found string
		var walk func(stmts []xfront.Stmt) error
		walk = func(stmts []xfront.Stmt) error {
			for _, st := range stmts {
				r, ok := st.(*xfront.ReturnStmt)
				if !ok || r.Value == nil {
					continue
				}
				t, err := s.exprType(r.Value)
				if err != nil {
					return err
				}
				found = t
			}
			return nil
		}
		if err := walk(lam.Block.Stmts); err != nil {
			return "", err
		}
		if found == "" {
			return "", fmt.Errorf("codegen：闭包缺少返回表达式（XDK-07）")
		}
		ret = cTypeToTypeRef(found)
	}
	return s.g.funcTypeC(&xfront.FuncTypeRef{Params: params, Ret: ret})
}

// cTypeToTypeRef 把已解析的 C 类型回填为最小 TypeRef（供函数指针 typedef）。
func cTypeToTypeRef(c string) xfront.TypeRef {
	switch c {
	case "int64_t":
		return &xfront.NamedType{Qual: []string{"Int"}}
	case "int32_t":
		return &xfront.NamedType{Qual: []string{"Int32"}}
	case "int":
		return &xfront.NamedType{Qual: []string{"Bool"}}
	case "double":
		return &xfront.NamedType{Qual: []string{"Double"}}
	case "rt_string *":
		return &xfront.NamedType{Qual: []string{"String"}}
	}
	// 类/其它指针：以占位 NamedType 表示，cType 回填时按名字解析失败则退回。
	return &xfront.NamedType{Qual: []string{strings.TrimSuffix(strings.TrimPrefix(c, "xn_Cls_"), " *")}}
}

// emitLambdaFn 生成无捕获闭包的 C 函数（供函数指针字段/参数）。
func (s *scope) emitLambdaFn(lam *xfront.Lambda) (string, error) {
	used := map[string]bool{}
	if lam.Block != nil {
		walkBlockAll(lam.Block, used)
	} else {
		walkExprAll(lam.ExprB, used)
	}
	declared := map[string]bool{}
	collectLambdaDecls(lam.Block, declared)
	for _, p := range lam.Params {
		declared[p.Name] = true
	}
	for name := range used {
		if declared[name] {
			continue
		}
		if _, ok := s.localCType(name); ok {
			return "", fmt.Errorf("codegen：函数实参闭包捕获外部变量 %s 暂不支持（XDK-07）", name)
		}
	}
	ft, err := s.lambdaFuncType(lam)
	if err != nil {
		return "", err
	}
	name := fmt.Sprintf("xn_fn_lit_%d", s.g.nextTaskID())
	sc := &scope{g: s.g, retC: "", params: map[string]bool{}, locals: map[string]string{}}
	parts := make([]string, 0, len(lam.Params))
	for _, p := range lam.Params {
		pc, err := s.g.cType(p.Type)
		if err != nil {
			return "", err
		}
		parts = append(parts, pc+" "+p.Name)
		sc.locals[p.Name] = pc
	}
	var body string
	if lam.ExprB != nil {
		v, err := s.intExpr(lam.ExprB)
		if err != nil {
			return "", err
		}
		body = "    return " + v + ";\n"
	} else {
		// 返回类型：取函数指针签名推断结果。
		sig := s.g.fnTypeSig[ft]
		ret := strings.TrimSpace(strings.SplitN(sig, "|", 2)[0])
		sc.retC = ret
		b, err := sc.emitBlock(lam.Block.Stmts)
		if err != nil {
			return "", err
		}
		body = b
	}
	retC := strings.TrimSpace(strings.SplitN(s.g.fnTypeSig[ft], "|", 2)[0])
	var b strings.Builder
	fmt.Fprintf(&b, "static %s %s(%s) {\n", retC, name, strings.Join(parts, ", "))
	if lam.ExprB != nil {
		b.WriteString("    (void)0;\n")
	}
	b.WriteString(body)
	b.WriteString("\n}\n\n")
	s.g.lateProtos = append(s.g.lateProtos, "static "+retC+" "+name+"("+strings.Join(parts, ", ")+");")
	s.g.lateFns = append(s.g.lateFns, b.String())
	return name, nil
}

// arrayNewExpr 生成 new T[n] 的定长数组（GC 容器，零初始化到长度 n）。
func (s *scope) arrayNewExpr(n *xfront.NewArray, arrC string) ([]string, string, error) {
	elem, ok := containerElem(arrC)
	if !ok {
		return nil, "", fmt.Errorf("codegen：数组元素类型推不出（%s）", arrC)
	}
	cnt, err := s.intExpr(n.Count)
	if err != nil {
		return nil, "", err
	}
	lines := append([]string{}, s.pending...)
	s.pending = nil
	t := s.tmp()
	base := strings.TrimSuffix(arrC, " *")
	lines = append(lines, fmt.Sprintf("%s *%s = %s_new((size_t)(%s));", base, t, base, cnt))
	lines = append(lines, fmt.Sprintf("%s->len = (size_t)(%s);", t, cnt))
	lines = append(lines, fmt.Sprintf("memset(%s->data, 0, sizeof(%s) * (size_t)(%s));", t, elem, cnt))
	return lines, t, nil
}
