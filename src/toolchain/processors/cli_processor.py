#!/usr/bin/env python3
"""M2 pilot: generate xdk.cli Command tree and typed binders from annotation IR v2."""
import argparse
import json
import sys
from pathlib import Path

SUPPORTED = {"String", "Int", "Long", "Double", "Bool"}
PARSE_HELPER = {"Int": "cliBindIntValue", "Long": "cliBindIntValue",
                "Double": "cliBindDoubleValue", "Bool": "cliBindBoolValue"}


def fail(out, code, message, target=""):
    out.mkdir(parents=True, exist_ok=True)
    (out / "diagnostics.json").write_text(json.dumps([{
        "code": code, "severity": "Error", "message": message,
        "line": 1, "col": 1, "target": target,
    }], ensure_ascii=False), encoding="utf-8")
    return 0


def warning(code, message, target=""):
    return {"code": code, "severity": "Warning", "message": message,
            "line": 1, "col": 1, "target": target}


def write_diagnostics(out, diagnostics):
    if not diagnostics:
        return
    out.mkdir(parents=True, exist_ok=True)
    (out / "diagnostics.json").write_text(
        json.dumps(diagnostics, ensure_ascii=False), encoding="utf-8")


def simple(name):
    return name.split(".")[-1]


def args_of(use):
    return use.get("arguments", [])


def text_arg(use, index, field_index, default=""):
    args = args_of(use)
    if field_index >= len(args):
        return default
    arg = args[field_index]
    return arg.get("text", default)


def bool_arg(use, field_index, default=False):
    args = args_of(use)
    if field_index >= len(args):
        return default
    arg = args[field_index]
    return arg.get("kind") == "bool" and arg.get("text") == "true"


def string_literal(text):
    return json.dumps(text, ensure_ascii=False)


def has_default_ctor(sym):
    ctors = sym.get("ctors", [])
    if not ctors:
        return True
    for ctor in ctors:
        if len(ctor.get("params", [])) == 0:
            return True
    return False


