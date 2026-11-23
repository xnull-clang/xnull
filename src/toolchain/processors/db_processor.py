#!/usr/bin/env python3
"""M6.5: generate entity CRUD helpers and transactional wrappers."""
import argparse
import json
import sys
from pathlib import Path

ENTITY = "xdk.db.Entity"
TABLE = "xdk.db.Table"
ID = "xdk.db.Id"
TX = "xdk.db.Transactional"
COLUMN = "xdk.sql.Column"
SUPPORTED = {"String", "Int", "Long", "Double", "Bool"}
SQL_TYPE = {"String": "TEXT", "Int": "INTEGER", "Long": "INTEGER", "Double": "REAL", "Bool": "INTEGER"}


def diag(code, message, target="", severity="Error"):
    return {"code": code, "severity": severity, "message": message,
            "line": 1, "col": 1, "target": target}


def write_diags(out, diags):
    out.mkdir(parents=True, exist_ok=True)
    (out / "diagnostics.json").write_text(json.dumps(diags, ensure_ascii=False), encoding="utf-8")


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


def bool_arg(use):
    args = use.get("arguments", [])
    if not args:
        return False
    return args[0].get("kind") == "bool" and args[0].get("text") == "true"


def text_arg(use):
    args = use.get("arguments", [])
    return args[0].get("text", "") if args else ""


def lit(text):
    return json.dumps(text, ensure_ascii=False)


