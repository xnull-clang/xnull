// strmethods.go：String 成员方法生成（S1 §9.2，字节语义，与解释器逐字节对齐）。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// strMemberValue 生成 String 成员调用。
// wantStr=true 时用于字符串上下文（substring/trim/toUpper/toLower 返回新串），
// false 时用于标量上下文（length/indexOf/startsWith/endsWith）。
func (s *scope) strMemberValue(mem *xfront.Member, args []xfront.Expr, wantStr bool) (string, bool, error) {
	recv := ""
	if id, ok := mem.X.(*xfront.IdentExpr); ok {
		recv = id.Name
		if s.params != nil && s.params[recv] {
			recv = "xn_p_" + recv
		}
	} else {
		// 字面量/表达式接收者：先求值得到 owned 串
		lines, err := s.strExpr(mem.X)
		if err != nil {
			return "", true, err
		}
		s.pending = append(s.pending, lines...)
		recv = lastVar(lines)
	}
	strArg := func(i int) (string, error) {
		lines, err := s.strExpr(args[i])
		if err != nil {
			return "", err
		}
		s.pending = append(s.pending, lines...)
		return lastVar(lines), nil
	}
	switch mem.Name {
	case "length":
		return fmt.Sprintf("xn_str_length(%s)", recv), true, nil
	case "indexOf":
		sub, err := strArg(0)
		if err != nil {
			return "", true, err
		}
		return fmt.Sprintf("xn_str_indexof(%s, %s)", recv, sub), true, nil
	case "startsWith":
		sub, err := strArg(0)
		if err != nil {
			return "", true, err
		}
		return fmt.Sprintf("xn_str_startswith(%s, %s)", recv, sub), true, nil
	case "endsWith":
		sub, err := strArg(0)
		if err != nil {
			return "", true, err
		}
		return fmt.Sprintf("xn_str_endswith(%s, %s)", recv, sub), true, nil
	}
	if !wantStr {
		return "", false, nil
	}
	switch mem.Name {
	case "substring":
		start, err := s.intExpr(args[0])
		if err != nil {
			return "", true, err
		}
		n, err := s.intExpr(args[1])
		if err != nil {
			return "", true, err
		}
		return fmt.Sprintf("xn_str_substr(%s, %s, %s)", recv, start, n), true, nil
	case "trim":
		return fmt.Sprintf("xn_str_trim(%s)", recv), true, nil
	case "toUpper":
		return fmt.Sprintf("xn_str_upper(%s)", recv), true, nil
	case "toLower":
		return fmt.Sprintf("xn_str_lower(%s)", recv), true, nil
	}
	return "", false, nil
}

// strMethodReturnNames 供 exprType 复用（保持单一来源）。
var strMethodReturnNames = map[string]string{
	"length":     "int64_t",
	"indexOf":    "int64_t",
	"startsWith": "int",
	"endsWith":   "int",
	"substring":  "rt_string *",
	"trim":       "rt_string *",
	"toUpper":    "rt_string *",
	"toLower":    "rt_string *",
}

var _ = strings.TrimSpace
