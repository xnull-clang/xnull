// B3-01：xnullc 骨架（XNull 版 AST -> C）。
//
// 输入：<entryPath> <xnast v1 AST dump>
// 输出：与 Go `xnull build --emit-c` 口径一致的 C 文本。
// 本卡只覆盖空 main 与 hello.x；B3-02 起扩展表达式/语句面。

static String PRELUDE = "/* 由 XNull 编译器生成（M4.1 代码生成）。 */\n#include \"rt.h\"\n#include \"rt_gc.h\"\n#include \"xrt.h\"\n#include <inttypes.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n\nstatic void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }\nstatic void xn_print_bool(int v) { fputs(v ? \"true\\n\" : \"false\\n\", stdout); }\nstatic void xn_print_double(double v) { printf(\"%g\\n\", v); }\nstatic void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }\nstatic void xn_print_null(void) { fputs(\"null\\n\", stdout); }\n\n/* 可空值（S1 §2.10）：has=0 表示 null。 */\ntypedef struct { int has; int64_t v; } xn_opt_i;\ntypedef struct { int has; int v; } xn_opt_b;\ntypedef struct { int has; rt_string *v; } xn_opt_s;\n\ntypedef int32_t xn_char; /* S1 Char：Unicode 标量值 */\nstatic rt_string *xn_str_char(int32_t cp) {\n    char buf[8];\n    size_t n = 0;\n    if (cp < 0) { cp = 0xFFFD; }\n    if (cp < 0x80) { buf[n++] = (char)cp; }\n    else if (cp < 0x800) { buf[n++] = (char)(0xC0 | (cp >> 6)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else if (cp < 0x10000) { buf[n++] = (char)(0xE0 | (cp >> 12)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    else { buf[n++] = (char)(0xF0 | (cp >> 18)); buf[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); buf[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); buf[n++] = (char)(0x80 | (cp & 0x3F)); }\n    return rt_string_new(buf, n);\n}\n\nstatic rt_string *xn_str_int(int64_t v) {\n    char buf[32];\n    int n = snprintf(buf, sizeof(buf), \"%lld\", (long long)v);\n    return rt_string_new(buf, (size_t)n);\n}\n\nstatic rt_string *xn_str_double(double v) { char buf[64]; int n = snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_new(buf, (size_t)n); }\nstatic rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }\n\n/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */\nstatic rt_string *xn_alloc_str(size_t n);\n\n/* ---- String 成员（S1 §9.2，字节语义）---- */\nstatic int xn_str_eq(rt_string *a, rt_string *b) {\n    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;\n}\n\nstatic int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }\n\nstatic rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {\n    if (start < 0) { start = 0; }\n    if (n < 0) { n = 0; }\n    if ((size_t)start > s->len) { start = (int64_t)s->len; }\n    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }\n    rt_string *out = xn_alloc_str((size_t)n);\n    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }\n    return out;\n}\n\nstatic int64_t xn_str_indexof(rt_string *s, rt_string *sub) {\n    if (sub->len == 0) { return 0; }\n    if (sub->len > s->len) { return -1; }\n    for (size_t i = 0; i + sub->len <= s->len; i++) {\n        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }\n    }\n    return -1;\n}\n\nstatic int xn_str_startswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes, p->bytes, p->len) == 0;\n}\n\nstatic int xn_str_endswith(rt_string *s, rt_string *p) {\n    if (p->len > s->len) { return 0; }\n    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;\n}\n\nstatic int xn_is_space(uint8_t c) {\n    return c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r';\n}\n\nstatic rt_string *xn_str_trim(rt_string *s) {\n    size_t b = 0, e = s->len;\n    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }\n    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }\n    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));\n}\n\nstatic rt_string *xn_str_upper(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }\n    }\n    return out;\n}\n\nstatic rt_string *xn_str_lower(rt_string *s) {\n    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);\n    for (size_t i = 0; i < out->len; i++) {\n        char c = out->bytes[i];\n        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }\n    }\n    return out;\n}\n\n/* 定长 String 分配走运行时入口：S3-04 起 String 为 GC 对象，\n * 运行时负责分配头/GC 清单登记（main 过渡期仍为 ARC，接口一致）。 */\nstatic rt_string *xn_alloc_str(size_t n) {\n    rt_string *s = rt_string_alloc(n);\n    s->bytes[0] = 0;\n    return s;\n}\n\n/* 拼接：接管 a、b 的所有权，返回新串。 */\nstatic rt_string *xn_concat(rt_string *a, rt_string *b) {\n    rt_string *out = xn_alloc_str(a->len + b->len);\n    memcpy(out->bytes, a->bytes, a->len);\n    memcpy(out->bytes + a->len, b->bytes, b->len);\n    rt_release(a);\n    rt_release(b);\n    return out;\n}\n\nstatic void xn_throw(rt_string *msg) {\n    fprintf(stderr, \"fatal: %.*s\\n\", (int)msg->len, msg->bytes);\n    exit(134);\n}\n\n/* S6-02：xdk.runtime 绑定/发射面（E5 runtime 原语）。 */\nconst char *xdkc_env_get(const char *name, size_t len, size_t *out_len);\nvoid xdkc_diagnose(const char *bytes, size_t len);\nvoid xdkc_exit(int64_t code);\nint64_t xdkc_now_mono_ms(void);\nint64_t xdkc_now_wall_ms(void);\n/* dumpTasks：运行时诊断（非承诺，S6 §4.4）；单行、无堆，计数由调度器维护。 */\nvoid xdkc_dump_tasks(void);\nstatic xn_opt_s xn_env_lookup(rt_string *name) {\n    xn_opt_s r;\n    size_t len = 0;\n    const char *v = xdkc_env_get(name->bytes, name->len, &len);\n    if (v == NULL) { r.has = 0; r.v = NULL; }\n    else { r.has = 1; r.v = rt_string_new(v, len); }\n    return r;\n}\n\n/* S4-02：边界观测输出——单行「[kind] describe」，无堆分配（栈缓冲 + write）。 */\nstatic void xn_report_write(const char *p, size_t n) {\n    if (n > 0) { ssize_t w = write(STDERR_FILENO, p, n); (void)w; }\n}\nstatic void xn_report_line(int64_t kind, rt_string *desc) {\n    const char *name = xrt_error_kind_name((xrt_error_kind)kind);\n    char head[96];\n    size_t off = 0;\n    head[off++] = '[';\n    size_t nl = strlen(name);\n    if (nl > sizeof(head) - 8) { nl = sizeof(head) - 8; }\n    memcpy(head + off, name, nl);\n    off += nl;\n    head[off++] = ']';\n    head[off++] = ' ';\n    xn_report_write(head, off);\n    if (desc != NULL) {\n        char chunk[256];\n        size_t i = 0;\n        while (i < desc->len) {\n            size_t n = desc->len - i;\n            if (n > sizeof(chunk)) { n = sizeof(chunk); }\n            for (size_t k = 0; k < n; k++) {\n                char c = desc->bytes[i + k];\n                chunk[k] = (c == '\\n' || c == '\\r') ? ' ' : c;\n            }\n            xn_report_write(chunk, n);\n            i += n;\n        }\n    }\n    xn_report_write(\"\\n\", 1);\n}\n\n/* ---- GC 根帧与安全点（S3-02）------------------------------------------\n * 根登记用「对象→持有计数」表镜像到运行时根集合：同一对象被多个栈槽/全局\n * 槽位持有时只登记一次，最后一个持有者撤销时才 rt_gc_root_remove。\n * 块级根帧：块进入记录影子栈标记（xn_root_mark），局部赋值后 xn_root_add；\n * 块退出/return/break/continue 恢复到标记，逆序撤销本块登记。\n * 长期根（全局字段/单例/数据枚举项）用 xn_root_hold 登记，不随块恢复撤销。\n * 安全点：GC 分配计数达阈值时执行一次完整收集（S3 §8 分配点/回边；\n * 运行时若暴露阈值 API，这里改为薄调用）。 */\ntypedef struct { void *obj; size_t count; } xn_root_ref;\nstatic xn_root_ref *xn_root_refs = NULL;\nstatic size_t xn_root_ref_n = 0;\nstatic size_t xn_root_ref_cap = 0;\nstatic void  **xn_root_track = NULL;\nstatic size_t  xn_root_depth = 0;\nstatic size_t  xn_root_cap   = 0;\n\nstatic void xn_root_hold(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj == obj) { xn_root_refs[i].count++; return; }\n    }\n    if (xn_root_ref_n == xn_root_ref_cap) {\n        xn_root_ref_cap = xn_root_ref_cap ? xn_root_ref_cap * 2 : 16;\n        xn_root_refs = (xn_root_ref *)realloc(xn_root_refs, xn_root_ref_cap * sizeof(xn_root_ref));\n        if (xn_root_refs == NULL) { abort(); }\n    }\n    xn_root_refs[xn_root_ref_n].obj = obj;\n    xn_root_refs[xn_root_ref_n].count = 1;\n    xn_root_ref_n++;\n    rt_gc_root_add(obj);\n}\nstatic void xn_root_release(void *obj) {\n    if (obj == NULL) { return; }\n    for (size_t i = 0; i < xn_root_ref_n; i++) {\n        if (xn_root_refs[i].obj != obj) { continue; }\n        if (xn_root_refs[i].count > 1) { xn_root_refs[i].count--; return; }\n        rt_gc_root_remove(obj);\n        xn_root_refs[i] = xn_root_refs[--xn_root_ref_n];\n        return;\n    }\n}\nstatic size_t xn_root_mark(void) { return xn_root_depth; }\nstatic void xn_root_add(void *obj) {\n    if (obj == NULL) { return; }\n    xn_root_hold(obj);\n    if (xn_root_depth == xn_root_cap) {\n        xn_root_cap = xn_root_cap ? xn_root_cap * 2 : 16;\n        xn_root_track = (void **)realloc(xn_root_track, xn_root_cap * sizeof(void *));\n        if (xn_root_track == NULL) { abort(); }\n    }\n    xn_root_track[xn_root_depth++] = obj;\n}\nstatic void xn_root_restore(size_t mark) {\n    while (xn_root_depth > mark) {\n        xn_root_release(xn_root_track[--xn_root_depth]);\n    }\n}\n\nstatic size_t xn_gc_alloc_pending = 0;\n#define XN_GC_SAFEPOINT_THRESHOLD 1024\nstatic void *xn_gc_new(const rt_type *type) {\n    xn_gc_alloc_pending++;\n    return rt_gc_new(type);\n}\nstatic void xn_gc_safepoint(void) {\n    if (xn_gc_alloc_pending >= XN_GC_SAFEPOINT_THRESHOLD) {\n        xn_gc_alloc_pending = 0;\n        rt_gc_collect();\n    }\n}\n\n/* Any/Object 装箱（S3 §3）：GC 盒，typeName 供 is/as 拆箱；引用元素由 scan 追踪。 */\ntypedef struct {\n    rt_header hdr;\n    const char *typeName;\n    int64_t i;\n    rt_string *s;\n    void *o;\n} xn_Any;\nstatic void xn_Any_scan(void *p, void (*visit)(void *)) {\n    xn_Any *b = (xn_Any *)p;\n    if (b->s) { visit(b->s); }\n    if (b->o) { visit(b->o); }\n}\nstatic const rt_type RT_TYPE_XN_ANY = { \"Any\", sizeof(xn_Any) - sizeof(rt_header), NULL, xn_Any_scan };\nstatic xn_Any *xn_box_int(int64_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int\"; b->i = v;\n    return b;\n}\nstatic xn_Any *xn_box_int32(int32_t v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Int32\"; b->i = (int64_t)v;\n    return b;\n}\nstatic xn_Any *xn_box_bool(int v) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"Bool\"; b->i = v ? 1 : 0;\n    return b;\n}\nstatic xn_Any *xn_box_str(rt_string *s) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    b->typeName = \"String\";\n    if (s != NULL) { rt_retain(s); }\n    b->s = s;\n    return b;\n}\n/* 对象装箱：类型名取运行期分配头的类型描述符（动态类型），ARC 载荷持有一份引用，\n * GC 载荷不计数（由 GC 管理）。 */\nstatic xn_Any *xn_box_obj(void *o) {\n    xn_Any *b = (xn_Any *)xn_gc_new(&RT_TYPE_XN_ANY);\n    if (o != NULL) {\n        b->typeName = ((rt_object *)o)->hdr.type->name;\n        if (((rt_object *)o)->hdr.kind == RT_KIND_ARC) { rt_retain(o); }\n        b->o = o;\n    }\n    return b;\n}\nstatic int xn_any_is(xn_Any *b, const char *typeName) {\n    return b != NULL && b->typeName != NULL && strcmp(b->typeName, typeName) == 0;\n}\n/* 拆箱：类型匹配才取值；nullSafe=0 时类型不匹配是 fatal（as），=1 返回零值（as?）。 */\nstatic int64_t xn_any_get_int(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) { return b->i; }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return 0;\n}\nstatic rt_string *xn_any_get_str(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->s != NULL) { rt_retain(b->s); }\n        return b->s;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\nstatic void *xn_any_get_obj(xn_Any *b, const char *typeName, int nullSafe) {\n    if (xn_any_is(b, typeName)) {\n        if (b->o != NULL && ((rt_object *)b->o)->hdr.kind == RT_KIND_ARC) { rt_retain(b->o); }\n        return b->o;\n    }\n    if (!nullSafe) { rt_fatal(\"Any 拆箱类型不匹配（S3 §3）\"); }\n    return NULL;\n}\n\n/* 除零 fatal（S1 §10.4）：与解释路径同口径，退出码 134，入口不执行。 */\nstatic void xn_fatal_div(void) {\n    fprintf(stderr, \"xnull: fatal: 除零\\n\");\n    fflush(stderr);\n    exit(134);\n}\nstatic int64_t xn_div_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a / b;\n}\nstatic int64_t xn_mod_i64(int64_t a, int64_t b) {\n    if (b == 0) { xn_fatal_div(); }\n    return a % b;\n}\n/* S6-03：sys Async/Process 原生原型（E5 runtime；Context/出参形态不经 .xfb） */\nextern void *xdkc_file_open_read_async(xrt_context *, const char *, size_t, int32_t *);\nextern void *xdkc_file_open_write_async(xrt_context *, const char *, size_t, int32_t *);\nextern int64_t xdkc_file_read_async(xrt_context *, void *, void *, size_t, int32_t *);\nextern int32_t xdkc_file_write_async(xrt_context *, void *, const void *, size_t);\nextern int32_t xdkc_file_close_async(xrt_context *, void *);\nextern void *xdkc_dir_open_async(xrt_context *, const char *, size_t, int32_t *);\nextern const char *xdkc_dir_read_async(xrt_context *, void *, int32_t *);\nextern int32_t xdkc_dir_close_async(xrt_context *, void *);\nextern void *xdkc_proc_spawn(const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_wait(void *, int32_t *);\nextern int32_t xdkc_proc_kill(void *, int32_t);\nextern int32_t xdkc_proc_close(void *);\nextern int32_t xdkc_proc_run_async(xrt_context *, const char *, size_t, int32_t *);\nextern int32_t xdkc_proc_status_async(xrt_context *, const char *, size_t);\n/* S6-04：xdk.sys 内嵌资源读取原生原型（E5 runtime） */\nextern int32_t xdkc_resource_exists(const char *, size_t);\nextern int32_t xdkc_resource_size(const char *, size_t, int64_t *);\nextern int32_t xdkc_read_resource(xrt_context *, const char *, size_t, xrt_bytes_buf **, int32_t *);\nextern int32_t xdkc_read_resource_text(xrt_context *, const char *, size_t, xrt_text **, int32_t *);\nextern int32_t xdkc_list_resources(xrt_context *, const char *, size_t, const char ***, size_t *, int32_t *);\nextern void xdkc_list_resources_free(const char **);\ntypedef void *xn_proto_Error;\ntypedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\ntypedef int64_t xn_Enum_ErrorKind;\nstatic rt_string *xn_enum_ErrorKind_name(int64_t v) {\n    switch (v) {\n    case 0: return rt_string_from_c(\"InvalidArgument\");\n    case 1: return rt_string_from_c(\"NotFound\");\n    case 2: return rt_string_from_c(\"AlreadyExists\");\n    case 3: return rt_string_from_c(\"PermissionDenied\");\n    case 4: return rt_string_from_c(\"Io\");\n    case 5: return rt_string_from_c(\"Network\");\n    case 6: return rt_string_from_c(\"Timeout\");\n    case 7: return rt_string_from_c(\"Cancelled\");\n    case 8: return rt_string_from_c(\"Busy\");\n    case 9: return rt_string_from_c(\"Unavailable\");\n    case 10: return rt_string_from_c(\"DataCorrupted\");\n    case 11: return rt_string_from_c(\"Unsupported\");\n    case 12: return rt_string_from_c(\"OutOfMemory\");\n    case 13: return rt_string_from_c(\"Internal\");\n    default: return xn_str_int(v);\n    }\n}\n\nstatic void xn_fatal_oob(void);\nstatic void xn_fatal_oob(void) {\n    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n    exit(134);\n}\n\n\nstatic int64_t xn_main();\n\nstatic void xn_init_vtables(void) {\n}\n\nstatic void xn_init_enums(void) {\n}\n\nstatic rt_string *xn_result_error_copy_rt(rt_string *err) {\n    return rt_string_new(err->bytes, err->len);\n}\n\n";

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

    void ws() {
        while self.p < self.n && self.ch(self.p) == " " { self.p = self.p + 1 }
    }

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
        } else {
            b = b + c
        }
        i = i + 1
    }
    return b
}

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

