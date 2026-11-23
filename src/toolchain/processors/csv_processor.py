#!/usr/bin/env python3
"""M3.3: generate CSV codecs for @Serializable types (CsvGenerated.x)."""
import argparse
import json
import sys
from pathlib import Path

SERIALIZABLE = "xdk.codec.Serializable"
CSV_NAME = "xdk.codec.CsvName"
SUPPORTED = {"String", "Int", "Long", "Double", "Bool"}


def diag(code, message, target="", severity="Error"):
    return {"code": code, "severity": severity, "message": message,
            "line": 1, "col": 1, "target": target}


def write_diags(out, diags):
    out.mkdir(parents=True, exist_ok=True)
    (out / "diagnostics.json").write_text(json.dumps(diags, ensure_ascii=False), encoding="utf-8")


def simple(name):
    return name.split(".")[-1]


def lit(text):
    return json.dumps(text, ensure_ascii=False)


def text_arg(use):
    args = use.get("arguments", [])
    return args[0].get("text", "") if args else ""


def ctor_for(sym):
    fields = [f for f in sym.get("fields", []) if not f.get("static")]
    for ctor in sym.get("ctors", []):
        params = ctor.get("params", [])
        if len(params) != len(fields):
            continue
        mapping = {}
        ok = True
        for param in params:
            pname = param.get("name", "")
            ptype = param.get("type", "")
            found = None
            for i, field in enumerate(fields):
                if i in mapping.values():
                    continue
                fname = field.get("name", "")
                if pname == fname or pname == fname.lstrip("_"):
                    if simple(ptype) == simple(field.get("type", "")):
                        found = i
                        break
            if found is None:
                ok = False
                break
            mapping[pname] = found
        if ok:
            return mapping, params
    if not fields:
        return {}, []
    return None


