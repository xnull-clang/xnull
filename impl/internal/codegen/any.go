// any.go：Any/Object 装箱与拆箱代码生成（S3 §3、§2 类型描述符合同）。
//
// 表示：Any/Object 统一为 GC 盒 `xn_Any *`（typeName + int/string/object 载荷）。
//   - 装箱：值类型/引用类型都装入新 GC 盒；盒的 scan 钩子追踪 String 与对象载荷。
//   - 拆箱：`is` 比较盒内动态类型名；`as?` 不匹配返回零值；`as` 不匹配 fatal。
//   - 所有权：盒本身是 GC 引用，局部/字段不做 retain/release；盒内 ARC 载荷在装箱
//     时 retain，由盒的 scan 在清扫时 release（S3 §5 混合图不变量）。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// isAnyC 判断 C 类型是否为 Any/Object 装箱盒。
func (g *gen) isAnyC(c string) bool { return c == "xn_Any *" }

// anyTypeLabel 返回 C 类型对应的运行期类型名（装箱 typeName / is 比较用）。
// 协议目标暂不支持：协议实现检查需要 vtable 元数据（B2 边界）。
func (g *gen) anyTypeLabel(c string) (string, bool) {
	switch c {
	case "int64_t":
		return "Int", true
	case "int32_t":
		return "Int32", true
	case "int":
		return "Bool", true
	case "rt_string *":
		return "String", true
	case "xn_Any *":
		return "Any", true
	}
	if isClassPtr(c) {
		if name, ok := classPtrName(c); ok {
			return name, true
		}
	}
	if strings.HasPrefix(c, "xn_Enum_") && strings.HasSuffix(c, " *") {
		return strings.TrimSuffix(strings.TrimPrefix(c, "xn_Enum_"), " *"), true
	}
	return "", false
}

// anyBoxC 把 C 表达式装箱为 xn_Any *（表达式为值/引用，已求值一次）。
func (s *scope) anyBoxC(x, lt string) (string, error) {
	switch lt {
	case "int64_t":
		return "xn_box_int((int64_t)(" + x + "))", nil
	case "int32_t":
		return "xn_box_int32((int32_t)(" + x + "))", nil
	case "int":
		return "xn_box_bool((int)(" + x + "))", nil
	case "rt_string *":
		return "xn_box_str(" + x + ")", nil
	}
	if isClassPtr(lt) || s.g.isProtoC(lt) || s.g.isDataEnumC(lt) || s.g.isSingletonC(lt) ||
		isHandlePtr(lt) || lt == "xrt_bytes_obj *" {
		return "xn_box_obj((void *)(" + x + "))", nil
	}
	return "", fmt.Errorf("codegen：类型 %s 暂不支持装箱为 Any/Object（S3 §3）", lt)
}

// anyBoxExpr 求值并装箱任意非 Any 值（String 走 strExpr，其余走 intExpr）。
func (s *scope) anyBoxExpr(e xfront.Expr, lt string) (string, error) {
	if lt == "rt_string *" {
		lines, err := s.strExpr(e)
		if err != nil {
			return "", err
		}
		t := lastVar(lines)
		b := s.tmp()
		s.pending = append(s.pending, lines...)
		s.pending = append(s.pending, "xn_Any *"+b+" = xn_box_str("+t+");", "rt_release("+t+");")
		return b, nil
	}
	x, err := s.intExpr(e)
	if err != nil {
		return "", err
	}
	out := append([]string{}, s.pending...)
	s.pending = nil
	// `new C() as Any`：装箱保留一份后释放构造产生的那份所有权。
	if _, isNew := e.(*xfront.New); isNew {
		t := s.tmp()
		b := s.tmp()
		out = append(out, "void *"+t+" = (void *)("+x+");")
		out = append(out, "xn_Any *"+b+" = xn_box_obj("+t+");")
		out = append(out, "rt_release("+t+");")
		s.pending = append(s.pending, out...)
		return b, nil
	}
	boxed, err := s.anyBoxC(x, lt)
	if err != nil {
		return "", err
	}
	s.pending = append(s.pending, out...)
	return boxed, nil
}

// anyExpr 生成 Any/Object 值表达式：接受已装箱值、`as Any/Object` 表达式，
// 或缺省地把值隐式装箱（sema 只允许显式 as，这里作保守兜底）。
func (s *scope) anyExpr(e xfront.Expr) ([]string, string, error) {
	switch n := e.(type) {
	case nil:
		return nil, "NULL", nil
	case *xfront.NullLit:
		return nil, "NULL", nil
	case *xfront.Paren:
		return s.anyExpr(n.X)
	}
	t, err := s.exprType(e)
	if err != nil {
		return nil, "", err
	}
	if s.g.isAnyC(t) {
		v, err := s.intExpr(e)
		if err != nil {
			return nil, "", err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return out, v, nil
	}
	boxed, err := s.anyBoxExpr(e, t)
	if err != nil {
		return nil, "", err
	}
	out := append([]string{}, s.pending...)
	s.pending = nil
	return out, boxed, nil
}

// anyUnboxCond 生成 Any 拆箱取值的 C 表达式。
// 目标为标量/String/类/数据枚举；协议目标显式拒绝（见 anyTypeLabel）。
func (s *scope) anyUnboxC(x, rt string, nullSafe bool) (string, error) {
	if s.g.isAnyC(rt) {
		return x, nil
	}
	label, ok := s.g.anyTypeLabel(rt)
	if !ok {
		return "", fmt.Errorf("codegen：Any/Object 拆箱到 %s 暂未支持（S3 §3；协议目标需 vtable 元数据）", rt)
	}
	ns := "0"
	if nullSafe {
		ns = "1"
	}
	switch rt {
	case "int64_t", "int32_t", "int":
		v := "xn_any_get_int(" + x + ", " + cQuote(label) + ", " + ns + ")"
		if rt == "int32_t" {
			return "((int32_t)" + v + ")", nil
		}
		if rt == "int" {
			return "((int)" + v + ")", nil
		}
		return v, nil
	case "rt_string *":
		return "xn_any_get_str(" + x + ", " + cQuote(label) + ", " + ns + ")", nil
	}
	// 对象类/数据枚举/单例。
	return "((" + rt + ")xn_any_get_obj(" + x + ", " + cQuote(label) + ", " + ns + "))", nil
}
