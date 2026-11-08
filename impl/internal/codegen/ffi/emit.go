package ffi

import (
	"fmt"
	"sort"
	"strings"
)

// 本文件实现 M4.5b/c 的生成面：
//
//   - EmitCall：生成单个入口的包装函数（自包含 C 函数：编组 → 原生调用 → 解编 + 错误码归一）；
//   - EmitSupport：生成整表支撑代码（布局结构、canary 助手、错误码分类函数、全部包装）；
//   - LinkArgs：把工程清单的 link.libraries 翻译为链接参数（S8 §7）；
//   - BlockingManifest：逐入口阻塞分类清单（S5 §9 / FFI-07 机械核验面）。
//
// 包装 ABI（v1，供 codegen 调用点消费）：
//
//	static int32_t xn_ffi_<entry>(<入参...>[, <retC> *xn_out]);
//	返回值：0 = 成功（xn_out 有效）；非 0 = 原生错误码，
//	        分类经 xn_ffi_<region>_error_kind(code) 取得（未知码 → "Internal"，绝不当 Ok）。
//
// 生成代码只 include xrt.h（S7 §6.1 / INV-FFI-7），不使用内部 rt_* 符号。

// wrapperABI 是包装 ABI 的注释头（写进生成代码，便于审计）。
const wrapperABI = "/* 包装 ABI：返回 0 成功；非 0 为原生错误码（未知码→Internal，S7 §7.2） */\n" +
	"/* S6-09 net Async 运行时原语（E5 rt_std_net.c） */\n" +
	"void *xdkc_socket_connect_async(xrt_context *ctx, const char *host, size_t hlen, int32_t port, int32_t *code);\n" +
	"int64_t xdkc_socket_send_async(xrt_context *ctx, void *sock, const void *buf, size_t n, int32_t *code);\n" +
	"int64_t xdkc_socket_recv_async(xrt_context *ctx, void *sock, void *buf, size_t cap, int32_t *code);\n" +
	"void *xdkc_http_request_async(xrt_context *ctx, const char *method, size_t mlen, const char *host, size_t hlen, int32_t port, const char *path, size_t plen, const void *body, size_t blen, int32_t *code);\n"

// canaryHelpers 是借出缓冲区的 pin/canary 助手（S7 §9 INV-FFI-5）。
const canaryHelpers = `#define XN_FFI_CANARY 16

static uint8_t *xn_ffi_canary_enter(const uint8_t *src, size_t n) {
    uint8_t *buf = (uint8_t *)malloc(n + 2 * XN_FFI_CANARY);
    if (buf == NULL) { xrt_fatal("FFI 编组：内存不足（S7 §9）"); }
    memset(buf, 0xA5, XN_FFI_CANARY);
    memset(buf + XN_FFI_CANARY, 0, n);
    if (src != NULL) { memcpy(buf + XN_FFI_CANARY, src, n); }
    memset(buf + XN_FFI_CANARY + n, 0x5A, XN_FFI_CANARY);
    return buf;
}

static void xn_ffi_canary_leave(uint8_t *buf, uint8_t *dst, size_t n) {
    size_t i;
    for (i = 0; i < XN_FFI_CANARY; i++) {
        if (buf[i] != 0xA5 || buf[XN_FFI_CANARY + n + i] != 0x5A) {
            xrt_fatal("FFI 借出缓冲区越界写（S7 §9 INV-FFI-5）");
        }
    }
    if (dst != NULL) { memcpy(dst, buf + XN_FFI_CANARY, n); }
    free(buf);
}

static int xn_ffi_bool_from_native(uint8_t v) {
    if (v > 1) { xrt_fatal("FFI Bool 返回值非 0/1（S7 §3.2 合同违规）"); }
    return (int)v;
}

`

