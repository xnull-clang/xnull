#!/usr/bin/env python3
"""M11.2: generate explicit test suites and benchmark lists from annotations."""
import argparse
import json
import sys
from pathlib import Path

TEST_CASE = "xdk.test.TestCase"
BEFORE = "xdk.test.Before"
AFTER = "xdk.test.After"
BENCHMARK = "xdk.test.Benchmark"
TEST_ANNOTATIONS = {TEST_CASE: "case", BEFORE: "before", AFTER: "after", BENCHMARK: "benchmark"}


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


def supported_return(return_type):
    if return_type.strip() == "void":
        return "void"
    success = parse_result(return_type)
    if success is not None and simple(success) == "Unit":
        return "result"
    return None


def method_name_of(use):
    owner, name, _ = split_signature(use.get("targetName", ""))
    return owner, name


def find_method(sym, name, types):
    for candidate in sym.get("methods", []):
        if candidate.get("name") != name:
            continue
        params = [p.get("type", "") for p in candidate.get("params", [])]
        if [simple(t) for t in params] == [simple(t) for t in types]:
            return candidate
    return None


def literal(text):
    return json.dumps(text, ensure_ascii=False)


def body_call(lines, target_expr, method_name, method_return, result_name=None,
              indent="        ", declare=True):
    if method_return == "void":
        lines.append(indent + target_expr + "." + method_name + "()")
        if result_name is not None:
            lines.append(indent + "Result<Unit, Error> " + result_name + " = Ok()")
    elif declare:
        lines.append(indent + "Result<Unit, Error> " + result_name + " = " + target_expr + "." + method_name + "()")
    else:
        lines.append(indent + result_name + " = " + target_expr + "." + method_name + "()")


def generate_suite(type_name, plan):
    lines = ["TestSuite " + type_name + "Suite(" + type_name + " target) {"]
    lines.append('    if target == null { throw "' + type_name + 'Suite: null target" }')
    lines.append("    TestSuite suite = new TestSuite(" + literal(type_name) + ")")
    lines.append("    List<String> tags = []")
    for index, entry in enumerate(plan["cases"]):
        method = entry["method"]
        lines.append("    Result<Unit, Error>(TestContext) case" + str(index) + " = (TestContext context) -> {")
        before = plan["before"]
        after = plan["after"]
        if before is not None:
            body_call(lines, "target", before["method"]["name"], before["kind"], "beforeResult")
        else:
            lines.append("        Result<Unit, Error> beforeResult = Ok()")
        lines.append("        if beforeResult.isErr() {")
        if after is not None:
            body_call(lines, "target", after["method"]["name"], after["kind"], "afterResult", "            ")
        else:
            lines.append("            Result<Unit, Error> afterResult = Ok()")
        lines.append("            return beforeResult")
        lines.append("        }")
        if entry["kind"] == "void":
            lines.append("        target." + method["name"] + "()")
        else:
            lines.append("        Result<Unit, Error> outcome = target." + method["name"] + "()")
        if after is not None:
            body_call(lines, "target", after["method"]["name"], after["kind"], "afterResult")
        else:
            lines.append("        Result<Unit, Error> afterResult = Ok()")
        if entry["kind"] != "void":
            lines.append("        if outcome.isErr() { return outcome }")
        lines.append("        if afterResult.isErr() { return afterResult }")
        lines.append("        return Ok()")
        lines.append("    }")
        lines.append("    suite.add(new Test(" + literal(entry["name"]) + ", tags, 0, case" + str(index) + "))")
    lines.append("    return suite")
    lines.append("}")
    lines.append("")
    return lines


