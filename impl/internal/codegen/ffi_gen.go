// ffi_gen.go 是 P-09（M6-B0-01）codegen 侧实现：
// 把 `.xfb` 入口注入为包级可调用声明（供 sema 名称/类型检查），
// 调用点在 C 侧走冻结包装 ABI `xn_ffi_<entry>`（ffi-contract §5.1）。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/codegen/ffi"
	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xfront"
)

// LoadFFI 读取工程根下全部 `.xfb` 绑定声明（确定性：ffi.Load 已排序）。
func LoadFFI(root string) (*ffi.Registry, []diag.Diagnostic, error) {
	return ffi.Load(root)
}

// InjectFFI 把注册表入口作为包级函数声明追加到编译单元（P-09）。
//
// 仅注入可安全映射到当前语言面的形态；其余跳过并由 UnsupportedFFIEntries
// 在构建侧给出显式提示（调用点会以“未定义标识符”失败，不静默接受）：
//   - 返回：void / Int / String；
//   - 参数：Int（Int/Int64 标量）与 String（.borrow）。
//
// 含错误码通道（@errorCode）的入口需要 Result 映射，本轮未接入。
// 编译单元内已有同名顶层声明时报错（P-09 条件 1）。
func InjectFFI(u *xfront.CompilationUnit, reg *ffi.Registry) error {
	if reg == nil || reg.Empty() {
		return nil
	}
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
	for _, e := range reg.Entries {
		if err := ffiSupported(e); err != nil {
			continue // 未纳入 P-09：跳过注入，构建侧给出提示
		}
		if declared[e.Name] {
			return fmt.Errorf("codegen：FFI 入口 %s 与编译单元内已有顶层声明重名（P-09 条件 1）", e.Name)
		}
		fn := &xfront.TopFunc{P: xfront.Pos{Line: 1, Col: 1}, Name: e.Name, Static: true, Public: true}
		if e.ErrorCodeRet && e.CloseOf != "" {
			// 句柄 close（@errorCode(.result)）以 Bool 暴露：true = 成功（幂等关闭，B0-07c）。
			fn.Ret = xfrontNamedType("Bool")
		} else {
			rt, isVoid, err := ffiRetXType(e)
			if err != nil {
				return fmt.Errorf("%v", err)
			}
			fn.Void = isVoid
			fn.Ret = rt
		}
		for _, p := range e.Params {
			pt, err := ffiParamXType(p)
			if err != nil {
				return fmt.Errorf("FFI 入口 %s：%v", e.Name, err)
			}
			fn.Params = append(fn.Params, &xfront.Param{Name: p.Name, Type: pt})
		}
		// 合成函数体只为满足 sema 的返回路径检查（while(true) 无正常出口）；codegen 不生成该函数。
		fn.Body = &xfront.Block{}
		if !fn.Void {
			fn.Body.Stmts = []xfront.Stmt{&xfront.WhileStmt{
				Cond: &xfront.BoolLit{V: true},
				Body: &xfront.Block{},
			}}
		}
		u.Decls = append(u.Decls, fn)
		declared[e.Name] = true
	}
	return nil
}

// UnsupportedFFIEntries 列出未纳入 P-09 的入口及原因（按注册表顺序，确定性）。
func UnsupportedFFIEntries(reg *ffi.Registry) []string {
	if reg == nil {
		return nil
	}
	var out []string
	for _, e := range reg.Entries {
		if err := ffiSupported(e); err != nil {
			out = append(out, err.Error())
		}
	}
	return out
}

