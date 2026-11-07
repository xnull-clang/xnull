// Package codegen 把语义检查通过的 XNull 程序生成 C 源码（M4.1）。
//
// 消费 impl/runtime 的 ABI（rt.h/rt_gc.h）：Int→int64_t、Bool→int、
// String→rt_string*（单一所有权：字符串求值结果由消耗语句构造并在用后
// 释放，xn_concat/xn_str_* 返回新串）、Result<T,E>→按实例化的值结构体。
// defer/errdefer 以退出点内联清理序列实现（§10.3：块退出/return/try
// 传播执行，errdefer 仅在函数以 Err 返回时执行）；throw/fatal 走
// xn_throw（fprintf+exit(134)，§10.4 不展开栈）。
//
// M4.1 范围：三示例特征面（Int/Bool/String、拼接、print/str、
// Result 成员、defer/errdefer、if/while/return、局部声明/赋值、顶层
// 函数调用）。类声明、容器、闭包等随 M4 后续批次扩展；超出范围的
// 构造返回错误，不静默降级。
package codegen

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/codegen/ffi"
	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// prelude 是生成文件的运行时前置（impl/runtime ABI + 打印/字符串助手）。
const prelude = `/* 由 XNull 编译器生成（M4.1 代码生成）。 */
#include "rt.h"
#include "rt_gc.h"
#include "xrt.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void xn_print_int(int64_t v) { printf("%lld\n", (long long)v); }
static void xn_print_bool(int v) { fputs(v ? "true\n" : "false\n", stdout); }
static void xn_print_str(rt_string *s) { printf("%.*s\n", (int)s->len, s->bytes); }
static void xn_print_null(void) { fputs("null\n", stdout); }

/* 可空值（S1 §2.10）：has=0 表示 null。 */
typedef struct { int has; int64_t v; } xn_opt_i;
typedef struct { int has; int v; } xn_opt_b;
typedef struct { int has; rt_string *v; } xn_opt_s;

static rt_string *xn_str_int(int64_t v) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%lld", (long long)v);
    return rt_string_new(buf, (size_t)n);
}

static rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? "true" : "false"); }

/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */
static rt_string *xn_alloc_str(size_t n);

/* ---- String 成员（S1 §9.2，字节语义）---- */
static int xn_str_eq(rt_string *a, rt_string *b) {
    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;
}

static int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }

static rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {
    if (start < 0) { start = 0; }
    if (n < 0) { n = 0; }
    if ((size_t)start > s->len) { start = (int64_t)s->len; }
    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }
    rt_string *out = xn_alloc_str((size_t)n);
    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }
    return out;
}

static int64_t xn_str_indexof(rt_string *s, rt_string *sub) {
    if (sub->len == 0) { return 0; }
    if (sub->len > s->len) { return -1; }
    for (size_t i = 0; i + sub->len <= s->len; i++) {
        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }
    }
    return -1;
}

static int xn_str_startswith(rt_string *s, rt_string *p) {
    if (p->len > s->len) { return 0; }
    return memcmp(s->bytes, p->bytes, p->len) == 0;
}

static int xn_str_endswith(rt_string *s, rt_string *p) {
    if (p->len > s->len) { return 0; }
    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;
}

static int xn_is_space(uint8_t c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
}

static rt_string *xn_str_trim(rt_string *s) {
    size_t b = 0, e = s->len;
    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }
    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }
    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));
}

static rt_string *xn_str_upper(rt_string *s) {
    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);
    for (size_t i = 0; i < out->len; i++) {
        char c = out->bytes[i];
        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }
    }
    return out;
}

static rt_string *xn_str_lower(rt_string *s) {
    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);
    for (size_t i = 0; i < out->len; i++) {
        char c = out->bytes[i];
        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }
    }
    return out;
}

/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，
 * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */
static rt_string *xn_alloc_str(size_t n) {
    rt_string *s = rt_string_alloc(n);
    s->bytes[0] = 0;
    return s;
}

/* 拼接：接管 a、b 的所有权，返回新串。 */
static rt_string *xn_concat(rt_string *a, rt_string *b) {
    rt_string *out = xn_alloc_str(a->len + b->len);
    memcpy(out->bytes, a->bytes, a->len);
    memcpy(out->bytes + a->len, b->bytes, b->len);
    rt_release(a);
    rt_release(b);
    return out;
}

static void xn_throw(rt_string *msg) {
    fprintf(stderr, "fatal: %.*s\n", (int)msg->len, msg->bytes);
    exit(134);
}

/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */
const char *xdkc_env_get(const char *name, size_t len, size_t *out_len);
void xdkc_diagnose(const char *bytes, size_t len);
void xdkc_exit(int64_t code);
int64_t xdkc_now_mono_ms(void);
int64_t xdkc_now_wall_ms(void);
/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */
void xdkc_dump_tasks(void);
static xn_opt_s xn_env_lookup(rt_string *name) {
    xn_opt_s r;
    size_t len = 0;
    const char *v = xdkc_env_get(name->bytes, name->len, &len);
    if (v == NULL) { r.has = 0; r.v = NULL; }
    else { r.has = 1; r.v = rt_string_new(v, len); }
    return r;
}

/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */
static void xn_report_write(const char *p, size_t n) {
    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }
}
static void xn_report_line(int64_t kind, rt_string *desc) {
    const char *name = xrt_error_kind_name((xrt_error_kind)kind);
    char head[96];
    size_t off = 0;
    head[off++] = '[';
    size_t nl = strlen(name);
    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }
    memcpy(head + off, name, nl);
    off += nl;
    head[off++] = ']';
    head[off++] = ' ';
    xn_report_write(head, off);
    if (desc != NULL) {
        char chunk[256];
        size_t i = 0;
        while (i < desc->len) {
            size_t n = desc->len - i;
            if (n > sizeof(chunk)) { n = sizeof(chunk); }
            for (size_t k = 0; k < n; k++) {
                char c = desc->bytes[i + k];
                chunk[k] = (c == '\n' || c == '\r') ? ' ' : c;
            }
            xn_report_write(chunk, n);
            i += n;
        }
    }
    xn_report_write("\n", 1);
}

/* ---- GC 根帧与安全点（S3-02）------------------------------------------
 * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局
 * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。
 * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；
 * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。
 * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。
 * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；
 * 运行时若暴露阈值 API，这里改为薄调用）。 */
typedef struct { void *obj; size_t count; } xn_root_ref;
static xn_root_ref *xn_root_refs = NULL;
static size_t xn_root_ref_n = 0;
static size_t xn_root_ref_cap = 0;
static void  **xn_root_track = NULL;
static size_t  xn_root_depth = 0;
static size_t  xn_root_cap   = 0;

static void xn_root_hold(void *obj) {
    if (obj == NULL) { return; }
    for (size_t i = 0; i < xn_root_ref_n; i++) {
        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }
    }
    if (xn_root_ref_n == xn_root_ref_cap) {
        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;
        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));
        if (xn_root_refs == NULL) { abort(); }
    }
    xn_root_refs[xn_root_ref_n].obj = obj;
    xn_root_refs[xn_root_ref_n].count = 1;
    xn_root_ref_n++;
    rt_gc_root_add(obj);
}
static void xn_root_release(void *obj) {
    if (obj == NULL) { return; }
    for (size_t i = 0; i < xn_root_ref_n; i++) {
        if (xn_root_refs[i].obj != obj) { continue; }
        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }
        rt_gc_root_remove(obj);
        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];
        return;
    }
}
static size_t xn_root_mark(void) { return xn_root_depth; }
static void xn_root_add(void *obj) {
    if (obj == NULL) { return; }
    xn_root_hold(obj);
    if (xn_root_depth == xn_root_cap) {
        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;
        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));
        if (xn_root_track == NULL) { abort(); }
    }
    xn_root_track[xn_root_depth++] = obj;
}
static void xn_root_restore(size_t mark) {
    while (xn_root_depth > mark) {
        xn_root_release(xn_root_track[--xn_root_depth]);
    }
}

static size_t xn_gc_alloc_pending = 0;
#define XN_GC_SAFEPOINT_THRESHOLD 1024
static void *xn_gc_new(const rt_type *type) {
    xn_gc_alloc_pending++;
    return rt_gc_new(type);
}
static void xn_gc_safepoint(void) {
    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {
        xn_gc_alloc_pending = 0;
        rt_gc_collect();
    }
}

/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */
typedef struct {
    rt_header hdr;
    const char *typeName;
    int64_t i;
    rt_string *s;
    void *o;
} xn_Any;
static void xn_Any_scan(void *p, void (*visit)(void *)) {
    xn_Any *b = (xn_Any *)p;
    if (b->s) { visit(b->s); }
    if (b->o) { visit(b->o); }
}
static const rt_type RT_TYPE_XN_ANY = { "Any", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };
static xn_Any *xn_box_int(int64_t v) {
    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);
    b->typeName = "Int"; b->i = v;
    return b;
}
static xn_Any *xn_box_int32(int32_t v) {
    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);
    b->typeName = "Int32"; b->i = (int64_t)v;
    return b;
}
static xn_Any *xn_box_bool(int v) {
    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);
    b->typeName = "Bool"; b->i = v ? 1 : 0;
    return b;
}
static xn_Any *xn_box_str(rt_string *s) {
    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);
    b->typeName = "String";
    if (s != NULL) { rt_retain(s); }
    b->s = s;
    return b;
}
/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，
 * GC 载荷不计数（由 GC 管理）。 */
static xn_Any *xn_box_obj(void *o) {
    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);
    if (o != NULL) {
        b->typeName = ((rt_object *)o)->hdr.type->name;
        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }
        b->o = o;
    }
    return b;
}
static int xn_any_is(xn_Any *b, const char *typeName) {
    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;
}
/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */
static int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {
    if (xn_any_is(b, typeName)) { return b->i; }
    if (!nullSafe) { rt_fatal("Any 拆箱类型不匹配（S3 §3）"); }
    return 0;
}
static rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {
    if (xn_any_is(b, typeName)) {
        if (b->s != NULL) { rt_retain(b->s); }
        return b->s;
    }
    if (!nullSafe) { rt_fatal("Any 拆箱类型不匹配（S3 §3）"); }
    return NULL;
}
static void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {
    if (xn_any_is(b, typeName)) {
        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }
        return b->o;
    }
    if (!nullSafe) { rt_fatal("Any 拆箱类型不匹配（S3 §3）"); }
    return NULL;
}

/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */
static void xn_fatal_div(void) {
    fprintf(stderr, "xnull: fatal: 除零\n");
    fflush(stderr);
    exit(134);
}
static int64_t xn_div_i64(int64_t a, int64_t b) {
    if (b == 0) { xn_fatal_div(); }
    return a / b;
}
static int64_t xn_mod_i64(int64_t a, int64_t b) {
    if (b == 0) { xn_fatal_div(); }
    return a % b;
}
`

// EmitC 生成完整 C 翻译单元文本（无 FFI 路径）。
func EmitC(u *xfront.CompilationUnit) (string, error) {
	return EmitCWithFFI(u, nil)
}

// EmitCWithFFI 生成完整 C 翻译单元文本，并把 `.xfb` 注册表的入口包装
// （`xn_ffi_<entry>`）插入单元级支撑代码（P-09；空注册表零成本）。
func EmitCWithFFI(u *xfront.CompilationUnit, reg *ffi.Registry) (string, error) {
	return EmitCWithStrategies(u, reg, nil)
}

// EmitCWithBuildOptions 是构建入口（S3-08）：在策略之上叠加 §23 选项
// （MemPolicy 强制 arc/gc、Stats 打开分配统计）。
func EmitCWithBuildOptions(u *xfront.CompilationUnit, reg *ffi.Registry, strategies []sema.Strategy, opts Options) (string, error) {
	switch opts.MemPolicy {
	case "", "auto":
	case "arc", "gc":
		forced := make([]sema.Strategy, len(strategies))
		copy(forced, strategies)
		for i := range forced {
			if forced[i].Kind == "class" {
				forced[i].Policy = opts.MemPolicy
				// --mem=arc/gc 强制全部堆分配，禁用栈优化（S3-03）。
				forced[i].Escape = "n/a"
			}
		}
		strategies = forced
	default:
		return "", fmt.Errorf("codegen：--mem 只接受 auto/arc/gc，got %q", opts.MemPolicy)
	}
	return emitC(u, reg, strategies, opts.Stats)
}

// EmitCWithStrategies 是 EmitCWithFFI 的带策略入口（BND-10）：
// strategies 来自 sema.ComputeStrategies，决定类的分配种类（arc/gc）。
// strategies 为空时全部按 ARC（与历史行为一致）。
func EmitCWithStrategies(u *xfront.CompilationUnit, reg *ffi.Registry, strategies []sema.Strategy) (string, error) {
	return emitC(u, reg, strategies, false)
}

