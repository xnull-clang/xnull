#!/usr/bin/env python3
"""用原生 xparser 生成包感知的 xnast bundle。

- import P 兼容 legacy P.x；P/ 中的源码与 P.x 聚合为一个包槽位；
- import P.C 解析 P/C.x，并校验 package 与同名 class；
- 依赖后序、包级环检测、入口最后；同包文件确定性排序。

用法：native-bundle.py <root> <xparser> <entry>  → stdout 输出 bundle JSON
"""
import json
import os
import subprocess
import sys

from package_resolver import PackageResolver, ResolveError, imports_of


def ast_of(xparser, path):
    r = subprocess.run([xparser, "--file", path], capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("xparser --file %s 失败：%s" % (
            path, r.stderr.decode("utf-8", "replace")[:200]))
    ast = r.stdout.decode("utf-8")
    if not ast.startswith("(xnast v1"):
        raise RuntimeError("xparser --file %s 未返回完整 AST" % path)
    return ast


def build_bundle(root, xparser, entry):
    root = os.path.abspath(root)
    entry = os.path.abspath(entry)
    resolver = PackageResolver(root, os.path.dirname(entry))
    state = {}
    out = []

    def visit(parts):
        resolution = resolver.resolve(parts)
        key = resolution.package + "@" + resolution.primary
        st = state.get(key, 0)
        if st == 1:
            raise ResolveError("import 包环：%s" % resolution.package)
        if st == 2:
            return
        state[key] = 1
        _units, slot = resolver.parse(
            resolution, lambda path: ast_of(xparser, path))
        for imported in imports_of(slot["ast"]):
            visit(imported)
        state[key] = 2
        slot["path"] = resolution.slot or slot["path"]
        out.append(slot)

    entry_resolution = resolver.resolve_entry(entry)
    if entry_resolution is None:
        entry_ast = ast_of(xparser, entry)
    else:
        _units, entry_slot = resolver.parse(
            entry_resolution, lambda path: ast_of(xparser, path))
        entry_ast = entry_slot["ast"]
    for imported in imports_of(entry_ast):
        visit(imported)
    out.append({"path": entry, "ast": entry_ast})
    return {"version": "xnast-bundle v1", "files": out}


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("用法：native-bundle.py <root> <xparser> <entry>\n")
        return 2
    root, xparser, entry = sys.argv[1], sys.argv[2], sys.argv[3]
    try:
        os.chdir(os.path.abspath(root))
        bundle = build_bundle(root, xparser, entry)
    except (ResolveError, RuntimeError, OSError) as exc:
        sys.stderr.write("native-bundle: %s\n" % exc)
        return 1
    json.dump(bundle, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
