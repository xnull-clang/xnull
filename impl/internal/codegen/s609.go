// s609.go：S6-09 net socket/HTTP 的 Async 语言面（Context 首参）。
//
// `.xfb` 无法表达 Context（S7 §3.6），因此 *Async 入口在 codegen 合成：
//   - 注入 XNull 声明（sema 名称/类型检查）；
//   - 调用点直接降到 E5 运行时原语 xdkc_socket_*_async / xdkc_http_request_async；
//   - 结果构造 Result<T, ErrorKind>，复用 .xfb 的 errorMap 映射函数。
package codegen

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

type net609Kind int

const (
	k609Connect net609Kind = iota
	k609Send
	k609Recv
	k609HTTPRequest
)

var net609Kinds = map[string]net609Kind{
	"socketConnectAsync": k609Connect,
	"socketSendAsync":    k609Send,
	"socketRecvAsync":    k609Recv,
	"httpRequestAsync":   k609HTTPRequest,
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
	case "socketConnectAsync":
		return res("Socket")
	case "socketSendAsync", "socketRecvAsync":
		return res("Int64")
	case "httpRequestAsync":
		return res("HttpResponse")
	}
	return nil
}

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
		mk("socketSendAsync", p("ctx", "Context"), p("sock", "Socket"), p("buf", "Bytes")),
		mk("socketRecvAsync", p("ctx", "Context"), p("sock", "Socket"), p("buf", "Bytes")),
		mk("httpRequestAsync", p("ctx", "Context"), p("method", "String"), p("host", "String"),
			p("port", "Int32"), p("path", "String"), p("body", "Bytes")),
	}
}

// InjectNet609 把 net Async 声明追加到编译单元（net.xfb 已声明 Socket/HttpResponse）。
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

// net609Result 生成 Result<T, ErrorKind> 构造。
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

// net609Call 生成 Async 调用（返回前置语句与 Result 表达式）。
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
	strArg := func(i int) (string, error) {
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
	bytesArg := func(i int) (string, string, error) {
		e, err := arg(i)
		if err != nil {
			return "", "", err
		}
		return s.sys603ArgBytes(e)
	}
	handleArg := func(i int) (string, error) {
		e, err := arg(i)
		if err != nil {
			return "", err
		}
		_, hn, err := s.sys603ArgHandle(e)
		return hn, err
	}
	intArg := func(i int) (string, error) {
		e, err := arg(i)
		if err != nil {
			return "", err
		}
		return s.intExpr(e)
	}
	kindExpr := func(code string) string { return "xn_ffi_xdkc_net_error_kind_id(" + code + ")" }

	switch kind {
	case k609Connect:
		ctx, err := ctxArg()
		if err != nil {
			return nil, "", true, err
		}
		host, err := strArg(1)
		if err != nil {
			return nil, "", true, err
		}
		port, err := intArg(2)
		if err != nil {
			return nil, "", true, err
		}
		code, nv, h := s.tmp(), s.tmp(), s.tmp()
		add("int32_t " + code + " = 0;")
		add("void *" + nv + " = xdkc_socket_connect_async(" + ctx + ", " + host + "->bytes, " + host + "->len, (int32_t)(" + port + "), &" + code + ");")
		add("rt_release(" + host + ");")
		add("xrt_handle *" + h + " = (" + nv + " == NULL) ? NULL : xrt_handle_new(" + nv + ", NULL, \"" + name + "\");")
		resultC, _ := s.g.cType(net609XType(name))
		rl, expr, err := s.net609Result(resultC, h+" != NULL", h, kindExpr(code))
		add(rl...)
		return lines, expr, true, err

	case k609Send, k609Recv:
		ctx, err := ctxArg()
		if err != nil {
			return nil, "", true, err
		}
		hn, err := handleArg(1)
		if err != nil {
			return nil, "", true, err
		}
		data, blen, err := bytesArg(2)
		if err != nil {
			return nil, "", true, err
		}
		native := "xdkc_socket_send_async"
		if kind == k609Recv {
			native = "xdkc_socket_recv_async"
		}
		code, n := s.tmp(), s.tmp()
		add("int32_t " + code + " = 0;")
		add("int64_t " + n + " = " + native + "(" + ctx + ", " + hn + ", " + data + ", " + blen + ", &" + code + ");")
		resultC, _ := s.g.cType(net609XType(name))
		rl, expr, err := s.net609Result(resultC, code+" == 0", n, kindExpr(code))
		add(rl...)
		return lines, expr, true, err

	case k609HTTPRequest:
		ctx, err := ctxArg()
		if err != nil {
			return nil, "", true, err
		}
		method, err := strArg(1)
		if err != nil {
			return nil, "", true, err
		}
		host, err := strArg(2)
		if err != nil {
			return nil, "", true, err
		}
		port, err := intArg(3)
		if err != nil {
			return nil, "", true, err
		}
		path, err := strArg(4)
		if err != nil {
			return nil, "", true, err
		}
		data, blen, err := bytesArg(5)
		if err != nil {
			return nil, "", true, err
		}
		code, nv, h := s.tmp(), s.tmp(), s.tmp()
		add("int32_t " + code + " = 0;")
		add("void *" + nv + " = xdkc_http_request_async(" + ctx + ", " + method + "->bytes, " + method + "->len, " +
			host + "->bytes, " + host + "->len, (int32_t)(" + port + "), " + path + "->bytes, " + path + "->len, " +
			data + ", " + blen + ", &" + code + ");")
		add("rt_release(" + method + "); rt_release(" + host + "); rt_release(" + path + ");")
		add("xrt_handle *" + h + " = (" + nv + " == NULL) ? NULL : xrt_handle_new(" + nv + ", NULL, \"" + name + "\");")
		resultC, _ := s.g.cType(net609XType(name))
		rl, expr, err := s.net609Result(resultC, h+" != NULL", h, kindExpr(code))
		add(rl...)
		return lines, expr, true, err
	}
	return nil, "", false, nil
}
