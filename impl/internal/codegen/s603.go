// s603.go：S6-03 sys plain/Async 双形态（codegen 内建面）。
//
// `.xfb` 无法表达 `Context`（S7 §3.6：未声明句柄不跨界）与出参形态，
// 因此 *Async 入口、Process 句柄族与 procWait 状态出参在 codegen 合成：
//   - 注入 XNull 侧声明（供 sema 名称/类型检查）；
//   - 调用点直接降到 E5 原语（xdkc_*_async / xdkc_proc_*），不走 xn_ffi_ 包装。
//
// 运行时合同（E5 S6-03）：
//   - Async 返回句柄 + Int32 code（0 成功 / 2 取消或 IO 失败）；
//   - 取消不抢占原生 I/O；文件/目录等待取消后仍等待完成并自动关闭 open 结果；
//   - Process close 为 SIGKILL+reap，幂等由 xrt_handle 层保证；
//   - proc_run 取消立即返回、命令继续。
package codegen

import (
	"fmt"

	"xnull.dev/xnull/internal/codegen/ffi"
	"xnull.dev/xnull/internal/xfront"
)

// regHasHandle 判断注册表是否声明了指定句柄类型。
func regHasHandle(reg *ffi.Registry, name string) bool {
	if reg == nil {
		return false
	}
	for _, h := range reg.Handles {
		if h.Name == name {
			return true
		}
	}
	return false
}

type sys603Kind int

const (
	kSys603OpenRead sys603Kind = iota
	kSys603OpenWrite
	kSys603Read
	kSys603Write
	kSys603CloseFile
	kSys603OpenDir
	kSys603ReadDir
	kSys603CloseDir
	kSys603ProcSpawn
	kSys603ProcWait
	kSys603ProcKill
	kSys603ProcClose
	kSys603ProcRun
	kSys603ProcStatus
)

var sys603Kinds = map[string]sys603Kind{
	"fileOpenReadAsync":  kSys603OpenRead,
	"fileOpenWriteAsync": kSys603OpenWrite,
	"fileReadAsync":      kSys603Read,
	"fileWriteAsync":     kSys603Write,
	"fileCloseAsync":     kSys603CloseFile,
	"dirOpenAsync":       kSys603OpenDir,
	"dirReadAsync":       kSys603ReadDir,
	"dirCloseAsync":      kSys603CloseDir,
	"procSpawn":          kSys603ProcSpawn,
	"procWait":           kSys603ProcWait,
	"procKill":           kSys603ProcKill,
	"procClose":          kSys603ProcClose,
	"procRunAsync":       kSys603ProcRun,
	"procStatusAsync":    kSys603ProcStatus,
}

// sys603Type 返回内建入口的 C 类型（供 exprType/print 分流）。
func sys603Type(name string) (string, bool) {
	switch name {
	case "fileOpenReadAsync", "fileOpenWriteAsync", "dirOpenAsync", "procSpawn":
		return "xrt_handle *", true
	case "fileReadAsync":
		return "int64_t", true
	case "fileWriteAsync", "procRunAsync", "procStatusAsync", "procWait", "procKill":
		return "int32_t", true
	case "fileCloseAsync", "dirCloseAsync", "procClose":
		return "int", true
	case "dirReadAsync":
		return "rt_string *", true
	}
	return "", false
}

// sys603XType 是内建入口的 XNull 侧类型（注入声明用）。
func sys603XType(name string) xfront.TypeRef {
	pos := xfront.Pos{Line: 1, Col: 1}
	nt := func(n string) xfront.TypeRef { return &xfront.NamedType{P: pos, Qual: []string{n}} }
	opt := func(t xfront.TypeRef) xfront.TypeRef {
		return &xfront.SuffixedType{P: pos, Base: t, Suffixes: []string{"?"}}
	}
	switch name {
	case "fileOpenReadAsync", "fileOpenWriteAsync":
		return opt(nt("File"))
	case "dirOpenAsync":
		return opt(nt("Dir"))
	case "dirReadAsync":
		return opt(nt("String"))
	case "procSpawn":
		return opt(nt("Process"))
	case "fileReadAsync":
		return nt("Int64")
	case "fileWriteAsync", "procRunAsync", "procStatusAsync", "procWait", "procKill":
		return nt("Int32")
	case "fileCloseAsync", "dirCloseAsync", "procClose":
		return nt("Bool")
	}
	return nil
}

