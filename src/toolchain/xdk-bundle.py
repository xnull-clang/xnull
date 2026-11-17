#!/usr/bin/env python3
"""XDK 源码层 bundle（过渡）：把 `import xdk.*` 解析到
src/xdk/<layer>/<domain>/ 下的分层源码，生成 xnullc 可消费的 AST bundle
与 FFI 投影。

背景：产品编译器当前仍含部分 XDK 内建发射。本脚本按入口 import 闭包
只载入实际引用的包（及其传递依赖），把同名包目录分片聚合进稳定包槽位，
并生成该闭包所需的 raw FFI 投影。

用法：xdk-bundle.py <root> <entry.x> <outdir>
输出：<outdir>/bundle.json、<outdir>/project.txt；stdout 打印 bundle 文件数。

范围：未在 UNITS 注册的 xdk 包显式报错；目录拆分不得增加槽位数。
"""
import json
import os
import shutil
import subprocess
import sys

from package_resolver import (PackageResolver, Resolution, ResolveError,
                              imports_of)

# 有源码层实现的包 → legacy 主单元；同名包目录作为该单元的物理分片。
UNITS = {
    "errors": "src/xdk/core/errors/Errors.x",
    "text": "src/xdk/text/full/Text.x",
    "sys": "src/xdk/io/system/Sys.x",
    "runtime": "src/xdk/core/runtime/Runtime.x",
    "tasks": "src/xdk/concurrent/tasks/Tasks.x",
    "sync": "src/xdk/concurrent/sync/Sync.x",
    "math": "src/xdk/core/math/Math.x",
    "time": "src/xdk/core/time/Time.x",
    "collections": "src/xdk/core/collections/Collections.x",
    "meta": "src/xdk/core/meta/Meta.x",
}

# 投影所需 .xfb：只用 raw 桥；冻结编译器在混合绑定集下会把部分 FFI
# 包装参数错位（已知缺口）。按闭包实际需要的原语选择，避免无关符号。
def xfb_for(seen):
    out = []
    if "runtime" in seen:
        out.append("runtime_raw.xfb")
    if seen & {"meta", "math", "text", "time"}:
        out.append("ext_raw.xfb")
    if seen & {"sys", "resource"}:
        out.append("sys_raw.xfb")
    return out


def package_resolution(root, pkg):
    """按实际 legacy stem 选择 basic/full 目录，并加载对应 manifest。"""
    primary = os.path.abspath(os.path.join(root, UNITS[pkg]))
    directory = os.path.dirname(primary)
    resolver = PackageResolver(root, os.path.dirname(primary))
    return resolver._resolution("xdk." + pkg, primary, directory)


def package_key(parts):
    if not parts or parts[0] != "xdk" or len(parts) < 2:
        return None
    return parts[1]


def closure(root, resolver, entry_ast, xparser):
    """按 entry 的 import 闭包解析；只加载被引用的包，不加载全部 XDK。"""
    seen = set()
    order = []

    def visit(pkg):
        if pkg in seen:
            return
        seen.add(pkg)
        if pkg not in UNITS:
            raise ResolveError("XDK 包未注册：xdk.%s" % pkg)
        _units, slot = resolver.parse(
            package_resolution(root, pkg), lambda path: ast_of(xparser, root, path))
        for parts in imports_of(slot["ast"]):
            dep = package_key(parts)
            if dep:
                visit(dep)
        order.append(slot)

    for parts in imports_of(entry_ast):
        pkg = package_key(parts)
        if pkg:
            visit(pkg)
    return order, seen


def validate_entry_imports(resolver, entry_ast):
    for parts in imports_of(entry_ast):
        if not parts or parts[0] != "xdk":
            continue
        found = resolver.resolve(parts)
        if found.symbol and found.symbol[0].isupper():
            pkg = found.package.split(".")[1]
            if pkg not in UNITS:
                raise ResolveError("XDK 源码槽位尚未注册：%s" % found.package)


def ast_complete(text):
    """检查 S 表达式完整，拒绝原生 parser 偶发的截断输出。"""
    depth = 0
    quoted = False
    escaped = False
    for ch in text:
        if escaped:
            escaped = False
            continue
        if ch == "\\" and quoted:
            escaped = True
            continue
        if ch == '"':
            quoted = not quoted
            continue
        if quoted:
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0 and not quoted


def ast_of(xparser, root, path):
    last_error = ""
    for _ in range(3):
        try:
            p = subprocess.run([xparser, "--file", path], cwd=root,
                               capture_output=True, text=True, timeout=1800)
        except subprocess.TimeoutExpired:
            last_error = "xparser 超过 60 秒"
            continue
        if (p.returncode == 0 and p.stdout.startswith("(xnast v1")
                and ast_complete(p.stdout)):
            return p.stdout
        last_error = p.stderr[:400] or "AST 前缀或完整性校验失败"
    sys.stderr.write("xdk-bundle: xparser 三次失败：%s\n%s\n" % (path, last_error))
    sys.exit(1)


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("用法：xdk-bundle.py <root> <entry.x> <outdir>\n")
        return 2
    root, entry, outdir = sys.argv[1], os.path.abspath(sys.argv[2]), sys.argv[3]
    if not entry.startswith(root):
        entry = os.path.join(root, sys.argv[2])
    os.makedirs(outdir, exist_ok=True)

    xparser = os.environ.get("XPARSER_BIN") or os.path.join(root, "src/bootstrap/bin/xparser")
    files = []
    try:
        resolver = PackageResolver(root, os.path.dirname(entry), xdk_units=UNITS)
        entry_resolution = resolver.resolve_entry(entry)
        if entry_resolution is None:
            entry_ast = ast_of(xparser, root, entry)
        else:
            _units, entry_slot = resolver.parse(
                entry_resolution, lambda path: ast_of(xparser, root, path))
            entry_ast = entry_slot["ast"]
        validate_entry_imports(resolver, entry_ast)
        slots, seen = closure(root, resolver, entry_ast, xparser)
        files.extend(slots)
        if "sys" in seen or "resource" in seen:
            sys_res = os.path.join(root, "src/xdk/io/resource/Resource.x")
            files.append({"path": sys_res, "ast": ast_of(xparser, root, sys_res)})
    except ResolveError as exc:
        sys.stderr.write("xdk-bundle: %s\n" % exc)
        return 1
    files.append({"path": entry, "ast": entry_ast})
    with open(os.path.join(outdir, "bundle.json"), "w", encoding="utf-8") as f:
        json.dump({"version": "xnast-bundle v1", "files": files}, f)

    # 过滤投影：只保留源码层/桥接所需 .xfb
    pdir = os.path.join(outdir, "xfb")
    os.makedirs(pdir, exist_ok=True)
    xfb_names = xfb_for(seen)
    if xfb_names:
        for name in xfb_names:
            src = os.path.join(root, "src/ffi", name)
            if os.path.isfile(src):
                shutil.copyfile(src, os.path.join(pdir, name))
        proj = subprocess.run([sys.executable, os.path.join(root, "src/toolchain/xfb-projection.py"), pdir],
                              cwd=root, capture_output=True, text=True)
        if proj.returncode != 0:
            sys.stderr.write("xdk-bundle: 投影失败：%s\n" % proj.stderr[:400])
            return 1
        project_text = proj.stdout
    else:
        project_text = ""
    with open(os.path.join(outdir, "project.txt"), "w", encoding="utf-8") as f:
        f.write(project_text)
    sys.stdout.write(str(len(files)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
