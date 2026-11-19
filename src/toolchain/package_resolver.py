#!/usr/bin/env python3
"""XNull 包目录解析、受管类分片与 AST 聚合。

无 manifest 时保持 legacy P.x + P/*.x 的兼容行为；存在 .xsplit.json 时，
按原 Decls 下标、Package 和 CompilationUnit 位置恢复虚拟 legacy 单元。
"""
import dataclasses
import json
import os
import re


class ResolveError(RuntimeError):
    pass


# XDK 标准库物理布局：第一层分层，第二层域。路径相对 src/xdk。
# 包名保持稳定（xdk.errors 等）；同一包有 base/full 两套源码面时用变体区分。
XDK_LAYOUT = {
    "errors": {"default": "core/errors/Errors.x"},
    "runtime": {"default": "core/runtime/Runtime.x"},
    "meta": {"default": "core/meta/Meta.x"},
    "collections": {"default": "core/collections/Collections.x"},
    "math": {"default": "core/math/Math.x"},
    "time": {"default": "core/time/Time.x"},
    "text": {"default": "text/base/Text.x", "full": "text/full/Text.x"},
    "codec": {"default": "data/codec/Codec.x"},
    "sys": {"default": "io/base/Sys.x", "full": "io/system/Sys.x"},
    "net": {"default": "net/base/Net.x", "full": "net/network/Net.x"},
    "tasks": {"default": "concurrent/tasks/Tasks.x"},
    "sync": {"default": "concurrent/sync/Sync.x"},
    "log": {"default": "log/Log.x"},
    "config": {"default": "config/Config.x"},
    "cli": {"default": "cli/Cli.x"},
    "util": {"default": "util/tool/Util.x"},
    "compiler.lexer": {"default": "compiler/lexer/Lexer.x"},
    "compiler.parser": {"default": "compiler/parser/Parser.x"},
    "compiler.codegen": {"default": "compiler/codegen/Codegen.x"},
    "build.artifact": {"default": "build/artifact/Artifact.x"},
    "build.config": {"default": "build/config/Config.x"},
    "build.deps": {"default": "build/deps/Deps.x"},
    "build.manifest": {"default": "build/manifest/Manifest.x"},
    "build.reactor": {"default": "build/reactor/Reactor.x"},
    "build.resource": {"default": "build/resource/Resource.x"},
    "build.meta": {"default": "build/meta/Meta.x"},
    "build.project": {"default": "build/project/Project.x"},
}

# 旧扁平单元路径：仅用于 bundle 槽位标识，保持冻结 golden 的 #line/槽位稳定。
XDK_SLOT = {
    "errors": "errors.x",
    "runtime": "runtime.x",
    "collections": "collections.x",
    "math": "math.x",
    "time": "time.x",
    "text": "text.x",
    "codec": "codec.x",
    "sys": "sys.x",
    "net": "net.x",
    "tasks": "tasks.x",
    "sync": "sync.x",
    "log": "log.x",
    "config": "config.x",
    "cli": "cli.x",
    "util": "util.x",
}


def xdk_primary(package, variant="default"):
    """返回包的物理主单元路径（相对 src/xdk）。"""
    variants = XDK_LAYOUT.get(package)
    if not variants:
        return None
    return variants.get(variant) or variants.get("default")


def _form_end(text, start):
    depth = 0
    quoted = False
    escaped = False
    for i in range(start, len(text)):
        ch = text[i]
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
            if depth == 0:
                return i + 1
            if depth < 0:
                break
    raise ResolveError("AST S 表达式不完整")


def _section_span(ast, name):
    start = ast.find("(" + name + " ")
    if start < 0:
        raise ResolveError("AST 缺少 (%s ...) 段" % name)
    return start, _form_end(ast, start)


def _section(ast, name):
    start, end = _section_span(ast, name)
    return ast[start:end]


def _slice_body(ast, name):
    sec = _section(ast, name)
    start = sec.find("(slice")
    if start < 0:
        return ""
    end = _form_end(sec, start)
    return sec[start + len("(slice"):end - 1].strip()


def _quoted_strings(text):
    return [json.loads(m.group(0)) for m in re.finditer(r'"(?:[^"\\]|\\.)*"', text)]


def _top_level_forms(body):
    forms = []
    i = 0
    while i < len(body):
        while i < len(body) and body[i].isspace():
            i += 1
        if i >= len(body):
            break
        if body[i] != "(":
            raise ResolveError("AST 声明段存在非 S 表达式内容")
        end = _form_end(body, i)
        forms.append(body[i:end])
        i = end
    return forms


def declaration_forms(ast):
    return _top_level_forms(_slice_body(ast, "Decls"))


