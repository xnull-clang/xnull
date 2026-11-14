// 资源表生成（最小 resman）。
//
// 用法：
//   resman <资源目录> <输出.c> [<文件> …]
//
// 约定：只处理**单层目录**下的常规文件；文件名（相对资源目录）即资源名，
// 由调用方（xnull-build.sh）用 shell glob 展开并传入，按名字节序排序。
// 输出与 Go `impl/internal/devtool` 的 renderResources 逐字节一致（空表/单文件/多文件）。
//
// 未支持（后续）：子目录递归、符号链接校验、glob includes/excludes、二进制资源。
package xdk.build.resource
import xdk.sys

           
                           
                           
 

static String hexUp(Int v) {
    String digits = "0123456789ABCDEF"
    return digits.substring(v, 1)
}

static void sortNames(List<String> xs) {
    Int i = 1
    while i < xs.length() {
        String v = xs.get(i)
        Int j = i - 1
        Bool moving = true
        while moving {
            if j < 0 { moving = false }
            else {
                String p = xs.get(j)
                Int c = cmpStr(p, v)
                if c <= 0 { moving = false }
                else {
                    xs.set(j + 1, p)
                    j = j - 1
                }
            }
        }
        xs.set(j + 1, v)
        i = i + 1
    }
}

static Int cmpStr(String a, String b) {
    Bytes x = Bytes.fromString(a)
    Bytes y = Bytes.fromString(b)
    Int n = x.length()
    if y.length() < n { n = y.length() }
    Int i = 0
    while i < n {
        Int cx = x.get(i)
        Int cy = y.get(i)
        if cx != cy {
            if cx < cy { return -1 }
            return 1
        }
        i = i + 1
    }
    if x.length() == y.length() { return 0 }
    if x.length() < y.length() { return -1 }
    return 1
}

static String baseName(String path) {
    Int i = path.length() - 1
    Bool go = true
    while go {
        if i < 0 { go = false }
        else if path.substring(i, 1) == "/" { go = false }
        else { i = i - 1 }
    }
    return path.substring(i + 1, path.length() - i - 1)
}

static String bytesBlock(String data) {
    Bytes b = Bytes.fromString(data)
    String s = ""
    Int i = 0
    while i < b.length() {
        s = s + "    "
        Int k = 0
        while k < 16 && i + k < b.length() {
            if k > 0 { s = s + ", " }
            Int v = b.get(i + k)
            s = s + "0x" + hexUp(v / 16) + hexUp(v % 16)
            k = k + 1
        }
        s = s + ",\n"
        i = i + 16
    }
    return s
}

static String header() {
    String s = "/* 由 impl/tools/gen_resources.py 生成（构建期产物，勿手改；S8 §5.6）。\n"
    s = s + " * 资源表按名称升序；查找为二分；空表零成本。 */\n"
    s = s + "#include <stddef.h>\n"
    s = s + "#include <string.h>\n"
    s = s + "\n"
    s = s + "typedef struct {\n"
    s = s + "    const char         *name;\n"
    s = s + "    const unsigned char *data;\n"
    s = s + "    size_t              len;\n"
    s = s + "} xrt_resource;\n"
    s = s + "\n"
    return s
}

static String emptyBody() {
    String s = "/* 空表：无资源的工程零成本 */\n"
    s = s + "size_t xrt_resource_count(void) { return 0; }\n"
    s = s + "\n"
    s = s + "int xrt_resource_get(const char *name, size_t nlen,\n"
    s = s + "                     const unsigned char **out, size_t *out_len) {\n"
    s = s + "    (void)name; (void)nlen;\n"
    s = s + "    *out = 0; *out_len = 0;\n"
    s = s + "    return 1;\n"
    s = s + "}\n"
    s = s + "/* ---- 资源枚举（S6-04/XDK-10）：按名称升序；供 listResources 枚举 ---- */\n"
    s = s + "int xrt_resource_at(size_t i, const char **name, size_t *nlen,\n"
    s = s + "                    const unsigned char **out, size_t *out_len) {\n"
    s = s + "    (void)i; (void)name; (void)nlen; (void)out; (void)out_len;\n"
    s = s + "    return 1;\n"
    s = s + "}\n"
    return s
}