func emitC(u *xfront.CompilationUnit, reg *ffi.Registry, strategies []sema.Strategy, stats bool) (string, error) {
	policy := map[string]string{}
	stack := map[string]bool{}
	for _, st := range strategies {
		if st.Kind == "class" && st.Policy != "" {
			policy[st.Decl] = st.Policy
		}
		// S3-03：Escape=none 的类在局部构造点可栈分配（后续用法安全性再校验）。
		if st.Kind == "class" && st.Escape == "none" {
			stack[st.Decl] = true
		}
	}
	g := &gen{results: map[string]string{}, resultArgs: map[string][]xfront.TypeRef{}, cs: newContainers(), fnRet: map[string]string{}, classes: map[string]*classInfo{},
		classDecls: map[string]*xfront.ClassDecl{},
		globals:    map[string]string{}, ffi: reg, ffiEntries: map[string]ffi.Entry{}, handleNames: map[string]bool{},
		generics: map[string]*xfront.TopFunc{}, insts: map[string]*instInfo{},
		fnNames: map[*xfront.TopFunc]string{}, mainOverloads: map[int]string{},
		tuples: map[string]*tupleInfo{}, protocols: map[string]*protoInfo{},
		protoSlotByKey: map[string]int{}, enums: map[string]*enumInfo{}, structs: map[string]*classInfo{},
		classInsts: map[string]*classInfo{}, singletons: map[string]*classInfo{},
		factories: map[string]*factoryInfo{}, policy: policy, stack: stack, stats: stats}
	g.resultArgs = map[string][]xfront.TypeRef{}
	g.syncElems = map[string]string{}
	if reg != nil {
		for _, e := range reg.Entries {
			g.ffiEntries[e.Name] = e
		}
		for _, h := range reg.Handles {
			g.handleNames[h.Name] = true
		}
	}
	// S6-03：Process 是内建句柄族（.xfb 无法声明其 Context/出参入口）。
	g.handleNames["Process"] = true
	g.collectGenerics(u)
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			if _, isFFI := g.ffiEntries[fn.Name]; isFFI {
				continue
			}
			if err := g.collectResult(fn); err != nil {
				return "", err
			}
		}
	}
	// 类名预登记（前向引用）+ 字段/方法签名收集
	g.registerClassNames(u)
	if err := g.collectEnums(u); err != nil {
		return "", err
	}
	// S4-02：xdk.errors 的 ErrorKind 为内建简单枚举（§3.1 14 项，值对齐 XRT_ERR_*）。
	if importsXDK(u, "errors") {
		g.ensureErrorKind()
	}
	if err := g.collectStructs(u); err != nil {
		return "", err
	}
	if err := g.collectProtocols(u); err != nil {
		return "", err
	}
	for _, d := range u.Decls {
		if c, ok := d.(*xfront.ClassDecl); ok {
			if len(c.TypePars) > 0 {
				continue // 泛型类按实例收集（BND-12）
			}
			if err := g.collectClass(c); err != nil {
				return "", err
			}
		}
	}
	if err := g.collectSingletons(u); err != nil {
		return "", err
	}
	if err := g.collectFactories(u); err != nil {
		return "", err
	}
	if err := g.collectAllResults(u); err != nil {
		return "", err
	}
	if err := g.collectExtensions(u); err != nil {
		return "", err
	}
	// 协议 vtable 槽对齐（S2 §5.7）：子类实现协议时，祖先也必须保留同一 vtable
	// 指针槽，否则父类字段偏移与子类布局不一致（多级继承回归）。
	for _, ci := range g.classes {
		for b := ci.base; ci.vptr && b != nil; b = b.base {
			b.vptr = true
		}
	}
	// 顶层字段收集（§4.3/§11.3 初始化顺序；ENTRY-01 范围：Int/Bool/String）
	for _, d := range u.Decls {
		if f, ok := d.(*xfront.TopField); ok {
			ct, err := g.cType(f.Type)
			if err != nil {
				return "", err
			}
			switch ct {
			case "int64_t", "int", "rt_string *":
			default:
				// S3-02：顶层字段允许 GC 引用（类/Any/容器/数据枚举/协议），
				// 初始化后登记为全局根。
				if !g.isTupleC(ct) && !g.isGCRootC(ct) {
					return "", fmt.Errorf("codegen：顶层字段 %s 的类型 %s 暂未支持（ENTRY-01 范围：Int/Bool/String/元组/GC 引用）", f.Name, ct)
				}
			}
			if _, dup := g.globals[f.Name]; dup {
				return "", fmt.Errorf("codegen：顶层字段 %s 重复声明（§4.2）", f.Name)
			}
			g.globals[f.Name] = ct
			g.globalList = append(g.globalList, f)
		}
	}
	// 入口选择（§11.2/§11.4）：匹配签名的 main 才是入口；其余 main 重载是普通函数。
	// 必须先于签名表/函数生成：非入口 main 需要独立 C 名，否则 C 侧撞名。
	entry, err := entryDeclOf(u)
	if err != nil {
		return "", err
	}
	g.assignMainNames(u, entry)
	g.entry = entry
	// main 的签名表项固定取入口声明：声明顺序不影响类型推断（§11.2）。
	if entry != nil {
		rc, err := g.cType(entry.fn.Ret)
		if err != nil {
			return "", err
		}
		if entry.fn.Void {
			rc = "void"
		}
		g.fnRet["main"] = rc
	}
	// 函数签名表（类型推断消费）。泛型声明不进表：调用点一律走实例名，
	// 同名普通函数与泛型函数构成合法重载（§8.2），C 侧靠实例后缀区分。
	seenFn := map[string]bool{}
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			if len(fn.TypePars) > 0 {
				continue
			}
			if fn.Name == "main" {
				// 入口唯一性由 entryDeclOf 判定；其余 main 重载走独立 C 名，
				// 不参与普通函数的同名冲突检测（与声明顺序无关）。
				continue
			}
			if e, isFFI := g.ffiEntries[fn.Name]; isFFI {
				rc := "void"
				switch {
				case e.ErrorCodeRet:
					rc = "int"
				case e.Ret.Kind == ffi.KindScalar && e.Ret.Name == "Bool":
					rc = "int"
				case e.Ret.Kind == ffi.KindScalar:
					rc = "int64_t"
				case e.Ret.Kind == ffi.KindString:
					rc = "rt_string *"
				case e.Ret.Kind == ffi.KindHandle:
					rc = "xrt_handle *"
				}
				g.fnRet[fn.Name] = rc
				seenFn[fn.Name] = true
				continue
			}
			if seenFn[fn.Name] {
				return "", fmt.Errorf("codegen：顶层函数 `%s` 重载未支持（§4.4 重载属 M4.5+；当前同名函数在 C 侧冲突）", fn.Name)
			}
			seenFn[fn.Name] = true
			rc, err := g.cType(fn.Ret)
			if err != nil {
				return "", err
			}
			if fn.Void {
				rc = "void"
			}
			g.fnRet[fn.Name] = rc
		}
	}
	// 第一遍：试生成以收集 Result/容器实例化（产物丢弃）
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			if _, isFFI := g.ffiEntries[n.Name]; isFFI {
				continue
			}
			if len(n.TypePars) > 0 {
				continue // 泛型声明按实例生成，见 expandInstances
			}
			if _, err := g.genFuncNamed(n, g.fnCName(n)); err != nil {
				return "", err
			}
		case *xfront.ClassDecl:
			if len(n.TypePars) > 0 {
				continue // 泛型类实例在 emitClassInstance 中试生成（BND-12）
			}
			ci := g.classes[n.Name]
			for _, m := range ci.methods {
				if _, err := g.genMethod(ci, m); err != nil {
					return "", err
				}
			}
		case *xfront.TopField:
			// 顶层字段初值在第一遍不需要试生成（无容器/Result 实例化登记）。
		case *xfront.ProtocolDecl:
			// 协议只声明方法签名；布局槽由实现类的 vtable 指针承载（S2 §5.7）。
		case *xfront.EnumDecl:
			// 枚举由 collectEnums/emitEnumTypes 发射；简单枚举无函数体。
		case *xfront.StructDecl:
			// 结构体由 collectStructs/emitStructTypes 发射。
		case *xfront.SingletonDecl:
			// 单例由 collectSingletons/emitSingletons 发射。
		case *xfront.FactoryDecl:
			// 工厂方法由 collectFactories/emitFactories 发射。
		case *xfront.ExtensionDecl:
			// 扩展方法由 collectExtensions/emitExtensions 发射。
		case *xfront.AnnotationDecl:
			// 注解是编译期元数据：不产生运行期对象/布局/代码（S2 §12）。
		default:
			return "", fmt.Errorf("codegen：顶层声明 %T 未支持（M4.1 范围：顶层函数/类）", d)
		}
	}
	// 单态化展开：试生成新发现的实例，直到不再增长（§8.3，含无限展开上限）
	if err := g.expandInstances(); err != nil {
		return "", err
	}
	g.tmp = 0
	g.taskID = 0
	g.taskSupport = nil
	g.taskSupportAdded = false
	g.lateProtos = nil
	g.lateFns = nil
	var fns []string
	// 第二遍：正式生成顶层函数（普通函数 + 单态化实例）
	for _, d := range u.Decls {
		fn, ok := d.(*xfront.TopFunc)
		if !ok || len(fn.TypePars) > 0 {
			continue
		}
		if _, isFFI := g.ffiEntries[fn.Name]; isFFI {
			continue
		}
		c, err := g.genFuncNamed(fn, g.fnCName(fn))
		if err != nil {
			return "", err
		}
		fns = append(fns, c)
	}
	for _, cn := range g.instNames() {
		c, err := g.genInstance(g.insts[cn])
		if err != nil {
			return "", err
		}
		fns = append(fns, c)
	}
	var b strings.Builder
	b.WriteString(prelude)
	b.WriteString(sys603SupportText)
	b.WriteString(s604SupportText)
	// 元组结构体（S1 §2.11）：元素可能引用类类型，须在类前向声明之后、
	// 容器/类/函数定义之前（S3-05：元组引用元素）。
	// 协议类型与 vtable 对象前缀（S2 §4/§5.7）。
	g.emitProtocolTypes(&b)
	// 枚举 typedef / 数据枚举结构与项全局（S2 §8）。
	if err := g.emitEnumTypes(&b); err != nil {
		return "", err
	}
	if err := g.emitStructTypes(&b); err != nil {
		return "", err
	}
	// FFI 支撑代码（P-09）：包装函数 xn_ffi_<entry> 必须定义在调用点之前；
	// 生成失败即构建失败，绝不静默降级（ffi-contract §5.1）。
	if g.ffi != nil && !g.ffi.Empty() {
		sup := g.ffi.EmitSupport()
		if len(sup.Problems) > 0 {
			return "", fmt.Errorf("codegen：FFI 支撑代码生成失败：%v", sup.Problems)
		}
		b.WriteString(sup.Text)
		b.WriteString("\n")
	}
	names := make([]string, 0, len(g.results))
	for name := range g.results {
		names = append(names, name)
	}
	sort.Strings(names)
	b.WriteString("static void xn_fatal_oob(void);\n")
	b.WriteString("static void xn_fatal_oob(void) {\n")
	b.WriteString("    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n")
	b.WriteString("    exit(134);\n")
	b.WriteString("}\n\n")
	// 类前向声明：容器结构、顶层函数原型与类结构都只按指针使用类类型，
	// 必须先于它们出现（多文件下使用方声明可能先于定义方，S1-06）。
	if err := g.emitClassForwardDecls(&b); err != nil {
		return "", err
	}
	if err := g.emitSingletonForwards(&b); err != nil {
		return "", err
	}
	if err := g.emitExtensionProtos(&b); err != nil {
		return "", err
	}
	// 元组结构体（S1 §2.11）：类前向 typedef 已就位，可作为元素类型。
	g.emitTupleTypes(&b)
	// Result 实例 typedef：需要类/struct/枚举的前向 typedef 先就位（INT-01b）。
	{
		// S6-04：Result 成员可直接是容器（Result<List<String>, Error>）；
		// 先提前生成这些容器的 typedef，避免 Result typedef 引用未定义类型。
		needed := map[string]bool{}
		for name := range g.results {
			info, err := g.resultInfo(name)
			if err != nil {
				return "", err
			}
			if isContainerC(info.memberC) {
				needed[strings.TrimSuffix(info.memberC, " *")] = true
			}
		}
		g.cs.emitTypeDecls(&b, needed)
		rnames := make([]string, 0, len(g.results))
		for name := range g.results {
			rnames = append(rnames, name)
		}
		sort.Strings(rnames)
		for _, name := range rnames {
			info, err := g.resultInfo(name)
			if err != nil {
				return "", err
			}
			fmt.Fprintf(&b, "typedef struct { int ok; %s v; %s } %s;\n", info.memberC, cDecl(info.errC, "err"), name)
		}
		b.WriteString("\n")
	}
	// S5-04：任务 env 支撑（按需登记；必须在使用它的函数定义之前）。
	for _, sup := range g.taskSupport {
		b.WriteString(sup)
	}
	// 顶层字段存储：函数体与初始化函数都要引用，声明必须先于函数定义。
	for _, f := range g.globalList {
		fmt.Fprintf(&b, "static %s xn_g_%s;\n", g.globals[f.Name], f.Name)
	}
	if len(g.globalList) > 0 {
		b.WriteString("\n")
	}
	g.cs.ensureMapArrays()
	g.cs.emit(&b, g.isGCTypeC)
	// String.split 返回 String[]（依赖数组实例化）；replace 为纯字符串助手。
	if g.cs.arr["rt_string *"] {
		b.WriteString(strSplitHelper)
	}
	if g.needStrReplace {
		b.WriteString(strReplaceHelper)
	}
	// 顶层函数原型（类方法体可能引用后定义的顶层函数；与顺序无关）
	for _, d := range u.Decls {
		fn, ok := d.(*xfront.TopFunc)
		if !ok || len(fn.TypePars) > 0 {
			continue // 泛型声明本身不发原型；实例原型在下方单独发
		}
		if _, isFFI := g.ffiEntries[fn.Name]; isFFI {
			continue // 包装由 EmitSupport 提供
		}
		retC := "void"
		if !fn.Void {
			c, err := g.cType(fn.Ret)
			if err != nil {
				return "", err
			}
			retC = c
		}
		parts := []string{}
		for _, prm := range fn.Params {
			pc, err := g.cType(prm.Type)
			if err != nil {
				return "", err
			}
			parts = append(parts, pc+" xn_p_"+prm.Name)
		}
		fmt.Fprintf(&b, "static %s %s(%s);\n", retC, g.fnCName(fn), strings.Join(parts, ", "))
	}
	// 单态化实例原型（§8.3）：params/返回均已替换为具体类型，按实例名排序（DET-01）
	for _, cn := range g.instNames() {
		inst := g.insts[cn]
		saved := g.subst
		g.subst = inst.subst
		parts := []string{}
		var perr error
		for _, prm := range inst.fn.Params {
			pc, err := g.cType(prm.Type)
			if err != nil {
				perr = err
				break
			}
			parts = append(parts, pc+" xn_p_"+prm.Name)
		}
		g.subst = saved
		if perr != nil {
			return "", perr
		}
		fmt.Fprintf(&b, "static %s %s(%s);\n", inst.retC, inst.cname, strings.Join(parts, ", "))
	}
	if len(u.Decls) > 0 {
		b.WriteString("\n")
	}

	// 类结构/构造/方法（M4.4b）：容器与 Result typedef 已就位
	for _, d := range u.Decls {
		if n, ok := d.(*xfront.ClassDecl); ok {
			if len(n.TypePars) > 0 {
				continue // 泛型类实例在下方按需发射
			}
			ci := g.classes[n.Name]
			g.emitClassStruct(&b, ci)
			if err := g.emitClassCtor(&b, ci); err != nil {
				return "", err
			}
			// 方法前向声明（方法间互相调用与声明顺序无关）
			for _, md := range n.Methods {
				m := ci.methods[md.Name]
				if md.IsDeinit {
					m = ci.deinit
				}
				if m == nil {
					return "", fmt.Errorf("codegen：类 %s 的成员 %s 未登记", n.Name, md.Name)
				}
				proto, err := g.methodProto(ci, m)
				if err != nil {
					return "", err
				}
				b.WriteString(proto + "\n")
			}
			b.WriteString("\n")
			for _, md := range n.Methods {
				if md.IsDeinit {
					// 用户 deinit 体：由类型 deinit 钩子先调用（S2-E5-02）。
					mc, err := g.genMethod(ci, ci.deinit)
					if err != nil {
						return "", err
					}
					b.WriteString(mc + "\n")
					continue
				}
				mc, err := g.genMethod(ci, ci.methods[md.Name])
				if err != nil {
					return "", err
				}
				b.WriteString(mc + "\n")
			}
		}
	}
	// 泛型类实例（BND-12）：按发现顺序发射；嵌套实例可能在本轮追加。
	for i := 0; i < len(g.classInstKeys); i++ {
		ci := g.classInsts[g.classInstKeys[i]]
		if err := g.emitClassInstance(&b, ci); err != nil {
			return "", err
		}
	}
	if err := g.emitVtables(&b); err != nil {
		return "", err
	}
	if err := g.emitEnumBodies(&b); err != nil {
		return "", err
	}
	if err := g.emitStructBodies(&b); err != nil {
		return "", err
	}
	if err := g.emitSingletons(&b); err != nil {
		return "", err
	}
	if err := g.emitFactories(&b); err != nil {
		return "", err
	}
	if err := g.emitExtensions(&b); err != nil {
		return "", err
	}
	if err := g.emitEnumInit(&b); err != nil {
		return "", err
	}
	b.WriteString("static rt_string *xn_result_error_copy_rt(rt_string *err) {\n")
	b.WriteString("    return rt_string_new(err->bytes, err->len);\n")
	b.WriteString("}\n\n")
	// S5-04：任务闭包体原型（函数体生成阶段登记，晚于用户原型发出）。
	for _, p := range g.lateProtos {
		b.WriteString(p + "\n")
	}
	if len(g.lateProtos) > 0 {
		b.WriteString("\n")
	}
	for _, fn := range fns {
		b.WriteString(fn)
		b.WriteString("\n")
	}
	for _, fn := range g.lateFns {
		b.WriteString(fn)
		b.WriteString("\n")
	}
	// 顶层字段初始化（§4.3/§11.3）：声明顺序即初始化顺序，先于入口执行。
	if len(g.globalList) > 0 {
		initC, err := g.genGlobalInit()
		if err != nil {
			return "", err
		}
		b.WriteString(initC)
	}
	// C 入口：运行时/GC → 顶层字段初始化 → 调用 XNull main；返回值作进程退出码。
	// 无入口（库单元）时不发 C main。
	if entry != nil {
		var argsArr string
		if entry.withArgs {
			argsArr = arrName("rt_string *")
		}
		b.WriteString("int main(")
		if entry.withArgs {
			b.WriteString("int argc, char **argv")
		} else {
			b.WriteString("void")
		}
		b.WriteString(") {\n")
		if len(g.slotOrder) > 0 {
			b.WriteString("    xn_init_vtables();\n")
		}
		if g.stats {
			b.WriteString("    xrt_stats_reset();\n    xrt_stats_set_enabled(1);\n")
		}
		if len(g.enums) > 0 {
			b.WriteString("    xn_init_enums();\n")
		}
		if len(g.globalList) > 0 {
			b.WriteString("    xn_init_globals();\n")
		}
		if len(g.singletonOrder) > 0 {
			b.WriteString("    xn_init_singletons();\n")
		}
		if entry.withArgs {
			// args 是运行时创建的新数组，元素为进程参数（不含程序名，§11.2）。
			fmt.Fprintf(&b, "    %s *xn_args = %s_new((size_t)(argc > 1 ? argc - 1 : 0));\n", argsArr, argsArr)
			b.WriteString("    for (int i = 1; i < argc; i++) {\n")
			b.WriteString("        rt_string *xn_av = rt_string_from_c(argv[i]);\n")
			fmt.Fprintf(&b, "        %s_push(xn_args, xn_av);\n", argsArr)
			b.WriteString("        rt_release(xn_av);\n    }\n")
		}
		if entry.fn.Void {
			if entry.withArgs {
				b.WriteString("    xn_main(xn_args);\n")
			} else {
				b.WriteString("    xn_main();\n")
			}
			b.WriteString("    rt_gc_collect();\n    rt_quarantine_flush();\n")
			if g.stats {
				b.WriteString("    xrt_stats_set_enabled(0);\n    xrt_stats_report();\n")
			}
			b.WriteString("    return 0;\n")
		} else {
			if entry.withArgs {
				b.WriteString("    int64_t xn_r = xn_main(xn_args);\n")
			} else {
				b.WriteString("    int64_t xn_r = xn_main();\n")
			}
			b.WriteString("    rt_gc_collect();\n    rt_quarantine_flush();\n")
			if g.stats {
				b.WriteString("    xrt_stats_set_enabled(0);\n    xrt_stats_report();\n")
			}
			b.WriteString("    return (int)xn_r;\n")
		}
		b.WriteString("}\n")
	}
	return b.String(), nil
}

// entryInfo 是被校验过的入口声明。
type entryInfo struct {
	fn       *xfront.TopFunc
	withArgs bool // 入口接收 String[] 参数（§11.2 第二形态）
}

// entryDeclOf 查找并校验入口声明；无 main 时返回 (nil, nil)（供库单元 EmitC）。
// §11.2：只有匹配入口签名的 main 才是入口；不匹配的 main 重载是普通函数。
func entryDeclOf(u *xfront.CompilationUnit) (*entryInfo, error) {
	var mains []*xfront.TopFunc
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok && fn.Name == "main" {
			mains = append(mains, fn)
		}
	}
	if len(mains) == 0 {
		return nil, nil
	}
	var matched []*xfront.TopFunc
	for _, fn := range mains {
		if entrySignatureOK(fn) {
			matched = append(matched, fn)
		}
	}
	if len(matched) == 0 {
		return nil, fmt.Errorf("入口 main 的签名必须是 static void main(...) 或 static Int main(...)，参数只能是 String[]（§11.2）")
	}
	if len(matched) > 1 {
		return nil, fmt.Errorf("重复入口 main（§11.4）：一个程序只能有一个匹配签名的入口")
	}
	fn := matched[0]
	return &entryInfo{fn: fn, withArgs: len(fn.Params) == 1}, nil
}

// entrySignatureOK 判断声明是否满足入口签名（§11.2）：static、公开、非泛型、
// 返回 void/Int、参数为空或 String[]。
func entrySignatureOK(fn *xfront.TopFunc) bool {
	if !fn.Static || fn.Private || fn.Protected || len(fn.TypePars) > 0 {
		return false
	}
	if !fn.Void {
		nt, ok := fn.Ret.(*xfront.NamedType)
		if !ok || typeName(nt) != "Int" || len(nt.Args) > 0 {
			return false
		}
	}
	switch {
	case len(fn.Params) == 0:
		return true
	case len(fn.Params) == 1 && isStringArrayType(fn.Params[0].Type):
		return true
	}
	return false
}

// assignMainNames 为入口与其余 main 重载分配唯一 C 名。
// 入口固定 xn_main（C 垫片按此调用）；非匹配重载用 xn_main__ov<N>（§11.2 普通函数）。
func (g *gen) assignMainNames(u *xfront.CompilationUnit, entry *entryInfo) {
	n := 0
	for _, d := range u.Decls {
		fn, ok := d.(*xfront.TopFunc)
		if !ok || fn.Name != "main" {
			continue
		}
		if entry != nil && fn == entry.fn {
			g.fnNames[fn] = "xn_main"
			continue
		}
		n++
		name := fmt.Sprintf("xn_main__ov%d", n)
		g.fnNames[fn] = name
		g.mainOverloads[len(fn.Params)] = name
	}
}

// fnCName 返回顶层函数声明的 C 名（未登记时按常规 xn_<name>）。
func (g *gen) fnCName(fn *xfront.TopFunc) string {
	if c, ok := g.fnNames[fn]; ok {
		return c
	}
	return "xn_" + fn.Name
}

// RequireEntry 校验可执行程序的入口：缺失/重复/签名非法均为编译错误（§11.2/§11.4）。
// 供 Build 在生成 C 之前调用；EmitC 本身允许无入口的库单元。
func RequireEntry(u *xfront.CompilationUnit) error {
	e, err := entryDeclOf(u)
	if err != nil {
		return err
	}
	if e == nil {
		return fmt.Errorf("找不到入口 main（缺失入口，§11.4）")
	}
	return nil
}

// isStringArrayType 判断类型是否 String[]（入口参数形态）。
func isStringArrayType(t xfront.TypeRef) bool {
	st, ok := t.(*xfront.SuffixedType)
	if !ok {
		return false
	}
	for _, sfx := range st.Suffixes {
		if sfx != "[]" {
			return false
		}
	}
	nt, ok := st.Base.(*xfront.NamedType)
	return ok && typeName(nt) == "String"
}

// genGlobalInit 生成顶层字段初始化函数（声明顺序，§4.3/§11.3）。
func (g *gen) genGlobalInit() (string, error) {
	var b strings.Builder
	b.WriteString("static void xn_init_globals(void) {\n")
	sc := &scope{g: g, locals: map[string]string{}}
	var lines []string
	for _, f := range g.globalList {
		if f.Init == nil {
			continue
		}
		target := "xn_g_" + f.Name
		if g.isTupleC(g.globals[f.Name]) {
			tc := g.globals[f.Name]
			_, v, err := sc.tupleExpr(f.Init, tc)
			if err != nil {
				return "", err
			}
			lines = append(lines, sc.pending...)
			sc.pending = nil
			lines = append(lines, target+" = "+v+";")
			continue
		}
		if g.globals[f.Name] == "rt_string *" {
			sl, err := sc.strExpr(f.Init)
			if err != nil {
				return "", err
			}
			lines = append(lines, sc.pending...)
			sc.pending = nil
			lines = append(lines, sl...)
			lines = append(lines, target+" = "+lastVar(sl)+";", "xn_root_hold("+target+");")
			continue
		}
		if isContainerC(g.globals[f.Name]) {
			vl, v, err := sc.valExpr(f.Init, g.globals[f.Name])
			if err != nil {
				return "", err
			}
			lines = append(lines, vl...)
			lines = append(lines, target+" = "+v+";", "xn_root_hold("+target+");")
			continue
		}
		if g.isAnyC(g.globals[f.Name]) {
			al, v, err := sc.anyExpr(f.Init)
			if err != nil {
				return "", err
			}
			lines = append(lines, al...)
			lines = append(lines, target+" = "+v+";")
			if g.isGCRootC(g.globals[f.Name]) {
				lines = append(lines, "xn_root_hold("+target+");")
			}
			continue
		}
		if g.globals[f.Name] == "xrt_text *" {
			tl, v, err := sc.textExpr(f.Init)
			if err != nil {
				return "", err
			}
			lines = append(lines, tl...)
			lines = append(lines, target+" = "+v+";", "xn_root_hold("+target+");")
			continue
		}
		if g.globals[f.Name] == "xrt_sb *" {
			bl, v, err := sc.sbExpr(f.Init)
			if err != nil {
				return "", err
			}
			lines = append(lines, bl...)
			lines = append(lines, target+" = "+v+";", "xn_root_hold("+target+");")
			continue
		}
		if g.isProtoC(g.globals[f.Name]) {
			pl, expr, owned, err := sc.protoValue(f.Init)
			if err != nil {
				return "", err
			}
			lines = append(lines, pl...)
			if !owned {
				t := sc.tmp()
				lines = append(lines, "void *"+t+" = rt_retain((void *)"+expr+");")
				expr = t
			}
			lines = append(lines, target+" = ("+g.globals[f.Name]+")"+expr+";")
			lines = append(lines, "xn_root_hold((void *)"+target+");")
			continue
		}
		v, err := sc.intExpr(f.Init)
		if err != nil {
			return "", err
		}
		lines = append(lines, sc.pending...)
		sc.pending = nil
		lines = append(lines, target+" = "+v+";")
		// S3-02：GC 顶层字段登记为全局根。
		if g.isGCRootC(g.globals[f.Name]) {
			lines = append(lines, "xn_root_hold("+target+");")
		}
	}
	for _, l := range lines {
		b.WriteString("    " + l + "\n")
	}
	b.WriteString("}\n\n")
	return b.String(), nil
}

type gen struct {
	results          map[string]string            // Result 实例化名 → v 成员类型
	resultArgs       map[string][]xfront.TypeRef  // Result 实例化名 → 类型实参（S4-02 任意 E）
	cs               *containers                  // 容器实例化注册表（M4.4a）
	fnRet            map[string]string            // 顶层函数名 → 返回 C 类型（类型推断用）
	classes          map[string]*classInfo        // 类名 → 生成信息（M4.4b）
	classDecls       map[string]*xfront.ClassDecl // 类名 → 声明（继承递归收集用）
	globals          map[string]string            // 顶层字段名 → C 类型（ENTRY-01）
	globalList       []*xfront.TopField           // 顶层字段声明顺序（初始化顺序）
	ffi              *ffi.Registry                // .xfb 绑定注册表（P-09）
	ffiEntries       map[string]ffi.Entry         // 入口名 → 合同投影（P-09）
	handleNames      map[string]bool              // 不透明句柄类型（B0-07c）
	needStrReplace   bool                         // 使用过 String.replace（按需发助手）
	generics         map[string]*xfront.TopFunc   // 泛型函数名 → 声明（S1 §8.1）
	insts            map[string]*instInfo         // 实例 C 名 → 实例信息（S1 §8.3）
	instOrder        []string                     // 实例发现顺序（展开轮驱动；输出前排序）
	subst            map[string]xfront.TypeRef    // 当前实例的类型参数替换（空 = 普通函数）
	fnNames          map[*xfront.TopFunc]string   // 顶层函数声明 → C 名（main 重载需区分）
	mainOverloads    map[int]string               // 非匹配 main 重载：参数个数 → C 名（§11.2）
	entry            *entryInfo                   // 选中的入口（main 重载分派用）
	tuples           map[string]*tupleInfo        // 元组 C 结构体名 → 定义（S1 §2.11）
	policy           map[string]string            // 类名 → 内存策略（BND-10：arc/gc；缺省 arc）
	stack            map[string]bool              // 类名 → 栈分配候选（S3-03：Escape=none）
	inDeinit         bool                         // 正在发射 deinit 体（禁安全点：清扫期间不可重入收集）
	curEscaped       map[string]bool              // 当前函数体内已发布的局部名（S3-03 安全性）
	syncElems        map[string]string            // 同步原语局部 → 元素 C 类型（XDK-05）
	taskID           int                          // 任务闭包编号（S5-04）
	taskSupport      []string                     // 任务 env 支撑代码（按需）
	taskSupportAdded bool                         // 任务 env 支撑已登记
	lateProtos       []string                     // 延迟生成函数原型（任务闭包体）
	lateFns          []string                     // 延迟生成函数定义（任务闭包体）
	stats            bool                         // §21/§23：运行期分配统计开关
	tupleOrder       []string                     // 元组结构体登记顺序（内层先于外层）
	protocols        map[string]*protoInfo        // 协议名 → 签名/槽位（S2 §4）
	protoSlotByKey   map[string]int               // 签名 key → 全局槽位
	slotOrder        []protoSlot                  // 槽位表（索引即槽位）
	enums            map[string]*enumInfo         // 枚举名 → 定义（S2 §8）
	enumOrder        []string                     // 枚举声明顺序
	structs          map[string]*classInfo        // 结构体名 → 值布局（S2 §3）
	classInsts       map[string]*classInfo        // 泛型类实例 C 名 → 实例（BND-12）
	classInstKeys    []string                     // 实例发现顺序
	singletons       map[string]*classInfo        // 单例名 → 对象布局（BND-07）
	singletonOrder   []string                     // 单例声明顺序
	factories        map[string]*factoryInfo      // 工厂名 → 方法表（BND-08）
	factoryOrder     []string                     // 工厂声明顺序
	extensions       []*extensionInfo             // 扩展方法（BND-13）
	tmp              int
}

