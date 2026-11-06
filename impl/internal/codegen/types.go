// types.go：代码生成期的轻量表达式类型推断（只服务分派决策：
// print 的 Int/Bool/String 分流、容器成员返回值、成员调用接收者判定）。
// 不替代 sema 类型检查——不可判定时返回错误，绝不猜测。
package codegen

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

// exprType 推断表达式的 C 类型（"int64_t" / "int" / "rt_string *" / 容器 / Result）。
func (s *scope) exprType(e xfront.Expr) (string, error) {
	switch n := e.(type) {
	case nil:
		return "void", nil
	case *xfront.IntLitExpr:
		return "int64_t", nil
	case *xfront.FloatLitExpr:
		return "", fmt.Errorf("codegen：Float 未支持（M4.4a 范围）")
	case *xfront.CharLitExpr:
		return "", fmt.Errorf("codegen：Char 未支持（M4.4a 范围）")
	case *xfront.BoolLit:
		return "int", nil
	case *xfront.StrLitExpr:
		return "rt_string *", nil
	case *xfront.NullLit:
		return "", fmt.Errorf("codegen：null 未支持（M4.4a 范围）")
	case *xfront.Paren:
		return s.exprType(n.X)
	case *xfront.IdentExpr:
		if c, ok := s.localCType(n.Name); ok {
			return c, nil
		}
		return "", fmt.Errorf("codegen：未登记标识符 %s（M4.4a 范围：局部/参数）", n.Name)
	case *xfront.New:
		nt, ok := n.Type.(*xfront.NamedType)
		if !ok {
			return "", fmt.Errorf("codegen：new 类型 %T 未支持", n.Type)
		}
		name := lastQualName(nt)
		if _, ok := s.g.classOf(name); !ok {
			return "", fmt.Errorf("codegen：未定义的类 %s", name)
		}
		return "xn_Cls_" + name + " *", nil
	case *xfront.Member:
		_, recvC, err := recvCName(n.X, s)
		if err != nil {
			return "", err
		}
		ci, ok := s.g.classOfC(recvC)
		if !ok {
			return "", fmt.Errorf("codegen：成员 %s 的接收者类型 %s 不可判定（M4.4b 范围）", n.Name, recvC)
		}
		if f, ok := ci.fieldOf(n.Name); ok {
			return f.ctype, nil
		}
		return "", fmt.Errorf("codegen：类 %s 没有字段 %s（裸成员读取；方法请调用）", ci.decl.Name, n.Name)
	case *xfront.Index:
		id, ok := n.X.(*xfront.IdentExpr)
		if !ok {
			return "", fmt.Errorf("codegen：下标接收者 %T 未支持", n.X)
		}
		c, ok := s.localCType(id.Name)
		if !ok {
			return "", fmt.Errorf("codegen：未登记标识符 %s", id.Name)
		}
		elem, ok2 := containerElem(c)
		if !ok2 {
			return "", fmt.Errorf("codegen：%s 不是容器", id.Name)
		}
		return elem, nil
	case *xfront.Unary:
		switch n.Op {
		case "!":
			return "int", nil
		case "-", "+", "~":
			return s.exprType(n.X)
		}
		return "", fmt.Errorf("codegen：一元运算 %s 未支持（M4.4a 范围）", n.Op)
	case *xfront.Binary:
		switch n.Op {
		case "==", "!=", "<", "<=", ">", ">=", "&&", "||":
			return "int", nil
		case "+":
			lt, err := s.exprType(n.L)
			if err != nil {
				return "", err
			}
			if lt == "rt_string *" {
				return "rt_string *", nil
			}
			return "int64_t", nil
		default:
			return "int64_t", nil
		}
	case *xfront.Ternary:
		return s.exprType(n.Then)
	case *xfront.Call:
		if mem, ok := n.Callee.(*xfront.Member); ok {
			recvC, err := s.exprType(mem.X)
			if err != nil {
				return "", err
			}
			if isClassPtr(recvC) {
				ci, ok := s.g.classOfC(recvC)
				if !ok {
					return "", fmt.Errorf("codegen：未知类类型 %s", recvC)
				}
				if m, ok := ci.methodOf(mem.Name); ok {
					return s.g.methodRetC(m)
				}
				if f, ok := ci.fieldOf(mem.Name); ok {
					return f.ctype, nil
				}
				return "", fmt.Errorf("codegen：类 %s 没有成员 %s", ci.decl.Name, mem.Name)
			}
			switch mem.Name {
			case "isOk", "isErr", "has", "add", "remove", "contains":
				return "int", nil
			case "length":
				return "int64_t", nil
			}
			if isContainerC(recvC) {
				if k, v := mapTypes(recvC); k != "" {
					switch mem.Name {
					case "getOr":
						return v, nil
					case "get", "keys", "values":
						return "", fmt.Errorf("codegen：Map.%s 未支持（M4.4a 范围）", mem.Name)
					}
				}
				if elem, ok2 := containerElem(recvC); ok2 {
					switch mem.Name {
					case "get":
						return elem, nil
					}
				}
			}
			if recvC != "" && strings0(recvC) {
				if rt, ok := strMethodReturnNames[mem.Name]; ok {
					return rt, nil
				}
				return "", fmt.Errorf("codegen：String 成员 %s 未支持（M4.4a 范围）", mem.Name)
			}
			return "", fmt.Errorf("codegen：成员 %s 返回类型不可判定（M4.4a 范围）", mem.Name)
		}
		id, ok := n.Callee.(*xfront.IdentExpr)
		if !ok {
			return "", fmt.Errorf("codegen：调用目标 %T 未支持", n.Callee)
		}
		switch id.Name {
		case "Ok", "Err":
			return "", fmt.Errorf("codegen：Ok/Err 需在 Result 上下文使用")
		case "str":
			return "rt_string *", nil
		}
		if ret, ok := s.g.fnRet[id.Name]; ok {
			return ret, nil
		}
		return "", fmt.Errorf("codegen：未知函数 %s（M4.4a 范围）", id.Name)
	}
	return "", fmt.Errorf("codegen：表达式 %T 类型不可判定（M4.4a 范围）", e)
}

// strings0 判断是否为 String 接收者。
func strings0(c string) bool { return c == "rt_string *" }
