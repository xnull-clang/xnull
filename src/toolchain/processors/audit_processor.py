#!/usr/bin/env python3
"""M10.2: generate explicit audit wrappers."""
import argparse
import json
import sys
from pathlib import Path

AUDITED = "xdk.audit.Audited"


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


def supported_type(ftype):
    text = ftype.strip()
    return "->" not in text and "(" not in text and text not in ("Any", "Object")


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
        if name != AUDITED:
            continue
        target = use.get("target")
        target_name = use.get("targetName", "")
        if target != "Method":
            diags.append(diag("AN2103", "@Audited must target a method: " + target_name, target_name))
            continue
        owner, method_name, types = split_signature(target_name)
        if not method_name:
            diags.append(diag("AN2103", "@Audited has invalid method target", target_name))
            continue
        sym = symbols.get(owner)
        if not sym or sym.get("kind") != "Class":
            diags.append(diag("AN2101", "@Audited requires a class method: " + owner, target_name))
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
            diags.append(diag("AN2103", "@Audited method not found: " + target_name, target_name))
            continue
        if method.get("static"):
            diags.append(diag("AN2104", "@Audited does not support static methods: " + target_name, target_name))
            continue
        action = text_arg(use, 0, "")
        if action == "":
            diags.append(diag("AN2102", "@Audited action must not be empty: " + target_name, target_name))
            continue
        success = parse_result(method.get("return", ""))
        if success is None:
            diags.append(diag("AN2101", "@Audited method must return Result<T, Error>: " + target_name, target_name))
            continue
        unsupported = False
        for param in method.get("params", []):
            if not supported_type(param.get("type", "")):
                diags.append(diag("AN2105", "unsupported parameter type: " + target_name, target_name))
                unsupported = True
                break
        if unsupported:
            continue
        if not supported_type(success):
            diags.append(diag("AN2105", "unsupported result type: " + target_name, target_name))
            continue
        plans.append({"sym": sym, "method": method, "action": action,
                      "success": success, "owner": owner, "name": method_name,
                      "target": target_name})

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0
    if not plans:
        write_diags(out, diags)
        return 0

    package = plans[0]["sym"].get("package", "") or "app.audit"
    lines = [
        "// generated by audit_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.audit",
        "import xdk.errors",
        "import xdk.runtime",
        "",
    ]

    for plan in sorted(plans, key=lambda p: (p["sym"].get("fullName", ""), p["name"])):
        type_name = plan["sym"].get("simpleName") or simple(plan["owner"])
        method = plan["method"]
        params = method.get("params", [])
        param_list = ", ".join(p.get("type", "") + " " + p.get("name", "") for p in params)
        call_args = ", ".join(p.get("name", "") for p in params)
        wrapper = type_name + "_" + plan["name"] + "Audited"
        signature = ("Result<" + plan["success"] + ", Error> " + wrapper + "(" + type_name +
                     " target, AuditLogger logger, String actor")
        if param_list:
            signature += ", " + param_list
        signature += ")"
        resource = type_name + "." + plan["name"]
        lines.append(signature + " {")
        lines.append('    if target == null || logger == null { throw "' + wrapper + ': null argument" }')
        lines.append("    Long startedMono = nowMono()")
        lines.append("    Result<" + plan["success"] + ", Error> result = target." +
                     plan["name"] + "(" + call_args + ")")
        lines.append("    if result.isErr() {")
        lines.append("        Map<String, String> fields = [:]")
        lines.append('        fields.put("errorKind", errorKindName(result.error().kind()))')
        lines.append("        AuditEvent event = new AuditEvent(actor, " + json.dumps(plan["action"]) +
                     ", " + json.dumps(resource) + ', "failure", AuditLevel.Warning, startedMono, fields)')
        lines.append("        Result<Unit, Error> audited = logger.log(event)")
        lines.append("        // Audit failure is intentionally ignored; the method error wins.")
        lines.append("        return result")
        lines.append("    }")
        lines.append("    Result<Unit, Error> audited = logger.logAction(actor, " +
                     json.dumps(plan["action"]) + ", " + json.dumps(resource) + ', "success")')
        lines.append("    if audited.isErr() { return Err(audited.error()) }")
        lines.append("    return result")
        lines.append("}")
        lines.append("")

    (out / "AuditGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