// cRef 把 XNull 标识符映射为 C 侧名字：参数带 xn_p_ 前缀，顶层字段带 xn_g_ 前缀。
func (s *scope) cRef(name string) string {
	if name == "super" && s.superT != "" {
		cvar := "self"
		if s.self != nil && s.self.cvar != "" {
			cvar = s.self.cvar
		}
		return "((" + s.superT + ")" + cvar + ")"
	}
	if s.params != nil && s.params[name] {
		return "xn_p_" + name
	}
	if _, ok := s.locals[name]; ok {
		return name
	}
	if s.self != nil {
		if name == "self" {
			return s.self.cvar
		}
		if cname, ok := s.self.fields[name]; ok {
			sep := "->"
			if s.self.value {
				sep = "."
			}
			return s.self.cvar + sep + cname
		}
	}
	if s.staticRefs != nil {
		if v, ok := s.staticRefs[name]; ok {
			return v
		}
	}
	if _, ok := s.g.globals[name]; ok {
		return "xn_g_" + name
	}
	return name
}

// typeName 取 NamedType 的末段名（x.y.z → z）。
func typeName(nt *xfront.NamedType) string {
	if len(nt.Qual) == 0 {
		return ""
	}
	return nt.Qual[len(nt.Qual)-1]
}

// resultName 由 Result 类型实参生成内联结构体名（§9/§10；S4-02 支持任意 E）。
// 命名沿用 xn_Result_<V>_<E>；E=String 保持历史名 xn_Result_<V>_String。
func (g *gen) resultName(args []xfront.TypeRef) (string, error) {
	if len(args) != 2 {
		return "", fmt.Errorf("codegen：Result 需要两个类型实参")
	}
	vt, ok := args[0].(*xfront.NamedType)
	if !ok {
		return "", fmt.Errorf("codegen：Result 值类型 %T 未支持", args[0])
	}
	et, ok := args[1].(*xfront.NamedType)
	if !ok {
		return "", fmt.Errorf("codegen：Result 错误类型 %T 未支持（S4-02）", args[1])
	}
	vtag := typeName(vt)
	if vtag == "" {
		return "", fmt.Errorf("codegen：Result 值类型缺少类型名")
	}
	if vtag == "Result" || typeName(et) == "Result" {
		return "", fmt.Errorf("codegen：Result 不得嵌套 Result（S4 §2.1）")
	}
	name := "xn_Result_" + vtag + "_" + typeName(et)
	if typeName(et) == "String" {
		name = "xn_Result_" + vtag + "_String"
	}
	g.resultArgs[name] = args
	return name, nil
}

// resultInfo 解析 Result 实例的 v / err 成员 C 类型。
type resultInfo struct {
	memberC string
	errC    string
}

func (g *gen) resultInfo(name string) (resultInfo, error) {
	args := g.resultArgs[name]
	if args == nil {
		// 兼容未登记实例（历史代码路径）：按 _String 后缀回退。
		const pre, suf = "xn_Result_", "_String"
		if !strings.HasPrefix(name, pre) || !strings.HasSuffix(name, suf) {
			return resultInfo{}, fmt.Errorf("codegen：未知 Result 类型 %s", name)
		}
		tag := strings.TrimSuffix(strings.TrimPrefix(name, pre), suf)
		mC, err := g.resultCType(&xfront.NamedType{Qual: []string{tag}})
		if err != nil {
			return resultInfo{}, err
		}
		return resultInfo{memberC: mC, errC: "rt_string *"}, nil
	}
	mC, err := g.resultCType(args[0])
	if err != nil {
		return resultInfo{}, err
	}
	eC, err := g.resultCType(args[1])
	if err != nil {
		return resultInfo{}, err
	}
	return resultInfo{memberC: mC, errC: eC}, nil
}

// resultMemberC 由 Result 实例名解析值成员的 C 类型（BND/INT-01）。
func (g *gen) resultMemberC(resultC string) (string, error) {
	info, err := g.resultInfo(resultC)
	if err != nil {
		return "", err
	}
	return info.memberC, nil
}

// resultCType 把 Result 的 V/E 类型引用解析为 C 类型。
func (g *gen) resultCType(t xfront.TypeRef) (string, error) {
	nt, ok := t.(*xfront.NamedType)
	if !ok {
		return "", fmt.Errorf("codegen：Result 成员类型 %T 未支持（S4-02）", t)
	}
	name := typeName(nt)
	switch name {
	case "Int", "Int64":
		return "int64_t", nil
	case "Int32":
		return "int32_t", nil
	case "Bool":
		return "int", nil
	case "String":
		return "rt_string *", nil
	case "Result":
		return "", fmt.Errorf("codegen：Result 不得嵌套 Result（S4 §2.1）")
	case "ErrorKind":
		if ei, ok := g.enums["ErrorKind"]; ok {
			return ei.ctype, nil
		}
		return "int64_t", nil
	case "TaskError", "CancelledError":
		// 任务/取消边界错误面：复用 S4 ErrorKind（S5-00 §八）。
		return "xrt_error_kind", nil
	case "Bytes":
		return "xrt_bytes_obj *", nil
	case "Text":
		return "xrt_text *", nil
	case "Error":
		// S6-04：资源 API 的 Error 以 ErrorKind 值通道交付（E5 资源 ABI）。
		return "xrt_error_kind", nil
	case "List":
		if len(nt.Args) != 1 {
			return "", fmt.Errorf("codegen：Result 值 List 需要一个类型实参")
		}
		ec, err := g.resultCType(nt.Args[0])
		if err != nil {
			return "", err
		}
		if err := g.cs.needArr(ec); err != nil {
			return "", err
		}
		return arrName(ec) + " *", nil
	case "void":
		// Result<void, E>：值槽仅占位（close 等无值结果）。
		return "int64_t", nil
	}
	if ci, ok := g.classes[name]; ok {
		return ci.cname + " *", nil
	}
	if ci, ok := g.singletons[name]; ok {
		return ci.cname + " *", nil
	}
	if ci, ok := g.structs[name]; ok {
		return ci.cname, nil
	}
	if ei, ok := g.enums[name]; ok {
		return ei.ctype, nil
	}
	if ct, ok := g.protoCType(name); ok {
		return ct, nil
	}
	return "", fmt.Errorf("codegen：Result 成员类型 %s 未支持（S4-02）", name)
}

// resultZeroC 生成 Result 成员的零值 C 表达式。
func (g *gen) resultZeroC(c string) string {
	if strings.HasSuffix(c, "*") {
		return "NULL"
	}
	if g.isStructC(c) || g.isTupleC(c) {
		return "(" + c + "){0}"
	}
	return "0"
}

// importsXDK 判断编译单元是否导入了 xdk.<pkg>。
func importsXDK(u *xfront.CompilationUnit, pkg string) bool {
	for _, imp := range u.Imports {
		if strings.Join(imp.Path, ".") == "xdk."+pkg {
			return true
		}
	}
	return false
}

// ensureErrorKind 注入 xdk.errors 的内建 ErrorKind 简单枚举（S4 §3.1，值对齐 XRT_ERR_*）。
func (g *gen) ensureErrorKind() {
	if _, ok := g.enums["ErrorKind"]; ok {
		return
	}
	items := []string{
		"InvalidArgument", "NotFound", "AlreadyExists", "PermissionDenied",
		"Io", "Network", "Timeout", "Cancelled", "Busy", "Unavailable",
		"DataCorrupted", "Unsupported", "OutOfMemory", "Internal",
	}
	ei := &enumInfo{name: "ErrorKind", ctype: "xn_Enum_ErrorKind", simple: true,
		decl: &xfront.EnumDecl{Name: "ErrorKind"}, values: map[string]int64{}}
	for i, n := range items {
		ei.values[n] = int64(i)
		ei.items = append(ei.items, enumItemInfo{name: n, value: int64(i)})
	}
	g.enums["ErrorKind"] = ei
	g.enumOrder = append(g.enumOrder, "ErrorKind")
}

// collectAllResults 汇总类/结构体/枚举/单例/工厂方法与局部声明中的 Result 实例。
func (g *gen) collectAllResults(u *xfront.CompilationUnit) error {
	addType := func(t xfront.TypeRef) error {
		nt, ok := t.(*xfront.NamedType)
		if !ok || typeName(nt) != "Result" {
			return nil
		}
		name, err := g.resultName(nt.Args)
		if err != nil {
			return err
		}
		g.results[name] = ""
		return nil
	}
	addMethods := func(ms []*xfront.MethodDecl) error {
		for _, m := range ms {
			if !m.Void {
				if err := addType(m.Ret); err != nil {
					return err
				}
			}
			if m.Body != nil {
				if err := g.collectBlock(m.Body); err != nil {
					return err
				}
			}
		}
		return nil
	}
	addFields := func(fs []*xfront.FieldDecl) error {
		for _, f := range fs {
			if err := addType(f.Type); err != nil {
				return err
			}
		}
		return nil
	}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.ClassDecl:
			if err := addFields(n.Fields); err != nil {
				return err
			}
			if err := addMethods(n.Methods); err != nil {
				return err
			}
		case *xfront.StructDecl:
			if err := addFields(n.Fields); err != nil {
				return err
			}
			if err := addMethods(n.Methods); err != nil {
				return err
			}
		case *xfront.EnumDecl:
			if err := addFields(n.Fields); err != nil {
				return err
			}
			if err := addMethods(n.Methods); err != nil {
				return err
			}
		case *xfront.SingletonDecl:
			if err := addFields(n.Fields); err != nil {
				return err
			}
			if err := addMethods(n.Methods); err != nil {
				return err
			}
		case *xfront.FactoryDecl:
			if err := addMethods(n.Methods); err != nil {
				return err
			}
		}
	}
	return nil
}

func (g *gen) collectResult(fn *xfront.TopFunc) error {
	// 泛型声明的 Result<T,E> 不在此实例化（单态化实例走 expandInstances）。
	if len(fn.TypePars) > 0 {
		return nil
	}
	if !fn.Void {
		if nt, ok := fn.Ret.(*xfront.NamedType); ok && typeName(nt) == "Result" {
			name, err := g.resultName(nt.Args)
			if err != nil {
				return err
			}
			g.results[name] = ""
		}
	}
	return g.collectBlock(fn.Body)
}

func (g *gen) collectBlock(b *xfront.Block) error {
	for _, st := range b.Stmts {
		if err := g.collectStmt(st); err != nil {
			return err
		}
	}
	return nil
}

func (g *gen) collectStmt(st xfront.Stmt) error {
	switch n := st.(type) {
	case *xfront.LocalDeclStmt:
		if nt, ok := n.Type.(*xfront.NamedType); ok && typeName(nt) == "Result" {
			name, err := g.resultName(nt.Args)
			if err != nil {
				return err
			}
			g.results[name] = ""
		}
	case *xfront.IfStmt:
		if err := g.collectBlock(n.Then); err != nil {
			return err
		}
		if eb, ok := n.Else.(*xfront.Block); ok {
			return g.collectBlock(eb)
		}
		if n.Else != nil {
			return g.collectStmt(n.Else)
		}
	case *xfront.WhileStmt:
		return g.collectBlock(n.Body)
	case *xfront.DeferStmt:
		if n.Block != nil {
			return g.collectBlock(n.Block)
		}
	}
	return nil
}

func (g *gen) cType(t xfront.TypeRef) (string, error) {
	// 单态化实例内：先把类型参数替换为具体类型（S1 §8.3）。空替换表为恒等。
	t = g.substitute(t)
	switch n := t.(type) {
	case nil:
		return "void", nil
	case *xfront.SuffixedType:
		if len(n.Suffixes) == 1 && n.Suffixes[0] == "[]" {
			ec, err := g.cType(n.Base)
			if err != nil {
				return "", err
			}
			if err := g.cs.needArr(ec); err != nil {
				return "", err
			}
			return arrName(ec) + " *", nil
		}
		if len(n.Suffixes) == 1 && n.Suffixes[0] == "?" {
			bc, err := g.cType(n.Base)
			if err != nil {
				return "", err
			}
			// 类/协议指针本身可空：用 NULL 哨兵，不加 wrapper（S2 §4.5/§5.2）。
			if isClassPtr(bc) || g.isProtoC(bc) || isHandlePtr(bc) || bc == "xrt_bytes_obj *" {
				return bc, nil
			}
			return optName(bc)
		}
		return "", fmt.Errorf("codegen：类型后缀 %v 未支持（M4.4a 范围）", n.Suffixes)
	case *xfront.TupleTypeRef:
		return g.tupleTypeFromElems(n.Elems)
	case *xfront.NamedType:
		switch typeName(n) {
		case "Int":
			return "int64_t", nil
		case "Int32":
			return "int32_t", nil
		case "Int64":
			return "int64_t", nil
		case "Bool":
			return "int", nil
		case "String", "Text":
			if typeName(n) == "Text" {
				return "xrt_text *", nil
			}
			return "rt_string *", nil
		case "StringBuilder":
			return "xrt_sb *", nil
		case "Context":
			return "xrt_context *", nil
		case "CancelToken":
			return "xrt_cancel_token *", nil
		case "TaskGroup":
			return "xrt_task_group *", nil
		case "Task":
			// Task<T> 的 C 句柄不区分 T（结果映射由 join 目标类型决定）。
			return "xrt_task *", nil
		case "TaskError":
			return "xrt_error_kind", nil
		case "CancelledError":
			return "xrt_error_kind", nil
		case "Mutex":
			return "xrt_mutex *", nil
		case "Channel":
			return "xrt_channel *", nil
		case "AtomicInt":
			return "xrt_atomic_int *", nil
		case "AtomicBool":
			return "xrt_atomic_bool *", nil
		case "AtomicRef":
			return "xrt_atomic_ref *", nil
		case "Any", "Object":
			// Any/Object 是 GC 装箱盒（S3 §3：值类型进入 Any 必须装箱，装箱对象由 GC 管理）。
			return "xn_Any *", nil
		case "Bytes":
			// S1 §9.7：Bytes 是 GC 管理的可变字节缓冲（引用类型）。
			// data/len 字段同时充当 S7 §3.4 的边界视图（FFI 借出用）。
			return "xrt_bytes_obj *", nil
		case "List":
			if len(n.Args) != 1 {
				return "", fmt.Errorf("codegen：List 需要一个类型实参")
			}
			ec, err := g.cType(n.Args[0])
			if err != nil {
				return "", err
			}
			if err := g.cs.needArr(ec); err != nil {
				return "", err
			}
			return arrName(ec) + " *", nil
		case "Set":
			if len(n.Args) != 1 {
				return "", fmt.Errorf("codegen：Set 需要一个类型实参")
			}
			ec, err := g.cType(n.Args[0])
			if err != nil {
				return "", err
			}
			if err := g.cs.needSet(ec); err != nil {
				return "", err
			}
			return setName(ec) + " *", nil
		case "Map":
			if len(n.Args) != 2 {
				return "", fmt.Errorf("codegen：Map 需要两个类型实参")
			}
			kc, err := g.cType(n.Args[0])
			if err != nil {
				return "", err
			}
			vc, err := g.cType(n.Args[1])
			if err != nil {
				return "", err
			}
			if err := g.cs.needMap(kc, vc); err != nil {
				return "", err
			}
			return mapName(kc, vc) + " *", nil
		case "Result":
			return g.resultName(n.Args)
		default:
			if ci, ok := g.singletons[typeName(n)]; ok {
				return ci.cname + " *", nil
			}
			if decl, ok := g.classDecls[typeName(n)]; ok && len(decl.TypePars) > 0 {
				ci, err := g.ensureClassInstance(typeName(n), n.Args)
				if err != nil {
					return "", err
				}
				return ci.cname + " *", nil
			}
			if ei, ok := g.enums[typeName(n)]; ok {
				return ei.ctype, nil
			}
			if ci, ok := g.structs[typeName(n)]; ok {
				return ci.cname, nil
			}
			if ct, ok := g.protoCType(typeName(n)); ok {
				return ct, nil
			}
			if _, ok := g.classOf(typeName(n)); ok {
				return "xn_Cls_" + typeName(n) + " *", nil
			}
			if g.handleNames[typeName(n)] {
				return "xrt_handle *", nil
			}
		case "void":
			return "void", nil
		}
	}
	if nt, ok := t.(*xfront.NamedType); ok {
		return "", fmt.Errorf("codegen：类型 %s 未支持（M4.1 范围）", typeName(nt))
	}
	return "", fmt.Errorf("codegen：类型 %T 未支持（M4.1 范围）", t)
}

// ---------- 函数 ----------

func (g *gen) genFunc(fn *xfront.TopFunc) (string, error) {
	return g.genFuncNamed(fn, "xn_"+fn.Name)
}