// scalarC 是 §4.1 标量映射表的 C 侧类型。
func scalarC(name string) (string, bool) {
	switch name {
	case "Int":
		return "int64_t", true
	case "UInt":
		return "uint64_t", true
	case "Int8":
		return "int8_t", true
	case "Int16":
		return "int16_t", true
	case "Int32":
		return "int32_t", true
	case "Int64":
		return "int64_t", true
	case "UInt8":
		return "uint8_t", true
	case "UInt16":
		return "uint16_t", true
	case "UInt32":
		return "uint32_t", true
	case "UInt64":
		return "uint64_t", true
	case "Float", "Float64":
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

// EmitCall 生成入口 entry 的包装函数。
//
// args/dst 为兼容位：包装是逐入口的通用函数（不注入调用点表达式），
// 调用点由 codegen 直接按 xn_ffi_<entry> 符号调用；保留形参以维持冻结签名。
func (r *Registry) EmitCall(entry string, args []ArgExpr, dst TempName) (Snippet, error) {
	e, ok := r.Entry(entry)
	if !ok {
		return Snippet{}, fmt.Errorf("ffi: 未声明的入口 %s", entry)
	}
	_ = args
	_ = dst
	text, err := emitWrapper(e)
	if err != nil {
		return Snippet{}, err
	}
	return Snippet{Text: wrapperABI + text, Includes: []string{"xrt.h"}}, nil
}

// EmitSupport 生成注册表所需的全部支撑代码。
//
// 空注册表返回空片段（无 FFI 空路径零成本）。无法编组的入口不会被静默跳过：
// 其包装以注释占位并记入 Problems，调用方（构建）必须视为失败。
func (r *Registry) EmitSupport() Snippet {
	if r.Empty() {
		return Snippet{}
	}
	var b strings.Builder
	var problems []string
	b.WriteString("/* 绑定层支撑代码（由 .xfb 注册表生成；只包含 xrt.h，S7 §6.1 / INV-FFI-7） */\n")
	b.WriteString("/* S7 §6.2：绑定层可访问弱表；应用层包含 xrt.h 时不定义此宏。 */\n")
	b.WriteString("#define XRT_BINDINGS_LAYER 1\n")
	b.WriteString("#include \"xrt.h\"\n#include <stdint.h>\n#include <stdlib.h>\n#include <string.h>\n\n")
	b.WriteString(wrapperABI)
	b.WriteString("\n")
	b.WriteString(canaryHelpers)
	for _, l := range r.Layouts {
		b.WriteString(emitLayout(l))
		// S7-01：layout(c) 尺寸检查（编译期；与 sema.RegisterExternalLayout 同源计算）。
		if n, err := layoutCSize(l, r.Layouts); err == nil {
			fmt.Fprintf(&b, "_Static_assert(sizeof(xn_layout_%s) == %d, \"layout(c) %s 尺寸不符（S7 §3.3）\");\n\n", l.Name, n, l.Name)
		}
	}
	for _, cb := range r.Callbacks {
		// S7-03：回调声明自动生成 typed trampoline（EmitTrampoline 的唯一调用点）。
		txt, err := r.EmitTrampoline(cb.Name)
		if err != nil {
			problems = append(problems, fmt.Sprintf("回调 %s：%v", cb.Name, err))
			fmt.Fprintf(&b, "/* 回调 %s 未生成：%v */\n", cb.Name, err)
			continue
		}
		b.WriteString(txt.Text)
		b.WriteString("\n")
	}
	for _, rg := range r.regionNames() {
		b.WriteString(emitErrorKind(rg, r.rulesOfRegion(rg)))
	}
	b.WriteString("/* 原生符号声明：编组签名的投影。绑定层自行包含原生头时\n")
	b.WriteString("   定义 XN_FFI_NATIVE_DECLS 关闭本节（S7 §3.2）。 */\n#ifndef XN_FFI_NATIVE_DECLS\n")
	for _, e := range r.Entries {
		proto, err := nativeProto(e)
		if err != nil {
			continue // 已记入 Problems 的入口不再重复声明
		}
		b.WriteString(proto + "\n")
	}
	b.WriteString("#endif\n\n")
	wrapped := map[string]bool{}
	for _, e := range r.Entries {
		text, err := emitWrapper(e)
		if err != nil {
			problems = append(problems, fmt.Sprintf("入口 %s：%v", e.Name, err))
			fmt.Fprintf(&b, "/* 入口 %s 未生成：%v */\n", e.Name, err)
			continue
		}
		b.WriteString(text)
		b.WriteString("\n")
		wrapped[e.Name] = true
	}
	// S7-06/FFI-07：.unaware + @longRunning 的伴生 thunk（调用点经 submit/wait 路由）。
	for _, e := range r.Entries {
		if !e.NeedsCompanion() || !wrapped[e.Name] {
			continue
		}
		b.WriteString(emitCompanion(e))
		b.WriteString("\n")
	}
	return Snippet{Text: b.String(), Includes: []string{"xrt.h"}, Problems: problems}
}

// LinkArgs 把工程清单 link.libraries 翻译为链接参数（S8 §7）。
// 确定性：去重 + 升序（P-10 条件 3，评审回签 2026-11-06）；
// 只认清单声明（不读环境变量）；搜索路径与产物复制属构建侧职责，
// 注入顺序由构建侧保证 `-l/-L` 位于全部目标文件之后。
func LinkArgs(libs []LinkLib) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(libs))
	for _, l := range libs {
		if l.Name == "" || seen[l.Name] {
			continue
		}
		seen[l.Name] = true
		out = append(out, "-l"+l.Name)
	}
	sort.Strings(out)
	return out
}

// EmitTrampoline 为"原生回调 XNull"生成跳板（S3-07 / S7 §5.1/§5.2）。
//
// 生成面（目标 ABI 由绑定层以 xrt_callback_fn 提供，env 生命周期由运行时承担）：
//
//	xn_tramp_<entry>_new(closure, fn)   → xrt_callback_env_new（登记根）
//	xn_tramp_<entry>_destroy(env)       → xrt_callback_env_destroy（注销根，幂等）
//	xn_tramp_<entry>(env, args, n, res) → xrt_callback_env_invoke
//
// 已注销 env 再调用由运行时 xrt_fatal 终止（S7 §5.2）；回调内 panic 走
// 既有 fatal 路径（S7 §5.3），不做任务级隔离。
func (r *Registry) EmitTrampoline(entry string) (Snippet, error) {
	if cb, ok := r.Callback(entry); ok {
		return Snippet{Text: emitCallbackTrampoline(cb), Includes: []string{"xrt.h"}}, nil
	}
	if _, ok := r.Entry(entry); !ok {
		return Snippet{}, fmt.Errorf("ffi: 未声明的入口或回调 %s", entry)
	}
	name := "xn_tramp_" + entry
	var b strings.Builder
	b.WriteString("/* trampoline " + entry + "（S7 §5.1/§5.2：env 生命周期 + 根登记） */\n")
	b.WriteString("static " + name + "_new(void *xn_closure, xrt_callback_fn xn_fn) {\n")
	b.WriteString("    return xrt_callback_env_new(xn_closure, xn_fn);\n")
	b.WriteString("}\n\n")
	b.WriteString("static void " + name + "_destroy(xrt_callback_env *xn_env) {\n")
	b.WriteString("    xrt_callback_env_destroy(xn_env);\n")
	b.WriteString("}\n\n")
	b.WriteString("static int32_t " + name + "(void *xn_env, const void *xn_args, size_t xn_argc, void *xn_result) {\n")
	b.WriteString("    return xrt_callback_env_invoke((xrt_callback_env *)xn_env, xn_args, xn_argc, xn_result);\n")
	b.WriteString("}\n")
	return Snippet{Text: b.String(), Includes: []string{"xrt.h"}}, nil
}