def field_type(sym, field_name):
    for field in sym.get("fields", []):
        if field.get("name") == field_name:
            return field.get("type", "")
    return ""


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
    by_name = {t.get("fullName"): t for t in symbols}
    uses = ir.get("uses", [])

    commands = []
    subcommands = []
    options = {}
    args_map = {}
    arg_owners = {}
    warnings = []
    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        target = use.get("target")
        target_name = use.get("targetName", "")
        if name == "xdk.cli.CliCommand":
            if target != "Type":
                return fail(out, "AN1005", "@CliCommand must target a class", target_name)
            sym = by_name.get(target_name)
            if not sym or sym.get("kind") != "Class":
                return fail(out, "AN1005", "@CliCommand requires a class", target_name)
            commands.append({
                "type": target_name,
                "name": text_arg(use, 0, 0),
                "summary": text_arg(use, 0, 1),
                "pkg": sym.get("package", ""),
            })
        elif name == "xdk.cli.CliSubcommand":
            if target != "Type":
                return fail(out, "AN1005", "@CliSubcommand must target a class", target_name)
            sym = by_name.get(target_name)
            if not sym or sym.get("kind") != "Class":
                return fail(out, "AN1005", "@CliSubcommand requires a class", target_name)
            subcommands.append({
                "type": target_name,
                "parent": text_arg(use, 0, 0),
                "name": text_arg(use, 0, 1),
                "summary": text_arg(use, 0, 2),
                "pkg": sym.get("package", ""),
            })
        elif name in ("xdk.cli.Option", "xdk.cli.Arg"):
            if target != "Field":
                code = "AN1702" if name == "xdk.cli.Arg" else "AN1005"
                return fail(out, code, name + " must target a field", target_name)
            owner, _, field = target_name.partition("#")
            if not field:
                return fail(out, "AN1005", name + " has invalid field target", target_name)
            sym = by_name.get(owner)
            if not sym:
                return fail(out, "AN1005", name + " owner type missing", owner)
            ftype = field_type(sym, field)
            if ftype == "":
                return fail(out, "AN1005", name + " target field missing", target_name)
            if name == "xdk.cli.Option":
                option = {
                    "owner": owner, "field": field, "type": ftype,
                    "name": text_arg(use, 0, 0),
                    "short": text_arg(use, 0, 1),
                    "help": text_arg(use, 0, 2),
                    "required": bool_arg(use, 3),
                }
                if option["name"] == "":
                    return fail(out, "AN1005", "option name must not be empty", target_name)
                if ftype == "Bool" and option["required"]:
                    return fail(out, "AN1006", "Bool @Option cannot be required", target_name)
                if ftype not in SUPPORTED:
                    warnings.append(warning("AN1703", "@Option field type is not supported: " +
                                            owner + "." + field + " (" + ftype + "); skipped", target_name))
                    continue
                options.setdefault(owner, []).append(option)
            else:
                arg = {
                    "owner": owner, "field": field, "type": ftype,
                    "name": text_arg(use, 0, 0),
                    "help": text_arg(use, 1, 1),
                    "required": bool_arg(use, 2),
                }
                if arg["name"] == "":
                    return fail(out, "AN1702", "@Arg name must not be empty", target_name)
                arg_owners[owner] = True
                if ftype not in SUPPORTED:
                    warnings.append(warning("AN1703", "@Arg field type is not supported: " +
                                            owner + "." + field + " (" + ftype + "); skipped", target_name))
                    continue
                args_map.setdefault(owner, []).append(arg)

    if not commands:
        return fail(out, "AN1001", "no @CliCommand type found")

    for sub in subcommands:
        for other in subcommands:
            if sub is other:
                continue
            if sub["parent"] == other["parent"] and sub["name"] == other["name"] and sub["type"] < other["type"]:
                return fail(out, "AN1701", "duplicate subcommand under parent: " +
                            sub["parent"] + " " + sub["name"], sub["type"])

    names = {}
    for c in commands + subcommands:
        if not c["name"]:
            return fail(out, "AN1001", "command name must not be empty", c["type"])
        if c["name"] in names:
            return fail(out, "AN1003", "duplicate command name: " + c["name"], c["type"])
        names[c["name"]] = c
    for owner, opts in options.items():
        seen = set()
        for o in opts:
            if o["name"] in seen:
                return fail(out, "AN1004", "duplicate option: " + o["name"], owner)
            seen.add(o["name"])

    for owner, entries in args_map.items():
        seen = set()
        for entry in entries:
            if entry["name"] in seen:
                return fail(out, "AN1705", "duplicate positional name: " + entry["name"], owner)
            seen.add(entry["name"])

    roots = [c for c in commands if not any(s["type"] == c["type"] for s in subcommands)]
    if len(roots) != 1:
        return fail(out, "AN1001", "exactly one root @CliCommand required")
    root = roots[0]
    for sub in subcommands:
        if sub["parent"] not in names:
            return fail(out, "AN1002", "unknown parent command: " + sub["parent"], sub["type"])
        if names[sub["parent"]]["type"] == sub["type"]:
            return fail(out, "AN1003", "subcommand cannot parent itself", sub["type"])
    if root["type"] in arg_owners:
        return fail(out, "AN1706", "@Arg is not allowed on the root command", root["type"])

    package = root["pkg"] or "app.cli"
    lines = [
        "// generated by cli_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.cli",
        "import xdk.errors",
        "import xdk.text",
        "",
        "Result<Int, Error> cliBindIntValue(String field, String text) {",
        "    Result<Int, Error> parsed = parseInt(text)",
        "    if parsed.isErr() {",
        "        return Err(cliError(ErrorKind.InvalidArgument, field + \": invalid integer\"))",
        "    }",
        "    return parsed",
        "}",
        "",
        "Result<Double, Error> cliBindDoubleValue(String field, String text) {",
        "    Result<Double, Error> parsed = parseFloat(text)",
        "    if parsed.isErr() {",
        "        return Err(cliError(ErrorKind.InvalidArgument, field + \": invalid number\"))",
        "    }",
        "    return parsed",
        "}",
        "",
        "Result<Bool, Error> cliBindBoolValue(String field, String text) {",
        "    if text == \"true\" { return Ok(true) }",
        "    if text == \"false\" { return Ok(false) }",
        "    return Err(cliError(ErrorKind.InvalidArgument, field + \": invalid boolean\"))",
        "}",
        "",
    ]

    def emit_options(owner, var):
        lines.append("    List<OptionSpec> " + var + " = []")
        for idx, o in enumerate(options.get(owner, [])):
            takes = "false" if o["type"] == "Bool" else "true"
            local = var + "Opt" + str(idx)
            expr = ('new OptionSpec(' + string_literal(o["name"]) + ', ' + takes + ', ' +
                    string_literal(o["help"]) + ', ' + ("true" if o["required"] else "false") + ')')
            lines.append("    OptionSpec " + local + " = " + expr)
            if o["short"]:
                short = o["short"]
                if not short.startswith("-"):
                    short = "-" + short
                lines.append("    " + local + " = " + local + ".withShort(" + string_literal(short) + ")")
            lines.append("    " + var + ".push(" + local + ")")
        if not options.get(owner):
            lines.append("    // no options")

    def emit_arg_specs(owner, var):
        for idx, p in enumerate(args_map.get(owner, [])):
            local = var + "Positional" + str(idx)
            expr = ('new ArgSpec(' + string_literal(p["name"]) + ', ' +
                    string_literal(p["help"]) + ', ' + ("true" if p["required"] else "false") + ')')
            lines.append("    ArgSpec " + local + " = " + expr)
        if not args_map.get(owner):
            lines.append("    // no positionals")

    def emit_arg_adds(owner, var):
        for idx in range(len(args_map.get(owner, []))):
            lines.append("    " + var + ".addPositional(" + var + "Positional" + str(idx) + ")")

    lines.append("Command cliCommandTree() {")
    root_var = "root"
    emit_options(root["type"], "rootOptions")
    emit_arg_specs(root["type"], "root")
    lines.append('    Command ' + root_var + ' = new Command(' + string_literal(root["name"]) + ', ' +
                 string_literal(root["summary"]) + ', rootOptions)')
    emit_arg_adds(root["type"], "root")
    var_by_name = {root["name"]: root_var}
    for idx, sub in enumerate(subcommands):
        var = "sub" + str(idx)
        emit_options(sub["type"], var + "Options")
        emit_arg_specs(sub["type"], var)
        lines.append('    Command ' + var + ' = new Command(' + string_literal(sub["name"]) + ', ' +
                     string_literal(sub["summary"]) + ', ' + var + 'Options)')
        emit_arg_adds(sub["type"], var)
        parent_var = var_by_name.get(sub["parent"], root_var)
        lines.append("    " + parent_var + ".add(" + var + ")")
        var_by_name[sub["name"]] = var
    lines.append("    return " + root_var)
    lines.append("}")
    lines.append("")
    lines.append("List<String> cliPositionalHelp() {")
    lines.append("    List<String> out = []")
    for c in commands + subcommands:
        for p in args_map.get(c["type"], []):
            suffix = " (required)" if p["required"] else ""
            lines.append('    out.push(' + string_literal(p["name"] + ": " + p["help"] + suffix) + ')')
    lines.append("    return out")
    lines.append("}")
    lines.append("")

    for c in commands + subcommands:
        sym = by_name.get(c["type"])
        if not sym:
            continue
        if not has_default_ctor(sym):
            warnings.append(warning("AN1704", "command type has no default constructor; binder skipped: " +
                                    c["type"], c["type"]))
            continue
        type_name = sym.get("simpleName") or simple(c["type"])
        lines.append("Result<" + type_name + ", Error> " + type_name + "Bind(CommandMatch match) {")
        lines.append('    if match == null { throw "' + type_name + 'Bind: null match" }')
        lines.append("    List<String> positionals = match.positionals()")
        lines.append("    " + type_name + " value = new " + type_name + "()")
        for idx, o in enumerate(options.get(c["type"], [])):
            field = o["field"]
            if o["type"] == "Bool":
                lines.append("    value." + field + " = match.arguments.has(" + string_literal(o["name"]) + ")")
            elif o["type"] == "String":
                lines.append("    if match.arguments.has(" + string_literal(o["name"]) + ") {")
                lines.append("        value." + field + " = match.arguments.lastValue(" +
                             string_literal(o["name"]) + ")")
                lines.append("    }")
            else:
                helper = PARSE_HELPER[o["type"]]
                parsed_type = "Int" if o["type"] == "Long" else o["type"]
                lines.append("    if match.arguments.has(" + string_literal(o["name"]) + ") {")
                lines.append("        Result<" + parsed_type + ", Error> parsed" + str(idx) + " = " +
                             helper + "(" + string_literal(field) + ", match.arguments.lastValue(" +
                             string_literal(o["name"]) + "))")
                lines.append("        if parsed" + str(idx) + ".isErr() { return Err(parsed" + str(idx) + ".error()) }")
                lines.append("        value." + field + " = parsed" + str(idx) + ".value()")
                lines.append("    }")
        for idx, p in enumerate(args_map.get(c["type"], [])):
            field = p["field"]
            if p["type"] == "String":
                lines.append("    if positionals.length() > " + str(idx) + " {")
                lines.append("        value." + field + " = positionals.get(" + str(idx) + ")")
                lines.append("    }")
                if p["required"]:
                    lines.append("    else {")
                    lines.append("        return Err(cliError(ErrorKind.InvalidArgument, " +
                                 string_literal(field + ": missing required argument") + "))")
                    lines.append("    }")
            else:
                helper = PARSE_HELPER[p["type"]]
                parsed_type = "Int" if p["type"] == "Long" else p["type"]
                lines.append("    if positionals.length() > " + str(idx) + " {")
                lines.append("        Result<" + parsed_type + ", Error> argParsed" + str(idx) + " = " +
                             helper + "(" + string_literal(field) + ", positionals.get(" + str(idx) + "))")
                lines.append("        if argParsed" + str(idx) + ".isErr() { return Err(argParsed" + str(idx) + ".error()) }")
                lines.append("        value." + field + " = argParsed" + str(idx) + ".value()")
                lines.append("    }")
                if p["required"]:
                    lines.append("    else {")
                    lines.append("        return Err(cliError(ErrorKind.InvalidArgument, " +
                                 string_literal(field + ": missing required argument") + "))")
                    lines.append("    }")
        lines.append("    return Ok(value)")
        lines.append("}")
        lines.append("")

    (out / "CliGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    write_diagnostics(out, warnings)
    return 0


if __name__ == "__main__":
    sys.exit(main())
