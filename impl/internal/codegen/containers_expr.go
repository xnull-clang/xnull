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
	c = strings.TrimSuffix(strings.TrimSpace(c), "*")
	c = strings.TrimSpace(c)
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
	case "u8":
		return "uint8_t", true
	case "u16":
		return "uint16_t", true
	case "u32":
		return "uint32_t", true
	case "u64":
		return "uint64_t", true
	case "i8":
		return "int8_t", true
	case "i16":
		return "int16_t", true
	case "i32":
		return "int32_t", true
	case "f64":
		return "double", true
	case "f32":
		return "float", true
	case "s":
		return "rt_string *", true
	default:
		if strings.HasPrefix(elem, "o_") {
			return "xn_Cls_" + elem[2:] + " *", true
		}
		if strings.HasPrefix(elem, "t_") {
			return "xn_tup_" + elem[2:], true
		}
	}
	return "", false
}

// valExpr 生成容器值表达式：返回生产语句（末尾临时持有该容器值）与变量名。
func (s *scope) valExpr(e xfront.Expr, wantC string) ([]string, string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		return nil, s.cRef(n.Name), nil
	case *xfront.Paren:
		return s.valExpr(n.X, wantC)
	case *xfront.ArrayLit:
		return s.arrayLit(n, wantC)
	case *xfront.MapLit:
		return s.mapLit(n, wantC)
	case *xfront.Call:
		mem, ok := n.Callee.(*xfront.Member)
		if !ok {
			return nil, "", fmt.Errorf("codegen：容器表达式调用 %T 未支持（M6-B0-05 范围）", n.Callee)
		}
		rt, terr := s.exprType(mem.X)
		if terr == nil && rt == "rt_string *" && mem.Name == "split" {
			if err := s.g.cs.needArr("rt_string *"); err != nil {
				return nil, "", err
			}
			recvLines, err := s.strExpr(mem.X)
			if err != nil {
				return nil, "", err
			}
			sepLines, err := s.strExpr(n.Args[0])
			if err != nil {
				return nil, "", err
			}
			t := s.tmp()
			out := append([]string{}, recvLines...)
			out = append(out, sepLines...)
			out = append(out, fmt.Sprintf("xn_arr_s *%s = xn_str_split(%s, %s);", t, lastVar(recvLines), lastVar(sepLines)))
			return out, t, nil
		}
		recvName, recvC, err := recvCName(mem.X, s)
		if err != nil {
			return nil, "", err
		}
		if !isContainerC(recvC) {
			return nil, "", fmt.Errorf("codegen：容器表达式成员 %s 的接收者 %s 不是容器", mem.Name, recvC)
		}
		switch mem.Name {
		case "keys", "values":
			t := s.tmp()
			return []string{fmt.Sprintf("%s %s = %s_%s(%s);", wantC, t, recvC, mem.Name, recvName)}, t, nil
		}
		return nil, "", fmt.Errorf("codegen：容器成员 %s 不返回值（M6-B0-05 范围）", mem.Name)
	}
	return nil, "", fmt.Errorf("codegen：容器表达式 %T 未支持（M4.4a 范围）", e)
}

func contBase(c string) string {
	c = strings.TrimSpace(c)
	c = strings.TrimSuffix(c, "*")
	return strings.TrimSpace(c)
}

