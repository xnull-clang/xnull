#!/usr/bin/env python3
"""M6.2: generate @Row mappers and @Sql DAO helpers from annotation IR v2."""
import argparse
import json
import re
import sys
from pathlib import Path

SQL = "xdk.sql.Sql"
PARAM = "xdk.sql.Param"
ROW = "xdk.sql.Row"
COLUMN = "xdk.sql.Column"
SCALARS = {"String", "Int", "Long", "Double", "Bool", "Bytes"}


def diag(code, message, target="", severity="Error", line=1, col=1):
    return {"code": code, "severity": severity, "message": message,
            "line": line, "col": col, "target": target}


def write_diags(out, diags):
    out.mkdir(parents=True, exist_ok=True)
    (out / "diagnostics.json").write_text(json.dumps(diags, ensure_ascii=False), encoding="utf-8")


def text_arg(use, index=0, default=""):
    args = use.get("arguments", [])
    if index >= len(args):
        return default
    return args[index].get("text", default)


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
    inner = text[len("Result<"):-1]
    parts = split_top_level(inner)
    if len(parts) != 2:
        return None
    return parts[0].strip()


def placeholders(sql):
    names = []
    index = 0
    while index < len(sql):
        if sql[index] == ":" and index + 1 < len(sql):
            if sql[index + 1] == ":":
                index += 2
                continue
            match = re.match(r"[A-Za-z_][A-Za-z0-9_]*", sql[index + 1:])
            if match:
                name = match.group(0)
                if name not in names:
                    names.append(name)
                index += 1 + len(name)
                continue
        index += 1
    return names


