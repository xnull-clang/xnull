// s609.go：S6-09 net socket/HTTP 的 Async 语言面（Context 首参）。
//
// `.xfb` 无法表达 Context（S7 §3.6），因此 *Async 入口在 codegen 合成：
//   - 注入 XNull 声明（sema 名称/类型检查）；
//   - 调用点降到 E5 原语 xdkc_net_* / xdkc_http_*，先做 Context 取消检查，
//     取消返回 Err(Cancelled)，不发起阻塞调用；
//   - 结果构造 Result<T, ErrorKind>，复用 .xfb 的 errorMap 映射函数。
package codegen

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

type net609Kind int

const (
	k609Connect net609Kind = iota
	k609Listen
	k609Accept
	k609Read
	k609Write
	k609Close
	k609ListenerClose
	k609HTTPGet
	k609HTTPPost
)

var net609Kinds = map[string]net609Kind{
	"socketConnectAsync": k609Connect,
	"socketListenAsync":  k609Listen,
	"socketAcceptAsync":  k609Accept,
	"socketReadAsync":    k609Read,
	"socketWriteAsync":   k609Write,
	"socketCloseAsync":   k609Close,
	"listenerCloseAsync": k609ListenerClose,
	"httpGet":            k609HTTPGet,
	"httpPost":           k609HTTPPost,
}

// net609XType 返回内建入口的 XNull 返回类型（Result<T, ErrorKind>）。
func net609XType(name string) xfront.TypeRef {
	pos := xfront.Pos{Line: 1, Col: 1}
	nt := func(n string) xfront.TypeRef { return &xfront.NamedType{P: pos, Qual: []string{n}} }
	res := func(v string) xfront.TypeRef {
		return &xfront.NamedType{P: pos, Qual: []string{"Result"},
			Args: []xfront.TypeRef{nt(v), nt("ErrorKind")}}
	}
	switch name {
	case "socketConnectAsync", "socketAcceptAsync":
		return res("Socket")
	case "socketListenAsync":
		return res("Listener")
	case "socketReadAsync":
		return res("Int64")
	case "socketWriteAsync":
		return res("Int64")
	case "socketCloseAsync", "listenerCloseAsync":
		return &xfront.NamedType{P: pos, Qual: []string{"Result"},
			Args: []xfront.TypeRef{nt("void"), nt("ErrorKind")}}
	case "httpGet", "httpPost":
		return res("Bytes")
	}
	return nil
}

// net609Decls 构造 Async/HTTP 的内建声明。
func net609Decls() []*xfront.TopFunc {
	pos := xfront.Pos{Line: 1, Col: 1}
	nt := func(n string) xfront.TypeRef { return &xfront.NamedType{P: pos, Qual: []string{n}} }
	p := func(name, typ string) *xfront.Param { return &xfront.Param{Name: name, Type: nt(typ)} }
	mk := func(name string, params ...*xfront.Param) *xfront.TopFunc {
		fn := &xfront.TopFunc{P: pos, Name: name, Static: true, Public: true, Ret: net609XType(name)}
		fn.Params = params
		fn.Body = &xfront.Block{Stmts: []xfront.Stmt{&xfront.WhileStmt{Cond: &xfront.BoolLit{V: true}, Body: &xfront.Block{}}}}
		return fn
	}
	return []*xfront.TopFunc{
		mk("socketConnectAsync", p("ctx", "Context"), p("host", "String"), p("port", "Int32")),
		mk("socketListenAsync", p("ctx", "Context"), p("host", "String"), p("port", "Int32")),
		mk("socketAcceptAsync", p("ctx", "Context"), p("l", "Listener")),
		mk("socketReadAsync", p("ctx", "Context"), p("s", "Socket"), p("buf", "Bytes")),
		mk("socketWriteAsync", p("ctx", "Context"), p("s", "Socket"), p("buf", "Bytes")),
		mk("socketCloseAsync", p("ctx", "Context"), p("s", "Socket")),
		mk("listenerCloseAsync", p("ctx", "Context"), p("l", "Listener")),
		mk("httpGet", p("ctx", "Context"), p("url", "String")),
		mk("httpPost", p("ctx", "Context"), p("url", "String"), p("body", "Bytes")),
	}
}

// InjectNet609 把 net Async/HTTP 声明追加到编译单元（net.xfb 已声明 Socket/Listener）。
func InjectNet609(u *xfront.CompilationUnit) error {
	declared := map[string]bool{}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			declared[n.Name] = true
		case *xfront.TopField:
			declared[n.Name] = true
		case *xfront.ClassDecl:
			declared[n.Name] = true
		}
	}
	for _, fn := range net609Decls() {
		if declared[fn.Name] {
			return fmt.Errorf("codegen：S6-09 内建入口 %s 与编译单元内已有声明重名", fn.Name)
		}
		u.Decls = append(u.Decls, fn)
		declared[fn.Name] = true
	}
	return nil
}

