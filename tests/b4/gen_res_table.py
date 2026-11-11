#!/usr/bin/env python3
"""资源表 C 生成（无 Go 版，B4c-02b）。

用法：gen_res_table.py <资源目录> <输出.c>

输出与 `impl/internal/devtool.renderResources` 逐字节一致：
表头署名 + xrt_resource 结构 + 按名称字节序的条目 + 二分查找 + xrt_resource_at 枚举接口。
"""
import os
import sys


def render(entries):
    b = []
    b.append("/* 由 impl/tools/gen_resources.py 生成（构建期产物，勿手改；S8 §5.6）。")
    b.append(" * 资源表按名称升序；查找为二分；空表零成本。 */")
    b.append("#include <stddef.h>")
    b.append("#include <string.h>")
    b.append("")
    b.append("typedef struct {")
    b.append("    const char         *name;")
    b.append("    const unsigned char *data;")
    b.append("    size_t              len;")
    b.append("} xrt_resource;")
    b.append("")
    if not entries:
        b.append("/* 空表：无资源的工程零成本 */")
        b.append("size_t xrt_resource_count(void) { return 0; }")
        b.append("")
        b.append("int xrt_resource_get(const char *name, size_t nlen,")
        b.append("                     const unsigned char **out, size_t *out_len) {")
        b.append("    (void)name; (void)nlen;")
        b.append("    *out = 0; *out_len = 0;")
        b.append("    return 1;")
        b.append("}")
        add_index(b, True)
        return "\n".join(b) + "\n"

    b.append("static const xrt_resource g_xrt_resources[] = {")
    for name, data in entries:
        b.append("    /* %s（%d 字节） */" % (name, len(data)))
        b.append("    {")
        b.append('        .name = "%s",' % name)
        b.append("        .data = (const unsigned char[]){")
        for i in range(0, len(data), 16):
            chunk = data[i:i + 16]
            b.append("    " + ", ".join("0x%02X" % c for c in chunk) + ",")
        b.append("        },")
        b.append("        .len = %d," % len(data))
        b.append("    },")
    b.append("};")
    b.append("")
    b.append("size_t xrt_resource_count(void) {")
    b.append("    return sizeof(g_xrt_resources) / sizeof(g_xrt_resources[0]);")
    b.append("}")
    b.append("")
    b.append("int xrt_resource_get(const char *name, size_t nlen,")
    b.append("                     const unsigned char **out, size_t *out_len) {")
    b.append("    size_t lo = 0, hi = xrt_resource_count();")
    b.append("    while (lo < hi) {")
    b.append("        size_t mid = lo + (hi - lo) / 2;")
    b.append("        const xrt_resource *r = &g_xrt_resources[mid];")
    b.append("        size_t min_len = nlen < strlen(r->name) ? nlen : strlen(r->name);")
    b.append("        int cmp = memcmp(name, r->name, min_len);")
    b.append("        if (cmp == 0) {")
    b.append("            if (nlen == strlen(r->name)) {")
    b.append("                *out = r->data; *out_len = r->len; return 0;")
    b.append("            }")
    b.append("            cmp = nlen < strlen(r->name) ? -1 : 1;")
    b.append("        }")
    b.append("        if (cmp < 0) { hi = mid; } else { lo = mid + 1; }")
    b.append("    }")
    b.append("    return 1; /* 未找到：显式区分，不静默给空 */")
    b.append("}")
    add_index(b, False)
    return "\n".join(b) + "\n"


def add_index(b, empty):
    b.append("/* ---- 资源枚举（S6-04/XDK-10）：按名称升序；供 listResources 枚举 ---- */")
    b.append("int xrt_resource_at(size_t i, const char **name, size_t *nlen,")
    b.append("                    const unsigned char **out, size_t *out_len) {")
    if empty:
        b.append("    (void)i; (void)name; (void)nlen; (void)out; (void)out_len;")
        b.append("    return 1;")
    else:
        b.append("    if (i >= xrt_resource_count()) { return 1; }")
        b.append("    const xrt_resource *r = &g_xrt_resources[i];")
        b.append("    *name = r->name; *nlen = strlen(r->name);")
        b.append("    *out = r->data; *out_len = r->len;")
        b.append("    return 0;")
    b.append("}")


def collect(root):
    out = []
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            out.append((rel, open(p, "rb").read()))
    out.sort(key=lambda x: x[0])
    return out


def main():
    if len(sys.argv) < 3:
        print("gen_res_table: 需要 <资源目录> <输出.c>", file=sys.stderr)
        return 2
    root, dst = sys.argv[1], sys.argv[2]
    if not os.path.isdir(root):
        print("gen_res_table: 资源目录不存在：%s" % root, file=sys.stderr)
        return 1
    text = render(collect(root))
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    with open(dst, "w", encoding="utf-8") as f:
        f.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
