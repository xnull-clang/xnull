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
static int64_t xn_long_shl(int64_t value, int64_t bitCount) { if (bitCount < 0 || bitCount >= 64) { rt_fatal("shift count out of range"); } return (int64_t)((uint64_t)value << (uint64_t)bitCount); }
static int64_t xn_long_shr(int64_t value, int64_t bitCount) { if (bitCount < 0 || bitCount >= 64) { rt_fatal("shift count out of range"); } return (int64_t)((int64_t)value >> (int64_t)bitCount); }
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
static rt_string *xn_bytes_to_string(xrt_bytes_obj *buffer) { return rt_string_new((const char *)xrt_bytes_data(buffer), (size_t)xrt_bytes_len(buffer)); }
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
static xn_arr_i *xn_arr_i_copy(const xn_arr_i *a) { xn_arr_i *out = xn_arr_i_new(a->len); if (a->len > 0) { memcpy(out->data, a->data, sizeof(int64_t) * a->len); } out->len = a->len; return out; }
static xn_arr_d *xn_arr_d_copy(const xn_arr_d *a) { xn_arr_d *out = xn_arr_d_new(a->len); if (a->len > 0) { memcpy(out->data, a->data, sizeof(double) * a->len); } out->len = a->len; return out; }
static xn_arr_s *xn_arr_s_copy(const xn_arr_s *a) { xn_arr_s *out = xn_arr_s_new(a->len); if (a->len > 0) { memcpy(out->data, a->data, sizeof(rt_string *) * a->len); } out->len = a->len; return out; }
static xn_arr_o *xn_arr_o_copy(const xn_arr_o *a) { xn_arr_o *out = xn_arr_o_new(a->len); if (a->len > 0) { memcpy(out->data, a->data, sizeof(void *) * a->len); } out->len = a->len; return out; }
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
static xn_arr_r *xn_arr_r_copy(const xn_arr_r *a) { xn_arr_r *out = xn_arr_r_new(a->len); if (a->len > 0) { memcpy(out->data, a->data, sizeof(xn_Result) * a->len); } out->len = a->len; return out; }
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
typedef struct xn_Cls_AnnotationDiag xn_Cls_AnnotationDiag;
typedef struct xn_Cls_AnnotationType xn_Cls_AnnotationType;
typedef struct xn_Cls_AnnotationChecker xn_Cls_AnnotationChecker;
typedef struct xn_Cls_Checker xn_Cls_Checker;
typedef struct xn_Cls_AnnotationUseMeta xn_Cls_AnnotationUseMeta;
typedef struct xn_Cls_CGen xn_Cls_CGen;
static xn_Cls_Token *xn_Cls_Token_new(rt_string * kind, rt_string * text, int64_t line, int64_t col);
static xn_Cls_AstNode *xn_Cls_AstNode_new(rt_string * kind, rt_string * text, int64_t line, int64_t col);
static void xn_Cls_AstNode_add(xn_Cls_AstNode *self, xn_Cls_AstNode * kid);
static void xn_Cls_AstNode_annotate(xn_Cls_AstNode *self, xn_Cls_AstNode * use);
static void xn_Cls_AstNode_setKid(xn_Cls_AstNode *self, int64_t idx, xn_Cls_AstNode * v);
static void xn_Cls_AstNode_dump(xn_Cls_AstNode *self, int64_t depth);
static xn_Cls_Parser *xn_Cls_Parser_new(xn_arr_o * ts);
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
static int xn_Cls_Parser_atAnnotationStart(xn_Cls_Parser *self);
static int xn_Cls_Parser_atAnnotationDecl(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseAnnotationUse(xn_Cls_Parser *self);
static xn_arr_o * xn_Cls_Parser_parseAnnotations(xn_Cls_Parser *self);
static void xn_Cls_Parser_attachAnnotations(xn_Cls_Parser *self, xn_Cls_AstNode * n, xn_arr_o * uses);
static xn_Cls_AstNode * xn_Cls_Parser_parseAnnotationDecl(xn_Cls_Parser *self);
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
static xn_Cls_Mono *xn_Cls_Mono_new(xn_Cls_AstNode * p);
static int xn_Cls_Mono_isGenericMethod(xn_Cls_Mono *self, rt_string * className, rt_string * methodName);
static int xn_Cls_Mono_isGenericMethodStatic(xn_Cls_Mono *self, rt_string * className, rt_string * methodName);
static int xn_Cls_Mono_hasTypeParams(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static xn_arr_s * xn_Cls_Mono_typeParams(xn_Cls_Mono *self, xn_Cls_AstNode * fn);
static int xn_Cls_Mono_hasGenericSyntax(xn_Cls_Mono *self, rt_string * ty);
static rt_string * xn_Cls_Mono_genericBase(xn_Cls_Mono *self, rt_string * ty);
static xn_arr_s * xn_Cls_Mono_genericArgsOf(xn_Cls_Mono *self, rt_string * ty);
static rt_string * xn_Cls_Mono_joinTypeArgs(xn_Cls_Mono *self, xn_arr_s * args);
static rt_string * xn_Cls_Mono_instanceName(xn_Cls_Mono *self, rt_string * cname, xn_arr_s * args);
static int xn_Cls_Mono_identChar(xn_Cls_Mono *self, rt_string * c);
static rt_string * xn_Cls_Mono_subst(xn_Cls_Mono *self, rt_string * text, rt_string * from, rt_string * to);
static rt_string * xn_Cls_Mono_substAll(xn_Cls_Mono *self, rt_string * text, xn_arr_s * names, xn_arr_s * args);
static rt_string * xn_Cls_Mono_mangle(xn_Cls_Mono *self, rt_string * ty);
static int xn_Cls_Mono_isDataEnum(xn_Cls_Mono *self, rt_string * name);
static xn_Cls_AstNode * xn_Cls_Mono_findClass(xn_Cls_Mono *self, rt_string * name);
static xn_Cls_AstNode * xn_Cls_Mono_findGenericClass(xn_Cls_Mono *self, rt_string * name);
static xn_arr_s * xn_Cls_Mono_splitArgs(xn_Cls_Mono *self, rt_string * text);
static rt_string * xn_Cls_Mono_retTypeText(xn_Cls_Mono *self, xn_Cls_AstNode * m);
static int xn_Cls_Mono_safeInstanceMethod(xn_Cls_Mono *self, rt_string * name);
static int xn_Cls_Mono_methodRecursive(xn_Cls_Mono *self, xn_Cls_AstNode * m, rt_string * base);
static rt_string * xn_Cls_Mono_instantiateClass(xn_Cls_Mono *self, rt_string * cname, xn_arr_s * args);
static void xn_Cls_Mono_instantiateNestedTypes(xn_Cls_Mono *self, xn_Cls_AstNode * cls);
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
static void xn_Cls_Mono_collectDeclTypes(xn_Cls_Mono *self, xn_Cls_AstNode * n, xn_arr_s * names, xn_arr_s * types);
static rt_string * xn_Cls_Mono_declaredType(xn_Cls_Mono *self, xn_arr_s * names, xn_arr_s * types, rt_string * name);
static int xn_Cls_Mono_sameClassType(xn_Cls_Mono *self, rt_string * ty, xn_Cls_AstNode * cls);
static void xn_Cls_Mono_collectClassCalls(xn_Cls_Mono *self, xn_Cls_AstNode * n, xn_Cls_AstNode * cls, xn_arr_s * names, xn_arr_s * types, xn_arr_s * out);
static int xn_Cls_Mono_listHas(xn_Cls_Mono *self, xn_arr_s * items, rt_string * value);
static rt_string * xn_Cls_Mono_mangledTypeName(xn_Cls_Mono *self, rt_string * ty);
static xn_arr_s * xn_Cls_Mono_reachableMethods(xn_Cls_Mono *self, xn_Cls_AstNode * cls, rt_string * iname, rt_string * sname);
static int xn_Cls_Mono_methodIsStatic(xn_Cls_Mono *self, xn_Cls_AstNode * m);
static void xn_Cls_Mono_collectUsedIn(xn_Cls_Mono *self, xn_Cls_AstNode * fn);
static void xn_Cls_Mono_scanUsed(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static void xn_Cls_Mono_collectUsedMethods(xn_Cls_Mono *self);
static rt_string * xn_Cls_Mono_methodReturnType(xn_Cls_Mono *self, rt_string * recvType, rt_string * mth);
static rt_string * xn_Cls_Mono_simpleExprType(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Mono_inferLambdaReturn(xn_Cls_Mono *self, xn_Cls_AstNode * lambda);
static int xn_Cls_Mono_inferTypePattern(xn_Cls_Mono *self, rt_string * pattern, rt_string * actual, xn_arr_s * names, xn_arr_s * inferred);
static rt_string * xn_Cls_Mono_angleFromMangled(xn_Cls_Mono *self, rt_string * ty);
static rt_string * xn_Cls_Mono_typeArgsFor(xn_Cls_Mono *self, xn_Cls_AstNode * call);
static xn_Cls_AstNode * xn_Cls_Mono_walk(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static xn_Cls_AstNode * xn_Cls_Mono_cloneAst(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static int xn_Cls_Mono_hasMember(xn_Cls_Mono *self, xn_Cls_AstNode * cls, xn_Cls_AstNode * member);
static void xn_Cls_Mono_flattenClass(xn_Cls_Mono *self, xn_Cls_AstNode * cls);
static rt_string * xn_Cls_Mono_gmName(xn_Cls_Mono *self, rt_string * className, rt_string * methodName);
static xn_Cls_AstNode * xn_Cls_Mono_replaceSelf(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static void xn_Cls_Mono_desugarGenericMethods(xn_Cls_Mono *self);
static xn_Cls_AstNode * xn_Cls_Mono_rewriteGenericMethodCall(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Mono_firstTypeToken(xn_Cls_Mono *self, rt_string * text);
static xn_Cls_AstNode * xn_Cls_Mono_inferGenericStaticCall(xn_Cls_Mono *self, xn_Cls_AstNode * n, rt_string * expected);
static int xn_Cls_Mono_inferGenericStaticCalls(xn_Cls_Mono *self, xn_Cls_AstNode * n, rt_string * expected, rt_string * curRet);
static xn_Cls_AstNode * xn_Cls_Mono_run(xn_Cls_Mono *self);
static xn_Cls_AnnotationDiag *xn_Cls_AnnotationDiag_new(rt_string * code, rt_string * msg, int64_t line, int64_t col);
static xn_Cls_AnnotationType *xn_Cls_AnnotationType_new(rt_string * name, xn_arr_s * targets, rt_string * retention, int repeatable);
static void xn_Cls_AnnotationType_addField(xn_Cls_AnnotationType *self, rt_string * name, rt_string * ty, int required, xn_Cls_AstNode * def);
static void xn_Cls_AnnotationType_clearTargets(xn_Cls_AnnotationType *self);
static int xn_Cls_AnnotationType_allows(xn_Cls_AnnotationType *self, rt_string * target);
static xn_Cls_AnnotationChecker *xn_Cls_AnnotationChecker_new(rt_string * file, xn_Cls_AstNode * program);
static int xn_Cls_AnnotationChecker_hasError(xn_Cls_AnnotationChecker *self);
static void xn_Cls_AnnotationChecker_fail(xn_Cls_AnnotationChecker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n);
static void xn_Cls_AnnotationChecker_warn(xn_Cls_AnnotationChecker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n, xn_Cls_AstNode * owner);
static void xn_Cls_AnnotationChecker_failAt(xn_Cls_AnnotationChecker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n, xn_Cls_AstNode * owner);
static int xn_Cls_AnnotationChecker_suppressed(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * owner, rt_string * code);
static xn_arr_s * xn_Cls_AnnotationChecker_allTargets(xn_Cls_AnnotationChecker *self);
static xn_arr_s * xn_Cls_AnnotationChecker_declTargets(xn_Cls_AnnotationChecker *self);
static xn_arr_s * xn_Cls_AnnotationChecker_retentionNames(xn_Cls_AnnotationChecker *self);
static xn_arr_s * xn_Cls_AnnotationChecker_knownCodes(xn_Cls_AnnotationChecker *self);
static int xn_Cls_AnnotationChecker_listHas(xn_Cls_AnnotationChecker *self, xn_arr_s * items, rt_string * v);
static int xn_Cls_AnnotationChecker_isReserved(xn_Cls_AnnotationChecker *self, rt_string * name);
static int xn_Cls_AnnotationChecker_isBuiltin(xn_Cls_AnnotationChecker *self, rt_string * name);
static int64_t xn_Cls_AnnotationChecker_findType(xn_Cls_AnnotationChecker *self, rt_string * name);
static int64_t xn_Cls_AnnotationChecker_findTypeFor(xn_Cls_AnnotationChecker *self, rt_string * name, rt_string * ownerPkg);
static void xn_Cls_AnnotationChecker_addBuiltin(xn_Cls_AnnotationChecker *self, rt_string * name, xn_arr_s * targets, int repeatable);
static void xn_Cls_AnnotationChecker_initBuiltins(xn_Cls_AnnotationChecker *self);
static rt_string * xn_Cls_AnnotationChecker_unquote(xn_Cls_AnnotationChecker *self, rt_string * s);
static rt_string * xn_Cls_AnnotationChecker_pathOf(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n);
static int xn_Cls_AnnotationChecker_isEnumItem(xn_Cls_AnnotationChecker *self, rt_string * path);
static rt_string * xn_Cls_AnnotationChecker_enumOwnerOf(xn_Cls_AnnotationChecker *self, rt_string * path);
static rt_string * xn_Cls_AnnotationChecker_constType(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n);
static int xn_Cls_AnnotationChecker_isConstValue(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n);
static int xn_Cls_AnnotationChecker_numericType(xn_Cls_AnnotationChecker *self, rt_string * ty);
static int xn_Cls_AnnotationChecker_accepts(xn_Cls_AnnotationChecker *self, rt_string * fieldType, xn_Cls_AstNode * arg);
static int xn_Cls_AnnotationChecker_constantTypeAllowed(xn_Cls_AnnotationChecker *self, rt_string * ty);
static void xn_Cls_AnnotationChecker_collectTypes(xn_Cls_AnnotationChecker *self);
static void xn_Cls_AnnotationChecker_validateAnnotationDecl(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * d);
static void xn_Cls_AnnotationChecker_validateUses(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * owner, rt_string * target, xn_Cls_AstNode * scope);
static void xn_Cls_AnnotationChecker_validateTypeUses(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * owner, xn_Cls_AstNode * scope);
static void xn_Cls_AnnotationChecker_validateUse(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * use, rt_string * target, xn_Cls_AstNode * owner, xn_arr_o * uses, xn_Cls_AstNode * scope, int64_t index);
static void xn_Cls_AnnotationChecker_collectDeprecated(xn_Cls_AnnotationChecker *self);
static int xn_Cls_AnnotationChecker_hasUse(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, rt_string * name);
static int xn_Cls_AnnotationChecker_isReadOnlyField(xn_Cls_AnnotationChecker *self, rt_string * owner, rt_string * field);
static void xn_Cls_AnnotationChecker_checkDecl(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, rt_string * target);
static void xn_Cls_AnnotationChecker_checkBlock(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * block, xn_Cls_AstNode * owner);
static void xn_Cls_AnnotationChecker_checkExpr(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, xn_Cls_AstNode * owner);
static rt_string * xn_Cls_AnnotationChecker_paramTypesOf(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * fn);
static rt_string * xn_Cls_AnnotationChecker_retOf(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * fn);
static int xn_Cls_AnnotationChecker_protocolHasSig(xn_Cls_AnnotationChecker *self, rt_string * pname, rt_string * mname, rt_string * params, rt_string * ret);
static void xn_Cls_AnnotationChecker_checkOverrides(xn_Cls_AnnotationChecker *self);
static rt_string * xn_Cls_AnnotationChecker_lookupVar(xn_Cls_AnnotationChecker *self, xn_arr_s * names, xn_arr_s * types, rt_string * name);
static void xn_Cls_AnnotationChecker_popVars(xn_Cls_AnnotationChecker *self, xn_arr_s * names, xn_arr_s * types, int64_t mark);
static void xn_Cls_AnnotationChecker_checkReadOnlyIn(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, rt_string * cls, xn_arr_s * names, xn_arr_s * types, xn_Cls_AstNode * owner);
static void xn_Cls_AnnotationChecker_checkReadOnlyWrites(xn_Cls_AnnotationChecker *self);
static void xn_Cls_AnnotationChecker_roCheckMembers(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * c, rt_string * cls);
static void xn_Cls_AnnotationChecker_check(xn_Cls_AnnotationChecker *self);
static xn_Cls_Checker *xn_Cls_Checker_new(rt_string * file, xn_Cls_AstNode * program);
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
static rt_string * xn_Cls_Checker_demangleType(xn_Cls_Checker *self, rt_string * ty);
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
static xn_Cls_AnnotationUseMeta *xn_Cls_AnnotationUseMeta_new(xn_Cls_AstNode * use, xn_Cls_AstNode * decl, rt_string * typeName, rt_string * target, rt_string * targetName, int64_t repeatIndex);
static xn_Cls_CGen *xn_Cls_CGen_new(xn_Cls_AstNode * program, xn_arr_s * callNames, xn_arr_s * callCNames, xn_arr_s * callRets, xn_arr_s * callSpecs, xn_arr_s * callErrParams, xn_arr_s * callErrRets);
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
static int xn_Cls_CGen_literalHasNul(xn_Cls_CGen *self, rt_string * text);
static int xn_Cls_CGen_charNeedsU(xn_Cls_CGen *self, rt_string * text);
static rt_string * xn_Cls_CGen_expr(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static void xn_Cls_CGen_local(xn_Cls_CGen *self, xn_Cls_AstNode * st, rt_string * indent);
static void xn_Cls_CGen_stmt(xn_Cls_CGen *self, xn_Cls_AstNode * st, rt_string * indent);
static void xn_Cls_CGen_emitDefers(xn_Cls_CGen *self, rt_string * indent, int includeErr);
static void xn_Cls_CGen_blockBody(xn_Cls_CGen *self, xn_Cls_AstNode * block, rt_string * indent);
static int xn_Cls_CGen_methodStatic(xn_Cls_CGen *self, xn_Cls_AstNode * m);
static rt_string * xn_Cls_CGen_methodSig(xn_Cls_CGen *self, xn_Cls_AstNode * m, rt_string * cls);
static void xn_Cls_CGen_method(xn_Cls_CGen *self, xn_Cls_AstNode * m, rt_string * cls);
static xn_Cls_AstNode * xn_Cls_CGen_ctorOf(xn_Cls_CGen *self, xn_Cls_AstNode * cls);
static xn_Cls_AstNode * xn_Cls_CGen_deinitOf(xn_Cls_CGen *self, xn_Cls_AstNode * cls);
static rt_string * xn_Cls_CGen_baseNameOf(xn_Cls_CGen *self, xn_Cls_AstNode * cls);
static xn_Cls_AstNode * xn_Cls_CGen_classByName(xn_Cls_CGen *self, rt_string * name);
static int xn_Cls_CGen_hasSuperDeinitCall(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static void xn_Cls_CGen_deinitMethod(xn_Cls_CGen *self, xn_Cls_AstNode * d, rt_string * cn);
static void xn_Cls_CGen_genClass(xn_Cls_CGen *self, xn_Cls_AstNode * cls);
static rt_string * xn_Cls_CGen_funcProto(xn_Cls_CGen *self, xn_Cls_AstNode * fn);
static void xn_Cls_CGen_func(xn_Cls_CGen *self, xn_Cls_AstNode * fn);
static rt_string * xn_Cls_CGen_annotationPackageName(xn_Cls_CGen *self);
static rt_string * xn_Cls_CGen_annotationQualifiedFor(xn_Cls_CGen *self, rt_string * name, rt_string * ownerPkg);
static rt_string * xn_Cls_CGen_annotationQualified(xn_Cls_CGen *self, rt_string * name);
static rt_string * xn_Cls_CGen_typeTextOf(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static int xn_Cls_CGen_knownTypeName(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_qualifiedTypeName(xn_Cls_CGen *self, rt_string * ty, rt_string * ownerPkg);
static void xn_Cls_CGen_collectTypeUses(xn_Cls_CGen *self, xn_Cls_AstNode * node, rt_string * targetName, rt_string * ownerPkg, xn_arr_o * out);
static void xn_Cls_CGen_collectTypeUseLocals(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * methodOwner, rt_string * ownerPkg, xn_arr_o * out);
static rt_string * xn_Cls_CGen_annotationStringText(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_CGen_annotationPath(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_CGen_annotationLastSegment(xn_Cls_CGen *self, rt_string * path);
static xn_Cls_AstNode * xn_Cls_CGen_annotationFindDeclFor(xn_Cls_CGen *self, rt_string * name, rt_string * ownerPkg);
static rt_string * xn_Cls_CGen_annotationRetention(xn_Cls_CGen *self, xn_Cls_AstNode * decl);
static xn_arr_o * xn_Cls_CGen_annotationFields(xn_Cls_CGen *self, xn_Cls_AstNode * decl);
static rt_string * xn_Cls_CGen_annotationFieldType(xn_Cls_CGen *self, xn_Cls_AstNode * f);
static rt_string * xn_Cls_CGen_annotationFieldName(xn_Cls_CGen *self, xn_Cls_AstNode * f);
static rt_string * xn_Cls_CGen_annotationParamTypes(xn_Cls_CGen *self, xn_Cls_AstNode * fn);
static void xn_Cls_CGen_collectAnnotationUses(xn_Cls_CGen *self, xn_Cls_AstNode * node, rt_string * target, rt_string * targetName, xn_arr_o * out);
static void xn_Cls_CGen_collectAnnotationParams(xn_Cls_CGen *self, xn_Cls_AstNode * fn, rt_string * memberTarget, xn_arr_o * out);
static void xn_Cls_CGen_collectAnnotationClass(xn_Cls_CGen *self, xn_Cls_AstNode * cls, xn_arr_o * out);
static xn_arr_o * xn_Cls_CGen_collectGeneratedAnnotations(xn_Cls_CGen *self);
static rt_string * xn_Cls_CGen_annotationNumberText(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_CGen_emitAnnotationValue(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * expected, rt_string * indent);
static rt_string * xn_Cls_CGen_emitAnnotationInfo(xn_Cls_CGen *self, xn_Cls_AstNode * use, xn_Cls_AstNode * decl, rt_string * typeName, rt_string * target, rt_string * targetName, int64_t repeatIndex, rt_string * indent);
static void xn_Cls_CGen_emitAnnotationRegistry(xn_Cls_CGen *self);
static void xn_Cls_CGen_gen(xn_Cls_CGen *self);
static rt_string * xn_Cls_CGen_text(xn_Cls_CGen *self);
static xn_arr_s * loadedFiles;
static xn_arr_s * compilerWarnings;
static rt_string * loadBaseDir;
static rt_string * loadRoot;
static int xdkFullSource;
static rt_string * rootPackageName;
static xn_arr_o * unitDeclNodes;
static xn_arr_s * unitDeclPkgs;
static xn_arr_s * unitImportOwners;
static xn_arr_s * unitImportPkgs;
static xn_arr_s * ffiNames;
static xn_arr_s * ffiCNames;
static xn_arr_s * ffiRets;
static xn_arr_s * ffiParamSpecs;
static xn_arr_s * ffiErrParams;
static xn_arr_s * ffiErrRets;
static rt_string * a8ErrorCode;
static rt_string * a8ErrorMessage;
static int64_t a8ErrorLine;
static int64_t a8ErrorCol;


static int64_t xn_usage(void);
static rt_string * xn_at(rt_string * s, int64_t i);
static int xn_starts(rt_string * s, int64_t i, rt_string * lit);
static int xn_isDigit(rt_string * c);
static int xn_isHex(rt_string * c);
static int64_t xn_hexValue(rt_string * c);
static int xn_validScalar(int64_t value);
static int xn_validEscapeAt(rt_string * src, int64_t slash, int64_t limit);
static int xn_isLower(rt_string * c);
static int xn_isUpper(rt_string * c);
static int xn_isIdentStart(rt_string * c);
static int xn_isIdentPart(rt_string * c);
static int xn_isSpace(rt_string * c);
static int xn_isKeyword(rt_string * s);
static rt_string * xn_cStringLiteral(rt_string * content);
static rt_string * xn_canonicalStringLiteral(rt_string * raw);
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
static rt_string * xn_packageNameOf(xn_Cls_AstNode * program);
static rt_string * xn_declPackageOf(xn_Cls_AstNode * n);
static void xn_mergeDecls(xn_Cls_AstNode * program, xn_Cls_AstNode * parsed);
static void xn_loadUnit(rt_string * path, xn_Cls_AstNode * program);
static void xn_loadSiblings(rt_string * path, xn_Cls_AstNode * program);
static rt_string * xn_simpleTypeUseName(rt_string * name);
static rt_string * xn_targetPath(xn_Cls_AstNode * n);
static xn_arr_s * xn_annotationTargetSet(xn_Cls_AstNode * program, rt_string * useText);
static int xn_typeUsePosition(xn_Cls_AstNode * n);
static void xn_splitTypeUseAnnotationsIn(xn_Cls_AstNode * n, xn_Cls_AstNode * program);
static void xn_splitTypeUseAnnotations(xn_Cls_AstNode * program);
static rt_string * xn_annotationCandidates(rt_string * simple);
static void xn_resolveAnnotationUse(xn_Cls_AstNode * use, rt_string * ownerPkg);
static void xn_resolveAnnotationTree(xn_Cls_AstNode * n, rt_string * ownerPkg);
static void xn_resolveAnnotationUses(xn_Cls_AstNode * program);
static rt_string * xn_a8SimpleName(rt_string * name);
static int xn_a8Fail(rt_string * code, rt_string * message, xn_Cls_AstNode * n);
static int xn_a8HasAnno(xn_Cls_AstNode * cls, rt_string * name);
static void xn_a8DropAnno(xn_Cls_AstNode * cls, rt_string * name);
static xn_arr_s * xn_a8TypeParams(xn_Cls_AstNode * cls);
static rt_string * xn_a8ClassType(xn_Cls_AstNode * cls);
static rt_string * xn_a8Capitalize(rt_string * name);
static int xn_a8MethodExists(xn_Cls_AstNode * cls, rt_string * name);
static xn_Cls_AstNode * xn_a8Method(rt_string * name, rt_string * retType, xn_Cls_AstNode * cls);
static xn_Cls_AstNode * xn_a8SelfField(rt_string * field);
static xn_Cls_AstNode * xn_a8OtherField(rt_string * field);
static xn_arr_o * xn_a8InstanceFields(xn_Cls_AstNode * cls);
static int xn_a8IsFinalField(xn_Cls_AstNode * f);
static rt_string * xn_a8FieldType(xn_Cls_AstNode * f);
static rt_string * xn_a8FieldName(xn_Cls_AstNode * f);
static xn_Cls_AstNode * xn_a8Ctor(xn_Cls_AstNode * cls);
static int xn_a8CtorMatches(xn_Cls_AstNode * cls, xn_arr_o * fields);
static xn_Cls_AstNode * xn_a8EqualsMethod(xn_Cls_AstNode * cls, xn_arr_o * fields);
static xn_Cls_AstNode * xn_a8ToStringMethod(xn_Cls_AstNode * cls, xn_arr_o * fields);
static xn_Cls_AstNode * xn_a8CopyMethod(xn_Cls_AstNode * cls, xn_arr_o * fields);
static xn_Cls_AstNode * xn_a8WithMethod(xn_Cls_AstNode * cls, xn_Cls_AstNode * field);
static int xn_a8ClassExists(xn_Cls_AstNode * program, rt_string * name);
static xn_arr_o * xn_a8CtorParams(xn_Cls_AstNode * cls);
static rt_string * xn_a8ParamType(xn_Cls_AstNode * p);
static rt_string * xn_a8ParamName(xn_Cls_AstNode * p);
static xn_Cls_AstNode * xn_a8BuilderField(rt_string * ty, rt_string * name, xn_Cls_AstNode * cls);
static xn_Cls_AstNode * xn_a8BuilderWith(xn_Cls_AstNode * builder, xn_Cls_AstNode * p, rt_string * fname, xn_Cls_AstNode * cls);
static xn_Cls_AstNode * xn_a8BuilderBuild(xn_Cls_AstNode * builder, xn_Cls_AstNode * cls, xn_arr_o * params, xn_arr_o * fields);
static xn_Cls_AstNode * xn_a8BuildBuilder(xn_Cls_AstNode * cls, xn_arr_o * params, xn_arr_o * fields);
static int xn_a8ListHas(xn_arr_s * items, rt_string * value);
static int xn_a8FieldHasAnno(xn_Cls_AstNode * f, rt_string * name);
static void xn_a8DropFieldAnno(xn_Cls_AstNode * f, rt_string * name);
static xn_Cls_AstNode * xn_a8FindClassIn(xn_Cls_AstNode * program, rt_string * name);
static rt_string * xn_a8TypeBase(rt_string * ty);
static int xn_a8MethodStatic(xn_Cls_AstNode * m);
static xn_Cls_AstNode * xn_a8DelegateMethod(xn_Cls_AstNode * host, xn_Cls_AstNode * field, xn_Cls_AstNode * target);
static int xn_expandA8Class(xn_Cls_AstNode * cls, xn_Cls_AstNode * program);
static int xn_expandA8Annotations(xn_Cls_AstNode * program);
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
  xn_arr_o * annotations;
  xn_arr_o * typeAnnotations;
  rt_string * packageName;
  rt_string * resolvedAnnotationName;
  rt_string * annotationError;
  int isFinalField;
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
  xn_obj->annotations = xn_arr_o_new(4);
  xn_obj->typeAnnotations = xn_arr_o_new(4);
  xn_obj->packageName = rt_string_from_c("");
  xn_obj->resolvedAnnotationName = rt_string_from_c("");
  xn_obj->annotationError = rt_string_from_c("");
  xn_obj->isFinalField = 0;
  xn_Cls_AstNode *self = xn_obj;
  self->kind = kind;
  self->text = text;
  self->line = line;
  self->col = col;
  self->kids = xn_arr_o_new(0);
  self->annotations = xn_arr_o_new(0);
  self->typeAnnotations = xn_arr_o_new(0);
  self->packageName = rt_string_from_c("");
  self->resolvedAnnotationName = rt_string_from_c("");
  self->annotationError = rt_string_from_c("");
  self->isFinalField = 0;
  return xn_obj;
}

static void xn_Cls_AstNode_add(xn_Cls_AstNode *self, xn_Cls_AstNode * kid);
static void xn_Cls_AstNode_annotate(xn_Cls_AstNode *self, xn_Cls_AstNode * use);
static void xn_Cls_AstNode_setKid(xn_Cls_AstNode *self, int64_t idx, xn_Cls_AstNode * v);
static void xn_Cls_AstNode_dump(xn_Cls_AstNode *self, int64_t depth);

static void xn_Cls_AstNode_add(xn_Cls_AstNode *self, xn_Cls_AstNode * kid) {
  xn_arr_o_push(self->kids, kid);
}

static void xn_Cls_AstNode_annotate(xn_Cls_AstNode *self, xn_Cls_AstNode * use) {
  xn_arr_o_push(self->annotations, use);
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
  int64_t ai = xn_int_wrap(0);
  while ((ai < ((int64_t)self->annotations->len))) {
    xn_Cls_AstNode * ann = ((xn_Cls_AstNode *)xn_arr_o_get(self->annotations, ai));
    xn_Cls_AstNode_dump(ann, xn_int_wrap((depth + 1)));
    ai = xn_int_wrap((ai + 1));
  }
  if ((((int64_t)self->typeAnnotations->len) > 0)) {
    xn_print_str(xn_concat(pad, rt_string_from_c("  TypeUse")));
    int64_t ti = xn_int_wrap(0);
    while ((ti < ((int64_t)self->typeAnnotations->len))) {
      xn_Cls_AstNode_dump(((xn_Cls_AstNode *)xn_arr_o_get(self->typeAnnotations, ti)), xn_int_wrap((depth + 2)));
      ti = xn_int_wrap((ti + 1));
    }
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
static int xn_Cls_Parser_atAnnotationStart(xn_Cls_Parser *self);
static int xn_Cls_Parser_atAnnotationDecl(xn_Cls_Parser *self);
static xn_Cls_AstNode * xn_Cls_Parser_parseAnnotationUse(xn_Cls_Parser *self);
static xn_arr_o * xn_Cls_Parser_parseAnnotations(xn_Cls_Parser *self);
static void xn_Cls_Parser_attachAnnotations(xn_Cls_Parser *self, xn_Cls_AstNode * n, xn_arr_o * uses);
static xn_Cls_AstNode * xn_Cls_Parser_parseAnnotationDecl(xn_Cls_Parser *self);
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

static int xn_Cls_Parser_atAnnotationStart(xn_Cls_Parser *self) {
  return (xn_Cls_Parser_at(self, rt_string_from_c("@")) && (xn_str_eq(xn_Cls_Parser_look(self, 1)->kind, rt_string_from_c("ident")) || xn_str_eq(xn_Cls_Parser_look(self, 1)->kind, rt_string_from_c("kw"))));
}

static int xn_Cls_Parser_atAnnotationDecl(xn_Cls_Parser *self) {
  return (xn_Cls_Parser_at(self, rt_string_from_c("@")) && xn_str_eq(xn_Cls_Parser_look(self, 1)->text, rt_string_from_c("annotation")));
}

static xn_Cls_AstNode * xn_Cls_Parser_parseAnnotationUse(xn_Cls_Parser *self) {
  xn_Cls_Token * at = xn_Cls_Parser_expect(self, rt_string_from_c("@"));
  if (((!xn_Cls_Parser_kind(self, rt_string_from_c("ident"))) && (!xn_Cls_Parser_kind(self, rt_string_from_c("kw"))))) {
    xn_Cls_Parser_fail(self, rt_string_from_c("expected annotation name"));
    return xn_Cls_Parser_node(self, rt_string_from_c("error"), rt_string_from_c(""), at);
  }
  xn_Cls_Token * nt = xn_Cls_Parser_advance(self);
  xn_Cls_AstNode * use = xn_Cls_AstNode_new(rt_string_from_c("AnnotationUse"), nt->text, at->line, at->col);
  if (xn_Cls_Parser_eat(self, rt_string_from_c("("))) {
    int64_t idx = xn_int_wrap(0);
    if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
      while ((!xn_Cls_Parser_hasError(self))) {
        xn_Cls_Token * at2 = xn_Cls_Parser_peek(self);
        xn_Cls_AstNode * arg = xn_Cls_AstNode_new(rt_string_from_c("AnnotationArg"), xn_str_int(idx), at2->line, at2->col);
        if ((xn_Cls_Parser_atAnnotationStart(self) && (!xn_Cls_Parser_atAnnotationDecl(self)))) {
          xn_Cls_AstNode_add(arg, xn_Cls_Parser_parseAnnotationUse(self));
        }
        else {
          xn_Cls_AstNode_add(arg, xn_Cls_Parser_parseExpr(self));
        }
        xn_Cls_AstNode_add(use, arg);
        idx = xn_int_wrap((idx + 1));
        if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
          break;
        }
      }
    }
    xn_Cls_Parser_expect(self, rt_string_from_c(")"));
  }
  return use;
}

static xn_arr_o * xn_Cls_Parser_parseAnnotations(xn_Cls_Parser *self) {
  xn_arr_o *uses = xn_arr_o_new(0);
  while ((xn_Cls_Parser_atAnnotationStart(self) && (!xn_Cls_Parser_atAnnotationDecl(self)))) {
    xn_arr_o_push(uses, xn_Cls_Parser_parseAnnotationUse(self));
  }
  return uses;
}

static void xn_Cls_Parser_attachAnnotations(xn_Cls_Parser *self, xn_Cls_AstNode * n, xn_arr_o * uses) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)uses->len))) {
    xn_Cls_AstNode_annotate(n, ((xn_Cls_AstNode *)xn_arr_o_get(uses, i)));
    i = xn_int_wrap((i + 1));
  }
}

static xn_Cls_AstNode * xn_Cls_Parser_parseAnnotationDecl(xn_Cls_Parser *self) {
  xn_Cls_Token * at = xn_Cls_Parser_expect(self, rt_string_from_c("@"));
  xn_Cls_Parser_expect(self, rt_string_from_c("annotation"));
  if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
    xn_Cls_Parser_fail(self, rt_string_from_c("expected annotation name"));
    return xn_Cls_Parser_node(self, rt_string_from_c("error"), rt_string_from_c(""), at);
  }
  xn_Cls_Token * nt = xn_Cls_Parser_advance(self);
  xn_Cls_AstNode * d = xn_Cls_AstNode_new(rt_string_from_c("AnnotationDecl"), nt->text, at->line, at->col);
  xn_Cls_Parser_expect(self, rt_string_from_c("{"));
  while ((((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c("}")))) && (!xn_Cls_Parser_eof(self)))) {
    while ((((xn_Cls_Parser_at(self, rt_string_from_c("final")) || xn_Cls_Parser_at(self, rt_string_from_c("public"))) || xn_Cls_Parser_at(self, rt_string_from_c("private"))) || xn_Cls_Parser_at(self, rt_string_from_c("protected")))) {
      xn_Cls_Parser_advance(self);
    }
    rt_string * ty = xn_Cls_Parser_parseType(self);
    if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("expected annotation field name"));
      break;
    }
    xn_Cls_Token * ft = xn_Cls_Parser_advance(self);
    xn_Cls_AstNode * f = xn_Cls_AstNode_new(rt_string_from_c("AnnotationField"), xn_concat(xn_concat(ty, rt_string_from_c(" ")), ft->text), ft->line, ft->col);
    if (xn_Cls_Parser_eat(self, rt_string_from_c("="))) {
      if ((xn_Cls_Parser_atAnnotationStart(self) && (!xn_Cls_Parser_atAnnotationDecl(self)))) {
        xn_Cls_AstNode_add(f, xn_Cls_Parser_parseAnnotationUse(self));
      }
      else {
        xn_Cls_AstNode_add(f, xn_Cls_Parser_parseExpr(self));
      }
    }
    xn_Cls_Parser_eat(self, rt_string_from_c(";"));
    xn_Cls_AstNode_add(d, f);
  }
  xn_Cls_Parser_expect(self, rt_string_from_c("}"));
  return d;
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
  if (xn_Cls_Parser_atAnnotationDecl(self)) {
    return xn_Cls_Parser_parseAnnotationDecl(self);
  }
  if (xn_Cls_Parser_atAnnotationStart(self)) {
    xn_arr_o * anns = xn_Cls_Parser_parseAnnotations(self);
    if (xn_Cls_Parser_atAnnotationDecl(self)) {
      xn_Cls_AstNode * ad = xn_Cls_Parser_parseAnnotationDecl(self);
      xn_Cls_Parser_attachAnnotations(self, ad, anns);
      return ad;
    }
    xn_Cls_AstNode * d = xn_Cls_Parser_parseTop(self);
    xn_Cls_Parser_attachAnnotations(self, d, anns);
    return d;
  }
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
      xn_arr_o * panns = xn_Cls_Parser_parseAnnotations(self);
      if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("expected type parameter"));
        break;
      }
      xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
      xn_Cls_AstNode * tpn = xn_Cls_AstNode_new(rt_string_from_c("TypeParam"), pn->text, pn->line, pn->col);
      xn_Cls_Parser_attachAnnotations(self, tpn, panns);
      xn_Cls_AstNode_add(tp, tpn);
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
    xn_arr_o * memberAnns = xn_Cls_Parser_parseAnnotations(self);
    int isStatic = 0;
    int isFinal = 0;
    int hasVisibility = 0;
    while (((((xn_Cls_Parser_at(self, rt_string_from_c("static")) || xn_Cls_Parser_at(self, rt_string_from_c("final"))) || xn_Cls_Parser_at(self, rt_string_from_c("public"))) || xn_Cls_Parser_at(self, rt_string_from_c("private"))) || xn_Cls_Parser_at(self, rt_string_from_c("protected")))) {
      if (xn_Cls_Parser_at(self, rt_string_from_c("static"))) {
        isStatic = 1;
      }
      if (xn_Cls_Parser_at(self, rt_string_from_c("final"))) {
        isFinal = 1;
      }
      if (((xn_Cls_Parser_at(self, rt_string_from_c("public")) || xn_Cls_Parser_at(self, rt_string_from_c("private"))) || xn_Cls_Parser_at(self, rt_string_from_c("protected")))) {
        hasVisibility = 1;
      }
      xn_Cls_Parser_advance(self);
    }
    if (xn_Cls_Parser_at(self, rt_string_from_c("deinit"))) {
      xn_Cls_Token * dt = xn_Cls_Parser_advance(self);
      if ((!xn_str_eq(kindName, rt_string_from_c("Class")))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("deinit is only allowed in class"));
        return cls;
      }
      if (isStatic) {
        xn_Cls_Parser_fail(self, rt_string_from_c("deinit cannot be static"));
        return cls;
      }
      if (hasVisibility) {
        xn_Cls_Parser_fail(self, rt_string_from_c("deinit cannot have a visibility modifier"));
        return cls;
      }
      xn_Cls_AstNode * d = xn_Cls_Parser_node(self, rt_string_from_c("Deinit"), rt_string_from_c(""), dt);
      xn_Cls_Parser_expect(self, rt_string_from_c("("));
      if (((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c(")"))))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("deinit cannot have parameters"));
        return cls;
      }
      xn_Cls_Parser_expect(self, rt_string_from_c(")"));
      xn_Cls_AstNode_add(d, xn_Cls_Parser_parseBlock(self));
      xn_Cls_Parser_attachAnnotations(self, d, memberAnns);
      xn_Cls_AstNode_add(cls, d);
      continue;
    }
    rt_string * ty = xn_Cls_Parser_parseType(self);
    if ((xn_Cls_Parser_at(self, rt_string_from_c("(")) && xn_str_eq(ty, name))) {
      xn_Cls_Token * ct = xn_Cls_Parser_peek(self);
      xn_Cls_AstNode * ctor = xn_Cls_Parser_node(self, rt_string_from_c("Ctor"), name, ct);
      xn_Cls_Parser_expect(self, rt_string_from_c("("));
      if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
        while ((!xn_Cls_Parser_hasError(self))) {
          xn_arr_o * parms = xn_Cls_Parser_parseAnnotations(self);
          rt_string * pt = xn_Cls_Parser_parseType(self);
          if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
            xn_Cls_Parser_fail(self, rt_string_from_c("expected constructor parameter name"));
            break;
          }
          xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
          xn_Cls_AstNode * prm = xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), ct->line, ct->col);
          xn_Cls_Parser_attachAnnotations(self, prm, parms);
          xn_Cls_AstNode_add(ctor, prm);
          if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
            break;
          }
        }
      }
      xn_Cls_Parser_expect(self, rt_string_from_c(")"));
      xn_Cls_AstNode_add(ctor, xn_Cls_Parser_parseBlock(self));
      xn_Cls_Parser_attachAnnotations(self, ctor, memberAnns);
      xn_Cls_AstNode_add(cls, ctor);
      continue;
    }
    if (xn_Cls_Parser_at(self, rt_string_from_c("deinit"))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("deinit cannot declare a return type"));
      break;
    }
    if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("expected member name"));
      break;
    }
    xn_Cls_Token * mt = xn_Cls_Parser_advance(self);
    rt_string * mn = mt->text;
    if (xn_str_eq(mn, rt_string_from_c("deinit"))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("deinit cannot declare a return type"));
      return cls;
    }
    int hasMethodTypeParams = 0;
    xn_Cls_AstNode * methodTypeParams = xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), mt->line, mt->col);
    if (xn_Cls_Parser_at(self, rt_string_from_c("<"))) {
      xn_Cls_Parser_advance(self);
      methodTypeParams = xn_Cls_AstNode_new(rt_string_from_c("TypeParams"), rt_string_from_c(""), mt->line, mt->col);
      while (((!xn_Cls_Parser_hasError(self)) && (!xn_Cls_Parser_at(self, rt_string_from_c(">"))))) {
        xn_arr_o * panns = xn_Cls_Parser_parseAnnotations(self);
        if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
          xn_Cls_Parser_fail(self, rt_string_from_c("expected method type parameter"));
          break;
        }
        xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
        xn_Cls_AstNode * tpn = xn_Cls_AstNode_new(rt_string_from_c("TypeParam"), pn->text, pn->line, pn->col);
        xn_Cls_Parser_attachAnnotations(self, tpn, panns);
        xn_Cls_AstNode_add(methodTypeParams, tpn);
        if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
          break;
        }
      }
      xn_Cls_Parser_expect(self, rt_string_from_c(">"));
      hasMethodTypeParams = 1;
    }
    if (xn_Cls_Parser_at(self, rt_string_from_c("("))) {
      xn_Cls_AstNode * m = xn_Cls_Parser_node(self, rt_string_from_c("Method"), mn, mt);
      if (isStatic) {
        xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Static"), rt_string_from_c(""), mt->line, mt->col));
      }
      xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Ret"), ty, mt->line, mt->col));
      if (hasMethodTypeParams) {
        xn_Cls_AstNode_add(m, methodTypeParams);
      }
      xn_Cls_Parser_advance(self);
      if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
        while ((!xn_Cls_Parser_hasError(self))) {
          xn_arr_o * parms = xn_Cls_Parser_parseAnnotations(self);
          rt_string * pt = xn_Cls_Parser_parseType(self);
          if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
            xn_Cls_Parser_fail(self, rt_string_from_c("expected parameter name"));
            break;
          }
          xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
          xn_Cls_AstNode * prm = xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), mt->line, mt->col);
          xn_Cls_Parser_attachAnnotations(self, prm, parms);
          xn_Cls_AstNode_add(m, prm);
          if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
            break;
          }
        }
      }
      xn_Cls_Parser_expect(self, rt_string_from_c(")"));
      xn_Cls_AstNode_add(m, xn_Cls_Parser_parseBlock(self));
      xn_Cls_Parser_attachAnnotations(self, m, memberAnns);
      xn_Cls_AstNode_add(cls, m);
    }
    else {
      xn_Cls_AstNode * f = xn_Cls_Parser_node(self, rt_string_from_c("Field"), xn_concat(xn_concat(ty, rt_string_from_c(" ")), mn), mt);
      if (isStatic) {
        xn_Cls_AstNode_add(f, xn_Cls_AstNode_new(rt_string_from_c("Static"), rt_string_from_c(""), mt->line, mt->col));
      }
      if (isFinal) {
        f->isFinalField = 1;
      }
      if (xn_Cls_Parser_eat(self, rt_string_from_c("="))) {
        xn_Cls_AstNode_add(f, xn_Cls_Parser_parseExpr(self));
      }
      xn_Cls_Parser_eat(self, rt_string_from_c(";"));
      xn_Cls_Parser_attachAnnotations(self, f, memberAnns);
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
    xn_arr_o * itemAnns = xn_Cls_Parser_parseAnnotations(self);
    if (xn_Cls_Parser_at(self, rt_string_from_c("deinit"))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("deinit is only allowed in class"));
      break;
    }
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
    xn_Cls_Parser_attachAnnotations(self, item, itemAnns);
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
      xn_arr_o * memberAnns = xn_Cls_Parser_parseAnnotations(self);
      while (((((xn_Cls_Parser_at(self, rt_string_from_c("static")) || xn_Cls_Parser_at(self, rt_string_from_c("final"))) || xn_Cls_Parser_at(self, rt_string_from_c("public"))) || xn_Cls_Parser_at(self, rt_string_from_c("private"))) || xn_Cls_Parser_at(self, rt_string_from_c("protected")))) {
        xn_Cls_Parser_advance(self);
      }
      if (xn_Cls_Parser_at(self, rt_string_from_c("deinit"))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("deinit is only allowed in class"));
        break;
      }
      rt_string * ty = xn_Cls_Parser_parseType(self);
      if ((xn_Cls_Parser_at(self, rt_string_from_c("(")) && xn_str_eq(ty, e->text))) {
        xn_Cls_Token * ct = xn_Cls_Parser_peek(self);
        xn_Cls_AstNode * ctor = xn_Cls_Parser_node(self, rt_string_from_c("Ctor"), e->text, ct);
        xn_Cls_Parser_expect(self, rt_string_from_c("("));
        if ((!xn_Cls_Parser_at(self, rt_string_from_c(")")))) {
          while ((!xn_Cls_Parser_hasError(self))) {
            xn_arr_o * parms = xn_Cls_Parser_parseAnnotations(self);
            rt_string * pt = xn_Cls_Parser_parseType(self);
            if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
              xn_Cls_Parser_fail(self, rt_string_from_c("expected constructor parameter name"));
              break;
            }
            xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
            xn_Cls_AstNode * prm = xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), ct->line, ct->col);
            xn_Cls_Parser_attachAnnotations(self, prm, parms);
            xn_Cls_AstNode_add(ctor, prm);
            if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
              break;
            }
          }
        }
        xn_Cls_Parser_expect(self, rt_string_from_c(")"));
        xn_Cls_AstNode_add(ctor, xn_Cls_Parser_parseBlock(self));
        xn_Cls_Parser_attachAnnotations(self, ctor, memberAnns);
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
            xn_arr_o * parms = xn_Cls_Parser_parseAnnotations(self);
            rt_string * pt = xn_Cls_Parser_parseType(self);
            if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
              xn_Cls_Parser_fail(self, rt_string_from_c("expected parameter name"));
              break;
            }
            xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
            xn_Cls_AstNode * prm = xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), mt->line, mt->col);
            xn_Cls_Parser_attachAnnotations(self, prm, parms);
            xn_Cls_AstNode_add(m, prm);
            if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
              break;
            }
          }
        }
        xn_Cls_Parser_expect(self, rt_string_from_c(")"));
        xn_Cls_AstNode_add(m, xn_Cls_Parser_parseBlock(self));
        xn_Cls_Parser_attachAnnotations(self, m, memberAnns);
        xn_Cls_AstNode_add(e, m);
      }
      else {
        xn_Cls_AstNode * f = xn_Cls_Parser_node(self, rt_string_from_c("Field"), xn_concat(xn_concat(ty, rt_string_from_c(" ")), mt->text), mt);
        if (xn_Cls_Parser_eat(self, rt_string_from_c("="))) {
          xn_Cls_AstNode_add(f, xn_Cls_Parser_parseExpr(self));
        }
        xn_Cls_Parser_eat(self, rt_string_from_c(";"));
        xn_Cls_Parser_attachAnnotations(self, f, memberAnns);
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
    xn_arr_o * sigAnns = xn_Cls_Parser_parseAnnotations(self);
    if (xn_Cls_Parser_at(self, rt_string_from_c("deinit"))) {
      xn_Cls_Parser_fail(self, rt_string_from_c("deinit is only allowed in class"));
      break;
    }
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
        xn_arr_o * parms = xn_Cls_Parser_parseAnnotations(self);
        rt_string * pt = xn_Cls_Parser_parseType(self);
        if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
          xn_Cls_Parser_fail(self, rt_string_from_c("expected parameter name"));
          break;
        }
        xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
        xn_Cls_AstNode * prm = xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), mn->line, mn->col);
        xn_Cls_Parser_attachAnnotations(self, prm, parms);
        xn_Cls_AstNode_add(m, prm);
        if ((!xn_Cls_Parser_eat(self, rt_string_from_c(",")))) {
          break;
        }
      }
    }
    xn_Cls_Parser_expect(self, rt_string_from_c(")"));
    xn_Cls_Parser_expect(self, rt_string_from_c(";"));
    xn_Cls_Parser_attachAnnotations(self, m, sigAnns);
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
      xn_arr_o * panns = xn_Cls_Parser_parseAnnotations(self);
      if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("expected type parameter"));
        break;
      }
      xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
      xn_Cls_AstNode * tpn = xn_Cls_AstNode_new(rt_string_from_c("TypeParam"), pn->text, pn->line, pn->col);
      xn_Cls_Parser_attachAnnotations(self, tpn, panns);
      xn_Cls_AstNode_add(tp, tpn);
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
      xn_arr_o * parms = xn_Cls_Parser_parseAnnotations(self);
      rt_string * pt = xn_Cls_Parser_parseType(self);
      if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("expected parameter name"));
        break;
      }
      xn_Cls_Token * pnToken = xn_Cls_Parser_advance(self);
      rt_string * pn = pnToken->text;
      xn_Cls_AstNode * prm = xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn), t->line, t->col);
      xn_Cls_Parser_attachAnnotations(self, prm, parms);
      xn_Cls_AstNode_add(fn, prm);
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
      else {
        if (xn_str_eq(t->kind, rt_string_from_c("ident"))) {
        }
        else {
          if ((((((((xn_str_eq(t->text, rt_string_from_c(".")) || xn_str_eq(t->text, rt_string_from_c(","))) || xn_str_eq(t->text, rt_string_from_c("?"))) || xn_str_eq(t->text, rt_string_from_c("["))) || xn_str_eq(t->text, rt_string_from_c("]"))) || xn_str_eq(t->text, rt_string_from_c("("))) || xn_str_eq(t->text, rt_string_from_c(")"))) || xn_str_eq(t->text, rt_string_from_c("->")))) {
          }
          else {
            return 0;
          }
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
    if (xn_Cls_Parser_atAnnotationDecl(self)) {
      xn_Cls_AstNode_add(block, xn_Cls_Parser_parseAnnotationDecl(self));
    }
    else {
      xn_arr_o * stAnns = xn_Cls_Parser_parseAnnotations(self);
      xn_Cls_AstNode * st = xn_Cls_Parser_parseStmt(self);
      xn_Cls_Parser_attachAnnotations(self, st, stAnns);
      xn_Cls_AstNode_add(block, st);
    }
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
  if ((xn_Cls_Parser_atAnnotationStart(self) && (!xn_Cls_Parser_atAnnotationDecl(self)))) {
    xn_Cls_AstNode * use = xn_Cls_Parser_parseAnnotationUse(self);
    xn_Cls_AstNode * n = xn_Cls_AstNode_new(rt_string_from_c("AnnotatedExpr"), rt_string_from_c(""), use->line, use->col);
    xn_Cls_AstNode_add(n, use);
    xn_Cls_AstNode_add(n, xn_Cls_Parser_parseExpr(self));
    return n;
  }
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
      xn_arr_o * parms = xn_Cls_Parser_parseAnnotations(self);
      rt_string * pt = xn_Cls_Parser_parseType(self);
      if ((!xn_Cls_Parser_kind(self, rt_string_from_c("ident")))) {
        xn_Cls_Parser_fail(self, rt_string_from_c("expected lambda parameter name"));
        break;
      }
      xn_Cls_Token * pn = xn_Cls_Parser_advance(self);
      xn_Cls_AstNode * prm = xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_concat(pt, rt_string_from_c(" ")), pn->text), pn->line, pn->col);
      xn_Cls_Parser_attachAnnotations(self, prm, parms);
      xn_Cls_AstNode_add(n, prm);
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
  if (xn_Cls_Parser_kind(self, rt_string_from_c("error"))) {
    xn_Cls_Parser_fail(self, t->text);
    return xn_Cls_Parser_node(self, rt_string_from_c("error"), t->text, t);
  }
  if (xn_Cls_Parser_kind(self, rt_string_from_c("int"))) {
    xn_Cls_Parser_advance(self);
    return xn_Cls_Parser_node(self, rt_string_from_c("Int"), t->text, t);
  }
  if (xn_Cls_Parser_kind(self, rt_string_from_c("long"))) {
    xn_Cls_Parser_advance(self);
    return xn_Cls_Parser_node(self, rt_string_from_c("Long"), t->text, t);
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
        xn_Cls_AstNode * call = xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), t->line, t->col);
        if (xn_str_eq(n->kind, rt_string_from_c("Member"))) {
          call = xn_Cls_Parser_node(self, rt_string_from_c("MethodCall"), n->text, t);
          xn_Cls_AstNode_add(call, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
        }
        else {
          call = xn_Cls_Parser_node(self, rt_string_from_c("GenericCall"), n->text, t);
        }
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
  xn_arr_s * usedMethodTypes;
  xn_arr_s * usedMethodNames;
  xn_arr_s * wildcardMethods;
  xn_arr_s * gmClasses;
  xn_arr_s * gmMethods;
  xn_arr_i * gmStatic;
};

static const rt_type RT_TYPE_XN_Mono = { "Mono", sizeof(xn_Cls_Mono), NULL, NULL };

static xn_Cls_Mono *xn_Cls_Mono_new(xn_Cls_AstNode * p) {
  xn_Cls_Mono *xn_obj = (xn_Cls_Mono *)rt_gc_new(&RT_TYPE_XN_Mono);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_Mono) - sizeof(rt_header));
  xn_obj->program = 0;
  xn_obj->scopeNames = xn_arr_s_new(4);
  xn_obj->scopeTypes = xn_arr_s_new(4);
  xn_obj->usedMethodTypes = xn_arr_s_new(4);
  xn_obj->usedMethodNames = xn_arr_s_new(4);
  xn_obj->wildcardMethods = xn_arr_s_new(4);
  xn_obj->gmClasses = xn_arr_s_new(4);
  xn_obj->gmMethods = xn_arr_s_new(4);
  xn_obj->gmStatic = xn_arr_i_new(4);
  xn_Cls_Mono *self = xn_obj;
  self->program = p;
  self->scopeNames = xn_arr_s_new(0);
  self->scopeTypes = xn_arr_s_new(0);
  self->usedMethodTypes = xn_arr_s_new(0);
  self->usedMethodNames = xn_arr_s_new(0);
  self->wildcardMethods = xn_arr_s_new(0);
  self->gmClasses = xn_arr_s_new(0);
  self->gmMethods = xn_arr_s_new(0);
  self->gmStatic = xn_arr_i_new(0);
  return xn_obj;
}

static int xn_Cls_Mono_isGenericMethod(xn_Cls_Mono *self, rt_string * className, rt_string * methodName);
static int xn_Cls_Mono_isGenericMethodStatic(xn_Cls_Mono *self, rt_string * className, rt_string * methodName);
static int xn_Cls_Mono_hasTypeParams(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static xn_arr_s * xn_Cls_Mono_typeParams(xn_Cls_Mono *self, xn_Cls_AstNode * fn);
static int xn_Cls_Mono_hasGenericSyntax(xn_Cls_Mono *self, rt_string * ty);
static rt_string * xn_Cls_Mono_genericBase(xn_Cls_Mono *self, rt_string * ty);
static xn_arr_s * xn_Cls_Mono_genericArgsOf(xn_Cls_Mono *self, rt_string * ty);
static rt_string * xn_Cls_Mono_joinTypeArgs(xn_Cls_Mono *self, xn_arr_s * args);
static rt_string * xn_Cls_Mono_instanceName(xn_Cls_Mono *self, rt_string * cname, xn_arr_s * args);
static int xn_Cls_Mono_identChar(xn_Cls_Mono *self, rt_string * c);
static rt_string * xn_Cls_Mono_subst(xn_Cls_Mono *self, rt_string * text, rt_string * from, rt_string * to);
static rt_string * xn_Cls_Mono_substAll(xn_Cls_Mono *self, rt_string * text, xn_arr_s * names, xn_arr_s * args);
static rt_string * xn_Cls_Mono_mangle(xn_Cls_Mono *self, rt_string * ty);
static int xn_Cls_Mono_isDataEnum(xn_Cls_Mono *self, rt_string * name);
static xn_Cls_AstNode * xn_Cls_Mono_findClass(xn_Cls_Mono *self, rt_string * name);
static xn_Cls_AstNode * xn_Cls_Mono_findGenericClass(xn_Cls_Mono *self, rt_string * name);
static xn_arr_s * xn_Cls_Mono_splitArgs(xn_Cls_Mono *self, rt_string * text);
static rt_string * xn_Cls_Mono_retTypeText(xn_Cls_Mono *self, xn_Cls_AstNode * m);
static int xn_Cls_Mono_safeInstanceMethod(xn_Cls_Mono *self, rt_string * name);
static int xn_Cls_Mono_methodRecursive(xn_Cls_Mono *self, xn_Cls_AstNode * m, rt_string * base);
static rt_string * xn_Cls_Mono_instantiateClass(xn_Cls_Mono *self, rt_string * cname, xn_arr_s * args);
static void xn_Cls_Mono_instantiateNestedTypes(xn_Cls_Mono *self, xn_Cls_AstNode * cls);
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
static void xn_Cls_Mono_collectDeclTypes(xn_Cls_Mono *self, xn_Cls_AstNode * n, xn_arr_s * names, xn_arr_s * types);
static rt_string * xn_Cls_Mono_declaredType(xn_Cls_Mono *self, xn_arr_s * names, xn_arr_s * types, rt_string * name);
static int xn_Cls_Mono_sameClassType(xn_Cls_Mono *self, rt_string * ty, xn_Cls_AstNode * cls);
static void xn_Cls_Mono_collectClassCalls(xn_Cls_Mono *self, xn_Cls_AstNode * n, xn_Cls_AstNode * cls, xn_arr_s * names, xn_arr_s * types, xn_arr_s * out);
static int xn_Cls_Mono_listHas(xn_Cls_Mono *self, xn_arr_s * items, rt_string * value);
static rt_string * xn_Cls_Mono_mangledTypeName(xn_Cls_Mono *self, rt_string * ty);
static xn_arr_s * xn_Cls_Mono_reachableMethods(xn_Cls_Mono *self, xn_Cls_AstNode * cls, rt_string * iname, rt_string * sname);
static int xn_Cls_Mono_methodIsStatic(xn_Cls_Mono *self, xn_Cls_AstNode * m);
static void xn_Cls_Mono_collectUsedIn(xn_Cls_Mono *self, xn_Cls_AstNode * fn);
static void xn_Cls_Mono_scanUsed(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static void xn_Cls_Mono_collectUsedMethods(xn_Cls_Mono *self);
static rt_string * xn_Cls_Mono_methodReturnType(xn_Cls_Mono *self, rt_string * recvType, rt_string * mth);
static rt_string * xn_Cls_Mono_simpleExprType(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Mono_inferLambdaReturn(xn_Cls_Mono *self, xn_Cls_AstNode * lambda);
static int xn_Cls_Mono_inferTypePattern(xn_Cls_Mono *self, rt_string * pattern, rt_string * actual, xn_arr_s * names, xn_arr_s * inferred);
static rt_string * xn_Cls_Mono_angleFromMangled(xn_Cls_Mono *self, rt_string * ty);
static rt_string * xn_Cls_Mono_typeArgsFor(xn_Cls_Mono *self, xn_Cls_AstNode * call);
static xn_Cls_AstNode * xn_Cls_Mono_walk(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static xn_Cls_AstNode * xn_Cls_Mono_cloneAst(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static int xn_Cls_Mono_hasMember(xn_Cls_Mono *self, xn_Cls_AstNode * cls, xn_Cls_AstNode * member);
static void xn_Cls_Mono_flattenClass(xn_Cls_Mono *self, xn_Cls_AstNode * cls);
static rt_string * xn_Cls_Mono_gmName(xn_Cls_Mono *self, rt_string * className, rt_string * methodName);
static xn_Cls_AstNode * xn_Cls_Mono_replaceSelf(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static void xn_Cls_Mono_desugarGenericMethods(xn_Cls_Mono *self);
static xn_Cls_AstNode * xn_Cls_Mono_rewriteGenericMethodCall(xn_Cls_Mono *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_Mono_firstTypeToken(xn_Cls_Mono *self, rt_string * text);
static xn_Cls_AstNode * xn_Cls_Mono_inferGenericStaticCall(xn_Cls_Mono *self, xn_Cls_AstNode * n, rt_string * expected);
static int xn_Cls_Mono_inferGenericStaticCalls(xn_Cls_Mono *self, xn_Cls_AstNode * n, rt_string * expected, rt_string * curRet);
static xn_Cls_AstNode * xn_Cls_Mono_run(xn_Cls_Mono *self);

static int xn_Cls_Mono_isGenericMethod(xn_Cls_Mono *self, rt_string * className, rt_string * methodName) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->gmClasses->len))) {
    if ((xn_str_eq(xn_arr_s_get(self->gmClasses, i), className) && xn_str_eq(xn_arr_s_get(self->gmMethods, i), methodName))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int xn_Cls_Mono_isGenericMethodStatic(xn_Cls_Mono *self, rt_string * className, rt_string * methodName) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->gmClasses->len))) {
    if ((xn_str_eq(xn_arr_s_get(self->gmClasses, i), className) && xn_str_eq(xn_arr_s_get(self->gmMethods, i), methodName))) {
      return (xn_arr_i_get(self->gmStatic, i) != 0);
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

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

static int xn_Cls_Mono_hasGenericSyntax(xn_Cls_Mono *self, rt_string * ty) {
  return ((xn_str_indexof(ty, rt_string_from_c("<")) > 0) && xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 1)), 1), rt_string_from_c(">")));
}

static rt_string * xn_Cls_Mono_genericBase(xn_Cls_Mono *self, rt_string * ty) {
  int64_t p = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("<")));
  if ((p > 0)) {
    return xn_str_substr(ty, 0, p);
  }
  return ty;
}

static xn_arr_s * xn_Cls_Mono_genericArgsOf(xn_Cls_Mono *self, rt_string * ty) {
  int64_t p = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("<")));
  if (((p <= 0) || (!xn_str_eq(xn_str_substr(ty, xn_int_wrap((((int64_t)ty->len) - 1)), 1), rt_string_from_c(">"))))) {
    xn_arr_s *empty = xn_arr_s_new(0);
    return empty;
  }
  return xn_splitTop(xn_str_substr(ty, xn_int_wrap((p + 1)), xn_int_wrap((xn_int_wrap((((int64_t)ty->len) - p)) - 2))));
}

static rt_string * xn_Cls_Mono_joinTypeArgs(xn_Cls_Mono *self, xn_arr_s * args) {
  rt_string * out = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)args->len))) {
    if ((!xn_str_eq(out, rt_string_from_c("")))) {
      out = xn_concat(out, rt_string_from_c(","));
    }
    out = xn_concat(out, xn_str_trim(xn_arr_s_get(args, i)));
    i = xn_int_wrap((i + 1));
  }
  return out;
}

static rt_string * xn_Cls_Mono_instanceName(xn_Cls_Mono *self, rt_string * cname, xn_arr_s * args) {
  return xn_concat(xn_concat(xn_concat(cname, rt_string_from_c("<")), xn_Cls_Mono_joinTypeArgs(self, args)), rt_string_from_c(">"));
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
    if ((xn_str_eq(c, rt_string_from_c(" ")) || xn_str_eq(c, rt_string_from_c("\t")))) {
      i = xn_int_wrap((i + 1));
      continue;
    }
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

static xn_Cls_AstNode * xn_Cls_Mono_findGenericClass(xn_Cls_Mono *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) && xn_str_eq(n->text, name)) && xn_Cls_Mono_hasTypeParams(self, n))) {
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

static rt_string * xn_Cls_Mono_retTypeText(xn_Cls_Mono *self, xn_Cls_AstNode * m) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)m->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(m->kids, i))->kind, rt_string_from_c("Ret"))) {
      return ((xn_Cls_AstNode *)xn_arr_o_get(m->kids, i))->text;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Unit");
}

static int xn_Cls_Mono_safeInstanceMethod(xn_Cls_Mono *self, rt_string * name) {
  return (xn_str_eq(name, rt_string_from_c("length")) || xn_str_eq(name, rt_string_from_c("get")));
}

static int xn_Cls_Mono_methodRecursive(xn_Cls_Mono *self, xn_Cls_AstNode * m, rt_string * base) {
  rt_string * rt = xn_Cls_Mono_retTypeText(self, m);
  return (xn_str_eq(rt, base) || (xn_str_indexof(rt, xn_concat(base, rt_string_from_c("<"))) >= 0));
}

static rt_string * xn_Cls_Mono_instantiateClass(xn_Cls_Mono *self, rt_string * cname, xn_arr_s * args) {
  xn_Cls_AstNode * cls = xn_Cls_Mono_findGenericClass(self, cname);
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
    suffix = xn_concat(suffix, xn_Cls_Mono_mangle(self, xn_str_trim(xn_arr_s_get(args, i))));
    i = xn_int_wrap((i + 1));
  }
  rt_string * sname = xn_concat(xn_concat(cname, rt_string_from_c("__")), suffix);
  if ((!xn_str_eq(xn_Cls_Mono_findClass(self, sname)->kind, rt_string_from_c("None")))) {
    return sname;
  }
  rt_string * iname = xn_Cls_Mono_instanceName(self, cname, args);
  xn_Cls_AstNode * clone = xn_Cls_AstNode_new(cls->kind, sname, cls->line, cls->col);
  clone->isFinalField = cls->isFinalField;
  clone->packageName = cls->packageName;
  clone->resolvedAnnotationName = cls->resolvedAnnotationName;
  clone->annotationError = cls->annotationError;
  clone->typeAnnotations = cls->typeAnnotations;
  i = 0;
  while ((i < ((int64_t)cls->annotations->len))) {
    xn_Cls_AstNode_annotate(clone, ((xn_Cls_AstNode *)xn_arr_o_get(cls->annotations, i)));
    i = xn_int_wrap((i + 1));
  }
  xn_arr_s * reachable = xn_Cls_Mono_reachableMethods(self, cls, iname, sname);
  i = 0;
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * member = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    int skip = 0;
    if (xn_str_eq(member->kind, rt_string_from_c("TypeParams"))) {
      skip = 1;
    }
    if ((((xn_str_eq(member->kind, rt_string_from_c("Method")) && (!xn_Cls_Mono_methodIsStatic(self, member))) && (!xn_Cls_Mono_listHas(self, reachable, member->text))) && (!(xn_str_eq(cname, rt_string_from_c("Seq")) && xn_Cls_Mono_safeInstanceMethod(self, member->text))))) {
      skip = 1;
    }
    if ((!skip)) {
      xn_Cls_AstNode_add(clone, xn_Cls_Mono_cloneSubst(self, member, names, args));
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_Mono_instantiateNestedTypes(self, clone);
  xn_Cls_AstNode_add(self->program, clone);
  return sname;
}

static void xn_Cls_Mono_instantiateNestedTypes(xn_Cls_Mono *self, xn_Cls_AstNode * cls) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (((xn_str_eq(k->kind, rt_string_from_c("Field")) || xn_str_eq(k->kind, rt_string_from_c("Base"))) || xn_str_eq(k->kind, rt_string_from_c("Implements")))) {
      k->text = xn_Cls_Mono_rewriteType(self, k->text);
    }
    i = xn_int_wrap((i + 1));
  }
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
    int64_t bestP = xn_int_wrap(xn_int_wrap(-(1)));
    xn_Cls_AstNode * bestCls = xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), 1, 1);
    int64_t ci = xn_int_wrap(0);
    while ((ci < ((int64_t)self->program->kids->len))) {
      xn_Cls_AstNode * cls = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, ci));
      if ((((xn_str_eq(cls->kind, rt_string_from_c("Class")) || xn_str_eq(cls->kind, rt_string_from_c("Struct"))) && xn_Cls_Mono_hasTypeParams(self, cls)) && (((int64_t)xn_Cls_Mono_typeParams(self, cls)->len) > 0))) {
        int64_t p = xn_int_wrap(xn_str_indexof(res, xn_concat(cls->text, rt_string_from_c("<"))));
        if (((p >= 0) && ((bestP < 0) || (p < bestP)))) {
          bestP = p;
          bestCls = cls;
        }
      }
      ci = xn_int_wrap((ci + 1));
    }
    if (((bestP >= 0) && (!xn_str_eq(bestCls->kind, rt_string_from_c("None"))))) {
      rt_string * needle = xn_concat(bestCls->text, rt_string_from_c("<"));
      int64_t depth = xn_int_wrap(0);
      int64_t j = xn_int_wrap(xn_int_wrap((bestP + ((int64_t)bestCls->text->len))));
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
      if ((end > bestP)) {
        rt_string * inner = xn_str_substr(res, xn_int_wrap((bestP + ((int64_t)needle->len))), xn_int_wrap((xn_int_wrap((end - bestP)) - ((int64_t)needle->len))));
        rt_string * sname = xn_Cls_Mono_instantiateClass(self, bestCls->text, xn_Cls_Mono_splitArgs(self, inner));
        res = xn_concat(xn_concat(xn_str_substr(res, 0, bestP), sname), xn_str_substr(res, xn_int_wrap((end + 1)), xn_int_wrap((xn_int_wrap((((int64_t)res->len) - end)) - 1))));
        changed = 1;
      }
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
  c->isFinalField = n->isFinalField;
  c->packageName = n->packageName;
  c->resolvedAnnotationName = n->resolvedAnnotationName;
  c->annotationError = n->annotationError;
  c->typeAnnotations = n->typeAnnotations;
  int64_t ai = xn_int_wrap(0);
  while ((ai < ((int64_t)n->annotations->len))) {
    xn_Cls_AstNode_annotate(c, ((xn_Cls_AstNode *)xn_arr_o_get(n->annotations, ai)));
    ai = xn_int_wrap((ai + 1));
  }
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
  clone->isFinalField = fn->isFinalField;
  clone->packageName = fn->packageName;
  clone->resolvedAnnotationName = fn->resolvedAnnotationName;
  clone->annotationError = fn->annotationError;
  clone->typeAnnotations = fn->typeAnnotations;
  i = 0;
  while ((i < ((int64_t)fn->annotations->len))) {
    xn_Cls_AstNode_annotate(clone, ((xn_Cls_AstNode *)xn_arr_o_get(fn->annotations, i)));
    i = xn_int_wrap((i + 1));
  }
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
  if (xn_str_eq(n->kind, rt_string_from_c("Long"))) {
    return rt_string_from_c("Long");
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

static void xn_Cls_Mono_collectDeclTypes(xn_Cls_Mono *self, xn_Cls_AstNode * n, xn_arr_s * names, xn_arr_s * types) {
  if (((xn_str_eq(n->kind, rt_string_from_c("Param")) || xn_str_eq(n->kind, rt_string_from_c("Local"))) || xn_str_eq(n->kind, rt_string_from_c("Field")))) {
    rt_string * text = n->text;
    int64_t splitAt = xn_int_wrap(xn_int_wrap(-(1)));
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)text->len))) {
      if (xn_str_eq(xn_str_substr(text, i, 1), rt_string_from_c(" "))) {
        splitAt = i;
      }
      i = xn_int_wrap((i + 1));
    }
    if (((splitAt > 0) && (xn_int_wrap((splitAt + 1)) < ((int64_t)text->len)))) {
      xn_arr_s_push(names, xn_str_substr(text, xn_int_wrap((splitAt + 1)), xn_int_wrap((xn_int_wrap((((int64_t)text->len) - splitAt)) - 1))));
      xn_arr_s_push(types, xn_str_substr(text, 0, splitAt));
    }
  }
  int64_t j = xn_int_wrap(0);
  while ((j < ((int64_t)n->kids->len))) {
    xn_Cls_Mono_collectDeclTypes(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j)), names, types);
    j = xn_int_wrap((j + 1));
  }
}

static rt_string * xn_Cls_Mono_declaredType(xn_Cls_Mono *self, xn_arr_s * names, xn_arr_s * types, rt_string * name) {
  int64_t i = xn_int_wrap(xn_int_wrap((((int64_t)names->len) - 1)));
  while ((i >= 0)) {
    if (xn_str_eq(xn_arr_s_get(names, i), name)) {
      return xn_arr_s_get(types, i);
    }
    i = xn_int_wrap((i - 1));
  }
  return rt_string_from_c("");
}

static int xn_Cls_Mono_sameClassType(xn_Cls_Mono *self, rt_string * ty, xn_Cls_AstNode * cls) {
  return (xn_str_eq(ty, cls->text) || xn_str_startswith(ty, xn_concat(cls->text, rt_string_from_c("<"))));
}

static void xn_Cls_Mono_collectClassCalls(xn_Cls_Mono *self, xn_Cls_AstNode * n, xn_Cls_AstNode * cls, xn_arr_s * names, xn_arr_s * types, xn_arr_s * out) {
  if ((xn_str_eq(n->kind, rt_string_from_c("MethodCall")) && (((int64_t)n->kids->len) > 0))) {
    xn_Cls_AstNode * recv = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
    if (xn_str_eq(recv->kind, rt_string_from_c("Name"))) {
      rt_string * rt = rt_string_from_c("");
      if (xn_str_eq(recv->text, rt_string_from_c("self"))) {
        rt = cls->text;
      }
      else {
        rt = xn_Cls_Mono_declaredType(self, names, types, recv->text);
      }
      if ((xn_Cls_Mono_sameClassType(self, rt, cls) && (!xn_Cls_Mono_listHas(self, out, n->text)))) {
        xn_arr_s_push(out, n->text);
      }
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
    int64_t dot = xn_int_wrap(xn_lastDot(n->text));
    if ((dot > 0)) {
      rt_string * recv = xn_str_substr(n->text, 0, dot);
      rt_string * mth = xn_str_substr(n->text, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)n->text->len) - dot)) - 1)));
      rt_string * rt = rt_string_from_c("");
      if (xn_str_eq(recv, rt_string_from_c("self"))) {
        rt = cls->text;
      }
      else {
        rt = xn_Cls_Mono_declaredType(self, names, types, recv);
      }
      if ((xn_Cls_Mono_sameClassType(self, rt, cls) && (!xn_Cls_Mono_listHas(self, out, mth)))) {
        xn_arr_s_push(out, mth);
      }
    }
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_Mono_collectClassCalls(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), cls, names, types, out);
    i = xn_int_wrap((i + 1));
  }
}

static int xn_Cls_Mono_listHas(xn_Cls_Mono *self, xn_arr_s * items, rt_string * value) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)items->len))) {
    if (xn_str_eq(xn_arr_s_get(items, i), value)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static rt_string * xn_Cls_Mono_mangledTypeName(xn_Cls_Mono *self, rt_string * ty) {
  if ((!xn_Cls_Mono_hasGenericSyntax(self, ty))) {
    return ty;
  }
  rt_string * base = xn_Cls_Mono_genericBase(self, ty);
  xn_arr_s * args = xn_Cls_Mono_genericArgsOf(self, ty);
  rt_string * suffix = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)args->len))) {
    if ((!xn_str_eq(suffix, rt_string_from_c("")))) {
      suffix = xn_concat(suffix, rt_string_from_c("_"));
    }
    suffix = xn_concat(suffix, xn_Cls_Mono_mangle(self, xn_str_trim(xn_arr_s_get(args, i))));
    i = xn_int_wrap((i + 1));
  }
  return xn_concat(xn_concat(base, rt_string_from_c("__")), suffix);
}

static xn_arr_s * xn_Cls_Mono_reachableMethods(xn_Cls_Mono *self, xn_Cls_AstNode * cls, rt_string * iname, rt_string * sname) {
  xn_arr_s *out = xn_arr_s_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->usedMethodTypes->len))) {
    rt_string * usedType = xn_arr_s_get(self->usedMethodTypes, i);
    if (((xn_str_eq(usedType, iname) || xn_str_eq(xn_Cls_Mono_mangledTypeName(self, usedType), sname)) && (!xn_Cls_Mono_listHas(self, out, xn_arr_s_get(self->usedMethodNames, i))))) {
      xn_arr_s_push(out, xn_arr_s_get(self->usedMethodNames, i));
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)cls->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i))->kind, rt_string_from_c("Ctor"))) {
      xn_arr_s *cnames = xn_arr_s_new(0);
      xn_arr_s *ctypes = xn_arr_s_new(0);
      xn_Cls_Mono_collectDeclTypes(self, ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i)), cnames, ctypes);
      xn_Cls_Mono_collectClassCalls(self, ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i)), cls, cnames, ctypes, out);
    }
    i = xn_int_wrap((i + 1));
  }
  int changed = 1;
  while (changed) {
    changed = 0;
    i = 0;
    while ((i < ((int64_t)cls->kids->len))) {
      xn_Cls_AstNode * m = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
      if ((xn_str_eq(m->kind, rt_string_from_c("Method")) && xn_Cls_Mono_listHas(self, out, m->text))) {
        xn_arr_s *mnames = xn_arr_s_new(0);
        xn_arr_s *mtypes = xn_arr_s_new(0);
        xn_Cls_Mono_collectDeclTypes(self, m, mnames, mtypes);
        xn_arr_s *calls = xn_arr_s_new(0);
        xn_Cls_Mono_collectClassCalls(self, m, cls, mnames, mtypes, calls);
        int64_t ci = xn_int_wrap(0);
        while ((ci < ((int64_t)calls->len))) {
          if ((!xn_Cls_Mono_listHas(self, out, xn_arr_s_get(calls, ci)))) {
            xn_arr_s_push(out, xn_arr_s_get(calls, ci));
            changed = 1;
          }
          ci = xn_int_wrap((ci + 1));
        }
      }
      i = xn_int_wrap((i + 1));
    }
  }
  return out;
}

static int xn_Cls_Mono_methodIsStatic(xn_Cls_Mono *self, xn_Cls_AstNode * m) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)m->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(m->kids, i))->kind, rt_string_from_c("Static"))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_Cls_Mono_collectUsedIn(xn_Cls_Mono *self, xn_Cls_AstNode * fn) {
  int64_t mark = xn_int_wrap(((int64_t)self->scopeNames->len));
  xn_Cls_Mono_collectScope(self, fn);
  xn_Cls_Mono_scanUsed(self, fn);
  while ((((int64_t)self->scopeNames->len) > mark)) {
    xn_arr_s_remove(self->scopeNames, xn_int_wrap((((int64_t)self->scopeNames->len) - 1)));
    xn_arr_s_remove(self->scopeTypes, xn_int_wrap((((int64_t)self->scopeTypes->len) - 1)));
  }
}

static void xn_Cls_Mono_scanUsed(xn_Cls_Mono *self, xn_Cls_AstNode * n) {
  if ((xn_str_eq(n->kind, rt_string_from_c("MethodCall")) && (((int64_t)n->kids->len) > 0))) {
    rt_string * recv = xn_Cls_Mono_simpleExprType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if ((!xn_str_eq(recv, rt_string_from_c("Any")))) {
      xn_arr_s_push(self->usedMethodTypes, recv);
      xn_arr_s_push(self->usedMethodNames, n->text);
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
    int64_t dot = xn_int_wrap(xn_lastDot(n->text));
    if ((dot > 0)) {
      rt_string * recv = xn_str_substr(n->text, 0, dot);
      rt_string * mth = xn_str_substr(n->text, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)n->text->len) - dot)) - 1)));
      xn_Cls_AstNode * recvNode = xn_Cls_AstNode_new(rt_string_from_c("Name"), recv, n->line, n->col);
      rt_string * rt = xn_Cls_Mono_simpleExprType(self, recvNode);
      if ((!xn_str_eq(rt, rt_string_from_c("Any")))) {
        xn_arr_s_push(self->usedMethodTypes, rt);
        xn_arr_s_push(self->usedMethodNames, mth);
      }
    }
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_Mono_scanUsed(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)));
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_Mono_collectUsedMethods(xn_Cls_Mono *self) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("Func"))) {
      xn_Cls_Mono_collectUsedIn(self, n);
    }
    if (((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || xn_str_eq(n->kind, rt_string_from_c("Enum")))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j));
        if ((xn_str_eq(k->kind, rt_string_from_c("Method")) || xn_str_eq(k->kind, rt_string_from_c("Ctor")))) {
          xn_Cls_Mono_collectUsedIn(self, k);
        }
        j = xn_int_wrap((j + 1));
      }
    }
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
    if (xn_str_eq(mth, rt_string_from_c("copy"))) {
      return recvType;
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
  if (xn_Cls_Mono_hasGenericSyntax(self, recvType)) {
    rt_string * base = xn_Cls_Mono_genericBase(self, recvType);
    xn_Cls_AstNode * gc = xn_Cls_Mono_findGenericClass(self, base);
    if ((!xn_str_eq(gc->kind, rt_string_from_c("None")))) {
      xn_arr_s * gnames = xn_Cls_Mono_typeParams(self, gc);
      xn_arr_s * gargs = xn_Cls_Mono_genericArgsOf(self, recvType);
      if ((((int64_t)gnames->len) == ((int64_t)gargs->len))) {
        int64_t gi = xn_int_wrap(0);
        while ((gi < ((int64_t)gc->kids->len))) {
          xn_Cls_AstNode * gm = ((xn_Cls_AstNode *)xn_arr_o_get(gc->kids, gi));
          if ((xn_str_eq(gm->kind, rt_string_from_c("Method")) && xn_str_eq(gm->text, mth))) {
            int64_t gr = xn_int_wrap(0);
            while ((gr < ((int64_t)gm->kids->len))) {
              if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(gm->kids, gr))->kind, rt_string_from_c("Ret"))) {
                return xn_Cls_Mono_substAll(self, ((xn_Cls_AstNode *)xn_arr_o_get(gm->kids, gr))->text, gnames, gargs);
              }
              gr = xn_int_wrap((gr + 1));
            }
          }
          gi = xn_int_wrap((gi + 1));
        }
      }
    }
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
    if ((((xn_str_eq(lt, rt_string_from_c("Double")) || xn_str_eq(rt, rt_string_from_c("Double"))) || xn_str_eq(lt, rt_string_from_c("Float"))) || xn_str_eq(rt, rt_string_from_c("Float")))) {
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
    if ((((int64_t)n->kids->len) > 0)) {
      rt_string * recvType = xn_Cls_Mono_simpleExprType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      if ((!xn_str_eq(recvType, rt_string_from_c("Any")))) {
        rt_string * inferred = xn_Cls_Mono_methodReturnType(self, recvType, n->text);
        if ((!xn_str_eq(inferred, rt_string_from_c("Any")))) {
          return inferred;
        }
      }
    }
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
  if (((((int64_t)pattern->len) > 1) && xn_str_eq(xn_str_substr(pattern, xn_int_wrap((((int64_t)pattern->len) - 1)), 1), rt_string_from_c("?")))) {
    return xn_Cls_Mono_inferTypePattern(self, xn_str_substr(pattern, 0, xn_int_wrap((((int64_t)pattern->len) - 1))), actual, names, inferred);
  }
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
  int64_t pparen = xn_int_wrap(xn_str_indexof(pattern, rt_string_from_c("(")));
  int64_t aparen = xn_int_wrap(xn_str_indexof(actual, rt_string_from_c("(")));
  if (((pparen > 0) && (aparen > 0))) {
    rt_string * pret = xn_str_trim(xn_str_substr(pattern, 0, pparen));
    rt_string * aret = xn_str_trim(xn_str_substr(actual, 0, aparen));
    if ((!xn_Cls_Mono_inferTypePattern(self, pret, aret, names, inferred))) {
      return 0;
    }
    rt_string * pin = xn_str_substr(pattern, xn_int_wrap((pparen + 1)), xn_int_wrap((xn_int_wrap((((int64_t)pattern->len) - pparen)) - 2)));
    rt_string * ain = xn_str_substr(actual, xn_int_wrap((aparen + 1)), xn_int_wrap((xn_int_wrap((((int64_t)actual->len) - aparen)) - 2)));
    xn_arr_s * pps = xn_splitTop(pin);
    xn_arr_s * aps = xn_splitTop(ain);
    if ((((int64_t)pps->len) != ((int64_t)aps->len))) {
      return 0;
    }
    int64_t fi = xn_int_wrap(0);
    while ((fi < ((int64_t)pps->len))) {
      if ((!xn_Cls_Mono_inferTypePattern(self, xn_str_trim(xn_arr_s_get(pps, fi)), xn_str_trim(xn_arr_s_get(aps, fi)), names, inferred))) {
        return 0;
      }
      fi = xn_int_wrap((fi + 1));
    }
    return 1;
  }
  int64_t gp = xn_int_wrap(xn_str_indexof(pattern, rt_string_from_c("<")));
  if (((gp > 0) && xn_str_startswith(actual, xn_concat(xn_str_substr(pattern, 0, gp), rt_string_from_c("__"))))) {
    rt_string * suffix = xn_str_substr(actual, xn_int_wrap((gp + 2)), xn_int_wrap((xn_int_wrap((((int64_t)actual->len) - gp)) - 2)));
    xn_arr_s * aa = xn_str_split(suffix, rt_string_from_c("_"));
    xn_arr_s * pp = xn_splitTop(xn_str_substr(pattern, xn_int_wrap((gp + 1)), xn_int_wrap((xn_int_wrap((((int64_t)pattern->len) - gp)) - 2))));
    if ((((int64_t)pp->len) != ((int64_t)aa->len))) {
      return 0;
    }
    int64_t gi = xn_int_wrap(0);
    while ((gi < ((int64_t)pp->len))) {
      if ((!xn_Cls_Mono_inferTypePattern(self, xn_str_trim(xn_arr_s_get(pp, gi)), xn_str_trim(xn_arr_s_get(aa, gi)), names, inferred))) {
        return 0;
      }
      gi = xn_int_wrap((gi + 1));
    }
    return 1;
  }
  int64_t ga = xn_int_wrap(xn_str_indexof(actual, rt_string_from_c("<")));
  if ((((((gp > 0) && (ga > 0)) && xn_str_eq(xn_str_substr(pattern, xn_int_wrap((((int64_t)pattern->len) - 1)), 1), rt_string_from_c(">"))) && xn_str_eq(xn_str_substr(actual, xn_int_wrap((((int64_t)actual->len) - 1)), 1), rt_string_from_c(">"))) && xn_str_eq(xn_str_substr(pattern, 0, gp), xn_str_substr(actual, 0, ga)))) {
    xn_arr_s * pp = xn_splitTop(xn_str_substr(pattern, xn_int_wrap((gp + 1)), xn_int_wrap((xn_int_wrap((((int64_t)pattern->len) - gp)) - 2))));
    xn_arr_s * aa = xn_splitTop(xn_str_substr(actual, xn_int_wrap((ga + 1)), xn_int_wrap((xn_int_wrap((((int64_t)actual->len) - ga)) - 2))));
    if ((((int64_t)pp->len) != ((int64_t)aa->len))) {
      return 0;
    }
    int64_t gi = xn_int_wrap(0);
    while ((gi < ((int64_t)pp->len))) {
      if ((!xn_Cls_Mono_inferTypePattern(self, xn_str_trim(xn_arr_s_get(pp, gi)), xn_str_trim(xn_arr_s_get(aa, gi)), names, inferred))) {
        return 0;
      }
      gi = xn_int_wrap((gi + 1));
    }
    return 1;
  }
  return xn_str_eq(pattern, actual);
}

static rt_string * xn_Cls_Mono_angleFromMangled(xn_Cls_Mono *self, rt_string * ty) {
  int64_t u = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("__")));
  if ((u < 0)) {
    return ty;
  }
  rt_string * base = xn_str_substr(ty, 0, u);
  rt_string * rest = xn_str_substr(ty, xn_int_wrap((u + 2)), xn_int_wrap((xn_int_wrap((((int64_t)ty->len) - u)) - 2)));
  if (((((int64_t)rest->len) > 0) && xn_str_eq(xn_str_substr(rest, xn_int_wrap((((int64_t)rest->len) - 1)), 1), rt_string_from_c("_")))) {
    rest = xn_str_substr(rest, 0, xn_int_wrap((((int64_t)rest->len) - 1)));
  }
  if (xn_str_eq(rest, rt_string_from_c(""))) {
    return ty;
  }
  xn_arr_s * parts = xn_str_split(rest, rt_string_from_c("_"));
  rt_string * joined = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)parts->len))) {
    if ((!xn_str_eq(xn_arr_s_get(parts, i), rt_string_from_c("")))) {
      if ((!xn_str_eq(joined, rt_string_from_c("")))) {
        joined = xn_concat(joined, rt_string_from_c(","));
      }
      joined = xn_concat(joined, xn_arr_s_get(parts, i));
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_concat(xn_concat(xn_concat(base, rt_string_from_c("<")), joined), rt_string_from_c(">"));
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
    xn_arr_s_push(actual, xn_Cls_Mono_angleFromMangled(self, xn_Cls_Mono_argType(self, ((xn_Cls_AstNode *)xn_arr_o_get(call->kids, ai)))));
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
  if ((xn_str_eq(n->kind, rt_string_from_c("MethodCall")) || xn_str_eq(n->kind, rt_string_from_c("Call")))) {
    n = xn_Cls_Mono_rewriteGenericMethodCall(self, n);
  }
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
  c->isFinalField = n->isFinalField;
  c->packageName = n->packageName;
  c->resolvedAnnotationName = n->resolvedAnnotationName;
  c->annotationError = n->annotationError;
  c->typeAnnotations = n->typeAnnotations;
  int64_t ai = xn_int_wrap(0);
  while ((ai < ((int64_t)n->annotations->len))) {
    xn_Cls_AstNode_annotate(c, ((xn_Cls_AstNode *)xn_arr_o_get(n->annotations, ai)));
    ai = xn_int_wrap((ai + 1));
  }
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

static rt_string * xn_Cls_Mono_gmName(xn_Cls_Mono *self, rt_string * className, rt_string * methodName) {
  return xn_concat(xn_concat(xn_concat(rt_string_from_c("__gm_"), className), rt_string_from_c("_")), methodName);
}

static xn_Cls_AstNode * xn_Cls_Mono_replaceSelf(xn_Cls_Mono *self, xn_Cls_AstNode * n) {
  xn_Cls_AstNode * c = xn_Cls_AstNode_new(n->kind, n->text, n->line, n->col);
  c->isFinalField = n->isFinalField;
  c->packageName = n->packageName;
  c->resolvedAnnotationName = n->resolvedAnnotationName;
  c->annotationError = n->annotationError;
  c->typeAnnotations = n->typeAnnotations;
  if ((xn_str_eq(n->kind, rt_string_from_c("Name")) && xn_str_eq(n->text, rt_string_from_c("self")))) {
    c->text = rt_string_from_c("__self");
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Call")) && xn_str_startswith(n->text, rt_string_from_c("self.")))) {
    c->text = xn_concat(rt_string_from_c("__self."), xn_str_substr(n->text, 5, xn_int_wrap((((int64_t)n->text->len) - 5))));
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_AstNode_add(c, xn_Cls_Mono_replaceSelf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i))));
    i = xn_int_wrap((i + 1));
  }
  return c;
}

static void xn_Cls_Mono_desugarGenericMethods(xn_Cls_Mono *self) {
  int64_t ci = xn_int_wrap(0);
  while ((ci < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * cls = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, ci));
    if ((xn_str_eq(cls->kind, rt_string_from_c("Class")) || xn_str_eq(cls->kind, rt_string_from_c("Struct")))) {
      xn_arr_s * classParams = xn_Cls_Mono_typeParams(self, cls);
      xn_arr_i *removeAt = xn_arr_i_new(0);
      int64_t mi = xn_int_wrap(0);
      while ((mi < ((int64_t)cls->kids->len))) {
        xn_Cls_AstNode * m = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, mi));
        if ((xn_str_eq(m->kind, rt_string_from_c("Method")) && xn_Cls_Mono_hasTypeParams(self, m))) {
          xn_arr_s * methodParams = xn_Cls_Mono_typeParams(self, m);
          int isStatic = xn_Cls_Mono_methodIsStatic(self, m);
          xn_arr_s *combined = xn_arr_s_new(0);
          int64_t pi = xn_int_wrap(0);
          if ((!isStatic)) {
            while ((pi < ((int64_t)classParams->len))) {
              xn_arr_s_push(combined, xn_arr_s_get(classParams, pi));
              pi = xn_int_wrap((pi + 1));
            }
          }
          pi = 0;
          while ((pi < ((int64_t)methodParams->len))) {
            int found = 0;
            int64_t qi = xn_int_wrap(0);
            while ((qi < ((int64_t)combined->len))) {
              if (xn_str_eq(xn_arr_s_get(combined, qi), xn_arr_s_get(methodParams, pi))) {
                found = 1;
                break;
              }
              qi = xn_int_wrap((qi + 1));
            }
            if ((!found)) {
              xn_arr_s_push(combined, xn_arr_s_get(methodParams, pi));
            }
            pi = xn_int_wrap((pi + 1));
          }
          xn_Cls_AstNode * fn = xn_Cls_AstNode_new(rt_string_from_c("Func"), xn_Cls_Mono_gmName(self, cls->text, m->text), m->line, m->col);
          fn->packageName = cls->packageName;
          xn_Cls_AstNode * tp = xn_Cls_AstNode_new(rt_string_from_c("TypeParams"), rt_string_from_c(""), m->line, m->col);
          pi = 0;
          while ((pi < ((int64_t)combined->len))) {
            xn_Cls_AstNode_add(tp, xn_Cls_AstNode_new(rt_string_from_c("TypeParam"), xn_arr_s_get(combined, pi), m->line, m->col));
            pi = xn_int_wrap((pi + 1));
          }
          xn_Cls_AstNode_add(fn, tp);
          pi = 0;
          while ((pi < ((int64_t)m->kids->len))) {
            xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(m->kids, pi));
            if (xn_str_eq(k->kind, rt_string_from_c("Ret"))) {
              xn_Cls_AstNode_add(fn, xn_Cls_Mono_replaceSelf(self, k));
            }
            pi = xn_int_wrap((pi + 1));
          }
          if ((!isStatic)) {
            rt_string * recvType = cls->text;
            if ((((int64_t)classParams->len) > 0)) {
              recvType = xn_concat(xn_concat(xn_concat(cls->text, rt_string_from_c("<")), xn_Cls_Mono_joinTypeArgs(self, classParams)), rt_string_from_c(">"));
            }
            xn_Cls_AstNode_add(fn, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(recvType, rt_string_from_c(" __self")), m->line, m->col));
          }
          pi = 0;
          while ((pi < ((int64_t)m->kids->len))) {
            xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(m->kids, pi));
            if ((xn_str_eq(k->kind, rt_string_from_c("Param")) || xn_str_eq(k->kind, rt_string_from_c("Block")))) {
              xn_Cls_AstNode_add(fn, xn_Cls_Mono_replaceSelf(self, k));
            }
            pi = xn_int_wrap((pi + 1));
          }
          xn_Cls_AstNode_add(self->program, fn);
          xn_arr_s_push(self->gmClasses, cls->text);
          xn_arr_s_push(self->gmMethods, m->text);
          if (isStatic) {
            xn_arr_i_push(self->gmStatic, 1);
          }
          else {
            xn_arr_i_push(self->gmStatic, 0);
          }
          xn_arr_i_push(removeAt, mi);
        }
        mi = xn_int_wrap((mi + 1));
      }
      int64_t ri = xn_int_wrap(xn_int_wrap((((int64_t)removeAt->len) - 1)));
      while ((ri >= 0)) {
        xn_arr_o_remove(cls->kids, xn_arr_i_get(removeAt, ri));
        ri = xn_int_wrap((ri - 1));
      }
    }
    ci = xn_int_wrap((ci + 1));
  }
}

static xn_Cls_AstNode * xn_Cls_Mono_rewriteGenericMethodCall(xn_Cls_Mono *self, xn_Cls_AstNode * n) {
  rt_string * className = rt_string_from_c("");
  rt_string * classArgsText = rt_string_from_c("");
  xn_Cls_AstNode * recv = xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), n->line, n->col);
  int methodCall = xn_str_eq(n->kind, rt_string_from_c("MethodCall"));
  int receiverInKids = xn_str_eq(n->kind, rt_string_from_c("MethodCall"));
  if ((methodCall && (((int64_t)n->kids->len) > 0))) {
    recv = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
    if ((xn_str_eq(recv->kind, rt_string_from_c("Call")) || xn_str_eq(recv->kind, rt_string_from_c("MethodCall")))) {
      recv = xn_Cls_Mono_rewriteGenericMethodCall(self, recv);
      xn_Cls_AstNode_setKid(n, 0, recv);
    }
    rt_string * rt = xn_Cls_Mono_simpleExprType(self, recv);
    if ((!xn_str_eq(rt, rt_string_from_c("Any")))) {
      if ((xn_str_startswith(rt, rt_string_from_c("Box<")) || (xn_str_indexof(rt, rt_string_from_c("<")) > 0))) {
        classArgsText = xn_Cls_Mono_joinTypeArgs(self, xn_Cls_Mono_genericArgsOf(self, rt));
      }
      else {
        if ((xn_str_indexof(rt, rt_string_from_c("__")) > 0)) {
          classArgsText = xn_str_replace(xn_str_substr(rt, xn_int_wrap((xn_str_indexof(rt, rt_string_from_c("__")) + 2)), xn_int_wrap((xn_int_wrap((((int64_t)rt->len) - xn_str_indexof(rt, rt_string_from_c("__")))) - 2))), rt_string_from_c("_"), rt_string_from_c(","));
        }
      }
      className = xn_Cls_Mono_genericBase(self, rt);
      int64_t uu = xn_int_wrap(xn_str_indexof(className, rt_string_from_c("__")));
      if ((uu > 0)) {
        rt_string * baseCandidate = xn_str_substr(className, 0, uu);
        if (xn_Cls_Mono_isGenericMethod(self, baseCandidate, n->text)) {
          className = baseCandidate;
        }
      }
    }
    else {
      if ((xn_str_eq(recv->kind, rt_string_from_c("Name")) && (!xn_str_eq(xn_Cls_Mono_findClass(self, recv->text)->kind, rt_string_from_c("None"))))) {
        className = recv->text;
      }
    }
  }
  else {
    if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
      int64_t dot = xn_int_wrap(xn_lastDot(n->text));
      if ((dot > 0)) {
        rt_string * recvName = xn_str_substr(n->text, 0, dot);
        xn_Cls_AstNode * recvNode = xn_Cls_AstNode_new(rt_string_from_c("Name"), recvName, n->line, n->col);
        rt_string * rt = xn_Cls_Mono_simpleExprType(self, recvNode);
        if ((!xn_str_eq(rt, rt_string_from_c("Any")))) {
          className = xn_Cls_Mono_genericBase(self, rt);
          int64_t uu = xn_int_wrap(xn_str_indexof(className, rt_string_from_c("__")));
          if ((uu > 0)) {
            rt_string * baseCandidate = xn_str_substr(className, 0, uu);
            if (xn_Cls_Mono_isGenericMethod(self, baseCandidate, xn_str_substr(n->text, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)n->text->len) - dot)) - 1))))) {
              className = baseCandidate;
            }
          }
          methodCall = 1;
          recv = recvNode;
        }
        else {
          className = recvName;
        }
      }
    }
  }
  if (xn_str_eq(className, rt_string_from_c(""))) {
    return n;
  }
  rt_string * originalName = n->text;
  if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
    int64_t dot2 = xn_int_wrap(xn_lastDot(n->text));
    if ((dot2 > 0)) {
      originalName = xn_str_substr(n->text, xn_int_wrap((dot2 + 1)), xn_int_wrap((xn_int_wrap((((int64_t)n->text->len) - dot2)) - 1)));
    }
  }
  if ((!xn_Cls_Mono_isGenericMethod(self, className, originalName))) {
    return n;
  }
  int isStatic = xn_Cls_Mono_isGenericMethodStatic(self, className, originalName);
  rt_string * gname = xn_Cls_Mono_gmName(self, className, originalName);
  xn_Cls_AstNode * call = xn_Cls_AstNode_new(rt_string_from_c("Call"), gname, n->line, n->col);
  int64_t start = xn_int_wrap(0);
  if (methodCall) {
    if ((!isStatic)) {
      xn_Cls_AstNode_add(call, recv);
    }
    if (receiverInKids) {
      start = 1;
    }
  }
  if (((start < ((int64_t)n->kids->len)) && xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, start))->kind, rt_string_from_c("TypeArgs")))) {
    rt_string * explicitArgs = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, start))->text;
    rt_string * combinedArgs = explicitArgs;
    if ((!xn_str_eq(classArgsText, rt_string_from_c("")))) {
      combinedArgs = xn_concat(xn_concat(classArgsText, rt_string_from_c(",")), explicitArgs);
    }
    xn_Cls_AstNode * gf = xn_Cls_Mono_findGeneric(self, gname);
    if (xn_str_eq(gf->kind, rt_string_from_c("Func"))) {
      rt_string * sname = xn_Cls_Mono_specialize(self, gf, xn_splitTop(combinedArgs));
      if ((!xn_str_eq(sname, rt_string_from_c("")))) {
        call->text = sname;
      }
    }
    start = xn_int_wrap((start + 1));
  }
  while ((start < ((int64_t)n->kids->len))) {
    xn_Cls_AstNode_add(call, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, start)));
    start = xn_int_wrap((start + 1));
  }
  if (xn_str_eq(call->text, gname)) {
    rt_string * inferredArgs = xn_Cls_Mono_typeArgsFor(self, call);
    if ((!xn_str_eq(inferredArgs, rt_string_from_c("")))) {
      xn_Cls_AstNode * gf2 = xn_Cls_Mono_findGeneric(self, gname);
      if (xn_str_eq(gf2->kind, rt_string_from_c("Func"))) {
        rt_string * sname = xn_Cls_Mono_specialize(self, gf2, xn_splitTop(inferredArgs));
        if ((!xn_str_eq(sname, rt_string_from_c("")))) {
          call->text = sname;
        }
      }
    }
  }
  return call;
}

static rt_string * xn_Cls_Mono_firstTypeToken(xn_Cls_Mono *self, rt_string * text) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)text->len))) {
    if (xn_str_eq(xn_str_substr(text, i, 1), rt_string_from_c(" "))) {
      return xn_str_substr(text, 0, i);
    }
    i = xn_int_wrap((i + 1));
  }
  return text;
}

static xn_Cls_AstNode * xn_Cls_Mono_inferGenericStaticCall(xn_Cls_Mono *self, xn_Cls_AstNode * n, rt_string * expected) {
  if (((!xn_str_eq(n->kind, rt_string_from_c("Call"))) || xn_str_eq(expected, rt_string_from_c("")))) {
    return n;
  }
  xn_Cls_AstNode * fn = xn_Cls_Mono_findGeneric(self, n->text);
  if ((!xn_str_eq(fn->kind, rt_string_from_c("Func")))) {
    return n;
  }
  xn_arr_s * names = xn_Cls_Mono_typeParams(self, fn);
  if ((((int64_t)names->len) == 0)) {
    return n;
  }
  xn_arr_s *inferred = xn_arr_s_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)names->len))) {
    xn_arr_s_push(inferred, rt_string_from_c(""));
    i = xn_int_wrap((i + 1));
  }
  if ((!xn_Cls_Mono_inferTypePattern(self, xn_Cls_Mono_retTypeText(self, fn), expected, names, inferred))) {
    return n;
  }
  int64_t k = xn_int_wrap(0);
  while ((k < ((int64_t)inferred->len))) {
    if (xn_str_eq(xn_arr_s_get(inferred, k), rt_string_from_c(""))) {
      return n;
    }
    k = xn_int_wrap((k + 1));
  }
  rt_string * sname = xn_Cls_Mono_specialize(self, fn, inferred);
  if ((!xn_str_eq(sname, rt_string_from_c("")))) {
    n->text = sname;
  }
  return n;
}

static int xn_Cls_Mono_inferGenericStaticCalls(xn_Cls_Mono *self, xn_Cls_AstNode * n, rt_string * expected, rt_string * curRet) {
  if (xn_Cls_Mono_hasTypeParams(self, n)) {
    return 0;
  }
  int changed = 0;
  if (xn_str_eq(n->kind, rt_string_from_c("Call"))) {
    rt_string * before = n->text;
    n = xn_Cls_Mono_inferGenericStaticCall(self, n, expected);
    if ((!xn_str_eq(n->text, before))) {
      changed = 1;
    }
  }
  rt_string * childExpected = rt_string_from_c("");
  rt_string * childRet = curRet;
  if ((xn_str_eq(n->kind, rt_string_from_c("Local")) || xn_str_eq(n->kind, rt_string_from_c("Field")))) {
    childExpected = xn_Cls_Mono_firstTypeToken(self, n->text);
  }
  else {
    if (xn_str_eq(n->kind, rt_string_from_c("Return"))) {
      childExpected = curRet;
    }
    else {
      if ((((xn_str_eq(n->kind, rt_string_from_c("Func")) || xn_str_eq(n->kind, rt_string_from_c("Method"))) || xn_str_eq(n->kind, rt_string_from_c("Ctor"))) || xn_str_eq(n->kind, rt_string_from_c("Deinit")))) {
        childRet = xn_Cls_Mono_retTypeText(self, n);
      }
    }
  }
  int childChanged = 0;
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    if (xn_Cls_Mono_inferGenericStaticCalls(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), childExpected, childRet)) {
      childChanged = 1;
    }
    i = xn_int_wrap((i + 1));
  }
  if (((xn_str_eq(n->kind, rt_string_from_c("Local")) || xn_str_eq(n->kind, rt_string_from_c("Field"))) && childChanged)) {
    n->text = xn_Cls_Mono_rewriteType(self, n->text);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("New"))) {
    n->text = xn_Cls_Mono_rewriteType(self, n->text);
  }
  if ((((xn_str_eq(n->kind, rt_string_from_c("Func")) || xn_str_eq(n->kind, rt_string_from_c("Method"))) || xn_str_eq(n->kind, rt_string_from_c("Ctor"))) || xn_str_eq(n->kind, rt_string_from_c("Deinit")))) {
    int64_t ri = xn_int_wrap(0);
    while ((ri < ((int64_t)n->kids->len))) {
      if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ri))->kind, rt_string_from_c("Ret"))) {
        ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ri))->text = xn_Cls_Mono_rewriteType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, ri))->text);
      }
      ri = xn_int_wrap((ri + 1));
    }
  }
  if (childChanged) {
    changed = 1;
  }
  return changed;
}

static xn_Cls_AstNode * xn_Cls_Mono_run(xn_Cls_Mono *self) {
  xn_Cls_Mono_desugarGenericMethods(self);
  xn_Cls_Mono_collectUsedMethods(self);
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
  xn_Cls_Mono_inferGenericStaticCalls(self, self->program, rt_string_from_c(""), rt_string_from_c(""));
  return self->program;
}

struct xn_Cls_AnnotationDiag {
  rt_header hdr;
  rt_string * code;
  rt_string * msg;
  int64_t line;
  int64_t col;
};

static const rt_type RT_TYPE_XN_AnnotationDiag = { "AnnotationDiag", sizeof(xn_Cls_AnnotationDiag), NULL, NULL };

static xn_Cls_AnnotationDiag *xn_Cls_AnnotationDiag_new(rt_string * code, rt_string * msg, int64_t line, int64_t col) {
  xn_Cls_AnnotationDiag *xn_obj = (xn_Cls_AnnotationDiag *)rt_gc_new(&RT_TYPE_XN_AnnotationDiag);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_AnnotationDiag) - sizeof(rt_header));
  xn_obj->code = rt_string_from_c("");
  xn_obj->msg = rt_string_from_c("");
  xn_obj->line = 0;
  xn_obj->col = 0;
  xn_Cls_AnnotationDiag *self = xn_obj;
  self->code = code;
  self->msg = msg;
  self->line = line;
  self->col = col;
  return xn_obj;
}


struct xn_Cls_AnnotationType {
  rt_header hdr;
  rt_string * name;
  xn_arr_s * targets;
  rt_string * retention;
  int repeatable;
  xn_arr_s * fieldNames;
  xn_arr_s * fieldTypes;
  xn_arr_s * fieldRequired;
  xn_arr_o * fieldDefaults;
};

static const rt_type RT_TYPE_XN_AnnotationType = { "AnnotationType", sizeof(xn_Cls_AnnotationType), NULL, NULL };

static xn_Cls_AnnotationType *xn_Cls_AnnotationType_new(rt_string * name, xn_arr_s * targets, rt_string * retention, int repeatable) {
  xn_Cls_AnnotationType *xn_obj = (xn_Cls_AnnotationType *)rt_gc_new(&RT_TYPE_XN_AnnotationType);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_AnnotationType) - sizeof(rt_header));
  xn_obj->name = rt_string_from_c("");
  xn_obj->targets = xn_arr_s_new(4);
  xn_obj->retention = rt_string_from_c("");
  xn_obj->repeatable = 0;
  xn_obj->fieldNames = xn_arr_s_new(4);
  xn_obj->fieldTypes = xn_arr_s_new(4);
  xn_obj->fieldRequired = xn_arr_s_new(4);
  xn_obj->fieldDefaults = xn_arr_o_new(4);
  xn_Cls_AnnotationType *self = xn_obj;
  self->name = name;
  self->targets = targets;
  self->retention = retention;
  self->repeatable = repeatable;
  self->fieldNames = xn_arr_s_new(0);
  self->fieldTypes = xn_arr_s_new(0);
  self->fieldRequired = xn_arr_s_new(0);
  self->fieldDefaults = xn_arr_o_new(0);
  return xn_obj;
}

static void xn_Cls_AnnotationType_addField(xn_Cls_AnnotationType *self, rt_string * name, rt_string * ty, int required, xn_Cls_AstNode * def);
static void xn_Cls_AnnotationType_clearTargets(xn_Cls_AnnotationType *self);
static int xn_Cls_AnnotationType_allows(xn_Cls_AnnotationType *self, rt_string * target);

static void xn_Cls_AnnotationType_addField(xn_Cls_AnnotationType *self, rt_string * name, rt_string * ty, int required, xn_Cls_AstNode * def) {
  xn_arr_s_push(self->fieldNames, name);
  xn_arr_s_push(self->fieldTypes, ty);
  if (required) {
    xn_arr_s_push(self->fieldRequired, rt_string_from_c("1"));
  }
  else {
    xn_arr_s_push(self->fieldRequired, rt_string_from_c("0"));
  }
  xn_arr_o_push(self->fieldDefaults, def);
}

static void xn_Cls_AnnotationType_clearTargets(xn_Cls_AnnotationType *self) {
  while ((((int64_t)self->targets->len) > 0)) {
    xn_arr_s_remove(self->targets, xn_int_wrap((((int64_t)self->targets->len) - 1)));
  }
}

static int xn_Cls_AnnotationType_allows(xn_Cls_AnnotationType *self, rt_string * target) {
  if ((((int64_t)self->targets->len) == 0)) {
    return (!xn_str_eq(target, rt_string_from_c("TypeUse")));
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->targets->len))) {
    if (xn_str_eq(xn_arr_s_get(self->targets, i), target)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

struct xn_Cls_AnnotationChecker {
  rt_header hdr;
  rt_string * file;
  xn_Cls_AstNode * program;
  xn_arr_o * types;
  xn_arr_s * enumNames;
  xn_arr_s * enumItemNames;
  xn_arr_s * enumItemOwners;
  xn_arr_s * roOwners;
  xn_arr_s * roFields;
  xn_arr_s * depFuncs;
  xn_arr_s * depTypes;
  xn_arr_s * depAnnos;
  xn_arr_s * depMethods;
  xn_arr_s * depFields;
  xn_arr_s * depItems;
  xn_arr_s * depCtors;
  xn_arr_s * classNames;
  xn_arr_o * warnings;
  xn_arr_s * validated;
  rt_string * error;
  rt_string * errorCode;
  int64_t errorLine;
  int64_t errorCol;
};

static const rt_type RT_TYPE_XN_AnnotationChecker = { "AnnotationChecker", sizeof(xn_Cls_AnnotationChecker), NULL, NULL };

static xn_Cls_AnnotationChecker *xn_Cls_AnnotationChecker_new(rt_string * file, xn_Cls_AstNode * program) {
  xn_Cls_AnnotationChecker *xn_obj = (xn_Cls_AnnotationChecker *)rt_gc_new(&RT_TYPE_XN_AnnotationChecker);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_AnnotationChecker) - sizeof(rt_header));
  xn_obj->file = rt_string_from_c("");
  xn_obj->program = 0;
  xn_obj->types = xn_arr_o_new(4);
  xn_obj->enumNames = xn_arr_s_new(4);
  xn_obj->enumItemNames = xn_arr_s_new(4);
  xn_obj->enumItemOwners = xn_arr_s_new(4);
  xn_obj->roOwners = xn_arr_s_new(4);
  xn_obj->roFields = xn_arr_s_new(4);
  xn_obj->depFuncs = xn_arr_s_new(4);
  xn_obj->depTypes = xn_arr_s_new(4);
  xn_obj->depAnnos = xn_arr_s_new(4);
  xn_obj->depMethods = xn_arr_s_new(4);
  xn_obj->depFields = xn_arr_s_new(4);
  xn_obj->depItems = xn_arr_s_new(4);
  xn_obj->depCtors = xn_arr_s_new(4);
  xn_obj->classNames = xn_arr_s_new(4);
  xn_obj->warnings = xn_arr_o_new(4);
  xn_obj->validated = xn_arr_s_new(4);
  xn_obj->error = rt_string_from_c("");
  xn_obj->errorCode = rt_string_from_c("");
  xn_obj->errorLine = 0;
  xn_obj->errorCol = 0;
  xn_Cls_AnnotationChecker *self = xn_obj;
  self->file = file;
  self->program = program;
  self->types = xn_arr_o_new(0);
  self->enumNames = xn_arr_s_new(0);
  self->enumItemNames = xn_arr_s_new(0);
  self->enumItemOwners = xn_arr_s_new(0);
  self->roOwners = xn_arr_s_new(0);
  self->roFields = xn_arr_s_new(0);
  self->depFuncs = xn_arr_s_new(0);
  self->depTypes = xn_arr_s_new(0);
  self->depAnnos = xn_arr_s_new(0);
  self->depMethods = xn_arr_s_new(0);
  self->depFields = xn_arr_s_new(0);
  self->depItems = xn_arr_s_new(0);
  self->depCtors = xn_arr_s_new(0);
  self->classNames = xn_arr_s_new(0);
  self->warnings = xn_arr_o_new(0);
  self->validated = xn_arr_s_new(0);
  self->error = rt_string_from_c("");
  self->errorCode = rt_string_from_c("");
  self->errorLine = 1;
  self->errorCol = 1;
  return xn_obj;
}

static int xn_Cls_AnnotationChecker_hasError(xn_Cls_AnnotationChecker *self);
static void xn_Cls_AnnotationChecker_fail(xn_Cls_AnnotationChecker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n);
static void xn_Cls_AnnotationChecker_warn(xn_Cls_AnnotationChecker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n, xn_Cls_AstNode * owner);
static void xn_Cls_AnnotationChecker_failAt(xn_Cls_AnnotationChecker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n, xn_Cls_AstNode * owner);
static int xn_Cls_AnnotationChecker_suppressed(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * owner, rt_string * code);
static xn_arr_s * xn_Cls_AnnotationChecker_allTargets(xn_Cls_AnnotationChecker *self);
static xn_arr_s * xn_Cls_AnnotationChecker_declTargets(xn_Cls_AnnotationChecker *self);
static xn_arr_s * xn_Cls_AnnotationChecker_retentionNames(xn_Cls_AnnotationChecker *self);
static xn_arr_s * xn_Cls_AnnotationChecker_knownCodes(xn_Cls_AnnotationChecker *self);
static int xn_Cls_AnnotationChecker_listHas(xn_Cls_AnnotationChecker *self, xn_arr_s * items, rt_string * v);
static int xn_Cls_AnnotationChecker_isReserved(xn_Cls_AnnotationChecker *self, rt_string * name);
static int xn_Cls_AnnotationChecker_isBuiltin(xn_Cls_AnnotationChecker *self, rt_string * name);
static int64_t xn_Cls_AnnotationChecker_findType(xn_Cls_AnnotationChecker *self, rt_string * name);
static int64_t xn_Cls_AnnotationChecker_findTypeFor(xn_Cls_AnnotationChecker *self, rt_string * name, rt_string * ownerPkg);
static void xn_Cls_AnnotationChecker_addBuiltin(xn_Cls_AnnotationChecker *self, rt_string * name, xn_arr_s * targets, int repeatable);
static void xn_Cls_AnnotationChecker_initBuiltins(xn_Cls_AnnotationChecker *self);
static rt_string * xn_Cls_AnnotationChecker_unquote(xn_Cls_AnnotationChecker *self, rt_string * s);
static rt_string * xn_Cls_AnnotationChecker_pathOf(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n);
static int xn_Cls_AnnotationChecker_isEnumItem(xn_Cls_AnnotationChecker *self, rt_string * path);
static rt_string * xn_Cls_AnnotationChecker_enumOwnerOf(xn_Cls_AnnotationChecker *self, rt_string * path);
static rt_string * xn_Cls_AnnotationChecker_constType(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n);
static int xn_Cls_AnnotationChecker_isConstValue(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n);
static int xn_Cls_AnnotationChecker_numericType(xn_Cls_AnnotationChecker *self, rt_string * ty);
static int xn_Cls_AnnotationChecker_accepts(xn_Cls_AnnotationChecker *self, rt_string * fieldType, xn_Cls_AstNode * arg);
static int xn_Cls_AnnotationChecker_constantTypeAllowed(xn_Cls_AnnotationChecker *self, rt_string * ty);
static void xn_Cls_AnnotationChecker_collectTypes(xn_Cls_AnnotationChecker *self);
static void xn_Cls_AnnotationChecker_validateAnnotationDecl(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * d);
static void xn_Cls_AnnotationChecker_validateUses(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * owner, rt_string * target, xn_Cls_AstNode * scope);
static void xn_Cls_AnnotationChecker_validateTypeUses(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * owner, xn_Cls_AstNode * scope);
static void xn_Cls_AnnotationChecker_validateUse(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * use, rt_string * target, xn_Cls_AstNode * owner, xn_arr_o * uses, xn_Cls_AstNode * scope, int64_t index);
static void xn_Cls_AnnotationChecker_collectDeprecated(xn_Cls_AnnotationChecker *self);
static int xn_Cls_AnnotationChecker_hasUse(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, rt_string * name);
static int xn_Cls_AnnotationChecker_isReadOnlyField(xn_Cls_AnnotationChecker *self, rt_string * owner, rt_string * field);
static void xn_Cls_AnnotationChecker_checkDecl(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, rt_string * target);
static void xn_Cls_AnnotationChecker_checkBlock(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * block, xn_Cls_AstNode * owner);
static void xn_Cls_AnnotationChecker_checkExpr(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, xn_Cls_AstNode * owner);
static rt_string * xn_Cls_AnnotationChecker_paramTypesOf(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * fn);
static rt_string * xn_Cls_AnnotationChecker_retOf(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * fn);
static int xn_Cls_AnnotationChecker_protocolHasSig(xn_Cls_AnnotationChecker *self, rt_string * pname, rt_string * mname, rt_string * params, rt_string * ret);
static void xn_Cls_AnnotationChecker_checkOverrides(xn_Cls_AnnotationChecker *self);
static rt_string * xn_Cls_AnnotationChecker_lookupVar(xn_Cls_AnnotationChecker *self, xn_arr_s * names, xn_arr_s * types, rt_string * name);
static void xn_Cls_AnnotationChecker_popVars(xn_Cls_AnnotationChecker *self, xn_arr_s * names, xn_arr_s * types, int64_t mark);
static void xn_Cls_AnnotationChecker_checkReadOnlyIn(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, rt_string * cls, xn_arr_s * names, xn_arr_s * types, xn_Cls_AstNode * owner);
static void xn_Cls_AnnotationChecker_checkReadOnlyWrites(xn_Cls_AnnotationChecker *self);
static void xn_Cls_AnnotationChecker_roCheckMembers(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * c, rt_string * cls);
static void xn_Cls_AnnotationChecker_check(xn_Cls_AnnotationChecker *self);

static int xn_Cls_AnnotationChecker_hasError(xn_Cls_AnnotationChecker *self) {
  return (!xn_str_eq(self->error, rt_string_from_c("")));
}

static void xn_Cls_AnnotationChecker_fail(xn_Cls_AnnotationChecker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n) {
  if (xn_str_eq(self->error, rt_string_from_c(""))) {
    self->error = msg;
    self->errorCode = code;
    self->errorLine = n->line;
    self->errorCol = n->col;
  }
}

static void xn_Cls_AnnotationChecker_warn(xn_Cls_AnnotationChecker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n, xn_Cls_AstNode * owner) {
  if (((!xn_str_eq(code, rt_string_from_c("AN0015"))) && xn_Cls_AnnotationChecker_suppressed(self, owner, code))) {
    return;
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->warnings->len))) {
    xn_Cls_AnnotationDiag * old = ((xn_Cls_AnnotationDiag *)xn_arr_o_get(self->warnings, i));
    if ((((xn_str_eq(old->code, code) && (old->line == n->line)) && (old->col == n->col)) && xn_str_eq(old->msg, msg))) {
      return;
    }
    i = xn_int_wrap((i + 1));
  }
  xn_arr_o_push(self->warnings, xn_Cls_AnnotationDiag_new(code, msg, n->line, n->col));
}

static void xn_Cls_AnnotationChecker_failAt(xn_Cls_AnnotationChecker *self, rt_string * code, rt_string * msg, xn_Cls_AstNode * n, xn_Cls_AstNode * owner) {
  if (((!xn_str_eq(code, rt_string_from_c("AN0015"))) && xn_Cls_AnnotationChecker_suppressed(self, owner, code))) {
    return;
  }
  xn_Cls_AnnotationChecker_fail(self, code, msg, n);
}

static int xn_Cls_AnnotationChecker_suppressed(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * owner, rt_string * code) {
  if (xn_str_eq(owner->kind, rt_string_from_c("None"))) {
    return 0;
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)owner->annotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(owner->annotations, i));
    if (xn_str_eq(use->text, rt_string_from_c("SuppressWarnings"))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)use->kids->len))) {
        xn_Cls_AstNode * arg = ((xn_Cls_AstNode *)xn_arr_o_get(use->kids, j));
        if ((((int64_t)arg->kids->len) > 0)) {
          xn_Cls_AstNode * v = ((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0));
          if ((xn_str_eq(v->kind, rt_string_from_c("String")) && xn_str_eq(xn_Cls_AnnotationChecker_unquote(self, v->text), code))) {
            return 1;
          }
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static xn_arr_s * xn_Cls_AnnotationChecker_allTargets(xn_Cls_AnnotationChecker *self) {
  xn_arr_s *r = xn_arr_s_new(0);
  xn_arr_s_push(r, rt_string_from_c("Package"));
  xn_arr_s_push(r, rt_string_from_c("Type"));
  xn_arr_s_push(r, rt_string_from_c("Annotation"));
  xn_arr_s_push(r, rt_string_from_c("TypeParameter"));
  xn_arr_s_push(r, rt_string_from_c("Field"));
  xn_arr_s_push(r, rt_string_from_c("Method"));
  xn_arr_s_push(r, rt_string_from_c("Constructor"));
  xn_arr_s_push(r, rt_string_from_c("Deinit"));
  xn_arr_s_push(r, rt_string_from_c("Parameter"));
  xn_arr_s_push(r, rt_string_from_c("TypeUse"));
  xn_arr_s_push(r, rt_string_from_c("EnumItem"));
  return r;
}

static xn_arr_s * xn_Cls_AnnotationChecker_declTargets(xn_Cls_AnnotationChecker *self) {
  xn_arr_s *r = xn_arr_s_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)xn_Cls_AnnotationChecker_allTargets(self)->len))) {
    rt_string * t = xn_arr_s_get(xn_Cls_AnnotationChecker_allTargets(self), i);
    if ((!xn_str_eq(t, rt_string_from_c("TypeUse")))) {
      xn_arr_s_push(r, t);
    }
    i = xn_int_wrap((i + 1));
  }
  return r;
}

static xn_arr_s * xn_Cls_AnnotationChecker_retentionNames(xn_Cls_AnnotationChecker *self) {
  xn_arr_s *r = xn_arr_s_new(0);
  xn_arr_s_push(r, rt_string_from_c("Source"));
  xn_arr_s_push(r, rt_string_from_c("Binary"));
  xn_arr_s_push(r, rt_string_from_c("Runtime"));
  return r;
}

static xn_arr_s * xn_Cls_AnnotationChecker_knownCodes(xn_Cls_AnnotationChecker *self) {
  xn_arr_s *r = xn_arr_s_new(0);
  xn_arr_s_push(r, rt_string_from_c("AN0001"));
  xn_arr_s_push(r, rt_string_from_c("AN0002"));
  xn_arr_s_push(r, rt_string_from_c("AN0003"));
  xn_arr_s_push(r, rt_string_from_c("AN0004"));
  xn_arr_s_push(r, rt_string_from_c("AN0005"));
  xn_arr_s_push(r, rt_string_from_c("AN0006"));
  xn_arr_s_push(r, rt_string_from_c("AN0007"));
  xn_arr_s_push(r, rt_string_from_c("AN0008"));
  xn_arr_s_push(r, rt_string_from_c("AN0009"));
  xn_arr_s_push(r, rt_string_from_c("AN0010"));
  xn_arr_s_push(r, rt_string_from_c("AN0011"));
  xn_arr_s_push(r, rt_string_from_c("AN0012"));
  xn_arr_s_push(r, rt_string_from_c("AN0013"));
  xn_arr_s_push(r, rt_string_from_c("AN0014"));
  xn_arr_s_push(r, rt_string_from_c("AN0015"));
  xn_arr_s_push(r, rt_string_from_c("AN0016"));
  xn_arr_s_push(r, rt_string_from_c("AN0017"));
  xn_arr_s_push(r, rt_string_from_c("AN0018"));
  xn_arr_s_push(r, rt_string_from_c("AN0019"));
  xn_arr_s_push(r, rt_string_from_c("AN0020"));
  xn_arr_s_push(r, rt_string_from_c("AN0021"));
  xn_arr_s_push(r, rt_string_from_c("AN0022"));
  xn_arr_s_push(r, rt_string_from_c("AN0023"));
  xn_arr_s_push(r, rt_string_from_c("AN0024"));
  xn_arr_s_push(r, rt_string_from_c("AN0025"));
  xn_arr_s_push(r, rt_string_from_c("AN0026"));
  xn_arr_s_push(r, rt_string_from_c("AN0027"));
  xn_arr_s_push(r, rt_string_from_c("AN0028"));
  return r;
}

static int xn_Cls_AnnotationChecker_listHas(xn_Cls_AnnotationChecker *self, xn_arr_s * items, rt_string * v) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)items->len))) {
    if (xn_str_eq(xn_arr_s_get(items, i), v)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int xn_Cls_AnnotationChecker_isReserved(xn_Cls_AnnotationChecker *self, rt_string * name) {
  return ((((((xn_str_eq(name, rt_string_from_c("Immediate")) || xn_str_eq(name, rt_string_from_c("NoAlloc"))) || xn_str_eq(name, rt_string_from_c("Pure"))) || xn_str_eq(name, rt_string_from_c("Sendable"))) || xn_str_eq(name, rt_string_from_c("tasks"))) || xn_str_eq(name, rt_string_from_c("arena"))) || xn_str_eq(name, rt_string_from_c("Inherited")));
}

static int xn_Cls_AnnotationChecker_isBuiltin(xn_Cls_AnnotationChecker *self, rt_string * name) {
  return ((((((((xn_str_eq(name, rt_string_from_c("Target")) || xn_str_eq(name, rt_string_from_c("Retention"))) || xn_str_eq(name, rt_string_from_c("Repeatable"))) || xn_str_eq(name, rt_string_from_c("Deprecated"))) || xn_str_eq(name, rt_string_from_c("SuppressWarnings"))) || xn_str_eq(name, rt_string_from_c("ReadOnly"))) || xn_str_eq(name, rt_string_from_c("WriteOnly"))) || xn_str_eq(name, rt_string_from_c("Override"))) || xn_str_eq(name, rt_string_from_c("MustUse")));
}

static int64_t xn_Cls_AnnotationChecker_findType(xn_Cls_AnnotationChecker *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->types->len))) {
    if (xn_str_eq(((xn_Cls_AnnotationType *)xn_arr_o_get(self->types, i))->name, name)) {
      return xn_int_wrap(i);
    }
    i = xn_int_wrap((i + 1));
  }
  if ((xn_str_indexof(name, rt_string_from_c(".")) >= 0)) {
    return xn_int_wrap(xn_int_wrap(-(1)));
  }
  int64_t found = xn_int_wrap(xn_int_wrap(-(1)));
  i = 0;
  while ((i < ((int64_t)self->types->len))) {
    rt_string * candidate = ((xn_Cls_AnnotationType *)xn_arr_o_get(self->types, i))->name;
    int64_t dot = xn_int_wrap(xn_int_wrap((((int64_t)candidate->len) - 1)));
    while ((dot >= 0)) {
      if (xn_str_eq(xn_str_substr(candidate, dot, 1), rt_string_from_c("."))) {
        break;
      }
      dot = xn_int_wrap((dot - 1));
    }
    rt_string * simple = candidate;
    if ((dot >= 0)) {
      simple = xn_str_substr(candidate, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)candidate->len) - dot)) - 1)));
    }
    if (xn_str_eq(simple, name)) {
      if ((found >= 0)) {
        return xn_int_wrap(xn_int_wrap(-(1)));
      }
      found = i;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_int_wrap(found);
}

static int64_t xn_Cls_AnnotationChecker_findTypeFor(xn_Cls_AnnotationChecker *self, rt_string * name, rt_string * ownerPkg) {
  if ((xn_str_indexof(name, rt_string_from_c(".")) >= 0)) {
    return xn_int_wrap(xn_Cls_AnnotationChecker_findType(self, name));
  }
  int64_t found = xn_int_wrap(xn_int_wrap(-(1)));
  int64_t hits = xn_int_wrap(0);
  rt_string * own = xn_concat(xn_concat(ownerPkg, rt_string_from_c(".")), name);
  int64_t direct = xn_int_wrap(xn_Cls_AnnotationChecker_findType(self, own));
  if ((direct >= 0)) {
    return xn_int_wrap(direct);
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)unitImportOwners->len))) {
    if (xn_str_eq(xn_arr_s_get(unitImportOwners, i), ownerPkg)) {
      int64_t candidate = xn_int_wrap(xn_Cls_AnnotationChecker_findType(self, xn_concat(xn_concat(xn_arr_s_get(unitImportPkgs, i), rt_string_from_c(".")), name)));
      if ((candidate >= 0)) {
        found = candidate;
        hits = xn_int_wrap((hits + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  if ((hits == 1)) {
    return xn_int_wrap(found);
  }
  if ((hits > 1)) {
    return xn_int_wrap(xn_int_wrap(-(2)));
  }
  return xn_int_wrap(xn_Cls_AnnotationChecker_findType(self, name));
}

static void xn_Cls_AnnotationChecker_addBuiltin(xn_Cls_AnnotationChecker *self, rt_string * name, xn_arr_s * targets, int repeatable) {
  xn_arr_o_push(self->types, xn_Cls_AnnotationType_new(name, targets, rt_string_from_c("Binary"), repeatable));
}

static void xn_Cls_AnnotationChecker_initBuiltins(xn_Cls_AnnotationChecker *self) {
  xn_arr_s *meta = xn_arr_s_new(0);
  xn_arr_s_push(meta, rt_string_from_c("Annotation"));
  xn_Cls_AnnotationChecker_addBuiltin(self, rt_string_from_c("Target"), meta, 0);
  xn_Cls_AnnotationChecker_addBuiltin(self, rt_string_from_c("Retention"), meta, 0);
  xn_Cls_AnnotationChecker_addBuiltin(self, rt_string_from_c("Repeatable"), meta, 0);
  xn_arr_s * decl = xn_Cls_AnnotationChecker_declTargets(self);
  xn_Cls_AnnotationChecker_addBuiltin(self, rt_string_from_c("Deprecated"), decl, 0);
  xn_Cls_AnnotationChecker_addBuiltin(self, rt_string_from_c("SuppressWarnings"), decl, 0);
  xn_arr_s *fieldTarget = xn_arr_s_new(0);
  xn_arr_s_push(fieldTarget, rt_string_from_c("Field"));
  xn_Cls_AnnotationChecker_addBuiltin(self, rt_string_from_c("ReadOnly"), fieldTarget, 0);
  xn_Cls_AnnotationChecker_addBuiltin(self, rt_string_from_c("WriteOnly"), fieldTarget, 0);
  xn_arr_s *methodTarget = xn_arr_s_new(0);
  xn_arr_s_push(methodTarget, rt_string_from_c("Method"));
  xn_Cls_AnnotationChecker_addBuiltin(self, rt_string_from_c("Override"), methodTarget, 0);
  xn_arr_s *mustTarget = xn_arr_s_new(0);
  xn_arr_s_push(mustTarget, rt_string_from_c("Type"));
  xn_arr_s_push(mustTarget, rt_string_from_c("Method"));
  xn_Cls_AnnotationChecker_addBuiltin(self, rt_string_from_c("MustUse"), mustTarget, 0);
}

static rt_string * xn_Cls_AnnotationChecker_unquote(xn_Cls_AnnotationChecker *self, rt_string * s) {
  if ((((((int64_t)s->len) >= 2) && xn_str_eq(xn_str_substr(s, 0, 1), rt_string_from_c("\""))) && xn_str_eq(xn_str_substr(s, xn_int_wrap((((int64_t)s->len) - 1)), 1), rt_string_from_c("\"")))) {
    return xn_str_substr(s, 1, xn_int_wrap((((int64_t)s->len) - 2)));
  }
  return s;
}

static rt_string * xn_Cls_AnnotationChecker_pathOf(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Name"))) {
    return n->text;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Member")) && (((int64_t)n->kids->len) > 0))) {
    rt_string * b = xn_Cls_AnnotationChecker_pathOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (xn_str_eq(b, rt_string_from_c(""))) {
      return n->text;
    }
    return xn_concat(xn_concat(b, rt_string_from_c(".")), n->text);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    return xn_Cls_AnnotationChecker_unquote(self, n->text);
  }
  return rt_string_from_c("");
}

static int xn_Cls_AnnotationChecker_isEnumItem(xn_Cls_AnnotationChecker *self, rt_string * path) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->enumItemNames->len))) {
    rt_string * full = xn_concat(xn_concat(xn_arr_s_get(self->enumItemOwners, i), rt_string_from_c(".")), xn_arr_s_get(self->enumItemNames, i));
    if (xn_str_eq(full, path)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static rt_string * xn_Cls_AnnotationChecker_enumOwnerOf(xn_Cls_AnnotationChecker *self, rt_string * path) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->enumItemNames->len))) {
    rt_string * full = xn_concat(xn_concat(xn_arr_s_get(self->enumItemOwners, i), rt_string_from_c(".")), xn_arr_s_get(self->enumItemNames, i));
    if (xn_str_eq(full, path)) {
      return xn_arr_s_get(self->enumItemOwners, i);
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_AnnotationChecker_constType(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Int"))) {
    return rt_string_from_c("Int");
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Long"))) {
    return rt_string_from_c("Long");
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
  if ((xn_str_eq(n->kind, rt_string_from_c("Unary")) && (((int64_t)n->kids->len) > 0))) {
    return xn_Cls_AnnotationChecker_constType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("ArrayLit"))) {
    if ((((int64_t)n->kids->len) == 0)) {
      return rt_string_from_c("Any[]");
    }
    return xn_concat(xn_Cls_AnnotationChecker_constType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("[]"));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("AnnotationUse"))) {
    return n->text;
  }
  rt_string * p = xn_Cls_AnnotationChecker_pathOf(self, n);
  if (((!xn_str_eq(p, rt_string_from_c(""))) && xn_Cls_AnnotationChecker_isEnumItem(self, p))) {
    return xn_Cls_AnnotationChecker_enumOwnerOf(self, p);
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Name")) || xn_str_eq(n->kind, rt_string_from_c("Member")))) {
    return rt_string_from_c("Type");
  }
  return rt_string_from_c("Unknown");
}

static int xn_Cls_AnnotationChecker_isConstValue(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n) {
  if (((((xn_str_eq(n->kind, rt_string_from_c("Int")) || xn_str_eq(n->kind, rt_string_from_c("Double"))) || xn_str_eq(n->kind, rt_string_from_c("Bool"))) || xn_str_eq(n->kind, rt_string_from_c("Char"))) || xn_str_eq(n->kind, rt_string_from_c("String")))) {
    return 1;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Unary")) && (((int64_t)n->kids->len) > 0))) {
    rt_string * t = xn_Cls_AnnotationChecker_constType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    return (xn_str_eq(t, rt_string_from_c("Int")) || xn_str_eq(t, rt_string_from_c("Double")));
  }
  if (xn_str_eq(n->kind, rt_string_from_c("ArrayLit"))) {
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)n->kids->len))) {
      if ((!xn_Cls_AnnotationChecker_isConstValue(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i))))) {
        return 0;
      }
      i = xn_int_wrap((i + 1));
    }
    return 1;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("AnnotationUse"))) {
    return 1;
  }
  rt_string * p = xn_Cls_AnnotationChecker_pathOf(self, n);
  if (((!xn_str_eq(p, rt_string_from_c(""))) && (xn_Cls_AnnotationChecker_isEnumItem(self, p) || (xn_Cls_AnnotationChecker_findType(self, p) >= 0)))) {
    return 1;
  }
  return 0;
}

static int xn_Cls_AnnotationChecker_numericType(xn_Cls_AnnotationChecker *self, rt_string * ty) {
  return (((((((xn_str_eq(ty, rt_string_from_c("Int")) || xn_str_eq(ty, rt_string_from_c("Int32"))) || xn_str_eq(ty, rt_string_from_c("Int64"))) || xn_str_eq(ty, rt_string_from_c("Long"))) || xn_str_eq(ty, rt_string_from_c("UInt16"))) || xn_str_eq(ty, rt_string_from_c("Int128"))) || xn_str_eq(ty, rt_string_from_c("Float"))) || xn_str_eq(ty, rt_string_from_c("Double")));
}

static int xn_Cls_AnnotationChecker_accepts(xn_Cls_AnnotationChecker *self, rt_string * fieldType, xn_Cls_AstNode * arg) {
  rt_string * ft = fieldType;
  if (((((int64_t)ft->len) > 1) && xn_str_eq(xn_str_substr(ft, xn_int_wrap((((int64_t)ft->len) - 1)), 1), rt_string_from_c("?")))) {
    ft = xn_str_substr(ft, 0, xn_int_wrap((((int64_t)ft->len) - 1)));
  }
  rt_string * ct = xn_Cls_AnnotationChecker_constType(self, arg);
  if (xn_str_eq(ft, ct)) {
    return 1;
  }
  if ((xn_Cls_AnnotationChecker_numericType(self, ft) && (xn_str_eq(ct, rt_string_from_c("Int")) || xn_str_eq(ct, rt_string_from_c("Double"))))) {
    if (((xn_str_eq(ft, rt_string_from_c("Double")) || xn_str_eq(ft, rt_string_from_c("Float"))) || xn_str_eq(ct, rt_string_from_c("Int")))) {
      return 1;
    }
  }
  if ((xn_str_eq(ft, rt_string_from_c("Type")) || xn_str_eq(ft, rt_string_from_c("TypeRef")))) {
    return ((xn_str_eq(arg->kind, rt_string_from_c("Name")) || xn_str_eq(arg->kind, rt_string_from_c("Member"))) || xn_str_eq(arg->kind, rt_string_from_c("String")));
  }
  if (((((int64_t)ft->len) > 2) && xn_str_eq(xn_str_substr(ft, xn_int_wrap((((int64_t)ft->len) - 2)), 2), rt_string_from_c("[]")))) {
    if ((!xn_str_eq(arg->kind, rt_string_from_c("ArrayLit")))) {
      return 0;
    }
    rt_string * et = xn_str_substr(ft, 0, xn_int_wrap((((int64_t)ft->len) - 2)));
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)arg->kids->len))) {
      if ((!xn_Cls_AnnotationChecker_accepts(self, et, ((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, i))))) {
        return 0;
      }
      i = xn_int_wrap((i + 1));
    }
    return 1;
  }
  if ((xn_str_eq(arg->kind, rt_string_from_c("AnnotationUse")) && xn_str_eq(arg->text, ft))) {
    return 1;
  }
  rt_string * p = xn_Cls_AnnotationChecker_pathOf(self, arg);
  if (((!xn_str_eq(p, rt_string_from_c(""))) && xn_str_eq(xn_Cls_AnnotationChecker_enumOwnerOf(self, p), ft))) {
    return 1;
  }
  return 0;
}

static int xn_Cls_AnnotationChecker_constantTypeAllowed(xn_Cls_AnnotationChecker *self, rt_string * ty) {
  rt_string * base = ty;
  if (((((int64_t)base->len) > 1) && xn_str_eq(xn_str_substr(base, xn_int_wrap((((int64_t)base->len) - 1)), 1), rt_string_from_c("?")))) {
    base = xn_str_substr(base, 0, xn_int_wrap((((int64_t)base->len) - 1)));
  }
  if (((((int64_t)base->len) > 2) && xn_str_eq(xn_str_substr(base, xn_int_wrap((((int64_t)base->len) - 2)), 2), rt_string_from_c("[]")))) {
    return xn_Cls_AnnotationChecker_constantTypeAllowed(self, xn_str_substr(base, 0, xn_int_wrap((((int64_t)base->len) - 2))));
  }
  if (((((((((((((xn_str_eq(base, rt_string_from_c("Bool")) || xn_str_eq(base, rt_string_from_c("Int"))) || xn_str_eq(base, rt_string_from_c("Int32"))) || xn_str_eq(base, rt_string_from_c("Int64"))) || xn_str_eq(base, rt_string_from_c("Long"))) || xn_str_eq(base, rt_string_from_c("UInt16"))) || xn_str_eq(base, rt_string_from_c("Int128"))) || xn_str_eq(base, rt_string_from_c("Float"))) || xn_str_eq(base, rt_string_from_c("Double"))) || xn_str_eq(base, rt_string_from_c("Char"))) || xn_str_eq(base, rt_string_from_c("String"))) || xn_str_eq(base, rt_string_from_c("Type"))) || xn_str_eq(base, rt_string_from_c("TypeRef")))) {
    return 1;
  }
  if (xn_Cls_AnnotationChecker_listHas(self, self->enumNames, base)) {
    return 1;
  }
  if ((xn_Cls_AnnotationChecker_findType(self, base) >= 0)) {
    return 1;
  }
  return 0;
}

static void xn_Cls_AnnotationChecker_collectTypes(xn_Cls_AnnotationChecker *self) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("Enum"))) {
      xn_arr_s_push(self->enumNames, n->text);
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j));
        if (xn_str_eq(k->kind, rt_string_from_c("EnumItem"))) {
          xn_arr_s_push(self->enumItemNames, k->text);
          xn_arr_s_push(self->enumItemOwners, n->text);
        }
        j = xn_int_wrap((j + 1));
      }
    }
    if ((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct")))) {
      xn_arr_s_push(self->classNames, n->text);
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl"))) {
      rt_string * pkg = xn_declPackageOf(n);
      rt_string * qualified = n->text;
      if ((!xn_str_eq(pkg, rt_string_from_c("")))) {
        qualified = xn_concat(xn_concat(pkg, rt_string_from_c(".")), n->text);
      }
      if ((xn_Cls_AnnotationChecker_findType(self, qualified) >= 0)) {
        xn_Cls_AnnotationChecker_fail(self, rt_string_from_c("AN0001"), xn_concat(rt_string_from_c("duplicate annotation type: "), qualified), n);
      }
      else {
        xn_arr_o_push(self->types, xn_Cls_AnnotationType_new(qualified, xn_Cls_AnnotationChecker_declTargets(self), rt_string_from_c("Binary"), 0));
      }
    }
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_AnnotationChecker_validateAnnotationDecl(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * d) {
  int64_t ti = xn_int_wrap(xn_Cls_AnnotationChecker_findTypeFor(self, d->text, xn_declPackageOf(d)));
  if ((ti < 0)) {
    return;
  }
  rt_string * validateKey = d->text;
  if ((!xn_str_eq(xn_declPackageOf(d), rt_string_from_c("")))) {
    validateKey = xn_concat(xn_concat(xn_declPackageOf(d), rt_string_from_c(".")), d->text);
  }
  if (xn_Cls_AnnotationChecker_listHas(self, self->validated, validateKey)) {
    xn_Cls_AnnotationChecker_validateUses(self, d, rt_string_from_c("Annotation"), d);
    return;
  }
  xn_arr_s_push(self->validated, validateKey);
  xn_Cls_AnnotationType * t = ((xn_Cls_AnnotationType *)xn_arr_o_get(self->types, ti));
  int hasTarget = 0;
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)d->annotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(d->annotations, i));
    if (xn_str_eq(use->text, rt_string_from_c("Target"))) {
      hasTarget = 1;
      xn_Cls_AnnotationType_clearTargets(t);
      if ((((int64_t)use->kids->len) == 0)) {
        xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0009"), rt_string_from_c("@Target needs at least one target"), use, d);
      }
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)use->kids->len))) {
        xn_Cls_AstNode * arg = ((xn_Cls_AstNode *)xn_arr_o_get(use->kids, j));
        rt_string * path = rt_string_from_c("");
        if ((((int64_t)arg->kids->len) > 0)) {
          path = xn_Cls_AnnotationChecker_pathOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0)));
        }
        if ((!xn_Cls_AnnotationChecker_listHas(self, xn_Cls_AnnotationChecker_allTargets(self), path))) {
          xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0009"), xn_concat(rt_string_from_c("invalid @Target member: "), path), use, d);
        }
        else {
          if ((!xn_Cls_AnnotationChecker_listHas(self, t->targets, path))) {
            xn_arr_s_push(t->targets, path);
          }
        }
        j = xn_int_wrap((j + 1));
      }
    }
    else {
      if (xn_str_eq(use->text, rt_string_from_c("Retention"))) {
        rt_string * rp = rt_string_from_c("");
        if (((((int64_t)use->kids->len) == 1) && (((int64_t)((xn_Cls_AstNode *)xn_arr_o_get(use->kids, 0))->kids->len) > 0))) {
          rp = xn_Cls_AnnotationChecker_pathOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(((xn_Cls_AstNode *)xn_arr_o_get(use->kids, 0))->kids, 0)));
        }
        if (((((int64_t)use->kids->len) != 1) || (!xn_Cls_AnnotationChecker_listHas(self, xn_Cls_AnnotationChecker_retentionNames(self), rp)))) {
          xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0010"), rt_string_from_c("invalid @Retention member"), use, d);
        }
        else {
          t->retention = rp;
        }
      }
      else {
        if (xn_str_eq(use->text, rt_string_from_c("Repeatable"))) {
          if ((((int64_t)use->kids->len) != 0)) {
            xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0011"), rt_string_from_c("@Repeatable takes no arguments"), use, d);
          }
          else {
            t->repeatable = 1;
          }
        }
      }
    }
    i = xn_int_wrap((i + 1));
  }
  if ((hasTarget && (((int64_t)t->targets->len) == 0))) {
    int64_t k = xn_int_wrap(0);
    while ((k < ((int64_t)xn_Cls_AnnotationChecker_declTargets(self)->len))) {
      xn_arr_s_push(t->targets, xn_arr_s_get(xn_Cls_AnnotationChecker_declTargets(self), k));
      k = xn_int_wrap((k + 1));
    }
  }
  i = 0;
  while ((i < ((int64_t)d->kids->len))) {
    xn_Cls_AstNode * f = ((xn_Cls_AstNode *)xn_arr_o_get(d->kids, i));
    if ((!xn_str_eq(f->kind, rt_string_from_c("AnnotationField")))) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0008"), rt_string_from_c("annotation may only declare fields"), f, d);
      i = xn_int_wrap((i + 1));
      continue;
    }
    xn_arr_s * parts = xn_str_split(f->text, rt_string_from_c(" "));
    if ((((int64_t)parts->len) < 2)) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0008"), rt_string_from_c("malformed annotation field"), f, d);
      i = xn_int_wrap((i + 1));
      continue;
    }
    rt_string * ft = xn_arr_s_get(parts, 0);
    rt_string * fn = xn_arr_s_get(parts, 1);
    if ((!xn_Cls_AnnotationChecker_constantTypeAllowed(self, ft))) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0008"), xn_concat(rt_string_from_c("annotation field type is not constant: "), ft), f, d);
    }
    if (xn_Cls_AnnotationChecker_listHas(self, t->fieldNames, fn)) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0008"), xn_concat(rt_string_from_c("duplicate annotation field: "), fn), f, d);
    }
    int hasDefault = (((int64_t)f->kids->len) > 0);
    if (hasDefault) {
      xn_Cls_AstNode * def = ((xn_Cls_AstNode *)xn_arr_o_get(f->kids, 0));
      if ((!xn_Cls_AnnotationChecker_isConstValue(self, def))) {
        xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0008"), xn_concat(rt_string_from_c("annotation default is not constant: "), fn), f, d);
      }
      else {
        if ((!xn_Cls_AnnotationChecker_accepts(self, ft, def))) {
          xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0008"), xn_concat(rt_string_from_c("annotation default type mismatch: "), fn), f, d);
        }
      }
    }
    xn_Cls_AstNode * dummy = xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), f->line, f->col);
    xn_Cls_AnnotationType_addField(t, fn, ft, (!hasDefault), dummy);
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AnnotationChecker_validateUses(self, d, rt_string_from_c("Annotation"), d);
}

static void xn_Cls_AnnotationChecker_validateUses(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * owner, rt_string * target, xn_Cls_AstNode * scope) {
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)owner->annotations->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(owner->annotations, i));
    xn_Cls_AnnotationChecker_validateUse(self, use, target, owner, owner->annotations, scope, i);
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_AnnotationChecker_validateTypeUses(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * owner, xn_Cls_AstNode * scope) {
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)owner->typeAnnotations->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(owner->typeAnnotations, i));
    xn_Cls_AnnotationChecker_validateUse(self, use, rt_string_from_c("TypeUse"), owner, owner->typeAnnotations, scope, i);
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_AnnotationChecker_validateUse(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * use, rt_string * target, xn_Cls_AstNode * owner, xn_arr_o * uses, xn_Cls_AstNode * scope, int64_t index) {
  if ((!xn_str_eq(use->annotationError, rt_string_from_c("")))) {
    xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0001"), use->annotationError, use, scope);
    return;
  }
  rt_string * name = use->text;
  if ((!xn_str_eq(use->resolvedAnnotationName, rt_string_from_c("")))) {
    name = use->resolvedAnnotationName;
  }
  if (xn_Cls_AnnotationChecker_isReserved(self, name)) {
    xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0001"), xn_concat(rt_string_from_c("reserved annotation cannot be used: @"), name), use, scope);
    return;
  }
  int64_t ti = xn_int_wrap(xn_Cls_AnnotationChecker_findTypeFor(self, name, xn_declPackageOf(owner)));
  if ((ti == xn_int_wrap(-(2)))) {
    xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0001"), xn_concat(rt_string_from_c("ambiguous annotation: @"), name), use, scope);
    return;
  }
  if ((ti < 0)) {
    xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0001"), xn_concat(rt_string_from_c("unknown annotation: @"), name), use, scope);
    return;
  }
  xn_Cls_AnnotationType * t = ((xn_Cls_AnnotationType *)xn_arr_o_get(self->types, ti));
  if (xn_str_eq(name, rt_string_from_c("Repeatable"))) {
    if ((!xn_str_eq(target, rt_string_from_c("Annotation")))) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0011"), rt_string_from_c("@Repeatable only applies to annotation declarations"), use, scope);
    }
    if ((((int64_t)use->kids->len) != 0)) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0011"), rt_string_from_c("@Repeatable takes no arguments"), use, scope);
    }
    return;
  }
  if (xn_str_eq(target, rt_string_from_c(""))) {
  }
  else {
    if ((!xn_Cls_AnnotationChecker_listHas(self, xn_Cls_AnnotationChecker_allTargets(self), target))) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0002"), xn_concat(xn_concat(xn_concat(rt_string_from_c("annotation @"), name), rt_string_from_c(" is not allowed on ")), target), use, scope);
      return;
    }
    else {
      if ((!xn_Cls_AnnotationType_allows(t, target))) {
        xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0002"), xn_concat(xn_concat(xn_concat(rt_string_from_c("annotation @"), name), rt_string_from_c(" is not allowed on ")), target), use, scope);
        return;
      }
    }
  }
  int64_t dup = xn_int_wrap(0);
  int64_t j = xn_int_wrap(0);
  while (((j < index) && (j < ((int64_t)uses->len)))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(uses, j))->text, name)) {
      dup = xn_int_wrap((dup + 1));
    }
    j = xn_int_wrap((j + 1));
  }
  if (((dup > 0) && (!t->repeatable))) {
    xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0003"), xn_concat(xn_concat(rt_string_from_c("duplicate annotation @"), name), rt_string_from_c(" (not @Repeatable)")), use, scope);
    return;
  }
  if (xn_str_eq(name, rt_string_from_c("Target"))) {
    if ((((int64_t)use->kids->len) == 0)) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0009"), rt_string_from_c("@Target needs at least one target"), use, scope);
    }
    int64_t k = xn_int_wrap(0);
    while ((k < ((int64_t)use->kids->len))) {
      xn_Cls_AstNode * arg = ((xn_Cls_AstNode *)xn_arr_o_get(use->kids, k));
      rt_string * p = rt_string_from_c("");
      if ((((int64_t)arg->kids->len) > 0)) {
        p = xn_Cls_AnnotationChecker_pathOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0)));
      }
      if ((!xn_Cls_AnnotationChecker_listHas(self, xn_Cls_AnnotationChecker_allTargets(self), p))) {
        xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0009"), xn_concat(rt_string_from_c("invalid @Target member: "), p), use, scope);
      }
      k = xn_int_wrap((k + 1));
    }
    return;
  }
  if (xn_str_eq(name, rt_string_from_c("Retention"))) {
    if ((((int64_t)use->kids->len) != 1)) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0010"), rt_string_from_c("invalid @Retention member"), use, scope);
    }
    else {
      xn_Cls_AstNode * arg = ((xn_Cls_AstNode *)xn_arr_o_get(use->kids, 0));
      rt_string * p = rt_string_from_c("");
      if ((((int64_t)arg->kids->len) > 0)) {
        p = xn_Cls_AnnotationChecker_pathOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0)));
      }
      if ((!xn_Cls_AnnotationChecker_listHas(self, xn_Cls_AnnotationChecker_retentionNames(self), p))) {
        xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0010"), xn_concat(rt_string_from_c("invalid @Retention member: "), p), use, scope);
      }
    }
    return;
  }
  if (((((xn_str_eq(name, rt_string_from_c("Deprecated")) || xn_str_eq(name, rt_string_from_c("ReadOnly"))) || xn_str_eq(name, rt_string_from_c("WriteOnly"))) || xn_str_eq(name, rt_string_from_c("Override"))) || xn_str_eq(name, rt_string_from_c("MustUse")))) {
    if ((((int64_t)use->kids->len) != 0)) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0005"), xn_concat(xn_concat(rt_string_from_c("annotation @"), name), rt_string_from_c(" takes no arguments")), use, scope);
    }
    return;
  }
  if (xn_str_eq(name, rt_string_from_c("SuppressWarnings"))) {
    if ((((int64_t)use->kids->len) == 0)) {
      xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0015"), rt_string_from_c("@SuppressWarnings needs a diagnostic code"), use, scope);
    }
    int64_t k = xn_int_wrap(0);
    while ((k < ((int64_t)use->kids->len))) {
      xn_Cls_AstNode * arg = ((xn_Cls_AstNode *)xn_arr_o_get(use->kids, k));
      if (((((int64_t)arg->kids->len) == 0) || (!xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0))->kind, rt_string_from_c("String"))))) {
        xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0015"), rt_string_from_c("@SuppressWarnings code must be a String"), use, scope);
      }
      else {
        rt_string * code = xn_Cls_AnnotationChecker_unquote(self, ((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0))->text);
        if ((!xn_Cls_AnnotationChecker_listHas(self, xn_Cls_AnnotationChecker_knownCodes(self), code))) {
          xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0015"), xn_concat(rt_string_from_c("unknown diagnostic code: "), code), use, scope);
        }
        else {
          if (((((xn_str_eq(code, rt_string_from_c("AN0015")) || xn_str_eq(code, rt_string_from_c("AN0016"))) || xn_str_eq(code, rt_string_from_c("AN0017"))) || xn_str_eq(code, rt_string_from_c("AN0018"))) || xn_str_eq(code, rt_string_from_c("AN0019")))) {
            xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0015"), xn_concat(rt_string_from_c("diagnostic code is not suppressible: "), code), use, scope);
          }
        }
      }
      k = xn_int_wrap((k + 1));
    }
    return;
  }
  if ((((int64_t)use->kids->len) > ((int64_t)t->fieldNames->len))) {
    xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0005"), xn_concat(rt_string_from_c("too many arguments for @"), name), use, scope);
    return;
  }
  int64_t k = xn_int_wrap(0);
  while ((k < ((int64_t)t->fieldNames->len))) {
    if ((k < ((int64_t)use->kids->len))) {
      xn_Cls_AstNode * arg = ((xn_Cls_AstNode *)xn_arr_o_get(use->kids, k));
      xn_Cls_AstNode * v = ((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0));
      if ((!xn_Cls_AnnotationChecker_isConstValue(self, v))) {
        xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0007"), xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("argument "), xn_str_int(xn_int_wrap((k + 1)))), rt_string_from_c(" of @")), name), rt_string_from_c(" is not a compile-time constant")), use, scope);
      }
      else {
        if ((!xn_Cls_AnnotationChecker_accepts(self, xn_arr_s_get(t->fieldTypes, k), v))) {
          xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0006"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("argument "), xn_str_int(xn_int_wrap((k + 1)))), rt_string_from_c(" of @")), name), rt_string_from_c(" expects ")), xn_arr_s_get(t->fieldTypes, k)), use, scope);
        }
        else {
          if (xn_str_eq(v->kind, rt_string_from_c("AnnotationUse"))) {
            xn_Cls_AnnotationChecker_validateUse(self, v, rt_string_from_c(""), v, v->annotations, scope, 0);
          }
        }
      }
    }
    else {
      if (xn_str_eq(xn_arr_s_get(t->fieldRequired, k), rt_string_from_c("1"))) {
        xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0004"), xn_concat(xn_concat(xn_concat(rt_string_from_c("missing required argument "), xn_arr_s_get(t->fieldNames, k)), rt_string_from_c(" for @")), name), use, scope);
      }
    }
    k = xn_int_wrap((k + 1));
  }
}

static void xn_Cls_AnnotationChecker_collectDeprecated(xn_Cls_AnnotationChecker *self) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    int dep = xn_Cls_AnnotationChecker_hasUse(self, n, rt_string_from_c("Deprecated"));
    if ((dep && xn_str_eq(n->kind, rt_string_from_c("Func")))) {
      xn_arr_s_push(self->depFuncs, n->text);
    }
    if ((dep && (((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || xn_str_eq(n->kind, rt_string_from_c("Enum"))) || xn_str_eq(n->kind, rt_string_from_c("Protocol"))))) {
      xn_arr_s_push(self->depTypes, n->text);
    }
    if ((dep && xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl")))) {
      xn_arr_s_push(self->depAnnos, n->text);
    }
    if ((dep && xn_str_eq(n->kind, rt_string_from_c("TopField")))) {
      xn_arr_s * tf = xn_str_split(n->text, rt_string_from_c(" "));
      if ((((int64_t)tf->len) >= 2)) {
        xn_arr_s_push(self->depFields, xn_arr_s_get(tf, 1));
      }
    }
    if (((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || xn_str_eq(n->kind, rt_string_from_c("Enum")))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, j));
        if ((xn_str_eq(k->kind, rt_string_from_c("Field")) && xn_Cls_AnnotationChecker_hasUse(self, k, rt_string_from_c("ReadOnly")))) {
          xn_arr_s_push(self->roOwners, n->text);
          xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
          if ((((int64_t)parts->len) >= 2)) {
            xn_arr_s_push(self->roFields, xn_arr_s_get(parts, 1));
          }
        }
        if ((xn_str_eq(k->kind, rt_string_from_c("Method")) && xn_Cls_AnnotationChecker_hasUse(self, k, rt_string_from_c("Deprecated")))) {
          xn_arr_s_push(self->depMethods, k->text);
        }
        if ((xn_str_eq(k->kind, rt_string_from_c("Field")) && xn_Cls_AnnotationChecker_hasUse(self, k, rt_string_from_c("Deprecated")))) {
          xn_arr_s * fp = xn_str_split(k->text, rt_string_from_c(" "));
          if ((((int64_t)fp->len) >= 2)) {
            xn_arr_s_push(self->depFields, xn_arr_s_get(fp, 1));
          }
        }
        if ((xn_str_eq(k->kind, rt_string_from_c("Ctor")) && xn_Cls_AnnotationChecker_hasUse(self, k, rt_string_from_c("Deprecated")))) {
          xn_arr_s_push(self->depCtors, n->text);
        }
        if ((xn_str_eq(k->kind, rt_string_from_c("EnumItem")) && xn_Cls_AnnotationChecker_hasUse(self, k, rt_string_from_c("Deprecated")))) {
          xn_arr_s_push(self->depItems, xn_concat(xn_concat(n->text, rt_string_from_c(".")), k->text));
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
}

static int xn_Cls_AnnotationChecker_hasUse(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->annotations->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->annotations, i))->text, name)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int xn_Cls_AnnotationChecker_isReadOnlyField(xn_Cls_AnnotationChecker *self, rt_string * owner, rt_string * field) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->roFields->len))) {
    if ((xn_str_eq(xn_arr_s_get(self->roOwners, i), owner) && xn_str_eq(xn_arr_s_get(self->roFields, i), field))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_Cls_AnnotationChecker_checkDecl(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, rt_string * target) {
  if (xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl"))) {
    xn_Cls_AnnotationChecker_validateAnnotationDecl(self, n);
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)n->kids->len))) {
      xn_Cls_AnnotationChecker_checkDecl(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), rt_string_from_c("AnnotationField"));
      i = xn_int_wrap((i + 1));
    }
    return;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("AnnotationField"))) {
    return;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("AnnotationUse"))) {
    return;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("AnnotatedExpr"))) {
    if ((((int64_t)n->kids->len) > 0)) {
      xn_Cls_AnnotationChecker_validateUse(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)), rt_string_from_c("Expression"), n, n->annotations, n, 0);
    }
    if ((((int64_t)n->kids->len) > 1)) {
      xn_Cls_AnnotationChecker_checkExpr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)), n);
    }
    return;
  }
  if (xn_Cls_AnnotationChecker_hasError(self)) {
    return;
  }
  rt_string * t = target;
  if (xn_str_eq(n->kind, rt_string_from_c("Program"))) {
    t = rt_string_from_c("");
  }
  else {
    if (xn_str_eq(n->kind, rt_string_from_c("Package"))) {
      t = rt_string_from_c("Package");
    }
    else {
      if ((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || xn_str_eq(n->kind, rt_string_from_c("Enum"))) || xn_str_eq(n->kind, rt_string_from_c("Protocol")))) {
        t = rt_string_from_c("Type");
      }
      else {
        if (((xn_str_eq(n->kind, rt_string_from_c("Func")) || xn_str_eq(n->kind, rt_string_from_c("Method"))) || xn_str_eq(n->kind, rt_string_from_c("Sig")))) {
          t = rt_string_from_c("Method");
        }
        else {
          if (xn_str_eq(n->kind, rt_string_from_c("Ctor"))) {
            t = rt_string_from_c("Constructor");
          }
          else {
            if (xn_str_eq(n->kind, rt_string_from_c("Deinit"))) {
              t = rt_string_from_c("Deinit");
            }
            else {
              if (xn_str_eq(n->kind, rt_string_from_c("Field"))) {
                t = rt_string_from_c("Field");
              }
              else {
                if (xn_str_eq(n->kind, rt_string_from_c("Param"))) {
                  t = rt_string_from_c("Parameter");
                }
                else {
                  if (xn_str_eq(n->kind, rt_string_from_c("TypeParam"))) {
                    t = rt_string_from_c("TypeParameter");
                  }
                  else {
                    if (xn_str_eq(n->kind, rt_string_from_c("EnumItem"))) {
                      t = rt_string_from_c("EnumItem");
                    }
                    else {
                      if (((((((((((((((((((xn_str_eq(n->kind, rt_string_from_c("Local")) || xn_str_eq(n->kind, rt_string_from_c("Block"))) || xn_str_eq(n->kind, rt_string_from_c("Return"))) || xn_str_eq(n->kind, rt_string_from_c("Assign"))) || xn_str_eq(n->kind, rt_string_from_c("ExprStmt"))) || xn_str_eq(n->kind, rt_string_from_c("If"))) || xn_str_eq(n->kind, rt_string_from_c("ForIn"))) || xn_str_eq(n->kind, rt_string_from_c("ForRange"))) || xn_str_eq(n->kind, rt_string_from_c("While"))) || xn_str_eq(n->kind, rt_string_from_c("DoWhile"))) || xn_str_eq(n->kind, rt_string_from_c("Switch"))) || xn_str_eq(n->kind, rt_string_from_c("Case"))) || xn_str_eq(n->kind, rt_string_from_c("Default"))) || xn_str_eq(n->kind, rt_string_from_c("Defer"))) || xn_str_eq(n->kind, rt_string_from_c("Label"))) || xn_str_eq(n->kind, rt_string_from_c("Throw"))) || xn_str_eq(n->kind, rt_string_from_c("Break"))) || xn_str_eq(n->kind, rt_string_from_c("Continue"))) || xn_str_eq(n->kind, rt_string_from_c("Goto")))) {
                        t = n->kind;
                      }
                      else {
                        if (xn_str_eq(n->kind, rt_string_from_c("AnnotationField"))) {
                          return;
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  if ((!xn_str_eq(target, rt_string_from_c("AnnotationField")))) {
    xn_Cls_AnnotationChecker_validateUses(self, n, t, n);
    xn_Cls_AnnotationChecker_validateTypeUses(self, n, n);
  }
  if ((((xn_str_eq(n->kind, rt_string_from_c("Func")) || xn_str_eq(n->kind, rt_string_from_c("Method"))) || xn_str_eq(n->kind, rt_string_from_c("Ctor"))) || xn_str_eq(n->kind, rt_string_from_c("Deinit")))) {
    int64_t i = xn_int_wrap(0);
    while (((i < ((int64_t)n->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
      xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i));
      if (xn_str_eq(k->kind, rt_string_from_c("Param"))) {
        xn_Cls_AnnotationChecker_checkDecl(self, k, rt_string_from_c("Parameter"));
      }
      else {
        if (xn_str_eq(k->kind, rt_string_from_c("Block"))) {
          xn_Cls_AnnotationChecker_checkBlock(self, k, n);
        }
      }
      i = xn_int_wrap((i + 1));
    }
    return;
  }
  if ((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || xn_str_eq(n->kind, rt_string_from_c("Enum"))) || xn_str_eq(n->kind, rt_string_from_c("Protocol")))) {
    int64_t i = xn_int_wrap(0);
    while (((i < ((int64_t)n->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
      xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i));
      if (xn_str_eq(k->kind, rt_string_from_c("TypeParams"))) {
        int64_t j = xn_int_wrap(0);
        while ((j < ((int64_t)k->kids->len))) {
          xn_Cls_AnnotationChecker_checkDecl(self, ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, j)), rt_string_from_c("TypeParameter"));
          j = xn_int_wrap((j + 1));
        }
      }
      else {
        if ((((((xn_str_eq(k->kind, rt_string_from_c("Field")) || xn_str_eq(k->kind, rt_string_from_c("Method"))) || xn_str_eq(k->kind, rt_string_from_c("Ctor"))) || xn_str_eq(k->kind, rt_string_from_c("Deinit"))) || xn_str_eq(k->kind, rt_string_from_c("EnumItem"))) || xn_str_eq(k->kind, rt_string_from_c("Sig")))) {
          xn_Cls_AnnotationChecker_checkDecl(self, k, rt_string_from_c(""));
        }
      }
      i = xn_int_wrap((i + 1));
    }
    return;
  }
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)n->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i));
    if ((!xn_str_eq(k->kind, rt_string_from_c("AnnotationUse")))) {
      xn_Cls_AnnotationChecker_checkDecl(self, k, rt_string_from_c(""));
    }
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_AnnotationChecker_checkBlock(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * block, xn_Cls_AstNode * owner) {
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)block->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AstNode * st = ((xn_Cls_AstNode *)xn_arr_o_get(block->kids, i));
    if (xn_str_eq(st->kind, rt_string_from_c("AnnotationDecl"))) {
      xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0002"), rt_string_from_c("annotation declaration is only allowed at top level"), st, owner);
    }
    else {
      xn_Cls_AnnotationChecker_checkDecl(self, st, st->kind);
      xn_Cls_AnnotationChecker_checkExpr(self, st, owner);
    }
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_AnnotationChecker_checkExpr(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, xn_Cls_AstNode * owner) {
  if (xn_Cls_AnnotationChecker_hasError(self)) {
    return;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Call")) || xn_str_eq(n->kind, rt_string_from_c("MethodCall")))) {
    rt_string * dn = n->text;
    int isDeinitCall = (xn_str_eq(dn, rt_string_from_c("deinit")) || xn_str_endswith(dn, rt_string_from_c(".deinit")));
    if (isDeinitCall) {
      int superCall = xn_str_eq(dn, rt_string_from_c("super.deinit"));
      if ((xn_str_eq(n->kind, rt_string_from_c("MethodCall")) && (((int64_t)n->kids->len) > 0))) {
        superCall = xn_str_eq(xn_Cls_AnnotationChecker_pathOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("super"));
      }
      if ((!superCall)) {
        xn_Cls_AnnotationChecker_fail(self, rt_string_from_c("SEM-001"), rt_string_from_c("deinit cannot be called explicitly"), n);
        return;
      }
    }
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Call")) || xn_str_eq(n->kind, rt_string_from_c("GenericCall")))) {
    if (xn_Cls_AnnotationChecker_listHas(self, self->depFuncs, n->text)) {
      xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0014"), xn_concat(rt_string_from_c("use of deprecated function: "), n->text), n, owner);
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("MethodCall"))) {
    if (xn_Cls_AnnotationChecker_listHas(self, self->depMethods, n->text)) {
      xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0014"), xn_concat(rt_string_from_c("use of deprecated method: "), n->text), n, owner);
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("New"))) {
    if (xn_Cls_AnnotationChecker_listHas(self, self->depTypes, n->text)) {
      xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0014"), xn_concat(rt_string_from_c("use of deprecated type: "), n->text), n, owner);
    }
    if (xn_Cls_AnnotationChecker_listHas(self, self->depCtors, n->text)) {
      xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0014"), xn_concat(rt_string_from_c("use of deprecated constructor: "), n->text), n, owner);
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Member"))) {
    if (xn_Cls_AnnotationChecker_listHas(self, self->depFields, n->text)) {
      xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0014"), xn_concat(rt_string_from_c("use of deprecated field: "), n->text), n, owner);
    }
    rt_string * mp = xn_Cls_AnnotationChecker_pathOf(self, n);
    if (xn_Cls_AnnotationChecker_listHas(self, self->depItems, mp)) {
      xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0014"), xn_concat(rt_string_from_c("use of deprecated enum item: "), mp), n, owner);
    }
  }
  if (xn_str_eq(n->kind, rt_string_from_c("AnnotationUse"))) {
    if (xn_Cls_AnnotationChecker_listHas(self, self->depAnnos, n->text)) {
      xn_Cls_AnnotationChecker_warn(self, rt_string_from_c("AN0014"), xn_concat(rt_string_from_c("use of deprecated annotation: @"), n->text), n, owner);
    }
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_AnnotationChecker_checkExpr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), owner);
    i = xn_int_wrap((i + 1));
  }
}

static rt_string * xn_Cls_AnnotationChecker_paramTypesOf(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * fn) {
  rt_string * res = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fn->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Param"))) {
      xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 1)) {
        if ((!xn_str_eq(res, rt_string_from_c("")))) {
          res = xn_concat(res, rt_string_from_c(","));
        }
        res = xn_concat(res, xn_arr_s_get(parts, 0));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return res;
}

static rt_string * xn_Cls_AnnotationChecker_retOf(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * fn) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fn->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i))->kind, rt_string_from_c("Ret"))) {
      return ((xn_Cls_AstNode *)xn_arr_o_get(fn->kids, i))->text;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("Unit");
}

static int xn_Cls_AnnotationChecker_protocolHasSig(xn_Cls_AnnotationChecker *self, rt_string * pname, rt_string * mname, rt_string * params, rt_string * ret) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(p->kind, rt_string_from_c("Protocol")) && xn_str_eq(p->text, pname))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)p->kids->len))) {
        xn_Cls_AstNode * s = ((xn_Cls_AstNode *)xn_arr_o_get(p->kids, j));
        if ((((xn_str_eq(s->kind, rt_string_from_c("Sig")) && xn_str_eq(s->text, mname)) && xn_str_eq(xn_Cls_AnnotationChecker_paramTypesOf(self, s), params)) && xn_str_eq(xn_Cls_AnnotationChecker_retOf(self, s), ret))) {
          return 1;
        }
        if (xn_str_eq(s->kind, rt_string_from_c("Extends"))) {
          if (xn_Cls_AnnotationChecker_protocolHasSig(self, s->text, mname, params, ret)) {
            return 1;
          }
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_Cls_AnnotationChecker_checkOverrides(xn_Cls_AnnotationChecker *self) {
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)self->program->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AstNode * c = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(c->kind, rt_string_from_c("Class")) || xn_str_eq(c->kind, rt_string_from_c("Struct")))) {
      int64_t j = xn_int_wrap(0);
      while (((j < ((int64_t)c->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
        xn_Cls_AstNode * m = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, j));
        if ((xn_str_eq(m->kind, rt_string_from_c("Method")) && xn_Cls_AnnotationChecker_hasUse(self, m, rt_string_from_c("Override")))) {
          xn_arr_s *impls = xn_arr_s_new(0);
          int64_t k = xn_int_wrap(0);
          while ((k < ((int64_t)c->kids->len))) {
            if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(c->kids, k))->kind, rt_string_from_c("Implements"))) {
              xn_arr_s_push(impls, ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, k))->text);
            }
            k = xn_int_wrap((k + 1));
          }
          int found = 0;
          k = 0;
          while ((k < ((int64_t)impls->len))) {
            if (xn_Cls_AnnotationChecker_protocolHasSig(self, xn_arr_s_get(impls, k), m->text, xn_Cls_AnnotationChecker_paramTypesOf(self, m), xn_Cls_AnnotationChecker_retOf(self, m))) {
              found = 1;
            }
            k = xn_int_wrap((k + 1));
          }
          if ((!found)) {
            xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0013"), xn_concat(rt_string_from_c("@Override method has no matching protocol signature: "), m->text), m, m);
          }
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
}

static rt_string * xn_Cls_AnnotationChecker_lookupVar(xn_Cls_AnnotationChecker *self, xn_arr_s * names, xn_arr_s * types, rt_string * name) {
  int64_t i = xn_int_wrap(xn_int_wrap((((int64_t)names->len) - 1)));
  while ((i >= 0)) {
    if (xn_str_eq(xn_arr_s_get(names, i), name)) {
      return xn_arr_s_get(types, i);
    }
    i = xn_int_wrap((i - 1));
  }
  return rt_string_from_c("");
}

static void xn_Cls_AnnotationChecker_popVars(xn_Cls_AnnotationChecker *self, xn_arr_s * names, xn_arr_s * types, int64_t mark) {
  while ((((int64_t)names->len) > mark)) {
    xn_arr_s_remove(names, xn_int_wrap((((int64_t)names->len) - 1)));
    xn_arr_s_remove(types, xn_int_wrap((((int64_t)types->len) - 1)));
  }
}

static void xn_Cls_AnnotationChecker_checkReadOnlyIn(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * n, rt_string * cls, xn_arr_s * names, xn_arr_s * types, xn_Cls_AstNode * owner) {
  int64_t mark = xn_int_wrap(((int64_t)names->len));
  if (xn_str_eq(n->kind, rt_string_from_c("Local"))) {
    xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
    if ((((int64_t)parts->len) >= 2)) {
      xn_arr_s_push(names, xn_arr_s_get(parts, 1));
      xn_arr_s_push(types, xn_arr_s_get(parts, 0));
    }
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Assign")) && (((int64_t)n->kids->len) >= 2))) {
    xn_Cls_AstNode * left = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0));
    if ((xn_str_eq(left->kind, rt_string_from_c("Member")) && (((int64_t)left->kids->len) > 0))) {
      xn_Cls_AstNode * base = ((xn_Cls_AstNode *)xn_arr_o_get(left->kids, 0));
      rt_string * ownerType = rt_string_from_c("");
      if (xn_str_eq(base->kind, rt_string_from_c("Name"))) {
        if (xn_str_eq(base->text, rt_string_from_c("self"))) {
          ownerType = cls;
        }
        else {
          ownerType = xn_Cls_AnnotationChecker_lookupVar(self, names, types, base->text);
          if ((xn_str_eq(ownerType, rt_string_from_c("")) && xn_Cls_AnnotationChecker_listHas(self, self->classNames, base->text))) {
            ownerType = base->text;
          }
        }
      }
      if ((((!xn_str_eq(ownerType, rt_string_from_c(""))) && xn_Cls_AnnotationChecker_isReadOnlyField(self, ownerType, left->text)) && (!xn_str_eq(ownerType, cls)))) {
        xn_Cls_AnnotationChecker_failAt(self, rt_string_from_c("AN0012"), xn_concat(xn_concat(xn_concat(rt_string_from_c("write to @ReadOnly field outside its declaring type: "), ownerType), rt_string_from_c(".")), left->text), left, owner);
      }
    }
  }
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)n->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AnnotationChecker_checkReadOnlyIn(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), cls, names, types, owner);
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AnnotationChecker_popVars(self, names, types, mark);
}

static void xn_Cls_AnnotationChecker_checkReadOnlyWrites(xn_Cls_AnnotationChecker *self) {
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)self->program->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || xn_str_eq(n->kind, rt_string_from_c("Enum")))) {
      xn_Cls_AnnotationChecker_roCheckMembers(self, n, n->text);
    }
    if (xn_str_eq(n->kind, rt_string_from_c("Func"))) {
      xn_arr_s *names = xn_arr_s_new(0);
      xn_arr_s *types = xn_arr_s_new(0);
      int64_t k = xn_int_wrap(0);
      while ((k < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, k));
        if (xn_str_eq(p->kind, rt_string_from_c("Param"))) {
          xn_arr_s * parts = xn_str_split(p->text, rt_string_from_c(" "));
          if ((((int64_t)parts->len) >= 2)) {
            xn_arr_s_push(names, xn_arr_s_get(parts, 1));
            xn_arr_s_push(types, xn_arr_s_get(parts, 0));
          }
        }
        k = xn_int_wrap((k + 1));
      }
      k = 0;
      while (((k < ((int64_t)n->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, k))->kind, rt_string_from_c("Block"))) {
          xn_Cls_AnnotationChecker_checkReadOnlyIn(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, k)), rt_string_from_c(""), names, types, n);
        }
        k = xn_int_wrap((k + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_AnnotationChecker_roCheckMembers(xn_Cls_AnnotationChecker *self, xn_Cls_AstNode * c, rt_string * cls) {
  int64_t j = xn_int_wrap(0);
  while (((j < ((int64_t)c->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AstNode * m = ((xn_Cls_AstNode *)xn_arr_o_get(c->kids, j));
    if ((xn_str_eq(m->kind, rt_string_from_c("Method")) || xn_str_eq(m->kind, rt_string_from_c("Ctor")))) {
      xn_arr_s *names = xn_arr_s_new(0);
      xn_arr_s *types = xn_arr_s_new(0);
      xn_arr_s_push(names, rt_string_from_c("self"));
      xn_arr_s_push(types, cls);
      int64_t k = xn_int_wrap(0);
      while ((k < ((int64_t)m->kids->len))) {
        xn_Cls_AstNode * p = ((xn_Cls_AstNode *)xn_arr_o_get(m->kids, k));
        if (xn_str_eq(p->kind, rt_string_from_c("Param"))) {
          xn_arr_s * parts = xn_str_split(p->text, rt_string_from_c(" "));
          if ((((int64_t)parts->len) >= 2)) {
            xn_arr_s_push(names, xn_arr_s_get(parts, 1));
            xn_arr_s_push(types, xn_arr_s_get(parts, 0));
          }
        }
        k = xn_int_wrap((k + 1));
      }
      k = 0;
      while (((k < ((int64_t)m->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(m->kids, k))->kind, rt_string_from_c("Block"))) {
          xn_Cls_AnnotationChecker_checkReadOnlyIn(self, ((xn_Cls_AstNode *)xn_arr_o_get(m->kids, k)), cls, names, types, m);
        }
        k = xn_int_wrap((k + 1));
      }
    }
    j = xn_int_wrap((j + 1));
  }
}

static void xn_Cls_AnnotationChecker_check(xn_Cls_AnnotationChecker *self) {
  xn_Cls_AnnotationChecker_initBuiltins(self);
  xn_Cls_AnnotationChecker_collectTypes(self);
  if (xn_Cls_AnnotationChecker_hasError(self)) {
    return;
  }
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)self->program->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl"))) {
      xn_Cls_AnnotationChecker_validateAnnotationDecl(self, n);
    }
    i = xn_int_wrap((i + 1));
  }
  if (xn_Cls_AnnotationChecker_hasError(self)) {
    return;
  }
  xn_Cls_AnnotationChecker_collectDeprecated(self);
  i = 0;
  while (((i < ((int64_t)self->program->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AnnotationChecker_checkDecl(self, ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i)), rt_string_from_c(""));
    i = xn_int_wrap((i + 1));
  }
  if (xn_Cls_AnnotationChecker_hasError(self)) {
    return;
  }
  xn_Cls_AnnotationChecker_checkOverrides(self);
  if (xn_Cls_AnnotationChecker_hasError(self)) {
    return;
  }
  xn_Cls_AnnotationChecker_checkReadOnlyWrites(self);
  if (xn_Cls_AnnotationChecker_hasError(self)) {
    return;
  }
  i = 0;
  while (((i < ((int64_t)self->program->kids->len)) && (!xn_Cls_AnnotationChecker_hasError(self)))) {
    xn_Cls_AnnotationChecker_checkExpr(self, ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i)), ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i)));
    i = xn_int_wrap((i + 1));
  }
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
  xn_arr_o * warnings;
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
  xn_obj->warnings = xn_arr_o_new(4);
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
  self->warnings = xn_arr_o_new(0);
  self->error = rt_string_from_c("");
  self->errorCode = rt_string_from_c("");
  self->errorLine = 1;
  self->errorCol = 1;
  self->curRet = rt_string_from_c("Unit");
  self->curClass = rt_string_from_c("");
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
static rt_string * xn_Cls_Checker_demangleType(xn_Cls_Checker *self, rt_string * ty);
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
  if (((((((((((((xn_str_eq(ty, rt_string_from_c("Int")) || xn_str_eq(ty, rt_string_from_c("String"))) || xn_str_eq(ty, rt_string_from_c("Bool"))) || xn_str_eq(ty, rt_string_from_c("Unit"))) || xn_str_eq(ty, rt_string_from_c("Char"))) || xn_str_eq(ty, rt_string_from_c("Double"))) || xn_str_eq(ty, rt_string_from_c("Float"))) || xn_str_eq(ty, rt_string_from_c("Long"))) || xn_str_eq(ty, rt_string_from_c("Int64"))) || xn_str_eq(ty, rt_string_from_c("Int32"))) || xn_str_eq(ty, rt_string_from_c("UInt16"))) || xn_str_eq(ty, rt_string_from_c("Int128"))) || xn_str_eq(ty, rt_string_from_c("void")))) {
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

static rt_string * xn_Cls_Checker_demangleType(xn_Cls_Checker *self, rt_string * ty) {
  int64_t u = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("__")));
  if ((u < 0)) {
    return ty;
  }
  rt_string * base = xn_str_substr(ty, 0, u);
  rt_string * rest = xn_str_substr(ty, xn_int_wrap((u + 2)), xn_int_wrap((xn_int_wrap((((int64_t)ty->len) - u)) - 2)));
  if (((((int64_t)rest->len) > 0) && xn_str_eq(xn_str_substr(rest, xn_int_wrap((((int64_t)rest->len) - 1)), 1), rt_string_from_c("_")))) {
    rest = xn_str_substr(rest, 0, xn_int_wrap((((int64_t)rest->len) - 1)));
  }
  if (xn_str_eq(rest, rt_string_from_c(""))) {
    return ty;
  }
  xn_arr_s * parts = xn_str_split(rest, rt_string_from_c("_"));
  rt_string * joined = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)parts->len))) {
    if ((!xn_str_eq(xn_arr_s_get(parts, i), rt_string_from_c("")))) {
      if ((!xn_str_eq(joined, rt_string_from_c("")))) {
        joined = xn_concat(joined, rt_string_from_c(","));
      }
      joined = xn_concat(joined, xn_arr_s_get(parts, i));
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_concat(xn_concat(xn_concat(base, rt_string_from_c("<")), joined), rt_string_from_c(">"));
}

static int xn_Cls_Checker_sameType(xn_Cls_Checker *self, rt_string * a, rt_string * b) {
  if (xn_str_eq(a, b)) {
    return 1;
  }
  rt_string * da = xn_Cls_Checker_demangleType(self, a);
  rt_string * db = xn_Cls_Checker_demangleType(self, b);
  if (((!xn_str_eq(da, a)) || (!xn_str_eq(db, b)))) {
    return xn_Cls_Checker_sameType(self, da, db);
  }
  if ((xn_str_eq(b, rt_string_from_c("Null")) && (xn_str_eq(a, rt_string_from_c("Any")) || ((((int64_t)a->len) > 1) && xn_str_eq(xn_str_substr(a, xn_int_wrap((((int64_t)a->len) - 1)), 1), rt_string_from_c("?")))))) {
    return 1;
  }
  if ((xn_str_eq(a, rt_string_from_c("Null")) && (xn_str_eq(b, rt_string_from_c("Any")) || ((((int64_t)b->len) > 1) && xn_str_eq(xn_str_substr(b, xn_int_wrap((((int64_t)b->len) - 1)), 1), rt_string_from_c("?")))))) {
    return 1;
  }
  if ((xn_Cls_Checker_isListType(self, a) && xn_Cls_Checker_isListType(self, b))) {
    return xn_Cls_Checker_sameType(self, xn_Cls_Checker_elementType(self, a), xn_Cls_Checker_elementType(self, b));
  }
  if (((((xn_str_eq(a, rt_string_from_c("Int")) || xn_str_eq(a, rt_string_from_c("Int32"))) || xn_str_eq(a, rt_string_from_c("Int64"))) || xn_str_eq(a, rt_string_from_c("Long"))) && (((xn_str_eq(b, rt_string_from_c("Int")) || xn_str_eq(b, rt_string_from_c("Int32"))) || xn_str_eq(b, rt_string_from_c("Int64"))) || xn_str_eq(b, rt_string_from_c("Long"))))) {
    return 1;
  }
  if (((xn_str_eq(a, rt_string_from_c("Float")) || xn_str_eq(a, rt_string_from_c("Double"))) && (xn_str_eq(b, rt_string_from_c("Float")) || xn_str_eq(b, rt_string_from_c("Double"))))) {
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
  xn_Cls_AnnotationChecker * ann = xn_Cls_AnnotationChecker_new(self->file, self->program);
  xn_Cls_AnnotationChecker_check(ann);
  int64_t ai = xn_int_wrap(0);
  while ((ai < ((int64_t)ann->warnings->len))) {
    xn_arr_o_push(self->warnings, ((xn_Cls_AnnotationDiag *)xn_arr_o_get(ann->warnings, ai)));
    ai = xn_int_wrap((ai + 1));
  }
  if (xn_Cls_AnnotationChecker_hasError(ann)) {
    self->error = ann->error;
    self->errorCode = ann->errorCode;
    self->errorLine = ann->errorLine;
    self->errorCol = ann->errorCol;
    return;
  }
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
  int64_t deinitCount = xn_int_wrap(0);
  int64_t i = xn_int_wrap(0);
  while (((i < ((int64_t)cls->kids->len)) && (!xn_Cls_Checker_hasError(self)))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Deinit"))) {
      deinitCount = xn_int_wrap((deinitCount + 1));
      if ((deinitCount > 1)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), xn_concat(rt_string_from_c("duplicate deinit in "), cls->text), k);
      }
    }
    if (xn_str_eq(k->kind, rt_string_from_c("Field"))) {
      xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        if ((!xn_Cls_Checker_knownType(self, xn_arr_s_get(parts, 0)))) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-005"), xn_concat(rt_string_from_c("unknown field type: "), xn_arr_s_get(parts, 0)), k);
        }
        if ((((int64_t)k->kids->len) > 0)) {
          rt_string * it = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, 0)));
          if ((((!xn_str_eq(it, rt_string_from_c("Error"))) && (!xn_Cls_Checker_sameType(self, xn_arr_s_get(parts, 0), it))) && (!(xn_Cls_Checker_isEmptyArray(self, ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, 0))) && xn_Cls_Checker_isListType(self, xn_arr_s_get(parts, 0)))))) {
            xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("field "), xn_arr_s_get(parts, 1)), rt_string_from_c(" expects ")), xn_arr_s_get(parts, 0)), rt_string_from_c(", got ")), it), k);
          }
        }
      }
    }
    if (((xn_str_eq(k->kind, rt_string_from_c("Method")) || xn_str_eq(k->kind, rt_string_from_c("Ctor"))) || xn_str_eq(k->kind, rt_string_from_c("Deinit")))) {
      xn_Cls_Checker_checkFunc(self, k);
    }
    i = xn_int_wrap((i + 1));
  }
  self->curClass = rt_string_from_c("");
}

static void xn_Cls_Checker_checkFunc(xn_Cls_Checker *self, xn_Cls_AstNode * fn) {
  if ((xn_str_eq(fn->kind, rt_string_from_c("Ctor")) || xn_str_eq(fn->kind, rt_string_from_c("Deinit")))) {
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
  if (xn_str_eq(n->kind, rt_string_from_c("Long"))) {
    return rt_string_from_c("Long");
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
    if (((((xn_str_eq(lt, rt_string_from_c("Double")) || xn_str_eq(rt, rt_string_from_c("Double"))) || xn_str_eq(lt, rt_string_from_c("Float"))) || xn_str_eq(rt, rt_string_from_c("Float"))) && (!xn_str_eq(n->text, rt_string_from_c("%"))))) {
      if ((((xn_str_eq(lt, rt_string_from_c("Double")) || xn_str_eq(lt, rt_string_from_c("Float"))) || xn_str_eq(lt, rt_string_from_c("Int"))) && ((xn_str_eq(rt, rt_string_from_c("Double")) || xn_str_eq(rt, rt_string_from_c("Float"))) || xn_str_eq(rt, rt_string_from_c("Int"))))) {
        return rt_string_from_c("Double");
      }
    }
    if (((xn_str_eq(n->text, rt_string_from_c("&")) || xn_str_eq(n->text, rt_string_from_c("|"))) || xn_str_eq(n->text, rt_string_from_c("^")))) {
      if ((xn_str_eq(lt, rt) && (((xn_str_eq(lt, rt_string_from_c("Int")) || xn_str_eq(lt, rt_string_from_c("Long"))) || xn_str_eq(lt, rt_string_from_c("Int32"))) || xn_str_eq(lt, rt_string_from_c("Int64"))))) {
        return lt;
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("operator "), n->text), rt_string_from_c(" needs matching Int/Long, got ")), lt), rt_string_from_c("/")), rt), n);
      return rt_string_from_c("Error");
    }
    if ((xn_str_eq(n->text, rt_string_from_c("<<")) || xn_str_eq(n->text, rt_string_from_c(">>")))) {
      int wideLeft = ((xn_str_eq(lt, rt_string_from_c("Long")) || xn_str_eq(lt, rt_string_from_c("Int64"))) || xn_str_eq(lt, rt_string_from_c("Int32")));
      int narrowLeft = xn_str_eq(lt, rt_string_from_c("Int"));
      int shiftCount = (((xn_str_eq(rt, rt_string_from_c("Int")) || xn_str_eq(rt, rt_string_from_c("Int32"))) || xn_str_eq(rt, rt_string_from_c("Int64"))) || xn_str_eq(rt, rt_string_from_c("Long")));
      if (((wideLeft || narrowLeft) && shiftCount)) {
        if (wideLeft) {
          return lt;
        }
        return rt_string_from_c("Int");
      }
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("operator "), n->text), rt_string_from_c(" needs Int/Long left and Int right, got ")), lt), rt_string_from_c("/")), rt), n);
      return rt_string_from_c("Error");
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
  if (xn_str_eq(n->kind, rt_string_from_c("Long"))) {
    return rt_string_from_c("Long");
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
    if ((((xn_str_eq(xn_Cls_Checker_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("Double")) || xn_str_eq(xn_Cls_Checker_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1))), rt_string_from_c("Double"))) || xn_str_eq(xn_Cls_Checker_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("Float"))) || xn_str_eq(xn_Cls_Checker_syntacticType(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1))), rt_string_from_c("Float")))) {
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
    if (xn_str_eq(mth, rt_string_from_c("wait"))) {
      if ((argc != 0)) {
        xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Context.wait expects 0 arguments"), n);
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
    if (xn_str_eq(mth, rt_string_from_c("copy"))) {
      return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_Checker_elementType(self, bt)), rt_string_from_c(">"));
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
  if (xn_str_eq(n->text, rt_string_from_c("Context.withCancel"))) {
    if ((argc != 1)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Context.withCancel expects 1 argument"), n);
      return rt_string_from_c("Context");
    }
    rt_string * pt = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (((!xn_str_eq(pt, rt_string_from_c("Error"))) && (!xn_str_eq(pt, rt_string_from_c("Context"))))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(rt_string_from_c("Context.withCancel expects Context, got "), pt), n);
    }
    return rt_string_from_c("Context");
  }
  if ((xn_str_eq(n->text, rt_string_from_c("Context.withDeadline")) || xn_str_eq(n->text, rt_string_from_c("Context.withTimeout")))) {
    if ((argc != 2)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), xn_concat(n->text, rt_string_from_c(" expects 2 arguments")), n);
      return rt_string_from_c("Context");
    }
    rt_string * pt = xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (((!xn_str_eq(pt, rt_string_from_c("Error"))) && (!xn_str_eq(pt, rt_string_from_c("Context"))))) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-003"), xn_concat(xn_concat(n->text, rt_string_from_c(" expects Context, got ")), pt), n);
    }
    xn_Cls_Checker_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
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
  if (xn_str_eq(n->text, rt_string_from_c("super.deinit"))) {
    return rt_string_from_c("Unit");
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
      if (xn_str_eq(mth, rt_string_from_c("wait"))) {
        if ((argc != 0)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Context.wait expects 0 arguments"), n);
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
      if (xn_str_eq(mth, rt_string_from_c("alloc"))) {
        if ((argc != 1)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Bytes.alloc expects 1 argument"), n);
        }
        return rt_string_from_c("Bytes");
      }
      if (xn_str_eq(mth, rt_string_from_c("empty"))) {
        if ((argc != 0)) {
          xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("Bytes.empty expects 0 arguments"), n);
        }
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
      if (xn_str_eq(mth, rt_string_from_c("copy"))) {
        return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_Checker_elementType(self, bt)), rt_string_from_c(">"));
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
  if (xn_str_eq(n->text, rt_string_from_c("xdkAnnotationRegistry"))) {
    if ((argc != 0)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("xdkAnnotationRegistry expects 0 arguments"), n);
      return rt_string_from_c("Error");
    }
    if ((xn_Cls_Checker_findClass(self, rt_string_from_c("AnnotationRegistry")) < 0)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), rt_string_from_c("xdkAnnotationRegistry requires import xdk.annotations"), n);
      return rt_string_from_c("Error");
    }
    return rt_string_from_c("AnnotationRegistry");
  }
  if (xn_str_eq(n->text, rt_string_from_c("xdkAnnotationRegistryVersion"))) {
    if ((argc != 0)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-004"), rt_string_from_c("xdkAnnotationRegistryVersion expects 0 arguments"), n);
      return rt_string_from_c("Error");
    }
    if ((xn_Cls_Checker_findClass(self, rt_string_from_c("AnnotationRegistry")) < 0)) {
      xn_Cls_Checker_fail(self, rt_string_from_c("SEM-001"), rt_string_from_c("xdkAnnotationRegistryVersion requires import xdk.annotations"), n);
      return rt_string_from_c("Error");
    }
    return rt_string_from_c("Int");
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

struct xn_Cls_AnnotationUseMeta {
  rt_header hdr;
  xn_Cls_AstNode * use;
  xn_Cls_AstNode * decl;
  rt_string * typeName;
  rt_string * target;
  rt_string * targetName;
  int64_t repeatIndex;
};

static const rt_type RT_TYPE_XN_AnnotationUseMeta = { "AnnotationUseMeta", sizeof(xn_Cls_AnnotationUseMeta), NULL, NULL };

static xn_Cls_AnnotationUseMeta *xn_Cls_AnnotationUseMeta_new(xn_Cls_AstNode * use, xn_Cls_AstNode * decl, rt_string * typeName, rt_string * target, rt_string * targetName, int64_t repeatIndex) {
  xn_Cls_AnnotationUseMeta *xn_obj = (xn_Cls_AnnotationUseMeta *)rt_gc_new(&RT_TYPE_XN_AnnotationUseMeta);
  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_AnnotationUseMeta) - sizeof(rt_header));
  xn_obj->use = 0;
  xn_obj->decl = 0;
  xn_obj->typeName = rt_string_from_c("");
  xn_obj->target = rt_string_from_c("");
  xn_obj->targetName = rt_string_from_c("");
  xn_obj->repeatIndex = 0;
  xn_Cls_AnnotationUseMeta *self = xn_obj;
  self->use = use;
  self->decl = decl;
  self->typeName = typeName;
  self->target = target;
  self->targetName = targetName;
  self->repeatIndex = repeatIndex;
  return xn_obj;
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
static int xn_Cls_CGen_literalHasNul(xn_Cls_CGen *self, rt_string * text);
static int xn_Cls_CGen_charNeedsU(xn_Cls_CGen *self, rt_string * text);
static rt_string * xn_Cls_CGen_expr(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static void xn_Cls_CGen_local(xn_Cls_CGen *self, xn_Cls_AstNode * st, rt_string * indent);
static void xn_Cls_CGen_stmt(xn_Cls_CGen *self, xn_Cls_AstNode * st, rt_string * indent);
static void xn_Cls_CGen_emitDefers(xn_Cls_CGen *self, rt_string * indent, int includeErr);
static void xn_Cls_CGen_blockBody(xn_Cls_CGen *self, xn_Cls_AstNode * block, rt_string * indent);
static int xn_Cls_CGen_methodStatic(xn_Cls_CGen *self, xn_Cls_AstNode * m);
static rt_string * xn_Cls_CGen_methodSig(xn_Cls_CGen *self, xn_Cls_AstNode * m, rt_string * cls);
static void xn_Cls_CGen_method(xn_Cls_CGen *self, xn_Cls_AstNode * m, rt_string * cls);
static xn_Cls_AstNode * xn_Cls_CGen_ctorOf(xn_Cls_CGen *self, xn_Cls_AstNode * cls);
static xn_Cls_AstNode * xn_Cls_CGen_deinitOf(xn_Cls_CGen *self, xn_Cls_AstNode * cls);
static rt_string * xn_Cls_CGen_baseNameOf(xn_Cls_CGen *self, xn_Cls_AstNode * cls);
static xn_Cls_AstNode * xn_Cls_CGen_classByName(xn_Cls_CGen *self, rt_string * name);
static int xn_Cls_CGen_hasSuperDeinitCall(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static void xn_Cls_CGen_deinitMethod(xn_Cls_CGen *self, xn_Cls_AstNode * d, rt_string * cn);
static void xn_Cls_CGen_genClass(xn_Cls_CGen *self, xn_Cls_AstNode * cls);
static rt_string * xn_Cls_CGen_funcProto(xn_Cls_CGen *self, xn_Cls_AstNode * fn);
static void xn_Cls_CGen_func(xn_Cls_CGen *self, xn_Cls_AstNode * fn);
static rt_string * xn_Cls_CGen_annotationPackageName(xn_Cls_CGen *self);
static rt_string * xn_Cls_CGen_annotationQualifiedFor(xn_Cls_CGen *self, rt_string * name, rt_string * ownerPkg);
static rt_string * xn_Cls_CGen_annotationQualified(xn_Cls_CGen *self, rt_string * name);
static rt_string * xn_Cls_CGen_typeTextOf(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static int xn_Cls_CGen_knownTypeName(xn_Cls_CGen *self, rt_string * ty);
static rt_string * xn_Cls_CGen_qualifiedTypeName(xn_Cls_CGen *self, rt_string * ty, rt_string * ownerPkg);
static void xn_Cls_CGen_collectTypeUses(xn_Cls_CGen *self, xn_Cls_AstNode * node, rt_string * targetName, rt_string * ownerPkg, xn_arr_o * out);
static void xn_Cls_CGen_collectTypeUseLocals(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * methodOwner, rt_string * ownerPkg, xn_arr_o * out);
static rt_string * xn_Cls_CGen_annotationStringText(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_CGen_annotationPath(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_CGen_annotationLastSegment(xn_Cls_CGen *self, rt_string * path);
static xn_Cls_AstNode * xn_Cls_CGen_annotationFindDeclFor(xn_Cls_CGen *self, rt_string * name, rt_string * ownerPkg);
static rt_string * xn_Cls_CGen_annotationRetention(xn_Cls_CGen *self, xn_Cls_AstNode * decl);
static xn_arr_o * xn_Cls_CGen_annotationFields(xn_Cls_CGen *self, xn_Cls_AstNode * decl);
static rt_string * xn_Cls_CGen_annotationFieldType(xn_Cls_CGen *self, xn_Cls_AstNode * f);
static rt_string * xn_Cls_CGen_annotationFieldName(xn_Cls_CGen *self, xn_Cls_AstNode * f);
static rt_string * xn_Cls_CGen_annotationParamTypes(xn_Cls_CGen *self, xn_Cls_AstNode * fn);
static void xn_Cls_CGen_collectAnnotationUses(xn_Cls_CGen *self, xn_Cls_AstNode * node, rt_string * target, rt_string * targetName, xn_arr_o * out);
static void xn_Cls_CGen_collectAnnotationParams(xn_Cls_CGen *self, xn_Cls_AstNode * fn, rt_string * memberTarget, xn_arr_o * out);
static void xn_Cls_CGen_collectAnnotationClass(xn_Cls_CGen *self, xn_Cls_AstNode * cls, xn_arr_o * out);
static xn_arr_o * xn_Cls_CGen_collectGeneratedAnnotations(xn_Cls_CGen *self);
static rt_string * xn_Cls_CGen_annotationNumberText(xn_Cls_CGen *self, xn_Cls_AstNode * n);
static rt_string * xn_Cls_CGen_emitAnnotationValue(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * expected, rt_string * indent);
static rt_string * xn_Cls_CGen_emitAnnotationInfo(xn_Cls_CGen *self, xn_Cls_AstNode * use, xn_Cls_AstNode * decl, rt_string * typeName, rt_string * target, rt_string * targetName, int64_t repeatIndex, rt_string * indent);
static void xn_Cls_CGen_emitAnnotationRegistry(xn_Cls_CGen *self);
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
  if ((xn_str_eq(ty, rt_string_from_c("Double")) || xn_str_eq(ty, rt_string_from_c("Float")))) {
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
    if (xn_Cls_CGen_isArray(self, elementType)) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("(("), xn_Cls_CGen_arrayCName(self, elementType)), rt_string_from_c(" *)")), call), rt_string_from_c(")"));
    }
    if (xn_Cls_CGen_isMap(self, elementType)) {
      return xn_concat(xn_concat(rt_string_from_c("((xn_map_g *)"), call), rt_string_from_c(")"));
    }
    if (xn_Cls_CGen_isSet(self, elementType)) {
      return xn_concat(xn_concat(rt_string_from_c("((xn_set_g *)"), call), rt_string_from_c(")"));
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
  if (xn_str_eq(n->kind, rt_string_from_c("Long"))) {
    return rt_string_from_c("Long");
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
    if (xn_str_eq(mth, rt_string_from_c("wait"))) {
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
    if (xn_str_eq(mth, rt_string_from_c("alloc"))) {
      return rt_string_from_c("Bytes");
    }
    if (xn_str_eq(mth, rt_string_from_c("empty"))) {
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
    if (xn_str_eq(mth, rt_string_from_c("copy"))) {
      return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_CGen_elementType(self, bt)), rt_string_from_c(">"));
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
    if (xn_str_eq(mth, rt_string_from_c("wait"))) {
      return xn_concat(xn_concat(rt_string_from_c("xrt_context_wait("), bv), rt_string_from_c(")"));
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
    if (xn_str_eq(mth, rt_string_from_c("copy"))) {
      return xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_copy(")), bv), rt_string_from_c(")"));
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
  if (xn_str_eq(n->kind, rt_string_from_c("Long"))) {
    return rt_string_from_c("Long");
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
    if ((((xn_str_eq(xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("Double")) || xn_str_eq(xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1))), rt_string_from_c("Double"))) || xn_str_eq(xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))), rt_string_from_c("Float"))) || xn_str_eq(xn_Cls_CGen_typeOf(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1))), rt_string_from_c("Float")))) {
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
    if (xn_str_eq(n->text, rt_string_from_c("super.deinit"))) {
      return rt_string_from_c("Unit");
    }
    if (xn_str_eq(n->text, rt_string_from_c("xdkAnnotationRegistry"))) {
      return rt_string_from_c("AnnotationRegistry");
    }
    if (xn_str_eq(n->text, rt_string_from_c("xdkAnnotationRegistryVersion"))) {
      return rt_string_from_c("Int");
    }
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
    if (((xn_str_eq(n->text, rt_string_from_c("Context.withCancel")) || xn_str_eq(n->text, rt_string_from_c("Context.withDeadline"))) || xn_str_eq(n->text, rt_string_from_c("Context.withTimeout")))) {
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
        if (xn_str_eq(mth, rt_string_from_c("wait"))) {
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
        if (xn_str_eq(mth, rt_string_from_c("alloc"))) {
          return rt_string_from_c("Bytes");
        }
        if (xn_str_eq(mth, rt_string_from_c("empty"))) {
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
        if (xn_str_eq(mth, rt_string_from_c("copy"))) {
          return xn_concat(xn_concat(rt_string_from_c("List<"), xn_Cls_CGen_elementType(self, bt)), rt_string_from_c(">"));
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

static int xn_Cls_CGen_literalHasNul(xn_Cls_CGen *self, rt_string * text) {
  return (xn_str_indexof(text, rt_string_new("\\000", sizeof("\\000") - 1)) >= 0);
}

static int xn_Cls_CGen_charNeedsU(xn_Cls_CGen *self, rt_string * text) {
  if ((((int64_t)text->len) < 2)) {
    return 0;
  }
  rt_string * content = xn_str_substr(text, 1, xn_int_wrap((((int64_t)text->len) - 2)));
  if ((((int64_t)content->len) <= 1)) {
    return 0;
  }
  if (((((((xn_str_eq(content, rt_string_from_c("\\n")) || xn_str_eq(content, rt_string_from_c("\\r"))) || xn_str_eq(content, rt_string_from_c("\\t"))) || xn_str_eq(content, rt_string_from_c("\\0"))) || xn_str_eq(content, rt_string_from_c("\\\\"))) || xn_str_eq(content, rt_string_from_c("\\'"))) || xn_str_eq(content, rt_string_from_c("\\\"")))) {
    return 0;
  }
  return 1;
}

static rt_string * xn_Cls_CGen_expr(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Int"))) {
    if ((!xn_Cls_CGen_intLiteralFits64(self, n->text))) {
      return xn_concat(xn_concat(rt_string_from_c("xn_int128_from_dec(\""), n->text), rt_string_from_c("\")"));
    }
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Long"))) {
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Double"))) {
    return n->text;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    if (xn_Cls_CGen_literalHasNul(self, n->text)) {
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("rt_string_new("), n->text), rt_string_from_c(", sizeof(")), n->text), rt_string_from_c(") - 1)"));
    }
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
    if (xn_Cls_CGen_charNeedsU(self, n->text)) {
      return xn_concat(xn_concat(rt_string_from_c("((int32_t)U"), n->text), rt_string_from_c(")"));
    }
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
    if ((((xn_str_eq(lt, rt_string_from_c("Long")) || xn_str_eq(lt, rt_string_from_c("Int64"))) || xn_str_eq(lt, rt_string_from_c("Int32"))) && (((xn_str_eq(rt, rt_string_from_c("Int")) || xn_str_eq(rt, rt_string_from_c("Int32"))) || xn_str_eq(rt, rt_string_from_c("Int64"))) || xn_str_eq(rt, rt_string_from_c("Long"))))) {
      if (xn_str_eq(n->text, rt_string_from_c("<<"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_long_shl("), a), rt_string_from_c(", ")), b), rt_string_from_c(")"));
      }
      if (xn_str_eq(n->text, rt_string_from_c(">>"))) {
        return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xn_long_shr("), a), rt_string_from_c(", ")), b), rt_string_from_c(")"));
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
    if (xn_str_eq(n->text, rt_string_from_c("super.deinit"))) {
      xn_Cls_AstNode * cur = xn_Cls_CGen_classByName(self, self->curClass);
      rt_string * base = rt_string_from_c("");
      if ((!xn_str_eq(cur->kind, rt_string_from_c("None")))) {
        base = xn_Cls_CGen_baseNameOf(self, cur);
      }
      if ((!xn_str_eq(base, rt_string_from_c("")))) {
        return xn_concat(xn_concat(rt_string_from_c("xn_Cls_"), base), rt_string_from_c("_deinit((void *)self)"));
      }
      return rt_string_from_c("((void)0)");
    }
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
    if (xn_str_eq(n->text, rt_string_from_c("Context.withCancel"))) {
      rt_string * av = rt_string_from_c("NULL");
      if ((((int64_t)n->kids->len) > 0)) {
        av = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      return xn_concat(xn_concat(rt_string_from_c("xrt_context_child("), av), rt_string_from_c(")"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("Context.withDeadline"))) {
      rt_string * pv = rt_string_from_c("NULL");
      rt_string * dv = rt_string_from_c("0");
      if ((((int64_t)n->kids->len) > 0)) {
        pv = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      if ((((int64_t)n->kids->len) > 1)) {
        dv = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_context_with_deadline("), pv), rt_string_from_c(", ")), dv), rt_string_from_c(")"));
    }
    if (xn_str_eq(n->text, rt_string_from_c("Context.withTimeout"))) {
      rt_string * pv = rt_string_from_c("NULL");
      rt_string * tv = rt_string_from_c("0");
      if ((((int64_t)n->kids->len) > 0)) {
        pv = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
      }
      if ((((int64_t)n->kids->len) > 1)) {
        tv = xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 1)));
      }
      return xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("xrt_context_with_timeout("), pv), rt_string_from_c(", ")), tv), rt_string_from_c(")"));
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
      if ((xn_str_eq(pat, rt_string_from_c("Double")) || xn_str_eq(pat, rt_string_from_c("Float")))) {
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
      if ((xn_str_eq(pat, rt_string_from_c("Double")) || xn_str_eq(pat, rt_string_from_c("Float")))) {
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
        if (xn_str_eq(mth, rt_string_from_c("wait"))) {
          return xn_concat(xn_concat(rt_string_from_c("xrt_context_wait("), bv), rt_string_from_c(")"));
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
        if (xn_str_eq(mth, rt_string_from_c("alloc"))) {
          if ((((int64_t)n->kids->len) > 0)) {
            return xn_concat(xn_concat(rt_string_from_c("xrt_bytes_alloc_checked("), xn_Cls_CGen_expr(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)))), rt_string_from_c(")"));
          }
          return rt_string_from_c("xrt_bytes_new()");
        }
        if (xn_str_eq(mth, rt_string_from_c("empty"))) {
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
        if (xn_str_eq(mth, rt_string_from_c("copy"))) {
          return xn_concat(xn_concat(xn_concat(xn_Cls_CGen_arrayCName(self, bt), rt_string_from_c("_copy(")), bv), rt_string_from_c(")"));
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

static xn_Cls_AstNode * xn_Cls_CGen_deinitOf(xn_Cls_CGen *self, xn_Cls_AstNode * cls) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i))->kind, rt_string_from_c("Deinit"))) {
      return ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), cls->line, cls->col);
}

static rt_string * xn_Cls_CGen_baseNameOf(xn_Cls_CGen *self, xn_Cls_AstNode * cls) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i))->kind, rt_string_from_c("Base"))) {
      return ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i))->text;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("");
}

static xn_Cls_AstNode * xn_Cls_CGen_classByName(xn_Cls_CGen *self, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Class")) && xn_str_eq(n->text, name))) {
      return n;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), 1, 1);
}

static int xn_Cls_CGen_hasSuperDeinitCall(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if ((xn_str_eq(n->kind, rt_string_from_c("Call")) && xn_str_eq(n->text, rt_string_from_c("super.deinit")))) {
    return 1;
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    if (xn_Cls_CGen_hasSuperDeinitCall(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_Cls_CGen_deinitMethod(xn_Cls_CGen *self, xn_Cls_AstNode * d, rt_string * cn) {
  self->curClass = cn;
  self->curRet = rt_string_from_c("Unit");
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("static void xn_Cls_"), cn), rt_string_from_c("_deinit(void *payload) {")));
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("  xn_Cls_"), cn), rt_string_from_c(" *self = (xn_Cls_")), cn), rt_string_from_c(" *)payload;")));
  xn_Cls_CGen_popTo(self, 0);
  xn_Cls_CGen_addVar(self, cn, rt_string_from_c("self"));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)d->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(d->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Block"))) {
      xn_Cls_CGen_blockBody(self, k, rt_string_from_c("  "));
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_popTo(self, 0);
  xn_Cls_AstNode * cur = xn_Cls_CGen_classByName(self, cn);
  rt_string * base = xn_Cls_CGen_baseNameOf(self, cur);
  if ((!xn_str_eq(base, rt_string_from_c("")))) {
    xn_Cls_AstNode * bc = xn_Cls_CGen_classByName(self, base);
    if ((((!xn_str_eq(bc->kind, rt_string_from_c("None"))) && (!xn_str_eq(xn_Cls_CGen_deinitOf(self, bc)->kind, rt_string_from_c("None")))) && (!xn_Cls_CGen_hasSuperDeinitCall(self, d)))) {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("  xn_Cls_"), base), rt_string_from_c("_deinit(payload);")));
    }
  }
  self->curClass = rt_string_from_c("");
  self->curRet = rt_string_from_c("Int");
  xn_Cls_CGen_emit(self, rt_string_from_c("}"));
  xn_Cls_CGen_emit(self, rt_string_from_c(""));
}

static void xn_Cls_CGen_genClass(xn_Cls_CGen *self, xn_Cls_AstNode * cls) {
  rt_string * cn = cls->text;
  xn_Cls_AstNode * dinit = xn_Cls_CGen_deinitOf(self, cls);
  if ((!xn_str_eq(dinit->kind, rt_string_from_c("None")))) {
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("static void xn_Cls_"), cn), rt_string_from_c("_deinit(void *payload);")));
  }
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
  rt_string * deinitPtr = rt_string_from_c("NULL");
  if ((!xn_str_eq(dinit->kind, rt_string_from_c("None")))) {
    deinitPtr = xn_concat(xn_concat(rt_string_from_c("xn_Cls_"), cn), rt_string_from_c("_deinit"));
  }
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static const rt_type RT_TYPE_XN_"), cn), rt_string_from_c(" = { \"")), cn), rt_string_from_c("\", sizeof(xn_Cls_")), cn), rt_string_from_c("), ")), deinitPtr), rt_string_from_c(", NULL };")));
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
  if ((!xn_str_eq(dinit->kind, rt_string_from_c("None")))) {
    xn_Cls_CGen_deinitMethod(self, dinit, cn);
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

static rt_string * xn_Cls_CGen_annotationPackageName(xn_Cls_CGen *self) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("Package"))) {
      return n->text;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_CGen_annotationQualifiedFor(xn_Cls_CGen *self, rt_string * name, rt_string * ownerPkg) {
  if ((xn_str_indexof(name, rt_string_from_c(".")) >= 0)) {
    return name;
  }
  xn_Cls_AstNode * d = xn_Cls_CGen_annotationFindDeclFor(self, name, ownerPkg);
  if (xn_str_eq(d->kind, rt_string_from_c("None"))) {
    if (xn_str_eq(ownerPkg, rt_string_from_c(""))) {
      return name;
    }
    return xn_concat(xn_concat(ownerPkg, rt_string_from_c(".")), name);
  }
  rt_string * pkg = xn_declPackageOf(d);
  if (xn_str_eq(pkg, rt_string_from_c(""))) {
    return name;
  }
  return xn_concat(xn_concat(pkg, rt_string_from_c(".")), name);
}

static rt_string * xn_Cls_CGen_annotationQualified(xn_Cls_CGen *self, rt_string * name) {
  if ((xn_str_indexof(name, rt_string_from_c(".")) >= 0)) {
    return name;
  }
  return xn_Cls_CGen_annotationQualifiedFor(self, name, rootPackageName);
}

static rt_string * xn_Cls_CGen_typeTextOf(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Ret"))) {
    return n->text;
  }
  if (((xn_str_eq(n->kind, rt_string_from_c("Method")) || xn_str_eq(n->kind, rt_string_from_c("Func"))) || xn_str_eq(n->kind, rt_string_from_c("Sig")))) {
    return xn_Cls_CGen_retNode(self, n)->text;
  }
  xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
  if ((((int64_t)parts->len) >= 1)) {
    return xn_arr_s_get(parts, 0);
  }
  return n->text;
}

static int xn_Cls_CGen_knownTypeName(xn_Cls_CGen *self, rt_string * ty) {
  if (xn_Cls_CGen_isClass(self, ty)) {
    return 1;
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (((xn_str_eq(n->kind, rt_string_from_c("Enum")) || xn_str_eq(n->kind, rt_string_from_c("Protocol"))) && xn_str_eq(n->text, ty))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static rt_string * xn_Cls_CGen_qualifiedTypeName(xn_Cls_CGen *self, rt_string * ty, rt_string * ownerPkg) {
  if ((xn_str_eq(ty, rt_string_from_c("")) || (xn_str_indexof(ty, rt_string_from_c(".")) >= 0))) {
    return ty;
  }
  if ((xn_Cls_CGen_knownTypeName(self, ty) && (!xn_str_eq(ownerPkg, rt_string_from_c(""))))) {
    return xn_concat(xn_concat(ownerPkg, rt_string_from_c(".")), ty);
  }
  return ty;
}

static void xn_Cls_CGen_collectTypeUses(xn_Cls_CGen *self, xn_Cls_AstNode * node, rt_string * targetName, rt_string * ownerPkg, xn_arr_o * out) {
  rt_string * typeName = xn_Cls_CGen_qualifiedTypeName(self, xn_Cls_CGen_typeTextOf(self, node), ownerPkg);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)node->typeAnnotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(node->typeAnnotations, i));
    rt_string * useName = use->text;
    if ((!xn_str_eq(use->resolvedAnnotationName, rt_string_from_c("")))) {
      useName = use->resolvedAnnotationName;
    }
    xn_Cls_AstNode * decl = xn_Cls_CGen_annotationFindDeclFor(self, useName, ownerPkg);
    if (((!xn_str_eq(decl->kind, rt_string_from_c("None"))) && xn_str_eq(xn_Cls_CGen_annotationRetention(self, decl), rt_string_from_c("Runtime")))) {
      xn_arr_o_push(out, xn_Cls_AnnotationUseMeta_new(use, decl, typeName, rt_string_from_c("TypeUse"), targetName, xn_int_wrap((i + 1))));
    }
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_CGen_collectTypeUseLocals(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * methodOwner, rt_string * ownerPkg, xn_arr_o * out) {
  if ((xn_str_eq(n->kind, rt_string_from_c("Local")) && (((int64_t)n->typeAnnotations->len) > 0))) {
    xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
    if ((((int64_t)parts->len) >= 2)) {
      xn_Cls_CGen_collectTypeUses(self, n, xn_concat(xn_concat(methodOwner, rt_string_from_c("#local:")), xn_arr_s_get(parts, 1)), ownerPkg, out);
    }
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->kids->len))) {
    xn_Cls_CGen_collectTypeUseLocals(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), methodOwner, ownerPkg, out);
    i = xn_int_wrap((i + 1));
  }
}

static rt_string * xn_Cls_CGen_annotationStringText(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if ((!xn_str_eq(n->kind, rt_string_from_c("String")))) {
    return rt_string_from_c("");
  }
  rt_string * raw = n->text;
  if ((((int64_t)raw->len) >= 2)) {
    if ((xn_str_eq(xn_str_substr(raw, 0, 1), rt_string_from_c("\"")) && xn_str_eq(xn_str_substr(raw, xn_int_wrap((((int64_t)raw->len) - 1)), 1), rt_string_from_c("\"")))) {
      return xn_str_substr(raw, 1, xn_int_wrap((((int64_t)raw->len) - 2)));
    }
  }
  return raw;
}

static rt_string * xn_Cls_CGen_annotationPath(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Name"))) {
    return n->text;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Member")) && (((int64_t)n->kids->len) > 0))) {
    rt_string * b = xn_Cls_CGen_annotationPath(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (xn_str_eq(b, rt_string_from_c(""))) {
      return n->text;
    }
    return xn_concat(xn_concat(b, rt_string_from_c(".")), n->text);
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    return xn_Cls_CGen_annotationStringText(self, n);
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_CGen_annotationLastSegment(xn_Cls_CGen *self, rt_string * path) {
  int64_t i = xn_int_wrap(xn_int_wrap((((int64_t)path->len) - 1)));
  while ((i >= 0)) {
    if (xn_str_eq(xn_str_substr(path, i, 1), rt_string_from_c("."))) {
      return xn_str_substr(path, xn_int_wrap((i + 1)), xn_int_wrap((xn_int_wrap((((int64_t)path->len) - i)) - 1)));
    }
    i = xn_int_wrap((i - 1));
  }
  return path;
}

static xn_Cls_AstNode * xn_Cls_CGen_annotationFindDeclFor(xn_Cls_CGen *self, rt_string * name, rt_string * ownerPkg) {
  rt_string * simple = name;
  rt_string * exactPkg = rt_string_from_c("");
  int64_t dot = xn_int_wrap(xn_int_wrap((((int64_t)name->len) - 1)));
  while ((dot >= 0)) {
    if (xn_str_eq(xn_str_substr(name, dot, 1), rt_string_from_c("."))) {
      exactPkg = xn_str_substr(name, 0, dot);
      simple = xn_str_substr(name, xn_int_wrap((dot + 1)), xn_int_wrap((xn_int_wrap((((int64_t)name->len) - dot)) - 1)));
      break;
    }
    dot = xn_int_wrap((dot - 1));
  }
  if ((!xn_str_eq(exactPkg, rt_string_from_c("")))) {
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)self->program->kids->len))) {
      xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
      if (((xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl")) && xn_str_eq(n->text, simple)) && xn_str_eq(xn_declPackageOf(n), exactPkg))) {
        return n;
      }
      i = xn_int_wrap((i + 1));
    }
    return xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), 1, 1);
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (((xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl")) && xn_str_eq(n->text, simple)) && xn_str_eq(xn_declPackageOf(n), ownerPkg))) {
      return n;
    }
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)unitImportOwners->len))) {
    if (xn_str_eq(xn_arr_s_get(unitImportOwners, i), ownerPkg)) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)self->program->kids->len))) {
        xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, j));
        if (((xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl")) && xn_str_eq(n->text, simple)) && xn_str_eq(xn_declPackageOf(n), xn_arr_s_get(unitImportPkgs, i)))) {
          return n;
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode * found = xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), 1, 1);
  int64_t hits = xn_int_wrap(0);
  i = 0;
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl")) && xn_str_eq(n->text, simple))) {
      found = n;
      hits = xn_int_wrap((hits + 1));
    }
    i = xn_int_wrap((i + 1));
  }
  if ((hits == 1)) {
    return found;
  }
  return xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), 1, 1);
}

static rt_string * xn_Cls_CGen_annotationRetention(xn_Cls_CGen *self, xn_Cls_AstNode * decl) {
  rt_string * retention = rt_string_from_c("Binary");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)decl->annotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(decl->annotations, i));
    if ((xn_str_eq(use->text, rt_string_from_c("Retention")) && (((int64_t)use->kids->len) > 0))) {
      xn_Cls_AstNode * arg = ((xn_Cls_AstNode *)xn_arr_o_get(use->kids, 0));
      if ((((int64_t)arg->kids->len) > 0)) {
        rt_string * p = xn_Cls_CGen_annotationPath(self, ((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0)));
        if ((!xn_str_eq(p, rt_string_from_c("")))) {
          retention = p;
        }
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return retention;
}

static xn_arr_o * xn_Cls_CGen_annotationFields(xn_Cls_CGen *self, xn_Cls_AstNode * decl) {
  xn_arr_o *fields = xn_arr_o_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)decl->kids->len))) {
    xn_Cls_AstNode * f = ((xn_Cls_AstNode *)xn_arr_o_get(decl->kids, i));
    if (xn_str_eq(f->kind, rt_string_from_c("AnnotationField"))) {
      xn_arr_o_push(fields, f);
    }
    i = xn_int_wrap((i + 1));
  }
  return fields;
}

static rt_string * xn_Cls_CGen_annotationFieldType(xn_Cls_CGen *self, xn_Cls_AstNode * f) {
  xn_arr_s * parts = xn_str_split(f->text, rt_string_from_c(" "));
  if ((((int64_t)parts->len) >= 2)) {
    return xn_arr_s_get(parts, 0);
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_CGen_annotationFieldName(xn_Cls_CGen *self, xn_Cls_AstNode * f) {
  xn_arr_s * parts = xn_str_split(f->text, rt_string_from_c(" "));
  if ((((int64_t)parts->len) >= 2)) {
    return xn_arr_s_get(parts, 1);
  }
  return rt_string_from_c("");
}

static rt_string * xn_Cls_CGen_annotationParamTypes(xn_Cls_CGen *self, xn_Cls_AstNode * fn) {
  rt_string * result = rt_string_from_c("");
  xn_arr_o * ps = xn_Cls_CGen_paramsOf(self, fn);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ps->len))) {
    xn_arr_s * parts = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(ps, i))->text, rt_string_from_c(" "));
    if ((((int64_t)parts->len) >= 2)) {
      if ((!xn_str_eq(result, rt_string_from_c("")))) {
        result = xn_concat(result, rt_string_from_c(","));
      }
      result = xn_concat(result, xn_arr_s_get(parts, 0));
    }
    i = xn_int_wrap((i + 1));
  }
  return result;
}

static void xn_Cls_CGen_collectAnnotationUses(xn_Cls_CGen *self, xn_Cls_AstNode * node, rt_string * target, rt_string * targetName, xn_arr_o * out) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)node->annotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(node->annotations, i));
    rt_string * useName = use->text;
    if ((!xn_str_eq(use->resolvedAnnotationName, rt_string_from_c("")))) {
      useName = use->resolvedAnnotationName;
    }
    xn_Cls_AstNode * decl = xn_Cls_CGen_annotationFindDeclFor(self, useName, xn_declPackageOf(node));
    if (((!xn_str_eq(decl->kind, rt_string_from_c("None"))) && xn_str_eq(xn_Cls_CGen_annotationRetention(self, decl), rt_string_from_c("Runtime")))) {
      int64_t repeat = xn_int_wrap(1);
      int64_t j = xn_int_wrap(0);
      while ((j < i)) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(node->annotations, j))->text, use->text)) {
          repeat = xn_int_wrap((repeat + 1));
        }
        j = xn_int_wrap((j + 1));
      }
      xn_arr_o_push(out, xn_Cls_AnnotationUseMeta_new(use, decl, xn_Cls_CGen_annotationQualifiedFor(self, useName, xn_declPackageOf(node)), target, targetName, repeat));
    }
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_CGen_collectAnnotationParams(xn_Cls_CGen *self, xn_Cls_AstNode * fn, rt_string * memberTarget, xn_arr_o * out) {
  xn_arr_o * ps = xn_Cls_CGen_paramsOf(self, fn);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ps->len))) {
    xn_Cls_CGen_collectAnnotationUses(self, ((xn_Cls_AstNode *)xn_arr_o_get(ps, i)), rt_string_from_c("Parameter"), xn_concat(xn_concat(memberTarget, rt_string_from_c("#")), xn_str_int(i)), out);
    i = xn_int_wrap((i + 1));
  }
}

static void xn_Cls_CGen_collectAnnotationClass(xn_Cls_CGen *self, xn_Cls_AstNode * cls, xn_arr_o * out) {
  rt_string * owner = xn_Cls_CGen_annotationQualifiedFor(self, cls->text, xn_declPackageOf(cls));
  xn_Cls_CGen_collectAnnotationUses(self, cls, rt_string_from_c("Type"), owner, out);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("TypeParams"))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)k->kids->len))) {
        xn_Cls_AstNode * tp = ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, j));
        if (xn_str_eq(tp->kind, rt_string_from_c("TypeParam"))) {
          xn_Cls_CGen_collectAnnotationUses(self, tp, rt_string_from_c("TypeParameter"), xn_concat(xn_concat(owner, rt_string_from_c("#")), tp->text), out);
        }
        j = xn_int_wrap((j + 1));
      }
    }
    if (xn_str_eq(k->kind, rt_string_from_c("Ctor"))) {
      rt_string * tn = xn_concat(xn_concat(xn_concat(owner, rt_string_from_c("#<init>(")), xn_Cls_CGen_annotationParamTypes(self, k)), rt_string_from_c(")"));
      xn_Cls_CGen_collectAnnotationUses(self, k, rt_string_from_c("Constructor"), tn, out);
      xn_Cls_CGen_collectAnnotationParams(self, k, tn, out);
      xn_arr_o * cps = xn_Cls_CGen_paramsOf(self, k);
      int64_t cpi = xn_int_wrap(0);
      while ((cpi < ((int64_t)cps->len))) {
        xn_Cls_CGen_collectTypeUses(self, ((xn_Cls_AstNode *)xn_arr_o_get(cps, cpi)), xn_concat(xn_concat(tn, rt_string_from_c("#")), xn_str_int(cpi)), xn_declPackageOf(cls), out);
        cpi = xn_int_wrap((cpi + 1));
      }
      xn_Cls_CGen_collectTypeUseLocals(self, k, tn, xn_declPackageOf(cls), out);
    }
    if (xn_str_eq(k->kind, rt_string_from_c("Method"))) {
      rt_string * tn = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(owner, rt_string_from_c("#")), k->text), rt_string_from_c("(")), xn_Cls_CGen_annotationParamTypes(self, k)), rt_string_from_c(")"));
      xn_Cls_CGen_collectAnnotationUses(self, k, rt_string_from_c("Method"), tn, out);
      xn_Cls_CGen_collectAnnotationParams(self, k, tn, out);
      xn_Cls_CGen_collectTypeUses(self, k, xn_concat(tn, rt_string_from_c("#return")), xn_declPackageOf(cls), out);
      xn_arr_o * mps = xn_Cls_CGen_paramsOf(self, k);
      int64_t mpi = xn_int_wrap(0);
      while ((mpi < ((int64_t)mps->len))) {
        xn_Cls_CGen_collectTypeUses(self, ((xn_Cls_AstNode *)xn_arr_o_get(mps, mpi)), xn_concat(xn_concat(tn, rt_string_from_c("#")), xn_str_int(mpi)), xn_declPackageOf(cls), out);
        mpi = xn_int_wrap((mpi + 1));
      }
      xn_Cls_CGen_collectTypeUseLocals(self, k, tn, xn_declPackageOf(cls), out);
    }
    if (xn_str_eq(k->kind, rt_string_from_c("Deinit"))) {
      xn_Cls_CGen_collectAnnotationUses(self, k, rt_string_from_c("Deinit"), xn_concat(owner, rt_string_from_c("#deinit()")), out);
    }
    if (xn_str_eq(k->kind, rt_string_from_c("Field"))) {
      xn_arr_s * parts = xn_str_split(k->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        xn_Cls_CGen_collectAnnotationUses(self, k, rt_string_from_c("Field"), xn_concat(xn_concat(owner, rt_string_from_c("#")), xn_arr_s_get(parts, 1)), out);
        xn_Cls_CGen_collectTypeUses(self, k, xn_concat(xn_concat(owner, rt_string_from_c("#")), xn_arr_s_get(parts, 1)), xn_declPackageOf(cls), out);
      }
    }
    i = xn_int_wrap((i + 1));
  }
}

static xn_arr_o * xn_Cls_CGen_collectGeneratedAnnotations(xn_Cls_CGen *self) {
  xn_arr_o *out = xn_arr_o_new(0);
  rt_string * pkg = xn_Cls_CGen_annotationPackageName(self);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)self->program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(self->program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("Package"))) {
      xn_Cls_CGen_collectAnnotationUses(self, n, rt_string_from_c("Package"), n->text, out);
    }
    if (xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl"))) {
      rt_string * full = xn_Cls_CGen_annotationQualifiedFor(self, n->text, xn_declPackageOf(n));
      xn_Cls_CGen_collectAnnotationUses(self, n, rt_string_from_c("Annotation"), full, out);
    }
    if ((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct")))) {
      xn_Cls_CGen_collectAnnotationClass(self, n, out);
    }
    if (xn_str_eq(n->kind, rt_string_from_c("Enum"))) {
      rt_string * owner = xn_Cls_CGen_annotationQualifiedFor(self, n->text, xn_declPackageOf(n));
      xn_Cls_CGen_collectAnnotationUses(self, n, rt_string_from_c("Type"), owner, out);
      int64_t e = xn_int_wrap(0);
      while ((e < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * item = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, e));
        if (xn_str_eq(item->kind, rt_string_from_c("EnumItem"))) {
          xn_Cls_CGen_collectAnnotationUses(self, item, rt_string_from_c("EnumItem"), xn_concat(xn_concat(owner, rt_string_from_c("#")), item->text), out);
        }
        e = xn_int_wrap((e + 1));
      }
    }
    if (xn_str_eq(n->kind, rt_string_from_c("Protocol"))) {
      rt_string * owner = xn_Cls_CGen_annotationQualifiedFor(self, n->text, xn_declPackageOf(n));
      xn_Cls_CGen_collectAnnotationUses(self, n, rt_string_from_c("Type"), owner, out);
      int64_t p = xn_int_wrap(0);
      while ((p < ((int64_t)n->kids->len))) {
        xn_Cls_AstNode * sig = ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, p));
        if (xn_str_eq(sig->kind, rt_string_from_c("Sig"))) {
          rt_string * tn = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(owner, rt_string_from_c("#")), sig->text), rt_string_from_c("(")), xn_Cls_CGen_annotationParamTypes(self, sig)), rt_string_from_c(")"));
          xn_Cls_CGen_collectAnnotationUses(self, sig, rt_string_from_c("Method"), tn, out);
          xn_Cls_CGen_collectAnnotationParams(self, sig, tn, out);
        }
        p = xn_int_wrap((p + 1));
      }
    }
    if (xn_str_eq(n->kind, rt_string_from_c("Func"))) {
      rt_string * owner = pkg;
      rt_string * tn = xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(owner, rt_string_from_c("#")), n->text), rt_string_from_c("(")), xn_Cls_CGen_annotationParamTypes(self, n)), rt_string_from_c(")"));
      xn_Cls_CGen_collectAnnotationUses(self, n, rt_string_from_c("Method"), tn, out);
      xn_Cls_CGen_collectAnnotationParams(self, n, tn, out);
      xn_Cls_CGen_collectTypeUses(self, n, xn_concat(tn, rt_string_from_c("#return")), pkg, out);
      xn_arr_o * fps = xn_Cls_CGen_paramsOf(self, n);
      int64_t fpi = xn_int_wrap(0);
      while ((fpi < ((int64_t)fps->len))) {
        xn_Cls_CGen_collectTypeUses(self, ((xn_Cls_AstNode *)xn_arr_o_get(fps, fpi)), xn_concat(xn_concat(tn, rt_string_from_c("#")), xn_str_int(fpi)), pkg, out);
        fpi = xn_int_wrap((fpi + 1));
      }
      xn_Cls_CGen_collectTypeUseLocals(self, n, tn, pkg, out);
    }
    if (xn_str_eq(n->kind, rt_string_from_c("TopField"))) {
      xn_arr_s * parts = xn_str_split(n->text, rt_string_from_c(" "));
      if ((((int64_t)parts->len) >= 2)) {
        xn_Cls_CGen_collectAnnotationUses(self, n, rt_string_from_c("Field"), xn_concat(xn_concat(pkg, rt_string_from_c("#")), xn_arr_s_get(parts, 1)), out);
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return out;
}

static rt_string * xn_Cls_CGen_annotationNumberText(xn_Cls_CGen *self, xn_Cls_AstNode * n) {
  if ((xn_str_eq(n->kind, rt_string_from_c("Int")) || xn_str_eq(n->kind, rt_string_from_c("Double")))) {
    return n->text;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Unary")) && (((int64_t)n->kids->len) > 0))) {
    return xn_concat(n->text, xn_Cls_CGen_annotationNumberText(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))));
  }
  return rt_string_from_c("0");
}

static rt_string * xn_Cls_CGen_emitAnnotationValue(xn_Cls_CGen *self, xn_Cls_AstNode * n, rt_string * expected, rt_string * indent) {
  if (((((int64_t)expected->len) > 2) && xn_str_eq(xn_str_substr(expected, xn_int_wrap((((int64_t)expected->len) - 2)), 2), rt_string_from_c("[]")))) {
    rt_string * elementType = xn_str_substr(expected, 0, xn_int_wrap((((int64_t)expected->len) - 2)));
    rt_string * items = xn_Cls_CGen_temp(self);
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_arr_o *")), items), rt_string_from_c(" = xn_arr_o_new(")), xn_str_int(((int64_t)n->kids->len))), rt_string_from_c(");")));
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)n->kids->len))) {
      rt_string * item = xn_Cls_CGen_emitAnnotationValue(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), elementType, indent);
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_arr_o_push(")), items), rt_string_from_c(", (void *)")), item), rt_string_from_c(");")));
      i = xn_int_wrap((i + 1));
    }
    rt_string * arrayValue = xn_Cls_CGen_temp(self);
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), arrayValue), rt_string_from_c(" = xn_Cls_AnnotationValue_ofArray(")), items), rt_string_from_c(");")));
    return arrayValue;
  }
  xn_Cls_AstNode * nestedDecl = xn_Cls_CGen_annotationFindDeclFor(self, expected, rootPackageName);
  if (((!xn_str_eq(nestedDecl->kind, rt_string_from_c("None"))) && xn_str_eq(n->kind, rt_string_from_c("AnnotationUse")))) {
    rt_string * info = xn_Cls_CGen_emitAnnotationInfo(self, n, nestedDecl, xn_Cls_CGen_annotationQualified(self, expected), rt_string_from_c("Annotation"), xn_Cls_CGen_annotationQualified(self, expected), 1, indent);
    rt_string * nestedValue = xn_Cls_CGen_temp(self);
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), nestedValue), rt_string_from_c(" = xn_Cls_AnnotationValue_ofAnnotation(")), info), rt_string_from_c(");")));
    return nestedValue;
  }
  rt_string * value = xn_Cls_CGen_temp(self);
  if ((xn_str_eq(expected, rt_string_from_c("Type")) || xn_str_eq(expected, rt_string_from_c("TypeRef")))) {
    rt_string * name = xn_Cls_CGen_annotationPath(self, n);
    if (xn_str_eq(name, rt_string_from_c(""))) {
      name = xn_Cls_CGen_annotationStringText(self, n);
    }
    if (xn_str_eq(name, rt_string_from_c(""))) {
      name = expected;
    }
    if (((xn_str_indexof(name, rt_string_from_c(".")) < 0) && (!xn_str_eq(name, rt_string_from_c("void"))))) {
      name = xn_Cls_CGen_annotationQualified(self, name);
    }
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), value), rt_string_from_c(" = xn_Cls_AnnotationValue_ofType(rt_string_from_c(")), xn_cStringLiteral(name)), rt_string_from_c("));")));
    return value;
  }
  if (xn_Cls_CGen_isEnumName(self, expected)) {
    rt_string * path = xn_Cls_CGen_annotationPath(self, n);
    rt_string * item = xn_Cls_CGen_annotationLastSegment(self, path);
    rt_string * enumName = xn_Cls_CGen_annotationQualified(self, expected);
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), value), rt_string_from_c(" = xn_Cls_AnnotationValue_ofEnum(rt_string_from_c(")), xn_cStringLiteral(enumName)), rt_string_from_c("), rt_string_from_c(")), xn_cStringLiteral(item)), rt_string_from_c("));")));
    return value;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Bool"))) {
    rt_string * boolValue = rt_string_from_c("0");
    if (xn_str_eq(n->text, rt_string_from_c("true"))) {
      boolValue = rt_string_from_c("1");
    }
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), value), rt_string_from_c(" = xn_Cls_AnnotationValue_ofBool(")), boolValue), rt_string_from_c(");")));
    return value;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("String"))) {
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), value), rt_string_from_c(" = xn_Cls_AnnotationValue_ofString(rt_string_from_c(")), xn_canonicalStringLiteral(n->text)), rt_string_from_c("));")));
    return value;
  }
  if (xn_str_eq(n->kind, rt_string_from_c("Char"))) {
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), value), rt_string_from_c(" = xn_Cls_AnnotationValue_ofChar((int32_t)(")), n->text), rt_string_from_c("));")));
    return value;
  }
  if (((xn_str_eq(n->kind, rt_string_from_c("Int")) || xn_str_eq(n->kind, rt_string_from_c("Double"))) || ((xn_str_eq(n->kind, rt_string_from_c("Unary")) && (((int64_t)n->kids->len) > 0)) && (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))->kind, rt_string_from_c("Int")) || xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0))->kind, rt_string_from_c("Double")))))) {
    rt_string * number = xn_Cls_CGen_annotationNumberText(self, n);
    if (xn_str_eq(expected, rt_string_from_c("Long"))) {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), value), rt_string_from_c(" = xn_Cls_AnnotationValue_ofLong((int64_t)(")), number), rt_string_from_c("));")));
    }
    else {
      if (xn_str_eq(expected, rt_string_from_c("Float"))) {
        xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), value), rt_string_from_c(" = xn_Cls_AnnotationValue_ofFloat((double)(")), number), rt_string_from_c("));")));
      }
      else {
        if (xn_str_eq(expected, rt_string_from_c("Double"))) {
          xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), value), rt_string_from_c(" = xn_Cls_AnnotationValue_ofDouble((double)(")), number), rt_string_from_c("));")));
        }
        else {
          xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), value), rt_string_from_c(" = xn_Cls_AnnotationValue_ofInt((int64_t)(")), number), rt_string_from_c("));")));
        }
      }
    }
    return value;
  }
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationValue *")), value), rt_string_from_c(" = xn_Cls_AnnotationValue_nullValue();")));
  return value;
}

static rt_string * xn_Cls_CGen_emitAnnotationInfo(xn_Cls_CGen *self, xn_Cls_AstNode * use, xn_Cls_AstNode * decl, rt_string * typeName, rt_string * target, rt_string * targetName, int64_t repeatIndex, rt_string * indent) {
  xn_arr_o * fields = xn_Cls_CGen_annotationFields(self, decl);
  rt_string * values = xn_Cls_CGen_temp(self);
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_map_g *")), values), rt_string_from_c(" = xn_map_g_new(")), xn_str_int(((int64_t)fields->len))), rt_string_from_c(", 1, 0);")));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fields->len))) {
    xn_Cls_AstNode * field = ((xn_Cls_AstNode *)xn_arr_o_get(fields, i));
    xn_Cls_AstNode * value = xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), 1, 1);
    if (((i < ((int64_t)use->kids->len)) && (((int64_t)((xn_Cls_AstNode *)xn_arr_o_get(use->kids, i))->kids->len) > 0))) {
      value = ((xn_Cls_AstNode *)xn_arr_o_get(((xn_Cls_AstNode *)xn_arr_o_get(use->kids, i))->kids, 0));
    }
    else {
      if ((((int64_t)field->kids->len) > 0)) {
        value = ((xn_Cls_AstNode *)xn_arr_o_get(field->kids, 0));
      }
    }
    if ((!xn_str_eq(value->kind, rt_string_from_c("None")))) {
      rt_string * name = xn_Cls_CGen_annotationFieldName(self, field);
      rt_string * type = xn_Cls_CGen_annotationFieldType(self, field);
      rt_string * emitted = xn_Cls_CGen_emitAnnotationValue(self, value, type, indent);
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_map_g_put_replaced(")), values), rt_string_from_c(", rt_string_from_c(")), xn_cStringLiteral(name)), rt_string_from_c("), (void *)")), emitted), rt_string_from_c(");")));
    }
    i = xn_int_wrap((i + 1));
  }
  rt_string * info = xn_Cls_CGen_temp(self);
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(indent, rt_string_from_c("xn_Cls_AnnotationInfo *")), info), rt_string_from_c(" = xn_Cls_AnnotationInfo_new(rt_string_from_c(")), xn_cStringLiteral(typeName)), rt_string_from_c("), xn_enum_AnnotationTarget_")), target), rt_string_from_c(", rt_string_from_c(")), xn_cStringLiteral(targetName)), rt_string_from_c("), ")), values), rt_string_from_c(", ")), xn_str_int(repeatIndex)), rt_string_from_c(");")));
  return info;
}

static void xn_Cls_CGen_emitAnnotationRegistry(xn_Cls_CGen *self) {
  if (((((!xn_Cls_CGen_isClass(self, rt_string_from_c("AnnotationValue"))) || (!xn_Cls_CGen_isClass(self, rt_string_from_c("AnnotationInfo")))) || (!xn_Cls_CGen_isClass(self, rt_string_from_c("AnnotationRegistry")))) || (!xn_Cls_CGen_isEnumName(self, rt_string_from_c("AnnotationTarget"))))) {
    return;
  }
  xn_arr_o * uses = xn_Cls_CGen_collectGeneratedAnnotations(self);
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Cls_AnnotationRegistry *xn_generated_annotation_registry = NULL;"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_xdkAnnotationRegistryVersion(void) { return 1; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_Cls_AnnotationRegistry *xn_xdkAnnotationRegistry(void) {"));
  xn_Cls_CGen_emit(self, rt_string_from_c("  if (xn_generated_annotation_registry == NULL) {"));
  xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("    xn_arr_o *items = xn_arr_o_new("), xn_str_int(((int64_t)uses->len))), rt_string_from_c(");")));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)uses->len))) {
    xn_Cls_AnnotationUseMeta * use = ((xn_Cls_AnnotationUseMeta *)xn_arr_o_get(uses, i));
    rt_string * info = xn_Cls_CGen_emitAnnotationInfo(self, use->use, use->decl, use->typeName, use->target, use->targetName, use->repeatIndex, rt_string_from_c("    "));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("    xn_arr_o_push(items, (void *)"), info), rt_string_from_c(");")));
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_CGen_emit(self, rt_string_from_c("    xn_generated_annotation_registry = xn_Cls_AnnotationRegistry_new(items);"));
  xn_Cls_CGen_emit(self, rt_string_from_c("  }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("  return xn_generated_annotation_registry;"));
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
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_long_shl(int64_t value, int64_t bitCount) { if (bitCount < 0 || bitCount >= 64) { rt_fatal(\"shift count out of range\"); } return (int64_t)((uint64_t)value << (uint64_t)bitCount); }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static int64_t xn_long_shr(int64_t value, int64_t bitCount) { if (bitCount < 0 || bitCount >= 64) { rt_fatal(\"shift count out of range\"); } return (int64_t)((int64_t)value >> (int64_t)bitCount); }"));
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
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_i *xn_arr_i_copy(const xn_arr_i *a) { xn_arr_i *out = xn_arr_i_new(a->len); if (a->len > 0) { memcpy(out->data, a->data, sizeof(int64_t) * a->len); } out->len = a->len; return out; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_d *xn_arr_d_copy(const xn_arr_d *a) { xn_arr_d *out = xn_arr_d_new(a->len); if (a->len > 0) { memcpy(out->data, a->data, sizeof(double) * a->len); } out->len = a->len; return out; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_s *xn_arr_s_copy(const xn_arr_s *a) { xn_arr_s *out = xn_arr_s_new(a->len); if (a->len > 0) { memcpy(out->data, a->data, sizeof(rt_string *) * a->len); } out->len = a->len; return out; }"));
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_o *xn_arr_o_copy(const xn_arr_o *a) { xn_arr_o *out = xn_arr_o_new(a->len); if (a->len > 0) { memcpy(out->data, a->data, sizeof(void *) * a->len); } out->len = a->len; return out; }"));
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
    rt_string * entryCls = xn_Cls_CGen_entryClassName(self, kty, vty);
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), kac), rt_string_from_c(" *")), xn_Cls_CGen_genericMapKeysName(self, gty)), rt_string_from_c("(const xn_map_g *m);")));
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static "), vac), rt_string_from_c(" *")), xn_Cls_CGen_genericMapValuesName(self, gty)), rt_string_from_c("(const xn_map_g *m);")));
    if (xn_Cls_CGen_isClass(self, entryCls)) {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(rt_string_from_c("static xn_arr_o *"), xn_Cls_CGen_genericMapEntriesName(self, gty)), rt_string_from_c("(const xn_map_g *m);")));
    }
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
  xn_Cls_CGen_emit(self, rt_string_from_c("static xn_arr_r *xn_arr_r_copy(const xn_arr_r *a) { xn_arr_r *out = xn_arr_r_new(a->len); if (a->len > 0) { memcpy(out->data, a->data, sizeof(xn_Result) * a->len); } out->len = a->len; return out; }"));
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
    if ((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || (xn_str_eq(n->kind, rt_string_from_c("Enum")) && xn_Cls_CGen_isDataEnum(self, n->text))) && (!xn_hasTypeParams(n)))) {
      xn_Cls_AstNode * ctor = xn_Cls_CGen_ctorOf(self, n);
      xn_arr_o * cps = xn_Cls_CGen_paramsOf(self, ctor);
      rt_string * csig = xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static xn_Cls_"), n->text), rt_string_from_c(" *xn_Cls_")), n->text), rt_string_from_c("_new("));
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
      xn_Cls_CGen_emit(self, xn_concat(csig, rt_string_from_c(");")));
      int64_t mi = xn_int_wrap(0);
      while ((mi < ((int64_t)n->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, mi))->kind, rt_string_from_c("Method"))) {
          xn_Cls_CGen_emit(self, xn_concat(xn_Cls_CGen_methodSig(self, ((xn_Cls_AstNode *)xn_arr_o_get(n->kids, mi)), n->text), rt_string_from_c(";")));
        }
        mi = xn_int_wrap((mi + 1));
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
  xn_Cls_CGen_emitAnnotationRegistry(self);
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
    if (xn_Cls_CGen_isClass(self, entryCls)) {
      xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("static xn_arr_o *"), xn_Cls_CGen_genericMapEntriesName(self, gty)), rt_string_from_c("(const xn_map_g *m) { xn_arr_o *out = xn_arr_o_new(m->len); for (size_t i = 0; i < m->len; i++) { xn_arr_o_push(out, (void *)xn_Cls_")), entryCls), rt_string_from_c("_new(")), xn_Cls_CGen_decodeOf(self, kty, rt_string_from_c("m->keys[i]"))), rt_string_from_c(", ")), xn_Cls_CGen_decodeOf(self, vty, rt_string_from_c("m->vals[i]"))), rt_string_from_c(")); } return out; }")));
    }
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
  int64_t wi = xn_int_wrap(0);
  while ((wi < ((int64_t)compilerWarnings->len))) {
    rt_string * warning = xn_arr_s_get(compilerWarnings, wi);
    xn_Cls_CGen_emit(self, xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("  (void)xdkc_diagnose_rc("), xn_cStringLiteral(warning)), rt_string_from_c(", ")), xn_str_int(((int64_t)warning->len))), rt_string_from_c(");")));
    wi = xn_int_wrap((wi + 1));
  }
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
static xn_arr_s * compilerWarnings;
static rt_string * loadBaseDir;
static rt_string * loadRoot;
static int xdkFullSource;
static rt_string * rootPackageName;
static xn_arr_o * unitDeclNodes;
static xn_arr_s * unitDeclPkgs;
static xn_arr_s * unitImportOwners;
static xn_arr_s * unitImportPkgs;
static xn_arr_s * ffiNames;
static xn_arr_s * ffiCNames;
static xn_arr_s * ffiRets;
static xn_arr_s * ffiParamSpecs;
static xn_arr_s * ffiErrParams;
static xn_arr_s * ffiErrRets;
static rt_string * a8ErrorCode;
static rt_string * a8ErrorMessage;
static int64_t a8ErrorLine;
static int64_t a8ErrorCol;

static void xn_init_globals(void) {
  loadedFiles = xn_arr_s_new(0);
  compilerWarnings = xn_arr_s_new(0);
  loadBaseDir = rt_string_from_c("");
  loadRoot = rt_string_from_c("");
  xdkFullSource = 0;
  rootPackageName = rt_string_from_c("");
  unitDeclNodes = xn_arr_o_new(0);
  unitDeclPkgs = xn_arr_s_new(0);
  unitImportOwners = xn_arr_s_new(0);
  unitImportPkgs = xn_arr_s_new(0);
  ffiNames = xn_arr_s_new(0);
  ffiCNames = xn_arr_s_new(0);
  ffiRets = xn_arr_s_new(0);
  ffiParamSpecs = xn_arr_s_new(0);
  ffiErrParams = xn_arr_s_new(0);
  ffiErrRets = xn_arr_s_new(0);
  a8ErrorCode = rt_string_from_c("");
  a8ErrorMessage = rt_string_from_c("");
  a8ErrorLine = 1;
  a8ErrorCol = 1;
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

static int64_t xn_hexValue(rt_string * c) {
  if (xn_str_eq(c, rt_string_from_c("0"))) {
    return xn_int_wrap(0);
  }
  if (xn_str_eq(c, rt_string_from_c("1"))) {
    return xn_int_wrap(1);
  }
  if (xn_str_eq(c, rt_string_from_c("2"))) {
    return xn_int_wrap(2);
  }
  if (xn_str_eq(c, rt_string_from_c("3"))) {
    return xn_int_wrap(3);
  }
  if (xn_str_eq(c, rt_string_from_c("4"))) {
    return xn_int_wrap(4);
  }
  if (xn_str_eq(c, rt_string_from_c("5"))) {
    return xn_int_wrap(5);
  }
  if (xn_str_eq(c, rt_string_from_c("6"))) {
    return xn_int_wrap(6);
  }
  if (xn_str_eq(c, rt_string_from_c("7"))) {
    return xn_int_wrap(7);
  }
  if (xn_str_eq(c, rt_string_from_c("8"))) {
    return xn_int_wrap(8);
  }
  if (xn_str_eq(c, rt_string_from_c("9"))) {
    return xn_int_wrap(9);
  }
  if ((xn_str_eq(c, rt_string_from_c("a")) || xn_str_eq(c, rt_string_from_c("A")))) {
    return xn_int_wrap(10);
  }
  if ((xn_str_eq(c, rt_string_from_c("b")) || xn_str_eq(c, rt_string_from_c("B")))) {
    return xn_int_wrap(11);
  }
  if ((xn_str_eq(c, rt_string_from_c("c")) || xn_str_eq(c, rt_string_from_c("C")))) {
    return xn_int_wrap(12);
  }
  if ((xn_str_eq(c, rt_string_from_c("d")) || xn_str_eq(c, rt_string_from_c("D")))) {
    return xn_int_wrap(13);
  }
  if ((xn_str_eq(c, rt_string_from_c("e")) || xn_str_eq(c, rt_string_from_c("E")))) {
    return xn_int_wrap(14);
  }
  return xn_int_wrap(15);
}

static int xn_validScalar(int64_t value) {
  if (((value < 0) || (value > 0x10FFFF))) {
    return 0;
  }
  if (((value >= 0xD800) && (value <= 0xDFFF))) {
    return 0;
  }
  return 1;
}

static int xn_validEscapeAt(rt_string * src, int64_t slash, int64_t limit) {
  if ((xn_int_wrap((slash + 1)) >= limit)) {
    return 0;
  }
  rt_string * e = xn_at(src, xn_int_wrap((slash + 1)));
  if (((((((xn_str_eq(e, rt_string_from_c("n")) || xn_str_eq(e, rt_string_from_c("r"))) || xn_str_eq(e, rt_string_from_c("t"))) || xn_str_eq(e, rt_string_from_c("0"))) || xn_str_eq(e, rt_string_from_c("\\"))) || xn_str_eq(e, rt_string_from_c("'"))) || xn_str_eq(e, rt_string_from_c("\"")))) {
    return 1;
  }
  if (xn_str_eq(e, rt_string_from_c("x"))) {
    return (((xn_int_wrap((slash + 3)) < limit) && xn_isHex(xn_at(src, xn_int_wrap((slash + 2))))) && xn_isHex(xn_at(src, xn_int_wrap((slash + 3)))));
  }
  if (xn_str_eq(e, rt_string_from_c("u"))) {
    if (((xn_int_wrap((slash + 2)) < limit) && xn_str_eq(xn_at(src, xn_int_wrap((slash + 2))), rt_string_from_c("{")))) {
      int64_t j = xn_int_wrap(xn_int_wrap((slash + 3)));
      int64_t digits = xn_int_wrap(0);
      int64_t value = xn_int_wrap(0);
      while (((j < limit) && (!xn_str_eq(xn_at(src, j), rt_string_from_c("}"))))) {
        rt_string * h = xn_at(src, j);
        if ((!xn_isHex(h))) {
          return 0;
        }
        value = xn_int_wrap((xn_int_wrap((value * 16)) + xn_hexValue(h)));
        digits = xn_int_wrap((digits + 1));
        if ((digits > 6)) {
          return 0;
        }
        j = xn_int_wrap((j + 1));
      }
      if ((((digits == 0) || (j >= limit)) || (!xn_str_eq(xn_at(src, j), rt_string_from_c("}"))))) {
        return 0;
      }
      return xn_validScalar(value);
    }
    if ((xn_int_wrap((slash + 5)) >= limit)) {
      return 0;
    }
    int64_t value = xn_int_wrap(0);
    int64_t k = xn_int_wrap(xn_int_wrap((slash + 2)));
    int64_t n = xn_int_wrap(0);
    while ((n < 4)) {
      rt_string * h = xn_at(src, k);
      if ((!xn_isHex(h))) {
        return 0;
      }
      value = xn_int_wrap((xn_int_wrap((value * 16)) + xn_hexValue(h)));
      k = xn_int_wrap((k + 1));
      n = xn_int_wrap((n + 1));
    }
    return xn_validScalar(value);
  }
  return 0;
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

static rt_string * xn_cStringLiteral(rt_string * content) {
  rt_string * out = rt_string_from_c("\"");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)content->len))) {
    rt_string * c = xn_at(content, i);
    if (xn_str_eq(c, rt_string_from_c("\\"))) {
      out = xn_concat(out, rt_string_from_c("\\\\"));
    }
    else {
      if (xn_str_eq(c, rt_string_from_c("\""))) {
        out = xn_concat(out, rt_string_from_c("\\\""));
      }
      else {
        if (xn_str_eq(c, rt_string_from_c("\n"))) {
          out = xn_concat(out, rt_string_from_c("\\n"));
        }
        else {
          if (xn_str_eq(c, rt_string_from_c("\r"))) {
            out = xn_concat(out, rt_string_from_c("\\r"));
          }
          else {
            if (xn_str_eq(c, rt_string_from_c("\t"))) {
              out = xn_concat(out, rt_string_from_c("\\t"));
            }
            else {
              out = xn_concat(out, c);
            }
          }
        }
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_concat(out, rt_string_from_c("\""));
}

static rt_string * xn_canonicalStringLiteral(rt_string * raw) {
  if ((((int64_t)raw->len) < 2)) {
    return raw;
  }
  rt_string * content = xn_str_substr(raw, 1, xn_int_wrap((((int64_t)raw->len) - 2)));
  rt_string * out = rt_string_from_c("\"");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)content->len))) {
    rt_string * c = xn_at(content, i);
    if (xn_str_eq(c, rt_string_from_c("\\"))) {
      rt_string * e = xn_at(content, xn_int_wrap((i + 1)));
      if (xn_str_eq(e, rt_string_from_c("0"))) {
        out = xn_concat(out, rt_string_new("\\000", sizeof("\\000") - 1));
      }
      else {
        out = xn_concat(xn_concat(out, rt_string_from_c("\\")), e);
      }
      i = xn_int_wrap((i + 2));
    }
    else {
      out = xn_concat(out, c);
      i = xn_int_wrap((i + 1));
    }
  }
  return xn_concat(out, rt_string_from_c("\""));
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
    if ((xn_str_eq(c, rt_string_from_c("r")) && xn_str_eq(next, rt_string_from_c("\"")))) {
      int triple = xn_starts(src, i, rt_string_from_c("r\"\"\""));
      i = xn_int_wrap((i + 1));
      col = xn_int_wrap((col + 1));
      int64_t contentStart = xn_int_wrap(i);
      int rawClosed = 0;
      if (triple) {
        i = xn_int_wrap((i + 3));
        col = xn_int_wrap((col + 3));
        contentStart = i;
        while ((i < ((int64_t)src->len))) {
          if (xn_starts(src, i, rt_string_from_c("\"\"\""))) {
            rt_string * content = xn_str_substr(src, contentStart, xn_int_wrap((i - contentStart)));
            xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("string"), xn_cStringLiteral(content), startLine, startCol));
            i = xn_int_wrap((i + 3));
            col = xn_int_wrap((col + 3));
            rawClosed = 1;
            break;
          }
          if (xn_str_eq(xn_at(src, i), rt_string_from_c("\n"))) {
            line = xn_int_wrap((line + 1));
            col = 1;
          }
          else {
            col = xn_int_wrap((col + 1));
          }
          i = xn_int_wrap((i + 1));
        }
      }
      else {
        i = xn_int_wrap((i + 1));
        col = xn_int_wrap((col + 1));
        contentStart = i;
        while ((i < ((int64_t)src->len))) {
          rt_string * d = xn_at(src, i);
          if (xn_str_eq(d, rt_string_from_c("\""))) {
            rt_string * content = xn_str_substr(src, contentStart, xn_int_wrap((i - contentStart)));
            xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("string"), xn_cStringLiteral(content), startLine, startCol));
            i = xn_int_wrap((i + 1));
            col = xn_int_wrap((col + 1));
            rawClosed = 1;
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
      }
      if ((!rawClosed)) {
        xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("error"), rt_string_from_c("unterminated raw string"), startLine, startCol));
        return tokens;
      }
      continue;
    }
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
        if (((i < ((int64_t)src->len)) && (xn_str_eq(xn_at(src, i), rt_string_from_c("L")) || xn_str_eq(xn_at(src, i), rt_string_from_c("l"))))) {
          rt_string * text = xn_str_substr(src, start, xn_int_wrap((i - start)));
          i = xn_int_wrap((i + 1));
          col = xn_int_wrap((col + 1));
          xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("long"), text, startLine, startCol));
        }
        else {
          xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("int"), xn_str_substr(src, start, xn_int_wrap((i - start))), startLine, startCol));
        }
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
        if (((i < ((int64_t)src->len)) && (xn_str_eq(xn_at(src, i), rt_string_from_c("L")) || xn_str_eq(xn_at(src, i), rt_string_from_c("l"))))) {
          rt_string * text = xn_str_substr(src, start, xn_int_wrap((i - start)));
          i = xn_int_wrap((i + 1));
          col = xn_int_wrap((col + 1));
          xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("long"), text, startLine, startCol));
        }
        else {
          xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("int"), xn_str_substr(src, start, xn_int_wrap((i - start))), startLine, startCol));
        }
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
          if ((!xn_validEscapeAt(src, i, ((int64_t)src->len)))) {
            xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("error"), rt_string_from_c("invalid escape sequence"), startLine, startCol));
            return tokens;
          }
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
        xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("string"), xn_canonicalStringLiteral(xn_str_substr(src, start, xn_int_wrap((i - start)))), startLine, startCol));
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
          if ((!xn_validEscapeAt(src, i, ((int64_t)src->len)))) {
            xn_arr_o_push(tokens, xn_Cls_Token_new(rt_string_from_c("error"), rt_string_from_c("invalid escape sequence"), startLine, startCol));
            return tokens;
          }
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
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.annotations")) || xn_str_startswith(pkg, rt_string_from_c("xdk.annotations.")))) {
    return rt_string_from_c("annotations/Annotations.x");
  }
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
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.functional")) || xn_str_startswith(pkg, rt_string_from_c("xdk.functional.")))) {
    return rt_string_from_c("functional/Functional.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.graph")) || xn_str_startswith(pkg, rt_string_from_c("xdk.graph.")))) {
    return rt_string_from_c("graph/Graph.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.stats")) || xn_str_startswith(pkg, rt_string_from_c("xdk.stats.")))) {
    return rt_string_from_c("stats/Stats.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.net.uri")) || xn_str_startswith(pkg, rt_string_from_c("xdk.net.uri.")))) {
    return rt_string_from_c("net/uri/Uri.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.net.mime")) || xn_str_startswith(pkg, rt_string_from_c("xdk.net.mime.")))) {
    return rt_string_from_c("net/mime/Mime.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.tensor")) || xn_str_startswith(pkg, rt_string_from_c("xdk.tensor.")))) {
    return rt_string_from_c("tensor/Tensor.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.linalg")) || xn_str_startswith(pkg, rt_string_from_c("xdk.linalg.")))) {
    return rt_string_from_c("linalg/Linalg.x");
  }
  if ((xn_str_eq(pkg, rt_string_from_c("xdk.geo")) || xn_str_startswith(pkg, rt_string_from_c("xdk.geo.")))) {
    return rt_string_from_c("geo/Geo.x");
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

static rt_string * xn_packageNameOf(xn_Cls_AstNode * program) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(program->kids, i));
    if (xn_str_eq(n->kind, rt_string_from_c("Package"))) {
      return n->text;
    }
    i = xn_int_wrap((i + 1));
  }
  return rt_string_from_c("");
}

static rt_string * xn_declPackageOf(xn_Cls_AstNode * n) {
  if ((!xn_str_eq(n->packageName, rt_string_from_c("")))) {
    return n->packageName;
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)unitDeclNodes->len))) {
    if ((((xn_Cls_AstNode *)xn_arr_o_get(unitDeclNodes, i)) == n)) {
      return xn_arr_s_get(unitDeclPkgs, i);
    }
    i = xn_int_wrap((i + 1));
  }
  return rootPackageName;
}

static void xn_mergeDecls(xn_Cls_AstNode * program, xn_Cls_AstNode * parsed) {
  rt_string * pkg = xn_packageNameOf(parsed);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)parsed->kids->len))) {
    xn_Cls_AstNode * d = ((xn_Cls_AstNode *)xn_arr_o_get(parsed->kids, i));
    if (xn_str_eq(d->kind, rt_string_from_c("Import"))) {
      xn_arr_s_push(unitImportOwners, pkg);
      xn_arr_s_push(unitImportPkgs, d->text);
    }
    if (((!xn_str_eq(d->kind, rt_string_from_c("Package"))) && (!xn_str_eq(d->kind, rt_string_from_c("Import"))))) {
      d->packageName = pkg;
      xn_arr_o_push(unitDeclNodes, d);
      xn_arr_s_push(unitDeclPkgs, pkg);
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

static rt_string * xn_simpleTypeUseName(rt_string * name) {
  int64_t last = xn_int_wrap(xn_int_wrap(-(1)));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)name->len))) {
    if (xn_str_eq(xn_str_substr(name, i, 1), rt_string_from_c("."))) {
      last = i;
    }
    i = xn_int_wrap((i + 1));
  }
  if ((last >= 0)) {
    return xn_str_substr(name, xn_int_wrap((last + 1)), xn_int_wrap((xn_int_wrap((((int64_t)name->len) - last)) - 1)));
  }
  return name;
}

static rt_string * xn_targetPath(xn_Cls_AstNode * n) {
  if (xn_str_eq(n->kind, rt_string_from_c("Name"))) {
    return n->text;
  }
  if ((xn_str_eq(n->kind, rt_string_from_c("Member")) && (((int64_t)n->kids->len) > 0))) {
    rt_string * b = xn_targetPath(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, 0)));
    if (xn_str_eq(b, rt_string_from_c(""))) {
      return n->text;
    }
    return xn_concat(xn_concat(b, rt_string_from_c(".")), n->text);
  }
  return n->text;
}

static xn_arr_s * xn_annotationTargetSet(xn_Cls_AstNode * program, rt_string * useText) {
  xn_arr_s *targets = xn_arr_s_new(0);
  rt_string * simple = xn_simpleTypeUseName(useText);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)program->kids->len))) {
    xn_Cls_AstNode * d = ((xn_Cls_AstNode *)xn_arr_o_get(program->kids, i));
    if ((xn_str_eq(d->kind, rt_string_from_c("AnnotationDecl")) && xn_str_eq(d->text, simple))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)d->annotations->len))) {
        xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(d->annotations, j));
        if (xn_str_eq(xn_simpleTypeUseName(use->text), rt_string_from_c("Target"))) {
          int64_t k = xn_int_wrap(0);
          while ((k < ((int64_t)use->kids->len))) {
            xn_Cls_AstNode * arg = ((xn_Cls_AstNode *)xn_arr_o_get(use->kids, k));
            if ((((int64_t)arg->kids->len) > 0)) {
              rt_string * p = xn_targetPath(((xn_Cls_AstNode *)xn_arr_o_get(arg->kids, 0)));
              if ((!xn_str_eq(p, rt_string_from_c("")))) {
                xn_arr_s_push(targets, xn_simpleTypeUseName(p));
              }
            }
            k = xn_int_wrap((k + 1));
          }
        }
        j = xn_int_wrap((j + 1));
      }
      return targets;
    }
    i = xn_int_wrap((i + 1));
  }
  return targets;
}

static int xn_typeUsePosition(xn_Cls_AstNode * n) {
  return ((((((xn_str_eq(n->kind, rt_string_from_c("Field")) || xn_str_eq(n->kind, rt_string_from_c("Param"))) || xn_str_eq(n->kind, rt_string_from_c("Ret"))) || xn_str_eq(n->kind, rt_string_from_c("Local"))) || xn_str_eq(n->kind, rt_string_from_c("Method"))) || xn_str_eq(n->kind, rt_string_from_c("Func"))) || xn_str_eq(n->kind, rt_string_from_c("Sig")));
}

static void xn_splitTypeUseAnnotationsIn(xn_Cls_AstNode * n, xn_Cls_AstNode * program) {
  if ((((int64_t)n->annotations->len) > 0)) {
    xn_arr_o *keep = xn_arr_o_new(0);
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)n->annotations->len))) {
      xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(n->annotations, i));
      xn_arr_s * targets = xn_annotationTargetSet(program, use->text);
      int hasTypeUse = 0;
      int64_t t = xn_int_wrap(0);
      while ((t < ((int64_t)targets->len))) {
        if (xn_str_eq(xn_arr_s_get(targets, t), rt_string_from_c("TypeUse"))) {
          hasTypeUse = 1;
        }
        t = xn_int_wrap((t + 1));
      }
      if ((hasTypeUse && (((int64_t)targets->len) == 1))) {
        if (xn_typeUsePosition(n)) {
          xn_arr_o_push(n->typeAnnotations, use);
        }
        else {
          xn_arr_o_push(keep, use);
        }
      }
      else {
        if ((hasTypeUse && (((int64_t)targets->len) > 1))) {
          if (xn_typeUsePosition(n)) {
            use->annotationError = xn_concat(xn_concat(rt_string_from_c("ambiguous annotation @"), use->text), rt_string_from_c(": TypeUse and declaration targets; split it or remove one target"));
          }
          xn_arr_o_push(keep, use);
        }
        else {
          xn_arr_o_push(keep, use);
        }
      }
      i = xn_int_wrap((i + 1));
    }
    n->annotations = keep;
  }
  int64_t k = xn_int_wrap(0);
  while ((k < ((int64_t)n->kids->len))) {
    xn_splitTypeUseAnnotationsIn(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, k)), program);
    k = xn_int_wrap((k + 1));
  }
}

static void xn_splitTypeUseAnnotations(xn_Cls_AstNode * program) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(program->kids, i));
    if (((!xn_str_eq(n->kind, rt_string_from_c("Package"))) && (!xn_str_eq(n->kind, rt_string_from_c("Import"))))) {
      xn_splitTypeUseAnnotationsIn(n, program);
    }
    i = xn_int_wrap((i + 1));
  }
}

static rt_string * xn_annotationCandidates(rt_string * simple) {
  rt_string * result = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)unitDeclNodes->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(unitDeclNodes, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl")) && xn_str_eq(n->text, simple))) {
      rt_string * p = xn_arr_s_get(unitDeclPkgs, i);
      int seen = 0;
      int64_t k = xn_int_wrap(0);
      while ((k < i)) {
        xn_Cls_AstNode * old = ((xn_Cls_AstNode *)xn_arr_o_get(unitDeclNodes, k));
        if (((xn_str_eq(old->kind, rt_string_from_c("AnnotationDecl")) && xn_str_eq(old->text, simple)) && xn_str_eq(xn_arr_s_get(unitDeclPkgs, k), p))) {
          seen = 1;
          break;
        }
        k = xn_int_wrap((k + 1));
      }
      if ((!seen)) {
        if ((!xn_str_eq(result, rt_string_from_c("")))) {
          result = xn_concat(result, rt_string_from_c(","));
        }
        result = xn_concat(result, p);
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return result;
}

static void xn_resolveAnnotationUse(xn_Cls_AstNode * use, rt_string * ownerPkg) {
  if ((!xn_str_eq(use->kind, rt_string_from_c("AnnotationUse")))) {
    return;
  }
  if ((xn_str_indexof(use->text, rt_string_from_c(".")) >= 0)) {
    use->resolvedAnnotationName = use->text;
    return;
  }
  rt_string * simple = use->text;
  int64_t same = xn_int_wrap(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)unitDeclNodes->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(unitDeclNodes, i));
    if (((xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl")) && xn_str_eq(n->text, simple)) && xn_str_eq(xn_arr_s_get(unitDeclPkgs, i), ownerPkg))) {
      same = xn_int_wrap((same + 1));
      use->resolvedAnnotationName = xn_concat(xn_concat(ownerPkg, rt_string_from_c(".")), simple);
    }
    i = xn_int_wrap((i + 1));
  }
  if ((same > 0)) {
    return;
  }
  rt_string * hitPkg = rt_string_from_c("");
  int64_t hits = xn_int_wrap(0);
  i = 0;
  while ((i < ((int64_t)unitImportOwners->len))) {
    if (xn_str_eq(xn_arr_s_get(unitImportOwners, i), ownerPkg)) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)unitDeclNodes->len))) {
        xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(unitDeclNodes, j));
        if (((xn_str_eq(n->kind, rt_string_from_c("AnnotationDecl")) && xn_str_eq(n->text, simple)) && xn_str_eq(xn_arr_s_get(unitDeclPkgs, j), xn_arr_s_get(unitImportPkgs, i)))) {
          hitPkg = xn_arr_s_get(unitImportPkgs, i);
          hits = xn_int_wrap((hits + 1));
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  if ((hits == 1)) {
    use->resolvedAnnotationName = xn_concat(xn_concat(hitPkg, rt_string_from_c(".")), simple);
    return;
  }
  if ((hits > 1)) {
    use->annotationError = xn_concat(xn_concat(xn_concat(rt_string_from_c("ambiguous annotation @"), simple), rt_string_from_c("; candidates: ")), xn_annotationCandidates(simple));
    return;
  }
  rt_string * all = xn_annotationCandidates(simple);
  if (((xn_str_indexof(all, rt_string_from_c(",")) < 0) && (!xn_str_eq(all, rt_string_from_c(""))))) {
    use->resolvedAnnotationName = xn_concat(xn_concat(all, rt_string_from_c(".")), simple);
  }
  else {
    if ((!xn_str_eq(all, rt_string_from_c("")))) {
      use->annotationError = xn_concat(xn_concat(xn_concat(rt_string_from_c("ambiguous annotation @"), simple), rt_string_from_c("; candidates: ")), all);
    }
  }
}

static void xn_resolveAnnotationTree(xn_Cls_AstNode * n, rt_string * ownerPkg) {
  if (xn_str_eq(n->kind, rt_string_from_c("AnnotationUse"))) {
    xn_resolveAnnotationUse(n, ownerPkg);
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)n->annotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(n->annotations, i));
    xn_resolveAnnotationUse(use, ownerPkg);
    xn_resolveAnnotationTree(use, ownerPkg);
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)n->typeAnnotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(n->typeAnnotations, i));
    xn_resolveAnnotationUse(use, ownerPkg);
    xn_resolveAnnotationTree(use, ownerPkg);
    i = xn_int_wrap((i + 1));
  }
  i = 0;
  while ((i < ((int64_t)n->kids->len))) {
    xn_resolveAnnotationTree(((xn_Cls_AstNode *)xn_arr_o_get(n->kids, i)), ownerPkg);
    i = xn_int_wrap((i + 1));
  }
}

static void xn_resolveAnnotationUses(xn_Cls_AstNode * program) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(program->kids, i));
    if (((!xn_str_eq(n->kind, rt_string_from_c("Package"))) && (!xn_str_eq(n->kind, rt_string_from_c("Import"))))) {
      xn_resolveAnnotationTree(n, xn_declPackageOf(n));
    }
    i = xn_int_wrap((i + 1));
  }
}

static rt_string * xn_a8SimpleName(rt_string * name) {
  int64_t last = xn_int_wrap(xn_int_wrap(-(1)));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)name->len))) {
    if (xn_str_eq(xn_str_substr(name, i, 1), rt_string_from_c("."))) {
      last = i;
    }
    i = xn_int_wrap((i + 1));
  }
  if ((last >= 0)) {
    return xn_str_substr(name, xn_int_wrap((last + 1)), xn_int_wrap((xn_int_wrap((((int64_t)name->len) - last)) - 1)));
  }
  return name;
}

static int xn_a8Fail(rt_string * code, rt_string * message, xn_Cls_AstNode * n) {
  a8ErrorCode = code;
  a8ErrorMessage = message;
  a8ErrorLine = n->line;
  a8ErrorCol = n->col;
  return 0;
}

static int xn_a8HasAnno(xn_Cls_AstNode * cls, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->annotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(cls->annotations, i));
    rt_string * useName = use->text;
    if ((!xn_str_eq(use->resolvedAnnotationName, rt_string_from_c("")))) {
      useName = use->resolvedAnnotationName;
    }
    if (xn_str_eq(xn_a8SimpleName(useName), name)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_a8DropAnno(xn_Cls_AstNode * cls, rt_string * name) {
  xn_arr_o *keep = xn_arr_o_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->annotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(cls->annotations, i));
    rt_string * useName = use->text;
    if ((!xn_str_eq(use->resolvedAnnotationName, rt_string_from_c("")))) {
      useName = use->resolvedAnnotationName;
    }
    if ((!xn_str_eq(xn_a8SimpleName(useName), name))) {
      xn_arr_o_push(keep, use);
    }
    i = xn_int_wrap((i + 1));
  }
  cls->annotations = keep;
}

static xn_arr_s * xn_a8TypeParams(xn_Cls_AstNode * cls) {
  xn_arr_s *out = xn_arr_s_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("TypeParams"))) {
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)k->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(k->kids, j))->kind, rt_string_from_c("TypeParam"))) {
          xn_arr_s_push(out, ((xn_Cls_AstNode *)xn_arr_o_get(k->kids, j))->text);
        }
        j = xn_int_wrap((j + 1));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return out;
}

static rt_string * xn_a8ClassType(xn_Cls_AstNode * cls) {
  xn_arr_s * tps = xn_a8TypeParams(cls);
  if ((((int64_t)tps->len) == 0)) {
    return cls->text;
  }
  rt_string * joined = rt_string_from_c("");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)tps->len))) {
    if ((!xn_str_eq(joined, rt_string_from_c("")))) {
      joined = xn_concat(joined, rt_string_from_c(","));
    }
    joined = xn_concat(joined, xn_arr_s_get(tps, i));
    i = xn_int_wrap((i + 1));
  }
  return xn_concat(xn_concat(xn_concat(cls->text, rt_string_from_c("<")), joined), rt_string_from_c(">"));
}

static rt_string * xn_a8Capitalize(rt_string * name) {
  int64_t start = xn_int_wrap(0);
  while (((start < ((int64_t)name->len)) && xn_str_eq(xn_str_substr(name, start, 1), rt_string_from_c("_")))) {
    start = xn_int_wrap((start + 1));
  }
  rt_string * base = xn_str_substr(name, start, xn_int_wrap((((int64_t)name->len) - start)));
  if (xn_str_eq(base, rt_string_from_c(""))) {
    return rt_string_from_c("With");
  }
  return xn_concat(xn_str_case(xn_str_substr(base, 0, 1), 1), xn_str_substr(base, 1, xn_int_wrap((((int64_t)base->len) - 1))));
}

static int xn_a8MethodExists(xn_Cls_AstNode * cls, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if ((xn_str_eq(k->kind, rt_string_from_c("Method")) && xn_str_eq(k->text, name))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static xn_Cls_AstNode * xn_a8Method(rt_string * name, rt_string * retType, xn_Cls_AstNode * cls) {
  xn_Cls_AstNode * m = xn_Cls_AstNode_new(rt_string_from_c("Method"), name, cls->line, cls->col);
  xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Ret"), retType, cls->line, cls->col));
  xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Generated"), rt_string_from_c("A8"), cls->line, cls->col));
  return m;
}

static xn_Cls_AstNode * xn_a8SelfField(rt_string * field) {
  xn_Cls_AstNode * mem = xn_Cls_AstNode_new(rt_string_from_c("Member"), field, 1, 1);
  xn_Cls_AstNode_add(mem, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("self"), 1, 1));
  return mem;
}

static xn_Cls_AstNode * xn_a8OtherField(rt_string * field) {
  xn_Cls_AstNode * mem = xn_Cls_AstNode_new(rt_string_from_c("Member"), field, 1, 1);
  xn_Cls_AstNode_add(mem, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("other"), 1, 1));
  return mem;
}

static xn_arr_o * xn_a8InstanceFields(xn_Cls_AstNode * cls) {
  xn_arr_o *out = xn_arr_o_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Field"))) {
      int isStatic = 0;
      int64_t j = xn_int_wrap(0);
      while ((j < ((int64_t)k->kids->len))) {
        if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(k->kids, j))->kind, rt_string_from_c("Static"))) {
          isStatic = 1;
        }
        j = xn_int_wrap((j + 1));
      }
      if ((!isStatic)) {
        xn_arr_o_push(out, k);
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return out;
}

static int xn_a8IsFinalField(xn_Cls_AstNode * f) {
  return f->isFinalField;
}

static rt_string * xn_a8FieldType(xn_Cls_AstNode * f) {
  xn_arr_s * parts = xn_str_split(f->text, rt_string_from_c(" "));
  if ((((int64_t)parts->len) >= 1)) {
    return xn_arr_s_get(parts, 0);
  }
  return f->text;
}

static rt_string * xn_a8FieldName(xn_Cls_AstNode * f) {
  xn_arr_s * parts = xn_str_split(f->text, rt_string_from_c(" "));
  if ((((int64_t)parts->len) >= 2)) {
    return xn_arr_s_get(parts, 1);
  }
  return f->text;
}

static xn_Cls_AstNode * xn_a8Ctor(xn_Cls_AstNode * cls) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)cls->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i))->kind, rt_string_from_c("Ctor"))) {
      return ((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, i));
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), cls->line, cls->col);
}

static int xn_a8CtorMatches(xn_Cls_AstNode * cls, xn_arr_o * fields) {
  xn_Cls_AstNode * ctor = xn_a8Ctor(cls);
  if ((((int64_t)fields->len) == 0)) {
    return 1;
  }
  if (xn_str_eq(ctor->kind, rt_string_from_c("None"))) {
    return 0;
  }
  xn_arr_o *ps = xn_arr_o_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ctor->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(ctor->kids, i))->kind, rt_string_from_c("Param"))) {
      xn_arr_o_push(ps, ((xn_Cls_AstNode *)xn_arr_o_get(ctor->kids, i)));
    }
    i = xn_int_wrap((i + 1));
  }
  if ((((int64_t)ps->len) != ((int64_t)fields->len))) {
    return 0;
  }
  i = 0;
  while ((i < ((int64_t)fields->len))) {
    xn_arr_s * pp = xn_str_split(((xn_Cls_AstNode *)xn_arr_o_get(ps, i))->text, rt_string_from_c(" "));
    if (((((int64_t)pp->len) < 1) || (!xn_str_eq(xn_arr_s_get(pp, 0), xn_a8FieldType(((xn_Cls_AstNode *)xn_arr_o_get(fields, i))))))) {
      return 0;
    }
    i = xn_int_wrap((i + 1));
  }
  return 1;
}

static xn_Cls_AstNode * xn_a8EqualsMethod(xn_Cls_AstNode * cls, xn_arr_o * fields) {
  rt_string * ct = xn_a8ClassType(cls);
  xn_Cls_AstNode * m = xn_a8Method(rt_string_from_c("equals"), rt_string_from_c("Bool"), cls);
  xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(ct, rt_string_from_c(" other")), cls->line, cls->col));
  xn_Cls_AstNode * body = xn_Cls_AstNode_new(rt_string_from_c("Block"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode * notNull = xn_Cls_AstNode_new(rt_string_from_c("Binary"), rt_string_from_c("!="), cls->line, cls->col);
  xn_Cls_AstNode_add(notNull, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("other"), cls->line, cls->col));
  xn_Cls_AstNode_add(notNull, xn_Cls_AstNode_new(rt_string_from_c("Null"), rt_string_from_c(""), cls->line, cls->col));
  xn_Cls_AstNode * expr = notNull;
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fields->len))) {
    xn_Cls_AstNode * eq = xn_Cls_AstNode_new(rt_string_from_c("Binary"), rt_string_from_c("=="), cls->line, cls->col);
    xn_Cls_AstNode_add(eq, xn_a8SelfField(xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i)))));
    xn_Cls_AstNode_add(eq, xn_a8OtherField(xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i)))));
    xn_Cls_AstNode * both = xn_Cls_AstNode_new(rt_string_from_c("Binary"), rt_string_from_c("&&"), cls->line, cls->col);
    xn_Cls_AstNode_add(both, expr);
    xn_Cls_AstNode_add(both, eq);
    expr = both;
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode * ret = xn_Cls_AstNode_new(rt_string_from_c("Return"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode_add(ret, expr);
  xn_Cls_AstNode_add(body, ret);
  xn_Cls_AstNode_add(m, body);
  return m;
}

static xn_Cls_AstNode * xn_a8ToStringMethod(xn_Cls_AstNode * cls, xn_arr_o * fields) {
  xn_Cls_AstNode * m = xn_a8Method(rt_string_from_c("toString"), rt_string_from_c("String"), cls);
  xn_Cls_AstNode * body = xn_Cls_AstNode_new(rt_string_from_c("Block"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode * expr = xn_Cls_AstNode_new(rt_string_from_c("String"), xn_concat(xn_concat(rt_string_from_c("\""), cls->text), rt_string_from_c("(\"")), cls->line, cls->col);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fields->len))) {
    rt_string * fname = xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i)));
    if ((i > 0)) {
      xn_Cls_AstNode * sep = xn_Cls_AstNode_new(rt_string_from_c("Binary"), rt_string_from_c("+"), cls->line, cls->col);
      xn_Cls_AstNode_add(sep, expr);
      xn_Cls_AstNode_add(sep, xn_Cls_AstNode_new(rt_string_from_c("String"), rt_string_from_c("\", \""), cls->line, cls->col));
      expr = sep;
    }
    xn_Cls_AstNode * label = xn_Cls_AstNode_new(rt_string_from_c("Binary"), rt_string_from_c("+"), cls->line, cls->col);
    xn_Cls_AstNode_add(label, expr);
    xn_Cls_AstNode_add(label, xn_Cls_AstNode_new(rt_string_from_c("String"), xn_concat(xn_concat(rt_string_from_c("\""), fname), rt_string_from_c("=\"")), cls->line, cls->col));
    expr = label;
    xn_Cls_AstNode * call = xn_Cls_AstNode_new(rt_string_from_c("Call"), rt_string_from_c("str"), cls->line, cls->col);
    xn_Cls_AstNode_add(call, xn_a8SelfField(fname));
    xn_Cls_AstNode * val = xn_Cls_AstNode_new(rt_string_from_c("Binary"), rt_string_from_c("+"), cls->line, cls->col);
    xn_Cls_AstNode_add(val, expr);
    xn_Cls_AstNode_add(val, call);
    expr = val;
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode * close = xn_Cls_AstNode_new(rt_string_from_c("Binary"), rt_string_from_c("+"), cls->line, cls->col);
  xn_Cls_AstNode_add(close, expr);
  xn_Cls_AstNode_add(close, xn_Cls_AstNode_new(rt_string_from_c("String"), rt_string_from_c("\")\""), cls->line, cls->col));
  xn_Cls_AstNode * ret = xn_Cls_AstNode_new(rt_string_from_c("Return"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode_add(ret, close);
  xn_Cls_AstNode_add(body, ret);
  xn_Cls_AstNode_add(m, body);
  return m;
}

static xn_Cls_AstNode * xn_a8CopyMethod(xn_Cls_AstNode * cls, xn_arr_o * fields) {
  rt_string * ct = xn_a8ClassType(cls);
  xn_Cls_AstNode * m = xn_a8Method(rt_string_from_c("copy"), ct, cls);
  xn_Cls_AstNode * body = xn_Cls_AstNode_new(rt_string_from_c("Block"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode * nw = xn_Cls_AstNode_new(rt_string_from_c("New"), ct, cls->line, cls->col);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)fields->len))) {
    xn_Cls_AstNode_add(nw, xn_a8SelfField(xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i)))));
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode * ret = xn_Cls_AstNode_new(rt_string_from_c("Return"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode_add(ret, nw);
  xn_Cls_AstNode_add(body, ret);
  xn_Cls_AstNode_add(m, body);
  return m;
}

static xn_Cls_AstNode * xn_a8WithMethod(xn_Cls_AstNode * cls, xn_Cls_AstNode * field) {
  rt_string * ct = xn_a8ClassType(cls);
  rt_string * fname = xn_a8FieldName(field);
  xn_Cls_AstNode * m = xn_a8Method(xn_concat(rt_string_from_c("with"), xn_a8Capitalize(fname)), ct, cls);
  xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_a8FieldType(field), rt_string_from_c(" value")), cls->line, cls->col));
  xn_Cls_AstNode * body = xn_Cls_AstNode_new(rt_string_from_c("Block"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode * local = xn_Cls_AstNode_new(rt_string_from_c("Local"), xn_concat(ct, rt_string_from_c(" result")), cls->line, cls->col);
  xn_Cls_AstNode_add(local, xn_Cls_AstNode_new(rt_string_from_c("Call"), rt_string_from_c("self.copy"), cls->line, cls->col));
  xn_Cls_AstNode_add(body, local);
  xn_Cls_AstNode * set = xn_Cls_AstNode_new(rt_string_from_c("Assign"), rt_string_from_c("="), cls->line, cls->col);
  xn_Cls_AstNode * member = xn_Cls_AstNode_new(rt_string_from_c("Member"), fname, cls->line, cls->col);
  xn_Cls_AstNode_add(member, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("result"), cls->line, cls->col));
  xn_Cls_AstNode_add(set, member);
  xn_Cls_AstNode_add(set, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("value"), cls->line, cls->col));
  xn_Cls_AstNode_add(body, set);
  xn_Cls_AstNode * ret = xn_Cls_AstNode_new(rt_string_from_c("Return"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode_add(ret, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("result"), cls->line, cls->col));
  xn_Cls_AstNode_add(body, ret);
  xn_Cls_AstNode_add(m, body);
  return m;
}

static int xn_a8ClassExists(xn_Cls_AstNode * program, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(program->kids, i));
    if (((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || xn_str_eq(n->kind, rt_string_from_c("Enum"))) || xn_str_eq(n->kind, rt_string_from_c("Protocol"))) && xn_str_eq(n->text, name))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static xn_arr_o * xn_a8CtorParams(xn_Cls_AstNode * cls) {
  xn_arr_o *out = xn_arr_o_new(0);
  xn_Cls_AstNode * ctor = xn_a8Ctor(cls);
  if (xn_str_eq(ctor->kind, rt_string_from_c("None"))) {
    return out;
  }
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)ctor->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(ctor->kids, i))->kind, rt_string_from_c("Param"))) {
      xn_arr_o_push(out, ((xn_Cls_AstNode *)xn_arr_o_get(ctor->kids, i)));
    }
    i = xn_int_wrap((i + 1));
  }
  return out;
}

static rt_string * xn_a8ParamType(xn_Cls_AstNode * p) {
  xn_arr_s * parts = xn_str_split(p->text, rt_string_from_c(" "));
  if ((((int64_t)parts->len) >= 1)) {
    return xn_arr_s_get(parts, 0);
  }
  return p->text;
}

static rt_string * xn_a8ParamName(xn_Cls_AstNode * p) {
  xn_arr_s * parts = xn_str_split(p->text, rt_string_from_c(" "));
  if ((((int64_t)parts->len) >= 2)) {
    return xn_arr_s_get(parts, 1);
  }
  return p->text;
}

static xn_Cls_AstNode * xn_a8BuilderField(rt_string * ty, rt_string * name, xn_Cls_AstNode * cls) {
  return xn_Cls_AstNode_new(rt_string_from_c("Field"), xn_concat(xn_concat(ty, rt_string_from_c(" ")), name), cls->line, cls->col);
}

static xn_Cls_AstNode * xn_a8BuilderWith(xn_Cls_AstNode * builder, xn_Cls_AstNode * p, rt_string * fname, xn_Cls_AstNode * cls) {
  rt_string * bname = builder->text;
  rt_string * pname = fname;
  rt_string * cap = xn_a8Capitalize(pname);
  xn_Cls_AstNode * m = xn_a8Method(xn_concat(rt_string_from_c("with"), cap), bname, cls);
  xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Param"), xn_concat(xn_a8ParamType(p), rt_string_from_c(" value")), cls->line, cls->col));
  xn_Cls_AstNode * body = xn_Cls_AstNode_new(rt_string_from_c("Block"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode * set = xn_Cls_AstNode_new(rt_string_from_c("Assign"), rt_string_from_c("="), cls->line, cls->col);
  xn_Cls_AstNode * member = xn_Cls_AstNode_new(rt_string_from_c("Member"), xn_concat(rt_string_from_c("_"), pname), cls->line, cls->col);
  xn_Cls_AstNode_add(member, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("self"), cls->line, cls->col));
  xn_Cls_AstNode_add(set, member);
  xn_Cls_AstNode_add(set, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("value"), cls->line, cls->col));
  xn_Cls_AstNode_add(body, set);
  xn_Cls_AstNode * flag = xn_Cls_AstNode_new(rt_string_from_c("Assign"), rt_string_from_c("="), cls->line, cls->col);
  xn_Cls_AstNode * flagMember = xn_Cls_AstNode_new(rt_string_from_c("Member"), xn_concat(rt_string_from_c("_has"), cap), cls->line, cls->col);
  xn_Cls_AstNode_add(flagMember, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("self"), cls->line, cls->col));
  xn_Cls_AstNode_add(flag, flagMember);
  xn_Cls_AstNode_add(flag, xn_Cls_AstNode_new(rt_string_from_c("Bool"), rt_string_from_c("true"), cls->line, cls->col));
  xn_Cls_AstNode_add(body, flag);
  xn_Cls_AstNode * ret = xn_Cls_AstNode_new(rt_string_from_c("Return"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode_add(ret, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("self"), cls->line, cls->col));
  xn_Cls_AstNode_add(body, ret);
  xn_Cls_AstNode_add(m, body);
  return m;
}

static xn_Cls_AstNode * xn_a8BuilderBuild(xn_Cls_AstNode * builder, xn_Cls_AstNode * cls, xn_arr_o * params, xn_arr_o * fields) {
  xn_Cls_AstNode * m = xn_a8Method(rt_string_from_c("build"), cls->text, cls);
  xn_Cls_AstNode * body = xn_Cls_AstNode_new(rt_string_from_c("Block"), rt_string_from_c(""), cls->line, cls->col);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)params->len))) {
    rt_string * cap = xn_a8Capitalize(xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i))));
    xn_Cls_AstNode * has = xn_Cls_AstNode_new(rt_string_from_c("Member"), xn_concat(rt_string_from_c("_has"), cap), cls->line, cls->col);
    xn_Cls_AstNode_add(has, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("self"), cls->line, cls->col));
    xn_Cls_AstNode * cond = xn_Cls_AstNode_new(rt_string_from_c("Unary"), rt_string_from_c("!"), cls->line, cls->col);
    xn_Cls_AstNode_add(cond, has);
    xn_Cls_AstNode * ifn = xn_Cls_AstNode_new(rt_string_from_c("If"), rt_string_from_c(""), cls->line, cls->col);
    xn_Cls_AstNode_add(ifn, cond);
    xn_Cls_AstNode * block = xn_Cls_AstNode_new(rt_string_from_c("Block"), rt_string_from_c(""), cls->line, cls->col);
    xn_Cls_AstNode * thr = xn_Cls_AstNode_new(rt_string_from_c("Throw"), rt_string_from_c(""), cls->line, cls->col);
    xn_Cls_AstNode_add(thr, xn_Cls_AstNode_new(rt_string_from_c("String"), xn_concat(xn_concat(xn_concat(xn_concat(rt_string_from_c("\""), builder->text), rt_string_from_c(".build: missing field ")), xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i)))), rt_string_from_c("\"")), cls->line, cls->col));
    xn_Cls_AstNode_add(block, thr);
    xn_Cls_AstNode_add(ifn, block);
    xn_Cls_AstNode_add(body, ifn);
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode * nw = xn_Cls_AstNode_new(rt_string_from_c("New"), cls->text, cls->line, cls->col);
  i = 0;
  while ((i < ((int64_t)params->len))) {
    xn_Cls_AstNode * mem = xn_Cls_AstNode_new(rt_string_from_c("Member"), xn_concat(rt_string_from_c("_"), xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i)))), cls->line, cls->col);
    xn_Cls_AstNode_add(mem, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("self"), cls->line, cls->col));
    xn_Cls_AstNode_add(nw, mem);
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode * ret = xn_Cls_AstNode_new(rt_string_from_c("Return"), rt_string_from_c(""), cls->line, cls->col);
  xn_Cls_AstNode_add(ret, nw);
  xn_Cls_AstNode_add(body, ret);
  xn_Cls_AstNode_add(m, body);
  return m;
}

static xn_Cls_AstNode * xn_a8BuildBuilder(xn_Cls_AstNode * cls, xn_arr_o * params, xn_arr_o * fields) {
  rt_string * bname = xn_concat(cls->text, rt_string_from_c("Builder"));
  xn_Cls_AstNode * b = xn_Cls_AstNode_new(rt_string_from_c("Class"), bname, cls->line, cls->col);
  b->packageName = cls->packageName;
  xn_Cls_AstNode_add(b, xn_Cls_AstNode_new(rt_string_from_c("Generated"), rt_string_from_c("A8"), cls->line, cls->col));
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)params->len))) {
    xn_Cls_AstNode_add(b, xn_a8BuilderField(xn_a8ParamType(((xn_Cls_AstNode *)xn_arr_o_get(params, i))), xn_concat(rt_string_from_c("_"), xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i)))), cls));
    xn_Cls_AstNode_add(b, xn_a8BuilderField(rt_string_from_c("Bool"), xn_concat(rt_string_from_c("_has"), xn_a8Capitalize(xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i))))), cls));
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode * ctor = xn_Cls_AstNode_new(rt_string_from_c("Ctor"), bname, cls->line, cls->col);
  xn_Cls_AstNode_add(ctor, xn_Cls_AstNode_new(rt_string_from_c("Block"), rt_string_from_c(""), cls->line, cls->col));
  xn_Cls_AstNode_add(b, ctor);
  i = 0;
  while ((i < ((int64_t)params->len))) {
    xn_Cls_AstNode_add(b, xn_a8BuilderWith(b, ((xn_Cls_AstNode *)xn_arr_o_get(params, i)), xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i))), cls));
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode_add(b, xn_a8BuilderBuild(b, cls, params, fields));
  return b;
}

static int xn_a8ListHas(xn_arr_s * items, rt_string * value) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)items->len))) {
    if (xn_str_eq(xn_arr_s_get(items, i), value)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static int xn_a8FieldHasAnno(xn_Cls_AstNode * f, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)f->annotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(f->annotations, i));
    rt_string * useName = use->text;
    if ((!xn_str_eq(use->resolvedAnnotationName, rt_string_from_c("")))) {
      useName = use->resolvedAnnotationName;
    }
    if (xn_str_eq(xn_a8SimpleName(useName), name)) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static void xn_a8DropFieldAnno(xn_Cls_AstNode * f, rt_string * name) {
  xn_arr_o *keep = xn_arr_o_new(0);
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)f->annotations->len))) {
    xn_Cls_AstNode * use = ((xn_Cls_AstNode *)xn_arr_o_get(f->annotations, i));
    rt_string * useName = use->text;
    if ((!xn_str_eq(use->resolvedAnnotationName, rt_string_from_c("")))) {
      useName = use->resolvedAnnotationName;
    }
    if ((!xn_str_eq(xn_a8SimpleName(useName), name))) {
      xn_arr_o_push(keep, use);
    }
    i = xn_int_wrap((i + 1));
  }
  f->annotations = keep;
}

static xn_Cls_AstNode * xn_a8FindClassIn(xn_Cls_AstNode * program, rt_string * name) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(program->kids, i));
    if ((xn_str_eq(n->kind, rt_string_from_c("Class")) && xn_str_eq(n->text, name))) {
      return n;
    }
    i = xn_int_wrap((i + 1));
  }
  return xn_Cls_AstNode_new(rt_string_from_c("None"), rt_string_from_c(""), 1, 1);
}

static rt_string * xn_a8TypeBase(rt_string * ty) {
  int64_t p = xn_int_wrap(xn_str_indexof(ty, rt_string_from_c("<")));
  if ((p > 0)) {
    return xn_str_substr(ty, 0, p);
  }
  return ty;
}

static int xn_a8MethodStatic(xn_Cls_AstNode * m) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)m->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(m->kids, i))->kind, rt_string_from_c("Static"))) {
      return 1;
    }
    i = xn_int_wrap((i + 1));
  }
  return 0;
}

static xn_Cls_AstNode * xn_a8DelegateMethod(xn_Cls_AstNode * host, xn_Cls_AstNode * field, xn_Cls_AstNode * target) {
  rt_string * fieldName = xn_a8FieldName(field);
  rt_string * mname = target->text;
  rt_string * ret = rt_string_from_c("Unit");
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)target->kids->len))) {
    if (xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(target->kids, i))->kind, rt_string_from_c("Ret"))) {
      ret = ((xn_Cls_AstNode *)xn_arr_o_get(target->kids, i))->text;
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode * m = xn_a8Method(mname, ret, host);
  xn_Cls_AstNode * call = xn_Cls_AstNode_new(rt_string_from_c("MethodCall"), mname, host->line, host->col);
  xn_Cls_AstNode * recv = xn_Cls_AstNode_new(rt_string_from_c("Member"), fieldName, host->line, host->col);
  xn_Cls_AstNode_add(recv, xn_Cls_AstNode_new(rt_string_from_c("Name"), rt_string_from_c("self"), host->line, host->col));
  xn_Cls_AstNode_add(call, recv);
  i = 0;
  while ((i < ((int64_t)target->kids->len))) {
    xn_Cls_AstNode * k = ((xn_Cls_AstNode *)xn_arr_o_get(target->kids, i));
    if (xn_str_eq(k->kind, rt_string_from_c("Param"))) {
      xn_Cls_AstNode_add(m, xn_Cls_AstNode_new(rt_string_from_c("Param"), k->text, k->line, k->col));
      xn_arr_s * pp = xn_str_split(k->text, rt_string_from_c(" "));
      if ((((int64_t)pp->len) >= 2)) {
        xn_Cls_AstNode_add(call, xn_Cls_AstNode_new(rt_string_from_c("Name"), xn_arr_s_get(pp, 1), k->line, k->col));
      }
    }
    i = xn_int_wrap((i + 1));
  }
  xn_Cls_AstNode * body = xn_Cls_AstNode_new(rt_string_from_c("Block"), rt_string_from_c(""), host->line, host->col);
  if ((xn_str_eq(ret, rt_string_from_c("Void")) || xn_str_eq(ret, rt_string_from_c("Unit")))) {
    xn_Cls_AstNode * st = xn_Cls_AstNode_new(rt_string_from_c("ExprStmt"), rt_string_from_c(""), host->line, host->col);
    xn_Cls_AstNode_add(st, call);
    xn_Cls_AstNode_add(body, st);
  }
  else {
    xn_Cls_AstNode * r = xn_Cls_AstNode_new(rt_string_from_c("Return"), rt_string_from_c(""), host->line, host->col);
    xn_Cls_AstNode_add(r, call);
    xn_Cls_AstNode_add(body, r);
  }
  xn_Cls_AstNode_add(m, body);
  return m;
}

static int xn_expandA8Class(xn_Cls_AstNode * cls, xn_Cls_AstNode * program) {
  int v = xn_a8HasAnno(cls, rt_string_from_c("Value"));
  int d = xn_a8HasAnno(cls, rt_string_from_c("Data"));
  int c = xn_a8HasAnno(cls, rt_string_from_c("Copy"));
  int b = xn_a8HasAnno(cls, rt_string_from_c("Builder"));
  int fieldDelegate = 0;
  int64_t fdi = xn_int_wrap(0);
  while ((fdi < ((int64_t)cls->kids->len))) {
    if ((xn_str_eq(((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, fdi))->kind, rt_string_from_c("Field")) && xn_a8FieldHasAnno(((xn_Cls_AstNode *)xn_arr_o_get(cls->kids, fdi)), rt_string_from_c("Delegate")))) {
      fieldDelegate = 1;
    }
    fdi = xn_int_wrap((fdi + 1));
  }
  if ((((((!v) && (!d)) && (!c)) && (!b)) && (!fieldDelegate))) {
    return 1;
  }
  if ((!xn_str_eq(cls->kind, rt_string_from_c("Class")))) {
    return xn_a8Fail(rt_string_from_c("AN0021"), rt_string_from_c("@Value/@Data/@Copy/@Builder require a class"), cls);
  }
  xn_a8DropAnno(cls, rt_string_from_c("Value"));
  xn_a8DropAnno(cls, rt_string_from_c("Data"));
  xn_a8DropAnno(cls, rt_string_from_c("Copy"));
  xn_a8DropAnno(cls, rt_string_from_c("Builder"));
  xn_arr_o * fields = xn_a8InstanceFields(cls);
  xn_arr_o *delegateFields = xn_arr_o_new(0);
  int64_t dfi = xn_int_wrap(0);
  while ((dfi < ((int64_t)fields->len))) {
    if (xn_a8FieldHasAnno(((xn_Cls_AstNode *)xn_arr_o_get(fields, dfi)), rt_string_from_c("Delegate"))) {
      xn_a8DropFieldAnno(((xn_Cls_AstNode *)xn_arr_o_get(fields, dfi)), rt_string_from_c("Delegate"));
      xn_arr_o_push(delegateFields, ((xn_Cls_AstNode *)xn_arr_o_get(fields, dfi)));
    }
    dfi = xn_int_wrap((dfi + 1));
  }
  if (((((int64_t)delegateFields->len) > 0) && (!xn_str_eq(cls->kind, rt_string_from_c("Class"))))) {
    return xn_a8Fail(rt_string_from_c("AN0021"), rt_string_from_c("@Delegate requires a class"), cls);
  }
  if (v) {
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)fields->len))) {
      if ((!xn_a8IsFinalField(((xn_Cls_AstNode *)xn_arr_o_get(fields, i))))) {
        return xn_a8Fail(rt_string_from_c("AN0021"), rt_string_from_c("@Value requires all instance fields final"), ((xn_Cls_AstNode *)xn_arr_o_get(fields, i)));
      }
      i = xn_int_wrap((i + 1));
    }
  }
  if (((v || d) && (!xn_a8CtorMatches(cls, fields)))) {
    return xn_a8Fail(rt_string_from_c("AN0022"), rt_string_from_c("constructor parameters must match field order and types"), cls);
  }
  if ((v || d)) {
    if (((xn_a8MethodExists(cls, rt_string_from_c("equals")) || xn_a8MethodExists(cls, rt_string_from_c("toString"))) || xn_a8MethodExists(cls, rt_string_from_c("copy")))) {
      return xn_a8Fail(rt_string_from_c("AN0023"), rt_string_from_c("generated method conflicts with existing method"), cls);
    }
    xn_Cls_AstNode_add(cls, xn_a8EqualsMethod(cls, fields));
    xn_Cls_AstNode_add(cls, xn_a8ToStringMethod(cls, fields));
    xn_Cls_AstNode_add(cls, xn_a8CopyMethod(cls, fields));
  }
  if (c) {
    if ((!xn_a8CtorMatches(cls, fields))) {
      return xn_a8Fail(rt_string_from_c("AN0022"), rt_string_from_c("constructor parameters must match field order and types"), cls);
    }
    if (((!v) && (!d))) {
      if (xn_a8MethodExists(cls, rt_string_from_c("copy"))) {
        return xn_a8Fail(rt_string_from_c("AN0023"), rt_string_from_c("generated copy conflicts with existing method"), cls);
      }
    }
    int64_t i = xn_int_wrap(0);
    while ((i < ((int64_t)fields->len))) {
      rt_string * wname = xn_concat(rt_string_from_c("with"), xn_a8Capitalize(xn_a8FieldName(((xn_Cls_AstNode *)xn_arr_o_get(fields, i)))));
      if (xn_a8MethodExists(cls, wname)) {
        return xn_a8Fail(rt_string_from_c("AN0023"), xn_concat(rt_string_from_c("generated method conflicts with existing method: "), wname), cls);
      }
      i = xn_int_wrap((i + 1));
    }
    if (((!v) && (!d))) {
      xn_Cls_AstNode_add(cls, xn_a8CopyMethod(cls, fields));
    }
    i = 0;
    while ((i < ((int64_t)fields->len))) {
      xn_Cls_AstNode_add(cls, xn_a8WithMethod(cls, ((xn_Cls_AstNode *)xn_arr_o_get(fields, i))));
      i = xn_int_wrap((i + 1));
    }
  }
  if (b) {
    if ((((int64_t)xn_a8TypeParams(cls)->len) > 0)) {
      return xn_a8Fail(rt_string_from_c("AN0025"), rt_string_from_c("generic @Builder is not supported yet"), cls);
    }
    if ((!xn_a8CtorMatches(cls, fields))) {
      return xn_a8Fail(rt_string_from_c("AN0022"), rt_string_from_c("constructor parameters must match field order and types"), cls);
    }
    rt_string * bname = xn_concat(cls->text, rt_string_from_c("Builder"));
    if (xn_a8ClassExists(program, bname)) {
      return xn_a8Fail(rt_string_from_c("AN0024"), xn_concat(rt_string_from_c("builder class already exists: "), bname), cls);
    }
    xn_Cls_AstNode_add(program, xn_a8BuildBuilder(cls, xn_a8CtorParams(cls), fields));
  }
  if ((((int64_t)delegateFields->len) > 0)) {
    xn_arr_s *generated = xn_arr_s_new(0);
    int64_t di = xn_int_wrap(0);
    while ((di < ((int64_t)delegateFields->len))) {
      xn_Cls_AstNode * f = ((xn_Cls_AstNode *)xn_arr_o_get(delegateFields, di));
      rt_string * targetName = xn_a8TypeBase(xn_a8FieldType(f));
      xn_Cls_AstNode * target = xn_a8FindClassIn(program, targetName);
      if (xn_str_eq(target->kind, rt_string_from_c("None"))) {
        return xn_a8Fail(rt_string_from_c("AN0027"), xn_concat(rt_string_from_c("@Delegate target is not a class: "), targetName), f);
      }
      if (((((int64_t)xn_a8TypeParams(target)->len) > 0) || (xn_str_indexof(xn_a8FieldType(f), rt_string_from_c("<")) >= 0))) {
        return xn_a8Fail(rt_string_from_c("AN0028"), xn_concat(rt_string_from_c("@Delegate target must be non-generic class: "), targetName), f);
      }
      int64_t mi = xn_int_wrap(0);
      while ((mi < ((int64_t)target->kids->len))) {
        xn_Cls_AstNode * tm = ((xn_Cls_AstNode *)xn_arr_o_get(target->kids, mi));
        if ((xn_str_eq(tm->kind, rt_string_from_c("Method")) && (!xn_a8MethodStatic(tm)))) {
          rt_string * mname = tm->text;
          if ((xn_a8MethodExists(cls, mname) || xn_a8ListHas(generated, mname))) {
            return xn_a8Fail(rt_string_from_c("AN0026"), xn_concat(rt_string_from_c("@Delegate method conflicts: "), mname), f);
          }
          xn_arr_s_push(generated, mname);
          xn_Cls_AstNode_add(cls, xn_a8DelegateMethod(cls, f, tm));
        }
        mi = xn_int_wrap((mi + 1));
      }
      di = xn_int_wrap((di + 1));
    }
  }
  return 1;
}

static int xn_expandA8Annotations(xn_Cls_AstNode * program) {
  int64_t i = xn_int_wrap(0);
  while ((i < ((int64_t)program->kids->len))) {
    xn_Cls_AstNode * n = ((xn_Cls_AstNode *)xn_arr_o_get(program->kids, i));
    if ((((xn_str_eq(n->kind, rt_string_from_c("Class")) || xn_str_eq(n->kind, rt_string_from_c("Struct"))) || xn_str_eq(n->kind, rt_string_from_c("Enum"))) || xn_str_eq(n->kind, rt_string_from_c("Protocol")))) {
      if ((!xn_expandA8Class(n, program))) {
        return 0;
      }
    }
    i = xn_int_wrap((i + 1));
  }
  return 1;
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
    return xn_Cls_AstNode_new(rt_string_from_c("Program"), rt_string_from_c(""), 1, 1);
  }
  xn_arr_s_push(loadedFiles, entry);
  rootPackageName = xn_packageNameOf(program);
  int64_t ri = xn_int_wrap(0);
  while ((ri < ((int64_t)program->kids->len))) {
    xn_Cls_AstNode * rn = ((xn_Cls_AstNode *)xn_arr_o_get(program->kids, ri));
    if (xn_str_eq(rn->kind, rt_string_from_c("Import"))) {
      xn_arr_s_push(unitImportOwners, rootPackageName);
      xn_arr_s_push(unitImportPkgs, rn->text);
    }
    if (((!xn_str_eq(rn->kind, rt_string_from_c("Package"))) && (!xn_str_eq(rn->kind, rt_string_from_c("Import"))))) {
      rn->packageName = rootPackageName;
    }
    ri = xn_int_wrap((ri + 1));
  }
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
  xn_splitTypeUseAnnotations(program);
  xn_resolveAnnotationUses(program);
  if ((!xn_expandA8Annotations(program))) {
    xn_print_str(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(entry, rt_string_from_c(":")), xn_str_int(a8ErrorLine)), rt_string_from_c(":")), xn_str_int(a8ErrorCol)), rt_string_from_c(": [")), a8ErrorCode), rt_string_from_c("] ")), a8ErrorMessage));
    return xn_Cls_AstNode_new(rt_string_from_c("Program"), rt_string_from_c(""), 1, 1);
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
    xn_print_str(rt_string_from_c("mini 1.0.0"));
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
    int64_t wi = xn_int_wrap(0);
    while ((wi < ((int64_t)c->warnings->len))) {
      xn_Cls_AnnotationDiag * d = ((xn_Cls_AnnotationDiag *)xn_arr_o_get(c->warnings, wi));
      xn_print_str(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_arr_s_get(args, 1), rt_string_from_c(":")), xn_str_int(d->line)), rt_string_from_c(":")), xn_str_int(d->col)), rt_string_from_c(": warning [")), d->code), rt_string_from_c("] ")), d->msg));
      wi = xn_int_wrap((wi + 1));
    }
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
    while ((((int64_t)compilerWarnings->len) > 0)) {
      xn_arr_s_remove(compilerWarnings, xn_int_wrap((((int64_t)compilerWarnings->len) - 1)));
    }
    int64_t wi = xn_int_wrap(0);
    while ((wi < ((int64_t)c->warnings->len))) {
      xn_Cls_AnnotationDiag * d = ((xn_Cls_AnnotationDiag *)xn_arr_o_get(c->warnings, wi));
      xdkc_diagnose_rc(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_arr_s_get(args, 1), rt_string_from_c(":")), xn_str_int(d->line)), rt_string_from_c(":")), xn_str_int(d->col)), rt_string_from_c(": warning [")), d->code), rt_string_from_c("] ")), d->msg)->bytes, xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_concat(xn_arr_s_get(args, 1), rt_string_from_c(":")), xn_str_int(d->line)), rt_string_from_c(":")), xn_str_int(d->col)), rt_string_from_c(": warning [")), d->code), rt_string_from_c("] ")), d->msg)->len);
      xn_arr_s_push(compilerWarnings, xn_concat(xn_concat(xn_concat(rt_string_from_c("warning ["), d->code), rt_string_from_c("] ")), d->msg));
      wi = xn_int_wrap((wi + 1));
    }
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