// genFuncNamed 生成函数体，C 名可指定（单态化实例用实例名，§8.3）。
func (g *gen) genFuncNamed(fn *xfront.TopFunc, cname string) (string, error) {
	retC, err := g.cType(fn.Ret)
	if err != nil {
		return "", err
	}
	if fn.Void {
		retC = "void"
	}
	var params []string
	for _, p := range fn.Params {
		pc, err := g.cType(p.Type)
		if err != nil {
			return "", err
		}
		params = append(params, pc+" xn_p_"+p.Name)
	}
	hasResult := strings.HasPrefix(retC, "xn_Result_")
	pnames := map[string]bool{}
	locals := map[string]string{}
	for _, p := range fn.Params {
		pnames[p.Name] = true
		if pc, err := g.cType(p.Type); err == nil {
			locals[p.Name] = pc
		}
	}
	sc := &scope{g: g, retC: retC, hasResult: hasResult, params: pnames, locals: locals}
	// S3-02：函数级根帧；GC 参数在入口登记为栈根。
	sc.rootMark = g.nextTmp()
	for _, p := range fn.Params {
		if pc, err := g.cType(p.Type); err == nil && g.isGCRootC(pc) {
			sc.rootPrelude = append(sc.rootPrelude, "xn_root_add(xn_p_"+p.Name+");")
		}
	}
	// S3-03：预扫描逃逸位置（发布到实参/返回值/别名的局部退回堆分配）。
	savedEsc := g.curEscaped
	g.curEscaped = escapeIdents(fn.Body)
	defer func() { g.curEscaped = savedEsc }()
	body, err := sc.emitBlock(fn.Body.Stmts)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s %s(%s) {\n", retC, cname, strings.Join(params, ", "))
	if hasResult {
		fmt.Fprintf(&b, "    %s xn_ret;\n", retC)
	}
	b.WriteString(body)
	// 函数体末尾自然退出的 defer 已由 emitBlock 的块退出清理承载
	//（errdefer 不触发：无返回发生，§10.3）
	if hasResult && !sc.returned {
		// 自然落到函数末尾（无 return）：C 结构体零值即 ok=0（Err 语义由 sema 保证不可达）
		fmt.Fprintf(&b, "    %s xn_zero = {0};\n", retC)
		b.WriteString("    xn_ret = xn_zero;\n")
		b.WriteString("    return xn_ret;\n")
	}
	b.WriteString("}\n")
	return b.String(), nil
}

// ---------- 作用域与 defer（§10.3） ----------

type deferItem struct {
	errdefer bool
	lines    []string // 缩进 8 的 C 语句
	name     string   // 保护的引用名（类/String 临时）；return 引用计数抵消用
}

type scope struct {
	parent      *scope // 父块作用域（return/try 需执行祖先块注册的 defer）
	g           *gen
	retC        string
	hasResult   bool
	defers      []deferItem       // 本块注册的清理（LIFO）
	pending     []string          // 表达式求值产生的临时声明（语句边界冲刷到输出）
	params      map[string]bool   // 参数名（C 侧带 xn_p_ 前缀）
	locals      map[string]string // 局部变量 → C 类型（for-in/容器成员查找）
	self        *selfCtx          // 实例成员上下文（方法/构造器/deinit 内非限定名，§5.8）
	staticRefs  map[string]string // 单例静态字段 → C 全局变量（BND-07）
	staticTypes map[string]string // 单例静态字段 → C 类型（BND-07）
	superT      string            // super 的静态类型（直接父类 C 指针类型；无继承为空）
	isCtor      bool              // 构造器体：`return;` 返回已构造对象
	returned    bool              // 末句已生成 return（块退出清理跳过）
	rootMark    string            // 根帧标记变量（S3-02；空=本块不登记）
	rootPrelude []string          // 根帧建立后立即执行的登记（参数/self 根）
	kind        string            // 块种类：loop/switch（break/continue 根帧恢复用）
	taskBody    *taskBodyInfo     // 任务闭包体（S5-04）：return → xrt_task_result
	taskEnvVar  string            // 任务体 env 变量名
	taskOutVar  string            // 任务体 out 参数名
	lockBody    *taskBodyInfo     // Mutex.withLock 回调体（XDK-05）
}

// selfCtx 是实例上下文：非限定字段/方法按 §5.8 解析到 self。
type selfCtx struct {
	ctype   string                  // 当前类 C 类型（xn_Cls_X *）
	cvar    string                  // 当前 self 的 C 变量名（方法=self，构造器=o）
	value   bool                    // self 为值（struct 构造器）而非指针
	fields  map[string]string       // 字段声明名/规范名 → C 成员名
	types   map[string]string       // 字段声明名/规范名 → C 类型
	methods map[string]*classInfo_m // 实例方法名 → 签名
	ci      *classInfo
}

// newSelfCtx 构建类的实例上下文（字段含私有规范名）。
func newSelfCtx(ci *classInfo) *selfCtx {
	sc := &selfCtx{cvar: "self", ctype: ci.cname + " *", fields: map[string]string{}, types: map[string]string{}, methods: map[string]*classInfo_m{}, ci: ci}
	for _, f := range ci.fields {
		sc.fields[f.name] = f.cname
		sc.types[f.name] = f.ctype
		if f.name != f.cname {
			sc.fields[f.cname] = f.cname
			sc.types[f.cname] = f.ctype
		}
	}
	for name, m := range ci.methods {
		sc.methods[name] = m
	}
	return sc
}

// localCType 查局部变量 C 类型（含参数；参数按其声明类型登记）。
func (s *scope) localCType(name string) (string, bool) {
	c, ok := s.locals[name]
	return c, ok
}

// newChild 生成继承函数级状态的子作用域（if/while 体等块级范围）。
func (s *scope) newChild() *scope {
	locals := map[string]string{}
	for k, v := range s.locals {
		locals[k] = v
	}
	return &scope{parent: s, g: s.g, retC: s.retC, hasResult: s.hasResult, params: s.params, locals: locals, self: s.self, staticRefs: s.staticRefs, staticTypes: s.staticTypes, superT: s.superT, isCtor: s.isCtor, rootMark: s.tmp()}
}

func (s *scope) tmp() string { return s.g.nextTmp() }

// nextTaskID 分配任务闭包编号。
func (g *gen) nextTaskID() int {
	g.taskID++
	return g.taskID
}

// nextTmp 分配一个翻译单元内唯一的临时变量名。
func (g *gen) nextTmp() string {
	g.tmp++
	return fmt.Sprintf("xn_t%d", g.tmp)
}

// emitCleanup 生成清理序列（注册逆序）。condErr 为 true 时 errdefer 以
// 运行时 `xn_ret.ok` 判定（return / try 传播路径）；false 时跳过 errdefer
// （普通块退出/Ok 返回不触发，§10.3）。
func (s *scope) emitCleanup(condErr bool, indent string) string {
	var out []string
	// 返回/传播路径：从最内层块向外执行所有祖先块注册的 defer（LIFO）。
	for sc := s; sc != nil; sc = sc.parent {
		for i := len(sc.defers) - 1; i >= 0; i-- {
			d := sc.defers[i]
			if d.errdefer {
				if !s.hasResult || !condErr {
					continue
				}
				out = append(out, indent+"if (!xn_ret.ok) {")
				out = append(out, d.lines...)
				out = append(out, indent+"}")
			} else {
				out = append(out, indent+"{")
				out = append(out, d.lines...)
				out = append(out, indent+"}")
			}
		}
	}
	return strings.Join(out, "\n") + trailingNewline(out)
}

func trailingNewline(lines []string) string {
	if len(lines) == 0 {
		return ""
	}
	return "\n"
}

// emitRootRestores 生成 break/continue 跳出块时的根帧恢复（S3-02）。
// break 恢复到最近的 loop/switch 块（含）；continue 恢复到最近 loop 块（含）。
func (s *scope) emitRootRestores(kind string) []string {
	var out []string
	for sc := s; sc != nil; sc = sc.parent {
		if sc.rootMark != "" {
			out = append(out, "xn_root_restore("+sc.rootMark+");")
		}
		if kind == "continue" {
			if sc.kind == "loop" {
				break
			}
			continue
		}
		if sc.kind != "" {
			break
		}
	}
	return out
}

// emitBlock 生成语句序列；块退出时执行本块注册的 defer（errdefer 不触发）。
func (s *scope) emitBlock(stmts []xfront.Stmt) (string, error) {
	var out []string
	// S3-02：块级根帧——记录进入时的根栈标记，块退出/返回时恢复。
	if s.rootMark != "" {
		out = append(out, "size_t "+s.rootMark+" = xn_root_mark();")
		if len(s.rootPrelude) > 0 {
			out = append(out, s.rootPrelude...)
			s.rootPrelude = nil
		}
		s.defers = append(s.defers, deferItem{lines: []string{"xn_root_restore(" + s.rootMark + ");"}})
	}
	for _, st := range stmts {
		lines, err := s.emitStmt(st)
		if err != nil {
			return "", err
		}
		out = append(out, lines...)
	}
	// 块退出清理（跳过 errdefer）；末句是 return 时清理已随返回路径生成
	if !s.returned {
		for i := len(s.defers) - 1; i >= 0; i-- {
			d := s.defers[i]
			if !d.errdefer {
				out = append(out, "    {")
				out = append(out, reindent(d.lines, "    ")...)
				out = append(out, "    }")
			}
		}
	}
	return strings.Join(out, "\n") + trailingNewline(out), nil
}

// ---------- 语句 ----------

func (s *scope) emitStmt(st xfront.Stmt) ([]string, error) {
	out := s.pending
	s.pending = nil
	lines, err := s.emitStmtInner(st)
	if err != nil {
		return nil, err
	}
	out = append(out, s.pending...)
	s.pending = nil
	return append(out, lines...), nil
}

func (s *scope) emitStmtInner(st xfront.Stmt) ([]string, error) {
	switch n := st.(type) {
	case *xfront.ExprStmt:
		return s.emitExprStmt(n.X)
	case *xfront.LocalDeclStmt:
		lines, err := s.emitLocalDecl(n)
		if err == nil {
			// S3-02：GC 引用局部登记为栈根；分配点安全点。
			if tc, ok := s.locals[n.Name]; ok && s.g.isGCRootC(tc) {
				lines = append(lines, "xn_root_add("+n.Name+");")
				if !s.g.inDeinit {
					lines = append(lines, "xn_gc_safepoint();")
				}
			}
		}
		return lines, err
	case *xfront.AssignStmt:
		return s.emitAssign(n)
	case *xfront.ReturnStmt:
		return s.emitReturn(n)
	case *xfront.IfStmt:
		return s.emitIf(n)
	case *xfront.SwitchStmt:
		return s.emitSwitch(n)
	case *xfront.BreakStmt:
		// 循环/switch 体内合法；先恢复被跳出块的根帧，再 break。
		return append(s.emitRootRestores("break"), "break;"), nil
	case *xfront.ContinueStmt:
		return append(s.emitRootRestores("continue"), "continue;"), nil
	case *xfront.WhileStmt:
		cond, err := s.cond(n.Cond)
		if err != nil {
			return nil, err
		}
		// 条件求值产生前置语句（字符串临时等）时不能在循环外提升：
		// 降级为 while(1){ 前置; if(!cond) break; 体 }——每轮重新求值，
		// continue 跳到顶部同样重新求值（语义等价 §6.4）。
		if len(s.pending) > 0 {
			pre := append([]string{}, s.pending...)
			s.pending = nil
			bodySc := s.newChild()
			bodySc.kind = "loop"
			body, err := bodySc.emitBlock(n.Body.Stmts)
			if err != nil {
				return nil, err
			}
			out := []string{"    while (1) {"}
			out = append(out, reindent(pre, "        ")...)
			out = append(out, "        if (!("+cond+")) { break; }")
			out = append(out, reindent(splitLines(body), "        ")...)
			if !s.g.inDeinit {
				out = append(out, "        xn_gc_safepoint();")
			}
			out = append(out, "    }")
			return out, nil
		}
		bodySc := s.newChild()
		bodySc.kind = "loop"
		body, err := bodySc.emitBlock(n.Body.Stmts)
		if err != nil {
			return nil, err
		}
		out := reindent(splitLines(body), "    ")
		if !s.g.inDeinit {
			out = append(out, "    xn_gc_safepoint();")
		}
		return append([]string{"    while (" + cond + ") {"}, append(out, "    }")...), nil
	case *xfront.ForStmt:
		return s.emitForIn(n)
	case *xfront.DeferStmt:
		var lines []string
		if n.Block != nil {
			for _, st := range n.Block.Stmts {
				ls, err := s.emitStmt(st)
				if err != nil {
					return nil, err
				}
				lines = append(lines, ls...)
			}
		} else {
			ls, err := s.emitStmt(n.Stmt)
			if err != nil {
				return nil, err
			}
			lines = ls
		}
		s.defers = append(s.defers, deferItem{errdefer: n.Errdefer, lines: reindent(lines, "        ")})
		return nil, nil
	case *xfront.ThrowStmt:
		v, err := s.strExprOne(n.Value)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return append(out, "xn_throw("+v+");"), nil
	}
	return nil, fmt.Errorf("codegen：语句 %T 未支持（M4.1 范围）", st)
}

func reindent(lines []string, indent string) []string {
	out := make([]string, len(lines))
	for i, l := range lines {
		if l == "" {
			out[i] = l
		} else {
			out[i] = indent + l
		}
	}
	return out
}

// emitExprStmt 表达式语句：print(...) 或 void 调用。
func (s *scope) emitExprStmt(e xfront.Expr) ([]string, error) {
	call, ok := e.(*xfront.Call)
	if !ok {
		return nil, fmt.Errorf("codegen：表达式语句 %T 未支持（M4.1 范围）", e)
	}
	if mem, ok := call.Callee.(*xfront.Member); ok {
		if expr, _, hit, err := s.tryFactoryCall(mem, call); err != nil {
			return nil, err
		} else if hit {
			out := append([]string{}, s.pending...)
			s.pending = nil
			return append(out, expr+";"), nil
		}
		if expr, _, hit, err := s.staticClassCall(mem, call); err != nil {
			return nil, err
		} else if hit {
			out := append([]string{}, s.pending...)
			s.pending = nil
			return append(out, expr+";"), nil
		}
		if rt, err := s.exprType(mem.X); err == nil && s.g.isProtoC(rt) {
			expr, _, err := s.protoDispatch(mem, call.Args)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			return append(out, expr+";"), nil
		}
		if rn, rc, err := recvCName(mem.X, s); err == nil && s.g.isStructC(rc) {
			ci, _ := s.g.structOfC(rc)
			m, ok := s.methodFor(ci, mem.Name, call.Args)
			if !ok {
				return nil, fmt.Errorf("codegen：结构体 %s 没有方法 %s", ci.decl.Name, mem.Name)
			}
			expr, err := s.methodCall(ci, m, "(&"+rn+")", call.Args)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			return append(out, expr+";"), nil
		}
		if rn, rc, err := recvCName(mem.X, s); err == nil {
			if isClassPtr(rc) || s.g.isDataEnumC(rc) {
				if v, hit, err := s.classMemberValue(rc, rn, mem, call.Args); err != nil {
					return nil, err
				} else if hit {
					out := append([]string{}, s.pending...)
					s.pending = nil
					return append(out, v+";"), nil
				}
			}
			if rc == "xrt_sb *" {
				lines, hit, err := s.sbMemberStmt(rn, mem.Name, call.Args)
				if err != nil {
					return nil, err
				}
				if hit {
					return lines, nil
				}
			}
			if rc == "xrt_bytes_obj *" {
				lines, hit, err := s.bytesMemberStmt(rn, mem.Name, call.Args)
				if err != nil {
					return nil, err
				}
				if hit {
					return lines, nil
				}
			}
			if rc == "xrt_sb *" {
				lines, hit, err := s.sbMemberStmt(rn, mem.Name, call.Args)
				if err != nil {
					return nil, err
				}
				if hit {
					return lines, nil
				}
			}
			if isContainerC(rc) {
				lines, hit, err := s.containerMemberStmt(rc, rn, mem.Name, call.Args)
				if err != nil {
					return nil, err
				}
				if hit {
					return lines, nil
				}
			}
			if lines, hit, err := s.emitSyncSpecialStmt(rn, rc, mem.Name, call.Args); err != nil {
				return nil, err
			} else if hit {
				return lines, nil
			}
			if mem.Name == "cancel" {
				if rc == "xrt_task_group *" {
					return []string{"xrt_task_group_cancel(" + rn + ");", "xrt_safepoint();"}, nil
				}
				if rc == "xrt_context *" {
					return []string{"xrt_context_cancel(" + rn + ");"}, nil
				}
			}
		}
		return nil, fmt.Errorf("codegen：成员调用 %s 未支持（M4.4a 范围）", mem.Name)
	}
	id, ok := call.Callee.(*xfront.IdentExpr)
	if !ok {
		return nil, fmt.Errorf("codegen：调用目标 %T 未支持", call.Callee)
	}
	if sys603IsAsyncName(id.Name) {
		lines, expr, handled, err := s.sys603Call(call)
		if err != nil {
			return nil, err
		}
		if handled {
			if expr == "" {
				return lines, nil
			}
			if _, ok := sys603Type(id.Name); ok && sys603IsStringOut(id.Name) {
				lines = append(lines, "rt_release("+expr+");")
			}
			return append(lines, expr+";"), nil
		}
	}
	if id.Name == "dumpTasks" {
		// S6-02：dumpTasks 运行时诊断（单行；非承诺）。计数由调度器维护，
		// 与生成侧任务提交/终结共用同一来源，避免两套计数漂移。
		return []string{"xrt_safepoint();", "xdkc_dump_tasks();"}, nil
	}
	if id.Name == "diagnose" && len(call.Args) == 1 {
		sl, err := s.strExpr(call.Args[0])
		if err != nil {
			return nil, err
		}
		return append(sl, "xdkc_diagnose("+lastVar(sl)+"->bytes, "+lastVar(sl)+"->len);"), nil
	}
	if id.Name == "exit" && len(call.Args) == 1 {
		v, err := s.intExpr(call.Args[0])
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return append(out, "xdkc_exit((int64_t)("+v+"));"), nil
	}
	if id.Name == "print" {
		return s.emitPrint(call.Args[0])
	}
	// S4-02：report(r) 语句形态（边界观测；返回原 Result 但丢弃）。
	if id.Name == "report" && len(call.Args) == 1 {
		if t, err := s.exprType(call.Args[0]); err == nil && strings.HasPrefix(t, "xn_Result_") {
			v, err := s.emitResultReport(call.Args[0], t)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			return append(out, "(void)"+v+";"), nil
		}
	}
	if id.Name == "str" {
		return nil, fmt.Errorf("codegen：str(...) 结果被丢弃（sema 应拒绝）")
	}
	if e, isFFI := s.ffiEntry(id.Name); isFFI {
		lines, out, err := s.ffiCallLines(call, e)
		if err != nil {
			return nil, err
		}
		if e.Ret.Kind == ffi.KindString && out != "" {
			lines = append(lines, "rt_release("+out+");")
		}
		if len(lines) == 0 && out != "" {
			// 错误码即返回值（句柄 close）：表达式自含调用，语句化执行。
			return []string{out + ";"}, nil
		}
		return lines, nil
	}
	if expr, hit, err := s.selfMethodCall(id.Name, call.Args); err != nil {
		return nil, err
	} else if hit {
		out := append([]string{}, s.pending...)
		s.pending = nil
		return append(out, expr+";"), nil
	}
	args, err := s.callArgs(call.Args)
	if err != nil {
		return nil, err
	}
	cn, err := s.g.callName(id.Name, call.TypeArgs, len(call.Args))
	if err != nil {
		return nil, err
	}
	return []string{cn + "(" + strings.Join(args, ", ") + ");"}, nil
}

// emitSwitch 生成 switch（S1 §6.8：无隐式贯穿，按源码顺序首个匹配）。
// 发射为 do{ if/else-if }while(0)：case 体内 break 自然退出 switch。
func (s *scope) emitSwitch(n *xfront.SwitchStmt) ([]string, error) {
	vt, err := s.exprType(n.Value)
	if err != nil {
		return nil, err
	}
	var out []string
	var valExpr string
	isStr := vt == "rt_string *"
	if isStr {
		lines, err := s.strExpr(n.Value)
		if err != nil {
			return nil, err
		}
		out = append(out, lines...)
		valExpr = lastVar(lines)
	} else {
		v, err := s.intExpr(n.Value)
		if err != nil {
			return nil, err
		}
		out = append(out, s.pending...)
		s.pending = nil
		valExpr = v
	}
	// 先求值全部 case 表达式（无副作用常量/项），保留临时字符串。
	conds := make([]string, 0, len(n.Cases))
	var caseTemps []string
	for _, c := range n.Cases {
		if isStr {
			lines, err := s.strExpr(c.Expr)
			if err != nil {
				return nil, err
			}
			out = append(out, lines...)
			t := lastVar(lines)
			caseTemps = append(caseTemps, t)
			conds = append(conds, "xn_str_eq("+valExpr+", "+t+")")
			continue
		}
		v, err := s.intExpr(c.Expr)
		if err != nil {
			return nil, err
		}
		out = append(out, s.pending...)
		s.pending = nil
		conds = append(conds, valExpr+" == ("+v+")")
	}
	out = append(out, "    do {")
	for i, c := range n.Cases {
		kw := "if"
		if i > 0 {
			kw = "else if"
		}
		bodySc := s.newChild()
		bodySc.kind = "switch"
		body, err := bodySc.emitBlock(c.Stmts)
		if err != nil {
			return nil, err
		}
		out = append(out, "        "+kw+" ("+conds[i]+") {")
		out = append(out, reindent(splitLines(body), "            ")...)
		out = append(out, "        }")
	}
	if n.Default != nil {
		bodySc := s.newChild()
		bodySc.kind = "switch"
		body, err := bodySc.emitBlock(n.Default.Stmts)
		if err != nil {
			return nil, err
		}
		out = append(out, "        else {")
		out = append(out, reindent(splitLines(body), "            ")...)
		out = append(out, "        }")
	}
	out = append(out, "    } while (0);")
	for _, t := range caseTemps {
		out = append(out, "    rt_release("+t+");")
	}
	if isStr {
		out = append(out, "    rt_release("+valExpr+");")
	}
	return out, nil
}

// emitForIn 生成 `for x in src { }`：容器遍历（M4.4a；整型区间随区间表达式批次）。
func (s *scope) emitForIn(n *xfront.ForStmt) ([]string, error) {
	// 源：容器局部变量或字段链（self.kids 等，M5.1-b）
	srcName, srcC, err := recvCName(n.Src, s)
	if err != nil || !isContainerC(srcC) {
		return nil, fmt.Errorf("codegen：for-in 源 %T 不是容器（M4.4a/M5.1-b 范围）", n.Src)
	}
	elem, ok := containerElem(srcC)
	if !ok {
		return nil, fmt.Errorf("codegen：for-in 元素类型推不出（%s）", srcC)
	}
	acc := srcName
	if strings.HasPrefix(srcC, "xn_set_") {
		acc += "->a"
	}
	bodySc := s.newChild()
	bodySc.kind = "loop"
	bodySc.locals = map[string]string{}
	if s.locals != nil {
		for k, v := range s.locals {
			bodySc.locals[k] = v
		}
	}
	bodySc.locals[n.Var] = elem
	body, err := bodySc.emitBlock(n.Body.Stmts)
	if err != nil {
		return nil, err
	}
	idx := s.tmp()
	lines := []string{
		"for (size_t " + idx + " = 0; " + idx + " < " + acc + "->len; " + idx + "++) {",
		"    " + elem + " " + n.Var + " = " + acc + "->data[" + idx + "];",
	}
	lines = append(lines, reindent(splitLines(body), "    ")...)
	if !s.g.inDeinit {
		lines = append(lines, "    xn_gc_safepoint();")
	}
	lines = append(lines, "}")
	return lines, nil
}

// emitPrint 按静态类型分派 print：String（自有临时）/Bool/Int。
// 借用形态（容器元素 get/下标读）不释放——所有权在容器。
func (s *scope) emitPrint(e xfront.Expr) ([]string, error) {
	if _, ok := e.(*xfront.NullLit); ok {
		return []string{"xn_print_null();"}, nil
	}
	t, err := s.exprType(e)
	if err != nil {
		return nil, err
	}
	if s.g.isTupleC(t) {
		lines, v, err := s.tupleStr(e, t)
		if err != nil {
			return nil, err
		}
		return append(lines, "xn_print_str("+v+");", "rt_release("+v+");"), nil
	}
	if s.g.isSimpleEnumC(t) || s.g.isDataEnumC(t) {
		fn := "xn_enum_" + strings.TrimSuffix(strings.TrimPrefix(t, "xn_Enum_"), " *") + "_name"
		v, err := s.intExpr(e)
		if err != nil {
			return nil, err
		}
		tmp := s.tmp()
		out := append([]string{}, s.pending...)
		s.pending = nil
		out = append(out, "rt_string *"+tmp+" = "+fn+"("+v+");", "xn_print_str("+tmp+");", "rt_release("+tmp+");")
		return out, nil
	}
	switch t {
	case "xn_opt_i", "xn_opt_b", "xn_opt_s":
		lines, v, err := s.optExpr(e, t)
		if err != nil {
			return nil, err
		}
		printFn := "xn_print_int"
		if t == "xn_opt_b" {
			printFn = "xn_print_bool"
		} else if t == "xn_opt_s" {
			printFn = "xn_print_str"
		}
		out := append([]string{}, lines...)
		out = append(out, "if ("+v+".has) { "+printFn+"("+v+".v); } else { xn_print_null(); }")
		return out, nil
	case "rt_string *":
		if s.isBorrowExpr(e) {
			v, err := s.borrowStr(e)
			if err != nil {
				return nil, err
			}
			return []string{"xn_print_str(" + v + ");"}, nil
		}
		lines, err := s.strExpr(e)
		if err != nil {
			return nil, err
		}
		tv := lastVar(lines)
		return append(lines, "xn_print_str("+tv+");", "rt_release("+tv+");"), nil
	case "int":
		v, err := s.boolExpr(e)
		if err != nil {
			return nil, err
		}
		return []string{"xn_print_bool(" + v + ");"}, nil
	case "int64_t", "int32_t":
		v, err := s.intExpr(e)
		if err != nil {
			return nil, err
		}
		return []string{"xn_print_int(" + v + ");"}, nil
	}
	return nil, fmt.Errorf("codegen：print 实参类型 %s 未支持（M4.4a 范围）", t)
}

// isBorrowExpr 判断字符串表达式是否为借用（不拥有所有权）。
func (s *scope) isBorrowExpr(e xfront.Expr) bool {
	switch n := e.(type) {
	case *xfront.Index:
		return true
	case *xfront.Member:
		return true
	case *xfront.Call:
		if mem, ok := n.Callee.(*xfront.Member); ok && mem.Name == "get" {
			if _, rc, err := recvCName(mem.X, s); err == nil && isContainerC(rc) {
				return true
			}
		}
	}
	return false
}

// borrowStr 生成借用字符串表达式（不产生所有权）。
func (s *scope) borrowStr(e xfront.Expr) (string, error) {
	switch n := e.(type) {
	case *xfront.Member:
		recvName, recvC, err := recvCName(n.X, s)
		if err != nil {
			return "", err
		}
		if ci, ok := s.g.classOfC(recvC); ok {
			if f, ok2 := ci.fieldOf(n.Name); ok2 && f.isStr {
				return recvName + "->" + f.cname, nil
			}
		}
		return "", fmt.Errorf("codegen：String 成员 %s 借用不可判定（M4.4b 范围）", n.Name)
	case *xfront.Index:
		return s.indexRead(n)
	case *xfront.Call:
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if rn, rc, err := recvCName(mem.X, s); err == nil && isContainerC(rc) {
				if v, hit, err := s.containerMemberValue(rc, rn, mem.Name, n.Args); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
		}
	}
	return "", fmt.Errorf("codegen：借用字符串表达式 %T 未支持（M4.4a 范围）", e)
}

// boolExpr 生成 C 布尔值表达式。
func (s *scope) boolExpr(e xfront.Expr) (string, error) {
	if c, err := s.cond(e); err == nil {
		return c, nil
	}
	return s.intExpr(e)
}

func (s *scope) isStrShape(e xfront.Expr) bool {
	switch n := e.(type) {
	case *xfront.StrLitExpr:
		return true
	case *xfront.Binary:
		if n.Op == "+" {
			return s.isStrShape(n.L)
		}
	}
	return false
}

// emitLocalDecl 局部声明。
func (s *scope) emitLocalDecl(n *xfront.LocalDeclStmt) ([]string, error) {
	var tc string
	var err error
	if n.Type == nil {
		// var 推断（S1 §5.1）：编译期按初始化式求 C 类型。
		if n.Init == nil {
			return nil, fmt.Errorf("codegen：var 声明缺少初始化式（sema 应拒绝）")
		}
		tc, err = s.exprType(n.Init)
	} else {
		tc, err = s.g.cType(n.Type)
	}
	if err != nil {
		return nil, err
	}
	// try 通用解包（Result<T,String> → T）：类/struct/枚举/协议/String/标量统一走
	// `Result temp = call; ... T name = temp.v`（INT-01/BND-15 集成）。
	if n.Init != nil {
		if u, ok := n.Init.(*xfront.Unary); ok && u.Op == "try" {
			rt, err := s.exprType(u.X)
			if err != nil {
				return nil, err
			}
			if !strings.HasPrefix(rt, "xn_Result_") {
				return nil, fmt.Errorf("codegen：try 目标不是 Result（%s）", rt)
			}
			t := s.tmp()
			lines, err := s.emitTryInto(rt, t, u.X)
			if err != nil {
				return nil, err
			}
			s.locals[n.Name] = tc
			if strings.HasPrefix(tc, "xn_Result_") {
				return append(lines, tc+" "+n.Name+" = "+t+";"), nil
			}
			switch {
			case tc == "rt_string *", isClassPtr(tc), s.g.isProtoC(tc), isHandlePtr(tc), tc == "xrt_bytes_obj *":
				s.defers = append(s.defers, deferItem{name: n.Name, lines: []string{"rt_release(" + n.Name + ");"}})
			}
			return append(lines, tc+" "+n.Name+" = "+t+".v;"), nil
		}
	}
	// Any/Object 装箱局部（S3 §3）：GC 盒引用，不做 retain/release。
	if s.g.isAnyC(tc) {
		lines, v, err := s.anyExpr(n.Init)
		if err != nil {
			return nil, err
		}
		s.locals[n.Name] = tc
		return append(lines, tc+" "+n.Name+" = "+v+";"), nil
	}
	if s.g.isTupleC(tc) {
		s.locals[n.Name] = tc
		if n.Init == nil {
			return []string{tc + " " + n.Name + " = (" + tc + "){0};"}, nil
		}
		lines, v, err := s.tupleExpr(n.Init, tc)
		if err != nil {
			return nil, err
		}
		return append(lines, tc+" "+n.Name+" = "+v+";"), nil
	}
	// 结构体值局部（S2 §3.3）：C 结构体赋值即整值复制。
	if s.g.isStructC(tc) {
		s.locals[n.Name] = tc
		if n.Init == nil {
			return []string{tc + " " + n.Name + " = (" + tc + "){0};"}, nil
		}
		lines, expr, err := s.structValue(n.Init, tc)
		if err != nil {
			return nil, err
		}
		return append(lines, tc+" "+n.Name+" = "+expr+";"), nil
	}
	// 协议类型局部（S2 §4.4）：对象指针强引用；null 为零值。
	if s.g.isProtoC(tc) {
		s.locals[n.Name] = tc
		s.defers = append(s.defers, deferItem{name: n.Name, lines: []string{"rt_release((void *)" + n.Name + ");"}})
		if n.Init == nil {
			return []string{tc + " " + n.Name + " = NULL;"}, nil
		}
		lines, expr, owned, err := s.protoValue(n.Init)
		if err != nil {
			return nil, err
		}
		if !owned {
			t := s.tmp()
			lines = append(lines, "void *"+t+" = rt_retain((void *)"+expr+");")
			expr = t
		}
		return append(lines, tc+" "+n.Name+" = "+expr+";"), nil
	}
	if strings.HasPrefix(tc, "xn_opt_") {
		lines, v := []string{}, "("+tc+"){0, 0}"
		if n.Init != nil {
			ls, expr, err := s.optExpr(n.Init, tc)
			if err != nil {
				return nil, err
			}
			lines, v = ls, expr
		}
		s.locals[n.Name] = tc
		return append(lines, tc+" "+n.Name+" = "+v+";"), nil
	}
	if tc == "xrt_text *" {
		lines, out, err := s.textExpr(n.Init)
		if err != nil {
			return nil, err
		}
		s.locals[n.Name] = tc
		return append(lines, "xrt_text *"+n.Name+" = "+out+";"), nil
	}
	if tc == "xrt_sb *" {
		lines, out, err := s.sbExpr(n.Init)
		if err != nil {
			return nil, err
		}
		s.locals[n.Name] = tc
		return append(lines, "xrt_sb *"+n.Name+" = "+out+";"), nil
	}
	if isHandlePtr(tc) {
		lines, out, err := s.handleExpr(n.Init)
		if err != nil {
			return nil, err
		}
		s.locals[n.Name] = tc
		s.defers = append(s.defers, deferItem{name: n.Name, lines: []string{"rt_release(" + n.Name + ");"}})
		return append(lines, "xrt_handle *"+n.Name+" = "+out+";"), nil
	}
	if tc == "xrt_bytes_obj *" {
		lines, out, err := s.bytesExpr(n.Init)
		if err != nil {
			return nil, err
		}
		s.locals[n.Name] = tc
		s.defers = append(s.defers, deferItem{name: n.Name, lines: []string{"rt_release(" + n.Name + ");"}})
		return append(lines, "xrt_bytes_obj *"+n.Name+" = "+out+";"), nil
	}
	// S3-04：Text / StringBuilder 局部（GC 引用；根登记由 S3-02 包装统一添加）。
	if tc == "xrt_text *" {
		lines, v, err := s.textExpr(n.Init)
		if err != nil {
			return nil, err
		}
		s.locals[n.Name] = tc
		return append(lines, tc+" "+n.Name+" = "+v+";"), nil
	}
	if tc == "xrt_sb *" {
		lines, v, err := s.sbExpr(n.Init)
		if err != nil {
			return nil, err
		}
		s.locals[n.Name] = tc
		return append(lines, tc+" "+n.Name+" = "+v+";"), nil
	}
	// XDK-05：同步原语句柄局部（ARC 资源；不参与 GC 根登记）。
	if isSyncHandleC(tc) {
		lines, v, err := s.syncValueExpr(n.Init, tc)
		if err != nil {
			return nil, err
		}
		if c, ok := n.Init.(*xfront.Call); ok {
			if e, err := s.syncElemType(c, ""); err == nil {
				s.g.syncElems[n.Name] = e
			}
		}
		s.locals[n.Name] = tc
		return append(lines, tc+" "+n.Name+" = "+v+";"), nil
	}
	// S5-04：任务/上下文句柄局部（ARC；不参与 GC 根登记）。
	if isTaskHandleC(tc) {
		lines, v, err := s.taskValueExpr(n.Init, tc)
		if err != nil {
			return nil, err
		}
		s.locals[n.Name] = tc
		// 作用域退出释放本地句柄；只有“拥有型”初始化才释放（标识符/borrow 不重复释放）。
		// TaskGroup 未 close 时，release 会触发 group_deinit 的合同诊断（S5 §3.2）。
		if taskValueOwned(n.Init, tc) {
			s.defers = append(s.defers, deferItem{name: n.Name, lines: []string{"rt_release(" + n.Name + ");"}})
		}
		return append(lines, tc+" "+n.Name+" = "+v+";"), nil
	}
	if isClassPtr(tc) {
		if n.Init == nil {
			return nil, fmt.Errorf("codegen：类实例局部声明需要 new 初始化（M4.4b 范围）")
		}
		if nw, ok := n.Init.(*xfront.New); ok {
			// S3-03：Escape=none 且未发布的局部 → 栈对象（无分配器调用）。
			if s.g.classIsStack(tc) && !s.localEscaped(n.Name) {
				out, err := s.emitStackNew(nw, tc, n.Name)
				if err != nil {
					return nil, err
				}
				s.locals[n.Name] = tc
				return out, nil
			}
			ctor, err := s.emitNewClass(nw)
			if err != nil {
				return nil, err
			}
			if nt, ok := nw.Type.(*xfront.NamedType); ok {
				if ci, ok := s.g.classOf(typeName(nt)); ok && ci.cname+" *" != tc {
					ctor = "(" + tc + ")(" + ctor + ")" // 子类 → 父类/协议（S2 §5.2）
				}
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			if !s.g.classIsGC(tc) {
				s.defers = append(s.defers, deferItem{name: n.Name, lines: []string{"rt_release(" + n.Name + ");"}})
			}
			s.locals[n.Name] = tc
			return append(out, tc+" "+n.Name+" = "+ctor+";"), nil
		}
		if _, ok := n.Init.(*xfront.NullLit); ok {
			s.defers = append(s.defers, deferItem{name: n.Name, lines: []string{"rt_release(" + n.Name + ");"}})
			s.locals[n.Name] = tc
			return []string{tc + " " + n.Name + " = NULL;"}, nil
		}
		if id, ok := n.Init.(*xfront.IdentExpr); ok {
			r := s.cRef(id.Name)
			if sc, ok := s.localCType(id.Name); ok && sc != tc {
				r = "(" + tc + ")(" + r + ")"
			}
			s.defers = append(s.defers, deferItem{name: n.Name, lines: []string{"rt_release(" + n.Name + ");"}})
			s.locals[n.Name] = tc
			return []string{tc + " " + n.Name + " = rt_retain(" + r + ");"}, nil
		}
		if bin, ok := n.Init.(*xfront.Binary); ok && (bin.Op == "as?" || bin.Op == "as") {
			v, err := s.intExpr(bin)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			s.defers = append(s.defers, deferItem{name: n.Name, lines: []string{"rt_release(" + n.Name + ");"}})
			s.locals[n.Name] = tc
			return append(out, tc+" "+n.Name+" = ("+tc+")("+v+");"), nil
		}
		if cl, ok := n.Init.(*xfront.Call); ok {
			expr, owns, err := s.classCallExpr(cl)
			if err != nil {
				return nil, err
			}
			lines := append([]string{}, s.pending...)
			s.pending = nil
			if owns && !s.g.classIsGC(tc) {
				s.defers = append(s.defers, deferItem{name: n.Name, lines: []string{"rt_release(" + n.Name + ");"}})
			}
			s.locals[n.Name] = tc
			return append(lines, tc+" "+n.Name+" = "+expr+";"), nil
		}
		return nil, fmt.Errorf("codegen：类实例局部初始值只支持 new/调用（M5.1-b 范围：%T）", n.Init)
	}
	if isContainerC(tc) {
		if n.Init == nil {
			return nil, fmt.Errorf("codegen：容器局部声明需要初始化（M4.4a 范围）")
		}
		lines, v, err := s.valExpr(n.Init, tc)
		if err != nil {
			return nil, err
		}
		s.locals[n.Name] = tc
		return append(lines, tc+" "+n.Name+" = "+v+";"), nil
	}
	// Result 内联值（§10/§9）：Ok/Err 构造、函数返回、变量/字段复制。
	if strings.HasPrefix(tc, "xn_Result_") {
		if n.Init != nil {
			if u, ok := n.Init.(*xfront.Unary); ok && u.Op == "try" {
				s.locals[n.Name] = tc
				return s.emitTryInto(tc, n.Name, u.X)
			}
		}
		v, err := s.resultExpr(n.Init, tc)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		s.locals[n.Name] = tc
		return append(out, tc+" "+n.Name+" = "+v+";"), nil
	}
	switch tc {
	case "rt_string *":
		if n.Init == nil {
			return []string{"rt_string *" + n.Name + " = rt_string_from_c(\"\");"}, nil
		}
		// try 形态：Result 局部 + 解包（此处类型是 String，不支持）
		lines, err := s.strExpr(n.Init)
		if err != nil {
			return nil, err
		}
		t := lastVar(lines)
		// 所有权移交局部：函数退出时释放（追加到本层 defer）
		s.defers = append(s.defers, deferItem{lines: []string{"rt_release(" + n.Name + ");"}})
		s.locals[n.Name] = tc
		// 把最后一行的临时声明直接改名为目标变量（保留其前置语句）
		out := append([]string{}, lines[:len(lines)-1]...)
		last := strings.Replace(lines[len(lines)-1], "rt_string *"+t+" =", "rt_string *"+n.Name+" =", 1)
		return append(out, last), nil
	default:
		// Int/Bool；try 形态解包 .v
		if n.Init != nil {
			if u, ok := n.Init.(*xfront.Unary); ok && u.Op == "try" {
				t := s.tmp()
				lines, err := s.emitTryInto("xn_Result_Int_String", t, u.X)
				if err != nil {
					return nil, err
				}
				s.locals[n.Name] = tc
				return append(lines, tc+" "+n.Name+" = "+t+".v;"), nil
			}
			v, err := s.intExpr(n.Init)
			if err != nil {
				return nil, err
			}
			s.locals[n.Name] = tc
			return []string{tc + " " + n.Name + " = " + v + ";"}, nil
		}
		s.locals[n.Name] = tc
		return []string{tc + " " + n.Name + " = 0;"}, nil
	}
}

// emitTryInto 生成 try 传播：临时 Result ← 调用；失败则接管清理并返回。
// 目标变量名 name 接收整个 Result 结构。
func (s *scope) emitTryInto(resultC, name string, callExpr xfront.Expr) ([]string, error) {
	call, ok := callExpr.(*xfront.Call)
	if !ok {
		return nil, fmt.Errorf("codegen：try 实参必须是调用，got %T", callExpr)
	}
	// S6-04：资源读取的 Result 先由内建降级构造，再按 try 传播。
	if id, ok := call.Callee.(*xfront.IdentExpr); ok {
		if id.Name == "readResource" || id.Name == "readResourceText" || id.Name == "listResources" {
			lines, expr, err := s.s604ResultCall(id.Name, call, resultC)
			if err != nil {
				return nil, err
			}
			lines = append(lines, resultC+" "+name+" = "+expr+";")
			lines = append(lines, "if (!"+name+".ok) {")
			lines = append(lines, "    xn_ret = "+name+";")
			lines = append(lines, reindent(splitLines(strings.TrimSuffix(s.emitCleanup(true, ""), "\n")), "        ")...)
			lines = append(lines, "    return xn_ret;", "}")
			return lines, nil
		}
	}
	var callStr string
	switch callee := call.Callee.(type) {
	case *xfront.IdentExpr:
		args, err := s.callArgs(call.Args)
		if err != nil {
			return nil, err
		}
		cn, err := s.g.callName(callee.Name, call.TypeArgs, len(call.Args))
		if err != nil {
			return nil, err
		}
		callStr = cn + "(" + strings.Join(args, ", ") + ")"
	case *xfront.Member:
		if expr, _, hit, err := s.tryFactoryCall(callee, call); err != nil {
			return nil, err
		} else if hit {
			callStr = expr
			break
		}
		if expr, _, hit, err := s.staticClassCall(callee, call); err != nil {
			return nil, err
		} else if hit {
			callStr = expr
			break
		}
		recvName, recvC, err := recvCName(callee.X, s)
		if err != nil {
			return nil, err
		}
		switch {
		case s.g.isStructC(recvC):
			ci, _ := s.g.structOfC(recvC)
			m, ok := s.methodFor(ci, callee.Name, call.Args)
			if !ok {
				return nil, fmt.Errorf("codegen：结构体 %s 没有方法 %s", ci.decl.Name, callee.Name)
			}
			expr, err := s.methodCall(ci, m, "(&"+recvName+")", call.Args)
			if err != nil {
				return nil, err
			}
			callStr = expr
		case s.g.isProtoC(recvC):
			expr, _, err := s.protoDispatch(callee, call.Args)
			if err != nil {
				return nil, err
			}
			callStr = expr
		default:
			ci, ok := s.g.classOfC(recvC)
			if !ok {
				return nil, fmt.Errorf("codegen：try 调用目标 %T 未支持", call.Callee)
			}
			m, ok := s.methodFor(ci, callee.Name, call.Args)
			if !ok {
				return nil, fmt.Errorf("codegen：类 %s 没有方法 %s", ci.decl.Name, callee.Name)
			}
			expr, err := s.methodCall(ci, m, recvName, call.Args)
			if err != nil {
				return nil, err
			}
			callStr = expr
		}
	default:
		return nil, fmt.Errorf("codegen：try 调用目标 %T 未支持", call.Callee)
	}
	pre := append([]string{}, s.pending...)
	s.pending = nil
	lines := append(pre, resultC+" "+name+" = "+callStr+";", "if (!"+name+".ok) {")
	// try 传播 = 以 Err 返回：全部 defer 执行，errdefer 触发（xn_ret 为 Err）。
	// 外层 Result 值类型可与 try 目标不同（如 Result<Color> → Result<Int>）：
	// 置零后用 Err 通道逐字段转移（BND-15 集成）。
	if !strings.HasPrefix(s.retC, "xn_Result_") {
		return nil, fmt.Errorf("codegen：try 只能用于返回 Result 的函数（当前返回 %s）", s.retC)
	}
	if s.retC == resultC {
		lines = append(lines, "    xn_ret = "+name+";")
	} else {
		lines = append(lines, "    xn_ret = ("+s.retC+"){0};", "    xn_ret.err = "+name+".err;")
	}
	lines = append(lines, reindent(splitLines(strings.TrimSuffix(s.emitCleanup(true, ""), "\n")), "        ")...)
	lines = append(lines, "    return xn_ret;", "}")
	return lines, nil
}

func (s *scope) emitAssign(n *xfront.AssignStmt) ([]string, error) {
	if n.Op == "+=" || n.Op == "-=" {
		id, ok := n.Target.(*xfront.IdentExpr)
		if !ok {
			return nil, fmt.Errorf("codegen：复合赋值目标 %T 未支持（M6-B0-05 范围）", n.Target)
		}
		tgt := s.cRef(id.Name)
		// 可空/String 目标的复合赋值不在覆盖面内；标量按 Int 展开。
		if tc, ok := s.localCType(id.Name); ok && (tc == "rt_string *" || strings.HasPrefix(tc, "xn_opt_")) {
			return nil, fmt.Errorf("codegen：%s 上的复合赋值 %s 未支持（M6-B0-05 范围）", tc, n.Op)
		}
		if tc, ok := s.g.globals[id.Name]; ok && (tc == "rt_string *" || strings.HasPrefix(tc, "xn_opt_")) {
			return nil, fmt.Errorf("codegen：%s 上的复合赋值 %s 未支持（M6-B0-05 范围）", tc, n.Op)
		}
		v, err := s.intExpr(n.Value)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		op := "+"
		if n.Op == "-=" {
			op = "-"
		}
		return append(out, tgt+" = "+tgt+" "+op+" ("+v+");"), nil
	}
	if n.Op != "=" {
		return nil, fmt.Errorf("codegen：复合赋值 %s 未支持（M4.1 范围）", n.Op)
	}
	// 元组成员赋值（S1 §2.11）：`pair.0 = 2`，目标必须是可赋值元组。
	if tm, ok := n.Target.(*xfront.TupleMember); ok {
		lv, err := s.tupleLValue(tm)
		if err != nil {
			return nil, err
		}
		ec, err := s.exprType(tm)
		if err != nil {
			return nil, err
		}
		ls, v, err := s.tupleElemExpr(n.Value, ec)
		if err != nil {
			return nil, err
		}
		return append(ls, lv+" = "+v+";"), nil
	}
	if mem, ok := n.Target.(*xfront.Member); ok {
		if _, _, isInst := s.g.singletonInstance(mem); isInst {
			return nil, fmt.Errorf("codegen：单例 instance 只读，不能赋值（S2 §9.1）")
		}
		if varName, ct, ok := s.g.singletonStatic(mem); ok {
			if s.g.isGCTypeC(ct) {
				// 静态字段是 GC 全局根：替换时同步根集合。
				var expr string
				var lines []string
				switch v := n.Value.(type) {
				case *xfront.New:
					e, err := s.emitNewClass(v)
					if err != nil {
						return nil, err
					}
					expr = e
					lines = append([]string{}, s.pending...)
					s.pending = nil
				case *xfront.IdentExpr:
					expr = s.cRef(v.Name)
				case *xfront.NullLit:
					expr = "NULL"
				default:
					return nil, fmt.Errorf("codegen：GC 静态字段赋值右值 %T 未支持（BND-10）", n.Value)
				}
				out := append(lines, "xn_root_release("+varName+");", varName+" = "+expr+";")
				out = append(out, "xn_root_hold("+varName+");")
				return out, nil
			}
			switch ct {
			case "rt_string *":
				lines, err := s.strExpr(n.Value)
				if err != nil {
					return nil, err
				}
				out := append([]string{}, lines...)
				out = append(out, "rt_release("+varName+");", varName+" = "+lastVar(lines)+";")
				return out, nil
			default:
				v, err := s.intExpr(n.Value)
				if err != nil {
					return nil, err
				}
				out := append([]string{}, s.pending...)
				s.pending = nil
				return append(out, varName+" = "+v+";"), nil
			}
		}
		return s.emitFieldAssign(mem, n.Value)
	}
	if idx, ok := n.Target.(*xfront.Index); ok {
		return s.emitIndexAssign(idx, n.Value)
	}
	id, ok := n.Target.(*xfront.IdentExpr)
	if !ok {
		return nil, fmt.Errorf("codegen：赋值目标 %T 未支持（M4.1 范围）", n.Target)
	}
	tgt := s.cRef(id.Name)
	if tgt == "" {
		return nil, fmt.Errorf("codegen：结构体赋值目标未支持")
	}
	// 结构体值局部赋值（整值复制）。
	if tc, ok := s.localCType(id.Name); ok && s.g.isStructC(tc) {
		lines, expr, err := s.structValue(n.Value, tc)
		if err != nil {
			return nil, err
		}
		return append(lines, tgt+" = "+expr+";"), nil
	}
	// 元组局部/顶层字段赋值（S1 §2.11）：C 结构体整值赋值即整值复制。
	if u, ok := n.Value.(*xfront.Unary); ok && u.Op == "try" {
		var tc string
		if c, ok := s.localCType(id.Name); ok {
			tc = c
		} else if c, ok := s.g.globals[id.Name]; ok {
			tc = c
		} else {
			return nil, fmt.Errorf("codegen：try 赋值目标 %s 类型未知", id.Name)
		}
		rt, err := s.exprType(u.X)
		if err != nil {
			return nil, err
		}
		if !strings.HasPrefix(rt, "xn_Result_") {
			return nil, fmt.Errorf("codegen：try 目标不是 Result（%s）", rt)
		}
		t := s.tmp()
		out, err := s.emitTryInto(rt, t, u.X)
		if err != nil {
			return nil, err
		}
		if strings.HasPrefix(tc, "xn_Result_") {
			return append(out, tgt+" = "+t+";"), nil
		}
		switch {
		case tc == "rt_string *", isClassPtr(tc), s.g.isProtoC(tc), isHandlePtr(tc), tc == "xrt_bytes_obj *":
			out = append(out, "rt_release("+tgt+");")
		}
		return append(out, tgt+" = "+t+".v;"), nil
	}
	if tc, ok := s.localCType(id.Name); ok && s.g.isTupleC(tc) {
		lines, v, err := s.tupleExpr(n.Value, tc)
		if err != nil {
			return nil, err
		}
		return append(lines, tgt+" = "+v+";"), nil
	}
	if tc, ok := s.g.globals[id.Name]; ok && s.g.isTupleC(tc) {
		if _, shadowed := s.locals[id.Name]; !shadowed && (s.params == nil || !s.params[id.Name]) {
			lines, v, err := s.tupleExpr(n.Value, tc)
			if err != nil {
				return nil, err
			}
			return append(lines, tgt+" = "+v+";"), nil
		}
	}
	if tc, ok := s.localCType(id.Name); ok && s.g.isProtoC(tc) {
		lines, expr, owned, err := s.protoValue(n.Value)
		if err != nil {
			return nil, err
		}
		if !owned {
			t := s.tmp()
			lines = append(lines, "void *"+t+" = rt_retain((void *)"+expr+");")
			expr = t
		}
		out := append([]string{}, lines...)
		out = append(out, "rt_release((void *)"+tgt+");", tgt+" = "+expr+";")
		return out, nil
	}
	// 句柄局部赋值（B0-07c）：Call/Ident 右值；旧句柄释放。
	if tc, ok := s.localCType(id.Name); ok && isHandlePtr(tc) {
		switch v := n.Value.(type) {
		case *xfront.Call:
			lines, expr, err := s.handleExpr(v)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, lines...)
			out = append(out, "rt_release("+tgt+");")
			out = append(out, tgt+" = "+expr+";")
			return out, nil
		case *xfront.IdentExpr:
			r := s.cRef(v.Name)
			return []string{
				"rt_retain(" + r + ");",
				"rt_release(" + tgt + ");",
				tgt + " = " + r + ";",
			}, nil
		}
		return nil, fmt.Errorf("codegen：句柄赋值右值 %T 未支持（B0-07c 范围）", n.Value)
	}
	// 实例字段赋值（§5.8）：类内非限定名解析到 self->field。
	if s.self != nil {
		if ft, ok := s.self.types[id.Name]; ok {
			field := s.cRef(id.Name)
			switch {
			case ft == "rt_string *":
				if _, isNull := n.Value.(*xfront.NullLit); isNull {
					return []string{"rt_release(" + field + ");", field + " = NULL;"}, nil
				}
				lines, err := s.strExpr(n.Value)
				if err != nil {
					return nil, err
				}
				out := append([]string{}, lines...)
				out = append(out, "rt_release("+field+");")
				out = append(out, field+" = "+lastVar(lines)+";")
				return out, nil
			case isClassPtr(ft):
				if s.g.classIsGC(ft) {
					lines, v, _, err := s.classValueExpr(n.Value)
					if err != nil {
						return nil, err
					}
					out := append([]string{}, lines...)
					return append(out, field+" = "+v+";"), nil
				}
				switch v := n.Value.(type) {
				case *xfront.IdentExpr:
					r := s.cRef(v.Name)
					return []string{"rt_retain(" + r + ");", "rt_release(" + field + ");", field + " = " + r + ";"}, nil
				case *xfront.New:
					ctor, err := s.emitNewClass(v)
					if err != nil {
						return nil, err
					}
					t := s.tmp()
					out := append([]string{}, s.pending...)
					s.pending = nil
					out = append(out, ft+" "+t+" = "+ctor+";", "rt_release("+field+");", field+" = "+t+";")
					return out, nil
				}
				return nil, fmt.Errorf("codegen：字段 %s 的类引用赋值右值 %T 未支持（M5.1-c 范围）", id.Name, n.Value)
			default:
				v, err := s.intExpr(n.Value)
				if err != nil {
					return nil, err
				}
				out := append([]string{}, s.pending...)
				s.pending = nil
				return append(out, field+" = "+v+";"), nil
			}
		}
	}
	// 顶层字段赋值（ENTRY-01：Int/Bool/String）
	if tc, ok := s.g.globals[id.Name]; ok {
		if _, shadowed := s.locals[id.Name]; !shadowed && (s.params == nil || !s.params[id.Name]) {
			if tc == "rt_string *" {
				lines, err := s.strExpr(n.Value)
				if err != nil {
					return nil, err
				}
				out := append([]string{}, lines...)
				out = append(out, "xn_root_release("+tgt+");", tgt+" = "+lastVar(lines)+";", "xn_root_hold("+tgt+");")
				return out, nil
			}
			if tc == "xrt_text *" || tc == "xrt_sb *" {
				var lines []string
				var v string
				var err error
				if tc == "xrt_text *" {
					lines, v, err = s.textExpr(n.Value)
				} else {
					lines, v, err = s.sbExpr(n.Value)
				}
				if err != nil {
					return nil, err
				}
				out := append([]string{}, lines...)
				out = append(out, "xn_root_release("+tgt+");", tgt+" = "+v+";", "xn_root_hold("+tgt+");")
				return out, nil
			}
			v, err := s.intExpr(n.Value)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			return append(out, tgt+" = "+v+";"), nil
		}
	}
	// 类引用局部：按 §3.3 纪律——旧值释放；新值为 +1 产物（调用/new）则接管，
	// 为借用（变量/容器 get）则 retain 后接管。消除此前「裸赋值泄漏旧值」。
	if tc, ok := s.localCType(id.Name); ok && isClassPtr(tc) {
		if s.g.classIsGC(tc) {
			lines, v, _, err := s.classValueExpr(n.Value)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, lines...)
			return append(out, tgt+" = "+v+";"), nil
		}
		switch v := n.Value.(type) {
		case *xfront.Call:
			// 顺序关键：先求值（+1 产物入临时），再放旧，后赋值——
			// 若先放旧，mkBin(lhs,…) 内部 retain 将命中已终结对象（复活 fatal）
			expr, _, err := s.classCallExpr(v)
			if err != nil {
				return nil, err
			}
			t := s.tmp()
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, tc+" "+t+" = "+expr+";")
			out = append(out, "rt_release("+tgt+");")
			out = append(out, tgt+" = "+t+";")
			return out, nil
		case *xfront.New:
			ctor, err := s.emitNewClass(v)
			if err != nil {
				return nil, err
			}
			t := s.tmp()
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, tc+" "+t+" = "+ctor+";")
			out = append(out, "rt_release("+tgt+");")
			out = append(out, tgt+" = "+t+";")
			return out, nil
		case *xfront.IdentExpr:
			name := s.cRef(v.Name)
			return []string{
				"rt_retain(" + name + ");",
				"rt_release(" + tgt + ");",
				tgt + " = " + name + ";",
			}, nil
		}
		return nil, fmt.Errorf("codegen：类引用赋值右值 %T 未支持（M5.1-c 范围）", n.Value)
	}
	// String 局部：新串接管，旧串释放（§9.2 不可变字符串）
	if tc, ok := s.localCType(id.Name); ok && tc == "rt_string *" {
		lines, err := s.strExpr(n.Value)
		if err != nil {
			return nil, err
		}
		t := lastVar(lines)
		out := append([]string{}, lines...)
		out = append(out, "rt_release("+tgt+");", tgt+" = "+t+";", "xn_root_add("+tgt+");")
		if !s.g.inDeinit {
			out = append(out, "xn_gc_safepoint();")
		}
		return out, nil
	}
	// Result 局部赋值（内联值整值复制 / Ok/Err 构造）。
	if tc, ok := s.localCType(id.Name); ok && strings.HasPrefix(tc, "xn_Result_") {
		v, err := s.resultExpr(n.Value, tc)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return append(out, tgt+" = "+v+";"), nil
	}
	// S3-04：Text/StringBuilder 局部赋值（GC 引用，不计数）。
	if tc, ok := s.localCType(id.Name); ok && (tc == "xrt_text *" || tc == "xrt_sb *") {
		var lines []string
		var v string
		var err error
		if tc == "xrt_text *" {
			lines, v, err = s.textExpr(n.Value)
		} else {
			lines, v, err = s.sbExpr(n.Value)
		}
		if err != nil {
			return nil, err
		}
		out := append([]string{}, lines...)
		out = append(out, tgt+" = "+v+";", "xn_root_add("+tgt+");")
		if !s.g.inDeinit {
			out = append(out, "xn_gc_safepoint();")
		}
		return out, nil
	}
	v, err := s.intExpr(n.Value)
	if err != nil {
		return nil, err
	}
	out := append([]string{}, s.pending...)
	s.pending = nil
	// S3-02：GC 引用局部赋值后登记栈根（旧值保留登记到块退出）。
	if tc, ok := s.localCType(id.Name); ok && s.g.isGCRootC(tc) {
		out = append(out, tgt+" = "+v+";", "xn_root_add("+tgt+");")
		if !s.g.inDeinit {
			out = append(out, "xn_gc_safepoint();")
		}
		return out, nil
	}
	// 顶层字段是全局根：替换时同步根集合（持有计数；与栈槽共享对象安全）。
	if tc, ok := s.g.globals[id.Name]; ok && s.g.isGCRootC(tc) {
		out = append(out, "xn_root_release("+tgt+");", tgt+" = "+v+";", "xn_root_hold("+tgt+");")
		return out, nil
	}
	return append(out, tgt+" = "+v+";"), nil
}

