// s604.go：S6-04 内嵌资源读取（XDK-10）的 codegen 内建发射面。
//
// `.xfb` 无法表达 `Context` 与 `Result<Bytes/Text/List<String>, Error>`，
// 五个 API 由 codegen 合成声明并按 E5 运行时 ABI 直接降级：
//   - 成功=1 / 失败=0 + error_kind（InvalidArgument=0，不能以 0 表示成功）；
//   - resourceSize 的缺失用 Int? 表示（has=0）；
//   - listResources 结果复制为 List<String> 后释放静态表视图。
package codegen

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

const s604SupportText = `/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */
extern int32_t xdkc_resource_exists(const char *, size_t);
extern int32_t xdkc_resource_size(const char *, size_t, int64_t *);
extern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);
extern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);
extern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);
extern void xdkc_list_resources_free(const char **);
`

var s604Names = map[string]bool{
	"resourceExists": true, "resourceSize": true,
	"readResource": true, "readResourceText": true, "listResources": true,
}

func s604Pos() xfront.Pos { return xfront.Pos{Line: 1, Col: 1} }

func s604NT(name string) xfront.TypeRef {
	return &xfront.NamedType{P: s604Pos(), Qual: []string{name}}
}

func s604Result(val string) xfront.TypeRef {
	return &xfront.NamedType{P: s604Pos(), Qual: []string{"Result"},
		Args: []xfront.TypeRef{s604NT(val), s604NT("Error")}}
}

func s604ListString() xfront.TypeRef {
	return &xfront.NamedType{P: s604Pos(), Qual: []string{"List"}, Args: []xfront.TypeRef{s604NT("String")}}
}

// s604Decls 构造五个资源 API 的 XNull 声明（S6 §4.8）。
func s604Decls() []*xfront.TopFunc {
	mk := func(name string, ret xfront.TypeRef, params ...*xfront.Param) *xfront.TopFunc {
		fn := &xfront.TopFunc{P: s604Pos(), Name: name, Static: true, Public: true, Ret: ret}
		fn.Params = params
		fn.Body = &xfront.Block{Stmts: []xfront.Stmt{&xfront.WhileStmt{
			Cond: &xfront.BoolLit{V: true}, Body: &xfront.Block{}}}}
		return fn
	}
	p := func(name, typ string) *xfront.Param {
		return &xfront.Param{Name: name, Type: s604NT(typ)}
	}
	optInt := &xfront.SuffixedType{P: s604Pos(), Base: s604NT("Int"), Suffixes: []string{"?"}}
	return []*xfront.TopFunc{
		mk("resourceExists", s604NT("Bool"), p("path", "String")),
		mk("resourceSize", optInt, p("path", "String")),
		mk("readResource", s604Result("Bytes"), p("ctx", "Context"), p("path", "String")),
		mk("readResourceText", s604Result("Text"), p("ctx", "Context"), p("path", "String")),
		mk("listResources", s604Result("List"), p("ctx", "Context"), p("path", "String")),
	}
}

// InjectS604 追加资源 API 声明（与 S6-03 同时注入，仅 sys 绑定工程）。
func InjectS604(u *xfront.CompilationUnit) error {
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
	for _, fn := range s604Decls() {
		if fn.Name == "listResources" {
			fn.Ret = s604ResultList()
		}
		if declared[fn.Name] {
			return fmt.Errorf("codegen：S6-04 内建入口 %s 与编译单元内已有声明重名", fn.Name)
		}
		u.Decls = append(u.Decls, fn)
		declared[fn.Name] = true
	}
	return nil
}

func s604ResultList() xfront.TypeRef {
	return &xfront.NamedType{P: s604Pos(), Qual: []string{"Result"},
		Args: []xfront.TypeRef{s604ListString(), s604NT("Error")}}
}

// s604PathArg 生成 String 实参（拥有临时 + 释放）。
func (s *scope) s604PathArg(e xfront.Expr) ([]string, string, error) {
	lines, err := s.strExpr(e)
	if err != nil {
		return nil, "", err
	}
	return lines, lastVar(lines), nil
}

// s604Exists / s604Size：无 Result 通道的两项。
func (s *scope) s604Exists(call *xfront.Call) ([]string, string, error) {
	if len(call.Args) != 1 {
		return nil, "", fmt.Errorf("codegen：resourceExists 需要 1 个路径实参")
	}
	lines, p, err := s.s604PathArg(call.Args[0])
	if err != nil {
		return nil, "", err
	}
	t := s.tmp()
	out := append([]string{}, lines...)
	out = append(out, "int32_t "+t+" = xdkc_resource_exists("+p+"->bytes, "+p+"->len);")
	out = append(out, "rt_release("+p+");")
	return out, "(" + t + " != 0)", nil
}

