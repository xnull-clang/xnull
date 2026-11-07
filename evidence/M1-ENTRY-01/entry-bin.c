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

static rt_string *xn_str_int(int64_t v) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%lld", (long long)v);
    return rt_string_new(buf, (size_t)n);
}

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

static void xn_fatal_oob(void);
static void xn_fatal_oob(void) {
    fprintf(stderr, "fatal: 容器下标越界\n");
    exit(134);
}

static int64_t xn_g_a;
static int64_t xn_g_b;
static rt_string * xn_g_tag;

typedef struct { size_t len; size_t cap; rt_string * *data; } xn_arr_s;

static xn_arr_s xn_arr_s_new(size_t cap) {
    xn_arr_s a;
    a.len = 0;
    a.cap = cap ? cap : 4;
    a.data = malloc(sizeof(rt_string *) * a.cap);
    if (a.data == NULL) { abort(); }
    return a;
}

static void xn_arr_s_push(xn_arr_s *a, rt_string * v) {
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    rt_retain(v);
    a->data[a->len++] = v;
}

static rt_string * xn_arr_s_get(const xn_arr_s *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    return a->data[i];
}

static void xn_arr_s_set(xn_arr_s *a, int64_t i, rt_string * v) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    rt_release(a->data[i]);
    rt_retain(v);
    a->data[i] = v;
}

static void xn_arr_s_remove(xn_arr_s *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }
    for (size_t j = (size_t)i; j + 1 < a->len; j++) {
        a->data[j] = a->data[j + 1];
    }
    a->len--;
}

static void xn_arr_s_clear(xn_arr_s *a) {
    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }
    a->len = 0;
}

static void xn_arr_s_free(xn_arr_s *a) {
    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }
    free(a->data);
    a->data = NULL;
    a->len = 0;
    a->cap = 0;
}

static int64_t xn_mark(int64_t xn_p_v);
static int64_t xn_main(xn_arr_s xn_p_args);

static rt_string *xn_result_error_copy_rt(rt_string *err) {
    return rt_string_new(err->bytes, err->len);
}

int64_t xn_mark(int64_t xn_p_v) {
rt_string *xn_t1 = rt_string_from_c("init ");
rt_string *xn_t2 = xn_str_int(xn_p_v);
rt_string *xn_t3 = xn_concat(xn_t1, xn_t2);
xn_print_str(xn_t3);
rt_release(xn_t3);
return xn_p_v;
}

int64_t xn_main(xn_arr_s xn_p_args) {
rt_string *xn_t4 = rt_string_from_c("main ");
rt_string *xn_t5 = rt_retain(xn_g_tag);
rt_string *xn_t6 = xn_concat(xn_t4, xn_t5);
rt_string *xn_t7 = rt_string_from_c(" args=");
rt_string *xn_t8 = xn_concat(xn_t6, xn_t7);
rt_string *xn_t9 = xn_str_int(((int64_t)xn_p_args.len));
rt_string *xn_t10 = xn_concat(xn_t8, xn_t9);
xn_print_str(xn_t10);
rt_release(xn_t10);
return 7;
}

static void xn_init_globals(void) {
    xn_g_a = xn_mark(1);
    xn_g_b = xn_mark((xn_g_a + 1));
    rt_string *xn_t11 = rt_string_from_c("t");
    rt_string *xn_t12 = xn_str_int(xn_g_b);
    rt_string *xn_t13 = xn_concat(xn_t11, xn_t12);
    xn_g_tag = xn_t13;
}

int main(int argc, char **argv) {
    xn_init_globals();
    xn_arr_s xn_args = xn_arr_s_new((size_t)(argc > 1 ? argc - 1 : 0));
    for (int i = 1; i < argc; i++) {
        rt_string *xn_av = rt_string_from_c(argv[i]);
        xn_arr_s_push(&xn_args, xn_av);
        rt_release(xn_av);
    }
    int64_t xn_r = xn_main(xn_args);
    rt_quarantine_flush();
    return (int)xn_r;
}
