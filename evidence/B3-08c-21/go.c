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
static void xn_print_double(double v) { printf("%g\n", v); }
static void xn_print_str(rt_string *s) { printf("%.*s\n", (int)s->len, s->bytes); }
static void xn_print_null(void) { fputs("null\n", stdout); }

/* 可空值（S1 §2.10）：has=0 表示 null。 */
typedef struct { int has; int64_t v; } xn_opt_i;
typedef struct { int has; int v; } xn_opt_b;
typedef struct { int has; rt_string *v; } xn_opt_s;

typedef int32_t xn_char; /* S1 Char：Unicode 标量值 */
static rt_string *xn_str_char(int32_t cp) {
    char buf[8];
    size_t n = 0;
    if (cp < 0) { cp = 0xFFFD; }
    if (cp < 0x80) { buf[n++] = (char)cp; }
    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }
    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }
    return rt_string_new(buf, n);
}

static rt_string *xn_str_int(int64_t v) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%lld", (long long)v);
    return rt_string_new(buf, (size_t)n);
}

static rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), "%g", v); return rt_string_new(buf, (size_t)n); }
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
/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */
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
/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */
extern int32_t xdkc_resource_exists(const char *, size_t);
extern int32_t xdkc_resource_size(const char *, size_t, int64_t *);
extern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);
extern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);
extern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);
extern void xdkc_list_resources_free(const char **);
typedef void *xn_proto_Error;
typedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;

typedef int64_t xn_Enum_ErrorKind;
static rt_string *xn_enum_ErrorKind_name(int64_t v) {
    switch (v) {
    case 0: return rt_string_from_c("InvalidArgument");
    case 1: return rt_string_from_c("NotFound");
    case 2: return rt_string_from_c("AlreadyExists");
    case 3: return rt_string_from_c("PermissionDenied");
    case 4: return rt_string_from_c("Io");
    case 5: return rt_string_from_c("Network");
    case 6: return rt_string_from_c("Timeout");
    case 7: return rt_string_from_c("Cancelled");
    case 8: return rt_string_from_c("Busy");
    case 9: return rt_string_from_c("Unavailable");
    case 10: return rt_string_from_c("DataCorrupted");
    case 11: return rt_string_from_c("Unsupported");
    case 12: return rt_string_from_c("OutOfMemory");
    case 13: return rt_string_from_c("Internal");
    default: return xn_str_int(v);
    }
}

static void xn_fatal_oob(void);
static void xn_fatal_oob(void) {
    fprintf(stderr, "fatal: 容器下标越界\n");
    exit(134);
}

typedef struct xn_Cls_CauseError xn_Cls_CauseError;
typedef struct xn_Cls_Format xn_Cls_Format;
typedef struct xn_Cls_Regex xn_Cls_Regex;

typedef struct { rt_header hdr; size_t len; size_t cap; uint16_t *data; } xn_arr_u16;

typedef struct xn_Cls_CauseError xn_Cls_CauseError;
typedef struct xn_Cls_Format xn_Cls_Format;
typedef struct xn_Cls_Regex xn_Cls_Regex;

static xn_Cls_CauseError *xn_Cls_CauseError_new(xn_Enum_ErrorKind xn_p_kind, rt_string * xn_p_message, xn_proto_Error xn_p_cause);
static void xn_Cls_CauseError_new_init(xn_Cls_CauseError *o, xn_Enum_ErrorKind xn_p_kind, rt_string * xn_p_message, xn_proto_Error xn_p_cause);
static void *xn_vt_CauseError[2];
static xn_Cls_Format *xn_Cls_Format_new(rt_string * xn_p_text, int64_t xn_p_width, xn_char xn_p_pad);
static void xn_Cls_Format_new_init(xn_Cls_Format *o, rt_string * xn_p_text, int64_t xn_p_width, xn_char xn_p_pad);
static xn_Cls_Regex *xn_Cls_Regex_new(rt_string * xn_p_pattern);
static void xn_Cls_Regex_new_init(xn_Cls_Regex *o, rt_string * xn_p_pattern);

typedef struct { int ok; xrt_bytes_obj * v; xn_proto_Error err; } xn_Result_Bytes_Error;
typedef struct { int ok; double v; xn_proto_Error err; } xn_Result_Double_Error;
typedef struct { int ok; int64_t v; xn_proto_Error err; } xn_Result_Int_Error;
typedef struct { int ok; xn_arr_u16 * v; xn_proto_Error err; } xn_Result_List_Error;
typedef struct { int ok; xn_Cls_Regex * v; xn_proto_Error err; } xn_Result_Regex_Error;

static void xn_arr_u16_deinit(void *p) {
    xn_arr_u16 *a = (xn_arr_u16 *)p;
    if (a->data != NULL) {
        free(a->data);
        a->data = NULL;
    }
    a->len = 0;
    a->cap = 0;
}

static const rt_type RT_TYPE_xn_arr_u16 = { "List", sizeof(xn_arr_u16), xn_arr_u16_deinit, NULL };

static xn_arr_u16 *xn_arr_u16_new(size_t cap) {
    xn_arr_u16 *a = (xn_arr_u16 *)xn_gc_new(&RT_TYPE_xn_arr_u16);
    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_u16) - sizeof(rt_header));
    a->cap = cap ? cap : 4;
    a->data = malloc(sizeof(uint16_t) * a->cap);
    if (a->data == NULL) { abort(); }
    return a;
}

static void xn_arr_u16_push(xn_arr_u16 *a, uint16_t v) {
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(uint16_t) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    a->data[a->len++] = v;
}

static uint16_t xn_arr_u16_get(const xn_arr_u16 *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    return a->data[i];
}

static void xn_arr_u16_set(xn_arr_u16 *a, int64_t i, uint16_t v) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    a->data[i] = v;
}

static uint16_t xn_arr_u16_remove(xn_arr_u16 *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    uint16_t old = a->data[i];
    for (size_t j = (size_t)i; j + 1 < a->len; j++) {
        a->data[j] = a->data[j + 1];
    }
    a->len--;
    return old;
}

static void xn_arr_u16_insert(xn_arr_u16 *a, int64_t i, uint16_t v) {
    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(uint16_t) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    for (size_t j = a->len; j > (size_t)i; j--) {
        a->data[j] = a->data[j - 1];
    }
    a->data[i] = v;
    a->len++;
}

static void xn_arr_u16_clear(xn_arr_u16 *a) {
    a->len = 0;
}

static rt_string *xn_arr_u16_join(xn_arr_u16 *a, rt_string *sep) {
    rt_string *res = rt_string_from_c("");
    for (size_t i = 0; i < a->len; i++) {
        if (i > 0) {
            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));
        }
        res = xn_concat(res, rt_string_from_c(""));
    }
    return res;
}

static int64_t xn_digitOf(rt_string * xn_p_ch);
static double xn_digitOfD(rt_string * xn_p_ch);
static xn_proto_Error xn_textErr(rt_string * xn_p_msg);
static xn_Result_Int_Error xn_parseInt(rt_string * xn_p_s);
static xn_Result_Double_Error xn_parseFloat(rt_string * xn_p_s);
static xn_Result_List_Error xn_utf8ToUtf16(xrt_bytes_obj * xn_p_b);
static xn_Result_Bytes_Error xn_utf16ToUtf8(xn_arr_u16 * xn_p_xs);
static int xn_regexAtomMatch(rt_string * xn_p_atom, rt_string * xn_p_ch);
static int xn_regexMatchAt(rt_string * xn_p_pattern, int64_t xn_p_pi, rt_string * xn_p_text, int64_t xn_p_ti);
static rt_string * xn_repeatText(rt_string * xn_p_unit, int64_t xn_p_times);
static rt_string * xn_repeatJoined(rt_string * xn_p_unit, rt_string * xn_p_sep, int64_t xn_p_times);
static int xn_isPositive(int64_t xn_p_n);
static int64_t xn_main();

/* 类 CauseError（M4.4b） */
typedef struct xn_Cls_CauseError {
    rt_header hdr;
    void **__vtable; /* 协议 vtable 槽（S2 §5.7；派发批次填充） */
    xn_Enum_ErrorKind errorKind;
    rt_string * message;
    xn_proto_Error cause;
} xn_Cls_CauseError;

static void xn_Cls_CauseError_deinit_hook(void *p) {
    xn_Cls_CauseError *o = (xn_Cls_CauseError *)p;
    rt_release(o->message);
}

static void xn_Cls_CauseError_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_CauseError *o = (xn_Cls_CauseError *)p;
    if (o->message) { visit(o->message); }
    if (o->cause) { visit(o->cause); }
}

static const rt_type RT_TYPE_XN_CauseError = { "CauseError", sizeof(xn_Cls_CauseError), xn_Cls_CauseError_deinit_hook, xn_Cls_CauseError_gc_scan };

static void xn_Cls_CauseError_new_init(xn_Cls_CauseError *o, xn_Enum_ErrorKind xn_p_kind, rt_string * xn_p_message, xn_proto_Error xn_p_cause) {
size_t xn_t286 = xn_root_mark();
xn_root_add(o);
xn_root_add(xn_p_message);
xn_root_add(xn_p_cause);
#line 40 "tests/b3/fixtures/bundle_text/app.x"
o->errorKind = xn_p_kind;
#line 41 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t287 = rt_retain(xn_p_message);
xn_root_add(xn_t287);
rt_release(o->message);
o->message = xn_t287;
#line 42 "tests/b3/fixtures/bundle_text/app.x"
void *xn_t288 = rt_retain((void *)xn_p_cause);
rt_release((void *)o->cause);
o->cause = xn_t288;
    {
    xn_root_restore(xn_t286);
    }
}

static xn_Cls_CauseError *xn_Cls_CauseError_new(xn_Enum_ErrorKind xn_p_kind, rt_string * xn_p_message, xn_proto_Error xn_p_cause) {
    xn_Cls_CauseError *o = (xn_Cls_CauseError *)xn_gc_new(&RT_TYPE_XN_CauseError);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_CauseError) - sizeof(rt_header));
    o->__vtable = xn_vt_CauseError;
    xn_Cls_CauseError_new_init(o, xn_p_kind, xn_p_message, xn_p_cause);
    return o;
}

static xn_Enum_ErrorKind xn_Cls_CauseError_kind(xn_Cls_CauseError *self);
static rt_string * xn_Cls_CauseError_describe(xn_Cls_CauseError *self);

static xn_Enum_ErrorKind xn_Cls_CauseError_kind(xn_Cls_CauseError *self) {
size_t xn_t289 = xn_root_mark();
xn_root_add(self);
#line 45 "tests/b3/fixtures/bundle_text/app.x"
    {
xn_root_restore(xn_t289);
    }

return self->errorKind;
    return (xn_Enum_ErrorKind)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_CauseError_describe(xn_Cls_CauseError *self) {
size_t xn_t290 = xn_root_mark();
xn_root_add(self);
#line 47 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t291 = rt_retain(self->message);
xn_root_add(xn_t291);
xn_root_add(xn_t291);
    {
xn_root_restore(xn_t290);
    }

return xn_t291;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

/* 类 Format（M4.4b） */
typedef struct xn_Cls_Format {
    rt_header hdr;
    rt_string * text;
    int64_t width;
    xn_char pad;
} xn_Cls_Format;

static void xn_Cls_Format_deinit_hook(void *p) {
    xn_Cls_Format *o = (xn_Cls_Format *)p;
    rt_release(o->text);
}

static void xn_Cls_Format_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_Format *o = (xn_Cls_Format *)p;
    if (o->text) { visit(o->text); }
}

static const rt_type RT_TYPE_XN_Format = { "Format", sizeof(xn_Cls_Format), xn_Cls_Format_deinit_hook, xn_Cls_Format_gc_scan };

static void xn_Cls_Format_new_init(xn_Cls_Format *o, rt_string * xn_p_text, int64_t xn_p_width, xn_char xn_p_pad) {
size_t xn_t292 = xn_root_mark();
xn_root_add(o);
xn_root_add(xn_p_text);
#line 19 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t293 = rt_retain(xn_p_text);
xn_root_add(xn_t293);
rt_release(o->text);
o->text = xn_t293;
#line 20 "tests/b3/fixtures/bundle_text/app.x"
o->width = xn_p_width;
#line 21 "tests/b3/fixtures/bundle_text/app.x"
o->pad = xn_p_pad;
    {
    xn_root_restore(xn_t292);
    }
}

static xn_Cls_Format *xn_Cls_Format_new(rt_string * xn_p_text, int64_t xn_p_width, xn_char xn_p_pad) {
    xn_Cls_Format *o = (xn_Cls_Format *)xn_gc_new(&RT_TYPE_XN_Format);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_Format) - sizeof(rt_header));
    xn_Cls_Format_new_init(o, xn_p_text, xn_p_width, xn_p_pad);
    return o;
}

