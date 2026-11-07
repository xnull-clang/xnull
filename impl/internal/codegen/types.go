// types.go：代码生成期的轻量表达式类型推断（只服务分派决策：
// print 的 Int/Bool/String 分流、容器成员返回值、成员调用接收者判定）。
// 不替代 sema 类型检查——不可判定时返回错误，绝不猜测。
package codegen

import (
	"fmt"
	"strings"

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
		if n.Name == "self" && s.self != nil {
			return s.self.ctype, nil
		}
		if n.Name == "super" && s.superT != "" {
			return s.superT, nil
		}
		if c, ok := s.localCType(n.Name); ok {
			return c, nil
		}
		if s.staticTypes != nil {
			if c, ok := s.staticTypes[n.Name]; ok {
				return c, nil
			}
		}
		if s.self != nil {
			if c, ok := s.self.types[n.Name]; ok {
				return c, nil
			}
		}
		if c, ok := s.g.globals[n.Name]; ok {
			return c, nil
		}
		return "", fmt.Errorf("codegen：未登记标识符 %s（M4.4a 范围：局部/参数）", n.Name)
	case *xfront.New:
		nt, ok := n.Type.(*xfront.NamedType)
		if !ok {
			return "", fmt.Errorf("codegen：new 类型 %T 未支持", n.Type)
		}
		name := lastQualName(nt)
		if decl, isGen := s.g.classDecls[name]; isGen && len(decl.TypePars) > 0 {
			return s.g.cType(nt)
		}
		if ci, ok := s.g.structs[name]; ok {
			return ci.cname, nil
		}
		if _, ok := s.g.classOf(name); !ok {
			return "", fmt.Errorf("codegen：未定义的类 %s", name)
		}
		return "xn_Cls_" + name + " *", nil
	case *xfront.Tuple:
		elems := make([]string, 0, len(n.Elems))
		for _, el := range n.Elems {
			ec, err := s.exprType(el)
			if err != nil {
				return "", err
			}
			elems = append(elems, ec)
		}
		if len(elems) < 2 {
			return "", fmt.Errorf("codegen：元组至少需要两个元素（S1 §2.11）")
		}
		return s.g.tupleOf(elems), nil
	case *xfront.TupleMember:
		baseT, err := s.exprType(n.X)
		if err != nil {
			return "", err
		}
		elems, ok := s.g.tupleElems(baseT)
		if !ok {
			return "", fmt.Errorf("codegen：成员 .%d 的接收者 %s 不是元组", n.Index, baseT)
		}
		if n.Index < 0 || n.Index >= len(elems) {
			return "", fmt.Errorf("codegen：元组下标 .%d 越界", n.Index)
		}
		return elems[n.Index], nil
	case *xfront.Member:
		if _, t, ok := s.g.singletonStatic(n); ok {
			return t, nil
		}
		if ci, _, ok := s.g.singletonInstance(n); ok {
			return ci.cname + " *", nil
		}
		if ei, _, ok := s.g.enumItem(n); ok {
			return ei.ctype, nil
		}
		_, recvC, err := recvCName(n.X, s)
		if err != nil {
			return "", err
		}
		if s.g.isStructC(recvC) {
			if ci, ok := s.g.structOfC(recvC); ok {
				if f, ok := ci.fieldOf(n.Name); ok {
					return f.ctype, nil
				}
			}
			return "", fmt.Errorf("codegen：结构体没有成员 %s", n.Name)
		}
		ci, ok := s.g.classOfC(recvC)
		if !ok {
			return "", fmt.Errorf("codegen：成员 %s 的接收者类型 %s 不可判定（M4.4b 范围）", n.Name, recvC)
		}
		if f, ok := ci.fieldOf(n.Name); ok {
			if f.semC != "" {
				return f.semC, nil
			}
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
		if n.Op == "==" || n.Op == "!=" || n.Op == "===" || n.Op == "!==" {
			if lt, err := s.exprType(n.L); err == nil && s.g.isTupleC(lt) {
				return "int", nil
			}
		}
		switch n.Op {
		case "==", "!=", "===", "!==", "<", "<=", ">", ">=", "&&", "||", "is":
			return "int", nil
		case "as", "as?":
			if ta, ok := n.R.(*xfront.TypeAsExpr); ok {
				return s.g.cType(s.g.substitute(ta.Type))
			}
			return "", fmt.Errorf("codegen：%s 缺少目标类型", n.Op)
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
		if id, ok := n.Callee.(*xfront.IdentExpr); ok && id.Name == "StringBuilder" {
			return "xrt_sb *", nil
		}
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if _, retC, hit, err := s.staticClassCall(mem, n); err != nil {
				return "", err
			} else if hit {
				return retC, nil
			}
			if fi, m, ok := s.g.factoryMethod(mem, len(n.Args)); ok {
				if len(m.TypePars) > 0 {
					key := "Factory_" + fi.decl.Name + "_" + m.Name
					inst, err := s.g.needInstance(key, n.TypeArgs)
					if err != nil {
						return "", err
					}
					return inst.retC, nil
				}
				return fi.retC[m], nil
			}
			// Bytes/Text 静态构造入口（S1 §9.7）。
			if recv, ok2 := mem.X.(*xfront.IdentExpr); ok2 {
				if recv.Name == "Bytes" && mem.Name == "fromString" {
					return "xrt_bytes_obj *", nil
				}
				if recv.Name == "Text" && mem.Name == "fromString" {
					return "xrt_text *", nil
				}
			}
			// S3-04：Text.fromString / StringBuilder() 构造。
			if recv, ok2 := mem.X.(*xfront.IdentExpr); ok2 && recv.Name == "Text" && mem.Name == "fromString" {
				return "xrt_text *", nil
			}
			recvC, err := s.exprType(mem.X)
			if err != nil {
				return "", err
			}
			if strings.HasPrefix(recvC, "xn_Result_") {
				switch mem.Name {
				case "isOk", "isErr":
					return "int", nil
				case "value":
					mC, err := s.g.resultMemberC(recvC)
					if err != nil {
						return "", err
					}
					return mC, nil
				case "error":
					info, err := s.g.resultInfo(recvC)
					if err != nil {
						return "", err
					}
					return info.errC, nil
				case "unwrapOr":
					mC, err := s.g.resultMemberC(recvC)
					if err != nil {
						return "", err
					}
					return mC, nil
				}
			}
			if s.g.isProtoC(recvC) {
				pi := s.g.protocols[strings.TrimPrefix(recvC, "xn_proto_")]
				if pi == nil {
					return "", fmt.Errorf("codegen：未定义的协议类型 %s", recvC)
				}
				sig := pi.protoSigOf(mem.Name, len(n.Args))
				if sig == nil {
					return "", fmt.Errorf("codegen：协议 %s 没有方法 %s/%d（S2 §4.2）", pi.name, mem.Name, len(n.Args))
				}
				if sig.void {
					return "void", nil
				}
				return s.g.cType(sig.ret)
			}
			if s.g.isStructC(recvC) {
				ci, _ := s.g.structOfC(recvC)
				if m, ok := s.methodFor(ci, mem.Name, n.Args); ok {
					return s.g.methodRetC(m)
				}
				return "", fmt.Errorf("codegen：结构体没有方法 %s", mem.Name)
			}
			if s.g.isDataEnumC(recvC) {
				name := strings.TrimSuffix(strings.TrimPrefix(recvC, "xn_Enum_"), " *")
				if ei, ok := s.g.enums[name]; ok && ei.cls != nil {
					if m, ok := s.methodFor(ei.cls, mem.Name, n.Args); ok {
						return s.g.methodRetC(m)
					}
				}
				return "", fmt.Errorf("codegen：数据枚举没有方法 %s", mem.Name)
			}
			if isClassPtr(recvC) || s.g.isSingletonC(recvC) {
				ci, ok := s.g.classOfC(recvC)
				if !ok {
					return "", fmt.Errorf("codegen：未知类类型 %s", recvC)
				}
				if m, ok := s.methodFor(ci, mem.Name, n.Args); ok {
					return s.g.methodRetC(m)
				}
				if f, ok := ci.fieldOf(mem.Name); ok {
					return f.ctype, nil
				}
				return "", fmt.Errorf("codegen：类 %s 没有成员 %s", ci.decl.Name, mem.Name)
			}
			if recvC == "xrt_bytes_obj *" {
				switch mem.Name {
				case "length", "get":
					return "int64_t", nil
				case "slice":
					return "xrt_bytes_obj *", nil
				case "append":
					return "void", nil
				}
			}
			if recvC == "xrt_text *" {
				switch mem.Name {
				case "length", "codePointCount", "compareTo":
					return "int64_t", nil
				case "toString":
					return "rt_string *", nil
				}
			}
			if recvC == "xrt_sb *" {
				switch mem.Name {
				case "length":
					return "int64_t", nil
				case "toString":
					return "rt_string *", nil
				case "append":
					return "void", nil
				}
			}
			if recvC == "xrt_text *" {
				switch mem.Name {
				case "length", "codePointCount", "compareTo":
					return "int64_t", nil
				case "toString":
					return "rt_string *", nil
				}
			}
			if recvC == "xrt_sb *" {
				switch mem.Name {
				case "length":
					return "int64_t", nil
				case "toString":
					return "rt_string *", nil
				case "append":
					return "xrt_sb *", nil
				}
			}
			switch mem.Name {
			case "isOk", "isErr", "has", "add", "contains":
				return "int", nil
			case "length":
				return "int64_t", nil
			}
			if isContainerC(recvC) {
				if k, v := mapTypes(recvC); k != "" {
					switch mem.Name {
					case "getOr":
						return v, nil
					case "get":
						return optName(v)
					case "keys":
						if err := s.g.cs.needArr(k); err != nil {
							return "", err
						}
						return arrName(k), nil
					case "values":
						if err := s.g.cs.needArr(v); err != nil {
							return "", err
						}
						return arrName(v), nil
					case "remove":
						return "int", nil
					}
				}
				if elem, ok2 := containerElem(recvC); ok2 {
					switch mem.Name {
					case "get", "at":
						return elem, nil
					case "remove":
						if strings.HasPrefix(recvC, "xn_set_") {
							return "int", nil // Set.remove 返回 Bool（与解释器一致）
						}
						return elem, nil // List.remove 返回被删元素
					case "join":
						return "rt_string *", nil
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
		// S6-03：内建 sys Async/Process 入口。
		if t, ok := sys603Type(id.Name); ok {
			return t, nil
		}
		// S6-04：资源读取内建入口。
		if t, ok, err := s604Type(id.Name, s.g); ok {
			return t, err
		}
		switch id.Name {
		case "Ok", "Err":
			return "", fmt.Errorf("codegen：Ok/Err 需在 Result 上下文使用")
		case "str":
			return "rt_string *", nil
		}
		if s.self != nil && (s.params == nil || !s.params[id.Name]) {
			if _, local := s.locals[id.Name]; !local {
				if m, ok := s.methodFor(s.self.ci, id.Name, n.Args); ok && !m.decl.IsDeinit {
					return s.g.methodRetC(m)
				}
			}
		}
		if ret, ok := s.g.callRetC(id.Name, n.TypeArgs); ok {
			return ret, nil
		}
		// 泛型调用的失败原因要给准（缺实参 / 数量不符 / 非泛型带实参），
		// 不要笼统报「未知函数」。
		if s.g.isGenericName(id.Name) || len(n.TypeArgs) > 0 {
			return "", fmt.Errorf("codegen：%s", s.g.callErr(id.Name, n.TypeArgs))
		}
		return "", fmt.Errorf("codegen：未知函数 %s（M4.4a 范围）", id.Name)
	}
	return "", fmt.Errorf("codegen：表达式 %T 类型不可判定（M4.4a 范围）", e)
}

// strings0 判断是否为 String 接收者。
func strings0(c string) bool { return c == "rt_string *" }
