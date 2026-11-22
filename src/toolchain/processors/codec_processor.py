#!/usr/bin/env python3
"""M3.2: generate JSON codecs for @Serializable types from annotation IR v2."""
import argparse
import json
import sys
from pathlib import Path

SERIALIZABLE = "xdk.codec.Serializable"
JSON_NAME = "xdk.codec.JsonName"
SCALARS = {"String", "Int", "Long", "Double", "Bool"}


def fail(out, code, message, target=""):
    out.mkdir(parents=True, exist_ok=True)
    (out / "diagnostics.json").write_text(json.dumps([{
        "code": code, "severity": "Error", "message": message,
        "line": 1, "col": 1, "target": target,
    }], ensure_ascii=False), encoding="utf-8")
    return 0


def simple(name):
    return name.split(".")[-1]


def strip_underscores(name):
    return name.replace("_", "")


def text_arg(use, index, default=""):
    args = use.get("arguments", [])
    if index >= len(args):
        return default
    return args[index].get("text", default)


def lit(text):
    return json.dumps(text, ensure_ascii=False)


def field_type_name(name):
    """Type used in generated signatures: same-package simple names."""
    return simple(name)


def resolve_nested(name, by_full, by_simple):
    if name in by_full:
        return by_full[name]
    if simple(name) in by_simple:
        return by_simple[simple(name)]
    return None