static xn_Cls_Format * xn_Cls_Format_int(int64_t xn_p_v);
static xn_Cls_Format * xn_Cls_Format_float(double xn_p_v);
static xn_Cls_Format * xn_Cls_Format_string(rt_string * xn_p_v);
static xn_Cls_Format * xn_Cls_Format_bool(int xn_p_v);
static xn_Cls_Format * xn_Cls_Format_width(xn_Cls_Format *self, int64_t xn_p_w);
static xn_Cls_Format * xn_Cls_Format_pad(xn_Cls_Format *self, xn_char xn_p_c);
static rt_string * xn_Cls_Format_build(xn_Cls_Format *self);

static xn_Cls_Format * xn_Cls_Format_int(int64_t xn_p_v) {
size_t xn_t294 = xn_root_mark();
#line 25 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t295 = xn_str_int(xn_p_v);
xn_root_add(xn_t295);
xn_root_add(xn_t295);
xn_Cls_Format *xn_t296 = xn_Cls_Format_new(xn_t295, 0, 32);
xn_root_add(xn_t296);
xn_root_add(xn_t296);
    {
xn_root_restore(xn_t294);
    }

return xn_t296;
    return (xn_Cls_Format *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Format * xn_Cls_Format_float(double xn_p_v) {
size_t xn_t297 = xn_root_mark();
#line 29 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t298 = xn_str_double(xn_p_v);
xn_root_add(xn_t298);
xn_root_add(xn_t298);
xn_Cls_Format *xn_t299 = xn_Cls_Format_new(xn_t298, 0, 32);
xn_root_add(xn_t299);
xn_root_add(xn_t299);
    {
xn_root_restore(xn_t297);
    }

return xn_t299;
    return (xn_Cls_Format *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Format * xn_Cls_Format_string(rt_string * xn_p_v) {
size_t xn_t300 = xn_root_mark();
xn_root_add(xn_p_v);
#line 33 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t301 = rt_retain(xn_p_v);
xn_root_add(xn_t301);
xn_root_add(xn_t301);
xn_Cls_Format *xn_t302 = xn_Cls_Format_new(xn_t301, 0, 32);
xn_root_add(xn_t302);
xn_root_add(xn_t302);
    {
xn_root_restore(xn_t300);
    }

return xn_t302;
    return (xn_Cls_Format *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Format * xn_Cls_Format_bool(int xn_p_v) {
size_t xn_t303 = xn_root_mark();
#line 37 "tests/b3/fixtures/bundle_text/app.x"
    if ((xn_p_v)) {
        size_t xn_t304 = xn_root_mark();
        #line 38 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t305 = rt_string_from_c("true");
xn_root_add(xn_t305);
        xn_root_add(xn_t305);
        xn_root_add(xn_t305);
        xn_Cls_Format *xn_t306 = xn_Cls_Format_new(xn_t305, 0, 32);
xn_root_add(xn_t306);
        xn_root_add(xn_t306);
        xn_root_add(xn_t306);
            {
        xn_root_restore(xn_t304);
            }
            {
        xn_root_restore(xn_t303);
            }

        return xn_t306;

    }
#line 40 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t307 = rt_string_from_c("false");
xn_root_add(xn_t307);
xn_root_add(xn_t307);
xn_Cls_Format *xn_t308 = xn_Cls_Format_new(xn_t307, 0, 32);
xn_root_add(xn_t308);
xn_root_add(xn_t308);
    {
xn_root_restore(xn_t303);
    }

return xn_t308;
    return (xn_Cls_Format *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Format * xn_Cls_Format_width(xn_Cls_Format *self, int64_t xn_p_w) {
size_t xn_t309 = xn_root_mark();
xn_root_add(self);
#line 44 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t310 = rt_retain(self->text);
xn_root_add(xn_t310);
xn_root_add(xn_t310);
xn_Cls_Format *xn_t311 = xn_Cls_Format_new(xn_t310, xn_p_w, self->pad);
xn_root_add(xn_t311);
xn_root_add(xn_t311);
    {
xn_root_restore(xn_t309);
    }

return xn_t311;
    return (xn_Cls_Format *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Format * xn_Cls_Format_pad(xn_Cls_Format *self, xn_char xn_p_c) {
size_t xn_t312 = xn_root_mark();
xn_root_add(self);
#line 48 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t313 = rt_retain(self->text);
xn_root_add(xn_t313);
xn_root_add(xn_t313);
xn_Cls_Format *xn_t314 = xn_Cls_Format_new(xn_t313, self->width, xn_p_c);
xn_root_add(xn_t314);
xn_root_add(xn_t314);
    {
xn_root_restore(xn_t312);
    }

return xn_t314;
    return (xn_Cls_Format *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Format_build(xn_Cls_Format *self) {
size_t xn_t315 = xn_root_mark();
xn_root_add(self);
#line 52 "tests/b3/fixtures/bundle_text/app.x"
rt_string *res = rt_retain(self->text);
xn_root_add(res);
xn_root_add(res);
xn_gc_safepoint();
#line 53 "tests/b3/fixtures/bundle_text/app.x"
rt_string *unit = xn_str_char((int32_t)(self->pad));
xn_root_add(unit);
xn_root_add(unit);
xn_gc_safepoint();
#line 54 "tests/b3/fixtures/bundle_text/app.x"
    while (((xn_str_length(res) < self->width))) {
    size_t xn_t318 = xn_root_mark();
    #line 55 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t319 = rt_retain(unit);
xn_root_add(xn_t319);
    xn_root_add(xn_t319);
    rt_string *xn_t320 = rt_retain(res);
xn_root_add(xn_t320);
    xn_root_add(xn_t320);
    rt_string *xn_t321 = xn_concat(xn_t319, xn_t320);
xn_root_add(xn_t321);
    xn_root_add(xn_t321);
    xn_root_release(res);
    rt_release(res);
    res = xn_t321;
    xn_root_hold(res);
    xn_gc_safepoint();
        {
        xn_root_restore(xn_t318);
        }

    xn_gc_safepoint();
    }
#line 57 "tests/b3/fixtures/bundle_text/app.x"
rt_retain(res);
    {
rt_release(unit);
    }
    {
rt_release(res);
    }
    {
xn_root_restore(xn_t315);
    }

return res;
xn_root_release(res);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

/* 类 Regex（M4.4b） */
typedef struct xn_Cls_Regex {
    rt_header hdr;
    rt_string * pattern;
} xn_Cls_Regex;

static void xn_Cls_Regex_deinit_hook(void *p) {
    xn_Cls_Regex *o = (xn_Cls_Regex *)p;
    rt_release(o->pattern);
}

static void xn_Cls_Regex_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_Regex *o = (xn_Cls_Regex *)p;
    if (o->pattern) { visit(o->pattern); }
}

static const rt_type RT_TYPE_XN_Regex = { "Regex", sizeof(xn_Cls_Regex), xn_Cls_Regex_deinit_hook, xn_Cls_Regex_gc_scan };

static void xn_Cls_Regex_new_init(xn_Cls_Regex *o, rt_string * xn_p_pattern) {
size_t xn_t322 = xn_root_mark();
xn_root_add(o);
xn_root_add(xn_p_pattern);
#line 265 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t323 = rt_retain(xn_p_pattern);
xn_root_add(xn_t323);
rt_release(o->pattern);
o->pattern = xn_t323;
    {
    xn_root_restore(xn_t322);
    }
}

static xn_Cls_Regex *xn_Cls_Regex_new(rt_string * xn_p_pattern) {
    xn_Cls_Regex *o = (xn_Cls_Regex *)xn_gc_new(&RT_TYPE_XN_Regex);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_Regex) - sizeof(rt_header));
    xn_Cls_Regex_new_init(o, xn_p_pattern);
    return o;
}

static xn_Result_Regex_Error xn_Cls_Regex_compile(rt_string * xn_p_pattern);
static int xn_Cls_Regex_isMatch(xn_Cls_Regex *self, rt_string * xn_p_text);

static xn_Result_Regex_Error xn_Cls_Regex_compile(rt_string * xn_p_pattern) {
    xn_Result_Regex_Error xn_ret;
size_t xn_t324 = xn_root_mark();
xn_root_add(xn_p_pattern);
#line 269 "tests/b3/fixtures/bundle_text/app.x"
int64_t i = 0;
#line 270 "tests/b3/fixtures/bundle_text/app.x"
    while (((i < xn_str_length(xn_p_pattern)))) {
    size_t xn_t325 = xn_root_mark();
    #line 271 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *ch = xn_str_substr(xn_p_pattern, i, 1);
xn_root_add(ch);
    xn_root_add(ch);
    xn_root_add(ch);
    xn_gc_safepoint();
    #line 272 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t327 = rt_retain(ch);
xn_root_add(xn_t327);
    xn_root_add(xn_t327);
    rt_string *xn_t328 = rt_string_from_c("(");
xn_root_add(xn_t328);
    xn_root_add(xn_t328);
    rt_string *xn_t329 = rt_retain(ch);
xn_root_add(xn_t329);
    xn_root_add(xn_t329);
    rt_string *xn_t330 = rt_string_from_c(")");
xn_root_add(xn_t330);
    xn_root_add(xn_t330);
    rt_string *xn_t331 = rt_retain(ch);
xn_root_add(xn_t331);
    xn_root_add(xn_t331);
    rt_string *xn_t332 = rt_string_from_c("[");
xn_root_add(xn_t332);
    xn_root_add(xn_t332);
    rt_string *xn_t333 = rt_retain(ch);
xn_root_add(xn_t333);
    xn_root_add(xn_t333);
    rt_string *xn_t334 = rt_string_from_c("]");
xn_root_add(xn_t334);
    xn_root_add(xn_t334);
    rt_string *xn_t335 = rt_retain(ch);
xn_root_add(xn_t335);
    xn_root_add(xn_t335);
    rt_string *xn_t336 = rt_string_from_c("|");
xn_root_add(xn_t336);
    xn_root_add(xn_t336);
    rt_string *xn_t337 = rt_retain(ch);
xn_root_add(xn_t337);
    xn_root_add(xn_t337);
    rt_string *xn_t338 = rt_string_from_c("\\");
xn_root_add(xn_t338);
    xn_root_add(xn_t338);
        if (((((((xn_str_eq(xn_t327, xn_t328)) || (xn_str_eq(xn_t329, xn_t330))) || (xn_str_eq(xn_t331, xn_t332))) || (xn_str_eq(xn_t333, xn_t334))) || (xn_str_eq(xn_t335, xn_t336))) || (xn_str_eq(xn_t337, xn_t338)))) {
            size_t xn_t339 = xn_root_mark();
            #line 273 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t340 = rt_string_from_c("Regex.compile: 暂不支持该 ERE 构造");
xn_root_add(xn_t340);
    xn_root_add(xn_t340);
            xn_root_add(xn_t340);
            xn_root_add(xn_t340);
            xn_ret = (xn_Result_Regex_Error){0, NULL, xn_textErr(xn_t340)};
                {
            xn_root_restore(xn_t339);
                }
                {
            rt_release(ch);
                }
                {
            xn_root_restore(xn_t325);
                }
                {
            xn_root_restore(xn_t324);
                }

            return xn_ret;

        }
    #line 275 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t341 = rt_retain(ch);
xn_root_add(xn_t341);
    xn_root_add(xn_t341);
    rt_string *xn_t342 = rt_string_from_c("*");
xn_root_add(xn_t342);
    xn_root_add(xn_t342);
    rt_string *xn_t343 = rt_retain(ch);
xn_root_add(xn_t343);
    xn_root_add(xn_t343);
    rt_string *xn_t344 = rt_string_from_c("+");
xn_root_add(xn_t344);
    xn_root_add(xn_t344);
    rt_string *xn_t345 = rt_retain(ch);
xn_root_add(xn_t345);
    xn_root_add(xn_t345);
    rt_string *xn_t346 = rt_string_from_c("?");
xn_root_add(xn_t346);
    xn_root_add(xn_t346);
        if (((((xn_str_eq(xn_t341, xn_t342) || xn_str_eq(xn_t343, xn_t344)) || xn_str_eq(xn_t345, xn_t346))) && ((i == 0)))) {
            size_t xn_t347 = xn_root_mark();
            #line 276 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t348 = rt_string_from_c("Regex.compile: 量词缺少原子");
xn_root_add(xn_t348);
    xn_root_add(xn_t348);
            xn_root_add(xn_t348);
            xn_root_add(xn_t348);
            xn_ret = (xn_Result_Regex_Error){0, NULL, xn_textErr(xn_t348)};
                {
            xn_root_restore(xn_t347);
                }
                {
            rt_release(ch);
                }
                {
            xn_root_restore(xn_t325);
                }
                {
            xn_root_restore(xn_t324);
                }

            return xn_ret;

        }
    #line 278 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t349 = rt_retain(ch);
xn_root_add(xn_t349);
    xn_root_add(xn_t349);
    rt_string *xn_t350 = rt_string_from_c("$");
xn_root_add(xn_t350);
    xn_root_add(xn_t350);
        if (((xn_str_eq(xn_t349, xn_t350)) && ((i != (xn_str_length(xn_p_pattern) - 1))))) {
            size_t xn_t351 = xn_root_mark();
            #line 279 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t352 = rt_string_from_c("Regex.compile: $ 只能在末尾");
xn_root_add(xn_t352);
    xn_root_add(xn_t352);
            xn_root_add(xn_t352);
            xn_root_add(xn_t352);
            xn_ret = (xn_Result_Regex_Error){0, NULL, xn_textErr(xn_t352)};
                {
            xn_root_restore(xn_t351);
                }
                {
            rt_release(ch);
                }
                {
            xn_root_restore(xn_t325);
                }
                {
            xn_root_restore(xn_t324);
                }

            return xn_ret;

        }
    #line 281 "tests/b3/fixtures/bundle_text/app.x"
    i = (i + 1);
        {
        rt_release(ch);
        }
        {
        xn_root_restore(xn_t325);
        }

    xn_gc_safepoint();
    }
#line 283 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t353 = rt_retain(xn_p_pattern);
xn_root_add(xn_t353);
xn_root_add(xn_t353);
xn_ret = (xn_Result_Regex_Error){1, xn_Cls_Regex_new(xn_t353), 0};
    {
xn_root_restore(xn_t324);
    }

return xn_ret;
}

static int xn_Cls_Regex_isMatch(xn_Cls_Regex *self, rt_string * xn_p_text) {
size_t xn_t354 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_text);
#line 287 "tests/b3/fixtures/bundle_text/app.x"
int64_t pi = 0;
#line 288 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t355 = rt_retain(self->pattern);
xn_root_add(xn_t355);
rt_string *xn_t356 = rt_retain(self->pattern);
xn_root_add(xn_t356);
rt_string *xn_t357 = xn_str_substr(xn_t356, 0, 1);
xn_root_add(xn_t357);
rt_string *xn_t358 = rt_string_from_c("^");
xn_root_add(xn_t358);
    if ((((xn_str_length(xn_t355) > 0)) && (xn_str_eq(xn_t357, xn_t358)))) {
        size_t xn_t359 = xn_root_mark();
        #line 289 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t360 = rt_retain(self->pattern);
xn_root_add(xn_t360);
        xn_root_add(xn_t360);
        xn_root_add(xn_t360);
        rt_string *xn_t361 = rt_retain(xn_p_text);
xn_root_add(xn_t361);
        xn_root_add(xn_t361);
        xn_root_add(xn_t361);
        int xn_t362 = xn_regexMatchAt(xn_t360, 1, xn_t361, 0);
            {
        xn_root_restore(xn_t359);
            }
            {
        xn_root_restore(xn_t354);
            }

        return xn_t362;

    }
#line 291 "tests/b3/fixtures/bundle_text/app.x"
int64_t start = 0;
#line 292 "tests/b3/fixtures/bundle_text/app.x"
    while (((start <= xn_str_length(xn_p_text)))) {
    size_t xn_t363 = xn_root_mark();
    #line 293 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t364 = rt_retain(self->pattern);
xn_root_add(xn_t364);
    xn_root_add(xn_t364);
    rt_string *xn_t365 = rt_retain(xn_p_text);
xn_root_add(xn_t365);
    xn_root_add(xn_t365);
        if ((xn_regexMatchAt(xn_t364, 0, xn_t365, start))) {
            size_t xn_t366 = xn_root_mark();
            #line 293 "tests/b3/fixtures/bundle_text/app.x"
            int xn_t367 = 1;
                {
            xn_root_restore(xn_t366);
                }
                {
            xn_root_restore(xn_t363);
                }
                {
            xn_root_restore(xn_t354);
                }

            return xn_t367;

        }
    #line 294 "tests/b3/fixtures/bundle_text/app.x"
    start = (start + 1);
        {
        xn_root_restore(xn_t363);
        }

    xn_gc_safepoint();
    }
#line 296 "tests/b3/fixtures/bundle_text/app.x"
int xn_t368 = 0;
    {
xn_root_restore(xn_t354);
    }

return xn_t368;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static void xn_init_vtables(void) {
    xn_vt_CauseError[0] = (void *)&xn_Cls_CauseError_kind;
    xn_vt_CauseError[1] = (void *)&xn_Cls_CauseError_describe;
}

static void xn_init_enums(void) {
}

static rt_string *xn_result_error_copy_rt(rt_string *err) {
    return rt_string_new(err->bytes, err->len);
}

int64_t xn_digitOf(rt_string * xn_p_ch) {
size_t xn_t1 = xn_root_mark();
xn_root_add(xn_p_ch);
#line 64 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t2 = rt_retain(xn_p_ch);
xn_root_add(xn_t2);
rt_string *xn_t3 = rt_string_from_c("0");
xn_root_add(xn_t3);
    if ((xn_str_eq(xn_t2, xn_t3))) {
        size_t xn_t4 = xn_root_mark();
        #line 64 "tests/b3/fixtures/bundle_text/app.x"
        int64_t xn_t5 = 0;
            {
        xn_root_restore(xn_t4);
            }
            {
        xn_root_restore(xn_t1);
            }

        return xn_t5;

    }
#line 65 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t6 = rt_retain(xn_p_ch);
xn_root_add(xn_t6);
rt_string *xn_t7 = rt_string_from_c("1");
xn_root_add(xn_t7);
    if ((xn_str_eq(xn_t6, xn_t7))) {
        size_t xn_t8 = xn_root_mark();
        #line 65 "tests/b3/fixtures/bundle_text/app.x"
        int64_t xn_t9 = 1;
            {
        xn_root_restore(xn_t8);
            }
            {
        xn_root_restore(xn_t1);
            }

        return xn_t9;

    }
#line 66 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t10 = rt_retain(xn_p_ch);
xn_root_add(xn_t10);
rt_string *xn_t11 = rt_string_from_c("2");
xn_root_add(xn_t11);
    if ((xn_str_eq(xn_t10, xn_t11))) {
        size_t xn_t12 = xn_root_mark();
        #line 66 "tests/b3/fixtures/bundle_text/app.x"
        int64_t xn_t13 = 2;
            {
        xn_root_restore(xn_t12);
            }
            {
        xn_root_restore(xn_t1);
            }

        return xn_t13;

    }
#line 67 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t14 = rt_retain(xn_p_ch);
xn_root_add(xn_t14);
rt_string *xn_t15 = rt_string_from_c("3");
xn_root_add(xn_t15);
    if ((xn_str_eq(xn_t14, xn_t15))) {
        size_t xn_t16 = xn_root_mark();
        #line 67 "tests/b3/fixtures/bundle_text/app.x"
        int64_t xn_t17 = 3;
            {
        xn_root_restore(xn_t16);
            }
            {
        xn_root_restore(xn_t1);
            }

        return xn_t17;

    }
#line 68 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t18 = rt_retain(xn_p_ch);
xn_root_add(xn_t18);
rt_string *xn_t19 = rt_string_from_c("4");
xn_root_add(xn_t19);
    if ((xn_str_eq(xn_t18, xn_t19))) {
        size_t xn_t20 = xn_root_mark();
        #line 68 "tests/b3/fixtures/bundle_text/app.x"
        int64_t xn_t21 = 4;
            {
        xn_root_restore(xn_t20);
            }
            {
        xn_root_restore(xn_t1);
            }

        return xn_t21;

    }
#line 69 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t22 = rt_retain(xn_p_ch);
xn_root_add(xn_t22);
rt_string *xn_t23 = rt_string_from_c("5");
xn_root_add(xn_t23);
    if ((xn_str_eq(xn_t22, xn_t23))) {
        size_t xn_t24 = xn_root_mark();
        #line 69 "tests/b3/fixtures/bundle_text/app.x"
        int64_t xn_t25 = 5;
            {
        xn_root_restore(xn_t24);
            }
            {
        xn_root_restore(xn_t1);
            }

        return xn_t25;

    }
#line 70 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t26 = rt_retain(xn_p_ch);
xn_root_add(xn_t26);
rt_string *xn_t27 = rt_string_from_c("6");
xn_root_add(xn_t27);
    if ((xn_str_eq(xn_t26, xn_t27))) {
        size_t xn_t28 = xn_root_mark();
        #line 70 "tests/b3/fixtures/bundle_text/app.x"
        int64_t xn_t29 = 6;
            {
        xn_root_restore(xn_t28);
            }
            {
        xn_root_restore(xn_t1);
            }

        return xn_t29;

    }
#line 71 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t30 = rt_retain(xn_p_ch);
xn_root_add(xn_t30);
rt_string *xn_t31 = rt_string_from_c("7");
xn_root_add(xn_t31);
    if ((xn_str_eq(xn_t30, xn_t31))) {
        size_t xn_t32 = xn_root_mark();
        #line 71 "tests/b3/fixtures/bundle_text/app.x"
        int64_t xn_t33 = 7;
            {
        xn_root_restore(xn_t32);
            }
            {
        xn_root_restore(xn_t1);
            }

        return xn_t33;

    }
#line 72 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t34 = rt_retain(xn_p_ch);
xn_root_add(xn_t34);
rt_string *xn_t35 = rt_string_from_c("8");
xn_root_add(xn_t35);
    if ((xn_str_eq(xn_t34, xn_t35))) {
        size_t xn_t36 = xn_root_mark();
        #line 72 "tests/b3/fixtures/bundle_text/app.x"
        int64_t xn_t37 = 8;
            {
        xn_root_restore(xn_t36);
            }
            {
        xn_root_restore(xn_t1);
            }

        return xn_t37;

    }
#line 73 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t38 = rt_retain(xn_p_ch);
xn_root_add(xn_t38);
rt_string *xn_t39 = rt_string_from_c("9");
xn_root_add(xn_t39);
    if ((xn_str_eq(xn_t38, xn_t39))) {
        size_t xn_t40 = xn_root_mark();
        #line 73 "tests/b3/fixtures/bundle_text/app.x"
        int64_t xn_t41 = 9;
            {
        xn_root_restore(xn_t40);
            }
            {
        xn_root_restore(xn_t1);
            }

        return xn_t41;

    }
#line 74 "tests/b3/fixtures/bundle_text/app.x"
int64_t xn_t42 = (-(1));
    {
xn_root_restore(xn_t1);
    }

return xn_t42;
}

double xn_digitOfD(rt_string * xn_p_ch) {
size_t xn_t43 = xn_root_mark();
xn_root_add(xn_p_ch);
#line 78 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t44 = rt_retain(xn_p_ch);
xn_root_add(xn_t44);
rt_string *xn_t45 = rt_string_from_c("0");
xn_root_add(xn_t45);
    if ((xn_str_eq(xn_t44, xn_t45))) {
        size_t xn_t46 = xn_root_mark();
        #line 78 "tests/b3/fixtures/bundle_text/app.x"
        double xn_t47 = 0.0;
            {
        xn_root_restore(xn_t46);
            }
            {
        xn_root_restore(xn_t43);
            }

        return xn_t47;

    }
#line 79 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t48 = rt_retain(xn_p_ch);
xn_root_add(xn_t48);
rt_string *xn_t49 = rt_string_from_c("1");
xn_root_add(xn_t49);
    if ((xn_str_eq(xn_t48, xn_t49))) {
        size_t xn_t50 = xn_root_mark();
        #line 79 "tests/b3/fixtures/bundle_text/app.x"
        double xn_t51 = 1.0;
            {
        xn_root_restore(xn_t50);
            }
            {
        xn_root_restore(xn_t43);
            }

        return xn_t51;

    }
#line 80 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t52 = rt_retain(xn_p_ch);
xn_root_add(xn_t52);
rt_string *xn_t53 = rt_string_from_c("2");
xn_root_add(xn_t53);
    if ((xn_str_eq(xn_t52, xn_t53))) {
        size_t xn_t54 = xn_root_mark();
        #line 80 "tests/b3/fixtures/bundle_text/app.x"
        double xn_t55 = 2.0;
            {
        xn_root_restore(xn_t54);
            }
            {
        xn_root_restore(xn_t43);
            }

        return xn_t55;

    }
#line 81 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t56 = rt_retain(xn_p_ch);
xn_root_add(xn_t56);
rt_string *xn_t57 = rt_string_from_c("3");
xn_root_add(xn_t57);
    if ((xn_str_eq(xn_t56, xn_t57))) {
        size_t xn_t58 = xn_root_mark();
        #line 81 "tests/b3/fixtures/bundle_text/app.x"
        double xn_t59 = 3.0;
            {
        xn_root_restore(xn_t58);
            }
            {
        xn_root_restore(xn_t43);
            }

        return xn_t59;

    }
#line 82 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t60 = rt_retain(xn_p_ch);
xn_root_add(xn_t60);
rt_string *xn_t61 = rt_string_from_c("4");
xn_root_add(xn_t61);
    if ((xn_str_eq(xn_t60, xn_t61))) {
        size_t xn_t62 = xn_root_mark();
        #line 82 "tests/b3/fixtures/bundle_text/app.x"
        double xn_t63 = 4.0;
            {
        xn_root_restore(xn_t62);
            }
            {
        xn_root_restore(xn_t43);
            }

        return xn_t63;

    }
#line 83 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t64 = rt_retain(xn_p_ch);
xn_root_add(xn_t64);
rt_string *xn_t65 = rt_string_from_c("5");
xn_root_add(xn_t65);
    if ((xn_str_eq(xn_t64, xn_t65))) {
        size_t xn_t66 = xn_root_mark();
        #line 83 "tests/b3/fixtures/bundle_text/app.x"
        double xn_t67 = 5.0;
            {
        xn_root_restore(xn_t66);
            }
            {
        xn_root_restore(xn_t43);
            }

        return xn_t67;

    }
#line 84 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t68 = rt_retain(xn_p_ch);
xn_root_add(xn_t68);
rt_string *xn_t69 = rt_string_from_c("6");
xn_root_add(xn_t69);
    if ((xn_str_eq(xn_t68, xn_t69))) {
        size_t xn_t70 = xn_root_mark();
        #line 84 "tests/b3/fixtures/bundle_text/app.x"
        double xn_t71 = 6.0;
            {
        xn_root_restore(xn_t70);
            }
            {
        xn_root_restore(xn_t43);
            }

        return xn_t71;

    }
#line 85 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t72 = rt_retain(xn_p_ch);
xn_root_add(xn_t72);
rt_string *xn_t73 = rt_string_from_c("7");
xn_root_add(xn_t73);
    if ((xn_str_eq(xn_t72, xn_t73))) {
        size_t xn_t74 = xn_root_mark();
        #line 85 "tests/b3/fixtures/bundle_text/app.x"
        double xn_t75 = 7.0;
            {
        xn_root_restore(xn_t74);
            }
            {
        xn_root_restore(xn_t43);
            }

        return xn_t75;

    }
#line 86 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t76 = rt_retain(xn_p_ch);
xn_root_add(xn_t76);
rt_string *xn_t77 = rt_string_from_c("8");
xn_root_add(xn_t77);
    if ((xn_str_eq(xn_t76, xn_t77))) {
        size_t xn_t78 = xn_root_mark();
        #line 86 "tests/b3/fixtures/bundle_text/app.x"
        double xn_t79 = 8.0;
            {
        xn_root_restore(xn_t78);
            }
            {
        xn_root_restore(xn_t43);
            }

        return xn_t79;

    }
#line 87 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t80 = rt_retain(xn_p_ch);
xn_root_add(xn_t80);
rt_string *xn_t81 = rt_string_from_c("9");
xn_root_add(xn_t81);
    if ((xn_str_eq(xn_t80, xn_t81))) {
        size_t xn_t82 = xn_root_mark();
        #line 87 "tests/b3/fixtures/bundle_text/app.x"
        double xn_t83 = 9.0;
            {
        xn_root_restore(xn_t82);
            }
            {
        xn_root_restore(xn_t43);
            }

        return xn_t83;

    }
#line 88 "tests/b3/fixtures/bundle_text/app.x"
double xn_t84 = (-(1.0));
    {
xn_root_restore(xn_t43);
    }

return xn_t84;
}

xn_proto_Error xn_textErr(rt_string * xn_p_msg) {
size_t xn_t85 = xn_root_mark();
xn_root_add(xn_p_msg);
#line 92 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t86 = rt_retain(xn_p_msg);
xn_root_add(xn_t86);
xn_root_add(xn_t86);
    {
xn_root_restore(xn_t85);
    }

return xn_Cls_CauseError_new(0, xn_t86, NULL);
}

xn_Result_Int_Error xn_parseInt(rt_string * xn_p_s) {
    xn_Result_Int_Error xn_ret;
size_t xn_t87 = xn_root_mark();
xn_root_add(xn_p_s);
#line 97 "tests/b3/fixtures/bundle_text/app.x"
int64_t n = xn_str_length(xn_p_s);
#line 98 "tests/b3/fixtures/bundle_text/app.x"
    if (((n == 0))) {
        size_t xn_t88 = xn_root_mark();
        #line 98 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t89 = rt_string_from_c("parseInt: 空串");
xn_root_add(xn_t89);
        xn_root_add(xn_t89);
        xn_root_add(xn_t89);
        xn_ret = (xn_Result_Int_Error){0, 0, xn_textErr(xn_t89)};
            {
        xn_root_restore(xn_t88);
            }
            {
        xn_root_restore(xn_t87);
            }

        return xn_ret;

    }
#line 99 "tests/b3/fixtures/bundle_text/app.x"
int64_t i = 0;
#line 100 "tests/b3/fixtures/bundle_text/app.x"
int neg = 0;
#line 101 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t90 = xn_str_substr(xn_p_s, 0, 1);
xn_root_add(xn_t90);
rt_string *xn_t91 = rt_string_from_c("-");
xn_root_add(xn_t91);
    if ((xn_str_eq(xn_t90, xn_t91))) {
        size_t xn_t92 = xn_root_mark();
        #line 101 "tests/b3/fixtures/bundle_text/app.x"
        neg = 1;
        #line 101 "tests/b3/fixtures/bundle_text/app.x"
        i = 1;
            {
            xn_root_restore(xn_t92);
            }

    } else {
        rt_string *xn_t94 = xn_str_substr(xn_p_s, 0, 1);
xn_root_add(xn_t94);
        xn_root_add(xn_t94);
        rt_string *xn_t95 = rt_string_from_c("+");
xn_root_add(xn_t95);
        xn_root_add(xn_t95);
            if ((xn_str_eq(xn_t94, xn_t95))) {
                size_t xn_t96 = xn_root_mark();
                #line 102 "tests/b3/fixtures/bundle_text/app.x"
                i = 1;
                    {
                    xn_root_restore(xn_t96);
                    }

            }
    }
#line 103 "tests/b3/fixtures/bundle_text/app.x"
    if (((i >= n))) {
        size_t xn_t97 = xn_root_mark();
        #line 103 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t98 = rt_string_from_c("parseInt: 缺少数字");
xn_root_add(xn_t98);
        xn_root_add(xn_t98);
        xn_root_add(xn_t98);
        xn_ret = (xn_Result_Int_Error){0, 0, xn_textErr(xn_t98)};
            {
        xn_root_restore(xn_t97);
            }
            {
        xn_root_restore(xn_t87);
            }

        return xn_ret;

    }
#line 104 "tests/b3/fixtures/bundle_text/app.x"
int64_t v = 0;
#line 105 "tests/b3/fixtures/bundle_text/app.x"
int any = 0;
#line 106 "tests/b3/fixtures/bundle_text/app.x"
    while (((i < n))) {
    size_t xn_t99 = xn_root_mark();
    #line 107 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t100 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t100);
    xn_root_add(xn_t100);
    int64_t d = xn_digitOf(xn_t100);
    #line 108 "tests/b3/fixtures/bundle_text/app.x"
        if (((d < 0))) {
            size_t xn_t101 = xn_root_mark();
            #line 108 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t102 = rt_string_from_c("parseInt: 非法字符");
xn_root_add(xn_t102);
    xn_root_add(xn_t102);
            xn_root_add(xn_t102);
            xn_root_add(xn_t102);
            xn_ret = (xn_Result_Int_Error){0, 0, xn_textErr(xn_t102)};
                {
            xn_root_restore(xn_t101);
                }
                {
            xn_root_restore(xn_t99);
                }
                {
            xn_root_restore(xn_t87);
                }

            return xn_ret;

        }
    #line 109 "tests/b3/fixtures/bundle_text/app.x"
    any = 1;
    #line 110 "tests/b3/fixtures/bundle_text/app.x"
    int64_t limit = 922337203685477580;
    #line 111 "tests/b3/fixtures/bundle_text/app.x"
        if (((v > limit))) {
            size_t xn_t103 = xn_root_mark();
            #line 111 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t104 = rt_string_from_c("parseInt: 溢出");
xn_root_add(xn_t104);
    xn_root_add(xn_t104);
            xn_root_add(xn_t104);
            xn_root_add(xn_t104);
            xn_ret = (xn_Result_Int_Error){0, 0, xn_textErr(xn_t104)};
                {
            xn_root_restore(xn_t103);
                }
                {
            xn_root_restore(xn_t99);
                }
                {
            xn_root_restore(xn_t87);
                }

            return xn_ret;

        }
    #line 112 "tests/b3/fixtures/bundle_text/app.x"
    v = ((v * 10) + d);
    #line 113 "tests/b3/fixtures/bundle_text/app.x"
        if ((((!(neg))) && ((v < 0)))) {
            size_t xn_t105 = xn_root_mark();
            #line 113 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t106 = rt_string_from_c("parseInt: 溢出");
xn_root_add(xn_t106);
    xn_root_add(xn_t106);
            xn_root_add(xn_t106);
            xn_root_add(xn_t106);
            xn_ret = (xn_Result_Int_Error){0, 0, xn_textErr(xn_t106)};
                {
            xn_root_restore(xn_t105);
                }
                {
            xn_root_restore(xn_t99);
                }
                {
            xn_root_restore(xn_t87);
                }

            return xn_ret;

        }
    #line 114 "tests/b3/fixtures/bundle_text/app.x"
    i = (i + 1);
        {
        xn_root_restore(xn_t99);
        }

    xn_gc_safepoint();
    }
#line 116 "tests/b3/fixtures/bundle_text/app.x"
    if (((!(any)))) {
        size_t xn_t107 = xn_root_mark();
        #line 116 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t108 = rt_string_from_c("parseInt: 缺少数字");
xn_root_add(xn_t108);
        xn_root_add(xn_t108);
        xn_root_add(xn_t108);
        xn_ret = (xn_Result_Int_Error){0, 0, xn_textErr(xn_t108)};
            {
        xn_root_restore(xn_t107);
            }
            {
        xn_root_restore(xn_t87);
            }

        return xn_ret;

    }
#line 117 "tests/b3/fixtures/bundle_text/app.x"
    if ((neg)) {
        size_t xn_t109 = xn_root_mark();
        #line 117 "tests/b3/fixtures/bundle_text/app.x"
        xn_ret = (xn_Result_Int_Error){1, (0 - v), 0};
            {
        xn_root_restore(xn_t109);
            }
            {
        xn_root_restore(xn_t87);
            }

        return xn_ret;

    }
#line 118 "tests/b3/fixtures/bundle_text/app.x"
xn_ret = (xn_Result_Int_Error){1, v, 0};
    {
xn_root_restore(xn_t87);
    }

return xn_ret;
}

xn_Result_Double_Error xn_parseFloat(rt_string * xn_p_s) {
    xn_Result_Double_Error xn_ret;
size_t xn_t110 = xn_root_mark();
xn_root_add(xn_p_s);
#line 123 "tests/b3/fixtures/bundle_text/app.x"
int64_t n = xn_str_length(xn_p_s);
#line 124 "tests/b3/fixtures/bundle_text/app.x"
    if (((n == 0))) {
        size_t xn_t111 = xn_root_mark();
        #line 124 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t112 = rt_string_from_c("parseFloat: 空串");
xn_root_add(xn_t112);
        xn_root_add(xn_t112);
        xn_root_add(xn_t112);
        xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t112)};
            {
        xn_root_restore(xn_t111);
            }
            {
        xn_root_restore(xn_t110);
            }

        return xn_ret;

    }
#line 125 "tests/b3/fixtures/bundle_text/app.x"
int64_t i = 0;
#line 126 "tests/b3/fixtures/bundle_text/app.x"
int neg = 0;
#line 127 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t113 = xn_str_substr(xn_p_s, 0, 1);
xn_root_add(xn_t113);
rt_string *xn_t114 = rt_string_from_c("-");
xn_root_add(xn_t114);
    if ((xn_str_eq(xn_t113, xn_t114))) {
        size_t xn_t115 = xn_root_mark();
        #line 127 "tests/b3/fixtures/bundle_text/app.x"
        neg = 1;
        #line 127 "tests/b3/fixtures/bundle_text/app.x"
        i = 1;
            {
            xn_root_restore(xn_t115);
            }

    } else {
        rt_string *xn_t117 = xn_str_substr(xn_p_s, 0, 1);
xn_root_add(xn_t117);
        xn_root_add(xn_t117);
        rt_string *xn_t118 = rt_string_from_c("+");
xn_root_add(xn_t118);
        xn_root_add(xn_t118);
            if ((xn_str_eq(xn_t117, xn_t118))) {
                size_t xn_t119 = xn_root_mark();
                #line 128 "tests/b3/fixtures/bundle_text/app.x"
                i = 1;
                    {
                    xn_root_restore(xn_t119);
                    }

            }
    }
#line 129 "tests/b3/fixtures/bundle_text/app.x"
double v = 0.0;
#line 130 "tests/b3/fixtures/bundle_text/app.x"
int any = 0;
#line 131 "tests/b3/fixtures/bundle_text/app.x"
    while (((i < n))) {
    size_t xn_t120 = xn_root_mark();
    #line 132 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *ch = xn_str_substr(xn_p_s, i, 1);
xn_root_add(ch);
    xn_root_add(ch);
    xn_root_add(ch);
    xn_gc_safepoint();
    #line 133 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t122 = rt_retain(ch);
xn_root_add(xn_t122);
    xn_root_add(xn_t122);
    rt_string *xn_t123 = rt_string_from_c(".");
xn_root_add(xn_t123);
    xn_root_add(xn_t123);
        if ((xn_str_eq(xn_t122, xn_t123))) {
            size_t xn_t124 = xn_root_mark();
            #line 133 "tests/b3/fixtures/bundle_text/app.x"
            xn_root_restore(xn_t124);
            xn_root_restore(xn_t120);
            break;
                {
                xn_root_restore(xn_t124);
                }

        }
    #line 134 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t125 = rt_retain(ch);
xn_root_add(xn_t125);
    xn_root_add(xn_t125);
    rt_string *xn_t126 = rt_string_from_c("e");
xn_root_add(xn_t126);
    xn_root_add(xn_t126);
    rt_string *xn_t127 = rt_retain(ch);
xn_root_add(xn_t127);
    xn_root_add(xn_t127);
    rt_string *xn_t128 = rt_string_from_c("E");
xn_root_add(xn_t128);
    xn_root_add(xn_t128);
        if (((xn_str_eq(xn_t125, xn_t126)) || (xn_str_eq(xn_t127, xn_t128)))) {
            size_t xn_t129 = xn_root_mark();
            #line 134 "tests/b3/fixtures/bundle_text/app.x"
            xn_root_restore(xn_t129);
            xn_root_restore(xn_t120);
            break;
                {
                xn_root_restore(xn_t129);
                }

        }
    #line 135 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t130 = rt_retain(ch);
xn_root_add(xn_t130);
    xn_root_add(xn_t130);
    double d = xn_digitOfD(xn_t130);
    #line 136 "tests/b3/fixtures/bundle_text/app.x"
        if (((d < 0.0))) {
            size_t xn_t131 = xn_root_mark();
            #line 136 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t132 = rt_string_from_c("parseFloat: 非法字符");
xn_root_add(xn_t132);
    xn_root_add(xn_t132);
            xn_root_add(xn_t132);
            xn_root_add(xn_t132);
            xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t132)};
                {
            xn_root_restore(xn_t131);
                }
                {
            rt_release(ch);
                }
                {
            xn_root_restore(xn_t120);
                }
                {
            xn_root_restore(xn_t110);
                }

            return xn_ret;

        }
    #line 137 "tests/b3/fixtures/bundle_text/app.x"
    v = ((v * 10.0) + d);
    #line 138 "tests/b3/fixtures/bundle_text/app.x"
    any = 1;
    #line 139 "tests/b3/fixtures/bundle_text/app.x"
    i = (i + 1);
        {
        rt_release(ch);
        }
        {
        xn_root_restore(xn_t120);
        }

    xn_gc_safepoint();
    }
#line 141 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t133 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t133);
rt_string *xn_t134 = rt_string_from_c(".");
xn_root_add(xn_t134);
    if ((((i < n)) && (xn_str_eq(xn_t133, xn_t134)))) {
        size_t xn_t135 = xn_root_mark();
        #line 142 "tests/b3/fixtures/bundle_text/app.x"
        i = (i + 1);
        #line 143 "tests/b3/fixtures/bundle_text/app.x"
        double scale = 0.1;
        #line 144 "tests/b3/fixtures/bundle_text/app.x"
            while (((i < n))) {
            size_t xn_t136 = xn_root_mark();
            #line 145 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *ch = xn_str_substr(xn_p_s, i, 1);
xn_root_add(ch);
        xn_root_add(ch);
            xn_root_add(ch);
            xn_root_add(ch);
            xn_gc_safepoint();
            #line 146 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t138 = rt_retain(ch);
xn_root_add(xn_t138);
        xn_root_add(xn_t138);
            xn_root_add(xn_t138);
            rt_string *xn_t139 = rt_string_from_c("e");
xn_root_add(xn_t139);
        xn_root_add(xn_t139);
            xn_root_add(xn_t139);
            rt_string *xn_t140 = rt_retain(ch);
xn_root_add(xn_t140);
        xn_root_add(xn_t140);
            xn_root_add(xn_t140);
            rt_string *xn_t141 = rt_string_from_c("E");
xn_root_add(xn_t141);
        xn_root_add(xn_t141);
            xn_root_add(xn_t141);
                if (((xn_str_eq(xn_t138, xn_t139)) || (xn_str_eq(xn_t140, xn_t141)))) {
                    size_t xn_t142 = xn_root_mark();
                    #line 146 "tests/b3/fixtures/bundle_text/app.x"
                    xn_root_restore(xn_t142);
                    xn_root_restore(xn_t136);
                    break;
                        {
                        xn_root_restore(xn_t142);
                        }

                }
            #line 147 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t143 = rt_retain(ch);
xn_root_add(xn_t143);
        xn_root_add(xn_t143);
            xn_root_add(xn_t143);
            double d = xn_digitOfD(xn_t143);
            #line 148 "tests/b3/fixtures/bundle_text/app.x"
                if (((d < 0.0))) {
                    size_t xn_t144 = xn_root_mark();
                    #line 148 "tests/b3/fixtures/bundle_text/app.x"
                    rt_string *xn_t145 = rt_string_from_c("parseFloat: 非法小数");
xn_root_add(xn_t145);
        xn_root_add(xn_t145);
            xn_root_add(xn_t145);
                    xn_root_add(xn_t145);
                    xn_root_add(xn_t145);
                    xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t145)};
                        {
                    xn_root_restore(xn_t144);
                        }
                        {
                    rt_release(ch);
                        }
                        {
                    xn_root_restore(xn_t136);
                        }
                        {
                    xn_root_restore(xn_t135);
                        }
                        {
                    xn_root_restore(xn_t110);
                        }

                    return xn_ret;

                }
            #line 149 "tests/b3/fixtures/bundle_text/app.x"
            v = (v + (d * scale));
            #line 150 "tests/b3/fixtures/bundle_text/app.x"
            scale = (scale * 0.1);
            #line 151 "tests/b3/fixtures/bundle_text/app.x"
            any = 1;
            #line 152 "tests/b3/fixtures/bundle_text/app.x"
            i = (i + 1);
                {
                rt_release(ch);
                }
                {
                xn_root_restore(xn_t136);
                }

            xn_gc_safepoint();
            }
            {
            xn_root_restore(xn_t135);
            }

    }
#line 155 "tests/b3/fixtures/bundle_text/app.x"
    if (((!(any)))) {
        size_t xn_t146 = xn_root_mark();
        #line 155 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t147 = rt_string_from_c("parseFloat: 缺少数字");
xn_root_add(xn_t147);
        xn_root_add(xn_t147);
        xn_root_add(xn_t147);
        xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t147)};
            {
        xn_root_restore(xn_t146);
            }
            {
        xn_root_restore(xn_t110);
            }

        return xn_ret;

    }
#line 156 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t148 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t148);
rt_string *xn_t149 = rt_string_from_c("e");
xn_root_add(xn_t149);
rt_string *xn_t150 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t150);
rt_string *xn_t151 = rt_string_from_c("E");
xn_root_add(xn_t151);
    if ((((i < n)) && ((xn_str_eq(xn_t148, xn_t149) || xn_str_eq(xn_t150, xn_t151))))) {
        size_t xn_t152 = xn_root_mark();
        #line 157 "tests/b3/fixtures/bundle_text/app.x"
        i = (i + 1);
        #line 158 "tests/b3/fixtures/bundle_text/app.x"
        int eneg = 0;
        #line 159 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t153 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t153);
        xn_root_add(xn_t153);
        rt_string *xn_t154 = rt_string_from_c("-");
xn_root_add(xn_t154);
        xn_root_add(xn_t154);
            if ((((i < n)) && (xn_str_eq(xn_t153, xn_t154)))) {
                size_t xn_t155 = xn_root_mark();
                #line 159 "tests/b3/fixtures/bundle_text/app.x"
                eneg = 1;
                #line 159 "tests/b3/fixtures/bundle_text/app.x"
                i = (i + 1);
                    {
                    xn_root_restore(xn_t155);
                    }

            } else {
                rt_string *xn_t157 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t157);
        xn_root_add(xn_t157);
                xn_root_add(xn_t157);
                rt_string *xn_t158 = rt_string_from_c("+");
xn_root_add(xn_t158);
        xn_root_add(xn_t158);
                xn_root_add(xn_t158);
                    if ((((i < n)) && (xn_str_eq(xn_t157, xn_t158)))) {
                        size_t xn_t159 = xn_root_mark();
                        #line 160 "tests/b3/fixtures/bundle_text/app.x"
                        i = (i + 1);
                            {
                            xn_root_restore(xn_t159);
                            }

                    }
            }
        #line 161 "tests/b3/fixtures/bundle_text/app.x"
            if (((i >= n))) {
                size_t xn_t160 = xn_root_mark();
                #line 161 "tests/b3/fixtures/bundle_text/app.x"
                rt_string *xn_t161 = rt_string_from_c("parseFloat: 指数缺少数字");
xn_root_add(xn_t161);
        xn_root_add(xn_t161);
                xn_root_add(xn_t161);
                xn_root_add(xn_t161);
                xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t161)};
                    {
                xn_root_restore(xn_t160);
                    }
                    {
                xn_root_restore(xn_t152);
                    }
                    {
                xn_root_restore(xn_t110);
                    }

                return xn_ret;

            }
        #line 162 "tests/b3/fixtures/bundle_text/app.x"
        int64_t e = 0;
        #line 163 "tests/b3/fixtures/bundle_text/app.x"
            while (((i < n))) {
            size_t xn_t162 = xn_root_mark();
            #line 164 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t163 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t163);
        xn_root_add(xn_t163);
            xn_root_add(xn_t163);
            int64_t d = xn_digitOf(xn_t163);
            #line 165 "tests/b3/fixtures/bundle_text/app.x"
                if (((d < 0))) {
                    size_t xn_t164 = xn_root_mark();
                    #line 165 "tests/b3/fixtures/bundle_text/app.x"
                    rt_string *xn_t165 = rt_string_from_c("parseFloat: 非法指数");
xn_root_add(xn_t165);
        xn_root_add(xn_t165);
            xn_root_add(xn_t165);
                    xn_root_add(xn_t165);
                    xn_root_add(xn_t165);
                    xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t165)};
                        {
                    xn_root_restore(xn_t164);
                        }
                        {
                    xn_root_restore(xn_t162);
                        }
                        {
                    xn_root_restore(xn_t152);
                        }
                        {
                    xn_root_restore(xn_t110);
                        }

                    return xn_ret;

                }
            #line 166 "tests/b3/fixtures/bundle_text/app.x"
            e = ((e * 10) + d);
            #line 167 "tests/b3/fixtures/bundle_text/app.x"
            i = (i + 1);
                {
                xn_root_restore(xn_t162);
                }

            xn_gc_safepoint();
            }
        #line 169 "tests/b3/fixtures/bundle_text/app.x"
        int64_t k = 0;
        #line 170 "tests/b3/fixtures/bundle_text/app.x"
            while (((k < e))) {
            size_t xn_t166 = xn_root_mark();
            #line 171 "tests/b3/fixtures/bundle_text/app.x"
                if ((eneg)) {
                    size_t xn_t167 = xn_root_mark();
                    #line 171 "tests/b3/fixtures/bundle_text/app.x"
                    v = xn_div_i64((int64_t)(v), (int64_t)(10.0));
                        {
                        xn_root_restore(xn_t167);
                        }

                } else {
                    size_t xn_t168 = xn_root_mark();
                    #line 171 "tests/b3/fixtures/bundle_text/app.x"
                    v = (v * 10.0);
                        {
                        xn_root_restore(xn_t168);
                        }

                }
            #line 172 "tests/b3/fixtures/bundle_text/app.x"
            k = (k + 1);
                {
                xn_root_restore(xn_t166);
                }

            xn_gc_safepoint();
            }
            {
            xn_root_restore(xn_t152);
            }

    }
