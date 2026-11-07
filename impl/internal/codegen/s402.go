// s402.go：xdk.errors 的 codegen 发射（S4-02）。
//
// 运行时/契约：
//
//	wrap<E>(Result<T,E>, E) -> Result<T,E>         失败丢弃原错误、换新错误
//	mapErr<T,E1,E2>(Result<T,E1>, (E1)->E2) -> Result<T,E2>
//	report<E: Error>(Result<T,E>) -> Result<T,E>    失败时单行输出 [kind] describe
//
// Result 为内联值结构（S3-RESULT）；report 的输出走生成前置的 xn_report_line：
// 栈缓冲 + write(2)，单行、无堆分配（S4 §9 / E5 75f9e16 诊断通道）。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// resultErrExpr 生成 Err(e) 的内联 Result 值（任意 E）。
func (s *scope) resultErrExpr(resultC string, e xfront.Expr) (string, error) {
	info, err := s.g.resultInfo(resultC)
	if err != nil {
		return "", err
	}
	expr, err := s.resultMemberValue(info.errC, e)
	if err != nil {
		return "", err
	}
	return "(" + resultC + "){0, " + s.g.resultZeroC(info.memberC) + ", " + expr + "}", nil
}

// resultMemberValue 生成给定 C 类型的值表达式（E 或 V 成员构造）。
func (s *scope) resultMemberValue(c string, e xfront.Expr) (string, error) {
	switch {
	case c == "rt_string *":
		return s.strExprOne(e)
	case s.g.isProtoC(c):
		lines, v, _, err := s.protoValue(e)
		if err != nil {
			return "", err
		}
		s.pending = append(s.pending, lines...)
		return v, nil
	case isClassPtr(c):
		lines, v, owns, err := s.classValueExpr(e)
		if err != nil {
			return "", err
		}
		s.pending = append(s.pending, lines...)
		if !owns && !s.g.classIsGC(c) {
			return "((" + c + ")rt_retain((void *)" + v + "))", nil
		}
		return v, nil
	case s.g.isStructC(c):
		lines, v, err := s.structValue(e, c)
		if err != nil {
			return "", err
		}
		s.pending = append(s.pending, lines...)
		return v, nil
	default:
		return s.intExpr(e)
	}
}

// emitResultWrap 生成 wrap(r, e)：失败时以新错误替换，成功原样通过。
func (s *scope) emitResultWrap(n *xfront.Call, resultC string) (string, error) {
	if len(n.Args) != 2 {
		return "", fmt.Errorf("codegen：wrap 需要 2 个参数（S4-02）")
	}
	info, err := s.g.resultInfo(resultC)
	if err != nil {
		return "", err
	}
	src, err := s.resultExpr(n.Args[0], resultC)
	if err != nil {
		return "", err
	}
	lines := append([]string{}, s.pending...)
	s.pending = nil
	if errArg := n.Args[1]; errArg != nil {
		ev, err := s.resultMemberValue(info.errC, errArg)
		if err != nil {
			return "", err
		}
		lines = append(lines, s.pending...)
		s.pending = nil
		tmp := s.tmp()
		et := s.tmp()
		lines = append(lines, info.errC+" "+et+" = "+ev+";")
		lines = append(lines, resultC+" "+tmp+" = "+src+";")
		lines = append(lines, "if (!"+tmp+".ok) { "+tmp+".err = "+et+"; }")
		s.pending = append(s.pending, lines...)
		return tmp, nil
	}
	return "", fmt.Errorf("codegen：wrap 缺少错误实参（S4-02）")
}