def lit(text):
    return json.dumps(text, ensure_ascii=False)


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
    row_types = []
    sql_methods = []
    columns = {}
    params = {}

    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        target = use.get("target")
        target_name = use.get("targetName", "")
        line = use.get("line", 1)
        col = use.get("col", 1)
        if name == ROW:
            if target != "Type":
                diags.append(diag("AN1405", "@Row must target a type: " + target_name, target_name, line=line, col=col))
                continue
            sym = by_full.get(target_name)
            if not sym or sym.get("kind") != "Class":
                diags.append(diag("AN1405", "@Row requires a class: " + target_name, target_name, line=line, col=col))
                continue
            if target_name not in row_types:
                row_types.append(target_name)
        elif name == COLUMN:
            if target != "Field":
                diags.append(diag("AN1408", "@Column must target a field: " + target_name, target_name, line=line, col=col))
                continue
            owner, _, field = target_name.partition("#")
            if not owner or not field:
                diags.append(diag("AN1408", "@Column has invalid target: " + target_name, target_name, line=line, col=col))
                continue
            value = text_arg(use)
            if value == "":
                diags.append(diag("AN1408", "@Column value must not be empty: " + target_name, target_name, line=line, col=col))
                continue
            columns[target_name] = value
        elif name == SQL:
            if target != "Method":
                diags.append(diag("AN1401", "@Sql must target a method: " + target_name, target_name, line=line, col=col))
                continue
            value = text_arg(use)
            if value.strip() == "":
                diags.append(diag("AN1402", "@Sql text must not be empty: " + target_name, target_name, line=line, col=col))
                continue
            owner, method, types = split_signature(target_name)
            sql_methods.append({"owner": owner, "method": method, "types": types, "sql": value,
                                "line": line, "col": col})
        elif name == PARAM:
            if target != "Parameter":
                diags.append(diag("AN1404", "@Param must target a parameter: " + target_name, target_name, line=line, col=col))
                continue
            if "#" not in target_name:
                diags.append(diag("AN1404", "invalid parameter target: " + target_name, target_name, line=line, col=col))
                continue
            base, _, index_text = target_name.rpartition("#")
            try:
                index = int(index_text)
            except ValueError:
                diags.append(diag("AN1404", "invalid parameter index: " + target_name, target_name, line=line, col=col))
                continue
            value = text_arg(use)
            if value.strip() == "":
                diags.append(diag("AN1404", "@Param value must not be empty: " + target_name, target_name, line=line, col=col))
                continue
            params.setdefault(base, {})[index] = value

    row_plans = {}
    for full in sorted(row_types):
        sym = by_full[full]
        fields = [f for f in sym.get("fields", []) if not f.get("static")]
        plan_fields = []
        names = []
        for field in fields:
            fname = field.get("name", "")
            ftype = field.get("type", "")
            if ftype.endswith("?") or ftype not in SCALARS:
                diags.append(diag("AN1407", "unsupported row field type: " + ftype + " (" + full + "#" + fname + ")", full + "#" + fname))
                plan_fields = []
                break
            key = full + "#" + fname
            column = columns.get(key, fname)
            if column in names:
                diags.append(diag("AN1408", "duplicate column name: " + column, key))
                plan_fields = []
                break
            names.append(column)
            plan_fields.append({"name": fname, "type": ftype, "column": column})
        if not plan_fields and fields:
            continue
        ctor = ctor_for(sym)
        if ctor is None:
            diags.append(diag("AN1407", "no constructor matches row fields: " + full, full))
            continue
        row_plans[full] = {"sym": sym, "fields": plan_fields, "ctor": ctor}

    dao_plans = {}
    for entry in sql_methods:
        sym = by_full.get(entry["owner"])
        if not sym:
            diags.append(diag("AN1401", "DAO class not found: " + entry["owner"], entry["owner"]))
            continue
        method = next((m for m in sym.get("methods", []) if m.get("name") == entry["method"] and
                       [p.get("type") for p in m.get("params", [])] == entry["types"]), None)
        if method is None:
            diags.append(diag("AN1401", "DAO method not found: " + entry["owner"] + "#" + entry["method"], entry["owner"]))
            continue
        success = parse_result(method.get("return", ""))
        if success is None:
            diags.append(diag("AN1406", "unsupported return type: " + method.get("return", ""), entry["owner"]))
            continue
        success_simple = simple(success.replace(" ", ""))
        list_row = None
        row_name = None
        if success_simple == "SqlResult" or success_simple == "Long":
            pass
        elif success_simple.startswith("List<") and success_simple.endswith(">"):
            list_row = success_simple[5:-1]
            list_row = simple(list_row)
        else:
            row_name = success_simple
        if row_name is not None or list_row is not None:
            wanted = row_name if row_name is not None else list_row
            resolved = None
            for full in row_plans:
                if simple(full) == wanted:
                    resolved = full
                    break
            if resolved is None:
                diags.append(diag("AN1409", "row type is not @Row: " + wanted, entry["owner"]))
                continue
            if row_name is not None:
                row_name = resolved
            else:
                list_row = resolved
        method_params = method.get("params", [])
        base_key = entry["owner"] + "#" + entry["method"] + "(" + ",".join(entry["types"]) + ")"
        annotations = params.get(base_key, {})
        bindings = []
        bound_names = []
        ok = True
        for idx, param in enumerate(method_params):
            pname = param.get("name", "")
            ptype = param.get("type", "")
            if ptype not in SCALARS:
                diags.append(diag("AN1403", "unsupported DAO parameter type: " + ptype + " (" + pname + ")", entry["owner"]))
                ok = False
                break
            bound = annotations.get(idx, pname)
            if bound in bound_names:
                diags.append(diag("AN1403", "duplicate parameter binding: " + bound, entry["owner"]))
                ok = False
                break
            bound_names.append(bound)
            bindings.append({"name": pname, "type": ptype, "bound": bound})
        if not ok:
            continue
        names = placeholders(entry["sql"])
        if "?" in entry["sql"]:
            diags.append(diag("AN1403", "indexed placeholders are not supported in @Sql", entry["owner"]))
            continue
        if sorted(names) != sorted(bound_names):
            diags.append(diag("AN1403", "SQL placeholders " + ",".join(names) + " do not match parameters " + ",".join(bound_names), entry["owner"]))
            continue
        dao_plans.setdefault(entry["owner"], []).append({
            "method": entry["method"], "sql": entry["sql"], "bindings": bindings,
            "success": success_simple, "row": row_name, "list_row": list_row,
        })

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0

    if not row_plans and not dao_plans:
        write_diags(out, diags)
        return 0

    package = ""
    if row_plans:
        package = next(iter(row_plans.values()))["sym"].get("package", "")
    if package == "" and dao_plans:
        package = by_full[next(iter(dao_plans))].get("package", "")
    if package == "":
        package = "app.sql"

    lines = [
        "// generated by sql_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.errors",
        "",
    ]

    for full in sorted(row_plans):
        plan = row_plans[full]
        row_simple = plan["sym"].get("simpleName")
        fields = plan["fields"]
        lines.append("Result<" + row_simple + ", Error> " + row_simple + "FromRow(SqlRow row) {")
        lines.append("    if row == null { throw \"" + row_simple + "FromRow: null row\" }")
        lines.append("    if row.length() < " + str(len(fields)) + " {")
        lines.append("        return Err(sqlDataCorrupted(" + lit(row_simple + ": row has too few columns") + "))")
        lines.append("    }")
        for idx, field in enumerate(fields):
            value = "value" + str(idx)
            lines.append("    SqlValue " + value + " = row.get(" + str(idx) + ")")
            expected = {"String": "SqlKind.String", "Int": "SqlKind.Int", "Long": "SqlKind.Long",
                        "Double": "SqlKind.Double", "Bool": "SqlKind.Bool", "Bytes": "SqlKind.Bytes"}[field["type"]]
            lines.append("    if " + value + ".kind() != " + expected + " {")
            lines.append("        return Err(sqlDataCorrupted(" + lit(row_simple + "." + field["column"] + ": expected " + field["type"]) + "))")
            lines.append("    }")
            cast = {"String": "asString", "Int": "asInt", "Long": "asLong",
                    "Double": "asDouble", "Bool": "asBool", "Bytes": "asBytes"}[field["type"]]
            lines.append("    " + field["type"] + " field" + str(idx) + " = " + value + "." + cast + "().value()")
        mapping, ctor_params = plan["ctor"]
        field_index = {field["name"]: i for i, field in enumerate(fields)}
        arguments = []
        for param in ctor_params:
            arguments.append("field" + str(mapping.get(param.get("name", ""))) )
        lines.append("    return Ok(new " + row_simple + "(" + ", ".join(arguments) + "))")
        lines.append("}")
        lines.append("")

    for dao in sorted(dao_plans):
        dao_simple = by_full[dao].get("simpleName")
        for method in dao_plans[dao]:
            name = dao_simple + "_" + method["method"]
            params_text = ", ".join(binding["type"] + " " + binding["name"] for binding in method["bindings"])
            statement_name = name + "Statement"
            lines.append("SqlStatement " + statement_name + "(" + params_text + ") {")
            lines.append("    SqlStatement statement = new SqlStatement(" + lit(method["sql"]) + ")")
            for binding in method["bindings"]:
                cast = {"String": "ofString", "Int": "ofInt", "Long": "ofLong",
                        "Double": "ofDouble", "Bool": "ofBool", "Bytes": "ofBytes"}[binding["type"]]
                lines.append("    statement = statement.withParameter(SqlParameter.named(" + lit(binding["bound"]) + ", SqlValue." + cast + "(" + binding["name"] + ")))")
            lines.append("    return statement")
            lines.append("}")
            lines.append("")
            execute_name = name + "Execute"
            call_args = ", ".join(binding["name"] for binding in method["bindings"])
            if call_args != "":
                call_args = ", " + call_args
            lines.append("Result<" + method["success"] + ", Error> " + execute_name + "(SqlConnection connection" + (", " if params_text != "" else "") + params_text + ") {")
            lines.append("    if connection == null { throw \"" + execute_name + ": null connection\" }")
            lines.append("    SqlStatement statement = " + statement_name + "(" + ", ".join(binding["name"] for binding in method["bindings"]) + ")")
            lines.append("    Result<SqlResult, Error> executed = connection.execute(statement)")
            lines.append("    if executed.isErr() { return Err(executed.error()) }")
            lines.append("    SqlResult value = executed.value()")
            if method["success"] == "SqlResult":
                lines.append("    return Ok(value)")
            elif method["success"] == "Long":
                lines.append("    return Ok(value.rowsAffected())")
            elif method["row"] is not None:
                row_simple = simple(method["row"])
                lines.append("    List<SqlRow> rows = value.rows()")
                lines.append("    if rows.length() == 0 { return Err(sqlNotFound(" + lit(dao_simple + "." + method["method"] + ": no rows") + ")) }")
                lines.append("    if rows.length() > 1 { return Err(sqlDataCorrupted(" + lit(dao_simple + "." + method["method"] + ": multiple rows") + ")) }")
                lines.append("    SqlRow row = rows.get(0)")
                lines.append("    return " + row_simple + "FromRow(row)")
            else:
                row_simple = simple(method["list_row"])
                lines.append("    List<SqlRow> rows = value.rows()")
                lines.append("    List<" + row_simple + "> mapped = []")
                lines.append("    Int index = 0")
                lines.append("    while index < rows.length() {")
                lines.append("        Result<" + row_simple + ", Error> mappedRow = " + row_simple + "FromRow(rows.get(index))")
                lines.append("        if mappedRow.isErr() { return Err(mappedRow.error()) }")
                lines.append("        mapped.push(mappedRow.value())")
                lines.append("        index = index + 1")
                lines.append("    }")
                lines.append("    return Ok(mapped)")
            lines.append("}")
            lines.append("")

    (out / "SqlGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    if diags:
        write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