#line 175 "tests/b3/fixtures/bundle_text/app.x"
    if (((i != n))) {
        size_t xn_t169 = xn_root_mark();
        #line 175 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t170 = rt_string_from_c("parseFloat: 未消费完整字符串");
xn_root_add(xn_t170);
        xn_root_add(xn_t170);
        xn_root_add(xn_t170);
        xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t170)};
            {
        xn_root_restore(xn_t169);
            }
            {
        xn_root_restore(xn_t110);
            }

        return xn_ret;

    }
#line 176 "tests/b3/fixtures/bundle_text/app.x"
    if ((neg)) {
        size_t xn_t171 = xn_root_mark();
        #line 176 "tests/b3/fixtures/bundle_text/app.x"
        xn_ret = (xn_Result_Double_Error){1, (0.0 - v), 0};
            {
        xn_root_restore(xn_t171);
            }
            {
        xn_root_restore(xn_t110);
            }

        return xn_ret;

    }
#line 177 "tests/b3/fixtures/bundle_text/app.x"
xn_ret = (xn_Result_Double_Error){1, v, 0};
    {
xn_root_restore(xn_t110);
    }

return xn_ret;
}

xn_Result_List_Error xn_utf8ToUtf16(xrt_bytes_obj * xn_p_b) {
    xn_Result_List_Error xn_ret;
size_t xn_t172 = xn_root_mark();
xn_root_add(xn_p_b);
#line 184 "tests/b3/fixtures/bundle_text/app.x"
xn_arr_u16 *xn_t173 = xn_arr_u16_new(0);
xn_root_add(xn_t173);
xn_arr_u16 * res = xn_t173;
xn_root_add(res);
xn_root_add(res);
xn_gc_safepoint();
#line 185 "tests/b3/fixtures/bundle_text/app.x"
int64_t i = 0;
#line 186 "tests/b3/fixtures/bundle_text/app.x"
    while (((i < ((int64_t)xrt_bytes_len(xn_p_b))))) {
    size_t xn_t174 = xn_root_mark();
    #line 187 "tests/b3/fixtures/bundle_text/app.x"
    int64_t c = ((int64_t)xrt_bytes_get(xn_p_b, (size_t)(i)));
    #line 188 "tests/b3/fixtures/bundle_text/app.x"
        if (((c < 128))) {
            size_t xn_t175 = xn_root_mark();
            #line 189 "tests/b3/fixtures/bundle_text/app.x"
            xn_arr_u16_push(res, c);
            #line 190 "tests/b3/fixtures/bundle_text/app.x"
            i = (i + 1);
                {
                xn_root_restore(xn_t175);
                }

        } else {
                if ((((c >= 192)) && ((c < 224)))) {
                    size_t xn_t177 = xn_root_mark();
                    #line 192 "tests/b3/fixtures/bundle_text/app.x"
                        if ((((i + 1) >= ((int64_t)xrt_bytes_len(xn_p_b))))) {
                            size_t xn_t178 = xn_root_mark();
                            #line 192 "tests/b3/fixtures/bundle_text/app.x"
                            rt_string *xn_t179 = rt_string_from_c("utf8ToUtf16: 截断的 2 字节序列");
xn_root_add(xn_t179);
    xn_root_add(xn_t179);
            xn_root_add(xn_t179);
                    xn_root_add(xn_t179);
                            xn_root_add(xn_t179);
                            xn_root_add(xn_t179);
                            xn_ret = (xn_Result_List_Error){0, NULL, xn_textErr(xn_t179)};
                                {
                            xn_root_restore(xn_t178);
                                }
                                {
                            xn_root_restore(xn_t177);
                                }
                                {
                            xn_root_restore(xn_t174);
                                }
                                {
                            xn_root_restore(xn_t172);
                                }

                            return xn_ret;

                        }
                    #line 193 "tests/b3/fixtures/bundle_text/app.x"
                    int64_t c2 = ((int64_t)xrt_bytes_get(xn_p_b, (size_t)((i + 1))));
                    #line 194 "tests/b3/fixtures/bundle_text/app.x"
                        if ((((c2 & 192) != 128))) {
                            size_t xn_t180 = xn_root_mark();
                            #line 194 "tests/b3/fixtures/bundle_text/app.x"
                            rt_string *xn_t181 = rt_string_from_c("utf8ToUtf16: 非法续字节");
xn_root_add(xn_t181);
    xn_root_add(xn_t181);
            xn_root_add(xn_t181);
                    xn_root_add(xn_t181);
                            xn_root_add(xn_t181);
                            xn_root_add(xn_t181);
                            xn_ret = (xn_Result_List_Error){0, NULL, xn_textErr(xn_t181)};
                                {
                            xn_root_restore(xn_t180);
                                }
                                {
                            xn_root_restore(xn_t177);
                                }
                                {
                            xn_root_restore(xn_t174);
                                }
                                {
                            xn_root_restore(xn_t172);
                                }

                            return xn_ret;

                        }
                    #line 195 "tests/b3/fixtures/bundle_text/app.x"
                    xn_arr_u16_push(res, (((c & 31) << 6) | (c2 & 63)));
                    #line 196 "tests/b3/fixtures/bundle_text/app.x"
                    i = (i + 2);
                        {
                        xn_root_restore(xn_t177);
                        }

                } else {
                        if ((((c >= 224)) && ((c < 240)))) {
                            size_t xn_t183 = xn_root_mark();
                            #line 198 "tests/b3/fixtures/bundle_text/app.x"
                                if ((((i + 2) >= ((int64_t)xrt_bytes_len(xn_p_b))))) {
                                    size_t xn_t184 = xn_root_mark();
                                    #line 198 "tests/b3/fixtures/bundle_text/app.x"
                                    rt_string *xn_t185 = rt_string_from_c("utf8ToUtf16: 截断的 3 字节序列");
xn_root_add(xn_t185);
    xn_root_add(xn_t185);
            xn_root_add(xn_t185);
                    xn_root_add(xn_t185);
                            xn_root_add(xn_t185);
                                    xn_root_add(xn_t185);
                                    xn_root_add(xn_t185);
                                    xn_ret = (xn_Result_List_Error){0, NULL, xn_textErr(xn_t185)};
                                        {
                                    xn_root_restore(xn_t184);
                                        }
                                        {
                                    xn_root_restore(xn_t183);
                                        }
                                        {
                                    xn_root_restore(xn_t174);
                                        }
                                        {
                                    xn_root_restore(xn_t172);
                                        }

                                    return xn_ret;

                                }
                            #line 199 "tests/b3/fixtures/bundle_text/app.x"
                            int64_t c2 = ((int64_t)xrt_bytes_get(xn_p_b, (size_t)((i + 1))));
                            #line 200 "tests/b3/fixtures/bundle_text/app.x"
                            int64_t c3 = ((int64_t)xrt_bytes_get(xn_p_b, (size_t)((i + 2))));
                            #line 201 "tests/b3/fixtures/bundle_text/app.x"
                                if (((((c2 & 192) != 128)) || (((c3 & 192) != 128)))) {
                                    size_t xn_t186 = xn_root_mark();
                                    #line 201 "tests/b3/fixtures/bundle_text/app.x"
                                    rt_string *xn_t187 = rt_string_from_c("utf8ToUtf16: 非法续字节");
xn_root_add(xn_t187);
    xn_root_add(xn_t187);
            xn_root_add(xn_t187);
                    xn_root_add(xn_t187);
                            xn_root_add(xn_t187);
                                    xn_root_add(xn_t187);
                                    xn_root_add(xn_t187);
                                    xn_ret = (xn_Result_List_Error){0, NULL, xn_textErr(xn_t187)};
                                        {
                                    xn_root_restore(xn_t186);
                                        }
                                        {
                                    xn_root_restore(xn_t183);
                                        }
                                        {
                                    xn_root_restore(xn_t174);
                                        }
                                        {
                                    xn_root_restore(xn_t172);
                                        }

                                    return xn_ret;

                                }
                            #line 202 "tests/b3/fixtures/bundle_text/app.x"
                            xn_arr_u16_push(res, ((((c & 15) << 12) | ((c2 & 63) << 6)) | (c3 & 63)));
                            #line 203 "tests/b3/fixtures/bundle_text/app.x"
                            i = (i + 3);
                                {
                                xn_root_restore(xn_t183);
                                }

                        } else {
                                if ((((c >= 240)) && ((c < 248)))) {
                                    size_t xn_t189 = xn_root_mark();
                                    #line 205 "tests/b3/fixtures/bundle_text/app.x"
                                        if ((((i + 3) >= ((int64_t)xrt_bytes_len(xn_p_b))))) {
                                            size_t xn_t190 = xn_root_mark();
                                            #line 205 "tests/b3/fixtures/bundle_text/app.x"
                                            rt_string *xn_t191 = rt_string_from_c("utf8ToUtf16: 截断的 4 字节序列");
xn_root_add(xn_t191);
    xn_root_add(xn_t191);
            xn_root_add(xn_t191);
                    xn_root_add(xn_t191);
                            xn_root_add(xn_t191);
                                    xn_root_add(xn_t191);
                                            xn_root_add(xn_t191);
                                            xn_root_add(xn_t191);
                                            xn_ret = (xn_Result_List_Error){0, NULL, xn_textErr(xn_t191)};
                                                {
                                            xn_root_restore(xn_t190);
                                                }
                                                {
                                            xn_root_restore(xn_t189);
                                                }
                                                {
                                            xn_root_restore(xn_t174);
                                                }
                                                {
                                            xn_root_restore(xn_t172);
                                                }

                                            return xn_ret;

                                        }
                                    #line 206 "tests/b3/fixtures/bundle_text/app.x"
                                    int64_t c2 = ((int64_t)xrt_bytes_get(xn_p_b, (size_t)((i + 1))));
                                    #line 207 "tests/b3/fixtures/bundle_text/app.x"
                                    int64_t c3 = ((int64_t)xrt_bytes_get(xn_p_b, (size_t)((i + 2))));
                                    #line 208 "tests/b3/fixtures/bundle_text/app.x"
                                    int64_t c4 = ((int64_t)xrt_bytes_get(xn_p_b, (size_t)((i + 3))));
                                    #line 209 "tests/b3/fixtures/bundle_text/app.x"
                                        if ((((((c2 & 192) != 128)) || (((c3 & 192) != 128))) || (((c4 & 192) != 128)))) {
                                            size_t xn_t192 = xn_root_mark();
                                            #line 210 "tests/b3/fixtures/bundle_text/app.x"
                                            rt_string *xn_t193 = rt_string_from_c("utf8ToUtf16: 非法续字节");
xn_root_add(xn_t193);
    xn_root_add(xn_t193);
            xn_root_add(xn_t193);
                    xn_root_add(xn_t193);
                            xn_root_add(xn_t193);
                                    xn_root_add(xn_t193);
                                            xn_root_add(xn_t193);
                                            xn_root_add(xn_t193);
                                            xn_ret = (xn_Result_List_Error){0, NULL, xn_textErr(xn_t193)};
                                                {
                                            xn_root_restore(xn_t192);
                                                }
                                                {
                                            xn_root_restore(xn_t189);
                                                }
                                                {
                                            xn_root_restore(xn_t174);
                                                }
                                                {
                                            xn_root_restore(xn_t172);
                                                }

                                            return xn_ret;

                                        }
                                    #line 212 "tests/b3/fixtures/bundle_text/app.x"
                                    int64_t cp = (((((c & 7) << 18) | ((c2 & 63) << 12)) | ((c3 & 63) << 6)) | (c4 & 63));
                                    #line 213 "tests/b3/fixtures/bundle_text/app.x"
                                    cp = (cp - 65536);
                                    #line 214 "tests/b3/fixtures/bundle_text/app.x"
                                    xn_arr_u16_push(res, (55296 + (cp >> 10)));
                                    #line 215 "tests/b3/fixtures/bundle_text/app.x"
                                    xn_arr_u16_push(res, (56320 + (cp & 1023)));
                                    #line 216 "tests/b3/fixtures/bundle_text/app.x"
                                    i = (i + 4);
                                        {
                                        xn_root_restore(xn_t189);
                                        }

                                } else {
                                    size_t xn_t194 = xn_root_mark();
                                    #line 218 "tests/b3/fixtures/bundle_text/app.x"
                                    rt_string *xn_t195 = rt_string_from_c("utf8ToUtf16: 不支持的 UTF-8 序列");
xn_root_add(xn_t195);
    xn_root_add(xn_t195);
            xn_root_add(xn_t195);
                    xn_root_add(xn_t195);
                            xn_root_add(xn_t195);
                                    xn_root_add(xn_t195);
                                    xn_root_add(xn_t195);
                                    xn_ret = (xn_Result_List_Error){0, NULL, xn_textErr(xn_t195)};
                                        {
                                    xn_root_restore(xn_t194);
                                        }
                                        {
                                    xn_root_restore(xn_t174);
                                        }
                                        {
                                    xn_root_restore(xn_t172);
                                        }

                                    return xn_ret;

                                }
                        }
                }
        }
        {
        xn_root_restore(xn_t174);
        }

    xn_gc_safepoint();
    }
#line 221 "tests/b3/fixtures/bundle_text/app.x"
xn_ret = (xn_Result_List_Error){1, res, 0};
    {
xn_root_restore(xn_t172);
    }

return xn_ret;
}