static String tableBody(List<String> names, List<String> datas) {
    String s = "static const xrt_resource g_xrt_resources[] = {\n"
    Int i = 0
    while i < names.length() {
        Bytes b = Bytes.fromString(datas.get(i))
        s = s + "    /* " + names.get(i) + "（" + str(b.length()) + " 字节） */\n"
        s = s + "    {\n"
        s = s + "        .name = \"" + names.get(i) + "\",\n"
        s = s + "        .data = (const unsigned char[]){\n"
        s = s + bytesBlock(datas.get(i))
        s = s + "        },\n"
        s = s + "        .len = " + str(b.length()) + ",\n"
        s = s + "    },\n"
        i = i + 1
    }
    s = s + "};\n"
    s = s + "\n"
    s = s + "size_t xrt_resource_count(void) {\n"
    s = s + "    return sizeof(g_xrt_resources) / sizeof(g_xrt_resources[0]);\n"
    s = s + "}\n"
    s = s + "\n"
    s = s + "int xrt_resource_get(const char *name, size_t nlen,\n"
    s = s + "                     const unsigned char **out, size_t *out_len) {\n"
    s = s + "    size_t lo = 0, hi = xrt_resource_count();\n"
    s = s + "    while (lo < hi) {\n"
    s = s + "        size_t mid = lo + (hi - lo) / 2;\n"
    s = s + "        const xrt_resource *r = &g_xrt_resources[mid];\n"
    s = s + "        size_t min_len = nlen < strlen(r->name) ? nlen : strlen(r->name);\n"
    s = s + "        int cmp = memcmp(name, r->name, min_len);\n"
    s = s + "        if (cmp == 0) {\n"
    s = s + "            if (nlen == strlen(r->name)) {\n"
    s = s + "                *out = r->data; *out_len = r->len; return 0;\n"
    s = s + "            }\n"
    s = s + "            cmp = nlen < strlen(r->name) ? -1 : 1;\n"
    s = s + "        }\n"
    s = s + "        if (cmp < 0) { hi = mid; } else { lo = mid + 1; }\n"
    s = s + "    }\n"
    s = s + "    return 1; /* 未找到：显式区分，不静默给空 */\n"
    s = s + "}\n"
    s = s + "/* ---- 资源枚举（S6-04/XDK-10）：按名称升序；供 listResources 枚举 ---- */\n"
    s = s + "int xrt_resource_at(size_t i, const char **name, size_t *nlen,\n"
    s = s + "                    const unsigned char **out, size_t *out_len) {\n"
    s = s + "    if (i >= xrt_resource_count()) { return 1; }\n"
    s = s + "    const xrt_resource *r = &g_xrt_resources[i];\n"
    s = s + "    *name = r->name; *nlen = strlen(r->name);\n"
    s = s + "    *out = r->data; *out_len = r->len;\n"
    s = s + "    return 0;\n"
    s = s + "}\n"
    return s
}

static Int run(String resDir, String outPath, String[] a, Int start) {
    List<String> names = []
    List<String> datas = []
    Int i = start
    while i < a.length() {
        String f = a[i]
        // shell glob 未展开时会传入字面量（如 `dir/*`）：不存在即视为无文件（空表）。
        if pathExists(f) {
            names.push(baseName(f))
            datas.push(readFileText(f))
        }
        i = i + 1
    }
    sortNames(names)
    // 名称排序后按新顺序取数据（重新按名字匹配文件；文件数很小）。
    List<String> sortedData = []
    i = 0
    while i < names.length() {
        Int k = start
        while k < a.length() {
            if baseName(a[k]) == names.get(i) { sortedData.push(readFileText(a[k])) }
            k = k + 1
        }
        i = i + 1
    }
    String body = ""
    if names.length() == 0 {
        body = emptyBody()
    } else {
        body = tableBody(names, sortedData)
    }
    writeFileText(outPath, header() + body)
    i = 0
    while i < names.length() {
        print("resource\t" + names.get(i))
        i = i + 1
    }
    if names.length() == 0 {
        print("resource\t（空表）")
    }
    return 0
}

static Int main(String[] args) {
    List<String> seed = ["x"]
    seed.push("y")
    // 用法：resman <out.c> <资源目录> [<文件> …]
    if args.length() < 2 {
        print("resman: 需要 <输出.c> <资源目录> [<文件> …]")
        return 2
    }
    return run(args[1], args[0], args, 2)
}