static Int lineOf(N n) {
    N pos = fld(n, "P")
    return dec(txt(fld(pos, "Line")))
}

class SC {
    String ret = ""
    String root = "xn_t1"
}

class EM {
    List<String> ls = []
    Int tmp = 1
    String path = ""

    void add(String s) { self.ls.push(s) }

    String nt() {
        self.tmp = self.tmp + 1
        return "xn_t" + str(self.tmp)
    }
}

static String emitInt(N x) {
    if x.nm == "IntLitExpr" { return unq(txt(fld(x, "Text"))) }
    if x.nm == "Binary" {
        String op = unq(txt(fld(x, "Op")))
        return "(" + emitInt(fld(x, "L")) + " " + op + " " + emitInt(fld(x, "R")) + ")"
    }
    return "0"
}

static String firstArg(N call) {
    N args = fld(call, "Args")
    if args.el.length() > 0 { return firstArg0(args.el.get(0)) }
    return ""
}

static String firstArg0(N x) { return x.nm }

static String emitStr(N x, EM e) {
    if x.nm == "StrLitExpr" {
        N parts = fld(x, "Parts")
        String text = ""
        if parts.el.length() > 0 {
            N part = parts.el.get(0)
            text = unq(txt(fld(part, "Text")))
        }
        String t = e.nt()
        e.add("rt_string *" + t + " = rt_string_from_c(" + q(text) + ");")
        e.add("xn_root_add(" + t + ");")
        return t
    }
    if x.nm == "Binary" {
        String l = emitStr(fld(x, "L"), e)
        String r = emitStr(fld(x, "R"), e)
        String t = e.nt()
        e.add("rt_string *" + t + " = xn_concat(" + l + ", " + r + ");")
        e.add("xn_root_add(" + t + ");")
        return t
    }
    if x.nm == "Call" {
        N callee = fld(x, "Callee")
        if callee.nm == "IdentExpr" && unq(txt(fld(callee, "Name"))) == "str" {
            N args = fld(x, "Args")
            String t = e.nt()
            String a = "0"
            if args.el.length() > 0 { a = emitInt(args.el.get(0)) }
            e.add("rt_string *" + t + " = xn_str_int(" + a + ");")
            e.add("xn_root_add(" + t + ");")
            return t
        }
    }
    return e.nt()
}