xn_Result_Bytes_Error xn_utf16ToUtf8(xn_arr_u16 * xn_p_xs) {
    xn_Result_Bytes_Error xn_ret;
size_t xn_t196 = xn_root_mark();
xn_root_add(xn_p_xs);
#line 226 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t197 = rt_string_from_c("");
xn_root_add(xn_t197);
xrt_bytes_obj *xn_t198 = xrt_bytes_from_string(xn_t197->bytes, xn_t197->len);
xn_root_add(xn_t198);
rt_release(xn_t197);
xrt_bytes_obj *res = xn_t198;
xn_root_add(res);
xn_root_add(res);
xn_gc_safepoint();
#line 227 "tests/b3/fixtures/bundle_text/app.x"
int64_t i = 0;
#line 228 "tests/b3/fixtures/bundle_text/app.x"
    while (((i < ((int64_t)xn_p_xs->len)))) {
    size_t xn_t199 = xn_root_mark();
    #line 229 "tests/b3/fixtures/bundle_text/app.x"
    uint16_t u = xn_arr_u16_get(xn_p_xs, i);
    #line 230 "tests/b3/fixtures/bundle_text/app.x"
        if (((u < 128))) {
            size_t xn_t200 = xn_root_mark();
            #line 231 "tests/b3/fixtures/bundle_text/app.x"
            xrt_bytes_push(res, (int32_t)(((int64_t)(u))));
            #line 232 "tests/b3/fixtures/bundle_text/app.x"
            i = (i + 1);
                {
                xn_root_restore(xn_t200);
                }

        } else {
                if (((u < 2048))) {
                    size_t xn_t202 = xn_root_mark();
                    #line 234 "tests/b3/fixtures/bundle_text/app.x"
                    xrt_bytes_push(res, (int32_t)((192 | (u >> 6))));
                    #line 235 "tests/b3/fixtures/bundle_text/app.x"
                    xrt_bytes_push(res, (int32_t)((128 | (u & 63))));
                    #line 236 "tests/b3/fixtures/bundle_text/app.x"
                    i = (i + 1);
                        {
                        xn_root_restore(xn_t202);
                        }

                } else {
                        if ((((u >= 55296)) && ((u <= 56319)))) {
                            size_t xn_t204 = xn_root_mark();
                            #line 238 "tests/b3/fixtures/bundle_text/app.x"
                                if ((((i + 1) >= ((int64_t)xn_p_xs->len)))) {
                                    size_t xn_t205 = xn_root_mark();
                                    #line 238 "tests/b3/fixtures/bundle_text/app.x"
                                    rt_string *xn_t206 = rt_string_from_c("utf16ToUtf8: 孤立的高代理");
xn_root_add(xn_t206);
    xn_root_add(xn_t206);
            xn_root_add(xn_t206);
                    xn_root_add(xn_t206);
                            xn_root_add(xn_t206);
                                    xn_root_add(xn_t206);
                                    xn_root_add(xn_t206);
                                    xn_ret = (xn_Result_Bytes_Error){0, NULL, xn_textErr(xn_t206)};
                                        {
                                    xn_root_restore(xn_t205);
                                        }
                                        {
                                    xn_root_restore(xn_t204);
                                        }
                                        {
                                    xn_root_restore(xn_t199);
                                        }
                                        {
                                    rt_release(res);
                                        }
                                        {
                                    xn_root_restore(xn_t196);
                                        }

                                    return xn_ret;

                                }
                            #line 239 "tests/b3/fixtures/bundle_text/app.x"
                            uint16_t u2 = xn_arr_u16_get(xn_p_xs, (i + 1));
                            #line 240 "tests/b3/fixtures/bundle_text/app.x"
                                if ((((u2 < 56320)) || ((u2 > 57343)))) {
                                    size_t xn_t207 = xn_root_mark();
                                    #line 240 "tests/b3/fixtures/bundle_text/app.x"
                                    rt_string *xn_t208 = rt_string_from_c("utf16ToUtf8: 高代理后缺低代理");
xn_root_add(xn_t208);
    xn_root_add(xn_t208);
            xn_root_add(xn_t208);
                    xn_root_add(xn_t208);
                            xn_root_add(xn_t208);
                                    xn_root_add(xn_t208);
                                    xn_root_add(xn_t208);
                                    xn_ret = (xn_Result_Bytes_Error){0, NULL, xn_textErr(xn_t208)};
                                        {
                                    xn_root_restore(xn_t207);
                                        }
                                        {
                                    xn_root_restore(xn_t204);
                                        }
                                        {
                                    xn_root_restore(xn_t199);
                                        }
                                        {
                                    rt_release(res);
                                        }
                                        {
                                    xn_root_restore(xn_t196);
                                        }

                                    return xn_ret;

                                }
                            #line 241 "tests/b3/fixtures/bundle_text/app.x"
                            int64_t cp = ((65536 + ((((int64_t)(u)) - 55296) << 10)) + (((int64_t)(u2)) - 56320));
                            #line 242 "tests/b3/fixtures/bundle_text/app.x"
                            xrt_bytes_push(res, (int32_t)((240 | (cp >> 18))));
                            #line 243 "tests/b3/fixtures/bundle_text/app.x"
                            xrt_bytes_push(res, (int32_t)((128 | ((cp >> 12) & 63))));
                            #line 244 "tests/b3/fixtures/bundle_text/app.x"
                            xrt_bytes_push(res, (int32_t)((128 | ((cp >> 6) & 63))));
                            #line 245 "tests/b3/fixtures/bundle_text/app.x"
                            xrt_bytes_push(res, (int32_t)((128 | (cp & 63))));
                            #line 246 "tests/b3/fixtures/bundle_text/app.x"
                            i = (i + 2);
                                {
                                xn_root_restore(xn_t204);
                                }

                        } else {
                                if ((((u >= 56320)) && ((u <= 57343)))) {
                                    size_t xn_t210 = xn_root_mark();
                                    #line 248 "tests/b3/fixtures/bundle_text/app.x"
                                    rt_string *xn_t211 = rt_string_from_c("utf16ToUtf8: 孤立的低代理");
xn_root_add(xn_t211);
    xn_root_add(xn_t211);
            xn_root_add(xn_t211);
                    xn_root_add(xn_t211);
                            xn_root_add(xn_t211);
                                    xn_root_add(xn_t211);
                                    xn_root_add(xn_t211);
                                    xn_ret = (xn_Result_Bytes_Error){0, NULL, xn_textErr(xn_t211)};
                                        {
                                    xn_root_restore(xn_t210);
                                        }
                                        {
                                    xn_root_restore(xn_t199);
                                        }
                                        {
                                    rt_release(res);
                                        }
                                        {
                                    xn_root_restore(xn_t196);
                                        }

                                    return xn_ret;

                                } else {
                                    size_t xn_t212 = xn_root_mark();
                                    #line 250 "tests/b3/fixtures/bundle_text/app.x"
                                    xrt_bytes_push(res, (int32_t)((224 | (u >> 12))));
                                    #line 251 "tests/b3/fixtures/bundle_text/app.x"
                                    xrt_bytes_push(res, (int32_t)((128 | ((u >> 6) & 63))));
                                    #line 252 "tests/b3/fixtures/bundle_text/app.x"
                                    xrt_bytes_push(res, (int32_t)((128 | (u & 63))));
                                    #line 253 "tests/b3/fixtures/bundle_text/app.x"
                                    i = (i + 1);
                                        {
                                        xn_root_restore(xn_t212);
                                        }

                                }
                        }
                }
        }
        {
        xn_root_restore(xn_t199);
        }

    xn_gc_safepoint();
    }
#line 256 "tests/b3/fixtures/bundle_text/app.x"
xn_ret = (xn_Result_Bytes_Error){1, res, 0};
    {
rt_release(res);
    }
    {
xn_root_restore(xn_t196);
    }

return xn_ret;
}