// ffiSupported 校验入口形态是否在 P-09 本轮覆盖面内（B0-07c：含 handle）。
func ffiSupported(e ffi.Entry) error {
	isClose := e.ErrorCodeRet && e.CloseOf != ""
	if e.ErrorCode != "" || e.ErrorCodeRet {
		// 句柄 close 以 Bool 暴露（幂等关闭，B0-07c）；其余错误码通道仍拒绝。
		if !isClose {
			return fmt.Errorf("codegen：FFI 入口 %s 含错误码通道（@errorCode），P-09 本轮未接入 Result 映射（显式拒绝，不静默）", e.Name)
		}
	}
	if !isClose {
		switch e.Ret.Kind {
		case ffi.KindVoid, ffi.KindString, ffi.KindHandle:
		case ffi.KindScalar:
			if e.Ret.Name != "Int" && e.Ret.Name != "Int64" && e.Ret.Name != "Bool" {
				return fmt.Errorf("codegen：FFI 入口 %s 的返回标量 %s 未纳入 P-09（仅 Int/Int64/Bool）", e.Name, e.Ret.Name)
			}
		default:
			return fmt.Errorf("codegen：FFI 入口 %s 的返回类型 %s 未纳入 P-09（仅 void/Int/String/handle）", e.Name, e.Ret.String())
		}
	}
	for _, p := range e.Params {
		switch p.Type.Kind {
		case ffi.KindScalar:
			if p.Type.Name != "Int" && p.Type.Name != "Int64" && p.Type.Name != "Bool" {
				return fmt.Errorf("codegen：FFI 入口 %s 的参数 %s 标量 %s 未纳入 P-09（仅 Int/Int64/Bool）", e.Name, p.Name, p.Type.Name)
			}
		case ffi.KindString, ffi.KindHandle:
		default:
			return fmt.Errorf("codegen：FFI 入口 %s 的参数 %s 类型 %s 未纳入 P-09（仅 Int/String/handle）", e.Name, p.Name, p.Type.String())
		}
	}
	return nil
}

func ffiParamXType(p ffi.Param) (xfront.TypeRef, error) {
	switch p.Type.Kind {
	case ffi.KindScalar:
		if p.Type.Name == "Int" || p.Type.Name == "Int64" {
			return xfrontIntType(), nil
		}
		if p.Type.Name == "Bool" {
			return xfrontNamedType("Bool"), nil
		}
	case ffi.KindString:
		return xfrontStringType(), nil
	case ffi.KindHandle:
		return xfrontNamedType(p.Type.Name), nil
	}
	return nil, fmt.Errorf("参数 %s 类型 %s 未纳入 P-09", p.Name, p.Type.String())
}

func xfrontIntType() xfront.TypeRef {
	return xfrontNamedType("Int")
}

func xfrontStringType() xfront.TypeRef {
	return xfrontNamedType("String")
}

func xfrontNamedType(name string) xfront.TypeRef {
	return &xfront.NamedType{P: xfront.Pos{Line: 1, Col: 1}, Qual: []string{name}}
}

// isHandlePtr 判断 C 类型是否为不透明句柄（B0-07c：xrt_handle 为 ARC 对象）。
func isHandlePtr(c string) bool { return c == "xrt_handle *" }

// handleExpr 生成句柄值：FFI 入口返回（+1）或变量借用（retain）。
func (s *scope) handleExpr(e xfront.Expr) ([]string, string, error) {
	switch n := e.(type) {
	case *xfront.Call:
		id, ok := n.Callee.(*xfront.IdentExpr)
		if !ok {
			return nil, "", fmt.Errorf("codegen：句柄表达式调用 %T 未支持（B0-07c 范围）", n.Callee)
		}
		entry, isFFI := s.ffiEntry(id.Name)
		if !isFFI || entry.Ret.Kind != ffi.KindHandle {
			return nil, "", fmt.Errorf("codegen：%s 不是返回句柄的 FFI 入口（B0-07c 范围）", id.Name)
		}
		return s.ffiCallLines(n, entry)
	case *xfront.IdentExpr:
		r := s.cRef(n.Name)
		t := s.tmp()
		return []string{"xrt_handle *" + t + " = rt_retain(" + r + ");"}, t, nil
	case *xfront.Paren:
		return s.handleExpr(n.X)
	}
	return nil, "", fmt.Errorf("codegen：句柄表达式 %T 未支持（B0-07c 范围）", e)
}

// ffiRetXType 是入口返回值的 XNull 侧类型（void 返回 nil）。
// 句柄 close（@errorCode(.result)）以 Bool 暴露：true=成功（幂等关闭）。
func ffiRetXType(e ffi.Entry) (xfront.TypeRef, bool, error) {
	switch e.Ret.Kind {
	case ffi.KindVoid:
		return nil, true, nil
	case ffi.KindScalar:
		if e.Ret.Name == "Bool" {
			return xfrontNamedType("Bool"), false, nil
		}
		return xfrontIntType(), false, nil
	case ffi.KindString:
		return xfrontStringType(), false, nil
	case ffi.KindHandle:
		return xfrontNamedType(e.Ret.Name), false, nil
	}
	return nil, false, fmt.Errorf("FFI 入口 %s 返回类型 %s 未纳入 P-09", e.Name, e.Ret.String())
}

