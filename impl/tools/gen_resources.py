#!/usr/bin/env python3
"""构建期资源表生成器（S8 §5.6；M4.6b-2）

用法：gen_resources.py <资源目录> <输出.c>

合同：
- 确定性（DET-01 延伸）：按资源名（相对路径，'/' 分隔）升序生成；
- 资源名限 [A-Za-z0-9_.-]（相对路径整体校验），同名冲突显式报错；
- 空目录生成空表（无资源工程零成本，不产生死数据）；
- 输出为自包含 C 文件：`xrt_resource_get` 二分查找（升序前提由生成器保证）；
  不依赖运行时内部符号，只依赖 libc（接入 build 清单等 P-10 回签）。
"""
import os
import re
import sys

NAME_RE = re.compile(r"[A-Za-z0-9_.\-]+")


def die(msg: str) -> "None":
    print("gen_resources: " + msg, file=sys.stderr)
    sys.exit(2)


def collect(src: str):
    entries = []
    seen = set()
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for fn in sorted(files):
            path = os.path.join(root, fn)
            rel = os.path.relpath(path, src).replace(os.sep, "/")
            if not NAME_RE.fullmatch(rel):
                die("资源名非法（限 [A-Za-z0-9_.-]）：%s" % rel)
            if rel in seen:
                die("资源名重复：%s" % rel)
            seen.add(rel)
            with open(path, "rb") as f:
                entries.append((rel, f.read()))
    entries.sort(key=lambda e: e[0])  # 确定性：升序
    return entries


def c_bytes(data: bytes) -> str:
    if not data:
        return ""
    parts = []
    for i in range(0, len(data), 16):
        chunk = data[i:i + 16]
        parts.append("    " + ", ".join("0x%02X" % b for b in chunk) + ",")
    return "\n".join(parts)


def emit(entries, out_path: str) -> None:
    lines = []
    lines.append("/* 由 impl/tools/gen_resources.py 生成（构建期产物，勿手改；S8 §5.6）。")
    lines.append(" * 资源表按名称升序；查找为二分；空表零成本。 */")
    lines.append("#include <stddef.h>")
    lines.append("#include <string.h>")
    lines.append("")
    lines.append("typedef struct {")
    lines.append("    const char         *name;")
    lines.append("    const unsigned char *data;")
    lines.append("    size_t              len;")
    lines.append("} xrt_resource;")
    lines.append("")
    if entries:
        lines.append("static const xrt_resource g_xrt_resources[] = {")
        for name, data in entries:
            sym = "xrt_res_" + re.sub(r"[^A-Za-z0-9]", "_", name)
            lines.append("    /* %s（%d 字节） */" % (name, len(data)))
            lines.append("    {")
            lines.append('        .name = "%s",' % name)
            lines.append("        .data = (const unsigned char[]){")
            if data:
                lines.append(c_bytes(data))
            lines.append("        },")
            lines.append("        .len = %d," % len(data))
            lines.append("    },")
        lines.append("};")
        lines.append("")
        lines.append("size_t xrt_resource_count(void) {")
        lines.append("    return sizeof(g_xrt_resources) / sizeof(g_xrt_resources[0]);")
        lines.append("}")
        lines.append("")
        lines.append("int xrt_resource_get(const char *name, size_t nlen,")
        lines.append("                     const unsigned char **out, size_t *out_len) {")
        lines.append("    size_t lo = 0, hi = xrt_resource_count();")
        lines.append("    while (lo < hi) {")
        lines.append("        size_t mid = lo + (hi - lo) / 2;")
        lines.append("        const xrt_resource *r = &g_xrt_resources[mid];")
        lines.append("        size_t min_len = nlen < strlen(r->name) ? nlen : strlen(r->name);")
        lines.append("        int cmp = memcmp(name, r->name, min_len);")
        lines.append("        if (cmp == 0) {")
        lines.append("            if (nlen == strlen(r->name)) {")
        lines.append("                *out = r->data; *out_len = r->len; return 0;")
        lines.append("            }")
        lines.append("            cmp = nlen < strlen(r->name) ? -1 : 1;")
        lines.append("        }")
        lines.append("        if (cmp < 0) { hi = mid; } else { lo = mid + 1; }")
        lines.append("    }")
        lines.append("    return 1; /* 未找到：显式区分，不静默给空 */")
        lines.append("}")
    else:
        lines.append("/* 空表：无资源的工程零成本 */")
        lines.append("size_t xrt_resource_count(void) { return 0; }")
        lines.append("")
        lines.append("int xrt_resource_get(const char *name, size_t nlen,")
        lines.append("                     const unsigned char **out, size_t *out_len) {")
        lines.append("    (void)name; (void)nlen;")
        lines.append("    *out = 0; *out_len = 0;")
        lines.append("    return 1;")
        lines.append("}")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main() -> int:
    if len(sys.argv) != 3:
        die("用法：gen_resources.py <资源目录> <输出.c>")
    src, out_path = sys.argv[1], sys.argv[2]
    if not os.path.isdir(src):
        die("资源目录不存在：%s" % src)
    emit(collect(src), out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
