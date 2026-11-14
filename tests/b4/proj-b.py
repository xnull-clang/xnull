#!/usr/bin/env python3
"""复现 golden 投影 B；受管分片先物化，保持原源码文本并集。"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from package_resolver import xdk_primary


def source_text(root, path):
    materializer = os.path.join(root, "tests/b4/materialize_legacy.py")
    result = subprocess.run([sys.executable, materializer, root, path],
                            cwd=root, capture_output=True, text=True, check=True)
    materialized = result.stdout.strip()
    with open(materialized, encoding="utf-8") as f:
        return f.read()


def main():
    root = os.path.abspath(sys.argv[1])
    rel = sys.argv[2]
    os.chdir(root)
    src = source_text(root, rel)
    if not any(line.startswith("import xdk.") for line in src.splitlines()):
        return
    for line in src.splitlines():
        if line.startswith("import xdk."):
            mod = line[len("import xdk."):].split()[0].rstrip(";")
            rel = xdk_primary(mod)
            dep = os.path.join("impl/lib/xdk", rel) if rel else ""
            if dep and os.path.exists(dep):
                src += source_text(root, dep)
    allp = subprocess.run(
        [sys.executable, "tests/b3/xfb-projection.py", "bindings"],
        capture_output=True, check=True,
    ).stdout.decode()
    out = [l for l in allp.splitlines() if l.startswith("E|") and (l.split("|")[2] + "(") in src]
    if out:
        sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