// ffiEntry 查当前单元的 FFI 入口表。
func (s *scope) ffiEntry(name string) (ffi.Entry, bool) {
	if s.g.ffiEntries == nil {
		return ffi.Entry{}, false
	}
	e, ok := s.g.ffiEntries[name]
	return e, ok
}

// ffiCallLines 生成一次 FFI 调用：先编组实参，再调包装，错误码非零即 fatal（不隐藏）。
// 返回值为结果变量名（void 入口为空串）。
func (s *scope) ffiCallLines(call *xfront.Call, e ffi.Entry) ([]string, string, error) {
	if len(call.Args) != len(e.Params) {
		return nil, "", fmt.Errorf("codegen：FFI 入口 %s 实参数 %d，声明 %d", e.Name, len(call.Args), len(e.Params))
	}
	lines := append([]string{}, s.pending...)
	s.pending = nil
	var parts []string
	var post []string
	for i, p := range e.Params {
		arg := call.Args[i]
		switch p.Type.Kind {
		case ffi.KindScalar:
			v, err := s.intExpr(arg)
			if err != nil {
				return nil, "", err
			}
			lines = append(lines, s.pending...)
			s.pending = nil
			parts = append(parts, v)
		case ffi.KindString:
			// .borrow 借用：只传字节视图，不 retain（ffi-contract §5.2）。
			// 字面量/表达式实参先生成 owned 临时，调用后释放。
			name := ""
			if id, ok := arg.(*xfront.IdentExpr); ok {
				name = s.cRef(id.Name)
			} else {
				sl, err := s.strExpr(arg)
				if err != nil {
					return nil, "", err
				}
				lines = append(lines, sl...)
				name = lastVar(sl)
				post = append(post, "rt_release("+name+");")
			}
			parts = append(parts, name+"->bytes", name+"->len")
		case ffi.KindHandle:
			id, ok := arg.(*xfront.IdentExpr)
			if !ok {
				return nil, "", fmt.Errorf("codegen：FFI 入口 %s 的 handle 实参仅支持变量（B0-07c 范围），got %T", e.Name, arg)
			}
			parts = append(parts, s.cRef(id.Name))
		default:
			return nil, "", fmt.Errorf("codegen：FFI 入口 %s 参数 %s 类型未纳入 P-09", e.Name, p.Name)
		}
	}
	// 错误码即返回值（句柄 close，B0-07c）：Bool = (rc == 0)，不落 out。
	if e.ErrorCodeRet {
		t := s.tmp()
		lines = append(lines, "int32_t "+t+" = xn_ffi_"+e.Name+"("+strings.Join(parts, ", ")+");")
		lines = append(lines, post...)
		return lines, "(" + t + " == 0)", nil
	}
	out := ""
	switch e.Ret.Kind {
	case ffi.KindVoid:
	case ffi.KindScalar:
		out = s.tmp()
		if e.Ret.Name == "Bool" {
			lines = append(lines, "uint8_t "+out+" = 0;")
		} else {
			lines = append(lines, "int64_t "+out+" = 0;")
		}
		parts = append(parts, "&"+out)
	case ffi.KindString:
		out = s.tmp()
		lines = append(lines, "rt_string *"+out+" = NULL;")
		parts = append(parts, "&"+out)
	case ffi.KindHandle:
		out = s.tmp()
		lines = append(lines, "xrt_handle *"+out+" = NULL;")
		parts = append(parts, "&"+out)
	default:
		return nil, "", fmt.Errorf("codegen：FFI 入口 %s 返回类型未纳入 P-09", e.Name)
	}
	rc := s.tmp()
	lines = append(lines, "int32_t "+rc+" = xn_ffi_"+e.Name+"("+strings.Join(parts, ", ")+");")
	// 错误码经包装层归一（未知码 → Internal），非零即终止：不隐藏、不吞错（P-09 条件 2）。
	lines = append(lines, fmt.Sprintf(
		`if (%s != 0) { fprintf(stderr, "fatal: FFI 入口 %s 错误码 %%d（%%s）\n", (int)%s, xn_ffi_%s_error_kind(%s)); exit(134); }`,
		rc, e.Name, rc, ffiRegionIdent(e.Region), rc))
	lines = append(lines, post...)
	return lines, out, nil
}

// ffiRegionIdent 把区域名转成 C 标识符片段（与 ffi 子模块生成规则一致）。
func ffiRegionIdent(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '_':
			b.WriteRune(r)
		default:
			b.WriteRune('_')
		}
	}
	if b.Len() == 0 {
		return "region"
	}
	return b.String()
}
