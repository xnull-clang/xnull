#!/usr/bin/env python3
"""B4c-03：用原生 xparser 生成 xnast bundle（替代已删除的 Go --emit-ast-bundle）。

规则对齐 Go impl/internal/frontbridge/bundle.go：
- 依赖后序（依赖先于使用方，入口最后）；
- xdk.<pkg> → <root>/impl/lib/xdk/<pkg>.x（存在时）；
- 其他点分导入 → <entryDir>/<path...>.x；
- 每个文件的 AST 由 xparser --file 生成，文本原样写入。

用法：native-bundle.py <root> <xparser> <entry>  → stdout 输出 bundle JSON
"""
import json
import os
import re
import subprocess
import sys


def ast_of(xparser, path):
    r = subprocess.run([xparser, "--file", path], capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("xparser --file %s 失败：%s" % (path, r.stderr.decode("utf-8", "replace")[:200]))
    return r.stdout.decode("utf-8")


# AST 是 S 表达式；只取 (Imports ...) 段，避免误读函数体里的字符串。
def imports_of(ast):
    i = ast.find("(Imports ")
    if i < 0:
        return []
    depth = 0
    j = i
    while j < len(ast):
        ch = ast[j]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                j += 1
                break
        j += 1
    seg = ast[i:j]
    out = []
    for m in re.finditer(r"\(Path\s+\(slice([^)]*)\)\)", seg):
        parts = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))
        parts = [p.encode().decode("unicode_escape") for p in parts]
        if parts:
            out.append(parts)
    return out


def main():
    root, xparser, entry = sys.argv[1], sys.argv[2], sys.argv[3]
    root = os.path.abspath(root)
    entry = os.path.abspath(entry)
    os.chdir(root)
    entry_dir = os.path.dirname(entry)
    xdk_dir = os.path.join(root, "impl", "lib", "xdk")
    state = {}
    out = []

    def visit(path):
        key = os.path.normpath(path)
        st = state.get(key, 0)
        if st == 1:
            raise RuntimeError("import 环：%s" % key)
        if st == 2:
            return
        state[key] = 1
        ast = ast_of(xparser, key)
        for imp in imports_of(ast):
            if imp[0] == "xdk":
                if len(imp) >= 2:
                    dep = os.path.join(xdk_dir, imp[1] + ".x")
                    if os.path.exists(dep):
                        visit(dep)
                continue
            dep = os.path.join(entry_dir, *imp) + ".x"
            visit(dep)
        state[key] = 2
        out.append({"path": os.path.abspath(key), "ast": ast})

    visit(entry)
    json.dump({"version": "xnast-bundle v1", "files": out}, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
