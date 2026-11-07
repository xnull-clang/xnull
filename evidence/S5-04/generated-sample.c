/* 由 XNull 编译器生成（M4.1 代码生成）。 */
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
static void xn_fatal_oob(void);
static void xn_fatal_oob(void) {
    fprintf(stderr, "fatal: 容器下标越界\n");
    exit(134);
}

typedef struct { int ok; int64_t v; xrt_error_kind err; } xn_Result_Int_TaskError;
typedef struct { int ok; int64_t v; xrt_error_kind err; } xn_Result_void_TaskError;

/* S5-04：任务 env（GC 对象；scan 遍历捕获引用） */
typedef struct {
    rt_header hdr;
    size_t    nrefs;
    size_t    nvals;
    /* 紧随其后：void *refs[nrefs]; int64_t vals[nvals]; */
} xn_task_env;
static void *xn_task_env_refs(xn_task_env *e) { return (void *)(e + 1); }
static int64_t *xn_task_env_vals(xn_task_env *e) { return (int64_t *)((void **)(e + 1) + e->nrefs); }
static void xn_task_env_scan(void *p, void (*visit)(void *)) {
    xn_task_env *e = (xn_task_env *)p;
    void **refs = (void **)xn_task_env_refs(e);
    for (size_t i = 0; i < e->nrefs; i++) { if (refs[i] != NULL) { visit(refs[i]); } }
}
static const rt_type RT_TYPE_XN_TASK_ENV = { "TaskEnv", sizeof(xn_task_env), NULL, xn_task_env_scan };
static xn_task_env *xn_task_env_new(size_t nrefs, size_t nvals) {
    xn_task_env *e = (xn_task_env *)rt_gc_new_size(&RT_TYPE_XN_TASK_ENV,
        sizeof(xn_task_env) + nrefs * sizeof(void *) + nvals * sizeof(int64_t));
    e->nrefs = nrefs;
    e->nvals = nvals;
    return e;
}
static int64_t xn_main();

static rt_string *xn_result_error_copy_rt(rt_string *err) {
    return rt_string_new(err->bytes, err->len);
}

static int32_t xn_task_body_1(void *env, xrt_context *ctx, xrt_task_result *out);
static int32_t xn_task_body_2(void *env, xrt_context *ctx, xrt_task_result *out);

int64_t xn_main() {
size_t xn_t1 = xn_root_mark();
xrt_context * c = xrt_context_background();
xrt_task_group * g = xrt_task_group_new(c);
xn_Result_Int_TaskError seed = (xn_Result_Int_TaskError){1, 41, 0};
xn_task_env *xn_t4 = xn_task_env_new(0, 3);
xn_task_env_vals(xn_t4)[0] = (int64_t)(seed.ok);
xn_task_env_vals(xn_t4)[1] = (int64_t)(seed.v);
xn_task_env_vals(xn_t4)[2] = (int64_t)(seed.err);
xrt_task *xn_t5 = NULL;
int32_t xn_t6 = xrt_task_group_spawn(g, xn_task_body_2, xn_t4, &xn_t5);
if (xn_t6 != 0) { xrt_fatal("task_group_spawn 失败（S5-00 §三）"); }
xrt_safepoint(); /* 任务 env 发布点（S5-00 §7.6） */
xrt_task * t = xn_t5;
xrt_task_result xn_t7;
int32_t xn_t8 = xrt_task_join(t, &xn_t7);
xn_Result_Int_TaskError xn_t9;
if (xn_t8 != 0) {
    xn_t9.ok = 0; xn_t9.v = 0; xn_t9.err = (xrt_error_kind)xn_t8;
} else if (!xn_t7.ok) {
    xn_t9.ok = 0; xn_t9.v = 0; xn_t9.err = xn_t7.kind;
} else {
    xn_t9.ok = 1; xn_t9.v = ((int64_t)(intptr_t)xn_t7.value); xn_t9.err = 0;
}
xrt_safepoint(); /* join/close 结果发布点（S5-00 §7.6） */
xn_Result_Int_TaskError r = xn_t9;
xn_print_int(((r).ok ? (r).v : (0)));
xrt_task_result xn_t10;
int32_t xn_t11 = xrt_task_group_close(g, &xn_t10);
xn_Result_void_TaskError xn_t12;
if (xn_t11 != 0) {
    xn_t12.ok = 0; xn_t12.v = 0; xn_t12.err = (xrt_error_kind)xn_t11;
} else if (!xn_t10.ok) {
    xn_t12.ok = 0; xn_t12.v = 0; xn_t12.err = xn_t10.kind;
} else {
    xn_t12.ok = 1; xn_t12.v = ((int64_t)(intptr_t)xn_t10.value); xn_t12.err = 0;
}
xrt_safepoint(); /* join/close 结果发布点（S5-00 §7.6） */
xn_Result_void_TaskError cr = xn_t12;
xn_print_bool(((cr).ok));
int64_t xn_t13 = 0;
    {
xn_root_restore(xn_t1);
    }

return xn_t13;
}

static int32_t xn_task_body_1(void *env, xrt_context *ctx, xrt_task_result *out) {
    (void)ctx;
    xrt_safepoint(); /* 任务体入口：挂起点安全点（S5-00 §7.2） */
    size_t xn_t2 = xn_root_mark();
    xn_task_env *e = (xn_task_env *)env;
    xn_Result_Int_TaskError seed = (xn_Result_Int_TaskError){ (int)xn_task_env_vals(e)[0], (int64_t)xn_task_env_vals(e)[1], (xrt_error_kind)xn_task_env_vals(e)[2] };
size_t xn_t2 = xn_root_mark();
xn_Result_Int_TaskError xn_t3 = (seed);
out->ok = xn_t3.ok;
out->value = ((void *)(intptr_t)(xn_t3.v));
out->kind = xn_t3.ok ? XRT_ERR_INVALID_ARGUMENT : xn_t3.err;
out->error = NULL;
xn_root_restore(xn_t2);
xrt_safepoint(); /* 任务体出口（S5-00 §7.2） */
return 0;

    xn_root_restore(xn_t2);
    out->ok = 0; out->kind = XRT_ERR_INTERNAL; out->value = NULL; out->error = NULL;
    xrt_safepoint();
    return 0;
}


static int32_t xn_task_body_2(void *env, xrt_context *ctx, xrt_task_result *out) {
    (void)ctx;
    xrt_safepoint(); /* 任务体入口：挂起点安全点（S5-00 §7.2） */
    size_t xn_t2 = xn_root_mark();
    xn_task_env *e = (xn_task_env *)env;
    xn_Result_Int_TaskError seed = (xn_Result_Int_TaskError){ (int)xn_task_env_vals(e)[0], (int64_t)xn_task_env_vals(e)[1], (xrt_error_kind)xn_task_env_vals(e)[2] };
size_t xn_t2 = xn_root_mark();
xn_Result_Int_TaskError xn_t3 = (seed);
out->ok = xn_t3.ok;
out->value = ((void *)(intptr_t)(xn_t3.v));
out->kind = xn_t3.ok ? XRT_ERR_INVALID_ARGUMENT : xn_t3.err;
out->error = NULL;
xn_root_restore(xn_t2);
xrt_safepoint(); /* 任务体出口（S5-00 §7.2） */
return 0;

    xn_root_restore(xn_t2);
    out->ok = 0; out->kind = XRT_ERR_INTERNAL; out->value = NULL; out->error = NULL;
    xrt_safepoint();
    return 0;
}


int main(void) {
    int64_t xn_r = xn_main();
    rt_gc_collect();
    rt_quarantine_flush();
    return (int)xn_r;
}
