// containers_expr.go：容器在表达式/语句层的生成（M4.4a）。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

func isContainerC(c string) bool {
	return strings.HasPrefix(c, "xn_arr_") || strings.HasPrefix(c, "xn_set_") || strings.HasPrefix(c, "xn_map_")
}

// containerElem 返回容器的元素 C 类型（Set/Array/List 一致；Map 取值类型）。
func containerElem(c string) (string, bool) {
	elem := ""
	switch {
	case strings.HasPrefix(c, "xn_arr_"), strings.HasPrefix(c, "xn_set_"):
		elem = strings.TrimPrefix(strings.TrimPrefix(c, "xn_arr_"), "xn_set_")
	case strings.HasPrefix(c, "xn_map_"):
		rest := strings.TrimPrefix(c, "xn_map_")
		idx := strings.LastIndex(rest, "_")
		if idx < 0 {
			return "", false
		}
		elem = rest[idx+1:]
	default:
		return "", false
	}
	switch elem {
	case "i":
		return "int64_t", true
	case "b":
		return "int", true
	case "s":
		return "rt_string *", true
	default:
		if strings.HasPrefix(elem, "o_") {
			return "xn_Cls_" + elem[2:] + " *", true
		}
	}
	return "", false
}

// valExpr 生成容器值表达式：返回生产语句（末尾临时持有该容器值）与变量名。
func (s *scope) valExpr(e xfront.Expr, wantC string) ([]string, string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		name := n.Name
		if s.params != nil && s.params[name] {
			name = "xn_p_" + name
		}
		return nil, name, nil
	case *xfront.Paren:
		return s.valExpr(n.X, wantC)
	case *xfront.ArrayLit:
		return s.arrayLit(n, wantC)
	case *xfront.MapLit:
		return s.mapLit(n, wantC)
	}
	return nil, "", fmt.Errorf("codegen：容器表达式 %T 未支持（M4.4a 范围）", e)
}

func (s *scope) arrayLit(n *xfront.ArrayLit, wantC string) ([]string, string, error) {
	t := s.tmp()
	var out []string
	switch {
	case strings.HasPrefix(wantC, "xn_arr_"), strings.HasPrefix(wantC, "xn_set_"):
		base := wantC
		if strings.HasPrefix(wantC, "xn_set_") {
			base = "xn_arr_" + wantC[len("xn_set_"):]
		}
		elem, ok := containerElem(base)
		if !ok {
			return nil, "", fmt.Errorf("codegen：容器元素类型推不出（%s）", wantC)
		}
		out = append(out, fmt.Sprintf("%s %s = %s_new(%d);", base, t, base, len(n.Elems)))
		for _, el := range n.Elems {
			v, lines, err := s.elemValue(el, elem)
			if err != nil {
				return nil, "", err
			}
			out = append(out, lines...)
			out = append(out, fmt.Sprintf("%s_push(&%s, %s);", base, t, v))
		}
		if strings.HasPrefix(wantC, "xn_set_") {
			// 集合字面量：去重包装
			st := s.tmp()
			out = append(out, fmt.Sprintf("%s %s = %s_new();", wantC, st, wantC))
			out = append(out, fmt.Sprintf("for (size_t i = 0; i < %s.len; i++) { %s_add(&%s, %s.data[i]); }", t, wantC, st, t))
			out = append(out, fmt.Sprintf("%s_free(&%s);", base, t))
			return out, st, nil
		}
		return out, t, nil
	}
	return nil, "", fmt.Errorf("codegen：数组字面量目标类型 %s 不支持（M4.4a 范围）", wantC)
}

func (s *scope) mapLit(n *xfront.MapLit, wantC string) ([]string, string, error) {
	if !strings.HasPrefix(wantC, "xn_map_") {
		return nil, "", fmt.Errorf("codegen：Map 字面量目标类型 %s 不支持（M4.4a 范围）", wantC)
	}
	t := s.tmp()
	var out []string
	out = append(out, fmt.Sprintf("%s %s = %s_new(%d);", wantC, t, wantC, len(n.Keys)))
	for i := range n.Keys {
		k, klines, err := s.mapKeyValue(n.Keys[i], wantC)
		if err != nil {
			return nil, "", err
		}
		out = append(out, klines...)
		v, vlines, err := s.mapValValue(n.Vals[i], wantC)
		if err != nil {
			return nil, "", err
		}
		out = append(out, vlines...)
		out = append(out, fmt.Sprintf("%s_put(&%s, %s, %s);", wantC, t, k, v))
	}
	return out, t, nil
}