func (s *scope) arrayLit(n *xfront.ArrayLit, wantC string) ([]string, string, error) {
	t := s.tmp()
	var out []string
	wantBase := contBase(wantC)
	if strings.HasPrefix(wantBase, "xn_map_") && len(n.Elems) == 0 {
		// `Map<K,V> m = []`：空数组字面量是空 Map 的常用写法。
		out = append(out, fmt.Sprintf("%s *%s = %s_new(0);", wantBase, t, wantBase))
		return out, t, nil
	}
	if !strings.HasPrefix(wantBase, "xn_arr_") && !strings.HasPrefix(wantBase, "xn_set_") {
		return nil, "", fmt.Errorf("codegen：数组字面量目标类型 %s 不支持（M4.4a 范围）", wantC)
	}
	isSet := strings.HasPrefix(wantBase, "xn_set_")
	arrBase := wantBase
	if isSet {
		arrBase = "xn_arr_" + strings.TrimPrefix(wantBase, "xn_set_")
	}
	elem, ok := containerElem(arrBase)
	if !ok {
		return nil, "", fmt.Errorf("codegen：容器元素类型推不出（%s）", wantC)
	}
	out = append(out, fmt.Sprintf("%s *%s = %s_new(%d);", arrBase, t, arrBase, len(n.Elems)))
	for _, el := range n.Elems {
		v, lines, err := s.elemValue(el, elem)
		if err != nil {
			return nil, "", err
		}
		out = append(out, lines...)
		if isRef(elem) && !s.g.isGCTypeC(elem) {
			// 引用元素：push 内部 retain；字面量/构造产物 +1 需在入容器后释放
			//（Ident/Member 是借用，不释放）。
			switch el.(type) {
			case *xfront.IdentExpr, *xfront.Member:
			default:
				tmp := s.tmp()
				out = append(out, fmt.Sprintf("%s %s = %s;", elem, tmp, v))
				out = append(out, fmt.Sprintf("%s_push(%s, %s);", arrBase, t, tmp))
				out = append(out, fmt.Sprintf("rt_release(%s);", tmp))
				continue
			}
		}
		out = append(out, fmt.Sprintf("%s_push(%s, %s);", arrBase, t, v))
	}
	if isSet {
		st := s.tmp()
		out = append(out, fmt.Sprintf("%s *%s = %s_new();", wantBase, st, wantBase))
		out = append(out, fmt.Sprintf("for (size_t i = 0; i < %s->len; i++) { %s_add(%s, %s->data[i]); }", t, wantBase, st, t))
		return out, st, nil
	}
	return out, t, nil
}

func (s *scope) mapLit(n *xfront.MapLit, wantC string) ([]string, string, error) {
	base := contBase(wantC)
	if !strings.HasPrefix(base, "xn_map_") {
		return nil, "", fmt.Errorf("codegen：Map 字面量目标类型 %s 不支持（M4.4a 范围）", wantC)
	}
	t := s.tmp()
	var out []string
	out = append(out, fmt.Sprintf("%s *%s = %s_new(%d);", base, t, base, len(n.Keys)))
	for i := range n.Keys {
		k, klines, err := s.mapKeyValue(n.Keys[i], base)
		if err != nil {
			return nil, "", err
		}
		out = append(out, klines...)
		v, vlines, err := s.mapValValue(n.Vals[i], base)
		if err != nil {
			return nil, "", err
		}
		out = append(out, vlines...)
		out = append(out, fmt.Sprintf("%s_put(%s, %s, %s);", base, t, k, v))
	}
	return out, t, nil
}

