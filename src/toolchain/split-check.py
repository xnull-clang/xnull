#!/usr/bin/env python3
"""全量校验 xsplit manifest、虚拟 legacy AST、源码物化及遗漏类。"""
import hashlib
import json
import os
import subprocess
import sys

from package_resolver import PackageResolver
from split_classes import ast_of, class_spans


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    xparser = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else
                              os.path.join(root, "src/bootstrap/bin/xparser"))
    manifests = []
    for area in ("src/xdk",):
        for directory, dirs, files in os.walk(os.path.join(root, area)):
            dirs.sort()
            if ".xsplit.json" in files:
                manifests.append(os.path.join(directory, ".xsplit.json"))
    manifests.sort()
    total_classes = 0
    managed_paths = set()
    blocked = 0
    for manifest_path in manifests:
        directory = os.path.dirname(manifest_path)
        manifest = json.load(open(manifest_path, encoding="utf-8"))
        legacy = os.path.join(root, manifest["legacy"])
        total_classes += len(manifest["classes"])
        for item in manifest["classes"]:
            path = os.path.abspath(os.path.join(directory, item["file"]))
            assert os.path.isfile(path), path
            managed_paths.add(path)
        materialized = subprocess.run(
            [sys.executable, os.path.join(root, "src/toolchain/materialize_legacy.py"),
             root, legacy], capture_output=True, text=True, check=True).stdout.strip()
        source_hash = hashlib.sha256(open(materialized, "rb").read()).hexdigest()
        assert source_hash == manifest["source_sha256"], manifest["legacy"]
        if manifest.get("baseline_blocked"):
            blocked += 1
            print("BLOCKED %s（%d classes）：%s" % (
                manifest["legacy"], len(manifest["classes"]),
                manifest["baseline_blocked"]))
            continue
        resolver = PackageResolver(root, os.path.dirname(legacy))
        resolution = resolver.resolve_entry(legacy)
        assert resolution is not None, manifest_path
        _units, slot = resolver.parse(
            resolution, lambda path: ast_of(xparser, root, path))
        actual = hashlib.sha256(slot["ast"].encode("utf-8")).hexdigest()
        assert actual == manifest["baseline_ast_sha256"], (
            "AST 不一致：%s：%s != %s" % (manifest["legacy"], actual,
                                          manifest["baseline_ast_sha256"]))
        print("PASS %s（%d classes）" % (manifest["legacy"], len(manifest["classes"])))
    unmanaged = []
    for area in ("src/xdk",):
        for directory, dirs, files in os.walk(os.path.join(root, area)):
            dirs.sort()
            for name in sorted(files):
                if not name.endswith(".x"):
                    continue
                path = os.path.abspath(os.path.join(directory, name))
                spans = class_spans(open(path, encoding="utf-8").read())
                if spans and path not in managed_paths:
                    unmanaged.append((path, sorted(spans)))
    assert not unmanaged, "存在未纳管类：%s" % unmanaged
    print("SPLIT CHECK：manifest=%d classes=%d unmanaged=0 blocked=%d" % (
        len(manifests), total_classes, blocked))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        sys.stderr.write("split-check: %s\n" % exc)
        sys.exit(1)
