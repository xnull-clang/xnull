#!/usr/bin/env python3
"""把受管类分片物化为迁移前 legacy 单文件，供旧解释执行入口使用。"""
import hashlib
import json
import os
import sys
import tempfile


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("用法：materialize_legacy.py <root> <legacy.x>\n")
        return 2
    root = os.path.abspath(sys.argv[1])
    legacy = os.path.abspath(sys.argv[2])
    directory = os.path.dirname(legacy)
    manifest_path = os.path.join(directory, ".xsplit.json")
    if not os.path.isfile(manifest_path):
        directory = os.path.splitext(legacy)[0]
        manifest_path = os.path.join(directory, ".xsplit.json")
    if not os.path.isfile(manifest_path):
        print(legacy)
        return 0
    manifest = json.load(open(manifest_path, encoding="utf-8"))
    lines = open(legacy, encoding="utf-8").read().splitlines(keepends=True)
    for item in manifest["classes"]:
        source = item["source"]
        if source.get("external"):
            continue
        class_path = os.path.join(directory, item["file"])
        class_lines = open(class_path, encoding="utf-8").read().splitlines(keepends=True)
        start = source["start_line"] - 1
        end = source["end_line"]
        replacement = class_lines[start:end]
        if len(replacement) != end - start:
            raise RuntimeError("类文件行数与 manifest 不一致：%s" % class_path)
        lines[start:end] = replacement
    synthetic = manifest.get("synthetic_package")
    if synthetic:
        lines[synthetic["line"] - 1] = synthetic["original"]
    text = "".join(lines)
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    if digest != manifest["source_sha256"]:
        raise RuntimeError("物化源码哈希不一致：%s：%s != %s" % (
            legacy, digest, manifest["source_sha256"]))
    stem = os.path.splitext(os.path.basename(legacy))[0]
    out = os.path.join(tempfile.gettempdir(), "xnull-legacy-%s-%s.x" % (stem, digest[:16]))
    if not os.path.isfile(out) or open(out, encoding="utf-8").read() != text:
        with open(out, "w", encoding="utf-8") as f:
            f.write(text)
    print(out)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, KeyError) as exc:
        sys.stderr.write("materialize-legacy: %s\n" % exc)
        sys.exit(1)