def imports_of(ast):
    out = []
    try:
        body = _slice_body(ast, "Imports")
    except ResolveError:
        return out
    for form in _top_level_forms(body):
        if form.startswith("(ImportDecl "):
            out.append(_quoted_strings(_slice_body(form, "Path")))
    return out


def package_of(ast):
    sec = _section(ast, "Package")
    if sec == "(Package (nil))":
        return ""
    return ".".join(_quoted_strings(_slice_body(sec, "Name")))


def _class_name(form):
    # ClassDecl 的 Annos 也可能含 Name；直接 Name 位于 Mod 之后。
    mod = form.find("(Mod ")
    start = _form_end(form, mod) if mod >= 0 else 0
    match = re.search(r'\(Name\s+("(?:[^"\\]|\\.)*")', form[start:])
    if not match:
        raise ResolveError("ClassDecl 缺少直接 Name")
    return json.loads(match.group(1))


def class_details(ast):
    out = []
    for index, form in enumerate(declaration_forms(ast)):
        if not form.startswith("(ClassDecl "):
            continue
        psec = _section(form, "P")
        match = re.search(r"\(Line\s+(\d+)\)\s*\(Col\s+(\d+)\)", psec)
        if not match:
            raise ResolveError("ClassDecl 缺少 Pos")
        out.append({"index": index, "name": _class_name(form), "form": form,
                    "line": int(match.group(1)), "col": int(match.group(2))})
    return out


def declared_classes(ast):
    return [item["name"] for item in class_details(ast)]


def unit_pos_of(ast):
    start = ast.find("(CompilationUnit ")
    if start < 0:
        raise ResolveError("AST 缺少 CompilationUnit")
    pstart = ast.find("(P ", start)
    if pstart < 0:
        raise ResolveError("CompilationUnit 缺少 P")
    pend = _form_end(ast, pstart)
    match = re.search(r"\(Line\s+(\d+)\)\s*\(Col\s+(\d+)\)", ast[pstart:pend])
    if not match:
        raise ResolveError("CompilationUnit Pos 不完整")
    return int(match.group(1)), int(match.group(2))


def _replace_unit_pos(ast, line, col):
    start = ast.find("(CompilationUnit ")
    pstart = ast.find("(P ", start)
    pend = _form_end(ast, pstart)
    replacement = "(P (Pos (Line %d) (Col %d)))" % (line, col)
    return ast[:pstart] + replacement + ast[pend:]


def _replace_package(ast, package_ast):
    start, end = _section_span(ast, "Package")
    return ast[:start] + package_ast + ast[end:]


def _replace_decls(ast, forms):
    start, end = _section_span(ast, "Decls")
    replacement = "(Decls (slice%s))" % (" " + " ".join(forms) if forms else "")
    return ast[:start] + replacement + ast[end:]


def merge_asts(asts):
    if not asts:
        raise ResolveError("不能聚合空包")
    if len(asts) == 1:
        return asts[0]
    packages = [package_of(ast) for ast in asts]
    named = sorted(set(pkg for pkg in packages if pkg))
    if len(named) > 1:
        raise ResolveError("同一聚合包出现多个 package：%s" % ", ".join(named))
    decls = []
    imports = []
    for ast in asts:
        decls.extend(declaration_forms(ast))
        imports.extend(_top_level_forms(_slice_body(ast, "Imports")))
    out = asts[0]
    if named and not packages[0]:
        source = asts[packages.index(named[0])]
        out = _replace_package(out, _section(source, "Package"))
    start, end = _section_span(out, "Imports")
    out = out[:start] + "(Imports (slice%s))" % (
        " " + " ".join(imports) if imports else "") + out[end:]
    return _replace_decls(out, decls)


def load_split(directory):
    if not directory:
        return None
    path = os.path.join(directory, ".xsplit.json")
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        split = json.load(f)
    if split.get("version") != "xsplit-v1":
        raise ResolveError("不支持的 manifest：%s" % path)
    split["_manifest_path"] = os.path.abspath(path)
    return split


@dataclasses.dataclass(frozen=True)
class Resolution:
    package: str
    primary: str
    files: tuple
    directory: str
    legacy: str
    symbol: str = ""
    split: object = None
    slot: str = ""


