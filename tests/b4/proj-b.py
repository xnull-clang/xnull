#!/usr/bin/env python3
"""B4c-03：复现冻结 golden 的投影 B（入口 + 直接 xdk 依赖 → 过滤绑定 E 行）。

与 tests/b4/freeze-golden.sh 的 proj_B 同口径：
- 仅当入口含 `import xdk.*` 时生成；
- 投影源 = 入口源码 + 每个直接 xdk 模块源码；
- 从 bindings 注册表只保留 `E|...` 中 `name(` 出现在上述源码里的条目。
"""
import os
import subprocess
import sys


def main():
    root = os.path.abspath(sys.argv[1])
    rel = sys.argv[2]
    os.chdir(root)
    src = open(rel, encoding="utf-8").read()
    if not any(line.startswith("import xdk.") for line in src.splitlines()):
        return
    for line in src.splitlines():
        if line.startswith("import xdk."):
            mod = line[len("import xdk."):].split()[0].rstrip(";")
            dep = os.path.join("impl/lib/xdk", mod + ".x")
            if os.path.exists(dep):
                src += open(dep, encoding="utf-8").read()
    allp = subprocess.run(
        [sys.executable, "tests/b3/xfb-projection.py", "bindings"],
        capture_output=True, check=True,
    ).stdout.decode()
    out = [l for l in allp.splitlines() if l.startswith("E|") and (l.split("|")[2] + "(") in src]
    if out:
        sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