// elemValue 生成容器元素值（Int/Bool/String）。
func (s *scope) elemValue(e xfront.Expr, elemC string) (string, []string, error) {
	if s.g.isTupleC(elemC) {
		lines, v, err := s.tupleExpr(e, elemC)
		return v, lines, err
	}
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
	mapC = strings.TrimSuffix(strings.TrimSpace(mapC), "*")
	mapC = strings.TrimSpace(mapC)
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

// optExpr 生成可空值表达式（M6-B0-05：null / 变量 / 成员 / 字面量 / Map.get）。
func (s *scope) optExpr(e xfront.Expr, optC string) ([]string, string, error) {
	switch n := e.(type) {
	case *xfront.NullLit:
		return nil, "(" + optC + "){0, 0}", nil
	case *xfront.Paren:
		return s.optExpr(n.X, optC)
	case *xfront.IdentExpr:
		if t, err := s.exprType(n); err == nil && t == optC {
			return nil, s.cRef(n.Name), nil
		}
		return s.optWrap(n, optC)
	case *xfront.Member:
		// 可空字段（含 struct/类字段链）：直接引用字段。
		recvName, recvC, err := recvCName(n.X, s)
		if err != nil {
			return nil, "", err
		}
		if s.g.isStructC(recvC) {
			ci, ok := s.g.structOfC(recvC)
			if !ok {
				return nil, "", fmt.Errorf("codegen：未知结构体类型 %s", recvC)
			}
			f, ok := ci.fieldOf(n.Name)
			if !ok {
				return nil, "", fmt.Errorf("codegen：结构体 %s 没有字段 %s", ci.decl.Name, n.Name)
			}
			return nil, recvName + structSep(recvC) + f.cname, nil
		}
		if ci, ok := s.g.classOfC(recvC); ok {
			if f, ok := ci.fieldOf(n.Name); ok {
				return nil, recvName + "->" + f.cname, nil
			}
		}
		return nil, "", fmt.Errorf("codegen：可空成员 %s 的接收者 %s 不支持", n.Name, recvC)
	case *xfront.Call:
		// S6-04：resourceSize 的缺失语义（成功=1 / 缺失=0）落 Int?。
		if id, ok := n.Callee.(*xfront.IdentExpr); ok && id.Name == "resourceSize" {
			lines, expr, err := s.s604Size(n)
			if err != nil {
				return nil, "", err
			}
			return lines, expr, nil
		}
		if id, ok := n.Callee.(*xfront.IdentExpr); ok && id.Name == "env" {
			if len(n.Args) != 1 {
				return nil, "", fmt.Errorf("codegen：env 需要 1 个参数（S6 §4.4）")
			}
			sl, err := s.strExpr(n.Args[0])
			if err != nil {
				return nil, "", err
			}
			t := s.tmp()
			out := append([]string{}, sl...)
			out = append(out, "xn_opt_s "+t+" = xn_env_lookup("+lastVar(sl)+");")
			return out, t, nil
		}
		mem, ok := n.Callee.(*xfront.Member)
		if !ok {
			return s.optWrap(n, optC)
		}
		recvName, recvC, err := recvCName(mem.X, s)
		if err != nil {
			return nil, "", err
		}
		if !strings.HasPrefix(recvC, "xn_map_") || mem.Name != "get" {
			return nil, "", fmt.Errorf("codegen：可空表达式成员 %s 未支持（M6-B0-05 范围）", mem.Name)
		}
		k, _ := mapTypes(recvC)
		kk, lines, err := s.elemValue(n.Args[0], k)
		if err != nil {
			return nil, "", err
		}
		return lines, fmt.Sprintf("%s_get(%s, %s)", recvC, recvName, kk), nil
	}
	return s.optWrap(e, optC)
}

// optWrap 把基础值表达式包成可选值（{has=1, v}）。
func (s *scope) optWrap(e xfront.Expr, optC string) ([]string, string, error) {
	switch optC {
	case "xn_opt_i":
		v, err := s.intExpr(e)
		if err != nil {
			return nil, "", err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return out, "(" + optC + "){1, " + v + "}", nil
	case "xn_opt_b":
		v, err := s.boolExpr(e)
		if err != nil {
			return nil, "", err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return out, "(" + optC + "){1, " + v + "}", nil
	case "xn_opt_s":
		lines, err := s.strExpr(e)
		if err != nil {
			return nil, "", err
		}
		return lines, "(" + optC + "){1, " + lastVar(lines) + "}", nil
	}
	return nil, "", fmt.Errorf("codegen：可空表达式 %T 未支持（M6-B0-05 范围）", e)
}

// containerMemberStmt 生成容器成员调用语句（push/put/add/insert/remove/clear/set）。
func (s *scope) containerMemberStmt(recvC string, recvName string, name string, args []xfront.Expr) ([]string, bool, error) {
	recvC = contBase(recvC)
	acc := recvName
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
			i, err := s.intExpr(args[0])
			if err != nil {
				return nil, true, err
			}
			v, lines, err := s.elemValue(args[1], elem)
			if err != nil {
				return nil, true, err
			}
			return append(lines, fmt.Sprintf("%s_insert(%s, %s, %s);", recvC, acc, i, v)), true, nil
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
			t := s.tmp()
			out := []string{fmt.Sprintf("%s %s = %s_remove(%s, %s);", elem, t, recvC, acc, i)}
			if isRef(elem) && !s.g.isGCTypeC(elem) {
				out = append(out, "rt_release("+t+");")
			}
			return out, true, nil
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
		case "remove":
			v, lines, err := s.elemValue(args[0], elem)
			if err != nil {
				return nil, true, err
			}
			return append(lines, fmt.Sprintf("%s_remove(%s, %s);", recvC, acc, v)), true, nil
		case "clear":
			return []string{fmt.Sprintf("%s_clear(%s);", recvC, acc)}, true, nil
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

// bytesMemberValue 生成 Bytes 成员调用的标量值（length/get，S1 §9.7）。
// 运行时对象是 ARC 管理的 xrt_bytes_obj（E5 BYTES-RUNTIME），字段不可直接读。
func (s *scope) bytesMemberValue(recvName string, name string, args []xfront.Expr) (string, bool, error) {
	switch name {
	case "length":
		return "((int64_t)xrt_bytes_len(" + recvName + "))", true, nil
	case "get":
		idx, err := s.intExpr(args[0])
		if err != nil {
			return "", true, err
		}
		return "((int64_t)xrt_bytes_get(" + recvName + ", (size_t)(" + idx + ")))", true, nil
	case "slice":
		a, err := s.intExpr(args[0])
		if err != nil {
			return "", true, err
		}
		b, err := s.intExpr(args[1])
		if err != nil {
			return "", true, err
		}
		return "xrt_bytes_slice(" + recvName + ", (size_t)(" + a + "), (size_t)(" + b + "))", true, nil
	}
	return "", false, nil
}

// bytesMemberStmt 生成 Bytes 成员调用语句（push/set，S1 §9.7）。
func (s *scope) bytesMemberStmt(recvName string, name string, args []xfront.Expr) ([]string, bool, error) {
	switch name {
	case "push":
		v, err := s.intExpr(args[0])
		if err != nil {
			return nil, true, err
		}
		return []string{"xrt_bytes_push(" + recvName + ", (int32_t)(" + v + "));"}, true, nil
	case "set":
		idx, err := s.intExpr(args[0])
		if err != nil {
			return nil, true, err
		}
		v, err := s.intExpr(args[1])
		if err != nil {
			return nil, true, err
		}
		return []string{"xrt_bytes_set(" + recvName + ", (size_t)(" + idx + "), (int32_t)(" + v + "));"}, true, nil
	case "append":
		id, ok := args[0].(*xfront.IdentExpr)
		if !ok {
			return nil, true, fmt.Errorf("codegen：Bytes.append 实参仅支持变量（S1 §9.7）")
		}
		return []string{"xrt_bytes_append(" + recvName + ", " + s.cRef(id.Name) + ");"}, true, nil
	}
	return nil, false, nil
}

// containerMemberValue 生成容器成员调用的标量/借用值（length/has/get/getOr）。
func (s *scope) containerMemberValue(recvC string, recvName string, name string, args []xfront.Expr) (string, bool, error) {
	recvC = contBase(recvC)
	if name == "length" {
		if strings.HasPrefix(recvC, "xn_set_") {
			return fmt.Sprintf("((int64_t)%s->a->len)", recvName), true, nil
		}
		return fmt.Sprintf("((int64_t)%s->len)", recvName), true, nil
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
			return fmt.Sprintf("%s_has(%s, %s)", recvC, recvName, kk), true, nil
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
			return fmt.Sprintf("%s_get_or(%s, %s, %s)", recvC, recvName, kk, d), true, nil
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
			return fmt.Sprintf("%s_add(%s, %s)", recvC, recvName, v), true, nil
		}
		if name == "at" {
			i, err := s.intExpr(args[0])
			if err != nil {
				return "", true, err
			}
			return fmt.Sprintf("%s_at(%s, %s)", recvC, recvName, i), true, nil
		}
	}
	if strings.HasPrefix(recvC, "xn_arr_") || strings.HasPrefix(recvC, "xn_set_") {
		switch name {
		case "get":
			i, err := s.intExpr(args[0])
			if err != nil {
				return "", true, err
			}
			return fmt.Sprintf("%s_get(%s, %s)", recvC, recvName, i), true, nil
		case "remove":
			if strings.HasPrefix(recvC, "xn_arr_") {
				i, err := s.intExpr(args[0])
				if err != nil {
					return "", true, err
				}
				return fmt.Sprintf("%s_remove(%s, %s)", recvC, recvName, i), true, nil
			}
		case "has":
			v, err := s.intExpr(args[0])
			if err != nil {
				return "", true, err
			}
			return fmt.Sprintf("%s_has(%s, %s)", recvC, recvName, v), true, nil
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
	return fmt.Sprintf("%s_get(%s, %s)", contBase(c), s.cRef(id.Name), i), nil
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
	return append(lines, fmt.Sprintf("%s_set(%s, %s, %s);", contBase(c), s.cRef(id.Name), i, v)), nil
}