func (s *scope) s604Size(call *xfront.Call) ([]string, string, error) {
	if len(call.Args) != 1 {
		return nil, "", fmt.Errorf("codegen：resourceSize 需要 1 个路径实参")
	}
	lines, p, err := s.s604PathArg(call.Args[0])
	if err != nil {
		return nil, "", err
	}
	ok := s.tmp()
	sz := s.tmp()
	t := s.tmp()
	out := append([]string{}, lines...)
	out = append(out, "int64_t "+sz+" = 0;")
	out = append(out, "int32_t "+ok+" = xdkc_resource_size("+p+"->bytes, "+p+"->len, &"+sz+");")
	out = append(out, "rt_release("+p+");")
	out = append(out, "xn_opt_i "+t+" = ("+ok+" != 0) ? (xn_opt_i){1, "+sz+"} : (xn_opt_i){0, 0};")
	return out, t, nil
}

// s604ResultCall 生成 readResource/readResourceText/listResources 的 Result 值。
func (s *scope) s604ResultCall(name string, call *xfront.Call, resultC string) ([]string, string, error) {
	if len(call.Args) != 2 {
		return nil, "", fmt.Errorf("codegen：%s 需要 (Context, String) 两个实参", name)
	}
	ctx, err := s.sys603ArgCtx(call.Args[0])
	if err != nil {
		return nil, "", err
	}
	lines, p, err := s.s604PathArg(call.Args[1])
	if err != nil {
		return nil, "", err
	}
	ok := s.tmp()
	kind := s.tmp()
	out := append([]string{}, lines...)
	out = append(out, "int32_t "+kind+" = 0;")
	switch name {
	case "readResource":
		v := s.tmp()
		out = append(out, "xrt_bytes_buf *"+v+" = NULL;")
		out = append(out, "int32_t "+ok+" = xdkc_read_resource("+ctx+", "+p+"->bytes, "+p+"->len, &"+v+", &"+kind+");")
		out = append(out, "rt_release("+p+");")
		t := s.tmp()
		out = append(out, resultC+" "+t+" = ("+resultC+"){"+ok+", ("+ok+" != 0) ? "+v+" : NULL, (xrt_error_kind)"+kind+"};")
		return out, t, nil
	case "readResourceText":
		v := s.tmp()
		out = append(out, "xrt_text *"+v+" = NULL;")
		out = append(out, "int32_t "+ok+" = xdkc_read_resource_text("+ctx+", "+p+"->bytes, "+p+"->len, &"+v+", &"+kind+");")
		out = append(out, "rt_release("+p+");")
		t := s.tmp()
		out = append(out, resultC+" "+t+" = ("+resultC+"){"+ok+", ("+ok+" != 0) ? "+v+" : NULL, (xrt_error_kind)"+kind+"};")
		return out, t, nil
	case "listResources":
		items := s.tmp()
		cnt := s.tmp()
		out = append(out, "const char **"+items+" = NULL;")
		out = append(out, "size_t "+cnt+" = 0;")
		out = append(out, "int32_t "+ok+" = xdkc_list_resources("+ctx+", "+p+"->bytes, "+p+"->len, &"+items+", &"+cnt+", &"+kind+");")
		out = append(out, "rt_release("+p+");")
		arr := s.tmp()
		out = append(out, "xn_arr_s *"+arr+" = xn_arr_s_new("+cnt+");")
		out = append(out, "if ("+ok+" != 0) { for (size_t i = 0; i < "+cnt+"; i++) { xn_arr_s_push("+arr+", rt_string_from_c("+items+"[i])); } }")
		out = append(out, "xdkc_list_resources_free("+items+");")
		t := s.tmp()
		out = append(out, resultC+" "+t+" = ("+resultC+"){"+ok+", "+arr+", (xrt_error_kind)"+kind+"};")
		return out, t, nil
	}
	return nil, "", fmt.Errorf("codegen：未知资源入口 %s", name)
}

// s604Type 供 exprType 分派。
func s604Type(name string, g *gen) (string, bool, error) {
	switch name {
	case "resourceExists":
		return "int", true, nil
	case "resourceSize":
		return "xn_opt_i", true, nil
	case "readResource":
		rc, err := g.resultName([]xfront.TypeRef{s604NT("Bytes"), s604NT("Error")})
		return rc, true, err
	case "readResourceText":
		rc, err := g.resultName([]xfront.TypeRef{s604NT("Text"), s604NT("Error")})
		return rc, true, err
	case "listResources":
		rc, err := g.resultName([]xfront.TypeRef{s604ListString(), s604NT("Error")})
		return rc, true, err
	}
	return "", false, nil
}
