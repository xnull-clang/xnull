#!/usr/bin/env python3
"""M12.1b: generate explicit @Metered duration wrappers."""
import argparse
import json
import sys
from pathlib import Path

METERED = "xdk.metrics.Metered"


def diag(code, message, target="", line=1, col=1, severity="Error"):
    return {"code": code, "severity": severity, "message": message,
            "line": line, "col": col, "target": target}


def write_diags(out, diags):
    out.mkdir(parents=True, exist_ok=True)
    ordered = sorted(diags, key=lambda d: (d["severity"], d["code"], d["target"], d["line"], d["col"], d["message"]))
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

    plans = []
    diags = []
    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        if name != METERED:
            continue
        target_name = use.get("targetName", "")
        line = use.get("line", 1)
        col = use.get("col", 1)
        if use.get("target") != "Method":
            diags.append(diag("AN2302", "@Metered must target a method: " + target_name, target_name, line, col))
            continue
        owner, method_name, types = split_signature(target_name)
        sym = symbols.get(owner)
        if not sym or sym.get("kind") != "Class":
            diags.append(diag("AN2301", "@Metered requires a class method: " + target_name,
                              target_name, line, col))
            continue
        method = None
        for candidate in sym.get("methods", []):
            if candidate.get("name") != method_name:
                continue
            params = [p.get("type", "") for p in candidate.get("params", [])]
            if [simple(t) for t in params] == [simple(t) for t in types]:
                method = candidate
                break
        if method is None:
            diags.append(diag("AN2301", "@Metered method not found: " + target_name, target_name, line, col))
            continue
        if method.get("static"):
            diags.append(diag("AN2304", "@Metered does not support static methods: " + target_name,
                              target_name, line, col))
            continue
        success = parse_result(method.get("return", ""))
        if success is None:
            diags.append(diag("AN2301", "@Metered method must return Result<T, Error>: " + target_name,
                              target_name, line, col))
            continue
        type_name = sym.get("simpleName") or simple(owner)
        label = text_arg(use, 0, "").strip()
        metric_name = label if label != "" else type_name + "." + method_name
        unit_name = text_arg(use, 1, "").strip()
        plans.append({"sym": sym, "method": method, "owner": owner, "name": method_name,
                      "type": type_name, "metric": metric_name, "unit": unit_name,
                      "success": success, "target": target_name, "line": line, "col": col})

    for plan in plans:
        diags.append(diag("AN2303", "metric lookup errors are ignored for " + plan["target"],
                          plan["target"], plan["line"], plan["col"], "Warning"))

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0
    if not plans:
        write_diags(out, diags)
        return 0

    package = plans[0]["sym"].get("package", "") or "app.metrics"
    lines = [
        "// generated by metrics_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.metrics",
        "import xdk.errors",
        "",
    ]
    for index, plan in enumerate(sorted(plans, key=lambda p: (p["owner"], p["name"]))):
        method = plan["method"]
        params = method.get("params", [])
        param_list = ", ".join(p.get("type", "") + " " + p.get("name", "") for p in params)
        call_args = ", ".join(p.get("name", "") for p in params)
        wrapper = plan["type"] + "_" + plan["name"] + "Metered"
        signature = ("Result<" + plan["success"] + ", Error> " + wrapper + "(" + plan["type"] +
                     " target, Registry registry")
        if param_list:
            signature += ", " + param_list
        signature += ")"
        lines.append(signature + " {")
        lines.append('    if target == null || registry == null { throw "' + wrapper + ': null argument" }')
        if plan["unit"] != "" and plan["unit"] != "ms":
            lines.append('    // unitName "' + plan["unit"] +
                         '" is not applied: MetricTimer unit is fixed to "ms".')
        lines.append("    Result<MetricTimer, Error> metric" + str(index) + " = registry.timer(" +
                     json.dumps(plan["metric"]) + ")")
        lines.append("    if metric" + str(index) + ".isOk() {")
        lines.append("        MetricTimer timer" + str(index) + " = metric" + str(index) + ".value()")
        lines.append("        Long started" + str(index) + " = timer" + str(index) + ".start()")
        lines.append("        Result<" + plan["success"] + ", Error> measured" + str(index) +
                     " = target." + plan["name"] + "(" + call_args + ")")
        lines.append("        timer" + str(index) + ".stop(started" + str(index) + ")")
        lines.append("        return measured" + str(index))
        lines.append("    }")
        lines.append("    Result<" + plan["success"] + ", Error> plain" + str(index) +
                     " = target." + plan["name"] + "(" + call_args + ")")
        lines.append("    return plain" + str(index))
        lines.append("}")
        lines.append("")

    (out / "MetricsGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