// BlockingRow 是逐入口阻塞分类清单的一行（FFI-07 机械核验面）。
type BlockingRow struct {
	Entry       string
	CName       string
	Region      string
	Class       string
	LongRunning bool
	Companion   string // 长阻塞的专用执行器伴生入口（无则空）
}

// BlockingManifest 输出逐入口阻塞分类清单（按入口名排序，DET-01）。
func (r *Registry) BlockingManifest() []BlockingRow {
	if r == nil {
		return nil
	}
	rows := make([]BlockingRow, 0, len(r.Entries))
	for _, e := range r.Entries {
		row := BlockingRow{
			Entry: e.Name, CName: e.CName, Region: e.Region,
			Class: e.Blocking.String(), LongRunning: e.LongRunning,
		}
		if e.LongRunning && e.Blocking == BlockingUnaware {
			// 只报告注册表实际存在的 companion，不按命名推导（FFI-07）。
			if _, ok := r.Entry("submit" + e.Name); ok {
				row.Companion = "submit" + e.Name
			}
		}
		rows = append(rows, row)
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].Entry < rows[j].Entry })
	return rows
}

func (r *Registry) regionNames() []string {
	seen := map[string]bool{}
	var names []string
	for _, e := range r.Entries {
		if !seen[e.Region] {
			seen[e.Region] = true
			names = append(names, e.Region)
		}
	}
	sort.Strings(names)
	return names
}

func (r *Registry) rulesOfRegion(region string) []ErrRule {
	seen := map[int32]string{}
	for _, e := range r.Entries {
		if e.Region != region {
			continue
		}
		for _, rule := range e.ErrorMap {
			if _, ok := seen[rule.Code]; !ok {
				seen[rule.Code] = rule.Kind
			}
		}
	}
	codes := make([]int32, 0, len(seen))
	for c := range seen {
		codes = append(codes, c)
	}
	sort.Slice(codes, func(i, j int) bool { return codes[i] < codes[j] })
	out := make([]ErrRule, 0, len(codes))
	for _, c := range codes {
		out = append(out, ErrRule{Code: c, Kind: seen[c]})
	}
	return out
}

// emitLayout 生成 layout(c) 结构的 C 侧镜像与尺寸核对函数。
func emitLayout(l Layout) string {
	var b strings.Builder
	fmt.Fprintf(&b, "/* layout(c) 镜像：%s（字段序与 .xfb 声明一致，S7 §3.3） */\n", l.Name)
	fmt.Fprintf(&b, "typedef struct xn_layout_%s {\n", l.Name)
	for _, f := range l.Fields {
		cT, ok := scalarC(f.Type)
		if !ok {
			cT = "xn_layout_" + f.Type // 嵌套结构（校验期已保证已声明且非递归）
		}
		fmt.Fprintf(&b, "    %s %s;\n", cT, f.Name)
	}
	fmt.Fprintf(&b, "} xn_layout_%s;\n\n", l.Name)
	fmt.Fprintf(&b, "static void xn_layout_%s_check(size_t native_size) {\n", l.Name)
	fmt.Fprintf(&b, "    if (native_size != sizeof(xn_layout_%s)) {\n", l.Name)
	fmt.Fprintf(&b, "        xrt_fatal(\"layout(c) 尺寸不一致：%s（S7 §3.3）\");\n", l.Name)
	b.WriteString("    }\n}\n\n")
	return b.String()
}

// errorKindEnum 把绑定层 errorMap 的短名映射到稳定枚举（S4 §3/附录 A）。
func errorKindEnum(kind string) string {
	switch kind {
	// S4 §3.1 规范名
	case "InvalidArgument":
		return "XRT_ERR_INVALID_ARGUMENT"
	case "NotFound":
		return "XRT_ERR_NOT_FOUND"
	case "AlreadyExists":
		return "XRT_ERR_ALREADY_EXISTS"
	case "PermissionDenied":
		return "XRT_ERR_PERMISSION_DENIED"
	case "Io":
		return "XRT_ERR_IO"
	case "Network":
		return "XRT_ERR_NETWORK"
	case "Timeout":
		return "XRT_ERR_TIMEOUT"
	case "Cancelled":
		return "XRT_ERR_CANCELLED"
	case "Busy":
		return "XRT_ERR_BUSY"
	case "Unavailable":
		return "XRT_ERR_UNAVAILABLE"
	case "DataCorrupted":
		return "XRT_ERR_DATA_CORRUPTED"
	case "Unsupported":
		return "XRT_ERR_UNSUPPORTED"
	case "OutOfMemory":
		return "XRT_ERR_OUT_OF_MEMORY"
	case "Internal":
		return "XRT_ERR_INTERNAL"
	// 历史短名别名
	case "Invalid":
		return "XRT_ERR_INVALID_ARGUMENT"
	case "Conflict":
		return "XRT_ERR_ALREADY_EXISTS"
	case "Permission":
		return "XRT_ERR_PERMISSION_DENIED"
	case "Limit":
		return "XRT_ERR_BUSY"
	default:
		return "XRT_ERR_INTERNAL"
	}
}