// net609Result 生成 Result<T, ErrorKind> 构造：ok 条件 + 成功值 + 错误码表达式。
func (s *scope) net609Result(resultC, okExpr, valExpr, errExpr string) ([]string, string, error) {
	info, err := s.g.resultInfo(resultC)
	if err != nil {
		return nil, "", err
	}
	s.g.results[resultC] = ""
	r := s.tmp()
	var lines []string
	lines = append(lines, resultC+" "+r+" = {0};")
	lines = append(lines, r+".ok = ("+okExpr+") ? 1 : 0;")
	if valExpr != "" {
		lines = append(lines, "if ("+r+".ok) { "+r+".v = "+valExpr+"; }")
	}
	lines = append(lines, fmt.Sprintf("if (!%s.ok) { %s.err = (%s)%s; }", r, r, info.errC, errExpr))
	return lines, r, nil
}

// net609Call 生成 Async/HTTP 调用（返回前置语句与 Result 表达式）。
func (s *scope) net609Call(call *xfront.Call) ([]string, string, bool, error) {
	id, ok := call.Callee.(*xfront.IdentExpr)
	if !ok {
		return nil, "", false, nil
	}
	kind, ok := net609Kinds[id.Name]
	if !ok {
		return nil, "", false, nil
	}
	name := id.Name
	lines := append([]string{}, s.pending...)
	s.pending = nil
	add := func(ls ...string) { lines = append(lines, ls...) }
	arg := func(i int) (xfront.Expr, error) {
		if i >= len(call.Args) {
			return nil, fmt.Errorf("codegen：%s 缺少实参 %d", name, i+1)
		}
		return call.Args[i], nil
	}
	ctxArg := func() (string, error) {
		e, err := arg(0)
		if err != nil {
			return "", err
		}
		return s.sys603ArgCtx(e)
	}
	hostArg := func(i int) (string, error) {
		e, err := arg(i)
		if err != nil {
			return "", err
		}
		sl, err := s.strExpr(e)
		if err != nil {
			return "", err
		}
		add(sl...)
		return lastVar(sl), nil
	}
	portArg := func(i int) (string, error) {
		e, err := arg(i)
		if err != nil {
			return "", err
		}
		return s.intExpr(e)
	}
	handleArg := func(i int) (string, string, error) {
		e, err := arg(i)
		if err != nil {
			return "", "", err
		}
		return s.sys603ArgHandle(e)
	}
	bytesArg := func(i int) (string, string, error) {
		e, err := arg(i)
		if err != nil {
			return "", "", err
		}
		return s.sys603ArgBytes(e)
	}
	errKind := func(code string, cancelled string) string {
		return "(" + cancelled + " != 0) ? XRT_ERR_CANCELLED : xn_ffi_xdkc_net_error_kind_id(" + code + ")"
	}

	switch kind {
	case k609Connect, k609Listen:
		ctx, err := ctxArg()
		if err != nil {
			return nil, "", true, err
		}
		host, err := hostArg(1)
		if err != nil {
			return nil, "", true, err
		}
		port, err := portArg(2)
		if err != nil {
			return nil, "", true, err
		}
		native := "xdkc_net_connect"
		if kind == k609Listen {
			native = "xdkc_net_listen"
		}
		code, xc, nv, h := s.tmp(), s.tmp(), s.tmp(), s.tmp()
		add("int32_t " + code + " = 0;")
		add("int32_t " + xc + " = xrt_context_check_cancel(" + ctx + ");")
		add("void *" + nv + " = NULL;")
		add("if (" + xc + " == 0) { " + nv + " = " + native + "(" + host + "->bytes, " + host + "->len, (int32_t)(" + port + "), &" + code + "); }")
		add("rt_release(" + host + ");")
		add("xrt_handle *" + h + " = (" + nv + " == NULL) ? NULL : xrt_handle_new(" + nv + ", NULL, \"" + name + "\");")
		resultC, err := s.g.cType(net609XType(name))
		if err != nil {
			return nil, "", true, err
		}
		rl, expr, err := s.net609Result(resultC, h+" != NULL", h, errKind(code, xc))
		if err != nil {
			return nil, "", true, err
		}
		add(rl...)
		return lines, expr, true, nil

	case k609Accept:
		ctx, err := ctxArg()
		if err != nil {
			return nil, "", true, err
		}
		_, hn, err := handleArg(1)
		if err != nil {
			return nil, "", true, err
		}
		code, xc, nv, h := s.tmp(), s.tmp(), s.tmp(), s.tmp()
		add("int32_t " + code + " = 0;")
		add("int32_t " + xc + " = xrt_context_check_cancel(" + ctx + ");")
		add("void *" + nv + " = NULL;")
		add("if (" + xc + " == 0) { " + nv + " = xdkc_net_accept(" + hn + ", &" + code + "); }")
		add("xrt_handle *" + h + " = (" + nv + " == NULL) ? NULL : xrt_handle_new(" + nv + ", NULL, \"" + name + "\");")
		resultC, _ := s.g.cType(net609XType(name))
		rl, expr, err := s.net609Result(resultC, h+" != NULL", h, errKind(code, xc))
		add(rl...)
		return lines, expr, true, err

	case k609Read:
		ctx, err := ctxArg()
		if err != nil {
			return nil, "", true, err
		}
		_, hn, err := handleArg(1)
		if err != nil {
			return nil, "", true, err
		}
		data, blen, err := bytesArg(2)
		if err != nil {
			return nil, "", true, err
		}
		code, xc, n := s.tmp(), s.tmp(), s.tmp()
		add("int32_t " + code + " = 0;")
		add("int32_t " + xc + " = xrt_context_check_cancel(" + ctx + ");")
		add("int64_t " + n + " = -1;")
		add("if (" + xc + " == 0) { " + n + " = xdkc_net_read(" + hn + ", " + data + ", " + blen + ", &" + code + "); }")
		resultC, _ := s.g.cType(net609XType(name))
		rl, expr, err := s.net609Result(resultC, code+" == 0 && "+xc+" == 0", n, errKind(code, xc))
		add(rl...)
		return lines, expr, true, err

	case k609Write:
		ctx, err := ctxArg()
		if err != nil {
			return nil, "", true, err
		}
		_, hn, err := handleArg(1)
		if err != nil {
			return nil, "", true, err
		}
		data, blen, err := bytesArg(2)
		if err != nil {
			return nil, "", true, err
		}
		code, xc := s.tmp(), s.tmp()
		add("int32_t " + code + " = 0;")
		add("int32_t " + xc + " = xrt_context_check_cancel(" + ctx + ");")
		add("if (" + xc + " == 0) { " + code + " = xdkc_net_write(" + hn + ", " + data + ", " + blen + "); }")
		resultC, _ := s.g.cType(net609XType(name))
		rl, expr, err := s.net609Result(resultC, code+" == 0 && "+xc+" == 0", "(int64_t)("+blen+")", errKind(code, xc))
		add(rl...)
		return lines, expr, true, err

	case k609Close, k609ListenerClose:
		ctx, err := ctxArg()
		if err != nil {
			return nil, "", true, err
		}
		hr, hn, err := handleArg(1)
		if err != nil {
			return nil, "", true, err
		}
		code, xc := s.tmp(), s.tmp()
		add("int32_t " + code + " = 0;")
		add("int32_t " + xc + " = xrt_context_check_cancel(" + ctx + ");")
		add("if (" + xc + " == 0) { " + code + " = xdkc_net_close(" + hn + "); }")
		add("if (" + code + " == 0) { xrt_handle_mark_closed(" + hr + "); }")
		resultC, _ := s.g.cType(net609XType(name))
		rl, expr, err := s.net609Result(resultC, code+" == 0 && "+xc+" == 0", "", errKind(code, xc))
		add(rl...)
		return lines, expr, true, err

	case k609HTTPGet, k609HTTPPost:
		ctx, err := ctxArg()
		if err != nil {
			return nil, "", true, err
		}
		url, err := hostArg(1)
		if err != nil {
			return nil, "", true, err
		}
		native := "xdkc_http_get"
		bodyCall := ""
		if kind == k609HTTPPost {
			native = "xdkc_http_post"
			data, blen, err := bytesArg(2)
			if err != nil {
				return nil, "", true, err
			}
			bodyCall = ", " + data + ", " + blen
		}
		code, xc, b := s.tmp(), s.tmp(), s.tmp()
		add("int32_t " + code + " = 0;")
		add("int32_t " + xc + " = xrt_context_check_cancel(" + ctx + ");")
		add("xrt_bytes_obj *" + b + " = NULL;")
		add("if (" + xc + " == 0) { " + b + " = " + native + "(" + url + "->bytes, " + url + "->len" + bodyCall + ", &" + code + "); }")
		add("rt_release(" + url + ");")
		resultC, _ := s.g.cType(net609XType(name))
		rl, expr, err := s.net609Result(resultC, b+" != NULL", b, errKind(code, xc))
		add(rl...)
		return lines, expr, true, err
	}
	return nil, "", false, nil
}
