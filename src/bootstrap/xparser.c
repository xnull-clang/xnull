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

/* 绑定层支撑代码（由 .xfb 注册表生成；只包含 xrt.h，S7 §6.1 / INV-FFI-7） */
/* S7 §6.2：绑定层可访问弱表；应用层包含 xrt.h 时不定义此宏。 */
#define XRT_BINDINGS_LAYER 1
#include "xrt.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* 包装 ABI：返回 0 成功；非 0 为原生错误码（未知码→Internal，S7 §7.2） */
/* S6-09 net Async 运行时原语（E5 rt_std_net.c） */
void *xdkc_socket_connect_async(xrt_context *ctx, const char *host, size_t hlen, int32_t port, int32_t *code);
int64_t xdkc_socket_send_async(xrt_context *ctx, void *sock, const void *buf, size_t n, int32_t *code);
int64_t xdkc_socket_recv_async(xrt_context *ctx, void *sock, void *buf, size_t cap, int32_t *code);
void *xdkc_http_request_async(xrt_context *ctx, const char *method, size_t mlen, const char *host, size_t hlen, int32_t port, const char *path, size_t plen, const void *body, size_t blen, int32_t *code);

#define XN_FFI_CANARY 16

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

static const char *xn_ffi_xdkc_sys_error_kind(int32_t code) {
    switch (code) {
    default: return "Internal";
    }
}

static xrt_error_kind xn_ffi_xdkc_sys_error_kind_id(int32_t code) {
    switch (code) {
    default: return XRT_ERR_INTERNAL;
    }
}

/* 原生符号声明：编组签名的投影。绑定层自行包含原生头时
   定义 XN_FFI_NATIVE_DECLS 关闭本节（S7 §3.2）。 */
#ifndef XN_FFI_NATIVE_DECLS
int32_t xdkc_read_file_text_error();
const char * xdkc_read_file_text(const char *path_bytes, size_t path_len);
#endif

/* 绑定入口 readFileTextError（原生 xdkc_read_file_text_error） */
static int32_t xn_ffi_readFileTextError(int32_t *xn_out) {
    int32_t xn_v = xdkc_read_file_text_error();
    *xn_out = (int32_t)xn_v;
    return 0;
}

/* 绑定入口 readFileTextRaw（原生 xdkc_read_file_text） */
static int32_t xn_ffi_readFileTextRaw(const char *path_bytes, size_t path_len, xrt_string * *xn_out) {
    const char * xn_v = xdkc_read_file_text(path_bytes, path_len);
    *xn_out = (xn_v == NULL) ? NULL : xrt_string_from_c(xn_v);
    return 0;
}


static void xn_fatal_oob(void);
static void xn_fatal_oob(void) {
    fprintf(stderr, "fatal: 容器下标越界\n");
    exit(134);
}

typedef struct xn_Cls_Diag xn_Cls_Diag;
typedef struct xn_Cls_E xn_Cls_E;
typedef struct xn_Cls_Lexer xn_Cls_Lexer;
typedef struct xn_Cls_M xn_Cls_M;
typedef struct xn_Cls_Parser xn_Cls_Parser;
typedef struct xn_Cls_TN xn_Cls_TN;
typedef struct xn_Cls_TP xn_Cls_TP;
typedef struct xn_Cls_Tok xn_Cls_Tok;

typedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *data; } xn_arr_s;

typedef struct { rt_header hdr; size_t len; size_t cap; xn_Cls_Diag * *data; } xn_arr_o_Diag;

typedef struct { rt_header hdr; size_t len; size_t cap; xn_Cls_E * *data; } xn_arr_o_E;

typedef struct { rt_header hdr; size_t len; size_t cap; xn_Cls_TN * *data; } xn_arr_o_TN;

typedef struct { rt_header hdr; size_t len; size_t cap; xn_Cls_Tok * *data; } xn_arr_o_Tok;

typedef struct xn_Cls_Diag xn_Cls_Diag;
typedef struct xn_Cls_E xn_Cls_E;
typedef struct xn_Cls_Lexer xn_Cls_Lexer;
typedef struct xn_Cls_M xn_Cls_M;
typedef struct xn_Cls_Parser xn_Cls_Parser;
typedef struct xn_Cls_TN xn_Cls_TN;
typedef struct xn_Cls_TP xn_Cls_TP;
typedef struct xn_Cls_Tok xn_Cls_Tok;

static xn_Cls_Diag *xn_Cls_Diag_new(void);
static void xn_Cls_Diag_new_init(xn_Cls_Diag *o);
static xn_Cls_E *xn_Cls_E_new(void);
static void xn_Cls_E_new_init(xn_Cls_E *o);
static xn_Cls_Lexer *xn_Cls_Lexer_new(rt_string * xn_p_s);
static void xn_Cls_Lexer_new_init(xn_Cls_Lexer *o, rt_string * xn_p_s);
static xn_Cls_M *xn_Cls_M_new(void);
static void xn_Cls_M_new_init(xn_Cls_M *o);
static xn_Cls_Parser *xn_Cls_Parser_new(xn_arr_o_Tok * xn_p_ts);
static void xn_Cls_Parser_new_init(xn_Cls_Parser *o, xn_arr_o_Tok * xn_p_ts);
static xn_Cls_TN *xn_Cls_TN_new(void);
static void xn_Cls_TN_new_init(xn_Cls_TN *o);
static xn_Cls_TP *xn_Cls_TP_new(rt_string * xn_p_t);
static void xn_Cls_TP_new_init(xn_Cls_TP *o, rt_string * xn_p_t);
static xn_Cls_Tok *xn_Cls_Tok_new(void);
static void xn_Cls_Tok_new_init(xn_Cls_Tok *o);


static void xn_arr_s_scan(void *p, void (*visit)(void *)) {
    xn_arr_s *a = (xn_arr_s *)p;
    if (a->data == NULL) { return; }
    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }
}

static void xn_arr_s_deinit(void *p) {
    xn_arr_s *a = (xn_arr_s *)p;
    if (a->data != NULL) {
        free(a->data);
        a->data = NULL;
    }
    a->len = 0;
    a->cap = 0;
}

static const rt_type RT_TYPE_xn_arr_s = { "List", sizeof(xn_arr_s), xn_arr_s_deinit, xn_arr_s_scan };

static xn_arr_s *xn_arr_s_new(size_t cap) {
    xn_arr_s *a = (xn_arr_s *)xn_gc_new(&RT_TYPE_xn_arr_s);
    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_s) - sizeof(rt_header));
    a->cap = cap ? cap : 4;
    a->data = malloc(sizeof(rt_string *) * a->cap);
    if (a->data == NULL) { abort(); }
    return a;
}

static void xn_arr_s_push(xn_arr_s *a, rt_string * v) {
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    a->data[a->len++] = v;
}

static rt_string * xn_arr_s_get(const xn_arr_s *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    return a->data[i];
}

static void xn_arr_s_set(xn_arr_s *a, int64_t i, rt_string * v) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    a->data[i] = v;
}

static rt_string * xn_arr_s_remove(xn_arr_s *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    rt_string * old = a->data[i];
    for (size_t j = (size_t)i; j + 1 < a->len; j++) {
        a->data[j] = a->data[j + 1];
    }
    a->len--;
    return old;
}

static void xn_arr_s_insert(xn_arr_s *a, int64_t i, rt_string * v) {
    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    for (size_t j = a->len; j > (size_t)i; j--) {
        a->data[j] = a->data[j - 1];
    }
    a->data[i] = v;
    a->len++;
}

static void xn_arr_s_clear(xn_arr_s *a) {
    a->len = 0;
}

static rt_string *xn_arr_s_join(xn_arr_s *a, rt_string *sep) {
    rt_string *res = rt_string_from_c("");
    for (size_t i = 0; i < a->len; i++) {
        if (i > 0) {
            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));
        }
        res = xn_concat(res, rt_string_new(a->data[i]->bytes, a->data[i]->len));
    }
    return res;
}

static void xn_arr_o_Diag_scan(void *p, void (*visit)(void *)) {
    xn_arr_o_Diag *a = (xn_arr_o_Diag *)p;
    if (a->data == NULL) { return; }
    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }
}

static void xn_arr_o_Diag_deinit(void *p) {
    xn_arr_o_Diag *a = (xn_arr_o_Diag *)p;
    if (a->data != NULL) {
        free(a->data);
        a->data = NULL;
    }
    a->len = 0;
    a->cap = 0;
}

static const rt_type RT_TYPE_xn_arr_o_Diag = { "List", sizeof(xn_arr_o_Diag), xn_arr_o_Diag_deinit, xn_arr_o_Diag_scan };

static xn_arr_o_Diag *xn_arr_o_Diag_new(size_t cap) {
    xn_arr_o_Diag *a = (xn_arr_o_Diag *)xn_gc_new(&RT_TYPE_xn_arr_o_Diag);
    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_o_Diag) - sizeof(rt_header));
    a->cap = cap ? cap : 4;
    a->data = malloc(sizeof(xn_Cls_Diag *) * a->cap);
    if (a->data == NULL) { abort(); }
    return a;
}

static void xn_arr_o_Diag_push(xn_arr_o_Diag *a, xn_Cls_Diag * v) {
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(xn_Cls_Diag *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    a->data[a->len++] = v;
}

static xn_Cls_Diag * xn_arr_o_Diag_get(const xn_arr_o_Diag *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    return a->data[i];
}

static void xn_arr_o_Diag_set(xn_arr_o_Diag *a, int64_t i, xn_Cls_Diag * v) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    a->data[i] = v;
}

static xn_Cls_Diag * xn_arr_o_Diag_remove(xn_arr_o_Diag *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    xn_Cls_Diag * old = a->data[i];
    for (size_t j = (size_t)i; j + 1 < a->len; j++) {
        a->data[j] = a->data[j + 1];
    }
    a->len--;
    return old;
}

static void xn_arr_o_Diag_insert(xn_arr_o_Diag *a, int64_t i, xn_Cls_Diag * v) {
    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(xn_Cls_Diag *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    for (size_t j = a->len; j > (size_t)i; j--) {
        a->data[j] = a->data[j - 1];
    }
    a->data[i] = v;
    a->len++;
}

static void xn_arr_o_Diag_clear(xn_arr_o_Diag *a) {
    a->len = 0;
}

static rt_string *xn_arr_o_Diag_join(xn_arr_o_Diag *a, rt_string *sep) {
    rt_string *res = rt_string_from_c("");
    for (size_t i = 0; i < a->len; i++) {
        if (i > 0) {
            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));
        }
        res = xn_concat(res, rt_string_from_c(""));
    }
    return res;
}

static void xn_arr_o_E_scan(void *p, void (*visit)(void *)) {
    xn_arr_o_E *a = (xn_arr_o_E *)p;
    if (a->data == NULL) { return; }
    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }
}

static void xn_arr_o_E_deinit(void *p) {
    xn_arr_o_E *a = (xn_arr_o_E *)p;
    if (a->data != NULL) {
        free(a->data);
        a->data = NULL;
    }
    a->len = 0;
    a->cap = 0;
}

static const rt_type RT_TYPE_xn_arr_o_E = { "List", sizeof(xn_arr_o_E), xn_arr_o_E_deinit, xn_arr_o_E_scan };

static xn_arr_o_E *xn_arr_o_E_new(size_t cap) {
    xn_arr_o_E *a = (xn_arr_o_E *)xn_gc_new(&RT_TYPE_xn_arr_o_E);
    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_o_E) - sizeof(rt_header));
    a->cap = cap ? cap : 4;
    a->data = malloc(sizeof(xn_Cls_E *) * a->cap);
    if (a->data == NULL) { abort(); }
    return a;
}

static void xn_arr_o_E_push(xn_arr_o_E *a, xn_Cls_E * v) {
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(xn_Cls_E *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    a->data[a->len++] = v;
}

static xn_Cls_E * xn_arr_o_E_get(const xn_arr_o_E *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    return a->data[i];
}

static void xn_arr_o_E_set(xn_arr_o_E *a, int64_t i, xn_Cls_E * v) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    a->data[i] = v;
}

static xn_Cls_E * xn_arr_o_E_remove(xn_arr_o_E *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    xn_Cls_E * old = a->data[i];
    for (size_t j = (size_t)i; j + 1 < a->len; j++) {
        a->data[j] = a->data[j + 1];
    }
    a->len--;
    return old;
}

static void xn_arr_o_E_insert(xn_arr_o_E *a, int64_t i, xn_Cls_E * v) {
    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(xn_Cls_E *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    for (size_t j = a->len; j > (size_t)i; j--) {
        a->data[j] = a->data[j - 1];
    }
    a->data[i] = v;
    a->len++;
}

static void xn_arr_o_E_clear(xn_arr_o_E *a) {
    a->len = 0;
}

static rt_string *xn_arr_o_E_join(xn_arr_o_E *a, rt_string *sep) {
    rt_string *res = rt_string_from_c("");
    for (size_t i = 0; i < a->len; i++) {
        if (i > 0) {
            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));
        }
        res = xn_concat(res, rt_string_from_c(""));
    }
    return res;
}

static void xn_arr_o_TN_scan(void *p, void (*visit)(void *)) {
    xn_arr_o_TN *a = (xn_arr_o_TN *)p;
    if (a->data == NULL) { return; }
    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }
}

static void xn_arr_o_TN_deinit(void *p) {
    xn_arr_o_TN *a = (xn_arr_o_TN *)p;
    if (a->data != NULL) {
        free(a->data);
        a->data = NULL;
    }
    a->len = 0;
    a->cap = 0;
}

static const rt_type RT_TYPE_xn_arr_o_TN = { "List", sizeof(xn_arr_o_TN), xn_arr_o_TN_deinit, xn_arr_o_TN_scan };

static xn_arr_o_TN *xn_arr_o_TN_new(size_t cap) {
    xn_arr_o_TN *a = (xn_arr_o_TN *)xn_gc_new(&RT_TYPE_xn_arr_o_TN);
    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_o_TN) - sizeof(rt_header));
    a->cap = cap ? cap : 4;
    a->data = malloc(sizeof(xn_Cls_TN *) * a->cap);
    if (a->data == NULL) { abort(); }
    return a;
}

static void xn_arr_o_TN_push(xn_arr_o_TN *a, xn_Cls_TN * v) {
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(xn_Cls_TN *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    a->data[a->len++] = v;
}

static xn_Cls_TN * xn_arr_o_TN_get(const xn_arr_o_TN *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    return a->data[i];
}

static void xn_arr_o_TN_set(xn_arr_o_TN *a, int64_t i, xn_Cls_TN * v) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    a->data[i] = v;
}

static xn_Cls_TN * xn_arr_o_TN_remove(xn_arr_o_TN *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    xn_Cls_TN * old = a->data[i];
    for (size_t j = (size_t)i; j + 1 < a->len; j++) {
        a->data[j] = a->data[j + 1];
    }
    a->len--;
    return old;
}

static void xn_arr_o_TN_insert(xn_arr_o_TN *a, int64_t i, xn_Cls_TN * v) {
    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(xn_Cls_TN *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    for (size_t j = a->len; j > (size_t)i; j--) {
        a->data[j] = a->data[j - 1];
    }
    a->data[i] = v;
    a->len++;
}

static void xn_arr_o_TN_clear(xn_arr_o_TN *a) {
    a->len = 0;
}

static rt_string *xn_arr_o_TN_join(xn_arr_o_TN *a, rt_string *sep) {
    rt_string *res = rt_string_from_c("");
    for (size_t i = 0; i < a->len; i++) {
        if (i > 0) {
            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));
        }
        res = xn_concat(res, rt_string_from_c(""));
    }
    return res;
}

static void xn_arr_o_Tok_scan(void *p, void (*visit)(void *)) {
    xn_arr_o_Tok *a = (xn_arr_o_Tok *)p;
    if (a->data == NULL) { return; }
    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }
}

static void xn_arr_o_Tok_deinit(void *p) {
    xn_arr_o_Tok *a = (xn_arr_o_Tok *)p;
    if (a->data != NULL) {
        free(a->data);
        a->data = NULL;
    }
    a->len = 0;
    a->cap = 0;
}

static const rt_type RT_TYPE_xn_arr_o_Tok = { "List", sizeof(xn_arr_o_Tok), xn_arr_o_Tok_deinit, xn_arr_o_Tok_scan };

static xn_arr_o_Tok *xn_arr_o_Tok_new(size_t cap) {
    xn_arr_o_Tok *a = (xn_arr_o_Tok *)xn_gc_new(&RT_TYPE_xn_arr_o_Tok);
    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_o_Tok) - sizeof(rt_header));
    a->cap = cap ? cap : 4;
    a->data = malloc(sizeof(xn_Cls_Tok *) * a->cap);
    if (a->data == NULL) { abort(); }
    return a;
}

static void xn_arr_o_Tok_push(xn_arr_o_Tok *a, xn_Cls_Tok * v) {
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(xn_Cls_Tok *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    a->data[a->len++] = v;
}

static xn_Cls_Tok * xn_arr_o_Tok_get(const xn_arr_o_Tok *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    return a->data[i];
}

static void xn_arr_o_Tok_set(xn_arr_o_Tok *a, int64_t i, xn_Cls_Tok * v) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    a->data[i] = v;
}

static xn_Cls_Tok * xn_arr_o_Tok_remove(xn_arr_o_Tok *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    xn_Cls_Tok * old = a->data[i];
    for (size_t j = (size_t)i; j + 1 < a->len; j++) {
        a->data[j] = a->data[j + 1];
    }
    a->len--;
    return old;
}

static void xn_arr_o_Tok_insert(xn_arr_o_Tok *a, int64_t i, xn_Cls_Tok * v) {
    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(xn_Cls_Tok *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    for (size_t j = a->len; j > (size_t)i; j--) {
        a->data[j] = a->data[j - 1];
    }
    a->data[i] = v;
    a->len++;
}

static void xn_arr_o_Tok_clear(xn_arr_o_Tok *a) {
    a->len = 0;
}

static rt_string *xn_arr_o_Tok_join(xn_arr_o_Tok *a, rt_string *sep) {
    rt_string *res = rt_string_from_c("");
    for (size_t i = 0; i < a->len; i++) {
        if (i > 0) {
            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));
        }
        res = xn_concat(res, rt_string_from_c(""));
    }
    return res;
}


static xn_arr_s *xn_str_split(rt_string *s, rt_string *sep) {
    xn_arr_s *out = xn_arr_s_new(4);
    if (sep->len == 0) {
        rt_string *t = rt_string_new(s->bytes, s->len);
        xn_arr_s_push(out, t);
        rt_release(t);
        return out;
    }
    size_t start = 0, i = 0;
    while (i + sep->len <= s->len) {
        if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) {
            rt_string *t = rt_string_new(s->bytes + start, i - start);
            xn_arr_s_push(out, t);
            rt_release(t);
            i += sep->len;
            start = i;
        } else {
            i++;
        }
    }
    rt_string *last = rt_string_new(s->bytes + start, s->len - start);
    xn_arr_s_push(out, last);
    rt_release(last);
    return out;
}
static rt_string * xn_readFileText(rt_string * xn_p_path);
static int xn_inList(xn_arr_s * xn_p_xs, rt_string * xn_p_w);
static rt_string * xn_q(rt_string * xn_p_s);
static rt_string * xn_dumpTok(xn_Cls_Tok * xn_p_t);
static rt_string * xn_P(int64_t xn_p_l, int64_t xn_p_c);
static rt_string * xn_F(rt_string * xn_p_n, rt_string * xn_p_v);
static rt_string * xn_SL(xn_arr_s * xn_p_xs);
static rt_string * xn_SLS(xn_arr_s * xn_p_xs);
static rt_string * xn_B(int xn_p_v);
static int64_t xn_main(xn_arr_s * xn_p_args);

/* 类 Tok（M4.4b） */
typedef struct xn_Cls_Tok {
    rt_header hdr;
    int64_t kind;
    rt_string * text;
    int64_t line;
    int64_t col;
    int64_t str;
    rt_string * value;
    xn_arr_s * segs;
    xn_arr_s * interps;
    int64_t ch;
    int64_t base;
    rt_string * suffix;
    int64_t hasSuffixF;
} xn_Cls_Tok;

static void xn_Cls_Tok_deinit_hook(void *p) {
    xn_Cls_Tok *o = (xn_Cls_Tok *)p;
    rt_release(o->text);
    rt_release(o->value);
    rt_release(o->suffix);
}

static void xn_Cls_Tok_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_Tok *o = (xn_Cls_Tok *)p;
    if (o->text) { visit(o->text); }
    if (o->value) { visit(o->value); }
    if (o->segs) { visit(o->segs); }
    if (o->interps) { visit(o->interps); }
    if (o->suffix) { visit(o->suffix); }
}

static const rt_type RT_TYPE_XN_Tok = { "Tok", sizeof(xn_Cls_Tok), xn_Cls_Tok_deinit_hook, xn_Cls_Tok_gc_scan };

static void xn_Cls_Tok_new_init(xn_Cls_Tok *o) {
    o->kind = 0;
    rt_string *xn_t238 = rt_string_from_c("");
    rt_release((void *)o->text);
    o->text = xn_t238;
    o->line = 1;
    o->col = 1;
    o->str = 0;
    rt_string *xn_t239 = rt_string_from_c("");
    rt_release((void *)o->value);
    o->value = xn_t239;
    xn_arr_s *xn_t240 = xn_arr_s_new(0);
    o->segs = xn_t240;
    xn_arr_s *xn_t241 = xn_arr_s_new(0);
    o->interps = xn_t241;
    o->ch = 0;
    o->base = 0;
    rt_string *xn_t242 = rt_string_from_c("");
    rt_release((void *)o->suffix);
    o->suffix = xn_t242;
    o->hasSuffixF = (int64_t)((int)(0));
}

static xn_Cls_Tok *xn_Cls_Tok_new(void) {
    xn_Cls_Tok *o = (xn_Cls_Tok *)xn_gc_new(&RT_TYPE_XN_Tok);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_Tok) - sizeof(rt_header));
    xn_Cls_Tok_new_init(o);
    return o;
}


/* 类 Diag（M4.4b） */
typedef struct xn_Cls_Diag {
    rt_header hdr;
    rt_string * code;
    int64_t line;
    int64_t col;
    rt_string * msg;
} xn_Cls_Diag;

static void xn_Cls_Diag_deinit_hook(void *p) {
    xn_Cls_Diag *o = (xn_Cls_Diag *)p;
    rt_release(o->code);
    rt_release(o->msg);
}

static void xn_Cls_Diag_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_Diag *o = (xn_Cls_Diag *)p;
    if (o->code) { visit(o->code); }
    if (o->msg) { visit(o->msg); }
}

static const rt_type RT_TYPE_XN_Diag = { "Diag", sizeof(xn_Cls_Diag), xn_Cls_Diag_deinit_hook, xn_Cls_Diag_gc_scan };

static void xn_Cls_Diag_new_init(xn_Cls_Diag *o) {
    rt_string *xn_t243 = rt_string_from_c("");
    rt_release((void *)o->code);
    o->code = xn_t243;
    o->line = 1;
    o->col = 1;
    rt_string *xn_t244 = rt_string_from_c("");
    rt_release((void *)o->msg);
    o->msg = xn_t244;
}

static xn_Cls_Diag *xn_Cls_Diag_new(void) {
    xn_Cls_Diag *o = (xn_Cls_Diag *)xn_gc_new(&RT_TYPE_XN_Diag);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_Diag) - sizeof(rt_header));
    xn_Cls_Diag_new_init(o);
    return o;
}


/* 类 Lexer（M4.4b） */
typedef struct xn_Cls_Lexer {
    rt_header hdr;
    rt_string * src;
    xrt_bytes_obj * bytes;
    int64_t pos;
    int64_t line;
    int64_t col;
    int64_t blen;
    int64_t sawNL;
    int64_t hasLast;
    xn_Cls_Tok * last;
    int64_t hasStash;
    xn_Cls_Tok * stash;
    xn_arr_o_Diag * diags;
} xn_Cls_Lexer;

static void xn_Cls_Lexer_deinit_hook(void *p) {
    xn_Cls_Lexer *o = (xn_Cls_Lexer *)p;
    rt_release(o->src);
    rt_release(o->bytes);
}

static void xn_Cls_Lexer_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_Lexer *o = (xn_Cls_Lexer *)p;
    if (o->src) { visit(o->src); }
    if (o->bytes) { visit(o->bytes); }
    if (o->last) { visit(o->last); }
    if (o->stash) { visit(o->stash); }
    if (o->diags) { visit(o->diags); }
}

static const rt_type RT_TYPE_XN_Lexer = { "Lexer", sizeof(xn_Cls_Lexer), xn_Cls_Lexer_deinit_hook, xn_Cls_Lexer_gc_scan };

static void xn_Cls_Lexer_new_init(xn_Cls_Lexer *o, rt_string * xn_p_s) {
    rt_string *xn_t245 = rt_string_from_c("");
    rt_release((void *)o->src);
    o->src = xn_t245;
    o->pos = 0;
    o->line = 1;
    o->col = 1;
    o->blen = 0;
    o->sawNL = (int64_t)((int)(0));
    o->hasLast = (int64_t)((int)(0));
    rt_release((void *)o->last);
    o->last = xn_Cls_Tok_new();
    o->hasStash = (int64_t)((int)(0));
    rt_release((void *)o->stash);
    o->stash = xn_Cls_Tok_new();
    xn_arr_o_Diag *xn_t246 = xn_arr_o_Diag_new(0);
    o->diags = xn_t246;
size_t xn_t247 = xn_root_mark();
xn_root_add(o);
xn_root_add(xn_p_s);
#line 53 "impl/lib/b2/xparser.x"
rt_string *xn_t248 = rt_retain(xn_p_s);
xn_root_add(xn_t248);
rt_release(o->src);
o->src = xn_t248;
#line 54 "impl/lib/b2/xparser.x"
rt_string *xn_t249 = rt_retain(xn_p_s);
xn_root_add(xn_t249);
xrt_bytes_obj *xn_t250 = xrt_bytes_from_string(xn_t249->bytes, xn_t249->len);
xn_root_add(xn_t250);
rt_release(xn_t249);
rt_release(o->bytes);
o->bytes = xn_t250;
#line 55 "impl/lib/b2/xparser.x"
o->blen = ((int64_t)xrt_bytes_len(o->bytes));
#line 56 "impl/lib/b2/xparser.x"
o->pos = 0;
#line 57 "impl/lib/b2/xparser.x"
o->line = 1;
#line 58 "impl/lib/b2/xparser.x"
o->col = 1;
#line 59 "impl/lib/b2/xparser.x"
    if (((((((o->blen > 0)) && ((((int64_t)xrt_bytes_get(o->bytes, (size_t)(0))) == 239))) && ((o->blen > 2))) && ((((int64_t)xrt_bytes_get(o->bytes, (size_t)(1))) == 187))) && ((((int64_t)xrt_bytes_get(o->bytes, (size_t)(2))) == 191)))) {
        size_t xn_t251 = xn_root_mark();
        #line 61 "impl/lib/b2/xparser.x"
        o->pos = 3;
            {
            xn_root_restore(xn_t251);
            }

    }
    {
    xn_root_restore(xn_t247);
    }
}

static xn_Cls_Lexer *xn_Cls_Lexer_new(rt_string * xn_p_s) {
    xn_Cls_Lexer *o = (xn_Cls_Lexer *)xn_gc_new(&RT_TYPE_XN_Lexer);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_Lexer) - sizeof(rt_header));
    xn_Cls_Lexer_new_init(o, xn_p_s);
    return o;
}

static int64_t xn_Cls_Lexer_b(xn_Cls_Lexer *self, int64_t xn_p_i);
static int xn_Cls_Lexer_eof(xn_Cls_Lexer *self);
static rt_string * xn_Cls_Lexer_piece(xn_Cls_Lexer *self, int64_t xn_p_start, int64_t xn_p_end);
static rt_string * xn_Cls_Lexer_one(xn_Cls_Lexer *self, int64_t xn_p_i);
static void xn_Cls_Lexer_adv(xn_Cls_Lexer *self);
static void xn_Cls_Lexer_err(xn_Cls_Lexer *self, rt_string * xn_p_code, int64_t xn_p_l, int64_t xn_p_c, rt_string * xn_p_msg);
static int xn_Cls_Lexer_isDigit(xn_Cls_Lexer *self, int64_t xn_p_x);
static int xn_Cls_Lexer_isHex(xn_Cls_Lexer *self, int64_t xn_p_x);
static int xn_Cls_Lexer_isIdentStart(xn_Cls_Lexer *self, int64_t xn_p_x);
static int xn_Cls_Lexer_isIdentRune(xn_Cls_Lexer *self, int64_t xn_p_x);
static void xn_Cls_Lexer_skipTrivia(xn_Cls_Lexer *self);
static int xn_Cls_Lexer_insertable(xn_Cls_Lexer *self, xn_Cls_Tok * xn_p_t);
static int xn_Cls_Lexer_blocksSemi(xn_Cls_Lexer *self, xn_Cls_Tok * xn_p_t, xn_Cls_Tok * xn_p_l);
static xn_Cls_Tok * xn_Cls_Lexer_mk(xn_Cls_Lexer *self, int64_t xn_p_kind, rt_string * xn_p_text, int64_t xn_p_l, int64_t xn_p_c);
static xn_Cls_Tok * xn_Cls_Lexer_next(xn_Cls_Lexer *self);
static xn_Cls_Tok * xn_Cls_Lexer_scanToken(xn_Cls_Lexer *self);
static rt_string * xn_Cls_Lexer_matchOp(xn_Cls_Lexer *self);
static int xn_Cls_Lexer_startsAt(xn_Cls_Lexer *self, rt_string * xn_p_s);
static int64_t xn_Cls_Lexer_opKind(xn_Cls_Lexer *self, rt_string * xn_p_s);
static int xn_Cls_Lexer_isKeyword(xn_Cls_Lexer *self, rt_string * xn_p_w);
static int64_t xn_Cls_Lexer_scanDigits(xn_Cls_Lexer *self, int64_t xn_p_base);
static xn_Cls_Tok * xn_Cls_Lexer_scanNumber(xn_Cls_Lexer *self, int64_t xn_p_l, int64_t xn_p_c);
static rt_string * xn_Cls_Lexer_scanSuffix(xn_Cls_Lexer *self);
static xn_Cls_Tok * xn_Cls_Lexer_scanChar(xn_Cls_Lexer *self, int64_t xn_p_l, int64_t xn_p_c);
static xn_Cls_Tok * xn_Cls_Lexer_scanString(xn_Cls_Lexer *self, int64_t xn_p_l, int64_t xn_p_c, int xn_p_raw, int xn_p_multiline, int xn_p_interp);

static int64_t xn_Cls_Lexer_b(xn_Cls_Lexer *self, int64_t xn_p_i) {
size_t xn_t252 = xn_root_mark();
xn_root_add(self);
#line 66 "impl/lib/b2/xparser.x"
    if ((((xn_p_i < 0)) || ((xn_p_i >= self->blen)))) {
        size_t xn_t253 = xn_root_mark();
        #line 67 "impl/lib/b2/xparser.x"
        int64_t xn_t254 = (-(1));
            {
        xn_root_restore(xn_t253);
            }
            {
        xn_root_restore(xn_t252);
            }

        return xn_t254;

    }
#line 69 "impl/lib/b2/xparser.x"
int64_t xn_t255 = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(xn_p_i)));
    {
xn_root_restore(xn_t252);
    }

return xn_t255;
    return (int64_t)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Lexer_eof(xn_Cls_Lexer *self) {
size_t xn_t256 = xn_root_mark();
xn_root_add(self);
#line 73 "impl/lib/b2/xparser.x"
int xn_t257 = (self->pos >= self->blen);
    {
xn_root_restore(xn_t256);
    }

return xn_t257;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Lexer_piece(xn_Cls_Lexer *self, int64_t xn_p_start, int64_t xn_p_end) {
size_t xn_t258 = xn_root_mark();
xn_root_add(self);
#line 77 "impl/lib/b2/xparser.x"
    if (((xn_p_end <= xn_p_start))) {
        size_t xn_t259 = xn_root_mark();
        #line 78 "impl/lib/b2/xparser.x"
        rt_string *xn_t260 = rt_string_from_c("");
xn_root_add(xn_t260);
        xn_root_add(xn_t260);
        xn_root_add(xn_t260);
            {
        xn_root_restore(xn_t259);
            }
            {
        xn_root_restore(xn_t258);
            }

        return xn_t260;

    }
#line 80 "impl/lib/b2/xparser.x"
rt_string *xn_t261 = rt_retain(self->src);
xn_root_add(xn_t261);
xn_root_add(xn_t261);
rt_string *xn_t262 = xn_str_substr(xn_t261, xn_p_start, (xn_p_end - xn_p_start));
xn_root_add(xn_t262);
xn_root_add(xn_t262);
    {
xn_root_restore(xn_t258);
    }

return xn_t262;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Lexer_one(xn_Cls_Lexer *self, int64_t xn_p_i) {
size_t xn_t263 = xn_root_mark();
xn_root_add(self);
#line 84 "impl/lib/b2/xparser.x"
rt_string *xn_t264 = rt_retain(self->src);
xn_root_add(xn_t264);
xn_root_add(xn_t264);
rt_string *xn_t265 = xn_str_substr(xn_t264, xn_p_i, 1);
xn_root_add(xn_t265);
xn_root_add(xn_t265);
    {
xn_root_restore(xn_t263);
    }

return xn_t265;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static void xn_Cls_Lexer_adv(xn_Cls_Lexer *self) {
size_t xn_t266 = xn_root_mark();
xn_root_add(self);
#line 88 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Lexer_eof(self))) {
        size_t xn_t267 = xn_root_mark();
        #line 89 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t267);
            }
            {
        xn_root_restore(xn_t266);
            }

        return;

    }
#line 91 "impl/lib/b2/xparser.x"
int64_t x = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
#line 92 "impl/lib/b2/xparser.x"
self->pos = (self->pos + 1);
#line 93 "impl/lib/b2/xparser.x"
    if (((x == 10))) {
        size_t xn_t268 = xn_root_mark();
        #line 94 "impl/lib/b2/xparser.x"
        self->line = (self->line + 1);
        #line 95 "impl/lib/b2/xparser.x"
        self->col = 1;
            {
            xn_root_restore(xn_t268);
            }

    } else {
            if ((((x < 128)) || ((x >= 192)))) {
                size_t xn_t270 = xn_root_mark();
                #line 97 "impl/lib/b2/xparser.x"
                self->col = (self->col + 1);
                    {
                    xn_root_restore(xn_t270);
                    }

            }
    }
    {
    xn_root_restore(xn_t266);
    }
}

static void xn_Cls_Lexer_err(xn_Cls_Lexer *self, rt_string * xn_p_code, int64_t xn_p_l, int64_t xn_p_c, rt_string * xn_p_msg) {
size_t xn_t271 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_code);
xn_root_add(xn_p_msg);
#line 102 "impl/lib/b2/xparser.x"
xn_Cls_Diag * d = xn_Cls_Diag_new();
xn_root_add(d);
xn_root_add(d);
xn_gc_safepoint();
#line 103 "impl/lib/b2/xparser.x"
rt_string *xn_t272 = rt_retain(xn_p_code);
xn_root_add(xn_t272);
rt_release(d->code);
d->code = xn_t272;
#line 104 "impl/lib/b2/xparser.x"
d->line = xn_p_l;
#line 105 "impl/lib/b2/xparser.x"
d->col = xn_p_c;
#line 106 "impl/lib/b2/xparser.x"
rt_string *xn_t273 = rt_retain(xn_p_msg);
xn_root_add(xn_t273);
rt_release(d->msg);
d->msg = xn_t273;
#line 107 "impl/lib/b2/xparser.x"
xn_arr_o_Diag_push(self->diags, d);
    {
    xn_root_restore(xn_t271);
    }
}

static int xn_Cls_Lexer_isDigit(xn_Cls_Lexer *self, int64_t xn_p_x) {
size_t xn_t274 = xn_root_mark();
xn_root_add(self);
#line 110 "impl/lib/b2/xparser.x"
int xn_t275 = ((xn_p_x >= 48) && (xn_p_x <= 57));
    {
xn_root_restore(xn_t274);
    }

return xn_t275;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Lexer_isHex(xn_Cls_Lexer *self, int64_t xn_p_x) {
size_t xn_t276 = xn_root_mark();
xn_root_add(self);
#line 112 "impl/lib/b2/xparser.x"
int xn_t277 = ((xn_Cls_Lexer_isDigit(self, xn_p_x) || ((xn_p_x >= 97) && (xn_p_x <= 102))) || ((xn_p_x >= 65) && (xn_p_x <= 70)));
    {
xn_root_restore(xn_t276);
    }

return xn_t277;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Lexer_isIdentStart(xn_Cls_Lexer *self, int64_t xn_p_x) {
size_t xn_t278 = xn_root_mark();
xn_root_add(self);
#line 115 "impl/lib/b2/xparser.x"
int xn_t279 = (((xn_p_x == 95) || ((xn_p_x >= 97) && (xn_p_x <= 122))) || ((xn_p_x >= 65) && (xn_p_x <= 90)));
    {
xn_root_restore(xn_t278);
    }

return xn_t279;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Lexer_isIdentRune(xn_Cls_Lexer *self, int64_t xn_p_x) {
size_t xn_t280 = xn_root_mark();
xn_root_add(self);
#line 117 "impl/lib/b2/xparser.x"
int xn_t281 = (xn_Cls_Lexer_isIdentStart(self, xn_p_x) || xn_Cls_Lexer_isDigit(self, xn_p_x));
    {
xn_root_restore(xn_t280);
    }

return xn_t281;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static void xn_Cls_Lexer_skipTrivia(xn_Cls_Lexer *self) {
size_t xn_t282 = xn_root_mark();
xn_root_add(self);
#line 120 "impl/lib/b2/xparser.x"
int go = 1;
#line 121 "impl/lib/b2/xparser.x"
    while (((go) && ((!(xn_Cls_Lexer_eof(self)))))) {
    size_t xn_t283 = xn_root_mark();
    #line 122 "impl/lib/b2/xparser.x"
    int64_t x = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
    #line 123 "impl/lib/b2/xparser.x"
        if (((((x == 32)) || ((x == 9))) || ((x == 13)))) {
            size_t xn_t284 = xn_root_mark();
            #line 124 "impl/lib/b2/xparser.x"
            xn_Cls_Lexer_adv(self);
                {
                xn_root_restore(xn_t284);
                }

        } else {
                if (((x == 10))) {
                    size_t xn_t286 = xn_root_mark();
                    #line 126 "impl/lib/b2/xparser.x"
                    self->sawNL = (int64_t)((int)(1));
                    #line 127 "impl/lib/b2/xparser.x"
                    xn_Cls_Lexer_adv(self);
                        {
                        xn_root_restore(xn_t286);
                        }

                } else {
                        if ((((x == 47)) && ((xn_Cls_Lexer_b(self, (self->pos + 1)) == 47)))) {
                            size_t xn_t288 = xn_root_mark();
                            #line 129 "impl/lib/b2/xparser.x"
                                while ((((!(xn_Cls_Lexer_eof(self)))) && ((((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))) != 10)))) {
                                size_t xn_t289 = xn_root_mark();
                                #line 130 "impl/lib/b2/xparser.x"
                                xn_Cls_Lexer_adv(self);
                                    {
                                    xn_root_restore(xn_t289);
                                    }

                                xn_gc_safepoint();
                                }
                                {
                                xn_root_restore(xn_t288);
                                }

                        } else {
                                if ((((x == 47)) && ((xn_Cls_Lexer_b(self, (self->pos + 1)) == 42)))) {
                                    size_t xn_t291 = xn_root_mark();
                                    #line 133 "impl/lib/b2/xparser.x"
                                    int64_t sl = self->line;
                                    #line 134 "impl/lib/b2/xparser.x"
                                    int64_t sc = self->col;
                                    #line 135 "impl/lib/b2/xparser.x"
                                    xn_Cls_Lexer_adv(self);
                                    #line 136 "impl/lib/b2/xparser.x"
                                    xn_Cls_Lexer_adv(self);
                                    #line 137 "impl/lib/b2/xparser.x"
                                    int closed = 0;
                                    #line 138 "impl/lib/b2/xparser.x"
                                        while (((!(xn_Cls_Lexer_eof(self))))) {
                                        size_t xn_t292 = xn_root_mark();
                                        #line 139 "impl/lib/b2/xparser.x"
                                            if ((((((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))) == 42)) && ((xn_Cls_Lexer_b(self, (self->pos + 1)) == 47)))) {
                                                size_t xn_t293 = xn_root_mark();
                                                #line 140 "impl/lib/b2/xparser.x"
                                                xn_Cls_Lexer_adv(self);
                                                #line 141 "impl/lib/b2/xparser.x"
                                                xn_Cls_Lexer_adv(self);
                                                #line 142 "impl/lib/b2/xparser.x"
                                                closed = 1;
                                                #line 143 "impl/lib/b2/xparser.x"
                                                xn_root_restore(xn_t293);
                                                xn_root_restore(xn_t292);
                                                break;
                                                    {
                                                    xn_root_restore(xn_t293);
                                                    }

                                            }
                                        #line 145 "impl/lib/b2/xparser.x"
                                        xn_Cls_Lexer_adv(self);
                                            {
                                            xn_root_restore(xn_t292);
                                            }

                                        xn_gc_safepoint();
                                        }
                                    #line 147 "impl/lib/b2/xparser.x"
                                        if (((!(closed)))) {
                                            size_t xn_t294 = xn_root_mark();
                                            #line 148 "impl/lib/b2/xparser.x"
                                            rt_string *xn_t295 = rt_string_from_c("LEX-102");
xn_root_add(xn_t295);
    xn_root_add(xn_t295);
            xn_root_add(xn_t295);
                    xn_root_add(xn_t295);
                            xn_root_add(xn_t295);
                                    xn_root_add(xn_t295);
                                            xn_root_add(xn_t295);
                                            rt_string *xn_t296 = rt_string_from_c("块注释未闭合");
xn_root_add(xn_t296);
    xn_root_add(xn_t296);
            xn_root_add(xn_t296);
                    xn_root_add(xn_t296);
                            xn_root_add(xn_t296);
                                    xn_root_add(xn_t296);
                                            xn_root_add(xn_t296);
                                            xn_Cls_Lexer_err(self, xn_t295, sl, sc, xn_t296);
                                                {
                                                xn_root_restore(xn_t294);
                                                }

                                        }
                                        {
                                        xn_root_restore(xn_t291);
                                        }

                                } else {
                                    size_t xn_t297 = xn_root_mark();
                                    #line 151 "impl/lib/b2/xparser.x"
                                    go = 0;
                                        {
                                        xn_root_restore(xn_t297);
                                        }

                                }
                        }
                }
        }
        {
        xn_root_restore(xn_t283);
        }

    xn_gc_safepoint();
    }
    {
    xn_root_restore(xn_t282);
    }
}

static int xn_Cls_Lexer_insertable(xn_Cls_Lexer *self, xn_Cls_Tok * xn_p_t) {
size_t xn_t298 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_t);
#line 157 "impl/lib/b2/xparser.x"
    if ((((((((((xn_p_t->kind == 2)) || ((xn_p_t->kind == 5))) || ((xn_p_t->kind == 6))) || ((xn_p_t->kind == 7))) || ((xn_p_t->kind == 8))) || ((xn_p_t->kind == 11))) || ((xn_p_t->kind == 15))) || ((xn_p_t->kind == 13)))) {
        size_t xn_t299 = xn_root_mark();
        #line 159 "impl/lib/b2/xparser.x"
        int xn_t300 = 1;
            {
        xn_root_restore(xn_t299);
            }
            {
        xn_root_restore(xn_t298);
            }

        return xn_t300;

    }
#line 161 "impl/lib/b2/xparser.x"
    if (((xn_p_t->kind == 9))) {
        size_t xn_t301 = xn_root_mark();
        #line 162 "impl/lib/b2/xparser.x"
        rt_string *xn_t302 = rt_retain(xn_p_t->text);
xn_root_add(xn_t302);
        xn_root_add(xn_t302);
        xn_root_add(xn_t302);
        rt_string *xn_t303 = rt_string_from_c("++");
xn_root_add(xn_t303);
        xn_root_add(xn_t303);
        xn_root_add(xn_t303);
        rt_string *xn_t304 = rt_retain(xn_p_t->text);
xn_root_add(xn_t304);
        xn_root_add(xn_t304);
        xn_root_add(xn_t304);
        rt_string *xn_t305 = rt_string_from_c("--");
xn_root_add(xn_t305);
        xn_root_add(xn_t305);
        xn_root_add(xn_t305);
        int xn_t306 = (xn_str_eq(xn_t302, xn_t303) || xn_str_eq(xn_t304, xn_t305));
            {
        xn_root_restore(xn_t301);
            }
            {
        xn_root_restore(xn_t298);
            }

        return xn_t306;

    }
#line 164 "impl/lib/b2/xparser.x"
    if (((xn_p_t->kind == 3))) {
        size_t xn_t307 = xn_root_mark();
        #line 165 "impl/lib/b2/xparser.x"
        rt_string *xn_t308 = rt_retain(xn_p_t->text);
xn_root_add(xn_t308);
        xn_root_add(xn_t308);
        xn_root_add(xn_t308);
        rt_string *xn_t309 = rt_string_from_c("return");
xn_root_add(xn_t309);
        xn_root_add(xn_t309);
        xn_root_add(xn_t309);
        rt_string *xn_t310 = rt_retain(xn_p_t->text);
xn_root_add(xn_t310);
        xn_root_add(xn_t310);
        xn_root_add(xn_t310);
        rt_string *xn_t311 = rt_string_from_c("break");
xn_root_add(xn_t311);
        xn_root_add(xn_t311);
        xn_root_add(xn_t311);
        rt_string *xn_t312 = rt_retain(xn_p_t->text);
xn_root_add(xn_t312);
        xn_root_add(xn_t312);
        xn_root_add(xn_t312);
        rt_string *xn_t313 = rt_string_from_c("continue");
xn_root_add(xn_t313);
        xn_root_add(xn_t313);
        xn_root_add(xn_t313);
        rt_string *xn_t314 = rt_retain(xn_p_t->text);
xn_root_add(xn_t314);
        xn_root_add(xn_t314);
        xn_root_add(xn_t314);
        rt_string *xn_t315 = rt_string_from_c("throw");
xn_root_add(xn_t315);
        xn_root_add(xn_t315);
        xn_root_add(xn_t315);
        int xn_t316 = (((xn_str_eq(xn_t308, xn_t309) || xn_str_eq(xn_t310, xn_t311)) || xn_str_eq(xn_t312, xn_t313)) || xn_str_eq(xn_t314, xn_t315));
            {
        xn_root_restore(xn_t307);
            }
            {
        xn_root_restore(xn_t298);
            }

        return xn_t316;

    }
#line 167 "impl/lib/b2/xparser.x"
int xn_t317 = 0;
    {
xn_root_restore(xn_t298);
    }

return xn_t317;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Lexer_blocksSemi(xn_Cls_Lexer *self, xn_Cls_Tok * xn_p_t, xn_Cls_Tok * xn_p_l) {
size_t xn_t318 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_t);
xn_root_add(xn_p_l);
#line 171 "impl/lib/b2/xparser.x"
    if (((xn_p_l->kind != 13))) {
        size_t xn_t319 = xn_root_mark();
        #line 172 "impl/lib/b2/xparser.x"
        int xn_t320 = 0;
            {
        xn_root_restore(xn_t319);
            }
            {
        xn_root_restore(xn_t318);
            }

        return xn_t320;

    }
#line 174 "impl/lib/b2/xparser.x"
rt_string *xn_t321 = rt_retain(xn_p_t->text);
xn_root_add(xn_t321);
xn_root_add(xn_t321);
rt_string *xn_t322 = rt_string_from_c("else");
xn_root_add(xn_t322);
xn_root_add(xn_t322);
rt_string *xn_t323 = rt_retain(xn_p_t->text);
xn_root_add(xn_t323);
xn_root_add(xn_t323);
rt_string *xn_t324 = rt_string_from_c("while");
xn_root_add(xn_t324);
xn_root_add(xn_t324);
int xn_t325 = ((xn_p_t->kind == 3) && (xn_str_eq(xn_t321, xn_t322) || xn_str_eq(xn_t323, xn_t324)));
    {
xn_root_restore(xn_t318);
    }

return xn_t325;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Tok * xn_Cls_Lexer_mk(xn_Cls_Lexer *self, int64_t xn_p_kind, rt_string * xn_p_text, int64_t xn_p_l, int64_t xn_p_c) {
size_t xn_t326 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_text);
#line 178 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Tok_new();
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 179 "impl/lib/b2/xparser.x"
t->kind = xn_p_kind;
#line 180 "impl/lib/b2/xparser.x"
rt_string *xn_t327 = rt_retain(xn_p_text);
xn_root_add(xn_t327);
rt_release(t->text);
t->text = xn_t327;
#line 181 "impl/lib/b2/xparser.x"
t->line = xn_p_l;
#line 182 "impl/lib/b2/xparser.x"
t->col = xn_p_c;
#line 183 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t326);
    }

return t;
    return (xn_Cls_Tok *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Tok * xn_Cls_Lexer_next(xn_Cls_Lexer *self) {
size_t xn_t328 = xn_root_mark();
xn_root_add(self);
#line 187 "impl/lib/b2/xparser.x"
    if ((((int)(self->hasStash)))) {
        size_t xn_t329 = xn_root_mark();
        #line 188 "impl/lib/b2/xparser.x"
        self->hasStash = (int64_t)((int)(0));
        #line 189 "impl/lib/b2/xparser.x"
        self->last = self->stash;
        #line 190 "impl/lib/b2/xparser.x"
        self->hasLast = (int64_t)((int)(1));
        #line 191 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t329);
            }
            {
        xn_root_restore(xn_t328);
            }

        return self->stash;

    }
#line 193 "impl/lib/b2/xparser.x"
    while (1) {
    size_t xn_t330 = xn_root_mark();
    #line 194 "impl/lib/b2/xparser.x"
    xn_Cls_Lexer_skipTrivia(self);
    #line 195 "impl/lib/b2/xparser.x"
        if ((xn_Cls_Lexer_eof(self))) {
            size_t xn_t331 = xn_root_mark();
            #line 196 "impl/lib/b2/xparser.x"
                if ((((((int)(self->sawNL))) && (((int)(self->hasLast)))) && (xn_Cls_Lexer_insertable(self, self->last)))) {
                    size_t xn_t332 = xn_root_mark();
                    #line 197 "impl/lib/b2/xparser.x"
                    self->sawNL = (int64_t)((int)(0));
                    #line 198 "impl/lib/b2/xparser.x"
                    rt_string *xn_t333 = rt_string_from_c("");
xn_root_add(xn_t333);
    xn_root_add(xn_t333);
            xn_root_add(xn_t333);
                    xn_root_add(xn_t333);
                    xn_root_add(xn_t333);
                        {
                    xn_root_restore(xn_t332);
                        }
                        {
                    xn_root_restore(xn_t331);
                        }
                        {
                    xn_root_restore(xn_t330);
                        }
                        {
                    xn_root_restore(xn_t328);
                        }

                    return xn_Cls_Lexer_mk(self, 1, xn_t333, self->last->line, self->last->col);

                }
            #line 200 "impl/lib/b2/xparser.x"
            rt_string *xn_t334 = rt_string_from_c("");
xn_root_add(xn_t334);
    xn_root_add(xn_t334);
            xn_root_add(xn_t334);
            xn_root_add(xn_t334);
                {
            xn_root_restore(xn_t331);
                }
                {
            xn_root_restore(xn_t330);
                }
                {
            xn_root_restore(xn_t328);
                }

            return xn_Cls_Lexer_mk(self, 0, xn_t334, self->line, self->col);

        }
    #line 202 "impl/lib/b2/xparser.x"
    xn_Cls_Tok * t = xn_Cls_Lexer_scanToken(self);
xn_root_add(t);
    xn_root_add(t);
    xn_root_add(t);
    xn_gc_safepoint();
    #line 203 "impl/lib/b2/xparser.x"
        if (((t->kind == (-(1))))) {
            size_t xn_t335 = xn_root_mark();
            #line 204 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t335);
            xn_root_restore(xn_t330);
            continue;
                {
                xn_root_restore(xn_t335);
                }

        }
    #line 206 "impl/lib/b2/xparser.x"
        if (((((((int)(self->sawNL))) && (((int)(self->hasLast)))) && (xn_Cls_Lexer_insertable(self, self->last))) && ((!(xn_Cls_Lexer_blocksSemi(self, t, self->last)))))) {
            size_t xn_t336 = xn_root_mark();
            #line 207 "impl/lib/b2/xparser.x"
            self->hasStash = (int64_t)((int)(1));
            #line 208 "impl/lib/b2/xparser.x"
            self->stash = t;
            #line 209 "impl/lib/b2/xparser.x"
            self->sawNL = (int64_t)((int)(0));
            #line 210 "impl/lib/b2/xparser.x"
            rt_string *xn_t337 = rt_string_from_c("");
xn_root_add(xn_t337);
    xn_root_add(xn_t337);
            xn_root_add(xn_t337);
            xn_root_add(xn_t337);
                {
            xn_root_restore(xn_t336);
                }
                {
            xn_root_restore(xn_t330);
                }
                {
            xn_root_restore(xn_t328);
                }

            return xn_Cls_Lexer_mk(self, 1, xn_t337, self->last->line, self->last->col);

        }
    #line 212 "impl/lib/b2/xparser.x"
    self->sawNL = (int64_t)((int)(0));
    #line 213 "impl/lib/b2/xparser.x"
    self->last = t;
    #line 214 "impl/lib/b2/xparser.x"
    self->hasLast = (int64_t)((int)(1));
    #line 215 "impl/lib/b2/xparser.x"
        {
    xn_root_restore(xn_t330);
        }
        {
    xn_root_restore(xn_t328);
        }

    return t;

    xn_gc_safepoint();
    }
    {
    xn_root_restore(xn_t328);
    }
    return (xn_Cls_Tok *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Tok * xn_Cls_Lexer_scanToken(xn_Cls_Lexer *self) {
size_t xn_t338 = xn_root_mark();
xn_root_add(self);
#line 220 "impl/lib/b2/xparser.x"
int64_t l = self->line;
#line 221 "impl/lib/b2/xparser.x"
int64_t c = self->col;
#line 222 "impl/lib/b2/xparser.x"
int64_t x = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
#line 224 "impl/lib/b2/xparser.x"
    if (((((x == 34)) && ((xn_Cls_Lexer_b(self, (self->pos + 1)) == 34))) && ((xn_Cls_Lexer_b(self, (self->pos + 2)) == 34)))) {
        size_t xn_t339 = xn_root_mark();
        #line 225 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t339);
            }
            {
        xn_root_restore(xn_t338);
            }

        return xn_Cls_Lexer_scanString(self, l, c, 0, 1, 0);

    }
#line 227 "impl/lib/b2/xparser.x"
    if ((((((x == 114)) && ((xn_Cls_Lexer_b(self, (self->pos + 1)) == 34))) && ((xn_Cls_Lexer_b(self, (self->pos + 2)) == 34))) && ((xn_Cls_Lexer_b(self, (self->pos + 3)) == 34)))) {
        size_t xn_t340 = xn_root_mark();
        #line 228 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t340);
            }
            {
        xn_root_restore(xn_t338);
            }

        return xn_Cls_Lexer_scanString(self, l, c, 1, 1, 0);

    }
#line 230 "impl/lib/b2/xparser.x"
    if ((((x == 36)) && ((xn_Cls_Lexer_b(self, (self->pos + 1)) == 34)))) {
        size_t xn_t341 = xn_root_mark();
        #line 231 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t341);
            }
            {
        xn_root_restore(xn_t338);
            }

        return xn_Cls_Lexer_scanString(self, l, c, 0, 0, 1);

    }
#line 233 "impl/lib/b2/xparser.x"
    if ((((x == 114)) && ((xn_Cls_Lexer_b(self, (self->pos + 1)) == 34)))) {
        size_t xn_t342 = xn_root_mark();
        #line 234 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t342);
            }
            {
        xn_root_restore(xn_t338);
            }

        return xn_Cls_Lexer_scanString(self, l, c, 1, 0, 0);

    }
#line 236 "impl/lib/b2/xparser.x"
    if (((x == 34))) {
        size_t xn_t343 = xn_root_mark();
        #line 237 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t343);
            }
            {
        xn_root_restore(xn_t338);
            }

        return xn_Cls_Lexer_scanString(self, l, c, 0, 0, 0);

    }
#line 239 "impl/lib/b2/xparser.x"
    if (((x == 39))) {
        size_t xn_t344 = xn_root_mark();
        #line 240 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t344);
            }
            {
        xn_root_restore(xn_t338);
            }

        return xn_Cls_Lexer_scanChar(self, l, c);

    }
#line 242 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Lexer_isDigit(self, x))) {
        size_t xn_t345 = xn_root_mark();
        #line 243 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t345);
            }
            {
        xn_root_restore(xn_t338);
            }

        return xn_Cls_Lexer_scanNumber(self, l, c);

    }
#line 245 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Lexer_isIdentStart(self, x))) {
        size_t xn_t346 = xn_root_mark();
        #line 246 "impl/lib/b2/xparser.x"
        int64_t start = self->pos;
        #line 247 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 248 "impl/lib/b2/xparser.x"
            while ((((!(xn_Cls_Lexer_eof(self)))) && (xn_Cls_Lexer_isIdentRune(self, ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))))))) {
            size_t xn_t347 = xn_root_mark();
            #line 249 "impl/lib/b2/xparser.x"
            xn_Cls_Lexer_adv(self);
                {
                xn_root_restore(xn_t347);
                }

            xn_gc_safepoint();
            }
        #line 251 "impl/lib/b2/xparser.x"
        rt_string *word = xn_Cls_Lexer_piece(self, start, self->pos);
xn_root_add(word);
        xn_root_add(word);
        xn_root_add(word);
        xn_gc_safepoint();
        #line 252 "impl/lib/b2/xparser.x"
        rt_string *xn_t349 = rt_retain(word);
xn_root_add(xn_t349);
        xn_root_add(xn_t349);
            if ((xn_Cls_Lexer_isKeyword(self, xn_t349))) {
                size_t xn_t350 = xn_root_mark();
                #line 253 "impl/lib/b2/xparser.x"
                rt_string *xn_t351 = rt_retain(word);
xn_root_add(xn_t351);
        xn_root_add(xn_t351);
                xn_root_add(xn_t351);
                xn_root_add(xn_t351);
                    {
                xn_root_restore(xn_t350);
                    }
                    {
                rt_release(word);
                    }
                    {
                xn_root_restore(xn_t346);
                    }
                    {
                xn_root_restore(xn_t338);
                    }

                return xn_Cls_Lexer_mk(self, 3, xn_t351, l, c);

            }
        #line 255 "impl/lib/b2/xparser.x"
        rt_string *xn_t352 = rt_retain(word);
xn_root_add(xn_t352);
        xn_root_add(xn_t352);
        xn_root_add(xn_t352);
            {
        rt_release(word);
            }
            {
        xn_root_restore(xn_t346);
            }
            {
        xn_root_restore(xn_t338);
            }

        return xn_Cls_Lexer_mk(self, 2, xn_t352, l, c);

    }
#line 257 "impl/lib/b2/xparser.x"
    if ((((x == 64)) && (xn_Cls_Lexer_isIdentStart(self, xn_Cls_Lexer_b(self, (self->pos + 1)))))) {
        size_t xn_t353 = xn_root_mark();
        #line 258 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 259 "impl/lib/b2/xparser.x"
        int64_t start = self->pos;
        #line 260 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 261 "impl/lib/b2/xparser.x"
            while ((((!(xn_Cls_Lexer_eof(self)))) && (xn_Cls_Lexer_isIdentRune(self, ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))))))) {
            size_t xn_t354 = xn_root_mark();
            #line 262 "impl/lib/b2/xparser.x"
            xn_Cls_Lexer_adv(self);
                {
                xn_root_restore(xn_t354);
                }

            xn_gc_safepoint();
            }
        #line 264 "impl/lib/b2/xparser.x"
        rt_string *xn_t355 = xn_Cls_Lexer_piece(self, start, self->pos);
xn_root_add(xn_t355);
        xn_root_add(xn_t355);
        xn_root_add(xn_t355);
            {
        xn_root_restore(xn_t353);
            }
            {
        xn_root_restore(xn_t338);
            }

        return xn_Cls_Lexer_mk(self, 4, xn_t355, l, c);

    }
#line 266 "impl/lib/b2/xparser.x"
rt_string *op = xn_Cls_Lexer_matchOp(self);
xn_root_add(op);
xn_root_add(op);
xn_gc_safepoint();
#line 267 "impl/lib/b2/xparser.x"
rt_string *xn_t357 = rt_retain(op);
xn_root_add(xn_t357);
rt_string *xn_t358 = rt_string_from_c("");
xn_root_add(xn_t358);
    if (((!(xn_str_eq(xn_t357, xn_t358))))) {
        size_t xn_t359 = xn_root_mark();
        #line 268 "impl/lib/b2/xparser.x"
        rt_string *xn_t360 = rt_retain(op);
xn_root_add(xn_t360);
        xn_root_add(xn_t360);
        xn_root_add(xn_t360);
        rt_string *xn_t361 = rt_retain(op);
xn_root_add(xn_t361);
        xn_root_add(xn_t361);
        xn_root_add(xn_t361);
            {
        xn_root_restore(xn_t359);
            }
            {
        rt_release(op);
            }
            {
        xn_root_restore(xn_t338);
            }

        return xn_Cls_Lexer_mk(self, xn_Cls_Lexer_opKind(self, xn_t360), xn_t361, l, c);

    }
#line 270 "impl/lib/b2/xparser.x"
xn_Cls_Lexer_adv(self);
#line 271 "impl/lib/b2/xparser.x"
rt_string *xn_t362 = rt_string_from_c("LEX-101");
xn_root_add(xn_t362);
rt_string *xn_t363 = rt_string_from_c("无法识别的字符");
xn_root_add(xn_t363);
xn_Cls_Lexer_err(self, xn_t362, l, c, xn_t363);
#line 272 "impl/lib/b2/xparser.x"
rt_string *xn_t364 = rt_string_from_c("");
xn_root_add(xn_t364);
xn_root_add(xn_t364);
    {
rt_release(op);
    }
    {
xn_root_restore(xn_t338);
    }

return xn_Cls_Lexer_mk(self, (-(1)), xn_t364, l, c);
    return (xn_Cls_Tok *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Lexer_matchOp(xn_Cls_Lexer *self) {
size_t xn_t365 = xn_root_mark();
xn_root_add(self);
#line 276 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t366 = xn_arr_s_new(52);
xn_root_add(xn_t366);
rt_string *xn_t367 = rt_string_from_c("<<=");
xn_root_add(xn_t367);
xn_arr_s_push(xn_t366, xn_t367);
rt_string *xn_t368 = rt_string_from_c(">>=");
xn_root_add(xn_t368);
xn_arr_s_push(xn_t366, xn_t368);
rt_string *xn_t369 = rt_string_from_c("...");
xn_root_add(xn_t369);
xn_arr_s_push(xn_t366, xn_t369);
rt_string *xn_t370 = rt_string_from_c("..<");
xn_root_add(xn_t370);
xn_arr_s_push(xn_t366, xn_t370);
rt_string *xn_t371 = rt_string_from_c("===");
xn_root_add(xn_t371);
xn_arr_s_push(xn_t366, xn_t371);
rt_string *xn_t372 = rt_string_from_c("!==");
xn_root_add(xn_t372);
xn_arr_s_push(xn_t366, xn_t372);
rt_string *xn_t373 = rt_string_from_c("==");
xn_root_add(xn_t373);
xn_arr_s_push(xn_t366, xn_t373);
rt_string *xn_t374 = rt_string_from_c("!=");
xn_root_add(xn_t374);
xn_arr_s_push(xn_t366, xn_t374);
rt_string *xn_t375 = rt_string_from_c("<=");
xn_root_add(xn_t375);
xn_arr_s_push(xn_t366, xn_t375);
rt_string *xn_t376 = rt_string_from_c(">=");
xn_root_add(xn_t376);
xn_arr_s_push(xn_t366, xn_t376);
rt_string *xn_t377 = rt_string_from_c("<<");
xn_root_add(xn_t377);
xn_arr_s_push(xn_t366, xn_t377);
rt_string *xn_t378 = rt_string_from_c(">>");
xn_root_add(xn_t378);
xn_arr_s_push(xn_t366, xn_t378);
rt_string *xn_t379 = rt_string_from_c("&&");
xn_root_add(xn_t379);
xn_arr_s_push(xn_t366, xn_t379);
rt_string *xn_t380 = rt_string_from_c("||");
xn_root_add(xn_t380);
xn_arr_s_push(xn_t366, xn_t380);
rt_string *xn_t381 = rt_string_from_c("??");
xn_root_add(xn_t381);
xn_arr_s_push(xn_t366, xn_t381);
rt_string *xn_t382 = rt_string_from_c("?.");
xn_root_add(xn_t382);
xn_arr_s_push(xn_t366, xn_t382);
rt_string *xn_t383 = rt_string_from_c("->");
xn_root_add(xn_t383);
xn_arr_s_push(xn_t366, xn_t383);
rt_string *xn_t384 = rt_string_from_c("+=");
xn_root_add(xn_t384);
xn_arr_s_push(xn_t366, xn_t384);
rt_string *xn_t385 = rt_string_from_c("-=");
xn_root_add(xn_t385);
xn_arr_s_push(xn_t366, xn_t385);
rt_string *xn_t386 = rt_string_from_c("*=");
xn_root_add(xn_t386);
xn_arr_s_push(xn_t366, xn_t386);
rt_string *xn_t387 = rt_string_from_c("/=");
xn_root_add(xn_t387);
xn_arr_s_push(xn_t366, xn_t387);
rt_string *xn_t388 = rt_string_from_c("%=");
xn_root_add(xn_t388);
xn_arr_s_push(xn_t366, xn_t388);
rt_string *xn_t389 = rt_string_from_c("&=");
xn_root_add(xn_t389);
xn_arr_s_push(xn_t366, xn_t389);
rt_string *xn_t390 = rt_string_from_c("|=");
xn_root_add(xn_t390);
xn_arr_s_push(xn_t366, xn_t390);
rt_string *xn_t391 = rt_string_from_c("^=");
xn_root_add(xn_t391);
xn_arr_s_push(xn_t366, xn_t391);
rt_string *xn_t392 = rt_string_from_c("++");
xn_root_add(xn_t392);
xn_arr_s_push(xn_t366, xn_t392);
rt_string *xn_t393 = rt_string_from_c("--");
xn_root_add(xn_t393);
xn_arr_s_push(xn_t366, xn_t393);
rt_string *xn_t394 = rt_string_from_c("+");
xn_root_add(xn_t394);
xn_arr_s_push(xn_t366, xn_t394);
rt_string *xn_t395 = rt_string_from_c("-");
xn_root_add(xn_t395);
xn_arr_s_push(xn_t366, xn_t395);
rt_string *xn_t396 = rt_string_from_c("*");
xn_root_add(xn_t396);
xn_arr_s_push(xn_t366, xn_t396);
rt_string *xn_t397 = rt_string_from_c("/");
xn_root_add(xn_t397);
xn_arr_s_push(xn_t366, xn_t397);
rt_string *xn_t398 = rt_string_from_c("%");
xn_root_add(xn_t398);
xn_arr_s_push(xn_t366, xn_t398);
rt_string *xn_t399 = rt_string_from_c("=");
xn_root_add(xn_t399);
xn_arr_s_push(xn_t366, xn_t399);
rt_string *xn_t400 = rt_string_from_c("<");
xn_root_add(xn_t400);
xn_arr_s_push(xn_t366, xn_t400);
rt_string *xn_t401 = rt_string_from_c(">");
xn_root_add(xn_t401);
xn_arr_s_push(xn_t366, xn_t401);
rt_string *xn_t402 = rt_string_from_c("!");
xn_root_add(xn_t402);
xn_arr_s_push(xn_t366, xn_t402);
rt_string *xn_t403 = rt_string_from_c("?");
xn_root_add(xn_t403);
xn_arr_s_push(xn_t366, xn_t403);
rt_string *xn_t404 = rt_string_from_c(":");
xn_root_add(xn_t404);
xn_arr_s_push(xn_t366, xn_t404);
rt_string *xn_t405 = rt_string_from_c("&");
xn_root_add(xn_t405);
xn_arr_s_push(xn_t366, xn_t405);
rt_string *xn_t406 = rt_string_from_c("|");
xn_root_add(xn_t406);
xn_arr_s_push(xn_t366, xn_t406);
rt_string *xn_t407 = rt_string_from_c("^");
xn_root_add(xn_t407);
xn_arr_s_push(xn_t366, xn_t407);
rt_string *xn_t408 = rt_string_from_c("~");
xn_root_add(xn_t408);
xn_arr_s_push(xn_t366, xn_t408);
rt_string *xn_t409 = rt_string_from_c(".");
xn_root_add(xn_t409);
xn_arr_s_push(xn_t366, xn_t409);
rt_string *xn_t410 = rt_string_from_c(",");
xn_root_add(xn_t410);
xn_arr_s_push(xn_t366, xn_t410);
rt_string *xn_t411 = rt_string_from_c(";");
xn_root_add(xn_t411);
xn_arr_s_push(xn_t366, xn_t411);
rt_string *xn_t412 = rt_string_from_c("@");
xn_root_add(xn_t412);
xn_arr_s_push(xn_t366, xn_t412);
rt_string *xn_t413 = rt_string_from_c("(");
xn_root_add(xn_t413);
xn_arr_s_push(xn_t366, xn_t413);
rt_string *xn_t414 = rt_string_from_c(")");
xn_root_add(xn_t414);
xn_arr_s_push(xn_t366, xn_t414);
rt_string *xn_t415 = rt_string_from_c("{");
xn_root_add(xn_t415);
xn_arr_s_push(xn_t366, xn_t415);
rt_string *xn_t416 = rt_string_from_c("}");
xn_root_add(xn_t416);
xn_arr_s_push(xn_t366, xn_t416);
rt_string *xn_t417 = rt_string_from_c("[");
xn_root_add(xn_t417);
xn_arr_s_push(xn_t366, xn_t417);
rt_string *xn_t418 = rt_string_from_c("]");
xn_root_add(xn_t418);
xn_arr_s_push(xn_t366, xn_t418);
xn_arr_s * ops = xn_t366;
xn_root_add(ops);
xn_root_add(ops);
xn_gc_safepoint();
#line 280 "impl/lib/b2/xparser.x"
int64_t i = 0;
#line 281 "impl/lib/b2/xparser.x"
    while (((i < ((int64_t)ops->len)))) {
    size_t xn_t419 = xn_root_mark();
    #line 282 "impl/lib/b2/xparser.x"
    rt_string *s = rt_retain(xn_arr_s_get(ops, i));
xn_root_add(s);
    xn_root_add(s);
    xn_root_add(s);
    xn_gc_safepoint();
    #line 283 "impl/lib/b2/xparser.x"
    rt_string *xn_t421 = rt_retain(s);
xn_root_add(xn_t421);
    xn_root_add(xn_t421);
        if ((xn_Cls_Lexer_startsAt(self, xn_t421))) {
            size_t xn_t422 = xn_root_mark();
            #line 284 "impl/lib/b2/xparser.x"
            self->pos = (self->pos + xn_str_length(s));
            #line 285 "impl/lib/b2/xparser.x"
            rt_string *xn_t423 = rt_retain(s);
xn_root_add(xn_t423);
    xn_root_add(xn_t423);
            xn_root_add(xn_t423);
            rt_string *xn_t424 = rt_string_from_c("(");
xn_root_add(xn_t424);
    xn_root_add(xn_t424);
            xn_root_add(xn_t424);
            rt_string *xn_t425 = rt_retain(s);
xn_root_add(xn_t425);
    xn_root_add(xn_t425);
            xn_root_add(xn_t425);
            rt_string *xn_t426 = rt_string_from_c(")");
xn_root_add(xn_t426);
    xn_root_add(xn_t426);
            xn_root_add(xn_t426);
            rt_string *xn_t427 = rt_retain(s);
xn_root_add(xn_t427);
    xn_root_add(xn_t427);
            xn_root_add(xn_t427);
            rt_string *xn_t428 = rt_string_from_c("{");
xn_root_add(xn_t428);
    xn_root_add(xn_t428);
            xn_root_add(xn_t428);
            rt_string *xn_t429 = rt_retain(s);
xn_root_add(xn_t429);
    xn_root_add(xn_t429);
            xn_root_add(xn_t429);
            rt_string *xn_t430 = rt_string_from_c("}");
xn_root_add(xn_t430);
    xn_root_add(xn_t430);
            xn_root_add(xn_t430);
            rt_string *xn_t431 = rt_retain(s);
xn_root_add(xn_t431);
    xn_root_add(xn_t431);
            xn_root_add(xn_t431);
            rt_string *xn_t432 = rt_string_from_c("[");
xn_root_add(xn_t432);
    xn_root_add(xn_t432);
            xn_root_add(xn_t432);
            rt_string *xn_t433 = rt_retain(s);
xn_root_add(xn_t433);
    xn_root_add(xn_t433);
            xn_root_add(xn_t433);
            rt_string *xn_t434 = rt_string_from_c("]");
xn_root_add(xn_t434);
    xn_root_add(xn_t434);
            xn_root_add(xn_t434);
                if (((((((xn_str_eq(xn_t423, xn_t424)) || (xn_str_eq(xn_t425, xn_t426))) || (xn_str_eq(xn_t427, xn_t428))) || (xn_str_eq(xn_t429, xn_t430))) || (xn_str_eq(xn_t431, xn_t432))) || (xn_str_eq(xn_t433, xn_t434)))) {
                    size_t xn_t435 = xn_root_mark();
                    #line 286 "impl/lib/b2/xparser.x"
                    self->col = (self->col + 1);
                        {
                        xn_root_restore(xn_t435);
                        }

                } else {
                    rt_string *xn_t437 = rt_retain(s);
xn_root_add(xn_t437);
    xn_root_add(xn_t437);
            xn_root_add(xn_t437);
                    xn_root_add(xn_t437);
                    rt_string *xn_t438 = rt_string_from_c(";");
xn_root_add(xn_t438);
    xn_root_add(xn_t438);
            xn_root_add(xn_t438);
                    xn_root_add(xn_t438);
                    rt_string *xn_t439 = rt_retain(s);
xn_root_add(xn_t439);
    xn_root_add(xn_t439);
            xn_root_add(xn_t439);
                    xn_root_add(xn_t439);
                    rt_string *xn_t440 = rt_string_from_c(",");
xn_root_add(xn_t440);
    xn_root_add(xn_t440);
            xn_root_add(xn_t440);
                    xn_root_add(xn_t440);
                        if (((xn_str_eq(xn_t437, xn_t438)) || (xn_str_eq(xn_t439, xn_t440)))) {
                            size_t xn_t441 = xn_root_mark();
                            #line 288 "impl/lib/b2/xparser.x"
                            self->col = (self->col + 1);
                                {
                                xn_root_restore(xn_t441);
                                }

                        } else {
                            size_t xn_t442 = xn_root_mark();
                            #line 290 "impl/lib/b2/xparser.x"
                            self->col = (self->col + xn_str_length(s));
                                {
                                xn_root_restore(xn_t442);
                                }

                        }
                }
            #line 292 "impl/lib/b2/xparser.x"
            rt_retain(s);
                {
            xn_root_restore(xn_t422);
                }
                {
            rt_release(s);
                }
                {
            xn_root_restore(xn_t419);
                }
                {
            xn_root_restore(xn_t365);
                }

            return s;

        }
    #line 294 "impl/lib/b2/xparser.x"
    i = (i + 1);
        {
        rt_release(s);
        }
        {
        xn_root_restore(xn_t419);
        }

    xn_gc_safepoint();
    }
#line 296 "impl/lib/b2/xparser.x"
rt_string *xn_t443 = rt_string_from_c("");
xn_root_add(xn_t443);
xn_root_add(xn_t443);
    {
xn_root_restore(xn_t365);
    }

return xn_t443;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Lexer_startsAt(xn_Cls_Lexer *self, rt_string * xn_p_s) {
size_t xn_t444 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_s);
#line 300 "impl/lib/b2/xparser.x"
    if ((((self->pos + xn_str_length(xn_p_s)) > self->blen))) {
        size_t xn_t445 = xn_root_mark();
        #line 301 "impl/lib/b2/xparser.x"
        int xn_t446 = 0;
            {
        xn_root_restore(xn_t445);
            }
            {
        xn_root_restore(xn_t444);
            }

        return xn_t446;

    }
#line 303 "impl/lib/b2/xparser.x"
rt_string *xn_t447 = rt_retain(self->src);
xn_root_add(xn_t447);
xn_root_add(xn_t447);
rt_string *xn_t448 = xn_str_substr(xn_t447, self->pos, xn_str_length(xn_p_s));
xn_root_add(xn_t448);
xn_root_add(xn_t448);
rt_string *xn_t449 = rt_retain(xn_p_s);
xn_root_add(xn_t449);
xn_root_add(xn_t449);
int xn_t450 = xn_str_eq(xn_t448, xn_t449);
    {
xn_root_restore(xn_t444);
    }

return xn_t450;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static int64_t xn_Cls_Lexer_opKind(xn_Cls_Lexer *self, rt_string * xn_p_s) {
size_t xn_t451 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_s);
#line 307 "impl/lib/b2/xparser.x"
rt_string *xn_t452 = rt_retain(xn_p_s);
xn_root_add(xn_t452);
rt_string *xn_t453 = rt_string_from_c("(");
xn_root_add(xn_t453);
    if ((xn_str_eq(xn_t452, xn_t453))) {
        size_t xn_t454 = xn_root_mark();
        #line 307 "impl/lib/b2/xparser.x"
        int64_t xn_t455 = 10;
            {
        xn_root_restore(xn_t454);
            }
            {
        xn_root_restore(xn_t451);
            }

        return xn_t455;

    }
#line 308 "impl/lib/b2/xparser.x"
rt_string *xn_t456 = rt_retain(xn_p_s);
xn_root_add(xn_t456);
rt_string *xn_t457 = rt_string_from_c(")");
xn_root_add(xn_t457);
    if ((xn_str_eq(xn_t456, xn_t457))) {
        size_t xn_t458 = xn_root_mark();
        #line 308 "impl/lib/b2/xparser.x"
        int64_t xn_t459 = 11;
            {
        xn_root_restore(xn_t458);
            }
            {
        xn_root_restore(xn_t451);
            }

        return xn_t459;

    }
#line 309 "impl/lib/b2/xparser.x"
rt_string *xn_t460 = rt_retain(xn_p_s);
xn_root_add(xn_t460);
rt_string *xn_t461 = rt_string_from_c("{");
xn_root_add(xn_t461);
    if ((xn_str_eq(xn_t460, xn_t461))) {
        size_t xn_t462 = xn_root_mark();
        #line 309 "impl/lib/b2/xparser.x"
        int64_t xn_t463 = 12;
            {
        xn_root_restore(xn_t462);
            }
            {
        xn_root_restore(xn_t451);
            }

        return xn_t463;

    }
#line 310 "impl/lib/b2/xparser.x"
rt_string *xn_t464 = rt_retain(xn_p_s);
xn_root_add(xn_t464);
rt_string *xn_t465 = rt_string_from_c("}");
xn_root_add(xn_t465);
    if ((xn_str_eq(xn_t464, xn_t465))) {
        size_t xn_t466 = xn_root_mark();
        #line 310 "impl/lib/b2/xparser.x"
        int64_t xn_t467 = 13;
            {
        xn_root_restore(xn_t466);
            }
            {
        xn_root_restore(xn_t451);
            }

        return xn_t467;

    }
#line 311 "impl/lib/b2/xparser.x"
rt_string *xn_t468 = rt_retain(xn_p_s);
xn_root_add(xn_t468);
rt_string *xn_t469 = rt_string_from_c("[");
xn_root_add(xn_t469);
    if ((xn_str_eq(xn_t468, xn_t469))) {
        size_t xn_t470 = xn_root_mark();
        #line 311 "impl/lib/b2/xparser.x"
        int64_t xn_t471 = 14;
            {
        xn_root_restore(xn_t470);
            }
            {
        xn_root_restore(xn_t451);
            }

        return xn_t471;

    }
#line 312 "impl/lib/b2/xparser.x"
rt_string *xn_t472 = rt_retain(xn_p_s);
xn_root_add(xn_t472);
rt_string *xn_t473 = rt_string_from_c("]");
xn_root_add(xn_t473);
    if ((xn_str_eq(xn_t472, xn_t473))) {
        size_t xn_t474 = xn_root_mark();
        #line 312 "impl/lib/b2/xparser.x"
        int64_t xn_t475 = 15;
            {
        xn_root_restore(xn_t474);
            }
            {
        xn_root_restore(xn_t451);
            }

        return xn_t475;

    }
#line 313 "impl/lib/b2/xparser.x"
rt_string *xn_t476 = rt_retain(xn_p_s);
xn_root_add(xn_t476);
rt_string *xn_t477 = rt_string_from_c(",");
xn_root_add(xn_t477);
    if ((xn_str_eq(xn_t476, xn_t477))) {
        size_t xn_t478 = xn_root_mark();
        #line 313 "impl/lib/b2/xparser.x"
        int64_t xn_t479 = 16;
            {
        xn_root_restore(xn_t478);
            }
            {
        xn_root_restore(xn_t451);
            }

        return xn_t479;

    }
#line 314 "impl/lib/b2/xparser.x"
rt_string *xn_t480 = rt_retain(xn_p_s);
xn_root_add(xn_t480);
rt_string *xn_t481 = rt_string_from_c(";");
xn_root_add(xn_t481);
    if ((xn_str_eq(xn_t480, xn_t481))) {
        size_t xn_t482 = xn_root_mark();
        #line 314 "impl/lib/b2/xparser.x"
        int64_t xn_t483 = 1;
            {
        xn_root_restore(xn_t482);
            }
            {
        xn_root_restore(xn_t451);
            }

        return xn_t483;

    }
#line 315 "impl/lib/b2/xparser.x"
int64_t xn_t484 = 9;
    {
xn_root_restore(xn_t451);
    }

return xn_t484;
    return (int64_t)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Lexer_isKeyword(xn_Cls_Lexer *self, rt_string * xn_p_w) {
size_t xn_t485 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_w);
#line 319 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t486 = xn_arr_s_new(41);
xn_root_add(xn_t486);
rt_string *xn_t487 = rt_string_from_c("package");
xn_root_add(xn_t487);
xn_arr_s_push(xn_t486, xn_t487);
rt_string *xn_t488 = rt_string_from_c("import");
xn_root_add(xn_t488);
xn_arr_s_push(xn_t486, xn_t488);
rt_string *xn_t489 = rt_string_from_c("as");
xn_root_add(xn_t489);
xn_arr_s_push(xn_t486, xn_t489);
rt_string *xn_t490 = rt_string_from_c("public");
xn_root_add(xn_t490);
xn_arr_s_push(xn_t486, xn_t490);
rt_string *xn_t491 = rt_string_from_c("protected");
xn_root_add(xn_t491);
xn_arr_s_push(xn_t486, xn_t491);
rt_string *xn_t492 = rt_string_from_c("private");
xn_root_add(xn_t492);
xn_arr_s_push(xn_t486, xn_t492);
rt_string *xn_t493 = rt_string_from_c("final");
xn_root_add(xn_t493);
xn_arr_s_push(xn_t486, xn_t493);
rt_string *xn_t494 = rt_string_from_c("static");
xn_root_add(xn_t494);
xn_arr_s_push(xn_t486, xn_t494);
rt_string *xn_t495 = rt_string_from_c("const");
xn_root_add(xn_t495);
xn_arr_s_push(xn_t486, xn_t495);
rt_string *xn_t496 = rt_string_from_c("var");
xn_root_add(xn_t496);
xn_arr_s_push(xn_t486, xn_t496);
rt_string *xn_t497 = rt_string_from_c("abstract");
xn_root_add(xn_t497);
xn_arr_s_push(xn_t486, xn_t497);
rt_string *xn_t498 = rt_string_from_c("class");
xn_root_add(xn_t498);
xn_arr_s_push(xn_t486, xn_t498);
rt_string *xn_t499 = rt_string_from_c("struct");
xn_root_add(xn_t499);
xn_arr_s_push(xn_t486, xn_t499);
rt_string *xn_t500 = rt_string_from_c("protocol");
xn_root_add(xn_t500);
xn_arr_s_push(xn_t486, xn_t500);
rt_string *xn_t501 = rt_string_from_c("enum");
xn_root_add(xn_t501);
xn_arr_s_push(xn_t486, xn_t501);
rt_string *xn_t502 = rt_string_from_c("singleton");
xn_root_add(xn_t502);
xn_arr_s_push(xn_t486, xn_t502);
rt_string *xn_t503 = rt_string_from_c("factory");
xn_root_add(xn_t503);
xn_arr_s_push(xn_t486, xn_t503);
rt_string *xn_t504 = rt_string_from_c("extension");
xn_root_add(xn_t504);
xn_arr_s_push(xn_t486, xn_t504);
rt_string *xn_t505 = rt_string_from_c("implements");
xn_root_add(xn_t505);
xn_arr_s_push(xn_t486, xn_t505);
rt_string *xn_t506 = rt_string_from_c("new");
xn_root_add(xn_t506);
xn_arr_s_push(xn_t486, xn_t506);
rt_string *xn_t507 = rt_string_from_c("self");
xn_root_add(xn_t507);
xn_arr_s_push(xn_t486, xn_t507);
rt_string *xn_t508 = rt_string_from_c("super");
xn_root_add(xn_t508);
xn_arr_s_push(xn_t486, xn_t508);
rt_string *xn_t509 = rt_string_from_c("out");
xn_root_add(xn_t509);
xn_arr_s_push(xn_t486, xn_t509);
rt_string *xn_t510 = rt_string_from_c("in");
xn_root_add(xn_t510);
xn_arr_s_push(xn_t486, xn_t510);
rt_string *xn_t511 = rt_string_from_c("if");
xn_root_add(xn_t511);
xn_arr_s_push(xn_t486, xn_t511);
rt_string *xn_t512 = rt_string_from_c("else");
xn_root_add(xn_t512);
xn_arr_s_push(xn_t486, xn_t512);
rt_string *xn_t513 = rt_string_from_c("while");
xn_root_add(xn_t513);
xn_arr_s_push(xn_t486, xn_t513);
rt_string *xn_t514 = rt_string_from_c("do");
xn_root_add(xn_t514);
xn_arr_s_push(xn_t486, xn_t514);
rt_string *xn_t515 = rt_string_from_c("for");
xn_root_add(xn_t515);
xn_arr_s_push(xn_t486, xn_t515);
rt_string *xn_t516 = rt_string_from_c("switch");
xn_root_add(xn_t516);
xn_arr_s_push(xn_t486, xn_t516);
rt_string *xn_t517 = rt_string_from_c("case");
xn_root_add(xn_t517);
xn_arr_s_push(xn_t486, xn_t517);
rt_string *xn_t518 = rt_string_from_c("default");
xn_root_add(xn_t518);
xn_arr_s_push(xn_t486, xn_t518);
rt_string *xn_t519 = rt_string_from_c("break");
xn_root_add(xn_t519);
xn_arr_s_push(xn_t486, xn_t519);
rt_string *xn_t520 = rt_string_from_c("continue");
xn_root_add(xn_t520);
xn_arr_s_push(xn_t486, xn_t520);
rt_string *xn_t521 = rt_string_from_c("throw");
xn_root_add(xn_t521);
xn_arr_s_push(xn_t486, xn_t521);
rt_string *xn_t522 = rt_string_from_c("try");
xn_root_add(xn_t522);
xn_arr_s_push(xn_t486, xn_t522);
rt_string *xn_t523 = rt_string_from_c("return");
xn_root_add(xn_t523);
xn_arr_s_push(xn_t486, xn_t523);
rt_string *xn_t524 = rt_string_from_c("goto");
xn_root_add(xn_t524);
xn_arr_s_push(xn_t486, xn_t524);
rt_string *xn_t525 = rt_string_from_c("defer");
xn_root_add(xn_t525);
xn_arr_s_push(xn_t486, xn_t525);
rt_string *xn_t526 = rt_string_from_c("errdefer");
xn_root_add(xn_t526);
xn_arr_s_push(xn_t486, xn_t526);
rt_string *xn_t527 = rt_string_from_c("is");
xn_root_add(xn_t527);
xn_arr_s_push(xn_t486, xn_t527);
xn_arr_s * ks = xn_t486;
xn_root_add(ks);
xn_root_add(ks);
xn_gc_safepoint();
#line 324 "impl/lib/b2/xparser.x"
rt_string *xn_t528 = rt_retain(xn_p_w);
xn_root_add(xn_t528);
xn_root_add(xn_t528);
int xn_t529 = xn_inList(ks, xn_t528);
    {
xn_root_restore(xn_t485);
    }

return xn_t529;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static int64_t xn_Cls_Lexer_scanDigits(xn_Cls_Lexer *self, int64_t xn_p_base) {
size_t xn_t530 = xn_root_mark();
xn_root_add(self);
#line 328 "impl/lib/b2/xparser.x"
int64_t n = 0;
#line 329 "impl/lib/b2/xparser.x"
    while (((!(xn_Cls_Lexer_eof(self))))) {
    size_t xn_t531 = xn_root_mark();
    #line 330 "impl/lib/b2/xparser.x"
    int64_t x = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
    #line 331 "impl/lib/b2/xparser.x"
        if (((x == 95))) {
            size_t xn_t532 = xn_root_mark();
            #line 332 "impl/lib/b2/xparser.x"
                if (((!(xn_Cls_Lexer_isDigit(self, xn_Cls_Lexer_b(self, (self->pos + 1))))))) {
                    size_t xn_t533 = xn_root_mark();
                    #line 333 "impl/lib/b2/xparser.x"
                    rt_string *xn_t534 = rt_string_from_c("LEX-104");
xn_root_add(xn_t534);
    xn_root_add(xn_t534);
            xn_root_add(xn_t534);
                    xn_root_add(xn_t534);
                    rt_string *xn_t535 = rt_string_from_c("下划线位置错误");
xn_root_add(xn_t535);
    xn_root_add(xn_t535);
            xn_root_add(xn_t535);
                    xn_root_add(xn_t535);
                    xn_Cls_Lexer_err(self, xn_t534, self->line, self->col, xn_t535);
                        {
                        xn_root_restore(xn_t533);
                        }

                }
            #line 335 "impl/lib/b2/xparser.x"
            xn_Cls_Lexer_adv(self);
            #line 336 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t532);
            xn_root_restore(xn_t531);
            continue;
                {
                xn_root_restore(xn_t532);
                }

        }
    #line 338 "impl/lib/b2/xparser.x"
    int ok = 0;
    #line 339 "impl/lib/b2/xparser.x"
        if (((xn_p_base == 16))) {
            size_t xn_t536 = xn_root_mark();
            #line 339 "impl/lib/b2/xparser.x"
            ok = xn_Cls_Lexer_isHex(self, x);
                {
                xn_root_restore(xn_t536);
                }

        } else {
                if (((xn_p_base == 2))) {
                    size_t xn_t538 = xn_root_mark();
                    #line 340 "impl/lib/b2/xparser.x"
                    ok = ((x == 48) || (x == 49));
                        {
                        xn_root_restore(xn_t538);
                        }

                } else {
                        if (((xn_p_base == 8))) {
                            size_t xn_t540 = xn_root_mark();
                            #line 341 "impl/lib/b2/xparser.x"
                            ok = ((x >= 48) && (x <= 55));
                                {
                                xn_root_restore(xn_t540);
                                }

                        } else {
                            size_t xn_t541 = xn_root_mark();
                            #line 342 "impl/lib/b2/xparser.x"
                            ok = xn_Cls_Lexer_isDigit(self, x);
                                {
                                xn_root_restore(xn_t541);
                                }

                        }
                }
        }
    #line 343 "impl/lib/b2/xparser.x"
        if (((!(ok)))) {
            size_t xn_t542 = xn_root_mark();
            #line 343 "impl/lib/b2/xparser.x"
            int64_t xn_t543 = n;
                {
            xn_root_restore(xn_t542);
                }
                {
            xn_root_restore(xn_t531);
                }
                {
            xn_root_restore(xn_t530);
                }

            return xn_t543;

        }
    #line 344 "impl/lib/b2/xparser.x"
    n = (n + 1);
    #line 345 "impl/lib/b2/xparser.x"
    xn_Cls_Lexer_adv(self);
        {
        xn_root_restore(xn_t531);
        }

    xn_gc_safepoint();
    }
#line 347 "impl/lib/b2/xparser.x"
int64_t xn_t544 = n;
    {
xn_root_restore(xn_t530);
    }

return xn_t544;
    return (int64_t)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Tok * xn_Cls_Lexer_scanNumber(xn_Cls_Lexer *self, int64_t xn_p_l, int64_t xn_p_c) {
size_t xn_t545 = xn_root_mark();
xn_root_add(self);
#line 351 "impl/lib/b2/xparser.x"
int64_t start = self->pos;
#line 352 "impl/lib/b2/xparser.x"
int64_t base = 10;
#line 353 "impl/lib/b2/xparser.x"
int64_t save = self->pos;
#line 354 "impl/lib/b2/xparser.x"
int64_t saveL = self->line;
#line 355 "impl/lib/b2/xparser.x"
int64_t saveC = self->col;
#line 356 "impl/lib/b2/xparser.x"
    if ((((xn_Cls_Lexer_b(self, self->pos) == 48)) && (((xn_Cls_Lexer_b(self, (self->pos + 1)) == 120) || (xn_Cls_Lexer_b(self, (self->pos + 1)) == 88))))) {
        size_t xn_t546 = xn_root_mark();
        #line 357 "impl/lib/b2/xparser.x"
        base = 16;
        #line 358 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 359 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 360 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_scanDigits(self, 16);
            {
            xn_root_restore(xn_t546);
            }

    } else {
            if ((((xn_Cls_Lexer_b(self, self->pos) == 48)) && (((xn_Cls_Lexer_b(self, (self->pos + 1)) == 98) || (xn_Cls_Lexer_b(self, (self->pos + 1)) == 66))))) {
                size_t xn_t548 = xn_root_mark();
                #line 362 "impl/lib/b2/xparser.x"
                base = 2;
                #line 363 "impl/lib/b2/xparser.x"
                xn_Cls_Lexer_adv(self);
                #line 364 "impl/lib/b2/xparser.x"
                xn_Cls_Lexer_adv(self);
                #line 365 "impl/lib/b2/xparser.x"
                xn_Cls_Lexer_scanDigits(self, 2);
                    {
                    xn_root_restore(xn_t548);
                    }

            } else {
                    if ((((xn_Cls_Lexer_b(self, self->pos) == 48)) && (((xn_Cls_Lexer_b(self, (self->pos + 1)) == 111) || (xn_Cls_Lexer_b(self, (self->pos + 1)) == 79))))) {
                        size_t xn_t550 = xn_root_mark();
                        #line 367 "impl/lib/b2/xparser.x"
                        base = 8;
                        #line 368 "impl/lib/b2/xparser.x"
                        xn_Cls_Lexer_adv(self);
                        #line 369 "impl/lib/b2/xparser.x"
                        xn_Cls_Lexer_adv(self);
                        #line 370 "impl/lib/b2/xparser.x"
                        xn_Cls_Lexer_scanDigits(self, 8);
                            {
                            xn_root_restore(xn_t550);
                            }

                    } else {
                        size_t xn_t551 = xn_root_mark();
                        #line 372 "impl/lib/b2/xparser.x"
                        xn_Cls_Lexer_scanDigits(self, 10);
                            {
                            xn_root_restore(xn_t551);
                            }

                    }
            }
    }
#line 374 "impl/lib/b2/xparser.x"
    if (((base == 10))) {
        size_t xn_t552 = xn_root_mark();
        #line 375 "impl/lib/b2/xparser.x"
            if ((((xn_Cls_Lexer_b(self, self->pos) == 46)) && (xn_Cls_Lexer_isDigit(self, xn_Cls_Lexer_b(self, (self->pos + 1)))))) {
                size_t xn_t553 = xn_root_mark();
                #line 376 "impl/lib/b2/xparser.x"
                xn_Cls_Lexer_adv(self);
                #line 377 "impl/lib/b2/xparser.x"
                xn_Cls_Lexer_scanDigits(self, 10);
                #line 378 "impl/lib/b2/xparser.x"
                    if ((((xn_Cls_Lexer_b(self, self->pos) == 101)) || ((xn_Cls_Lexer_b(self, self->pos) == 69)))) {
                        size_t xn_t554 = xn_root_mark();
                        #line 379 "impl/lib/b2/xparser.x"
                            if (((xn_Cls_Lexer_isDigit(self, xn_Cls_Lexer_b(self, (self->pos + 1)))) || ((((xn_Cls_Lexer_b(self, (self->pos + 1)) == 43) || (xn_Cls_Lexer_b(self, (self->pos + 1)) == 45)) && xn_Cls_Lexer_isDigit(self, xn_Cls_Lexer_b(self, (self->pos + 2))))))) {
                                size_t xn_t555 = xn_root_mark();
                                #line 381 "impl/lib/b2/xparser.x"
                                xn_Cls_Lexer_adv(self);
                                #line 382 "impl/lib/b2/xparser.x"
                                    if ((((xn_Cls_Lexer_b(self, self->pos) == 43)) || ((xn_Cls_Lexer_b(self, self->pos) == 45)))) {
                                        size_t xn_t556 = xn_root_mark();
                                        #line 382 "impl/lib/b2/xparser.x"
                                        xn_Cls_Lexer_adv(self);
                                            {
                                            xn_root_restore(xn_t556);
                                            }

                                    }
                                #line 383 "impl/lib/b2/xparser.x"
                                xn_Cls_Lexer_scanDigits(self, 10);
                                    {
                                    xn_root_restore(xn_t555);
                                    }

                            }
                            {
                            xn_root_restore(xn_t554);
                            }

                    }
                #line 386 "impl/lib/b2/xparser.x"
                rt_string *sf = xn_Cls_Lexer_scanSuffix(self);
xn_root_add(sf);
        xn_root_add(sf);
                xn_root_add(sf);
                xn_root_add(sf);
                xn_gc_safepoint();
                #line 387 "impl/lib/b2/xparser.x"
                rt_string *xn_t558 = xn_Cls_Lexer_piece(self, start, self->pos);
xn_root_add(xn_t558);
        xn_root_add(xn_t558);
                xn_root_add(xn_t558);
                xn_Cls_Tok * t = xn_Cls_Lexer_mk(self, 6, xn_t558, xn_p_l, xn_p_c);
xn_root_add(t);
        xn_root_add(t);
                xn_root_add(t);
                xn_root_add(t);
                xn_gc_safepoint();
                #line 388 "impl/lib/b2/xparser.x"
                t->base = 0;
                #line 389 "impl/lib/b2/xparser.x"
                rt_string *xn_t559 = rt_retain(sf);
xn_root_add(xn_t559);
        xn_root_add(xn_t559);
                xn_root_add(xn_t559);
                rt_release(t->suffix);
                t->suffix = xn_t559;
                #line 390 "impl/lib/b2/xparser.x"
                rt_string *xn_t560 = rt_retain(sf);
xn_root_add(xn_t560);
        xn_root_add(xn_t560);
                xn_root_add(xn_t560);
                rt_string *xn_t561 = rt_string_from_c("F");
xn_root_add(xn_t561);
        xn_root_add(xn_t561);
                xn_root_add(xn_t561);
                t->hasSuffixF = (int64_t)((int)(xn_str_eq(xn_t560, xn_t561)));
                #line 391 "impl/lib/b2/xparser.x"
                    {
                rt_release(sf);
                    }
                    {
                xn_root_restore(xn_t553);
                    }
                    {
                xn_root_restore(xn_t552);
                    }
                    {
                xn_root_restore(xn_t545);
                    }

                return t;

            }
            {
            xn_root_restore(xn_t552);
            }

    }
#line 394 "impl/lib/b2/xparser.x"
rt_string *sf = xn_Cls_Lexer_scanSuffix(self);
xn_root_add(sf);
xn_root_add(sf);
xn_gc_safepoint();
#line 395 "impl/lib/b2/xparser.x"
rt_string *xn_t563 = xn_Cls_Lexer_piece(self, start, self->pos);
xn_root_add(xn_t563);
xn_Cls_Tok * t = xn_Cls_Lexer_mk(self, 5, xn_t563, xn_p_l, xn_p_c);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 396 "impl/lib/b2/xparser.x"
t->base = base;
#line 397 "impl/lib/b2/xparser.x"
rt_string *xn_t564 = rt_retain(sf);
xn_root_add(xn_t564);
rt_release(t->suffix);
t->suffix = xn_t564;
#line 398 "impl/lib/b2/xparser.x"
    {
rt_release(sf);
    }
    {
xn_root_restore(xn_t545);
    }

return t;
    return (xn_Cls_Tok *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Lexer_scanSuffix(xn_Cls_Lexer *self) {
size_t xn_t565 = xn_root_mark();
xn_root_add(self);
#line 402 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Lexer_eof(self))) {
        size_t xn_t566 = xn_root_mark();
        #line 402 "impl/lib/b2/xparser.x"
        rt_string *xn_t567 = rt_string_from_c("");
xn_root_add(xn_t567);
        xn_root_add(xn_t567);
        xn_root_add(xn_t567);
            {
        xn_root_restore(xn_t566);
            }
            {
        xn_root_restore(xn_t565);
            }

        return xn_t567;

    }
#line 403 "impl/lib/b2/xparser.x"
int64_t x = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
#line 404 "impl/lib/b2/xparser.x"
    if (((x == 70))) {
        size_t xn_t568 = xn_root_mark();
        #line 405 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 406 "impl/lib/b2/xparser.x"
        rt_string *xn_t569 = rt_string_from_c("F");
xn_root_add(xn_t569);
        xn_root_add(xn_t569);
        xn_root_add(xn_t569);
            {
        xn_root_restore(xn_t568);
            }
            {
        xn_root_restore(xn_t565);
            }

        return xn_t569;

    }
#line 408 "impl/lib/b2/xparser.x"
    if (((x == 76))) {
        size_t xn_t570 = xn_root_mark();
        #line 409 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 410 "impl/lib/b2/xparser.x"
        rt_string *xn_t571 = rt_string_from_c("L");
xn_root_add(xn_t571);
        xn_root_add(xn_t571);
        xn_root_add(xn_t571);
            {
        xn_root_restore(xn_t570);
            }
            {
        xn_root_restore(xn_t565);
            }

        return xn_t571;

    }
#line 412 "impl/lib/b2/xparser.x"
    if (((x == 85))) {
        size_t xn_t572 = xn_root_mark();
        #line 413 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 414 "impl/lib/b2/xparser.x"
            if (((xn_Cls_Lexer_b(self, self->pos) == 76))) {
                size_t xn_t573 = xn_root_mark();
                #line 414 "impl/lib/b2/xparser.x"
                xn_Cls_Lexer_adv(self);
                #line 414 "impl/lib/b2/xparser.x"
                rt_string *xn_t574 = rt_string_from_c("UL");
xn_root_add(xn_t574);
        xn_root_add(xn_t574);
                xn_root_add(xn_t574);
                xn_root_add(xn_t574);
                    {
                xn_root_restore(xn_t573);
                    }
                    {
                xn_root_restore(xn_t572);
                    }
                    {
                xn_root_restore(xn_t565);
                    }

                return xn_t574;

            }
        #line 415 "impl/lib/b2/xparser.x"
        rt_string *xn_t575 = rt_string_from_c("U");
xn_root_add(xn_t575);
        xn_root_add(xn_t575);
        xn_root_add(xn_t575);
            {
        xn_root_restore(xn_t572);
            }
            {
        xn_root_restore(xn_t565);
            }

        return xn_t575;

    }
#line 417 "impl/lib/b2/xparser.x"
rt_string *xn_t576 = rt_string_from_c("");
xn_root_add(xn_t576);
xn_root_add(xn_t576);
    {
xn_root_restore(xn_t565);
    }

return xn_t576;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Tok * xn_Cls_Lexer_scanChar(xn_Cls_Lexer *self, int64_t xn_p_l, int64_t xn_p_c) {
size_t xn_t577 = xn_root_mark();
xn_root_add(self);
#line 421 "impl/lib/b2/xparser.x"
xn_Cls_Lexer_adv(self);
#line 422 "impl/lib/b2/xparser.x"
int64_t val = 0;
#line 423 "impl/lib/b2/xparser.x"
int64_t count = 0;
#line 424 "impl/lib/b2/xparser.x"
    if ((((!(xn_Cls_Lexer_eof(self)))) && ((((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))) == 39)))) {
        size_t xn_t578 = xn_root_mark();
        #line 425 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 426 "impl/lib/b2/xparser.x"
        rt_string *xn_t579 = rt_string_from_c("LEX-106");
xn_root_add(xn_t579);
        xn_root_add(xn_t579);
        rt_string *xn_t580 = rt_string_from_c("空字符字面量");
xn_root_add(xn_t580);
        xn_root_add(xn_t580);
        xn_Cls_Lexer_err(self, xn_t579, xn_p_l, xn_p_c, xn_t580);
        #line 427 "impl/lib/b2/xparser.x"
        rt_string *xn_t581 = rt_string_from_c("");
xn_root_add(xn_t581);
        xn_root_add(xn_t581);
        xn_root_add(xn_t581);
            {
        xn_root_restore(xn_t578);
            }
            {
        xn_root_restore(xn_t577);
            }

        return xn_Cls_Lexer_mk(self, 7, xn_t581, xn_p_l, xn_p_c);

    }
#line 429 "impl/lib/b2/xparser.x"
    if (((xn_Cls_Lexer_eof(self)) || ((((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))) == 10)))) {
        size_t xn_t582 = xn_root_mark();
        #line 430 "impl/lib/b2/xparser.x"
        rt_string *xn_t583 = rt_string_from_c("LEX-106");
xn_root_add(xn_t583);
        xn_root_add(xn_t583);
        rt_string *xn_t584 = rt_string_from_c("字符字面量跨行或为空");
xn_root_add(xn_t584);
        xn_root_add(xn_t584);
        xn_Cls_Lexer_err(self, xn_t583, xn_p_l, xn_p_c, xn_t584);
        #line 431 "impl/lib/b2/xparser.x"
        rt_string *xn_t585 = rt_string_from_c("");
xn_root_add(xn_t585);
        xn_root_add(xn_t585);
        xn_root_add(xn_t585);
            {
        xn_root_restore(xn_t582);
            }
            {
        xn_root_restore(xn_t577);
            }

        return xn_Cls_Lexer_mk(self, 7, xn_t585, xn_p_l, xn_p_c);

    }
#line 433 "impl/lib/b2/xparser.x"
    if (((((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))) == 92))) {
        size_t xn_t586 = xn_root_mark();
        #line 434 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 435 "impl/lib/b2/xparser.x"
            if (((!(xn_Cls_Lexer_eof(self))))) {
                size_t xn_t587 = xn_root_mark();
                #line 436 "impl/lib/b2/xparser.x"
                int64_t e = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
                #line 437 "impl/lib/b2/xparser.x"
                xn_Cls_Lexer_adv(self);
                #line 438 "impl/lib/b2/xparser.x"
                    if (((e == 110))) {
                        size_t xn_t588 = xn_root_mark();
                        #line 438 "impl/lib/b2/xparser.x"
                        val = 10;
                            {
                            xn_root_restore(xn_t588);
                            }

                    } else {
                            if (((e == 116))) {
                                size_t xn_t590 = xn_root_mark();
                                #line 438 "impl/lib/b2/xparser.x"
                                val = 9;
                                    {
                                    xn_root_restore(xn_t590);
                                    }

                            } else {
                                    if (((e == 114))) {
                                        size_t xn_t592 = xn_root_mark();
                                        #line 439 "impl/lib/b2/xparser.x"
                                        val = 13;
                                            {
                                            xn_root_restore(xn_t592);
                                            }

                                    } else {
                                            if (((e == 92))) {
                                                size_t xn_t594 = xn_root_mark();
                                                #line 439 "impl/lib/b2/xparser.x"
                                                val = 92;
                                                    {
                                                    xn_root_restore(xn_t594);
                                                    }

                                            } else {
                                                    if (((e == 39))) {
                                                        size_t xn_t596 = xn_root_mark();
                                                        #line 440 "impl/lib/b2/xparser.x"
                                                        val = 39;
                                                            {
                                                            xn_root_restore(xn_t596);
                                                            }

                                                    } else {
                                                            if (((e == 34))) {
                                                                size_t xn_t598 = xn_root_mark();
                                                                #line 440 "impl/lib/b2/xparser.x"
                                                                val = 34;
                                                                    {
                                                                    xn_root_restore(xn_t598);
                                                                    }

                                                            } else {
                                                                    if (((e == 48))) {
                                                                        size_t xn_t600 = xn_root_mark();
                                                                        #line 441 "impl/lib/b2/xparser.x"
                                                                        val = 0;
                                                                            {
                                                                            xn_root_restore(xn_t600);
                                                                            }

                                                                    } else {
                                                                        size_t xn_t601 = xn_root_mark();
                                                                        #line 441 "impl/lib/b2/xparser.x"
                                                                        rt_string *xn_t602 = rt_string_from_c("LEX-103");
xn_root_add(xn_t602);
        xn_root_add(xn_t602);
                xn_root_add(xn_t602);
                        xn_root_add(xn_t602);
                                xn_root_add(xn_t602);
                                        xn_root_add(xn_t602);
                                                xn_root_add(xn_t602);
                                                        xn_root_add(xn_t602);
                                                                xn_root_add(xn_t602);
                                                                        xn_root_add(xn_t602);
                                                                        rt_string *xn_t603 = rt_string_from_c("未知转义");
xn_root_add(xn_t603);
        xn_root_add(xn_t603);
                xn_root_add(xn_t603);
                        xn_root_add(xn_t603);
                                xn_root_add(xn_t603);
                                        xn_root_add(xn_t603);
                                                xn_root_add(xn_t603);
                                                        xn_root_add(xn_t603);
                                                                xn_root_add(xn_t603);
                                                                        xn_root_add(xn_t603);
                                                                        xn_Cls_Lexer_err(self, xn_t602, xn_p_l, xn_p_c, xn_t603);
                                                                        #line 441 "impl/lib/b2/xparser.x"
                                                                        val = e;
                                                                            {
                                                                            xn_root_restore(xn_t601);
                                                                            }

                                                                    }
                                                            }
                                                    }
                                            }
                                    }
                            }
                    }
                #line 442 "impl/lib/b2/xparser.x"
                count = 1;
                    {
                    xn_root_restore(xn_t587);
                    }

            }
            {
            xn_root_restore(xn_t586);
            }

    } else {
        size_t xn_t604 = xn_root_mark();
        #line 445 "impl/lib/b2/xparser.x"
        val = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
        #line 446 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 447 "impl/lib/b2/xparser.x"
        count = 1;
            {
            xn_root_restore(xn_t604);
            }

    }
#line 449 "impl/lib/b2/xparser.x"
    if ((((!(xn_Cls_Lexer_eof(self)))) && ((((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))) != 39)))) {
        size_t xn_t605 = xn_root_mark();
        #line 450 "impl/lib/b2/xparser.x"
        count = 2;
        #line 451 "impl/lib/b2/xparser.x"
            while (((((!(xn_Cls_Lexer_eof(self)))) && ((((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))) != 39))) && ((((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))) != 10)))) {
            size_t xn_t606 = xn_root_mark();
            #line 452 "impl/lib/b2/xparser.x"
            xn_Cls_Lexer_adv(self);
                {
                xn_root_restore(xn_t606);
                }

            xn_gc_safepoint();
            }
            {
            xn_root_restore(xn_t605);
            }

    }
#line 455 "impl/lib/b2/xparser.x"
    if ((((!(xn_Cls_Lexer_eof(self)))) && ((((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos))) == 39)))) {
        size_t xn_t607 = xn_root_mark();
        #line 456 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
            {
            xn_root_restore(xn_t607);
            }

    } else {
        size_t xn_t608 = xn_root_mark();
        #line 458 "impl/lib/b2/xparser.x"
        rt_string *xn_t609 = rt_string_from_c("LEX-106");
xn_root_add(xn_t609);
        xn_root_add(xn_t609);
        rt_string *xn_t610 = rt_string_from_c("字符字面量未闭合");
xn_root_add(xn_t610);
        xn_root_add(xn_t610);
        xn_Cls_Lexer_err(self, xn_t609, xn_p_l, xn_p_c, xn_t610);
            {
            xn_root_restore(xn_t608);
            }

    }
#line 460 "impl/lib/b2/xparser.x"
    if ((((count != 1)) && ((count != 0)))) {
        size_t xn_t611 = xn_root_mark();
        #line 461 "impl/lib/b2/xparser.x"
        rt_string *xn_t612 = rt_string_from_c("LEX-106");
xn_root_add(xn_t612);
        xn_root_add(xn_t612);
        rt_string *xn_t613 = rt_string_from_c("字符字面量必须恰好一个码点");
xn_root_add(xn_t613);
        xn_root_add(xn_t613);
        xn_Cls_Lexer_err(self, xn_t612, xn_p_l, xn_p_c, xn_t613);
            {
            xn_root_restore(xn_t611);
            }

    }
#line 463 "impl/lib/b2/xparser.x"
rt_string *xn_t614 = rt_string_from_c("");
xn_root_add(xn_t614);
xn_Cls_Tok * t = xn_Cls_Lexer_mk(self, 7, xn_t614, xn_p_l, xn_p_c);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 464 "impl/lib/b2/xparser.x"
t->ch = val;
#line 465 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t577);
    }

return t;
    return (xn_Cls_Tok *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Tok * xn_Cls_Lexer_scanString(xn_Cls_Lexer *self, int64_t xn_p_l, int64_t xn_p_c, int xn_p_raw, int xn_p_multiline, int xn_p_interp) {
size_t xn_t615 = xn_root_mark();
xn_root_add(self);
#line 469 "impl/lib/b2/xparser.x"
    if (((xn_p_raw) || (xn_p_interp))) {
        size_t xn_t616 = xn_root_mark();
        #line 469 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
            {
            xn_root_restore(xn_t616);
            }

    }
#line 470 "impl/lib/b2/xparser.x"
xn_Cls_Lexer_adv(self);
#line 471 "impl/lib/b2/xparser.x"
    if ((xn_p_multiline)) {
        size_t xn_t617 = xn_root_mark();
        #line 471 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
        #line 471 "impl/lib/b2/xparser.x"
        xn_Cls_Lexer_adv(self);
            {
            xn_root_restore(xn_t617);
            }

    }
#line 472 "impl/lib/b2/xparser.x"
rt_string *val = rt_string_from_c("");
xn_root_add(val);
xn_root_add(val);
xn_gc_safepoint();
#line 473 "impl/lib/b2/xparser.x"
rt_string *joined = rt_string_from_c("");
xn_root_add(joined);
xn_root_add(joined);
xn_gc_safepoint();
#line 474 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t620 = xn_arr_s_new(0);
xn_root_add(xn_t620);
xn_arr_s * segs = xn_t620;
xn_root_add(segs);
xn_root_add(segs);
xn_gc_safepoint();
#line 475 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t621 = xn_arr_s_new(0);
xn_root_add(xn_t621);
xn_arr_s * interps = xn_t621;
xn_root_add(interps);
xn_root_add(interps);
xn_gc_safepoint();
#line 476 "impl/lib/b2/xparser.x"
int closed = 0;
#line 477 "impl/lib/b2/xparser.x"
    while (((!(xn_Cls_Lexer_eof(self))))) {
    size_t xn_t622 = xn_root_mark();
    #line 478 "impl/lib/b2/xparser.x"
    int64_t x = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
    #line 479 "impl/lib/b2/xparser.x"
        if ((((!(xn_p_multiline))) && ((x == 10)))) {
            size_t xn_t623 = xn_root_mark();
            #line 480 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t623);
            xn_root_restore(xn_t622);
            break;
                {
                xn_root_restore(xn_t623);
                }

        }
    #line 482 "impl/lib/b2/xparser.x"
        if (((xn_p_interp) && ((x == 123)))) {
            size_t xn_t624 = xn_root_mark();
            #line 483 "impl/lib/b2/xparser.x"
                if (((xn_Cls_Lexer_b(self, (self->pos + 1)) == 123))) {
                    size_t xn_t625 = xn_root_mark();
                    #line 484 "impl/lib/b2/xparser.x"
                    xn_Cls_Lexer_adv(self);
                    #line 484 "impl/lib/b2/xparser.x"
                    xn_Cls_Lexer_adv(self);
                    #line 485 "impl/lib/b2/xparser.x"
                    rt_string *xn_t626 = rt_retain(val);
xn_root_add(xn_t626);
    xn_root_add(xn_t626);
            xn_root_add(xn_t626);
                    xn_root_add(xn_t626);
                    rt_string *xn_t627 = rt_string_from_c("{");
xn_root_add(xn_t627);
    xn_root_add(xn_t627);
            xn_root_add(xn_t627);
                    xn_root_add(xn_t627);
                    rt_string *xn_t628 = xn_concat(xn_t626, xn_t627);
xn_root_add(xn_t628);
    xn_root_add(xn_t628);
            xn_root_add(xn_t628);
                    xn_root_add(xn_t628);
                    xn_root_release(val);
                    rt_release(val);
                    val = xn_t628;
                    xn_root_hold(val);
                    xn_gc_safepoint();
                    #line 486 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t625);
                    xn_root_restore(xn_t624);
                    xn_root_restore(xn_t622);
                    continue;
                        {
                        xn_root_restore(xn_t625);
                        }

                }
            #line 488 "impl/lib/b2/xparser.x"
            rt_string *xn_t629 = rt_retain(val);
xn_root_add(xn_t629);
    xn_root_add(xn_t629);
            xn_root_add(xn_t629);
            xn_arr_s_push(segs, xn_t629);
            #line 489 "impl/lib/b2/xparser.x"
            rt_string *xn_t630 = rt_retain(joined);
xn_root_add(xn_t630);
    xn_root_add(xn_t630);
            xn_root_add(xn_t630);
            rt_string *xn_t631 = rt_retain(val);
xn_root_add(xn_t631);
    xn_root_add(xn_t631);
            xn_root_add(xn_t631);
            rt_string *xn_t632 = xn_concat(xn_t630, xn_t631);
xn_root_add(xn_t632);
    xn_root_add(xn_t632);
            xn_root_add(xn_t632);
            xn_root_release(joined);
            rt_release(joined);
            joined = xn_t632;
            xn_root_hold(joined);
            xn_gc_safepoint();
            #line 490 "impl/lib/b2/xparser.x"
            rt_string *xn_t633 = rt_string_from_c("");
xn_root_add(xn_t633);
    xn_root_add(xn_t633);
            xn_root_add(xn_t633);
            xn_root_release(val);
            rt_release(val);
            val = xn_t633;
            xn_root_hold(val);
            xn_gc_safepoint();
            #line 491 "impl/lib/b2/xparser.x"
            xn_Cls_Lexer_adv(self);
            #line 492 "impl/lib/b2/xparser.x"
            rt_string *expr = rt_string_from_c("");
xn_root_add(expr);
    xn_root_add(expr);
            xn_root_add(expr);
            xn_root_add(expr);
            xn_gc_safepoint();
            #line 493 "impl/lib/b2/xparser.x"
            int64_t depth = 1;
            #line 494 "impl/lib/b2/xparser.x"
                while ((((!(xn_Cls_Lexer_eof(self)))) && ((depth > 0)))) {
                size_t xn_t635 = xn_root_mark();
                #line 495 "impl/lib/b2/xparser.x"
                int64_t y = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
                #line 496 "impl/lib/b2/xparser.x"
                    if (((y == 123))) {
                        size_t xn_t636 = xn_root_mark();
                        #line 497 "impl/lib/b2/xparser.x"
                        depth = (depth + 1);
                        #line 498 "impl/lib/b2/xparser.x"
                        rt_string *xn_t637 = rt_retain(expr);
xn_root_add(xn_t637);
    xn_root_add(xn_t637);
            xn_root_add(xn_t637);
                xn_root_add(xn_t637);
                        xn_root_add(xn_t637);
                        rt_string *xn_t638 = rt_string_from_c("{");
xn_root_add(xn_t638);
    xn_root_add(xn_t638);
            xn_root_add(xn_t638);
                xn_root_add(xn_t638);
                        xn_root_add(xn_t638);
                        rt_string *xn_t639 = xn_concat(xn_t637, xn_t638);
xn_root_add(xn_t639);
    xn_root_add(xn_t639);
            xn_root_add(xn_t639);
                xn_root_add(xn_t639);
                        xn_root_add(xn_t639);
                        xn_root_release(expr);
                        rt_release(expr);
                        expr = xn_t639;
                        xn_root_hold(expr);
                        xn_gc_safepoint();
                        #line 499 "impl/lib/b2/xparser.x"
                        xn_Cls_Lexer_adv(self);
                            {
                            xn_root_restore(xn_t636);
                            }

                    } else {
                            if (((y == 125))) {
                                size_t xn_t641 = xn_root_mark();
                                #line 501 "impl/lib/b2/xparser.x"
                                depth = (depth - 1);
                                #line 502 "impl/lib/b2/xparser.x"
                                    if (((depth == 0))) {
                                        size_t xn_t642 = xn_root_mark();
                                        #line 503 "impl/lib/b2/xparser.x"
                                        xn_Cls_Lexer_adv(self);
                                            {
                                            xn_root_restore(xn_t642);
                                            }

                                    } else {
                                        size_t xn_t643 = xn_root_mark();
                                        #line 505 "impl/lib/b2/xparser.x"
                                        rt_string *xn_t644 = rt_retain(expr);
xn_root_add(xn_t644);
    xn_root_add(xn_t644);
            xn_root_add(xn_t644);
                xn_root_add(xn_t644);
                        xn_root_add(xn_t644);
                                xn_root_add(xn_t644);
                                        xn_root_add(xn_t644);
                                        rt_string *xn_t645 = rt_string_from_c("}");
xn_root_add(xn_t645);
    xn_root_add(xn_t645);
            xn_root_add(xn_t645);
                xn_root_add(xn_t645);
                        xn_root_add(xn_t645);
                                xn_root_add(xn_t645);
                                        xn_root_add(xn_t645);
                                        rt_string *xn_t646 = xn_concat(xn_t644, xn_t645);
xn_root_add(xn_t646);
    xn_root_add(xn_t646);
            xn_root_add(xn_t646);
                xn_root_add(xn_t646);
                        xn_root_add(xn_t646);
                                xn_root_add(xn_t646);
                                        xn_root_add(xn_t646);
                                        xn_root_release(expr);
                                        rt_release(expr);
                                        expr = xn_t646;
                                        xn_root_hold(expr);
                                        xn_gc_safepoint();
                                        #line 506 "impl/lib/b2/xparser.x"
                                        xn_Cls_Lexer_adv(self);
                                            {
                                            xn_root_restore(xn_t643);
                                            }

                                    }
                                    {
                                    xn_root_restore(xn_t641);
                                    }

                            } else {
                                    if (((y == 34))) {
                                        size_t xn_t648 = xn_root_mark();
                                        #line 509 "impl/lib/b2/xparser.x"
                                        rt_string *xn_t649 = rt_retain(expr);
xn_root_add(xn_t649);
    xn_root_add(xn_t649);
            xn_root_add(xn_t649);
                xn_root_add(xn_t649);
                        xn_root_add(xn_t649);
                                xn_root_add(xn_t649);
                                        xn_root_add(xn_t649);
                                        rt_string *xn_t650 = rt_string_from_c("\"");
xn_root_add(xn_t650);
    xn_root_add(xn_t650);
            xn_root_add(xn_t650);
                xn_root_add(xn_t650);
                        xn_root_add(xn_t650);
                                xn_root_add(xn_t650);
                                        xn_root_add(xn_t650);
                                        rt_string *xn_t651 = xn_concat(xn_t649, xn_t650);
xn_root_add(xn_t651);
    xn_root_add(xn_t651);
            xn_root_add(xn_t651);
                xn_root_add(xn_t651);
                        xn_root_add(xn_t651);
                                xn_root_add(xn_t651);
                                        xn_root_add(xn_t651);
                                        xn_root_release(expr);
                                        rt_release(expr);
                                        expr = xn_t651;
                                        xn_root_hold(expr);
                                        xn_gc_safepoint();
                                        #line 510 "impl/lib/b2/xparser.x"
                                        xn_Cls_Lexer_adv(self);
                                        #line 511 "impl/lib/b2/xparser.x"
                                        int qdone = 0;
                                        #line 512 "impl/lib/b2/xparser.x"
                                            while ((((!(xn_Cls_Lexer_eof(self)))) && ((!(qdone))))) {
                                            size_t xn_t652 = xn_root_mark();
                                            #line 513 "impl/lib/b2/xparser.x"
                                            int64_t z = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
                                            #line 514 "impl/lib/b2/xparser.x"
                                                if (((z == 92))) {
                                                    size_t xn_t653 = xn_root_mark();
                                                    #line 515 "impl/lib/b2/xparser.x"
                                                    rt_string *xn_t654 = rt_retain(expr);
xn_root_add(xn_t654);
    xn_root_add(xn_t654);
            xn_root_add(xn_t654);
                xn_root_add(xn_t654);
                        xn_root_add(xn_t654);
                                xn_root_add(xn_t654);
                                        xn_root_add(xn_t654);
                                            xn_root_add(xn_t654);
                                                    xn_root_add(xn_t654);
                                                    rt_string *xn_t655 = xn_Cls_Lexer_one(self, self->pos);
xn_root_add(xn_t655);
    xn_root_add(xn_t655);
            xn_root_add(xn_t655);
                xn_root_add(xn_t655);
                        xn_root_add(xn_t655);
                                xn_root_add(xn_t655);
                                        xn_root_add(xn_t655);
                                            xn_root_add(xn_t655);
                                                    xn_root_add(xn_t655);
                                                    rt_string *xn_t656 = xn_concat(xn_t654, xn_t655);
xn_root_add(xn_t656);
    xn_root_add(xn_t656);
            xn_root_add(xn_t656);
                xn_root_add(xn_t656);
                        xn_root_add(xn_t656);
                                xn_root_add(xn_t656);
                                        xn_root_add(xn_t656);
                                            xn_root_add(xn_t656);
                                                    xn_root_add(xn_t656);
                                                    xn_root_release(expr);
                                                    rt_release(expr);
                                                    expr = xn_t656;
                                                    xn_root_hold(expr);
                                                    xn_gc_safepoint();
                                                    #line 516 "impl/lib/b2/xparser.x"
                                                    xn_Cls_Lexer_adv(self);
                                                    #line 517 "impl/lib/b2/xparser.x"
                                                        if (((!(xn_Cls_Lexer_eof(self))))) {
                                                            size_t xn_t657 = xn_root_mark();
                                                            #line 518 "impl/lib/b2/xparser.x"
                                                            rt_string *xn_t658 = rt_retain(expr);
xn_root_add(xn_t658);
    xn_root_add(xn_t658);
            xn_root_add(xn_t658);
                xn_root_add(xn_t658);
                        xn_root_add(xn_t658);
                                xn_root_add(xn_t658);
                                        xn_root_add(xn_t658);
                                            xn_root_add(xn_t658);
                                                    xn_root_add(xn_t658);
                                                            xn_root_add(xn_t658);
                                                            rt_string *xn_t659 = xn_Cls_Lexer_one(self, self->pos);
xn_root_add(xn_t659);
    xn_root_add(xn_t659);
            xn_root_add(xn_t659);
                xn_root_add(xn_t659);
                        xn_root_add(xn_t659);
                                xn_root_add(xn_t659);
                                        xn_root_add(xn_t659);
                                            xn_root_add(xn_t659);
                                                    xn_root_add(xn_t659);
                                                            xn_root_add(xn_t659);
                                                            rt_string *xn_t660 = xn_concat(xn_t658, xn_t659);
xn_root_add(xn_t660);
    xn_root_add(xn_t660);
            xn_root_add(xn_t660);
                xn_root_add(xn_t660);
                        xn_root_add(xn_t660);
                                xn_root_add(xn_t660);
                                        xn_root_add(xn_t660);
                                            xn_root_add(xn_t660);
                                                    xn_root_add(xn_t660);
                                                            xn_root_add(xn_t660);
                                                            xn_root_release(expr);
                                                            rt_release(expr);
                                                            expr = xn_t660;
                                                            xn_root_hold(expr);
                                                            xn_gc_safepoint();
                                                            #line 519 "impl/lib/b2/xparser.x"
                                                            xn_Cls_Lexer_adv(self);
                                                                {
                                                                xn_root_restore(xn_t657);
                                                                }

                                                        }
                                                        {
                                                        xn_root_restore(xn_t653);
                                                        }

                                                } else {
                                                    size_t xn_t661 = xn_root_mark();
                                                    #line 522 "impl/lib/b2/xparser.x"
                                                    rt_string *xn_t662 = rt_retain(expr);
xn_root_add(xn_t662);
    xn_root_add(xn_t662);
            xn_root_add(xn_t662);
                xn_root_add(xn_t662);
                        xn_root_add(xn_t662);
                                xn_root_add(xn_t662);
                                        xn_root_add(xn_t662);
                                            xn_root_add(xn_t662);
                                                    xn_root_add(xn_t662);
                                                    rt_string *xn_t663 = xn_Cls_Lexer_one(self, self->pos);
xn_root_add(xn_t663);
    xn_root_add(xn_t663);
            xn_root_add(xn_t663);
                xn_root_add(xn_t663);
                        xn_root_add(xn_t663);
                                xn_root_add(xn_t663);
                                        xn_root_add(xn_t663);
                                            xn_root_add(xn_t663);
                                                    xn_root_add(xn_t663);
                                                    rt_string *xn_t664 = xn_concat(xn_t662, xn_t663);
xn_root_add(xn_t664);
    xn_root_add(xn_t664);
            xn_root_add(xn_t664);
                xn_root_add(xn_t664);
                        xn_root_add(xn_t664);
                                xn_root_add(xn_t664);
                                        xn_root_add(xn_t664);
                                            xn_root_add(xn_t664);
                                                    xn_root_add(xn_t664);
                                                    xn_root_release(expr);
                                                    rt_release(expr);
                                                    expr = xn_t664;
                                                    xn_root_hold(expr);
                                                    xn_gc_safepoint();
                                                    #line 523 "impl/lib/b2/xparser.x"
                                                    xn_Cls_Lexer_adv(self);
                                                    #line 524 "impl/lib/b2/xparser.x"
                                                        if (((z == 34))) {
                                                            size_t xn_t665 = xn_root_mark();
                                                            #line 524 "impl/lib/b2/xparser.x"
                                                            qdone = 1;
                                                                {
                                                                xn_root_restore(xn_t665);
                                                                }

                                                        }
                                                        {
                                                        xn_root_restore(xn_t661);
                                                        }

                                                }
                                                {
                                                xn_root_restore(xn_t652);
                                                }

                                            xn_gc_safepoint();
                                            }
                                            {
                                            xn_root_restore(xn_t648);
                                            }

                                    } else {
                                        size_t xn_t666 = xn_root_mark();
                                        #line 528 "impl/lib/b2/xparser.x"
                                        rt_string *xn_t667 = rt_retain(expr);
xn_root_add(xn_t667);
    xn_root_add(xn_t667);
            xn_root_add(xn_t667);
                xn_root_add(xn_t667);
                        xn_root_add(xn_t667);
                                xn_root_add(xn_t667);
                                        xn_root_add(xn_t667);
                                        rt_string *xn_t668 = xn_Cls_Lexer_one(self, self->pos);
xn_root_add(xn_t668);
    xn_root_add(xn_t668);
            xn_root_add(xn_t668);
                xn_root_add(xn_t668);
                        xn_root_add(xn_t668);
                                xn_root_add(xn_t668);
                                        xn_root_add(xn_t668);
                                        rt_string *xn_t669 = xn_concat(xn_t667, xn_t668);
xn_root_add(xn_t669);
    xn_root_add(xn_t669);
            xn_root_add(xn_t669);
                xn_root_add(xn_t669);
                        xn_root_add(xn_t669);
                                xn_root_add(xn_t669);
                                        xn_root_add(xn_t669);
                                        xn_root_release(expr);
                                        rt_release(expr);
                                        expr = xn_t669;
                                        xn_root_hold(expr);
                                        xn_gc_safepoint();
                                        #line 529 "impl/lib/b2/xparser.x"
                                        xn_Cls_Lexer_adv(self);
                                            {
                                            xn_root_restore(xn_t666);
                                            }

                                    }
                            }
                    }
                    {
                    xn_root_restore(xn_t635);
                    }

                xn_gc_safepoint();
                }
            #line 532 "impl/lib/b2/xparser.x"
            rt_string *xn_t670 = rt_retain(expr);
xn_root_add(xn_t670);
    xn_root_add(xn_t670);
            xn_root_add(xn_t670);
            xn_arr_s_push(interps, xn_t670);
            #line 533 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t624);
            xn_root_restore(xn_t622);
            continue;
            xn_root_release(expr);
                {
                rt_release(expr);
                }
                {
                xn_root_restore(xn_t624);
                }

        }
    #line 535 "impl/lib/b2/xparser.x"
        if (((x == 34))) {
            size_t xn_t671 = xn_root_mark();
            #line 536 "impl/lib/b2/xparser.x"
                if ((xn_p_multiline)) {
                    size_t xn_t672 = xn_root_mark();
                    #line 537 "impl/lib/b2/xparser.x"
                        if ((((xn_Cls_Lexer_b(self, (self->pos + 1)) == 34)) && ((xn_Cls_Lexer_b(self, (self->pos + 2)) == 34)))) {
                            size_t xn_t673 = xn_root_mark();
                            #line 538 "impl/lib/b2/xparser.x"
                            xn_Cls_Lexer_adv(self);
                            #line 538 "impl/lib/b2/xparser.x"
                            xn_Cls_Lexer_adv(self);
                            #line 538 "impl/lib/b2/xparser.x"
                            xn_Cls_Lexer_adv(self);
                            #line 539 "impl/lib/b2/xparser.x"
                            closed = 1;
                            #line 540 "impl/lib/b2/xparser.x"
                            xn_root_restore(xn_t673);
                            xn_root_restore(xn_t672);
                            xn_root_restore(xn_t671);
                            xn_root_restore(xn_t622);
                            break;
                                {
                                xn_root_restore(xn_t673);
                                }

                        }
                    #line 542 "impl/lib/b2/xparser.x"
                    rt_string *xn_t674 = rt_retain(val);
xn_root_add(xn_t674);
    xn_root_add(xn_t674);
            xn_root_add(xn_t674);
                    xn_root_add(xn_t674);
                    rt_string *xn_t675 = xn_Cls_Lexer_one(self, self->pos);
xn_root_add(xn_t675);
    xn_root_add(xn_t675);
            xn_root_add(xn_t675);
                    xn_root_add(xn_t675);
                    rt_string *xn_t676 = xn_concat(xn_t674, xn_t675);
xn_root_add(xn_t676);
    xn_root_add(xn_t676);
            xn_root_add(xn_t676);
                    xn_root_add(xn_t676);
                    xn_root_release(val);
                    rt_release(val);
                    val = xn_t676;
                    xn_root_hold(val);
                    xn_gc_safepoint();
                    #line 543 "impl/lib/b2/xparser.x"
                    xn_Cls_Lexer_adv(self);
                        {
                        xn_root_restore(xn_t672);
                        }

                } else {
                    size_t xn_t677 = xn_root_mark();
                    #line 545 "impl/lib/b2/xparser.x"
                    xn_Cls_Lexer_adv(self);
                    #line 546 "impl/lib/b2/xparser.x"
                    closed = 1;
                    #line 547 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t677);
                    xn_root_restore(xn_t671);
                    xn_root_restore(xn_t622);
                    break;
                        {
                        xn_root_restore(xn_t677);
                        }

                }
                {
                xn_root_restore(xn_t671);
                }

        } else {
                if ((((!(xn_p_raw))) && ((x == 92)))) {
                    size_t xn_t679 = xn_root_mark();
                    #line 550 "impl/lib/b2/xparser.x"
                    int64_t el = self->line;
                    #line 551 "impl/lib/b2/xparser.x"
                    int64_t ec = self->col;
                    #line 552 "impl/lib/b2/xparser.x"
                    xn_Cls_Lexer_adv(self);
                    #line 553 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Lexer_eof(self))) {
                            size_t xn_t680 = xn_root_mark();
                            #line 553 "impl/lib/b2/xparser.x"
                            xn_root_restore(xn_t680);
                            xn_root_restore(xn_t679);
                            xn_root_restore(xn_t622);
                            break;
                                {
                                xn_root_restore(xn_t680);
                                }

                        }
                    #line 554 "impl/lib/b2/xparser.x"
                    int64_t e = ((int64_t)xrt_bytes_get(self->bytes, (size_t)(self->pos)));
                    #line 555 "impl/lib/b2/xparser.x"
                    xn_Cls_Lexer_adv(self);
                    #line 556 "impl/lib/b2/xparser.x"
                        if (((e == 110))) {
                            size_t xn_t681 = xn_root_mark();
                            #line 556 "impl/lib/b2/xparser.x"
                            rt_string *xn_t682 = rt_retain(val);
xn_root_add(xn_t682);
    xn_root_add(xn_t682);
            xn_root_add(xn_t682);
                    xn_root_add(xn_t682);
                            xn_root_add(xn_t682);
                            rt_string *xn_t683 = rt_string_from_c("\n");
xn_root_add(xn_t683);
    xn_root_add(xn_t683);
            xn_root_add(xn_t683);
                    xn_root_add(xn_t683);
                            xn_root_add(xn_t683);
                            rt_string *xn_t684 = xn_concat(xn_t682, xn_t683);
xn_root_add(xn_t684);
    xn_root_add(xn_t684);
            xn_root_add(xn_t684);
                    xn_root_add(xn_t684);
                            xn_root_add(xn_t684);
                            xn_root_release(val);
                            rt_release(val);
                            val = xn_t684;
                            xn_root_hold(val);
                            xn_gc_safepoint();
                                {
                                xn_root_restore(xn_t681);
                                }

                        } else {
                                if (((e == 116))) {
                                    size_t xn_t686 = xn_root_mark();
                                    #line 557 "impl/lib/b2/xparser.x"
                                    rt_string *xn_t687 = rt_retain(val);
xn_root_add(xn_t687);
    xn_root_add(xn_t687);
            xn_root_add(xn_t687);
                    xn_root_add(xn_t687);
                            xn_root_add(xn_t687);
                                    xn_root_add(xn_t687);
                                    rt_string *xn_t688 = rt_string_from_c("\t");
xn_root_add(xn_t688);
    xn_root_add(xn_t688);
            xn_root_add(xn_t688);
                    xn_root_add(xn_t688);
                            xn_root_add(xn_t688);
                                    xn_root_add(xn_t688);
                                    rt_string *xn_t689 = xn_concat(xn_t687, xn_t688);
xn_root_add(xn_t689);
    xn_root_add(xn_t689);
            xn_root_add(xn_t689);
                    xn_root_add(xn_t689);
                            xn_root_add(xn_t689);
                                    xn_root_add(xn_t689);
                                    xn_root_release(val);
                                    rt_release(val);
                                    val = xn_t689;
                                    xn_root_hold(val);
                                    xn_gc_safepoint();
                                        {
                                        xn_root_restore(xn_t686);
                                        }

                                } else {
                                        if (((e == 114))) {
                                            size_t xn_t691 = xn_root_mark();
                                            #line 558 "impl/lib/b2/xparser.x"
                                            rt_string *xn_t692 = rt_retain(val);
xn_root_add(xn_t692);
    xn_root_add(xn_t692);
            xn_root_add(xn_t692);
                    xn_root_add(xn_t692);
                            xn_root_add(xn_t692);
                                    xn_root_add(xn_t692);
                                            xn_root_add(xn_t692);
                                            rt_string *xn_t693 = rt_string_from_c("\r");
xn_root_add(xn_t693);
    xn_root_add(xn_t693);
            xn_root_add(xn_t693);
                    xn_root_add(xn_t693);
                            xn_root_add(xn_t693);
                                    xn_root_add(xn_t693);
                                            xn_root_add(xn_t693);
                                            rt_string *xn_t694 = xn_concat(xn_t692, xn_t693);
xn_root_add(xn_t694);
    xn_root_add(xn_t694);
            xn_root_add(xn_t694);
                    xn_root_add(xn_t694);
                            xn_root_add(xn_t694);
                                    xn_root_add(xn_t694);
                                            xn_root_add(xn_t694);
                                            xn_root_release(val);
                                            rt_release(val);
                                            val = xn_t694;
                                            xn_root_hold(val);
                                            xn_gc_safepoint();
                                                {
                                                xn_root_restore(xn_t691);
                                                }

                                        } else {
                                                if (((e == 34))) {
                                                    size_t xn_t696 = xn_root_mark();
                                                    #line 559 "impl/lib/b2/xparser.x"
                                                    rt_string *xn_t697 = rt_retain(val);
xn_root_add(xn_t697);
    xn_root_add(xn_t697);
            xn_root_add(xn_t697);
                    xn_root_add(xn_t697);
                            xn_root_add(xn_t697);
                                    xn_root_add(xn_t697);
                                            xn_root_add(xn_t697);
                                                    xn_root_add(xn_t697);
                                                    rt_string *xn_t698 = rt_string_from_c("\"");
xn_root_add(xn_t698);
    xn_root_add(xn_t698);
            xn_root_add(xn_t698);
                    xn_root_add(xn_t698);
                            xn_root_add(xn_t698);
                                    xn_root_add(xn_t698);
                                            xn_root_add(xn_t698);
                                                    xn_root_add(xn_t698);
                                                    rt_string *xn_t699 = xn_concat(xn_t697, xn_t698);
xn_root_add(xn_t699);
    xn_root_add(xn_t699);
            xn_root_add(xn_t699);
                    xn_root_add(xn_t699);
                            xn_root_add(xn_t699);
                                    xn_root_add(xn_t699);
                                            xn_root_add(xn_t699);
                                                    xn_root_add(xn_t699);
                                                    xn_root_release(val);
                                                    rt_release(val);
                                                    val = xn_t699;
                                                    xn_root_hold(val);
                                                    xn_gc_safepoint();
                                                        {
                                                        xn_root_restore(xn_t696);
                                                        }

                                                } else {
                                                        if (((e == 92))) {
                                                            size_t xn_t701 = xn_root_mark();
                                                            #line 560 "impl/lib/b2/xparser.x"
                                                            rt_string *xn_t702 = rt_retain(val);
xn_root_add(xn_t702);
    xn_root_add(xn_t702);
            xn_root_add(xn_t702);
                    xn_root_add(xn_t702);
                            xn_root_add(xn_t702);
                                    xn_root_add(xn_t702);
                                            xn_root_add(xn_t702);
                                                    xn_root_add(xn_t702);
                                                            xn_root_add(xn_t702);
                                                            rt_string *xn_t703 = rt_string_from_c("\\");
xn_root_add(xn_t703);
    xn_root_add(xn_t703);
            xn_root_add(xn_t703);
                    xn_root_add(xn_t703);
                            xn_root_add(xn_t703);
                                    xn_root_add(xn_t703);
                                            xn_root_add(xn_t703);
                                                    xn_root_add(xn_t703);
                                                            xn_root_add(xn_t703);
                                                            rt_string *xn_t704 = xn_concat(xn_t702, xn_t703);
xn_root_add(xn_t704);
    xn_root_add(xn_t704);
            xn_root_add(xn_t704);
                    xn_root_add(xn_t704);
                            xn_root_add(xn_t704);
                                    xn_root_add(xn_t704);
                                            xn_root_add(xn_t704);
                                                    xn_root_add(xn_t704);
                                                            xn_root_add(xn_t704);
                                                            xn_root_release(val);
                                                            rt_release(val);
                                                            val = xn_t704;
                                                            xn_root_hold(val);
                                                            xn_gc_safepoint();
                                                                {
                                                                xn_root_restore(xn_t701);
                                                                }

                                                        } else {
                                                                if (((e == 39))) {
                                                                    size_t xn_t706 = xn_root_mark();
                                                                    #line 561 "impl/lib/b2/xparser.x"
                                                                    rt_string *xn_t707 = rt_retain(val);
xn_root_add(xn_t707);
    xn_root_add(xn_t707);
            xn_root_add(xn_t707);
                    xn_root_add(xn_t707);
                            xn_root_add(xn_t707);
                                    xn_root_add(xn_t707);
                                            xn_root_add(xn_t707);
                                                    xn_root_add(xn_t707);
                                                            xn_root_add(xn_t707);
                                                                    xn_root_add(xn_t707);
                                                                    rt_string *xn_t708 = rt_string_from_c("'");
xn_root_add(xn_t708);
    xn_root_add(xn_t708);
            xn_root_add(xn_t708);
                    xn_root_add(xn_t708);
                            xn_root_add(xn_t708);
                                    xn_root_add(xn_t708);
                                            xn_root_add(xn_t708);
                                                    xn_root_add(xn_t708);
                                                            xn_root_add(xn_t708);
                                                                    xn_root_add(xn_t708);
                                                                    rt_string *xn_t709 = xn_concat(xn_t707, xn_t708);
xn_root_add(xn_t709);
    xn_root_add(xn_t709);
            xn_root_add(xn_t709);
                    xn_root_add(xn_t709);
                            xn_root_add(xn_t709);
                                    xn_root_add(xn_t709);
                                            xn_root_add(xn_t709);
                                                    xn_root_add(xn_t709);
                                                            xn_root_add(xn_t709);
                                                                    xn_root_add(xn_t709);
                                                                    xn_root_release(val);
                                                                    rt_release(val);
                                                                    val = xn_t709;
                                                                    xn_root_hold(val);
                                                                    xn_gc_safepoint();
                                                                        {
                                                                        xn_root_restore(xn_t706);
                                                                        }

                                                                } else {
                                                                        if (((e == 48))) {
                                                                            size_t xn_t711 = xn_root_mark();
                                                                            #line 562 "impl/lib/b2/xparser.x"
                                                                            rt_string *xn_t712 = rt_retain(val);
xn_root_add(xn_t712);
    xn_root_add(xn_t712);
            xn_root_add(xn_t712);
                    xn_root_add(xn_t712);
                            xn_root_add(xn_t712);
                                    xn_root_add(xn_t712);
                                            xn_root_add(xn_t712);
                                                    xn_root_add(xn_t712);
                                                            xn_root_add(xn_t712);
                                                                    xn_root_add(xn_t712);
                                                                            xn_root_add(xn_t712);
                                                                            rt_string *xn_t713 = xn_str_char((int32_t)(0));
xn_root_add(xn_t713);
    xn_root_add(xn_t713);
            xn_root_add(xn_t713);
                    xn_root_add(xn_t713);
                            xn_root_add(xn_t713);
                                    xn_root_add(xn_t713);
                                            xn_root_add(xn_t713);
                                                    xn_root_add(xn_t713);
                                                            xn_root_add(xn_t713);
                                                                    xn_root_add(xn_t713);
                                                                            xn_root_add(xn_t713);
                                                                            rt_string *xn_t714 = xn_concat(xn_t712, xn_t713);
xn_root_add(xn_t714);
    xn_root_add(xn_t714);
            xn_root_add(xn_t714);
                    xn_root_add(xn_t714);
                            xn_root_add(xn_t714);
                                    xn_root_add(xn_t714);
                                            xn_root_add(xn_t714);
                                                    xn_root_add(xn_t714);
                                                            xn_root_add(xn_t714);
                                                                    xn_root_add(xn_t714);
                                                                            xn_root_add(xn_t714);
                                                                            xn_root_release(val);
                                                                            rt_release(val);
                                                                            val = xn_t714;
                                                                            xn_root_hold(val);
                                                                            xn_gc_safepoint();
                                                                                {
                                                                                xn_root_restore(xn_t711);
                                                                                }

                                                                        } else {
                                                                                if (((((((e == 117)) && ((xn_Cls_Lexer_b(self, self->pos) == 48))) && ((xn_Cls_Lexer_b(self, (self->pos + 1)) == 48))) && ((xn_Cls_Lexer_b(self, (self->pos + 2)) == 48))) && ((xn_Cls_Lexer_b(self, (self->pos + 3)) == 48)))) {
                                                                                    size_t xn_t716 = xn_root_mark();
                                                                                    #line 566 "impl/lib/b2/xparser.x"
                                                                                    xn_Cls_Lexer_adv(self);
                                                                                    #line 566 "impl/lib/b2/xparser.x"
                                                                                    xn_Cls_Lexer_adv(self);
                                                                                    #line 566 "impl/lib/b2/xparser.x"
                                                                                    xn_Cls_Lexer_adv(self);
                                                                                    #line 566 "impl/lib/b2/xparser.x"
                                                                                    xn_Cls_Lexer_adv(self);
                                                                                    #line 567 "impl/lib/b2/xparser.x"
                                                                                    rt_string *xn_t717 = rt_retain(val);
xn_root_add(xn_t717);
    xn_root_add(xn_t717);
            xn_root_add(xn_t717);
                    xn_root_add(xn_t717);
                            xn_root_add(xn_t717);
                                    xn_root_add(xn_t717);
                                            xn_root_add(xn_t717);
                                                    xn_root_add(xn_t717);
                                                            xn_root_add(xn_t717);
                                                                    xn_root_add(xn_t717);
                                                                            xn_root_add(xn_t717);
                                                                                    xn_root_add(xn_t717);
                                                                                    rt_string *xn_t718 = xn_str_char((int32_t)(0));
xn_root_add(xn_t718);
    xn_root_add(xn_t718);
            xn_root_add(xn_t718);
                    xn_root_add(xn_t718);
                            xn_root_add(xn_t718);
                                    xn_root_add(xn_t718);
                                            xn_root_add(xn_t718);
                                                    xn_root_add(xn_t718);
                                                            xn_root_add(xn_t718);
                                                                    xn_root_add(xn_t718);
                                                                            xn_root_add(xn_t718);
                                                                                    xn_root_add(xn_t718);
                                                                                    rt_string *xn_t719 = xn_concat(xn_t717, xn_t718);
xn_root_add(xn_t719);
    xn_root_add(xn_t719);
            xn_root_add(xn_t719);
                    xn_root_add(xn_t719);
                            xn_root_add(xn_t719);
                                    xn_root_add(xn_t719);
                                            xn_root_add(xn_t719);
                                                    xn_root_add(xn_t719);
                                                            xn_root_add(xn_t719);
                                                                    xn_root_add(xn_t719);
                                                                            xn_root_add(xn_t719);
                                                                                    xn_root_add(xn_t719);
                                                                                    xn_root_release(val);
                                                                                    rt_release(val);
                                                                                    val = xn_t719;
                                                                                    xn_root_hold(val);
                                                                                    xn_gc_safepoint();
                                                                                        {
                                                                                        xn_root_restore(xn_t716);
                                                                                        }

                                                                                } else {
                                                                                    size_t xn_t720 = xn_root_mark();
                                                                                    #line 569 "impl/lib/b2/xparser.x"
                                                                                    rt_string *xn_t721 = rt_string_from_c("LEX-103");
xn_root_add(xn_t721);
    xn_root_add(xn_t721);
            xn_root_add(xn_t721);
                    xn_root_add(xn_t721);
                            xn_root_add(xn_t721);
                                    xn_root_add(xn_t721);
                                            xn_root_add(xn_t721);
                                                    xn_root_add(xn_t721);
                                                            xn_root_add(xn_t721);
                                                                    xn_root_add(xn_t721);
                                                                            xn_root_add(xn_t721);
                                                                                    xn_root_add(xn_t721);
                                                                                    rt_string *xn_t722 = rt_string_from_c("未知转义");
xn_root_add(xn_t722);
    xn_root_add(xn_t722);
            xn_root_add(xn_t722);
                    xn_root_add(xn_t722);
                            xn_root_add(xn_t722);
                                    xn_root_add(xn_t722);
                                            xn_root_add(xn_t722);
                                                    xn_root_add(xn_t722);
                                                            xn_root_add(xn_t722);
                                                                    xn_root_add(xn_t722);
                                                                            xn_root_add(xn_t722);
                                                                                    xn_root_add(xn_t722);
                                                                                    xn_Cls_Lexer_err(self, xn_t721, el, ec, xn_t722);
                                                                                    #line 569 "impl/lib/b2/xparser.x"
                                                                                    rt_string *xn_t723 = rt_retain(val);
xn_root_add(xn_t723);
    xn_root_add(xn_t723);
            xn_root_add(xn_t723);
                    xn_root_add(xn_t723);
                            xn_root_add(xn_t723);
                                    xn_root_add(xn_t723);
                                            xn_root_add(xn_t723);
                                                    xn_root_add(xn_t723);
                                                            xn_root_add(xn_t723);
                                                                    xn_root_add(xn_t723);
                                                                            xn_root_add(xn_t723);
                                                                                    xn_root_add(xn_t723);
                                                                                    rt_string *xn_t724 = xn_Cls_Lexer_one(self, (self->pos - 1));
xn_root_add(xn_t724);
    xn_root_add(xn_t724);
            xn_root_add(xn_t724);
                    xn_root_add(xn_t724);
                            xn_root_add(xn_t724);
                                    xn_root_add(xn_t724);
                                            xn_root_add(xn_t724);
                                                    xn_root_add(xn_t724);
                                                            xn_root_add(xn_t724);
                                                                    xn_root_add(xn_t724);
                                                                            xn_root_add(xn_t724);
                                                                                    xn_root_add(xn_t724);
                                                                                    rt_string *xn_t725 = xn_concat(xn_t723, xn_t724);
xn_root_add(xn_t725);
    xn_root_add(xn_t725);
            xn_root_add(xn_t725);
                    xn_root_add(xn_t725);
                            xn_root_add(xn_t725);
                                    xn_root_add(xn_t725);
                                            xn_root_add(xn_t725);
                                                    xn_root_add(xn_t725);
                                                            xn_root_add(xn_t725);
                                                                    xn_root_add(xn_t725);
                                                                            xn_root_add(xn_t725);
                                                                                    xn_root_add(xn_t725);
                                                                                    xn_root_release(val);
                                                                                    rt_release(val);
                                                                                    val = xn_t725;
                                                                                    xn_root_hold(val);
                                                                                    xn_gc_safepoint();
                                                                                        {
                                                                                        xn_root_restore(xn_t720);
                                                                                        }

                                                                                }
                                                                        }
                                                                }
                                                        }
                                                }
                                        }
                                }
                        }
                        {
                        xn_root_restore(xn_t679);
                        }

                } else {
                    size_t xn_t726 = xn_root_mark();
                    #line 571 "impl/lib/b2/xparser.x"
                    rt_string *xn_t727 = rt_retain(val);
xn_root_add(xn_t727);
    xn_root_add(xn_t727);
            xn_root_add(xn_t727);
                    xn_root_add(xn_t727);
                    rt_string *xn_t728 = xn_Cls_Lexer_one(self, self->pos);
xn_root_add(xn_t728);
    xn_root_add(xn_t728);
            xn_root_add(xn_t728);
                    xn_root_add(xn_t728);
                    rt_string *xn_t729 = xn_concat(xn_t727, xn_t728);
xn_root_add(xn_t729);
    xn_root_add(xn_t729);
            xn_root_add(xn_t729);
                    xn_root_add(xn_t729);
                    xn_root_release(val);
                    rt_release(val);
                    val = xn_t729;
                    xn_root_hold(val);
                    xn_gc_safepoint();
                    #line 572 "impl/lib/b2/xparser.x"
                    xn_Cls_Lexer_adv(self);
                        {
                        xn_root_restore(xn_t726);
                        }

                }
        }
        {
        xn_root_restore(xn_t622);
        }

    xn_gc_safepoint();
    }
#line 575 "impl/lib/b2/xparser.x"
    if (((!(closed)))) {
        size_t xn_t730 = xn_root_mark();
        #line 576 "impl/lib/b2/xparser.x"
        rt_string *xn_t731 = rt_string_from_c("LEX-102");
xn_root_add(xn_t731);
        xn_root_add(xn_t731);
        rt_string *xn_t732 = rt_string_from_c("字符串未闭合");
xn_root_add(xn_t732);
        xn_root_add(xn_t732);
        xn_Cls_Lexer_err(self, xn_t731, xn_p_l, xn_p_c, xn_t732);
            {
            xn_root_restore(xn_t730);
            }

    }
#line 578 "impl/lib/b2/xparser.x"
rt_string *xn_t733 = rt_retain(val);
xn_root_add(xn_t733);
xn_arr_s_push(segs, xn_t733);
#line 579 "impl/lib/b2/xparser.x"
rt_string *xn_t734 = rt_retain(joined);
xn_root_add(xn_t734);
rt_string *xn_t735 = rt_retain(val);
xn_root_add(xn_t735);
rt_string *xn_t736 = xn_concat(xn_t734, xn_t735);
xn_root_add(xn_t736);
rt_release(joined);
joined = xn_t736;
xn_root_add(joined);
xn_gc_safepoint();
#line 580 "impl/lib/b2/xparser.x"
int64_t kind = 0;
#line 581 "impl/lib/b2/xparser.x"
    if ((xn_p_interp)) {
        size_t xn_t737 = xn_root_mark();
        #line 581 "impl/lib/b2/xparser.x"
        kind = 4;
            {
            xn_root_restore(xn_t737);
            }

    } else {
            if (((xn_p_raw) && (xn_p_multiline))) {
                size_t xn_t739 = xn_root_mark();
                #line 582 "impl/lib/b2/xparser.x"
                kind = 3;
                    {
                    xn_root_restore(xn_t739);
                    }

            } else {
                    if ((xn_p_raw)) {
                        size_t xn_t741 = xn_root_mark();
                        #line 583 "impl/lib/b2/xparser.x"
                        kind = 1;
                            {
                            xn_root_restore(xn_t741);
                            }

                    } else {
                            if ((xn_p_multiline)) {
                                size_t xn_t743 = xn_root_mark();
                                #line 584 "impl/lib/b2/xparser.x"
                                kind = 2;
                                    {
                                    xn_root_restore(xn_t743);
                                    }

                            }
                    }
            }
    }
#line 585 "impl/lib/b2/xparser.x"
rt_string *xn_t744 = rt_string_from_c("");
xn_root_add(xn_t744);
xn_Cls_Tok * t = xn_Cls_Lexer_mk(self, 8, xn_t744, xn_p_l, xn_p_c);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 586 "impl/lib/b2/xparser.x"
t->str = kind;
#line 587 "impl/lib/b2/xparser.x"
rt_string *xn_t745 = rt_retain(joined);
xn_root_add(xn_t745);
rt_release(t->value);
t->value = xn_t745;
#line 588 "impl/lib/b2/xparser.x"
t->segs = segs;
#line 589 "impl/lib/b2/xparser.x"
t->interps = interps;
#line 590 "impl/lib/b2/xparser.x"
    {
rt_release(joined);
    }
    {
rt_release(val);
    }
    {
xn_root_restore(xn_t615);
    }

return t;
xn_root_release(val);
xn_root_release(joined);
    return (xn_Cls_Tok *)0; /* sema 保证不可达（函数体全路径 return） */
}

/* 类 E（M4.4b） */
typedef struct xn_Cls_E {
    rt_header hdr;
    rt_string * d;
    int64_t l;
    int64_t c;
    int64_t sl;
    int64_t sc;
} xn_Cls_E;

static void xn_Cls_E_deinit_hook(void *p) {
    xn_Cls_E *o = (xn_Cls_E *)p;
    rt_release(o->d);
}

static void xn_Cls_E_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_E *o = (xn_Cls_E *)p;
    if (o->d) { visit(o->d); }
}

static const rt_type RT_TYPE_XN_E = { "E", sizeof(xn_Cls_E), xn_Cls_E_deinit_hook, xn_Cls_E_gc_scan };

static void xn_Cls_E_new_init(xn_Cls_E *o) {
    rt_string *xn_t746 = rt_string_from_c("");
    rt_release((void *)o->d);
    o->d = xn_t746;
    o->l = 1;
    o->c = 1;
    o->sl = 1;
    o->sc = 1;
}

static xn_Cls_E *xn_Cls_E_new(void) {
    xn_Cls_E *o = (xn_Cls_E *)xn_gc_new(&RT_TYPE_XN_E);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_E) - sizeof(rt_header));
    xn_Cls_E_new_init(o);
    return o;
}


/* 类 M（M4.4b） */
typedef struct xn_Cls_M {
    rt_header hdr;
    rt_string * vis;
    int64_t abs;
    int64_t fin;
    int64_t stat;
    int64_t cons;
} xn_Cls_M;

static void xn_Cls_M_deinit_hook(void *p) {
    xn_Cls_M *o = (xn_Cls_M *)p;
    rt_release(o->vis);
}

static void xn_Cls_M_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_M *o = (xn_Cls_M *)p;
    if (o->vis) { visit(o->vis); }
}

static const rt_type RT_TYPE_XN_M = { "M", sizeof(xn_Cls_M), xn_Cls_M_deinit_hook, xn_Cls_M_gc_scan };

static void xn_Cls_M_new_init(xn_Cls_M *o) {
    rt_string *xn_t747 = rt_string_from_c("");
    rt_release((void *)o->vis);
    o->vis = xn_t747;
    o->abs = (int64_t)((int)(0));
    o->fin = (int64_t)((int)(0));
    o->stat = (int64_t)((int)(0));
    o->cons = (int64_t)((int)(0));
}

static xn_Cls_M *xn_Cls_M_new(void) {
    xn_Cls_M *o = (xn_Cls_M *)xn_gc_new(&RT_TYPE_XN_M);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_M) - sizeof(rt_header));
    xn_Cls_M_new_init(o);
    return o;
}


/* 类 TN（M4.4b） */
typedef struct xn_Cls_TN {
    rt_header hdr;
    int64_t sc;
    rt_string * raw;
    rt_string * nm;
    xn_arr_s * fn;
    xn_arr_o_TN * fv;
    xn_arr_o_TN * el;
} xn_Cls_TN;

static void xn_Cls_TN_deinit_hook(void *p) {
    xn_Cls_TN *o = (xn_Cls_TN *)p;
    rt_release(o->raw);
    rt_release(o->nm);
}

static void xn_Cls_TN_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_TN *o = (xn_Cls_TN *)p;
    if (o->raw) { visit(o->raw); }
    if (o->nm) { visit(o->nm); }
    if (o->fn) { visit(o->fn); }
    if (o->fv) { visit(o->fv); }
    if (o->el) { visit(o->el); }
}

static const rt_type RT_TYPE_XN_TN = { "TN", sizeof(xn_Cls_TN), xn_Cls_TN_deinit_hook, xn_Cls_TN_gc_scan };

static void xn_Cls_TN_new_init(xn_Cls_TN *o) {
    o->sc = (int64_t)((int)(0));
    rt_string *xn_t748 = rt_string_from_c("");
    rt_release((void *)o->raw);
    o->raw = xn_t748;
    rt_string *xn_t749 = rt_string_from_c("");
    rt_release((void *)o->nm);
    o->nm = xn_t749;
    xn_arr_s *xn_t750 = xn_arr_s_new(0);
    o->fn = xn_t750;
    xn_arr_o_TN *xn_t751 = xn_arr_o_TN_new(0);
    o->fv = xn_t751;
    xn_arr_o_TN *xn_t752 = xn_arr_o_TN_new(0);
    o->el = xn_t752;
}

static xn_Cls_TN *xn_Cls_TN_new(void) {
    xn_Cls_TN *o = (xn_Cls_TN *)xn_gc_new(&RT_TYPE_XN_TN);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_TN) - sizeof(rt_header));
    xn_Cls_TN_new_init(o);
    return o;
}


/* 类 TP（M4.4b） */
typedef struct xn_Cls_TP {
    rt_header hdr;
    rt_string * s;
    int64_t p;
    int64_t n;
} xn_Cls_TP;

static void xn_Cls_TP_deinit_hook(void *p) {
    xn_Cls_TP *o = (xn_Cls_TP *)p;
    rt_release(o->s);
}

static void xn_Cls_TP_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_TP *o = (xn_Cls_TP *)p;
    if (o->s) { visit(o->s); }
}

static const rt_type RT_TYPE_XN_TP = { "TP", sizeof(xn_Cls_TP), xn_Cls_TP_deinit_hook, xn_Cls_TP_gc_scan };

static void xn_Cls_TP_new_init(xn_Cls_TP *o, rt_string * xn_p_t) {
    rt_string *xn_t753 = rt_string_from_c("");
    rt_release((void *)o->s);
    o->s = xn_t753;
    o->p = 0;
    o->n = 0;
size_t xn_t754 = xn_root_mark();
xn_root_add(o);
xn_root_add(xn_p_t);
#line 689 "impl/lib/b2/xparser.x"
rt_string *xn_t755 = rt_retain(xn_p_t);
xn_root_add(xn_t755);
rt_release(o->s);
o->s = xn_t755;
#line 689 "impl/lib/b2/xparser.x"
o->n = xn_str_length(xn_p_t);
    {
    xn_root_restore(xn_t754);
    }
}

static xn_Cls_TP *xn_Cls_TP_new(rt_string * xn_p_t) {
    xn_Cls_TP *o = (xn_Cls_TP *)xn_gc_new(&RT_TYPE_XN_TP);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_TP) - sizeof(rt_header));
    xn_Cls_TP_new_init(o, xn_p_t);
    return o;
}

static rt_string * xn_Cls_TP_ch(xn_Cls_TP *self, int64_t xn_p_i);
static void xn_Cls_TP_ws(xn_Cls_TP *self);
static rt_string * xn_Cls_TP_bare(xn_Cls_TP *self);
static xn_Cls_TN * xn_Cls_TP_val(xn_Cls_TP *self);
static rt_string * xn_Cls_TP_render(xn_Cls_TP *self, xn_Cls_TN * xn_p_v, int64_t xn_p_dep);
static rt_string * xn_Cls_TP_renderField(xn_Cls_TP *self, xn_Cls_TN * xn_p_v, int64_t xn_p_cd, rt_string * xn_p_cat);
static rt_string * xn_Cls_TP_fcat(xn_Cls_TP *self, rt_string * xn_p_nd, rt_string * xn_p_f);

static rt_string * xn_Cls_TP_ch(xn_Cls_TP *self, int64_t xn_p_i) {
size_t xn_t756 = xn_root_mark();
xn_root_add(self);
#line 692 "impl/lib/b2/xparser.x"
    if (((xn_p_i < 0))) {
        size_t xn_t757 = xn_root_mark();
        #line 692 "impl/lib/b2/xparser.x"
        rt_string *xn_t758 = rt_string_from_c("");
xn_root_add(xn_t758);
        xn_root_add(xn_t758);
        xn_root_add(xn_t758);
            {
        xn_root_restore(xn_t757);
            }
            {
        xn_root_restore(xn_t756);
            }

        return xn_t758;

    }
#line 693 "impl/lib/b2/xparser.x"
    if (((xn_p_i >= self->n))) {
        size_t xn_t759 = xn_root_mark();
        #line 693 "impl/lib/b2/xparser.x"
        rt_string *xn_t760 = rt_string_from_c("");
xn_root_add(xn_t760);
        xn_root_add(xn_t760);
        xn_root_add(xn_t760);
            {
        xn_root_restore(xn_t759);
            }
            {
        xn_root_restore(xn_t756);
            }

        return xn_t760;

    }
#line 694 "impl/lib/b2/xparser.x"
rt_string *xn_t761 = rt_retain(self->s);
xn_root_add(xn_t761);
xn_root_add(xn_t761);
rt_string *xn_t762 = xn_str_substr(xn_t761, xn_p_i, 1);
xn_root_add(xn_t762);
xn_root_add(xn_t762);
    {
xn_root_restore(xn_t756);
    }

return xn_t762;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static void xn_Cls_TP_ws(xn_Cls_TP *self) {
size_t xn_t763 = xn_root_mark();
xn_root_add(self);
#line 698 "impl/lib/b2/xparser.x"
    while (1) {
        rt_string *xn_t764 = xn_Cls_TP_ch(self, self->p);
xn_root_add(xn_t764);
        rt_string *xn_t765 = rt_string_from_c(" ");
xn_root_add(xn_t765);
        if (!((((self->p < self->n)) && (xn_str_eq(xn_t764, xn_t765))))) { break; }
        size_t xn_t766 = xn_root_mark();
        #line 698 "impl/lib/b2/xparser.x"
        self->p = (self->p + 1);
            {
            xn_root_restore(xn_t766);
            }

        xn_gc_safepoint();
    }
    {
    xn_root_restore(xn_t763);
    }
}

static rt_string * xn_Cls_TP_bare(xn_Cls_TP *self) {
size_t xn_t767 = xn_root_mark();
xn_root_add(self);
#line 702 "impl/lib/b2/xparser.x"
int64_t st = self->p;
#line 703 "impl/lib/b2/xparser.x"
    while (((self->p < self->n))) {
    size_t xn_t768 = xn_root_mark();
    #line 704 "impl/lib/b2/xparser.x"
    rt_string *c = xn_Cls_TP_ch(self, self->p);
xn_root_add(c);
    xn_root_add(c);
    xn_root_add(c);
    xn_gc_safepoint();
    #line 705 "impl/lib/b2/xparser.x"
    rt_string *xn_t770 = rt_retain(c);
xn_root_add(xn_t770);
    xn_root_add(xn_t770);
    rt_string *xn_t771 = rt_string_from_c(" ");
xn_root_add(xn_t771);
    xn_root_add(xn_t771);
    rt_string *xn_t772 = rt_retain(c);
xn_root_add(xn_t772);
    xn_root_add(xn_t772);
    rt_string *xn_t773 = rt_string_from_c("(");
xn_root_add(xn_t773);
    xn_root_add(xn_t773);
    rt_string *xn_t774 = rt_retain(c);
xn_root_add(xn_t774);
    xn_root_add(xn_t774);
    rt_string *xn_t775 = rt_string_from_c(")");
xn_root_add(xn_t775);
    xn_root_add(xn_t775);
        if ((((xn_str_eq(xn_t770, xn_t771)) || (xn_str_eq(xn_t772, xn_t773))) || (xn_str_eq(xn_t774, xn_t775)))) {
            size_t xn_t776 = xn_root_mark();
            #line 705 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t776);
            xn_root_restore(xn_t768);
            break;
                {
                xn_root_restore(xn_t776);
                }

        }
    #line 706 "impl/lib/b2/xparser.x"
    self->p = (self->p + 1);
        {
        rt_release(c);
        }
        {
        xn_root_restore(xn_t768);
        }

    xn_gc_safepoint();
    }
#line 708 "impl/lib/b2/xparser.x"
rt_string *xn_t777 = rt_retain(self->s);
xn_root_add(xn_t777);
xn_root_add(xn_t777);
rt_string *xn_t778 = xn_str_substr(xn_t777, st, (self->p - st));
xn_root_add(xn_t778);
xn_root_add(xn_t778);
    {
xn_root_restore(xn_t767);
    }

return xn_t778;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_TN * xn_Cls_TP_val(xn_Cls_TP *self) {
size_t xn_t779 = xn_root_mark();
xn_root_add(self);
#line 712 "impl/lib/b2/xparser.x"
xn_Cls_TP_ws(self);
#line 713 "impl/lib/b2/xparser.x"
rt_string *xn_t780 = xn_Cls_TP_ch(self, self->p);
xn_root_add(xn_t780);
rt_string *xn_t781 = rt_string_from_c("(");
xn_root_add(xn_t781);
    if ((xn_str_eq(xn_t780, xn_t781))) {
        size_t xn_t782 = xn_root_mark();
        #line 714 "impl/lib/b2/xparser.x"
        self->p = (self->p + 1);
        #line 715 "impl/lib/b2/xparser.x"
        rt_string *name = xn_Cls_TP_bare(self);
xn_root_add(name);
        xn_root_add(name);
        xn_root_add(name);
        xn_gc_safepoint();
        #line 716 "impl/lib/b2/xparser.x"
        xn_Cls_TN * r = xn_Cls_TN_new();
xn_root_add(r);
        xn_root_add(r);
        xn_root_add(r);
        xn_gc_safepoint();
        #line 717 "impl/lib/b2/xparser.x"
        rt_string *xn_t784 = rt_retain(name);
xn_root_add(xn_t784);
        xn_root_add(xn_t784);
        rt_string *xn_t785 = rt_string_from_c("slice");
xn_root_add(xn_t785);
        xn_root_add(xn_t785);
            if ((xn_str_eq(xn_t784, xn_t785))) {
                size_t xn_t786 = xn_root_mark();
                #line 718 "impl/lib/b2/xparser.x"
                rt_string *xn_t787 = rt_string_from_c("slice");
xn_root_add(xn_t787);
        xn_root_add(xn_t787);
                xn_root_add(xn_t787);
                rt_release(r->nm);
                r->nm = xn_t787;
                #line 719 "impl/lib/b2/xparser.x"
                    while (1) {
                    size_t xn_t788 = xn_root_mark();
                    #line 720 "impl/lib/b2/xparser.x"
                    xn_Cls_TP_ws(self);
                    #line 721 "impl/lib/b2/xparser.x"
                    rt_string *xn_t789 = xn_Cls_TP_ch(self, self->p);
xn_root_add(xn_t789);
        xn_root_add(xn_t789);
                xn_root_add(xn_t789);
                    xn_root_add(xn_t789);
                    rt_string *xn_t790 = rt_string_from_c(")");
xn_root_add(xn_t790);
        xn_root_add(xn_t790);
                xn_root_add(xn_t790);
                    xn_root_add(xn_t790);
                        if ((xn_str_eq(xn_t789, xn_t790))) {
                            size_t xn_t791 = xn_root_mark();
                            #line 721 "impl/lib/b2/xparser.x"
                            self->p = (self->p + 1);
                            #line 721 "impl/lib/b2/xparser.x"
                            xn_root_restore(xn_t791);
                            xn_root_restore(xn_t788);
                            break;
                                {
                                xn_root_restore(xn_t791);
                                }

                        }
                    #line 722 "impl/lib/b2/xparser.x"
                    xn_Cls_TN * xn_t792 = xn_Cls_TP_val(self);
xn_root_add(xn_t792);
        xn_root_add(xn_t792);
                xn_root_add(xn_t792);
                    xn_root_add(xn_t792);
                    xn_root_add(xn_t792);
                    xn_arr_o_TN_push(r->el, xn_t792);
                        {
                        xn_root_restore(xn_t788);
                        }

                    xn_gc_safepoint();
                    }
                #line 724 "impl/lib/b2/xparser.x"
                    {
                xn_root_restore(xn_t786);
                    }
                    {
                rt_release(name);
                    }
                    {
                xn_root_restore(xn_t782);
                    }
                    {
                xn_root_restore(xn_t779);
                    }

                return r;

            }
        #line 726 "impl/lib/b2/xparser.x"
        rt_string *xn_t793 = rt_retain(name);
xn_root_add(xn_t793);
        xn_root_add(xn_t793);
        rt_release(r->nm);
        r->nm = xn_t793;
        #line 727 "impl/lib/b2/xparser.x"
            while (1) {
            size_t xn_t794 = xn_root_mark();
            #line 728 "impl/lib/b2/xparser.x"
            xn_Cls_TP_ws(self);
            #line 729 "impl/lib/b2/xparser.x"
            rt_string *xn_t795 = xn_Cls_TP_ch(self, self->p);
xn_root_add(xn_t795);
        xn_root_add(xn_t795);
            xn_root_add(xn_t795);
            rt_string *xn_t796 = rt_string_from_c(")");
xn_root_add(xn_t796);
        xn_root_add(xn_t796);
            xn_root_add(xn_t796);
                if ((xn_str_eq(xn_t795, xn_t796))) {
                    size_t xn_t797 = xn_root_mark();
                    #line 729 "impl/lib/b2/xparser.x"
                    self->p = (self->p + 1);
                    #line 729 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t797);
                    xn_root_restore(xn_t794);
                    break;
                        {
                        xn_root_restore(xn_t797);
                        }

                }
            #line 730 "impl/lib/b2/xparser.x"
            self->p = (self->p + 1);
            #line 731 "impl/lib/b2/xparser.x"
            rt_string *f = xn_Cls_TP_bare(self);
xn_root_add(f);
        xn_root_add(f);
            xn_root_add(f);
            xn_root_add(f);
            xn_gc_safepoint();
            #line 732 "impl/lib/b2/xparser.x"
            xn_Cls_TN * v = xn_Cls_TP_val(self);
xn_root_add(v);
        xn_root_add(v);
            xn_root_add(v);
            xn_root_add(v);
            xn_gc_safepoint();
            #line 733 "impl/lib/b2/xparser.x"
            xn_Cls_TP_ws(self);
            #line 734 "impl/lib/b2/xparser.x"
            self->p = (self->p + 1);
            #line 735 "impl/lib/b2/xparser.x"
            rt_string *xn_t799 = rt_retain(f);
xn_root_add(xn_t799);
        xn_root_add(xn_t799);
            xn_root_add(xn_t799);
            xn_arr_s_push(r->fn, xn_t799);
            #line 736 "impl/lib/b2/xparser.x"
            xn_arr_o_TN_push(r->fv, v);
                {
                rt_release(f);
                }
                {
                xn_root_restore(xn_t794);
                }

            xn_gc_safepoint();
            }
        #line 738 "impl/lib/b2/xparser.x"
            {
        rt_release(name);
            }
            {
        xn_root_restore(xn_t782);
            }
            {
        xn_root_restore(xn_t779);
            }

        return r;

    }
#line 740 "impl/lib/b2/xparser.x"
xn_Cls_TN * r = xn_Cls_TN_new();
xn_root_add(r);
xn_root_add(r);
xn_gc_safepoint();
#line 741 "impl/lib/b2/xparser.x"
r->sc = (int64_t)((int)(1));
#line 742 "impl/lib/b2/xparser.x"
rt_string *xn_t800 = xn_Cls_TP_ch(self, self->p);
xn_root_add(xn_t800);
rt_string *xn_t801 = rt_string_from_c("\"");
xn_root_add(xn_t801);
    if ((xn_str_eq(xn_t800, xn_t801))) {
        size_t xn_t802 = xn_root_mark();
        #line 743 "impl/lib/b2/xparser.x"
        int64_t st = self->p;
        #line 744 "impl/lib/b2/xparser.x"
        self->p = (self->p + 1);
        #line 745 "impl/lib/b2/xparser.x"
            while (1) {
            size_t xn_t803 = xn_root_mark();
            #line 746 "impl/lib/b2/xparser.x"
            rt_string *c = xn_Cls_TP_ch(self, self->p);
xn_root_add(c);
        xn_root_add(c);
            xn_root_add(c);
            xn_root_add(c);
            xn_gc_safepoint();
            #line 747 "impl/lib/b2/xparser.x"
            rt_string *xn_t805 = rt_retain(c);
xn_root_add(xn_t805);
        xn_root_add(xn_t805);
            xn_root_add(xn_t805);
            rt_string *xn_t806 = rt_string_from_c("\\");
xn_root_add(xn_t806);
        xn_root_add(xn_t806);
            xn_root_add(xn_t806);
                if ((xn_str_eq(xn_t805, xn_t806))) {
                    size_t xn_t807 = xn_root_mark();
                    #line 747 "impl/lib/b2/xparser.x"
                    self->p = (self->p + 2);
                    #line 747 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t807);
                    xn_root_restore(xn_t803);
                    continue;
                        {
                        xn_root_restore(xn_t807);
                        }

                }
            #line 748 "impl/lib/b2/xparser.x"
            rt_string *xn_t808 = rt_retain(c);
xn_root_add(xn_t808);
        xn_root_add(xn_t808);
            xn_root_add(xn_t808);
            rt_string *xn_t809 = rt_string_from_c("\"");
xn_root_add(xn_t809);
        xn_root_add(xn_t809);
            xn_root_add(xn_t809);
                if ((xn_str_eq(xn_t808, xn_t809))) {
                    size_t xn_t810 = xn_root_mark();
                    #line 748 "impl/lib/b2/xparser.x"
                    self->p = (self->p + 1);
                    #line 748 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t810);
                    xn_root_restore(xn_t803);
                    break;
                        {
                        xn_root_restore(xn_t810);
                        }

                }
            #line 749 "impl/lib/b2/xparser.x"
            self->p = (self->p + 1);
                {
                rt_release(c);
                }
                {
                xn_root_restore(xn_t803);
                }

            xn_gc_safepoint();
            }
        #line 751 "impl/lib/b2/xparser.x"
        rt_string *xn_t811 = rt_retain(self->s);
xn_root_add(xn_t811);
        xn_root_add(xn_t811);
        rt_string *xn_t812 = xn_str_substr(xn_t811, st, (self->p - st));
xn_root_add(xn_t812);
        xn_root_add(xn_t812);
        rt_release(r->raw);
        r->raw = xn_t812;
        #line 752 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t802);
            }
            {
        xn_root_restore(xn_t779);
            }

        return r;

    }
#line 754 "impl/lib/b2/xparser.x"
int64_t st = self->p;
#line 755 "impl/lib/b2/xparser.x"
    while (((self->p < self->n))) {
    size_t xn_t813 = xn_root_mark();
    #line 756 "impl/lib/b2/xparser.x"
    rt_string *c = xn_Cls_TP_ch(self, self->p);
xn_root_add(c);
    xn_root_add(c);
    xn_root_add(c);
    xn_gc_safepoint();
    #line 757 "impl/lib/b2/xparser.x"
    rt_string *xn_t815 = rt_retain(c);
xn_root_add(xn_t815);
    xn_root_add(xn_t815);
    rt_string *xn_t816 = rt_string_from_c(" ");
xn_root_add(xn_t816);
    xn_root_add(xn_t816);
    rt_string *xn_t817 = rt_retain(c);
xn_root_add(xn_t817);
    xn_root_add(xn_t817);
    rt_string *xn_t818 = rt_string_from_c("(");
xn_root_add(xn_t818);
    xn_root_add(xn_t818);
    rt_string *xn_t819 = rt_retain(c);
xn_root_add(xn_t819);
    xn_root_add(xn_t819);
    rt_string *xn_t820 = rt_string_from_c(")");
xn_root_add(xn_t820);
    xn_root_add(xn_t820);
        if ((((xn_str_eq(xn_t815, xn_t816)) || (xn_str_eq(xn_t817, xn_t818))) || (xn_str_eq(xn_t819, xn_t820)))) {
            size_t xn_t821 = xn_root_mark();
            #line 757 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t821);
            xn_root_restore(xn_t813);
            break;
                {
                xn_root_restore(xn_t821);
                }

        }
    #line 758 "impl/lib/b2/xparser.x"
    self->p = (self->p + 1);
        {
        rt_release(c);
        }
        {
        xn_root_restore(xn_t813);
        }

    xn_gc_safepoint();
    }
#line 760 "impl/lib/b2/xparser.x"
rt_string *xn_t822 = rt_retain(self->s);
xn_root_add(xn_t822);
rt_string *xn_t823 = xn_str_substr(xn_t822, st, (self->p - st));
xn_root_add(xn_t823);
rt_release(r->raw);
r->raw = xn_t823;
#line 761 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t779);
    }

return r;
    return (xn_Cls_TN *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_TP_render(xn_Cls_TP *self, xn_Cls_TN * xn_p_v, int64_t xn_p_dep) {
size_t xn_t824 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_v);
#line 765 "impl/lib/b2/xparser.x"
    if (((xn_p_dep > 100000))) {
        size_t xn_t825 = xn_root_mark();
        #line 765 "impl/lib/b2/xparser.x"
        rt_string *xn_t826 = rt_string_from_c("(depth-limit)");
xn_root_add(xn_t826);
        xn_root_add(xn_t826);
        xn_root_add(xn_t826);
            {
        xn_root_restore(xn_t825);
            }
            {
        xn_root_restore(xn_t824);
            }

        return xn_t826;

    }
#line 766 "impl/lib/b2/xparser.x"
    if ((((int)(xn_p_v->sc)))) {
        size_t xn_t827 = xn_root_mark();
        #line 766 "impl/lib/b2/xparser.x"
        rt_string *xn_t828 = rt_retain(xn_p_v->raw);
xn_root_add(xn_t828);
        xn_root_add(xn_t828);
        xn_root_add(xn_t828);
            {
        xn_root_restore(xn_t827);
            }
            {
        xn_root_restore(xn_t824);
            }

        return xn_t828;

    }
#line 767 "impl/lib/b2/xparser.x"
rt_string *xn_t829 = rt_retain(xn_p_v->nm);
xn_root_add(xn_t829);
rt_string *xn_t830 = rt_string_from_c("nil");
xn_root_add(xn_t830);
    if ((xn_str_eq(xn_t829, xn_t830))) {
        size_t xn_t831 = xn_root_mark();
        #line 767 "impl/lib/b2/xparser.x"
        rt_string *xn_t832 = rt_string_from_c("(nil)");
xn_root_add(xn_t832);
        xn_root_add(xn_t832);
        xn_root_add(xn_t832);
            {
        xn_root_restore(xn_t831);
            }
            {
        xn_root_restore(xn_t824);
            }

        return xn_t832;

    }
#line 768 "impl/lib/b2/xparser.x"
rt_string *xn_t833 = rt_retain(xn_p_v->nm);
xn_root_add(xn_t833);
rt_string *xn_t834 = rt_string_from_c("slice");
xn_root_add(xn_t834);
    if ((xn_str_eq(xn_t833, xn_t834))) {
        size_t xn_t835 = xn_root_mark();
        #line 769 "impl/lib/b2/xparser.x"
        rt_string *r = rt_string_from_c("(slice");
xn_root_add(r);
        xn_root_add(r);
        xn_root_add(r);
        xn_gc_safepoint();
        #line 770 "impl/lib/b2/xparser.x"
        int64_t i = 0;
        #line 771 "impl/lib/b2/xparser.x"
            while (((i < ((int64_t)xn_p_v->el->len)))) {
            size_t xn_t837 = xn_root_mark();
            #line 772 "impl/lib/b2/xparser.x"
            rt_string *xn_t838 = rt_retain(r);
xn_root_add(xn_t838);
        xn_root_add(xn_t838);
            xn_root_add(xn_t838);
            rt_string *xn_t839 = rt_string_from_c(" ");
xn_root_add(xn_t839);
        xn_root_add(xn_t839);
            xn_root_add(xn_t839);
            rt_string *xn_t840 = xn_concat(xn_t838, xn_t839);
xn_root_add(xn_t840);
        xn_root_add(xn_t840);
            xn_root_add(xn_t840);
            rt_string *xn_t841 = xn_Cls_TP_render(self, xn_arr_o_TN_get(xn_p_v->el, i), (xn_p_dep + 1));
xn_root_add(xn_t841);
        xn_root_add(xn_t841);
            xn_root_add(xn_t841);
            rt_string *xn_t842 = xn_concat(xn_t840, xn_t841);
xn_root_add(xn_t842);
        xn_root_add(xn_t842);
            xn_root_add(xn_t842);
            xn_root_release(r);
            rt_release(r);
            r = xn_t842;
            xn_root_hold(r);
            xn_gc_safepoint();
            #line 773 "impl/lib/b2/xparser.x"
            i = (i + 1);
                {
                xn_root_restore(xn_t837);
                }

            xn_gc_safepoint();
            }
        #line 775 "impl/lib/b2/xparser.x"
        rt_string *xn_t843 = rt_retain(r);
xn_root_add(xn_t843);
        xn_root_add(xn_t843);
        xn_root_add(xn_t843);
        rt_string *xn_t844 = rt_string_from_c(")");
xn_root_add(xn_t844);
        xn_root_add(xn_t844);
        xn_root_add(xn_t844);
        rt_string *xn_t845 = xn_concat(xn_t843, xn_t844);
xn_root_add(xn_t845);
        xn_root_add(xn_t845);
        xn_root_add(xn_t845);
            {
        rt_release(r);
            }
            {
        xn_root_restore(xn_t835);
            }
            {
        xn_root_restore(xn_t824);
            }

        return xn_t845;
        xn_root_release(r);

    }
#line 777 "impl/lib/b2/xparser.x"
rt_string *xn_t846 = rt_string_from_c("(");
xn_root_add(xn_t846);
rt_string *xn_t847 = rt_retain(xn_p_v->nm);
xn_root_add(xn_t847);
rt_string *r = xn_concat(xn_t846, xn_t847);
xn_root_add(r);
xn_root_add(r);
xn_gc_safepoint();
#line 778 "impl/lib/b2/xparser.x"
int64_t i = 0;
#line 779 "impl/lib/b2/xparser.x"
    while (((i < ((int64_t)xn_p_v->fn->len)))) {
    size_t xn_t849 = xn_root_mark();
    #line 780 "impl/lib/b2/xparser.x"
    rt_string *f = rt_retain(xn_arr_s_get(xn_p_v->fn, i));
xn_root_add(f);
    xn_root_add(f);
    xn_root_add(f);
    xn_gc_safepoint();
    #line 781 "impl/lib/b2/xparser.x"
    rt_string *xn_t851 = rt_retain(r);
xn_root_add(xn_t851);
    xn_root_add(xn_t851);
    rt_string *xn_t852 = rt_string_from_c(" (");
xn_root_add(xn_t852);
    xn_root_add(xn_t852);
    rt_string *xn_t853 = xn_concat(xn_t851, xn_t852);
xn_root_add(xn_t853);
    xn_root_add(xn_t853);
    rt_string *xn_t854 = rt_retain(f);
xn_root_add(xn_t854);
    xn_root_add(xn_t854);
    rt_string *xn_t855 = xn_concat(xn_t853, xn_t854);
xn_root_add(xn_t855);
    xn_root_add(xn_t855);
    rt_string *xn_t856 = rt_string_from_c(" ");
xn_root_add(xn_t856);
    xn_root_add(xn_t856);
    rt_string *xn_t857 = xn_concat(xn_t855, xn_t856);
xn_root_add(xn_t857);
    xn_root_add(xn_t857);
    rt_string *xn_t858 = rt_retain(xn_p_v->nm);
xn_root_add(xn_t858);
    xn_root_add(xn_t858);
    rt_string *xn_t859 = rt_retain(f);
xn_root_add(xn_t859);
    xn_root_add(xn_t859);
    rt_string *xn_t860 = xn_Cls_TP_fcat(self, xn_t858, xn_t859);
xn_root_add(xn_t860);
    xn_root_add(xn_t860);
    rt_string *xn_t861 = xn_Cls_TP_renderField(self, xn_arr_o_TN_get(xn_p_v->fv, i), (xn_p_dep + 1), xn_t860);
xn_root_add(xn_t861);
    xn_root_add(xn_t861);
    rt_string *xn_t862 = xn_concat(xn_t857, xn_t861);
xn_root_add(xn_t862);
    xn_root_add(xn_t862);
    rt_string *xn_t863 = rt_string_from_c(")");
xn_root_add(xn_t863);
    xn_root_add(xn_t863);
    rt_string *xn_t864 = xn_concat(xn_t862, xn_t863);
xn_root_add(xn_t864);
    xn_root_add(xn_t864);
    xn_root_release(r);
    rt_release(r);
    r = xn_t864;
    xn_root_hold(r);
    xn_gc_safepoint();
    #line 782 "impl/lib/b2/xparser.x"
    i = (i + 1);
        {
        rt_release(f);
        }
        {
        xn_root_restore(xn_t849);
        }

    xn_gc_safepoint();
    }
#line 784 "impl/lib/b2/xparser.x"
rt_string *xn_t865 = rt_retain(r);
xn_root_add(xn_t865);
xn_root_add(xn_t865);
rt_string *xn_t866 = rt_string_from_c(")");
xn_root_add(xn_t866);
xn_root_add(xn_t866);
rt_string *xn_t867 = xn_concat(xn_t865, xn_t866);
xn_root_add(xn_t867);
xn_root_add(xn_t867);
    {
rt_release(r);
    }
    {
xn_root_restore(xn_t824);
    }

return xn_t867;
xn_root_release(r);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_TP_renderField(xn_Cls_TP *self, xn_Cls_TN * xn_p_v, int64_t xn_p_cd, rt_string * xn_p_cat) {
size_t xn_t868 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_v);
xn_root_add(xn_p_cat);
#line 788 "impl/lib/b2/xparser.x"
    if (((xn_p_cd > 100000))) {
        size_t xn_t869 = xn_root_mark();
        #line 788 "impl/lib/b2/xparser.x"
        rt_string *xn_t870 = rt_string_from_c("(depth-limit)");
xn_root_add(xn_t870);
        xn_root_add(xn_t870);
        xn_root_add(xn_t870);
            {
        xn_root_restore(xn_t869);
            }
            {
        xn_root_restore(xn_t868);
            }

        return xn_t870;

    }
#line 789 "impl/lib/b2/xparser.x"
rt_string *xn_t871 = rt_retain(xn_p_cat);
xn_root_add(xn_t871);
rt_string *xn_t872 = rt_string_from_c("s");
xn_root_add(xn_t872);
rt_string *xn_t873 = rt_retain(xn_p_cat);
xn_root_add(xn_t873);
rt_string *xn_t874 = rt_string_from_c("v");
xn_root_add(xn_t874);
    if (((xn_str_eq(xn_t871, xn_t872)) || (xn_str_eq(xn_t873, xn_t874)))) {
        size_t xn_t875 = xn_root_mark();
        #line 789 "impl/lib/b2/xparser.x"
        rt_string *xn_t876 = xn_Cls_TP_render(self, xn_p_v, xn_p_cd);
xn_root_add(xn_t876);
        xn_root_add(xn_t876);
        xn_root_add(xn_t876);
            {
        xn_root_restore(xn_t875);
            }
            {
        xn_root_restore(xn_t868);
            }

        return xn_t876;

    }
#line 790 "impl/lib/b2/xparser.x"
rt_string *xn_t877 = rt_retain(xn_p_cat);
xn_root_add(xn_t877);
rt_string *xn_t878 = rt_string_from_c("p");
xn_root_add(xn_t878);
    if ((xn_str_eq(xn_t877, xn_t878))) {
        size_t xn_t879 = xn_root_mark();
        #line 790 "impl/lib/b2/xparser.x"
        rt_string *xn_t880 = xn_Cls_TP_render(self, xn_p_v, (xn_p_cd + 1));
xn_root_add(xn_t880);
        xn_root_add(xn_t880);
        xn_root_add(xn_t880);
            {
        xn_root_restore(xn_t879);
            }
            {
        xn_root_restore(xn_t868);
            }

        return xn_t880;

    }
#line 791 "impl/lib/b2/xparser.x"
rt_string *xn_t881 = rt_retain(xn_p_cat);
xn_root_add(xn_t881);
rt_string *xn_t882 = rt_string_from_c("i");
xn_root_add(xn_t882);
    if ((xn_str_eq(xn_t881, xn_t882))) {
        size_t xn_t883 = xn_root_mark();
        #line 791 "impl/lib/b2/xparser.x"
        rt_string *xn_t884 = xn_Cls_TP_render(self, xn_p_v, (xn_p_cd + 2));
xn_root_add(xn_t884);
        xn_root_add(xn_t884);
        xn_root_add(xn_t884);
            {
        xn_root_restore(xn_t883);
            }
            {
        xn_root_restore(xn_t868);
            }

        return xn_t884;

    }
#line 792 "impl/lib/b2/xparser.x"
rt_string *r = rt_string_from_c("(slice");
xn_root_add(r);
xn_root_add(r);
xn_gc_safepoint();
#line 793 "impl/lib/b2/xparser.x"
int64_t i = 0;
#line 794 "impl/lib/b2/xparser.x"
    while (((i < ((int64_t)xn_p_v->el->len)))) {
    size_t xn_t886 = xn_root_mark();
    #line 795 "impl/lib/b2/xparser.x"
    rt_string *xn_t887 = rt_retain(xn_p_cat);
xn_root_add(xn_t887);
    xn_root_add(xn_t887);
    rt_string *xn_t888 = rt_string_from_c("ss");
xn_root_add(xn_t888);
    xn_root_add(xn_t888);
    rt_string *xn_t889 = rt_retain(xn_p_cat);
xn_root_add(xn_t889);
    xn_root_add(xn_t889);
    rt_string *xn_t890 = rt_string_from_c("sv");
xn_root_add(xn_t890);
    xn_root_add(xn_t890);
        if (((xn_str_eq(xn_t887, xn_t888)) || (xn_str_eq(xn_t889, xn_t890)))) {
            size_t xn_t891 = xn_root_mark();
            #line 795 "impl/lib/b2/xparser.x"
            rt_string *xn_t892 = rt_retain(r);
xn_root_add(xn_t892);
    xn_root_add(xn_t892);
            xn_root_add(xn_t892);
            rt_string *xn_t893 = rt_string_from_c(" ");
xn_root_add(xn_t893);
    xn_root_add(xn_t893);
            xn_root_add(xn_t893);
            rt_string *xn_t894 = xn_concat(xn_t892, xn_t893);
xn_root_add(xn_t894);
    xn_root_add(xn_t894);
            xn_root_add(xn_t894);
            rt_string *xn_t895 = xn_Cls_TP_render(self, xn_arr_o_TN_get(xn_p_v->el, i), (xn_p_cd + 1));
xn_root_add(xn_t895);
    xn_root_add(xn_t895);
            xn_root_add(xn_t895);
            rt_string *xn_t896 = xn_concat(xn_t894, xn_t895);
xn_root_add(xn_t896);
    xn_root_add(xn_t896);
            xn_root_add(xn_t896);
            xn_root_release(r);
            rt_release(r);
            r = xn_t896;
            xn_root_hold(r);
            xn_gc_safepoint();
                {
                xn_root_restore(xn_t891);
                }

        } else {
            rt_string *xn_t898 = rt_retain(xn_p_cat);
xn_root_add(xn_t898);
    xn_root_add(xn_t898);
            xn_root_add(xn_t898);
            rt_string *xn_t899 = rt_string_from_c("sp");
xn_root_add(xn_t899);
    xn_root_add(xn_t899);
            xn_root_add(xn_t899);
                if ((xn_str_eq(xn_t898, xn_t899))) {
                    size_t xn_t900 = xn_root_mark();
                    #line 796 "impl/lib/b2/xparser.x"
                    rt_string *xn_t901 = rt_retain(r);
xn_root_add(xn_t901);
    xn_root_add(xn_t901);
            xn_root_add(xn_t901);
                    xn_root_add(xn_t901);
                    rt_string *xn_t902 = rt_string_from_c(" ");
xn_root_add(xn_t902);
    xn_root_add(xn_t902);
            xn_root_add(xn_t902);
                    xn_root_add(xn_t902);
                    rt_string *xn_t903 = xn_concat(xn_t901, xn_t902);
xn_root_add(xn_t903);
    xn_root_add(xn_t903);
            xn_root_add(xn_t903);
                    xn_root_add(xn_t903);
                    rt_string *xn_t904 = xn_Cls_TP_render(self, xn_arr_o_TN_get(xn_p_v->el, i), (xn_p_cd + 2));
xn_root_add(xn_t904);
    xn_root_add(xn_t904);
            xn_root_add(xn_t904);
                    xn_root_add(xn_t904);
                    rt_string *xn_t905 = xn_concat(xn_t903, xn_t904);
xn_root_add(xn_t905);
    xn_root_add(xn_t905);
            xn_root_add(xn_t905);
                    xn_root_add(xn_t905);
                    xn_root_release(r);
                    rt_release(r);
                    r = xn_t905;
                    xn_root_hold(r);
                    xn_gc_safepoint();
                        {
                        xn_root_restore(xn_t900);
                        }

                } else {
                    rt_string *xn_t907 = rt_retain(xn_p_cat);
xn_root_add(xn_t907);
    xn_root_add(xn_t907);
            xn_root_add(xn_t907);
                    xn_root_add(xn_t907);
                    rt_string *xn_t908 = rt_string_from_c("si");
xn_root_add(xn_t908);
    xn_root_add(xn_t908);
            xn_root_add(xn_t908);
                    xn_root_add(xn_t908);
                        if ((xn_str_eq(xn_t907, xn_t908))) {
                            size_t xn_t909 = xn_root_mark();
                            #line 797 "impl/lib/b2/xparser.x"
                            rt_string *xn_t910 = rt_retain(r);
xn_root_add(xn_t910);
    xn_root_add(xn_t910);
            xn_root_add(xn_t910);
                    xn_root_add(xn_t910);
                            xn_root_add(xn_t910);
                            rt_string *xn_t911 = rt_string_from_c(" ");
xn_root_add(xn_t911);
    xn_root_add(xn_t911);
            xn_root_add(xn_t911);
                    xn_root_add(xn_t911);
                            xn_root_add(xn_t911);
                            rt_string *xn_t912 = xn_concat(xn_t910, xn_t911);
xn_root_add(xn_t912);
    xn_root_add(xn_t912);
            xn_root_add(xn_t912);
                    xn_root_add(xn_t912);
                            xn_root_add(xn_t912);
                            rt_string *xn_t913 = xn_Cls_TP_render(self, xn_arr_o_TN_get(xn_p_v->el, i), (xn_p_cd + 3));
xn_root_add(xn_t913);
    xn_root_add(xn_t913);
            xn_root_add(xn_t913);
                    xn_root_add(xn_t913);
                            xn_root_add(xn_t913);
                            rt_string *xn_t914 = xn_concat(xn_t912, xn_t913);
xn_root_add(xn_t914);
    xn_root_add(xn_t914);
            xn_root_add(xn_t914);
                    xn_root_add(xn_t914);
                            xn_root_add(xn_t914);
                            xn_root_release(r);
                            rt_release(r);
                            r = xn_t914;
                            xn_root_hold(r);
                            xn_gc_safepoint();
                                {
                                xn_root_restore(xn_t909);
                                }

                        }
                }
        }
    #line 798 "impl/lib/b2/xparser.x"
    i = (i + 1);
        {
        xn_root_restore(xn_t886);
        }

    xn_gc_safepoint();
    }
#line 800 "impl/lib/b2/xparser.x"
rt_string *xn_t915 = rt_retain(r);
xn_root_add(xn_t915);
xn_root_add(xn_t915);
rt_string *xn_t916 = rt_string_from_c(")");
xn_root_add(xn_t916);
xn_root_add(xn_t916);
rt_string *xn_t917 = xn_concat(xn_t915, xn_t916);
xn_root_add(xn_t917);
xn_root_add(xn_t917);
    {
rt_release(r);
    }
    {
xn_root_restore(xn_t868);
    }

return xn_t917;
xn_root_release(r);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_TP_fcat(xn_Cls_TP *self, rt_string * xn_p_nd, rt_string * xn_p_f) {
size_t xn_t918 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_nd);
xn_root_add(xn_p_f);
#line 804 "impl/lib/b2/xparser.x"
rt_string *xn_t919 = rt_retain(xn_p_nd);
xn_root_add(xn_t919);
rt_string *xn_t920 = rt_string_from_c(".");
xn_root_add(xn_t920);
rt_string *xn_t921 = xn_concat(xn_t919, xn_t920);
xn_root_add(xn_t921);
rt_string *xn_t922 = rt_retain(xn_p_f);
xn_root_add(xn_t922);
rt_string *k = xn_concat(xn_t921, xn_t922);
xn_root_add(k);
xn_root_add(k);
xn_gc_safepoint();
#line 805 "impl/lib/b2/xparser.x"
rt_string *xn_t924 = rt_retain(k);
xn_root_add(xn_t924);
rt_string *xn_t925 = rt_string_from_c("AnnotationDecl.Annos");
xn_root_add(xn_t925);
    if ((xn_str_eq(xn_t924, xn_t925))) {
        size_t xn_t926 = xn_root_mark();
        #line 805 "impl/lib/b2/xparser.x"
        rt_string *xn_t927 = rt_string_from_c("sp");
xn_root_add(xn_t927);
        xn_root_add(xn_t927);
        xn_root_add(xn_t927);
            {
        xn_root_restore(xn_t926);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t927;

    }
#line 806 "impl/lib/b2/xparser.x"
rt_string *xn_t928 = rt_retain(k);
xn_root_add(xn_t928);
rt_string *xn_t929 = rt_string_from_c("AnnotationDecl.Fields");
xn_root_add(xn_t929);
    if ((xn_str_eq(xn_t928, xn_t929))) {
        size_t xn_t930 = xn_root_mark();
        #line 806 "impl/lib/b2/xparser.x"
        rt_string *xn_t931 = rt_string_from_c("sp");
xn_root_add(xn_t931);
        xn_root_add(xn_t931);
        xn_root_add(xn_t931);
            {
        xn_root_restore(xn_t930);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t931;

    }
#line 807 "impl/lib/b2/xparser.x"
rt_string *xn_t932 = rt_retain(k);
xn_root_add(xn_t932);
rt_string *xn_t933 = rt_string_from_c("AnnotationDecl.Mod");
xn_root_add(xn_t933);
    if ((xn_str_eq(xn_t932, xn_t933))) {
        size_t xn_t934 = xn_root_mark();
        #line 807 "impl/lib/b2/xparser.x"
        rt_string *xn_t935 = rt_string_from_c("v");
xn_root_add(xn_t935);
        xn_root_add(xn_t935);
        xn_root_add(xn_t935);
            {
        xn_root_restore(xn_t934);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t935;

    }
#line 808 "impl/lib/b2/xparser.x"
rt_string *xn_t936 = rt_retain(k);
xn_root_add(xn_t936);
rt_string *xn_t937 = rt_string_from_c("AnnotationDecl.Name");
xn_root_add(xn_t937);
    if ((xn_str_eq(xn_t936, xn_t937))) {
        size_t xn_t938 = xn_root_mark();
        #line 808 "impl/lib/b2/xparser.x"
        rt_string *xn_t939 = rt_string_from_c("s");
xn_root_add(xn_t939);
        xn_root_add(xn_t939);
        xn_root_add(xn_t939);
            {
        xn_root_restore(xn_t938);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t939;

    }
#line 809 "impl/lib/b2/xparser.x"
rt_string *xn_t940 = rt_retain(k);
xn_root_add(xn_t940);
rt_string *xn_t941 = rt_string_from_c("AnnotationDecl.P");
xn_root_add(xn_t941);
    if ((xn_str_eq(xn_t940, xn_t941))) {
        size_t xn_t942 = xn_root_mark();
        #line 809 "impl/lib/b2/xparser.x"
        rt_string *xn_t943 = rt_string_from_c("v");
xn_root_add(xn_t943);
        xn_root_add(xn_t943);
        xn_root_add(xn_t943);
            {
        xn_root_restore(xn_t942);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t943;

    }
#line 810 "impl/lib/b2/xparser.x"
rt_string *xn_t944 = rt_retain(k);
xn_root_add(xn_t944);
rt_string *xn_t945 = rt_string_from_c("AnnotationNode.Args");
xn_root_add(xn_t945);
    if ((xn_str_eq(xn_t944, xn_t945))) {
        size_t xn_t946 = xn_root_mark();
        #line 810 "impl/lib/b2/xparser.x"
        rt_string *xn_t947 = rt_string_from_c("si");
xn_root_add(xn_t947);
        xn_root_add(xn_t947);
        xn_root_add(xn_t947);
            {
        xn_root_restore(xn_t946);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t947;

    }
#line 811 "impl/lib/b2/xparser.x"
rt_string *xn_t948 = rt_retain(k);
xn_root_add(xn_t948);
rt_string *xn_t949 = rt_string_from_c("AnnotationNode.Name");
xn_root_add(xn_t949);
    if ((xn_str_eq(xn_t948, xn_t949))) {
        size_t xn_t950 = xn_root_mark();
        #line 811 "impl/lib/b2/xparser.x"
        rt_string *xn_t951 = rt_string_from_c("s");
xn_root_add(xn_t951);
        xn_root_add(xn_t951);
        xn_root_add(xn_t951);
            {
        xn_root_restore(xn_t950);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t951;

    }
#line 812 "impl/lib/b2/xparser.x"
rt_string *xn_t952 = rt_retain(k);
xn_root_add(xn_t952);
rt_string *xn_t953 = rt_string_from_c("AnnotationNode.P");
xn_root_add(xn_t953);
    if ((xn_str_eq(xn_t952, xn_t953))) {
        size_t xn_t954 = xn_root_mark();
        #line 812 "impl/lib/b2/xparser.x"
        rt_string *xn_t955 = rt_string_from_c("v");
xn_root_add(xn_t955);
        xn_root_add(xn_t955);
        xn_root_add(xn_t955);
            {
        xn_root_restore(xn_t954);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t955;

    }
#line 813 "impl/lib/b2/xparser.x"
rt_string *xn_t956 = rt_retain(k);
xn_root_add(xn_t956);
rt_string *xn_t957 = rt_string_from_c("ArrayLit.Elems");
xn_root_add(xn_t957);
    if ((xn_str_eq(xn_t956, xn_t957))) {
        size_t xn_t958 = xn_root_mark();
        #line 813 "impl/lib/b2/xparser.x"
        rt_string *xn_t959 = rt_string_from_c("si");
xn_root_add(xn_t959);
        xn_root_add(xn_t959);
        xn_root_add(xn_t959);
            {
        xn_root_restore(xn_t958);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t959;

    }
#line 814 "impl/lib/b2/xparser.x"
rt_string *xn_t960 = rt_retain(k);
xn_root_add(xn_t960);
rt_string *xn_t961 = rt_string_from_c("ArrayLit.P");
xn_root_add(xn_t961);
    if ((xn_str_eq(xn_t960, xn_t961))) {
        size_t xn_t962 = xn_root_mark();
        #line 814 "impl/lib/b2/xparser.x"
        rt_string *xn_t963 = rt_string_from_c("v");
xn_root_add(xn_t963);
        xn_root_add(xn_t963);
        xn_root_add(xn_t963);
            {
        xn_root_restore(xn_t962);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t963;

    }
#line 815 "impl/lib/b2/xparser.x"
rt_string *xn_t964 = rt_retain(k);
xn_root_add(xn_t964);
rt_string *xn_t965 = rt_string_from_c("AssignStmt.Op");
xn_root_add(xn_t965);
    if ((xn_str_eq(xn_t964, xn_t965))) {
        size_t xn_t966 = xn_root_mark();
        #line 815 "impl/lib/b2/xparser.x"
        rt_string *xn_t967 = rt_string_from_c("s");
xn_root_add(xn_t967);
        xn_root_add(xn_t967);
        xn_root_add(xn_t967);
            {
        xn_root_restore(xn_t966);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t967;

    }
#line 816 "impl/lib/b2/xparser.x"
rt_string *xn_t968 = rt_retain(k);
xn_root_add(xn_t968);
rt_string *xn_t969 = rt_string_from_c("AssignStmt.P");
xn_root_add(xn_t969);
    if ((xn_str_eq(xn_t968, xn_t969))) {
        size_t xn_t970 = xn_root_mark();
        #line 816 "impl/lib/b2/xparser.x"
        rt_string *xn_t971 = rt_string_from_c("v");
xn_root_add(xn_t971);
        xn_root_add(xn_t971);
        xn_root_add(xn_t971);
            {
        xn_root_restore(xn_t970);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t971;

    }
#line 817 "impl/lib/b2/xparser.x"
rt_string *xn_t972 = rt_retain(k);
xn_root_add(xn_t972);
rt_string *xn_t973 = rt_string_from_c("AssignStmt.Target");
xn_root_add(xn_t973);
    if ((xn_str_eq(xn_t972, xn_t973))) {
        size_t xn_t974 = xn_root_mark();
        #line 817 "impl/lib/b2/xparser.x"
        rt_string *xn_t975 = rt_string_from_c("i");
xn_root_add(xn_t975);
        xn_root_add(xn_t975);
        xn_root_add(xn_t975);
            {
        xn_root_restore(xn_t974);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t975;

    }
#line 818 "impl/lib/b2/xparser.x"
rt_string *xn_t976 = rt_retain(k);
xn_root_add(xn_t976);
rt_string *xn_t977 = rt_string_from_c("AssignStmt.Value");
xn_root_add(xn_t977);
    if ((xn_str_eq(xn_t976, xn_t977))) {
        size_t xn_t978 = xn_root_mark();
        #line 818 "impl/lib/b2/xparser.x"
        rt_string *xn_t979 = rt_string_from_c("i");
xn_root_add(xn_t979);
        xn_root_add(xn_t979);
        xn_root_add(xn_t979);
            {
        xn_root_restore(xn_t978);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t979;

    }
#line 819 "impl/lib/b2/xparser.x"
rt_string *xn_t980 = rt_retain(k);
xn_root_add(xn_t980);
rt_string *xn_t981 = rt_string_from_c("Binary.L");
xn_root_add(xn_t981);
    if ((xn_str_eq(xn_t980, xn_t981))) {
        size_t xn_t982 = xn_root_mark();
        #line 819 "impl/lib/b2/xparser.x"
        rt_string *xn_t983 = rt_string_from_c("i");
xn_root_add(xn_t983);
        xn_root_add(xn_t983);
        xn_root_add(xn_t983);
            {
        xn_root_restore(xn_t982);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t983;

    }
#line 820 "impl/lib/b2/xparser.x"
rt_string *xn_t984 = rt_retain(k);
xn_root_add(xn_t984);
rt_string *xn_t985 = rt_string_from_c("Binary.Op");
xn_root_add(xn_t985);
    if ((xn_str_eq(xn_t984, xn_t985))) {
        size_t xn_t986 = xn_root_mark();
        #line 820 "impl/lib/b2/xparser.x"
        rt_string *xn_t987 = rt_string_from_c("s");
xn_root_add(xn_t987);
        xn_root_add(xn_t987);
        xn_root_add(xn_t987);
            {
        xn_root_restore(xn_t986);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t987;

    }
#line 821 "impl/lib/b2/xparser.x"
rt_string *xn_t988 = rt_retain(k);
xn_root_add(xn_t988);
rt_string *xn_t989 = rt_string_from_c("Binary.P");
xn_root_add(xn_t989);
    if ((xn_str_eq(xn_t988, xn_t989))) {
        size_t xn_t990 = xn_root_mark();
        #line 821 "impl/lib/b2/xparser.x"
        rt_string *xn_t991 = rt_string_from_c("v");
xn_root_add(xn_t991);
        xn_root_add(xn_t991);
        xn_root_add(xn_t991);
            {
        xn_root_restore(xn_t990);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t991;

    }
#line 822 "impl/lib/b2/xparser.x"
rt_string *xn_t992 = rt_retain(k);
xn_root_add(xn_t992);
rt_string *xn_t993 = rt_string_from_c("Binary.R");
xn_root_add(xn_t993);
    if ((xn_str_eq(xn_t992, xn_t993))) {
        size_t xn_t994 = xn_root_mark();
        #line 822 "impl/lib/b2/xparser.x"
        rt_string *xn_t995 = rt_string_from_c("i");
xn_root_add(xn_t995);
        xn_root_add(xn_t995);
        xn_root_add(xn_t995);
            {
        xn_root_restore(xn_t994);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t995;

    }
#line 823 "impl/lib/b2/xparser.x"
rt_string *xn_t996 = rt_retain(k);
xn_root_add(xn_t996);
rt_string *xn_t997 = rt_string_from_c("Block.P");
xn_root_add(xn_t997);
    if ((xn_str_eq(xn_t996, xn_t997))) {
        size_t xn_t998 = xn_root_mark();
        #line 823 "impl/lib/b2/xparser.x"
        rt_string *xn_t999 = rt_string_from_c("v");
xn_root_add(xn_t999);
        xn_root_add(xn_t999);
        xn_root_add(xn_t999);
            {
        xn_root_restore(xn_t998);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t999;

    }
#line 824 "impl/lib/b2/xparser.x"
rt_string *xn_t1000 = rt_retain(k);
xn_root_add(xn_t1000);
rt_string *xn_t1001 = rt_string_from_c("Block.Stmts");
xn_root_add(xn_t1001);
    if ((xn_str_eq(xn_t1000, xn_t1001))) {
        size_t xn_t1002 = xn_root_mark();
        #line 824 "impl/lib/b2/xparser.x"
        rt_string *xn_t1003 = rt_string_from_c("si");
xn_root_add(xn_t1003);
        xn_root_add(xn_t1003);
        xn_root_add(xn_t1003);
            {
        xn_root_restore(xn_t1002);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1003;

    }
#line 825 "impl/lib/b2/xparser.x"
rt_string *xn_t1004 = rt_retain(k);
xn_root_add(xn_t1004);
rt_string *xn_t1005 = rt_string_from_c("BoolLit.P");
xn_root_add(xn_t1005);
    if ((xn_str_eq(xn_t1004, xn_t1005))) {
        size_t xn_t1006 = xn_root_mark();
        #line 825 "impl/lib/b2/xparser.x"
        rt_string *xn_t1007 = rt_string_from_c("v");
xn_root_add(xn_t1007);
        xn_root_add(xn_t1007);
        xn_root_add(xn_t1007);
            {
        xn_root_restore(xn_t1006);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1007;

    }
#line 826 "impl/lib/b2/xparser.x"
rt_string *xn_t1008 = rt_retain(k);
xn_root_add(xn_t1008);
rt_string *xn_t1009 = rt_string_from_c("BoolLit.V");
xn_root_add(xn_t1009);
    if ((xn_str_eq(xn_t1008, xn_t1009))) {
        size_t xn_t1010 = xn_root_mark();
        #line 826 "impl/lib/b2/xparser.x"
        rt_string *xn_t1011 = rt_string_from_c("s");
xn_root_add(xn_t1011);
        xn_root_add(xn_t1011);
        xn_root_add(xn_t1011);
            {
        xn_root_restore(xn_t1010);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1011;

    }
#line 827 "impl/lib/b2/xparser.x"
rt_string *xn_t1012 = rt_retain(k);
xn_root_add(xn_t1012);
rt_string *xn_t1013 = rt_string_from_c("BreakStmt.Label");
xn_root_add(xn_t1013);
    if ((xn_str_eq(xn_t1012, xn_t1013))) {
        size_t xn_t1014 = xn_root_mark();
        #line 827 "impl/lib/b2/xparser.x"
        rt_string *xn_t1015 = rt_string_from_c("s");
xn_root_add(xn_t1015);
        xn_root_add(xn_t1015);
        xn_root_add(xn_t1015);
            {
        xn_root_restore(xn_t1014);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1015;

    }
#line 828 "impl/lib/b2/xparser.x"
rt_string *xn_t1016 = rt_retain(k);
xn_root_add(xn_t1016);
rt_string *xn_t1017 = rt_string_from_c("BreakStmt.P");
xn_root_add(xn_t1017);
    if ((xn_str_eq(xn_t1016, xn_t1017))) {
        size_t xn_t1018 = xn_root_mark();
        #line 828 "impl/lib/b2/xparser.x"
        rt_string *xn_t1019 = rt_string_from_c("v");
xn_root_add(xn_t1019);
        xn_root_add(xn_t1019);
        xn_root_add(xn_t1019);
            {
        xn_root_restore(xn_t1018);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1019;

    }
#line 829 "impl/lib/b2/xparser.x"
rt_string *xn_t1020 = rt_retain(k);
xn_root_add(xn_t1020);
rt_string *xn_t1021 = rt_string_from_c("Call.Args");
xn_root_add(xn_t1021);
    if ((xn_str_eq(xn_t1020, xn_t1021))) {
        size_t xn_t1022 = xn_root_mark();
        #line 829 "impl/lib/b2/xparser.x"
        rt_string *xn_t1023 = rt_string_from_c("si");
xn_root_add(xn_t1023);
        xn_root_add(xn_t1023);
        xn_root_add(xn_t1023);
            {
        xn_root_restore(xn_t1022);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1023;

    }
#line 830 "impl/lib/b2/xparser.x"
rt_string *xn_t1024 = rt_retain(k);
xn_root_add(xn_t1024);
rt_string *xn_t1025 = rt_string_from_c("Call.Callee");
xn_root_add(xn_t1025);
    if ((xn_str_eq(xn_t1024, xn_t1025))) {
        size_t xn_t1026 = xn_root_mark();
        #line 830 "impl/lib/b2/xparser.x"
        rt_string *xn_t1027 = rt_string_from_c("i");
xn_root_add(xn_t1027);
        xn_root_add(xn_t1027);
        xn_root_add(xn_t1027);
            {
        xn_root_restore(xn_t1026);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1027;

    }
#line 831 "impl/lib/b2/xparser.x"
rt_string *xn_t1028 = rt_retain(k);
xn_root_add(xn_t1028);
rt_string *xn_t1029 = rt_string_from_c("Call.P");
xn_root_add(xn_t1029);
    if ((xn_str_eq(xn_t1028, xn_t1029))) {
        size_t xn_t1030 = xn_root_mark();
        #line 831 "impl/lib/b2/xparser.x"
        rt_string *xn_t1031 = rt_string_from_c("v");
xn_root_add(xn_t1031);
        xn_root_add(xn_t1031);
        xn_root_add(xn_t1031);
            {
        xn_root_restore(xn_t1030);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1031;

    }
#line 832 "impl/lib/b2/xparser.x"
rt_string *xn_t1032 = rt_retain(k);
xn_root_add(xn_t1032);
rt_string *xn_t1033 = rt_string_from_c("Call.TypeArgs");
xn_root_add(xn_t1033);
    if ((xn_str_eq(xn_t1032, xn_t1033))) {
        size_t xn_t1034 = xn_root_mark();
        #line 832 "impl/lib/b2/xparser.x"
        rt_string *xn_t1035 = rt_string_from_c("si");
xn_root_add(xn_t1035);
        xn_root_add(xn_t1035);
        xn_root_add(xn_t1035);
            {
        xn_root_restore(xn_t1034);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1035;

    }
#line 833 "impl/lib/b2/xparser.x"
rt_string *xn_t1036 = rt_retain(k);
xn_root_add(xn_t1036);
rt_string *xn_t1037 = rt_string_from_c("CharLitExpr.P");
xn_root_add(xn_t1037);
    if ((xn_str_eq(xn_t1036, xn_t1037))) {
        size_t xn_t1038 = xn_root_mark();
        #line 833 "impl/lib/b2/xparser.x"
        rt_string *xn_t1039 = rt_string_from_c("v");
xn_root_add(xn_t1039);
        xn_root_add(xn_t1039);
        xn_root_add(xn_t1039);
            {
        xn_root_restore(xn_t1038);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1039;

    }
#line 834 "impl/lib/b2/xparser.x"
rt_string *xn_t1040 = rt_retain(k);
xn_root_add(xn_t1040);
rt_string *xn_t1041 = rt_string_from_c("CharLitExpr.Rune");
xn_root_add(xn_t1041);
    if ((xn_str_eq(xn_t1040, xn_t1041))) {
        size_t xn_t1042 = xn_root_mark();
        #line 834 "impl/lib/b2/xparser.x"
        rt_string *xn_t1043 = rt_string_from_c("s");
xn_root_add(xn_t1043);
        xn_root_add(xn_t1043);
        xn_root_add(xn_t1043);
            {
        xn_root_restore(xn_t1042);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1043;

    }
#line 835 "impl/lib/b2/xparser.x"
rt_string *xn_t1044 = rt_retain(k);
xn_root_add(xn_t1044);
rt_string *xn_t1045 = rt_string_from_c("ClassDecl.Annos");
xn_root_add(xn_t1045);
    if ((xn_str_eq(xn_t1044, xn_t1045))) {
        size_t xn_t1046 = xn_root_mark();
        #line 835 "impl/lib/b2/xparser.x"
        rt_string *xn_t1047 = rt_string_from_c("sp");
xn_root_add(xn_t1047);
        xn_root_add(xn_t1047);
        xn_root_add(xn_t1047);
            {
        xn_root_restore(xn_t1046);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1047;

    }
#line 836 "impl/lib/b2/xparser.x"
rt_string *xn_t1048 = rt_retain(k);
xn_root_add(xn_t1048);
rt_string *xn_t1049 = rt_string_from_c("ClassDecl.Base");
xn_root_add(xn_t1049);
    if ((xn_str_eq(xn_t1048, xn_t1049))) {
        size_t xn_t1050 = xn_root_mark();
        #line 836 "impl/lib/b2/xparser.x"
        rt_string *xn_t1051 = rt_string_from_c("i");
xn_root_add(xn_t1051);
        xn_root_add(xn_t1051);
        xn_root_add(xn_t1051);
            {
        xn_root_restore(xn_t1050);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1051;

    }
#line 837 "impl/lib/b2/xparser.x"
rt_string *xn_t1052 = rt_retain(k);
xn_root_add(xn_t1052);
rt_string *xn_t1053 = rt_string_from_c("ClassDecl.Ctors");
xn_root_add(xn_t1053);
    if ((xn_str_eq(xn_t1052, xn_t1053))) {
        size_t xn_t1054 = xn_root_mark();
        #line 837 "impl/lib/b2/xparser.x"
        rt_string *xn_t1055 = rt_string_from_c("sp");
xn_root_add(xn_t1055);
        xn_root_add(xn_t1055);
        xn_root_add(xn_t1055);
            {
        xn_root_restore(xn_t1054);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1055;

    }
#line 838 "impl/lib/b2/xparser.x"
rt_string *xn_t1056 = rt_retain(k);
xn_root_add(xn_t1056);
rt_string *xn_t1057 = rt_string_from_c("ClassDecl.Fields");
xn_root_add(xn_t1057);
    if ((xn_str_eq(xn_t1056, xn_t1057))) {
        size_t xn_t1058 = xn_root_mark();
        #line 838 "impl/lib/b2/xparser.x"
        rt_string *xn_t1059 = rt_string_from_c("sp");
xn_root_add(xn_t1059);
        xn_root_add(xn_t1059);
        xn_root_add(xn_t1059);
            {
        xn_root_restore(xn_t1058);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1059;

    }
#line 839 "impl/lib/b2/xparser.x"
rt_string *xn_t1060 = rt_retain(k);
xn_root_add(xn_t1060);
rt_string *xn_t1061 = rt_string_from_c("ClassDecl.Methods");
xn_root_add(xn_t1061);
    if ((xn_str_eq(xn_t1060, xn_t1061))) {
        size_t xn_t1062 = xn_root_mark();
        #line 839 "impl/lib/b2/xparser.x"
        rt_string *xn_t1063 = rt_string_from_c("sp");
xn_root_add(xn_t1063);
        xn_root_add(xn_t1063);
        xn_root_add(xn_t1063);
            {
        xn_root_restore(xn_t1062);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1063;

    }
#line 840 "impl/lib/b2/xparser.x"
rt_string *xn_t1064 = rt_retain(k);
xn_root_add(xn_t1064);
rt_string *xn_t1065 = rt_string_from_c("ClassDecl.Mod");
xn_root_add(xn_t1065);
    if ((xn_str_eq(xn_t1064, xn_t1065))) {
        size_t xn_t1066 = xn_root_mark();
        #line 840 "impl/lib/b2/xparser.x"
        rt_string *xn_t1067 = rt_string_from_c("v");
xn_root_add(xn_t1067);
        xn_root_add(xn_t1067);
        xn_root_add(xn_t1067);
            {
        xn_root_restore(xn_t1066);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1067;

    }
#line 841 "impl/lib/b2/xparser.x"
rt_string *xn_t1068 = rt_retain(k);
xn_root_add(xn_t1068);
rt_string *xn_t1069 = rt_string_from_c("ClassDecl.Name");
xn_root_add(xn_t1069);
    if ((xn_str_eq(xn_t1068, xn_t1069))) {
        size_t xn_t1070 = xn_root_mark();
        #line 841 "impl/lib/b2/xparser.x"
        rt_string *xn_t1071 = rt_string_from_c("s");
xn_root_add(xn_t1071);
        xn_root_add(xn_t1071);
        xn_root_add(xn_t1071);
            {
        xn_root_restore(xn_t1070);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1071;

    }
#line 842 "impl/lib/b2/xparser.x"
rt_string *xn_t1072 = rt_retain(k);
xn_root_add(xn_t1072);
rt_string *xn_t1073 = rt_string_from_c("ClassDecl.P");
xn_root_add(xn_t1073);
    if ((xn_str_eq(xn_t1072, xn_t1073))) {
        size_t xn_t1074 = xn_root_mark();
        #line 842 "impl/lib/b2/xparser.x"
        rt_string *xn_t1075 = rt_string_from_c("v");
xn_root_add(xn_t1075);
        xn_root_add(xn_t1075);
        xn_root_add(xn_t1075);
            {
        xn_root_restore(xn_t1074);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1075;

    }
#line 843 "impl/lib/b2/xparser.x"
rt_string *xn_t1076 = rt_retain(k);
xn_root_add(xn_t1076);
rt_string *xn_t1077 = rt_string_from_c("ClassDecl.Primary");
xn_root_add(xn_t1077);
    if ((xn_str_eq(xn_t1076, xn_t1077))) {
        size_t xn_t1078 = xn_root_mark();
        #line 843 "impl/lib/b2/xparser.x"
        rt_string *xn_t1079 = rt_string_from_c("p");
xn_root_add(xn_t1079);
        xn_root_add(xn_t1079);
        xn_root_add(xn_t1079);
            {
        xn_root_restore(xn_t1078);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1079;

    }
#line 844 "impl/lib/b2/xparser.x"
rt_string *xn_t1080 = rt_retain(k);
xn_root_add(xn_t1080);
rt_string *xn_t1081 = rt_string_from_c("ClassDecl.Protocols");
xn_root_add(xn_t1081);
    if ((xn_str_eq(xn_t1080, xn_t1081))) {
        size_t xn_t1082 = xn_root_mark();
        #line 844 "impl/lib/b2/xparser.x"
        rt_string *xn_t1083 = rt_string_from_c("sp");
xn_root_add(xn_t1083);
        xn_root_add(xn_t1083);
        xn_root_add(xn_t1083);
            {
        xn_root_restore(xn_t1082);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1083;

    }
#line 845 "impl/lib/b2/xparser.x"
rt_string *xn_t1084 = rt_retain(k);
xn_root_add(xn_t1084);
rt_string *xn_t1085 = rt_string_from_c("ClassDecl.TypePars");
xn_root_add(xn_t1085);
    if ((xn_str_eq(xn_t1084, xn_t1085))) {
        size_t xn_t1086 = xn_root_mark();
        #line 845 "impl/lib/b2/xparser.x"
        rt_string *xn_t1087 = rt_string_from_c("ss");
xn_root_add(xn_t1087);
        xn_root_add(xn_t1087);
        xn_root_add(xn_t1087);
            {
        xn_root_restore(xn_t1086);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1087;

    }
#line 846 "impl/lib/b2/xparser.x"
rt_string *xn_t1088 = rt_retain(k);
xn_root_add(xn_t1088);
rt_string *xn_t1089 = rt_string_from_c("CompilationUnit.Decls");
xn_root_add(xn_t1089);
    if ((xn_str_eq(xn_t1088, xn_t1089))) {
        size_t xn_t1090 = xn_root_mark();
        #line 846 "impl/lib/b2/xparser.x"
        rt_string *xn_t1091 = rt_string_from_c("si");
xn_root_add(xn_t1091);
        xn_root_add(xn_t1091);
        xn_root_add(xn_t1091);
            {
        xn_root_restore(xn_t1090);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1091;

    }
#line 847 "impl/lib/b2/xparser.x"
rt_string *xn_t1092 = rt_retain(k);
xn_root_add(xn_t1092);
rt_string *xn_t1093 = rt_string_from_c("CompilationUnit.Imports");
xn_root_add(xn_t1093);
    if ((xn_str_eq(xn_t1092, xn_t1093))) {
        size_t xn_t1094 = xn_root_mark();
        #line 847 "impl/lib/b2/xparser.x"
        rt_string *xn_t1095 = rt_string_from_c("sp");
xn_root_add(xn_t1095);
        xn_root_add(xn_t1095);
        xn_root_add(xn_t1095);
            {
        xn_root_restore(xn_t1094);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1095;

    }
#line 848 "impl/lib/b2/xparser.x"
rt_string *xn_t1096 = rt_retain(k);
xn_root_add(xn_t1096);
rt_string *xn_t1097 = rt_string_from_c("CompilationUnit.P");
xn_root_add(xn_t1097);
    if ((xn_str_eq(xn_t1096, xn_t1097))) {
        size_t xn_t1098 = xn_root_mark();
        #line 848 "impl/lib/b2/xparser.x"
        rt_string *xn_t1099 = rt_string_from_c("v");
xn_root_add(xn_t1099);
        xn_root_add(xn_t1099);
        xn_root_add(xn_t1099);
            {
        xn_root_restore(xn_t1098);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1099;

    }
#line 849 "impl/lib/b2/xparser.x"
rt_string *xn_t1100 = rt_retain(k);
xn_root_add(xn_t1100);
rt_string *xn_t1101 = rt_string_from_c("CompilationUnit.Package");
xn_root_add(xn_t1101);
    if ((xn_str_eq(xn_t1100, xn_t1101))) {
        size_t xn_t1102 = xn_root_mark();
        #line 849 "impl/lib/b2/xparser.x"
        rt_string *xn_t1103 = rt_string_from_c("p");
xn_root_add(xn_t1103);
        xn_root_add(xn_t1103);
        xn_root_add(xn_t1103);
            {
        xn_root_restore(xn_t1102);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1103;

    }
#line 850 "impl/lib/b2/xparser.x"
rt_string *xn_t1104 = rt_retain(k);
xn_root_add(xn_t1104);
rt_string *xn_t1105 = rt_string_from_c("ContinueStmt.Label");
xn_root_add(xn_t1105);
    if ((xn_str_eq(xn_t1104, xn_t1105))) {
        size_t xn_t1106 = xn_root_mark();
        #line 850 "impl/lib/b2/xparser.x"
        rt_string *xn_t1107 = rt_string_from_c("s");
xn_root_add(xn_t1107);
        xn_root_add(xn_t1107);
        xn_root_add(xn_t1107);
            {
        xn_root_restore(xn_t1106);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1107;

    }
#line 851 "impl/lib/b2/xparser.x"
rt_string *xn_t1108 = rt_retain(k);
xn_root_add(xn_t1108);
rt_string *xn_t1109 = rt_string_from_c("ContinueStmt.P");
xn_root_add(xn_t1109);
    if ((xn_str_eq(xn_t1108, xn_t1109))) {
        size_t xn_t1110 = xn_root_mark();
        #line 851 "impl/lib/b2/xparser.x"
        rt_string *xn_t1111 = rt_string_from_c("v");
xn_root_add(xn_t1111);
        xn_root_add(xn_t1111);
        xn_root_add(xn_t1111);
            {
        xn_root_restore(xn_t1110);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1111;

    }
#line 852 "impl/lib/b2/xparser.x"
rt_string *xn_t1112 = rt_retain(k);
xn_root_add(xn_t1112);
rt_string *xn_t1113 = rt_string_from_c("CtorDecl.Annos");
xn_root_add(xn_t1113);
    if ((xn_str_eq(xn_t1112, xn_t1113))) {
        size_t xn_t1114 = xn_root_mark();
        #line 852 "impl/lib/b2/xparser.x"
        rt_string *xn_t1115 = rt_string_from_c("sp");
xn_root_add(xn_t1115);
        xn_root_add(xn_t1115);
        xn_root_add(xn_t1115);
            {
        xn_root_restore(xn_t1114);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1115;

    }
#line 853 "impl/lib/b2/xparser.x"
rt_string *xn_t1116 = rt_retain(k);
xn_root_add(xn_t1116);
rt_string *xn_t1117 = rt_string_from_c("CtorDecl.Body");
xn_root_add(xn_t1117);
    if ((xn_str_eq(xn_t1116, xn_t1117))) {
        size_t xn_t1118 = xn_root_mark();
        #line 853 "impl/lib/b2/xparser.x"
        rt_string *xn_t1119 = rt_string_from_c("p");
xn_root_add(xn_t1119);
        xn_root_add(xn_t1119);
        xn_root_add(xn_t1119);
            {
        xn_root_restore(xn_t1118);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1119;

    }
#line 854 "impl/lib/b2/xparser.x"
rt_string *xn_t1120 = rt_retain(k);
xn_root_add(xn_t1120);
rt_string *xn_t1121 = rt_string_from_c("CtorDecl.Mod");
xn_root_add(xn_t1121);
    if ((xn_str_eq(xn_t1120, xn_t1121))) {
        size_t xn_t1122 = xn_root_mark();
        #line 854 "impl/lib/b2/xparser.x"
        rt_string *xn_t1123 = rt_string_from_c("v");
xn_root_add(xn_t1123);
        xn_root_add(xn_t1123);
        xn_root_add(xn_t1123);
            {
        xn_root_restore(xn_t1122);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1123;

    }
#line 855 "impl/lib/b2/xparser.x"
rt_string *xn_t1124 = rt_retain(k);
xn_root_add(xn_t1124);
rt_string *xn_t1125 = rt_string_from_c("CtorDecl.P");
xn_root_add(xn_t1125);
    if ((xn_str_eq(xn_t1124, xn_t1125))) {
        size_t xn_t1126 = xn_root_mark();
        #line 855 "impl/lib/b2/xparser.x"
        rt_string *xn_t1127 = rt_string_from_c("v");
xn_root_add(xn_t1127);
        xn_root_add(xn_t1127);
        xn_root_add(xn_t1127);
            {
        xn_root_restore(xn_t1126);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1127;

    }
#line 856 "impl/lib/b2/xparser.x"
rt_string *xn_t1128 = rt_retain(k);
xn_root_add(xn_t1128);
rt_string *xn_t1129 = rt_string_from_c("CtorDecl.Params");
xn_root_add(xn_t1129);
    if ((xn_str_eq(xn_t1128, xn_t1129))) {
        size_t xn_t1130 = xn_root_mark();
        #line 856 "impl/lib/b2/xparser.x"
        rt_string *xn_t1131 = rt_string_from_c("sp");
xn_root_add(xn_t1131);
        xn_root_add(xn_t1131);
        xn_root_add(xn_t1131);
            {
        xn_root_restore(xn_t1130);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1131;

    }
#line 857 "impl/lib/b2/xparser.x"
rt_string *xn_t1132 = rt_retain(k);
xn_root_add(xn_t1132);
rt_string *xn_t1133 = rt_string_from_c("DeferStmt.Block");
xn_root_add(xn_t1133);
    if ((xn_str_eq(xn_t1132, xn_t1133))) {
        size_t xn_t1134 = xn_root_mark();
        #line 857 "impl/lib/b2/xparser.x"
        rt_string *xn_t1135 = rt_string_from_c("p");
xn_root_add(xn_t1135);
        xn_root_add(xn_t1135);
        xn_root_add(xn_t1135);
            {
        xn_root_restore(xn_t1134);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1135;

    }
#line 858 "impl/lib/b2/xparser.x"
rt_string *xn_t1136 = rt_retain(k);
xn_root_add(xn_t1136);
rt_string *xn_t1137 = rt_string_from_c("DeferStmt.Errdefer");
xn_root_add(xn_t1137);
    if ((xn_str_eq(xn_t1136, xn_t1137))) {
        size_t xn_t1138 = xn_root_mark();
        #line 858 "impl/lib/b2/xparser.x"
        rt_string *xn_t1139 = rt_string_from_c("s");
xn_root_add(xn_t1139);
        xn_root_add(xn_t1139);
        xn_root_add(xn_t1139);
            {
        xn_root_restore(xn_t1138);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1139;

    }
#line 859 "impl/lib/b2/xparser.x"
rt_string *xn_t1140 = rt_retain(k);
xn_root_add(xn_t1140);
rt_string *xn_t1141 = rt_string_from_c("DeferStmt.P");
xn_root_add(xn_t1141);
    if ((xn_str_eq(xn_t1140, xn_t1141))) {
        size_t xn_t1142 = xn_root_mark();
        #line 859 "impl/lib/b2/xparser.x"
        rt_string *xn_t1143 = rt_string_from_c("v");
xn_root_add(xn_t1143);
        xn_root_add(xn_t1143);
        xn_root_add(xn_t1143);
            {
        xn_root_restore(xn_t1142);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1143;

    }
#line 860 "impl/lib/b2/xparser.x"
rt_string *xn_t1144 = rt_retain(k);
xn_root_add(xn_t1144);
rt_string *xn_t1145 = rt_string_from_c("DeferStmt.Stmt");
xn_root_add(xn_t1145);
    if ((xn_str_eq(xn_t1144, xn_t1145))) {
        size_t xn_t1146 = xn_root_mark();
        #line 860 "impl/lib/b2/xparser.x"
        rt_string *xn_t1147 = rt_string_from_c("i");
xn_root_add(xn_t1147);
        xn_root_add(xn_t1147);
        xn_root_add(xn_t1147);
            {
        xn_root_restore(xn_t1146);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1147;

    }
#line 861 "impl/lib/b2/xparser.x"
rt_string *xn_t1148 = rt_retain(k);
xn_root_add(xn_t1148);
rt_string *xn_t1149 = rt_string_from_c("DoWhileStmt.Body");
xn_root_add(xn_t1149);
    if ((xn_str_eq(xn_t1148, xn_t1149))) {
        size_t xn_t1150 = xn_root_mark();
        #line 861 "impl/lib/b2/xparser.x"
        rt_string *xn_t1151 = rt_string_from_c("p");
xn_root_add(xn_t1151);
        xn_root_add(xn_t1151);
        xn_root_add(xn_t1151);
            {
        xn_root_restore(xn_t1150);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1151;

    }
#line 862 "impl/lib/b2/xparser.x"
rt_string *xn_t1152 = rt_retain(k);
xn_root_add(xn_t1152);
rt_string *xn_t1153 = rt_string_from_c("DoWhileStmt.Cond");
xn_root_add(xn_t1153);
    if ((xn_str_eq(xn_t1152, xn_t1153))) {
        size_t xn_t1154 = xn_root_mark();
        #line 862 "impl/lib/b2/xparser.x"
        rt_string *xn_t1155 = rt_string_from_c("i");
xn_root_add(xn_t1155);
        xn_root_add(xn_t1155);
        xn_root_add(xn_t1155);
            {
        xn_root_restore(xn_t1154);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1155;

    }
#line 863 "impl/lib/b2/xparser.x"
rt_string *xn_t1156 = rt_retain(k);
xn_root_add(xn_t1156);
rt_string *xn_t1157 = rt_string_from_c("DoWhileStmt.P");
xn_root_add(xn_t1157);
    if ((xn_str_eq(xn_t1156, xn_t1157))) {
        size_t xn_t1158 = xn_root_mark();
        #line 863 "impl/lib/b2/xparser.x"
        rt_string *xn_t1159 = rt_string_from_c("v");
xn_root_add(xn_t1159);
        xn_root_add(xn_t1159);
        xn_root_add(xn_t1159);
            {
        xn_root_restore(xn_t1158);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1159;

    }
#line 864 "impl/lib/b2/xparser.x"
rt_string *xn_t1160 = rt_retain(k);
xn_root_add(xn_t1160);
rt_string *xn_t1161 = rt_string_from_c("EnumDecl.Annos");
xn_root_add(xn_t1161);
    if ((xn_str_eq(xn_t1160, xn_t1161))) {
        size_t xn_t1162 = xn_root_mark();
        #line 864 "impl/lib/b2/xparser.x"
        rt_string *xn_t1163 = rt_string_from_c("sp");
xn_root_add(xn_t1163);
        xn_root_add(xn_t1163);
        xn_root_add(xn_t1163);
            {
        xn_root_restore(xn_t1162);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1163;

    }
#line 865 "impl/lib/b2/xparser.x"
rt_string *xn_t1164 = rt_retain(k);
xn_root_add(xn_t1164);
rt_string *xn_t1165 = rt_string_from_c("EnumDecl.Ctors");
xn_root_add(xn_t1165);
    if ((xn_str_eq(xn_t1164, xn_t1165))) {
        size_t xn_t1166 = xn_root_mark();
        #line 865 "impl/lib/b2/xparser.x"
        rt_string *xn_t1167 = rt_string_from_c("sp");
xn_root_add(xn_t1167);
        xn_root_add(xn_t1167);
        xn_root_add(xn_t1167);
            {
        xn_root_restore(xn_t1166);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1167;

    }
#line 866 "impl/lib/b2/xparser.x"
rt_string *xn_t1168 = rt_retain(k);
xn_root_add(xn_t1168);
rt_string *xn_t1169 = rt_string_from_c("EnumDecl.Fields");
xn_root_add(xn_t1169);
    if ((xn_str_eq(xn_t1168, xn_t1169))) {
        size_t xn_t1170 = xn_root_mark();
        #line 866 "impl/lib/b2/xparser.x"
        rt_string *xn_t1171 = rt_string_from_c("sp");
xn_root_add(xn_t1171);
        xn_root_add(xn_t1171);
        xn_root_add(xn_t1171);
            {
        xn_root_restore(xn_t1170);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1171;

    }
#line 867 "impl/lib/b2/xparser.x"
rt_string *xn_t1172 = rt_retain(k);
xn_root_add(xn_t1172);
rt_string *xn_t1173 = rt_string_from_c("EnumDecl.IsData");
xn_root_add(xn_t1173);
    if ((xn_str_eq(xn_t1172, xn_t1173))) {
        size_t xn_t1174 = xn_root_mark();
        #line 867 "impl/lib/b2/xparser.x"
        rt_string *xn_t1175 = rt_string_from_c("s");
xn_root_add(xn_t1175);
        xn_root_add(xn_t1175);
        xn_root_add(xn_t1175);
            {
        xn_root_restore(xn_t1174);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1175;

    }
#line 868 "impl/lib/b2/xparser.x"
rt_string *xn_t1176 = rt_retain(k);
xn_root_add(xn_t1176);
rt_string *xn_t1177 = rt_string_from_c("EnumDecl.Items");
xn_root_add(xn_t1177);
    if ((xn_str_eq(xn_t1176, xn_t1177))) {
        size_t xn_t1178 = xn_root_mark();
        #line 868 "impl/lib/b2/xparser.x"
        rt_string *xn_t1179 = rt_string_from_c("sp");
xn_root_add(xn_t1179);
        xn_root_add(xn_t1179);
        xn_root_add(xn_t1179);
            {
        xn_root_restore(xn_t1178);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1179;

    }
#line 869 "impl/lib/b2/xparser.x"
rt_string *xn_t1180 = rt_retain(k);
xn_root_add(xn_t1180);
rt_string *xn_t1181 = rt_string_from_c("EnumDecl.Methods");
xn_root_add(xn_t1181);
    if ((xn_str_eq(xn_t1180, xn_t1181))) {
        size_t xn_t1182 = xn_root_mark();
        #line 869 "impl/lib/b2/xparser.x"
        rt_string *xn_t1183 = rt_string_from_c("sp");
xn_root_add(xn_t1183);
        xn_root_add(xn_t1183);
        xn_root_add(xn_t1183);
            {
        xn_root_restore(xn_t1182);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1183;

    }
#line 870 "impl/lib/b2/xparser.x"
rt_string *xn_t1184 = rt_retain(k);
xn_root_add(xn_t1184);
rt_string *xn_t1185 = rt_string_from_c("EnumDecl.Mod");
xn_root_add(xn_t1185);
    if ((xn_str_eq(xn_t1184, xn_t1185))) {
        size_t xn_t1186 = xn_root_mark();
        #line 870 "impl/lib/b2/xparser.x"
        rt_string *xn_t1187 = rt_string_from_c("v");
xn_root_add(xn_t1187);
        xn_root_add(xn_t1187);
        xn_root_add(xn_t1187);
            {
        xn_root_restore(xn_t1186);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1187;

    }
#line 871 "impl/lib/b2/xparser.x"
rt_string *xn_t1188 = rt_retain(k);
xn_root_add(xn_t1188);
rt_string *xn_t1189 = rt_string_from_c("EnumDecl.Name");
xn_root_add(xn_t1189);
    if ((xn_str_eq(xn_t1188, xn_t1189))) {
        size_t xn_t1190 = xn_root_mark();
        #line 871 "impl/lib/b2/xparser.x"
        rt_string *xn_t1191 = rt_string_from_c("s");
xn_root_add(xn_t1191);
        xn_root_add(xn_t1191);
        xn_root_add(xn_t1191);
            {
        xn_root_restore(xn_t1190);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1191;

    }
#line 872 "impl/lib/b2/xparser.x"
rt_string *xn_t1192 = rt_retain(k);
xn_root_add(xn_t1192);
rt_string *xn_t1193 = rt_string_from_c("EnumDecl.P");
xn_root_add(xn_t1193);
    if ((xn_str_eq(xn_t1192, xn_t1193))) {
        size_t xn_t1194 = xn_root_mark();
        #line 872 "impl/lib/b2/xparser.x"
        rt_string *xn_t1195 = rt_string_from_c("v");
xn_root_add(xn_t1195);
        xn_root_add(xn_t1195);
        xn_root_add(xn_t1195);
            {
        xn_root_restore(xn_t1194);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1195;

    }
#line 873 "impl/lib/b2/xparser.x"
rt_string *xn_t1196 = rt_retain(k);
xn_root_add(xn_t1196);
rt_string *xn_t1197 = rt_string_from_c("EnumItem.Annos");
xn_root_add(xn_t1197);
    if ((xn_str_eq(xn_t1196, xn_t1197))) {
        size_t xn_t1198 = xn_root_mark();
        #line 873 "impl/lib/b2/xparser.x"
        rt_string *xn_t1199 = rt_string_from_c("sp");
xn_root_add(xn_t1199);
        xn_root_add(xn_t1199);
        xn_root_add(xn_t1199);
            {
        xn_root_restore(xn_t1198);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1199;

    }
#line 874 "impl/lib/b2/xparser.x"
rt_string *xn_t1200 = rt_retain(k);
xn_root_add(xn_t1200);
rt_string *xn_t1201 = rt_string_from_c("EnumItem.Args");
xn_root_add(xn_t1201);
    if ((xn_str_eq(xn_t1200, xn_t1201))) {
        size_t xn_t1202 = xn_root_mark();
        #line 874 "impl/lib/b2/xparser.x"
        rt_string *xn_t1203 = rt_string_from_c("si");
xn_root_add(xn_t1203);
        xn_root_add(xn_t1203);
        xn_root_add(xn_t1203);
            {
        xn_root_restore(xn_t1202);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1203;

    }
#line 875 "impl/lib/b2/xparser.x"
rt_string *xn_t1204 = rt_retain(k);
xn_root_add(xn_t1204);
rt_string *xn_t1205 = rt_string_from_c("EnumItem.Name");
xn_root_add(xn_t1205);
    if ((xn_str_eq(xn_t1204, xn_t1205))) {
        size_t xn_t1206 = xn_root_mark();
        #line 875 "impl/lib/b2/xparser.x"
        rt_string *xn_t1207 = rt_string_from_c("s");
xn_root_add(xn_t1207);
        xn_root_add(xn_t1207);
        xn_root_add(xn_t1207);
            {
        xn_root_restore(xn_t1206);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1207;

    }
#line 876 "impl/lib/b2/xparser.x"
rt_string *xn_t1208 = rt_retain(k);
xn_root_add(xn_t1208);
rt_string *xn_t1209 = rt_string_from_c("EnumItem.P");
xn_root_add(xn_t1209);
    if ((xn_str_eq(xn_t1208, xn_t1209))) {
        size_t xn_t1210 = xn_root_mark();
        #line 876 "impl/lib/b2/xparser.x"
        rt_string *xn_t1211 = rt_string_from_c("v");
xn_root_add(xn_t1211);
        xn_root_add(xn_t1211);
        xn_root_add(xn_t1211);
            {
        xn_root_restore(xn_t1210);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1211;

    }
#line 877 "impl/lib/b2/xparser.x"
rt_string *xn_t1212 = rt_retain(k);
xn_root_add(xn_t1212);
rt_string *xn_t1213 = rt_string_from_c("EnumItem.Value");
xn_root_add(xn_t1213);
    if ((xn_str_eq(xn_t1212, xn_t1213))) {
        size_t xn_t1214 = xn_root_mark();
        #line 877 "impl/lib/b2/xparser.x"
        rt_string *xn_t1215 = rt_string_from_c("i");
xn_root_add(xn_t1215);
        xn_root_add(xn_t1215);
        xn_root_add(xn_t1215);
            {
        xn_root_restore(xn_t1214);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1215;

    }
#line 878 "impl/lib/b2/xparser.x"
rt_string *xn_t1216 = rt_retain(k);
xn_root_add(xn_t1216);
rt_string *xn_t1217 = rt_string_from_c("ExprStmt.P");
xn_root_add(xn_t1217);
    if ((xn_str_eq(xn_t1216, xn_t1217))) {
        size_t xn_t1218 = xn_root_mark();
        #line 878 "impl/lib/b2/xparser.x"
        rt_string *xn_t1219 = rt_string_from_c("v");
xn_root_add(xn_t1219);
        xn_root_add(xn_t1219);
        xn_root_add(xn_t1219);
            {
        xn_root_restore(xn_t1218);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1219;

    }
#line 879 "impl/lib/b2/xparser.x"
rt_string *xn_t1220 = rt_retain(k);
xn_root_add(xn_t1220);
rt_string *xn_t1221 = rt_string_from_c("ExprStmt.X");
xn_root_add(xn_t1221);
    if ((xn_str_eq(xn_t1220, xn_t1221))) {
        size_t xn_t1222 = xn_root_mark();
        #line 879 "impl/lib/b2/xparser.x"
        rt_string *xn_t1223 = rt_string_from_c("i");
xn_root_add(xn_t1223);
        xn_root_add(xn_t1223);
        xn_root_add(xn_t1223);
            {
        xn_root_restore(xn_t1222);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1223;

    }
#line 880 "impl/lib/b2/xparser.x"
rt_string *xn_t1224 = rt_retain(k);
xn_root_add(xn_t1224);
rt_string *xn_t1225 = rt_string_from_c("ExtensionDecl.Annos");
xn_root_add(xn_t1225);
    if ((xn_str_eq(xn_t1224, xn_t1225))) {
        size_t xn_t1226 = xn_root_mark();
        #line 880 "impl/lib/b2/xparser.x"
        rt_string *xn_t1227 = rt_string_from_c("sp");
xn_root_add(xn_t1227);
        xn_root_add(xn_t1227);
        xn_root_add(xn_t1227);
            {
        xn_root_restore(xn_t1226);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1227;

    }
#line 881 "impl/lib/b2/xparser.x"
rt_string *xn_t1228 = rt_retain(k);
xn_root_add(xn_t1228);
rt_string *xn_t1229 = rt_string_from_c("ExtensionDecl.Methods");
xn_root_add(xn_t1229);
    if ((xn_str_eq(xn_t1228, xn_t1229))) {
        size_t xn_t1230 = xn_root_mark();
        #line 881 "impl/lib/b2/xparser.x"
        rt_string *xn_t1231 = rt_string_from_c("sp");
xn_root_add(xn_t1231);
        xn_root_add(xn_t1231);
        xn_root_add(xn_t1231);
            {
        xn_root_restore(xn_t1230);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1231;

    }
#line 882 "impl/lib/b2/xparser.x"
rt_string *xn_t1232 = rt_retain(k);
xn_root_add(xn_t1232);
rt_string *xn_t1233 = rt_string_from_c("ExtensionDecl.Mod");
xn_root_add(xn_t1233);
    if ((xn_str_eq(xn_t1232, xn_t1233))) {
        size_t xn_t1234 = xn_root_mark();
        #line 882 "impl/lib/b2/xparser.x"
        rt_string *xn_t1235 = rt_string_from_c("v");
xn_root_add(xn_t1235);
        xn_root_add(xn_t1235);
        xn_root_add(xn_t1235);
            {
        xn_root_restore(xn_t1234);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1235;

    }
#line 883 "impl/lib/b2/xparser.x"
rt_string *xn_t1236 = rt_retain(k);
xn_root_add(xn_t1236);
rt_string *xn_t1237 = rt_string_from_c("ExtensionDecl.P");
xn_root_add(xn_t1237);
    if ((xn_str_eq(xn_t1236, xn_t1237))) {
        size_t xn_t1238 = xn_root_mark();
        #line 883 "impl/lib/b2/xparser.x"
        rt_string *xn_t1239 = rt_string_from_c("v");
xn_root_add(xn_t1239);
        xn_root_add(xn_t1239);
        xn_root_add(xn_t1239);
            {
        xn_root_restore(xn_t1238);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1239;

    }
#line 884 "impl/lib/b2/xparser.x"
rt_string *xn_t1240 = rt_retain(k);
xn_root_add(xn_t1240);
rt_string *xn_t1241 = rt_string_from_c("ExtensionDecl.Target");
xn_root_add(xn_t1241);
    if ((xn_str_eq(xn_t1240, xn_t1241))) {
        size_t xn_t1242 = xn_root_mark();
        #line 884 "impl/lib/b2/xparser.x"
        rt_string *xn_t1243 = rt_string_from_c("i");
xn_root_add(xn_t1243);
        xn_root_add(xn_t1243);
        xn_root_add(xn_t1243);
            {
        xn_root_restore(xn_t1242);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1243;

    }
#line 885 "impl/lib/b2/xparser.x"
rt_string *xn_t1244 = rt_retain(k);
xn_root_add(xn_t1244);
rt_string *xn_t1245 = rt_string_from_c("FactoryDecl.Annos");
xn_root_add(xn_t1245);
    if ((xn_str_eq(xn_t1244, xn_t1245))) {
        size_t xn_t1246 = xn_root_mark();
        #line 885 "impl/lib/b2/xparser.x"
        rt_string *xn_t1247 = rt_string_from_c("sp");
xn_root_add(xn_t1247);
        xn_root_add(xn_t1247);
        xn_root_add(xn_t1247);
            {
        xn_root_restore(xn_t1246);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1247;

    }
#line 886 "impl/lib/b2/xparser.x"
rt_string *xn_t1248 = rt_retain(k);
xn_root_add(xn_t1248);
rt_string *xn_t1249 = rt_string_from_c("FactoryDecl.Methods");
xn_root_add(xn_t1249);
    if ((xn_str_eq(xn_t1248, xn_t1249))) {
        size_t xn_t1250 = xn_root_mark();
        #line 886 "impl/lib/b2/xparser.x"
        rt_string *xn_t1251 = rt_string_from_c("sp");
xn_root_add(xn_t1251);
        xn_root_add(xn_t1251);
        xn_root_add(xn_t1251);
            {
        xn_root_restore(xn_t1250);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1251;

    }
#line 887 "impl/lib/b2/xparser.x"
rt_string *xn_t1252 = rt_retain(k);
xn_root_add(xn_t1252);
rt_string *xn_t1253 = rt_string_from_c("FactoryDecl.Mod");
xn_root_add(xn_t1253);
    if ((xn_str_eq(xn_t1252, xn_t1253))) {
        size_t xn_t1254 = xn_root_mark();
        #line 887 "impl/lib/b2/xparser.x"
        rt_string *xn_t1255 = rt_string_from_c("v");
xn_root_add(xn_t1255);
        xn_root_add(xn_t1255);
        xn_root_add(xn_t1255);
            {
        xn_root_restore(xn_t1254);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1255;

    }
#line 888 "impl/lib/b2/xparser.x"
rt_string *xn_t1256 = rt_retain(k);
xn_root_add(xn_t1256);
rt_string *xn_t1257 = rt_string_from_c("FactoryDecl.Name");
xn_root_add(xn_t1257);
    if ((xn_str_eq(xn_t1256, xn_t1257))) {
        size_t xn_t1258 = xn_root_mark();
        #line 888 "impl/lib/b2/xparser.x"
        rt_string *xn_t1259 = rt_string_from_c("s");
xn_root_add(xn_t1259);
        xn_root_add(xn_t1259);
        xn_root_add(xn_t1259);
            {
        xn_root_restore(xn_t1258);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1259;

    }
#line 889 "impl/lib/b2/xparser.x"
rt_string *xn_t1260 = rt_retain(k);
xn_root_add(xn_t1260);
rt_string *xn_t1261 = rt_string_from_c("FactoryDecl.P");
xn_root_add(xn_t1261);
    if ((xn_str_eq(xn_t1260, xn_t1261))) {
        size_t xn_t1262 = xn_root_mark();
        #line 889 "impl/lib/b2/xparser.x"
        rt_string *xn_t1263 = rt_string_from_c("v");
xn_root_add(xn_t1263);
        xn_root_add(xn_t1263);
        xn_root_add(xn_t1263);
            {
        xn_root_restore(xn_t1262);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1263;

    }
#line 890 "impl/lib/b2/xparser.x"
rt_string *xn_t1264 = rt_retain(k);
xn_root_add(xn_t1264);
rt_string *xn_t1265 = rt_string_from_c("FactoryDecl.Target");
xn_root_add(xn_t1265);
    if ((xn_str_eq(xn_t1264, xn_t1265))) {
        size_t xn_t1266 = xn_root_mark();
        #line 890 "impl/lib/b2/xparser.x"
        rt_string *xn_t1267 = rt_string_from_c("i");
xn_root_add(xn_t1267);
        xn_root_add(xn_t1267);
        xn_root_add(xn_t1267);
            {
        xn_root_restore(xn_t1266);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1267;

    }
#line 891 "impl/lib/b2/xparser.x"
rt_string *xn_t1268 = rt_retain(k);
xn_root_add(xn_t1268);
rt_string *xn_t1269 = rt_string_from_c("FieldDecl.Annos");
xn_root_add(xn_t1269);
    if ((xn_str_eq(xn_t1268, xn_t1269))) {
        size_t xn_t1270 = xn_root_mark();
        #line 891 "impl/lib/b2/xparser.x"
        rt_string *xn_t1271 = rt_string_from_c("sp");
xn_root_add(xn_t1271);
        xn_root_add(xn_t1271);
        xn_root_add(xn_t1271);
            {
        xn_root_restore(xn_t1270);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1271;

    }
#line 892 "impl/lib/b2/xparser.x"
rt_string *xn_t1272 = rt_retain(k);
xn_root_add(xn_t1272);
rt_string *xn_t1273 = rt_string_from_c("FieldDecl.Canonical");
xn_root_add(xn_t1273);
    if ((xn_str_eq(xn_t1272, xn_t1273))) {
        size_t xn_t1274 = xn_root_mark();
        #line 892 "impl/lib/b2/xparser.x"
        rt_string *xn_t1275 = rt_string_from_c("s");
xn_root_add(xn_t1275);
        xn_root_add(xn_t1275);
        xn_root_add(xn_t1275);
            {
        xn_root_restore(xn_t1274);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1275;

    }
#line 893 "impl/lib/b2/xparser.x"
rt_string *xn_t1276 = rt_retain(k);
xn_root_add(xn_t1276);
rt_string *xn_t1277 = rt_string_from_c("FieldDecl.Init");
xn_root_add(xn_t1277);
    if ((xn_str_eq(xn_t1276, xn_t1277))) {
        size_t xn_t1278 = xn_root_mark();
        #line 893 "impl/lib/b2/xparser.x"
        rt_string *xn_t1279 = rt_string_from_c("i");
xn_root_add(xn_t1279);
        xn_root_add(xn_t1279);
        xn_root_add(xn_t1279);
            {
        xn_root_restore(xn_t1278);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1279;

    }
#line 894 "impl/lib/b2/xparser.x"
rt_string *xn_t1280 = rt_retain(k);
xn_root_add(xn_t1280);
rt_string *xn_t1281 = rt_string_from_c("FieldDecl.Mod");
xn_root_add(xn_t1281);
    if ((xn_str_eq(xn_t1280, xn_t1281))) {
        size_t xn_t1282 = xn_root_mark();
        #line 894 "impl/lib/b2/xparser.x"
        rt_string *xn_t1283 = rt_string_from_c("v");
xn_root_add(xn_t1283);
        xn_root_add(xn_t1283);
        xn_root_add(xn_t1283);
            {
        xn_root_restore(xn_t1282);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1283;

    }
#line 895 "impl/lib/b2/xparser.x"
rt_string *xn_t1284 = rt_retain(k);
xn_root_add(xn_t1284);
rt_string *xn_t1285 = rt_string_from_c("FieldDecl.Name");
xn_root_add(xn_t1285);
    if ((xn_str_eq(xn_t1284, xn_t1285))) {
        size_t xn_t1286 = xn_root_mark();
        #line 895 "impl/lib/b2/xparser.x"
        rt_string *xn_t1287 = rt_string_from_c("s");
xn_root_add(xn_t1287);
        xn_root_add(xn_t1287);
        xn_root_add(xn_t1287);
            {
        xn_root_restore(xn_t1286);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1287;

    }
#line 896 "impl/lib/b2/xparser.x"
rt_string *xn_t1288 = rt_retain(k);
xn_root_add(xn_t1288);
rt_string *xn_t1289 = rt_string_from_c("FieldDecl.P");
xn_root_add(xn_t1289);
    if ((xn_str_eq(xn_t1288, xn_t1289))) {
        size_t xn_t1290 = xn_root_mark();
        #line 896 "impl/lib/b2/xparser.x"
        rt_string *xn_t1291 = rt_string_from_c("v");
xn_root_add(xn_t1291);
        xn_root_add(xn_t1291);
        xn_root_add(xn_t1291);
            {
        xn_root_restore(xn_t1290);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1291;

    }
#line 897 "impl/lib/b2/xparser.x"
rt_string *xn_t1292 = rt_retain(k);
xn_root_add(xn_t1292);
rt_string *xn_t1293 = rt_string_from_c("FieldDecl.Type");
xn_root_add(xn_t1293);
    if ((xn_str_eq(xn_t1292, xn_t1293))) {
        size_t xn_t1294 = xn_root_mark();
        #line 897 "impl/lib/b2/xparser.x"
        rt_string *xn_t1295 = rt_string_from_c("i");
xn_root_add(xn_t1295);
        xn_root_add(xn_t1295);
        xn_root_add(xn_t1295);
            {
        xn_root_restore(xn_t1294);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1295;

    }
#line 898 "impl/lib/b2/xparser.x"
rt_string *xn_t1296 = rt_retain(k);
xn_root_add(xn_t1296);
rt_string *xn_t1297 = rt_string_from_c("FloatLitExpr.HasSuffixF");
xn_root_add(xn_t1297);
    if ((xn_str_eq(xn_t1296, xn_t1297))) {
        size_t xn_t1298 = xn_root_mark();
        #line 898 "impl/lib/b2/xparser.x"
        rt_string *xn_t1299 = rt_string_from_c("s");
xn_root_add(xn_t1299);
        xn_root_add(xn_t1299);
        xn_root_add(xn_t1299);
            {
        xn_root_restore(xn_t1298);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1299;

    }
#line 899 "impl/lib/b2/xparser.x"
rt_string *xn_t1300 = rt_retain(k);
xn_root_add(xn_t1300);
rt_string *xn_t1301 = rt_string_from_c("FloatLitExpr.P");
xn_root_add(xn_t1301);
    if ((xn_str_eq(xn_t1300, xn_t1301))) {
        size_t xn_t1302 = xn_root_mark();
        #line 899 "impl/lib/b2/xparser.x"
        rt_string *xn_t1303 = rt_string_from_c("v");
xn_root_add(xn_t1303);
        xn_root_add(xn_t1303);
        xn_root_add(xn_t1303);
            {
        xn_root_restore(xn_t1302);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1303;

    }
#line 900 "impl/lib/b2/xparser.x"
rt_string *xn_t1304 = rt_retain(k);
xn_root_add(xn_t1304);
rt_string *xn_t1305 = rt_string_from_c("FloatLitExpr.Text");
xn_root_add(xn_t1305);
    if ((xn_str_eq(xn_t1304, xn_t1305))) {
        size_t xn_t1306 = xn_root_mark();
        #line 900 "impl/lib/b2/xparser.x"
        rt_string *xn_t1307 = rt_string_from_c("s");
xn_root_add(xn_t1307);
        xn_root_add(xn_t1307);
        xn_root_add(xn_t1307);
            {
        xn_root_restore(xn_t1306);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1307;

    }
#line 901 "impl/lib/b2/xparser.x"
rt_string *xn_t1308 = rt_retain(k);
xn_root_add(xn_t1308);
rt_string *xn_t1309 = rt_string_from_c("ForStmt.Body");
xn_root_add(xn_t1309);
    if ((xn_str_eq(xn_t1308, xn_t1309))) {
        size_t xn_t1310 = xn_root_mark();
        #line 901 "impl/lib/b2/xparser.x"
        rt_string *xn_t1311 = rt_string_from_c("p");
xn_root_add(xn_t1311);
        xn_root_add(xn_t1311);
        xn_root_add(xn_t1311);
            {
        xn_root_restore(xn_t1310);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1311;

    }
#line 902 "impl/lib/b2/xparser.x"
rt_string *xn_t1312 = rt_retain(k);
xn_root_add(xn_t1312);
rt_string *xn_t1313 = rt_string_from_c("ForStmt.P");
xn_root_add(xn_t1313);
    if ((xn_str_eq(xn_t1312, xn_t1313))) {
        size_t xn_t1314 = xn_root_mark();
        #line 902 "impl/lib/b2/xparser.x"
        rt_string *xn_t1315 = rt_string_from_c("v");
xn_root_add(xn_t1315);
        xn_root_add(xn_t1315);
        xn_root_add(xn_t1315);
            {
        xn_root_restore(xn_t1314);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1315;

    }
#line 903 "impl/lib/b2/xparser.x"
rt_string *xn_t1316 = rt_retain(k);
xn_root_add(xn_t1316);
rt_string *xn_t1317 = rt_string_from_c("ForStmt.Src");
xn_root_add(xn_t1317);
    if ((xn_str_eq(xn_t1316, xn_t1317))) {
        size_t xn_t1318 = xn_root_mark();
        #line 903 "impl/lib/b2/xparser.x"
        rt_string *xn_t1319 = rt_string_from_c("i");
xn_root_add(xn_t1319);
        xn_root_add(xn_t1319);
        xn_root_add(xn_t1319);
            {
        xn_root_restore(xn_t1318);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1319;

    }
#line 904 "impl/lib/b2/xparser.x"
rt_string *xn_t1320 = rt_retain(k);
xn_root_add(xn_t1320);
rt_string *xn_t1321 = rt_string_from_c("ForStmt.Var");
xn_root_add(xn_t1321);
    if ((xn_str_eq(xn_t1320, xn_t1321))) {
        size_t xn_t1322 = xn_root_mark();
        #line 904 "impl/lib/b2/xparser.x"
        rt_string *xn_t1323 = rt_string_from_c("s");
xn_root_add(xn_t1323);
        xn_root_add(xn_t1323);
        xn_root_add(xn_t1323);
            {
        xn_root_restore(xn_t1322);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1323;

    }
#line 905 "impl/lib/b2/xparser.x"
rt_string *xn_t1324 = rt_retain(k);
xn_root_add(xn_t1324);
rt_string *xn_t1325 = rt_string_from_c("FuncTypeRef.P");
xn_root_add(xn_t1325);
    if ((xn_str_eq(xn_t1324, xn_t1325))) {
        size_t xn_t1326 = xn_root_mark();
        #line 905 "impl/lib/b2/xparser.x"
        rt_string *xn_t1327 = rt_string_from_c("v");
xn_root_add(xn_t1327);
        xn_root_add(xn_t1327);
        xn_root_add(xn_t1327);
            {
        xn_root_restore(xn_t1326);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1327;

    }
#line 906 "impl/lib/b2/xparser.x"
rt_string *xn_t1328 = rt_retain(k);
xn_root_add(xn_t1328);
rt_string *xn_t1329 = rt_string_from_c("FuncTypeRef.Params");
xn_root_add(xn_t1329);
    if ((xn_str_eq(xn_t1328, xn_t1329))) {
        size_t xn_t1330 = xn_root_mark();
        #line 906 "impl/lib/b2/xparser.x"
        rt_string *xn_t1331 = rt_string_from_c("si");
xn_root_add(xn_t1331);
        xn_root_add(xn_t1331);
        xn_root_add(xn_t1331);
            {
        xn_root_restore(xn_t1330);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1331;

    }
#line 907 "impl/lib/b2/xparser.x"
rt_string *xn_t1332 = rt_retain(k);
xn_root_add(xn_t1332);
rt_string *xn_t1333 = rt_string_from_c("FuncTypeRef.Ret");
xn_root_add(xn_t1333);
    if ((xn_str_eq(xn_t1332, xn_t1333))) {
        size_t xn_t1334 = xn_root_mark();
        #line 907 "impl/lib/b2/xparser.x"
        rt_string *xn_t1335 = rt_string_from_c("i");
xn_root_add(xn_t1335);
        xn_root_add(xn_t1335);
        xn_root_add(xn_t1335);
            {
        xn_root_restore(xn_t1334);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1335;

    }
#line 908 "impl/lib/b2/xparser.x"
rt_string *xn_t1336 = rt_retain(k);
xn_root_add(xn_t1336);
rt_string *xn_t1337 = rt_string_from_c("GotoStmt.Label");
xn_root_add(xn_t1337);
    if ((xn_str_eq(xn_t1336, xn_t1337))) {
        size_t xn_t1338 = xn_root_mark();
        #line 908 "impl/lib/b2/xparser.x"
        rt_string *xn_t1339 = rt_string_from_c("s");
xn_root_add(xn_t1339);
        xn_root_add(xn_t1339);
        xn_root_add(xn_t1339);
            {
        xn_root_restore(xn_t1338);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1339;

    }
#line 909 "impl/lib/b2/xparser.x"
rt_string *xn_t1340 = rt_retain(k);
xn_root_add(xn_t1340);
rt_string *xn_t1341 = rt_string_from_c("GotoStmt.P");
xn_root_add(xn_t1341);
    if ((xn_str_eq(xn_t1340, xn_t1341))) {
        size_t xn_t1342 = xn_root_mark();
        #line 909 "impl/lib/b2/xparser.x"
        rt_string *xn_t1343 = rt_string_from_c("v");
xn_root_add(xn_t1343);
        xn_root_add(xn_t1343);
        xn_root_add(xn_t1343);
            {
        xn_root_restore(xn_t1342);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1343;

    }
#line 910 "impl/lib/b2/xparser.x"
rt_string *xn_t1344 = rt_retain(k);
xn_root_add(xn_t1344);
rt_string *xn_t1345 = rt_string_from_c("IdentExpr.Name");
xn_root_add(xn_t1345);
    if ((xn_str_eq(xn_t1344, xn_t1345))) {
        size_t xn_t1346 = xn_root_mark();
        #line 910 "impl/lib/b2/xparser.x"
        rt_string *xn_t1347 = rt_string_from_c("s");
xn_root_add(xn_t1347);
        xn_root_add(xn_t1347);
        xn_root_add(xn_t1347);
            {
        xn_root_restore(xn_t1346);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1347;

    }
#line 911 "impl/lib/b2/xparser.x"
rt_string *xn_t1348 = rt_retain(k);
xn_root_add(xn_t1348);
rt_string *xn_t1349 = rt_string_from_c("IdentExpr.P");
xn_root_add(xn_t1349);
    if ((xn_str_eq(xn_t1348, xn_t1349))) {
        size_t xn_t1350 = xn_root_mark();
        #line 911 "impl/lib/b2/xparser.x"
        rt_string *xn_t1351 = rt_string_from_c("v");
xn_root_add(xn_t1351);
        xn_root_add(xn_t1351);
        xn_root_add(xn_t1351);
            {
        xn_root_restore(xn_t1350);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1351;

    }
#line 912 "impl/lib/b2/xparser.x"
rt_string *xn_t1352 = rt_retain(k);
xn_root_add(xn_t1352);
rt_string *xn_t1353 = rt_string_from_c("IfStmt.Cond");
xn_root_add(xn_t1353);
    if ((xn_str_eq(xn_t1352, xn_t1353))) {
        size_t xn_t1354 = xn_root_mark();
        #line 912 "impl/lib/b2/xparser.x"
        rt_string *xn_t1355 = rt_string_from_c("i");
xn_root_add(xn_t1355);
        xn_root_add(xn_t1355);
        xn_root_add(xn_t1355);
            {
        xn_root_restore(xn_t1354);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1355;

    }
#line 913 "impl/lib/b2/xparser.x"
rt_string *xn_t1356 = rt_retain(k);
xn_root_add(xn_t1356);
rt_string *xn_t1357 = rt_string_from_c("IfStmt.Else");
xn_root_add(xn_t1357);
    if ((xn_str_eq(xn_t1356, xn_t1357))) {
        size_t xn_t1358 = xn_root_mark();
        #line 913 "impl/lib/b2/xparser.x"
        rt_string *xn_t1359 = rt_string_from_c("i");
xn_root_add(xn_t1359);
        xn_root_add(xn_t1359);
        xn_root_add(xn_t1359);
            {
        xn_root_restore(xn_t1358);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1359;

    }
#line 914 "impl/lib/b2/xparser.x"
rt_string *xn_t1360 = rt_retain(k);
xn_root_add(xn_t1360);
rt_string *xn_t1361 = rt_string_from_c("IfStmt.P");
xn_root_add(xn_t1361);
    if ((xn_str_eq(xn_t1360, xn_t1361))) {
        size_t xn_t1362 = xn_root_mark();
        #line 914 "impl/lib/b2/xparser.x"
        rt_string *xn_t1363 = rt_string_from_c("v");
xn_root_add(xn_t1363);
        xn_root_add(xn_t1363);
        xn_root_add(xn_t1363);
            {
        xn_root_restore(xn_t1362);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1363;

    }
#line 915 "impl/lib/b2/xparser.x"
rt_string *xn_t1364 = rt_retain(k);
xn_root_add(xn_t1364);
rt_string *xn_t1365 = rt_string_from_c("IfStmt.Then");
xn_root_add(xn_t1365);
    if ((xn_str_eq(xn_t1364, xn_t1365))) {
        size_t xn_t1366 = xn_root_mark();
        #line 915 "impl/lib/b2/xparser.x"
        rt_string *xn_t1367 = rt_string_from_c("p");
xn_root_add(xn_t1367);
        xn_root_add(xn_t1367);
        xn_root_add(xn_t1367);
            {
        xn_root_restore(xn_t1366);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1367;

    }
#line 916 "impl/lib/b2/xparser.x"
rt_string *xn_t1368 = rt_retain(k);
xn_root_add(xn_t1368);
rt_string *xn_t1369 = rt_string_from_c("ImportDecl.Alias");
xn_root_add(xn_t1369);
    if ((xn_str_eq(xn_t1368, xn_t1369))) {
        size_t xn_t1370 = xn_root_mark();
        #line 916 "impl/lib/b2/xparser.x"
        rt_string *xn_t1371 = rt_string_from_c("s");
xn_root_add(xn_t1371);
        xn_root_add(xn_t1371);
        xn_root_add(xn_t1371);
            {
        xn_root_restore(xn_t1370);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1371;

    }
#line 917 "impl/lib/b2/xparser.x"
rt_string *xn_t1372 = rt_retain(k);
xn_root_add(xn_t1372);
rt_string *xn_t1373 = rt_string_from_c("ImportDecl.P");
xn_root_add(xn_t1373);
    if ((xn_str_eq(xn_t1372, xn_t1373))) {
        size_t xn_t1374 = xn_root_mark();
        #line 917 "impl/lib/b2/xparser.x"
        rt_string *xn_t1375 = rt_string_from_c("v");
xn_root_add(xn_t1375);
        xn_root_add(xn_t1375);
        xn_root_add(xn_t1375);
            {
        xn_root_restore(xn_t1374);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1375;

    }
#line 918 "impl/lib/b2/xparser.x"
rt_string *xn_t1376 = rt_retain(k);
xn_root_add(xn_t1376);
rt_string *xn_t1377 = rt_string_from_c("ImportDecl.Path");
xn_root_add(xn_t1377);
    if ((xn_str_eq(xn_t1376, xn_t1377))) {
        size_t xn_t1378 = xn_root_mark();
        #line 918 "impl/lib/b2/xparser.x"
        rt_string *xn_t1379 = rt_string_from_c("ss");
xn_root_add(xn_t1379);
        xn_root_add(xn_t1379);
        xn_root_add(xn_t1379);
            {
        xn_root_restore(xn_t1378);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1379;

    }
#line 919 "impl/lib/b2/xparser.x"
rt_string *xn_t1380 = rt_retain(k);
xn_root_add(xn_t1380);
rt_string *xn_t1381 = rt_string_from_c("IncDecStmt.Op");
xn_root_add(xn_t1381);
    if ((xn_str_eq(xn_t1380, xn_t1381))) {
        size_t xn_t1382 = xn_root_mark();
        #line 919 "impl/lib/b2/xparser.x"
        rt_string *xn_t1383 = rt_string_from_c("s");
xn_root_add(xn_t1383);
        xn_root_add(xn_t1383);
        xn_root_add(xn_t1383);
            {
        xn_root_restore(xn_t1382);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1383;

    }
#line 920 "impl/lib/b2/xparser.x"
rt_string *xn_t1384 = rt_retain(k);
xn_root_add(xn_t1384);
rt_string *xn_t1385 = rt_string_from_c("IncDecStmt.P");
xn_root_add(xn_t1385);
    if ((xn_str_eq(xn_t1384, xn_t1385))) {
        size_t xn_t1386 = xn_root_mark();
        #line 920 "impl/lib/b2/xparser.x"
        rt_string *xn_t1387 = rt_string_from_c("v");
xn_root_add(xn_t1387);
        xn_root_add(xn_t1387);
        xn_root_add(xn_t1387);
            {
        xn_root_restore(xn_t1386);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1387;

    }
#line 921 "impl/lib/b2/xparser.x"
rt_string *xn_t1388 = rt_retain(k);
xn_root_add(xn_t1388);
rt_string *xn_t1389 = rt_string_from_c("IncDecStmt.Prefix");
xn_root_add(xn_t1389);
    if ((xn_str_eq(xn_t1388, xn_t1389))) {
        size_t xn_t1390 = xn_root_mark();
        #line 921 "impl/lib/b2/xparser.x"
        rt_string *xn_t1391 = rt_string_from_c("s");
xn_root_add(xn_t1391);
        xn_root_add(xn_t1391);
        xn_root_add(xn_t1391);
            {
        xn_root_restore(xn_t1390);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1391;

    }
#line 922 "impl/lib/b2/xparser.x"
rt_string *xn_t1392 = rt_retain(k);
xn_root_add(xn_t1392);
rt_string *xn_t1393 = rt_string_from_c("IncDecStmt.Target");
xn_root_add(xn_t1393);
    if ((xn_str_eq(xn_t1392, xn_t1393))) {
        size_t xn_t1394 = xn_root_mark();
        #line 922 "impl/lib/b2/xparser.x"
        rt_string *xn_t1395 = rt_string_from_c("i");
xn_root_add(xn_t1395);
        xn_root_add(xn_t1395);
        xn_root_add(xn_t1395);
            {
        xn_root_restore(xn_t1394);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1395;

    }
#line 923 "impl/lib/b2/xparser.x"
rt_string *xn_t1396 = rt_retain(k);
xn_root_add(xn_t1396);
rt_string *xn_t1397 = rt_string_from_c("Index.Idx");
xn_root_add(xn_t1397);
    if ((xn_str_eq(xn_t1396, xn_t1397))) {
        size_t xn_t1398 = xn_root_mark();
        #line 923 "impl/lib/b2/xparser.x"
        rt_string *xn_t1399 = rt_string_from_c("i");
xn_root_add(xn_t1399);
        xn_root_add(xn_t1399);
        xn_root_add(xn_t1399);
            {
        xn_root_restore(xn_t1398);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1399;

    }
#line 924 "impl/lib/b2/xparser.x"
rt_string *xn_t1400 = rt_retain(k);
xn_root_add(xn_t1400);
rt_string *xn_t1401 = rt_string_from_c("Index.P");
xn_root_add(xn_t1401);
    if ((xn_str_eq(xn_t1400, xn_t1401))) {
        size_t xn_t1402 = xn_root_mark();
        #line 924 "impl/lib/b2/xparser.x"
        rt_string *xn_t1403 = rt_string_from_c("v");
xn_root_add(xn_t1403);
        xn_root_add(xn_t1403);
        xn_root_add(xn_t1403);
            {
        xn_root_restore(xn_t1402);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1403;

    }
#line 925 "impl/lib/b2/xparser.x"
rt_string *xn_t1404 = rt_retain(k);
xn_root_add(xn_t1404);
rt_string *xn_t1405 = rt_string_from_c("Index.X");
xn_root_add(xn_t1405);
    if ((xn_str_eq(xn_t1404, xn_t1405))) {
        size_t xn_t1406 = xn_root_mark();
        #line 925 "impl/lib/b2/xparser.x"
        rt_string *xn_t1407 = rt_string_from_c("i");
xn_root_add(xn_t1407);
        xn_root_add(xn_t1407);
        xn_root_add(xn_t1407);
            {
        xn_root_restore(xn_t1406);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1407;

    }
#line 926 "impl/lib/b2/xparser.x"
rt_string *xn_t1408 = rt_retain(k);
xn_root_add(xn_t1408);
rt_string *xn_t1409 = rt_string_from_c("IntLitExpr.Base");
xn_root_add(xn_t1409);
    if ((xn_str_eq(xn_t1408, xn_t1409))) {
        size_t xn_t1410 = xn_root_mark();
        #line 926 "impl/lib/b2/xparser.x"
        rt_string *xn_t1411 = rt_string_from_c("s");
xn_root_add(xn_t1411);
        xn_root_add(xn_t1411);
        xn_root_add(xn_t1411);
            {
        xn_root_restore(xn_t1410);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1411;

    }
#line 927 "impl/lib/b2/xparser.x"
rt_string *xn_t1412 = rt_retain(k);
xn_root_add(xn_t1412);
rt_string *xn_t1413 = rt_string_from_c("IntLitExpr.P");
xn_root_add(xn_t1413);
    if ((xn_str_eq(xn_t1412, xn_t1413))) {
        size_t xn_t1414 = xn_root_mark();
        #line 927 "impl/lib/b2/xparser.x"
        rt_string *xn_t1415 = rt_string_from_c("v");
xn_root_add(xn_t1415);
        xn_root_add(xn_t1415);
        xn_root_add(xn_t1415);
            {
        xn_root_restore(xn_t1414);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1415;

    }
#line 928 "impl/lib/b2/xparser.x"
rt_string *xn_t1416 = rt_retain(k);
xn_root_add(xn_t1416);
rt_string *xn_t1417 = rt_string_from_c("IntLitExpr.Suffix");
xn_root_add(xn_t1417);
    if ((xn_str_eq(xn_t1416, xn_t1417))) {
        size_t xn_t1418 = xn_root_mark();
        #line 928 "impl/lib/b2/xparser.x"
        rt_string *xn_t1419 = rt_string_from_c("s");
xn_root_add(xn_t1419);
        xn_root_add(xn_t1419);
        xn_root_add(xn_t1419);
            {
        xn_root_restore(xn_t1418);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1419;

    }
#line 929 "impl/lib/b2/xparser.x"
rt_string *xn_t1420 = rt_retain(k);
xn_root_add(xn_t1420);
rt_string *xn_t1421 = rt_string_from_c("IntLitExpr.Text");
xn_root_add(xn_t1421);
    if ((xn_str_eq(xn_t1420, xn_t1421))) {
        size_t xn_t1422 = xn_root_mark();
        #line 929 "impl/lib/b2/xparser.x"
        rt_string *xn_t1423 = rt_string_from_c("s");
xn_root_add(xn_t1423);
        xn_root_add(xn_t1423);
        xn_root_add(xn_t1423);
            {
        xn_root_restore(xn_t1422);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1423;

    }
#line 930 "impl/lib/b2/xparser.x"
rt_string *xn_t1424 = rt_retain(k);
xn_root_add(xn_t1424);
rt_string *xn_t1425 = rt_string_from_c("LabeledStmt.Label");
xn_root_add(xn_t1425);
    if ((xn_str_eq(xn_t1424, xn_t1425))) {
        size_t xn_t1426 = xn_root_mark();
        #line 930 "impl/lib/b2/xparser.x"
        rt_string *xn_t1427 = rt_string_from_c("s");
xn_root_add(xn_t1427);
        xn_root_add(xn_t1427);
        xn_root_add(xn_t1427);
            {
        xn_root_restore(xn_t1426);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1427;

    }
#line 931 "impl/lib/b2/xparser.x"
rt_string *xn_t1428 = rt_retain(k);
xn_root_add(xn_t1428);
rt_string *xn_t1429 = rt_string_from_c("LabeledStmt.P");
xn_root_add(xn_t1429);
    if ((xn_str_eq(xn_t1428, xn_t1429))) {
        size_t xn_t1430 = xn_root_mark();
        #line 931 "impl/lib/b2/xparser.x"
        rt_string *xn_t1431 = rt_string_from_c("v");
xn_root_add(xn_t1431);
        xn_root_add(xn_t1431);
        xn_root_add(xn_t1431);
            {
        xn_root_restore(xn_t1430);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1431;

    }
#line 932 "impl/lib/b2/xparser.x"
rt_string *xn_t1432 = rt_retain(k);
xn_root_add(xn_t1432);
rt_string *xn_t1433 = rt_string_from_c("LabeledStmt.Stmt");
xn_root_add(xn_t1433);
    if ((xn_str_eq(xn_t1432, xn_t1433))) {
        size_t xn_t1434 = xn_root_mark();
        #line 932 "impl/lib/b2/xparser.x"
        rt_string *xn_t1435 = rt_string_from_c("i");
xn_root_add(xn_t1435);
        xn_root_add(xn_t1435);
        xn_root_add(xn_t1435);
            {
        xn_root_restore(xn_t1434);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1435;

    }
#line 933 "impl/lib/b2/xparser.x"
rt_string *xn_t1436 = rt_retain(k);
xn_root_add(xn_t1436);
rt_string *xn_t1437 = rt_string_from_c("Lambda.Block");
xn_root_add(xn_t1437);
    if ((xn_str_eq(xn_t1436, xn_t1437))) {
        size_t xn_t1438 = xn_root_mark();
        #line 933 "impl/lib/b2/xparser.x"
        rt_string *xn_t1439 = rt_string_from_c("p");
xn_root_add(xn_t1439);
        xn_root_add(xn_t1439);
        xn_root_add(xn_t1439);
            {
        xn_root_restore(xn_t1438);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1439;

    }
#line 934 "impl/lib/b2/xparser.x"
rt_string *xn_t1440 = rt_retain(k);
xn_root_add(xn_t1440);
rt_string *xn_t1441 = rt_string_from_c("Lambda.ExprB");
xn_root_add(xn_t1441);
    if ((xn_str_eq(xn_t1440, xn_t1441))) {
        size_t xn_t1442 = xn_root_mark();
        #line 934 "impl/lib/b2/xparser.x"
        rt_string *xn_t1443 = rt_string_from_c("i");
xn_root_add(xn_t1443);
        xn_root_add(xn_t1443);
        xn_root_add(xn_t1443);
            {
        xn_root_restore(xn_t1442);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1443;

    }
#line 935 "impl/lib/b2/xparser.x"
rt_string *xn_t1444 = rt_retain(k);
xn_root_add(xn_t1444);
rt_string *xn_t1445 = rt_string_from_c("Lambda.P");
xn_root_add(xn_t1445);
    if ((xn_str_eq(xn_t1444, xn_t1445))) {
        size_t xn_t1446 = xn_root_mark();
        #line 935 "impl/lib/b2/xparser.x"
        rt_string *xn_t1447 = rt_string_from_c("v");
xn_root_add(xn_t1447);
        xn_root_add(xn_t1447);
        xn_root_add(xn_t1447);
            {
        xn_root_restore(xn_t1446);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1447;

    }
#line 936 "impl/lib/b2/xparser.x"
rt_string *xn_t1448 = rt_retain(k);
xn_root_add(xn_t1448);
rt_string *xn_t1449 = rt_string_from_c("Lambda.Params");
xn_root_add(xn_t1449);
    if ((xn_str_eq(xn_t1448, xn_t1449))) {
        size_t xn_t1450 = xn_root_mark();
        #line 936 "impl/lib/b2/xparser.x"
        rt_string *xn_t1451 = rt_string_from_c("sv");
xn_root_add(xn_t1451);
        xn_root_add(xn_t1451);
        xn_root_add(xn_t1451);
            {
        xn_root_restore(xn_t1450);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1451;

    }
#line 937 "impl/lib/b2/xparser.x"
rt_string *xn_t1452 = rt_retain(k);
xn_root_add(xn_t1452);
rt_string *xn_t1453 = rt_string_from_c("Lambda.Single");
xn_root_add(xn_t1453);
    if ((xn_str_eq(xn_t1452, xn_t1453))) {
        size_t xn_t1454 = xn_root_mark();
        #line 937 "impl/lib/b2/xparser.x"
        rt_string *xn_t1455 = rt_string_from_c("s");
xn_root_add(xn_t1455);
        xn_root_add(xn_t1455);
        xn_root_add(xn_t1455);
            {
        xn_root_restore(xn_t1454);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1455;

    }
#line 938 "impl/lib/b2/xparser.x"
rt_string *xn_t1456 = rt_retain(k);
xn_root_add(xn_t1456);
rt_string *xn_t1457 = rt_string_from_c("LambdaParam.Final");
xn_root_add(xn_t1457);
    if ((xn_str_eq(xn_t1456, xn_t1457))) {
        size_t xn_t1458 = xn_root_mark();
        #line 938 "impl/lib/b2/xparser.x"
        rt_string *xn_t1459 = rt_string_from_c("s");
xn_root_add(xn_t1459);
        xn_root_add(xn_t1459);
        xn_root_add(xn_t1459);
            {
        xn_root_restore(xn_t1458);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1459;

    }
#line 939 "impl/lib/b2/xparser.x"
rt_string *xn_t1460 = rt_retain(k);
xn_root_add(xn_t1460);
rt_string *xn_t1461 = rt_string_from_c("LambdaParam.Name");
xn_root_add(xn_t1461);
    if ((xn_str_eq(xn_t1460, xn_t1461))) {
        size_t xn_t1462 = xn_root_mark();
        #line 939 "impl/lib/b2/xparser.x"
        rt_string *xn_t1463 = rt_string_from_c("s");
xn_root_add(xn_t1463);
        xn_root_add(xn_t1463);
        xn_root_add(xn_t1463);
            {
        xn_root_restore(xn_t1462);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1463;

    }
#line 940 "impl/lib/b2/xparser.x"
rt_string *xn_t1464 = rt_retain(k);
xn_root_add(xn_t1464);
rt_string *xn_t1465 = rt_string_from_c("LambdaParam.P");
xn_root_add(xn_t1465);
    if ((xn_str_eq(xn_t1464, xn_t1465))) {
        size_t xn_t1466 = xn_root_mark();
        #line 940 "impl/lib/b2/xparser.x"
        rt_string *xn_t1467 = rt_string_from_c("v");
xn_root_add(xn_t1467);
        xn_root_add(xn_t1467);
        xn_root_add(xn_t1467);
            {
        xn_root_restore(xn_t1466);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1467;

    }
#line 941 "impl/lib/b2/xparser.x"
rt_string *xn_t1468 = rt_retain(k);
xn_root_add(xn_t1468);
rt_string *xn_t1469 = rt_string_from_c("LambdaParam.Type");
xn_root_add(xn_t1469);
    if ((xn_str_eq(xn_t1468, xn_t1469))) {
        size_t xn_t1470 = xn_root_mark();
        #line 941 "impl/lib/b2/xparser.x"
        rt_string *xn_t1471 = rt_string_from_c("i");
xn_root_add(xn_t1471);
        xn_root_add(xn_t1471);
        xn_root_add(xn_t1471);
            {
        xn_root_restore(xn_t1470);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1471;

    }
#line 942 "impl/lib/b2/xparser.x"
rt_string *xn_t1472 = rt_retain(k);
xn_root_add(xn_t1472);
rt_string *xn_t1473 = rt_string_from_c("LocalDeclStmt.Const");
xn_root_add(xn_t1473);
    if ((xn_str_eq(xn_t1472, xn_t1473))) {
        size_t xn_t1474 = xn_root_mark();
        #line 942 "impl/lib/b2/xparser.x"
        rt_string *xn_t1475 = rt_string_from_c("s");
xn_root_add(xn_t1475);
        xn_root_add(xn_t1475);
        xn_root_add(xn_t1475);
            {
        xn_root_restore(xn_t1474);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1475;

    }
#line 943 "impl/lib/b2/xparser.x"
rt_string *xn_t1476 = rt_retain(k);
xn_root_add(xn_t1476);
rt_string *xn_t1477 = rt_string_from_c("LocalDeclStmt.Final");
xn_root_add(xn_t1477);
    if ((xn_str_eq(xn_t1476, xn_t1477))) {
        size_t xn_t1478 = xn_root_mark();
        #line 943 "impl/lib/b2/xparser.x"
        rt_string *xn_t1479 = rt_string_from_c("s");
xn_root_add(xn_t1479);
        xn_root_add(xn_t1479);
        xn_root_add(xn_t1479);
            {
        xn_root_restore(xn_t1478);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1479;

    }
#line 944 "impl/lib/b2/xparser.x"
rt_string *xn_t1480 = rt_retain(k);
xn_root_add(xn_t1480);
rt_string *xn_t1481 = rt_string_from_c("LocalDeclStmt.Init");
xn_root_add(xn_t1481);
    if ((xn_str_eq(xn_t1480, xn_t1481))) {
        size_t xn_t1482 = xn_root_mark();
        #line 944 "impl/lib/b2/xparser.x"
        rt_string *xn_t1483 = rt_string_from_c("i");
xn_root_add(xn_t1483);
        xn_root_add(xn_t1483);
        xn_root_add(xn_t1483);
            {
        xn_root_restore(xn_t1482);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1483;

    }
#line 945 "impl/lib/b2/xparser.x"
rt_string *xn_t1484 = rt_retain(k);
xn_root_add(xn_t1484);
rt_string *xn_t1485 = rt_string_from_c("LocalDeclStmt.Name");
xn_root_add(xn_t1485);
    if ((xn_str_eq(xn_t1484, xn_t1485))) {
        size_t xn_t1486 = xn_root_mark();
        #line 945 "impl/lib/b2/xparser.x"
        rt_string *xn_t1487 = rt_string_from_c("s");
xn_root_add(xn_t1487);
        xn_root_add(xn_t1487);
        xn_root_add(xn_t1487);
            {
        xn_root_restore(xn_t1486);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1487;

    }
#line 946 "impl/lib/b2/xparser.x"
rt_string *xn_t1488 = rt_retain(k);
xn_root_add(xn_t1488);
rt_string *xn_t1489 = rt_string_from_c("LocalDeclStmt.P");
xn_root_add(xn_t1489);
    if ((xn_str_eq(xn_t1488, xn_t1489))) {
        size_t xn_t1490 = xn_root_mark();
        #line 946 "impl/lib/b2/xparser.x"
        rt_string *xn_t1491 = rt_string_from_c("v");
xn_root_add(xn_t1491);
        xn_root_add(xn_t1491);
        xn_root_add(xn_t1491);
            {
        xn_root_restore(xn_t1490);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1491;

    }
#line 947 "impl/lib/b2/xparser.x"
rt_string *xn_t1492 = rt_retain(k);
xn_root_add(xn_t1492);
rt_string *xn_t1493 = rt_string_from_c("LocalDeclStmt.Type");
xn_root_add(xn_t1493);
    if ((xn_str_eq(xn_t1492, xn_t1493))) {
        size_t xn_t1494 = xn_root_mark();
        #line 947 "impl/lib/b2/xparser.x"
        rt_string *xn_t1495 = rt_string_from_c("i");
xn_root_add(xn_t1495);
        xn_root_add(xn_t1495);
        xn_root_add(xn_t1495);
            {
        xn_root_restore(xn_t1494);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1495;

    }
#line 948 "impl/lib/b2/xparser.x"
rt_string *xn_t1496 = rt_retain(k);
xn_root_add(xn_t1496);
rt_string *xn_t1497 = rt_string_from_c("LocalDeclStmt.Var");
xn_root_add(xn_t1497);
    if ((xn_str_eq(xn_t1496, xn_t1497))) {
        size_t xn_t1498 = xn_root_mark();
        #line 948 "impl/lib/b2/xparser.x"
        rt_string *xn_t1499 = rt_string_from_c("s");
xn_root_add(xn_t1499);
        xn_root_add(xn_t1499);
        xn_root_add(xn_t1499);
            {
        xn_root_restore(xn_t1498);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1499;

    }
#line 949 "impl/lib/b2/xparser.x"
rt_string *xn_t1500 = rt_retain(k);
xn_root_add(xn_t1500);
rt_string *xn_t1501 = rt_string_from_c("MapLit.Keys");
xn_root_add(xn_t1501);
    if ((xn_str_eq(xn_t1500, xn_t1501))) {
        size_t xn_t1502 = xn_root_mark();
        #line 949 "impl/lib/b2/xparser.x"
        rt_string *xn_t1503 = rt_string_from_c("si");
xn_root_add(xn_t1503);
        xn_root_add(xn_t1503);
        xn_root_add(xn_t1503);
            {
        xn_root_restore(xn_t1502);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1503;

    }
#line 950 "impl/lib/b2/xparser.x"
rt_string *xn_t1504 = rt_retain(k);
xn_root_add(xn_t1504);
rt_string *xn_t1505 = rt_string_from_c("MapLit.P");
xn_root_add(xn_t1505);
    if ((xn_str_eq(xn_t1504, xn_t1505))) {
        size_t xn_t1506 = xn_root_mark();
        #line 950 "impl/lib/b2/xparser.x"
        rt_string *xn_t1507 = rt_string_from_c("v");
xn_root_add(xn_t1507);
        xn_root_add(xn_t1507);
        xn_root_add(xn_t1507);
            {
        xn_root_restore(xn_t1506);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1507;

    }
#line 951 "impl/lib/b2/xparser.x"
rt_string *xn_t1508 = rt_retain(k);
xn_root_add(xn_t1508);
rt_string *xn_t1509 = rt_string_from_c("MapLit.Vals");
xn_root_add(xn_t1509);
    if ((xn_str_eq(xn_t1508, xn_t1509))) {
        size_t xn_t1510 = xn_root_mark();
        #line 951 "impl/lib/b2/xparser.x"
        rt_string *xn_t1511 = rt_string_from_c("si");
xn_root_add(xn_t1511);
        xn_root_add(xn_t1511);
        xn_root_add(xn_t1511);
            {
        xn_root_restore(xn_t1510);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1511;

    }
#line 952 "impl/lib/b2/xparser.x"
rt_string *xn_t1512 = rt_retain(k);
xn_root_add(xn_t1512);
rt_string *xn_t1513 = rt_string_from_c("Member.Name");
xn_root_add(xn_t1513);
    if ((xn_str_eq(xn_t1512, xn_t1513))) {
        size_t xn_t1514 = xn_root_mark();
        #line 952 "impl/lib/b2/xparser.x"
        rt_string *xn_t1515 = rt_string_from_c("s");
xn_root_add(xn_t1515);
        xn_root_add(xn_t1515);
        xn_root_add(xn_t1515);
            {
        xn_root_restore(xn_t1514);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1515;

    }
#line 953 "impl/lib/b2/xparser.x"
rt_string *xn_t1516 = rt_retain(k);
xn_root_add(xn_t1516);
rt_string *xn_t1517 = rt_string_from_c("Member.NullSafe");
xn_root_add(xn_t1517);
    if ((xn_str_eq(xn_t1516, xn_t1517))) {
        size_t xn_t1518 = xn_root_mark();
        #line 953 "impl/lib/b2/xparser.x"
        rt_string *xn_t1519 = rt_string_from_c("s");
xn_root_add(xn_t1519);
        xn_root_add(xn_t1519);
        xn_root_add(xn_t1519);
            {
        xn_root_restore(xn_t1518);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1519;

    }
#line 954 "impl/lib/b2/xparser.x"
rt_string *xn_t1520 = rt_retain(k);
xn_root_add(xn_t1520);
rt_string *xn_t1521 = rt_string_from_c("Member.P");
xn_root_add(xn_t1521);
    if ((xn_str_eq(xn_t1520, xn_t1521))) {
        size_t xn_t1522 = xn_root_mark();
        #line 954 "impl/lib/b2/xparser.x"
        rt_string *xn_t1523 = rt_string_from_c("v");
xn_root_add(xn_t1523);
        xn_root_add(xn_t1523);
        xn_root_add(xn_t1523);
            {
        xn_root_restore(xn_t1522);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1523;

    }
#line 955 "impl/lib/b2/xparser.x"
rt_string *xn_t1524 = rt_retain(k);
xn_root_add(xn_t1524);
rt_string *xn_t1525 = rt_string_from_c("Member.X");
xn_root_add(xn_t1525);
    if ((xn_str_eq(xn_t1524, xn_t1525))) {
        size_t xn_t1526 = xn_root_mark();
        #line 955 "impl/lib/b2/xparser.x"
        rt_string *xn_t1527 = rt_string_from_c("i");
xn_root_add(xn_t1527);
        xn_root_add(xn_t1527);
        xn_root_add(xn_t1527);
            {
        xn_root_restore(xn_t1526);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1527;

    }
#line 956 "impl/lib/b2/xparser.x"
rt_string *xn_t1528 = rt_retain(k);
xn_root_add(xn_t1528);
rt_string *xn_t1529 = rt_string_from_c("MethodDecl.Annos");
xn_root_add(xn_t1529);
    if ((xn_str_eq(xn_t1528, xn_t1529))) {
        size_t xn_t1530 = xn_root_mark();
        #line 956 "impl/lib/b2/xparser.x"
        rt_string *xn_t1531 = rt_string_from_c("sp");
xn_root_add(xn_t1531);
        xn_root_add(xn_t1531);
        xn_root_add(xn_t1531);
            {
        xn_root_restore(xn_t1530);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1531;

    }
#line 957 "impl/lib/b2/xparser.x"
rt_string *xn_t1532 = rt_retain(k);
xn_root_add(xn_t1532);
rt_string *xn_t1533 = rt_string_from_c("MethodDecl.Body");
xn_root_add(xn_t1533);
    if ((xn_str_eq(xn_t1532, xn_t1533))) {
        size_t xn_t1534 = xn_root_mark();
        #line 957 "impl/lib/b2/xparser.x"
        rt_string *xn_t1535 = rt_string_from_c("p");
xn_root_add(xn_t1535);
        xn_root_add(xn_t1535);
        xn_root_add(xn_t1535);
            {
        xn_root_restore(xn_t1534);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1535;

    }
#line 958 "impl/lib/b2/xparser.x"
rt_string *xn_t1536 = rt_retain(k);
xn_root_add(xn_t1536);
rt_string *xn_t1537 = rt_string_from_c("MethodDecl.IsDeinit");
xn_root_add(xn_t1537);
    if ((xn_str_eq(xn_t1536, xn_t1537))) {
        size_t xn_t1538 = xn_root_mark();
        #line 958 "impl/lib/b2/xparser.x"
        rt_string *xn_t1539 = rt_string_from_c("s");
xn_root_add(xn_t1539);
        xn_root_add(xn_t1539);
        xn_root_add(xn_t1539);
            {
        xn_root_restore(xn_t1538);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1539;

    }
#line 959 "impl/lib/b2/xparser.x"
rt_string *xn_t1540 = rt_retain(k);
xn_root_add(xn_t1540);
rt_string *xn_t1541 = rt_string_from_c("MethodDecl.Mod");
xn_root_add(xn_t1541);
    if ((xn_str_eq(xn_t1540, xn_t1541))) {
        size_t xn_t1542 = xn_root_mark();
        #line 959 "impl/lib/b2/xparser.x"
        rt_string *xn_t1543 = rt_string_from_c("v");
xn_root_add(xn_t1543);
        xn_root_add(xn_t1543);
        xn_root_add(xn_t1543);
            {
        xn_root_restore(xn_t1542);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1543;

    }
#line 960 "impl/lib/b2/xparser.x"
rt_string *xn_t1544 = rt_retain(k);
xn_root_add(xn_t1544);
rt_string *xn_t1545 = rt_string_from_c("MethodDecl.Name");
xn_root_add(xn_t1545);
    if ((xn_str_eq(xn_t1544, xn_t1545))) {
        size_t xn_t1546 = xn_root_mark();
        #line 960 "impl/lib/b2/xparser.x"
        rt_string *xn_t1547 = rt_string_from_c("s");
xn_root_add(xn_t1547);
        xn_root_add(xn_t1547);
        xn_root_add(xn_t1547);
            {
        xn_root_restore(xn_t1546);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1547;

    }
#line 961 "impl/lib/b2/xparser.x"
rt_string *xn_t1548 = rt_retain(k);
xn_root_add(xn_t1548);
rt_string *xn_t1549 = rt_string_from_c("MethodDecl.P");
xn_root_add(xn_t1549);
    if ((xn_str_eq(xn_t1548, xn_t1549))) {
        size_t xn_t1550 = xn_root_mark();
        #line 961 "impl/lib/b2/xparser.x"
        rt_string *xn_t1551 = rt_string_from_c("v");
xn_root_add(xn_t1551);
        xn_root_add(xn_t1551);
        xn_root_add(xn_t1551);
            {
        xn_root_restore(xn_t1550);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1551;

    }
#line 962 "impl/lib/b2/xparser.x"
rt_string *xn_t1552 = rt_retain(k);
xn_root_add(xn_t1552);
rt_string *xn_t1553 = rt_string_from_c("MethodDecl.Params");
xn_root_add(xn_t1553);
    if ((xn_str_eq(xn_t1552, xn_t1553))) {
        size_t xn_t1554 = xn_root_mark();
        #line 962 "impl/lib/b2/xparser.x"
        rt_string *xn_t1555 = rt_string_from_c("sp");
xn_root_add(xn_t1555);
        xn_root_add(xn_t1555);
        xn_root_add(xn_t1555);
            {
        xn_root_restore(xn_t1554);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1555;

    }
#line 963 "impl/lib/b2/xparser.x"
rt_string *xn_t1556 = rt_retain(k);
xn_root_add(xn_t1556);
rt_string *xn_t1557 = rt_string_from_c("MethodDecl.Ret");
xn_root_add(xn_t1557);
    if ((xn_str_eq(xn_t1556, xn_t1557))) {
        size_t xn_t1558 = xn_root_mark();
        #line 963 "impl/lib/b2/xparser.x"
        rt_string *xn_t1559 = rt_string_from_c("i");
xn_root_add(xn_t1559);
        xn_root_add(xn_t1559);
        xn_root_add(xn_t1559);
            {
        xn_root_restore(xn_t1558);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1559;

    }
#line 964 "impl/lib/b2/xparser.x"
rt_string *xn_t1560 = rt_retain(k);
xn_root_add(xn_t1560);
rt_string *xn_t1561 = rt_string_from_c("MethodDecl.TypePars");
xn_root_add(xn_t1561);
    if ((xn_str_eq(xn_t1560, xn_t1561))) {
        size_t xn_t1562 = xn_root_mark();
        #line 964 "impl/lib/b2/xparser.x"
        rt_string *xn_t1563 = rt_string_from_c("ss");
xn_root_add(xn_t1563);
        xn_root_add(xn_t1563);
        xn_root_add(xn_t1563);
            {
        xn_root_restore(xn_t1562);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1563;

    }
#line 965 "impl/lib/b2/xparser.x"
rt_string *xn_t1564 = rt_retain(k);
xn_root_add(xn_t1564);
rt_string *xn_t1565 = rt_string_from_c("MethodDecl.Void");
xn_root_add(xn_t1565);
    if ((xn_str_eq(xn_t1564, xn_t1565))) {
        size_t xn_t1566 = xn_root_mark();
        #line 965 "impl/lib/b2/xparser.x"
        rt_string *xn_t1567 = rt_string_from_c("s");
xn_root_add(xn_t1567);
        xn_root_add(xn_t1567);
        xn_root_add(xn_t1567);
            {
        xn_root_restore(xn_t1566);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1567;

    }
#line 966 "impl/lib/b2/xparser.x"
rt_string *xn_t1568 = rt_retain(k);
xn_root_add(xn_t1568);
rt_string *xn_t1569 = rt_string_from_c("NamedType.Args");
xn_root_add(xn_t1569);
    if ((xn_str_eq(xn_t1568, xn_t1569))) {
        size_t xn_t1570 = xn_root_mark();
        #line 966 "impl/lib/b2/xparser.x"
        rt_string *xn_t1571 = rt_string_from_c("si");
xn_root_add(xn_t1571);
        xn_root_add(xn_t1571);
        xn_root_add(xn_t1571);
            {
        xn_root_restore(xn_t1570);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1571;

    }
#line 967 "impl/lib/b2/xparser.x"
rt_string *xn_t1572 = rt_retain(k);
xn_root_add(xn_t1572);
rt_string *xn_t1573 = rt_string_from_c("NamedType.P");
xn_root_add(xn_t1573);
    if ((xn_str_eq(xn_t1572, xn_t1573))) {
        size_t xn_t1574 = xn_root_mark();
        #line 967 "impl/lib/b2/xparser.x"
        rt_string *xn_t1575 = rt_string_from_c("v");
xn_root_add(xn_t1575);
        xn_root_add(xn_t1575);
        xn_root_add(xn_t1575);
            {
        xn_root_restore(xn_t1574);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1575;

    }
#line 968 "impl/lib/b2/xparser.x"
rt_string *xn_t1576 = rt_retain(k);
xn_root_add(xn_t1576);
rt_string *xn_t1577 = rt_string_from_c("NamedType.Qual");
xn_root_add(xn_t1577);
    if ((xn_str_eq(xn_t1576, xn_t1577))) {
        size_t xn_t1578 = xn_root_mark();
        #line 968 "impl/lib/b2/xparser.x"
        rt_string *xn_t1579 = rt_string_from_c("ss");
xn_root_add(xn_t1579);
        xn_root_add(xn_t1579);
        xn_root_add(xn_t1579);
            {
        xn_root_restore(xn_t1578);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1579;

    }
#line 969 "impl/lib/b2/xparser.x"
rt_string *xn_t1580 = rt_retain(k);
xn_root_add(xn_t1580);
rt_string *xn_t1581 = rt_string_from_c("New.Args");
xn_root_add(xn_t1581);
    if ((xn_str_eq(xn_t1580, xn_t1581))) {
        size_t xn_t1582 = xn_root_mark();
        #line 969 "impl/lib/b2/xparser.x"
        rt_string *xn_t1583 = rt_string_from_c("si");
xn_root_add(xn_t1583);
        xn_root_add(xn_t1583);
        xn_root_add(xn_t1583);
            {
        xn_root_restore(xn_t1582);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1583;

    }
#line 970 "impl/lib/b2/xparser.x"
rt_string *xn_t1584 = rt_retain(k);
xn_root_add(xn_t1584);
rt_string *xn_t1585 = rt_string_from_c("New.P");
xn_root_add(xn_t1585);
    if ((xn_str_eq(xn_t1584, xn_t1585))) {
        size_t xn_t1586 = xn_root_mark();
        #line 970 "impl/lib/b2/xparser.x"
        rt_string *xn_t1587 = rt_string_from_c("v");
xn_root_add(xn_t1587);
        xn_root_add(xn_t1587);
        xn_root_add(xn_t1587);
            {
        xn_root_restore(xn_t1586);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1587;

    }
#line 971 "impl/lib/b2/xparser.x"
rt_string *xn_t1588 = rt_retain(k);
xn_root_add(xn_t1588);
rt_string *xn_t1589 = rt_string_from_c("New.Type");
xn_root_add(xn_t1589);
    if ((xn_str_eq(xn_t1588, xn_t1589))) {
        size_t xn_t1590 = xn_root_mark();
        #line 971 "impl/lib/b2/xparser.x"
        rt_string *xn_t1591 = rt_string_from_c("i");
xn_root_add(xn_t1591);
        xn_root_add(xn_t1591);
        xn_root_add(xn_t1591);
            {
        xn_root_restore(xn_t1590);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1591;

    }
#line 972 "impl/lib/b2/xparser.x"
rt_string *xn_t1592 = rt_retain(k);
xn_root_add(xn_t1592);
rt_string *xn_t1593 = rt_string_from_c("NewArray.Count");
xn_root_add(xn_t1593);
    if ((xn_str_eq(xn_t1592, xn_t1593))) {
        size_t xn_t1594 = xn_root_mark();
        #line 972 "impl/lib/b2/xparser.x"
        rt_string *xn_t1595 = rt_string_from_c("i");
xn_root_add(xn_t1595);
        xn_root_add(xn_t1595);
        xn_root_add(xn_t1595);
            {
        xn_root_restore(xn_t1594);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1595;

    }
#line 973 "impl/lib/b2/xparser.x"
rt_string *xn_t1596 = rt_retain(k);
xn_root_add(xn_t1596);
rt_string *xn_t1597 = rt_string_from_c("NewArray.P");
xn_root_add(xn_t1597);
    if ((xn_str_eq(xn_t1596, xn_t1597))) {
        size_t xn_t1598 = xn_root_mark();
        #line 973 "impl/lib/b2/xparser.x"
        rt_string *xn_t1599 = rt_string_from_c("v");
xn_root_add(xn_t1599);
        xn_root_add(xn_t1599);
        xn_root_add(xn_t1599);
            {
        xn_root_restore(xn_t1598);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1599;

    }
#line 974 "impl/lib/b2/xparser.x"
rt_string *xn_t1600 = rt_retain(k);
xn_root_add(xn_t1600);
rt_string *xn_t1601 = rt_string_from_c("NewArray.Type");
xn_root_add(xn_t1601);
    if ((xn_str_eq(xn_t1600, xn_t1601))) {
        size_t xn_t1602 = xn_root_mark();
        #line 974 "impl/lib/b2/xparser.x"
        rt_string *xn_t1603 = rt_string_from_c("i");
xn_root_add(xn_t1603);
        xn_root_add(xn_t1603);
        xn_root_add(xn_t1603);
            {
        xn_root_restore(xn_t1602);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1603;

    }
#line 975 "impl/lib/b2/xparser.x"
rt_string *xn_t1604 = rt_retain(k);
xn_root_add(xn_t1604);
rt_string *xn_t1605 = rt_string_from_c("PackageDecl.Name");
xn_root_add(xn_t1605);
    if ((xn_str_eq(xn_t1604, xn_t1605))) {
        size_t xn_t1606 = xn_root_mark();
        #line 975 "impl/lib/b2/xparser.x"
        rt_string *xn_t1607 = rt_string_from_c("ss");
xn_root_add(xn_t1607);
        xn_root_add(xn_t1607);
        xn_root_add(xn_t1607);
            {
        xn_root_restore(xn_t1606);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1607;

    }
#line 976 "impl/lib/b2/xparser.x"
rt_string *xn_t1608 = rt_retain(k);
xn_root_add(xn_t1608);
rt_string *xn_t1609 = rt_string_from_c("PackageDecl.P");
xn_root_add(xn_t1609);
    if ((xn_str_eq(xn_t1608, xn_t1609))) {
        size_t xn_t1610 = xn_root_mark();
        #line 976 "impl/lib/b2/xparser.x"
        rt_string *xn_t1611 = rt_string_from_c("v");
xn_root_add(xn_t1611);
        xn_root_add(xn_t1611);
        xn_root_add(xn_t1611);
            {
        xn_root_restore(xn_t1610);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1611;

    }
#line 977 "impl/lib/b2/xparser.x"
rt_string *xn_t1612 = rt_retain(k);
xn_root_add(xn_t1612);
rt_string *xn_t1613 = rt_string_from_c("Param.Annos");
xn_root_add(xn_t1613);
    if ((xn_str_eq(xn_t1612, xn_t1613))) {
        size_t xn_t1614 = xn_root_mark();
        #line 977 "impl/lib/b2/xparser.x"
        rt_string *xn_t1615 = rt_string_from_c("sp");
xn_root_add(xn_t1615);
        xn_root_add(xn_t1615);
        xn_root_add(xn_t1615);
            {
        xn_root_restore(xn_t1614);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1615;

    }
#line 978 "impl/lib/b2/xparser.x"
rt_string *xn_t1616 = rt_retain(k);
xn_root_add(xn_t1616);
rt_string *xn_t1617 = rt_string_from_c("Param.Final");
xn_root_add(xn_t1617);
    if ((xn_str_eq(xn_t1616, xn_t1617))) {
        size_t xn_t1618 = xn_root_mark();
        #line 978 "impl/lib/b2/xparser.x"
        rt_string *xn_t1619 = rt_string_from_c("s");
xn_root_add(xn_t1619);
        xn_root_add(xn_t1619);
        xn_root_add(xn_t1619);
            {
        xn_root_restore(xn_t1618);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1619;

    }
#line 979 "impl/lib/b2/xparser.x"
rt_string *xn_t1620 = rt_retain(k);
xn_root_add(xn_t1620);
rt_string *xn_t1621 = rt_string_from_c("Param.Name");
xn_root_add(xn_t1621);
    if ((xn_str_eq(xn_t1620, xn_t1621))) {
        size_t xn_t1622 = xn_root_mark();
        #line 979 "impl/lib/b2/xparser.x"
        rt_string *xn_t1623 = rt_string_from_c("s");
xn_root_add(xn_t1623);
        xn_root_add(xn_t1623);
        xn_root_add(xn_t1623);
            {
        xn_root_restore(xn_t1622);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1623;

    }
#line 980 "impl/lib/b2/xparser.x"
rt_string *xn_t1624 = rt_retain(k);
xn_root_add(xn_t1624);
rt_string *xn_t1625 = rt_string_from_c("Param.P");
xn_root_add(xn_t1625);
    if ((xn_str_eq(xn_t1624, xn_t1625))) {
        size_t xn_t1626 = xn_root_mark();
        #line 980 "impl/lib/b2/xparser.x"
        rt_string *xn_t1627 = rt_string_from_c("v");
xn_root_add(xn_t1627);
        xn_root_add(xn_t1627);
        xn_root_add(xn_t1627);
            {
        xn_root_restore(xn_t1626);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1627;

    }
#line 981 "impl/lib/b2/xparser.x"
rt_string *xn_t1628 = rt_retain(k);
xn_root_add(xn_t1628);
rt_string *xn_t1629 = rt_string_from_c("Param.Type");
xn_root_add(xn_t1629);
    if ((xn_str_eq(xn_t1628, xn_t1629))) {
        size_t xn_t1630 = xn_root_mark();
        #line 981 "impl/lib/b2/xparser.x"
        rt_string *xn_t1631 = rt_string_from_c("i");
xn_root_add(xn_t1631);
        xn_root_add(xn_t1631);
        xn_root_add(xn_t1631);
            {
        xn_root_restore(xn_t1630);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1631;

    }
#line 982 "impl/lib/b2/xparser.x"
rt_string *xn_t1632 = rt_retain(k);
xn_root_add(xn_t1632);
rt_string *xn_t1633 = rt_string_from_c("Paren.P");
xn_root_add(xn_t1633);
    if ((xn_str_eq(xn_t1632, xn_t1633))) {
        size_t xn_t1634 = xn_root_mark();
        #line 982 "impl/lib/b2/xparser.x"
        rt_string *xn_t1635 = rt_string_from_c("v");
xn_root_add(xn_t1635);
        xn_root_add(xn_t1635);
        xn_root_add(xn_t1635);
            {
        xn_root_restore(xn_t1634);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1635;

    }
#line 983 "impl/lib/b2/xparser.x"
rt_string *xn_t1636 = rt_retain(k);
xn_root_add(xn_t1636);
rt_string *xn_t1637 = rt_string_from_c("Paren.X");
xn_root_add(xn_t1637);
    if ((xn_str_eq(xn_t1636, xn_t1637))) {
        size_t xn_t1638 = xn_root_mark();
        #line 983 "impl/lib/b2/xparser.x"
        rt_string *xn_t1639 = rt_string_from_c("i");
xn_root_add(xn_t1639);
        xn_root_add(xn_t1639);
        xn_root_add(xn_t1639);
            {
        xn_root_restore(xn_t1638);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1639;

    }
#line 984 "impl/lib/b2/xparser.x"
rt_string *xn_t1640 = rt_retain(k);
xn_root_add(xn_t1640);
rt_string *xn_t1641 = rt_string_from_c("Pos.Col");
xn_root_add(xn_t1641);
    if ((xn_str_eq(xn_t1640, xn_t1641))) {
        size_t xn_t1642 = xn_root_mark();
        #line 984 "impl/lib/b2/xparser.x"
        rt_string *xn_t1643 = rt_string_from_c("s");
xn_root_add(xn_t1643);
        xn_root_add(xn_t1643);
        xn_root_add(xn_t1643);
            {
        xn_root_restore(xn_t1642);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1643;

    }
#line 985 "impl/lib/b2/xparser.x"
rt_string *xn_t1644 = rt_retain(k);
xn_root_add(xn_t1644);
rt_string *xn_t1645 = rt_string_from_c("Pos.Line");
xn_root_add(xn_t1645);
    if ((xn_str_eq(xn_t1644, xn_t1645))) {
        size_t xn_t1646 = xn_root_mark();
        #line 985 "impl/lib/b2/xparser.x"
        rt_string *xn_t1647 = rt_string_from_c("s");
xn_root_add(xn_t1647);
        xn_root_add(xn_t1647);
        xn_root_add(xn_t1647);
            {
        xn_root_restore(xn_t1646);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1647;

    }
#line 986 "impl/lib/b2/xparser.x"
rt_string *xn_t1648 = rt_retain(k);
xn_root_add(xn_t1648);
rt_string *xn_t1649 = rt_string_from_c("ProtocolDecl.Annos");
xn_root_add(xn_t1649);
    if ((xn_str_eq(xn_t1648, xn_t1649))) {
        size_t xn_t1650 = xn_root_mark();
        #line 986 "impl/lib/b2/xparser.x"
        rt_string *xn_t1651 = rt_string_from_c("sp");
xn_root_add(xn_t1651);
        xn_root_add(xn_t1651);
        xn_root_add(xn_t1651);
            {
        xn_root_restore(xn_t1650);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1651;

    }
#line 987 "impl/lib/b2/xparser.x"
rt_string *xn_t1652 = rt_retain(k);
xn_root_add(xn_t1652);
rt_string *xn_t1653 = rt_string_from_c("ProtocolDecl.Extends");
xn_root_add(xn_t1653);
    if ((xn_str_eq(xn_t1652, xn_t1653))) {
        size_t xn_t1654 = xn_root_mark();
        #line 987 "impl/lib/b2/xparser.x"
        rt_string *xn_t1655 = rt_string_from_c("sp");
xn_root_add(xn_t1655);
        xn_root_add(xn_t1655);
        xn_root_add(xn_t1655);
            {
        xn_root_restore(xn_t1654);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1655;

    }
#line 988 "impl/lib/b2/xparser.x"
rt_string *xn_t1656 = rt_retain(k);
xn_root_add(xn_t1656);
rt_string *xn_t1657 = rt_string_from_c("ProtocolDecl.Name");
xn_root_add(xn_t1657);
    if ((xn_str_eq(xn_t1656, xn_t1657))) {
        size_t xn_t1658 = xn_root_mark();
        #line 988 "impl/lib/b2/xparser.x"
        rt_string *xn_t1659 = rt_string_from_c("s");
xn_root_add(xn_t1659);
        xn_root_add(xn_t1659);
        xn_root_add(xn_t1659);
            {
        xn_root_restore(xn_t1658);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1659;

    }
#line 989 "impl/lib/b2/xparser.x"
rt_string *xn_t1660 = rt_retain(k);
xn_root_add(xn_t1660);
rt_string *xn_t1661 = rt_string_from_c("ProtocolDecl.P");
xn_root_add(xn_t1661);
    if ((xn_str_eq(xn_t1660, xn_t1661))) {
        size_t xn_t1662 = xn_root_mark();
        #line 989 "impl/lib/b2/xparser.x"
        rt_string *xn_t1663 = rt_string_from_c("v");
xn_root_add(xn_t1663);
        xn_root_add(xn_t1663);
        xn_root_add(xn_t1663);
            {
        xn_root_restore(xn_t1662);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1663;

    }
#line 990 "impl/lib/b2/xparser.x"
rt_string *xn_t1664 = rt_retain(k);
xn_root_add(xn_t1664);
rt_string *xn_t1665 = rt_string_from_c("ProtocolDecl.Sigs");
xn_root_add(xn_t1665);
    if ((xn_str_eq(xn_t1664, xn_t1665))) {
        size_t xn_t1666 = xn_root_mark();
        #line 990 "impl/lib/b2/xparser.x"
        rt_string *xn_t1667 = rt_string_from_c("sp");
xn_root_add(xn_t1667);
        xn_root_add(xn_t1667);
        xn_root_add(xn_t1667);
            {
        xn_root_restore(xn_t1666);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1667;

    }
#line 991 "impl/lib/b2/xparser.x"
rt_string *xn_t1668 = rt_retain(k);
xn_root_add(xn_t1668);
rt_string *xn_t1669 = rt_string_from_c("ProtocolSig.Annos");
xn_root_add(xn_t1669);
    if ((xn_str_eq(xn_t1668, xn_t1669))) {
        size_t xn_t1670 = xn_root_mark();
        #line 991 "impl/lib/b2/xparser.x"
        rt_string *xn_t1671 = rt_string_from_c("sp");
xn_root_add(xn_t1671);
        xn_root_add(xn_t1671);
        xn_root_add(xn_t1671);
            {
        xn_root_restore(xn_t1670);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1671;

    }
#line 992 "impl/lib/b2/xparser.x"
rt_string *xn_t1672 = rt_retain(k);
xn_root_add(xn_t1672);
rt_string *xn_t1673 = rt_string_from_c("ProtocolSig.Mod");
xn_root_add(xn_t1673);
    if ((xn_str_eq(xn_t1672, xn_t1673))) {
        size_t xn_t1674 = xn_root_mark();
        #line 992 "impl/lib/b2/xparser.x"
        rt_string *xn_t1675 = rt_string_from_c("v");
xn_root_add(xn_t1675);
        xn_root_add(xn_t1675);
        xn_root_add(xn_t1675);
            {
        xn_root_restore(xn_t1674);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1675;

    }
#line 993 "impl/lib/b2/xparser.x"
rt_string *xn_t1676 = rt_retain(k);
xn_root_add(xn_t1676);
rt_string *xn_t1677 = rt_string_from_c("ProtocolSig.Name");
xn_root_add(xn_t1677);
    if ((xn_str_eq(xn_t1676, xn_t1677))) {
        size_t xn_t1678 = xn_root_mark();
        #line 993 "impl/lib/b2/xparser.x"
        rt_string *xn_t1679 = rt_string_from_c("s");
xn_root_add(xn_t1679);
        xn_root_add(xn_t1679);
        xn_root_add(xn_t1679);
            {
        xn_root_restore(xn_t1678);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1679;

    }
#line 994 "impl/lib/b2/xparser.x"
rt_string *xn_t1680 = rt_retain(k);
xn_root_add(xn_t1680);
rt_string *xn_t1681 = rt_string_from_c("ProtocolSig.P");
xn_root_add(xn_t1681);
    if ((xn_str_eq(xn_t1680, xn_t1681))) {
        size_t xn_t1682 = xn_root_mark();
        #line 994 "impl/lib/b2/xparser.x"
        rt_string *xn_t1683 = rt_string_from_c("v");
xn_root_add(xn_t1683);
        xn_root_add(xn_t1683);
        xn_root_add(xn_t1683);
            {
        xn_root_restore(xn_t1682);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1683;

    }
#line 995 "impl/lib/b2/xparser.x"
rt_string *xn_t1684 = rt_retain(k);
xn_root_add(xn_t1684);
rt_string *xn_t1685 = rt_string_from_c("ProtocolSig.Params");
xn_root_add(xn_t1685);
    if ((xn_str_eq(xn_t1684, xn_t1685))) {
        size_t xn_t1686 = xn_root_mark();
        #line 995 "impl/lib/b2/xparser.x"
        rt_string *xn_t1687 = rt_string_from_c("sp");
xn_root_add(xn_t1687);
        xn_root_add(xn_t1687);
        xn_root_add(xn_t1687);
            {
        xn_root_restore(xn_t1686);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1687;

    }
#line 996 "impl/lib/b2/xparser.x"
rt_string *xn_t1688 = rt_retain(k);
xn_root_add(xn_t1688);
rt_string *xn_t1689 = rt_string_from_c("ProtocolSig.Ret");
xn_root_add(xn_t1689);
    if ((xn_str_eq(xn_t1688, xn_t1689))) {
        size_t xn_t1690 = xn_root_mark();
        #line 996 "impl/lib/b2/xparser.x"
        rt_string *xn_t1691 = rt_string_from_c("i");
xn_root_add(xn_t1691);
        xn_root_add(xn_t1691);
        xn_root_add(xn_t1691);
            {
        xn_root_restore(xn_t1690);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1691;

    }
#line 997 "impl/lib/b2/xparser.x"
rt_string *xn_t1692 = rt_retain(k);
xn_root_add(xn_t1692);
rt_string *xn_t1693 = rt_string_from_c("ProtocolSig.Void");
xn_root_add(xn_t1693);
    if ((xn_str_eq(xn_t1692, xn_t1693))) {
        size_t xn_t1694 = xn_root_mark();
        #line 997 "impl/lib/b2/xparser.x"
        rt_string *xn_t1695 = rt_string_from_c("s");
xn_root_add(xn_t1695);
        xn_root_add(xn_t1695);
        xn_root_add(xn_t1695);
            {
        xn_root_restore(xn_t1694);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1695;

    }
#line 998 "impl/lib/b2/xparser.x"
rt_string *xn_t1696 = rt_retain(k);
xn_root_add(xn_t1696);
rt_string *xn_t1697 = rt_string_from_c("ReturnStmt.P");
xn_root_add(xn_t1697);
    if ((xn_str_eq(xn_t1696, xn_t1697))) {
        size_t xn_t1698 = xn_root_mark();
        #line 998 "impl/lib/b2/xparser.x"
        rt_string *xn_t1699 = rt_string_from_c("v");
xn_root_add(xn_t1699);
        xn_root_add(xn_t1699);
        xn_root_add(xn_t1699);
            {
        xn_root_restore(xn_t1698);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1699;

    }
#line 999 "impl/lib/b2/xparser.x"
rt_string *xn_t1700 = rt_retain(k);
xn_root_add(xn_t1700);
rt_string *xn_t1701 = rt_string_from_c("ReturnStmt.Value");
xn_root_add(xn_t1701);
    if ((xn_str_eq(xn_t1700, xn_t1701))) {
        size_t xn_t1702 = xn_root_mark();
        #line 999 "impl/lib/b2/xparser.x"
        rt_string *xn_t1703 = rt_string_from_c("i");
xn_root_add(xn_t1703);
        xn_root_add(xn_t1703);
        xn_root_add(xn_t1703);
            {
        xn_root_restore(xn_t1702);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1703;

    }
#line 1000 "impl/lib/b2/xparser.x"
rt_string *xn_t1704 = rt_retain(k);
xn_root_add(xn_t1704);
rt_string *xn_t1705 = rt_string_from_c("SingletonDecl.Annos");
xn_root_add(xn_t1705);
    if ((xn_str_eq(xn_t1704, xn_t1705))) {
        size_t xn_t1706 = xn_root_mark();
        #line 1000 "impl/lib/b2/xparser.x"
        rt_string *xn_t1707 = rt_string_from_c("sp");
xn_root_add(xn_t1707);
        xn_root_add(xn_t1707);
        xn_root_add(xn_t1707);
            {
        xn_root_restore(xn_t1706);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1707;

    }
#line 1001 "impl/lib/b2/xparser.x"
rt_string *xn_t1708 = rt_retain(k);
xn_root_add(xn_t1708);
rt_string *xn_t1709 = rt_string_from_c("SingletonDecl.Ctors");
xn_root_add(xn_t1709);
    if ((xn_str_eq(xn_t1708, xn_t1709))) {
        size_t xn_t1710 = xn_root_mark();
        #line 1001 "impl/lib/b2/xparser.x"
        rt_string *xn_t1711 = rt_string_from_c("sp");
xn_root_add(xn_t1711);
        xn_root_add(xn_t1711);
        xn_root_add(xn_t1711);
            {
        xn_root_restore(xn_t1710);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1711;

    }
#line 1002 "impl/lib/b2/xparser.x"
rt_string *xn_t1712 = rt_retain(k);
xn_root_add(xn_t1712);
rt_string *xn_t1713 = rt_string_from_c("SingletonDecl.Fields");
xn_root_add(xn_t1713);
    if ((xn_str_eq(xn_t1712, xn_t1713))) {
        size_t xn_t1714 = xn_root_mark();
        #line 1002 "impl/lib/b2/xparser.x"
        rt_string *xn_t1715 = rt_string_from_c("sp");
xn_root_add(xn_t1715);
        xn_root_add(xn_t1715);
        xn_root_add(xn_t1715);
            {
        xn_root_restore(xn_t1714);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1715;

    }
#line 1003 "impl/lib/b2/xparser.x"
rt_string *xn_t1716 = rt_retain(k);
xn_root_add(xn_t1716);
rt_string *xn_t1717 = rt_string_from_c("SingletonDecl.Methods");
xn_root_add(xn_t1717);
    if ((xn_str_eq(xn_t1716, xn_t1717))) {
        size_t xn_t1718 = xn_root_mark();
        #line 1003 "impl/lib/b2/xparser.x"
        rt_string *xn_t1719 = rt_string_from_c("sp");
xn_root_add(xn_t1719);
        xn_root_add(xn_t1719);
        xn_root_add(xn_t1719);
            {
        xn_root_restore(xn_t1718);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1719;

    }
#line 1004 "impl/lib/b2/xparser.x"
rt_string *xn_t1720 = rt_retain(k);
xn_root_add(xn_t1720);
rt_string *xn_t1721 = rt_string_from_c("SingletonDecl.Mod");
xn_root_add(xn_t1721);
    if ((xn_str_eq(xn_t1720, xn_t1721))) {
        size_t xn_t1722 = xn_root_mark();
        #line 1004 "impl/lib/b2/xparser.x"
        rt_string *xn_t1723 = rt_string_from_c("v");
xn_root_add(xn_t1723);
        xn_root_add(xn_t1723);
        xn_root_add(xn_t1723);
            {
        xn_root_restore(xn_t1722);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1723;

    }
#line 1005 "impl/lib/b2/xparser.x"
rt_string *xn_t1724 = rt_retain(k);
xn_root_add(xn_t1724);
rt_string *xn_t1725 = rt_string_from_c("SingletonDecl.Name");
xn_root_add(xn_t1725);
    if ((xn_str_eq(xn_t1724, xn_t1725))) {
        size_t xn_t1726 = xn_root_mark();
        #line 1005 "impl/lib/b2/xparser.x"
        rt_string *xn_t1727 = rt_string_from_c("s");
xn_root_add(xn_t1727);
        xn_root_add(xn_t1727);
        xn_root_add(xn_t1727);
            {
        xn_root_restore(xn_t1726);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1727;

    }
#line 1006 "impl/lib/b2/xparser.x"
rt_string *xn_t1728 = rt_retain(k);
xn_root_add(xn_t1728);
rt_string *xn_t1729 = rt_string_from_c("SingletonDecl.P");
xn_root_add(xn_t1729);
    if ((xn_str_eq(xn_t1728, xn_t1729))) {
        size_t xn_t1730 = xn_root_mark();
        #line 1006 "impl/lib/b2/xparser.x"
        rt_string *xn_t1731 = rt_string_from_c("v");
xn_root_add(xn_t1731);
        xn_root_add(xn_t1731);
        xn_root_add(xn_t1731);
            {
        xn_root_restore(xn_t1730);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1731;

    }
#line 1007 "impl/lib/b2/xparser.x"
rt_string *xn_t1732 = rt_retain(k);
xn_root_add(xn_t1732);
rt_string *xn_t1733 = rt_string_from_c("StrLitExpr.Kind");
xn_root_add(xn_t1733);
    if ((xn_str_eq(xn_t1732, xn_t1733))) {
        size_t xn_t1734 = xn_root_mark();
        #line 1007 "impl/lib/b2/xparser.x"
        rt_string *xn_t1735 = rt_string_from_c("s");
xn_root_add(xn_t1735);
        xn_root_add(xn_t1735);
        xn_root_add(xn_t1735);
            {
        xn_root_restore(xn_t1734);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1735;

    }
#line 1008 "impl/lib/b2/xparser.x"
rt_string *xn_t1736 = rt_retain(k);
xn_root_add(xn_t1736);
rt_string *xn_t1737 = rt_string_from_c("StrLitExpr.P");
xn_root_add(xn_t1737);
    if ((xn_str_eq(xn_t1736, xn_t1737))) {
        size_t xn_t1738 = xn_root_mark();
        #line 1008 "impl/lib/b2/xparser.x"
        rt_string *xn_t1739 = rt_string_from_c("v");
xn_root_add(xn_t1739);
        xn_root_add(xn_t1739);
        xn_root_add(xn_t1739);
            {
        xn_root_restore(xn_t1738);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1739;

    }
#line 1009 "impl/lib/b2/xparser.x"
rt_string *xn_t1740 = rt_retain(k);
xn_root_add(xn_t1740);
rt_string *xn_t1741 = rt_string_from_c("StrLitExpr.Parts");
xn_root_add(xn_t1741);
    if ((xn_str_eq(xn_t1740, xn_t1741))) {
        size_t xn_t1742 = xn_root_mark();
        #line 1009 "impl/lib/b2/xparser.x"
        rt_string *xn_t1743 = rt_string_from_c("sv");
xn_root_add(xn_t1743);
        xn_root_add(xn_t1743);
        xn_root_add(xn_t1743);
            {
        xn_root_restore(xn_t1742);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1743;

    }
#line 1010 "impl/lib/b2/xparser.x"
rt_string *xn_t1744 = rt_retain(k);
xn_root_add(xn_t1744);
rt_string *xn_t1745 = rt_string_from_c("StrPart.Expr");
xn_root_add(xn_t1745);
    if ((xn_str_eq(xn_t1744, xn_t1745))) {
        size_t xn_t1746 = xn_root_mark();
        #line 1010 "impl/lib/b2/xparser.x"
        rt_string *xn_t1747 = rt_string_from_c("i");
xn_root_add(xn_t1747);
        xn_root_add(xn_t1747);
        xn_root_add(xn_t1747);
            {
        xn_root_restore(xn_t1746);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1747;

    }
#line 1011 "impl/lib/b2/xparser.x"
rt_string *xn_t1748 = rt_retain(k);
xn_root_add(xn_t1748);
rt_string *xn_t1749 = rt_string_from_c("StrPart.Text");
xn_root_add(xn_t1749);
    if ((xn_str_eq(xn_t1748, xn_t1749))) {
        size_t xn_t1750 = xn_root_mark();
        #line 1011 "impl/lib/b2/xparser.x"
        rt_string *xn_t1751 = rt_string_from_c("s");
xn_root_add(xn_t1751);
        xn_root_add(xn_t1751);
        xn_root_add(xn_t1751);
            {
        xn_root_restore(xn_t1750);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1751;

    }
#line 1012 "impl/lib/b2/xparser.x"
rt_string *xn_t1752 = rt_retain(k);
xn_root_add(xn_t1752);
rt_string *xn_t1753 = rt_string_from_c("StructDecl.Annos");
xn_root_add(xn_t1753);
    if ((xn_str_eq(xn_t1752, xn_t1753))) {
        size_t xn_t1754 = xn_root_mark();
        #line 1012 "impl/lib/b2/xparser.x"
        rt_string *xn_t1755 = rt_string_from_c("sp");
xn_root_add(xn_t1755);
        xn_root_add(xn_t1755);
        xn_root_add(xn_t1755);
            {
        xn_root_restore(xn_t1754);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1755;

    }
#line 1013 "impl/lib/b2/xparser.x"
rt_string *xn_t1756 = rt_retain(k);
xn_root_add(xn_t1756);
rt_string *xn_t1757 = rt_string_from_c("StructDecl.Ctors");
xn_root_add(xn_t1757);
    if ((xn_str_eq(xn_t1756, xn_t1757))) {
        size_t xn_t1758 = xn_root_mark();
        #line 1013 "impl/lib/b2/xparser.x"
        rt_string *xn_t1759 = rt_string_from_c("sp");
xn_root_add(xn_t1759);
        xn_root_add(xn_t1759);
        xn_root_add(xn_t1759);
            {
        xn_root_restore(xn_t1758);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1759;

    }
#line 1014 "impl/lib/b2/xparser.x"
rt_string *xn_t1760 = rt_retain(k);
xn_root_add(xn_t1760);
rt_string *xn_t1761 = rt_string_from_c("StructDecl.Fields");
xn_root_add(xn_t1761);
    if ((xn_str_eq(xn_t1760, xn_t1761))) {
        size_t xn_t1762 = xn_root_mark();
        #line 1014 "impl/lib/b2/xparser.x"
        rt_string *xn_t1763 = rt_string_from_c("sp");
xn_root_add(xn_t1763);
        xn_root_add(xn_t1763);
        xn_root_add(xn_t1763);
            {
        xn_root_restore(xn_t1762);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1763;

    }
#line 1015 "impl/lib/b2/xparser.x"
rt_string *xn_t1764 = rt_retain(k);
xn_root_add(xn_t1764);
rt_string *xn_t1765 = rt_string_from_c("StructDecl.Methods");
xn_root_add(xn_t1765);
    if ((xn_str_eq(xn_t1764, xn_t1765))) {
        size_t xn_t1766 = xn_root_mark();
        #line 1015 "impl/lib/b2/xparser.x"
        rt_string *xn_t1767 = rt_string_from_c("sp");
xn_root_add(xn_t1767);
        xn_root_add(xn_t1767);
        xn_root_add(xn_t1767);
            {
        xn_root_restore(xn_t1766);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1767;

    }
#line 1016 "impl/lib/b2/xparser.x"
rt_string *xn_t1768 = rt_retain(k);
xn_root_add(xn_t1768);
rt_string *xn_t1769 = rt_string_from_c("StructDecl.Mod");
xn_root_add(xn_t1769);
    if ((xn_str_eq(xn_t1768, xn_t1769))) {
        size_t xn_t1770 = xn_root_mark();
        #line 1016 "impl/lib/b2/xparser.x"
        rt_string *xn_t1771 = rt_string_from_c("v");
xn_root_add(xn_t1771);
        xn_root_add(xn_t1771);
        xn_root_add(xn_t1771);
            {
        xn_root_restore(xn_t1770);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1771;

    }
#line 1017 "impl/lib/b2/xparser.x"
rt_string *xn_t1772 = rt_retain(k);
xn_root_add(xn_t1772);
rt_string *xn_t1773 = rt_string_from_c("StructDecl.Name");
xn_root_add(xn_t1773);
    if ((xn_str_eq(xn_t1772, xn_t1773))) {
        size_t xn_t1774 = xn_root_mark();
        #line 1017 "impl/lib/b2/xparser.x"
        rt_string *xn_t1775 = rt_string_from_c("s");
xn_root_add(xn_t1775);
        xn_root_add(xn_t1775);
        xn_root_add(xn_t1775);
            {
        xn_root_restore(xn_t1774);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1775;

    }
#line 1018 "impl/lib/b2/xparser.x"
rt_string *xn_t1776 = rt_retain(k);
xn_root_add(xn_t1776);
rt_string *xn_t1777 = rt_string_from_c("StructDecl.P");
xn_root_add(xn_t1777);
    if ((xn_str_eq(xn_t1776, xn_t1777))) {
        size_t xn_t1778 = xn_root_mark();
        #line 1018 "impl/lib/b2/xparser.x"
        rt_string *xn_t1779 = rt_string_from_c("v");
xn_root_add(xn_t1779);
        xn_root_add(xn_t1779);
        xn_root_add(xn_t1779);
            {
        xn_root_restore(xn_t1778);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1779;

    }
#line 1019 "impl/lib/b2/xparser.x"
rt_string *xn_t1780 = rt_retain(k);
xn_root_add(xn_t1780);
rt_string *xn_t1781 = rt_string_from_c("StructDecl.Primary");
xn_root_add(xn_t1781);
    if ((xn_str_eq(xn_t1780, xn_t1781))) {
        size_t xn_t1782 = xn_root_mark();
        #line 1019 "impl/lib/b2/xparser.x"
        rt_string *xn_t1783 = rt_string_from_c("p");
xn_root_add(xn_t1783);
        xn_root_add(xn_t1783);
        xn_root_add(xn_t1783);
            {
        xn_root_restore(xn_t1782);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1783;

    }
#line 1020 "impl/lib/b2/xparser.x"
rt_string *xn_t1784 = rt_retain(k);
xn_root_add(xn_t1784);
rt_string *xn_t1785 = rt_string_from_c("StructDecl.TypePars");
xn_root_add(xn_t1785);
    if ((xn_str_eq(xn_t1784, xn_t1785))) {
        size_t xn_t1786 = xn_root_mark();
        #line 1020 "impl/lib/b2/xparser.x"
        rt_string *xn_t1787 = rt_string_from_c("ss");
xn_root_add(xn_t1787);
        xn_root_add(xn_t1787);
        xn_root_add(xn_t1787);
            {
        xn_root_restore(xn_t1786);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1787;

    }
#line 1021 "impl/lib/b2/xparser.x"
rt_string *xn_t1788 = rt_retain(k);
xn_root_add(xn_t1788);
rt_string *xn_t1789 = rt_string_from_c("SuffixedType.Base");
xn_root_add(xn_t1789);
    if ((xn_str_eq(xn_t1788, xn_t1789))) {
        size_t xn_t1790 = xn_root_mark();
        #line 1021 "impl/lib/b2/xparser.x"
        rt_string *xn_t1791 = rt_string_from_c("i");
xn_root_add(xn_t1791);
        xn_root_add(xn_t1791);
        xn_root_add(xn_t1791);
            {
        xn_root_restore(xn_t1790);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1791;

    }
#line 1022 "impl/lib/b2/xparser.x"
rt_string *xn_t1792 = rt_retain(k);
xn_root_add(xn_t1792);
rt_string *xn_t1793 = rt_string_from_c("SuffixedType.P");
xn_root_add(xn_t1793);
    if ((xn_str_eq(xn_t1792, xn_t1793))) {
        size_t xn_t1794 = xn_root_mark();
        #line 1022 "impl/lib/b2/xparser.x"
        rt_string *xn_t1795 = rt_string_from_c("v");
xn_root_add(xn_t1795);
        xn_root_add(xn_t1795);
        xn_root_add(xn_t1795);
            {
        xn_root_restore(xn_t1794);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1795;

    }
#line 1023 "impl/lib/b2/xparser.x"
rt_string *xn_t1796 = rt_retain(k);
xn_root_add(xn_t1796);
rt_string *xn_t1797 = rt_string_from_c("SuffixedType.Suffixes");
xn_root_add(xn_t1797);
    if ((xn_str_eq(xn_t1796, xn_t1797))) {
        size_t xn_t1798 = xn_root_mark();
        #line 1023 "impl/lib/b2/xparser.x"
        rt_string *xn_t1799 = rt_string_from_c("ss");
xn_root_add(xn_t1799);
        xn_root_add(xn_t1799);
        xn_root_add(xn_t1799);
            {
        xn_root_restore(xn_t1798);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1799;

    }
#line 1024 "impl/lib/b2/xparser.x"
rt_string *xn_t1800 = rt_retain(k);
xn_root_add(xn_t1800);
rt_string *xn_t1801 = rt_string_from_c("SwitchCase.Default");
xn_root_add(xn_t1801);
    if ((xn_str_eq(xn_t1800, xn_t1801))) {
        size_t xn_t1802 = xn_root_mark();
        #line 1024 "impl/lib/b2/xparser.x"
        rt_string *xn_t1803 = rt_string_from_c("s");
xn_root_add(xn_t1803);
        xn_root_add(xn_t1803);
        xn_root_add(xn_t1803);
            {
        xn_root_restore(xn_t1802);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1803;

    }
#line 1025 "impl/lib/b2/xparser.x"
rt_string *xn_t1804 = rt_retain(k);
xn_root_add(xn_t1804);
rt_string *xn_t1805 = rt_string_from_c("SwitchCase.Expr");
xn_root_add(xn_t1805);
    if ((xn_str_eq(xn_t1804, xn_t1805))) {
        size_t xn_t1806 = xn_root_mark();
        #line 1025 "impl/lib/b2/xparser.x"
        rt_string *xn_t1807 = rt_string_from_c("i");
xn_root_add(xn_t1807);
        xn_root_add(xn_t1807);
        xn_root_add(xn_t1807);
            {
        xn_root_restore(xn_t1806);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1807;

    }
#line 1026 "impl/lib/b2/xparser.x"
rt_string *xn_t1808 = rt_retain(k);
xn_root_add(xn_t1808);
rt_string *xn_t1809 = rt_string_from_c("SwitchCase.P");
xn_root_add(xn_t1809);
    if ((xn_str_eq(xn_t1808, xn_t1809))) {
        size_t xn_t1810 = xn_root_mark();
        #line 1026 "impl/lib/b2/xparser.x"
        rt_string *xn_t1811 = rt_string_from_c("v");
xn_root_add(xn_t1811);
        xn_root_add(xn_t1811);
        xn_root_add(xn_t1811);
            {
        xn_root_restore(xn_t1810);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1811;

    }
#line 1027 "impl/lib/b2/xparser.x"
rt_string *xn_t1812 = rt_retain(k);
xn_root_add(xn_t1812);
rt_string *xn_t1813 = rt_string_from_c("SwitchCase.Stmts");
xn_root_add(xn_t1813);
    if ((xn_str_eq(xn_t1812, xn_t1813))) {
        size_t xn_t1814 = xn_root_mark();
        #line 1027 "impl/lib/b2/xparser.x"
        rt_string *xn_t1815 = rt_string_from_c("si");
xn_root_add(xn_t1815);
        xn_root_add(xn_t1815);
        xn_root_add(xn_t1815);
            {
        xn_root_restore(xn_t1814);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1815;

    }
#line 1028 "impl/lib/b2/xparser.x"
rt_string *xn_t1816 = rt_retain(k);
xn_root_add(xn_t1816);
rt_string *xn_t1817 = rt_string_from_c("SwitchStmt.Cases");
xn_root_add(xn_t1817);
    if ((xn_str_eq(xn_t1816, xn_t1817))) {
        size_t xn_t1818 = xn_root_mark();
        #line 1028 "impl/lib/b2/xparser.x"
        rt_string *xn_t1819 = rt_string_from_c("sp");
xn_root_add(xn_t1819);
        xn_root_add(xn_t1819);
        xn_root_add(xn_t1819);
            {
        xn_root_restore(xn_t1818);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1819;

    }
#line 1029 "impl/lib/b2/xparser.x"
rt_string *xn_t1820 = rt_retain(k);
xn_root_add(xn_t1820);
rt_string *xn_t1821 = rt_string_from_c("SwitchStmt.Default");
xn_root_add(xn_t1821);
    if ((xn_str_eq(xn_t1820, xn_t1821))) {
        size_t xn_t1822 = xn_root_mark();
        #line 1029 "impl/lib/b2/xparser.x"
        rt_string *xn_t1823 = rt_string_from_c("p");
xn_root_add(xn_t1823);
        xn_root_add(xn_t1823);
        xn_root_add(xn_t1823);
            {
        xn_root_restore(xn_t1822);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1823;

    }
#line 1030 "impl/lib/b2/xparser.x"
rt_string *xn_t1824 = rt_retain(k);
xn_root_add(xn_t1824);
rt_string *xn_t1825 = rt_string_from_c("SwitchStmt.P");
xn_root_add(xn_t1825);
    if ((xn_str_eq(xn_t1824, xn_t1825))) {
        size_t xn_t1826 = xn_root_mark();
        #line 1030 "impl/lib/b2/xparser.x"
        rt_string *xn_t1827 = rt_string_from_c("v");
xn_root_add(xn_t1827);
        xn_root_add(xn_t1827);
        xn_root_add(xn_t1827);
            {
        xn_root_restore(xn_t1826);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1827;

    }
#line 1031 "impl/lib/b2/xparser.x"
rt_string *xn_t1828 = rt_retain(k);
xn_root_add(xn_t1828);
rt_string *xn_t1829 = rt_string_from_c("SwitchStmt.Value");
xn_root_add(xn_t1829);
    if ((xn_str_eq(xn_t1828, xn_t1829))) {
        size_t xn_t1830 = xn_root_mark();
        #line 1031 "impl/lib/b2/xparser.x"
        rt_string *xn_t1831 = rt_string_from_c("i");
xn_root_add(xn_t1831);
        xn_root_add(xn_t1831);
        xn_root_add(xn_t1831);
            {
        xn_root_restore(xn_t1830);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1831;

    }
#line 1032 "impl/lib/b2/xparser.x"
rt_string *xn_t1832 = rt_retain(k);
xn_root_add(xn_t1832);
rt_string *xn_t1833 = rt_string_from_c("Ternary.Cond");
xn_root_add(xn_t1833);
    if ((xn_str_eq(xn_t1832, xn_t1833))) {
        size_t xn_t1834 = xn_root_mark();
        #line 1032 "impl/lib/b2/xparser.x"
        rt_string *xn_t1835 = rt_string_from_c("i");
xn_root_add(xn_t1835);
        xn_root_add(xn_t1835);
        xn_root_add(xn_t1835);
            {
        xn_root_restore(xn_t1834);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1835;

    }
#line 1033 "impl/lib/b2/xparser.x"
rt_string *xn_t1836 = rt_retain(k);
xn_root_add(xn_t1836);
rt_string *xn_t1837 = rt_string_from_c("Ternary.Else");
xn_root_add(xn_t1837);
    if ((xn_str_eq(xn_t1836, xn_t1837))) {
        size_t xn_t1838 = xn_root_mark();
        #line 1033 "impl/lib/b2/xparser.x"
        rt_string *xn_t1839 = rt_string_from_c("i");
xn_root_add(xn_t1839);
        xn_root_add(xn_t1839);
        xn_root_add(xn_t1839);
            {
        xn_root_restore(xn_t1838);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1839;

    }
#line 1034 "impl/lib/b2/xparser.x"
rt_string *xn_t1840 = rt_retain(k);
xn_root_add(xn_t1840);
rt_string *xn_t1841 = rt_string_from_c("Ternary.P");
xn_root_add(xn_t1841);
    if ((xn_str_eq(xn_t1840, xn_t1841))) {
        size_t xn_t1842 = xn_root_mark();
        #line 1034 "impl/lib/b2/xparser.x"
        rt_string *xn_t1843 = rt_string_from_c("v");
xn_root_add(xn_t1843);
        xn_root_add(xn_t1843);
        xn_root_add(xn_t1843);
            {
        xn_root_restore(xn_t1842);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1843;

    }
#line 1035 "impl/lib/b2/xparser.x"
rt_string *xn_t1844 = rt_retain(k);
xn_root_add(xn_t1844);
rt_string *xn_t1845 = rt_string_from_c("Ternary.Then");
xn_root_add(xn_t1845);
    if ((xn_str_eq(xn_t1844, xn_t1845))) {
        size_t xn_t1846 = xn_root_mark();
        #line 1035 "impl/lib/b2/xparser.x"
        rt_string *xn_t1847 = rt_string_from_c("i");
xn_root_add(xn_t1847);
        xn_root_add(xn_t1847);
        xn_root_add(xn_t1847);
            {
        xn_root_restore(xn_t1846);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1847;

    }
#line 1036 "impl/lib/b2/xparser.x"
rt_string *xn_t1848 = rt_retain(k);
xn_root_add(xn_t1848);
rt_string *xn_t1849 = rt_string_from_c("ThrowStmt.P");
xn_root_add(xn_t1849);
    if ((xn_str_eq(xn_t1848, xn_t1849))) {
        size_t xn_t1850 = xn_root_mark();
        #line 1036 "impl/lib/b2/xparser.x"
        rt_string *xn_t1851 = rt_string_from_c("v");
xn_root_add(xn_t1851);
        xn_root_add(xn_t1851);
        xn_root_add(xn_t1851);
            {
        xn_root_restore(xn_t1850);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1851;

    }
#line 1037 "impl/lib/b2/xparser.x"
rt_string *xn_t1852 = rt_retain(k);
xn_root_add(xn_t1852);
rt_string *xn_t1853 = rt_string_from_c("ThrowStmt.Value");
xn_root_add(xn_t1853);
    if ((xn_str_eq(xn_t1852, xn_t1853))) {
        size_t xn_t1854 = xn_root_mark();
        #line 1037 "impl/lib/b2/xparser.x"
        rt_string *xn_t1855 = rt_string_from_c("i");
xn_root_add(xn_t1855);
        xn_root_add(xn_t1855);
        xn_root_add(xn_t1855);
            {
        xn_root_restore(xn_t1854);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1855;

    }
#line 1038 "impl/lib/b2/xparser.x"
rt_string *xn_t1856 = rt_retain(k);
xn_root_add(xn_t1856);
rt_string *xn_t1857 = rt_string_from_c("Token.Base");
xn_root_add(xn_t1857);
    if ((xn_str_eq(xn_t1856, xn_t1857))) {
        size_t xn_t1858 = xn_root_mark();
        #line 1038 "impl/lib/b2/xparser.x"
        rt_string *xn_t1859 = rt_string_from_c("s");
xn_root_add(xn_t1859);
        xn_root_add(xn_t1859);
        xn_root_add(xn_t1859);
            {
        xn_root_restore(xn_t1858);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1859;

    }
#line 1039 "impl/lib/b2/xparser.x"
rt_string *xn_t1860 = rt_retain(k);
xn_root_add(xn_t1860);
rt_string *xn_t1861 = rt_string_from_c("Token.Char");
xn_root_add(xn_t1861);
    if ((xn_str_eq(xn_t1860, xn_t1861))) {
        size_t xn_t1862 = xn_root_mark();
        #line 1039 "impl/lib/b2/xparser.x"
        rt_string *xn_t1863 = rt_string_from_c("s");
xn_root_add(xn_t1863);
        xn_root_add(xn_t1863);
        xn_root_add(xn_t1863);
            {
        xn_root_restore(xn_t1862);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1863;

    }
#line 1040 "impl/lib/b2/xparser.x"
rt_string *xn_t1864 = rt_retain(k);
xn_root_add(xn_t1864);
rt_string *xn_t1865 = rt_string_from_c("Token.HasSuffixF");
xn_root_add(xn_t1865);
    if ((xn_str_eq(xn_t1864, xn_t1865))) {
        size_t xn_t1866 = xn_root_mark();
        #line 1040 "impl/lib/b2/xparser.x"
        rt_string *xn_t1867 = rt_string_from_c("s");
xn_root_add(xn_t1867);
        xn_root_add(xn_t1867);
        xn_root_add(xn_t1867);
            {
        xn_root_restore(xn_t1866);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1867;

    }
#line 1041 "impl/lib/b2/xparser.x"
rt_string *xn_t1868 = rt_retain(k);
xn_root_add(xn_t1868);
rt_string *xn_t1869 = rt_string_from_c("Token.Interps");
xn_root_add(xn_t1869);
    if ((xn_str_eq(xn_t1868, xn_t1869))) {
        size_t xn_t1870 = xn_root_mark();
        #line 1041 "impl/lib/b2/xparser.x"
        rt_string *xn_t1871 = rt_string_from_c("ss");
xn_root_add(xn_t1871);
        xn_root_add(xn_t1871);
        xn_root_add(xn_t1871);
            {
        xn_root_restore(xn_t1870);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1871;

    }
#line 1042 "impl/lib/b2/xparser.x"
rt_string *xn_t1872 = rt_retain(k);
xn_root_add(xn_t1872);
rt_string *xn_t1873 = rt_string_from_c("Token.Kind");
xn_root_add(xn_t1873);
    if ((xn_str_eq(xn_t1872, xn_t1873))) {
        size_t xn_t1874 = xn_root_mark();
        #line 1042 "impl/lib/b2/xparser.x"
        rt_string *xn_t1875 = rt_string_from_c("v");
xn_root_add(xn_t1875);
        xn_root_add(xn_t1875);
        xn_root_add(xn_t1875);
            {
        xn_root_restore(xn_t1874);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1875;

    }
#line 1043 "impl/lib/b2/xparser.x"
rt_string *xn_t1876 = rt_retain(k);
xn_root_add(xn_t1876);
rt_string *xn_t1877 = rt_string_from_c("Token.Pos");
xn_root_add(xn_t1877);
    if ((xn_str_eq(xn_t1876, xn_t1877))) {
        size_t xn_t1878 = xn_root_mark();
        #line 1043 "impl/lib/b2/xparser.x"
        rt_string *xn_t1879 = rt_string_from_c("v");
xn_root_add(xn_t1879);
        xn_root_add(xn_t1879);
        xn_root_add(xn_t1879);
            {
        xn_root_restore(xn_t1878);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1879;

    }
#line 1044 "impl/lib/b2/xparser.x"
rt_string *xn_t1880 = rt_retain(k);
xn_root_add(xn_t1880);
rt_string *xn_t1881 = rt_string_from_c("Token.Segs");
xn_root_add(xn_t1881);
    if ((xn_str_eq(xn_t1880, xn_t1881))) {
        size_t xn_t1882 = xn_root_mark();
        #line 1044 "impl/lib/b2/xparser.x"
        rt_string *xn_t1883 = rt_string_from_c("ss");
xn_root_add(xn_t1883);
        xn_root_add(xn_t1883);
        xn_root_add(xn_t1883);
            {
        xn_root_restore(xn_t1882);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1883;

    }
#line 1045 "impl/lib/b2/xparser.x"
rt_string *xn_t1884 = rt_retain(k);
xn_root_add(xn_t1884);
rt_string *xn_t1885 = rt_string_from_c("Token.Str");
xn_root_add(xn_t1885);
    if ((xn_str_eq(xn_t1884, xn_t1885))) {
        size_t xn_t1886 = xn_root_mark();
        #line 1045 "impl/lib/b2/xparser.x"
        rt_string *xn_t1887 = rt_string_from_c("s");
xn_root_add(xn_t1887);
        xn_root_add(xn_t1887);
        xn_root_add(xn_t1887);
            {
        xn_root_restore(xn_t1886);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1887;

    }
#line 1046 "impl/lib/b2/xparser.x"
rt_string *xn_t1888 = rt_retain(k);
xn_root_add(xn_t1888);
rt_string *xn_t1889 = rt_string_from_c("Token.Suffix");
xn_root_add(xn_t1889);
    if ((xn_str_eq(xn_t1888, xn_t1889))) {
        size_t xn_t1890 = xn_root_mark();
        #line 1046 "impl/lib/b2/xparser.x"
        rt_string *xn_t1891 = rt_string_from_c("s");
xn_root_add(xn_t1891);
        xn_root_add(xn_t1891);
        xn_root_add(xn_t1891);
            {
        xn_root_restore(xn_t1890);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1891;

    }
#line 1047 "impl/lib/b2/xparser.x"
rt_string *xn_t1892 = rt_retain(k);
xn_root_add(xn_t1892);
rt_string *xn_t1893 = rt_string_from_c("Token.Text");
xn_root_add(xn_t1893);
    if ((xn_str_eq(xn_t1892, xn_t1893))) {
        size_t xn_t1894 = xn_root_mark();
        #line 1047 "impl/lib/b2/xparser.x"
        rt_string *xn_t1895 = rt_string_from_c("s");
xn_root_add(xn_t1895);
        xn_root_add(xn_t1895);
        xn_root_add(xn_t1895);
            {
        xn_root_restore(xn_t1894);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1895;

    }
#line 1048 "impl/lib/b2/xparser.x"
rt_string *xn_t1896 = rt_retain(k);
xn_root_add(xn_t1896);
rt_string *xn_t1897 = rt_string_from_c("Token.Value");
xn_root_add(xn_t1897);
    if ((xn_str_eq(xn_t1896, xn_t1897))) {
        size_t xn_t1898 = xn_root_mark();
        #line 1048 "impl/lib/b2/xparser.x"
        rt_string *xn_t1899 = rt_string_from_c("s");
xn_root_add(xn_t1899);
        xn_root_add(xn_t1899);
        xn_root_add(xn_t1899);
            {
        xn_root_restore(xn_t1898);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1899;

    }
#line 1049 "impl/lib/b2/xparser.x"
rt_string *xn_t1900 = rt_retain(k);
xn_root_add(xn_t1900);
rt_string *xn_t1901 = rt_string_from_c("TopField.Annos");
xn_root_add(xn_t1901);
    if ((xn_str_eq(xn_t1900, xn_t1901))) {
        size_t xn_t1902 = xn_root_mark();
        #line 1049 "impl/lib/b2/xparser.x"
        rt_string *xn_t1903 = rt_string_from_c("sp");
xn_root_add(xn_t1903);
        xn_root_add(xn_t1903);
        xn_root_add(xn_t1903);
            {
        xn_root_restore(xn_t1902);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1903;

    }
#line 1050 "impl/lib/b2/xparser.x"
rt_string *xn_t1904 = rt_retain(k);
xn_root_add(xn_t1904);
rt_string *xn_t1905 = rt_string_from_c("TopField.Const");
xn_root_add(xn_t1905);
    if ((xn_str_eq(xn_t1904, xn_t1905))) {
        size_t xn_t1906 = xn_root_mark();
        #line 1050 "impl/lib/b2/xparser.x"
        rt_string *xn_t1907 = rt_string_from_c("s");
xn_root_add(xn_t1907);
        xn_root_add(xn_t1907);
        xn_root_add(xn_t1907);
            {
        xn_root_restore(xn_t1906);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1907;

    }
#line 1051 "impl/lib/b2/xparser.x"
rt_string *xn_t1908 = rt_retain(k);
xn_root_add(xn_t1908);
rt_string *xn_t1909 = rt_string_from_c("TopField.Final");
xn_root_add(xn_t1909);
    if ((xn_str_eq(xn_t1908, xn_t1909))) {
        size_t xn_t1910 = xn_root_mark();
        #line 1051 "impl/lib/b2/xparser.x"
        rt_string *xn_t1911 = rt_string_from_c("s");
xn_root_add(xn_t1911);
        xn_root_add(xn_t1911);
        xn_root_add(xn_t1911);
            {
        xn_root_restore(xn_t1910);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1911;

    }
#line 1052 "impl/lib/b2/xparser.x"
rt_string *xn_t1912 = rt_retain(k);
xn_root_add(xn_t1912);
rt_string *xn_t1913 = rt_string_from_c("TopField.Init");
xn_root_add(xn_t1913);
    if ((xn_str_eq(xn_t1912, xn_t1913))) {
        size_t xn_t1914 = xn_root_mark();
        #line 1052 "impl/lib/b2/xparser.x"
        rt_string *xn_t1915 = rt_string_from_c("i");
xn_root_add(xn_t1915);
        xn_root_add(xn_t1915);
        xn_root_add(xn_t1915);
            {
        xn_root_restore(xn_t1914);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1915;

    }
#line 1053 "impl/lib/b2/xparser.x"
rt_string *xn_t1916 = rt_retain(k);
xn_root_add(xn_t1916);
rt_string *xn_t1917 = rt_string_from_c("TopField.Name");
xn_root_add(xn_t1917);
    if ((xn_str_eq(xn_t1916, xn_t1917))) {
        size_t xn_t1918 = xn_root_mark();
        #line 1053 "impl/lib/b2/xparser.x"
        rt_string *xn_t1919 = rt_string_from_c("s");
xn_root_add(xn_t1919);
        xn_root_add(xn_t1919);
        xn_root_add(xn_t1919);
            {
        xn_root_restore(xn_t1918);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1919;

    }
#line 1054 "impl/lib/b2/xparser.x"
rt_string *xn_t1920 = rt_retain(k);
xn_root_add(xn_t1920);
rt_string *xn_t1921 = rt_string_from_c("TopField.P");
xn_root_add(xn_t1921);
    if ((xn_str_eq(xn_t1920, xn_t1921))) {
        size_t xn_t1922 = xn_root_mark();
        #line 1054 "impl/lib/b2/xparser.x"
        rt_string *xn_t1923 = rt_string_from_c("v");
xn_root_add(xn_t1923);
        xn_root_add(xn_t1923);
        xn_root_add(xn_t1923);
            {
        xn_root_restore(xn_t1922);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1923;

    }
#line 1055 "impl/lib/b2/xparser.x"
rt_string *xn_t1924 = rt_retain(k);
xn_root_add(xn_t1924);
rt_string *xn_t1925 = rt_string_from_c("TopField.Private");
xn_root_add(xn_t1925);
    if ((xn_str_eq(xn_t1924, xn_t1925))) {
        size_t xn_t1926 = xn_root_mark();
        #line 1055 "impl/lib/b2/xparser.x"
        rt_string *xn_t1927 = rt_string_from_c("s");
xn_root_add(xn_t1927);
        xn_root_add(xn_t1927);
        xn_root_add(xn_t1927);
            {
        xn_root_restore(xn_t1926);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1927;

    }
#line 1056 "impl/lib/b2/xparser.x"
rt_string *xn_t1928 = rt_retain(k);
xn_root_add(xn_t1928);
rt_string *xn_t1929 = rt_string_from_c("TopField.Protected");
xn_root_add(xn_t1929);
    if ((xn_str_eq(xn_t1928, xn_t1929))) {
        size_t xn_t1930 = xn_root_mark();
        #line 1056 "impl/lib/b2/xparser.x"
        rt_string *xn_t1931 = rt_string_from_c("s");
xn_root_add(xn_t1931);
        xn_root_add(xn_t1931);
        xn_root_add(xn_t1931);
            {
        xn_root_restore(xn_t1930);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1931;

    }
#line 1057 "impl/lib/b2/xparser.x"
rt_string *xn_t1932 = rt_retain(k);
xn_root_add(xn_t1932);
rt_string *xn_t1933 = rt_string_from_c("TopField.Public");
xn_root_add(xn_t1933);
    if ((xn_str_eq(xn_t1932, xn_t1933))) {
        size_t xn_t1934 = xn_root_mark();
        #line 1057 "impl/lib/b2/xparser.x"
        rt_string *xn_t1935 = rt_string_from_c("s");
xn_root_add(xn_t1935);
        xn_root_add(xn_t1935);
        xn_root_add(xn_t1935);
            {
        xn_root_restore(xn_t1934);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1935;

    }
#line 1058 "impl/lib/b2/xparser.x"
rt_string *xn_t1936 = rt_retain(k);
xn_root_add(xn_t1936);
rt_string *xn_t1937 = rt_string_from_c("TopField.Static");
xn_root_add(xn_t1937);
    if ((xn_str_eq(xn_t1936, xn_t1937))) {
        size_t xn_t1938 = xn_root_mark();
        #line 1058 "impl/lib/b2/xparser.x"
        rt_string *xn_t1939 = rt_string_from_c("s");
xn_root_add(xn_t1939);
        xn_root_add(xn_t1939);
        xn_root_add(xn_t1939);
            {
        xn_root_restore(xn_t1938);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1939;

    }
#line 1059 "impl/lib/b2/xparser.x"
rt_string *xn_t1940 = rt_retain(k);
xn_root_add(xn_t1940);
rt_string *xn_t1941 = rt_string_from_c("TopField.Type");
xn_root_add(xn_t1941);
    if ((xn_str_eq(xn_t1940, xn_t1941))) {
        size_t xn_t1942 = xn_root_mark();
        #line 1059 "impl/lib/b2/xparser.x"
        rt_string *xn_t1943 = rt_string_from_c("i");
xn_root_add(xn_t1943);
        xn_root_add(xn_t1943);
        xn_root_add(xn_t1943);
            {
        xn_root_restore(xn_t1942);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1943;

    }
#line 1060 "impl/lib/b2/xparser.x"
rt_string *xn_t1944 = rt_retain(k);
xn_root_add(xn_t1944);
rt_string *xn_t1945 = rt_string_from_c("TopFunc.Annos");
xn_root_add(xn_t1945);
    if ((xn_str_eq(xn_t1944, xn_t1945))) {
        size_t xn_t1946 = xn_root_mark();
        #line 1060 "impl/lib/b2/xparser.x"
        rt_string *xn_t1947 = rt_string_from_c("sp");
xn_root_add(xn_t1947);
        xn_root_add(xn_t1947);
        xn_root_add(xn_t1947);
            {
        xn_root_restore(xn_t1946);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1947;

    }
#line 1061 "impl/lib/b2/xparser.x"
rt_string *xn_t1948 = rt_retain(k);
xn_root_add(xn_t1948);
rt_string *xn_t1949 = rt_string_from_c("TopFunc.Body");
xn_root_add(xn_t1949);
    if ((xn_str_eq(xn_t1948, xn_t1949))) {
        size_t xn_t1950 = xn_root_mark();
        #line 1061 "impl/lib/b2/xparser.x"
        rt_string *xn_t1951 = rt_string_from_c("p");
xn_root_add(xn_t1951);
        xn_root_add(xn_t1951);
        xn_root_add(xn_t1951);
            {
        xn_root_restore(xn_t1950);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1951;

    }
#line 1062 "impl/lib/b2/xparser.x"
rt_string *xn_t1952 = rt_retain(k);
xn_root_add(xn_t1952);
rt_string *xn_t1953 = rt_string_from_c("TopFunc.Name");
xn_root_add(xn_t1953);
    if ((xn_str_eq(xn_t1952, xn_t1953))) {
        size_t xn_t1954 = xn_root_mark();
        #line 1062 "impl/lib/b2/xparser.x"
        rt_string *xn_t1955 = rt_string_from_c("s");
xn_root_add(xn_t1955);
        xn_root_add(xn_t1955);
        xn_root_add(xn_t1955);
            {
        xn_root_restore(xn_t1954);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1955;

    }
#line 1063 "impl/lib/b2/xparser.x"
rt_string *xn_t1956 = rt_retain(k);
xn_root_add(xn_t1956);
rt_string *xn_t1957 = rt_string_from_c("TopFunc.P");
xn_root_add(xn_t1957);
    if ((xn_str_eq(xn_t1956, xn_t1957))) {
        size_t xn_t1958 = xn_root_mark();
        #line 1063 "impl/lib/b2/xparser.x"
        rt_string *xn_t1959 = rt_string_from_c("v");
xn_root_add(xn_t1959);
        xn_root_add(xn_t1959);
        xn_root_add(xn_t1959);
            {
        xn_root_restore(xn_t1958);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1959;

    }
#line 1064 "impl/lib/b2/xparser.x"
rt_string *xn_t1960 = rt_retain(k);
xn_root_add(xn_t1960);
rt_string *xn_t1961 = rt_string_from_c("TopFunc.Params");
xn_root_add(xn_t1961);
    if ((xn_str_eq(xn_t1960, xn_t1961))) {
        size_t xn_t1962 = xn_root_mark();
        #line 1064 "impl/lib/b2/xparser.x"
        rt_string *xn_t1963 = rt_string_from_c("sp");
xn_root_add(xn_t1963);
        xn_root_add(xn_t1963);
        xn_root_add(xn_t1963);
            {
        xn_root_restore(xn_t1962);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1963;

    }
#line 1065 "impl/lib/b2/xparser.x"
rt_string *xn_t1964 = rt_retain(k);
xn_root_add(xn_t1964);
rt_string *xn_t1965 = rt_string_from_c("TopFunc.Private");
xn_root_add(xn_t1965);
    if ((xn_str_eq(xn_t1964, xn_t1965))) {
        size_t xn_t1966 = xn_root_mark();
        #line 1065 "impl/lib/b2/xparser.x"
        rt_string *xn_t1967 = rt_string_from_c("s");
xn_root_add(xn_t1967);
        xn_root_add(xn_t1967);
        xn_root_add(xn_t1967);
            {
        xn_root_restore(xn_t1966);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1967;

    }
#line 1066 "impl/lib/b2/xparser.x"
rt_string *xn_t1968 = rt_retain(k);
xn_root_add(xn_t1968);
rt_string *xn_t1969 = rt_string_from_c("TopFunc.Protected");
xn_root_add(xn_t1969);
    if ((xn_str_eq(xn_t1968, xn_t1969))) {
        size_t xn_t1970 = xn_root_mark();
        #line 1066 "impl/lib/b2/xparser.x"
        rt_string *xn_t1971 = rt_string_from_c("s");
xn_root_add(xn_t1971);
        xn_root_add(xn_t1971);
        xn_root_add(xn_t1971);
            {
        xn_root_restore(xn_t1970);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1971;

    }
#line 1067 "impl/lib/b2/xparser.x"
rt_string *xn_t1972 = rt_retain(k);
xn_root_add(xn_t1972);
rt_string *xn_t1973 = rt_string_from_c("TopFunc.Public");
xn_root_add(xn_t1973);
    if ((xn_str_eq(xn_t1972, xn_t1973))) {
        size_t xn_t1974 = xn_root_mark();
        #line 1067 "impl/lib/b2/xparser.x"
        rt_string *xn_t1975 = rt_string_from_c("s");
xn_root_add(xn_t1975);
        xn_root_add(xn_t1975);
        xn_root_add(xn_t1975);
            {
        xn_root_restore(xn_t1974);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1975;

    }
#line 1068 "impl/lib/b2/xparser.x"
rt_string *xn_t1976 = rt_retain(k);
xn_root_add(xn_t1976);
rt_string *xn_t1977 = rt_string_from_c("TopFunc.Ret");
xn_root_add(xn_t1977);
    if ((xn_str_eq(xn_t1976, xn_t1977))) {
        size_t xn_t1978 = xn_root_mark();
        #line 1068 "impl/lib/b2/xparser.x"
        rt_string *xn_t1979 = rt_string_from_c("i");
xn_root_add(xn_t1979);
        xn_root_add(xn_t1979);
        xn_root_add(xn_t1979);
            {
        xn_root_restore(xn_t1978);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1979;

    }
#line 1069 "impl/lib/b2/xparser.x"
rt_string *xn_t1980 = rt_retain(k);
xn_root_add(xn_t1980);
rt_string *xn_t1981 = rt_string_from_c("TopFunc.Static");
xn_root_add(xn_t1981);
    if ((xn_str_eq(xn_t1980, xn_t1981))) {
        size_t xn_t1982 = xn_root_mark();
        #line 1069 "impl/lib/b2/xparser.x"
        rt_string *xn_t1983 = rt_string_from_c("s");
xn_root_add(xn_t1983);
        xn_root_add(xn_t1983);
        xn_root_add(xn_t1983);
            {
        xn_root_restore(xn_t1982);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1983;

    }
#line 1070 "impl/lib/b2/xparser.x"
rt_string *xn_t1984 = rt_retain(k);
xn_root_add(xn_t1984);
rt_string *xn_t1985 = rt_string_from_c("TopFunc.TypePars");
xn_root_add(xn_t1985);
    if ((xn_str_eq(xn_t1984, xn_t1985))) {
        size_t xn_t1986 = xn_root_mark();
        #line 1070 "impl/lib/b2/xparser.x"
        rt_string *xn_t1987 = rt_string_from_c("ss");
xn_root_add(xn_t1987);
        xn_root_add(xn_t1987);
        xn_root_add(xn_t1987);
            {
        xn_root_restore(xn_t1986);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1987;

    }
#line 1071 "impl/lib/b2/xparser.x"
rt_string *xn_t1988 = rt_retain(k);
xn_root_add(xn_t1988);
rt_string *xn_t1989 = rt_string_from_c("TopFunc.Void");
xn_root_add(xn_t1989);
    if ((xn_str_eq(xn_t1988, xn_t1989))) {
        size_t xn_t1990 = xn_root_mark();
        #line 1071 "impl/lib/b2/xparser.x"
        rt_string *xn_t1991 = rt_string_from_c("s");
xn_root_add(xn_t1991);
        xn_root_add(xn_t1991);
        xn_root_add(xn_t1991);
            {
        xn_root_restore(xn_t1990);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1991;

    }
#line 1072 "impl/lib/b2/xparser.x"
rt_string *xn_t1992 = rt_retain(k);
xn_root_add(xn_t1992);
rt_string *xn_t1993 = rt_string_from_c("Tuple.Elems");
xn_root_add(xn_t1993);
    if ((xn_str_eq(xn_t1992, xn_t1993))) {
        size_t xn_t1994 = xn_root_mark();
        #line 1072 "impl/lib/b2/xparser.x"
        rt_string *xn_t1995 = rt_string_from_c("si");
xn_root_add(xn_t1995);
        xn_root_add(xn_t1995);
        xn_root_add(xn_t1995);
            {
        xn_root_restore(xn_t1994);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1995;

    }
#line 1073 "impl/lib/b2/xparser.x"
rt_string *xn_t1996 = rt_retain(k);
xn_root_add(xn_t1996);
rt_string *xn_t1997 = rt_string_from_c("Tuple.P");
xn_root_add(xn_t1997);
    if ((xn_str_eq(xn_t1996, xn_t1997))) {
        size_t xn_t1998 = xn_root_mark();
        #line 1073 "impl/lib/b2/xparser.x"
        rt_string *xn_t1999 = rt_string_from_c("v");
xn_root_add(xn_t1999);
        xn_root_add(xn_t1999);
        xn_root_add(xn_t1999);
            {
        xn_root_restore(xn_t1998);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t1999;

    }
#line 1074 "impl/lib/b2/xparser.x"
rt_string *xn_t2000 = rt_retain(k);
xn_root_add(xn_t2000);
rt_string *xn_t2001 = rt_string_from_c("TupleMember.Index");
xn_root_add(xn_t2001);
    if ((xn_str_eq(xn_t2000, xn_t2001))) {
        size_t xn_t2002 = xn_root_mark();
        #line 1074 "impl/lib/b2/xparser.x"
        rt_string *xn_t2003 = rt_string_from_c("s");
xn_root_add(xn_t2003);
        xn_root_add(xn_t2003);
        xn_root_add(xn_t2003);
            {
        xn_root_restore(xn_t2002);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2003;

    }
#line 1075 "impl/lib/b2/xparser.x"
rt_string *xn_t2004 = rt_retain(k);
xn_root_add(xn_t2004);
rt_string *xn_t2005 = rt_string_from_c("TupleMember.NullSafe");
xn_root_add(xn_t2005);
    if ((xn_str_eq(xn_t2004, xn_t2005))) {
        size_t xn_t2006 = xn_root_mark();
        #line 1075 "impl/lib/b2/xparser.x"
        rt_string *xn_t2007 = rt_string_from_c("s");
xn_root_add(xn_t2007);
        xn_root_add(xn_t2007);
        xn_root_add(xn_t2007);
            {
        xn_root_restore(xn_t2006);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2007;

    }
#line 1076 "impl/lib/b2/xparser.x"
rt_string *xn_t2008 = rt_retain(k);
xn_root_add(xn_t2008);
rt_string *xn_t2009 = rt_string_from_c("TupleMember.P");
xn_root_add(xn_t2009);
    if ((xn_str_eq(xn_t2008, xn_t2009))) {
        size_t xn_t2010 = xn_root_mark();
        #line 1076 "impl/lib/b2/xparser.x"
        rt_string *xn_t2011 = rt_string_from_c("v");
xn_root_add(xn_t2011);
        xn_root_add(xn_t2011);
        xn_root_add(xn_t2011);
            {
        xn_root_restore(xn_t2010);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2011;

    }
#line 1077 "impl/lib/b2/xparser.x"
rt_string *xn_t2012 = rt_retain(k);
xn_root_add(xn_t2012);
rt_string *xn_t2013 = rt_string_from_c("TupleMember.X");
xn_root_add(xn_t2013);
    if ((xn_str_eq(xn_t2012, xn_t2013))) {
        size_t xn_t2014 = xn_root_mark();
        #line 1077 "impl/lib/b2/xparser.x"
        rt_string *xn_t2015 = rt_string_from_c("i");
xn_root_add(xn_t2015);
        xn_root_add(xn_t2015);
        xn_root_add(xn_t2015);
            {
        xn_root_restore(xn_t2014);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2015;

    }
#line 1078 "impl/lib/b2/xparser.x"
rt_string *xn_t2016 = rt_retain(k);
xn_root_add(xn_t2016);
rt_string *xn_t2017 = rt_string_from_c("TupleTypeRef.Elems");
xn_root_add(xn_t2017);
    if ((xn_str_eq(xn_t2016, xn_t2017))) {
        size_t xn_t2018 = xn_root_mark();
        #line 1078 "impl/lib/b2/xparser.x"
        rt_string *xn_t2019 = rt_string_from_c("si");
xn_root_add(xn_t2019);
        xn_root_add(xn_t2019);
        xn_root_add(xn_t2019);
            {
        xn_root_restore(xn_t2018);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2019;

    }
#line 1079 "impl/lib/b2/xparser.x"
rt_string *xn_t2020 = rt_retain(k);
xn_root_add(xn_t2020);
rt_string *xn_t2021 = rt_string_from_c("TupleTypeRef.P");
xn_root_add(xn_t2021);
    if ((xn_str_eq(xn_t2020, xn_t2021))) {
        size_t xn_t2022 = xn_root_mark();
        #line 1079 "impl/lib/b2/xparser.x"
        rt_string *xn_t2023 = rt_string_from_c("v");
xn_root_add(xn_t2023);
        xn_root_add(xn_t2023);
        xn_root_add(xn_t2023);
            {
        xn_root_restore(xn_t2022);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2023;

    }
#line 1080 "impl/lib/b2/xparser.x"
rt_string *xn_t2024 = rt_retain(k);
xn_root_add(xn_t2024);
rt_string *xn_t2025 = rt_string_from_c("TypeModifiers.Abstract");
xn_root_add(xn_t2025);
    if ((xn_str_eq(xn_t2024, xn_t2025))) {
        size_t xn_t2026 = xn_root_mark();
        #line 1080 "impl/lib/b2/xparser.x"
        rt_string *xn_t2027 = rt_string_from_c("s");
xn_root_add(xn_t2027);
        xn_root_add(xn_t2027);
        xn_root_add(xn_t2027);
            {
        xn_root_restore(xn_t2026);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2027;

    }
#line 1081 "impl/lib/b2/xparser.x"
rt_string *xn_t2028 = rt_retain(k);
xn_root_add(xn_t2028);
rt_string *xn_t2029 = rt_string_from_c("TypeModifiers.Const");
xn_root_add(xn_t2029);
    if ((xn_str_eq(xn_t2028, xn_t2029))) {
        size_t xn_t2030 = xn_root_mark();
        #line 1081 "impl/lib/b2/xparser.x"
        rt_string *xn_t2031 = rt_string_from_c("s");
xn_root_add(xn_t2031);
        xn_root_add(xn_t2031);
        xn_root_add(xn_t2031);
            {
        xn_root_restore(xn_t2030);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2031;

    }
#line 1082 "impl/lib/b2/xparser.x"
rt_string *xn_t2032 = rt_retain(k);
xn_root_add(xn_t2032);
rt_string *xn_t2033 = rt_string_from_c("TypeModifiers.Final");
xn_root_add(xn_t2033);
    if ((xn_str_eq(xn_t2032, xn_t2033))) {
        size_t xn_t2034 = xn_root_mark();
        #line 1082 "impl/lib/b2/xparser.x"
        rt_string *xn_t2035 = rt_string_from_c("s");
xn_root_add(xn_t2035);
        xn_root_add(xn_t2035);
        xn_root_add(xn_t2035);
            {
        xn_root_restore(xn_t2034);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2035;

    }
#line 1083 "impl/lib/b2/xparser.x"
rt_string *xn_t2036 = rt_retain(k);
xn_root_add(xn_t2036);
rt_string *xn_t2037 = rt_string_from_c("TypeModifiers.Static");
xn_root_add(xn_t2037);
    if ((xn_str_eq(xn_t2036, xn_t2037))) {
        size_t xn_t2038 = xn_root_mark();
        #line 1083 "impl/lib/b2/xparser.x"
        rt_string *xn_t2039 = rt_string_from_c("s");
xn_root_add(xn_t2039);
        xn_root_add(xn_t2039);
        xn_root_add(xn_t2039);
            {
        xn_root_restore(xn_t2038);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2039;

    }
#line 1084 "impl/lib/b2/xparser.x"
rt_string *xn_t2040 = rt_retain(k);
xn_root_add(xn_t2040);
rt_string *xn_t2041 = rt_string_from_c("TypeModifiers.Vis");
xn_root_add(xn_t2041);
    if ((xn_str_eq(xn_t2040, xn_t2041))) {
        size_t xn_t2042 = xn_root_mark();
        #line 1084 "impl/lib/b2/xparser.x"
        rt_string *xn_t2043 = rt_string_from_c("s");
xn_root_add(xn_t2043);
        xn_root_add(xn_t2043);
        xn_root_add(xn_t2043);
            {
        xn_root_restore(xn_t2042);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2043;

    }
#line 1085 "impl/lib/b2/xparser.x"
rt_string *xn_t2044 = rt_retain(k);
xn_root_add(xn_t2044);
rt_string *xn_t2045 = rt_string_from_c("Unary.Op");
xn_root_add(xn_t2045);
    if ((xn_str_eq(xn_t2044, xn_t2045))) {
        size_t xn_t2046 = xn_root_mark();
        #line 1085 "impl/lib/b2/xparser.x"
        rt_string *xn_t2047 = rt_string_from_c("s");
xn_root_add(xn_t2047);
        xn_root_add(xn_t2047);
        xn_root_add(xn_t2047);
            {
        xn_root_restore(xn_t2046);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2047;

    }
#line 1086 "impl/lib/b2/xparser.x"
rt_string *xn_t2048 = rt_retain(k);
xn_root_add(xn_t2048);
rt_string *xn_t2049 = rt_string_from_c("Unary.P");
xn_root_add(xn_t2049);
    if ((xn_str_eq(xn_t2048, xn_t2049))) {
        size_t xn_t2050 = xn_root_mark();
        #line 1086 "impl/lib/b2/xparser.x"
        rt_string *xn_t2051 = rt_string_from_c("v");
xn_root_add(xn_t2051);
        xn_root_add(xn_t2051);
        xn_root_add(xn_t2051);
            {
        xn_root_restore(xn_t2050);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2051;

    }
#line 1087 "impl/lib/b2/xparser.x"
rt_string *xn_t2052 = rt_retain(k);
xn_root_add(xn_t2052);
rt_string *xn_t2053 = rt_string_from_c("Unary.X");
xn_root_add(xn_t2053);
    if ((xn_str_eq(xn_t2052, xn_t2053))) {
        size_t xn_t2054 = xn_root_mark();
        #line 1087 "impl/lib/b2/xparser.x"
        rt_string *xn_t2055 = rt_string_from_c("i");
xn_root_add(xn_t2055);
        xn_root_add(xn_t2055);
        xn_root_add(xn_t2055);
            {
        xn_root_restore(xn_t2054);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2055;

    }
#line 1088 "impl/lib/b2/xparser.x"
rt_string *xn_t2056 = rt_retain(k);
xn_root_add(xn_t2056);
rt_string *xn_t2057 = rt_string_from_c("WhileStmt.Body");
xn_root_add(xn_t2057);
    if ((xn_str_eq(xn_t2056, xn_t2057))) {
        size_t xn_t2058 = xn_root_mark();
        #line 1088 "impl/lib/b2/xparser.x"
        rt_string *xn_t2059 = rt_string_from_c("p");
xn_root_add(xn_t2059);
        xn_root_add(xn_t2059);
        xn_root_add(xn_t2059);
            {
        xn_root_restore(xn_t2058);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2059;

    }
#line 1089 "impl/lib/b2/xparser.x"
rt_string *xn_t2060 = rt_retain(k);
xn_root_add(xn_t2060);
rt_string *xn_t2061 = rt_string_from_c("WhileStmt.Cond");
xn_root_add(xn_t2061);
    if ((xn_str_eq(xn_t2060, xn_t2061))) {
        size_t xn_t2062 = xn_root_mark();
        #line 1089 "impl/lib/b2/xparser.x"
        rt_string *xn_t2063 = rt_string_from_c("i");
xn_root_add(xn_t2063);
        xn_root_add(xn_t2063);
        xn_root_add(xn_t2063);
            {
        xn_root_restore(xn_t2062);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2063;

    }
#line 1090 "impl/lib/b2/xparser.x"
rt_string *xn_t2064 = rt_retain(k);
xn_root_add(xn_t2064);
rt_string *xn_t2065 = rt_string_from_c("WhileStmt.P");
xn_root_add(xn_t2065);
    if ((xn_str_eq(xn_t2064, xn_t2065))) {
        size_t xn_t2066 = xn_root_mark();
        #line 1090 "impl/lib/b2/xparser.x"
        rt_string *xn_t2067 = rt_string_from_c("v");
xn_root_add(xn_t2067);
        xn_root_add(xn_t2067);
        xn_root_add(xn_t2067);
            {
        xn_root_restore(xn_t2066);
            }
            {
        rt_release(k);
            }
            {
        xn_root_restore(xn_t918);
            }

        return xn_t2067;

    }
#line 1091 "impl/lib/b2/xparser.x"
rt_string *xn_t2068 = rt_string_from_c("s");
xn_root_add(xn_t2068);
xn_root_add(xn_t2068);
    {
rt_release(k);
    }
    {
xn_root_restore(xn_t918);
    }

return xn_t2068;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

/* 类 Parser（M4.4b） */
typedef struct xn_Cls_Parser {
    rt_header hdr;
    xn_arr_o_Tok * toks;
    int64_t i;
    int64_t inNew;
    xn_arr_o_Diag * diags;
} xn_Cls_Parser;

static void xn_Cls_Parser_deinit_hook(void *p) {
    xn_Cls_Parser *o = (xn_Cls_Parser *)p;
}

static void xn_Cls_Parser_gc_scan(void *p, void (*visit)(void *)) {
    xn_Cls_Parser *o = (xn_Cls_Parser *)p;
    if (o->toks) { visit(o->toks); }
    if (o->diags) { visit(o->diags); }
}

static const rt_type RT_TYPE_XN_Parser = { "Parser", sizeof(xn_Cls_Parser), xn_Cls_Parser_deinit_hook, xn_Cls_Parser_gc_scan };

static void xn_Cls_Parser_new_init(xn_Cls_Parser *o, xn_arr_o_Tok * xn_p_ts) {
    xn_arr_o_Tok *xn_t2069 = xn_arr_o_Tok_new(0);
    o->toks = xn_t2069;
    o->i = 0;
    o->inNew = 0;
    xn_arr_o_Diag *xn_t2070 = xn_arr_o_Diag_new(0);
    o->diags = xn_t2070;
size_t xn_t2071 = xn_root_mark();
xn_root_add(o);
xn_root_add(xn_p_ts);
#line 1101 "impl/lib/b2/xparser.x"
o->toks = xn_p_ts;
    {
    xn_root_restore(xn_t2071);
    }
}

static xn_Cls_Parser *xn_Cls_Parser_new(xn_arr_o_Tok * xn_p_ts) {
    xn_Cls_Parser *o = (xn_Cls_Parser *)xn_gc_new(&RT_TYPE_XN_Parser);
    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_Parser) - sizeof(rt_header));
    xn_Cls_Parser_new_init(o, xn_p_ts);
    return o;
}

static void xn_Cls_Parser_err(xn_Cls_Parser *self, rt_string * xn_p_code, int64_t xn_p_l, int64_t xn_p_c, rt_string * xn_p_msg);
static xn_Cls_Tok * xn_Cls_Parser_cur(xn_Cls_Parser *self);
static int xn_Cls_Parser_at(xn_Cls_Parser *self, int64_t xn_p_k);
static int xn_Cls_Parser_atOp(xn_Cls_Parser *self, rt_string * xn_p_s);
static int xn_Cls_Parser_atKw(xn_Cls_Parser *self, rt_string * xn_p_s);
static xn_Cls_Tok * xn_Cls_Parser_next(xn_Cls_Parser *self);
static int xn_Cls_Parser_eof(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseUnit(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseTop(xn_Cls_Parser *self);
static xn_arr_s * xn_Cls_Parser_parseAnnos(xn_Cls_Parser *self);
static xn_Cls_M * xn_Cls_Parser_parseMods(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_retv(xn_Cls_Parser *self, int xn_p_vd, rt_string * xn_p_rt);
static rt_string * xn_Cls_Parser_modDump(xn_Cls_Parser *self, xn_Cls_M * xn_p_m);
static xn_arr_s * xn_Cls_Parser_parseParams(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseTypeDecl(xn_Cls_Parser *self, rt_string * xn_p_kw, int64_t xn_p_sl, int64_t xn_p_sc, xn_arr_s * xn_p_annos, xn_Cls_M * xn_p_m);
static rt_string * xn_Cls_Parser_parseModsDump(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseMember(xn_Cls_Parser *self, rt_string * xn_p_cls, xn_arr_s * xn_p_fields, xn_arr_s * xn_p_methods, xn_arr_s * xn_p_ctors);
static rt_string * xn_Cls_Parser_parseField(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseCtor(xn_Cls_Parser *self, int64_t xn_p_l, int64_t xn_p_c, xn_arr_s * xn_p_annos);
static rt_string * xn_Cls_Parser_parseAnnotationDecl(xn_Cls_Parser *self, int64_t xn_p_sl, int64_t xn_p_sc, xn_arr_s * xn_p_annos);
static rt_string * xn_Cls_Parser_parseParam(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseType(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseBlock(xn_Cls_Parser *self);
static int xn_Cls_Parser_isTypeStart(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseStmt(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseLocal(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseIf(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseWhile(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseDo(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseFor(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseSwitch(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseDefer(xn_Cls_Parser *self);
static xn_Cls_E * xn_Cls_Parser_mk(xn_Cls_Parser *self, rt_string * xn_p_d, int64_t xn_p_l, int64_t xn_p_c);
static xn_Cls_E * xn_Cls_Parser_parseExpr(xn_Cls_Parser *self);
static xn_Cls_E * xn_Cls_Parser_parseTernary(xn_Cls_Parser *self);
static xn_Cls_E * xn_Cls_Parser_parseCoalesce(xn_Cls_Parser *self);
static int64_t xn_Cls_Parser_prec(xn_Cls_Parser *self, rt_string * xn_p_op);
static xn_Cls_E * xn_Cls_Parser_parseBin(xn_Cls_Parser *self, int64_t xn_p_lvl);
static xn_Cls_E * xn_Cls_Parser_parseUnary(xn_Cls_Parser *self);
static xn_Cls_E * xn_Cls_Parser_parsePostfix(xn_Cls_Parser *self);
static int xn_Cls_Parser_genericCallAhead(xn_Cls_Parser *self);
static int xn_Cls_Parser_lambdaAhead(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseSubExpr(xn_Cls_Parser *self, rt_string * xn_p_text);
static xn_Cls_E * xn_Cls_Parser_parsePrimary(xn_Cls_Parser *self);

static void xn_Cls_Parser_err(xn_Cls_Parser *self, rt_string * xn_p_code, int64_t xn_p_l, int64_t xn_p_c, rt_string * xn_p_msg) {
size_t xn_t2072 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_code);
xn_root_add(xn_p_msg);
#line 1104 "impl/lib/b2/xparser.x"
xn_Cls_Diag * d = xn_Cls_Diag_new();
xn_root_add(d);
xn_root_add(d);
xn_gc_safepoint();
#line 1105 "impl/lib/b2/xparser.x"
rt_string *xn_t2073 = rt_retain(xn_p_code);
xn_root_add(xn_t2073);
rt_release(d->code);
d->code = xn_t2073;
#line 1106 "impl/lib/b2/xparser.x"
d->line = xn_p_l;
#line 1107 "impl/lib/b2/xparser.x"
d->col = xn_p_c;
#line 1108 "impl/lib/b2/xparser.x"
rt_string *xn_t2074 = rt_retain(xn_p_msg);
xn_root_add(xn_t2074);
rt_release(d->msg);
d->msg = xn_t2074;
#line 1109 "impl/lib/b2/xparser.x"
xn_arr_o_Diag_push(self->diags, d);
    {
    xn_root_restore(xn_t2072);
    }
}

static xn_Cls_Tok * xn_Cls_Parser_cur(xn_Cls_Parser *self) {
size_t xn_t2075 = xn_root_mark();
xn_root_add(self);
#line 1112 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t2075);
    }

return xn_arr_o_Tok_get(self->toks, self->i);
    return (xn_Cls_Tok *)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Parser_at(xn_Cls_Parser *self, int64_t xn_p_k) {
size_t xn_t2076 = xn_root_mark();
xn_root_add(self);
#line 1113 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2077 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2077);
xn_root_add(xn_t2077);
int xn_t2078 = (xn_t2077->kind == xn_p_k);
    {
xn_root_restore(xn_t2076);
    }

return xn_t2078;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Parser_atOp(xn_Cls_Parser *self, rt_string * xn_p_s) {
size_t xn_t2079 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_s);
#line 1114 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2080 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2080);
xn_root_add(xn_t2080);
xn_Cls_Tok * xn_t2081 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2081);
xn_root_add(xn_t2081);
rt_string *xn_t2082 = rt_retain(xn_t2081->text);
xn_root_add(xn_t2082);
xn_root_add(xn_t2082);
rt_string *xn_t2083 = rt_retain(xn_p_s);
xn_root_add(xn_t2083);
xn_root_add(xn_t2083);
int xn_t2084 = ((xn_t2080->kind == 9) && xn_str_eq(xn_t2082, xn_t2083));
    {
xn_root_restore(xn_t2079);
    }

return xn_t2084;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Parser_atKw(xn_Cls_Parser *self, rt_string * xn_p_s) {
size_t xn_t2085 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_s);
#line 1115 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2086 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2086);
xn_root_add(xn_t2086);
xn_Cls_Tok * xn_t2087 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2087);
xn_root_add(xn_t2087);
rt_string *xn_t2088 = rt_retain(xn_t2087->text);
xn_root_add(xn_t2088);
xn_root_add(xn_t2088);
rt_string *xn_t2089 = rt_retain(xn_p_s);
xn_root_add(xn_t2089);
xn_root_add(xn_t2089);
int xn_t2090 = ((xn_t2086->kind == 3) && xn_str_eq(xn_t2088, xn_t2089));
    {
xn_root_restore(xn_t2085);
    }

return xn_t2090;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_Tok * xn_Cls_Parser_next(xn_Cls_Parser *self) {
size_t xn_t2091 = xn_root_mark();
xn_root_add(self);
#line 1116 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_cur(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1116 "impl/lib/b2/xparser.x"
self->i = (self->i + 1);
#line 1116 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t2091);
    }

return t;
    return (xn_Cls_Tok *)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Parser_eof(xn_Cls_Parser *self) {
size_t xn_t2092 = xn_root_mark();
xn_root_add(self);
#line 1117 "impl/lib/b2/xparser.x"
int xn_t2093 = xn_Cls_Parser_at(self, 0);
    {
xn_root_restore(xn_t2092);
    }

return xn_t2093;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseUnit(xn_Cls_Parser *self) {
size_t xn_t2094 = xn_root_mark();
xn_root_add(self);
#line 1120 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2095 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2095);
int64_t sl = xn_t2095->line;
#line 1121 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2096 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2096);
int64_t sc = xn_t2096->col;
#line 1122 "impl/lib/b2/xparser.x"
rt_string *pkg = rt_string_from_c("(nil)");
xn_root_add(pkg);
xn_root_add(pkg);
xn_gc_safepoint();
#line 1123 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2098 = xn_arr_s_new(0);
xn_root_add(xn_t2098);
xn_arr_s * imps = xn_t2098;
xn_root_add(imps);
xn_root_add(imps);
xn_gc_safepoint();
#line 1124 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2099 = xn_arr_s_new(0);
xn_root_add(xn_t2099);
xn_arr_s * ds = xn_t2099;
xn_root_add(ds);
xn_root_add(ds);
xn_gc_safepoint();
#line 1125 "impl/lib/b2/xparser.x"
    while (((!(xn_Cls_Parser_eof(self))))) {
    size_t xn_t2100 = xn_root_mark();
    #line 1126 "impl/lib/b2/xparser.x"
        if ((xn_Cls_Parser_at(self, 1))) {
            size_t xn_t2101 = xn_root_mark();
            #line 1126 "impl/lib/b2/xparser.x"
            xn_Cls_Parser_next(self);
            #line 1126 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t2101);
            xn_root_restore(xn_t2100);
            continue;
                {
                xn_root_restore(xn_t2101);
                }

        }
    #line 1127 "impl/lib/b2/xparser.x"
    rt_string *xn_t2102 = rt_string_from_c("package");
xn_root_add(xn_t2102);
    xn_root_add(xn_t2102);
        if ((xn_Cls_Parser_atKw(self, xn_t2102))) {
            size_t xn_t2103 = xn_root_mark();
            #line 1128 "impl/lib/b2/xparser.x"
            xn_Cls_Tok * pt = xn_Cls_Parser_next(self);
xn_root_add(pt);
    xn_root_add(pt);
            xn_root_add(pt);
            xn_root_add(pt);
            xn_gc_safepoint();
            #line 1129 "impl/lib/b2/xparser.x"
            xn_arr_s *xn_t2104 = xn_arr_s_new(0);
xn_root_add(xn_t2104);
    xn_root_add(xn_t2104);
            xn_root_add(xn_t2104);
            xn_arr_s * qn = xn_t2104;
xn_root_add(qn);
    xn_root_add(qn);
            xn_root_add(qn);
            xn_root_add(qn);
            xn_gc_safepoint();
            #line 1130 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 2))) {
                    size_t xn_t2105 = xn_root_mark();
                    #line 1130 "impl/lib/b2/xparser.x"
                    xn_Cls_Tok * xn_t2106 = xn_Cls_Parser_next(self);
xn_root_add(xn_t2106);
    xn_root_add(xn_t2106);
            xn_root_add(xn_t2106);
                    xn_root_add(xn_t2106);
                    rt_string *xn_t2107 = rt_retain(xn_t2106->text);
xn_root_add(xn_t2107);
    xn_root_add(xn_t2107);
            xn_root_add(xn_t2107);
                    xn_root_add(xn_t2107);
                    xn_arr_s_push(qn, xn_t2107);
                        {
                        xn_root_restore(xn_t2105);
                        }

                }
            #line 1131 "impl/lib/b2/xparser.x"
                while (1) {
                    rt_string *xn_t2108 = rt_string_from_c(".");
xn_root_add(xn_t2108);
    xn_root_add(xn_t2108);
            xn_root_add(xn_t2108);
                    if (!((xn_Cls_Parser_atOp(self, xn_t2108)))) { break; }
                    size_t xn_t2109 = xn_root_mark();
                    #line 1131 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 1131 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 2))) {
                            size_t xn_t2110 = xn_root_mark();
                            #line 1131 "impl/lib/b2/xparser.x"
                            xn_Cls_Tok * xn_t2111 = xn_Cls_Parser_next(self);
xn_root_add(xn_t2111);
    xn_root_add(xn_t2111);
            xn_root_add(xn_t2111);
                    xn_root_add(xn_t2111);
                            xn_root_add(xn_t2111);
                            rt_string *xn_t2112 = rt_retain(xn_t2111->text);
xn_root_add(xn_t2112);
    xn_root_add(xn_t2112);
            xn_root_add(xn_t2112);
                    xn_root_add(xn_t2112);
                            xn_root_add(xn_t2112);
                            xn_arr_s_push(qn, xn_t2112);
                                {
                                xn_root_restore(xn_t2110);
                                }

                        }
                        {
                        xn_root_restore(xn_t2109);
                        }

                    xn_gc_safepoint();
                }
            #line 1132 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 1))) {
                    size_t xn_t2113 = xn_root_mark();
                    #line 1132 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t2113);
                        }

                }
            #line 1133 "impl/lib/b2/xparser.x"
            rt_string *xn_t2114 = rt_string_from_c("(PackageDecl ");
xn_root_add(xn_t2114);
    xn_root_add(xn_t2114);
            xn_root_add(xn_t2114);
            rt_string *xn_t2115 = xn_P(pt->line, pt->col);
xn_root_add(xn_t2115);
    xn_root_add(xn_t2115);
            xn_root_add(xn_t2115);
            rt_string *xn_t2116 = xn_concat(xn_t2114, xn_t2115);
xn_root_add(xn_t2116);
    xn_root_add(xn_t2116);
            xn_root_add(xn_t2116);
            rt_string *xn_t2117 = rt_string_from_c(" (Name ");
xn_root_add(xn_t2117);
    xn_root_add(xn_t2117);
            xn_root_add(xn_t2117);
            rt_string *xn_t2118 = xn_concat(xn_t2116, xn_t2117);
xn_root_add(xn_t2118);
    xn_root_add(xn_t2118);
            xn_root_add(xn_t2118);
            rt_string *xn_t2119 = xn_SLS(qn);
xn_root_add(xn_t2119);
    xn_root_add(xn_t2119);
            xn_root_add(xn_t2119);
            rt_string *xn_t2120 = xn_concat(xn_t2118, xn_t2119);
xn_root_add(xn_t2120);
    xn_root_add(xn_t2120);
            xn_root_add(xn_t2120);
            rt_string *xn_t2121 = rt_string_from_c("))");
xn_root_add(xn_t2121);
    xn_root_add(xn_t2121);
            xn_root_add(xn_t2121);
            rt_string *xn_t2122 = xn_concat(xn_t2120, xn_t2121);
xn_root_add(xn_t2122);
    xn_root_add(xn_t2122);
            xn_root_add(xn_t2122);
            xn_root_release(pkg);
            rt_release(pkg);
            pkg = xn_t2122;
            xn_root_hold(pkg);
            xn_gc_safepoint();
            #line 1134 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t2103);
            xn_root_restore(xn_t2100);
            continue;
                {
                xn_root_restore(xn_t2103);
                }

        }
    #line 1136 "impl/lib/b2/xparser.x"
    rt_string *xn_t2123 = rt_string_from_c("import");
xn_root_add(xn_t2123);
    xn_root_add(xn_t2123);
        if ((xn_Cls_Parser_atKw(self, xn_t2123))) {
            size_t xn_t2124 = xn_root_mark();
            #line 1137 "impl/lib/b2/xparser.x"
            xn_Cls_Tok * it = xn_Cls_Parser_next(self);
xn_root_add(it);
    xn_root_add(it);
            xn_root_add(it);
            xn_root_add(it);
            xn_gc_safepoint();
            #line 1138 "impl/lib/b2/xparser.x"
            xn_arr_s *xn_t2125 = xn_arr_s_new(0);
xn_root_add(xn_t2125);
    xn_root_add(xn_t2125);
            xn_root_add(xn_t2125);
            xn_arr_s * qn = xn_t2125;
xn_root_add(qn);
    xn_root_add(qn);
            xn_root_add(qn);
            xn_root_add(qn);
            xn_gc_safepoint();
            #line 1139 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 2))) {
                    size_t xn_t2126 = xn_root_mark();
                    #line 1139 "impl/lib/b2/xparser.x"
                    xn_Cls_Tok * xn_t2127 = xn_Cls_Parser_next(self);
xn_root_add(xn_t2127);
    xn_root_add(xn_t2127);
            xn_root_add(xn_t2127);
                    xn_root_add(xn_t2127);
                    rt_string *xn_t2128 = rt_retain(xn_t2127->text);
xn_root_add(xn_t2128);
    xn_root_add(xn_t2128);
            xn_root_add(xn_t2128);
                    xn_root_add(xn_t2128);
                    xn_arr_s_push(qn, xn_t2128);
                        {
                        xn_root_restore(xn_t2126);
                        }

                }
            #line 1140 "impl/lib/b2/xparser.x"
                while (1) {
                    rt_string *xn_t2129 = rt_string_from_c(".");
xn_root_add(xn_t2129);
    xn_root_add(xn_t2129);
            xn_root_add(xn_t2129);
                    if (!((xn_Cls_Parser_atOp(self, xn_t2129)))) { break; }
                    size_t xn_t2130 = xn_root_mark();
                    #line 1140 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 1140 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 2))) {
                            size_t xn_t2131 = xn_root_mark();
                            #line 1140 "impl/lib/b2/xparser.x"
                            xn_Cls_Tok * xn_t2132 = xn_Cls_Parser_next(self);
xn_root_add(xn_t2132);
    xn_root_add(xn_t2132);
            xn_root_add(xn_t2132);
                    xn_root_add(xn_t2132);
                            xn_root_add(xn_t2132);
                            rt_string *xn_t2133 = rt_retain(xn_t2132->text);
xn_root_add(xn_t2133);
    xn_root_add(xn_t2133);
            xn_root_add(xn_t2133);
                    xn_root_add(xn_t2133);
                            xn_root_add(xn_t2133);
                            xn_arr_s_push(qn, xn_t2133);
                                {
                                xn_root_restore(xn_t2131);
                                }

                        }
                        {
                        xn_root_restore(xn_t2130);
                        }

                    xn_gc_safepoint();
                }
            #line 1141 "impl/lib/b2/xparser.x"
            rt_string *al = rt_string_from_c("");
xn_root_add(al);
    xn_root_add(al);
            xn_root_add(al);
            xn_root_add(al);
            xn_gc_safepoint();
            #line 1142 "impl/lib/b2/xparser.x"
            rt_string *xn_t2135 = rt_string_from_c("as");
xn_root_add(xn_t2135);
    xn_root_add(xn_t2135);
            xn_root_add(xn_t2135);
                if ((xn_Cls_Parser_atKw(self, xn_t2135))) {
                    size_t xn_t2136 = xn_root_mark();
                    #line 1142 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 1142 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 2))) {
                            size_t xn_t2137 = xn_root_mark();
                            #line 1142 "impl/lib/b2/xparser.x"
                            xn_Cls_Tok * xn_t2138 = xn_Cls_Parser_next(self);
xn_root_add(xn_t2138);
    xn_root_add(xn_t2138);
            xn_root_add(xn_t2138);
                    xn_root_add(xn_t2138);
                            xn_root_add(xn_t2138);
                            rt_string *xn_t2139 = rt_retain(xn_t2138->text);
xn_root_add(xn_t2139);
    xn_root_add(xn_t2139);
            xn_root_add(xn_t2139);
                    xn_root_add(xn_t2139);
                            xn_root_add(xn_t2139);
                            xn_root_release(al);
                            rt_release(al);
                            al = xn_t2139;
                            xn_root_hold(al);
                            xn_gc_safepoint();
                                {
                                xn_root_restore(xn_t2137);
                                }

                        }
                        {
                        xn_root_restore(xn_t2136);
                        }

                }
            #line 1143 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 1))) {
                    size_t xn_t2140 = xn_root_mark();
                    #line 1143 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t2140);
                        }

                }
            #line 1144 "impl/lib/b2/xparser.x"
            rt_string *xn_t2141 = rt_string_from_c("(ImportDecl ");
xn_root_add(xn_t2141);
    xn_root_add(xn_t2141);
            xn_root_add(xn_t2141);
            rt_string *xn_t2142 = xn_P(it->line, it->col);
xn_root_add(xn_t2142);
    xn_root_add(xn_t2142);
            xn_root_add(xn_t2142);
            rt_string *xn_t2143 = xn_concat(xn_t2141, xn_t2142);
xn_root_add(xn_t2143);
    xn_root_add(xn_t2143);
            xn_root_add(xn_t2143);
            rt_string *xn_t2144 = rt_string_from_c(" (Path ");
xn_root_add(xn_t2144);
    xn_root_add(xn_t2144);
            xn_root_add(xn_t2144);
            rt_string *xn_t2145 = xn_concat(xn_t2143, xn_t2144);
xn_root_add(xn_t2145);
    xn_root_add(xn_t2145);
            xn_root_add(xn_t2145);
            rt_string *xn_t2146 = xn_SLS(qn);
xn_root_add(xn_t2146);
    xn_root_add(xn_t2146);
            xn_root_add(xn_t2146);
            rt_string *xn_t2147 = xn_concat(xn_t2145, xn_t2146);
xn_root_add(xn_t2147);
    xn_root_add(xn_t2147);
            xn_root_add(xn_t2147);
            rt_string *xn_t2148 = rt_string_from_c(") (Alias ");
xn_root_add(xn_t2148);
    xn_root_add(xn_t2148);
            xn_root_add(xn_t2148);
            rt_string *xn_t2149 = xn_concat(xn_t2147, xn_t2148);
xn_root_add(xn_t2149);
    xn_root_add(xn_t2149);
            xn_root_add(xn_t2149);
            rt_string *xn_t2150 = rt_retain(al);
xn_root_add(xn_t2150);
    xn_root_add(xn_t2150);
            xn_root_add(xn_t2150);
            rt_string *xn_t2151 = xn_q(xn_t2150);
xn_root_add(xn_t2151);
    xn_root_add(xn_t2151);
            xn_root_add(xn_t2151);
            rt_string *xn_t2152 = xn_concat(xn_t2149, xn_t2151);
xn_root_add(xn_t2152);
    xn_root_add(xn_t2152);
            xn_root_add(xn_t2152);
            rt_string *xn_t2153 = rt_string_from_c("))");
xn_root_add(xn_t2153);
    xn_root_add(xn_t2153);
            xn_root_add(xn_t2153);
            rt_string *xn_t2154 = xn_concat(xn_t2152, xn_t2153);
xn_root_add(xn_t2154);
    xn_root_add(xn_t2154);
            xn_root_add(xn_t2154);
            xn_arr_s_push(imps, xn_t2154);
            #line 1145 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t2124);
            xn_root_restore(xn_t2100);
            continue;
            xn_root_release(al);
                {
                rt_release(al);
                }
                {
                xn_root_restore(xn_t2124);
                }

        }
    #line 1147 "impl/lib/b2/xparser.x"
    rt_string *xn_t2155 = xn_Cls_Parser_parseTop(self);
xn_root_add(xn_t2155);
    xn_root_add(xn_t2155);
    xn_arr_s_push(ds, xn_t2155);
        {
        xn_root_restore(xn_t2100);
        }

    xn_gc_safepoint();
    }
#line 1149 "impl/lib/b2/xparser.x"
rt_string *xn_t2156 = rt_string_from_c("(CompilationUnit ");
xn_root_add(xn_t2156);
rt_string *xn_t2157 = xn_P(sl, sc);
xn_root_add(xn_t2157);
rt_string *xn_t2158 = xn_concat(xn_t2156, xn_t2157);
xn_root_add(xn_t2158);
rt_string *xn_t2159 = rt_string_from_c(" (Package ");
xn_root_add(xn_t2159);
rt_string *xn_t2160 = xn_concat(xn_t2158, xn_t2159);
xn_root_add(xn_t2160);
rt_string *xn_t2161 = rt_retain(pkg);
xn_root_add(xn_t2161);
rt_string *xn_t2162 = xn_concat(xn_t2160, xn_t2161);
xn_root_add(xn_t2162);
rt_string *xn_t2163 = rt_string_from_c(") (Imports ");
xn_root_add(xn_t2163);
rt_string *xn_t2164 = xn_concat(xn_t2162, xn_t2163);
xn_root_add(xn_t2164);
rt_string *xn_t2165 = xn_SL(imps);
xn_root_add(xn_t2165);
rt_string *xn_t2166 = xn_concat(xn_t2164, xn_t2165);
xn_root_add(xn_t2166);
rt_string *xn_t2167 = rt_string_from_c(") (Decls ");
xn_root_add(xn_t2167);
rt_string *xn_t2168 = xn_concat(xn_t2166, xn_t2167);
xn_root_add(xn_t2168);
rt_string *xn_t2169 = xn_SL(ds);
xn_root_add(xn_t2169);
rt_string *xn_t2170 = xn_concat(xn_t2168, xn_t2169);
xn_root_add(xn_t2170);
rt_string *xn_t2171 = rt_string_from_c("))");
xn_root_add(xn_t2171);
rt_string *body = xn_concat(xn_t2170, xn_t2171);
xn_root_add(body);
xn_root_add(body);
xn_gc_safepoint();
#line 1152 "impl/lib/b2/xparser.x"
rt_string *xn_t2173 = rt_string_from_c("(xnast v1 ");
xn_root_add(xn_t2173);
xn_root_add(xn_t2173);
rt_string *xn_t2174 = rt_retain(body);
xn_root_add(xn_t2174);
xn_root_add(xn_t2174);
rt_string *xn_t2175 = xn_concat(xn_t2173, xn_t2174);
xn_root_add(xn_t2175);
xn_root_add(xn_t2175);
rt_string *xn_t2176 = rt_string_from_c(")");
xn_root_add(xn_t2176);
xn_root_add(xn_t2176);
rt_string *xn_t2177 = xn_concat(xn_t2175, xn_t2176);
xn_root_add(xn_t2177);
xn_root_add(xn_t2177);
    {
rt_release(body);
    }
    {
rt_release(pkg);
    }
    {
xn_root_restore(xn_t2094);
    }

return xn_t2177;
xn_root_release(pkg);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseTop(xn_Cls_Parser *self) {
size_t xn_t2178 = xn_root_mark();
xn_root_add(self);
#line 1156 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2179 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2179);
int64_t sl = xn_t2179->line;
#line 1157 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2180 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2180);
int64_t sc = xn_t2180->col;
#line 1158 "impl/lib/b2/xparser.x"
xn_arr_s * annos = xn_Cls_Parser_parseAnnos(self);
xn_root_add(annos);
xn_root_add(annos);
xn_gc_safepoint();
#line 1159 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2181 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2181);
rt_string *xn_t2182 = rt_retain(xn_t2181->text);
xn_root_add(xn_t2182);
rt_string *xn_t2183 = rt_string_from_c("annotation");
xn_root_add(xn_t2183);
    if (((xn_Cls_Parser_at(self, 4)) && (xn_str_eq(xn_t2182, xn_t2183)))) {
        size_t xn_t2184 = xn_root_mark();
        #line 1160 "impl/lib/b2/xparser.x"
        rt_string *xn_t2185 = xn_Cls_Parser_parseAnnotationDecl(self, sl, sc, annos);
xn_root_add(xn_t2185);
        xn_root_add(xn_t2185);
        xn_root_add(xn_t2185);
            {
        xn_root_restore(xn_t2184);
            }
            {
        xn_root_restore(xn_t2178);
            }

        return xn_t2185;

    }
#line 1162 "impl/lib/b2/xparser.x"
xn_Cls_M * m = xn_Cls_Parser_parseMods(self);
xn_root_add(m);
xn_root_add(m);
xn_gc_safepoint();
#line 1163 "impl/lib/b2/xparser.x"
rt_string *kw = rt_string_from_c("");
xn_root_add(kw);
xn_root_add(kw);
xn_gc_safepoint();
#line 1164 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2187 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2187);
    if (((xn_t2187->kind == 3))) {
        size_t xn_t2188 = xn_root_mark();
        #line 1165 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t2189 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2189);
        xn_root_add(xn_t2189);
        rt_string *k = rt_retain(xn_t2189->text);
xn_root_add(k);
        xn_root_add(k);
        xn_root_add(k);
        xn_gc_safepoint();
        #line 1166 "impl/lib/b2/xparser.x"
        rt_string *xn_t2191 = rt_retain(k);
xn_root_add(xn_t2191);
        xn_root_add(xn_t2191);
        rt_string *xn_t2192 = rt_string_from_c("class");
xn_root_add(xn_t2192);
        xn_root_add(xn_t2192);
        rt_string *xn_t2193 = rt_retain(k);
xn_root_add(xn_t2193);
        xn_root_add(xn_t2193);
        rt_string *xn_t2194 = rt_string_from_c("struct");
xn_root_add(xn_t2194);
        xn_root_add(xn_t2194);
        rt_string *xn_t2195 = rt_retain(k);
xn_root_add(xn_t2195);
        xn_root_add(xn_t2195);
        rt_string *xn_t2196 = rt_string_from_c("protocol");
xn_root_add(xn_t2196);
        xn_root_add(xn_t2196);
        rt_string *xn_t2197 = rt_retain(k);
xn_root_add(xn_t2197);
        xn_root_add(xn_t2197);
        rt_string *xn_t2198 = rt_string_from_c("enum");
xn_root_add(xn_t2198);
        xn_root_add(xn_t2198);
        rt_string *xn_t2199 = rt_retain(k);
xn_root_add(xn_t2199);
        xn_root_add(xn_t2199);
        rt_string *xn_t2200 = rt_string_from_c("singleton");
xn_root_add(xn_t2200);
        xn_root_add(xn_t2200);
        rt_string *xn_t2201 = rt_retain(k);
xn_root_add(xn_t2201);
        xn_root_add(xn_t2201);
        rt_string *xn_t2202 = rt_string_from_c("factory");
xn_root_add(xn_t2202);
        xn_root_add(xn_t2202);
        rt_string *xn_t2203 = rt_retain(k);
xn_root_add(xn_t2203);
        xn_root_add(xn_t2203);
        rt_string *xn_t2204 = rt_string_from_c("extension");
xn_root_add(xn_t2204);
        xn_root_add(xn_t2204);
            if ((((((((xn_str_eq(xn_t2191, xn_t2192)) || (xn_str_eq(xn_t2193, xn_t2194))) || (xn_str_eq(xn_t2195, xn_t2196))) || (xn_str_eq(xn_t2197, xn_t2198))) || (xn_str_eq(xn_t2199, xn_t2200))) || (xn_str_eq(xn_t2201, xn_t2202))) || (xn_str_eq(xn_t2203, xn_t2204)))) {
                size_t xn_t2205 = xn_root_mark();
                #line 1168 "impl/lib/b2/xparser.x"
                rt_string *xn_t2206 = rt_retain(k);
xn_root_add(xn_t2206);
        xn_root_add(xn_t2206);
                xn_root_add(xn_t2206);
                xn_root_release(kw);
                rt_release(kw);
                kw = xn_t2206;
                xn_root_hold(kw);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t2205);
                    }

            }
            {
            rt_release(k);
            }
            {
            xn_root_restore(xn_t2188);
            }

    }
#line 1171 "impl/lib/b2/xparser.x"
rt_string *xn_t2207 = rt_retain(kw);
xn_root_add(xn_t2207);
rt_string *xn_t2208 = rt_string_from_c("");
xn_root_add(xn_t2208);
    if (((!(xn_str_eq(xn_t2207, xn_t2208))))) {
        size_t xn_t2209 = xn_root_mark();
        #line 1172 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1173 "impl/lib/b2/xparser.x"
        rt_string *xn_t2210 = rt_retain(kw);
xn_root_add(xn_t2210);
        xn_root_add(xn_t2210);
        xn_root_add(xn_t2210);
        rt_string *xn_t2211 = xn_Cls_Parser_parseTypeDecl(self, xn_t2210, sl, sc, annos, m);
xn_root_add(xn_t2211);
        xn_root_add(xn_t2211);
        xn_root_add(xn_t2211);
            {
        xn_root_restore(xn_t2209);
            }
            {
        rt_release(kw);
            }
            {
        xn_root_restore(xn_t2178);
            }

        return xn_t2211;

    }
#line 1175 "impl/lib/b2/xparser.x"
int xn_v_void = 0;
#line 1176 "impl/lib/b2/xparser.x"
rt_string *ret = rt_string_from_c("");
xn_root_add(ret);
xn_root_add(ret);
xn_gc_safepoint();
#line 1177 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2213 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2213);
rt_string *xn_t2214 = rt_retain(xn_t2213->text);
xn_root_add(xn_t2214);
rt_string *xn_t2215 = rt_string_from_c("void");
xn_root_add(xn_t2215);
    if (((xn_Cls_Parser_at(self, 2)) && (xn_str_eq(xn_t2214, xn_t2215)))) {
        size_t xn_t2216 = xn_root_mark();
        #line 1177 "impl/lib/b2/xparser.x"
        xn_v_void = 1;
        #line 1177 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t2216);
            }

    } else {
        size_t xn_t2217 = xn_root_mark();
        #line 1178 "impl/lib/b2/xparser.x"
        rt_string *xn_t2218 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t2218);
        xn_root_add(xn_t2218);
        xn_root_release(ret);
        rt_release(ret);
        ret = xn_t2218;
        xn_root_hold(ret);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t2217);
            }

    }
#line 1179 "impl/lib/b2/xparser.x"
rt_string *name = rt_string_from_c("");
xn_root_add(name);
xn_root_add(name);
xn_gc_safepoint();
#line 1180 "impl/lib/b2/xparser.x"
int64_t nl = sl;
#line 1181 "impl/lib/b2/xparser.x"
int64_t nc = sc;
#line 1182 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 2))) {
        size_t xn_t2220 = xn_root_mark();
        #line 1182 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * nt = xn_Cls_Parser_next(self);
xn_root_add(nt);
        xn_root_add(nt);
        xn_root_add(nt);
        xn_gc_safepoint();
        #line 1182 "impl/lib/b2/xparser.x"
        rt_string *xn_t2221 = rt_retain(nt->text);
xn_root_add(xn_t2221);
        xn_root_add(xn_t2221);
        xn_root_release(name);
        rt_release(name);
        name = xn_t2221;
        xn_root_hold(name);
        xn_gc_safepoint();
        #line 1182 "impl/lib/b2/xparser.x"
        nl = nt->line;
        #line 1182 "impl/lib/b2/xparser.x"
        nc = nt->col;
            {
            xn_root_restore(xn_t2220);
            }

    }
#line 1183 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2222 = xn_arr_s_new(0);
xn_root_add(xn_t2222);
xn_arr_s * tps = xn_t2222;
xn_root_add(tps);
xn_root_add(tps);
xn_gc_safepoint();
#line 1184 "impl/lib/b2/xparser.x"
rt_string *xn_t2223 = rt_string_from_c("<");
xn_root_add(xn_t2223);
    if ((xn_Cls_Parser_atOp(self, xn_t2223))) {
        size_t xn_t2224 = xn_root_mark();
        #line 1185 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1186 "impl/lib/b2/xparser.x"
            while (1) {
                rt_string *xn_t2225 = rt_string_from_c(">");
xn_root_add(xn_t2225);
        xn_root_add(xn_t2225);
                if (!((((!(xn_Cls_Parser_atOp(self, xn_t2225)))) && ((!(xn_Cls_Parser_eof(self))))))) { break; }
                size_t xn_t2226 = xn_root_mark();
                #line 1187 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 2))) {
                        size_t xn_t2227 = xn_root_mark();
                        #line 1187 "impl/lib/b2/xparser.x"
                        xn_Cls_Tok * xn_t2228 = xn_Cls_Parser_next(self);
xn_root_add(xn_t2228);
        xn_root_add(xn_t2228);
                xn_root_add(xn_t2228);
                        xn_root_add(xn_t2228);
                        rt_string *xn_t2229 = rt_retain(xn_t2228->text);
xn_root_add(xn_t2229);
        xn_root_add(xn_t2229);
                xn_root_add(xn_t2229);
                        xn_root_add(xn_t2229);
                        xn_arr_s_push(tps, xn_t2229);
                            {
                            xn_root_restore(xn_t2227);
                            }

                    } else {
                        size_t xn_t2230 = xn_root_mark();
                        #line 1187 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t2230);
                            }

                    }
                    {
                    xn_root_restore(xn_t2226);
                    }

                xn_gc_safepoint();
            }
        #line 1189 "impl/lib/b2/xparser.x"
        rt_string *xn_t2231 = rt_string_from_c(">");
xn_root_add(xn_t2231);
        xn_root_add(xn_t2231);
            if ((xn_Cls_Parser_atOp(self, xn_t2231))) {
                size_t xn_t2232 = xn_root_mark();
                #line 1189 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t2232);
                    }

            }
            {
            xn_root_restore(xn_t2224);
            }

    }
#line 1191 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 10))) {
        size_t xn_t2233 = xn_root_mark();
        #line 1192 "impl/lib/b2/xparser.x"
        xn_arr_s * ps = xn_Cls_Parser_parseParams(self);
xn_root_add(ps);
        xn_root_add(ps);
        xn_root_add(ps);
        xn_gc_safepoint();
        #line 1193 "impl/lib/b2/xparser.x"
        rt_string *body = xn_Cls_Parser_parseBlock(self);
xn_root_add(body);
        xn_root_add(body);
        xn_root_add(body);
        xn_gc_safepoint();
        #line 1194 "impl/lib/b2/xparser.x"
        rt_string *retv = rt_string_from_c("(nil)");
xn_root_add(retv);
        xn_root_add(retv);
        xn_root_add(retv);
        xn_gc_safepoint();
        #line 1195 "impl/lib/b2/xparser.x"
            if (((!(xn_v_void)))) {
                size_t xn_t2236 = xn_root_mark();
                #line 1195 "impl/lib/b2/xparser.x"
                rt_string *xn_t2237 = rt_retain(ret);
xn_root_add(xn_t2237);
        xn_root_add(xn_t2237);
                xn_root_add(xn_t2237);
                xn_root_release(retv);
                rt_release(retv);
                retv = xn_t2237;
                xn_root_hold(retv);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t2236);
                    }

            }
        #line 1196 "impl/lib/b2/xparser.x"
        rt_string *xn_t2238 = rt_string_from_c("(TopFunc ");
xn_root_add(xn_t2238);
        xn_root_add(xn_t2238);
        xn_root_add(xn_t2238);
        rt_string *xn_t2239 = xn_P(sl, sc);
xn_root_add(xn_t2239);
        xn_root_add(xn_t2239);
        xn_root_add(xn_t2239);
        rt_string *xn_t2240 = xn_concat(xn_t2238, xn_t2239);
xn_root_add(xn_t2240);
        xn_root_add(xn_t2240);
        xn_root_add(xn_t2240);
        rt_string *xn_t2241 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2241);
        xn_root_add(xn_t2241);
        xn_root_add(xn_t2241);
        rt_string *xn_t2242 = xn_concat(xn_t2240, xn_t2241);
xn_root_add(xn_t2242);
        xn_root_add(xn_t2242);
        xn_root_add(xn_t2242);
        rt_string *xn_t2243 = xn_SL(annos);
xn_root_add(xn_t2243);
        xn_root_add(xn_t2243);
        xn_root_add(xn_t2243);
        rt_string *xn_t2244 = xn_concat(xn_t2242, xn_t2243);
xn_root_add(xn_t2244);
        xn_root_add(xn_t2244);
        xn_root_add(xn_t2244);
        rt_string *xn_t2245 = rt_string_from_c(") (Public ");
xn_root_add(xn_t2245);
        xn_root_add(xn_t2245);
        xn_root_add(xn_t2245);
        rt_string *xn_t2246 = xn_concat(xn_t2244, xn_t2245);
xn_root_add(xn_t2246);
        xn_root_add(xn_t2246);
        xn_root_add(xn_t2246);
        rt_string *xn_t2247 = rt_retain(m->vis);
xn_root_add(xn_t2247);
        xn_root_add(xn_t2247);
        xn_root_add(xn_t2247);
        rt_string *xn_t2248 = rt_string_from_c("public");
xn_root_add(xn_t2248);
        xn_root_add(xn_t2248);
        xn_root_add(xn_t2248);
        rt_string *xn_t2249 = xn_B(xn_str_eq(xn_t2247, xn_t2248));
xn_root_add(xn_t2249);
        xn_root_add(xn_t2249);
        xn_root_add(xn_t2249);
        rt_string *xn_t2250 = xn_concat(xn_t2246, xn_t2249);
xn_root_add(xn_t2250);
        xn_root_add(xn_t2250);
        xn_root_add(xn_t2250);
        rt_string *xn_t2251 = rt_string_from_c(") (Protected ");
xn_root_add(xn_t2251);
        xn_root_add(xn_t2251);
        xn_root_add(xn_t2251);
        rt_string *xn_t2252 = xn_concat(xn_t2250, xn_t2251);
xn_root_add(xn_t2252);
        xn_root_add(xn_t2252);
        xn_root_add(xn_t2252);
        rt_string *xn_t2253 = rt_retain(m->vis);
xn_root_add(xn_t2253);
        xn_root_add(xn_t2253);
        xn_root_add(xn_t2253);
        rt_string *xn_t2254 = rt_string_from_c("protected");
xn_root_add(xn_t2254);
        xn_root_add(xn_t2254);
        xn_root_add(xn_t2254);
        rt_string *xn_t2255 = xn_B(xn_str_eq(xn_t2253, xn_t2254));
xn_root_add(xn_t2255);
        xn_root_add(xn_t2255);
        xn_root_add(xn_t2255);
        rt_string *xn_t2256 = xn_concat(xn_t2252, xn_t2255);
xn_root_add(xn_t2256);
        xn_root_add(xn_t2256);
        xn_root_add(xn_t2256);
        rt_string *xn_t2257 = rt_string_from_c(") (Private ");
xn_root_add(xn_t2257);
        xn_root_add(xn_t2257);
        xn_root_add(xn_t2257);
        rt_string *xn_t2258 = xn_concat(xn_t2256, xn_t2257);
xn_root_add(xn_t2258);
        xn_root_add(xn_t2258);
        xn_root_add(xn_t2258);
        rt_string *xn_t2259 = rt_retain(m->vis);
xn_root_add(xn_t2259);
        xn_root_add(xn_t2259);
        xn_root_add(xn_t2259);
        rt_string *xn_t2260 = rt_string_from_c("private");
xn_root_add(xn_t2260);
        xn_root_add(xn_t2260);
        xn_root_add(xn_t2260);
        rt_string *xn_t2261 = xn_B(xn_str_eq(xn_t2259, xn_t2260));
xn_root_add(xn_t2261);
        xn_root_add(xn_t2261);
        xn_root_add(xn_t2261);
        rt_string *xn_t2262 = xn_concat(xn_t2258, xn_t2261);
xn_root_add(xn_t2262);
        xn_root_add(xn_t2262);
        xn_root_add(xn_t2262);
        rt_string *xn_t2263 = rt_string_from_c(") (Static ");
xn_root_add(xn_t2263);
        xn_root_add(xn_t2263);
        xn_root_add(xn_t2263);
        rt_string *xn_t2264 = xn_concat(xn_t2262, xn_t2263);
xn_root_add(xn_t2264);
        xn_root_add(xn_t2264);
        xn_root_add(xn_t2264);
        rt_string *xn_t2265 = xn_B(((int)(m->stat)));
xn_root_add(xn_t2265);
        xn_root_add(xn_t2265);
        xn_root_add(xn_t2265);
        rt_string *xn_t2266 = xn_concat(xn_t2264, xn_t2265);
xn_root_add(xn_t2266);
        xn_root_add(xn_t2266);
        xn_root_add(xn_t2266);
        rt_string *xn_t2267 = rt_string_from_c(") (Void ");
xn_root_add(xn_t2267);
        xn_root_add(xn_t2267);
        xn_root_add(xn_t2267);
        rt_string *xn_t2268 = xn_concat(xn_t2266, xn_t2267);
xn_root_add(xn_t2268);
        xn_root_add(xn_t2268);
        xn_root_add(xn_t2268);
        rt_string *xn_t2269 = xn_B(xn_v_void);
xn_root_add(xn_t2269);
        xn_root_add(xn_t2269);
        xn_root_add(xn_t2269);
        rt_string *xn_t2270 = xn_concat(xn_t2268, xn_t2269);
xn_root_add(xn_t2270);
        xn_root_add(xn_t2270);
        xn_root_add(xn_t2270);
        rt_string *xn_t2271 = rt_string_from_c(") (Ret ");
xn_root_add(xn_t2271);
        xn_root_add(xn_t2271);
        xn_root_add(xn_t2271);
        rt_string *xn_t2272 = xn_concat(xn_t2270, xn_t2271);
xn_root_add(xn_t2272);
        xn_root_add(xn_t2272);
        xn_root_add(xn_t2272);
        rt_string *xn_t2273 = rt_retain(retv);
xn_root_add(xn_t2273);
        xn_root_add(xn_t2273);
        xn_root_add(xn_t2273);
        rt_string *xn_t2274 = xn_concat(xn_t2272, xn_t2273);
xn_root_add(xn_t2274);
        xn_root_add(xn_t2274);
        xn_root_add(xn_t2274);
        rt_string *xn_t2275 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2275);
        xn_root_add(xn_t2275);
        xn_root_add(xn_t2275);
        rt_string *xn_t2276 = xn_concat(xn_t2274, xn_t2275);
xn_root_add(xn_t2276);
        xn_root_add(xn_t2276);
        xn_root_add(xn_t2276);
        rt_string *xn_t2277 = rt_retain(name);
xn_root_add(xn_t2277);
        xn_root_add(xn_t2277);
        xn_root_add(xn_t2277);
        rt_string *xn_t2278 = xn_q(xn_t2277);
xn_root_add(xn_t2278);
        xn_root_add(xn_t2278);
        xn_root_add(xn_t2278);
        rt_string *xn_t2279 = xn_concat(xn_t2276, xn_t2278);
xn_root_add(xn_t2279);
        xn_root_add(xn_t2279);
        xn_root_add(xn_t2279);
        rt_string *xn_t2280 = rt_string_from_c(") (TypePars ");
xn_root_add(xn_t2280);
        xn_root_add(xn_t2280);
        xn_root_add(xn_t2280);
        rt_string *xn_t2281 = xn_concat(xn_t2279, xn_t2280);
xn_root_add(xn_t2281);
        xn_root_add(xn_t2281);
        xn_root_add(xn_t2281);
        rt_string *xn_t2282 = xn_SLS(tps);
xn_root_add(xn_t2282);
        xn_root_add(xn_t2282);
        xn_root_add(xn_t2282);
        rt_string *xn_t2283 = xn_concat(xn_t2281, xn_t2282);
xn_root_add(xn_t2283);
        xn_root_add(xn_t2283);
        xn_root_add(xn_t2283);
        rt_string *xn_t2284 = rt_string_from_c(") (Params ");
xn_root_add(xn_t2284);
        xn_root_add(xn_t2284);
        xn_root_add(xn_t2284);
        rt_string *xn_t2285 = xn_concat(xn_t2283, xn_t2284);
xn_root_add(xn_t2285);
        xn_root_add(xn_t2285);
        xn_root_add(xn_t2285);
        rt_string *xn_t2286 = xn_SL(ps);
xn_root_add(xn_t2286);
        xn_root_add(xn_t2286);
        xn_root_add(xn_t2286);
        rt_string *xn_t2287 = xn_concat(xn_t2285, xn_t2286);
xn_root_add(xn_t2287);
        xn_root_add(xn_t2287);
        xn_root_add(xn_t2287);
        rt_string *xn_t2288 = rt_string_from_c(") (Body ");
xn_root_add(xn_t2288);
        xn_root_add(xn_t2288);
        xn_root_add(xn_t2288);
        rt_string *xn_t2289 = xn_concat(xn_t2287, xn_t2288);
xn_root_add(xn_t2289);
        xn_root_add(xn_t2289);
        xn_root_add(xn_t2289);
        rt_string *xn_t2290 = rt_retain(body);
xn_root_add(xn_t2290);
        xn_root_add(xn_t2290);
        xn_root_add(xn_t2290);
        rt_string *xn_t2291 = xn_concat(xn_t2289, xn_t2290);
xn_root_add(xn_t2291);
        xn_root_add(xn_t2291);
        xn_root_add(xn_t2291);
        rt_string *xn_t2292 = rt_string_from_c("))");
xn_root_add(xn_t2292);
        xn_root_add(xn_t2292);
        xn_root_add(xn_t2292);
        rt_string *xn_t2293 = xn_concat(xn_t2291, xn_t2292);
xn_root_add(xn_t2293);
        xn_root_add(xn_t2293);
        xn_root_add(xn_t2293);
            {
        rt_release(retv);
            }
            {
        rt_release(body);
            }
            {
        xn_root_restore(xn_t2233);
            }
            {
        rt_release(name);
            }
            {
        rt_release(ret);
            }
            {
        rt_release(kw);
            }
            {
        xn_root_restore(xn_t2178);
            }

        return xn_t2293;
        xn_root_release(retv);

    }
#line 1201 "impl/lib/b2/xparser.x"
rt_string *init = rt_string_from_c("(nil)");
xn_root_add(init);
xn_root_add(init);
xn_gc_safepoint();
#line 1202 "impl/lib/b2/xparser.x"
rt_string *xn_t2295 = rt_string_from_c("=");
xn_root_add(xn_t2295);
    if ((xn_Cls_Parser_atOp(self, xn_t2295))) {
        size_t xn_t2296 = xn_root_mark();
        #line 1202 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1202 "impl/lib/b2/xparser.x"
        xn_Cls_E * xn_t2297 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t2297);
        xn_root_add(xn_t2297);
        rt_string *xn_t2298 = rt_retain(xn_t2297->d);
xn_root_add(xn_t2298);
        xn_root_add(xn_t2298);
        xn_root_release(init);
        rt_release(init);
        init = xn_t2298;
        xn_root_hold(init);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t2296);
            }

    }
#line 1203 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 1))) {
        size_t xn_t2299 = xn_root_mark();
        #line 1203 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t2299);
            }

    }
#line 1204 "impl/lib/b2/xparser.x"
rt_string *xn_t2300 = rt_string_from_c("(TopField ");
xn_root_add(xn_t2300);
xn_root_add(xn_t2300);
rt_string *xn_t2301 = xn_P(sl, sc);
xn_root_add(xn_t2301);
xn_root_add(xn_t2301);
rt_string *xn_t2302 = xn_concat(xn_t2300, xn_t2301);
xn_root_add(xn_t2302);
xn_root_add(xn_t2302);
rt_string *xn_t2303 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2303);
xn_root_add(xn_t2303);
rt_string *xn_t2304 = xn_concat(xn_t2302, xn_t2303);
xn_root_add(xn_t2304);
xn_root_add(xn_t2304);
rt_string *xn_t2305 = xn_SL(annos);
xn_root_add(xn_t2305);
xn_root_add(xn_t2305);
rt_string *xn_t2306 = xn_concat(xn_t2304, xn_t2305);
xn_root_add(xn_t2306);
xn_root_add(xn_t2306);
rt_string *xn_t2307 = rt_string_from_c(") (Public ");
xn_root_add(xn_t2307);
xn_root_add(xn_t2307);
rt_string *xn_t2308 = xn_concat(xn_t2306, xn_t2307);
xn_root_add(xn_t2308);
xn_root_add(xn_t2308);
rt_string *xn_t2309 = rt_retain(m->vis);
xn_root_add(xn_t2309);
xn_root_add(xn_t2309);
rt_string *xn_t2310 = rt_string_from_c("public");
xn_root_add(xn_t2310);
xn_root_add(xn_t2310);
rt_string *xn_t2311 = xn_B(xn_str_eq(xn_t2309, xn_t2310));
xn_root_add(xn_t2311);
xn_root_add(xn_t2311);
rt_string *xn_t2312 = xn_concat(xn_t2308, xn_t2311);
xn_root_add(xn_t2312);
xn_root_add(xn_t2312);
rt_string *xn_t2313 = rt_string_from_c(") (Protected ");
xn_root_add(xn_t2313);
xn_root_add(xn_t2313);
rt_string *xn_t2314 = xn_concat(xn_t2312, xn_t2313);
xn_root_add(xn_t2314);
xn_root_add(xn_t2314);
rt_string *xn_t2315 = rt_retain(m->vis);
xn_root_add(xn_t2315);
xn_root_add(xn_t2315);
rt_string *xn_t2316 = rt_string_from_c("protected");
xn_root_add(xn_t2316);
xn_root_add(xn_t2316);
rt_string *xn_t2317 = xn_B(xn_str_eq(xn_t2315, xn_t2316));
xn_root_add(xn_t2317);
xn_root_add(xn_t2317);
rt_string *xn_t2318 = xn_concat(xn_t2314, xn_t2317);
xn_root_add(xn_t2318);
xn_root_add(xn_t2318);
rt_string *xn_t2319 = rt_string_from_c(") (Private ");
xn_root_add(xn_t2319);
xn_root_add(xn_t2319);
rt_string *xn_t2320 = xn_concat(xn_t2318, xn_t2319);
xn_root_add(xn_t2320);
xn_root_add(xn_t2320);
rt_string *xn_t2321 = rt_retain(m->vis);
xn_root_add(xn_t2321);
xn_root_add(xn_t2321);
rt_string *xn_t2322 = rt_string_from_c("private");
xn_root_add(xn_t2322);
xn_root_add(xn_t2322);
rt_string *xn_t2323 = xn_B(xn_str_eq(xn_t2321, xn_t2322));
xn_root_add(xn_t2323);
xn_root_add(xn_t2323);
rt_string *xn_t2324 = xn_concat(xn_t2320, xn_t2323);
xn_root_add(xn_t2324);
xn_root_add(xn_t2324);
rt_string *xn_t2325 = rt_string_from_c(") (Static ");
xn_root_add(xn_t2325);
xn_root_add(xn_t2325);
rt_string *xn_t2326 = xn_concat(xn_t2324, xn_t2325);
xn_root_add(xn_t2326);
xn_root_add(xn_t2326);
rt_string *xn_t2327 = xn_B(((int)(m->stat)));
xn_root_add(xn_t2327);
xn_root_add(xn_t2327);
rt_string *xn_t2328 = xn_concat(xn_t2326, xn_t2327);
xn_root_add(xn_t2328);
xn_root_add(xn_t2328);
rt_string *xn_t2329 = rt_string_from_c(") (Final ");
xn_root_add(xn_t2329);
xn_root_add(xn_t2329);
rt_string *xn_t2330 = xn_concat(xn_t2328, xn_t2329);
xn_root_add(xn_t2330);
xn_root_add(xn_t2330);
rt_string *xn_t2331 = xn_B(((int)(m->fin)));
xn_root_add(xn_t2331);
xn_root_add(xn_t2331);
rt_string *xn_t2332 = xn_concat(xn_t2330, xn_t2331);
xn_root_add(xn_t2332);
xn_root_add(xn_t2332);
rt_string *xn_t2333 = rt_string_from_c(") (Const ");
xn_root_add(xn_t2333);
xn_root_add(xn_t2333);
rt_string *xn_t2334 = xn_concat(xn_t2332, xn_t2333);
xn_root_add(xn_t2334);
xn_root_add(xn_t2334);
rt_string *xn_t2335 = xn_B(((int)(m->cons)));
xn_root_add(xn_t2335);
xn_root_add(xn_t2335);
rt_string *xn_t2336 = xn_concat(xn_t2334, xn_t2335);
xn_root_add(xn_t2336);
xn_root_add(xn_t2336);
rt_string *xn_t2337 = rt_string_from_c(") (Type ");
xn_root_add(xn_t2337);
xn_root_add(xn_t2337);
rt_string *xn_t2338 = xn_concat(xn_t2336, xn_t2337);
xn_root_add(xn_t2338);
xn_root_add(xn_t2338);
rt_string *xn_t2339 = rt_retain(ret);
xn_root_add(xn_t2339);
xn_root_add(xn_t2339);
rt_string *xn_t2340 = xn_concat(xn_t2338, xn_t2339);
xn_root_add(xn_t2340);
xn_root_add(xn_t2340);
rt_string *xn_t2341 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2341);
xn_root_add(xn_t2341);
rt_string *xn_t2342 = xn_concat(xn_t2340, xn_t2341);
xn_root_add(xn_t2342);
xn_root_add(xn_t2342);
rt_string *xn_t2343 = rt_retain(name);
xn_root_add(xn_t2343);
xn_root_add(xn_t2343);
rt_string *xn_t2344 = xn_q(xn_t2343);
xn_root_add(xn_t2344);
xn_root_add(xn_t2344);
rt_string *xn_t2345 = xn_concat(xn_t2342, xn_t2344);
xn_root_add(xn_t2345);
xn_root_add(xn_t2345);
rt_string *xn_t2346 = rt_string_from_c(") (Init ");
xn_root_add(xn_t2346);
xn_root_add(xn_t2346);
rt_string *xn_t2347 = xn_concat(xn_t2345, xn_t2346);
xn_root_add(xn_t2347);
xn_root_add(xn_t2347);
rt_string *xn_t2348 = rt_retain(init);
xn_root_add(xn_t2348);
xn_root_add(xn_t2348);
rt_string *xn_t2349 = xn_concat(xn_t2347, xn_t2348);
xn_root_add(xn_t2349);
xn_root_add(xn_t2349);
rt_string *xn_t2350 = rt_string_from_c("))");
xn_root_add(xn_t2350);
xn_root_add(xn_t2350);
rt_string *xn_t2351 = xn_concat(xn_t2349, xn_t2350);
xn_root_add(xn_t2351);
xn_root_add(xn_t2351);
    {
rt_release(init);
    }
    {
rt_release(name);
    }
    {
rt_release(ret);
    }
    {
rt_release(kw);
    }
    {
xn_root_restore(xn_t2178);
    }

return xn_t2351;
xn_root_release(kw);
xn_root_release(ret);
xn_root_release(name);
xn_root_release(init);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_arr_s * xn_Cls_Parser_parseAnnos(xn_Cls_Parser *self) {
size_t xn_t2352 = xn_root_mark();
xn_root_add(self);
#line 1211 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2353 = xn_arr_s_new(0);
xn_root_add(xn_t2353);
xn_arr_s * res = xn_t2353;
xn_root_add(res);
xn_root_add(res);
xn_gc_safepoint();
#line 1212 "impl/lib/b2/xparser.x"
    while ((xn_Cls_Parser_at(self, 4))) {
    size_t xn_t2354 = xn_root_mark();
    #line 1213 "impl/lib/b2/xparser.x"
    xn_Cls_Tok * t = xn_Cls_Parser_next(self);
xn_root_add(t);
    xn_root_add(t);
    xn_root_add(t);
    xn_gc_safepoint();
    #line 1214 "impl/lib/b2/xparser.x"
    xn_arr_s *xn_t2355 = xn_arr_s_new(0);
xn_root_add(xn_t2355);
    xn_root_add(xn_t2355);
    xn_arr_s * args = xn_t2355;
xn_root_add(args);
    xn_root_add(args);
    xn_root_add(args);
    xn_gc_safepoint();
    #line 1215 "impl/lib/b2/xparser.x"
        if ((xn_Cls_Parser_at(self, 10))) {
            size_t xn_t2356 = xn_root_mark();
            #line 1216 "impl/lib/b2/xparser.x"
            xn_Cls_Parser_next(self);
            #line 1217 "impl/lib/b2/xparser.x"
                while ((((!(xn_Cls_Parser_at(self, 11)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                size_t xn_t2357 = xn_root_mark();
                #line 1218 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 16))) {
                        size_t xn_t2358 = xn_root_mark();
                        #line 1218 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                        #line 1218 "impl/lib/b2/xparser.x"
                        xn_root_restore(xn_t2358);
                        xn_root_restore(xn_t2357);
                        continue;
                            {
                            xn_root_restore(xn_t2358);
                            }

                    }
                #line 1219 "impl/lib/b2/xparser.x"
                xn_Cls_E * xn_t2359 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t2359);
    xn_root_add(xn_t2359);
            xn_root_add(xn_t2359);
                xn_root_add(xn_t2359);
                rt_string *xn_t2360 = rt_retain(xn_t2359->d);
xn_root_add(xn_t2360);
    xn_root_add(xn_t2360);
            xn_root_add(xn_t2360);
                xn_root_add(xn_t2360);
                xn_arr_s_push(args, xn_t2360);
                    {
                    xn_root_restore(xn_t2357);
                    }

                xn_gc_safepoint();
                }
            #line 1221 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 11))) {
                    size_t xn_t2361 = xn_root_mark();
                    #line 1221 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t2361);
                        }

                }
                {
                xn_root_restore(xn_t2356);
                }

        }
    #line 1223 "impl/lib/b2/xparser.x"
    rt_string *xn_t2362 = rt_string_from_c("(AnnotationNode ");
xn_root_add(xn_t2362);
    xn_root_add(xn_t2362);
    rt_string *xn_t2363 = xn_P(t->line, t->col);
xn_root_add(xn_t2363);
    xn_root_add(xn_t2363);
    rt_string *xn_t2364 = xn_concat(xn_t2362, xn_t2363);
xn_root_add(xn_t2364);
    xn_root_add(xn_t2364);
    rt_string *xn_t2365 = rt_string_from_c(" (Name ");
xn_root_add(xn_t2365);
    xn_root_add(xn_t2365);
    rt_string *xn_t2366 = xn_concat(xn_t2364, xn_t2365);
xn_root_add(xn_t2366);
    xn_root_add(xn_t2366);
    rt_string *xn_t2367 = rt_retain(t->text);
xn_root_add(xn_t2367);
    xn_root_add(xn_t2367);
    rt_string *xn_t2368 = xn_q(xn_t2367);
xn_root_add(xn_t2368);
    xn_root_add(xn_t2368);
    rt_string *xn_t2369 = xn_concat(xn_t2366, xn_t2368);
xn_root_add(xn_t2369);
    xn_root_add(xn_t2369);
    rt_string *xn_t2370 = rt_string_from_c(") (Args ");
xn_root_add(xn_t2370);
    xn_root_add(xn_t2370);
    rt_string *xn_t2371 = xn_concat(xn_t2369, xn_t2370);
xn_root_add(xn_t2371);
    xn_root_add(xn_t2371);
    rt_string *xn_t2372 = xn_SL(args);
xn_root_add(xn_t2372);
    xn_root_add(xn_t2372);
    rt_string *xn_t2373 = xn_concat(xn_t2371, xn_t2372);
xn_root_add(xn_t2373);
    xn_root_add(xn_t2373);
    rt_string *xn_t2374 = rt_string_from_c("))");
xn_root_add(xn_t2374);
    xn_root_add(xn_t2374);
    rt_string *xn_t2375 = xn_concat(xn_t2373, xn_t2374);
xn_root_add(xn_t2375);
    xn_root_add(xn_t2375);
    xn_arr_s_push(res, xn_t2375);
    #line 1224 "impl/lib/b2/xparser.x"
        if ((xn_Cls_Parser_at(self, 1))) {
            size_t xn_t2376 = xn_root_mark();
            #line 1224 "impl/lib/b2/xparser.x"
            xn_Cls_Parser_next(self);
                {
                xn_root_restore(xn_t2376);
                }

        }
        {
        xn_root_restore(xn_t2354);
        }

    xn_gc_safepoint();
    }
#line 1226 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t2352);
    }

return res;
    return (xn_arr_s *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_M * xn_Cls_Parser_parseMods(xn_Cls_Parser *self) {
size_t xn_t2377 = xn_root_mark();
xn_root_add(self);
#line 1230 "impl/lib/b2/xparser.x"
xn_Cls_M * m = xn_Cls_M_new();
xn_root_add(m);
xn_root_add(m);
xn_gc_safepoint();
#line 1231 "impl/lib/b2/xparser.x"
    while (1) {
    size_t xn_t2378 = xn_root_mark();
    #line 1232 "impl/lib/b2/xparser.x"
    rt_string *xn_t2379 = rt_string_from_c("public");
xn_root_add(xn_t2379);
    xn_root_add(xn_t2379);
        if ((xn_Cls_Parser_atKw(self, xn_t2379))) {
            size_t xn_t2380 = xn_root_mark();
            #line 1232 "impl/lib/b2/xparser.x"
            rt_string *xn_t2381 = rt_string_from_c("public");
xn_root_add(xn_t2381);
    xn_root_add(xn_t2381);
            xn_root_add(xn_t2381);
            rt_release(m->vis);
            m->vis = xn_t2381;
            #line 1232 "impl/lib/b2/xparser.x"
            xn_Cls_Parser_next(self);
                {
                xn_root_restore(xn_t2380);
                }

        } else {
            rt_string *xn_t2383 = rt_string_from_c("protected");
xn_root_add(xn_t2383);
    xn_root_add(xn_t2383);
            xn_root_add(xn_t2383);
                if ((xn_Cls_Parser_atKw(self, xn_t2383))) {
                    size_t xn_t2384 = xn_root_mark();
                    #line 1233 "impl/lib/b2/xparser.x"
                    rt_string *xn_t2385 = rt_string_from_c("protected");
xn_root_add(xn_t2385);
    xn_root_add(xn_t2385);
            xn_root_add(xn_t2385);
                    xn_root_add(xn_t2385);
                    rt_release(m->vis);
                    m->vis = xn_t2385;
                    #line 1233 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t2384);
                        }

                } else {
                    rt_string *xn_t2387 = rt_string_from_c("private");
xn_root_add(xn_t2387);
    xn_root_add(xn_t2387);
            xn_root_add(xn_t2387);
                    xn_root_add(xn_t2387);
                        if ((xn_Cls_Parser_atKw(self, xn_t2387))) {
                            size_t xn_t2388 = xn_root_mark();
                            #line 1234 "impl/lib/b2/xparser.x"
                            rt_string *xn_t2389 = rt_string_from_c("private");
xn_root_add(xn_t2389);
    xn_root_add(xn_t2389);
            xn_root_add(xn_t2389);
                    xn_root_add(xn_t2389);
                            xn_root_add(xn_t2389);
                            rt_release(m->vis);
                            m->vis = xn_t2389;
                            #line 1234 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                                {
                                xn_root_restore(xn_t2388);
                                }

                        } else {
                            rt_string *xn_t2391 = rt_string_from_c("abstract");
xn_root_add(xn_t2391);
    xn_root_add(xn_t2391);
            xn_root_add(xn_t2391);
                    xn_root_add(xn_t2391);
                            xn_root_add(xn_t2391);
                                if ((xn_Cls_Parser_atKw(self, xn_t2391))) {
                                    size_t xn_t2392 = xn_root_mark();
                                    #line 1235 "impl/lib/b2/xparser.x"
                                    m->abs = (int64_t)((int)(1));
                                    #line 1235 "impl/lib/b2/xparser.x"
                                    xn_Cls_Parser_next(self);
                                        {
                                        xn_root_restore(xn_t2392);
                                        }

                                } else {
                                    rt_string *xn_t2394 = rt_string_from_c("final");
xn_root_add(xn_t2394);
    xn_root_add(xn_t2394);
            xn_root_add(xn_t2394);
                    xn_root_add(xn_t2394);
                            xn_root_add(xn_t2394);
                                    xn_root_add(xn_t2394);
                                        if ((xn_Cls_Parser_atKw(self, xn_t2394))) {
                                            size_t xn_t2395 = xn_root_mark();
                                            #line 1236 "impl/lib/b2/xparser.x"
                                            m->fin = (int64_t)((int)(1));
                                            #line 1236 "impl/lib/b2/xparser.x"
                                            xn_Cls_Parser_next(self);
                                                {
                                                xn_root_restore(xn_t2395);
                                                }

                                        } else {
                                            rt_string *xn_t2397 = rt_string_from_c("static");
xn_root_add(xn_t2397);
    xn_root_add(xn_t2397);
            xn_root_add(xn_t2397);
                    xn_root_add(xn_t2397);
                            xn_root_add(xn_t2397);
                                    xn_root_add(xn_t2397);
                                            xn_root_add(xn_t2397);
                                                if ((xn_Cls_Parser_atKw(self, xn_t2397))) {
                                                    size_t xn_t2398 = xn_root_mark();
                                                    #line 1237 "impl/lib/b2/xparser.x"
                                                    m->stat = (int64_t)((int)(1));
                                                    #line 1237 "impl/lib/b2/xparser.x"
                                                    xn_Cls_Parser_next(self);
                                                        {
                                                        xn_root_restore(xn_t2398);
                                                        }

                                                } else {
                                                    rt_string *xn_t2400 = rt_string_from_c("const");
xn_root_add(xn_t2400);
    xn_root_add(xn_t2400);
            xn_root_add(xn_t2400);
                    xn_root_add(xn_t2400);
                            xn_root_add(xn_t2400);
                                    xn_root_add(xn_t2400);
                                            xn_root_add(xn_t2400);
                                                    xn_root_add(xn_t2400);
                                                        if ((xn_Cls_Parser_atKw(self, xn_t2400))) {
                                                            size_t xn_t2401 = xn_root_mark();
                                                            #line 1238 "impl/lib/b2/xparser.x"
                                                            m->cons = (int64_t)((int)(1));
                                                            #line 1238 "impl/lib/b2/xparser.x"
                                                            xn_Cls_Parser_next(self);
                                                                {
                                                                xn_root_restore(xn_t2401);
                                                                }

                                                        } else {
                                                            size_t xn_t2402 = xn_root_mark();
                                                            #line 1239 "impl/lib/b2/xparser.x"
                                                            xn_root_restore(xn_t2402);
                                                            xn_root_restore(xn_t2378);
                                                            break;
                                                                {
                                                                xn_root_restore(xn_t2402);
                                                                }

                                                        }
                                                }
                                        }
                                }
                        }
                }
        }
        {
        xn_root_restore(xn_t2378);
        }

    xn_gc_safepoint();
    }
#line 1241 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t2377);
    }

return m;
    return (xn_Cls_M *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_retv(xn_Cls_Parser *self, int xn_p_vd, rt_string * xn_p_rt) {
size_t xn_t2403 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_rt);
#line 1245 "impl/lib/b2/xparser.x"
    if ((xn_p_vd)) {
        size_t xn_t2404 = xn_root_mark();
        #line 1245 "impl/lib/b2/xparser.x"
        rt_string *xn_t2405 = rt_string_from_c("(nil)");
xn_root_add(xn_t2405);
        xn_root_add(xn_t2405);
        xn_root_add(xn_t2405);
            {
        xn_root_restore(xn_t2404);
            }
            {
        xn_root_restore(xn_t2403);
            }

        return xn_t2405;

    }
#line 1246 "impl/lib/b2/xparser.x"
rt_string *xn_t2406 = rt_retain(xn_p_rt);
xn_root_add(xn_t2406);
rt_string *xn_t2407 = rt_string_from_c("");
xn_root_add(xn_t2407);
    if ((xn_str_eq(xn_t2406, xn_t2407))) {
        size_t xn_t2408 = xn_root_mark();
        #line 1246 "impl/lib/b2/xparser.x"
        rt_string *xn_t2409 = rt_string_from_c("(nil)");
xn_root_add(xn_t2409);
        xn_root_add(xn_t2409);
        xn_root_add(xn_t2409);
            {
        xn_root_restore(xn_t2408);
            }
            {
        xn_root_restore(xn_t2403);
            }

        return xn_t2409;

    }
#line 1247 "impl/lib/b2/xparser.x"
rt_retain(xn_p_rt);
    {
xn_root_restore(xn_t2403);
    }

return xn_p_rt;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_modDump(xn_Cls_Parser *self, xn_Cls_M * xn_p_m) {
size_t xn_t2410 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_m);
#line 1251 "impl/lib/b2/xparser.x"
rt_string *xn_t2411 = rt_string_from_c("(TypeModifiers (Vis ");
xn_root_add(xn_t2411);
xn_root_add(xn_t2411);
rt_string *xn_t2412 = rt_retain(xn_p_m->vis);
xn_root_add(xn_t2412);
xn_root_add(xn_t2412);
rt_string *xn_t2413 = xn_q(xn_t2412);
xn_root_add(xn_t2413);
xn_root_add(xn_t2413);
rt_string *xn_t2414 = xn_concat(xn_t2411, xn_t2413);
xn_root_add(xn_t2414);
xn_root_add(xn_t2414);
rt_string *xn_t2415 = rt_string_from_c(") (Abstract ");
xn_root_add(xn_t2415);
xn_root_add(xn_t2415);
rt_string *xn_t2416 = xn_concat(xn_t2414, xn_t2415);
xn_root_add(xn_t2416);
xn_root_add(xn_t2416);
rt_string *xn_t2417 = xn_B(((int)(xn_p_m->abs)));
xn_root_add(xn_t2417);
xn_root_add(xn_t2417);
rt_string *xn_t2418 = xn_concat(xn_t2416, xn_t2417);
xn_root_add(xn_t2418);
xn_root_add(xn_t2418);
rt_string *xn_t2419 = rt_string_from_c(") (Final ");
xn_root_add(xn_t2419);
xn_root_add(xn_t2419);
rt_string *xn_t2420 = xn_concat(xn_t2418, xn_t2419);
xn_root_add(xn_t2420);
xn_root_add(xn_t2420);
rt_string *xn_t2421 = xn_B(((int)(xn_p_m->fin)));
xn_root_add(xn_t2421);
xn_root_add(xn_t2421);
rt_string *xn_t2422 = xn_concat(xn_t2420, xn_t2421);
xn_root_add(xn_t2422);
xn_root_add(xn_t2422);
rt_string *xn_t2423 = rt_string_from_c(") (Static ");
xn_root_add(xn_t2423);
xn_root_add(xn_t2423);
rt_string *xn_t2424 = xn_concat(xn_t2422, xn_t2423);
xn_root_add(xn_t2424);
xn_root_add(xn_t2424);
rt_string *xn_t2425 = xn_B(((int)(xn_p_m->stat)));
xn_root_add(xn_t2425);
xn_root_add(xn_t2425);
rt_string *xn_t2426 = xn_concat(xn_t2424, xn_t2425);
xn_root_add(xn_t2426);
xn_root_add(xn_t2426);
rt_string *xn_t2427 = rt_string_from_c(") (Const ");
xn_root_add(xn_t2427);
xn_root_add(xn_t2427);
rt_string *xn_t2428 = xn_concat(xn_t2426, xn_t2427);
xn_root_add(xn_t2428);
xn_root_add(xn_t2428);
rt_string *xn_t2429 = xn_B(((int)(xn_p_m->cons)));
xn_root_add(xn_t2429);
xn_root_add(xn_t2429);
rt_string *xn_t2430 = xn_concat(xn_t2428, xn_t2429);
xn_root_add(xn_t2430);
xn_root_add(xn_t2430);
rt_string *xn_t2431 = rt_string_from_c("))");
xn_root_add(xn_t2431);
xn_root_add(xn_t2431);
rt_string *xn_t2432 = xn_concat(xn_t2430, xn_t2431);
xn_root_add(xn_t2432);
xn_root_add(xn_t2432);
    {
xn_root_restore(xn_t2410);
    }

return xn_t2432;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_arr_s * xn_Cls_Parser_parseParams(xn_Cls_Parser *self) {
size_t xn_t2433 = xn_root_mark();
xn_root_add(self);
#line 1256 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2434 = xn_arr_s_new(0);
xn_root_add(xn_t2434);
xn_arr_s * ps = xn_t2434;
xn_root_add(ps);
xn_root_add(ps);
xn_gc_safepoint();
#line 1257 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 10))) {
        size_t xn_t2435 = xn_root_mark();
        #line 1258 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1259 "impl/lib/b2/xparser.x"
            while ((((!(xn_Cls_Parser_at(self, 11)))) && ((!(xn_Cls_Parser_eof(self)))))) {
            size_t xn_t2436 = xn_root_mark();
            #line 1260 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 16))) {
                    size_t xn_t2437 = xn_root_mark();
                    #line 1260 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 1260 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t2437);
                    xn_root_restore(xn_t2436);
                    continue;
                        {
                        xn_root_restore(xn_t2437);
                        }

                }
            #line 1261 "impl/lib/b2/xparser.x"
            rt_string *xn_t2438 = xn_Cls_Parser_parseParam(self);
xn_root_add(xn_t2438);
        xn_root_add(xn_t2438);
            xn_root_add(xn_t2438);
            xn_arr_s_push(ps, xn_t2438);
                {
                xn_root_restore(xn_t2436);
                }

            xn_gc_safepoint();
            }
        #line 1263 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 11))) {
                size_t xn_t2439 = xn_root_mark();
                #line 1263 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t2439);
                    }

            }
            {
            xn_root_restore(xn_t2435);
            }

    }
#line 1265 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t2433);
    }

return ps;
    return (xn_arr_s *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseTypeDecl(xn_Cls_Parser *self, rt_string * xn_p_kw, int64_t xn_p_sl, int64_t xn_p_sc, xn_arr_s * xn_p_annos, xn_Cls_M * xn_p_m) {
size_t xn_t2440 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_kw);
xn_root_add(xn_p_annos);
xn_root_add(xn_p_m);
#line 1269 "impl/lib/b2/xparser.x"
rt_string *name = rt_string_from_c("");
xn_root_add(name);
xn_root_add(name);
xn_gc_safepoint();
#line 1270 "impl/lib/b2/xparser.x"
int64_t nl = xn_p_sl;
#line 1271 "impl/lib/b2/xparser.x"
int64_t nc = xn_p_sc;
#line 1272 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 2))) {
        size_t xn_t2442 = xn_root_mark();
        #line 1272 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * nt = xn_Cls_Parser_next(self);
xn_root_add(nt);
        xn_root_add(nt);
        xn_root_add(nt);
        xn_gc_safepoint();
        #line 1272 "impl/lib/b2/xparser.x"
        rt_string *xn_t2443 = rt_retain(nt->text);
xn_root_add(xn_t2443);
        xn_root_add(xn_t2443);
        xn_root_release(name);
        rt_release(name);
        name = xn_t2443;
        xn_root_hold(name);
        xn_gc_safepoint();
        #line 1272 "impl/lib/b2/xparser.x"
        nl = nt->line;
        #line 1272 "impl/lib/b2/xparser.x"
        nc = nt->col;
            {
            xn_root_restore(xn_t2442);
            }

    }
#line 1273 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2444 = xn_arr_s_new(0);
xn_root_add(xn_t2444);
xn_arr_s * tps = xn_t2444;
xn_root_add(tps);
xn_root_add(tps);
xn_gc_safepoint();
#line 1274 "impl/lib/b2/xparser.x"
rt_string *xn_t2445 = rt_string_from_c("<");
xn_root_add(xn_t2445);
    if ((xn_Cls_Parser_atOp(self, xn_t2445))) {
        size_t xn_t2446 = xn_root_mark();
        #line 1275 "impl/lib/b2/xparser.x"
        rt_string *xn_t2447 = rt_retain(xn_p_kw);
xn_root_add(xn_t2447);
        xn_root_add(xn_t2447);
        rt_string *xn_t2448 = rt_string_from_c("protocol");
xn_root_add(xn_t2448);
        xn_root_add(xn_t2448);
            if ((xn_str_eq(xn_t2447, xn_t2448))) {
                size_t xn_t2449 = xn_root_mark();
                #line 1276 "impl/lib/b2/xparser.x"
                rt_string *xn_t2450 = rt_string_from_c("SYN-101");
xn_root_add(xn_t2450);
        xn_root_add(xn_t2450);
                xn_root_add(xn_t2450);
                xn_Cls_Tok * xn_t2451 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2451);
        xn_root_add(xn_t2451);
                xn_root_add(xn_t2451);
                xn_Cls_Tok * xn_t2452 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2452);
        xn_root_add(xn_t2452);
                xn_root_add(xn_t2452);
                rt_string *xn_t2453 = rt_string_from_c("协议不支持类型参数");
xn_root_add(xn_t2453);
        xn_root_add(xn_t2453);
                xn_root_add(xn_t2453);
                xn_Cls_Parser_err(self, xn_t2450, xn_t2451->line, xn_t2452->col, xn_t2453);
                    {
                    xn_root_restore(xn_t2449);
                    }

            }
        #line 1278 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1279 "impl/lib/b2/xparser.x"
            while (1) {
                rt_string *xn_t2454 = rt_string_from_c(">");
xn_root_add(xn_t2454);
        xn_root_add(xn_t2454);
                if (!((((!(xn_Cls_Parser_atOp(self, xn_t2454)))) && ((!(xn_Cls_Parser_eof(self))))))) { break; }
                size_t xn_t2455 = xn_root_mark();
                #line 1280 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 2))) {
                        size_t xn_t2456 = xn_root_mark();
                        #line 1280 "impl/lib/b2/xparser.x"
                        xn_Cls_Tok * xn_t2457 = xn_Cls_Parser_next(self);
xn_root_add(xn_t2457);
        xn_root_add(xn_t2457);
                xn_root_add(xn_t2457);
                        xn_root_add(xn_t2457);
                        rt_string *xn_t2458 = rt_retain(xn_t2457->text);
xn_root_add(xn_t2458);
        xn_root_add(xn_t2458);
                xn_root_add(xn_t2458);
                        xn_root_add(xn_t2458);
                        xn_arr_s_push(tps, xn_t2458);
                            {
                            xn_root_restore(xn_t2456);
                            }

                    } else {
                        size_t xn_t2459 = xn_root_mark();
                        #line 1280 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t2459);
                            }

                    }
                    {
                    xn_root_restore(xn_t2455);
                    }

                xn_gc_safepoint();
            }
        #line 1282 "impl/lib/b2/xparser.x"
        rt_string *xn_t2460 = rt_string_from_c(">");
xn_root_add(xn_t2460);
        xn_root_add(xn_t2460);
            if ((xn_Cls_Parser_atOp(self, xn_t2460))) {
                size_t xn_t2461 = xn_root_mark();
                #line 1282 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t2461);
                    }

            }
            {
            xn_root_restore(xn_t2446);
            }

    }
#line 1284 "impl/lib/b2/xparser.x"
rt_string *primary = rt_string_from_c("(nil)");
xn_root_add(primary);
xn_root_add(primary);
xn_gc_safepoint();
#line 1285 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 10))) {
        size_t xn_t2463 = xn_root_mark();
        #line 1287 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t2464 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2464);
        xn_root_add(xn_t2464);
        int64_t pl = xn_t2464->line;
        #line 1288 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t2465 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2465);
        xn_root_add(xn_t2465);
        int64_t pc = xn_t2465->col;
        #line 1289 "impl/lib/b2/xparser.x"
        xn_arr_s * pps = xn_Cls_Parser_parseParams(self);
xn_root_add(pps);
        xn_root_add(pps);
        xn_root_add(pps);
        xn_gc_safepoint();
        #line 1290 "impl/lib/b2/xparser.x"
        rt_string *xn_t2466 = rt_string_from_c("(CtorDecl ");
xn_root_add(xn_t2466);
        xn_root_add(xn_t2466);
        rt_string *xn_t2467 = xn_P(pl, pc);
xn_root_add(xn_t2467);
        xn_root_add(xn_t2467);
        rt_string *xn_t2468 = xn_concat(xn_t2466, xn_t2467);
xn_root_add(xn_t2468);
        xn_root_add(xn_t2468);
        rt_string *xn_t2469 = rt_string_from_c(" (Annos (slice)) (Mod (TypeModifiers (Vis \"\") (Abstract false) (Final false) (Static false) (Const false))) (Params ");
xn_root_add(xn_t2469);
        xn_root_add(xn_t2469);
        rt_string *xn_t2470 = xn_concat(xn_t2468, xn_t2469);
xn_root_add(xn_t2470);
        xn_root_add(xn_t2470);
        rt_string *xn_t2471 = xn_SL(pps);
xn_root_add(xn_t2471);
        xn_root_add(xn_t2471);
        rt_string *xn_t2472 = xn_concat(xn_t2470, xn_t2471);
xn_root_add(xn_t2472);
        xn_root_add(xn_t2472);
        rt_string *xn_t2473 = rt_string_from_c(") (Body (nil)))");
xn_root_add(xn_t2473);
        xn_root_add(xn_t2473);
        rt_string *xn_t2474 = xn_concat(xn_t2472, xn_t2473);
xn_root_add(xn_t2474);
        xn_root_add(xn_t2474);
        xn_root_release(primary);
        rt_release(primary);
        primary = xn_t2474;
        xn_root_hold(primary);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t2463);
            }

    }
#line 1292 "impl/lib/b2/xparser.x"
rt_string *base = rt_string_from_c("(nil)");
xn_root_add(base);
xn_root_add(base);
xn_gc_safepoint();
#line 1293 "impl/lib/b2/xparser.x"
rt_string *xn_t2476 = rt_string_from_c(":");
xn_root_add(xn_t2476);
    if ((xn_Cls_Parser_atOp(self, xn_t2476))) {
        size_t xn_t2477 = xn_root_mark();
        #line 1293 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1293 "impl/lib/b2/xparser.x"
        rt_string *xn_t2478 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t2478);
        xn_root_add(xn_t2478);
        xn_root_release(base);
        rt_release(base);
        base = xn_t2478;
        xn_root_hold(base);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t2477);
            }

    }
#line 1294 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2479 = xn_arr_s_new(0);
xn_root_add(xn_t2479);
xn_arr_s * protos = xn_t2479;
xn_root_add(protos);
xn_root_add(protos);
xn_gc_safepoint();
#line 1295 "impl/lib/b2/xparser.x"
rt_string *xn_t2480 = rt_string_from_c("implements");
xn_root_add(xn_t2480);
    if ((xn_Cls_Parser_atKw(self, xn_t2480))) {
        size_t xn_t2481 = xn_root_mark();
        #line 1296 "impl/lib/b2/xparser.x"
        rt_string *xn_t2482 = rt_retain(xn_p_kw);
xn_root_add(xn_t2482);
        xn_root_add(xn_t2482);
        rt_string *xn_t2483 = rt_string_from_c("enum");
xn_root_add(xn_t2483);
        xn_root_add(xn_t2483);
            if ((xn_str_eq(xn_t2482, xn_t2483))) {
                size_t xn_t2484 = xn_root_mark();
                #line 1297 "impl/lib/b2/xparser.x"
                rt_string *xn_t2485 = rt_string_from_c("SYN-101");
xn_root_add(xn_t2485);
        xn_root_add(xn_t2485);
                xn_root_add(xn_t2485);
                xn_Cls_Tok * xn_t2486 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2486);
        xn_root_add(xn_t2486);
                xn_root_add(xn_t2486);
                xn_Cls_Tok * xn_t2487 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2487);
        xn_root_add(xn_t2487);
                xn_root_add(xn_t2487);
                rt_string *xn_t2488 = rt_string_from_c("enum 不支持 implements");
xn_root_add(xn_t2488);
        xn_root_add(xn_t2488);
                xn_root_add(xn_t2488);
                xn_Cls_Parser_err(self, xn_t2485, xn_t2486->line, xn_t2487->col, xn_t2488);
                    {
                    xn_root_restore(xn_t2484);
                    }

            }
        #line 1299 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1300 "impl/lib/b2/xparser.x"
            while ((xn_Cls_Parser_at(self, 2))) {
            size_t xn_t2489 = xn_root_mark();
            #line 1300 "impl/lib/b2/xparser.x"
            rt_string *xn_t2490 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t2490);
        xn_root_add(xn_t2490);
            xn_root_add(xn_t2490);
            xn_arr_s_push(protos, xn_t2490);
            #line 1300 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 16))) {
                    size_t xn_t2491 = xn_root_mark();
                    #line 1300 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t2491);
                        }

                } else {
                    size_t xn_t2492 = xn_root_mark();
                    #line 1300 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t2492);
                    xn_root_restore(xn_t2489);
                    break;
                        {
                        xn_root_restore(xn_t2492);
                        }

                }
                {
                xn_root_restore(xn_t2489);
                }

            xn_gc_safepoint();
            }
            {
            xn_root_restore(xn_t2481);
            }

    }
#line 1302 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 12))) {
        size_t xn_t2493 = xn_root_mark();
        #line 1302 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t2493);
            }

    }
#line 1303 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2494 = xn_arr_s_new(0);
xn_root_add(xn_t2494);
xn_arr_s * fields = xn_t2494;
xn_root_add(fields);
xn_root_add(fields);
xn_gc_safepoint();
#line 1304 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2495 = xn_arr_s_new(0);
xn_root_add(xn_t2495);
xn_arr_s * methods = xn_t2495;
xn_root_add(methods);
xn_root_add(methods);
xn_gc_safepoint();
#line 1305 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2496 = xn_arr_s_new(0);
xn_root_add(xn_t2496);
xn_arr_s * ctors = xn_t2496;
xn_root_add(ctors);
xn_root_add(ctors);
xn_gc_safepoint();
#line 1306 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2497 = xn_arr_s_new(0);
xn_root_add(xn_t2497);
xn_arr_s * items = xn_t2497;
xn_root_add(items);
xn_root_add(items);
xn_gc_safepoint();
#line 1307 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2498 = xn_arr_s_new(0);
xn_root_add(xn_t2498);
xn_arr_s * sigs = xn_t2498;
xn_root_add(sigs);
xn_root_add(sigs);
xn_gc_safepoint();
#line 1308 "impl/lib/b2/xparser.x"
rt_string *xn_t2499 = rt_retain(xn_p_kw);
xn_root_add(xn_t2499);
rt_string *xn_t2500 = rt_string_from_c("protocol");
xn_root_add(xn_t2500);
    if ((xn_str_eq(xn_t2499, xn_t2500))) {
        size_t xn_t2501 = xn_root_mark();
        #line 1309 "impl/lib/b2/xparser.x"
            while ((((!(xn_Cls_Parser_at(self, 13)))) && ((!(xn_Cls_Parser_eof(self)))))) {
            size_t xn_t2502 = xn_root_mark();
            #line 1310 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 1))) {
                    size_t xn_t2503 = xn_root_mark();
                    #line 1310 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 1310 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t2503);
                    xn_root_restore(xn_t2502);
                    continue;
                        {
                        xn_root_restore(xn_t2503);
                        }

                }
            #line 1311 "impl/lib/b2/xparser.x"
            rt_string *ms = xn_Cls_Parser_parseModsDump(self);
xn_root_add(ms);
        xn_root_add(ms);
            xn_root_add(ms);
            xn_root_add(ms);
            xn_gc_safepoint();
            #line 1312 "impl/lib/b2/xparser.x"
            int vd = 0;
            #line 1313 "impl/lib/b2/xparser.x"
            rt_string *rt = rt_string_from_c("");
xn_root_add(rt);
        xn_root_add(rt);
            xn_root_add(rt);
            xn_root_add(rt);
            xn_gc_safepoint();
            #line 1314 "impl/lib/b2/xparser.x"
            xn_Cls_Tok * xn_t2506 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2506);
        xn_root_add(xn_t2506);
            xn_root_add(xn_t2506);
            rt_string *xn_t2507 = rt_retain(xn_t2506->text);
xn_root_add(xn_t2507);
        xn_root_add(xn_t2507);
            xn_root_add(xn_t2507);
            rt_string *xn_t2508 = rt_string_from_c("void");
xn_root_add(xn_t2508);
        xn_root_add(xn_t2508);
            xn_root_add(xn_t2508);
                if (((xn_Cls_Parser_at(self, 2)) && (xn_str_eq(xn_t2507, xn_t2508)))) {
                    size_t xn_t2509 = xn_root_mark();
                    #line 1314 "impl/lib/b2/xparser.x"
                    vd = 1;
                    #line 1314 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t2509);
                        }

                } else {
                    size_t xn_t2510 = xn_root_mark();
                    #line 1314 "impl/lib/b2/xparser.x"
                    rt_string *xn_t2511 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t2511);
        xn_root_add(xn_t2511);
            xn_root_add(xn_t2511);
                    xn_root_add(xn_t2511);
                    xn_root_release(rt);
                    rt_release(rt);
                    rt = xn_t2511;
                    xn_root_hold(rt);
                    xn_gc_safepoint();
                        {
                        xn_root_restore(xn_t2510);
                        }

                }
            #line 1315 "impl/lib/b2/xparser.x"
            rt_string *mn = rt_string_from_c("");
xn_root_add(mn);
        xn_root_add(mn);
            xn_root_add(mn);
            xn_root_add(mn);
            xn_gc_safepoint();
            #line 1316 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 2))) {
                    size_t xn_t2513 = xn_root_mark();
                    #line 1316 "impl/lib/b2/xparser.x"
                    xn_Cls_Tok * xn_t2514 = xn_Cls_Parser_next(self);
xn_root_add(xn_t2514);
        xn_root_add(xn_t2514);
            xn_root_add(xn_t2514);
                    xn_root_add(xn_t2514);
                    rt_string *xn_t2515 = rt_retain(xn_t2514->text);
xn_root_add(xn_t2515);
        xn_root_add(xn_t2515);
            xn_root_add(xn_t2515);
                    xn_root_add(xn_t2515);
                    xn_root_release(mn);
                    rt_release(mn);
                    mn = xn_t2515;
                    xn_root_hold(mn);
                    xn_gc_safepoint();
                        {
                        xn_root_restore(xn_t2513);
                        }

                }
            #line 1317 "impl/lib/b2/xparser.x"
            int hadParen = xn_Cls_Parser_at(self, 10);
            #line 1318 "impl/lib/b2/xparser.x"
            xn_arr_s * ps = xn_Cls_Parser_parseParams(self);
xn_root_add(ps);
        xn_root_add(ps);
            xn_root_add(ps);
            xn_root_add(ps);
            xn_gc_safepoint();
            #line 1319 "impl/lib/b2/xparser.x"
                if (((!(hadParen)))) {
                    size_t xn_t2516 = xn_root_mark();
                    #line 1320 "impl/lib/b2/xparser.x"
                    rt_string *xn_t2517 = rt_string_from_c("SYN-101");
xn_root_add(xn_t2517);
        xn_root_add(xn_t2517);
            xn_root_add(xn_t2517);
                    xn_root_add(xn_t2517);
                    xn_Cls_Tok * xn_t2518 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2518);
        xn_root_add(xn_t2518);
            xn_root_add(xn_t2518);
                    xn_root_add(xn_t2518);
                    xn_Cls_Tok * xn_t2519 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2519);
        xn_root_add(xn_t2519);
            xn_root_add(xn_t2519);
                    xn_root_add(xn_t2519);
                    rt_string *xn_t2520 = rt_string_from_c("协议不能声明字段（缺少 `()`）");
xn_root_add(xn_t2520);
        xn_root_add(xn_t2520);
            xn_root_add(xn_t2520);
                    xn_root_add(xn_t2520);
                    xn_Cls_Parser_err(self, xn_t2517, xn_t2518->line, xn_t2519->col, xn_t2520);
                        {
                        xn_root_restore(xn_t2516);
                        }

                }
            #line 1322 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 1))) {
                    size_t xn_t2521 = xn_root_mark();
                    #line 1322 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t2521);
                        }

                }
            #line 1323 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 12))) {
                    size_t xn_t2522 = xn_root_mark();
                    #line 1324 "impl/lib/b2/xparser.x"
                    rt_string *xn_t2523 = rt_string_from_c("SYN-101");
xn_root_add(xn_t2523);
        xn_root_add(xn_t2523);
            xn_root_add(xn_t2523);
                    xn_root_add(xn_t2523);
                    xn_Cls_Tok * xn_t2524 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2524);
        xn_root_add(xn_t2524);
            xn_root_add(xn_t2524);
                    xn_root_add(xn_t2524);
                    xn_Cls_Tok * xn_t2525 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2525);
        xn_root_add(xn_t2525);
            xn_root_add(xn_t2525);
                    xn_root_add(xn_t2525);
                    rt_string *xn_t2526 = rt_string_from_c("协议方法不能有函数体");
xn_root_add(xn_t2526);
        xn_root_add(xn_t2526);
            xn_root_add(xn_t2526);
                    xn_root_add(xn_t2526);
                    xn_Cls_Parser_err(self, xn_t2523, xn_t2524->line, xn_t2525->col, xn_t2526);
                    #line 1325 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_parseBlock(self);
                        {
                        xn_root_restore(xn_t2522);
                        }

                }
            #line 1327 "impl/lib/b2/xparser.x"
            rt_string *xn_t2527 = rt_string_from_c("(ProtocolSig ");
xn_root_add(xn_t2527);
        xn_root_add(xn_t2527);
            xn_root_add(xn_t2527);
            rt_string *xn_t2528 = xn_P(xn_p_sl, xn_p_sc);
xn_root_add(xn_t2528);
        xn_root_add(xn_t2528);
            xn_root_add(xn_t2528);
            rt_string *xn_t2529 = xn_concat(xn_t2527, xn_t2528);
xn_root_add(xn_t2529);
        xn_root_add(xn_t2529);
            xn_root_add(xn_t2529);
            rt_string *xn_t2530 = rt_string_from_c(" (Annos (slice)) (Mod ");
xn_root_add(xn_t2530);
        xn_root_add(xn_t2530);
            xn_root_add(xn_t2530);
            rt_string *xn_t2531 = xn_concat(xn_t2529, xn_t2530);
xn_root_add(xn_t2531);
        xn_root_add(xn_t2531);
            xn_root_add(xn_t2531);
            rt_string *xn_t2532 = rt_retain(ms);
xn_root_add(xn_t2532);
        xn_root_add(xn_t2532);
            xn_root_add(xn_t2532);
            rt_string *xn_t2533 = xn_concat(xn_t2531, xn_t2532);
xn_root_add(xn_t2533);
        xn_root_add(xn_t2533);
            xn_root_add(xn_t2533);
            rt_string *xn_t2534 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2534);
        xn_root_add(xn_t2534);
            xn_root_add(xn_t2534);
            rt_string *xn_t2535 = xn_concat(xn_t2533, xn_t2534);
xn_root_add(xn_t2535);
        xn_root_add(xn_t2535);
            xn_root_add(xn_t2535);
            rt_string *xn_t2536 = rt_retain(mn);
xn_root_add(xn_t2536);
        xn_root_add(xn_t2536);
            xn_root_add(xn_t2536);
            rt_string *xn_t2537 = xn_q(xn_t2536);
xn_root_add(xn_t2537);
        xn_root_add(xn_t2537);
            xn_root_add(xn_t2537);
            rt_string *xn_t2538 = xn_concat(xn_t2535, xn_t2537);
xn_root_add(xn_t2538);
        xn_root_add(xn_t2538);
            xn_root_add(xn_t2538);
            rt_string *xn_t2539 = rt_string_from_c(") (Void ");
xn_root_add(xn_t2539);
        xn_root_add(xn_t2539);
            xn_root_add(xn_t2539);
            rt_string *xn_t2540 = xn_concat(xn_t2538, xn_t2539);
xn_root_add(xn_t2540);
        xn_root_add(xn_t2540);
            xn_root_add(xn_t2540);
            rt_string *xn_t2541 = xn_B(vd);
xn_root_add(xn_t2541);
        xn_root_add(xn_t2541);
            xn_root_add(xn_t2541);
            rt_string *xn_t2542 = xn_concat(xn_t2540, xn_t2541);
xn_root_add(xn_t2542);
        xn_root_add(xn_t2542);
            xn_root_add(xn_t2542);
            rt_string *xn_t2543 = rt_string_from_c(") (Ret ");
xn_root_add(xn_t2543);
        xn_root_add(xn_t2543);
            xn_root_add(xn_t2543);
            rt_string *xn_t2544 = xn_concat(xn_t2542, xn_t2543);
xn_root_add(xn_t2544);
        xn_root_add(xn_t2544);
            xn_root_add(xn_t2544);
            rt_string *xn_t2545 = rt_retain(rt);
xn_root_add(xn_t2545);
        xn_root_add(xn_t2545);
            xn_root_add(xn_t2545);
            rt_string *xn_t2546 = xn_Cls_Parser_retv(self, vd, xn_t2545);
xn_root_add(xn_t2546);
        xn_root_add(xn_t2546);
            xn_root_add(xn_t2546);
            rt_string *xn_t2547 = xn_concat(xn_t2544, xn_t2546);
xn_root_add(xn_t2547);
        xn_root_add(xn_t2547);
            xn_root_add(xn_t2547);
            rt_string *xn_t2548 = rt_string_from_c(") (Params ");
xn_root_add(xn_t2548);
        xn_root_add(xn_t2548);
            xn_root_add(xn_t2548);
            rt_string *xn_t2549 = xn_concat(xn_t2547, xn_t2548);
xn_root_add(xn_t2549);
        xn_root_add(xn_t2549);
            xn_root_add(xn_t2549);
            rt_string *xn_t2550 = xn_SL(ps);
xn_root_add(xn_t2550);
        xn_root_add(xn_t2550);
            xn_root_add(xn_t2550);
            rt_string *xn_t2551 = xn_concat(xn_t2549, xn_t2550);
xn_root_add(xn_t2551);
        xn_root_add(xn_t2551);
            xn_root_add(xn_t2551);
            rt_string *xn_t2552 = rt_string_from_c("))");
xn_root_add(xn_t2552);
        xn_root_add(xn_t2552);
            xn_root_add(xn_t2552);
            rt_string *xn_t2553 = xn_concat(xn_t2551, xn_t2552);
xn_root_add(xn_t2553);
        xn_root_add(xn_t2553);
            xn_root_add(xn_t2553);
            xn_arr_s_push(sigs, xn_t2553);
            xn_root_release(rt);
            xn_root_release(mn);
                {
                rt_release(mn);
                }
                {
                rt_release(rt);
                }
                {
                rt_release(ms);
                }
                {
                xn_root_restore(xn_t2502);
                }

            xn_gc_safepoint();
            }
            {
            xn_root_restore(xn_t2501);
            }

    } else {
        rt_string *xn_t2555 = rt_retain(xn_p_kw);
xn_root_add(xn_t2555);
        xn_root_add(xn_t2555);
        rt_string *xn_t2556 = rt_string_from_c("enum");
xn_root_add(xn_t2556);
        xn_root_add(xn_t2556);
            if ((xn_str_eq(xn_t2555, xn_t2556))) {
                size_t xn_t2557 = xn_root_mark();
                #line 1331 "impl/lib/b2/xparser.x"
                    while ((((!(xn_Cls_Parser_at(self, 13)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                    size_t xn_t2558 = xn_root_mark();
                    #line 1332 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 1))) {
                            size_t xn_t2559 = xn_root_mark();
                            #line 1332 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                            #line 1332 "impl/lib/b2/xparser.x"
                            xn_root_restore(xn_t2559);
                            xn_root_restore(xn_t2558);
                            continue;
                                {
                                xn_root_restore(xn_t2559);
                                }

                        }
                    #line 1333 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 2))) {
                            size_t xn_t2560 = xn_root_mark();
                            #line 1334 "impl/lib/b2/xparser.x"
                            xn_Cls_Tok * it = xn_Cls_Parser_cur(self);
xn_root_add(it);
        xn_root_add(it);
                xn_root_add(it);
                    xn_root_add(it);
                            xn_root_add(it);
                            xn_root_add(it);
                            xn_gc_safepoint();
                            #line 1336 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                            #line 1337 "impl/lib/b2/xparser.x"
                            xn_arr_s *xn_t2561 = xn_arr_s_new(0);
xn_root_add(xn_t2561);
        xn_root_add(xn_t2561);
                xn_root_add(xn_t2561);
                    xn_root_add(xn_t2561);
                            xn_root_add(xn_t2561);
                            xn_arr_s * args = xn_t2561;
xn_root_add(args);
        xn_root_add(args);
                xn_root_add(args);
                    xn_root_add(args);
                            xn_root_add(args);
                            xn_root_add(args);
                            xn_gc_safepoint();
                            #line 1338 "impl/lib/b2/xparser.x"
                                if ((xn_Cls_Parser_at(self, 10))) {
                                    size_t xn_t2562 = xn_root_mark();
                                    #line 1339 "impl/lib/b2/xparser.x"
                                    xn_Cls_Parser_next(self);
                                    #line 1340 "impl/lib/b2/xparser.x"
                                        while ((((!(xn_Cls_Parser_at(self, 11)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                                        size_t xn_t2563 = xn_root_mark();
                                        #line 1341 "impl/lib/b2/xparser.x"
                                            if ((xn_Cls_Parser_at(self, 16))) {
                                                size_t xn_t2564 = xn_root_mark();
                                                #line 1341 "impl/lib/b2/xparser.x"
                                                xn_Cls_Parser_next(self);
                                                #line 1341 "impl/lib/b2/xparser.x"
                                                xn_root_restore(xn_t2564);
                                                xn_root_restore(xn_t2563);
                                                continue;
                                                    {
                                                    xn_root_restore(xn_t2564);
                                                    }

                                            }
                                        #line 1342 "impl/lib/b2/xparser.x"
                                        xn_Cls_E * xn_t2565 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t2565);
        xn_root_add(xn_t2565);
                xn_root_add(xn_t2565);
                    xn_root_add(xn_t2565);
                            xn_root_add(xn_t2565);
                                    xn_root_add(xn_t2565);
                                        xn_root_add(xn_t2565);
                                        rt_string *xn_t2566 = rt_retain(xn_t2565->d);
xn_root_add(xn_t2566);
        xn_root_add(xn_t2566);
                xn_root_add(xn_t2566);
                    xn_root_add(xn_t2566);
                            xn_root_add(xn_t2566);
                                    xn_root_add(xn_t2566);
                                        xn_root_add(xn_t2566);
                                        xn_arr_s_push(args, xn_t2566);
                                            {
                                            xn_root_restore(xn_t2563);
                                            }

                                        xn_gc_safepoint();
                                        }
                                    #line 1344 "impl/lib/b2/xparser.x"
                                        if ((xn_Cls_Parser_at(self, 11))) {
                                            size_t xn_t2567 = xn_root_mark();
                                            #line 1344 "impl/lib/b2/xparser.x"
                                            xn_Cls_Parser_next(self);
                                                {
                                                xn_root_restore(xn_t2567);
                                                }

                                        }
                                        {
                                        xn_root_restore(xn_t2562);
                                        }

                                }
                            #line 1346 "impl/lib/b2/xparser.x"
                            rt_string *val = rt_string_from_c("(nil)");
xn_root_add(val);
        xn_root_add(val);
                xn_root_add(val);
                    xn_root_add(val);
                            xn_root_add(val);
                            xn_root_add(val);
                            xn_gc_safepoint();
                            #line 1347 "impl/lib/b2/xparser.x"
                            rt_string *xn_t2569 = rt_string_from_c("=");
xn_root_add(xn_t2569);
        xn_root_add(xn_t2569);
                xn_root_add(xn_t2569);
                    xn_root_add(xn_t2569);
                            xn_root_add(xn_t2569);
                                if ((xn_Cls_Parser_atOp(self, xn_t2569))) {
                                    size_t xn_t2570 = xn_root_mark();
                                    #line 1347 "impl/lib/b2/xparser.x"
                                    xn_Cls_Parser_next(self);
                                    #line 1347 "impl/lib/b2/xparser.x"
                                    xn_Cls_E * xn_t2571 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t2571);
        xn_root_add(xn_t2571);
                xn_root_add(xn_t2571);
                    xn_root_add(xn_t2571);
                            xn_root_add(xn_t2571);
                                    xn_root_add(xn_t2571);
                                    rt_string *xn_t2572 = rt_retain(xn_t2571->d);
xn_root_add(xn_t2572);
        xn_root_add(xn_t2572);
                xn_root_add(xn_t2572);
                    xn_root_add(xn_t2572);
                            xn_root_add(xn_t2572);
                                    xn_root_add(xn_t2572);
                                    xn_root_release(val);
                                    rt_release(val);
                                    val = xn_t2572;
                                    xn_root_hold(val);
                                    xn_gc_safepoint();
                                        {
                                        xn_root_restore(xn_t2570);
                                        }

                                }
                            #line 1348 "impl/lib/b2/xparser.x"
                            rt_string *xn_t2573 = rt_string_from_c("(EnumItem ");
xn_root_add(xn_t2573);
        xn_root_add(xn_t2573);
                xn_root_add(xn_t2573);
                    xn_root_add(xn_t2573);
                            xn_root_add(xn_t2573);
                            rt_string *xn_t2574 = xn_P(it->line, it->col);
xn_root_add(xn_t2574);
        xn_root_add(xn_t2574);
                xn_root_add(xn_t2574);
                    xn_root_add(xn_t2574);
                            xn_root_add(xn_t2574);
                            rt_string *xn_t2575 = xn_concat(xn_t2573, xn_t2574);
xn_root_add(xn_t2575);
        xn_root_add(xn_t2575);
                xn_root_add(xn_t2575);
                    xn_root_add(xn_t2575);
                            xn_root_add(xn_t2575);
                            rt_string *xn_t2576 = rt_string_from_c(" (Annos (slice)) (Name ");
xn_root_add(xn_t2576);
        xn_root_add(xn_t2576);
                xn_root_add(xn_t2576);
                    xn_root_add(xn_t2576);
                            xn_root_add(xn_t2576);
                            rt_string *xn_t2577 = xn_concat(xn_t2575, xn_t2576);
xn_root_add(xn_t2577);
        xn_root_add(xn_t2577);
                xn_root_add(xn_t2577);
                    xn_root_add(xn_t2577);
                            xn_root_add(xn_t2577);
                            rt_string *xn_t2578 = rt_retain(it->text);
xn_root_add(xn_t2578);
        xn_root_add(xn_t2578);
                xn_root_add(xn_t2578);
                    xn_root_add(xn_t2578);
                            xn_root_add(xn_t2578);
                            rt_string *xn_t2579 = xn_q(xn_t2578);
xn_root_add(xn_t2579);
        xn_root_add(xn_t2579);
                xn_root_add(xn_t2579);
                    xn_root_add(xn_t2579);
                            xn_root_add(xn_t2579);
                            rt_string *xn_t2580 = xn_concat(xn_t2577, xn_t2579);
xn_root_add(xn_t2580);
        xn_root_add(xn_t2580);
                xn_root_add(xn_t2580);
                    xn_root_add(xn_t2580);
                            xn_root_add(xn_t2580);
                            rt_string *xn_t2581 = rt_string_from_c(") (Value ");
xn_root_add(xn_t2581);
        xn_root_add(xn_t2581);
                xn_root_add(xn_t2581);
                    xn_root_add(xn_t2581);
                            xn_root_add(xn_t2581);
                            rt_string *xn_t2582 = xn_concat(xn_t2580, xn_t2581);
xn_root_add(xn_t2582);
        xn_root_add(xn_t2582);
                xn_root_add(xn_t2582);
                    xn_root_add(xn_t2582);
                            xn_root_add(xn_t2582);
                            rt_string *xn_t2583 = rt_retain(val);
xn_root_add(xn_t2583);
        xn_root_add(xn_t2583);
                xn_root_add(xn_t2583);
                    xn_root_add(xn_t2583);
                            xn_root_add(xn_t2583);
                            rt_string *xn_t2584 = xn_concat(xn_t2582, xn_t2583);
xn_root_add(xn_t2584);
        xn_root_add(xn_t2584);
                xn_root_add(xn_t2584);
                    xn_root_add(xn_t2584);
                            xn_root_add(xn_t2584);
                            rt_string *xn_t2585 = rt_string_from_c(") (Args ");
xn_root_add(xn_t2585);
        xn_root_add(xn_t2585);
                xn_root_add(xn_t2585);
                    xn_root_add(xn_t2585);
                            xn_root_add(xn_t2585);
                            rt_string *xn_t2586 = xn_concat(xn_t2584, xn_t2585);
xn_root_add(xn_t2586);
        xn_root_add(xn_t2586);
                xn_root_add(xn_t2586);
                    xn_root_add(xn_t2586);
                            xn_root_add(xn_t2586);
                            rt_string *xn_t2587 = xn_SL(args);
xn_root_add(xn_t2587);
        xn_root_add(xn_t2587);
                xn_root_add(xn_t2587);
                    xn_root_add(xn_t2587);
                            xn_root_add(xn_t2587);
                            rt_string *xn_t2588 = xn_concat(xn_t2586, xn_t2587);
xn_root_add(xn_t2588);
        xn_root_add(xn_t2588);
                xn_root_add(xn_t2588);
                    xn_root_add(xn_t2588);
                            xn_root_add(xn_t2588);
                            rt_string *xn_t2589 = rt_string_from_c("))");
xn_root_add(xn_t2589);
        xn_root_add(xn_t2589);
                xn_root_add(xn_t2589);
                    xn_root_add(xn_t2589);
                            xn_root_add(xn_t2589);
                            rt_string *xn_t2590 = xn_concat(xn_t2588, xn_t2589);
xn_root_add(xn_t2590);
        xn_root_add(xn_t2590);
                xn_root_add(xn_t2590);
                    xn_root_add(xn_t2590);
                            xn_root_add(xn_t2590);
                            xn_arr_s_push(items, xn_t2590);
                            #line 1350 "impl/lib/b2/xparser.x"
                                if ((xn_Cls_Parser_at(self, 16))) {
                                    size_t xn_t2591 = xn_root_mark();
                                    #line 1350 "impl/lib/b2/xparser.x"
                                    xn_Cls_Parser_next(self);
                                        {
                                        xn_root_restore(xn_t2591);
                                        }

                                }
                            #line 1351 "impl/lib/b2/xparser.x"
                            xn_root_restore(xn_t2560);
                            xn_root_restore(xn_t2558);
                            continue;
                            xn_root_release(val);
                                {
                                rt_release(val);
                                }
                                {
                                xn_root_restore(xn_t2560);
                                }

                        }
                    #line 1353 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t2558);
                    break;
                        {
                        xn_root_restore(xn_t2558);
                        }

                    xn_gc_safepoint();
                    }
                #line 1355 "impl/lib/b2/xparser.x"
                    while ((((!(xn_Cls_Parser_at(self, 13)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                    size_t xn_t2592 = xn_root_mark();
                    #line 1356 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 1))) {
                            size_t xn_t2593 = xn_root_mark();
                            #line 1356 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                            #line 1356 "impl/lib/b2/xparser.x"
                            xn_root_restore(xn_t2593);
                            xn_root_restore(xn_t2592);
                            continue;
                                {
                                xn_root_restore(xn_t2593);
                                }

                        }
                    #line 1357 "impl/lib/b2/xparser.x"
                    rt_string *xn_t2594 = rt_retain(name);
xn_root_add(xn_t2594);
        xn_root_add(xn_t2594);
                xn_root_add(xn_t2594);
                    xn_root_add(xn_t2594);
                    rt_string *r = xn_Cls_Parser_parseMember(self, xn_t2594, fields, methods, ctors);
xn_root_add(r);
        xn_root_add(r);
                xn_root_add(r);
                    xn_root_add(r);
                    xn_root_add(r);
                    xn_gc_safepoint();
                    #line 1358 "impl/lib/b2/xparser.x"
                    rt_string *xn_t2596 = rt_retain(r);
xn_root_add(xn_t2596);
        xn_root_add(xn_t2596);
                xn_root_add(xn_t2596);
                    xn_root_add(xn_t2596);
                    rt_string *xn_t2597 = rt_string_from_c("");
xn_root_add(xn_t2597);
        xn_root_add(xn_t2597);
                xn_root_add(xn_t2597);
                    xn_root_add(xn_t2597);
                        if (((!(xn_str_eq(xn_t2596, xn_t2597))))) {
                            size_t xn_t2598 = xn_root_mark();
                            #line 1358 "impl/lib/b2/xparser.x"
                            rt_string *xn_t2599 = rt_retain(r);
xn_root_add(xn_t2599);
        xn_root_add(xn_t2599);
                xn_root_add(xn_t2599);
                    xn_root_add(xn_t2599);
                            xn_root_add(xn_t2599);
                            xn_arr_s_push(methods, xn_t2599);
                                {
                                xn_root_restore(xn_t2598);
                                }

                        }
                        {
                        rt_release(r);
                        }
                        {
                        xn_root_restore(xn_t2592);
                        }

                    xn_gc_safepoint();
                    }
                    {
                    xn_root_restore(xn_t2557);
                    }

            } else {
                rt_string *xn_t2601 = rt_retain(xn_p_kw);
xn_root_add(xn_t2601);
        xn_root_add(xn_t2601);
                xn_root_add(xn_t2601);
                rt_string *xn_t2602 = rt_string_from_c("annotation");
xn_root_add(xn_t2602);
        xn_root_add(xn_t2602);
                xn_root_add(xn_t2602);
                    if ((xn_str_eq(xn_t2601, xn_t2602))) {
                        size_t xn_t2603 = xn_root_mark();
                        #line 1361 "impl/lib/b2/xparser.x"
                            while ((((!(xn_Cls_Parser_at(self, 13)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                            size_t xn_t2604 = xn_root_mark();
                            #line 1362 "impl/lib/b2/xparser.x"
                                if ((xn_Cls_Parser_at(self, 1))) {
                                    size_t xn_t2605 = xn_root_mark();
                                    #line 1362 "impl/lib/b2/xparser.x"
                                    xn_Cls_Parser_next(self);
                                    #line 1362 "impl/lib/b2/xparser.x"
                                    xn_root_restore(xn_t2605);
                                    xn_root_restore(xn_t2604);
                                    continue;
                                        {
                                        xn_root_restore(xn_t2605);
                                        }

                                }
                            #line 1363 "impl/lib/b2/xparser.x"
                            rt_string *xn_t2606 = xn_Cls_Parser_parseField(self);
xn_root_add(xn_t2606);
        xn_root_add(xn_t2606);
                xn_root_add(xn_t2606);
                        xn_root_add(xn_t2606);
                            xn_root_add(xn_t2606);
                            xn_arr_s_push(fields, xn_t2606);
                                {
                                xn_root_restore(xn_t2604);
                                }

                            xn_gc_safepoint();
                            }
                            {
                            xn_root_restore(xn_t2603);
                            }

                    } else {
                        rt_string *xn_t2608 = rt_retain(xn_p_kw);
xn_root_add(xn_t2608);
        xn_root_add(xn_t2608);
                xn_root_add(xn_t2608);
                        xn_root_add(xn_t2608);
                        rt_string *xn_t2609 = rt_string_from_c("factory");
xn_root_add(xn_t2609);
        xn_root_add(xn_t2609);
                xn_root_add(xn_t2609);
                        xn_root_add(xn_t2609);
                        rt_string *xn_t2610 = rt_retain(xn_p_kw);
xn_root_add(xn_t2610);
        xn_root_add(xn_t2610);
                xn_root_add(xn_t2610);
                        xn_root_add(xn_t2610);
                        rt_string *xn_t2611 = rt_string_from_c("extension");
xn_root_add(xn_t2611);
        xn_root_add(xn_t2611);
                xn_root_add(xn_t2611);
                        xn_root_add(xn_t2611);
                            if (((xn_str_eq(xn_t2608, xn_t2609)) || (xn_str_eq(xn_t2610, xn_t2611)))) {
                                size_t xn_t2612 = xn_root_mark();
                                #line 1366 "impl/lib/b2/xparser.x"
                                rt_string *xn_t2613 = rt_string_from_c("for");
xn_root_add(xn_t2613);
        xn_root_add(xn_t2613);
                xn_root_add(xn_t2613);
                        xn_root_add(xn_t2613);
                                xn_root_add(xn_t2613);
                                    if ((xn_Cls_Parser_atKw(self, xn_t2613))) {
                                        size_t xn_t2614 = xn_root_mark();
                                        #line 1366 "impl/lib/b2/xparser.x"
                                        xn_Cls_Parser_next(self);
                                        #line 1366 "impl/lib/b2/xparser.x"
                                        rt_string *xn_t2615 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t2615);
        xn_root_add(xn_t2615);
                xn_root_add(xn_t2615);
                        xn_root_add(xn_t2615);
                                xn_root_add(xn_t2615);
                                        xn_root_add(xn_t2615);
                                        xn_root_release(base);
                                        rt_release(base);
                                        base = xn_t2615;
                                        xn_root_hold(base);
                                        xn_gc_safepoint();
                                            {
                                            xn_root_restore(xn_t2614);
                                            }

                                    }
                                #line 1367 "impl/lib/b2/xparser.x"
                                rt_string *xn_t2616 = rt_retain(xn_p_kw);
xn_root_add(xn_t2616);
        xn_root_add(xn_t2616);
                xn_root_add(xn_t2616);
                        xn_root_add(xn_t2616);
                                xn_root_add(xn_t2616);
                                rt_string *xn_t2617 = rt_string_from_c("extension");
xn_root_add(xn_t2617);
        xn_root_add(xn_t2617);
                xn_root_add(xn_t2617);
                        xn_root_add(xn_t2617);
                                xn_root_add(xn_t2617);
                                rt_string *xn_t2618 = rt_retain(base);
xn_root_add(xn_t2618);
        xn_root_add(xn_t2618);
                xn_root_add(xn_t2618);
                        xn_root_add(xn_t2618);
                                xn_root_add(xn_t2618);
                                rt_string *xn_t2619 = rt_string_from_c("(nil)");
xn_root_add(xn_t2619);
        xn_root_add(xn_t2619);
                xn_root_add(xn_t2619);
                        xn_root_add(xn_t2619);
                                xn_root_add(xn_t2619);
                                    if (((xn_str_eq(xn_t2616, xn_t2617)) && (xn_str_eq(xn_t2618, xn_t2619)))) {
                                        size_t xn_t2620 = xn_root_mark();
                                        #line 1368 "impl/lib/b2/xparser.x"
                                        rt_string *xn_t2621 = rt_string_from_c("(NamedType ");
xn_root_add(xn_t2621);
        xn_root_add(xn_t2621);
                xn_root_add(xn_t2621);
                        xn_root_add(xn_t2621);
                                xn_root_add(xn_t2621);
                                        xn_root_add(xn_t2621);
                                        rt_string *xn_t2622 = xn_P(nl, nc);
xn_root_add(xn_t2622);
        xn_root_add(xn_t2622);
                xn_root_add(xn_t2622);
                        xn_root_add(xn_t2622);
                                xn_root_add(xn_t2622);
                                        xn_root_add(xn_t2622);
                                        rt_string *xn_t2623 = xn_concat(xn_t2621, xn_t2622);
xn_root_add(xn_t2623);
        xn_root_add(xn_t2623);
                xn_root_add(xn_t2623);
                        xn_root_add(xn_t2623);
                                xn_root_add(xn_t2623);
                                        xn_root_add(xn_t2623);
                                        rt_string *xn_t2624 = rt_string_from_c(" (Qual (slice ");
xn_root_add(xn_t2624);
        xn_root_add(xn_t2624);
                xn_root_add(xn_t2624);
                        xn_root_add(xn_t2624);
                                xn_root_add(xn_t2624);
                                        xn_root_add(xn_t2624);
                                        rt_string *xn_t2625 = xn_concat(xn_t2623, xn_t2624);
xn_root_add(xn_t2625);
        xn_root_add(xn_t2625);
                xn_root_add(xn_t2625);
                        xn_root_add(xn_t2625);
                                xn_root_add(xn_t2625);
                                        xn_root_add(xn_t2625);
                                        rt_string *xn_t2626 = rt_retain(name);
xn_root_add(xn_t2626);
        xn_root_add(xn_t2626);
                xn_root_add(xn_t2626);
                        xn_root_add(xn_t2626);
                                xn_root_add(xn_t2626);
                                        xn_root_add(xn_t2626);
                                        rt_string *xn_t2627 = xn_q(xn_t2626);
xn_root_add(xn_t2627);
        xn_root_add(xn_t2627);
                xn_root_add(xn_t2627);
                        xn_root_add(xn_t2627);
                                xn_root_add(xn_t2627);
                                        xn_root_add(xn_t2627);
                                        rt_string *xn_t2628 = xn_concat(xn_t2625, xn_t2627);
xn_root_add(xn_t2628);
        xn_root_add(xn_t2628);
                xn_root_add(xn_t2628);
                        xn_root_add(xn_t2628);
                                xn_root_add(xn_t2628);
                                        xn_root_add(xn_t2628);
                                        rt_string *xn_t2629 = rt_string_from_c(")) (Args (slice)))");
xn_root_add(xn_t2629);
        xn_root_add(xn_t2629);
                xn_root_add(xn_t2629);
                        xn_root_add(xn_t2629);
                                xn_root_add(xn_t2629);
                                        xn_root_add(xn_t2629);
                                        rt_string *xn_t2630 = xn_concat(xn_t2628, xn_t2629);
xn_root_add(xn_t2630);
        xn_root_add(xn_t2630);
                xn_root_add(xn_t2630);
                        xn_root_add(xn_t2630);
                                xn_root_add(xn_t2630);
                                        xn_root_add(xn_t2630);
                                        xn_root_release(base);
                                        rt_release(base);
                                        base = xn_t2630;
                                        xn_root_hold(base);
                                        xn_gc_safepoint();
                                            {
                                            xn_root_restore(xn_t2620);
                                            }

                                    }
                                #line 1371 "impl/lib/b2/xparser.x"
                                    if ((xn_Cls_Parser_at(self, 12))) {
                                        size_t xn_t2631 = xn_root_mark();
                                        #line 1371 "impl/lib/b2/xparser.x"
                                        xn_Cls_Parser_next(self);
                                            {
                                            xn_root_restore(xn_t2631);
                                            }

                                    }
                                #line 1372 "impl/lib/b2/xparser.x"
                                    while ((((!(xn_Cls_Parser_at(self, 13)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                                    size_t xn_t2632 = xn_root_mark();
                                    #line 1373 "impl/lib/b2/xparser.x"
                                        if ((xn_Cls_Parser_at(self, 1))) {
                                            size_t xn_t2633 = xn_root_mark();
                                            #line 1373 "impl/lib/b2/xparser.x"
                                            xn_Cls_Parser_next(self);
                                            #line 1373 "impl/lib/b2/xparser.x"
                                            xn_root_restore(xn_t2633);
                                            xn_root_restore(xn_t2632);
                                            continue;
                                                {
                                                xn_root_restore(xn_t2633);
                                                }

                                        }
                                    #line 1374 "impl/lib/b2/xparser.x"
                                    rt_string *xn_t2634 = rt_retain(name);
xn_root_add(xn_t2634);
        xn_root_add(xn_t2634);
                xn_root_add(xn_t2634);
                        xn_root_add(xn_t2634);
                                xn_root_add(xn_t2634);
                                    xn_root_add(xn_t2634);
                                    rt_string *r = xn_Cls_Parser_parseMember(self, xn_t2634, fields, methods, ctors);
xn_root_add(r);
        xn_root_add(r);
                xn_root_add(r);
                        xn_root_add(r);
                                xn_root_add(r);
                                    xn_root_add(r);
                                    xn_root_add(r);
                                    xn_gc_safepoint();
                                    #line 1375 "impl/lib/b2/xparser.x"
                                    rt_string *xn_t2636 = rt_retain(r);
xn_root_add(xn_t2636);
        xn_root_add(xn_t2636);
                xn_root_add(xn_t2636);
                        xn_root_add(xn_t2636);
                                xn_root_add(xn_t2636);
                                    xn_root_add(xn_t2636);
                                    rt_string *xn_t2637 = rt_string_from_c("");
xn_root_add(xn_t2637);
        xn_root_add(xn_t2637);
                xn_root_add(xn_t2637);
                        xn_root_add(xn_t2637);
                                xn_root_add(xn_t2637);
                                    xn_root_add(xn_t2637);
                                        if (((!(xn_str_eq(xn_t2636, xn_t2637))))) {
                                            size_t xn_t2638 = xn_root_mark();
                                            #line 1375 "impl/lib/b2/xparser.x"
                                            rt_string *xn_t2639 = rt_retain(r);
xn_root_add(xn_t2639);
        xn_root_add(xn_t2639);
                xn_root_add(xn_t2639);
                        xn_root_add(xn_t2639);
                                xn_root_add(xn_t2639);
                                    xn_root_add(xn_t2639);
                                            xn_root_add(xn_t2639);
                                            xn_arr_s_push(methods, xn_t2639);
                                                {
                                                xn_root_restore(xn_t2638);
                                                }

                                        }
                                        {
                                        rt_release(r);
                                        }
                                        {
                                        xn_root_restore(xn_t2632);
                                        }

                                    xn_gc_safepoint();
                                    }
                                    {
                                    xn_root_restore(xn_t2612);
                                    }

                            } else {
                                size_t xn_t2640 = xn_root_mark();
                                #line 1378 "impl/lib/b2/xparser.x"
                                    while ((((!(xn_Cls_Parser_at(self, 13)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                                    size_t xn_t2641 = xn_root_mark();
                                    #line 1379 "impl/lib/b2/xparser.x"
                                        if ((xn_Cls_Parser_at(self, 1))) {
                                            size_t xn_t2642 = xn_root_mark();
                                            #line 1379 "impl/lib/b2/xparser.x"
                                            xn_Cls_Parser_next(self);
                                            #line 1379 "impl/lib/b2/xparser.x"
                                            xn_root_restore(xn_t2642);
                                            xn_root_restore(xn_t2641);
                                            continue;
                                                {
                                                xn_root_restore(xn_t2642);
                                                }

                                        }
                                    #line 1380 "impl/lib/b2/xparser.x"
                                    rt_string *xn_t2643 = rt_retain(name);
xn_root_add(xn_t2643);
        xn_root_add(xn_t2643);
                xn_root_add(xn_t2643);
                        xn_root_add(xn_t2643);
                                xn_root_add(xn_t2643);
                                    xn_root_add(xn_t2643);
                                    rt_string *r = xn_Cls_Parser_parseMember(self, xn_t2643, fields, methods, ctors);
xn_root_add(r);
        xn_root_add(r);
                xn_root_add(r);
                        xn_root_add(r);
                                xn_root_add(r);
                                    xn_root_add(r);
                                    xn_root_add(r);
                                    xn_gc_safepoint();
                                    #line 1381 "impl/lib/b2/xparser.x"
                                    rt_string *xn_t2645 = rt_retain(r);
xn_root_add(xn_t2645);
        xn_root_add(xn_t2645);
                xn_root_add(xn_t2645);
                        xn_root_add(xn_t2645);
                                xn_root_add(xn_t2645);
                                    xn_root_add(xn_t2645);
                                    rt_string *xn_t2646 = rt_string_from_c("");
xn_root_add(xn_t2646);
        xn_root_add(xn_t2646);
                xn_root_add(xn_t2646);
                        xn_root_add(xn_t2646);
                                xn_root_add(xn_t2646);
                                    xn_root_add(xn_t2646);
                                        if (((!(xn_str_eq(xn_t2645, xn_t2646))))) {
                                            size_t xn_t2647 = xn_root_mark();
                                            #line 1381 "impl/lib/b2/xparser.x"
                                            rt_string *xn_t2648 = rt_retain(r);
xn_root_add(xn_t2648);
        xn_root_add(xn_t2648);
                xn_root_add(xn_t2648);
                        xn_root_add(xn_t2648);
                                xn_root_add(xn_t2648);
                                    xn_root_add(xn_t2648);
                                            xn_root_add(xn_t2648);
                                            xn_arr_s_push(methods, xn_t2648);
                                                {
                                                xn_root_restore(xn_t2647);
                                                }

                                        }
                                        {
                                        rt_release(r);
                                        }
                                        {
                                        xn_root_restore(xn_t2641);
                                        }

                                    xn_gc_safepoint();
                                    }
                                    {
                                    xn_root_restore(xn_t2640);
                                    }

                            }
                    }
            }
    }
#line 1384 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 13))) {
        size_t xn_t2649 = xn_root_mark();
        #line 1384 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t2649);
            }

    }
#line 1385 "impl/lib/b2/xparser.x"
rt_string *xn_t2650 = rt_retain(xn_p_kw);
xn_root_add(xn_t2650);
rt_string *xn_t2651 = rt_string_from_c("class");
xn_root_add(xn_t2651);
    if ((xn_str_eq(xn_t2650, xn_t2651))) {
        size_t xn_t2652 = xn_root_mark();
        #line 1386 "impl/lib/b2/xparser.x"
        rt_string *xn_t2653 = rt_string_from_c("(ClassDecl ");
xn_root_add(xn_t2653);
        xn_root_add(xn_t2653);
        xn_root_add(xn_t2653);
        rt_string *xn_t2654 = xn_P(nl, nc);
xn_root_add(xn_t2654);
        xn_root_add(xn_t2654);
        xn_root_add(xn_t2654);
        rt_string *xn_t2655 = xn_concat(xn_t2653, xn_t2654);
xn_root_add(xn_t2655);
        xn_root_add(xn_t2655);
        xn_root_add(xn_t2655);
        rt_string *xn_t2656 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2656);
        xn_root_add(xn_t2656);
        xn_root_add(xn_t2656);
        rt_string *xn_t2657 = xn_concat(xn_t2655, xn_t2656);
xn_root_add(xn_t2657);
        xn_root_add(xn_t2657);
        xn_root_add(xn_t2657);
        rt_string *xn_t2658 = xn_SL(xn_p_annos);
xn_root_add(xn_t2658);
        xn_root_add(xn_t2658);
        xn_root_add(xn_t2658);
        rt_string *xn_t2659 = xn_concat(xn_t2657, xn_t2658);
xn_root_add(xn_t2659);
        xn_root_add(xn_t2659);
        xn_root_add(xn_t2659);
        rt_string *xn_t2660 = rt_string_from_c(") (Mod ");
xn_root_add(xn_t2660);
        xn_root_add(xn_t2660);
        xn_root_add(xn_t2660);
        rt_string *xn_t2661 = xn_concat(xn_t2659, xn_t2660);
xn_root_add(xn_t2661);
        xn_root_add(xn_t2661);
        xn_root_add(xn_t2661);
        rt_string *xn_t2662 = xn_Cls_Parser_modDump(self, xn_p_m);
xn_root_add(xn_t2662);
        xn_root_add(xn_t2662);
        xn_root_add(xn_t2662);
        rt_string *xn_t2663 = xn_concat(xn_t2661, xn_t2662);
xn_root_add(xn_t2663);
        xn_root_add(xn_t2663);
        xn_root_add(xn_t2663);
        rt_string *xn_t2664 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2664);
        xn_root_add(xn_t2664);
        xn_root_add(xn_t2664);
        rt_string *xn_t2665 = xn_concat(xn_t2663, xn_t2664);
xn_root_add(xn_t2665);
        xn_root_add(xn_t2665);
        xn_root_add(xn_t2665);
        rt_string *xn_t2666 = rt_retain(name);
xn_root_add(xn_t2666);
        xn_root_add(xn_t2666);
        xn_root_add(xn_t2666);
        rt_string *xn_t2667 = xn_q(xn_t2666);
xn_root_add(xn_t2667);
        xn_root_add(xn_t2667);
        xn_root_add(xn_t2667);
        rt_string *xn_t2668 = xn_concat(xn_t2665, xn_t2667);
xn_root_add(xn_t2668);
        xn_root_add(xn_t2668);
        xn_root_add(xn_t2668);
        rt_string *xn_t2669 = rt_string_from_c(") (TypePars ");
xn_root_add(xn_t2669);
        xn_root_add(xn_t2669);
        xn_root_add(xn_t2669);
        rt_string *xn_t2670 = xn_concat(xn_t2668, xn_t2669);
xn_root_add(xn_t2670);
        xn_root_add(xn_t2670);
        xn_root_add(xn_t2670);
        rt_string *xn_t2671 = xn_SLS(tps);
xn_root_add(xn_t2671);
        xn_root_add(xn_t2671);
        xn_root_add(xn_t2671);
        rt_string *xn_t2672 = xn_concat(xn_t2670, xn_t2671);
xn_root_add(xn_t2672);
        xn_root_add(xn_t2672);
        xn_root_add(xn_t2672);
        rt_string *xn_t2673 = rt_string_from_c(") (Primary ");
xn_root_add(xn_t2673);
        xn_root_add(xn_t2673);
        xn_root_add(xn_t2673);
        rt_string *xn_t2674 = xn_concat(xn_t2672, xn_t2673);
xn_root_add(xn_t2674);
        xn_root_add(xn_t2674);
        xn_root_add(xn_t2674);
        rt_string *xn_t2675 = rt_retain(primary);
xn_root_add(xn_t2675);
        xn_root_add(xn_t2675);
        xn_root_add(xn_t2675);
        rt_string *xn_t2676 = xn_concat(xn_t2674, xn_t2675);
xn_root_add(xn_t2676);
        xn_root_add(xn_t2676);
        xn_root_add(xn_t2676);
        rt_string *xn_t2677 = rt_string_from_c(") (Base ");
xn_root_add(xn_t2677);
        xn_root_add(xn_t2677);
        xn_root_add(xn_t2677);
        rt_string *xn_t2678 = xn_concat(xn_t2676, xn_t2677);
xn_root_add(xn_t2678);
        xn_root_add(xn_t2678);
        xn_root_add(xn_t2678);
        rt_string *xn_t2679 = rt_retain(base);
xn_root_add(xn_t2679);
        xn_root_add(xn_t2679);
        xn_root_add(xn_t2679);
        rt_string *xn_t2680 = xn_concat(xn_t2678, xn_t2679);
xn_root_add(xn_t2680);
        xn_root_add(xn_t2680);
        xn_root_add(xn_t2680);
        rt_string *xn_t2681 = rt_string_from_c(") (Protocols ");
xn_root_add(xn_t2681);
        xn_root_add(xn_t2681);
        xn_root_add(xn_t2681);
        rt_string *xn_t2682 = xn_concat(xn_t2680, xn_t2681);
xn_root_add(xn_t2682);
        xn_root_add(xn_t2682);
        xn_root_add(xn_t2682);
        rt_string *xn_t2683 = xn_SL(protos);
xn_root_add(xn_t2683);
        xn_root_add(xn_t2683);
        xn_root_add(xn_t2683);
        rt_string *xn_t2684 = xn_concat(xn_t2682, xn_t2683);
xn_root_add(xn_t2684);
        xn_root_add(xn_t2684);
        xn_root_add(xn_t2684);
        rt_string *xn_t2685 = rt_string_from_c(") (Fields ");
xn_root_add(xn_t2685);
        xn_root_add(xn_t2685);
        xn_root_add(xn_t2685);
        rt_string *xn_t2686 = xn_concat(xn_t2684, xn_t2685);
xn_root_add(xn_t2686);
        xn_root_add(xn_t2686);
        xn_root_add(xn_t2686);
        rt_string *xn_t2687 = xn_SL(fields);
xn_root_add(xn_t2687);
        xn_root_add(xn_t2687);
        xn_root_add(xn_t2687);
        rt_string *xn_t2688 = xn_concat(xn_t2686, xn_t2687);
xn_root_add(xn_t2688);
        xn_root_add(xn_t2688);
        xn_root_add(xn_t2688);
        rt_string *xn_t2689 = rt_string_from_c(") (Methods ");
xn_root_add(xn_t2689);
        xn_root_add(xn_t2689);
        xn_root_add(xn_t2689);
        rt_string *xn_t2690 = xn_concat(xn_t2688, xn_t2689);
xn_root_add(xn_t2690);
        xn_root_add(xn_t2690);
        xn_root_add(xn_t2690);
        rt_string *xn_t2691 = xn_SL(methods);
xn_root_add(xn_t2691);
        xn_root_add(xn_t2691);
        xn_root_add(xn_t2691);
        rt_string *xn_t2692 = xn_concat(xn_t2690, xn_t2691);
xn_root_add(xn_t2692);
        xn_root_add(xn_t2692);
        xn_root_add(xn_t2692);
        rt_string *xn_t2693 = rt_string_from_c(") (Ctors ");
xn_root_add(xn_t2693);
        xn_root_add(xn_t2693);
        xn_root_add(xn_t2693);
        rt_string *xn_t2694 = xn_concat(xn_t2692, xn_t2693);
xn_root_add(xn_t2694);
        xn_root_add(xn_t2694);
        xn_root_add(xn_t2694);
        rt_string *xn_t2695 = xn_SL(ctors);
xn_root_add(xn_t2695);
        xn_root_add(xn_t2695);
        xn_root_add(xn_t2695);
        rt_string *xn_t2696 = xn_concat(xn_t2694, xn_t2695);
xn_root_add(xn_t2696);
        xn_root_add(xn_t2696);
        xn_root_add(xn_t2696);
        rt_string *xn_t2697 = rt_string_from_c("))");
xn_root_add(xn_t2697);
        xn_root_add(xn_t2697);
        xn_root_add(xn_t2697);
        rt_string *xn_t2698 = xn_concat(xn_t2696, xn_t2697);
xn_root_add(xn_t2698);
        xn_root_add(xn_t2698);
        xn_root_add(xn_t2698);
            {
        xn_root_restore(xn_t2652);
            }
            {
        rt_release(base);
            }
            {
        rt_release(primary);
            }
            {
        rt_release(name);
            }
            {
        xn_root_restore(xn_t2440);
            }

        return xn_t2698;

    }
#line 1390 "impl/lib/b2/xparser.x"
rt_string *xn_t2699 = rt_retain(xn_p_kw);
xn_root_add(xn_t2699);
rt_string *xn_t2700 = rt_string_from_c("struct");
xn_root_add(xn_t2700);
    if ((xn_str_eq(xn_t2699, xn_t2700))) {
        size_t xn_t2701 = xn_root_mark();
        #line 1391 "impl/lib/b2/xparser.x"
        rt_string *xn_t2702 = rt_string_from_c("(StructDecl ");
xn_root_add(xn_t2702);
        xn_root_add(xn_t2702);
        xn_root_add(xn_t2702);
        rt_string *xn_t2703 = xn_P(nl, nc);
xn_root_add(xn_t2703);
        xn_root_add(xn_t2703);
        xn_root_add(xn_t2703);
        rt_string *xn_t2704 = xn_concat(xn_t2702, xn_t2703);
xn_root_add(xn_t2704);
        xn_root_add(xn_t2704);
        xn_root_add(xn_t2704);
        rt_string *xn_t2705 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2705);
        xn_root_add(xn_t2705);
        xn_root_add(xn_t2705);
        rt_string *xn_t2706 = xn_concat(xn_t2704, xn_t2705);
xn_root_add(xn_t2706);
        xn_root_add(xn_t2706);
        xn_root_add(xn_t2706);
        rt_string *xn_t2707 = xn_SL(xn_p_annos);
xn_root_add(xn_t2707);
        xn_root_add(xn_t2707);
        xn_root_add(xn_t2707);
        rt_string *xn_t2708 = xn_concat(xn_t2706, xn_t2707);
xn_root_add(xn_t2708);
        xn_root_add(xn_t2708);
        xn_root_add(xn_t2708);
        rt_string *xn_t2709 = rt_string_from_c(") (Mod ");
xn_root_add(xn_t2709);
        xn_root_add(xn_t2709);
        xn_root_add(xn_t2709);
        rt_string *xn_t2710 = xn_concat(xn_t2708, xn_t2709);
xn_root_add(xn_t2710);
        xn_root_add(xn_t2710);
        xn_root_add(xn_t2710);
        rt_string *xn_t2711 = xn_Cls_Parser_modDump(self, xn_p_m);
xn_root_add(xn_t2711);
        xn_root_add(xn_t2711);
        xn_root_add(xn_t2711);
        rt_string *xn_t2712 = xn_concat(xn_t2710, xn_t2711);
xn_root_add(xn_t2712);
        xn_root_add(xn_t2712);
        xn_root_add(xn_t2712);
        rt_string *xn_t2713 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2713);
        xn_root_add(xn_t2713);
        xn_root_add(xn_t2713);
        rt_string *xn_t2714 = xn_concat(xn_t2712, xn_t2713);
xn_root_add(xn_t2714);
        xn_root_add(xn_t2714);
        xn_root_add(xn_t2714);
        rt_string *xn_t2715 = rt_retain(name);
xn_root_add(xn_t2715);
        xn_root_add(xn_t2715);
        xn_root_add(xn_t2715);
        rt_string *xn_t2716 = xn_q(xn_t2715);
xn_root_add(xn_t2716);
        xn_root_add(xn_t2716);
        xn_root_add(xn_t2716);
        rt_string *xn_t2717 = xn_concat(xn_t2714, xn_t2716);
xn_root_add(xn_t2717);
        xn_root_add(xn_t2717);
        xn_root_add(xn_t2717);
        rt_string *xn_t2718 = rt_string_from_c(") (TypePars ");
xn_root_add(xn_t2718);
        xn_root_add(xn_t2718);
        xn_root_add(xn_t2718);
        rt_string *xn_t2719 = xn_concat(xn_t2717, xn_t2718);
xn_root_add(xn_t2719);
        xn_root_add(xn_t2719);
        xn_root_add(xn_t2719);
        rt_string *xn_t2720 = xn_SLS(tps);
xn_root_add(xn_t2720);
        xn_root_add(xn_t2720);
        xn_root_add(xn_t2720);
        rt_string *xn_t2721 = xn_concat(xn_t2719, xn_t2720);
xn_root_add(xn_t2721);
        xn_root_add(xn_t2721);
        xn_root_add(xn_t2721);
        rt_string *xn_t2722 = rt_string_from_c(") (Primary ");
xn_root_add(xn_t2722);
        xn_root_add(xn_t2722);
        xn_root_add(xn_t2722);
        rt_string *xn_t2723 = xn_concat(xn_t2721, xn_t2722);
xn_root_add(xn_t2723);
        xn_root_add(xn_t2723);
        xn_root_add(xn_t2723);
        rt_string *xn_t2724 = rt_retain(primary);
xn_root_add(xn_t2724);
        xn_root_add(xn_t2724);
        xn_root_add(xn_t2724);
        rt_string *xn_t2725 = xn_concat(xn_t2723, xn_t2724);
xn_root_add(xn_t2725);
        xn_root_add(xn_t2725);
        xn_root_add(xn_t2725);
        rt_string *xn_t2726 = rt_string_from_c(") (Fields ");
xn_root_add(xn_t2726);
        xn_root_add(xn_t2726);
        xn_root_add(xn_t2726);
        rt_string *xn_t2727 = xn_concat(xn_t2725, xn_t2726);
xn_root_add(xn_t2727);
        xn_root_add(xn_t2727);
        xn_root_add(xn_t2727);
        rt_string *xn_t2728 = xn_SL(fields);
xn_root_add(xn_t2728);
        xn_root_add(xn_t2728);
        xn_root_add(xn_t2728);
        rt_string *xn_t2729 = xn_concat(xn_t2727, xn_t2728);
xn_root_add(xn_t2729);
        xn_root_add(xn_t2729);
        xn_root_add(xn_t2729);
        rt_string *xn_t2730 = rt_string_from_c(") (Methods ");
xn_root_add(xn_t2730);
        xn_root_add(xn_t2730);
        xn_root_add(xn_t2730);
        rt_string *xn_t2731 = xn_concat(xn_t2729, xn_t2730);
xn_root_add(xn_t2731);
        xn_root_add(xn_t2731);
        xn_root_add(xn_t2731);
        rt_string *xn_t2732 = xn_SL(methods);
xn_root_add(xn_t2732);
        xn_root_add(xn_t2732);
        xn_root_add(xn_t2732);
        rt_string *xn_t2733 = xn_concat(xn_t2731, xn_t2732);
xn_root_add(xn_t2733);
        xn_root_add(xn_t2733);
        xn_root_add(xn_t2733);
        rt_string *xn_t2734 = rt_string_from_c(") (Ctors ");
xn_root_add(xn_t2734);
        xn_root_add(xn_t2734);
        xn_root_add(xn_t2734);
        rt_string *xn_t2735 = xn_concat(xn_t2733, xn_t2734);
xn_root_add(xn_t2735);
        xn_root_add(xn_t2735);
        xn_root_add(xn_t2735);
        rt_string *xn_t2736 = xn_SL(ctors);
xn_root_add(xn_t2736);
        xn_root_add(xn_t2736);
        xn_root_add(xn_t2736);
        rt_string *xn_t2737 = xn_concat(xn_t2735, xn_t2736);
xn_root_add(xn_t2737);
        xn_root_add(xn_t2737);
        xn_root_add(xn_t2737);
        rt_string *xn_t2738 = rt_string_from_c("))");
xn_root_add(xn_t2738);
        xn_root_add(xn_t2738);
        xn_root_add(xn_t2738);
        rt_string *xn_t2739 = xn_concat(xn_t2737, xn_t2738);
xn_root_add(xn_t2739);
        xn_root_add(xn_t2739);
        xn_root_add(xn_t2739);
            {
        xn_root_restore(xn_t2701);
            }
            {
        rt_release(base);
            }
            {
        rt_release(primary);
            }
            {
        rt_release(name);
            }
            {
        xn_root_restore(xn_t2440);
            }

        return xn_t2739;

    }
#line 1395 "impl/lib/b2/xparser.x"
rt_string *xn_t2740 = rt_retain(xn_p_kw);
xn_root_add(xn_t2740);
rt_string *xn_t2741 = rt_string_from_c("protocol");
xn_root_add(xn_t2741);
    if ((xn_str_eq(xn_t2740, xn_t2741))) {
        size_t xn_t2742 = xn_root_mark();
        #line 1396 "impl/lib/b2/xparser.x"
        rt_string *xn_t2743 = rt_string_from_c("(ProtocolDecl ");
xn_root_add(xn_t2743);
        xn_root_add(xn_t2743);
        xn_root_add(xn_t2743);
        rt_string *xn_t2744 = xn_P(nl, nc);
xn_root_add(xn_t2744);
        xn_root_add(xn_t2744);
        xn_root_add(xn_t2744);
        rt_string *xn_t2745 = xn_concat(xn_t2743, xn_t2744);
xn_root_add(xn_t2745);
        xn_root_add(xn_t2745);
        xn_root_add(xn_t2745);
        rt_string *xn_t2746 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2746);
        xn_root_add(xn_t2746);
        xn_root_add(xn_t2746);
        rt_string *xn_t2747 = xn_concat(xn_t2745, xn_t2746);
xn_root_add(xn_t2747);
        xn_root_add(xn_t2747);
        xn_root_add(xn_t2747);
        rt_string *xn_t2748 = xn_SL(xn_p_annos);
xn_root_add(xn_t2748);
        xn_root_add(xn_t2748);
        xn_root_add(xn_t2748);
        rt_string *xn_t2749 = xn_concat(xn_t2747, xn_t2748);
xn_root_add(xn_t2749);
        xn_root_add(xn_t2749);
        xn_root_add(xn_t2749);
        rt_string *xn_t2750 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2750);
        xn_root_add(xn_t2750);
        xn_root_add(xn_t2750);
        rt_string *xn_t2751 = xn_concat(xn_t2749, xn_t2750);
xn_root_add(xn_t2751);
        xn_root_add(xn_t2751);
        xn_root_add(xn_t2751);
        rt_string *xn_t2752 = rt_retain(name);
xn_root_add(xn_t2752);
        xn_root_add(xn_t2752);
        xn_root_add(xn_t2752);
        rt_string *xn_t2753 = xn_q(xn_t2752);
xn_root_add(xn_t2753);
        xn_root_add(xn_t2753);
        xn_root_add(xn_t2753);
        rt_string *xn_t2754 = xn_concat(xn_t2751, xn_t2753);
xn_root_add(xn_t2754);
        xn_root_add(xn_t2754);
        xn_root_add(xn_t2754);
        rt_string *xn_t2755 = rt_string_from_c(") (Extends ");
xn_root_add(xn_t2755);
        xn_root_add(xn_t2755);
        xn_root_add(xn_t2755);
        rt_string *xn_t2756 = xn_concat(xn_t2754, xn_t2755);
xn_root_add(xn_t2756);
        xn_root_add(xn_t2756);
        xn_root_add(xn_t2756);
        rt_string *xn_t2757 = xn_SL(protos);
xn_root_add(xn_t2757);
        xn_root_add(xn_t2757);
        xn_root_add(xn_t2757);
        rt_string *xn_t2758 = xn_concat(xn_t2756, xn_t2757);
xn_root_add(xn_t2758);
        xn_root_add(xn_t2758);
        xn_root_add(xn_t2758);
        rt_string *xn_t2759 = rt_string_from_c(") (Sigs ");
xn_root_add(xn_t2759);
        xn_root_add(xn_t2759);
        xn_root_add(xn_t2759);
        rt_string *xn_t2760 = xn_concat(xn_t2758, xn_t2759);
xn_root_add(xn_t2760);
        xn_root_add(xn_t2760);
        xn_root_add(xn_t2760);
        rt_string *xn_t2761 = xn_SL(sigs);
xn_root_add(xn_t2761);
        xn_root_add(xn_t2761);
        xn_root_add(xn_t2761);
        rt_string *xn_t2762 = xn_concat(xn_t2760, xn_t2761);
xn_root_add(xn_t2762);
        xn_root_add(xn_t2762);
        xn_root_add(xn_t2762);
        rt_string *xn_t2763 = rt_string_from_c("))");
xn_root_add(xn_t2763);
        xn_root_add(xn_t2763);
        xn_root_add(xn_t2763);
        rt_string *xn_t2764 = xn_concat(xn_t2762, xn_t2763);
xn_root_add(xn_t2764);
        xn_root_add(xn_t2764);
        xn_root_add(xn_t2764);
            {
        xn_root_restore(xn_t2742);
            }
            {
        rt_release(base);
            }
            {
        rt_release(primary);
            }
            {
        rt_release(name);
            }
            {
        xn_root_restore(xn_t2440);
            }

        return xn_t2764;

    }
#line 1399 "impl/lib/b2/xparser.x"
rt_string *xn_t2765 = rt_retain(xn_p_kw);
xn_root_add(xn_t2765);
rt_string *xn_t2766 = rt_string_from_c("enum");
xn_root_add(xn_t2766);
    if ((xn_str_eq(xn_t2765, xn_t2766))) {
        size_t xn_t2767 = xn_root_mark();
        #line 1400 "impl/lib/b2/xparser.x"
        rt_string *xn_t2768 = rt_string_from_c("(EnumDecl ");
xn_root_add(xn_t2768);
        xn_root_add(xn_t2768);
        xn_root_add(xn_t2768);
        rt_string *xn_t2769 = xn_P(nl, nc);
xn_root_add(xn_t2769);
        xn_root_add(xn_t2769);
        xn_root_add(xn_t2769);
        rt_string *xn_t2770 = xn_concat(xn_t2768, xn_t2769);
xn_root_add(xn_t2770);
        xn_root_add(xn_t2770);
        xn_root_add(xn_t2770);
        rt_string *xn_t2771 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2771);
        xn_root_add(xn_t2771);
        xn_root_add(xn_t2771);
        rt_string *xn_t2772 = xn_concat(xn_t2770, xn_t2771);
xn_root_add(xn_t2772);
        xn_root_add(xn_t2772);
        xn_root_add(xn_t2772);
        rt_string *xn_t2773 = xn_SL(xn_p_annos);
xn_root_add(xn_t2773);
        xn_root_add(xn_t2773);
        xn_root_add(xn_t2773);
        rt_string *xn_t2774 = xn_concat(xn_t2772, xn_t2773);
xn_root_add(xn_t2774);
        xn_root_add(xn_t2774);
        xn_root_add(xn_t2774);
        rt_string *xn_t2775 = rt_string_from_c(") (Mod ");
xn_root_add(xn_t2775);
        xn_root_add(xn_t2775);
        xn_root_add(xn_t2775);
        rt_string *xn_t2776 = xn_concat(xn_t2774, xn_t2775);
xn_root_add(xn_t2776);
        xn_root_add(xn_t2776);
        xn_root_add(xn_t2776);
        rt_string *xn_t2777 = xn_Cls_Parser_modDump(self, xn_p_m);
xn_root_add(xn_t2777);
        xn_root_add(xn_t2777);
        xn_root_add(xn_t2777);
        rt_string *xn_t2778 = xn_concat(xn_t2776, xn_t2777);
xn_root_add(xn_t2778);
        xn_root_add(xn_t2778);
        xn_root_add(xn_t2778);
        rt_string *xn_t2779 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2779);
        xn_root_add(xn_t2779);
        xn_root_add(xn_t2779);
        rt_string *xn_t2780 = xn_concat(xn_t2778, xn_t2779);
xn_root_add(xn_t2780);
        xn_root_add(xn_t2780);
        xn_root_add(xn_t2780);
        rt_string *xn_t2781 = rt_retain(name);
xn_root_add(xn_t2781);
        xn_root_add(xn_t2781);
        xn_root_add(xn_t2781);
        rt_string *xn_t2782 = xn_q(xn_t2781);
xn_root_add(xn_t2782);
        xn_root_add(xn_t2782);
        xn_root_add(xn_t2782);
        rt_string *xn_t2783 = xn_concat(xn_t2780, xn_t2782);
xn_root_add(xn_t2783);
        xn_root_add(xn_t2783);
        xn_root_add(xn_t2783);
        rt_string *xn_t2784 = rt_string_from_c(") (Items ");
xn_root_add(xn_t2784);
        xn_root_add(xn_t2784);
        xn_root_add(xn_t2784);
        rt_string *xn_t2785 = xn_concat(xn_t2783, xn_t2784);
xn_root_add(xn_t2785);
        xn_root_add(xn_t2785);
        xn_root_add(xn_t2785);
        rt_string *xn_t2786 = xn_SL(items);
xn_root_add(xn_t2786);
        xn_root_add(xn_t2786);
        xn_root_add(xn_t2786);
        rt_string *xn_t2787 = xn_concat(xn_t2785, xn_t2786);
xn_root_add(xn_t2787);
        xn_root_add(xn_t2787);
        xn_root_add(xn_t2787);
        rt_string *xn_t2788 = rt_string_from_c(") (IsData ");
xn_root_add(xn_t2788);
        xn_root_add(xn_t2788);
        xn_root_add(xn_t2788);
        rt_string *xn_t2789 = xn_concat(xn_t2787, xn_t2788);
xn_root_add(xn_t2789);
        xn_root_add(xn_t2789);
        xn_root_add(xn_t2789);
        rt_string *xn_t2790 = xn_B((((((int64_t)fields->len) > 0) || (((int64_t)methods->len) > 0)) || (((int64_t)ctors->len) > 0)));
xn_root_add(xn_t2790);
        xn_root_add(xn_t2790);
        xn_root_add(xn_t2790);
        rt_string *xn_t2791 = xn_concat(xn_t2789, xn_t2790);
xn_root_add(xn_t2791);
        xn_root_add(xn_t2791);
        xn_root_add(xn_t2791);
        rt_string *xn_t2792 = rt_string_from_c(") (Fields ");
xn_root_add(xn_t2792);
        xn_root_add(xn_t2792);
        xn_root_add(xn_t2792);
        rt_string *xn_t2793 = xn_concat(xn_t2791, xn_t2792);
xn_root_add(xn_t2793);
        xn_root_add(xn_t2793);
        xn_root_add(xn_t2793);
        rt_string *xn_t2794 = xn_SL(fields);
xn_root_add(xn_t2794);
        xn_root_add(xn_t2794);
        xn_root_add(xn_t2794);
        rt_string *xn_t2795 = xn_concat(xn_t2793, xn_t2794);
xn_root_add(xn_t2795);
        xn_root_add(xn_t2795);
        xn_root_add(xn_t2795);
        rt_string *xn_t2796 = rt_string_from_c(") (Methods ");
xn_root_add(xn_t2796);
        xn_root_add(xn_t2796);
        xn_root_add(xn_t2796);
        rt_string *xn_t2797 = xn_concat(xn_t2795, xn_t2796);
xn_root_add(xn_t2797);
        xn_root_add(xn_t2797);
        xn_root_add(xn_t2797);
        rt_string *xn_t2798 = xn_SL(methods);
xn_root_add(xn_t2798);
        xn_root_add(xn_t2798);
        xn_root_add(xn_t2798);
        rt_string *xn_t2799 = xn_concat(xn_t2797, xn_t2798);
xn_root_add(xn_t2799);
        xn_root_add(xn_t2799);
        xn_root_add(xn_t2799);
        rt_string *xn_t2800 = rt_string_from_c(") (Ctors ");
xn_root_add(xn_t2800);
        xn_root_add(xn_t2800);
        xn_root_add(xn_t2800);
        rt_string *xn_t2801 = xn_concat(xn_t2799, xn_t2800);
xn_root_add(xn_t2801);
        xn_root_add(xn_t2801);
        xn_root_add(xn_t2801);
        rt_string *xn_t2802 = xn_SL(ctors);
xn_root_add(xn_t2802);
        xn_root_add(xn_t2802);
        xn_root_add(xn_t2802);
        rt_string *xn_t2803 = xn_concat(xn_t2801, xn_t2802);
xn_root_add(xn_t2803);
        xn_root_add(xn_t2803);
        xn_root_add(xn_t2803);
        rt_string *xn_t2804 = rt_string_from_c("))");
xn_root_add(xn_t2804);
        xn_root_add(xn_t2804);
        xn_root_add(xn_t2804);
        rt_string *xn_t2805 = xn_concat(xn_t2803, xn_t2804);
xn_root_add(xn_t2805);
        xn_root_add(xn_t2805);
        xn_root_add(xn_t2805);
            {
        xn_root_restore(xn_t2767);
            }
            {
        rt_release(base);
            }
            {
        rt_release(primary);
            }
            {
        rt_release(name);
            }
            {
        xn_root_restore(xn_t2440);
            }

        return xn_t2805;

    }
#line 1404 "impl/lib/b2/xparser.x"
rt_string *xn_t2806 = rt_retain(xn_p_kw);
xn_root_add(xn_t2806);
rt_string *xn_t2807 = rt_string_from_c("singleton");
xn_root_add(xn_t2807);
    if ((xn_str_eq(xn_t2806, xn_t2807))) {
        size_t xn_t2808 = xn_root_mark();
        #line 1405 "impl/lib/b2/xparser.x"
        rt_string *xn_t2809 = rt_string_from_c("(SingletonDecl ");
xn_root_add(xn_t2809);
        xn_root_add(xn_t2809);
        xn_root_add(xn_t2809);
        rt_string *xn_t2810 = xn_P(nl, nc);
xn_root_add(xn_t2810);
        xn_root_add(xn_t2810);
        xn_root_add(xn_t2810);
        rt_string *xn_t2811 = xn_concat(xn_t2809, xn_t2810);
xn_root_add(xn_t2811);
        xn_root_add(xn_t2811);
        xn_root_add(xn_t2811);
        rt_string *xn_t2812 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2812);
        xn_root_add(xn_t2812);
        xn_root_add(xn_t2812);
        rt_string *xn_t2813 = xn_concat(xn_t2811, xn_t2812);
xn_root_add(xn_t2813);
        xn_root_add(xn_t2813);
        xn_root_add(xn_t2813);
        rt_string *xn_t2814 = xn_SL(xn_p_annos);
xn_root_add(xn_t2814);
        xn_root_add(xn_t2814);
        xn_root_add(xn_t2814);
        rt_string *xn_t2815 = xn_concat(xn_t2813, xn_t2814);
xn_root_add(xn_t2815);
        xn_root_add(xn_t2815);
        xn_root_add(xn_t2815);
        rt_string *xn_t2816 = rt_string_from_c(") (Mod ");
xn_root_add(xn_t2816);
        xn_root_add(xn_t2816);
        xn_root_add(xn_t2816);
        rt_string *xn_t2817 = xn_concat(xn_t2815, xn_t2816);
xn_root_add(xn_t2817);
        xn_root_add(xn_t2817);
        xn_root_add(xn_t2817);
        rt_string *xn_t2818 = xn_Cls_Parser_modDump(self, xn_p_m);
xn_root_add(xn_t2818);
        xn_root_add(xn_t2818);
        xn_root_add(xn_t2818);
        rt_string *xn_t2819 = xn_concat(xn_t2817, xn_t2818);
xn_root_add(xn_t2819);
        xn_root_add(xn_t2819);
        xn_root_add(xn_t2819);
        rt_string *xn_t2820 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2820);
        xn_root_add(xn_t2820);
        xn_root_add(xn_t2820);
        rt_string *xn_t2821 = xn_concat(xn_t2819, xn_t2820);
xn_root_add(xn_t2821);
        xn_root_add(xn_t2821);
        xn_root_add(xn_t2821);
        rt_string *xn_t2822 = rt_retain(name);
xn_root_add(xn_t2822);
        xn_root_add(xn_t2822);
        xn_root_add(xn_t2822);
        rt_string *xn_t2823 = xn_q(xn_t2822);
xn_root_add(xn_t2823);
        xn_root_add(xn_t2823);
        xn_root_add(xn_t2823);
        rt_string *xn_t2824 = xn_concat(xn_t2821, xn_t2823);
xn_root_add(xn_t2824);
        xn_root_add(xn_t2824);
        xn_root_add(xn_t2824);
        rt_string *xn_t2825 = rt_string_from_c(") (Fields ");
xn_root_add(xn_t2825);
        xn_root_add(xn_t2825);
        xn_root_add(xn_t2825);
        rt_string *xn_t2826 = xn_concat(xn_t2824, xn_t2825);
xn_root_add(xn_t2826);
        xn_root_add(xn_t2826);
        xn_root_add(xn_t2826);
        rt_string *xn_t2827 = xn_SL(fields);
xn_root_add(xn_t2827);
        xn_root_add(xn_t2827);
        xn_root_add(xn_t2827);
        rt_string *xn_t2828 = xn_concat(xn_t2826, xn_t2827);
xn_root_add(xn_t2828);
        xn_root_add(xn_t2828);
        xn_root_add(xn_t2828);
        rt_string *xn_t2829 = rt_string_from_c(") (Methods ");
xn_root_add(xn_t2829);
        xn_root_add(xn_t2829);
        xn_root_add(xn_t2829);
        rt_string *xn_t2830 = xn_concat(xn_t2828, xn_t2829);
xn_root_add(xn_t2830);
        xn_root_add(xn_t2830);
        xn_root_add(xn_t2830);
        rt_string *xn_t2831 = xn_SL(methods);
xn_root_add(xn_t2831);
        xn_root_add(xn_t2831);
        xn_root_add(xn_t2831);
        rt_string *xn_t2832 = xn_concat(xn_t2830, xn_t2831);
xn_root_add(xn_t2832);
        xn_root_add(xn_t2832);
        xn_root_add(xn_t2832);
        rt_string *xn_t2833 = rt_string_from_c(") (Ctors ");
xn_root_add(xn_t2833);
        xn_root_add(xn_t2833);
        xn_root_add(xn_t2833);
        rt_string *xn_t2834 = xn_concat(xn_t2832, xn_t2833);
xn_root_add(xn_t2834);
        xn_root_add(xn_t2834);
        xn_root_add(xn_t2834);
        rt_string *xn_t2835 = xn_SL(ctors);
xn_root_add(xn_t2835);
        xn_root_add(xn_t2835);
        xn_root_add(xn_t2835);
        rt_string *xn_t2836 = xn_concat(xn_t2834, xn_t2835);
xn_root_add(xn_t2836);
        xn_root_add(xn_t2836);
        xn_root_add(xn_t2836);
        rt_string *xn_t2837 = rt_string_from_c("))");
xn_root_add(xn_t2837);
        xn_root_add(xn_t2837);
        xn_root_add(xn_t2837);
        rt_string *xn_t2838 = xn_concat(xn_t2836, xn_t2837);
xn_root_add(xn_t2838);
        xn_root_add(xn_t2838);
        xn_root_add(xn_t2838);
            {
        xn_root_restore(xn_t2808);
            }
            {
        rt_release(base);
            }
            {
        rt_release(primary);
            }
            {
        rt_release(name);
            }
            {
        xn_root_restore(xn_t2440);
            }

        return xn_t2838;

    }
#line 1408 "impl/lib/b2/xparser.x"
rt_string *xn_t2839 = rt_retain(xn_p_kw);
xn_root_add(xn_t2839);
rt_string *xn_t2840 = rt_string_from_c("factory");
xn_root_add(xn_t2840);
    if ((xn_str_eq(xn_t2839, xn_t2840))) {
        size_t xn_t2841 = xn_root_mark();
        #line 1409 "impl/lib/b2/xparser.x"
        rt_string *xn_t2842 = rt_string_from_c("(FactoryDecl ");
xn_root_add(xn_t2842);
        xn_root_add(xn_t2842);
        xn_root_add(xn_t2842);
        rt_string *xn_t2843 = xn_P(nl, nc);
xn_root_add(xn_t2843);
        xn_root_add(xn_t2843);
        xn_root_add(xn_t2843);
        rt_string *xn_t2844 = xn_concat(xn_t2842, xn_t2843);
xn_root_add(xn_t2844);
        xn_root_add(xn_t2844);
        xn_root_add(xn_t2844);
        rt_string *xn_t2845 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2845);
        xn_root_add(xn_t2845);
        xn_root_add(xn_t2845);
        rt_string *xn_t2846 = xn_concat(xn_t2844, xn_t2845);
xn_root_add(xn_t2846);
        xn_root_add(xn_t2846);
        xn_root_add(xn_t2846);
        rt_string *xn_t2847 = xn_SL(xn_p_annos);
xn_root_add(xn_t2847);
        xn_root_add(xn_t2847);
        xn_root_add(xn_t2847);
        rt_string *xn_t2848 = xn_concat(xn_t2846, xn_t2847);
xn_root_add(xn_t2848);
        xn_root_add(xn_t2848);
        xn_root_add(xn_t2848);
        rt_string *xn_t2849 = rt_string_from_c(") (Mod ");
xn_root_add(xn_t2849);
        xn_root_add(xn_t2849);
        xn_root_add(xn_t2849);
        rt_string *xn_t2850 = xn_concat(xn_t2848, xn_t2849);
xn_root_add(xn_t2850);
        xn_root_add(xn_t2850);
        xn_root_add(xn_t2850);
        rt_string *xn_t2851 = xn_Cls_Parser_modDump(self, xn_p_m);
xn_root_add(xn_t2851);
        xn_root_add(xn_t2851);
        xn_root_add(xn_t2851);
        rt_string *xn_t2852 = xn_concat(xn_t2850, xn_t2851);
xn_root_add(xn_t2852);
        xn_root_add(xn_t2852);
        xn_root_add(xn_t2852);
        rt_string *xn_t2853 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2853);
        xn_root_add(xn_t2853);
        xn_root_add(xn_t2853);
        rt_string *xn_t2854 = xn_concat(xn_t2852, xn_t2853);
xn_root_add(xn_t2854);
        xn_root_add(xn_t2854);
        xn_root_add(xn_t2854);
        rt_string *xn_t2855 = rt_retain(name);
xn_root_add(xn_t2855);
        xn_root_add(xn_t2855);
        xn_root_add(xn_t2855);
        rt_string *xn_t2856 = xn_q(xn_t2855);
xn_root_add(xn_t2856);
        xn_root_add(xn_t2856);
        xn_root_add(xn_t2856);
        rt_string *xn_t2857 = xn_concat(xn_t2854, xn_t2856);
xn_root_add(xn_t2857);
        xn_root_add(xn_t2857);
        xn_root_add(xn_t2857);
        rt_string *xn_t2858 = rt_string_from_c(") (Target ");
xn_root_add(xn_t2858);
        xn_root_add(xn_t2858);
        xn_root_add(xn_t2858);
        rt_string *xn_t2859 = xn_concat(xn_t2857, xn_t2858);
xn_root_add(xn_t2859);
        xn_root_add(xn_t2859);
        xn_root_add(xn_t2859);
        rt_string *xn_t2860 = rt_retain(base);
xn_root_add(xn_t2860);
        xn_root_add(xn_t2860);
        xn_root_add(xn_t2860);
        rt_string *xn_t2861 = xn_concat(xn_t2859, xn_t2860);
xn_root_add(xn_t2861);
        xn_root_add(xn_t2861);
        xn_root_add(xn_t2861);
        rt_string *xn_t2862 = rt_string_from_c(") (Methods ");
xn_root_add(xn_t2862);
        xn_root_add(xn_t2862);
        xn_root_add(xn_t2862);
        rt_string *xn_t2863 = xn_concat(xn_t2861, xn_t2862);
xn_root_add(xn_t2863);
        xn_root_add(xn_t2863);
        xn_root_add(xn_t2863);
        rt_string *xn_t2864 = xn_SL(methods);
xn_root_add(xn_t2864);
        xn_root_add(xn_t2864);
        xn_root_add(xn_t2864);
        rt_string *xn_t2865 = xn_concat(xn_t2863, xn_t2864);
xn_root_add(xn_t2865);
        xn_root_add(xn_t2865);
        xn_root_add(xn_t2865);
        rt_string *xn_t2866 = rt_string_from_c("))");
xn_root_add(xn_t2866);
        xn_root_add(xn_t2866);
        xn_root_add(xn_t2866);
        rt_string *xn_t2867 = xn_concat(xn_t2865, xn_t2866);
xn_root_add(xn_t2867);
        xn_root_add(xn_t2867);
        xn_root_add(xn_t2867);
            {
        xn_root_restore(xn_t2841);
            }
            {
        rt_release(base);
            }
            {
        rt_release(primary);
            }
            {
        rt_release(name);
            }
            {
        xn_root_restore(xn_t2440);
            }

        return xn_t2867;

    }
#line 1412 "impl/lib/b2/xparser.x"
rt_string *xn_t2868 = rt_string_from_c("(ExtensionDecl ");
xn_root_add(xn_t2868);
xn_root_add(xn_t2868);
rt_string *xn_t2869 = xn_P(nl, nc);
xn_root_add(xn_t2869);
xn_root_add(xn_t2869);
rt_string *xn_t2870 = xn_concat(xn_t2868, xn_t2869);
xn_root_add(xn_t2870);
xn_root_add(xn_t2870);
rt_string *xn_t2871 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2871);
xn_root_add(xn_t2871);
rt_string *xn_t2872 = xn_concat(xn_t2870, xn_t2871);
xn_root_add(xn_t2872);
xn_root_add(xn_t2872);
rt_string *xn_t2873 = xn_SL(xn_p_annos);
xn_root_add(xn_t2873);
xn_root_add(xn_t2873);
rt_string *xn_t2874 = xn_concat(xn_t2872, xn_t2873);
xn_root_add(xn_t2874);
xn_root_add(xn_t2874);
rt_string *xn_t2875 = rt_string_from_c(") (Mod ");
xn_root_add(xn_t2875);
xn_root_add(xn_t2875);
rt_string *xn_t2876 = xn_concat(xn_t2874, xn_t2875);
xn_root_add(xn_t2876);
xn_root_add(xn_t2876);
rt_string *xn_t2877 = xn_Cls_Parser_modDump(self, xn_p_m);
xn_root_add(xn_t2877);
xn_root_add(xn_t2877);
rt_string *xn_t2878 = xn_concat(xn_t2876, xn_t2877);
xn_root_add(xn_t2878);
xn_root_add(xn_t2878);
rt_string *xn_t2879 = rt_string_from_c(") (Target ");
xn_root_add(xn_t2879);
xn_root_add(xn_t2879);
rt_string *xn_t2880 = xn_concat(xn_t2878, xn_t2879);
xn_root_add(xn_t2880);
xn_root_add(xn_t2880);
rt_string *xn_t2881 = rt_retain(base);
xn_root_add(xn_t2881);
xn_root_add(xn_t2881);
rt_string *xn_t2882 = xn_concat(xn_t2880, xn_t2881);
xn_root_add(xn_t2882);
xn_root_add(xn_t2882);
rt_string *xn_t2883 = rt_string_from_c(") (Methods ");
xn_root_add(xn_t2883);
xn_root_add(xn_t2883);
rt_string *xn_t2884 = xn_concat(xn_t2882, xn_t2883);
xn_root_add(xn_t2884);
xn_root_add(xn_t2884);
rt_string *xn_t2885 = xn_SL(methods);
xn_root_add(xn_t2885);
xn_root_add(xn_t2885);
rt_string *xn_t2886 = xn_concat(xn_t2884, xn_t2885);
xn_root_add(xn_t2886);
xn_root_add(xn_t2886);
rt_string *xn_t2887 = rt_string_from_c("))");
xn_root_add(xn_t2887);
xn_root_add(xn_t2887);
rt_string *xn_t2888 = xn_concat(xn_t2886, xn_t2887);
xn_root_add(xn_t2888);
xn_root_add(xn_t2888);
    {
rt_release(base);
    }
    {
rt_release(primary);
    }
    {
rt_release(name);
    }
    {
xn_root_restore(xn_t2440);
    }

return xn_t2888;
xn_root_release(name);
xn_root_release(primary);
xn_root_release(base);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseModsDump(xn_Cls_Parser *self) {
size_t xn_t2889 = xn_root_mark();
xn_root_add(self);
#line 1417 "impl/lib/b2/xparser.x"
xn_Cls_M * mm = xn_Cls_Parser_parseMods(self);
xn_root_add(mm);
xn_root_add(mm);
xn_gc_safepoint();
#line 1418 "impl/lib/b2/xparser.x"
rt_string *xn_t2890 = xn_Cls_Parser_modDump(self, mm);
xn_root_add(xn_t2890);
xn_root_add(xn_t2890);
    {
xn_root_restore(xn_t2889);
    }

return xn_t2890;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseMember(xn_Cls_Parser *self, rt_string * xn_p_cls, xn_arr_s * xn_p_fields, xn_arr_s * xn_p_methods, xn_arr_s * xn_p_ctors) {
size_t xn_t2891 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_cls);
xn_root_add(xn_p_fields);
xn_root_add(xn_p_methods);
xn_root_add(xn_p_ctors);
#line 1422 "impl/lib/b2/xparser.x"
xn_arr_s * annos = xn_Cls_Parser_parseAnnos(self);
xn_root_add(annos);
xn_root_add(annos);
xn_gc_safepoint();
#line 1423 "impl/lib/b2/xparser.x"
xn_Cls_M * m = xn_Cls_Parser_parseMods(self);
xn_root_add(m);
xn_root_add(m);
xn_gc_safepoint();
#line 1424 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2892 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2892);
int64_t ml = xn_t2892->line;
#line 1425 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2893 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2893);
int64_t mc = xn_t2893->col;
#line 1426 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2894 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2894);
rt_string *xn_t2895 = rt_retain(xn_t2894->text);
xn_root_add(xn_t2895);
rt_string *xn_t2896 = rt_retain(xn_p_cls);
xn_root_add(xn_t2896);
xn_Cls_Tok * xn_t2897 = xn_arr_o_Tok_get(self->toks, (self->i + 1));
xn_root_add(xn_t2897);
    if ((((xn_Cls_Parser_at(self, 2)) && (xn_str_eq(xn_t2895, xn_t2896))) && ((xn_t2897->kind == 10)))) {
        size_t xn_t2898 = xn_root_mark();
        #line 1427 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1428 "impl/lib/b2/xparser.x"
        rt_string *c = xn_Cls_Parser_parseCtor(self, ml, mc, annos);
xn_root_add(c);
        xn_root_add(c);
        xn_root_add(c);
        xn_gc_safepoint();
        #line 1429 "impl/lib/b2/xparser.x"
        rt_string *xn_t2900 = rt_retain(c);
xn_root_add(xn_t2900);
        xn_root_add(xn_t2900);
        xn_arr_s_push(xn_p_ctors, xn_t2900);
        #line 1430 "impl/lib/b2/xparser.x"
        rt_string *xn_t2901 = rt_string_from_c("");
xn_root_add(xn_t2901);
        xn_root_add(xn_t2901);
        xn_root_add(xn_t2901);
            {
        rt_release(c);
            }
            {
        xn_root_restore(xn_t2898);
            }
            {
        xn_root_restore(xn_t2891);
            }

        return xn_t2901;

    }
#line 1432 "impl/lib/b2/xparser.x"
int vd = 0;
#line 1433 "impl/lib/b2/xparser.x"
rt_string *rt = rt_string_from_c("");
xn_root_add(rt);
xn_root_add(rt);
xn_gc_safepoint();
#line 1434 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t2903 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t2903);
rt_string *xn_t2904 = rt_retain(xn_t2903->text);
xn_root_add(xn_t2904);
rt_string *xn_t2905 = rt_string_from_c("void");
xn_root_add(xn_t2905);
    if (((xn_Cls_Parser_at(self, 2)) && (xn_str_eq(xn_t2904, xn_t2905)))) {
        size_t xn_t2906 = xn_root_mark();
        #line 1434 "impl/lib/b2/xparser.x"
        vd = 1;
        #line 1434 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t2906);
            }

    } else {
        size_t xn_t2907 = xn_root_mark();
        #line 1434 "impl/lib/b2/xparser.x"
        rt_string *xn_t2908 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t2908);
        xn_root_add(xn_t2908);
        xn_root_release(rt);
        rt_release(rt);
        rt = xn_t2908;
        xn_root_hold(rt);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t2907);
            }

    }
#line 1435 "impl/lib/b2/xparser.x"
rt_string *nm = rt_string_from_c("");
xn_root_add(nm);
xn_root_add(nm);
xn_gc_safepoint();
#line 1436 "impl/lib/b2/xparser.x"
int64_t nml = ml;
#line 1437 "impl/lib/b2/xparser.x"
int64_t nmc = mc;
#line 1438 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 2))) {
        size_t xn_t2910 = xn_root_mark();
        #line 1438 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * nt = xn_Cls_Parser_next(self);
xn_root_add(nt);
        xn_root_add(nt);
        xn_root_add(nt);
        xn_gc_safepoint();
        #line 1438 "impl/lib/b2/xparser.x"
        rt_string *xn_t2911 = rt_retain(nt->text);
xn_root_add(xn_t2911);
        xn_root_add(xn_t2911);
        xn_root_release(nm);
        rt_release(nm);
        nm = xn_t2911;
        xn_root_hold(nm);
        xn_gc_safepoint();
        #line 1438 "impl/lib/b2/xparser.x"
        nml = nt->line;
        #line 1438 "impl/lib/b2/xparser.x"
        nmc = nt->col;
            {
            xn_root_restore(xn_t2910);
            }

    }
#line 1439 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t2912 = xn_arr_s_new(0);
xn_root_add(xn_t2912);
xn_arr_s * tps = xn_t2912;
xn_root_add(tps);
xn_root_add(tps);
xn_gc_safepoint();
#line 1440 "impl/lib/b2/xparser.x"
rt_string *xn_t2913 = rt_string_from_c("<");
xn_root_add(xn_t2913);
    if ((xn_Cls_Parser_atOp(self, xn_t2913))) {
        size_t xn_t2914 = xn_root_mark();
        #line 1441 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1442 "impl/lib/b2/xparser.x"
            while (1) {
                rt_string *xn_t2915 = rt_string_from_c(">");
xn_root_add(xn_t2915);
        xn_root_add(xn_t2915);
                if (!((((!(xn_Cls_Parser_atOp(self, xn_t2915)))) && ((!(xn_Cls_Parser_eof(self))))))) { break; }
                size_t xn_t2916 = xn_root_mark();
                #line 1442 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 2))) {
                        size_t xn_t2917 = xn_root_mark();
                        #line 1442 "impl/lib/b2/xparser.x"
                        xn_Cls_Tok * xn_t2918 = xn_Cls_Parser_next(self);
xn_root_add(xn_t2918);
        xn_root_add(xn_t2918);
                xn_root_add(xn_t2918);
                        xn_root_add(xn_t2918);
                        rt_string *xn_t2919 = rt_retain(xn_t2918->text);
xn_root_add(xn_t2919);
        xn_root_add(xn_t2919);
                xn_root_add(xn_t2919);
                        xn_root_add(xn_t2919);
                        xn_arr_s_push(tps, xn_t2919);
                            {
                            xn_root_restore(xn_t2917);
                            }

                    } else {
                        size_t xn_t2920 = xn_root_mark();
                        #line 1442 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t2920);
                            }

                    }
                    {
                    xn_root_restore(xn_t2916);
                    }

                xn_gc_safepoint();
            }
        #line 1443 "impl/lib/b2/xparser.x"
        rt_string *xn_t2921 = rt_string_from_c(">");
xn_root_add(xn_t2921);
        xn_root_add(xn_t2921);
            if ((xn_Cls_Parser_atOp(self, xn_t2921))) {
                size_t xn_t2922 = xn_root_mark();
                #line 1443 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t2922);
                    }

            }
            {
            xn_root_restore(xn_t2914);
            }

    }
#line 1445 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 10))) {
        size_t xn_t2923 = xn_root_mark();
        #line 1446 "impl/lib/b2/xparser.x"
        xn_arr_s * ps = xn_Cls_Parser_parseParams(self);
xn_root_add(ps);
        xn_root_add(ps);
        xn_root_add(ps);
        xn_gc_safepoint();
        #line 1447 "impl/lib/b2/xparser.x"
        rt_string *body = xn_Cls_Parser_parseBlock(self);
xn_root_add(body);
        xn_root_add(body);
        xn_root_add(body);
        xn_gc_safepoint();
        #line 1448 "impl/lib/b2/xparser.x"
        rt_string *xn_t2925 = rt_string_from_c("(MethodDecl ");
xn_root_add(xn_t2925);
        xn_root_add(xn_t2925);
        rt_string *xn_t2926 = xn_P(nml, nmc);
xn_root_add(xn_t2926);
        xn_root_add(xn_t2926);
        rt_string *xn_t2927 = xn_concat(xn_t2925, xn_t2926);
xn_root_add(xn_t2927);
        xn_root_add(xn_t2927);
        rt_string *xn_t2928 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2928);
        xn_root_add(xn_t2928);
        rt_string *xn_t2929 = xn_concat(xn_t2927, xn_t2928);
xn_root_add(xn_t2929);
        xn_root_add(xn_t2929);
        rt_string *xn_t2930 = xn_SL(annos);
xn_root_add(xn_t2930);
        xn_root_add(xn_t2930);
        rt_string *xn_t2931 = xn_concat(xn_t2929, xn_t2930);
xn_root_add(xn_t2931);
        xn_root_add(xn_t2931);
        rt_string *xn_t2932 = rt_string_from_c(") (Mod ");
xn_root_add(xn_t2932);
        xn_root_add(xn_t2932);
        rt_string *xn_t2933 = xn_concat(xn_t2931, xn_t2932);
xn_root_add(xn_t2933);
        xn_root_add(xn_t2933);
        rt_string *xn_t2934 = xn_Cls_Parser_modDump(self, m);
xn_root_add(xn_t2934);
        xn_root_add(xn_t2934);
        rt_string *xn_t2935 = xn_concat(xn_t2933, xn_t2934);
xn_root_add(xn_t2935);
        xn_root_add(xn_t2935);
        rt_string *xn_t2936 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2936);
        xn_root_add(xn_t2936);
        rt_string *xn_t2937 = xn_concat(xn_t2935, xn_t2936);
xn_root_add(xn_t2937);
        xn_root_add(xn_t2937);
        rt_string *xn_t2938 = rt_retain(nm);
xn_root_add(xn_t2938);
        xn_root_add(xn_t2938);
        rt_string *xn_t2939 = xn_q(xn_t2938);
xn_root_add(xn_t2939);
        xn_root_add(xn_t2939);
        rt_string *xn_t2940 = xn_concat(xn_t2937, xn_t2939);
xn_root_add(xn_t2940);
        xn_root_add(xn_t2940);
        rt_string *xn_t2941 = rt_string_from_c(") (TypePars ");
xn_root_add(xn_t2941);
        xn_root_add(xn_t2941);
        rt_string *xn_t2942 = xn_concat(xn_t2940, xn_t2941);
xn_root_add(xn_t2942);
        xn_root_add(xn_t2942);
        rt_string *xn_t2943 = xn_SLS(tps);
xn_root_add(xn_t2943);
        xn_root_add(xn_t2943);
        rt_string *xn_t2944 = xn_concat(xn_t2942, xn_t2943);
xn_root_add(xn_t2944);
        xn_root_add(xn_t2944);
        rt_string *xn_t2945 = rt_string_from_c(") (Void ");
xn_root_add(xn_t2945);
        xn_root_add(xn_t2945);
        rt_string *xn_t2946 = xn_concat(xn_t2944, xn_t2945);
xn_root_add(xn_t2946);
        xn_root_add(xn_t2946);
        rt_string *xn_t2947 = xn_B(vd);
xn_root_add(xn_t2947);
        xn_root_add(xn_t2947);
        rt_string *xn_t2948 = xn_concat(xn_t2946, xn_t2947);
xn_root_add(xn_t2948);
        xn_root_add(xn_t2948);
        rt_string *xn_t2949 = rt_string_from_c(") (Ret ");
xn_root_add(xn_t2949);
        xn_root_add(xn_t2949);
        rt_string *xn_t2950 = xn_concat(xn_t2948, xn_t2949);
xn_root_add(xn_t2950);
        xn_root_add(xn_t2950);
        rt_string *xn_t2951 = rt_retain(rt);
xn_root_add(xn_t2951);
        xn_root_add(xn_t2951);
        rt_string *xn_t2952 = xn_Cls_Parser_retv(self, vd, xn_t2951);
xn_root_add(xn_t2952);
        xn_root_add(xn_t2952);
        rt_string *xn_t2953 = xn_concat(xn_t2950, xn_t2952);
xn_root_add(xn_t2953);
        xn_root_add(xn_t2953);
        rt_string *xn_t2954 = rt_string_from_c(") (Params ");
xn_root_add(xn_t2954);
        xn_root_add(xn_t2954);
        rt_string *xn_t2955 = xn_concat(xn_t2953, xn_t2954);
xn_root_add(xn_t2955);
        xn_root_add(xn_t2955);
        rt_string *xn_t2956 = xn_SL(ps);
xn_root_add(xn_t2956);
        xn_root_add(xn_t2956);
        rt_string *xn_t2957 = xn_concat(xn_t2955, xn_t2956);
xn_root_add(xn_t2957);
        xn_root_add(xn_t2957);
        rt_string *xn_t2958 = rt_string_from_c(") (Body ");
xn_root_add(xn_t2958);
        xn_root_add(xn_t2958);
        rt_string *xn_t2959 = xn_concat(xn_t2957, xn_t2958);
xn_root_add(xn_t2959);
        xn_root_add(xn_t2959);
        rt_string *xn_t2960 = rt_retain(body);
xn_root_add(xn_t2960);
        xn_root_add(xn_t2960);
        rt_string *xn_t2961 = xn_concat(xn_t2959, xn_t2960);
xn_root_add(xn_t2961);
        xn_root_add(xn_t2961);
        rt_string *xn_t2962 = rt_string_from_c(") (IsDeinit ");
xn_root_add(xn_t2962);
        xn_root_add(xn_t2962);
        rt_string *xn_t2963 = xn_concat(xn_t2961, xn_t2962);
xn_root_add(xn_t2963);
        xn_root_add(xn_t2963);
        rt_string *xn_t2964 = rt_retain(nm);
xn_root_add(xn_t2964);
        xn_root_add(xn_t2964);
        rt_string *xn_t2965 = rt_string_from_c("deinit");
xn_root_add(xn_t2965);
        xn_root_add(xn_t2965);
        rt_string *xn_t2966 = xn_B(xn_str_eq(xn_t2964, xn_t2965));
xn_root_add(xn_t2966);
        xn_root_add(xn_t2966);
        rt_string *xn_t2967 = xn_concat(xn_t2963, xn_t2966);
xn_root_add(xn_t2967);
        xn_root_add(xn_t2967);
        rt_string *xn_t2968 = rt_string_from_c("))");
xn_root_add(xn_t2968);
        xn_root_add(xn_t2968);
        rt_string *xn_t2969 = xn_concat(xn_t2967, xn_t2968);
xn_root_add(xn_t2969);
        xn_root_add(xn_t2969);
        xn_arr_s_push(xn_p_methods, xn_t2969);
        #line 1451 "impl/lib/b2/xparser.x"
        rt_string *xn_t2970 = rt_string_from_c("");
xn_root_add(xn_t2970);
        xn_root_add(xn_t2970);
        xn_root_add(xn_t2970);
            {
        rt_release(body);
            }
            {
        xn_root_restore(xn_t2923);
            }
            {
        rt_release(nm);
            }
            {
        rt_release(rt);
            }
            {
        xn_root_restore(xn_t2891);
            }

        return xn_t2970;

    }
#line 1453 "impl/lib/b2/xparser.x"
rt_string *init = rt_string_from_c("(nil)");
xn_root_add(init);
xn_root_add(init);
xn_gc_safepoint();
#line 1454 "impl/lib/b2/xparser.x"
rt_string *xn_t2972 = rt_string_from_c("=");
xn_root_add(xn_t2972);
    if ((xn_Cls_Parser_atOp(self, xn_t2972))) {
        size_t xn_t2973 = xn_root_mark();
        #line 1454 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1454 "impl/lib/b2/xparser.x"
        xn_Cls_E * xn_t2974 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t2974);
        xn_root_add(xn_t2974);
        rt_string *xn_t2975 = rt_retain(xn_t2974->d);
xn_root_add(xn_t2975);
        xn_root_add(xn_t2975);
        xn_root_release(init);
        rt_release(init);
        init = xn_t2975;
        xn_root_hold(init);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t2973);
            }

    }
#line 1455 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 1))) {
        size_t xn_t2976 = xn_root_mark();
        #line 1455 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t2976);
            }

    }
#line 1456 "impl/lib/b2/xparser.x"
rt_string *xn_t2977 = rt_string_from_c("(FieldDecl ");
xn_root_add(xn_t2977);
rt_string *xn_t2978 = xn_P(nml, nmc);
xn_root_add(xn_t2978);
rt_string *xn_t2979 = xn_concat(xn_t2977, xn_t2978);
xn_root_add(xn_t2979);
rt_string *xn_t2980 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t2980);
rt_string *xn_t2981 = xn_concat(xn_t2979, xn_t2980);
xn_root_add(xn_t2981);
rt_string *xn_t2982 = xn_SL(annos);
xn_root_add(xn_t2982);
rt_string *xn_t2983 = xn_concat(xn_t2981, xn_t2982);
xn_root_add(xn_t2983);
rt_string *xn_t2984 = rt_string_from_c(") (Mod ");
xn_root_add(xn_t2984);
rt_string *xn_t2985 = xn_concat(xn_t2983, xn_t2984);
xn_root_add(xn_t2985);
rt_string *xn_t2986 = xn_Cls_Parser_modDump(self, m);
xn_root_add(xn_t2986);
rt_string *xn_t2987 = xn_concat(xn_t2985, xn_t2986);
xn_root_add(xn_t2987);
rt_string *xn_t2988 = rt_string_from_c(") (Type ");
xn_root_add(xn_t2988);
rt_string *xn_t2989 = xn_concat(xn_t2987, xn_t2988);
xn_root_add(xn_t2989);
rt_string *xn_t2990 = rt_retain(rt);
xn_root_add(xn_t2990);
rt_string *xn_t2991 = xn_concat(xn_t2989, xn_t2990);
xn_root_add(xn_t2991);
rt_string *xn_t2992 = rt_string_from_c(") (Name ");
xn_root_add(xn_t2992);
rt_string *xn_t2993 = xn_concat(xn_t2991, xn_t2992);
xn_root_add(xn_t2993);
rt_string *xn_t2994 = rt_retain(nm);
xn_root_add(xn_t2994);
rt_string *xn_t2995 = xn_q(xn_t2994);
xn_root_add(xn_t2995);
rt_string *xn_t2996 = xn_concat(xn_t2993, xn_t2995);
xn_root_add(xn_t2996);
rt_string *xn_t2997 = rt_string_from_c(") (Canonical \"\") (Init ");
xn_root_add(xn_t2997);
rt_string *xn_t2998 = xn_concat(xn_t2996, xn_t2997);
xn_root_add(xn_t2998);
rt_string *xn_t2999 = rt_retain(init);
xn_root_add(xn_t2999);
rt_string *xn_t3000 = xn_concat(xn_t2998, xn_t2999);
xn_root_add(xn_t3000);
rt_string *xn_t3001 = rt_string_from_c("))");
xn_root_add(xn_t3001);
rt_string *xn_t3002 = xn_concat(xn_t3000, xn_t3001);
xn_root_add(xn_t3002);
xn_arr_s_push(xn_p_fields, xn_t3002);
#line 1458 "impl/lib/b2/xparser.x"
rt_string *xn_t3003 = rt_string_from_c("");
xn_root_add(xn_t3003);
xn_root_add(xn_t3003);
    {
rt_release(init);
    }
    {
rt_release(nm);
    }
    {
rt_release(rt);
    }
    {
xn_root_restore(xn_t2891);
    }

return xn_t3003;
xn_root_release(rt);
xn_root_release(nm);
xn_root_release(init);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseField(xn_Cls_Parser *self) {
size_t xn_t3004 = xn_root_mark();
xn_root_add(self);
#line 1462 "impl/lib/b2/xparser.x"
xn_arr_s * annos = xn_Cls_Parser_parseAnnos(self);
xn_root_add(annos);
xn_root_add(annos);
xn_gc_safepoint();
#line 1463 "impl/lib/b2/xparser.x"
xn_Cls_M * m = xn_Cls_Parser_parseMods(self);
xn_root_add(m);
xn_root_add(m);
xn_gc_safepoint();
#line 1464 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t3005 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3005);
int64_t l = xn_t3005->line;
#line 1465 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t3006 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3006);
int64_t c = xn_t3006->col;
#line 1466 "impl/lib/b2/xparser.x"
rt_string *ty = xn_Cls_Parser_parseType(self);
xn_root_add(ty);
xn_root_add(ty);
xn_gc_safepoint();
#line 1467 "impl/lib/b2/xparser.x"
rt_string *nm = rt_string_from_c("");
xn_root_add(nm);
xn_root_add(nm);
xn_gc_safepoint();
#line 1468 "impl/lib/b2/xparser.x"
int64_t nml = l;
#line 1469 "impl/lib/b2/xparser.x"
int64_t nmc = c;
#line 1470 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 2))) {
        size_t xn_t3009 = xn_root_mark();
        #line 1470 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * nt = xn_Cls_Parser_next(self);
xn_root_add(nt);
        xn_root_add(nt);
        xn_root_add(nt);
        xn_gc_safepoint();
        #line 1470 "impl/lib/b2/xparser.x"
        rt_string *xn_t3010 = rt_retain(nt->text);
xn_root_add(xn_t3010);
        xn_root_add(xn_t3010);
        xn_root_release(nm);
        rt_release(nm);
        nm = xn_t3010;
        xn_root_hold(nm);
        xn_gc_safepoint();
        #line 1470 "impl/lib/b2/xparser.x"
        nml = nt->line;
        #line 1470 "impl/lib/b2/xparser.x"
        nmc = nt->col;
            {
            xn_root_restore(xn_t3009);
            }

    }
#line 1471 "impl/lib/b2/xparser.x"
rt_string *init = rt_string_from_c("(nil)");
xn_root_add(init);
xn_root_add(init);
xn_gc_safepoint();
#line 1472 "impl/lib/b2/xparser.x"
rt_string *xn_t3012 = rt_string_from_c("=");
xn_root_add(xn_t3012);
    if ((xn_Cls_Parser_atOp(self, xn_t3012))) {
        size_t xn_t3013 = xn_root_mark();
        #line 1472 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1472 "impl/lib/b2/xparser.x"
        xn_Cls_E * xn_t3014 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t3014);
        xn_root_add(xn_t3014);
        rt_string *xn_t3015 = rt_retain(xn_t3014->d);
xn_root_add(xn_t3015);
        xn_root_add(xn_t3015);
        xn_root_release(init);
        rt_release(init);
        init = xn_t3015;
        xn_root_hold(init);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t3013);
            }

    }
#line 1473 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 1))) {
        size_t xn_t3016 = xn_root_mark();
        #line 1473 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3016);
            }

    }
#line 1474 "impl/lib/b2/xparser.x"
rt_string *xn_t3017 = rt_string_from_c("(FieldDecl ");
xn_root_add(xn_t3017);
xn_root_add(xn_t3017);
rt_string *xn_t3018 = xn_P(nml, nmc);
xn_root_add(xn_t3018);
xn_root_add(xn_t3018);
rt_string *xn_t3019 = xn_concat(xn_t3017, xn_t3018);
xn_root_add(xn_t3019);
xn_root_add(xn_t3019);
rt_string *xn_t3020 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t3020);
xn_root_add(xn_t3020);
rt_string *xn_t3021 = xn_concat(xn_t3019, xn_t3020);
xn_root_add(xn_t3021);
xn_root_add(xn_t3021);
rt_string *xn_t3022 = xn_SL(annos);
xn_root_add(xn_t3022);
xn_root_add(xn_t3022);
rt_string *xn_t3023 = xn_concat(xn_t3021, xn_t3022);
xn_root_add(xn_t3023);
xn_root_add(xn_t3023);
rt_string *xn_t3024 = rt_string_from_c(") (Mod ");
xn_root_add(xn_t3024);
xn_root_add(xn_t3024);
rt_string *xn_t3025 = xn_concat(xn_t3023, xn_t3024);
xn_root_add(xn_t3025);
xn_root_add(xn_t3025);
rt_string *xn_t3026 = xn_Cls_Parser_modDump(self, m);
xn_root_add(xn_t3026);
xn_root_add(xn_t3026);
rt_string *xn_t3027 = xn_concat(xn_t3025, xn_t3026);
xn_root_add(xn_t3027);
xn_root_add(xn_t3027);
rt_string *xn_t3028 = rt_string_from_c(") (Type ");
xn_root_add(xn_t3028);
xn_root_add(xn_t3028);
rt_string *xn_t3029 = xn_concat(xn_t3027, xn_t3028);
xn_root_add(xn_t3029);
xn_root_add(xn_t3029);
rt_string *xn_t3030 = rt_retain(ty);
xn_root_add(xn_t3030);
xn_root_add(xn_t3030);
rt_string *xn_t3031 = xn_concat(xn_t3029, xn_t3030);
xn_root_add(xn_t3031);
xn_root_add(xn_t3031);
rt_string *xn_t3032 = rt_string_from_c(") (Name ");
xn_root_add(xn_t3032);
xn_root_add(xn_t3032);
rt_string *xn_t3033 = xn_concat(xn_t3031, xn_t3032);
xn_root_add(xn_t3033);
xn_root_add(xn_t3033);
rt_string *xn_t3034 = rt_retain(nm);
xn_root_add(xn_t3034);
xn_root_add(xn_t3034);
rt_string *xn_t3035 = xn_q(xn_t3034);
xn_root_add(xn_t3035);
xn_root_add(xn_t3035);
rt_string *xn_t3036 = xn_concat(xn_t3033, xn_t3035);
xn_root_add(xn_t3036);
xn_root_add(xn_t3036);
rt_string *xn_t3037 = rt_string_from_c(") (Canonical \"\") (Init ");
xn_root_add(xn_t3037);
xn_root_add(xn_t3037);
rt_string *xn_t3038 = xn_concat(xn_t3036, xn_t3037);
xn_root_add(xn_t3038);
xn_root_add(xn_t3038);
rt_string *xn_t3039 = rt_retain(init);
xn_root_add(xn_t3039);
xn_root_add(xn_t3039);
rt_string *xn_t3040 = xn_concat(xn_t3038, xn_t3039);
xn_root_add(xn_t3040);
xn_root_add(xn_t3040);
rt_string *xn_t3041 = rt_string_from_c("))");
xn_root_add(xn_t3041);
xn_root_add(xn_t3041);
rt_string *xn_t3042 = xn_concat(xn_t3040, xn_t3041);
xn_root_add(xn_t3042);
xn_root_add(xn_t3042);
    {
rt_release(init);
    }
    {
rt_release(nm);
    }
    {
rt_release(ty);
    }
    {
xn_root_restore(xn_t3004);
    }

return xn_t3042;
xn_root_release(nm);
xn_root_release(init);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseCtor(xn_Cls_Parser *self, int64_t xn_p_l, int64_t xn_p_c, xn_arr_s * xn_p_annos) {
size_t xn_t3043 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_annos);
#line 1479 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t3044 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3044);
int64_t pl = xn_t3044->line;
#line 1480 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t3045 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3045);
int64_t pc = xn_t3045->col;
#line 1481 "impl/lib/b2/xparser.x"
xn_arr_s * ps = xn_Cls_Parser_parseParams(self);
xn_root_add(ps);
xn_root_add(ps);
xn_gc_safepoint();
#line 1482 "impl/lib/b2/xparser.x"
rt_string *body = xn_Cls_Parser_parseBlock(self);
xn_root_add(body);
xn_root_add(body);
xn_gc_safepoint();
#line 1483 "impl/lib/b2/xparser.x"
rt_string *xn_t3047 = rt_string_from_c("(CtorDecl ");
xn_root_add(xn_t3047);
xn_root_add(xn_t3047);
rt_string *xn_t3048 = xn_P(pl, pc);
xn_root_add(xn_t3048);
xn_root_add(xn_t3048);
rt_string *xn_t3049 = xn_concat(xn_t3047, xn_t3048);
xn_root_add(xn_t3049);
xn_root_add(xn_t3049);
rt_string *xn_t3050 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t3050);
xn_root_add(xn_t3050);
rt_string *xn_t3051 = xn_concat(xn_t3049, xn_t3050);
xn_root_add(xn_t3051);
xn_root_add(xn_t3051);
rt_string *xn_t3052 = xn_SL(xn_p_annos);
xn_root_add(xn_t3052);
xn_root_add(xn_t3052);
rt_string *xn_t3053 = xn_concat(xn_t3051, xn_t3052);
xn_root_add(xn_t3053);
xn_root_add(xn_t3053);
rt_string *xn_t3054 = rt_string_from_c(") (Mod (TypeModifiers (Vis \"\") (Abstract false) (Final false) (Static false) (Const false))) (Params ");
xn_root_add(xn_t3054);
xn_root_add(xn_t3054);
rt_string *xn_t3055 = xn_concat(xn_t3053, xn_t3054);
xn_root_add(xn_t3055);
xn_root_add(xn_t3055);
rt_string *xn_t3056 = xn_SL(ps);
xn_root_add(xn_t3056);
xn_root_add(xn_t3056);
rt_string *xn_t3057 = xn_concat(xn_t3055, xn_t3056);
xn_root_add(xn_t3057);
xn_root_add(xn_t3057);
rt_string *xn_t3058 = rt_string_from_c(") (Body ");
xn_root_add(xn_t3058);
xn_root_add(xn_t3058);
rt_string *xn_t3059 = xn_concat(xn_t3057, xn_t3058);
xn_root_add(xn_t3059);
xn_root_add(xn_t3059);
rt_string *xn_t3060 = rt_retain(body);
xn_root_add(xn_t3060);
xn_root_add(xn_t3060);
rt_string *xn_t3061 = xn_concat(xn_t3059, xn_t3060);
xn_root_add(xn_t3061);
xn_root_add(xn_t3061);
rt_string *xn_t3062 = rt_string_from_c("))");
xn_root_add(xn_t3062);
xn_root_add(xn_t3062);
rt_string *xn_t3063 = xn_concat(xn_t3061, xn_t3062);
xn_root_add(xn_t3063);
xn_root_add(xn_t3063);
    {
rt_release(body);
    }
    {
xn_root_restore(xn_t3043);
    }

return xn_t3063;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseAnnotationDecl(xn_Cls_Parser *self, int64_t xn_p_sl, int64_t xn_p_sc, xn_arr_s * xn_p_annos) {
size_t xn_t3064 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_annos);
#line 1487 "impl/lib/b2/xparser.x"
xn_Cls_Parser_next(self);
#line 1488 "impl/lib/b2/xparser.x"
rt_string *name = rt_string_from_c("");
xn_root_add(name);
xn_root_add(name);
xn_gc_safepoint();
#line 1489 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 2))) {
        size_t xn_t3066 = xn_root_mark();
        #line 1489 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3067 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3067);
        xn_root_add(xn_t3067);
        rt_string *xn_t3068 = rt_retain(xn_t3067->text);
xn_root_add(xn_t3068);
        xn_root_add(xn_t3068);
        xn_root_release(name);
        rt_release(name);
        name = xn_t3068;
        xn_root_hold(name);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t3066);
            }

    }
#line 1490 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 12))) {
        size_t xn_t3069 = xn_root_mark();
        #line 1490 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3069);
            }

    }
#line 1491 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t3070 = xn_arr_s_new(0);
xn_root_add(xn_t3070);
xn_arr_s * fs = xn_t3070;
xn_root_add(fs);
xn_root_add(fs);
xn_gc_safepoint();
#line 1492 "impl/lib/b2/xparser.x"
    while ((((!(xn_Cls_Parser_at(self, 13)))) && ((!(xn_Cls_Parser_eof(self)))))) {
    size_t xn_t3071 = xn_root_mark();
    #line 1493 "impl/lib/b2/xparser.x"
        if ((xn_Cls_Parser_at(self, 1))) {
            size_t xn_t3072 = xn_root_mark();
            #line 1493 "impl/lib/b2/xparser.x"
            xn_Cls_Parser_next(self);
            #line 1493 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t3072);
            xn_root_restore(xn_t3071);
            continue;
                {
                xn_root_restore(xn_t3072);
                }

        }
    #line 1494 "impl/lib/b2/xparser.x"
    rt_string *xn_t3073 = xn_Cls_Parser_parseField(self);
xn_root_add(xn_t3073);
    xn_root_add(xn_t3073);
    xn_arr_s_push(fs, xn_t3073);
        {
        xn_root_restore(xn_t3071);
        }

    xn_gc_safepoint();
    }
#line 1496 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 13))) {
        size_t xn_t3074 = xn_root_mark();
        #line 1496 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3074);
            }

    }
#line 1497 "impl/lib/b2/xparser.x"
rt_string *xn_t3075 = rt_string_from_c("(AnnotationDecl ");
xn_root_add(xn_t3075);
xn_root_add(xn_t3075);
rt_string *xn_t3076 = xn_P(xn_p_sl, xn_p_sc);
xn_root_add(xn_t3076);
xn_root_add(xn_t3076);
rt_string *xn_t3077 = xn_concat(xn_t3075, xn_t3076);
xn_root_add(xn_t3077);
xn_root_add(xn_t3077);
rt_string *xn_t3078 = rt_string_from_c(" (Annos ");
xn_root_add(xn_t3078);
xn_root_add(xn_t3078);
rt_string *xn_t3079 = xn_concat(xn_t3077, xn_t3078);
xn_root_add(xn_t3079);
xn_root_add(xn_t3079);
rt_string *xn_t3080 = xn_SL(xn_p_annos);
xn_root_add(xn_t3080);
xn_root_add(xn_t3080);
rt_string *xn_t3081 = xn_concat(xn_t3079, xn_t3080);
xn_root_add(xn_t3081);
xn_root_add(xn_t3081);
rt_string *xn_t3082 = rt_string_from_c(") (Mod (TypeModifiers (Vis \"\") (Abstract false) (Final false) (Static false) (Const false))) (Name ");
xn_root_add(xn_t3082);
xn_root_add(xn_t3082);
rt_string *xn_t3083 = xn_concat(xn_t3081, xn_t3082);
xn_root_add(xn_t3083);
xn_root_add(xn_t3083);
rt_string *xn_t3084 = rt_retain(name);
xn_root_add(xn_t3084);
xn_root_add(xn_t3084);
rt_string *xn_t3085 = xn_q(xn_t3084);
xn_root_add(xn_t3085);
xn_root_add(xn_t3085);
rt_string *xn_t3086 = xn_concat(xn_t3083, xn_t3085);
xn_root_add(xn_t3086);
xn_root_add(xn_t3086);
rt_string *xn_t3087 = rt_string_from_c(") (Fields ");
xn_root_add(xn_t3087);
xn_root_add(xn_t3087);
rt_string *xn_t3088 = xn_concat(xn_t3086, xn_t3087);
xn_root_add(xn_t3088);
xn_root_add(xn_t3088);
rt_string *xn_t3089 = xn_SL(fs);
xn_root_add(xn_t3089);
xn_root_add(xn_t3089);
rt_string *xn_t3090 = xn_concat(xn_t3088, xn_t3089);
xn_root_add(xn_t3090);
xn_root_add(xn_t3090);
rt_string *xn_t3091 = rt_string_from_c("))");
xn_root_add(xn_t3091);
xn_root_add(xn_t3091);
rt_string *xn_t3092 = xn_concat(xn_t3090, xn_t3091);
xn_root_add(xn_t3092);
xn_root_add(xn_t3092);
    {
rt_release(name);
    }
    {
xn_root_restore(xn_t3064);
    }

return xn_t3092;
xn_root_release(name);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseParam(xn_Cls_Parser *self) {
size_t xn_t3093 = xn_root_mark();
xn_root_add(self);
#line 1502 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t3094 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3094);
int64_t sl = xn_t3094->line;
#line 1503 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t3095 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3095);
int64_t sc = xn_t3095->col;
#line 1504 "impl/lib/b2/xparser.x"
int fin = 0;
#line 1505 "impl/lib/b2/xparser.x"
rt_string *xn_t3096 = rt_string_from_c("final");
xn_root_add(xn_t3096);
    if ((xn_Cls_Parser_atKw(self, xn_t3096))) {
        size_t xn_t3097 = xn_root_mark();
        #line 1505 "impl/lib/b2/xparser.x"
        fin = 1;
        #line 1505 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3097);
            }

    }
#line 1506 "impl/lib/b2/xparser.x"
rt_string *ty = xn_Cls_Parser_parseType(self);
xn_root_add(ty);
xn_root_add(ty);
xn_gc_safepoint();
#line 1507 "impl/lib/b2/xparser.x"
rt_string *nm = rt_string_from_c("");
xn_root_add(nm);
xn_root_add(nm);
xn_gc_safepoint();
#line 1508 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 2))) {
        size_t xn_t3100 = xn_root_mark();
        #line 1508 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3101 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3101);
        xn_root_add(xn_t3101);
        rt_string *xn_t3102 = rt_retain(xn_t3101->text);
xn_root_add(xn_t3102);
        xn_root_add(xn_t3102);
        xn_root_release(nm);
        rt_release(nm);
        nm = xn_t3102;
        xn_root_hold(nm);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t3100);
            }

    }
#line 1509 "impl/lib/b2/xparser.x"
rt_string *xn_t3103 = rt_string_from_c("(Param ");
xn_root_add(xn_t3103);
xn_root_add(xn_t3103);
rt_string *xn_t3104 = xn_P(sl, sc);
xn_root_add(xn_t3104);
xn_root_add(xn_t3104);
rt_string *xn_t3105 = xn_concat(xn_t3103, xn_t3104);
xn_root_add(xn_t3105);
xn_root_add(xn_t3105);
rt_string *xn_t3106 = rt_string_from_c(" (Annos (slice)) (Final ");
xn_root_add(xn_t3106);
xn_root_add(xn_t3106);
rt_string *xn_t3107 = xn_concat(xn_t3105, xn_t3106);
xn_root_add(xn_t3107);
xn_root_add(xn_t3107);
rt_string *xn_t3108 = xn_B(fin);
xn_root_add(xn_t3108);
xn_root_add(xn_t3108);
rt_string *xn_t3109 = xn_concat(xn_t3107, xn_t3108);
xn_root_add(xn_t3109);
xn_root_add(xn_t3109);
rt_string *xn_t3110 = rt_string_from_c(") (Type ");
xn_root_add(xn_t3110);
xn_root_add(xn_t3110);
rt_string *xn_t3111 = xn_concat(xn_t3109, xn_t3110);
xn_root_add(xn_t3111);
xn_root_add(xn_t3111);
rt_string *xn_t3112 = rt_retain(ty);
xn_root_add(xn_t3112);
xn_root_add(xn_t3112);
rt_string *xn_t3113 = xn_concat(xn_t3111, xn_t3112);
xn_root_add(xn_t3113);
xn_root_add(xn_t3113);
rt_string *xn_t3114 = rt_string_from_c(") (Name ");
xn_root_add(xn_t3114);
xn_root_add(xn_t3114);
rt_string *xn_t3115 = xn_concat(xn_t3113, xn_t3114);
xn_root_add(xn_t3115);
xn_root_add(xn_t3115);
rt_string *xn_t3116 = rt_retain(nm);
xn_root_add(xn_t3116);
xn_root_add(xn_t3116);
rt_string *xn_t3117 = xn_q(xn_t3116);
xn_root_add(xn_t3117);
xn_root_add(xn_t3117);
rt_string *xn_t3118 = xn_concat(xn_t3115, xn_t3117);
xn_root_add(xn_t3118);
xn_root_add(xn_t3118);
rt_string *xn_t3119 = rt_string_from_c("))");
xn_root_add(xn_t3119);
xn_root_add(xn_t3119);
rt_string *xn_t3120 = xn_concat(xn_t3118, xn_t3119);
xn_root_add(xn_t3120);
xn_root_add(xn_t3120);
    {
rt_release(nm);
    }
    {
rt_release(ty);
    }
    {
xn_root_restore(xn_t3093);
    }

return xn_t3120;
xn_root_release(nm);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseType(xn_Cls_Parser *self) {
size_t xn_t3121 = xn_root_mark();
xn_root_add(self);
#line 1513 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_cur(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1514 "impl/lib/b2/xparser.x"
rt_string *base = rt_string_from_c("");
xn_root_add(base);
xn_root_add(base);
xn_gc_safepoint();
#line 1515 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 10))) {
        size_t xn_t3123 = xn_root_mark();
        #line 1516 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1517 "impl/lib/b2/xparser.x"
        xn_arr_s *xn_t3124 = xn_arr_s_new(0);
xn_root_add(xn_t3124);
        xn_root_add(xn_t3124);
        xn_arr_s * es = xn_t3124;
xn_root_add(es);
        xn_root_add(es);
        xn_root_add(es);
        xn_gc_safepoint();
        #line 1518 "impl/lib/b2/xparser.x"
            while ((((!(xn_Cls_Parser_at(self, 11)))) && ((!(xn_Cls_Parser_eof(self)))))) {
            size_t xn_t3125 = xn_root_mark();
            #line 1519 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 16))) {
                    size_t xn_t3126 = xn_root_mark();
                    #line 1519 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 1519 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t3126);
                    xn_root_restore(xn_t3125);
                    continue;
                        {
                        xn_root_restore(xn_t3126);
                        }

                }
            #line 1520 "impl/lib/b2/xparser.x"
            rt_string *xn_t3127 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t3127);
        xn_root_add(xn_t3127);
            xn_root_add(xn_t3127);
            xn_arr_s_push(es, xn_t3127);
                {
                xn_root_restore(xn_t3125);
                }

            xn_gc_safepoint();
            }
        #line 1522 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 11))) {
                size_t xn_t3128 = xn_root_mark();
                #line 1522 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t3128);
                    }

            }
        #line 1523 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * after = xn_Cls_Parser_cur(self);
xn_root_add(after);
        xn_root_add(after);
        xn_root_add(after);
        xn_gc_safepoint();
        #line 1524 "impl/lib/b2/xparser.x"
        rt_string *xn_t3129 = rt_string_from_c("(TupleTypeRef ");
xn_root_add(xn_t3129);
        xn_root_add(xn_t3129);
        rt_string *xn_t3130 = xn_P(after->line, after->col);
xn_root_add(xn_t3130);
        xn_root_add(xn_t3130);
        rt_string *xn_t3131 = xn_concat(xn_t3129, xn_t3130);
xn_root_add(xn_t3131);
        xn_root_add(xn_t3131);
        rt_string *xn_t3132 = rt_string_from_c(" (Elems ");
xn_root_add(xn_t3132);
        xn_root_add(xn_t3132);
        rt_string *xn_t3133 = xn_concat(xn_t3131, xn_t3132);
xn_root_add(xn_t3133);
        xn_root_add(xn_t3133);
        rt_string *xn_t3134 = xn_SL(es);
xn_root_add(xn_t3134);
        xn_root_add(xn_t3134);
        rt_string *xn_t3135 = xn_concat(xn_t3133, xn_t3134);
xn_root_add(xn_t3135);
        xn_root_add(xn_t3135);
        rt_string *xn_t3136 = rt_string_from_c("))");
xn_root_add(xn_t3136);
        xn_root_add(xn_t3136);
        rt_string *xn_t3137 = xn_concat(xn_t3135, xn_t3136);
xn_root_add(xn_t3137);
        xn_root_add(xn_t3137);
        xn_root_release(base);
        rt_release(base);
        base = xn_t3137;
        xn_root_hold(base);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t3123);
            }

    } else {
        size_t xn_t3138 = xn_root_mark();
        #line 1526 "impl/lib/b2/xparser.x"
        xn_arr_s *xn_t3139 = xn_arr_s_new(0);
xn_root_add(xn_t3139);
        xn_root_add(xn_t3139);
        xn_arr_s * qn = xn_t3139;
xn_root_add(qn);
        xn_root_add(qn);
        xn_root_add(qn);
        xn_gc_safepoint();
        #line 1527 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 2))) {
                size_t xn_t3140 = xn_root_mark();
                #line 1527 "impl/lib/b2/xparser.x"
                xn_Cls_Tok * xn_t3141 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3141);
        xn_root_add(xn_t3141);
                xn_root_add(xn_t3141);
                rt_string *xn_t3142 = rt_retain(xn_t3141->text);
xn_root_add(xn_t3142);
        xn_root_add(xn_t3142);
                xn_root_add(xn_t3142);
                xn_arr_s_push(qn, xn_t3142);
                    {
                    xn_root_restore(xn_t3140);
                    }

            }
        #line 1528 "impl/lib/b2/xparser.x"
            while (1) {
                rt_string *xn_t3143 = rt_string_from_c(".");
xn_root_add(xn_t3143);
        xn_root_add(xn_t3143);
                if (!((xn_Cls_Parser_atOp(self, xn_t3143)))) { break; }
                size_t xn_t3144 = xn_root_mark();
                #line 1529 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                #line 1530 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 2))) {
                        size_t xn_t3145 = xn_root_mark();
                        #line 1530 "impl/lib/b2/xparser.x"
                        xn_Cls_Tok * xn_t3146 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3146);
        xn_root_add(xn_t3146);
                xn_root_add(xn_t3146);
                        xn_root_add(xn_t3146);
                        rt_string *xn_t3147 = rt_retain(xn_t3146->text);
xn_root_add(xn_t3147);
        xn_root_add(xn_t3147);
                xn_root_add(xn_t3147);
                        xn_root_add(xn_t3147);
                        xn_arr_s_push(qn, xn_t3147);
                            {
                            xn_root_restore(xn_t3145);
                            }

                    }
                    {
                    xn_root_restore(xn_t3144);
                    }

                xn_gc_safepoint();
            }
        #line 1532 "impl/lib/b2/xparser.x"
        xn_arr_s *xn_t3148 = xn_arr_s_new(0);
xn_root_add(xn_t3148);
        xn_root_add(xn_t3148);
        xn_arr_s * tas = xn_t3148;
xn_root_add(tas);
        xn_root_add(tas);
        xn_root_add(tas);
        xn_gc_safepoint();
        #line 1533 "impl/lib/b2/xparser.x"
        rt_string *xn_t3149 = rt_string_from_c("<");
xn_root_add(xn_t3149);
        xn_root_add(xn_t3149);
            if ((xn_Cls_Parser_atOp(self, xn_t3149))) {
                size_t xn_t3150 = xn_root_mark();
                #line 1534 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                #line 1535 "impl/lib/b2/xparser.x"
                    while (1) {
                        rt_string *xn_t3151 = rt_string_from_c(">");
xn_root_add(xn_t3151);
        xn_root_add(xn_t3151);
                xn_root_add(xn_t3151);
                        if (!((((!(xn_Cls_Parser_atOp(self, xn_t3151)))) && ((!(xn_Cls_Parser_eof(self))))))) { break; }
                        size_t xn_t3152 = xn_root_mark();
                        #line 1536 "impl/lib/b2/xparser.x"
                            if ((xn_Cls_Parser_at(self, 16))) {
                                size_t xn_t3153 = xn_root_mark();
                                #line 1536 "impl/lib/b2/xparser.x"
                                xn_Cls_Parser_next(self);
                                #line 1536 "impl/lib/b2/xparser.x"
                                xn_root_restore(xn_t3153);
                                xn_root_restore(xn_t3152);
                                continue;
                                    {
                                    xn_root_restore(xn_t3153);
                                    }

                            }
                        #line 1537 "impl/lib/b2/xparser.x"
                        xn_Cls_Tok * xn_t3154 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3154);
        xn_root_add(xn_t3154);
                xn_root_add(xn_t3154);
                        xn_root_add(xn_t3154);
                        rt_string *xn_t3155 = rt_retain(xn_t3154->text);
xn_root_add(xn_t3155);
        xn_root_add(xn_t3155);
                xn_root_add(xn_t3155);
                        xn_root_add(xn_t3155);
                        rt_string *xn_t3156 = rt_string_from_c(">>");
xn_root_add(xn_t3156);
        xn_root_add(xn_t3156);
                xn_root_add(xn_t3156);
                        xn_root_add(xn_t3156);
                            if (((xn_Cls_Parser_at(self, 9)) && (xn_str_eq(xn_t3155, xn_t3156)))) {
                                size_t xn_t3157 = xn_root_mark();
                                #line 1540 "impl/lib/b2/xparser.x"
                                xn_Cls_Tok * xn_t3158 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3158);
        xn_root_add(xn_t3158);
                xn_root_add(xn_t3158);
                        xn_root_add(xn_t3158);
                                xn_root_add(xn_t3158);
                                rt_string *xn_t3159 = rt_string_from_c(">");
xn_root_add(xn_t3159);
        xn_root_add(xn_t3159);
                xn_root_add(xn_t3159);
                        xn_root_add(xn_t3159);
                                xn_root_add(xn_t3159);
                                rt_release(xn_t3158->text);
                                xn_t3158->text = xn_t3159;
                                #line 1541 "impl/lib/b2/xparser.x"
                                xn_Cls_Tok * extra = xn_Cls_Tok_new();
xn_root_add(extra);
        xn_root_add(extra);
                xn_root_add(extra);
                        xn_root_add(extra);
                                xn_root_add(extra);
                                xn_root_add(extra);
                                xn_gc_safepoint();
                                #line 1542 "impl/lib/b2/xparser.x"
                                extra->kind = 9;
                                #line 1543 "impl/lib/b2/xparser.x"
                                rt_string *xn_t3160 = rt_string_from_c(">");
xn_root_add(xn_t3160);
        xn_root_add(xn_t3160);
                xn_root_add(xn_t3160);
                        xn_root_add(xn_t3160);
                                xn_root_add(xn_t3160);
                                rt_release(extra->text);
                                extra->text = xn_t3160;
                                #line 1544 "impl/lib/b2/xparser.x"
                                xn_Cls_Tok * xn_t3161 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3161);
        xn_root_add(xn_t3161);
                xn_root_add(xn_t3161);
                        xn_root_add(xn_t3161);
                                xn_root_add(xn_t3161);
                                extra->line = xn_t3161->line;
                                #line 1545 "impl/lib/b2/xparser.x"
                                xn_Cls_Tok * xn_t3162 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3162);
        xn_root_add(xn_t3162);
                xn_root_add(xn_t3162);
                        xn_root_add(xn_t3162);
                                xn_root_add(xn_t3162);
                                extra->col = xn_t3162->col;
                                #line 1546 "impl/lib/b2/xparser.x"
                                xn_arr_o_Tok_insert(self->toks, (self->i + 1), extra);
                                #line 1547 "impl/lib/b2/xparser.x"
                                xn_root_restore(xn_t3157);
                                xn_root_restore(xn_t3152);
                                break;
                                    {
                                    xn_root_restore(xn_t3157);
                                    }

                            }
                        #line 1549 "impl/lib/b2/xparser.x"
                        rt_string *xn_t3163 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t3163);
        xn_root_add(xn_t3163);
                xn_root_add(xn_t3163);
                        xn_root_add(xn_t3163);
                        xn_arr_s_push(tas, xn_t3163);
                            {
                            xn_root_restore(xn_t3152);
                            }

                        xn_gc_safepoint();
                    }
                #line 1551 "impl/lib/b2/xparser.x"
                rt_string *xn_t3164 = rt_string_from_c(">");
xn_root_add(xn_t3164);
        xn_root_add(xn_t3164);
                xn_root_add(xn_t3164);
                    if ((xn_Cls_Parser_atOp(self, xn_t3164))) {
                        size_t xn_t3165 = xn_root_mark();
                        #line 1551 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t3165);
                            }

                    }
                    {
                    xn_root_restore(xn_t3150);
                    }

            }
        #line 1553 "impl/lib/b2/xparser.x"
        rt_string *xn_t3166 = rt_string_from_c("(NamedType ");
xn_root_add(xn_t3166);
        xn_root_add(xn_t3166);
        rt_string *xn_t3167 = xn_P(t->line, t->col);
xn_root_add(xn_t3167);
        xn_root_add(xn_t3167);
        rt_string *xn_t3168 = xn_concat(xn_t3166, xn_t3167);
xn_root_add(xn_t3168);
        xn_root_add(xn_t3168);
        rt_string *xn_t3169 = rt_string_from_c(" (Qual ");
xn_root_add(xn_t3169);
        xn_root_add(xn_t3169);
        rt_string *xn_t3170 = xn_concat(xn_t3168, xn_t3169);
xn_root_add(xn_t3170);
        xn_root_add(xn_t3170);
        rt_string *xn_t3171 = xn_SLS(qn);
xn_root_add(xn_t3171);
        xn_root_add(xn_t3171);
        rt_string *xn_t3172 = xn_concat(xn_t3170, xn_t3171);
xn_root_add(xn_t3172);
        xn_root_add(xn_t3172);
        rt_string *xn_t3173 = rt_string_from_c(") (Args ");
xn_root_add(xn_t3173);
        xn_root_add(xn_t3173);
        rt_string *xn_t3174 = xn_concat(xn_t3172, xn_t3173);
xn_root_add(xn_t3174);
        xn_root_add(xn_t3174);
        rt_string *xn_t3175 = xn_SL(tas);
xn_root_add(xn_t3175);
        xn_root_add(xn_t3175);
        rt_string *xn_t3176 = xn_concat(xn_t3174, xn_t3175);
xn_root_add(xn_t3176);
        xn_root_add(xn_t3176);
        rt_string *xn_t3177 = rt_string_from_c("))");
xn_root_add(xn_t3177);
        xn_root_add(xn_t3177);
        rt_string *xn_t3178 = xn_concat(xn_t3176, xn_t3177);
xn_root_add(xn_t3178);
        xn_root_add(xn_t3178);
        xn_root_release(base);
        rt_release(base);
        base = xn_t3178;
        xn_root_hold(base);
        xn_gc_safepoint();
        #line 1556 "impl/lib/b2/xparser.x"
            if ((((self->inNew == 0)) && (xn_Cls_Parser_at(self, 10)))) {
                size_t xn_t3179 = xn_root_mark();
                #line 1557 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                #line 1558 "impl/lib/b2/xparser.x"
                xn_arr_s *xn_t3180 = xn_arr_s_new(0);
xn_root_add(xn_t3180);
        xn_root_add(xn_t3180);
                xn_root_add(xn_t3180);
                xn_arr_s * ps = xn_t3180;
xn_root_add(ps);
        xn_root_add(ps);
                xn_root_add(ps);
                xn_root_add(ps);
                xn_gc_safepoint();
                #line 1559 "impl/lib/b2/xparser.x"
                    while ((((!(xn_Cls_Parser_at(self, 11)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                    size_t xn_t3181 = xn_root_mark();
                    #line 1560 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 16))) {
                            size_t xn_t3182 = xn_root_mark();
                            #line 1560 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                            #line 1560 "impl/lib/b2/xparser.x"
                            xn_root_restore(xn_t3182);
                            xn_root_restore(xn_t3181);
                            continue;
                                {
                                xn_root_restore(xn_t3182);
                                }

                        }
                    #line 1561 "impl/lib/b2/xparser.x"
                    rt_string *xn_t3183 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t3183);
        xn_root_add(xn_t3183);
                xn_root_add(xn_t3183);
                    xn_root_add(xn_t3183);
                    xn_arr_s_push(ps, xn_t3183);
                        {
                        xn_root_restore(xn_t3181);
                        }

                    xn_gc_safepoint();
                    }
                #line 1563 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 11))) {
                        size_t xn_t3184 = xn_root_mark();
                        #line 1563 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t3184);
                            }

                    }
                #line 1564 "impl/lib/b2/xparser.x"
                rt_string *xn_t3185 = rt_string_from_c("(FuncTypeRef ");
xn_root_add(xn_t3185);
        xn_root_add(xn_t3185);
                xn_root_add(xn_t3185);
                rt_string *xn_t3186 = xn_P(t->line, t->col);
xn_root_add(xn_t3186);
        xn_root_add(xn_t3186);
                xn_root_add(xn_t3186);
                rt_string *xn_t3187 = xn_concat(xn_t3185, xn_t3186);
xn_root_add(xn_t3187);
        xn_root_add(xn_t3187);
                xn_root_add(xn_t3187);
                rt_string *xn_t3188 = rt_string_from_c(" (Ret ");
xn_root_add(xn_t3188);
        xn_root_add(xn_t3188);
                xn_root_add(xn_t3188);
                rt_string *xn_t3189 = xn_concat(xn_t3187, xn_t3188);
xn_root_add(xn_t3189);
        xn_root_add(xn_t3189);
                xn_root_add(xn_t3189);
                rt_string *xn_t3190 = rt_retain(base);
xn_root_add(xn_t3190);
        xn_root_add(xn_t3190);
                xn_root_add(xn_t3190);
                rt_string *xn_t3191 = xn_concat(xn_t3189, xn_t3190);
xn_root_add(xn_t3191);
        xn_root_add(xn_t3191);
                xn_root_add(xn_t3191);
                rt_string *xn_t3192 = rt_string_from_c(") (Params ");
xn_root_add(xn_t3192);
        xn_root_add(xn_t3192);
                xn_root_add(xn_t3192);
                rt_string *xn_t3193 = xn_concat(xn_t3191, xn_t3192);
xn_root_add(xn_t3193);
        xn_root_add(xn_t3193);
                xn_root_add(xn_t3193);
                rt_string *xn_t3194 = xn_SL(ps);
xn_root_add(xn_t3194);
        xn_root_add(xn_t3194);
                xn_root_add(xn_t3194);
                rt_string *xn_t3195 = xn_concat(xn_t3193, xn_t3194);
xn_root_add(xn_t3195);
        xn_root_add(xn_t3195);
                xn_root_add(xn_t3195);
                rt_string *xn_t3196 = rt_string_from_c("))");
xn_root_add(xn_t3196);
        xn_root_add(xn_t3196);
                xn_root_add(xn_t3196);
                rt_string *xn_t3197 = xn_concat(xn_t3195, xn_t3196);
xn_root_add(xn_t3197);
        xn_root_add(xn_t3197);
                xn_root_add(xn_t3197);
                xn_root_release(base);
                rt_release(base);
                base = xn_t3197;
                xn_root_hold(base);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t3179);
                    }

            }
            {
            xn_root_restore(xn_t3138);
            }

    }
#line 1567 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t3198 = xn_arr_s_new(0);
xn_root_add(xn_t3198);
xn_arr_s * sufs = xn_t3198;
xn_root_add(sufs);
xn_root_add(sufs);
xn_gc_safepoint();
#line 1568 "impl/lib/b2/xparser.x"
    while (1) {
    size_t xn_t3199 = xn_root_mark();
    #line 1569 "impl/lib/b2/xparser.x"
    rt_string *xn_t3200 = rt_string_from_c("?");
xn_root_add(xn_t3200);
    xn_root_add(xn_t3200);
        if ((xn_Cls_Parser_atOp(self, xn_t3200))) {
            size_t xn_t3201 = xn_root_mark();
            #line 1569 "impl/lib/b2/xparser.x"
            rt_string *xn_t3202 = rt_string_from_c("?");
xn_root_add(xn_t3202);
    xn_root_add(xn_t3202);
            xn_root_add(xn_t3202);
            xn_arr_s_push(sufs, xn_t3202);
            #line 1569 "impl/lib/b2/xparser.x"
            xn_Cls_Parser_next(self);
                {
                xn_root_restore(xn_t3201);
                }

        } else {
            xn_Cls_Tok * xn_t3204 = xn_arr_o_Tok_get(self->toks, (self->i + 1));
xn_root_add(xn_t3204);
    xn_root_add(xn_t3204);
            xn_root_add(xn_t3204);
                if (((xn_Cls_Parser_at(self, 14)) && ((xn_t3204->kind == 15)))) {
                    size_t xn_t3205 = xn_root_mark();
                    #line 1571 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 1572 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 1573 "impl/lib/b2/xparser.x"
                    rt_string *xn_t3206 = rt_string_from_c("[]");
xn_root_add(xn_t3206);
    xn_root_add(xn_t3206);
            xn_root_add(xn_t3206);
                    xn_root_add(xn_t3206);
                    xn_arr_s_push(sufs, xn_t3206);
                        {
                        xn_root_restore(xn_t3205);
                        }

                } else {
                    size_t xn_t3207 = xn_root_mark();
                    #line 1574 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t3207);
                    xn_root_restore(xn_t3199);
                    break;
                        {
                        xn_root_restore(xn_t3207);
                        }

                }
        }
        {
        xn_root_restore(xn_t3199);
        }

    xn_gc_safepoint();
    }
#line 1576 "impl/lib/b2/xparser.x"
    if (((((int64_t)sufs->len) > 0))) {
        size_t xn_t3208 = xn_root_mark();
        #line 1577 "impl/lib/b2/xparser.x"
        rt_string *xn_t3209 = rt_string_from_c("(SuffixedType ");
xn_root_add(xn_t3209);
        xn_root_add(xn_t3209);
        xn_root_add(xn_t3209);
        rt_string *xn_t3210 = xn_P(t->line, t->col);
xn_root_add(xn_t3210);
        xn_root_add(xn_t3210);
        xn_root_add(xn_t3210);
        rt_string *xn_t3211 = xn_concat(xn_t3209, xn_t3210);
xn_root_add(xn_t3211);
        xn_root_add(xn_t3211);
        xn_root_add(xn_t3211);
        rt_string *xn_t3212 = rt_string_from_c(" (Base ");
xn_root_add(xn_t3212);
        xn_root_add(xn_t3212);
        xn_root_add(xn_t3212);
        rt_string *xn_t3213 = xn_concat(xn_t3211, xn_t3212);
xn_root_add(xn_t3213);
        xn_root_add(xn_t3213);
        xn_root_add(xn_t3213);
        rt_string *xn_t3214 = rt_retain(base);
xn_root_add(xn_t3214);
        xn_root_add(xn_t3214);
        xn_root_add(xn_t3214);
        rt_string *xn_t3215 = xn_concat(xn_t3213, xn_t3214);
xn_root_add(xn_t3215);
        xn_root_add(xn_t3215);
        xn_root_add(xn_t3215);
        rt_string *xn_t3216 = rt_string_from_c(") (Suffixes ");
xn_root_add(xn_t3216);
        xn_root_add(xn_t3216);
        xn_root_add(xn_t3216);
        rt_string *xn_t3217 = xn_concat(xn_t3215, xn_t3216);
xn_root_add(xn_t3217);
        xn_root_add(xn_t3217);
        xn_root_add(xn_t3217);
        rt_string *xn_t3218 = xn_SLS(sufs);
xn_root_add(xn_t3218);
        xn_root_add(xn_t3218);
        xn_root_add(xn_t3218);
        rt_string *xn_t3219 = xn_concat(xn_t3217, xn_t3218);
xn_root_add(xn_t3219);
        xn_root_add(xn_t3219);
        xn_root_add(xn_t3219);
        rt_string *xn_t3220 = rt_string_from_c("))");
xn_root_add(xn_t3220);
        xn_root_add(xn_t3220);
        xn_root_add(xn_t3220);
        rt_string *xn_t3221 = xn_concat(xn_t3219, xn_t3220);
xn_root_add(xn_t3221);
        xn_root_add(xn_t3221);
        xn_root_add(xn_t3221);
            {
        xn_root_restore(xn_t3208);
            }
            {
        rt_release(base);
            }
            {
        xn_root_restore(xn_t3121);
            }

        return xn_t3221;

    }
#line 1579 "impl/lib/b2/xparser.x"
rt_retain(base);
    {
rt_release(base);
    }
    {
xn_root_restore(xn_t3121);
    }

return base;
xn_root_release(base);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseBlock(xn_Cls_Parser *self) {
size_t xn_t3222 = xn_root_mark();
xn_root_add(self);
#line 1583 "impl/lib/b2/xparser.x"
xn_Cls_Tok * o = xn_Cls_Parser_cur(self);
xn_root_add(o);
xn_root_add(o);
xn_gc_safepoint();
#line 1584 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 12))) {
        size_t xn_t3223 = xn_root_mark();
        #line 1584 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3223);
            }

    }
#line 1585 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t3224 = xn_arr_s_new(0);
xn_root_add(xn_t3224);
xn_arr_s * ss = xn_t3224;
xn_root_add(ss);
xn_root_add(ss);
xn_gc_safepoint();
#line 1586 "impl/lib/b2/xparser.x"
    while ((((!(xn_Cls_Parser_at(self, 13)))) && ((!(xn_Cls_Parser_eof(self)))))) {
    size_t xn_t3225 = xn_root_mark();
    #line 1587 "impl/lib/b2/xparser.x"
        if ((xn_Cls_Parser_at(self, 1))) {
            size_t xn_t3226 = xn_root_mark();
            #line 1587 "impl/lib/b2/xparser.x"
            xn_Cls_Parser_next(self);
            #line 1587 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t3226);
            xn_root_restore(xn_t3225);
            continue;
                {
                xn_root_restore(xn_t3226);
                }

        }
    #line 1588 "impl/lib/b2/xparser.x"
    rt_string *xn_t3227 = xn_Cls_Parser_parseStmt(self);
xn_root_add(xn_t3227);
    xn_root_add(xn_t3227);
    xn_arr_s_push(ss, xn_t3227);
        {
        xn_root_restore(xn_t3225);
        }

    xn_gc_safepoint();
    }
#line 1590 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 13))) {
        size_t xn_t3228 = xn_root_mark();
        #line 1590 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3228);
            }

    } else {
        size_t xn_t3229 = xn_root_mark();
        #line 1591 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * e = xn_Cls_Parser_cur(self);
xn_root_add(e);
        xn_root_add(e);
        xn_root_add(e);
        xn_gc_safepoint();
        #line 1592 "impl/lib/b2/xparser.x"
        rt_string *xn_t3230 = rt_string_from_c("SYN-101");
xn_root_add(xn_t3230);
        xn_root_add(xn_t3230);
        rt_string *xn_t3231 = rt_string_from_c("期望`}`");
xn_root_add(xn_t3231);
        xn_root_add(xn_t3231);
        xn_Cls_Parser_err(self, xn_t3230, e->line, e->col, xn_t3231);
            {
            xn_root_restore(xn_t3229);
            }

    }
#line 1594 "impl/lib/b2/xparser.x"
rt_string *xn_t3232 = rt_string_from_c("(Block ");
xn_root_add(xn_t3232);
xn_root_add(xn_t3232);
rt_string *xn_t3233 = xn_P(o->line, o->col);
xn_root_add(xn_t3233);
xn_root_add(xn_t3233);
rt_string *xn_t3234 = xn_concat(xn_t3232, xn_t3233);
xn_root_add(xn_t3234);
xn_root_add(xn_t3234);
rt_string *xn_t3235 = rt_string_from_c(" (Stmts ");
xn_root_add(xn_t3235);
xn_root_add(xn_t3235);
rt_string *xn_t3236 = xn_concat(xn_t3234, xn_t3235);
xn_root_add(xn_t3236);
xn_root_add(xn_t3236);
rt_string *xn_t3237 = xn_SL(ss);
xn_root_add(xn_t3237);
xn_root_add(xn_t3237);
rt_string *xn_t3238 = xn_concat(xn_t3236, xn_t3237);
xn_root_add(xn_t3238);
xn_root_add(xn_t3238);
rt_string *xn_t3239 = rt_string_from_c("))");
xn_root_add(xn_t3239);
xn_root_add(xn_t3239);
rt_string *xn_t3240 = xn_concat(xn_t3238, xn_t3239);
xn_root_add(xn_t3240);
xn_root_add(xn_t3240);
    {
xn_root_restore(xn_t3222);
    }

return xn_t3240;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Parser_isTypeStart(xn_Cls_Parser *self) {
size_t xn_t3241 = xn_root_mark();
xn_root_add(self);
#line 1598 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 10))) {
        size_t xn_t3242 = xn_root_mark();
        #line 1599 "impl/lib/b2/xparser.x"
        int64_t j = (self->i + 1);
        #line 1600 "impl/lib/b2/xparser.x"
        int64_t dep = 1;
        #line 1601 "impl/lib/b2/xparser.x"
        int comma = 0;
        #line 1602 "impl/lib/b2/xparser.x"
            while ((((j < ((int64_t)self->toks->len))) && ((dep > 0)))) {
            size_t xn_t3243 = xn_root_mark();
            #line 1603 "impl/lib/b2/xparser.x"
            xn_Cls_Tok * x = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(x);
        xn_root_add(x);
            xn_root_add(x);
            xn_root_add(x);
            xn_gc_safepoint();
            #line 1604 "impl/lib/b2/xparser.x"
                if (((x->kind == 10))) {
                    size_t xn_t3244 = xn_root_mark();
                    #line 1604 "impl/lib/b2/xparser.x"
                    dep = (dep + 1);
                        {
                        xn_root_restore(xn_t3244);
                        }

                } else {
                        if (((x->kind == 11))) {
                            size_t xn_t3246 = xn_root_mark();
                            #line 1605 "impl/lib/b2/xparser.x"
                            dep = (dep - 1);
                                {
                                xn_root_restore(xn_t3246);
                                }

                        } else {
                                if ((((x->kind == 16)) && ((dep == 1)))) {
                                    size_t xn_t3248 = xn_root_mark();
                                    #line 1606 "impl/lib/b2/xparser.x"
                                    comma = 1;
                                        {
                                        xn_root_restore(xn_t3248);
                                        }

                                }
                        }
                }
            #line 1607 "impl/lib/b2/xparser.x"
            j = (j + 1);
                {
                xn_root_restore(xn_t3243);
                }

            xn_gc_safepoint();
            }
        #line 1609 "impl/lib/b2/xparser.x"
            if ((comma)) {
                size_t xn_t3249 = xn_root_mark();
                #line 1609 "impl/lib/b2/xparser.x"
                int xn_t3250 = 1;
                    {
                xn_root_restore(xn_t3249);
                    }
                    {
                xn_root_restore(xn_t3242);
                    }
                    {
                xn_root_restore(xn_t3241);
                    }

                return xn_t3250;

            }
            {
            xn_root_restore(xn_t3242);
            }

    }
#line 1611 "impl/lib/b2/xparser.x"
rt_string *xn_t3251 = rt_string_from_c("final");
xn_root_add(xn_t3251);
rt_string *xn_t3252 = rt_string_from_c("const");
xn_root_add(xn_t3252);
rt_string *xn_t3253 = rt_string_from_c("var");
xn_root_add(xn_t3253);
    if ((((xn_Cls_Parser_atKw(self, xn_t3251)) || (xn_Cls_Parser_atKw(self, xn_t3252))) || (xn_Cls_Parser_atKw(self, xn_t3253)))) {
        size_t xn_t3254 = xn_root_mark();
        #line 1611 "impl/lib/b2/xparser.x"
        int xn_t3255 = 1;
            {
        xn_root_restore(xn_t3254);
            }
            {
        xn_root_restore(xn_t3241);
            }

        return xn_t3255;

    }
#line 1612 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 2))) {
        size_t xn_t3256 = xn_root_mark();
        #line 1613 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3257 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3257);
        xn_root_add(xn_t3257);
        rt_string *n = rt_retain(xn_t3257->text);
xn_root_add(n);
        xn_root_add(n);
        xn_root_add(n);
        xn_gc_safepoint();
        #line 1614 "impl/lib/b2/xparser.x"
        rt_string *xn_t3259 = rt_retain(n);
xn_root_add(xn_t3259);
        xn_root_add(xn_t3259);
        rt_string *xn_t3260 = rt_string_from_c("Int");
xn_root_add(xn_t3260);
        xn_root_add(xn_t3260);
        rt_string *xn_t3261 = rt_retain(n);
xn_root_add(xn_t3261);
        xn_root_add(xn_t3261);
        rt_string *xn_t3262 = rt_string_from_c("String");
xn_root_add(xn_t3262);
        xn_root_add(xn_t3262);
        rt_string *xn_t3263 = rt_retain(n);
xn_root_add(xn_t3263);
        xn_root_add(xn_t3263);
        rt_string *xn_t3264 = rt_string_from_c("Bool");
xn_root_add(xn_t3264);
        xn_root_add(xn_t3264);
        rt_string *xn_t3265 = rt_retain(n);
xn_root_add(xn_t3265);
        xn_root_add(xn_t3265);
        rt_string *xn_t3266 = rt_string_from_c("Char");
xn_root_add(xn_t3266);
        xn_root_add(xn_t3266);
        rt_string *xn_t3267 = rt_retain(n);
xn_root_add(xn_t3267);
        xn_root_add(xn_t3267);
        rt_string *xn_t3268 = rt_string_from_c("Float");
xn_root_add(xn_t3268);
        xn_root_add(xn_t3268);
        rt_string *xn_t3269 = rt_retain(n);
xn_root_add(xn_t3269);
        xn_root_add(xn_t3269);
        rt_string *xn_t3270 = rt_string_from_c("Double");
xn_root_add(xn_t3270);
        xn_root_add(xn_t3270);
        rt_string *xn_t3271 = rt_retain(n);
xn_root_add(xn_t3271);
        xn_root_add(xn_t3271);
        rt_string *xn_t3272 = rt_string_from_c("Long");
xn_root_add(xn_t3272);
        xn_root_add(xn_t3272);
        rt_string *xn_t3273 = rt_retain(n);
xn_root_add(xn_t3273);
        xn_root_add(xn_t3273);
        rt_string *xn_t3274 = rt_string_from_c("UInt");
xn_root_add(xn_t3274);
        xn_root_add(xn_t3274);
        rt_string *xn_t3275 = rt_retain(n);
xn_root_add(xn_t3275);
        xn_root_add(xn_t3275);
        rt_string *xn_t3276 = rt_string_from_c("Text");
xn_root_add(xn_t3276);
        xn_root_add(xn_t3276);
        rt_string *xn_t3277 = rt_retain(n);
xn_root_add(xn_t3277);
        xn_root_add(xn_t3277);
        rt_string *xn_t3278 = rt_string_from_c("Bytes");
xn_root_add(xn_t3278);
        xn_root_add(xn_t3278);
        rt_string *xn_t3279 = rt_retain(n);
xn_root_add(xn_t3279);
        xn_root_add(xn_t3279);
        rt_string *xn_t3280 = rt_string_from_c("Map");
xn_root_add(xn_t3280);
        xn_root_add(xn_t3280);
        rt_string *xn_t3281 = rt_retain(n);
xn_root_add(xn_t3281);
        xn_root_add(xn_t3281);
        rt_string *xn_t3282 = rt_string_from_c("List");
xn_root_add(xn_t3282);
        xn_root_add(xn_t3282);
        rt_string *xn_t3283 = rt_retain(n);
xn_root_add(xn_t3283);
        xn_root_add(xn_t3283);
        rt_string *xn_t3284 = rt_string_from_c("Set");
xn_root_add(xn_t3284);
        xn_root_add(xn_t3284);
        rt_string *xn_t3285 = rt_retain(n);
xn_root_add(xn_t3285);
        xn_root_add(xn_t3285);
        rt_string *xn_t3286 = rt_string_from_c("Result");
xn_root_add(xn_t3286);
        xn_root_add(xn_t3286);
        rt_string *xn_t3287 = rt_retain(n);
xn_root_add(xn_t3287);
        xn_root_add(xn_t3287);
        rt_string *xn_t3288 = rt_string_from_c("Object");
xn_root_add(xn_t3288);
        xn_root_add(xn_t3288);
        rt_string *xn_t3289 = rt_retain(n);
xn_root_add(xn_t3289);
        xn_root_add(xn_t3289);
        rt_string *xn_t3290 = rt_string_from_c("Any");
xn_root_add(xn_t3290);
        xn_root_add(xn_t3290);
            if (((((((((((((((((xn_str_eq(xn_t3259, xn_t3260)) || (xn_str_eq(xn_t3261, xn_t3262))) || (xn_str_eq(xn_t3263, xn_t3264))) || (xn_str_eq(xn_t3265, xn_t3266))) || (xn_str_eq(xn_t3267, xn_t3268))) || (xn_str_eq(xn_t3269, xn_t3270))) || (xn_str_eq(xn_t3271, xn_t3272))) || (xn_str_eq(xn_t3273, xn_t3274))) || (xn_str_eq(xn_t3275, xn_t3276))) || (xn_str_eq(xn_t3277, xn_t3278))) || (xn_str_eq(xn_t3279, xn_t3280))) || (xn_str_eq(xn_t3281, xn_t3282))) || (xn_str_eq(xn_t3283, xn_t3284))) || (xn_str_eq(xn_t3285, xn_t3286))) || (xn_str_eq(xn_t3287, xn_t3288))) || (xn_str_eq(xn_t3289, xn_t3290)))) {
                size_t xn_t3291 = xn_root_mark();
                #line 1617 "impl/lib/b2/xparser.x"
                int xn_t3292 = 1;
                    {
                xn_root_restore(xn_t3291);
                    }
                    {
                rt_release(n);
                    }
                    {
                xn_root_restore(xn_t3256);
                    }
                    {
                xn_root_restore(xn_t3241);
                    }

                return xn_t3292;

            }
        #line 1619 "impl/lib/b2/xparser.x"
        int64_t j = (self->i + 1);
        #line 1620 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3293 = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(xn_t3293);
        xn_root_add(xn_t3293);
        xn_Cls_Tok * xn_t3294 = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(xn_t3294);
        xn_root_add(xn_t3294);
        rt_string *xn_t3295 = rt_retain(xn_t3294->text);
xn_root_add(xn_t3295);
        xn_root_add(xn_t3295);
        rt_string *xn_t3296 = rt_string_from_c("<");
xn_root_add(xn_t3296);
        xn_root_add(xn_t3296);
            if ((((xn_t3293->kind == 9)) && (xn_str_eq(xn_t3295, xn_t3296)))) {
                size_t xn_t3297 = xn_root_mark();
                #line 1621 "impl/lib/b2/xparser.x"
                int64_t dep = 1;
                #line 1622 "impl/lib/b2/xparser.x"
                j = (j + 1);
                #line 1623 "impl/lib/b2/xparser.x"
                    while ((((j < ((int64_t)self->toks->len))) && ((dep > 0)))) {
                    size_t xn_t3298 = xn_root_mark();
                    #line 1624 "impl/lib/b2/xparser.x"
                    xn_Cls_Tok * x = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(x);
        xn_root_add(x);
                xn_root_add(x);
                    xn_root_add(x);
                    xn_root_add(x);
                    xn_gc_safepoint();
                    #line 1625 "impl/lib/b2/xparser.x"
                    rt_string *xn_t3299 = rt_retain(x->text);
xn_root_add(xn_t3299);
        xn_root_add(xn_t3299);
                xn_root_add(xn_t3299);
                    xn_root_add(xn_t3299);
                    rt_string *xn_t3300 = rt_string_from_c("<");
xn_root_add(xn_t3300);
        xn_root_add(xn_t3300);
                xn_root_add(xn_t3300);
                    xn_root_add(xn_t3300);
                        if ((((x->kind == 9)) && (xn_str_eq(xn_t3299, xn_t3300)))) {
                            size_t xn_t3301 = xn_root_mark();
                            #line 1625 "impl/lib/b2/xparser.x"
                            dep = (dep + 1);
                                {
                                xn_root_restore(xn_t3301);
                                }

                        } else {
                            rt_string *xn_t3303 = rt_retain(x->text);
xn_root_add(xn_t3303);
        xn_root_add(xn_t3303);
                xn_root_add(xn_t3303);
                    xn_root_add(xn_t3303);
                            xn_root_add(xn_t3303);
                            rt_string *xn_t3304 = rt_string_from_c(">>");
xn_root_add(xn_t3304);
        xn_root_add(xn_t3304);
                xn_root_add(xn_t3304);
                    xn_root_add(xn_t3304);
                            xn_root_add(xn_t3304);
                                if ((((x->kind == 9)) && (xn_str_eq(xn_t3303, xn_t3304)))) {
                                    size_t xn_t3305 = xn_root_mark();
                                    #line 1626 "impl/lib/b2/xparser.x"
                                    dep = (dep - 2);
                                        {
                                        xn_root_restore(xn_t3305);
                                        }

                                } else {
                                    rt_string *xn_t3307 = rt_retain(x->text);
xn_root_add(xn_t3307);
        xn_root_add(xn_t3307);
                xn_root_add(xn_t3307);
                    xn_root_add(xn_t3307);
                            xn_root_add(xn_t3307);
                                    xn_root_add(xn_t3307);
                                    rt_string *xn_t3308 = rt_string_from_c(">");
xn_root_add(xn_t3308);
        xn_root_add(xn_t3308);
                xn_root_add(xn_t3308);
                    xn_root_add(xn_t3308);
                            xn_root_add(xn_t3308);
                                    xn_root_add(xn_t3308);
                                        if ((((x->kind == 9)) && (xn_str_eq(xn_t3307, xn_t3308)))) {
                                            size_t xn_t3309 = xn_root_mark();
                                            #line 1627 "impl/lib/b2/xparser.x"
                                            dep = (dep - 1);
                                                {
                                                xn_root_restore(xn_t3309);
                                                }

                                        }
                                }
                        }
                    #line 1628 "impl/lib/b2/xparser.x"
                    j = (j + 1);
                        {
                        xn_root_restore(xn_t3298);
                        }

                    xn_gc_safepoint();
                    }
                #line 1630 "impl/lib/b2/xparser.x"
                    if (((dep > 0))) {
                        size_t xn_t3310 = xn_root_mark();
                        #line 1630 "impl/lib/b2/xparser.x"
                        int xn_t3311 = 0;
                            {
                        xn_root_restore(xn_t3310);
                            }
                            {
                        xn_root_restore(xn_t3297);
                            }
                            {
                        rt_release(n);
                            }
                            {
                        xn_root_restore(xn_t3256);
                            }
                            {
                        xn_root_restore(xn_t3241);
                            }

                        return xn_t3311;

                    }
                    {
                    xn_root_restore(xn_t3297);
                    }

            }
        #line 1632 "impl/lib/b2/xparser.x"
            while (1) {
                xn_Cls_Tok * xn_t3312 = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(xn_t3312);
        xn_root_add(xn_t3312);
                xn_Cls_Tok * xn_t3313 = xn_arr_o_Tok_get(self->toks, (j + 1));
xn_root_add(xn_t3313);
        xn_root_add(xn_t3313);
                if (!((((((j + 1) < ((int64_t)self->toks->len))) && ((xn_t3312->kind == 14))) && ((xn_t3313->kind == 15))))) { break; }
                size_t xn_t3314 = xn_root_mark();
                #line 1633 "impl/lib/b2/xparser.x"
                j = (j + 2);
                    {
                    xn_root_restore(xn_t3314);
                    }

                xn_gc_safepoint();
            }
        #line 1635 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3315 = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(xn_t3315);
        xn_root_add(xn_t3315);
        xn_Cls_Tok * xn_t3316 = xn_arr_o_Tok_get(self->toks, (j + 1));
xn_root_add(xn_t3316);
        xn_root_add(xn_t3316);
        xn_Cls_Tok * xn_t3317 = xn_arr_o_Tok_get(self->toks, (j + 1));
xn_root_add(xn_t3317);
        xn_root_add(xn_t3317);
            if ((((((j + 1) < ((int64_t)self->toks->len))) && ((xn_t3315->kind == 2))) && (((xn_t3316->kind == 9) || (xn_t3317->kind == 1))))) {
                size_t xn_t3318 = xn_root_mark();
                #line 1637 "impl/lib/b2/xparser.x"
                int xn_t3319 = 1;
                    {
                xn_root_restore(xn_t3318);
                    }
                    {
                rt_release(n);
                    }
                    {
                xn_root_restore(xn_t3256);
                    }
                    {
                xn_root_restore(xn_t3241);
                    }

                return xn_t3319;

            }
        #line 1639 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3320 = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(xn_t3320);
        xn_root_add(xn_t3320);
        xn_Cls_Tok * xn_t3321 = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(xn_t3321);
        xn_root_add(xn_t3321);
        rt_string *xn_t3322 = rt_retain(xn_t3321->text);
xn_root_add(xn_t3322);
        xn_root_add(xn_t3322);
        rt_string *xn_t3323 = rt_string_from_c("?");
xn_root_add(xn_t3323);
        xn_root_add(xn_t3323);
        xn_Cls_Tok * xn_t3324 = xn_arr_o_Tok_get(self->toks, (j + 1));
xn_root_add(xn_t3324);
        xn_root_add(xn_t3324);
            if (((((((j + 1) < ((int64_t)self->toks->len))) && ((xn_t3320->kind == 9))) && (xn_str_eq(xn_t3322, xn_t3323))) && ((xn_t3324->kind == 2)))) {
                size_t xn_t3325 = xn_root_mark();
                #line 1641 "impl/lib/b2/xparser.x"
                int xn_t3326 = 1;
                    {
                xn_root_restore(xn_t3325);
                    }
                    {
                rt_release(n);
                    }
                    {
                xn_root_restore(xn_t3256);
                    }
                    {
                xn_root_restore(xn_t3241);
                    }

                return xn_t3326;

            }
            {
            rt_release(n);
            }
            {
            xn_root_restore(xn_t3256);
            }

    }
#line 1644 "impl/lib/b2/xparser.x"
int xn_t3327 = 0;
    {
xn_root_restore(xn_t3241);
    }

return xn_t3327;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseStmt(xn_Cls_Parser *self) {
size_t xn_t3328 = xn_root_mark();
xn_root_add(self);
#line 1648 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_cur(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1649 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 1))) {
        size_t xn_t3329 = xn_root_mark();
        #line 1649 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1649 "impl/lib/b2/xparser.x"
        rt_string *xn_t3330 = rt_string_from_c("(EmptyStmt ");
xn_root_add(xn_t3330);
        xn_root_add(xn_t3330);
        xn_root_add(xn_t3330);
        rt_string *xn_t3331 = xn_P(t->line, t->col);
xn_root_add(xn_t3331);
        xn_root_add(xn_t3331);
        xn_root_add(xn_t3331);
        rt_string *xn_t3332 = xn_concat(xn_t3330, xn_t3331);
xn_root_add(xn_t3332);
        xn_root_add(xn_t3332);
        xn_root_add(xn_t3332);
        rt_string *xn_t3333 = rt_string_from_c(")");
xn_root_add(xn_t3333);
        xn_root_add(xn_t3333);
        xn_root_add(xn_t3333);
        rt_string *xn_t3334 = xn_concat(xn_t3332, xn_t3333);
xn_root_add(xn_t3334);
        xn_root_add(xn_t3334);
        xn_root_add(xn_t3334);
            {
        xn_root_restore(xn_t3329);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3334;

    }
#line 1650 "impl/lib/b2/xparser.x"
rt_string *xn_t3335 = rt_string_from_c("return");
xn_root_add(xn_t3335);
    if ((xn_Cls_Parser_atKw(self, xn_t3335))) {
        size_t xn_t3336 = xn_root_mark();
        #line 1651 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1652 "impl/lib/b2/xparser.x"
        rt_string *v = rt_string_from_c("(nil)");
xn_root_add(v);
        xn_root_add(v);
        xn_root_add(v);
        xn_gc_safepoint();
        #line 1653 "impl/lib/b2/xparser.x"
            if (((((!(xn_Cls_Parser_at(self, 1)))) && ((!(xn_Cls_Parser_at(self, 13))))) && ((!(xn_Cls_Parser_at(self, 0)))))) {
                size_t xn_t3338 = xn_root_mark();
                #line 1653 "impl/lib/b2/xparser.x"
                xn_Cls_E * xn_t3339 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t3339);
        xn_root_add(xn_t3339);
                xn_root_add(xn_t3339);
                rt_string *xn_t3340 = rt_retain(xn_t3339->d);
xn_root_add(xn_t3340);
        xn_root_add(xn_t3340);
                xn_root_add(xn_t3340);
                xn_root_release(v);
                rt_release(v);
                v = xn_t3340;
                xn_root_hold(v);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t3338);
                    }

            }
        #line 1654 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 1))) {
                size_t xn_t3341 = xn_root_mark();
                #line 1654 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t3341);
                    }

            }
        #line 1655 "impl/lib/b2/xparser.x"
        rt_string *xn_t3342 = rt_string_from_c("(ReturnStmt ");
xn_root_add(xn_t3342);
        xn_root_add(xn_t3342);
        xn_root_add(xn_t3342);
        rt_string *xn_t3343 = xn_P(t->line, t->col);
xn_root_add(xn_t3343);
        xn_root_add(xn_t3343);
        xn_root_add(xn_t3343);
        rt_string *xn_t3344 = xn_concat(xn_t3342, xn_t3343);
xn_root_add(xn_t3344);
        xn_root_add(xn_t3344);
        xn_root_add(xn_t3344);
        rt_string *xn_t3345 = rt_string_from_c(" (Value ");
xn_root_add(xn_t3345);
        xn_root_add(xn_t3345);
        xn_root_add(xn_t3345);
        rt_string *xn_t3346 = xn_concat(xn_t3344, xn_t3345);
xn_root_add(xn_t3346);
        xn_root_add(xn_t3346);
        xn_root_add(xn_t3346);
        rt_string *xn_t3347 = rt_retain(v);
xn_root_add(xn_t3347);
        xn_root_add(xn_t3347);
        xn_root_add(xn_t3347);
        rt_string *xn_t3348 = xn_concat(xn_t3346, xn_t3347);
xn_root_add(xn_t3348);
        xn_root_add(xn_t3348);
        xn_root_add(xn_t3348);
        rt_string *xn_t3349 = rt_string_from_c("))");
xn_root_add(xn_t3349);
        xn_root_add(xn_t3349);
        xn_root_add(xn_t3349);
        rt_string *xn_t3350 = xn_concat(xn_t3348, xn_t3349);
xn_root_add(xn_t3350);
        xn_root_add(xn_t3350);
        xn_root_add(xn_t3350);
            {
        rt_release(v);
            }
            {
        xn_root_restore(xn_t3336);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3350;
        xn_root_release(v);

    }
#line 1657 "impl/lib/b2/xparser.x"
rt_string *xn_t3351 = rt_string_from_c("if");
xn_root_add(xn_t3351);
    if ((xn_Cls_Parser_atKw(self, xn_t3351))) {
        size_t xn_t3352 = xn_root_mark();
        #line 1657 "impl/lib/b2/xparser.x"
        rt_string *xn_t3353 = xn_Cls_Parser_parseIf(self);
xn_root_add(xn_t3353);
        xn_root_add(xn_t3353);
        xn_root_add(xn_t3353);
            {
        xn_root_restore(xn_t3352);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3353;

    }
#line 1658 "impl/lib/b2/xparser.x"
rt_string *xn_t3354 = rt_string_from_c("while");
xn_root_add(xn_t3354);
    if ((xn_Cls_Parser_atKw(self, xn_t3354))) {
        size_t xn_t3355 = xn_root_mark();
        #line 1658 "impl/lib/b2/xparser.x"
        rt_string *xn_t3356 = xn_Cls_Parser_parseWhile(self);
xn_root_add(xn_t3356);
        xn_root_add(xn_t3356);
        xn_root_add(xn_t3356);
            {
        xn_root_restore(xn_t3355);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3356;

    }
#line 1659 "impl/lib/b2/xparser.x"
rt_string *xn_t3357 = rt_string_from_c("do");
xn_root_add(xn_t3357);
    if ((xn_Cls_Parser_atKw(self, xn_t3357))) {
        size_t xn_t3358 = xn_root_mark();
        #line 1659 "impl/lib/b2/xparser.x"
        rt_string *xn_t3359 = xn_Cls_Parser_parseDo(self);
xn_root_add(xn_t3359);
        xn_root_add(xn_t3359);
        xn_root_add(xn_t3359);
            {
        xn_root_restore(xn_t3358);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3359;

    }
#line 1660 "impl/lib/b2/xparser.x"
rt_string *xn_t3360 = rt_string_from_c("for");
xn_root_add(xn_t3360);
    if ((xn_Cls_Parser_atKw(self, xn_t3360))) {
        size_t xn_t3361 = xn_root_mark();
        #line 1660 "impl/lib/b2/xparser.x"
        rt_string *xn_t3362 = xn_Cls_Parser_parseFor(self);
xn_root_add(xn_t3362);
        xn_root_add(xn_t3362);
        xn_root_add(xn_t3362);
            {
        xn_root_restore(xn_t3361);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3362;

    }
#line 1661 "impl/lib/b2/xparser.x"
rt_string *xn_t3363 = rt_string_from_c("switch");
xn_root_add(xn_t3363);
    if ((xn_Cls_Parser_atKw(self, xn_t3363))) {
        size_t xn_t3364 = xn_root_mark();
        #line 1661 "impl/lib/b2/xparser.x"
        rt_string *xn_t3365 = xn_Cls_Parser_parseSwitch(self);
xn_root_add(xn_t3365);
        xn_root_add(xn_t3365);
        xn_root_add(xn_t3365);
            {
        xn_root_restore(xn_t3364);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3365;

    }
#line 1662 "impl/lib/b2/xparser.x"
rt_string *xn_t3366 = rt_string_from_c("defer");
xn_root_add(xn_t3366);
rt_string *xn_t3367 = rt_string_from_c("errdefer");
xn_root_add(xn_t3367);
    if (((xn_Cls_Parser_atKw(self, xn_t3366)) || (xn_Cls_Parser_atKw(self, xn_t3367)))) {
        size_t xn_t3368 = xn_root_mark();
        #line 1662 "impl/lib/b2/xparser.x"
        rt_string *xn_t3369 = xn_Cls_Parser_parseDefer(self);
xn_root_add(xn_t3369);
        xn_root_add(xn_t3369);
        xn_root_add(xn_t3369);
            {
        xn_root_restore(xn_t3368);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3369;

    }
#line 1663 "impl/lib/b2/xparser.x"
rt_string *xn_t3370 = rt_string_from_c("throw");
xn_root_add(xn_t3370);
    if ((xn_Cls_Parser_atKw(self, xn_t3370))) {
        size_t xn_t3371 = xn_root_mark();
        #line 1664 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1665 "impl/lib/b2/xparser.x"
        xn_Cls_E * xn_t3372 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t3372);
        xn_root_add(xn_t3372);
        rt_string *v = rt_retain(xn_t3372->d);
xn_root_add(v);
        xn_root_add(v);
        xn_root_add(v);
        xn_gc_safepoint();
        #line 1666 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 1))) {
                size_t xn_t3374 = xn_root_mark();
                #line 1666 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t3374);
                    }

            }
        #line 1667 "impl/lib/b2/xparser.x"
        rt_string *xn_t3375 = rt_string_from_c("(ThrowStmt ");
xn_root_add(xn_t3375);
        xn_root_add(xn_t3375);
        xn_root_add(xn_t3375);
        rt_string *xn_t3376 = xn_P(t->line, t->col);
xn_root_add(xn_t3376);
        xn_root_add(xn_t3376);
        xn_root_add(xn_t3376);
        rt_string *xn_t3377 = xn_concat(xn_t3375, xn_t3376);
xn_root_add(xn_t3377);
        xn_root_add(xn_t3377);
        xn_root_add(xn_t3377);
        rt_string *xn_t3378 = rt_string_from_c(" (Value ");
xn_root_add(xn_t3378);
        xn_root_add(xn_t3378);
        xn_root_add(xn_t3378);
        rt_string *xn_t3379 = xn_concat(xn_t3377, xn_t3378);
xn_root_add(xn_t3379);
        xn_root_add(xn_t3379);
        xn_root_add(xn_t3379);
        rt_string *xn_t3380 = rt_retain(v);
xn_root_add(xn_t3380);
        xn_root_add(xn_t3380);
        xn_root_add(xn_t3380);
        rt_string *xn_t3381 = xn_concat(xn_t3379, xn_t3380);
xn_root_add(xn_t3381);
        xn_root_add(xn_t3381);
        xn_root_add(xn_t3381);
        rt_string *xn_t3382 = rt_string_from_c("))");
xn_root_add(xn_t3382);
        xn_root_add(xn_t3382);
        xn_root_add(xn_t3382);
        rt_string *xn_t3383 = xn_concat(xn_t3381, xn_t3382);
xn_root_add(xn_t3383);
        xn_root_add(xn_t3383);
        xn_root_add(xn_t3383);
            {
        rt_release(v);
            }
            {
        xn_root_restore(xn_t3371);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3383;

    }
#line 1669 "impl/lib/b2/xparser.x"
rt_string *xn_t3384 = rt_string_from_c("break");
xn_root_add(xn_t3384);
rt_string *xn_t3385 = rt_string_from_c("continue");
xn_root_add(xn_t3385);
rt_string *xn_t3386 = rt_string_from_c("goto");
xn_root_add(xn_t3386);
    if ((((xn_Cls_Parser_atKw(self, xn_t3384)) || (xn_Cls_Parser_atKw(self, xn_t3385))) || (xn_Cls_Parser_atKw(self, xn_t3386)))) {
        size_t xn_t3387 = xn_root_mark();
        #line 1670 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3388 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3388);
        xn_root_add(xn_t3388);
        rt_string *kw = rt_retain(xn_t3388->text);
xn_root_add(kw);
        xn_root_add(kw);
        xn_root_add(kw);
        xn_gc_safepoint();
        #line 1671 "impl/lib/b2/xparser.x"
        rt_string *lab = rt_string_from_c("");
xn_root_add(lab);
        xn_root_add(lab);
        xn_root_add(lab);
        xn_gc_safepoint();
        #line 1672 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 2))) {
                size_t xn_t3391 = xn_root_mark();
                #line 1672 "impl/lib/b2/xparser.x"
                xn_Cls_Tok * xn_t3392 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3392);
        xn_root_add(xn_t3392);
                xn_root_add(xn_t3392);
                rt_string *xn_t3393 = rt_retain(xn_t3392->text);
xn_root_add(xn_t3393);
        xn_root_add(xn_t3393);
                xn_root_add(xn_t3393);
                xn_root_release(lab);
                rt_release(lab);
                lab = xn_t3393;
                xn_root_hold(lab);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t3391);
                    }

            }
        #line 1673 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 1))) {
                size_t xn_t3394 = xn_root_mark();
                #line 1673 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t3394);
                    }

            }
        #line 1674 "impl/lib/b2/xparser.x"
        rt_string *type = rt_string_from_c("BreakStmt");
xn_root_add(type);
        xn_root_add(type);
        xn_root_add(type);
        xn_gc_safepoint();
        #line 1675 "impl/lib/b2/xparser.x"
        rt_string *xn_t3396 = rt_retain(kw);
xn_root_add(xn_t3396);
        xn_root_add(xn_t3396);
        rt_string *xn_t3397 = rt_string_from_c("continue");
xn_root_add(xn_t3397);
        xn_root_add(xn_t3397);
            if ((xn_str_eq(xn_t3396, xn_t3397))) {
                size_t xn_t3398 = xn_root_mark();
                #line 1675 "impl/lib/b2/xparser.x"
                rt_string *xn_t3399 = rt_string_from_c("ContinueStmt");
xn_root_add(xn_t3399);
        xn_root_add(xn_t3399);
                xn_root_add(xn_t3399);
                xn_root_release(type);
                rt_release(type);
                type = xn_t3399;
                xn_root_hold(type);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t3398);
                    }

            }
        #line 1676 "impl/lib/b2/xparser.x"
        rt_string *xn_t3400 = rt_retain(kw);
xn_root_add(xn_t3400);
        xn_root_add(xn_t3400);
        rt_string *xn_t3401 = rt_string_from_c("goto");
xn_root_add(xn_t3401);
        xn_root_add(xn_t3401);
            if ((xn_str_eq(xn_t3400, xn_t3401))) {
                size_t xn_t3402 = xn_root_mark();
                #line 1676 "impl/lib/b2/xparser.x"
                rt_string *xn_t3403 = rt_string_from_c("GotoStmt");
xn_root_add(xn_t3403);
        xn_root_add(xn_t3403);
                xn_root_add(xn_t3403);
                xn_root_release(type);
                rt_release(type);
                type = xn_t3403;
                xn_root_hold(type);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t3402);
                    }

            }
        #line 1677 "impl/lib/b2/xparser.x"
        rt_string *xn_t3404 = rt_string_from_c("(");
xn_root_add(xn_t3404);
        xn_root_add(xn_t3404);
        xn_root_add(xn_t3404);
        rt_string *xn_t3405 = rt_retain(type);
xn_root_add(xn_t3405);
        xn_root_add(xn_t3405);
        xn_root_add(xn_t3405);
        rt_string *xn_t3406 = xn_concat(xn_t3404, xn_t3405);
xn_root_add(xn_t3406);
        xn_root_add(xn_t3406);
        xn_root_add(xn_t3406);
        rt_string *xn_t3407 = rt_string_from_c(" ");
xn_root_add(xn_t3407);
        xn_root_add(xn_t3407);
        xn_root_add(xn_t3407);
        rt_string *xn_t3408 = xn_concat(xn_t3406, xn_t3407);
xn_root_add(xn_t3408);
        xn_root_add(xn_t3408);
        xn_root_add(xn_t3408);
        rt_string *xn_t3409 = xn_P(t->line, t->col);
xn_root_add(xn_t3409);
        xn_root_add(xn_t3409);
        xn_root_add(xn_t3409);
        rt_string *xn_t3410 = xn_concat(xn_t3408, xn_t3409);
xn_root_add(xn_t3410);
        xn_root_add(xn_t3410);
        xn_root_add(xn_t3410);
        rt_string *xn_t3411 = rt_string_from_c(" (Label ");
xn_root_add(xn_t3411);
        xn_root_add(xn_t3411);
        xn_root_add(xn_t3411);
        rt_string *xn_t3412 = xn_concat(xn_t3410, xn_t3411);
xn_root_add(xn_t3412);
        xn_root_add(xn_t3412);
        xn_root_add(xn_t3412);
        rt_string *xn_t3413 = rt_retain(lab);
xn_root_add(xn_t3413);
        xn_root_add(xn_t3413);
        xn_root_add(xn_t3413);
        rt_string *xn_t3414 = xn_q(xn_t3413);
xn_root_add(xn_t3414);
        xn_root_add(xn_t3414);
        xn_root_add(xn_t3414);
        rt_string *xn_t3415 = xn_concat(xn_t3412, xn_t3414);
xn_root_add(xn_t3415);
        xn_root_add(xn_t3415);
        xn_root_add(xn_t3415);
        rt_string *xn_t3416 = rt_string_from_c("))");
xn_root_add(xn_t3416);
        xn_root_add(xn_t3416);
        xn_root_add(xn_t3416);
        rt_string *xn_t3417 = xn_concat(xn_t3415, xn_t3416);
xn_root_add(xn_t3417);
        xn_root_add(xn_t3417);
        xn_root_add(xn_t3417);
            {
        rt_release(type);
            }
            {
        rt_release(lab);
            }
            {
        rt_release(kw);
            }
            {
        xn_root_restore(xn_t3387);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3417;
        xn_root_release(lab);
        xn_root_release(type);

    }
#line 1679 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 12))) {
        size_t xn_t3418 = xn_root_mark();
        #line 1679 "impl/lib/b2/xparser.x"
        rt_string *xn_t3419 = xn_Cls_Parser_parseBlock(self);
xn_root_add(xn_t3419);
        xn_root_add(xn_t3419);
        xn_root_add(xn_t3419);
            {
        xn_root_restore(xn_t3418);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3419;

    }
#line 1680 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t3420 = xn_arr_o_Tok_get(self->toks, (self->i + 1));
xn_root_add(xn_t3420);
xn_Cls_Tok * xn_t3421 = xn_arr_o_Tok_get(self->toks, (self->i + 1));
xn_root_add(xn_t3421);
rt_string *xn_t3422 = rt_retain(xn_t3421->text);
xn_root_add(xn_t3422);
rt_string *xn_t3423 = rt_string_from_c(":");
xn_root_add(xn_t3423);
    if ((((xn_Cls_Parser_at(self, 2)) && ((xn_t3420->kind == 9))) && (xn_str_eq(xn_t3422, xn_t3423)))) {
        size_t xn_t3424 = xn_root_mark();
        #line 1681 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3425 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3425);
        xn_root_add(xn_t3425);
        rt_string *lab = rt_retain(xn_t3425->text);
xn_root_add(lab);
        xn_root_add(lab);
        xn_root_add(lab);
        xn_gc_safepoint();
        #line 1682 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1683 "impl/lib/b2/xparser.x"
        rt_string *st = rt_string_from_c("");
xn_root_add(st);
        xn_root_add(st);
        xn_root_add(st);
        xn_gc_safepoint();
        #line 1684 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 1))) {
                size_t xn_t3428 = xn_root_mark();
                #line 1684 "impl/lib/b2/xparser.x"
                xn_Cls_Tok * s = xn_Cls_Parser_next(self);
xn_root_add(s);
        xn_root_add(s);
                xn_root_add(s);
                xn_root_add(s);
                xn_gc_safepoint();
                #line 1684 "impl/lib/b2/xparser.x"
                rt_string *xn_t3429 = rt_string_from_c("(EmptyStmt ");
xn_root_add(xn_t3429);
        xn_root_add(xn_t3429);
                xn_root_add(xn_t3429);
                rt_string *xn_t3430 = xn_P(s->line, s->col);
xn_root_add(xn_t3430);
        xn_root_add(xn_t3430);
                xn_root_add(xn_t3430);
                rt_string *xn_t3431 = xn_concat(xn_t3429, xn_t3430);
xn_root_add(xn_t3431);
        xn_root_add(xn_t3431);
                xn_root_add(xn_t3431);
                rt_string *xn_t3432 = rt_string_from_c(")");
xn_root_add(xn_t3432);
        xn_root_add(xn_t3432);
                xn_root_add(xn_t3432);
                rt_string *xn_t3433 = xn_concat(xn_t3431, xn_t3432);
xn_root_add(xn_t3433);
        xn_root_add(xn_t3433);
                xn_root_add(xn_t3433);
                xn_root_release(st);
                rt_release(st);
                st = xn_t3433;
                xn_root_hold(st);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t3428);
                    }

            } else {
                size_t xn_t3434 = xn_root_mark();
                #line 1685 "impl/lib/b2/xparser.x"
                rt_string *xn_t3435 = xn_Cls_Parser_parseStmt(self);
xn_root_add(xn_t3435);
        xn_root_add(xn_t3435);
                xn_root_add(xn_t3435);
                xn_root_release(st);
                rt_release(st);
                st = xn_t3435;
                xn_root_hold(st);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t3434);
                    }

            }
        #line 1686 "impl/lib/b2/xparser.x"
        rt_string *xn_t3436 = rt_string_from_c("(LabeledStmt ");
xn_root_add(xn_t3436);
        xn_root_add(xn_t3436);
        xn_root_add(xn_t3436);
        rt_string *xn_t3437 = xn_P(t->line, t->col);
xn_root_add(xn_t3437);
        xn_root_add(xn_t3437);
        xn_root_add(xn_t3437);
        rt_string *xn_t3438 = xn_concat(xn_t3436, xn_t3437);
xn_root_add(xn_t3438);
        xn_root_add(xn_t3438);
        xn_root_add(xn_t3438);
        rt_string *xn_t3439 = rt_string_from_c(" (Label ");
xn_root_add(xn_t3439);
        xn_root_add(xn_t3439);
        xn_root_add(xn_t3439);
        rt_string *xn_t3440 = xn_concat(xn_t3438, xn_t3439);
xn_root_add(xn_t3440);
        xn_root_add(xn_t3440);
        xn_root_add(xn_t3440);
        rt_string *xn_t3441 = rt_retain(lab);
xn_root_add(xn_t3441);
        xn_root_add(xn_t3441);
        xn_root_add(xn_t3441);
        rt_string *xn_t3442 = xn_q(xn_t3441);
xn_root_add(xn_t3442);
        xn_root_add(xn_t3442);
        xn_root_add(xn_t3442);
        rt_string *xn_t3443 = xn_concat(xn_t3440, xn_t3442);
xn_root_add(xn_t3443);
        xn_root_add(xn_t3443);
        xn_root_add(xn_t3443);
        rt_string *xn_t3444 = rt_string_from_c(") (Stmt ");
xn_root_add(xn_t3444);
        xn_root_add(xn_t3444);
        xn_root_add(xn_t3444);
        rt_string *xn_t3445 = xn_concat(xn_t3443, xn_t3444);
xn_root_add(xn_t3445);
        xn_root_add(xn_t3445);
        xn_root_add(xn_t3445);
        rt_string *xn_t3446 = rt_retain(st);
xn_root_add(xn_t3446);
        xn_root_add(xn_t3446);
        xn_root_add(xn_t3446);
        rt_string *xn_t3447 = xn_concat(xn_t3445, xn_t3446);
xn_root_add(xn_t3447);
        xn_root_add(xn_t3447);
        xn_root_add(xn_t3447);
        rt_string *xn_t3448 = rt_string_from_c("))");
xn_root_add(xn_t3448);
        xn_root_add(xn_t3448);
        xn_root_add(xn_t3448);
        rt_string *xn_t3449 = xn_concat(xn_t3447, xn_t3448);
xn_root_add(xn_t3449);
        xn_root_add(xn_t3449);
        xn_root_add(xn_t3449);
            {
        rt_release(st);
            }
            {
        rt_release(lab);
            }
            {
        xn_root_restore(xn_t3424);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3449;
        xn_root_release(st);

    }
#line 1688 "impl/lib/b2/xparser.x"
rt_string *xn_t3450 = rt_string_from_c("var");
xn_root_add(xn_t3450);
    if (((xn_Cls_Parser_isTypeStart(self)) || (xn_Cls_Parser_atKw(self, xn_t3450)))) {
        size_t xn_t3451 = xn_root_mark();
        #line 1689 "impl/lib/b2/xparser.x"
        rt_string *xn_t3452 = xn_Cls_Parser_parseLocal(self);
xn_root_add(xn_t3452);
        xn_root_add(xn_t3452);
        xn_root_add(xn_t3452);
            {
        xn_root_restore(xn_t3451);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3452;

    }
#line 1691 "impl/lib/b2/xparser.x"
xn_Cls_E * e = xn_Cls_Parser_parseExpr(self);
xn_root_add(e);
xn_root_add(e);
xn_gc_safepoint();
#line 1692 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t3453 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3453);
xn_Cls_Tok * xn_t3454 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3454);
rt_string *xn_t3455 = rt_retain(xn_t3454->text);
xn_root_add(xn_t3455);
rt_string *xn_t3456 = rt_string_from_c("=");
xn_root_add(xn_t3456);
xn_Cls_Tok * xn_t3457 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3457);
rt_string *xn_t3458 = rt_retain(xn_t3457->text);
xn_root_add(xn_t3458);
rt_string *xn_t3459 = rt_string_from_c("+=");
xn_root_add(xn_t3459);
xn_Cls_Tok * xn_t3460 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3460);
rt_string *xn_t3461 = rt_retain(xn_t3460->text);
xn_root_add(xn_t3461);
rt_string *xn_t3462 = rt_string_from_c("-=");
xn_root_add(xn_t3462);
xn_Cls_Tok * xn_t3463 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3463);
rt_string *xn_t3464 = rt_retain(xn_t3463->text);
xn_root_add(xn_t3464);
rt_string *xn_t3465 = rt_string_from_c("*=");
xn_root_add(xn_t3465);
xn_Cls_Tok * xn_t3466 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3466);
rt_string *xn_t3467 = rt_retain(xn_t3466->text);
xn_root_add(xn_t3467);
rt_string *xn_t3468 = rt_string_from_c("/=");
xn_root_add(xn_t3468);
xn_Cls_Tok * xn_t3469 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3469);
rt_string *xn_t3470 = rt_retain(xn_t3469->text);
xn_root_add(xn_t3470);
rt_string *xn_t3471 = rt_string_from_c("%=");
xn_root_add(xn_t3471);
xn_Cls_Tok * xn_t3472 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3472);
rt_string *xn_t3473 = rt_retain(xn_t3472->text);
xn_root_add(xn_t3473);
rt_string *xn_t3474 = rt_string_from_c("&=");
xn_root_add(xn_t3474);
xn_Cls_Tok * xn_t3475 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3475);
rt_string *xn_t3476 = rt_retain(xn_t3475->text);
xn_root_add(xn_t3476);
rt_string *xn_t3477 = rt_string_from_c("|=");
xn_root_add(xn_t3477);
xn_Cls_Tok * xn_t3478 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3478);
rt_string *xn_t3479 = rt_retain(xn_t3478->text);
xn_root_add(xn_t3479);
rt_string *xn_t3480 = rt_string_from_c("^=");
xn_root_add(xn_t3480);
xn_Cls_Tok * xn_t3481 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3481);
rt_string *xn_t3482 = rt_retain(xn_t3481->text);
xn_root_add(xn_t3482);
rt_string *xn_t3483 = rt_string_from_c("<<=");
xn_root_add(xn_t3483);
xn_Cls_Tok * xn_t3484 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3484);
rt_string *xn_t3485 = rt_retain(xn_t3484->text);
xn_root_add(xn_t3485);
rt_string *xn_t3486 = rt_string_from_c(">>=");
xn_root_add(xn_t3486);
    if ((((xn_t3453->kind == 9)) && (((((((((((xn_str_eq(xn_t3455, xn_t3456) || xn_str_eq(xn_t3458, xn_t3459)) || xn_str_eq(xn_t3461, xn_t3462)) || xn_str_eq(xn_t3464, xn_t3465)) || xn_str_eq(xn_t3467, xn_t3468)) || xn_str_eq(xn_t3470, xn_t3471)) || xn_str_eq(xn_t3473, xn_t3474)) || xn_str_eq(xn_t3476, xn_t3477)) || xn_str_eq(xn_t3479, xn_t3480)) || xn_str_eq(xn_t3482, xn_t3483)) || xn_str_eq(xn_t3485, xn_t3486))))) {
        size_t xn_t3487 = xn_root_mark();
        #line 1695 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3488 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3488);
        xn_root_add(xn_t3488);
        rt_string *op = rt_retain(xn_t3488->text);
xn_root_add(op);
        xn_root_add(op);
        xn_root_add(op);
        xn_gc_safepoint();
        #line 1696 "impl/lib/b2/xparser.x"
        xn_Cls_E * v = xn_Cls_Parser_parseExpr(self);
xn_root_add(v);
        xn_root_add(v);
        xn_root_add(v);
        xn_gc_safepoint();
        #line 1697 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 1))) {
                size_t xn_t3490 = xn_root_mark();
                #line 1697 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t3490);
                    }

            }
        #line 1698 "impl/lib/b2/xparser.x"
        rt_string *xn_t3491 = rt_string_from_c("(AssignStmt ");
xn_root_add(xn_t3491);
        xn_root_add(xn_t3491);
        xn_root_add(xn_t3491);
        rt_string *xn_t3492 = xn_P(e->l, e->c);
xn_root_add(xn_t3492);
        xn_root_add(xn_t3492);
        xn_root_add(xn_t3492);
        rt_string *xn_t3493 = xn_concat(xn_t3491, xn_t3492);
xn_root_add(xn_t3493);
        xn_root_add(xn_t3493);
        xn_root_add(xn_t3493);
        rt_string *xn_t3494 = rt_string_from_c(" (Target ");
xn_root_add(xn_t3494);
        xn_root_add(xn_t3494);
        xn_root_add(xn_t3494);
        rt_string *xn_t3495 = xn_concat(xn_t3493, xn_t3494);
xn_root_add(xn_t3495);
        xn_root_add(xn_t3495);
        xn_root_add(xn_t3495);
        rt_string *xn_t3496 = rt_retain(e->d);
xn_root_add(xn_t3496);
        xn_root_add(xn_t3496);
        xn_root_add(xn_t3496);
        rt_string *xn_t3497 = xn_concat(xn_t3495, xn_t3496);
xn_root_add(xn_t3497);
        xn_root_add(xn_t3497);
        xn_root_add(xn_t3497);
        rt_string *xn_t3498 = rt_string_from_c(") (Op ");
xn_root_add(xn_t3498);
        xn_root_add(xn_t3498);
        xn_root_add(xn_t3498);
        rt_string *xn_t3499 = xn_concat(xn_t3497, xn_t3498);
xn_root_add(xn_t3499);
        xn_root_add(xn_t3499);
        xn_root_add(xn_t3499);
        rt_string *xn_t3500 = rt_retain(op);
xn_root_add(xn_t3500);
        xn_root_add(xn_t3500);
        xn_root_add(xn_t3500);
        rt_string *xn_t3501 = xn_q(xn_t3500);
xn_root_add(xn_t3501);
        xn_root_add(xn_t3501);
        xn_root_add(xn_t3501);
        rt_string *xn_t3502 = xn_concat(xn_t3499, xn_t3501);
xn_root_add(xn_t3502);
        xn_root_add(xn_t3502);
        xn_root_add(xn_t3502);
        rt_string *xn_t3503 = rt_string_from_c(") (Value ");
xn_root_add(xn_t3503);
        xn_root_add(xn_t3503);
        xn_root_add(xn_t3503);
        rt_string *xn_t3504 = xn_concat(xn_t3502, xn_t3503);
xn_root_add(xn_t3504);
        xn_root_add(xn_t3504);
        xn_root_add(xn_t3504);
        rt_string *xn_t3505 = rt_retain(v->d);
xn_root_add(xn_t3505);
        xn_root_add(xn_t3505);
        xn_root_add(xn_t3505);
        rt_string *xn_t3506 = xn_concat(xn_t3504, xn_t3505);
xn_root_add(xn_t3506);
        xn_root_add(xn_t3506);
        xn_root_add(xn_t3506);
        rt_string *xn_t3507 = rt_string_from_c("))");
xn_root_add(xn_t3507);
        xn_root_add(xn_t3507);
        xn_root_add(xn_t3507);
        rt_string *xn_t3508 = xn_concat(xn_t3506, xn_t3507);
xn_root_add(xn_t3508);
        xn_root_add(xn_t3508);
        xn_root_add(xn_t3508);
            {
        rt_release(op);
            }
            {
        xn_root_restore(xn_t3487);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3508;

    }
#line 1700 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t3509 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3509);
xn_Cls_Tok * xn_t3510 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3510);
rt_string *xn_t3511 = rt_retain(xn_t3510->text);
xn_root_add(xn_t3511);
rt_string *xn_t3512 = rt_string_from_c("++");
xn_root_add(xn_t3512);
xn_Cls_Tok * xn_t3513 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3513);
rt_string *xn_t3514 = rt_retain(xn_t3513->text);
xn_root_add(xn_t3514);
rt_string *xn_t3515 = rt_string_from_c("--");
xn_root_add(xn_t3515);
    if ((((xn_t3509->kind == 9)) && ((xn_str_eq(xn_t3511, xn_t3512) || xn_str_eq(xn_t3514, xn_t3515))))) {
        size_t xn_t3516 = xn_root_mark();
        #line 1701 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3517 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3517);
        xn_root_add(xn_t3517);
        rt_string *op = rt_retain(xn_t3517->text);
xn_root_add(op);
        xn_root_add(op);
        xn_root_add(op);
        xn_gc_safepoint();
        #line 1702 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 1))) {
                size_t xn_t3519 = xn_root_mark();
                #line 1702 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t3519);
                    }

            }
        #line 1703 "impl/lib/b2/xparser.x"
        rt_string *xn_t3520 = rt_string_from_c("(IncDecStmt ");
xn_root_add(xn_t3520);
        xn_root_add(xn_t3520);
        xn_root_add(xn_t3520);
        rt_string *xn_t3521 = xn_P(e->l, e->c);
xn_root_add(xn_t3521);
        xn_root_add(xn_t3521);
        xn_root_add(xn_t3521);
        rt_string *xn_t3522 = xn_concat(xn_t3520, xn_t3521);
xn_root_add(xn_t3522);
        xn_root_add(xn_t3522);
        xn_root_add(xn_t3522);
        rt_string *xn_t3523 = rt_string_from_c(" (Target ");
xn_root_add(xn_t3523);
        xn_root_add(xn_t3523);
        xn_root_add(xn_t3523);
        rt_string *xn_t3524 = xn_concat(xn_t3522, xn_t3523);
xn_root_add(xn_t3524);
        xn_root_add(xn_t3524);
        xn_root_add(xn_t3524);
        rt_string *xn_t3525 = rt_retain(e->d);
xn_root_add(xn_t3525);
        xn_root_add(xn_t3525);
        xn_root_add(xn_t3525);
        rt_string *xn_t3526 = xn_concat(xn_t3524, xn_t3525);
xn_root_add(xn_t3526);
        xn_root_add(xn_t3526);
        xn_root_add(xn_t3526);
        rt_string *xn_t3527 = rt_string_from_c(") (Op ");
xn_root_add(xn_t3527);
        xn_root_add(xn_t3527);
        xn_root_add(xn_t3527);
        rt_string *xn_t3528 = xn_concat(xn_t3526, xn_t3527);
xn_root_add(xn_t3528);
        xn_root_add(xn_t3528);
        xn_root_add(xn_t3528);
        rt_string *xn_t3529 = rt_retain(op);
xn_root_add(xn_t3529);
        xn_root_add(xn_t3529);
        xn_root_add(xn_t3529);
        rt_string *xn_t3530 = xn_q(xn_t3529);
xn_root_add(xn_t3530);
        xn_root_add(xn_t3530);
        xn_root_add(xn_t3530);
        rt_string *xn_t3531 = xn_concat(xn_t3528, xn_t3530);
xn_root_add(xn_t3531);
        xn_root_add(xn_t3531);
        xn_root_add(xn_t3531);
        rt_string *xn_t3532 = rt_string_from_c(") (Prefix false))");
xn_root_add(xn_t3532);
        xn_root_add(xn_t3532);
        xn_root_add(xn_t3532);
        rt_string *xn_t3533 = xn_concat(xn_t3531, xn_t3532);
xn_root_add(xn_t3533);
        xn_root_add(xn_t3533);
        xn_root_add(xn_t3533);
            {
        rt_release(op);
            }
            {
        xn_root_restore(xn_t3516);
            }
            {
        xn_root_restore(xn_t3328);
            }

        return xn_t3533;

    }
#line 1705 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 1))) {
        size_t xn_t3534 = xn_root_mark();
        #line 1705 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3534);
            }

    }
#line 1706 "impl/lib/b2/xparser.x"
rt_string *xn_t3535 = rt_string_from_c("(ExprStmt ");
xn_root_add(xn_t3535);
xn_root_add(xn_t3535);
rt_string *xn_t3536 = xn_P(e->sl, e->sc);
xn_root_add(xn_t3536);
xn_root_add(xn_t3536);
rt_string *xn_t3537 = xn_concat(xn_t3535, xn_t3536);
xn_root_add(xn_t3537);
xn_root_add(xn_t3537);
rt_string *xn_t3538 = rt_string_from_c(" (X ");
xn_root_add(xn_t3538);
xn_root_add(xn_t3538);
rt_string *xn_t3539 = xn_concat(xn_t3537, xn_t3538);
xn_root_add(xn_t3539);
xn_root_add(xn_t3539);
rt_string *xn_t3540 = rt_retain(e->d);
xn_root_add(xn_t3540);
xn_root_add(xn_t3540);
rt_string *xn_t3541 = xn_concat(xn_t3539, xn_t3540);
xn_root_add(xn_t3541);
xn_root_add(xn_t3541);
rt_string *xn_t3542 = rt_string_from_c("))");
xn_root_add(xn_t3542);
xn_root_add(xn_t3542);
rt_string *xn_t3543 = xn_concat(xn_t3541, xn_t3542);
xn_root_add(xn_t3543);
xn_root_add(xn_t3543);
    {
xn_root_restore(xn_t3328);
    }

return xn_t3543;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseLocal(xn_Cls_Parser *self) {
size_t xn_t3544 = xn_root_mark();
xn_root_add(self);
#line 1710 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_cur(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1711 "impl/lib/b2/xparser.x"
int fin = 0;
#line 1712 "impl/lib/b2/xparser.x"
int cons = 0;
#line 1713 "impl/lib/b2/xparser.x"
int vr = 0;
#line 1714 "impl/lib/b2/xparser.x"
rt_string *xn_t3545 = rt_string_from_c("final");
xn_root_add(xn_t3545);
    if ((xn_Cls_Parser_atKw(self, xn_t3545))) {
        size_t xn_t3546 = xn_root_mark();
        #line 1714 "impl/lib/b2/xparser.x"
        fin = 1;
        #line 1714 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3546);
            }

    } else {
        rt_string *xn_t3548 = rt_string_from_c("const");
xn_root_add(xn_t3548);
        xn_root_add(xn_t3548);
            if ((xn_Cls_Parser_atKw(self, xn_t3548))) {
                size_t xn_t3549 = xn_root_mark();
                #line 1715 "impl/lib/b2/xparser.x"
                cons = 1;
                #line 1715 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t3549);
                    }

            } else {
                rt_string *xn_t3551 = rt_string_from_c("var");
xn_root_add(xn_t3551);
        xn_root_add(xn_t3551);
                xn_root_add(xn_t3551);
                    if ((xn_Cls_Parser_atKw(self, xn_t3551))) {
                        size_t xn_t3552 = xn_root_mark();
                        #line 1716 "impl/lib/b2/xparser.x"
                        vr = 1;
                        #line 1716 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t3552);
                            }

                    }
            }
    }
#line 1717 "impl/lib/b2/xparser.x"
rt_string *ty = rt_string_from_c("(nil)");
xn_root_add(ty);
xn_root_add(ty);
xn_gc_safepoint();
#line 1718 "impl/lib/b2/xparser.x"
    if (((!(vr)))) {
        size_t xn_t3554 = xn_root_mark();
        #line 1718 "impl/lib/b2/xparser.x"
        rt_string *xn_t3555 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t3555);
        xn_root_add(xn_t3555);
        xn_root_release(ty);
        rt_release(ty);
        ty = xn_t3555;
        xn_root_hold(ty);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t3554);
            }

    }
#line 1719 "impl/lib/b2/xparser.x"
rt_string *nm = rt_string_from_c("");
xn_root_add(nm);
xn_root_add(nm);
xn_gc_safepoint();
#line 1720 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 2))) {
        size_t xn_t3557 = xn_root_mark();
        #line 1720 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3558 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3558);
        xn_root_add(xn_t3558);
        rt_string *xn_t3559 = rt_retain(xn_t3558->text);
xn_root_add(xn_t3559);
        xn_root_add(xn_t3559);
        xn_root_release(nm);
        rt_release(nm);
        nm = xn_t3559;
        xn_root_hold(nm);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t3557);
            }

    }
#line 1721 "impl/lib/b2/xparser.x"
rt_string *init = rt_string_from_c("(nil)");
xn_root_add(init);
xn_root_add(init);
xn_gc_safepoint();
#line 1722 "impl/lib/b2/xparser.x"
rt_string *xn_t3561 = rt_string_from_c("=");
xn_root_add(xn_t3561);
    if ((xn_Cls_Parser_atOp(self, xn_t3561))) {
        size_t xn_t3562 = xn_root_mark();
        #line 1722 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1722 "impl/lib/b2/xparser.x"
        xn_Cls_E * xn_t3563 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t3563);
        xn_root_add(xn_t3563);
        rt_string *xn_t3564 = rt_retain(xn_t3563->d);
xn_root_add(xn_t3564);
        xn_root_add(xn_t3564);
        xn_root_release(init);
        rt_release(init);
        init = xn_t3564;
        xn_root_hold(init);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t3562);
            }

    }
#line 1723 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 1))) {
        size_t xn_t3565 = xn_root_mark();
        #line 1723 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3565);
            }

    }
#line 1724 "impl/lib/b2/xparser.x"
rt_string *xn_t3566 = rt_string_from_c("(LocalDeclStmt ");
xn_root_add(xn_t3566);
xn_root_add(xn_t3566);
rt_string *xn_t3567 = xn_P(t->line, t->col);
xn_root_add(xn_t3567);
xn_root_add(xn_t3567);
rt_string *xn_t3568 = xn_concat(xn_t3566, xn_t3567);
xn_root_add(xn_t3568);
xn_root_add(xn_t3568);
rt_string *xn_t3569 = rt_string_from_c(" (Final ");
xn_root_add(xn_t3569);
xn_root_add(xn_t3569);
rt_string *xn_t3570 = xn_concat(xn_t3568, xn_t3569);
xn_root_add(xn_t3570);
xn_root_add(xn_t3570);
rt_string *xn_t3571 = xn_B(fin);
xn_root_add(xn_t3571);
xn_root_add(xn_t3571);
rt_string *xn_t3572 = xn_concat(xn_t3570, xn_t3571);
xn_root_add(xn_t3572);
xn_root_add(xn_t3572);
rt_string *xn_t3573 = rt_string_from_c(") (Const ");
xn_root_add(xn_t3573);
xn_root_add(xn_t3573);
rt_string *xn_t3574 = xn_concat(xn_t3572, xn_t3573);
xn_root_add(xn_t3574);
xn_root_add(xn_t3574);
rt_string *xn_t3575 = xn_B(cons);
xn_root_add(xn_t3575);
xn_root_add(xn_t3575);
rt_string *xn_t3576 = xn_concat(xn_t3574, xn_t3575);
xn_root_add(xn_t3576);
xn_root_add(xn_t3576);
rt_string *xn_t3577 = rt_string_from_c(") (Var ");
xn_root_add(xn_t3577);
xn_root_add(xn_t3577);
rt_string *xn_t3578 = xn_concat(xn_t3576, xn_t3577);
xn_root_add(xn_t3578);
xn_root_add(xn_t3578);
rt_string *xn_t3579 = xn_B(vr);
xn_root_add(xn_t3579);
xn_root_add(xn_t3579);
rt_string *xn_t3580 = xn_concat(xn_t3578, xn_t3579);
xn_root_add(xn_t3580);
xn_root_add(xn_t3580);
rt_string *xn_t3581 = rt_string_from_c(") (Type ");
xn_root_add(xn_t3581);
xn_root_add(xn_t3581);
rt_string *xn_t3582 = xn_concat(xn_t3580, xn_t3581);
xn_root_add(xn_t3582);
xn_root_add(xn_t3582);
rt_string *xn_t3583 = rt_retain(ty);
xn_root_add(xn_t3583);
xn_root_add(xn_t3583);
rt_string *xn_t3584 = xn_concat(xn_t3582, xn_t3583);
xn_root_add(xn_t3584);
xn_root_add(xn_t3584);
rt_string *xn_t3585 = rt_string_from_c(") (Name ");
xn_root_add(xn_t3585);
xn_root_add(xn_t3585);
rt_string *xn_t3586 = xn_concat(xn_t3584, xn_t3585);
xn_root_add(xn_t3586);
xn_root_add(xn_t3586);
rt_string *xn_t3587 = rt_retain(nm);
xn_root_add(xn_t3587);
xn_root_add(xn_t3587);
rt_string *xn_t3588 = xn_q(xn_t3587);
xn_root_add(xn_t3588);
xn_root_add(xn_t3588);
rt_string *xn_t3589 = xn_concat(xn_t3586, xn_t3588);
xn_root_add(xn_t3589);
xn_root_add(xn_t3589);
rt_string *xn_t3590 = rt_string_from_c(") (Init ");
xn_root_add(xn_t3590);
xn_root_add(xn_t3590);
rt_string *xn_t3591 = xn_concat(xn_t3589, xn_t3590);
xn_root_add(xn_t3591);
xn_root_add(xn_t3591);
rt_string *xn_t3592 = rt_retain(init);
xn_root_add(xn_t3592);
xn_root_add(xn_t3592);
rt_string *xn_t3593 = xn_concat(xn_t3591, xn_t3592);
xn_root_add(xn_t3593);
xn_root_add(xn_t3593);
rt_string *xn_t3594 = rt_string_from_c("))");
xn_root_add(xn_t3594);
xn_root_add(xn_t3594);
rt_string *xn_t3595 = xn_concat(xn_t3593, xn_t3594);
xn_root_add(xn_t3595);
xn_root_add(xn_t3595);
    {
rt_release(init);
    }
    {
rt_release(nm);
    }
    {
rt_release(ty);
    }
    {
xn_root_restore(xn_t3544);
    }

return xn_t3595;
xn_root_release(ty);
xn_root_release(nm);
xn_root_release(init);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseIf(xn_Cls_Parser *self) {
size_t xn_t3596 = xn_root_mark();
xn_root_add(self);
#line 1729 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_next(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1730 "impl/lib/b2/xparser.x"
xn_Cls_E * c = xn_Cls_Parser_parseExpr(self);
xn_root_add(c);
xn_root_add(c);
xn_gc_safepoint();
#line 1731 "impl/lib/b2/xparser.x"
rt_string *th = xn_Cls_Parser_parseBlock(self);
xn_root_add(th);
xn_root_add(th);
xn_gc_safepoint();
#line 1732 "impl/lib/b2/xparser.x"
rt_string *el = rt_string_from_c("(nil)");
xn_root_add(el);
xn_root_add(el);
xn_gc_safepoint();
#line 1733 "impl/lib/b2/xparser.x"
rt_string *xn_t3599 = rt_string_from_c("else");
xn_root_add(xn_t3599);
    if ((xn_Cls_Parser_atKw(self, xn_t3599))) {
        size_t xn_t3600 = xn_root_mark();
        #line 1734 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1735 "impl/lib/b2/xparser.x"
        rt_string *xn_t3601 = rt_string_from_c("if");
xn_root_add(xn_t3601);
        xn_root_add(xn_t3601);
            if ((xn_Cls_Parser_atKw(self, xn_t3601))) {
                size_t xn_t3602 = xn_root_mark();
                #line 1735 "impl/lib/b2/xparser.x"
                rt_string *xn_t3603 = xn_Cls_Parser_parseIf(self);
xn_root_add(xn_t3603);
        xn_root_add(xn_t3603);
                xn_root_add(xn_t3603);
                xn_root_release(el);
                rt_release(el);
                el = xn_t3603;
                xn_root_hold(el);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t3602);
                    }

            } else {
                size_t xn_t3604 = xn_root_mark();
                #line 1735 "impl/lib/b2/xparser.x"
                rt_string *xn_t3605 = xn_Cls_Parser_parseBlock(self);
xn_root_add(xn_t3605);
        xn_root_add(xn_t3605);
                xn_root_add(xn_t3605);
                xn_root_release(el);
                rt_release(el);
                el = xn_t3605;
                xn_root_hold(el);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t3604);
                    }

            }
            {
            xn_root_restore(xn_t3600);
            }

    }
#line 1737 "impl/lib/b2/xparser.x"
rt_string *xn_t3606 = rt_string_from_c("(IfStmt ");
xn_root_add(xn_t3606);
xn_root_add(xn_t3606);
rt_string *xn_t3607 = xn_P(t->line, t->col);
xn_root_add(xn_t3607);
xn_root_add(xn_t3607);
rt_string *xn_t3608 = xn_concat(xn_t3606, xn_t3607);
xn_root_add(xn_t3608);
xn_root_add(xn_t3608);
rt_string *xn_t3609 = rt_string_from_c(" (Cond ");
xn_root_add(xn_t3609);
xn_root_add(xn_t3609);
rt_string *xn_t3610 = xn_concat(xn_t3608, xn_t3609);
xn_root_add(xn_t3610);
xn_root_add(xn_t3610);
rt_string *xn_t3611 = rt_retain(c->d);
xn_root_add(xn_t3611);
xn_root_add(xn_t3611);
rt_string *xn_t3612 = xn_concat(xn_t3610, xn_t3611);
xn_root_add(xn_t3612);
xn_root_add(xn_t3612);
rt_string *xn_t3613 = rt_string_from_c(") (Then ");
xn_root_add(xn_t3613);
xn_root_add(xn_t3613);
rt_string *xn_t3614 = xn_concat(xn_t3612, xn_t3613);
xn_root_add(xn_t3614);
xn_root_add(xn_t3614);
rt_string *xn_t3615 = rt_retain(th);
xn_root_add(xn_t3615);
xn_root_add(xn_t3615);
rt_string *xn_t3616 = xn_concat(xn_t3614, xn_t3615);
xn_root_add(xn_t3616);
xn_root_add(xn_t3616);
rt_string *xn_t3617 = rt_string_from_c(") (Else ");
xn_root_add(xn_t3617);
xn_root_add(xn_t3617);
rt_string *xn_t3618 = xn_concat(xn_t3616, xn_t3617);
xn_root_add(xn_t3618);
xn_root_add(xn_t3618);
rt_string *xn_t3619 = rt_retain(el);
xn_root_add(xn_t3619);
xn_root_add(xn_t3619);
rt_string *xn_t3620 = xn_concat(xn_t3618, xn_t3619);
xn_root_add(xn_t3620);
xn_root_add(xn_t3620);
rt_string *xn_t3621 = rt_string_from_c("))");
xn_root_add(xn_t3621);
xn_root_add(xn_t3621);
rt_string *xn_t3622 = xn_concat(xn_t3620, xn_t3621);
xn_root_add(xn_t3622);
xn_root_add(xn_t3622);
    {
rt_release(el);
    }
    {
rt_release(th);
    }
    {
xn_root_restore(xn_t3596);
    }

return xn_t3622;
xn_root_release(el);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseWhile(xn_Cls_Parser *self) {
size_t xn_t3623 = xn_root_mark();
xn_root_add(self);
#line 1741 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_next(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1742 "impl/lib/b2/xparser.x"
xn_Cls_E * c = xn_Cls_Parser_parseExpr(self);
xn_root_add(c);
xn_root_add(c);
xn_gc_safepoint();
#line 1743 "impl/lib/b2/xparser.x"
rt_string *b = xn_Cls_Parser_parseBlock(self);
xn_root_add(b);
xn_root_add(b);
xn_gc_safepoint();
#line 1744 "impl/lib/b2/xparser.x"
rt_string *xn_t3625 = rt_string_from_c("(WhileStmt ");
xn_root_add(xn_t3625);
xn_root_add(xn_t3625);
rt_string *xn_t3626 = xn_P(t->line, t->col);
xn_root_add(xn_t3626);
xn_root_add(xn_t3626);
rt_string *xn_t3627 = xn_concat(xn_t3625, xn_t3626);
xn_root_add(xn_t3627);
xn_root_add(xn_t3627);
rt_string *xn_t3628 = rt_string_from_c(" (Cond ");
xn_root_add(xn_t3628);
xn_root_add(xn_t3628);
rt_string *xn_t3629 = xn_concat(xn_t3627, xn_t3628);
xn_root_add(xn_t3629);
xn_root_add(xn_t3629);
rt_string *xn_t3630 = rt_retain(c->d);
xn_root_add(xn_t3630);
xn_root_add(xn_t3630);
rt_string *xn_t3631 = xn_concat(xn_t3629, xn_t3630);
xn_root_add(xn_t3631);
xn_root_add(xn_t3631);
rt_string *xn_t3632 = rt_string_from_c(") (Body ");
xn_root_add(xn_t3632);
xn_root_add(xn_t3632);
rt_string *xn_t3633 = xn_concat(xn_t3631, xn_t3632);
xn_root_add(xn_t3633);
xn_root_add(xn_t3633);
rt_string *xn_t3634 = rt_retain(b);
xn_root_add(xn_t3634);
xn_root_add(xn_t3634);
rt_string *xn_t3635 = xn_concat(xn_t3633, xn_t3634);
xn_root_add(xn_t3635);
xn_root_add(xn_t3635);
rt_string *xn_t3636 = rt_string_from_c("))");
xn_root_add(xn_t3636);
xn_root_add(xn_t3636);
rt_string *xn_t3637 = xn_concat(xn_t3635, xn_t3636);
xn_root_add(xn_t3637);
xn_root_add(xn_t3637);
    {
rt_release(b);
    }
    {
xn_root_restore(xn_t3623);
    }

return xn_t3637;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseDo(xn_Cls_Parser *self) {
size_t xn_t3638 = xn_root_mark();
xn_root_add(self);
#line 1748 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_next(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1749 "impl/lib/b2/xparser.x"
rt_string *b = xn_Cls_Parser_parseBlock(self);
xn_root_add(b);
xn_root_add(b);
xn_gc_safepoint();
#line 1750 "impl/lib/b2/xparser.x"
rt_string *xn_t3640 = rt_string_from_c("while");
xn_root_add(xn_t3640);
    if ((xn_Cls_Parser_atKw(self, xn_t3640))) {
        size_t xn_t3641 = xn_root_mark();
        #line 1750 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3641);
            }

    }
#line 1751 "impl/lib/b2/xparser.x"
xn_Cls_E * c = xn_Cls_Parser_parseExpr(self);
xn_root_add(c);
xn_root_add(c);
xn_gc_safepoint();
#line 1752 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 1))) {
        size_t xn_t3642 = xn_root_mark();
        #line 1752 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3642);
            }

    }
#line 1753 "impl/lib/b2/xparser.x"
rt_string *xn_t3643 = rt_string_from_c("(DoWhileStmt ");
xn_root_add(xn_t3643);
xn_root_add(xn_t3643);
rt_string *xn_t3644 = xn_P(t->line, t->col);
xn_root_add(xn_t3644);
xn_root_add(xn_t3644);
rt_string *xn_t3645 = xn_concat(xn_t3643, xn_t3644);
xn_root_add(xn_t3645);
xn_root_add(xn_t3645);
rt_string *xn_t3646 = rt_string_from_c(" (Body ");
xn_root_add(xn_t3646);
xn_root_add(xn_t3646);
rt_string *xn_t3647 = xn_concat(xn_t3645, xn_t3646);
xn_root_add(xn_t3647);
xn_root_add(xn_t3647);
rt_string *xn_t3648 = rt_retain(b);
xn_root_add(xn_t3648);
xn_root_add(xn_t3648);
rt_string *xn_t3649 = xn_concat(xn_t3647, xn_t3648);
xn_root_add(xn_t3649);
xn_root_add(xn_t3649);
rt_string *xn_t3650 = rt_string_from_c(") (Cond ");
xn_root_add(xn_t3650);
xn_root_add(xn_t3650);
rt_string *xn_t3651 = xn_concat(xn_t3649, xn_t3650);
xn_root_add(xn_t3651);
xn_root_add(xn_t3651);
rt_string *xn_t3652 = rt_retain(c->d);
xn_root_add(xn_t3652);
xn_root_add(xn_t3652);
rt_string *xn_t3653 = xn_concat(xn_t3651, xn_t3652);
xn_root_add(xn_t3653);
xn_root_add(xn_t3653);
rt_string *xn_t3654 = rt_string_from_c("))");
xn_root_add(xn_t3654);
xn_root_add(xn_t3654);
rt_string *xn_t3655 = xn_concat(xn_t3653, xn_t3654);
xn_root_add(xn_t3655);
xn_root_add(xn_t3655);
    {
rt_release(b);
    }
    {
xn_root_restore(xn_t3638);
    }

return xn_t3655;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseFor(xn_Cls_Parser *self) {
size_t xn_t3656 = xn_root_mark();
xn_root_add(self);
#line 1757 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_next(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1758 "impl/lib/b2/xparser.x"
rt_string *v = rt_string_from_c("");
xn_root_add(v);
xn_root_add(v);
xn_gc_safepoint();
#line 1759 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 2))) {
        size_t xn_t3658 = xn_root_mark();
        #line 1759 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * xn_t3659 = xn_Cls_Parser_next(self);
xn_root_add(xn_t3659);
        xn_root_add(xn_t3659);
        rt_string *xn_t3660 = rt_retain(xn_t3659->text);
xn_root_add(xn_t3660);
        xn_root_add(xn_t3660);
        xn_root_release(v);
        rt_release(v);
        v = xn_t3660;
        xn_root_hold(v);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t3658);
            }

    }
#line 1760 "impl/lib/b2/xparser.x"
rt_string *xn_t3661 = rt_string_from_c("in");
xn_root_add(xn_t3661);
    if ((xn_Cls_Parser_atKw(self, xn_t3661))) {
        size_t xn_t3662 = xn_root_mark();
        #line 1760 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3662);
            }

    }
#line 1761 "impl/lib/b2/xparser.x"
xn_Cls_E * src = xn_Cls_Parser_parseExpr(self);
xn_root_add(src);
xn_root_add(src);
xn_gc_safepoint();
#line 1762 "impl/lib/b2/xparser.x"
rt_string *b = xn_Cls_Parser_parseBlock(self);
xn_root_add(b);
xn_root_add(b);
xn_gc_safepoint();
#line 1763 "impl/lib/b2/xparser.x"
rt_string *xn_t3664 = rt_string_from_c("(ForStmt ");
xn_root_add(xn_t3664);
xn_root_add(xn_t3664);
rt_string *xn_t3665 = xn_P(t->line, t->col);
xn_root_add(xn_t3665);
xn_root_add(xn_t3665);
rt_string *xn_t3666 = xn_concat(xn_t3664, xn_t3665);
xn_root_add(xn_t3666);
xn_root_add(xn_t3666);
rt_string *xn_t3667 = rt_string_from_c(" (Var ");
xn_root_add(xn_t3667);
xn_root_add(xn_t3667);
rt_string *xn_t3668 = xn_concat(xn_t3666, xn_t3667);
xn_root_add(xn_t3668);
xn_root_add(xn_t3668);
rt_string *xn_t3669 = rt_retain(v);
xn_root_add(xn_t3669);
xn_root_add(xn_t3669);
rt_string *xn_t3670 = xn_q(xn_t3669);
xn_root_add(xn_t3670);
xn_root_add(xn_t3670);
rt_string *xn_t3671 = xn_concat(xn_t3668, xn_t3670);
xn_root_add(xn_t3671);
xn_root_add(xn_t3671);
rt_string *xn_t3672 = rt_string_from_c(") (Src ");
xn_root_add(xn_t3672);
xn_root_add(xn_t3672);
rt_string *xn_t3673 = xn_concat(xn_t3671, xn_t3672);
xn_root_add(xn_t3673);
xn_root_add(xn_t3673);
rt_string *xn_t3674 = rt_retain(src->d);
xn_root_add(xn_t3674);
xn_root_add(xn_t3674);
rt_string *xn_t3675 = xn_concat(xn_t3673, xn_t3674);
xn_root_add(xn_t3675);
xn_root_add(xn_t3675);
rt_string *xn_t3676 = rt_string_from_c(") (Body ");
xn_root_add(xn_t3676);
xn_root_add(xn_t3676);
rt_string *xn_t3677 = xn_concat(xn_t3675, xn_t3676);
xn_root_add(xn_t3677);
xn_root_add(xn_t3677);
rt_string *xn_t3678 = rt_retain(b);
xn_root_add(xn_t3678);
xn_root_add(xn_t3678);
rt_string *xn_t3679 = xn_concat(xn_t3677, xn_t3678);
xn_root_add(xn_t3679);
xn_root_add(xn_t3679);
rt_string *xn_t3680 = rt_string_from_c("))");
xn_root_add(xn_t3680);
xn_root_add(xn_t3680);
rt_string *xn_t3681 = xn_concat(xn_t3679, xn_t3680);
xn_root_add(xn_t3681);
xn_root_add(xn_t3681);
    {
rt_release(b);
    }
    {
rt_release(v);
    }
    {
xn_root_restore(xn_t3656);
    }

return xn_t3681;
xn_root_release(v);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseSwitch(xn_Cls_Parser *self) {
size_t xn_t3682 = xn_root_mark();
xn_root_add(self);
#line 1767 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_next(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1768 "impl/lib/b2/xparser.x"
xn_Cls_E * v = xn_Cls_Parser_parseExpr(self);
xn_root_add(v);
xn_root_add(v);
xn_gc_safepoint();
#line 1769 "impl/lib/b2/xparser.x"
xn_arr_s *xn_t3683 = xn_arr_s_new(0);
xn_root_add(xn_t3683);
xn_arr_s * cs = xn_t3683;
xn_root_add(cs);
xn_root_add(cs);
xn_gc_safepoint();
#line 1770 "impl/lib/b2/xparser.x"
rt_string *def = rt_string_from_c("(nil)");
xn_root_add(def);
xn_root_add(def);
xn_gc_safepoint();
#line 1771 "impl/lib/b2/xparser.x"
int sawDef = 0;
#line 1772 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 12))) {
        size_t xn_t3685 = xn_root_mark();
        #line 1772 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3685);
            }

    }
#line 1773 "impl/lib/b2/xparser.x"
    while ((((!(xn_Cls_Parser_at(self, 13)))) && ((!(xn_Cls_Parser_eof(self)))))) {
    size_t xn_t3686 = xn_root_mark();
    #line 1774 "impl/lib/b2/xparser.x"
        if ((xn_Cls_Parser_at(self, 1))) {
            size_t xn_t3687 = xn_root_mark();
            #line 1774 "impl/lib/b2/xparser.x"
            xn_Cls_Parser_next(self);
            #line 1774 "impl/lib/b2/xparser.x"
            xn_root_restore(xn_t3687);
            xn_root_restore(xn_t3686);
            continue;
                {
                xn_root_restore(xn_t3687);
                }

        }
    #line 1775 "impl/lib/b2/xparser.x"
    rt_string *xn_t3688 = rt_string_from_c("case");
xn_root_add(xn_t3688);
    xn_root_add(xn_t3688);
        if ((xn_Cls_Parser_atKw(self, xn_t3688))) {
            size_t xn_t3689 = xn_root_mark();
            #line 1776 "impl/lib/b2/xparser.x"
            xn_Cls_Tok * c = xn_Cls_Parser_next(self);
xn_root_add(c);
    xn_root_add(c);
            xn_root_add(c);
            xn_root_add(c);
            xn_gc_safepoint();
            #line 1777 "impl/lib/b2/xparser.x"
            xn_Cls_E * ex = xn_Cls_Parser_parseExpr(self);
xn_root_add(ex);
    xn_root_add(ex);
            xn_root_add(ex);
            xn_root_add(ex);
            xn_gc_safepoint();
            #line 1778 "impl/lib/b2/xparser.x"
            rt_string *xn_t3690 = rt_string_from_c(":");
xn_root_add(xn_t3690);
    xn_root_add(xn_t3690);
            xn_root_add(xn_t3690);
                if ((xn_Cls_Parser_atOp(self, xn_t3690))) {
                    size_t xn_t3691 = xn_root_mark();
                    #line 1778 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t3691);
                        }

                }
            #line 1779 "impl/lib/b2/xparser.x"
            xn_arr_s *xn_t3692 = xn_arr_s_new(0);
xn_root_add(xn_t3692);
    xn_root_add(xn_t3692);
            xn_root_add(xn_t3692);
            xn_arr_s * ss = xn_t3692;
xn_root_add(ss);
    xn_root_add(ss);
            xn_root_add(ss);
            xn_root_add(ss);
            xn_gc_safepoint();
            #line 1780 "impl/lib/b2/xparser.x"
                while (1) {
                    rt_string *xn_t3693 = rt_string_from_c("case");
xn_root_add(xn_t3693);
    xn_root_add(xn_t3693);
            xn_root_add(xn_t3693);
                    rt_string *xn_t3694 = rt_string_from_c("default");
xn_root_add(xn_t3694);
    xn_root_add(xn_t3694);
            xn_root_add(xn_t3694);
                    if (!((((((!(xn_Cls_Parser_atKw(self, xn_t3693)))) && ((!(xn_Cls_Parser_atKw(self, xn_t3694))))) && ((!(xn_Cls_Parser_at(self, 13))))) && ((!(xn_Cls_Parser_eof(self))))))) { break; }
                    size_t xn_t3695 = xn_root_mark();
                    #line 1781 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 1))) {
                            size_t xn_t3696 = xn_root_mark();
                            #line 1781 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                            #line 1781 "impl/lib/b2/xparser.x"
                            xn_root_restore(xn_t3696);
                            xn_root_restore(xn_t3695);
                            continue;
                                {
                                xn_root_restore(xn_t3696);
                                }

                        }
                    #line 1782 "impl/lib/b2/xparser.x"
                    rt_string *xn_t3697 = xn_Cls_Parser_parseStmt(self);
xn_root_add(xn_t3697);
    xn_root_add(xn_t3697);
            xn_root_add(xn_t3697);
                    xn_root_add(xn_t3697);
                    xn_arr_s_push(ss, xn_t3697);
                        {
                        xn_root_restore(xn_t3695);
                        }

                    xn_gc_safepoint();
                }
            #line 1784 "impl/lib/b2/xparser.x"
            rt_string *xn_t3698 = rt_string_from_c("(SwitchCase ");
xn_root_add(xn_t3698);
    xn_root_add(xn_t3698);
            xn_root_add(xn_t3698);
            rt_string *xn_t3699 = xn_P(c->line, c->col);
xn_root_add(xn_t3699);
    xn_root_add(xn_t3699);
            xn_root_add(xn_t3699);
            rt_string *xn_t3700 = xn_concat(xn_t3698, xn_t3699);
xn_root_add(xn_t3700);
    xn_root_add(xn_t3700);
            xn_root_add(xn_t3700);
            rt_string *xn_t3701 = rt_string_from_c(" (Expr ");
xn_root_add(xn_t3701);
    xn_root_add(xn_t3701);
            xn_root_add(xn_t3701);
            rt_string *xn_t3702 = xn_concat(xn_t3700, xn_t3701);
xn_root_add(xn_t3702);
    xn_root_add(xn_t3702);
            xn_root_add(xn_t3702);
            rt_string *xn_t3703 = rt_retain(ex->d);
xn_root_add(xn_t3703);
    xn_root_add(xn_t3703);
            xn_root_add(xn_t3703);
            rt_string *xn_t3704 = xn_concat(xn_t3702, xn_t3703);
xn_root_add(xn_t3704);
    xn_root_add(xn_t3704);
            xn_root_add(xn_t3704);
            rt_string *xn_t3705 = rt_string_from_c(") (Stmts ");
xn_root_add(xn_t3705);
    xn_root_add(xn_t3705);
            xn_root_add(xn_t3705);
            rt_string *xn_t3706 = xn_concat(xn_t3704, xn_t3705);
xn_root_add(xn_t3706);
    xn_root_add(xn_t3706);
            xn_root_add(xn_t3706);
            rt_string *xn_t3707 = xn_SL(ss);
xn_root_add(xn_t3707);
    xn_root_add(xn_t3707);
            xn_root_add(xn_t3707);
            rt_string *xn_t3708 = xn_concat(xn_t3706, xn_t3707);
xn_root_add(xn_t3708);
    xn_root_add(xn_t3708);
            xn_root_add(xn_t3708);
            rt_string *xn_t3709 = rt_string_from_c(") (Default false))");
xn_root_add(xn_t3709);
    xn_root_add(xn_t3709);
            xn_root_add(xn_t3709);
            rt_string *xn_t3710 = xn_concat(xn_t3708, xn_t3709);
xn_root_add(xn_t3710);
    xn_root_add(xn_t3710);
            xn_root_add(xn_t3710);
            xn_arr_s_push(cs, xn_t3710);
                {
                xn_root_restore(xn_t3689);
                }

        } else {
            rt_string *xn_t3712 = rt_string_from_c("default");
xn_root_add(xn_t3712);
    xn_root_add(xn_t3712);
            xn_root_add(xn_t3712);
                if ((xn_Cls_Parser_atKw(self, xn_t3712))) {
                    size_t xn_t3713 = xn_root_mark();
                    #line 1786 "impl/lib/b2/xparser.x"
                    xn_Cls_Tok * c = xn_Cls_Parser_next(self);
xn_root_add(c);
    xn_root_add(c);
            xn_root_add(c);
                    xn_root_add(c);
                    xn_root_add(c);
                    xn_gc_safepoint();
                    #line 1787 "impl/lib/b2/xparser.x"
                        if ((sawDef)) {
                            size_t xn_t3714 = xn_root_mark();
                            #line 1788 "impl/lib/b2/xparser.x"
                            rt_string *xn_t3715 = rt_string_from_c("SYN-101");
xn_root_add(xn_t3715);
    xn_root_add(xn_t3715);
            xn_root_add(xn_t3715);
                    xn_root_add(xn_t3715);
                            xn_root_add(xn_t3715);
                            rt_string *xn_t3716 = rt_string_from_c("switch 重复 default");
xn_root_add(xn_t3716);
    xn_root_add(xn_t3716);
            xn_root_add(xn_t3716);
                    xn_root_add(xn_t3716);
                            xn_root_add(xn_t3716);
                            xn_Cls_Parser_err(self, xn_t3715, c->line, c->col, xn_t3716);
                                {
                                xn_root_restore(xn_t3714);
                                }

                        }
                    #line 1790 "impl/lib/b2/xparser.x"
                    sawDef = 1;
                    #line 1791 "impl/lib/b2/xparser.x"
                    rt_string *xn_t3717 = rt_string_from_c(":");
xn_root_add(xn_t3717);
    xn_root_add(xn_t3717);
            xn_root_add(xn_t3717);
                    xn_root_add(xn_t3717);
                        if ((xn_Cls_Parser_atOp(self, xn_t3717))) {
                            size_t xn_t3718 = xn_root_mark();
                            #line 1791 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                                {
                                xn_root_restore(xn_t3718);
                                }

                        }
                    #line 1792 "impl/lib/b2/xparser.x"
                    xn_arr_s *xn_t3719 = xn_arr_s_new(0);
xn_root_add(xn_t3719);
    xn_root_add(xn_t3719);
            xn_root_add(xn_t3719);
                    xn_root_add(xn_t3719);
                    xn_arr_s * ss = xn_t3719;
xn_root_add(ss);
    xn_root_add(ss);
            xn_root_add(ss);
                    xn_root_add(ss);
                    xn_root_add(ss);
                    xn_gc_safepoint();
                    #line 1793 "impl/lib/b2/xparser.x"
                        while (1) {
                            rt_string *xn_t3720 = rt_string_from_c("case");
xn_root_add(xn_t3720);
    xn_root_add(xn_t3720);
            xn_root_add(xn_t3720);
                    xn_root_add(xn_t3720);
                            rt_string *xn_t3721 = rt_string_from_c("default");
xn_root_add(xn_t3721);
    xn_root_add(xn_t3721);
            xn_root_add(xn_t3721);
                    xn_root_add(xn_t3721);
                            if (!((((((!(xn_Cls_Parser_atKw(self, xn_t3720)))) && ((!(xn_Cls_Parser_atKw(self, xn_t3721))))) && ((!(xn_Cls_Parser_at(self, 13))))) && ((!(xn_Cls_Parser_eof(self))))))) { break; }
                            size_t xn_t3722 = xn_root_mark();
                            #line 1794 "impl/lib/b2/xparser.x"
                                if ((xn_Cls_Parser_at(self, 1))) {
                                    size_t xn_t3723 = xn_root_mark();
                                    #line 1794 "impl/lib/b2/xparser.x"
                                    xn_Cls_Parser_next(self);
                                    #line 1794 "impl/lib/b2/xparser.x"
                                    xn_root_restore(xn_t3723);
                                    xn_root_restore(xn_t3722);
                                    continue;
                                        {
                                        xn_root_restore(xn_t3723);
                                        }

                                }
                            #line 1795 "impl/lib/b2/xparser.x"
                            rt_string *xn_t3724 = xn_Cls_Parser_parseStmt(self);
xn_root_add(xn_t3724);
    xn_root_add(xn_t3724);
            xn_root_add(xn_t3724);
                    xn_root_add(xn_t3724);
                            xn_root_add(xn_t3724);
                            xn_arr_s_push(ss, xn_t3724);
                                {
                                xn_root_restore(xn_t3722);
                                }

                            xn_gc_safepoint();
                        }
                    #line 1797 "impl/lib/b2/xparser.x"
                    rt_string *xn_t3725 = rt_string_from_c("(SwitchCase ");
xn_root_add(xn_t3725);
    xn_root_add(xn_t3725);
            xn_root_add(xn_t3725);
                    xn_root_add(xn_t3725);
                    rt_string *xn_t3726 = xn_P(c->line, c->col);
xn_root_add(xn_t3726);
    xn_root_add(xn_t3726);
            xn_root_add(xn_t3726);
                    xn_root_add(xn_t3726);
                    rt_string *xn_t3727 = xn_concat(xn_t3725, xn_t3726);
xn_root_add(xn_t3727);
    xn_root_add(xn_t3727);
            xn_root_add(xn_t3727);
                    xn_root_add(xn_t3727);
                    rt_string *xn_t3728 = rt_string_from_c(" (Expr (nil)) (Stmts ");
xn_root_add(xn_t3728);
    xn_root_add(xn_t3728);
            xn_root_add(xn_t3728);
                    xn_root_add(xn_t3728);
                    rt_string *xn_t3729 = xn_concat(xn_t3727, xn_t3728);
xn_root_add(xn_t3729);
    xn_root_add(xn_t3729);
            xn_root_add(xn_t3729);
                    xn_root_add(xn_t3729);
                    rt_string *xn_t3730 = xn_SL(ss);
xn_root_add(xn_t3730);
    xn_root_add(xn_t3730);
            xn_root_add(xn_t3730);
                    xn_root_add(xn_t3730);
                    rt_string *xn_t3731 = xn_concat(xn_t3729, xn_t3730);
xn_root_add(xn_t3731);
    xn_root_add(xn_t3731);
            xn_root_add(xn_t3731);
                    xn_root_add(xn_t3731);
                    rt_string *xn_t3732 = rt_string_from_c(") (Default true))");
xn_root_add(xn_t3732);
    xn_root_add(xn_t3732);
            xn_root_add(xn_t3732);
                    xn_root_add(xn_t3732);
                    rt_string *xn_t3733 = xn_concat(xn_t3731, xn_t3732);
xn_root_add(xn_t3733);
    xn_root_add(xn_t3733);
            xn_root_add(xn_t3733);
                    xn_root_add(xn_t3733);
                    xn_root_release(def);
                    rt_release(def);
                    def = xn_t3733;
                    xn_root_hold(def);
                    xn_gc_safepoint();
                        {
                        xn_root_restore(xn_t3713);
                        }

                } else {
                    size_t xn_t3734 = xn_root_mark();
                    #line 1798 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t3734);
                        }

                }
        }
        {
        xn_root_restore(xn_t3686);
        }

    xn_gc_safepoint();
    }
#line 1800 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 13))) {
        size_t xn_t3735 = xn_root_mark();
        #line 1800 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
            {
            xn_root_restore(xn_t3735);
            }

    }
#line 1801 "impl/lib/b2/xparser.x"
rt_string *xn_t3736 = rt_string_from_c("(SwitchStmt ");
xn_root_add(xn_t3736);
xn_root_add(xn_t3736);
rt_string *xn_t3737 = xn_P(t->line, t->col);
xn_root_add(xn_t3737);
xn_root_add(xn_t3737);
rt_string *xn_t3738 = xn_concat(xn_t3736, xn_t3737);
xn_root_add(xn_t3738);
xn_root_add(xn_t3738);
rt_string *xn_t3739 = rt_string_from_c(" (Value ");
xn_root_add(xn_t3739);
xn_root_add(xn_t3739);
rt_string *xn_t3740 = xn_concat(xn_t3738, xn_t3739);
xn_root_add(xn_t3740);
xn_root_add(xn_t3740);
rt_string *xn_t3741 = rt_retain(v->d);
xn_root_add(xn_t3741);
xn_root_add(xn_t3741);
rt_string *xn_t3742 = xn_concat(xn_t3740, xn_t3741);
xn_root_add(xn_t3742);
xn_root_add(xn_t3742);
rt_string *xn_t3743 = rt_string_from_c(") (Cases ");
xn_root_add(xn_t3743);
xn_root_add(xn_t3743);
rt_string *xn_t3744 = xn_concat(xn_t3742, xn_t3743);
xn_root_add(xn_t3744);
xn_root_add(xn_t3744);
rt_string *xn_t3745 = xn_SL(cs);
xn_root_add(xn_t3745);
xn_root_add(xn_t3745);
rt_string *xn_t3746 = xn_concat(xn_t3744, xn_t3745);
xn_root_add(xn_t3746);
xn_root_add(xn_t3746);
rt_string *xn_t3747 = rt_string_from_c(") (Default ");
xn_root_add(xn_t3747);
xn_root_add(xn_t3747);
rt_string *xn_t3748 = xn_concat(xn_t3746, xn_t3747);
xn_root_add(xn_t3748);
xn_root_add(xn_t3748);
rt_string *xn_t3749 = rt_retain(def);
xn_root_add(xn_t3749);
xn_root_add(xn_t3749);
rt_string *xn_t3750 = xn_concat(xn_t3748, xn_t3749);
xn_root_add(xn_t3750);
xn_root_add(xn_t3750);
rt_string *xn_t3751 = rt_string_from_c("))");
xn_root_add(xn_t3751);
xn_root_add(xn_t3751);
rt_string *xn_t3752 = xn_concat(xn_t3750, xn_t3751);
xn_root_add(xn_t3752);
xn_root_add(xn_t3752);
    {
rt_release(def);
    }
    {
xn_root_restore(xn_t3682);
    }

return xn_t3752;
xn_root_release(def);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseDefer(xn_Cls_Parser *self) {
size_t xn_t3753 = xn_root_mark();
xn_root_add(self);
#line 1805 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_next(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1806 "impl/lib/b2/xparser.x"
rt_string *xn_t3754 = rt_retain(t->text);
xn_root_add(xn_t3754);
rt_string *xn_t3755 = rt_string_from_c("errdefer");
xn_root_add(xn_t3755);
int er = xn_str_eq(xn_t3754, xn_t3755);
#line 1807 "impl/lib/b2/xparser.x"
rt_string *blk = rt_string_from_c("(nil)");
xn_root_add(blk);
xn_root_add(blk);
xn_gc_safepoint();
#line 1808 "impl/lib/b2/xparser.x"
rt_string *st = rt_string_from_c("(nil)");
xn_root_add(st);
xn_root_add(st);
xn_gc_safepoint();
#line 1809 "impl/lib/b2/xparser.x"
    if ((xn_Cls_Parser_at(self, 12))) {
        size_t xn_t3758 = xn_root_mark();
        #line 1809 "impl/lib/b2/xparser.x"
        rt_string *xn_t3759 = xn_Cls_Parser_parseBlock(self);
xn_root_add(xn_t3759);
        xn_root_add(xn_t3759);
        xn_root_release(blk);
        rt_release(blk);
        blk = xn_t3759;
        xn_root_hold(blk);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t3758);
            }

    } else {
        size_t xn_t3760 = xn_root_mark();
        #line 1810 "impl/lib/b2/xparser.x"
        rt_string *xn_t3761 = xn_Cls_Parser_parseStmt(self);
xn_root_add(xn_t3761);
        xn_root_add(xn_t3761);
        xn_root_release(st);
        rt_release(st);
        st = xn_t3761;
        xn_root_hold(st);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t3760);
            }

    }
#line 1811 "impl/lib/b2/xparser.x"
rt_string *xn_t3762 = rt_string_from_c("(DeferStmt ");
xn_root_add(xn_t3762);
xn_root_add(xn_t3762);
rt_string *xn_t3763 = xn_P(t->line, t->col);
xn_root_add(xn_t3763);
xn_root_add(xn_t3763);
rt_string *xn_t3764 = xn_concat(xn_t3762, xn_t3763);
xn_root_add(xn_t3764);
xn_root_add(xn_t3764);
rt_string *xn_t3765 = rt_string_from_c(" (Errdefer ");
xn_root_add(xn_t3765);
xn_root_add(xn_t3765);
rt_string *xn_t3766 = xn_concat(xn_t3764, xn_t3765);
xn_root_add(xn_t3766);
xn_root_add(xn_t3766);
rt_string *xn_t3767 = xn_B(er);
xn_root_add(xn_t3767);
xn_root_add(xn_t3767);
rt_string *xn_t3768 = xn_concat(xn_t3766, xn_t3767);
xn_root_add(xn_t3768);
xn_root_add(xn_t3768);
rt_string *xn_t3769 = rt_string_from_c(") (Block ");
xn_root_add(xn_t3769);
xn_root_add(xn_t3769);
rt_string *xn_t3770 = xn_concat(xn_t3768, xn_t3769);
xn_root_add(xn_t3770);
xn_root_add(xn_t3770);
rt_string *xn_t3771 = rt_retain(blk);
xn_root_add(xn_t3771);
xn_root_add(xn_t3771);
rt_string *xn_t3772 = xn_concat(xn_t3770, xn_t3771);
xn_root_add(xn_t3772);
xn_root_add(xn_t3772);
rt_string *xn_t3773 = rt_string_from_c(") (Stmt ");
xn_root_add(xn_t3773);
xn_root_add(xn_t3773);
rt_string *xn_t3774 = xn_concat(xn_t3772, xn_t3773);
xn_root_add(xn_t3774);
xn_root_add(xn_t3774);
rt_string *xn_t3775 = rt_retain(st);
xn_root_add(xn_t3775);
xn_root_add(xn_t3775);
rt_string *xn_t3776 = xn_concat(xn_t3774, xn_t3775);
xn_root_add(xn_t3776);
xn_root_add(xn_t3776);
rt_string *xn_t3777 = rt_string_from_c("))");
xn_root_add(xn_t3777);
xn_root_add(xn_t3777);
rt_string *xn_t3778 = xn_concat(xn_t3776, xn_t3777);
xn_root_add(xn_t3778);
xn_root_add(xn_t3778);
    {
rt_release(st);
    }
    {
rt_release(blk);
    }
    {
xn_root_restore(xn_t3753);
    }

return xn_t3778;
xn_root_release(blk);
xn_root_release(st);
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_E * xn_Cls_Parser_mk(xn_Cls_Parser *self, rt_string * xn_p_d, int64_t xn_p_l, int64_t xn_p_c) {
size_t xn_t3779 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_d);
#line 1814 "impl/lib/b2/xparser.x"
xn_Cls_E * e = xn_Cls_E_new();
xn_root_add(e);
xn_root_add(e);
xn_gc_safepoint();
#line 1814 "impl/lib/b2/xparser.x"
rt_string *xn_t3780 = rt_retain(xn_p_d);
xn_root_add(xn_t3780);
rt_release(e->d);
e->d = xn_t3780;
#line 1814 "impl/lib/b2/xparser.x"
e->l = xn_p_l;
#line 1814 "impl/lib/b2/xparser.x"
e->c = xn_p_c;
#line 1814 "impl/lib/b2/xparser.x"
e->sl = xn_p_l;
#line 1814 "impl/lib/b2/xparser.x"
e->sc = xn_p_c;
#line 1814 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t3779);
    }

return e;
    return (xn_Cls_E *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_E * xn_Cls_Parser_parseExpr(xn_Cls_Parser *self) {
size_t xn_t3781 = xn_root_mark();
xn_root_add(self);
#line 1816 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t3781);
    }

return xn_Cls_Parser_parseTernary(self);
    return (xn_Cls_E *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_E * xn_Cls_Parser_parseTernary(xn_Cls_Parser *self) {
size_t xn_t3782 = xn_root_mark();
xn_root_add(self);
#line 1819 "impl/lib/b2/xparser.x"
xn_Cls_E * c = xn_Cls_Parser_parseCoalesce(self);
xn_root_add(c);
xn_root_add(c);
xn_gc_safepoint();
#line 1820 "impl/lib/b2/xparser.x"
rt_string *xn_t3783 = rt_string_from_c("?");
xn_root_add(xn_t3783);
    if ((xn_Cls_Parser_atOp(self, xn_t3783))) {
        size_t xn_t3784 = xn_root_mark();
        #line 1821 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * t = xn_Cls_Parser_next(self);
xn_root_add(t);
        xn_root_add(t);
        xn_root_add(t);
        xn_gc_safepoint();
        #line 1822 "impl/lib/b2/xparser.x"
        xn_Cls_E * a = xn_Cls_Parser_parseExpr(self);
xn_root_add(a);
        xn_root_add(a);
        xn_root_add(a);
        xn_gc_safepoint();
        #line 1823 "impl/lib/b2/xparser.x"
        rt_string *xn_t3785 = rt_string_from_c(":");
xn_root_add(xn_t3785);
        xn_root_add(xn_t3785);
            if ((xn_Cls_Parser_atOp(self, xn_t3785))) {
                size_t xn_t3786 = xn_root_mark();
                #line 1823 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t3786);
                    }

            }
        #line 1824 "impl/lib/b2/xparser.x"
        xn_Cls_E * b = xn_Cls_Parser_parseTernary(self);
xn_root_add(b);
        xn_root_add(b);
        xn_root_add(b);
        xn_gc_safepoint();
        #line 1825 "impl/lib/b2/xparser.x"
        rt_string *xn_t3787 = rt_string_from_c("(Ternary ");
xn_root_add(xn_t3787);
        xn_root_add(xn_t3787);
        rt_string *xn_t3788 = xn_P(t->line, t->col);
xn_root_add(xn_t3788);
        xn_root_add(xn_t3788);
        rt_string *xn_t3789 = xn_concat(xn_t3787, xn_t3788);
xn_root_add(xn_t3789);
        xn_root_add(xn_t3789);
        rt_string *xn_t3790 = rt_string_from_c(" (Cond ");
xn_root_add(xn_t3790);
        xn_root_add(xn_t3790);
        rt_string *xn_t3791 = xn_concat(xn_t3789, xn_t3790);
xn_root_add(xn_t3791);
        xn_root_add(xn_t3791);
        rt_string *xn_t3792 = rt_retain(c->d);
xn_root_add(xn_t3792);
        xn_root_add(xn_t3792);
        rt_string *xn_t3793 = xn_concat(xn_t3791, xn_t3792);
xn_root_add(xn_t3793);
        xn_root_add(xn_t3793);
        rt_string *xn_t3794 = rt_string_from_c(") (Then ");
xn_root_add(xn_t3794);
        xn_root_add(xn_t3794);
        rt_string *xn_t3795 = xn_concat(xn_t3793, xn_t3794);
xn_root_add(xn_t3795);
        xn_root_add(xn_t3795);
        rt_string *xn_t3796 = rt_retain(a->d);
xn_root_add(xn_t3796);
        xn_root_add(xn_t3796);
        rt_string *xn_t3797 = xn_concat(xn_t3795, xn_t3796);
xn_root_add(xn_t3797);
        xn_root_add(xn_t3797);
        rt_string *xn_t3798 = rt_string_from_c(") (Else ");
xn_root_add(xn_t3798);
        xn_root_add(xn_t3798);
        rt_string *xn_t3799 = xn_concat(xn_t3797, xn_t3798);
xn_root_add(xn_t3799);
        xn_root_add(xn_t3799);
        rt_string *xn_t3800 = rt_retain(b->d);
xn_root_add(xn_t3800);
        xn_root_add(xn_t3800);
        rt_string *xn_t3801 = xn_concat(xn_t3799, xn_t3800);
xn_root_add(xn_t3801);
        xn_root_add(xn_t3801);
        rt_string *xn_t3802 = rt_string_from_c("))");
xn_root_add(xn_t3802);
        xn_root_add(xn_t3802);
        rt_string *xn_t3803 = xn_concat(xn_t3801, xn_t3802);
xn_root_add(xn_t3803);
        xn_root_add(xn_t3803);
        xn_Cls_E * te = xn_Cls_Parser_mk(self, xn_t3803, t->line, t->col);
xn_root_add(te);
        xn_root_add(te);
        xn_root_add(te);
        xn_gc_safepoint();
        #line 1826 "impl/lib/b2/xparser.x"
        te->sl = c->sl;
        #line 1827 "impl/lib/b2/xparser.x"
        te->sc = c->sc;
        #line 1828 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t3784);
            }
            {
        xn_root_restore(xn_t3782);
            }

        return te;

    }
#line 1830 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t3782);
    }

return c;
    return (xn_Cls_E *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_E * xn_Cls_Parser_parseCoalesce(xn_Cls_Parser *self) {
size_t xn_t3804 = xn_root_mark();
xn_root_add(self);
#line 1834 "impl/lib/b2/xparser.x"
xn_Cls_E * l = xn_Cls_Parser_parseBin(self, 1);
xn_root_add(l);
xn_root_add(l);
xn_gc_safepoint();
#line 1835 "impl/lib/b2/xparser.x"
rt_string *xn_t3805 = rt_string_from_c("??");
xn_root_add(xn_t3805);
    if ((xn_Cls_Parser_atOp(self, xn_t3805))) {
        size_t xn_t3806 = xn_root_mark();
        #line 1836 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * op = xn_Cls_Parser_next(self);
xn_root_add(op);
        xn_root_add(op);
        xn_root_add(op);
        xn_gc_safepoint();
        #line 1837 "impl/lib/b2/xparser.x"
        xn_Cls_E * r = xn_Cls_Parser_parseCoalesce(self);
xn_root_add(r);
        xn_root_add(r);
        xn_root_add(r);
        xn_gc_safepoint();
        #line 1838 "impl/lib/b2/xparser.x"
        rt_string *xn_t3807 = rt_string_from_c("(Binary ");
xn_root_add(xn_t3807);
        xn_root_add(xn_t3807);
        rt_string *xn_t3808 = xn_P(op->line, op->col);
xn_root_add(xn_t3808);
        xn_root_add(xn_t3808);
        rt_string *xn_t3809 = xn_concat(xn_t3807, xn_t3808);
xn_root_add(xn_t3809);
        xn_root_add(xn_t3809);
        rt_string *xn_t3810 = rt_string_from_c(" (Op \"??\") (L ");
xn_root_add(xn_t3810);
        xn_root_add(xn_t3810);
        rt_string *xn_t3811 = xn_concat(xn_t3809, xn_t3810);
xn_root_add(xn_t3811);
        xn_root_add(xn_t3811);
        rt_string *xn_t3812 = rt_retain(l->d);
xn_root_add(xn_t3812);
        xn_root_add(xn_t3812);
        rt_string *xn_t3813 = xn_concat(xn_t3811, xn_t3812);
xn_root_add(xn_t3813);
        xn_root_add(xn_t3813);
        rt_string *xn_t3814 = rt_string_from_c(") (R ");
xn_root_add(xn_t3814);
        xn_root_add(xn_t3814);
        rt_string *xn_t3815 = xn_concat(xn_t3813, xn_t3814);
xn_root_add(xn_t3815);
        xn_root_add(xn_t3815);
        rt_string *xn_t3816 = rt_retain(r->d);
xn_root_add(xn_t3816);
        xn_root_add(xn_t3816);
        rt_string *xn_t3817 = xn_concat(xn_t3815, xn_t3816);
xn_root_add(xn_t3817);
        xn_root_add(xn_t3817);
        rt_string *xn_t3818 = rt_string_from_c("))");
xn_root_add(xn_t3818);
        xn_root_add(xn_t3818);
        rt_string *xn_t3819 = xn_concat(xn_t3817, xn_t3818);
xn_root_add(xn_t3819);
        xn_root_add(xn_t3819);
        xn_Cls_E * be = xn_Cls_Parser_mk(self, xn_t3819, op->line, op->col);
xn_root_add(be);
        xn_root_add(be);
        xn_root_add(be);
        xn_gc_safepoint();
        #line 1839 "impl/lib/b2/xparser.x"
        be->sl = l->sl;
        #line 1840 "impl/lib/b2/xparser.x"
        be->sc = l->sc;
        #line 1841 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t3806);
            }
            {
        xn_root_restore(xn_t3804);
            }

        return be;

    }
#line 1843 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t3804);
    }

return l;
    return (xn_Cls_E *)0; /* sema 保证不可达（函数体全路径 return） */
}

static int64_t xn_Cls_Parser_prec(xn_Cls_Parser *self, rt_string * xn_p_op) {
size_t xn_t3820 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_op);
#line 1847 "impl/lib/b2/xparser.x"
rt_string *xn_t3821 = rt_retain(xn_p_op);
xn_root_add(xn_t3821);
rt_string *xn_t3822 = rt_string_from_c("||");
xn_root_add(xn_t3822);
    if ((xn_str_eq(xn_t3821, xn_t3822))) {
        size_t xn_t3823 = xn_root_mark();
        #line 1847 "impl/lib/b2/xparser.x"
        int64_t xn_t3824 = 1;
            {
        xn_root_restore(xn_t3823);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3824;

    }
#line 1848 "impl/lib/b2/xparser.x"
rt_string *xn_t3825 = rt_retain(xn_p_op);
xn_root_add(xn_t3825);
rt_string *xn_t3826 = rt_string_from_c("&&");
xn_root_add(xn_t3826);
    if ((xn_str_eq(xn_t3825, xn_t3826))) {
        size_t xn_t3827 = xn_root_mark();
        #line 1848 "impl/lib/b2/xparser.x"
        int64_t xn_t3828 = 2;
            {
        xn_root_restore(xn_t3827);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3828;

    }
#line 1849 "impl/lib/b2/xparser.x"
rt_string *xn_t3829 = rt_retain(xn_p_op);
xn_root_add(xn_t3829);
rt_string *xn_t3830 = rt_string_from_c("|");
xn_root_add(xn_t3830);
    if ((xn_str_eq(xn_t3829, xn_t3830))) {
        size_t xn_t3831 = xn_root_mark();
        #line 1849 "impl/lib/b2/xparser.x"
        int64_t xn_t3832 = 3;
            {
        xn_root_restore(xn_t3831);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3832;

    }
#line 1850 "impl/lib/b2/xparser.x"
rt_string *xn_t3833 = rt_retain(xn_p_op);
xn_root_add(xn_t3833);
rt_string *xn_t3834 = rt_string_from_c("^");
xn_root_add(xn_t3834);
    if ((xn_str_eq(xn_t3833, xn_t3834))) {
        size_t xn_t3835 = xn_root_mark();
        #line 1850 "impl/lib/b2/xparser.x"
        int64_t xn_t3836 = 4;
            {
        xn_root_restore(xn_t3835);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3836;

    }
#line 1851 "impl/lib/b2/xparser.x"
rt_string *xn_t3837 = rt_retain(xn_p_op);
xn_root_add(xn_t3837);
rt_string *xn_t3838 = rt_string_from_c("&");
xn_root_add(xn_t3838);
    if ((xn_str_eq(xn_t3837, xn_t3838))) {
        size_t xn_t3839 = xn_root_mark();
        #line 1851 "impl/lib/b2/xparser.x"
        int64_t xn_t3840 = 5;
            {
        xn_root_restore(xn_t3839);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3840;

    }
#line 1852 "impl/lib/b2/xparser.x"
rt_string *xn_t3841 = rt_retain(xn_p_op);
xn_root_add(xn_t3841);
rt_string *xn_t3842 = rt_string_from_c("==");
xn_root_add(xn_t3842);
rt_string *xn_t3843 = rt_retain(xn_p_op);
xn_root_add(xn_t3843);
rt_string *xn_t3844 = rt_string_from_c("!=");
xn_root_add(xn_t3844);
rt_string *xn_t3845 = rt_retain(xn_p_op);
xn_root_add(xn_t3845);
rt_string *xn_t3846 = rt_string_from_c("===");
xn_root_add(xn_t3846);
rt_string *xn_t3847 = rt_retain(xn_p_op);
xn_root_add(xn_t3847);
rt_string *xn_t3848 = rt_string_from_c("!==");
xn_root_add(xn_t3848);
    if (((((xn_str_eq(xn_t3841, xn_t3842)) || (xn_str_eq(xn_t3843, xn_t3844))) || (xn_str_eq(xn_t3845, xn_t3846))) || (xn_str_eq(xn_t3847, xn_t3848)))) {
        size_t xn_t3849 = xn_root_mark();
        #line 1852 "impl/lib/b2/xparser.x"
        int64_t xn_t3850 = 6;
            {
        xn_root_restore(xn_t3849);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3850;

    }
#line 1853 "impl/lib/b2/xparser.x"
rt_string *xn_t3851 = rt_retain(xn_p_op);
xn_root_add(xn_t3851);
rt_string *xn_t3852 = rt_string_from_c("<");
xn_root_add(xn_t3852);
rt_string *xn_t3853 = rt_retain(xn_p_op);
xn_root_add(xn_t3853);
rt_string *xn_t3854 = rt_string_from_c(">");
xn_root_add(xn_t3854);
rt_string *xn_t3855 = rt_retain(xn_p_op);
xn_root_add(xn_t3855);
rt_string *xn_t3856 = rt_string_from_c("<=");
xn_root_add(xn_t3856);
rt_string *xn_t3857 = rt_retain(xn_p_op);
xn_root_add(xn_t3857);
rt_string *xn_t3858 = rt_string_from_c(">=");
xn_root_add(xn_t3858);
rt_string *xn_t3859 = rt_retain(xn_p_op);
xn_root_add(xn_t3859);
rt_string *xn_t3860 = rt_string_from_c("is");
xn_root_add(xn_t3860);
rt_string *xn_t3861 = rt_retain(xn_p_op);
xn_root_add(xn_t3861);
rt_string *xn_t3862 = rt_string_from_c("as");
xn_root_add(xn_t3862);
rt_string *xn_t3863 = rt_retain(xn_p_op);
xn_root_add(xn_t3863);
rt_string *xn_t3864 = rt_string_from_c("as?");
xn_root_add(xn_t3864);
    if ((((((((xn_str_eq(xn_t3851, xn_t3852)) || (xn_str_eq(xn_t3853, xn_t3854))) || (xn_str_eq(xn_t3855, xn_t3856))) || (xn_str_eq(xn_t3857, xn_t3858))) || (xn_str_eq(xn_t3859, xn_t3860))) || (xn_str_eq(xn_t3861, xn_t3862))) || (xn_str_eq(xn_t3863, xn_t3864)))) {
        size_t xn_t3865 = xn_root_mark();
        #line 1853 "impl/lib/b2/xparser.x"
        int64_t xn_t3866 = 7;
            {
        xn_root_restore(xn_t3865);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3866;

    }
#line 1854 "impl/lib/b2/xparser.x"
rt_string *xn_t3867 = rt_retain(xn_p_op);
xn_root_add(xn_t3867);
rt_string *xn_t3868 = rt_string_from_c("..<");
xn_root_add(xn_t3868);
rt_string *xn_t3869 = rt_retain(xn_p_op);
xn_root_add(xn_t3869);
rt_string *xn_t3870 = rt_string_from_c("...");
xn_root_add(xn_t3870);
    if (((xn_str_eq(xn_t3867, xn_t3868)) || (xn_str_eq(xn_t3869, xn_t3870)))) {
        size_t xn_t3871 = xn_root_mark();
        #line 1854 "impl/lib/b2/xparser.x"
        int64_t xn_t3872 = 8;
            {
        xn_root_restore(xn_t3871);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3872;

    }
#line 1855 "impl/lib/b2/xparser.x"
rt_string *xn_t3873 = rt_retain(xn_p_op);
xn_root_add(xn_t3873);
rt_string *xn_t3874 = rt_string_from_c("<<");
xn_root_add(xn_t3874);
rt_string *xn_t3875 = rt_retain(xn_p_op);
xn_root_add(xn_t3875);
rt_string *xn_t3876 = rt_string_from_c(">>");
xn_root_add(xn_t3876);
    if (((xn_str_eq(xn_t3873, xn_t3874)) || (xn_str_eq(xn_t3875, xn_t3876)))) {
        size_t xn_t3877 = xn_root_mark();
        #line 1855 "impl/lib/b2/xparser.x"
        int64_t xn_t3878 = 9;
            {
        xn_root_restore(xn_t3877);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3878;

    }
#line 1856 "impl/lib/b2/xparser.x"
rt_string *xn_t3879 = rt_retain(xn_p_op);
xn_root_add(xn_t3879);
rt_string *xn_t3880 = rt_string_from_c("+");
xn_root_add(xn_t3880);
rt_string *xn_t3881 = rt_retain(xn_p_op);
xn_root_add(xn_t3881);
rt_string *xn_t3882 = rt_string_from_c("-");
xn_root_add(xn_t3882);
    if (((xn_str_eq(xn_t3879, xn_t3880)) || (xn_str_eq(xn_t3881, xn_t3882)))) {
        size_t xn_t3883 = xn_root_mark();
        #line 1856 "impl/lib/b2/xparser.x"
        int64_t xn_t3884 = 10;
            {
        xn_root_restore(xn_t3883);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3884;

    }
#line 1857 "impl/lib/b2/xparser.x"
rt_string *xn_t3885 = rt_retain(xn_p_op);
xn_root_add(xn_t3885);
rt_string *xn_t3886 = rt_string_from_c("*");
xn_root_add(xn_t3886);
rt_string *xn_t3887 = rt_retain(xn_p_op);
xn_root_add(xn_t3887);
rt_string *xn_t3888 = rt_string_from_c("/");
xn_root_add(xn_t3888);
rt_string *xn_t3889 = rt_retain(xn_p_op);
xn_root_add(xn_t3889);
rt_string *xn_t3890 = rt_string_from_c("%");
xn_root_add(xn_t3890);
    if ((((xn_str_eq(xn_t3885, xn_t3886)) || (xn_str_eq(xn_t3887, xn_t3888))) || (xn_str_eq(xn_t3889, xn_t3890)))) {
        size_t xn_t3891 = xn_root_mark();
        #line 1857 "impl/lib/b2/xparser.x"
        int64_t xn_t3892 = 11;
            {
        xn_root_restore(xn_t3891);
            }
            {
        xn_root_restore(xn_t3820);
            }

        return xn_t3892;

    }
#line 1858 "impl/lib/b2/xparser.x"
int64_t xn_t3893 = 0;
    {
xn_root_restore(xn_t3820);
    }

return xn_t3893;
    return (int64_t)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_E * xn_Cls_Parser_parseBin(xn_Cls_Parser *self, int64_t xn_p_lvl) {
size_t xn_t3894 = xn_root_mark();
xn_root_add(self);
#line 1862 "impl/lib/b2/xparser.x"
    if (((xn_p_lvl > 11))) {
        size_t xn_t3895 = xn_root_mark();
        #line 1862 "impl/lib/b2/xparser.x"
            {
        xn_root_restore(xn_t3895);
            }
            {
        xn_root_restore(xn_t3894);
            }

        return xn_Cls_Parser_parseUnary(self);

    }
#line 1865 "impl/lib/b2/xparser.x"
xn_arr_o_E *xn_t3896 = xn_arr_o_E_new(0);
xn_root_add(xn_t3896);
xn_arr_o_E * lh = xn_t3896;
xn_root_add(lh);
xn_root_add(lh);
xn_gc_safepoint();
#line 1866 "impl/lib/b2/xparser.x"
xn_Cls_E * xn_t3897 = xn_Cls_Parser_parseBin(self, (xn_p_lvl + 1));
xn_root_add(xn_t3897);
xn_root_add(xn_t3897);
xn_arr_o_E_push(lh, xn_t3897);
#line 1867 "impl/lib/b2/xparser.x"
    while (1) {
        xn_Cls_Tok * xn_t3898 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3898);
        xn_Cls_Tok * xn_t3899 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3899);
        xn_Cls_Tok * xn_t3900 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t3900);
        rt_string *xn_t3901 = rt_retain(xn_t3900->text);
xn_root_add(xn_t3901);
        if (!(((((xn_t3898->kind == 9) || (xn_t3899->kind == 3))) && ((xn_Cls_Parser_prec(self, xn_t3901) == xn_p_lvl))))) { break; }
        size_t xn_t3902 = xn_root_mark();
        #line 1868 "impl/lib/b2/xparser.x"
        xn_Cls_E * l = xn_arr_o_E_get(lh, 0);
xn_root_add(l);
        xn_root_add(l);
        xn_root_add(l);
        xn_gc_safepoint();
        #line 1869 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * op = xn_Cls_Parser_next(self);
xn_root_add(op);
        xn_root_add(op);
        xn_root_add(op);
        xn_gc_safepoint();
        #line 1870 "impl/lib/b2/xparser.x"
        rt_string *xn_t3903 = rt_retain(op->text);
xn_root_add(xn_t3903);
        xn_root_add(xn_t3903);
        rt_string *xn_t3904 = rt_string_from_c("<");
xn_root_add(xn_t3904);
        xn_root_add(xn_t3904);
        rt_string *xn_t3905 = rt_retain(op->text);
xn_root_add(xn_t3905);
        xn_root_add(xn_t3905);
        rt_string *xn_t3906 = rt_string_from_c(">");
xn_root_add(xn_t3906);
        xn_root_add(xn_t3906);
        rt_string *xn_t3907 = rt_retain(op->text);
xn_root_add(xn_t3907);
        xn_root_add(xn_t3907);
        rt_string *xn_t3908 = rt_string_from_c("<=");
xn_root_add(xn_t3908);
        xn_root_add(xn_t3908);
        rt_string *xn_t3909 = rt_retain(op->text);
xn_root_add(xn_t3909);
        xn_root_add(xn_t3909);
        rt_string *xn_t3910 = rt_string_from_c(">=");
xn_root_add(xn_t3910);
        xn_root_add(xn_t3910);
        rt_string *xn_t3911 = rt_retain(l->d);
xn_root_add(xn_t3911);
        xn_root_add(xn_t3911);
        rt_string *xn_t3912 = rt_string_from_c("(Binary ");
xn_root_add(xn_t3912);
        xn_root_add(xn_t3912);
        rt_string *xn_t3913 = rt_retain(l->d);
xn_root_add(xn_t3913);
        xn_root_add(xn_t3913);
        rt_string *xn_t3914 = rt_string_from_c("(Op \"");
xn_root_add(xn_t3914);
        xn_root_add(xn_t3914);
            if (((((((xn_str_eq(xn_t3903, xn_t3904) || xn_str_eq(xn_t3905, xn_t3906)) || xn_str_eq(xn_t3907, xn_t3908)) || xn_str_eq(xn_t3909, xn_t3910))) && ((xn_str_indexof(xn_t3911, xn_t3912) == 0))) && ((xn_str_indexof(xn_t3913, xn_t3914) > 0)))) {
                size_t xn_t3915 = xn_root_mark();
                #line 1871 "impl/lib/b2/xparser.x"
                rt_string *xn_t3916 = rt_string_from_c("SYN-102");
xn_root_add(xn_t3916);
        xn_root_add(xn_t3916);
                xn_root_add(xn_t3916);
                rt_string *xn_t3917 = rt_string_from_c("比较运算不可链式使用");
xn_root_add(xn_t3917);
        xn_root_add(xn_t3917);
                xn_root_add(xn_t3917);
                xn_Cls_Parser_err(self, xn_t3916, op->line, op->col, xn_t3917);
                #line 1872 "impl/lib/b2/xparser.x"
                rt_string *xn_t3918 = rt_string_from_c("SYN-108");
xn_root_add(xn_t3918);
        xn_root_add(xn_t3918);
                xn_root_add(xn_t3918);
                rt_string *xn_t3919 = rt_string_from_c("语句未终止（同一行的下一条语句前缺少 `;`）");
xn_root_add(xn_t3919);
        xn_root_add(xn_t3919);
                xn_root_add(xn_t3919);
                xn_Cls_Parser_err(self, xn_t3918, op->line, op->col, xn_t3919);
                    {
                    xn_root_restore(xn_t3915);
                    }

            }
        #line 1874 "impl/lib/b2/xparser.x"
        rt_string *xn_t3920 = rt_string_from_c("(nil)");
xn_root_add(xn_t3920);
        xn_root_add(xn_t3920);
        xn_Cls_E * r = xn_Cls_Parser_mk(self, xn_t3920, 0, 0);
xn_root_add(r);
        xn_root_add(r);
        xn_root_add(r);
        xn_gc_safepoint();
        #line 1875 "impl/lib/b2/xparser.x"
        rt_string *xn_t3921 = rt_retain(op->text);
xn_root_add(xn_t3921);
        xn_root_add(xn_t3921);
        rt_string *xn_t3922 = rt_string_from_c("as");
xn_root_add(xn_t3922);
        xn_root_add(xn_t3922);
        rt_string *xn_t3923 = rt_string_from_c("?");
xn_root_add(xn_t3923);
        xn_root_add(xn_t3923);
            if (((xn_str_eq(xn_t3921, xn_t3922)) && (xn_Cls_Parser_atOp(self, xn_t3923)))) {
                size_t xn_t3924 = xn_root_mark();
                #line 1875 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                #line 1875 "impl/lib/b2/xparser.x"
                rt_string *xn_t3925 = rt_string_from_c("as?");
xn_root_add(xn_t3925);
        xn_root_add(xn_t3925);
                xn_root_add(xn_t3925);
                rt_release(op->text);
                op->text = xn_t3925;
                    {
                    xn_root_restore(xn_t3924);
                    }

            }
        #line 1876 "impl/lib/b2/xparser.x"
        rt_string *xn_t3926 = rt_retain(op->text);
xn_root_add(xn_t3926);
        xn_root_add(xn_t3926);
        rt_string *xn_t3927 = rt_string_from_c("is");
xn_root_add(xn_t3927);
        xn_root_add(xn_t3927);
        rt_string *xn_t3928 = rt_retain(op->text);
xn_root_add(xn_t3928);
        xn_root_add(xn_t3928);
        rt_string *xn_t3929 = rt_string_from_c("as");
xn_root_add(xn_t3929);
        xn_root_add(xn_t3929);
        rt_string *xn_t3930 = rt_retain(op->text);
xn_root_add(xn_t3930);
        xn_root_add(xn_t3930);
        rt_string *xn_t3931 = rt_string_from_c("as?");
xn_root_add(xn_t3931);
        xn_root_add(xn_t3931);
            if ((((xn_str_eq(xn_t3926, xn_t3927)) || (xn_str_eq(xn_t3928, xn_t3929))) || (xn_str_eq(xn_t3930, xn_t3931)))) {
                size_t xn_t3932 = xn_root_mark();
                #line 1877 "impl/lib/b2/xparser.x"
                rt_string *ty = xn_Cls_Parser_parseType(self);
xn_root_add(ty);
        xn_root_add(ty);
                xn_root_add(ty);
                xn_root_add(ty);
                xn_gc_safepoint();
                #line 1878 "impl/lib/b2/xparser.x"
                rt_string *xn_t3934 = rt_string_from_c("(TypeAsExpr ");
xn_root_add(xn_t3934);
        xn_root_add(xn_t3934);
                xn_root_add(xn_t3934);
                rt_string *xn_t3935 = xn_P(0, 0);
xn_root_add(xn_t3935);
        xn_root_add(xn_t3935);
                xn_root_add(xn_t3935);
                rt_string *xn_t3936 = xn_concat(xn_t3934, xn_t3935);
xn_root_add(xn_t3936);
        xn_root_add(xn_t3936);
                xn_root_add(xn_t3936);
                rt_string *xn_t3937 = rt_string_from_c(" (Type ");
xn_root_add(xn_t3937);
        xn_root_add(xn_t3937);
                xn_root_add(xn_t3937);
                rt_string *xn_t3938 = xn_concat(xn_t3936, xn_t3937);
xn_root_add(xn_t3938);
        xn_root_add(xn_t3938);
                xn_root_add(xn_t3938);
                rt_string *xn_t3939 = rt_retain(ty);
xn_root_add(xn_t3939);
        xn_root_add(xn_t3939);
                xn_root_add(xn_t3939);
                rt_string *xn_t3940 = xn_concat(xn_t3938, xn_t3939);
xn_root_add(xn_t3940);
        xn_root_add(xn_t3940);
                xn_root_add(xn_t3940);
                rt_string *xn_t3941 = rt_string_from_c(") (Is ");
xn_root_add(xn_t3941);
        xn_root_add(xn_t3941);
                xn_root_add(xn_t3941);
                rt_string *xn_t3942 = xn_concat(xn_t3940, xn_t3941);
xn_root_add(xn_t3942);
        xn_root_add(xn_t3942);
                xn_root_add(xn_t3942);
                rt_string *xn_t3943 = rt_retain(op->text);
xn_root_add(xn_t3943);
        xn_root_add(xn_t3943);
                xn_root_add(xn_t3943);
                rt_string *xn_t3944 = rt_string_from_c("is");
xn_root_add(xn_t3944);
        xn_root_add(xn_t3944);
                xn_root_add(xn_t3944);
                rt_string *xn_t3945 = xn_B(xn_str_eq(xn_t3943, xn_t3944));
xn_root_add(xn_t3945);
        xn_root_add(xn_t3945);
                xn_root_add(xn_t3945);
                rt_string *xn_t3946 = xn_concat(xn_t3942, xn_t3945);
xn_root_add(xn_t3946);
        xn_root_add(xn_t3946);
                xn_root_add(xn_t3946);
                rt_string *xn_t3947 = rt_string_from_c(") (NullSafe ");
xn_root_add(xn_t3947);
        xn_root_add(xn_t3947);
                xn_root_add(xn_t3947);
                rt_string *xn_t3948 = xn_concat(xn_t3946, xn_t3947);
xn_root_add(xn_t3948);
        xn_root_add(xn_t3948);
                xn_root_add(xn_t3948);
                rt_string *xn_t3949 = rt_retain(op->text);
xn_root_add(xn_t3949);
        xn_root_add(xn_t3949);
                xn_root_add(xn_t3949);
                rt_string *xn_t3950 = rt_string_from_c("as?");
xn_root_add(xn_t3950);
        xn_root_add(xn_t3950);
                xn_root_add(xn_t3950);
                rt_string *xn_t3951 = xn_B(xn_str_eq(xn_t3949, xn_t3950));
xn_root_add(xn_t3951);
        xn_root_add(xn_t3951);
                xn_root_add(xn_t3951);
                rt_string *xn_t3952 = xn_concat(xn_t3948, xn_t3951);
xn_root_add(xn_t3952);
        xn_root_add(xn_t3952);
                xn_root_add(xn_t3952);
                rt_string *xn_t3953 = rt_string_from_c("))");
xn_root_add(xn_t3953);
        xn_root_add(xn_t3953);
                xn_root_add(xn_t3953);
                rt_string *ta = xn_concat(xn_t3952, xn_t3953);
xn_root_add(ta);
        xn_root_add(ta);
                xn_root_add(ta);
                xn_root_add(ta);
                xn_gc_safepoint();
                #line 1879 "impl/lib/b2/xparser.x"
                rt_string *xn_t3955 = rt_retain(ta);
xn_root_add(xn_t3955);
        xn_root_add(xn_t3955);
                xn_root_add(xn_t3955);
                r = xn_Cls_Parser_mk(self, xn_t3955, 0, 0);
                    {
                    rt_release(ta);
                    }
                    {
                    rt_release(ty);
                    }
                    {
                    xn_root_restore(xn_t3932);
                    }

            } else {
                size_t xn_t3956 = xn_root_mark();
                #line 1881 "impl/lib/b2/xparser.x"
                r = xn_Cls_Parser_parseBin(self, (xn_p_lvl + 1));
                    {
                    xn_root_restore(xn_t3956);
                    }

            }
        #line 1883 "impl/lib/b2/xparser.x"
        rt_string *xn_t3957 = rt_string_from_c("(Binary ");
xn_root_add(xn_t3957);
        xn_root_add(xn_t3957);
        rt_string *xn_t3958 = xn_P(op->line, op->col);
xn_root_add(xn_t3958);
        xn_root_add(xn_t3958);
        rt_string *xn_t3959 = xn_concat(xn_t3957, xn_t3958);
xn_root_add(xn_t3959);
        xn_root_add(xn_t3959);
        rt_string *xn_t3960 = rt_string_from_c(" (Op ");
xn_root_add(xn_t3960);
        xn_root_add(xn_t3960);
        rt_string *xn_t3961 = xn_concat(xn_t3959, xn_t3960);
xn_root_add(xn_t3961);
        xn_root_add(xn_t3961);
        rt_string *xn_t3962 = rt_retain(op->text);
xn_root_add(xn_t3962);
        xn_root_add(xn_t3962);
        rt_string *xn_t3963 = xn_q(xn_t3962);
xn_root_add(xn_t3963);
        xn_root_add(xn_t3963);
        rt_string *xn_t3964 = xn_concat(xn_t3961, xn_t3963);
xn_root_add(xn_t3964);
        xn_root_add(xn_t3964);
        rt_string *xn_t3965 = rt_string_from_c(") (L ");
xn_root_add(xn_t3965);
        xn_root_add(xn_t3965);
        rt_string *xn_t3966 = xn_concat(xn_t3964, xn_t3965);
xn_root_add(xn_t3966);
        xn_root_add(xn_t3966);
        rt_string *xn_t3967 = rt_retain(l->d);
xn_root_add(xn_t3967);
        xn_root_add(xn_t3967);
        rt_string *xn_t3968 = xn_concat(xn_t3966, xn_t3967);
xn_root_add(xn_t3968);
        xn_root_add(xn_t3968);
        rt_string *xn_t3969 = rt_string_from_c(") (R ");
xn_root_add(xn_t3969);
        xn_root_add(xn_t3969);
        rt_string *xn_t3970 = xn_concat(xn_t3968, xn_t3969);
xn_root_add(xn_t3970);
        xn_root_add(xn_t3970);
        rt_string *xn_t3971 = rt_retain(r->d);
xn_root_add(xn_t3971);
        xn_root_add(xn_t3971);
        rt_string *xn_t3972 = xn_concat(xn_t3970, xn_t3971);
xn_root_add(xn_t3972);
        xn_root_add(xn_t3972);
        rt_string *xn_t3973 = rt_string_from_c("))");
xn_root_add(xn_t3973);
        xn_root_add(xn_t3973);
        rt_string *xn_t3974 = xn_concat(xn_t3972, xn_t3973);
xn_root_add(xn_t3974);
        xn_root_add(xn_t3974);
        xn_Cls_E * be = xn_Cls_Parser_mk(self, xn_t3974, op->line, op->col);
xn_root_add(be);
        xn_root_add(be);
        xn_root_add(be);
        xn_gc_safepoint();
        #line 1884 "impl/lib/b2/xparser.x"
        be->sl = l->sl;
        #line 1885 "impl/lib/b2/xparser.x"
        be->sc = l->sc;
        #line 1886 "impl/lib/b2/xparser.x"
        xn_arr_o_E_set(lh, 0, be);
            {
            xn_root_restore(xn_t3902);
            }

        xn_gc_safepoint();
    }
#line 1888 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t3894);
    }

return xn_arr_o_E_get(lh, 0);
    return (xn_Cls_E *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_E * xn_Cls_Parser_parseUnary(xn_Cls_Parser *self) {
size_t xn_t3975 = xn_root_mark();
xn_root_add(self);
#line 1892 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_cur(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 1893 "impl/lib/b2/xparser.x"
rt_string *xn_t3976 = rt_retain(t->text);
xn_root_add(xn_t3976);
rt_string *xn_t3977 = rt_string_from_c("!");
xn_root_add(xn_t3977);
rt_string *xn_t3978 = rt_retain(t->text);
xn_root_add(xn_t3978);
rt_string *xn_t3979 = rt_string_from_c("-");
xn_root_add(xn_t3979);
rt_string *xn_t3980 = rt_retain(t->text);
xn_root_add(xn_t3980);
rt_string *xn_t3981 = rt_string_from_c("+");
xn_root_add(xn_t3981);
rt_string *xn_t3982 = rt_retain(t->text);
xn_root_add(xn_t3982);
rt_string *xn_t3983 = rt_string_from_c("~");
xn_root_add(xn_t3983);
rt_string *xn_t3984 = rt_retain(t->text);
xn_root_add(xn_t3984);
rt_string *xn_t3985 = rt_string_from_c("try");
xn_root_add(xn_t3985);
    if (((((t->kind == 9) && (((xn_str_eq(xn_t3976, xn_t3977) || xn_str_eq(xn_t3978, xn_t3979)) || xn_str_eq(xn_t3980, xn_t3981)) || xn_str_eq(xn_t3982, xn_t3983)))) || (((t->kind == 3) && xn_str_eq(xn_t3984, xn_t3985))))) {
        size_t xn_t3986 = xn_root_mark();
        #line 1894 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 1895 "impl/lib/b2/xparser.x"
        xn_Cls_E * x = xn_Cls_Parser_parseUnary(self);
xn_root_add(x);
        xn_root_add(x);
        xn_root_add(x);
        xn_gc_safepoint();
        #line 1896 "impl/lib/b2/xparser.x"
        rt_string *xn_t3987 = rt_string_from_c("(Unary ");
xn_root_add(xn_t3987);
        xn_root_add(xn_t3987);
        xn_root_add(xn_t3987);
        rt_string *xn_t3988 = xn_P(t->line, t->col);
xn_root_add(xn_t3988);
        xn_root_add(xn_t3988);
        xn_root_add(xn_t3988);
        rt_string *xn_t3989 = xn_concat(xn_t3987, xn_t3988);
xn_root_add(xn_t3989);
        xn_root_add(xn_t3989);
        xn_root_add(xn_t3989);
        rt_string *xn_t3990 = rt_string_from_c(" (Op ");
xn_root_add(xn_t3990);
        xn_root_add(xn_t3990);
        xn_root_add(xn_t3990);
        rt_string *xn_t3991 = xn_concat(xn_t3989, xn_t3990);
xn_root_add(xn_t3991);
        xn_root_add(xn_t3991);
        xn_root_add(xn_t3991);
        rt_string *xn_t3992 = rt_retain(t->text);
xn_root_add(xn_t3992);
        xn_root_add(xn_t3992);
        xn_root_add(xn_t3992);
        rt_string *xn_t3993 = xn_q(xn_t3992);
xn_root_add(xn_t3993);
        xn_root_add(xn_t3993);
        xn_root_add(xn_t3993);
        rt_string *xn_t3994 = xn_concat(xn_t3991, xn_t3993);
xn_root_add(xn_t3994);
        xn_root_add(xn_t3994);
        xn_root_add(xn_t3994);
        rt_string *xn_t3995 = rt_string_from_c(") (X ");
xn_root_add(xn_t3995);
        xn_root_add(xn_t3995);
        xn_root_add(xn_t3995);
        rt_string *xn_t3996 = xn_concat(xn_t3994, xn_t3995);
xn_root_add(xn_t3996);
        xn_root_add(xn_t3996);
        xn_root_add(xn_t3996);
        rt_string *xn_t3997 = rt_retain(x->d);
xn_root_add(xn_t3997);
        xn_root_add(xn_t3997);
        xn_root_add(xn_t3997);
        rt_string *xn_t3998 = xn_concat(xn_t3996, xn_t3997);
xn_root_add(xn_t3998);
        xn_root_add(xn_t3998);
        xn_root_add(xn_t3998);
        rt_string *xn_t3999 = rt_string_from_c("))");
xn_root_add(xn_t3999);
        xn_root_add(xn_t3999);
        xn_root_add(xn_t3999);
        rt_string *xn_t4000 = xn_concat(xn_t3998, xn_t3999);
xn_root_add(xn_t4000);
        xn_root_add(xn_t4000);
        xn_root_add(xn_t4000);
            {
        xn_root_restore(xn_t3986);
            }
            {
        xn_root_restore(xn_t3975);
            }

        return xn_Cls_Parser_mk(self, xn_t4000, t->line, t->col);

    }
#line 1898 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t3975);
    }

return xn_Cls_Parser_parsePostfix(self);
    return (xn_Cls_E *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_E * xn_Cls_Parser_parsePostfix(xn_Cls_Parser *self) {
size_t xn_t4001 = xn_root_mark();
xn_root_add(self);
#line 1903 "impl/lib/b2/xparser.x"
xn_arr_o_E *xn_t4002 = xn_arr_o_E_new(0);
xn_root_add(xn_t4002);
xn_arr_o_E * eh = xn_t4002;
xn_root_add(eh);
xn_root_add(eh);
xn_gc_safepoint();
#line 1904 "impl/lib/b2/xparser.x"
xn_Cls_E * xn_t4003 = xn_Cls_Parser_parsePrimary(self);
xn_root_add(xn_t4003);
xn_root_add(xn_t4003);
xn_arr_o_E_push(eh, xn_t4003);
#line 1905 "impl/lib/b2/xparser.x"
int go = 1;
#line 1906 "impl/lib/b2/xparser.x"
    while ((go)) {
    size_t xn_t4004 = xn_root_mark();
    #line 1907 "impl/lib/b2/xparser.x"
    xn_Cls_E * e = xn_arr_o_E_get(eh, 0);
xn_root_add(e);
    xn_root_add(e);
    xn_root_add(e);
    xn_gc_safepoint();
    #line 1908 "impl/lib/b2/xparser.x"
    rt_string *xn_t4005 = rt_retain(e->d);
xn_root_add(xn_t4005);
    xn_root_add(xn_t4005);
    rt_string *xn_t4006 = rt_string_from_c("(IdentExpr ");
xn_root_add(xn_t4006);
    xn_root_add(xn_t4006);
        if (((xn_Cls_Parser_genericCallAhead(self)) && ((xn_str_indexof(xn_t4005, xn_t4006) == 0)))) {
            size_t xn_t4007 = xn_root_mark();
            #line 1909 "impl/lib/b2/xparser.x"
            xn_Cls_Parser_next(self);
            #line 1910 "impl/lib/b2/xparser.x"
            xn_arr_s *xn_t4008 = xn_arr_s_new(0);
xn_root_add(xn_t4008);
    xn_root_add(xn_t4008);
            xn_root_add(xn_t4008);
            xn_arr_s * tas2 = xn_t4008;
xn_root_add(tas2);
    xn_root_add(tas2);
            xn_root_add(tas2);
            xn_root_add(tas2);
            xn_gc_safepoint();
            #line 1911 "impl/lib/b2/xparser.x"
                while (1) {
                    rt_string *xn_t4009 = rt_string_from_c(">");
xn_root_add(xn_t4009);
    xn_root_add(xn_t4009);
            xn_root_add(xn_t4009);
                    if (!((((!(xn_Cls_Parser_atOp(self, xn_t4009)))) && ((!(xn_Cls_Parser_eof(self))))))) { break; }
                    size_t xn_t4010 = xn_root_mark();
                    #line 1912 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 16))) {
                            size_t xn_t4011 = xn_root_mark();
                            #line 1912 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                            #line 1912 "impl/lib/b2/xparser.x"
                            xn_root_restore(xn_t4011);
                            xn_root_restore(xn_t4010);
                            continue;
                                {
                                xn_root_restore(xn_t4011);
                                }

                        }
                    #line 1913 "impl/lib/b2/xparser.x"
                    rt_string *xn_t4012 = xn_Cls_Parser_parseType(self);
xn_root_add(xn_t4012);
    xn_root_add(xn_t4012);
            xn_root_add(xn_t4012);
                    xn_root_add(xn_t4012);
                    xn_arr_s_push(tas2, xn_t4012);
                        {
                        xn_root_restore(xn_t4010);
                        }

                    xn_gc_safepoint();
                }
            #line 1915 "impl/lib/b2/xparser.x"
            rt_string *xn_t4013 = rt_string_from_c(">");
xn_root_add(xn_t4013);
    xn_root_add(xn_t4013);
            xn_root_add(xn_t4013);
                if ((xn_Cls_Parser_atOp(self, xn_t4013))) {
                    size_t xn_t4014 = xn_root_mark();
                    #line 1915 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t4014);
                        }

                }
            #line 1916 "impl/lib/b2/xparser.x"
            xn_arr_s *xn_t4015 = xn_arr_s_new(0);
xn_root_add(xn_t4015);
    xn_root_add(xn_t4015);
            xn_root_add(xn_t4015);
            xn_arr_s * cas = xn_t4015;
xn_root_add(cas);
    xn_root_add(cas);
            xn_root_add(cas);
            xn_root_add(cas);
            xn_gc_safepoint();
            #line 1917 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 10))) {
                    size_t xn_t4016 = xn_root_mark();
                    #line 1918 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 1919 "impl/lib/b2/xparser.x"
                        while ((((!(xn_Cls_Parser_at(self, 11)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                        size_t xn_t4017 = xn_root_mark();
                        #line 1920 "impl/lib/b2/xparser.x"
                            if ((xn_Cls_Parser_at(self, 1))) {
                                size_t xn_t4018 = xn_root_mark();
                                #line 1920 "impl/lib/b2/xparser.x"
                                xn_root_restore(xn_t4018);
                                xn_root_restore(xn_t4017);
                                break;
                                    {
                                    xn_root_restore(xn_t4018);
                                    }

                            }
                        #line 1921 "impl/lib/b2/xparser.x"
                            if ((xn_Cls_Parser_at(self, 16))) {
                                size_t xn_t4019 = xn_root_mark();
                                #line 1921 "impl/lib/b2/xparser.x"
                                xn_Cls_Parser_next(self);
                                #line 1921 "impl/lib/b2/xparser.x"
                                xn_root_restore(xn_t4019);
                                xn_root_restore(xn_t4017);
                                continue;
                                    {
                                    xn_root_restore(xn_t4019);
                                    }

                            }
                        #line 1922 "impl/lib/b2/xparser.x"
                        xn_Cls_E * xn_t4020 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t4020);
    xn_root_add(xn_t4020);
            xn_root_add(xn_t4020);
                    xn_root_add(xn_t4020);
                        xn_root_add(xn_t4020);
                        rt_string *xn_t4021 = rt_retain(xn_t4020->d);
xn_root_add(xn_t4021);
    xn_root_add(xn_t4021);
            xn_root_add(xn_t4021);
                    xn_root_add(xn_t4021);
                        xn_root_add(xn_t4021);
                        xn_arr_s_push(cas, xn_t4021);
                            {
                            xn_root_restore(xn_t4017);
                            }

                        xn_gc_safepoint();
                        }
                    #line 1924 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 11))) {
                            size_t xn_t4022 = xn_root_mark();
                            #line 1924 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                                {
                                xn_root_restore(xn_t4022);
                                }

                        }
                        {
                        xn_root_restore(xn_t4016);
                        }

                }
            #line 1926 "impl/lib/b2/xparser.x"
            rt_string *xn_t4023 = rt_string_from_c("(Call ");
xn_root_add(xn_t4023);
    xn_root_add(xn_t4023);
            xn_root_add(xn_t4023);
            rt_string *xn_t4024 = xn_P(e->l, e->c);
xn_root_add(xn_t4024);
    xn_root_add(xn_t4024);
            xn_root_add(xn_t4024);
            rt_string *xn_t4025 = xn_concat(xn_t4023, xn_t4024);
xn_root_add(xn_t4025);
    xn_root_add(xn_t4025);
            xn_root_add(xn_t4025);
            rt_string *xn_t4026 = rt_string_from_c(" (Callee ");
xn_root_add(xn_t4026);
    xn_root_add(xn_t4026);
            xn_root_add(xn_t4026);
            rt_string *xn_t4027 = xn_concat(xn_t4025, xn_t4026);
xn_root_add(xn_t4027);
    xn_root_add(xn_t4027);
            xn_root_add(xn_t4027);
            rt_string *xn_t4028 = rt_retain(e->d);
xn_root_add(xn_t4028);
    xn_root_add(xn_t4028);
            xn_root_add(xn_t4028);
            rt_string *xn_t4029 = xn_concat(xn_t4027, xn_t4028);
xn_root_add(xn_t4029);
    xn_root_add(xn_t4029);
            xn_root_add(xn_t4029);
            rt_string *xn_t4030 = rt_string_from_c(") (TypeArgs ");
xn_root_add(xn_t4030);
    xn_root_add(xn_t4030);
            xn_root_add(xn_t4030);
            rt_string *xn_t4031 = xn_concat(xn_t4029, xn_t4030);
xn_root_add(xn_t4031);
    xn_root_add(xn_t4031);
            xn_root_add(xn_t4031);
            rt_string *xn_t4032 = xn_SL(tas2);
xn_root_add(xn_t4032);
    xn_root_add(xn_t4032);
            xn_root_add(xn_t4032);
            rt_string *xn_t4033 = xn_concat(xn_t4031, xn_t4032);
xn_root_add(xn_t4033);
    xn_root_add(xn_t4033);
            xn_root_add(xn_t4033);
            rt_string *xn_t4034 = rt_string_from_c(") (Args ");
xn_root_add(xn_t4034);
    xn_root_add(xn_t4034);
            xn_root_add(xn_t4034);
            rt_string *xn_t4035 = xn_concat(xn_t4033, xn_t4034);
xn_root_add(xn_t4035);
    xn_root_add(xn_t4035);
            xn_root_add(xn_t4035);
            rt_string *xn_t4036 = xn_SL(cas);
xn_root_add(xn_t4036);
    xn_root_add(xn_t4036);
            xn_root_add(xn_t4036);
            rt_string *xn_t4037 = xn_concat(xn_t4035, xn_t4036);
xn_root_add(xn_t4037);
    xn_root_add(xn_t4037);
            xn_root_add(xn_t4037);
            rt_string *xn_t4038 = rt_string_from_c("))");
xn_root_add(xn_t4038);
    xn_root_add(xn_t4038);
            xn_root_add(xn_t4038);
            rt_string *xn_t4039 = xn_concat(xn_t4037, xn_t4038);
xn_root_add(xn_t4039);
    xn_root_add(xn_t4039);
            xn_root_add(xn_t4039);
            xn_Cls_E * ne = xn_Cls_Parser_mk(self, xn_t4039, e->l, e->c);
xn_root_add(ne);
    xn_root_add(ne);
            xn_root_add(ne);
            xn_root_add(ne);
            xn_gc_safepoint();
            #line 1927 "impl/lib/b2/xparser.x"
            ne->sl = e->sl;
            #line 1927 "impl/lib/b2/xparser.x"
            ne->sc = e->sc;
            #line 1927 "impl/lib/b2/xparser.x"
            xn_arr_o_E_set(eh, 0, ne);
                {
                xn_root_restore(xn_t4007);
                }

        } else {
            rt_string *xn_t4041 = rt_string_from_c(".");
xn_root_add(xn_t4041);
    xn_root_add(xn_t4041);
            xn_root_add(xn_t4041);
            rt_string *xn_t4042 = rt_string_from_c("?.");
xn_root_add(xn_t4042);
    xn_root_add(xn_t4042);
            xn_root_add(xn_t4042);
                if (((xn_Cls_Parser_atOp(self, xn_t4041)) || (xn_Cls_Parser_atOp(self, xn_t4042)))) {
                    size_t xn_t4043 = xn_root_mark();
                    #line 1929 "impl/lib/b2/xparser.x"
                    xn_Cls_Tok * xn_t4044 = xn_Cls_Parser_cur(self);
xn_root_add(xn_t4044);
    xn_root_add(xn_t4044);
            xn_root_add(xn_t4044);
                    xn_root_add(xn_t4044);
                    rt_string *xn_t4045 = rt_retain(xn_t4044->text);
xn_root_add(xn_t4045);
    xn_root_add(xn_t4045);
            xn_root_add(xn_t4045);
                    xn_root_add(xn_t4045);
                    rt_string *xn_t4046 = rt_string_from_c("?.");
xn_root_add(xn_t4046);
    xn_root_add(xn_t4046);
            xn_root_add(xn_t4046);
                    xn_root_add(xn_t4046);
                    int ns = xn_str_eq(xn_t4045, xn_t4046);
                    #line 1930 "impl/lib/b2/xparser.x"
                    xn_Cls_Tok * dot = xn_Cls_Parser_next(self);
xn_root_add(dot);
    xn_root_add(dot);
            xn_root_add(dot);
                    xn_root_add(dot);
                    xn_root_add(dot);
                    xn_gc_safepoint();
                    #line 1931 "impl/lib/b2/xparser.x"
                    xn_Cls_Tok * n = xn_Cls_Parser_cur(self);
xn_root_add(n);
    xn_root_add(n);
            xn_root_add(n);
                    xn_root_add(n);
                    xn_root_add(n);
                    xn_gc_safepoint();
                    #line 1932 "impl/lib/b2/xparser.x"
                        if (((n->kind == 2))) {
                            size_t xn_t4047 = xn_root_mark();
                            #line 1933 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                            #line 1934 "impl/lib/b2/xparser.x"
                            rt_string *xn_t4048 = rt_string_from_c("(Member ");
xn_root_add(xn_t4048);
    xn_root_add(xn_t4048);
            xn_root_add(xn_t4048);
                    xn_root_add(xn_t4048);
                            xn_root_add(xn_t4048);
                            rt_string *xn_t4049 = xn_P(dot->line, dot->col);
xn_root_add(xn_t4049);
    xn_root_add(xn_t4049);
            xn_root_add(xn_t4049);
                    xn_root_add(xn_t4049);
                            xn_root_add(xn_t4049);
                            rt_string *xn_t4050 = xn_concat(xn_t4048, xn_t4049);
xn_root_add(xn_t4050);
    xn_root_add(xn_t4050);
            xn_root_add(xn_t4050);
                    xn_root_add(xn_t4050);
                            xn_root_add(xn_t4050);
                            rt_string *xn_t4051 = rt_string_from_c(" (X ");
xn_root_add(xn_t4051);
    xn_root_add(xn_t4051);
            xn_root_add(xn_t4051);
                    xn_root_add(xn_t4051);
                            xn_root_add(xn_t4051);
                            rt_string *xn_t4052 = xn_concat(xn_t4050, xn_t4051);
xn_root_add(xn_t4052);
    xn_root_add(xn_t4052);
            xn_root_add(xn_t4052);
                    xn_root_add(xn_t4052);
                            xn_root_add(xn_t4052);
                            rt_string *xn_t4053 = rt_retain(e->d);
xn_root_add(xn_t4053);
    xn_root_add(xn_t4053);
            xn_root_add(xn_t4053);
                    xn_root_add(xn_t4053);
                            xn_root_add(xn_t4053);
                            rt_string *xn_t4054 = xn_concat(xn_t4052, xn_t4053);
xn_root_add(xn_t4054);
    xn_root_add(xn_t4054);
            xn_root_add(xn_t4054);
                    xn_root_add(xn_t4054);
                            xn_root_add(xn_t4054);
                            rt_string *xn_t4055 = rt_string_from_c(") (Name ");
xn_root_add(xn_t4055);
    xn_root_add(xn_t4055);
            xn_root_add(xn_t4055);
                    xn_root_add(xn_t4055);
                            xn_root_add(xn_t4055);
                            rt_string *xn_t4056 = xn_concat(xn_t4054, xn_t4055);
xn_root_add(xn_t4056);
    xn_root_add(xn_t4056);
            xn_root_add(xn_t4056);
                    xn_root_add(xn_t4056);
                            xn_root_add(xn_t4056);
                            rt_string *xn_t4057 = rt_retain(n->text);
xn_root_add(xn_t4057);
    xn_root_add(xn_t4057);
            xn_root_add(xn_t4057);
                    xn_root_add(xn_t4057);
                            xn_root_add(xn_t4057);
                            rt_string *xn_t4058 = xn_q(xn_t4057);
xn_root_add(xn_t4058);
    xn_root_add(xn_t4058);
            xn_root_add(xn_t4058);
                    xn_root_add(xn_t4058);
                            xn_root_add(xn_t4058);
                            rt_string *xn_t4059 = xn_concat(xn_t4056, xn_t4058);
xn_root_add(xn_t4059);
    xn_root_add(xn_t4059);
            xn_root_add(xn_t4059);
                    xn_root_add(xn_t4059);
                            xn_root_add(xn_t4059);
                            rt_string *xn_t4060 = rt_string_from_c(") (NullSafe ");
xn_root_add(xn_t4060);
    xn_root_add(xn_t4060);
            xn_root_add(xn_t4060);
                    xn_root_add(xn_t4060);
                            xn_root_add(xn_t4060);
                            rt_string *xn_t4061 = xn_concat(xn_t4059, xn_t4060);
xn_root_add(xn_t4061);
    xn_root_add(xn_t4061);
            xn_root_add(xn_t4061);
                    xn_root_add(xn_t4061);
                            xn_root_add(xn_t4061);
                            rt_string *xn_t4062 = xn_B(ns);
xn_root_add(xn_t4062);
    xn_root_add(xn_t4062);
            xn_root_add(xn_t4062);
                    xn_root_add(xn_t4062);
                            xn_root_add(xn_t4062);
                            rt_string *xn_t4063 = xn_concat(xn_t4061, xn_t4062);
xn_root_add(xn_t4063);
    xn_root_add(xn_t4063);
            xn_root_add(xn_t4063);
                    xn_root_add(xn_t4063);
                            xn_root_add(xn_t4063);
                            rt_string *xn_t4064 = rt_string_from_c("))");
xn_root_add(xn_t4064);
    xn_root_add(xn_t4064);
            xn_root_add(xn_t4064);
                    xn_root_add(xn_t4064);
                            xn_root_add(xn_t4064);
                            rt_string *d = xn_concat(xn_t4063, xn_t4064);
xn_root_add(d);
    xn_root_add(d);
            xn_root_add(d);
                    xn_root_add(d);
                            xn_root_add(d);
                            xn_root_add(d);
                            xn_gc_safepoint();
                            #line 1935 "impl/lib/b2/xparser.x"
                            rt_string *xn_t4066 = rt_retain(d);
xn_root_add(xn_t4066);
    xn_root_add(xn_t4066);
            xn_root_add(xn_t4066);
                    xn_root_add(xn_t4066);
                            xn_root_add(xn_t4066);
                            xn_Cls_E * ne = xn_Cls_Parser_mk(self, xn_t4066, dot->line, dot->col);
xn_root_add(ne);
    xn_root_add(ne);
            xn_root_add(ne);
                    xn_root_add(ne);
                            xn_root_add(ne);
                            xn_root_add(ne);
                            xn_gc_safepoint();
                            #line 1935 "impl/lib/b2/xparser.x"
                            ne->sl = e->sl;
                            #line 1935 "impl/lib/b2/xparser.x"
                            ne->sc = e->sc;
                            #line 1935 "impl/lib/b2/xparser.x"
                            xn_arr_o_E_set(eh, 0, ne);
                                {
                                rt_release(d);
                                }
                                {
                                xn_root_restore(xn_t4047);
                                }

                        } else {
                                if (((n->kind == 5))) {
                                    size_t xn_t4068 = xn_root_mark();
                                    #line 1937 "impl/lib/b2/xparser.x"
                                    xn_Cls_Parser_next(self);
                                    #line 1938 "impl/lib/b2/xparser.x"
                                    rt_string *xn_t4069 = rt_string_from_c("(TupleMember ");
xn_root_add(xn_t4069);
    xn_root_add(xn_t4069);
            xn_root_add(xn_t4069);
                    xn_root_add(xn_t4069);
                            xn_root_add(xn_t4069);
                                    xn_root_add(xn_t4069);
                                    rt_string *xn_t4070 = xn_P(dot->line, dot->col);
xn_root_add(xn_t4070);
    xn_root_add(xn_t4070);
            xn_root_add(xn_t4070);
                    xn_root_add(xn_t4070);
                            xn_root_add(xn_t4070);
                                    xn_root_add(xn_t4070);
                                    rt_string *xn_t4071 = xn_concat(xn_t4069, xn_t4070);
xn_root_add(xn_t4071);
    xn_root_add(xn_t4071);
            xn_root_add(xn_t4071);
                    xn_root_add(xn_t4071);
                            xn_root_add(xn_t4071);
                                    xn_root_add(xn_t4071);
                                    rt_string *xn_t4072 = rt_string_from_c(" (X ");
xn_root_add(xn_t4072);
    xn_root_add(xn_t4072);
            xn_root_add(xn_t4072);
                    xn_root_add(xn_t4072);
                            xn_root_add(xn_t4072);
                                    xn_root_add(xn_t4072);
                                    rt_string *xn_t4073 = xn_concat(xn_t4071, xn_t4072);
xn_root_add(xn_t4073);
    xn_root_add(xn_t4073);
            xn_root_add(xn_t4073);
                    xn_root_add(xn_t4073);
                            xn_root_add(xn_t4073);
                                    xn_root_add(xn_t4073);
                                    rt_string *xn_t4074 = rt_retain(e->d);
xn_root_add(xn_t4074);
    xn_root_add(xn_t4074);
            xn_root_add(xn_t4074);
                    xn_root_add(xn_t4074);
                            xn_root_add(xn_t4074);
                                    xn_root_add(xn_t4074);
                                    rt_string *xn_t4075 = xn_concat(xn_t4073, xn_t4074);
xn_root_add(xn_t4075);
    xn_root_add(xn_t4075);
            xn_root_add(xn_t4075);
                    xn_root_add(xn_t4075);
                            xn_root_add(xn_t4075);
                                    xn_root_add(xn_t4075);
                                    rt_string *xn_t4076 = rt_string_from_c(") (Index ");
xn_root_add(xn_t4076);
    xn_root_add(xn_t4076);
            xn_root_add(xn_t4076);
                    xn_root_add(xn_t4076);
                            xn_root_add(xn_t4076);
                                    xn_root_add(xn_t4076);
                                    rt_string *xn_t4077 = xn_concat(xn_t4075, xn_t4076);
xn_root_add(xn_t4077);
    xn_root_add(xn_t4077);
            xn_root_add(xn_t4077);
                    xn_root_add(xn_t4077);
                            xn_root_add(xn_t4077);
                                    xn_root_add(xn_t4077);
                                    rt_string *xn_t4078 = rt_retain(n->text);
xn_root_add(xn_t4078);
    xn_root_add(xn_t4078);
            xn_root_add(xn_t4078);
                    xn_root_add(xn_t4078);
                            xn_root_add(xn_t4078);
                                    xn_root_add(xn_t4078);
                                    rt_string *xn_t4079 = xn_concat(xn_t4077, xn_t4078);
xn_root_add(xn_t4079);
    xn_root_add(xn_t4079);
            xn_root_add(xn_t4079);
                    xn_root_add(xn_t4079);
                            xn_root_add(xn_t4079);
                                    xn_root_add(xn_t4079);
                                    rt_string *xn_t4080 = rt_string_from_c(") (NullSafe ");
xn_root_add(xn_t4080);
    xn_root_add(xn_t4080);
            xn_root_add(xn_t4080);
                    xn_root_add(xn_t4080);
                            xn_root_add(xn_t4080);
                                    xn_root_add(xn_t4080);
                                    rt_string *xn_t4081 = xn_concat(xn_t4079, xn_t4080);
xn_root_add(xn_t4081);
    xn_root_add(xn_t4081);
            xn_root_add(xn_t4081);
                    xn_root_add(xn_t4081);
                            xn_root_add(xn_t4081);
                                    xn_root_add(xn_t4081);
                                    rt_string *xn_t4082 = xn_B(ns);
xn_root_add(xn_t4082);
    xn_root_add(xn_t4082);
            xn_root_add(xn_t4082);
                    xn_root_add(xn_t4082);
                            xn_root_add(xn_t4082);
                                    xn_root_add(xn_t4082);
                                    rt_string *xn_t4083 = xn_concat(xn_t4081, xn_t4082);
xn_root_add(xn_t4083);
    xn_root_add(xn_t4083);
            xn_root_add(xn_t4083);
                    xn_root_add(xn_t4083);
                            xn_root_add(xn_t4083);
                                    xn_root_add(xn_t4083);
                                    rt_string *xn_t4084 = rt_string_from_c("))");
xn_root_add(xn_t4084);
    xn_root_add(xn_t4084);
            xn_root_add(xn_t4084);
                    xn_root_add(xn_t4084);
                            xn_root_add(xn_t4084);
                                    xn_root_add(xn_t4084);
                                    rt_string *d = xn_concat(xn_t4083, xn_t4084);
xn_root_add(d);
    xn_root_add(d);
            xn_root_add(d);
                    xn_root_add(d);
                            xn_root_add(d);
                                    xn_root_add(d);
                                    xn_root_add(d);
                                    xn_gc_safepoint();
                                    #line 1939 "impl/lib/b2/xparser.x"
                                    rt_string *xn_t4086 = rt_retain(d);
xn_root_add(xn_t4086);
    xn_root_add(xn_t4086);
            xn_root_add(xn_t4086);
                    xn_root_add(xn_t4086);
                            xn_root_add(xn_t4086);
                                    xn_root_add(xn_t4086);
                                    xn_Cls_E * ne = xn_Cls_Parser_mk(self, xn_t4086, dot->line, dot->col);
xn_root_add(ne);
    xn_root_add(ne);
            xn_root_add(ne);
                    xn_root_add(ne);
                            xn_root_add(ne);
                                    xn_root_add(ne);
                                    xn_root_add(ne);
                                    xn_gc_safepoint();
                                    #line 1939 "impl/lib/b2/xparser.x"
                                    ne->sl = e->sl;
                                    #line 1939 "impl/lib/b2/xparser.x"
                                    ne->sc = e->sc;
                                    #line 1939 "impl/lib/b2/xparser.x"
                                    xn_arr_o_E_set(eh, 0, ne);
                                        {
                                        rt_release(d);
                                        }
                                        {
                                        xn_root_restore(xn_t4068);
                                        }

                                } else {
                                    size_t xn_t4087 = xn_root_mark();
                                    #line 1940 "impl/lib/b2/xparser.x"
                                    xn_Cls_Parser_next(self);
                                        {
                                        xn_root_restore(xn_t4087);
                                        }

                                }
                        }
                        {
                        xn_root_restore(xn_t4043);
                        }

                } else {
                        if ((xn_Cls_Parser_at(self, 10))) {
                            size_t xn_t4089 = xn_root_mark();
                            #line 1942 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                            #line 1943 "impl/lib/b2/xparser.x"
                            xn_arr_s *xn_t4090 = xn_arr_s_new(0);
xn_root_add(xn_t4090);
    xn_root_add(xn_t4090);
            xn_root_add(xn_t4090);
                    xn_root_add(xn_t4090);
                            xn_root_add(xn_t4090);
                            xn_arr_s * tas = xn_t4090;
xn_root_add(tas);
    xn_root_add(tas);
            xn_root_add(tas);
                    xn_root_add(tas);
                            xn_root_add(tas);
                            xn_root_add(tas);
                            xn_gc_safepoint();
                            #line 1944 "impl/lib/b2/xparser.x"
                            int argBad = 0;
                            #line 1945 "impl/lib/b2/xparser.x"
                                while ((((!(xn_Cls_Parser_at(self, 11)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                                size_t xn_t4091 = xn_root_mark();
                                #line 1946 "impl/lib/b2/xparser.x"
                                    if ((xn_Cls_Parser_at(self, 1))) {
                                        size_t xn_t4092 = xn_root_mark();
                                        #line 1947 "impl/lib/b2/xparser.x"
                                        xn_Cls_Tok * ce = xn_Cls_Parser_cur(self);
xn_root_add(ce);
    xn_root_add(ce);
            xn_root_add(ce);
                    xn_root_add(ce);
                            xn_root_add(ce);
                                xn_root_add(ce);
                                        xn_root_add(ce);
                                        xn_root_add(ce);
                                        xn_gc_safepoint();
                                        #line 1948 "impl/lib/b2/xparser.x"
                                        rt_string *xn_t4093 = rt_string_from_c("SYN-101");
xn_root_add(xn_t4093);
    xn_root_add(xn_t4093);
            xn_root_add(xn_t4093);
                    xn_root_add(xn_t4093);
                            xn_root_add(xn_t4093);
                                xn_root_add(xn_t4093);
                                        xn_root_add(xn_t4093);
                                        rt_string *xn_t4094 = rt_string_from_c("期望`)`");
xn_root_add(xn_t4094);
    xn_root_add(xn_t4094);
            xn_root_add(xn_t4094);
                    xn_root_add(xn_t4094);
                            xn_root_add(xn_t4094);
                                xn_root_add(xn_t4094);
                                        xn_root_add(xn_t4094);
                                        xn_Cls_Parser_err(self, xn_t4093, ce->line, ce->col, xn_t4094);
                                        #line 1949 "impl/lib/b2/xparser.x"
                                        argBad = 1;
                                        #line 1950 "impl/lib/b2/xparser.x"
                                        xn_root_restore(xn_t4092);
                                        xn_root_restore(xn_t4091);
                                        break;
                                            {
                                            xn_root_restore(xn_t4092);
                                            }

                                    }
                                #line 1952 "impl/lib/b2/xparser.x"
                                    if ((xn_Cls_Parser_at(self, 16))) {
                                        size_t xn_t4095 = xn_root_mark();
                                        #line 1952 "impl/lib/b2/xparser.x"
                                        xn_Cls_Parser_next(self);
                                        #line 1952 "impl/lib/b2/xparser.x"
                                        xn_root_restore(xn_t4095);
                                        xn_root_restore(xn_t4091);
                                        continue;
                                            {
                                            xn_root_restore(xn_t4095);
                                            }

                                    }
                                #line 1953 "impl/lib/b2/xparser.x"
                                xn_Cls_E * xn_t4096 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t4096);
    xn_root_add(xn_t4096);
            xn_root_add(xn_t4096);
                    xn_root_add(xn_t4096);
                            xn_root_add(xn_t4096);
                                xn_root_add(xn_t4096);
                                rt_string *xn_t4097 = rt_retain(xn_t4096->d);
xn_root_add(xn_t4097);
    xn_root_add(xn_t4097);
            xn_root_add(xn_t4097);
                    xn_root_add(xn_t4097);
                            xn_root_add(xn_t4097);
                                xn_root_add(xn_t4097);
                                xn_arr_s_push(tas, xn_t4097);
                                    {
                                    xn_root_restore(xn_t4091);
                                    }

                                xn_gc_safepoint();
                                }
                            #line 1955 "impl/lib/b2/xparser.x"
                                if ((xn_Cls_Parser_at(self, 11))) {
                                    size_t xn_t4098 = xn_root_mark();
                                    #line 1955 "impl/lib/b2/xparser.x"
                                    xn_Cls_Parser_next(self);
                                        {
                                        xn_root_restore(xn_t4098);
                                        }

                                } else {
                                        if (((!(argBad)))) {
                                            size_t xn_t4100 = xn_root_mark();
                                            #line 1956 "impl/lib/b2/xparser.x"
                                            xn_Cls_Tok * ce = xn_Cls_Parser_cur(self);
xn_root_add(ce);
    xn_root_add(ce);
            xn_root_add(ce);
                    xn_root_add(ce);
                            xn_root_add(ce);
                                    xn_root_add(ce);
                                            xn_root_add(ce);
                                            xn_root_add(ce);
                                            xn_gc_safepoint();
                                            #line 1957 "impl/lib/b2/xparser.x"
                                            rt_string *xn_t4101 = rt_string_from_c("SYN-101");
xn_root_add(xn_t4101);
    xn_root_add(xn_t4101);
            xn_root_add(xn_t4101);
                    xn_root_add(xn_t4101);
                            xn_root_add(xn_t4101);
                                    xn_root_add(xn_t4101);
                                            xn_root_add(xn_t4101);
                                            rt_string *xn_t4102 = rt_string_from_c("期望`)`");
xn_root_add(xn_t4102);
    xn_root_add(xn_t4102);
            xn_root_add(xn_t4102);
                    xn_root_add(xn_t4102);
                            xn_root_add(xn_t4102);
                                    xn_root_add(xn_t4102);
                                            xn_root_add(xn_t4102);
                                            xn_Cls_Parser_err(self, xn_t4101, ce->line, ce->col, xn_t4102);
                                                {
                                                xn_root_restore(xn_t4100);
                                                }

                                        }
                                }
                            #line 1959 "impl/lib/b2/xparser.x"
                            rt_string *xn_t4103 = rt_string_from_c("(Call ");
xn_root_add(xn_t4103);
    xn_root_add(xn_t4103);
            xn_root_add(xn_t4103);
                    xn_root_add(xn_t4103);
                            xn_root_add(xn_t4103);
                            rt_string *xn_t4104 = xn_P(e->l, e->c);
xn_root_add(xn_t4104);
    xn_root_add(xn_t4104);
            xn_root_add(xn_t4104);
                    xn_root_add(xn_t4104);
                            xn_root_add(xn_t4104);
                            rt_string *xn_t4105 = xn_concat(xn_t4103, xn_t4104);
xn_root_add(xn_t4105);
    xn_root_add(xn_t4105);
            xn_root_add(xn_t4105);
                    xn_root_add(xn_t4105);
                            xn_root_add(xn_t4105);
                            rt_string *xn_t4106 = rt_string_from_c(" (Callee ");
xn_root_add(xn_t4106);
    xn_root_add(xn_t4106);
            xn_root_add(xn_t4106);
                    xn_root_add(xn_t4106);
                            xn_root_add(xn_t4106);
                            rt_string *xn_t4107 = xn_concat(xn_t4105, xn_t4106);
xn_root_add(xn_t4107);
    xn_root_add(xn_t4107);
            xn_root_add(xn_t4107);
                    xn_root_add(xn_t4107);
                            xn_root_add(xn_t4107);
                            rt_string *xn_t4108 = rt_retain(e->d);
xn_root_add(xn_t4108);
    xn_root_add(xn_t4108);
            xn_root_add(xn_t4108);
                    xn_root_add(xn_t4108);
                            xn_root_add(xn_t4108);
                            rt_string *xn_t4109 = xn_concat(xn_t4107, xn_t4108);
xn_root_add(xn_t4109);
    xn_root_add(xn_t4109);
            xn_root_add(xn_t4109);
                    xn_root_add(xn_t4109);
                            xn_root_add(xn_t4109);
                            rt_string *xn_t4110 = rt_string_from_c(") (TypeArgs (slice)) (Args ");
xn_root_add(xn_t4110);
    xn_root_add(xn_t4110);
            xn_root_add(xn_t4110);
                    xn_root_add(xn_t4110);
                            xn_root_add(xn_t4110);
                            rt_string *xn_t4111 = xn_concat(xn_t4109, xn_t4110);
xn_root_add(xn_t4111);
    xn_root_add(xn_t4111);
            xn_root_add(xn_t4111);
                    xn_root_add(xn_t4111);
                            xn_root_add(xn_t4111);
                            rt_string *xn_t4112 = xn_SL(tas);
xn_root_add(xn_t4112);
    xn_root_add(xn_t4112);
            xn_root_add(xn_t4112);
                    xn_root_add(xn_t4112);
                            xn_root_add(xn_t4112);
                            rt_string *xn_t4113 = xn_concat(xn_t4111, xn_t4112);
xn_root_add(xn_t4113);
    xn_root_add(xn_t4113);
            xn_root_add(xn_t4113);
                    xn_root_add(xn_t4113);
                            xn_root_add(xn_t4113);
                            rt_string *xn_t4114 = rt_string_from_c("))");
xn_root_add(xn_t4114);
    xn_root_add(xn_t4114);
            xn_root_add(xn_t4114);
                    xn_root_add(xn_t4114);
                            xn_root_add(xn_t4114);
                            rt_string *xn_t4115 = xn_concat(xn_t4113, xn_t4114);
xn_root_add(xn_t4115);
    xn_root_add(xn_t4115);
            xn_root_add(xn_t4115);
                    xn_root_add(xn_t4115);
                            xn_root_add(xn_t4115);
                            xn_Cls_E * ne = xn_Cls_Parser_mk(self, xn_t4115, e->l, e->c);
xn_root_add(ne);
    xn_root_add(ne);
            xn_root_add(ne);
                    xn_root_add(ne);
                            xn_root_add(ne);
                            xn_root_add(ne);
                            xn_gc_safepoint();
                            #line 1960 "impl/lib/b2/xparser.x"
                            ne->sl = e->sl;
                            #line 1960 "impl/lib/b2/xparser.x"
                            ne->sc = e->sc;
                            #line 1960 "impl/lib/b2/xparser.x"
                            xn_arr_o_E_set(eh, 0, ne);
                                {
                                xn_root_restore(xn_t4089);
                                }

                        } else {
                                if ((xn_Cls_Parser_at(self, 14))) {
                                    size_t xn_t4117 = xn_root_mark();
                                    #line 1962 "impl/lib/b2/xparser.x"
                                    xn_Cls_Parser_next(self);
                                    #line 1963 "impl/lib/b2/xparser.x"
                                    xn_Cls_E * idx = xn_Cls_Parser_parseExpr(self);
xn_root_add(idx);
    xn_root_add(idx);
            xn_root_add(idx);
                    xn_root_add(idx);
                            xn_root_add(idx);
                                    xn_root_add(idx);
                                    xn_root_add(idx);
                                    xn_gc_safepoint();
                                    #line 1964 "impl/lib/b2/xparser.x"
                                        if ((xn_Cls_Parser_at(self, 15))) {
                                            size_t xn_t4118 = xn_root_mark();
                                            #line 1964 "impl/lib/b2/xparser.x"
                                            xn_Cls_Parser_next(self);
                                                {
                                                xn_root_restore(xn_t4118);
                                                }

                                        }
                                    #line 1965 "impl/lib/b2/xparser.x"
                                    rt_string *xn_t4119 = rt_string_from_c("(Index ");
xn_root_add(xn_t4119);
    xn_root_add(xn_t4119);
            xn_root_add(xn_t4119);
                    xn_root_add(xn_t4119);
                            xn_root_add(xn_t4119);
                                    xn_root_add(xn_t4119);
                                    rt_string *xn_t4120 = xn_P(e->l, e->c);
xn_root_add(xn_t4120);
    xn_root_add(xn_t4120);
            xn_root_add(xn_t4120);
                    xn_root_add(xn_t4120);
                            xn_root_add(xn_t4120);
                                    xn_root_add(xn_t4120);
                                    rt_string *xn_t4121 = xn_concat(xn_t4119, xn_t4120);
xn_root_add(xn_t4121);
    xn_root_add(xn_t4121);
            xn_root_add(xn_t4121);
                    xn_root_add(xn_t4121);
                            xn_root_add(xn_t4121);
                                    xn_root_add(xn_t4121);
                                    rt_string *xn_t4122 = rt_string_from_c(" (X ");
xn_root_add(xn_t4122);
    xn_root_add(xn_t4122);
            xn_root_add(xn_t4122);
                    xn_root_add(xn_t4122);
                            xn_root_add(xn_t4122);
                                    xn_root_add(xn_t4122);
                                    rt_string *xn_t4123 = xn_concat(xn_t4121, xn_t4122);
xn_root_add(xn_t4123);
    xn_root_add(xn_t4123);
            xn_root_add(xn_t4123);
                    xn_root_add(xn_t4123);
                            xn_root_add(xn_t4123);
                                    xn_root_add(xn_t4123);
                                    rt_string *xn_t4124 = rt_retain(e->d);
xn_root_add(xn_t4124);
    xn_root_add(xn_t4124);
            xn_root_add(xn_t4124);
                    xn_root_add(xn_t4124);
                            xn_root_add(xn_t4124);
                                    xn_root_add(xn_t4124);
                                    rt_string *xn_t4125 = xn_concat(xn_t4123, xn_t4124);
xn_root_add(xn_t4125);
    xn_root_add(xn_t4125);
            xn_root_add(xn_t4125);
                    xn_root_add(xn_t4125);
                            xn_root_add(xn_t4125);
                                    xn_root_add(xn_t4125);
                                    rt_string *xn_t4126 = rt_string_from_c(") (Idx ");
xn_root_add(xn_t4126);
    xn_root_add(xn_t4126);
            xn_root_add(xn_t4126);
                    xn_root_add(xn_t4126);
                            xn_root_add(xn_t4126);
                                    xn_root_add(xn_t4126);
                                    rt_string *xn_t4127 = xn_concat(xn_t4125, xn_t4126);
xn_root_add(xn_t4127);
    xn_root_add(xn_t4127);
            xn_root_add(xn_t4127);
                    xn_root_add(xn_t4127);
                            xn_root_add(xn_t4127);
                                    xn_root_add(xn_t4127);
                                    rt_string *xn_t4128 = rt_retain(idx->d);
xn_root_add(xn_t4128);
    xn_root_add(xn_t4128);
            xn_root_add(xn_t4128);
                    xn_root_add(xn_t4128);
                            xn_root_add(xn_t4128);
                                    xn_root_add(xn_t4128);
                                    rt_string *xn_t4129 = xn_concat(xn_t4127, xn_t4128);
xn_root_add(xn_t4129);
    xn_root_add(xn_t4129);
            xn_root_add(xn_t4129);
                    xn_root_add(xn_t4129);
                            xn_root_add(xn_t4129);
                                    xn_root_add(xn_t4129);
                                    rt_string *xn_t4130 = rt_string_from_c("))");
xn_root_add(xn_t4130);
    xn_root_add(xn_t4130);
            xn_root_add(xn_t4130);
                    xn_root_add(xn_t4130);
                            xn_root_add(xn_t4130);
                                    xn_root_add(xn_t4130);
                                    rt_string *xn_t4131 = xn_concat(xn_t4129, xn_t4130);
xn_root_add(xn_t4131);
    xn_root_add(xn_t4131);
            xn_root_add(xn_t4131);
                    xn_root_add(xn_t4131);
                            xn_root_add(xn_t4131);
                                    xn_root_add(xn_t4131);
                                    xn_Cls_E * ne = xn_Cls_Parser_mk(self, xn_t4131, e->l, e->c);
xn_root_add(ne);
    xn_root_add(ne);
            xn_root_add(ne);
                    xn_root_add(ne);
                            xn_root_add(ne);
                                    xn_root_add(ne);
                                    xn_root_add(ne);
                                    xn_gc_safepoint();
                                    #line 1966 "impl/lib/b2/xparser.x"
                                    ne->sl = e->sl;
                                    #line 1966 "impl/lib/b2/xparser.x"
                                    ne->sc = e->sc;
                                    #line 1966 "impl/lib/b2/xparser.x"
                                    xn_arr_o_E_set(eh, 0, ne);
                                        {
                                        xn_root_restore(xn_t4117);
                                        }

                                } else {
                                    size_t xn_t4132 = xn_root_mark();
                                    #line 1967 "impl/lib/b2/xparser.x"
                                    go = 0;
                                        {
                                        xn_root_restore(xn_t4132);
                                        }

                                }
                        }
                }
        }
        {
        xn_root_restore(xn_t4004);
        }

    xn_gc_safepoint();
    }
#line 1969 "impl/lib/b2/xparser.x"
    {
xn_root_restore(xn_t4001);
    }

return xn_arr_o_E_get(eh, 0);
    return (xn_Cls_E *)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Parser_genericCallAhead(xn_Cls_Parser *self) {
size_t xn_t4133 = xn_root_mark();
xn_root_add(self);
#line 1973 "impl/lib/b2/xparser.x"
rt_string *xn_t4134 = rt_string_from_c("<");
xn_root_add(xn_t4134);
    if (((!(xn_Cls_Parser_atOp(self, xn_t4134))))) {
        size_t xn_t4135 = xn_root_mark();
        #line 1973 "impl/lib/b2/xparser.x"
        int xn_t4136 = 0;
            {
        xn_root_restore(xn_t4135);
            }
            {
        xn_root_restore(xn_t4133);
            }

        return xn_t4136;

    }
#line 1974 "impl/lib/b2/xparser.x"
int64_t dep = 0;
#line 1975 "impl/lib/b2/xparser.x"
int64_t j = self->i;
#line 1976 "impl/lib/b2/xparser.x"
    while (((j < ((int64_t)self->toks->len)))) {
    size_t xn_t4137 = xn_root_mark();
    #line 1977 "impl/lib/b2/xparser.x"
    xn_Cls_Tok * x = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(x);
    xn_root_add(x);
    xn_root_add(x);
    xn_gc_safepoint();
    #line 1978 "impl/lib/b2/xparser.x"
    rt_string *xn_t4138 = rt_retain(x->text);
xn_root_add(xn_t4138);
    xn_root_add(xn_t4138);
    rt_string *xn_t4139 = rt_string_from_c("<");
xn_root_add(xn_t4139);
    xn_root_add(xn_t4139);
        if ((((x->kind == 9)) && (xn_str_eq(xn_t4138, xn_t4139)))) {
            size_t xn_t4140 = xn_root_mark();
            #line 1978 "impl/lib/b2/xparser.x"
            dep = (dep + 1);
                {
                xn_root_restore(xn_t4140);
                }

        } else {
            rt_string *xn_t4142 = rt_retain(x->text);
xn_root_add(xn_t4142);
    xn_root_add(xn_t4142);
            xn_root_add(xn_t4142);
            rt_string *xn_t4143 = rt_string_from_c(">");
xn_root_add(xn_t4143);
    xn_root_add(xn_t4143);
            xn_root_add(xn_t4143);
                if ((((x->kind == 9)) && (xn_str_eq(xn_t4142, xn_t4143)))) {
                    size_t xn_t4144 = xn_root_mark();
                    #line 1980 "impl/lib/b2/xparser.x"
                    dep = (dep - 1);
                    #line 1981 "impl/lib/b2/xparser.x"
                        if (((dep == 0))) {
                            size_t xn_t4145 = xn_root_mark();
                            #line 1981 "impl/lib/b2/xparser.x"
                            xn_Cls_Tok * xn_t4146 = xn_arr_o_Tok_get(self->toks, (j + 1));
xn_root_add(xn_t4146);
    xn_root_add(xn_t4146);
            xn_root_add(xn_t4146);
                    xn_root_add(xn_t4146);
                            xn_root_add(xn_t4146);
                            xn_root_add(xn_t4146);
                            int xn_t4147 = (((j + 1) < ((int64_t)self->toks->len)) && (xn_t4146->kind == 10));
                                {
                            xn_root_restore(xn_t4145);
                                }
                                {
                            xn_root_restore(xn_t4144);
                                }
                                {
                            xn_root_restore(xn_t4137);
                                }
                                {
                            xn_root_restore(xn_t4133);
                                }

                            return xn_t4147;

                        }
                        {
                        xn_root_restore(xn_t4144);
                        }

                }
        }
    #line 1983 "impl/lib/b2/xparser.x"
    j = (j + 1);
        {
        xn_root_restore(xn_t4137);
        }

    xn_gc_safepoint();
    }
#line 1985 "impl/lib/b2/xparser.x"
int xn_t4148 = 0;
    {
xn_root_restore(xn_t4133);
    }

return xn_t4148;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static int xn_Cls_Parser_lambdaAhead(xn_Cls_Parser *self) {
size_t xn_t4149 = xn_root_mark();
xn_root_add(self);
#line 1989 "impl/lib/b2/xparser.x"
    if (((!(xn_Cls_Parser_at(self, 10))))) {
        size_t xn_t4150 = xn_root_mark();
        #line 1989 "impl/lib/b2/xparser.x"
        int xn_t4151 = 0;
            {
        xn_root_restore(xn_t4150);
            }
            {
        xn_root_restore(xn_t4149);
            }

        return xn_t4151;

    }
#line 1990 "impl/lib/b2/xparser.x"
int64_t dep = 1;
#line 1991 "impl/lib/b2/xparser.x"
int64_t j = (self->i + 1);
#line 1992 "impl/lib/b2/xparser.x"
    while ((((j < ((int64_t)self->toks->len))) && ((dep > 0)))) {
    size_t xn_t4152 = xn_root_mark();
    #line 1993 "impl/lib/b2/xparser.x"
    xn_Cls_Tok * x = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(x);
    xn_root_add(x);
    xn_root_add(x);
    xn_gc_safepoint();
    #line 1994 "impl/lib/b2/xparser.x"
        if (((x->kind == 10))) {
            size_t xn_t4153 = xn_root_mark();
            #line 1994 "impl/lib/b2/xparser.x"
            dep = (dep + 1);
                {
                xn_root_restore(xn_t4153);
                }

        } else {
                if (((x->kind == 11))) {
                    size_t xn_t4155 = xn_root_mark();
                    #line 1995 "impl/lib/b2/xparser.x"
                    dep = (dep - 1);
                        {
                        xn_root_restore(xn_t4155);
                        }

                }
        }
    #line 1996 "impl/lib/b2/xparser.x"
    j = (j + 1);
        {
        xn_root_restore(xn_t4152);
        }

    xn_gc_safepoint();
    }
#line 1998 "impl/lib/b2/xparser.x"
xn_Cls_Tok * xn_t4156 = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(xn_t4156);
xn_root_add(xn_t4156);
xn_Cls_Tok * xn_t4157 = xn_arr_o_Tok_get(self->toks, j);
xn_root_add(xn_t4157);
xn_root_add(xn_t4157);
rt_string *xn_t4158 = rt_retain(xn_t4157->text);
xn_root_add(xn_t4158);
xn_root_add(xn_t4158);
rt_string *xn_t4159 = rt_string_from_c("->");
xn_root_add(xn_t4159);
xn_root_add(xn_t4159);
int xn_t4160 = (((j < ((int64_t)self->toks->len)) && (xn_t4156->kind == 9)) && xn_str_eq(xn_t4158, xn_t4159));
    {
xn_root_restore(xn_t4149);
    }

return xn_t4160;
    return (int)0; /* sema 保证不可达（函数体全路径 return） */
}

static rt_string * xn_Cls_Parser_parseSubExpr(xn_Cls_Parser *self, rt_string * xn_p_text) {
size_t xn_t4161 = xn_root_mark();
xn_root_add(self);
xn_root_add(xn_p_text);
#line 2002 "impl/lib/b2/xparser.x"
rt_string *xn_t4162 = rt_retain(xn_p_text);
xn_root_add(xn_t4162);
xn_Cls_Lexer * sl = xn_Cls_Lexer_new(xn_t4162);
xn_root_add(sl);
xn_root_add(sl);
xn_gc_safepoint();
#line 2003 "impl/lib/b2/xparser.x"
xn_arr_o_Tok *xn_t4163 = xn_arr_o_Tok_new(0);
xn_root_add(xn_t4163);
xn_arr_o_Tok * ts = xn_t4163;
xn_root_add(ts);
xn_root_add(ts);
xn_gc_safepoint();
#line 2004 "impl/lib/b2/xparser.x"
int go = 1;
#line 2005 "impl/lib/b2/xparser.x"
    while ((go)) {
    size_t xn_t4164 = xn_root_mark();
    #line 2006 "impl/lib/b2/xparser.x"
    xn_Cls_Tok * x = xn_Cls_Lexer_next(sl);
xn_root_add(x);
    xn_root_add(x);
    xn_root_add(x);
    xn_gc_safepoint();
    #line 2007 "impl/lib/b2/xparser.x"
    xn_arr_o_Tok_push(ts, x);
    #line 2008 "impl/lib/b2/xparser.x"
        if (((x->kind == 0))) {
            size_t xn_t4165 = xn_root_mark();
            #line 2008 "impl/lib/b2/xparser.x"
            go = 0;
                {
                xn_root_restore(xn_t4165);
                }

        }
        {
        xn_root_restore(xn_t4164);
        }

    xn_gc_safepoint();
    }
#line 2010 "impl/lib/b2/xparser.x"
xn_Cls_Parser * sp = xn_Cls_Parser_new(ts);
xn_root_add(sp);
xn_root_add(sp);
xn_gc_safepoint();
#line 2011 "impl/lib/b2/xparser.x"
xn_Cls_E * xn_t4166 = xn_Cls_Parser_parseExpr(sp);
xn_root_add(xn_t4166);
rt_string *xn_t4167 = rt_retain(xn_t4166->d);
xn_root_add(xn_t4167);
xn_root_add(xn_t4167);
    {
xn_root_restore(xn_t4161);
    }

return xn_t4167;
    return (rt_string *)0; /* sema 保证不可达（函数体全路径 return） */
}

static xn_Cls_E * xn_Cls_Parser_parsePrimary(xn_Cls_Parser *self) {
size_t xn_t4168 = xn_root_mark();
xn_root_add(self);
#line 2015 "impl/lib/b2/xparser.x"
xn_Cls_Tok * t = xn_Cls_Parser_cur(self);
xn_root_add(t);
xn_root_add(t);
xn_gc_safepoint();
#line 2016 "impl/lib/b2/xparser.x"
    if (((t->kind == 2))) {
        size_t xn_t4169 = xn_root_mark();
        #line 2017 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 2018 "impl/lib/b2/xparser.x"
        rt_string *xn_t4170 = rt_retain(t->text);
xn_root_add(xn_t4170);
        xn_root_add(xn_t4170);
        rt_string *xn_t4171 = rt_string_from_c("true");
xn_root_add(xn_t4171);
        xn_root_add(xn_t4171);
        rt_string *xn_t4172 = rt_retain(t->text);
xn_root_add(xn_t4172);
        xn_root_add(xn_t4172);
        rt_string *xn_t4173 = rt_string_from_c("false");
xn_root_add(xn_t4173);
        xn_root_add(xn_t4173);
            if (((xn_str_eq(xn_t4170, xn_t4171)) || (xn_str_eq(xn_t4172, xn_t4173)))) {
                size_t xn_t4174 = xn_root_mark();
                #line 2019 "impl/lib/b2/xparser.x"
                rt_string *xn_t4175 = rt_string_from_c("(BoolLit ");
xn_root_add(xn_t4175);
        xn_root_add(xn_t4175);
                xn_root_add(xn_t4175);
                xn_root_add(xn_t4175);
                rt_string *xn_t4176 = xn_P(t->line, t->col);
xn_root_add(xn_t4176);
        xn_root_add(xn_t4176);
                xn_root_add(xn_t4176);
                xn_root_add(xn_t4176);
                rt_string *xn_t4177 = xn_concat(xn_t4175, xn_t4176);
xn_root_add(xn_t4177);
        xn_root_add(xn_t4177);
                xn_root_add(xn_t4177);
                xn_root_add(xn_t4177);
                rt_string *xn_t4178 = rt_string_from_c(" (V ");
xn_root_add(xn_t4178);
        xn_root_add(xn_t4178);
                xn_root_add(xn_t4178);
                xn_root_add(xn_t4178);
                rt_string *xn_t4179 = xn_concat(xn_t4177, xn_t4178);
xn_root_add(xn_t4179);
        xn_root_add(xn_t4179);
                xn_root_add(xn_t4179);
                xn_root_add(xn_t4179);
                rt_string *xn_t4180 = rt_retain(t->text);
xn_root_add(xn_t4180);
        xn_root_add(xn_t4180);
                xn_root_add(xn_t4180);
                xn_root_add(xn_t4180);
                rt_string *xn_t4181 = rt_string_from_c("true");
xn_root_add(xn_t4181);
        xn_root_add(xn_t4181);
                xn_root_add(xn_t4181);
                xn_root_add(xn_t4181);
                rt_string *xn_t4182 = xn_B(xn_str_eq(xn_t4180, xn_t4181));
xn_root_add(xn_t4182);
        xn_root_add(xn_t4182);
                xn_root_add(xn_t4182);
                xn_root_add(xn_t4182);
                rt_string *xn_t4183 = xn_concat(xn_t4179, xn_t4182);
xn_root_add(xn_t4183);
        xn_root_add(xn_t4183);
                xn_root_add(xn_t4183);
                xn_root_add(xn_t4183);
                rt_string *xn_t4184 = rt_string_from_c("))");
xn_root_add(xn_t4184);
        xn_root_add(xn_t4184);
                xn_root_add(xn_t4184);
                xn_root_add(xn_t4184);
                rt_string *xn_t4185 = xn_concat(xn_t4183, xn_t4184);
xn_root_add(xn_t4185);
        xn_root_add(xn_t4185);
                xn_root_add(xn_t4185);
                xn_root_add(xn_t4185);
                    {
                xn_root_restore(xn_t4174);
                    }
                    {
                xn_root_restore(xn_t4169);
                    }
                    {
                xn_root_restore(xn_t4168);
                    }

                return xn_Cls_Parser_mk(self, xn_t4185, t->line, t->col);

            }
        #line 2021 "impl/lib/b2/xparser.x"
        rt_string *xn_t4186 = rt_retain(t->text);
xn_root_add(xn_t4186);
        xn_root_add(xn_t4186);
        rt_string *xn_t4187 = rt_string_from_c("null");
xn_root_add(xn_t4187);
        xn_root_add(xn_t4187);
            if ((xn_str_eq(xn_t4186, xn_t4187))) {
                size_t xn_t4188 = xn_root_mark();
                #line 2022 "impl/lib/b2/xparser.x"
                rt_string *xn_t4189 = rt_string_from_c("(NullLit ");
xn_root_add(xn_t4189);
        xn_root_add(xn_t4189);
                xn_root_add(xn_t4189);
                xn_root_add(xn_t4189);
                rt_string *xn_t4190 = xn_P(t->line, t->col);
xn_root_add(xn_t4190);
        xn_root_add(xn_t4190);
                xn_root_add(xn_t4190);
                xn_root_add(xn_t4190);
                rt_string *xn_t4191 = xn_concat(xn_t4189, xn_t4190);
xn_root_add(xn_t4191);
        xn_root_add(xn_t4191);
                xn_root_add(xn_t4191);
                xn_root_add(xn_t4191);
                rt_string *xn_t4192 = rt_string_from_c(")");
xn_root_add(xn_t4192);
        xn_root_add(xn_t4192);
                xn_root_add(xn_t4192);
                xn_root_add(xn_t4192);
                rt_string *xn_t4193 = xn_concat(xn_t4191, xn_t4192);
xn_root_add(xn_t4193);
        xn_root_add(xn_t4193);
                xn_root_add(xn_t4193);
                xn_root_add(xn_t4193);
                    {
                xn_root_restore(xn_t4188);
                    }
                    {
                xn_root_restore(xn_t4169);
                    }
                    {
                xn_root_restore(xn_t4168);
                    }

                return xn_Cls_Parser_mk(self, xn_t4193, t->line, t->col);

            }
        #line 2024 "impl/lib/b2/xparser.x"
        rt_string *xn_t4194 = rt_string_from_c("(IdentExpr ");
xn_root_add(xn_t4194);
        xn_root_add(xn_t4194);
        xn_root_add(xn_t4194);
        rt_string *xn_t4195 = xn_P(t->line, t->col);
xn_root_add(xn_t4195);
        xn_root_add(xn_t4195);
        xn_root_add(xn_t4195);
        rt_string *xn_t4196 = xn_concat(xn_t4194, xn_t4195);
xn_root_add(xn_t4196);
        xn_root_add(xn_t4196);
        xn_root_add(xn_t4196);
        rt_string *xn_t4197 = rt_string_from_c(" (Name ");
xn_root_add(xn_t4197);
        xn_root_add(xn_t4197);
        xn_root_add(xn_t4197);
        rt_string *xn_t4198 = xn_concat(xn_t4196, xn_t4197);
xn_root_add(xn_t4198);
        xn_root_add(xn_t4198);
        xn_root_add(xn_t4198);
        rt_string *xn_t4199 = rt_retain(t->text);
xn_root_add(xn_t4199);
        xn_root_add(xn_t4199);
        xn_root_add(xn_t4199);
        rt_string *xn_t4200 = xn_q(xn_t4199);
xn_root_add(xn_t4200);
        xn_root_add(xn_t4200);
        xn_root_add(xn_t4200);
        rt_string *xn_t4201 = xn_concat(xn_t4198, xn_t4200);
xn_root_add(xn_t4201);
        xn_root_add(xn_t4201);
        xn_root_add(xn_t4201);
        rt_string *xn_t4202 = rt_string_from_c("))");
xn_root_add(xn_t4202);
        xn_root_add(xn_t4202);
        xn_root_add(xn_t4202);
        rt_string *xn_t4203 = xn_concat(xn_t4201, xn_t4202);
xn_root_add(xn_t4203);
        xn_root_add(xn_t4203);
        xn_root_add(xn_t4203);
            {
        xn_root_restore(xn_t4169);
            }
            {
        xn_root_restore(xn_t4168);
            }

        return xn_Cls_Parser_mk(self, xn_t4203, t->line, t->col);

    }
#line 2026 "impl/lib/b2/xparser.x"
    if (((t->kind == 5))) {
        size_t xn_t4204 = xn_root_mark();
        #line 2027 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 2028 "impl/lib/b2/xparser.x"
        rt_string *xn_t4205 = rt_string_from_c("(IntLitExpr ");
xn_root_add(xn_t4205);
        xn_root_add(xn_t4205);
        xn_root_add(xn_t4205);
        rt_string *xn_t4206 = xn_P(t->line, t->col);
xn_root_add(xn_t4206);
        xn_root_add(xn_t4206);
        xn_root_add(xn_t4206);
        rt_string *xn_t4207 = xn_concat(xn_t4205, xn_t4206);
xn_root_add(xn_t4207);
        xn_root_add(xn_t4207);
        xn_root_add(xn_t4207);
        rt_string *xn_t4208 = rt_string_from_c(" (Text ");
xn_root_add(xn_t4208);
        xn_root_add(xn_t4208);
        xn_root_add(xn_t4208);
        rt_string *xn_t4209 = xn_concat(xn_t4207, xn_t4208);
xn_root_add(xn_t4209);
        xn_root_add(xn_t4209);
        xn_root_add(xn_t4209);
        rt_string *xn_t4210 = rt_retain(t->text);
xn_root_add(xn_t4210);
        xn_root_add(xn_t4210);
        xn_root_add(xn_t4210);
        rt_string *xn_t4211 = xn_q(xn_t4210);
xn_root_add(xn_t4211);
        xn_root_add(xn_t4211);
        xn_root_add(xn_t4211);
        rt_string *xn_t4212 = xn_concat(xn_t4209, xn_t4211);
xn_root_add(xn_t4212);
        xn_root_add(xn_t4212);
        xn_root_add(xn_t4212);
        rt_string *xn_t4213 = rt_string_from_c(") (Base ");
xn_root_add(xn_t4213);
        xn_root_add(xn_t4213);
        xn_root_add(xn_t4213);
        rt_string *xn_t4214 = xn_concat(xn_t4212, xn_t4213);
xn_root_add(xn_t4214);
        xn_root_add(xn_t4214);
        xn_root_add(xn_t4214);
        rt_string *xn_t4215 = xn_str_int(t->base);
xn_root_add(xn_t4215);
        xn_root_add(xn_t4215);
        xn_root_add(xn_t4215);
        rt_string *xn_t4216 = xn_concat(xn_t4214, xn_t4215);
xn_root_add(xn_t4216);
        xn_root_add(xn_t4216);
        xn_root_add(xn_t4216);
        rt_string *xn_t4217 = rt_string_from_c(") (Suffix ");
xn_root_add(xn_t4217);
        xn_root_add(xn_t4217);
        xn_root_add(xn_t4217);
        rt_string *xn_t4218 = xn_concat(xn_t4216, xn_t4217);
xn_root_add(xn_t4218);
        xn_root_add(xn_t4218);
        xn_root_add(xn_t4218);
        rt_string *xn_t4219 = rt_retain(t->suffix);
xn_root_add(xn_t4219);
        xn_root_add(xn_t4219);
        xn_root_add(xn_t4219);
        rt_string *xn_t4220 = xn_q(xn_t4219);
xn_root_add(xn_t4220);
        xn_root_add(xn_t4220);
        xn_root_add(xn_t4220);
        rt_string *xn_t4221 = xn_concat(xn_t4218, xn_t4220);
xn_root_add(xn_t4221);
        xn_root_add(xn_t4221);
        xn_root_add(xn_t4221);
        rt_string *xn_t4222 = rt_string_from_c("))");
xn_root_add(xn_t4222);
        xn_root_add(xn_t4222);
        xn_root_add(xn_t4222);
        rt_string *xn_t4223 = xn_concat(xn_t4221, xn_t4222);
xn_root_add(xn_t4223);
        xn_root_add(xn_t4223);
        xn_root_add(xn_t4223);
            {
        xn_root_restore(xn_t4204);
            }
            {
        xn_root_restore(xn_t4168);
            }

        return xn_Cls_Parser_mk(self, xn_t4223, t->line, t->col);

    }
#line 2030 "impl/lib/b2/xparser.x"
    if (((t->kind == 6))) {
        size_t xn_t4224 = xn_root_mark();
        #line 2031 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 2032 "impl/lib/b2/xparser.x"
        rt_string *xn_t4225 = rt_string_from_c("(FloatLitExpr ");
xn_root_add(xn_t4225);
        xn_root_add(xn_t4225);
        xn_root_add(xn_t4225);
        rt_string *xn_t4226 = xn_P(t->line, t->col);
xn_root_add(xn_t4226);
        xn_root_add(xn_t4226);
        xn_root_add(xn_t4226);
        rt_string *xn_t4227 = xn_concat(xn_t4225, xn_t4226);
xn_root_add(xn_t4227);
        xn_root_add(xn_t4227);
        xn_root_add(xn_t4227);
        rt_string *xn_t4228 = rt_string_from_c(" (Text ");
xn_root_add(xn_t4228);
        xn_root_add(xn_t4228);
        xn_root_add(xn_t4228);
        rt_string *xn_t4229 = xn_concat(xn_t4227, xn_t4228);
xn_root_add(xn_t4229);
        xn_root_add(xn_t4229);
        xn_root_add(xn_t4229);
        rt_string *xn_t4230 = rt_retain(t->text);
xn_root_add(xn_t4230);
        xn_root_add(xn_t4230);
        xn_root_add(xn_t4230);
        rt_string *xn_t4231 = xn_q(xn_t4230);
xn_root_add(xn_t4231);
        xn_root_add(xn_t4231);
        xn_root_add(xn_t4231);
        rt_string *xn_t4232 = xn_concat(xn_t4229, xn_t4231);
xn_root_add(xn_t4232);
        xn_root_add(xn_t4232);
        xn_root_add(xn_t4232);
        rt_string *xn_t4233 = rt_string_from_c(") (HasSuffixF ");
xn_root_add(xn_t4233);
        xn_root_add(xn_t4233);
        xn_root_add(xn_t4233);
        rt_string *xn_t4234 = xn_concat(xn_t4232, xn_t4233);
xn_root_add(xn_t4234);
        xn_root_add(xn_t4234);
        xn_root_add(xn_t4234);
        rt_string *xn_t4235 = xn_B(((int)(t->hasSuffixF)));
xn_root_add(xn_t4235);
        xn_root_add(xn_t4235);
        xn_root_add(xn_t4235);
        rt_string *xn_t4236 = xn_concat(xn_t4234, xn_t4235);
xn_root_add(xn_t4236);
        xn_root_add(xn_t4236);
        xn_root_add(xn_t4236);
        rt_string *xn_t4237 = rt_string_from_c("))");
xn_root_add(xn_t4237);
        xn_root_add(xn_t4237);
        xn_root_add(xn_t4237);
        rt_string *xn_t4238 = xn_concat(xn_t4236, xn_t4237);
xn_root_add(xn_t4238);
        xn_root_add(xn_t4238);
        xn_root_add(xn_t4238);
            {
        xn_root_restore(xn_t4224);
            }
            {
        xn_root_restore(xn_t4168);
            }

        return xn_Cls_Parser_mk(self, xn_t4238, t->line, t->col);

    }
#line 2034 "impl/lib/b2/xparser.x"
    if (((t->kind == 7))) {
        size_t xn_t4239 = xn_root_mark();
        #line 2035 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 2036 "impl/lib/b2/xparser.x"
        rt_string *xn_t4240 = rt_string_from_c("(CharLitExpr ");
xn_root_add(xn_t4240);
        xn_root_add(xn_t4240);
        xn_root_add(xn_t4240);
        rt_string *xn_t4241 = xn_P(t->line, t->col);
xn_root_add(xn_t4241);
        xn_root_add(xn_t4241);
        xn_root_add(xn_t4241);
        rt_string *xn_t4242 = xn_concat(xn_t4240, xn_t4241);
xn_root_add(xn_t4242);
        xn_root_add(xn_t4242);
        xn_root_add(xn_t4242);
        rt_string *xn_t4243 = rt_string_from_c(" (Rune ");
xn_root_add(xn_t4243);
        xn_root_add(xn_t4243);
        xn_root_add(xn_t4243);
        rt_string *xn_t4244 = xn_concat(xn_t4242, xn_t4243);
xn_root_add(xn_t4244);
        xn_root_add(xn_t4244);
        xn_root_add(xn_t4244);
        rt_string *xn_t4245 = xn_str_int(t->ch);
xn_root_add(xn_t4245);
        xn_root_add(xn_t4245);
        xn_root_add(xn_t4245);
        rt_string *xn_t4246 = xn_concat(xn_t4244, xn_t4245);
xn_root_add(xn_t4246);
        xn_root_add(xn_t4246);
        xn_root_add(xn_t4246);
        rt_string *xn_t4247 = rt_string_from_c("))");
xn_root_add(xn_t4247);
        xn_root_add(xn_t4247);
        xn_root_add(xn_t4247);
        rt_string *xn_t4248 = xn_concat(xn_t4246, xn_t4247);
xn_root_add(xn_t4248);
        xn_root_add(xn_t4248);
        xn_root_add(xn_t4248);
            {
        xn_root_restore(xn_t4239);
            }
            {
        xn_root_restore(xn_t4168);
            }

        return xn_Cls_Parser_mk(self, xn_t4248, t->line, t->col);

    }
#line 2038 "impl/lib/b2/xparser.x"
    if (((t->kind == 8))) {
        size_t xn_t4249 = xn_root_mark();
        #line 2039 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 2040 "impl/lib/b2/xparser.x"
        xn_arr_s *xn_t4250 = xn_arr_s_new(0);
xn_root_add(xn_t4250);
        xn_root_add(xn_t4250);
        xn_arr_s * parts = xn_t4250;
xn_root_add(parts);
        xn_root_add(parts);
        xn_root_add(parts);
        xn_gc_safepoint();
        #line 2041 "impl/lib/b2/xparser.x"
            if (((((int64_t)t->interps->len) == 0))) {
                size_t xn_t4251 = xn_root_mark();
                #line 2042 "impl/lib/b2/xparser.x"
                rt_string *xn_t4252 = rt_string_from_c("(StrPart (Text ");
xn_root_add(xn_t4252);
        xn_root_add(xn_t4252);
                xn_root_add(xn_t4252);
                rt_string *xn_t4253 = rt_retain(t->value);
xn_root_add(xn_t4253);
        xn_root_add(xn_t4253);
                xn_root_add(xn_t4253);
                rt_string *xn_t4254 = xn_q(xn_t4253);
xn_root_add(xn_t4254);
        xn_root_add(xn_t4254);
                xn_root_add(xn_t4254);
                rt_string *xn_t4255 = xn_concat(xn_t4252, xn_t4254);
xn_root_add(xn_t4255);
        xn_root_add(xn_t4255);
                xn_root_add(xn_t4255);
                rt_string *xn_t4256 = rt_string_from_c(") (Expr (nil)))");
xn_root_add(xn_t4256);
        xn_root_add(xn_t4256);
                xn_root_add(xn_t4256);
                rt_string *xn_t4257 = xn_concat(xn_t4255, xn_t4256);
xn_root_add(xn_t4257);
        xn_root_add(xn_t4257);
                xn_root_add(xn_t4257);
                xn_arr_s_push(parts, xn_t4257);
                    {
                    xn_root_restore(xn_t4251);
                    }

            } else {
                size_t xn_t4258 = xn_root_mark();
                #line 2044 "impl/lib/b2/xparser.x"
                int64_t j = 0;
                #line 2045 "impl/lib/b2/xparser.x"
                    while (((j < ((int64_t)t->interps->len)))) {
                    size_t xn_t4259 = xn_root_mark();
                    #line 2046 "impl/lib/b2/xparser.x"
                    rt_string *xn_t4260 = rt_retain(xn_arr_s_get(t->segs, j));
xn_root_add(xn_t4260);
        xn_root_add(xn_t4260);
                xn_root_add(xn_t4260);
                    xn_root_add(xn_t4260);
                    rt_string *xn_t4261 = rt_string_from_c("");
xn_root_add(xn_t4261);
        xn_root_add(xn_t4261);
                xn_root_add(xn_t4261);
                    xn_root_add(xn_t4261);
                        if (((!(xn_str_eq(xn_t4260, xn_t4261))))) {
                            size_t xn_t4262 = xn_root_mark();
                            #line 2047 "impl/lib/b2/xparser.x"
                            rt_string *xn_t4263 = rt_string_from_c("(StrPart (Text ");
xn_root_add(xn_t4263);
        xn_root_add(xn_t4263);
                xn_root_add(xn_t4263);
                    xn_root_add(xn_t4263);
                            xn_root_add(xn_t4263);
                            rt_string *xn_t4264 = rt_retain(xn_arr_s_get(t->segs, j));
xn_root_add(xn_t4264);
        xn_root_add(xn_t4264);
                xn_root_add(xn_t4264);
                    xn_root_add(xn_t4264);
                            xn_root_add(xn_t4264);
                            rt_string *xn_t4265 = xn_q(xn_t4264);
xn_root_add(xn_t4265);
        xn_root_add(xn_t4265);
                xn_root_add(xn_t4265);
                    xn_root_add(xn_t4265);
                            xn_root_add(xn_t4265);
                            rt_string *xn_t4266 = xn_concat(xn_t4263, xn_t4265);
xn_root_add(xn_t4266);
        xn_root_add(xn_t4266);
                xn_root_add(xn_t4266);
                    xn_root_add(xn_t4266);
                            xn_root_add(xn_t4266);
                            rt_string *xn_t4267 = rt_string_from_c(") (Expr (nil)))");
xn_root_add(xn_t4267);
        xn_root_add(xn_t4267);
                xn_root_add(xn_t4267);
                    xn_root_add(xn_t4267);
                            xn_root_add(xn_t4267);
                            rt_string *xn_t4268 = xn_concat(xn_t4266, xn_t4267);
xn_root_add(xn_t4268);
        xn_root_add(xn_t4268);
                xn_root_add(xn_t4268);
                    xn_root_add(xn_t4268);
                            xn_root_add(xn_t4268);
                            xn_arr_s_push(parts, xn_t4268);
                                {
                                xn_root_restore(xn_t4262);
                                }

                        }
                    #line 2049 "impl/lib/b2/xparser.x"
                    rt_string *xn_t4269 = rt_string_from_c("(StrPart (Text \"\") (Expr ");
xn_root_add(xn_t4269);
        xn_root_add(xn_t4269);
                xn_root_add(xn_t4269);
                    xn_root_add(xn_t4269);
                    rt_string *xn_t4270 = rt_retain(xn_arr_s_get(t->interps, j));
xn_root_add(xn_t4270);
        xn_root_add(xn_t4270);
                xn_root_add(xn_t4270);
                    xn_root_add(xn_t4270);
                    rt_string *xn_t4271 = xn_Cls_Parser_parseSubExpr(self, xn_t4270);
xn_root_add(xn_t4271);
        xn_root_add(xn_t4271);
                xn_root_add(xn_t4271);
                    xn_root_add(xn_t4271);
                    rt_string *xn_t4272 = xn_concat(xn_t4269, xn_t4271);
xn_root_add(xn_t4272);
        xn_root_add(xn_t4272);
                xn_root_add(xn_t4272);
                    xn_root_add(xn_t4272);
                    rt_string *xn_t4273 = rt_string_from_c("))");
xn_root_add(xn_t4273);
        xn_root_add(xn_t4273);
                xn_root_add(xn_t4273);
                    xn_root_add(xn_t4273);
                    rt_string *xn_t4274 = xn_concat(xn_t4272, xn_t4273);
xn_root_add(xn_t4274);
        xn_root_add(xn_t4274);
                xn_root_add(xn_t4274);
                    xn_root_add(xn_t4274);
                    xn_arr_s_push(parts, xn_t4274);
                    #line 2050 "impl/lib/b2/xparser.x"
                    j = (j + 1);
                        {
                        xn_root_restore(xn_t4259);
                        }

                    xn_gc_safepoint();
                    }
                #line 2052 "impl/lib/b2/xparser.x"
                rt_string *tail = rt_retain(xn_arr_s_get(t->segs, (((int64_t)t->segs->len) - 1)));
xn_root_add(tail);
        xn_root_add(tail);
                xn_root_add(tail);
                xn_root_add(tail);
                xn_gc_safepoint();
                #line 2053 "impl/lib/b2/xparser.x"
                rt_string *xn_t4276 = rt_retain(tail);
xn_root_add(xn_t4276);
        xn_root_add(xn_t4276);
                xn_root_add(xn_t4276);
                rt_string *xn_t4277 = rt_string_from_c("");
xn_root_add(xn_t4277);
        xn_root_add(xn_t4277);
                xn_root_add(xn_t4277);
                    if (((!(xn_str_eq(xn_t4276, xn_t4277))))) {
                        size_t xn_t4278 = xn_root_mark();
                        #line 2054 "impl/lib/b2/xparser.x"
                        rt_string *xn_t4279 = rt_string_from_c("(StrPart (Text ");
xn_root_add(xn_t4279);
        xn_root_add(xn_t4279);
                xn_root_add(xn_t4279);
                        xn_root_add(xn_t4279);
                        rt_string *xn_t4280 = rt_retain(tail);
xn_root_add(xn_t4280);
        xn_root_add(xn_t4280);
                xn_root_add(xn_t4280);
                        xn_root_add(xn_t4280);
                        rt_string *xn_t4281 = xn_q(xn_t4280);
xn_root_add(xn_t4281);
        xn_root_add(xn_t4281);
                xn_root_add(xn_t4281);
                        xn_root_add(xn_t4281);
                        rt_string *xn_t4282 = xn_concat(xn_t4279, xn_t4281);
xn_root_add(xn_t4282);
        xn_root_add(xn_t4282);
                xn_root_add(xn_t4282);
                        xn_root_add(xn_t4282);
                        rt_string *xn_t4283 = rt_string_from_c(") (Expr (nil)))");
xn_root_add(xn_t4283);
        xn_root_add(xn_t4283);
                xn_root_add(xn_t4283);
                        xn_root_add(xn_t4283);
                        rt_string *xn_t4284 = xn_concat(xn_t4282, xn_t4283);
xn_root_add(xn_t4284);
        xn_root_add(xn_t4284);
                xn_root_add(xn_t4284);
                        xn_root_add(xn_t4284);
                        xn_arr_s_push(parts, xn_t4284);
                            {
                            xn_root_restore(xn_t4278);
                            }

                    }
                    {
                    rt_release(tail);
                    }
                    {
                    xn_root_restore(xn_t4258);
                    }

            }
        #line 2057 "impl/lib/b2/xparser.x"
        rt_string *xn_t4285 = rt_string_from_c("(StrLitExpr ");
xn_root_add(xn_t4285);
        xn_root_add(xn_t4285);
        xn_root_add(xn_t4285);
        rt_string *xn_t4286 = xn_P(t->line, t->col);
xn_root_add(xn_t4286);
        xn_root_add(xn_t4286);
        xn_root_add(xn_t4286);
        rt_string *xn_t4287 = xn_concat(xn_t4285, xn_t4286);
xn_root_add(xn_t4287);
        xn_root_add(xn_t4287);
        xn_root_add(xn_t4287);
        rt_string *xn_t4288 = rt_string_from_c(" (Kind ");
xn_root_add(xn_t4288);
        xn_root_add(xn_t4288);
        xn_root_add(xn_t4288);
        rt_string *xn_t4289 = xn_concat(xn_t4287, xn_t4288);
xn_root_add(xn_t4289);
        xn_root_add(xn_t4289);
        xn_root_add(xn_t4289);
        rt_string *xn_t4290 = xn_str_int(t->str);
xn_root_add(xn_t4290);
        xn_root_add(xn_t4290);
        xn_root_add(xn_t4290);
        rt_string *xn_t4291 = xn_concat(xn_t4289, xn_t4290);
xn_root_add(xn_t4291);
        xn_root_add(xn_t4291);
        xn_root_add(xn_t4291);
        rt_string *xn_t4292 = rt_string_from_c(") (Parts ");
xn_root_add(xn_t4292);
        xn_root_add(xn_t4292);
        xn_root_add(xn_t4292);
        rt_string *xn_t4293 = xn_concat(xn_t4291, xn_t4292);
xn_root_add(xn_t4293);
        xn_root_add(xn_t4293);
        xn_root_add(xn_t4293);
        rt_string *xn_t4294 = xn_SL(parts);
xn_root_add(xn_t4294);
        xn_root_add(xn_t4294);
        xn_root_add(xn_t4294);
        rt_string *xn_t4295 = xn_concat(xn_t4293, xn_t4294);
xn_root_add(xn_t4295);
        xn_root_add(xn_t4295);
        xn_root_add(xn_t4295);
        rt_string *xn_t4296 = rt_string_from_c("))");
xn_root_add(xn_t4296);
        xn_root_add(xn_t4296);
        xn_root_add(xn_t4296);
        rt_string *xn_t4297 = xn_concat(xn_t4295, xn_t4296);
xn_root_add(xn_t4297);
        xn_root_add(xn_t4297);
        xn_root_add(xn_t4297);
            {
        xn_root_restore(xn_t4249);
            }
            {
        xn_root_restore(xn_t4168);
            }

        return xn_Cls_Parser_mk(self, xn_t4297, t->line, t->col);

    }
#line 2059 "impl/lib/b2/xparser.x"
    if ((((t->kind == 10)) && (xn_Cls_Parser_lambdaAhead(self)))) {
        size_t xn_t4298 = xn_root_mark();
        #line 2060 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 2061 "impl/lib/b2/xparser.x"
        xn_arr_s *xn_t4299 = xn_arr_s_new(0);
xn_root_add(xn_t4299);
        xn_root_add(xn_t4299);
        xn_arr_s * lps = xn_t4299;
xn_root_add(lps);
        xn_root_add(lps);
        xn_root_add(lps);
        xn_gc_safepoint();
        #line 2062 "impl/lib/b2/xparser.x"
            while ((((!(xn_Cls_Parser_at(self, 11)))) && ((!(xn_Cls_Parser_eof(self)))))) {
            size_t xn_t4300 = xn_root_mark();
            #line 2063 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 16))) {
                    size_t xn_t4301 = xn_root_mark();
                    #line 2063 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 2063 "impl/lib/b2/xparser.x"
                    xn_root_restore(xn_t4301);
                    xn_root_restore(xn_t4300);
                    continue;
                        {
                        xn_root_restore(xn_t4301);
                        }

                }
            #line 2064 "impl/lib/b2/xparser.x"
            xn_Cls_Tok * lp = xn_Cls_Parser_cur(self);
xn_root_add(lp);
        xn_root_add(lp);
            xn_root_add(lp);
            xn_root_add(lp);
            xn_gc_safepoint();
            #line 2065 "impl/lib/b2/xparser.x"
            int lf = 0;
            #line 2066 "impl/lib/b2/xparser.x"
            rt_string *xn_t4302 = rt_string_from_c("final");
xn_root_add(xn_t4302);
        xn_root_add(xn_t4302);
            xn_root_add(xn_t4302);
                if ((xn_Cls_Parser_atKw(self, xn_t4302))) {
                    size_t xn_t4303 = xn_root_mark();
                    #line 2066 "impl/lib/b2/xparser.x"
                    lf = 1;
                    #line 2066 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                        {
                        xn_root_restore(xn_t4303);
                        }

                }
            #line 2067 "impl/lib/b2/xparser.x"
            rt_string *lt = xn_Cls_Parser_parseType(self);
xn_root_add(lt);
        xn_root_add(lt);
            xn_root_add(lt);
            xn_root_add(lt);
            xn_gc_safepoint();
            #line 2068 "impl/lib/b2/xparser.x"
            rt_string *ln = rt_string_from_c("");
xn_root_add(ln);
        xn_root_add(ln);
            xn_root_add(ln);
            xn_root_add(ln);
            xn_gc_safepoint();
            #line 2069 "impl/lib/b2/xparser.x"
                if ((xn_Cls_Parser_at(self, 2))) {
                    size_t xn_t4306 = xn_root_mark();
                    #line 2069 "impl/lib/b2/xparser.x"
                    xn_Cls_Tok * xn_t4307 = xn_Cls_Parser_next(self);
xn_root_add(xn_t4307);
        xn_root_add(xn_t4307);
            xn_root_add(xn_t4307);
                    xn_root_add(xn_t4307);
                    rt_string *xn_t4308 = rt_retain(xn_t4307->text);
xn_root_add(xn_t4308);
        xn_root_add(xn_t4308);
            xn_root_add(xn_t4308);
                    xn_root_add(xn_t4308);
                    xn_root_release(ln);
                    rt_release(ln);
                    ln = xn_t4308;
                    xn_root_hold(ln);
                    xn_gc_safepoint();
                        {
                        xn_root_restore(xn_t4306);
                        }

                }
            #line 2070 "impl/lib/b2/xparser.x"
            rt_string *xn_t4309 = rt_string_from_c("(LambdaParam ");
xn_root_add(xn_t4309);
        xn_root_add(xn_t4309);
            xn_root_add(xn_t4309);
            rt_string *xn_t4310 = xn_P(lp->line, lp->col);
xn_root_add(xn_t4310);
        xn_root_add(xn_t4310);
            xn_root_add(xn_t4310);
            rt_string *xn_t4311 = xn_concat(xn_t4309, xn_t4310);
xn_root_add(xn_t4311);
        xn_root_add(xn_t4311);
            xn_root_add(xn_t4311);
            rt_string *xn_t4312 = rt_string_from_c(" (Type ");
xn_root_add(xn_t4312);
        xn_root_add(xn_t4312);
            xn_root_add(xn_t4312);
            rt_string *xn_t4313 = xn_concat(xn_t4311, xn_t4312);
xn_root_add(xn_t4313);
        xn_root_add(xn_t4313);
            xn_root_add(xn_t4313);
            rt_string *xn_t4314 = rt_retain(lt);
xn_root_add(xn_t4314);
        xn_root_add(xn_t4314);
            xn_root_add(xn_t4314);
            rt_string *xn_t4315 = xn_concat(xn_t4313, xn_t4314);
xn_root_add(xn_t4315);
        xn_root_add(xn_t4315);
            xn_root_add(xn_t4315);
            rt_string *xn_t4316 = rt_string_from_c(") (Name ");
xn_root_add(xn_t4316);
        xn_root_add(xn_t4316);
            xn_root_add(xn_t4316);
            rt_string *xn_t4317 = xn_concat(xn_t4315, xn_t4316);
xn_root_add(xn_t4317);
        xn_root_add(xn_t4317);
            xn_root_add(xn_t4317);
            rt_string *xn_t4318 = rt_retain(ln);
xn_root_add(xn_t4318);
        xn_root_add(xn_t4318);
            xn_root_add(xn_t4318);
            rt_string *xn_t4319 = xn_q(xn_t4318);
xn_root_add(xn_t4319);
        xn_root_add(xn_t4319);
            xn_root_add(xn_t4319);
            rt_string *xn_t4320 = xn_concat(xn_t4317, xn_t4319);
xn_root_add(xn_t4320);
        xn_root_add(xn_t4320);
            xn_root_add(xn_t4320);
            rt_string *xn_t4321 = rt_string_from_c(") (Final ");
xn_root_add(xn_t4321);
        xn_root_add(xn_t4321);
            xn_root_add(xn_t4321);
            rt_string *xn_t4322 = xn_concat(xn_t4320, xn_t4321);
xn_root_add(xn_t4322);
        xn_root_add(xn_t4322);
            xn_root_add(xn_t4322);
            rt_string *xn_t4323 = xn_B(lf);
xn_root_add(xn_t4323);
        xn_root_add(xn_t4323);
            xn_root_add(xn_t4323);
            rt_string *xn_t4324 = xn_concat(xn_t4322, xn_t4323);
xn_root_add(xn_t4324);
        xn_root_add(xn_t4324);
            xn_root_add(xn_t4324);
            rt_string *xn_t4325 = rt_string_from_c("))");
xn_root_add(xn_t4325);
        xn_root_add(xn_t4325);
            xn_root_add(xn_t4325);
            rt_string *xn_t4326 = xn_concat(xn_t4324, xn_t4325);
xn_root_add(xn_t4326);
        xn_root_add(xn_t4326);
            xn_root_add(xn_t4326);
            xn_arr_s_push(lps, xn_t4326);
            xn_root_release(ln);
                {
                rt_release(ln);
                }
                {
                rt_release(lt);
                }
                {
                xn_root_restore(xn_t4300);
                }

            xn_gc_safepoint();
            }
        #line 2072 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 11))) {
                size_t xn_t4327 = xn_root_mark();
                #line 2072 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t4327);
                    }

            }
        #line 2073 "impl/lib/b2/xparser.x"
        rt_string *xn_t4328 = rt_string_from_c("->");
xn_root_add(xn_t4328);
        xn_root_add(xn_t4328);
            if ((xn_Cls_Parser_atOp(self, xn_t4328))) {
                size_t xn_t4329 = xn_root_mark();
                #line 2073 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t4329);
                    }

            }
        #line 2074 "impl/lib/b2/xparser.x"
        rt_string *lb = rt_string_from_c("(nil)");
xn_root_add(lb);
        xn_root_add(lb);
        xn_root_add(lb);
        xn_gc_safepoint();
        #line 2075 "impl/lib/b2/xparser.x"
        rt_string *le = rt_string_from_c("(nil)");
xn_root_add(le);
        xn_root_add(le);
        xn_root_add(le);
        xn_gc_safepoint();
        #line 2076 "impl/lib/b2/xparser.x"
        int single = 1;
        #line 2077 "impl/lib/b2/xparser.x"
        xn_Cls_Tok * bodyTok = xn_Cls_Parser_cur(self);
xn_root_add(bodyTok);
        xn_root_add(bodyTok);
        xn_root_add(bodyTok);
        xn_gc_safepoint();
        #line 2078 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 12))) {
                size_t xn_t4332 = xn_root_mark();
                #line 2078 "impl/lib/b2/xparser.x"
                rt_string *xn_t4333 = xn_Cls_Parser_parseBlock(self);
xn_root_add(xn_t4333);
        xn_root_add(xn_t4333);
                xn_root_add(xn_t4333);
                xn_root_release(lb);
                rt_release(lb);
                lb = xn_t4333;
                xn_root_hold(lb);
                xn_gc_safepoint();
                #line 2078 "impl/lib/b2/xparser.x"
                single = 0;
                    {
                    xn_root_restore(xn_t4332);
                    }

            } else {
                size_t xn_t4334 = xn_root_mark();
                #line 2079 "impl/lib/b2/xparser.x"
                xn_Cls_E * xn_t4335 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t4335);
        xn_root_add(xn_t4335);
                xn_root_add(xn_t4335);
                rt_string *xn_t4336 = rt_retain(xn_t4335->d);
xn_root_add(xn_t4336);
        xn_root_add(xn_t4336);
                xn_root_add(xn_t4336);
                xn_root_release(le);
                rt_release(le);
                le = xn_t4336;
                xn_root_hold(le);
                xn_gc_safepoint();
                    {
                    xn_root_restore(xn_t4334);
                    }

            }
        #line 2080 "impl/lib/b2/xparser.x"
        rt_string *xn_t4337 = rt_string_from_c("(Lambda ");
xn_root_add(xn_t4337);
        xn_root_add(xn_t4337);
        xn_root_add(xn_t4337);
        rt_string *xn_t4338 = xn_P(t->line, t->col);
xn_root_add(xn_t4338);
        xn_root_add(xn_t4338);
        xn_root_add(xn_t4338);
        rt_string *xn_t4339 = xn_concat(xn_t4337, xn_t4338);
xn_root_add(xn_t4339);
        xn_root_add(xn_t4339);
        xn_root_add(xn_t4339);
        rt_string *xn_t4340 = rt_string_from_c(" (Params ");
xn_root_add(xn_t4340);
        xn_root_add(xn_t4340);
        xn_root_add(xn_t4340);
        rt_string *xn_t4341 = xn_concat(xn_t4339, xn_t4340);
xn_root_add(xn_t4341);
        xn_root_add(xn_t4341);
        xn_root_add(xn_t4341);
        rt_string *xn_t4342 = xn_SL(lps);
xn_root_add(xn_t4342);
        xn_root_add(xn_t4342);
        xn_root_add(xn_t4342);
        rt_string *xn_t4343 = xn_concat(xn_t4341, xn_t4342);
xn_root_add(xn_t4343);
        xn_root_add(xn_t4343);
        xn_root_add(xn_t4343);
        rt_string *xn_t4344 = rt_string_from_c(") (Block ");
xn_root_add(xn_t4344);
        xn_root_add(xn_t4344);
        xn_root_add(xn_t4344);
        rt_string *xn_t4345 = xn_concat(xn_t4343, xn_t4344);
xn_root_add(xn_t4345);
        xn_root_add(xn_t4345);
        xn_root_add(xn_t4345);
        rt_string *xn_t4346 = rt_retain(lb);
xn_root_add(xn_t4346);
        xn_root_add(xn_t4346);
        xn_root_add(xn_t4346);
        rt_string *xn_t4347 = xn_concat(xn_t4345, xn_t4346);
xn_root_add(xn_t4347);
        xn_root_add(xn_t4347);
        xn_root_add(xn_t4347);
        rt_string *xn_t4348 = rt_string_from_c(") (ExprB ");
xn_root_add(xn_t4348);
        xn_root_add(xn_t4348);
        xn_root_add(xn_t4348);
        rt_string *xn_t4349 = xn_concat(xn_t4347, xn_t4348);
xn_root_add(xn_t4349);
        xn_root_add(xn_t4349);
        xn_root_add(xn_t4349);
        rt_string *xn_t4350 = rt_retain(le);
xn_root_add(xn_t4350);
        xn_root_add(xn_t4350);
        xn_root_add(xn_t4350);
        rt_string *xn_t4351 = xn_concat(xn_t4349, xn_t4350);
xn_root_add(xn_t4351);
        xn_root_add(xn_t4351);
        xn_root_add(xn_t4351);
        rt_string *xn_t4352 = rt_string_from_c(") (Single ");
xn_root_add(xn_t4352);
        xn_root_add(xn_t4352);
        xn_root_add(xn_t4352);
        rt_string *xn_t4353 = xn_concat(xn_t4351, xn_t4352);
xn_root_add(xn_t4353);
        xn_root_add(xn_t4353);
        xn_root_add(xn_t4353);
        rt_string *xn_t4354 = xn_B(single);
xn_root_add(xn_t4354);
        xn_root_add(xn_t4354);
        xn_root_add(xn_t4354);
        rt_string *xn_t4355 = xn_concat(xn_t4353, xn_t4354);
xn_root_add(xn_t4355);
        xn_root_add(xn_t4355);
        xn_root_add(xn_t4355);
        rt_string *xn_t4356 = rt_string_from_c("))");
xn_root_add(xn_t4356);
        xn_root_add(xn_t4356);
        xn_root_add(xn_t4356);
        rt_string *xn_t4357 = xn_concat(xn_t4355, xn_t4356);
xn_root_add(xn_t4357);
        xn_root_add(xn_t4357);
        xn_root_add(xn_t4357);
            {
        rt_release(le);
            }
            {
        rt_release(lb);
            }
            {
        xn_root_restore(xn_t4298);
            }
            {
        xn_root_restore(xn_t4168);
            }

        return xn_Cls_Parser_mk(self, xn_t4357, t->line, t->col);
        xn_root_release(lb);
        xn_root_release(le);

    }
#line 2082 "impl/lib/b2/xparser.x"
    if (((t->kind == 10))) {
        size_t xn_t4358 = xn_root_mark();
        #line 2083 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 2084 "impl/lib/b2/xparser.x"
        xn_Cls_E * x = xn_Cls_Parser_parseExpr(self);
xn_root_add(x);
        xn_root_add(x);
        xn_root_add(x);
        xn_gc_safepoint();
        #line 2085 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 16))) {
                size_t xn_t4359 = xn_root_mark();
                #line 2086 "impl/lib/b2/xparser.x"
                xn_arr_s *xn_t4360 = xn_arr_s_new(1);
xn_root_add(xn_t4360);
        xn_root_add(xn_t4360);
                xn_root_add(xn_t4360);
                rt_string *xn_t4361 = rt_retain(x->d);
xn_root_add(xn_t4361);
        xn_root_add(xn_t4361);
                xn_root_add(xn_t4361);
                xn_arr_s_push(xn_t4360, xn_t4361);
                xn_arr_s * es = xn_t4360;
xn_root_add(es);
        xn_root_add(es);
                xn_root_add(es);
                xn_root_add(es);
                xn_gc_safepoint();
                #line 2087 "impl/lib/b2/xparser.x"
                    while ((xn_Cls_Parser_at(self, 16))) {
                    size_t xn_t4362 = xn_root_mark();
                    #line 2088 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 2089 "impl/lib/b2/xparser.x"
                    xn_Cls_E * xn_t4363 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t4363);
        xn_root_add(xn_t4363);
                xn_root_add(xn_t4363);
                    xn_root_add(xn_t4363);
                    rt_string *xn_t4364 = rt_retain(xn_t4363->d);
xn_root_add(xn_t4364);
        xn_root_add(xn_t4364);
                xn_root_add(xn_t4364);
                    xn_root_add(xn_t4364);
                    xn_arr_s_push(es, xn_t4364);
                        {
                        xn_root_restore(xn_t4362);
                        }

                    xn_gc_safepoint();
                    }
                #line 2091 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 11))) {
                        size_t xn_t4365 = xn_root_mark();
                        #line 2091 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t4365);
                            }

                    }
                #line 2092 "impl/lib/b2/xparser.x"
                rt_string *xn_t4366 = rt_string_from_c("(Tuple ");
xn_root_add(xn_t4366);
        xn_root_add(xn_t4366);
                xn_root_add(xn_t4366);
                xn_root_add(xn_t4366);
                rt_string *xn_t4367 = xn_P(t->line, t->col);
xn_root_add(xn_t4367);
        xn_root_add(xn_t4367);
                xn_root_add(xn_t4367);
                xn_root_add(xn_t4367);
                rt_string *xn_t4368 = xn_concat(xn_t4366, xn_t4367);
xn_root_add(xn_t4368);
        xn_root_add(xn_t4368);
                xn_root_add(xn_t4368);
                xn_root_add(xn_t4368);
                rt_string *xn_t4369 = rt_string_from_c(" (Elems ");
xn_root_add(xn_t4369);
        xn_root_add(xn_t4369);
                xn_root_add(xn_t4369);
                xn_root_add(xn_t4369);
                rt_string *xn_t4370 = xn_concat(xn_t4368, xn_t4369);
xn_root_add(xn_t4370);
        xn_root_add(xn_t4370);
                xn_root_add(xn_t4370);
                xn_root_add(xn_t4370);
                rt_string *xn_t4371 = xn_SL(es);
xn_root_add(xn_t4371);
        xn_root_add(xn_t4371);
                xn_root_add(xn_t4371);
                xn_root_add(xn_t4371);
                rt_string *xn_t4372 = xn_concat(xn_t4370, xn_t4371);
xn_root_add(xn_t4372);
        xn_root_add(xn_t4372);
                xn_root_add(xn_t4372);
                xn_root_add(xn_t4372);
                rt_string *xn_t4373 = rt_string_from_c("))");
xn_root_add(xn_t4373);
        xn_root_add(xn_t4373);
                xn_root_add(xn_t4373);
                xn_root_add(xn_t4373);
                rt_string *xn_t4374 = xn_concat(xn_t4372, xn_t4373);
xn_root_add(xn_t4374);
        xn_root_add(xn_t4374);
                xn_root_add(xn_t4374);
                xn_root_add(xn_t4374);
                    {
                xn_root_restore(xn_t4359);
                    }
                    {
                xn_root_restore(xn_t4358);
                    }
                    {
                xn_root_restore(xn_t4168);
                    }

                return xn_Cls_Parser_mk(self, xn_t4374, t->line, t->col);

            }
        #line 2094 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 11))) {
                size_t xn_t4375 = xn_root_mark();
                #line 2094 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t4375);
                    }

            }
        #line 2095 "impl/lib/b2/xparser.x"
        rt_string *xn_t4376 = rt_string_from_c("(Paren ");
xn_root_add(xn_t4376);
        xn_root_add(xn_t4376);
        xn_root_add(xn_t4376);
        rt_string *xn_t4377 = xn_P(t->line, t->col);
xn_root_add(xn_t4377);
        xn_root_add(xn_t4377);
        xn_root_add(xn_t4377);
        rt_string *xn_t4378 = xn_concat(xn_t4376, xn_t4377);
xn_root_add(xn_t4378);
        xn_root_add(xn_t4378);
        xn_root_add(xn_t4378);
        rt_string *xn_t4379 = rt_string_from_c(" (X ");
xn_root_add(xn_t4379);
        xn_root_add(xn_t4379);
        xn_root_add(xn_t4379);
        rt_string *xn_t4380 = xn_concat(xn_t4378, xn_t4379);
xn_root_add(xn_t4380);
        xn_root_add(xn_t4380);
        xn_root_add(xn_t4380);
        rt_string *xn_t4381 = rt_retain(x->d);
xn_root_add(xn_t4381);
        xn_root_add(xn_t4381);
        xn_root_add(xn_t4381);
        rt_string *xn_t4382 = xn_concat(xn_t4380, xn_t4381);
xn_root_add(xn_t4382);
        xn_root_add(xn_t4382);
        xn_root_add(xn_t4382);
        rt_string *xn_t4383 = rt_string_from_c("))");
xn_root_add(xn_t4383);
        xn_root_add(xn_t4383);
        xn_root_add(xn_t4383);
        rt_string *xn_t4384 = xn_concat(xn_t4382, xn_t4383);
xn_root_add(xn_t4384);
        xn_root_add(xn_t4384);
        xn_root_add(xn_t4384);
            {
        xn_root_restore(xn_t4358);
            }
            {
        xn_root_restore(xn_t4168);
            }

        return xn_Cls_Parser_mk(self, xn_t4384, t->line, t->col);

    }
#line 2097 "impl/lib/b2/xparser.x"
    if (((t->kind == 14))) {
        size_t xn_t4385 = xn_root_mark();
        #line 2098 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 2099 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 15))) {
                size_t xn_t4386 = xn_root_mark();
                #line 2099 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                #line 2099 "impl/lib/b2/xparser.x"
                rt_string *xn_t4387 = rt_string_from_c("(ArrayLit ");
xn_root_add(xn_t4387);
        xn_root_add(xn_t4387);
                xn_root_add(xn_t4387);
                xn_root_add(xn_t4387);
                rt_string *xn_t4388 = xn_P(t->line, t->col);
xn_root_add(xn_t4388);
        xn_root_add(xn_t4388);
                xn_root_add(xn_t4388);
                xn_root_add(xn_t4388);
                rt_string *xn_t4389 = xn_concat(xn_t4387, xn_t4388);
xn_root_add(xn_t4389);
        xn_root_add(xn_t4389);
                xn_root_add(xn_t4389);
                xn_root_add(xn_t4389);
                rt_string *xn_t4390 = rt_string_from_c(" (Elems (slice)))");
xn_root_add(xn_t4390);
        xn_root_add(xn_t4390);
                xn_root_add(xn_t4390);
                xn_root_add(xn_t4390);
                rt_string *xn_t4391 = xn_concat(xn_t4389, xn_t4390);
xn_root_add(xn_t4391);
        xn_root_add(xn_t4391);
                xn_root_add(xn_t4391);
                xn_root_add(xn_t4391);
                    {
                xn_root_restore(xn_t4386);
                    }
                    {
                xn_root_restore(xn_t4385);
                    }
                    {
                xn_root_restore(xn_t4168);
                    }

                return xn_Cls_Parser_mk(self, xn_t4391, t->line, t->col);

            }
        #line 2100 "impl/lib/b2/xparser.x"
        rt_string *xn_t4392 = rt_string_from_c(":");
xn_root_add(xn_t4392);
        xn_root_add(xn_t4392);
            if ((xn_Cls_Parser_atOp(self, xn_t4392))) {
                size_t xn_t4393 = xn_root_mark();
                #line 2101 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                #line 2102 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 15))) {
                        size_t xn_t4394 = xn_root_mark();
                        #line 2102 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t4394);
                            }

                    }
                #line 2103 "impl/lib/b2/xparser.x"
                rt_string *xn_t4395 = rt_string_from_c("(MapLit ");
xn_root_add(xn_t4395);
        xn_root_add(xn_t4395);
                xn_root_add(xn_t4395);
                xn_root_add(xn_t4395);
                rt_string *xn_t4396 = xn_P(t->line, t->col);
xn_root_add(xn_t4396);
        xn_root_add(xn_t4396);
                xn_root_add(xn_t4396);
                xn_root_add(xn_t4396);
                rt_string *xn_t4397 = xn_concat(xn_t4395, xn_t4396);
xn_root_add(xn_t4397);
        xn_root_add(xn_t4397);
                xn_root_add(xn_t4397);
                xn_root_add(xn_t4397);
                rt_string *xn_t4398 = rt_string_from_c(" (Keys (slice)) (Vals (slice)))");
xn_root_add(xn_t4398);
        xn_root_add(xn_t4398);
                xn_root_add(xn_t4398);
                xn_root_add(xn_t4398);
                rt_string *xn_t4399 = xn_concat(xn_t4397, xn_t4398);
xn_root_add(xn_t4399);
        xn_root_add(xn_t4399);
                xn_root_add(xn_t4399);
                xn_root_add(xn_t4399);
                    {
                xn_root_restore(xn_t4393);
                    }
                    {
                xn_root_restore(xn_t4385);
                    }
                    {
                xn_root_restore(xn_t4168);
                    }

                return xn_Cls_Parser_mk(self, xn_t4399, t->line, t->col);

            }
        #line 2105 "impl/lib/b2/xparser.x"
        xn_Cls_E * first = xn_Cls_Parser_parseExpr(self);
xn_root_add(first);
        xn_root_add(first);
        xn_root_add(first);
        xn_gc_safepoint();
        #line 2106 "impl/lib/b2/xparser.x"
        rt_string *xn_t4400 = rt_string_from_c(":");
xn_root_add(xn_t4400);
        xn_root_add(xn_t4400);
            if ((xn_Cls_Parser_atOp(self, xn_t4400))) {
                size_t xn_t4401 = xn_root_mark();
                #line 2107 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                #line 2108 "impl/lib/b2/xparser.x"
                xn_Cls_E * v = xn_Cls_Parser_parseExpr(self);
xn_root_add(v);
        xn_root_add(v);
                xn_root_add(v);
                xn_root_add(v);
                xn_gc_safepoint();
                #line 2109 "impl/lib/b2/xparser.x"
                xn_arr_s *xn_t4402 = xn_arr_s_new(1);
xn_root_add(xn_t4402);
        xn_root_add(xn_t4402);
                xn_root_add(xn_t4402);
                rt_string *xn_t4403 = rt_retain(first->d);
xn_root_add(xn_t4403);
        xn_root_add(xn_t4403);
                xn_root_add(xn_t4403);
                xn_arr_s_push(xn_t4402, xn_t4403);
                xn_arr_s * ks = xn_t4402;
xn_root_add(ks);
        xn_root_add(ks);
                xn_root_add(ks);
                xn_root_add(ks);
                xn_gc_safepoint();
                #line 2110 "impl/lib/b2/xparser.x"
                xn_arr_s *xn_t4404 = xn_arr_s_new(1);
xn_root_add(xn_t4404);
        xn_root_add(xn_t4404);
                xn_root_add(xn_t4404);
                rt_string *xn_t4405 = rt_retain(v->d);
xn_root_add(xn_t4405);
        xn_root_add(xn_t4405);
                xn_root_add(xn_t4405);
                xn_arr_s_push(xn_t4404, xn_t4405);
                xn_arr_s * vs = xn_t4404;
xn_root_add(vs);
        xn_root_add(vs);
                xn_root_add(vs);
                xn_root_add(vs);
                xn_gc_safepoint();
                #line 2111 "impl/lib/b2/xparser.x"
                    while ((xn_Cls_Parser_at(self, 16))) {
                    size_t xn_t4406 = xn_root_mark();
                    #line 2112 "impl/lib/b2/xparser.x"
                    xn_Cls_Parser_next(self);
                    #line 2113 "impl/lib/b2/xparser.x"
                    xn_Cls_E * xn_t4407 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t4407);
        xn_root_add(xn_t4407);
                xn_root_add(xn_t4407);
                    xn_root_add(xn_t4407);
                    rt_string *xn_t4408 = rt_retain(xn_t4407->d);
xn_root_add(xn_t4408);
        xn_root_add(xn_t4408);
                xn_root_add(xn_t4408);
                    xn_root_add(xn_t4408);
                    xn_arr_s_push(ks, xn_t4408);
                    #line 2114 "impl/lib/b2/xparser.x"
                    rt_string *xn_t4409 = rt_string_from_c(":");
xn_root_add(xn_t4409);
        xn_root_add(xn_t4409);
                xn_root_add(xn_t4409);
                    xn_root_add(xn_t4409);
                        if ((xn_Cls_Parser_atOp(self, xn_t4409))) {
                            size_t xn_t4410 = xn_root_mark();
                            #line 2114 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                                {
                                xn_root_restore(xn_t4410);
                                }

                        }
                    #line 2115 "impl/lib/b2/xparser.x"
                    xn_Cls_E * xn_t4411 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t4411);
        xn_root_add(xn_t4411);
                xn_root_add(xn_t4411);
                    xn_root_add(xn_t4411);
                    rt_string *xn_t4412 = rt_retain(xn_t4411->d);
xn_root_add(xn_t4412);
        xn_root_add(xn_t4412);
                xn_root_add(xn_t4412);
                    xn_root_add(xn_t4412);
                    xn_arr_s_push(vs, xn_t4412);
                        {
                        xn_root_restore(xn_t4406);
                        }

                    xn_gc_safepoint();
                    }
                #line 2117 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 15))) {
                        size_t xn_t4413 = xn_root_mark();
                        #line 2117 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t4413);
                            }

                    }
                #line 2118 "impl/lib/b2/xparser.x"
                rt_string *xn_t4414 = rt_string_from_c("(MapLit ");
xn_root_add(xn_t4414);
        xn_root_add(xn_t4414);
                xn_root_add(xn_t4414);
                xn_root_add(xn_t4414);
                rt_string *xn_t4415 = xn_P(t->line, t->col);
xn_root_add(xn_t4415);
        xn_root_add(xn_t4415);
                xn_root_add(xn_t4415);
                xn_root_add(xn_t4415);
                rt_string *xn_t4416 = xn_concat(xn_t4414, xn_t4415);
xn_root_add(xn_t4416);
        xn_root_add(xn_t4416);
                xn_root_add(xn_t4416);
                xn_root_add(xn_t4416);
                rt_string *xn_t4417 = rt_string_from_c(" (Keys ");
xn_root_add(xn_t4417);
        xn_root_add(xn_t4417);
                xn_root_add(xn_t4417);
                xn_root_add(xn_t4417);
                rt_string *xn_t4418 = xn_concat(xn_t4416, xn_t4417);
xn_root_add(xn_t4418);
        xn_root_add(xn_t4418);
                xn_root_add(xn_t4418);
                xn_root_add(xn_t4418);
                rt_string *xn_t4419 = xn_SL(ks);
xn_root_add(xn_t4419);
        xn_root_add(xn_t4419);
                xn_root_add(xn_t4419);
                xn_root_add(xn_t4419);
                rt_string *xn_t4420 = xn_concat(xn_t4418, xn_t4419);
xn_root_add(xn_t4420);
        xn_root_add(xn_t4420);
                xn_root_add(xn_t4420);
                xn_root_add(xn_t4420);
                rt_string *xn_t4421 = rt_string_from_c(") (Vals ");
xn_root_add(xn_t4421);
        xn_root_add(xn_t4421);
                xn_root_add(xn_t4421);
                xn_root_add(xn_t4421);
                rt_string *xn_t4422 = xn_concat(xn_t4420, xn_t4421);
xn_root_add(xn_t4422);
        xn_root_add(xn_t4422);
                xn_root_add(xn_t4422);
                xn_root_add(xn_t4422);
                rt_string *xn_t4423 = xn_SL(vs);
xn_root_add(xn_t4423);
        xn_root_add(xn_t4423);
                xn_root_add(xn_t4423);
                xn_root_add(xn_t4423);
                rt_string *xn_t4424 = xn_concat(xn_t4422, xn_t4423);
xn_root_add(xn_t4424);
        xn_root_add(xn_t4424);
                xn_root_add(xn_t4424);
                xn_root_add(xn_t4424);
                rt_string *xn_t4425 = rt_string_from_c("))");
xn_root_add(xn_t4425);
        xn_root_add(xn_t4425);
                xn_root_add(xn_t4425);
                xn_root_add(xn_t4425);
                rt_string *xn_t4426 = xn_concat(xn_t4424, xn_t4425);
xn_root_add(xn_t4426);
        xn_root_add(xn_t4426);
                xn_root_add(xn_t4426);
                xn_root_add(xn_t4426);
                    {
                xn_root_restore(xn_t4401);
                    }
                    {
                xn_root_restore(xn_t4385);
                    }
                    {
                xn_root_restore(xn_t4168);
                    }

                return xn_Cls_Parser_mk(self, xn_t4426, t->line, t->col);

            }
        #line 2120 "impl/lib/b2/xparser.x"
        xn_arr_s *xn_t4427 = xn_arr_s_new(1);
xn_root_add(xn_t4427);
        xn_root_add(xn_t4427);
        rt_string *xn_t4428 = rt_retain(first->d);
xn_root_add(xn_t4428);
        xn_root_add(xn_t4428);
        xn_arr_s_push(xn_t4427, xn_t4428);
        xn_arr_s * es = xn_t4427;
xn_root_add(es);
        xn_root_add(es);
        xn_root_add(es);
        xn_gc_safepoint();
        #line 2121 "impl/lib/b2/xparser.x"
            while ((xn_Cls_Parser_at(self, 16))) {
            size_t xn_t4429 = xn_root_mark();
            #line 2122 "impl/lib/b2/xparser.x"
            xn_Cls_Parser_next(self);
            #line 2123 "impl/lib/b2/xparser.x"
            xn_Cls_E * xn_t4430 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t4430);
        xn_root_add(xn_t4430);
            xn_root_add(xn_t4430);
            rt_string *xn_t4431 = rt_retain(xn_t4430->d);
xn_root_add(xn_t4431);
        xn_root_add(xn_t4431);
            xn_root_add(xn_t4431);
            xn_arr_s_push(es, xn_t4431);
                {
                xn_root_restore(xn_t4429);
                }

            xn_gc_safepoint();
            }
        #line 2125 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 15))) {
                size_t xn_t4432 = xn_root_mark();
                #line 2125 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                    {
                    xn_root_restore(xn_t4432);
                    }

            }
        #line 2126 "impl/lib/b2/xparser.x"
        rt_string *xn_t4433 = rt_string_from_c("(ArrayLit ");
xn_root_add(xn_t4433);
        xn_root_add(xn_t4433);
        xn_root_add(xn_t4433);
        rt_string *xn_t4434 = xn_P(t->line, t->col);
xn_root_add(xn_t4434);
        xn_root_add(xn_t4434);
        xn_root_add(xn_t4434);
        rt_string *xn_t4435 = xn_concat(xn_t4433, xn_t4434);
xn_root_add(xn_t4435);
        xn_root_add(xn_t4435);
        xn_root_add(xn_t4435);
        rt_string *xn_t4436 = rt_string_from_c(" (Elems ");
xn_root_add(xn_t4436);
        xn_root_add(xn_t4436);
        xn_root_add(xn_t4436);
        rt_string *xn_t4437 = xn_concat(xn_t4435, xn_t4436);
xn_root_add(xn_t4437);
        xn_root_add(xn_t4437);
        xn_root_add(xn_t4437);
        rt_string *xn_t4438 = xn_SL(es);
xn_root_add(xn_t4438);
        xn_root_add(xn_t4438);
        xn_root_add(xn_t4438);
        rt_string *xn_t4439 = xn_concat(xn_t4437, xn_t4438);
xn_root_add(xn_t4439);
        xn_root_add(xn_t4439);
        xn_root_add(xn_t4439);
        rt_string *xn_t4440 = rt_string_from_c("))");
xn_root_add(xn_t4440);
        xn_root_add(xn_t4440);
        xn_root_add(xn_t4440);
        rt_string *xn_t4441 = xn_concat(xn_t4439, xn_t4440);
xn_root_add(xn_t4441);
        xn_root_add(xn_t4441);
        xn_root_add(xn_t4441);
            {
        xn_root_restore(xn_t4385);
            }
            {
        xn_root_restore(xn_t4168);
            }

        return xn_Cls_Parser_mk(self, xn_t4441, t->line, t->col);

    }
#line 2128 "impl/lib/b2/xparser.x"
rt_string *xn_t4442 = rt_retain(t->text);
xn_root_add(xn_t4442);
rt_string *xn_t4443 = rt_string_from_c("new");
xn_root_add(xn_t4443);
    if ((((t->kind == 3)) && (xn_str_eq(xn_t4442, xn_t4443)))) {
        size_t xn_t4444 = xn_root_mark();
        #line 2129 "impl/lib/b2/xparser.x"
        xn_Cls_Parser_next(self);
        #line 2130 "impl/lib/b2/xparser.x"
        self->inNew = (self->inNew + 1);
        #line 2131 "impl/lib/b2/xparser.x"
        rt_string *ty = xn_Cls_Parser_parseType(self);
xn_root_add(ty);
        xn_root_add(ty);
        xn_root_add(ty);
        xn_gc_safepoint();
        #line 2132 "impl/lib/b2/xparser.x"
        self->inNew = (self->inNew - 1);
        #line 2133 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 14))) {
                size_t xn_t4446 = xn_root_mark();
                #line 2134 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                #line 2135 "impl/lib/b2/xparser.x"
                xn_Cls_E * cnt = xn_Cls_Parser_parseExpr(self);
xn_root_add(cnt);
        xn_root_add(cnt);
                xn_root_add(cnt);
                xn_root_add(cnt);
                xn_gc_safepoint();
                #line 2136 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 15))) {
                        size_t xn_t4447 = xn_root_mark();
                        #line 2136 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t4447);
                            }

                    }
                #line 2137 "impl/lib/b2/xparser.x"
                rt_string *xn_t4448 = rt_string_from_c("(NewArray ");
xn_root_add(xn_t4448);
        xn_root_add(xn_t4448);
                xn_root_add(xn_t4448);
                xn_root_add(xn_t4448);
                rt_string *xn_t4449 = xn_P(t->line, t->col);
xn_root_add(xn_t4449);
        xn_root_add(xn_t4449);
                xn_root_add(xn_t4449);
                xn_root_add(xn_t4449);
                rt_string *xn_t4450 = xn_concat(xn_t4448, xn_t4449);
xn_root_add(xn_t4450);
        xn_root_add(xn_t4450);
                xn_root_add(xn_t4450);
                xn_root_add(xn_t4450);
                rt_string *xn_t4451 = rt_string_from_c(" (Type ");
xn_root_add(xn_t4451);
        xn_root_add(xn_t4451);
                xn_root_add(xn_t4451);
                xn_root_add(xn_t4451);
                rt_string *xn_t4452 = xn_concat(xn_t4450, xn_t4451);
xn_root_add(xn_t4452);
        xn_root_add(xn_t4452);
                xn_root_add(xn_t4452);
                xn_root_add(xn_t4452);
                rt_string *xn_t4453 = rt_retain(ty);
xn_root_add(xn_t4453);
        xn_root_add(xn_t4453);
                xn_root_add(xn_t4453);
                xn_root_add(xn_t4453);
                rt_string *xn_t4454 = xn_concat(xn_t4452, xn_t4453);
xn_root_add(xn_t4454);
        xn_root_add(xn_t4454);
                xn_root_add(xn_t4454);
                xn_root_add(xn_t4454);
                rt_string *xn_t4455 = rt_string_from_c(") (Count ");
xn_root_add(xn_t4455);
        xn_root_add(xn_t4455);
                xn_root_add(xn_t4455);
                xn_root_add(xn_t4455);
                rt_string *xn_t4456 = xn_concat(xn_t4454, xn_t4455);
xn_root_add(xn_t4456);
        xn_root_add(xn_t4456);
                xn_root_add(xn_t4456);
                xn_root_add(xn_t4456);
                rt_string *xn_t4457 = rt_retain(cnt->d);
xn_root_add(xn_t4457);
        xn_root_add(xn_t4457);
                xn_root_add(xn_t4457);
                xn_root_add(xn_t4457);
                rt_string *xn_t4458 = xn_concat(xn_t4456, xn_t4457);
xn_root_add(xn_t4458);
        xn_root_add(xn_t4458);
                xn_root_add(xn_t4458);
                xn_root_add(xn_t4458);
                rt_string *xn_t4459 = rt_string_from_c("))");
xn_root_add(xn_t4459);
        xn_root_add(xn_t4459);
                xn_root_add(xn_t4459);
                xn_root_add(xn_t4459);
                rt_string *xn_t4460 = xn_concat(xn_t4458, xn_t4459);
xn_root_add(xn_t4460);
        xn_root_add(xn_t4460);
                xn_root_add(xn_t4460);
                xn_root_add(xn_t4460);
                    {
                xn_root_restore(xn_t4446);
                    }
                    {
                rt_release(ty);
                    }
                    {
                xn_root_restore(xn_t4444);
                    }
                    {
                xn_root_restore(xn_t4168);
                    }

                return xn_Cls_Parser_mk(self, xn_t4460, t->line, t->col);

            }
        #line 2139 "impl/lib/b2/xparser.x"
        xn_arr_s *xn_t4461 = xn_arr_s_new(0);
xn_root_add(xn_t4461);
        xn_root_add(xn_t4461);
        xn_arr_s * tas = xn_t4461;
xn_root_add(tas);
        xn_root_add(tas);
        xn_root_add(tas);
        xn_gc_safepoint();
        #line 2140 "impl/lib/b2/xparser.x"
            if ((xn_Cls_Parser_at(self, 10))) {
                size_t xn_t4462 = xn_root_mark();
                #line 2141 "impl/lib/b2/xparser.x"
                xn_Cls_Parser_next(self);
                #line 2142 "impl/lib/b2/xparser.x"
                    while ((((!(xn_Cls_Parser_at(self, 11)))) && ((!(xn_Cls_Parser_eof(self)))))) {
                    size_t xn_t4463 = xn_root_mark();
                    #line 2143 "impl/lib/b2/xparser.x"
                        if ((xn_Cls_Parser_at(self, 16))) {
                            size_t xn_t4464 = xn_root_mark();
                            #line 2143 "impl/lib/b2/xparser.x"
                            xn_Cls_Parser_next(self);
                            #line 2143 "impl/lib/b2/xparser.x"
                            xn_root_restore(xn_t4464);
                            xn_root_restore(xn_t4463);
                            continue;
                                {
                                xn_root_restore(xn_t4464);
                                }

                        }
                    #line 2144 "impl/lib/b2/xparser.x"
                    xn_Cls_E * xn_t4465 = xn_Cls_Parser_parseExpr(self);
xn_root_add(xn_t4465);
        xn_root_add(xn_t4465);
                xn_root_add(xn_t4465);
                    xn_root_add(xn_t4465);
                    rt_string *xn_t4466 = rt_retain(xn_t4465->d);
xn_root_add(xn_t4466);
        xn_root_add(xn_t4466);
                xn_root_add(xn_t4466);
                    xn_root_add(xn_t4466);
                    xn_arr_s_push(tas, xn_t4466);
                        {
                        xn_root_restore(xn_t4463);
                        }

                    xn_gc_safepoint();
                    }
                #line 2146 "impl/lib/b2/xparser.x"
                    if ((xn_Cls_Parser_at(self, 11))) {
                        size_t xn_t4467 = xn_root_mark();
                        #line 2146 "impl/lib/b2/xparser.x"
                        xn_Cls_Parser_next(self);
                            {
                            xn_root_restore(xn_t4467);
                            }

                    }
                    {
                    xn_root_restore(xn_t4462);
                    }

            }
        #line 2148 "impl/lib/b2/xparser.x"
        rt_string *xn_t4468 = rt_string_from_c("(New ");
xn_root_add(xn_t4468);
        xn_root_add(xn_t4468);
        xn_root_add(xn_t4468);
        rt_string *xn_t4469 = xn_P(t->line, t->col);
xn_root_add(xn_t4469);
        xn_root_add(xn_t4469);
        xn_root_add(xn_t4469);
        rt_string *xn_t4470 = xn_concat(xn_t4468, xn_t4469);
xn_root_add(xn_t4470);
        xn_root_add(xn_t4470);
        xn_root_add(xn_t4470);
        rt_string *xn_t4471 = rt_string_from_c(" (Type ");
xn_root_add(xn_t4471);
        xn_root_add(xn_t4471);
        xn_root_add(xn_t4471);
        rt_string *xn_t4472 = xn_concat(xn_t4470, xn_t4471);
xn_root_add(xn_t4472);
        xn_root_add(xn_t4472);
        xn_root_add(xn_t4472);
        rt_string *xn_t4473 = rt_retain(ty);
xn_root_add(xn_t4473);
        xn_root_add(xn_t4473);
        xn_root_add(xn_t4473);
        rt_string *xn_t4474 = xn_concat(xn_t4472, xn_t4473);
xn_root_add(xn_t4474);
        xn_root_add(xn_t4474);
        xn_root_add(xn_t4474);
        rt_string *xn_t4475 = rt_string_from_c(") (Args ");
xn_root_add(xn_t4475);
        xn_root_add(xn_t4475);
        xn_root_add(xn_t4475);
        rt_string *xn_t4476 = xn_concat(xn_t4474, xn_t4475);
xn_root_add(xn_t4476);
        xn_root_add(xn_t4476);
        xn_root_add(xn_t4476);
        rt_string *xn_t4477 = xn_SL(tas);
xn_root_add(xn_t4477);
        xn_root_add(xn_t4477);
        xn_root_add(xn_t4477);
        rt_string *xn_t4478 = xn_concat(xn_t4476, xn_t4477);
xn_root_add(xn_t4478);
        xn_root_add(xn_t4478);
        xn_root_add(xn_t4478);
        rt_string *xn_t4479 = rt_string_from_c("))");
xn_root_add(xn_t4479);
        xn_root_add(xn_t4479);
        xn_root_add(xn_t4479);
        rt_string *xn_t4480 = xn_concat(xn_t4478, xn_t4479);
xn_root_add(xn_t4480);
        xn_root_add(xn_t4480);
        xn_root_add(xn_t4480);
            {
        rt_release(ty);
            }
            {
        xn_root_restore(xn_t4444);
            }
            {
        xn_root_restore(xn_t4168);
            }

        return xn_Cls_Parser_mk(self, xn_t4480, t->line, t->col);

    }
#line 2150 "impl/lib/b2/xparser.x"
xn_Cls_Parser_next(self);
#line 2151 "impl/lib/b2/xparser.x"
rt_string *xn_t4481 = rt_string_from_c("(IdentExpr ");
xn_root_add(xn_t4481);
xn_root_add(xn_t4481);
rt_string *xn_t4482 = xn_P(t->line, t->col);
xn_root_add(xn_t4482);
xn_root_add(xn_t4482);
rt_string *xn_t4483 = xn_concat(xn_t4481, xn_t4482);
xn_root_add(xn_t4483);
xn_root_add(xn_t4483);
rt_string *xn_t4484 = rt_string_from_c(" (Name ");
xn_root_add(xn_t4484);
xn_root_add(xn_t4484);
rt_string *xn_t4485 = xn_concat(xn_t4483, xn_t4484);
xn_root_add(xn_t4485);
xn_root_add(xn_t4485);
rt_string *xn_t4486 = rt_retain(t->text);
xn_root_add(xn_t4486);
xn_root_add(xn_t4486);
rt_string *xn_t4487 = xn_q(xn_t4486);
xn_root_add(xn_t4487);
xn_root_add(xn_t4487);
rt_string *xn_t4488 = xn_concat(xn_t4485, xn_t4487);
xn_root_add(xn_t4488);
xn_root_add(xn_t4488);
rt_string *xn_t4489 = rt_string_from_c("))");
xn_root_add(xn_t4489);
xn_root_add(xn_t4489);
rt_string *xn_t4490 = xn_concat(xn_t4488, xn_t4489);
xn_root_add(xn_t4490);
xn_root_add(xn_t4490);
    {
xn_root_restore(xn_t4168);
    }

return xn_Cls_Parser_mk(self, xn_t4490, t->line, t->col);
    return (xn_Cls_E *)0; /* sema 保证不可达（函数体全路径 return） */
}

static void xn_init_vtables(void) {
}

static void xn_init_enums(void) {
}

static rt_string *xn_result_error_copy_rt(rt_string *err) {
    return rt_string_new(err->bytes, err->len);
}

rt_string * xn_readFileText(rt_string * xn_p_path) {
size_t xn_t1 = xn_root_mark();
xn_root_add(xn_p_path);
#line 10 "impl/lib/b2/xparser.x"
xrt_string *xn_t2 = NULL;
int32_t xn_t3 = xn_ffi_readFileTextRaw(xn_p_path->bytes, xn_p_path->len, &xn_t2);
rt_string *raw = (rt_string *)xn_t2;
xn_root_add(raw);
xn_root_add(raw);
xn_gc_safepoint();
#line 11 "impl/lib/b2/xparser.x"
int32_t xn_t5 = 0;
int32_t xn_t6 = xn_ffi_readFileTextError(&xn_t5);
    if (((xn_t5 != 0))) {
        size_t xn_t7 = xn_root_mark();
        #line 12 "impl/lib/b2/xparser.x"
        rt_string *xn_t8 = rt_string_from_c("readFileText: 无法读取文件 ");
xn_root_add(xn_t8);
        xn_root_add(xn_t8);
        rt_string *xn_t9 = rt_retain(xn_p_path);
xn_root_add(xn_t9);
        xn_root_add(xn_t9);
        rt_string *xn_t10 = xn_concat(xn_t8, xn_t9);
xn_root_add(xn_t10);
        xn_root_add(xn_t10);
        xn_throw(xn_t10);
            {
            xn_root_restore(xn_t7);
            }

    }
#line 14 "impl/lib/b2/xparser.x"
rt_retain(raw);
    {
rt_release(raw);
    }
    {
xn_root_restore(xn_t1);
    }

return raw;
}

int xn_inList(xn_arr_s * xn_p_xs, rt_string * xn_p_w) {
size_t xn_t11 = xn_root_mark();
xn_root_add(xn_p_xs);
xn_root_add(xn_p_w);
#line 8 "impl/lib/b2/xparser.x"
int64_t i = 0;
#line 9 "impl/lib/b2/xparser.x"
    while (((i < ((int64_t)xn_p_xs->len)))) {
    size_t xn_t12 = xn_root_mark();
    #line 10 "impl/lib/b2/xparser.x"
    rt_string *xn_t13 = rt_retain(xn_arr_s_get(xn_p_xs, i));
xn_root_add(xn_t13);
    xn_root_add(xn_t13);
    rt_string *xn_t14 = rt_retain(xn_p_w);
xn_root_add(xn_t14);
    xn_root_add(xn_t14);
        if ((xn_str_eq(xn_t13, xn_t14))) {
            size_t xn_t15 = xn_root_mark();
            #line 10 "impl/lib/b2/xparser.x"
            int xn_t16 = 1;
                {
            xn_root_restore(xn_t15);
                }
                {
            xn_root_restore(xn_t12);
                }
                {
            xn_root_restore(xn_t11);
                }

            return xn_t16;

        }
    #line 11 "impl/lib/b2/xparser.x"
    i = (i + 1);
        {
        xn_root_restore(xn_t12);
        }

    xn_gc_safepoint();
    }
#line 13 "impl/lib/b2/xparser.x"
int xn_t17 = 0;
    {
xn_root_restore(xn_t11);
    }

return xn_t17;
}

rt_string * xn_q(rt_string * xn_p_s) {
size_t xn_t18 = xn_root_mark();
xn_root_add(xn_p_s);
#line 595 "impl/lib/b2/xparser.x"
rt_string *b = rt_string_from_c("\"");
xn_root_add(b);
xn_root_add(b);
xn_gc_safepoint();
#line 596 "impl/lib/b2/xparser.x"
rt_string *nul = xn_str_char((int32_t)(0));
xn_root_add(nul);
xn_root_add(nul);
xn_gc_safepoint();
#line 597 "impl/lib/b2/xparser.x"
int64_t i = 0;
#line 598 "impl/lib/b2/xparser.x"
    while (((i < xn_str_length(xn_p_s)))) {
    size_t xn_t21 = xn_root_mark();
    #line 599 "impl/lib/b2/xparser.x"
    rt_string *c = xn_str_substr(xn_p_s, i, 1);
xn_root_add(c);
    xn_root_add(c);
    xn_root_add(c);
    xn_gc_safepoint();
    #line 600 "impl/lib/b2/xparser.x"
    rt_string *xn_t23 = rt_retain(c);
xn_root_add(xn_t23);
    xn_root_add(xn_t23);
    rt_string *xn_t24 = rt_string_from_c("\"");
xn_root_add(xn_t24);
    xn_root_add(xn_t24);
        if ((xn_str_eq(xn_t23, xn_t24))) {
            size_t xn_t25 = xn_root_mark();
            #line 600 "impl/lib/b2/xparser.x"
            rt_string *xn_t26 = rt_retain(b);
xn_root_add(xn_t26);
    xn_root_add(xn_t26);
            xn_root_add(xn_t26);
            rt_string *xn_t27 = rt_string_from_c("\\\"");
xn_root_add(xn_t27);
    xn_root_add(xn_t27);
            xn_root_add(xn_t27);
            rt_string *xn_t28 = xn_concat(xn_t26, xn_t27);
xn_root_add(xn_t28);
    xn_root_add(xn_t28);
            xn_root_add(xn_t28);
            xn_root_release(b);
            rt_release(b);
            b = xn_t28;
            xn_root_hold(b);
            xn_gc_safepoint();
                {
                xn_root_restore(xn_t25);
                }

        } else {
            rt_string *xn_t30 = rt_retain(c);
xn_root_add(xn_t30);
    xn_root_add(xn_t30);
            xn_root_add(xn_t30);
            rt_string *xn_t31 = rt_string_from_c("\\");
xn_root_add(xn_t31);
    xn_root_add(xn_t31);
            xn_root_add(xn_t31);
                if ((xn_str_eq(xn_t30, xn_t31))) {
                    size_t xn_t32 = xn_root_mark();
                    #line 601 "impl/lib/b2/xparser.x"
                    rt_string *xn_t33 = rt_retain(b);
xn_root_add(xn_t33);
    xn_root_add(xn_t33);
            xn_root_add(xn_t33);
                    xn_root_add(xn_t33);
                    rt_string *xn_t34 = rt_string_from_c("\\\\");
xn_root_add(xn_t34);
    xn_root_add(xn_t34);
            xn_root_add(xn_t34);
                    xn_root_add(xn_t34);
                    rt_string *xn_t35 = xn_concat(xn_t33, xn_t34);
xn_root_add(xn_t35);
    xn_root_add(xn_t35);
            xn_root_add(xn_t35);
                    xn_root_add(xn_t35);
                    xn_root_release(b);
                    rt_release(b);
                    b = xn_t35;
                    xn_root_hold(b);
                    xn_gc_safepoint();
                        {
                        xn_root_restore(xn_t32);
                        }

                } else {
                    rt_string *xn_t37 = rt_retain(c);
xn_root_add(xn_t37);
    xn_root_add(xn_t37);
            xn_root_add(xn_t37);
                    xn_root_add(xn_t37);
                    rt_string *xn_t38 = rt_string_from_c("\n");
xn_root_add(xn_t38);
    xn_root_add(xn_t38);
            xn_root_add(xn_t38);
                    xn_root_add(xn_t38);
                        if ((xn_str_eq(xn_t37, xn_t38))) {
                            size_t xn_t39 = xn_root_mark();
                            #line 602 "impl/lib/b2/xparser.x"
                            rt_string *xn_t40 = rt_retain(b);
xn_root_add(xn_t40);
    xn_root_add(xn_t40);
            xn_root_add(xn_t40);
                    xn_root_add(xn_t40);
                            xn_root_add(xn_t40);
                            rt_string *xn_t41 = rt_string_from_c("\\n");
xn_root_add(xn_t41);
    xn_root_add(xn_t41);
            xn_root_add(xn_t41);
                    xn_root_add(xn_t41);
                            xn_root_add(xn_t41);
                            rt_string *xn_t42 = xn_concat(xn_t40, xn_t41);
xn_root_add(xn_t42);
    xn_root_add(xn_t42);
            xn_root_add(xn_t42);
                    xn_root_add(xn_t42);
                            xn_root_add(xn_t42);
                            xn_root_release(b);
                            rt_release(b);
                            b = xn_t42;
                            xn_root_hold(b);
                            xn_gc_safepoint();
                                {
                                xn_root_restore(xn_t39);
                                }

                        } else {
                            rt_string *xn_t44 = rt_retain(c);
xn_root_add(xn_t44);
    xn_root_add(xn_t44);
            xn_root_add(xn_t44);
                    xn_root_add(xn_t44);
                            xn_root_add(xn_t44);
                            rt_string *xn_t45 = rt_string_from_c("\t");
xn_root_add(xn_t45);
    xn_root_add(xn_t45);
            xn_root_add(xn_t45);
                    xn_root_add(xn_t45);
                            xn_root_add(xn_t45);
                                if ((xn_str_eq(xn_t44, xn_t45))) {
                                    size_t xn_t46 = xn_root_mark();
                                    #line 603 "impl/lib/b2/xparser.x"
                                    rt_string *xn_t47 = rt_retain(b);
xn_root_add(xn_t47);
    xn_root_add(xn_t47);
            xn_root_add(xn_t47);
                    xn_root_add(xn_t47);
                            xn_root_add(xn_t47);
                                    xn_root_add(xn_t47);
                                    rt_string *xn_t48 = rt_string_from_c("\\t");
xn_root_add(xn_t48);
    xn_root_add(xn_t48);
            xn_root_add(xn_t48);
                    xn_root_add(xn_t48);
                            xn_root_add(xn_t48);
                                    xn_root_add(xn_t48);
                                    rt_string *xn_t49 = xn_concat(xn_t47, xn_t48);
xn_root_add(xn_t49);
    xn_root_add(xn_t49);
            xn_root_add(xn_t49);
                    xn_root_add(xn_t49);
                            xn_root_add(xn_t49);
                                    xn_root_add(xn_t49);
                                    xn_root_release(b);
                                    rt_release(b);
                                    b = xn_t49;
                                    xn_root_hold(b);
                                    xn_gc_safepoint();
                                        {
                                        xn_root_restore(xn_t46);
                                        }

                                } else {
                                    rt_string *xn_t51 = rt_retain(c);
xn_root_add(xn_t51);
    xn_root_add(xn_t51);
            xn_root_add(xn_t51);
                    xn_root_add(xn_t51);
                            xn_root_add(xn_t51);
                                    xn_root_add(xn_t51);
                                    rt_string *xn_t52 = rt_string_from_c("\r");
xn_root_add(xn_t52);
    xn_root_add(xn_t52);
            xn_root_add(xn_t52);
                    xn_root_add(xn_t52);
                            xn_root_add(xn_t52);
                                    xn_root_add(xn_t52);
                                        if ((xn_str_eq(xn_t51, xn_t52))) {
                                            size_t xn_t53 = xn_root_mark();
                                            #line 604 "impl/lib/b2/xparser.x"
                                            rt_string *xn_t54 = rt_retain(b);
xn_root_add(xn_t54);
    xn_root_add(xn_t54);
            xn_root_add(xn_t54);
                    xn_root_add(xn_t54);
                            xn_root_add(xn_t54);
                                    xn_root_add(xn_t54);
                                            xn_root_add(xn_t54);
                                            rt_string *xn_t55 = rt_string_from_c("\\r");
xn_root_add(xn_t55);
    xn_root_add(xn_t55);
            xn_root_add(xn_t55);
                    xn_root_add(xn_t55);
                            xn_root_add(xn_t55);
                                    xn_root_add(xn_t55);
                                            xn_root_add(xn_t55);
                                            rt_string *xn_t56 = xn_concat(xn_t54, xn_t55);
xn_root_add(xn_t56);
    xn_root_add(xn_t56);
            xn_root_add(xn_t56);
                    xn_root_add(xn_t56);
                            xn_root_add(xn_t56);
                                    xn_root_add(xn_t56);
                                            xn_root_add(xn_t56);
                                            xn_root_release(b);
                                            rt_release(b);
                                            b = xn_t56;
                                            xn_root_hold(b);
                                            xn_gc_safepoint();
                                                {
                                                xn_root_restore(xn_t53);
                                                }

                                        } else {
                                            rt_string *xn_t58 = rt_retain(c);
xn_root_add(xn_t58);
    xn_root_add(xn_t58);
            xn_root_add(xn_t58);
                    xn_root_add(xn_t58);
                            xn_root_add(xn_t58);
                                    xn_root_add(xn_t58);
                                            xn_root_add(xn_t58);
                                            rt_string *xn_t59 = rt_retain(nul);
xn_root_add(xn_t59);
    xn_root_add(xn_t59);
            xn_root_add(xn_t59);
                    xn_root_add(xn_t59);
                            xn_root_add(xn_t59);
                                    xn_root_add(xn_t59);
                                            xn_root_add(xn_t59);
                                                if ((xn_str_eq(xn_t58, xn_t59))) {
                                                    size_t xn_t60 = xn_root_mark();
                                                    #line 605 "impl/lib/b2/xparser.x"
                                                    rt_string *xn_t61 = rt_retain(b);
xn_root_add(xn_t61);
    xn_root_add(xn_t61);
            xn_root_add(xn_t61);
                    xn_root_add(xn_t61);
                            xn_root_add(xn_t61);
                                    xn_root_add(xn_t61);
                                            xn_root_add(xn_t61);
                                                    xn_root_add(xn_t61);
                                                    rt_string *xn_t62 = rt_string_from_c("\\x00");
xn_root_add(xn_t62);
    xn_root_add(xn_t62);
            xn_root_add(xn_t62);
                    xn_root_add(xn_t62);
                            xn_root_add(xn_t62);
                                    xn_root_add(xn_t62);
                                            xn_root_add(xn_t62);
                                                    xn_root_add(xn_t62);
                                                    rt_string *xn_t63 = xn_concat(xn_t61, xn_t62);
xn_root_add(xn_t63);
    xn_root_add(xn_t63);
            xn_root_add(xn_t63);
                    xn_root_add(xn_t63);
                            xn_root_add(xn_t63);
                                    xn_root_add(xn_t63);
                                            xn_root_add(xn_t63);
                                                    xn_root_add(xn_t63);
                                                    xn_root_release(b);
                                                    rt_release(b);
                                                    b = xn_t63;
                                                    xn_root_hold(b);
                                                    xn_gc_safepoint();
                                                        {
                                                        xn_root_restore(xn_t60);
                                                        }

                                                } else {
                                                    size_t xn_t64 = xn_root_mark();
                                                    #line 606 "impl/lib/b2/xparser.x"
                                                    rt_string *xn_t65 = rt_retain(b);
xn_root_add(xn_t65);
    xn_root_add(xn_t65);
            xn_root_add(xn_t65);
                    xn_root_add(xn_t65);
                            xn_root_add(xn_t65);
                                    xn_root_add(xn_t65);
                                            xn_root_add(xn_t65);
                                                    xn_root_add(xn_t65);
                                                    rt_string *xn_t66 = rt_retain(c);
xn_root_add(xn_t66);
    xn_root_add(xn_t66);
            xn_root_add(xn_t66);
                    xn_root_add(xn_t66);
                            xn_root_add(xn_t66);
                                    xn_root_add(xn_t66);
                                            xn_root_add(xn_t66);
                                                    xn_root_add(xn_t66);
                                                    rt_string *xn_t67 = xn_concat(xn_t65, xn_t66);
xn_root_add(xn_t67);
    xn_root_add(xn_t67);
            xn_root_add(xn_t67);
                    xn_root_add(xn_t67);
                            xn_root_add(xn_t67);
                                    xn_root_add(xn_t67);
                                            xn_root_add(xn_t67);
                                                    xn_root_add(xn_t67);
                                                    xn_root_release(b);
                                                    rt_release(b);
                                                    b = xn_t67;
                                                    xn_root_hold(b);
                                                    xn_gc_safepoint();
                                                        {
                                                        xn_root_restore(xn_t64);
                                                        }

                                                }
                                        }
                                }
                        }
                }
        }
    #line 607 "impl/lib/b2/xparser.x"
    i = (i + 1);
        {
        rt_release(c);
        }
        {
        xn_root_restore(xn_t21);
        }

    xn_gc_safepoint();
    }
#line 609 "impl/lib/b2/xparser.x"
rt_string *xn_t68 = rt_retain(b);
xn_root_add(xn_t68);
xn_root_add(xn_t68);
rt_string *xn_t69 = rt_string_from_c("\"");
xn_root_add(xn_t69);
xn_root_add(xn_t69);
rt_string *xn_t70 = xn_concat(xn_t68, xn_t69);
xn_root_add(xn_t70);
xn_root_add(xn_t70);
    {
rt_release(nul);
    }
    {
rt_release(b);
    }
    {
xn_root_restore(xn_t18);
    }

return xn_t70;
xn_root_release(b);
}

rt_string * xn_dumpTok(xn_Cls_Tok * xn_p_t) {
size_t xn_t71 = xn_root_mark();
xn_root_add(xn_p_t);
#line 613 "impl/lib/b2/xparser.x"
rt_string *xn_t72 = rt_string_from_c("(Token (Kind ");
xn_root_add(xn_t72);
rt_string *xn_t73 = xn_str_int(xn_p_t->kind);
xn_root_add(xn_t73);
rt_string *xn_t74 = xn_concat(xn_t72, xn_t73);
xn_root_add(xn_t74);
rt_string *xn_t75 = rt_string_from_c(") (Text ");
xn_root_add(xn_t75);
rt_string *xn_t76 = xn_concat(xn_t74, xn_t75);
xn_root_add(xn_t76);
rt_string *xn_t77 = rt_retain(xn_p_t->text);
xn_root_add(xn_t77);
rt_string *xn_t78 = xn_q(xn_t77);
xn_root_add(xn_t78);
rt_string *b = xn_concat(xn_t76, xn_t78);
xn_root_add(b);
xn_root_add(b);
xn_gc_safepoint();
#line 614 "impl/lib/b2/xparser.x"
rt_string *xn_t80 = rt_retain(b);
xn_root_add(xn_t80);
rt_string *xn_t81 = rt_string_from_c(") (Pos (Pos (Line ");
xn_root_add(xn_t81);
rt_string *xn_t82 = xn_concat(xn_t80, xn_t81);
xn_root_add(xn_t82);
rt_string *xn_t83 = xn_str_int(xn_p_t->line);
xn_root_add(xn_t83);
rt_string *xn_t84 = xn_concat(xn_t82, xn_t83);
xn_root_add(xn_t84);
rt_string *xn_t85 = rt_string_from_c(") (Col ");
xn_root_add(xn_t85);
rt_string *xn_t86 = xn_concat(xn_t84, xn_t85);
xn_root_add(xn_t86);
rt_string *xn_t87 = xn_str_int(xn_p_t->col);
xn_root_add(xn_t87);
rt_string *xn_t88 = xn_concat(xn_t86, xn_t87);
xn_root_add(xn_t88);
rt_string *xn_t89 = rt_string_from_c("))) (Str ");
xn_root_add(xn_t89);
rt_string *xn_t90 = xn_concat(xn_t88, xn_t89);
xn_root_add(xn_t90);
rt_string *xn_t91 = xn_str_int(xn_p_t->str);
xn_root_add(xn_t91);
rt_string *xn_t92 = xn_concat(xn_t90, xn_t91);
xn_root_add(xn_t92);
rt_release(b);
b = xn_t92;
xn_root_add(b);
xn_gc_safepoint();
#line 615 "impl/lib/b2/xparser.x"
rt_string *xn_t93 = rt_retain(b);
xn_root_add(xn_t93);
rt_string *xn_t94 = rt_string_from_c(") (Value ");
xn_root_add(xn_t94);
rt_string *xn_t95 = xn_concat(xn_t93, xn_t94);
xn_root_add(xn_t95);
rt_string *xn_t96 = rt_retain(xn_p_t->value);
xn_root_add(xn_t96);
rt_string *xn_t97 = xn_q(xn_t96);
xn_root_add(xn_t97);
rt_string *xn_t98 = xn_concat(xn_t95, xn_t97);
xn_root_add(xn_t98);
rt_string *xn_t99 = rt_string_from_c(") (Segs (slice");
xn_root_add(xn_t99);
rt_string *xn_t100 = xn_concat(xn_t98, xn_t99);
xn_root_add(xn_t100);
rt_release(b);
b = xn_t100;
xn_root_add(b);
xn_gc_safepoint();
#line 616 "impl/lib/b2/xparser.x"
int64_t i = 0;
#line 617 "impl/lib/b2/xparser.x"
    while (((i < ((int64_t)xn_p_t->segs->len)))) {
    size_t xn_t101 = xn_root_mark();
    #line 617 "impl/lib/b2/xparser.x"
    rt_string *xn_t102 = rt_retain(b);
xn_root_add(xn_t102);
    xn_root_add(xn_t102);
    rt_string *xn_t103 = rt_string_from_c(" ");
xn_root_add(xn_t103);
    xn_root_add(xn_t103);
    rt_string *xn_t104 = xn_concat(xn_t102, xn_t103);
xn_root_add(xn_t104);
    xn_root_add(xn_t104);
    rt_string *xn_t105 = rt_retain(xn_arr_s_get(xn_p_t->segs, i));
xn_root_add(xn_t105);
    xn_root_add(xn_t105);
    rt_string *xn_t106 = xn_q(xn_t105);
xn_root_add(xn_t106);
    xn_root_add(xn_t106);
    rt_string *xn_t107 = xn_concat(xn_t104, xn_t106);
xn_root_add(xn_t107);
    xn_root_add(xn_t107);
    xn_root_release(b);
    rt_release(b);
    b = xn_t107;
    xn_root_hold(b);
    xn_gc_safepoint();
    #line 617 "impl/lib/b2/xparser.x"
    i = (i + 1);
        {
        xn_root_restore(xn_t101);
        }

    xn_gc_safepoint();
    }
#line 618 "impl/lib/b2/xparser.x"
rt_string *xn_t108 = rt_retain(b);
xn_root_add(xn_t108);
rt_string *xn_t109 = rt_string_from_c(")) (Interps (slice");
xn_root_add(xn_t109);
rt_string *xn_t110 = xn_concat(xn_t108, xn_t109);
xn_root_add(xn_t110);
rt_release(b);
b = xn_t110;
xn_root_add(b);
xn_gc_safepoint();
#line 619 "impl/lib/b2/xparser.x"
i = 0;
#line 620 "impl/lib/b2/xparser.x"
    while (((i < ((int64_t)xn_p_t->interps->len)))) {
    size_t xn_t111 = xn_root_mark();
    #line 620 "impl/lib/b2/xparser.x"
    rt_string *xn_t112 = rt_retain(b);
xn_root_add(xn_t112);
    xn_root_add(xn_t112);
    rt_string *xn_t113 = rt_string_from_c(" ");
xn_root_add(xn_t113);
    xn_root_add(xn_t113);
    rt_string *xn_t114 = xn_concat(xn_t112, xn_t113);
xn_root_add(xn_t114);
    xn_root_add(xn_t114);
    rt_string *xn_t115 = rt_retain(xn_arr_s_get(xn_p_t->interps, i));
xn_root_add(xn_t115);
    xn_root_add(xn_t115);
    rt_string *xn_t116 = xn_q(xn_t115);
xn_root_add(xn_t116);
    xn_root_add(xn_t116);
    rt_string *xn_t117 = xn_concat(xn_t114, xn_t116);
xn_root_add(xn_t117);
    xn_root_add(xn_t117);
    xn_root_release(b);
    rt_release(b);
    b = xn_t117;
    xn_root_hold(b);
    xn_gc_safepoint();
    #line 620 "impl/lib/b2/xparser.x"
    i = (i + 1);
        {
        xn_root_restore(xn_t111);
        }

    xn_gc_safepoint();
    }
#line 621 "impl/lib/b2/xparser.x"
rt_string *xn_t118 = rt_retain(b);
xn_root_add(xn_t118);
rt_string *xn_t119 = rt_string_from_c(")) (Char ");
xn_root_add(xn_t119);
rt_string *xn_t120 = xn_concat(xn_t118, xn_t119);
xn_root_add(xn_t120);
rt_string *xn_t121 = xn_str_int(xn_p_t->ch);
xn_root_add(xn_t121);
rt_string *xn_t122 = xn_concat(xn_t120, xn_t121);
xn_root_add(xn_t122);
rt_string *xn_t123 = rt_string_from_c(") (Base ");
xn_root_add(xn_t123);
rt_string *xn_t124 = xn_concat(xn_t122, xn_t123);
xn_root_add(xn_t124);
rt_string *xn_t125 = xn_str_int(xn_p_t->base);
xn_root_add(xn_t125);
rt_string *xn_t126 = xn_concat(xn_t124, xn_t125);
xn_root_add(xn_t126);
rt_string *xn_t127 = rt_string_from_c(") (Suffix ");
xn_root_add(xn_t127);
rt_string *xn_t128 = xn_concat(xn_t126, xn_t127);
xn_root_add(xn_t128);
rt_string *xn_t129 = rt_retain(xn_p_t->suffix);
xn_root_add(xn_t129);
rt_string *xn_t130 = xn_q(xn_t129);
xn_root_add(xn_t130);
rt_string *xn_t131 = xn_concat(xn_t128, xn_t130);
xn_root_add(xn_t131);
rt_string *xn_t132 = rt_string_from_c(") (HasSuffixF ");
xn_root_add(xn_t132);
rt_string *xn_t133 = xn_concat(xn_t131, xn_t132);
xn_root_add(xn_t133);
rt_release(b);
b = xn_t133;
xn_root_add(b);
xn_gc_safepoint();
#line 622 "impl/lib/b2/xparser.x"
    if ((((int)(xn_p_t->hasSuffixF)))) {
        size_t xn_t134 = xn_root_mark();
        #line 622 "impl/lib/b2/xparser.x"
        rt_string *xn_t135 = rt_retain(b);
xn_root_add(xn_t135);
        xn_root_add(xn_t135);
        rt_string *xn_t136 = rt_string_from_c("true");
xn_root_add(xn_t136);
        xn_root_add(xn_t136);
        rt_string *xn_t137 = xn_concat(xn_t135, xn_t136);
xn_root_add(xn_t137);
        xn_root_add(xn_t137);
        xn_root_release(b);
        rt_release(b);
        b = xn_t137;
        xn_root_hold(b);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t134);
            }

    } else {
        size_t xn_t138 = xn_root_mark();
        #line 622 "impl/lib/b2/xparser.x"
        rt_string *xn_t139 = rt_retain(b);
xn_root_add(xn_t139);
        xn_root_add(xn_t139);
        rt_string *xn_t140 = rt_string_from_c("false");
xn_root_add(xn_t140);
        xn_root_add(xn_t140);
        rt_string *xn_t141 = xn_concat(xn_t139, xn_t140);
xn_root_add(xn_t141);
        xn_root_add(xn_t141);
        xn_root_release(b);
        rt_release(b);
        b = xn_t141;
        xn_root_hold(b);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t138);
            }

    }
#line 623 "impl/lib/b2/xparser.x"
rt_string *xn_t142 = rt_retain(b);
xn_root_add(xn_t142);
xn_root_add(xn_t142);
rt_string *xn_t143 = rt_string_from_c("))");
xn_root_add(xn_t143);
xn_root_add(xn_t143);
rt_string *xn_t144 = xn_concat(xn_t142, xn_t143);
xn_root_add(xn_t144);
xn_root_add(xn_t144);
    {
rt_release(b);
    }
    {
xn_root_restore(xn_t71);
    }

return xn_t144;
xn_root_release(b);
}

rt_string * xn_P(int64_t xn_p_l, int64_t xn_p_c) {
size_t xn_t145 = xn_root_mark();
#line 636 "impl/lib/b2/xparser.x"
rt_string *xn_t146 = rt_string_from_c("(P (Pos (Line ");
xn_root_add(xn_t146);
xn_root_add(xn_t146);
rt_string *xn_t147 = xn_str_int(xn_p_l);
xn_root_add(xn_t147);
xn_root_add(xn_t147);
rt_string *xn_t148 = xn_concat(xn_t146, xn_t147);
xn_root_add(xn_t148);
xn_root_add(xn_t148);
rt_string *xn_t149 = rt_string_from_c(") (Col ");
xn_root_add(xn_t149);
xn_root_add(xn_t149);
rt_string *xn_t150 = xn_concat(xn_t148, xn_t149);
xn_root_add(xn_t150);
xn_root_add(xn_t150);
rt_string *xn_t151 = xn_str_int(xn_p_c);
xn_root_add(xn_t151);
xn_root_add(xn_t151);
rt_string *xn_t152 = xn_concat(xn_t150, xn_t151);
xn_root_add(xn_t152);
xn_root_add(xn_t152);
rt_string *xn_t153 = rt_string_from_c(")))");
xn_root_add(xn_t153);
xn_root_add(xn_t153);
rt_string *xn_t154 = xn_concat(xn_t152, xn_t153);
xn_root_add(xn_t154);
xn_root_add(xn_t154);
    {
xn_root_restore(xn_t145);
    }

return xn_t154;
}

rt_string * xn_F(rt_string * xn_p_n, rt_string * xn_p_v) {
size_t xn_t155 = xn_root_mark();
xn_root_add(xn_p_n);
xn_root_add(xn_p_v);
#line 640 "impl/lib/b2/xparser.x"
rt_string *xn_t156 = rt_string_from_c("(");
xn_root_add(xn_t156);
xn_root_add(xn_t156);
rt_string *xn_t157 = rt_retain(xn_p_n);
xn_root_add(xn_t157);
xn_root_add(xn_t157);
rt_string *xn_t158 = xn_concat(xn_t156, xn_t157);
xn_root_add(xn_t158);
xn_root_add(xn_t158);
rt_string *xn_t159 = rt_string_from_c(" ");
xn_root_add(xn_t159);
xn_root_add(xn_t159);
rt_string *xn_t160 = xn_concat(xn_t158, xn_t159);
xn_root_add(xn_t160);
xn_root_add(xn_t160);
rt_string *xn_t161 = rt_retain(xn_p_v);
xn_root_add(xn_t161);
xn_root_add(xn_t161);
rt_string *xn_t162 = xn_concat(xn_t160, xn_t161);
xn_root_add(xn_t162);
xn_root_add(xn_t162);
rt_string *xn_t163 = rt_string_from_c(")");
xn_root_add(xn_t163);
xn_root_add(xn_t163);
rt_string *xn_t164 = xn_concat(xn_t162, xn_t163);
xn_root_add(xn_t164);
xn_root_add(xn_t164);
    {
xn_root_restore(xn_t155);
    }

return xn_t164;
}

rt_string * xn_SL(xn_arr_s * xn_p_xs) {
size_t xn_t165 = xn_root_mark();
xn_root_add(xn_p_xs);
#line 644 "impl/lib/b2/xparser.x"
    if (((((int64_t)xn_p_xs->len) == 0))) {
        size_t xn_t166 = xn_root_mark();
        #line 644 "impl/lib/b2/xparser.x"
        rt_string *xn_t167 = rt_string_from_c("(slice)");
xn_root_add(xn_t167);
        xn_root_add(xn_t167);
        xn_root_add(xn_t167);
            {
        xn_root_restore(xn_t166);
            }
            {
        xn_root_restore(xn_t165);
            }

        return xn_t167;

    }
#line 645 "impl/lib/b2/xparser.x"
rt_string *s = rt_string_from_c("(slice");
xn_root_add(s);
xn_root_add(s);
xn_gc_safepoint();
#line 646 "impl/lib/b2/xparser.x"
int64_t i = 0;
#line 647 "impl/lib/b2/xparser.x"
    while (((i < ((int64_t)xn_p_xs->len)))) {
    size_t xn_t169 = xn_root_mark();
    #line 648 "impl/lib/b2/xparser.x"
    rt_string *xn_t170 = rt_retain(s);
xn_root_add(xn_t170);
    xn_root_add(xn_t170);
    rt_string *xn_t171 = rt_string_from_c(" ");
xn_root_add(xn_t171);
    xn_root_add(xn_t171);
    rt_string *xn_t172 = xn_concat(xn_t170, xn_t171);
xn_root_add(xn_t172);
    xn_root_add(xn_t172);
    rt_string *xn_t173 = rt_retain(xn_arr_s_get(xn_p_xs, i));
xn_root_add(xn_t173);
    xn_root_add(xn_t173);
    rt_string *xn_t174 = xn_concat(xn_t172, xn_t173);
xn_root_add(xn_t174);
    xn_root_add(xn_t174);
    xn_root_release(s);
    rt_release(s);
    s = xn_t174;
    xn_root_hold(s);
    xn_gc_safepoint();
    #line 649 "impl/lib/b2/xparser.x"
    i = (i + 1);
        {
        xn_root_restore(xn_t169);
        }

    xn_gc_safepoint();
    }
#line 651 "impl/lib/b2/xparser.x"
rt_string *xn_t175 = rt_retain(s);
xn_root_add(xn_t175);
xn_root_add(xn_t175);
rt_string *xn_t176 = rt_string_from_c(")");
xn_root_add(xn_t176);
xn_root_add(xn_t176);
rt_string *xn_t177 = xn_concat(xn_t175, xn_t176);
xn_root_add(xn_t177);
xn_root_add(xn_t177);
    {
rt_release(s);
    }
    {
xn_root_restore(xn_t165);
    }

return xn_t177;
xn_root_release(s);
}

rt_string * xn_SLS(xn_arr_s * xn_p_xs) {
size_t xn_t178 = xn_root_mark();
xn_root_add(xn_p_xs);
#line 655 "impl/lib/b2/xparser.x"
    if (((((int64_t)xn_p_xs->len) == 0))) {
        size_t xn_t179 = xn_root_mark();
        #line 655 "impl/lib/b2/xparser.x"
        rt_string *xn_t180 = rt_string_from_c("(slice)");
xn_root_add(xn_t180);
        xn_root_add(xn_t180);
        xn_root_add(xn_t180);
            {
        xn_root_restore(xn_t179);
            }
            {
        xn_root_restore(xn_t178);
            }

        return xn_t180;

    }
#line 656 "impl/lib/b2/xparser.x"
rt_string *s = rt_string_from_c("(slice");
xn_root_add(s);
xn_root_add(s);
xn_gc_safepoint();
#line 657 "impl/lib/b2/xparser.x"
int64_t i = 0;
#line 658 "impl/lib/b2/xparser.x"
    while (((i < ((int64_t)xn_p_xs->len)))) {
    size_t xn_t182 = xn_root_mark();
    #line 658 "impl/lib/b2/xparser.x"
    rt_string *xn_t183 = rt_retain(s);
xn_root_add(xn_t183);
    xn_root_add(xn_t183);
    rt_string *xn_t184 = rt_string_from_c(" ");
xn_root_add(xn_t184);
    xn_root_add(xn_t184);
    rt_string *xn_t185 = xn_concat(xn_t183, xn_t184);
xn_root_add(xn_t185);
    xn_root_add(xn_t185);
    rt_string *xn_t186 = rt_retain(xn_arr_s_get(xn_p_xs, i));
xn_root_add(xn_t186);
    xn_root_add(xn_t186);
    rt_string *xn_t187 = xn_q(xn_t186);
xn_root_add(xn_t187);
    xn_root_add(xn_t187);
    rt_string *xn_t188 = xn_concat(xn_t185, xn_t187);
xn_root_add(xn_t188);
    xn_root_add(xn_t188);
    xn_root_release(s);
    rt_release(s);
    s = xn_t188;
    xn_root_hold(s);
    xn_gc_safepoint();
    #line 658 "impl/lib/b2/xparser.x"
    i = (i + 1);
        {
        xn_root_restore(xn_t182);
        }

    xn_gc_safepoint();
    }
#line 659 "impl/lib/b2/xparser.x"
rt_string *xn_t189 = rt_retain(s);
xn_root_add(xn_t189);
xn_root_add(xn_t189);
rt_string *xn_t190 = rt_string_from_c(")");
xn_root_add(xn_t190);
xn_root_add(xn_t190);
rt_string *xn_t191 = xn_concat(xn_t189, xn_t190);
xn_root_add(xn_t191);
xn_root_add(xn_t191);
    {
rt_release(s);
    }
    {
xn_root_restore(xn_t178);
    }

return xn_t191;
xn_root_release(s);
}

rt_string * xn_B(int xn_p_v) {
size_t xn_t192 = xn_root_mark();
#line 663 "impl/lib/b2/xparser.x"
    if ((xn_p_v)) {
        size_t xn_t193 = xn_root_mark();
        #line 663 "impl/lib/b2/xparser.x"
        rt_string *xn_t194 = rt_string_from_c("true");
xn_root_add(xn_t194);
        xn_root_add(xn_t194);
        xn_root_add(xn_t194);
            {
        xn_root_restore(xn_t193);
            }
            {
        xn_root_restore(xn_t192);
            }

        return xn_t194;

    }
#line 664 "impl/lib/b2/xparser.x"
rt_string *xn_t195 = rt_string_from_c("false");
xn_root_add(xn_t195);
xn_root_add(xn_t195);
    {
xn_root_restore(xn_t192);
    }

return xn_t195;
}

int64_t xn_main(xn_arr_s * xn_p_args) {
size_t xn_t196 = xn_root_mark();
xn_root_add(xn_p_args);
#line 2161 "impl/lib/b2/xparser.x"
    if (((((int64_t)xn_p_args->len) == 0))) {
        size_t xn_t197 = xn_root_mark();
        #line 2162 "impl/lib/b2/xparser.x"
        rt_string *xn_t198 = rt_string_from_c("xparser: 需要源码字符串或 --file <path>");
xn_root_add(xn_t198);
        xn_root_add(xn_t198);
        xn_print_str(xn_t198);
        rt_release(xn_t198);
        #line 2163 "impl/lib/b2/xparser.x"
        int64_t xn_t199 = 2;
            {
        xn_root_restore(xn_t197);
            }
            {
        xn_root_restore(xn_t196);
            }

        return xn_t199;

    }
#line 2165 "impl/lib/b2/xparser.x"
int diagMode = 0;
#line 2166 "impl/lib/b2/xparser.x"
int64_t ai = 0;
#line 2167 "impl/lib/b2/xparser.x"
rt_string *xn_t200 = rt_retain(xn_arr_s_get(xn_p_args, ai));
xn_root_add(xn_t200);
rt_string *xn_t201 = rt_string_from_c("--diags");
xn_root_add(xn_t201);
    if ((xn_str_eq(xn_t200, xn_t201))) {
        size_t xn_t202 = xn_root_mark();
        #line 2168 "impl/lib/b2/xparser.x"
        diagMode = 1;
        #line 2169 "impl/lib/b2/xparser.x"
        ai = (ai + 1);
        #line 2170 "impl/lib/b2/xparser.x"
            if (((ai >= ((int64_t)xn_p_args->len)))) {
                size_t xn_t203 = xn_root_mark();
                #line 2170 "impl/lib/b2/xparser.x"
                int64_t xn_t204 = 2;
                    {
                xn_root_restore(xn_t203);
                    }
                    {
                xn_root_restore(xn_t202);
                    }
                    {
                xn_root_restore(xn_t196);
                    }

                return xn_t204;

            }
            {
            xn_root_restore(xn_t202);
            }

    }
#line 2172 "impl/lib/b2/xparser.x"
rt_string *src = rt_string_from_c("");
xn_root_add(src);
xn_root_add(src);
xn_gc_safepoint();
#line 2173 "impl/lib/b2/xparser.x"
rt_string *xn_t206 = rt_retain(xn_arr_s_get(xn_p_args, ai));
xn_root_add(xn_t206);
rt_string *xn_t207 = rt_string_from_c("--file");
xn_root_add(xn_t207);
    if ((xn_str_eq(xn_t206, xn_t207))) {
        size_t xn_t208 = xn_root_mark();
        #line 2174 "impl/lib/b2/xparser.x"
            if ((((ai + 1) >= ((int64_t)xn_p_args->len)))) {
                size_t xn_t209 = xn_root_mark();
                #line 2174 "impl/lib/b2/xparser.x"
                int64_t xn_t210 = 2;
                    {
                xn_root_restore(xn_t209);
                    }
                    {
                xn_root_restore(xn_t208);
                    }
                    {
                rt_release(src);
                    }
                    {
                xn_root_restore(xn_t196);
                    }

                return xn_t210;

            }
        #line 2176 "impl/lib/b2/xparser.x"
        rt_string *path = rt_retain(xn_arr_s_get(xn_p_args, (ai + 1)));
xn_root_add(path);
        xn_root_add(path);
        xn_root_add(path);
        xn_gc_safepoint();
        #line 2177 "impl/lib/b2/xparser.x"
        rt_string *xn_t212 = rt_retain(path);
xn_root_add(xn_t212);
        xn_root_add(xn_t212);
        rt_string *xn_t213 = xn_readFileText(xn_t212);
xn_root_add(xn_t213);
        xn_root_add(xn_t213);
        xn_root_release(src);
        rt_release(src);
        src = xn_t213;
        xn_root_hold(src);
        xn_gc_safepoint();
            {
            rt_release(path);
            }
            {
            xn_root_restore(xn_t208);
            }

    } else {
        size_t xn_t214 = xn_root_mark();
        #line 2179 "impl/lib/b2/xparser.x"
        rt_string *xn_t215 = rt_retain(xn_arr_s_get(xn_p_args, ai));
xn_root_add(xn_t215);
        xn_root_add(xn_t215);
        xn_root_release(src);
        rt_release(src);
        src = xn_t215;
        xn_root_hold(src);
        xn_gc_safepoint();
            {
            xn_root_restore(xn_t214);
            }

    }
#line 2181 "impl/lib/b2/xparser.x"
rt_string *xn_t216 = rt_retain(src);
xn_root_add(xn_t216);
xn_Cls_Lexer * l = xn_Cls_Lexer_new(xn_t216);
xn_root_add(l);
xn_root_add(l);
xn_gc_safepoint();
#line 2182 "impl/lib/b2/xparser.x"
xn_arr_o_Tok *xn_t217 = xn_arr_o_Tok_new(0);
xn_root_add(xn_t217);
xn_arr_o_Tok * ts = xn_t217;
xn_root_add(ts);
xn_root_add(ts);
xn_gc_safepoint();
#line 2183 "impl/lib/b2/xparser.x"
int go = 1;
#line 2184 "impl/lib/b2/xparser.x"
    while ((go)) {
    size_t xn_t218 = xn_root_mark();
    #line 2185 "impl/lib/b2/xparser.x"
    xn_Cls_Tok * t = xn_Cls_Lexer_next(l);
xn_root_add(t);
    xn_root_add(t);
    xn_root_add(t);
    xn_gc_safepoint();
    #line 2186 "impl/lib/b2/xparser.x"
    xn_arr_o_Tok_push(ts, t);
    #line 2187 "impl/lib/b2/xparser.x"
        if (((t->kind == 0))) {
            size_t xn_t219 = xn_root_mark();
            #line 2187 "impl/lib/b2/xparser.x"
            go = 0;
                {
                xn_root_restore(xn_t219);
                }

        }
        {
        xn_root_restore(xn_t218);
        }

    xn_gc_safepoint();
    }
#line 2189 "impl/lib/b2/xparser.x"
xn_Cls_Parser * p = xn_Cls_Parser_new(ts);
xn_root_add(p);
xn_root_add(p);
xn_gc_safepoint();
#line 2191 "impl/lib/b2/xparser.x"
int64_t ldi = 0;
#line 2192 "impl/lib/b2/xparser.x"
    while (((ldi < ((int64_t)l->diags->len)))) {
    size_t xn_t220 = xn_root_mark();
    #line 2192 "impl/lib/b2/xparser.x"
    xn_Cls_Diag * xn_t221 = xn_arr_o_Diag_get(l->diags, ldi);
xn_root_add(xn_t221);
    xn_root_add(xn_t221);
    xn_arr_o_Diag_push(p->diags, xn_t221);
    #line 2192 "impl/lib/b2/xparser.x"
    ldi = (ldi + 1);
        {
        xn_root_restore(xn_t220);
        }

    xn_gc_safepoint();
    }
#line 2193 "impl/lib/b2/xparser.x"
rt_string *res = xn_Cls_Parser_parseUnit(p);
xn_root_add(res);
xn_root_add(res);
xn_gc_safepoint();
#line 2194 "impl/lib/b2/xparser.x"
    if ((diagMode)) {
        size_t xn_t223 = xn_root_mark();
        #line 2195 "impl/lib/b2/xparser.x"
        rt_string *xn_t224 = rt_string_from_c("xnast-diags-simple v1");
xn_root_add(xn_t224);
        xn_root_add(xn_t224);
        xn_print_str(xn_t224);
        rt_release(xn_t224);
        #line 2196 "impl/lib/b2/xparser.x"
        int64_t i = 0;
        #line 2197 "impl/lib/b2/xparser.x"
            while (((i < ((int64_t)p->diags->len)))) {
            size_t xn_t225 = xn_root_mark();
            #line 2198 "impl/lib/b2/xparser.x"
            xn_Cls_Diag * d = xn_arr_o_Diag_get(p->diags, i);
xn_root_add(d);
        xn_root_add(d);
            xn_root_add(d);
            xn_root_add(d);
            xn_gc_safepoint();
            #line 2199 "impl/lib/b2/xparser.x"
            rt_string *xn_t226 = rt_retain(d->code);
xn_root_add(xn_t226);
        xn_root_add(xn_t226);
            xn_root_add(xn_t226);
            rt_string *xn_t227 = rt_string_from_c(" ");
xn_root_add(xn_t227);
        xn_root_add(xn_t227);
            xn_root_add(xn_t227);
            rt_string *xn_t228 = xn_concat(xn_t226, xn_t227);
xn_root_add(xn_t228);
        xn_root_add(xn_t228);
            xn_root_add(xn_t228);
            rt_string *xn_t229 = xn_str_int(d->line);
xn_root_add(xn_t229);
        xn_root_add(xn_t229);
            xn_root_add(xn_t229);
            rt_string *xn_t230 = xn_concat(xn_t228, xn_t229);
xn_root_add(xn_t230);
        xn_root_add(xn_t230);
            xn_root_add(xn_t230);
            rt_string *xn_t231 = rt_string_from_c(" ");
xn_root_add(xn_t231);
        xn_root_add(xn_t231);
            xn_root_add(xn_t231);
            rt_string *xn_t232 = xn_concat(xn_t230, xn_t231);
xn_root_add(xn_t232);
        xn_root_add(xn_t232);
            xn_root_add(xn_t232);
            rt_string *xn_t233 = xn_str_int(d->col);
xn_root_add(xn_t233);
        xn_root_add(xn_t233);
            xn_root_add(xn_t233);
            rt_string *xn_t234 = xn_concat(xn_t232, xn_t233);
xn_root_add(xn_t234);
        xn_root_add(xn_t234);
            xn_root_add(xn_t234);
            xn_print_str(xn_t234);
            rt_release(xn_t234);
            #line 2200 "impl/lib/b2/xparser.x"
            i = (i + 1);
                {
                xn_root_restore(xn_t225);
                }

            xn_gc_safepoint();
            }
        #line 2202 "impl/lib/b2/xparser.x"
        int64_t xn_t235 = 0;
            {
        xn_root_restore(xn_t223);
            }
            {
        rt_release(res);
            }
            {
        rt_release(src);
            }
            {
        xn_root_restore(xn_t196);
            }

        return xn_t235;

    }
#line 2204 "impl/lib/b2/xparser.x"
rt_string *xn_t236 = rt_retain(res);
xn_root_add(xn_t236);
xn_print_str(xn_t236);
rt_release(xn_t236);
#line 2205 "impl/lib/b2/xparser.x"
int64_t xn_t237 = 0;
    {
rt_release(res);
    }
    {
rt_release(src);
    }
    {
xn_root_restore(xn_t196);
    }

return xn_t237;
xn_root_release(src);
}

int main(int argc, char **argv) {
    xrt_runtime_init();
    xn_init_vtables();
    xn_init_enums();
    xn_arr_s *xn_args = xn_arr_s_new((size_t)(argc > 1 ? argc - 1 : 0));
    for (int i = 1; i < argc; i++) {
        rt_string *xn_av = rt_string_from_c(argv[i]);
        xn_arr_s_push(xn_args, xn_av);
        rt_release(xn_av);
    }
    int64_t xn_r = xn_main(xn_args);
    rt_gc_collect();
    rt_quarantine_flush();
    return (int)xn_r;
}
