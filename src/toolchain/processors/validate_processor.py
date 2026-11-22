#!/usr/bin/env python3
"""M4.2: generate Schema/ValidationResult from @Validate/@Min/@Max/@Pattern IR v2."""
import argparse
import json
import re
import sys
from pathlib import Path

VALIDATE = "xdk.validate.Validate"
MIN = "xdk.validate.Min"
MAX = "xdk.validate.Max"
PATTERN = "xdk.validate.Pattern"
SCALARS = {"String", "Int", "Long", "Double", "Bool"}


def diag(code, message, target="", severity="Error", line=1, col=1):
    return {"code": code, "severity": severity, "message": message,
            "line": line, "col": col, "target": target}


def write_diags(out, diags):
    out.mkdir(parents=True, exist_ok=True)
    (out / "diagnostics.json").write_text(json.dumps(diags, ensure_ascii=False), encoding="utf-8")


def lit(text):
    return json.dumps(text, ensure_ascii=False)


def long_arg(use):
    args = use.get("arguments", [])
    if not args:
        return None
    try:
        return int(args[0].get("text", "0"))
    except ValueError:
        return None


def text_arg(use, default=""):
    args = use.get("arguments", [])
    if not args:
        return default
    return args[0].get("text", default)


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
    symbols = ir.get("symbols", {}).get("types", [])
    by_full = {t.get("fullName"): t for t in symbols}
    uses = ir.get("uses", [])

    diags = []
    targets = []
    limits = {}
    patterns = {}

    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        target = use.get("target")
        target_name = use.get("targetName", "")
        line = use.get("line", 1)
        col = use.get("col", 1)
        if name == VALIDATE:
            if target != "Type":
                diags.append(diag("AN1201", "@Validate must target a type: " + target_name, target_name, line=line, col=col))
                continue
            sym = by_full.get(target_name)
            if not sym or sym.get("kind") not in ("Class", "Struct"):
                diags.append(diag("AN1201", "@Validate requires a class or struct: " + target_name, target_name, line=line, col=col))
                continue
            if target_name in targets:
                diags.append(diag("AN1201", "duplicate @Validate: " + target_name, target_name, line=line, col=col))
                continue
            targets.append(target_name)
        elif name in (MIN, MAX, PATTERN):
            if target != "Field":
                diags.append(diag("AN1202", name.split(".")[-1] + " must target a field: " + target_name, target_name, line=line, col=col))
                continue
            owner, _, field = target_name.partition("#")
            if not field:
                diags.append(diag("AN1202", name + " has invalid field target", target_name, line=line, col=col))
                continue
            if name in (MIN, MAX):
                value = long_arg(use)
                if value is None:
                    diags.append(diag("AN1203", name + " requires an integer bound: " + target_name, target_name, line=line, col=col))
                    continue
                slot = limits.setdefault(target_name, {})
                slot["min" if name == MIN else "max"] = value
            else:
                patterns.setdefault(target_name, []).append(text_arg(use))

    if not targets:
        if not diags:
            diags.append(diag("AN1204", "no @Validate type found", "", severity="Warning"))
        write_diags(out, diags)
        return 0

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0

    target_syms = [by_full[name] for name in targets]
    package = target_syms[0].get("package", "") or "app.validate"

    def field_required(ftype):
        return not ftype.endswith("?")

    def root_type(ftype):
        return ftype[:-1] if ftype.endswith("?") else ftype

    plans = {}
    for sym in sorted(target_syms, key=lambda s: s.get("fullName", "")):
        full = sym.get("fullName", "")
        simple = sym.get("simpleName", "")
        fields = []
        for field in sym.get("fields", []):
            if field.get("static"):
                continue
            fname = field.get("name", "")
            ftype = field.get("type", "")
            key = full + "#" + fname
            path = simple + "." + fname
            nullable = ftype.endswith("?")
            base = root_type(ftype)
            if nullable and base != "String":
                diags.append(diag("AN1205", path + ": nullable " + base + " is not supported; field skipped", key, severity="Warning"))
                continue
            if base not in SCALARS:
                diags.append(diag("AN1205", path + ": unsupported field type " + ftype + "; field skipped", key, severity="Warning"))
                continue
            info = {"name": fname, "type": base, "required": not nullable,
                    "min": None, "max": None, "patterns": []}
            bounds = limits.get(key, {})
            if "min" in bounds:
                info["min"] = bounds["min"]
            if "max" in bounds:
                info["max"] = bounds["max"]
            if info["min"] is not None and info["max"] is not None and info["min"] > info["max"]:
                diags.append(diag("AN1203", path + ": @Min > @Max", key))
                continue
            if base == "String":
                if info["min"] is not None and info["min"] < 0:
                    diags.append(diag("AN1203", path + ": @Min length must be >= 0", key))
                    continue
                if info["max"] is not None and info["max"] < 0:
                    diags.append(diag("AN1203", path + ": @Max length must be >= 0", key))
                    continue
                info["patterns"] = patterns.get(key, [])
                for pattern in info["patterns"]:
                    try:
                        re.compile(pattern)
                    except re.error:
                        diags.append(diag("AN1206", path + ": @Pattern cannot compile: " + pattern, key))
                        break
            else:
                for pattern in patterns.get(key, []):
                    diags.append(diag("AN1205", path + ": @Pattern is only supported on String; ignored", key, severity="Warning"))
                if info["min"] is not None or info["max"] is not None:
                    if base == "Bool":
                        diags.append(diag("AN1205", path + ": @Min/@Max are not supported on Bool; ignored", key, severity="Warning"))
                        info["min"] = None
                        info["max"] = None
            fields.append(info)
        if not fields:
            diags.append(diag("AN1204", full + ": @Validate type has no supported fields", full, severity="Warning"))
        plans[full] = {"simple": simple, "fields": fields}

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0

    lines = [
        "// generated by validate_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.validate",
        "import xdk.codec",
        "import xdk.errors",
        "import xdk.text",
        "import xdk.math",
        "",
    ]

    for full in sorted(plans):
        plan = plans[full]
        simple = plan["simple"]
        lines.append("Schema " + simple + "Schema() {")
        lines.append("    Schema schema = new Schema()")
        for idx, field in enumerate(plan["fields"]):
            var = "validators" + str(idx)
            lines.append("    List<Validator> " + var + " = []")
            if field["type"] == "String":
                lines.append("    " + var + ".push(Rules.string())")
                if field["min"] is not None:
                    lines.append("    " + var + ".push(Rules.minLength(" + str(field["min"]) + "))")
                if field["max"] is not None:
                    lines.append("    " + var + ".push(Rules.maxLength(" + str(field["max"]) + "))")
                for pidx, pattern in enumerate(field["patterns"]):
                    result = "patternResult" + str(idx) + "_" + str(pidx)
                    regex = "patternRegex" + str(idx) + "_" + str(pidx)
                    lines.append("    Result<Regex, Error> " + result + " = Regex.compile(" + lit(pattern) + ")")
                    lines.append("    Regex " + regex + " = " + result + ".value()")
                    lines.append("    " + var + ".push(Rules.pattern(" + regex + "))")
            elif field["type"] == "Int":
                lines.append("    " + var + ".push(Rules.integer())")
                if field["min"] is not None or field["max"] is not None:
                    low = str(field["min"]) + ".0" if field["min"] is not None else "-Inf()"
                    high = str(field["max"]) + ".0" if field["max"] is not None else "Inf()"
                    lines.append("    " + var + ".push(Rules.range(" + low + ", " + high + "))")
            elif field["type"] == "Long":
                lines.append("    " + var + ".push(Rules.integer())")
                if field["min"] is not None or field["max"] is not None:
                    low = str(field["min"]) + ".0" if field["min"] is not None else "-Inf()"
                    high = str(field["max"]) + ".0" if field["max"] is not None else "Inf()"
                    lines.append("    " + var + ".push(Rules.range(" + low + ", " + high + "))")
            elif field["type"] == "Double":
                lines.append("    " + var + ".push(Rules.number())")
                if field["min"] is not None or field["max"] is not None:
                    low = str(field["min"]) + ".0" if field["min"] is not None else "-Inf()"
                    high = str(field["max"]) + ".0" if field["max"] is not None else "Inf()"
                    lines.append("    " + var + ".push(Rules.range(" + low + ", " + high + "))")
            else:
                lines.append("    " + var + ".push(Rules.bool())")
            validator = "validator" + str(idx)
            lines.append("    Validator " + validator + " = Rules.all(" + var + ")")
            lines.append("    schema.field(" + lit(field["name"]) + ", " + validator + ")")
            if field["required"]:
                lines.append("    schema.required(" + lit(field["name"]) + ")")
        lines.append("    return schema")
        lines.append("}")
        lines.append("")
        lines.append("ValidationResult " + simple + "Validate(JsonValue json) {")
        lines.append("    Schema schema = " + simple + "Schema()")
        lines.append("    return schema.validateValue(json)")
        lines.append("}")
        lines.append("")

    (out / "ValidateGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    if diags:
        write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
