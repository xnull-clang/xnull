/* 由 XNull 编译器生成（M4.1 代码生成）。 */
#include "rt.h"
#include "rt_gc.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static rt_string *xn_alloc_str(size_t n) {
    rt_string *s = malloc(sizeof(rt_string) + n + 1);
    if (s == NULL) { abort(); }
    memset(s, 0, sizeof(rt_string) + n + 1);
    s->hdr.kind = RT_KIND_ARC;
    s->hdr.type = &RT_TYPE_STRING;
    atomic_init(&s->hdr.refcount, 1);
    s->len = n;
    s->bytes[n] = 0;
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
/* 绑定层支撑代码（由 .xfb 注册表生成；只包含 xrt.h，S7 §6.1 / INV-FFI-7） */
#include "xrt.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* 包装 ABI：返回 0 成功；非 0 为原生错误码（未知码→Internal，S7 §7.2） */

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
    case 1: return "Invalid";
    case 2: return "Internal";
    default: return "Internal";
    }
}

/* 原生符号声明：编组签名的投影。绑定层自行包含原生头时
   定义 XN_FFI_NATIVE_DECLS 关闭本节（S7 §3.2）。 */
#ifndef XN_FFI_NATIVE_DECLS
int32_t xdkc_dir_close(void *d);
void * xdkc_dir_open(const char *path_bytes, size_t path_len);
const char * xdkc_dir_read(void *d);
int32_t xdkc_file_close(void *f);
void * xdkc_file_open_read(const char *path_bytes, size_t path_len);
void * xdkc_file_open_write(const char *path_bytes, size_t path_len);
int64_t xdkc_file_read(void *f, void *buf, size_t buf_len, int32_t *code);
int32_t xdkc_file_write(void *f, void *buf, size_t buf_len);
uint8_t xdkc_path_exists(const char *path_bytes, size_t path_len);
#endif

/* 绑定入口 dirClose（原生 xdkc_dir_close） */
static int32_t xn_ffi_dirClose(xrt_handle *d) {
    void *xn_h_d = xrt_handle_native(d);
    if (xn_h_d == NULL) { if (xrt_handle_is_closed(d)) { return 0; } xrt_fatal("FFI 句柄为空或已失效（S7 §4.3）：dirClose"); }
    int32_t xn_rc = (int32_t)xdkc_dir_close(xn_h_d);
    xrt_handle_mark_closed(d);
    return xn_rc;
}

/* 绑定入口 dirOpen（原生 xdkc_dir_open） */
static int32_t xn_ffi_dirOpen(const char *path_bytes, size_t path_len, xrt_handle * *xn_out) {
    xrt_handle * xn_v = xdkc_dir_open(path_bytes, path_len);
    *xn_out = xrt_handle_new(xn_v, NULL, "dirOpen");
    return 0;
}

/* 绑定入口 dirRead（原生 xdkc_dir_read） */
static int32_t xn_ffi_dirRead(xrt_handle *d, xrt_string * *xn_out) {
    void *xn_h_d = xrt_handle_native(d);
    if (xn_h_d == NULL) { xrt_fatal("FFI 句柄已关闭或为空（S7 §4.3）：dirRead"); }
    xrt_string * xn_v = xdkc_dir_read(xn_h_d);
    *xn_out = (xn_v == NULL) ? NULL : xrt_string_from_c(xn_v);
    return 0;
}

/* 绑定入口 fileClose（原生 xdkc_file_close） */
static int32_t xn_ffi_fileClose(xrt_handle *f) {
    void *xn_h_f = xrt_handle_native(f);
    if (xn_h_f == NULL) { if (xrt_handle_is_closed(f)) { return 0; } xrt_fatal("FFI 句柄为空或已失效（S7 §4.3）：fileClose"); }
    int32_t xn_rc = (int32_t)xdkc_file_close(xn_h_f);
    xrt_handle_mark_closed(f);
    return xn_rc;
}