func (s *scope) emitReturn(n *xfront.ReturnStmt) ([]string, error) {
	if s.isCtor {
		if n.Value != nil {
			return nil, fmt.Errorf("codegen：构造器不能带返回值（S2 §6.3）")
		}
		out := splitLines(s.emitCleanup(true, "    "))
		s.returned = true
		return append(out, "return o;"), nil
	}
	// XDK-05：Mutex.withLock 回调体 return Result → int32 状态（Err kind，Ok 0）。
	if s.lockBody != nil {
		if n.Value == nil {
			out := append([]string{}, s.pending...)
			s.pending = nil
			s.returned = true
			return append(out, "return 0;"), nil
		}
		rc, err := s.exprType(n.Value)
		if err != nil {
			return nil, err
		}
		v, err := s.resultExpr(n.Value, rc)
		if err != nil {
			return nil, err
		}
		tmp := s.tmp()
		out := append([]string{}, s.pending...)
		s.pending = nil
		out = append(out, rc+" "+tmp+" = "+v+";")
		out = append(out, "if (!"+tmp+".ok) { return (int32_t)"+tmp+".err; }")
		out = append(out, "return 0;")
		s.returned = true
		return out, nil
	}
	// S5-04：任务闭包体 return Result → xrt_task_result（值/错误 +1 移交）。
	if s.taskBody != nil {
		if n.Value == nil {
			return nil, fmt.Errorf("codegen：任务闭包必须返回 Result（S5-00 §二）")
		}
		v, err := s.resultExpr(n.Value, s.taskBody.resultC)
		if err != nil {
			return nil, err
		}
		tmp := s.tmp()
		out := append([]string{}, s.pending...)
		s.pending = nil
		out = append(out, s.taskBody.resultC+" "+tmp+" = "+v+";")
		out = append(out, "out->ok = "+tmp+".ok;")
		out = append(out, "out->value = "+taskBox(s.taskBody.memberC, tmp+".v")+";")
		out = append(out, "out->kind = "+tmp+".ok ? XRT_ERR_INVALID_ARGUMENT : "+tmp+".err;")
		out = append(out, "out->error = NULL;")
		if s.g.isGCRootC(s.taskBody.memberC) {
			out = append(out, "xrt_task_root_bind(out->value); /* 任务持有 GC 结果（S5-00 §7.3） */")
		}
		if s.rootMark != "" {
			out = append(out, "xn_root_restore("+s.rootMark+");")
		}
		out = append(out, "xrt_safepoint(); /* 任务体出口（S5-00 §7.2） */")
		out = append(out, "return 0;")
		s.returned = true
		return out, nil
	}
	if s.retC == "void" {
		if n.Value != nil {
			return nil, fmt.Errorf("codegen：void 函数不得带返回值")
		}
		out := []string{}
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return;"), nil
	}
	if s.g.isTupleC(s.retC) && n.Value != nil {
		lines, v, err := s.tupleExpr(n.Value, s.retC)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, lines...)
		out = append(out, s.pending...)
		s.pending = nil
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return "+v+";"), nil
	}
	if s.g.isProtoC(s.retC) && n.Value != nil {
		lines, expr, owned, err := s.protoValue(n.Value)
		if err != nil {
			return nil, err
		}
		if !owned {
			t := s.tmp()
			lines = append(lines, "void *"+t+" = rt_retain((void *)"+expr+");")
			expr = t
		}
		out := append([]string{}, lines...)
		out = append(out, s.pending...)
		s.pending = nil
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return "+expr+";"), nil
	}
	if s.g.isSimpleEnumC(s.retC) && n.Value != nil {
		v, err := s.intExpr(n.Value)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return "+v+";"), nil
	}
	if s.g.isStructC(s.retC) && n.Value != nil {
		lines, expr, err := s.structValue(n.Value, s.retC)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, lines...)
		out = append(out, s.pending...)
		s.pending = nil
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return "+expr+";"), nil
	}
	if isClassPtr(s.retC) && n.Value != nil {
		// 类引用返回：与 String 同一纪律——标识符 retain 后返回（本层 defer release 抵消）；
		// new 调用产物直接移交（无需 retain）。
		if id, ok := n.Value.(*xfront.IdentExpr); ok {
			name := s.cRef(id.Name)
			out := append([]string{}, s.pending...)
			s.pending = nil
			if !s.g.classIsGC(s.retC) {
				out = append(out, "rt_retain("+name+");")
			}
			out = append(out, splitLines(s.emitCleanup(true, "    "))...)
			s.returned = true
			return append(out, "return "+name+";"), nil
		}
		if nw, ok := n.Value.(*xfront.New); ok {
			ctor, err := s.emitNewClass(nw)
			if err != nil {
				return nil, err
			}
			t := s.tmp()
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, retBase(s.retC)+t+" = "+ctor+";")
			out = append(out, splitLines(s.emitCleanup(true, "    "))...)
			s.returned = true
			return append(out, "return "+t+";"), nil
		}
		if cl, ok := n.Value.(*xfront.Call); ok {
			expr, _, err := s.classCallExpr(cl)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			// 引用计数抵消：return 表达式引用的 defer 保护对象先 retain
			//（随后的 cleanup 会 release——与 String 标识符返回同一纪律）。
			// 否则 cleanup 先终结对象，return 调用内 retain 命中复活（fatal）。
			for _, d := range s.defers {
				if d.name != "" && strings.Contains(expr, d.name) {
					out = append(out, "rt_retain("+d.name+");")
				}
			}
			out = append(out, splitLines(s.emitCleanup(true, "    "))...)
			s.returned = true
			return append(out, "return "+expr+";"), nil
			// owns=false（借用）直传；owns=true 时调用方接管 +1 引用
		}
		return nil, fmt.Errorf("codegen：类返回表达式 %T 未支持（M5.1-b 范围：局部变量/new/调用）", n.Value)
	}
	if s.retC == "rt_string *" && n.Value != nil {
		// 标识符返回：retain 后返回（局部清理仍会 release 本层引用）
		if id, ok := n.Value.(*xfront.IdentExpr); ok {
			name := s.cRef(id.Name)
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, "rt_retain("+name+");")
			out = append(out, splitLines(s.emitCleanup(true, "    "))...)
			s.returned = true
			return append(out, "return "+name+";"), nil
		}
		lines, err := s.strExpr(n.Value)
		if err != nil {
			return nil, err
		}
		t := lastVar(lines)
		out := append([]string{}, lines...)
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return "+t+";"), nil
	}
	// Result 返回（内联值）：Ok/Err/wrap/mapErr/report/变量/字段/调用统一走 resultExpr。
	if strings.HasPrefix(s.retC, "xn_Result_") && n.Value != nil {
		v, err := s.resultExpr(n.Value, s.retC)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		out = append(out, "xn_ret = "+v+";")
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return xn_ret;"), nil
	}
	if isIntScalarC(s.retC) && n.Value != nil {
		v, err := s.intExpr(n.Value)
		if err != nil {
			return nil, err
		}
		// 先在清理之前把返回值落到临时变量：容器局部（如 List 参数元素）
		// 的 defer free 会把接收者清零，直接 return 表达式会读到已释放容器（G11）。
		pre := append([]string{}, s.pending...)
		s.pending = nil
		t := s.tmp()
		out := append(pre, s.retC+" "+t+" = "+v+";")
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return "+t+";"), nil
	}
	switch v := n.Value.(type) {
	case *xfront.Call:
		if id, ok := v.Callee.(*xfront.IdentExpr); ok && (id.Name == "Ok" || id.Name == "Err") {
			structLit, err := s.resultExpr(v, s.retC)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, "xn_ret = "+structLit+";")
			out = append(out, splitLines(s.emitCleanup(true, "    "))...)
			s.returned = true
			return append(out, "return xn_ret;"), nil
		}
		// 返回函数调用结果（Result）
		args, err := s.callArgs(v.Args)
		if err != nil {
			return nil, err
		}
		callee, ok := v.Callee.(*xfront.IdentExpr)
		if !ok {
			return nil, fmt.Errorf("codegen：返回调用目标 %T 未支持", v.Callee)
		}
		cn, err := s.g.callName(callee.Name, v.TypeArgs, len(v.Args))
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		out = append(out, "xn_ret = "+cn+"("+strings.Join(args, ", ")+");")
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return xn_ret;"), nil
	}
	return nil, fmt.Errorf("codegen：返回表达式 %T 未支持（M4.1 范围）", n.Value)
}