def ctor_for(sym):
    fields = [f for f in sym.get("fields", []) if not f.get("static")]
    candidates = []
    for ctor in sym.get("ctors", []):
        params = ctor.get("params", [])
        if len(params) != len(fields):
            continue
        mapping = {}
        ok = True
        for param in params:
            pname = param.get("name", "")
            ptype = param.get("type", "")
            idx = None
            for i, field in enumerate(fields):
                fname = field.get("name", "")
                if i in mapping.values():
                    continue
                if pname == fname or pname == fname.lstrip("_"):
                    if simple(ptype) != simple(field.get("type", "")):
                        continue
                    idx = i
                    break
            if idx is None:
                ok = False
                break
            mapping[pname] = idx
        if ok:
            candidates.append((mapping, params))
    if candidates:
        return candidates[0]
    if not fields:
        for ctor in sym.get("ctors", []):
            if len(ctor.get("params", [])) == 0:
                return ({}, [])
        return ({}, [])
    return None


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

    annotated = []
    json_names = {}
    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        target = use.get("target")
        target_name = use.get("targetName", "")
        if name == SERIALIZABLE:
            if target != "Type":
                return fail(out, "AN1102", "@Serializable must target a type", target_name)
            sym = by_full.get(target_name)
            if not sym or sym.get("kind") != "Class":
                return fail(out, "AN1102", "@Serializable requires a class", target_name)
            if target_name in annotated:
                return fail(out, "AN1101", "duplicate @Serializable for type: " + target_name, target_name)
            annotated.append(target_name)
        elif name == JSON_NAME:
            if target != "Field":
                return fail(out, "AN1102", "@JsonName must target a field", target_name)
            owner, _, field = target_name.partition("#")
            if not field:
                return fail(out, "AN1102", "@JsonName has invalid field target", target_name)
            value = text_arg(use, 0)
            if value == "":
                return fail(out, "AN1102", "@JsonName value must not be empty", target_name)
            json_names[target_name] = value

    if not annotated:
        return fail(out, "AN1102", "no @Serializable class found")

    serializable = [by_full[name] for name in annotated]
    by_simple = {}
    for sym in serializable:
        key = sym.get("simpleName")
        if key in by_simple:
            return fail(out, "AN1101", "duplicate generated codec: " + key, sym.get("fullName", ""))
        by_simple[key] = sym
    full = {sym.get("fullName"): sym for sym in serializable}

    package = serializable[0].get("package", "") or "app.codec"
    for sym in serializable:
        if sym.get("package", "") != package:
            return fail(out, "AN1102", "cross-package @Serializable set is not supported: " + sym.get("fullName", ""))

    plans = {}
    for sym in serializable:
        full_name = sym.get("fullName", "")
        type_name = sym.get("simpleName", "")
        existing = {m.get("name") for m in sym.get("methods", [])}
        if type_name + "ToJson" in existing or type_name + "FromJson" in existing:
            return fail(out, "AN1101", "generated function conflicts with existing method: " + full_name, full_name)
        fields = []
        for field in sym.get("fields", []):
            if field.get("static"):
                continue
            fname = field.get("name", "")
            ftype = field.get("type", "")
            key = full_name + "#" + fname
            json_name = json_names.get(key, strip_underscores(fname))
            nested = None
            if ftype in SCALARS:
                kind = ftype
            elif ftype.startswith("List<"):
                return fail(out, "AN1102", "List fields are planned, not supported: " + key, key)
            else:
                nested_sym = resolve_nested(ftype, full, by_simple)
                if nested_sym is None:
                    return fail(out, "AN1102", "unsupported field type: " + ftype + " (" + key + ")", key)
                if nested_sym.get("fullName") not in full:
                    return fail(out, "AN1102", "nested type is not @Serializable: " + ftype, key)
                if nested_sym.get("package", "") != package:
                    return fail(out, "AN1102", "cross-package nested type is not supported: " + ftype, key)
                nested = nested_sym.get("simpleName")
                kind = "nested"
            fields.append({"name": fname, "json": json_name, "type": ftype, "kind": kind, "nested": nested})
        ctor = ctor_for(sym)
        if ctor is None:
            return fail(out, "AN1102", "no constructor matches fields: " + full_name, full_name)
        plans[full_name] = {"sym": sym, "fields": fields, "ctor": ctor}

    # Dependencies first (nested types), with stable fullName tie-break.
    order = []
    visiting = set()

    def visit(name):
        if name in order:
            return
        if name in visiting:
            return
        visiting.add(name)
        for field in plans[name]["fields"]:
            if field["kind"] == "nested":
                dep = field["nested"]
                dep_name = next((k for k, v in plans.items() if v["sym"].get("simpleName") == dep), None)
                if dep_name:
                    visit(dep_name)
        visiting.discard(name)
        order.append(name)

    for sym in sorted(serializable, key=lambda s: s.get("fullName", "")):
        visit(sym.get("fullName"))

    lines = [
        "// generated by codec_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.codec",
        "import xdk.errors",
        "",
    ]

    for full_name in order:
        plan = plans[full_name]
        type_name = plan["sym"].get("simpleName")
        fields = plan["fields"]

        lines.append("JsonValue " + type_name + "ToJson(" + type_name + " value) {")
        lines.append("    JsonObject object = new JsonObject()")
        for field in fields:
            arg = "value." + field["name"]
            if field["kind"] == "String":
                expr = "Json.string(" + arg + ")"
            elif field["kind"] == "Int":
                expr = "Json.number(str(" + arg + "))"
            elif field["kind"] == "Long":
                expr = "Json.number(str(" + arg + "))"
            elif field["kind"] == "Double":
                expr = "Json.number(str(" + arg + "))"
            elif field["kind"] == "Bool":
                expr = "Json.bool(" + arg + ")"
            else:
                expr = field["nested"] + "ToJson(" + arg + ")"
            lines.append("    object.set(" + lit(field["json"]) + ", " + expr + ")")
        lines.append("    JsonValue result = new JsonValue(JsonKind.Object, false, null, null, null, object)")
        lines.append("    return result")
        lines.append("}")
        lines.append("")

        lines.append("Result<" + type_name + ", Error> " + type_name + "FromJson(JsonValue json) {")
        lines.append("    if !json.isObject() {")
        lines.append("        return Err(codecError(ErrorKind.DataCorrupted, " + lit(type_name + ": expected object") + "))")
        lines.append("    }")
        lines.append("    JsonObject object = json.asObject() as JsonObject")
        for idx, field in enumerate(fields):
            key = type_name + "." + field["json"]
            lines.append("    if !object.has(" + lit(field["json"]) + ") {")
            lines.append("        return Err(codecError(ErrorKind.InvalidArgument, " + lit(key + ": missing field") + "))")
            lines.append("    }")
            lines.append("    JsonValue field" + str(idx) + "Json = object.getOr(" + lit(field["json"]) + ", Json.nullValue())")
            if field["kind"] == "String":
                lines.append("    if !field" + str(idx) + "Json.isString() {")
                lines.append("        return Err(codecError(ErrorKind.InvalidArgument, " + lit(key + ": expected String") + "))")
                lines.append("    }")
                lines.append("    String field" + str(idx) + "Value = field" + str(idx) + "Json.asString() as String")
            elif field["kind"] == "Bool":
                lines.append("    if !field" + str(idx) + "Json.isBool() {")
                lines.append("        return Err(codecError(ErrorKind.InvalidArgument, " + lit(key + ": expected Bool") + "))")
                lines.append("    }")
                lines.append("    Bool field" + str(idx) + "Value = field" + str(idx) + "Json.asBool() as Bool")
            elif field["kind"] == "Int":
                lines.append("    if !field" + str(idx) + "Json.isNumber() {")
                lines.append("        return Err(codecError(ErrorKind.InvalidArgument, " + lit(key + ": expected Int") + "))")
                lines.append("    }")
                lines.append("    JsonNumber? field" + str(idx) + "Number = field" + str(idx) + "Json.asNumber()")
                lines.append("    JsonNumber field" + str(idx) + "Num = field" + str(idx) + "Number as JsonNumber")
                lines.append("    Result<Int, Error> field" + str(idx) + "Parsed = field" + str(idx) + "Num.asInt()")
                lines.append("    if field" + str(idx) + "Parsed.isErr() {")
                lines.append("        return Err(codecError(ErrorKind.InvalidArgument, " + lit(key + ": invalid Int") + "))")
                lines.append("    }")
                lines.append("    Int field" + str(idx) + "Value = field" + str(idx) + "Parsed.value()")
            elif field["kind"] == "Long":
                lines.append("    if !field" + str(idx) + "Json.isNumber() {")
                lines.append("        return Err(codecError(ErrorKind.InvalidArgument, " + lit(key + ": expected Long") + "))")
                lines.append("    }")
                lines.append("    JsonNumber? field" + str(idx) + "Number = field" + str(idx) + "Json.asNumber()")
                lines.append("    JsonNumber field" + str(idx) + "Num = field" + str(idx) + "Number as JsonNumber")
                lines.append("    Result<Long, Error> field" + str(idx) + "Parsed = field" + str(idx) + "Num.asLong()")
                lines.append("    if field" + str(idx) + "Parsed.isErr() {")
                lines.append("        return Err(codecError(ErrorKind.InvalidArgument, " + lit(key + ": invalid Long") + "))")
                lines.append("    }")
                lines.append("    Long field" + str(idx) + "Value = field" + str(idx) + "Parsed.value()")
            elif field["kind"] == "Double":
                lines.append("    if !field" + str(idx) + "Json.isNumber() {")
                lines.append("        return Err(codecError(ErrorKind.InvalidArgument, " + lit(key + ": expected Double") + "))")
                lines.append("    }")
                lines.append("    JsonNumber? field" + str(idx) + "Number = field" + str(idx) + "Json.asNumber()")
                lines.append("    JsonNumber field" + str(idx) + "Num = field" + str(idx) + "Number as JsonNumber")
                lines.append("    Result<Double, Error> field" + str(idx) + "Parsed = field" + str(idx) + "Num.asDouble()")
                lines.append("    if field" + str(idx) + "Parsed.isErr() {")
                lines.append("        return Err(codecError(ErrorKind.InvalidArgument, " + lit(key + ": invalid Double") + "))")
                lines.append("    }")
                lines.append("    Double field" + str(idx) + "Value = field" + str(idx) + "Parsed.value()")
            else:
                lines.append("    Result<" + field["nested"] + ", Error> field" + str(idx) + "Parsed = " + field["nested"] + "FromJson(field" + str(idx) + "Json)")
                lines.append("    if field" + str(idx) + "Parsed.isErr() {")
                lines.append("        return Err(codecError(ErrorKind.InvalidArgument, " + lit(key + ": invalid nested value") + "))")
                lines.append("    }")
                lines.append("    " + field["nested"] + " field" + str(idx) + "Value = field" + str(idx) + "Parsed.value()")

        mapping, params = plan["ctor"]
        field_index = {field["name"]: i for i, field in enumerate(fields)}
        arguments = []
        for param in params:
            idx = mapping.get(param.get("name", ""))
            arguments.append("field" + str(idx) + "Value")
        lines.append("    return Ok(new " + type_name + "(" + ", ".join(arguments) + "))")
        lines.append("}")
        lines.append("")

    (out / "CodecGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