// sys603Decls 构造内建入口的 XNull 声明（顺序固定，确定性）。
func sys603Decls() []*xfront.TopFunc {
	pos := xfront.Pos{Line: 1, Col: 1}
	nt := func(n string) xfront.TypeRef { return &xfront.NamedType{P: pos, Qual: []string{n}} }
	mk := func(name string, params ...*xfront.Param) *xfront.TopFunc {
		fn := &xfront.TopFunc{P: pos, Name: name, Static: true, Public: true, Ret: sys603XType(name)}
		fn.Void = fn.Ret == nil
		fn.Params = params
		fn.Body = &xfront.Block{}
		if !fn.Void {
			// 合成体只为满足 sema 返回路径检查；codegen 不生成该函数。
			fn.Body.Stmts = []xfront.Stmt{&xfront.WhileStmt{Cond: &xfront.BoolLit{V: true}, Body: &xfront.Block{}}}
		}
		return fn
	}
	p := func(name, typ string) *xfront.Param { return &xfront.Param{Name: name, Type: nt(typ)} }
	return []*xfront.TopFunc{
		mk("fileOpenReadAsync", p("ctx", "Context"), p("path", "String")),
		mk("fileOpenWriteAsync", p("ctx", "Context"), p("path", "String")),
		mk("fileReadAsync", p("ctx", "Context"), p("f", "File"), p("buf", "Bytes"), p("code", "Int32")),
		mk("fileWriteAsync", p("ctx", "Context"), p("f", "File"), p("buf", "Bytes")),
		mk("fileCloseAsync", p("ctx", "Context"), p("f", "File")),
		mk("dirOpenAsync", p("ctx", "Context"), p("path", "String")),
		mk("dirReadAsync", p("ctx", "Context"), p("d", "Dir")),
		mk("dirCloseAsync", p("ctx", "Context"), p("d", "Dir")),
		mk("procSpawn", p("cmd", "String")),
		mk("procWait", p("proc", "Process"), p("status", "Int32")),
		mk("procKill", p("proc", "Process"), p("sig", "Int32")),
		mk("procClose", p("proc", "Process")),
		mk("procRunAsync", p("ctx", "Context"), p("cmd", "String")),
		mk("procStatusAsync", p("ctx", "Context"), p("cmd", "String")),
	}
}

// InjectSys603 把内建入口声明追加到编译单元（仅当绑定层已声明 File/Dir 时调用）。
func InjectSys603(u *xfront.CompilationUnit) error {
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
	for _, fn := range sys603Decls() {
		if declared[fn.Name] {
			return fmt.Errorf("codegen：S6-03 内建入口 %s 与编译单元内已有声明重名", fn.Name)
		}
		u.Decls = append(u.Decls, fn)
		declared[fn.Name] = true
	}
	return nil
}

// sys603ArgCtx / HandleBytes / Out 等取参助手：只接受可安全求值的形态。
func (s *scope) sys603ArgCtx(e xfront.Expr) (string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		return s.cRef(n.Name), nil
	case *xfront.Paren:
		return s.sys603ArgCtx(n.X)
	}
	return "", fmt.Errorf("codegen：S6-03 Context 实参仅支持变量（got %T）", e)
}