func (s *scope) emitIf(n *xfront.IfStmt) ([]string, error) {
	cond, err := s.cond(n.Cond)
	if err != nil {
		return nil, err
	}
	thenSc := s.newChild()
	thenBody, err := thenSc.emitBlock(n.Then.Stmts)
	if err != nil {
		return nil, err
	}
	var out []string
	out = append(out, "if ("+cond+") {")
	out = append(out, reindent(splitLines(thenBody), "    ")...)
	if n.Else == nil {
		out = append(out, "}")
		return indentAll(out), nil
	}
	out = append(out, "} else {")
	if eb, ok := n.Else.(*xfront.Block); ok {
		elseSc := s.newChild()
		elseBody, err := elseSc.emitBlock(eb.Stmts)
		if err != nil {
			return nil, err
		}
		out = append(out, reindent(splitLines(elseBody), "    ")...)
	} else {
		elseSc := s.newChild()
		elseLines, err := elseSc.emitStmt(n.Else)
		if err != nil {
			return nil, err
		}
		out = append(out, reindent(elseLines, "    ")...)
	}
	out = append(out, "}")
	return indentAll(out), nil
}

func indentAll(lines []string) []string {
	return reindent(lines, "    ")
}

func splitLines(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(s, "\n")
}

// ---------- 表达式（strExpr 约定：返回的语句序列把结果放进最后一个声明的临时） ----------