static N findMain(N unit) {
    N decls = fld(unit, "Decls")
    Int i = 0
    while i < decls.el.length() {
        N d = decls.el.get(i)
        if d.nm == "TopFunc" && unq(txt(fld(d, "Name"))) == "main" { return d }
        i = i + 1
    }
    return new N()
}

static String emitUnit(N unit, String path) {
    EM e = new EM()
    SC sc = new SC()
    e.path = path
    N fn = findMain(unit)
    N body = fld(fn, "Body")
    N stmts = fld(body, "Stmts")
    e.add("int64_t xn_main() {")
    e.add("size_t " + sc.root + " = xn_root_mark();")
    sc.ret = "xn_t2"
    Int i = 0
    while i < stmts.el.length() {
        N st = stmts.el.get(i)
        e.add("#line " + str(lineOf(st)) + " \"" + path + "\"")
        if st.nm == "ExprStmt" {
            N call = fld(st, "X")
            if call.nm == "Call" {
                N args = fld(call, "Args")
                if args.el.length() > 0 {
                    String t = emitStr(args.el.get(0), e)
                    e.add("xn_print_str(" + t + ");")
                    e.add("rt_release(" + t + ");")
                }
            }
        } else if st.nm == "ReturnStmt" {
            String t = e.nt()
            e.add("int64_t " + t + " = " + emitInt(fld(st, "Value")) + ";")
            sc.ret = t
        }
        i = i + 1
    }
    e.add("    {")
    e.add("xn_root_restore(" + sc.root + ");")
    e.add("    }")
    e.add("")
    e.add("return " + sc.ret + ";")
    e.add("}")
    e.add("")
    e.add("int main(void) {")
    e.add("    xrt_runtime_init();")
    e.add("    xn_init_vtables();")
    e.add("    xn_init_enums();")
    e.add("    int64_t xn_r = xn_main();")
    e.add("    rt_gc_collect();")
    e.add("    rt_quarantine_flush();")
    e.add("    return (int)xn_r;")
    e.add("}")
    String res = PRELUDE
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
    if ast.indexOf("(xnast v1 ") == 0 && ast.length() > 11 {
        ast = ast.substring(10, ast.length() - 11)
    }
    AP ap = new AP(ast)
    N unit = ap.val()
    print(emitUnit(unit, path))
    return 0
}