def zero_expr(ftype):
    if ftype == "String":
        return '""'
    if ftype in ("Int", "Long"):
        return "0"
    if ftype == "Double":
        return "0.0"
    if ftype == "Bool":
        return "false"
    if ftype == "Bytes":
        return "Bytes.fromString(\"\")"
    return "null"


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
    entity_names = {}
    table_names = {}
    ids = {}
    columns = {}
    transactions = []

    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        target = use.get("target")
        target_name = use.get("targetName", "")
        if name in (ENTITY, TABLE):
            if target != "Type":
                diags.append(diag("AN1801", name + " must target a type: " + target_name, target_name))
                continue
            sym = by_full.get(target_name)
            if not sym or sym.get("kind") != "Class":
                diags.append(diag("AN1801", name + " requires a class: " + target_name, target_name))
                continue
            value = text_arg(use)
            if value == "":
                diags.append(diag("AN1803", name + " table name must not be empty: " + target_name, target_name))
                continue
            if name == ENTITY:
                entity_names[target_name] = value
            else:
                table_names[target_name] = value
        elif name == ID:
            if target != "Field":
                diags.append(diag("AN1805", "@Id must target a field: " + target_name, target_name))
                continue
            owner = target_name.partition("#")[0]
            ids.setdefault(owner, []).append(target_name.partition("#")[2])
        elif name == COLUMN and target == "Field":
            value = text_arg(use)
            if value == "":
                diags.append(diag("AN1809", "@Column value must not be empty: " + target_name, target_name))
                continue
            columns[target_name] = value
        elif name == TX:
            if target != "Method":
                diags.append(diag("AN1807", "@Transactional must target a method: " + target_name, target_name))
                continue
            owner, method, types = split_signature(target_name)
            transactions.append({"owner": owner, "method": method, "types": types,
                                 "readOnly": bool_arg(use)})

    for full in sorted(set(entity_names) | set(table_names)):
        if full in entity_names and full in table_names:
            diags.append(diag("AN1802", "both @Entity and @Table on " + full, full))

    entity_plans = {}
    for full in sorted(set(entity_names) | set(table_names)):
        if full in entity_names and full in table_names:
            continue
        sym = by_full[full]
        table = entity_names.get(full, table_names.get(full, ""))
        if table == "":
            continue
        id_fields = ids.get(full, [])
        if len(id_fields) != 1:
            diags.append(diag("AN1804", full + ": exactly one @Id required", full))
            continue
        id_name = id_fields[0]
        fields = []
        names = {}
        unsupported = []
        for field in sym.get("fields", []):
            if field.get("static"):
                continue
            fname = field.get("name", "")
            ftype = field.get("type", "")
            key = full + "#" + fname
            column = columns.get(key, fname)
            if column in names:
                diags.append(diag("AN1809", full + "." + column + ": duplicate column", key))
                fields = []
                break
            names[column] = True
            if ftype not in SUPPORTED:
                diags.append(diag("AN1806", full + "." + column + ": unsupported type " + ftype + "; skipped", key, severity="Warning"))
                unsupported.append(fname)
                continue
            fields.append({"name": fname, "type": ftype, "column": column})
        if not fields:
            continue
        id_field = next((f for f in fields if f["name"] == id_name), None)
        if id_field is None:
            diags.append(diag("AN1804", full + ": @Id field type is not supported", full))
            continue
        ctor = ctor_for(sym)
        if ctor is None:
            diags.append(diag("AN1806", full + ": no constructor matches fields", full, severity="Warning"))
            continue
        entity_plans[full] = {"sym": sym, "table": table, "fields": fields,
                              "id": id_field, "unsupported": unsupported, "ctor": ctor}

    tx_plans = []
    for entry in transactions:
        sym = by_full.get(entry["owner"])
        if sym is None:
            diags.append(diag("AN1807", "transaction owner not found: " + entry["owner"], entry["owner"]))
            continue
        method = None
        for candidate in sym.get("methods", []):
            if candidate.get("name") == entry["method"] and [simple(p.get("type", "")) for p in candidate.get("params", [])] == [simple(t) for t in entry["types"]]:
                method = candidate
                break
        if method is None:
            diags.append(diag("AN1807", "transaction method not found: " + entry["owner"] + "#" + entry["method"], entry["owner"]))
            continue
        params = method.get("params", [])
        success = parse_result(method.get("return", ""))
        if len(params) == 0 or simple(params[0].get("type", "")) != "SqlTransaction" or success is None:
            diags.append(diag("AN1807", "transaction method must start with SqlTransaction and return Result<T,Error>: " + entry["owner"] + "#" + entry["method"], entry["owner"]))
            continue
        if entry["readOnly"]:
            diags.append(diag("AN1808", "readOnly transaction has no driver hint support: " + entry["owner"] + "#" + entry["method"], entry["owner"], severity="Warning"))
        tx_plans.append({"owner": entry["owner"], "sym": sym, "method": method,
                         "params": params[1:], "return": method.get("return", ""),
                         "readOnly": entry["readOnly"]})

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0
    if not entity_plans and not tx_plans:
        write_diags(out, diags)
        return 0

    package = ""
    if entity_plans:
        package = next(iter(entity_plans.values()))["sym"].get("package", "")
    if package == "" and tx_plans:
        package = tx_plans[0]["sym"].get("package", "")
    if package == "":
        package = "app.db"

    lines = [
        "// generated by db_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.db",
        "import xdk.sql",
        "import xdk.errors",
        "",
        "static Int dbColumnIndex(List<SqlColumn> columns, String name) {",
        "    Int index = 0",
        "    while index < columns.length() {",
        "        if columns.get(index).name() == name { return index }",
        "        index = index + 1",
        "    }",
        "    return -1",
        "}",
        "",
    ]

    for full in sorted(entity_plans):
        plan = entity_plans[full]
        type_name = plan["sym"].get("simpleName")
        fields = plan["fields"]
        id_field = plan["id"]
        columns_sql = ", ".join(f["column"] + " " + SQL_TYPE[f["type"]] for f in fields)
        lines.append("String " + type_name + "TableName() { return " + lit(plan["table"]) + " }")
        lines.append("")
        lines.append("SqlStatement " + type_name + "CreateTableStatement() {")
        lines.append("    SqlStatement statement = new SqlStatement(" + lit("CREATE TABLE " + plan["table"] + " (" + columns_sql + ", PRIMARY KEY (" + id_field["column"] + "))") + ")")
        lines.append("    return statement")
        lines.append("}")
        lines.append("")
        lines.append("SqlStatement " + type_name + "InsertStatement(" + type_name + " value) {")
        values = ", ".join(":" + f["name"] for f in fields)
        lines.append("    SqlStatement statement = new SqlStatement(" + lit("INSERT INTO " + plan["table"] + " VALUES (" + values + ")") + ")")
        for field in fields:
            cast = {"String": "ofString", "Int": "ofInt", "Long": "ofLong", "Double": "ofDouble", "Bool": "ofBool"}[field["type"]]
            lines.append("    statement = statement.withParameter(SqlParameter.named(" + lit(field["name"]) + ", SqlValue." + cast + "(value." + field["name"] + ")))")
        lines.append("    return statement")
        lines.append("}")
        lines.append("")
        lines.append("SqlStatement " + type_name + "SelectByIdStatement(" + id_field["type"] + " id) {")
        select = ", ".join(f["column"] for f in fields)
        lines.append("    SqlStatement statement = new SqlStatement(" + lit("SELECT " + select + " FROM " + plan["table"] + " WHERE " + id_field["column"] + " = :id") + ")")
        cast = {"String": "ofString", "Int": "ofInt", "Long": "ofLong", "Double": "ofDouble", "Bool": "ofBool"}[id_field["type"]]
        lines.append("    statement = statement.withParameter(SqlParameter.named(\"id\", SqlValue." + cast + "(id)))")
        lines.append("    return statement")
        lines.append("}")
        lines.append("")
        lines.append("SqlStatement " + type_name + "UpdateStatement(" + type_name + " value) {")
        updates = [f for f in fields if f["name"] != id_field["name"]]
        set_sql = ", ".join(f["column"] + " = :" + f["name"] for f in updates)
        lines.append("    SqlStatement statement = new SqlStatement(" + lit("UPDATE " + plan["table"] + " SET " + set_sql + " WHERE " + id_field["column"] + " = :id") + ")")
        for field in updates:
            cast = {"String": "ofString", "Int": "ofInt", "Long": "ofLong", "Double": "ofDouble", "Bool": "ofBool"}[field["type"]]
            lines.append("    statement = statement.withParameter(SqlParameter.named(" + lit(field["name"]) + ", SqlValue." + cast + "(value." + field["name"] + ")))")
        cast = {"String": "ofString", "Int": "ofInt", "Long": "ofLong", "Double": "ofDouble", "Bool": "ofBool"}[id_field["type"]]
        lines.append("    statement = statement.withParameter(SqlParameter.named(\"id\", SqlValue." + cast + "(value." + id_field["name"] + ")))")
        lines.append("    return statement")
        lines.append("}")
        lines.append("")
        lines.append("SqlStatement " + type_name + "DeleteByIdStatement(" + id_field["type"] + " id) {")
        lines.append("    SqlStatement statement = new SqlStatement(" + lit("DELETE FROM " + plan["table"] + " WHERE " + id_field["column"] + " = :id") + ")")
        lines.append("    statement = statement.withParameter(SqlParameter.named(\"id\", SqlValue." + cast + "(id)))")
        lines.append("    return statement")
        lines.append("}")
        lines.append("")
        lines.append("Result<" + type_name + ", Error> " + type_name + "FromRow(SqlRow row, List<SqlColumn> columns) {")
        lines.append("    if row == null || columns == null { throw \"" + type_name + "FromRow: null argument\" }")
        for idx, field in enumerate(fields):
            lines.append("    Int index" + str(idx) + " = dbColumnIndex(columns, " + lit(field["column"]) + ")")
            lines.append("    if index" + str(idx) + " < 0 || index" + str(idx) + " >= row.length() {")
            lines.append("        return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + "." + field["column"] + ": missing column") + "))")
            lines.append("    }")
            lines.append("    SqlValue value" + str(idx) + " = row.get(index" + str(idx) + ")")
            kind = {"String": "SqlKind.String", "Int": "SqlKind.Int", "Long": "SqlKind.Long", "Double": "SqlKind.Double", "Bool": "SqlKind.Bool"}[field["type"]]
            lines.append("    if value" + str(idx) + ".kind() != " + kind + " {")
            lines.append("        return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + "." + field["column"] + ": expected " + field["type"]) + "))")
            lines.append("    }")
            cast = {"String": "asString", "Int": "asInt", "Long": "asLong", "Double": "asDouble", "Bool": "asBool"}[field["type"]]
            lines.append("    " + field["type"] + " field" + str(idx) + " = value" + str(idx) + "." + cast + "().value()")
        mapping, ctor_params = plan["ctor"]
        fields_all = [f for f in plan["sym"].get("fields", []) if not f.get("static")]
        supported_index = {f["name"]: i for i, f in enumerate(fields)}
        args_list = []
        zero_index = 0
        for param in ctor_params:
            field_name = fields_all[mapping.get(param.get("name", ""))]["name"] if mapping.get(param.get("name", "")) is not None else ""
            if field_name in supported_index:
                args_list.append("field" + str(supported_index[field_name]))
            else:
                ftype = param.get("type", "")
                if ftype.startswith("List<"):
                    zero = "zero" + str(zero_index)
                    lines.append("    " + ftype + " " + zero + " = []")
                    zero_index += 1
                    args_list.append(zero)
                else:
                    args_list.append(zero_expr(ftype))
        lines.append("    return Ok(new " + type_name + "(" + ", ".join(args_list) + "))")
        lines.append("}")
        lines.append("")
        lines.append("Result<Long, Error> " + type_name + "Insert(SqlConnection connection, " + type_name + " value) {")
        lines.append("    if connection == null || value == null { throw \"" + type_name + "Insert: null argument\" }")
        lines.append("    Result<SqlResult, Error> result = connection.execute(" + type_name + "InsertStatement(value))")
        lines.append("    if result.isErr() { return Err(result.error()) }")
        lines.append("    return Ok(result.value().rowsAffected())")
        lines.append("}")
        lines.append("")
        lines.append("Result<" + type_name + ", Error> " + type_name + "FindById(SqlConnection connection, " + id_field["type"] + " id) {")
        lines.append("    if connection == null { throw \"" + type_name + "FindById: null connection\" }")
        lines.append("    Result<SqlResult, Error> result = connection.execute(" + type_name + "SelectByIdStatement(id))")
        lines.append("    if result.isErr() { return Err(result.error()) }")
        lines.append("    SqlResult value = result.value()")
        lines.append("    List<SqlRow> rows = value.rows()")
        lines.append("    if rows.length() == 0 { return Err(new BasicError(ErrorKind.NotFound, " + lit(type_name + ": not found") + ")) }")
        lines.append("    if rows.length() > 1 { return Err(new BasicError(ErrorKind.DataCorrupted, " + lit(type_name + ": multiple rows") + ")) }")
        lines.append("    return " + type_name + "FromRow(rows.get(0), value.columns())")
        lines.append("}")
        lines.append("")
        lines.append("Result<Long, Error> " + type_name + "Update(SqlConnection connection, " + type_name + " value) {")
        lines.append("    if connection == null || value == null { throw \"" + type_name + "Update: null argument\" }")
        lines.append("    Result<SqlResult, Error> result = connection.execute(" + type_name + "UpdateStatement(value))")
        lines.append("    if result.isErr() { return Err(result.error()) }")
        lines.append("    return Ok(result.value().rowsAffected())")
        lines.append("}")
        lines.append("")
        lines.append("Result<Long, Error> " + type_name + "DeleteById(SqlConnection connection, " + id_field["type"] + " id) {")
        lines.append("    if connection == null { throw \"" + type_name + "DeleteById: null connection\" }")
        lines.append("    Result<SqlResult, Error> result = connection.execute(" + type_name + "DeleteByIdStatement(id))")
        lines.append("    if result.isErr() { return Err(result.error()) }")
        lines.append("    return Ok(result.value().rowsAffected())")
        lines.append("}")
        lines.append("")
        lines.append("Result<List<" + type_name + ">, Error> " + type_name + "ListAll(SqlConnection connection) {")
        lines.append("    if connection == null { throw \"" + type_name + "ListAll: null connection\" }")
        select = ", ".join(f["column"] for f in fields)
        lines.append("    SqlStatement statement = new SqlStatement(" + lit("SELECT " + select + " FROM " + plan["table"]) + ")")
        lines.append("    Result<SqlResult, Error> result = connection.execute(statement)")
        lines.append("    if result.isErr() { return Err(result.error()) }")
        lines.append("    SqlResult value = result.value()")
        lines.append("    List<SqlRow> rows = value.rows()")
        lines.append("    List<SqlColumn> columns = value.columns()")
        lines.append("    List<" + type_name + "> mapped = []")
        lines.append("    Int index = 0")
        lines.append("    while index < rows.length() {")
        lines.append("        Result<" + type_name + ", Error> mappedRow = " + type_name + "FromRow(rows.get(index), columns)")
        lines.append("        if mappedRow.isErr() { return Err(mappedRow.error()) }")
        lines.append("        mapped.push(mappedRow.value())")
        lines.append("        index = index + 1")
        lines.append("    }")
        lines.append("    return Ok(mapped)")
        lines.append("}")
        lines.append("")

    for plan in tx_plans:
        type_name = plan["sym"].get("simpleName")
        method = plan["method"]["name"]
        extra = plan["params"]
        extra_text = ", ".join(simple(p["type"]) + " " + p["name"] for p in extra)
        signature_params = "SqlConnection connection, " + type_name + " target"
        if extra_text != "":
            signature_params += ", " + extra_text
        call_args = ", ".join(p["name"] for p in extra)
        call_text = "target." + method + "(tx"
        if call_args != "":
            call_text += ", " + call_args
        call_text += ")"
        lines.append(plan["return"] + " " + type_name + "_" + method + "Transactional(" + signature_params + ") {")
        lines.append("    if connection == null || target == null { throw \"" + type_name + "_" + method + "Transactional: null argument\" }")
        if plan["readOnly"]:
            lines.append("    // readOnly requested; this driver version has no read-only transaction hint.")
        lines.append("    Result<SqlTransaction, Error> started = connection.begin()")
        lines.append("    if started.isErr() { return Err(started.error()) }")
        lines.append("    SqlTransaction tx = started.value()")
        lines.append("    " + plan["return"] + " outcome = " + call_text)
        lines.append("    if outcome.isErr() {")
        lines.append("        tx.rollback()")
        lines.append("        return outcome")
        lines.append("    }")
        lines.append("    Result<Unit, Error> committed = tx.commit()")
        lines.append("    if committed.isErr() { return Err(committed.error()) }")
        lines.append("    return outcome")
        lines.append("}")
        lines.append("")

    (out / "DbGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    if diags:
        write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