def zero_expr(ftype):
    if ftype == "String":
        return '""'
    if ftype in ("Int", "Long"):
        return "0"
    if ftype == "Double":
        return "0.0"
    if ftype == "Bool":
        return "false"
    return "null"


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

    serializable = []
    for use in uses:
        if (use.get("resolvedName") or use.get("name")) == SERIALIZABLE and use.get("target") == "Type":
            if use.get("targetName") not in serializable:
                serializable.append(use.get("targetName"))

    diags = []
    csv_names = {}
    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        if name != CSV_NAME:
            continue
        target = use.get("target")
        target_name = use.get("targetName", "")
        if target != "Field":
            diags.append(diag("AN1601", "@CsvName must target a field: " + target_name, target_name))
            continue
        value = text_arg(use)
        if value == "":
            diags.append(diag("AN1601", "@CsvName value must not be empty: " + target_name, target_name))
            continue
        owner = target_name.partition("#")[0]
        if owner not in serializable:
            diags.append(diag("AN1603", "@CsvName requires @Serializable: " + target_name, target_name))
            continue
        csv_names[target_name] = value

    plans = {}
    for full in sorted(serializable):
        sym = by_full.get(full)
        if sym is None:
            continue
        fields = []
        seen = {}
        for field in sym.get("fields", []):
            if field.get("static"):
                continue
            fname = field.get("name", "")
            ftype = field.get("type", "")
            key = full + "#" + fname
            csv = csv_names.get(key, fname.replace("_", ""))
            if csv in seen:
                diags.append(diag("AN1602", full + "." + csv + ": duplicate CSV column", key))
                continue
            seen[csv] = True
            if ftype not in SUPPORTED:
                diags.append(diag("AN1605", full + "." + csv + ": unsupported CSV field type " + ftype + "; skipped", key, severity="Warning"))
                continue
            fields.append({"name": fname, "type": ftype, "csv": csv})
        ctor = ctor_for(sym)
        if ctor is None:
            diags.append(diag("AN1605", full + ": no constructor matches fields; CSV codec skipped", full, severity="Warning"))
            continue
        plans[full] = {"sym": sym, "fields": fields, "ctor": ctor}

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0

    if not plans:
        write_diags(out, diags)
        return 0

    package = by_full[next(iter(plans))].get("package", "") or "app.csv"
    lines = [
        "// generated by csv_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.codec",
        "import xdk.errors",
        "import xdk.text",
        "",
        "static Int csvColumnIndex(List<String> header, String name) {",
        "    Int index = 0",
        "    while index < header.length() {",
        "        if header.get(index) == name { return index }",
        "        index = index + 1",
        "    }",
        "    return -1",
        "}",
        "",
        "static Result<Long, Error> csvParseLong(String text) {",
        "    if text == \"\" { return Err(new BasicError(ErrorKind.DataCorrupted, \"empty long\")) }",
        "    Int index = 0",
        "    Bool negative = false",
        "    if text.substring(0, 1) == \"-\" { negative = true; index = 1 }",
        "    if index >= text.length() { return Err(new BasicError(ErrorKind.DataCorrupted, \"invalid long\")) }",
        "    Long value = 0",
        "    Long cutoff = 922337203685477580",
        "    Int limit = 7",
        "    if negative { limit = 8 }",
        "    String digits = \"0123456789\"",
        "    while index < text.length() {",
        "        Int digit = digits.indexOf(text.substring(index, 1))",
        "        if digit < 0 { return Err(new BasicError(ErrorKind.DataCorrupted, \"invalid long\")) }",
        "        if value > cutoff { return Err(new BasicError(ErrorKind.DataCorrupted, \"long overflow\")) }",
        "        if value == cutoff && digit > limit { return Err(new BasicError(ErrorKind.DataCorrupted, \"long overflow\")) }",
        "        value = value * 10 + digit",
        "        index = index + 1",
        "    }",
        "    if negative { value = -value }",
        "    return Ok(value)",
        "}",
        "",
    ]

    for full in sorted(plans):
        plan = plans[full]
        type_name = plan["sym"].get("simpleName")
        fields = plan["fields"]
        lines.append("String " + type_name + "CsvHeader() {")
        lines.append("    List<List<String>> rows = []")
        lines.append("    List<String> header = []")
        for field in fields:
            lines.append("    header.push(" + lit(field["csv"]) + ")")
        lines.append("    rows.push(header)")
        lines.append("    CsvOptions options = new CsvOptions()")
        lines.append("    return Csv.write(rows, options)")
        lines.append("}")
        lines.append("")
        lines.append("String " + type_name + "ToCsv(" + type_name + " value) {")
        lines.append("    List<List<String>> rows = []")
        lines.append("    List<String> header = []")
        for field in fields:
            lines.append("    header.push(" + lit(field["csv"]) + ")")
        lines.append("    rows.push(header)")
        lines.append("    List<String> row = []")
        for field in fields:
            access = "value." + field["name"]
            if field["type"] == "String":
                lines.append("    row.push(" + access + ")")
            else:
                lines.append("    row.push(str(" + access + "))")
        lines.append("    rows.push(row)")
        lines.append("    CsvOptions options = new CsvOptions()")
        lines.append("    return Csv.write(rows, options)")
        lines.append("}")
        lines.append("")
        lines.append("Result<" + type_name + ", Error> " + type_name + "FromCsv(String text) {")
        lines.append("    CsvOptions options = new CsvOptions()")
        lines.append("    Result<List<List<String>>, Error> parsed = Csv.parse(text, options)")
        lines.append("    if parsed.isErr() { return Err(parsed.error()) }")
        lines.append("    List<List<String>> rows = parsed.value()")
        lines.append("    if rows.length() == 0 { return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + ": missing header") + ")) }")
        lines.append("    if rows.length() < 2 { return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + ": missing data row") + ")) }")
        lines.append("    List<String> header = rows.get(0)")
        lines.append("    List<String> data = rows.get(1)")
        lines.append("    return " + type_name + "FromCsvRow(header, data)")
        lines.append("}")
        lines.append("")
        lines.append("Result<List<" + type_name + ">, Error> " + type_name + "FromCsvRows(String text) {")
        lines.append("    CsvOptions options = new CsvOptions()")
        lines.append("    Result<List<List<String>>, Error> parsed = Csv.parse(text, options)")
        lines.append("    if parsed.isErr() { return Err(parsed.error()) }")
        lines.append("    List<List<String>> rows = parsed.value()")
        lines.append("    if rows.length() == 0 { return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + ": missing header") + ")) }")
        lines.append("    List<String> header = rows.get(0)")
        lines.append("    List<" + type_name + "> result = []")
        lines.append("    Int index = 1")
        lines.append("    while index < rows.length() {")
        lines.append("        Result<" + type_name + ", Error> mapped = " + type_name + "FromCsvRow(header, rows.get(index))")
        lines.append("        if mapped.isErr() { return Err(mapped.error()) }")
        lines.append("        result.push(mapped.value())")
        lines.append("        index = index + 1")
        lines.append("    }")
        lines.append("    return Ok(result)")
        lines.append("}")
        lines.append("")
        lines.append("static Result<" + type_name + ", Error> " + type_name + "FromCsvRow(List<String> header, List<String> data) {")
        for idx, field in enumerate(fields):
            lines.append("    Int index" + str(idx) + " = csvColumnIndex(header, " + lit(field["csv"]) + ")")
            lines.append("    if index" + str(idx) + " < 0 || index" + str(idx) + " >= data.length() {")
            lines.append("        return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + "." + field["csv"] + ": missing column") + "))")
            lines.append("    }")
            lines.append("    String text" + str(idx) + " = data.get(index" + str(idx) + ")")
            if field["type"] == "String":
                lines.append("    String field" + str(idx) + " = text" + str(idx))
            elif field["type"] == "Int":
                lines.append("    Result<Int, Error> parsed" + str(idx) + " = parseInt(text" + str(idx) + ")")
                lines.append("    if parsed" + str(idx) + ".isErr() { return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + "." + field["csv"] + ": invalid Int") + ")) }")
                lines.append("    Int field" + str(idx) + " = parsed" + str(idx) + ".value()")
            elif field["type"] == "Long":
                lines.append("    Result<Long, Error> parsed" + str(idx) + " = csvParseLong(text" + str(idx) + ")")
                lines.append("    if parsed" + str(idx) + ".isErr() { return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + "." + field["csv"] + ": invalid Long") + ")) }")
                lines.append("    Long field" + str(idx) + " = parsed" + str(idx) + ".value()")
            elif field["type"] == "Double":
                lines.append("    Result<Double, Error> parsed" + str(idx) + " = parseFloat(text" + str(idx) + ")")
                lines.append("    if parsed" + str(idx) + ".isErr() { return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + "." + field["csv"] + ": invalid Double") + ")) }")
                lines.append("    Double field" + str(idx) + " = parsed" + str(idx) + ".value()")
            else:
                lines.append("    String lower" + str(idx) + " = text" + str(idx) + ".toLower()")
                lines.append("    if lower" + str(idx) + " != \"true\" && lower" + str(idx) + " != \"false\" { return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + "." + field["csv"] + ": invalid Bool") + ")) }")
                lines.append("    Bool field" + str(idx) + " = lower" + str(idx) + " == \"true\"")
        mapping, ctor_params = plan["ctor"]
        fields_all = [f for f in plan["sym"].get("fields", []) if not f.get("static")]
        supported_index = {field["name"]: i for i, field in enumerate(fields)}
        arguments = []
        zero_index = 0
        for param in ctor_params:
            field_name = fields_all[mapping.get(param.get("name", ""))]["name"] if mapping.get(param.get("name", "")) is not None else ""
            if field_name in supported_index:
                arguments.append("field" + str(supported_index[field_name]))
            else:
                ftype = param.get("type", "")
                if ftype.startswith("List<"):
                    zero = "zero" + str(zero_index)
                    lines.append("    " + ftype + " " + zero + " = []")
                    zero_index += 1
                    arguments.append(zero)
                else:
                    arguments.append(zero_expr(ftype))
        lines.append("    return Ok(new " + type_name + "(" + ", ".join(arguments) + "))")
        lines.append("}")
        lines.append("")

    (out / "CsvGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    if diags:
        write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
