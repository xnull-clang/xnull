// ffi_gen.go 是 P-09（M6-B0-01）codegen 侧实现：
// 把 `.xfb` 入口注入为包级可调用声明（供 sema 名称/类型检查），
// 调用点在 C 侧走冻结包装 ABI `xn_ffi_<entry>`（ffi-contract §5.1）。
package codegen

import (
	"fmt"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/codegen/ffi"
	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/sema"
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
			if ffiCodeParamSkipped(e, p) {
				continue // 错误码出参由包装层内部承接，不进入 XNull 签名（S7 §7.1）
			}
			pt, err := ffiParamXType(p)
			if err != nil {
				return fmt.Errorf("FFI 入口 %s：%v", e.Name, err)
			}
			fn.Params = append(fn.Params, &xfront.Param{Name: p.Name, Type: pt})
		}
		if ffiReturnsResult(e) {
			sema.RegisterExternalTypes("ErrorKind")
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

// FFIHandleTypes 返回绑定声明的全部句柄类型名（File/Dir 等）。
// 句柄类型不在源码中声明，由 InjectFFI 注入签名；sema 的签名类型可见性
// 检查需要这些名字（E2 §8.1 严格化后，否则 File/Dir 报 RES-101）。
func FFIHandleTypes(reg *ffi.Registry) []string {
	if reg == nil {
		return nil
	}
	seen := map[string]bool{}
	for _, e := range reg.Entries {
		if e.Ret.Kind == ffi.KindHandle {
			seen[e.Ret.Name] = true
		}
		for _, p := range e.Params {
			if p.Type.Kind == ffi.KindHandle {
				seen[p.Type.Name] = true
			}
		}
	}
	out := make([]string, 0, len(seen))
	for n := range seen {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
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

// ffiSupported 校验入口形态是否在 P-09 本轮覆盖面内（B0-07c：handle/Bytes/@errorCode/Int32/Int64）。
// ffiScalarC 把 S7 标量名映射为 C 类型（S7 §3.2）。
func ffiScalarC(name string) (string, bool) {
	switch name {
	case "Int", "Int64":
		return "int64_t", true
	case "UInt", "UInt64":
		return "uint64_t", true
	case "Int8":
		return "int8_t", true
	case "Int16":
		return "int16_t", true
	case "Int32":
		return "int32_t", true
	case "UInt8":
		return "uint8_t", true
	case "UInt16":
		return "uint16_t", true
	case "UInt32":
		return "uint32_t", true
	case "Float", "Float64", "Double":
		return "double", true
	case "Float32":
		return "float", true
	case "Bool":
		return "uint8_t", true
	case "Char":
		return "uint32_t", true
	}
	return "", false
}

// ffiCodeParamSkipped 报告错误码出参是否从 XNull 签名移除。
// 仅非 close 的 @errorCode 出参形态移除；close 保持 Bool 兼容面。
func ffiCodeParamSkipped(e ffi.Entry, p ffi.Param) bool {
	return e.ErrorCode != "" && p.Name == e.ErrorCode && !(e.ErrorCodeRet && e.CloseOf != "")
}

// ffiReturnsResult 报告入口是否以 Result<T, ErrorKind> 暴露（S7 §7.1 / FFI-01）。
// close（幂等 Bool）与无错误码入口保持既有形态（兼容 .unaware 等调用面）。
func ffiReturnsResult(e ffi.Entry) bool {
	if e.ErrorCodeRet && e.CloseOf != "" {
		return false
	}
	return e.ErrorCode != "" || e.ErrorCodeRet
}

// ffiResultXType 返回 Result<T, ErrorKind> 的 XNull 类型；
// 错误码即返回值（codeParam=.result）时 T = void。
func ffiResultXType(e ffi.Entry) (xfront.TypeRef, error) {
	value := xfront.TypeRef(xfrontNamedType("void"))
	if !e.ErrorCodeRet && e.Ret.Kind != ffi.KindVoid {
		base, isVoid, err := ffiBaseRetXType(e)
		if err != nil {
			return nil, err
		}
		if !isVoid {
			value = base
		}
	}
	return &xfront.NamedType{Qual: []string{"Result"}, Args: []xfront.TypeRef{value, xfrontNamedType("ErrorKind")}}, nil
}

func ffiSupported(e ffi.Entry) error {
	isClose := e.ErrorCodeRet && e.CloseOf != ""
	// 错误码通道（S7 §7.1）：
	//   - 句柄 close（codeParam=.result）以 Bool 暴露（幂等关闭）；
	//   - 其余 codeParam 出参形态（fileRead）与「返回码即错误码」（fileWrite）放行。
	if e.ErrorCodeRet && !isClose && e.Ret.Kind != ffi.KindScalar {
		return fmt.Errorf("codegen：FFI 入口 %s 的 @errorCode(.result) 要求标量返回（S7 §7.1）", e.Name)
	}
	if e.ErrorCode != "" {
		found := false
		for _, p := range e.Params {
			if p.Name == e.ErrorCode {
				found = true
				if p.Type.Kind != ffi.KindScalar || p.Type.Name != "Int32" {
					return fmt.Errorf("codegen：FFI 入口 %s 的错误码出参 %s 必须是 Int32（S7 §7.1）", e.Name, p.Name)
				}
			}
		}
		if !found {
			return fmt.Errorf("codegen：FFI 入口 %s 的 @errorCode 出参 %s 不在形参表（S7 §7.1）", e.Name, e.ErrorCode)
		}
	}
	if !isClose {
		switch e.Ret.Kind {
		case ffi.KindVoid, ffi.KindString, ffi.KindText, ffi.KindHandle:
		case ffi.KindScalar:
			if _, ok := ffiScalarC(e.Ret.Name); !ok {
				return fmt.Errorf("codegen：FFI 入口 %s 的返回标量 %s 未纳入 S7-01", e.Name, e.Ret.Name)
			}
		default:
			return fmt.Errorf("codegen：FFI 入口 %s 的返回类型 %s 未纳入 P-09（仅 void/Int/String/handle）", e.Name, e.Ret.String())
		}
	}
	for _, p := range e.Params {
		switch p.Type.Kind {
		case ffi.KindScalar:
			if _, ok := ffiScalarC(p.Type.Name); !ok {
				return fmt.Errorf("codegen：FFI 入口 %s 的参数 %s 标量 %s 未纳入 S7-01", e.Name, p.Name, p.Type.Name)
			}
		case ffi.KindBytes:
			// S7-01：borrow 走 canary；transfer/reclaim 显式所有权转移。
		case ffi.KindString, ffi.KindText, ffi.KindHandle, ffi.KindLayout, ffi.KindArray:
		default:
			return fmt.Errorf("codegen：FFI 入口 %s 的参数 %s 类型 %s 未纳入 P-09（仅 Int/String/handle/Bytes）", e.Name, p.Name, p.Type.String())
		}
	}
	return nil
}

func ffiParamXType(p ffi.Param) (xfront.TypeRef, error) {
	switch p.Type.Kind {
	case ffi.KindScalar:
		if _, ok := ffiScalarC(p.Type.Name); ok {
			return xfrontNamedType(p.Type.Name), nil
		}
	case ffi.KindString:
		return xfrontStringType(), nil
	case ffi.KindText:
		return xfrontNamedType("Text"), nil
	case ffi.KindBytes:
		return xfrontNamedType("Bytes"), nil
	case ffi.KindLayout:
		return xfrontNamedType(p.Type.Name), nil
	case ffi.KindArray:
		if p.Type.Elem == nil {
			return nil, fmt.Errorf("参数 %s 数组元素缺失", p.Name)
		}
		base, err := ffiParamXType(ffi.Param{Name: p.Name, Type: *p.Type.Elem})
		if err != nil {
			return nil, err
		}
		return &xfront.SuffixedType{Base: base, Suffixes: []string{"[]"}}, nil
	case ffi.KindHandle:
		// 句柄参数可为空（out/.transfer 与关闭失败路径统一以 null 表示）。
		return &xfront.SuffixedType{Base: xfrontNamedType(p.Type.Name), Suffixes: []string{"?"}}, nil
	}
	return nil, fmt.Errorf("参数 %s 类型 %s 未纳入 S7-01", p.Name, p.Type.String())
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
		// S6-03：*Async 打开/创建返回 File?/Dir?/Process?（内建降级，不走 .xfb）。
		switch id.Name {
		case "fileOpenReadAsync", "fileOpenWriteAsync", "dirOpenAsync", "procSpawn":
			lines, expr, _, err := s.sys603Call(n)
			return lines, expr, err
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
	case *xfront.NullLit:
		// File? 用 NULL 哨兵（S6 §3：打开失败返回 null）。
		return nil, "NULL", nil
	case *xfront.Paren:
		return s.handleExpr(n.X)
	}
	return nil, "", fmt.Errorf("codegen：句柄表达式 %T 未支持（B0-07c 范围）", e)
}

// bytesExpr 生成 Bytes 值表达式（B0-07c：Bytes.fromString 起步）。
// 运行时对象（data/len/cap + push/get）由 E5 的 BYTES-RUNTIME 提供；
// 本层只发出调用，不自行实现分配器。
func (s *scope) bytesExpr(e xfront.Expr) ([]string, string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		// 借用转 +1：局部声明/字段赋值统一按所有权接管（S2-E5-01）。
		r := s.cRef(n.Name)
		t := s.tmp()
		return []string{"xrt_bytes_obj *" + t + " = rt_retain(" + r + ");"}, t, nil
	case *xfront.NullLit:
		return nil, "NULL", nil
	case *xfront.Paren:
		return s.bytesExpr(n.X)
	case *xfront.Call:
		mem, ok := n.Callee.(*xfront.Member)
		if !ok {
			return nil, "", fmt.Errorf("codegen：Bytes 构造调用 %T 未支持（B0-07c 范围）", n.Callee)
		}
		recv, ok := mem.X.(*xfront.IdentExpr)
		if !ok || recv.Name != "Bytes" {
			// Bytes 实例的 slice（S3-04）：返回新 Bytes。
			if ok && mem.Name == "slice" {
				if rc, ok2 := s.localCType(recv.Name); ok2 && rc == "xrt_bytes_obj *" {
					a, err := s.intExpr(n.Args[0])
					if err != nil {
						return nil, "", err
					}
					b, err := s.intExpr(n.Args[1])
					if err != nil {
						return nil, "", err
					}
					t := s.tmp()
					return []string{"xrt_bytes_obj *" + t + " = xrt_bytes_slice(" + s.cRef(recv.Name) + ", (size_t)(" + a + "), (size_t)(" + b + "));"}, t, nil
				}
			}
			return nil, "", fmt.Errorf("codegen：Bytes 表达式成员 %s 未支持（B0-07c 范围）", mem.Name)
		}
		switch mem.Name {
		case "fromString":
			sl, err := s.strExpr(n.Args[0])
			if err != nil {
				return nil, "", err
			}
			sv := lastVar(sl)
			t := s.tmp()
			out := append([]string{}, sl...)
			out = append(out, "xrt_bytes_obj *"+t+" = xrt_bytes_from_string("+sv+"->bytes, "+sv+"->len);")
			out = append(out, "rt_release("+sv+");")
			return out, t, nil
		}
		return nil, "", fmt.Errorf("codegen：Bytes.fromString 之外的构造 %s 未支持（B0-07c 范围）", mem.Name)
	}
	return nil, "", fmt.Errorf("codegen：Bytes 表达式 %T 未支持（B0-07c 范围）", e)
}

// ffiRetXType 是入口返回值的 XNull 侧类型（void 返回 nil）。
// 非 close 的 @errorCode 入口统一以 Result<T, ErrorKind> 暴露（FFI-01）；
// 句柄 close（@errorCode(.result)）以 Bool 暴露：true=成功（幂等关闭）。
func ffiRetXType(e ffi.Entry) (xfront.TypeRef, bool, error) {
	if ffiReturnsResult(e) {
		rt, err := ffiResultXType(e)
		return rt, false, err
	}
	return ffiBaseRetXType(e)
}

// ffiBaseRetXType 是未包裹 Result 时的返回类型映射。
func ffiBaseRetXType(e ffi.Entry) (xfront.TypeRef, bool, error) {
	switch e.Ret.Kind {
	case ffi.KindVoid:
		return nil, true, nil
	case ffi.KindScalar:
		// 句柄 close 以 Bool 暴露（幂等关闭，B0-07c）。
		if e.CloseOf != "" {
			return xfrontNamedType("Bool"), false, nil
		}
		// 其余按声明宽度保留类型（Int32/Int64 不再一律折成 Int）。
		return xfrontNamedType(e.Ret.Name), false, nil
	case ffi.KindString:
		return xfrontStringType(), false, nil
	case ffi.KindText:
		return xfrontNamedType("Text"), false, nil
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
	want := len(e.Params)
	for _, p := range e.Params {
		if ffiCodeParamSkipped(e, p) {
			want--
		}
	}
	if len(call.Args) != want {
		return nil, "", fmt.Errorf("codegen：FFI 入口 %s 实参数 %d，声明 %d", e.Name, len(call.Args), want)
	}
	lines := append([]string{}, s.pending...)
	s.pending = nil
	var parts []string
	var post []string
	argIdx := 0
	for i, p := range e.Params {
		// 错误码出参：包装层内部承接（签名不含 code，ffi-contract §5.1），
		// XNull 调用点不再传入，改由 Result.err 交付（S7 §7.1 / FFI-01）。
		if ffiCodeParamSkipped(e, p) {
			continue
		}
		arg := call.Args[argIdx]
		argIdx++
		switch p.Type.Kind {
		case ffi.KindScalar:
			v, err := s.intExpr(arg)
			if err != nil {
				return nil, "", err
			}
			lines = append(lines, s.pending...)
			s.pending = nil
			parts = append(parts, v)
		case ffi.KindBytes:
			lease := ffi.LeaseNone
			if i < len(e.Lease) {
				lease = e.Lease[i]
			}
			id, ok := arg.(*xfront.IdentExpr)
			if !ok {
				return nil, "", fmt.Errorf("codegen：FFI 入口 %s 的 Bytes 实参必须是变量（S7 §4.2），got %T", e.Name, arg)
			}
			b := s.cRef(id.Name)
			parts = append(parts, "xrt_bytes_data("+b+")", "xrt_bytes_len("+b+")")
			_ = lease
		case ffi.KindText:
			lease := ffi.LeaseNone
			if i < len(e.Lease) {
				lease = e.Lease[i]
			}
			if lease == ffi.LeaseTransfer || lease == ffi.LeaseClaim {
				return nil, "", fmt.Errorf("codegen：Text %s 的移交/归还不可编组（S7 §3.4）", p.Name)
			}
			tl, vt, err := s.textExpr(arg)
			if err != nil {
				return nil, "", err
			}
			lines = append(lines, tl...)
			xt := s.tmp()
			lines = append(lines, "rt_string *"+xt+" = xrt_text_to_string("+vt+");")
			parts = append(parts, xt+"->bytes", xt+"->len")
		case ffi.KindLayout:
			ct := "xn_Struct_" + p.Type.Name
			expr, err := s.intExpr(arg)
			if err != nil {
				return nil, "", err
			}
			_ = expr
			lines = append(lines, s.pending...)
			s.pending = nil
			sl, v, err := s.structValue(arg, ct)
			if err != nil {
				return nil, "", err
			}
			lines = append(lines, sl...)
			t := s.tmp()
			lines = append(lines, ct+" "+t+" = "+v+";")
			parts = append(parts, "(xn_layout_"+p.Type.Name+" *)&"+t)
		case ffi.KindArray:
			if p.Type.Elem == nil {
				return nil, "", fmt.Errorf("codegen：FFI 入口 %s 数组元素缺失（S7 §3.5）", e.Name)
			}
			elemC, ok := ffiScalarC(p.Type.Elem.Name)
			if !ok {
				return nil, "", fmt.Errorf("codegen：数组元素 %s 不可编组（S7 §3.5）", p.Type.Elem.String())
			}
			if err := s.g.cs.needArr(elemC); err != nil {
				return nil, "", err
			}
			arrC := arrName(elemC) + " *"
			al, v, err := s.valExpr(arg, arrC)
			if err != nil {
				return nil, "", err
			}
			t := s.tmp()
			lines = append(lines, al...)
			lines = append(lines, arrC+" "+t+" = "+v+";")
			parts = append(parts, t+"->data", "(size_t)"+t+"->len")
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
				return nil, "", fmt.Errorf("codegen：FFI 入口 %s 的 handle 实参必须是变量（S7 §4.2），got %T", e.Name, arg)
			}
			lease := ffi.LeaseNone
			if i < len(e.Lease) {
				lease = e.Lease[i]
			}
			if lease == ffi.LeaseTransfer {
				// .transfer 句柄 out：包装层经 xrt_handle ** 写回。
				parts = append(parts, "&"+s.cRef(id.Name))
			} else {
				parts = append(parts, s.cRef(id.Name))
			}
		default:
			return nil, "", fmt.Errorf("codegen：FFI 入口 %s 参数 %s 类型未纳入 P-09", e.Name, p.Name)
		}
	}
	// 错误码即返回值（B0-07c）：
	//   - 句柄 close：Bool = (rc == 0)；
	//   - 其余（fileWrite）：按声明宽度返回 rc 本身。
	if e.ErrorCodeRet && e.CloseOf != "" {
		t := s.tmp()
		lines = append(lines, "int32_t "+t+" = xn_ffi_"+e.Name+"("+strings.Join(parts, ", ")+");")
		lines = append(lines, post...)
		return lines, "(" + t + " == 0)", nil
	}
	if ffiReturnsResult(e) {
		return s.ffiResultLines(e, lines, parts, post)
	}
	out := ""
	switch e.Ret.Kind {
	case ffi.KindVoid:
	case ffi.KindScalar:
		out = s.tmp()
		cT, ok := ffiScalarC(e.Ret.Name)
		if !ok {
			return nil, "", fmt.Errorf("codegen：FFI 入口 %s 返回标量 %s 未纳入 S7-01", e.Name, e.Ret.Name)
		}
		lines = append(lines, cT+" "+out+" = 0;")
		parts = append(parts, "&"+out)
	case ffi.KindString:
		out = s.tmp()
		lines = append(lines, "rt_string *"+out+" = NULL;")
		parts = append(parts, "&"+out)
	case ffi.KindText:
		out = s.tmp()
		lines = append(lines, "xrt_text *"+out+" = NULL;")
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
	lines = append(lines, post...)
	return lines, out, nil
}

// ffiResultLines 生成 Result<T, ErrorKind> 构造：rc==0 → Ok(value)；
// 非零 → Err(映射分类)，未知码 Internal，Cancelled/Timeout 不降级（S7 §7.1）。
func (s *scope) ffiResultLines(e ffi.Entry, lines, parts, post []string) ([]string, string, error) {
	rt, err := ffiResultXType(e)
	if err != nil {
		return nil, "", err
	}
	resultC, err := s.g.cType(rt)
	if err != nil {
		return nil, "", err
	}
	s.g.results[resultC] = ""
	info, err := s.g.resultInfo(resultC)
	if err != nil {
		return nil, "", err
	}
	var out string
	if !e.ErrorCodeRet {
		// 出参形态：原生返回值即成功值（可能是 void）。
		switch e.Ret.Kind {
		case ffi.KindVoid:
		case ffi.KindScalar:
			out = s.tmp()
			if _, ok := ffiScalarC(e.Ret.Name); !ok {
				return nil, "", fmt.Errorf("codegen：FFI 入口 %s 返回标量 %s 未纳入 S7-01", e.Name, e.Ret.Name)
			}
			parts = append(parts, "&"+out)
		case ffi.KindString:
			out = s.tmp()
			parts = append(parts, "&"+out)
		case ffi.KindText:
			out = s.tmp()
			parts = append(parts, "&"+out)
		case ffi.KindHandle:
			out = s.tmp()
			parts = append(parts, "&"+out)
		default:
			return nil, "", fmt.Errorf("codegen：FFI 入口 %s 返回类型未纳入 P-09", e.Name)
		}
	}
	if !e.ErrorCodeRet {
		switch e.Ret.Kind {
		case ffi.KindVoid:
		case ffi.KindScalar:
			cT, _ := ffiScalarC(e.Ret.Name)
			lines = append(lines, cT+" "+out+" = 0;")
		case ffi.KindString:
			lines = append(lines, "rt_string *"+out+" = NULL;")
		case ffi.KindText:
			lines = append(lines, "xrt_text *"+out+" = NULL;")
		case ffi.KindHandle:
			lines = append(lines, "xrt_handle *"+out+" = NULL;")
		}
	}
	rc := s.tmp()
	lines = append(lines, "int32_t "+rc+" = xn_ffi_"+e.Name+"("+strings.Join(parts, ", ")+");")
	lines = append(lines, post...)
	res := s.tmp()
	lines = append(lines, resultC+" "+res+" = {0};")
	lines = append(lines, res+".ok = ("+rc+" == 0);")
	if out != "" {
		lines = append(lines, res+".v = "+out+";")
	}
	lines = append(lines, fmt.Sprintf(
		"if (%s != 0) { %s.err = (%s)%s; }",
		rc, res, info.errC, ffiErrorKindExpr(e.Region, rc)))
	return lines, res, nil
}

// ffiErrorKindExpr 返回“原生错误码 → xrt_error_kind”的 C 表达式。
// 生成支撑代码提供 xn_ffi_<region>_error_kind_id：已知码 → ErrorKind；
// 未知码 → Internal；Cancelled/Timeout 不降级。E4 的调用点改造用它构造 Result.err。
func ffiErrorKindExpr(region, code string) string {
	return "xn_ffi_" + ffiRegionIdent(region) + "_error_kind_id(" + code + ")"
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
