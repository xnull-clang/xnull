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
    rt_retain(v);
    a->data[i] = v;
    a->len++;
}

static void xn_arr_s_clear(xn_arr_s *a) {
    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }
    a->len = 0;
}

static rt_string *xn_arr_s_join(xn_arr_s a, rt_string *sep) {
    rt_string *res = rt_string_from_c("");
    for (size_t i = 0; i < a.len; i++) {
        if (i > 0) {
            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));
        }
        res = xn_concat(res, rt_string_new(a.data[i]->bytes, a.data[i]->len));
    }
    return res;
}

static void xn_arr_s_free(xn_arr_s *a) {
    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }
    free(a->data);
    a->data = NULL;
    a->len = 0;
    a->cap = 0;
}

typedef struct { size_t len; size_t cap; rt_string * *keys; int64_t *vals; } xn_map_s_i;

static xn_map_s_i xn_map_s_i_new(size_t cap) {
    xn_map_s_i m;
    m.len = 0;
    m.cap = cap ? cap : 4;
    m.keys = malloc(sizeof(rt_string *) * m.cap);
    m.vals = malloc(sizeof(int64_t) * m.cap);
    if (m.keys == NULL || m.vals == NULL) { abort(); }
    return m;
}

static long xn_map_s_i_find(const xn_map_s_i *m, rt_string * key) {
    for (size_t i = 0; i < m->len; i++) {
        if (m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0) { return (long)i; }
    }
    return -1;
}

static void xn_map_s_i_put(xn_map_s_i *m, rt_string * key, int64_t val) {
    long i = xn_map_s_i_find(m, key);
    if (i >= 0) {
    rt_release(m->keys[i]);
        m->vals[i] = val;
        return;
    }
    if (m->len == m->cap) {
        m->cap *= 2;
        m->keys = realloc(m->keys, sizeof(rt_string *) * m->cap);
        m->vals = realloc(m->vals, sizeof(int64_t) * m->cap);
        if (m->keys == NULL || m->vals == NULL) { abort(); }
    }
    rt_retain(key);
    m->keys[m->len] = key;
    m->vals[m->len] = val;
    m->len++;
}

static int xn_map_s_i_has(const xn_map_s_i *m, rt_string * key) { return xn_map_s_i_find(m, key) >= 0; }

static int64_t xn_map_s_i_get_or(const xn_map_s_i *m, rt_string * key, int64_t dflt) {
    long i = xn_map_s_i_find(m, key);
    return i >= 0 ? m->vals[i] : dflt;
}

static int xn_map_s_i_remove(xn_map_s_i *m, rt_string * key) {
    long i = xn_map_s_i_find(m, key);
    if (i < 0) { return 0; }
    rt_release(m->keys[i]);
    for (size_t j = (size_t)i; j + 1 < m->len; j++) {
        m->keys[j] = m->keys[j + 1];
        m->vals[j] = m->vals[j + 1];
    }
    m->len--;
    return 1;
}

static void xn_map_s_i_clear(xn_map_s_i *m) {
    for (size_t i = 0; i < m->len; i++) { rt_release(m->keys[i]); }
    free(m->keys);
    free(m->vals);
    m->len = 0;
}

static void xn_map_s_i_free(xn_map_s_i *m) {
    for (size_t i = 0; i < m->len; i++) { rt_release(m->keys[i]); }
    free(m->keys);
    free(m->vals);
    m->len = 0;
    m->cap = 0;
}

static int xn_map_s_i_cmp_key(rt_string * a, rt_string * b) {
    size_t n = a->len < b->len ? a->len : b->len;
    int c = memcmp(a->bytes, b->bytes, n);
    if (c != 0) { return c; }
    return (a->len > b->len) - (a->len < b->len);
}

static void xn_map_s_i_sort_idx(const xn_map_s_i *m, size_t *idx) {
    for (size_t i = 1; i < m->len; i++) {
        size_t x = idx[i];
        size_t j = i;
        while (j > 0 && xn_map_s_i_cmp_key(m->keys[idx[j - 1]], m->keys[x]) > 0) {
            idx[j] = idx[j - 1];
            j--;
        }
        idx[j] = x;
    }
}

static xn_arr_s xn_map_s_i_keys(const xn_map_s_i *m) {
    xn_arr_s out = xn_arr_s_new(m->len);
    if (m->len == 0) { return out; }
    size_t *idx = malloc(sizeof(size_t) * m->len);
    if (idx == NULL) { abort(); }
    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }
    xn_map_s_i_sort_idx(m, idx);
    for (size_t i = 0; i < m->len; i++) { xn_arr_s_push(&out, m->keys[idx[i]]); }
    free(idx);
    return out;
}

static xn_arr_i xn_map_s_i_values(const xn_map_s_i *m) {
    xn_arr_i out = xn_arr_i_new(m->len);
    if (m->len == 0) { return out; }
    size_t *idx = malloc(sizeof(size_t) * m->len);
    if (idx == NULL) { abort(); }
    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }
    xn_map_s_i_sort_idx(m, idx);
    for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(&out, m->vals[idx[i]]); }
    free(idx);
    return out;
}

static xn_opt_i xn_map_s_i_get(const xn_map_s_i *m, rt_string * key) {
    xn_opt_i r;
    long i = xn_map_s_i_find(m, key);
    if (i < 0) { r.has = 0; r.v = 0; return r; }
    r.has = 1;
    r.v = m->vals[i];
    return r;
}


static xn_arr_s xn_str_split(rt_string *s, rt_string *sep) {
    xn_arr_s out = xn_arr_s_new(4);
    if (sep->len == 0) {
        rt_string *t = rt_string_new(s->bytes, s->len);
        xn_arr_s_push(&out, t);
        rt_release(t);
        return out;
    }
    size_t start = 0, i = 0;
    while (i + sep->len <= s->len) {
        if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) {
            rt_string *t = rt_string_new(s->bytes + start, i - start);
            xn_arr_s_push(&out, t);
            rt_release(t);
            i += sep->len;
            start = i;
        } else {
            i++;
        }
    }
    rt_string *last = rt_string_new(s->bytes + start, s->len - start);
    xn_arr_s_push(&out, last);
    rt_release(last);
    return out;
}
static int64_t xn_main();

static rt_string *xn_result_error_copy_rt(rt_string *err) {
    return rt_string_new(err->bytes, err->len);
}

int64_t xn_main() {
xn_map_s_i xn_t1 = xn_map_s_i_new(3);
rt_string *xn_t2 = rt_string_from_c("c");
xn_map_s_i_put(&xn_t1, xn_t2, 3);
rt_string *xn_t3 = rt_string_from_c("a");
xn_map_s_i_put(&xn_t1, xn_t3, 1);
rt_string *xn_t4 = rt_string_from_c("b");
xn_map_s_i_put(&xn_t1, xn_t4, 2);
xn_map_s_i m = xn_t1;
xn_arr_s xn_t5 = xn_map_s_i_keys(&m);
xn_arr_s k = xn_t5;
xn_print_str(xn_arr_s_get(&k, 0));
xn_print_str(xn_arr_s_get(&k, 1));
xn_print_str(xn_arr_s_get(&k, 2));
    {
xn_arr_s_free(&k);
    }
    {
xn_map_s_i_free(&m);
    }

return 0;
}

int main(void) {
    int64_t xn_r = xn_main();
    rt_quarantine_flush();
    return (int)xn_r;
}