// emitErrorKind 生成错误码分类函数：已知码 → 分类名 / 稳定枚举，未知码 → Internal。
func emitErrorKind(region string, rules []ErrRule) string {
	var b strings.Builder
	rid := sanitizeIdent(region)
	fmt.Fprintf(&b, "static const char *xn_ffi_%s_error_kind(int32_t code) {\n", rid)
	b.WriteString("    switch (code) {\n")
	for _, r := range rules {
		fmt.Fprintf(&b, "    case %d: return \"%s\";\n", r.Code, r.Kind)
	}
	b.WriteString("    default: return \"Internal\";\n")
	b.WriteString("    }\n}\n\n")
	// S4-04 骨架：稳定的 ErrorKind 枚举映射；Cancelled/Timeout 不降级。
	fmt.Fprintf(&b, "static xrt_error_kind xn_ffi_%s_error_kind_id(int32_t code) {\n", rid)
	b.WriteString("    switch (code) {\n")
	for _, r := range rules {
		fmt.Fprintf(&b, "    case %d: return %s;\n", r.Code, errorKindEnum(r.Kind))
	}
	b.WriteString("    default: return XRT_ERR_INTERNAL;\n")
	b.WriteString("    }\n}\n\n")
	return b.String()
}

// emitWrapper 生成单个入口的包装函数。
func emitWrapper(e Entry) (string, error) {
	codeParam := e.ErrorCode
	codeRet := e.ErrorCodeRet

	var decls, pre, call, postAlways, postOK []string
	// 句柄关闭入口：调用成功后把包装对象标记关闭（不再触达原生 close_fn）
	closeTarget := ""

	for i, p := range e.Params {
		lease := LeaseNone
		if i < len(e.Lease) {
			lease = e.Lease[i]
		}
		if codeParam != "" && p.Name == codeParam {
			pre = append(pre, "int32_t xn_code = 0;")
			call = append(call, "&xn_code")
			continue
		}
		switch p.Type.Kind {
		case KindScalar:
			cT, ok := scalarC(p.Type.Name)
			if !ok {
				return "", fmt.Errorf("标量 %s 无编组映射（S7 §3.2）", p.Type.Name)
			}
			if p.Type.Name == "Bool" {
				decls = append(decls, "int "+p.Name)
				call = append(call, "((uint8_t)("+p.Name+" ? 1 : 0))")
				break
			}
			decls = append(decls, cT+" "+p.Name)
			call = append(call, p.Name)
		case KindString:
			if lease == LeaseTransfer || lease == LeaseClaim {
				return "", fmt.Errorf("String 移交/归还不可编组（S7 §3.4）")
			}
			decls = append(decls, "const char *"+p.Name+"_bytes, size_t "+p.Name+"_len")
			call = append(call, p.Name+"_bytes, "+p.Name+"_len")
		case KindText:
			decls = append(decls, "const char *"+p.Name+"_bytes, size_t "+p.Name+"_len")
			call = append(call, p.Name+"_bytes, "+p.Name+"_len")
		case KindBytes:
			if lease == LeaseBorrow {
				decls = append(decls, "void *"+p.Name+", size_t "+p.Name+"_len")
				pre = append(pre, "uint8_t *xn_buf_"+p.Name+" = xn_ffi_canary_enter((const uint8_t *)"+p.Name+", "+p.Name+"_len);")
				call = append(call, "(void *)(xn_buf_"+p.Name+" + XN_FFI_CANARY), "+p.Name+"_len")
				postAlways = append(postAlways, "xn_ffi_canary_leave(xn_buf_"+p.Name+", (uint8_t *)"+p.Name+", "+p.Name+"_len);")
				break
			}
			// S7-01：transfer/reclaim 为显式所有权转移，不经 canary（S7 §3.4）。
			decls = append(decls, "void *"+p.Name+", size_t "+p.Name+"_len")
			call = append(call, p.Name+", "+p.Name+"_len")
		case KindArray:
			if p.Type.Elem == nil {
				return "", fmt.Errorf("数组元素缺失（S7 §3.5）")
			}
			elem := ""
			if p.Type.Elem.Kind == KindLayout {
				elem = "xn_layout_" + p.Type.Elem.Name
			} else if cT, ok := scalarC(p.Type.Elem.Name); ok {
				elem = cT
			} else {
				return "", fmt.Errorf("数组元素 %s 不可编组（S7 §3.5）", p.Type.Elem.String())
			}
			decls = append(decls, elem+" *"+p.Name+", size_t "+p.Name+"_n")
			call = append(call, p.Name+", "+p.Name+"_n")
		case KindLayout:
			decls = append(decls, "xn_layout_"+p.Type.Name+" *"+p.Name)
			call = append(call, p.Name)
		case KindHandle:
			if lease == LeaseTransfer {
				/* 移交：原生经出参交出新对象，包装层接管 */
				decls = append(decls, "xrt_handle **"+p.Name+"_out")
				pre = append(pre, "void *xn_native_"+p.Name+" = NULL;")
				call = append(call, "&xn_native_"+p.Name)
				postOK = append(postOK, "*"+p.Name+"_out = (xn_native_"+p.Name+" == NULL) ? NULL : xrt_handle_new(xn_native_"+p.Name+", NULL, \""+e.Name+"\");")
				break
			}
			if lease == LeaseClaim {
				/* 归还：所有权移交回原生；包装对象登记关闭（无论返回码）。
				 * 已关闭句柄归还即合同违约（S7 §4.3），fatal。 */
				decls = append(decls, "xrt_handle *"+p.Name)
				pre = append(pre, "void *xn_h_"+p.Name+" = xrt_handle_native("+p.Name+");")
				pre = append(pre, "if (xn_h_"+p.Name+" == NULL) { xrt_fatal(\"FFI 归还句柄已关闭或为空（S7 §4.3）："+e.Name+"\"); }")
				call = append(call, "xn_h_"+p.Name)
				postAlways = append(postAlways, "xrt_handle_mark_closed("+p.Name+");")
				break
			}
			decls = append(decls, "xrt_handle *"+p.Name)
			pre = append(pre, "void *xn_h_"+p.Name+" = xrt_handle_native("+p.Name+");")
			if e.CloseOf != "" && p.Type.Name == e.CloseOf {
				/* 关闭入口：已关闭句柄按幂等成功返回，不再触达原生（S7 §4.3） */
				pre = append(pre, "if (xn_h_"+p.Name+" == NULL) { if (xrt_handle_is_closed("+p.Name+")) { return 0; } xrt_fatal(\"FFI 句柄为空或已失效（S7 §4.3）："+e.Name+"\"); }")
				closeTarget = p.Name
			} else {
				pre = append(pre, "if (xn_h_"+p.Name+" == NULL) { xrt_fatal(\"FFI 句柄已关闭或为空（S7 §4.3）："+e.Name+"\"); }")
			}
			call = append(call, "xn_h_"+p.Name)
		default:
			return "", fmt.Errorf("参数 %s 的类型 %s 不可编组（S7 §3.6）", p.Name, p.Type.String())
		}
	}

	// 返回通道
	retC := ""
	nativeC := "" // 原生返回值的 C 类型（空则与 retC 相同；String 为 const char *）
	hasOut := false
	postOut := ""
	if !codeRet {
		switch e.Ret.Kind {
		case KindVoid:
		case KindScalar:
			cT, ok := scalarC(e.Ret.Name)
			if !ok {
				return "", fmt.Errorf("标量 %s 无编组映射（S7 §3.2）", e.Ret.Name)
			}
			hasOut = true
			retC = cT
			if e.Ret.Name == "Bool" {
				postOut = "*xn_out = (uint8_t)xn_ffi_bool_from_native((uint8_t)xn_v);"
			} else {
				postOut = "*xn_out = (" + cT + ")xn_v;"
			}
		case KindBytes:
			hasOut = true
			retC = "xrt_bytes_obj *"
			nativeC = "xrt_bytes_obj *"
			postOut = "*xn_out = xn_v;"
		case KindString:
			hasOut = true
			retC = "xrt_string *"
			// 原生 String 返回是 C 字符串（借用给包装层立即复制，S7 §3.4/§5.1），
			// 不是 rt/xrt_string：变量类型必须与原生签名一致，否则 C 侧类型不符。
			nativeC = "const char *"
			postOut = "*xn_out = (xn_v == NULL) ? NULL : xrt_string_from_c(xn_v);"
		case KindText:
			hasOut = true
			retC = "xrt_text *"
			nativeC = "const char *"
			postOut = "*xn_out = (xn_v == NULL) ? NULL : xrt_text_from_string(xn_v, strlen(xn_v));"
		case KindHandle:
			hasOut = true
			retC = "xrt_handle *"
			// 原生返回 NULL = 打开失败（S6 §3 第 1 条：不 panic）。
			// 必须回 NULL 而不是包一个 native==NULL 的句柄：否则 File? 的
			// `f == null` 永远为假，失败被静默当成成功。
			postOut = "*xn_out = (xn_v == NULL) ? NULL : xrt_handle_new(xn_v, NULL, \"" + e.Name + "\");"
		default:
			return "", fmt.Errorf("返回类型 %s 的编组未实现（M4.5c）", e.Ret.String())
		}
	}

	// 组装函数
	var b strings.Builder
	fmt.Fprintf(&b, "/* 绑定入口 %s（原生 %s） */\n", e.Name, e.CName)
	sig := "static int32_t xn_ffi_" + e.Name + "("
	parts := append([]string{}, decls...)
	if hasOut {
		parts = append(parts, retC+" *xn_out")
	}
	if len(parts) == 0 {
		sig += "void"
	} else {
		sig += strings.Join(parts, ", ")
	}
	sig += ") {\n"
	b.WriteString(sig)
	for _, line := range pre {
		b.WriteString("    " + line + "\n")
	}
	nativeCall := e.CName + "(" + strings.Join(call, ", ") + ")"
	switch {
	case codeRet:
		if closeTarget != "" {
			/* 关闭失败不等于未关闭（S5 §4.4）：状态照常登记，错误码交调用方 */
			b.WriteString("    int32_t xn_rc = (int32_t)" + nativeCall + ";\n")
			b.WriteString("    xrt_handle_mark_closed(" + closeTarget + ");\n")
			b.WriteString("    return xn_rc;\n")
		} else if len(postAlways) > 0 || len(postOK) > 0 {
			/* 错误码即返回值：出参仅在成功时生效，缓冲区回写与校验始终执行 */
			b.WriteString("    int32_t xn_rc = (int32_t)" + nativeCall + ";\n")
			for _, line := range postAlways {
				b.WriteString("    " + line + "\n")
			}
			if len(postOK) > 0 {
				b.WriteString("    if (xn_rc == 0) {\n")
				for _, line := range postOK {
					b.WriteString("        " + line + "\n")
				}
				b.WriteString("    }\n")
			}
			b.WriteString("    return xn_rc;\n")
		} else {
			b.WriteString("    return (int32_t)" + nativeCall + ";\n")
		}
	default:
		if hasOut {
			if nativeC == "" {
				nativeC = retC
			}
			b.WriteString("    " + nativeC + " xn_v = " + nativeCall + ";\n")
			if codeParam != "" {
				b.WriteString("    if (xn_code != 0) { return xn_code; }\n")
			}
			for _, line := range postAlways {
				b.WriteString("    " + line + "\n")
			}
			for _, line := range postOK {
				b.WriteString("    " + line + "\n")
			}
			if closeTarget != "" {
				b.WriteString("    xrt_handle_mark_closed(" + closeTarget + ");\n")
			}
			b.WriteString("    " + postOut + "\n")
			b.WriteString("    return 0;\n")
		} else {
			b.WriteString("    " + nativeCall + ";\n")
			if codeParam != "" {
				b.WriteString("    if (xn_code != 0) { return xn_code; }\n")
			}
			for _, line := range postAlways {
				b.WriteString("    " + line + "\n")
			}
			for _, line := range postOK {
				b.WriteString("    " + line + "\n")
			}
			if closeTarget != "" {
				b.WriteString("    xrt_handle_mark_closed(" + closeTarget + ");\n")
			}
			b.WriteString("    return 0;\n")
		}
	}
	b.WriteString("}\n")
	return b.String(), nil
}