int xn_regexAtomMatch(rt_string * xn_p_atom, rt_string * xn_p_ch) {
size_t xn_t213 = xn_root_mark();
xn_root_add(xn_p_atom);
xn_root_add(xn_p_ch);
#line 301 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t214 = rt_retain(xn_p_atom);
xn_root_add(xn_t214);
rt_string *xn_t215 = rt_string_from_c(".");
xn_root_add(xn_t215);
    if ((xn_str_eq(xn_t214, xn_t215))) {
        size_t xn_t216 = xn_root_mark();
        #line 301 "tests/b3/fixtures/bundle_text/app.x"
        int xn_t217 = 1;
            {
        xn_root_restore(xn_t216);
            }
            {
        xn_root_restore(xn_t213);
            }

        return xn_t217;

    }
#line 302 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t218 = rt_retain(xn_p_atom);
xn_root_add(xn_t218);
xn_root_add(xn_t218);
rt_string *xn_t219 = rt_retain(xn_p_ch);
xn_root_add(xn_t219);
xn_root_add(xn_t219);
int xn_t220 = xn_str_eq(xn_t218, xn_t219);
    {
xn_root_restore(xn_t213);
    }

return xn_t220;
}

int xn_regexMatchAt(rt_string * xn_p_pattern, int64_t xn_p_pi, rt_string * xn_p_text, int64_t xn_p_ti) {
size_t xn_t221 = xn_root_mark();
xn_root_add(xn_p_pattern);
xn_root_add(xn_p_text);
#line 306 "tests/b3/fixtures/bundle_text/app.x"
int64_t plen = xn_str_length(xn_p_pattern);
#line 307 "tests/b3/fixtures/bundle_text/app.x"
    if (((xn_p_pi >= plen))) {
        size_t xn_t222 = xn_root_mark();
        #line 307 "tests/b3/fixtures/bundle_text/app.x"
        int xn_t223 = 1;
            {
        xn_root_restore(xn_t222);
            }
            {
        xn_root_restore(xn_t221);
            }

        return xn_t223;

    }
#line 308 "tests/b3/fixtures/bundle_text/app.x"
rt_string *c = xn_str_substr(xn_p_pattern, xn_p_pi, 1);
xn_root_add(c);
xn_root_add(c);
xn_gc_safepoint();
#line 309 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t225 = rt_retain(c);
xn_root_add(xn_t225);
rt_string *xn_t226 = rt_string_from_c("$");
xn_root_add(xn_t226);
    if (((xn_str_eq(xn_t225, xn_t226)) && ((xn_p_pi == (plen - 1))))) {
        size_t xn_t227 = xn_root_mark();
        #line 309 "tests/b3/fixtures/bundle_text/app.x"
        int xn_t228 = (xn_p_ti == xn_str_length(xn_p_text));
            {
        xn_root_restore(xn_t227);
            }
            {
        rt_release(c);
            }
            {
        xn_root_restore(xn_t221);
            }

        return xn_t228;

    }
#line 310 "tests/b3/fixtures/bundle_text/app.x"
rt_string *next = rt_string_from_c("");
xn_root_add(next);
xn_root_add(next);
xn_gc_safepoint();
#line 311 "tests/b3/fixtures/bundle_text/app.x"
    if ((((xn_p_pi + 1) < plen))) {
        size_t xn_t230 = xn_root_mark();
        #line 311 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t231 = xn_str_substr(xn_p_pattern, (xn_p_pi + 1), 1);
xn_root_add(xn_t231);
        xn_root_add(xn_t231);
        xn_root_release(next);
        rt_release(next);
        next = xn_t231;
        xn_root_hold(next);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t230);
            }

    }