/* 绑定入口 fileOpenRead（原生 xdkc_file_open_read） */
static int32_t xn_ffi_fileOpenRead(const char *path_bytes, size_t path_len, xrt_handle * *xn_out) {
    xrt_handle * xn_v = xdkc_file_open_read(path_bytes, path_len);
    *xn_out = xrt_handle_new(xn_v, NULL, "fileOpenRead");
    return 0;
}

/* 绑定入口 fileOpenWrite（原生 xdkc_file_open_write） */
static int32_t xn_ffi_fileOpenWrite(const char *path_bytes, size_t path_len, xrt_handle * *xn_out) {
    xrt_handle * xn_v = xdkc_file_open_write(path_bytes, path_len);
    *xn_out = xrt_handle_new(xn_v, NULL, "fileOpenWrite");
    return 0;
}

/* 绑定入口 fileRead（原生 xdkc_file_read） */
static int32_t xn_ffi_fileRead(xrt_handle *f, void *buf, size_t buf_len, int64_t *xn_out) {
    void *xn_h_f = xrt_handle_native(f);
    if (xn_h_f == NULL) { xrt_fatal("FFI 句柄已关闭或为空（S7 §4.3）：fileRead"); }
    uint8_t *xn_buf_buf = xn_ffi_canary_enter((const uint8_t *)buf, buf_len);
    int32_t xn_code = 0;
    int64_t xn_v = xdkc_file_read(xn_h_f, (void *)(xn_buf_buf + XN_FFI_CANARY), buf_len, &xn_code);
    if (xn_code != 0) { return xn_code; }
    xn_ffi_canary_leave(xn_buf_buf, (uint8_t *)buf, buf_len);
    *xn_out = (int64_t)xn_v;
    return 0;
}

/* 绑定入口 fileWrite（原生 xdkc_file_write） */
static int32_t xn_ffi_fileWrite(xrt_handle *f, void *buf, size_t buf_len) {
    void *xn_h_f = xrt_handle_native(f);
    if (xn_h_f == NULL) { xrt_fatal("FFI 句柄已关闭或为空（S7 §4.3）：fileWrite"); }
    uint8_t *xn_buf_buf = xn_ffi_canary_enter((const uint8_t *)buf, buf_len);
    int32_t xn_rc = (int32_t)xdkc_file_write(xn_h_f, (void *)(xn_buf_buf + XN_FFI_CANARY), buf_len);
    xn_ffi_canary_leave(xn_buf_buf, (uint8_t *)buf, buf_len);
    return xn_rc;
}

/* 绑定入口 pathExists（原生 xdkc_path_exists） */
static int32_t xn_ffi_pathExists(const char *path_bytes, size_t path_len, uint8_t *xn_out) {
    uint8_t xn_v = xdkc_path_exists(path_bytes, path_len);
    *xn_out = (uint8_t)xn_ffi_bool_from_native((uint8_t)xn_v);
    return 0;
}



static void xn_fatal_oob(void);
static void xn_fatal_oob(void) {
    fprintf(stderr, "fatal: 容器下标越界\n");
    exit(134);
}

static int64_t xn_main();

static rt_string *xn_result_error_copy_rt(rt_string *err) {
    return rt_string_new(err->bytes, err->len);
}

int64_t xn_main() {
rt_string *xn_t1 = rt_string_from_c("in.txt");
xrt_handle *xn_t2 = NULL;
int32_t xn_t3 = xn_ffi_fileOpenRead(xn_t1->bytes, xn_t1->len, &xn_t2);
if (xn_t3 != 0) { fprintf(stderr, "fatal: FFI 入口 fileOpenRead 错误码 %d（%s）\n", (int)xn_t3, xn_ffi_xdkc_sys_error_kind(xn_t3)); exit(134); }
rt_release(xn_t1);
xrt_handle *f = xn_t2;
int32_t xn_t4 = xn_ffi_fileClose(f);
rt_string *xn_t5 = rt_string_from_c("closed");
xn_print_str(xn_t5);
rt_release(xn_t5);
    {
rt_release(f);
    }

return 0;
}

int main(void) {
    int64_t xn_r = xn_main();
    rt_quarantine_flush();
    return (int)xn_r;
}