func lastVar(lines []string) string {
	l := lines[len(lines)-1]
	// "rt_string *xn_tN = ..." → 取 = 左侧最后一个标识符
	if i := strings.Index(l, "="); i >= 0 {
		f := strings.Fields(l[:i])
		if len(f) > 0 {
			return strings.TrimPrefix(f[len(f)-1], "*")
		}
	}
	return l
}

// strExpr 生成"拥有 rt_string*"的字符串值；结果存入最后一个临时变量。
func (s *scope) strExpr(e xfront.Expr) ([]string, error) {
	if t, err := s.exprType(e); err == nil && (s.g.isSimpleEnumC(t) || s.g.isDataEnumC(t)) {
		fn := "xn_enum_" + strings.TrimSuffix(strings.TrimPrefix(t, "xn_Enum_"), " *") + "_name"
		v, err := s.intExpr(e)
		if err != nil {
			return nil, err
		}
		tmp := s.tmp()
		out := append([]string{}, s.pending...)
		s.pending = nil
		return append(out, "rt_string *"+tmp+" = "+fn+"("+v+");"), nil
	}
	switch n := e.(type) {
	case *xfront.StrLitExpr:
		hasExpr := false
		for _, p := range n.Parts {
			if p.Expr != nil {
				hasExpr = true
				break
			}
		}
		if !hasExpr {
			t := s.tmp()
			return []string{"rt_string *" + t + " = rt_string_from_c(" + cQuote(plainText(n)) + ");"}, nil
		}
		// 插值串（S1 §1.4.4）：静态片段与表达式交错拼接。
		var lines []string
		acc := ""
		for _, p := range n.Parts {
			var piece string
			if p.Expr == nil {
				piece = s.tmp()
				lines = append(lines, "rt_string *"+piece+" = rt_string_from_c("+cQuote(p.Text)+");")
			} else {
				ec, err := s.exprType(p.Expr)
				if err != nil {
					return nil, err
				}
				switch {
				case s.g.isTupleC(ec):
					ls, v, err := s.tupleStr(p.Expr, ec)
					if err != nil {
						return nil, err
					}
					lines = append(lines, ls...)
					piece = v
				case ec == "rt_string *":
					ls, err := s.strExpr(p.Expr)
					if err != nil {
						return nil, err
					}
					lines = append(lines, ls...)
					piece = lastVar(ls)
				case ec == "int":
					v, err := s.boolExpr(p.Expr)
					if err != nil {
						return nil, err
					}
					piece = s.tmp()
					lines = append(lines, "rt_string *"+piece+" = xn_str_bool("+v+");")
				default:
					v, err := s.intExpr(p.Expr)
					if err != nil {
						return nil, err
					}
					piece = s.tmp()
					lines = append(lines, "rt_string *"+piece+" = xn_str_int("+v+");")
				}
				lines = append(lines, s.pending...)
				s.pending = nil
			}
			if acc == "" {
				acc = piece
				continue
			}
			nt := s.tmp()
			lines = append(lines, "rt_string *"+nt+" = xn_concat("+acc+", "+piece+");")
			acc = nt
		}
		if acc == "" {
			acc = s.tmp()
			lines = append(lines, "rt_string *"+acc+" = rt_string_from_c(\"\");")
		}
		return lines, nil
	case *xfront.Binary:
		// Any/Object → String 拆箱（S3 §3）：get_str 取得一份引用。
		if n.Op == "as" || n.Op == "as?" {
			if ta, ok := n.R.(*xfront.TypeAsExpr); ok {
				if t, err := s.g.cType(s.g.substitute(ta.Type)); err == nil && t == "rt_string *" {
					v, err := s.intExpr(n)
					if err != nil {
						return nil, err
					}
					out := append([]string{}, s.pending...)
					s.pending = nil
					tv := s.tmp()
					return append(out, "rt_string *"+tv+" = "+v+";"), nil
				}
			}
		}
		if n.Op == "+" {
			var out []string
			ls, err := s.strExpr(n.L)
			if err != nil {
				return nil, err
			}
			rs, err := s.strExpr(n.R)
			if err != nil {
				return nil, err
			}
			out = append(out, ls...)
			out = append(out, rs...)
			t := s.tmp()
			out = append(out, "rt_string *"+t+" = xn_concat("+lastVar(ls)+", "+lastVar(rs)+");")
			return out, nil // xn_concat 接管两侧所有权
		}
	case *xfront.Call:
		// S6-03：dirReadAsync 等 String 返回的内建入口。
		if id, ok := n.Callee.(*xfront.IdentExpr); ok && sys603IsAsyncName(id.Name) {
			lines, _, handled, err := s.sys603Call(n)
			if err != nil {
				return nil, err
			}
			if handled {
				return lines, nil
			}
		}
		// S3-04：Text/StringBuilder.toString() 返回新 String（GC）。
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if rn, rc, err := recvCName(mem.X, s); err == nil && mem.Name == "toString" {
				switch rc {
				case "xrt_text *":
					t := s.tmp()
					return []string{"rt_string *" + t + " = xrt_text_to_string(" + rn + ");"}, nil
				case "xrt_sb *":
					t := s.tmp()
					return []string{"rt_string *" + t + " = xrt_sb_to_string(" + rn + ");"}, nil
				}
			}
		}
		if id, ok := n.Callee.(*xfront.IdentExpr); ok && id.Name == "str" {
			if t, err := s.exprType(n.Args[0]); err == nil {
				if s.g.isTupleC(t) {
					lines, _, err := s.tupleStr(n.Args[0], t)
					if err != nil {
						return nil, err
					}
					return lines, nil
				}
				if t == "int" {
					v, err := s.boolExpr(n.Args[0])
					if err != nil {
						return nil, err
					}
					tmp := s.tmp()
					return []string{"rt_string *" + tmp + " = xn_str_bool(" + v + ");"}, nil
				}
				if t == "rt_string *" {
					return s.strExpr(n.Args[0])
				}
			}
			v, err := s.intExpr(n.Args[0])
			if err != nil {
				return nil, err
			}
			t := s.tmp()
			return []string{"rt_string *" + t + " = xn_str_int(" + v + ");"}, nil
		}
		if id, ok := n.Callee.(*xfront.IdentExpr); ok {
			if e, isFFI := s.ffiEntry(id.Name); isFFI {
				if e.Ret.Kind != ffi.KindString {
					return nil, fmt.Errorf("codegen：FFI 入口 %s 返回类型不是 String（P-09）", e.Name)
				}
				lines, out, err := s.ffiCallLines(n, e)
				if err != nil {
					return nil, err
				}
				t := s.tmp()
				return append(lines, "rt_string *"+t+" = "+out+";"), nil
			}
			if expr, hit, err := s.selfMethodCall(id.Name, n.Args); err != nil {
				return nil, err
			} else if hit {
				t := s.tmp()
				out := append([]string{}, s.pending...)
				s.pending = nil
				return append(out, "rt_string *"+t+" = "+expr+";"), nil
			}
			if ret, ok2 := s.g.callRetC(id.Name, n.TypeArgs); ok2 && ret == "rt_string *" {
				args, err := s.callArgs(n.Args)
				if err != nil {
					return nil, err
				}
				cn, err := s.g.callName(id.Name, n.TypeArgs, len(n.Args))
				if err != nil {
					return nil, err
				}
				t := s.tmp()
				out := append([]string{}, s.pending...)
				s.pending = nil
				return append(out, "rt_string *"+t+" = "+cn+"("+strings.Join(args, ", ")+");"), nil
			}
		}
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if expr, retC, hit, err := s.tryFactoryCall(mem, n); err != nil {
				return nil, err
			} else if hit {
				if retC != "rt_string *" {
					return nil, fmt.Errorf("codegen：工厂方法 %s 返回 %s，不是 String", mem.Name, retC)
				}
				t := s.tmp()
				out := append([]string{}, s.pending...)
				s.pending = nil
				return append(out, "rt_string *"+t+" = "+expr+";"), nil
			}
			if expr, retC, hit, err := s.staticClassCall(mem, n); err != nil {
				return nil, err
			} else if hit {
				if retC != "rt_string *" {
					return nil, fmt.Errorf("codegen：静态方法 %s 返回 %s，不是 String", mem.Name, retC)
				}
				t := s.tmp()
				out := append([]string{}, s.pending...)
				s.pending = nil
				return append(out, "rt_string *"+t+" = "+expr+";"), nil
			}
			if rt, err := s.exprType(mem.X); err == nil && s.g.isProtoC(rt) {
				expr, retC, err := s.protoDispatch(mem, n.Args)
				if err != nil {
					return nil, err
				}
				if retC != "rt_string *" {
					return nil, fmt.Errorf("codegen：协议方法 %s 返回 %s，不是 String", mem.Name, retC)
				}
				t := s.tmp()
				out := append([]string{}, s.pending...)
				s.pending = nil
				return append(out, "rt_string *"+t+" = "+expr+";"), nil
			}
			if rn, rc, err := recvCName(mem.X, s); err == nil && isContainerC(rc) {
				switch mem.Name {
				case "join":
					sep, err := s.strExpr(n.Args[0])
					if err != nil {
						return nil, err
					}
					t := s.tmp()
					out := append([]string{}, s.pending...)
					s.pending = nil
					out = append(out, sep...)
					return append(out, "rt_string *"+t+" = "+contBase(rc)+"_join("+rn+", "+lastVar(sep)+");"), nil
				case "get", "at":
					if elem, ok2 := containerElem(rc); ok2 && elem == "rt_string *" {
						i, err := s.intExpr(n.Args[0])
						if err != nil {
							return nil, err
						}
						t := s.tmp()
						out := append([]string{}, s.pending...)
						s.pending = nil
						return append(out, "rt_string *"+t+" = rt_retain("+contBase(rc)+"_"+mem.Name+"("+rn+", "+i+"));"), nil
					}
				}
			}
			if rn, rc, err := recvCName(mem.X, s); err == nil && mem.Name == "toString" &&
				(rc == "xrt_text *" || rc == "xrt_sb *") {
				t := s.tmp()
				out := append([]string{}, s.pending...)
				s.pending = nil
				call := "(rt_string *)xrt_text_to_string(" + rn + ")"
				if rc == "xrt_sb *" {
					call = "(rt_string *)xrt_sb_to_string(" + rn + ")"
				}
				return append(out, "rt_string *"+t+" = "+call+";"), nil
			}
			if rt, err2 := s.exprType(mem.X); err2 == nil && rt == "rt_string *" {
				call, hit, err := s.strMemberValue(mem, n.Args, true)
				if err != nil {
					return nil, err
				}
				if hit {
					t := s.tmp()
					out := append([]string{}, s.pending...)
					s.pending = nil
					return append(out, "rt_string *"+t+" = "+call+";"), nil
				}
			}
			if recv, ok2 := mem.X.(*xfront.IdentExpr); ok2 {
				if rc, ok3 := s.localCType(recv.Name); ok3 && (isClassPtr(rc) || s.g.isDataEnumC(rc) || s.g.isSingletonC(rc)) {
					rn := recv.Name
					if s.params != nil && s.params[rn] {
						rn = "xn_p_" + rn
					}
					call, _, err := s.classMemberValue(rc, rn, mem, n.Args)
					if err != nil {
						return nil, err
					}
					t := s.tmp()
					out := append([]string{}, s.pending...)
					s.pending = nil
					return append(out, "rt_string *"+t+" = "+call+";"), nil
				}
			}
		}
		if mem, ok := n.Callee.(*xfront.Member); ok && mem.Name == "error" {
			if recv, ok2 := mem.X.(*xfront.IdentExpr); ok2 {
				if rc, ok3 := s.localCType(recv.Name); ok3 && strings.HasPrefix(rc, "xn_Result_") {
					if info, err := s.g.resultInfo(rc); err == nil && info.errC == "rt_string *" {
						t := s.tmp()
						return []string{"rt_string *" + t + " = xn_result_error_copy_rt(" + recv.Name + ".err);"}, nil
					}
				}
			}
		}
	case *xfront.Index:
		v, err := s.borrowStr(n)
		if err != nil {
			return nil, err
		}
		t := s.tmp()
		return []string{"rt_string *" + t + " = rt_retain(" + v + ");"}, nil
	case *xfront.IdentExpr:
		name := s.cRef(n.Name)
		// 借用 → 为消费方取得一份引用（concat 接管两侧所有权）
		t := s.tmp()
		return []string{"rt_string *" + t + " = rt_retain(" + name + ");"}, nil
	case *xfront.Member:
		recvName, recvC, err := recvCName(n.X, s)
		if err != nil {
			return nil, err
		}
		if s.g.isStructC(recvC) {
			if ci, ok := s.g.structOfC(recvC); ok {
				if f, ok2 := ci.fieldOf(n.Name); ok2 && f.ctype == "rt_string *" {
					t := s.tmp()
					return []string{"rt_string *" + t + " = rt_retain(" + recvName + structSep(recvC) + f.cname + ");"}, nil
				}
			}
		}
		ci, ok := s.g.classOfC(recvC)
		if ok {
			if f, ok2 := ci.fieldOf(n.Name); ok2 && f.isStr {
				t := s.tmp()
				return []string{"rt_string *" + t + " = rt_retain(" + recvName + "->" + f.cname + ");"}, nil
			}
		}
		return nil, fmt.Errorf("codegen：String 成员 %s 的接收者不支持（M4.4b 范围）", n.Name)
	case *xfront.TupleMember:
		ec, err := s.exprType(n)
		if err != nil {
			return nil, err
		}
		if ec != "rt_string *" {
			return nil, fmt.Errorf("codegen：元组元素 .%d 不是 String", n.Index)
		}
		baseT, err := s.exprType(n.X)
		if err != nil {
			return nil, err
		}
		lines, base, err := s.tupleExpr(n.X, baseT)
		if err != nil {
			return nil, err
		}
		t := s.tmp()
		return append(lines, "rt_string *"+t+" = rt_retain(("+base+").f"+fmt.Sprintf("%d", n.Index)+");"), nil
	case *xfront.Paren:
		return s.strExpr(n.X)
	}
	if t, err := s.exprType(e); err == nil && s.g.isTupleC(t) {
		lines, _, err := s.tupleStr(e, t)
		if err != nil {
			return nil, err
		}
		return lines, nil
	}
	return nil, fmt.Errorf("codegen：String 表达式 %T 未支持（M4.1 范围）", e)
}

// resultExpr 生成 Result 值表达式（Ok/Err 构造或函数调用）。
func (s *scope) resultExpr(e xfront.Expr, resultC string) (string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		if rc, ok := s.localCType(n.Name); ok && rc == resultC {
			return "(" + s.cRef(n.Name) + ")", nil
		}
		if rc, ok := s.g.globals[n.Name]; ok && rc == resultC {
			return "(" + s.cRef(n.Name) + ")", nil
		}
		return "", fmt.Errorf("codegen：Result 复制源 %s 类型不是 %s（S3-RESULT）", n.Name, resultC)
	case *xfront.Member:
		// 字段上的 Result 值复制（内联结构整值复制）。
		v, err := s.intExpr(n)
		if err != nil {
			return "", err
		}
		return "(" + v + ")", nil
	case *xfront.Paren:
		return s.resultExpr(n.X, resultC)
	case *xfront.Call:
		if id, ok := n.Callee.(*xfront.IdentExpr); ok {
			// S6-04：资源读取的 Result 由内建降级直接构造。
			if id.Name == "readResource" || id.Name == "readResourceText" || id.Name == "listResources" {
				lines, expr, err := s.s604ResultCall(id.Name, n, resultC)
				if err != nil {
					return "", err
				}
				s.pending = append(s.pending, lines...)
				return expr, nil
			}
			switch id.Name {
			case "Ok":
				if len(n.Args) == 0 {
					info, err := s.g.resultInfo(resultC)
					if err != nil {
						return "", err
					}
					return "(" + resultC + "){1, " + s.g.resultZeroC(info.memberC) + ", " + s.g.resultZeroC(info.errC) + "}", nil
				}
				return s.resultOkValue(resultC, n.Args[0])
			case "Err":
				return s.resultErrExpr(resultC, n.Args[0])
			case "wrap":
				return s.emitResultWrap(n, resultC)
			case "mapErr":
				return s.emitResultMapErr(n, resultC)
			case "report":
				if len(n.Args) != 1 {
					return "", fmt.Errorf("codegen：report 需要 1 个参数（S4-02）")
				}
				out, err := s.emitResultReport(n.Args[0], resultC)
				return out, err
			}
			args, err := s.callArgs(n.Args)
			if err != nil {
				return "", err
			}
			cn, err := s.g.callName(id.Name, n.TypeArgs, len(n.Args))
			if err != nil {
				return "", err
			}
			return cn + "(" + strings.Join(args, ", ") + ")", nil
		}
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if rn, rc, err := recvCName(mem.X, s); err == nil {
				if isSyncHandleC(rc) {
					return s.emitSyncResult(rn, rc, mem.Name, resultC, n.Args)
				}
				if rc == "xrt_task *" && (mem.Name == "join" || mem.Name == "joinDeadline") {
					return s.emitTaskResult(rn, rc, mem.Name, resultC, n.Args)
				}
				if rc == "xrt_task_group *" && mem.Name == "close" {
					return s.emitTaskResult(rn, rc, mem.Name, resultC, n.Args)
				}
			}
			if expr, _, hit, err := s.tryFactoryCall(mem, n); err != nil {
				return "", err
			} else if hit {
				return expr, nil
			}
			if expr, _, hit, err := s.staticClassCall(mem, n); err != nil {
				return "", err
			} else if hit {
				return expr, nil
			}
			recvName, recvC, err := recvCName(mem.X, s)
			if err != nil {
				return "", err
			}
			if s.g.isStructC(recvC) {
				ci, _ := s.g.structOfC(recvC)
				m, ok := s.methodFor(ci, mem.Name, n.Args)
				if !ok {
					return "", fmt.Errorf("codegen：结构体 %s 没有方法 %s", ci.decl.Name, mem.Name)
				}
				return s.methodCall(ci, m, "(&"+recvName+")", n.Args)
			}
			if s.g.isProtoC(recvC) {
				expr, _, err := s.protoDispatch(mem, n.Args)
				return expr, err
			}
			ci, ok := s.g.classOfC(recvC)
			if !ok {
				return "", fmt.Errorf("codegen：Result 表达式目标 %T 未支持", n.Callee)
			}
			m, ok := s.methodFor(ci, mem.Name, n.Args)
			if !ok {
				return "", fmt.Errorf("codegen：类 %s 没有方法 %s", ci.decl.Name, mem.Name)
			}
			return s.methodCall(ci, m, recvName, n.Args)
		}
		return "", fmt.Errorf("codegen：Result 表达式目标 %T 未支持", n.Callee)
	}
	return "", fmt.Errorf("codegen：Result 表达式 %T 未支持（M4.1 范围）", e)
}

// resultOkValue 生成 Result Ok 值（支持 Int/Bool/String/类/struct/枚举/协议）。
func (s *scope) resultOkValue(resultC string, e xfront.Expr) (string, error) {
	mC, err := s.g.resultMemberC(resultC)
	if err != nil {
		return "", err
	}
	var expr string
	switch {
	case isClassPtr(mC):
		lines, v, owns, err := s.classValueExpr(e)
		if err != nil {
			return "", err
		}
		s.pending = append(s.pending, lines...)
		expr = v
		if !owns {
			expr = "rt_retain(" + expr + ")"
		}
	case s.g.isProtoC(mC):
		lines, v, _, err := s.protoValue(e)
		if err != nil {
			return "", err
		}
		s.pending = append(s.pending, lines...)
		expr = v
	case s.g.isStructC(mC):
		lines, v, err := s.structValue(e, mC)
		if err != nil {
			return "", err
		}
		s.pending = append(s.pending, lines...)
		expr = v
	case mC == "rt_string *":
		v, err := s.strExprOne(e)
		if err != nil {
			return "", err
		}
		expr = v
	case s.g.isSimpleEnumC(mC) || s.g.isDataEnumC(mC):
		v, err := s.intExpr(e)
		if err != nil {
			return "", err
		}
		expr = v
	default:
		v, err := s.intExpr(e)
		if err != nil {
			return "", err
		}
		expr = v
	}
	info, err := s.g.resultInfo(resultC)
	if err != nil {
		return "", err
	}
	return "(" + resultC + "){1, " + expr + ", " + s.g.resultZeroC(info.errC) + "}", nil
}

// classValueExpr 生成类引用值表达式（+1 产物 owns=true）。
func (s *scope) classValueExpr(e xfront.Expr) ([]string, string, bool, error) {
	switch n := e.(type) {
	case *xfront.New:
		expr, err := s.emitNewClass(n)
		if err != nil {
			return nil, "", false, err
		}
		lines := append([]string{}, s.pending...)
		s.pending = nil
		return lines, expr, true, nil
	case *xfront.Call:
		expr, owns, err := s.classCallExpr(n)
		if err != nil {
			return nil, "", false, err
		}
		lines := append([]string{}, s.pending...)
		s.pending = nil
		return lines, expr, owns, nil
	case *xfront.IdentExpr:
		return nil, s.cRef(n.Name), false, nil
	case *xfront.NullLit:
		return nil, "NULL", false, nil
	case *xfront.Paren:
		return s.classValueExpr(n.X)
	case *xfront.Member:
		v, err := s.intExpr(n)
		return nil, v, false, err
	}
	return nil, "", false, fmt.Errorf("codegen：类值表达式 %T 未支持", e)
}

// strExprOne 生成字符串表达式（临时语句 + 最终 C 表达式文本，Err 构造用）。
func (s *scope) strExprOne(e xfront.Expr) (string, error) {
	lines, err := s.strExpr(e)
	if err != nil {
		return "", err
	}
	s.pending = append(s.pending, lines...)
	return lastVar(lines), nil
}

// cond 生成 C 布尔条件。
func (s *scope) cond(e xfront.Expr) (string, error) {
	switch n := e.(type) {
	case *xfront.BoolLit:
		if n.V {
			return "1", nil
		}
		return "0", nil
	case *xfront.Binary:
		switch n.Op {
		case "&&", "||":
			l, err := s.cond(n.L)
			if err != nil {
				return "", err
			}
			r, err := s.cond(n.R)
			if err != nil {
				return "", err
			}
			return "(" + l + " " + n.Op + " " + r + ")", nil
		}
		v, err := s.intExpr(n)
		return "(" + v + ")", err
	}
	// 其余标量形态（局部/字面量/调用）按 Int 处理
	v, err := s.intExpr(e)
	return "(" + v + ")", err
}