#line 312 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t232 = rt_retain(next);
xn_root_add(xn_t232);
rt_string *xn_t233 = rt_string_from_c("*");
xn_root_add(xn_t233);
rt_string *xn_t234 = rt_retain(next);
xn_root_add(xn_t234);
rt_string *xn_t235 = rt_string_from_c("+");
xn_root_add(xn_t235);
rt_string *xn_t236 = rt_retain(next);
xn_root_add(xn_t236);
rt_string *xn_t237 = rt_string_from_c("?");
xn_root_add(xn_t237);
int quant = ((xn_str_eq(xn_t232, xn_t233) || xn_str_eq(xn_t234, xn_t235)) || xn_str_eq(xn_t236, xn_t237));
#line 313 "tests/b3/fixtures/bundle_text/app.x"
    if ((quant)) {
        size_t xn_t238 = xn_root_mark();
        #line 314 "tests/b3/fixtures/bundle_text/app.x"
        int64_t nextp = (xn_p_pi + 2);
        #line 315 "tests/b3/fixtures/bundle_text/app.x"
        int64_t k = xn_p_ti;
        #line 316 "tests/b3/fixtures/bundle_text/app.x"
        int64_t count = 0;
        #line 317 "tests/b3/fixtures/bundle_text/app.x"
            while (1) {
                rt_string *xn_t239 = rt_retain(c);
xn_root_add(xn_t239);
        xn_root_add(xn_t239);
                rt_string *xn_t240 = xn_str_substr(xn_p_text, k, 1);
xn_root_add(xn_t240);
        xn_root_add(xn_t240);
                if (!((((k < xn_str_length(xn_p_text))) && (xn_regexAtomMatch(xn_t239, xn_t240))))) { break; }
                size_t xn_t241 = xn_root_mark();
                #line 318 "tests/b3/fixtures/bundle_text/app.x"
                count = (count + 1);
                #line 319 "tests/b3/fixtures/bundle_text/app.x"
                k = (k + 1);
                    {
                    xn_root_restore(xn_t241);
                    }

                xn_gc_safepoint();
            }
        #line 321 "tests/b3/fixtures/bundle_text/app.x"
        int64_t min = 1;
        #line 322 "tests/b3/fixtures/bundle_text/app.x"
        int64_t max = count;
        #line 323 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t242 = rt_retain(next);
xn_root_add(xn_t242);
        xn_root_add(xn_t242);
        rt_string *xn_t243 = rt_string_from_c("*");
xn_root_add(xn_t243);
        xn_root_add(xn_t243);
            if ((xn_str_eq(xn_t242, xn_t243))) {
                size_t xn_t244 = xn_root_mark();
                #line 323 "tests/b3/fixtures/bundle_text/app.x"
                min = 0;
                    {
                    xn_root_restore(xn_t244);
                    }

            }
        #line 324 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t245 = rt_retain(next);
xn_root_add(xn_t245);
        xn_root_add(xn_t245);
        rt_string *xn_t246 = rt_string_from_c("?");
xn_root_add(xn_t246);
        xn_root_add(xn_t246);
            if ((xn_str_eq(xn_t245, xn_t246))) {
                size_t xn_t247 = xn_root_mark();
                #line 324 "tests/b3/fixtures/bundle_text/app.x"
                min = 0;
                #line 324 "tests/b3/fixtures/bundle_text/app.x"
                    if (((max > 1))) {
                        size_t xn_t248 = xn_root_mark();
                        #line 324 "tests/b3/fixtures/bundle_text/app.x"
                        max = 1;
                            {
                            xn_root_restore(xn_t248);
                            }

                    }
                    {
                    xn_root_restore(xn_t247);
                    }

            }
        #line 325 "tests/b3/fixtures/bundle_text/app.x"
        int64_t use = max;
        #line 326 "tests/b3/fixtures/bundle_text/app.x"
            while (((use >= min))) {
            size_t xn_t249 = xn_root_mark();
            #line 327 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t250 = rt_retain(xn_p_pattern);
xn_root_add(xn_t250);
        xn_root_add(xn_t250);
            xn_root_add(xn_t250);
            rt_string *xn_t251 = rt_retain(xn_p_text);
xn_root_add(xn_t251);
        xn_root_add(xn_t251);
            xn_root_add(xn_t251);
                if ((xn_regexMatchAt(xn_t250, nextp, xn_t251, (xn_p_ti + use)))) {
                    size_t xn_t252 = xn_root_mark();
                    #line 327 "tests/b3/fixtures/bundle_text/app.x"
                    int xn_t253 = 1;
                        {
                    xn_root_restore(xn_t252);
                        }
                        {
                    xn_root_restore(xn_t249);
                        }
                        {
                    xn_root_restore(xn_t238);
                        }
                        {
                    rt_release(next);
                        }
                        {
                    rt_release(c);
                        }
                        {
                    xn_root_restore(xn_t221);
                        }

                    return xn_t253;

                }
            #line 328 "tests/b3/fixtures/bundle_text/app.x"
            use = (use - 1);
                {
                xn_root_restore(xn_t249);
                }

            xn_gc_safepoint();
            }
        #line 330 "tests/b3/fixtures/bundle_text/app.x"
        int xn_t254 = 0;
            {
        xn_root_restore(xn_t238);
            }
            {
        rt_release(next);
            }
            {
        rt_release(c);
            }
            {
        xn_root_restore(xn_t221);
            }

        return xn_t254;

    }
