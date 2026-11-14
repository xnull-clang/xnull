#!/usr/bin/env python3
"""把多类 legacy 单元机械拆成大写同名类文件。

先解析临时镜像并用 package_resolver 恢复虚拟 legacy AST；只有恢复结果与
迁移前基线逐字节一致时才允许 --apply 写入源码树。
"""
import argparse
import dataclasses
import hashlib
import json
import os
import re
import subprocess
import tempfile

from package_resolver import (PackageResolver, Resolution, XDK_LAYOUT,
                              _section, class_details, declaration_forms,
                              package_of, unit_pos_of, xdk_primary)


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def ast_of(xparser, root, path):
    last = ""
    oracle = os.environ.get("XNAST_BIN", "")
    for _ in range(1 if oracle else 3):
        try:
            p = subprocess.run([xparser, "--file", path], cwd=root,
                               capture_output=True, text=True,
                               timeout=60 if oracle else 180)
        except subprocess.TimeoutExpired:
            last = "timeout"
            continue
        if p.returncode == 0 and p.stdout.startswith("(xnast v1"):
            return p.stdout
        last = p.stderr[:300]
    if oracle:
        p = subprocess.run([oracle, "--ast", "--dump-depth", "100000", path],
                           cwd=root, capture_output=True, text=True, timeout=180)
        if p.returncode == 0 and p.stdout.startswith("(xnast v1"):
            return p.stdout
        last = p.stderr[:300]
    raise RuntimeError("xparser/xnast 失败：%s：%s" % (path, last))


def lexical_mask(text):
    """空白化注释和字符串，保留偏移与换行，供顶层 class/花括号扫描。"""
    chars = list(text)
    i = 0
    state = "code"
    quote = ""
    while i < len(chars):
        ch = chars[i]
        nxt = chars[i + 1] if i + 1 < len(chars) else ""
        if state == "line":
            if ch == "\n":
                state = "code"
            elif ch != "\r":
                chars[i] = " "
            i += 1
            continue
        if state == "block":
            if ch == "*" and nxt == "/":
                chars[i] = chars[i + 1] = " "
                i += 2
                state = "code"
            else:
                if ch not in "\n\r":
                    chars[i] = " "
                i += 1
            continue
        if state == "string":
            if ch == "\\":
                chars[i] = " "
                if i + 1 < len(chars) and chars[i + 1] not in "\n\r":
                    chars[i + 1] = " "
                i += 2
            elif ch == quote:
                chars[i] = " "
                i += 1
                state = "code"
            else:
                if ch not in "\n\r":
                    chars[i] = " "
                i += 1
            continue
        if ch == "/" and nxt == "/":
            chars[i] = chars[i + 1] = " "
            i += 2
            state = "line"
        elif ch == "/" and nxt == "*":
            chars[i] = chars[i + 1] = " "
            i += 2
            state = "block"
        elif ch in ('"', "'"):
            quote = ch
            chars[i] = " "
            i += 1
            state = "string"
        else:
            i += 1
    return "".join(chars)


def class_spans(source):
    masked = lexical_mask(source)
    lines = source.splitlines(keepends=True)
    out = {}
    for match in re.finditer(r"(?m)^class[ \t]+([A-Z][A-Za-z0-9_]*)\b", masked):
        name = match.group(1)
        class_line = source.count("\n", 0, match.start()) + 1
        open_brace = masked.find("{", match.end())
        if open_brace < 0:
            raise RuntimeError("类缺少类体：%s" % name)
        depth = 0
        close = -1
        for i in range(open_brace, len(masked)):
            if masked[i] == "{":
                depth += 1
            elif masked[i] == "}":
                depth -= 1
                if depth == 0:
                    close = i + 1
                    break
        if close < 0:
            raise RuntimeError("类体花括号不完整：%s" % name)
        start_line = class_line
        while start_line > 1 and lines[start_line - 2].lstrip().startswith("//"):
            start_line -= 1
        out[name] = {"start_line": start_line, "class_line": class_line,
                     "end_line": source.count("\n", 0, close) + 1}
    return out


