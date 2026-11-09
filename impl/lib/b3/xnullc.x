import xdk.sys

// B3-03：xnullc Result/try/defer（XNull 版 AST -> C）。
//
// 输入：<entryPath> <xnast v1 AST dump>
// 输出：与 Go `xnull build --emit-c` 口径一致的 C 文本。
// 覆盖：Result 实例化、Ok/Err、isOk/isErr/value/error/unwrapOr、try、defer/errdefer、throw。

static String PRELUDE_HEAD = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\n\n";
static String PRELUDE_PRE_FATAL = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\n";
static String PRELUDE_PRE_A = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\n";
static String PRELUDE_PRE_B = "typedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\n";
static String PRELUDE_B1 = "typedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\n";
static String PRELUDE_B2 = "typedef int64_t xn_Enum_ErrorKind;\n";
static String PRELUDE_B3 = "static rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\n";
static String PRELUDE_FATAL_MID = "static void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\n\n";
static String PRELUDE_TAIL_A = "\nstatic void xn_init_vtables(void) {\n}\n\n";
static String PRELUDE_VT_OPEN = "\nstatic void xn_init_vtables(void) {\n";
static String PRELUDE_VT_CLOSE = "}\n\n";
static String PRELUDE_TAIL_B = "static void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_EN_OPEN = "static void xn_init_enums(void) {\n";
static String PRELUDE_EN_CLOSE = "}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_TAIL = "\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_ARR = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;\n\n\nstatic void xn_arr_i_deinit(void *p) {\n    xn_arr_i *a = (xn_arr_i *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_i = { \"List\", sizeof(xn_arr_i), xn_arr_i_deinit, NULL };\n\nstatic xn_arr_i *xn_arr_i_new(size_t cap) {\n    xn_arr_i *a = (xn_arr_i *)xn_gc_new(&RT_TYPE_xn_arr_i);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_i) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(int64_t) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_i_push(xn_arr_i *a, int64_t v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_i_set(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic int64_t xn_arr_i_remove(xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    int64_t old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_i_insert(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_i_clear(xn_arr_i *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_i_join(xn_arr_i *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, xn_str_int(a->data[i]));\n    }\n    return res;\n}\n\nstatic int64_t xn_main();\n\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_MAPSET = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;\n\ntypedef struct { rt_header hdr; xn_arr_i *a; } xn_set_i;\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *keys; int64_t *vals; } xn_map_s_i;\n\n\nstatic void xn_arr_i_deinit(void *p) {\n    xn_arr_i *a = (xn_arr_i *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_i = { \"List\", sizeof(xn_arr_i), xn_arr_i_deinit, NULL };\n\nstatic xn_arr_i *xn_arr_i_new(size_t cap) {\n    xn_arr_i *a = (xn_arr_i *)xn_gc_new(&RT_TYPE_xn_arr_i);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_i) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(int64_t) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_i_push(xn_arr_i *a, int64_t v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_i_set(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic int64_t xn_arr_i_remove(xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    int64_t old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_i_insert(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_i_clear(xn_arr_i *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_i_join(xn_arr_i *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, xn_str_int(a->data[i]));\n    }\n    return res;\n}\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *data; } xn_arr_s;\n\nstatic void xn_arr_s_scan(void *p, void (*visit)(void *)) {\n    xn_arr_s *a = (xn_arr_s *)p;\n    if (a->data == NULL) { return; }\n    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }\n}\n\nstatic void xn_arr_s_deinit(void *p) {\n    xn_arr_s *a = (xn_arr_s *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_s = { \"List\", sizeof(xn_arr_s), xn_arr_s_deinit, xn_arr_s_scan };\n\nstatic xn_arr_s *xn_arr_s_new(size_t cap) {\n    xn_arr_s *a = (xn_arr_s *)xn_gc_new(&RT_TYPE_xn_arr_s);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_s) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(rt_string *) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_s_push(xn_arr_s *a, rt_string * v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic rt_string * xn_arr_s_get(const xn_arr_s *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_s_set(xn_arr_s *a, int64_t i, rt_string * v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic rt_string * xn_arr_s_remove(xn_arr_s *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    rt_string * old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_s_insert(xn_arr_s *a, int64_t i, rt_string * v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_s_clear(xn_arr_s *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_s_join(xn_arr_s *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, rt_string_new(a->data[i]->bytes, a->data[i]->len));\n    }\n    return res;\n}\n\nstatic void xn_set_i_scan(void *p, void (*visit)(void *)) {\n    xn_set_i *s = (xn_set_i *)p;\n    if (s->a != NULL) { visit(s->a); }\n}\n\nstatic void xn_set_i_deinit(void *p) {\n    xn_set_i *s = (xn_set_i *)p;\n    s->a = NULL; /* 数组是 GC 对象，由 GC 回收 */\n}\n\nstatic const rt_type RT_TYPE_xn_set_i = { \"Set\", sizeof(xn_set_i), xn_set_i_deinit, xn_set_i_scan };\n\nstatic xn_set_i *xn_set_i_new(void) {\n    xn_set_i *s = (xn_set_i *)xn_gc_new(&RT_TYPE_xn_set_i);\n    memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_i) - sizeof(rt_header));\n    s->a = xn_arr_i_new(4);\n    return s;\n}\n\nstatic int xn_set_i_add(xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) { return 0; }\n    }\n    xn_arr_i_push(s->a, v);\n    return 1;\n}\n\nstatic int xn_set_i_has(const xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) { return 1; }\n    }\n    return 0;\n}\n\nstatic int64_t xn_set_i_at(const xn_set_i *s, int64_t i) {\n    if (i < 0 || (size_t)i >= s->a->len) { xn_fatal_oob(); }\n    return s->a->data[i];\n}\n\nstatic int xn_set_i_remove(xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) {\n            for (size_t j = i; j + 1 < s->a->len; j++) {\n                s->a->data[j] = s->a->data[j + 1];\n            }\n            s->a->len--;\n            return 1;\n        }\n    }\n    return 0;\n}\n\nstatic void xn_set_i_clear(xn_set_i *s) { xn_arr_i_clear(s->a); }\n\nstatic void xn_map_s_i_scan(void *p, void (*visit)(void *)) {\n    xn_map_s_i *m = (xn_map_s_i *)p;\n    if (m->keys != NULL) { for (size_t i = 0; i < m->len; i++) { visit(m->keys[i]); } }\n}\n\nstatic void xn_map_s_i_deinit(void *p) {\n    xn_map_s_i *m = (xn_map_s_i *)p;\n    if (m->keys != NULL) {\n        free(m->keys);\n        m->keys = NULL;\n    }\n    if (m->vals != NULL) {\n        free(m->vals);\n        m->vals = NULL;\n    }\n    m->len = 0;\n    m->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_map_s_i = { \"Map\", sizeof(xn_map_s_i), xn_map_s_i_deinit, xn_map_s_i_scan };\n\nstatic xn_map_s_i *xn_map_s_i_new(size_t cap) {\n    xn_map_s_i *m = (xn_map_s_i *)xn_gc_new(&RT_TYPE_xn_map_s_i);\n    memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_s_i) - sizeof(rt_header));\n    m->cap = cap ? cap : 4;\n    m->keys = malloc(sizeof(rt_string *) * m->cap);\n    m->vals = malloc(sizeof(int64_t) * m->cap);\n    if (m->keys == NULL || m->vals == NULL) { abort(); }\n    return m;\n}\n\nstatic long xn_map_s_i_find(const xn_map_s_i *m, rt_string * key) {\n    for (size_t i = 0; i < m->len; i++) {\n        if (m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0) { return (long)i; }\n    }\n    return -1;\n}\n\nstatic void xn_map_s_i_put(xn_map_s_i *m, rt_string * key, int64_t val) {\n    long i = xn_map_s_i_find(m, key);\n    if (i >= 0) {\n        m->vals[i] = val;\n        return;\n    }\n    if (m->len == m->cap) {\n        m->cap *= 2;\n        m->keys = realloc(m->keys, sizeof(rt_string *) * m->cap);\n        m->vals = realloc(m->vals, sizeof(int64_t) * m->cap);\n        if (m->keys == NULL || m->vals == NULL) { abort(); }\n    }\n    m->keys[m->len] = key;\n    m->vals[m->len] = val;\n    m->len++;\n}\n\nstatic int xn_map_s_i_has(const xn_map_s_i *m, rt_string * key) { return xn_map_s_i_find(m, key) >= 0; }\n\nstatic int64_t xn_map_s_i_get_or(const xn_map_s_i *m, rt_string * key, int64_t dflt) {\n    long i = xn_map_s_i_find(m, key);\n    return i >= 0 ? m->vals[i] : dflt;\n}\n\nstatic int xn_map_s_i_remove(xn_map_s_i *m, rt_string * key) {\n    long i = xn_map_s_i_find(m, key);\n    if (i < 0) { return 0; }\n    for (size_t j = (size_t)i; j + 1 < m->len; j++) {\n        m->keys[j] = m->keys[j + 1];\n        m->vals[j] = m->vals[j + 1];\n    }\n    m->len--;\n    return 1;\n}\n\nstatic void xn_map_s_i_clear(xn_map_s_i *m) {\n    m->len = 0;\n}\n\nstatic int xn_map_s_i_cmp_key(rt_string * a, rt_string * b) {\n    size_t n = a->len < b->len ? a->len : b->len;\n    int c = memcmp(a->bytes, b->bytes, n);\n    if (c != 0) { return c; }\n    return (a->len > b->len) - (a->len < b->len);\n}\n\nstatic void xn_map_s_i_sort_idx(const xn_map_s_i *m, size_t *idx) {\n    for (size_t i = 1; i < m->len; i++) {\n        size_t x = idx[i];\n        size_t j = i;\n        while (j > 0 && xn_map_s_i_cmp_key(m->keys[idx[j - 1]], m->keys[x]) > 0) {\n            idx[j] = idx[j - 1];\n            j--;\n        }\n        idx[j] = x;\n    }\n}\n\nstatic xn_arr_s *xn_map_s_i_keys(const xn_map_s_i *m) {\n    xn_arr_s *out = xn_arr_s_new(m->len);\n    if (m->len == 0) { return out; }\n    size_t *idx = malloc(sizeof(size_t) * m->len);\n    if (idx == NULL) { abort(); }\n    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }\n    xn_map_s_i_sort_idx(m, idx);\n    for (size_t i = 0; i < m->len; i++) { xn_arr_s_push(out, m->keys[idx[i]]); }\n    free(idx);\n    return out;\n}\n\nstatic xn_arr_i *xn_map_s_i_values(const xn_map_s_i *m) {\n    xn_arr_i *out = xn_arr_i_new(m->len);\n    if (m->len == 0) { return out; }\n    size_t *idx = malloc(sizeof(size_t) * m->len);\n    if (idx == NULL) { abort(); }\n    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }\n    xn_map_s_i_sort_idx(m, idx);\n    for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(out, m->vals[idx[i]]); }\n    free(idx);\n    return out;\n}\n\nstatic xn_opt_i xn_map_s_i_get(const xn_map_s_i *m, rt_string * key) {\n    xn_opt_i r;\n    long i = xn_map_s_i_find(m, key);\n    if (i < 0) { r.has = 0; r.v = 0; return r; }\n    r.has = 1;\n    r.v = m->vals[i];\n    return r;\n}\n\n\nstatic xn_arr_s *xn_str_split(rt_string *s, rt_string *sep) {\n    xn_arr_s *out = xn_arr_s_new(4);\n    if (sep->len == 0) {\n        rt_string *t = rt_string_new(s->bytes, s->len);\n        xn_arr_s_push(out, t);\n        rt_release(t);\n        return out;\n    }\n    size_t start = 0, i = 0;\n    while (i + sep->len <= s->len) {\n        if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) {\n            rt_string *t = rt_string_new(s->bytes + start, i - start);\n            xn_arr_s_push(out, t);\n            rt_release(t);\n            i += sep->len;\n            start = i;\n        } else {\n            i++;\n        }\n    }\n    rt_string *last = rt_string_new(s->bytes + start, s->len - start);\n    xn_arr_s_push(out, last);\n    rt_release(last);\n    return out;\n}\nstatic int64_t xn_main();\n\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_CONT = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;\n\ntypedef struct { rt_header hdr; xn_arr_i *a; } xn_set_i;\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *keys; int64_t *vals; } xn_map_s_i;\n\n\nstatic void xn_arr_i_deinit(void *p) {\n    xn_arr_i *a = (xn_arr_i *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_i = { \"List\", sizeof(xn_arr_i), xn_arr_i_deinit, NULL };\n\nstatic xn_arr_i *xn_arr_i_new(size_t cap) {\n    xn_arr_i *a = (xn_arr_i *)xn_gc_new(&RT_TYPE_xn_arr_i);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_i) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(int64_t) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_i_push(xn_arr_i *a, int64_t v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_i_set(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic int64_t xn_arr_i_remove(xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    int64_t old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_i_insert(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_i_clear(xn_arr_i *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_i_join(xn_arr_i *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, xn_str_int(a->data[i]));\n    }\n    return res;\n}\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *data; } xn_arr_s;\n\nstatic void xn_arr_s_scan(void *p, void (*visit)(void *)) {\n    xn_arr_s *a = (xn_arr_s *)p;\n    if (a->data == NULL) { return; }\n    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }\n}\n\nstatic void xn_arr_s_deinit(void *p) {\n    xn_arr_s *a = (xn_arr_s *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_s = { \"List\", sizeof(xn_arr_s), xn_arr_s_deinit, xn_arr_s_scan };\n\nstatic xn_arr_s *xn_arr_s_new(size_t cap) {\n    xn_arr_s *a = (xn_arr_s *)xn_gc_new(&RT_TYPE_xn_arr_s);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_s) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(rt_string *) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_s_push(xn_arr_s *a, rt_string * v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic rt_string * xn_arr_s_get(const xn_arr_s *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_s_set(xn_arr_s *a, int64_t i, rt_string * v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic rt_string * xn_arr_s_remove(xn_arr_s *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    rt_string * old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_s_insert(xn_arr_s *a, int64_t i, rt_string * v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_s_clear(xn_arr_s *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_s_join(xn_arr_s *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, rt_string_new(a->data[i]->bytes, a->data[i]->len));\n    }\n    return res;\n}\n\nstatic void xn_set_i_scan(void *p, void (*visit)(void *)) {\n    xn_set_i *s = (xn_set_i *)p;\n    if (s->a != NULL) { visit(s->a); }\n}\n\nstatic void xn_set_i_deinit(void *p) {\n    xn_set_i *s = (xn_set_i *)p;\n    s->a = NULL; /* 数组是 GC 对象，由 GC 回收 */\n}\n\nstatic const rt_type RT_TYPE_xn_set_i = { \"Set\", sizeof(xn_set_i), xn_set_i_deinit, xn_set_i_scan };\n\nstatic xn_set_i *xn_set_i_new(void) {\n    xn_set_i *s = (xn_set_i *)xn_gc_new(&RT_TYPE_xn_set_i);\n    memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_i) - sizeof(rt_header));\n    s->a = xn_arr_i_new(4);\n    return s;\n}\n\nstatic int xn_set_i_add(xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) { return 0; }\n    }\n    xn_arr_i_push(s->a, v);\n    return 1;\n}\n\nstatic int xn_set_i_has(const xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) { return 1; }\n    }\n    return 0;\n}\n\nstatic int64_t xn_set_i_at(const xn_set_i *s, int64_t i) {\n    if (i < 0 || (size_t)i >= s->a->len) { xn_fatal_oob(); }\n    return s->a->data[i];\n}\n\nstatic int xn_set_i_remove(xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) {\n            for (size_t j = i; j + 1 < s->a->len; j++) {\n                s->a->data[j] = s->a->data[j + 1];\n            }\n            s->a->len--;\n            return 1;\n        }\n    }\n    return 0;\n}\n\nstatic void xn_set_i_clear(xn_set_i *s) { xn_arr_i_clear(s->a); }\n\nstatic void xn_map_s_i_scan(void *p, void (*visit)(void *)) {\n    xn_map_s_i *m = (xn_map_s_i *)p;\n    if (m->keys != NULL) { for (size_t i = 0; i < m->len; i++) { visit(m->keys[i]); } }\n}\n\nstatic void xn_map_s_i_deinit(void *p) {\n    xn_map_s_i *m = (xn_map_s_i *)p;\n    if (m->keys != NULL) {\n        free(m->keys);\n        m->keys = NULL;\n    }\n    if (m->vals != NULL) {\n        free(m->vals);\n        m->vals = NULL;\n    }\n    m->len = 0;\n    m->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_map_s_i = { \"Map\", sizeof(xn_map_s_i), xn_map_s_i_deinit, xn_map_s_i_scan };\n\nstatic xn_map_s_i *xn_map_s_i_new(size_t cap) {\n    xn_map_s_i *m = (xn_map_s_i *)xn_gc_new(&RT_TYPE_xn_map_s_i);\n    memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_s_i) - sizeof(rt_header));\n    m->cap = cap ? cap : 4;\n    m->keys = malloc(sizeof(rt_string *) * m->cap);\n    m->vals = malloc(sizeof(int64_t) * m->cap);\n    if (m->keys == NULL || m->vals == NULL) { abort(); }\n    return m;\n}\n\nstatic long xn_map_s_i_find(const xn_map_s_i *m, rt_string * key) {\n    for (size_t i = 0; i < m->len; i++) {\n        if (m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0) { return (long)i; }\n    }\n    return -1;\n}\n\nstatic void xn_map_s_i_put(xn_map_s_i *m, rt_string * key, int64_t val) {\n    long i = xn_map_s_i_find(m, key);\n    if (i >= 0) {\n        m->vals[i] = val;\n        return;\n    }\n    if (m->len == m->cap) {\n        m->cap *= 2;\n        m->keys = realloc(m->keys, sizeof(rt_string *) * m->cap);\n        m->vals = realloc(m->vals, sizeof(int64_t) * m->cap);\n        if (m->keys == NULL || m->vals == NULL) { abort(); }\n    }\n    m->keys[m->len] = key;\n    m->vals[m->len] = val;\n    m->len++;\n}\n\nstatic int xn_map_s_i_has(const xn_map_s_i *m, rt_string * key) { return xn_map_s_i_find(m, key) >= 0; }\n\nstatic int64_t xn_map_s_i_get_or(const xn_map_s_i *m, rt_string * key, int64_t dflt) {\n    long i = xn_map_s_i_find(m, key);\n    return i >= 0 ? m->vals[i] : dflt;\n}\n\nstatic int xn_map_s_i_remove(xn_map_s_i *m, rt_string * key) {\n    long i = xn_map_s_i_find(m, key);\n    if (i < 0) { return 0; }\n    for (size_t j = (size_t)i; j + 1 < m->len; j++) {\n        m->keys[j] = m->keys[j + 1];\n        m->vals[j] = m->vals[j + 1];\n    }\n    m->len--;\n    return 1;\n}\n\nstatic void xn_map_s_i_clear(xn_map_s_i *m) {\n    m->len = 0;\n}\n\nstatic int xn_map_s_i_cmp_key(rt_string * a, rt_string * b) {\n    size_t n = a->len < b->len ? a->len : b->len;\n    int c = memcmp(a->bytes, b->bytes, n);\n    if (c != 0) { return c; }\n    return (a->len > b->len) - (a->len < b->len);\n}\n\nstatic void xn_map_s_i_sort_idx(const xn_map_s_i *m, size_t *idx) {\n    for (size_t i = 1; i < m->len; i++) {\n        size_t x = idx[i];\n        size_t j = i;\n        while (j > 0 && xn_map_s_i_cmp_key(m->keys[idx[j - 1]], m->keys[x]) > 0) {\n            idx[j] = idx[j - 1];\n            j--;\n        }\n        idx[j] = x;\n    }\n}\n\nstatic xn_arr_s *xn_map_s_i_keys(const xn_map_s_i *m) {\n    xn_arr_s *out = xn_arr_s_new(m->len);\n    if (m->len == 0) { return out; }\n    size_t *idx = malloc(sizeof(size_t) * m->len);\n    if (idx == NULL) { abort(); }\n    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }\n    xn_map_s_i_sort_idx(m, idx);\n    for (size_t i = 0; i < m->len; i++) { xn_arr_s_push(out, m->keys[idx[i]]); }\n    free(idx);\n    return out;\n}\n\nstatic xn_arr_i *xn_map_s_i_values(const xn_map_s_i *m) {\n    xn_arr_i *out = xn_arr_i_new(m->len);\n    if (m->len == 0) { return out; }\n    size_t *idx = malloc(sizeof(size_t) * m->len);\n    if (idx == NULL) { abort(); }\n    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }\n    xn_map_s_i_sort_idx(m, idx);\n    for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(out, m->vals[idx[i]]); }\n    free(idx);\n    return out;\n}\n\nstatic xn_opt_i xn_map_s_i_get(const xn_map_s_i *m, rt_string * key) {\n    xn_opt_i r;\n    long i = xn_map_s_i_find(m, key);\n    if (i < 0) { r.has = 0; r.v = 0; return r; }\n    r.has = 1;\n    r.v = m->vals[i];\n    return r;\n}\n\n\nstatic xn_arr_s *xn_str_split(rt_string *s, rt_string *sep) {\n    xn_arr_s *out = xn_arr_s_new(4);\n    if (sep->len == 0) {\n        rt_string *t = rt_string_new(s->bytes, s->len);\n        xn_arr_s_push(out, t);\n        rt_release(t);\n        return out;\n    }\n    size_t start = 0, i = 0;\n    while (i + sep->len <= s->len) {\n        if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) {\n            rt_string *t = rt_string_new(s->bytes + start, i - start);\n            xn_arr_s_push(out, t);\n            rt_release(t);\n            i += sep->len;\n            start = i;\n        } else {\n            i++;\n        }\n    }\n    rt_string *last = rt_string_new(s->bytes + start, s->len - start);\n    xn_arr_s_push(out, last);\n    rt_release(last);\n    return out;\n}\nstatic int64_t xn_sum(xn_arr_i * xn_p_xs);\nstatic int64_t xn_main();\n\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_TARR = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\ntypedef struct {\n    int64_t f0;\n    int64_t f1;\n} xn_tup_int64_t_int64_t;\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; xn_tup_int64_t_int64_t *data; } xn_arr_t_int64_t_int64_t;\n\n\nstatic void xn_arr_t_int64_t_int64_t_deinit(void *p) {\n    xn_arr_t_int64_t_int64_t *a = (xn_arr_t_int64_t_int64_t *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_t_int64_t_int64_t = { \"List\", sizeof(xn_arr_t_int64_t_int64_t), xn_arr_t_int64_t_int64_t_deinit, NULL };\n\nstatic xn_arr_t_int64_t_int64_t *xn_arr_t_int64_t_int64_t_new(size_t cap) {\n    xn_arr_t_int64_t_int64_t *a = (xn_arr_t_int64_t_int64_t *)xn_gc_new(&RT_TYPE_xn_arr_t_int64_t_int64_t);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_t_int64_t_int64_t) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(xn_tup_int64_t_int64_t) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_t_int64_t_int64_t_push(xn_arr_t_int64_t_int64_t *a, xn_tup_int64_t_int64_t v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(xn_tup_int64_t_int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic xn_tup_int64_t_int64_t xn_arr_t_int64_t_int64_t_get(const xn_arr_t_int64_t_int64_t *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_t_int64_t_int64_t_set(xn_arr_t_int64_t_int64_t *a, int64_t i, xn_tup_int64_t_int64_t v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic xn_tup_int64_t_int64_t xn_arr_t_int64_t_int64_t_remove(xn_arr_t_int64_t_int64_t *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    xn_tup_int64_t_int64_t old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_t_int64_t_int64_t_insert(xn_arr_t_int64_t_int64_t *a, int64_t i, xn_tup_int64_t_int64_t v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(xn_tup_int64_t_int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_t_int64_t_int64_t_clear(xn_arr_t_int64_t_int64_t *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_t_int64_t_int64_t_join(xn_arr_t_int64_t_int64_t *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, rt_string_from_c(\"\"));\n    }\n    return res;\n}\n\nstatic int64_t xn_main();\n\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_ANY = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\n\nstatic int64_t xn_main();\n\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";

class N {
    Bool sc = false
    String raw = ""
    String nm = ""
    List<String> fn = []
    List<N> fv = []
    List<N> el = []
}

class AP {
    String s = ""
    Int p = 0
    Int n = 0
    AP(String t) { self.s = t; self.n = t.length() }
    String ch(Int i) {
        if i < 0 { return "" }
        if i >= self.n { return "" }
        return self.s.substring(i, 1)
    }
    void ws() { while self.p < self.n && self.ch(self.p) == " " { self.p = self.p + 1 } }
    String bare() {
        Int st = self.p
        while self.p < self.n {
            String c = self.ch(self.p)
            if c == " " || c == "(" || c == ")" { break }
            self.p = self.p + 1
        }
        return self.s.substring(st, self.p - st)
    }
    N val() {
        self.ws()
        if self.ch(self.p) == "(" {
            self.p = self.p + 1
            String name = self.bare()
            N r = new N()
            if name == "slice" {
                r.nm = "slice"
                while true {
                    self.ws()
                    if self.ch(self.p) == ")" { self.p = self.p + 1; break }
                    r.el.push(self.val())
                }
                return r
            }
            r.nm = name
            while true {
                self.ws()
                if self.ch(self.p) == ")" { self.p = self.p + 1; break }
                self.p = self.p + 1
                String f = self.bare()
                N v = self.val()
                self.ws()
                self.p = self.p + 1
                r.fn.push(f)
                r.fv.push(v)
            }
            return r
        }
        N r = new N()
        r.sc = true
        if self.ch(self.p) == "\"" {
            Int st = self.p
            self.p = self.p + 1
            while true {
                String c = self.ch(self.p)
                if c == "\\" { self.p = self.p + 2; continue }
                if c == "\"" { self.p = self.p + 1; break }
                self.p = self.p + 1
            }
            r.raw = self.s.substring(st, self.p - st)
            return r
        }
        Int st = self.p
        while self.p < self.n {
            String c = self.ch(self.p)
            if c == " " || c == "(" || c == ")" { break }
            self.p = self.p + 1
        }
        r.raw = self.s.substring(st, self.p - st)
        return r
    }
}

static N fld(N n, String name) {
    Int i = 0
    while i < n.fn.length() {
        if n.fn.get(i) == name { return n.fv.get(i) }
        i = i + 1
    }
    return new N()
}
static String txt(N n) { return n.raw }
static Int dec(String s) {
    Int v = 0
    Int i = 0
    while i < s.length() {
        String c = s.substring(i, 1)
        if c == "0" { v = v * 10 + 0 }
        else if c == "1" { v = v * 10 + 1 }
        else if c == "2" { v = v * 10 + 2 }
        else if c == "3" { v = v * 10 + 3 }
        else if c == "4" { v = v * 10 + 4 }
        else if c == "5" { v = v * 10 + 5 }
        else if c == "6" { v = v * 10 + 6 }
        else if c == "7" { v = v * 10 + 7 }
        else if c == "8" { v = v * 10 + 8 }
        else if c == "9" { v = v * 10 + 9 }
        i = i + 1
    }
    return v
}
static String unq(String raw) {
    if raw.length() < 2 { return raw }
    String s = raw.substring(1, raw.length() - 2)
    String b = ""
    Int i = 0
    while i < s.length() {
        String c = s.substring(i, 1)
        if c == "\\" {
            i = i + 1
            if i < s.length() {
                String e = s.substring(i, 1)
                if e == "n" { b = b + "\n" }
                else if e == "t" { b = b + "\t" }
                else if e == "r" { b = b + "\r" }
                else { b = b + e }
            }
        } else { b = b + c }
        i = i + 1
    }
    return b
}
static String q(String s) {
    String b = "\""
    Int i = 0
    while i < s.length() {
        String c = s.substring(i, 1)
        if c == "\"" { b = b + "\\\"" }
        else if c == "\\" { b = b + "\\\\" }
        else if c == "\n" { b = b + "\\n" }
        else if c == "\t" { b = b + "\\t" }
        else if c == "\r" { b = b + "\\r" }
        else { b = b + c }
        i = i + 1
    }
    return b + "\""
}
static Int lineOf(N n) { return dec(txt(fld(fld(n, "P"), "Line"))) }
static String sp(Int n) {
    String b = ""
    Int i = 0
    while i < n { b = b + " "; i = i + 1 }
    return b
}
static String paramDecl(String cty, String name) { return cty + " " + name }
static String resultErrC(String et) {
    if et == "TaskError" || et == "CancelledError" { return "xrt_error_kind" }
    if et == "ErrorKind" { return "xn_Enum_ErrorKind" }
    if et == "Error" { return "xn_proto_Error" }
    return cType(et)
}
static String resultValC(String vt) {
    if vt == "void" { return "int64_t" }
    return cType(vt)
}
static String errMember(String cty) {
    if cty.length() > 0 && cty.substring(cty.length() - 1, 1) == "*" { return cty + "err" }
    return cty + " err"
}
static String decl(String cty, String name) {
    if cty.length() > 0 && cty.substring(cty.length() - 1, 1) == "*" { return cty + name }
    return cty + " " + name
}
static String lastQual(N t) {
    N ql = fld(t, "Qual")
    if ql.el.length() == 0 { return "" }
    return unq(txt(ql.el.get(ql.el.length() - 1)))
}
static String substKey(String k) {
    Int i = 0
    while i < SUB_FROM.length() { if SUB_FROM.get(i) == k && i < SUB_TO.length() { return SUB_TO.get(i) }; i = i + 1 }
    if k.length() > 1 && k.substring(k.length() - 1, 1) == "?" {
        String b = k.substring(0, k.length() - 1)
        i = 0
        while i < SUB_FROM.length() { if SUB_FROM.get(i) == b && i < SUB_TO.length() { return SUB_TO.get(i) + "?" }; i = i + 1 }
    }
    return k
}
static String typeKey(N t) {
    String rr = typeKey0(t)
    return substKey(rr)
}
List<String> FN_NAMES = []
List<String> FN_SIGS = []
List<String> C_ARR = []
List<String> C_SET = []
List<String> C_MAPK = []
List<String> C_MAPV = []
List<String> C_DECL = []
Bool USES_ARR_S = false
Bool USES_MAP_S_I = false
Bool USES_MAP_S_S = false

static Bool hasStr(List<String> xs, String v) {
    Int i = 0
    while i < xs.length() { if xs.get(i) == v { return true }; i = i + 1 }
    return false
}
static void needArr(String ec) {
    if !hasStr(C_ARR, ec) { C_ARR.push(ec) }
    if ec == "rt_string *" { USES_ARR_S = true }
}
static void needSet(String ec) {
    needArr(ec)
    if !hasStr(C_SET, ec) { C_SET.push(ec) }
}
static void needMap(String kc, String vc) {
    String key = kc + "|" + vc
    Int i = 0
    while i < C_MAPK.length() { if C_MAPK.get(i) + "|" + C_MAPV.get(i) == key { return }; i = i + 1 }
    C_MAPK.push(kc)
    C_MAPV.push(vc)
    if kc == "rt_string *" && vc == "int64_t" { USES_MAP_S_I = true }
    if kc == "rt_string *" && vc == "rt_string *" { USES_MAP_S_S = true }
}

static Bool asciiAlnum(String c) {
    return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".indexOf(c) >= 0
}
static String sanitizeCName(String s) {
    String b = ""
    Int i = 0
    while i < s.length() {
        String c = s.substring(i, 1)
        if asciiAlnum(c) { b = b + c } else { b = b + "_" }
        i = i + 1
    }
    return b
}
static String funcTypeC(N ft) {
    String ret = cType(typeKey(fld(ft, "Ret")))
    N ps = fld(ft, "Params")
    String pj = ""
    String pn = ""
    Int i = 0
    while i < ps.el.length() {
        if i > 0 { pj = pj + ", "; pn = pn + "_" }
        String pc = cType(typeKey(ps.el.get(i)))
        pj = pj + pc
        pn = pn + pc
        i = i + 1
    }
    String nm = "xn_fn_" + sanitizeCName(ret + "_" + pn)
    Bool seen = false
    Int k = 0
    while k < FN_NAMES.length() { if FN_NAMES.get(k) == nm { seen = true }; k = k + 1 }
    if !seen { FN_NAMES.push(nm); FN_SIGS.push(ret + "|" + pj) }
    return nm
}
static Int asciiOrd(String c) {
    return " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~".indexOf(c)
}
static Bool strLess(String a, String b) {
    Int i = 0
    Int n = a.length()
    if b.length() < n { n = b.length() }
    while i < n {
        Int oa = asciiOrd(a.substring(i, 1))
        Int ob = asciiOrd(b.substring(i, 1))
        if oa < ob { return true }
        if oa > ob { return false }
        i = i + 1
    }
    return a.length() < b.length()
}
static String fnTypedefs() {
    List<String> ns = []
    Int i = 0
    while i < FN_NAMES.length() { ns.push(FN_NAMES.get(i)); i = i + 1 }
    Int a = 1
    while a < ns.length() {
        String x = ns.get(a)
        Int b = a
        while b > 0 && strLess(x, ns.get(b - 1)) { ns.set(b, ns.get(b - 1)); b = b - 1 }
        ns.set(b, x)
        a = a + 1
    }
    String fx = ""
    i = 0
    while i < ns.length() {
        String nm = ns.get(i)
        Int sigi = 0
        while sigi < FN_NAMES.length() { if FN_NAMES.get(sigi) == nm { String sg = FN_SIGS.get(sigi); Int bar = sg.indexOf("|"); String ret = sg.substring(0, bar); String prm = sg.substring(bar + 1, sg.length() - bar - 1); fx = fx + "typedef " + ret + " (*" + nm + ")(" + prm + ");\n"; sigi = FN_NAMES.length() } else { sigi = sigi + 1 } }
        i = i + 1
    }
    if fx != "" { fx = fx + "\n" }
    return fx
}
static String typeKey0(N t) {
    if t.nm == "FuncTypeRef" { return funcTypeC(t) }
    if t.nm == "NamedType" {
        String last = lastQual(t)
        N args = fld(t, "Args")
        if last == "List" && args.el.length() > 0 { return "List<" + typeKey(args.el.get(0)) + ">" }
        Int gi = 0
        Bool isGenCls = false
        while gi < GEN_CLS_NAMES.length() { if GEN_CLS_NAMES.get(gi) == last { isGenCls = true }; gi = gi + 1 }
        if isGenCls && args.el.length() > 0 {
            String ak = typeKey(args.el.get(0))
            return last + "_" + mangle(ak)
        }
        if last == "Result" && args.el.length() == 2 {
            return "Result<" + typeKey(args.el.get(0)) + ", " + typeKey(args.el.get(1)) + ">"
        }
        if last == "Map" && args.el.length() == 2 {
            return "Map<" + typeKey(args.el.get(0)) + ", " + typeKey(args.el.get(1)) + ">"
        }
        if last == "Set" && args.el.length() == 1 {
            return "Set<" + typeKey(args.el.get(0)) + ">"
        }
        return last
    }
    if t.nm == "TupleTypeRef" {
        N els = fld(t, "Elems")
        String b = "Tuple<"
        Int i = 0
        while i < els.el.length() { if i > 0 { b = b + ", " }; b = b + typeKey(els.el.get(i)); i = i + 1 }
        return b + ">"
    }
    if t.nm == "SuffixedType" {
        N sfx = fld(t, "Suffixes")
        if sfx.el.length() == 1 && unq(txt(sfx.el.get(0))) == "?" { return typeKey(fld(t, "Base")) + "?" }
        if sfx.el.length() == 1 && unq(txt(sfx.el.get(0))) == "[]" { return typeKey(fld(t, "Base")) + "[]" }
        return typeKey(fld(t, "Base"))
    }
    return "Int"
}
static String cNamePart(String k) {
    if k == "Int" { return "Int" }
    if k == "Int32" { return "Int32" }
    if k == "Int64" { return "Int64" }
    if k == "UInt" { return "UInt" }
    if k == "UInt32" { return "UInt32" }
    if k == "UInt64" { return "UInt64" }
    if k == "ErrorKind" { return "ErrorKind" }
    if k == "Bool" { return "Bool" }
    if k == "Char" { return "Char" }
    if k == "Float" { return "Float" }
    if k == "Double" { return "Double" }
    if k == "String" { return "String" }
    if k == "Error" { return "Error" }
    if k == "Bytes" { return "Bytes" }
    if k == "List<Int>" { return "List_Int" }
    if k.indexOf("List<") == 0 { return "List" }
    if isClass(k) { return k }
    if k == "" || k == "T" || k == "V" { return "X" }
    return k
}
static Int topComma(String k) {
    Int d = 0
    Int i = 0
    while i < k.length() {
        String c = k.substring(i, 1)
        if c == "<" { d = d + 1 }
        if c == ">" { d = d - 1 }
        if c == "," && d == 1 { return i }
        i = i + 1
    }
    return -1
}
static Int lastClose(String k) {
    Int d = 0
    Int i = 0
    while i < k.length() {
        String c = k.substring(i, 1)
        if c == "<" { d = d + 1 }
        if c == ">" { d = d - 1; if d == 0 { return i } }
        i = i + 1
    }
    return -1
}
static String resultName(String k) {
    Int l = k.indexOf("<")
    Int c = topComma(k)
    Int r = lastClose(k)
    if l < 0 || c < 0 || r < 0 { return "xn_Result_X_X" }
    String a = k.substring(l + 1, c - l - 1).trim()
    String b = k.substring(c + 1, r - c - 1).trim()
    return "xn_Result_" + cNamePart(a) + "_" + cNamePart(b)
}
static String resultVal(String k) {
    Int l = k.indexOf("<")
    Int c = topComma(k)
    if l < 0 || c < 0 { return "Int" }
    return k.substring(l + 1, c - l - 1).trim()
}
static String resultErr(String k) {
    Int c = topComma(k)
    Int r = lastClose(k)
    if c < 0 || r < 0 { return "String" }
    return k.substring(c + 1, r - c - 1).trim()
}


static String cType(String k) {
    if k == "void" { return "void" }
    if k.indexOf("xn_fn_") == 0 { return k }
    if k.length() > 6 && k.indexOf("List<") == 0 { needArr(cType(k.substring(5, k.length() - 6))) }
    if k.length() > 5 && k.indexOf("Set<") == 0 { needSet(cType(k.substring(4, k.length() - 5))) }
    if k.length() > 5 && k.indexOf("Map<") == 0 {
        Int mc = topComma(k)
        if mc >= 0 {
            String kc = cType(k.substring(4, mc - 4).trim())
            String vc = cType(k.substring(mc + 1, k.length() - mc - 2).trim())
            needMap(kc, vc)
        }
    }
    if k.length() > 2 && k.substring(k.length() - 2, 2) == "[]" { needArr(cType(k.substring(0, k.length() - 2))) }
    if isTupleKey(k) { return tupleCName(tupleInnerKeys(k)) }
    if k == "Int" { return "int64_t" }
    if k == "Int8" { return "int8_t" }
    if k == "Int16" { return "int16_t" }
    if k == "Int32" { return "int32_t" }
    if k == "Int64" { return "int64_t" }
    if k == "UInt" || k == "UInt64" { return "uint64_t" }
    if k == "UInt8" { return "uint8_t" }
    if k == "UInt16" { return "uint16_t" }
    if k == "UInt32" { return "uint32_t" }
    if k == "ErrorKind" { return "xn_Enum_ErrorKind" }
    if k == "Bool" { return "int" }
    if k == "Context" || k == "xrt_context" { return "xrt_context *" }
    if k == "Char" { return "xn_char" }
    if k == "Float" || k == "Double" { return "double" }
    if k == "Any" { return "xn_Any *" }
    if k == "Int?" { return "xn_opt_i" }
    if k == "Bool?" { return "xn_opt_b" }
    if k == "String?" { return "xn_opt_s" }
    if k == "String" { return "rt_string *" }
    if k == "Bytes" { return "xrt_bytes_obj *" }
    if k == "List<UInt16>" || k == "UInt16[]" { return "xn_arr_u16 *" }
    if isObjArr(k) { return classArrName(k) + " *" }
    if isTupList(k) { return arrTupName(k) + " *" }
    if k == "Set<Int>" { return "xn_set_i *" }
    if k == "Map<String, Int>" { return "xn_map_s_i *" }
    if k.indexOf("Result<") == 0 { return resultName(k) }
    if isProtoType(stripQ(k)) { return "xn_proto_" + stripQ(k) }
    if baseCls(k) != "" { return "xn_Cls_" + baseCls(k) + " *" }
    if isEnumType(k) { if isDataEnum(k) { return "xn_Enum_" + k + " *" }; return "xn_Enum_" + k }
    if isProtoType(k) { return "xn_proto_" + k }
    if isClass(k) { return "xn_Cls_" + k + " *" }
    if isStruct(k) { return "xn_Struct_" + k }
    if k.length() > 5 && k.indexOf("Map<") == 0 {
        Int mc2 = topComma(k)
        if mc2 >= 0 {
            String kc2 = cType(k.substring(4, mc2 - 4).trim())
            String vc2 = cType(k.substring(mc2 + 1, k.length() - mc2 - 2).trim())
            return mapNameC(kc2, vc2) + " *"
        }
    }
    if k.length() > 5 && k.indexOf("Set<") == 0 { return setNameC(cType(k.substring(4, k.length() - 5))) + " *" }
    if k.length() > 6 && k.indexOf("List<") == 0 { return arrNameC(cType(k.substring(5, k.length() - 6))) + " *" }
    if k.length() > 2 && k.substring(k.length() - 2, 2) == "[]" { return arrNameC(cType(k.substring(0, k.length() - 2))) + " *" }
    return "int64_t"
}
static Bool isResult(String k) { return k.indexOf("Result<") == 0 }
static Bool isArr(String k) {
    if k == "List<Int>" || k == "Int[]" { return true }
    if k.indexOf("List<") == 0 && !isU16List(k) && !isObjArr(k) && !isTupList(k) { return true }
    return false
}
static Bool isU16List(String k) { return k == "List<UInt16>" || k == "UInt16[]" }
static Bool isMap(String k) { return k.indexOf("Map<") == 0 }
static Bool isSet(String k) { return k.indexOf("Set<") == 0 }
static String stripQ(String k) {
    if k.length() > 0 && k.substring(k.length() - 1, 1) == "?" { return k.substring(0, k.length() - 1) }
    return k
}
static String baseCls(String k) {
    String b = stripQ(k)
    if isClass(b) { return b }
    return ""
}
static Bool isObjArr(String k) {
    if k.indexOf("List<") != 0 { return false }
    Int l = k.indexOf("<")
    if l < 0 { return false }
    String e = k.substring(l + 1, k.length() - l - 2).trim()
    return isClass(e)
}
static String objArrElem(String k) {
    Int l = k.indexOf("<")
    if l < 0 { return "Int" }
    return k.substring(l + 1, k.length() - l - 2).trim()
}
static String classArrName(String k) { return "xn_arr_o_" + objArrElem(k) }
static Bool fieldIsGC(String k) {
    String b = stripQ(k)
    if b == "Any" || b == "Object" || b == "Result" { return true }
    if b == "String" || b == "Text" || b == "Bytes" || b == "StringBuilder" { return true }
    if b.indexOf("List<") == 0 || b.indexOf("Set<") == 0 || b.indexOf("Map<") == 0 { return true }
    if b.indexOf("Result<") == 0 { return true }
    if isProtoType(b) { return true }
    if b.indexOf("Tuple<") == 0 {
        Int l = b.indexOf("<")
        String es = b.substring(l + 1, b.length() - l - 1)
        if es.indexOf("String") >= 0 || es.indexOf("Any") >= 0 { return true }
    }
    return false
}
static String fieldKind(String k) {
    if fieldIsGC(k) { return "gc" }
    if baseCls(k) != "" { return "ref" }
    if isDataEnum(stripQ(k)) { return "ref" }
    return "value"
}
static Bool clsHasGC(String cn) {
    String cur = cn
    while cur != "" {
        Int i = 0
        while i < FLD_OWNER.length() {
            if FLD_OWNER.get(i) == cur && fieldIsGC(FLD_TYPE.get(i)) { return true }
            i = i + 1
        }
        cur = baseOf(cur)
    }
    return false
}
static Bool clsReaches(String cur, String target, List<String> seen) {
    String base = baseOf(cur)
    if base != "" {
        if base == target { return true }
        Bool vb = false
        Int jb = 0
        while jb < seen.length() { if seen.get(jb) == base { vb = true }; jb = jb + 1 }
        if !vb { List<String> sb = []; Int kb = 0; while kb < seen.length() { sb.push(seen.get(kb)); kb = kb + 1 }; sb.push(base); if clsReaches(base, target, sb) { return true } }
    }
    Int i = 0
    while i < FLD_OWNER.length() {
        if FLD_OWNER.get(i) == cur {
            String b = baseCls(FLD_TYPE.get(i))
            if b != "" {
                if b == target { return true }
                Bool vis = false
                Int j = 0
                while j < seen.length() { if seen.get(j) == b { vis = true }; j = j + 1 }
                if !vis {
                    List<String> s2 = []
                    Int k = 0
                    while k < seen.length() { s2.push(seen.get(k)); k = k + 1 }
                    s2.push(b)
                    if clsReaches(b, target, s2) { return true }
                }
            }
        }
        i = i + 1
    }
    return false
}
static Bool clsHasCycle(String cn) {
    List<String> s = []
    s.push(cn)
    return clsReaches(cn, cn, s)
}
static String classPolicy(String cn) {
    if clsHasGC(cn) { return "gc" }
    if clsHasCycle(cn) { return "gc" }
    return "arc"
}
static Bool classStackOK(String cn) {
    if classPolicy(cn) != "arc" { return false }
    if hasDeinitDeep(cn) || hasProto(cn) || isGenInstCls(cn) { return false }
    String cur = cn
    while cur != "" {
        if hasDeinit(cur) || hasProto(cur) { return false }
        Int i = 0
        while i < FLD_OWNER.length() {
            if FLD_OWNER.get(i) == cur && fieldKind(FLD_TYPE.get(i)) != "value" { return false }
            i = i + 1
        }
        cur = baseOf(cur)
    }
    return true
}
static List<String> CLS_NAMES = []
static List<String> PRIMARY_NAMES = []
static List<String> SINGLE_NAMES = []
static List<String> FACTORY_NAMES = []
static List<String> FACTORY_TARGET = []
static List<N> FACTORY_DECLS = []
static List<String> EXT_TARGET = []
static List<String> EXT_NAME = []
static List<String> EXT_CNAME = []
static List<N> EXT_DECLS = []
static List<N> SINGLE_DECLS = []
static List<N> GEN_FN_DECLS = []
static List<String> INST_FN = []
static List<String> INST_NAME = []
static List<String> INST_ARGS = []
static List<String> INST_KEYS = []
static List<String> SUB_FROM = []
static List<String> SUB_TO = []
static String FN_SUFFIX = ""
static Bool IN_GEN = false
static List<String> GEN_CLS_NAMES = []
static List<N> GEN_CLS_DECLS = []
static List<String> GEN_INST_NAME = []
static List<String> GEN_INST_KEY = []
static List<String> GEN_INST_BASE = []
static List<String> TUPLE_KEYS = []
static List<String> TUPLE_ELEMS = []
static List<String> TUPLE_CN = []
static List<String> FFI_E_REGION = []
static List<String> FFI_E_NAME = []
static List<String> FFI_E_CNAME = []
static List<String> FFI_E_RETK = []
static List<String> FFI_E_RETN = []
static List<String> FFI_E_ERRP = []
static List<Int> FFI_E_ERRRET = []
static List<Int> FFI_E_COMP = []
static List<String> FFI_E_PARAMS = []
static List<String> FFI_RULE_REGION = []
static List<Int> FFI_RULE_CODE = []
static List<String> FFI_RULE_KIND = []
static String FFI_FIXED_HEAD = "/* 绑定层支撑代码（由 .xfb 注册表生成；只包含 xrt.h，S7 §6.1 / INV-FFI-7） */\n/* S7 §6.2：绑定层可访问弱表；应用层包含 xrt.h 时不定义此宏。 */\n#define XRT_BINDINGS_LAYER 1\n#include \"xrt.h\"\n#include <stdint.h>\n#include <stdlib.h>\n#include <string.h>\n\n/* 包装 ABI：返回 0 成功；非 0 为原生错误码（未知码→Internal，S7 §7.2） */\n/* S6-09 net Async 运行时原语（E5 rt_std_net.c） */\nvoid *xdkc_socket_connect_async(xrt_context *ctx, const char *host, size_t hlen, int32_t port, int32_t *code);\nint64_t xdkc_socket_send_async(xrt_context *ctx, void *sock, const void *buf, size_t n, int32_t *code);\nint64_t xdkc_socket_recv_async(xrt_context *ctx, void *sock, void *buf, size_t cap, int32_t *code);\nvoid *xdkc_http_request_async(xrt_context *ctx, const char *method, size_t mlen, const char *host, size_t hlen, int32_t port, const char *path, size_t plen, const void *body, size_t blen, int32_t *code);\n\n"
static String FFI_CANARY = "#define XN_FFI_CANARY 16\n\nstatic uint8_t *xn_ffi_canary_enter(const uint8_t *src, size_t n) {\n    uint8_t *buf = (uint8_t *)malloc(n + 2 * XN_FFI_CANARY);\n    if (buf == NULL) { xrt_fatal(\"FFI 编组：内存不足（S7 §9）\"); }\n    memset(buf, 0xA5, XN_FFI_CANARY);\n    memset(buf + XN_FFI_CANARY, 0, n);\n    if (src != NULL) { memcpy(buf + XN_FFI_CANARY, src, n); }\n    memset(buf + XN_FFI_CANARY + n, 0x5A, XN_FFI_CANARY);\n    return buf;\n}\n\nstatic void xn_ffi_canary_leave(uint8_t *buf, uint8_t *dst, size_t n) {\n    size_t i;\n    for (i = 0; i < XN_FFI_CANARY; i++) {\n        if (buf[i] != 0xA5 || buf[XN_FFI_CANARY + n + i] != 0x5A) {\n            xrt_fatal(\"FFI 借出缓冲区越界写（S7 §9 INV-FFI-5）\");\n        }\n    }\n    if (dst != NULL) { memcpy(dst, buf + XN_FFI_CANARY, n); }\n    free(buf);\n}\n\nstatic int xn_ffi_bool_from_native(uint8_t v) {\n    if (v > 1) { xrt_fatal(\"FFI Bool 返回值非 0/1（S7 §3.2 合同违规）\"); }\n    return (int)v;\n}\n\n"
static Bool SKIP_LINE = false
static Bool IN_PAREN = false
static Bool NO_OP_WRAP = false
static String CLS_OVERRIDE = ""
static List<String> ENUM_NAMES = []
static List<String> ENUM_ITEM_OWNER = []
static List<String> ENUM_ITEM_NAME = []
static Int ENUM_ITEM_INDEX_N = 0
static List<Int> ENUM_ITEM_INDEX = []
static List<String> DATA_ENUM_NAMES = []
static List<N> DATA_ENUM_DECLS = []
static List<String> PROTO_NAMES = []
static List<String> PROTO_OWNER = []
static List<String> PROTO_MNAME = []
static List<String> CLS_PROTO_OWNER = []
static List<String> CLS_PROTO_NAME = []
static List<String> CLS_BASE_OWNER = []
static List<String> CLS_BASE_NAME = []
static List<String> STRUCT_NAMES = []
static List<String> FLD_OWNER = []
static List<String> FLD_NAME = []
static List<String> FLD_TYPE = []
static List<String> MTH_OWNER = []
static List<String> MTH_NAME = []
static List<String> MTH_RET = []
static Bool isClass(String k) {
    Int i = 0
    while i < CLS_NAMES.length() { if CLS_NAMES.get(i) == k { return true }; i = i + 1 }
    return false
}
static Bool isStruct(String k) {
    Int i = 0
    while i < STRUCT_NAMES.length() { if STRUCT_NAMES.get(i) == k { return true }; i = i + 1 }
    return false
}
static String fieldType(String cls, String f) {
    Int i = 0
    while i < FLD_OWNER.length() {
        if FLD_OWNER.get(i) == cls && FLD_NAME.get(i) == f { return FLD_TYPE.get(i) }
        i = i + 1
    }
    return "Int"
}
static String methodRet(String cls, String m) {
    Int i = 0
    while i < MTH_OWNER.length() {
        if MTH_OWNER.get(i) == cls && MTH_NAME.get(i) == m { return MTH_RET.get(i) }
        i = i + 1
    }
    return "Int"
}
static Bool fieldExists(String cls, String f) {
    Int i = 0
    while i < FLD_OWNER.length() {
        if FLD_OWNER.get(i) == cls && FLD_NAME.get(i) == f { return true }
        i = i + 1
    }
    return false
}
static Bool isExtMethod(String cls, String mn) {
    Int i = 0
    while i < EXT_TARGET.length() {
        if EXT_TARGET.get(i) == cls && EXT_NAME.get(i) == mn { return true }
        i = i + 1
    }
    return false
}
static String extCName(String cls, String mn) {
    Int i = 0
    while i < EXT_TARGET.length() {
        if EXT_TARGET.get(i) == cls && EXT_NAME.get(i) == mn { return EXT_CNAME.get(i) }
        i = i + 1
    }
    return ""
}
static Bool isFactory(String k) {
    Int i = 0
    while i < FACTORY_NAMES.length() { if FACTORY_NAMES.get(i) == k { return true }; i = i + 1 }
    return false
}
static String factoryTarget(String k) {
    Int i = 0
    while i < FACTORY_NAMES.length() { if FACTORY_NAMES.get(i) == k { return FACTORY_TARGET.get(i) }; i = i + 1 }
    return "Int"
}
static String factoryMethodRet(String fac, String mn) {
    N d = factoryDecl(fac)
    N ms = fld(d, "Methods")
    Int i = 0
    while i < ms.el.length() {
        if unq(txt(fld(ms.el.get(i), "Name"))) == mn { return retKey(ms.el.get(i)) }
        i = i + 1
    }
    return factoryTarget(fac)
}
static N factoryDecl(String fac) {
    Int i = 0
    while i < FACTORY_NAMES.length() {
        if FACTORY_NAMES.get(i) == fac { return FACTORY_DECLS.get(i) }
        i = i + 1
    }
    return new N()
}
static Bool isSingle(String k) {
    Int i = 0
    while i < SINGLE_NAMES.length() { if SINGLE_NAMES.get(i) == k { return true }; i = i + 1 }
    return false
}
static Bool isEnumType(String k) {
    Int i = 0
    while i < ENUM_NAMES.length() { if ENUM_NAMES.get(i) == k { return true }; i = i + 1 }
    return false
}
static Bool isDataEnum(String k) {
    Int i = 0
    while i < DATA_ENUM_NAMES.length() { if DATA_ENUM_NAMES.get(i) == k { return true }; i = i + 1 }
    return false
}
static Int enumIndex(String en, String item) {
    Int i = 0
    while i < ENUM_ITEM_OWNER.length() {
        if ENUM_ITEM_OWNER.get(i) == en && ENUM_ITEM_NAME.get(i) == item { return ENUM_ITEM_INDEX.get(i) }
        i = i + 1
    }
    return 0
}
static Bool isProtoType(String k) {
    Int i = 0
    while i < PROTO_NAMES.length() { if PROTO_NAMES.get(i) == k { return true }; i = i + 1 }
    return false
}
static Int protoSlot(String pn, String mn) {
    Int n = 0
    Int i = 0
    while i < PROTO_OWNER.length() {
        if PROTO_OWNER.get(i) == pn { if PROTO_MNAME.get(i) == mn { return n }; n = n + 1 }
        i = i + 1
    }
    return 0
}
static String protoRet(String pn, String mn) {
    Int i = 0
    while i < PROTO_OWNER.length() {
        if PROTO_OWNER.get(i) == pn && PROTO_MNAME.get(i) == mn { return "Int" }
        i = i + 1
    }
    return "Int"
}
static Bool hasProto(String cls) {
    Int i = 0
    while i < CLS_PROTO_OWNER.length() {
        if CLS_PROTO_OWNER.get(i) == cls { return true }
        i = i + 1
    }
    return false
}
static Int protoSlots(String cls) {
    Int n = 0
    Int i = 0
    while i < CLS_PROTO_OWNER.length() {
        if CLS_PROTO_OWNER.get(i) == cls {
            String pn = CLS_PROTO_NAME.get(i)
            Int j = 0
            while j < PROTO_OWNER.length() {
                if PROTO_OWNER.get(j) == pn && pn != "Error" { n = n + 1 }
                j = j + 1
            }
        }
        i = i + 1
    }
    return n
}
static N classByName(String cn) {
    Int i = 0
    while i < CLS_DECLS.length() {
        if unq(txt(fld(CLS_DECLS.get(i), "Name"))) == cn { return CLS_DECLS.get(i) }
        i = i + 1
    }
    i = 0
    while i < GEN_CLS_DECLS.length() {
        if unq(txt(fld(GEN_CLS_DECLS.get(i), "Name"))) == cn { return GEN_CLS_DECLS.get(i) }
        i = i + 1
    }
    return new N()
}
static List<N> CLS_DECLS = []
static String baseOf(String cn) {
    Int i = 0
    while i < CLS_BASE_OWNER.length() {
        if CLS_BASE_OWNER.get(i) == cn { return CLS_BASE_NAME.get(i) }
        i = i + 1
    }
    return ""
}
static String fieldOwner(String cn, String fn) {
    String cur = cn
    while cur != "" {
        Int i = 0
        while i < FLD_OWNER.length() {
            if FLD_OWNER.get(i) == cur && FLD_NAME.get(i) == fn { return cur }
            i = i + 1
        }
        cur = baseOf(cur)
    }
    return ""
}
static Bool fieldPrivate(String cn, String fn) {
    N cls = classByName(cn)
    N fs = fld(cls, "Fields")
    Int i = 0
    while i < fs.el.length() {
        N f = fs.el.get(i)
        if unq(txt(fld(f, "Name"))) == fn {
            return unq(txt(fld(fld(f, "Mod"), "Vis"))) == "private"
        }
        i = i + 1
    }
    return false
}
static String fieldCName(N f) {
    String fn = unq(txt(fld(f, "Name")))
    if unq(txt(fld(fld(f, "Mod"), "Vis"))) == "private" { return "_" + fn }
    return fn
}
static String methodOwner(String cn, String mn) {
    String cur = cn
    while cur != "" {
        Int i = 0
        while i < MTH_OWNER.length() {
            if MTH_OWNER.get(i) == cur && MTH_NAME.get(i) == mn { return cur }
            i = i + 1
        }
        cur = baseOf(cur)
    }
    return ""
}
static Bool hasRefFieldsDeep(String cn) {
    String cur = cn
    while cur != "" {
        if hasRefFields(cur) { return true }
        cur = baseOf(cur)
    }
    return false
}
static Bool hasDeinitDeep(String cn) {
    String cur = cn
    while cur != "" {
        if hasDeinit(cur) { return true }
        cur = baseOf(cur)
    }
    return false
}
static Bool hasDeinit(String cls) {
    Int i = 0
    while i < MTH_OWNER.length() {
        if MTH_OWNER.get(i) == cls && MTH_NAME.get(i) == "deinit" { return true }
        i = i + 1
    }
    return false
}
static Bool hasRefFields(String cls) {
    Int i = 0
    while i < FLD_OWNER.length() {
        if FLD_OWNER.get(i) == cls && FLD_TYPE.get(i) == "String" { return true }
        i = i + 1
    }
    return false
}
static String setElem(String k) {
    Int l = k.indexOf("<"); Int r = k.indexOf(">")
    if l < 0 || r < 0 { return "Int" }
    return k.substring(l + 1, r - l - 1).trim()
}
static String mapVal(String k) {
    Int c = k.indexOf(","); Int r = k.indexOf(">")
    if c < 0 || r < 0 { return "Int" }
    return k.substring(c + 1, r - c - 1).trim()
}
static String mapKey(String k) {
    Int l = k.indexOf("<"); Int c = k.indexOf(",")
    if l < 0 || c < 0 { return "String" }
    return k.substring(l + 1, c - l - 1).trim()
}
static String arrElem(String k) {
    if k.length() > 2 && k.substring(k.length() - 2, 2) == "[]" { return k.substring(0, k.length() - 2) }
    Int l = k.indexOf("<"); Int r = k.indexOf(">")
    if l < 0 || r < 0 { return "Int" }
    return k.substring(l + 1, r - l - 1).trim()
}

class DF {
    String text = ""
    String temp = ""
    Bool err = false
    List<String> lines = []
    String name = ""
}

class SC {
    List<String> names = []
    List<String> types = []
    List<DF> defers = []
    String curFn = ""
    List<String> params = []
    List<String> paramTypes = []
    List<String> escaped = []
    List<String> fnNames = []
    List<String> fnRets = []
    List<String> resultTypes = []
    String ret = ""
    String rootMark = ""
    List<String> rootPrelude = []
    Int sid = -1
    Int parentId = -1
    Bool hasResult = false
    Bool isCtor = false
    List<String> own = []
    List<String> blockHeld = []
    Bool returned = false
    Bool rootDeclared = false
    String kind = ""
    String selfName = "self"
    String curClass = ""
    Bool selfPtr = false
    Bool staticMeth = false
    String retKind = "Int"
    Bool directRet = false
    String deferredRet = ""
    void def(String n, String t) {
        self.names.push(n)
        self.types.push(t)
        if !inNames(self.own, n) { self.own.push(n) }
    }
    String typeOf(String n) {
        Int i = 0
        while i < self.params.length() {
            if self.params.get(i) == n && i < self.paramTypes.length() { return self.paramTypes.get(i) }
            i = i + 1
        }
        i = 0
        while i < self.names.length() {
            if self.names.get(i) == n { return self.types.get(i) }
            i = i + 1
        }
        return "Int"
    }
    String nameOf(String n) {
        Int i = 0
        while i < self.params.length() {
            if self.params.get(i) == n { return "xn_p_" + n }
            i = i + 1
        }
        return n
    }
    void defFn(String n, String r) { self.fnNames.push(n); self.fnRets.push(r) }
    String retOf(String n) {
        Int i = 0
        while i < self.fnNames.length() {
            if self.fnNames.get(i) == n { return self.fnRets.get(i) }
            i = i + 1
        }
        return "Int"
    }
    void useResult(String k) {
        if !isResult(k) { return }
        Int i = 0
        while i < self.resultTypes.length() {
            if self.resultTypes.get(i) == k { return }
            i = i + 1
        }
        self.resultTypes.push(k)
    }
}

List<SC> SC_REG = []

static SC parentOf(SC s) {
    if s.parentId < 0 { return s }
    return SC_REG.get(s.parentId)
}

class EM {
    List<String> ls = []
    Int tmp = 0
    Int ind = 0
    Bool usesList = false
    Bool hasMap = false
    Bool hasSet = false
    Bool hasGetOr = false
    Bool usesTArr = false
    Bool usesAny = false
    Bool usesObjArr = false
    String objArrKey = ""
    Bool terminated = false
    String path = ""
    void add(String s) { self.ls.push(sp(self.ind) + s) }
    void addAt(Int n, String s) { self.ls.push(sp(n) + s) }
    void raw(String s) { self.ls.push(s) }
    String nt() { self.tmp = self.tmp + 1; return "xn_t" + str(self.tmp) }
}

static String exprType(N x, SC sc) {
    if x.nm == "IntLitExpr" { return "Int" }
    if x.nm == "BoolLit" { return "Bool" }
    if x.nm == "CharLitExpr" { return "Char" }
    if x.nm == "FloatLitExpr" { return "Double" }
    if x.nm == "StrLitExpr" { return "String" }
    if x.nm == "NullLit" { return "Null" }
    if x.nm == "Paren" { return exprType(fld(x, "X"), sc) }
    if x.nm == "New" { return typeKey(fld(x, "Type")) }
    if x.nm == "Tuple" {
        N els = fld(x, "Elems")
        String b = "Tuple<"
        Int i = 0
        while i < els.el.length() { if i > 0 { b = b + ", " }; b = b + exprType(els.el.get(i), sc); i = i + 1 }
        return b + ">"
    }
    if x.nm == "IdentExpr" { return sc.typeOf(unq(txt(fld(x, "Name")))) }
    if x.nm == "TupleMember" {
        String bt = exprType(fld(x, "X"), sc)
        String es = tupleInnerKeys(bt)
        Int idx = dec(txt(fld(x, "Index")))
        Int c = 0; Int st = 0; String cur = ""
        while c < es.length() { if es.substring(c,1) == "," { if idx == 0 { return cur.trim() }; idx = idx - 1; cur = "" } else { cur = cur + es.substring(c,1) }; c = c + 1 }
        return cur.trim()
    }
    if x.nm == "Member" {
        N mb = fld(x, "X")
        if mb.nm == "Member" && fld(mb, "X").nm == "IdentExpr" {
            String si0 = unq(txt(fld(fld(mb, "X"), "Name")))
            if isSingle(si0) && unq(txt(fld(mb, "Name"))) == "instance" { return fieldType(si0, unq(txt(fld(x, "Name")))) }
        }
        if mb.nm == "IdentExpr" && isSingle(unq(txt(fld(mb, "Name")))) {
            if unq(txt(fld(x, "Name"))) == "instance" { return unq(txt(fld(mb, "Name"))) }
            return fieldType(unq(txt(fld(mb, "Name"))), unq(txt(fld(x, "Name"))))
        }
        if mb.nm == "IdentExpr" && isEnumType(unq(txt(fld(mb, "Name")))) {
            String en1 = unq(txt(fld(mb, "Name")))
            if isDataEnum(en1) { if unq(txt(fld(x, "Name"))) != "instance" { return en1 } }
            return en1
        }
        String bt = exprType(mb, sc)
        String f = unq(txt(fld(x, "Name")))
        if baseCls(bt) != "" { return fieldType(fieldOwner(baseCls(bt), f), f) }
        if isClass(bt) || isStruct(bt) { return fieldType(fieldOwner(bt, f), f) }
        if isDataEnum(bt) { return fieldType(bt, f) }
        if isSingle(bt) { return fieldType(bt, f) }
        if isProtoType(bt) { return "Int" }
        return "Int"
    }
    if x.nm == "Unary" {
        String op = unq(txt(fld(x, "Op")))
        if op == "!" { return "Bool" }
        if op == "try" { return exprType(fld(x, "X"), sc) }
        return exprType(fld(x, "X"), sc)
    }
    if x.nm == "Call" {
        N callee = fld(x, "Callee")
        if callee.nm == "IdentExpr" {
            String n = unq(txt(fld(callee, "Name")))
            if isFFI(n) {
                Int fidx = ffiIdx(n)
                if ffiIsErr(fidx) { return "Result<" + FFI_E_RETN.get(fidx) + ", ErrorKind>" }
                return ffiRetType(n)
            }
            if n == "str" { return "String" }
            if n == "Ok" || n == "Err" { return "Result" }
            N ta2 = fld(x, "TypeArgs")
            if ta2.el.length() > 0 && isGenericFn(n) {
                SUB_FROM = ["T"]
                SUB_TO = [typeKey(ta2.el.get(0))]
                String rt2 = retKey(genFnDecl(n))
                SUB_FROM = []
                SUB_TO = []
                return rt2
            }
            return sc.retOf(n)
        }
        if callee.nm == "Member" {
            N mx = fld(callee, "X")
            String mn = unq(txt(fld(callee, "Name")))
            String mt = exprType(mx, sc)
            if mx.nm == "IdentExpr" && unq(txt(fld(mx, "Name"))) == "super" { return "void" }
            if mn == "isOk" || mn == "isErr" { return "Bool" }
            if mn == "value" || mn == "unwrapOr" { return resultVal(mt) }
            if mn == "error" { return resultErr(mt) }
            if mx.nm == "IdentExpr" && isFactory(unq(txt(fld(mx, "Name")))) { return factoryMethodRet(unq(txt(fld(mx, "Name"))), mn) }
            if mx.nm == "Member" && fld(mx, "X").nm == "IdentExpr" {
                String si3 = unq(txt(fld(fld(mx, "X"), "Name")))
                if isSingle(si3) && unq(txt(fld(mx, "Name"))) == "instance" { return methodRet(si3, mn) }
            }
            if isDataEnum(mt) { return methodRet(mt, mn) }
            if isClass(mt) && isExtMethod(mt, mn) {
                Int ei = 0
                while ei < EXT_TARGET.length() {
                    if EXT_TARGET.get(ei) == mt && EXT_NAME.get(ei) == mn { return "String" }
                    ei = ei + 1
                }
            }
            if isSingle(mt) { return methodRet(mt, mn) }
            if isProtoType(mt) { return protoRet(mt, mn) }
            if isClass(mt) || isStruct(mt) {
                String mow = methodOwner(mt, mn)
                if mow != "" { return methodRet(mow, mn) }
                return methodRet(mt, mn)
            }
            if mt == "Bytes" && mn == "length" { return "Int" }
            if mt == "Bytes" && mn == "get" { return "Int" }
            if mt == "Bytes" && mn == "toString" { return "String" }
            if mt == "Bytes" && mn == "slice" { return "Bytes" }
            if mn == "length" { return "Int" }
            if mn == "substring" { return "String" }
            if mn == "indexOf" || mn == "indexOfByte" { return "Int" }
            if mn == "charAt" { return "Char" }
            if mn == "get" { if isMap(mt) { return mapVal(mt) }; if isU16List(mt) { return "UInt16" }; if isObjArr(mt) { return objArrElem(mt) }; if isTupList(mt) { return tupleListElem(mt) }; return "Int" }
            if mn == "getOr" { return mapVal(mt) }
            if mn == "has" { return "Bool" }
            if mn == "add" { return "Bool" }
            if mn == "remove" { return "Int" }
        }
        return "Int"
    }
    if x.nm == "TupleMember" {
        String bt = exprType(fld(x, "X"), sc)
        String es = tupleInnerKeys(bt)
        Int idx = dec(txt(fld(x, "Index")))
        Int c = 0; Int st = 0; String cur = ""
        while c < es.length() { if es.substring(c,1) == "," { if idx == 0 { return cur.trim() }; idx = idx - 1; cur = "" } else { cur = cur + es.substring(c,1) }; c = c + 1 }
        return cur.trim()
    }
    if x.nm == "Member" {
        N mb = fld(x, "X")
        if mb.nm == "Member" && fld(mb, "X").nm == "IdentExpr" {
            String si1 = unq(txt(fld(fld(mb, "X"), "Name")))
            if isSingle(si1) && unq(txt(fld(mb, "Name"))) == "instance" { return "xn_single_" + si1 + "->" + unq(txt(fld(x, "Name"))) }
        }
        if mb.nm == "IdentExpr" && isSingle(unq(txt(fld(mb, "Name")))) && unq(txt(fld(x, "Name"))) == "instance" {
            return "xn_single_" + unq(txt(fld(mb, "Name")))
        }
        if mb.nm == "IdentExpr" && isEnumType(unq(txt(fld(mb, "Name")))) {
            String en0 = unq(txt(fld(mb, "Name")))
            if isDataEnum(en0) { return "xn_enum_" + en0 + "_" + unq(txt(fld(x, "Name"))) }
            return str(enumIndex(en0, unq(txt(fld(x, "Name")))))
        }
        String bt = exprType(mb, sc)
        String f = unq(txt(fld(x, "Name")))
        if isClass(bt) || isStruct(bt) || isSingle(bt) { return fieldType((isSingle(bt) ? bt : fieldOwner(bt, f)), f) }
        return "Int"
    }
    if x.nm == "Index" {
        String bt = exprType(fld(x, "X"), sc)
        if isMap(bt) { return mapVal(bt) }
        return "Int"
    }
    if x.nm == "Binary" {
        String op = unq(txt(fld(x, "Op")))
        if op == "is" { return "Bool" }
        if op == "as" || op == "as?" {
            N ta0 = fld(x, "R")
            String tt0 = typeKey(fld(ta0, "Type"))
            return tt0
        }
        if op == "<" || op == ">" || op == "<=" || op == ">=" || op == "==" || op == "!=" || op == "===" || op == "!==" || op == "&&" || op == "||" { return "Bool" }
        if op == "+" && (exprType(fld(x, "L"), sc) == "String" || exprType(fld(x, "R"), sc) == "String") { return "String" }
        if exprType(fld(x, "L"), sc) == "Double" || exprType(fld(x, "R"), sc) == "Double" { return "Double" }
        return "Int"
    }
    return "Int"
}
static String strHelper(N a, EM e, SC sc) {
    String t = exprType(a, sc)
    String v = expr(a, e, sc)
    if t == "Bool" { return "xn_str_bool((" + v + "))" }
    if t == "Char" {
        if a.nm == "Member" || a.nm == "CharLitExpr" { return "xn_str_char((int32_t)(" + v + "))" }
        return "xn_str_int(" + v + ")"
    }
    if t == "Double" || t == "Float" { return "xn_str_double(" + v + ")" }
    return "xn_str_int(" + v + ")"
}

static void rootStr(EM e, SC sc, String t) {
    if false { e.raw(""); }
}

static String argExpr(N a, EM e, SC sc) {
    if exprType(a, sc) == "String" {
        String at = emitStr(a, e, sc)
        return at
    }
    if a.nm == "Call" {
        N c0 = fld(a, "Callee")
        if c0.nm == "Member" && unq(txt(fld(c0, "Name"))) == "get" {
            N mx0 = fld(c0, "X")
            String mt0 = exprType(mx0, sc)
            N as0 = fld(a, "Args")
            if isObjArr(mt0) && as0.el.length() > 0 {
                return classArrName(mt0) + "_get(" + expr(mx0, e, sc) + ", " + expr(as0.el.get(0), e, sc) + ")"
            }
            if isTupList(mt0) && as0.el.length() > 0 {
                return arrTupName(mt0) + "_get(" + expr(mx0, e, sc) + ", " + expr(as0.el.get(0), e, sc) + ")"
            }
        }
    }
    return expr(a, e, sc)
}

static String expr(N x, EM e, SC sc) {
    if x.nm == "IntLitExpr" {
        String it = unq(txt(fld(x, "Text")))
        if it.indexOf("0x") == 0 || it.indexOf("0X") == 0 {
            Int hv = 0
            Int hi = 2
            while hi < it.length() { hv = hv * 16 + jsonHex1(it.substring(hi, 1)); hi = hi + 1 }
            return str(hv)
        }
        return it
    }
    if x.nm == "NullLit" { return "0" }
    if x.nm == "BoolLit" { if txt(fld(x, "V")) == "true" { return "1" }; return "0" }
    if x.nm == "CharLitExpr" { return txt(fld(x, "Rune")) }
    if x.nm == "FloatLitExpr" { return unq(txt(fld(x, "Text"))) }
    if x.nm == "Paren" {
        Bool op0 = IN_PAREN
        IN_PAREN = true
        String pv0 = expr(fld(x, "X"), e, sc)
        IN_PAREN = op0
        return pv0
    }
    if x.nm == "New" {
        String ccls = typeKey(fld(x, "Type"))
        N nargs = fld(x, "Args")
        String b = "xn_Cls_" + ccls + "_new("
        Int ai = 0
        while ai < nargs.el.length() {
            if ai > 0 { b = b + ", " }
            N av = nargs.el.get(ai)
            if exprType(av, sc) == "String" { b = b + emitStr(av, e, sc) } else { b = b + expr(av, e, sc) }
            ai = ai + 1
        }
        return b + ")"
    }
    if x.nm == "Tuple" {
        N els = fld(x, "Elems")
        String ek = "Tuple<"
        Int ei = 0
        while ei < els.el.length() { if ei > 0 { ek = ek + ", " }; ek = ek + exprType(els.el.get(ei), sc); ei = ei + 1 }
        ek = ek + ">"
        String b = "(" + cType(ek) + "){"
        ei = 0
        while ei < els.el.length() {
            if ei > 0 { b = b + ", " }
            String ev = expr(els.el.get(ei), e, sc)
            b = b + ".f" + str(ei) + " = " + ev
            ei = ei + 1
        }
        return b + "}"
    }
    if x.nm == "IdentExpr" {
        String idn = unq(txt(fld(x, "Name")))
        if idn == "self" { return sc.selfName }
        if sc.curClass != "" && (isClass(sc.curClass) || isStruct(sc.curClass)) {
            if fieldOwner(sc.curClass, idn) != "" { return sc.selfName + "->" + idn }
            if idn.length() > 1 && idn.substring(0, 1) == "_" {
                String bn = idn.substring(1, idn.length() - 1)
                if fieldOwner(sc.curClass, bn) != "" { return sc.selfName + "->" + idn }
            }
        }
        return sc.nameOf(idn)
    }
    if x.nm == "Unary" {
        String op = unq(txt(fld(x, "Op")))
        if op == "try" { return expr(fld(x, "X"), e, sc) }
        return "(" + op + "(" + expr(fld(x, "X"), e, sc) + "))"
    }
    if x.nm == "Binary" {
        String op = unq(txt(fld(x, "Op")))
        if op == "is" || op == "as" || op == "as?" {
            N ta = fld(x, "R")
            String tyn = typeKey(fld(ta, "Type"))
            String lv = expr(fld(x, "L"), e, sc)
            if op == "is" { return "xn_any_is(" + lv + ", \"" + tyn + "\")" }
            if op == "as" && tyn == "Int" {
                N asl = fld(x, "L")
                if asl.nm == "IdentExpr" || asl.nm == "Member" { return "((int64_t)(" + lv + "))" }
                return lv
            }
            if tyn == "Any" {
                e.usesAny = true
                String lt = exprType(fld(x, "L"), sc)
                if lt == "String" {
                    String sv = emitStr(fld(x, "L"), e, sc)
                    String bt = e.nt()
                    e.add("xn_Any *" + bt + " = xn_box_str(" + sv + ");")
                    e.add("rt_release(" + sv + ");")
                    return bt
                }
                if lt == "Bool" { return "xn_box_bool((int)(" + lv + "))" }
                if isClass(lt) { return "xn_box_obj(" + lv + ")" }
                return "xn_box_int((int64_t)(" + lv + "))"
            }
            e.usesAny = true
            String rt = typeKey(fld(ta, "Type"))
            String ns = "1"
            if op == "as" { ns = "0" }
            if rt == "String" { return "xn_any_get_str(" + lv + ", \"" + rt + "\", " + ns + ")" }
            if rt == "Bool" { return "((int)xn_any_get_int(" + lv + ", \"" + rt + "\", " + ns + "))" }
            return "xn_any_get_int(" + lv + ", \"" + rt + "\", " + ns + ")"
        }
        if ((op == "==" || op == "!=" || op == "===" || op == "!==") && (exprType(fld(x, "L"), sc) == "String" || exprType(fld(x, "R"), sc) == "String")) {
            String sl = emitStr(fld(x, "L"), e, sc)
            String sr = emitStr(fld(x, "R"), e, sc)
            String se = "xn_str_eq(" + sl + ", " + sr + ")"
            if op == "==" || op == "===" { return se }
            return "(!(" + se + "))"
        }
        if (op == "==" || op == "!=") && fld(x, "R").nm == "NullLit" {
            String lt0 = exprType(fld(x, "L"), sc)
            if lt0.length() > 0 && lt0.substring(lt0.length() - 1, 1) == "?" {
                String lb = expr(fld(x, "L"), e, sc)
                if op == "!=" { return "((" + lb + ").has)" }
                return "(!((" + lb + ").has))"
            }
        }
        if (op == "==" || op == "!=" || op == "===" || op == "!==") && isTupleKey(exprType(fld(x, "L"), sc)) {
            String lt = exprType(fld(x, "L"), sc)
            String ltmp = e.nt()
            e.add(cType(lt) + " " + ltmp + " = " + expr(fld(x, "L"), e, sc) + ";")
            String rtmp = e.nt()
            e.add(cType(lt) + " " + rtmp + " = " + expr(fld(x, "R"), e, sc) + ";")
            String eq = ""
            Int ei = 0
            while ei < 2 {
                String ek = tupleElemAt(lt, ei)
                String term = ""
                if ek == "String" && (op == "==" || op == "!=") {
                    term = "xn_str_eq((" + ltmp + ").f" + str(ei) + ", (" + rtmp + ").f" + str(ei) + ")"
                } else {
                    term = "((" + ltmp + ").f" + str(ei) + " == (" + rtmp + ").f" + str(ei) + ")"
                }
                if eq == "" { eq = term } else { eq = eq + " && " + term }
                ei = ei + 1
            }
            String eq2 = "(" + eq + ")"
            if op == "!=" { return "(!(" + eq2 + "))" }
            if op == "!==" { return "(!(" + eq2 + "))" }
            return eq2
        }
        if op == "&&" || op == "||" {
            N lb = fld(x, "L")
            N rb = fld(x, "R")
            String lv = expr(lb, e, sc)
            String rv = expr(rb, e, sc)
            if !IN_PAREN && !NO_OP_WRAP && lb.nm == "Binary" && (unq(txt(fld(lb, "Op"))) != "&&" && unq(txt(fld(lb, "Op"))) != "||") { lv = "(" + lv + ")" }
            if !NO_OP_WRAP && lb.nm == "Binary" { String lop = unq(txt(fld(lb, "Op"))); if (lop == "&&" || lop == "||") && lop != op { lv = "(" + lv + ")" } }
            if !NO_OP_WRAP && lb.nm == "Paren" { N lp2 = fld(lb, "X"); if lp2.nm == "Binary" { String lop = unq(txt(fld(lp2, "Op"))); if (lop == "&&" || lop == "||") && lop != op { lv = "(" + lv + ")" } } }
            if !IN_PAREN && !NO_OP_WRAP && (lb.nm == "Unary" || lb.nm == "Call") { lv = "(" + lv + ")" }
            if !IN_PAREN && !NO_OP_WRAP && rb.nm == "Binary" && (unq(txt(fld(rb, "Op"))) != "&&" && unq(txt(fld(rb, "Op"))) != "||") { rv = "(" + rv + ")" }
            if !NO_OP_WRAP && rb.nm == "Binary" { String rop = unq(txt(fld(rb, "Op"))); if (rop == "&&" || rop == "||") && rop != op { rv = "(" + rv + ")" } }
            if !NO_OP_WRAP && rb.nm == "Paren" { N rp2 = fld(rb, "X"); if rp2.nm == "Binary" { String rop = unq(txt(fld(rp2, "Op"))); if (rop == "&&" || rop == "||") && rop != op { rv = "(" + rv + ")" } } }
            if !IN_PAREN && !NO_OP_WRAP && (rb.nm == "Unary" || rb.nm == "Call") { rv = "(" + rv + ")" }

            return "(" + lv + " " + op + " " + rv + ")"
        }
        if op == "/" { return "xn_div_i64((int64_t)(" + expr(fld(x, "L"), e, sc) + "), (int64_t)(" + expr(fld(x, "R"), e, sc) + "))" }
        if op == "%" { return "xn_mod_i64((int64_t)(" + expr(fld(x, "L"), e, sc) + "), (int64_t)(" + expr(fld(x, "R"), e, sc) + "))" }
        return "(" + expr(fld(x, "L"), e, sc) + " " + op + " " + expr(fld(x, "R"), e, sc) + ")"
    }
    if x.nm == "TupleMember" {
        return "(" + expr(fld(x, "X"), e, sc) + ").f" + txt(fld(x, "Index"))
    }
    if x.nm == "Member" {
        N mb = fld(x, "X")
        if mb.nm == "Member" && fld(mb, "X").nm == "IdentExpr" {
            String si1 = unq(txt(fld(fld(mb, "X"), "Name")))
            if isSingle(si1) && unq(txt(fld(mb, "Name"))) == "instance" { return "xn_single_" + si1 + "->" + unq(txt(fld(x, "Name"))) }
        }
        if mb.nm == "IdentExpr" && isSingle(unq(txt(fld(mb, "Name")))) && unq(txt(fld(x, "Name"))) == "instance" {
            return "xn_single_" + unq(txt(fld(mb, "Name")))
        }
        if mb.nm == "IdentExpr" && isEnumType(unq(txt(fld(mb, "Name")))) {
            String en0 = unq(txt(fld(mb, "Name")))
            if isDataEnum(en0) { return "xn_enum_" + en0 + "_" + unq(txt(fld(x, "Name"))) }
            return str(enumIndex(en0, unq(txt(fld(x, "Name")))))
        }
        String bt = exprType(mb, sc)
        String f = unq(txt(fld(x, "Name")))
        String fc = f
        if baseCls(bt) != "" { String own = fieldOwner(baseCls(bt), f); if own != "" && fieldPrivate(own, f) { fc = "_" + f } }
        else if isClass(bt) { if fieldPrivate(bt, f) { fc = "_" + f } }
        if baseCls(bt) != "" { return expr(fld(x, "X"), e, sc) + "->" + fc }
        if isClass(bt) || isSingle(bt) || isDataEnum(bt) { return expr(fld(x, "X"), e, sc) + "->" + fc }
        if isStruct(bt) {
            String bx = expr(fld(x, "X"), e, sc)
            if bx == "self" && sc.selfPtr { return "self->" + f }
            return bx + "." + f
        }
        return expr(fld(x, "X"), e, sc) + "." + f
    }
    if x.nm == "Index" {
        return "xn_arr_i_get(" + expr(fld(x, "X"), e, sc) + ", " + expr(fld(x, "Idx"), e, sc) + ")"
    }
    if x.nm == "Call" {
        N callee = fld(x, "Callee")
        if callee.nm == "IdentExpr" {
            String n = unq(txt(fld(callee, "Name")))
            if n == "str" {
                N args = fld(x, "Args")
                if args.el.length() > 0 { return strHelper(args.el.get(0), e, sc) }
            }
        }
        if callee.nm == "Member" {
            N mx = fld(callee, "X")
            String mn = unq(txt(fld(callee, "Name")))
            N args = fld(x, "Args")
            if mx.nm == "IdentExpr" && isFactory(unq(txt(fld(mx, "Name")))) {
                String facn = unq(txt(fld(mx, "Name")))
                String callf = "xn_Factory_" + facn + "_" + mn + "("
                Int af = 0
                while af < args.el.length() { if af > 0 { callf = callf + ", " }; callf = callf + argExpr(args.el.get(af), e, sc); af = af + 1 }
                return callf + ")"
            }
            if mx.nm == "Member" && fld(mx, "X").nm == "IdentExpr" {
                String si2 = unq(txt(fld(fld(mx, "X"), "Name")))
                if isSingle(si2) && unq(txt(fld(mx, "Name"))) == "instance" {
                    String call0 = "xn_Single_" + si2 + "_" + mn + "(xn_single_" + si2
                    Int ai0 = 0
                    while ai0 < args.el.length() { call0 = call0 + ", " + expr(args.el.get(ai0), e, sc); ai0 = ai0 + 1 }
                    return call0 + ")"
                }
            }
            if mx.nm == "IdentExpr" && unq(txt(fld(mx, "Name"))) == "super" {
                String bcn2 = baseOf(sc.curClass)
                String bb2 = "xn_Cls_" + bcn2 + "_" + mn + "(((" + cType(bcn2) + ")" + sc.selfName + ")"
                Int ai2 = 0
                while ai2 < args.el.length() { bb2 = bb2 + ", " + expr(args.el.get(ai2), e, sc); ai2 = ai2 + 1 }
                return bb2 + ")"
            }
            String cbt = exprType(mx, sc)
            if isSingle(cbt) {
                String b0 = "xn_single_" + cbt
                String call = "xn_Single_" + cbt + "_" + mn + "(" + b0
                Int ai = 0
                while ai < args.el.length() { call = call + ", " + argExpr(args.el.get(ai), e, sc); ai = ai + 1 }
                return call + ")"
            }
            if isProtoType(cbt) {
                String b0 = expr(mx, e, sc)
                Int slot = protoSlot(cbt, mn)
                String rc = cType(protoRet(cbt, mn))
                return "((" + rc + " (*)(void *))((xn_vt_obj *)(" + b0 + "))->__vtable[" + str(slot) + "])(" + b0 + ")"
            }
            if isDataEnum(cbt) {
                String b0 = expr(mx, e, sc)
                String call = "xn_Enum_" + cbt + "_" + mn + "(" + b0
                Int ai = 0
                while ai < args.el.length() { call = call + ", " + argExpr(args.el.get(ai), e, sc); ai = ai + 1 }
                return call + ")"
            }
            if isClass(cbt) || isStruct(cbt) {
                String b0 = expr(mx, e, sc)
                String owner = methodOwner(cbt, mn)
                if owner == "" { owner = cbt }
                if isStruct(cbt) { b0 = "(&" + b0 + ")" }
                else if owner != cbt { b0 = "(xn_Cls_" + owner + " *)" + b0 }
                String call = ""
                if isClass(cbt) && isExtMethod(cbt, mn) { call = extCName(cbt, mn) + "(" + b0 }
                else { call = "xn_" + (isClass(cbt) ? "Cls_" : "Struct_") + owner + "_" + mn + "(" + b0 }
                Int ai = 0
                while ai < args.el.length() {
                    call = call + ", " + argExpr(args.el.get(ai), e, sc)
                    ai = ai + 1
                }
                return call + ")"
            }
            String base = "(" + expr(mx, e, sc) + ")"
            if mn == "isOk" { return base + ".ok" }
            if mn == "isErr" { return "(!(" + expr(mx, e, sc) + ").ok)" }
            if mn == "value" { return base + ".v" }
            if mn == "unwrapOr" {
                String d = "0"
                if args.el.length() > 0 { d = expr(args.el.get(0), e, sc) }
                return "(" + base + ".ok ? " + base + ".v : (" + d + "))"
            }
            String mt2 = exprType(mx, sc)
            if mt2 == "Bytes" && mn == "length" { return "((int64_t)xrt_bytes_len(" + expr(mx, e, sc) + "))" }
            if mt2 == "Bytes" && mn == "get" {
                String ix = "0"
                if args.el.length() > 0 { ix = expr(args.el.get(0), e, sc) }
                return "((int64_t)xrt_bytes_get(" + expr(mx, e, sc) + ", (size_t)(" + ix + ")))"
            }
            if mt2 == "Bytes" && mn == "slice" {
                String a0 = "0"
                String a1 = "0"
                if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                if args.el.length() > 1 { a1 = expr(args.el.get(1), e, sc) }
                return "xrt_bytes_slice(" + expr(mx, e, sc) + ", (size_t)(" + a0 + "), (size_t)(" + a1 + "))"
            }
            if mt2 == "String" && mn == "length" {
                String rb = expr(mx, e, sc)
                if mx.nm == "Member" { rb = emitStr(mx, e, sc) }
                return "xn_str_length(" + rb + ")"
            }
            if mt2 == "String" && mn == "substring" {
                String a0 = "0"
                String a1 = "0"
                if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                if args.el.length() > 1 { a1 = expr(args.el.get(1), e, sc) }
                String rb = expr(mx, e, sc)
                if mx.nm == "Member" { rb = emitStr(mx, e, sc) }
                return "xn_str_substr(" + rb + ", " + a0 + ", " + a1 + ")"
            }
            if mt2 == "String" && mn == "toLower" { return "xn_str_lower(" + expr(mx, e, sc) + ")" }
            if mt2 == "String" && mn == "toUpper" { return "xn_str_upper(" + expr(mx, e, sc) + ")" }
            if mt2 == "String" && mn == "trim" { return "xn_str_trim(" + expr(mx, e, sc) + ")" }
            if mt2 == "String" && mn == "replace" {
                String rb0 = expr(mx, e, sc)
                String a00 = "0"
                String a01 = "0"
                if args.el.length() > 0 { a00 = emitStr(args.el.get(0), e, sc) }
                if args.el.length() > 1 { a01 = emitStr(args.el.get(1), e, sc) }
                return "xn_str_replace(" + rb0 + ", " + a00 + ", " + a01 + ")"
            }
            if mt2 == "String" && mn == "startsWith" {
                String a00 = "0"
                if args.el.length() > 0 { a00 = emitStr(args.el.get(0), e, sc) }
                return "xn_str_startswith(" + expr(mx, e, sc) + ", " + a00 + ")"
            }
            if mt2 == "String" && mn == "endsWith" {
                String a00 = "0"
                if args.el.length() > 0 { a00 = emitStr(args.el.get(0), e, sc) }
                return "xn_str_endswith(" + expr(mx, e, sc) + ", " + a00 + ")"
            }
            if mt2 == "String" && mn == "split" {
                String a00 = "0"
                if args.el.length() > 0 { a00 = emitStr(args.el.get(0), e, sc) }
                return "xn_str_split(" + expr(mx, e, sc) + ", " + a00 + ")"
            }
            if mt2 == "String" && mn == "charAt" {
                String a00 = "0"
                if args.el.length() > 0 { a00 = expr(args.el.get(0), e, sc) }
                return "xn_str_substr(" + expr(mx, e, sc) + ", " + a00 + ", 1)"
            }
            if mt2 == "String" && (mn == "indexOf" || mn == "indexOfByte") {
                String rb = expr(mx, e, sc)
                if mx.nm == "StrLitExpr" || mx.nm == "Member" { rb = emitStr(mx, e, sc) }
                String a0 = "0"
                if args.el.length() > 0 { a0 = emitStr(args.el.get(0), e, sc) }
                return "xn_str_indexof(" + rb + ", " + a0 + ")"
            }
            if mn == "length" {
                if isSet(mt2) { return "((int64_t)" + expr(mx, e, sc) + "->a->len)" }
                return "((int64_t)" + expr(mx, e, sc) + "->len)"
            }
            if mn == "get" {
                String xb = expr(mx, e, sc)
                String a0 = "0"
                if args.el.length() > 0 {
                    if isMap(mt2) && exprType(args.el.get(0), sc) == "String" { a0 = emitStr(args.el.get(0), e, sc) }
                    else { a0 = expr(args.el.get(0), e, sc) }
                }
                if isMap(mt2) { return "(" + mapNameC(cType(mapKey(mt2)), cType(mapVal(mt2))) + "_get(" + xb + ", " + a0 + ").v)" }
                if isU16List(mt2) { return "xn_arr_u16_get(" + xb + ", " + a0 + ")" }
                if isObjArr(mt2) {
                    String an = classArrName(mt2)
                    String t = e.nt()
                    e.add(cType(objArrElem(mt2)) + " " + t + " = " + an + "_get(" + xb + ", " + a0 + ");")
                    return t
                }
                if isTupList(mt2) { return arrTupName(mt2) + "_get(" + xb + ", " + a0 + ")" }
                return arrNameC(cType(arrElem(mt2))) + "_get(" + xb + ", " + a0 + ")"
            }
            if mn == "getOr" {
                e.hasGetOr = true
                String xb = expr(mx, e, sc)
                String a0 = "0"
                String a1 = "0"
                if args.el.length() > 0 { a0 = emitStr(args.el.get(0), e, sc) }
                if args.el.length() > 1 { a1 = expr(args.el.get(1), e, sc) }
                return mapNameC(cType(mapKey(mt2)), cType(mapVal(mt2))) + "_get_or(" + xb + ", " + a0 + ", " + a1 + ")"
            }
            if mn == "has" {
                String xb = expr(mx, e, sc)
                String a0 = "0"
                if args.el.length() > 0 {
                    if isMap(mt2) && exprType(args.el.get(0), sc) == "String" { a0 = emitStr(args.el.get(0), e, sc) }
                    else { a0 = expr(args.el.get(0), e, sc) }
                }
                if isSet(mt2) { return setNameC(cType(setElem(mt2))) + "_has(" + xb + ", " + a0 + ")" }
                return mapNameC(cType(mapKey(mt2)), cType(mapVal(mt2))) + "_has(" + xb + ", " + a0 + ")"
            }
            if mn == "add" {
                String xb = expr(mx, e, sc)
                String a0 = "0"
                if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                return setNameC(cType(setElem(mt2))) + "_add(" + xb + ", " + a0 + ")"
            }
            if mn == "remove" {
                String xb = expr(mx, e, sc)
                String a0 = "0"
                if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                return arrNameC(cType(arrElem(mt2))) + "_remove(" + xb + ", " + a0 + ")"
            }
            if mn == "insert" {
                String xb = expr(mx, e, sc)
                String a0 = "0"
                String a1 = "0"
                if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                if args.el.length() > 1 { a1 = expr(args.el.get(1), e, sc) }
                return arrNameC(cType(arrElem(mt2))) + "_insert(" + xb + ", " + a0 + ", " + a1 + ")"
            }
        }
        // 普通函数调用
        N cl = fld(x, "Callee")
        String cal = expr(cl, e, sc)
        N args = fld(x, "Args")
        if cl.nm == "IdentExpr" {
            String cn = unq(txt(fld(cl, "Name")))
            if isFFI(cn) { return ffiCallExpr(cn, x, e, sc) }
            if cn == "nowMono" { return "xdkc_now_mono_ms()" }
            if cn == "nowWall" { return "xdkc_now_wall_ms()" }
            if cn == "env" {
                N envArgs = fld(x, "Args")
                if envArgs.el.length() > 0 { return "xn_env_lookup(" + emitStr(envArgs.el.get(0), e, sc) + ")" }
            }
            N targs0 = fld(x, "TypeArgs")
            if targs0.el.length() > 0 && isGenericFn(cn) {
                String ag = ""
                Int ti = 0
                while ti < targs0.el.length() { if ti > 0 { ag = ag + "," }; ag = ag + typeKey(targs0.el.get(ti)); ti = ti + 1 }
                String nm0 = "xn_" + cn + "_" + mangle(ag)
                String bb0 = nm0 + "("
                Int ai = 0
                while ai < args.el.length() { if ai > 0 { bb0 = bb0 + ", " }; bb0 = bb0 + argExpr(args.el.get(ai), e, sc); ai = ai + 1 }
                return bb0 + ")"
            }
            if sc.curClass != "" && methodOwner(sc.curClass, cn) != "" {
                String own = methodOwner(sc.curClass, cn)
                String cast = sc.selfName
                if own != sc.curClass { cast = "(xn_Cls_" + own + " *)" + sc.selfName }
                String bb = "xn_Cls_" + own + "_" + cn + "(" + cast
                Int ai = 0
                while ai < args.el.length() { bb = bb + ", " + argExpr(args.el.get(ai), e, sc); ai = ai + 1 }
                return bb + ")"
            }
            if cn != "str" && cn != "print" && cn != "Ok" && cn != "Err" { cal = "xn_" + cn }
        }
        String b = cal + "("
        Int i = 0
        while i < args.el.length() {
            if i > 0 { b = b + ", " }
            b = b + argExpr(args.el.get(i), e, sc)
            i = i + 1
        }
        return b + ")"
    }
    return "0"
}

static String emitStr(N x, EM e, SC sc) {
    if x.nm == "StrLitExpr" {
        N parts = fld(x, "Parts")
        String cur = ""
        Int i = 0
        while i < parts.el.length() {
            N part = parts.el.get(i)
            String text = unq(txt(fld(part, "Text")))
            N ex = fld(part, "Expr")
            if text != "" {
                String t = e.nt()
                e.add("rt_string *" + t + " = rt_string_from_c(" + q(text) + ");")
                rootStr(e, sc, t)
                if cur == "" { cur = t } else { String c = e.nt(); e.add("rt_string *" + c + " = xn_concat(" + cur + ", " + t + ");"); rootStr(e, sc, c); cur = c }
            }
            if ex.nm != "" && ex.nm != "nil" {
                if isTupleKey(exprType(ex, sc)) {
                    String tk = exprType(ex, sc)
                    String tt = e.nt()
                    e.add(cType(tk) + " " + tt + " = " + expr(ex, e, sc) + ";")
                    String curT = e.nt()
                    e.add("rt_string *" + curT + " = rt_string_from_c(\"(\");")
                    rootStr(e, sc, curT)
                    Int tei = 0
                    while tei < 2 {
                        if tei > 0 {
                            String sep = e.nt()
                            e.add("rt_string *" + sep + " = xn_concat(" + curT + ", rt_string_from_c(\", \"));")
                            rootStr(e, sc, sep)
                            curT = sep
                        }
                        String ek = tupleElemAt(tk, tei)
                        String ev = ""
                        if ek == "String" {
                            ev = e.nt()
                            e.add("rt_string *" + ev + " = rt_retain((" + tt + ").f" + str(tei) + ");")
                            rootStr(e, sc, ev)
                        } else {
                            ev = e.nt()
                            e.add("rt_string *" + ev + " = xn_str_int((" + tt + ").f" + str(tei) + ");")
                            rootStr(e, sc, ev)
                        }
                        String cc = e.nt()
                        e.add("rt_string *" + cc + " = xn_concat(" + curT + ", " + ev + ");")
                        rootStr(e, sc, cc)
                        curT = cc
                        tei = tei + 1
                    }
                    String cl = e.nt()
                    e.add("rt_string *" + cl + " = xn_concat(" + curT + ", rt_string_from_c(\")\"));")
                    rootStr(e, sc, cl)
                    curT = cl
                    if cur == "" { cur = curT } else { String c2 = e.nt(); e.add("rt_string *" + c2 + " = xn_concat(" + cur + ", " + curT + ");"); rootStr(e, sc, c2); cur = c2 }
                    i = i + 1
                    continue
                }
                String t = ""
                if exprType(ex, sc) == "String" { t = emitStr(ex, e, sc) } else {
                    t = e.nt()
                    e.add("rt_string *" + t + " = " + strHelper(ex, e, sc) + ";")
                    rootStr(e, sc, t)
                }
                if cur == "" { cur = t } else { String c = e.nt(); e.add("rt_string *" + c + " = xn_concat(" + cur + ", " + t + ");"); rootStr(e, sc, c); cur = c }
            }
            i = i + 1
        }
        if cur == "" {
            String et0 = e.nt()
            e.add("rt_string *" + et0 + " = rt_string_from_c(\"\");")
            rootStr(e, sc, et0)
            return et0
        }
        return cur
    }
    if x.nm == "Binary" {
        String bop = unq(txt(fld(x, "Op")))
        if bop == "as" || bop == "as?" {
            N ta = fld(x, "R")
            String tyn = typeKey(fld(ta, "Type"))
            if tyn == "String" {
                String t = e.nt()
                e.add("rt_string *" + t + " = xn_any_get_str(" + expr(fld(x, "L"), e, sc) + ", \"" + tyn + "\", " + (bop == "as?" ? "1" : "0") + ");")
                rootStr(e, sc, t)
                return t
            }
        }
        String l = emitStr(fld(x, "L"), e, sc)
        String r = emitStr(fld(x, "R"), e, sc)
        String t = e.nt()
        e.add("rt_string *" + t + " = xn_concat(" + l + ", " + r + ");")
        rootStr(e, sc, t)
        return t
    }
    if x.nm == "TupleMember" {
        String t = e.nt()
        e.add("rt_string *" + t + " = rt_retain(" + expr(x, e, sc) + ");")
        rootStr(e, sc, t)
        return t
    }
    if x.nm == "IdentExpr" || x.nm == "Member" {
        String t = e.nt()
        e.add("rt_string *" + t + " = rt_retain(" + expr(x, e, sc) + ");")
        rootStr(e, sc, t)
        return t
    }
    if x.nm == "Call" {
        N callee = fld(x, "Callee")
        if callee.nm == "Member" {
            String mn = unq(txt(fld(callee, "Name")))
            if mn == "error" {
                N mx = fld(callee, "X")
                String t = e.nt()
                e.add("rt_string *" + t + " = xn_result_error_copy_rt(" + expr(mx, e, sc) + ".err);")
                rootStr(e, sc, t)
                return t
            }
        }
        String val0 = expr(x, e, sc)
        String t = e.nt()
        e.add("rt_string *" + t + " = " + val0 + ";")
        rootStr(e, sc, t)
        return t
    }
    String t = e.nt()
    e.add("rt_string *" + t + " = rt_string_from_c(" + q("") + ");")
    rootStr(e, sc, t)
    return t
}

static void emitPrint(N arg, EM e, SC sc) {
    String ty = exprType(arg, sc)
    if ty == "String" {
        if arg.nm == "Member" { e.add("xn_print_str(" + expr(arg, e, sc) + ");"); return }
        String t = emitStr(arg, e, sc)
        e.add("xn_print_str(" + t + ");")
        e.add("rt_release(" + t + ");")
        return
    }
    if ty == "Int?" || ty == "Bool?" || ty == "String?" {
        String base = expr(arg, e, sc)
        String inner = ""
        if ty == "Int?" { inner = "xn_print_int(" + base + ".v);" }
        else if ty == "Bool?" { inner = "xn_print_bool(" + base + ".v);" }
        else { inner = "xn_print_str(" + base + ".v);" }
        e.add("if (" + base + ".has) { " + inner + " } else { xn_print_null(); }")
        return
    }
    if isEnumType(ty) && !isDataEnum(ty) {
        String t = e.nt()
        e.add("rt_string *" + t + " = xn_enum_" + ty + "_name(" + expr(arg, e, sc) + ");")
        rootStr(e, sc, t)
        e.add("xn_print_str(" + t + ");")
        e.add("rt_release(" + t + ");")
        return
    }
    if isDataEnum(ty) {
        String t = e.nt()
        e.add("rt_string *" + t + " = xn_enum_" + ty + "_name(" + expr(arg, e, sc) + ");")
        rootStr(e, sc, t)
        e.add("xn_print_str(" + t + ");")
        e.add("rt_release(" + t + ");")
        return
    }
    if ty == "Bool" { e.add("xn_print_bool((" + expr(arg, e, sc) + "));"); return }
    if ty == "Double" || ty == "Float" { e.add("xn_print_double(" + expr(arg, e, sc) + ");"); return }
    e.add("xn_print_int((int64_t)(" + expr(arg, e, sc) + "));")
}

static String liteText(N arg) {
    if arg.nm == "StrLitExpr" {
        N parts = fld(arg, "Parts")
        if parts.el.length() > 0 { return unq(txt(fld(parts.el.get(0), "Text"))) }
    }
    return ""
}

static List<String> copyStrs(List<String> xs) {
    List<String> r = []
    Int i = 0
    while i < xs.length() { r.push(xs.get(i)); i = i + 1 }
    return r
}
static Bool isGCRootType(String t) {
    if t == "String" || t == "Bytes" || t == "Text" || t == "StringBuilder" || t == "Any" { return true }
    if t.indexOf("List<") == 0 || t.indexOf("Set<") == 0 || t.indexOf("Map<") == 0 { return true }
    if isArr(t) || isSet(t) || isMap(t) || isTupList(t) || isU16List(t) || isObjArr(t) { return true }
    if isProtoType(t) { return true }
    if isDataEnum(t) { return true }
    if isClass(t) { return classPolicy(t) == "gc" }
    return false
}
static void finishLocalRoot(SC sc, EM e, String nm, String ty) {
    if isGCRootType(ty) {
        e.raw("xn_root_add(" + nm + ");")
        if sc.curFn != "deinit" { e.add("xn_gc_safepoint();") }
    }
}

static SC newChild(SC parent, EM e) {
    if parent.sid < 0 { parent.sid = SC_REG.length(); SC_REG.push(parent) }
    SC s = new SC()
    s.parentId = parent.sid
    s.sid = SC_REG.length()
    SC_REG.push(s)
    s.curFn = parent.curFn
    s.retKind = parent.retKind
    s.selfName = parent.selfName
    s.curClass = parent.curClass
    s.selfPtr = parent.selfPtr
    s.staticMeth = parent.staticMeth
    s.hasResult = parent.hasResult
    s.isCtor = parent.isCtor
    s.params = parent.params
    s.paramTypes = parent.paramTypes
    s.fnNames = parent.fnNames
    s.fnRets = parent.fnRets
    s.resultTypes = parent.resultTypes
    s.escaped = parent.escaped
    s.names = copyStrs(parent.names)
    s.types = copyStrs(parent.types)
    s.defers = []
    s.ret = parent.ret
    s.directRet = parent.directRet
    s.deferredRet = parent.deferredRet
    s.own = []
    s.blockHeld = []
    s.rootPrelude = []
    s.returned = false
    s.rootDeclared = false
    s.kind = ""
    s.rootMark = e.nt()
    return s
}

static void addDefer(SC s, List<String> lines, Bool err) {
    DF d = new DF()
    d.lines = lines
    d.err = err
    s.defers.push(d)
}

static void addRelease(SC s, String code) { addDefer(s, [code], false) }

static void addNamedRelease(SC s, String name, String code) {
    DF d = new DF()
    d.lines = [code]
    d.err = false
    d.name = name
    s.defers.push(d)
}

static void emitDeferItem(DF d, EM e, Int braceInd, Int lineInd, Bool guarded) {
    if guarded { e.addAt(braceInd, "if (!xn_ret.ok) {") }
    else { e.addAt(braceInd, "{") }
    Int i = 0
    while i < d.lines.length() {
        e.addAt(lineInd, d.lines.get(i))
        i = i + 1
    }
    e.addAt(braceInd, "}")
}

static void emitCleanup(SC s, EM e, Int braceBase, Int lineBase, Bool condErr) {
    SC sc = s
    Bool stop = false
    while !stop {
        Int i = sc.defers.length() - 1
        while i >= 0 {
            DF d = sc.defers.get(i)
            if d.err {
                if s.hasResult && condErr { emitDeferItem(d, e, braceBase, lineBase, true) }
            } else {
                emitDeferItem(d, e, braceBase, lineBase, false)
            }
            i = i - 1
        }
        if sc.parentId >= 0 { sc = parentOf(sc) } else { stop = true }
    }
}

static void emitReturnClose(SC sc, EM e, String expr) {
    emitCleanup(sc, e, e.ind + 4, e.ind, true)
    sc.returned = true
    e.raw("")
    if expr == "" { e.add("return;") } else { e.add("return " + expr + ";") }
    if e.ind > 0 { e.raw("") }
}

static List<String> rootRestoresOf(SC s, String kind) {
    List<String> rv = []
    SC sc = s
    Bool stop = false
    while !stop {
        if (sc.rootMark != "") && sc.rootDeclared { rv.push("xn_root_restore(" + sc.rootMark + ");") }
        if kind == "continue" {
            if sc.kind == "loop" { stop = true }
        } else {
            if sc.kind != "" { stop = true }
        }
        if !stop {
            if sc.parentId >= 0 { sc = parentOf(sc) } else { stop = true }
        }
    }
    return rv
}

static Bool gcDeclLine(String t) {
    return t.indexOf("rt_string *") == 0 || t.indexOf("xrt_bytes_obj *") == 0 || t.indexOf("xrt_text *") == 0 || t.indexOf("xrt_sb *") == 0 || t.indexOf("xn_arr_") == 0 || t.indexOf("xn_set_") == 0 || t.indexOf("xn_map_") == 0 || t.indexOf("xn_Cls_") == 0
}
static String declNameOf(String t) {
    Int eq = t.indexOf(" = ")
    if eq < 0 { return "" }
    String lhs = t.substring(0, eq)
    List<String> fs = lhs.split(" ")
    if fs.length() == 0 { return "" }
    String nm = fs.get(fs.length() - 1)
    if nm.length() > 0 && nm.substring(nm.length() - 1, 1) == ";" { nm = nm.substring(0, nm.length() - 1) }
    while nm.length() > 0 && nm.substring(0, 1) == "*" { nm = nm.substring(1, nm.length() - 1) }
    return nm
}

static void rootTempDecls(SC sc, EM e, Int start, Int ind) {
    List<String> res = []
    Int pendAt = -1
    String pendNm = ""
    Int pendLead = 0
    Int i = start
    while i < e.ls.length() {
        String ln = e.ls.get(i)
        if i == pendAt {
            res.push(sp(pendLead) + "xn_root_add(" + pendNm + ");")
            pendAt = -1
            pendNm = ""
        }
        res.push(ln)
        String t = ln.trim()
        Bool skip = t.indexOf("xn_root_add(") >= 0 || t.indexOf("xn_root_hold(") >= 0
        if !skip && t.indexOf(" = ") >= 0 && gcDeclLine(t) {
            String nm = declNameOf(t)
            Int lead = 0
            while lead < ln.length() && ln.substring(lead, 1) == " " { lead = lead + 1 }
            Int rawIdx = -1
            Int j = i + 1
            while j < e.ls.length() && j <= i + 4 {
                if e.ls.get(j) == "xn_root_add(" + nm + ");" { rawIdx = j }
                j = j + 1
            }
            if nm != "" && nm.indexOf("(") < 0 {
                if rawIdx < 0 { res.push(sp(ind) + "xn_root_add(" + nm + ");") }
                else {
                    Int at = rawIdx + 1
                    if ind == 0 && nm.indexOf("xn_t") != 0 {
                        while at < e.ls.length() && e.ls.get(at).trim().indexOf("xn_root_add(" + nm + ");") == 0 { at = at + 1 }
                    }
                    pendAt = at
                    pendNm = nm
                    if ind > 0 || nm.indexOf("xn_t") == 0 { pendLead = ind } else { pendLead = lead }
                }
            }
        }
        i = i + 1
    }
    if i == pendAt && pendNm != "" { res.push(sp(pendLead) + "xn_root_add(" + pendNm + ");") }
    while e.ls.length() > start { e.ls.remove(e.ls.length() - 1) }
    i = 0
    while i < res.length() { e.ls.push(res.get(i)); i = i + 1 }
}

static void emitStmt(N st, EM e, SC sc, Bool early) {
    Int stStart = e.ls.length()
    emitStmtInner(st, e, sc, early)
    if st.nm == "ReturnStmt" { rootTempDecls(sc, e, stStart, e.ind) }
    rootTempDecls(sc, e, stStart, e.ind)
}

static void emitStmtInner(N st, EM e, SC sc, Bool early) {
    Bool lineStmt = st.nm == "DeferStmt" || st.nm == "ReturnStmt" || st.nm == "LocalDeclStmt" || st.nm == "AssignStmt" || st.nm == "ExprStmt" || st.nm == "IfStmt" || st.nm == "WhileStmt" || st.nm == "ForStmt" || st.nm == "SwitchStmt" || st.nm == "BreakStmt" || st.nm == "ContinueStmt" || st.nm == "ThrowStmt"
    Bool isSuperStmt = false
    if st.nm == "ExprStmt" {
        N sx0 = fld(st, "X")
        if sx0.nm == "Call" {
            N sc0 = fld(sx0, "Callee")
            if sc0.nm == "IdentExpr" && unq(txt(fld(sc0, "Name"))) == "super" { isSuperStmt = true }
        }
    }
    if SKIP_LINE { SKIP_LINE = false }
    else if lineStmt && !isSuperStmt { e.add("#line " + str(lineOf(st)) + " \"" + e.path + "\"") }
    if st.nm == "DeferStmt" {
        Bool err = txt(fld(st, "Errdefer")) == "true"
        N inner = fld(st, "Stmt")
        N b = fld(st, "Block")
        EM de = new EM()
        de.tmp = e.tmp
        de.path = e.path
        de.ind = 0
        if b.nm == "Block" {
            N stmts = fld(b, "Stmts")
            Int j = 0
            while j < stmts.el.length() {
                SKIP_LINE = true
                emitStmt(stmts.el.get(j), de, sc, false)
                j = j + 1
            }
        } else {
            SKIP_LINE = true
            emitStmt(inner, de, sc, false)
        }
        e.tmp = de.tmp
        List<String> dl = []
        Int j2 = 0
        while j2 < de.ls.length() { dl.push("        " + de.ls.get(j2)); j2 = j2 + 1 }
        addDefer(sc, dl, err)
        return
    }
    if st.nm == "BreakStmt" || st.nm == "ContinueStmt" {
        String kd = "break"
        if st.nm == "ContinueStmt" { kd = "continue" }
        List<String> rs = rootRestoresOf(sc, kd)
        Int ri = 0
        while ri < rs.length() { e.add(rs.get(ri)); ri = ri + 1 }
        if st.nm == "BreakStmt" { e.add("break;") } else { e.add("continue;") }
        e.terminated = false
        return
    }
    if st.nm == "ThrowStmt" {
        N v = fld(st, "Value")
        String t = emitStr(v, e, sc)
        e.add("xn_throw(" + t + ");")
        return
    }
    if st.nm == "LocalDeclStmt" {
        String ty = typeKey(fld(st, "Type"))
        String nm = unq(txt(fld(st, "Name")))
        N init = fld(st, "Init")
        sc.def(nm, ty)
        sc.useResult(ty)
        String regTy0 = cType(ty)
        if init.nm == "Unary" && unq(txt(fld(init, "Op"))) == "try" {
            String rk = exprType(fld(init, "X"), sc)
            sc.useResult(rk)
            String call = expr(fld(init, "X"), e, sc)
            String t = e.nt()
            e.add(cType(rk) + " " + t + " = " + call + ";")
            e.add("if (!" + t + ".ok) {")
            e.add("    xn_ret = " + t + ";")
            emitCleanup(sc, e, e.ind + 8, e.ind + 8, true)
            e.add("    return xn_ret;")
            e.add("}")
            String vt = resultVal(rk)
            e.add(cType(vt) + " " + nm + " = " + t + ".v;")
            return
        }
        if ty == "Bytes" {
            if init.nm == "Call" {
                N bc = fld(init, "Callee")
                N bargs = fld(init, "Args")
                if bc.nm == "Member" && unq(txt(fld(bc, "Name"))) == "fromString" && bargs.el.length() == 1 {
                    String bs = emitStr(bargs.el.get(0), e, sc)
                    String bt = e.nt()
                    e.add("xrt_bytes_obj *" + bt + " = xrt_bytes_from_string(" + bs + "->bytes, " + bs + "->len);")
                    e.add("rt_release(" + bs + ");")
                    e.add("xrt_bytes_obj *" + nm + " = " + bt + ";")
                    finishLocalRoot(sc, e, nm, "Bytes")
                    addRelease(sc, "rt_release(" + nm + ");")
                    return
                }
            }
            e.add("xrt_bytes_obj *" + nm + " = " + expr(init, e, sc) + ";")
            finishLocalRoot(sc, e, nm, "Bytes")
            addRelease(sc, "rt_release(" + nm + ");")
            return
        }
        if ty == "String" {
            if init.nm == "StrLitExpr" {
                N parts0 = fld(init, "Parts")
                Bool hasEx = false
                Int pei = 0
                while pei < parts0.el.length() {
                    N ex0 = fld(parts0.el.get(pei), "Expr")
                    if ex0.nm != "" && ex0.nm != "nil" { hasEx = true }
                    pei = pei + 1
                }
                if !hasEx {
                    e.tmp = e.tmp + 1
                    String text = liteText(init)
                    e.add("rt_string *" + nm + " = rt_string_from_c(" + q(text) + ");")
                } else if parts0.el.length() == 1 && unq(txt(fld(parts0.el.get(0), "Text"))) == "" {
                    String sdum0 = e.nt()
                    e.add("rt_string *" + nm + " = " + strHelper(fld(parts0.el.get(0), "Expr"), e, sc) + ";")
                } else {
                    String sv = emitStr(init, e, sc)
                    e.add("rt_string *" + nm + " = " + sv + ";")
                }
            } else if init.nm == "IdentExpr" || init.nm == "Member" {
                String sdum1 = e.nt()
                e.add("rt_string *" + nm + " = rt_retain(" + expr(init, e, sc) + ");")
            } else if init.nm == "Call" {
                N ic0 = fld(init, "Callee")
                N as0 = fld(init, "Args")
                Bool subM = false
                if ic0.nm == "Member" && unq(txt(fld(ic0, "Name"))) == "substring" {
                    if fld(ic0, "X").nm == "Member" && as0.el.length() >= 2 { subM = true }
                }
                if subM {
                    String sd0 = e.nt()
                    e.add("rt_string *" + sd0 + " = rt_retain(" + expr(fld(ic0, "X"), e, sc) + ");")
                    String sd1 = e.nt()
                    e.add("rt_string *" + nm + " = xn_str_substr(" + sd0 + ", " + expr(as0.el.get(0), e, sc) + ", " + expr(as0.el.get(1), e, sc) + ");")
                } else {
                    String sdum = e.nt()
                    e.add("rt_string *" + nm + " = " + expr(init, e, sc) + ";")
                }
            } else {
                String sv = emitStr(init, e, sc)
                e.add("rt_string *" + nm + " = " + sv + ";")
            }
            finishLocalRoot(sc, e, nm, "String")
            addRelease(sc, "rt_release(" + nm + ");")
            return
        }
        if isU16List(ty) {
            N elems = fld(init, "Elems")
            String t = e.nt()
            e.add("xn_arr_u16 *" + t + " = xn_arr_u16_new(" + str(elems.el.length()) + ");")
            Int i = 0
            while i < elems.el.length() { e.raw("xn_arr_u16_push(" + t + ", " + expr(elems.el.get(i), e, sc) + ");"); i = i + 1 }
            e.add("xn_arr_u16 * " + nm + " = " + t + ";")
            finishLocalRoot(sc, e, nm, ty)
            return
        }
        if isObjArr(ty) {
            e.usesObjArr = true
            e.objArrKey = ty
            String an = classArrName(ty)
            N elems = fld(init, "Elems")
            String t = e.nt()
            e.add(an + " *" + t + " = " + an + "_new(" + str(elems.el.length()) + ");")
            Int i = 0
            while i < elems.el.length() { e.raw(an + "_push(" + t + ", " + expr(elems.el.get(i), e, sc) + ");"); i = i + 1 }
            e.add(an + " * " + nm + " = " + t + ";")
            finishLocalRoot(sc, e, nm, ty)
            return
        }
        if isTupList(ty) {
            e.usesTArr = true
            String an = arrTupName(ty)
            N elems = fld(init, "Elems")
            String t = e.nt()
            e.add(an + " *" + t + " = " + an + "_new(" + str(elems.el.length()) + ");")
            Int i = 0
            while i < elems.el.length() { e.raw(an + "_push(" + t + ", " + expr(elems.el.get(i), e, sc) + ");"); i = i + 1 }
            e.add(an + " * " + nm + " = " + t + ";")
            finishLocalRoot(sc, e, nm, ty)
            return
        }
        if init.nm == "ArrayLit" && isArr(ty) {
            e.usesList = true
            N elems = fld(init, "Elems")
            String an = arrNameC(cType(arrElem(ty)))
            String t = e.nt()
            e.add(an + " *" + t + " = " + an + "_new(" + str(elems.el.length()) + ");")
            Int i = 0
            while i < elems.el.length() { e.raw(an + "_push(" + t + ", " + expr(elems.el.get(i), e, sc) + ");"); i = i + 1 }
            e.add(an + " * " + nm + " = " + t + ";")
            finishLocalRoot(sc, e, nm, ty)
            return
        }
        if isSet(ty) {
            e.hasSet = true
            N elems = fld(init, "Elems")
            String ta = e.nt()
            e.add("xn_arr_i *" + ta + " = xn_arr_i_new(" + str(elems.el.length()) + ");")
            Int i = 0
            while i < elems.el.length() { e.raw("xn_arr_i_push(" + ta + ", " + expr(elems.el.get(i), e, sc) + ");"); i = i + 1 }
            String ts = e.nt()
            e.add("xn_set_i *" + ts + " = xn_set_i_new();")
            e.raw("for (size_t i = 0; i < " + ta + "->len; i++) { xn_set_i_add(" + ts + ", " + ta + "->data[i]); }")
            e.add("xn_set_i * " + nm + " = " + ts + ";")
            finishLocalRoot(sc, e, nm, ty)
            return
        }
        if isMap(ty) {
            e.hasMap = true
            N keys = fld(init, "Keys")
            N vals = fld(init, "Vals")
            String tm = e.nt()
            e.add("xn_map_s_i *" + tm + " = xn_map_s_i_new(" + str(keys.el.length()) + ");")
            Int i = 0
            while i < keys.el.length() {
                String kt = emitStr(keys.el.get(i), e, sc)
                String tv = expr(vals.el.get(i), e, sc)
                e.raw("xn_map_s_i_put(" + tm + ", " + kt + ", " + tv + ");")
                i = i + 1
            }
            e.add("xn_map_s_i * " + nm + " = " + tm + ";")
            finishLocalRoot(sc, e, nm, ty)
            return
        }
        if ty == "Any" {
            e.usesAny = true
            e.add("xn_Any * " + nm + " = " + expr(init, e, sc) + ";")
            finishLocalRoot(sc, e, nm, ty)
            return
        }
        if ty == "Int?" || ty == "Bool?" || ty == "String?" {
            if init.nm == "Call" {
                N ic = fld(init, "Callee")
                if ic.nm == "IdentExpr" && unq(txt(fld(ic, "Name"))) == "env" {
                    String ev = expr(init, e, sc)
                    String et = e.nt()
                    e.add(cType(ty) + " " + et + " = " + ev + ";")
                    e.add(cType(ty) + " " + nm + " = " + et + ";")
                    return
                }
            }
            if init.nm == "NullLit" { e.add(cType(ty) + " " + nm + " = (" + cType(ty) + "){0, 0};") }
            else {
                String iv = expr(init, e, sc)
                if ty == "String?" && exprType(init, sc) == "String" { iv = emitStr(init, e, sc) }
                e.add(cType(ty) + " " + nm + " = (" + cType(ty) + "){1, " + iv + "};")
            }
            return
        }
        if isTupleKey(ty) {
            if init.nm != "Tuple" {
                e.add(cType(ty) + " " + nm + " = " + expr(init, e, sc) + ";")
                return
            }
            N elems = fld(init, "Elems")
            List<String> vals = []
            Int ei = 0
            String elemsStr = tupleElems(ty)
            while ei < elems.el.length() {
                String ev = ""
                if exprType(elems.el.get(ei), sc) == "String" { ev = emitStr(elems.el.get(ei), e, sc) } else { ev = expr(elems.el.get(ei), e, sc) }
                vals.push(ev)
                ei = ei + 1
            }
            String cn0 = cType(ty)
            String b0 = cn0 + " " + nm + " = (" + cn0 + "){"
            ei = 0
            while ei < vals.length() { if ei > 0 { b0 = b0 + ", " }; b0 = b0 + ".f" + str(ei) + " = " + vals.get(ei); ei = ei + 1 }
            e.add(b0 + "};")
            return
        }
        if isProtoType(ty) {
            if init.nm == "New" {
                String ccls = typeKey(fld(init, "Type"))
                N nargs = fld(init, "Args")
                String b = "xn_Cls_" + ccls + "_new("
                Int ai = 0
                while ai < nargs.el.length() { if ai > 0 { b = b + ", " }; b = b + expr(nargs.el.get(ai), e, sc); ai = ai + 1 }
                e.add("xn_proto_" + ty + " " + nm + " = " + b + ");")
            } else {
                e.add("xn_proto_" + ty + " " + nm + " = " + expr(init, e, sc) + ";")
            }
            finishLocalRoot(sc, e, nm, ty)
            addNamedRelease(sc, nm, "rt_release((void *)" + nm + ");")
            return
        }
        if isClass(ty) {
            Bool isGC = classPolicy(ty) == "gc"
            if init.nm == "New" {
                N args = fld(init, "Args")
                if classStackOK(ty) && !isEscaped(sc, nm) {
                    String t = e.nt()
                    e.add("xn_Cls_" + ty + " " + t + ";")
                    e.raw("memset((char *)&" + t + ", 0, sizeof(xn_Cls_" + ty + "));")
                    String b = "xn_Cls_" + ty + "_new" + (isPrimaryName(ty) ? "_1" : "") + "_init" + "(&" + t
                    Int ai = 0
                    while ai < args.el.length() { b = b + ", " + expr(args.el.get(ai), e, sc); ai = ai + 1 }
                    e.raw(b + ");")
                    e.add("xn_Cls_" + ty + " * " + nm + " = &" + t + ";")
                    finishLocalRoot(sc, e, nm, ty)
                } else {
                    String b = "xn_Cls_" + ty + "_new("
                    Int ai = 0
                    while ai < args.el.length() {
                        if ai > 0 { b = b + ", " }
                        N av = args.el.get(ai)
                        if exprType(av, sc) == "String" { b = b + emitStr(av, e, sc) } else { b = b + expr(av, e, sc) }
                        ai = ai + 1
                    }
                    e.add("xn_Cls_" + ty + " * " + nm + " = " + b + ");")
                    finishLocalRoot(sc, e, nm, ty)
                    if !isGC { addNamedRelease(sc, nm, "rt_release(" + nm + ");") }
                }
                return
            }
            if init.nm == "IdentExpr" && !isGC {
                String src = expr(init, e, sc)
                e.add("xn_Cls_" + ty + " * " + nm + " = rt_retain(" + src + ");")
                finishLocalRoot(sc, e, nm, ty)
                addNamedRelease(sc, nm, "rt_release(" + nm + ");")
                return
            }
            e.add("xn_Cls_" + ty + " * " + nm + " = " + expr(init, e, sc) + ";")
            finishLocalRoot(sc, e, nm, ty)
            if !isGC { addNamedRelease(sc, nm, "rt_release(" + nm + ");") }
            return
        }
        if isStruct(ty) {
            if init.nm == "New" {
                String b = "xn_Struct_" + ty + "_new("
                N args = fld(init, "Args")
                Int ai = 0
                while ai < args.el.length() {
                    if ai > 0 { b = b + ", " }
                    b = b + expr(args.el.get(ai), e, sc)
                    ai = ai + 1
                }
                e.add("xn_Struct_" + ty + " " + nm + " = " + b + ");")
            } else {
                e.add("xn_Struct_" + ty + " " + nm + " = " + expr(init, e, sc) + ";")
            }
            return
        }
        if isResult(ty) {
            e.add(cType(ty) + " " + nm + " = " + expr(init, e, sc) + ";")
            return
        }
        Bool now0 = NO_OP_WRAP
        if init.nm == "Binary" && (unq(txt(fld(init, "Op"))) == "&&" || unq(txt(fld(init, "Op"))) == "||") { NO_OP_WRAP = true }
        String genv = expr(init, e, sc)
        NO_OP_WRAP = now0
        e.add(cType(ty) + " " + nm + " = " + genv + ";")
        return
    }
    if st.nm == "AssignStmt" {
        N tgt = fld(st, "Target")
        String op0 = unq(txt(fld(st, "Op")))
        N val0 = fld(st, "Value")
        if tgt.nm == "Member" && op0 == "=" {
            String mtt = exprType(tgt, sc)
            if isProtoType(stripQ(mtt)) {
                String mnm = expr(tgt, e, sc)
                String pt0 = e.nt()
                String pv0 = expr(val0, e, sc)
                if val0.nm == "IdentExpr" || val0.nm == "Member" { e.add("void *" + pt0 + " = rt_retain((void *)" + pv0 + ");") }
                else { e.add("void *" + pt0 + " = rt_retain((void *)(" + pv0 + "));") }
                e.add("rt_release((void *)" + mnm + ");")
                e.add(mnm + " = " + pt0 + ";")
                return
            }
            String mcls = baseCls(mtt)
            if mcls != "" {
                String mnm = expr(tgt, e, sc)
                if classPolicy(mcls) == "arc" {
                    String t = e.nt()
                    if val0.nm == "New" { e.add(cType(mcls) + " " + t + " = " + expr(val0, e, sc) + ";") }
                    else { e.add(cType(mcls) + " " + t + " = rt_retain(" + expr(val0, e, sc) + ");") }
                    e.add("rt_release(" + mnm + ");")
                    e.add(mnm + " = " + t + ";")
                } else {
                    e.add(mnm + " = " + expr(val0, e, sc) + ";")
                }
                return
            }
        }
        String v0 = ""
        if tgt.nm == "TupleMember" {
            e.add(expr(fld(tgt, "X"), e, sc) + ".f" + txt(fld(tgt, "Index")) + " = " + expr(fld(st, "Value"), e, sc) + ";")
            return
        }
        if tgt.nm == "Index" {
            String xb = expr(fld(tgt, "X"), e, sc)
            String ix = expr(fld(tgt, "Idx"), e, sc)
            e.add(arrNameC(cType(arrElem(exprType(fld(tgt, "X"), sc)))) + "_set(" + xb + ", " + ix + ", " + expr(fld(st, "Value"), e, sc) + ");")
            return
        }
        String nm = expr(tgt, e, sc)
        String op = unq(txt(fld(st, "Op")))
        String v = ""
        if tgt.nm == "IdentExpr" && exprType(tgt, sc) == "String" && op == "=" {
            String sv = emitStr(fld(st, "Value"), e, sc)
            SC owner = sc
            while owner.parentId >= 0 && !inNames(owner.own, nm) { owner = parentOf(owner) }
            if owner == sc {
                e.add("rt_release(" + nm + ");")
                e.add(nm + " = " + sv + ";")
                e.add("xn_root_add(" + nm + ");")
            } else {
                if !inNames(owner.blockHeld, nm) { owner.blockHeld.push(nm) }
                e.add("xn_root_release(" + nm + ");")
                e.add("rt_release(" + nm + ");")
                e.add(nm + " = " + sv + ";")
                e.add("xn_root_hold(" + nm + ");")
            }
            e.add("xn_gc_safepoint();")
            return
        }
        if tgt.nm == "Member" && exprType(tgt, sc) == "String" && op == "=" {
            if val0.nm == "StrLitExpr" {
                String svl = emitStr(val0, e, sc)
                e.add("rt_release(" + nm + ");")
                e.add(nm + " = " + svl + ";")
                return
            }
            String vv0 = expr(fld(st, "Value"), e, sc)
            String t = e.nt()
            e.add("rt_string *" + t + " = rt_retain(" + vv0 + ");")
            rootStr(e, sc, t)
            e.add("rt_release(" + nm + ");")
            e.add(nm + " = " + t + ";")
            return
        }
        v0 = expr(fld(st, "Value"), e, sc)
        v = v0
        if op == "+=" { e.add(nm + " = " + nm + " + (" + v + ");") }
        else if op == "-=" { e.add(nm + " = " + nm + " - (" + v + ");") }
        else { e.add(nm + " = " + v + ";") }
        return
    }
    if st.nm == "ExprStmt" {
        N call = fld(st, "X")
        if call.nm == "Call" {
            N callee = fld(call, "Callee")
            N args = fld(call, "Args")
            if callee.nm == "Member" {
                N mx = fld(callee, "X")
                String mn = unq(txt(fld(callee, "Name")))
                if mx.nm == "IdentExpr" && unq(txt(fld(mx, "Name"))) == "super" {
                    e.add(expr(call, e, sc) + ";")
                    return
                }
                String xb = expr(mx, e, sc)
                String rt0 = exprType(mx, sc)
                if mn == "push" && (rt0 == "Bytes" || isU16List(rt0) || isObjArr(rt0) || isArr(rt0)) {
                    String a0 = "0"
                    if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                    if rt0 == "Bytes" { e.add("xrt_bytes_push(" + xb + ", (int32_t)(" + a0 + "));") }
                    else if isU16List(rt0) { e.add("xn_arr_u16_push(" + xb + ", " + a0 + ");") }
                    else if isObjArr(rt0) { e.add(classArrName(rt0) + "_push(" + xb + ", " + a0 + ");") }
                    else { e.add(arrNameC(cType(arrElem(rt0))) + "_push(" + xb + ", " + a0 + ");") }
                    return
                }
                if mn == "clear" && (isSet(rt0) || isU16List(rt0) || isObjArr(rt0) || isArr(rt0)) {
                    if isSet(rt0) { e.add("xn_set_i_clear(" + xb + ");") }
                    else if isU16List(rt0) { e.add("xn_arr_u16_clear(" + xb + ");") }
                    else if isObjArr(rt0) { e.add(classArrName(rt0) + "_clear(" + xb + ");") }
                    else { e.add(arrNameC(cType(arrElem(rt0))) + "_clear(" + xb + ");") }
                    return
                }
                if mn == "put" && isMap(rt0) {
                    String a0 = "0"
                    String a1 = "0"
                    if args.el.length() > 0 { a0 = emitStr(args.el.get(0), e, sc) }
                    if args.el.length() > 1 { a1 = expr(args.el.get(1), e, sc) }
                    e.add(mapNameC(cType(mapKey(rt0)), cType(mapVal(rt0))) + "_put(" + xb + ", " + a0 + ", " + a1 + ");")
                    return
                }
                if mn == "set" && (isArr(rt0) || isU16List(rt0) || isObjArr(rt0)) {
                    String a0 = "0"
                    String a1 = "0"
                    if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                    if args.el.length() > 1 { a1 = expr(args.el.get(1), e, sc) }
                    if isU16List(rt0) { e.add("xn_arr_u16_set(" + xb + ", " + a0 + ", " + a1 + ");") }
                    else if isObjArr(rt0) { e.add(classArrName(rt0) + "_set(" + xb + ", " + a0 + ", " + a1 + ");") }
                    else { e.add(arrNameC(cType(arrElem(rt0))) + "_set(" + xb + ", " + a0 + ", " + a1 + ");") }
                    return
                }
            }
            if callee.nm == "IdentExpr" {
                String bn = unq(txt(fld(callee, "Name")))
                if bn == "diagnose" && args.el.length() > 0 {
                    String dt = emitStr(args.el.get(0), e, sc)
                    e.add("xdkc_diagnose(" + dt + "->bytes, " + dt + "->len);")
                    return
                }
                if bn == "dumpTasks" {
                    e.add("xrt_safepoint();")
                    e.add("xdkc_dump_tasks();")
                    return
                }
                if bn == "exit" && args.el.length() > 0 {
                    e.add("xdkc_exit((int64_t)(" + expr(args.el.get(0), e, sc) + "));")
                    return
                }
            }
            if callee.nm == "IdentExpr" {
                String bn2 = unq(txt(fld(callee, "Name")))
                if bn2 == "print" && args.el.length() > 0 { emitPrint(args.el.get(0), e, sc); return }
            }
            e.add(expr(call, e, sc) + ";")
        }
        return
    }
    if st.nm == "ReturnStmt" {
        e.terminated = false
        N v = fld(st, "Value")
        if sc.isCtor || sc.retKind == "void" {
            emitReturnClose(sc, e, "")
            return
        }
        if isResult(sc.retKind) {
            String rk = sc.retKind
            Bool okerr = false
            if v.nm == "Call" {
                N callee = fld(v, "Callee")
                String cn = ""
                if callee.nm == "IdentExpr" { cn = unq(txt(fld(callee, "Name"))) }
                N args = fld(v, "Args")
                if cn == "Ok" {
                    String arg = "0"
                    if args.el.length() > 0 { arg = expr(args.el.get(0), e, sc) }
                    String rvz = arg
                    String ez = "0"
                    String ect = cType(resultErr(rk))
                    if ect.length() > 0 && ect.substring(ect.length() - 1, 1) == "*" { ez = "NULL" }
                    e.add("xn_ret = (" + cType(rk) + "){1, " + rvz + ", " + ez + "};")
                    okerr = true
                } else if cn == "Err" {
                    N ea = args.el.get(0)
                    String et = exprType(ea, sc)
                    String ev = ""
                    if et == "String" {
                        ev = emitStr(ea, e, sc)
                    } else if ea.nm == "Call" {
                        N ec = fld(ea, "Callee")
                        N ecs = fld(ea, "Args")
                        if ec.nm == "IdentExpr" && ecs.el.length() == 1 && exprType(ecs.el.get(0), sc) == "String" {
                            String mt = emitStr(ecs.el.get(0), e, sc)
                            ev = "xn_" + unq(txt(fld(ec, "Name"))) + "(" + mt + ")"
                        } else {
                            ev = expr(ea, e, sc)
                        }
                    } else {
                        ev = expr(ea, e, sc)
                    }
                    String evz = "0"
                    String vct = cType(resultVal(rk))
                    if vct.length() > 0 && vct.substring(vct.length() - 1, 1) == "*" { evz = "NULL" }
                    e.add("xn_ret = (" + cType(rk) + "){0, " + evz + ", " + ev + "};")
                    okerr = true
                }
            }
            if !okerr && v.nm != "" && v.nm != "nil" { e.add("xn_ret = " + expr(v, e, sc) + ";") }
            emitReturnClose(sc, e, "xn_ret")
            return
        }
        if v.nm == "New" {
            String ccls = typeKey(fld(v, "Type"))
            N nargs = fld(v, "Args")
            String b = "xn_Cls_" + ccls + "_new("
            Int ai = 0
            while ai < nargs.el.length() {
                if ai > 0 { b = b + ", " }
                N an = nargs.el.get(ai)
                if an.nm == "NullLit" { b = b + "NULL" }
                else if exprType(an, sc) == "String" {
                    String stx = emitStr(an, e, sc)
                    b = b + stx
                } else { b = b + expr(an, e, sc) }
                ai = ai + 1
            }
            if isProtoType(sc.retKind) {
                sc.ret = b + ")"
            } else {
                String nt0 = e.nt()
                e.add(cType(sc.retKind) + nt0 + " = " + b + ");")
                sc.ret = nt0
            }
            emitReturnClose(sc, e, sc.ret)
            return
        }
        if baseCls(sc.retKind) != "" && v.nm == "IdentExpr" {
            String pv = expr(v, e, sc)
            if classPolicy(baseCls(sc.retKind)) == "arc" { e.add("rt_retain(" + pv + ");") }
            sc.ret = pv
            emitReturnClose(sc, e, sc.ret)
            return
        }
        if isTupleKey(exprType(v, sc)) {
            if v.nm == "Tuple" {
                sc.deferredRet = expr(v, e, sc)
                sc.directRet = true
                emitReturnClose(sc, e, sc.deferredRet)
                return
            }
            String tk = exprType(v, sc)
            String tt = e.nt()
            e.add(cType(tk) + " " + tt + " = " + expr(v, e, sc) + ";")
            sc.ret = tt
            emitReturnClose(sc, e, sc.ret)
            return
        }
        if exprType(v, sc) == "String" {
            if v.nm == "IdentExpr" {
                String pv = expr(v, e, sc)
                e.add("rt_retain(" + pv + ");")
                sc.ret = pv
                emitReturnClose(sc, e, sc.ret)
                return
            }
            String t = emitStr(v, e, sc)
            sc.ret = t
            emitReturnClose(sc, e, sc.ret)
            return
        }
        if isEnumType(sc.retKind) && (v.nm == "Member" || v.nm == "IdentExpr") {
            sc.ret = expr(v, e, sc)
            emitReturnClose(sc, e, sc.ret)
            return
        }
        if v.nm == "Call" && isClass(sc.retKind) {
            N cv1 = fld(v, "Callee")
            if cv1.nm == "IdentExpr" {
                N av1 = fld(v, "Args")
                String cb1 = "xn_" + unq(txt(fld(cv1, "Name"))) + "("
                Int ci1 = 0
                while ci1 < av1.el.length() {
                    if ci1 > 0 { cb1 = cb1 + ", " }
                    N aa1 = av1.el.get(ci1)
                    if aa1.nm == "Call" {
                        String at1 = e.nt()
                        e.add(cType(exprType(aa1, sc)) + " " + at1 + " = " + expr(aa1, e, sc) + ";")
                        cb1 = cb1 + at1
                    } else if exprType(aa1, sc) == "String" { cb1 = cb1 + emitStr(aa1, e, sc) }
                    else { cb1 = cb1 + expr(aa1, e, sc) }
                    ci1 = ci1 + 1
                }
                emitReturnClose(sc, e, cb1 + ")")
                return
            }
            if cv1.nm == "Member" {
                emitReturnClose(sc, e, expr(v, e, sc))
                return
            }
        }
        if sc.retKind == "Int?" || sc.retKind == "Bool?" || sc.retKind == "String?" {
            String oz = "0"
            if sc.retKind == "String?" { oz = "NULL" }
            if v.nm == "NullLit" { emitReturnClose(sc, e, "(" + cType(sc.retKind) + "){0, " + oz + "}") }
            else { emitReturnClose(sc, e, "(" + cType(sc.retKind) + "){1, " + expr(v, e, sc) + "}") }
            return
        }
        if v.nm == "Call" && sc.retKind == "Int" {
            N cv2 = fld(v, "Callee")
            if cv2.nm == "IdentExpr" {
                emitReturnClose(sc, e, expr(v, e, sc))
                return
            }
        }
        String rv0 = expr(v, e, sc)
        String t = e.nt()
        e.add(cType(sc.retKind) + " " + t + " = " + rv0 + ";")
        sc.ret = t
        emitReturnClose(sc, e, sc.ret)
        return
    }
    if st.nm == "IfStmt" {
        N cond = fld(st, "Cond")
        String cexpr = expr(cond, e, sc)
        if cond.nm == "Binary" && (unq(txt(fld(cond, "Op"))) == "&&" || unq(txt(fld(cond, "Op"))) == "||") { cexpr = stripOuter(cexpr) }
        if cond.nm == "BoolLit" { e.addAt(e.ind + 4, "if (" + cexpr + ") {") } else { e.addAt(e.ind + 4, "if ((" + cexpr + ")) {") }
        e.terminated = false
        SC thenSc = newChild(sc, e)
        emitBlock(fld(st, "Then"), e, thenSc, e.ind + 8, true)
        N els = fld(st, "Else")
        if els.nm != "" && els.nm != "nil" {
            e.addAt(e.ind + 4, "} else {")
            if els.nm == "IfStmt" {
                Int saveEI = e.ind
                e.ind = e.ind + 8
                e.terminated = false
                SC elseSc = newChild(sc, e)
                SKIP_LINE = true
                emitStmt(els, e, sc, true)
                e.ind = saveEI
            } else {
                e.terminated = false
                SC elseSc2 = newChild(sc, e)
                if els.nm == "Block" { emitBlock(els, e, elseSc2, e.ind + 8, true) } else {
                    Int save = e.ind
                    e.ind = e.ind + 8
                    emitStmt(els, e, elseSc2, true)
                    e.ind = save
                }
            }
            e.addAt(e.ind + 4, "}")
        } else {
            e.addAt(e.ind + 4, "}")
        }
        return
    }
    if st.nm == "WhileStmt" {
        N cond = fld(st, "Cond")
        Int wstart = e.ls.length()
        String cexpr = expr(cond, e, sc)
        String cexprRaw = cexpr
        if cond.nm == "Binary" && (unq(txt(fld(cond, "Op"))) == "&&" || unq(txt(fld(cond, "Op"))) == "||") { cexpr = stripOuter(cexpr) }
        Bool lowered = e.ls.length() > wstart
        if lowered {
            List<String> cl = []
            Int wi = wstart
            while wi < e.ls.length() {
                String wl = e.ls.get(wi)
                String wt = wl.trim()
                if wt.indexOf("rt_string *") == 0 || wt.indexOf("xrt_bytes_obj *") == 0 || wt.indexOf("xn_arr_") == 0 { cl.push(sp(8) + wl) } else { cl.push(wl) }
                wi = wi + 1
            }
            while e.ls.length() > wstart { e.ls.remove(e.ls.length() - 1) }
            e.addAt(e.ind + 4, "while (1) {")
            wi = 0
            while wi < cl.length() { e.ls.push(cl.get(wi)); wi = wi + 1 }
            if cond.nm == "Binary" && (unq(txt(fld(cond, "Op"))) == "&&" || unq(txt(fld(cond, "Op"))) == "||") {
                e.addAt(e.ind + 8, "if (!(" + cexprRaw + ")) { break; }")
            } else {
                e.addAt(e.ind + 8, "if (!((" + cexprRaw + "))) { break; }")
            }
            SC bodySc = newChild(sc, e)
            bodySc.kind = "loop"
            e.terminated = false
            emitBlock(fld(st, "Body"), e, bodySc, e.ind + 8, true)
            e.addAt(e.ind + 8, "xn_gc_safepoint();")
            e.addAt(e.ind + 4, "}")
            return
        }
        if cond.nm == "BoolLit" { e.addAt(e.ind + 4, "while (" + cexpr + ") {") } else { e.addAt(e.ind + 4, "while ((" + cexpr + ")) {") }
        SC bodySc2 = newChild(sc, e)
        bodySc2.kind = "loop"
        e.terminated = false
        emitBlock(fld(st, "Body"), e, bodySc2, e.ind + 4, true)
        e.addAt(e.ind + 4, "xn_gc_safepoint();")
        e.addAt(e.ind + 4, "}")
        return
    }
    if st.nm == "ForStmt" {
        String vname = unq(txt(fld(st, "Var")))
        String coll = expr(fld(st, "Src"), e, sc)
        SC bodySc3 = newChild(sc, e)
        bodySc3.kind = "loop"
        String loop = e.nt()
        e.addAt(e.ind, "for (size_t " + loop + " = 0; " + loop + " < " + coll + "->len; " + loop + "++) {")
        e.addAt(e.ind + 4, "int64_t " + vname + " = " + coll + "->data[" + loop + "];")
        e.terminated = false
        emitBlock(fld(st, "Body"), e, bodySc3, e.ind + 4, true)
        e.addAt(e.ind + 4, "xn_gc_safepoint();")
        e.addAt(e.ind, "}")
        return
    }
    if st.nm == "SwitchStmt" {
        String val = expr(fld(st, "Value"), e, sc)
        N cases = fld(st, "Cases")
        List<String> caseVals = []
        Int ci = 0
        while ci < cases.el.length() {
            caseVals.push(expr(fld(cases.el.get(ci), "Expr"), e, sc))
            ci = ci + 1
        }
        e.addAt(e.ind + 4, "do {")
        Int i = 0
        while i < cases.el.length() {
            N c = cases.el.get(i)
            String head = "else if "
            if i == 0 { head = "if " }
            e.addAt(e.ind + 8, head + "(" + val + " == (" + caseVals.get(i) + ")) {")
            SC caseSc = newChild(sc, e)
            caseSc.kind = "switch"
            emitScopedStmts(caseSc, fld(c, "Stmts"), e, e.ind + 12, true)
            e.addAt(e.ind + 8, "}")
            i = i + 1
        }
        N def = fld(st, "Default")
        if def.nm != "" && def.nm != "nil" {
            e.addAt(e.ind + 8, "else {")
            SC defSc = newChild(sc, e)
            defSc.kind = "switch"
            emitScopedStmts(defSc, fld(def, "Stmts"), e, e.ind + 12, true)
            e.addAt(e.ind + 8, "}")
        }
        e.addAt(e.ind + 4, "} while (0);")
        return
    }
}

static void emitScopedStmts(SC s, N stmts, EM e, Int ind, Bool early) {
    if s.rootMark != "" && !s.rootDeclared {
        s.rootDeclared = true
        e.addAt(ind, "size_t " + s.rootMark + " = xn_root_mark();")
        Int pi = 0
        while pi < s.rootPrelude.length() {
            e.addAt(ind, s.rootPrelude.get(pi))
            pi = pi + 1
        }
        s.rootPrelude = []
        addDefer(s, ["xn_root_restore(" + s.rootMark + ");"], false)
    }
    Int i = 0
    while i < stmts.el.length() {
        Int save = e.ind
        e.ind = ind
        emitStmt(stmts.el.get(i), e, s, early)
        e.ind = save
        i = i + 1
    }
    emitBlockExit(s, e, ind)
}

static void emitBlock(N blk, EM e, SC sc, Int ind, Bool early) {
    if blk.nm != "Block" { return }
    emitScopedStmts(sc, fld(blk, "Stmts"), e, ind, early)
}

static String paramsOf(N fn) {
    N ps = fld(fn, "Params")
    String b = ""
    Int i = 0
    while i < ps.el.length() {
        N p = ps.el.get(i)
        String ty = typeKey(fld(p, "Type"))
        String nm = unq(txt(fld(p, "Name")))
        if i > 0 { b = b + ", " }
        b = b + paramDecl(cType(ty), "xn_p_" + nm)
        i = i + 1
    }
    return b
}

static Bool inNames(List<String> xs, String v) {
    Int i = 0
    while i < xs.length() { if xs.get(i) == v { return true }; i = i + 1 }
    return false
}
static void escMark(SC sc, String n) {
    if n == "" || n == "self" || n == "super" { return }
    if !inNames(sc.escaped, n) { sc.escaped.push(n) }
}
static void escAll(N n, SC sc) {
    if n.nm == "" || n.nm == "nil" { return }
    if n.nm == "IdentExpr" { escMark(sc, unq(txt(fld(n, "Name")))) }
    Int i = 0
    while i < n.fv.length() { escAll(n.fv.get(i), sc); i = i + 1 }
    i = 0
    while i < n.el.length() { escAll(n.el.get(i), sc); i = i + 1 }
}
static void escExpr(N x, Bool mark, SC sc) {
    if x.nm == "" || x.nm == "nil" { return }
    if x.nm == "IdentExpr" { if mark { escMark(sc, unq(txt(fld(x, "Name")))) }; return }
    if x.nm == "StrLitExpr" {
        N ps = fld(x, "Parts")
        Int i = 0
        while i < ps.el.length() { escExpr(ps.el.get(i), mark, sc); i = i + 1 }
        return
    }
    if x.nm == "Paren" { escExpr(fld(x, "X"), mark, sc); return }
    if x.nm == "Tuple" {
        N els = fld(x, "Elems")
        Int i = 0
        while i < els.el.length() { escExpr(els.el.get(i), mark, sc); i = i + 1 }
        return
    }
    if x.nm == "ArrayLit" {
        N els = fld(x, "Elems")
        Int i = 0
        while i < els.el.length() { escExpr(els.el.get(i), mark, sc); i = i + 1 }
        return
    }
    if x.nm == "MapLit" {
        N ks = fld(x, "Keys")
        N vs = fld(x, "Vals")
        Int i = 0
        while i < ks.el.length() { escExpr(ks.el.get(i), mark, sc); escExpr(vs.el.get(i), mark, sc); i = i + 1 }
        return
    }
    if x.nm == "Unary" { escExpr(fld(x, "X"), mark, sc); return }
    if x.nm == "Binary" {
        String op = unq(txt(fld(x, "Op")))
        Bool m2 = mark
        if op == "is" || op == "==" || op == "!=" || op == "===" || op == "!==" { m2 = false }
        escExpr(fld(x, "L"), m2, sc)
        escExpr(fld(x, "R"), m2, sc)
        return
    }
    if x.nm == "Ternary" {
        escExpr(fld(x, "Cond"), mark, sc)
        escExpr(fld(x, "Then"), mark, sc)
        escExpr(fld(x, "Else"), mark, sc)
        return
    }
    if x.nm == "Member" { escExpr(fld(x, "X"), false, sc); return }
    if x.nm == "TupleMember" { escExpr(fld(x, "X"), false, sc); return }
    if x.nm == "Call" {
        N args = fld(x, "Args")
        Int i = 0
        while i < args.el.length() { escExpr(args.el.get(i), true, sc); i = i + 1 }
        N callee = fld(x, "Callee")
        if callee.nm == "Member" { escExpr(fld(callee, "X"), false, sc) } else { escExpr(callee, true, sc) }
        return
    }
    if x.nm == "Index" { escExpr(fld(x, "X"), true, sc); escExpr(fld(x, "Idx"), true, sc); return }
    if x.nm == "New" {
        N args = fld(x, "Args")
        Int i = 0
        while i < args.el.length() { escExpr(args.el.get(i), true, sc); i = i + 1 }
        return
    }
    if x.nm == "NewArray" { escExpr(fld(x, "Count"), true, sc); return }
    if x.nm == "Lambda" { escAll(x, sc); return }
    escAll(x, sc)
}
static void escStmt(N st, SC sc) {
    if st.nm == "ReturnStmt" || st.nm == "ThrowStmt" { escExpr(fld(st, "Value"), true, sc); return }
    if st.nm == "ExprStmt" { escExpr(fld(st, "X"), true, sc); return }
    if st.nm == "LocalDeclStmt" { escExpr(fld(st, "Init"), true, sc); return }
    if st.nm == "AssignStmt" {
        escExpr(fld(st, "Value"), true, sc)
        N tg = fld(st, "Target")
        if tg.nm == "IdentExpr" { escMark(sc, unq(txt(fld(tg, "Name")))) }
        else if tg.nm == "Member" { escExpr(fld(tg, "X"), false, sc) }
        else if tg.nm == "Index" { escExpr(fld(tg, "X"), true, sc); escExpr(fld(tg, "Idx"), true, sc) }
        return
    }
    if st.nm == "IncDecStmt" {
        N tg = fld(st, "Target")
        if tg.nm == "IdentExpr" { escMark(sc, unq(txt(fld(tg, "Name")))) }
        return
    }
    if st.nm == "IfStmt" {
        escExpr(fld(st, "Cond"), true, sc)
        escBlock(fld(st, "Then"), sc)
        N el = fld(st, "Else")
        if el.nm != "" && el.nm != "nil" {
            if el.nm == "Block" { escBlock(el, sc) } else { escStmt(el, sc) }
        }
        return
    }
    if st.nm == "WhileStmt" { escExpr(fld(st, "Cond"), true, sc); escBlock(fld(st, "Body"), sc); return }
    if st.nm == "DoWhileStmt" { escBlock(fld(st, "Body"), sc); escExpr(fld(st, "Cond"), true, sc); return }
    if st.nm == "ForStmt" { escExpr(fld(st, "Src"), true, sc); escBlock(fld(st, "Body"), sc); return }
    if st.nm == "SwitchStmt" {
        escExpr(fld(st, "Value"), true, sc)
        N cs = fld(st, "Cases")
        Int i = 0
        while i < cs.el.length() {
            N c = cs.el.get(i)
            escExpr(fld(c, "Expr"), true, sc)
            N ss = fld(c, "Stmts")
            Int j = 0
            while j < ss.el.length() { escStmt(ss.el.get(j), sc); j = j + 1 }
            i = i + 1
        }
        N df = fld(st, "Default")
        if df.nm != "" && df.nm != "nil" {
            N ss2 = fld(df, "Stmts")
            Int j2 = 0
            while j2 < ss2.el.length() { escStmt(ss2.el.get(j2), sc); j2 = j2 + 1 }
        }
        return
    }
    if st.nm == "DeferStmt" {
        N b = fld(st, "Block")
        if b.nm == "Block" { escBlock(b, sc) } else { escStmt(fld(st, "Stmt"), sc) }
        return
    }
    if st.nm == "LabeledStmt" { escStmt(fld(st, "Stmt"), sc); return }
}
static void escBlock(N b, SC sc) {
    if b.nm != "Block" { return }
    N stmts = fld(b, "Stmts")
    Int i = 0
    while i < stmts.el.length() { escStmt(stmts.el.get(i), sc); i = i + 1 }
}
static Bool isEscaped(SC sc, String n) { return inNames(sc.escaped, n) }

static void emitBlockExit(SC sc, EM e, Int ind) {
    Int hi = 0
    while hi < sc.blockHeld.length() {
        e.addAt(ind, "xn_root_release(" + sc.blockHeld.get(hi) + ");")
        hi = hi + 1
    }
    if sc.returned { return }
    Int i = sc.defers.length() - 1
    while i >= 0 {
        DF d = sc.defers.get(i)
        if !d.err && d.lines.length() > 0 { emitDeferItem(d, e, ind + 4, ind + 4, false) }
        i = i - 1
    }
    if sc.parentId >= 0 { e.raw("") }
}

static void emitFunc(N fn, EM e, SC sc) {
    String fname = unq(txt(fld(fn, "Name")))
    String rk = retKey(fn)
    if fname == "main" { rk = "Int" }
    sc.retKind = rk
    sc.directRet = false
    sc.params = []
    sc.paramTypes = []
    N ps = fld(fn, "Params")
    Int pi = 0
    while pi < ps.el.length() {
        sc.params.push(unq(txt(fld(ps.el.get(pi), "Name"))))
        if !inNames(sc.own, unq(txt(fld(ps.el.get(pi), "Name")))) { sc.own.push(unq(txt(fld(ps.el.get(pi), "Name")))) }
        sc.paramTypes.push(typeKey(fld(ps.el.get(pi), "Type")))
        pi = pi + 1
    }
    sc.defers = []
    sc.escaped = []
    sc.names = []
    sc.types = []
    sc.own = []
    sc.blockHeld = []
    sc.returned = false
    sc.sid = -1
    sc.parentId = -1
    escBlock(fld(fn, "Body"), sc)
    String outName = "xn_" + fname + FN_SUFFIX
    sc.curFn = fname
    e.add(cType(rk) + " " + outName + "(" + paramsOf(fn) + ") {")
    if isResult(rk) {
        e.add("    " + cType(rk) + " xn_ret;")
        sc.useResult(rk)
    }
    String root = e.nt()
    sc.rootMark = root
    sc.rootPrelude = []
    sc.hasResult = isResult(rk)
    sc.rootDeclared = true
    e.add("size_t " + root + " = xn_root_mark();")
    addDefer(sc, ["xn_root_restore(" + root + ");"], false)
    N ps2 = fld(fn, "Params")
    Int pj = 0
    while pj < ps2.el.length() {
        String pty = typeKey(fld(ps2.el.get(pj), "Type"))
        String pnm = unq(txt(fld(ps2.el.get(pj), "Name")))
        String pct = cType(pty)
        if pct.length() > 0 && pct.substring(pct.length() - 1, 1) == "*" {
            Bool needRoot = true
            if baseCls(pty) != "" && classPolicy(baseCls(pty)) != "gc" { needRoot = false }
            if needRoot { e.raw("xn_root_add(xn_p_" + pnm + ");") }
        }
        pj = pj + 1
    }
    emitBlock(fld(fn, "Body"), e, sc, 0, false)
    if isResult(rk) && !sc.returned {
        String vz = "0"
        String vct = cType(resultVal(rk))
        if vct.length() > 0 && vct.substring(vct.length() - 1, 1) == "*" { vz = "NULL" }
        String ez0 = "0"
        String ect0 = cType(resultErr(rk))
        if ect0.length() > 0 && ect0.substring(ect0.length() - 1, 1) == "*" { ez0 = "NULL" }
        e.add("return (" + cType(rk) + "){0, " + vz + ", " + ez0 + "};")
    }
    e.add("}")
    e.add("")
}


static String joinLines(List<String> xs) {
    String b = ""
    Int i = 0
    while i < xs.length() { b = b + xs.get(i) + "\n"; i = i + 1 }
    return b
}

static String fbComment(String rt) {
    if rt.length() > 0 && rt.substring(rt.length() - 1, 1) == "?" { return " /* sema 保证不可达 */" }
    return " /* sema 保证不可达（函数体全路径 return） */"
}
static String zeroOf(String cty) {
    if cty.length() > 0 && cty.substring(cty.length() - 1, 1) == "*" { return "(" + cty + ")0" }
    if cty == "int64_t" || cty == "int32_t" || cty == "int" || cty == "double" || cty == "float" { return "(" + cty + ")0" }
    if cty.indexOf("xn_Enum_") == 0 { return "(" + cty + ")0" }
    return "(" + cty + "){0}"
}
static String stripOuter(String x) {
    if x.length() >= 2 && x.substring(0, 1) == "(" && x.substring(x.length() - 1, 1) == ")" {
        return x.substring(1, x.length() - 2)
    }
    return x
}

static String ctorParams(N cls) { return paramsOf(ctorOf(cls)) }
static String newParamDecls(N cls) {
    String cp = ctorParams(cls)
    if cp != "" { return cp }
    if fld(cls, "Ctors").el.length() > 0 { return "" }
    return "void"
}
static String ctorArgs(N cls) {
    N d = ctorOf(cls)
    N ps = fld(d, "Params")
    String b = ""
    Int i = 0
    while i < ps.el.length() {
        if i > 0 { b = b + ", " }
        b = b + "xn_p_" + unq(txt(fld(ps.el.get(i), "Name")))
        i = i + 1
    }
    return b
}

static void emitClassForwards(N cls, List<String> dst, Int dummy) {
    String cn = unq(txt(fld(cls, "Name")))
    if CLS_OVERRIDE != "" { cn = CLS_OVERRIDE }
    dst.push("typedef struct xn_Cls_" + cn + " xn_Cls_" + cn + ";")
    dst.push("")
    dst.push("typedef struct xn_Cls_" + cn + " xn_Cls_" + cn + ";")
    dst.push("")
    String sfx = ""
    if isPrimary(cls) { sfx = "_1" }
    String np = newParamDecls(cls)
    dst.push("static xn_Cls_" + cn + " *xn_Cls_" + cn + "_new" + sfx + "(" + np + ");")
    dst.push("static void xn_Cls_" + cn + "_new" + sfx + "_init" + "(xn_Cls_" + cn + " *o" + (ctorParams(cls) == "" ? "" : ", " + ctorParams(cls)) + ");")
    if hasDeinit(cn) { dst.push("static void xn_Cls_" + cn + "_deinit(xn_Cls_" + cn + " *self);") }
    if hasProto(cn) { dst.push("static void *xn_vt_" + cn + "[" + str(protoSlots(cn) + 2) + "];") }
    dst.push("")
    dst.push("")
}

static String retKey(N fn) {
    if txt(fld(fn, "Void")) == "true" { return "void" }
    return typeKey(fld(fn, "Ret"))
}

static String clsMethRet(N m) {
    return retKey(m)
}
static String clsMethSig(N m, String cn) {
    Bool stat = isStaticM(m)
    String sig = "xn_Cls_" + cn + "_" + unq(txt(fld(m, "Name"))) + "("
    N mps = fld(m, "Params")
    Int mj = 0
    if !stat { sig = sig + "xn_Cls_" + cn + " *self" }
    while mj < mps.el.length() {
        String mt = typeKey(fld(mps.el.get(mj), "Type"))
        if !stat || mj > 0 { sig = sig + ", " }
        sig = sig + cType(mt) + " xn_p_" + unq(txt(fld(mps.el.get(mj), "Name")))
        mj = mj + 1
    }
    return sig + ")"
}

static void emitClassSection(N cls, EM ce) {
    String cn = unq(txt(fld(cls, "Name")))
    if CLS_OVERRIDE != "" { cn = CLS_OVERRIDE }
    Bool ref = classPolicy(cn) == "gc"
    N fs = fld(cls, "Fields")
    N ms = fld(cls, "Methods")
    N cs = fld(cls, "Ctors")
    Bool primary = isPrimary(cls)
    String sfx = ""
    if primary { sfx = "_1" }
    ce.add("/* 类 " + unq(txt(fld(cls, "Name"))) + "（M4.4b） */")
    ce.add("typedef struct xn_Cls_" + cn + " {")
    ce.add("    rt_header hdr;")
    if hasProto(cn) { ce.add("    void **__vtable; /* 协议 vtable 槽（S2 §5.7；派发批次填充） */") }
    Int i = 0
    if primary {
        N pps = fld(ctorOf(cls), "Params")
        i = pps.el.length() - 1
        while i >= 0 {
            ce.add("    " + cType(typeKey(fld(pps.el.get(i), "Type"))) + " " + unq(txt(fld(pps.el.get(i), "Name"))) + ";")
            i = i - 1
        }
    } else {
        List<String> chain = []
        String cur = unq(txt(fld(cls, "Name")))
        while cur != "" { chain.insert(0, cur); cur = baseOf(cur) }
        Int ci2 = 0
        while ci2 < chain.length() {
            String own = chain.get(ci2)
            N ofs = fld(classByName(own), "Fields")
            Int oi = 0
            while oi < ofs.el.length() {
                ce.add("    " + cType(typeKey(fld(ofs.el.get(oi), "Type"))) + " " + fieldCName(ofs.el.get(oi)) + ";")
                oi = oi + 1
            }
            ci2 = ci2 + 1
        }
    }
    ce.add("} xn_Cls_" + cn + ";")
    ce.raw("")
    ce.add("static void xn_Cls_" + cn + "_deinit_hook(void *p) {")
    ce.add("    xn_Cls_" + cn + " *o = (xn_Cls_" + cn + " *)p;")
    if hasDeinit(cn) { ce.add("    xn_Cls_" + cn + "_deinit(o);") }
    i = 0
    while i < fs.el.length() {
        String dft = typeKey(fld(fs.el.get(i), "Type"))
        String dfn = fieldCName(fs.el.get(i))
        if dft == "String" { ce.add("    rt_release(o->" + dfn + ");") }
        else if baseCls(dft) != "" && classPolicy(baseCls(dft)) == "arc" { ce.add("    rt_release(o->" + dfn + ");") }
        i = i + 1
    }
    ce.add("}")
    ce.raw("")
    if ref {
        ce.add("static void xn_Cls_" + cn + "_gc_scan(void *p, void (*visit)(void *)) {")
        ce.add("    xn_Cls_" + cn + " *o = (xn_Cls_" + cn + " *)p;")
        i = 0
        while i < fs.el.length() {
            String sft = typeKey(fld(fs.el.get(i), "Type"))
            String sfn = fieldCName(fs.el.get(i))
            if sft == "String" || fieldIsGC(sft) || baseCls(sft) != "" { ce.add("    if (o->" + sfn + ") { visit(o->" + sfn + "); }") }
            i = i + 1
        }
        ce.add("}")
        ce.raw("")
    }
    ce.add("static const rt_type RT_TYPE_XN_" + cn + " = { \"" + unq(txt(fld(cls, "Name"))) + "\", sizeof(xn_Cls_" + cn + "), xn_Cls_" + cn + "_deinit_hook, " + (ref ? "xn_Cls_" + cn + "_gc_scan" : "NULL") + " };")
    ce.raw("")
    // new_init
    ce.add("static void xn_Cls_" + cn + "_new" + sfx + "_init" + "(xn_Cls_" + cn + " *o" + (ctorParams(cls) == "" ? "" : ", " + ctorParams(cls)) + ") {")
    String bcn = baseOf(cn)
    if bcn != "" && !primary { ce.add("    xn_Cls_" + bcn + "_new_init((xn_Cls_" + bcn + " *)o);") }
    if primary {
        N pps = fld(ctorOf(cls), "Params")
        Int pi2 = 0
        while pi2 < pps.el.length() {
            String pn = unq(txt(fld(pps.el.get(pi2), "Name")))
            ce.add("    o->" + pn + " = xn_p_" + pn + ";")
            pi2 = pi2 + 1
        }
        ce.add("}")
        ce.raw("")
        ce.add("static xn_Cls_" + cn + " *xn_Cls_" + cn + "_new_1(" + ctorParams(cls) + ") {")
        ce.add("    xn_Cls_" + cn + " *o = (xn_Cls_" + cn + " *)" + ((ref && !isGenInstCls(cn)) ? "xn_gc_new" : "rt_arc_new") + "(&RT_TYPE_XN_" + cn + ");")
        ce.add("    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_" + cn + ") - sizeof(rt_header));")
        if hasProto(cn) { ce.add("    o->__vtable = xn_vt_" + cn + ";") }
        String pa = ctorArgs(cls)
        if pa == "" { ce.add("    xn_Cls_" + cn + "_new_1_init(o);") } else { ce.add("    xn_Cls_" + cn + "_new_1_init(o, " + pa + ");") }
        ce.add("    return o;")
        ce.add("}")
        ce.raw("")
        ce.tmp = ce.tmp + 1
        // methods below
        i = 0
        while i < ms.el.length() {
            N m = ms.el.get(i)
            String mn = unq(txt(fld(m, "Name")))
            String rt = retKey(m)
            N mps = fld(m, "Params")
            String sig = "xn_Cls_" + cn + "_" + mn + "(xn_Cls_" + cn + " *self"
            Int mj = 0
            while mj < mps.el.length() {
                String mt = typeKey(fld(mps.el.get(mj), "Type"))
                sig = sig + ", " + decl(cType(mt), "xn_p_" + unq(txt(fld(mps.el.get(mj), "Name"))))
                mj = mj + 1
            }
            sig = sig + ")"
            ce.add("static " + cType(rt) + " " + sig + ";")
            ce.raw("")
            ce.add("static " + cType(rt) + " " + sig + " {")
            SC msc = new SC()
            msc.selfName = "self"
            msc.curClass = cn
            msc.def("self", cn)
            msc.retKind = rt
            msc.hasResult = isResult(rt)
            if isResult(rt) { ce.add("    " + cType(rt) + " xn_ret;"); msc.useResult(rt) }
            String mr = ce.nt()
            msc.rootMark = mr
            msc.rootDeclared = true
            ce.add("size_t " + mr + " = xn_root_mark();")
            addDefer(msc, ["xn_root_restore(" + mr + ");"], false)
            emitBlock(fld(m, "Body"), ce, msc, 0, false)
            if rt != "void" && !isResult(rt) { ce.add("    return " + zeroOf(cType(rt)) + ";" + fbComment(rt)) }
            ce.add("}")
            ce.raw("")
            i = i + 1
        }
        return
    }
    i = 0
    while i < fs.el.length() {
        String ft = typeKey(fld(fs.el.get(i), "Type"))
        String fn = fieldCName(fs.el.get(i))
        N init = fld(fs.el.get(i), "Init")
        if init.nm == "" || init.nm == "nil" { i = i + 1; continue }
        if ft == "String" {
            String text = ""
            if init.nm == "StrLitExpr" {
                N parts = fld(init, "Parts")
                if parts.el.length() > 0 { text = unq(txt(fld(parts.el.get(0), "Text"))) }
            }
            String t = ce.nt()
            ce.addAt(4, "rt_string *" + t + " = rt_string_from_c(" + q(text) + ");")
            ce.addAt(4, "rt_release((void *)o->" + fn + ");")
            ce.addAt(4, "o->" + fn + " = " + t + ";")
        } else if isArr(ft) || isObjArr(ft) {
            N elems = fld(init, "Elems")
            String t = ce.nt()
            String an = classArrName(ft)
            if isArr(ft) { an = arrNameC(cType(arrElem(ft))) }
            ce.add("    " + cType(ft) + t + " = " + an + "_new(" + str(elems.el.length()) + ");")
            Int ei = 0
            while ei < elems.el.length() { ce.add("    " + an + "_push(" + t + ", " + expr(elems.el.get(ei), ce, new SC()) + ");"); ei = ei + 1 }
            ce.add("    o->" + fn + " = " + t + ";")
        } else {
            String dv = "0"
            if init.nm == "IntLitExpr" { dv = expr(init, ce, new SC()) }
            else if init.nm == "BoolLit" { dv = expr(init, ce, new SC()) }
            ce.add("    o->" + fn + " = " + dv + ";")
        }
        i = i + 1
    }
    Bool hasCtor = fld(cls, "Ctors").el.length() > 0 || isPrimary(cls)
    String root = ""
    if hasCtor {
        root = ce.nt()
        ce.add("size_t " + root + " = xn_root_mark();")
        if ref && !isGenInstCls(cn) { ce.raw("xn_root_add(o);") }
    }
    N ps = fld(cls, "Params")
    N cps = fld(ctorOf(cls), "Params")
    Int pj = 0
    while pj < cps.el.length() {
        String pt = typeKey(fld(cps.el.get(pj), "Type"))
        Bool proot = cType(pt).length() > 0 && cType(pt).substring(cType(pt).length() - 1, 1) == "*"
        if isProtoType(stripQ(pt)) { proot = true }
        if proot { ce.raw("xn_root_add(xn_p_" + unq(txt(fld(cps.el.get(pj), "Name"))) + ");") }
        pj = pj + 1
    }
    N ctor = ctorOf(cls)
    SC csc = new SC()
    csc.selfName = "o"
    csc.def("self", cn)
    csc.retKind = "Int"
    csc.isCtor = true
    csc.hasResult = false
    csc.rootMark = root
    csc.rootDeclared = true
    if hasCtor { addDefer(csc, ["xn_root_restore(" + root + ");"], false) }
    csc.params = []
    csc.paramTypes = []
    Int cpj = 0
    while cpj < cps.el.length() {
        csc.params.push(unq(txt(fld(cps.el.get(cpj), "Name"))))
        csc.paramTypes.push(typeKey(fld(cps.el.get(cpj), "Type")))
        cpj = cpj + 1
    }
    if hasCtor {
        if ctor.nm == "CtorDecl" { emitBlock(fld(ctor, "Body"), ce, csc, 0, false) }
    }
    ce.add("}")
    ce.raw("")
    // new
    String np2 = newParamDecls(cls)
    ce.add("static xn_Cls_" + cn + " *xn_Cls_" + cn + "_new" + sfx + "(" + np2 + ") {")
    ce.add("    xn_Cls_" + cn + " *o = (xn_Cls_" + cn + " *)" + ((ref && !isGenInstCls(cn)) ? "xn_gc_new" : "rt_arc_new") + "(&RT_TYPE_XN_" + cn + ");")
    ce.add("    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_" + cn + ") - sizeof(rt_header));")
    if hasProto(cn) { ce.add("    o->__vtable = xn_vt_" + cn + ";") }
    String cargs = ctorArgs(cls)
    if cargs == "" { ce.add("    xn_Cls_" + cn + "_new" + sfx + "_init" + "(o);") }
    else { ce.add("    xn_Cls_" + cn + "_new_init(o, " + cargs + ");") }
    ce.add("    return o;")
    ce.add("}")
    ce.raw("")
    if ms.el.length() == 0 { ce.raw("") }
    // methods: 先全部原型，再逐个函数体（与 Go 两遍发射一致）
    i = 0
    while i < ms.el.length() {
        N m = ms.el.get(i)
        ce.add("static " + cType(clsMethRet(m)) + " " + clsMethSig(m, cn) + ";")
        i = i + 1
    }
    if ms.el.length() > 0 { ce.raw("") }
    i = 0
    while i < ms.el.length() {
        N m = ms.el.get(i)
        String mn = unq(txt(fld(m, "Name")))
        String rt = clsMethRet(m)
        Bool stat = isStaticM(m)
        String sig = clsMethSig(m, cn)
        ce.add("static " + cType(rt) + " " + sig + " {")
        N mps = fld(m, "Params")
        Int mj = 0
        SC msc = new SC()
        msc.selfName = "self"
        if !stat { msc.curClass = cn }
        msc.staticMeth = stat
        if !stat { msc.def("self", cn) }
        msc.retKind = rt
        msc.hasResult = isResult(rt)
        msc.params = []
        msc.paramTypes = []
        mj = 0
        while mj < mps.el.length() {
            msc.params.push(unq(txt(fld(mps.el.get(mj), "Name"))))
            if !inNames(msc.own, unq(txt(fld(mps.el.get(mj), "Name")))) { msc.own.push(unq(txt(fld(mps.el.get(mj), "Name")))) }
            msc.paramTypes.push(typeKey(fld(mps.el.get(mj), "Type")))
            mj = mj + 1
        }
        if isResult(rt) { ce.add("    " + cType(rt) + " xn_ret;"); msc.useResult(rt) }
        String mr = ce.nt()
        msc.rootMark = mr
        msc.rootDeclared = true
        ce.add("size_t " + mr + " = xn_root_mark();")
        addDefer(msc, ["xn_root_restore(" + mr + ");"], false)
        if ref && !stat && !inNames(GEN_INST_NAME, cn) { ce.raw("xn_root_add(self);") }
        mj = 0
        while mj < mps.el.length() {
            String pt0 = typeKey(fld(mps.el.get(mj), "Type"))
            Bool proot0 = (cType(pt0).length() > 0 && cType(pt0).substring(cType(pt0).length() - 1, 1) == "*")
            if isProtoType(stripQ(pt0)) { proot0 = true }
            if proot0 { ce.raw("xn_root_add(xn_p_" + unq(txt(fld(mps.el.get(mj), "Name"))) + ");") }
            mj = mj + 1
        }
        emitBlock(fld(m, "Body"), ce, msc, 0, false)
        if rt != "void" && !msc.hasResult { ce.add("    return " + zeroOf(cType(rt)) + ";" + fbComment(rt)) }
        ce.add("}")
        ce.raw("")
        i = i + 1
    }
}

static Bool isStaticM(N m) {
    N md = fld(m, "Mod")
    if md.nm == "" || md.nm == "nil" { return false }
    return txt(fld(md, "Static")) == "true"
}

static Bool isPrimaryName(String cn) {
    Int i = 0
    while i < PRIMARY_NAMES.length() {
        if PRIMARY_NAMES.get(i) == cn { return true }
        i = i + 1
    }
    return false
}
static Bool isPrimary(N cls) {
    N p = fld(cls, "Primary")
    return p.nm != "" && p.nm != "nil"
}
static N ctorOf(N cls) {
    N cs = fld(cls, "Ctors")
    if cs.el.length() > 0 { return cs.el.get(0) }
    if isPrimary(cls) { return fld(cls, "Primary") }
    return new N()
}


static void emitStructEarly(N st, EM ce) {
    String sn = unq(txt(fld(st, "Name")))
    N fs = fld(st, "Fields")
    N ctor = ctorOf(st)
    ce.add("typedef struct xn_Struct_" + sn + " {")
    Int i = 0
    while i < fs.el.length() {
        ce.add("    " + cType(typeKey(fld(fs.el.get(i), "Type"))) + " " + unq(txt(fld(fs.el.get(i), "Name"))) + ";")
        i = i + 1
    }
    ce.add("} xn_Struct_" + sn + ";")
    ce.raw("")
    String sp0 = ctorParams(st)
    if sp0 == "" { sp0 = "void" }
    ce.add("static xn_Struct_" + sn + " xn_Struct_" + sn + "_new(" + sp0 + ") {")
    ce.add("    xn_Struct_" + sn + " self = (xn_Struct_" + sn + "){0};")
    i = 0
    while i < fs.el.length() {
        String fn = unq(txt(fld(fs.el.get(i), "Name")))
        ce.add("    self." + fn + " = 0;")
        i = i + 1
    }
    SC csc = new SC()
    csc.selfName = "self"
    csc.selfPtr = false
    csc.def("self", sn)
    csc.params = []
    N cps = fld(ctor, "Params")
    Int cpj = 0
    while cpj < cps.el.length() { csc.params.push(unq(txt(fld(cps.el.get(cpj), "Name")))); cpj = cpj + 1 }
    if ctor.nm == "CtorDecl" { emitBlock(fld(ctor, "Body"), ce, csc, 0, false) }
    ce.add("    return self;")
    ce.add("}")
    ce.raw("")
}

static void emitStructMethods(N st, EM ce) {
    String sn = unq(txt(fld(st, "Name")))
    N ms = fld(st, "Methods")
    Int i = 0
    while i < ms.el.length() {
        N m = ms.el.get(i)
        String mn = unq(txt(fld(m, "Name")))
        String rt = retKey(m)
        N mps = fld(m, "Params")
        String sig = "xn_Struct_" + sn + "_" + mn + "(xn_Struct_" + sn + " *self"
        Int mj = 0
        while mj < mps.el.length() {
            String mt = typeKey(fld(mps.el.get(mj), "Type"))
            sig = sig + ", " + decl(cType(mt), "xn_p_" + unq(txt(fld(mps.el.get(mj), "Name"))))
            mj = mj + 1
        }
        sig = sig + ")"
        ce.add("static " + cType(rt) + " " + sig + ";")
        ce.raw("")
        ce.add("static " + cType(rt) + " " + sig + " {")
        SC msc = new SC()
        msc.selfName = "self"
        msc.selfPtr = true
        msc.curClass = sn
        msc.def("self", sn)
        msc.retKind = rt
        msc.hasResult = isResult(rt)
        if isResult(rt) { ce.add("    " + cType(rt) + " xn_ret;"); msc.useResult(rt) }
        msc.params = []
        msc.paramTypes = []
        mj = 0
        while mj < mps.el.length() {
            msc.params.push(unq(txt(fld(mps.el.get(mj), "Name"))))
            if !inNames(msc.own, unq(txt(fld(mps.el.get(mj), "Name")))) { msc.own.push(unq(txt(fld(mps.el.get(mj), "Name")))) }
            msc.paramTypes.push(typeKey(fld(mps.el.get(mj), "Type")))
            mj = mj + 1
        }
        String mr = ce.nt()
        msc.rootMark = mr
        emitBlock(fld(m, "Body"), ce, msc, 0, false)
        if rt != "void" && !msc.hasResult { ce.add("    return " + zeroOf(cType(rt)) + ";" + fbComment(rt)) }
        ce.add("}")
        ce.raw("")
        i = i + 1
    }
}

static String protoTypedefs() {
    String b = ""
    Int i = 0
    while i < PROTO_OWNER.length() {
        String pn = PROTO_OWNER.get(i)
        Bool seen = false
        Int j = 0
        while j < i { if PROTO_OWNER.get(j) == pn { seen = true }; j = j + 1 }
        if !seen && pn != "Error" { b = b + "typedef void *xn_proto_" + pn + ";\n" }
        i = i + 1
    }
    return b
}

static void emitExtensionMethods(N ext, EM ce) {
    N ems = fld(ext, "Methods")
    Int i = 0
    String et = typeKey(fld(ext, "Target"))
    while i < ems.el.length() {
        N m = ems.el.get(i)
        String mn = unq(txt(fld(m, "Name")))
        String rt = retKey(m)
        String cn = "xn_Cls_" + et + "_ext_" + mn + "_" + str(i + 1)
        ce.add("static " + cType(rt) + " " + cn + "(xn_Cls_" + et + " *self) {")
        SC msc = new SC()
        msc.selfName = "self"
        msc.curClass = et
        msc.def("self", et)
        msc.retKind = rt
        msc.hasResult = isResult(rt)
        if isResult(rt) { ce.add("    " + cType(rt) + " xn_ret;"); msc.useResult(rt) }
        String mr = ce.nt()
        msc.rootMark = mr
        msc.rootPrelude = ["xn_root_add(self);"]
        emitBlock(fld(m, "Body"), ce, msc, 0, false)
        if rt != "void" && !msc.hasResult { ce.add("    return " + zeroOf(cType(rt)) + ";" + fbComment(rt)) }
        ce.add("}")
        ce.raw("")
        i = i + 1
    }
}

static void emitFactoryMethods(N fac, EM ce) {
    String fn = unq(txt(fld(fac, "Name")))
    N ms = fld(fac, "Methods")
    Int i = 0
    while i < ms.el.length() {
        N m = ms.el.get(i)
        String mn = unq(txt(fld(m, "Name")))
        String rt = retKey(m)
        N mps = fld(m, "Params")
        String sig = "xn_Factory_" + fn + "_" + mn + "("
        Int mj = 0
        while mj < mps.el.length() {
            if mj > 0 { sig = sig + ", " }
            sig = sig + paramDecl(cType(typeKey(fld(mps.el.get(mj), "Type"))), "xn_p_" + unq(txt(fld(mps.el.get(mj), "Name"))))
            mj = mj + 1
        }
        sig = sig + ")"
        ce.add(cType(rt) + " " + sig + " {")
        SC fsc = new SC()
        fsc.retKind = rt
        fsc.hasResult = isResult(rt)
        if isResult(rt) { ce.add("    " + cType(rt) + " xn_ret;"); fsc.useResult(rt) }
        fsc.params = []
        fsc.paramTypes = []
        mj = 0
        while mj < mps.el.length() {
            fsc.params.push(unq(txt(fld(mps.el.get(mj), "Name"))))
            fsc.paramTypes.push(typeKey(fld(mps.el.get(mj), "Type")))
            mj = mj + 1
        }
        fsc.rootPrelude = []
        mj = 0
        while mj < mps.el.length() {
            String pt = typeKey(fld(mps.el.get(mj), "Type"))
            if cType(pt).length() > 0 && cType(pt).substring(cType(pt).length() - 1, 1) == "*" { fsc.rootPrelude.push("xn_root_add(xn_p_" + unq(txt(fld(mps.el.get(mj), "Name"))) + ");") }
            mj = mj + 1
        }
        String r = ce.nt()
        fsc.rootMark = r
        emitBlock(fld(m, "Body"), ce, fsc, 0, false)
        ce.add("}")
        ce.raw("")
        i = i + 1
    }
}


static void emitDataEnum(N de, EM e) {
    String en = unq(txt(fld(de, "Name")))
    N fs = fld(de, "Fields")
    N its = fld(de, "Items")
    N ctor = ctorOf(de)
    Bool ref = false
    Int i = 0
    while i < fs.el.length() { if typeKey(fld(fs.el.get(i), "Type")) == "String" { ref = true }; i = i + 1 }
    e.add("/* 类 " + en + "（M4.4b） */")
    e.add("typedef struct xn_Enum_" + en + " {")
    e.add("    rt_header hdr;")
    i = 0
    while i < fs.el.length() {
        e.add("    " + cType(typeKey(fld(fs.el.get(i), "Type"))) + " " + unq(txt(fld(fs.el.get(i), "Name"))) + ";")
        i = i + 1
    }
    e.add("} xn_Enum_" + en + ";")
    e.raw("")
    e.add("static void xn_Enum_" + en + "_deinit_hook(void *p) {")
    e.add("    xn_Enum_" + en + " *o = (xn_Enum_" + en + " *)p;")
    i = 0
    while i < fs.el.length() { if typeKey(fld(fs.el.get(i), "Type")) == "String" { e.add("    rt_release(o->" + unq(txt(fld(fs.el.get(i), "Name"))) + ");") }; i = i + 1 }
    e.add("}")
    e.raw("")
    if ref {
        e.add("static void xn_Enum_" + en + "_gc_scan(void *p, void (*visit)(void *)) {")
        e.add("    xn_Enum_" + en + " *o = (xn_Enum_" + en + " *)p;")
        i = 0
        while i < fs.el.length() { if typeKey(fld(fs.el.get(i), "Type")) == "String" { e.add("    if (o->" + unq(txt(fld(fs.el.get(i), "Name"))) + ") { visit(o->" + unq(txt(fld(fs.el.get(i), "Name"))) + "); }") }; i = i + 1 }
        e.add("}")
        e.raw("")
    }
    e.add("static const rt_type RT_TYPE_XN_ENUM_" + en + " = { \"" + en + "\", sizeof(xn_Enum_" + en + "), xn_Enum_" + en + "_deinit_hook, " + (ref ? "xn_Enum_" + en + "_gc_scan" : "NULL") + " };")
    e.raw("")
    e.add("static void xn_Enum_" + en + "_new_init(xn_Enum_" + en + " *o" + (ctorParams(de) == "" ? "" : ", " + ctorParams(de)) + ") {")
    String rt = e.nt()
    SC csc = new SC()
    csc.selfName = "o"
    csc.def("self", en)
    csc.isCtor = true
    csc.hasResult = false
    csc.rootMark = rt
    csc.rootPrelude = ["xn_root_add(o);"]
    csc.params = []
    csc.paramTypes = []
    N cps0 = fld(ctor, "Params")
    Int cp0 = 0
    while cp0 < cps0.el.length() {
        csc.params.push(unq(txt(fld(cps0.el.get(cp0), "Name"))))
        csc.paramTypes.push(typeKey(fld(cps0.el.get(cp0), "Type")))
        cp0 = cp0 + 1
    }
    String pa = ctorArgs(de)
    if ctor.nm == "CtorDecl" { emitBlock(fld(ctor, "Body"), e, csc, 0, false) }
    e.add("}")
    e.raw("")
    e.add("static xn_Enum_" + en + " *xn_Enum_" + en + "_new(" + ctorParams(de) + ") {")
    e.add("    xn_Enum_" + en + " *o = (xn_Enum_" + en + " *)xn_gc_new(&RT_TYPE_XN_ENUM_" + en + ");")
    e.add("    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Enum_" + en + ") - sizeof(rt_header));")
    if pa == "" { e.add("    xn_Enum_" + en + "_new_init(o);") } else { e.add("    xn_Enum_" + en + "_new_init(o, " + pa + ");") }
    e.add("    return o;")
    e.add("}")
    e.raw("")
    i = 0
    while i < its.el.length() {
        e.add("static xn_Enum_" + en + " * xn_enum_" + en + "_" + unq(txt(fld(its.el.get(i), "Name"))) + ";")
        i = i + 1
    }
    e.add("static rt_string *xn_enum_" + en + "_name(xn_Enum_" + en + " * v) {")
    i = 0
    while i < its.el.length() {
        e.add("    if (v == xn_enum_" + en + "_" + unq(txt(fld(its.el.get(i), "Name"))) + ") { return rt_string_from_c(\"" + unq(txt(fld(its.el.get(i), "Name"))) + "\"); }")
        i = i + 1
    }
    e.add("    return rt_string_from_c(\"null\");")
    e.add("}")
    e.raw("")
}

static void emitDataEnumMethods(N de, EM e) {
    String en = unq(txt(fld(de, "Name")))
    N ms = fld(de, "Methods")
    Int i = 0
    while i < ms.el.length() {
        N m = ms.el.get(i)
        String mn = unq(txt(fld(m, "Name")))
        String rt = retKey(m)
        e.add("static " + cType(rt) + " xn_Enum_" + en + "_" + mn + "(xn_Enum_" + en + " *self);")
        e.raw("")
        e.add("static " + cType(rt) + " xn_Enum_" + en + "_" + mn + "(xn_Enum_" + en + " *self) {")
        SC msc = new SC()
        msc.selfName = "self"
        msc.curClass = en
        msc.def("self", en)
        msc.retKind = rt
        msc.hasResult = isResult(rt)
        if isResult(rt) { e.add("    " + cType(rt) + " xn_ret;"); msc.useResult(rt) }
        String r = e.nt()
        msc.rootMark = r
        msc.rootPrelude = ["xn_root_add(self);"]
        emitBlock(fld(m, "Body"), e, msc, 0, false)
        if rt != "void" && !msc.hasResult { e.add("    return " + zeroOf(cType(rt)) + ";" + fbComment(rt)) }
        e.add("}")
        e.raw("")
        i = i + 1
    }
}

static String dataEnumInit() {
    String b = ""
    Int i = 0
    while i < DATA_ENUM_DECLS.length() {
        N de = DATA_ENUM_DECLS.get(i)
        String en = unq(txt(fld(de, "Name")))
        N its = fld(de, "Items")
        String pa = ctorArgs(de)
        Int j = 0
        while j < its.el.length() {
            String item = unq(txt(fld(its.el.get(j), "Name")))
            String args = ""
            N ia = fld(its.el.get(j), "Args")
            Int k = 0
            while k < ia.el.length() { if k > 0 { args = args + ", " }; args = args + expr(ia.el.get(k), new EM(), new SC()); k = k + 1 }
            b = b + "    xn_enum_" + en + "_" + item + " = xn_Enum_" + en + "_new(" + args + ");\n"
            b = b + "    xn_root_hold(xn_enum_" + en + "_" + item + ");\n"
            j = j + 1
        }
        i = i + 1
    }
    return b
}

static void emitSingletonSection(N sg, EM ce) {
    String sn = unq(txt(fld(sg, "Name")))
    N fs = fld(sg, "Fields")
    N ms = fld(sg, "Methods")
    Bool ref = hasRefFields(sn)
    ce.add("/* 类 " + sn + "（M4.4b） */")
    ce.add("typedef struct xn_Single_" + sn + " {")
    ce.add("    rt_header hdr;")
    Int i = 0
    while i < fs.el.length() {
        String ft = typeKey(fld(fs.el.get(i), "Type"))
        ce.add("    " + cType(ft) + " " + unq(txt(fld(fs.el.get(i), "Name"))) + ";")
        i = i + 1
    }
    ce.add("} xn_Single_" + sn + ";")
    ce.raw("")
    ce.add("static void xn_Single_" + sn + "_deinit_hook(void *p) {")
    ce.add("    xn_Single_" + sn + " *o = (xn_Single_" + sn + " *)p;")
    i = 0
    while i < fs.el.length() {
        if typeKey(fld(fs.el.get(i), "Type")) == "String" { ce.add("    rt_release(o->" + unq(txt(fld(fs.el.get(i), "Name"))) + ");") }
        i = i + 1
    }
    ce.add("}")
    ce.raw("")
    if ref {
        ce.add("static void xn_Single_" + sn + "_gc_scan(void *p, void (*visit)(void *)) {")
        ce.add("    xn_Single_" + sn + " *o = (xn_Single_" + sn + " *)p;")
        i = 0
        while i < fs.el.length() {
            if typeKey(fld(fs.el.get(i), "Type")) == "String" { ce.add("    if (o->" + unq(txt(fld(fs.el.get(i), "Name"))) + ") { visit(o->" + unq(txt(fld(fs.el.get(i), "Name"))) + "); }") }
            i = i + 1
        }
        ce.add("}")
        ce.raw("")
    }
    ce.add("static const rt_type RT_TYPE_XN_SINGLE_" + sn + " = { \"" + sn + "\", sizeof(xn_Single_" + sn + "), xn_Single_" + sn + "_deinit_hook, " + (ref ? "xn_Single_" + sn + "_gc_scan" : "NULL") + " };")
    ce.raw("")
    // methods
    i = 0
    while i < ms.el.length() {
        N m = ms.el.get(i)
        String mn = unq(txt(fld(m, "Name")))
        String rt = retKey(m)
        N mps = fld(m, "Params")
        String sig = "xn_Single_" + sn + "_" + mn + "(xn_Single_" + sn + " *self"
        Int mj = 0
        while mj < mps.el.length() {
            sig = sig + ", " + decl(cType(typeKey(fld(mps.el.get(mj), "Type"))), "xn_p_" + unq(txt(fld(mps.el.get(mj), "Name"))))
            mj = mj + 1
        }
        sig = sig + ")"
        ce.add("static " + cType(rt) + " " + sig + " {")
        SC msc = new SC()
        msc.selfName = "self"
        msc.def("self", sn)
        msc.retKind = rt
        msc.hasResult = isResult(rt)
        if isResult(rt) { ce.add("    " + cType(rt) + " xn_ret;"); msc.useResult(rt) }
        String mr = ce.nt()
        msc.rootMark = mr
        msc.rootPrelude = []
        if ref { msc.rootPrelude.push("xn_root_add(self);") }
        emitBlock(fld(m, "Body"), ce, msc, 0, false)
        if rt != "void" && !msc.hasResult { ce.add("    return " + zeroOf(cType(rt)) + ";" + fbComment(rt)) }
        ce.add("}")
        ce.raw("")
        i = i + 1
    }
    // init
    ce.add("static void xn_Single_" + sn + "_init(void) {")
    ce.add("    xn_Single_" + sn + " *o = (xn_Single_" + sn + " *)xn_gc_new(&RT_TYPE_XN_SINGLE_" + sn + ");")
    ce.add("    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Single_" + sn + ") - sizeof(rt_header));")
    i = 0
    while i < fs.el.length() {
        String ft = typeKey(fld(fs.el.get(i), "Type"))
        String fn = fieldCName(fs.el.get(i))
        N init = fld(fs.el.get(i), "Init")
        if init.nm == "" || init.nm == "nil" { i = i + 1; continue }
        if ft == "String" {
            String text = ""
            if init.nm == "StrLitExpr" {
                N parts = fld(init, "Parts")
                if parts.el.length() > 0 { text = unq(txt(fld(parts.el.get(0), "Text"))) }
            }
            String t = ce.nt()
            ce.add("    rt_string *" + t + " = rt_string_from_c(" + q(text) + ");")
            ce.add("    o->" + fn + " = " + t + ";")
        } else {
            String dv = "0"
            if init.nm == "IntLitExpr" { dv = expr(init, ce, new SC()) }
            ce.add("    o->" + fn + " = " + dv + ";")
        }
        i = i + 1
    }
    ce.add("    xn_single_" + sn + " = o;")
    ce.add("    xn_root_hold(xn_single_" + sn + ");")
    ce.add("}")
    ce.raw("")
}

static N dataEnumDecl(String en) {
    Int i = 0
    while i < DATA_ENUM_DECLS.length() {
        if unq(txt(fld(DATA_ENUM_DECLS.get(i), "Name"))) == en { return DATA_ENUM_DECLS.get(i) }
        i = i + 1
    }
    return new N()
}
static String enumTypedefs() {
    String b = ""
    Int i = 0
    while i < ENUM_NAMES.length() {
        String en = ENUM_NAMES.get(i)
        if !isDataEnum(en) && en != "ErrorKind" { b = b + "typedef int64_t xn_Enum_" + en + ";\n" }
        i = i + 1
    }
    return b
}
static String enumNameDefs() {
    String b = ""
    Int i = 0
    while i < ENUM_NAMES.length() {
        String en = ENUM_NAMES.get(i)
        if !isDataEnum(en) && en != "ErrorKind" {
            b = b + "static rt_string *xn_enum_" + en + "_name(int64_t v) {\n"
            b = b + "    switch (v) {\n"
            Int j = 0
            while j < ENUM_ITEM_OWNER.length() {
                if ENUM_ITEM_OWNER.get(j) == en {
                    b = b + "    case " + str(ENUM_ITEM_INDEX.get(j)) + ": return rt_string_from_c(\"" + ENUM_ITEM_NAME.get(j) + "\");\n"
                }
                j = j + 1
            }
            b = b + "    default: return xn_str_int(v);\n"
            b = b + "    }\n}\n\n"
        }
        i = i + 1
    }
    return b
}

static String vtableInit(N unit) {
    N decls = fld(unit, "Decls")
    String b = ""
    Int i = 0
    while i < decls.el.length() {
        N d = decls.el.get(i)
        if d.nm == "ClassDecl" {
            String cn = unq(txt(fld(d, "Name")))
            N bse = fld(d, "Base")
            if bse.nm != "" && bse.nm != "nil" {
                CLS_BASE_OWNER.push(cn)
                CLS_BASE_NAME.push(unq(txt(fld(bse, "Qual").el.get(0))))
            }
            N prs = fld(d, "Protocols")
            Int slot = 0
            Int pj = 0
            while pj < prs.el.length() {
                N ql = fld(prs.el.get(pj), "Qual")
                String pn = ""
                if ql.el.length() > 0 { pn = unq(txt(ql.el.get(ql.el.length() - 1))) }
                Int k = 0
                while k < PROTO_OWNER.length() {
                    if PROTO_OWNER.get(k) == pn {
                        b = b + "    xn_vt_" + cn + "[" + str(slot) + "] = (void *)&xn_Cls_" + cn + "_" + PROTO_MNAME.get(k) + ";\n"
                        slot = slot + 1
                    }
                    k = k + 1
                }
                pj = pj + 1
            }
        }
        i = i + 1
    }
    return b
}

static Bool isGenericFn(String n) {
    Int i = 0
    while i < GEN_FN_DECLS.length() { if unq(txt(fld(GEN_FN_DECLS.get(i), "Name"))) == n { return true }; i = i + 1 }
    return false
}
static String mangle(String k) {
    if k == "Int" { return "i" }
    if k == "String" { return "s" }
    if k == "Bool" { return "b" }
    if k == "Char" { return "c" }
    if k == "Double" || k == "Float" { return "d" }
    return "x"
}
static String instName(String fn, String args) {
    String b = ""
    Int i = 0
    while i < args.length() {
        String c = args.substring(i, 1)
        if c == "," { } else if c == " " { } else { b = b + c }
        i = i + 1
    }
    b = b.replace(",", "_")
    b = b.replace(" ", "")
    return b
}
static String instSuffix(String fn) {
    Int i = 0
    while i < INST_FN.length() {
        if INST_FN.get(i) == fn { return INST_ARGS.get(i) }
        i = i + 1
    }
    return ""
}
static N genFnDecl(String n) {
    Int i = 0
    while i < GEN_FN_DECLS.length() {
        if unq(txt(fld(GEN_FN_DECLS.get(i), "Name"))) == n { return GEN_FN_DECLS.get(i) }
        i = i + 1
    }
    return new N()
}
static void addInst(String fn, String args) {
    String sfx = "_" + mangle(args)
    String nm = "xn_" + fn + sfx
    Int j = 0
    while j < INST_NAME.length() { if INST_NAME.get(j) == nm { return }; j = j + 1 }
    INST_FN.push(fn)
    INST_NAME.push(nm)
    INST_ARGS.push(sfx)
    INST_KEYS.push(args)
}
static void scanCalls(N n) {
    if n.nm == "Call" {
        N ta = fld(n, "TypeArgs")
        if ta.el.length() > 0 {
            N cal = fld(n, "Callee")
            if cal.nm == "IdentExpr" {
                String fn = unq(txt(fld(cal, "Name")))
                if isGenericFn(fn) {
                    String args = ""
                    Int i = 0
                    while i < ta.el.length() { if i > 0 { args = args + "," }; args = args + typeKey(ta.el.get(i)); i = i + 1 }
                    addInst(fn, args)
                }
            }
        }
    }
    Int i = 0
    while i < n.fv.length() { scanCalls(n.fv.get(i)); i = i + 1 }
    i = 0
    while i < n.el.length() { scanCalls(n.el.get(i)); i = i + 1 }
}
static String tupleTypedefs() {
    String b = ""
    Int i = 0
    while i < TUPLE_KEYS.length() {
        String es = TUPLE_ELEMS.get(i)
        b = b + "typedef struct {\n"
        Int c = 0; Int fi = 0; Int dep = 0; String cur = ""
        while c <= es.length() {
            String ch = ""
            if c < es.length() { ch = es.substring(c, 1) }
            if ch == "<" { dep = dep + 1 }
            if ch == ">" { dep = dep - 1 }
            if c == es.length() || (ch == "," && dep == 0) {
                String ct = cur.trim()
                if ct != "" { b = b + "    " + cType(ct) + " f" + str(fi) + ";\n"; fi = fi + 1 }
                cur = ""
            } else { cur = cur + ch }
            c = c + 1
        }
        b = b + "} " + TUPLE_CN.get(i) + ";\n"
        i = i + 1
    }
    return b
}
static String genProtos() {
    String b = ""
    Int i = 0
    while i < INST_FN.length() {
        N fn = genFnDecl(INST_FN.get(i))
        SUB_FROM = ["T"]
        SUB_TO = [INST_KEYS.get(i)]
        String rt = retKey(fn)
        b = b + "static " + cType(rt) + " " + INST_NAME.get(i) + "(" + paramsOf(fn) + ");\n"
        i = i + 1
    }
    SUB_FROM = []
    SUB_TO = []
    return b
}
static void emitInstances(EM e, SC sc) {
    Int i = 0
    while i < INST_FN.length() {
        N fn = genFnDecl(INST_FN.get(i))
        SUB_FROM = ["T"]
        SUB_TO = [INST_KEYS.get(i)]
        FN_SUFFIX = INST_ARGS.get(i)
        emitFunc(fn, e, sc)
        FN_SUFFIX = ""
        SUB_FROM = []
        SUB_TO = []
        i = i + 1
    }
}

static Bool isTupList(String k) { return k.indexOf("List<Tuple<") == 0 }
static String tupleListElem(String k) {
    Int l = k.indexOf("<")
    Int r = k.length() - 1
    return k.substring(l + 1, r - l - 1).trim()
}
static String arrTupName(String k) {
    String ek = tupleListElem(k)
    String tc = cType(ek)
    return "xn_arr_t" + tc.substring(6, tc.length() - 6)
}
static Bool isTupleKey(String k) { return k.indexOf("Tuple<") == 0 }
static void addTuple(String key, String elems) {
    Int i = 0
    while i < TUPLE_KEYS.length() { if TUPLE_KEYS.get(i) == key { return }; i = i + 1 }
    TUPLE_KEYS.push(key)
    TUPLE_ELEMS.push(elems)
    TUPLE_CN.push(tupleCName(elems))
}
static String tupleCName(String elems) {
    String b = "xn_tup"
    Int i = 0
    Int dep = 0
    String cur = ""
    while i <= elems.length() {
        String c = ""
        if i < elems.length() { c = elems.substring(i, 1) }
        if c == "<" { dep = dep + 1 }
        if c == ">" { dep = dep - 1 }
        if i == elems.length() || (c == "," && dep == 0) {
            String e = cur.trim()
            if e != "" {
                b = b + "_"
                String ct = cType(e)
                Int j = 0
                while j < ct.length() {
                    String ch = ct.substring(j, 1)
                    if ch == " " || ch == "*" || ch == "(" || ch == ")" { b = b + "_" } else { b = b + ch }
                    j = j + 1
                }
            }
            cur = ""
        } else { cur = cur + c }
        i = i + 1
    }
    return b
}
static String tupleCN(String k) {
    Int i = 0
    while i < TUPLE_KEYS.length() { if TUPLE_KEYS.get(i) == k { return TUPLE_CN.get(i) }; i = i + 1 }
    return "xn_tup"
}
static String tupleElemAt(String k, Int idx) {
    String es = tupleInnerKeys(k)
    Int c = 0; String cur = ""
    while c <= es.length() {
        String ch = ""
        if c < es.length() { ch = es.substring(c, 1) }
        if c == es.length() || ch == "," {
            if idx == 0 { return cur.trim() }
            idx = idx - 1
            cur = ""
        } else { cur = cur + ch }
        c = c + 1
    }
    return "Int"
}
static String tupleInnerKeys(String k) {
    Int l = k.indexOf("<")
    if l < 0 { return "Int" }
    Int dep = 0
    Int i = l
    while i < k.length() {
        String c = k.substring(i, 1)
        if c == "<" { dep = dep + 1 }
        if c == ">" { dep = dep - 1; if dep == 0 { return k.substring(l + 1, i - l - 1).trim() } }
        i = i + 1
    }
    return "Int"
}
static String tupleElems(String k) {
    Int i = 0
    while i < TUPLE_KEYS.length() { if TUPLE_KEYS.get(i) == k { return TUPLE_ELEMS.get(i) }; i = i + 1 }
    return "int64_t"
}
static Bool isGenInstCls(String k) {
    Int i = 0
    while i < GEN_INST_NAME.length() { if GEN_INST_NAME.get(i) == k { return true }; i = i + 1 }
    return false
}
static Bool isGenCls(String n) {
    Int i = 0
    while i < GEN_CLS_NAMES.length() { if GEN_CLS_NAMES.get(i) == n { return true }; i = i + 1 }
    return false
}
static N genClsDecl(String n) {
    Int i = 0
    while i < GEN_CLS_NAMES.length() {
        if GEN_CLS_NAMES.get(i) == n { return GEN_CLS_DECLS.get(i) }
        i = i + 1
    }
    return new N()
}
static List<String> genSorted() {
    List<String> xs = []
    Int i = 0
    while i < GEN_INST_NAME.length() { xs.push(GEN_INST_NAME.get(i)); i = i + 1 }
    sortStrs(xs)
    return xs
}
static void sortGenInsts() {
    Int a = 1
    while a < GEN_INST_NAME.length() {
        String xn = GEN_INST_NAME.get(a)
        String xk = GEN_INST_KEY.get(a)
        String xb = GEN_INST_BASE.get(a)
        Int b = a
        while b > 0 && strLess(xn, GEN_INST_NAME.get(b - 1)) {
            GEN_INST_NAME.set(b, GEN_INST_NAME.get(b - 1))
            GEN_INST_KEY.set(b, GEN_INST_KEY.get(b - 1))
            GEN_INST_BASE.set(b, GEN_INST_BASE.get(b - 1))
            b = b - 1
        }
        GEN_INST_NAME.set(b, xn)
        GEN_INST_KEY.set(b, xk)
        GEN_INST_BASE.set(b, xb)
        a = a + 1
    }
}
static void addClsInst(String cn, String key) {
    String inst = cn + "_" + mangle(key)
    Int i = 0
    while i < GEN_INST_NAME.length() { if GEN_INST_NAME.get(i) == inst { return }; i = i + 1 }
    GEN_INST_NAME.push(inst)
    GEN_INST_KEY.push(key)
    GEN_INST_BASE.push(cn)
    CLS_NAMES.push(inst)
    N d = genClsDecl(cn)
    SUB_FROM = ["T"]
    SUB_TO = [key]
    N fs = fld(d, "Fields")
    Int fi = 0
    while fi < fs.el.length() {
        FLD_OWNER.push(inst)
        FLD_NAME.push(unq(txt(fld(fs.el.get(fi), "Name"))))
        FLD_TYPE.push(typeKey(fld(fs.el.get(fi), "Type")))
        fi = fi + 1
    }
    N ms = fld(d, "Methods")
    fi = 0
    while fi < ms.el.length() {
        MTH_OWNER.push(inst)
        MTH_NAME.push(unq(txt(fld(ms.el.get(fi), "Name"))))
        MTH_RET.push(retKey(ms.el.get(fi)))
        fi = fi + 1
    }
    SUB_FROM = []
    SUB_TO = []
}
static void scanCls(N n) {
    if n.nm == "New" {
        N t = fld(n, "Type")
        String last = lastQual(t)
        N ta = fld(t, "Args")
        if isGenCls(last) && ta.el.length() > 0 { addClsInst(last, typeKey(ta.el.get(0))) }
    }
    if n.nm == "NamedType" {
        String last2 = lastQual(n)
        N ta2 = fld(n, "Args")
        if isGenCls(last2) && ta2.el.length() > 0 { addClsInst(last2, typeKey(ta2.el.get(0))) }
    }
    Int i = 0
    while i < n.fv.length() { scanCls(n.fv.get(i)); i = i + 1 }
    i = 0
    while i < n.el.length() { scanCls(n.el.get(i)); i = i + 1 }
}

static void scanTupleTypes(N n) {
    if n.nm == "TupleTypeRef" {
        N els = fld(n, "Elems")
        Int pre = 0
        while pre < els.el.length() { scanTupleTypes(els.el.get(pre)); pre = pre + 1 }
        String b = ""
        Int i = 0
        while i < els.el.length() { if i > 0 { b = b + ", " }; b = b + typeKey(els.el.get(i)); i = i + 1 }
        addTuple(typeKey(n), b)
    }
    Int i = 0
    while i < n.fv.length() { scanTupleTypes(n.fv.get(i)); i = i + 1 }
    i = 0
    while i < n.el.length() { scanTupleTypes(n.el.get(i)); i = i + 1 }
}

static Int chRank(String c) {
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_".indexOf(c)
}
static Int cmpName(String a, String b) {
    Int i = 0
    while i < a.length() && i < b.length() {
        if a.substring(i, 1) != b.substring(i, 1) {
            Int ra = chRank(a.substring(i, 1))
            Int rb = chRank(b.substring(i, 1))
            if ra < rb { return -1 }
            return 1
        }
        i = i + 1
    }
    if a.length() < b.length() { return -1 }
    if a.length() > b.length() { return 1 }
    return 0
}
static Bool hasGenericListType(N n) {
    if n.nm == "NamedType" && lastQual(n) == "List" {
        N ags = fld(n, "Args")
        if ags.el.length() > 0 {
            N a0 = ags.el.get(0)
            if a0.nm == "NamedType" && lastQual(a0) == "T" { return true }
        }
    }
    Int j = 0
    while j < n.fv.length() { if hasGenericListType(n.fv.get(j)) { return true }; j = j + 1 }
    j = 0
    while j < n.el.length() { if hasGenericListType(n.el.get(j)) { return true }; j = j + 1 }
    return false
}

static Bool hasU16In(N n) {
    if n.nm == "NamedType" && lastQual(n) == "List" {
        N ags = fld(n, "Args")
        if ags.el.length() > 0 {
            N a0 = ags.el.get(0)
            if a0.nm == "NamedType" && lastQual(a0) == "UInt16" { return true }
        }
    }
    if n.nm == "SuffixedType" {
        N bs = fld(n, "Base")
        if bs.nm == "NamedType" && lastQual(bs) == "UInt16" { return true }
    }
    Int j = 0
    while j < n.fv.length() { if hasU16In(n.fv.get(j)) { return true }; j = j + 1 }
    j = 0
    while j < n.el.length() { if hasU16In(n.el.get(j)) { return true }; j = j + 1 }
    return false
}

static Bool hasListIn(N n) {
    if n.nm == "NamedType" && lastQual(n) == "List" { return true }
    if n.nm == "SuffixedType" {
        N sf = fld(n, "Suffixes")
        Int i = 0
        while i < sf.el.length() { if unq(txt(sf.el.get(i))) == "[]" { return true }; i = i + 1 }
    }
    Int j = 0
    while j < n.fv.length() { if hasListIn(n.fv.get(j)) { return true }; j = j + 1 }
    j = 0
    while j < n.el.length() { if hasListIn(n.el.get(j)) { return true }; j = j + 1 }
    return false
}

static List<N> sortedClassDecls(N decls) {
    List<N> xs = []
    Int i = 0
    while i < decls.el.length() {
        N d = decls.el.get(i)
        if d.nm == "ClassDecl" && fld(d, "TypePars").el.length() == 0 { xs.push(d) }
        i = i + 1
    }
    List<N> resL = []
    List<String> used = []
    while resL.length() < xs.length() {
        Int best = -1
        String bestNm = ""
        Int j = 0
        while j < xs.length() {
            String nm = unq(txt(fld(xs.get(j), "Name")))
            if !inNames(used, nm) {
                if (best < 0) || (cmpName(nm, bestNm) < 0) { best = j; bestNm = nm }
            }
            j = j + 1
        }
        resL.push(xs.get(best))
        used.push(bestNm)
    }
    return resL
}
static String containerTypedef(String key) {
    if isObjArr(key) {
        String e = objArrElem(key)
        return "typedef struct { rt_header hdr; size_t len; size_t cap; " + cType(e) + " *data; } " + classArrName(key) + ";"
    }
    if key == "List<Int>" || key == "Int[]" { return "typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;" }
    if key == "List<UInt16>" || key == "UInt16[]" { return "typedef struct { rt_header hdr; size_t len; size_t cap; uint16_t *data; } xn_arr_u16;" }
    return ""
}
static String mangleC(String ct) {
    if ct == "int64_t" { return "i" }
    if ct == "int" { return "b" }
    if ct == "uint8_t" { return "u8" }
    if ct == "uint16_t" { return "u16" }
    if ct == "uint32_t" { return "u32" }
    if ct == "uint64_t" { return "u64" }
    if ct == "int8_t" { return "i8" }
    if ct == "int16_t" { return "i16" }
    if ct == "int32_t" { return "i32" }
    if ct == "double" { return "f64" }
    if ct == "float" { return "f32" }
    if ct == "rt_string *" { return "s" }
    if ct.indexOf("xn_Cls_") == 0 && ct.length() > 4 && ct.substring(ct.length() - 2, 2) == " *" { return "o_" + ct.substring(7, ct.length() - 9) }
    if ct.indexOf("xn_tup_") == 0 { return "t_" + ct.substring(7, ct.length() - 7) }
    return sanitizeCName(ct)
}
static String arrNameC(String ec) { return "xn_arr_" + mangleC(ec) }
static String setNameC(String ec) { return "xn_set_" + mangleC(ec) }
static String mapNameC(String kc, String vc) { return "xn_map_" + mangleC(kc) + "_" + mangleC(vc) }
static void sortStrs(List<String> xs) {
    Int a = 1
    while a < xs.length() {
        String x = xs.get(a)
        Int b = a
        while b > 0 && strLess(x, xs.get(b - 1)) { xs.set(b, xs.get(b - 1)); b = b - 1 }
        xs.set(b, x)
        a = a + 1
    }
}
static String dynContainerTypedefs() {
    List<String> arrs = []
    Int i = 0
    while i < C_ARR.length() { if !hasStr(arrs, C_ARR.get(i)) { arrs.push(C_ARR.get(i)) }; i = i + 1 }
    sortStrs(arrs)
    String s = ""
    i = 0
    while i < arrs.length() {
        String ec = arrs.get(i)
        s = s + "typedef struct { rt_header hdr; size_t len; size_t cap; " + ec + " *data; } " + arrNameC(ec) + ";\n\n"
        i = i + 1
    }
    List<String> sets = []
    i = 0
    while i < C_SET.length() { if !hasStr(sets, C_SET.get(i)) { sets.push(C_SET.get(i)) }; i = i + 1 }
    sortStrs(sets)
    i = 0
    while i < sets.length() {
        String ec = sets.get(i)
        s = s + "typedef struct { rt_header hdr; " + arrNameC(ec) + " *a; } " + setNameC(ec) + ";\n\n"
        i = i + 1
    }
    List<String> mkeys = []
    i = 0
    while i < C_MAPK.length() {
        String mk = mangleC(C_MAPK.get(i)) + "|" + mangleC(C_MAPV.get(i))
        if !hasStr(mkeys, mk) { mkeys.push(mk) }
        i = i + 1
    }
    sortStrs(mkeys)
    i = 0
    while i < mkeys.length() {
        String mk = mkeys.get(i)
        Int bar = mk.indexOf("|")
        String km = mk.substring(0, bar)
        String vm = mk.substring(bar + 1, mk.length() - bar - 1)
        Int j = 0
        while j < C_MAPK.length() {
            if mangleC(C_MAPK.get(j)) == km && mangleC(C_MAPV.get(j)) == vm {
                s = s + "typedef struct { rt_header hdr; size_t len; size_t cap; " + C_MAPK.get(j) + " *keys; " + C_MAPV.get(j) + " *vals; } xn_map_" + km + "_" + vm + ";\n\n"
                j = C_MAPK.length()
            } else { j = j + 1 }
        }
        i = i + 1
    }
    if s.length() > 0 && s.substring(s.length() - 1, 1) == "\n" { s = s.substring(0, s.length() - 1) }
    return s
}
static String MAP_SS_HELP = "static void xn_map_s_s_scan(void *p, void (*visit)(void *)) {\n    xn_map_s_s *m = (xn_map_s_s *)p;\n    if (m->keys != NULL) { for (size_t i = 0; i < m->len; i++) { visit(m->keys[i]); } }\n    if (m->vals != NULL) { for (size_t i = 0; i < m->len; i++) { visit(m->vals[i]); } }\n}\n\nstatic void xn_map_s_s_deinit(void *p) {\n    xn_map_s_s *m = (xn_map_s_s *)p;\n    if (m->keys != NULL) {\n        free(m->keys);\n        m->keys = NULL;\n    }\n    if (m->vals != NULL) {\n        free(m->vals);\n        m->vals = NULL;\n    }\n    m->len = 0;\n    m->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_map_s_s = { \"Map\", sizeof(xn_map_s_s), xn_map_s_s_deinit, xn_map_s_s_scan };\n\nstatic xn_map_s_s *xn_map_s_s_new(size_t cap) {\n    xn_map_s_s *m = (xn_map_s_s *)xn_gc_new(&RT_TYPE_xn_map_s_s);\n    memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_s_s) - sizeof(rt_header));\n    m->cap = cap ? cap : 4;\n    m->keys = malloc(sizeof(rt_string *) * m->cap);\n    m->vals = malloc(sizeof(rt_string *) * m->cap);\n    if (m->keys == NULL || m->vals == NULL) { abort(); }\n    return m;\n}\n\nstatic long xn_map_s_s_find(const xn_map_s_s *m, rt_string * key) {\n    for (size_t i = 0; i < m->len; i++) {\n        if (m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0) { return (long)i; }\n    }\n    return -1;\n}\n\nstatic void xn_map_s_s_put(xn_map_s_s *m, rt_string * key, rt_string * val) {\n    long i = xn_map_s_s_find(m, key);\n    if (i >= 0) {\n        m->vals[i] = val;\n        return;\n    }\n    if (m->len == m->cap) {\n        m->cap *= 2;\n        m->keys = realloc(m->keys, sizeof(rt_string *) * m->cap);\n        m->vals = realloc(m->vals, sizeof(rt_string *) * m->cap);\n        if (m->keys == NULL || m->vals == NULL) { abort(); }\n    }\n    m->keys[m->len] = key;\n    m->vals[m->len] = val;\n    m->len++;\n}\n\nstatic int xn_map_s_s_has(const xn_map_s_s *m, rt_string * key) { return xn_map_s_s_find(m, key) >= 0; }\n\nstatic rt_string * xn_map_s_s_get_or(const xn_map_s_s *m, rt_string * key, rt_string * dflt) {\n    long i = xn_map_s_s_find(m, key);\n    return i >= 0 ? m->vals[i] : dflt;\n}\n\nstatic int xn_map_s_s_remove(xn_map_s_s *m, rt_string * key) {\n    long i = xn_map_s_s_find(m, key);\n    if (i < 0) { return 0; }\n    for (size_t j = (size_t)i; j + 1 < m->len; j++) {\n        m->keys[j] = m->keys[j + 1];\n        m->vals[j] = m->vals[j + 1];\n    }\n    m->len--;\n    return 1;\n}\n\nstatic void xn_map_s_s_clear(xn_map_s_s *m) {\n    m->len = 0;\n}\n\nstatic int xn_map_s_s_cmp_key(rt_string * a, rt_string * b) {\n    size_t n = a->len < b->len ? a->len : b->len;\n    int c = memcmp(a->bytes, b->bytes, n);\n    if (c != 0) { return c; }\n    return (a->len > b->len) - (a->len < b->len);\n}\n\nstatic void xn_map_s_s_sort_idx(const xn_map_s_s *m, size_t *idx) {\n    for (size_t i = 1; i < m->len; i++) {\n        size_t x = idx[i];\n        size_t j = i;\n        while (j > 0 && xn_map_s_s_cmp_key(m->keys[idx[j - 1]], m->keys[x]) > 0) {\n            idx[j] = idx[j - 1];\n            j--;\n        }\n        idx[j] = x;\n    }\n}\n\nstatic xn_arr_s *xn_map_s_s_keys(const xn_map_s_s *m) {\n    xn_arr_s *out = xn_arr_s_new(m->len);\n    if (m->len == 0) { return out; }\n    size_t *idx = malloc(sizeof(size_t) * m->len);\n    if (idx == NULL) { abort(); }\n    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }\n    xn_map_s_s_sort_idx(m, idx);\n    for (size_t i = 0; i < m->len; i++) { xn_arr_s_push(out, m->keys[idx[i]]); }\n    free(idx);\n    return out;\n}\n\nstatic xn_arr_s *xn_map_s_s_values(const xn_map_s_s *m) {\n    xn_arr_s *out = xn_arr_s_new(m->len);\n    if (m->len == 0) { return out; }\n    size_t *idx = malloc(sizeof(size_t) * m->len);\n    if (idx == NULL) { abort(); }\n    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }\n    xn_map_s_s_sort_idx(m, idx);\n    for (size_t i = 0; i < m->len; i++) { xn_arr_s_push(out, m->vals[idx[i]]); }\n    free(idx);\n    return out;\n}\n\nstatic xn_opt_s xn_map_s_s_get(const xn_map_s_s *m, rt_string * key) {\n    xn_opt_s r;\n    long i = xn_map_s_s_find(m, key);\n    if (i < 0) { r.has = 0; r.v = NULL; return r; }\n    r.has = 1;\n    r.v = m->vals[i];\n    return r;\n}"
static String mapSSBlock() { return MAP_SS_HELP }

static String mapSITypedef() {
    return "typedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *keys; int64_t *vals; } xn_map_s_i;"
}
static String arrSBlock() {
    String a = "typedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *data; } xn_arr_s;"
    String b = "static void xn_set_i_scan"
    Int i0 = PRELUDE_MAPSET.indexOf(a)
    Int j0 = PRELUDE_MAPSET.indexOf(b)
    if i0 < 0 || j0 < 0 { return "" }
    return PRELUDE_MAPSET.substring(i0, j0 - i0)
}
static String mapSIBlock() {
    String a = "static void xn_map_s_i_scan"
    String b = "static xn_arr_s *xn_str_split"
    Int i0 = PRELUDE_MAPSET.indexOf(a)
    Int j0 = PRELUDE_MAPSET.indexOf(b)
    if i0 < 0 || j0 < 0 { return "" }
    return PRELUDE_MAPSET.substring(i0, j0 - i0)
}
static String strSplitBlock() {
    String a = "static xn_arr_s *xn_str_split"
    String b = "static int64_t xn_main"
    Int i0 = PRELUDE_MAPSET.indexOf(a)
    Int j0 = PRELUDE_MAPSET.indexOf(b)
    if i0 < 0 || j0 < 0 { return "" }
    String r0 = PRELUDE_MAPSET.substring(i0, j0 - i0)
    if r0.length() > 0 && r0.substring(r0.length() - 1, 1) == "\n" { r0 = r0.substring(0, r0.length() - 1) }
    return r0
}
static String u16ArrHelperText() {
    String b = ""
    b = b + "static void xn_arr_u16_deinit(void *p) {\n"
    b = b + "    xn_arr_u16 *a = (xn_arr_u16 *)p;\n"
    b = b + "    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n"
    b = b + "    a->len = 0;\n    a->cap = 0;\n}\n\n"
    b = b + "static const rt_type RT_TYPE_xn_arr_u16 = { \"List\", sizeof(xn_arr_u16), xn_arr_u16_deinit, NULL };\n\n"
    b = b + "static xn_arr_u16 *xn_arr_u16_new(size_t cap) {\n"
    b = b + "    xn_arr_u16 *a = (xn_arr_u16 *)xn_gc_new(&RT_TYPE_xn_arr_u16);\n"
    b = b + "    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_u16) - sizeof(rt_header));\n"
    b = b + "    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(uint16_t) * a->cap);\n"
    b = b + "    if (a->data == NULL) { abort(); }\n    return a;\n}\n\n"
    b = b + "static void xn_arr_u16_push(xn_arr_u16 *a, uint16_t v) {\n"
    b = b + "    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(uint16_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n"
    b = b + "    a->data[a->len++] = v;\n}\n\n"
    b = b + "static uint16_t xn_arr_u16_get(const xn_arr_u16 *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\n"
    b = b + "static void xn_arr_u16_set(xn_arr_u16 *a, int64_t i, uint16_t v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\n"
    b = b + "static uint16_t xn_arr_u16_remove(xn_arr_u16 *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n"
    b = b + "    uint16_t old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\n"
    b = b + "static void xn_arr_u16_insert(xn_arr_u16 *a, int64_t i, uint16_t v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n"
    b = b + "    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(uint16_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n"
    b = b + "    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\n"
    b = b + "static void xn_arr_u16_clear(xn_arr_u16 *a) {\n    a->len = 0;\n}\n\n"
    b = b + "static rt_string *xn_arr_u16_join(xn_arr_u16 *a, rt_string *sep) {\n"
    b = b + "    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, rt_string_from_c(\"\"));\n    }\n    return res;\n}\n"
    return b
}
static String arrIHelperText() {
    Int s = PRELUDE_ARR.indexOf("static void xn_arr_i_deinit")
    Int e = PRELUDE_ARR.indexOf("static int64_t xn_main();")
    return PRELUDE_ARR.substring(s, e - s).trim() + "\n"
}
static String classArrHelperText(String key) {
    String an = classArrName(key)
    String ec = objArrElem(key)
    String ct = cType(ec)
    Bool gcEl = classPolicy(ec) == "gc"
    String b = ""
    b = b + "static void " + an + "_scan(void *p, void (*visit)(void *)) {\n"
    b = b + "    " + an + " *a = (" + an + " *)p;\n"
    b = b + "    if (a->data == NULL) { return; }\n"
    b = b + "    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }\n"
    b = b + "}\n\n"
    b = b + "static void " + an + "_deinit(void *p) {\n"
    b = b + "    " + an + " *a = (" + an + " *)p;\n"
    b = b + "    if (a->data != NULL) {\n"
    if !gcEl { b = b + "        for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }\n" }
    b = b + "        free(a->data);\n"
    b = b + "        a->data = NULL;\n"
    b = b + "    }\n"
    b = b + "    a->len = 0;\n"
    b = b + "    a->cap = 0;\n"
    b = b + "}\n\n"
    b = b + "static const rt_type RT_TYPE_" + an + " = { \"List\", sizeof(" + an + "), " + an + "_deinit, " + an + "_scan };\n\n"
    b = b + "static " + an + " *" + an + "_new(size_t cap) {\n"
    b = b + "    " + an + " *a = (" + an + " *)xn_gc_new(&RT_TYPE_" + an + ");\n"
    b = b + "    memset((char *)a + sizeof(rt_header), 0, sizeof(" + an + ") - sizeof(rt_header));\n"
    b = b + "    a->cap = cap ? cap : 4;\n"
    b = b + "    a->data = malloc(sizeof(" + ct + ") * a->cap);\n"
    b = b + "    if (a->data == NULL) { abort(); }\n"
    b = b + "    return a;\n"
    b = b + "}\n\n"
    b = b + "static void " + an + "_push(" + an + " *a, " + ct + " v) {\n"
    b = b + "    if (a->len == a->cap) {\n"
    b = b + "        a->cap *= 2;\n"
    b = b + "        a->data = realloc(a->data, sizeof(" + ct + ") * a->cap);\n"
    b = b + "        if (a->data == NULL) { abort(); }\n"
    b = b + "    }\n"
    if !gcEl { b = b + "    rt_retain(v);\n" }
    b = b + "    a->data[a->len++] = v;\n"
    b = b + "}\n\n"
    b = b + "static " + ct + " " + an + "_get(const " + an + " *a, int64_t i) {\n"
    b = b + "    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n"
    b = b + "    return a->data[i];\n"
    b = b + "}\n\n"
    b = b + "static void " + an + "_set(" + an + " *a, int64_t i, " + ct + " v) {\n"
    b = b + "    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n"
    if !gcEl { b = b + "    rt_release(a->data[i]);\n    rt_retain(v);\n" }
    b = b + "    a->data[i] = v;\n"
    b = b + "}\n\n"
    b = b + "static " + ct + " " + an + "_remove(" + an + " *a, int64_t i) {\n"
    b = b + "    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n"
    b = b + "    " + ct + " old = a->data[i];\n"
    b = b + "    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n"
    b = b + "        a->data[j] = a->data[j + 1];\n"
    b = b + "    }\n"
    b = b + "    a->len--;\n"
    b = b + "    return old;\n"
    b = b + "}\n\n"
    b = b + "static void " + an + "_insert(" + an + " *a, int64_t i, " + ct + " v) {\n"
    b = b + "    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n"
    b = b + "    if (a->len == a->cap) {\n"
    b = b + "        a->cap *= 2;\n"
    b = b + "        a->data = realloc(a->data, sizeof(" + ct + ") * a->cap);\n"
    b = b + "        if (a->data == NULL) { abort(); }\n"
    b = b + "    }\n"
    b = b + "    for (size_t j = a->len; j > (size_t)i; j--) {\n"
    b = b + "        a->data[j] = a->data[j - 1];\n"
    b = b + "    }\n"
    if !gcEl { b = b + "    rt_retain(v);\n" }
    b = b + "    a->data[i] = v;\n"
    b = b + "    a->len++;\n"
    b = b + "}\n\n"
    b = b + "static void " + an + "_clear(" + an + " *a) {\n"
    if !gcEl { b = b + "    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }\n" }
    b = b + "    a->len = 0;\n"
    b = b + "}\n\n"
    b = b + "static rt_string *" + an + "_join(" + an + " *a, rt_string *sep) {\n"
    b = b + "    rt_string *res = rt_string_from_c(\"\");\n"
    b = b + "    for (size_t i = 0; i < a->len; i++) {\n"
    b = b + "        if (i > 0) {\n"
    b = b + "            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n"
    b = b + "        }\n"
    b = b + "        res = xn_concat(res, rt_string_from_c(\"\"));\n"
    b = b + "    }\n"
    b = b + "    return res;\n"
    b = b + "}\n"
    return b
}
static String topFuncProtos(N decls) {
    String b = ""
    Int i = 0
    while i < decls.el.length() {
        N d = decls.el.get(i)
        if d.nm == "TopFunc" {
            String nm = unq(txt(fld(d, "Name")))
            if nm != "main" && fld(d, "TypePars").el.length() == 0 {
                String rk = retKey(d)
                b = b + "static " + cType(rk) + " xn_" + nm + "(" + paramsOf(d) + ");\n"
            }
        }
        i = i + 1
    }
    return b
}

static String joinList(List<String> xs, String sep) {
    String b = ""
    Int i = 0
    while i < xs.length() { if i > 0 { b = b + sep }; b = b + xs.get(i); i = i + 1 }
    return b
}
static Int ffiIdx(String name) {
    Int i = 0
    while i < FFI_E_NAME.length() { if FFI_E_NAME.get(i) == name { return i }; i = i + 1 }
    return -1
}
static Bool isFFI(String name) { return ffiIdx(name) >= 0 }
static Bool ffiIsErr(Int idx) { return FFI_E_ERRP.get(idx) != "" || FFI_E_ERRRET.get(idx) == 1 }
static String ffiRetType(String name) {
    Int idx = ffiIdx(name)
    if idx < 0 { return "Int" }
    String k = FFI_E_RETK.get(idx)
    if k == "string" { return "String" }
    if k == "text" { return "Text" }
    if k == "bytes" { return "Bytes" }
    if k == "void" { return "void" }
    return FFI_E_RETN.get(idx)
}
static String ffiScalarC(String n) {
    if n == "Int" || n == "Int64" { return "int64_t" }
    if n == "UInt" || n == "UInt64" { return "uint64_t" }
    if n == "Int8" { return "int8_t" }
    if n == "Int16" { return "int16_t" }
    if n == "Int32" { return "int32_t" }
    if n == "UInt8" { return "uint8_t" }
    if n == "UInt16" { return "uint16_t" }
    if n == "UInt32" { return "uint32_t" }
    if n == "Float" || n == "Float64" { return "double" }
    if n == "Float32" { return "float" }
    if n == "Bool" { return "uint8_t" }
    if n == "Char" { return "uint32_t" }
    return "int64_t"
}
static String ffiErrEnum(String kind) {
    if kind == "InvalidArgument" { return "XRT_ERR_INVALID_ARGUMENT" }
    if kind == "NotFound" { return "XRT_ERR_NOT_FOUND" }
    if kind == "AlreadyExists" || kind == "Conflict" { return "XRT_ERR_ALREADY_EXISTS" }
    if kind == "PermissionDenied" || kind == "Permission" { return "XRT_ERR_PERMISSION_DENIED" }
    if kind == "Io" { return "XRT_ERR_IO" }
    if kind == "Network" { return "XRT_ERR_NETWORK" }
    if kind == "Timeout" { return "XRT_ERR_TIMEOUT" }
    if kind == "Cancelled" { return "XRT_ERR_CANCELLED" }
    if kind == "Busy" || kind == "Limit" { return "XRT_ERR_BUSY" }
    if kind == "Unavailable" { return "XRT_ERR_UNAVAILABLE" }
    if kind == "DataCorrupted" { return "XRT_ERR_DATA_CORRUPTED" }
    if kind == "Unsupported" { return "XRT_ERR_UNSUPPORTED" }
    if kind == "OutOfMemory" { return "XRT_ERR_OUT_OF_MEMORY" }
    if kind == "Internal" { return "XRT_ERR_INTERNAL" }
    return "XRT_ERR_INTERNAL"
}
static List<String> ffiSegs(Int idx) {
    String ps = FFI_E_PARAMS.get(idx)
    List<String> resL = []
    if ps == "" { return resL }
    List<String> xs = ps.split(";")
    Int i = 0
    while i < xs.length() { resL.push(xs.get(i)); i = i + 1 }
    return resL
}
static String ffiSegField(String seg, Int n) {
    List<String> fs = seg.split(":")
    if n < fs.length() { return fs.get(n) }
    return ""
}
static String ffiRegions() {
    List<String> rs = []
    Int i = 0
    while i < FFI_E_REGION.length() {
        if !inNames(rs, FFI_E_REGION.get(i)) { rs.push(FFI_E_REGION.get(i)) }
        i = i + 1
    }
    Int a = 1
    while a < rs.length() {
        Int b = a
        while b > 0 {
            if cmpName(rs.get(b - 1), rs.get(b)) > 0 {
                String t = rs.get(b - 1)
                rs.set(b - 1, rs.get(b))
                rs.set(b, t)
                b = b - 1
            } else { b = 0 }
        }
        a = a + 1
    }
    return joinList(rs, ";")
}
static String ffiNativeProto(Int idx) {
    String retk = FFI_E_RETK.get(idx)
    String retn = FFI_E_RETN.get(idx)
    String cname = FFI_E_CNAME.get(idx)
    String errp = FFI_E_ERRP.get(idx)
    String ret = "void"
    if retk == "scalar" { ret = ffiScalarC(retn) }
    else if retk == "string" || retk == "text" { ret = "const char *" }
    else if retk == "bytes" { ret = "xrt_bytes_obj *" }
    else if retk == "handle" { ret = "void *" }
    List<String> parts = []
    List<String> segs = ffiSegs(idx)
    Int i = 0
    while i < segs.length() {
        String pn = ffiSegField(segs.get(i), 0)
        String kind = ffiSegField(segs.get(i), 1)
        String pt = ffiSegField(segs.get(i), 2)
        String lk = ffiSegField(segs.get(i), 3)
        if errp != "" && pn == errp { parts.push("int32_t *" + pn) }
        else if kind == "string" || kind == "text" { parts.push("const char *" + pn + "_bytes"); parts.push("size_t " + pn + "_len") }
        else if kind == "bytes" { parts.push("void *" + pn); parts.push("size_t " + pn + "_len") }
        else if kind == "handle" {
            if lk == "transfer" || lk == "reclaim" { parts.push("void **" + pn + "_out") }
            else { parts.push("void *" + pn) }
        }
        else { parts.push(ffiScalarC(pt) + " " + pn) }
        i = i + 1
    }
    return ret + " " + cname + "(" + joinList(parts, ", ") + ");"
}
static String ffiWrapper(Int idx) {
    String name = FFI_E_NAME.get(idx)
    String cname = FFI_E_CNAME.get(idx)
    String retk = FFI_E_RETK.get(idx)
    String retn = FFI_E_RETN.get(idx)
    String errp = FFI_E_ERRP.get(idx)
    Bool codeRet = FFI_E_ERRRET.get(idx) == 1
    List<String> decls = []
    List<String> pre = []
    List<String> call = []
    List<String> postAlways = []
    List<String> postOK = []
    String closeTarget = ""
    List<String> segs = ffiSegs(idx)
    Int i = 0
    while i < segs.length() {
        String pn = ffiSegField(segs.get(i), 0)
        String kind = ffiSegField(segs.get(i), 1)
        String pt = ffiSegField(segs.get(i), 2)
        String lk = ffiSegField(segs.get(i), 3)
        if errp != "" && pn == errp {
            pre.push("int32_t xn_code = 0;")
            call.push("&xn_code")
        } else if kind == "scalar" {
            if pt == "Bool" { decls.push("int " + pn); call.push("((uint8_t)(" + pn + " ? 1 : 0))") }
            else { decls.push(ffiScalarC(pt) + " " + pn); call.push(pn) }
        } else if kind == "string" || kind == "text" {
            decls.push("const char *" + pn + "_bytes, size_t " + pn + "_len")
            call.push(pn + "_bytes, " + pn + "_len")
        } else if kind == "bytes" {
            decls.push("void *" + pn + ", size_t " + pn + "_len")
            if lk == "borrow" {
                pre.push("uint8_t *xn_buf_" + pn + " = xn_ffi_canary_enter((const uint8_t *)" + pn + ", " + pn + "_len);")
                call.push("(void *)(xn_buf_" + pn + " + XN_FFI_CANARY), " + pn + "_len")
                postAlways.push("xn_ffi_canary_leave(xn_buf_" + pn + ", (uint8_t *)" + pn + ", " + pn + "_len);")
            } else { call.push(pn + ", " + pn + "_len") }
        } else if kind == "handle" {
            if lk == "transfer" {
                decls.push("xrt_handle **" + pn + "_out")
                pre.push("void *xn_native_" + pn + " = NULL;")
                call.push("&xn_native_" + pn)
                postOK.push("*" + pn + "_out = (xn_native_" + pn + " == NULL) ? NULL : xrt_handle_new(xn_native_" + pn + ", NULL, \"" + name + "\");")
            } else if lk == "reclaim" {
                decls.push("xrt_handle *" + pn)
                pre.push("void *xn_h_" + pn + " = xrt_handle_native(" + pn + ");")
                pre.push("if (xn_h_" + pn + " == NULL) { xrt_fatal(\"FFI 归还句柄已关闭或为空（S7 §4.3）：" + name + "\"); }")
                call.push("xn_h_" + pn)
                postAlways.push("xrt_handle_mark_closed(" + pn + ");")
            } else {
                decls.push("xrt_handle *" + pn)
                pre.push("void *xn_h_" + pn + " = xrt_handle_native(" + pn + ");")
                pre.push("if (xn_h_" + pn + " == NULL) { xrt_fatal(\"FFI 句柄已关闭或为空（S7 §4.3）：" + name + "\"); }")
                call.push("xn_h_" + pn)
            }
        }
        i = i + 1
    }
    Bool hasOut = false
    String retC = ""
    String nativeC = ""
    String postOut = ""
    if !codeRet {
        if retk == "scalar" {
            hasOut = true
            retC = ffiScalarC(retn)
            if retn == "Bool" { postOut = "*xn_out = (uint8_t)xn_ffi_bool_from_native((uint8_t)xn_v);" }
            else { postOut = "*xn_out = (" + retC + ")xn_v;" }
        } else if retk == "string" {
            hasOut = true; retC = "xrt_string *"; nativeC = "const char *"
            postOut = "*xn_out = (xn_v == NULL) ? NULL : xrt_string_from_c(xn_v);"
        } else if retk == "text" {
            hasOut = true; retC = "xrt_text *"; nativeC = "const char *"
            postOut = "*xn_out = (xn_v == NULL) ? NULL : xrt_text_from_string(xn_v, strlen(xn_v));"
        } else if retk == "bytes" {
            hasOut = true; retC = "xrt_bytes_obj *"; nativeC = "xrt_bytes_obj *"
            postOut = "*xn_out = xn_v;"
        } else if retk == "handle" {
            hasOut = true; retC = "xrt_handle *"
            postOut = "*xn_out = (xn_v == NULL) ? NULL : xrt_handle_new(xn_v, NULL, \"" + name + "\");"
        }
    }
    String b = "/* 绑定入口 " + name + "（原生 " + cname + "） */\n"
    String sig = "static int32_t xn_ffi_" + name + "("
    List<String> parts = []
    i = 0
    while i < decls.length() { parts.push(decls.get(i)); i = i + 1 }
    if hasOut { parts.push(retC + " *xn_out") }
    if parts.length() == 0 { sig = sig + "void" } else { sig = sig + joinList(parts, ", ") }
    b = b + sig + ") {\n"
    i = 0
    while i < pre.length() { b = b + "    " + pre.get(i) + "\n"; i = i + 1 }
    String nativeCall = cname + "(" + joinList(call, ", ") + ")"
    if codeRet {
        b = b + "    return (int32_t)" + nativeCall + ";\n"
    } else if hasOut {
        if nativeC == "" { nativeC = retC }
        b = b + "    " + nativeC + " xn_v = " + nativeCall + ";\n"
        if errp != "" { b = b + "    if (xn_code != 0) { return xn_code; }\n" }
        i = 0
        while i < postAlways.length() { b = b + "    " + postAlways.get(i) + "\n"; i = i + 1 }
        i = 0
        while i < postOK.length() { b = b + "    " + postOK.get(i) + "\n"; i = i + 1 }
        b = b + "    " + postOut + "\n    return 0;\n"
    } else {
        b = b + "    " + nativeCall + ";\n"
        if errp != "" { b = b + "    if (xn_code != 0) { return xn_code; }\n" }
        i = 0
        while i < postAlways.length() { b = b + "    " + postAlways.get(i) + "\n"; i = i + 1 }
        i = 0
        while i < postOK.length() { b = b + "    " + postOK.get(i) + "\n"; i = i + 1 }
        b = b + "    return 0;\n"
    }
    return b + "}\n"
}
static String ffiCompanion(Int idx) {
    String name = FFI_E_NAME.get(idx)
    String retk = FFI_E_RETK.get(idx)
    String retn = FFI_E_RETN.get(idx)
    List<String> fields = []
    List<String> fieldTypes = []
    List<String> segs = ffiSegs(idx)
    Int i = 0
    while i < segs.length() {
        String pn = ffiSegField(segs.get(i), 0)
        String kind = ffiSegField(segs.get(i), 1)
        String pt = ffiSegField(segs.get(i), 2)
        String lk = ffiSegField(segs.get(i), 3)
        if kind == "scalar" { fields.push("p" + str(i)); fieldTypes.push(ffiScalarC(pt)) }
        else if kind == "string" || kind == "text" { fields.push("p" + str(i) + "_bytes"); fieldTypes.push("const char *"); fields.push("p" + str(i) + "_len"); fieldTypes.push("size_t") }
        else if kind == "bytes" { fields.push("p" + str(i) + "_data"); fieldTypes.push("void *"); fields.push("p" + str(i) + "_len"); fieldTypes.push("size_t") }
        else if kind == "handle" { fields.push("p" + str(i)); fieldTypes.push("xrt_handle *") }
        i = i + 1
    }
    Bool hasOut = false
    String outC = ""
    if retk == "scalar" { hasOut = true; outC = ffiScalarC(retn) }
    else if retk == "string" { hasOut = true; outC = "rt_string *" }
    else if retk == "text" { hasOut = true; outC = "xrt_text *" }
    else if retk == "bytes" { hasOut = true; outC = "xrt_bytes_obj *" }
    else if retk == "handle" { hasOut = true; outC = "xrt_handle *" }
    String b = "/* companion " + name + "（.unaware + @longRunning → xrt_companion_submit/wait） */\n"
    b = b + "typedef struct {\n"
    i = 0
    while i < fields.length() { b = b + "    " + fieldTypes.get(i) + " " + fields.get(i) + ";\n"; i = i + 1 }
    if hasOut { b = b + "    " + outC + " out;\n" }
    if FFI_E_ERRP.get(idx) != "" { b = b + "    int32_t code;\n" }
    b = b + "    int32_t rc;\n"
    b = b + "} xn_companion_" + name + "_args;\n\n"
    b = b + "static void *xn_companion_" + name + "_thunk(void *xn_p) {\n"
    b = b + "    xn_companion_" + name + "_args *a = (xn_companion_" + name + "_args *)xn_p;\n"
    List<String> args = []
    i = 0
    while i < fields.length() { args.push("a->" + fields.get(i)); i = i + 1 }
    if hasOut { args.push("&a->out") }
    b = b + "    a->rc = xn_ffi_" + name + "(" + joinList(args, ", ") + ");\n"
    return b + "    return NULL;\n}\n"
}
static String ffiSupportText() {
    String b = FFI_FIXED_HEAD + FFI_CANARY
    List<String> regs = ffiRegions().split(";")
    Int ri = 0
    while ri < regs.length() {
        String rg = regs.get(ri)
        b = b + "static const char *xn_ffi_" + rg + "_error_kind(int32_t code) {\n    switch (code) {\n"
        Int j = 0
        while j < FFI_RULE_REGION.length() {
            if FFI_RULE_REGION.get(j) == rg { b = b + "    case " + str(FFI_RULE_CODE.get(j)) + ": return \"" + FFI_RULE_KIND.get(j) + "\";\n" }
            j = j + 1
        }
        b = b + "    default: return \"Internal\";\n    }\n}\n\n"
        b = b + "static xrt_error_kind xn_ffi_" + rg + "_error_kind_id(int32_t code) {\n    switch (code) {\n"
        j = 0
        while j < FFI_RULE_REGION.length() {
            if FFI_RULE_REGION.get(j) == rg { b = b + "    case " + str(FFI_RULE_CODE.get(j)) + ": return " + ffiErrEnum(FFI_RULE_KIND.get(j)) + ";\n" }
            j = j + 1
        }
        b = b + "    default: return XRT_ERR_INTERNAL;\n    }\n}\n\n"
        ri = ri + 1
    }
    b = b + "/* 原生符号声明：编组签名的投影。绑定层自行包含原生头时\n"
    b = b + "   定义 XN_FFI_NATIVE_DECLS 关闭本节（S7 §3.2）。 */\n#ifndef XN_FFI_NATIVE_DECLS\n"
    Int i = 0
    while i < FFI_E_NAME.length() { b = b + ffiNativeProto(i) + "\n"; i = i + 1 }
    b = b + "#endif\n\n"
    i = 0
    while i < FFI_E_NAME.length() { b = b + ffiWrapper(i) + "\n"; i = i + 1 }
    i = 0
    while i < FFI_E_NAME.length() {
        if FFI_E_COMP.get(i) == 1 { b = b + ffiCompanion(i) + "\n" }
        i = i + 1
    }
    return b
}
static void parseRegistry(String text) {
    FFI_E_REGION = []
    FFI_E_NAME = []
    FFI_E_CNAME = []
    FFI_E_RETK = []
    FFI_E_RETN = []
    FFI_E_ERRP = []
    FFI_E_ERRRET = []
    FFI_E_COMP = []
    FFI_E_PARAMS = []
    FFI_RULE_REGION = []
    FFI_RULE_CODE = []
    FFI_RULE_KIND = []
    List<String> lines = text.split("\n")
    Int i = 0
    while i < lines.length() {
        String ln = lines.get(i)
        if ln.length() > 2 {
            List<String> f = ln.split("|")
            if f.get(0) == "M" && f.length() >= 4 {
                FFI_RULE_REGION.push(f.get(1))
                FFI_RULE_CODE.push(dec(f.get(2)))
                FFI_RULE_KIND.push(f.get(3))
            } else if f.get(0) == "E" && f.length() >= 10 {
                FFI_E_REGION.push(f.get(1))
                FFI_E_NAME.push(f.get(2))
                FFI_E_CNAME.push(f.get(3))
                FFI_E_RETK.push(f.get(4))
                FFI_E_RETN.push(f.get(5))
                FFI_E_ERRP.push(f.get(6))
                FFI_E_ERRRET.push(dec(f.get(7)))
                FFI_E_COMP.push(dec(f.get(8)))
                FFI_E_PARAMS.push(f.get(9))
            }
        }
        i = i + 1
    }
}
static String ffiCallExpr(String name, N x, EM e, SC sc) {
    Int idx = ffiIdx(name)
    String retk = FFI_E_RETK.get(idx)
    String retn = FFI_E_RETN.get(idx)
    N args = fld(x, "Args")
    List<String> parts = []
    List<String> segs = ffiSegs(idx)
    String errp0 = FFI_E_ERRP.get(idx)
    Int ai = 0
    Int argi = 0
    while ai < segs.length() {
        String pn = ffiSegField(segs.get(ai), 0)
        String kind = ffiSegField(segs.get(ai), 1)
        String pt = ffiSegField(segs.get(ai), 2)
        if errp0 != "" && pn == errp0 { ai = ai + 1; continue }
        String av = expr(args.el.get(argi), e, sc)
        if kind == "string" || kind == "text" {
            String sv = av
            if args.el.get(argi).nm != "IdentExpr" { sv = emitStr(args.el.get(argi), e, sc) }
            parts.push(sv + "->bytes")
            parts.push(sv + "->len")
        } else if kind == "scalar" && pt == "Bool" {
            parts.push("((uint8_t)(" + av + " ? 1 : 0))")
        } else { parts.push(av) }
        argi = argi + 1
        ai = ai + 1
    }
    Bool hasOut = retk != "void"
    String outC = "int64_t"
    String zero = "0"
    if retk == "scalar" { outC = ffiScalarC(retn) }
    else if retk == "string" { outC = "xrt_string *"; zero = "NULL" }
    else if retk == "text" { outC = "xrt_text *"; zero = "NULL" }
    else if retk == "bytes" { outC = "xrt_bytes_obj *"; zero = "NULL" }
    else if retk == "handle" { outC = "xrt_handle *"; zero = "NULL" }
    String outv = ""
    if hasOut {
        outv = e.nt()
        e.add(outC + " " + outv + " = " + zero + ";")
    }
    if FFI_E_COMP.get(idx) == 1 {
        List<String> fields = []
        Int si = 0
        while si < segs.length() {
            String kind = ffiSegField(segs.get(si), 1)
            if kind == "scalar" { fields.push("p" + str(si)) }
            else if kind == "string" || kind == "text" { fields.push("p" + str(si) + "_bytes"); fields.push("p" + str(si) + "_len") }
            else if kind == "bytes" { fields.push("p" + str(si) + "_data"); fields.push("p" + str(si) + "_len") }
            else { fields.push("p" + str(si)) }
            si = si + 1
        }
        String ca = e.nt()
        e.add("xn_companion_" + name + "_args " + ca + " = {0};")
        Int fi = 0
        while fi < fields.length() { e.add(ca + "." + fields.get(fi) + " = " + parts.get(fi) + ";"); fi = fi + 1 }
        String fut = e.nt()
        e.add("xrt_future *" + fut + " = xrt_companion_submit(xn_companion_" + name + "_thunk, &" + ca + ");")
        String dummy = e.nt()
        e.add("void *" + dummy + " = NULL;")
        String wst = e.nt()
        e.add("int32_t " + wst + " = xrt_companion_wait(" + fut + ", NULL, &" + dummy + ");")
        e.add("xrt_release(" + fut + ");")
        String rc = e.nt()
        e.add("int32_t " + rc + " = (" + wst + " != 0) ? " + wst + " : " + ca + ".rc;")
        if hasOut { e.add(outv + " = " + ca + ".out;") }
        return outv
    }
    if hasOut { parts.push("&" + outv) }
    String rc = e.nt()
    e.add("int32_t " + rc + " = xn_ffi_" + name + "(" + joinList(parts, ", ") + ");")
    if ffiIsErr(idx) && FFI_E_ERRRET.get(idx) == 0 {
        String rt = "Result<" + retn + ", ErrorKind>"
        String resT = e.nt()
        e.add(cType(rt) + " " + resT + " = {0};")
        e.add(resT + ".ok = (" + rc + " == 0);")
        e.add(resT + ".v = " + outv + ";")
        e.add("if (" + rc + " != 0) { " + resT + ".err = (xn_Enum_ErrorKind)xn_ffi_" + FFI_E_REGION.get(idx) + "_error_kind_id(" + rc + "); }")
        return resT
    }
    return outv
}

static String resultTypedefsSorted(SC sc) {
    if sc.resultTypes.length() == 0 { return "" }
    List<String> rs = []
    Int i = 0
    while i < sc.resultTypes.length() { rs.push(sc.resultTypes.get(i)); i = i + 1 }
    Int a = 1
    while a < rs.length() {
        Int b = a
        while b > 0 {
            if cmpName(rs.get(b - 1), rs.get(b)) > 0 {
                String t = rs.get(b - 1)
                rs.set(b - 1, rs.get(b))
                rs.set(b, t)
                b = b - 1
            } else { b = 0 }
        }
        a = a + 1
    }
    String resT = ""
    i = 0
    while i < rs.length() {
        String rk = rs.get(i)
        String vt = resultVal(rk)
        String et = resultErr(rk)
        resT = resT + "typedef struct { int ok; " + resultValC(vt) + " v; " + errMember(resultErrC(et)) + "; } " + cType(rk) + ";\n"
        i = i + 1
    }
    return resT + "\n"
}

static String emitUnit(N unit, String path) {
    EM e = new EM()
    SC sc = new SC()
    e.path = path
    Int fui = 0
    while fui < FFI_E_NAME.length() {
        if ffiIsErr(fui) && FFI_E_ERRRET.get(fui) == 0 { sc.useResult("Result<" + FFI_E_RETN.get(fui) + ", ErrorKind>") }
        fui = fui + 1
    }
    N decls = fld(unit, "Decls")
    Int glc = 0
    while glc < decls.el.length() {
        if hasGenericListType(decls.el.get(glc)) { e.usesList = true; glc = decls.el.length() }
        else { glc = glc + 1 }
    }
    CLS_NAMES = []
    CLS_DECLS = []
    SINGLE_DECLS = []
    GEN_FN_DECLS = []
    INST_FN = []
    INST_NAME = []
    INST_ARGS = []
    INST_KEYS = []
    SUB_FROM = []
    SUB_TO = []
    FN_SUFFIX = ""
    PRIMARY_NAMES = []
    STRUCT_NAMES = []
    FLD_OWNER = []
    FLD_NAME = []
    FLD_TYPE = []
    MTH_OWNER = []
    MTH_NAME = []
    MTH_RET = []
    Int i = 0
    while i < decls.el.length() {
        N d = decls.el.get(i)
        if d.nm == "ClassDecl" {
            String cn = unq(txt(fld(d, "Name")))
            if fld(d, "TypePars").el.length() > 0 {
                GEN_CLS_NAMES.push(cn)
                GEN_CLS_DECLS.push(d)
            } else {
            CLS_NAMES.push(cn)
            CLS_DECLS.push(d)
            if isPrimary(d) {
                PRIMARY_NAMES.push(cn)
                N pps0 = fld(fld(d, "Primary"), "Params")
                Int ppi = 0
                while ppi < pps0.el.length() {
                    FLD_OWNER.push(cn)
                    FLD_NAME.push(unq(txt(fld(pps0.el.get(ppi), "Name"))))
                    FLD_TYPE.push(typeKey(fld(pps0.el.get(ppi), "Type")))
                    ppi = ppi + 1
                }
            }
            N fs = fld(d, "Fields")
            Int fi = 0
            while fi < fs.el.length() {
                FLD_OWNER.push(cn)
                FLD_NAME.push(unq(txt(fld(fs.el.get(fi), "Name"))))
                FLD_TYPE.push(typeKey(fld(fs.el.get(fi), "Type")))
                fi = fi + 1
            }
            N bse = fld(d, "Base")
            if bse.nm != "" && bse.nm != "nil" {
                CLS_BASE_OWNER.push(cn)
                CLS_BASE_NAME.push(unq(txt(fld(bse, "Qual").el.get(0))))
            }
            N prs = fld(d, "Protocols")
            Int prj = 0
            while prj < prs.el.length() {
                CLS_PROTO_OWNER.push(cn)
                CLS_PROTO_NAME.push(unq(txt(fld(prs.el.get(prj), "Qual").el.get(0))))
                prj = prj + 1
            }
            N ms = fld(d, "Methods")
            fi = 0
            while fi < ms.el.length() {
                MTH_OWNER.push(cn)
                MTH_NAME.push(unq(txt(fld(ms.el.get(fi), "Name"))))
                String mret0 = retKey(ms.el.get(fi))
                MTH_RET.push(mret0)
                sc.useResult(mret0)
                fi = fi + 1
            }
            }
        }
        if d.nm == "ExtensionDecl" {
            String et = typeKey(fld(d, "Target"))
            N ems = fld(d, "Methods")
            Int ei = 0
            while ei < ems.el.length() {
                String emn = unq(txt(fld(ems.el.get(ei), "Name")))
                EXT_TARGET.push(et)
                EXT_NAME.push(emn)
                EXT_CNAME.push("xn_Cls_" + et + "_ext_" + emn + "_" + str(ei + 1))
                ei = ei + 1
            }
            EXT_DECLS.push(d)
        }
        if d.nm == "FactoryDecl" {
            String fn = unq(txt(fld(d, "Name")))
            FACTORY_NAMES.push(fn)
            FACTORY_TARGET.push(typeKey(fld(d, "Target")))
            FACTORY_DECLS.push(d)
        }
        if d.nm == "SingletonDecl" {
            String sn = unq(txt(fld(d, "Name")))
            SINGLE_NAMES.push(sn)
            SINGLE_DECLS.push(d)
            N sfs = fld(d, "Fields")
            Int sfi = 0
            while sfi < sfs.el.length() {
                FLD_OWNER.push(sn)
                FLD_NAME.push(unq(txt(fld(sfs.el.get(sfi), "Name"))))
                FLD_TYPE.push(typeKey(fld(sfs.el.get(sfi), "Type")))
                sfi = sfi + 1
            }
            N sms = fld(d, "Methods")
            sfi = 0
            while sfi < sms.el.length() {
                MTH_OWNER.push(sn)
                MTH_NAME.push(unq(txt(fld(sms.el.get(sfi), "Name"))))
                MTH_RET.push(retKey(sms.el.get(sfi)))
                sfi = sfi + 1
            }
        }
        if d.nm == "EnumDecl" {
            String en = unq(txt(fld(d, "Name")))
            ENUM_NAMES.push(en)
            N its = fld(d, "Items")
            Bool data = fld(d, "Fields").el.length() > 0 || fld(d, "Methods").el.length() > 0 || fld(d, "Ctors").el.length() > 0
            if data { DATA_ENUM_NAMES.push(en); DATA_ENUM_DECLS.push(d) }
            Int ij = 0
            while ij < its.el.length() {
                ENUM_ITEM_OWNER.push(en)
                ENUM_ITEM_NAME.push(unq(txt(fld(its.el.get(ij), "Name"))))
                ENUM_ITEM_INDEX.push(ij)
                ij = ij + 1
            }
        }
        if d.nm == "ProtocolDecl" {
            String pn = unq(txt(fld(d, "Name")))
            PROTO_NAMES.push(pn)
            N sigs = fld(d, "Sigs")
            Int pj = 0
            while pj < sigs.el.length() {
                PROTO_OWNER.push(pn)
                PROTO_MNAME.push(unq(txt(fld(sigs.el.get(pj), "Name"))))
                pj = pj + 1
            }
        }
        if d.nm == "StructDecl" {
            String sn = unq(txt(fld(d, "Name")))
            STRUCT_NAMES.push(sn)
            N sfs = fld(d, "Fields")
            Int sfi = 0
            while sfi < sfs.el.length() {
                FLD_OWNER.push(sn)
                FLD_NAME.push(unq(txt(fld(sfs.el.get(sfi), "Name"))))
                FLD_TYPE.push(typeKey(fld(sfs.el.get(sfi), "Type")))
                sfi = sfi + 1
            }
            N sms = fld(d, "Methods")
            sfi = 0
            while sfi < sms.el.length() {
                MTH_OWNER.push(sn)
                MTH_NAME.push(unq(txt(fld(sms.el.get(sfi), "Name"))))
                MTH_RET.push(retKey(sms.el.get(sfi)))
                sfi = sfi + 1
            }
        }
        if d.nm == "TopFunc" {
            if fld(d, "TypePars").el.length() > 0 {
                GEN_FN_DECLS.push(d)
            } else {
                String rk = retKey(d)
                sc.useResult(rk)
                sc.defFn(unq(txt(fld(d, "Name"))), rk)
                scanCalls(fld(d, "Body"))
            }
        }
        i = i + 1
    }
    Int sci = 0
    while sci < decls.el.length() {
        N d = decls.el.get(sci)
        if d.nm == "TopFunc" { scanCls(fld(d, "Body")) }
        if d.nm == "ClassDecl" && fld(d, "TypePars").el.length() == 0 {
            N ms0 = fld(d, "Methods")
            Int mi0 = 0
            while mi0 < ms0.el.length() { scanCls(fld(ms0.el.get(mi0), "Body")); mi0 = mi0 + 1 }
        }
        sci = sci + 1
    }
    i = 0
    while i < decls.el.length() {
        N d = decls.el.get(i)
        if d.nm == "TopFunc" {
            String nm = unq(txt(fld(d, "Name")))
            if nm != "main" && fld(d, "TypePars").el.length() == 0 { emitFunc(d, e, sc) }
        }
        i = i + 1
    }
    i = 0
    while i < decls.el.length() {
        N d = decls.el.get(i)
        if d.nm == "TopFunc" && unq(txt(fld(d, "Name"))) == "main" { emitFunc(d, e, sc) }
        i = i + 1
    }
    emitInstances(e, sc)
    e.add("int main(void) {")
    e.add("    xrt_runtime_init();")
    e.add("    xn_init_vtables();")
    e.add("    xn_init_enums();")
    if SINGLE_NAMES.length() > 0 { e.add("    xn_init_singletons();") }
    e.add("    int64_t xn_r = xn_main();")
    e.add("    rt_gc_collect();")
    e.add("    rt_quarantine_flush();")
    e.add("    return (int)xn_r;")
    scanTupleTypes(unit)
    String res = ""
    if CLS_NAMES.length() > 0 {
        EM ce = new EM()
        ce.tmp = e.tmp
        ce.path = e.path
        Int ci = 0
        while ci < decls.el.length() {
            N d = decls.el.get(ci)
            if d.nm == "ClassDecl" && fld(d, "TypePars").el.length() == 0 { emitClassSection(d, ce) }
            ci = ci + 1
        }
        Int gci = 0
        while gci < GEN_INST_NAME.length() {
            CLS_OVERRIDE = GEN_INST_NAME.get(gci)
            SUB_FROM = ["T"]
            SUB_TO = [GEN_INST_KEY.get(gci)]
            emitClassSection(genClsDecl(GEN_INST_BASE.get(gci)), ce)
            SUB_FROM = []
            SUB_TO = []
            CLS_OVERRIDE = ""
            gci = gci + 1
        }
        e.tmp = ce.tmp
        EM xe = new EM()
        xe.tmp = e.tmp
        xe.path = e.path
        Int xi = 0
        while xi < decls.el.length() {
            N d = decls.el.get(xi)
            if d.nm == "ExtensionDecl" { emitExtensionMethods(d, xe) }
            xi = xi + 1
        }
        e.tmp = xe.tmp
        EM fe = new EM()
        fe.tmp = e.tmp
        fe.path = e.path
        Int fi2 = 0
        while fi2 < decls.el.length() {
            N d = decls.el.get(fi2)
            if d.nm == "ExtensionDecl" {
            String et = typeKey(fld(d, "Target"))
            N ems = fld(d, "Methods")
            Int ei = 0
            while ei < ems.el.length() {
                String emn = unq(txt(fld(ems.el.get(ei), "Name")))
                EXT_TARGET.push(et)
                EXT_NAME.push(emn)
                EXT_CNAME.push("xn_Cls_" + et + "_ext_" + emn + "_" + str(ei + 1))
                ei = ei + 1
            }
            EXT_DECLS.push(d)
        }
        if d.nm == "FactoryDecl" { emitFactoryMethods(d, fe) }
            fi2 = fi2 + 1
        }
        e.tmp = fe.tmp
        List<N> sdecls = sortedClassDecls(decls)
        String cbKey = ""
        if e.usesObjArr { cbKey = e.objArrKey }
        if cbKey == "" {
            Int cbi = 0
            while cbi < FLD_TYPE.length() {
                if isObjArr(FLD_TYPE.get(cbi)) { cbKey = FLD_TYPE.get(cbi) }
                cbi = cbi + 1
            }
        }
        if cbKey == "" {
            Int cbi2 = 0
            while cbi2 < FLD_TYPE.length() {
                if cbKey == "" && (FLD_TYPE.get(cbi2) == "List<Int>" || FLD_TYPE.get(cbi2) == "Int[]") { cbKey = "List<Int>" }
                cbi2 = cbi2 + 1
            }
        }
        if cbKey == "" && e.usesList { cbKey = "List<Int>" }
        if cbKey == "" {
            Int hui = 0
            while hui < decls.el.length() {
                if hasU16In(decls.el.get(hui)) { cbKey = "List<UInt16>"; hui = decls.el.length() }
                else { hui = hui + 1 }
            }
        }
        if cbKey == "" {
            Int hli = 0
            while hli < decls.el.length() {
                if hasListIn(decls.el.get(hli)) { cbKey = "List<Int>"; hli = decls.el.length() }
                else { hli = hli + 1 }
            }
        }
        String cbType = ""
        String cbHelp = ""
        if cbKey != "" {
            cbType = containerTypedef(cbKey)
            if isObjArr(cbKey) { cbHelp = classArrHelperText(cbKey) }
            else if isU16List(cbKey) { cbHelp = u16ArrHelperText() }
            else { cbHelp = arrIHelperText() }
        }
        Bool arrSAdded = false
        if USES_MAP_S_I {
            cbHelp = cbHelp + "\n" + arrSBlock() + mapSIBlock() + strSplitBlock()
            arrSAdded = true
        }
        if USES_MAP_S_S {
            if !arrSAdded { cbHelp = cbHelp + "\n" + arrSBlock() }
            cbHelp = cbHelp + mapSSBlock() + "\n\n\n" + strSplitBlock()
            arrSAdded = true
        }
        if cbHelp.length() > 0 && cbHelp.substring(0, 1) == "\n" { cbHelp = cbHelp.substring(1, cbHelp.length() - 1) }
        String tfp = topFuncProtos(decls)
        List<String> fw = []
        Int pass = 0
        while pass < 2 {
            Int sci2 = 0
            while sci2 < sdecls.length() {
                String ccn = unq(txt(fld(sdecls.get(sci2), "Name")))
                fw.push("typedef struct xn_Cls_" + ccn + " xn_Cls_" + ccn + ";")
                sci2 = sci2 + 1
            }
            Int gti = 0
            List<String> gs0 = genSorted()
            while gti < gs0.length() { fw.push("typedef struct xn_Cls_" + gs0.get(gti) + " xn_Cls_" + gs0.get(gti) + ";"); gti = gti + 1 }
            fw.push("")
            pass = pass + 1
        }
        ci = 0
        while ci < sdecls.length() {
            N d = sdecls.get(ci)
            String ccn = unq(txt(fld(d, "Name")))
            String csx = ""
            if isPrimary(d) { csx = "_1" }
            String cnp = newParamDecls(d)
            fw.push("static xn_Cls_" + ccn + " *xn_Cls_" + ccn + "_new" + csx + "(" + cnp + ");")
            fw.push("static void xn_Cls_" + ccn + "_new" + csx + "_init(xn_Cls_" + ccn + " *o" + (ctorParams(d) == "" ? "" : ", " + ctorParams(d)) + ");")
            if hasDeinit(ccn) { fw.push("static void xn_Cls_" + ccn + "_deinit(xn_Cls_" + ccn + " *self);") }
            if hasProto(ccn) { fw.push("static void *xn_vt_" + ccn + "[" + str(protoSlots(ccn) + 2) + "];") }
            ci = ci + 1
        }
        Int gpi = 0
        List<String> gs1 = genSorted()
        while gpi < gs1.length() {
            String instn = gs1.get(gpi)
            Int gi0 = 0
            while gi0 < GEN_INST_NAME.length() && GEN_INST_NAME.get(gi0) != instn { gi0 = gi0 + 1 }
            N gd = genClsDecl(GEN_INST_BASE.get(gi0))
            SUB_FROM = ["T"]
            SUB_TO = [GEN_INST_KEY.get(gi0)]
            CLS_OVERRIDE = instn
            String gnp = ctorParams(gd)
            if gnp == "" { gnp = "void" }
            fw.push("static xn_Cls_" + instn + " *xn_Cls_" + instn + "_new(" + gnp + ");")
            fw.push("static void xn_Cls_" + instn + "_new_init(xn_Cls_" + instn + " *o" + (ctorParams(gd) == "" ? "" : ", " + ctorParams(gd)) + ");")
            SUB_FROM = []
            SUB_TO = []
            CLS_OVERRIDE = ""
            gpi = gpi + 1
        }
        if EXT_TARGET.length() > 0 { fw.push("") }
        Int exi = 0
        while exi < decls.el.length() {
            N d = decls.el.get(exi)
            if d.nm == "ExtensionDecl" {
                String et2 = typeKey(fld(d, "Target"))
                N ems2 = fld(d, "Methods")
                Int emi = 0
                while emi < ems2.el.length() {
                    String emn2 = unq(txt(fld(ems2.el.get(emi), "Name")))
                    String ert2 = retKey(ems2.el.get(emi))
                    fw.push("static " + cType(ert2) + " xn_Cls_" + et2 + "_ext_" + emn2 + "_" + str(emi + 1) + "(xn_Cls_" + et2 + " *self);")
                    emi = emi + 1
                }
            }
            exi = exi + 1
        }
        fw.push("")
        fw.push("")
        String fwj = ""
        Bool fwi2 = false
        Int fwk = 0
        while fwk < fw.length() {
            fwj = fwj + fw.get(fwk) + "\n"
            if !fwi2 && fw.get(fwk) == "" {
                String dts0 = dynContainerTypedefs()
                if dts0 != "" { fwj = fwj + dts0 + "\n" }
                fwi2 = true
            }
            fwk = fwk + 1
        }
        String rtd = resultTypedefsSorted(sc)
        if rtd != "" { fwj = fwj.substring(0, fwj.length() - 1) }
        res = PRELUDE_PRE_A + protoTypedefs() + PRELUDE_B1 + fnTypedefs() + enumTypedefs() + PRELUDE_B2 + enumNameDefs() + PRELUDE_B3 + PRELUDE_FATAL_MID.substring(0, PRELUDE_FATAL_MID.length() - 1) + fwj + rtd + (cbHelp != "" ? cbHelp + "\n" : "") + tfp + "static int64_t xn_main();\n\n" + joinLines(ce.ls).substring(0, joinLines(ce.ls).length() - 1) + PRELUDE_VT_OPEN + vtableInit(unit) + PRELUDE_VT_CLOSE + joinLines(xe.ls) + joinLines(fe.ls) + PRELUDE_TAIL_B
    } else if DATA_ENUM_NAMES.length() > 0 {
        EM de = new EM()
        de.tmp = e.tmp
        de.path = e.path
        Int di = 0
        while di < DATA_ENUM_DECLS.length() { emitDataEnum(DATA_ENUM_DECLS.get(di), de); di = di + 1 }
        EM dme = new EM()
        dme.tmp = de.tmp
        dme.path = e.path
        di = 0
        while di < DATA_ENUM_DECLS.length() { emitDataEnumMethods(DATA_ENUM_DECLS.get(di), dme); di = di + 1 }
        e.tmp = dme.tmp
        res = PRELUDE_PRE_A + protoTypedefs() + PRELUDE_B1 + fnTypedefs() + enumTypedefs() + PRELUDE_B2 + enumNameDefs() + PRELUDE_B3 + joinLines(de.ls) + PRELUDE_FATAL_MID + "static int64_t xn_main();\n" + PRELUDE_VT_OPEN + vtableInit(unit) + PRELUDE_VT_CLOSE + joinLines(dme.ls) + PRELUDE_EN_OPEN + dataEnumInit() + PRELUDE_EN_CLOSE
    } else if SINGLE_NAMES.length() > 0 {
        List<String> fw = []
        Int si = 0
        while si < SINGLE_DECLS.length() {
            String sn = unq(txt(fld(SINGLE_DECLS.get(si), "Name")))
            fw.push("typedef struct xn_Single_" + sn + " xn_Single_" + sn + ";")
            fw.push("static xn_Single_" + sn + " *xn_single_" + sn + ";")
            N ms0 = fld(SINGLE_DECLS.get(si), "Methods")
            Int mj0 = 0
            while mj0 < ms0.el.length() {
                N m0 = ms0.el.get(mj0)
                String rt0 = retKey(m0)
                String sg0 = "xn_Single_" + sn + "_" + unq(txt(fld(m0, "Name"))) + "(xn_Single_" + sn + " *self)"
                fw.push("static " + cType(rt0) + " " + sg0 + ";")
                mj0 = mj0 + 1
            }
            si = si + 1
        }
        Int exi = 0
        while exi < decls.el.length() {
            N d = decls.el.get(exi)
            if d.nm == "ExtensionDecl" {
                String et2 = typeKey(fld(d, "Target"))
                N ems2 = fld(d, "Methods")
                Int emi = 0
                while emi < ems2.el.length() {
                    String emn2 = unq(txt(fld(ems2.el.get(emi), "Name")))
                    String ert2 = retKey(ems2.el.get(emi))
                    fw.push("static " + cType(ert2) + " xn_Cls_" + et2 + "_ext_" + emn2 + "_" + str(emi + 1) + "(xn_Cls_" + et2 + " *self);")
                    emi = emi + 1
                }
            }
            exi = exi + 1
        }
        fw.push("")
        fw.push("")
        EM ce = new EM()
        ce.tmp = e.tmp
        ce.path = e.path
        si = 0
        while si < SINGLE_DECLS.length() { emitSingletonSection(SINGLE_DECLS.get(si), ce); si = si + 1 }
        e.tmp = ce.tmp
        String sinit = ""
        si = 0
        while si < SINGLE_DECLS.length() {
            sinit = sinit + "    xn_Single_" + unq(txt(fld(SINGLE_DECLS.get(si), "Name"))) + "_init();\n"
            si = si + 1
        }
        res = PRELUDE_PRE_A + protoTypedefs() + PRELUDE_B1 + fnTypedefs() + enumTypedefs() + PRELUDE_B2 + enumNameDefs() + PRELUDE_B3 + PRELUDE_FATAL_MID.substring(0, PRELUDE_FATAL_MID.length() - 1) + joinLines(fw) + "static int64_t xn_main();\n" + PRELUDE_VT_OPEN + vtableInit(unit) + PRELUDE_VT_CLOSE + joinLines(ce.ls) + "static void xn_init_singletons(void) {\n" + sinit + "}\n\n" + PRELUDE_TAIL_B
    } else if ENUM_NAMES.length() > 0 {
        res = PRELUDE_PRE_A + protoTypedefs() + PRELUDE_B1 + fnTypedefs() + enumTypedefs() + PRELUDE_B2 + enumNameDefs() + PRELUDE_B3 + PRELUDE_FATAL_MID + "static int64_t xn_main();\n" + PRELUDE_TAIL
    } else if STRUCT_NAMES.length() > 0 {
        EM ce = new EM()
        ce.tmp = e.tmp
        ce.path = e.path
        List<String> early = []
        List<String> methods = []
        EM ee = new EM()
        ee.tmp = e.tmp
        ee.path = e.path
        Int ci = 0
        while ci < decls.el.length() {
            N d = decls.el.get(ci)
            if d.nm == "ExtensionDecl" {
            String et = typeKey(fld(d, "Target"))
            N ems = fld(d, "Methods")
            Int ei = 0
            while ei < ems.el.length() {
                String emn = unq(txt(fld(ems.el.get(ei), "Name")))
                EXT_TARGET.push(et)
                EXT_NAME.push(emn)
                EXT_CNAME.push("xn_Cls_" + et + "_ext_" + emn + "_" + str(ei + 1))
                ei = ei + 1
            }
            EXT_DECLS.push(d)
        }
        if d.nm == "FactoryDecl" {
            String fn = unq(txt(fld(d, "Name")))
            FACTORY_NAMES.push(fn)
            FACTORY_TARGET.push(typeKey(fld(d, "Target")))
            FACTORY_DECLS.push(d)
        }
        if d.nm == "SingletonDecl" {
            String sn = unq(txt(fld(d, "Name")))
            SINGLE_NAMES.push(sn)
            SINGLE_DECLS.push(d)
            N sfs = fld(d, "Fields")
            Int sfi = 0
            while sfi < sfs.el.length() {
                FLD_OWNER.push(sn)
                FLD_NAME.push(unq(txt(fld(sfs.el.get(sfi), "Name"))))
                FLD_TYPE.push(typeKey(fld(sfs.el.get(sfi), "Type")))
                sfi = sfi + 1
            }
            N sms = fld(d, "Methods")
            sfi = 0
            while sfi < sms.el.length() {
                MTH_OWNER.push(sn)
                MTH_NAME.push(unq(txt(fld(sms.el.get(sfi), "Name"))))
                MTH_RET.push(retKey(sms.el.get(sfi)))
                sfi = sfi + 1
            }
        }
        if d.nm == "EnumDecl" {
            String en = unq(txt(fld(d, "Name")))
            ENUM_NAMES.push(en)
            N its = fld(d, "Items")
            Bool data = fld(d, "Fields").el.length() > 0 || fld(d, "Methods").el.length() > 0 || fld(d, "Ctors").el.length() > 0
            if data { DATA_ENUM_NAMES.push(en); DATA_ENUM_DECLS.push(d) }
            Int ij = 0
            while ij < its.el.length() {
                ENUM_ITEM_OWNER.push(en)
                ENUM_ITEM_NAME.push(unq(txt(fld(its.el.get(ij), "Name"))))
                ENUM_ITEM_INDEX.push(ij)
                ij = ij + 1
            }
        }
        if d.nm == "ProtocolDecl" {
            String pn = unq(txt(fld(d, "Name")))
            PROTO_NAMES.push(pn)
            N sigs = fld(d, "Sigs")
            Int pj = 0
            while pj < sigs.el.length() {
                PROTO_OWNER.push(pn)
                PROTO_MNAME.push(unq(txt(fld(sigs.el.get(pj), "Name"))))
                pj = pj + 1
            }
        }
        if d.nm == "StructDecl" { emitStructEarly(d, ee) }
            ci = ci + 1
        }
        EM me = new EM()
        me.tmp = ee.tmp
        me.path = e.path
        ci = 0
        while ci < decls.el.length() {
            N d = decls.el.get(ci)
            if d.nm == "ExtensionDecl" {
            String et = typeKey(fld(d, "Target"))
            N ems = fld(d, "Methods")
            Int ei = 0
            while ei < ems.el.length() {
                String emn = unq(txt(fld(ems.el.get(ei), "Name")))
                EXT_TARGET.push(et)
                EXT_NAME.push(emn)
                EXT_CNAME.push("xn_Cls_" + et + "_ext_" + emn + "_" + str(ei + 1))
                ei = ei + 1
            }
            EXT_DECLS.push(d)
        }
        if d.nm == "FactoryDecl" {
            String fn = unq(txt(fld(d, "Name")))
            FACTORY_NAMES.push(fn)
            FACTORY_TARGET.push(typeKey(fld(d, "Target")))
            FACTORY_DECLS.push(d)
        }
        if d.nm == "SingletonDecl" {
            String sn = unq(txt(fld(d, "Name")))
            SINGLE_NAMES.push(sn)
            SINGLE_DECLS.push(d)
            N sfs = fld(d, "Fields")
            Int sfi = 0
            while sfi < sfs.el.length() {
                FLD_OWNER.push(sn)
                FLD_NAME.push(unq(txt(fld(sfs.el.get(sfi), "Name"))))
                FLD_TYPE.push(typeKey(fld(sfs.el.get(sfi), "Type")))
                sfi = sfi + 1
            }
            N sms = fld(d, "Methods")
            sfi = 0
            while sfi < sms.el.length() {
                MTH_OWNER.push(sn)
                MTH_NAME.push(unq(txt(fld(sms.el.get(sfi), "Name"))))
                MTH_RET.push(retKey(sms.el.get(sfi)))
                sfi = sfi + 1
            }
        }
        if d.nm == "EnumDecl" {
            String en = unq(txt(fld(d, "Name")))
            ENUM_NAMES.push(en)
            N its = fld(d, "Items")
            Bool data = fld(d, "Fields").el.length() > 0 || fld(d, "Methods").el.length() > 0 || fld(d, "Ctors").el.length() > 0
            if data { DATA_ENUM_NAMES.push(en); DATA_ENUM_DECLS.push(d) }
            Int ij = 0
            while ij < its.el.length() {
                ENUM_ITEM_OWNER.push(en)
                ENUM_ITEM_NAME.push(unq(txt(fld(its.el.get(ij), "Name"))))
                ENUM_ITEM_INDEX.push(ij)
                ij = ij + 1
            }
        }
        if d.nm == "ProtocolDecl" {
            String pn = unq(txt(fld(d, "Name")))
            PROTO_NAMES.push(pn)
            N sigs = fld(d, "Sigs")
            Int pj = 0
            while pj < sigs.el.length() {
                PROTO_OWNER.push(pn)
                PROTO_MNAME.push(unq(txt(fld(sigs.el.get(pj), "Name"))))
                pj = pj + 1
            }
        }
        if d.nm == "StructDecl" { emitStructMethods(d, me) }
            ci = ci + 1
        }
        e.tmp = me.tmp
        res = PRELUDE_PRE_A + protoTypedefs() + PRELUDE_B1 + fnTypedefs() + enumTypedefs() + PRELUDE_B2 + enumNameDefs() + PRELUDE_B3 + joinLines(ee.ls) + PRELUDE_FATAL_MID + "static int64_t xn_main();\n" + PRELUDE_VT_OPEN + vtableInit(unit) + PRELUDE_VT_CLOSE + joinLines(me.ls) + PRELUDE_TAIL_B
    } else if e.usesAny {
        res = PRELUDE_ANY
    } else if e.usesTArr {
        res = PRELUDE_TARR
    } else if e.usesList || e.hasMap || e.hasSet {
        if e.hasMap {
            if e.hasGetOr { res = PRELUDE_CONT } else { res = PRELUDE_MAPSET }
        } else {
            res = PRELUDE_ARR
        }
    } else {
        res = PRELUDE_HEAD
        if TUPLE_KEYS.length() > 0 { res = res.substring(0, res.length() - 1) }
        res = res + tupleTypedefs()
        if TUPLE_KEYS.length() > 0 { res = res + "\n\n" }
        if sc.resultTypes.length() > 0 {
            res = res.substring(0, res.length() - 1)
            Int k = 0
            while k < sc.resultTypes.length() {
                String rk = sc.resultTypes.get(k)
                String vt = resultVal(rk)
                String et = resultErr(rk)
                res = res + "typedef struct { int ok; " + decl(resultValC(vt), "v") + "; " + errMember(resultErrC(et)) + "; } " + cType(rk) + ";\n"
                k = k + 1
            }
            res = res + "\n"
        }
        i = 0
        while i < decls.el.length() {
            N d = decls.el.get(i)
            if d.nm == "TopFunc" {
                String nm = unq(txt(fld(d, "Name")))
                if nm != "main" && fld(d, "TypePars").el.length() == 0 {
                    String rk = retKey(d)
                    res = res + "static " + cType(rk) + " xn_" + nm + "(" + paramsOf(d) + ");\n"
                }
            }
            i = i + 1
        }
        res = res + "static int64_t xn_main();\n"
        res = res + genProtos()
        res = res + PRELUDE_TAIL
    }
    e.add("}")
    res = res + ""
    Int j = 0
    while j < e.ls.length() {
        res = res + e.ls.get(j) + "\n"
        j = j + 1
    }
    if FFI_E_NAME.length() > 0 {
        Int fp = res.indexOf("static void xn_fatal_oob(void);")
        if fp >= 0 { res = res.substring(0, fp) + ffiSupportText() + "\n" + res.substring(fp, res.length() - fp) }
    }
    return res.substring(0, res.length() - 1)
}

static Int JSON_I = 0
static Int jsonHex1(String c) {
    Int i = "0123456789abcdef".indexOf(c)
    if i >= 0 { return i }
    return "0123456789ABCDEF".indexOf(c)
}
static Int jsonHex4(String s, Int p) {
    return jsonHex1(s.substring(p, 1)) * 4096 + jsonHex1(s.substring(p + 1, 1)) * 256 + jsonHex1(s.substring(p + 2, 1)) * 16 + jsonHex1(s.substring(p + 3, 1))
}
static String jsonChr(Int code) {
    if code == 34 { return "\"" }
    if code == 38 { return "&" }
    if code == 39 { return "'" }
    if code == 47 { return "/" }
    if code == 60 { return "<" }
    if code == 62 { return ">" }
    if code == 92 { return "\\" }
    if code == 9 { return "\t" }
    if code == 10 { return "\n" }
    if code == 13 { return "\r" }
    if code >= 32 && code < 127 { return "" }
    return ""
}
static String jsonStr(String s, Int p) {
    String b = ""
    Int i = p
    while i < s.length() {
        String c = s.substring(i, 1)
        if c == "\"" { JSON_I = i + 1; return b }
        if c == "\\" {
            String e = s.substring(i + 1, 1)
            if e == "n" { b = b + "\n"; i = i + 2 }
            else if e == "r" { b = b + "\r"; i = i + 2 }
            else if e == "t" { b = b + "\t"; i = i + 2 }
            else if e == "\"" { b = b + "\""; i = i + 2 }
            else if e == "\\" { b = b + "\\"; i = i + 2 }
            else if e == "/" { b = b + "/"; i = i + 2 }
            else if e == "u" { b = b + jsonChr(jsonHex4(s, i + 2)); i = i + 6 }
            else { b = b + e; i = i + 2 }
        } else { b = b + c; i = i + 1 }
    }
    JSON_I = i
    return b
}
static N parseBundle(String text) {
    List<N> units = []
    Int i = 0
    while true {
        String rest = text.substring(i, text.length() - i)
        Int kr = rest.indexOf("\"ast\"")
        if kr < 0 { i = text.length(); break }
        Int k = i + kr
        String afterKey = text.substring(k + 5, text.length() - k - 5)
        Int c = k + 5 + afterKey.indexOf(":")
        String afterColon = text.substring(c + 1, text.length() - c - 1)
        Int q = c + 1 + afterColon.indexOf("\"")
        String ast = jsonStr(text, q + 1)
        i = JSON_I
        if ast.indexOf("(xnast v1 ") == 0 && ast.length() > 11 { ast = ast.substring(10, ast.length() - 11) }
        AP ap = new AP(ast)
        units.push(ap.val())
    }
    if units.length() == 0 { return new N() }
    N base = units.get(0)
    N bd = fld(base, "Decls")
    Int u = 1
    while u < units.length() {
        N du = fld(units.get(u), "Decls")
        Int j = 0
        while j < du.el.length() { bd.el.push(du.el.get(j)); j = j + 1 }
        u = u + 1
    }
    return base
}

static Int main(String[] args) {
    if args.length() < 1 {
        print("xnullc: 用法：xnullc <entryPath> [--ast-file <p>] [--project <text>] [--bundle-file <p>] | <entryPath> <ast> [project] [bundle]")
        return 2
    }
    String path = args.get(0)
    String astFile = ""
    String bundleFile = ""
    String project = ""
    List<String> pos = []
    Int ai = 1
    while ai < args.length() {
        String a = args.get(ai)
        if a == "--ast-file" && ai + 1 < args.length() { astFile = args.get(ai + 1); ai = ai + 2 }
        else if a == "--bundle-file" && ai + 1 < args.length() { bundleFile = args.get(ai + 1); ai = ai + 2 }
        else if a == "--project" && ai + 1 < args.length() { project = args.get(ai + 1); ai = ai + 2 }
        else { pos.push(a); ai = ai + 1 }
    }
    String ast = ""
    if astFile != "" { ast = readFileText(astFile) }
    else if pos.length() > 0 { ast = pos.get(0) }
    if ast == "" {
        print("xnullc: 缺少 AST：请提供 --ast-file 或位置参数 <ast>")
        return 2
    }
    String proj = project
    if proj == "" && pos.length() > 1 { proj = pos.get(1) }
    if proj != "" { parseRegistry(proj) }
    String bundle = ""
    if bundleFile != "" { bundle = readFileText(bundleFile) }
    else if pos.length() > 2 { bundle = pos.get(2) }
    if bundle != "" {
        N bunit = parseBundle(bundle)
        print(emitUnit(bunit, path))
        return 0
    }
    if ast.indexOf("(xnast v1 ") == 0 && ast.length() > 11 { ast = ast.substring(10, ast.length() - 11) }
    AP ap = new AP(ast)
    N unit = ap.val()
    print(emitUnit(unit, path))
    return 0
}
