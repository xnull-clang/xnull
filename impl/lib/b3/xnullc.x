// B3-03：xnullc Result/try/defer（XNull 版 AST -> C）。
//
// 输入：<entryPath> <xnast v1 AST dump>
// 输出：与 Go `xnull build --emit-c` 口径一致的 C 文本。
// 覆盖：Result 实例化、Ok/Err、isOk/isErr/value/error/unwrapOr、try、defer/errdefer、throw。

static String PRELUDE_HEAD = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\n\n";
static String PRELUDE_PRE_FATAL = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\n";
static String PRELUDE_FATAL_MID = "static void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\n\n";
static String PRELUDE_TAIL_A = "\nstatic void xn_init_vtables(void) {\n}\n\n";
static String PRELUDE_TAIL_B = "static void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_TAIL = "\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_ARR = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;\n\n\nstatic void xn_arr_i_deinit(void *p) {\n    xn_arr_i *a = (xn_arr_i *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_i = { \"List\", sizeof(xn_arr_i), xn_arr_i_deinit, NULL };\n\nstatic xn_arr_i *xn_arr_i_new(size_t cap) {\n    xn_arr_i *a = (xn_arr_i *)xn_gc_new(&RT_TYPE_xn_arr_i);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_i) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(int64_t) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_i_push(xn_arr_i *a, int64_t v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_i_set(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic int64_t xn_arr_i_remove(xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    int64_t old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_i_insert(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_i_clear(xn_arr_i *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_i_join(xn_arr_i *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, xn_str_int(a->data[i]));\n    }\n    return res;\n}\n\nstatic int64_t xn_main();\n\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_MAPSET = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;\n\ntypedef struct { rt_header hdr; xn_arr_i *a; } xn_set_i;\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *keys; int64_t *vals; } xn_map_s_i;\n\n\nstatic void xn_arr_i_deinit(void *p) {\n    xn_arr_i *a = (xn_arr_i *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_i = { \"List\", sizeof(xn_arr_i), xn_arr_i_deinit, NULL };\n\nstatic xn_arr_i *xn_arr_i_new(size_t cap) {\n    xn_arr_i *a = (xn_arr_i *)xn_gc_new(&RT_TYPE_xn_arr_i);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_i) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(int64_t) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_i_push(xn_arr_i *a, int64_t v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_i_set(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic int64_t xn_arr_i_remove(xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    int64_t old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_i_insert(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_i_clear(xn_arr_i *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_i_join(xn_arr_i *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, xn_str_int(a->data[i]));\n    }\n    return res;\n}\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *data; } xn_arr_s;\n\nstatic void xn_arr_s_scan(void *p, void (*visit)(void *)) {\n    xn_arr_s *a = (xn_arr_s *)p;\n    if (a->data == NULL) { return; }\n    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }\n}\n\nstatic void xn_arr_s_deinit(void *p) {\n    xn_arr_s *a = (xn_arr_s *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_s = { \"List\", sizeof(xn_arr_s), xn_arr_s_deinit, xn_arr_s_scan };\n\nstatic xn_arr_s *xn_arr_s_new(size_t cap) {\n    xn_arr_s *a = (xn_arr_s *)xn_gc_new(&RT_TYPE_xn_arr_s);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_s) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(rt_string *) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_s_push(xn_arr_s *a, rt_string * v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic rt_string * xn_arr_s_get(const xn_arr_s *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_s_set(xn_arr_s *a, int64_t i, rt_string * v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic rt_string * xn_arr_s_remove(xn_arr_s *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    rt_string * old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_s_insert(xn_arr_s *a, int64_t i, rt_string * v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_s_clear(xn_arr_s *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_s_join(xn_arr_s *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, rt_string_new(a->data[i]->bytes, a->data[i]->len));\n    }\n    return res;\n}\n\nstatic void xn_set_i_scan(void *p, void (*visit)(void *)) {\n    xn_set_i *s = (xn_set_i *)p;\n    if (s->a != NULL) { visit(s->a); }\n}\n\nstatic void xn_set_i_deinit(void *p) {\n    xn_set_i *s = (xn_set_i *)p;\n    s->a = NULL; /* 数组是 GC 对象，由 GC 回收 */\n}\n\nstatic const rt_type RT_TYPE_xn_set_i = { \"Set\", sizeof(xn_set_i), xn_set_i_deinit, xn_set_i_scan };\n\nstatic xn_set_i *xn_set_i_new(void) {\n    xn_set_i *s = (xn_set_i *)xn_gc_new(&RT_TYPE_xn_set_i);\n    memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_i) - sizeof(rt_header));\n    s->a = xn_arr_i_new(4);\n    return s;\n}\n\nstatic int xn_set_i_add(xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) { return 0; }\n    }\n    xn_arr_i_push(s->a, v);\n    return 1;\n}\n\nstatic int xn_set_i_has(const xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) { return 1; }\n    }\n    return 0;\n}\n\nstatic int64_t xn_set_i_at(const xn_set_i *s, int64_t i) {\n    if (i < 0 || (size_t)i >= s->a->len) { xn_fatal_oob(); }\n    return s->a->data[i];\n}\n\nstatic int xn_set_i_remove(xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) {\n            for (size_t j = i; j + 1 < s->a->len; j++) {\n                s->a->data[j] = s->a->data[j + 1];\n            }\n            s->a->len--;\n            return 1;\n        }\n    }\n    return 0;\n}\n\nstatic void xn_set_i_clear(xn_set_i *s) { xn_arr_i_clear(s->a); }\n\nstatic void xn_map_s_i_scan(void *p, void (*visit)(void *)) {\n    xn_map_s_i *m = (xn_map_s_i *)p;\n    if (m->keys != NULL) { for (size_t i = 0; i < m->len; i++) { visit(m->keys[i]); } }\n}\n\nstatic void xn_map_s_i_deinit(void *p) {\n    xn_map_s_i *m = (xn_map_s_i *)p;\n    if (m->keys != NULL) {\n        free(m->keys);\n        m->keys = NULL;\n    }\n    if (m->vals != NULL) {\n        free(m->vals);\n        m->vals = NULL;\n    }\n    m->len = 0;\n    m->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_map_s_i = { \"Map\", sizeof(xn_map_s_i), xn_map_s_i_deinit, xn_map_s_i_scan };\n\nstatic xn_map_s_i *xn_map_s_i_new(size_t cap) {\n    xn_map_s_i *m = (xn_map_s_i *)xn_gc_new(&RT_TYPE_xn_map_s_i);\n    memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_s_i) - sizeof(rt_header));\n    m->cap = cap ? cap : 4;\n    m->keys = malloc(sizeof(rt_string *) * m->cap);\n    m->vals = malloc(sizeof(int64_t) * m->cap);\n    if (m->keys == NULL || m->vals == NULL) { abort(); }\n    return m;\n}\n\nstatic long xn_map_s_i_find(const xn_map_s_i *m, rt_string * key) {\n    for (size_t i = 0; i < m->len; i++) {\n        if (m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0) { return (long)i; }\n    }\n    return -1;\n}\n\nstatic void xn_map_s_i_put(xn_map_s_i *m, rt_string * key, int64_t val) {\n    long i = xn_map_s_i_find(m, key);\n    if (i >= 0) {\n        m->vals[i] = val;\n        return;\n    }\n    if (m->len == m->cap) {\n        m->cap *= 2;\n        m->keys = realloc(m->keys, sizeof(rt_string *) * m->cap);\n        m->vals = realloc(m->vals, sizeof(int64_t) * m->cap);\n        if (m->keys == NULL || m->vals == NULL) { abort(); }\n    }\n    m->keys[m->len] = key;\n    m->vals[m->len] = val;\n    m->len++;\n}\n\nstatic int xn_map_s_i_has(const xn_map_s_i *m, rt_string * key) { return xn_map_s_i_find(m, key) >= 0; }\n\nstatic int64_t xn_map_s_i_get_or(const xn_map_s_i *m, rt_string * key, int64_t dflt) {\n    long i = xn_map_s_i_find(m, key);\n    return i >= 0 ? m->vals[i] : dflt;\n}\n\nstatic int xn_map_s_i_remove(xn_map_s_i *m, rt_string * key) {\n    long i = xn_map_s_i_find(m, key);\n    if (i < 0) { return 0; }\n    for (size_t j = (size_t)i; j + 1 < m->len; j++) {\n        m->keys[j] = m->keys[j + 1];\n        m->vals[j] = m->vals[j + 1];\n    }\n    m->len--;\n    return 1;\n}\n\nstatic void xn_map_s_i_clear(xn_map_s_i *m) {\n    m->len = 0;\n}\n\nstatic int xn_map_s_i_cmp_key(rt_string * a, rt_string * b) {\n    size_t n = a->len < b->len ? a->len : b->len;\n    int c = memcmp(a->bytes, b->bytes, n);\n    if (c != 0) { return c; }\n    return (a->len > b->len) - (a->len < b->len);\n}\n\nstatic void xn_map_s_i_sort_idx(const xn_map_s_i *m, size_t *idx) {\n    for (size_t i = 1; i < m->len; i++) {\n        size_t x = idx[i];\n        size_t j = i;\n        while (j > 0 && xn_map_s_i_cmp_key(m->keys[idx[j - 1]], m->keys[x]) > 0) {\n            idx[j] = idx[j - 1];\n            j--;\n        }\n        idx[j] = x;\n    }\n}\n\nstatic xn_arr_s *xn_map_s_i_keys(const xn_map_s_i *m) {\n    xn_arr_s *out = xn_arr_s_new(m->len);\n    if (m->len == 0) { return out; }\n    size_t *idx = malloc(sizeof(size_t) * m->len);\n    if (idx == NULL) { abort(); }\n    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }\n    xn_map_s_i_sort_idx(m, idx);\n    for (size_t i = 0; i < m->len; i++) { xn_arr_s_push(out, m->keys[idx[i]]); }\n    free(idx);\n    return out;\n}\n\nstatic xn_arr_i *xn_map_s_i_values(const xn_map_s_i *m) {\n    xn_arr_i *out = xn_arr_i_new(m->len);\n    if (m->len == 0) { return out; }\n    size_t *idx = malloc(sizeof(size_t) * m->len);\n    if (idx == NULL) { abort(); }\n    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }\n    xn_map_s_i_sort_idx(m, idx);\n    for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(out, m->vals[idx[i]]); }\n    free(idx);\n    return out;\n}\n\nstatic xn_opt_i xn_map_s_i_get(const xn_map_s_i *m, rt_string * key) {\n    xn_opt_i r;\n    long i = xn_map_s_i_find(m, key);\n    if (i < 0) { r.has = 0; r.v = 0; return r; }\n    r.has = 1;\n    r.v = m->vals[i];\n    return r;\n}\n\n\nstatic xn_arr_s *xn_str_split(rt_string *s, rt_string *sep) {\n    xn_arr_s *out = xn_arr_s_new(4);\n    if (sep->len == 0) {\n        rt_string *t = rt_string_new(s->bytes, s->len);\n        xn_arr_s_push(out, t);\n        rt_release(t);\n        return out;\n    }\n    size_t start = 0, i = 0;\n    while (i + sep->len <= s->len) {\n        if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) {\n            rt_string *t = rt_string_new(s->bytes + start, i - start);\n            xn_arr_s_push(out, t);\n            rt_release(t);\n            i += sep->len;\n            start = i;\n        } else {\n            i++;\n        }\n    }\n    rt_string *last = rt_string_new(s->bytes + start, s->len - start);\n    xn_arr_s_push(out, last);\n    rt_release(last);\n    return out;\n}\nstatic int64_t xn_main();\n\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";
static String PRELUDE_CONT = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;\n\ntypedef struct { rt_header hdr; xn_arr_i *a; } xn_set_i;\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *keys; int64_t *vals; } xn_map_s_i;\n\n\nstatic void xn_arr_i_deinit(void *p) {\n    xn_arr_i *a = (xn_arr_i *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_i = { \"List\", sizeof(xn_arr_i), xn_arr_i_deinit, NULL };\n\nstatic xn_arr_i *xn_arr_i_new(size_t cap) {\n    xn_arr_i *a = (xn_arr_i *)xn_gc_new(&RT_TYPE_xn_arr_i);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_i) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(int64_t) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_i_push(xn_arr_i *a, int64_t v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_i_set(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic int64_t xn_arr_i_remove(xn_arr_i *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    int64_t old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_i_insert(xn_arr_i *a, int64_t i, int64_t v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(int64_t) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_i_clear(xn_arr_i *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_i_join(xn_arr_i *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, xn_str_int(a->data[i]));\n    }\n    return res;\n}\n\ntypedef struct { rt_header hdr; size_t len; size_t cap; rt_string * *data; } xn_arr_s;\n\nstatic void xn_arr_s_scan(void *p, void (*visit)(void *)) {\n    xn_arr_s *a = (xn_arr_s *)p;\n    if (a->data == NULL) { return; }\n    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }\n}\n\nstatic void xn_arr_s_deinit(void *p) {\n    xn_arr_s *a = (xn_arr_s *)p;\n    if (a->data != NULL) {\n        free(a->data);\n        a->data = NULL;\n    }\n    a->len = 0;\n    a->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_arr_s = { \"List\", sizeof(xn_arr_s), xn_arr_s_deinit, xn_arr_s_scan };\n\nstatic xn_arr_s *xn_arr_s_new(size_t cap) {\n    xn_arr_s *a = (xn_arr_s *)xn_gc_new(&RT_TYPE_xn_arr_s);\n    memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_s) - sizeof(rt_header));\n    a->cap = cap ? cap : 4;\n    a->data = malloc(sizeof(rt_string *) * a->cap);\n    if (a->data == NULL) { abort(); }\n    return a;\n}\n\nstatic void xn_arr_s_push(xn_arr_s *a, rt_string * v) {\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    a->data[a->len++] = v;\n}\n\nstatic rt_string * xn_arr_s_get(const xn_arr_s *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    return a->data[i];\n}\n\nstatic void xn_arr_s_set(xn_arr_s *a, int64_t i, rt_string * v) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    a->data[i] = v;\n}\n\nstatic rt_string * xn_arr_s_remove(xn_arr_s *a, int64_t i) {\n    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }\n    rt_string * old = a->data[i];\n    for (size_t j = (size_t)i; j + 1 < a->len; j++) {\n        a->data[j] = a->data[j + 1];\n    }\n    a->len--;\n    return old;\n}\n\nstatic void xn_arr_s_insert(xn_arr_s *a, int64_t i, rt_string * v) {\n    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }\n    if (a->len == a->cap) {\n        a->cap *= 2;\n        a->data = realloc(a->data, sizeof(rt_string *) * a->cap);\n        if (a->data == NULL) { abort(); }\n    }\n    for (size_t j = a->len; j > (size_t)i; j--) {\n        a->data[j] = a->data[j - 1];\n    }\n    a->data[i] = v;\n    a->len++;\n}\n\nstatic void xn_arr_s_clear(xn_arr_s *a) {\n    a->len = 0;\n}\n\nstatic rt_string *xn_arr_s_join(xn_arr_s *a, rt_string *sep) {\n    rt_string *res = rt_string_from_c(\"\");\n    for (size_t i = 0; i < a->len; i++) {\n        if (i > 0) {\n            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));\n        }\n        res = xn_concat(res, rt_string_new(a->data[i]->bytes, a->data[i]->len));\n    }\n    return res;\n}\n\nstatic void xn_set_i_scan(void *p, void (*visit)(void *)) {\n    xn_set_i *s = (xn_set_i *)p;\n    if (s->a != NULL) { visit(s->a); }\n}\n\nstatic void xn_set_i_deinit(void *p) {\n    xn_set_i *s = (xn_set_i *)p;\n    s->a = NULL; /* 数组是 GC 对象，由 GC 回收 */\n}\n\nstatic const rt_type RT_TYPE_xn_set_i = { \"Set\", sizeof(xn_set_i), xn_set_i_deinit, xn_set_i_scan };\n\nstatic xn_set_i *xn_set_i_new(void) {\n    xn_set_i *s = (xn_set_i *)xn_gc_new(&RT_TYPE_xn_set_i);\n    memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_i) - sizeof(rt_header));\n    s->a = xn_arr_i_new(4);\n    return s;\n}\n\nstatic int xn_set_i_add(xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) { return 0; }\n    }\n    xn_arr_i_push(s->a, v);\n    return 1;\n}\n\nstatic int xn_set_i_has(const xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) { return 1; }\n    }\n    return 0;\n}\n\nstatic int64_t xn_set_i_at(const xn_set_i *s, int64_t i) {\n    if (i < 0 || (size_t)i >= s->a->len) { xn_fatal_oob(); }\n    return s->a->data[i];\n}\n\nstatic int xn_set_i_remove(xn_set_i *s, int64_t v) {\n    for (size_t i = 0; i < s->a->len; i++) {\n        if (s->a->data[i] == v) {\n            for (size_t j = i; j + 1 < s->a->len; j++) {\n                s->a->data[j] = s->a->data[j + 1];\n            }\n            s->a->len--;\n            return 1;\n        }\n    }\n    return 0;\n}\n\nstatic void xn_set_i_clear(xn_set_i *s) { xn_arr_i_clear(s->a); }\n\nstatic void xn_map_s_i_scan(void *p, void (*visit)(void *)) {\n    xn_map_s_i *m = (xn_map_s_i *)p;\n    if (m->keys != NULL) { for (size_t i = 0; i < m->len; i++) { visit(m->keys[i]); } }\n}\n\nstatic void xn_map_s_i_deinit(void *p) {\n    xn_map_s_i *m = (xn_map_s_i *)p;\n    if (m->keys != NULL) {\n        free(m->keys);\n        m->keys = NULL;\n    }\n    if (m->vals != NULL) {\n        free(m->vals);\n        m->vals = NULL;\n    }\n    m->len = 0;\n    m->cap = 0;\n}\n\nstatic const rt_type RT_TYPE_xn_map_s_i = { \"Map\", sizeof(xn_map_s_i), xn_map_s_i_deinit, xn_map_s_i_scan };\n\nstatic xn_map_s_i *xn_map_s_i_new(size_t cap) {\n    xn_map_s_i *m = (xn_map_s_i *)xn_gc_new(&RT_TYPE_xn_map_s_i);\n    memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_s_i) - sizeof(rt_header));\n    m->cap = cap ? cap : 4;\n    m->keys = malloc(sizeof(rt_string *) * m->cap);\n    m->vals = malloc(sizeof(int64_t) * m->cap);\n    if (m->keys == NULL || m->vals == NULL) { abort(); }\n    return m;\n}\n\nstatic long xn_map_s_i_find(const xn_map_s_i *m, rt_string * key) {\n    for (size_t i = 0; i < m->len; i++) {\n        if (m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0) { return (long)i; }\n    }\n    return -1;\n}\n\nstatic void xn_map_s_i_put(xn_map_s_i *m, rt_string * key, int64_t val) {\n    long i = xn_map_s_i_find(m, key);\n    if (i >= 0) {\n        m->vals[i] = val;\n        return;\n    }\n    if (m->len == m->cap) {\n        m->cap *= 2;\n        m->keys = realloc(m->keys, sizeof(rt_string *) * m->cap);\n        m->vals = realloc(m->vals, sizeof(int64_t) * m->cap);\n        if (m->keys == NULL || m->vals == NULL) { abort(); }\n    }\n    m->keys[m->len] = key;\n    m->vals[m->len] = val;\n    m->len++;\n}\n\nstatic int xn_map_s_i_has(const xn_map_s_i *m, rt_string * key) { return xn_map_s_i_find(m, key) >= 0; }\n\nstatic int64_t xn_map_s_i_get_or(const xn_map_s_i *m, rt_string * key, int64_t dflt) {\n    long i = xn_map_s_i_find(m, key);\n    return i >= 0 ? m->vals[i] : dflt;\n}\n\nstatic int xn_map_s_i_remove(xn_map_s_i *m, rt_string * key) {\n    long i = xn_map_s_i_find(m, key);\n    if (i < 0) { return 0; }\n    for (size_t j = (size_t)i; j + 1 < m->len; j++) {\n        m->keys[j] = m->keys[j + 1];\n        m->vals[j] = m->vals[j + 1];\n    }\n    m->len--;\n    return 1;\n}\n\nstatic void xn_map_s_i_clear(xn_map_s_i *m) {\n    m->len = 0;\n}\n\nstatic int xn_map_s_i_cmp_key(rt_string * a, rt_string * b) {\n    size_t n = a->len < b->len ? a->len : b->len;\n    int c = memcmp(a->bytes, b->bytes, n);\n    if (c != 0) { return c; }\n    return (a->len > b->len) - (a->len < b->len);\n}\n\nstatic void xn_map_s_i_sort_idx(const xn_map_s_i *m, size_t *idx) {\n    for (size_t i = 1; i < m->len; i++) {\n        size_t x = idx[i];\n        size_t j = i;\n        while (j > 0 && xn_map_s_i_cmp_key(m->keys[idx[j - 1]], m->keys[x]) > 0) {\n            idx[j] = idx[j - 1];\n            j--;\n        }\n        idx[j] = x;\n    }\n}\n\nstatic xn_arr_s *xn_map_s_i_keys(const xn_map_s_i *m) {\n    xn_arr_s *out = xn_arr_s_new(m->len);\n    if (m->len == 0) { return out; }\n    size_t *idx = malloc(sizeof(size_t) * m->len);\n    if (idx == NULL) { abort(); }\n    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }\n    xn_map_s_i_sort_idx(m, idx);\n    for (size_t i = 0; i < m->len; i++) { xn_arr_s_push(out, m->keys[idx[i]]); }\n    free(idx);\n    return out;\n}\n\nstatic xn_arr_i *xn_map_s_i_values(const xn_map_s_i *m) {\n    xn_arr_i *out = xn_arr_i_new(m->len);\n    if (m->len == 0) { return out; }\n    size_t *idx = malloc(sizeof(size_t) * m->len);\n    if (idx == NULL) { abort(); }\n    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }\n    xn_map_s_i_sort_idx(m, idx);\n    for (size_t i = 0; i < m->len; i++) { xn_arr_i_push(out, m->vals[idx[i]]); }\n    free(idx);\n    return out;\n}\n\nstatic xn_opt_i xn_map_s_i_get(const xn_map_s_i *m, rt_string * key) {\n    xn_opt_i r;\n    long i = xn_map_s_i_find(m, key);\n    if (i < 0) { r.has = 0; r.v = 0; return r; }\n    r.has = 1;\n    r.v = m->vals[i];\n    return r;\n}\n\n\nstatic xn_arr_s *xn_str_split(rt_string *s, rt_string *sep) {\n    xn_arr_s *out = xn_arr_s_new(4);\n    if (sep->len == 0) {\n        rt_string *t = rt_string_new(s->bytes, s->len);\n        xn_arr_s_push(out, t);\n        rt_release(t);\n        return out;\n    }\n    size_t start = 0, i = 0;\n    while (i + sep->len <= s->len) {\n        if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) {\n            rt_string *t = rt_string_new(s->bytes + start, i - start);\n            xn_arr_s_push(out, t);\n            rt_release(t);\n            i += sep->len;\n            start = i;\n        } else {\n            i++;\n        }\n    }\n    rt_string *last = rt_string_new(s->bytes + start, s->len - start);\n    xn_arr_s_push(out, last);\n    rt_release(last);\n    return out;\n}\nstatic int64_t xn_sum(xn_arr_i * xn_p_xs);\nstatic int64_t xn_main();\n\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";

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
static String decl(String cty, String name) {
    if cty.length() > 0 && cty.substring(cty.length() - 1, 1) == "*" { return cty + name }
    return cty + " " + name
}
static String lastQual(N t) {
    N ql = fld(t, "Qual")
    if ql.el.length() == 0 { return "" }
    return unq(txt(ql.el.get(ql.el.length() - 1)))
}
static String typeKey(N t) {
    if t.nm == "NamedType" {
        String last = lastQual(t)
        N args = fld(t, "Args")
        if last == "List" && args.el.length() > 0 { return "List<" + typeKey(args.el.get(0)) + ">" }
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
    if t.nm == "SuffixedType" {
        N sfx = fld(t, "Suffixes")
        if sfx.el.length() == 1 && unq(txt(sfx.el.get(0))) == "[]" { return typeKey(fld(t, "Base")) + "[]" }
        return typeKey(fld(t, "Base"))
    }
    return "Int"
}
static String cNamePart(String k) {
    if k == "Int" { return "Int" }
    if k == "Bool" { return "Bool" }
    if k == "Char" { return "Char" }
    if k == "Float" { return "Float" }
    if k == "Double" { return "Double" }
    if k == "String" { return "String" }
    if k == "Error" { return "Error" }
    if k == "List<Int>" { return "List_Int" }
    return "X"
}
static String resultName(String k) {
    Int l = k.indexOf("<")
    Int c = k.indexOf(",")
    Int r = k.indexOf(">")
    String a = k.substring(l + 1, c - l - 1).trim()
    String b = k.substring(c + 1, r - c - 1).trim()
    return "xn_Result_" + cNamePart(a) + "_" + cNamePart(b)
}
static String cType(String k) {
    if k == "Int" { return "int64_t" }
    if k == "Bool" { return "int" }
    if k == "Char" { return "xn_char" }
    if k == "Float" || k == "Double" { return "double" }
    if k == "String" { return "rt_string *" }
    if k == "List<Int>" || k == "Int[]" { return "xn_arr_i *" }
    if k == "Set<Int>" { return "xn_set_i *" }
    if k == "Map<String, Int>" { return "xn_map_s_i *" }
    if k.indexOf("Result<") == 0 { return resultName(k) }
    if isClass(k) { return "xn_Cls_" + k + " *" }
    if isStruct(k) { return "xn_Struct_" + k }
    return "int64_t"
}
static Bool isResult(String k) { return k.indexOf("Result<") == 0 }
static Bool isArr(String k) { return k == "List<Int>" || k == "Int[]" }
static Bool isMap(String k) { return k.indexOf("Map<") == 0 }
static Bool isSet(String k) { return k.indexOf("Set<") == 0 }
static List<String> CLS_NAMES = []
static List<String> PRIMARY_NAMES = []
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

class DF {
    String text = ""
    String temp = ""
    Bool err = false
}

class SC {
    List<String> names = []
    List<String> types = []
    List<String> strLocals = []
    List<DF> defers = []
    List<DF> errdefers = []
    List<DF> blockDefers = []
    List<String> blockRoots = []
    List<String> params = []
    List<String> fnNames = []
    List<String> fnRets = []
    List<String> resultTypes = []
    String ret = ""
    String root = "xn_t1"
    String selfName = "self"
    String curClass = ""
    Bool selfPtr = false
    String retKind = "Int"
    void def(String n, String t) { self.names.push(n); self.types.push(t) }
    String typeOf(String n) {
        Int i = 0
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

class EM {
    List<String> ls = []
    Int tmp = 0
    Int ind = 0
    Bool usesList = false
    Bool hasMap = false
    Bool hasSet = false
    Bool hasGetOr = false
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
    if x.nm == "IdentExpr" { return sc.typeOf(unq(txt(fld(x, "Name")))) }
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
            if n == "str" { return "String" }
            if n == "Ok" || n == "Err" { return "Result" }
            return sc.retOf(n)
        }
        if callee.nm == "Member" {
            N mx = fld(callee, "X")
            String mn = unq(txt(fld(callee, "Name")))
            String mt = exprType(mx, sc)
            if mn == "isOk" || mn == "isErr" { return "Bool" }
            if mn == "value" || mn == "unwrapOr" { return resultVal(mt) }
            if mn == "error" { return resultErr(mt) }
            if isClass(mt) || isStruct(mt) { return methodRet(mt, mn) }
            if mn == "length" { return "Int" }
            if mn == "get" { if isMap(mt) { return mapVal(mt) }; return "Int" }
            if mn == "getOr" { return mapVal(mt) }
            if mn == "has" { return "Bool" }
            if mn == "add" { return "Bool" }
            if mn == "remove" { return "Int" }
        }
        return "Int"
    }
    if x.nm == "Member" {
        String bt = exprType(fld(x, "X"), sc)
        String f = unq(txt(fld(x, "Name")))
        if isClass(bt) || isStruct(bt) { return fieldType(bt, f) }
        return "Int"
    }
    if x.nm == "Index" {
        String bt = exprType(fld(x, "X"), sc)
        if isMap(bt) { return mapVal(bt) }
        return "Int"
    }
    if x.nm == "Binary" {
        String op = unq(txt(fld(x, "Op")))
        if op == "<" || op == ">" || op == "<=" || op == ">=" || op == "==" || op == "!=" || op == "&&" || op == "||" { return "Bool" }
        if op == "+" && (exprType(fld(x, "L"), sc) == "String" || exprType(fld(x, "R"), sc) == "String") { return "String" }
        if exprType(fld(x, "L"), sc) == "Double" || exprType(fld(x, "R"), sc) == "Double" { return "Double" }
        return "Int"
    }
    return "Int"
}
static String resultVal(String k) {
    Int l = k.indexOf("<"); Int c = k.indexOf(",")
    if l < 0 || c < 0 { return "Int" }
    return k.substring(l + 1, c - l - 1).trim()
}
static String resultErr(String k) {
    Int c = k.indexOf(","); Int r = k.indexOf(">")
    if c < 0 || r < 0 { return "String" }
    return k.substring(c + 1, r - c - 1).trim()
}

static String strHelper(N a, EM e, SC sc) {
    String t = exprType(a, sc)
    String v = expr(a, e, sc)
    if t == "Bool" { return "xn_str_bool((" + v + "))" }
    if t == "Char" { return "xn_str_int(" + v + ")" }
    if t == "Double" || t == "Float" { return "xn_str_double(" + v + ")" }
    return "xn_str_int(" + v + ")"
}

static String expr(N x, EM e, SC sc) {
    if x.nm == "IntLitExpr" { return unq(txt(fld(x, "Text"))) }
    if x.nm == "BoolLit" { if txt(fld(x, "V")) == "true" { return "1" }; return "0" }
    if x.nm == "CharLitExpr" { return txt(fld(x, "Rune")) }
    if x.nm == "FloatLitExpr" { return unq(txt(fld(x, "Text"))) }
    if x.nm == "IdentExpr" {
        String idn = unq(txt(fld(x, "Name")))
        if idn == "self" { return sc.selfName }
        if sc.curClass != "" && (isClass(sc.curClass) || isStruct(sc.curClass)) {
            if fieldExists(sc.curClass, idn) { return sc.selfName + "->" + idn }
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
        if op == "/" { return "xn_div_i64((int64_t)(" + expr(fld(x, "L"), e, sc) + "), (int64_t)(" + expr(fld(x, "R"), e, sc) + "))" }
        if op == "%" { return "xn_mod_i64((int64_t)(" + expr(fld(x, "L"), e, sc) + "), (int64_t)(" + expr(fld(x, "R"), e, sc) + "))" }
        return "(" + expr(fld(x, "L"), e, sc) + " " + op + " " + expr(fld(x, "R"), e, sc) + ")"
    }
    if x.nm == "Member" {
        String bt = exprType(fld(x, "X"), sc)
        String f = unq(txt(fld(x, "Name")))
        if isClass(bt) { return expr(fld(x, "X"), e, sc) + "->" + f }
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
            String cbt = exprType(mx, sc)
            if isClass(cbt) || isStruct(cbt) {
                String b0 = expr(mx, e, sc)
                if isStruct(cbt) { b0 = "(&" + b0 + ")" }
                String call = "xn_" + (isClass(cbt) ? "Cls_" : "Struct_") + cbt + "_" + mn + "(" + b0
                Int ai = 0
                while ai < args.el.length() {
                    call = call + ", " + expr(args.el.get(ai), e, sc)
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
                if isMap(mt2) { return "(xn_map_s_i_get(" + xb + ", " + a0 + ").v)" }
                return "xn_arr_i_get(" + xb + ", " + a0 + ")"
            }
            if mn == "getOr" {
                e.hasGetOr = true
                String xb = expr(mx, e, sc)
                String a0 = "0"
                String a1 = "0"
                if args.el.length() > 0 { a0 = emitStr(args.el.get(0), e, sc) }
                if args.el.length() > 1 { a1 = expr(args.el.get(1), e, sc) }
                return "xn_map_s_i_get_or(" + xb + ", " + a0 + ", " + a1 + ")"
            }
            if mn == "has" {
                String xb = expr(mx, e, sc)
                String a0 = "0"
                if args.el.length() > 0 {
                    if isMap(mt2) && exprType(args.el.get(0), sc) == "String" { a0 = emitStr(args.el.get(0), e, sc) }
                    else { a0 = expr(args.el.get(0), e, sc) }
                }
                if isSet(mt2) { return "xn_set_i_has(" + xb + ", " + a0 + ")" }
                return "xn_map_s_i_has(" + xb + ", " + a0 + ")"
            }
            if mn == "add" {
                String xb = expr(mx, e, sc)
                String a0 = "0"
                if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                return "xn_set_i_add(" + xb + ", " + a0 + ")"
            }
            if mn == "remove" {
                String xb = expr(mx, e, sc)
                String a0 = "0"
                if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                return "xn_arr_i_remove(" + xb + ", " + a0 + ")"
            }
        }
        // 普通函数调用
        N cl = fld(x, "Callee")
        String cal = expr(cl, e, sc)
        if cl.nm == "IdentExpr" {
            String cn = unq(txt(fld(cl, "Name")))
            if cn != "str" && cn != "print" && cn != "Ok" && cn != "Err" { cal = "xn_" + cn }
        }
        N args = fld(x, "Args")
        String b = cal + "("
        Int i = 0
        while i < args.el.length() {
            if i > 0 { b = b + ", " }
            b = b + expr(args.el.get(i), e, sc)
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
                e.raw("xn_root_add(" + t + ");")
                if cur == "" { cur = t } else { String c = e.nt(); e.add("rt_string *" + c + " = xn_concat(" + cur + ", " + t + ");"); e.raw("xn_root_add(" + c + ");"); cur = c }
            }
            if ex.nm != "" && ex.nm != "nil" {
                String t = ""
                if exprType(ex, sc) == "String" { t = emitStr(ex, e, sc) } else {
                    t = e.nt()
                    e.add("rt_string *" + t + " = " + strHelper(ex, e, sc) + ";")
                    e.raw("xn_root_add(" + t + ");")
                }
                if cur == "" { cur = t } else { String c = e.nt(); e.add("rt_string *" + c + " = xn_concat(" + cur + ", " + t + ");"); e.raw("xn_root_add(" + c + ");"); cur = c }
            }
            i = i + 1
        }
        return cur
    }
    if x.nm == "Binary" {
        String l = emitStr(fld(x, "L"), e, sc)
        String r = emitStr(fld(x, "R"), e, sc)
        String t = e.nt()
        e.add("rt_string *" + t + " = xn_concat(" + l + ", " + r + ");")
        e.raw("xn_root_add(" + t + ");")
        return t
    }
    if x.nm == "IdentExpr" || x.nm == "Member" {
        String t = e.nt()
        e.add("rt_string *" + t + " = rt_retain(" + expr(x, e, sc) + ");")
        e.raw("xn_root_add(" + t + ");")
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
                e.raw("xn_root_add(" + t + ");")
                return t
            }
        }
        String t = e.nt()
        e.add("rt_string *" + t + " = " + expr(x, e, sc) + ";")
        e.raw("xn_root_add(" + t + ");")
        return t
    }
    String t = e.nt()
    e.add("rt_string *" + t + " = rt_string_from_c(" + q("") + ");")
    e.raw("xn_root_add(" + t + ");")
    return t
}

static void emitPrint(N arg, EM e, SC sc, Int extraRoots) {
    String ty = exprType(arg, sc)
    if ty == "String" {
        String t = emitStr(arg, e, sc)
        Int i = 0
        while i < extraRoots { e.add("xn_root_add(" + t + ");"); i = i + 1 }
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

static void emitDeferBody(DF d, EM e, Int base, Int mode, Bool guarded) {
    // mode 0=函数退出；1=嵌套块 early-return
    if guarded { e.addAt(base + 4, "if (!xn_ret.ok) {") } else { e.addAt(base + 4, "{") }
    if mode == 0 {
        e.addAt(base + 8, "rt_string *" + d.temp + " = rt_string_from_c(" + q(d.text) + ");")
        e.raw("xn_root_add(" + d.temp + ");")
        e.raw("xn_root_add(" + d.temp + ");")
        e.addAt(base + 8, "xn_root_add(" + d.temp + ");")
        e.addAt(base + 8, "xn_print_str(" + d.temp + ");")
        e.addAt(base + 8, "rt_release(" + d.temp + ");")
    } else {
        e.addAt(base + 8, "rt_string *" + d.temp + " = rt_string_from_c(" + q(d.text) + ");")
        e.raw("xn_root_add(" + d.temp + ");")
        e.addAt(base, "xn_root_add(" + d.temp + ");")
        e.addAt(base, "xn_root_add(" + d.temp + ");")
        e.addAt(base + 8, "xn_root_add(" + d.temp + ");")
        e.addAt(base + 8, "xn_print_str(" + d.temp + ");")
        e.addAt(base + 8, "rt_release(" + d.temp + ");")
    }
    e.addAt(base + 4, "}")
}

static void emitBlockDefers(SC sc, EM e, Int ind) {
    Int i = sc.blockDefers.length() - 1
    while i >= 0 {
        DF d = sc.blockDefers.get(i)
        e.addAt(ind + 4, "{")
        e.addAt(ind + 12, "rt_string *" + d.temp + " = rt_string_from_c(" + q(d.text) + ");")
        e.raw("xn_root_add(" + d.temp + ");")
        e.addAt(ind + 12, "xn_root_add(" + d.temp + ");")
        e.addAt(ind + 12, "xn_print_str(" + d.temp + ");")
        e.addAt(ind + 12, "rt_release(" + d.temp + ");")
        e.addAt(ind + 4, "}")
        i = i - 1
    }
}

static void emitCleanup(SC sc, EM e, Int base, Int mode, Bool skipErr) {
    Int i = sc.errdefers.length() - 1
    while i >= 0 {
        if !skipErr { emitDeferBody(sc.errdefers.get(i), e, base, mode, true) }
        i = i - 1
    }
    i = sc.defers.length() - 1
    while i >= 0 {
        emitDeferBody(sc.defers.get(i), e, base, mode, false)
        i = i - 1
    }
}

static void emitStmt(N st, EM e, SC sc, Bool early) {
    if st.nm == "DeferStmt" || st.nm == "ReturnStmt" || st.nm == "LocalDeclStmt" || st.nm == "AssignStmt" || st.nm == "ExprStmt" || st.nm == "IfStmt" || st.nm == "WhileStmt" || st.nm == "ForStmt" || st.nm == "SwitchStmt" || st.nm == "ThrowStmt" {
        e.add("#line " + str(lineOf(st)) + " \"" + e.path + "\"")
    }
    if st.nm == "DeferStmt" {
        Bool err = txt(fld(st, "Errdefer")) == "true"
        N inner = fld(st, "Stmt")
        N call = fld(inner, "X")
        N args = fld(call, "Args")
        String text = ""
        if args.el.length() > 0 { text = liteText(args.el.get(0)) }
        String t = e.nt()
        DF d = new DF()
        d.text = text
        d.temp = t
        d.err = err
        if err { sc.errdefers.push(d) } else if e.ind > 0 { sc.blockDefers.push(d) } else { sc.defers.push(d) }
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
        if init.nm == "Unary" && unq(txt(fld(init, "Op"))) == "try" {
            String rk = exprType(fld(init, "X"), sc)
            sc.useResult(rk)
            String call = expr(fld(init, "X"), e, sc)
            String t = e.nt()
            e.add(cType(rk) + " " + t + " = " + call + ";")
            e.add("if (!" + t + ".ok) {")
            e.add("    xn_ret = " + t + ";")
            e.addAt(e.ind + 8, "{")
            e.addAt(e.ind + 8, "xn_root_restore(" + sc.root + ");")
            e.addAt(e.ind + 8, "}")
            emitCleanup(sc, e, e.ind, 0, false)
            e.add("    return xn_ret;")
            e.add("}")
            String vt = resultVal(rk)
            e.add(cType(vt) + " " + nm + " = " + t + ".v;")
            return
        }
        if ty == "String" {
            e.tmp = e.tmp + 1
            String text = liteText(init)
            e.add("rt_string *" + nm + " = rt_string_from_c(" + q(text) + ");")
            e.raw("xn_root_add(" + nm + ");")
            e.raw("xn_root_add(" + nm + ");")
            e.raw("xn_gc_safepoint();")
            sc.strLocals.push(nm)
            return
        }
        if isArr(ty) {
            e.usesList = true
            N elems = fld(init, "Elems")
            String t = e.nt()
            e.add("xn_arr_i *" + t + " = xn_arr_i_new(" + str(elems.el.length()) + ");")
            e.raw("xn_root_add(" + t + ");")
            Int i = 0
            while i < elems.el.length() { e.raw("xn_arr_i_push(" + t + ", " + expr(elems.el.get(i), e, sc) + ");"); i = i + 1 }
            e.add("xn_arr_i * " + nm + " = " + t + ";")
            e.raw("xn_root_add(" + nm + ");")
            e.raw("xn_root_add(" + nm + ");")
            e.raw("xn_gc_safepoint();")
            return
        }
        if isSet(ty) {
            e.hasSet = true
            N elems = fld(init, "Elems")
            String ta = e.nt()
            e.add("xn_arr_i *" + ta + " = xn_arr_i_new(" + str(elems.el.length()) + ");")
            e.raw("xn_root_add(" + ta + ");")
            Int i = 0
            while i < elems.el.length() { e.raw("xn_arr_i_push(" + ta + ", " + expr(elems.el.get(i), e, sc) + ");"); i = i + 1 }
            String ts = e.nt()
            e.add("xn_set_i *" + ts + " = xn_set_i_new();")
            e.raw("xn_root_add(" + ts + ");")
            e.raw("for (size_t i = 0; i < " + ta + "->len; i++) { xn_set_i_add(" + ts + ", " + ta + "->data[i]); }")
            e.add("xn_set_i * " + nm + " = " + ts + ";")
            e.raw("xn_root_add(" + nm + ");")
            e.raw("xn_root_add(" + nm + ");")
            e.raw("xn_gc_safepoint();")
            return
        }
        if isMap(ty) {
            e.hasMap = true
            N keys = fld(init, "Keys")
            N vals = fld(init, "Vals")
            String tm = e.nt()
            e.add("xn_map_s_i *" + tm + " = xn_map_s_i_new(" + str(keys.el.length()) + ");")
            e.raw("xn_root_add(" + tm + ");")
            Int i = 0
            while i < keys.el.length() {
                String kt = emitStr(keys.el.get(i), e, sc)
                String tv = expr(vals.el.get(i), e, sc)
                e.raw("xn_map_s_i_put(" + tm + ", " + kt + ", " + tv + ");")
                i = i + 1
            }
            e.add("xn_map_s_i * " + nm + " = " + tm + ";")
            e.raw("xn_root_add(" + nm + ");")
            e.raw("xn_root_add(" + nm + ");")
            e.raw("xn_gc_safepoint();")
            return
        }
        if isClass(ty) {
            if init.nm == "New" {
                N args = fld(init, "Args")
                if hasRefFields(ty) {
                    String b = "xn_Cls_" + ty + "_new("
                    Int ai = 0
                    while ai < args.el.length() {
                        if ai > 0 { b = b + ", " }
                        N av = args.el.get(ai)
                        if exprType(av, sc) == "String" { b = b + emitStr(av, e, sc) } else { b = b + expr(av, e, sc) }
                        ai = ai + 1
                    }
                    e.add("xn_Cls_" + ty + " * " + nm + " = " + b + ");")
                    e.raw("xn_root_add(" + nm + ");")
                    e.raw("xn_root_add(" + nm + ");")
                    e.raw("xn_gc_safepoint();")
                } else {
                    String t = e.nt()
                    e.add("xn_Cls_" + ty + " " + t + ";")
                    e.raw("memset((char *)&" + t + ", 0, sizeof(xn_Cls_" + ty + "));")
                    String b = "xn_Cls_" + ty + "_new" + (isPrimaryName(ty) ? "_1" : "") + "_init" + "(&" + t
                    Int ai = 0
                    while ai < args.el.length() { b = b + ", " + expr(args.el.get(ai), e, sc); ai = ai + 1 }
                    e.raw(b + ");")
                    e.add("xn_Cls_" + ty + " * " + nm + " = &" + t + ";")
                    e.raw("xn_root_add(" + nm + ");")
                }
                return
            }
            e.add(cType(ty) + " " + nm + " = " + expr(init, e, sc) + ";")
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
        e.add(cType(ty) + " " + nm + " = " + expr(init, e, sc) + ";")
        return
    }
    if st.nm == "AssignStmt" {
        N tgt = fld(st, "Target")
        String v0 = expr(fld(st, "Value"), e, sc)
        if tgt.nm == "Index" {
            String xb = expr(fld(tgt, "X"), e, sc)
            String ix = expr(fld(tgt, "Idx"), e, sc)
            e.add("xn_arr_i_set(" + xb + ", " + ix + ", " + v0 + ");")
            return
        }
        String nm = expr(tgt, e, sc)
        String op = unq(txt(fld(st, "Op")))
        String v = v0
        if tgt.nm == "Member" && exprType(tgt, sc) == "String" && op == "=" {
            String t = e.nt()
            e.add("rt_string *" + t + " = rt_retain(" + v + ");")
            e.raw("xn_root_add(" + t + ");")
            e.add("rt_release(" + nm + ");")
            e.add(nm + " = " + t + ";")
            return
        }
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
                String xb = expr(mx, e, sc)
                if mn == "push" {
                    String a0 = "0"
                    if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                    e.add("xn_arr_i_push(" + xb + ", " + a0 + ");")
                    return
                }
                if mn == "clear" {
                    String mt = exprType(mx, sc)
                    if isSet(mt) { e.add("xn_set_i_clear(" + xb + ");") }
                    else { e.add("xn_arr_i_clear(" + xb + ");") }
                    return
                }
                if mn == "put" {
                    String a0 = "0"
                    String a1 = "0"
                    if args.el.length() > 0 { a0 = emitStr(args.el.get(0), e, sc) }
                    if args.el.length() > 1 { a1 = expr(args.el.get(1), e, sc) }
                    e.add("xn_map_s_i_put(" + xb + ", " + a0 + ", " + a1 + ");")
                    return
                }
                if mn == "set" {
                    String a0 = "0"
                    String a1 = "0"
                    if args.el.length() > 0 { a0 = expr(args.el.get(0), e, sc) }
                    if args.el.length() > 1 { a1 = expr(args.el.get(1), e, sc) }
                    e.add("xn_arr_i_set(" + xb + ", " + a0 + ", " + a1 + ");")
                    return
                }
            }
            Int extra = 0
            if e.ind > 0 { extra = 1 }
            if args.el.length() > 0 { emitPrint(args.el.get(0), e, sc, extra) }
        }
        return
    }
    if st.nm == "ReturnStmt" {
        N v = fld(st, "Value")
        if isResult(sc.retKind) {
            String rk = sc.retKind
            if v.nm == "Call" {
                N callee = fld(v, "Callee")
                String cn = ""
                if callee.nm == "IdentExpr" { cn = unq(txt(fld(callee, "Name"))) }
                N args = fld(v, "Args")
                if cn == "Ok" {
                    String arg = "0"
                    if args.el.length() > 0 { arg = expr(args.el.get(0), e, sc) }
                    e.add("xn_ret = (" + cType(rk) + "){1, " + arg + ", NULL};")
                } else if cn == "Err" {
                    String t = emitStr(args.el.get(0), e, sc)
                    Int i = 0
                    while i < 2 { e.add("xn_root_add(" + t + ");"); i = i + 1 }
                    e.add("xn_ret = (" + cType(rk) + "){0, 0, " + t + "};")
                }
            }
            if early {
                e.addAt(e.ind + 4, "{")
                e.addAt(e.ind, "xn_root_restore(" + sc.blockRoots.get(sc.blockRoots.length() - 1) + ");")
                e.addAt(e.ind + 4, "}")
                emitCleanup(sc, e, e.ind, 1, false)
                e.addAt(e.ind + 4, "{")
                e.addAt(e.ind, "xn_root_restore(" + sc.root + ");")
                e.addAt(e.ind + 4, "}")
                e.raw("")
                e.add("return xn_ret;")
                e.raw("")
                e.terminated = true
            }
            return
        }
        if exprType(v, sc) == "String" {
            String t = emitStr(v, e, sc)
            e.add("xn_root_add(" + t + ");")
            sc.ret = t
            return
        }
        String t = e.nt()
        e.add("int64_t " + t + " = " + expr(v, e, sc) + ";")
        sc.ret = t
        return
    }
    if st.nm == "IfStmt" {
        N cond = fld(st, "Cond")
        String cexpr = expr(cond, e, sc)
        if cond.nm == "BoolLit" { e.addAt(e.ind + 4, "if (" + cexpr + ") {") } else { e.addAt(e.ind + 4, "if ((" + cexpr + ")) {") }
        String r = e.nt()
        e.addAt(e.ind + 8, "size_t " + r + " = xn_root_mark();")
        sc.blockRoots.push(r)
        e.terminated = false
        List<DF> savedDefers = sc.blockDefers
        sc.blockDefers = []
        emitBlock(fld(st, "Then"), e, sc, e.ind + 8, true)
        Bool termThen = e.terminated
        emitBlockDefers(sc, e, e.ind + 8)
        sc.blockDefers = savedDefers
        sc.blockRoots.remove(sc.blockRoots.length() - 1)
        if !termThen {
            e.addAt(e.ind + 12, "{")
            e.addAt(e.ind + 12, "xn_root_restore(" + r + ");")
            e.addAt(e.ind + 12, "}")
            e.raw("")
        }
        N els = fld(st, "Else")
        if els.nm != "" && els.nm != "nil" {
            e.addAt(e.ind + 4, "} else {")
            String r2 = e.nt()
            e.addAt(e.ind + 8, "size_t " + r2 + " = xn_root_mark();")
            sc.blockRoots.push(r2)
            e.terminated = false
            List<DF> savedDefers2 = sc.blockDefers
            sc.blockDefers = []
            if els.nm == "Block" { emitBlock(els, e, sc, e.ind + 8, true) } else {
                Int save = e.ind
                e.ind = e.ind + 8
                emitStmt(els, e, sc, true)
                e.ind = save
            }
            Bool termElse = e.terminated
            emitBlockDefers(sc, e, e.ind + 8)
            sc.blockDefers = savedDefers2
            sc.blockRoots.remove(sc.blockRoots.length() - 1)
            if !termElse {
                e.addAt(e.ind + 12, "{")
                e.addAt(e.ind + 12, "xn_root_restore(" + r2 + ");")
                e.addAt(e.ind + 12, "}")
                e.raw("")
            }
            e.addAt(e.ind + 4, "}")
        } else {
            e.addAt(e.ind + 4, "}")
        }
        return
    }
    if st.nm == "WhileStmt" {
        N cond = fld(st, "Cond")
        String cexpr = expr(cond, e, sc)
        if cond.nm == "BoolLit" { e.addAt(e.ind + 4, "while (" + cexpr + ") {") } else { e.addAt(e.ind + 4, "while ((" + cexpr + ")) {") }
        String r = e.nt()
        e.addAt(e.ind + 4, "size_t " + r + " = xn_root_mark();")
        sc.blockRoots.push(r)
        e.terminated = false
        emitBlock(fld(st, "Body"), e, sc, e.ind + 4, true)
        sc.blockRoots.remove(sc.blockRoots.length() - 1)
        e.addAt(e.ind + 8, "{")
        e.addAt(e.ind + 8, "xn_root_restore(" + r + ");")
        e.addAt(e.ind + 8, "}")
        e.raw("")
        e.addAt(e.ind + 4, "xn_gc_safepoint();")
        e.addAt(e.ind + 4, "}")
        return
    }
    if st.nm == "ForStmt" {
        String vname = unq(txt(fld(st, "Var")))
        String coll = expr(fld(st, "Src"), e, sc)
        String bodyRoot = e.nt()
        String loop = e.nt()
        e.addAt(e.ind, "for (size_t " + loop + " = 0; " + loop + " < " + coll + "->len; " + loop + "++) {")
        e.addAt(e.ind + 4, "int64_t " + vname + " = " + coll + "->data[" + loop + "];")
        e.addAt(e.ind + 4, "size_t " + bodyRoot + " = xn_root_mark();")
        sc.blockRoots.push(bodyRoot)
        e.terminated = false
        emitBlock(fld(st, "Body"), e, sc, e.ind + 4, true)
        sc.blockRoots.remove(sc.blockRoots.length() - 1)
        e.addAt(e.ind + 8, "{")
        e.addAt(e.ind + 8, "xn_root_restore(" + bodyRoot + ");")
        e.addAt(e.ind + 8, "}")
        e.raw("")
        e.addAt(e.ind + 4, "xn_gc_safepoint();")
        e.addAt(e.ind, "}")
        return
    }
    if st.nm == "SwitchStmt" {
        String val = expr(fld(st, "Value"), e, sc)
        N cases = fld(st, "Cases")
        e.addAt(e.ind + 4, "do {")
        Int i = 0
        while i < cases.el.length() {
            N c = cases.el.get(i)
            String head = "else if "
            if i == 0 { head = "if " }
            e.addAt(e.ind + 8, head + "(" + val + " == (" + expr(fld(c, "Expr"), e, sc) + ")) {")
            String r = e.nt()
            e.addAt(e.ind + 12, "size_t " + r + " = xn_root_mark();")
            sc.blockRoots.push(r)
            N stmts = fld(c, "Stmts")
            Int j = 0
            while j < stmts.el.length() {
                Int save = e.ind
                e.ind = e.ind + 12
                emitStmt(stmts.el.get(j), e, sc, true)
                e.ind = save
                j = j + 1
            }
            sc.blockRoots.remove(sc.blockRoots.length() - 1)
            e.addAt(e.ind + 16, "{")
            e.addAt(e.ind + 16, "xn_root_restore(" + r + ");")
            e.addAt(e.ind + 16, "}")
            e.raw("")
            e.addAt(e.ind + 8, "}")
            i = i + 1
        }
        N def = fld(st, "Default")
        if def.nm != "" && def.nm != "nil" {
            e.addAt(e.ind + 8, "else {")
            String r = e.nt()
            e.addAt(e.ind + 12, "size_t " + r + " = xn_root_mark();")
            sc.blockRoots.push(r)
            N stmts = fld(def, "Stmts")
            Int j = 0
            while j < stmts.el.length() {
                Int save = e.ind
                e.ind = e.ind + 12
                emitStmt(stmts.el.get(j), e, sc, true)
                e.ind = save
                j = j + 1
            }
            sc.blockRoots.remove(sc.blockRoots.length() - 1)
            e.addAt(e.ind + 16, "{")
            e.addAt(e.ind + 16, "xn_root_restore(" + r + ");")
            e.addAt(e.ind + 16, "}")
            e.raw("")
            e.addAt(e.ind + 8, "}")
        }
        e.addAt(e.ind + 4, "} while (0);")
        return
    }
}

static void emitBlock(N blk, EM e, SC sc, Int ind, Bool early) {
    if blk.nm != "Block" { return }
    N stmts = fld(blk, "Stmts")
    Int i = 0
    while i < stmts.el.length() {
        Int save = e.ind
        e.ind = ind
        emitStmt(stmts.el.get(i), e, sc, early)
        e.ind = save
        i = i + 1
    }
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

static void emitFunc(N fn, EM e, SC sc) {
    String fname = unq(txt(fld(fn, "Name")))
    String rk = typeKey(fld(fn, "Ret"))
    if fname == "main" { rk = "Int" }
    sc.retKind = rk
    sc.params = []
    N ps = fld(fn, "Params")
    Int pi = 0
    while pi < ps.el.length() {
        sc.params.push(unq(txt(fld(ps.el.get(pi), "Name"))))
        pi = pi + 1
    }
    sc.defers = []
    sc.errdefers = []
    sc.strLocals = []
    sc.blockRoots = []
    String outName = "xn_" + fname
    e.add(cType(rk) + " " + outName + "(" + paramsOf(fn) + ") {")
    if isResult(rk) {
        e.add("    " + cType(rk) + " xn_ret;")
        sc.useResult(rk)
    }
    String root = e.nt()
    sc.root = root
    e.add("size_t " + root + " = xn_root_mark();")
    N ps2 = fld(fn, "Params")
    Int pj = 0
    while pj < ps2.el.length() {
        String pty = typeKey(fld(ps2.el.get(pj), "Type"))
        String pnm = unq(txt(fld(ps2.el.get(pj), "Name")))
        String pct = cType(pty)
        if pct.length() > 0 && pct.substring(pct.length() - 1, 1) == "*" {
            e.raw("xn_root_add(xn_p_" + pnm + ");")
        }
        pj = pj + 1
    }
    emitBlock(fld(fn, "Body"), e, sc, 0, false)
    emitCleanup(sc, e, 0, 0, false)
    Int i = 0
    while i < sc.strLocals.length() {
        if i == 0 { e.add("    {") }
        e.raw("rt_release(" + sc.strLocals.get(i) + ");")
        if i == sc.strLocals.length() - 1 { e.add("    }") }
        i = i + 1
    }
    e.add("    {")
    e.raw("xn_root_restore(" + root + ");")
    e.add("    }")
    e.add("")
    if isResult(rk) { e.add("return xn_ret;") } else { e.add("return " + sc.ret + ";") }
    e.add("}")
    e.add("")
}


static String joinLines(List<String> xs) {
    String b = ""
    Int i = 0
    while i < xs.length() { b = b + xs.get(i) + "\n"; i = i + 1 }
    return b
}

static String zeroOf(String cty) { return "(" + cty + ")0" }

static String ctorParams(N cls) { return paramsOf(ctorOf(cls)) }
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
    dst.push("typedef struct xn_Cls_" + cn + " xn_Cls_" + cn + ";")
    dst.push("")
    dst.push("typedef struct xn_Cls_" + cn + " xn_Cls_" + cn + ";")
    dst.push("")
    String sfx = ""
    if isPrimary(cls) { sfx = "_1" }
    dst.push("static xn_Cls_" + cn + " *xn_Cls_" + cn + "_new" + sfx + "(" + ctorParams(cls) + ");")
    dst.push("static void xn_Cls_" + cn + "_new" + sfx + "_init" + "(xn_Cls_" + cn + " *o" + (ctorParams(cls) == "" ? "" : ", " + ctorParams(cls)) + ");")
    dst.push("")
    dst.push("")
}

static void emitClassSection(N cls, EM ce) {
    String cn = unq(txt(fld(cls, "Name")))
    Bool ref = hasRefFields(cn)
    N fs = fld(cls, "Fields")
    N ms = fld(cls, "Methods")
    N cs = fld(cls, "Ctors")
    Bool primary = isPrimary(cls)
    String sfx = ""
    if primary { sfx = "_1" }
    ce.add("/* 类 " + cn + "（M4.4b） */")
    ce.add("typedef struct xn_Cls_" + cn + " {")
    ce.add("    rt_header hdr;")
    Int i = 0
    if primary {
        N pps = fld(ctorOf(cls), "Params")
        i = pps.el.length() - 1
        while i >= 0 {
            ce.add("    " + cType(typeKey(fld(pps.el.get(i), "Type"))) + " " + unq(txt(fld(pps.el.get(i), "Name"))) + ";")
            i = i - 1
        }
    } else {
        while i < fs.el.length() {
            ce.add("    " + cType(typeKey(fld(fs.el.get(i), "Type"))) + " " + unq(txt(fld(fs.el.get(i), "Name"))) + ";")
            i = i + 1
        }
    }
    ce.add("} xn_Cls_" + cn + ";")
    ce.raw("")
    ce.add("static void xn_Cls_" + cn + "_deinit_hook(void *p) {")
    ce.add("    xn_Cls_" + cn + " *o = (xn_Cls_" + cn + " *)p;")
    i = 0
    while i < fs.el.length() {
        if typeKey(fld(fs.el.get(i), "Type")) == "String" { ce.add("    rt_release(o->" + unq(txt(fld(fs.el.get(i), "Name"))) + ");") }
        i = i + 1
    }
    ce.add("}")
    ce.raw("")
    if ref {
        ce.add("static void xn_Cls_" + cn + "_gc_scan(void *p, void (*visit)(void *)) {")
        ce.add("    xn_Cls_" + cn + " *o = (xn_Cls_" + cn + " *)p;")
        i = 0
        while i < fs.el.length() {
            if typeKey(fld(fs.el.get(i), "Type")) == "String" { ce.add("    if (o->" + unq(txt(fld(fs.el.get(i), "Name"))) + ") { visit(o->" + unq(txt(fld(fs.el.get(i), "Name"))) + "); }") }
            i = i + 1
        }
        ce.add("}")
        ce.raw("")
    }
    ce.add("static const rt_type RT_TYPE_XN_" + cn + " = { \"" + cn + "\", sizeof(xn_Cls_" + cn + "), xn_Cls_" + cn + "_deinit_hook, " + (ref ? "xn_Cls_" + cn + "_gc_scan" : "NULL") + " };")
    ce.raw("")
    // new_init
    ce.add("static void xn_Cls_" + cn + "_new" + sfx + "_init" + "(xn_Cls_" + cn + " *o" + (ctorParams(cls) == "" ? "" : ", " + ctorParams(cls)) + ") {")
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
        ce.add("    xn_Cls_" + cn + " *o = (xn_Cls_" + cn + " *)" + (ref ? "xn_gc_new" : "rt_arc_new") + "(&RT_TYPE_XN_" + cn + ");")
        ce.add("    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_" + cn + ") - sizeof(rt_header));")
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
            String rt = typeKey(fld(m, "Ret"))
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
            String mr = ce.nt()
            ce.add("size_t " + mr + " = xn_root_mark();")
            emitBlock(fld(m, "Body"), ce, msc, 0, false)
            ce.add("    {")
            ce.addAt(0, "xn_root_restore(" + mr + ");")
            ce.add("    }")
            ce.raw("")
            ce.add("return " + msc.ret + ";")
            if rt != "void" { ce.add("    return " + zeroOf(cType(rt)) + "; /* sema 保证不可达（函数体全路径 return） */") }
            ce.add("}")
            ce.raw("")
            i = i + 1
        }
        return
    }
    i = 0
    while i < fs.el.length() {
        String ft = typeKey(fld(fs.el.get(i), "Type"))
        String fn = unq(txt(fld(fs.el.get(i), "Name")))
        N init = fld(fs.el.get(i), "Init")
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
        } else {
            String dv = "0"
            if init.nm == "IntLitExpr" { dv = expr(init, ce, new SC()) }
            ce.add("    o->" + fn + " = " + dv + ";")
        }
        i = i + 1
    }
    String root = ce.nt()
    ce.add("size_t " + root + " = xn_root_mark();")
    if ref { ce.raw("xn_root_add(o);") }
    N ps = fld(cls, "Params")
    N cps = fld(ctorOf(cls), "Params")
    Int pj = 0
    while pj < cps.el.length() {
        String pt = typeKey(fld(cps.el.get(pj), "Type"))
        if cType(pt).length() > 0 && cType(pt).substring(cType(pt).length() - 1, 1) == "*" { ce.raw("xn_root_add(xn_p_" + unq(txt(fld(cps.el.get(pj), "Name"))) + ");") }
        pj = pj + 1
    }
    N ctor = ctorOf(cls)
    SC csc = new SC()
    csc.selfName = "o"
    csc.def("self", cn)
    csc.retKind = "Int"
    csc.params = []
    Int cpj = 0
    while cpj < cps.el.length() { csc.params.push(unq(txt(fld(cps.el.get(cpj), "Name")))); cpj = cpj + 1 }
    if ctor.nm == "CtorDecl" { emitBlock(fld(ctor, "Body"), ce, csc, 0, false) }
    ce.add("    {")
    ce.addAt(4, "xn_root_restore(" + root + ");")
    ce.add("    }")
    ce.add("}")
    ce.raw("")
    // new
    ce.add("static xn_Cls_" + cn + " *xn_Cls_" + cn + "_new" + sfx + "(" + ctorParams(cls) + ") {")
    ce.add("    xn_Cls_" + cn + " *o = (xn_Cls_" + cn + " *)" + (ref ? "xn_gc_new" : "rt_arc_new") + "(&RT_TYPE_XN_" + cn + ");")
    ce.add("    memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_" + cn + ") - sizeof(rt_header));")
    String cargs = ctorArgs(cls)
    if cargs == "" { ce.add("    xn_Cls_" + cn + "_new" + sfx + "_init" + "(o);") }
    else { ce.add("    xn_Cls_" + cn + "_new_init(o, " + cargs + ");") }
    ce.add("    return o;")
    ce.add("}")
    ce.raw("")
    // methods
    i = 0
    while i < ms.el.length() {
        N m = ms.el.get(i)
        String mn = unq(txt(fld(m, "Name")))
        String rt = typeKey(fld(m, "Ret"))
        String sig = "xn_Cls_" + cn + "_" + mn + "(xn_Cls_" + cn + " *self"
        N mps = fld(m, "Params")
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
        msc.params = []
        mj = 0
        while mj < mps.el.length() { msc.params.push(unq(txt(fld(mps.el.get(mj), "Name")))); mj = mj + 1 }
        String mr = ce.nt()
        ce.add("size_t " + mr + " = xn_root_mark();")
        if ref { ce.raw("xn_root_add(self);") }
        emitBlock(fld(m, "Body"), ce, msc, 0, false)
        ce.add("    {")
        ce.raw("xn_root_restore(" + mr + ");")
        ce.add("    }")
        ce.raw("")
        ce.add("return " + msc.ret + ";")
        if rt != "void" { ce.add("    return " + zeroOf(cType(rt)) + "; /* sema 保证不可达（函数体全路径 return） */") }
        ce.add("}")
        ce.raw("")
        i = i + 1
    }
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
    ce.add("static xn_Struct_" + sn + " xn_Struct_" + sn + "_new(" + ctorParams(st) + ") {")
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
        String rt = typeKey(fld(m, "Ret"))
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
        msc.params = []
        mj = 0
        while mj < mps.el.length() { msc.params.push(unq(txt(fld(mps.el.get(mj), "Name")))); mj = mj + 1 }
        String mr = ce.nt()
        ce.add("size_t " + mr + " = xn_root_mark();")
        emitBlock(fld(m, "Body"), ce, msc, 0, false)
        ce.add("    {")
        ce.addAt(0, "xn_root_restore(" + mr + ");")
        ce.add("    }")
        ce.raw("")
        ce.add("return " + msc.ret + ";")
        if rt != "void" { ce.add("    return " + zeroOf(cType(rt)) + "; /* sema 保证不可达（函数体全路径 return） */") }
        ce.add("}")
        ce.raw("")
        i = i + 1
    }
}

static String emitUnit(N unit, String path) {
    EM e = new EM()
    SC sc = new SC()
    e.path = path
    N decls = fld(unit, "Decls")
    CLS_NAMES = []
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
            CLS_NAMES.push(cn)
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
            N ms = fld(d, "Methods")
            fi = 0
            while fi < ms.el.length() {
                MTH_OWNER.push(cn)
                MTH_NAME.push(unq(txt(fld(ms.el.get(fi), "Name"))))
                MTH_RET.push(typeKey(fld(ms.el.get(fi), "Ret")))
                fi = fi + 1
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
                MTH_RET.push(typeKey(fld(sms.el.get(sfi), "Ret")))
                sfi = sfi + 1
            }
        }
        if d.nm == "TopFunc" {
            String rk = typeKey(fld(d, "Ret"))
            sc.useResult(rk)
            sc.defFn(unq(txt(fld(d, "Name"))), rk)
        }
        i = i + 1
    }
    i = 0
    while i < decls.el.length() {
        N d = decls.el.get(i)
        if d.nm == "TopFunc" {
            String nm = unq(txt(fld(d, "Name")))
            if nm != "main" { emitFunc(d, e, sc) }
        }
        i = i + 1
    }
    i = 0
    while i < decls.el.length() {
        N d = decls.el.get(i)
        if d.nm == "TopFunc" && unq(txt(fld(d, "Name"))) == "main" { emitFunc(d, e, sc) }
        i = i + 1
    }
    Int funcEnd = e.ls.length()
    e.add("int main(void) {")
    e.add("    xrt_runtime_init();")
    e.add("    xn_init_vtables();")
    e.add("    xn_init_enums();")
    e.add("    int64_t xn_r = xn_main();")
    e.add("    rt_gc_collect();")
    e.add("    rt_quarantine_flush();")
    e.add("    return (int)xn_r;")
    String res = ""
    if CLS_NAMES.length() > 0 {
        EM ce = new EM()
        ce.tmp = e.tmp
        ce.path = e.path
        Int ci = 0
        while ci < decls.el.length() {
            N d = decls.el.get(ci)
            if d.nm == "ClassDecl" { emitClassSection(d, ce) }
            ci = ci + 1
        }
        e.tmp = ce.tmp
        List<String> fw = []
        ci = 0
        while ci < decls.el.length() {
            N d = decls.el.get(ci)
            if d.nm == "ClassDecl" { emitClassForwards(d, fw, 0) }
            ci = ci + 1
        }
        res = PRELUDE_PRE_FATAL + PRELUDE_FATAL_MID.substring(0, PRELUDE_FATAL_MID.length() - 1) + joinLines(fw) + "static int64_t xn_main();\n\n" + joinLines(ce.ls).substring(0, joinLines(ce.ls).length() - 1) + PRELUDE_TAIL
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
            if d.nm == "StructDecl" { emitStructEarly(d, ee) }
            ci = ci + 1
        }
        EM me = new EM()
        me.tmp = ee.tmp
        me.path = e.path
        ci = 0
        while ci < decls.el.length() {
            N d = decls.el.get(ci)
            if d.nm == "StructDecl" { emitStructMethods(d, me) }
            ci = ci + 1
        }
        e.tmp = me.tmp
        res = PRELUDE_PRE_FATAL + joinLines(ee.ls) + PRELUDE_FATAL_MID + "static int64_t xn_main();\n" + PRELUDE_TAIL_A + joinLines(me.ls) + PRELUDE_TAIL_B
    } else if e.usesList || e.hasMap || e.hasSet {
        if e.hasMap {
            if e.hasGetOr { res = PRELUDE_CONT } else { res = PRELUDE_MAPSET }
        } else {
            res = PRELUDE_ARR
        }
    } else {
        res = PRELUDE_HEAD
        if sc.resultTypes.length() > 0 {
            res = res.substring(0, res.length() - 1)
            Int k = 0
            while k < sc.resultTypes.length() {
                String rk = sc.resultTypes.get(k)
                String vt = resultVal(rk)
                String et = resultErr(rk)
                res = res + "typedef struct { int ok; " + decl(cType(vt), "v") + "; " + decl(cType(et), "err") + "; } " + cType(rk) + ";\n"
                k = k + 1
            }
            res = res + "\n"
        }
        i = 0
        while i < decls.el.length() {
            N d = decls.el.get(i)
            if d.nm == "TopFunc" {
                String nm = unq(txt(fld(d, "Name")))
                if nm != "main" {
                    String rk = typeKey(fld(d, "Ret"))
                    res = res + "static " + cType(rk) + " xn_" + nm + "(" + paramsOf(d) + ");\n"
                }
            }
            i = i + 1
        }
        res = res + "static int64_t xn_main();\n"
        res = res + PRELUDE_TAIL
    }
    e.add("}")
    res = res + ""
    Int j = 0
    while j < e.ls.length() {
        res = res + e.ls.get(j) + "\n"
        j = j + 1
    }
    return res.substring(0, res.length() - 1)
}

static Int main(String[] args) {
    if args.length() < 2 {
        print("xnullc: 用法：xnullc <entryPath> <xnast-v1-ast>")
        return 2
    }
    String path = args[0]
    String ast = args[1]
    if ast.indexOf("(xnast v1 ") == 0 && ast.length() > 11 { ast = ast.substring(10, ast.length() - 11) }
    AP ap = new AP(ast)
    N unit = ap.val()
    print(emitUnit(unit, path))
    return 0
}