// emitResultMapErr 生成 mapErr(r, f)：Ok 原样通过；Err 用 f 映射到目标 E2。
func (s *scope) emitResultMapErr(n *xfront.Call, resultC string) (string, error) {
	if len(n.Args) != 2 {
		return "", fmt.Errorf("codegen：mapErr 需要 2 个参数（S4-02）")
	}
	srcC, err := s.exprType(n.Args[0])
	if err != nil {
		return "", err
	}
	if !strings.HasPrefix(srcC, "xn_Result_") {
		return "", fmt.Errorf("codegen：mapErr 实参不是 Result（%s）", srcC)
	}
	dst, err := s.g.resultInfo(resultC)
	if err != nil {
		return "", err
	}
	id, ok := n.Args[1].(*xfront.IdentExpr)
	if !ok {
		return "", fmt.Errorf("codegen：mapErr 转换函数仅支持顶层函数（闭包未实现，S4-02）")
	}
	cn, err := s.g.callName(id.Name, nil, 1)
	if err != nil {
		return "", err
	}
	src, err := s.resultExpr(n.Args[0], srcC)
	if err != nil {
		return "", err
	}
	lines := append([]string{}, s.pending...)
	s.pending = nil
	sTmp := s.tmp()
	dTmp := s.tmp()
	lines = append(lines, srcC+" "+sTmp+" = "+src+";")
	lines = append(lines, resultC+" "+dTmp+";")
	lines = append(lines, "if ("+sTmp+".ok) {")
	lines = append(lines, "    "+dTmp+".ok = 1;")
	lines = append(lines, "    "+dTmp+".v = "+sTmp+".v;")
	lines = append(lines, "    "+dTmp+".err = "+s.g.resultZeroC(dst.errC)+";")
	lines = append(lines, "} else {")
	lines = append(lines, "    "+dTmp+".ok = 0;")
	lines = append(lines, "    "+dTmp+".v = "+s.g.resultZeroC(dst.memberC)+";")
	lines = append(lines, "    "+dTmp+".err = ("+dst.errC+")"+cn+"("+sTmp+".err);")
	lines = append(lines, "}")
	s.pending = append(s.pending, lines...)
	return dTmp, nil
}

// emitResultReport 生成 report(r)：失败时单行诊断 [kind] describe，返回原 Result。
func (s *scope) emitResultReport(arg xfront.Expr, resultC string) (string, error) {
	info, err := s.g.resultInfo(resultC)
	if err != nil {
		return "", err
	}
	src, err := s.resultExpr(arg, resultC)
	if err != nil {
		return "", err
	}
	lines := append([]string{}, s.pending...)
	s.pending = nil
	tmp := s.tmp()
	kindExpr, descExpr, err := s.reportKindDescribe(info.errC, tmp+".err")
	if err != nil {
		return "", err
	}
	lines = append(lines, resultC+" "+tmp+" = "+src+";")
	lines = append(lines, "if (!"+tmp+".ok) {")
	lines = append(lines, "    xn_report_line((int64_t)("+kindExpr+"), "+descExpr+");")
	lines = append(lines, "}")
	s.pending = append(s.pending, lines...)
	return tmp, nil
}

// reportKindDescribe 由错误 C 类型生成 kind / describe 表达式（单行诊断用）。
func (s *scope) reportKindDescribe(errC, errExpr string) (string, string, error) {
	switch {
	case errC == "xn_Enum_ErrorKind":
		// 错误类型本身就是分类：kind = 该值，无 describe。
		return errExpr, "NULL", nil
	case errC == "rt_string *":
		// 非 Error 类型（过渡）：归 Internal，describe 用错误串。
		return "XRT_ERR_INTERNAL", errExpr, nil
	case isClassPtr(errC):
		ci, ok := s.g.classOfC(errC)
		if !ok {
			return "", "", fmt.Errorf("codegen：report 的错误类型 %s 不可判定（S4-02）", errC)
		}
		km, ok := ci.methods["kind"]
		if !ok {
			return "", "", fmt.Errorf("codegen：report 要求错误类型实现 Error.kind()（S4-02）")
		}
		dm, ok := ci.methods["describe"]
		if !ok {
			return "", "", fmt.Errorf("codegen：report 要求错误类型实现 Error.describe()（S4-02）")
		}
		return km.cname + "(" + errExpr + ")", dm.cname + "(" + errExpr + ")", nil
	case s.g.isProtoC(errC):
		return "", "", fmt.Errorf("codegen：report 的协议错误类型暂未支持（S4-02 边界）")
	case s.g.isStructC(errC):
		ci, _ := s.g.structOfC(errC)
		km, ok := ci.methods["kind"]
		if !ok {
			return "", "", fmt.Errorf("codegen：report 要求错误结构体实现 kind()（S4-02）")
		}
		dm, ok := ci.methods["describe"]
		if !ok {
			return "", "", fmt.Errorf("codegen：report 要求错误结构体实现 describe()（S4-02）")
		}
		return km.cname + "(&" + errExpr + ")", dm.cname + "(&" + errExpr + ")", nil
	}
	return "", "", fmt.Errorf("codegen：report 不支持错误类型 %s（S4-02）", errC)
}

// cDecl 生成成员声明：指针类型不额外插空格（rt_string *err）。
func cDecl(c, name string) string {
	if strings.HasSuffix(c, "*") {
		return c + name + ";"
	}
	return c + " " + name + ";"
}