#line 332 "tests/b3/fixtures/bundle_text/app.x"
    if (((xn_p_ti >= xn_str_length(xn_p_text)))) {
        size_t xn_t255 = xn_root_mark();
        #line 332 "tests/b3/fixtures/bundle_text/app.x"
        int xn_t256 = 0;
            {
        xn_root_restore(xn_t255);
            }
            {
        rt_release(next);
            }
            {
        rt_release(c);
            }
            {
        xn_root_restore(xn_t221);
            }

        return xn_t256;

    }
#line 333 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t257 = rt_retain(c);
xn_root_add(xn_t257);
rt_string *xn_t258 = xn_str_substr(xn_p_text, xn_p_ti, 1);
xn_root_add(xn_t258);
    if ((xn_regexAtomMatch(xn_t257, xn_t258))) {
        size_t xn_t259 = xn_root_mark();
        #line 333 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t260 = rt_retain(xn_p_pattern);
xn_root_add(xn_t260);
        xn_root_add(xn_t260);
        xn_root_add(xn_t260);
        rt_string *xn_t261 = rt_retain(xn_p_text);
xn_root_add(xn_t261);
        xn_root_add(xn_t261);
        xn_root_add(xn_t261);
        int xn_t262 = xn_regexMatchAt(xn_t260, (xn_p_pi + 1), xn_t261, (xn_p_ti + 1));
            {
        xn_root_restore(xn_t259);
            }
            {
        rt_release(next);
            }
            {
        rt_release(c);
            }
            {
        xn_root_restore(xn_t221);
            }

        return xn_t262;

    }
