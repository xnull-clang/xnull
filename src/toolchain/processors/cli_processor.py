#!/usr/bin/env python3
"""M2 pilot: generate xdk.cli Command tree from annotation IR v2."""
import argparse
import json
import sys
from pathlib import Path


def fail(out, code, message, target=""):
    out.mkdir(parents=True, exist_ok=True)
    (out / "diagnostics.json").write_text(json.dumps([{
        "code": code, "severity": "Error", "message": message,
        "line": 1, "col": 1, "target": target,
    }], ensure_ascii=False), encoding="utf-8")
    return 0


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
    positionals = {}
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
                return fail(out, "AN1005", name + " must target a field", target_name)
            owner, _, field = target_name.partition("#")
            if not field:
                return fail(out, "AN1005", name + " has invalid field target", target_name)
            sym = by_name.get(owner)
            if not sym:
                return fail(out, "AN1005", name + " owner type missing", owner)
            ftype = ""
            for f in sym.get("fields", []):
                if f.get("name") == field:
                    ftype = f.get("type", "")
                    break
            if name == "xdk.cli.Option":
                option = {
                    "owner": owner, "field": field, "type": ftype,
                    "name": text_arg(use, 0, 0),
                    "short": text_arg(use, 0, 1),
                    "help": text_arg(use, 0, 2),
                    "required": bool_arg(use, 3),
                }
                if ftype == "Bool" and option["required"]:
                    return fail(out, "AN1006", "Bool @Option cannot be required", target_name)
                options.setdefault(owner, []).append(option)
            else:
                positionals.setdefault(owner, []).append({
                    "field": field,
                    "name": text_arg(use, 0, 0),
                    "help": text_arg(use, 0, 1),
                    "required": bool_arg(use, 2),
                })

    if not commands:
        return fail(out, "AN1001", "no @CliCommand type found")
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

    roots = [c for c in commands if not any(s["type"] == c["type"] for s in subcommands)]
    if len(roots) != 1:
        return fail(out, "AN1001", "exactly one root @CliCommand required")
    root = roots[0]
    for sub in subcommands:
        if sub["parent"] not in names:
            return fail(out, "AN1002", "unknown parent command: " + sub["parent"], sub["type"])
        if names[sub["parent"]]["type"] == sub["type"]:
            return fail(out, "AN1003", "subcommand cannot parent itself", sub["type"])

    package = root["pkg"] or "app.cli"
    lines = [
        "// generated by cli_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.cli",
        "",
    ]

    def emit_options(owner, var):
        lines.append("    List<OptionSpec> " + var + " = []")
        for idx, o in enumerate(options.get(owner, [])):
            takes = "false" if o["type"] == "Bool" else "true"
            local = var + "Opt" + str(idx)
            expr = ('new OptionSpec("' + o["name"] + '", ' + takes + ', "' +
                    o["help"] + '", ' + ("true" if o["required"] else "false") + ')')
            lines.append("    OptionSpec " + local + " = " + expr)
            if o["short"]:
                short = o["short"]
                if not short.startswith("-"):
                    short = "-" + short
                lines.append("    " + local + " = " + local + '.withShort("' + short + '")')
            lines.append("    " + var + ".push(" + local + ")")
        if not options.get(owner):
            lines.append("    // no options")

    lines.append("Command cliCommandTree() {")
    root_var = "root"
    emit_options(root["type"], "rootOptions")
    lines.append('    Command ' + root_var + ' = new Command("' + root["name"] + '", "' + root["summary"] + '", rootOptions)')
    var_by_name = {root["name"]: root_var}
    for idx, sub in enumerate(subcommands):
        var = "sub" + str(idx)
        emit_options(sub["type"], var + "Options")
        lines.append('    Command ' + var + ' = new Command("' + sub["name"] + '", "' + sub["summary"] + '", ' + var + 'Options)')
        parent_var = var_by_name.get(sub["parent"], root_var)
        lines.append("    " + parent_var + ".add(" + var + ")")
        var_by_name[sub["name"]] = var
    lines.append("    return " + root_var)
    lines.append("}")
    lines.append("")
    lines.append("List<String> cliPositionalHelp() {")
    lines.append("    List<String> out = []")
    for c in commands + subcommands:
        for p in positionals.get(c["type"], []):
            suffix = " (required)" if p["required"] else ""
            lines.append('    out.push("' + p["name"] + ': ' + p["help"] + suffix + '")')
    lines.append("    return out")
    lines.append("}")
    lines.append("")
    (out / "CliGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