// intExpr 生成 int64_t/int 表达式。
func (s *scope) intExpr(e xfront.Expr) (string, error) {
	switch n := e.(type) {
	case *xfront.BoolLit:
		if n.V {
			return "1", nil
		}
		return "0", nil
	case *xfront.IntLitExpr:
		v, err := intValue(n)
		if err != nil {
			return "", err
		}
		return strconv.FormatInt(v, 10), nil
	case *xfront.IdentExpr:
		if s.params != nil && s.params[n.Name] {
			return "xn_p_" + n.Name, nil
		}
		return s.cRef(n.Name), nil
	case *xfront.NullLit:
		// 可空句柄（File? 等）以 NULL 哨兵表示，与 null 比较直接落 C 的 NULL。
		return "NULL", nil
	case *xfront.TupleMember:
		baseT, err := s.exprType(n.X)
		if err != nil {
			return "", err
		}
		lines, base, err := s.tupleExpr(n.X, baseT)
		if err != nil {
			return "", err
		}
		s.pending = append(s.pending, lines...)
		return "(" + base + ").f" + fmt.Sprintf("%d", n.Index), nil
	case *xfront.Binary:
		// S6-02：可空值 null 比较（String? 等）按 has 位判定。
		if n.Op == "==" || n.Op == "!=" {
			if lt, err := s.exprType(n.L); err == nil && strings.HasPrefix(lt, "xn_opt_") {
				if _, isNull := n.R.(*xfront.NullLit); isNull {
					x, err := s.intExpr(n.L)
					if err != nil {
						return "", err
					}
					cond := "(" + x + ").has"
					if n.Op == "==" {
						return "(!(" + cond + "))", nil
					}
					return "(" + cond + ")", nil
				}
			}
		}
		if n.Op == "is" {
			if ta, ok := n.R.(*xfront.TypeAsExpr); ok {
				return s.typeIsExpr(n, ta)
			}
		}
		if n.Op == "as?" || n.Op == "as" {
			if ta, ok := n.R.(*xfront.TypeAsExpr); ok {
				return s.typeAsExpr(n, ta, n.Op == "as?")
			}
		}
		// 元组相等/同一性（S1 §2.11）：逐元素比较，整值语义。
		if n.Op == "==" || n.Op == "!=" || n.Op == "===" || n.Op == "!==" {
			if lt, err := s.exprType(n.L); err == nil && s.g.isTupleC(lt) {
				cmp, err := s.tupleEq(n.L, n.R, lt, n.Op == "===" || n.Op == "!==")
				if err != nil {
					return "", err
				}
				if n.Op == "!=" || n.Op == "!==" {
					return "(!(" + cmp + "))", nil
				}
				return cmp, nil
			}
		}
		if n.Op == "==" || n.Op == "!=" {
			if lt, err := s.exprType(n.L); err == nil && lt == "rt_string *" {
				ls, err := s.strExpr(n.L)
				if err != nil {
					return "", err
				}
				rs, err := s.strExpr(n.R)
				if err != nil {
					return "", err
				}
				out := append([]string{}, ls...)
				out = append(out, rs...)
				s.pending = append(s.pending, out...)
				eq := "xn_str_eq(" + lastVar(ls) + ", " + lastVar(rs) + ")"
				if n.Op == "!=" {
					return "(!(" + eq + "))", nil
				}
				return eq, nil
			}
		}
		// 对象同一性（S2 §2.8/§5.6）：类/协议/数据枚举/句柄/字节缓冲按指针身份。
		if n.Op == "===" || n.Op == "!==" {
			if lt, err := s.exprType(n.L); err == nil && (isClassPtr(lt) || s.g.isProtoC(lt) || s.g.isDataEnumC(lt) || lt == "xrt_handle *" || lt == "xrt_bytes_obj *") {
				l, err := s.intExpr(n.L)
				if err != nil {
					return "", err
				}
				r, err := s.intExpr(n.R)
				if err != nil {
					return "", err
				}
				op := "=="
				if n.Op == "!==" {
					op = "!="
				}
				return "(" + l + " " + op + " " + r + ")", nil
			}
		}
		l, err := s.intExpr(n.L)
		if err != nil {
			return "", err
		}
		r, err := s.intExpr(n.R)
		if err != nil {
			return "", err
		}
		// 除零是 fatal（S1 §10.4）：编译路径同样必须终止入口，不能被 C 常量折叠吞掉。
		if n.Op == "/" || n.Op == "%" {
			fn := "xn_div_i64"
			if n.Op == "%" {
				fn = "xn_mod_i64"
			}
			return fn + "((int64_t)(" + l + "), (int64_t)(" + r + "))", nil
		}
		return "(" + l + " " + cOp(n.Op) + " " + r + ")", nil
	case *xfront.Paren:
		return s.intExpr(n.X)
	case *xfront.Unary:
		switch n.Op {
		case "!":
			v, err := s.intExpr(n.X)
			if err != nil {
				return "", err
			}
			return "(!(" + v + "))", nil
		case "-":
			v, err := s.intExpr(n.X)
			if err != nil {
				return "", err
			}
			return "(-(" + v + "))", nil
		}
		return "", fmt.Errorf("codegen：一元运算 %s 未支持（M4.4b 范围）", n.Op)
	case *xfront.Index:
		return s.indexRead(n)
	case *xfront.Member:
		if varName, _, ok := s.g.singletonStatic(n); ok {
			return varName, nil
		}
		if _, varName, ok := s.g.singletonInstance(n); ok {
			return varName, nil
		}
		if ei, it, ok := s.g.enumItem(n); ok {
			if ei.simple {
				return strconv.FormatInt(it.value, 10), nil
			}
			return it.varName, nil
		}
		recvName, recvC, err := recvCName(n.X, s)
		if err != nil {
			return "", err
		}
		if s.g.isStructC(recvC) {
			ci, _ := s.g.structOfC(recvC)
			f, ok := ci.fieldOf(n.Name)
			if !ok {
				return "", fmt.Errorf("codegen：结构体没有字段 %s", n.Name)
			}
			return recvName + structSep(recvC) + f.cname, nil
		}
		if v, hit, err := s.classMemberValue(recvC, recvName, n, nil); err != nil {
			return "", err
		} else if hit {
			return v, nil
		}
		return "", fmt.Errorf("codegen：成员 %s 的接收者类型 %s 不支持（M4.4b 范围）", n.Name, recvC)
	case *xfront.New:
		return s.emitNewClass(n)
	case *xfront.Call:
		if id, ok := n.Callee.(*xfront.IdentExpr); ok {
			// S6-02：xdk.runtime 内建（不依赖项目 .xfb 装载）。
			switch id.Name {
			case "nowMono":
				return "xdkc_now_mono_ms()", nil
			case "nowWall":
				return "xdkc_now_wall_ms()", nil
			}
			// S6-03：sys *Async / Process 内建（Context/出参形态不经 .xfb）。
			if sys603IsAsyncName(id.Name) {
				lines, expr, handled, err := s.sys603Call(n)
				if err != nil {
					return "", err
				}
				if handled {
					s.pending = append(s.pending, lines...)
					return expr, nil
				}
			}
			// S6-04：resourceExists（无 Result 通道的资源探测）。
			if id.Name == "resourceExists" {
				lines, expr, err := s.s604Exists(n)
				if err != nil {
					return "", err
				}
				s.pending = append(s.pending, lines...)
				return expr, nil
			}
			if e, isFFI := s.ffiEntry(id.Name); isFFI {
				if e.Ret.Kind != ffi.KindScalar {
					return "", fmt.Errorf("codegen：FFI 入口 %s 返回类型不是 Int（P-09）", e.Name)
				}
				lines, out, err := s.ffiCallLines(n, e)
				if err != nil {
					return "", err
				}
				s.pending = append(s.pending, lines...)
				return out, nil
			}
			switch id.Name {
			case "Ok", "Err", "print", "str":
				return "", fmt.Errorf("codegen：%s(...) 不能作为 Int 值（M4.4a 范围）", id.Name)
			}
			if expr, hit, err := s.selfMethodCall(id.Name, n.Args); err != nil {
				return "", err
			} else if hit {
				return expr, nil
			}
			args, err := s.callArgs(n.Args)
			if err != nil {
				return "", err
			}
			cn, err := s.g.callName(id.Name, n.TypeArgs, len(n.Args))
			if err != nil {
				return "", err
			}
			s.pending = append(s.pending, s.flushPendingArgs()...)
			return cn + "(" + strings.Join(args, ", ") + ")", nil
		}
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if expr, _, hit, err := s.tryFactoryCall(mem, n); err != nil {
				return "", err
			} else if hit {
				return expr, nil
			}
			if expr, _, hit, err := s.staticClassCall(mem, n); err != nil {
				return "", err
			} else if hit {
				return expr, nil
			}
			if rt, err := s.exprType(mem.X); err == nil && s.g.isProtoC(rt) {
				expr, _, err := s.protoDispatch(mem, n.Args)
				if err != nil {
					return "", err
				}
				return expr, nil
			}
			if rn, rc, err := recvCName(mem.X, s); err == nil && s.g.isStructC(rc) {
				ci, _ := s.g.structOfC(rc)
				m, ok := s.methodFor(ci, mem.Name, n.Args)
				if !ok {
					return "", fmt.Errorf("codegen：结构体 %s 没有方法 %s", ci.decl.Name, mem.Name)
				}
				expr, err := s.methodCall(ci, m, "(&"+rn+")", n.Args)
				if err != nil {
					return "", err
				}
				out := append([]string{}, s.pending...)
				s.pending = nil
				s.pending = append(out, s.pending...)
				return expr, nil
			}
			if rn, rc, err := recvCName(mem.X, s); err == nil && isSyncHandleC(rc) {
				if v, hit, err := s.emitSyncAtomicValue(rn, rc, mem.Name, n.Args); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
			if rn, rc, err := recvCName(mem.X, s); err == nil && rc == "xrt_bytes_obj *" {
				if v, hit, err := s.bytesMemberValue(rn, mem.Name, n.Args); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
			if rn, rc, err := recvCName(mem.X, s); err == nil && rc == "xrt_text *" {
				if v, hit, err := s.textMemberValue(rn, mem.Name, n.Args); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
			if rn, rc, err := recvCName(mem.X, s); err == nil && rc == "xrt_sb *" {
				if mem.Name == "append" {
					if v, hit, err := s.sbAppendValue(rn, n.Args); err != nil {
						return "", err
					} else if hit {
						return v, nil
					}
				}
				if v, hit, err := s.sbMemberValue(rn, mem.Name); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
			if rn, rc, err := recvCName(mem.X, s); err == nil && isContainerC(rc) {
				if v, hit, err := s.containerMemberValue(rc, rn, mem.Name, n.Args); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
			if rt, err2 := s.exprType(mem.X); err2 == nil && rt == "rt_string *" {
				if v, hit, err := s.strMemberValue(mem, n.Args, false); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
			if rn, rc, err := recvCName(mem.X, s); err == nil && (isClassPtr(rc) || s.g.isDataEnumC(rc) || s.g.isSingletonC(rc)) {
				if v, hit, err := s.classMemberValue(rc, rn, mem, n.Args); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
			if recv, ok2 := mem.X.(*xfront.IdentExpr); ok2 {
				if rc, ok3 := s.localCType(recv.Name); ok3 && (isClassPtr(rc) || s.g.isDataEnumC(rc) || s.g.isSingletonC(rc)) {
					rn := recv.Name
					if s.params != nil && s.params[rn] {
						rn = "xn_p_" + rn
					}
					if v, hit, err := s.classMemberValue(rc, rn, mem, n.Args); err != nil {
						return "", err
					} else if hit {
						return v, nil
					}
				}
			}
		}
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if rn, rc, err := recvCName(mem.X, s); err == nil && isContainerC(rc) {
				base := contBase(rc)
				if k, _ := mapTypes(base); k != "" && mem.Name == "get" && len(n.Args) == 1 {
					// S3-EXPR：Map.get 返回 V?；标量参与算术/比较时取 .v（存在键）。
					kk, kl, err := s.elemValue(n.Args[0], k)
					if err != nil {
						return "", err
					}
					s.pending = append(s.pending, kl...)
					return "(" + base + "_get(" + rn + ", " + kk + ").v)", nil
				}
				if v, hit, err := s.containerMemberValue(rc, rn, mem.Name, n.Args); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
			// Result 成员（isOk/isErr/value/unwrapOr）：接收者可为变量或字段链。
			rn, rc := "", ""
			if recv, ok2 := mem.X.(*xfront.IdentExpr); ok2 {
				rn = s.varRef(recv.Name)
				if c, ok3 := s.localCType(recv.Name); ok3 {
					rc = c
				} else if c, ok3 := s.g.globals[recv.Name]; ok3 {
					rc = c
				}
			} else if _, err := s.exprType(mem.X); err == nil {
				if n2, c2, err2 := recvCName(mem.X, s); err2 == nil {
					rn, rc = n2, c2
				}
			}
			if rn != "" && strings.HasPrefix(rc, "xn_Result_") {
				switch mem.Name {
				case "isOk":
					return "(" + rn + ").ok", nil
				case "isErr":
					return "(!(" + rn + ").ok)", nil
				case "value":
					return "(" + rn + ").v", nil
				case "error":
					return "(" + rn + ").err", nil
				case "unwrapOr":
					arg, err := s.intExpr(n.Args[0])
					if err != nil {
						return "", err
					}
					return "((" + rn + ").ok ? (" + rn + ").v : (" + arg + "))", nil
				}
			}
		}
	}
	return "", fmt.Errorf("codegen：Int 表达式 %T 未支持（M4.1 范围）", e)
}

// varRef 把 XNull 标识符映射为 C 引用（参数带 xn_p_ 前缀）。
func (s *scope) varRef(name string) string {
	if s.params != nil && s.params[name] {
		return "xn_p_" + name
	}
	return name
}

// retBase 生成返回类型声明前缀（xn_Cls_X * → 'xn_Cls_X *'）。
func retBase(c string) string { return c }

// isIntScalarC 判断 C 类型是否为整数标量（Int/Int32/Int64；Bool 用 int 表示）。
func isIntScalarC(c string) bool {
	switch c {
	case "int64_t", "int32_t", "int":
		return true
	}
	return false
}

// classCallExpr 生成「返回类引用」的调用表达式。
// 返回 owns=true 表示调用点获得 +1 引用（须释放）；false 为借用（容器 get 等）。
func (s *scope) classCallExpr(cl *xfront.Call) (string, bool, error) {
	switch c := cl.Callee.(type) {
	case *xfront.IdentExpr:
		if expr, hit, err := s.selfMethodCall(c.Name, cl.Args); err != nil {
			return "", false, err
		} else if hit {
			return expr, true, nil
		}
		args, err := s.callArgs(cl.Args)
		if err != nil {
			return "", false, err
		}
		cn, err := s.g.callName(c.Name, cl.TypeArgs, len(cl.Args))
		if err != nil {
			return "", false, err
		}
		return cn + "(" + strings.Join(args, ", ") + ")", true, nil
	case *xfront.Member:
		if expr, _, hit, err := s.tryFactoryCall(c, cl); err != nil {
			return "", false, err
		} else if hit {
			return expr, true, nil
		}
		if expr, _, hit, err := s.staticClassCall(c, cl); err != nil {
			return "", false, err
		} else if hit {
			return expr, true, nil
		}
		rn, rc, err := recvCName(c.X, s)
		if err != nil {
			return "", false, err
		}
		if s.g.isProtoC(rc) {
			expr, _, err := s.protoDispatch(c, cl.Args)
			if err != nil {
				return "", false, err
			}
			return expr, true, nil
		}
		if isContainerC(rc) {
			v, hit, err := s.containerMemberValue(rc, rn, c.Name, cl.Args)
			if err != nil {
				return "", false, err
			}
			if hit {
				return v, false, nil // 容器元素借用
			}
		}
		if strings.HasPrefix(rc, "xn_Result_") && (c.Name == "error" || c.Name == "value") {
			info, err := s.g.resultInfo(rc)
			if err != nil {
				return "", false, err
			}
			field, eC := "v", info.memberC
			if c.Name == "error" {
				field, eC = "err", info.errC
			}
			expr := "(" + rn + ")." + field
			if isClassPtr(eC) && !s.g.classIsGC(eC) {
				return "((" + eC + ")rt_retain((void *)" + expr + "))", true, nil
			}
			return expr, false, nil
		}
		if isClassPtr(rc) || s.g.isDataEnumC(rc) {
			v, hit, err := s.classMemberValue(rc, rn, c, cl.Args)
			if err != nil {
				return "", false, err
			}
			if hit {
				return v, true, nil // 方法返回 +1 引用
			}
		}
	}
	return "", false, fmt.Errorf("codegen：类调用表达式被调 %T 未支持（M5.1-b 范围）", cl.Callee)
}

// callArgs 生成调用实参（按推断类型分派：String 临时移交所有权、
// 容器按值传递、标量按值）。
func (s *scope) callArgs(args []xfront.Expr) ([]string, error) {
	var out []string
	for _, a := range args {
		t, err := s.exprType(a)
		if err != nil {
			return nil, err
		}
		switch {
		case t == "rt_string *":
			lines, err := s.strExpr(a)
			if err != nil {
				return nil, err
			}
			s.pending = append(s.pending, lines...)
			out = append(out, lastVar(lines))
		case isClassPtr(t):
			if id, ok := a.(*xfront.IdentExpr); ok {
				out = append(out, s.cRef(id.Name))
				continue
			}
			// 临时类实参（M5.1-b）：new / 顶层调用产物 → 本层临时持有、
			// 函数尾统一释放（存活略长于语句但无泄漏、确定性；被调按借用消费）
			if nw, ok := a.(*xfront.New); ok {
				ctor, err := s.emitNewClass(nw)
				if err != nil {
					return nil, err
				}
				tn := s.tmp()
				s.pending = append(s.pending, t+" "+tn+" = "+ctor+";")
				if !s.g.classIsGC(t) {
					s.defers = append(s.defers, deferItem{name: tn, lines: []string{"rt_release(" + tn + ");"}})
				}
				out = append(out, tn)
				continue
			}
			if cl, ok := a.(*xfront.Call); ok {
				expr, owns, err := s.classCallExpr(cl)
				if err != nil {
					return nil, err
				}
				if owns {
					tn := s.tmp()
					s.pending = append(s.pending, t+" "+tn+" = "+expr+";")
					if !s.g.classIsGC(t) {
						s.defers = append(s.defers, deferItem{name: tn, lines: []string{"rt_release(" + tn + ");"}})
					}
					out = append(out, tn)
				} else {
					out = append(out, expr) // 借用：直传
				}
				continue
			}
			// S3-EXPR：成员表达式作实参（take(h.v)）：字段归持有者，按借用直传。
			if _, ok := a.(*xfront.Member); ok {
				v, err := s.intExpr(a)
				if err != nil {
					return nil, err
				}
				out = append(out, v)
				continue
			}
			return nil, fmt.Errorf("codegen：类实例实参只支持变量/new/调用/字段（M5.1-b/S3-EXPR 范围）")
		case strings.HasPrefix(t, "xn_Result_"):
			v, err := s.resultExpr(a, t)
			if err != nil {
				return nil, err
			}
			out = append(out, v)
		case s.g.isTupleC(t):
			lines, v, err := s.tupleExpr(a, t)
			if err != nil {
				return nil, err
			}
			s.pending = append(s.pending, lines...)
			out = append(out, v)
		case s.g.isProtoC(t):
			lines, expr, _, err := s.protoValue(a)
			if err != nil {
				return nil, err
			}
			s.pending = append(s.pending, lines...)
			out = append(out, expr)
		case s.g.isStructC(t):
			lines, v, err := s.structValue(a, t)
			if err != nil {
				return nil, err
			}
			s.pending = append(s.pending, lines...)
			out = append(out, v)
		case isContainerC(t):
			if id, ok := a.(*xfront.IdentExpr); ok {
				out = append(out, s.cRef(id.Name))
				continue
			}
			lines, v, err := s.valExpr(a, t)
			if err != nil {
				return nil, err
			}
			s.pending = append(s.pending, lines...)
			out = append(out, v)
		default:
			v, err := s.intExpr(a)
			if err != nil {
				return nil, err
			}
			out = append(out, v)
		}
	}
	return out, nil
}

func intValue(n *xfront.IntLitExpr) (int64, error) {
	text := n.Text
	for _, suf := range []string{"i", "I", "u", "U", "l", "L"} {
		text = strings.TrimSuffix(text, suf)
	}
	return strconv.ParseInt(text, n.Base, 64)
}

func cOp(op string) string { return op }

// cQuote 转 C 字符串字面量（UTF-8 字节直出）。
func cQuote(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch c {
		case '"':
			b.WriteString("\\\"")
		case '\\':
			b.WriteString("\\\\")
		case '\n':
			b.WriteString("\\n")
		case '\t':
			b.WriteString("\\t")
		case '\r':
			b.WriteString("\\r")
		case '\v':
			b.WriteString("\\v")
		case '\f':
			b.WriteString("\\f")
		default:
			if c < 0x20 || c == 0x7f {
				b.WriteString(fmt.Sprintf("\\%03o", c))
				continue
			}
			b.WriteByte(c)
		}
	}
	b.WriteByte('"')
	return b.String()
}

// plainText 提取无插值字符串字面量的文本。
func plainText(n *xfront.StrLitExpr) string {
	var b strings.Builder
	for _, p := range n.Parts {
		b.WriteString(p.Text)
	}
	return b.String()
}

// flushPendingArgs 取走调用实参求值产生的前置语句。
func (s *scope) flushPendingArgs() []string {
	out := s.pending
	s.pending = nil
	return out
}
