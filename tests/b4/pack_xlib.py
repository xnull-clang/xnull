#!/usr/bin/env python3
"""最小 .xlib 打包（B4b-05a）：与 Go internal/artifact.Build 同布局。

用法：
  pack_xlib.py <out.xlib> <module-dir> <groupId> <artifactId> <version> <packaging> [<coord> <ver> ...]

内容：`xnull.project` + `src/**`（递归）+ `xlib.meta`；条目按名称字节序、Store 压缩、零时间戳。
说明：Go 用 archive/zip 写出的字节与 Python zipfile 不完全相同（创建者版本/额外字段），
本工具保证 **布局与 xlib.meta 文本一致**，不承诺 zip 字节级一致。
"""
import hashlib
import os
import sys
import zipfile


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def collect(module_dir: str) -> list:
    files = []
    for root, _dirs, names in os.walk(module_dir):
        for n in names:
            p = os.path.join(root, n)
            rel = os.path.relpath(p, module_dir).replace(os.sep, "/")
            if rel.startswith("target/"):
                continue
            files.append(rel)
    files.sort()
    return files


def main() -> int:
    if len(sys.argv) < 7:
        print("pack_xlib: 参数不足", file=sys.stderr)
        return 2
    out = sys.argv[1]
    mod = sys.argv[2]
    gid, aid, ver, pack = sys.argv[3:7]
    deps = []
    rest = sys.argv[7:]
    for i in range(0, len(rest) - 1, 2):
        deps.append((rest[i], rest[i + 1]))
    deps.sort()

    files = collect(mod)
    meta = []
    meta.append("xlib {")
    meta.append("  groupId    = %s" % gid)
    meta.append("  artifactId = %s" % aid)
    meta.append("  version    = %s" % ver)
    meta.append("  packaging  = %s" % pack)
    for c, v in deps:
        meta.append("  dependency %s %s" % (c, v))
    meta.append("  files {")
    for rel in files:
        meta.append("    %s %s" % (sha256_file(os.path.join(mod, rel)), rel))
    meta.append("  }")
    meta.append("}")
    meta_text = "\n".join(meta) + "\n"

    os.makedirs(os.path.dirname(out), exist_ok=True)
    names = sorted(files + ["xlib.meta"])
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_STORED) as z:
        for name in names:
            zi = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_STORED
            zi.external_attr = 0o644 << 16
            data = meta_text.encode() if name == "xlib.meta" else open(os.path.join(mod, name), "rb").read()
            z.writestr(zi, data)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