def mask_spans(source, spans):
    lines = source.splitlines(keepends=True)
    for span in spans:
        for index in range(span["start_line"] - 1, span["end_line"]):
            lines[index] = "".join(ch if ch in "\n\r" else " " for ch in lines[index])
    return "".join(lines)


def first_decl_line(ast):
    forms = declaration_forms(ast)
    if not forms:
        return 1
    match = re.search(r"\(Line\s+(\d+)", forms[0])
    if not match:
        raise RuntimeError("首个声明缺少 Line")
    return int(match.group(1))


def add_package(source, ast, package):
    if not package or package_of(ast):
        return source, None
    lines = source.splitlines(keepends=True)
    boundary = first_decl_line(ast)
    for index, line in enumerate(lines):
        if re.match(r"^import\s", line):
            boundary = index + 1
            break
    candidates = [i for i in range(min(boundary - 1, len(lines)))
                  if not lines[i].strip()]
    if candidates:
        index = candidates[-1]
        original = lines[index]
        newline = "\n" if original.endswith("\n") else ""
        lines[index] = "package " + package + newline
        return "".join(lines), {"line": index + 1, "original": original}
    # import 前没有空行时，用同一物理行容纳 package 和 import，行号保持不变；
    # 虚拟 legacy 聚合会从 manifest 恢复原始 Imports。
    for index, line in enumerate(lines):
        if re.match(r"^import\s", line):
            lines[index] = "package " + package + "; " + line
            return "".join(lines), {"line": index + 1, "original": line}
    raise RuntimeError("无法在不移动行号的情况下插入 package %s" % package)


def make_class_file(source, ast, span):
    lines = source.splitlines(keepends=True)
    header_count = min(first_decl_line(ast) - 1, span["start_line"] - 1)
    header = lines[:header_count]
    if len(header) > span["start_line"] - 1:
        raise RuntimeError("类文件头部越过类声明")
    header.extend(["\n"] * (span["start_line"] - 1 - len(header)))
    header.extend(lines[span["start_line"] - 1:span["end_line"]])
    return "".join(header)


def unit_info(root, rel):
    stem = os.path.splitext(os.path.basename(rel))[0]
    if rel.startswith("impl/lib/xdk/"):
        normalized = os.path.normpath(rel)
        for package, variants in XDK_LAYOUT.items():
            for variant, layout in variants.items():
                expected = os.path.normpath(os.path.join("impl/lib/xdk", layout))
                if normalized == expected:
                    return ("xdk." + package,
                            "xdk-full" if variant == "full" else "package")
        return "xdk." + stem, "package"
    return stem, "entry"