class PackageResolver:
    def __init__(self, root, entry_dir, xdk_dir=None, xdk_units=None):
        self.root = os.path.abspath(root)
        self.entry_dir = os.path.abspath(entry_dir)
        self.xdk_dir = os.path.abspath(xdk_dir or os.path.join(root, "src", "xdk"))
        self.xdk_units = {name: os.path.abspath(os.path.join(root, path))
                          for name, path in (xdk_units or {}).items()}

    def _resolution(self, package, primary, directory, symbol=""):
        primary = os.path.abspath(primary)
        directory = os.path.abspath(directory) if directory else ""
        split = load_split(directory)
        managed = []
        if split:
            managed = [os.path.abspath(os.path.join(directory, item["file"]))
                       for item in sorted(split["classes"], key=lambda x: x["decl_index"])]
            package = split["package"]
        managed_set = set(managed)
        prefix = []
        if os.path.isdir(directory):
            for name in sorted(os.listdir(directory)):
                path = os.path.abspath(os.path.join(directory, name))
                if (name.endswith(".x") and os.path.isfile(path) and
                        path not in managed_set and path != primary):
                    prefix.append(path)
        legacy = primary if os.path.isfile(primary) else ""
        files = prefix + managed + ([legacy] if legacy else [])
        if not files:
            raise ResolveError("包没有源码文件：%s" % package)
        return Resolution(package, legacy or files[0], tuple(files), directory,
                          legacy, symbol, split)

    def _source(self, root, parts, xdk, symbol=""):
        if xdk:
            for size in range(len(parts), 0, -1):
                key = ".".join(parts[:size])
                variants = XDK_LAYOUT.get(key)
                if not variants:
                    continue
                rel = xdk_primary(key)
                legacy = os.path.join(root, rel)
                if not os.path.isfile(legacy):
                    return None
                package = "xdk." + key
                sym = ".".join(parts[size:]) or symbol
                found = self._resolution(package, legacy,
                                         os.path.dirname(legacy), sym)
                slot_rel = XDK_SLOT.get(key)
                if slot_rel:
                    found = dataclasses.replace(
                        found, slot=os.path.join(root, slot_rel))
                return found
            return None
        package = ".".join(parts)
        legacy = os.path.join(root, *parts) + ".x"
        directory = os.path.join(root, *parts)
        if not os.path.isfile(legacy) and not os.path.isdir(directory):
            return None
        return self._resolution(package, legacy, directory, symbol)

    def _xdk_variant(self, rel):
        primary = self.xdk_units.get(rel[0])
        if not primary:
            return None
        directory = os.path.dirname(primary)
        symbol = ".".join(rel[1:])
        if rel[-1][0].isupper():
            if len(rel) < 2:
                raise ResolveError("指定类导入必须包含包名：xdk.%s" % ".".join(rel))
            class_file = os.path.join(directory, *rel[1:]) + ".x"
            if not os.path.isfile(class_file):
                raise ResolveError("类文件不存在：%s" % class_file)
        return self._resolution("xdk." + rel[0], primary, directory, symbol)

    def resolve(self, parts):
        if not parts:
            raise ResolveError("空 import")
        xdk = parts[0] == "xdk"
        rel = list(parts[1:] if xdk else parts)
        if not rel:
            raise ResolveError("XDK import 缺少包名")
        if xdk:
            variant = self._xdk_variant(rel)
            if variant is not None:
                return variant
        root = self.xdk_dir if xdk else self.entry_dir
        if rel[-1][0].isupper():
            if len(rel) < 2:
                raise ResolveError("指定类导入必须包含包名：%s" % ".".join(parts))
            symbol = rel[-1]
            if xdk:
                for size in range(len(rel) - 1, 0, -1):
                    key = ".".join(rel[:size])
                    if key not in XDK_LAYOUT:
                        continue
                    for variant in ("default", "full"):
                        relpath = xdk_primary(key, variant)
                        if not relpath:
                            continue
                        primary = os.path.join(root, relpath)
                        class_file = os.path.join(
                            os.path.dirname(primary), *rel[size:]) + ".x"
                        if os.path.isfile(class_file):
                            symbol = ".".join(rel[size:])
                            found = self._resolution(
                                "xdk." + key, primary,
                                os.path.dirname(primary), symbol)
                            slot_rel = XDK_SLOT.get(key)
                            if slot_rel:
                                found = dataclasses.replace(
                                    found, slot=os.path.join(root, slot_rel))
                            return found
                    raise ResolveError("类文件不存在：xdk.%s（import %s）" % (
                        ".".join(rel), ".".join(parts)))
            class_file = os.path.join(root, *rel) + ".x"
            if not os.path.isfile(class_file):
                raise ResolveError("类文件不存在：%s（import %s）" % (
                    os.path.abspath(class_file), ".".join(parts)))
            found = self._source(root, rel[:-1], xdk, symbol)
            if found is None:
                raise ResolveError("类所属包不存在：%s" % ".".join(parts))
            return found
        for size in range(len(rel), 0, -1):
            found = self._source(root, rel[:size], xdk)
            if found is not None:
                symbol = ".".join(rel[size:])
                if symbol:
                    found = dataclasses.replace(found, symbol=symbol)
                return found
        raise ResolveError("包不存在：%s" % ".".join(parts))

    def resolve_entry(self, entry):
        entry = os.path.abspath(entry)
        directory = os.path.dirname(entry)
        split = load_split(directory)
        if split is None:
            directory = os.path.splitext(entry)[0]
            split = load_split(directory)
        if split is None:
            return None
        return self._resolution(split["package"], entry, directory)

    def _managed_slot(self, resolution, units):
        split = resolution.split
        by_path = dict(units)
        legacy_ast = by_path[resolution.legacy]
        managed_forms = {}
        managed_paths = set()
        for item in split["classes"]:
            path = os.path.abspath(os.path.join(resolution.directory, item["file"]))
            managed_paths.add(path)
            details = class_details(by_path[path])
            if len(details) != 1 or details[0]["name"] != item["name"]:
                raise ResolveError("manifest 类名与文件不一致：%s" % path)
            detail = details[0]
            origin = item["origin"]
            if (detail["line"], detail["col"]) != (origin["line"], origin["col"]):
                raise ResolveError("类位置漂移：%s 期望 %d:%d，实际 %d:%d" % (
                    path, origin["line"], origin["col"], detail["line"], detail["col"]))
            managed_forms[item["decl_index"]] = detail["form"]
        residual = declaration_forms(legacy_ast)
        restored = []
        ri = 0
        for index in range(len(residual) + len(managed_forms)):
            if index in managed_forms:
                restored.append(managed_forms[index])
            else:
                restored.append(residual[ri])
                ri += 1
        legacy_restored = _replace_decls(legacy_ast, restored)
        legacy_restored = _replace_package(legacy_restored, split["package_ast"])
        imports_start, imports_end = _section_span(legacy_restored, "Imports")
        imports_ast = split.get("imports_ast", _section(legacy_ast, "Imports"))
        legacy_restored = (legacy_restored[:imports_start] + imports_ast +
                           legacy_restored[imports_end:])
        pos = split["unit_pos"]
        legacy_restored = _replace_unit_pos(legacy_restored, pos["line"], pos["col"])
        prefix_asts = [ast for path, ast in units
                       if path != resolution.legacy and path not in managed_paths]
        ast = merge_asts(prefix_asts + [legacy_restored]) if prefix_asts else legacy_restored
        return {"path": resolution.primary, "ast": ast}

    def parse(self, resolution, ast_of):
        units = []
        seen = {}
        for path in resolution.files:
            ast = ast_of(path)
            pkg = package_of(ast)
            if pkg and resolution.package and pkg != resolution.package:
                raise ResolveError("package 不匹配：%s 声明 %s，期望 %s" % (
                    path, pkg, resolution.package))
            in_directory = (resolution.directory and
                            os.path.dirname(path) == resolution.directory)
            classes = class_details(ast)
            legacy_primary = path == resolution.legacy and resolution.split is None
            is_primary = path == resolution.legacy
            if in_directory:
                if (resolution.package and pkg != resolution.package and
                        not (legacy_primary and not pkg)):
                    raise ResolveError("包目录文件必须声明 package %s：%s" % (
                        resolution.package, path))
                if not is_primary:
                    stem = os.path.splitext(os.path.basename(path))[0]
                    if stem[0].isupper() and (len(classes) != 1 or
                                              classes[0]["name"] != stem):
                        raise ResolveError("类文件必须且只能声明同名 class %s：%s" % (stem, path))
                    if not stem[0].isupper() and classes:
                        raise ResolveError("小写源码文件不得声明 class：%s（%s）" % (
                            path, ", ".join(item["name"] for item in classes)))
            for item in classes:
                if item["name"] in seen:
                    raise ResolveError("重复 class %s：%s 与 %s" % (
                        item["name"], seen[item["name"]], path))
                seen[item["name"]] = path
            units.append((path, ast))
        if resolution.symbol and resolution.symbol[0].isupper():
            class_path = os.path.join(resolution.directory,
                                      *resolution.symbol.split(".")) + ".x"
            class_ast = next((ast for path, ast in units if path == class_path), None)
            if class_ast is None or resolution.symbol not in declared_classes(class_ast):
                raise ResolveError("导入类不存在或文件名不匹配：%s.%s" % (
                    resolution.package, resolution.symbol))
        slot = (self._managed_slot(resolution, units) if resolution.split else
                {"path": resolution.primary,
                 "ast": merge_asts([ast for _path, ast in units])})
        return units, slot
