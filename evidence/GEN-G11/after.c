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

static void xn_fatal_oob(void);
static void xn_fatal_oob(void) {
    fprintf(stderr, "fatal: 容器下标越界\n");
    exit(134);
}

typedef struct { size_t len; size_t cap; int64_t *data; } xn_arr_i;

static xn_arr_i xn_arr_i_new(size_t cap) {
    xn_arr_i a;
    a.len = 0;
    a.cap = cap ? cap : 4;
    a.data = malloc(sizeof(int64_t) * a.cap);
    if (a.data == NULL) { abort(); }
    return a;
}

static void xn_arr_i_push(xn_arr_i *a, int64_t v) {
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(int64_t) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    a->data[a->len++] = v;
}

static int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    return a->data[i];
}

static void xn_arr_i_set(xn_arr_i *a, int64_t i, int64_t v) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    a->data[i] = v;
}

static int64_t xn_arr_i_remove(xn_arr_i *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    int64_t old = a->data[i];
    for (size_t j = (size_t)i; j + 1 < a->len; j++) {
        a->data[j] = a->data[j + 1];
    }
    a->len--;
    return old;
}

static void xn_arr_i_insert(xn_arr_i *a, int64_t i, int64_t v) {
    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(int64_t) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    for (size_t j = a->len; j > (size_t)i; j--) {
        a->data[j] = a->data[j - 1];
    }
    a->data[i] = v;
    a->len++;
}

static void xn_arr_i_clear(xn_arr_i *a) {
    a->len = 0;
}

static rt_string *xn_arr_i_join(xn_arr_i a, rt_string *sep) {
    rt_string *res = rt_string_from_c("");
    for (size_t i = 0; i < a.len; i++) {
        if (i > 0) {
            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));
        }
        res = xn_concat(res, xn_str_int(a.data[i]));
    }
    return res;
}

static void xn_arr_i_free(xn_arr_i *a) {
    free(a->data);
    a->data = NULL;
    a->len = 0;
    a->cap = 0;
}

static int64_t xn_f(int64_t xn_p_v);
static int64_t xn_main();

static rt_string *xn_result_error_copy_rt(rt_string *err) {
    return rt_string_new(err->bytes, err->len);
}

int64_t xn_f(int64_t xn_p_v) {
xn_arr_i xn_t1 = xn_arr_i_new(1);
xn_arr_i_push(&xn_t1, xn_p_v);
xn_arr_i box = xn_t1;
int64_t xn_t2 = xn_arr_i_get(&box, 0);
    {
xn_arr_i_free(&box);
    }

return xn_t2;
}

int64_t xn_main() {
xn_print_int(xn_f(4));
int64_t xn_t3 = 0;
return xn_t3;
}

int main(void) {
    int64_t xn_r = xn_main();
    rt_quarantine_flush();
    return (int)xn_r;
}
