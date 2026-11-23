#!/usr/bin/env python3
"""M8.4: generate explicit cache wrappers."""
import argparse
import json
import sys
from pathlib import Path

CACHEABLE = "xdk.cache.Cacheable"
CACHE_EVICT = "xdk.cache.CacheEvict"


def diag(code, message, target=""):
    return {"code": code, "severity": "Error", "message": message,
            "line": 1, "col": 1, "target": target}


def write_diags(out, diags):
    out.mkdir(parents=True, exist_ok=True)
    ordered = sorted(diags, key=lambda d: (d["code"], d["target"], d["message"]))
    (out / "diagnostics.json").write_text(json.dumps(ordered, ensure_ascii=False), encoding="utf-8")


def simple(name):
    return name.split(".")[-1]


def split_signature(target):
    owner, _, rest = target.partition("#")
    if "(" not in rest or not rest.endswith(")"):
        return owner, "", []
    name = rest.split("(", 1)[0]
    inner = rest[len(name) + 1:-1]
    types = [t.strip() for t in inner.split(",")] if inner.strip() else []
    return owner, name, types


def split_top_level(text):
    parts, current, depth = [], "", 0
    for char in text:
        if char in "<(":
            depth += 1
        elif char in ">)":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += char
    if current.strip():
        parts.append(current)
    return parts


def parse_result(return_type):
    text = return_type.strip()
    if not text.startswith("Result<") or not text.endswith(">"):
        return None
    parts = split_top_level(text[len("Result<"):-1])
    if len(parts) != 2 or simple(parts[1].strip()) != "Error":
        return None
    return parts[0].strip()


def text_arg(use, index, default=""):
    args = use.get("arguments", [])
    if index >= len(args):
        return default
    return args[index].get("text", default)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", required=True)
    parser.add_argument("--ir", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    if args.phase != "Generate":
        return 0
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    ir = json.loads(Path(args.ir).read_text(encoding="utf-8"))
    symbols = {t.get("fullName"): t for t in ir.get("symbols", {}).get("types", [])}
    uses = ir.get("uses", [])

    diags = []
    plans = {}
    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        if name not in (CACHEABLE, CACHE_EVICT):
            continue
        target = use.get("target")
        target_name = use.get("targetName", "")
        if target != "Method":
            diags.append(diag("AN2003", name + " must target a method: " + target_name, target_name))
            continue
        owner, method, types = split_signature(target_name)
        if not method:
            diags.append(diag("AN2003", name + " has invalid method target", target_name))
            continue
        plans.setdefault(target_name, []).append({"kind": "cacheable" if name == CACHEABLE else "evict",
                                                   "use": use, "owner": owner,
                                                   "method": method, "types": types})

    generated = []
    for target_name in sorted(plans):
        entries = plans[target_name]
        if len(entries) > 1:
            diags.append(diag("AN2002", "only one cache annotation per method: " + target_name, target_name))
            continue
        entry = entries[0]
        value = text_arg(entry["use"], 0, "")
        if value == "":
            diags.append(diag("AN2004", "@Cacheable/@CacheEvict value must not be empty: " + target_name, target_name))
            continue
        sym = symbols.get(entry["owner"])
        if not sym or sym.get("kind") != "Class":
            diags.append(diag("AN2003", "cache method owner must be a class: " + entry["owner"], target_name))
            continue
        method = None
        for candidate in sym.get("methods", []):
            if candidate.get("name") != entry["method"]:
                continue
            cparams = [p.get("type", "") for p in candidate.get("params", [])]
            if [simple(t) for t in cparams] == [simple(t) for t in entry["types"]]:
                method = candidate
                break
        if method is None:
            diags.append(diag("AN2003", "cache method not found: " + target_name, target_name))
            continue
        if method.get("static"):
            diags.append(diag("AN2001", "static methods are not supported: " + target_name, target_name))
            continue
        success = parse_result(method.get("return", ""))
        if success is None:
            diags.append(diag("AN2001", "method must return Result<T, Error>: " + target_name, target_name))
            continue
        generated.append({"entry": entry, "sym": sym, "method": method,
                          "success": success, "value": value, "target": target_name})

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0
    if not generated:
        write_diags(out, diags)
        return 0

    package = generated[0]["sym"].get("package", "") or "app.cache"
    lines = [
        "// generated by cache_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.cache",
        "import xdk.errors",
        "",
    ]

    for plan in sorted(generated, key=lambda p: (p["sym"].get("fullName", ""), p["entry"]["method"])):
        entry = plan["entry"]
        type_name = plan["sym"].get("simpleName") or simple(entry["owner"])
        method = plan["method"]
        params = method.get("params", [])
        param_list = ", ".join(p.get("type", "") + " " + p.get("name", "") for p in params)
        call_args = ", ".join(p.get("name", "") for p in params)
        ret_value = plan["success"]
        call = "target." + entry["method"] + "(" + call_args + ")"
        wrapper = type_name + "_" + entry["method"] + ("Cached" if entry["kind"] == "cacheable" else "Evict")
        signature = ("Result<" + ret_value + ", Error> " + wrapper + "(" + type_name +
                     " target, Cache<String, " + ret_value + "> cache")
        if param_list:
            signature += ", " + param_list
        signature += ")"
        lines.append(signature + " {")
        lines.append('    if target == null || cache == null { throw "' + wrapper + ': null argument" }')
        explicit_key = text_arg(entry["use"], 1, "")
        if explicit_key != "":
            prefix = explicit_key + ":"
        else:
            prefix = plan["value"] + ":" + entry["method"] + ":"
        key_expr = '"' + prefix + '"'
        key_index = 0
        while key_index < len(params):
            if key_index == 0:
                key_expr += " + str(" + params[key_index].get("name", "") + ")"
            else:
                key_expr += ' + ":" + str(' + params[key_index].get("name", "") + ")"
            key_index += 1
        lines.append("    String key = " + key_expr)
        if entry["kind"] == "cacheable":
            lines.append("    " + ret_value + "? cached = cache.get(key)")
            lines.append("    if cached != null { return Ok(cached as " + ret_value + ") }")
            lines.append("    Result<" + ret_value + ", Error> loaded = " + call)
            lines.append("    if loaded.isOk() { cache.put(key, loaded.value()) }")
            lines.append("    return loaded")
        else:
            lines.append("    cache.invalidate(key)")
            lines.append("    return " + call)
        lines.append("}")
        lines.append("")

    (out / "CacheGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
