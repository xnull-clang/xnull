package ffi

import (
	"errors"
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
const wrapperABI = "/* 包装 ABI：返回 0 成功；非 0 为原生错误码（未知码→Internal，S7 §7.2） */\n"

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
	b.WriteString("/* 绑定层支撑代码（由 .xfb 注册表生成；只包含 xrt.h，S7 §6.1 / INV-FFI-7） */\n")
	b.WriteString("#include \"xrt.h\"\n#include <stdint.h>\n#include <stdlib.h>\n#include <string.h>\n\n")
	b.WriteString(wrapperABI)
	b.WriteString("\n")
	b.WriteString(canaryHelpers)
	for _, l := range r.Layouts {
		b.WriteString(emitLayout(l))
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
	var problems []string
	for _, e := range r.Entries {
		text, err := emitWrapper(e)
		if err != nil {
			problems = append(problems, fmt.Sprintf("入口 %s：%v", e.Name, err))
			fmt.Fprintf(&b, "/* 入口 %s 未生成：%v */\n", e.Name, err)
			continue
		}
		b.WriteString(text)
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

// ErrTrampolineReserved 表示回调（trampoline）形态仅做接口预留。
var ErrTrampolineReserved = errors.New("ffi: 回调（trampoline）形态预留中——回调根登记需要调度器的栈 pin 语义（S7 §5.1），随调度器切片落地")

// EmitTrampoline 为"原生回调 XNull"的注册入口生成跳板。
//
// 接口预留（M4.5c 收尾决议，2026-11-06）：最小跳板形态为
// 注册函数（fn 指针 + 用户数据指针）+ 回调进入时重入 XNull 调用，
// 依赖两件尚未落地的事：①调度器的回调期栈 pin/根登记语义；
// ②P-09 之后的 codegen 回调调用点钩子。两者就绪前显式拒绝，
// 不硬做（S7 §5.1 合同优先于实现速度）。
func (r *Registry) EmitTrampoline(entry string) (Snippet, error) {
	if _, ok := r.Entry(entry); !ok {
		return Snippet{}, fmt.Errorf("ffi: 未声明的入口 %s", entry)
	}
	return Snippet{}, ErrTrampolineReserved
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
			row.Companion = "submit" + e.Name
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

// emitErrorKind 生成错误码分类函数：已知码 → 分类名，未知码 → Internal（绝不 Ok）。
func emitErrorKind(region string, rules []ErrRule) string {
	var b strings.Builder
	fmt.Fprintf(&b, "static const char *xn_ffi_%s_error_kind(int32_t code) {\n", sanitizeIdent(region))
	b.WriteString("    switch (code) {\n")
	for _, r := range rules {
		fmt.Fprintf(&b, "    case %d: return \"%s\";\n", r.Code, r.Kind)
	}
	b.WriteString("    default: return \"Internal\";\n")
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
		case KindBytes:
			if lease != LeaseBorrow {
				return "", fmt.Errorf("Bytes %s 的 %s 形态需绑定层分配器合同（显式归属：随资源/调度器切片落地）", p.Name, lease.String())
			}
			decls = append(decls, "void *"+p.Name+", size_t "+p.Name+"_len")
			pre = append(pre, "uint8_t *xn_buf_"+p.Name+" = xn_ffi_canary_enter((const uint8_t *)"+p.Name+", "+p.Name+"_len);")
			call = append(call, "(void *)(xn_buf_"+p.Name+" + XN_FFI_CANARY), "+p.Name+"_len")
			postAlways = append(postAlways, "xn_ffi_canary_leave(xn_buf_"+p.Name+", (uint8_t *)"+p.Name+", "+p.Name+"_len);")
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
				postOK = append(postOK, "*"+p.Name+"_out = xrt_handle_new(xn_native_"+p.Name+", NULL, \""+e.Name+"\");")
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
		case KindString:
			hasOut = true
			retC = "xrt_string *"
			postOut = "*xn_out = (xn_v == NULL) ? NULL : xrt_string_from_c(xn_v);"
		case KindHandle:
			hasOut = true
			retC = "xrt_handle *"
			postOut = "*xn_out = xrt_handle_new(xn_v, NULL, \"" + e.Name + "\");"
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
			b.WriteString("    " + retC + " xn_v = " + nativeCall + ";\n")
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
		case KindString:
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
		case KindString:
			ret = "const char *"
		case KindHandle:
			ret = "void *"
		default:
			return "", fmt.Errorf("返回类型不可编组")
		}
	}
	return ret + " " + e.CName + "(" + strings.Join(parts, ", ") + ");", nil
}