func (s *scope) sys603ArgHandle(e xfront.Expr) (string, string, error) {
	id, ok := e.(*xfront.IdentExpr)
	if !ok {
		return "", "", fmt.Errorf("codegen：S6-03 句柄实参仅支持变量（got %T）", e)
	}
	r := s.cRef(id.Name)
	return r, "xrt_handle_native(" + r + ")", nil
}

func (s *scope) sys603ArgBytes(e xfront.Expr) (string, string, error) {
	id, ok := e.(*xfront.IdentExpr)
	if !ok {
		return "", "", fmt.Errorf("codegen：S6-03 Bytes 实参仅支持变量（got %T）", e)
	}
	b := s.cRef(id.Name)
	return "xrt_bytes_data(" + b + ")", "xrt_bytes_len(" + b + ")", nil
}

func (s *scope) sys603ArgOut32(e xfront.Expr) (string, error) {
	id, ok := e.(*xfront.IdentExpr)
	if !ok {
		return "", fmt.Errorf("codegen：S6-03 出参仅支持变量（got %T）", e)
	}
	return s.cRef(id.Name), nil
}

// sys603Call 生成内建入口调用（返回前置语句与结果表达式）。
func (s *scope) sys603Call(call *xfront.Call) ([]string, string, bool, error) {
	id, ok := call.Callee.(*xfront.IdentExpr)
	if !ok {
		return nil, "", false, nil
	}
	kind, ok := sys603Kinds[id.Name]
	if !ok {
		return nil, "", false, nil
	}
	name := id.Name
	var lines []string
	var expr string
	add := func(ls ...string) { lines = append(lines, ls...) }
	addPending := func() {
		lines = append(lines, s.pending...)
		s.pending = nil
	}
	arg := func(i int) (xfront.Expr, error) {
		if i >= len(call.Args) {
			return nil, fmt.Errorf("codegen：%s 缺少实参 %d", name, i+1)
		}
		return call.Args[i], nil
	}
	// 句柄打开：code 出参内部化，native NULL → XNull null。
	open := func(native string, pathArg xfront.Expr) error {
		ctxE, err := arg(0)
		if err != nil {
			return err
		}
		ctx, err := s.sys603ArgCtx(ctxE)
		if err != nil {
			return err
		}
		sl, err := s.strExpr(pathArg)
		if err != nil {
			return err
		}
		add(sl...)
		p := lastVar(sl)
		code := s.tmp()
		nv := s.tmp()
		h := s.tmp()
		add("int32_t "+code+" = 0;")
		add("void *"+nv+" = "+native+"("+ctx+", "+p+"->bytes, "+p+"->len, &"+code+");")
		add("rt_release(" + p + ");")
		add("xrt_handle *" + h + " = (" + nv + " == NULL) ? NULL : xrt_handle_new(" + nv + ", NULL, \"" + name + "\");")
		expr = h
		return nil
	}
	switch kind {
	case kSys603OpenRead, kSys603OpenWrite:
		p, err := arg(1)
		if err != nil {
			return nil, "", true, err
		}
		native := "xdkc_file_open_read_async"
		if kind == kSys603OpenWrite {
			native = "xdkc_file_open_write_async"
		}
		if err := open(native, p); err != nil {
			return nil, "", true, err
		}
	case kSys603OpenDir:
		p, err := arg(1)
		if err != nil {
			return nil, "", true, err
		}
		if err := open("xdkc_dir_open_async", p); err != nil {
			return nil, "", true, err
		}
	case kSys603Read:
		ctxE, err := arg(0)
		if err != nil {
			return nil, "", true, err
		}
		ctx, err := s.sys603ArgCtx(ctxE)
		if err != nil {
			return nil, "", true, err
		}
		hE, err := arg(1)
		if err != nil {
			return nil, "", true, err
		}
		h, hn, err := s.sys603ArgHandle(hE)
		if err != nil {
			return nil, "", true, err
		}
		_ = h
		bufE, err := arg(2)
		if err != nil {
			return nil, "", true, err
		}
		data, blen, err := s.sys603ArgBytes(bufE)
		if err != nil {
			return nil, "", true, err
		}
		outE, err := arg(3)
		if err != nil {
			return nil, "", true, err
		}
		codeVar, err := s.sys603ArgOut32(outE)
		if err != nil {
			return nil, "", true, err
		}
		code := s.tmp()
		n := s.tmp()
		add("int32_t " + code + " = 0;")
		add("int64_t " + n + " = xdkc_file_read_async(" + ctx + ", " + hn + ", " + data + ", " + blen + ", &" + code + ");")
		add(codeVar + " = " + code + ";")
		add(fmt.Sprintf(`if (%s != 0) { fprintf(stderr, "fatal: S6-03 %s 错误码 %%d\n", (int)%s); exit(134); }`, code, name, code))
		expr = n
	case kSys603Write:
		ctxE, err := arg(0)
		if err != nil {
			return nil, "", true, err
		}
		ctx, err := s.sys603ArgCtx(ctxE)
		if err != nil {
			return nil, "", true, err
		}
		hE, err := arg(1)
		if err != nil {
			return nil, "", true, err
		}
		_, hn, err := s.sys603ArgHandle(hE)
		if err != nil {
			return nil, "", true, err
		}
		bufE, err := arg(2)
		if err != nil {
			return nil, "", true, err
		}
		data, blen, err := s.sys603ArgBytes(bufE)
		if err != nil {
			return nil, "", true, err
		}
		r := s.tmp()
		add("int32_t " + r + " = xdkc_file_write_async(" + ctx + ", " + hn + ", " + data + ", " + blen + ");")
		expr = r
	case kSys603CloseFile, kSys603CloseDir:
		ctxE, err := arg(0)
		if err != nil {
			return nil, "", true, err
		}
		ctx, err := s.sys603ArgCtx(ctxE)
		if err != nil {
			return nil, "", true, err
		}
		hE, err := arg(1)
		if err != nil {
			return nil, "", true, err
		}
		hr, hn, err := s.sys603ArgHandle(hE)
		if err != nil {
			return nil, "", true, err
		}
		native := "xdkc_file_close_async"
		if kind == kSys603CloseDir {
			native = "xdkc_dir_close_async"
		}
		r := s.tmp()
		add("int32_t " + r + " = " + native + "(" + ctx + ", " + hn + ");")
		add("if (" + r + " == 0) { xrt_handle_mark_closed(" + hr + "); }")
		expr = "(" + r + " == 0)"
	case kSys603ReadDir:
		ctxE, err := arg(0)
		if err != nil {
			return nil, "", true, err
		}
		ctx, err := s.sys603ArgCtx(ctxE)
		if err != nil {
			return nil, "", true, err
		}
		hE, err := arg(1)
		if err != nil {
			return nil, "", true, err
		}
		_, hn, err := s.sys603ArgHandle(hE)
		if err != nil {
			return nil, "", true, err
		}
		code := s.tmp()
		src := s.tmp()
		out := s.tmp()
		add("int32_t " + code + " = 0;")
		add("const char *" + src + " = xdkc_dir_read_async(" + ctx + ", " + hn + ", &" + code + ");")
		add("rt_string *" + out + " = (" + src + " == NULL || " + code + " != 0) ? NULL : rt_string_from_c(" + src + ");")
		expr = out
	case kSys603ProcSpawn:
		p, err := arg(0)
		if err != nil {
			return nil, "", true, err
		}
		sl, err := s.strExpr(p)
		if err != nil {
			return nil, "", true, err
		}
		add(sl...)
		cmd := lastVar(sl)
		code := s.tmp()
		nv := s.tmp()
		h := s.tmp()
		add("int32_t " + code + " = 0;")
		add("void *" + nv + " = xdkc_proc_spawn(" + cmd + "->bytes, " + cmd + "->len, &" + code + ");")
		add("rt_release(" + cmd + ");")
		add("xrt_handle *" + h + " = (" + nv + " == NULL) ? NULL : xrt_handle_new(" + nv + ", NULL, \"procSpawn\");")
		expr = h
	case kSys603ProcWait:
		pE, err := arg(0)
		if err != nil {
			return nil, "", true, err
		}
		_, hn, err := s.sys603ArgHandle(pE)
		if err != nil {
			return nil, "", true, err
		}
		stE, err := arg(1)
		if err != nil {
			return nil, "", true, err
		}
		st, err := s.sys603ArgOut32(stE)
		if err != nil {
			return nil, "", true, err
		}
		r := s.tmp()
		add("int32_t " + r + " = xdkc_proc_wait(" + hn + ", &" + st + ");")
		expr = r
	case kSys603ProcKill:
		pE, err := arg(0)
		if err != nil {
			return nil, "", true, err
		}
		_, hn, err := s.sys603ArgHandle(pE)
		if err != nil {
			return nil, "", true, err
		}
		sigE, err := arg(1)
		if err != nil {
			return nil, "", true, err
		}
		sig, err := s.intExpr(sigE)
		if err != nil {
			return nil, "", true, err
		}
		addPending()
		r := s.tmp()
		add("int32_t " + r + " = xdkc_proc_kill(" + hn + ", (int32_t)(" + sig + "));")
		expr = r
	case kSys603ProcClose:
		pE, err := arg(0)
		if err != nil {
			return nil, "", true, err
		}
		hr, hn, err := s.sys603ArgHandle(pE)
		if err != nil {
			return nil, "", true, err
		}
		r := s.tmp()
		add("int32_t " + r + " = xdkc_proc_close(" + hn + ");")
		add("if (" + r + " == 0) { xrt_handle_mark_closed(" + hr + "); }")
		expr = "(" + r + " == 0)"
	case kSys603ProcRun, kSys603ProcStatus:
		ctxE, err := arg(0)
		if err != nil {
			return nil, "", true, err
		}
		ctx, err := s.sys603ArgCtx(ctxE)
		if err != nil {
			return nil, "", true, err
		}
		cmdE, err := arg(1)
		if err != nil {
			return nil, "", true, err
		}
		sl, err := s.strExpr(cmdE)
		if err != nil {
			return nil, "", true, err
		}
		add(sl...)
		cmd := lastVar(sl)
		r := s.tmp()
		if kind == kSys603ProcRun {
			st := s.tmp()
			add("int32_t " + st + " = 0;")
			add("int32_t " + r + " = xdkc_proc_run_async(" + ctx + ", " + cmd + "->bytes, " + cmd + "->len, &" + st + ");")
		} else {
			add("int32_t " + r + " = xdkc_proc_status_async(" + ctx + ", " + cmd + "->bytes, " + cmd + "->len);")
		}
		add("rt_release(" + cmd + ");")
		expr = r
	}
	return lines, expr, true, nil
}

// sys603IsAsyncName 供语句/表达式分派快速判断。
func sys603IsAsyncName(name string) bool {
	_, ok := sys603Kinds[name]
	return ok
}

// sys603IsStringOut 判断内建入口的返回是否需要表达式语句后释放。
func sys603IsStringOut(name string) bool { return name == "dirReadAsync" }

// sys603SupportText 是生成 C 的原生原型与句柄助手（放在 prelude 之后）。
const sys603SupportText = `/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */
extern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);
extern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);
extern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);
extern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);
extern int32_t xdkc_file_close_async(xrt_context *, void *);
extern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);
extern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);
extern int32_t xdkc_dir_close_async(xrt_context *, void *);
extern void *xdkc_proc_spawn(const char *, size_t, int32_t *);
extern int32_t xdkc_proc_wait(void *, int32_t *);
extern int32_t xdkc_proc_kill(void *, int32_t);
extern int32_t xdkc_proc_close(void *);
extern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);
extern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);
`