#line 334 "tests/b3/fixtures/bundle_text/app.x"
int xn_t263 = 0;
    {
rt_release(next);
    }
    {
rt_release(c);
    }
    {
xn_root_restore(xn_t221);
    }

return xn_t263;
xn_root_release(next);
}

rt_string * xn_repeatText(rt_string * xn_p_unit, int64_t xn_p_times) {
size_t xn_t264 = xn_root_mark();
xn_root_add(xn_p_unit);
#line 340 "tests/b3/fixtures/bundle_text/app.x"
    if (((xn_p_times <= 0))) {
        size_t xn_t265 = xn_root_mark();
        #line 340 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t266 = rt_string_from_c("");
xn_root_add(xn_t266);
        xn_root_add(xn_t266);
        xn_root_add(xn_t266);
            {
        xn_root_restore(xn_t265);
            }
            {
        xn_root_restore(xn_t264);
            }

        return xn_t266;

    }
#line 341 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t267 = rt_retain(xn_p_unit);
xn_root_add(xn_t267);
xn_root_add(xn_t267);
rt_string *xn_t268 = rt_retain(xn_p_unit);
xn_root_add(xn_t268);
xn_root_add(xn_t268);
rt_string *xn_t269 = xn_repeatText(xn_t268, (xn_p_times - 1));
xn_root_add(xn_t269);
xn_root_add(xn_t269);
rt_string *xn_t270 = xn_concat(xn_t267, xn_t269);
xn_root_add(xn_t270);
xn_root_add(xn_t270);
    {
xn_root_restore(xn_t264);
    }

return xn_t270;
}

rt_string * xn_repeatJoined(rt_string * xn_p_unit, rt_string * xn_p_sep, int64_t xn_p_times) {
size_t xn_t271 = xn_root_mark();
xn_root_add(xn_p_unit);
xn_root_add(xn_p_sep);
#line 345 "tests/b3/fixtures/bundle_text/app.x"
    if (((xn_p_times <= 0))) {
        size_t xn_t272 = xn_root_mark();
        #line 345 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t273 = rt_string_from_c("");
xn_root_add(xn_t273);
        xn_root_add(xn_t273);
        xn_root_add(xn_t273);
            {
        xn_root_restore(xn_t272);
            }
            {
        xn_root_restore(xn_t271);
            }

        return xn_t273;

    }
#line 346 "tests/b3/fixtures/bundle_text/app.x"
    if (((xn_p_times == 1))) {
        size_t xn_t274 = xn_root_mark();
        #line 346 "tests/b3/fixtures/bundle_text/app.x"
        rt_retain(xn_p_unit);
            {
        xn_root_restore(xn_t274);
            }
            {
        xn_root_restore(xn_t271);
            }

        return xn_p_unit;

    }
#line 347 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t275 = rt_retain(xn_p_unit);
xn_root_add(xn_t275);
xn_root_add(xn_t275);
rt_string *xn_t276 = rt_retain(xn_p_sep);
xn_root_add(xn_t276);
xn_root_add(xn_t276);
rt_string *xn_t277 = xn_concat(xn_t275, xn_t276);
xn_root_add(xn_t277);
xn_root_add(xn_t277);
rt_string *xn_t278 = rt_retain(xn_p_unit);
xn_root_add(xn_t278);
xn_root_add(xn_t278);
rt_string *xn_t279 = rt_retain(xn_p_sep);
xn_root_add(xn_t279);
xn_root_add(xn_t279);
rt_string *xn_t280 = xn_repeatJoined(xn_t278, xn_t279, (xn_p_times - 1));
xn_root_add(xn_t280);
xn_root_add(xn_t280);
rt_string *xn_t281 = xn_concat(xn_t277, xn_t280);
xn_root_add(xn_t281);
xn_root_add(xn_t281);
    {
xn_root_restore(xn_t271);
    }

return xn_t281;
}

int xn_isPositive(int64_t xn_p_n) {
size_t xn_t282 = xn_root_mark();
#line 351 "tests/b3/fixtures/bundle_text/app.x"
int xn_t283 = (xn_p_n > 0);
    {
xn_root_restore(xn_t282);
    }

return xn_t283;
}

int64_t xn_main() {
size_t xn_t284 = xn_root_mark();
#line 4 "tests/b3/fixtures/bundle_text/app.x"
int64_t xn_t285 = 0;
    {
xn_root_restore(xn_t284);
    }

return xn_t285;
}

int main(void) {
    xrt_runtime_init();
    xn_init_vtables();
    xn_init_enums();
    int64_t xn_r = xn_main();
    rt_gc_collect();
    rt_quarantine_flush();
    return (int)xn_r;
}