// elemValue 生成容器元素值（Int/Bool/String）。
func (s *scope) elemValue(e xfront.Expr, elemC string) (string, []string, error) {
	if elemC == "rt_string *" {
		lines, err := s.strExpr(e)
		return lastVar(lines), lines, err
	}
	v, err := s.intExpr(e)
	return v, nil, err
}

// mapKeyValue / mapValValue：从 Map 实例名推键/值 C 类型后取值。
func (s *scope) mapKeyValue(e xfront.Expr, mapC string) (string, []string, error) {
	k, _ := mapTypes(mapC)
	return s.elemValue(e, k)
}

func (s *scope) mapValValue(e xfront.Expr, mapC string) (string, []string, error) {
	_, v := mapTypes(mapC)
	return s.elemValue(e, v)
}

func mapTypes(mapC string) (string, string) {
	rest := strings.TrimPrefix(mapC, "xn_map_")
	// 形如 i_i / s_i —— 键与值各一位
	if len(rest) >= 3 {
		k := unMangle(rest[0])
		v := unMangle(rest[len(rest)-1])
		return k, v
	}
	return "", ""
}

func unMangle(c byte) string {
	switch c {
	case 'i':
		return "int64_t"
	case 'b':
		return "int"
	case 's':
		return "rt_string *"
	}
	return ""
}

// containerMemberStmt 生成容器成员调用语句（push/put/add/insert/remove/clear/set）。
func (s *scope) containerMemberStmt(recvC string, recvName string, name string, args []xfront.Expr) ([]string, bool, error) {
	acc := "&" + recvName
	var out []string
	switch {
	case strings.HasPrefix(recvC, "xn_arr_"):
		elem, _ := containerElem(recvC)
		switch name {
		case "push":
			v, lines, err := s.elemValue(args[0], elem)
			if err != nil {
				return nil, true, err
			}
			return append(lines, fmt.Sprintf("%s_push(%s, %s);", recvC, acc, v)), true, nil
		case "insert":
			return nil, true, fmt.Errorf("codegen：List.insert 未支持（M4.4a 范围；示例与自举不使用）")
		case "set":
			i, err := s.intExpr(args[0])
			if err != nil {
				return nil, true, err
			}
			v, lines, err := s.elemValue(args[1], elem)
			if err != nil {
				return nil, true, err
			}
			return append(lines, fmt.Sprintf("%s_set(%s, %s, %s);", recvC, acc, i, v)), true, nil
		case "remove":
			i, err := s.intExpr(args[0])
			if err != nil {
				return nil, true, err
			}
			return []string{fmt.Sprintf("%s_remove(%s, %s);", recvC, acc, i)}, true, nil
		case "clear":
			return []string{fmt.Sprintf("%s_clear(%s);", recvC, acc)}, true, nil
		}
		_ = out
		return nil, true, fmt.Errorf("codegen：List 成员 %s 未支持（M4.4a 范围）", name)
	case strings.HasPrefix(recvC, "xn_set_"):
		elem, _ := containerElem(recvC)
		switch name {
		case "add":
			v, lines, err := s.elemValue(args[0], elem)
			if err != nil {
				return nil, true, err
			}
			return append(lines, fmt.Sprintf("%s_add(%s, %s);", recvC, acc, v)), true, nil
		}
		return nil, true, fmt.Errorf("codegen：Set 成员 %s 未支持（M4.4a 范围）", name)
	case strings.HasPrefix(recvC, "xn_map_"):
		k, v := mapTypes(recvC)
		switch name {
		case "put":
			kk, kl, err := s.elemValue(args[0], k)
			if err != nil {
				return nil, true, err
			}
			vv, vl, err := s.elemValue(args[1], v)
			if err != nil {
				return nil, true, err
			}
			return append(append(kl, vl...), fmt.Sprintf("%s_put(%s, %s, %s);", recvC, acc, kk, vv)), true, nil
		case "remove":
			kk, kl, err := s.elemValue(args[0], k)
			if err != nil {
				return nil, true, err
			}
			return append(kl, fmt.Sprintf("%s_remove(%s, %s);", recvC, acc, kk)), true, nil
		case "clear":
			return []string{fmt.Sprintf("%s_clear(%s);", recvC, acc)}, true, nil
		}
		return nil, true, fmt.Errorf("codegen：Map 成员 %s 未支持（M4.4a 范围）", name)
	}
	return nil, false, nil
}

