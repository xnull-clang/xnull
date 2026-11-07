// s304.go：Text / StringBuilder 的 codegen 发射（S3-04，对齐 E5 运行时 API）。
//
// 运行时合同（E5 cbf93bc，impl/runtime/xrt.h）：
//
//	Text:          xrt_text_from_string / length / code_point_count / to_string / compare_to
//	StringBuilder: xrt_sb_new / append_str / append_int / length / to_string
//
// 两者均为 GC 对象（rd_gc_new/rt_gc_new_size 分配）；codegen 只发调用，根登记由
// S3-02 的 isGCRootC/根帧统一处理，不在这里重复。
package codegen

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

// textExpr 生成 Text 值表达式（构造或已绑定变量）。
func (s *scope) textExpr(e xfront.Expr) ([]string, string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		return nil, s.cRef(n.Name), nil
	case *xfront.NullLit:
		return nil, "NULL", nil
	case *xfront.Paren:
		return s.textExpr(n.X)
	case *xfront.Call:
		mem, ok := n.Callee.(*xfront.Member)
		if !ok {
			return nil, "", fmt.Errorf("codegen：Text 表达式调用 %T 未支持（S3-04）", n.Callee)
		}
		recv, ok := mem.X.(*xfront.IdentExpr)
		if !ok || recv.Name != "Text" || mem.Name != "fromString" || len(n.Args) != 1 {
			return nil, "", fmt.Errorf("codegen：Text.%s 未支持（S3-04：fromString）", mem.Name)
		}
		sl, err := s.strExpr(n.Args[0])
		if err != nil {
			return nil, "", err
		}
		sv := lastVar(sl)
		t := s.tmp()
		out := append([]string{}, sl...)
		out = append(out, "xrt_text *"+t+" = xrt_text_from_string("+sv+"->bytes, "+sv+"->len);")
		return out, t, nil
	}
	return nil, "", fmt.Errorf("codegen：Text 表达式 %T 未支持（S3-04）", e)
}

// sbExpr 生成 StringBuilder 值表达式（构造或已绑定变量）。
func (s *scope) sbExpr(e xfront.Expr) ([]string, string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		return nil, s.cRef(n.Name), nil
	case *xfront.NullLit:
		return nil, "NULL", nil
	case *xfront.Paren:
		return s.sbExpr(n.X)
	case *xfront.Call:
		if id, ok := n.Callee.(*xfront.IdentExpr); ok && id.Name == "StringBuilder" {
			if len(n.Args) != 0 {
				return nil, "", fmt.Errorf("codegen：StringBuilder() 不接受参数（S1 §9.7）")
			}
			t := s.tmp()
			return []string{"xrt_sb *" + t + " = xrt_sb_new();"}, t, nil
		}
	}
	return nil, "", fmt.Errorf("codegen：StringBuilder 表达式 %T 未支持（S3-04）", e)
}

// textMemberValue 生成 Text 标量成员调用（length/codePointCount/compareTo）。
func (s *scope) textMemberValue(recvName, name string, args []xfront.Expr) (string, bool, error) {
	switch name {
	case "length":
		return "((int64_t)xrt_text_length(" + recvName + "))", true, nil
	case "codePointCount":
		return "((int64_t)xrt_text_code_point_count(" + recvName + "))", true, nil
	case "compareTo":
		if len(args) != 1 {
			return "", true, fmt.Errorf("codegen：Text.compareTo 需要 1 个参数（S1 §9.7）")
		}
		u := ""
		switch a := args[0].(type) {
		case *xfront.IdentExpr:
			u = s.cRef(a.Name)
		case *xfront.NullLit:
			u = "NULL"
		default:
			return "", true, fmt.Errorf("codegen：Text.compareTo 实参 %T 未支持（S3-04）", args[0])
		}
		return "((int64_t)xrt_text_compare_to(" + recvName + ", " + u + "))", true, nil
	}
	return "", false, nil
}

// sbMemberValue 生成 StringBuilder 标量成员调用（length）。
func (s *scope) sbMemberValue(recvName, name string) (string, bool, error) {
	if name == "length" {
		return "((int64_t)xrt_sb_length(" + recvName + "))", true, nil
	}
	return "", false, nil
}

// sbMemberStmt 生成 StringBuilder 语句成员（append）。
func (s *scope) sbMemberStmt(recvName, name string, args []xfront.Expr) ([]string, bool, error) {
	if name != "append" {
		return nil, false, nil
	}
	if len(args) != 1 {
		return nil, true, fmt.Errorf("codegen：StringBuilder.append 需要 1 个参数（S1 §9.7）")
	}
	at, err := s.exprType(args[0])
	if err != nil {
		return nil, true, err
	}
	switch at {
	case "rt_string *":
		lines, err := s.strExpr(args[0])
		if err != nil {
			return nil, true, err
		}
		return append(lines, "xrt_sb_append_str("+recvName+", "+lastVar(lines)+"->bytes, "+lastVar(lines)+"->len);"), true, nil
	case "int64_t", "int32_t":
		v, err := s.intExpr(args[0])
		if err != nil {
			return nil, true, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return append(out, "xrt_sb_append_int("+recvName+", (int64_t)("+v+"));"), true, nil
	case "int":
		v, err := s.boolExpr(args[0])
		if err != nil {
			return nil, true, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return append(out, "xrt_sb_append_str("+recvName+", ("+v+") ? \"true\" : \"false\", ("+v+") ? 4 : 5);"), true, nil
	}
	return nil, true, fmt.Errorf("codegen：StringBuilder.append 实参类型 %s 未支持（S3-04）", at)
}

// sbAppendValue 生成 StringBuilder.append 的表达式值（链式调用返回接收者）。
func (s *scope) sbAppendValue(recvName string, args []xfront.Expr) (string, bool, error) {
	lines, hit, err := s.sbMemberStmt(recvName, "append", args)
	if err != nil || !hit {
		return "", hit, err
	}
	s.pending = append(s.pending, lines...)
	return recvName, true, nil
}
