#!/usr/bin/env python3
"""XDK 源码层 bundle（B5 过渡）：把 `import xdk.*` 解析到 impl/lib/xdk/*.x，
生成 xnullc 可消费的 AST bundle 与 FFI 投影。

背景：产品编译器当前把 XDK 类型/函数硬编码在发射面，`impl/lib/xdk/*.x`
未参与编译；本脚本让源码层单元真正进入编译集（设计 A：按需编译单元）。

用法：xdk-bundle.py <root> <entry.x> <outdir>
输出：<outdir>/bundle.json、<outdir>/project.txt；stdout 打印 bundle 文件数。

范围：仅纳入已有真实实现的单元（errors/text/sys/net）。runtime/collections/
sync/tasks 仍由编译器内建面提供，避免重复定义。
"""
import json
import os
import re
import shutil
import subprocess
import sys

# 有源码层实现的包 → 单元路径
UNITS = {
    "errors": "impl/lib/xdk/errors.x",
    "text": "impl/lib/xdk/text_full.x",
    "sys": "impl/lib/xdk/sys_full.x",
    "net": "impl/lib/xdk/net_full.x",
    "runtime": "impl/lib/xdk/runtime.x",
    "tasks": "impl/lib/xdk/tasks.x",
    "sync": "impl/lib/xdk/sync.x",
}

# 投影所需 .xfb（net.xfb 的 handle 入口在冻结编译器里发射有缺陷，改用 net_raw）
# 只用 raw 桥：冻结编译器在混合绑定集下会把部分 FFI 包装参数错位
# （B5 已记录）；raw-only 集合已通过 text/sys/resources/net 四组 E2E。
XFB = ["sys_raw.xfb", "net_raw.xfb"]

IMPORT_RE = re.compile(r"^\s*import\s+xdk\.([A-Za-z_][A-Za-z0-9_.]*)")


def imports_of(path):
    out = []
    if not os.path.isfile(path):
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = IMPORT_RE.match(line)
            if m:
                out.append(m.group(1).split(".")[0])
    return out


def closure(root, entry):
    """返回固定布局的单元序列（入口最后）。

    产品编译器在 bundle 文件数变化时会错位 FFI 原型的参数（B5 发射面缺陷）。
    因此不按 import 裁剪：恒定包含全部 XDK 单元，保持与输入无关的稳定布局。
    """
    order = []
    for pkg in ("runtime", "errors", "text", "sys", "net", "tasks", "sync"):
        rel = UNITS.get(pkg)
        if rel:
            order.append(os.path.join(root, rel))
    # sys 资源子单元（与 sys.x 同包，不单独 import）。
    order.append(os.path.join(root, "impl/lib/xdk/sys_res.x"))
    order.append(entry)
    return order


def ast_of(xparser, root, path):
    p = subprocess.run([xparser, "--file", path], cwd=root,
                       capture_output=True, text=True)
    if p.returncode != 0 or not p.stdout.startswith("(xnast v1"):
        sys.stderr.write("xdk-bundle: xparser 失败：%s\n%s\n" % (path, p.stderr[:400]))
        sys.exit(1)
    return p.stdout


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("用法：xdk-bundle.py <root> <entry.x> <outdir>\n")
        return 2
    root, entry, outdir = sys.argv[1], os.path.abspath(sys.argv[2]), sys.argv[3]
    if not entry.startswith(root):
        entry = os.path.join(root, sys.argv[2])
    os.makedirs(outdir, exist_ok=True)

    xparser = os.environ.get("XPARSER_BIN") or os.path.join(root, "bootstrap/bin/xparser")
    files = []
    for path in closure(root, entry):
        files.append({"path": path, "ast": ast_of(xparser, root, path)})
    with open(os.path.join(outdir, "bundle.json"), "w", encoding="utf-8") as f:
        json.dump({"version": "xnast-bundle v1", "files": files}, f)

    # 过滤投影：只保留源码层/桥接所需 .xfb
    pdir = os.path.join(outdir, "xfb")
    os.makedirs(pdir, exist_ok=True)
    for name in XFB:
        src = os.path.join(root, "xdk-raw", name)
        if os.path.isfile(src):
            shutil.copyfile(src, os.path.join(pdir, name))
    proj = subprocess.run([sys.executable, os.path.join(root, "tests/b3/xfb-projection.py"), pdir],
                          cwd=root, capture_output=True, text=True)
    if proj.returncode != 0:
        sys.stderr.write("xdk-bundle: 投影失败：%s\n" % proj.stderr[:400])
        return 1
    with open(os.path.join(outdir, "project.txt"), "w", encoding="utf-8") as f:
        f.write(proj.stdout)
    sys.stdout.write(str(len(files)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