// containerMemberValue 生成容器成员调用的标量/借用值（length/has/get/getOr）。
func (s *scope) containerMemberValue(recvC string, recvName string, name string, args []xfront.Expr) (string, bool, error) {
	if name == "length" {
		if strings.HasPrefix(recvC, "xn_set_") {
			return fmt.Sprintf("((int64_t)%s.a.len)", recvName), true, nil
		}
		return fmt.Sprintf("((int64_t)%s.len)", recvName), true, nil
	}
	if strings.HasPrefix(recvC, "xn_map_") {
		k, v := mapTypes(recvC)
		switch name {
		case "has":
			kk, lines, err := s.elemValue(args[0], k)
			if err != nil {
				return "", true, err
			}
			s.pending = append(s.pending, lines...)
			return fmt.Sprintf("%s_has(&%s, %s)", recvC, recvName, kk), true, nil
		case "getOr":
			kk, kl, err := s.elemValue(args[0], k)
			if err != nil {
				return "", true, err
			}
			s.pending = append(s.pending, kl...)
			d, dl, err := s.elemValue(args[1], v)
			if err != nil {
				return "", true, err
			}
			s.pending = append(s.pending, dl...)
			return fmt.Sprintf("%s_get_or(&%s, %s, %s)", recvC, recvName, kk, d), true, nil
		}
	}
	if strings.HasPrefix(recvC, "xn_set_") {
		elem, _ := containerElem(recvC)
		if name == "add" {
			v, lines, err := s.elemValue(args[0], elem)
			if err != nil {
				return "", true, err
			}
			s.pending = append(s.pending, lines...)
			return fmt.Sprintf("%s_add(&%s, %s)", recvC, recvName, v), true, nil
		}
	}
	if strings.HasPrefix(recvC, "xn_arr_") || strings.HasPrefix(recvC, "xn_set_") {
		switch name {
		case "get":
			i, err := s.intExpr(args[0])
			if err != nil {
				return "", true, err
			}
			return fmt.Sprintf("%s_get(&%s, %s)", recvC, recvName, i), true, nil
		case "has":
			v, err := s.intExpr(args[0])
			if err != nil {
				return "", true, err
			}
			return fmt.Sprintf("%s_has(&%s, %s)", recvC, recvName, v), true, nil
		}
	}
	return "", false, nil
}

// indexRead 生成 `a[i]`（容器下标读取，返回借用值）。
func (s *scope) indexRead(n *xfront.Index) (string, error) {
	id, ok := n.X.(*xfront.IdentExpr)
	if !ok {
		return "", fmt.Errorf("codegen：下标接收者 %T 未支持（M4.4a 范围）", n.X)
	}
	c, ok := s.localCType(id.Name)
	if !ok || !isContainerC(c) {
		return "", fmt.Errorf("codegen：下标接收者 %s 不是容器（M4.4a 范围）", id.Name)
	}
	i, err := s.intExpr(n.Idx)
	if err != nil {
		return "", err
	}
	if strings.HasPrefix(c, "xn_map_") {
		k, v := mapTypes(c)
		if k != "" {
			_ = v
		}
		return "", fmt.Errorf("codegen：Map 下标读取请用 getOr（M4.4a 范围）")
	}
	return fmt.Sprintf("%s_get(&%s, %s)", c, id.Name, i), nil
}

// emitIndexAssign 生成 `a[i] = v`。
func (s *scope) emitIndexAssign(idx *xfront.Index, val xfront.Expr) ([]string, error) {
	id, ok := idx.X.(*xfront.IdentExpr)
	if !ok {
		return nil, fmt.Errorf("codegen：下标赋值接收者 %T 未支持（M4.4a 范围）", idx.X)
	}
	c, ok := s.localCType(id.Name)
	if !ok || !isContainerC(c) {
		return nil, fmt.Errorf("codegen：下标赋值接收者 %s 不是容器（M4.4a 范围）", id.Name)
	}
	elem, ok := containerElem(c)
	if !ok {
		return nil, fmt.Errorf("codegen：容器元素类型推不出（%s）", c)
	}
	i, err := s.intExpr(idx.Idx)
	if err != nil {
		return nil, err
	}
	v, lines, err := s.elemValue(val, elem)
	if err != nil {
		return nil, err
	}
	return append(lines, fmt.Sprintf("%s_set(&%s, %s, %s);", c, id.Name, i, v)), nil
}