// sanitizeIdent 把区域名转成可用的 C 标识符片段。
func sanitizeIdent(s string) string {
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

// nativeProto 生成原生符号的 C 声明（编组签名的投影）。
func nativeProto(e Entry) (string, error) {
	var parts []string
	for i, p := range e.Params {
		lease := LeaseNone
		if i < len(e.Lease) {
			lease = e.Lease[i]
		}
		if e.ErrorCode != "" && p.Name == e.ErrorCode {
			parts = append(parts, "int32_t *"+p.Name)
			continue
		}
		switch p.Type.Kind {
		case KindScalar:
			cT, ok := scalarC(p.Type.Name)
			if !ok {
				return "", fmt.Errorf("标量 %s 无映射", p.Type.Name)
			}
			parts = append(parts, cT+" "+p.Name)
		case KindString, KindText:
			parts = append(parts, "const char *"+p.Name+"_bytes", "size_t "+p.Name+"_len")
		case KindBytes:
			parts = append(parts, "void *"+p.Name, "size_t "+p.Name+"_len")
		case KindArray:
			elem := ""
			if p.Type.Elem != nil && p.Type.Elem.Kind == KindLayout {
				elem = "xn_layout_" + p.Type.Elem.Name
			} else if p.Type.Elem != nil {
				if cT, ok := scalarC(p.Type.Elem.Name); ok {
					elem = cT
				}
			}
			if elem == "" {
				return "", fmt.Errorf("数组元素不可编组")
			}
			parts = append(parts, elem+" *"+p.Name, "size_t "+p.Name+"_n")
		case KindLayout:
			parts = append(parts, "xn_layout_"+p.Type.Name+" *"+p.Name)
		case KindHandle:
			if lease == LeaseTransfer || lease == LeaseClaim {
				parts = append(parts, "void **"+p.Name+"_out")
			} else {
				parts = append(parts, "void *"+p.Name)
			}
		default:
			return "", fmt.Errorf("参数类型不可编组")
		}
	}
	ret := "void"
	if e.ErrorCodeRet {
		ret = "int32_t"
	} else {
		switch e.Ret.Kind {
		case KindVoid:
			ret = "void"
		case KindScalar:
			cT, ok := scalarC(e.Ret.Name)
			if !ok {
				return "", fmt.Errorf("返回类型无映射")
			}
			ret = cT
		case KindBytes:
			ret = "xrt_bytes_buf *"
		case KindString, KindText:
			ret = "const char *"
		case KindHandle:
			ret = "void *"
		default:
			return "", fmt.Errorf("返回类型不可编组")
		}
	}
	return ret + " " + e.CName + "(" + strings.Join(parts, ", ") + ");", nil
}

// layoutCSize 按 C 自然对齐计算 layout 尺寸（与 sema S7-01 同规则）。
func layoutCSize(l Layout, all []Layout) (int, error) {
	sizes := map[string]int{}
	aligns := map[string]int{}
	var calc func(name string, seen map[string]bool) (int, int, error)
	calc = func(name string, seen map[string]bool) (int, int, error) {
		if s, ok := sizes[name]; ok {
			return s, aligns[name], nil
		}
		if seen[name] {
			return 0, 0, fmt.Errorf("layout(c) 嵌套环：%s", name)
		}
		seen[name] = true
		var fields []LayoutField
		for _, x := range all {
			if x.Name == name {
				fields = x.Fields
				break
			}
		}
		if fields == nil {
			return 0, 0, fmt.Errorf("未知 layout %s", name)
		}
		off, maxAlign := 0, 1
		for _, f := range fields {
			size, align := 0, 1
			if fs, fa, ok := scalarSizeAlign(f.Type); ok {
				size, align = fs, fa
			} else if fs, fa, err := calc(f.Type, seen); err == nil {
				size, align = fs, fa
			} else {
				return 0, 0, err
			}
			off = alignUp(off, align)
			off += size
			if align > maxAlign {
				maxAlign = align
			}
		}
		total := alignUp(off, maxAlign)
		sizes[name], aligns[name] = total, maxAlign
		return total, maxAlign, nil
	}
	return func() (int, error) {
		n, _, err := calc(l.Name, map[string]bool{})
		return n, err
	}()
}

func scalarSizeAlign(name string) (int, int, bool) {
	switch name {
	case "Int8", "UInt8", "Bool", "Byte", "UByte":
		return 1, 1, true
	case "Int16", "UInt16", "Short", "UShort":
		return 2, 2, true
	case "Int32", "UInt32", "Float32", "Char":
		return 4, 4, true
	case "Int", "UInt", "Int64", "UInt64", "Long", "ULong", "Float", "Float64", "Double":
		return 8, 8, true
	}
	return 0, 0, false
}

func alignUp(n, a int) int {
	if a <= 1 || n%a == 0 {
		return n
	}
	return n + a - n%a
}

// CSize 导出 layout 的 C sizeof（与 sema RegisterExternalLayout 同源）。
func CSize(l Layout, all []Layout) (int, error) { return layoutCSize(l, all) }

// emitCallbackTrampoline 为一条 .xfb 回调声明生成 typed trampoline（S7 §5.1/§5.2/§5.3）。
//
// 形态：
//
//	xn_tramp_<Name>_args            参数打包结构（C ABI 布局）
//	xn_tramp_<Name>_fn              闭包函数签名（captures + args + result）
//	xn_tramp_<Name>_closure         闭包对象（fn + captures，原生持有期间有效）
//	xn_tramp_<Name>_adapt           xrt_callback_fn 适配层（nargs + 类型校验）
//	xn_tramp_<Name>_new(closure)    → xrt_callback_env_new（登记根）
//	xn_tramp_<Name>_destroy(env)    → xrt_callback_env_destroy（注销根，幂等）
//	xn_tramp_<Name>_invoke(env,a,r) → xrt_callback_env_invoke；非 0 状态按 panic 终止
func emitCallbackTrampoline(cb Callback) string {
	name := "xn_tramp_" + cb.Name
	var b strings.Builder
	fmt.Fprintf(&b, "/* trampoline %s（S7 §5.1/§5.2：env 生命周期 + 根登记） */\n", cb.Name)

	// 参数打包结构：args 指向它，闭包按字段取值。
	if len(cb.Params) == 0 {
		fmt.Fprintf(&b, "typedef struct { uint8_t xn_unused; } %s_args;\n", name)
	} else {
		fmt.Fprintf(&b, "typedef struct {\n")
		for i, p := range cb.Params {
			fmt.Fprintf(&b, "    %s p%d;\n", callbackCType(p), i)
		}
		fmt.Fprintf(&b, "} %s_args;\n", name)
	}

	// 闭包签名与对象。
	retC, isVoid := callbackRetCType(cb.Ret)
	if isVoid {
		fmt.Fprintf(&b, "typedef int32_t (*%s_fn)(void *xn_captures, const %s_args *xn_args);\n", name, name)
	} else {
		fmt.Fprintf(&b, "typedef int32_t (*%s_fn)(void *xn_captures, const %s_args *xn_args, %s *xn_result);\n", name, name, retC)
	}
	fmt.Fprintf(&b, "typedef struct { %s_fn fn; void *captures; } %s_closure;\n\n", name, name)

	// 适配层：校验 nargs 后调用闭包；非 0 闭包状态由 invoke 转 fatal（§5.3）。
	fmt.Fprintf(&b, "static int32_t %s_adapt(void *xn_closure, const void *xn_args, size_t xn_argc, void *xn_result) {\n", name)
	b.WriteString("    const " + name + "_closure *xn_c = (const " + name + "_closure *)xn_closure;\n")
	b.WriteString("    const " + name + "_args *xn_a = (const " + name + "_args *)xn_args;\n")
	fmt.Fprintf(&b, "    if (xn_argc != sizeof(%s_args)) {\n        xrt_fatal(\"trampoline %s：参数尺寸不符（S7 §5.1）\");\n    }\n", name, cb.Name)
	fmt.Fprintf(&b, "    if (xn_c == NULL || xn_c->fn == NULL) {\n        xrt_fatal(\"trampoline %s：缺少闭包目标（S7 §5.1）\");\n    }\n", cb.Name)
	if isVoid {
		b.WriteString("    return xn_c->fn(xn_c->captures, xn_a);\n")
	} else {
		b.WriteString("    return xn_c->fn(xn_c->captures, xn_a, (" + retC + " *)xn_result);\n")
	}
	b.WriteString("}\n\n")

	// 创建/销毁/调用。
	fmt.Fprintf(&b, "static xrt_callback_env *%s_new(%s_closure *xn_closure) {\n", name, name)
	b.WriteString("    return xrt_callback_env_new((void *)xn_closure, " + name + "_adapt);\n")
	b.WriteString("}\n\n")
	fmt.Fprintf(&b, "static void %s_destroy(xrt_callback_env *xn_env) {\n", name)
	b.WriteString("    xrt_callback_env_destroy(xn_env);\n")
	b.WriteString("}\n\n")
	if isVoid {
		fmt.Fprintf(&b, "static int32_t %s_invoke(xrt_callback_env *xn_env, const %s_args *xn_args) {\n", name, name)
		b.WriteString("    int32_t xn_st = xrt_callback_env_invoke(xn_env, xn_args, sizeof(*xn_args), NULL);\n")
	} else {
		fmt.Fprintf(&b, "static int32_t %s_invoke(xrt_callback_env *xn_env, const %s_args *xn_args, %s *xn_result) {\n", name, name, retC)
		b.WriteString("    int32_t xn_st = xrt_callback_env_invoke(xn_env, xn_args, sizeof(*xn_args), xn_result);\n")
	}
	fmt.Fprintf(&b, "    if (xn_st != 0) {\n        /* S7 §5.3：回调内 panic 在嵌入侧根边界终止进程，不做任务级隔离。 */\n        xrt_fatal(\"trampoline %s：回调返回错误状态，按 panic 终止（S7 §5.3）\");\n    }\n", cb.Name)
	b.WriteString("    return xn_st;\n")
	b.WriteString("}\n")
	return b.String()
}

// callbackCType 把回调参数的边界类型映射为 C 类型（S7 §3.2/§5.1）。
func callbackCType(t BoundType) string {
	switch t.Kind {
	case KindScalar:
		if c, ok := scalarC(t.Name); ok {
			return c
		}
	case KindLayout:
		return "xn_layout_" + t.Name
	case KindHandle:
		return "xrt_handle *"
	}
	return "void *"
}

// callbackRetCType 返回回调返回值的 C 类型；Void 以 ok=false 表示。
func callbackRetCType(t BoundType) (string, bool) {
	if t.Kind == KindVoid {
		return "", true
	}
	if c, ok := scalarC(t.Name); ok {
		return c, false
	}
	return "int32_t", false
}

// CompanionField 是伴生 thunk 参数结构的一个字段；Parts 表示调用点消费的
// 编组表达式个数（String/Bytes/数组为 2，其余为 1）。
type CompanionField struct {
	Name  string
	CType string
	Parts int
}

// NeedsCompanion 报告入口是否必须经伴生执行器路由（S7 §7.3）。
func (e Entry) NeedsCompanion() bool {
	return e.LongRunning && e.Blocking == BlockingUnaware
}

// CompanionArgFields 返回 thunk 参数结构的字段（与包装形参编组顺序一致）。
func (e Entry) CompanionArgFields() []CompanionField {
	var out []CompanionField
	for i, p := range e.Params {
		if e.ErrorCode != "" && p.Name == e.ErrorCode && !(e.ErrorCodeRet && e.CloseOf != "") {
			continue
		}
		lease := LeaseNone
		if i < len(e.Lease) {
			lease = e.Lease[i]
		}
		name := fmt.Sprintf("p%d", i)
		switch p.Type.Kind {
		case KindScalar:
			c, _ := scalarC(p.Type.Name)
			out = append(out, CompanionField{name, c, 1})
		case KindString, KindText:
			out = append(out, CompanionField{name + "_bytes", "const char *", 1})
			out = append(out, CompanionField{name + "_len", "size_t", 1})
		case KindBytes:
			out = append(out, CompanionField{name + "_data", "void *", 1})
			out = append(out, CompanionField{name + "_len", "size_t", 1})
		case KindLayout:
			out = append(out, CompanionField{name, "xn_layout_" + p.Type.Name + " *", 1})
		case KindArray:
			elemC := "void"
			if p.Type.Elem != nil {
				if c, ok := scalarC(p.Type.Elem.Name); ok {
					elemC = c
				}
			}
			out = append(out, CompanionField{name + "_data", elemC + " *", 1})
			out = append(out, CompanionField{name + "_len", "size_t", 1})
		case KindHandle:
			t := "xrt_handle *"
			if lease == LeaseTransfer {
				// .transfer 句柄 out：包装层接收 xrt_handle **（E4 S7-01 约定）。
				t = "xrt_handle **"
			}
			out = append(out, CompanionField{name, t, 1})
		}
	}
	return out
}

// CompanionOutC 返回 thunk 结果槽的 C 类型；错误码即返回值/close 无结果槽。
func (e Entry) CompanionOutC() (string, bool) {
	if e.ErrorCodeRet {
		return "", false
	}
	switch e.Ret.Kind {
	case KindScalar:
		c, ok := scalarC(e.Ret.Name)
		return c, ok
	case KindString:
		return "rt_string *", true
	case KindText:
		return "xrt_text *", true
	case KindBytes:
		return "xrt_bytes_obj *", true
	case KindHandle:
		return "xrt_handle *", true
	}
	return "", false
}

// CompanionThunkArgExprs 返回 thunk 内调用包装函数的实参表达式。
func (e Entry) CompanionThunkArgExprs() []string {
	var out []string
	for i, p := range e.Params {
		if e.ErrorCode != "" && p.Name == e.ErrorCode && !(e.ErrorCodeRet && e.CloseOf != "") {
			out = append(out, "&a->code")
			continue
		}
		out = append(out, fmt.Sprintf("a->p%d", i))
		// String/Bytes/数组字段拆成两段，第二段在下面补。
		switch p.Type.Kind {
		case KindString, KindText, KindBytes, KindArray:
			// p<i>_bytes/p<i>_data 已由上一行给出，这里补 len 字段。
			out[len(out)-1] = fmt.Sprintf("a->p%d_data", i)
			if p.Type.Kind == KindString || p.Type.Kind == KindText {
				out[len(out)-1] = fmt.Sprintf("a->p%d_bytes", i)
			}
			out = append(out, fmt.Sprintf("a->p%d_len", i))
		}
	}
	if _, ok := e.CompanionOutC(); ok {
		out = append(out, "&a->out")
	}
	return out
}

// emitCompanion 生成伴生 thunk 与参数结构（S7 §7.3：worker 只做原生阻塞调用）。
func emitCompanion(e Entry) string {
	name := "xn_companion_" + e.Name
	var b strings.Builder
	fmt.Fprintf(&b, "/* companion %s（.unaware + @longRunning → xrt_companion_submit/wait） */\n", e.Name)
	fmt.Fprintf(&b, "typedef struct {\n")
	for _, f := range e.CompanionArgFields() {
		fmt.Fprintf(&b, "    %s %s;\n", f.CType, f.Name)
	}
	if e.ErrorCode != "" && !(e.ErrorCodeRet && e.CloseOf != "") {
		b.WriteString("    int32_t code;\n")
	}
	if outC, ok := e.CompanionOutC(); ok {
		fmt.Fprintf(&b, "    %s out;\n", outC)
	}
	b.WriteString("    int32_t rc;\n")
	fmt.Fprintf(&b, "} %s_args;\n\n", name)
	fmt.Fprintf(&b, "static void *%s_thunk(void *xn_p) {\n", name)
	fmt.Fprintf(&b, "    %s_args *a = (%s_args *)xn_p;\n", name, name)
	fmt.Fprintf(&b, "    a->rc = xn_ffi_%s(%s);\n", e.Name, strings.Join(e.CompanionThunkArgExprs(), ", "))
	b.WriteString("    return NULL;\n}\n")
	return b.String()
}