def build_plan(root, xparser, rel):
    path = os.path.join(root, rel)
    directory = os.path.dirname(path)
    if not os.path.isfile(os.path.join(directory, ".xsplit.json")):
        legacy_dir = os.path.splitext(path)[0]
        if os.path.isdir(legacy_dir):
            directory = legacy_dir
    if os.path.isfile(os.path.join(directory, ".xsplit.json")):
        return None
    source = open(path, encoding="utf-8").read()
    raw_ast = ast_of(xparser, root, path)
    package, role = unit_info(root, rel)
    if (rel.startswith("impl/lib/xdk/") and
            os.path.normpath(rel) == os.path.normpath(
                os.path.join("impl/lib/xdk", xdk_primary("time")))):
        resolver = PackageResolver(root, os.path.dirname(path))
        found = resolver.resolve(["xdk", "time"])
        _units, slot = resolver.parse(found, lambda p: ast_of(xparser, root, p))
        baseline = slot["ast"]
    else:
        baseline = raw_ast
    spans = class_spans(source)
    details = class_details(baseline)
    external = {}
    for detail in details:
        if detail["name"] not in spans:
            candidate = os.path.join(directory, detail["name"] + ".x")
            if not os.path.isfile(candidate):
                raise RuntimeError("基线类没有源码归属：%s.%s" % (rel, detail["name"]))
            external[detail["name"]] = candidate
    masked = mask_spans(source, [span for name, span in spans.items()
                                 if name not in external])
    with_package, synthetic = add_package(masked, raw_ast, package)
    original_with_package, _ = add_package(source, raw_ast, package)
    classes = []
    outputs = {}
    for detail in sorted(details, key=lambda item: item["index"]):
        name = detail["name"]
        filename = name + ".x"
        target = os.path.join(directory, filename)
        if name in external:
            content = open(target, encoding="utf-8").read()
            span = class_spans(content)[name]
            is_external = True
        else:
            span = spans[name]
            if span["class_line"] != detail["line"]:
                raise RuntimeError("类行号与 AST 不对齐：%s %d != %d" % (
                    name, span["class_line"], detail["line"]))
            if os.path.exists(target):
                raise RuntimeError("目标类文件已存在：%s" % target)
            content = make_class_file(original_with_package, raw_ast, span)
            is_external = False
        outputs[target] = content
        classes.append({
            "name": name, "file": filename, "decl_index": detail["index"],
            "origin": {"line": detail["line"], "col": detail["col"]},
            "source": {"start_line": span["start_line"], "end_line": span["end_line"],
                       "external": is_external},
        })
    pos = unit_pos_of(baseline)
    split = {
        "version": "xsplit-v1", "legacy": rel.replace(os.sep, "/"),
        "role": role, "package": package,
        "unit_pos": {"line": pos[0], "col": pos[1]},
        "package_ast": _section(baseline, "Package"),
        "imports_ast": _section(baseline, "Imports"),
        "classes": classes,
        "source_sha256": sha(source), "baseline_ast_sha256": sha(baseline),
    }
    if synthetic:
        split["synthetic_package"] = synthetic
    outputs[path] = with_package
    outputs[os.path.join(directory, ".xsplit.json")] = json.dumps(
        split, ensure_ascii=False, indent=2) + "\n"
    with tempfile.TemporaryDirectory(prefix="xsplit-check-") as tmp:
        tmp_outputs = {}
        for actual, content in outputs.items():
            relative = os.path.relpath(actual, root)
            mirror = os.path.join(tmp, relative)
            os.makedirs(os.path.dirname(mirror), exist_ok=True)
            with open(mirror, "w", encoding="utf-8") as f:
                f.write(content)
            tmp_outputs[actual] = mirror
        files = [tmp_outputs[os.path.join(directory, item["file"])]
                 for item in classes] + [tmp_outputs[path]]
        resolution = Resolution(package, tmp_outputs[path], tuple(files),
                                os.path.join(tmp, os.path.relpath(directory, root)),
                                tmp_outputs[path], split=split)
        resolver = PackageResolver(tmp, tmp)
        _units, slot = resolver.parse(
            resolution, lambda p: ast_of(xparser, tmp, p))
        if slot["ast"] != baseline:
            limit = min(len(slot["ast"]), len(baseline))
            index = next((i for i in range(limit) if slot["ast"][i] != baseline[i]), limit)
            raise RuntimeError("聚合 AST 不一致：%s @%d\n实际：%s\n期望：%s" % (
                rel, index, slot["ast"][max(0, index - 100):index + 160],
                baseline[max(0, index - 100):index + 160]))
    return {"path": path, "outputs": outputs, "classes": len(classes),
            "baseline_ast": baseline}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--xparser", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()
    root = os.path.abspath(args.root)
    plans = []
    for rel in args.paths:
        plan = build_plan(root, os.path.abspath(args.xparser), rel)
        if plan is None:
            print("SKIP %s（已迁移）" % rel)
            continue
        plans.append(plan)
        print("CHECK %s：%d classes，虚拟 legacy AST 一致" % (rel, plan["classes"]))
    if not args.apply:
        return 0
    backups = {}
    try:
        for plan in plans:
            for path, content in plan["outputs"].items():
                if os.path.exists(path) and path not in backups:
                    backups[path] = open(path, encoding="utf-8").read()
                os.makedirs(os.path.dirname(path), exist_ok=True)
                tmp = path + ".xsplit-tmp"
                with open(tmp, "w", encoding="utf-8") as f:
                    f.write(content)
                os.replace(tmp, path)
    except Exception:
        for path, content in backups.items():
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
        raise
    for plan in plans:
        print("APPLY %s" % os.path.relpath(plan["path"], root))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