def generate_benchmarks(type_name, plan):
    lines = ["List<Test> " + type_name + "Benchmarks(" + type_name + " target) {"]
    lines.append('    if target == null { throw "' + type_name + 'Benchmarks: null target" }')
    lines.append("    List<Test> result = []")
    lines.append("    List<String> tags = []")
    for index, entry in enumerate(plan["benchmarks"]):
        method = entry["method"]
        lines.append("    Result<Unit, Error>(TestContext) benchmark" + str(index) + " = (TestContext context) -> {")
        if entry["kind"] == "void":
            lines.append("        target." + method["name"] + "()")
            lines.append("        return Ok()")
        else:
            lines.append("        return target." + method["name"] + "()")
        lines.append("    }")
        lines.append("    result.push(new Test(" + literal(entry["name"]) + ", tags, 0, benchmark" + str(index) + "))")
    lines.append("    return result")
    lines.append("}")
    lines.append("")
    return lines


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

    plans = {}
    diags = []
    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        kind = TEST_ANNOTATIONS.get(name)
        if kind is None:
            continue
        target_name = use.get("targetName", "")
        line = use.get("line", 1)
        col = use.get("col", 1)
        if use.get("target") != "Method":
            diags.append(diag("AN2201", "@" + simple(name) + " must target an instance method: " + target_name,
                              target_name, line, col))
            continue
        owner, method_name, types = split_signature(target_name)
        sym = symbols.get(owner)
        if not sym or sym.get("kind") != "Class":
            diags.append(diag("AN2201", "@" + simple(name) + " requires a class method: " + target_name,
                              target_name, line, col))
            continue
        method = find_method(sym, method_name, types)
        if method is None:
            diags.append(diag("AN2201", "@" + simple(name) + " method not found: " + target_name,
                              target_name, line, col))
            continue
        if method.get("static") or len(method.get("params", [])) != 0:
            diags.append(diag("AN2201", "@" + simple(name) + " method must be non-static and take no parameters: " +
                              target_name, target_name, line, col))
            continue
        supported = supported_return(method.get("return", ""))
        if supported is None:
            diags.append(diag("AN2202", "@" + simple(name) +
                              " method must return void or Result<Unit, Error>: " + target_name,
                              target_name, line, col))
            continue
        plan = plans.setdefault(owner, {"sym": sym, "cases": [], "before": None, "after": None,
                                        "benchmarks": [], "beforeCount": 0, "afterCount": 0})
        entry = {"use": use, "method": method, "kind": supported, "line": method.get("line", line),
                 "col": method.get("col", col), "target": target_name}
        label = text_arg(use, 0, "").strip()
        entry["name"] = label if label != "" else method_name
        if kind == "case":
            plan["cases"].append(entry)
        elif kind == "before":
            plan["beforeCount"] += 1
            if plan["before"] is None:
                plan["before"] = entry
        elif kind == "after":
            plan["afterCount"] += 1
            if plan["after"] is None:
                plan["after"] = entry
        else:
            plan["benchmarks"].append(entry)

    for owner in sorted(plans):
        plan = plans[owner]
        for label, count in (("Before", plan["beforeCount"]), ("After", plan["afterCount"])):
            if count > 1:
                diags.append(diag("AN2203", "at most one @" + label + " method is supported: " + owner,
                                  owner, plan["sym"].get("line", 1), plan["sym"].get("col", 1)))
        if not plan["cases"] and (plan["beforeCount"] or plan["afterCount"]):
            diags.append(diag("AN2204", "class has @Before/@After but no @TestCase: " + owner,
                              owner, plan["sym"].get("line", 1), plan["sym"].get("col", 1),
                              "Warning"))
        plan["cases"].sort(key=lambda e: (e["line"], e["col"], e["method"]["name"]))
        plan["benchmarks"].sort(key=lambda e: (e["line"], e["col"], e["method"]["name"]))

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0

    generated = [owner for owner in sorted(plans)
                 if plans[owner]["cases"] or plans[owner]["benchmarks"]]
    if not generated:
        write_diags(out, diags)
        return 0

    package = plans[generated[0]]["sym"].get("package", "") or "app.test"
    lines = [
        "// generated by test_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.test",
        "import xdk.errors",
        "",
    ]
    for owner in generated:
        plan = plans[owner]
        type_name = plan["sym"].get("simpleName") or simple(owner)
        if plan["cases"]:
            lines.extend(generate_suite(type_name, plan))
        if plan["benchmarks"]:
            lines.extend(generate_benchmarks(type_name, plan))

    (out / "TestGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
