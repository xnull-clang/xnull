#include "rt.h"
#include "rt_gc.h"
#include "xrt.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

typedef struct { void *env; void *fn; } xn_closure;

static int64_t xn_int_wrap(int64_t value) { return (int64_t)(int32_t)value; }
static int64_t xn_int_shl(int64_t value, int64_t bitCount) { if (bitCount < 0 || bitCount >= 32) { rt_fatal("shift count out of range"); } return (int64_t)((uint32_t)value << (uint32_t)bitCount); }
static int64_t xn_int_shr(int64_t value, int64_t bitCount) { if (bitCount < 0 || bitCount >= 32) { rt_fatal("shift count out of range"); } return (int64_t)((int32_t)value >> (int32_t)bitCount); }
static void xn_print_int(int64_t v) { printf("%lld\n", (long long)xn_int_wrap(v)); }
static void xn_print_bool(int v) { printf(v ? "true\n" : "false\n"); }
static void xn_print_double(double v) { printf("%g\n", v); }
static void xn_print_str(rt_string *s) { printf("%.*s\n", (int)s->len, s->bytes); }
static rt_string *xn_str_int(int64_t v) { char buf[32]; snprintf(buf, sizeof(buf), "%lld", (long long)xn_int_wrap(v)); return rt_string_from_c(buf); }
static rt_string *xn_str_long(int64_t v) { char buf[32]; snprintf(buf, sizeof(buf), "%lld", (long long)v); return rt_string_from_c(buf); }
static void xn_print_long(int64_t v) { printf("%lld\n", (long long)v); }
static __int128 xn_int128_from_dec(const char *s) { unsigned __int128 u = 0; int neg = 0; if (*s == '-') { neg = 1; s++; } while (*s >= '0' && *s <= '9') { u = u * 10 + (unsigned __int128)(*s - '0'); s++; } return neg ? -(__int128)u : (__int128)u; }
static void xn_print_int128(__int128 v) { char buf[64]; int n = 0; unsigned __int128 u; if (v < 0) { putchar('-'); u = (unsigned __int128)(-(v + 1)) + 1; } else { u = (unsigned __int128)v; } do { buf[n++] = (char)('0' + (int)(u % 10)); u /= 10; } while (u != 0); while (n > 0) { putchar(buf[--n]); } putchar('\n'); }
static rt_string *xn_str_int128(__int128 v) { char buf[64]; int n = 0; unsigned __int128 u; if (v < 0) { buf[n++] = '-'; u = (unsigned __int128)(-(v + 1)) + 1; } else { u = (unsigned __int128)v; } int start = n; do { buf[n++] = (char)('0' + (int)(u % 10)); u /= 10; } while (u != 0); for (int i = start, j = n - 1; i < j; i++, j--) { char t = buf[i]; buf[i] = buf[j]; buf[j] = t; } buf[n] = 0; return rt_string_from_c(buf); }
static rt_string *xn_str_double(double v) { char buf[64]; snprintf(buf, sizeof(buf), "%g", v); return rt_string_from_c(buf); }
static rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? "true" : "false"); }
static rt_string *xn_str_char(int32_t cp) { char b[5]; int n = 0; if (cp < 0) { cp = 0xFFFD; } if (cp < 0x80) { b[n++] = (char)cp; } else if (cp < 0x800) { b[n++] = (char)(0xC0 | (cp >> 6)); b[n++] = (char)(0x80 | (cp & 0x3F)); } else if (cp < 0x10000) { b[n++] = (char)(0xE0 | (cp >> 12)); b[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); b[n++] = (char)(0x80 | (cp & 0x3F)); } else { b[n++] = (char)(0xF0 | (cp >> 18)); b[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); b[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); b[n++] = (char)(0x80 | (cp & 0x3F)); } b[n] = 0; return rt_string_from_c(b); }
static rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) { if (start < 0) { start = 0; } if (n < 0) { n = 0; } if ((size_t)start > s->len) { start = (int64_t)s->len; } if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; } rt_string *out = rt_string_alloc((size_t)n); if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); } out->bytes[n] = 0; return out; }
static int64_t xn_str_indexof(rt_string *s, rt_string *sub) { if (sub->len == 0) { return 0; } if (sub->len > s->len) { return -1; } for (size_t i = 0; i + sub->len <= s->len; i++) { if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; } } return -1; }
static int xn_str_eq(rt_string *a, rt_string *b) { return (a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0) ? 1 : 0; }
static rt_string *xn_concat(rt_string *a, rt_string *b) { size_t n = a->len + b->len; rt_string *r = rt_string_alloc(n); memcpy(r->bytes, a->bytes, a->len); memcpy(r->bytes + a->len, b->bytes, b->len); r->bytes[n] = 0; return r; }

typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;
static const rt_type RT_TYPE_XN_ARR_I = { "List", sizeof(xn_arr_i), NULL, NULL };
static xn_arr_i *xn_arr_i_new(size_t cap) { xn_arr_i *a = (xn_arr_i *)rt_gc_new(&RT_TYPE_XN_ARR_I); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_i) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (int64_t *)malloc(sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } return a; }
static void xn_arr_i_push(xn_arr_i *a, int64_t v) { if (a->len == a->cap) { a->cap *= 2; a->data = (int64_t *)realloc(a->data, sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }
static int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }
static void xn_arr_i_remove(xn_arr_i *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }
static void xn_arr_i_set(xn_arr_i *a, int64_t i, int64_t v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }
static void xn_arr_i_insert(xn_arr_i *a, int64_t i, int64_t v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (int64_t *)realloc(a->data, sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }
typedef struct { rt_header hdr; size_t len; size_t cap; double *data; } xn_arr_d;
static const rt_type RT_TYPE_XN_ARR_D = { "List", sizeof(xn_arr_d), NULL, NULL };
static xn_arr_d *xn_arr_d_new(size_t cap) { xn_arr_d *a = (xn_arr_d *)rt_gc_new(&RT_TYPE_XN_ARR_D); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_d) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (double *)malloc(sizeof(double) * a->cap); if (a->data == NULL) { abort(); } return a; }
static void xn_arr_d_push(xn_arr_d *a, double v) { if (a->len == a->cap) { a->cap *= 2; a->data = (double *)realloc(a->data, sizeof(double) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }
static double xn_arr_d_get(const xn_arr_d *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }
static void xn_arr_d_remove(xn_arr_d *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }
static void xn_arr_d_set(xn_arr_d *a, int64_t i, double v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }
static void xn_arr_d_insert(xn_arr_d *a, int64_t i, double v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (double *)realloc(a->data, sizeof(double) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }
typedef struct { rt_header hdr; size_t len; size_t cap; rt_string **data; } xn_arr_s;
static const rt_type RT_TYPE_XN_ARR_S = { "List", sizeof(xn_arr_s), NULL, NULL };
static xn_arr_s *xn_arr_s_new(size_t cap) { xn_arr_s *a = (xn_arr_s *)rt_gc_new(&RT_TYPE_XN_ARR_S); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_s) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (rt_string **)malloc(sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } return a; }
static void xn_arr_s_push(xn_arr_s *a, rt_string *v) { if (a->len == a->cap) { a->cap *= 2; a->data = (rt_string **)realloc(a->data, sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }
static rt_string *xn_arr_s_get(const xn_arr_s *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }
static void xn_arr_s_remove(xn_arr_s *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }
static void xn_arr_s_set(xn_arr_s *a, int64_t i, rt_string *v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }
static void xn_arr_s_insert(xn_arr_s *a, int64_t i, rt_string *v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (rt_string **)realloc(a->data, sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }
typedef struct { rt_header hdr; size_t len; size_t cap; void **data; } xn_arr_o;
static const rt_type RT_TYPE_XN_ARR_O = { "List", sizeof(xn_arr_o), NULL, NULL };
static xn_arr_o *xn_arr_o_new(size_t cap) { xn_arr_o *a = (xn_arr_o *)rt_gc_new(&RT_TYPE_XN_ARR_O); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_o) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (void **)malloc(sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } return a; }
static void xn_arr_o_push(xn_arr_o *a, void *v) { if (a->len == a->cap) { a->cap *= 2; a->data = (void **)realloc(a->data, sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }
static void *xn_arr_o_get(const xn_arr_o *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }
static void xn_arr_o_remove(xn_arr_o *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }
static void xn_arr_o_set(xn_arr_o *a, int64_t i, void *v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }
static void xn_arr_o_insert(xn_arr_o *a, int64_t i, void *v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (void **)realloc(a->data, sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }
static int xn_str_startswith(rt_string *s, rt_string *p) { if (p->len > s->len) { return 0; } return memcmp(s->bytes, p->bytes, p->len) == 0 ? 1 : 0; }
static int xn_str_endswith(rt_string *s, rt_string *p) { if (p->len > s->len) { return 0; } return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0 ? 1 : 0; }
static rt_string *xn_str_trim(rt_string *s) { size_t a = 0, b = s->len; while (a < b && (s->bytes[a] == ' ' || s->bytes[a] == '\t' || s->bytes[a] == '\n' || s->bytes[a] == '\r' || s->bytes[a] == '\v' || s->bytes[a] == '\f')) { a++; } while (b > a && (s->bytes[b-1] == ' ' || s->bytes[b-1] == '\t' || s->bytes[b-1] == '\n' || s->bytes[b-1] == '\r' || s->bytes[b-1] == '\v' || s->bytes[b-1] == '\f')) { b--; } rt_string *r = rt_string_alloc(b - a); if (b > a) { memcpy(r->bytes, s->bytes + a, b - a); } r->bytes[b-a] = 0; return r; }
static rt_string *xn_str_case(rt_string *s, int upper) { rt_string *r = rt_string_alloc(s->len); for (size_t i = 0; i < s->len; i++) { unsigned char c = (unsigned char)s->bytes[i]; if (upper && c >= 'a' && c <= 'z') { c = (unsigned char)(c - 32); } else if (!upper && c >= 'A' && c <= 'Z') { c = (unsigned char)(c + 32); } r->bytes[i] = (char)c; } r->bytes[s->len] = 0; return r; }
static rt_string *xn_str_replace(rt_string *s, rt_string *from, rt_string *to) { if (from->len == 0) { return s; } size_t cap = s->len + 8, n = 0; char *buf = (char *)malloc(cap); if (buf == NULL) { abort(); } for (size_t i = 0; i < s->len; ) { if (i + from->len <= s->len && memcmp(s->bytes + i, from->bytes, from->len) == 0) { while (n + to->len + 1 > cap) { cap *= 2; buf = (char *)realloc(buf, cap); if (buf == NULL) { abort(); } } memcpy(buf + n, to->bytes, to->len); n += to->len; i += from->len; } else { while (n + 2 > cap) { cap *= 2; buf = (char *)realloc(buf, cap); if (buf == NULL) { abort(); } } buf[n++] = s->bytes[i++]; } } buf[n] = 0; rt_string *r = rt_string_from_c(buf); free(buf); return r; }
static xn_arr_s *xn_str_split(rt_string *s, rt_string *sep) { xn_arr_s *out = xn_arr_s_new(4); if (sep->len == 0) { xn_arr_s_push(out, s); return out; } size_t start = 0; size_t i = 0; while (i + sep->len <= s->len) { if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) { size_t n = i - start; rt_string *p = rt_string_alloc(n); if (n > 0) { memcpy(p->bytes, s->bytes + start, n); } p->bytes[n] = 0; xn_arr_s_push(out, p); i = i + sep->len; start = i; } else { i++; } } { size_t n = s->len - start; rt_string *p = rt_string_alloc(n); if (n > 0) { memcpy(p->bytes, s->bytes + start, n); } p->bytes[n] = 0; xn_arr_s_push(out, p); } return out; }
static rt_string *xn_arr_s_join(xn_arr_s *a, rt_string *sep) { size_t n = 0; for (size_t i = 0; i < a->len; i++) { n += a->data[i]->len; if (i > 0) { n += sep->len; } } rt_string *r = rt_string_alloc(n); size_t off = 0; for (size_t i = 0; i < a->len; i++) { if (i > 0) { memcpy(r->bytes + off, sep->bytes, sep->len); off += sep->len; } memcpy(r->bytes + off, a->data[i]->bytes, a->data[i]->len); off += a->data[i]->len; } r->bytes[n] = 0; return r; }

typedef struct { rt_header hdr; size_t len; size_t cap; rt_string **keys; int64_t *vals; } xn_map_s_i;
static const rt_type RT_TYPE_XN_MAP_S_I = { "Map", sizeof(xn_map_s_i), NULL, NULL };
static xn_map_s_i *xn_map_s_i_new(size_t cap) { xn_map_s_i *m = (xn_map_s_i *)rt_gc_new(&RT_TYPE_XN_MAP_S_I); memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_s_i) - sizeof(rt_header)); m->cap = cap ? cap : 4; m->keys = (rt_string **)malloc(sizeof(rt_string *) * m->cap); m->vals = (int64_t *)malloc(sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } return m; }
static long xn_map_s_i_find(const xn_map_s_i *m, rt_string *key) { for (size_t i = 0; i < m->len; i++) { if (m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0) { return (long)i; } } return -1; }
static int xn_map_s_i_has(const xn_map_s_i *m, rt_string *key) { return xn_map_s_i_find(m, key) >= 0 ? 1 : 0; }
static void xn_map_s_i_put(xn_map_s_i *m, rt_string *key, int64_t val) { long i = xn_map_s_i_find(m, key); if (i >= 0) { m->vals[i] = val; return; } if (m->len == m->cap) { m->cap *= 2; m->keys = (rt_string **)realloc(m->keys, sizeof(rt_string *) * m->cap); m->vals = (int64_t *)realloc(m->vals, sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } } m->keys[m->len] = key; m->vals[m->len] = val; m->len++; }
static int64_t xn_map_s_i_getOr(const xn_map_s_i *m, rt_string *key, int64_t dflt) { long i = xn_map_s_i_find(m, key); return i >= 0 ? m->vals[i] : dflt; }
static int xn_map_s_i_put_replaced(xn_map_s_i *m, rt_string *key, int64_t val) { long i = xn_map_s_i_find(m, key); if (i >= 0) { m->vals[i] = val; return 1; } if (m->len == m->cap) { m->cap *= 2; m->keys = (rt_string **)realloc(m->keys, sizeof(rt_string *) * m->cap); m->vals = (int64_t *)realloc(m->vals, sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } } m->keys[m->len] = key; m->vals[m->len] = val; m->len++; return 0; }
static int xn_map_s_i_remove(xn_map_s_i *m, rt_string *key) { long i = xn_map_s_i_find(m, key); if (i < 0) { return 0; } for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return 1; }
static int64_t xn_map_s_i_remove_value(xn_map_s_i *m, rt_string *key, int64_t fallback) { long i = xn_map_s_i_find(m, key); if (i < 0) { return fallback; } int64_t v = m->vals[i]; for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return v; }
static xn_arr_o *xn_map_s_i_entries(const xn_map_s_i *m);
static xn_arr_s *xn_map_s_i_keys(const xn_map_s_i *m) { xn_arr_s *out = xn_arr_s_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_s_push(out, m->keys[i]); } return out; }
static xn_arr_i *xn_map_s_i_values(const xn_map_s_i *m) { xn_arr_i *out = xn_arr_i_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(out, m->vals[i]); } return out; }

typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_set_i;
static const rt_type RT_TYPE_XN_SET_I = { "Set", sizeof(xn_set_i), NULL, NULL };
static xn_set_i *xn_set_i_new(void) { xn_set_i *s = (xn_set_i *)rt_gc_new(&RT_TYPE_XN_SET_I); memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_i) - sizeof(rt_header)); s->cap = 4; s->data = (int64_t *)malloc(sizeof(int64_t) * s->cap); if (s->data == NULL) { abort(); } return s; }
static int xn_set_i_has(const xn_set_i *s, int64_t v) { for (size_t i = 0; i < s->len; i++) { if (s->data[i] == v) { return 1; } } return 0; }
static int xn_set_i_add(xn_set_i *s, int64_t v) { if (xn_set_i_has(s, v)) { return 0; } if (s->len == s->cap) { s->cap *= 2; s->data = (int64_t *)realloc(s->data, sizeof(int64_t) * s->cap); if (s->data == NULL) { abort(); } } s->data[s->len++] = v; return 1; }
static int xn_set_i_remove(xn_set_i *s, int64_t v) { for (size_t i = 0; i < s->len; i++) { if (s->data[i] == v) { for (size_t j = i; j + 1 < s->len; j++) { s->data[j] = s->data[j + 1]; } s->len--; return 1; } } return 0; }
typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *keys; int64_t *vals; } xn_map_i_i;
static const rt_type RT_TYPE_XN_MAP_I_I = { "Map", sizeof(xn_map_i_i), NULL, NULL };
static xn_map_i_i *xn_map_i_i_new(size_t cap) { xn_map_i_i *m = (xn_map_i_i *)rt_gc_new(&RT_TYPE_XN_MAP_I_I); memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_i_i) - sizeof(rt_header)); m->cap = cap ? cap : 4; m->keys = (int64_t *)malloc(sizeof(int64_t) * m->cap); m->vals = (int64_t *)malloc(sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } return m; }
static long xn_map_i_i_find(const xn_map_i_i *m, int64_t key) { for (size_t i = 0; i < m->len; i++) { if (m->keys[i] == key) { return (long)i; } } return -1; }
static int xn_map_i_i_has(const xn_map_i_i *m, int64_t key) { return xn_map_i_i_find(m, key) >= 0 ? 1 : 0; }
static int64_t xn_map_i_i_getOr(const xn_map_i_i *m, int64_t key, int64_t fallback) { long i = xn_map_i_i_find(m, key); return i >= 0 ? m->vals[i] : fallback; }
static int xn_map_i_i_put_replaced(xn_map_i_i *m, int64_t key, int64_t val) { long i = xn_map_i_i_find(m, key); if (i >= 0) { m->vals[i] = val; return 1; } if (m->len == m->cap) { m->cap *= 2; m->keys = (int64_t *)realloc(m->keys, sizeof(int64_t) * m->cap); m->vals = (int64_t *)realloc(m->vals, sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } } m->keys[m->len] = key; m->vals[m->len] = val; m->len++; return 0; }
static int xn_map_i_i_remove(xn_map_i_i *m, int64_t key) { long i = xn_map_i_i_find(m, key); if (i < 0) { return 0; } for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return 1; }
static int64_t xn_map_i_i_remove_value(xn_map_i_i *m, int64_t key, int64_t fallback) { long i = xn_map_i_i_find(m, key); if (i < 0) { return fallback; } int64_t v = m->vals[i]; for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return v; }
static xn_arr_i *xn_map_i_i_keys(const xn_map_i_i *m) { xn_arr_i *out = xn_arr_i_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(out, m->keys[i]); } return out; }
static xn_arr_i *xn_map_i_i_values(const xn_map_i_i *m) { xn_arr_i *out = xn_arr_i_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(out, m->vals[i]); } return out; }
static xn_arr_o *xn_map_i_i_entries(const xn_map_i_i *m);
typedef struct { rt_header hdr; size_t len; size_t cap; rt_string **data; } xn_set_s;
static const rt_type RT_TYPE_XN_SET_S = { "Set", sizeof(xn_set_s), NULL, NULL };
static xn_set_s *xn_set_s_new(void) { xn_set_s *s = (xn_set_s *)rt_gc_new(&RT_TYPE_XN_SET_S); memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_s) - sizeof(rt_header)); s->cap = 4; s->data = (rt_string **)malloc(sizeof(rt_string *) * s->cap); if (s->data == NULL) { abort(); } return s; }
static int xn_set_s_has(const xn_set_s *s, rt_string *v) { for (size_t i = 0; i < s->len; i++) { if (s->data[i]->len == v->len && memcmp(s->data[i]->bytes, v->bytes, v->len) == 0) { return 1; } } return 0; }
static int xn_set_s_add(xn_set_s *s, rt_string *v) { if (xn_set_s_has(s, v)) { return 0; } if (s->len == s->cap) { s->cap *= 2; s->data = (rt_string **)realloc(s->data, sizeof(rt_string *) * s->cap); if (s->data == NULL) { abort(); } } s->data[s->len++] = v; return 1; }
static int xn_set_s_remove(xn_set_s *s, rt_string *v) { for (size_t i = 0; i < s->len; i++) { if (s->data[i]->len == v->len && memcmp(s->data[i]->bytes, v->bytes, v->len) == 0) { for (size_t j = i; j + 1 < s->len; j++) { s->data[j] = s->data[j + 1]; } s->len--; return 1; } } return 0; }
typedef struct { rt_header hdr; size_t len; size_t cap; void **keys; void **vals; int keyKind; int valKind; } xn_map_g;
static const rt_type RT_TYPE_XN_MAP_G = { "Map", sizeof(xn_map_g), NULL, NULL };
static void *xn_double_to_ptr(double v) { uint64_t bits; memcpy(&bits, &v, sizeof(bits)); return (void *)(uintptr_t)bits; }
static double xn_ptr_to_double(void *p) { uint64_t bits = (uint64_t)(uintptr_t)p; double v; memcpy(&v, &bits, sizeof(v)); return v; }
static int xn_map_g_key_eq(int kind, void *a, void *b) { if (kind == 1) { return xn_str_eq((rt_string *)a, (rt_string *)b); } if (kind == 2) { return (uint64_t)(uintptr_t)a == (uint64_t)(uintptr_t)b; } return a == b; }
static xn_map_g *xn_map_g_new(size_t cap, int kk, int vk) { xn_map_g *m = (xn_map_g *)rt_gc_new(&RT_TYPE_XN_MAP_G); memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_g) - sizeof(rt_header)); m->cap = cap ? cap : 4; m->keys = (void **)malloc(sizeof(void *) * m->cap); m->vals = (void **)malloc(sizeof(void *) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } m->keyKind = kk; m->valKind = vk; return m; }
static long xn_map_g_find(const xn_map_g *m, void *key) { for (size_t i = 0; i < m->len; i++) { if (xn_map_g_key_eq(m->keyKind, m->keys[i], key)) { return (long)i; } } return -1; }
static int xn_map_g_has(const xn_map_g *m, void *key) { return xn_map_g_find(m, key) >= 0 ? 1 : 0; }
static int xn_map_g_put_replaced(xn_map_g *m, void *key, void *val) { long i = xn_map_g_find(m, key); if (i >= 0) { m->vals[i] = val; return 1; } if (m->len == m->cap) { m->cap *= 2; m->keys = (void **)realloc(m->keys, sizeof(void *) * m->cap); m->vals = (void **)realloc(m->vals, sizeof(void *) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } } m->keys[m->len] = key; m->vals[m->len] = val; m->len++; return 0; }
static void *xn_map_g_getOr(const xn_map_g *m, void *key, void *fallback) { long i = xn_map_g_find(m, key); return i >= 0 ? m->vals[i] : fallback; }
static int xn_map_g_remove(xn_map_g *m, void *key) { long i = xn_map_g_find(m, key); if (i < 0) { return 0; } for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return 1; }
static void *xn_map_g_remove_value(xn_map_g *m, void *key, void *fallback) { long i = xn_map_g_find(m, key); if (i < 0) { return fallback; } void *v = m->vals[i]; for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return v; }
typedef struct { rt_header hdr; size_t len; size_t cap; void **data; int elemKind; } xn_set_g;
static const rt_type RT_TYPE_XN_SET_G = { "Set", sizeof(xn_set_g), NULL, NULL };
static xn_set_g *xn_set_g_new(int ek) { xn_set_g *s = (xn_set_g *)rt_gc_new(&RT_TYPE_XN_SET_G); memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_g) - sizeof(rt_header)); s->cap = 4; s->data = (void **)malloc(sizeof(void *) * s->cap); if (s->data == NULL) { abort(); } s->elemKind = ek; return s; }
static int xn_set_g_has(const xn_set_g *s, void *v) { for (size_t i = 0; i < s->len; i++) { if (xn_map_g_key_eq(s->elemKind, s->data[i], v)) { return 1; } } return 0; }
static int xn_set_g_add(xn_set_g *s, void *v) { if (xn_set_g_has(s, v)) { return 0; } if (s->len == s->cap) { s->cap *= 2; s->data = (void **)realloc(s->data, sizeof(void *) * s->cap); if (s->data == NULL) { abort(); } } s->data[s->len++] = v; return 1; }
static int xn_set_g_remove(xn_set_g *s, void *v) { for (size_t i = 0; i < s->len; i++) { if (xn_map_g_key_eq(s->elemKind, s->data[i], v)) { for (size_t j = i; j + 1 < s->len; j++) { s->data[j] = s->data[j + 1]; } s->len--; return 1; } } return 0; }

const char *mini_read_file(const char *path, size_t len);
const char *mini_list_x(const char *path, size_t len);
static const char *mini_platform(void) { return "darwin"; }
static int32_t mini_file_exists(const char *path_bytes, size_t path_len) { char *p = (char *)malloc(path_len + 1); if (p == NULL) { return 0; } memcpy(p, path_bytes, path_len); p[path_len] = 0; int ok = access(p, F_OK) == 0; free(p); return ok ? 1 : 0; }
int32_t xdkc_p_resource_exists(const char *path, size_t len);
const char *xdkc_p_read_resource_text(const char *path, size_t len);
int64_t xdkc_p_resource_count(void);
const char *xdkc_read_file_text(const char *bytes, size_t len);
int32_t xdkc_read_file_text_error(void);
int32_t xdkc_diagnose_rc(const char *bytes, size_t len);
int32_t xdkc_exit_rc(int32_t code);
int64_t xdkc_now_mono_ms(void);
int64_t xdkc_now_wall_ms(void);
typedef struct { int ok; int64_t value; rt_string *error; } xn_Result_Int_String;
typedef struct { int ok; int64_t i; double d; rt_string *s; void *p; void *err; __int128 q; } xn_Result;
static void *xn_box_result(xn_Result v) { xn_Result *p = (xn_Result *)malloc(sizeof(xn_Result)); if (p == NULL) { abort(); } *p = v; return (void *)p; }
typedef struct { rt_header hdr; int64_t kind; rt_string *message; } xn_builtin_error;
static const rt_type RT_TYPE_XN_BUILTIN_ERROR = { "BuiltinError", sizeof(xn_builtin_error), NULL, NULL };
static xn_builtin_error *xn_builtin_error_new(int64_t kind, const char *message) { xn_builtin_error *e = (xn_builtin_error *)rt_gc_new(&RT_TYPE_XN_BUILTIN_ERROR); memset((char *)e + sizeof(rt_header), 0, sizeof(xn_builtin_error) - sizeof(rt_header)); e->kind = kind; e->message = rt_string_from_c(message); return e; }
static xn_Result xn_arr_i_try_remove(xn_arr_i *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { return (xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, "tryRemove: index out of range") }; } int64_t v = a->data[i]; for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; return (xn_Result){ .ok = 1, .i = v }; }
static xn_Result xn_arr_d_try_remove(xn_arr_d *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { return (xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, "tryRemove: index out of range") }; } double v = a->data[i]; for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; return (xn_Result){ .ok = 1, .d = v }; }
static xn_Result xn_arr_s_try_remove(xn_arr_s *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { return (xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, "tryRemove: index out of range") }; } rt_string *v = a->data[i]; for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; return (xn_Result){ .ok = 1, .s = v }; }
static xn_Result xn_arr_o_try_remove(xn_arr_o *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { return (xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, "tryRemove: index out of range") }; } void *v = a->data[i]; for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; return (xn_Result){ .ok = 1, .p = v }; }
typedef struct { rt_header hdr; size_t len; size_t cap; xn_Result *data; } xn_arr_r;
static const rt_type RT_TYPE_XN_ARR_R = { "List", sizeof(xn_arr_r), NULL, NULL };
static xn_arr_r *xn_arr_r_new(size_t cap) { xn_arr_r *a = (xn_arr_r *)rt_gc_new(&RT_TYPE_XN_ARR_R); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_r) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (xn_Result *)malloc(sizeof(xn_Result) * a->cap); if (a->data == NULL) { abort(); } return a; }
static void xn_arr_r_push(xn_arr_r *a, xn_Result v) { if (a->len == a->cap) { a->cap *= 2; a->data = (xn_Result *)realloc(a->data, sizeof(xn_Result) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }
static xn_Result xn_arr_r_get(const xn_arr_r *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }
static void xn_arr_r_set(xn_arr_r *a, int64_t i, xn_Result v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }
static void xn_arr_r_remove(xn_arr_r *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }
static void xn_arr_r_insert(xn_arr_r *a, int64_t i, xn_Result v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (xn_Result *)realloc(a->data, sizeof(xn_Result) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }
static xn_Result xn_channel_send_int(xrt_channel *c, int64_t v, xrt_context *ctx) { xn_Result r; int32_t rc = xrt_channel_send(c, (void *)(intptr_t)v, ctx); r.ok = rc == 0; r.i = 0; r.d = 0; r.s = NULL; r.p = NULL; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_channel_recv_int(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; r.i = rc == 0 ? (int64_t)(intptr_t)v : 0; r.d = 0; r.s = NULL; r.p = NULL; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_channel_send_ptr(xrt_channel *c, void *v, xrt_context *ctx) { xn_Result r; int32_t rc = xrt_channel_send(c, v, ctx); r.ok = rc == 0; r.i = 0; r.d = 0; r.s = NULL; r.p = NULL; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_channel_recv_ptr(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; r.i = (int64_t)(intptr_t)v; r.d = 0; r.s = (rt_string *)v; r.p = v; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_channel_send_double(xrt_channel *c, double v, xrt_context *ctx) { uint64_t bits; memcpy(&bits, &v, sizeof(bits)); xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_send(c, (void *)(uintptr_t)bits, ctx); r.ok = rc == 0; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_channel_recv_double(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; if (rc == 0) { uint64_t bits = (uint64_t)(uintptr_t)v; memcpy(&r.d, &bits, sizeof(double)); } r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static const xrt_channel_ops xn_channel_box_ops = { NULL, free };
static xn_Result xn_channel_send_int128(xrt_channel *c, __int128 v, xrt_context *ctx) { __int128 *p = (__int128 *)malloc(sizeof(__int128)); if (p == NULL) { abort(); } *p = v; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_send(c, (void *)p, ctx); if (rc != 0) { free(p); } r.ok = rc == 0; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_channel_recv_int128(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; if (rc == 0) { __int128 *p = (__int128 *)v; r.q = *p; free(p); } r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_channel_send_result(xrt_channel *c, xn_Result v, xrt_context *ctx) { xn_Result *p = (xn_Result *)malloc(sizeof(xn_Result)); if (p == NULL) { abort(); } *p = v; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_send(c, (void *)p, ctx); if (rc != 0) { free(p); } r.ok = rc == 0; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_channel_recv_result(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; if (rc == 0) { xn_Result *p = (xn_Result *)v; r.p = (void *)malloc(sizeof(xn_Result)); if (r.p == NULL) { abort(); } *(xn_Result *)r.p = *p; free(p); } r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_channel_send_result_is(xrt_channel *c, xn_Result_Int_String v, xrt_context *ctx) { xn_Result *p = (xn_Result *)malloc(sizeof(xn_Result)); if (p == NULL) { abort(); } memset(p, 0, sizeof(xn_Result)); p->ok = v.ok; p->i = v.value; p->s = v.error; p->err = v.error; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_send(c, (void *)p, ctx); if (rc != 0) { free(p); } r.ok = rc == 0; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_channel_recv_result_is(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; if (rc == 0) { xn_Result *p = (xn_Result *)v; xn_Result_Int_String *out = (xn_Result_Int_String *)malloc(sizeof(xn_Result_Int_String)); if (out == NULL) { abort(); } out->ok = p->ok; out->value = p->i; out->error = (rt_string *)p->err; r.p = (void *)out; free(p); } r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }
static xn_Result xn_mutex_lock(xrt_mutex *m, xn_closure cl, xrt_with_lock_body body) { xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_mutex_with_lock(m, body, &cl, NULL); r.ok = rc == 0; if (rc != 0) { r.err = (void *)(intptr_t)rc; } return r; }
static xrt_task *xn_task_spawn(xrt_task_group *g, xn_closure cl, xrt_task_body body) { xn_closure *env = (xn_closure *)malloc(sizeof(xn_closure)); if (env == NULL) { abort(); } *env = cl; xrt_task *t = NULL; xrt_task_group_spawn(g, body, env, &t); return t; }
static xn_Result xn_task_result_map(xrt_task_result *tr) { xn_Result r; memset(&r, 0, sizeof(r)); if (!tr->ok) { r.ok = 0; r.err = (void *)(intptr_t)tr->kind; return r; } r.ok = 1; r.i = (int64_t)(intptr_t)tr->value; r.s = (rt_string *)tr->value; r.p = tr->value; return r; }
static xn_Result xn_task_join(xrt_task *t) { xrt_task_result tr; memset(&tr, 0, sizeof(tr)); int32_t rc = xrt_task_join(t, &tr); if (rc != 0) { xn_Result r; memset(&r, 0, sizeof(r)); r.err = (void *)(intptr_t)rc; return r; } return xn_task_result_map(&tr); }
static xn_Result xn_task_join_deadline(xrt_task *t, int64_t dl) { xrt_task_result tr; memset(&tr, 0, sizeof(tr)); int32_t rc = xrt_task_join_deadline(t, dl, &tr); if (rc != 0) { xn_Result r; memset(&r, 0, sizeof(r)); r.err = (void *)(intptr_t)rc; return r; } return xn_task_result_map(&tr); }
static xn_Result xn_task_group_close(xrt_task_group *g) { xrt_task_result tr; memset(&tr, 0, sizeof(tr)); int32_t rc = xrt_task_group_close(g, &tr); xn_Result r; memset(&r, 0, sizeof(r)); if (rc != 0) { r.err = (void *)(intptr_t)rc; return r; } if (!tr.ok) { r.err = (void *)(intptr_t)tr.kind; return r; } r.ok = 1; return r; }

typedef struct xn_Cls_Token xn_Cls_Token;
typedef struct xn_Cls_AstNode xn_Cls_AstNode;
typedef struct xn_Cls_Parser xn_Cls_Parser;
typedef struct xn_Cls_Mono xn_Cls_Mono;
typedef struct xn_Cls_Checker xn_Cls_Checker;
typedef struct xn_Cls_CGen xn_Cls_CGen;
static xn_arr_s * loadedFiles;
static rt_string * loadBaseDir;
static rt_string * loadRoot;
static int xdkFullSource;
static xn_arr_s * ffiNames;
static xn_arr_s * ffiCNames;
static xn_arr_s * ffiRets;
static xn_arr_s * ffiParamSpecs;
static xn_arr_s * ffiErrParams;
static xn_arr_s * ffiErrRets;


static int64_t xn_usage(void);
static rt_string * xn_at(rt_string * s, int64_t i);
static int xn_starts(rt_string * s, int64_t i, rt_string * lit);
static int xn_isDigit(rt_string * c);
static int xn_isHex(rt_string * c);
static int xn_isLower(rt_string * c);
static int xn_isUpper(rt_string * c);
static int xn_isIdentStart(rt_string * c);
static int xn_isIdentPart(rt_string * c);
static int xn_isSpace(rt_string * c);
static int xn_isKeyword(rt_string * s);
static xn_arr_o * xn_lex(rt_string * src);
static int xn_hasTypeParams(xn_Cls_AstNode * fn);
static xn_arr_s * xn_splitTop(rt_string * s);
static int64_t xn_dumpTokens(xn_arr_o * ts, rt_string * path);
static int64_t xn_ffiIndex(rt_string * name);
static rt_string * xn_ffiRet(rt_string * name);
static rt_string * xn_ffiCName(rt_string * name);
static void xn_loadProject(rt_string * path);
static int64_t xn_lastDot(rt_string * s);
static rt_string * xn_localImportFile(rt_string * pkg);
static rt_string * xn_xdkFile(rt_string * pkg);
static int xn_endsWithX(rt_string * s);
static rt_string * xn_dirName(rt_string * path);
static int xn_loaded(rt_string * path);
static void xn_mergeDecls(xn_Cls_AstNode * program, xn_Cls_AstNode * parsed);
static void xn_loadUnit(rt_string * path, xn_Cls_AstNode * program);
static void xn_loadSiblings(rt_string * path, xn_Cls_AstNode * program);
static xn_Cls_AstNode * xn_loadProgram(rt_string * entry, rt_string * root);
static rt_string * xn_argAfter(xn_arr_s * args, rt_string * flag);
static int xn_hasArg(xn_arr_s * args, rt_string * flag);
static int64_t xn_main(xn_arr_s * args);

struct xn_Cls_Token {
  rt_header hdr;
  rt_string * kind;
  rt_string * text;
  int64_t line;
  int64_t col;
};

static const rt_type RT_TYPE_XN_Token = { "Token", sizeof(xn_Cls_Token), NULL, NULL };

static xn_Cls_Token *xn_Cls_Token_new(rt_string * kind, rt_string * text, int64_t line, int64_t col) {
  xn_Cls_Token *xn_obj = (xn_Cls_Token *)rt_gc_new(&RT_TYPE_XN_Token);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_Token) - sizeof(rt_header));
  xn_obj->kind = rt_string_from_c("");
  xn_obj->text = rt_string_from_c("");
  xn_obj->line = 0;
  xn_obj->col = 0;
  xn_Cls_Token *self = xn_obj;
  self->kind = kind;
  self->text = text;
  self->line = line;
  self->col = col;
  return xn_obj;
}


struct xn_Cls_AstNode {
  rt_header hdr;
  rt_string * kind;
  rt_string * text;
  int64_t line;
  int64_t col;
  xn_arr_o * kids;
};

static const rt_type RT_TYPE_XN_AstNode = { "AstNode", sizeof(xn_Cls_AstNode), NULL, NULL };

static xn_Cls_AstNode *xn_Cls_AstNode_new(rt_string * kind, rt_string * text, int64_t line, int64_t col) {
  xn_Cls_AstNode *xn_obj = (xn_Cls_AstNode *)rt_gc_new(&RT_TYPE_XN_AstNode);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_AstNode) - sizeof(rt_header));
  xn_obj->kind = rt_string_from_c("");
  xn_obj->text = rt_string_from_c("");
  xn_obj->line = 0;
  xn_obj->col = 0;
  xn_obj->kids = xn_arr_o_new(4);
  xn_Cls_AstNode *self = xn_obj;
  self->kind = kind;
  self->text = text;
  self->line = line;
  self->col = col;
  self->kids = xn_arr_o_new(0);
  return xn_obj;
}

static void xn_Cls_AstNode_add(xn_Cls_AstNode *self, xn_Cls_AstNode * kid);
static void xn_Cls_AstNode_setKid(xn_Cls_AstNode *self, int64_t idx, xn_Cls_AstNode * v);
static void xn_Cls_AstNode_dump(xn_Cls_AstNode *self, int64_t depth);

static void xn_Cls_AstNode_add(xn_Cls_AstNode *self, xn_Cls_AstNode * kid) {
  xn_arr_o_push(self->kids, kid);
}

static void xn_Cls_AstNode_setKid(xn_Cls_AstNode *self, int64_t idx, xn_Cls_AstNode * v) {
  xn_arr_o *tmp = xn_arr_o_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->kids->len))) {
    if ((i == idx)) {
      xn_arr_o_push(tmp, v);
    }
    else {
      xn_arr_o_push(tmp, ((xn_Cls_AstNode *)xn_arr_o_get(self->kids, i)));
    }
    i = xn_int_wrap((i + 1));
  }
  while ((((int64_t)self->kids->len) > 0)) {
    xn_arr_o_remove(self->kids, xn_int_wrap((((int64_t)self->kids->len) - 1)));
  }
  i = 0;
  while ((i < ((int64_t)tmp->len))) {
    xn_arr_o_push(self->kids, ((xn_Cls_AstNode *)xn_arr_o_get(tmp, i)));
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_AstNode_dump(xn_Cls_AstNode *self, int64_t depth) {
  rt_string * pad = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < depth)) {
    pad = xn_concat(pad, rt_string_from_c("  "));
    i = xn_int_wrap((i + 1));
  }
  if (xn_str_eq(self->text, rt_string_from_c(""))) {
    xn_print_str(xn_concat(pad, self->kind));
  }
  else {
    xn_print_str(xn_concat(xn_concat(xn_concat(pad, self->kind), rt_string_from_c(": ")), self->text));
  }
  int64_t j = xn_int_wrap(0);
  while ((j < ((int64_t)self->kids->len))) {
    xn_Cls_AstNode * kid = ((xn_Cls_AstNode *)xn_arr_o_get(self->kids, j));
    xn_Cls_AstNode_dump(kid, xn_int_wrap((depth + 1)));
    j = xn_int_wrap((j + 1));
  }
}

struct xn_Cls_Parser {
  rt_header hdr;
  xn_arr_o * ts;
  int64_t pos;
  rt_string * error;
  rt_string * errorCode;
  int64_t errorLine;
  int64_t errorCol;
};

static const rt_type RT_TYPE_XN_Parser = { "Parser", sizeof(xn_Cls_Parser), NULL, NULL };

static xn_Cls_Parser *xn_Cls_Parser_new(xn_arr_o * ts) {
  xn_Cls_Parser *xn_obj = (xn_Cls_Parser *)rt_gc_new(&RT_TYPE_XN_Parser);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_Parser) - sizeof(rt_header));
  xn_obj->ts = xn_arr_o_new(4);
  xn_obj->pos = 0;
  xn_obj->error = rt_string_from_c("");
  xn_obj->errorCode = rt_string_from_c("");
  xn_obj->errorLine = 0;
  xn_obj->errorCol = 0;
  xn_Cls_Parser *self = xn_obj;
  self->ts = ts;
  self->pos = 0;
  self->error = rt_string_from_c("");
  self->errorCode = rt_string_from_c("");
  self->errorLine = 1;
  self->errorCol = 1;
  return xn_obj;
}

static int xn_Cls_Parser_hasError(xn_Cls_Parser *self);
static xn_Cls_Token * xn_Cls_Parser_peek(xn_Cls_Parser *self);
static xn_Cls_Token * xn_Cls_Parser_advance(xn_Cls_Parser *self);
static int xn_Cls_Parser_eof(xn_Cls_Parser *self);
static int xn_Cls_Parser_at(xn_Cls_Parser *self, rt_string * text);
static int xn_Cls_Parser_kind(xn_Cls_Parser *self, rt_string * k);
static int xn_Cls_Parser_eat(xn_Cls_Parser *self, rt_string * text);
static xn_Cls_Token * xn_Cls_Parser_expect(xn_Cls_Parser *self, rt_string * text);
static void xn_Cls_Parser_fail(xn_Cls_Parser *self, rt_string * msg);
static xn_Cls_AstNode * xn_Cls_Parser_node(xn_Cls_Parser *self, rt_string * kindName, rt_string * text, xn_Cls_Token * t);
static xn_Cls_AstNode * xn_Cls_Parser_parse(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parsePath(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseTop(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseClassDecl(xn_Cls_Parser *self, rt_string * kindName);
static xn_Cls_AstNode * xn_Cls_Parser_parseEnum(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseProtocol(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseFunc(xn_Cls_Parser *self);
static int xn_Cls_Parser_looksLikeTypeArgs(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseTypeArgsText(xn_Cls_Parser *self);
static int xn_Cls_Parser_typeHasFuncSuffix(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseType(xn_Cls_Parser *self);
static rt_string * xn_Cls_Parser_parseNewType(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseBlock(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseCaseBody(xn_Cls_Parser *self);
static xn_Cls_Token * xn_Cls_Parser_look(xn_Cls_Parser *self, int64_t n);
static int xn_Cls_Parser_isLocalDecl(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseLocal(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseStmt(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseExpr(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseOr(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseAnd(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseEquality(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseRel(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseBitOr(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseBitXor(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseBitAnd(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseShift(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseAdd(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseMul(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseCast(xn_Cls_Parser *self);
static int xn_Cls_Parser_hasCall(xn_Cls_Parser *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Parser_memberPath(xn_Cls_Parser *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Parser_quoted(xn_Cls_Parser *self, rt_string * s);
static xn_Cls_AstNode * xn_Cls_Parser_parseInterpolation(xn_Cls_Parser *self, xn_Cls_Token * t);
static int xn_Cls_Parser_looksLikeLambda(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseLambda(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parsePrimary(xn_Cls_Parser *self);

static int xn_Cls_Parser_hasError(xn_Cls_Parser *self) {
  return (!xn_str_eq(self->error, rt_string_from_c("")));
}

static xn_Cls_Token * xn_Cls_Parser_peek(xn_Cls_Parser *self) {
  if ((self->pos < ((int64_t)self->ts->len))) {
    return ((xn_Cls_Token *)xn_arr_o_get(self->ts, self->pos));
  }
  return xn_Cls_Token_new(rt_string_from_c("eof"), rt_string_from_c(""), 1, 1);
}

static xn_Cls_Token * xn_Cls_Parser_advance(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  if ((self->pos < xn_int_wrap((((int64_t)self->ts->len) - 1)))) {
    self->pos = xn_int_wrap((self->pos + 1));
  }
  return t;
}

static int xn_Cls_Parser_eof(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  return xn_str_eq(t->kind, rt_string_from_c("eof"));
}

static int xn_Cls_Parser_at(xn_Cls_Parser *self, rt_string * text) {
  if (xn_Cls_Parser_hasError(self)) {
    return 0;
  }
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  return xn_str_eq(t->text, text);
}

static int xn_Cls_Parser_kind(xn_Cls_Parser *self, rt_string * k) {
  if (xn_Cls_Parser_hasError(self)) {
    return 0;
  }
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  return xn_str_eq(t->kind, k);
}

static int xn_Cls_Parser_eat(xn_Cls_Parser *self, rt_string * text) {
  if (xn_Cls_Parser_at(self, text)) {
    xn_Cls_Parser_advance(self);
    return 1;
  }
  return 0;
}

static xn_Cls_Token * xn_Cls_Parser_expect(xn_Cls_Parser *self, rt_string * text) {
  if (xn_Cls_Parser_at(self, text)) {
    return xn_Cls_Parser_advance(self);
  }
  xn_Cls_Parser_fail(self, xn_concat(rt_string_from_c("expected "), text));
  return xn_Cls_Parser_peek(self);
}

static void xn_Cls_Parser_fail(xn_Cls_Parser *self, rt_string * msg) {
  if (xn_str_eq(self->error, rt_string_from_c(""))) {
    xn_Cls_Token * t = xn_Cls_Parser_peek(self);
    self->error = msg;
    self->errorLine = t->line;
    self->errorCol = t->col;
  }
}

static xn_Cls_AstNode * xn_Cls_Parser_node(xn_Cls_Parser *self, rt_string * kindName, rt_string * text, xn_Cls_Token * t) {
  return xn_Cls_AstNode_new(kindName, text, t->line, t->col);
}

static xn_Cls_AstNode * xn_Cls_Parser_parse(xn_Cls_Parser *self) {
  xn_Cls_AstNode * program = xn_Cls_AstNode_new(rt_string_from_c("Program"), rt_string_from_c(""), 1, 1);
  while (((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_eof(self)))) {
    xn_Cls_AstNode * d = xn_Cls_Parser_parseTop(self);
    if (((!xn_Cls_Parser_hasError(self)) && (!xn_str_eq(d->kind, rt_string_from_c("error"))))) {
      xn_Cls_AstNode_add(program, d);
    }
  }
  return program;
}

static rt_string * xn_Cls_Parser_parsePath(xn_Cls_Parser *self) {
  rt_string * path = rt_string_from_c("");
  if (((!xn_Cls_Parser_kind(self, rt_string_from_c("ident"))) && (!xn_Cls_Parser_kind(self, rt_string_from_c("kw"))))) {
    xn_Cls_Parser_fail(self, rt_string_from_c("expected package/import name"));
    return path;
  }
  xn_Cls_Token * first = xn_Cls_Parser_advance(self);
  path = first->text;
  while (xn_Cls_Parser_eat(self, rt_string_from_c("."))) {
    if (((!xn_Cls_Parser_kind(self, rt_string_from_c("ident"))) && (!xn_Cls_Parser_kind(self, rt_string_from_c("kw"))))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("expected name after ."));
      return path;
    }
    xn_Cls_Token * part = xn_Cls_Parser_advance(self);
    path = xn_concat(xn_concat(path, rt_string_from_c(".")), part->text);
  }
  return path;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseTop(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  if (xn_Cls_Parser_at(self, rt_string_from_c("package"))) {
    xn_Cls_Parser_advance(self);
    rt_string * name = xn_Cls_Parser_parsePath(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Package"), name, t);
    xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    return n;
  }
  if (xn_Cls_Parser_at(self, rt_string_from_c("import"))) {
    xn_Cls_Parser_advance(self);
    rt_string * name = xn_Cls_Parser_parsePath(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Import"), name, t);
    xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    return n;
  }
  if (((xn_Cls_Parser_at(self, rt_string_from_c("final")) || xn_Cls_Parser_at(self, rt_string_from_c("abstract"))) || xn_Cls_Parser_at(self, rt_string_from_c("public")))) {
    xn_Cls_Parser_advance(self);
    return xn_Cls_Parser_parseTop(self);
  }
  if (xn_Cls_Parser_at(self, rt_string_from_c("class"))) {
    return xn_Cls_Parser_parseClassDecl(self, rt_string_from_c("Class"));
  }
  if (xn_Cls_Parser_at(self, rt_string_from_c("struct"))) {
    return xn_Cls_Parser_parseClassDecl(self, rt_string_from_c("Struct"));
  }
  if (xn_Cls_Parser_at(self, rt_string_from_c("enum"))) {
    return xn_Cls_Parser_parseEnum(self);
  }
  if (xn_Cls_Parser_at(self, rt_string_from_c("protocol"))) {
    return xn_Cls_Parser_parseProtocol(self);
  }
  if (xn_Cls_Parser_at(self, rt_string_from_c("static"))) {
    return xn_Cls_Parser_parseFunc(self);
  }
  if (xn_Cls_Parser_kind(self, rt_string_from_c("kw"))) {
    return xn_Cls_Parser_parseFunc(self);
  }
  if (xn_Cls_Parser_kind(self, rt_string_from_c("ident"))) {
    int64_t save = xn_int_wrap(self->pos);
    rt_string * ty = xn_Cls_Parser_parseType(self);
    if (xn_Cls_Parser_kind(self, rt_string_from_c("ident"))) {
      xn_Cls_Token * nt = xn_Cls_Parser_advance(self);
      if ((xn_Cls_Parser_at(self, rt_string_from_c("=")) || xn_Cls_Parser_at(self, rt_string_from_c(";")))) {
        xn_Cls_AstNode * f = xn_Cls_Parser_node(self, rt_string_from_c("TopField"), xn_concat(xn_concat(ty, rt_string_from_c(" ")), nt->text), nt);
        if (xn_Cls_Parser_eat(self, rt_string_from_c("="))) {
          xn_Cls_AstNode_add(f, xn_Cls_Parser_parseExpr(self));
        }
        xn_Cls_Parser_eat(self, rt_string_from_c(";"));
        return f;
      }
    }
    self->pos = save;
    return xn_Cls_Parser_parseFunc(self);
  }
  xn_Cls_Parser_fail(self, xn_concat(rt_string_from_c("unexpected top-level token: "), t->text));
  return xn_Cls_Parser_node(self, rt_string_from_c("error"), t->text, t);
}

static xn_Cls_AstNode * xn_Cls_Parser_parseClassDecl(xn_Cls_Parser *self, rt_string * kindName) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  xn_Cls_Parser_advance(self);
  if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
    xn_Cls_Parser_fail(self, rt_string_from_c("expected type name"));
    return xn_Cls_Parser_node(self, rt_string_from_c("error"), rt_string_from_c(""), t);
  }
  xn_Cls_Token * nt = xn_Cls_Parser_advance(self);
  rt_string * name = nt->text;
  xn_Cls_AstNode * cls = xn_Cls_Parser_node(self, kindName, name, t);
  if (xn_Cls_Parser_eat(self, rt_string_from_c("<"))) {
    xn_Cls_AstNode * tp = xn_Cls_Parser_node(self, rt_string_from_c("TypeParams"), rt_string_from_c(""), t);
    while (((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c(">"))))) {
      if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("expected type parameter"));
        break;
      }
      xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
      xn_Cls_AstNode_add(tp, xn_Cls_AstNode_new(rt_string_from_c("TypeParam"), pn->text, pn->line, pn->col));
      if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
        break;
      }
    }
    xn_Cls_Parser_expect(self, rt_string_from_c(">"));
    xn_Cls_AstNode_add(cls, tp);
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c(":"))) {
    rt_string * base = xn_Cls_Parser_parseType(self);
    xn_Cls_AstNode_add(cls, xn_Cls_AstNode_new(rt_string_from_c("Base"), base, t->line, t->col));
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("implements"))) {
    while ((!xn_Cls_Parser_hasError(self))) {
      rt_string * pn = xn_Cls_Parser_parseType(self);
      xn_Cls_AstNode_add(cls, xn_Cls_AstNode_new(rt_string_from_c("Implements"), pn, t->line, t->col));
      if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
        break;
      }
    }
  }
  xn_Cls_Parser_expect(self, rt_string_from_c("{"));
  while ((((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c("}")))) && (!xn_Cls_Parser_eof(self)))) {
    int isStatic = 0;
    while (((((xn_Cls_Parser_at(self, rt_string_from_c("static")) || xn_Cls_Parser_at(self, rt_string_from_c("final"))) || xn_Cls_Parser_at(self, rt_string_from_c("public"))) || xn_Cls_Parser_at(self, rt_string_from_c("private"))) || xn_Cls_Parser_at(self, rt_string_from_c("protected")))) {
      if (xn_Cls_Parser_at(self, rt_string_from_c("static"))) {
        isStatic = 1;
      }
      xn_Cls_Parser_advance(self);
    }
    rt_string * ty = xn_Cls_Parser_parseType(self);
    if ((xn_Cls_Parser_at(self, rt_string_from_c("(")) && xn_str_eq(ty, name))) {
      xn_Cls_Token * ct = xn_Cls_Parser_peek(self);
      xn_Cls_AstNode * ctor = xn_Cls_Parser_node(self, rt_string_from_c("Ctor"), name, ct);
      xn_Cls_Parser_expect(self, rt_string_from_c("("));
      if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
        while ((!xn_Cls_Parser_hasError(self))) {
          rt_string * pt = xn_Cls_Parser_parseType(self);
          if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
            xn_Cls_Parser_fail(self, rt_string_from_c("expected constructor parameter name"));
            break;
          }
          xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
          xn_Cls_AstNode_add(ctor, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), ct->line, ct->col));
          if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
            break;
          }
        }
      }
      xn_Cls_Parser_expect(self, rt_string_from_c(")"));
      xn_Cls_AstNode_add(ctor, xn_Cls_Parser_parseBlock(self));
      xn_Cls_AstNode_add(cls, ctor);
      continue;
    }
    if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("expected member name"));
      break;
    }
    xn_Cls_Token * mt = xn_Cls_Parser_advance(self);
    rt_string * mn = mt->text;
    if (xn_Cls_Parser_at(self, rt_string_from_c("("))) {
      xn_Cls_AstNode * m = xn_Cls_Parser_node(self, rt_string_from_c("Method"), mn, mt);
      if (isStatic) {
        xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Static"), rt_string_from_c(""), mt->line, mt->col));
      }
      xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Ret"), ty, mt->line, mt->col));
      xn_Cls_Parser_advance(self);
      if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
        while ((!xn_Cls_Parser_hasError(self))) {
          rt_string * pt = xn_Cls_Parser_parseType(self);
          if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
            xn_Cls_Parser_fail(self, rt_string_from_c("expected parameter name"));
            break;
          }
          xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
          xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), mt->line, mt->col));
          if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
            break;
          }
        }
      }
      xn_Cls_Parser_expect(self, rt_string_from_c(")"));
      xn_Cls_AstNode_add(m, xn_Cls_Parser_parseBlock(self));
      xn_Cls_AstNode_add(cls, m);
    }
    else {
      xn_Cls_AstNode * f = xn_Cls_Parser_node(self, rt_string_from_c("Field"), xn_concat(xn_concat(ty, rt_string_from_c(" ")), mn), mt);
      if (isStatic) {
        xn_Cls_AstNode_add(f, xn_Cls_AstNode_new(rt_string_from_c("Static"), rt_string_from_c(""), mt->line, mt->col));
      }
      if (xn_Cls_Parser_eat(self, rt_string_from_c("="))) {
        xn_Cls_AstNode_add(f, xn_Cls_Parser_parseExpr(self));
      }
      xn_Cls_Parser_eat(self, rt_string_from_c(";"));
      xn_Cls_AstNode_add(cls, f);
    }
  }
  xn_Cls_Parser_expect(self, rt_string_from_c("}"));
  return cls;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseEnum(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  xn_Cls_Parser_advance(self);
  if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
    xn_Cls_Parser_fail(self, rt_string_from_c("expected enum name"));
    return xn_Cls_Parser_node(self, rt_string_from_c("error"), rt_string_from_c(""), t);
  }
  xn_Cls_Token * nt = xn_Cls_Parser_advance(self);
  xn_Cls_AstNode * e = xn_Cls_Parser_node(self, rt_string_from_c("Enum"), nt->text, t);
  xn_Cls_Parser_expect(self, rt_string_from_c("{"));
  int data = 0;
  while ((((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c("}")))) && (!xn_Cls_Parser_eof(self)))) {
    if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("expected enum item"));
      break;
    }
    xn_Cls_Token * it = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * item = xn_Cls_Parser_node(self, rt_string_from_c("EnumItem"), it->text, it);
    if (xn_Cls_Parser_eat(self, rt_string_from_c("("))) {
      if ((!data)) {
        xn_Cls_AstNode_add(e, xn_Cls_AstNode_new(rt_string_from_c("Data"), rt_string_from_c(""), it->line, it->col));
      }
      data = 1;
      if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
        while ((!xn_Cls_Parser_hasError(self))) {
          xn_Cls_AstNode_add(item, xn_Cls_Parser_parseExpr(self));
          if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
            break;
          }
        }
      }
      xn_Cls_Parser_expect(self, rt_string_from_c(")"));
    }
    else {
      if (xn_Cls_Parser_eat(self, rt_string_from_c("="))) {
        xn_Cls_AstNode_add(item, xn_Cls_Parser_parseExpr(self));
      }
    }
    xn_Cls_AstNode_add(e, item);
    if (xn_Cls_Parser_eat(self, rt_string_from_c(","))) {
      continue;
    }
    if (xn_Cls_Parser_eat(self, rt_string_from_c(";"))) {
      break;
    }
    break;
  }
  if ((!xn_Cls_Parser_at(self, rt_string_from_c("}")))) {
    data = 1;
    while ((((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c("}")))) && (!xn_Cls_Parser_eof(self)))) {
      while (((((xn_Cls_Parser_at(self, rt_string_from_c("static")) || xn_Cls_Parser_at(self, rt_string_from_c("final"))) || xn_Cls_Parser_at(self, rt_string_from_c("public"))) || xn_Cls_Parser_at(self, rt_string_from_c("private"))) || xn_Cls_Parser_at(self, rt_string_from_c("protected")))) {
        xn_Cls_Parser_advance(self);
      }
      rt_string * ty = xn_Cls_Parser_parseType(self);
      if ((xn_Cls_Parser_at(self, rt_string_from_c("(")) && xn_str_eq(ty, e->text))) {
        xn_Cls_Token * ct = xn_Cls_Parser_peek(self);
        xn_Cls_AstNode * ctor = xn_Cls_Parser_node(self, rt_string_from_c("Ctor"), e->text, ct);
        xn_Cls_Parser_expect(self, rt_string_from_c("("));
        if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
          while ((!xn_Cls_Parser_hasError(self))) {
            rt_string * pt = xn_Cls_Parser_parseType(self);
            if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
              xn_Cls_Parser_fail(self, rt_string_from_c("expected constructor parameter name"));
              break;
            }
            xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
            xn_Cls_AstNode_add(ctor, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), ct->line, ct->col));
            if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
              break;
            }
          }
        }
        xn_Cls_Parser_expect(self, rt_string_from_c(")"));
        xn_Cls_AstNode_add(ctor, xn_Cls_Parser_parseBlock(self));
        xn_Cls_AstNode_add(e, ctor);
        continue;
      }
      if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("expected enum member"));
        break;
      }
      xn_Cls_Token * mt = xn_Cls_Parser_advance(self);
      if (xn_Cls_Parser_at(self, rt_string_from_c("("))) {
        xn_Cls_AstNode * m = xn_Cls_Parser_node(self, rt_string_from_c("Method"), mt->text, mt);
        xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Ret"), ty, mt->line, mt->col));
        xn_Cls_Parser_advance(self);
        if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
          while ((!xn_Cls_Parser_hasError(self))) {
            rt_string * pt = xn_Cls_Parser_parseType(self);
            if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
              xn_Cls_Parser_fail(self, rt_string_from_c("expected parameter name"));
              break;
            }
            xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
            xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), mt->line, mt->col));
            if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
              break;
            }
          }
        }
        xn_Cls_Parser_expect(self, rt_string_from_c(")"));
        xn_Cls_AstNode_add(m, xn_Cls_Parser_parseBlock(self));
        xn_Cls_AstNode_add(e, m);
      }
      else {
        xn_Cls_AstNode * f = xn_Cls_Parser_node(self, rt_string_from_c("Field"), xn_concat(xn_concat(ty, rt_string_from_c(" ")), mt->text), mt);
        if (xn_Cls_Parser_eat(self, rt_string_from_c("="))) {
          xn_Cls_AstNode_add(f, xn_Cls_Parser_parseExpr(self));
        }
        xn_Cls_Parser_eat(self, rt_string_from_c(";"));
        xn_Cls_AstNode_add(e, f);
      }
    }
  }
  xn_Cls_Parser_expect(self, rt_string_from_c("}"));
  return e;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseProtocol(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  xn_Cls_Parser_advance(self);
  if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
    xn_Cls_Parser_fail(self, rt_string_from_c("expected protocol name"));
    return xn_Cls_Parser_node(self, rt_string_from_c("error"), rt_string_from_c(""), t);
  }
  xn_Cls_Token * nt = xn_Cls_Parser_advance(self);
  xn_Cls_AstNode * p = xn_Cls_Parser_node(self, rt_string_from_c("Protocol"), nt->text, t);
  if (xn_Cls_Parser_eat(self, rt_string_from_c(":"))) {
    while ((!xn_Cls_Parser_hasError(self))) {
      rt_string * bn = xn_Cls_Parser_parseType(self);
      xn_Cls_AstNode_add(p, xn_Cls_AstNode_new(rt_string_from_c("Extends"), bn, t->line, t->col));
      if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
        break;
      }
    }
  }
  xn_Cls_Parser_expect(self, rt_string_from_c("{"));
  while ((((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c("}")))) && (!xn_Cls_Parser_eof(self)))) {
    rt_string * rt = xn_Cls_Parser_parseType(self);
    if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("expected protocol method name"));
      break;
    }
    xn_Cls_Token * mn = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * m = xn_Cls_Parser_node(self, rt_string_from_c("Sig"), mn->text, mn);
    xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Ret"), rt, mn->line, mn->col));
    xn_Cls_Parser_expect(self, rt_string_from_c("("));
    if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
      while ((!xn_Cls_Parser_hasError(self))) {
        rt_string * pt = xn_Cls_Parser_parseType(self);
        if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
          xn_Cls_Parser_fail(self, rt_string_from_c("expected parameter name"));
          break;
        }
        xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
        xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), mn->line, mn->col));
        if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
          break;
        }
      }
    }
    xn_Cls_Parser_expect(self, rt_string_from_c(")"));
    xn_Cls_Parser_expect(self, rt_string_from_c(";"));
    xn_Cls_AstNode_add(p, m);
  }
  xn_Cls_Parser_expect(self, rt_string_from_c("}"));
  return p;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseFunc(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  if (xn_Cls_Parser_eat(self, rt_string_from_c("static"))) {
  }
  rt_string * rt = xn_Cls_Parser_parseType(self);
  if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
    xn_Cls_Parser_fail(self, rt_string_from_c("expected function name"));
    return xn_Cls_Parser_node(self, rt_string_from_c("error"), rt_string_from_c(""), t);
  }
  xn_Cls_Token * nameToken = xn_Cls_Parser_advance(self);
  rt_string * name = nameToken->text;
  xn_Cls_AstNode * fn = xn_Cls_Parser_node(self, rt_string_from_c("Func"), name, t);
  xn_Cls_AstNode_add(fn, xn_Cls_AstNode_new(rt_string_from_c("Ret"), rt, t->line, t->col));
  if (xn_Cls_Parser_eat(self, rt_string_from_c("<"))) {
    xn_Cls_AstNode * tp = xn_Cls_AstNode_new(rt_string_from_c("TypeParams"), rt_string_from_c(""), t->line, t->col);
    while (((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c(">"))))) {
      if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("expected type parameter"));
        break;
      }
      xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
      xn_Cls_AstNode_add(tp, xn_Cls_AstNode_new(rt_string_from_c("TypeParam"), pn->text, pn->line, pn->col));
      if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
        break;
      }
    }
    xn_Cls_AstNode_add(fn, tp);
    xn_Cls_Parser_expect(self, rt_string_from_c(">"));
  }
  xn_Cls_Parser_expect(self, rt_string_from_c("("));
  if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
    while ((!xn_Cls_Parser_hasError(self))) {
      rt_string * pt = xn_Cls_Parser_parseType(self);
      if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("expected parameter name"));
        break;
      }
      xn_Cls_Token * pnToken = xn_Cls_Parser_advance(self);
      rt_string * pn = pnToken->text;
      xn_Cls_AstNode_add(fn, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn), t->line, t->col));
      if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
        break;
      }
    }
  }
  xn_Cls_Parser_expect(self, rt_string_from_c(")"));
  xn_Cls_AstNode_add(fn, xn_Cls_Parser_parseBlock(self));
  return fn;
}

static int xn_Cls_Parser_looksLikeTypeArgs(xn_Cls_Parser *self) {
  if ((!xn_Cls_Parser_at(self, rt_string_from_c("<")))) {
    return 0;
  }
  int64_t depth = xn_int_wrap(0);
  int64_t j = xn_int_wrap(0);
  while (1) {
    xn_Cls_Token * t = xn_Cls_Parser_look(self, j);
    if (xn_str_eq(t->kind, rt_string_from_c("eof"))) {
      return 0;
    }
    if (xn_str_eq(t->text, rt_string_from_c("<"))) {
      depth = xn_int_wrap((depth + 1));
    }
    else {
      if (xn_str_eq(t->text, rt_string_from_c(">"))) {
        depth = xn_int_wrap((depth - 1));
        if ((depth == 0)) {
          return xn_str_eq(xn_Cls_Parser_look(self, xn_int_wrap((j + 1)))->text, rt_string_from_c("("));
        }
      }
    }
    j = xn_int_wrap((j + 1));
  }
  return 0;
}

static rt_string * xn_Cls_Parser_parseTypeArgsText(xn_Cls_Parser *self) {
  xn_Cls_Parser_expect(self, rt_string_from_c("<"));
  rt_string * res = rt_string_from_c("");
  while (((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c(">"))))) {
    if ((!xn_str_eq(res, rt_string_from_c("")))) {
      res = xn_concat(res, rt_string_from_c(","));
    }
    res = xn_concat(res, xn_Cls_Parser_parseType(self));
    if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
      break;
    }
  }
  xn_Cls_Parser_expect(self, rt_string_from_c(">"));
  return res;
}

static int xn_Cls_Parser_typeHasFuncSuffix(xn_Cls_Parser *self) {
  if ((!xn_Cls_Parser_at(self, rt_string_from_c("(")))) {
    return 0;
  }
  int64_t depth = xn_int_wrap(0);
  int64_t j = xn_int_wrap(0);
  while (1) {
    xn_Cls_Token * t = xn_Cls_Parser_look(self, j);
    if (xn_str_eq(t->kind, rt_string_from_c("eof"))) {
      return 0;
    }
    if (xn_str_eq(t->text, rt_string_from_c("("))) {
      depth = xn_int_wrap((depth + 1));
    }
    else {
      if (xn_str_eq(t->text, rt_string_from_c(")"))) {
        depth = xn_int_wrap((depth - 1));
        if ((depth == 0)) {
          xn_Cls_Token * after = xn_Cls_Parser_look(self, xn_int_wrap((j + 1)));
          return xn_str_eq(after->kind, rt_string_from_c("ident"));
        }
      }
    }
    j = xn_int_wrap((j + 1));
  }
  return 0;
}

static rt_string * xn_Cls_Parser_parseType(xn_Cls_Parser *self) {
  if (xn_Cls_Parser_at(self, rt_string_from_c("final"))) {
    xn_Cls_Parser_advance(self);
  }
  if (((!xn_Cls_Parser_kind(self, rt_string_from_c("ident"))) && (!xn_Cls_Parser_kind(self, rt_string_from_c("kw"))))) {
    xn_Cls_Parser_fail(self, rt_string_from_c("expected type"));
    return rt_string_from_c("");
  }
  xn_Cls_Token * t = xn_Cls_Parser_advance(self);
  rt_string * ty = t->text;
  while (xn_Cls_Parser_eat(self, rt_string_from_c("."))) {
    xn_Cls_Token * part = xn_Cls_Parser_advance(self);
    ty = xn_concat(xn_concat(ty, rt_string_from_c(".")), part->text);
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("<"))) {
    ty = xn_concat(ty, rt_string_from_c("<"));
    int64_t depth = xn_int_wrap(1);
    while (((!xn_Cls_Parser_hasError(self)) && (depth > 0))) {
      if (xn_Cls_Parser_eof(self)) {
        xn_Cls_Parser_fail(self, rt_string_from_c("unterminated type arguments"));
        return ty;
      }
      if (xn_Cls_Parser_at(self, rt_string_from_c("<"))) {
        depth = xn_int_wrap((depth + 1));
      }
      else {
        if (xn_Cls_Parser_at(self, rt_string_from_c(">"))) {
          depth = xn_int_wrap((depth - 1));
        }
      }
      xn_Cls_Token * part = xn_Cls_Parser_advance(self);
      ty = xn_concat(ty, part->text);
    }
  }
  if (xn_Cls_Parser_typeHasFuncSuffix(self)) {
    xn_Cls_Parser_advance(self);
    ty = xn_concat(ty, rt_string_from_c("("));
    if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
      while ((!xn_Cls_Parser_hasError(self))) {
        ty = xn_concat(ty, xn_Cls_Parser_parseType(self));
        if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
          break;
        }
        ty = xn_concat(ty, rt_string_from_c(","));
      }
    }
    xn_Cls_Parser_expect(self, rt_string_from_c(")"));
    ty = xn_concat(ty, rt_string_from_c(")"));
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("["))) {
    xn_Cls_Parser_expect(self, rt_string_from_c("]"));
    ty = xn_concat(ty, rt_string_from_c("[]"));
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("?"))) {
    ty = xn_concat(ty, rt_string_from_c("?"));
  }
  return ty;
}

static rt_string * xn_Cls_Parser_parseNewType(xn_Cls_Parser *self) {
  if (((!xn_Cls_Parser_kind(self, rt_string_from_c("ident"))) && (!xn_Cls_Parser_kind(self, rt_string_from_c("kw"))))) {
    xn_Cls_Parser_fail(self, rt_string_from_c("expected type"));
    return rt_string_from_c("");
  }
  xn_Cls_Token * t = xn_Cls_Parser_advance(self);
  rt_string * ty = t->text;
  while (xn_Cls_Parser_eat(self, rt_string_from_c("."))) {
    xn_Cls_Token * part = xn_Cls_Parser_advance(self);
    ty = xn_concat(xn_concat(ty, rt_string_from_c(".")), part->text);
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("<"))) {
    ty = xn_concat(ty, rt_string_from_c("<"));
    int64_t depth = xn_int_wrap(1);
    while (((!xn_Cls_Parser_hasError(self)) && (depth > 0))) {
      if (xn_Cls_Parser_at(self, rt_string_from_c("<"))) {
        depth = xn_int_wrap((depth + 1));
      }
      else {
        if (xn_Cls_Parser_at(self, rt_string_from_c(">"))) {
          depth = xn_int_wrap((depth - 1));
        }
      }
      xn_Cls_Token * part = xn_Cls_Parser_advance(self);
      ty = xn_concat(ty, part->text);
    }
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("["))) {
    xn_Cls_Parser_expect(self, rt_string_from_c("]"));
    ty = xn_concat(ty, rt_string_from_c("[]"));
  }
  return ty;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseBlock(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  xn_Cls_AstNode * block = xn_Cls_Parser_node(self, rt_string_from_c("Block"), rt_string_from_c(""), t);
  xn_Cls_Parser_expect(self, rt_string_from_c("{"));
  while ((((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c("}")))) && (!xn_Cls_Parser_eof(self)))) {
    xn_Cls_AstNode_add(block, xn_Cls_Parser_parseStmt(self));
  }
  xn_Cls_Parser_expect(self, rt_string_from_c("}"));
  return block;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseCaseBody(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  xn_Cls_AstNode * block = xn_Cls_Parser_node(self, rt_string_from_c("Block"), rt_string_from_c(""), t);
  while ((((((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c("case")))) && (!xn_Cls_Parser_at(self, rt_string_from_c("default")))) && (!xn_Cls_Parser_at(self, rt_string_from_c("}")))) && (!xn_Cls_Parser_eof(self)))) {
    xn_Cls_AstNode_add(block, xn_Cls_Parser_parseStmt(self));
  }
  return block;
}

static xn_Cls_Token * xn_Cls_Parser_look(xn_Cls_Parser *self, int64_t n) {
  int64_t i = xn_int_wrap(xn_int_wrap((self->pos + n)));
  if (((i >= 0) && (i < ((int64_t)self->ts->len)))) {
    return ((xn_Cls_Token *)xn_arr_o_get(self->ts, i));
  }
  return xn_Cls_Token_new(rt_string_from_c("eof"), rt_string_from_c(""), 1, 1);
}

static int xn_Cls_Parser_isLocalDecl(xn_Cls_Parser *self) {
  xn_Cls_Token * a = xn_Cls_Parser_look(self, 0);
  xn_Cls_Token * b = xn_Cls_Parser_look(self, 1);
  xn_Cls_Token * c = xn_Cls_Parser_look(self, 2);
  if ((!(xn_str_eq(a->kind, rt_string_from_c("ident")) || xn_str_eq(a->kind, rt_string_from_c("kw"))))) {
    return 0;
  }
  if (xn_str_eq(b->kind, rt_string_from_c("ident"))) {
    return xn_str_eq(c->text, rt_string_from_c("="));
  }
  if (xn_str_eq(b->text, rt_string_from_c("?"))) {
    return (xn_str_eq(xn_Cls_Parser_look(self, 3)->text, rt_string_from_c("=")) || xn_str_eq(xn_Cls_Parser_look(self, 3)->text, rt_string_from_c(";")));
  }
  if (xn_str_eq(b->text, rt_string_from_c("["))) {
    xn_Cls_Token * d = xn_Cls_Parser_look(self, 2);
    xn_Cls_Token * e = xn_Cls_Parser_look(self, 3);
    if ((xn_str_eq(d->text, rt_string_from_c("]")) && xn_str_eq(e->kind, rt_string_from_c("ident")))) {
      return 1;
    }
  }
  if (xn_str_eq(b->text, rt_string_from_c("<"))) {
    int64_t depth = xn_int_wrap(1);
    int64_t j = xn_int_wrap(2);
    while ((depth > 0)) {
      xn_Cls_Token * t = xn_Cls_Parser_look(self, j);
      if (xn_str_eq(t->kind, rt_string_from_c("eof"))) {
        return 0;
      }
      if (xn_str_eq(t->text, rt_string_from_c("<"))) {
        depth = xn_int_wrap((depth + 1));
      }
      if (xn_str_eq(t->text, rt_string_from_c(">"))) {
        depth = xn_int_wrap((depth - 1));
      }
      j = xn_int_wrap((j + 1));
    }
    xn_Cls_Token * name = xn_Cls_Parser_look(self, j);
    return xn_str_eq(name->kind, rt_string_from_c("ident"));
  }
  if (xn_str_eq(b->text, rt_string_from_c("("))) {
    int64_t depth = xn_int_wrap(1);
    int64_t j = xn_int_wrap(2);
    while ((depth > 0)) {
      xn_Cls_Token * t = xn_Cls_Parser_look(self, j);
      if (xn_str_eq(t->kind, rt_string_from_c("eof"))) {
        return 0;
      }
      if (xn_str_eq(t->text, rt_string_from_c("("))) {
        depth = xn_int_wrap((depth + 1));
      }
      else {
        if (xn_str_eq(t->text, rt_string_from_c(")"))) {
          depth = xn_int_wrap((depth - 1));
        }
      }
      j = xn_int_wrap((j + 1));
    }
    return (xn_str_eq(xn_Cls_Parser_look(self, j)->kind, rt_string_from_c("ident")) && (xn_Cls_Parser_look(self, j)->line == a->line));
  }
  return 0;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseLocal(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  rt_string * ty = xn_Cls_Parser_parseType(self);
  xn_Cls_Token * name = xn_Cls_Parser_advance(self);
  xn_Cls_Parser_expect(self, rt_string_from_c("="));
  xn_Cls_AstNode * init = xn_Cls_Parser_parseExpr(self);
  xn_Cls_Parser_eat(self, rt_string_from_c(";"));
  xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Local"), xn_concat(xn_concat(ty, rt_string_from_c(" ")), name->text), t);
  xn_Cls_AstNode_add(n, init);
  return n;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseStmt(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  if ((xn_Cls_Parser_kind(self, rt_string_from_c("ident")) && xn_str_eq(xn_Cls_Parser_look(self, 1)->text, rt_string_from_c(":")))) {
    xn_Cls_Token * name = xn_Cls_Parser_advance(self);
    xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Label"), name->text, t);
    if ((((!xn_Cls_Parser_at(self, rt_string_from_c("}"))) && (!xn_Cls_Parser_at(self, rt_string_from_c(";")))) && (!xn_Cls_Parser_eof(self)))) {
      xn_Cls_AstNode_add(n, xn_Cls_Parser_parseStmt(self));
    }
    else {
      xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    }
    return n;
  }
  if (xn_Cls_Parser_isLocalDecl(self)) {
    return xn_Cls_Parser_parseLocal(self);
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("goto"))) {
    if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("expected goto label"));
      return xn_Cls_Parser_node(self, rt_string_from_c("error"), rt_string_from_c(""), t);
    }
    xn_Cls_Token * name = xn_Cls_Parser_advance(self);
    xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    return xn_Cls_Parser_node(self, rt_string_from_c("Goto"), name->text, t);
  }
  if ((xn_Cls_Parser_eat(self, rt_string_from_c("defer")) || xn_Cls_Parser_eat(self, rt_string_from_c("errdefer")))) {
    int isErr = 0;
    if (xn_str_eq(t->text, rt_string_from_c("errdefer"))) {
      isErr = 1;
    }
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Defer"), t->text, t);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseStmt(self));
    return n;
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("for"))) {
    if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("expected for-in variable"));
      return xn_Cls_Parser_node(self, rt_string_from_c("error"), rt_string_from_c(""), t);
    }
    xn_Cls_Token * v = xn_Cls_Parser_advance(self);
    xn_Cls_Parser_expect(self, rt_string_from_c("in"));
    xn_Cls_AstNode * first = xn_Cls_Parser_parseExpr(self);
    if (xn_Cls_Parser_at(self, rt_string_from_c(".."))) {
      xn_Cls_Parser_advance(self);
      rt_string * op = rt_string_from_c("..");
      if (xn_Cls_Parser_eat(self, rt_string_from_c("."))) {
        op = rt_string_from_c("...");
      }
      else {
        if (xn_Cls_Parser_eat(self, rt_string_from_c("<"))) {
          op = rt_string_from_c("..<");
        }
        else {
          xn_Cls_Parser_fail(self, rt_string_from_c("expected . or < after .."));
          return xn_Cls_Parser_node(self, rt_string_from_c("error"), rt_string_from_c(""), t);
        }
      }
      xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("ForRange"), xn_concat(xn_concat(op, rt_string_from_c(" ")), v->text), t);
      xn_Cls_AstNode_add(n, first);
      xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
      xn_Cls_AstNode_add(n, xn_Cls_Parser_parseBlock(self));
      return n;
    }
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("ForIn"), v->text, t);
    xn_Cls_AstNode_add(n, first);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseBlock(self));
    return n;
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("return"))) {
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Return"), rt_string_from_c(""), t);
    if ((((!xn_Cls_Parser_at(self, rt_string_from_c("}"))) && (!xn_Cls_Parser_at(self, rt_string_from_c(";")))) && (!xn_Cls_Parser_eof(self)))) {
      xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
    }
    xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    return n;
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("if"))) {
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("If"), rt_string_from_c(""), t);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseBlock(self));
    if (xn_Cls_Parser_eat(self, rt_string_from_c("else"))) {
      if (xn_Cls_Parser_at(self, rt_string_from_c("if"))) {
        xn_Cls_AstNode * eb = xn_Cls_Parser_node(self, rt_string_from_c("Block"), rt_string_from_c(""), t);
        xn_Cls_AstNode_add(eb, xn_Cls_Parser_parseStmt(self));
        xn_Cls_AstNode_add(n, eb);
      }
      else {
        xn_Cls_AstNode_add(n, xn_Cls_Parser_parseBlock(self));
      }
    }
    return n;
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("do"))) {
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("DoWhile"), rt_string_from_c(""), t);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseBlock(self));
    xn_Cls_Parser_expect(self, rt_string_from_c("while"));
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
    xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    return n;
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("while"))) {
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("While"), rt_string_from_c(""), t);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseBlock(self));
    return n;
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("switch"))) {
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Switch"), rt_string_from_c(""), t);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
    xn_Cls_Parser_expect(self, rt_string_from_c("{"));
    int seenDefault = 0;
    while ((((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c("}")))) && (!xn_Cls_Parser_eof(self)))) {
      if (xn_Cls_Parser_eat(self, rt_string_from_c("case"))) {
        if (seenDefault) {
          xn_Cls_Parser_fail(self, rt_string_from_c("case after default"));
          break;
        }
        xn_Cls_AstNode * c = xn_Cls_Parser_node(self, rt_string_from_c("Case"), rt_string_from_c(""), t);
        xn_Cls_AstNode_add(c, xn_Cls_Parser_parseExpr(self));
        xn_Cls_Parser_expect(self, rt_string_from_c(":"));
        xn_Cls_AstNode_add(c, xn_Cls_Parser_parseCaseBody(self));
        xn_Cls_AstNode_add(n, c);
      }
      else {
        if (xn_Cls_Parser_eat(self, rt_string_from_c("default"))) {
          if (seenDefault) {
            xn_Cls_Parser_fail(self, rt_string_from_c("duplicate default"));
            break;
          }
          seenDefault = 1;
          xn_Cls_Parser_expect(self, rt_string_from_c(":"));
          xn_Cls_AstNode * d = xn_Cls_Parser_node(self, rt_string_from_c("Default"), rt_string_from_c(""), t);
          xn_Cls_AstNode_add(d, xn_Cls_Parser_parseCaseBody(self));
          xn_Cls_AstNode_add(n, d);
        }
        else {
          xn_Cls_Parser_fail(self, rt_string_from_c("expected case or default"));
          break;
        }
      }
    }
    xn_Cls_Parser_expect(self, rt_string_from_c("}"));
    return n;
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("throw"))) {
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Throw"), rt_string_from_c(""), t);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
    xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    return n;
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("break"))) {
    xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    return xn_Cls_Parser_node(self, rt_string_from_c("Break"), rt_string_from_c(""), t);
  }
  if (xn_Cls_Parser_eat(self, rt_string_from_c("continue"))) {
    xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    return xn_Cls_Parser_node(self, rt_string_from_c("Continue"), rt_string_from_c(""), t);
  }
  xn_Cls_AstNode * e = xn_Cls_Parser_parseExpr(self);
  if (xn_Cls_Parser_eat(self, rt_string_from_c("="))) {
    xn_Cls_AstNode * a = xn_Cls_Parser_node(self, rt_string_from_c("Assign"), rt_string_from_c("="), t);
    xn_Cls_AstNode_add(a, e);
    xn_Cls_AstNode_add(a, xn_Cls_Parser_parseExpr(self));
    xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    return a;
  }
  xn_Cls_Parser_eat(self, rt_string_from_c(";"));
  xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("ExprStmt"), rt_string_from_c(""), t);
  xn_Cls_AstNode_add(n, e);
  return n;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseExpr(xn_Cls_Parser *self) {
  xn_Cls_AstNode * cond = xn_Cls_Parser_parseOr(self);
  if (xn_Cls_Parser_eat(self, rt_string_from_c("?"))) {
    xn_Cls_AstNode * n = xn_Cls_AstNode_new(rt_string_from_c("Ternary"), rt_string_from_c(""), cond->line, cond->col);
    xn_Cls_AstNode_add(n, cond);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
    xn_Cls_Parser_expect(self, rt_string_from_c(":"));
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
    return n;
  }
  return cond;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseOr(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parseAnd(self);
  while (((!xn_Cls_Parser_hasError(self)) && xn_Cls_Parser_at(self, rt_string_from_c("||")))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Binary"), op->text, op);
    xn_Cls_AstNode_add(n, left);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseAnd(self));
    left = n;
  }
  return left;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseAnd(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parseEquality(self);
  while (((!xn_Cls_Parser_hasError(self)) && xn_Cls_Parser_at(self, rt_string_from_c("&&")))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Binary"), op->text, op);
    xn_Cls_AstNode_add(n, left);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseEquality(self));
    left = n;
  }
  return left;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseEquality(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parseRel(self);
  while (((!xn_Cls_Parser_hasError(self)) && (xn_Cls_Parser_at(self, rt_string_from_c("==")) || xn_Cls_Parser_at(self, rt_string_from_c("!="))))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Binary"), op->text, op);
    xn_Cls_AstNode_add(n, left);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseRel(self));
    left = n;
  }
  return left;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseRel(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parseBitOr(self);
  while (((!xn_Cls_Parser_hasError(self)) && (((xn_Cls_Parser_at(self, rt_string_from_c("<")) || xn_Cls_Parser_at(self, rt_string_from_c("<="))) || xn_Cls_Parser_at(self, rt_string_from_c(">"))) || xn_Cls_Parser_at(self, rt_string_from_c(">="))))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Binary"), op->text, op);
    xn_Cls_AstNode_add(n, left);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseBitOr(self));
    left = n;
  }
  return left;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseBitOr(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parseBitXor(self);
  while (((!xn_Cls_Parser_hasError(self)) && xn_Cls_Parser_at(self, rt_string_from_c("|")))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Binary"), op->text, op);
    xn_Cls_AstNode_add(n, left);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseBitXor(self));
    left = n;
  }
  return left;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseBitXor(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parseBitAnd(self);
  while (((!xn_Cls_Parser_hasError(self)) && xn_Cls_Parser_at(self, rt_string_from_c("^")))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Binary"), op->text, op);
    xn_Cls_AstNode_add(n, left);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseBitAnd(self));
    left = n;
  }
  return left;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseBitAnd(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parseShift(self);
  while (((!xn_Cls_Parser_hasError(self)) && xn_Cls_Parser_at(self, rt_string_from_c("&")))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Binary"), op->text, op);
    xn_Cls_AstNode_add(n, left);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseShift(self));
    left = n;
  }
  return left;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseShift(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parseAdd(self);
  while ((!xn_Cls_Parser_hasError(self))) {
    int right = (xn_Cls_Parser_at(self, rt_string_from_c(">")) && xn_str_eq(xn_Cls_Parser_look(self, 1)->text, rt_string_from_c(">")));
    if (((!xn_Cls_Parser_at(self, rt_string_from_c("<<"))) && (!right))) {
      break;
    }
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    rt_string * opt = op->text;
    if (right) {
      xn_Cls_Parser_advance(self);
      opt = rt_string_from_c(">>");
    }
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Binary"), opt, op);
    xn_Cls_AstNode_add(n, left);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseAdd(self));
    left = n;
  }
  return left;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseAdd(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parseMul(self);
  while (((!xn_Cls_Parser_hasError(self)) && (xn_Cls_Parser_at(self, rt_string_from_c("+")) || xn_Cls_Parser_at(self, rt_string_from_c("-"))))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Binary"), op->text, op);
    xn_Cls_AstNode_add(n, left);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseMul(self));
    left = n;
  }
  return left;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseMul(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parseCast(self);
  while (((!xn_Cls_Parser_hasError(self)) && ((xn_Cls_Parser_at(self, rt_string_from_c("*")) || xn_Cls_Parser_at(self, rt_string_from_c("/"))) || xn_Cls_Parser_at(self, rt_string_from_c("%"))))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Binary"), op->text, op);
    xn_Cls_AstNode_add(n, left);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseCast(self));
    left = n;
  }
  return left;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseCast(xn_Cls_Parser *self) {
  xn_Cls_AstNode * left = xn_Cls_Parser_parsePrimary(self);
  while (((!xn_Cls_Parser_hasError(self)) && (xn_Cls_Parser_at(self, rt_string_from_c("as")) || xn_Cls_Parser_at(self, rt_string_from_c("is"))))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    rt_string * ty = xn_Cls_Parser_parseType(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Cast"), ty, op);
    if (xn_str_eq(op->text, rt_string_from_c("is"))) {
      n->kind = rt_string_from_c("Is");
    }
    xn_Cls_AstNode_add(n, left);
    left = n;
  }
  return left;
}

static int xn_Cls_Parser_hasCall(xn_Cls_Parser *self, xn_Cls_AstNode * n) {
  if ((xn_str_eq(n->kind, rt_string_from_c("Call")) || xn_str_eq(n->kind, rt_string_from_c("MethodCall")))) {
    return 1;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Member")) && (((int64_t)n->kids->len) > 0))) {
    return xn_Cls_Parser_hasCall(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
  }
  return 0;
}

static rt_string * xn_Cls_Parser_memberPath(xn_Cls_Parser *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Name"))) {
    return n->text;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Member")) && (((int64_t)n->kids->len) > 0))) {
    return xn_concat(xn_concat(xn_Cls_Parser_memberPath(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c(".")), n->text);
  }
  return n->text;
}

static rt_string * xn_Cls_Parser_quoted(xn_Cls_Parser *self, rt_string * s) {
  return xn_concat(xn_concat(rt_string_from_c("\""), s), rt_string_from_c("\""));
}

static xn_Cls_AstNode * xn_Cls_Parser_parseInterpolation(xn_Cls_Parser *self, xn_Cls_Token * t) {
  rt_string * raw = t->text;
  if ((((((int64_t)raw->len) >= 2) && xn_str_eq(xn_str_substr(raw, 0, 1), rt_string_from_c("\""))) && xn_str_eq(xn_str_substr(raw, xn_int_wrap((((int64_t)raw->len) - 1)), 1), rt_string_from_c("\"")))) {
    raw = xn_str_substr(raw, 1, xn_int_wrap((((int64_t)raw->len) - 2)));
  }
  xn_Cls_AstNode * result = xn_Cls_AstNode_new(rt_string_from_c("String"), xn_Cls_Parser_quoted(self, rt_string_from_c("")), t->line, t->col);
  rt_string * seg = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)raw->len))) {
    rt_string * c = xn_str_substr(raw, i, 1);
    if (xn_str_eq(c, rt_string_from_c("{"))) {
      if ((!xn_str_eq(seg, rt_string_from_c("")))) {
        xn_Cls_AstNode * lit = xn_Cls_AstNode_new(rt_string_from_c("String"), xn_Cls_Parser_quoted(self, seg), t->line, t->col);
        xn_Cls_AstNode * bin = xn_Cls_AstNode_new(rt_string_from_c("Binary"), rt_string_from_c("+"), t->line, t->col);
        xn_Cls_AstNode_add(bin, result);
        xn_Cls_AstNode_add(bin, lit);
        result = bin;
        seg = rt_string_from_c("");
      }
      int64_t depth = xn_int_wrap(1);
      int64_t j = xn_int_wrap(xn_int_wrap((i + 1)));
      while (((j < ((int64_t)raw->len)) && (depth > 0))) {
        rt_string * d = xn_str_substr(raw, j, 1);
        if (xn_str_eq(d, rt_string_from_c("{"))) {
          depth = xn_int_wrap((depth + 1));
        }
        else {
          if (xn_str_eq(d, rt_string_from_c("}"))) {
            depth = xn_int_wrap((depth - 1));
          }
        }
        if ((depth > 0)) {
          j = xn_int_wrap((j + 1));
        }
      }
      if ((j < ((int64_t)raw->len))) {
        rt_string * exprText = xn_str_substr(raw, xn_int_wrap((i + 1)), xn_int_wrap((xn_int_wrap((j - i)) - 1)));
        xn_Cls_Parser * ep = xn_Cls_Parser_new(xn_lex(exprText));
        xn_Cls_AstNode * ex = xn_Cls_Parser_parseExpr(ep);
        xn_Cls_AstNode * strCall = xn_Cls_AstNode_new(rt_string_from_c("Call"), rt_string_from_c("str"), t->line, t->col);
        xn_Cls_AstNode_add(strCall, ex);
        xn_Cls_AstNode * bin = xn_Cls_AstNode_new(rt_string_from_c("Binary"), rt_string_from_c("+"), t->line, t->col);
        xn_Cls_AstNode_add(bin, result);
        xn_Cls_AstNode_add(bin, strCall);
        result = bin;
        i = j;
      }
    }
    else {
      seg = xn_concat(seg, c);
    }
    i = xn_int_wrap((i + 1));
  }
  if ((!xn_str_eq(seg, rt_string_from_c("")))) {
    xn_Cls_AstNode * lit = xn_Cls_AstNode_new(rt_string_from_c("String"), xn_Cls_Parser_quoted(self, seg), t->line, t->col);
    xn_Cls_AstNode * bin = xn_Cls_AstNode_new(rt_string_from_c("Binary"), rt_string_from_c("+"), t->line, t->col);
    xn_Cls_AstNode_add(bin, result);
    xn_Cls_AstNode_add(bin, lit);
    result = bin;
  }
  return result;
}

static int xn_Cls_Parser_looksLikeLambda(xn_Cls_Parser *self) {
  if ((!xn_Cls_Parser_at(self, rt_string_from_c("(")))) {
    return 0;
  }
  int64_t depth = xn_int_wrap(0);
  int64_t j = xn_int_wrap(0);
  while (1) {
    xn_Cls_Token * t = xn_Cls_Parser_look(self, j);
    if (xn_str_eq(t->kind, rt_string_from_c("eof"))) {
      return 0;
    }
    if (xn_str_eq(t->text, rt_string_from_c("("))) {
      depth = xn_int_wrap((depth + 1));
    }
    else {
      if (xn_str_eq(t->text, rt_string_from_c(")"))) {
        depth = xn_int_wrap((depth - 1));
        if ((depth == 0)) {
          return xn_str_eq(xn_Cls_Parser_look(self, xn_int_wrap((j + 1)))->text, rt_string_from_c("->"));
        }
      }
    }
    j = xn_int_wrap((j + 1));
  }
  return 0;
}

static xn_Cls_AstNode * xn_Cls_Parser_parseLambda(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Lambda"), rt_string_from_c(""), t);
  xn_Cls_Parser_expect(self, rt_string_from_c("("));
  if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
    while ((!xn_Cls_Parser_hasError(self))) {
      if (xn_Cls_Parser_at(self, rt_string_from_c("final"))) {
        xn_Cls_Parser_advance(self);
      }
      rt_string * pt = xn_Cls_Parser_parseType(self);
      if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("expected lambda parameter name"));
        break;
      }
      xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
      xn_Cls_AstNode_add(n, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), pn->line, pn->col));
      if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
        break;
      }
    }
  }
  xn_Cls_Parser_expect(self, rt_string_from_c(")"));
  xn_Cls_Parser_expect(self, rt_string_from_c("->"));
  if (xn_Cls_Parser_at(self, rt_string_from_c("{"))) {
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseBlock(self));
  }
  else {
    xn_Cls_AstNode * b = xn_Cls_Parser_node(self, rt_string_from_c("Block"), rt_string_from_c(""), xn_Cls_Parser_peek(self));
    xn_Cls_AstNode * r = xn_Cls_Parser_node(self, rt_string_from_c("Return"), rt_string_from_c(""), xn_Cls_Parser_peek(self));
    xn_Cls_AstNode_add(r, xn_Cls_Parser_parseExpr(self));
    xn_Cls_AstNode_add(b, r);
    xn_Cls_AstNode_add(n, b);
  }
  return n;
}

static xn_Cls_AstNode * xn_Cls_Parser_parsePrimary(xn_Cls_Parser *self) {
  xn_Cls_Token * t = xn_Cls_Parser_peek(self);
  if (xn_Cls_Parser_kind(self, rt_string_from_c("int"))) {
    xn_Cls_Parser_advance(self);
    return xn_Cls_Parser_node(self, rt_string_from_c("Int"), t->text, t);
  }
  if (xn_Cls_Parser_kind(self, rt_string_from_c("double"))) {
    xn_Cls_Parser_advance(self);
    return xn_Cls_Parser_node(self, rt_string_from_c("Double"), t->text, t);
  }
  if (xn_Cls_Parser_kind(self, rt_string_from_c("string"))) {
    xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("String"), t->text, t);
    while ((xn_Cls_Parser_at(self, rt_string_from_c(".")) && (xn_str_eq(xn_Cls_Parser_look(self, 1)->kind, rt_string_from_c("ident")) || xn_str_eq(xn_Cls_Parser_look(self, 1)->kind, rt_string_from_c("kw"))))) {
      xn_Cls_Parser_advance(self);
      xn_Cls_Token * m = xn_Cls_Parser_advance(self);
      xn_Cls_AstNode * mc = xn_Cls_Parser_node(self, rt_string_from_c("MethodCall"), m->text, t);
      xn_Cls_AstNode_add(mc, n);
      if (xn_Cls_Parser_eat(self, rt_string_from_c("("))) {
        if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
          while ((!xn_Cls_Parser_hasError(self))) {
            xn_Cls_AstNode_add(mc, xn_Cls_Parser_parseExpr(self));
            if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
              break;
            }
          }
        }
        xn_Cls_Parser_expect(self, rt_string_from_c(")"));
      }
      n = mc;
    }
    return n;
  }
  if (xn_Cls_Parser_kind(self, rt_string_from_c("interp"))) {
    xn_Cls_Parser_advance(self);
    return xn_Cls_Parser_parseInterpolation(self, t);
  }
  if ((xn_Cls_Parser_kind(self, rt_string_from_c("kw")) && xn_str_eq(t->text, rt_string_from_c("null")))) {
    xn_Cls_Parser_advance(self);
    return xn_Cls_Parser_node(self, rt_string_from_c("Null"), rt_string_from_c(""), t);
  }
  if (xn_Cls_Parser_kind(self, rt_string_from_c("char"))) {
    xn_Cls_Parser_advance(self);
    return xn_Cls_Parser_node(self, rt_string_from_c("Char"), t->text, t);
  }
  if ((xn_Cls_Parser_kind(self, rt_string_from_c("kw")) && (xn_str_eq(t->text, rt_string_from_c("true")) || xn_str_eq(t->text, rt_string_from_c("false"))))) {
    xn_Cls_Parser_advance(self);
    return xn_Cls_Parser_node(self, rt_string_from_c("Bool"), t->text, t);
  }
  if ((xn_Cls_Parser_at(self, rt_string_from_c("(")) && xn_Cls_Parser_looksLikeLambda(self))) {
    return xn_Cls_Parser_parseLambda(self);
  }
  if (xn_Cls_Parser_at(self, rt_string_from_c("("))) {
    xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_parseExpr(self);
    xn_Cls_Parser_expect(self, rt_string_from_c(")"));
    return n;
  }
  if ((xn_Cls_Parser_at(self, rt_string_from_c("-")) || xn_Cls_Parser_at(self, rt_string_from_c("!")))) {
    xn_Cls_Token * op = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Unary"), op->text, op);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parsePrimary(self));
    return n;
  }
  if ((xn_Cls_Parser_kind(self, rt_string_from_c("kw")) && xn_str_eq(t->text, rt_string_from_c("try")))) {
    xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Try"), rt_string_from_c(""), t);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
    return n;
  }
  if (xn_Cls_Parser_at(self, rt_string_from_c("["))) {
    xn_Cls_Parser_advance(self);
    xn_Cls_Token * after = xn_Cls_Parser_look(self, 0);
    xn_Cls_Token * colon = xn_Cls_Parser_look(self, 1);
    if ((xn_str_eq(after->text, rt_string_from_c(":")) && xn_str_eq(colon->text, rt_string_from_c("]")))) {
      xn_Cls_Parser_advance(self);
      xn_Cls_Parser_advance(self);
      return xn_Cls_Parser_node(self, rt_string_from_c("MapLit"), rt_string_from_c(""), t);
    }
    if ((xn_str_eq(after->kind, rt_string_from_c("string")) && xn_str_eq(colon->text, rt_string_from_c(":")))) {
      xn_Cls_AstNode * m = xn_Cls_Parser_node(self, rt_string_from_c("MapLit"), rt_string_from_c(""), t);
      while ((!xn_Cls_Parser_hasError(self))) {
        xn_Cls_Token * k = xn_Cls_Parser_peek(self);
        if ((!xn_str_eq(k->kind, rt_string_from_c("string")))) {
          xn_Cls_Parser_fail(self, rt_string_from_c("map key must be String"));
          break;
        }
        xn_Cls_Parser_advance(self);
        xn_Cls_AstNode_add(m, xn_Cls_Parser_node(self, rt_string_from_c("String"), k->text, k));
        xn_Cls_Parser_expect(self, rt_string_from_c(":"));
        xn_Cls_AstNode_add(m, xn_Cls_Parser_parseExpr(self));
        if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
          break;
        }
      }
      xn_Cls_Parser_expect(self, rt_string_from_c("]"));
      return m;
    }
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("ArrayLit"), rt_string_from_c(""), t);
    if ((!xn_Cls_Parser_at(self, rt_string_from_c("]")))) {
      while ((!xn_Cls_Parser_hasError(self))) {
        xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
        if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
          break;
        }
      }
    }
    xn_Cls_Parser_expect(self, rt_string_from_c("]"));
    return n;
  }
  if ((xn_Cls_Parser_kind(self, rt_string_from_c("kw")) && xn_str_eq(t->text, rt_string_from_c("new")))) {
    xn_Cls_Parser_advance(self);
    rt_string * ty = xn_Cls_Parser_parseNewType(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("New"), ty, t);
    if (xn_Cls_Parser_eat(self, rt_string_from_c("("))) {
      if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
        while ((!xn_Cls_Parser_hasError(self))) {
          xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
          if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
            break;
          }
        }
      }
      xn_Cls_Parser_expect(self, rt_string_from_c(")"));
    }
    return n;
  }
  if ((xn_Cls_Parser_kind(self, rt_string_from_c("ident")) || xn_Cls_Parser_kind(self, rt_string_from_c("kw")))) {
    xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * n = xn_Cls_Parser_node(self, rt_string_from_c("Name"), t->text, t);
    while ((!xn_Cls_Parser_hasError(self))) {
      if ((xn_Cls_Parser_at(self, rt_string_from_c("<")) && xn_Cls_Parser_looksLikeTypeArgs(self))) {
        xn_Cls_Token * gt = xn_Cls_Parser_peek(self);
        rt_string * targs = xn_Cls_Parser_parseTypeArgsText(self);
        xn_Cls_AstNode * call = xn_Cls_Parser_node(self, rt_string_from_c("GenericCall"), n->text, t);
        xn_Cls_AstNode_add(call, xn_Cls_Parser_node(self, rt_string_from_c("TypeArgs"), targs, gt));
        xn_Cls_Parser_expect(self, rt_string_from_c("("));
        if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
          while ((!xn_Cls_Parser_hasError(self))) {
            xn_Cls_AstNode_add(call, xn_Cls_Parser_parseExpr(self));
            if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
              break;
            }
          }
        }
        xn_Cls_Parser_expect(self, rt_string_from_c(")"));
        n = call;
      }
      else {
        if (xn_Cls_Parser_eat(self, rt_string_from_c("("))) {
          if (xn_str_eq(n->kind, rt_string_from_c("Member"))) {
            xn_Cls_AstNode * recv = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
            if (xn_Cls_Parser_hasCall(self, recv)) {
              xn_Cls_AstNode * call = xn_Cls_Parser_node(self, rt_string_from_c("MethodCall"), n->text, t);
              xn_Cls_AstNode_add(call, recv);
              if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
                while ((!xn_Cls_Parser_hasError(self))) {
                  xn_Cls_AstNode_add(call, xn_Cls_Parser_parseExpr(self));
                  if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
                    break;
                  }
                }
              }
              xn_Cls_Parser_expect(self, rt_string_from_c(")"));
              n = call;
            }
            else {
              rt_string * cname = xn_Cls_Parser_memberPath(self, n);
              xn_Cls_AstNode * call = xn_Cls_Parser_node(self, rt_string_from_c("Call"), cname, t);
              if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
                while ((!xn_Cls_Parser_hasError(self))) {
                  xn_Cls_AstNode_add(call, xn_Cls_Parser_parseExpr(self));
                  if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
                    break;
                  }
                }
              }
              xn_Cls_Parser_expect(self, rt_string_from_c(")"));
              n = call;
            }
          }
          else {
            xn_Cls_AstNode * call = xn_Cls_Parser_node(self, rt_string_from_c("Call"), t->text, t);
            if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
              while ((!xn_Cls_Parser_hasError(self))) {
                xn_Cls_AstNode_add(call, xn_Cls_Parser_parseExpr(self));
                if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
                  break;
                }
              }
            }
            xn_Cls_Parser_expect(self, rt_string_from_c(")"));
            n = call;
          }
        }
        else {
          if (xn_Cls_Parser_eat(self, rt_string_from_c("."))) {
            if (((!xn_Cls_Parser_kind(self, rt_string_from_c("ident"))) && (!xn_Cls_Parser_kind(self, rt_string_from_c("kw"))))) {
              xn_Cls_Parser_fail(self, rt_string_from_c("expected member name"));
              return n;
            }
            xn_Cls_Token * m = xn_Cls_Parser_advance(self);
            xn_Cls_AstNode * mem = xn_Cls_Parser_node(self, rt_string_from_c("Member"), m->text, t);
            xn_Cls_AstNode_add(mem, n);
            n = mem;
          }
          else {
            if (xn_Cls_Parser_eat(self, rt_string_from_c("["))) {
              xn_Cls_AstNode * idx = xn_Cls_Parser_node(self, rt_string_from_c("Index"), rt_string_from_c(""), t);
              xn_Cls_AstNode_add(idx, n);
              xn_Cls_AstNode_add(idx, xn_Cls_Parser_parseExpr(self));
              xn_Cls_Parser_expect(self, rt_string_from_c("]"));
              n = idx;
            }
            else {
              break;
            }
          }
        }
      }
    }
    return n;
  }
  xn_Cls_Parser_fail(self, rt_string_from_c("expected expression"));
  return xn_Cls_Parser_node(self, rt_string_from_c("error"), t->text, t);
}

struct xn_Cls_Mono {
  rt_header hdr;
  xn_Cls_AstNode * program;
  xn_arr_s * scopeNames;
  xn_arr_s * scopeTypes;
};

static const rt_type RT_TYPE_XN_Mono = { "Mono", sizeof(xn_Cls_Mono), NULL, NULL };

static xn_Cls_Mono *xn_Cls_Mono_new(xn_Cls_AstNode * p) {
  xn_Cls_Mono *xn_obj = (xn_Cls_Mono *)rt_gc_new(&RT_TYPE_XN_Mono);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_Mono) - sizeof(rt_header));
  xn_obj->program = 0;
  xn_obj->scopeNames = xn_arr_s_new(4);
  xn_obj->scopeTypes = xn_arr_s_new(4);
  xn_Cls_Mono *self = xn_obj;
  self->program = p;
  self->scopeNames = xn_arr_s_new(0);
  self->scopeTypes = xn_arr_s_new(0);
  return xn_obj;
}

static int xn_Cls_Mono_hasTypeParams(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static xn_arr_s * xn_Cls_Mono_typeParams(xn_Cls_Mono *self, xn_Cls_AstNode * fn);
static int xn_Cls_Mono_identChar(xn_Cls_Mono *self, rt_string * c);
static rt_string * xn_Cls_Mono_subst(xn_Cls_Mono *self, rt_string * text, rt_string * from, rt_string * to);
static rt_string * xn_Cls_Mono_substAll(xn_Cls_Mono *self, rt_string * text, xn_arr_s * names, xn_arr_s * args);
static rt_string * xn_Cls_Mono_mangle(xn_Cls_Mono *self, rt_string * ty);
static int xn_Cls_Mono_isDataEnum(xn_Cls_Mono *self, rt_string * name);
static xn_Cls_AstNode * xn_Cls_Mono_findClass(xn_Cls_Mono *self, rt_string * name);
static xn_arr_s * xn_Cls_Mono_splitArgs(xn_Cls_Mono *self, rt_string * text);
static rt_string * xn_Cls_Mono_instantiateClass(xn_Cls_Mono *self, rt_string * cname, xn_arr_s * args);
static rt_string * xn_Cls_Mono_readAngleType(xn_Cls_Mono *self, rt_string * text, int64_t start);
static void xn_Cls_Mono_instantiateEntryForMap(xn_Cls_Mono *self, rt_string * ty);
static rt_string * xn_Cls_Mono_rewriteType(xn_Cls_Mono *self, rt_string * ty);
static xn_Cls_AstNode * xn_Cls_Mono_cloneSubst(xn_Cls_Mono *self, xn_Cls_AstNode * n, xn_arr_s * names, xn_arr_s * args);
static xn_Cls_AstNode * xn_Cls_Mono_findGeneric(xn_Cls_Mono *self, rt_string * name);
static int xn_Cls_Mono_hasFunc(xn_Cls_Mono *self, rt_string * name);
static rt_string * xn_Cls_Mono_specialize(xn_Cls_Mono *self, xn_Cls_AstNode * fn, xn_arr_s * args);
static rt_string * xn_Cls_Mono_argType(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static void xn_Cls_Mono_addScope(xn_Cls_Mono *self, rt_string * name, rt_string * ty);
static void xn_Cls_Mono_collectScope(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Mono_methodReturnType(xn_Cls_Mono *self, rt_string * recvType, rt_string * mth);
static rt_string * xn_Cls_Mono_simpleExprType(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Mono_inferLambdaReturn(xn_Cls_Mono *self, xn_Cls_AstNode * lambda);
static int xn_Cls_Mono_inferTypePattern(xn_Cls_Mono *self, rt_string * pattern, rt_string * actual, xn_arr_s * names, xn_arr_s * inferred);
static rt_string * xn_Cls_Mono_typeArgsFor(xn_Cls_Mono *self, xn_Cls_AstNode * call);
static xn_Cls_AstNode * xn_Cls_Mono_walk(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static xn_Cls_AstNode * xn_Cls_Mono_cloneAst(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static int xn_Cls_Mono_hasMember(xn_Cls_Mono *self, xn_Cls_AstNode * cls, xn_Cls_AstNode * member);
static void xn_Cls_Mono_flattenClass(xn_Cls_Mono *self, xn_Cls_AstNode * cls);
static xn_Cls_AstNode * xn_Cls_Mono_run(xn_Cls_Mono *self);

static int xn_Cls_Mono_hasTypeParams(xn_Cls_Mono *self, xn_Cls_AstNode * n) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i))->kind, rt_string_from_c("TypeParams"))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static xn_arr_s * xn_Cls_Mono_typeParams(xn_Cls_Mono *self, xn_Cls_AstNode * fn) {
  xn_arr_s *res = xn_arr_s_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fn->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("TypeParams"))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)k->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(k->kids, j))->kind, rt_string_from_c("TypeParam"))) {
          xn_arr_s_push(res, ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, j))->text);
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static int xn_Cls_Mono_identChar(xn_Cls_Mono *self, rt_string * c) {
  rt_string * alphabet = rt_string_from_c("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_");
  return (xn_str_indexof(alphabet, c) >= 0);
}

static rt_string * xn_Cls_Mono_subst(xn_Cls_Mono *self, rt_string * text, rt_string * from, rt_string * to) {
  rt_string * res = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)text->len))) {
    if (((xn_int_wrap((i + ((int64_t)from->len))) <= ((int64_t)text->len)) && xn_str_eq(xn_str_substr(text, i, ((int64_t)from->len)), from))) {
      int leftOk = 1;
      int rightOk = 1;
      if ((i > 0)) {
        rt_string * ch = xn_str_substr(text, xn_int_wrap((i - 1)), 1);
        if (xn_Cls_Mono_identChar(self, ch)) {
          leftOk = 0;
        }
      }
      if ((xn_int_wrap((i + ((int64_t)from->len))) < ((int64_t)text->len))) {
        rt_string * ch = xn_str_substr(text, xn_int_wrap((i + ((int64_t)from->len))), 1);
        if (xn_Cls_Mono_identChar(self, ch)) {
          rightOk = 0;
        }
      }
      if ((leftOk && rightOk)) {
        res = xn_concat(res, to);
        i = xn_int_wrap((i + ((int64_t)from->len)));
      }
      else {
        res = xn_concat(res, xn_str_substr(text, i, 1));
        i = xn_int_wrap((i + 1));
      }
    }
    else {
      res = xn_concat(res, xn_str_substr(text, i, 1));
      i = xn_int_wrap((i + 1));
    }
  }
  return res;
}

static rt_string * xn_Cls_Mono_substAll(xn_Cls_Mono *self, rt_string * text, xn_arr_s * names, xn_arr_s * args) {
  rt_string * res = text;
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)names->len))) {
    res = xn_Cls_Mono_subst(self, res, xn_arr_s_get(names, i), xn_arr_s_get(args, i));
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static rt_string * xn_Cls_Mono_mangle(xn_Cls_Mono *self, rt_string * ty) {
  rt_string * res = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ty->len))) {
    rt_string * c = xn_str_substr(ty, i, 1);
    if (xn_Cls_Mono_identChar(self, c)) {
      res = xn_concat(res, c);
    }
    else {
      res = xn_concat(res, rt_string_from_c("_"));
    }
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static int xn_Cls_Mono_isDataEnum(xn_Cls_Mono *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j))->kind, rt_string_from_c("Data"))) {
          return 1;
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static xn_Cls_AstNode * xn_Cls_Mono_findClass(xn_Cls_Mono *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && xn_str_eq(n->text, name)) || ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name)) && xn_Cls_Mono_isDataEnum(self, name)))) {
      return n;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), 1, 1);
}

static xn_arr_s * xn_Cls_Mono_splitArgs(xn_Cls_Mono *self, rt_string * text) {
  xn_arr_s *res = xn_arr_s_new(0);
  rt_string * cur = rt_string_from_c("");
  int64_t depth = xn_int_wrap(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)text->len))) {
    rt_string * c = xn_str_substr(text, i, 1);
    if (xn_str_eq(c, rt_string_from_c("<"))) {
      depth = xn_int_wrap((depth + 1));
    }
    else {
      if (xn_str_eq(c, rt_string_from_c(">"))) {
        depth = xn_int_wrap((depth - 1));
      }
    }
    if ((xn_str_eq(c, rt_string_from_c(",")) && (depth == 0))) {
      xn_arr_s_push(res, cur);
      cur = rt_string_from_c("");
    }
    else {
      cur = xn_concat(cur, c);
    }
    i = xn_int_wrap((i + 1));
  }
  if ((!xn_str_eq(cur, rt_string_from_c("")))) {
    xn_arr_s_push(res, cur);
  }
  return res;
}

static rt_string * xn_Cls_Mono_instantiateClass(xn_Cls_Mono *self, rt_string * cname, xn_arr_s * args) {
  xn_Cls_AstNode * cls = xn_Cls_Mono_findClass(self, cname);
  if ((xn_str_eq(cls->kind, rt_string_from_c("None")) || (!xn_Cls_Mono_hasTypeParams(self, cls)))) {
    return cname;
  }
  xn_arr_s * names = xn_Cls_Mono_typeParams(self, cls);
  if ((((int64_t)names->len) != ((int64_t)args->len))) {
    return cname;
  }
  rt_string * suffix = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)args->len))) {
    if ((!xn_str_eq(suffix, rt_string_from_c("")))) {
      suffix = xn_concat(suffix, rt_string_from_c("_"));
    }
    suffix = xn_concat(suffix, xn_Cls_Mono_mangle(self, xn_arr_s_get(args, i)));
    i = xn_int_wrap((i + 1));
  }
  rt_string * sname = xn_concat(xn_concat(cname, rt_string_from_c("__")), suffix);
  if ((!xn_str_eq(xn_Cls_Mono_findClass(self, sname)->kind, rt_string_from_c("None")))) {
    return sname;
  }
  xn_Cls_AstNode * clone = xn_Cls_AstNode_new(cls->kind, sname, cls->line, cls->col);
  i = 0;
  while ((i < ((int64_t)cls->kids->len))) {
    if ((!xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i))->kind, rt_string_from_c("TypeParams")))) {
      xn_Cls_AstNode_add(clone, xn_Cls_Mono_cloneSubst(self, ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i)), names, args));
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode_add(self->program, clone);
  return sname;
}

static rt_string * xn_Cls_Mono_readAngleType(xn_Cls_Mono *self, rt_string * text, int64_t start) {
  int64_t depth = xn_int_wrap(0);
  int64_t i = xn_int_wrap(start);
  while ((i < ((int64_t)text->len))) {
    rt_string * c = xn_str_substr(text, i, 1);
    if (xn_str_eq(c, rt_string_from_c("<"))) {
      depth = xn_int_wrap((depth + 1));
    }
    else {
      if (xn_str_eq(c, rt_string_from_c(">"))) {
        depth = xn_int_wrap((depth - 1));
        if ((depth == 0)) {
          return xn_str_substr(text, start, xn_int_wrap((xn_int_wrap((i - start)) + 1)));
        }
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("");
}

static void xn_Cls_Mono_instantiateEntryForMap(xn_Cls_Mono *self, rt_string * ty) {
  int64_t m = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("Map<")));
  if ((m < 0)) {
    return;
  }
  rt_string * mty = xn_Cls_Mono_readAngleType(self, ty, m);
  if ((((int64_t)mty->len) < 6)) {
    return;
  }
  rt_string * inner = xn_str_substr(mty, 4, xn_int_wrap((((int64_t)mty->len) - 5)));
  xn_arr_s * parts = xn_Cls_Mono_splitArgs(self, inner);
  if ((((int64_t)parts->len) < 2)) {
    return;
  }
  rt_string * keyTy = xn_str_trim(xn_arr_s_get(parts, 0));
  rt_string * valTy = xn_str_trim(xn_arr_s_get(parts, 1));
  if (((xn_str_eq(keyTy, rt_string_from_c("String")) && xn_str_eq(valTy, rt_string_from_c("Int"))) || (xn_str_eq(keyTy, rt_string_from_c("Int")) && xn_str_eq(valTy, rt_string_from_c("Int"))))) {
    return;
  }
  xn_Cls_AstNode * ec = xn_Cls_Mono_findClass(self, rt_string_from_c("Entry"));
  if ((xn_str_eq(ec->kind, rt_string_from_c("None")) || (!xn_Cls_Mono_hasTypeParams(self, ec)))) {
    return;
  }
  xn_arr_s *entryArgs = xn_arr_s_new(0);
  xn_arr_s_push(entryArgs, keyTy);
  xn_arr_s_push(entryArgs, valTy);
  xn_Cls_Mono_instantiateClass(self, rt_string_from_c("Entry"), entryArgs);
}

static rt_string * xn_Cls_Mono_rewriteType(xn_Cls_Mono *self, rt_string * ty) {
  rt_string * res = ty;
  int changed = 1;
  while (changed) {
    changed = 0;
    int64_t ci = xn_int_wrap(0);
    while ((ci < ((int64_t)self->program->kids->len))) {
      xn_Cls_AstNode * cls = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, ci));
      if ((((xn_str_eq(cls->kind, rt_string_from_c("Class")) || xn_str_eq(cls->kind, rt_string_from_c("Struct"))) && xn_Cls_Mono_hasTypeParams(self, cls)) && (((int64_t)xn_Cls_Mono_typeParams(self, cls)->len) > 0))) {
        rt_string * needle = xn_concat(cls->text, rt_string_from_c("<"));
        int64_t p = xn_int_wrap(xn_str_indexof(res, needle));
        if ((p >= 0)) {
          int64_t depth = xn_int_wrap(0);
          int64_t j = xn_int_wrap(xn_int_wrap((p + ((int64_t)cls->text->len))));
          int64_t end = xn_int_wrap(xn_int_wrap(-(1)));
          while ((j < ((int64_t)res->len))) {
            rt_string * c = xn_str_substr(res, j, 1);
            if (xn_str_eq(c, rt_string_from_c("<"))) {
              depth = xn_int_wrap((depth + 1));
            }
            else {
              if (xn_str_eq(c, rt_string_from_c(">"))) {
                depth = xn_int_wrap((depth - 1));
                if ((depth == 0)) {
                  end = j;
                  break;
                }
              }
            }
            j = xn_int_wrap((j + 1));
          }
          if ((end > p)) {
            rt_string * inner = xn_str_substr(res, xn_int_wrap((p + ((int64_t)needle->len))), xn_int_wrap((xn_int_wrap((end - p)) - ((int64_t)needle->len))));
            rt_string * sname = xn_Cls_Mono_instantiateClass(self, cls->text, xn_Cls_Mono_splitArgs(self, inner));
            res = xn_concat(xn_concat(xn_str_substr(res, 0, p), sname), xn_str_substr(res, xn_int_wrap((end + 1)), xn_int_wrap((xn_int_wrap((((int64_t)res->len) - end)) - 1))));
            changed = 1;
          }
        }
      }
      ci = xn_int_wrap((ci + 1));
    }
  }
  xn_Cls_Mono_instantiateEntryForMap(self, res);
  return res;
}

static xn_Cls_AstNode * xn_Cls_Mono_cloneSubst(xn_Cls_Mono *self, xn_Cls_AstNode * n, xn_arr_s * names, xn_arr_s * args) {
  rt_string * text = n->text;
  if ((((((((xn_str_eq(n->kind, rt_string_from_c("Ret")) || xn_str_eq(n->kind, rt_string_from_c("Param"))) || xn_str_eq(n->kind, rt_string_from_c("Field"))) || xn_str_eq(n->kind, rt_string_from_c("Local"))) || xn_str_eq(n->kind, rt_string_from_c("New"))) || xn_str_eq(n->kind, rt_string_from_c("TypeArgs"))) || xn_str_eq(n->kind, rt_string_from_c("Base"))) || xn_str_eq(n->kind, rt_string_from_c("Implements")))) {
    text = xn_Cls_Mono_substAll(self, text, names, args);
  }
  xn_Cls_AstNode * c = xn_Cls_AstNode_new(n->kind, text, n->line, n->col);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    if ((!xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i))->kind, rt_string_from_c("TypeParams")))) {
      xn_Cls_AstNode_add(c, xn_Cls_Mono_cloneSubst(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), names, args));
    }
    i = xn_int_wrap((i + 1));
  }
  return c;
}

static xn_Cls_AstNode * xn_Cls_Mono_findGeneric(xn_Cls_Mono *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (((xn_str_eq(n->kind, rt_string_from_c("Func")) && xn_str_eq(n->text, name)) && xn_Cls_Mono_hasTypeParams(self, n))) {
      return n;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), 1, 1);
}

static int xn_Cls_Mono_hasFunc(xn_Cls_Mono *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Func")) && xn_str_eq(n->text, name))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static rt_string * xn_Cls_Mono_specialize(xn_Cls_Mono *self, xn_Cls_AstNode * fn, xn_arr_s * args) {
  xn_arr_s * names = xn_Cls_Mono_typeParams(self, fn);
  if ((((int64_t)names->len) != ((int64_t)args->len))) {
    return rt_string_from_c("");
  }
  rt_string * suffix = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)args->len))) {
    if ((!xn_str_eq(suffix, rt_string_from_c("")))) {
      suffix = xn_concat(suffix, rt_string_from_c("_"));
    }
    suffix = xn_concat(suffix, xn_Cls_Mono_mangle(self, xn_arr_s_get(args, i)));
    i = xn_int_wrap((i + 1));
  }
  rt_string * sname = xn_concat(xn_concat(fn->text, rt_string_from_c("__")), suffix);
  if (xn_Cls_Mono_hasFunc(self, sname)) {
    return sname;
  }
  xn_Cls_AstNode * clone = xn_Cls_AstNode_new(rt_string_from_c("Func"), sname, fn->line, fn->col);
  i = 0;
  while ((i < ((int64_t)fn->kids->len))) {
    if ((!xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i))->kind, rt_string_from_c("TypeParams")))) {
      xn_Cls_AstNode_add(clone, xn_Cls_Mono_cloneSubst(self, ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i)), names, args));
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode_add(self->program, clone);
  return sname;
}

static rt_string * xn_Cls_Mono_argType(xn_Cls_Mono *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Int"))) {
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Double"))) {
    return rt_string_from_c("Double");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    return rt_string_from_c("String");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Null"))) {
    return rt_string_from_c("Null");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Bool"))) {
    return rt_string_from_c("Bool");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Char"))) {
    return rt_string_from_c("Char");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Name"))) {
    int64_t i = xn_int_wrap(xn_int_wrap((((int64_t)self->scopeNames->len) - 1)));
    while ((i >= 0)) {
      if (xn_str_eq(xn_arr_s_get(self->scopeNames, i), n->text)) {
        return xn_arr_s_get(self->scopeTypes, i);
      }
      i = xn_int_wrap((i - 1));
    }
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("ArrayLit")) && (((int64_t)n->kids->len) > 0))) {
    rt_string * et = xn_Cls_Mono_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if ((!xn_str_eq(et, rt_string_from_c("Any")))) {
      return xn_concat(xn_concat(rt_string_from_c("List<"), et), rt_string_from_c(">"));
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("New"))) {
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
    int64_t ci = xn_int_wrap(0);
    while ((ci < ((int64_t)self->program->kids->len))) {
      xn_Cls_AstNode * cf = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, ci));
      if ((xn_str_eq(cf->kind, rt_string_from_c("Func")) && xn_str_eq(cf->text, n->text))) {
        int64_t ri = xn_int_wrap(0);
        while ((ri < ((int64_t)cf->kids->len))) {
          if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(cf->kids, ri))->kind, rt_string_from_c("Ret"))) {
            return ((xn_Cls_AstNode *)xn_arr_o_get(cf->kids, ri))->text;
          }
          ri = xn_int_wrap((ri + 1));
        }
      }
      ci = xn_int_wrap((ci + 1));
    }
  }
  return rt_string_from_c("Any");
}

static void xn_Cls_Mono_addScope(xn_Cls_Mono *self, rt_string * name, rt_string * ty) {
  xn_arr_s_push(self->scopeNames, name);
  xn_arr_s_push(self->scopeTypes, ty);
}

static void xn_Cls_Mono_collectScope(xn_Cls_Mono *self, xn_Cls_AstNode * n) {
  if ((xn_str_eq(n->kind, rt_string_from_c("Param")) || xn_str_eq(n->kind, rt_string_from_c("Local")))) {
    rt_string * text = n->text;
    int64_t splitAt = xn_int_wrap(xn_int_wrap(-(1)));
    int64_t si = xn_int_wrap(0);
    while ((si < ((int64_t)text->len))) {
      if (xn_str_eq(xn_str_substr(text, si, 1), rt_string_from_c(" "))) {
        splitAt = si;
      }
      si = xn_int_wrap((si + 1));
    }
    if (((splitAt > 0) && (xn_int_wrap((splitAt + 1)) < ((int64_t)text->len)))) {
      xn_Cls_Mono_addScope(self, xn_str_substr(text, xn_int_wrap((splitAt + 1)), xn_int_wrap((xn_int_wrap((((int64_t)text->len) - splitAt)) - 1))), xn_str_substr(text, 0, splitAt));
    }
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_Mono_collectScope(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)));
    i = xn_int_wrap((i + 1));
  }
}

static rt_string * xn_Cls_Mono_methodReturnType(xn_Cls_Mono *self, rt_string * recvType, rt_string * mth) {
  if (xn_str_startswith(recvType, rt_string_from_c("Result<"))) {
    rt_string * inner = xn_str_substr(recvType, 7, xn_int_wrap((((int64_t)recvType->len) - 8)));
    xn_arr_s * parts = xn_splitTop(inner);
    if ((xn_str_eq(mth, rt_string_from_c("value")) && (((int64_t)parts->len) >= 1))) {
      return xn_str_trim(xn_arr_s_get(parts, 0));
    }
    if ((xn_str_eq(mth, rt_string_from_c("error")) && (((int64_t)parts->len) >= 2))) {
      return xn_str_trim(xn_arr_s_get(parts, 1));
    }
    if ((xn_str_eq(mth, rt_string_from_c("isOk")) || xn_str_eq(mth, rt_string_from_c("isErr")))) {
      return rt_string_from_c("Bool");
    }
    return rt_string_from_c("Any");
  }
  if (xn_str_startswith(recvType, rt_string_from_c("List<"))) {
    rt_string * elem = xn_str_substr(recvType, 5, xn_int_wrap((((int64_t)recvType->len) - 6)));
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("get"))) {
      return elem;
    }
    if (xn_str_eq(mth, rt_string_from_c("tryGet"))) {
      return xn_concat(xn_concat(rt_string_from_c("Result<"), elem), rt_string_from_c(",Error>"));
    }
    if (xn_str_eq(mth, rt_string_from_c("isEmpty"))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("clear"))) {
      return rt_string_from_c("Unit");
    }
    return rt_string_from_c("Any");
  }
  if (xn_str_startswith(recvType, rt_string_from_c("Map<"))) {
    rt_string * inner = xn_str_substr(recvType, 4, xn_int_wrap((((int64_t)recvType->len) - 5)));
    xn_arr_s * parts = xn_splitTop(inner);
    if ((((int64_t)parts->len) < 2)) {
      return rt_string_from_c("Any");
    }
    rt_string * key = xn_str_trim(xn_arr_s_get(parts, 0));
    rt_string * val = xn_str_trim(xn_arr_s_get(parts, 1));
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return rt_string_from_c("Int");
    }
    if (((xn_str_eq(mth, rt_string_from_c("has")) || xn_str_eq(mth, rt_string_from_c("put"))) || xn_str_eq(mth, rt_string_from_c("remove")))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(mth, rt_string_from_c("getOr")) || xn_str_eq(mth, rt_string_from_c("removeOr")))) {
      return val;
    }
    if (xn_str_eq(mth, rt_string_from_c("tryGet"))) {
      return xn_concat(xn_concat(rt_string_from_c("Result<"), val), rt_string_from_c(",Error>"));
    }
    if (xn_str_eq(mth, rt_string_from_c("keys"))) {
      return xn_concat(xn_concat(rt_string_from_c("List<"), key), rt_string_from_c(">"));
    }
    if (xn_str_eq(mth, rt_string_from_c("values"))) {
      return xn_concat(xn_concat(rt_string_from_c("List<"), val), rt_string_from_c(">"));
    }
    if (xn_str_eq(mth, rt_string_from_c("entries"))) {
      if ((xn_str_eq(key, rt_string_from_c("String")) && xn_str_eq(val, rt_string_from_c("Int")))) {
        return rt_string_from_c("List<Pair>");
      }
      if ((xn_str_eq(key, rt_string_from_c("Int")) && xn_str_eq(val, rt_string_from_c("Int")))) {
        return rt_string_from_c("List<IntPair>");
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("List<Entry__"), xn_Cls_Mono_mangle(self, key)), rt_string_from_c("_")), xn_Cls_Mono_mangle(self, val)), rt_string_from_c(">"));
    }
    if (xn_str_eq(mth, rt_string_from_c("clear"))) {
      return rt_string_from_c("Unit");
    }
    return rt_string_from_c("Any");
  }
  if (xn_str_startswith(recvType, rt_string_from_c("Set<"))) {
    rt_string * elem = xn_str_substr(recvType, 4, xn_int_wrap((((int64_t)recvType->len) - 5)));
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return rt_string_from_c("Int");
    }
    if (((xn_str_eq(mth, rt_string_from_c("has")) || xn_str_eq(mth, rt_string_from_c("add"))) || xn_str_eq(mth, rt_string_from_c("remove")))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("clear"))) {
      return rt_string_from_c("Unit");
    }
    return rt_string_from_c("Any");
  }
  xn_Cls_AstNode * cls = xn_Cls_Mono_findClass(self, recvType);
  if ((!xn_str_eq(cls->kind, rt_string_from_c("None")))) {
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)cls->kids->len))) {
      xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
      if (((xn_str_eq(k->kind, rt_string_from_c("Method")) || xn_str_eq(k->kind, rt_string_from_c("Func"))) && xn_str_eq(k->text, mth))) {
        int64_t r = xn_int_wrap(0);
        while ((r < ((int64_t)k->kids->len))) {
          if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(k->kids, r))->kind, rt_string_from_c("Ret"))) {
            return ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, r))->text;
          }
          r = xn_int_wrap((r + 1));
        }
      }
      i = xn_int_wrap((i + 1));
    }
  }
  int64_t pi = xn_int_wrap(0);
  while ((pi < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * pn = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, pi));
    if ((xn_str_eq(pn->kind, rt_string_from_c("Protocol")) && xn_str_eq(pn->text, recvType))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)pn->kids->len))) {
        xn_Cls_AstNode * sig = ((xn_Cls_AstNode *)xn_arr_o_get(pn->kids, j));
        if (((xn_str_eq(sig->kind, rt_string_from_c("Sig")) || xn_str_eq(sig->kind, rt_string_from_c("Method"))) && xn_str_eq(sig->text, mth))) {
          int64_t r = xn_int_wrap(0);
          while ((r < ((int64_t)sig->kids->len))) {
            if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(sig->kids, r))->kind, rt_string_from_c("Ret"))) {
              return ((xn_Cls_AstNode *)xn_arr_o_get(sig->kids, r))->text;
            }
            r = xn_int_wrap((r + 1));
          }
        }
        j = xn_int_wrap((j + 1));
      }
    }
    pi = xn_int_wrap((pi + 1));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_Mono_simpleExprType(xn_Cls_Mono *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Int"))) {
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    return rt_string_from_c("String");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Bool"))) {
    return rt_string_from_c("Bool");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Double"))) {
    return rt_string_from_c("Double");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Char"))) {
    return rt_string_from_c("Char");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Null"))) {
    return rt_string_from_c("Null");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("New"))) {
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Name"))) {
    int64_t i = xn_int_wrap(xn_int_wrap((((int64_t)self->scopeNames->len) - 1)));
    while ((i >= 0)) {
      if (xn_str_eq(xn_arr_s_get(self->scopeNames, i), n->text)) {
        return xn_arr_s_get(self->scopeTypes, i);
      }
      i = xn_int_wrap((i - 1));
    }
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Unary")) && (((int64_t)n->kids->len) > 0))) {
    return xn_Cls_Mono_simpleExprType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Binary")) && (((int64_t)n->kids->len) > 1))) {
    rt_string * lt = xn_Cls_Mono_simpleExprType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    rt_string * rt = xn_Cls_Mono_simpleExprType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
    if ((((((((xn_str_eq(n->text, rt_string_from_c("==")) || xn_str_eq(n->text, rt_string_from_c("!="))) || xn_str_eq(n->text, rt_string_from_c("<"))) || xn_str_eq(n->text, rt_string_from_c("<="))) || xn_str_eq(n->text, rt_string_from_c(">"))) || xn_str_eq(n->text, rt_string_from_c(">="))) || xn_str_eq(n->text, rt_string_from_c("&&"))) || xn_str_eq(n->text, rt_string_from_c("||")))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(lt, rt_string_from_c("String")) && xn_str_eq(rt, rt_string_from_c("String")))) {
      return rt_string_from_c("String");
    }
    if ((xn_str_eq(lt, rt_string_from_c("Double")) || xn_str_eq(rt, rt_string_from_c("Double")))) {
      return rt_string_from_c("Double");
    }
    if ((xn_str_eq(lt, rt_string_from_c("Long")) || xn_str_eq(rt, rt_string_from_c("Long")))) {
      return rt_string_from_c("Long");
    }
    if ((xn_str_eq(lt, rt_string_from_c("Int")) && xn_str_eq(rt, rt_string_from_c("Int")))) {
      return rt_string_from_c("Int");
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("MethodCall"))) {
    if ((((xn_str_eq(n->text, rt_string_from_c("describe")) || xn_str_eq(n->text, rt_string_from_c("message"))) || xn_str_eq(n->text, rt_string_from_c("code"))) || xn_str_eq(n->text, rt_string_from_c("toString")))) {
      return rt_string_from_c("String");
    }
    if (xn_str_eq(n->text, rt_string_from_c("kind"))) {
      return rt_string_from_c("ErrorKind");
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
    if (xn_str_eq(n->text, rt_string_from_c("str"))) {
      return rt_string_from_c("String");
    }
    int64_t dot = xn_int_wrap(xn_lastDot(n->text));
    if ((dot > 0)) {
      rt_string * recv = xn_str_substr(n->text, 0, dot);
      rt_string * mth = xn_str_substr(n->text, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)n->text->len) - dot)) - 1)));
      if (xn_Cls_Mono_identChar(self, xn_str_substr(recv, 0, 1))) {
        xn_Cls_AstNode * recvNode = xn_Cls_AstNode_new(rt_string_from_c("Name"), recv, n->line, n->col);
        rt_string * recvType = xn_Cls_Mono_simpleExprType(self, recvNode);
        rt_string * inferred = xn_Cls_Mono_methodReturnType(self, recvType, mth);
        if ((!xn_str_eq(inferred, rt_string_from_c("Any")))) {
          return inferred;
        }
      }
      if ((((xn_str_eq(mth, rt_string_from_c("describe")) || xn_str_eq(mth, rt_string_from_c("message"))) || xn_str_eq(mth, rt_string_from_c("code"))) || xn_str_eq(mth, rt_string_from_c("toString")))) {
        return rt_string_from_c("String");
      }
      if (xn_str_eq(mth, rt_string_from_c("kind"))) {
        return rt_string_from_c("ErrorKind");
      }
    }
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)self->program->kids->len))) {
      xn_Cls_AstNode * fn = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
      if ((xn_str_eq(fn->kind, rt_string_from_c("Func")) && xn_str_eq(fn->text, n->text))) {
        int64_t r = xn_int_wrap(0);
        while ((r < ((int64_t)fn->kids->len))) {
          if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, r))->kind, rt_string_from_c("Ret"))) {
            return ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, r))->text;
          }
          r = xn_int_wrap((r + 1));
        }
      }
      i = xn_int_wrap((i + 1));
    }
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_Mono_inferLambdaReturn(xn_Cls_Mono *self, xn_Cls_AstNode * lambda) {
  int64_t mark = xn_int_wrap(((int64_t)self->scopeNames->len));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)lambda->kids->len))) {
    xn_Cls_AstNode * c = ((xn_Cls_AstNode *)xn_arr_o_get(lambda->kids, i));
    if (xn_str_eq(c->kind, rt_string_from_c("Param"))) {
      rt_string * text = c->text;
      int64_t split = xn_int_wrap(xn_int_wrap(-(1)));
      int64_t si = xn_int_wrap(0);
      while ((si < ((int64_t)text->len))) {
        if (xn_str_eq(xn_str_substr(text, si, 1), rt_string_from_c(" "))) {
          split = si;
        }
        si = xn_int_wrap((si + 1));
      }
      if ((split > 0)) {
        xn_Cls_Mono_addScope(self, xn_str_substr(text, xn_int_wrap((split + 1)), xn_int_wrap((xn_int_wrap((((int64_t)text->len) - split)) - 1))), xn_str_substr(text, 0, split));
      }
    }
    if (xn_str_eq(c->kind, rt_string_from_c("Block"))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)c->kids->len))) {
        xn_Cls_AstNode * st = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, j));
        if ((xn_str_eq(st->kind, rt_string_from_c("Return")) && (((int64_t)st->kids->len) > 0))) {
          rt_string * result = xn_Cls_Mono_simpleExprType(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
          while ((((int64_t)self->scopeNames->len) > mark)) {
            xn_arr_s_remove(self->scopeNames, xn_int_wrap((((int64_t)self->scopeNames->len) - 1)));
            xn_arr_s_remove(self->scopeTypes, xn_int_wrap((((int64_t)self->scopeTypes->len) - 1)));
          }
          return result;
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  while ((((int64_t)self->scopeNames->len) > mark)) {
    xn_arr_s_remove(self->scopeNames, xn_int_wrap((((int64_t)self->scopeNames->len) - 1)));
    xn_arr_s_remove(self->scopeTypes, xn_int_wrap((((int64_t)self->scopeTypes->len) - 1)));
  }
  return rt_string_from_c("Any");
}

static int xn_Cls_Mono_inferTypePattern(xn_Cls_Mono *self, rt_string * pattern, rt_string * actual, xn_arr_s * names, xn_arr_s * inferred) {
  int64_t ni = xn_int_wrap(0);
  while ((ni < ((int64_t)names->len))) {
    if (xn_str_eq(pattern, xn_arr_s_get(names, ni))) {
      if (xn_str_eq(actual, rt_string_from_c("Any"))) {
        return 1;
      }
      if (xn_str_eq(xn_arr_s_get(inferred, ni), rt_string_from_c(""))) {
        xn_arr_s_set(inferred, ni, actual);
      }
      else {
        if ((!xn_str_eq(xn_arr_s_get(inferred, ni), actual))) {
          return 0;
        }
      }
      return 1;
    }
    ni = xn_int_wrap((ni + 1));
  }
  if ((((xn_str_startswith(pattern, rt_string_from_c("List<")) && xn_str_startswith(actual, rt_string_from_c("List<"))) && xn_str_eq(xn_str_substr(pattern, xn_int_wrap((((int64_t)pattern->len) - 1)), 1), rt_string_from_c(">"))) && xn_str_eq(xn_str_substr(actual, xn_int_wrap((((int64_t)actual->len) - 1)), 1), rt_string_from_c(">")))) {
    return xn_Cls_Mono_inferTypePattern(self, xn_str_substr(pattern, 5, xn_int_wrap((((int64_t)pattern->len) - 6))), xn_str_substr(actual, 5, xn_int_wrap((((int64_t)actual->len) - 6))), names, inferred);
  }
  if ((((xn_str_startswith(pattern, rt_string_from_c("Result<")) && xn_str_startswith(actual, rt_string_from_c("Result<"))) && xn_str_eq(xn_str_substr(pattern, xn_int_wrap((((int64_t)pattern->len) - 1)), 1), rt_string_from_c(">"))) && xn_str_eq(xn_str_substr(actual, xn_int_wrap((((int64_t)actual->len) - 1)), 1), rt_string_from_c(">")))) {
    xn_arr_s * patternParts = xn_splitTop(xn_str_substr(pattern, 7, xn_int_wrap((((int64_t)pattern->len) - 8))));
    xn_arr_s * actualParts = xn_splitTop(xn_str_substr(actual, 7, xn_int_wrap((((int64_t)actual->len) - 8))));
    if (((((int64_t)patternParts->len) != 2) || (((int64_t)actualParts->len) != 2))) {
      return 0;
    }
    if ((!xn_Cls_Mono_inferTypePattern(self, xn_arr_s_get(patternParts, 0), xn_arr_s_get(actualParts, 0), names, inferred))) {
      return 0;
    }
    return xn_Cls_Mono_inferTypePattern(self, xn_arr_s_get(patternParts, 1), xn_arr_s_get(actualParts, 1), names, inferred);
  }
  if (((xn_str_indexof(pattern, rt_string_from_c("(")) >= 0) && xn_str_eq(actual, rt_string_from_c("Any")))) {
    return 1;
  }
  return xn_str_eq(pattern, actual);
}

static rt_string * xn_Cls_Mono_typeArgsFor(xn_Cls_Mono *self, xn_Cls_AstNode * call) {
  if ((xn_str_eq(call->kind, rt_string_from_c("GenericCall")) && (((int64_t)call->kids->len) > 0))) {
    return ((xn_Cls_AstNode *)xn_arr_o_get(call->kids, 0))->text;
  }
  xn_Cls_AstNode * fn = xn_Cls_Mono_findGeneric(self, call->text);
  if ((!xn_str_eq(fn->kind, rt_string_from_c("Func")))) {
    return rt_string_from_c("");
  }
  xn_arr_s * names = xn_Cls_Mono_typeParams(self, fn);
  if ((((int64_t)names->len) == 0)) {
    return rt_string_from_c("");
  }
  xn_arr_s *actual = xn_arr_s_new(0);
  int64_t ai = xn_int_wrap(0);
  while ((ai < ((int64_t)call->kids->len))) {
    xn_arr_s_push(actual, xn_Cls_Mono_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(call->kids, ai))));
    ai = xn_int_wrap((ai + 1));
  }
  xn_arr_s *inferred = xn_arr_s_new(0);
  int64_t ni = xn_int_wrap(0);
  while ((ni < ((int64_t)names->len))) {
    xn_arr_s_push(inferred, rt_string_from_c(""));
    ni = xn_int_wrap((ni + 1));
  }
  int64_t pi = xn_int_wrap(0);
  int64_t argi = xn_int_wrap(0);
  while ((pi < ((int64_t)fn->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, pi));
    if (xn_str_eq(p->kind, rt_string_from_c("Param"))) {
      rt_string * ptext = p->text;
      int64_t splitAt = xn_int_wrap(xn_int_wrap(-(1)));
      int64_t si = xn_int_wrap(0);
      while ((si < ((int64_t)ptext->len))) {
        if (xn_str_eq(xn_str_substr(ptext, si, 1), rt_string_from_c(" "))) {
          splitAt = si;
        }
        si = xn_int_wrap((si + 1));
      }
      if (((splitAt > 0) && (argi < ((int64_t)actual->len)))) {
        xn_Cls_AstNode * argNode = ((xn_Cls_AstNode *)xn_arr_o_get(call->kids, argi));
        rt_string * patternType = xn_str_substr(ptext, 0, splitAt);
        if ((xn_str_eq(argNode->kind, rt_string_from_c("Lambda")) && (xn_str_indexof(patternType, rt_string_from_c("(")) >= 0))) {
          rt_string * returnPattern = xn_str_substr(patternType, 0, xn_str_indexof(patternType, rt_string_from_c("(")));
          rt_string * returnType = xn_Cls_Mono_inferLambdaReturn(self, argNode);
          if (((!xn_str_eq(returnType, rt_string_from_c("Any"))) && (!xn_Cls_Mono_inferTypePattern(self, returnPattern, returnType, names, inferred)))) {
            return rt_string_from_c("");
          }
          rt_string * inside = xn_str_substr(patternType, xn_int_wrap((xn_str_indexof(patternType, rt_string_from_c("(")) + 1)), xn_int_wrap((xn_int_wrap((((int64_t)patternType->len) - xn_str_indexof(patternType, rt_string_from_c("(")))) - 2)));
          xn_arr_s * patternArgs = xn_splitTop(inside);
          int64_t lpi = xn_int_wrap(0);
          int64_t api = xn_int_wrap(0);
          while ((lpi < ((int64_t)argNode->kids->len))) {
            xn_Cls_AstNode * lp = ((xn_Cls_AstNode *)xn_arr_o_get(argNode->kids, lpi));
            if ((xn_str_eq(lp->kind, rt_string_from_c("Param")) && (api < ((int64_t)patternArgs->len)))) {
              rt_string * lpText = lp->text;
              int64_t lpSplit = xn_int_wrap(xn_int_wrap(-(1)));
              int64_t lsi = xn_int_wrap(0);
              while ((lsi < ((int64_t)lpText->len))) {
                if (xn_str_eq(xn_str_substr(lpText, lsi, 1), rt_string_from_c(" "))) {
                  lpSplit = lsi;
                }
                lsi = xn_int_wrap((lsi + 1));
              }
              if (((lpSplit > 0) && (!xn_Cls_Mono_inferTypePattern(self, xn_str_trim(xn_arr_s_get(patternArgs, api)), xn_str_substr(lpText, 0, lpSplit), names, inferred)))) {
                return rt_string_from_c("");
              }
              api = xn_int_wrap((api + 1));
            }
            lpi = xn_int_wrap((lpi + 1));
          }
        }
        else {
          if ((!xn_Cls_Mono_inferTypePattern(self, patternType, xn_arr_s_get(actual, argi), names, inferred))) {
            return rt_string_from_c("");
          }
        }
      }
      argi = xn_int_wrap((argi + 1));
    }
    pi = xn_int_wrap((pi + 1));
  }
  rt_string * res = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)inferred->len))) {
    if (xn_str_eq(xn_arr_s_get(inferred, i), rt_string_from_c(""))) {
      return rt_string_from_c("");
    }
    if ((!xn_str_eq(res, rt_string_from_c("")))) {
      res = xn_concat(res, rt_string_from_c(","));
    }
    res = xn_concat(res, xn_arr_s_get(inferred, i));
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static xn_Cls_AstNode * xn_Cls_Mono_walk(xn_Cls_Mono *self, xn_Cls_AstNode * n) {
  int isFn = xn_str_eq(n->kind, rt_string_from_c("Func"));
  if (isFn) {
    xn_Cls_Mono_collectScope(self, n);
  }
  if ((((((((xn_str_eq(n->kind, rt_string_from_c("Ret")) || xn_str_eq(n->kind, rt_string_from_c("Param"))) || xn_str_eq(n->kind, rt_string_from_c("Field"))) || xn_str_eq(n->kind, rt_string_from_c("Local"))) || xn_str_eq(n->kind, rt_string_from_c("New"))) || xn_str_eq(n->kind, rt_string_from_c("TypeArgs"))) || xn_str_eq(n->kind, rt_string_from_c("Base"))) || xn_str_eq(n->kind, rt_string_from_c("Implements")))) {
    n->text = xn_Cls_Mono_rewriteType(self, n->text);
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("GenericCall")) || (xn_str_eq(n->kind, rt_string_from_c("Call")) && xn_str_eq(xn_Cls_Mono_findGeneric(self, n->text)->kind, rt_string_from_c("Func"))))) {
    xn_Cls_AstNode * fn = xn_Cls_Mono_findGeneric(self, n->text);
    if (xn_str_eq(fn->kind, rt_string_from_c("Func"))) {
      rt_string * tas = xn_Cls_Mono_typeArgsFor(self, n);
      if ((!xn_str_eq(tas, rt_string_from_c("")))) {
        xn_arr_s * args = xn_splitTop(tas);
        rt_string * sname = xn_Cls_Mono_specialize(self, fn, args);
        if ((!xn_str_eq(sname, rt_string_from_c("")))) {
          n->kind = rt_string_from_c("Call");
          n->text = sname;
          if (((((int64_t)n->kids->len) > 0) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))->kind, rt_string_from_c("TypeArgs")))) {
            xn_arr_o_remove(n->kids, 0);
          }
        }
      }
    }
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_AstNode_setKid(n, i, xn_Cls_Mono_walk(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i))));
    i = xn_int_wrap((i + 1));
  }
  return n;
}

static xn_Cls_AstNode * xn_Cls_Mono_cloneAst(xn_Cls_Mono *self, xn_Cls_AstNode * n) {
  xn_Cls_AstNode * c = xn_Cls_AstNode_new(n->kind, n->text, n->line, n->col);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_AstNode_add(c, xn_Cls_Mono_cloneAst(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i))));
    i = xn_int_wrap((i + 1));
  }
  return c;
}

static int xn_Cls_Mono_hasMember(xn_Cls_Mono *self, xn_Cls_AstNode * cls, xn_Cls_AstNode * member) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if ((xn_str_eq(k->kind, member->kind) && xn_str_eq(k->text, member->text))) {
      return 1;
    }
    if ((xn_str_eq(k->kind, rt_string_from_c("Field")) && xn_str_eq(member->kind, rt_string_from_c("Field")))) {
      xn_arr_s * a = xn_str_split(k->text, rt_string_from_c(" "));
      xn_arr_s * b = xn_str_split(member->text, rt_string_from_c(" "));
      if ((((((int64_t)a->len) >= 2) && (((int64_t)b->len) >= 2)) && xn_str_eq(xn_arr_s_get(a, 1), xn_arr_s_get(b, 1)))) {
        return 1;
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_Cls_Mono_flattenClass(xn_Cls_Mono *self, xn_Cls_AstNode * cls) {
  rt_string * baseName = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Base"))) {
      baseName = k->text;
    }
    i = xn_int_wrap((i + 1));
  }
  if (xn_str_eq(baseName, rt_string_from_c(""))) {
    return;
  }
  xn_Cls_AstNode * base = xn_Cls_Mono_findClass(self, baseName);
  if (xn_str_eq(base->kind, rt_string_from_c("None"))) {
    return;
  }
  xn_Cls_Mono_flattenClass(self, base);
  i = 0;
  while ((i < ((int64_t)base->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(base->kids, i));
    if (((xn_str_eq(k->kind, rt_string_from_c("Field")) || xn_str_eq(k->kind, rt_string_from_c("Method"))) && (!xn_Cls_Mono_hasMember(self, cls, k)))) {
      xn_Cls_AstNode_add(cls, xn_Cls_Mono_cloneAst(self, k));
    }
    i = xn_int_wrap((i + 1));
  }
}

static xn_Cls_AstNode * xn_Cls_Mono_run(xn_Cls_Mono *self) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && (!xn_Cls_Mono_hasTypeParams(self, n)))) {
      xn_Cls_Mono_flattenClass(self, n);
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Func")) && (!xn_Cls_Mono_hasTypeParams(self, n)))) {
      xn_Cls_AstNode_setKid(self->program, i, xn_Cls_Mono_walk(self, n));
    }
    if (((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && (!xn_Cls_Mono_hasTypeParams(self, n)))) {
      xn_Cls_AstNode_setKid(self->program, i, xn_Cls_Mono_walk(self, n));
    }
    i = xn_int_wrap((i + 1));
  }
  return self->program;
}

struct xn_Cls_Checker {
  rt_header hdr;
  rt_string * file;
  xn_Cls_AstNode * program;
  xn_arr_s * fnNames;
  xn_arr_s * fnRets;
  xn_arr_s * fnParams;
  xn_arr_s * vars;
  xn_arr_s * varTypes;
  xn_arr_s * classNames;
  xn_arr_s * enumNames;
  xn_arr_s * protocolNames;
  xn_arr_s * fieldOwners;
  xn_arr_s * fieldNames;
  xn_arr_s * fieldTypes;
  xn_arr_s * methodOwners;
  xn_arr_s * methodNames;
  xn_arr_s * methodRets;
  xn_arr_s * methodParams;
  rt_string * error;
  rt_string * errorCode;
  int64_t errorLine;
  int64_t errorCol;
  rt_string * curRet;
  rt_string * curClass;
  rt_string * expectedLambda;
};

static const rt_type RT_TYPE_XN_Checker = { "Checker", sizeof(xn_Cls_Checker), NULL, NULL };

static xn_Cls_Checker *xn_Cls_Checker_new(rt_string * file, xn_Cls_AstNode * program) {
  xn_Cls_Checker *xn_obj = (xn_Cls_Checker *)rt_gc_new(&RT_TYPE_XN_Checker);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_Checker) - sizeof(rt_header));
  xn_obj->file = rt_string_from_c("");
  xn_obj->program = 0;
  xn_obj->fnNames = xn_arr_s_new(4);
  xn_obj->fnRets = xn_arr_s_new(4);
  xn_obj->fnParams = xn_arr_s_new(4);
  xn_obj->vars = xn_arr_s_new(4);
  xn_obj->varTypes = xn_arr_s_new(4);
  xn_obj->classNames = xn_arr_s_new(4);
  xn_obj->enumNames = xn_arr_s_new(4);
  xn_obj->protocolNames = xn_arr_s_new(4);
  xn_obj->fieldOwners = xn_arr_s_new(4);
  xn_obj->fieldNames = xn_arr_s_new(4);
  xn_obj->fieldTypes = xn_arr_s_new(4);
  xn_obj->methodOwners = xn_arr_s_new(4);
  xn_obj->methodNames = xn_arr_s_new(4);
  xn_obj->methodRets = xn_arr_s_new(4);
  xn_obj->methodParams = xn_arr_s_new(4);
  xn_obj->error = rt_string_from_c("");
  xn_obj->errorCode = rt_string_from_c("");
  xn_obj->errorLine = 0;
  xn_obj->errorCol = 0;
  xn_obj->curRet = rt_string_from_c("");
  xn_obj->curClass = rt_string_from_c("");
  xn_obj->expectedLambda = rt_string_from_c("");
  xn_Cls_Checker *self = xn_obj;
  self->file = file;
  self->program = program;
  self->fnNames = xn_arr_s_new(0);
  self->fnRets = xn_arr_s_new(0);
  self->fnParams = xn_arr_s_new(0);
  self->vars = xn_arr_s_new(0);
  self->varTypes = xn_arr_s_new(0);
  self->classNames = xn_arr_s_new(0);
  self->enumNames = xn_arr_s_new(0);
  self->protocolNames = xn_arr_s_new(0);
  self->fieldOwners = xn_arr_s_new(0);
  self->fieldNames = xn_arr_s_new(0);
  self->fieldTypes = xn_arr_s_new(0);
  self->methodOwners = xn_arr_s_new(0);
  self->methodNames = xn_arr_s_new(0);
  self->methodRets = xn_arr_s_new(0);
  self->methodParams = xn_arr_s_new(0);
  self->error = rt_string_from_c("");
  self->errorCode = rt_string_from_c("");
  self->errorLine = 1;
  self->errorCol = 1;
  self->curRet = rt_string_from_c("Unit");
  return xn_obj;
}

static int xn_Cls_Checker_hasError(xn_Cls_Checker *self);
static void xn_Cls_Checker_fail(xn_Cls_Checker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n);
static int xn_Cls_Checker_isFunctionType(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_fnRetType(xn_Cls_Checker *self, rt_string * ty);
static xn_arr_s * xn_Cls_Checker_fnParams(xn_Cls_Checker *self, rt_string * ty);
static int xn_Cls_Checker_knownType(xn_Cls_Checker *self, rt_string * ty);
static int xn_Cls_Checker_isListType(xn_Cls_Checker *self, rt_string * ty);
static int xn_Cls_Checker_isMapType(xn_Cls_Checker *self, rt_string * ty);
static int xn_Cls_Checker_isSetType(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_setElement(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_mapInner(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_mapKeyType(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_mapValueType(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_elementType(xn_Cls_Checker *self, rt_string * ty);
static int xn_Cls_Checker_isResultType(xn_Cls_Checker *self, rt_string * ty);
static int xn_Cls_Checker_isMutexType(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_mutexElement(xn_Cls_Checker *self, rt_string * ty);
static int xn_Cls_Checker_isTaskType(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_taskElement(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_resultValueType(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_resultErrorType(xn_Cls_Checker *self, rt_string * ty);
static int xn_Cls_Checker_sameType(xn_Cls_Checker *self, rt_string * a, rt_string * b);
static rt_string * xn_Cls_Checker_typeMangle(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_entryClassName(xn_Cls_Checker *self, rt_string * keyTy, rt_string * valTy);
static int xn_Cls_Checker_classIsA(xn_Cls_Checker *self, rt_string * actual, rt_string * target);
static int xn_Cls_Checker_isAssignable(xn_Cls_Checker *self, rt_string * target, rt_string * actual);
static int64_t xn_Cls_Checker_findFn(xn_Cls_Checker *self, rt_string * name);
static int64_t xn_Cls_Checker_findVar(xn_Cls_Checker *self, rt_string * name);
static int64_t xn_Cls_Checker_findClass(xn_Cls_Checker *self, rt_string * name);
static int64_t xn_Cls_Checker_findField(xn_Cls_Checker *self, rt_string * cls, rt_string * name);
static int64_t xn_Cls_Checker_findMethod(xn_Cls_Checker *self, rt_string * cls, rt_string * name);
static rt_string * xn_Cls_Checker_retOf(xn_Cls_Checker *self, xn_Cls_AstNode * fn);
static rt_string * xn_Cls_Checker_paramTypes(xn_Cls_Checker *self, xn_Cls_AstNode * fn);
static void xn_Cls_Checker_collect(xn_Cls_Checker *self);
static void xn_Cls_Checker_addVar(xn_Cls_Checker *self, rt_string * ty, rt_string * name, xn_Cls_AstNode * where);
static void xn_Cls_Checker_popTo(xn_Cls_Checker *self, int64_t mark);
static int xn_Cls_Checker_isEmptyArray(xn_Cls_Checker *self, xn_Cls_AstNode * n);
static int xn_Cls_Checker_isEmptyMap(xn_Cls_Checker *self, xn_Cls_AstNode * n);
static int xn_Cls_Checker_intFits32(xn_Cls_Checker *self, rt_string * text);
static void xn_Cls_Checker_check(xn_Cls_Checker *self);
static void xn_Cls_Checker_checkClass(xn_Cls_Checker *self, xn_Cls_AstNode * cls);
static void xn_Cls_Checker_checkFunc(xn_Cls_Checker *self, xn_Cls_AstNode * fn);
static void xn_Cls_Checker_checkBlock(xn_Cls_Checker *self, xn_Cls_AstNode * block);
static void xn_Cls_Checker_checkStmt(xn_Cls_Checker *self, xn_Cls_AstNode * st);
static int xn_Cls_Checker_isClass(xn_Cls_Checker *self, rt_string * name);
static int xn_Cls_Checker_isDataEnum(xn_Cls_Checker *self, rt_string * name);
static rt_string * xn_Cls_Checker_protocolRet(xn_Cls_Checker *self, rt_string * pname, rt_string * mname);
static rt_string * xn_Cls_Checker_protocolParams(xn_Cls_Checker *self, rt_string * pname, rt_string * mname);
static int xn_Cls_Checker_isProtocolName(xn_Cls_Checker *self, rt_string * name);
static xn_arr_s * xn_Cls_Checker_enumItems(xn_Cls_Checker *self, rt_string * name);
static rt_string * xn_Cls_Checker_enumCaseItem(xn_Cls_Checker *self, xn_Cls_AstNode * n, rt_string * enumName);
static xn_Cls_AstNode * xn_Cls_Checker_classNode(xn_Cls_Checker *self, rt_string * name);
static rt_string * xn_Cls_Checker_curFieldType(xn_Cls_Checker *self, rt_string * fname);
static rt_string * xn_Cls_Checker_pathType(xn_Cls_Checker *self, rt_string * path);
static rt_string * xn_Cls_Checker_fieldType(xn_Cls_Checker *self, rt_string * cls, rt_string * fname);
static int xn_Cls_Checker_isStaticMethod(xn_Cls_Checker *self, rt_string * cls, rt_string * mname);
static int xn_Cls_Checker_methodStatic(xn_Cls_Checker *self, xn_Cls_AstNode * m);
static rt_string * xn_Cls_Checker_methodRet(xn_Cls_Checker *self, rt_string * cls, rt_string * mname);
static int xn_Cls_Checker_isGenericResult(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_resultInitField(xn_Cls_Checker *self, rt_string * ty, rt_string * val);
static rt_string * xn_Cls_Checker_resultValueExpr(xn_Cls_Checker *self, rt_string * ty, rt_string * bv);
static int xn_Cls_Checker_isResult(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_resultValue(xn_Cls_Checker *self, rt_string * ty);
static rt_string * xn_Cls_Checker_typeOf(xn_Cls_Checker *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Checker_syntacticType(xn_Cls_Checker *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Checker_spawnReturnType(xn_Cls_Checker *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Checker_spawnLambdaType(xn_Cls_Checker *self, xn_Cls_AstNode * lam);
static rt_string * xn_Cls_Checker_checkMethodCall(xn_Cls_Checker *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Checker_argType(xn_Cls_Checker *self, xn_Cls_AstNode * arg, rt_string * want);
static rt_string * xn_Cls_Checker_checkCall(xn_Cls_Checker *self, xn_Cls_AstNode * n);

static int xn_Cls_Checker_hasError(xn_Cls_Checker *self) {
  return (!xn_str_eq(self->error, rt_string_from_c("")));
}

static void xn_Cls_Checker_fail(xn_Cls_Checker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n) {
  if (xn_str_eq(self->error, rt_string_from_c(""))) {
    self->error = msg;
    self->errorCode = code;
    self->errorLine = n->line;
    self->errorCol = n->col;
  }
}

static int xn_Cls_Checker_isFunctionType(xn_Cls_Checker *self, rt_string * ty) {
  int64_t p = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("(")));
  return (((p > 0) && (((int64_t)ty->len) > xn_int_wrap((p + 1)))) && xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 1)), 1), rt_string_from_c(")")));
}

static rt_string * xn_Cls_Checker_fnRetType(xn_Cls_Checker *self, rt_string * ty) {
  int64_t p = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("(")));
  if ((p > 0)) {
    return xn_str_substr(ty, 0, p);
  }
  return rt_string_from_c("Any");
}

static xn_arr_s * xn_Cls_Checker_fnParams(xn_Cls_Checker *self, rt_string * ty) {
  xn_arr_s *res = xn_arr_s_new(0);
  int64_t p = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("(")));
  if (((p <= 0) || (!xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 1)), 1), rt_string_from_c(")"))))) {
    return res;
  }
  rt_string * inner = xn_str_substr(ty, xn_int_wrap((p + 1)), xn_int_wrap((xn_int_wrap((((int64_t)ty->len) - p)) - 2)));
  if (xn_str_eq(xn_str_trim(inner), rt_string_from_c(""))) {
    return res;
  }
  xn_arr_s * raw = xn_splitTop(inner);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)raw->len))) {
    xn_arr_s_push(res, xn_str_trim(xn_arr_s_get(raw, i)));
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static int xn_Cls_Checker_knownType(xn_Cls_Checker *self, rt_string * ty) {
  if (((((int64_t)ty->len) > 1) && xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 1)), 1), rt_string_from_c("?")))) {
    return xn_Cls_Checker_knownType(self, xn_str_substr(ty, 0, xn_int_wrap((((int64_t)ty->len) - 1))));
  }
  if (xn_str_eq(ty, rt_string_from_c("Bytes"))) {
    return 1;
  }
  if ((xn_str_eq(ty, rt_string_from_c("AtomicInt")) || xn_str_eq(ty, rt_string_from_c("AtomicBool")))) {
    return 1;
  }
  if ((xn_str_eq(ty, rt_string_from_c("AtomicRef")) || (xn_str_indexof(ty, rt_string_from_c("AtomicRef<")) == 0))) {
    return 1;
  }
  if ((xn_str_eq(ty, rt_string_from_c("Channel")) || (xn_str_indexof(ty, rt_string_from_c("Channel<")) == 0))) {
    return 1;
  }
  if ((xn_str_eq(ty, rt_string_from_c("Mutex")) || (xn_str_indexof(ty, rt_string_from_c("Mutex<")) == 0))) {
    return 1;
  }
  if ((xn_str_eq(ty, rt_string_from_c("Task")) || (xn_str_indexof(ty, rt_string_from_c("Task<")) == 0))) {
    return 1;
  }
  if ((xn_str_eq(ty, rt_string_from_c("TaskGroup")) || xn_str_eq(ty, rt_string_from_c("Context")))) {
    return 1;
  }
  if ((xn_str_eq(ty, rt_string_from_c("TaskError")) || xn_str_eq(ty, rt_string_from_c("CancelledError")))) {
    return 1;
  }
  if (xn_Cls_Checker_isFunctionType(self, ty)) {
    return 1;
  }
  if ((((((((((((xn_str_eq(ty, rt_string_from_c("Int")) || xn_str_eq(ty, rt_string_from_c("String"))) || xn_str_eq(ty, rt_string_from_c("Bool"))) || xn_str_eq(ty, rt_string_from_c("Unit"))) || xn_str_eq(ty, rt_string_from_c("Char"))) || xn_str_eq(ty, rt_string_from_c("Double"))) || xn_str_eq(ty, rt_string_from_c("Long"))) || xn_str_eq(ty, rt_string_from_c("Int64"))) || xn_str_eq(ty, rt_string_from_c("Int32"))) || xn_str_eq(ty, rt_string_from_c("UInt16"))) || xn_str_eq(ty, rt_string_from_c("Int128"))) || xn_str_eq(ty, rt_string_from_c("void")))) {
    return 1;
  }
  if (xn_Cls_Checker_isListType(self, ty)) {
    return xn_Cls_Checker_knownType(self, xn_Cls_Checker_elementType(self, ty));
  }
  if (xn_Cls_Checker_isMapType(self, ty)) {
    return (xn_Cls_Checker_knownType(self, xn_Cls_Checker_mapKeyType(self, ty)) && xn_Cls_Checker_knownType(self, xn_Cls_Checker_mapValueType(self, ty)));
  }
  if (xn_Cls_Checker_isResultType(self, ty)) {
    return (xn_Cls_Checker_knownType(self, xn_Cls_Checker_resultValueType(self, ty)) && xn_Cls_Checker_knownType(self, xn_Cls_Checker_resultErrorType(self, ty)));
  }
  if (xn_Cls_Checker_isSetType(self, ty)) {
    return xn_Cls_Checker_knownType(self, xn_Cls_Checker_setElement(self, ty));
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->classNames->len))) {
    if (xn_str_eq(xn_arr_s_get(self->classNames, i), ty)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)self->enumNames->len))) {
    if (xn_str_eq(xn_arr_s_get(self->enumNames, i), ty)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)self->protocolNames->len))) {
    if (xn_str_eq(xn_arr_s_get(self->protocolNames, i), ty)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int xn_Cls_Checker_isListType(xn_Cls_Checker *self, rt_string * ty) {
  return (((((int64_t)ty->len) >= 2) && xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 2)), 2), rt_string_from_c("[]"))) || ((((int64_t)ty->len) > 6) && xn_str_eq(xn_str_substr(ty, 0, 5), rt_string_from_c("List<"))));
}

static int xn_Cls_Checker_isMapType(xn_Cls_Checker *self, rt_string * ty) {
  return ((((int64_t)ty->len) > 5) && xn_str_eq(xn_str_substr(ty, 0, 4), rt_string_from_c("Map<")));
}

static int xn_Cls_Checker_isSetType(xn_Cls_Checker *self, rt_string * ty) {
  return ((((int64_t)ty->len) > 5) && xn_str_eq(xn_str_substr(ty, 0, 4), rt_string_from_c("Set<")));
}

static rt_string * xn_Cls_Checker_setElement(xn_Cls_Checker *self, rt_string * ty) {
  if (xn_Cls_Checker_isSetType(self, ty)) {
    return xn_str_substr(ty, 4, xn_int_wrap((((int64_t)ty->len) - 5)));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_Checker_mapInner(xn_Cls_Checker *self, rt_string * ty) {
  if (xn_Cls_Checker_isMapType(self, ty)) {
    return xn_str_substr(ty, 4, xn_int_wrap((((int64_t)ty->len) - 5)));
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_Checker_mapKeyType(xn_Cls_Checker *self, rt_string * ty) {
  rt_string * inner = xn_Cls_Checker_mapInner(self, ty);
  xn_arr_s * parts = xn_splitTop(inner);
  if ((((int64_t)parts->len) >= 1)) {
    return xn_arr_s_get(parts, 0);
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_Checker_mapValueType(xn_Cls_Checker *self, rt_string * ty) {
  rt_string * inner = xn_Cls_Checker_mapInner(self, ty);
  xn_arr_s * parts = xn_splitTop(inner);
  if ((((int64_t)parts->len) >= 2)) {
    return xn_str_trim(xn_arr_s_get(parts, 1));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_Checker_elementType(xn_Cls_Checker *self, rt_string * ty) {
  if (((((int64_t)ty->len) >= 2) && xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 2)), 2), rt_string_from_c("[]")))) {
    return xn_str_substr(ty, 0, xn_int_wrap((((int64_t)ty->len) - 2)));
  }
  if (((((int64_t)ty->len) > 6) && xn_str_eq(xn_str_substr(ty, 0, 5), rt_string_from_c("List<")))) {
    return xn_str_substr(ty, 5, xn_int_wrap((((int64_t)ty->len) - 6)));
  }
  return rt_string_from_c("Any");
}

static int xn_Cls_Checker_isResultType(xn_Cls_Checker *self, rt_string * ty) {
  return ((((int64_t)ty->len) > 8) && xn_str_eq(xn_str_substr(ty, 0, 7), rt_string_from_c("Result<")));
}

static int xn_Cls_Checker_isMutexType(xn_Cls_Checker *self, rt_string * ty) {
  return (xn_str_eq(ty, rt_string_from_c("Mutex")) || (xn_str_indexof(ty, rt_string_from_c("Mutex<")) == 0));
}

static rt_string * xn_Cls_Checker_mutexElement(xn_Cls_Checker *self, rt_string * ty) {
  if (((((int64_t)ty->len) > 7) && (xn_str_indexof(ty, rt_string_from_c("Mutex<")) == 0))) {
    return xn_str_substr(ty, 6, xn_int_wrap((((int64_t)ty->len) - 7)));
  }
  return rt_string_from_c("Int");
}

static int xn_Cls_Checker_isTaskType(xn_Cls_Checker *self, rt_string * ty) {
  return (xn_str_eq(ty, rt_string_from_c("Task")) || (xn_str_indexof(ty, rt_string_from_c("Task<")) == 0));
}

static rt_string * xn_Cls_Checker_taskElement(xn_Cls_Checker *self, rt_string * ty) {
  if (((((int64_t)ty->len) > 6) && (xn_str_indexof(ty, rt_string_from_c("Task<")) == 0))) {
    return xn_str_substr(ty, 5, xn_int_wrap((((int64_t)ty->len) - 6)));
  }
  return rt_string_from_c("Int");
}

static rt_string * xn_Cls_Checker_resultValueType(xn_Cls_Checker *self, rt_string * ty) {
  rt_string * inner = rt_string_from_c("");
  if (xn_Cls_Checker_isResultType(self, ty)) {
    inner = xn_str_substr(ty, 7, xn_int_wrap((((int64_t)ty->len) - 8)));
  }
  xn_arr_s * parts = xn_splitTop(inner);
  if ((((int64_t)parts->len) >= 1)) {
    return xn_str_trim(xn_arr_s_get(parts, 0));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_Checker_resultErrorType(xn_Cls_Checker *self, rt_string * ty) {
  rt_string * inner = rt_string_from_c("");
  if (xn_Cls_Checker_isResultType(self, ty)) {
    inner = xn_str_substr(ty, 7, xn_int_wrap((((int64_t)ty->len) - 8)));
  }
  xn_arr_s * parts = xn_splitTop(inner);
  if ((((int64_t)parts->len) >= 2)) {
    return xn_str_trim(xn_arr_s_get(parts, 1));
  }
  return rt_string_from_c("Any");
}

static int xn_Cls_Checker_sameType(xn_Cls_Checker *self, rt_string * a, rt_string * b) {
  if (xn_str_eq(a, b)) {
    return 1;
  }
  if ((xn_str_eq(b, rt_string_from_c("Null")) && (xn_str_eq(a, rt_string_from_c("Any")) || ((((int64_t)a->len) > 1) && xn_str_eq(xn_str_substr(a, xn_int_wrap((((int64_t)a->len) - 1)), 1), rt_string_from_c("?")))))) {
    return 1;
  }
  if ((xn_str_eq(a, rt_string_from_c("Null")) && (xn_str_eq(b, rt_string_from_c("Any")) || ((((int64_t)b->len) > 1) && xn_str_eq(xn_str_substr(b, xn_int_wrap((((int64_t)b->len) - 1)), 1), rt_string_from_c("?")))))) {
    return 1;
  }
  if ((xn_Cls_Checker_isListType(self, a) && xn_Cls_Checker_isListType(self, b))) {
    return xn_str_eq(xn_Cls_Checker_elementType(self, a), xn_Cls_Checker_elementType(self, b));
  }
  if (((((xn_str_eq(a, rt_string_from_c("Int")) || xn_str_eq(a, rt_string_from_c("Int32"))) || xn_str_eq(a, rt_string_from_c("Int64"))) || xn_str_eq(a, rt_string_from_c("Long"))) && (((xn_str_eq(b, rt_string_from_c("Int")) || xn_str_eq(b, rt_string_from_c("Int32"))) || xn_str_eq(b, rt_string_from_c("Int64"))) || xn_str_eq(b, rt_string_from_c("Long"))))) {
    return 1;
  }
  return 0;
}

static rt_string * xn_Cls_Checker_typeMangle(xn_Cls_Checker *self, rt_string * ty) {
  rt_string * res = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ty->len))) {
    rt_string * c = xn_str_substr(ty, i, 1);
    rt_string * alpha = rt_string_from_c("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_");
    if ((xn_str_indexof(alpha, c) >= 0)) {
      res = xn_concat(res, c);
    }
    else {
      res = xn_concat(res, rt_string_from_c("_"));
    }
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static rt_string * xn_Cls_Checker_entryClassName(xn_Cls_Checker *self, rt_string * keyTy, rt_string * valTy) {
  return xn_concat(xn_concat(xn_concat(rt_string_from_c("Entry__"), xn_Cls_Checker_typeMangle(self, keyTy)), rt_string_from_c("_")), xn_Cls_Checker_typeMangle(self, valTy));
}

static int xn_Cls_Checker_classIsA(xn_Cls_Checker *self, rt_string * actual, rt_string * target) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * c = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (((xn_str_eq(c->kind, rt_string_from_c("Class")) || xn_str_eq(c->kind, rt_string_from_c("Struct"))) && xn_str_eq(c->text, actual))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)c->kids->len))) {
        xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, j));
        if (xn_str_eq(k->kind, rt_string_from_c("Base"))) {
          if (xn_str_eq(k->text, target)) {
            return 1;
          }
          return xn_Cls_Checker_classIsA(self, k->text, target);
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int xn_Cls_Checker_isAssignable(xn_Cls_Checker *self, rt_string * target, rt_string * actual) {
  if (xn_Cls_Checker_sameType(self, target, actual)) {
    return 1;
  }
  if ((((xn_str_eq(target, rt_string_from_c("Any")) || xn_str_eq(actual, rt_string_from_c("Any"))) || xn_str_eq(target, rt_string_from_c("Error"))) || xn_str_eq(actual, rt_string_from_c("Error")))) {
    return 1;
  }
  if ((xn_str_eq(target, rt_string_from_c("Int128")) && (((xn_str_eq(actual, rt_string_from_c("Int")) || xn_str_eq(actual, rt_string_from_c("Int32"))) || xn_str_eq(actual, rt_string_from_c("Int64"))) || xn_str_eq(actual, rt_string_from_c("Long"))))) {
    return 1;
  }
  if (xn_str_eq(actual, rt_string_from_c("Null"))) {
    if ((((((((((((xn_str_eq(target, rt_string_from_c("Context")) || xn_str_eq(target, rt_string_from_c("Bytes"))) || xn_str_eq(target, rt_string_from_c("String"))) || xn_str_eq(target, rt_string_from_c("TaskGroup"))) || xn_Cls_Checker_isMutexType(self, target)) || xn_Cls_Checker_isTaskType(self, target)) || (xn_str_indexof(target, rt_string_from_c("Channel<")) == 0)) || (xn_Cls_Checker_findClass(self, target) >= 0)) || xn_Cls_Checker_isProtocolName(self, target)) || xn_Cls_Checker_isListType(self, target)) || xn_Cls_Checker_isMapType(self, target)) || xn_Cls_Checker_isSetType(self, target))) {
      return 1;
    }
  }
  if (((((int64_t)target->len) > 1) && xn_str_eq(xn_str_substr(target, xn_int_wrap((((int64_t)target->len) - 1)), 1), rt_string_from_c("?")))) {
    rt_string * base = xn_str_substr(target, 0, xn_int_wrap((((int64_t)target->len) - 1)));
    if ((xn_str_eq(actual, rt_string_from_c("Null")) || xn_Cls_Checker_isAssignable(self, base, actual))) {
      return 1;
    }
  }
  int64_t ci = xn_int_wrap(xn_Cls_Checker_findClass(self, actual));
  if ((ci >= 0)) {
    if (xn_Cls_Checker_classIsA(self, actual, target)) {
      return 1;
    }
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)self->program->kids->len))) {
      xn_Cls_AstNode * c = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
      if (((xn_str_eq(c->kind, rt_string_from_c("Class")) || xn_str_eq(c->kind, rt_string_from_c("Struct"))) && xn_str_eq(c->text, actual))) {
        int64_t j = xn_int_wrap(0);
        while ((j < ((int64_t)c->kids->len))) {
          xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, j));
          if ((xn_str_eq(k->kind, rt_string_from_c("Implements")) && xn_str_eq(k->text, target))) {
            return 1;
          }
          j = xn_int_wrap((j + 1));
        }
      }
      i = xn_int_wrap((i + 1));
    }
  }
  return 0;
}

static int64_t xn_Cls_Checker_findFn(xn_Cls_Checker *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->fnNames->len))) {
    if (xn_str_eq(xn_arr_s_get(self->fnNames, i), name)) {
      return xn_int_wrap(i);
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_int_wrap(xn_int_wrap(-(1)));
}

static int64_t xn_Cls_Checker_findVar(xn_Cls_Checker *self, rt_string * name) {
  int64_t i = xn_int_wrap(xn_int_wrap((((int64_t)self->vars->len) - 1)));
  while ((i >= 0)) {
    if (xn_str_eq(xn_arr_s_get(self->vars, i), name)) {
      return xn_int_wrap(i);
    }
    i = xn_int_wrap((i - 1));
  }
  return xn_int_wrap(xn_int_wrap(-(1)));
}

static int64_t xn_Cls_Checker_findClass(xn_Cls_Checker *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->classNames->len))) {
    if (xn_str_eq(xn_arr_s_get(self->classNames, i), name)) {
      return xn_int_wrap(i);
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_int_wrap(xn_int_wrap(-(1)));
}

static int64_t xn_Cls_Checker_findField(xn_Cls_Checker *self, rt_string * cls, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->fieldNames->len))) {
    if ((xn_str_eq(xn_arr_s_get(self->fieldOwners, i), cls) && xn_str_eq(xn_arr_s_get(self->fieldNames, i), name))) {
      return xn_int_wrap(i);
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_int_wrap(xn_int_wrap(-(1)));
}

static int64_t xn_Cls_Checker_findMethod(xn_Cls_Checker *self, rt_string * cls, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->methodNames->len))) {
    if ((xn_str_eq(xn_arr_s_get(self->methodOwners, i), cls) && xn_str_eq(xn_arr_s_get(self->methodNames, i), name))) {
      return xn_int_wrap(i);
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_int_wrap(xn_int_wrap(-(1)));
}

static rt_string * xn_Cls_Checker_retOf(xn_Cls_Checker *self, xn_Cls_AstNode * fn) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fn->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Ret"))) {
      return k->text;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Unit");
}

static rt_string * xn_Cls_Checker_paramTypes(xn_Cls_Checker *self, xn_Cls_AstNode * fn) {
  rt_string * b = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fn->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Param"))) {
      xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) > 0)) {
        if ((!xn_str_eq(b, rt_string_from_c("")))) {
          b = xn_concat(b, rt_string_from_c(","));
        }
        b = xn_concat(b, xn_arr_s_get(parts, 0));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return b;
}

static void xn_Cls_Checker_collect(xn_Cls_Checker *self) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("Func"))) {
      if (xn_hasTypeParams(n)) {
        i = xn_int_wrap((i + 1));
        continue;
      }
      int64_t old = xn_int_wrap(xn_Cls_Checker_findFn(self, n->text));
      if ((old >= 0)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-002"), xn_concat(rt_string_from_c("duplicate function: "), n->text), n);
      }
      else {
        rt_string * rt = xn_Cls_Checker_retOf(self, n);
        xn_arr_s_push(self->fnNames, n->text);
        xn_arr_s_push(self->fnRets, rt);
        xn_arr_s_push(self->fnParams, xn_Cls_Checker_paramTypes(self, n));
      }
    }
    if (xn_str_eq(n->kind, rt_string_from_c("TopField"))) {
      xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        xn_arr_s_push(self->vars, xn_arr_s_get(parts, 1));
        xn_arr_s_push(self->varTypes, xn_arr_s_get(parts, 0));
      }
    }
    if (xn_str_eq(n->kind, rt_string_from_c("Enum"))) {
      xn_arr_s_push(self->enumNames, n->text);
      if (xn_Cls_Checker_isDataEnum(self, n->text)) {
        if ((xn_Cls_Checker_findClass(self, n->text) < 0)) {
          xn_arr_s_push(self->classNames, n->text);
        }
        int64_t dj = xn_int_wrap(0);
        while ((dj < ((int64_t)n->kids->len))) {
          xn_Cls_AstNode * dk = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, dj));
          if (xn_str_eq(dk->kind, rt_string_from_c("Field"))) {
            xn_arr_s * dparts = xn_str_split(dk->text, rt_string_from_c(" "));
            if ((((int64_t)dparts->len) >= 2)) {
              xn_arr_s_push(self->fieldOwners, n->text);
              xn_arr_s_push(self->fieldNames, xn_arr_s_get(dparts, 1));
              xn_arr_s_push(self->fieldTypes, xn_arr_s_get(dparts, 0));
            }
          }
          if (xn_str_eq(dk->kind, rt_string_from_c("Method"))) {
            xn_arr_s_push(self->methodOwners, n->text);
            xn_arr_s_push(self->methodNames, dk->text);
            xn_arr_s_push(self->methodRets, xn_Cls_Checker_retOf(self, dk));
            xn_arr_s_push(self->methodParams, xn_Cls_Checker_paramTypes(self, dk));
          }
          dj = xn_int_wrap((dj + 1));
        }
      }
    }
    if (xn_str_eq(n->kind, rt_string_from_c("Protocol"))) {
      xn_arr_s_push(self->protocolNames, n->text);
    }
    if (((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && (!xn_hasTypeParams(n)))) {
      if ((xn_Cls_Checker_findClass(self, n->text) >= 0)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-002"), xn_concat(rt_string_from_c("duplicate class: "), n->text), n);
      }
      else {
        xn_arr_s_push(self->classNames, n->text);
        int64_t j = xn_int_wrap(0);
        while ((j < ((int64_t)n->kids->len))) {
          xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j));
          if (xn_str_eq(k->kind, rt_string_from_c("Field"))) {
            xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
            if ((((int64_t)parts->len) >= 2)) {
              xn_arr_s_push(self->fieldOwners, n->text);
              xn_arr_s_push(self->fieldNames, xn_arr_s_get(parts, 1));
              xn_arr_s_push(self->fieldTypes, xn_arr_s_get(parts, 0));
            }
          }
          if (xn_str_eq(k->kind, rt_string_from_c("Method"))) {
            int64_t dup = xn_int_wrap(xn_Cls_Checker_findMethod(self, n->text, k->text));
            if ((dup >= 0)) {
              xn_Cls_Checker_fail(self, rt_string_from_c("SEM-002"), xn_concat(rt_string_from_c("duplicate method: "), k->text), k);
            }
            else {
              xn_arr_s_push(self->methodOwners, n->text);
              xn_arr_s_push(self->methodNames, k->text);
              xn_arr_s_push(self->methodRets, xn_Cls_Checker_retOf(self, k));
              xn_arr_s_push(self->methodParams, xn_Cls_Checker_paramTypes(self, k));
            }
          }
          j = xn_int_wrap((j + 1));
        }
      }
    }
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_Checker_addVar(xn_Cls_Checker *self, rt_string * ty, rt_string * name, xn_Cls_AstNode * where) {
  if ((xn_Cls_Checker_findVar(self, name) >= 0)) {
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-002"), xn_concat(rt_string_from_c("duplicate variable: "), name), where);
    return;
  }
  xn_arr_s_push(self->vars, name);
  xn_arr_s_push(self->varTypes, ty);
}

static void xn_Cls_Checker_popTo(xn_Cls_Checker *self, int64_t mark) {
  while ((((int64_t)self->vars->len) > mark)) {
    xn_arr_s_remove(self->vars, xn_int_wrap((((int64_t)self->vars->len) - 1)));
    xn_arr_s_remove(self->varTypes, xn_int_wrap((((int64_t)self->varTypes->len) - 1)));
  }
}

static int xn_Cls_Checker_isEmptyArray(xn_Cls_Checker *self, xn_Cls_AstNode * n) {
  return (xn_str_eq(n->kind, rt_string_from_c("ArrayLit")) && (((int64_t)n->kids->len) == 0));
}

static int xn_Cls_Checker_isEmptyMap(xn_Cls_Checker *self, xn_Cls_AstNode * n) {
  return (xn_str_eq(n->kind, rt_string_from_c("MapLit")) && (((int64_t)n->kids->len) == 0));
}

static int xn_Cls_Checker_intFits32(xn_Cls_Checker *self, rt_string * text) {
  if ((((int64_t)text->len) < 10)) {
    return 1;
  }
  if ((((int64_t)text->len) > 10)) {
    return 0;
  }
  return xn_str_eq(xn_str_substr(text, 0, 1), rt_string_from_c("1"));
}

static void xn_Cls_Checker_check(xn_Cls_Checker *self) {
  xn_Cls_Checker_collect(self);
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)self->program->kids->len)) && (!xn_Cls_Checker_hasError(self)))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("Func"))) {
      xn_Cls_Checker_checkFunc(self, n);
    }
    if ((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && (!xn_hasTypeParams(n))) || (xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_Cls_Checker_isDataEnum(self, n->text)))) {
      xn_Cls_Checker_checkClass(self, n);
    }
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_Checker_checkClass(xn_Cls_Checker *self, xn_Cls_AstNode * cls) {
  self->curClass = cls->text;
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)cls->kids->len)) && (!xn_Cls_Checker_hasError(self)))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Field"))) {
      xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        if ((!xn_Cls_Checker_knownType(self, xn_arr_s_get(parts, 0)))) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), xn_concat(rt_string_from_c("unknown field type: "), xn_arr_s_get(parts, 0)), k);
        }
        if ((((int64_t)k->kids->len) > 0)) {
          rt_string * it = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, 0)));
          if ((((!xn_str_eq(it, rt_string_from_c("Error"))) && (!xn_str_eq(it, xn_arr_s_get(parts, 0)))) && (!(xn_Cls_Checker_isEmptyArray(self, ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, 0))) && xn_Cls_Checker_isListType(self, xn_arr_s_get(parts, 0)))))) {
            xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("field "), xn_arr_s_get(parts, 1)), rt_string_from_c(" expects ")), xn_arr_s_get(parts, 0)), rt_string_from_c(", got ")), it), k);
          }
        }
      }
    }
    if ((xn_str_eq(k->kind, rt_string_from_c("Method")) || xn_str_eq(k->kind, rt_string_from_c("Ctor")))) {
      xn_Cls_Checker_checkFunc(self, k);
    }
    i = xn_int_wrap((i + 1));
  }
  self->curClass = rt_string_from_c("");
}

static void xn_Cls_Checker_checkFunc(xn_Cls_Checker *self, xn_Cls_AstNode * fn) {
  if (xn_str_eq(fn->kind, rt_string_from_c("Ctor"))) {
    self->curRet = rt_string_from_c("Unit");
  }
  else {
    if (xn_str_eq(fn->kind, rt_string_from_c("Method"))) {
      self->curRet = xn_Cls_Checker_retOf(self, fn);
    }
    else {
      int64_t idx = xn_int_wrap(xn_Cls_Checker_findFn(self, fn->text));
      if ((idx < 0)) {
        return;
      }
      self->curRet = xn_arr_s_get(self->fnRets, idx);
    }
  }
  int64_t mark = xn_int_wrap(((int64_t)self->vars->len));
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)fn->kids->len)) && (!xn_Cls_Checker_hasError(self)))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Param"))) {
      xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) < 2)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), rt_string_from_c("malformed parameter"), k);
      }
      else {
        rt_string * ty = xn_arr_s_get(parts, 0);
        rt_string * name = xn_arr_s_get(parts, 1);
        if ((!xn_Cls_Checker_knownType(self, ty))) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), xn_concat(rt_string_from_c("unknown type: "), ty), k);
        }
        else {
          xn_Cls_Checker_addVar(self, ty, name, k);
        }
      }
    }
    else {
      if (xn_str_eq(k->kind, rt_string_from_c("Block"))) {
        xn_Cls_Checker_checkBlock(self, k);
      }
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_Checker_popTo(self, mark);
}

static void xn_Cls_Checker_checkBlock(xn_Cls_Checker *self, xn_Cls_AstNode * block) {
  int64_t mark = xn_int_wrap(((int64_t)self->vars->len));
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)block->kids->len)) && (!xn_Cls_Checker_hasError(self)))) {
    xn_Cls_Checker_checkStmt(self, ((xn_Cls_AstNode *)xn_arr_o_get(block->kids, i)));
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_Checker_popTo(self, mark);
}

static void xn_Cls_Checker_checkStmt(xn_Cls_Checker *self, xn_Cls_AstNode * st) {
  if (((xn_str_eq(st->kind, rt_string_from_c("Break")) || xn_str_eq(st->kind, rt_string_from_c("Continue"))) || xn_str_eq(st->kind, rt_string_from_c("Goto")))) {
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Label"))) {
    if ((((int64_t)st->kids->len) > 0)) {
      xn_Cls_Checker_checkStmt(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Throw"))) {
    if ((((int64_t)st->kids->len) > 0)) {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Assign"))) {
    if ((((int64_t)st->kids->len) < 2)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), rt_string_from_c("malformed assignment"), st);
      return;
    }
    rt_string * lt = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    rt_string * rt = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)));
    int emptyMap = (xn_Cls_Checker_isEmptyMap(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1))) && xn_Cls_Checker_isMapType(self, lt));
    if ((((((!xn_str_eq(lt, rt_string_from_c("Error"))) && (!xn_str_eq(rt, rt_string_from_c("Error")))) && (!xn_Cls_Checker_isAssignable(self, lt, rt))) && (!(xn_Cls_Checker_isEmptyArray(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1))) && (xn_Cls_Checker_isListType(self, lt) || xn_Cls_Checker_isSetType(self, lt))))) && (!emptyMap))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(rt_string_from_c("assignment "), lt), rt_string_from_c(" = ")), rt), st);
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Defer"))) {
    if ((((int64_t)st->kids->len) > 0)) {
      xn_Cls_Checker_checkStmt(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("ForIn"))) {
    if ((((int64_t)st->kids->len) < 2)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), rt_string_from_c("malformed for-in"), st);
      return;
    }
    rt_string * at = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    if (((!xn_str_eq(at, rt_string_from_c("Error"))) && xn_str_eq(xn_Cls_Checker_elementType(self, at), rt_string_from_c("Any")))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("for-in expects array, got "), at), st);
      return;
    }
    int64_t mark = xn_int_wrap(((int64_t)self->vars->len));
    xn_Cls_Checker_addVar(self, xn_Cls_Checker_elementType(self, at), st->text, st);
    xn_Cls_Checker_checkBlock(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)));
    xn_Cls_Checker_popTo(self, mark);
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Switch"))) {
    if ((((int64_t)st->kids->len) < 2)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), rt_string_from_c("malformed switch"), st);
      return;
    }
    rt_string * vt = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    if (xn_str_eq(vt, rt_string_from_c("Error"))) {
      return;
    }
    if ((xn_str_eq(vt, rt_string_from_c("Double")) || xn_Cls_Checker_isResultType(self, vt))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("unsupported switch value type: "), vt), st);
      return;
    }
    int64_t si = xn_int_wrap(1);
    int hasDefault = 0;
    xn_arr_s *covered = xn_arr_s_new(0);
    while (((si < ((int64_t)st->kids->len)) && (!xn_Cls_Checker_hasError(self)))) {
      xn_Cls_AstNode * clause = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, si));
      if (xn_str_eq(clause->kind, rt_string_from_c("Case"))) {
        if ((((int64_t)clause->kids->len) < 2)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), rt_string_from_c("malformed case"), clause);
          return;
        }
        rt_string * ct = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(clause->kids, 0)));
        if (((!xn_str_eq(ct, rt_string_from_c("Error"))) && (!xn_Cls_Checker_sameType(self, vt, ct)))) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(rt_string_from_c("case type "), ct), rt_string_from_c(" does not match switch ")), vt), clause);
          return;
        }
        rt_string * item = xn_Cls_Checker_enumCaseItem(self, ((xn_Cls_AstNode *)xn_arr_o_get(clause->kids, 0)), vt);
        if ((!xn_str_eq(item, rt_string_from_c("")))) {
          xn_arr_s_push(covered, item);
        }
        xn_Cls_Checker_checkBlock(self, ((xn_Cls_AstNode *)xn_arr_o_get(clause->kids, 1)));
      }
      else {
        if (xn_str_eq(clause->kind, rt_string_from_c("Default"))) {
          hasDefault = 1;
          if ((((int64_t)clause->kids->len) > 0)) {
            xn_Cls_Checker_checkBlock(self, ((xn_Cls_AstNode *)xn_arr_o_get(clause->kids, 0)));
          }
        }
      }
      si = xn_int_wrap((si + 1));
    }
    if (((!hasDefault) && (!xn_str_eq(vt, rt_string_from_c("Error"))))) {
      xn_arr_s * all = xn_Cls_Checker_enumItems(self, vt);
      if ((((int64_t)all->len) > 0)) {
        int64_t ei = xn_int_wrap(0);
        while ((ei < ((int64_t)all->len))) {
          int found = 0;
          int64_t ci = xn_int_wrap(0);
          while ((ci < ((int64_t)covered->len))) {
            if (xn_str_eq(xn_arr_s_get(covered, ci), xn_arr_s_get(all, ei))) {
              found = 1;
            }
            ci = xn_int_wrap((ci + 1));
          }
          if ((!found)) {
            xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("non-exhaustive enum switch: missing "), xn_arr_s_get(all, ei)), st);
            return;
          }
          ei = xn_int_wrap((ei + 1));
        }
      }
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("ForRange"))) {
    if ((((int64_t)st->kids->len) < 3)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), rt_string_from_c("malformed for-range"), st);
      return;
    }
    rt_string * a = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    rt_string * b = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)));
    if (((!xn_str_eq(a, rt_string_from_c("Error"))) && (!xn_str_eq(a, rt_string_from_c("Int"))))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("for-range lower bound must be Int, got "), a), st);
      return;
    }
    if (((!xn_str_eq(b, rt_string_from_c("Error"))) && (!xn_str_eq(b, rt_string_from_c("Int"))))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("for-range upper bound must be Int, got "), b), st);
      return;
    }
    int64_t mark = xn_int_wrap(((int64_t)self->vars->len));
    int64_t sp = xn_int_wrap(xn_str_indexof(st->text, rt_string_from_c(" ")));
    xn_Cls_Checker_addVar(self, rt_string_from_c("Int"), xn_str_substr(st->text, xn_int_wrap((sp + 1)), xn_int_wrap((xn_int_wrap((((int64_t)st->text->len) - sp)) - 1))), st);
    xn_Cls_Checker_checkBlock(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 2)));
    xn_Cls_Checker_popTo(self, mark);
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("DoWhile"))) {
    if ((((int64_t)st->kids->len) < 2)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), rt_string_from_c("malformed do-while"), st);
      return;
    }
    xn_Cls_Checker_checkBlock(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    rt_string * c = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)));
    if (((!xn_str_eq(c, rt_string_from_c("Error"))) && (!xn_str_eq(c, rt_string_from_c("Bool"))))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("do-while condition must be Bool, got "), c), st);
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Local"))) {
    xn_arr_s * parts = xn_str_split(st->text, rt_string_from_c(" "));
    if ((((int64_t)parts->len) < 2)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), rt_string_from_c("malformed local declaration"), st);
      return;
    }
    rt_string * ty = xn_arr_s_get(parts, 0);
    rt_string * name = xn_arr_s_get(parts, 1);
    if ((!xn_Cls_Checker_knownType(self, ty))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), xn_concat(rt_string_from_c("unknown type: "), ty), st);
      return;
    }
    xn_Cls_Checker_addVar(self, ty, name, st);
    if ((((int64_t)st->kids->len) > 0)) {
      rt_string * it = rt_string_from_c("");
      if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))->kind, rt_string_from_c("Lambda"))) {
        rt_string * oldExp = self->expectedLambda;
        self->expectedLambda = ty;
        it = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
        self->expectedLambda = oldExp;
      }
      else {
        it = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
      }
      rt_string * setElemType = xn_Cls_Checker_setElement(self, ty);
      int setLit = ((xn_Cls_Checker_isSetType(self, ty) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))->kind, rt_string_from_c("ArrayLit"))) && (xn_str_eq(xn_Cls_Checker_elementType(self, it), setElemType) || (xn_str_eq(setElemType, rt_string_from_c("Long")) && xn_str_eq(xn_Cls_Checker_elementType(self, it), rt_string_from_c("Int")))));
      int emptyMap = (xn_Cls_Checker_isEmptyMap(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))) && xn_Cls_Checker_isMapType(self, ty));
      if ((((((!xn_str_eq(it, rt_string_from_c("Error"))) && (!xn_Cls_Checker_isAssignable(self, ty, it))) && (!(xn_Cls_Checker_isEmptyArray(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))) && (xn_Cls_Checker_isListType(self, ty) || xn_Cls_Checker_isSetType(self, ty))))) && (!setLit)) && (!emptyMap))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(rt_string_from_c("cannot initialize "), ty), rt_string_from_c(" with ")), it), st);
      }
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Return"))) {
    if ((((int64_t)st->kids->len) == 0)) {
      if ((((!xn_str_eq(self->curRet, rt_string_from_c("Unit"))) && (!xn_str_eq(self->curRet, rt_string_from_c("Void")))) && (!xn_str_eq(self->curRet, rt_string_from_c("void"))))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), rt_string_from_c("return value required, got Unit"), st);
      }
    }
    else {
      rt_string * t = xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)), self->curRet);
      if (((!xn_str_eq(t, rt_string_from_c("Error"))) && (!xn_Cls_Checker_isAssignable(self, self->curRet, t)))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(rt_string_from_c("return type "), self->curRet), rt_string_from_c(", got ")), t), st);
      }
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("ExprStmt"))) {
    if ((((int64_t)st->kids->len) > 0)) {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("If"))) {
    if ((((int64_t)st->kids->len) >= 1)) {
      rt_string * c = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
      if (((!xn_str_eq(c, rt_string_from_c("Error"))) && (!xn_str_eq(c, rt_string_from_c("Bool"))))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("if condition must be Bool, got "), c), st);
      }
    }
    if ((((int64_t)st->kids->len) >= 2)) {
      xn_Cls_Checker_checkBlock(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)));
    }
    if ((((int64_t)st->kids->len) >= 3)) {
      xn_Cls_Checker_checkBlock(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 2)));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("While"))) {
    if ((((int64_t)st->kids->len) >= 1)) {
      rt_string * c = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
      if (((!xn_str_eq(c, rt_string_from_c("Error"))) && (!xn_str_eq(c, rt_string_from_c("Bool"))))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("while condition must be Bool, got "), c), st);
      }
    }
    if ((((int64_t)st->kids->len) >= 2)) {
      xn_Cls_Checker_checkBlock(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Block"))) {
    xn_Cls_Checker_checkBlock(self, st);
  }
}

static int xn_Cls_Checker_isClass(xn_Cls_Checker *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && xn_str_eq(n->text, name))) {
      return 1;
    }
    if ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j))->kind, rt_string_from_c("Data"))) {
          return 1;
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int xn_Cls_Checker_isDataEnum(xn_Cls_Checker *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j))->kind, rt_string_from_c("Data"))) {
          return 1;
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static rt_string * xn_Cls_Checker_protocolRet(xn_Cls_Checker *self, rt_string * pname, rt_string * mname) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(p->kind, rt_string_from_c("Protocol")) && xn_str_eq(p->text, pname))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)p->kids->len))) {
        xn_Cls_AstNode * sig = ((xn_Cls_AstNode *)xn_arr_o_get(p->kids, j));
        if ((xn_str_eq(sig->kind, rt_string_from_c("Sig")) && xn_str_eq(sig->text, mname))) {
          int64_t k = xn_int_wrap(0);
          while ((k < ((int64_t)sig->kids->len))) {
            if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(sig->kids, k))->kind, rt_string_from_c("Ret"))) {
              return ((xn_Cls_AstNode *)xn_arr_o_get(sig->kids, k))->text;
            }
            k = xn_int_wrap((k + 1));
          }
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_Checker_protocolParams(xn_Cls_Checker *self, rt_string * pname, rt_string * mname) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(p->kind, rt_string_from_c("Protocol")) && xn_str_eq(p->text, pname))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)p->kids->len))) {
        xn_Cls_AstNode * sig = ((xn_Cls_AstNode *)xn_arr_o_get(p->kids, j));
        if ((xn_str_eq(sig->kind, rt_string_from_c("Sig")) && xn_str_eq(sig->text, mname))) {
          rt_string * res = rt_string_from_c("");
          int64_t k = xn_int_wrap(0);
          while ((k < ((int64_t)sig->kids->len))) {
            xn_Cls_AstNode * q = ((xn_Cls_AstNode *)xn_arr_o_get(sig->kids, k));
            if (xn_str_eq(q->kind, rt_string_from_c("Param"))) {
              xn_arr_s * ps = xn_str_split(q->text, rt_string_from_c(" "));
              if ((((int64_t)ps->len) > 0)) {
                if ((!xn_str_eq(res, rt_string_from_c("")))) {
                  res = xn_concat(res, rt_string_from_c(","));
                }
                res = xn_concat(res, xn_arr_s_get(ps, 0));
              }
            }
            k = xn_int_wrap((k + 1));
          }
          return res;
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("");
}

static int xn_Cls_Checker_isProtocolName(xn_Cls_Checker *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->protocolNames->len))) {
    if (xn_str_eq(xn_arr_s_get(self->protocolNames, i), name)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static xn_arr_s * xn_Cls_Checker_enumItems(xn_Cls_Checker *self, rt_string * name) {
  xn_arr_s *res = xn_arr_s_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * it = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j));
        if (xn_str_eq(it->kind, rt_string_from_c("EnumItem"))) {
          xn_arr_s_push(res, it->text);
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static rt_string * xn_Cls_Checker_enumCaseItem(xn_Cls_Checker *self, xn_Cls_AstNode * n, rt_string * enumName) {
  if (((!xn_str_eq(n->kind, rt_string_from_c("Member"))) || (((int64_t)n->kids->len) == 0))) {
    return rt_string_from_c("");
  }
  if ((!xn_str_eq(xn_Cls_Checker_typeOf(self, n), enumName))) {
    return rt_string_from_c("");
  }
  return n->text;
}

static xn_Cls_AstNode * xn_Cls_Checker_classNode(xn_Cls_Checker *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && xn_str_eq(n->text, name)) || ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name)) && xn_Cls_Checker_isDataEnum(self, name)))) {
      return n;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("error"), name, 1, 1);
}

static rt_string * xn_Cls_Checker_curFieldType(xn_Cls_Checker *self, rt_string * fname) {
  if (xn_str_eq(self->curClass, rt_string_from_c(""))) {
    return rt_string_from_c("Any");
  }
  int64_t fi = xn_int_wrap(xn_Cls_Checker_findField(self, self->curClass, fname));
  if ((fi >= 0)) {
    return xn_arr_s_get(self->fieldTypes, fi);
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_Checker_pathType(xn_Cls_Checker *self, rt_string * path) {
  int64_t dot = xn_int_wrap(xn_str_indexof(path, rt_string_from_c(".")));
  if ((dot < 0)) {
    if (xn_str_eq(path, rt_string_from_c("self"))) {
      return self->curClass;
    }
    if (xn_str_eq(path, rt_string_from_c("Bytes"))) {
      return rt_string_from_c("Bytes");
    }
    if ((xn_Cls_Checker_findClass(self, path) >= 0)) {
      return path;
    }
    int64_t vi = xn_int_wrap(xn_Cls_Checker_findVar(self, path));
    if ((vi >= 0)) {
      return xn_arr_s_get(self->varTypes, vi);
    }
    rt_string * ft = xn_Cls_Checker_curFieldType(self, path);
    if ((!xn_str_eq(ft, rt_string_from_c("Any")))) {
      return ft;
    }
    return rt_string_from_c("Any");
  }
  rt_string * head = xn_str_substr(path, 0, dot);
  rt_string * rest = xn_str_substr(path, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)path->len) - dot)) - 1)));
  rt_string * bt = xn_Cls_Checker_pathType(self, head);
  while (((!xn_str_eq(bt, rt_string_from_c("Any"))) && (((int64_t)rest->len) > 0))) {
    int64_t d = xn_int_wrap(xn_str_indexof(rest, rt_string_from_c(".")));
    rt_string * seg = rest;
    if ((d >= 0)) {
      seg = xn_str_substr(rest, 0, d);
      rest = xn_str_substr(rest, xn_int_wrap((d + 1)), xn_int_wrap((xn_int_wrap((((int64_t)rest->len) - d)) - 1)));
    }
    else {
      rest = rt_string_from_c("");
    }
    bt = xn_Cls_Checker_fieldType(self, bt, seg);
  }
  return bt;
}

static rt_string * xn_Cls_Checker_fieldType(xn_Cls_Checker *self, rt_string * cls, rt_string * fname) {
  xn_Cls_AstNode * c = xn_Cls_Checker_classNode(self, cls);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)c->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Field"))) {
      xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
      if (((((int64_t)parts->len) >= 2) && xn_str_eq(xn_arr_s_get(parts, 1), fname))) {
        return xn_arr_s_get(parts, 0);
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Any");
}

static int xn_Cls_Checker_isStaticMethod(xn_Cls_Checker *self, rt_string * cls, rt_string * mname) {
  xn_Cls_AstNode * c = xn_Cls_Checker_classNode(self, cls);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)c->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, i));
    if ((xn_str_eq(k->kind, rt_string_from_c("Method")) && xn_str_eq(k->text, mname))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)k->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(k->kids, j))->kind, rt_string_from_c("Static"))) {
          return 1;
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int xn_Cls_Checker_methodStatic(xn_Cls_Checker *self, xn_Cls_AstNode * m) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)m->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(m->kids, i))->kind, rt_string_from_c("Static"))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static rt_string * xn_Cls_Checker_methodRet(xn_Cls_Checker *self, rt_string * cls, rt_string * mname) {
  xn_Cls_AstNode * c = xn_Cls_Checker_classNode(self, cls);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)c->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, i));
    if ((xn_str_eq(k->kind, rt_string_from_c("Method")) && xn_str_eq(k->text, mname))) {
      rt_string * r = xn_Cls_Checker_retOf(self, k);
      return r;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Any");
}

static int xn_Cls_Checker_isGenericResult(xn_Cls_Checker *self, rt_string * ty) {
  return (xn_Cls_Checker_isResult(self, ty) && (!xn_str_eq(ty, rt_string_from_c("Result<Int,String>"))));
}

static rt_string * xn_Cls_Checker_resultInitField(xn_Cls_Checker *self, rt_string * ty, rt_string * val) {
  rt_string * vt = xn_Cls_Checker_resultValue(self, ty);
  if ((((((xn_str_eq(vt, rt_string_from_c("Int")) || xn_str_eq(vt, rt_string_from_c("Int32"))) || xn_str_eq(vt, rt_string_from_c("Int64"))) || xn_str_eq(vt, rt_string_from_c("Long"))) || xn_str_eq(vt, rt_string_from_c("Bool"))) || xn_str_eq(vt, rt_string_from_c("Char")))) {
    return xn_concat(xn_concat(rt_string_from_c(".i = (int64_t)("), val), rt_string_from_c(")"));
  }
  if (xn_str_eq(vt, rt_string_from_c("Double"))) {
    return xn_concat(xn_concat(rt_string_from_c(".d = (double)("), val), rt_string_from_c(")"));
  }
  if (xn_str_eq(vt, rt_string_from_c("Int128"))) {
    return xn_concat(xn_concat(rt_string_from_c(".q = (__int128)("), val), rt_string_from_c(")"));
  }
  if (xn_str_eq(vt, rt_string_from_c("String"))) {
    return xn_concat(xn_concat(rt_string_from_c(".s = (rt_string *)("), val), rt_string_from_c(")"));
  }
  if (xn_str_startswith(vt, rt_string_from_c("Result<"))) {
    return xn_concat(xn_concat(rt_string_from_c(".p = xn_box_result("), val), rt_string_from_c(")"));
  }
  return xn_concat(xn_concat(rt_string_from_c(".p = (void *)("), val), rt_string_from_c(")"));
}

static rt_string * xn_Cls_Checker_resultValueExpr(xn_Cls_Checker *self, rt_string * ty, rt_string * bv) {
  rt_string * vt = xn_Cls_Checker_resultValue(self, ty);
  if ((((((xn_str_eq(vt, rt_string_from_c("Int")) || xn_str_eq(vt, rt_string_from_c("Int32"))) || xn_str_eq(vt, rt_string_from_c("Int64"))) || xn_str_eq(vt, rt_string_from_c("Long"))) || xn_str_eq(vt, rt_string_from_c("Bool"))) || xn_str_eq(vt, rt_string_from_c("Char")))) {
    return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c(").i"));
  }
  if (xn_str_eq(vt, rt_string_from_c("Double"))) {
    return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c(").d"));
  }
  if (xn_str_eq(vt, rt_string_from_c("Int128"))) {
    return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c(").q"));
  }
  if (xn_str_eq(vt, rt_string_from_c("String"))) {
    return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c(").s"));
  }
  if (xn_str_eq(vt, rt_string_from_c("Result<Int,String>"))) {
    return xn_concat(xn_concat(rt_string_from_c("(*(xn_Result_Int_String *)("), bv), rt_string_from_c(").p)"));
  }
  if (xn_str_startswith(vt, rt_string_from_c("Result<"))) {
    return xn_concat(xn_concat(rt_string_from_c("(*(xn_Result *)("), bv), rt_string_from_c(").p)"));
  }
  return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c(").p"));
}

static int xn_Cls_Checker_isResult(xn_Cls_Checker *self, rt_string * ty) {
  return ((((int64_t)ty->len) > 8) && xn_str_eq(xn_str_substr(ty, 0, 7), rt_string_from_c("Result<")));
}

static rt_string * xn_Cls_Checker_resultValue(xn_Cls_Checker *self, rt_string * ty) {
  rt_string * inner = xn_str_substr(ty, 7, xn_int_wrap((((int64_t)ty->len) - 8)));
  xn_arr_s * parts = xn_splitTop(inner);
  if ((((int64_t)parts->len) >= 1)) {
    return xn_str_trim(xn_arr_s_get(parts, 0));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_Checker_typeOf(xn_Cls_Checker *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Int"))) {
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Double"))) {
    return rt_string_from_c("Double");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    return rt_string_from_c("String");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Null"))) {
    return rt_string_from_c("Null");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Char"))) {
    return rt_string_from_c("Char");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Bool"))) {
    return rt_string_from_c("Bool");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Ternary"))) {
    if ((((int64_t)n->kids->len) < 3)) {
      return rt_string_from_c("Any");
    }
    return xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Cast"))) {
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Is"))) {
    return rt_string_from_c("Bool");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Unary"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("Any");
    }
    if (xn_str_eq(n->text, rt_string_from_c("!"))) {
      return rt_string_from_c("Bool");
    }
    return xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Try"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("Any");
    }
    rt_string * ct = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    return xn_Cls_Checker_resultValueType(self, ct);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("ArrayLit"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("Int[]");
    }
    return xn_concat(xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("[]"));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("MapLit"))) {
    if ((((int64_t)n->kids->len) >= 2)) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("Map<"), xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(",")), xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(">"));
    }
    return rt_string_from_c("Map<String,Int>");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Index"))) {
    if ((((int64_t)n->kids->len) < 2)) {
      return rt_string_from_c("Any");
    }
    rt_string * bt = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (xn_str_eq(bt, rt_string_from_c("Error"))) {
      return rt_string_from_c("Error");
    }
    if (xn_Cls_Checker_isMapType(self, bt)) {
      return xn_Cls_Checker_mapValueType(self, bt);
    }
    return xn_Cls_Checker_elementType(self, bt);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Lambda"))) {
    rt_string * ft = self->expectedLambda;
    if (xn_str_eq(ft, rt_string_from_c(""))) {
      return rt_string_from_c("Any");
    }
    int64_t mark = xn_int_wrap(((int64_t)self->vars->len));
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)n->kids->len))) {
      xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i));
      if (xn_str_eq(p->kind, rt_string_from_c("Param"))) {
        xn_arr_s * pp = xn_str_split(p->text, rt_string_from_c(" "));
        if ((((int64_t)pp->len) >= 2)) {
          xn_Cls_Checker_addVar(self, xn_arr_s_get(pp, 0), xn_arr_s_get(pp, 1), p);
        }
      }
      i = xn_int_wrap((i + 1));
    }
    rt_string * oldRet = self->curRet;
    self->curRet = xn_Cls_Checker_fnRetType(self, ft);
    i = 0;
    while ((i < ((int64_t)n->kids->len))) {
      if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i))->kind, rt_string_from_c("Block"))) {
        xn_Cls_Checker_checkBlock(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)));
      }
      i = xn_int_wrap((i + 1));
    }
    self->curRet = oldRet;
    xn_Cls_Checker_popTo(self, mark);
    return ft;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("New"))) {
    if ((!xn_Cls_Checker_knownType(self, n->text))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), xn_concat(rt_string_from_c("unknown class: "), n->text), n);
      return rt_string_from_c("Error");
    }
    if (xn_Cls_Checker_isDataEnum(self, n->text)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), xn_concat(rt_string_from_c("new is not allowed for data enum: "), n->text), n);
      return rt_string_from_c("Error");
    }
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Name"))) {
    if ((xn_str_eq(n->text, rt_string_from_c("self")) && (!xn_str_eq(self->curClass, rt_string_from_c(""))))) {
      return self->curClass;
    }
    int64_t eni = xn_int_wrap(0);
    while ((eni < ((int64_t)self->enumNames->len))) {
      if (xn_str_eq(xn_arr_s_get(self->enumNames, eni), n->text)) {
        return n->text;
      }
      eni = xn_int_wrap((eni + 1));
    }
    int64_t idx = xn_int_wrap(xn_Cls_Checker_findVar(self, n->text));
    if ((idx < 0)) {
      rt_string * ft = xn_Cls_Checker_curFieldType(self, n->text);
      if ((!xn_str_eq(ft, rt_string_from_c("Any")))) {
        return ft;
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined symbol: "), n->text), n);
      return rt_string_from_c("Error");
    }
    return xn_arr_s_get(self->varTypes, idx);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Binary"))) {
    rt_string * lt = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    rt_string * rt = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
    if ((xn_str_eq(lt, rt_string_from_c("Error")) || xn_str_eq(rt, rt_string_from_c("Error")))) {
      return rt_string_from_c("Error");
    }
    if ((((((((xn_str_eq(n->text, rt_string_from_c("==")) || xn_str_eq(n->text, rt_string_from_c("!="))) || xn_str_eq(n->text, rt_string_from_c("<"))) || xn_str_eq(n->text, rt_string_from_c("<="))) || xn_str_eq(n->text, rt_string_from_c(">"))) || xn_str_eq(n->text, rt_string_from_c(">="))) || xn_str_eq(n->text, rt_string_from_c("&&"))) || xn_str_eq(n->text, rt_string_from_c("||")))) {
      return rt_string_from_c("Bool");
    }
    if (((xn_str_eq(n->text, rt_string_from_c("+")) && xn_str_eq(lt, rt_string_from_c("String"))) && xn_str_eq(rt, rt_string_from_c("String")))) {
      return rt_string_from_c("String");
    }
    if (((xn_str_eq(lt, rt_string_from_c("Double")) || xn_str_eq(rt, rt_string_from_c("Double"))) && (!xn_str_eq(n->text, rt_string_from_c("%"))))) {
      if (((xn_str_eq(lt, rt_string_from_c("Double")) || xn_str_eq(lt, rt_string_from_c("Int"))) && (xn_str_eq(rt, rt_string_from_c("Double")) || xn_str_eq(rt, rt_string_from_c("Int"))))) {
        return rt_string_from_c("Double");
      }
    }
    if (((((xn_str_eq(n->text, rt_string_from_c("&")) || xn_str_eq(n->text, rt_string_from_c("|"))) || xn_str_eq(n->text, rt_string_from_c("^"))) || xn_str_eq(n->text, rt_string_from_c("<<"))) || xn_str_eq(n->text, rt_string_from_c(">>")))) {
      if (((!xn_str_eq(lt, rt_string_from_c("Int"))) || (!xn_str_eq(rt, rt_string_from_c("Int"))))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("operator "), n->text), rt_string_from_c(" needs Int, got ")), lt), rt_string_from_c("/")), rt), n);
        return rt_string_from_c("Error");
      }
      return rt_string_from_c("Int");
    }
    if ((xn_str_eq(lt, rt_string_from_c("Int128")) || xn_str_eq(rt, rt_string_from_c("Int128")))) {
      return rt_string_from_c("Int128");
    }
    if ((((xn_str_eq(lt, rt_string_from_c("Int64")) || xn_str_eq(lt, rt_string_from_c("Int32"))) || xn_str_eq(lt, rt_string_from_c("Long"))) && (((xn_str_eq(rt, rt_string_from_c("Int")) || xn_str_eq(rt, rt_string_from_c("Int32"))) || xn_str_eq(rt, rt_string_from_c("Int64"))) || xn_str_eq(rt, rt_string_from_c("Long"))))) {
      return lt;
    }
    if ((((xn_str_eq(rt, rt_string_from_c("Int64")) || xn_str_eq(rt, rt_string_from_c("Int32"))) || xn_str_eq(rt, rt_string_from_c("Long"))) && (((xn_str_eq(lt, rt_string_from_c("Int")) || xn_str_eq(lt, rt_string_from_c("Int32"))) || xn_str_eq(lt, rt_string_from_c("Int64"))) || xn_str_eq(lt, rt_string_from_c("Long"))))) {
      return rt;
    }
    if (((!xn_str_eq(lt, rt_string_from_c("Int"))) || (!xn_str_eq(rt, rt_string_from_c("Int"))))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("operator "), n->text), rt_string_from_c(" needs Int, got ")), lt), rt_string_from_c("/")), rt), n);
      return rt_string_from_c("Error");
    }
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("MethodCall"))) {
    return xn_Cls_Checker_checkMethodCall(self, n);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
    return xn_Cls_Checker_checkCall(self, n);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Member"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("Any");
    }
    rt_string * bt = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (xn_str_eq(bt, rt_string_from_c("Error"))) {
      return rt_string_from_c("Error");
    }
    int64_t fi = xn_int_wrap(xn_Cls_Checker_findField(self, bt, n->text));
    if ((fi >= 0)) {
      return xn_arr_s_get(self->fieldTypes, fi);
    }
    int64_t ei = xn_int_wrap(0);
    while ((ei < ((int64_t)self->enumNames->len))) {
      if (xn_str_eq(xn_arr_s_get(self->enumNames, ei), bt)) {
        return bt;
      }
      ei = xn_int_wrap((ei + 1));
    }
    return rt_string_from_c("Any");
  }
  xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("unsupported expression: "), n->kind), n);
  return rt_string_from_c("Error");
}

static rt_string * xn_Cls_Checker_syntacticType(xn_Cls_Checker *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Int"))) {
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Double"))) {
    return rt_string_from_c("Double");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Bool"))) {
    return rt_string_from_c("Bool");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Char"))) {
    return rt_string_from_c("Char");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    return rt_string_from_c("String");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Cast"))) {
    return n->text;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Unary")) && (((int64_t)n->kids->len) > 0))) {
    return xn_Cls_Checker_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Binary")) && (((int64_t)n->kids->len) > 1))) {
    if ((((((((xn_str_eq(n->text, rt_string_from_c("==")) || xn_str_eq(n->text, rt_string_from_c("!="))) || xn_str_eq(n->text, rt_string_from_c("<"))) || xn_str_eq(n->text, rt_string_from_c("<="))) || xn_str_eq(n->text, rt_string_from_c(">"))) || xn_str_eq(n->text, rt_string_from_c(">="))) || xn_str_eq(n->text, rt_string_from_c("&&"))) || xn_str_eq(n->text, rt_string_from_c("||")))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(xn_Cls_Checker_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("Double")) || xn_str_eq(xn_Cls_Checker_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1))), rt_string_from_c("Double")))) {
      return rt_string_from_c("Double");
    }
    return rt_string_from_c("Int");
  }
  if (((xn_str_eq(n->kind, rt_string_from_c("Call")) && xn_str_eq(n->text, rt_string_from_c("Ok"))) && (((int64_t)n->kids->len) > 0))) {
    return xn_Cls_Checker_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
  }
  return rt_string_from_c("Int");
}

static rt_string * xn_Cls_Checker_spawnReturnType(xn_Cls_Checker *self, xn_Cls_AstNode * n) {
  if ((xn_str_eq(n->kind, rt_string_from_c("Return")) && (((int64_t)n->kids->len) > 0))) {
    xn_Cls_AstNode * v = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
    if (((xn_str_eq(v->kind, rt_string_from_c("Call")) && xn_str_eq(v->text, rt_string_from_c("Ok"))) && (((int64_t)v->kids->len) > 0))) {
      return xn_Cls_Checker_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(v->kids, 0)));
    }
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    rt_string * r = xn_Cls_Checker_spawnReturnType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)));
    if ((!xn_str_eq(r, rt_string_from_c("")))) {
      return r;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_Checker_spawnLambdaType(xn_Cls_Checker *self, xn_Cls_AstNode * lam) {
  rt_string * vt = xn_Cls_Checker_spawnReturnType(self, lam);
  if (xn_str_eq(vt, rt_string_from_c(""))) {
    vt = rt_string_from_c("Int");
  }
  return xn_concat(xn_concat(rt_string_from_c("Result<"), vt), rt_string_from_c(",TaskError>()"));
}

static rt_string * xn_Cls_Checker_checkMethodCall(xn_Cls_Checker *self, xn_Cls_AstNode * n) {
  if ((((int64_t)n->kids->len) < 1)) {
    return rt_string_from_c("Error");
  }
  rt_string * bt = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
  if ((xn_str_eq(bt, rt_string_from_c("Any")) || xn_str_eq(bt, rt_string_from_c("Error")))) {
    return bt;
  }
  rt_string * mth = n->text;
  int64_t argc = xn_int_wrap(xn_int_wrap((((int64_t)n->kids->len) - 1)));
  if (xn_str_eq(bt, rt_string_from_c("AtomicInt"))) {
    if (xn_str_eq(mth, rt_string_from_c("load"))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("store"))) {
      if ((argc != 1)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("AtomicInt.store expects 1 argument"), n);
      }
      return rt_string_from_c("Unit");
    }
    if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
      return rt_string_from_c("Bool");
    }
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: AtomicInt."), mth), n);
    return rt_string_from_c("Error");
  }
  if (xn_str_eq(bt, rt_string_from_c("AtomicBool"))) {
    if (xn_str_eq(mth, rt_string_from_c("load"))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("store"))) {
      if ((argc != 1)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("AtomicBool.store expects 1 argument"), n);
      }
      return rt_string_from_c("Unit");
    }
    if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
      return rt_string_from_c("Bool");
    }
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: AtomicBool."), mth), n);
    return rt_string_from_c("Error");
  }
  if ((xn_str_indexof(bt, rt_string_from_c("AtomicRef<")) == 0)) {
    if (xn_str_eq(mth, rt_string_from_c("load"))) {
      return xn_str_substr(bt, 10, xn_int_wrap((((int64_t)bt->len) - 11)));
    }
    if (xn_str_eq(mth, rt_string_from_c("store"))) {
      if ((argc != 1)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("AtomicRef.store expects 1 argument"), n);
      }
      return rt_string_from_c("Unit");
    }
    if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
      return rt_string_from_c("Bool");
    }
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: AtomicRef."), mth), n);
    return rt_string_from_c("Error");
  }
  if ((xn_str_indexof(bt, rt_string_from_c("Channel<")) == 0)) {
    rt_string * elementType = xn_str_substr(bt, 8, xn_int_wrap((((int64_t)bt->len) - 9)));
    if (xn_str_eq(mth, rt_string_from_c("send"))) {
      return rt_string_from_c("Result<void,CancelledError>");
    }
    if (xn_str_eq(mth, rt_string_from_c("receive"))) {
      return xn_concat(xn_concat(rt_string_from_c("Result<"), elementType), rt_string_from_c(",CancelledError>"));
    }
    if (xn_str_eq(mth, rt_string_from_c("close"))) {
      return rt_string_from_c("Unit");
    }
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: Channel."), mth), n);
    return rt_string_from_c("Error");
  }
  if (xn_Cls_Checker_isMutexType(self, bt)) {
    if (xn_str_eq(mth, rt_string_from_c("withLock"))) {
      if ((argc != 1)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Mutex.withLock expects 1 argument"), n);
        return rt_string_from_c("Error");
      }
      rt_string * elem = xn_Cls_Checker_mutexElement(self, bt);
      xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)), xn_concat(xn_concat(rt_string_from_c("Unit("), elem), rt_string_from_c(")")));
      return rt_string_from_c("Result<void,TaskError>");
    }
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: Mutex."), mth), n);
    return rt_string_from_c("Error");
  }
  if (xn_str_eq(bt, rt_string_from_c("Context"))) {
    if (xn_str_eq(mth, rt_string_from_c("isCancelled"))) {
      if ((argc != 0)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Context.isCancelled expects 0 arguments"), n);
      }
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
      if ((argc != 0)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Context.cancel expects 0 arguments"), n);
      }
      return rt_string_from_c("Unit");
    }
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: Context."), mth), n);
    return rt_string_from_c("Error");
  }
  if (xn_str_eq(bt, rt_string_from_c("TaskGroup"))) {
    if (xn_str_eq(mth, rt_string_from_c("spawn"))) {
      if ((argc != 1)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("TaskGroup.spawn expects 1 argument"), n);
      }
      rt_string * exp = rt_string_from_c("Result<Int,TaskError>()");
      if ((argc == 1)) {
        exp = xn_Cls_Checker_spawnLambdaType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
      }
      xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)), exp);
      return xn_concat(xn_concat(rt_string_from_c("Task<"), xn_Cls_Checker_resultValueType(self, xn_Cls_Checker_fnRetType(self, exp))), rt_string_from_c(">"));
    }
    if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
      if ((argc != 0)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("TaskGroup.cancel expects 0 arguments"), n);
      }
      return rt_string_from_c("Unit");
    }
    if (xn_str_eq(mth, rt_string_from_c("close"))) {
      if ((argc != 0)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("TaskGroup.close expects 0 arguments"), n);
      }
      return rt_string_from_c("Result<void,TaskError>");
    }
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: TaskGroup."), mth), n);
    return rt_string_from_c("Error");
  }
  if (xn_Cls_Checker_isTaskType(self, bt)) {
    if ((xn_str_eq(mth, rt_string_from_c("join")) || xn_str_eq(mth, rt_string_from_c("joinDeadline")))) {
      if ((xn_str_eq(mth, rt_string_from_c("joinDeadline")) && (argc != 1))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Task.joinDeadline expects 1 argument"), n);
      }
      if ((xn_str_eq(mth, rt_string_from_c("join")) && (argc != 0))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Task.join expects 0 arguments"), n);
      }
      return xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_Checker_taskElement(self, bt)), rt_string_from_c(",TaskError>"));
    }
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: Task."), mth), n);
    return rt_string_from_c("Error");
  }
  if (xn_str_eq(bt, rt_string_from_c("Bytes"))) {
    if ((xn_str_eq(mth, rt_string_from_c("length")) || xn_str_eq(mth, rt_string_from_c("get")))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("slice"))) {
      return rt_string_from_c("Bytes");
    }
    if (xn_str_eq(mth, rt_string_from_c("toString"))) {
      return rt_string_from_c("String");
    }
    if (((xn_str_eq(mth, rt_string_from_c("set")) || xn_str_eq(mth, rt_string_from_c("append"))) || xn_str_eq(mth, rt_string_from_c("push")))) {
      return rt_string_from_c("Unit");
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("Bytes"))) {
    if ((xn_str_eq(mth, rt_string_from_c("length")) || xn_str_eq(mth, rt_string_from_c("get")))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("slice"))) {
      return rt_string_from_c("Bytes");
    }
    if (xn_str_eq(mth, rt_string_from_c("toString"))) {
      return rt_string_from_c("String");
    }
    if (((xn_str_eq(mth, rt_string_from_c("set")) || xn_str_eq(mth, rt_string_from_c("append"))) || xn_str_eq(mth, rt_string_from_c("push")))) {
      return rt_string_from_c("Unit");
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("String"))) {
    if ((((xn_str_eq(mth, rt_string_from_c("length")) || xn_str_eq(mth, rt_string_from_c("indexOf"))) || xn_str_eq(mth, rt_string_from_c("indexOfByte"))) || xn_str_eq(mth, rt_string_from_c("get")))) {
      return rt_string_from_c("Int");
    }
    if ((xn_str_eq(mth, rt_string_from_c("substring")) || xn_str_eq(mth, rt_string_from_c("charAt")))) {
      return rt_string_from_c("String");
    }
    if ((((xn_str_eq(mth, rt_string_from_c("trim")) || xn_str_eq(mth, rt_string_from_c("replace"))) || xn_str_eq(mth, rt_string_from_c("toUpper"))) || xn_str_eq(mth, rt_string_from_c("toLower")))) {
      return rt_string_from_c("String");
    }
    if ((xn_str_eq(mth, rt_string_from_c("startsWith")) || xn_str_eq(mth, rt_string_from_c("endsWith")))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("split"))) {
      return rt_string_from_c("List<String>");
    }
  }
  if (xn_Cls_Checker_isSetType(self, bt)) {
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("has"))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(mth, rt_string_from_c("add")) || xn_str_eq(mth, rt_string_from_c("remove")))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("clear"))) {
      return rt_string_from_c("Unit");
    }
  }
  if (xn_Cls_Checker_isResultType(self, bt)) {
    if ((xn_str_eq(mth, rt_string_from_c("isOk")) || xn_str_eq(mth, rt_string_from_c("isErr")))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(mth, rt_string_from_c("value")) || xn_str_eq(mth, rt_string_from_c("unwrapOr")))) {
      return xn_Cls_Checker_resultValueType(self, bt);
    }
    if (xn_str_eq(mth, rt_string_from_c("error"))) {
      return xn_Cls_Checker_resultErrorType(self, bt);
    }
  }
  if ((!xn_str_eq(xn_Cls_Checker_elementType(self, bt), rt_string_from_c("Any")))) {
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("get"))) {
      return xn_Cls_Checker_elementType(self, bt);
    }
    if (((((xn_str_eq(mth, rt_string_from_c("push")) || xn_str_eq(mth, rt_string_from_c("remove"))) || xn_str_eq(mth, rt_string_from_c("set"))) || xn_str_eq(mth, rt_string_from_c("insert"))) || xn_str_eq(mth, rt_string_from_c("clear")))) {
      return rt_string_from_c("Unit");
    }
    if ((xn_str_eq(mth, rt_string_from_c("tryGet")) || xn_str_eq(mth, rt_string_from_c("tryRemove")))) {
      return xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_Checker_elementType(self, bt)), rt_string_from_c(",Error>"));
    }
    if ((xn_str_eq(mth, rt_string_from_c("trySet")) || xn_str_eq(mth, rt_string_from_c("tryInsert")))) {
      return rt_string_from_c("Result<Unit,Error>");
    }
    if (xn_str_eq(mth, rt_string_from_c("join"))) {
      return rt_string_from_c("String");
    }
  }
  if (xn_Cls_Checker_isMapType(self, bt)) {
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("has"))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(mth, rt_string_from_c("put")) || xn_str_eq(mth, rt_string_from_c("remove")))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("clear"))) {
      return rt_string_from_c("Unit");
    }
    if ((xn_str_eq(mth, rt_string_from_c("getOr")) || xn_str_eq(mth, rt_string_from_c("removeOr")))) {
      return xn_Cls_Checker_mapValueType(self, bt);
    }
    if (xn_str_eq(mth, rt_string_from_c("tryGet"))) {
      return xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_Checker_mapValueType(self, bt)), rt_string_from_c(",Error>"));
    }
    if (xn_str_eq(mth, rt_string_from_c("keys"))) {
      return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_Checker_mapKeyType(self, bt)), rt_string_from_c(">"));
    }
    if (xn_str_eq(mth, rt_string_from_c("values"))) {
      return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_Checker_mapValueType(self, bt)), rt_string_from_c(">"));
    }
    if (xn_str_eq(mth, rt_string_from_c("entries"))) {
      if (xn_str_eq(bt, rt_string_from_c("Map<String,Int>"))) {
        return rt_string_from_c("List<Pair>");
      }
      if (xn_str_eq(bt, rt_string_from_c("Map<Int,Int>"))) {
        return rt_string_from_c("List<IntPair>");
      }
      return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_Checker_entryClassName(self, xn_Cls_Checker_mapKeyType(self, bt), xn_Cls_Checker_mapValueType(self, bt))), rt_string_from_c(">"));
    }
  }
  if (xn_Cls_Checker_isProtocolName(self, bt)) {
    rt_string * pr = xn_Cls_Checker_protocolRet(self, bt, mth);
    if ((!xn_str_eq(pr, rt_string_from_c("Any")))) {
      rt_string * pps = xn_Cls_Checker_protocolParams(self, bt, mth);
      xn_arr_s *pwant = xn_arr_s_new(0);
      if ((!xn_str_eq(pps, rt_string_from_c("")))) {
        pwant = xn_str_split(pps, rt_string_from_c(","));
      }
      if ((((int64_t)pwant->len) != argc)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(xn_concat(xn_concat(mth, rt_string_from_c(" expects ")), xn_str_int(((int64_t)pwant->len))), rt_string_from_c(" arguments, got ")), xn_str_int(argc)), n);
        return rt_string_from_c("Error");
      }
      int64_t pai = xn_int_wrap(0);
      while (((pai < argc) && (!xn_Cls_Checker_hasError(self)))) {
        rt_string * pat = xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((pai + 1)))), xn_arr_s_get(pwant, pai));
        if (((!xn_str_eq(pat, rt_string_from_c("Error"))) && (!xn_Cls_Checker_isAssignable(self, xn_arr_s_get(pwant, pai), pat)))) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("argument "), xn_str_int(xn_int_wrap((pai + 1)))), rt_string_from_c(" of ")), mth), rt_string_from_c(": expected ")), xn_arr_s_get(pwant, pai)), rt_string_from_c(", got ")), pat), n);
        }
        pai = xn_int_wrap((pai + 1));
      }
      return pr;
    }
  }
  int64_t mi = xn_int_wrap(xn_Cls_Checker_findMethod(self, bt, mth));
  if ((mi < 0)) {
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(xn_concat(xn_concat(rt_string_from_c("undefined method: "), bt), rt_string_from_c(".")), mth), n);
    return rt_string_from_c("Error");
  }
  rt_string * ps = xn_arr_s_get(self->methodParams, mi);
  if (xn_str_eq(ps, rt_string_from_c(""))) {
    if ((argc != 0)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(mth, rt_string_from_c(" expects 0 arguments, got ")), xn_str_int(argc)), n);
      return rt_string_from_c("Error");
    }
    return xn_arr_s_get(self->methodRets, mi);
  }
  xn_arr_s * want = xn_splitTop(ps);
  if ((((int64_t)want->len) != argc)) {
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(xn_concat(xn_concat(mth, rt_string_from_c(" expects ")), xn_str_int(((int64_t)want->len))), rt_string_from_c(" arguments, got ")), xn_str_int(argc)), n);
    return rt_string_from_c("Error");
  }
  int64_t ai = xn_int_wrap(0);
  while (((ai < argc) && (!xn_Cls_Checker_hasError(self)))) {
    rt_string * at = xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((ai + 1)))), xn_arr_s_get(want, ai));
    if (((!xn_str_eq(at, rt_string_from_c("Error"))) && (!xn_Cls_Checker_isAssignable(self, xn_arr_s_get(want, ai), at)))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("argument "), xn_str_int(xn_int_wrap((ai + 1)))), rt_string_from_c(" of ")), mth), rt_string_from_c(": expected ")), xn_arr_s_get(want, ai)), rt_string_from_c(", got ")), at), n);
    }
    ai = xn_int_wrap((ai + 1));
  }
  return xn_arr_s_get(self->methodRets, mi);
}

static rt_string * xn_Cls_Checker_argType(xn_Cls_Checker *self, xn_Cls_AstNode * arg, rt_string * want) {
  if (xn_str_eq(arg->kind, rt_string_from_c("Lambda"))) {
    rt_string * oldExp = self->expectedLambda;
    self->expectedLambda = want;
    rt_string * t = xn_Cls_Checker_typeOf(self, arg);
    self->expectedLambda = oldExp;
    return t;
  }
  return xn_Cls_Checker_typeOf(self, arg);
}

static rt_string * xn_Cls_Checker_checkCall(xn_Cls_Checker *self, xn_Cls_AstNode * n) {
  int64_t argc = xn_int_wrap(((int64_t)n->kids->len));
  if ((xn_str_eq(n->text, rt_string_from_c("AtomicInt")) || xn_str_eq(n->text, rt_string_from_c("AtomicBool")))) {
    if ((argc > 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(n->text, rt_string_from_c(" expects 0 or 1 argument")), n);
      return rt_string_from_c("Error");
    }
    if ((argc == 1)) {
      rt_string * at = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      rt_string * want = rt_string_from_c("Int");
      if (xn_str_eq(n->text, rt_string_from_c("AtomicBool"))) {
        want = rt_string_from_c("Bool");
      }
      if (((!xn_str_eq(at, rt_string_from_c("Error"))) && (!xn_Cls_Checker_sameType(self, at, want)))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(n->text, rt_string_from_c(" expects ")), want), rt_string_from_c(", got ")), at), n);
        return rt_string_from_c("Error");
      }
    }
    return n->text;
  }
  if (xn_str_eq(n->text, rt_string_from_c("AtomicRef"))) {
    if ((argc > 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("AtomicRef expects 0 or 1 argument"), n);
      return rt_string_from_c("Error");
    }
    rt_string * inner = rt_string_from_c("String");
    if ((argc == 1)) {
      inner = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      if (xn_str_eq(inner, rt_string_from_c("Error"))) {
        return rt_string_from_c("Error");
      }
    }
    return xn_concat(xn_concat(rt_string_from_c("AtomicRef<"), inner), rt_string_from_c(">"));
  }
  if ((xn_str_eq(n->text, rt_string_from_c("Channel")) || xn_str_startswith(n->text, rt_string_from_c("Channel<")))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Channel expects 1 argument"), n);
      return rt_string_from_c("Error");
    }
    xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (xn_str_startswith(n->text, rt_string_from_c("Channel<"))) {
      return n->text;
    }
    return rt_string_from_c("Channel<Int>");
  }
  if (xn_str_eq(n->text, rt_string_from_c("Mutex"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Mutex expects 1 argument"), n);
      return rt_string_from_c("Error");
    }
    rt_string * it = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (xn_str_eq(it, rt_string_from_c("Error"))) {
      return rt_string_from_c("Error");
    }
    return xn_concat(xn_concat(rt_string_from_c("Mutex<"), it), rt_string_from_c(">"));
  }
  if (xn_str_eq(n->text, rt_string_from_c("Context.background"))) {
    if ((argc != 0)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Context.background expects 0 arguments"), n);
    }
    return rt_string_from_c("Context");
  }
  if (xn_str_eq(n->text, rt_string_from_c("TaskGroup.create"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("TaskGroup.create expects 1 argument"), n);
      return rt_string_from_c("Error");
    }
    rt_string * ct = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (((!xn_str_eq(ct, rt_string_from_c("Error"))) && (!xn_str_eq(ct, rt_string_from_c("Context"))))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("TaskGroup.create expects Context, got "), ct), n);
    }
    return rt_string_from_c("TaskGroup");
  }
  if (xn_str_eq(n->text, rt_string_from_c("diagnoseRaw"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("diagnoseRaw expects 1 argument"), n);
    }
    else {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->text, rt_string_from_c("exitRaw"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("exitRaw expects 1 argument"), n);
    }
    else {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->text, rt_string_from_c("listFiles"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("listFiles expects 1 argument"), n);
    }
    else {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return rt_string_from_c("String");
  }
  if (xn_str_eq(n->text, rt_string_from_c("readFile"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("readFile expects 1 argument"), n);
    }
    else {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return rt_string_from_c("String");
  }
  if ((xn_str_eq(n->text, rt_string_from_c("nowMonoRaw")) || xn_str_eq(n->text, rt_string_from_c("nowWallRaw")))) {
    if ((argc != 0)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(n->text, rt_string_from_c(" expects 0 arguments")), n);
    }
    return rt_string_from_c("Long");
  }
  if (xn_str_eq(n->text, rt_string_from_c("resourceExistsRaw"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("resourceExistsRaw expects 1 argument"), n);
    }
    else {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->text, rt_string_from_c("readResourceTextRaw"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("readResourceTextRaw expects 1 argument"), n);
    }
    else {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return rt_string_from_c("String");
  }
  if (xn_str_eq(n->text, rt_string_from_c("resourceCountRaw"))) {
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->text, rt_string_from_c("readFileTextRaw"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("readFileTextRaw expects 1 argument"), n);
    }
    else {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return rt_string_from_c("String");
  }
  if (xn_str_eq(n->text, rt_string_from_c("readFileTextError"))) {
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->text, rt_string_from_c("fileExistsRaw"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("fileExistsRaw expects 1 argument"), n);
    }
    else {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->text, rt_string_from_c("platformRaw"))) {
    if ((argc != 0)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("platformRaw expects 0 arguments"), n);
    }
    return rt_string_from_c("String");
  }
  if (xn_str_eq(n->text, rt_string_from_c("Set.of"))) {
    rt_string * elementType = rt_string_from_c("Int");
    int seenElement = 0;
    int64_t i = xn_int_wrap(0);
    while ((i < argc)) {
      xn_Cls_AstNode * arg = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i));
      rt_string * at = xn_Cls_Checker_typeOf(self, arg);
      if ((xn_str_eq(arg->kind, rt_string_from_c("Int")) && (!xn_Cls_Checker_intFits32(self, arg->text)))) {
        at = rt_string_from_c("Long");
      }
      if ((((xn_str_eq(arg->kind, rt_string_from_c("Unary")) && (((int64_t)arg->kids->len) > 0)) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0))->kind, rt_string_from_c("Int"))) && (!xn_Cls_Checker_intFits32(self, ((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0))->text)))) {
        at = rt_string_from_c("Long");
      }
      if ((((xn_str_eq(at, rt_string_from_c("Error")) || xn_str_eq(at, rt_string_from_c("Unit"))) || xn_str_eq(at, rt_string_from_c("Void"))) || (!xn_Cls_Checker_knownType(self, at)))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("Set.of unsupported element type: "), at), n);
      }
      else {
        if ((!seenElement)) {
          elementType = at;
          seenElement = 1;
        }
        else {
          if (xn_str_eq(at, elementType)) {
          }
          else {
            if ((xn_str_eq(elementType, rt_string_from_c("Int")) && xn_str_eq(at, rt_string_from_c("Long")))) {
              elementType = rt_string_from_c("Long");
            }
            else {
              if ((xn_str_eq(elementType, rt_string_from_c("Long")) && xn_str_eq(at, rt_string_from_c("Int")))) {
              }
              else {
                xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), rt_string_from_c("Set.of mixed element types"), n);
              }
            }
          }
        }
      }
      i = xn_int_wrap((i + 1));
    }
    return xn_concat(xn_concat(rt_string_from_c("Set<"), elementType), rt_string_from_c(">"));
  }
  if ((xn_str_eq(n->text, rt_string_from_c("Ok")) || xn_str_eq(n->text, rt_string_from_c("Err")))) {
    if ((!xn_Cls_Checker_isResultType(self, self->curRet))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(n->text, rt_string_from_c(" requires Result return type")), n);
      return rt_string_from_c("Error");
    }
    if ((argc > 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(n->text, rt_string_from_c(" expects 0 or 1 argument, got ")), xn_str_int(argc)), n);
      return rt_string_from_c("Error");
    }
    if ((argc > 0)) {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return self->curRet;
  }
  int64_t dot = xn_int_wrap(xn_lastDot(n->text));
  if ((dot >= 0)) {
    rt_string * base = xn_str_substr(n->text, 0, dot);
    rt_string * mth = xn_str_substr(n->text, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)n->text->len) - dot)) - 1)));
    rt_string * bt = xn_Cls_Checker_pathType(self, base);
    if (xn_str_eq(bt, rt_string_from_c("Any"))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined symbol: "), base), n);
      return rt_string_from_c("Error");
    }
    if (xn_str_eq(bt, rt_string_from_c("AtomicInt"))) {
      if (xn_str_eq(mth, rt_string_from_c("load"))) {
        return rt_string_from_c("Int");
      }
      if (xn_str_eq(mth, rt_string_from_c("store"))) {
        if ((argc != 1)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("AtomicInt.store expects 1 argument"), n);
        }
        return rt_string_from_c("Unit");
      }
      if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
        return rt_string_from_c("Bool");
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: AtomicInt."), mth), n);
      return rt_string_from_c("Error");
    }
    if (xn_str_eq(bt, rt_string_from_c("AtomicBool"))) {
      if (xn_str_eq(mth, rt_string_from_c("load"))) {
        return rt_string_from_c("Bool");
      }
      if (xn_str_eq(mth, rt_string_from_c("store"))) {
        if ((argc != 1)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("AtomicBool.store expects 1 argument"), n);
        }
        return rt_string_from_c("Unit");
      }
      if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
        return rt_string_from_c("Bool");
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: AtomicBool."), mth), n);
      return rt_string_from_c("Error");
    }
    if ((xn_str_indexof(bt, rt_string_from_c("AtomicRef<")) == 0)) {
      if (xn_str_eq(mth, rt_string_from_c("load"))) {
        return xn_str_substr(bt, 10, xn_int_wrap((((int64_t)bt->len) - 11)));
      }
      if (xn_str_eq(mth, rt_string_from_c("store"))) {
        if ((argc != 1)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("AtomicRef.store expects 1 argument"), n);
        }
        return rt_string_from_c("Unit");
      }
      if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
        return rt_string_from_c("Bool");
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: AtomicRef."), mth), n);
      return rt_string_from_c("Error");
    }
    if ((xn_str_indexof(bt, rt_string_from_c("Channel<")) == 0)) {
      rt_string * elementType = xn_str_substr(bt, 8, xn_int_wrap((((int64_t)bt->len) - 9)));
      if (xn_str_eq(mth, rt_string_from_c("send"))) {
        return rt_string_from_c("Result<void,CancelledError>");
      }
      if (xn_str_eq(mth, rt_string_from_c("receive"))) {
        return xn_concat(xn_concat(rt_string_from_c("Result<"), elementType), rt_string_from_c(",CancelledError>"));
      }
      if (xn_str_eq(mth, rt_string_from_c("close"))) {
        return rt_string_from_c("Unit");
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: Channel."), mth), n);
      return rt_string_from_c("Error");
    }
    if (xn_Cls_Checker_isMutexType(self, bt)) {
      if (xn_str_eq(mth, rt_string_from_c("withLock"))) {
        if ((argc != 1)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Mutex.withLock expects 1 argument"), n);
          return rt_string_from_c("Error");
        }
        xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)), xn_concat(xn_concat(rt_string_from_c("Unit("), xn_Cls_Checker_mutexElement(self, bt)), rt_string_from_c(")")));
        return rt_string_from_c("Result<void,TaskError>");
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: Mutex."), mth), n);
      return rt_string_from_c("Error");
    }
    if (xn_str_eq(bt, rt_string_from_c("Context"))) {
      if (xn_str_eq(mth, rt_string_from_c("isCancelled"))) {
        if ((argc != 0)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Context.isCancelled expects 0 arguments"), n);
        }
        return rt_string_from_c("Bool");
      }
      if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
        if ((argc != 0)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Context.cancel expects 0 arguments"), n);
        }
        return rt_string_from_c("Unit");
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: Context."), mth), n);
      return rt_string_from_c("Error");
    }
    if (xn_str_eq(bt, rt_string_from_c("TaskGroup"))) {
      if (xn_str_eq(mth, rt_string_from_c("spawn"))) {
        if ((argc != 1)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("TaskGroup.spawn expects 1 argument"), n);
        }
        rt_string * exp = rt_string_from_c("Result<Int,TaskError>()");
        if ((argc == 1)) {
          exp = xn_Cls_Checker_spawnLambdaType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
        }
        xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)), exp);
        return xn_concat(xn_concat(rt_string_from_c("Task<"), xn_Cls_Checker_resultValueType(self, xn_Cls_Checker_fnRetType(self, exp))), rt_string_from_c(">"));
      }
      if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
        if ((argc != 0)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("TaskGroup.cancel expects 0 arguments"), n);
        }
        return rt_string_from_c("Unit");
      }
      if (xn_str_eq(mth, rt_string_from_c("close"))) {
        if ((argc != 0)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("TaskGroup.close expects 0 arguments"), n);
        }
        return rt_string_from_c("Result<void,TaskError>");
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: TaskGroup."), mth), n);
      return rt_string_from_c("Error");
    }
    if (xn_Cls_Checker_isTaskType(self, bt)) {
      if ((xn_str_eq(mth, rt_string_from_c("join")) || xn_str_eq(mth, rt_string_from_c("joinDeadline")))) {
        if ((xn_str_eq(mth, rt_string_from_c("joinDeadline")) && (argc != 1))) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Task.joinDeadline expects 1 argument"), n);
        }
        if ((xn_str_eq(mth, rt_string_from_c("join")) && (argc != 0))) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Task.join expects 0 arguments"), n);
        }
        return xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_Checker_taskElement(self, bt)), rt_string_from_c(",TaskError>"));
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined method: Task."), mth), n);
      return rt_string_from_c("Error");
    }
    if (xn_str_eq(bt, rt_string_from_c("Bytes"))) {
      if (xn_str_eq(mth, rt_string_from_c("fromString"))) {
        return rt_string_from_c("Bytes");
      }
      if ((xn_str_eq(mth, rt_string_from_c("length")) || xn_str_eq(mth, rt_string_from_c("get")))) {
        return rt_string_from_c("Int");
      }
      if (xn_str_eq(mth, rt_string_from_c("slice"))) {
        return rt_string_from_c("Bytes");
      }
      if (xn_str_eq(mth, rt_string_from_c("toString"))) {
        return rt_string_from_c("String");
      }
      if (((xn_str_eq(mth, rt_string_from_c("set")) || xn_str_eq(mth, rt_string_from_c("append"))) || xn_str_eq(mth, rt_string_from_c("push")))) {
        return rt_string_from_c("Unit");
      }
    }
    if (xn_str_eq(bt, rt_string_from_c("String"))) {
      if ((xn_str_eq(mth, rt_string_from_c("length")) || xn_str_eq(mth, rt_string_from_c("get")))) {
        return rt_string_from_c("Int");
      }
      if ((xn_str_eq(mth, rt_string_from_c("indexOf")) || xn_str_eq(mth, rt_string_from_c("indexOfByte")))) {
        return rt_string_from_c("Int");
      }
      if ((xn_str_eq(mth, rt_string_from_c("substring")) || xn_str_eq(mth, rt_string_from_c("charAt")))) {
        return rt_string_from_c("String");
      }
      if ((((xn_str_eq(mth, rt_string_from_c("trim")) || xn_str_eq(mth, rt_string_from_c("replace"))) || xn_str_eq(mth, rt_string_from_c("toUpper"))) || xn_str_eq(mth, rt_string_from_c("toLower")))) {
        return rt_string_from_c("String");
      }
      if ((xn_str_eq(mth, rt_string_from_c("startsWith")) || xn_str_eq(mth, rt_string_from_c("endsWith")))) {
        return rt_string_from_c("Bool");
      }
      if (xn_str_eq(mth, rt_string_from_c("split"))) {
        return rt_string_from_c("List<String>");
      }
    }
    if (xn_Cls_Checker_isSetType(self, bt)) {
      if (xn_str_eq(mth, rt_string_from_c("length"))) {
        return rt_string_from_c("Int");
      }
      if (xn_str_eq(mth, rt_string_from_c("has"))) {
        return rt_string_from_c("Bool");
      }
      if ((xn_str_eq(mth, rt_string_from_c("add")) || xn_str_eq(mth, rt_string_from_c("remove")))) {
        return rt_string_from_c("Bool");
      }
      if (xn_str_eq(mth, rt_string_from_c("clear"))) {
        return rt_string_from_c("Unit");
      }
    }
    if (xn_Cls_Checker_isResultType(self, bt)) {
      if ((xn_str_eq(mth, rt_string_from_c("isOk")) || xn_str_eq(mth, rt_string_from_c("isErr")))) {
        return rt_string_from_c("Bool");
      }
      if (xn_str_eq(mth, rt_string_from_c("unwrapOr"))) {
        return xn_Cls_Checker_resultValueType(self, bt);
      }
      if (xn_str_eq(mth, rt_string_from_c("value"))) {
        return xn_Cls_Checker_resultValueType(self, bt);
      }
      if (xn_str_eq(mth, rt_string_from_c("error"))) {
        return xn_Cls_Checker_resultErrorType(self, bt);
      }
    }
    if ((!xn_str_eq(xn_Cls_Checker_elementType(self, bt), rt_string_from_c("Any")))) {
      if (xn_str_eq(mth, rt_string_from_c("length"))) {
        return rt_string_from_c("Int");
      }
      if (xn_str_eq(mth, rt_string_from_c("get"))) {
        return xn_Cls_Checker_elementType(self, bt);
      }
      if (((((xn_str_eq(mth, rt_string_from_c("push")) || xn_str_eq(mth, rt_string_from_c("set"))) || xn_str_eq(mth, rt_string_from_c("insert"))) || xn_str_eq(mth, rt_string_from_c("remove"))) || xn_str_eq(mth, rt_string_from_c("clear")))) {
        return rt_string_from_c("Unit");
      }
      if ((xn_str_eq(mth, rt_string_from_c("tryGet")) || xn_str_eq(mth, rt_string_from_c("tryRemove")))) {
        return xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_Checker_elementType(self, bt)), rt_string_from_c(",Error>"));
      }
      if ((xn_str_eq(mth, rt_string_from_c("trySet")) || xn_str_eq(mth, rt_string_from_c("tryInsert")))) {
        return rt_string_from_c("Result<Unit,Error>");
      }
      if (xn_str_eq(mth, rt_string_from_c("join"))) {
        return rt_string_from_c("String");
      }
    }
    if (xn_Cls_Checker_isMapType(self, bt)) {
      if (xn_str_eq(mth, rt_string_from_c("length"))) {
        return rt_string_from_c("Int");
      }
      if (xn_str_eq(mth, rt_string_from_c("has"))) {
        return rt_string_from_c("Bool");
      }
      if (xn_str_eq(mth, rt_string_from_c("getOr"))) {
        return xn_Cls_Checker_mapValueType(self, bt);
      }
      if ((xn_str_eq(mth, rt_string_from_c("put")) || xn_str_eq(mth, rt_string_from_c("remove")))) {
        return rt_string_from_c("Bool");
      }
      if (xn_str_eq(mth, rt_string_from_c("clear"))) {
        return rt_string_from_c("Unit");
      }
      if ((xn_str_eq(mth, rt_string_from_c("getOr")) || xn_str_eq(mth, rt_string_from_c("removeOr")))) {
        return xn_Cls_Checker_mapValueType(self, bt);
      }
      if (xn_str_eq(mth, rt_string_from_c("tryGet"))) {
        return xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_Checker_mapValueType(self, bt)), rt_string_from_c(",Error>"));
      }
      if (xn_str_eq(mth, rt_string_from_c("keys"))) {
        return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_Checker_mapKeyType(self, bt)), rt_string_from_c(">"));
      }
      if (xn_str_eq(mth, rt_string_from_c("values"))) {
        return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_Checker_mapValueType(self, bt)), rt_string_from_c(">"));
      }
      if (xn_str_eq(mth, rt_string_from_c("entries"))) {
        if (xn_str_eq(bt, rt_string_from_c("Map<String,Int>"))) {
          return rt_string_from_c("List<Pair>");
        }
        if (xn_str_eq(bt, rt_string_from_c("Map<Int,Int>"))) {
          return rt_string_from_c("List<IntPair>");
        }
        return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_Checker_entryClassName(self, xn_Cls_Checker_mapKeyType(self, bt), xn_Cls_Checker_mapValueType(self, bt))), rt_string_from_c(">"));
      }
    }
    if (xn_Cls_Checker_isProtocolName(self, bt)) {
      rt_string * pr = xn_Cls_Checker_protocolRet(self, bt, mth);
      if ((!xn_str_eq(pr, rt_string_from_c("Any")))) {
        rt_string * pps = xn_Cls_Checker_protocolParams(self, bt, mth);
        xn_arr_s *pwant = xn_arr_s_new(0);
        if ((!xn_str_eq(pps, rt_string_from_c("")))) {
          pwant = xn_str_split(pps, rt_string_from_c(","));
        }
        if ((((int64_t)pwant->len) != argc)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(xn_concat(xn_concat(mth, rt_string_from_c(" expects ")), xn_str_int(((int64_t)pwant->len))), rt_string_from_c(" arguments, got ")), xn_str_int(argc)), n);
          return rt_string_from_c("Error");
        }
        int64_t pai = xn_int_wrap(0);
        while (((pai < argc) && (!xn_Cls_Checker_hasError(self)))) {
          rt_string * pat = xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, pai)), xn_arr_s_get(pwant, pai));
          if (((!xn_str_eq(pat, rt_string_from_c("Error"))) && (!xn_Cls_Checker_isAssignable(self, xn_arr_s_get(pwant, pai), pat)))) {
            xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("argument "), xn_str_int(xn_int_wrap((pai + 1)))), rt_string_from_c(" of ")), mth), rt_string_from_c(": expected ")), xn_arr_s_get(pwant, pai)), rt_string_from_c(", got ")), pat), n);
          }
          pai = xn_int_wrap((pai + 1));
        }
        return pr;
      }
    }
    rt_string * fty = xn_Cls_Checker_fieldType(self, bt, mth);
    if (xn_Cls_Checker_isFunctionType(self, fty)) {
      xn_arr_s * want = xn_Cls_Checker_fnParams(self, fty);
      if ((((int64_t)want->len) != argc)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(xn_concat(xn_concat(mth, rt_string_from_c(" expects ")), xn_str_int(((int64_t)want->len))), rt_string_from_c(" arguments, got ")), xn_str_int(argc)), n);
        return rt_string_from_c("Error");
      }
      int64_t ai = xn_int_wrap(0);
      while (((ai < argc) && (!xn_Cls_Checker_hasError(self)))) {
        rt_string * at = xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ai)), xn_arr_s_get(want, ai));
        if (((!xn_str_eq(at, rt_string_from_c("Error"))) && (!xn_Cls_Checker_isAssignable(self, xn_arr_s_get(want, ai), at)))) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("argument "), xn_str_int(xn_int_wrap((ai + 1)))), rt_string_from_c(" of ")), mth), rt_string_from_c(": expected ")), xn_arr_s_get(want, ai)), rt_string_from_c(", got ")), at), n);
        }
        ai = xn_int_wrap((ai + 1));
      }
      return xn_Cls_Checker_fnRetType(self, fty);
    }
    int64_t mi = xn_int_wrap(xn_Cls_Checker_findMethod(self, bt, mth));
    if ((mi < 0)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(xn_concat(xn_concat(rt_string_from_c("undefined method: "), bt), rt_string_from_c(".")), mth), n);
      return rt_string_from_c("Error");
    }
    rt_string * ps = xn_arr_s_get(self->methodParams, mi);
    if (xn_str_eq(ps, rt_string_from_c(""))) {
      if ((argc != 0)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(mth, rt_string_from_c(" expects 0 arguments, got ")), xn_str_int(argc)), n);
        return rt_string_from_c("Error");
      }
      return xn_arr_s_get(self->methodRets, mi);
    }
    xn_arr_s * want = xn_splitTop(ps);
    if ((((int64_t)want->len) != argc)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(xn_concat(xn_concat(mth, rt_string_from_c(" expects ")), xn_str_int(((int64_t)want->len))), rt_string_from_c(" arguments, got ")), xn_str_int(argc)), n);
      return rt_string_from_c("Error");
    }
    int64_t ai = xn_int_wrap(0);
    while (((ai < argc) && (!xn_Cls_Checker_hasError(self)))) {
      rt_string * at = xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ai)), xn_arr_s_get(want, ai));
      if (((!xn_str_eq(at, rt_string_from_c("Error"))) && (!xn_Cls_Checker_isAssignable(self, xn_arr_s_get(want, ai), at)))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("argument "), xn_str_int(xn_int_wrap((ai + 1)))), rt_string_from_c(" of ")), mth), rt_string_from_c(": expected ")), xn_arr_s_get(want, ai)), rt_string_from_c(", got ")), at), n);
      }
      ai = xn_int_wrap((ai + 1));
    }
    return xn_arr_s_get(self->methodRets, mi);
  }
  int64_t ffi = xn_int_wrap(xn_ffiIndex(n->text));
  if ((ffi >= 0)) {
    return xn_ffiRet(n->text);
  }
  if (xn_str_eq(n->text, rt_string_from_c("print"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(rt_string_from_c("print expects 1 argument, got "), xn_str_int(argc)), n);
    }
    else {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return rt_string_from_c("Unit");
  }
  if (xn_str_eq(n->text, rt_string_from_c("str"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(rt_string_from_c("str expects 1 argument, got "), xn_str_int(argc)), n);
    }
    else {
      xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    }
    return rt_string_from_c("String");
  }
  int64_t fvi = xn_int_wrap(xn_Cls_Checker_findVar(self, n->text));
  if (((fvi >= 0) && xn_Cls_Checker_isFunctionType(self, xn_arr_s_get(self->varTypes, fvi)))) {
    rt_string * ft = xn_arr_s_get(self->varTypes, fvi);
    xn_arr_s * want = xn_Cls_Checker_fnParams(self, ft);
    if ((((int64_t)want->len) != argc)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(xn_concat(xn_concat(n->text, rt_string_from_c(" expects ")), xn_str_int(((int64_t)want->len))), rt_string_from_c(" arguments, got ")), xn_str_int(argc)), n);
      return rt_string_from_c("Error");
    }
    int64_t ai = xn_int_wrap(0);
    while (((ai < argc) && (!xn_Cls_Checker_hasError(self)))) {
      rt_string * at = xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ai)), xn_arr_s_get(want, ai));
      if (((!xn_str_eq(at, rt_string_from_c("Error"))) && (!xn_Cls_Checker_isAssignable(self, xn_arr_s_get(want, ai), at)))) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("argument "), xn_str_int(xn_int_wrap((ai + 1)))), rt_string_from_c(" of ")), n->text), rt_string_from_c(": expected ")), xn_arr_s_get(want, ai)), rt_string_from_c(", got ")), at), n);
      }
      ai = xn_int_wrap((ai + 1));
    }
    return xn_Cls_Checker_fnRetType(self, ft);
  }
  int64_t idx = xn_int_wrap(xn_Cls_Checker_findFn(self, n->text));
  if ((idx < 0)) {
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("undefined function: "), n->text), n);
    return rt_string_from_c("Error");
  }
  rt_string * ps = xn_arr_s_get(self->fnParams, idx);
  if (xn_str_eq(ps, rt_string_from_c(""))) {
    if ((argc != 0)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(n->text, rt_string_from_c(" expects 0 arguments, got ")), xn_str_int(argc)), n);
      return rt_string_from_c("Error");
    }
    return xn_arr_s_get(self->fnRets, idx);
  }
  xn_arr_s * want = xn_splitTop(ps);
  if ((((int64_t)want->len) != argc)) {
    xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(xn_concat(xn_concat(xn_concat(n->text, rt_string_from_c(" expects ")), xn_str_int(((int64_t)want->len))), rt_string_from_c(" arguments, got ")), xn_str_int(argc)), n);
    return rt_string_from_c("Error");
  }
  int64_t i = xn_int_wrap(0);
  while (((i < argc) && (!xn_Cls_Checker_hasError(self)))) {
    rt_string * at = xn_Cls_Checker_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), xn_arr_s_get(want, i));
    if (((!xn_str_eq(at, rt_string_from_c("Error"))) && (!xn_Cls_Checker_isAssignable(self, xn_arr_s_get(want, i), at)))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("argument "), xn_str_int(xn_int_wrap((i + 1)))), rt_string_from_c(" of ")), n->text), rt_string_from_c(": expected ")), xn_arr_s_get(want, i)), rt_string_from_c(", got ")), at), n);
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_arr_s_get(self->fnRets, idx);
}

struct xn_Cls_CGen {
  rt_header hdr;
  xn_Cls_AstNode * program;
  xn_arr_s * lines;
  xn_arr_s * vars;
  xn_arr_s * varTypes;
  int64_t tmp;
  rt_string * err;
  rt_string * curClass;
  rt_string * curRet;
  rt_string * curCtxExpr;
  xn_arr_o * defers;
  xn_arr_s * deferErrs;
  xn_arr_s * breakTargets;
  xn_arr_o * lambdas;
  xn_arr_s * lambdaTypes;
  xn_arr_s * lambdaCaptures;
  xn_arr_s * lambdaCaptureTypes;
  xn_arr_s * lambdaCaptureScanned;
  xn_arr_s * lambdaOwners;
  xn_arr_s * lambdaModes;
  xn_arr_s * ffiCallNames;
  xn_arr_s * ffiCallCNames;
  xn_arr_s * ffiCallRets;
  xn_arr_s * ffiCallSpecs;
  xn_arr_s * ffiCallErrParams;
  xn_arr_s * ffiCallErrRets;
  xn_arr_s * genericMaps;
  xn_arr_s * genericSets;
};

static const rt_type RT_TYPE_XN_CGen = { "CGen", sizeof(xn_Cls_CGen), NULL, NULL };

static xn_Cls_CGen *xn_Cls_CGen_new(xn_Cls_AstNode * program, xn_arr_s * callNames, xn_arr_s * callCNames, xn_arr_s * callRets, xn_arr_s * callSpecs, xn_arr_s * callErrParams, xn_arr_s * callErrRets) {
  xn_Cls_CGen *xn_obj = (xn_Cls_CGen *)rt_gc_new(&RT_TYPE_XN_CGen);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_CGen) - sizeof(rt_header));
  xn_obj->program = 0;
  xn_obj->lines = xn_arr_s_new(4);
  xn_obj->vars = xn_arr_s_new(4);
  xn_obj->varTypes = xn_arr_s_new(4);
  xn_obj->tmp = 0;
  xn_obj->err = rt_string_from_c("");
  xn_obj->curClass = rt_string_from_c("");
  xn_obj->curRet = rt_string_from_c("");
  xn_obj->curCtxExpr = rt_string_from_c("");
  xn_obj->defers = xn_arr_o_new(4);
  xn_obj->deferErrs = xn_arr_s_new(4);
  xn_obj->breakTargets = xn_arr_s_new(4);
  xn_obj->lambdas = xn_arr_o_new(4);
  xn_obj->lambdaTypes = xn_arr_s_new(4);
  xn_obj->lambdaCaptures = xn_arr_s_new(4);
  xn_obj->lambdaCaptureTypes = xn_arr_s_new(4);
  xn_obj->lambdaCaptureScanned = xn_arr_s_new(4);
  xn_obj->lambdaOwners = xn_arr_s_new(4);
  xn_obj->lambdaModes = xn_arr_s_new(4);
  xn_obj->ffiCallNames = xn_arr_s_new(4);
  xn_obj->ffiCallCNames = xn_arr_s_new(4);
  xn_obj->ffiCallRets = xn_arr_s_new(4);
  xn_obj->ffiCallSpecs = xn_arr_s_new(4);
  xn_obj->ffiCallErrParams = xn_arr_s_new(4);
  xn_obj->ffiCallErrRets = xn_arr_s_new(4);
  xn_obj->genericMaps = xn_arr_s_new(4);
  xn_obj->genericSets = xn_arr_s_new(4);
  xn_Cls_CGen *self = xn_obj;
  self->program = program;
  self->lines = xn_arr_s_new(0);
  self->vars = xn_arr_s_new(0);
  self->varTypes = xn_arr_s_new(0);
  self->tmp = 0;
  self->err = rt_string_from_c("");
  self->curClass = rt_string_from_c("");
  self->curRet = rt_string_from_c("Int");
  self->curCtxExpr = rt_string_from_c("NULL");
  self->defers = xn_arr_o_new(0);
  self->deferErrs = xn_arr_s_new(0);
  self->breakTargets = xn_arr_s_new(0);
  self->lambdas = xn_arr_o_new(0);
  self->lambdaTypes = xn_arr_s_new(0);
  self->lambdaCaptures = xn_arr_s_new(0);
  self->lambdaCaptureTypes = xn_arr_s_new(0);
  self->lambdaCaptureScanned = xn_arr_s_new(0);
  self->lambdaOwners = xn_arr_s_new(0);
  self->lambdaModes = xn_arr_s_new(0);
  self->ffiCallNames = callNames;
  self->ffiCallCNames = callCNames;
  self->ffiCallRets = callRets;
  self->ffiCallSpecs = callSpecs;
  self->ffiCallErrParams = callErrParams;
  self->ffiCallErrRets = callErrRets;
  self->genericMaps = xn_arr_s_new(0);
  self->genericSets = xn_arr_s_new(0);
  return xn_obj;
}

static int xn_Cls_CGen_hasError(xn_Cls_CGen *self);
static void xn_Cls_CGen_fail(xn_Cls_CGen *self, rt_string * msg);
static void xn_Cls_CGen_emit(xn_Cls_CGen *self, rt_string * line);
static rt_string * xn_Cls_CGen_temp(xn_Cls_CGen *self);
static xn_Cls_AstNode * xn_Cls_CGen_retNode(xn_Cls_CGen *self, xn_Cls_AstNode * fn);
static xn_arr_o * xn_Cls_CGen_paramsOf(xn_Cls_CGen *self, xn_Cls_AstNode * fn);
static int xn_Cls_CGen_isProtocol(xn_Cls_CGen *self, rt_string * name);
static rt_string * xn_Cls_CGen_protoRet(xn_Cls_CGen *self, rt_string * pname, rt_string * mname);
static xn_arr_o * xn_Cls_CGen_protoParams(xn_Cls_CGen *self, rt_string * pname, rt_string * mname);
static rt_string * xn_Cls_CGen_ctype(xn_Cls_CGen *self, rt_string * ty);
static int xn_Cls_CGen_isGenericResult(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_resultInitField(xn_Cls_CGen *self, rt_string * ty, rt_string * val);
static rt_string * xn_Cls_CGen_resultValueExpr(xn_Cls_CGen *self, rt_string * ty, rt_string * bv);
static int xn_Cls_CGen_isResult(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_resultValue(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_resultError(xn_Cls_CGen *self, rt_string * ty);
static int xn_Cls_CGen_isArray(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_elementType(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_curFieldType(xn_Cls_CGen *self, rt_string * fname);
static rt_string * xn_Cls_CGen_topFieldType(xn_Cls_CGen *self, rt_string * fname);
static rt_string * xn_Cls_CGen_pathType(xn_Cls_CGen *self, rt_string * path);
static rt_string * xn_Cls_CGen_pathExpr(xn_Cls_CGen *self, rt_string * path);
static rt_string * xn_Cls_CGen_arrayCName(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_arrayNew(xn_Cls_CGen *self, rt_string * ty, int64_t cap);
static rt_string * xn_Cls_CGen_arrayPush(xn_Cls_CGen *self, rt_string * ty, rt_string * arr, rt_string * val);
static rt_string * xn_Cls_CGen_arrayGet(xn_Cls_CGen *self, rt_string * ty, rt_string * arr, rt_string * idx);
static rt_string * xn_Cls_CGen_nameExpr(xn_Cls_CGen *self, rt_string * name);
static rt_string * xn_Cls_CGen_resultValueCExpr(xn_Cls_CGen *self, rt_string * ty, rt_string * bv);
static int xn_Cls_CGen_isGcRefType(xn_Cls_CGen *self, rt_string * ty);
static int xn_Cls_CGen_isMap(xn_Cls_CGen *self, rt_string * ty);
static int xn_Cls_CGen_isSet(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_mapValue(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_mapKey(xn_Cls_CGen *self, rt_string * ty);
static int xn_Cls_CGen_isGenericMap(xn_Cls_CGen *self, rt_string * ty);
static int xn_Cls_CGen_isGenericSet(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_setElementOf(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_cMangle(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_genericMapSuffix(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_genericMapKeysName(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_genericMapValuesName(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_genericMapEntriesName(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_entryClassName(xn_Cls_CGen *self, rt_string * keyTy, rt_string * valTy);
static int xn_Cls_CGen_containsGeneric(xn_Cls_CGen *self, xn_arr_s * xs, rt_string * v);
static void xn_Cls_CGen_registerGenericMap(xn_Cls_CGen *self, rt_string * ty);
static void xn_Cls_CGen_registerGenericSet(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_baseType(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_kindOf(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_encodeOf(xn_Cls_CGen *self, rt_string * ty, rt_string * expr);
static rt_string * xn_Cls_CGen_decodeOf(xn_Cls_CGen *self, rt_string * ty, rt_string * expr);
static rt_string * xn_Cls_CGen_readTypeAt(xn_Cls_CGen *self, rt_string * text, int64_t start);
static void xn_Cls_CGen_scanGenericTypeText(xn_Cls_CGen *self, rt_string * text);
static void xn_Cls_CGen_collectGenericTypes(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static int xn_Cls_CGen_isFunctionType(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_fnRetType(xn_Cls_CGen *self, rt_string * ty);
static xn_arr_s * xn_Cls_CGen_fnParams(xn_Cls_CGen *self, rt_string * ty);
static int64_t xn_Cls_CGen_lambdaIndex(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static xn_Cls_AstNode * xn_Cls_CGen_findFunctionNode(xn_Cls_CGen *self, rt_string * name);
static rt_string * xn_Cls_CGen_callParamType(xn_Cls_CGen *self, rt_string * name, int64_t argIndex);
static rt_string * xn_Cls_CGen_ctorParamType(xn_Cls_CGen *self, rt_string * cls, int64_t argIndex);
static void xn_Cls_CGen_registerLambda(xn_Cls_CGen *self, xn_Cls_AstNode * lam, rt_string * ty);
static void xn_Cls_CGen_collectReturnLambdas(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * retTy);
static rt_string * xn_Cls_CGen_syntacticType(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_CGen_spawnReturnType(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_CGen_spawnLambdaType(xn_Cls_CGen *self, xn_Cls_AstNode * lam);
static rt_string * xn_Cls_CGen_lambdaFirstParamType(xn_Cls_CGen *self, xn_Cls_AstNode * lam);
static int xn_Cls_CGen_lambdaHasParams(xn_Cls_CGen *self, xn_Cls_AstNode * lam);
static void xn_Cls_CGen_setLambdaMode(xn_Cls_CGen *self, xn_Cls_AstNode * lam, rt_string * mode);
static void xn_Cls_CGen_collectLambdas(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * expected);
static xn_arr_s * xn_Cls_CGen_splitCaps(xn_Cls_CGen *self, rt_string * s);
static rt_string * xn_Cls_CGen_joinCaps(xn_Cls_CGen *self, xn_arr_s * xs);
static int xn_Cls_CGen_listHas(xn_Cls_CGen *self, xn_arr_s * xs, rt_string * v);
static void xn_Cls_CGen_collectShadows(xn_Cls_CGen *self, xn_Cls_AstNode * n, xn_arr_s * out);
static int xn_Cls_CGen_containsVarUse(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * name);
static void xn_Cls_CGen_ensureLambdaCaptures(xn_Cls_CGen *self, int64_t li, xn_Cls_AstNode * lam);
static rt_string * xn_Cls_CGen_lambdaName(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_CGen_fnPtrDecl(xn_Cls_CGen *self, rt_string * ty, rt_string * name);
static int xn_Cls_CGen_ffiSpecial(xn_Cls_CGen *self, rt_string * name);
static int xn_Cls_CGen_ffiHardProto(xn_Cls_CGen *self, rt_string * cname);
static int xn_Cls_CGen_ffiTypeOk(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_ffiMiniType(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_ffiAbiType(xn_Cls_CGen *self, rt_string * ty);
static int64_t xn_Cls_CGen_ffiParamCount(xn_Cls_CGen *self, int64_t idx);
static rt_string * xn_Cls_CGen_ffiParamType(xn_Cls_CGen *self, int64_t idx, int64_t p);
static rt_string * xn_Cls_CGen_ffiParamName(xn_Cls_CGen *self, int64_t idx, int64_t p);
static rt_string * xn_Cls_CGen_ffiErrParam(xn_Cls_CGen *self, int64_t idx);
static int64_t xn_Cls_CGen_ffiErrParamIndex(xn_Cls_CGen *self, int64_t idx);
static int xn_Cls_CGen_ffiEntryOk(xn_Cls_CGen *self, int64_t idx);
static rt_string * xn_Cls_CGen_ffiAbiProto(xn_Cls_CGen *self, int64_t idx);
static rt_string * xn_Cls_CGen_ffiWrapperSig(xn_Cls_CGen *self, int64_t idx);
static rt_string * xn_Cls_CGen_ffiWrapperArgs(xn_Cls_CGen *self, int64_t idx);
static rt_string * xn_Cls_CGen_ffiWrapperDef(xn_Cls_CGen *self, int64_t idx);
static void xn_Cls_CGen_emitFfiDecls(xn_Cls_CGen *self);
static rt_string * xn_Cls_CGen_closureCast(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_closureCall(xn_Cls_CGen *self, rt_string * ty, rt_string * target, xn_Cls_AstNode * call);
static rt_string * xn_Cls_CGen_lambdaProto(xn_Cls_CGen *self, int64_t i);
static rt_string * xn_Cls_CGen_lockAdapterProto(xn_Cls_CGen *self, int64_t i);
static rt_string * xn_Cls_CGen_lambdaMode(xn_Cls_CGen *self, int64_t i);
static rt_string * xn_Cls_CGen_taskAdapterProto(xn_Cls_CGen *self, int64_t i);
static void xn_Cls_CGen_emitLockAdapter(xn_Cls_CGen *self, int64_t i);
static void xn_Cls_CGen_emitTaskAdapter(xn_Cls_CGen *self, int64_t i);
static void xn_Cls_CGen_emitLambdaDef(xn_Cls_CGen *self, int64_t i);
static int xn_Cls_CGen_isEnumName(xn_Cls_CGen *self, rt_string * name);
static int64_t xn_Cls_CGen_enumValue(xn_Cls_CGen *self, rt_string * name, rt_string * item);
static xn_arr_s * xn_Cls_CGen_enumItems(xn_Cls_CGen *self, rt_string * name);
static rt_string * xn_Cls_CGen_enumCaseItem(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * enumName);
static int xn_Cls_CGen_isClass(xn_Cls_CGen *self, rt_string * name);
static int xn_Cls_CGen_isDataEnum(xn_Cls_CGen *self, rt_string * name);
static xn_Cls_AstNode * xn_Cls_CGen_classNode(xn_Cls_CGen *self, rt_string * name);
static rt_string * xn_Cls_CGen_fieldType(xn_Cls_CGen *self, rt_string * cls, rt_string * fname);
static int xn_Cls_CGen_isStaticMethod(xn_Cls_CGen *self, rt_string * cls, rt_string * mname);
static rt_string * xn_Cls_CGen_methodRet(xn_Cls_CGen *self, rt_string * cls, rt_string * mname);
static int64_t xn_Cls_CGen_varIndex(xn_Cls_CGen *self, rt_string * name);
static rt_string * xn_Cls_CGen_findVar(xn_Cls_CGen *self, rt_string * name);
static void xn_Cls_CGen_addVar(xn_Cls_CGen *self, rt_string * ty, rt_string * name);
static void xn_Cls_CGen_popTo(xn_Cls_CGen *self, int64_t mark);
static rt_string * xn_Cls_CGen_methodType(xn_Cls_CGen *self, rt_string * bt, rt_string * mth, xn_Cls_AstNode * n);
static rt_string * xn_Cls_CGen_mapMethodExpr(xn_Cls_CGen *self, rt_string * bv, rt_string * bt, rt_string * mth, xn_Cls_AstNode * n, int64_t off, int useOff);
static rt_string * xn_Cls_CGen_setMethodExpr(xn_Cls_CGen *self, rt_string * bv, rt_string * bt, rt_string * mth, xn_Cls_AstNode * n, int64_t off, int useOff);
static rt_string * xn_Cls_CGen_methodExpr(xn_Cls_CGen *self, rt_string * bv, rt_string * bt, rt_string * mth, xn_Cls_AstNode * n, int64_t off);
static rt_string * xn_Cls_CGen_fnRet(xn_Cls_CGen *self, rt_string * name);
static rt_string * xn_Cls_CGen_typeOf(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static int xn_Cls_CGen_intLiteralFits64(xn_Cls_CGen *self, rt_string * text);
static int xn_Cls_CGen_intLiteralFits32(xn_Cls_CGen *self, rt_string * text);
static rt_string * xn_Cls_CGen_expr(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static void xn_Cls_CGen_local(xn_Cls_CGen *self, xn_Cls_AstNode * st, rt_string * indent);
static void xn_Cls_CGen_stmt(xn_Cls_CGen *self, xn_Cls_AstNode * st, rt_string * indent);
static void xn_Cls_CGen_emitDefers(xn_Cls_CGen *self, rt_string * indent, int includeErr);
static void xn_Cls_CGen_blockBody(xn_Cls_CGen *self, xn_Cls_AstNode * block, rt_string * indent);
static int xn_Cls_CGen_methodStatic(xn_Cls_CGen *self, xn_Cls_AstNode * m);
static rt_string * xn_Cls_CGen_methodSig(xn_Cls_CGen *self, xn_Cls_AstNode * m, rt_string * cls);
static void xn_Cls_CGen_method(xn_Cls_CGen *self, xn_Cls_AstNode * m, rt_string * cls);
static xn_Cls_AstNode * xn_Cls_CGen_ctorOf(xn_Cls_CGen *self, xn_Cls_AstNode * cls);
static void xn_Cls_CGen_genClass(xn_Cls_CGen *self, xn_Cls_AstNode * cls);
static rt_string * xn_Cls_CGen_funcProto(xn_Cls_CGen *self, xn_Cls_AstNode * fn);
static void xn_Cls_CGen_func(xn_Cls_CGen *self, xn_Cls_AstNode * fn);
static void xn_Cls_CGen_gen(xn_Cls_CGen *self);
static rt_string * xn_Cls_CGen_text(xn_Cls_CGen *self);

static int xn_Cls_CGen_hasError(xn_Cls_CGen *self) {
  return (!xn_str_eq(self->err, rt_string_from_c("")));
}

static void xn_Cls_CGen_fail(xn_Cls_CGen *self, rt_string * msg) {
  if (xn_str_eq(self->err, rt_string_from_c(""))) {
    self->err = msg;
  }
}

static void xn_Cls_CGen_emit(xn_Cls_CGen *self, rt_string * line) {
  xn_arr_s_push(self->lines, line);
}

static rt_string * xn_Cls_CGen_temp(xn_Cls_CGen *self) {
  self->tmp = xn_int_wrap((self->tmp + 1));
  return xn_concat(rt_string_from_c("xn_t"), xn_str_int(self->tmp));
}

static xn_Cls_AstNode * xn_Cls_CGen_retNode(xn_Cls_CGen *self, xn_Cls_AstNode * fn) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fn->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Ret"))) {
      return k;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("Ret"), rt_string_from_c("Unit"), fn->line, fn->col);
}

static xn_arr_o * xn_Cls_CGen_paramsOf(xn_Cls_CGen *self, xn_Cls_AstNode * fn) {
  xn_arr_o *ps = xn_arr_o_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fn->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Param"))) {
      xn_arr_o_push(ps, k);
    }
    i = xn_int_wrap((i + 1));
  }
  return ps;
}

static int xn_Cls_CGen_isProtocol(xn_Cls_CGen *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Protocol")) && xn_str_eq(n->text, name))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static rt_string * xn_Cls_CGen_protoRet(xn_Cls_CGen *self, rt_string * pname, rt_string * mname) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(p->kind, rt_string_from_c("Protocol")) && xn_str_eq(p->text, pname))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)p->kids->len))) {
        xn_Cls_AstNode * sig = ((xn_Cls_AstNode *)xn_arr_o_get(p->kids, j));
        if ((xn_str_eq(sig->kind, rt_string_from_c("Sig")) && xn_str_eq(sig->text, mname))) {
          int64_t k = xn_int_wrap(0);
          while ((k < ((int64_t)sig->kids->len))) {
            if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(sig->kids, k))->kind, rt_string_from_c("Ret"))) {
              return ((xn_Cls_AstNode *)xn_arr_o_get(sig->kids, k))->text;
            }
            k = xn_int_wrap((k + 1));
          }
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Unit");
}

static xn_arr_o * xn_Cls_CGen_protoParams(xn_Cls_CGen *self, rt_string * pname, rt_string * mname) {
  xn_arr_o *res = xn_arr_o_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(p->kind, rt_string_from_c("Protocol")) && xn_str_eq(p->text, pname))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)p->kids->len))) {
        xn_Cls_AstNode * sig = ((xn_Cls_AstNode *)xn_arr_o_get(p->kids, j));
        if ((xn_str_eq(sig->kind, rt_string_from_c("Sig")) && xn_str_eq(sig->text, mname))) {
          int64_t k = xn_int_wrap(0);
          while ((k < ((int64_t)sig->kids->len))) {
            if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(sig->kids, k))->kind, rt_string_from_c("Param"))) {
              xn_arr_o_push(res, ((xn_Cls_AstNode *)xn_arr_o_get(sig->kids, k)));
            }
            k = xn_int_wrap((k + 1));
          }
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static rt_string * xn_Cls_CGen_ctype(xn_Cls_CGen *self, rt_string * ty) {
  if (((((int64_t)ty->len) > 1) && xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 1)), 1), rt_string_from_c("?")))) {
    return xn_Cls_CGen_ctype(self, xn_str_substr(ty, 0, xn_int_wrap((((int64_t)ty->len) - 1))));
  }
  if (xn_str_eq(ty, rt_string_from_c("Int"))) {
    return rt_string_from_c("int64_t");
  }
  if (xn_str_eq(ty, rt_string_from_c("String"))) {
    return rt_string_from_c("rt_string *");
  }
  if (xn_str_eq(ty, rt_string_from_c("Bytes"))) {
    return rt_string_from_c("xrt_bytes_obj *");
  }
  if (xn_str_eq(ty, rt_string_from_c("AtomicInt"))) {
    return rt_string_from_c("xrt_atomic_int *");
  }
  if (xn_str_eq(ty, rt_string_from_c("AtomicBool"))) {
    return rt_string_from_c("xrt_atomic_bool *");
  }
  if ((xn_str_eq(ty, rt_string_from_c("AtomicRef")) || (xn_str_indexof(ty, rt_string_from_c("AtomicRef<")) == 0))) {
    return rt_string_from_c("xrt_atomic_ref *");
  }
  if ((xn_str_eq(ty, rt_string_from_c("Channel")) || (xn_str_indexof(ty, rt_string_from_c("Channel<")) == 0))) {
    return rt_string_from_c("xrt_channel *");
  }
  if ((xn_str_eq(ty, rt_string_from_c("Mutex")) || (xn_str_indexof(ty, rt_string_from_c("Mutex<")) == 0))) {
    return rt_string_from_c("xrt_mutex *");
  }
  if ((xn_str_eq(ty, rt_string_from_c("Task")) || (xn_str_indexof(ty, rt_string_from_c("Task<")) == 0))) {
    return rt_string_from_c("xrt_task *");
  }
  if (xn_str_eq(ty, rt_string_from_c("TaskGroup"))) {
    return rt_string_from_c("xrt_task_group *");
  }
  if (xn_str_eq(ty, rt_string_from_c("Context"))) {
    return rt_string_from_c("xrt_context *");
  }
  if ((xn_str_eq(ty, rt_string_from_c("TaskError")) || xn_str_eq(ty, rt_string_from_c("CancelledError")))) {
    return rt_string_from_c("int64_t");
  }
  if (xn_str_eq(ty, rt_string_from_c("Bool"))) {
    return rt_string_from_c("int");
  }
  if (xn_str_eq(ty, rt_string_from_c("Char"))) {
    return rt_string_from_c("int32_t");
  }
  if (xn_str_eq(ty, rt_string_from_c("Double"))) {
    return rt_string_from_c("double");
  }
  if (((xn_str_eq(ty, rt_string_from_c("Long")) || xn_str_eq(ty, rt_string_from_c("Int64"))) || xn_str_eq(ty, rt_string_from_c("Int32")))) {
    return rt_string_from_c("int64_t");
  }
  if (xn_str_eq(ty, rt_string_from_c("Int128"))) {
    return rt_string_from_c("__int128");
  }
  if (((xn_str_eq(ty, rt_string_from_c("Void")) || xn_str_eq(ty, rt_string_from_c("void"))) || xn_str_eq(ty, rt_string_from_c("Unit")))) {
    return rt_string_from_c("void");
  }
  if (xn_str_eq(ty, rt_string_from_c("UInt16"))) {
    return rt_string_from_c("int64_t");
  }
  if (xn_Cls_CGen_isFunctionType(self, ty)) {
    return rt_string_from_c("xn_closure");
  }
  if ((xn_Cls_CGen_isArray(self, ty) || xn_str_eq(ty, rt_string_from_c("List<Int>")))) {
    return xn_concat(xn_Cls_CGen_arrayCName(self, ty), rt_string_from_c(" *"));
  }
  if (xn_str_eq(ty, rt_string_from_c("Map<String,Int>"))) {
    return rt_string_from_c("xn_map_s_i *");
  }
  if (xn_str_eq(ty, rt_string_from_c("Map<Int,Int>"))) {
    return rt_string_from_c("xn_map_i_i *");
  }
  if (xn_Cls_CGen_isMap(self, ty)) {
    return rt_string_from_c("xn_map_g *");
  }
  if (xn_str_eq(ty, rt_string_from_c("Set<String>"))) {
    return rt_string_from_c("xn_set_s *");
  }
  if (xn_Cls_CGen_isSet(self, ty)) {
    return rt_string_from_c("xn_set_g *");
  }
  if (xn_str_eq(ty, rt_string_from_c("Result<Int,String>"))) {
    return rt_string_from_c("xn_Result_Int_String");
  }
  if (xn_Cls_CGen_isResult(self, ty)) {
    return rt_string_from_c("xn_Result");
  }
  if (xn_Cls_CGen_isClass(self, ty)) {
    return xn_concat(xn_concat(rt_string_from_c("xn_Cls_"), ty), rt_string_from_c(" *"));
  }
  if (xn_Cls_CGen_isDataEnum(self, ty)) {
    return xn_concat(xn_concat(rt_string_from_c("xn_Cls_"), ty), rt_string_from_c(" *"));
  }
  if (xn_Cls_CGen_isEnumName(self, ty)) {
    return rt_string_from_c("int64_t");
  }
  if (xn_Cls_CGen_isProtocol(self, ty)) {
    return rt_string_from_c("void *");
  }
  xn_Cls_CGen_fail(self, xn_concat(rt_string_from_c("unsupported type: "), ty));
  return rt_string_from_c("int64_t");
}

static int xn_Cls_CGen_isGenericResult(xn_Cls_CGen *self, rt_string * ty) {
  return (xn_Cls_CGen_isResult(self, ty) && (!xn_str_eq(ty, rt_string_from_c("Result<Int,String>"))));
}

static rt_string * xn_Cls_CGen_resultInitField(xn_Cls_CGen *self, rt_string * ty, rt_string * val) {
  rt_string * vt = xn_Cls_CGen_resultValue(self, ty);
  if ((((((xn_str_eq(vt, rt_string_from_c("Int")) || xn_str_eq(vt, rt_string_from_c("Int32"))) || xn_str_eq(vt, rt_string_from_c("Int64"))) || xn_str_eq(vt, rt_string_from_c("Long"))) || xn_str_eq(vt, rt_string_from_c("Bool"))) || xn_str_eq(vt, rt_string_from_c("Char")))) {
    return xn_concat(xn_concat(rt_string_from_c(".i = (int64_t)("), val), rt_string_from_c(")"));
  }
  if (xn_str_eq(vt, rt_string_from_c("Double"))) {
    return xn_concat(xn_concat(rt_string_from_c(".d = (double)("), val), rt_string_from_c(")"));
  }
  if (xn_str_eq(vt, rt_string_from_c("Int128"))) {
    return xn_concat(xn_concat(rt_string_from_c(".q = (__int128)("), val), rt_string_from_c(")"));
  }
  if (xn_str_eq(vt, rt_string_from_c("String"))) {
    return xn_concat(xn_concat(rt_string_from_c(".s = (rt_string *)("), val), rt_string_from_c(")"));
  }
  if (xn_str_startswith(vt, rt_string_from_c("Result<"))) {
    return xn_concat(xn_concat(rt_string_from_c(".p = xn_box_result("), val), rt_string_from_c(")"));
  }
  return xn_concat(xn_concat(rt_string_from_c(".p = (void *)("), val), rt_string_from_c(")"));
}

static rt_string * xn_Cls_CGen_resultValueExpr(xn_Cls_CGen *self, rt_string * ty, rt_string * bv) {
  rt_string * vt = xn_Cls_CGen_resultValue(self, ty);
  if ((((((xn_str_eq(vt, rt_string_from_c("Int")) || xn_str_eq(vt, rt_string_from_c("Int32"))) || xn_str_eq(vt, rt_string_from_c("Int64"))) || xn_str_eq(vt, rt_string_from_c("Long"))) || xn_str_eq(vt, rt_string_from_c("Bool"))) || xn_str_eq(vt, rt_string_from_c("Char")))) {
    return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c(").i"));
  }
  if (xn_str_eq(vt, rt_string_from_c("Double"))) {
    return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c(").d"));
  }
  if (xn_str_eq(vt, rt_string_from_c("Int128"))) {
    return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c(").q"));
  }
  if (xn_str_eq(vt, rt_string_from_c("String"))) {
    return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c(").s"));
  }
  if (xn_str_eq(vt, rt_string_from_c("Result<Int,String>"))) {
    return xn_concat(xn_concat(rt_string_from_c("(*(xn_Result_Int_String *)("), bv), rt_string_from_c(").p)"));
  }
  if (xn_str_startswith(vt, rt_string_from_c("Result<"))) {
    return xn_concat(xn_concat(rt_string_from_c("(*(xn_Result *)("), bv), rt_string_from_c(").p)"));
  }
  return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c(").p"));
}

static int xn_Cls_CGen_isResult(xn_Cls_CGen *self, rt_string * ty) {
  return ((((int64_t)ty->len) > 8) && xn_str_eq(xn_str_substr(ty, 0, 7), rt_string_from_c("Result<")));
}

static rt_string * xn_Cls_CGen_resultValue(xn_Cls_CGen *self, rt_string * ty) {
  rt_string * inner = xn_str_substr(ty, 7, xn_int_wrap((((int64_t)ty->len) - 8)));
  xn_arr_s * parts = xn_splitTop(inner);
  if ((((int64_t)parts->len) >= 1)) {
    return xn_str_trim(xn_arr_s_get(parts, 0));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_CGen_resultError(xn_Cls_CGen *self, rt_string * ty) {
  rt_string * inner = xn_str_substr(ty, 7, xn_int_wrap((((int64_t)ty->len) - 8)));
  xn_arr_s * parts = xn_splitTop(inner);
  if ((((int64_t)parts->len) >= 2)) {
    return xn_str_trim(xn_arr_s_get(parts, 1));
  }
  return rt_string_from_c("Any");
}

static int xn_Cls_CGen_isArray(xn_Cls_CGen *self, rt_string * ty) {
  return (((((int64_t)ty->len) >= 2) && xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 2)), 2), rt_string_from_c("[]"))) || ((((int64_t)ty->len) > 6) && xn_str_eq(xn_str_substr(ty, 0, 5), rt_string_from_c("List<"))));
}

static rt_string * xn_Cls_CGen_elementType(xn_Cls_CGen *self, rt_string * ty) {
  if (((((int64_t)ty->len) >= 2) && xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 2)), 2), rt_string_from_c("[]")))) {
    return xn_str_substr(ty, 0, xn_int_wrap((((int64_t)ty->len) - 2)));
  }
  if (((((int64_t)ty->len) > 6) && xn_str_eq(xn_str_substr(ty, 0, 5), rt_string_from_c("List<")))) {
    return xn_str_substr(ty, 5, xn_int_wrap((((int64_t)ty->len) - 6)));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_CGen_curFieldType(xn_Cls_CGen *self, rt_string * fname) {
  if (xn_str_eq(self->curClass, rt_string_from_c(""))) {
    return rt_string_from_c("Any");
  }
  return xn_Cls_CGen_fieldType(self, self->curClass, fname);
}

static rt_string * xn_Cls_CGen_topFieldType(xn_Cls_CGen *self, rt_string * fname) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("TopField"))) {
      xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
      if (((((int64_t)parts->len) >= 2) && xn_str_eq(xn_arr_s_get(parts, 1), fname))) {
        return xn_arr_s_get(parts, 0);
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_CGen_pathType(xn_Cls_CGen *self, rt_string * path) {
  int64_t dot = xn_int_wrap(xn_str_indexof(path, rt_string_from_c(".")));
  if ((dot < 0)) {
    if (xn_str_eq(path, rt_string_from_c("self"))) {
      return self->curClass;
    }
    if (xn_str_eq(path, rt_string_from_c("Bytes"))) {
      return rt_string_from_c("Bytes");
    }
    if (xn_Cls_CGen_isClass(self, path)) {
      return path;
    }
    rt_string * vt = xn_Cls_CGen_findVar(self, path);
    if ((!xn_str_eq(vt, rt_string_from_c("Any")))) {
      return vt;
    }
    rt_string * ft = xn_Cls_CGen_curFieldType(self, path);
    if ((!xn_str_eq(ft, rt_string_from_c("Any")))) {
      return ft;
    }
    return xn_Cls_CGen_topFieldType(self, path);
  }
  rt_string * head = xn_str_substr(path, 0, dot);
  rt_string * rest = xn_str_substr(path, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)path->len) - dot)) - 1)));
  rt_string * bt = xn_Cls_CGen_pathType(self, head);
  while (((!xn_str_eq(bt, rt_string_from_c("Any"))) && (((int64_t)rest->len) > 0))) {
    int64_t d = xn_int_wrap(xn_str_indexof(rest, rt_string_from_c(".")));
    rt_string * seg = rest;
    if ((d >= 0)) {
      seg = xn_str_substr(rest, 0, d);
      rest = xn_str_substr(rest, xn_int_wrap((d + 1)), xn_int_wrap((xn_int_wrap((((int64_t)rest->len) - d)) - 1)));
    }
    else {
      rest = rt_string_from_c("");
    }
    bt = xn_Cls_CGen_fieldType(self, bt, seg);
  }
  return bt;
}

static rt_string * xn_Cls_CGen_pathExpr(xn_Cls_CGen *self, rt_string * path) {
  int64_t dot = xn_int_wrap(xn_str_indexof(path, rt_string_from_c(".")));
  if ((dot < 0)) {
    return xn_Cls_CGen_nameExpr(self, path);
  }
  rt_string * b = xn_Cls_CGen_nameExpr(self, xn_str_substr(path, 0, dot));
  rt_string * rest = xn_str_substr(path, 0, dot);
  rest = xn_str_substr(path, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)path->len) - dot)) - 1)));
  while ((((int64_t)rest->len) > 0)) {
    int64_t d = xn_int_wrap(xn_str_indexof(rest, rt_string_from_c(".")));
    rt_string * seg = rest;
    if ((d >= 0)) {
      seg = xn_str_substr(rest, 0, d);
      rest = xn_str_substr(rest, xn_int_wrap((d + 1)), xn_int_wrap((xn_int_wrap((((int64_t)rest->len) - d)) - 1)));
    }
    else {
      rest = rt_string_from_c("");
    }
    b = xn_concat(xn_concat(b, rt_string_from_c("->")), seg);
  }
  return b;
}

static rt_string * xn_Cls_CGen_arrayCName(xn_Cls_CGen *self, rt_string * ty) {
  rt_string * et = xn_Cls_CGen_elementType(self, ty);
  if (((((((xn_str_eq(et, rt_string_from_c("Int")) || xn_str_eq(et, rt_string_from_c("Long"))) || xn_str_eq(et, rt_string_from_c("Int64"))) || xn_str_eq(et, rt_string_from_c("UInt16"))) || xn_str_eq(et, rt_string_from_c("Bool"))) || xn_str_eq(et, rt_string_from_c("Char"))) || (xn_Cls_CGen_isEnumName(self, et) && (!xn_Cls_CGen_isDataEnum(self, et))))) {
    return rt_string_from_c("xn_arr_i");
  }
  if (xn_Cls_CGen_isDataEnum(self, et)) {
    return rt_string_from_c("xn_arr_o");
  }
  if (xn_str_eq(et, rt_string_from_c("Double"))) {
    return rt_string_from_c("xn_arr_d");
  }
  if (xn_str_eq(et, rt_string_from_c("String"))) {
    return rt_string_from_c("xn_arr_s");
  }
  if (xn_Cls_CGen_isResult(self, et)) {
    return rt_string_from_c("xn_arr_r");
  }
  return rt_string_from_c("xn_arr_o");
}

static rt_string * xn_Cls_CGen_arrayNew(xn_Cls_CGen *self, rt_string * ty, int64_t cap) {
  return xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, ty), rt_string_from_c("_new(")), xn_str_int(cap)), rt_string_from_c(")"));
}

static rt_string * xn_Cls_CGen_arrayPush(xn_Cls_CGen *self, rt_string * ty, rt_string * arr, rt_string * val) {
  return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, ty), rt_string_from_c("_push(")), arr), rt_string_from_c(", ")), val), rt_string_from_c(")"));
}

static rt_string * xn_Cls_CGen_arrayGet(xn_Cls_CGen *self, rt_string * ty, rt_string * arr, rt_string * idx) {
  rt_string * ac = xn_Cls_CGen_arrayCName(self, ty);
  rt_string * call = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(ac, rt_string_from_c("_get(")), arr), rt_string_from_c(", ")), idx), rt_string_from_c(")"));
  if (xn_str_eq(ac, rt_string_from_c("xn_arr_o"))) {
    rt_string * elementType = xn_Cls_CGen_elementType(self, ty);
    if (((xn_Cls_CGen_isProtocol(self, elementType) || xn_str_eq(elementType, rt_string_from_c("Any"))) || xn_str_eq(elementType, rt_string_from_c("Object")))) {
      return call;
    }
    if (xn_str_eq(elementType, rt_string_from_c("Bytes"))) {
      return xn_concat(xn_concat(rt_string_from_c("((xrt_bytes_obj *)"), call), rt_string_from_c(")"));
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((xn_Cls_"), elementType), rt_string_from_c(" *)")), call), rt_string_from_c(")"));
  }
  return call;
}

static rt_string * xn_Cls_CGen_nameExpr(xn_Cls_CGen *self, rt_string * name) {
  if (xn_str_eq(name, rt_string_from_c("self"))) {
    return rt_string_from_c("self");
  }
  if (((!xn_str_eq(xn_Cls_CGen_findVar(self, name), rt_string_from_c("Any"))) || (!xn_str_eq(xn_Cls_CGen_topFieldType(self, name), rt_string_from_c("Any"))))) {
    return name;
  }
  if ((!xn_str_eq(xn_Cls_CGen_curFieldType(self, name), rt_string_from_c("Any")))) {
    return xn_concat(rt_string_from_c("self->"), name);
  }
  return name;
}

static rt_string * xn_Cls_CGen_resultValueCExpr(xn_Cls_CGen *self, rt_string * ty, rt_string * bv) {
  rt_string * vt = xn_Cls_CGen_resultValue(self, ty);
  rt_string * base = xn_Cls_CGen_resultValueExpr(self, ty, bv);
  if (((((((xn_Cls_CGen_isArray(self, vt) || xn_Cls_CGen_isMap(self, vt)) || xn_Cls_CGen_isSet(self, vt)) || xn_Cls_CGen_isClass(self, vt)) || xn_Cls_CGen_isDataEnum(self, vt)) || xn_Cls_CGen_isProtocol(self, vt)) || xn_str_eq(vt, rt_string_from_c("Bytes")))) {
    return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), xn_Cls_CGen_ctype(self, vt)), rt_string_from_c(")")), base), rt_string_from_c(")"));
  }
  return base;
}

static int xn_Cls_CGen_isGcRefType(xn_Cls_CGen *self, rt_string * ty) {
  if (((xn_str_eq(ty, rt_string_from_c("String")) || xn_str_eq(ty, rt_string_from_c("Bytes"))) || xn_str_eq(ty, rt_string_from_c("Any")))) {
    return 1;
  }
  if (((xn_Cls_CGen_isArray(self, ty) || xn_Cls_CGen_isMap(self, ty)) || xn_Cls_CGen_isSet(self, ty))) {
    return 1;
  }
  if (((xn_Cls_CGen_isClass(self, ty) || xn_Cls_CGen_isDataEnum(self, ty)) || xn_Cls_CGen_isProtocol(self, ty))) {
    return 1;
  }
  return 0;
}

static int xn_Cls_CGen_isMap(xn_Cls_CGen *self, rt_string * ty) {
  return ((((int64_t)ty->len) > 5) && xn_str_eq(xn_str_substr(ty, 0, 4), rt_string_from_c("Map<")));
}

static int xn_Cls_CGen_isSet(xn_Cls_CGen *self, rt_string * ty) {
  return ((((int64_t)ty->len) > 5) && xn_str_eq(xn_str_substr(ty, 0, 4), rt_string_from_c("Set<")));
}

static rt_string * xn_Cls_CGen_mapValue(xn_Cls_CGen *self, rt_string * ty) {
  rt_string * inner = xn_str_substr(ty, 4, xn_int_wrap((((int64_t)ty->len) - 5)));
  xn_arr_s * parts = xn_splitTop(inner);
  if ((((int64_t)parts->len) >= 2)) {
    return xn_str_trim(xn_arr_s_get(parts, 1));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_CGen_mapKey(xn_Cls_CGen *self, rt_string * ty) {
  rt_string * inner = xn_str_substr(ty, 4, xn_int_wrap((((int64_t)ty->len) - 5)));
  xn_arr_s * parts = xn_splitTop(inner);
  if ((((int64_t)parts->len) >= 1)) {
    return xn_str_trim(xn_arr_s_get(parts, 0));
  }
  return rt_string_from_c("Any");
}

static int xn_Cls_CGen_isGenericMap(xn_Cls_CGen *self, rt_string * ty) {
  return ((xn_Cls_CGen_isMap(self, ty) && (!xn_str_eq(ty, rt_string_from_c("Map<String,Int>")))) && (!xn_str_eq(ty, rt_string_from_c("Map<Int,Int>"))));
}

static int xn_Cls_CGen_isGenericSet(xn_Cls_CGen *self, rt_string * ty) {
  return ((xn_Cls_CGen_isSet(self, ty) && (!xn_str_eq(ty, rt_string_from_c("Set<Int>")))) && (!xn_str_eq(ty, rt_string_from_c("Set<String>"))));
}

static rt_string * xn_Cls_CGen_setElementOf(xn_Cls_CGen *self, rt_string * ty) {
  if (xn_Cls_CGen_isSet(self, ty)) {
    return xn_str_substr(ty, 4, xn_int_wrap((((int64_t)ty->len) - 5)));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_CGen_cMangle(xn_Cls_CGen *self, rt_string * ty) {
  rt_string * res = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ty->len))) {
    rt_string * c = xn_str_substr(ty, i, 1);
    rt_string * alpha = rt_string_from_c("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_");
    if ((xn_str_indexof(alpha, c) >= 0)) {
      res = xn_concat(res, c);
    }
    else {
      res = xn_concat(res, rt_string_from_c("_"));
    }
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static rt_string * xn_Cls_CGen_genericMapSuffix(xn_Cls_CGen *self, rt_string * ty) {
  return xn_Cls_CGen_cMangle(self, ty);
}

static rt_string * xn_Cls_CGen_genericMapKeysName(xn_Cls_CGen *self, rt_string * ty) {
  return xn_concat(xn_concat(rt_string_from_c("xn_map_g_"), xn_Cls_CGen_genericMapSuffix(self, ty)), rt_string_from_c("_keys"));
}

static rt_string * xn_Cls_CGen_genericMapValuesName(xn_Cls_CGen *self, rt_string * ty) {
  return xn_concat(xn_concat(rt_string_from_c("xn_map_g_"), xn_Cls_CGen_genericMapSuffix(self, ty)), rt_string_from_c("_values"));
}

static rt_string * xn_Cls_CGen_genericMapEntriesName(xn_Cls_CGen *self, rt_string * ty) {
  return xn_concat(xn_concat(rt_string_from_c("xn_map_g_"), xn_Cls_CGen_genericMapSuffix(self, ty)), rt_string_from_c("_entries"));
}

static rt_string * xn_Cls_CGen_entryClassName(xn_Cls_CGen *self, rt_string * keyTy, rt_string * valTy) {
  return xn_concat(xn_concat(xn_concat(rt_string_from_c("Entry__"), xn_Cls_CGen_cMangle(self, keyTy)), rt_string_from_c("_")), xn_Cls_CGen_cMangle(self, valTy));
}

static int xn_Cls_CGen_containsGeneric(xn_Cls_CGen *self, xn_arr_s * xs, rt_string * v) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)xs->len))) {
    if (xn_str_eq(xn_arr_s_get(xs, i), v)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_Cls_CGen_registerGenericMap(xn_Cls_CGen *self, rt_string * ty) {
  if ((xn_str_eq(ty, rt_string_from_c("Map<String,Int>")) || xn_str_eq(ty, rt_string_from_c("Map<Int,Int>")))) {
    return;
  }
  if ((!xn_Cls_CGen_containsGeneric(self, self->genericMaps, ty))) {
    xn_arr_s_push(self->genericMaps, ty);
  }
}

static void xn_Cls_CGen_registerGenericSet(xn_Cls_CGen *self, rt_string * ty) {
  if ((!xn_Cls_CGen_containsGeneric(self, self->genericSets, ty))) {
    xn_arr_s_push(self->genericSets, ty);
  }
}

static rt_string * xn_Cls_CGen_baseType(xn_Cls_CGen *self, rt_string * ty) {
  if (((((int64_t)ty->len) > 1) && xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 1)), 1), rt_string_from_c("?")))) {
    return xn_str_substr(ty, 0, xn_int_wrap((((int64_t)ty->len) - 1)));
  }
  return ty;
}

static rt_string * xn_Cls_CGen_kindOf(xn_Cls_CGen *self, rt_string * ty) {
  rt_string * b = xn_Cls_CGen_baseType(self, ty);
  if (((((((xn_str_eq(b, rt_string_from_c("Int")) || xn_str_eq(b, rt_string_from_c("Long"))) || xn_str_eq(b, rt_string_from_c("Int64"))) || xn_str_eq(b, rt_string_from_c("Int32"))) || xn_str_eq(b, rt_string_from_c("UInt16"))) || xn_str_eq(b, rt_string_from_c("Bool"))) || xn_str_eq(b, rt_string_from_c("Char")))) {
    return rt_string_from_c("0");
  }
  if (xn_str_eq(b, rt_string_from_c("String"))) {
    return rt_string_from_c("1");
  }
  if (xn_str_eq(b, rt_string_from_c("Double"))) {
    return rt_string_from_c("2");
  }
  if (((xn_Cls_CGen_isArray(self, b) || xn_Cls_CGen_isMap(self, b)) || xn_Cls_CGen_isSet(self, b))) {
    return rt_string_from_c("3");
  }
  if ((((xn_str_eq(b, rt_string_from_c("Bytes")) || xn_Cls_CGen_isClass(self, b)) || xn_Cls_CGen_isProtocol(self, b)) || xn_Cls_CGen_isDataEnum(self, b))) {
    return rt_string_from_c("3");
  }
  if (xn_Cls_CGen_isEnumName(self, b)) {
    return rt_string_from_c("0");
  }
  return rt_string_from_c("-1");
}

static rt_string * xn_Cls_CGen_encodeOf(xn_Cls_CGen *self, rt_string * ty, rt_string * expr) {
  rt_string * k = xn_Cls_CGen_kindOf(self, ty);
  if (xn_str_eq(k, rt_string_from_c("0"))) {
    return xn_concat(xn_concat(rt_string_from_c("(void *)(intptr_t)("), expr), rt_string_from_c(")"));
  }
  if ((xn_str_eq(k, rt_string_from_c("1")) || xn_str_eq(k, rt_string_from_c("3")))) {
    return xn_concat(xn_concat(rt_string_from_c("(void *)("), expr), rt_string_from_c(")"));
  }
  if (xn_str_eq(k, rt_string_from_c("2"))) {
    return xn_concat(xn_concat(rt_string_from_c("xn_double_to_ptr("), expr), rt_string_from_c(")"));
  }
  return rt_string_from_c("0");
}

static rt_string * xn_Cls_CGen_decodeOf(xn_Cls_CGen *self, rt_string * ty, rt_string * expr) {
  rt_string * b = xn_Cls_CGen_baseType(self, ty);
  rt_string * k = xn_Cls_CGen_kindOf(self, ty);
  if (xn_str_eq(k, rt_string_from_c("0"))) {
    return xn_concat(xn_concat(rt_string_from_c("((int64_t)(intptr_t)("), expr), rt_string_from_c("))"));
  }
  if (xn_str_eq(k, rt_string_from_c("1"))) {
    return xn_concat(xn_concat(rt_string_from_c("((rt_string *)("), expr), rt_string_from_c("))"));
  }
  if (xn_str_eq(k, rt_string_from_c("2"))) {
    return xn_concat(xn_concat(rt_string_from_c("xn_ptr_to_double("), expr), rt_string_from_c(")"));
  }
  if (xn_str_eq(k, rt_string_from_c("3"))) {
    return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), xn_Cls_CGen_ctype(self, b)), rt_string_from_c(")(")), expr), rt_string_from_c("))"));
  }
  return rt_string_from_c("0");
}

static rt_string * xn_Cls_CGen_readTypeAt(xn_Cls_CGen *self, rt_string * text, int64_t start) {
  int64_t depth = xn_int_wrap(0);
  int64_t i = xn_int_wrap(start);
  while ((i < ((int64_t)text->len))) {
    rt_string * c = xn_str_substr(text, i, 1);
    if (xn_str_eq(c, rt_string_from_c("<"))) {
      depth = xn_int_wrap((depth + 1));
    }
    else {
      if (xn_str_eq(c, rt_string_from_c(">"))) {
        depth = xn_int_wrap((depth - 1));
        if ((depth == 0)) {
          return xn_str_substr(text, start, xn_int_wrap((xn_int_wrap((i - start)) + 1)));
        }
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("");
}

static void xn_Cls_CGen_scanGenericTypeText(xn_Cls_CGen *self, rt_string * text) {
  int64_t m = xn_int_wrap(xn_str_indexof(text, rt_string_from_c("Map<")));
  if ((m >= 0)) {
    rt_string * ty = xn_Cls_CGen_readTypeAt(self, text, m);
    if ((!xn_str_eq(ty, rt_string_from_c("")))) {
      xn_Cls_CGen_registerGenericMap(self, ty);
    }
  }
  int64_t st = xn_int_wrap(xn_str_indexof(text, rt_string_from_c("Set<")));
  if ((st >= 0)) {
    rt_string * ty = xn_Cls_CGen_readTypeAt(self, text, st);
    if ((!xn_str_eq(ty, rt_string_from_c("")))) {
      xn_Cls_CGen_registerGenericSet(self, ty);
    }
  }
}

static void xn_Cls_CGen_collectGenericTypes(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if ((((xn_str_eq(n->kind, rt_string_from_c("Func")) || xn_str_eq(n->kind, rt_string_from_c("Class"))) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && xn_hasTypeParams(n))) {
    return;
  }
  if (((((((((xn_str_eq(n->kind, rt_string_from_c("Local")) || xn_str_eq(n->kind, rt_string_from_c("Param"))) || xn_str_eq(n->kind, rt_string_from_c("Ret"))) || xn_str_eq(n->kind, rt_string_from_c("Field"))) || xn_str_eq(n->kind, rt_string_from_c("New"))) || xn_str_eq(n->kind, rt_string_from_c("Cast"))) || xn_str_eq(n->kind, rt_string_from_c("TypeArgs"))) || xn_str_eq(n->kind, rt_string_from_c("Base"))) || xn_str_eq(n->kind, rt_string_from_c("Implements")))) {
    xn_Cls_CGen_scanGenericTypeText(self, n->text);
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_CGen_collectGenericTypes(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)));
    i = xn_int_wrap((i + 1));
  }
}

static int xn_Cls_CGen_isFunctionType(xn_Cls_CGen *self, rt_string * ty) {
  int64_t p = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("(")));
  return (((p > 0) && (((int64_t)ty->len) > xn_int_wrap((p + 1)))) && xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 1)), 1), rt_string_from_c(")")));
}

static rt_string * xn_Cls_CGen_fnRetType(xn_Cls_CGen *self, rt_string * ty) {
  int64_t p = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("(")));
  if ((p > 0)) {
    return xn_str_substr(ty, 0, p);
  }
  return rt_string_from_c("Any");
}

static xn_arr_s * xn_Cls_CGen_fnParams(xn_Cls_CGen *self, rt_string * ty) {
  xn_arr_s *res = xn_arr_s_new(0);
  int64_t p = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("(")));
  if (((p <= 0) || (!xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 1)), 1), rt_string_from_c(")"))))) {
    return res;
  }
  rt_string * inner = xn_str_substr(ty, xn_int_wrap((p + 1)), xn_int_wrap((xn_int_wrap((((int64_t)ty->len) - p)) - 2)));
  if (xn_str_eq(xn_str_trim(inner), rt_string_from_c(""))) {
    return res;
  }
  xn_arr_s * raw = xn_splitTop(inner);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)raw->len))) {
    xn_arr_s_push(res, xn_str_trim(xn_arr_s_get(raw, i)));
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static int64_t xn_Cls_CGen_lambdaIndex(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->lambdas->len))) {
    if ((((xn_Cls_AstNode *)xn_arr_o_get(self->lambdas, i)) == n)) {
      return xn_int_wrap(i);
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_int_wrap(xn_int_wrap(-(1)));
}

static xn_Cls_AstNode * xn_Cls_CGen_findFunctionNode(xn_Cls_CGen *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Func")) && xn_str_eq(n->text, name))) {
      return n;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), 1, 1);
}

static rt_string * xn_Cls_CGen_callParamType(xn_Cls_CGen *self, rt_string * name, int64_t argIndex) {
  xn_Cls_AstNode * f = xn_Cls_CGen_findFunctionNode(self, name);
  if ((!xn_str_eq(f->kind, rt_string_from_c("Func")))) {
    return rt_string_from_c("");
  }
  xn_arr_o * ps = xn_Cls_CGen_paramsOf(self, f);
  if (((argIndex < 0) || (argIndex >= ((int64_t)ps->len)))) {
    return rt_string_from_c("");
  }
  xn_arr_s * parts = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(ps, argIndex))->text, rt_string_from_c(" "));
  if ((((int64_t)parts->len) >= 2)) {
    return xn_arr_s_get(parts, 0);
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_CGen_ctorParamType(xn_Cls_CGen *self, rt_string * cls, int64_t argIndex) {
  xn_Cls_AstNode * c = xn_Cls_CGen_classNode(self, cls);
  if (xn_str_eq(c->kind, rt_string_from_c("error"))) {
    return rt_string_from_c("");
  }
  xn_Cls_AstNode * ctor = xn_Cls_CGen_ctorOf(self, c);
  if ((!xn_str_eq(ctor->kind, rt_string_from_c("Ctor")))) {
    return rt_string_from_c("");
  }
  xn_arr_o * ps = xn_Cls_CGen_paramsOf(self, ctor);
  if (((argIndex < 0) || (argIndex >= ((int64_t)ps->len)))) {
    return rt_string_from_c("");
  }
  xn_arr_s * parts = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(ps, argIndex))->text, rt_string_from_c(" "));
  if ((((int64_t)parts->len) >= 2)) {
    return xn_arr_s_get(parts, 0);
  }
  return rt_string_from_c("");
}

static void xn_Cls_CGen_registerLambda(xn_Cls_CGen *self, xn_Cls_AstNode * lam, rt_string * ty) {
  if ((xn_str_eq(ty, rt_string_from_c("")) || (xn_Cls_CGen_lambdaIndex(self, lam) >= 0))) {
    return;
  }
  xn_arr_o_push(self->lambdas, lam);
  xn_arr_s_push(self->lambdaTypes, ty);
  xn_arr_s_push(self->lambdaCaptures, rt_string_from_c(""));
  xn_arr_s_push(self->lambdaCaptureTypes, rt_string_from_c(""));
  xn_arr_s_push(self->lambdaCaptureScanned, rt_string_from_c("0"));
  xn_arr_s_push(self->lambdaOwners, rt_string_from_c(""));
  xn_arr_s_push(self->lambdaModes, rt_string_from_c(""));
}

static void xn_Cls_CGen_collectReturnLambdas(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * retTy) {
  if (xn_str_eq(n->kind, rt_string_from_c("Return"))) {
    if ((((int64_t)n->kids->len) > 0)) {
      xn_Cls_CGen_collectLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)), retTy);
    }
    return;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Lambda"))) {
    return;
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_CGen_collectReturnLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), retTy);
    i = xn_int_wrap((i + 1));
  }
}

static rt_string * xn_Cls_CGen_syntacticType(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Int"))) {
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Double"))) {
    return rt_string_from_c("Double");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Bool"))) {
    return rt_string_from_c("Bool");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Char"))) {
    return rt_string_from_c("Char");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    return rt_string_from_c("String");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Cast"))) {
    return n->text;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Unary")) && (((int64_t)n->kids->len) > 0))) {
    return xn_Cls_CGen_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Binary")) && (((int64_t)n->kids->len) > 1))) {
    if ((((((((xn_str_eq(n->text, rt_string_from_c("==")) || xn_str_eq(n->text, rt_string_from_c("!="))) || xn_str_eq(n->text, rt_string_from_c("<"))) || xn_str_eq(n->text, rt_string_from_c("<="))) || xn_str_eq(n->text, rt_string_from_c(">"))) || xn_str_eq(n->text, rt_string_from_c(">="))) || xn_str_eq(n->text, rt_string_from_c("&&"))) || xn_str_eq(n->text, rt_string_from_c("||")))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(xn_Cls_CGen_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("Double")) || xn_str_eq(xn_Cls_CGen_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1))), rt_string_from_c("Double")))) {
      return rt_string_from_c("Double");
    }
    return rt_string_from_c("Int");
  }
  if (((xn_str_eq(n->kind, rt_string_from_c("Call")) && xn_str_eq(n->text, rt_string_from_c("Ok"))) && (((int64_t)n->kids->len) > 0))) {
    return xn_Cls_CGen_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
  }
  return rt_string_from_c("Int");
}

static rt_string * xn_Cls_CGen_spawnReturnType(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if ((xn_str_eq(n->kind, rt_string_from_c("Return")) && (((int64_t)n->kids->len) > 0))) {
    xn_Cls_AstNode * v = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
    if (((xn_str_eq(v->kind, rt_string_from_c("Call")) && xn_str_eq(v->text, rt_string_from_c("Ok"))) && (((int64_t)v->kids->len) > 0))) {
      return xn_Cls_CGen_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(v->kids, 0)));
    }
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    rt_string * r = xn_Cls_CGen_spawnReturnType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)));
    if ((!xn_str_eq(r, rt_string_from_c("")))) {
      return r;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_CGen_spawnLambdaType(xn_Cls_CGen *self, xn_Cls_AstNode * lam) {
  rt_string * vt = xn_Cls_CGen_spawnReturnType(self, lam);
  if (xn_str_eq(vt, rt_string_from_c(""))) {
    vt = rt_string_from_c("Int");
  }
  return xn_concat(xn_concat(rt_string_from_c("Result<"), vt), rt_string_from_c(",TaskError>()"));
}

static rt_string * xn_Cls_CGen_lambdaFirstParamType(xn_Cls_CGen *self, xn_Cls_AstNode * lam) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)lam->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(lam->kids, i));
    if (xn_str_eq(p->kind, rt_string_from_c("Param"))) {
      xn_arr_s * pp = xn_str_split(p->text, rt_string_from_c(" "));
      if ((((int64_t)pp->len) >= 2)) {
        return xn_arr_s_get(pp, 0);
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Int");
}

static int xn_Cls_CGen_lambdaHasParams(xn_Cls_CGen *self, xn_Cls_AstNode * lam) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)lam->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(lam->kids, i))->kind, rt_string_from_c("Param"))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_Cls_CGen_setLambdaMode(xn_Cls_CGen *self, xn_Cls_AstNode * lam, rt_string * mode) {
  int64_t li = xn_int_wrap(xn_Cls_CGen_lambdaIndex(self, lam));
  if ((li >= 0)) {
    xn_arr_s_set(self->lambdaModes, li, mode);
  }
}

static void xn_Cls_CGen_collectLambdas(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * expected) {
  if ((xn_str_eq(n->kind, rt_string_from_c("Func")) || xn_str_eq(n->kind, rt_string_from_c("Method")))) {
    rt_string * retTy = xn_Cls_CGen_retNode(self, n)->text;
    int64_t ri = xn_int_wrap(0);
    while ((ri < ((int64_t)n->kids->len))) {
      if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ri))->kind, rt_string_from_c("Block"))) {
        xn_Cls_CGen_collectReturnLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ri)), retTy);
      }
      ri = xn_int_wrap((ri + 1));
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Lambda"))) {
    xn_Cls_CGen_registerLambda(self, n, expected);
    if ((!xn_str_eq(expected, rt_string_from_c("")))) {
      int64_t ri = xn_int_wrap(0);
      while ((ri < ((int64_t)n->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ri))->kind, rt_string_from_c("Block"))) {
          xn_Cls_CGen_collectReturnLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ri)), xn_Cls_CGen_fnRetType(self, expected));
        }
        ri = xn_int_wrap((ri + 1));
      }
    }
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)n->kids->len))) {
      xn_Cls_CGen_collectLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), rt_string_from_c(""));
      i = xn_int_wrap((i + 1));
    }
    return;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("MethodCall"))) {
    if ((xn_str_eq(n->text, rt_string_from_c("withLock")) && (((int64_t)n->kids->len) > 1))) {
      xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1));
      rt_string * exp = xn_concat(xn_concat(rt_string_from_c("Unit("), xn_Cls_CGen_lambdaFirstParamType(self, lam)), rt_string_from_c(")"));
      xn_Cls_CGen_collectLambdas(self, lam, exp);
      xn_Cls_CGen_setLambdaMode(self, lam, rt_string_from_c("lock"));
      xn_Cls_CGen_collectLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)), rt_string_from_c(""));
      return;
    }
    if ((xn_str_eq(n->text, rt_string_from_c("spawn")) && (((int64_t)n->kids->len) > 1))) {
      xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1));
      xn_Cls_CGen_collectLambdas(self, lam, xn_Cls_CGen_spawnLambdaType(self, lam));
      xn_Cls_CGen_setLambdaMode(self, lam, rt_string_from_c("task"));
      xn_Cls_CGen_collectLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)), rt_string_from_c(""));
      return;
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Local"))) {
    xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
    rt_string * exp = rt_string_from_c("");
    if (((((int64_t)parts->len) >= 2) && xn_Cls_CGen_isFunctionType(self, xn_arr_s_get(parts, 0)))) {
      exp = xn_arr_s_get(parts, 0);
    }
    if ((((int64_t)n->kids->len) > 0)) {
      xn_Cls_CGen_collectLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)), exp);
    }
    return;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("New"))) {
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)n->kids->len))) {
      xn_Cls_CGen_collectLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), xn_Cls_CGen_ctorParamType(self, n->text, i));
      i = xn_int_wrap((i + 1));
    }
    return;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
    int64_t dn = xn_int_wrap(xn_lastDot(n->text));
    if ((dn >= 0)) {
      rt_string * dm = xn_str_substr(n->text, xn_int_wrap((dn + 1)), xn_int_wrap((xn_int_wrap((((int64_t)n->text->len) - dn)) - 1)));
      if ((xn_str_eq(dm, rt_string_from_c("withLock")) && (((int64_t)n->kids->len) > 0))) {
        xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
        xn_Cls_CGen_collectLambdas(self, lam, xn_concat(xn_concat(rt_string_from_c("Unit("), xn_Cls_CGen_lambdaFirstParamType(self, lam)), rt_string_from_c(")")));
        xn_Cls_CGen_setLambdaMode(self, lam, rt_string_from_c("lock"));
        return;
      }
      if ((xn_str_eq(dm, rt_string_from_c("spawn")) && (((int64_t)n->kids->len) > 0))) {
        xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
        xn_Cls_CGen_collectLambdas(self, lam, xn_Cls_CGen_spawnLambdaType(self, lam));
        xn_Cls_CGen_setLambdaMode(self, lam, rt_string_from_c("task"));
        return;
      }
    }
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)n->kids->len))) {
      xn_Cls_CGen_collectLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), xn_Cls_CGen_callParamType(self, n->text, i));
      i = xn_int_wrap((i + 1));
    }
    return;
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_CGen_collectLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), rt_string_from_c(""));
    i = xn_int_wrap((i + 1));
  }
}

static xn_arr_s * xn_Cls_CGen_splitCaps(xn_Cls_CGen *self, rt_string * s) {
  if (xn_str_eq(s, rt_string_from_c(""))) {
    xn_arr_s *empty = xn_arr_s_new(0);
    return empty;
  }
  return xn_str_split(s, rt_string_from_c("|"));
}

static rt_string * xn_Cls_CGen_joinCaps(xn_Cls_CGen *self, xn_arr_s * xs) {
  rt_string * s = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)xs->len))) {
    if ((i > 0)) {
      s = xn_concat(s, rt_string_from_c("|"));
    }
    s = xn_concat(s, xn_arr_s_get(xs, i));
    i = xn_int_wrap((i + 1));
  }
  return s;
}

static int xn_Cls_CGen_listHas(xn_Cls_CGen *self, xn_arr_s * xs, rt_string * v) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)xs->len))) {
    if (xn_str_eq(xn_arr_s_get(xs, i), v)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_Cls_CGen_collectShadows(xn_Cls_CGen *self, xn_Cls_AstNode * n, xn_arr_s * out) {
  if (xn_str_eq(n->kind, rt_string_from_c("Local"))) {
    xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
    if (((((int64_t)parts->len) >= 2) && (!xn_Cls_CGen_listHas(self, out, xn_arr_s_get(parts, 1))))) {
      xn_arr_s_push(out, xn_arr_s_get(parts, 1));
    }
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("ForIn")) || xn_str_eq(n->kind, rt_string_from_c("ForRange")))) {
    if ((!xn_str_eq(xn_str_trim(n->text), rt_string_from_c("")))) {
      xn_arr_s * parts = xn_str_split(xn_str_trim(n->text), rt_string_from_c(" "));
      if (((((int64_t)parts->len) >= 1) && (!xn_Cls_CGen_listHas(self, out, xn_arr_s_get(parts, xn_int_wrap((((int64_t)parts->len) - 1))))))) {
        xn_arr_s_push(out, xn_arr_s_get(parts, xn_int_wrap((((int64_t)parts->len) - 1))));
      }
    }
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_CGen_collectShadows(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), out);
    i = xn_int_wrap((i + 1));
  }
}

static int xn_Cls_CGen_containsVarUse(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * name) {
  if ((xn_str_eq(n->kind, rt_string_from_c("Name")) && xn_str_eq(n->text, name))) {
    return 1;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Call")) && (xn_str_eq(n->text, name) || xn_str_startswith(n->text, xn_concat(name, rt_string_from_c(".")))))) {
    return 1;
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    if (xn_Cls_CGen_containsVarUse(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), name)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_Cls_CGen_ensureLambdaCaptures(xn_Cls_CGen *self, int64_t li, xn_Cls_AstNode * lam) {
  if (((li < 0) || (li >= ((int64_t)self->lambdaCaptures->len)))) {
    return;
  }
  if (xn_str_eq(xn_arr_s_get(self->lambdaCaptureScanned, li), rt_string_from_c("1"))) {
    return;
  }
  xn_arr_s *params = xn_arr_s_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)lam->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(lam->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Param"))) {
      xn_arr_s * pp = xn_str_split(k->text, rt_string_from_c(" "));
      if ((((int64_t)pp->len) >= 2)) {
        xn_arr_s_push(params, xn_arr_s_get(pp, 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  xn_arr_s *shadows = xn_arr_s_new(0);
  i = 0;
  while ((i < ((int64_t)lam->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(lam->kids, i))->kind, rt_string_from_c("Block"))) {
      xn_Cls_CGen_collectShadows(self, ((xn_Cls_AstNode *)xn_arr_o_get(lam->kids, i)), shadows);
    }
    i = xn_int_wrap((i + 1));
  }
  xn_arr_s * names = xn_Cls_CGen_splitCaps(self, xn_arr_s_get(self->lambdaCaptures, li));
  xn_arr_s * types = xn_Cls_CGen_splitCaps(self, xn_arr_s_get(self->lambdaCaptureTypes, li));
  i = xn_int_wrap((((int64_t)self->vars->len) - 1));
  while ((i >= 0)) {
    rt_string * vn = xn_arr_s_get(self->vars, i);
    if (((((!xn_Cls_CGen_listHas(self, params, vn)) && (!xn_Cls_CGen_listHas(self, shadows, vn))) && (!xn_Cls_CGen_listHas(self, names, vn))) && xn_Cls_CGen_containsVarUse(self, lam, vn))) {
      xn_arr_s_push(names, vn);
      xn_arr_s_push(types, xn_arr_s_get(self->varTypes, i));
    }
    i = xn_int_wrap((i - 1));
  }
  xn_arr_s_set(self->lambdaCaptures, li, xn_Cls_CGen_joinCaps(self, names));
  xn_arr_s_set(self->lambdaCaptureTypes, li, xn_Cls_CGen_joinCaps(self, types));
  xn_arr_s_set(self->lambdaCaptureScanned, li, rt_string_from_c("1"));
}

static rt_string * xn_Cls_CGen_lambdaName(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  int64_t i = xn_int_wrap(xn_Cls_CGen_lambdaIndex(self, n));
  if ((i < 0)) {
    return rt_string_from_c("xn_lambda_missing");
  }
  return xn_concat(rt_string_from_c("xn_lambda_"), xn_str_int(i));
}

static rt_string * xn_Cls_CGen_fnPtrDecl(xn_Cls_CGen *self, rt_string * ty, rt_string * name) {
  return xn_concat(rt_string_from_c("xn_closure "), name);
}

static int xn_Cls_CGen_ffiSpecial(xn_Cls_CGen *self, rt_string * name) {
  return ((((((((((((xn_str_eq(name, rt_string_from_c("diagnoseRaw")) || xn_str_eq(name, rt_string_from_c("exitRaw"))) || xn_str_eq(name, rt_string_from_c("nowMonoRaw"))) || xn_str_eq(name, rt_string_from_c("nowWallRaw"))) || xn_str_eq(name, rt_string_from_c("resourceExistsRaw"))) || xn_str_eq(name, rt_string_from_c("resourceCountRaw"))) || xn_str_eq(name, rt_string_from_c("readResourceTextRaw"))) || xn_str_eq(name, rt_string_from_c("fileExistsRaw"))) || xn_str_eq(name, rt_string_from_c("readFile"))) || xn_str_eq(name, rt_string_from_c("listFiles"))) || xn_str_eq(name, rt_string_from_c("platformRaw"))) || xn_str_eq(name, rt_string_from_c("readFileTextRaw"))) || xn_str_eq(name, rt_string_from_c("readFileTextError")));
}

static int xn_Cls_CGen_ffiHardProto(xn_Cls_CGen *self, rt_string * cname) {
  return ((((((((xn_str_eq(cname, rt_string_from_c("xdkc_p_resource_exists")) || xn_str_eq(cname, rt_string_from_c("xdkc_p_read_resource_text"))) || xn_str_eq(cname, rt_string_from_c("xdkc_p_resource_count"))) || xn_str_eq(cname, rt_string_from_c("xdkc_read_file_text"))) || xn_str_eq(cname, rt_string_from_c("xdkc_read_file_text_error"))) || xn_str_eq(cname, rt_string_from_c("xdkc_diagnose_rc"))) || xn_str_eq(cname, rt_string_from_c("xdkc_exit_rc"))) || xn_str_eq(cname, rt_string_from_c("xdkc_now_mono_ms"))) || xn_str_eq(cname, rt_string_from_c("xdkc_now_wall_ms")));
}

static int xn_Cls_CGen_ffiTypeOk(xn_Cls_CGen *self, rt_string * ty) {
  return (((((((((((((xn_str_eq(ty, rt_string_from_c("Int")) || xn_str_eq(ty, rt_string_from_c("Int32"))) || xn_str_eq(ty, rt_string_from_c("Int64"))) || xn_str_eq(ty, rt_string_from_c("Long"))) || xn_str_eq(ty, rt_string_from_c("UInt16"))) || xn_str_eq(ty, rt_string_from_c("Bool"))) || xn_str_eq(ty, rt_string_from_c("Double"))) || xn_str_eq(ty, rt_string_from_c("Float"))) || xn_str_eq(ty, rt_string_from_c("String"))) || xn_str_eq(ty, rt_string_from_c("Bytes"))) || xn_str_eq(ty, rt_string_from_c("Context"))) || xn_str_eq(ty, rt_string_from_c("void"))) || xn_str_eq(ty, rt_string_from_c("Void"))) || xn_str_eq(ty, rt_string_from_c("Unit")));
}

static rt_string * xn_Cls_CGen_ffiMiniType(xn_Cls_CGen *self, rt_string * ty) {
  if (xn_str_eq(ty, rt_string_from_c("Context"))) {
    return rt_string_from_c("void *");
  }
  if (xn_str_eq(ty, rt_string_from_c("Bytes"))) {
    return rt_string_from_c("xrt_bytes_obj *");
  }
  if (xn_str_eq(ty, rt_string_from_c("String"))) {
    return rt_string_from_c("rt_string *");
  }
  if (xn_str_eq(ty, rt_string_from_c("Double"))) {
    return rt_string_from_c("double");
  }
  if (xn_str_eq(ty, rt_string_from_c("Float"))) {
    return rt_string_from_c("double");
  }
  if (xn_str_eq(ty, rt_string_from_c("Bool"))) {
    return rt_string_from_c("int");
  }
  if (((xn_str_eq(ty, rt_string_from_c("void")) || xn_str_eq(ty, rt_string_from_c("Void"))) || xn_str_eq(ty, rt_string_from_c("Unit")))) {
    return rt_string_from_c("void");
  }
  return rt_string_from_c("int64_t");
}

static rt_string * xn_Cls_CGen_ffiAbiType(xn_Cls_CGen *self, rt_string * ty) {
  if (xn_str_eq(ty, rt_string_from_c("String"))) {
    return rt_string_from_c("const char *");
  }
  if (xn_str_eq(ty, rt_string_from_c("Bytes"))) {
    return rt_string_from_c("const unsigned char *");
  }
  if (xn_str_eq(ty, rt_string_from_c("Context"))) {
    return rt_string_from_c("void *");
  }
  if ((xn_str_eq(ty, rt_string_from_c("Int32")) || xn_str_eq(ty, rt_string_from_c("Bool")))) {
    return rt_string_from_c("int32_t");
  }
  if (xn_str_eq(ty, rt_string_from_c("Double"))) {
    return rt_string_from_c("double");
  }
  if (xn_str_eq(ty, rt_string_from_c("Float"))) {
    return rt_string_from_c("float");
  }
  if (((xn_str_eq(ty, rt_string_from_c("void")) || xn_str_eq(ty, rt_string_from_c("Void"))) || xn_str_eq(ty, rt_string_from_c("Unit")))) {
    return rt_string_from_c("void");
  }
  return rt_string_from_c("int64_t");
}

static int64_t xn_Cls_CGen_ffiParamCount(xn_Cls_CGen *self, int64_t idx) {
  if ((((idx < 0) || (idx >= ((int64_t)self->ffiCallSpecs->len))) || xn_str_eq(xn_arr_s_get(self->ffiCallSpecs, idx), rt_string_from_c("")))) {
    return xn_int_wrap(0);
  }
  return xn_int_wrap(((int64_t)xn_str_split(xn_arr_s_get(self->ffiCallSpecs, idx), rt_string_from_c(";"))->len));
}

static rt_string * xn_Cls_CGen_ffiParamType(xn_Cls_CGen *self, int64_t idx, int64_t p) {
  if ((((idx < 0) || (idx >= ((int64_t)self->ffiCallSpecs->len))) || xn_str_eq(xn_arr_s_get(self->ffiCallSpecs, idx), rt_string_from_c("")))) {
    return rt_string_from_c("");
  }
  xn_arr_s * segs = xn_str_split(xn_arr_s_get(self->ffiCallSpecs, idx), rt_string_from_c(";"));
  if (((p < 0) || (p >= ((int64_t)segs->len)))) {
    return rt_string_from_c("");
  }
  xn_arr_s * parts = xn_str_split(xn_arr_s_get(segs, p), rt_string_from_c(":"));
  if ((((int64_t)parts->len) >= 3)) {
    return xn_arr_s_get(parts, 2);
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_CGen_ffiParamName(xn_Cls_CGen *self, int64_t idx, int64_t p) {
  if ((((idx < 0) || (idx >= ((int64_t)self->ffiCallSpecs->len))) || xn_str_eq(xn_arr_s_get(self->ffiCallSpecs, idx), rt_string_from_c("")))) {
    return rt_string_from_c("");
  }
  xn_arr_s * segs = xn_str_split(xn_arr_s_get(self->ffiCallSpecs, idx), rt_string_from_c(";"));
  if (((p < 0) || (p >= ((int64_t)segs->len)))) {
    return rt_string_from_c("");
  }
  xn_arr_s * parts = xn_str_split(xn_arr_s_get(segs, p), rt_string_from_c(":"));
  if ((((int64_t)parts->len) >= 1)) {
    return xn_arr_s_get(parts, 0);
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_CGen_ffiErrParam(xn_Cls_CGen *self, int64_t idx) {
  if (((idx < 0) || (idx >= ((int64_t)self->ffiCallErrParams->len)))) {
    return rt_string_from_c("");
  }
  return xn_arr_s_get(self->ffiCallErrParams, idx);
}

static int64_t xn_Cls_CGen_ffiErrParamIndex(xn_Cls_CGen *self, int64_t idx) {
  rt_string * ep = xn_Cls_CGen_ffiErrParam(self, idx);
  if (xn_str_eq(ep, rt_string_from_c(""))) {
    return xn_int_wrap(xn_int_wrap(-(1)));
  }
  int64_t n = xn_int_wrap(xn_Cls_CGen_ffiParamCount(self, idx));
  int64_t p = xn_int_wrap(0);
  while ((p < n)) {
    if (xn_str_eq(xn_Cls_CGen_ffiParamName(self, idx, p), ep)) {
      return xn_int_wrap(p);
    }
    p = xn_int_wrap((p + 1));
  }
  return xn_int_wrap(xn_int_wrap(-(1)));
}

static int xn_Cls_CGen_ffiEntryOk(xn_Cls_CGen *self, int64_t idx) {
  if (((idx < 0) || (idx >= ((int64_t)self->ffiCallNames->len)))) {
    return 0;
  }
  if ((!xn_Cls_CGen_ffiTypeOk(self, xn_arr_s_get(self->ffiCallRets, idx)))) {
    return 0;
  }
  int64_t n = xn_int_wrap(xn_Cls_CGen_ffiParamCount(self, idx));
  int64_t p = xn_int_wrap(0);
  while ((p < n)) {
    if ((!xn_Cls_CGen_ffiTypeOk(self, xn_Cls_CGen_ffiParamType(self, idx, p)))) {
      return 0;
    }
    p = xn_int_wrap((p + 1));
  }
  return 1;
}

static rt_string * xn_Cls_CGen_ffiAbiProto(xn_Cls_CGen *self, int64_t idx) {
  rt_string * cname = xn_arr_s_get(self->ffiCallCNames, idx);
  rt_string * ret = xn_Cls_CGen_ffiAbiType(self, xn_arr_s_get(self->ffiCallRets, idx));
  rt_string * sig = xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("extern "), ret), rt_string_from_c(" ")), cname), rt_string_from_c("("));
  int64_t n = xn_int_wrap(xn_Cls_CGen_ffiParamCount(self, idx));
  int64_t epi = xn_int_wrap(xn_Cls_CGen_ffiErrParamIndex(self, idx));
  if ((n == 0)) {
    sig = xn_concat(sig, rt_string_from_c("void"));
  }
  int64_t p = xn_int_wrap(0);
  while ((p < n)) {
    if ((p > 0)) {
      sig = xn_concat(sig, rt_string_from_c(", "));
    }
    rt_string * ty = xn_Cls_CGen_ffiParamType(self, idx, p);
    if ((p == epi)) {
      sig = xn_concat(xn_concat(sig, rt_string_from_c("int32_t *a")), xn_str_int(p));
    }
    else {
      if (xn_str_eq(ty, rt_string_from_c("String"))) {
        sig = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(sig, rt_string_from_c("const char *a")), xn_str_int(p)), rt_string_from_c("_bytes, size_t a")), xn_str_int(p)), rt_string_from_c("_len"));
      }
      else {
        if (xn_str_eq(ty, rt_string_from_c("Bytes"))) {
          sig = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(sig, rt_string_from_c("const unsigned char *a")), xn_str_int(p)), rt_string_from_c("_data, size_t a")), xn_str_int(p)), rt_string_from_c("_len"));
        }
        else {
          sig = xn_concat(xn_concat(xn_concat(sig, xn_Cls_CGen_ffiAbiType(self, ty)), rt_string_from_c(" a")), xn_str_int(p));
        }
      }
    }
    p = xn_int_wrap((p + 1));
  }
  return xn_concat(sig, rt_string_from_c(");"));
}

static rt_string * xn_Cls_CGen_ffiWrapperSig(xn_Cls_CGen *self, int64_t idx) {
  rt_string * name = xn_arr_s_get(self->ffiCallNames, idx);
  rt_string * ret = xn_Cls_CGen_ffiMiniType(self, xn_arr_s_get(self->ffiCallRets, idx));
  rt_string * sig = xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), ret), rt_string_from_c(" xn_ffi_")), name), rt_string_from_c("("));
  int64_t n = xn_int_wrap(xn_Cls_CGen_ffiParamCount(self, idx));
  int64_t epi = xn_int_wrap(xn_Cls_CGen_ffiErrParamIndex(self, idx));
  if ((n == 0)) {
    sig = xn_concat(sig, rt_string_from_c("void"));
  }
  int64_t p = xn_int_wrap(0);
  while ((p < n)) {
    if ((p > 0)) {
      sig = xn_concat(sig, rt_string_from_c(", "));
    }
    if ((p == epi)) {
      sig = xn_concat(xn_concat(sig, rt_string_from_c("int64_t *a")), xn_str_int(p));
    }
    else {
      sig = xn_concat(xn_concat(xn_concat(sig, xn_Cls_CGen_ffiMiniType(self, xn_Cls_CGen_ffiParamType(self, idx, p))), rt_string_from_c(" a")), xn_str_int(p));
    }
    p = xn_int_wrap((p + 1));
  }
  return xn_concat(sig, rt_string_from_c(")"));
}

static rt_string * xn_Cls_CGen_ffiWrapperArgs(xn_Cls_CGen *self, int64_t idx) {
  rt_string * args = rt_string_from_c("");
  int64_t n = xn_int_wrap(xn_Cls_CGen_ffiParamCount(self, idx));
  int64_t epi = xn_int_wrap(xn_Cls_CGen_ffiErrParamIndex(self, idx));
  int64_t p = xn_int_wrap(0);
  while ((p < n)) {
    if ((p > 0)) {
      args = xn_concat(args, rt_string_from_c(", "));
    }
    rt_string * ty = xn_Cls_CGen_ffiParamType(self, idx, p);
    if ((p == epi)) {
      args = xn_concat(args, rt_string_from_c("&xn_err"));
    }
    else {
      if (xn_str_eq(ty, rt_string_from_c("String"))) {
        args = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(args, rt_string_from_c("a")), xn_str_int(p)), rt_string_from_c("->bytes, a")), xn_str_int(p)), rt_string_from_c("->len"));
      }
      else {
        if (xn_str_eq(ty, rt_string_from_c("Bytes"))) {
          args = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(args, rt_string_from_c("xrt_bytes_data(a")), xn_str_int(p)), rt_string_from_c("), xrt_bytes_len(a")), xn_str_int(p)), rt_string_from_c(")"));
        }
        else {
          if ((xn_str_eq(ty, rt_string_from_c("Int32")) || xn_str_eq(ty, rt_string_from_c("Bool")))) {
            args = xn_concat(xn_concat(args, rt_string_from_c("(int32_t)a")), xn_str_int(p));
          }
          else {
            if (xn_str_eq(ty, rt_string_from_c("Context"))) {
              args = xn_concat(xn_concat(args, rt_string_from_c("(xrt_context *)a")), xn_str_int(p));
            }
            else {
              args = xn_concat(xn_concat(args, rt_string_from_c("a")), xn_str_int(p));
            }
          }
        }
      }
    }
    p = xn_int_wrap((p + 1));
  }
  return args;
}

static rt_string * xn_Cls_CGen_ffiWrapperDef(xn_Cls_CGen *self, int64_t idx) {
  rt_string * name = xn_arr_s_get(self->ffiCallNames, idx);
  rt_string * cname = xn_arr_s_get(self->ffiCallCNames, idx);
  rt_string * rt = xn_arr_s_get(self->ffiCallRets, idx);
  int64_t epi = xn_int_wrap(xn_Cls_CGen_ffiErrParamIndex(self, idx));
  rt_string * call = xn_concat(xn_concat(xn_concat(cname, rt_string_from_c("(")), xn_Cls_CGen_ffiWrapperArgs(self, idx)), rt_string_from_c(")"));
  rt_string * body = xn_concat(xn_Cls_CGen_ffiWrapperSig(self, idx), rt_string_from_c(" {\n"));
  if ((epi >= 0)) {
    body = xn_concat(body, rt_string_from_c("  int32_t xn_err = 0;\n"));
  }
  if (((xn_str_eq(rt, rt_string_from_c("void")) || xn_str_eq(rt, rt_string_from_c("Void"))) || xn_str_eq(rt, rt_string_from_c("Unit")))) {
    body = xn_concat(xn_concat(xn_concat(body, rt_string_from_c("  ")), call), rt_string_from_c(";\n"));
  }
  else {
    rt_string * miniRet = xn_Cls_CGen_ffiMiniType(self, rt);
    rt_string * out = call;
    if (xn_str_eq(rt, rt_string_from_c("String"))) {
      out = xn_concat(xn_concat(rt_string_from_c("rt_string_from_c((const char *)"), call), rt_string_from_c(")"));
    }
    else {
      if (xn_str_eq(rt, rt_string_from_c("Bool"))) {
        out = xn_concat(xn_concat(rt_string_from_c("("), call), rt_string_from_c(") ? 1 : 0"));
      }
      else {
        if (((!xn_str_eq(rt, rt_string_from_c("Double"))) && (!xn_str_eq(rt, rt_string_from_c("Float"))))) {
          out = xn_concat(xn_concat(rt_string_from_c("(int64_t)("), call), rt_string_from_c(")"));
        }
      }
    }
    body = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(body, rt_string_from_c("  ")), miniRet), rt_string_from_c(" xn_out = ")), out), rt_string_from_c(";\n"));
  }
  if ((epi >= 0)) {
    body = xn_concat(xn_concat(xn_concat(body, rt_string_from_c("  *a")), xn_str_int(epi)), rt_string_from_c(" = (int64_t)xn_err;\n"));
  }
  if (((xn_str_eq(rt, rt_string_from_c("void")) || xn_str_eq(rt, rt_string_from_c("Void"))) || xn_str_eq(rt, rt_string_from_c("Unit")))) {
    body = xn_concat(body, rt_string_from_c("  return;\n"));
  }
  else {
    body = xn_concat(body, rt_string_from_c("  return xn_out;\n"));
  }
  return xn_concat(body, rt_string_from_c("}"));
}

static void xn_Cls_CGen_emitFfiDecls(xn_Cls_CGen *self) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->ffiCallNames->len))) {
    if ((((!xn_Cls_CGen_ffiSpecial(self, xn_arr_s_get(self->ffiCallNames, i))) && xn_Cls_CGen_ffiEntryOk(self, i)) && (!xn_Cls_CGen_ffiHardProto(self, xn_arr_s_get(self->ffiCallCNames, i))))) {
      xn_Cls_CGen_emit(self, xn_Cls_CGen_ffiAbiProto(self, i));
    }
    i = xn_int_wrap((i + 1));
  }
  if ((((int64_t)self->ffiCallNames->len) > 0)) {
    xn_Cls_CGen_emit(self, rt_string_from_c(""));
  }
  i = 0;
  while ((i < ((int64_t)self->ffiCallNames->len))) {
    if (((!xn_Cls_CGen_ffiSpecial(self, xn_arr_s_get(self->ffiCallNames, i))) && xn_Cls_CGen_ffiEntryOk(self, i))) {
      xn_Cls_CGen_emit(self, xn_Cls_CGen_ffiWrapperDef(self, i));
    }
    i = xn_int_wrap((i + 1));
  }
  if ((((int64_t)self->ffiCallNames->len) > 0)) {
    xn_Cls_CGen_emit(self, rt_string_from_c(""));
  }
}

static rt_string * xn_Cls_CGen_closureCast(xn_Cls_CGen *self, rt_string * ty) {
  rt_string * ret = xn_Cls_CGen_ctype(self, xn_Cls_CGen_fnRetType(self, ty));
  xn_arr_s * ps = xn_Cls_CGen_fnParams(self, ty);
  rt_string * sig = xn_concat(ret, rt_string_from_c(" (*)(void *"));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ps->len))) {
    sig = xn_concat(xn_concat(sig, rt_string_from_c(", ")), xn_Cls_CGen_ctype(self, xn_arr_s_get(ps, i)));
    i = xn_int_wrap((i + 1));
  }
  return xn_concat(sig, rt_string_from_c(")"));
}

static rt_string * xn_Cls_CGen_closureCall(xn_Cls_CGen *self, rt_string * ty, rt_string * target, xn_Cls_AstNode * call) {
  rt_string * b = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), xn_Cls_CGen_closureCast(self, ty)), rt_string_from_c(")")), target), rt_string_from_c(".fn)(")), target), rt_string_from_c(".env"));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)call->kids->len))) {
    b = xn_concat(xn_concat(b, rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(call->kids, i))));
    i = xn_int_wrap((i + 1));
  }
  return xn_concat(b, rt_string_from_c(")"));
}

static rt_string * xn_Cls_CGen_lambdaProto(xn_Cls_CGen *self, int64_t i) {
  xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(self->lambdas, i));
  rt_string * ft = xn_arr_s_get(self->lambdaTypes, i);
  rt_string * sig = xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), xn_Cls_CGen_ctype(self, xn_Cls_CGen_fnRetType(self, ft))), rt_string_from_c(" xn_lambda_")), xn_str_int(i)), rt_string_from_c("(void *xn_env"));
  int64_t pi = xn_int_wrap(0);
  while ((pi < ((int64_t)lam->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(lam->kids, pi));
    if (xn_str_eq(p->kind, rt_string_from_c("Param"))) {
      xn_arr_s * pp = xn_str_split(p->text, rt_string_from_c(" "));
      if ((((int64_t)pp->len) >= 2)) {
        sig = xn_concat(xn_concat(xn_concat(xn_concat(sig, rt_string_from_c(", ")), xn_Cls_CGen_ctype(self, xn_arr_s_get(pp, 0))), rt_string_from_c(" ")), xn_arr_s_get(pp, 1));
      }
    }
    pi = xn_int_wrap((pi + 1));
  }
  if ((xn_str_eq(xn_Cls_CGen_lambdaMode(self, i), rt_string_from_c("task")) && (!xn_Cls_CGen_lambdaHasParams(self, lam)))) {
    sig = xn_concat(sig, rt_string_from_c(", xrt_context *xn_task_ctx"));
  }
  return xn_concat(sig, rt_string_from_c(");"));
}

static rt_string * xn_Cls_CGen_lockAdapterProto(xn_Cls_CGen *self, int64_t i) {
  return xn_concat(xn_concat(rt_string_from_c("static int32_t xn_lock_body_"), xn_str_int(i)), rt_string_from_c("(void *data, void *env, xrt_context *ctx);"));
}

static rt_string * xn_Cls_CGen_lambdaMode(xn_Cls_CGen *self, int64_t i) {
  if (((i >= 0) && (i < ((int64_t)self->lambdaModes->len)))) {
    return xn_arr_s_get(self->lambdaModes, i);
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_CGen_taskAdapterProto(xn_Cls_CGen *self, int64_t i) {
  return xn_concat(xn_concat(rt_string_from_c("static int32_t xn_task_body_"), xn_str_int(i)), rt_string_from_c("(void *env, xrt_context *ctx, xrt_task_result *out);"));
}

static void xn_Cls_CGen_emitLockAdapter(xn_Cls_CGen *self, int64_t i) {
  xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(self->lambdas, i));
  rt_string * pt = xn_Cls_CGen_lambdaFirstParamType(self, lam);
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("static int32_t xn_lock_body_"), xn_str_int(i)), rt_string_from_c("(void *data, void *env, xrt_context *ctx) {")));
  xn_Cls_CGen_emit(self, rt_string_from_c("  (void)ctx;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("  xn_closure *xn_cl = (xn_closure *)env;"));
  if (xn_Cls_CGen_lambdaHasParams(self, lam)) {
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("  ((void (*)(void *, "), xn_Cls_CGen_ctype(self, pt)), rt_string_from_c("))xn_cl->fn)(xn_cl->env, (")), xn_Cls_CGen_ctype(self, pt)), rt_string_from_c(")(intptr_t)data);")));
  }
  else {
    xn_Cls_CGen_emit(self, rt_string_from_c("  ((void (*)(void *))xn_cl->fn)(xn_cl->env);"));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c("  return 0;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("}"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
}

static void xn_Cls_CGen_emitTaskAdapter(xn_Cls_CGen *self, int64_t i) {
  rt_string * rt = xn_arr_s_get(self->lambdaTypes, i);
  rt_string * vt = xn_Cls_CGen_resultValue(self, xn_Cls_CGen_fnRetType(self, rt));
  rt_string * mapv = rt_string_from_c("(void *)(intptr_t)(r.i)");
  if (xn_str_eq(vt, rt_string_from_c("String"))) {
    mapv = rt_string_from_c("(void *)(r.s)");
  }
  else {
    if (((((((!xn_str_eq(vt, rt_string_from_c("Int"))) && (!xn_str_eq(vt, rt_string_from_c("Int32")))) && (!xn_str_eq(vt, rt_string_from_c("Int64")))) && (!xn_str_eq(vt, rt_string_from_c("Long")))) && (!xn_str_eq(vt, rt_string_from_c("Bool")))) && (!xn_str_eq(vt, rt_string_from_c("Char"))))) {
      mapv = rt_string_from_c("(void *)(r.p)");
    }
  }
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("static int32_t xn_task_body_"), xn_str_int(i)), rt_string_from_c("(void *env, xrt_context *ctx, xrt_task_result *out) {")));
  xn_Cls_CGen_emit(self, rt_string_from_c("  xn_closure *xn_cl = (xn_closure *)env;"));
  if (xn_Cls_CGen_lambdaHasParams(self, ((xn_Cls_AstNode *)xn_arr_o_get(self->lambdas, i)))) {
    xn_Cls_CGen_emit(self, rt_string_from_c("  (void)ctx;"));
    xn_Cls_CGen_emit(self, rt_string_from_c("  xn_Result r = ((xn_Result (*)(void *))xn_cl->fn)(xn_cl->env);"));
  }
  else {
    if (xn_str_eq(xn_Cls_CGen_lambdaMode(self, i), rt_string_from_c("task"))) {
      xn_Cls_CGen_emit(self, rt_string_from_c("  xn_Result r = ((xn_Result (*)(void *, xrt_context *))xn_cl->fn)(xn_cl->env, ctx);"));
    }
    else {
      xn_Cls_CGen_emit(self, rt_string_from_c("  (void)ctx;"));
      xn_Cls_CGen_emit(self, rt_string_from_c("  xn_Result r = ((xn_Result (*)(void *))xn_cl->fn)(xn_cl->env);"));
    }
  }
  xn_Cls_CGen_emit(self, rt_string_from_c("  out->ok = r.ok;"));
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("  out->value = r.ok ? "), mapv), rt_string_from_c(" : NULL;")));
  xn_Cls_CGen_emit(self, rt_string_from_c("  out->kind = r.ok ? (xrt_error_kind)0 : (xrt_error_kind)(intptr_t)r.err;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("  out->error = NULL;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("  return 0;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("}"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
}

static void xn_Cls_CGen_emitLambdaDef(xn_Cls_CGen *self, int64_t i) {
  xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(self->lambdas, i));
  rt_string * ft = xn_arr_s_get(self->lambdaTypes, i);
  xn_Cls_CGen_emit(self, xn_concat(xn_str_substr(xn_Cls_CGen_lambdaProto(self, i), 0, xn_int_wrap((((int64_t)xn_Cls_CGen_lambdaProto(self, i)->len) - 1))), rt_string_from_c(" {")));
  self->curRet = xn_Cls_CGen_fnRetType(self, ft);
  rt_string * oldClass = self->curClass;
  rt_string * oldCtx = self->curCtxExpr;
  if ((xn_str_eq(xn_Cls_CGen_lambdaMode(self, i), rt_string_from_c("task")) && (!xn_Cls_CGen_lambdaHasParams(self, lam)))) {
    self->curCtxExpr = rt_string_from_c("xn_task_ctx");
  }
  rt_string * owner = xn_arr_s_get(self->lambdaOwners, i);
  if ((!xn_str_eq(owner, rt_string_from_c("")))) {
    self->curClass = owner;
  }
  xn_Cls_CGen_popTo(self, 0);
  xn_arr_s * caps = xn_Cls_CGen_splitCaps(self, xn_arr_s_get(self->lambdaCaptures, i));
  xn_arr_s * capTypes = xn_Cls_CGen_splitCaps(self, xn_arr_s_get(self->lambdaCaptureTypes, i));
  if ((((int64_t)caps->len) > 0)) {
    xn_Cls_CGen_emit(self, rt_string_from_c("  void **xn_caps = (void **)xn_env;"));
  }
  int64_t ci = xn_int_wrap(0);
  while ((ci < ((int64_t)caps->len))) {
    rt_string * ct = xn_Cls_CGen_ctype(self, xn_arr_s_get(capTypes, ci));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("  "), ct), rt_string_from_c(" ")), xn_arr_s_get(caps, ci)), rt_string_from_c(" = *(")), ct), rt_string_from_c(" *)xn_caps[")), xn_str_int(ci)), rt_string_from_c("];")));
    xn_Cls_CGen_addVar(self, xn_arr_s_get(capTypes, ci), xn_arr_s_get(caps, ci));
    ci = xn_int_wrap((ci + 1));
  }
  int64_t pi = xn_int_wrap(0);
  while ((pi < ((int64_t)lam->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(lam->kids, pi));
    if (xn_str_eq(p->kind, rt_string_from_c("Param"))) {
      xn_arr_s * pp = xn_str_split(p->text, rt_string_from_c(" "));
      if ((((int64_t)pp->len) >= 2)) {
        xn_Cls_CGen_addVar(self, xn_arr_s_get(pp, 0), xn_arr_s_get(pp, 1));
      }
    }
    pi = xn_int_wrap((pi + 1));
  }
  pi = 0;
  while ((pi < ((int64_t)lam->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(lam->kids, pi))->kind, rt_string_from_c("Block"))) {
      xn_Cls_CGen_blockBody(self, ((xn_Cls_AstNode *)xn_arr_o_get(lam->kids, pi)), rt_string_from_c("  "));
    }
    pi = xn_int_wrap((pi + 1));
  }
  xn_Cls_CGen_popTo(self, 0);
  self->curClass = oldClass;
  self->curCtxExpr = oldCtx;
  xn_Cls_CGen_emit(self, rt_string_from_c("}"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
}

static int xn_Cls_CGen_isEnumName(xn_Cls_CGen *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int64_t xn_Cls_CGen_enumValue(xn_Cls_CGen *self, rt_string * name, rt_string * item) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * it = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j));
        if ((xn_str_eq(it->kind, rt_string_from_c("EnumItem")) && xn_str_eq(it->text, item))) {
          return xn_int_wrap(j);
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_int_wrap(0);
}

static xn_arr_s * xn_Cls_CGen_enumItems(xn_Cls_CGen *self, rt_string * name) {
  xn_arr_s *res = xn_arr_s_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * it = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j));
        if (xn_str_eq(it->kind, rt_string_from_c("EnumItem"))) {
          xn_arr_s_push(res, it->text);
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static rt_string * xn_Cls_CGen_enumCaseItem(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * enumName) {
  if (((!xn_str_eq(n->kind, rt_string_from_c("Member"))) || (((int64_t)n->kids->len) == 0))) {
    return rt_string_from_c("");
  }
  if ((!xn_str_eq(xn_Cls_CGen_typeOf(self, n), enumName))) {
    return rt_string_from_c("");
  }
  return n->text;
}

static int xn_Cls_CGen_isClass(xn_Cls_CGen *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && xn_str_eq(n->text, name))) {
      return 1;
    }
    if ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j))->kind, rt_string_from_c("Data"))) {
          return 1;
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int xn_Cls_CGen_isDataEnum(xn_Cls_CGen *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j))->kind, rt_string_from_c("Data"))) {
          return 1;
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static xn_Cls_AstNode * xn_Cls_CGen_classNode(xn_Cls_CGen *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && xn_str_eq(n->text, name)) || ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_str_eq(n->text, name)) && xn_Cls_CGen_isDataEnum(self, name)))) {
      return n;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("error"), name, 1, 1);
}

static rt_string * xn_Cls_CGen_fieldType(xn_Cls_CGen *self, rt_string * cls, rt_string * fname) {
  xn_Cls_AstNode * c = xn_Cls_CGen_classNode(self, cls);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)c->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Field"))) {
      xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
      if (((((int64_t)parts->len) >= 2) && xn_str_eq(xn_arr_s_get(parts, 1), fname))) {
        return xn_arr_s_get(parts, 0);
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Any");
}

static int xn_Cls_CGen_isStaticMethod(xn_Cls_CGen *self, rt_string * cls, rt_string * mname) {
  xn_Cls_AstNode * c = xn_Cls_CGen_classNode(self, cls);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)c->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, i));
    if ((xn_str_eq(k->kind, rt_string_from_c("Method")) && xn_str_eq(k->text, mname))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)k->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(k->kids, j))->kind, rt_string_from_c("Static"))) {
          return 1;
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static rt_string * xn_Cls_CGen_methodRet(xn_Cls_CGen *self, rt_string * cls, rt_string * mname) {
  xn_Cls_AstNode * c = xn_Cls_CGen_classNode(self, cls);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)c->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, i));
    if ((xn_str_eq(k->kind, rt_string_from_c("Method")) && xn_str_eq(k->text, mname))) {
      rt_string * r = xn_Cls_CGen_retNode(self, k)->text;
      return r;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Any");
}

static int64_t xn_Cls_CGen_varIndex(xn_Cls_CGen *self, rt_string * name) {
  int64_t i = xn_int_wrap(xn_int_wrap((((int64_t)self->vars->len) - 1)));
  while ((i >= 0)) {
    if (xn_str_eq(xn_arr_s_get(self->vars, i), name)) {
      return xn_int_wrap(i);
    }
    i = xn_int_wrap((i - 1));
  }
  return xn_int_wrap(xn_int_wrap(-(1)));
}

static rt_string * xn_Cls_CGen_findVar(xn_Cls_CGen *self, rt_string * name) {
  int64_t i = xn_int_wrap(xn_int_wrap((((int64_t)self->vars->len) - 1)));
  while ((i >= 0)) {
    if (xn_str_eq(xn_arr_s_get(self->vars, i), name)) {
      return xn_arr_s_get(self->varTypes, i);
    }
    i = xn_int_wrap((i - 1));
  }
  return rt_string_from_c("Any");
}

static void xn_Cls_CGen_addVar(xn_Cls_CGen *self, rt_string * ty, rt_string * name) {
  xn_arr_s_push(self->vars, name);
  xn_arr_s_push(self->varTypes, ty);
}

static void xn_Cls_CGen_popTo(xn_Cls_CGen *self, int64_t mark) {
  while ((((int64_t)self->vars->len) > mark)) {
    xn_arr_s_remove(self->vars, xn_int_wrap((((int64_t)self->vars->len) - 1)));
    xn_arr_s_remove(self->varTypes, xn_int_wrap((((int64_t)self->varTypes->len) - 1)));
  }
}

static rt_string * xn_Cls_CGen_methodType(xn_Cls_CGen *self, rt_string * bt, rt_string * mth, xn_Cls_AstNode * n) {
  if (xn_str_eq(bt, rt_string_from_c("AtomicInt"))) {
    if (xn_str_eq(mth, rt_string_from_c("load"))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("store"))) {
      return rt_string_from_c("Unit");
    }
    if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
      return rt_string_from_c("Bool");
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("AtomicBool"))) {
    if (xn_str_eq(mth, rt_string_from_c("load"))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("store"))) {
      return rt_string_from_c("Unit");
    }
    if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
      return rt_string_from_c("Bool");
    }
  }
  if ((xn_str_indexof(bt, rt_string_from_c("AtomicRef<")) == 0)) {
    if (xn_str_eq(mth, rt_string_from_c("load"))) {
      return xn_str_substr(bt, 10, xn_int_wrap((((int64_t)bt->len) - 11)));
    }
    if (xn_str_eq(mth, rt_string_from_c("store"))) {
      return rt_string_from_c("Unit");
    }
    if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
      return rt_string_from_c("Bool");
    }
  }
  if ((xn_str_indexof(bt, rt_string_from_c("Channel<")) == 0)) {
    rt_string * elementType = xn_str_substr(bt, 8, xn_int_wrap((((int64_t)bt->len) - 9)));
    if (xn_str_eq(mth, rt_string_from_c("send"))) {
      return rt_string_from_c("Result<void,CancelledError>");
    }
    if (xn_str_eq(mth, rt_string_from_c("receive"))) {
      return xn_concat(xn_concat(rt_string_from_c("Result<"), elementType), rt_string_from_c(",CancelledError>"));
    }
    if (xn_str_eq(mth, rt_string_from_c("close"))) {
      return rt_string_from_c("Unit");
    }
  }
  if ((xn_str_eq(bt, rt_string_from_c("Mutex")) || (xn_str_indexof(bt, rt_string_from_c("Mutex<")) == 0))) {
    if (xn_str_eq(mth, rt_string_from_c("withLock"))) {
      return rt_string_from_c("Result<void,TaskError>");
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("Context"))) {
    if (xn_str_eq(mth, rt_string_from_c("isCancelled"))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
      return rt_string_from_c("Unit");
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("TaskGroup"))) {
    if (xn_str_eq(mth, rt_string_from_c("spawn"))) {
      rt_string * exp = rt_string_from_c("Result<Int,TaskError>()");
      if ((((int64_t)n->kids->len) > 1)) {
        exp = xn_Cls_CGen_spawnLambdaType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
      }
      return xn_concat(xn_concat(rt_string_from_c("Task<"), xn_Cls_CGen_resultValue(self, xn_Cls_CGen_fnRetType(self, exp))), rt_string_from_c(">"));
    }
    if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
      return rt_string_from_c("Unit");
    }
    if (xn_str_eq(mth, rt_string_from_c("close"))) {
      return rt_string_from_c("Result<void,TaskError>");
    }
  }
  if ((xn_str_eq(bt, rt_string_from_c("Task")) || (xn_str_indexof(bt, rt_string_from_c("Task<")) == 0))) {
    if ((xn_str_eq(mth, rt_string_from_c("join")) || xn_str_eq(mth, rt_string_from_c("joinDeadline")))) {
      rt_string * et = rt_string_from_c("Int");
      if ((xn_str_indexof(bt, rt_string_from_c("Task<")) == 0)) {
        et = xn_str_substr(bt, 5, xn_int_wrap((((int64_t)bt->len) - 6)));
      }
      return xn_concat(xn_concat(rt_string_from_c("Result<"), et), rt_string_from_c(",TaskError>"));
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("String"))) {
    if ((((xn_str_eq(mth, rt_string_from_c("length")) || xn_str_eq(mth, rt_string_from_c("indexOf"))) || xn_str_eq(mth, rt_string_from_c("indexOfByte"))) || xn_str_eq(mth, rt_string_from_c("get")))) {
      return rt_string_from_c("Int");
    }
    if ((xn_str_eq(mth, rt_string_from_c("substring")) || xn_str_eq(mth, rt_string_from_c("charAt")))) {
      return rt_string_from_c("String");
    }
    if ((((xn_str_eq(mth, rt_string_from_c("trim")) || xn_str_eq(mth, rt_string_from_c("replace"))) || xn_str_eq(mth, rt_string_from_c("toUpper"))) || xn_str_eq(mth, rt_string_from_c("toLower")))) {
      return rt_string_from_c("String");
    }
    if ((xn_str_eq(mth, rt_string_from_c("startsWith")) || xn_str_eq(mth, rt_string_from_c("endsWith")))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("split"))) {
      return rt_string_from_c("List<String>");
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("Bytes"))) {
    if (xn_str_eq(mth, rt_string_from_c("fromString"))) {
      return rt_string_from_c("Bytes");
    }
    if ((xn_str_eq(mth, rt_string_from_c("length")) || xn_str_eq(mth, rt_string_from_c("get")))) {
      return rt_string_from_c("Int");
    }
    if ((xn_str_eq(mth, rt_string_from_c("slice")) || xn_str_eq(mth, rt_string_from_c("toString")))) {
      return rt_string_from_c("Bytes");
    }
    if (((xn_str_eq(mth, rt_string_from_c("set")) || xn_str_eq(mth, rt_string_from_c("append"))) || xn_str_eq(mth, rt_string_from_c("push")))) {
      return rt_string_from_c("Unit");
    }
  }
  if (xn_Cls_CGen_isSet(self, bt)) {
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("has"))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(mth, rt_string_from_c("add")) || xn_str_eq(mth, rt_string_from_c("remove")))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("clear"))) {
      return rt_string_from_c("Unit");
    }
  }
  if (xn_Cls_CGen_isResult(self, bt)) {
    if ((xn_str_eq(mth, rt_string_from_c("isOk")) || xn_str_eq(mth, rt_string_from_c("isErr")))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(mth, rt_string_from_c("value")) || xn_str_eq(mth, rt_string_from_c("unwrapOr")))) {
      return xn_Cls_CGen_resultValue(self, bt);
    }
    if (xn_str_eq(mth, rt_string_from_c("error"))) {
      return xn_Cls_CGen_resultError(self, bt);
    }
  }
  if (xn_Cls_CGen_isArray(self, bt)) {
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("get"))) {
      return xn_Cls_CGen_elementType(self, bt);
    }
    if (((((xn_str_eq(mth, rt_string_from_c("push")) || xn_str_eq(mth, rt_string_from_c("remove"))) || xn_str_eq(mth, rt_string_from_c("set"))) || xn_str_eq(mth, rt_string_from_c("insert"))) || xn_str_eq(mth, rt_string_from_c("clear")))) {
      return rt_string_from_c("Unit");
    }
    if (xn_str_eq(mth, rt_string_from_c("join"))) {
      return rt_string_from_c("String");
    }
  }
  if (xn_Cls_CGen_isMap(self, bt)) {
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return rt_string_from_c("Int");
    }
    if (xn_str_eq(mth, rt_string_from_c("has"))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(mth, rt_string_from_c("put")) || xn_str_eq(mth, rt_string_from_c("remove")))) {
      return rt_string_from_c("Bool");
    }
    if (xn_str_eq(mth, rt_string_from_c("clear"))) {
      return rt_string_from_c("Unit");
    }
    if ((xn_str_eq(mth, rt_string_from_c("getOr")) || xn_str_eq(mth, rt_string_from_c("removeOr")))) {
      return xn_Cls_CGen_mapValue(self, bt);
    }
    if (xn_str_eq(mth, rt_string_from_c("tryGet"))) {
      return xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_CGen_mapValue(self, bt)), rt_string_from_c(",Error>"));
    }
    if (xn_str_eq(mth, rt_string_from_c("keys"))) {
      return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_CGen_mapKey(self, bt)), rt_string_from_c(">"));
    }
    if (xn_str_eq(mth, rt_string_from_c("values"))) {
      return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_CGen_mapValue(self, bt)), rt_string_from_c(">"));
    }
    if (xn_str_eq(mth, rt_string_from_c("entries"))) {
      if (xn_str_eq(bt, rt_string_from_c("Map<Int,Int>"))) {
        return rt_string_from_c("List<IntPair>");
      }
      return rt_string_from_c("List<Pair>");
    }
  }
  if (xn_Cls_CGen_isProtocol(self, bt)) {
    return xn_Cls_CGen_protoRet(self, bt, mth);
  }
  return xn_Cls_CGen_methodRet(self, bt, mth);
}

static rt_string * xn_Cls_CGen_mapMethodExpr(xn_Cls_CGen *self, rt_string * bv, rt_string * bt, rt_string * mth, xn_Cls_AstNode * n, int64_t off, int useOff) {
  int64_t base = xn_int_wrap(0);
  if (useOff) {
    base = off;
  }
  int64_t argc = xn_int_wrap(xn_int_wrap((((int64_t)n->kids->len) - base)));
  int genericMap = xn_Cls_CGen_isGenericMap(self, bt);
  rt_string * keyTy = xn_Cls_CGen_mapKey(self, bt);
  rt_string * valTy = xn_Cls_CGen_mapValue(self, bt);
  if (genericMap) {
    if ((xn_str_eq(xn_Cls_CGen_kindOf(self, keyTy), rt_string_from_c("-1")) || xn_str_eq(xn_Cls_CGen_kindOf(self, valTy), rt_string_from_c("-1")))) {
      xn_Cls_CGen_fail(self, xn_concat(rt_string_from_c("generic Map does not support key/value type: "), bt));
      return rt_string_from_c("0");
    }
    xn_Cls_CGen_registerGenericMap(self, bt);
  }
  rt_string * mapPrefix = rt_string_from_c("");
  if (xn_str_eq(bt, rt_string_from_c("Map<String,Int>"))) {
    mapPrefix = rt_string_from_c("xn_map_s_i_");
  }
  else {
    if (xn_str_eq(bt, rt_string_from_c("Map<Int,Int>"))) {
      mapPrefix = rt_string_from_c("xn_map_i_i_");
    }
  }
  if (xn_str_eq(mth, rt_string_from_c("length"))) {
    return xn_concat(xn_concat(rt_string_from_c("((int64_t)"), bv), rt_string_from_c("->len)"));
  }
  if ((xn_str_eq(mth, rt_string_from_c("has")) && (argc >= 1))) {
    rt_string * key = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, base)));
    if (genericMap) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_map_g_has("), bv), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, keyTy, key)), rt_string_from_c(")"));
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(mapPrefix, rt_string_from_c("has(")), bv), rt_string_from_c(", ")), key), rt_string_from_c(")"));
  }
  if ((xn_str_eq(mth, rt_string_from_c("put")) && (argc >= 2))) {
    rt_string * key = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, base)));
    rt_string * val = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((base + 1)))));
    if (genericMap) {
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_map_g_put_replaced("), bv), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, keyTy, key)), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, valTy, val)), rt_string_from_c(")"));
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(mapPrefix, rt_string_from_c("put_replaced(")), bv), rt_string_from_c(", ")), key), rt_string_from_c(", ")), val), rt_string_from_c(")"));
  }
  if ((xn_str_eq(mth, rt_string_from_c("getOr")) && (argc >= 2))) {
    rt_string * key = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, base)));
    rt_string * fallback = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((base + 1)))));
    if (genericMap) {
      return xn_Cls_CGen_decodeOf(self, valTy, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_map_g_getOr("), bv), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, keyTy, key)), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, valTy, fallback)), rt_string_from_c(")")));
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(mapPrefix, rt_string_from_c("getOr(")), bv), rt_string_from_c(", ")), key), rt_string_from_c(", ")), fallback), rt_string_from_c(")"));
  }
  if ((xn_str_eq(mth, rt_string_from_c("remove")) && (argc >= 1))) {
    rt_string * key = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, base)));
    if (genericMap) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_map_g_remove("), bv), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, keyTy, key)), rt_string_from_c(")"));
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(mapPrefix, rt_string_from_c("remove(")), bv), rt_string_from_c(", ")), key), rt_string_from_c(")"));
  }
  if ((xn_str_eq(mth, rt_string_from_c("removeOr")) && (argc >= 2))) {
    rt_string * key = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, base)));
    rt_string * fallback = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((base + 1)))));
    if (genericMap) {
      return xn_Cls_CGen_decodeOf(self, valTy, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_map_g_remove_value("), bv), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, keyTy, key)), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, valTy, fallback)), rt_string_from_c(")")));
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(mapPrefix, rt_string_from_c("remove_value(")), bv), rt_string_from_c(", ")), key), rt_string_from_c(", ")), fallback), rt_string_from_c(")"));
  }
  if ((xn_str_eq(mth, rt_string_from_c("tryGet")) && (argc >= 1))) {
    rt_string * key = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, base)));
    rt_string * err = rt_string_from_c("(xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(1, \"tryGet: key not found\") }");
    if (genericMap) {
      rt_string * stored = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_map_g_getOr("), bv), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, keyTy, key)), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, valTy, rt_string_from_c("0"))), rt_string_from_c(")"));
      rt_string * ok = xn_concat(xn_concat(rt_string_from_c("(xn_Result){ .ok = 1, "), xn_Cls_CGen_resultInitField(self, xn_concat(xn_concat(rt_string_from_c("Result<"), valTy), rt_string_from_c(",Error>")), xn_Cls_CGen_decodeOf(self, valTy, stored))), rt_string_from_c(" }"));
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(xn_map_g_has("), bv), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, keyTy, key)), rt_string_from_c(") ? ")), ok), rt_string_from_c(" : ")), err), rt_string_from_c(")"));
    }
    rt_string * ok = xn_concat(xn_concat(rt_string_from_c("(xn_Result){ .ok = 1, "), xn_Cls_CGen_resultInitField(self, xn_concat(xn_concat(rt_string_from_c("Result<"), valTy), rt_string_from_c(",Error>")), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(mapPrefix, rt_string_from_c("getOr(")), bv), rt_string_from_c(", ")), key), rt_string_from_c(", 0)")))), rt_string_from_c(" }"));
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("("), mapPrefix), rt_string_from_c("has(")), bv), rt_string_from_c(", ")), key), rt_string_from_c(") ? ")), ok), rt_string_from_c(" : ")), err), rt_string_from_c(")"));
  }
  if (xn_str_eq(mth, rt_string_from_c("keys"))) {
    if (genericMap) {
      return xn_concat(xn_concat(xn_concat(xn_Cls_CGen_genericMapKeysName(self, bt), rt_string_from_c("(")), bv), rt_string_from_c(")"));
    }
    return xn_concat(xn_concat(xn_concat(mapPrefix, rt_string_from_c("keys(")), bv), rt_string_from_c(")"));
  }
  if (xn_str_eq(mth, rt_string_from_c("values"))) {
    if (genericMap) {
      return xn_concat(xn_concat(xn_concat(xn_Cls_CGen_genericMapValuesName(self, bt), rt_string_from_c("(")), bv), rt_string_from_c(")"));
    }
    return xn_concat(xn_concat(xn_concat(mapPrefix, rt_string_from_c("values(")), bv), rt_string_from_c(")"));
  }
  if (xn_str_eq(mth, rt_string_from_c("entries"))) {
    if (xn_str_eq(bt, rt_string_from_c("Map<String,Int>"))) {
      return xn_concat(xn_concat(rt_string_from_c("xn_map_s_i_entries("), bv), rt_string_from_c(")"));
    }
    if (xn_str_eq(bt, rt_string_from_c("Map<Int,Int>"))) {
      return xn_concat(xn_concat(rt_string_from_c("xn_map_i_i_entries("), bv), rt_string_from_c(")"));
    }
    return xn_concat(xn_concat(xn_concat(xn_Cls_CGen_genericMapEntriesName(self, bt), rt_string_from_c("(")), bv), rt_string_from_c(")"));
  }
  if (xn_str_eq(mth, rt_string_from_c("clear"))) {
    return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c("->len = 0)"));
  }
  return rt_string_from_c("0");
}

static rt_string * xn_Cls_CGen_setMethodExpr(xn_Cls_CGen *self, rt_string * bv, rt_string * bt, rt_string * mth, xn_Cls_AstNode * n, int64_t off, int useOff) {
  int64_t base = xn_int_wrap(0);
  if (useOff) {
    base = off;
  }
  int64_t argc = xn_int_wrap(xn_int_wrap((((int64_t)n->kids->len) - base)));
  int genericSet = xn_Cls_CGen_isGenericSet(self, bt);
  rt_string * elemTy = xn_Cls_CGen_setElementOf(self, bt);
  if (genericSet) {
    if (xn_str_eq(xn_Cls_CGen_kindOf(self, elemTy), rt_string_from_c("-1"))) {
      xn_Cls_CGen_fail(self, xn_concat(rt_string_from_c("generic Set does not support element type: "), bt));
      return rt_string_from_c("0");
    }
    xn_Cls_CGen_registerGenericSet(self, bt);
  }
  rt_string * setPrefix = rt_string_from_c("");
  if (xn_str_eq(bt, rt_string_from_c("Set<Int>"))) {
    setPrefix = rt_string_from_c("xn_set_i_");
  }
  else {
    if (xn_str_eq(bt, rt_string_from_c("Set<String>"))) {
      setPrefix = rt_string_from_c("xn_set_s_");
    }
  }
  if (xn_str_eq(mth, rt_string_from_c("length"))) {
    return xn_concat(xn_concat(rt_string_from_c("((int64_t)"), bv), rt_string_from_c("->len)"));
  }
  if ((xn_str_eq(mth, rt_string_from_c("has")) && (argc >= 1))) {
    rt_string * v = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, base)));
    if (genericSet) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_set_g_has("), bv), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, elemTy, v)), rt_string_from_c(")"));
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(setPrefix, rt_string_from_c("has(")), bv), rt_string_from_c(", ")), v), rt_string_from_c(")"));
  }
  if ((xn_str_eq(mth, rt_string_from_c("add")) && (argc >= 1))) {
    rt_string * v = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, base)));
    if (genericSet) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_set_g_add("), bv), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, elemTy, v)), rt_string_from_c(")"));
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(setPrefix, rt_string_from_c("add(")), bv), rt_string_from_c(", ")), v), rt_string_from_c(")"));
  }
  if ((xn_str_eq(mth, rt_string_from_c("remove")) && (argc >= 1))) {
    rt_string * v = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, base)));
    if (genericSet) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_set_g_remove("), bv), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, elemTy, v)), rt_string_from_c(")"));
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(setPrefix, rt_string_from_c("remove(")), bv), rt_string_from_c(", ")), v), rt_string_from_c(")"));
  }
  if (xn_str_eq(mth, rt_string_from_c("clear"))) {
    return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c("->len = 0)"));
  }
  return rt_string_from_c("0");
}

static rt_string * xn_Cls_CGen_methodExpr(xn_Cls_CGen *self, rt_string * bv, rt_string * bt, rt_string * mth, xn_Cls_AstNode * n, int64_t off) {
  if (xn_str_eq(bt, rt_string_from_c("AtomicInt"))) {
    if (xn_str_eq(mth, rt_string_from_c("load"))) {
      return xn_concat(xn_concat(rt_string_from_c("xrt_atomic_int_load("), bv), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("store"))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_atomic_int_store("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(")"));
    }
    if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((xrt_atomic_int_cas("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((off + 1)))))), rt_string_from_c(") != 0) ? 1 : 0)"));
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("AtomicBool"))) {
    if (xn_str_eq(mth, rt_string_from_c("load"))) {
      return xn_concat(xn_concat(rt_string_from_c("xrt_atomic_bool_load("), bv), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("store"))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_atomic_bool_store("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(")"));
    }
    if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((xrt_atomic_bool_cas("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((off + 1)))))), rt_string_from_c(") != 0) ? 1 : 0)"));
    }
  }
  if ((xn_str_indexof(bt, rt_string_from_c("AtomicRef<")) == 0)) {
    if (xn_str_eq(mth, rt_string_from_c("load"))) {
      return xn_concat(xn_concat(rt_string_from_c("((rt_string *)xrt_atomic_ref_load("), bv), rt_string_from_c("))"));
    }
    if (xn_str_eq(mth, rt_string_from_c("store"))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_atomic_ref_store("), bv), rt_string_from_c(", (void *)(")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c("))"));
    }
    if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((xrt_atomic_ref_cas("), bv), rt_string_from_c(", (void *)(")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c("), (void *)(")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((off + 1)))))), rt_string_from_c(")) != 0) ? 1 : 0)"));
    }
  }
  if ((xn_str_indexof(bt, rt_string_from_c("Channel<")) == 0)) {
    rt_string * elementType = xn_str_substr(bt, 8, xn_int_wrap((((int64_t)bt->len) - 9)));
    if (xn_str_eq(mth, rt_string_from_c("send"))) {
      if (xn_str_eq(elementType, rt_string_from_c("Int"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_int("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
      }
      if (xn_str_eq(elementType, rt_string_from_c("Double"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_double("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
      }
      if (xn_str_eq(elementType, rt_string_from_c("Int128"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_int128("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
      }
      if (xn_str_eq(elementType, rt_string_from_c("Result<Int,String>"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_result_is("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
      }
      if (xn_Cls_CGen_isResult(self, elementType)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_result("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_ptr("), bv), rt_string_from_c(", (void *)(")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c("), ")), self->curCtxExpr), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("receive"))) {
      if (xn_str_eq(elementType, rt_string_from_c("Int"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_int("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
      }
      if (xn_str_eq(elementType, rt_string_from_c("Double"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_double("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
      }
      if (xn_str_eq(elementType, rt_string_from_c("Int128"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_int128("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
      }
      if (xn_str_eq(elementType, rt_string_from_c("Result<Int,String>"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_result_is("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
      }
      if (xn_Cls_CGen_isResult(self, elementType)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_result("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_ptr("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("close"))) {
      return xn_concat(xn_concat(rt_string_from_c("xrt_channel_close("), bv), rt_string_from_c(")"));
    }
  }
  if ((xn_str_eq(bt, rt_string_from_c("Mutex")) || (xn_str_indexof(bt, rt_string_from_c("Mutex<")) == 0))) {
    if ((xn_str_eq(mth, rt_string_from_c("withLock")) && (((int64_t)n->kids->len) > off))) {
      xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off));
      int64_t li = xn_int_wrap(xn_Cls_CGen_lambdaIndex(self, lam));
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_mutex_lock("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, lam)), rt_string_from_c(", xn_lock_body_")), xn_str_int(li)), rt_string_from_c(")"));
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("Context"))) {
    if (xn_str_eq(mth, rt_string_from_c("isCancelled"))) {
      return xn_concat(xn_concat(rt_string_from_c("xrt_context_cancelled("), bv), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
      return xn_concat(xn_concat(rt_string_from_c("xrt_context_cancel("), bv), rt_string_from_c(")"));
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("TaskGroup"))) {
    if ((xn_str_eq(mth, rt_string_from_c("spawn")) && (((int64_t)n->kids->len) > off))) {
      xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off));
      int64_t li = xn_int_wrap(xn_Cls_CGen_lambdaIndex(self, lam));
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_task_spawn("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, lam)), rt_string_from_c(", xn_task_body_")), xn_str_int(li)), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
      return xn_concat(xn_concat(rt_string_from_c("xrt_task_group_cancel("), bv), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("close"))) {
      return xn_concat(xn_concat(rt_string_from_c("xn_task_group_close("), bv), rt_string_from_c(")"));
    }
  }
  if ((xn_str_eq(bt, rt_string_from_c("Task")) || (xn_str_indexof(bt, rt_string_from_c("Task<")) == 0))) {
    if (xn_str_eq(mth, rt_string_from_c("join"))) {
      return xn_concat(xn_concat(rt_string_from_c("xn_task_join("), bv), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("joinDeadline"))) {
      rt_string * dl = rt_string_from_c("0");
      if ((((int64_t)n->kids->len) > off)) {
        dl = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_task_join_deadline("), bv), rt_string_from_c(", ")), dl), rt_string_from_c(")"));
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("Bytes"))) {
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return xn_concat(xn_concat(rt_string_from_c("((int64_t)xrt_bytes_len("), bv), rt_string_from_c("))"));
    }
    if (xn_str_eq(mth, rt_string_from_c("get"))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((int64_t)xrt_bytes_get("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c("))"));
    }
    if (xn_str_eq(mth, rt_string_from_c("slice"))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_bytes_slice("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((off + 1)))))), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("set"))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_bytes_set("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((off + 1)))))), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("append"))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_bytes_append("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("push"))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_bytes_push("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("toString"))) {
      return xn_concat(xn_concat(rt_string_from_c("xn_bytes_to_string("), bv), rt_string_from_c(")"));
    }
  }
  if (xn_str_eq(bt, rt_string_from_c("String"))) {
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return xn_concat(xn_concat(rt_string_from_c("((int64_t)"), bv), rt_string_from_c("->len)"));
    }
    if (xn_str_eq(mth, rt_string_from_c("get"))) {
      if ((((int64_t)n->kids->len) > off)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((int64_t)(unsigned char)"), bv), rt_string_from_c("->bytes[")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c("])"));
      }
      return rt_string_from_c("0");
    }
    if ((xn_str_eq(mth, rt_string_from_c("indexOf")) || xn_str_eq(mth, rt_string_from_c("indexOfByte")))) {
      if ((((int64_t)n->kids->len) > off)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_indexof("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(")"));
      }
      return rt_string_from_c("-1");
    }
    if (xn_str_eq(mth, rt_string_from_c("substring"))) {
      if ((((int64_t)n->kids->len) > xn_int_wrap((off + 1)))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_substr("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((off + 1)))))), rt_string_from_c(")"));
      }
      return rt_string_from_c("rt_string_from_c(\"\")");
    }
    if (xn_str_eq(mth, rt_string_from_c("charAt"))) {
      if ((((int64_t)n->kids->len) > off)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_substr("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", 1)"));
      }
      return rt_string_from_c("rt_string_from_c(\"\")");
    }
    if (xn_str_eq(mth, rt_string_from_c("trim"))) {
      return xn_concat(xn_concat(rt_string_from_c("xn_str_trim("), bv), rt_string_from_c(")"));
    }
    if ((xn_str_eq(mth, rt_string_from_c("toUpper")) || xn_str_eq(mth, rt_string_from_c("toLower")))) {
      rt_string * up = rt_string_from_c("0");
      if (xn_str_eq(mth, rt_string_from_c("toUpper"))) {
        up = rt_string_from_c("1");
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_case("), bv), rt_string_from_c(", ")), up), rt_string_from_c(")"));
    }
    if ((xn_str_eq(mth, rt_string_from_c("replace")) && (((int64_t)n->kids->len) > xn_int_wrap((off + 1))))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_replace("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((off + 1)))))), rt_string_from_c(")"));
    }
    if (xn_str_eq(mth, rt_string_from_c("startsWith"))) {
      if ((((int64_t)n->kids->len) > off)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_startswith("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(")"));
      }
      return rt_string_from_c("0");
    }
    if (xn_str_eq(mth, rt_string_from_c("endsWith"))) {
      if ((((int64_t)n->kids->len) > off)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_endswith("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(")"));
      }
      return rt_string_from_c("0");
    }
    if (xn_str_eq(mth, rt_string_from_c("split"))) {
      if ((((int64_t)n->kids->len) > off)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_split("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(")"));
      }
      return rt_string_from_c("xn_arr_s_new(4)");
    }
  }
  if (xn_Cls_CGen_isSet(self, bt)) {
    return xn_Cls_CGen_setMethodExpr(self, bv, bt, mth, n, off, 1);
  }
  if (xn_Cls_CGen_isResult(self, bt)) {
    if (xn_str_eq(mth, rt_string_from_c("isOk"))) {
      return xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").ok != 0)"));
    }
    if (xn_str_eq(mth, rt_string_from_c("isErr"))) {
      return xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").ok == 0)"));
    }
    if (xn_str_eq(mth, rt_string_from_c("value"))) {
      if (xn_Cls_CGen_isGenericResult(self, bt)) {
        return xn_Cls_CGen_resultValueCExpr(self, bt, bv);
      }
      return xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").value)"));
    }
    if (xn_str_eq(mth, rt_string_from_c("error"))) {
      if (xn_Cls_CGen_isGenericResult(self, bt)) {
        return xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").err)"));
      }
      return xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").error)"));
    }
    if (xn_str_eq(mth, rt_string_from_c("unwrapOr"))) {
      rt_string * d = rt_string_from_c("0");
      if ((((int64_t)n->kids->len) > off)) {
        d = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)));
      }
      if (xn_Cls_CGen_isGenericResult(self, bt)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").ok ? ")), xn_Cls_CGen_resultValueExpr(self, bt, bv)), rt_string_from_c(" : ")), d), rt_string_from_c(")"));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").ok ? (")), bv), rt_string_from_c(").value : ")), d), rt_string_from_c(")"));
    }
  }
  if (xn_Cls_CGen_isArray(self, bt)) {
    if (xn_str_eq(mth, rt_string_from_c("length"))) {
      return xn_concat(xn_concat(rt_string_from_c("((int64_t)"), bv), rt_string_from_c("->len)"));
    }
    if (xn_str_eq(mth, rt_string_from_c("get"))) {
      if ((((int64_t)n->kids->len) > off)) {
        return xn_Cls_CGen_arrayGet(self, bt, bv, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off))));
      }
      return rt_string_from_c("0");
    }
    if (xn_str_eq(mth, rt_string_from_c("push"))) {
      if ((((int64_t)n->kids->len) > off)) {
        return xn_Cls_CGen_arrayPush(self, bt, bv, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off))));
      }
      return rt_string_from_c("0");
    }
    if (xn_str_eq(mth, rt_string_from_c("set"))) {
      if ((((int64_t)n->kids->len) > xn_int_wrap((off + 1)))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_set(")), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((off + 1)))))), rt_string_from_c(")"));
      }
      return rt_string_from_c("0");
    }
    if (xn_str_eq(mth, rt_string_from_c("insert"))) {
      if ((((int64_t)n->kids->len) > xn_int_wrap((off + 1)))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_insert(")), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((off + 1)))))), rt_string_from_c(")"));
      }
      return rt_string_from_c("0");
    }
    if (xn_str_eq(mth, rt_string_from_c("remove"))) {
      if ((((int64_t)n->kids->len) > off)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_remove(")), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(")"));
      }
      return rt_string_from_c("0");
    }
    if (xn_str_eq(mth, rt_string_from_c("join"))) {
      if ((((int64_t)n->kids->len) > off)) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_arr_s_join("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)))), rt_string_from_c(")"));
      }
      return rt_string_from_c("rt_string_from_c(\"\")");
    }
    if (xn_str_eq(mth, rt_string_from_c("clear"))) {
      return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c("->len = 0)"));
    }
    if ((xn_str_eq(mth, rt_string_from_c("tryGet")) && (((int64_t)n->kids->len) > off))) {
      rt_string * index = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)));
      rt_string * resultTy = xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_CGen_elementType(self, bt)), rt_string_from_c(",Error>"));
      rt_string * ok = xn_concat(xn_concat(rt_string_from_c("(xn_Result){ .ok = 1, "), xn_Cls_CGen_resultInitField(self, resultTy, xn_Cls_CGen_arrayGet(self, bt, bv, index))), rt_string_from_c(" }"));
      rt_string * err = rt_string_from_c("(xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, \"tryGet: index out of range\") }");
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), index), rt_string_from_c(" >= 0 && ")), index), rt_string_from_c(" < (int64_t)")), bv), rt_string_from_c("->len) ? ")), ok), rt_string_from_c(" : ")), err), rt_string_from_c(")"));
    }
    if ((xn_str_eq(mth, rt_string_from_c("tryRemove")) && (((int64_t)n->kids->len) > off))) {
      rt_string * index = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)));
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_try_remove(")), bv), rt_string_from_c(", ")), index), rt_string_from_c(")"));
    }
    if (((xn_str_eq(mth, rt_string_from_c("trySet")) || xn_str_eq(mth, rt_string_from_c("tryInsert"))) && (((int64_t)n->kids->len) > xn_int_wrap((off + 1))))) {
      rt_string * index = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, off)));
      rt_string * value = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, xn_int_wrap((off + 1)))));
      rt_string * call = rt_string_from_c("");
      if (xn_str_eq(mth, rt_string_from_c("trySet"))) {
        call = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_set(")), bv), rt_string_from_c(", ")), index), rt_string_from_c(", ")), value), rt_string_from_c(")"));
      }
      else {
        call = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_insert(")), bv), rt_string_from_c(", ")), index), rt_string_from_c(", ")), value), rt_string_from_c(")"));
      }
      rt_string * bound = rt_string_from_c(" < ");
      if (xn_str_eq(mth, rt_string_from_c("tryInsert"))) {
        bound = rt_string_from_c(" <= ");
      }
      rt_string * err = xn_concat(xn_concat(rt_string_from_c("(xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, \""), mth), rt_string_from_c(": index out of range\") }"));
      return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), index), rt_string_from_c(" >= 0 && ")), index), bound), rt_string_from_c("(int64_t)")), bv), rt_string_from_c("->len) ? (")), call), rt_string_from_c(", (xn_Result){ .ok = 1 }) : ")), err), rt_string_from_c(")"));
    }
  }
  if (xn_Cls_CGen_isMap(self, bt)) {
    return xn_Cls_CGen_mapMethodExpr(self, bv, bt, mth, n, off, 1);
  }
  if (xn_Cls_CGen_isProtocol(self, bt)) {
    rt_string * pb = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_proto_"), bt), rt_string_from_c("_")), mth), rt_string_from_c("(")), bv);
    int64_t pi = xn_int_wrap(off);
    while ((pi < ((int64_t)n->kids->len))) {
      pb = xn_concat(xn_concat(pb, rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, pi))));
      pi = xn_int_wrap((pi + 1));
    }
    return xn_concat(pb, rt_string_from_c(")"));
  }
  rt_string * b = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_Cls_"), bt), rt_string_from_c("_")), mth), rt_string_from_c("(")), bv);
  int64_t i = xn_int_wrap(off);
  while ((i < ((int64_t)n->kids->len))) {
    b = xn_concat(xn_concat(b, rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i))));
    i = xn_int_wrap((i + 1));
  }
  return xn_concat(b, rt_string_from_c(")"));
}

static rt_string * xn_Cls_CGen_fnRet(xn_Cls_CGen *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Func")) && xn_str_eq(n->text, name))) {
      return xn_Cls_CGen_retNode(self, n)->text;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_Cls_CGen_typeOf(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Int"))) {
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Double"))) {
    return rt_string_from_c("Double");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    return rt_string_from_c("String");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Null"))) {
    return rt_string_from_c("Null");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Bool"))) {
    return rt_string_from_c("Bool");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Char"))) {
    return rt_string_from_c("Char");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Lambda"))) {
    int64_t li = xn_int_wrap(xn_Cls_CGen_lambdaIndex(self, n));
    if ((li >= 0)) {
      return xn_arr_s_get(self->lambdaTypes, li);
    }
    return rt_string_from_c("Any");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Ternary"))) {
    if ((((int64_t)n->kids->len) < 3)) {
      return rt_string_from_c("Any");
    }
    return xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Cast"))) {
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Is"))) {
    return rt_string_from_c("Bool");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Unary"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("Any");
    }
    if (xn_str_eq(n->text, rt_string_from_c("!"))) {
      return rt_string_from_c("Bool");
    }
    return xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("ArrayLit"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("Int[]");
    }
    return xn_concat(xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("[]"));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("MapLit"))) {
    if ((((int64_t)n->kids->len) >= 2)) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("Map<"), xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(",")), xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(">"));
    }
    return rt_string_from_c("Map<String,Int>");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Index"))) {
    if ((((int64_t)n->kids->len) < 2)) {
      return rt_string_from_c("Any");
    }
    return xn_Cls_CGen_elementType(self, xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Name"))) {
    if (xn_Cls_CGen_isEnumName(self, n->text)) {
      return n->text;
    }
    if ((xn_str_eq(n->text, rt_string_from_c("self")) && (!xn_str_eq(self->curClass, rt_string_from_c(""))))) {
      return self->curClass;
    }
    rt_string * vt = xn_Cls_CGen_findVar(self, n->text);
    if ((!xn_str_eq(vt, rt_string_from_c("Any")))) {
      return vt;
    }
    rt_string * ft = xn_Cls_CGen_curFieldType(self, n->text);
    if ((!xn_str_eq(ft, rt_string_from_c("Any")))) {
      return ft;
    }
    return xn_Cls_CGen_topFieldType(self, n->text);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("New"))) {
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Binary"))) {
    if ((((((((xn_str_eq(n->text, rt_string_from_c("==")) || xn_str_eq(n->text, rt_string_from_c("!="))) || xn_str_eq(n->text, rt_string_from_c("<"))) || xn_str_eq(n->text, rt_string_from_c("<="))) || xn_str_eq(n->text, rt_string_from_c(">"))) || xn_str_eq(n->text, rt_string_from_c(">="))) || xn_str_eq(n->text, rt_string_from_c("&&"))) || xn_str_eq(n->text, rt_string_from_c("||")))) {
      return rt_string_from_c("Bool");
    }
    if ((xn_str_eq(n->text, rt_string_from_c("+")) && xn_str_eq(xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("String")))) {
      return rt_string_from_c("String");
    }
    if ((xn_str_eq(xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("Double")) || xn_str_eq(xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1))), rt_string_from_c("Double")))) {
      return rt_string_from_c("Double");
    }
    rt_string * leftType = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    rt_string * rightType = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
    if ((xn_str_eq(leftType, rt_string_from_c("Int128")) || xn_str_eq(rightType, rt_string_from_c("Int128")))) {
      return rt_string_from_c("Int128");
    }
    if ((((((xn_str_eq(leftType, rt_string_from_c("Long")) || xn_str_eq(leftType, rt_string_from_c("Int64"))) || xn_str_eq(leftType, rt_string_from_c("Int32"))) || xn_str_eq(rightType, rt_string_from_c("Long"))) || xn_str_eq(rightType, rt_string_from_c("Int64"))) || xn_str_eq(rightType, rt_string_from_c("Int32")))) {
      return rt_string_from_c("Long");
    }
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Try"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("Any");
    }
    return xn_Cls_CGen_resultValue(self, xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("MethodCall"))) {
    if ((((int64_t)n->kids->len) < 1)) {
      return rt_string_from_c("Any");
    }
    return xn_Cls_CGen_methodType(self, xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), n->text, n);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
    if ((xn_str_eq(n->text, rt_string_from_c("readFile")) || xn_str_eq(n->text, rt_string_from_c("listFiles")))) {
      return rt_string_from_c("String");
    }
    if (((((xn_str_eq(n->text, rt_string_from_c("diagnoseRaw")) || xn_str_eq(n->text, rt_string_from_c("exitRaw"))) || xn_str_eq(n->text, rt_string_from_c("resourceExistsRaw"))) || xn_str_eq(n->text, rt_string_from_c("resourceCountRaw"))) || xn_str_eq(n->text, rt_string_from_c("fileExistsRaw")))) {
      return rt_string_from_c("Int");
    }
    if ((xn_str_eq(n->text, rt_string_from_c("nowMonoRaw")) || xn_str_eq(n->text, rt_string_from_c("nowWallRaw")))) {
      return rt_string_from_c("Long");
    }
    if (((xn_str_eq(n->text, rt_string_from_c("readResourceTextRaw")) || xn_str_eq(n->text, rt_string_from_c("platformRaw"))) || xn_str_eq(n->text, rt_string_from_c("str")))) {
      return rt_string_from_c("String");
    }
    if (xn_str_eq(n->text, rt_string_from_c("Set.of"))) {
      if ((((int64_t)n->kids->len) == 0)) {
        return rt_string_from_c("Set<Int>");
      }
      xn_Cls_AstNode * firstSetArg = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
      rt_string * setElem = xn_Cls_CGen_typeOf(self, firstSetArg);
      if ((xn_str_eq(firstSetArg->kind, rt_string_from_c("Int")) && (!xn_Cls_CGen_intLiteralFits32(self, firstSetArg->text)))) {
        setElem = rt_string_from_c("Long");
      }
      if ((((xn_str_eq(firstSetArg->kind, rt_string_from_c("Unary")) && (((int64_t)firstSetArg->kids->len) > 0)) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(firstSetArg->kids, 0))->kind, rt_string_from_c("Int"))) && (!xn_Cls_CGen_intLiteralFits32(self, ((xn_Cls_AstNode *)xn_arr_o_get(firstSetArg->kids, 0))->text)))) {
        setElem = rt_string_from_c("Long");
      }
      return xn_concat(xn_concat(rt_string_from_c("Set<"), setElem), rt_string_from_c(">"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("Mutex"))) {
      if ((((int64_t)n->kids->len) > 0)) {
        return xn_concat(xn_concat(rt_string_from_c("Mutex<"), xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(">"));
      }
      return rt_string_from_c("Mutex<Int>");
    }
    if (xn_str_eq(n->text, rt_string_from_c("Context.background"))) {
      return rt_string_from_c("Context");
    }
    if (xn_str_eq(n->text, rt_string_from_c("TaskGroup.create"))) {
      return rt_string_from_c("TaskGroup");
    }
    if ((xn_ffiIndex(n->text) >= 0)) {
      return xn_ffiRet(n->text);
    }
    if ((xn_str_eq(n->text, rt_string_from_c("Ok")) || xn_str_eq(n->text, rt_string_from_c("Err")))) {
      return self->curRet;
    }
    if (xn_str_eq(n->text, rt_string_from_c("print"))) {
      return rt_string_from_c("Unit");
    }
    int64_t fvi = xn_int_wrap(xn_Cls_CGen_varIndex(self, n->text));
    if (((fvi >= 0) && xn_Cls_CGen_isFunctionType(self, xn_arr_s_get(self->varTypes, fvi)))) {
      return xn_Cls_CGen_fnRetType(self, xn_arr_s_get(self->varTypes, fvi));
    }
    int64_t dot = xn_int_wrap(xn_lastDot(n->text));
    if ((dot >= 0)) {
      rt_string * base = xn_str_substr(n->text, 0, dot);
      rt_string * mth = xn_str_substr(n->text, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)n->text->len) - dot)) - 1)));
      rt_string * bt = xn_Cls_CGen_pathType(self, base);
      if (xn_str_eq(bt, rt_string_from_c("AtomicInt"))) {
        if (xn_str_eq(mth, rt_string_from_c("load"))) {
          return rt_string_from_c("Int");
        }
        if (xn_str_eq(mth, rt_string_from_c("store"))) {
          return rt_string_from_c("Unit");
        }
        if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
          return rt_string_from_c("Bool");
        }
      }
      if (xn_str_eq(bt, rt_string_from_c("AtomicBool"))) {
        if (xn_str_eq(mth, rt_string_from_c("load"))) {
          return rt_string_from_c("Bool");
        }
        if (xn_str_eq(mth, rt_string_from_c("store"))) {
          return rt_string_from_c("Unit");
        }
        if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
          return rt_string_from_c("Bool");
        }
      }
      if ((xn_str_indexof(bt, rt_string_from_c("AtomicRef<")) == 0)) {
        if (xn_str_eq(mth, rt_string_from_c("load"))) {
          return xn_str_substr(bt, 10, xn_int_wrap((((int64_t)bt->len) - 11)));
        }
        if (xn_str_eq(mth, rt_string_from_c("store"))) {
          return rt_string_from_c("Unit");
        }
        if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
          return rt_string_from_c("Bool");
        }
      }
      if ((xn_str_indexof(bt, rt_string_from_c("Channel<")) == 0)) {
        rt_string * elementType = xn_str_substr(bt, 8, xn_int_wrap((((int64_t)bt->len) - 9)));
        if (xn_str_eq(mth, rt_string_from_c("send"))) {
          return rt_string_from_c("Result<void,CancelledError>");
        }
        if (xn_str_eq(mth, rt_string_from_c("receive"))) {
          return xn_concat(xn_concat(rt_string_from_c("Result<"), elementType), rt_string_from_c(",CancelledError>"));
        }
        if (xn_str_eq(mth, rt_string_from_c("close"))) {
          return rt_string_from_c("Unit");
        }
      }
      if ((xn_str_eq(bt, rt_string_from_c("Mutex")) || (xn_str_indexof(bt, rt_string_from_c("Mutex<")) == 0))) {
        if (xn_str_eq(mth, rt_string_from_c("withLock"))) {
          return rt_string_from_c("Result<void,TaskError>");
        }
      }
      if (xn_str_eq(bt, rt_string_from_c("Context"))) {
        if (xn_str_eq(mth, rt_string_from_c("isCancelled"))) {
          return rt_string_from_c("Bool");
        }
        if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
          return rt_string_from_c("Unit");
        }
      }
      if (xn_str_eq(bt, rt_string_from_c("TaskGroup"))) {
        if (xn_str_eq(mth, rt_string_from_c("spawn"))) {
          rt_string * exp = rt_string_from_c("Result<Int,TaskError>()");
          if ((((int64_t)n->kids->len) > 0)) {
            exp = xn_Cls_CGen_spawnLambdaType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
          }
          return xn_concat(xn_concat(rt_string_from_c("Task<"), xn_Cls_CGen_resultValue(self, xn_Cls_CGen_fnRetType(self, exp))), rt_string_from_c(">"));
        }
        if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
          return rt_string_from_c("Unit");
        }
        if (xn_str_eq(mth, rt_string_from_c("close"))) {
          return rt_string_from_c("Result<void,TaskError>");
        }
      }
      if ((xn_str_eq(bt, rt_string_from_c("Task")) || (xn_str_indexof(bt, rt_string_from_c("Task<")) == 0))) {
        if ((xn_str_eq(mth, rt_string_from_c("join")) || xn_str_eq(mth, rt_string_from_c("joinDeadline")))) {
          rt_string * et = rt_string_from_c("Int");
          if ((xn_str_indexof(bt, rt_string_from_c("Task<")) == 0)) {
            et = xn_str_substr(bt, 5, xn_int_wrap((((int64_t)bt->len) - 6)));
          }
          return xn_concat(xn_concat(rt_string_from_c("Result<"), et), rt_string_from_c(",TaskError>"));
        }
      }
      if (xn_str_eq(bt, rt_string_from_c("Bytes"))) {
        if (xn_str_eq(mth, rt_string_from_c("fromString"))) {
          return rt_string_from_c("Bytes");
        }
        if ((xn_str_eq(mth, rt_string_from_c("length")) || xn_str_eq(mth, rt_string_from_c("get")))) {
          return rt_string_from_c("Int");
        }
        if ((xn_str_eq(mth, rt_string_from_c("slice")) || xn_str_eq(mth, rt_string_from_c("toString")))) {
          return rt_string_from_c("Bytes");
        }
        if (((xn_str_eq(mth, rt_string_from_c("set")) || xn_str_eq(mth, rt_string_from_c("append"))) || xn_str_eq(mth, rt_string_from_c("push")))) {
          return rt_string_from_c("Unit");
        }
      }
      if (xn_str_eq(bt, rt_string_from_c("String"))) {
        if ((((xn_str_eq(mth, rt_string_from_c("length")) || xn_str_eq(mth, rt_string_from_c("indexOf"))) || xn_str_eq(mth, rt_string_from_c("indexOfByte"))) || xn_str_eq(mth, rt_string_from_c("get")))) {
          return rt_string_from_c("Int");
        }
        if ((xn_str_eq(mth, rt_string_from_c("substring")) || xn_str_eq(mth, rt_string_from_c("charAt")))) {
          return rt_string_from_c("String");
        }
        if ((((xn_str_eq(mth, rt_string_from_c("trim")) || xn_str_eq(mth, rt_string_from_c("replace"))) || xn_str_eq(mth, rt_string_from_c("toUpper"))) || xn_str_eq(mth, rt_string_from_c("toLower")))) {
          return rt_string_from_c("String");
        }
        if ((xn_str_eq(mth, rt_string_from_c("startsWith")) || xn_str_eq(mth, rt_string_from_c("endsWith")))) {
          return rt_string_from_c("Bool");
        }
        if (xn_str_eq(mth, rt_string_from_c("split"))) {
          return rt_string_from_c("List<String>");
        }
      }
      if (xn_Cls_CGen_isSet(self, bt)) {
        if (xn_str_eq(mth, rt_string_from_c("length"))) {
          return rt_string_from_c("Int");
        }
        if (xn_str_eq(mth, rt_string_from_c("has"))) {
          return rt_string_from_c("Bool");
        }
        if ((xn_str_eq(mth, rt_string_from_c("add")) || xn_str_eq(mth, rt_string_from_c("remove")))) {
          return rt_string_from_c("Bool");
        }
        if (xn_str_eq(mth, rt_string_from_c("clear"))) {
          return rt_string_from_c("Unit");
        }
      }
      if (xn_Cls_CGen_isResult(self, bt)) {
        if ((xn_str_eq(mth, rt_string_from_c("isOk")) || xn_str_eq(mth, rt_string_from_c("isErr")))) {
          return rt_string_from_c("Bool");
        }
        if ((xn_str_eq(mth, rt_string_from_c("value")) || xn_str_eq(mth, rt_string_from_c("unwrapOr")))) {
          return xn_Cls_CGen_resultValue(self, bt);
        }
        if (xn_str_eq(mth, rt_string_from_c("error"))) {
          return xn_Cls_CGen_resultError(self, bt);
        }
      }
      if (xn_Cls_CGen_isArray(self, bt)) {
        if (xn_str_eq(mth, rt_string_from_c("length"))) {
          return rt_string_from_c("Int");
        }
        if (xn_str_eq(mth, rt_string_from_c("get"))) {
          return xn_Cls_CGen_elementType(self, bt);
        }
        if (((xn_str_eq(mth, rt_string_from_c("push")) || xn_str_eq(mth, rt_string_from_c("remove"))) || xn_str_eq(mth, rt_string_from_c("clear")))) {
          return rt_string_from_c("Unit");
        }
        if ((xn_str_eq(mth, rt_string_from_c("tryGet")) || xn_str_eq(mth, rt_string_from_c("tryRemove")))) {
          return xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_CGen_elementType(self, bt)), rt_string_from_c(",Error>"));
        }
        if ((xn_str_eq(mth, rt_string_from_c("trySet")) || xn_str_eq(mth, rt_string_from_c("tryInsert")))) {
          return rt_string_from_c("Result<Unit,Error>");
        }
        if (xn_str_eq(mth, rt_string_from_c("join"))) {
          return rt_string_from_c("String");
        }
      }
      if (xn_Cls_CGen_isMap(self, bt)) {
        if (xn_str_eq(mth, rt_string_from_c("length"))) {
          return rt_string_from_c("Int");
        }
        if (xn_str_eq(mth, rt_string_from_c("has"))) {
          return rt_string_from_c("Bool");
        }
        if (xn_str_eq(mth, rt_string_from_c("clear"))) {
          return rt_string_from_c("Unit");
        }
        if ((xn_str_eq(mth, rt_string_from_c("put")) || xn_str_eq(mth, rt_string_from_c("remove")))) {
          return rt_string_from_c("Bool");
        }
        if (xn_str_eq(mth, rt_string_from_c("clear"))) {
          return rt_string_from_c("Unit");
        }
        if ((xn_str_eq(mth, rt_string_from_c("getOr")) || xn_str_eq(mth, rt_string_from_c("removeOr")))) {
          return xn_Cls_CGen_mapValue(self, bt);
        }
        if (xn_str_eq(mth, rt_string_from_c("tryGet"))) {
          return xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_CGen_mapValue(self, bt)), rt_string_from_c(",Error>"));
        }
        if (xn_str_eq(mth, rt_string_from_c("keys"))) {
          return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_CGen_mapKey(self, bt)), rt_string_from_c(">"));
        }
        if (xn_str_eq(mth, rt_string_from_c("values"))) {
          return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_CGen_mapValue(self, bt)), rt_string_from_c(">"));
        }
        if (xn_str_eq(mth, rt_string_from_c("entries"))) {
          if (xn_str_eq(bt, rt_string_from_c("Map<String,Int>"))) {
            return rt_string_from_c("List<Pair>");
          }
          if (xn_str_eq(bt, rt_string_from_c("Map<Int,Int>"))) {
            return rt_string_from_c("List<IntPair>");
          }
          return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_CGen_entryClassName(self, xn_Cls_CGen_mapKey(self, bt), xn_Cls_CGen_mapValue(self, bt))), rt_string_from_c(">"));
        }
      }
      if (xn_Cls_CGen_isProtocol(self, bt)) {
        return xn_Cls_CGen_protoRet(self, bt, mth);
      }
      if (xn_Cls_CGen_isClass(self, bt)) {
        rt_string * fty = xn_Cls_CGen_fieldType(self, bt, mth);
        if (xn_Cls_CGen_isFunctionType(self, fty)) {
          return xn_Cls_CGen_fnRetType(self, fty);
        }
      }
      rt_string * mr = xn_Cls_CGen_methodRet(self, bt, mth);
      if ((!xn_str_eq(mr, rt_string_from_c("Any")))) {
        return mr;
      }
    }
    rt_string * fr = xn_Cls_CGen_fnRet(self, n->text);
    if ((!xn_str_eq(fr, rt_string_from_c("Any")))) {
      return fr;
    }
    return rt_string_from_c("Any");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Member"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("Any");
    }
    rt_string * bt = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (xn_Cls_CGen_isClass(self, bt)) {
      rt_string * ft = xn_Cls_CGen_fieldType(self, bt, n->text);
      if ((!xn_str_eq(ft, rt_string_from_c("Any")))) {
        return ft;
      }
    }
    return rt_string_from_c("Any");
  }
  return rt_string_from_c("Any");
}

static int xn_Cls_CGen_intLiteralFits64(xn_Cls_CGen *self, rt_string * text) {
  if ((((int64_t)text->len) < 19)) {
    return 1;
  }
  if ((((int64_t)text->len) > 19)) {
    return 0;
  }
  return (text <= rt_string_from_c("9223372036854775807"));
}

static int xn_Cls_CGen_intLiteralFits32(xn_Cls_CGen *self, rt_string * text) {
  if ((((int64_t)text->len) < 10)) {
    return 1;
  }
  if ((((int64_t)text->len) > 10)) {
    return 0;
  }
  return xn_str_eq(xn_str_substr(text, 0, 1), rt_string_from_c("1"));
}

static rt_string * xn_Cls_CGen_expr(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Int"))) {
    if ((!xn_Cls_CGen_intLiteralFits64(self, n->text))) {
      return xn_concat(xn_concat(rt_string_from_c("xn_int128_from_dec(\""), n->text), rt_string_from_c("\")"));
    }
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Double"))) {
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    return xn_concat(xn_concat(rt_string_from_c("rt_string_from_c("), n->text), rt_string_from_c(")"));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Null"))) {
    return rt_string_from_c("0");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Bool"))) {
    if (xn_str_eq(n->text, rt_string_from_c("true"))) {
      return rt_string_from_c("1");
    }
    return rt_string_from_c("0");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Char"))) {
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Lambda"))) {
    int64_t li = xn_int_wrap(xn_Cls_CGen_lambdaIndex(self, n));
    if ((li < 0)) {
      xn_Cls_CGen_fail(self, rt_string_from_c("lambda is missing a function type context"));
      return rt_string_from_c("((xn_closure){0, 0})");
    }
    xn_Cls_CGen_ensureLambdaCaptures(self, li, n);
    if ((xn_str_eq(xn_arr_s_get(self->lambdaOwners, li), rt_string_from_c("")) && (!xn_str_eq(self->curClass, rt_string_from_c(""))))) {
      xn_arr_s_set(self->lambdaOwners, li, self->curClass);
    }
    xn_arr_s * caps = xn_Cls_CGen_splitCaps(self, xn_arr_s_get(self->lambdaCaptures, li));
    xn_arr_s * capTypes = xn_Cls_CGen_splitCaps(self, xn_arr_s_get(self->lambdaCaptureTypes, li));
    rt_string * selfTy = xn_Cls_CGen_findVar(self, rt_string_from_c("self"));
    if ((((!xn_str_eq(self->curClass, rt_string_from_c(""))) && (!xn_str_eq(selfTy, rt_string_from_c("Any")))) && (!xn_Cls_CGen_listHas(self, caps, rt_string_from_c("self"))))) {
      xn_arr_s_push(caps, rt_string_from_c("self"));
      xn_arr_s_push(capTypes, selfTy);
      xn_arr_s_set(self->lambdaCaptures, li, xn_Cls_CGen_joinCaps(self, caps));
      xn_arr_s_set(self->lambdaCaptureTypes, li, xn_Cls_CGen_joinCaps(self, capTypes));
    }
    if ((((int64_t)caps->len) == 0)) {
      return xn_concat(xn_concat(rt_string_from_c("((xn_closure){0, (void*)"), xn_Cls_CGen_lambdaName(self, n)), rt_string_from_c("})"));
    }
    rt_string * env = xn_Cls_CGen_temp(self);
    rt_string * cl = xn_Cls_CGen_temp(self);
    rt_string * b = xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(({ void **"), env), rt_string_from_c(" = (void **)malloc(sizeof(void *) * ")), xn_str_int(((int64_t)caps->len))), rt_string_from_c("); "));
    int64_t ci = xn_int_wrap(0);
    while ((ci < ((int64_t)caps->len))) {
      rt_string * box = xn_Cls_CGen_temp(self);
      rt_string * ct = xn_Cls_CGen_ctype(self, xn_arr_s_get(capTypes, ci));
      b = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(b, rt_string_from_c("{ ")), ct), rt_string_from_c(" *")), box), rt_string_from_c(" = (")), ct), rt_string_from_c(" *)malloc(sizeof(")), ct), rt_string_from_c(")); *")), box), rt_string_from_c(" = ")), xn_arr_s_get(caps, ci)), rt_string_from_c("; ")), env), rt_string_from_c("[")), xn_str_int(ci)), rt_string_from_c("] = ")), box), rt_string_from_c("; } "));
      if (xn_Cls_CGen_isGcRefType(self, xn_arr_s_get(capTypes, ci))) {
        b = xn_concat(xn_concat(xn_concat(b, rt_string_from_c("rt_gc_root_add((void *)")), xn_arr_s_get(caps, ci)), rt_string_from_c("); "));
      }
      ci = xn_int_wrap((ci + 1));
    }
    b = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(b, rt_string_from_c("xn_closure ")), cl), rt_string_from_c(" = { (void *)")), env), rt_string_from_c(", (void *)")), xn_Cls_CGen_lambdaName(self, n)), rt_string_from_c(" }; ")), cl), rt_string_from_c("; }))"));
    return b;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Ternary"))) {
    if ((((int64_t)n->kids->len) < 3)) {
      return rt_string_from_c("0");
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(") ? (")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(") : (")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 2)))), rt_string_from_c("))"));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Cast"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("0");
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), xn_Cls_CGen_ctype(self, n->text)), rt_string_from_c(")")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Is"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("0");
    }
    return rt_string_from_c("1");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Unary"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("0");
    }
    rt_string * operand = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    int wideLiteral = (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))->kind, rt_string_from_c("Int")) && (!xn_Cls_CGen_intLiteralFits64(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))->text)));
    if ((xn_str_eq(n->text, rt_string_from_c("-")) && (xn_str_eq(xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("Int128")) || wideLiteral))) {
      return xn_concat(xn_concat(rt_string_from_c("-("), operand), rt_string_from_c(")"));
    }
    if ((xn_str_eq(xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("Int")) && xn_str_eq(n->text, rt_string_from_c("-")))) {
      return xn_concat(xn_concat(rt_string_from_c("xn_int_wrap(-("), operand), rt_string_from_c("))"));
    }
    return xn_concat(xn_concat(xn_concat(rt_string_from_c("("), n->text), operand), rt_string_from_c(")"));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Index"))) {
    if ((((int64_t)n->kids->len) < 2)) {
      return rt_string_from_c("0");
    }
    rt_string * bt = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    return xn_Cls_CGen_arrayGet(self, bt, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1))));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Name"))) {
    return xn_Cls_CGen_nameExpr(self, n->text);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("New"))) {
    if ((xn_str_eq(n->text, rt_string_from_c("Channel")) || xn_str_startswith(n->text, rt_string_from_c("Channel<")))) {
      rt_string * capacity = rt_string_from_c("1");
      if ((((int64_t)n->kids->len) > 0)) {
        capacity = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      rt_string * ops = rt_string_from_c("NULL");
      if (xn_str_startswith(n->text, rt_string_from_c("Channel<"))) {
        rt_string * elem = xn_str_substr(n->text, 8, xn_int_wrap((((int64_t)n->text->len) - 9)));
        if ((xn_str_eq(elem, rt_string_from_c("Int128")) || xn_Cls_CGen_isResult(self, elem))) {
          ops = rt_string_from_c("&xn_channel_box_ops");
        }
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_channel_new((size_t)("), capacity), rt_string_from_c("), ")), ops), rt_string_from_c(")"));
    }
    rt_string * b = xn_concat(xn_concat(rt_string_from_c("xn_Cls_"), n->text), rt_string_from_c("_new("));
    int64_t ni = xn_int_wrap(0);
    while ((ni < ((int64_t)n->kids->len))) {
      if ((ni > 0)) {
        b = xn_concat(b, rt_string_from_c(", "));
      }
      b = xn_concat(b, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ni))));
      ni = xn_int_wrap((ni + 1));
    }
    return xn_concat(b, rt_string_from_c(")"));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Binary"))) {
    rt_string * lt = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    rt_string * rt = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
    rt_string * a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    rt_string * b = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
    if (((xn_str_eq(n->text, rt_string_from_c("+")) && xn_str_eq(lt, rt_string_from_c("String"))) && xn_str_eq(rt, rt_string_from_c("String")))) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_concat("), a), rt_string_from_c(", ")), b), rt_string_from_c(")"));
    }
    if ((xn_str_eq(lt, rt_string_from_c("String")) && xn_str_eq(rt, rt_string_from_c("String")))) {
      if (xn_str_eq(n->text, rt_string_from_c("=="))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_eq("), a), rt_string_from_c(", ")), b), rt_string_from_c(")"));
      }
      if (xn_str_eq(n->text, rt_string_from_c("!="))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(!xn_str_eq("), a), rt_string_from_c(", ")), b), rt_string_from_c("))"));
      }
    }
    if ((xn_str_eq(lt, rt_string_from_c("Int")) && xn_str_eq(rt, rt_string_from_c("Int")))) {
      if (xn_str_eq(n->text, rt_string_from_c("<<"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_int_shl("), a), rt_string_from_c(", ")), b), rt_string_from_c(")"));
      }
      if (xn_str_eq(n->text, rt_string_from_c(">>"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_int_shr("), a), rt_string_from_c(", ")), b), rt_string_from_c(")"));
      }
      if ((((((((xn_str_eq(n->text, rt_string_from_c("+")) || xn_str_eq(n->text, rt_string_from_c("-"))) || xn_str_eq(n->text, rt_string_from_c("*"))) || xn_str_eq(n->text, rt_string_from_c("/"))) || xn_str_eq(n->text, rt_string_from_c("%"))) || xn_str_eq(n->text, rt_string_from_c("&"))) || xn_str_eq(n->text, rt_string_from_c("|"))) || xn_str_eq(n->text, rt_string_from_c("^")))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_int_wrap(("), a), rt_string_from_c(" ")), n->text), rt_string_from_c(" ")), b), rt_string_from_c("))"));
      }
    }
    return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("("), a), rt_string_from_c(" ")), n->text), rt_string_from_c(" ")), b), rt_string_from_c(")"));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("MethodCall"))) {
    if ((((int64_t)n->kids->len) < 1)) {
      return rt_string_from_c("0");
    }
    rt_string * bv = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    rt_string * bt = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    return xn_Cls_CGen_methodExpr(self, bv, bt, n->text, n, 1);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
    int64_t fvi = xn_int_wrap(xn_Cls_CGen_varIndex(self, n->text));
    if (((fvi >= 0) && xn_Cls_CGen_isFunctionType(self, xn_arr_s_get(self->varTypes, fvi)))) {
      return xn_Cls_CGen_closureCall(self, xn_arr_s_get(self->varTypes, fvi), xn_Cls_CGen_nameExpr(self, n->text), n);
    }
    int64_t ffi = xn_int_wrap(xn_ffiIndex(n->text));
    if (((((((((((((((ffi >= 0) && (!xn_str_eq(n->text, rt_string_from_c("diagnoseRaw")))) && (!xn_str_eq(n->text, rt_string_from_c("exitRaw")))) && (!xn_str_eq(n->text, rt_string_from_c("nowMonoRaw")))) && (!xn_str_eq(n->text, rt_string_from_c("nowWallRaw")))) && (!xn_str_eq(n->text, rt_string_from_c("resourceExistsRaw")))) && (!xn_str_eq(n->text, rt_string_from_c("resourceCountRaw")))) && (!xn_str_eq(n->text, rt_string_from_c("readResourceTextRaw")))) && (!xn_str_eq(n->text, rt_string_from_c("fileExistsRaw")))) && (!xn_str_eq(n->text, rt_string_from_c("readFile")))) && (!xn_str_eq(n->text, rt_string_from_c("listFiles")))) && (!xn_str_eq(n->text, rt_string_from_c("platformRaw")))) && (!xn_str_eq(n->text, rt_string_from_c("readFileTextRaw")))) && (!xn_str_eq(n->text, rt_string_from_c("readFileTextError"))))) {
      if (xn_Cls_CGen_ffiEntryOk(self, ffi)) {
        rt_string * wb = xn_concat(xn_concat(rt_string_from_c("xn_ffi_"), n->text), rt_string_from_c("("));
        int64_t epi = xn_int_wrap(xn_Cls_CGen_ffiErrParamIndex(self, ffi));
        int64_t fi = xn_int_wrap(0);
        while ((fi < ((int64_t)n->kids->len))) {
          if ((fi > 0)) {
            wb = xn_concat(wb, rt_string_from_c(", "));
          }
          rt_string * av = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, fi)));
          if ((fi == epi)) {
            av = xn_concat(rt_string_from_c("&"), av);
          }
          wb = xn_concat(wb, av);
          fi = xn_int_wrap((fi + 1));
        }
        return xn_concat(wb, rt_string_from_c(")"));
      }
      rt_string * b = xn_concat(xn_ffiCName(n->text), rt_string_from_c("("));
      int64_t fi = xn_int_wrap(0);
      while ((fi < ((int64_t)n->kids->len))) {
        if ((fi > 0)) {
          b = xn_concat(b, rt_string_from_c(", "));
        }
        b = xn_concat(b, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, fi))));
        fi = xn_int_wrap((fi + 1));
      }
      return xn_concat(b, rt_string_from_c(")"));
    }
    if ((xn_str_eq(n->text, rt_string_from_c("AtomicInt")) || xn_str_eq(n->text, rt_string_from_c("AtomicBool")))) {
      rt_string * av = rt_string_from_c("0");
      if ((((int64_t)n->kids->len) > 0)) {
        av = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      if (xn_str_eq(n->text, rt_string_from_c("AtomicInt"))) {
        return xn_concat(xn_concat(rt_string_from_c("xrt_atomic_int_new((int64_t)("), av), rt_string_from_c("))"));
      }
      return xn_concat(xn_concat(rt_string_from_c("xrt_atomic_bool_new((int)("), av), rt_string_from_c("))"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("AtomicRef"))) {
      rt_string * av = rt_string_from_c("NULL");
      if ((((int64_t)n->kids->len) > 0)) {
        av = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(rt_string_from_c("xdkc_atomic_ref_new((void *)("), av), rt_string_from_c("))"));
    }
    if ((xn_str_eq(n->text, rt_string_from_c("Channel")) || xn_str_startswith(n->text, rt_string_from_c("Channel<")))) {
      rt_string * av = rt_string_from_c("1");
      if ((((int64_t)n->kids->len) > 0)) {
        av = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      rt_string * ops = rt_string_from_c("NULL");
      if (xn_str_startswith(n->text, rt_string_from_c("Channel<"))) {
        rt_string * elem = xn_str_substr(n->text, 8, xn_int_wrap((((int64_t)n->text->len) - 9)));
        if ((xn_str_eq(elem, rt_string_from_c("Int128")) || xn_Cls_CGen_isResult(self, elem))) {
          ops = rt_string_from_c("&xn_channel_box_ops");
        }
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_channel_new((size_t)("), av), rt_string_from_c("), ")), ops), rt_string_from_c(")"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("Mutex"))) {
      rt_string * av = rt_string_from_c("NULL");
      if ((((int64_t)n->kids->len) > 0)) {
        av = xn_concat(xn_concat(rt_string_from_c("((void *)(intptr_t)("), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c("))"));
      }
      return xn_concat(xn_concat(rt_string_from_c("xrt_mutex_new("), av), rt_string_from_c(", NULL)"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("Context.background"))) {
      return rt_string_from_c("xrt_context_background()");
    }
    if (xn_str_eq(n->text, rt_string_from_c("TaskGroup.create"))) {
      rt_string * av = rt_string_from_c("NULL");
      if ((((int64_t)n->kids->len) > 0)) {
        av = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(rt_string_from_c("xrt_task_group_new("), av), rt_string_from_c(")"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("listFiles"))) {
      rt_string * a = rt_string_from_c("rt_string_from_c(\"\")");
      if ((((int64_t)n->kids->len) > 0)) {
        a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("rt_string_from_c(mini_list_x("), a), rt_string_from_c("->bytes, ")), a), rt_string_from_c("->len))"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("readFile"))) {
      rt_string * a = rt_string_from_c("rt_string_from_c(\"\")");
      if ((((int64_t)n->kids->len) > 0)) {
        a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("rt_string_from_c(mini_read_file("), a), rt_string_from_c("->bytes, ")), a), rt_string_from_c("->len))"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("diagnoseRaw"))) {
      rt_string * a = rt_string_from_c("rt_string_from_c(\"\")");
      if ((((int64_t)n->kids->len) > 0)) {
        a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xdkc_diagnose_rc("), a), rt_string_from_c("->bytes, ")), a), rt_string_from_c("->len)"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("exitRaw"))) {
      rt_string * a = rt_string_from_c("0");
      if ((((int64_t)n->kids->len) > 0)) {
        a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(rt_string_from_c("xdkc_exit_rc((int32_t)"), a), rt_string_from_c(")"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("nowMonoRaw"))) {
      return rt_string_from_c("xdkc_now_mono_ms()");
    }
    if (xn_str_eq(n->text, rt_string_from_c("nowWallRaw"))) {
      return rt_string_from_c("xdkc_now_wall_ms()");
    }
    if (xn_str_eq(n->text, rt_string_from_c("resourceExistsRaw"))) {
      rt_string * a = rt_string_from_c("rt_string_from_c(\"\")");
      if ((((int64_t)n->kids->len) > 0)) {
        a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xdkc_p_resource_exists("), a), rt_string_from_c("->bytes, ")), a), rt_string_from_c("->len)"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("readResourceTextRaw"))) {
      rt_string * a = rt_string_from_c("rt_string_from_c(\"\")");
      if ((((int64_t)n->kids->len) > 0)) {
        a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("rt_string_from_c(xdkc_p_read_resource_text("), a), rt_string_from_c("->bytes, ")), a), rt_string_from_c("->len))"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("resourceCountRaw"))) {
      return rt_string_from_c("xdkc_p_resource_count()");
    }
    if (xn_str_eq(n->text, rt_string_from_c("readFileTextRaw"))) {
      rt_string * a = rt_string_from_c("rt_string_from_c(\"\")");
      if ((((int64_t)n->kids->len) > 0)) {
        a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("rt_string_from_c(xdkc_read_file_text("), a), rt_string_from_c("->bytes, ")), a), rt_string_from_c("->len))"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("readFileTextError"))) {
      return rt_string_from_c("xdkc_read_file_text_error()");
    }
    if (xn_str_eq(n->text, rt_string_from_c("fileExistsRaw"))) {
      rt_string * a = rt_string_from_c("rt_string_from_c(\"\")");
      if ((((int64_t)n->kids->len) > 0)) {
        a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("mini_file_exists("), a), rt_string_from_c("->bytes, ")), a), rt_string_from_c("->len)"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("platformRaw"))) {
      return rt_string_from_c("rt_string_from_c(mini_platform())");
    }
    if (xn_str_eq(n->text, rt_string_from_c("Ok"))) {
      rt_string * a = rt_string_from_c("0");
      if ((((int64_t)n->kids->len) > 0)) {
        a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      if (xn_Cls_CGen_isGenericResult(self, self->curRet)) {
        return xn_concat(xn_concat(rt_string_from_c("(xn_Result){ .ok = 1, "), xn_Cls_CGen_resultInitField(self, self->curRet, a)), rt_string_from_c(" }"));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("("), xn_Cls_CGen_ctype(self, self->curRet)), rt_string_from_c("){1, ")), a), rt_string_from_c(", 0}"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("Err"))) {
      rt_string * a = rt_string_from_c("rt_string_from_c(\"\")");
      if ((((int64_t)n->kids->len) > 0)) {
        a = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      if (xn_Cls_CGen_isGenericResult(self, self->curRet)) {
        return xn_concat(xn_concat(rt_string_from_c("(xn_Result){ .ok = 0, .err = (void *)("), a), rt_string_from_c(") }"));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("("), xn_Cls_CGen_ctype(self, self->curRet)), rt_string_from_c("){0, 0, ")), a), rt_string_from_c("}"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("print"))) {
      rt_string * at = rt_string_from_c("Any");
      if ((((int64_t)n->kids->len) > 0)) {
        at = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      rt_string * pat = at;
      if (((((int64_t)pat->len) > 1) && xn_str_eq(xn_str_substr(pat, xn_int_wrap((((int64_t)pat->len) - 1)), 1), rt_string_from_c("?")))) {
        pat = xn_str_substr(pat, 0, xn_int_wrap((((int64_t)pat->len) - 1)));
      }
      rt_string * av = rt_string_from_c("0");
      if ((((int64_t)n->kids->len) > 0)) {
        av = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      if (xn_str_eq(pat, rt_string_from_c("Int"))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_print_int("), av), rt_string_from_c(")"));
      }
      if ((xn_str_eq(pat, rt_string_from_c("Long")) || xn_str_eq(pat, rt_string_from_c("Int64")))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_print_long("), av), rt_string_from_c(")"));
      }
      if (xn_str_eq(pat, rt_string_from_c("Int128"))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_print_int128("), av), rt_string_from_c(")"));
      }
      if (xn_str_eq(pat, rt_string_from_c("Double"))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_print_double("), av), rt_string_from_c(")"));
      }
      if (xn_str_eq(pat, rt_string_from_c("Bool"))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_print_bool("), av), rt_string_from_c(")"));
      }
      if (xn_str_eq(pat, rt_string_from_c("Char"))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_print_str(xn_str_char("), av), rt_string_from_c("))"));
      }
      return xn_concat(xn_concat(rt_string_from_c("xn_print_str("), av), rt_string_from_c(")"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("str"))) {
      if ((((int64_t)n->kids->len) == 0)) {
        return rt_string_from_c("rt_string_from_c(\"\")");
      }
      rt_string * at = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      rt_string * pat = at;
      if (((((int64_t)pat->len) > 1) && xn_str_eq(xn_str_substr(pat, xn_int_wrap((((int64_t)pat->len) - 1)), 1), rt_string_from_c("?")))) {
        pat = xn_str_substr(pat, 0, xn_int_wrap((((int64_t)pat->len) - 1)));
      }
      rt_string * av = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      if (xn_str_eq(pat, rt_string_from_c("String"))) {
        return av;
      }
      if (xn_str_eq(pat, rt_string_from_c("Double"))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_str_double("), av), rt_string_from_c(")"));
      }
      if (xn_str_eq(pat, rt_string_from_c("Bool"))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_str_bool("), av), rt_string_from_c(")"));
      }
      if (xn_str_eq(pat, rt_string_from_c("Char"))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_str_char("), av), rt_string_from_c(")"));
      }
      if ((xn_str_eq(pat, rt_string_from_c("Long")) || xn_str_eq(pat, rt_string_from_c("Int64")))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_str_long("), av), rt_string_from_c(")"));
      }
      if (xn_str_eq(pat, rt_string_from_c("Int128"))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_str_int128("), av), rt_string_from_c(")"));
      }
      return xn_concat(xn_concat(rt_string_from_c("xn_str_int("), av), rt_string_from_c(")"));
    }
    int64_t dot = xn_int_wrap(xn_lastDot(n->text));
    if ((dot >= 0)) {
      rt_string * base = xn_str_substr(n->text, 0, dot);
      rt_string * mth = xn_str_substr(n->text, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)n->text->len) - dot)) - 1)));
      rt_string * bv = xn_Cls_CGen_pathExpr(self, base);
      rt_string * bt = xn_Cls_CGen_pathType(self, base);
      if (xn_str_eq(bt, rt_string_from_c("AtomicInt"))) {
        if (xn_str_eq(mth, rt_string_from_c("load"))) {
          return xn_concat(xn_concat(rt_string_from_c("xrt_atomic_int_load("), bv), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("store"))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_atomic_int_store("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
        }
        if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((xrt_atomic_int_cas("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(") != 0) ? 1 : 0)"));
        }
      }
      if (xn_str_eq(bt, rt_string_from_c("AtomicBool"))) {
        if (xn_str_eq(mth, rt_string_from_c("load"))) {
          return xn_concat(xn_concat(rt_string_from_c("xrt_atomic_bool_load("), bv), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("store"))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_atomic_bool_store("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
        }
        if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((xrt_atomic_bool_cas("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(") != 0) ? 1 : 0)"));
        }
      }
      if ((xn_str_indexof(bt, rt_string_from_c("AtomicRef<")) == 0)) {
        if (xn_str_eq(mth, rt_string_from_c("load"))) {
          return xn_concat(xn_concat(rt_string_from_c("((rt_string *)xrt_atomic_ref_load("), bv), rt_string_from_c("))"));
        }
        if (xn_str_eq(mth, rt_string_from_c("store"))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_atomic_ref_store("), bv), rt_string_from_c(", (void *)(")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c("))"));
        }
        if ((xn_str_eq(mth, rt_string_from_c("cas")) || xn_str_eq(mth, rt_string_from_c("compareExchange")))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((xrt_atomic_ref_cas("), bv), rt_string_from_c(", (void *)(")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c("), (void *)(")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(")) != 0) ? 1 : 0)"));
        }
      }
      if ((xn_str_indexof(bt, rt_string_from_c("Channel<")) == 0)) {
        rt_string * elementType = xn_str_substr(bt, 8, xn_int_wrap((((int64_t)bt->len) - 9)));
        if (xn_str_eq(mth, rt_string_from_c("send"))) {
          if (xn_str_eq(elementType, rt_string_from_c("Int"))) {
            return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_int("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
          }
          if (xn_str_eq(elementType, rt_string_from_c("Double"))) {
            return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_double("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
          }
          if (xn_str_eq(elementType, rt_string_from_c("Int128"))) {
            return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_int128("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
          }
          if (xn_str_eq(elementType, rt_string_from_c("Result<Int,String>"))) {
            return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_result_is("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
          }
          if (xn_Cls_CGen_isResult(self, elementType)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_result("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
          }
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_send_ptr("), bv), rt_string_from_c(", (void *)(")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c("), ")), self->curCtxExpr), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("receive"))) {
          if (xn_str_eq(elementType, rt_string_from_c("Int"))) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_int("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
          }
          if (xn_str_eq(elementType, rt_string_from_c("Double"))) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_double("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
          }
          if (xn_str_eq(elementType, rt_string_from_c("Int128"))) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_int128("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
          }
          if (xn_str_eq(elementType, rt_string_from_c("Result<Int,String>"))) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_result_is("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
          }
          if (xn_Cls_CGen_isResult(self, elementType)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_result("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
          }
          return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_channel_recv_ptr("), bv), rt_string_from_c(", ")), self->curCtxExpr), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("close"))) {
          return xn_concat(xn_concat(rt_string_from_c("xrt_channel_close("), bv), rt_string_from_c(")"));
        }
      }
      if ((xn_str_eq(bt, rt_string_from_c("Mutex")) || (xn_str_indexof(bt, rt_string_from_c("Mutex<")) == 0))) {
        if ((xn_str_eq(mth, rt_string_from_c("withLock")) && (((int64_t)n->kids->len) > 0))) {
          xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
          int64_t li = xn_int_wrap(xn_Cls_CGen_lambdaIndex(self, lam));
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_mutex_lock("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, lam)), rt_string_from_c(", xn_lock_body_")), xn_str_int(li)), rt_string_from_c(")"));
        }
      }
      if (xn_str_eq(bt, rt_string_from_c("Context"))) {
        if (xn_str_eq(mth, rt_string_from_c("isCancelled"))) {
          return xn_concat(xn_concat(rt_string_from_c("xrt_context_cancelled("), bv), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
          return xn_concat(xn_concat(rt_string_from_c("xrt_context_cancel("), bv), rt_string_from_c(")"));
        }
      }
      if (xn_str_eq(bt, rt_string_from_c("TaskGroup"))) {
        if ((xn_str_eq(mth, rt_string_from_c("spawn")) && (((int64_t)n->kids->len) > 0))) {
          xn_Cls_AstNode * lam = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
          int64_t li = xn_int_wrap(xn_Cls_CGen_lambdaIndex(self, lam));
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_task_spawn("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, lam)), rt_string_from_c(", xn_task_body_")), xn_str_int(li)), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("cancel"))) {
          return xn_concat(xn_concat(rt_string_from_c("xrt_task_group_cancel("), bv), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("close"))) {
          return xn_concat(xn_concat(rt_string_from_c("xn_task_group_close("), bv), rt_string_from_c(")"));
        }
      }
      if ((xn_str_eq(bt, rt_string_from_c("Task")) || (xn_str_indexof(bt, rt_string_from_c("Task<")) == 0))) {
        if (xn_str_eq(mth, rt_string_from_c("join"))) {
          return xn_concat(xn_concat(rt_string_from_c("xn_task_join("), bv), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("joinDeadline"))) {
          rt_string * dl = rt_string_from_c("0");
          if ((((int64_t)n->kids->len) > 0)) {
            dl = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
          }
          return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_task_join_deadline("), bv), rt_string_from_c(", ")), dl), rt_string_from_c(")"));
        }
      }
      if (xn_str_eq(bt, rt_string_from_c("Bytes"))) {
        if (xn_str_eq(mth, rt_string_from_c("fromString"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_bytes_from_string("), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c("->bytes, ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c("->len)"));
          }
          return rt_string_from_c("xrt_bytes_new()");
        }
        if (xn_str_eq(mth, rt_string_from_c("length"))) {
          return xn_concat(xn_concat(rt_string_from_c("((int64_t)xrt_bytes_len("), bv), rt_string_from_c("))"));
        }
        if (xn_str_eq(mth, rt_string_from_c("get"))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((int64_t)xrt_bytes_get("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c("))"));
        }
        if (xn_str_eq(mth, rt_string_from_c("slice"))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_bytes_slice("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("set"))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_bytes_set("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("append"))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_bytes_append("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("push"))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_bytes_push("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("toString"))) {
          return xn_concat(xn_concat(rt_string_from_c("xn_bytes_to_string("), bv), rt_string_from_c(")"));
        }
      }
      if (xn_str_eq(bt, rt_string_from_c("String"))) {
        if (xn_str_eq(mth, rt_string_from_c("length"))) {
          return xn_concat(xn_concat(rt_string_from_c("((int64_t)"), bv), rt_string_from_c("->len)"));
        }
        if (xn_str_eq(mth, rt_string_from_c("get"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("((int64_t)(unsigned char)"), bv), rt_string_from_c("->bytes[")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c("])"));
          }
          return rt_string_from_c("0");
        }
        if ((xn_str_eq(mth, rt_string_from_c("indexOf")) || xn_str_eq(mth, rt_string_from_c("indexOfByte")))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_indexof("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
          }
          return rt_string_from_c("-1");
        }
        if (xn_str_eq(mth, rt_string_from_c("substring"))) {
          if ((((int64_t)n->kids->len) >= 2)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_substr("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(")"));
          }
          return rt_string_from_c("rt_string_from_c(\"\")");
        }
        if (xn_str_eq(mth, rt_string_from_c("charAt"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_substr("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", 1)"));
          }
          return rt_string_from_c("rt_string_from_c(\"\")");
        }
        if (xn_str_eq(mth, rt_string_from_c("trim"))) {
          return xn_concat(xn_concat(rt_string_from_c("xn_str_trim("), bv), rt_string_from_c(")"));
        }
        if ((xn_str_eq(mth, rt_string_from_c("toUpper")) || xn_str_eq(mth, rt_string_from_c("toLower")))) {
          rt_string * up = rt_string_from_c("0");
          if (xn_str_eq(mth, rt_string_from_c("toUpper"))) {
            up = rt_string_from_c("1");
          }
          return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_case("), bv), rt_string_from_c(", ")), up), rt_string_from_c(")"));
        }
        if ((xn_str_eq(mth, rt_string_from_c("replace")) && (((int64_t)n->kids->len) > 1))) {
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_replace("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(")"));
        }
        if (xn_str_eq(mth, rt_string_from_c("startsWith"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_startswith("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
          }
          return rt_string_from_c("0");
        }
        if (xn_str_eq(mth, rt_string_from_c("endsWith"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_endswith("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
          }
          return rt_string_from_c("0");
        }
        if (xn_str_eq(mth, rt_string_from_c("split"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_split("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
          }
          return rt_string_from_c("xn_arr_s_new(4)");
        }
      }
      if (xn_Cls_CGen_isSet(self, bt)) {
        return xn_Cls_CGen_setMethodExpr(self, bv, bt, mth, n, 0, 0);
      }
      if (xn_Cls_CGen_isResult(self, bt)) {
        if (xn_str_eq(mth, rt_string_from_c("isOk"))) {
          return xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").ok != 0)"));
        }
        if (xn_str_eq(mth, rt_string_from_c("isErr"))) {
          return xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").ok == 0)"));
        }
        if (xn_str_eq(mth, rt_string_from_c("value"))) {
          if (xn_Cls_CGen_isGenericResult(self, bt)) {
            return xn_Cls_CGen_resultValueCExpr(self, bt, bv);
          }
          return xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").value)"));
        }
        if (xn_str_eq(mth, rt_string_from_c("error"))) {
          if (xn_Cls_CGen_isGenericResult(self, bt)) {
            return xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").err)"));
          }
          return xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").error)"));
        }
        if (xn_str_eq(mth, rt_string_from_c("unwrapOr"))) {
          rt_string * d = rt_string_from_c("0");
          if ((((int64_t)n->kids->len) > 0)) {
            d = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
          }
          if (xn_Cls_CGen_isGenericResult(self, bt)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").ok ? ")), xn_Cls_CGen_resultValueExpr(self, bt, bv)), rt_string_from_c(" : ")), d), rt_string_from_c(")"));
          }
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), bv), rt_string_from_c(").ok ? (")), bv), rt_string_from_c(").value : ")), d), rt_string_from_c(")"));
        }
      }
      if (xn_Cls_CGen_isArray(self, bt)) {
        if (xn_str_eq(mth, rt_string_from_c("length"))) {
          return xn_concat(xn_concat(rt_string_from_c("((int64_t)"), bv), rt_string_from_c("->len)"));
        }
        if (xn_str_eq(mth, rt_string_from_c("get"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_Cls_CGen_arrayGet(self, bt, bv, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))));
          }
          return rt_string_from_c("0");
        }
        if (xn_str_eq(mth, rt_string_from_c("push"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_Cls_CGen_arrayPush(self, bt, bv, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))));
          }
          return rt_string_from_c("0");
        }
        if (xn_str_eq(mth, rt_string_from_c("set"))) {
          if ((((int64_t)n->kids->len) > 1)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_set(")), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(")"));
          }
          return rt_string_from_c("0");
        }
        if (xn_str_eq(mth, rt_string_from_c("insert"))) {
          if ((((int64_t)n->kids->len) > 1)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_insert(")), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)))), rt_string_from_c(")"));
          }
          return rt_string_from_c("0");
        }
        if (xn_str_eq(mth, rt_string_from_c("remove"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_remove(")), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
          }
          return rt_string_from_c("0");
        }
        if (xn_str_eq(mth, rt_string_from_c("join"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_arr_s_join("), bv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
          }
          return rt_string_from_c("rt_string_from_c(\"\")");
        }
        if (xn_str_eq(mth, rt_string_from_c("clear"))) {
          return xn_concat(xn_concat(rt_string_from_c("("), bv), rt_string_from_c("->len = 0)"));
        }
        if ((xn_str_eq(mth, rt_string_from_c("tryGet")) && (((int64_t)n->kids->len) > 0))) {
          rt_string * index = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
          rt_string * resultTy = xn_concat(xn_concat(rt_string_from_c("Result<"), xn_Cls_CGen_elementType(self, bt)), rt_string_from_c(",Error>"));
          rt_string * ok = xn_concat(xn_concat(rt_string_from_c("(xn_Result){ .ok = 1, "), xn_Cls_CGen_resultInitField(self, resultTy, xn_Cls_CGen_arrayGet(self, bt, bv, index))), rt_string_from_c(" }"));
          rt_string * err = rt_string_from_c("(xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, \"tryGet: index out of range\") }");
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), index), rt_string_from_c(" >= 0 && ")), index), rt_string_from_c(" < (int64_t)")), bv), rt_string_from_c("->len) ? ")), ok), rt_string_from_c(" : ")), err), rt_string_from_c(")"));
        }
        if ((xn_str_eq(mth, rt_string_from_c("tryRemove")) && (((int64_t)n->kids->len) > 0))) {
          rt_string * index = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_try_remove(")), bv), rt_string_from_c(", ")), index), rt_string_from_c(")"));
        }
        if (((xn_str_eq(mth, rt_string_from_c("trySet")) || xn_str_eq(mth, rt_string_from_c("tryInsert"))) && (((int64_t)n->kids->len) > 1))) {
          rt_string * index = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
          rt_string * value = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
          rt_string * call = rt_string_from_c("");
          if (xn_str_eq(mth, rt_string_from_c("trySet"))) {
            call = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_set(")), bv), rt_string_from_c(", ")), index), rt_string_from_c(", ")), value), rt_string_from_c(")"));
          }
          else {
            call = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_insert(")), bv), rt_string_from_c(", ")), index), rt_string_from_c(", ")), value), rt_string_from_c(")"));
          }
          rt_string * bound = rt_string_from_c(" < ");
          if (xn_str_eq(mth, rt_string_from_c("tryInsert"))) {
            bound = rt_string_from_c(" <= ");
          }
          rt_string * err = xn_concat(xn_concat(rt_string_from_c("(xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, \""), mth), rt_string_from_c(": index out of range\") }"));
          return xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), index), rt_string_from_c(" >= 0 && ")), index), bound), rt_string_from_c("(int64_t)")), bv), rt_string_from_c("->len) ? (")), call), rt_string_from_c(", (xn_Result){ .ok = 1 }) : ")), err), rt_string_from_c(")"));
        }
      }
      if (xn_Cls_CGen_isMap(self, bt)) {
        return xn_Cls_CGen_mapMethodExpr(self, bv, bt, mth, n, 0, 0);
      }
      if (xn_Cls_CGen_isClass(self, bt)) {
        rt_string * fty = xn_Cls_CGen_fieldType(self, bt, mth);
        if (xn_Cls_CGen_isFunctionType(self, fty)) {
          return xn_Cls_CGen_closureCall(self, fty, xn_concat(xn_concat(bv, rt_string_from_c("->")), mth), n);
        }
      }
      if (xn_Cls_CGen_isProtocol(self, bt)) {
        rt_string * pb = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_proto_"), bt), rt_string_from_c("_")), mth), rt_string_from_c("(")), bv);
        int64_t pi = xn_int_wrap(0);
        while ((pi < ((int64_t)n->kids->len))) {
          pb = xn_concat(xn_concat(pb, rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, pi))));
          pi = xn_int_wrap((pi + 1));
        }
        return xn_concat(pb, rt_string_from_c(")"));
      }
      rt_string * b = xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_Cls_"), bt), rt_string_from_c("_")), mth), rt_string_from_c("("));
      if ((xn_Cls_CGen_isClass(self, bt) && (!xn_Cls_CGen_isStaticMethod(self, bt, mth)))) {
        b = xn_concat(b, bv);
      }
      int64_t di = xn_int_wrap(0);
      int firstArg = (!(xn_Cls_CGen_isClass(self, bt) && (!xn_Cls_CGen_isStaticMethod(self, bt, mth))));
      if ((xn_Cls_CGen_isClass(self, bt) && xn_Cls_CGen_isStaticMethod(self, bt, mth))) {
        firstArg = 1;
      }
      while ((di < ((int64_t)n->kids->len))) {
        if (firstArg) {
          firstArg = 0;
        }
        else {
          b = xn_concat(b, rt_string_from_c(", "));
        }
        b = xn_concat(b, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, di))));
        di = xn_int_wrap((di + 1));
      }
      return xn_concat(b, rt_string_from_c(")"));
    }
    rt_string * b = xn_concat(xn_concat(rt_string_from_c("xn_"), n->text), rt_string_from_c("("));
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)n->kids->len))) {
      if ((i > 0)) {
        b = xn_concat(b, rt_string_from_c(", "));
      }
      b = xn_concat(b, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i))));
      i = xn_int_wrap((i + 1));
    }
    return xn_concat(b, rt_string_from_c(")"));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Member"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("0");
    }
    xn_Cls_AstNode * mb = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
    if ((xn_str_eq(mb->kind, rt_string_from_c("Name")) && xn_Cls_CGen_isDataEnum(self, mb->text))) {
      return xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_enum_"), mb->text), rt_string_from_c("_")), n->text);
    }
    if ((xn_str_eq(mb->kind, rt_string_from_c("Name")) && xn_Cls_CGen_isEnumName(self, mb->text))) {
      return xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_enum_"), mb->text), rt_string_from_c("_")), n->text);
    }
    rt_string * bt = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    rt_string * b = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if ((xn_Cls_CGen_isClass(self, bt) || (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))->kind, rt_string_from_c("Name")) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))->text, rt_string_from_c("self"))))) {
      return xn_concat(xn_concat(b, rt_string_from_c("->")), n->text);
    }
    return xn_concat(xn_concat(b, rt_string_from_c(".")), n->text);
  }
  xn_Cls_CGen_fail(self, xn_concat(rt_string_from_c("unsupported expression: "), n->kind));
  return rt_string_from_c("0");
}

static void xn_Cls_CGen_local(xn_Cls_CGen *self, xn_Cls_AstNode * st, rt_string * indent) {
  xn_arr_s * parts = xn_str_split(st->text, rt_string_from_c(" "));
  if ((((int64_t)parts->len) < 2)) {
    xn_Cls_CGen_fail(self, rt_string_from_c("malformed local"));
    return;
  }
  rt_string * ty = xn_arr_s_get(parts, 0);
  rt_string * name = xn_arr_s_get(parts, 1);
  if (xn_Cls_CGen_isFunctionType(self, ty)) {
    xn_Cls_AstNode * initNode = xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), st->line, st->col);
    if ((((int64_t)st->kids->len) > 0)) {
      initNode = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0));
    }
    if (xn_str_eq(initNode->kind, rt_string_from_c("Lambda"))) {
      int64_t li = xn_int_wrap(xn_Cls_CGen_lambdaIndex(self, initNode));
      xn_Cls_CGen_ensureLambdaCaptures(self, li, initNode);
      xn_arr_s *caps = xn_arr_s_new(0);
      xn_arr_s *capTypes = xn_arr_s_new(0);
      if ((li >= 0)) {
        caps = xn_Cls_CGen_splitCaps(self, xn_arr_s_get(self->lambdaCaptures, li));
        capTypes = xn_Cls_CGen_splitCaps(self, xn_arr_s_get(self->lambdaCaptureTypes, li));
        if ((xn_str_eq(xn_arr_s_get(self->lambdaOwners, li), rt_string_from_c("")) && (!xn_str_eq(self->curClass, rt_string_from_c(""))))) {
          xn_arr_s_set(self->lambdaOwners, li, self->curClass);
        }
      }
      rt_string * selfTy = xn_Cls_CGen_findVar(self, rt_string_from_c("self"));
      if ((((!xn_str_eq(self->curClass, rt_string_from_c(""))) && (!xn_str_eq(selfTy, rt_string_from_c("Any")))) && (!xn_Cls_CGen_listHas(self, caps, rt_string_from_c("self"))))) {
        xn_arr_s_push(caps, rt_string_from_c("self"));
        xn_arr_s_push(capTypes, selfTy);
        if ((li >= 0)) {
          xn_arr_s_set(self->lambdaCaptures, li, xn_Cls_CGen_joinCaps(self, caps));
          xn_arr_s_set(self->lambdaCaptureTypes, li, xn_Cls_CGen_joinCaps(self, capTypes));
        }
      }
      int selfCap = xn_Cls_CGen_containsVarUse(self, initNode, name);
      if (selfCap) {
        xn_arr_s *keepNames = xn_arr_s_new(0);
        xn_arr_s *keepTypes = xn_arr_s_new(0);
        int64_t ki = xn_int_wrap(0);
        while ((ki < ((int64_t)caps->len))) {
          if ((!xn_str_eq(xn_arr_s_get(caps, ki), name))) {
            xn_arr_s_push(keepNames, xn_arr_s_get(caps, ki));
            xn_arr_s_push(keepTypes, xn_arr_s_get(capTypes, ki));
          }
          ki = xn_int_wrap((ki + 1));
        }
        caps = keepNames;
        capTypes = keepTypes;
        xn_arr_s_push(caps, name);
        xn_arr_s_push(capTypes, ty);
        if ((li >= 0)) {
          xn_arr_s_set(self->lambdaCaptures, li, xn_Cls_CGen_joinCaps(self, caps));
          xn_arr_s_set(self->lambdaCaptureTypes, li, xn_Cls_CGen_joinCaps(self, capTypes));
        }
      }
      int64_t selfIdx = xn_int_wrap(xn_int_wrap(-(1)));
      int64_t sci = xn_int_wrap(0);
      while ((sci < ((int64_t)caps->len))) {
        if (xn_str_eq(xn_arr_s_get(caps, sci), name)) {
          selfIdx = sci;
        }
        sci = xn_int_wrap((sci + 1));
      }
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(indent, xn_Cls_CGen_fnPtrDecl(self, ty, name)), rt_string_from_c(";")));
      rt_string * env = xn_concat(name, rt_string_from_c("_env"));
      if ((((int64_t)caps->len) > 0)) {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("void **")), env), rt_string_from_c(" = (void **)malloc(sizeof(void *) * ")), xn_str_int(((int64_t)caps->len))), rt_string_from_c(");")));
        int64_t ci = xn_int_wrap(0);
        while ((ci < ((int64_t)caps->len))) {
          if ((ci != selfIdx)) {
            rt_string * box = xn_Cls_CGen_temp(self);
            rt_string * ct = xn_Cls_CGen_ctype(self, xn_arr_s_get(capTypes, ci));
            xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("{ ")), ct), rt_string_from_c(" *")), box), rt_string_from_c(" = (")), ct), rt_string_from_c(" *)malloc(sizeof(")), ct), rt_string_from_c(")); *")), box), rt_string_from_c(" = ")), xn_arr_s_get(caps, ci)), rt_string_from_c("; ")), env), rt_string_from_c("[")), xn_str_int(ci)), rt_string_from_c("] = ")), box), rt_string_from_c("; }")));
            if (xn_Cls_CGen_isGcRefType(self, xn_arr_s_get(capTypes, ci))) {
              xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("rt_gc_root_add((void *)")), xn_arr_s_get(caps, ci)), rt_string_from_c(");")));
            }
          }
          ci = xn_int_wrap((ci + 1));
        }
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(indent, name), rt_string_from_c(".env = (void *)")), env), rt_string_from_c(";")));
      }
      else {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(indent, name), rt_string_from_c(".env = 0;")));
      }
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(indent, name), rt_string_from_c(".fn = (void *)")), xn_Cls_CGen_lambdaName(self, initNode)), rt_string_from_c(";")));
      if ((selfIdx >= 0)) {
        rt_string * selfBox = xn_Cls_CGen_temp(self);
        rt_string * selfCt = xn_Cls_CGen_ctype(self, ty);
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("{ ")), selfCt), rt_string_from_c(" *")), selfBox), rt_string_from_c(" = (")), selfCt), rt_string_from_c(" *)malloc(sizeof(")), selfCt), rt_string_from_c(")); *")), selfBox), rt_string_from_c(" = ")), name), rt_string_from_c("; ")), env), rt_string_from_c("[")), xn_str_int(selfIdx)), rt_string_from_c("] = ")), selfBox), rt_string_from_c("; }")));
      }
    }
    else {
      rt_string * init = rt_string_from_c("{0, 0}");
      if ((((int64_t)st->kids->len) > 0)) {
        init = xn_Cls_CGen_expr(self, initNode);
      }
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(indent, xn_Cls_CGen_fnPtrDecl(self, ty, name)), rt_string_from_c(" = ")), init), rt_string_from_c(";")));
    }
    xn_Cls_CGen_addVar(self, ty, name);
    return;
  }
  if (((xn_Cls_CGen_isSet(self, ty) && (((int64_t)st->kids->len) > 0)) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))->kind, rt_string_from_c("ArrayLit")))) {
    xn_Cls_AstNode * lit = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0));
    int stringSet = xn_str_eq(ty, rt_string_from_c("Set<String>"));
    int genericSet = xn_Cls_CGen_isGenericSet(self, ty);
    rt_string * elemTy = xn_Cls_CGen_setElementOf(self, ty);
    rt_string * ek = xn_Cls_CGen_kindOf(self, elemTy);
    if (genericSet) {
      if (xn_str_eq(ek, rt_string_from_c("-1"))) {
        xn_Cls_CGen_fail(self, xn_concat(rt_string_from_c("generic Set does not support element type: "), ty));
        return;
      }
      xn_Cls_CGen_registerGenericSet(self, ty);
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_set_g *")), name), rt_string_from_c(" = xn_set_g_new(")), ek), rt_string_from_c(");")));
    }
    else {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, ((stringSet) ? (rt_string_from_c("xn_set_s *")) : (rt_string_from_c("xn_set_i *")))), name), rt_string_from_c(" = ")), ((stringSet) ? (rt_string_from_c("xn_set_s_new()")) : (rt_string_from_c("xn_set_i_new()")))), rt_string_from_c(";")));
    }
    int64_t si = xn_int_wrap(0);
    while ((si < ((int64_t)lit->kids->len))) {
      rt_string * item = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(lit->kids, si)));
      if (genericSet) {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_set_g_add(")), name), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, elemTy, item)), rt_string_from_c(");")));
      }
      else {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, ((stringSet) ? (rt_string_from_c("xn_set_s_add(")) : (rt_string_from_c("xn_set_i_add(")))), name), rt_string_from_c(", ")), item), rt_string_from_c(");")));
      }
      si = xn_int_wrap((si + 1));
    }
    xn_Cls_CGen_addVar(self, ty, name);
    return;
  }
  if ((((xn_Cls_CGen_isSet(self, ty) && (((int64_t)st->kids->len) > 0)) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))->kind, rt_string_from_c("Call"))) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))->text, rt_string_from_c("Set.of")))) {
    xn_Cls_AstNode * call = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0));
    int stringSet = xn_str_eq(ty, rt_string_from_c("Set<String>"));
    int genericSet = xn_Cls_CGen_isGenericSet(self, ty);
    rt_string * elemTy = xn_Cls_CGen_setElementOf(self, ty);
    rt_string * ek = xn_Cls_CGen_kindOf(self, elemTy);
    if (genericSet) {
      if (xn_str_eq(ek, rt_string_from_c("-1"))) {
        xn_Cls_CGen_fail(self, xn_concat(rt_string_from_c("generic Set does not support element type: "), ty));
        return;
      }
      xn_Cls_CGen_registerGenericSet(self, ty);
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_set_g *")), name), rt_string_from_c(" = xn_set_g_new(")), ek), rt_string_from_c(");")));
    }
    else {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, ((stringSet) ? (rt_string_from_c("xn_set_s *")) : (rt_string_from_c("xn_set_i *")))), name), rt_string_from_c(" = ")), ((stringSet) ? (rt_string_from_c("xn_set_s_new()")) : (rt_string_from_c("xn_set_i_new()")))), rt_string_from_c(";")));
    }
    int64_t si = xn_int_wrap(0);
    while ((si < ((int64_t)call->kids->len))) {
      rt_string * item = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(call->kids, si)));
      if (genericSet) {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_set_g_add(")), name), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, elemTy, item)), rt_string_from_c(");")));
      }
      else {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, ((stringSet) ? (rt_string_from_c("xn_set_s_add(")) : (rt_string_from_c("xn_set_i_add(")))), name), rt_string_from_c(", ")), item), rt_string_from_c(");")));
      }
      si = xn_int_wrap((si + 1));
    }
    xn_Cls_CGen_addVar(self, ty, name);
    return;
  }
  if (((((int64_t)st->kids->len) > 0) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))->kind, rt_string_from_c("Try")))) {
    xn_Cls_AstNode * tr = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0));
    if ((((int64_t)tr->kids->len) > 0)) {
      rt_string * rt = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(tr->kids, 0)));
      rt_string * tv = xn_Cls_CGen_temp(self);
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, xn_Cls_CGen_ctype(self, rt)), rt_string_from_c(" ")), tv), rt_string_from_c(" = ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(tr->kids, 0)))), rt_string_from_c(";")));
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("if (!")), tv), rt_string_from_c(".ok) {")));
      xn_Cls_CGen_emitDefers(self, xn_concat(indent, rt_string_from_c("  ")), 1);
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("  return ")), tv), rt_string_from_c(";")));
      xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("}")));
      rt_string * valueExpr = xn_concat(tv, rt_string_from_c(".value"));
      if (xn_str_eq(ty, rt_string_from_c("Int"))) {
        valueExpr = xn_concat(xn_concat(rt_string_from_c("xn_int_wrap("), valueExpr), rt_string_from_c(")"));
      }
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, xn_Cls_CGen_ctype(self, ty)), rt_string_from_c(" ")), name), rt_string_from_c(" = ")), valueExpr), rt_string_from_c(";")));
      xn_Cls_CGen_addVar(self, ty, name);
      return;
    }
  }
  if (((xn_str_eq(ty, rt_string_from_c("Map<String,Int>")) && (((int64_t)st->kids->len) > 0)) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))->kind, rt_string_from_c("MapLit")))) {
    xn_Cls_AstNode * lit = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_map_s_i *")), name), rt_string_from_c(" = xn_map_s_i_new(4);")));
    int64_t mi = xn_int_wrap(0);
    while ((xn_int_wrap((mi + 1)) < ((int64_t)lit->kids->len))) {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_map_s_i_put(")), name), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(lit->kids, mi)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(lit->kids, xn_int_wrap((mi + 1)))))), rt_string_from_c(");")));
      mi = xn_int_wrap((mi + 2));
    }
    xn_Cls_CGen_addVar(self, ty, name);
    return;
  }
  if (((xn_str_eq(ty, rt_string_from_c("Map<Int,Int>")) && (((int64_t)st->kids->len) > 0)) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))->kind, rt_string_from_c("MapLit")))) {
    xn_Cls_AstNode * lit = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_map_i_i *")), name), rt_string_from_c(" = xn_map_i_i_new(4);")));
    int64_t mi = xn_int_wrap(0);
    while ((xn_int_wrap((mi + 1)) < ((int64_t)lit->kids->len))) {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_map_i_i_put_replaced(")), name), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(lit->kids, mi)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(lit->kids, xn_int_wrap((mi + 1)))))), rt_string_from_c(");")));
      mi = xn_int_wrap((mi + 2));
    }
    xn_Cls_CGen_addVar(self, ty, name);
    return;
  }
  if (((xn_Cls_CGen_isMap(self, ty) && (((int64_t)st->kids->len) > 0)) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))->kind, rt_string_from_c("MapLit")))) {
    xn_Cls_AstNode * lit = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0));
    rt_string * keyTy = xn_Cls_CGen_mapKey(self, ty);
    rt_string * valTy = xn_Cls_CGen_mapValue(self, ty);
    rt_string * kk = xn_Cls_CGen_kindOf(self, keyTy);
    rt_string * vk = xn_Cls_CGen_kindOf(self, valTy);
    if ((xn_str_eq(kk, rt_string_from_c("-1")) || xn_str_eq(vk, rt_string_from_c("-1")))) {
      xn_Cls_CGen_fail(self, xn_concat(rt_string_from_c("generic Map does not support key/value type: "), ty));
      return;
    }
    xn_Cls_CGen_registerGenericMap(self, ty);
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_map_g *")), name), rt_string_from_c(" = xn_map_g_new(4, ")), kk), rt_string_from_c(", ")), vk), rt_string_from_c(");")));
    int64_t mi = xn_int_wrap(0);
    while ((xn_int_wrap((mi + 1)) < ((int64_t)lit->kids->len))) {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_map_g_put_replaced(")), name), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, keyTy, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(lit->kids, mi))))), rt_string_from_c(", ")), xn_Cls_CGen_encodeOf(self, valTy, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(lit->kids, xn_int_wrap((mi + 1))))))), rt_string_from_c(");")));
      mi = xn_int_wrap((mi + 2));
    }
    xn_Cls_CGen_addVar(self, ty, name);
    return;
  }
  if (((xn_Cls_CGen_isArray(self, ty) && (((int64_t)st->kids->len) > 0)) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))->kind, rt_string_from_c("ArrayLit")))) {
    xn_Cls_AstNode * lit = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0));
    rt_string * ac = xn_Cls_CGen_arrayCName(self, ty);
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, ac), rt_string_from_c(" *")), name), rt_string_from_c(" = ")), ac), rt_string_from_c("_new(")), xn_str_int(((int64_t)lit->kids->len))), rt_string_from_c(");")));
    int64_t ai = xn_int_wrap(0);
    while ((ai < ((int64_t)lit->kids->len))) {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, ac), rt_string_from_c("_push(")), name), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(lit->kids, ai)))), rt_string_from_c(");")));
      ai = xn_int_wrap((ai + 1));
    }
    xn_Cls_CGen_addVar(self, ty, name);
    return;
  }
  rt_string * init = rt_string_from_c("0");
  if ((((int64_t)st->kids->len) > 0)) {
    init = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
  }
  if ((xn_str_eq(ty, rt_string_from_c("Int")) && (((int64_t)st->kids->len) > 0))) {
    init = xn_concat(xn_concat(rt_string_from_c("xn_int_wrap("), init), rt_string_from_c(")"));
  }
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, xn_Cls_CGen_ctype(self, ty)), rt_string_from_c(" ")), name), rt_string_from_c(" = ")), init), rt_string_from_c(";")));
  xn_Cls_CGen_addVar(self, ty, name);
}

static void xn_Cls_CGen_stmt(xn_Cls_CGen *self, xn_Cls_AstNode * st, rt_string * indent) {
  if (xn_str_eq(st->kind, rt_string_from_c("Goto"))) {
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("goto ")), st->text), rt_string_from_c(";")));
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Label"))) {
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(indent, st->text), rt_string_from_c(": ;")));
    if ((((int64_t)st->kids->len) > 0)) {
      xn_Cls_CGen_stmt(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)), indent);
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Break"))) {
    if ((((int64_t)self->breakTargets->len) > 0)) {
      rt_string * target = xn_arr_s_get(self->breakTargets, xn_int_wrap((((int64_t)self->breakTargets->len) - 1)));
      if (xn_str_eq(target, rt_string_from_c("loop"))) {
        xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("break;")));
      }
      else {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("goto ")), target), rt_string_from_c(";")));
      }
    }
    else {
      xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("break;")));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Continue"))) {
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("continue;")));
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Throw"))) {
    if ((((int64_t)st->kids->len) > 0)) {
      rt_string * v = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("rt_fatal(")), v), rt_string_from_c("->bytes);")));
    }
    else {
      xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("rt_fatal(\"throw\");")));
    }
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("abort();")));
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Assign"))) {
    if ((((int64_t)st->kids->len) >= 2)) {
      rt_string * lhs = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
      xn_Cls_AstNode * rv = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1));
      xn_Cls_AstNode * lv = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0));
      if ((xn_str_eq(lv->kind, rt_string_from_c("Index")) && (((int64_t)lv->kids->len) >= 2))) {
        rt_string * at = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(lv->kids, 0)));
        if (xn_Cls_CGen_isArray(self, at)) {
          rt_string * ac = xn_Cls_CGen_arrayCName(self, at);
          xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, ac), rt_string_from_c("_set(")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(lv->kids, 0)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(lv->kids, 1)))), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, rv)), rt_string_from_c(");")));
          return;
        }
      }
      if (xn_str_eq(rv->kind, rt_string_from_c("ArrayLit"))) {
        rt_string * lt = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
        if (xn_Cls_CGen_isArray(self, lt)) {
          rt_string * ac = xn_Cls_CGen_arrayCName(self, lt);
          xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, lhs), rt_string_from_c(" = ")), ac), rt_string_from_c("_new(")), xn_str_int(((int64_t)rv->kids->len))), rt_string_from_c(");")));
          int64_t ai = xn_int_wrap(0);
          while ((ai < ((int64_t)rv->kids->len))) {
            xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, ac), rt_string_from_c("_push(")), lhs), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(rv->kids, ai)))), rt_string_from_c(");")));
            ai = xn_int_wrap((ai + 1));
          }
          return;
        }
      }
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(indent, lhs), rt_string_from_c(" = ")), xn_Cls_CGen_expr(self, rv)), rt_string_from_c(";")));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Switch"))) {
    if ((((int64_t)st->kids->len) < 2)) {
      xn_Cls_CGen_fail(self, rt_string_from_c("malformed switch"));
      return;
    }
    rt_string * vt = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    rt_string * sv = xn_Cls_CGen_temp(self);
    rt_string * swEnd = xn_Cls_CGen_temp(self);
    xn_arr_s_push(self->breakTargets, swEnd);
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("{")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("  ")), xn_Cls_CGen_ctype(self, vt)), rt_string_from_c(" ")), sv), rt_string_from_c(" = ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)))), rt_string_from_c(";")));
    int64_t si = xn_int_wrap(1);
    int hasDefault = 0;
    int first = 1;
    while ((si < ((int64_t)st->kids->len))) {
      xn_Cls_AstNode * clause = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, si));
      if ((xn_str_eq(clause->kind, rt_string_from_c("Case")) && (((int64_t)clause->kids->len) >= 2))) {
        rt_string * cond = xn_concat(xn_concat(sv, rt_string_from_c(" == ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(clause->kids, 0))));
        if (xn_str_eq(vt, rt_string_from_c("String"))) {
          cond = xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_str_eq("), sv), rt_string_from_c(", ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(clause->kids, 0)))), rt_string_from_c(")"));
        }
        if (first) {
          xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("  if (")), cond), rt_string_from_c(") {")));
          first = 0;
        }
        else {
          xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("  else if (")), cond), rt_string_from_c(") {")));
        }
        xn_Cls_CGen_blockBody(self, ((xn_Cls_AstNode *)xn_arr_o_get(clause->kids, 1)), xn_concat(indent, rt_string_from_c("    ")));
        xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("  }")));
      }
      else {
        if (xn_str_eq(clause->kind, rt_string_from_c("Default"))) {
          hasDefault = 1;
          if (first) {
            xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("  if (1) {")));
          }
          else {
            xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("  else {")));
          }
          if ((((int64_t)clause->kids->len) > 0)) {
            xn_Cls_CGen_blockBody(self, ((xn_Cls_AstNode *)xn_arr_o_get(clause->kids, 0)), xn_concat(indent, rt_string_from_c("    ")));
          }
          xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("  }")));
        }
      }
      si = xn_int_wrap((si + 1));
    }
    if (((!hasDefault) && first)) {
      xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("  {}")));
    }
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("  ")), swEnd), rt_string_from_c(": ;")));
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("}")));
    xn_arr_s_remove(self->breakTargets, xn_int_wrap((((int64_t)self->breakTargets->len) - 1)));
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("ForRange"))) {
    if ((((int64_t)st->kids->len) < 3)) {
      xn_Cls_CGen_fail(self, rt_string_from_c("malformed for-range"));
      return;
    }
    rt_string * sstart = xn_Cls_CGen_temp(self);
    rt_string * send = xn_Cls_CGen_temp(self);
    rt_string * svar = xn_str_substr(st->text, xn_int_wrap((xn_str_indexof(st->text, rt_string_from_c(" ")) + 1)), xn_int_wrap((xn_int_wrap((((int64_t)st->text->len) - xn_str_indexof(st->text, rt_string_from_c(" ")))) - 1)));
    int inclusive = xn_str_startswith(st->text, rt_string_from_c("..."));
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("{")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("  int64_t ")), sstart), rt_string_from_c(" = ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)))), rt_string_from_c(";")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("  int64_t ")), send), rt_string_from_c(" = ")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)))), rt_string_from_c(";")));
    rt_string * cmp = ((inclusive) ? (rt_string_from_c(" <= ")) : (rt_string_from_c(" < ")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("  for (int64_t ")), svar), rt_string_from_c(" = ")), sstart), rt_string_from_c("; ")), svar), cmp), send), rt_string_from_c("; ")), svar), rt_string_from_c("++) {")));
    int64_t mark = xn_int_wrap(((int64_t)self->vars->len));
    xn_Cls_CGen_addVar(self, rt_string_from_c("Int"), svar);
    xn_arr_s_push(self->breakTargets, rt_string_from_c("loop"));
    xn_Cls_CGen_blockBody(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 2)), xn_concat(indent, rt_string_from_c("    ")));
    xn_arr_s_remove(self->breakTargets, xn_int_wrap((((int64_t)self->breakTargets->len) - 1)));
    xn_Cls_CGen_popTo(self, mark);
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("  }")));
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("}")));
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("ForIn"))) {
    if ((((int64_t)st->kids->len) < 2)) {
      xn_Cls_CGen_fail(self, rt_string_from_c("malformed for-in"));
      return;
    }
    rt_string * arr = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    rt_string * et = xn_Cls_CGen_elementType(self, xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0))));
    if (xn_str_eq(et, rt_string_from_c("Any"))) {
      xn_Cls_CGen_fail(self, rt_string_from_c("for-in expects array"));
      return;
    }
    rt_string * it = xn_Cls_CGen_temp(self);
    rt_string * ix = xn_Cls_CGen_temp(self);
    rt_string * aty = xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
    rt_string * ac = xn_Cls_CGen_arrayCName(self, aty);
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("{")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("  ")), ac), rt_string_from_c(" *")), it), rt_string_from_c(" = ")), arr), rt_string_from_c(";")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("  for (size_t ")), ix), rt_string_from_c(" = 0; ")), ix), rt_string_from_c(" < ")), it), rt_string_from_c("->len; ")), ix), rt_string_from_c("++) {")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("    ")), xn_Cls_CGen_ctype(self, et)), rt_string_from_c(" ")), st->text), rt_string_from_c(" = ")), xn_Cls_CGen_arrayGet(self, aty, it, ix)), rt_string_from_c(";")));
    int64_t mark = xn_int_wrap(((int64_t)self->vars->len));
    xn_Cls_CGen_addVar(self, et, st->text);
    xn_arr_s_push(self->breakTargets, rt_string_from_c("loop"));
    xn_Cls_CGen_blockBody(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)), xn_concat(indent, rt_string_from_c("    ")));
    xn_arr_s_remove(self->breakTargets, xn_int_wrap((((int64_t)self->breakTargets->len) - 1)));
    xn_Cls_CGen_popTo(self, mark);
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("  }")));
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("}")));
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Local"))) {
    xn_Cls_CGen_local(self, st, indent);
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Return"))) {
    int err = 0;
    if ((((int64_t)st->kids->len) > 0)) {
      xn_Cls_AstNode * rv = ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0));
      if ((xn_str_eq(rv->kind, rt_string_from_c("Call")) && xn_str_eq(rv->text, rt_string_from_c("Err")))) {
        err = 1;
      }
    }
    xn_Cls_CGen_emitDefers(self, indent, err);
    if ((((int64_t)st->kids->len) == 0)) {
      xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("return;")));
    }
    else {
      rt_string * returnExpr = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)));
      if (xn_str_eq(self->curRet, rt_string_from_c("Int"))) {
        returnExpr = xn_concat(xn_concat(rt_string_from_c("xn_int_wrap("), returnExpr), rt_string_from_c(")"));
      }
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("return ")), returnExpr), rt_string_from_c(";")));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("ExprStmt"))) {
    if ((((int64_t)st->kids->len) > 0)) {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(indent, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)))), rt_string_from_c(";")));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("If"))) {
    if ((((int64_t)st->kids->len) < 2)) {
      xn_Cls_CGen_fail(self, rt_string_from_c("malformed if"));
      return;
    }
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("if (")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)))), rt_string_from_c(") {")));
    xn_Cls_CGen_blockBody(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)), xn_concat(indent, rt_string_from_c("  ")));
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("}")));
    if ((((int64_t)st->kids->len) >= 3)) {
      xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("else {")));
      xn_Cls_CGen_blockBody(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 2)), xn_concat(indent, rt_string_from_c("  ")));
      xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("}")));
    }
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("DoWhile"))) {
    if ((((int64_t)st->kids->len) < 2)) {
      xn_Cls_CGen_fail(self, rt_string_from_c("malformed do-while"));
      return;
    }
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("do {")));
    xn_arr_s_push(self->breakTargets, rt_string_from_c("loop"));
    xn_Cls_CGen_blockBody(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)), xn_concat(indent, rt_string_from_c("  ")));
    xn_arr_s_remove(self->breakTargets, xn_int_wrap((((int64_t)self->breakTargets->len) - 1)));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("} while (")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)))), rt_string_from_c(");")));
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("While"))) {
    if ((((int64_t)st->kids->len) < 2)) {
      xn_Cls_CGen_fail(self, rt_string_from_c("malformed while"));
      return;
    }
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("while (")), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 0)))), rt_string_from_c(") {")));
    xn_arr_s_push(self->breakTargets, rt_string_from_c("loop"));
    xn_Cls_CGen_blockBody(self, ((xn_Cls_AstNode *)xn_arr_o_get(st->kids, 1)), xn_concat(indent, rt_string_from_c("  ")));
    xn_arr_s_remove(self->breakTargets, xn_int_wrap((((int64_t)self->breakTargets->len) - 1)));
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("}")));
    return;
  }
  if (xn_str_eq(st->kind, rt_string_from_c("Block"))) {
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("{")));
    xn_Cls_CGen_blockBody(self, st, xn_concat(indent, rt_string_from_c("  ")));
    xn_Cls_CGen_emit(self, xn_concat(indent, rt_string_from_c("}")));
    return;
  }
  xn_Cls_CGen_fail(self, xn_concat(rt_string_from_c("unsupported statement: "), st->kind));
}

static void xn_Cls_CGen_emitDefers(xn_Cls_CGen *self, rt_string * indent, int includeErr) {
  int64_t i = xn_int_wrap(xn_int_wrap((((int64_t)self->defers->len) - 1)));
  while ((i >= 0)) {
    rt_string * isErr = xn_arr_s_get(self->deferErrs, i);
    if (((!xn_str_eq(isErr, rt_string_from_c("errdefer"))) || includeErr)) {
      xn_Cls_CGen_stmt(self, ((xn_Cls_AstNode *)xn_arr_o_get(((xn_Cls_AstNode *)xn_arr_o_get(self->defers, i))->kids, 0)), indent);
    }
    i = xn_int_wrap((i - 1));
  }
}

static void xn_Cls_CGen_blockBody(xn_Cls_CGen *self, xn_Cls_AstNode * block, rt_string * indent) {
  int64_t mark = xn_int_wrap(((int64_t)self->vars->len));
  int64_t dmark = xn_int_wrap(((int64_t)self->defers->len));
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)block->kids->len)) && (!xn_Cls_CGen_hasError(self)))) {
    xn_Cls_AstNode * st = ((xn_Cls_AstNode *)xn_arr_o_get(block->kids, i));
    if (xn_str_eq(st->kind, rt_string_from_c("Defer"))) {
      xn_arr_o_push(self->defers, st);
      xn_arr_s_push(self->deferErrs, st->text);
    }
    else {
      xn_Cls_CGen_stmt(self, st, indent);
    }
    i = xn_int_wrap((i + 1));
  }
  int64_t j = xn_int_wrap(xn_int_wrap((((int64_t)self->defers->len) - 1)));
  while ((j >= dmark)) {
    xn_Cls_AstNode * d = ((xn_Cls_AstNode *)xn_arr_o_get(self->defers, j));
    xn_Cls_CGen_stmt(self, ((xn_Cls_AstNode *)xn_arr_o_get(d->kids, 0)), indent);
    j = xn_int_wrap((j - 1));
  }
  while ((((int64_t)self->defers->len) > dmark)) {
    xn_arr_o_remove(self->defers, xn_int_wrap((((int64_t)self->defers->len) - 1)));
    xn_arr_s_remove(self->deferErrs, xn_int_wrap((((int64_t)self->deferErrs->len) - 1)));
  }
  xn_Cls_CGen_popTo(self, mark);
}

static int xn_Cls_CGen_methodStatic(xn_Cls_CGen *self, xn_Cls_AstNode * m) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)m->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(m->kids, i))->kind, rt_string_from_c("Static"))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static rt_string * xn_Cls_CGen_methodSig(xn_Cls_CGen *self, xn_Cls_AstNode * m, rt_string * cls) {
  rt_string * ret = xn_Cls_CGen_ctype(self, xn_Cls_CGen_retNode(self, m)->text);
  int st = xn_Cls_CGen_methodStatic(self, m);
  rt_string * sig = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), ret), rt_string_from_c(" xn_Cls_")), cls), rt_string_from_c("_")), m->text), rt_string_from_c("("));
  xn_arr_o * ps = xn_Cls_CGen_paramsOf(self, m);
  if (st) {
    if ((((int64_t)ps->len) == 0)) {
      sig = xn_concat(sig, rt_string_from_c("void"));
    }
  }
  else {
    sig = xn_concat(xn_concat(xn_concat(sig, rt_string_from_c("xn_Cls_")), cls), rt_string_from_c(" *self"));
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ps->len))) {
    xn_arr_s * parts = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(ps, i))->text, rt_string_from_c(" "));
    if ((((int64_t)parts->len) >= 2)) {
      if (((!st) || (i > 0))) {
        sig = xn_concat(sig, rt_string_from_c(", "));
      }
      sig = xn_concat(xn_concat(xn_concat(sig, xn_Cls_CGen_ctype(self, xn_arr_s_get(parts, 0))), rt_string_from_c(" ")), xn_arr_s_get(parts, 1));
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_concat(sig, rt_string_from_c(")"));
}

static void xn_Cls_CGen_method(xn_Cls_CGen *self, xn_Cls_AstNode * m, rt_string * cls) {
  self->curClass = cls;
  self->curRet = xn_Cls_CGen_retNode(self, m)->text;
  rt_string * sig = xn_concat(xn_Cls_CGen_methodSig(self, m, cls), rt_string_from_c(" {"));
  xn_Cls_CGen_emit(self, sig);
  xn_Cls_CGen_popTo(self, 0);
  if ((!xn_Cls_CGen_methodStatic(self, m))) {
    xn_Cls_CGen_addVar(self, cls, rt_string_from_c("self"));
  }
  xn_arr_o * ps = xn_Cls_CGen_paramsOf(self, m);
  int64_t pi = xn_int_wrap(0);
  while ((pi < ((int64_t)ps->len))) {
    xn_arr_s * pps = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(ps, pi))->text, rt_string_from_c(" "));
    if ((((int64_t)pps->len) >= 2)) {
      xn_Cls_CGen_addVar(self, xn_arr_s_get(pps, 0), xn_arr_s_get(pps, 1));
    }
    pi = xn_int_wrap((pi + 1));
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)m->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(m->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Block"))) {
      xn_Cls_CGen_blockBody(self, k, rt_string_from_c("  "));
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c("}"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  self->curClass = rt_string_from_c("");
  self->curRet = rt_string_from_c("Int");
}

static xn_Cls_AstNode * xn_Cls_CGen_ctorOf(xn_Cls_CGen *self, xn_Cls_AstNode * cls) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Ctor"))) {
      return k;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), cls->line, cls->col);
}

static void xn_Cls_CGen_genClass(xn_Cls_CGen *self, xn_Cls_AstNode * cls) {
  rt_string * cn = cls->text;
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("struct xn_Cls_"), cn), rt_string_from_c(" {")));
  xn_Cls_CGen_emit(self, rt_string_from_c("  rt_header hdr;"));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Field"))) {
      xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("  "), xn_Cls_CGen_ctype(self, xn_arr_s_get(parts, 0))), rt_string_from_c(" ")), xn_arr_s_get(parts, 1)), rt_string_from_c(";")));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c("};"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static const rt_type RT_TYPE_XN_"), cn), rt_string_from_c(" = { \"")), cn), rt_string_from_c("\", sizeof(xn_Cls_")), cn), rt_string_from_c("), NULL, NULL };")));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  xn_Cls_AstNode * ctor = xn_Cls_CGen_ctorOf(self, cls);
  rt_string * csig = xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static xn_Cls_"), cn), rt_string_from_c(" *xn_Cls_")), cn), rt_string_from_c("_new("));
  xn_arr_o * cps = xn_Cls_CGen_paramsOf(self, ctor);
  if ((((int64_t)cps->len) == 0)) {
    csig = xn_concat(csig, rt_string_from_c("void"));
  }
  else {
    int64_t ci = xn_int_wrap(0);
    while ((ci < ((int64_t)cps->len))) {
      if ((ci > 0)) {
        csig = xn_concat(csig, rt_string_from_c(", "));
      }
      xn_arr_s * cpp = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(cps, ci))->text, rt_string_from_c(" "));
      if ((((int64_t)cpp->len) >= 2)) {
        csig = xn_concat(xn_concat(xn_concat(csig, xn_Cls_CGen_ctype(self, xn_arr_s_get(cpp, 0))), rt_string_from_c(" ")), xn_arr_s_get(cpp, 1));
      }
      ci = xn_int_wrap((ci + 1));
    }
  }
  xn_Cls_CGen_emit(self, xn_concat(csig, rt_string_from_c(") {")));
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("  xn_Cls_"), cn), rt_string_from_c(" *xn_obj = (xn_Cls_")), cn), rt_string_from_c(" *)rt_gc_new(&RT_TYPE_XN_")), cn), rt_string_from_c(");")));
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_"), cn), rt_string_from_c(") - sizeof(rt_header));")));
  self->curClass = cn;
  i = 0;
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Field"))) {
      xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        rt_string * ty = xn_arr_s_get(parts, 0);
        rt_string * fn = xn_arr_s_get(parts, 1);
        rt_string * init = rt_string_from_c("0");
        if (xn_str_eq(ty, rt_string_from_c("String"))) {
          init = rt_string_from_c("rt_string_from_c(\"\")");
        }
        if (xn_Cls_CGen_isFunctionType(self, ty)) {
          init = rt_string_from_c("(xn_closure){0, 0}");
        }
        if (xn_Cls_CGen_isArray(self, ty)) {
          init = xn_Cls_CGen_arrayNew(self, ty, 4);
        }
        if ((((int64_t)k->kids->len) > 0)) {
          if ((xn_Cls_CGen_isArray(self, ty) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(k->kids, 0))->kind, rt_string_from_c("ArrayLit")))) {
            xn_Cls_AstNode * lit = ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, 0));
            init = xn_Cls_CGen_arrayNew(self, ty, ((int64_t)lit->kids->len));
          }
          else {
            init = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, 0)));
          }
        }
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("  xn_obj->"), fn), rt_string_from_c(" = ")), init), rt_string_from_c(";")));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  if (xn_str_eq(ctor->kind, rt_string_from_c("Ctor"))) {
    self->curClass = cn;
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("  xn_Cls_"), cn), rt_string_from_c(" *self = xn_obj;")));
    xn_Cls_CGen_popTo(self, 0);
    xn_Cls_CGen_addVar(self, cn, rt_string_from_c("self"));
    int64_t pi = xn_int_wrap(0);
    while ((pi < ((int64_t)cps->len))) {
      xn_arr_s * cpp = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(cps, pi))->text, rt_string_from_c(" "));
      if ((((int64_t)cpp->len) >= 2)) {
        xn_Cls_CGen_addVar(self, xn_arr_s_get(cpp, 0), xn_arr_s_get(cpp, 1));
      }
      pi = xn_int_wrap((pi + 1));
    }
    int64_t bi = xn_int_wrap(0);
    while ((bi < ((int64_t)ctor->kids->len))) {
      xn_Cls_AstNode * ck = ((xn_Cls_AstNode *)xn_arr_o_get(ctor->kids, bi));
      if (xn_str_eq(ck->kind, rt_string_from_c("Block"))) {
        xn_Cls_CGen_blockBody(self, ck, rt_string_from_c("  "));
      }
      bi = xn_int_wrap((bi + 1));
    }
    xn_Cls_CGen_popTo(self, 0);
  }
  self->curClass = rt_string_from_c("");
  xn_Cls_CGen_emit(self, rt_string_from_c("  return xn_obj;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("}"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  i = 0;
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Method"))) {
      xn_Cls_CGen_emit(self, xn_concat(xn_Cls_CGen_methodSig(self, k, cn), rt_string_from_c(";")));
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  i = 0;
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Method"))) {
      xn_Cls_CGen_method(self, k, cn);
    }
    i = xn_int_wrap((i + 1));
  }
}

static rt_string * xn_Cls_CGen_funcProto(xn_Cls_CGen *self, xn_Cls_AstNode * fn) {
  rt_string * ret = xn_Cls_CGen_ctype(self, xn_Cls_CGen_retNode(self, fn)->text);
  rt_string * sig = xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), ret), rt_string_from_c(" xn_")), fn->text), rt_string_from_c("("));
  xn_arr_o * ps = xn_Cls_CGen_paramsOf(self, fn);
  if ((((int64_t)ps->len) == 0)) {
    sig = xn_concat(sig, rt_string_from_c("void"));
  }
  else {
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)ps->len))) {
      if ((i > 0)) {
        sig = xn_concat(sig, rt_string_from_c(", "));
      }
      xn_arr_s * parts = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(ps, i))->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        sig = xn_concat(xn_concat(xn_concat(sig, xn_Cls_CGen_ctype(self, xn_arr_s_get(parts, 0))), rt_string_from_c(" ")), xn_arr_s_get(parts, 1));
      }
      i = xn_int_wrap((i + 1));
    }
  }
  return xn_concat(sig, rt_string_from_c(");"));
}

static void xn_Cls_CGen_func(xn_Cls_CGen *self, xn_Cls_AstNode * fn) {
  rt_string * name = fn->text;
  rt_string * ret = xn_Cls_CGen_ctype(self, xn_Cls_CGen_retNode(self, fn)->text);
  rt_string * sig = xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), ret), rt_string_from_c(" xn_")), name), rt_string_from_c("("));
  xn_arr_o * ps = xn_Cls_CGen_paramsOf(self, fn);
  if ((((int64_t)ps->len) == 0)) {
    sig = xn_concat(sig, rt_string_from_c("void"));
  }
  else {
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)ps->len))) {
      if ((i > 0)) {
        sig = xn_concat(sig, rt_string_from_c(", "));
      }
      xn_arr_s * parts = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(ps, i))->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) < 2)) {
        xn_Cls_CGen_fail(self, rt_string_from_c("malformed parameter"));
        return;
      }
      sig = xn_concat(xn_concat(xn_concat(sig, xn_Cls_CGen_ctype(self, xn_arr_s_get(parts, 0))), rt_string_from_c(" ")), xn_arr_s_get(parts, 1));
      i = xn_int_wrap((i + 1));
    }
  }
  sig = xn_concat(sig, rt_string_from_c(") {"));
  xn_Cls_CGen_emit(self, sig);
  self->curRet = xn_Cls_CGen_retNode(self, fn)->text;
  xn_Cls_CGen_popTo(self, 0);
  int64_t pi = xn_int_wrap(0);
  while ((pi < ((int64_t)ps->len))) {
    xn_arr_s * pps = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(ps, pi))->text, rt_string_from_c(" "));
    if ((((int64_t)pps->len) >= 2)) {
      xn_Cls_CGen_addVar(self, xn_arr_s_get(pps, 0), xn_arr_s_get(pps, 1));
    }
    pi = xn_int_wrap((pi + 1));
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fn->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Block"))) {
      xn_Cls_CGen_blockBody(self, k, rt_string_from_c("  "));
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c("}"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
}

static void xn_Cls_CGen_gen(xn_Cls_CGen *self) {
  int64_t lci = xn_int_wrap(0);
  while ((lci < ((int64_t)self->program->kids->len))) {
    xn_Cls_CGen_collectLambdas(self, ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, lci)), rt_string_from_c(""));
    lci = xn_int_wrap((lci + 1));
  }
  xn_Cls_CGen_collectGenericTypes(self, self->program);
  xn_Cls_CGen_emit(self, rt_string_from_c("#include \"rt.h\""));
  xn_Cls_CGen_emit(self, rt_string_from_c("#include \"rt_gc.h\""));
  xn_Cls_CGen_emit(self, rt_string_from_c("#include \"xrt.h\""));
  xn_Cls_CGen_emit(self, rt_string_from_c("#include <stdint.h>"));
  xn_Cls_CGen_emit(self, rt_string_from_c("#include <stdio.h>"));
  xn_Cls_CGen_emit(self, rt_string_from_c("#include <stdlib.h>"));
  xn_Cls_CGen_emit(self, rt_string_from_c("#include <unistd.h>"));
  xn_Cls_CGen_emit(self, rt_string_from_c("#include <string.h>"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { void *env; void *fn; } xn_closure;"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_int_wrap(int64_t value) { return (int64_t)(int32_t)value; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_int_shl(int64_t value, int64_t bitCount) { if (bitCount < 0 || bitCount >= 32) { rt_fatal(\"shift count out of range\"); } return (int64_t)((uint32_t)value << (uint32_t)bitCount); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_int_shr(int64_t value, int64_t bitCount) { if (bitCount < 0 || bitCount >= 32) { rt_fatal(\"shift count out of range\"); } return (int64_t)((int32_t)value >> (int32_t)bitCount); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)xn_int_wrap(v)); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_print_bool(int v) { printf(v ? \"true\\n\" : \"false\\n\"); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_print_double(double v) { printf(\"%g\\n\", v); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_str_int(int64_t v) { char buf[32]; snprintf(buf, sizeof(buf), \"%lld\", (long long)xn_int_wrap(v)); return rt_string_from_c(buf); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_str_long(int64_t v) { char buf[32]; snprintf(buf, sizeof(buf), \"%lld\", (long long)v); return rt_string_from_c(buf); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_print_long(int64_t v) { printf(\"%lld\\n\", (long long)v); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static __int128 xn_int128_from_dec(const char *s) { unsigned __int128 u = 0; int neg = 0; if (*s == '-') { neg = 1; s++; } while (*s >= '0' && *s <= '9') { u = u * 10 + (unsigned __int128)(*s - '0'); s++; } return neg ? -(__int128)u : (__int128)u; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_print_int128(__int128 v) { char buf[64]; int n = 0; unsigned __int128 u; if (v < 0) { putchar('-'); u = (unsigned __int128)(-(v + 1)) + 1; } else { u = (unsigned __int128)v; } do { buf[n++] = (char)('0' + (int)(u % 10)); u /= 10; } while (u != 0); while (n > 0) { putchar(buf[--n]); } putchar('\\n'); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_str_int128(__int128 v) { char buf[64]; int n = 0; unsigned __int128 u; if (v < 0) { buf[n++] = '-'; u = (unsigned __int128)(-(v + 1)) + 1; } else { u = (unsigned __int128)v; } int start = n; do { buf[n++] = (char)('0' + (int)(u % 10)); u /= 10; } while (u != 0); for (int i = start, j = n - 1; i < j; i++, j--) { char t = buf[i]; buf[i] = buf[j]; buf[j] = t; } buf[n] = 0; return rt_string_from_c(buf); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_str_double(double v) { char buf[64]; snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_from_c(buf); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_bytes_to_string(xrt_bytes_obj *buffer) { return rt_string_new((const char *)xrt_bytes_data(buffer), (size_t)xrt_bytes_len(buffer)); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_str_char(int32_t cp) { char b[5]; int n = 0; if (cp < 0) { cp = 0xFFFD; } if (cp < 0x80) { b[n++] = (char)cp; } else if (cp < 0x800) { b[n++] = (char)(0xC0 | (cp >> 6)); b[n++] = (char)(0x80 | (cp & 0x3F)); } else if (cp < 0x10000) { b[n++] = (char)(0xE0 | (cp >> 12)); b[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); b[n++] = (char)(0x80 | (cp & 0x3F)); } else { b[n++] = (char)(0xF0 | (cp >> 18)); b[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); b[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); b[n++] = (char)(0x80 | (cp & 0x3F)); } b[n] = 0; return rt_string_from_c(b); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) { if (start < 0) { start = 0; } if (n < 0) { n = 0; } if ((size_t)start > s->len) { start = (int64_t)s->len; } if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; } rt_string *out = rt_string_alloc((size_t)n); if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); } out->bytes[n] = 0; return out; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_str_indexof(rt_string *s, rt_string *sub) { if (sub->len == 0) { return 0; } if (sub->len > s->len) { return -1; } for (size_t i = 0; i + sub->len <= s->len; i++) { if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; } } return -1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_str_eq(rt_string *a, rt_string *b) { return (a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0) ? 1 : 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_concat(rt_string *a, rt_string *b) { size_t n = a->len + b->len; rt_string *r = rt_string_alloc(n); memcpy(r->bytes, a->bytes, a->len); memcpy(r->bytes + a->len, b->bytes, b->len); r->bytes[n] = 0; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_ARR_I = { \"List\", sizeof(xn_arr_i), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_i *xn_arr_i_new(size_t cap) { xn_arr_i *a = (xn_arr_i *)rt_gc_new(&RT_TYPE_XN_ARR_I); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_i) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (int64_t *)malloc(sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } return a; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_i_push(xn_arr_i *a, int64_t v) { if (a->len == a->cap) { a->cap *= 2; a->data = (int64_t *)realloc(a->data, sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_i_remove(xn_arr_i *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_i_set(xn_arr_i *a, int64_t i, int64_t v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_i_insert(xn_arr_i *a, int64_t i, int64_t v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (int64_t *)realloc(a->data, sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; double *data; } xn_arr_d;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_ARR_D = { \"List\", sizeof(xn_arr_d), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_d *xn_arr_d_new(size_t cap) { xn_arr_d *a = (xn_arr_d *)rt_gc_new(&RT_TYPE_XN_ARR_D); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_d) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (double *)malloc(sizeof(double) * a->cap); if (a->data == NULL) { abort(); } return a; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_d_push(xn_arr_d *a, double v) { if (a->len == a->cap) { a->cap *= 2; a->data = (double *)realloc(a->data, sizeof(double) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static double xn_arr_d_get(const xn_arr_d *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_d_remove(xn_arr_d *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_d_set(xn_arr_d *a, int64_t i, double v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_d_insert(xn_arr_d *a, int64_t i, double v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (double *)realloc(a->data, sizeof(double) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; rt_string **data; } xn_arr_s;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_ARR_S = { \"List\", sizeof(xn_arr_s), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_s *xn_arr_s_new(size_t cap) { xn_arr_s *a = (xn_arr_s *)rt_gc_new(&RT_TYPE_XN_ARR_S); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_s) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (rt_string **)malloc(sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } return a; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_s_push(xn_arr_s *a, rt_string *v) { if (a->len == a->cap) { a->cap *= 2; a->data = (rt_string **)realloc(a->data, sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_arr_s_get(const xn_arr_s *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_s_remove(xn_arr_s *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_s_set(xn_arr_s *a, int64_t i, rt_string *v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_s_insert(xn_arr_s *a, int64_t i, rt_string *v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (rt_string **)realloc(a->data, sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; void **data; } xn_arr_o;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_ARR_O = { \"List\", sizeof(xn_arr_o), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_o *xn_arr_o_new(size_t cap) { xn_arr_o *a = (xn_arr_o *)rt_gc_new(&RT_TYPE_XN_ARR_O); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_o) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (void **)malloc(sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } return a; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_o_push(xn_arr_o *a, void *v) { if (a->len == a->cap) { a->cap *= 2; a->data = (void **)realloc(a->data, sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void *xn_arr_o_get(const xn_arr_o *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_o_remove(xn_arr_o *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_o_set(xn_arr_o *a, int64_t i, void *v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_o_insert(xn_arr_o *a, int64_t i, void *v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (void **)realloc(a->data, sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_str_startswith(rt_string *s, rt_string *p) { if (p->len > s->len) { return 0; } return memcmp(s->bytes, p->bytes, p->len) == 0 ? 1 : 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_str_endswith(rt_string *s, rt_string *p) { if (p->len > s->len) { return 0; } return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0 ? 1 : 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_str_trim(rt_string *s) { size_t a = 0, b = s->len; while (a < b && (s->bytes[a] == ' ' || s->bytes[a] == '\\t' || s->bytes[a] == '\\n' || s->bytes[a] == '\\r' || s->bytes[a] == '\\v' || s->bytes[a] == '\\f')) { a++; } while (b > a && (s->bytes[b-1] == ' ' || s->bytes[b-1] == '\\t' || s->bytes[b-1] == '\\n' || s->bytes[b-1] == '\\r' || s->bytes[b-1] == '\\v' || s->bytes[b-1] == '\\f')) { b--; } rt_string *r = rt_string_alloc(b - a); if (b > a) { memcpy(r->bytes, s->bytes + a, b - a); } r->bytes[b-a] = 0; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_str_case(rt_string *s, int upper) { rt_string *r = rt_string_alloc(s->len); for (size_t i = 0; i < s->len; i++) { unsigned char c = (unsigned char)s->bytes[i]; if (upper && c >= 'a' && c <= 'z') { c = (unsigned char)(c - 32); } else if (!upper && c >= 'A' && c <= 'Z') { c = (unsigned char)(c + 32); } r->bytes[i] = (char)c; } r->bytes[s->len] = 0; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_str_replace(rt_string *s, rt_string *from, rt_string *to) { if (from->len == 0) { return s; } size_t cap = s->len + 8, n = 0; char *buf = (char *)malloc(cap); if (buf == NULL) { abort(); } for (size_t i = 0; i < s->len; ) { if (i + from->len <= s->len && memcmp(s->bytes + i, from->bytes, from->len) == 0) { while (n + to->len + 1 > cap) { cap *= 2; buf = (char *)realloc(buf, cap); if (buf == NULL) { abort(); } } memcpy(buf + n, to->bytes, to->len); n += to->len; i += from->len; } else { while (n + 2 > cap) { cap *= 2; buf = (char *)realloc(buf, cap); if (buf == NULL) { abort(); } } buf[n++] = s->bytes[i++]; } } buf[n] = 0; rt_string *r = rt_string_from_c(buf); free(buf); return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_s *xn_str_split(rt_string *s, rt_string *sep) { xn_arr_s *out = xn_arr_s_new(4); if (sep->len == 0) { xn_arr_s_push(out, s); return out; } size_t start = 0; size_t i = 0; while (i + sep->len <= s->len) { if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) { size_t n = i - start; rt_string *p = rt_string_alloc(n); if (n > 0) { memcpy(p->bytes, s->bytes + start, n); } p->bytes[n] = 0; xn_arr_s_push(out, p); i = i + sep->len; start = i; } else { i++; } } { size_t n = s->len - start; rt_string *p = rt_string_alloc(n); if (n > 0) { memcpy(p->bytes, s->bytes + start, n); } p->bytes[n] = 0; xn_arr_s_push(out, p); } return out; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static rt_string *xn_arr_s_join(xn_arr_s *a, rt_string *sep) { size_t n = 0; for (size_t i = 0; i < a->len; i++) { n += a->data[i]->len; if (i > 0) { n += sep->len; } } rt_string *r = rt_string_alloc(n); size_t off = 0; for (size_t i = 0; i < a->len; i++) { if (i > 0) { memcpy(r->bytes + off, sep->bytes, sep->len); off += sep->len; } memcpy(r->bytes + off, a->data[i]->bytes, a->data[i]->len); off += a->data[i]->len; } r->bytes[n] = 0; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; rt_string **keys; int64_t *vals; } xn_map_s_i;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_MAP_S_I = { \"Map\", sizeof(xn_map_s_i), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_map_s_i *xn_map_s_i_new(size_t cap) { xn_map_s_i *m = (xn_map_s_i *)rt_gc_new(&RT_TYPE_XN_MAP_S_I); memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_s_i) - sizeof(rt_header)); m->cap = cap ? cap : 4; m->keys = (rt_string **)malloc(sizeof(rt_string *) * m->cap); m->vals = (int64_t *)malloc(sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } return m; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static long xn_map_s_i_find(const xn_map_s_i *m, rt_string *key) { for (size_t i = 0; i < m->len; i++) { if (m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0) { return (long)i; } } return -1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_map_s_i_has(const xn_map_s_i *m, rt_string *key) { return xn_map_s_i_find(m, key) >= 0 ? 1 : 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_map_s_i_put(xn_map_s_i *m, rt_string *key, int64_t val) { long i = xn_map_s_i_find(m, key); if (i >= 0) { m->vals[i] = val; return; } if (m->len == m->cap) { m->cap *= 2; m->keys = (rt_string **)realloc(m->keys, sizeof(rt_string *) * m->cap); m->vals = (int64_t *)realloc(m->vals, sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } } m->keys[m->len] = key; m->vals[m->len] = val; m->len++; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_map_s_i_getOr(const xn_map_s_i *m, rt_string *key, int64_t dflt) { long i = xn_map_s_i_find(m, key); return i >= 0 ? m->vals[i] : dflt; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_map_s_i_put_replaced(xn_map_s_i *m, rt_string *key, int64_t val) { long i = xn_map_s_i_find(m, key); if (i >= 0) { m->vals[i] = val; return 1; } if (m->len == m->cap) { m->cap *= 2; m->keys = (rt_string **)realloc(m->keys, sizeof(rt_string *) * m->cap); m->vals = (int64_t *)realloc(m->vals, sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } } m->keys[m->len] = key; m->vals[m->len] = val; m->len++; return 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_map_s_i_remove(xn_map_s_i *m, rt_string *key) { long i = xn_map_s_i_find(m, key); if (i < 0) { return 0; } for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return 1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_map_s_i_remove_value(xn_map_s_i *m, rt_string *key, int64_t fallback) { long i = xn_map_s_i_find(m, key); if (i < 0) { return fallback; } int64_t v = m->vals[i]; for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_o *xn_map_s_i_entries(const xn_map_s_i *m);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_s *xn_map_s_i_keys(const xn_map_s_i *m) { xn_arr_s *out = xn_arr_s_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_s_push(out, m->keys[i]); } return out; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_i *xn_map_s_i_values(const xn_map_s_i *m) { xn_arr_i *out = xn_arr_i_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(out, m->vals[i]); } return out; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_set_i;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_SET_I = { \"Set\", sizeof(xn_set_i), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_set_i *xn_set_i_new(void) { xn_set_i *s = (xn_set_i *)rt_gc_new(&RT_TYPE_XN_SET_I); memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_i) - sizeof(rt_header)); s->cap = 4; s->data = (int64_t *)malloc(sizeof(int64_t) * s->cap); if (s->data == NULL) { abort(); } return s; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_set_i_has(const xn_set_i *s, int64_t v) { for (size_t i = 0; i < s->len; i++) { if (s->data[i] == v) { return 1; } } return 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_set_i_add(xn_set_i *s, int64_t v) { if (xn_set_i_has(s, v)) { return 0; } if (s->len == s->cap) { s->cap *= 2; s->data = (int64_t *)realloc(s->data, sizeof(int64_t) * s->cap); if (s->data == NULL) { abort(); } } s->data[s->len++] = v; return 1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_set_i_remove(xn_set_i *s, int64_t v) { for (size_t i = 0; i < s->len; i++) { if (s->data[i] == v) { for (size_t j = i; j + 1 < s->len; j++) { s->data[j] = s->data[j + 1]; } s->len--; return 1; } } return 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *keys; int64_t *vals; } xn_map_i_i;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_MAP_I_I = { \"Map\", sizeof(xn_map_i_i), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_map_i_i *xn_map_i_i_new(size_t cap) { xn_map_i_i *m = (xn_map_i_i *)rt_gc_new(&RT_TYPE_XN_MAP_I_I); memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_i_i) - sizeof(rt_header)); m->cap = cap ? cap : 4; m->keys = (int64_t *)malloc(sizeof(int64_t) * m->cap); m->vals = (int64_t *)malloc(sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } return m; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static long xn_map_i_i_find(const xn_map_i_i *m, int64_t key) { for (size_t i = 0; i < m->len; i++) { if (m->keys[i] == key) { return (long)i; } } return -1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_map_i_i_has(const xn_map_i_i *m, int64_t key) { return xn_map_i_i_find(m, key) >= 0 ? 1 : 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_map_i_i_getOr(const xn_map_i_i *m, int64_t key, int64_t fallback) { long i = xn_map_i_i_find(m, key); return i >= 0 ? m->vals[i] : fallback; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_map_i_i_put_replaced(xn_map_i_i *m, int64_t key, int64_t val) { long i = xn_map_i_i_find(m, key); if (i >= 0) { m->vals[i] = val; return 1; } if (m->len == m->cap) { m->cap *= 2; m->keys = (int64_t *)realloc(m->keys, sizeof(int64_t) * m->cap); m->vals = (int64_t *)realloc(m->vals, sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } } m->keys[m->len] = key; m->vals[m->len] = val; m->len++; return 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_map_i_i_remove(xn_map_i_i *m, int64_t key) { long i = xn_map_i_i_find(m, key); if (i < 0) { return 0; } for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return 1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_map_i_i_remove_value(xn_map_i_i *m, int64_t key, int64_t fallback) { long i = xn_map_i_i_find(m, key); if (i < 0) { return fallback; } int64_t v = m->vals[i]; for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_i *xn_map_i_i_keys(const xn_map_i_i *m) { xn_arr_i *out = xn_arr_i_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(out, m->keys[i]); } return out; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_i *xn_map_i_i_values(const xn_map_i_i *m) { xn_arr_i *out = xn_arr_i_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(out, m->vals[i]); } return out; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_o *xn_map_i_i_entries(const xn_map_i_i *m);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; rt_string **data; } xn_set_s;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_SET_S = { \"Set\", sizeof(xn_set_s), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_set_s *xn_set_s_new(void) { xn_set_s *s = (xn_set_s *)rt_gc_new(&RT_TYPE_XN_SET_S); memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_s) - sizeof(rt_header)); s->cap = 4; s->data = (rt_string **)malloc(sizeof(rt_string *) * s->cap); if (s->data == NULL) { abort(); } return s; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_set_s_has(const xn_set_s *s, rt_string *v) { for (size_t i = 0; i < s->len; i++) { if (s->data[i]->len == v->len && memcmp(s->data[i]->bytes, v->bytes, v->len) == 0) { return 1; } } return 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_set_s_add(xn_set_s *s, rt_string *v) { if (xn_set_s_has(s, v)) { return 0; } if (s->len == s->cap) { s->cap *= 2; s->data = (rt_string **)realloc(s->data, sizeof(rt_string *) * s->cap); if (s->data == NULL) { abort(); } } s->data[s->len++] = v; return 1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_set_s_remove(xn_set_s *s, rt_string *v) { for (size_t i = 0; i < s->len; i++) { if (s->data[i]->len == v->len && memcmp(s->data[i]->bytes, v->bytes, v->len) == 0) { for (size_t j = i; j + 1 < s->len; j++) { s->data[j] = s->data[j + 1]; } s->len--; return 1; } } return 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; void **keys; void **vals; int keyKind; int valKind; } xn_map_g;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_MAP_G = { \"Map\", sizeof(xn_map_g), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void *xn_double_to_ptr(double v) { uint64_t bits; memcpy(&bits, &v, sizeof(bits)); return (void *)(uintptr_t)bits; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static double xn_ptr_to_double(void *p) { uint64_t bits = (uint64_t)(uintptr_t)p; double v; memcpy(&v, &bits, sizeof(v)); return v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_map_g_key_eq(int kind, void *a, void *b) { if (kind == 1) { return xn_str_eq((rt_string *)a, (rt_string *)b); } if (kind == 2) { return (uint64_t)(uintptr_t)a == (uint64_t)(uintptr_t)b; } return a == b; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_map_g *xn_map_g_new(size_t cap, int kk, int vk) { xn_map_g *m = (xn_map_g *)rt_gc_new(&RT_TYPE_XN_MAP_G); memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_g) - sizeof(rt_header)); m->cap = cap ? cap : 4; m->keys = (void **)malloc(sizeof(void *) * m->cap); m->vals = (void **)malloc(sizeof(void *) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } m->keyKind = kk; m->valKind = vk; return m; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static long xn_map_g_find(const xn_map_g *m, void *key) { for (size_t i = 0; i < m->len; i++) { if (xn_map_g_key_eq(m->keyKind, m->keys[i], key)) { return (long)i; } } return -1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_map_g_has(const xn_map_g *m, void *key) { return xn_map_g_find(m, key) >= 0 ? 1 : 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_map_g_put_replaced(xn_map_g *m, void *key, void *val) { long i = xn_map_g_find(m, key); if (i >= 0) { m->vals[i] = val; return 1; } if (m->len == m->cap) { m->cap *= 2; m->keys = (void **)realloc(m->keys, sizeof(void *) * m->cap); m->vals = (void **)realloc(m->vals, sizeof(void *) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } } m->keys[m->len] = key; m->vals[m->len] = val; m->len++; return 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void *xn_map_g_getOr(const xn_map_g *m, void *key, void *fallback) { long i = xn_map_g_find(m, key); return i >= 0 ? m->vals[i] : fallback; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_map_g_remove(xn_map_g *m, void *key) { long i = xn_map_g_find(m, key); if (i < 0) { return 0; } for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return 1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void *xn_map_g_remove_value(xn_map_g *m, void *key, void *fallback) { long i = xn_map_g_find(m, key); if (i < 0) { return fallback; } void *v = m->vals[i]; for (size_t j = (size_t)i; j + 1 < m->len; j++) { m->keys[j] = m->keys[j + 1]; m->vals[j] = m->vals[j + 1]; } m->len--; return v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; void **data; int elemKind; } xn_set_g;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_SET_G = { \"Set\", sizeof(xn_set_g), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_set_g *xn_set_g_new(int ek) { xn_set_g *s = (xn_set_g *)rt_gc_new(&RT_TYPE_XN_SET_G); memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_g) - sizeof(rt_header)); s->cap = 4; s->data = (void **)malloc(sizeof(void *) * s->cap); if (s->data == NULL) { abort(); } s->elemKind = ek; return s; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_set_g_has(const xn_set_g *s, void *v) { for (size_t i = 0; i < s->len; i++) { if (xn_map_g_key_eq(s->elemKind, s->data[i], v)) { return 1; } } return 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_set_g_add(xn_set_g *s, void *v) { if (xn_set_g_has(s, v)) { return 0; } if (s->len == s->cap) { s->cap *= 2; s->data = (void **)realloc(s->data, sizeof(void *) * s->cap); if (s->data == NULL) { abort(); } } s->data[s->len++] = v; return 1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int xn_set_g_remove(xn_set_g *s, void *v) { for (size_t i = 0; i < s->len; i++) { if (xn_map_g_key_eq(s->elemKind, s->data[i], v)) { for (size_t j = i; j + 1 < s->len; j++) { s->data[j] = s->data[j + 1]; } s->len--; return 1; } } return 0; }"));
  int64_t gmi = xn_int_wrap(0);
  while ((gmi < ((int64_t)self->genericMaps->len))) {
    rt_string * gty = xn_arr_s_get(self->genericMaps, gmi);
    rt_string * kty = xn_Cls_CGen_mapKey(self, gty);
    rt_string * vty = xn_Cls_CGen_mapValue(self, gty);
    rt_string * kac = xn_Cls_CGen_arrayCName(self, xn_concat(xn_concat(rt_string_from_c("List<"), kty), rt_string_from_c(">")));
    rt_string * vac = xn_Cls_CGen_arrayCName(self, xn_concat(xn_concat(rt_string_from_c("List<"), vty), rt_string_from_c(">")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), kac), rt_string_from_c(" *")), xn_Cls_CGen_genericMapKeysName(self, gty)), rt_string_from_c("(const xn_map_g *m);")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), vac), rt_string_from_c(" *")), xn_Cls_CGen_genericMapValuesName(self, gty)), rt_string_from_c("(const xn_map_g *m);")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("static xn_arr_o *"), xn_Cls_CGen_genericMapEntriesName(self, gty)), rt_string_from_c("(const xn_map_g *m);")));
    gmi = xn_int_wrap((gmi + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  xn_Cls_CGen_emit(self, rt_string_from_c("const char *mini_read_file(const char *path, size_t len);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("const char *mini_list_x(const char *path, size_t len);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const char *mini_platform(void) { return \"darwin\"; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int32_t mini_file_exists(const char *path_bytes, size_t path_len) { char *p = (char *)malloc(path_len + 1); if (p == NULL) { return 0; } memcpy(p, path_bytes, path_len); p[path_len] = 0; int ok = access(p, F_OK) == 0; free(p); return ok ? 1 : 0; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("int32_t xdkc_p_resource_exists(const char *path, size_t len);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("const char *xdkc_p_read_resource_text(const char *path, size_t len);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("int64_t xdkc_p_resource_count(void);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("const char *xdkc_read_file_text(const char *bytes, size_t len);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("int32_t xdkc_read_file_text_error(void);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("int32_t xdkc_diagnose_rc(const char *bytes, size_t len);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("int32_t xdkc_exit_rc(int32_t code);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("int64_t xdkc_now_mono_ms(void);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("int64_t xdkc_now_wall_ms(void);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { int ok; int64_t value; rt_string *error; } xn_Result_Int_String;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { int ok; int64_t i; double d; rt_string *s; void *p; void *err; __int128 q; } xn_Result;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void *xn_box_result(xn_Result v) { xn_Result *p = (xn_Result *)malloc(sizeof(xn_Result)); if (p == NULL) { abort(); } *p = v; return (void *)p; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; int64_t kind; rt_string *message; } xn_builtin_error;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_BUILTIN_ERROR = { \"BuiltinError\", sizeof(xn_builtin_error), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_builtin_error *xn_builtin_error_new(int64_t kind, const char *message) { xn_builtin_error *e = (xn_builtin_error *)rt_gc_new(&RT_TYPE_XN_BUILTIN_ERROR); memset((char *)e + sizeof(rt_header), 0, sizeof(xn_builtin_error) - sizeof(rt_header)); e->kind = kind; e->message = rt_string_from_c(message); return e; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_arr_i_try_remove(xn_arr_i *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { return (xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, \"tryRemove: index out of range\") }; } int64_t v = a->data[i]; for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; return (xn_Result){ .ok = 1, .i = v }; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_arr_d_try_remove(xn_arr_d *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { return (xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, \"tryRemove: index out of range\") }; } double v = a->data[i]; for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; return (xn_Result){ .ok = 1, .d = v }; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_arr_s_try_remove(xn_arr_s *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { return (xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, \"tryRemove: index out of range\") }; } rt_string *v = a->data[i]; for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; return (xn_Result){ .ok = 1, .s = v }; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_arr_o_try_remove(xn_arr_o *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { return (xn_Result){ .ok = 0, .err = (void *)xn_builtin_error_new(0, \"tryRemove: index out of range\") }; } void *v = a->data[i]; for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; return (xn_Result){ .ok = 1, .p = v }; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("typedef struct { rt_header hdr; size_t len; size_t cap; xn_Result *data; } xn_arr_r;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const rt_type RT_TYPE_XN_ARR_R = { \"List\", sizeof(xn_arr_r), NULL, NULL };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_r *xn_arr_r_new(size_t cap) { xn_arr_r *a = (xn_arr_r *)rt_gc_new(&RT_TYPE_XN_ARR_R); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_r) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (xn_Result *)malloc(sizeof(xn_Result) * a->cap); if (a->data == NULL) { abort(); } return a; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_r_push(xn_arr_r *a, xn_Result v) { if (a->len == a->cap) { a->cap *= 2; a->data = (xn_Result *)realloc(a->data, sizeof(xn_Result) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_arr_r_get(const xn_arr_r *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_r_set(xn_arr_r *a, int64_t i, xn_Result v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_r_remove(xn_arr_r *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_arr_r_insert(xn_arr_r *a, int64_t i, xn_Result v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (xn_Result *)realloc(a->data, sizeof(xn_Result) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_send_int(xrt_channel *c, int64_t v, xrt_context *ctx) { xn_Result r; int32_t rc = xrt_channel_send(c, (void *)(intptr_t)v, ctx); r.ok = rc == 0; r.i = 0; r.d = 0; r.s = NULL; r.p = NULL; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_recv_int(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; r.i = rc == 0 ? (int64_t)(intptr_t)v : 0; r.d = 0; r.s = NULL; r.p = NULL; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_send_ptr(xrt_channel *c, void *v, xrt_context *ctx) { xn_Result r; int32_t rc = xrt_channel_send(c, v, ctx); r.ok = rc == 0; r.i = 0; r.d = 0; r.s = NULL; r.p = NULL; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_recv_ptr(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; r.i = (int64_t)(intptr_t)v; r.d = 0; r.s = (rt_string *)v; r.p = v; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_send_double(xrt_channel *c, double v, xrt_context *ctx) { uint64_t bits; memcpy(&bits, &v, sizeof(bits)); xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_send(c, (void *)(uintptr_t)bits, ctx); r.ok = rc == 0; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_recv_double(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; if (rc == 0) { uint64_t bits = (uint64_t)(uintptr_t)v; memcpy(&r.d, &bits, sizeof(double)); } r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static const xrt_channel_ops xn_channel_box_ops = { NULL, free };"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_send_int128(xrt_channel *c, __int128 v, xrt_context *ctx) { __int128 *p = (__int128 *)malloc(sizeof(__int128)); if (p == NULL) { abort(); } *p = v; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_send(c, (void *)p, ctx); if (rc != 0) { free(p); } r.ok = rc == 0; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_recv_int128(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; if (rc == 0) { __int128 *p = (__int128 *)v; r.q = *p; free(p); } r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_send_result(xrt_channel *c, xn_Result v, xrt_context *ctx) { xn_Result *p = (xn_Result *)malloc(sizeof(xn_Result)); if (p == NULL) { abort(); } *p = v; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_send(c, (void *)p, ctx); if (rc != 0) { free(p); } r.ok = rc == 0; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_recv_result(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; if (rc == 0) { xn_Result *p = (xn_Result *)v; r.p = (void *)malloc(sizeof(xn_Result)); if (r.p == NULL) { abort(); } *(xn_Result *)r.p = *p; free(p); } r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_send_result_is(xrt_channel *c, xn_Result_Int_String v, xrt_context *ctx) { xn_Result *p = (xn_Result *)malloc(sizeof(xn_Result)); if (p == NULL) { abort(); } memset(p, 0, sizeof(xn_Result)); p->ok = v.ok; p->i = v.value; p->s = v.error; p->err = v.error; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_send(c, (void *)p, ctx); if (rc != 0) { free(p); } r.ok = rc == 0; r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_channel_recv_result_is(xrt_channel *c, xrt_context *ctx) { void *v = NULL; xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_channel_receive(c, &v, ctx); r.ok = rc == 0; if (rc == 0) { xn_Result *p = (xn_Result *)v; xn_Result_Int_String *out = (xn_Result_Int_String *)malloc(sizeof(xn_Result_Int_String)); if (out == NULL) { abort(); } out->ok = p->ok; out->value = p->i; out->error = (rt_string *)p->err; r.p = (void *)out; free(p); } r.err = (rc == 0) ? NULL : (void *)(intptr_t)rc; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_mutex_lock(xrt_mutex *m, xn_closure cl, xrt_with_lock_body body) { xn_Result r; memset(&r, 0, sizeof(r)); int32_t rc = xrt_mutex_with_lock(m, body, &cl, NULL); r.ok = rc == 0; if (rc != 0) { r.err = (void *)(intptr_t)rc; } return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xrt_task *xn_task_spawn(xrt_task_group *g, xn_closure cl, xrt_task_body body) { xn_closure *env = (xn_closure *)malloc(sizeof(xn_closure)); if (env == NULL) { abort(); } *env = cl; xrt_task *t = NULL; xrt_task_group_spawn(g, body, env, &t); return t; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_task_result_map(xrt_task_result *tr) { xn_Result r; memset(&r, 0, sizeof(r)); if (!tr->ok) { r.ok = 0; r.err = (void *)(intptr_t)tr->kind; return r; } r.ok = 1; r.i = (int64_t)(intptr_t)tr->value; r.s = (rt_string *)tr->value; r.p = tr->value; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_task_join(xrt_task *t) { xrt_task_result tr; memset(&tr, 0, sizeof(tr)); int32_t rc = xrt_task_join(t, &tr); if (rc != 0) { xn_Result r; memset(&r, 0, sizeof(r)); r.err = (void *)(intptr_t)rc; return r; } return xn_task_result_map(&tr); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_task_join_deadline(xrt_task *t, int64_t dl) { xrt_task_result tr; memset(&tr, 0, sizeof(tr)); int32_t rc = xrt_task_join_deadline(t, dl, &tr); if (rc != 0) { xn_Result r; memset(&r, 0, sizeof(r)); r.err = (void *)(intptr_t)rc; return r; } return xn_task_result_map(&tr); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Result xn_task_group_close(xrt_task_group *g) { xrt_task_result tr; memset(&tr, 0, sizeof(tr)); int32_t rc = xrt_task_group_close(g, &tr); xn_Result r; memset(&r, 0, sizeof(r)); if (rc != 0) { r.err = (void *)(intptr_t)rc; return r; } if (!tr.ok) { r.err = (void *)(intptr_t)tr.kind; return r; } r.ok = 1; return r; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  xn_Cls_CGen_emitFfiDecls(self);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || (xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_Cls_CGen_isDataEnum(self, n->text)))) {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("typedef struct xn_Cls_"), n->text), rt_string_from_c(" xn_Cls_")), n->text), rt_string_from_c(";")));
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("TopField"))) {
      xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), xn_Cls_CGen_ctype(self, xn_arr_s_get(parts, 0))), rt_string_from_c(" ")), xn_arr_s_get(parts, 1)), rt_string_from_c(";")));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  i = 0;
  while ((i < ((int64_t)self->lambdas->len))) {
    xn_Cls_CGen_emit(self, xn_Cls_CGen_lambdaProto(self, i));
    if ((i < ((int64_t)self->lambdaModes->len))) {
      if (xn_str_eq(xn_arr_s_get(self->lambdaModes, i), rt_string_from_c("lock"))) {
        xn_Cls_CGen_emit(self, xn_Cls_CGen_lockAdapterProto(self, i));
      }
      else {
        if (xn_str_eq(xn_arr_s_get(self->lambdaModes, i), rt_string_from_c("task"))) {
          xn_Cls_CGen_emit(self, xn_Cls_CGen_taskAdapterProto(self, i));
        }
      }
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Func")) && (!xn_hasTypeParams(n)))) {
      xn_Cls_CGen_emit(self, xn_Cls_CGen_funcProto(self, n));
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(p->kind, rt_string_from_c("Protocol"))) {
      int64_t pi = xn_int_wrap(0);
      while ((pi < ((int64_t)p->kids->len))) {
        xn_Cls_AstNode * sig = ((xn_Cls_AstNode *)xn_arr_o_get(p->kids, pi));
        if (xn_str_eq(sig->kind, rt_string_from_c("Sig"))) {
          rt_string * rt = xn_Cls_CGen_protoRet(self, p->text, sig->text);
          xn_arr_o * pps = xn_Cls_CGen_protoParams(self, p->text, sig->text);
          rt_string * fsig = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), xn_Cls_CGen_ctype(self, rt)), rt_string_from_c(" xn_proto_")), p->text), rt_string_from_c("_")), sig->text), rt_string_from_c("(void *xn_obj"));
          int64_t ai = xn_int_wrap(0);
          while ((ai < ((int64_t)pps->len))) {
            xn_arr_s * pp = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(pps, ai))->text, rt_string_from_c(" "));
            if ((((int64_t)pp->len) >= 2)) {
              fsig = xn_concat(xn_concat(xn_concat(xn_concat(fsig, rt_string_from_c(", ")), xn_Cls_CGen_ctype(self, xn_arr_s_get(pp, 0))), rt_string_from_c(" ")), xn_arr_s_get(pp, 1));
            }
            ai = xn_int_wrap((ai + 1));
          }
          fsig = xn_concat(fsig, rt_string_from_c(");"));
          xn_Cls_CGen_emit(self, fsig);
        }
        pi = xn_int_wrap((pi + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  i = 0;
  while (((i < ((int64_t)self->program->kids->len)) && (!xn_Cls_CGen_hasError(self)))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("Enum"))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * it = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j));
        if (xn_str_eq(it->kind, rt_string_from_c("EnumItem"))) {
          if (xn_Cls_CGen_isDataEnum(self, n->text)) {
            xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static xn_Cls_"), n->text), rt_string_from_c(" *xn_enum_")), n->text), rt_string_from_c("_")), it->text), rt_string_from_c(";")));
          }
          else {
            xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static const int64_t xn_enum_"), n->text), rt_string_from_c("_")), it->text), rt_string_from_c(" = ")), xn_str_int(xn_Cls_CGen_enumValue(self, n->text, it->text))), rt_string_from_c(";")));
          }
        }
        j = xn_int_wrap((j + 1));
      }
    }
    if ((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || (xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_Cls_CGen_isDataEnum(self, n->text))) && (!xn_hasTypeParams(n)))) {
      xn_Cls_CGen_genClass(self, n);
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(p->kind, rt_string_from_c("Protocol"))) {
      int64_t si = xn_int_wrap(0);
      while ((si < ((int64_t)p->kids->len))) {
        xn_Cls_AstNode * sig = ((xn_Cls_AstNode *)xn_arr_o_get(p->kids, si));
        if (xn_str_eq(sig->kind, rt_string_from_c("Sig"))) {
          rt_string * rt = xn_Cls_CGen_protoRet(self, p->text, sig->text);
          xn_arr_o * pps = xn_Cls_CGen_protoParams(self, p->text, sig->text);
          rt_string * fsig = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), xn_Cls_CGen_ctype(self, rt)), rt_string_from_c(" xn_proto_")), p->text), rt_string_from_c("_")), sig->text), rt_string_from_c("(void *xn_obj"));
          int64_t pi = xn_int_wrap(0);
          while ((pi < ((int64_t)pps->len))) {
            xn_arr_s * pp = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(pps, pi))->text, rt_string_from_c(" "));
            if ((((int64_t)pp->len) >= 2)) {
              fsig = xn_concat(xn_concat(xn_concat(xn_concat(fsig, rt_string_from_c(", ")), xn_Cls_CGen_ctype(self, xn_arr_s_get(pp, 0))), rt_string_from_c(" ")), xn_arr_s_get(pp, 1));
            }
            pi = xn_int_wrap((pi + 1));
          }
          fsig = xn_concat(fsig, rt_string_from_c(") {"));
          xn_Cls_CGen_emit(self, fsig);
          int64_t ci = xn_int_wrap(0);
          while ((ci < ((int64_t)self->program->kids->len))) {
            xn_Cls_AstNode * c = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, ci));
            if (((xn_str_eq(c->kind, rt_string_from_c("Class")) || xn_str_eq(c->kind, rt_string_from_c("Struct"))) && (!xn_hasTypeParams(c)))) {
              int impl = 0;
              int64_t ck = xn_int_wrap(0);
              while ((ck < ((int64_t)c->kids->len))) {
                if ((xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(c->kids, ck))->kind, rt_string_from_c("Implements")) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(c->kids, ck))->text, p->text))) {
                  impl = 1;
                }
                ck = xn_int_wrap((ck + 1));
              }
              if (impl) {
                rt_string * call = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("return xn_Cls_"), c->text), rt_string_from_c("_")), sig->text), rt_string_from_c("((xn_Cls_")), c->text), rt_string_from_c(" *)xn_obj"));
                int64_t ai = xn_int_wrap(0);
                while ((ai < ((int64_t)pps->len))) {
                  xn_arr_s * pp = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(pps, ai))->text, rt_string_from_c(" "));
                  if ((((int64_t)pp->len) >= 2)) {
                    call = xn_concat(xn_concat(call, rt_string_from_c(", ")), xn_arr_s_get(pp, 1));
                  }
                  ai = xn_int_wrap((ai + 1));
                }
                call = xn_concat(call, rt_string_from_c(");"));
                xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(rt_string_from_c("  if (((rt_header *)xn_obj)->type == &RT_TYPE_XN_"), c->text), rt_string_from_c(") ")), call));
              }
            }
            ci = xn_int_wrap((ci + 1));
          }
          if ((xn_str_eq(p->text, rt_string_from_c("Error")) && xn_str_eq(sig->text, rt_string_from_c("kind")))) {
            xn_Cls_CGen_emit(self, rt_string_from_c("  if (((rt_header *)xn_obj)->type == &RT_TYPE_XN_BUILTIN_ERROR) return ((xn_builtin_error *)xn_obj)->kind;"));
          }
          if ((xn_str_eq(p->text, rt_string_from_c("Error")) && xn_str_eq(sig->text, rt_string_from_c("describe")))) {
            xn_Cls_CGen_emit(self, rt_string_from_c("  if (((rt_header *)xn_obj)->type == &RT_TYPE_XN_BUILTIN_ERROR) return ((xn_builtin_error *)xn_obj)->message;"));
          }
          xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("  rt_fatal(\"protocol dispatch failed: "), p->text), rt_string_from_c(".")), sig->text), rt_string_from_c("\");")));
          rt_string * protocolCType = xn_Cls_CGen_ctype(self, rt);
          if (((xn_str_eq(rt, rt_string_from_c("Unit")) || xn_str_eq(rt, rt_string_from_c("void"))) || xn_str_eq(rt, rt_string_from_c("Void")))) {
            xn_Cls_CGen_emit(self, rt_string_from_c("  return;"));
          }
          else {
            if (xn_str_eq(protocolCType, rt_string_from_c("xn_Result"))) {
              xn_Cls_CGen_emit(self, rt_string_from_c("  return (xn_Result){ .ok = 0, .err = (void *)0 };"));
            }
            else {
              if (xn_str_eq(protocolCType, rt_string_from_c("xn_Result_Int_String"))) {
                xn_Cls_CGen_emit(self, rt_string_from_c("  return (xn_Result_Int_String){ .ok = 0, .value = 0, .error = 0 };"));
              }
              else {
                if (xn_str_eq(protocolCType, rt_string_from_c("xn_closure"))) {
                  xn_Cls_CGen_emit(self, rt_string_from_c("  return (xn_closure){ .env = 0, .fn = 0 };"));
                }
                else {
                  xn_Cls_CGen_emit(self, rt_string_from_c("  return 0;"));
                }
              }
            }
          }
          xn_Cls_CGen_emit(self, rt_string_from_c("}"));
          xn_Cls_CGen_emit(self, rt_string_from_c(""));
        }
        si = xn_int_wrap((si + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("TopField"))) {
      xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), xn_Cls_CGen_ctype(self, xn_arr_s_get(parts, 0))), rt_string_from_c(" ")), xn_arr_s_get(parts, 1)), rt_string_from_c(";")));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  xn_Cls_CGen_emit(self, rt_string_from_c("static void xn_init_globals(void) {"));
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("TopField"))) {
      xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        rt_string * ty = xn_arr_s_get(parts, 0);
        rt_string * name = xn_arr_s_get(parts, 1);
        rt_string * init = rt_string_from_c("0");
        if (xn_str_eq(ty, rt_string_from_c("String"))) {
          init = rt_string_from_c("rt_string_from_c(\"\")");
        }
        if (xn_Cls_CGen_isFunctionType(self, ty)) {
          init = rt_string_from_c("(xn_closure){0, 0}");
        }
        if (xn_Cls_CGen_isArray(self, ty)) {
          init = xn_Cls_CGen_arrayNew(self, ty, 4);
        }
        if ((((int64_t)n->kids->len) > 0)) {
          if ((xn_Cls_CGen_isArray(self, ty) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))->kind, rt_string_from_c("ArrayLit")))) {
            xn_Cls_AstNode * lit = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
            init = xn_Cls_CGen_arrayNew(self, ty, ((int64_t)lit->kids->len));
          }
          else {
            init = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
          }
        }
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("  "), name), rt_string_from_c(" = ")), init), rt_string_from_c(";")));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_Cls_CGen_isDataEnum(self, n->text))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * it = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j));
        if (xn_str_eq(it->kind, rt_string_from_c("EnumItem"))) {
          rt_string * args = rt_string_from_c("");
          int64_t ai = xn_int_wrap(0);
          while ((ai < ((int64_t)it->kids->len))) {
            if ((ai > 0)) {
              args = xn_concat(args, rt_string_from_c(", "));
            }
            args = xn_concat(args, xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(it->kids, ai))));
            ai = xn_int_wrap((ai + 1));
          }
          xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("  xn_enum_"), n->text), rt_string_from_c("_")), it->text), rt_string_from_c(" = xn_Cls_")), n->text), rt_string_from_c("_new(")), args), rt_string_from_c(");")));
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c("}"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
  i = 0;
  while (((i < ((int64_t)self->program->kids->len)) && (!xn_Cls_CGen_hasError(self)))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Func")) && (!xn_hasTypeParams(n)))) {
      xn_Cls_CGen_func(self, n);
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while (((i < ((int64_t)self->lambdas->len)) && (!xn_Cls_CGen_hasError(self)))) {
    xn_Cls_CGen_emitLambdaDef(self, i);
    if ((i < ((int64_t)self->lambdaModes->len))) {
      if (xn_str_eq(xn_arr_s_get(self->lambdaModes, i), rt_string_from_c("lock"))) {
        xn_Cls_CGen_emitLockAdapter(self, i);
      }
      else {
        if (xn_str_eq(xn_arr_s_get(self->lambdaModes, i), rt_string_from_c("task"))) {
          xn_Cls_CGen_emitTaskAdapter(self, i);
        }
      }
    }
    i = xn_int_wrap((i + 1));
  }
  int concretePair = 0;
  int64_t pairIdx = xn_int_wrap(0);
  while ((pairIdx < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * pairNode = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, pairIdx));
    if ((((xn_str_eq(pairNode->kind, rt_string_from_c("Class")) || xn_str_eq(pairNode->kind, rt_string_from_c("Struct"))) && xn_str_eq(pairNode->text, rt_string_from_c("Pair"))) && (!xn_hasTypeParams(pairNode)))) {
      concretePair = 1;
    }
    pairIdx = xn_int_wrap((pairIdx + 1));
  }
  if (concretePair) {
    xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_o *xn_map_s_i_entries(const xn_map_s_i *m) { xn_arr_o *out = xn_arr_o_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_o_push(out, (void *)xn_Cls_Pair_new(m->keys[i], m->vals[i])); } return out; }"));
  }
  int concreteIntPair = 0;
  int64_t intPairIdx = xn_int_wrap(0);
  while ((intPairIdx < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * intPairNode = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, intPairIdx));
    if ((((xn_str_eq(intPairNode->kind, rt_string_from_c("Class")) || xn_str_eq(intPairNode->kind, rt_string_from_c("Struct"))) && xn_str_eq(intPairNode->text, rt_string_from_c("IntPair"))) && (!xn_hasTypeParams(intPairNode)))) {
      concreteIntPair = 1;
    }
    intPairIdx = xn_int_wrap((intPairIdx + 1));
  }
  if (concreteIntPair) {
    xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_o *xn_map_i_i_entries(const xn_map_i_i *m) { xn_arr_o *out = xn_arr_o_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_o_push(out, (void *)xn_Cls_IntPair_new(m->keys[i], m->vals[i])); } return out; }"));
  }
  int64_t gmDef = xn_int_wrap(0);
  while ((gmDef < ((int64_t)self->genericMaps->len))) {
    rt_string * gty = xn_arr_s_get(self->genericMaps, gmDef);
    rt_string * kty = xn_Cls_CGen_mapKey(self, gty);
    rt_string * vty = xn_Cls_CGen_mapValue(self, gty);
    rt_string * kac = xn_Cls_CGen_arrayCName(self, xn_concat(xn_concat(rt_string_from_c("List<"), kty), rt_string_from_c(">")));
    rt_string * vac = xn_Cls_CGen_arrayCName(self, xn_concat(xn_concat(rt_string_from_c("List<"), vty), rt_string_from_c(">")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), kac), rt_string_from_c(" *")), xn_Cls_CGen_genericMapKeysName(self, gty)), rt_string_from_c("(const xn_map_g *m) { ")), kac), rt_string_from_c(" *out = ")), kac), rt_string_from_c("_new(m->len); for (size_t i = 0; i < m->len; i++) { ")), kac), rt_string_from_c("_push(out, ")), xn_Cls_CGen_decodeOf(self, kty, rt_string_from_c("m->keys[i]"))), rt_string_from_c("); } return out; }")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), vac), rt_string_from_c(" *")), xn_Cls_CGen_genericMapValuesName(self, gty)), rt_string_from_c("(const xn_map_g *m) { ")), vac), rt_string_from_c(" *out = ")), vac), rt_string_from_c("_new(m->len); for (size_t i = 0; i < m->len; i++) { ")), vac), rt_string_from_c("_push(out, ")), xn_Cls_CGen_decodeOf(self, vty, rt_string_from_c("m->vals[i]"))), rt_string_from_c("); } return out; }")));
    rt_string * entryCls = xn_Cls_CGen_entryClassName(self, kty, vty);
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static xn_arr_o *"), xn_Cls_CGen_genericMapEntriesName(self, gty)), rt_string_from_c("(const xn_map_g *m) { xn_arr_o *out = xn_arr_o_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_o_push(out, (void *)xn_Cls_")), entryCls), rt_string_from_c("_new(")), xn_Cls_CGen_decodeOf(self, kty, rt_string_from_c("m->keys[i]"))), rt_string_from_c(", ")), xn_Cls_CGen_decodeOf(self, vty, rt_string_from_c("m->vals[i]"))), rt_string_from_c(")); } return out; }")));
    gmDef = xn_int_wrap((gmDef + 1));
  }
  int mainArgs = 0;
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (((xn_str_eq(n->kind, rt_string_from_c("Func")) && xn_str_eq(n->text, rt_string_from_c("main"))) && (((int64_t)xn_Cls_CGen_paramsOf(self, n)->len) > 0))) {
      mainArgs = 1;
    }
    i = xn_int_wrap((i + 1));
  }
  if (mainArgs) {
    xn_Cls_CGen_emit(self, rt_string_from_c("int main(int argc, char **argv) {"));
  }
  else {
    xn_Cls_CGen_emit(self, rt_string_from_c("int main(void) {"));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c("  xrt_runtime_init();"));
  xn_Cls_CGen_emit(self, rt_string_from_c("  xn_init_globals();"));
  if (mainArgs) {
    xn_Cls_CGen_emit(self, rt_string_from_c("  xn_arr_s *args = xn_arr_s_new(argc > 1 ? (size_t)(argc - 1) : 1);"));
    xn_Cls_CGen_emit(self, rt_string_from_c("  for (int ai = 1; ai < argc; ai++) { xn_arr_s_push(args, rt_string_from_c(argv[ai])); }"));
    xn_Cls_CGen_emit(self, rt_string_from_c("  int64_t xn_result = xn_main(args);"));
  }
  else {
    xn_Cls_CGen_emit(self, rt_string_from_c("  int64_t xn_result = xn_main();"));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c("  rt_gc_collect();"));
  xn_Cls_CGen_emit(self, rt_string_from_c("  return (int)xn_result;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("}"));
}

static rt_string * xn_Cls_CGen_text(xn_Cls_CGen *self) {
  return xn_arr_s_join(self->lines, rt_string_from_c("\n"));
}

static xn_arr_s * loadedFiles;
static rt_string * loadBaseDir;
static rt_string * loadRoot;
static int xdkFullSource;
static xn_arr_s * ffiNames;
static xn_arr_s * ffiCNames;
static xn_arr_s * ffiRets;
static xn_arr_s * ffiParamSpecs;
static xn_arr_s * ffiErrParams;
static xn_arr_s * ffiErrRets;

static void xn_init_globals(void) {
  loadedFiles = xn_arr_s_new(0);
  loadBaseDir = rt_string_from_c("");
  loadRoot = rt_string_from_c("");
  xdkFullSource = 0;
  ffiNames = xn_arr_s_new(0);
  ffiCNames = xn_arr_s_new(0);
  ffiRets = xn_arr_s_new(0);
  ffiParamSpecs = xn_arr_s_new(0);
  ffiErrParams = xn_arr_s_new(0);
  ffiErrRets = xn_arr_s_new(0);
}

static int64_t xn_usage(void) {
  xn_print_str(rt_string_from_c("usage: mini --emit-c <entry.x> [-o out.c] | --check <entry.x> | --ast <entry.x> | --sema <entry.x> | --supports <entry.x> | --version"));
  return xn_int_wrap(2);
}

static rt_string * xn_at(rt_string * s, int64_t i) {
  if (((i < 0) || (i >= ((int64_t)s->len)))) {
    return rt_string_from_c("");
  }
  return xn_str_substr(s, i, 1);
}

static int xn_starts(rt_string * s, int64_t i, rt_string * lit) {
  if (((i < 0) || (xn_int_wrap((i + ((int64_t)lit->len))) > ((int64_t)s->len)))) {
    return 0;
  }
  return xn_str_eq(xn_str_substr(s, i, ((int64_t)lit->len)), lit);
}

static int xn_isDigit(rt_string * c) {
  return (((((((((xn_str_eq(c, rt_string_from_c("0")) || xn_str_eq(c, rt_string_from_c("1"))) || xn_str_eq(c, rt_string_from_c("2"))) || xn_str_eq(c, rt_string_from_c("3"))) || xn_str_eq(c, rt_string_from_c("4"))) || xn_str_eq(c, rt_string_from_c("5"))) || xn_str_eq(c, rt_string_from_c("6"))) || xn_str_eq(c, rt_string_from_c("7"))) || xn_str_eq(c, rt_string_from_c("8"))) || xn_str_eq(c, rt_string_from_c("9")));
}

static int xn_isHex(rt_string * c) {
  return ((((((((((((xn_isDigit(c) || xn_str_eq(c, rt_string_from_c("a"))) || xn_str_eq(c, rt_string_from_c("b"))) || xn_str_eq(c, rt_string_from_c("c"))) || xn_str_eq(c, rt_string_from_c("d"))) || xn_str_eq(c, rt_string_from_c("e"))) || xn_str_eq(c, rt_string_from_c("f"))) || xn_str_eq(c, rt_string_from_c("A"))) || xn_str_eq(c, rt_string_from_c("B"))) || xn_str_eq(c, rt_string_from_c("C"))) || xn_str_eq(c, rt_string_from_c("D"))) || xn_str_eq(c, rt_string_from_c("E"))) || xn_str_eq(c, rt_string_from_c("F")));
}

static int xn_isLower(rt_string * c) {
  return (((((((((((((((((((((((((xn_str_eq(c, rt_string_from_c("a")) || xn_str_eq(c, rt_string_from_c("b"))) || xn_str_eq(c, rt_string_from_c("c"))) || xn_str_eq(c, rt_string_from_c("d"))) || xn_str_eq(c, rt_string_from_c("e"))) || xn_str_eq(c, rt_string_from_c("f"))) || xn_str_eq(c, rt_string_from_c("g"))) || xn_str_eq(c, rt_string_from_c("h"))) || xn_str_eq(c, rt_string_from_c("i"))) || xn_str_eq(c, rt_string_from_c("j"))) || xn_str_eq(c, rt_string_from_c("k"))) || xn_str_eq(c, rt_string_from_c("l"))) || xn_str_eq(c, rt_string_from_c("m"))) || xn_str_eq(c, rt_string_from_c("n"))) || xn_str_eq(c, rt_string_from_c("o"))) || xn_str_eq(c, rt_string_from_c("p"))) || xn_str_eq(c, rt_string_from_c("q"))) || xn_str_eq(c, rt_string_from_c("r"))) || xn_str_eq(c, rt_string_from_c("s"))) || xn_str_eq(c, rt_string_from_c("t"))) || xn_str_eq(c, rt_string_from_c("u"))) || xn_str_eq(c, rt_string_from_c("v"))) || xn_str_eq(c, rt_string_from_c("w"))) || xn_str_eq(c, rt_string_from_c("x"))) || xn_str_eq(c, rt_string_from_c("y"))) || xn_str_eq(c, rt_string_from_c("z")));
}

static int xn_isUpper(rt_string * c) {
  return (((((((((((((((((((((((((xn_str_eq(c, rt_string_from_c("A")) || xn_str_eq(c, rt_string_from_c("B"))) || xn_str_eq(c, rt_string_from_c("C"))) || xn_str_eq(c, rt_string_from_c("D"))) || xn_str_eq(c, rt_string_from_c("E"))) || xn_str_eq(c, rt_string_from_c("F"))) || xn_str_eq(c, rt_string_from_c("G"))) || xn_str_eq(c, rt_string_from_c("H"))) || xn_str_eq(c, rt_string_from_c("I"))) || xn_str_eq(c, rt_string_from_c("J"))) || xn_str_eq(c, rt_string_from_c("K"))) || xn_str_eq(c, rt_string_from_c("L"))) || xn_str_eq(c, rt_string_from_c("M"))) || xn_str_eq(c, rt_string_from_c("N"))) || xn_str_eq(c, rt_string_from_c("O"))) || xn_str_eq(c, rt_string_from_c("P"))) || xn_str_eq(c, rt_string_from_c("Q"))) || xn_str_eq(c, rt_string_from_c("R"))) || xn_str_eq(c, rt_string_from_c("S"))) || xn_str_eq(c, rt_string_from_c("T"))) || xn_str_eq(c, rt_string_from_c("U"))) || xn_str_eq(c, rt_string_from_c("V"))) || xn_str_eq(c, rt_string_from_c("W"))) || xn_str_eq(c, rt_string_from_c("X"))) || xn_str_eq(c, rt_string_from_c("Y"))) || xn_str_eq(c, rt_string_from_c("Z")));
}

static int xn_isIdentStart(rt_string * c) {
  return ((xn_isLower(c) || xn_isUpper(c)) || xn_str_eq(c, rt_string_from_c("_")));
}

static int xn_isIdentPart(rt_string * c) {
  return (xn_isIdentStart(c) || xn_isDigit(c));
}

static int xn_isSpace(rt_string * c) {
  return (((xn_str_eq(c, rt_string_from_c(" ")) || xn_str_eq(c, rt_string_from_c("\t"))) || xn_str_eq(c, rt_string_from_c("\r"))) || xn_str_eq(c, rt_string_from_c("\n")));
}

static int xn_isKeyword(rt_string * s) {
  return (((((((((((((((((((((((((((((((((((((((((((xn_str_eq(s, rt_string_from_c("package")) || xn_str_eq(s, rt_string_from_c("import"))) || xn_str_eq(s, rt_string_from_c("static"))) || xn_str_eq(s, rt_string_from_c("final"))) || xn_str_eq(s, rt_string_from_c("public"))) || xn_str_eq(s, rt_string_from_c("private"))) || xn_str_eq(s, rt_string_from_c("protected"))) || xn_str_eq(s, rt_string_from_c("class"))) || xn_str_eq(s, rt_string_from_c("struct"))) || xn_str_eq(s, rt_string_from_c("enum"))) || xn_str_eq(s, rt_string_from_c("protocol"))) || xn_str_eq(s, rt_string_from_c("interface"))) || xn_str_eq(s, rt_string_from_c("extends"))) || xn_str_eq(s, rt_string_from_c("implements"))) || xn_str_eq(s, rt_string_from_c("new"))) || xn_str_eq(s, rt_string_from_c("self"))) || xn_str_eq(s, rt_string_from_c("super"))) || xn_str_eq(s, rt_string_from_c("this"))) || xn_str_eq(s, rt_string_from_c("return"))) || xn_str_eq(s, rt_string_from_c("if"))) || xn_str_eq(s, rt_string_from_c("else"))) || xn_str_eq(s, rt_string_from_c("while"))) || xn_str_eq(s, rt_string_from_c("do"))) || xn_str_eq(s, rt_string_from_c("for"))) || xn_str_eq(s, rt_string_from_c("in"))) || xn_str_eq(s, rt_string_from_c("switch"))) || xn_str_eq(s, rt_string_from_c("case"))) || xn_str_eq(s, rt_string_from_c("default"))) || xn_str_eq(s, rt_string_from_c("break"))) || xn_str_eq(s, rt_string_from_c("continue"))) || xn_str_eq(s, rt_string_from_c("goto"))) || xn_str_eq(s, rt_string_from_c("try"))) || xn_str_eq(s, rt_string_from_c("catch"))) || xn_str_eq(s, rt_string_from_c("throw"))) || xn_str_eq(s, rt_string_from_c("defer"))) || xn_str_eq(s, rt_string_from_c("errdefer"))) || xn_str_eq(s, rt_string_from_c("true"))) || xn_str_eq(s, rt_string_from_c("false"))) || xn_str_eq(s, rt_string_from_c("null"))) || xn_str_eq(s, rt_string_from_c("is"))) || xn_str_eq(s, rt_string_from_c("as"))) || xn_str_eq(s, rt_string_from_c("void"))) || xn_str_eq(s, rt_string_from_c("factory"))) || xn_str_eq(s, rt_string_from_c("deinit")));
}

static xn_arr_o * xn_lex(rt_string * src) {
  xn_arr_o *tokens = xn_arr_o_new(0);
  int64_t i = xn_int_wrap(0);
  int64_t line = xn_int_wrap(1);
  int64_t col = xn_int_wrap(1);
  while ((i < ((int64_t)src->len))) {
    rt_string * c = xn_at(src, i);
    rt_string * next = xn_at(src, xn_int_wrap((i + 1)));
    if (xn_str_eq(c, rt_string_from_c("\n"))) {
      i = xn_int_wrap((i + 1));
      line = xn_int_wrap((line + 1));
      col = 1;
      continue;
    }
    if (xn_isSpace(c)) {
      i = xn_int_wrap((i + 1));
      col = xn_int_wrap((col + 1));
      continue;
    }
    if ((xn_str_eq(c, rt_string_from_c("/")) && xn_str_eq(next, rt_string_from_c("/")))) {
      i = xn_int_wrap((i + 2));
      col = xn_int_wrap((col + 2));
      while (((i < ((int64_t)src->len)) && (!xn_str_eq(xn_at(src, i), rt_string_from_c("\n"))))) {
        i = xn_int_wrap((i + 1));
        col = xn_int_wrap((col + 1));
      }
      continue;
    }
    if ((xn_str_eq(c, rt_string_from_c("/")) && xn_str_eq(next, rt_string_from_c("*")))) {
      i = xn_int_wrap((i + 2));
      col = xn_int_wrap((col + 2));
      while (((i < ((int64_t)src->len)) && (!(xn_str_eq(xn_at(src, i), rt_string_from_c("*")) && xn_str_eq(xn_at(src, xn_int_wrap((i + 1))), rt_string_from_c("/")))))) {
        if (xn_str_eq(xn_at(src, i), rt_string_from_c("\n"))) {
          line = xn_int_wrap((line + 1));
          col = 1;
        }
        else {
          col = xn_int_wrap((col + 1));
        }
        i = xn_int_wrap((i + 1));
      }
      if ((i < ((int64_t)src->len))) {
        i = xn_int_wrap((i + 2));
        col = xn_int_wrap((col + 2));
      }
      continue;
    }
    int64_t start = xn_int_wrap(i);
    int64_t startLine = xn_int_wrap(line);
    int64_t startCol = xn_int_wrap(col);
    if (xn_isIdentStart(c)) {
      i = xn_int_wrap((i + 1));
      col = xn_int_wrap((col + 1));
      while (((i < ((int64_t)src->len)) && xn_isIdentPart(xn_at(src, i)))) {
        i = xn_int_wrap((i + 1));
        col = xn_int_wrap((col + 1));
      }
      rt_string * ident = xn_str_substr(src, start, xn_int_wrap((i - start)));
      rt_string * kind = rt_string_from_c("ident");
      if (xn_isKeyword(ident)) {
        kind = rt_string_from_c("kw");
      }
      xn_arr_o_push(tokens, xn_Cls_Token_new(kind, ident, startLine, startCol));
      continue;
    }
    if (xn_isDigit(c)) {
      if (((xn_str_eq(c, rt_string_from_c("0")) && (xn_int_wrap((i + 1)) < ((int64_t)src->len))) && (xn_str_eq(xn_at(src, xn_int_wrap((i + 1))), rt_string_from_c("x")) || xn_str_eq(xn_at(src, xn_int_wrap((i + 1))), rt_string_from_c("X"))))) {
        i = xn_int_wrap((i + 2));
        col = xn_int_wrap((col + 2));
        while (((i < ((int64_t)src->len)) && xn_isHex(xn_at(src, i)))) {
          i = xn_int_wrap((i + 1));
          col = xn_int_wrap((col + 1));
        }
        xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("int"), xn_str_substr(src, start, xn_int_wrap((i - start))), startLine, startCol));
        continue;
      }
      i = xn_int_wrap((i + 1));
      col = xn_int_wrap((col + 1));
      while (((i < ((int64_t)src->len)) && xn_isDigit(xn_at(src, i)))) {
        i = xn_int_wrap((i + 1));
        col = xn_int_wrap((col + 1));
      }
      int isDouble = 0;
      if (((((i < ((int64_t)src->len)) && xn_str_eq(xn_at(src, i), rt_string_from_c("."))) && (xn_int_wrap((i + 1)) < ((int64_t)src->len))) && xn_isDigit(xn_at(src, xn_int_wrap((i + 1)))))) {
        isDouble = 1;
        i = xn_int_wrap((i + 1));
        col = xn_int_wrap((col + 1));
        while (((i < ((int64_t)src->len)) && xn_isDigit(xn_at(src, i)))) {
          i = xn_int_wrap((i + 1));
          col = xn_int_wrap((col + 1));
        }
      }
      if (isDouble) {
        xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("double"), xn_str_substr(src, start, xn_int_wrap((i - start))), startLine, startCol));
      }
      else {
        xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("int"), xn_str_substr(src, start, xn_int_wrap((i - start))), startLine, startCol));
      }
      continue;
    }
    int interp = 0;
    if ((xn_str_eq(c, rt_string_from_c("$")) && xn_str_eq(next, rt_string_from_c("\"")))) {
      interp = 1;
      i = xn_int_wrap((i + 1));
      col = xn_int_wrap((col + 1));
      c = rt_string_from_c("\"");
      start = i;
    }
    if (xn_str_eq(c, rt_string_from_c("\""))) {
      i = xn_int_wrap((i + 1));
      col = xn_int_wrap((col + 1));
      int closed = 0;
      while ((i < ((int64_t)src->len))) {
        rt_string * d = xn_at(src, i);
        if (xn_str_eq(d, rt_string_from_c("\\"))) {
          i = xn_int_wrap((i + 2));
          col = xn_int_wrap((col + 2));
          continue;
        }
        if (xn_str_eq(d, rt_string_from_c("\""))) {
          i = xn_int_wrap((i + 1));
          col = xn_int_wrap((col + 1));
          closed = 1;
          break;
        }
        if (xn_str_eq(d, rt_string_from_c("\n"))) {
          line = xn_int_wrap((line + 1));
          col = 1;
        }
        else {
          col = xn_int_wrap((col + 1));
        }
        i = xn_int_wrap((i + 1));
      }
      if ((!closed)) {
        xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("error"), rt_string_from_c("unterminated string"), startLine, startCol));
        return tokens;
      }
      if (interp) {
        xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("interp"), xn_str_substr(src, start, xn_int_wrap((i - start))), startLine, startCol));
      }
      else {
        xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("string"), xn_str_substr(src, start, xn_int_wrap((i - start))), startLine, startCol));
      }
      continue;
    }
    if (xn_str_eq(c, rt_string_from_c("'"))) {
      i = xn_int_wrap((i + 1));
      col = xn_int_wrap((col + 1));
      int closed = 0;
      while ((i < ((int64_t)src->len))) {
        rt_string * d = xn_at(src, i);
        if (xn_str_eq(d, rt_string_from_c("\\"))) {
          i = xn_int_wrap((i + 2));
          col = xn_int_wrap((col + 2));
          continue;
        }
        if (xn_str_eq(d, rt_string_from_c("'"))) {
          i = xn_int_wrap((i + 1));
          col = xn_int_wrap((col + 1));
          closed = 1;
          break;
        }
        if (xn_str_eq(d, rt_string_from_c("\n"))) {
          line = xn_int_wrap((line + 1));
          col = 1;
        }
        else {
          col = xn_int_wrap((col + 1));
        }
        i = xn_int_wrap((i + 1));
      }
      if ((!closed)) {
        xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("error"), rt_string_from_c("unterminated char"), startLine, startCol));
        return tokens;
      }
      xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("char"), xn_str_substr(src, start, xn_int_wrap((i - start))), startLine, startCol));
      continue;
    }
    rt_string * op = c;
    if (((((((((((((((((xn_starts(src, i, rt_string_from_c("==")) || xn_starts(src, i, rt_string_from_c("!="))) || xn_starts(src, i, rt_string_from_c("<="))) || xn_starts(src, i, rt_string_from_c(">="))) || xn_starts(src, i, rt_string_from_c("<<"))) || xn_starts(src, i, rt_string_from_c("&&"))) || xn_starts(src, i, rt_string_from_c("||"))) || xn_starts(src, i, rt_string_from_c("->"))) || xn_starts(src, i, rt_string_from_c("=>"))) || xn_starts(src, i, rt_string_from_c("::"))) || xn_starts(src, i, rt_string_from_c(".."))) || xn_starts(src, i, rt_string_from_c("+="))) || xn_starts(src, i, rt_string_from_c("-="))) || xn_starts(src, i, rt_string_from_c("*="))) || xn_starts(src, i, rt_string_from_c("/="))) || xn_starts(src, i, rt_string_from_c("++"))) || xn_starts(src, i, rt_string_from_c("--")))) {
      op = xn_str_substr(src, i, 2);
      i = xn_int_wrap((i + 2));
      col = xn_int_wrap((col + 2));
    }
    else {
      if ((((((((((((((((((((((((xn_str_eq(c, rt_string_from_c("(")) || xn_str_eq(c, rt_string_from_c(")"))) || xn_str_eq(c, rt_string_from_c("{"))) || xn_str_eq(c, rt_string_from_c("}"))) || xn_str_eq(c, rt_string_from_c("["))) || xn_str_eq(c, rt_string_from_c("]"))) || xn_str_eq(c, rt_string_from_c(","))) || xn_str_eq(c, rt_string_from_c(";"))) || xn_str_eq(c, rt_string_from_c(":"))) || xn_str_eq(c, rt_string_from_c("."))) || xn_str_eq(c, rt_string_from_c("+"))) || xn_str_eq(c, rt_string_from_c("-"))) || xn_str_eq(c, rt_string_from_c("*"))) || xn_str_eq(c, rt_string_from_c("/"))) || xn_str_eq(c, rt_string_from_c("%"))) || xn_str_eq(c, rt_string_from_c("="))) || xn_str_eq(c, rt_string_from_c("<"))) || xn_str_eq(c, rt_string_from_c(">"))) || xn_str_eq(c, rt_string_from_c("!"))) || xn_str_eq(c, rt_string_from_c("&"))) || xn_str_eq(c, rt_string_from_c("|"))) || xn_str_eq(c, rt_string_from_c("^"))) || xn_str_eq(c, rt_string_from_c("?"))) || xn_str_eq(c, rt_string_from_c("@")))) {
        i = xn_int_wrap((i + 1));
        col = xn_int_wrap((col + 1));
      }
      else {
        xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("error"), xn_concat(rt_string_from_c("unexpected character: "), c), startLine, startCol));
        return tokens;
      }
    }
    xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("punct"), op, startLine, startCol));
  }
  xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("eof"), rt_string_from_c(""), line, col));
  return tokens;
}

static int xn_hasTypeParams(xn_Cls_AstNode * fn) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fn->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i))->kind, rt_string_from_c("TypeParams"))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static xn_arr_s * xn_splitTop(rt_string * s) {
  xn_arr_s *res = xn_arr_s_new(0);
  rt_string * cur = rt_string_from_c("");
  int64_t depth = xn_int_wrap(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)s->len))) {
    rt_string * c = xn_str_substr(s, i, 1);
    if ((((xn_str_eq(c, rt_string_from_c("<")) || xn_str_eq(c, rt_string_from_c("("))) || xn_str_eq(c, rt_string_from_c("["))) || xn_str_eq(c, rt_string_from_c("{")))) {
      depth = xn_int_wrap((depth + 1));
    }
    else {
      if ((((xn_str_eq(c, rt_string_from_c(">")) || xn_str_eq(c, rt_string_from_c(")"))) || xn_str_eq(c, rt_string_from_c("]"))) || xn_str_eq(c, rt_string_from_c("}")))) {
        depth = xn_int_wrap((depth - 1));
      }
    }
    if ((xn_str_eq(c, rt_string_from_c(",")) && (depth == 0))) {
      xn_arr_s_push(res, cur);
      cur = rt_string_from_c("");
    }
    else {
      cur = xn_concat(cur, c);
    }
    i = xn_int_wrap((i + 1));
  }
  if ((!xn_str_eq(cur, rt_string_from_c("")))) {
    xn_arr_s_push(res, cur);
  }
  return res;
}

static int64_t xn_dumpTokens(xn_arr_o * ts, rt_string * path) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ts->len))) {
    xn_Cls_Token * t = ((xn_Cls_Token *)xn_arr_o_get(ts, i));
    if (xn_str_eq(t->kind, rt_string_from_c("error"))) {
      xn_print_str(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(path, rt_string_from_c(":")), xn_str_int(t->line)), rt_string_from_c(":")), xn_str_int(t->col)), rt_string_from_c(": ")), t->text));
      return xn_int_wrap(1);
    }
    xn_print_str(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(t->kind, rt_string_from_c("\t")), t->text), rt_string_from_c("\t")), xn_str_int(t->line)), rt_string_from_c(":")), xn_str_int(t->col)));
    i = xn_int_wrap((i + 1));
  }
  return xn_int_wrap(0);
}

static int64_t xn_ffiIndex(rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ffiNames->len))) {
    if (xn_str_eq(xn_arr_s_get(ffiNames, i), name)) {
      return xn_int_wrap(i);
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_int_wrap(xn_int_wrap(-(1)));
}

static rt_string * xn_ffiRet(rt_string * name) {
  int64_t i = xn_int_wrap(xn_ffiIndex(name));
  if ((i >= 0)) {
    return xn_arr_s_get(ffiRets, i);
  }
  return rt_string_from_c("Any");
}

static rt_string * xn_ffiCName(rt_string * name) {
  int64_t i = xn_int_wrap(xn_ffiIndex(name));
  if ((i >= 0)) {
    return xn_arr_s_get(ffiCNames, i);
  }
  return name;
}

static void xn_loadProject(rt_string * path) {
  if (xn_str_eq(path, rt_string_from_c(""))) {
    return;
  }
  rt_string * src = rt_string_from_c(mini_read_file(path->bytes, path->len));
  if ((((int64_t)src->len) == 0)) {
    return;
  }
  xn_arr_s * lines = xn_str_split(src, rt_string_from_c("\n"));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)lines->len))) {
    rt_string * line = xn_arr_s_get(lines, i);
    if (((((int64_t)line->len) > 2) && xn_str_eq(xn_str_substr(line, 0, 2), rt_string_from_c("E|")))) {
      xn_arr_s * f = xn_str_split(line, rt_string_from_c("|"));
      if (((((int64_t)f->len) >= 6) && (xn_ffiIndex(xn_arr_s_get(f, 2)) < 0))) {
        xn_arr_s_push(ffiNames, xn_arr_s_get(f, 2));
        xn_arr_s_push(ffiCNames, xn_arr_s_get(f, 3));
        xn_arr_s_push(ffiRets, xn_arr_s_get(f, 5));
        if ((((int64_t)f->len) >= 10)) {
          xn_arr_s_push(ffiParamSpecs, xn_arr_s_get(f, 9));
        }
        else {
          xn_arr_s_push(ffiParamSpecs, rt_string_from_c(""));
        }
        if ((((int64_t)f->len) >= 8)) {
          xn_arr_s_push(ffiErrParams, xn_arr_s_get(f, 6));
          xn_arr_s_push(ffiErrRets, xn_arr_s_get(f, 7));
        }
        else {
          xn_arr_s_push(ffiErrParams, rt_string_from_c(""));
          xn_arr_s_push(ffiErrRets, rt_string_from_c(""));
        }
      }
    }
    i = xn_int_wrap((i + 1));
  }
}

static int64_t xn_lastDot(rt_string * s) {
  int64_t i = xn_int_wrap(0);
  int64_t found = xn_int_wrap(xn_int_wrap(-(1)));
  while ((i < ((int64_t)s->len))) {
    if (xn_str_eq(xn_str_substr(s, i, 1), rt_string_from_c("."))) {
      found = i;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_int_wrap(found);
}

static rt_string * xn_localImportFile(rt_string * pkg) {
  rt_string * rel = xn_concat(xn_str_replace(pkg, rt_string_from_c("."), rt_string_from_c("/")), rt_string_from_c(".x"));
  rt_string * path = xn_concat(xn_concat(loadBaseDir, rt_string_from_c("/")), rel);
  if ((((int64_t)rt_string_from_c(mini_read_file(path->bytes, path->len))->len) > 0)) {
    return path;
  }
  return rt_string_from_c("");
}

static rt_string * xn_xdkFile(rt_string * pkg) {
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.errors")) || xn_str_startswith(pkg, rt_string_from_c("xdk.errors.")))) {
    return rt_string_from_c("core/errors/Errors.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.meta")) || xn_str_startswith(pkg, rt_string_from_c("xdk.meta.")))) {
    return rt_string_from_c("core/meta/Meta.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.runtime")) || xn_str_startswith(pkg, rt_string_from_c("xdk.runtime.")))) {
    return rt_string_from_c("core/runtime/Runtime.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.math")) || xn_str_startswith(pkg, rt_string_from_c("xdk.math.")))) {
    return rt_string_from_c("core/math/Math.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.collections")) || xn_str_startswith(pkg, rt_string_from_c("xdk.collections.")))) {
    return rt_string_from_c("core/collections/Collections.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.bytes")) || xn_str_startswith(pkg, rt_string_from_c("xdk.bytes.")))) {
    return rt_string_from_c("core/bytes/Bytes.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.io")) || xn_str_startswith(pkg, rt_string_from_c("xdk.io.")))) {
    return rt_string_from_c("io/IO.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.fs")) || xn_str_startswith(pkg, rt_string_from_c("xdk.fs.")))) {
    return rt_string_from_c("fs/FS.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.sync")) || xn_str_startswith(pkg, rt_string_from_c("xdk.sync.")))) {
    return rt_string_from_c("concurrent/sync/Sync.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.tasks")) || xn_str_startswith(pkg, rt_string_from_c("xdk.tasks.")))) {
    return rt_string_from_c("concurrent/tasks/Tasks.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.log")) || xn_str_startswith(pkg, rt_string_from_c("xdk.log.")))) {
    return rt_string_from_c("log/Log.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.config")) || xn_str_startswith(pkg, rt_string_from_c("xdk.config.")))) {
    return rt_string_from_c("config/Config.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.cli")) || xn_str_startswith(pkg, rt_string_from_c("xdk.cli.")))) {
    return rt_string_from_c("cli/Cli.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.time")) || xn_str_startswith(pkg, rt_string_from_c("xdk.time.")))) {
    return rt_string_from_c("core/time/Time.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.text")) || xn_str_startswith(pkg, rt_string_from_c("xdk.text.")))) {
    return rt_string_from_c("text/full/Text.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.sys")) || xn_str_startswith(pkg, rt_string_from_c("xdk.sys.")))) {
    if (xdkFullSource) {
      return rt_string_from_c("io/system/Sys.x");
    }
    return rt_string_from_c("io/base/Sys.x");
  }
  return rt_string_from_c("");
}

static int xn_endsWithX(rt_string * s) {
  return ((((int64_t)s->len) >= 2) && xn_str_eq(xn_str_substr(s, xn_int_wrap((((int64_t)s->len) - 2)), 2), rt_string_from_c(".x")));
}

static rt_string * xn_dirName(rt_string * path) {
  int64_t i = xn_int_wrap(xn_int_wrap((((int64_t)path->len) - 1)));
  while ((i >= 0)) {
    if (xn_str_eq(xn_str_substr(path, i, 1), rt_string_from_c("/"))) {
      return xn_str_substr(path, 0, i);
    }
    i = xn_int_wrap((i - 1));
  }
  return rt_string_from_c(".");
}

static int xn_loaded(rt_string * path) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)loadedFiles->len))) {
    if (xn_str_eq(xn_arr_s_get(loadedFiles, i), path)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_mergeDecls(xn_Cls_AstNode * program, xn_Cls_AstNode * parsed) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)parsed->kids->len))) {
    xn_Cls_AstNode * d = ((xn_Cls_AstNode *)xn_arr_o_get(parsed->kids, i));
    if (((!xn_str_eq(d->kind, rt_string_from_c("Package"))) && (!xn_str_eq(d->kind, rt_string_from_c("Import"))))) {
      xn_Cls_AstNode_add(program, d);
    }
    i = xn_int_wrap((i + 1));
  }
}

static void xn_loadUnit(rt_string * path, xn_Cls_AstNode * program) {
  if (xn_loaded(path)) {
    return;
  }
  xn_arr_s_push(loadedFiles, path);
  rt_string * isrc = rt_string_from_c(mini_read_file(path->bytes, path->len));
  if ((((int64_t)isrc->len) == 0)) {
    return;
  }
  xn_Cls_Parser * ip = xn_Cls_Parser_new(xn_lex(isrc));
  xn_Cls_AstNode * iprogram = xn_Cls_Parser_parse(ip);
  if (xn_Cls_Parser_hasError(ip)) {
    return;
  }
  int64_t ii = xn_int_wrap(0);
  while ((ii < ((int64_t)iprogram->kids->len))) {
    xn_Cls_AstNode * idep = ((xn_Cls_AstNode *)xn_arr_o_get(iprogram->kids, ii));
    if (xn_str_eq(idep->kind, rt_string_from_c("Import"))) {
      rt_string * drel = xn_xdkFile(idep->text);
      if ((!xn_str_eq(drel, rt_string_from_c("")))) {
        xn_loadUnit(xn_concat(xn_concat(loadRoot, rt_string_from_c("/")), drel), program);
      }
      else {
        rt_string * dlocal = xn_localImportFile(idep->text);
        if ((!xn_str_eq(dlocal, rt_string_from_c("")))) {
          xn_loadUnit(dlocal, program);
        }
      }
    }
    ii = xn_int_wrap((ii + 1));
  }
  xn_mergeDecls(program, iprogram);
  rt_string * dir = xn_dirName(path);
  rt_string * names = rt_string_from_c(mini_list_x(dir->bytes, dir->len));
  xn_arr_s * files = xn_str_split(names, rt_string_from_c("\n"));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)files->len))) {
    rt_string * name = xn_arr_s_get(files, i);
    if (((!xn_str_eq(name, rt_string_from_c(""))) && xn_endsWithX(name))) {
      rt_string * p2 = xn_concat(xn_concat(dir, rt_string_from_c("/")), name);
      if (((!xn_loaded(p2)) && (!xn_str_eq(p2, path)))) {
        xn_loadUnit(p2, program);
      }
    }
    i = xn_int_wrap((i + 1));
  }
}

static void xn_loadSiblings(rt_string * path, xn_Cls_AstNode * program) {
  rt_string * dir = xn_dirName(path);
  rt_string * names = rt_string_from_c(mini_list_x(dir->bytes, dir->len));
  xn_arr_s * files = xn_str_split(names, rt_string_from_c("\n"));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)files->len))) {
    rt_string * name = xn_arr_s_get(files, i);
    if (((!xn_str_eq(name, rt_string_from_c(""))) && xn_endsWithX(name))) {
      rt_string * p2 = xn_concat(xn_concat(dir, rt_string_from_c("/")), name);
      if (((!xn_str_eq(p2, path)) && (!xn_loaded(p2)))) {
        xn_loadUnit(p2, program);
      }
    }
    i = xn_int_wrap((i + 1));
  }
}

static xn_Cls_AstNode * xn_loadProgram(rt_string * entry, rt_string * root) {
  rt_string * src = rt_string_from_c(mini_read_file(entry->bytes, entry->len));
  if ((((int64_t)src->len) == 0)) {
    xn_print_str(rt_string_from_c("mini: cannot read input or input is empty"));
    return xn_Cls_AstNode_new(rt_string_from_c("Program"), rt_string_from_c(""), 1, 1);
  }
  xn_Cls_Parser * p = xn_Cls_Parser_new(xn_lex(src));
  xn_Cls_AstNode * program = xn_Cls_Parser_parse(p);
  if (xn_Cls_Parser_hasError(p)) {
    xn_print_str(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(entry, rt_string_from_c(":")), xn_str_int(p->errorLine)), rt_string_from_c(":")), xn_str_int(p->errorCol)), rt_string_from_c(": ")), p->error));
    return program;
  }
  xn_arr_s_push(loadedFiles, entry);
  loadRoot = root;
  loadBaseDir = xn_dirName(entry);
  if ((xn_str_indexof(entry, rt_string_from_c("/xdk/")) >= 0)) {
    xn_loadSiblings(entry, program);
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)program->kids->len))) {
    xn_Cls_AstNode * imp = ((xn_Cls_AstNode *)xn_arr_o_get(program->kids, i));
    if (xn_str_eq(imp->kind, rt_string_from_c("Import"))) {
      rt_string * rel = xn_xdkFile(imp->text);
      rt_string * path = rt_string_from_c("");
      if ((!xn_str_eq(rel, rt_string_from_c("")))) {
        path = xn_concat(xn_concat(root, rt_string_from_c("/")), rel);
      }
      else {
        path = xn_localImportFile(imp->text);
        if (xn_str_eq(path, rt_string_from_c(""))) {
          xn_print_str(xn_concat(rt_string_from_c("mini: unsupported import: "), imp->text));
          return program;
        }
      }
      if ((xdkFullSource && (xn_str_eq(imp->text, rt_string_from_c("xdk.sys")) || xn_str_startswith(imp->text, rt_string_from_c("xdk.sys."))))) {
        xn_loadUnit(xn_concat(root, rt_string_from_c("/io/resource/Resource.x")), program);
      }
      if (xn_loaded(path)) {
        i = xn_int_wrap((i + 1));
        continue;
      }
      xn_loadUnit(path, program);
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_Mono * mono = xn_Cls_Mono_new(program);
  return xn_Cls_Mono_run(mono);
}

static rt_string * xn_argAfter(xn_arr_s * args, rt_string * flag) {
  int64_t i = xn_int_wrap(0);
  while ((xn_int_wrap((i + 1)) < ((int64_t)args->len))) {
    if (xn_str_eq(xn_arr_s_get(args, i), flag)) {
      return xn_arr_s_get(args, xn_int_wrap((i + 1)));
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("");
}

static int xn_hasArg(xn_arr_s * args, rt_string * flag) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)args->len))) {
    if (xn_str_eq(xn_arr_s_get(args, i), flag)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int64_t xn_main(xn_arr_s * args) {
  if ((((int64_t)args->len) == 0)) {
    return xn_int_wrap(xn_usage());
  }
  rt_string * cmd = xn_arr_s_get(args, 0);
  rt_string * xdkRoot = xn_argAfter(args, rt_string_from_c("--xdk-root"));
  if (xn_str_eq(xdkRoot, rt_string_from_c(""))) {
    xdkRoot = rt_string_from_c("src/xdk");
  }
  xn_loadProject(xn_argAfter(args, rt_string_from_c("--project-file")));
  xdkFullSource = xn_hasArg(args, rt_string_from_c("--xdk-full"));
  if (xn_str_eq(cmd, rt_string_from_c("--version"))) {
    xn_print_str(rt_string_from_c("mini 0.3.0"));
    return xn_int_wrap(0);
  }
  if (xn_str_eq(cmd, rt_string_from_c("--supports"))) {
    if ((((int64_t)args->len) < 2)) {
      return xn_int_wrap(3);
    }
    xn_Cls_AstNode * program = xn_loadProgram(xn_arr_s_get(args, 1), xdkRoot);
    if ((((int64_t)program->kids->len) == 0)) {
      return xn_int_wrap(3);
    }
    xn_Cls_Checker * c = xn_Cls_Checker_new(xn_arr_s_get(args, 1), program);
    xn_Cls_Checker_check(c);
    if (xn_Cls_Checker_hasError(c)) {
      return xn_int_wrap(3);
    }
    return xn_int_wrap(0);
  }
  if (xn_str_eq(cmd, rt_string_from_c("--check"))) {
    if ((((int64_t)args->len) < 2)) {
      return xn_int_wrap(xn_usage());
    }
    rt_string * src = rt_string_from_c(mini_read_file(xn_arr_s_get(args, 1)->bytes, xn_arr_s_get(args, 1)->len));
    if ((((int64_t)src->len) == 0)) {
      xn_print_str(rt_string_from_c("mini: cannot read input or input is empty"));
      return xn_int_wrap(1);
    }
    return xn_int_wrap(xn_dumpTokens(xn_lex(src), xn_arr_s_get(args, 1)));
  }
  if (xn_str_eq(cmd, rt_string_from_c("--ast"))) {
    if ((((int64_t)args->len) < 2)) {
      return xn_int_wrap(xn_usage());
    }
    xn_Cls_AstNode * program = xn_loadProgram(xn_arr_s_get(args, 1), xdkRoot);
    if ((((int64_t)program->kids->len) == 0)) {
      return xn_int_wrap(1);
    }
    xn_Cls_AstNode_dump(program, 0);
    return xn_int_wrap(0);
  }
  if (xn_str_eq(cmd, rt_string_from_c("--sema"))) {
    if ((((int64_t)args->len) < 2)) {
      return xn_int_wrap(xn_usage());
    }
    xn_Cls_AstNode * program = xn_loadProgram(xn_arr_s_get(args, 1), xdkRoot);
    if ((((int64_t)program->kids->len) == 0)) {
      return xn_int_wrap(1);
    }
    xn_Cls_Checker * c = xn_Cls_Checker_new(xn_arr_s_get(args, 1), program);
    xn_Cls_Checker_check(c);
    if (xn_Cls_Checker_hasError(c)) {
      xn_print_str(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_arr_s_get(args, 1), rt_string_from_c(":")), xn_str_int(c->errorLine)), rt_string_from_c(":")), xn_str_int(c->errorCol)), rt_string_from_c(": [")), c->errorCode), rt_string_from_c("] ")), c->error));
      return xn_int_wrap(1);
    }
    xn_print_str(rt_string_from_c("sema ok"));
    return xn_int_wrap(0);
  }
  if (xn_str_eq(cmd, rt_string_from_c("--emit-c"))) {
    if ((((int64_t)args->len) < 2)) {
      return xn_int_wrap(xn_usage());
    }
    xn_Cls_AstNode * program = xn_loadProgram(xn_arr_s_get(args, 1), xdkRoot);
    if ((((int64_t)program->kids->len) == 0)) {
      return xn_int_wrap(1);
    }
    xn_Cls_Checker * c = xn_Cls_Checker_new(xn_arr_s_get(args, 1), program);
    xn_Cls_Checker_check(c);
    if (xn_Cls_Checker_hasError(c)) {
      xn_print_str(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_arr_s_get(args, 1), rt_string_from_c(":")), xn_str_int(c->errorLine)), rt_string_from_c(":")), xn_str_int(c->errorCol)), rt_string_from_c(": [")), c->errorCode), rt_string_from_c("] ")), c->error));
      return xn_int_wrap(1);
    }
    xn_Cls_CGen * g = xn_Cls_CGen_new(program, ffiNames, ffiCNames, ffiRets, ffiParamSpecs, ffiErrParams, ffiErrRets);
    xn_Cls_CGen_gen(g);
    if (xn_Cls_CGen_hasError(g)) {
      xn_print_str(xn_concat(xn_concat(xn_arr_s_get(args, 1), rt_string_from_c(": ")), g->err));
      return xn_int_wrap(1);
    }
    xn_print_str(xn_Cls_CGen_text(g));
    return xn_int_wrap(0);
  }
  return xn_int_wrap(xn_usage());
}

int main(int argc, char **argv) {
  xrt_runtime_init();
  xn_init_globals();
  xn_arr_s *args = xn_arr_s_new(argc > 1 ? (size_t)(argc - 1) : 1);
  for (int ai = 1; ai < argc; ai++) { xn_arr_s_push(args, rt_string_from_c(argv[ai])); }
  int64_t xn_result = xn_main(args);
  rt_gc_collect();
  return (int)xn_result;
}
