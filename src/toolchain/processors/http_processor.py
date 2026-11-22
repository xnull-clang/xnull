#!/usr/bin/env python3
"""M5.2: generate Http routers from @HttpRoute/@Header/@Query/@Body IR v2."""
import argparse
import json
import re
import sys
from pathlib import Path

ROUTE = "xdk.net.http.HttpRoute"
HEADER = "xdk.net.http.Header"
QUERY = "xdk.net.http.Query"
BODY = "xdk.net.http.Body"
SERIALIZABLE = "xdk.codec.Serializable"
SCALARS = {"String", "Int", "Long"}


def diag(code, message, target="", severity="Error", line=1, col=1):
    return {"code": code, "severity": severity, "message": message,
            "line": line, "col": col, "target": target}


def write_diags(out, diags):
    out.mkdir(parents=True, exist_ok=True)
    (out / "diagnostics.json").write_text(json.dumps(diags, ensure_ascii=False), encoding="utf-8")


def text_arg(use, index, default=""):
    args = use.get("arguments", [])
    if index >= len(args):
        return default
    return args[index].get("text", default)


def simple(name):
    return name.split(".")[-1]


def split_signature(target):
    """app.Api#m(String,Int) -> (owner, method, [types])"""
    owner, _, rest = target.partition("#")
    if "(" not in rest or not rest.endswith(")"):
        return owner, "", []
    name = rest.split("(", 1)[0]
    inner = rest[len(name) + 1:-1]
    types = [t.strip() for t in inner.split(",")] if inner.strip() else []
    return owner, name, types


def template_parts(template):
    return template.split("/")


def validate_template(template, target, diags):
    if template == "" or not template.startswith("/"):
        diags.append(diag("AN1307", "route path must start with /: " + template, target))
        return None
    names = []
    for part in template_parts(template):
        if part == "":
            continue
        if part.startswith("{") or part.endswith("}"):
            if not (part.startswith("{") and part.endswith("}")) or len(part) < 3:
                diags.append(diag("AN1307", "malformed path segment: " + part, target))
                return None
            name = part[1:-1]
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
                diags.append(diag("AN1307", "invalid path parameter: " + part, target))
                return None
            if name in names:
                diags.append(diag("AN1307", "duplicate path parameter: " + name, target))
                return None
            names.append(name)
    return names


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
    routes = []
    params = {}
    body_types = set()

    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        target = use.get("target")
        target_name = use.get("targetName", "")
        line = use.get("line", 1)
        col = use.get("col", 1)
        if name == SERIALIZABLE and target == "Type":
            body_types.add(target_name)
        elif name == ROUTE:
            if target != "Method":
                diags.append(diag("AN1301", "@HttpRoute must target a method: " + target_name, target_name, line=line, col=col))
                continue
            owner, method, types = split_signature(target_name)
            path = text_arg(use, 0)
            method_text = text_arg(use, 1, "HttpMethod.Get")
            http_method = method_text.split(".")[-1]
            routes.append({"owner": owner, "method": method, "types": types,
                           "path": path, "httpMethod": http_method,
                           "line": line, "col": col})
        elif name in (HEADER, QUERY, BODY):
            if target != "Parameter":
                diags.append(diag("AN1302", name.split(".")[-1] + " must target a parameter: " + target_name, target_name, line=line, col=col))
                continue
            if "#" not in target_name:
                diags.append(diag("AN1302", "invalid parameter target: " + target_name, target_name, line=line, col=col))
                continue
            base, _, index_text = target_name.rpartition("#")
            try:
                index = int(index_text)
            except ValueError:
                diags.append(diag("AN1302", "invalid parameter index: " + target_name, target_name, line=line, col=col))
                continue
            value = text_arg(use, 0) if name != BODY else ""
            if name in (HEADER, QUERY) and value == "":
                diags.append(diag("AN1302", name.split(".")[-1] + " requires a non-empty name", target_name, line=line, col=col))
                continue
            kind = "header" if name == HEADER else ("query" if name == QUERY else "body")
            params.setdefault(base, {})[index] = {"kind": kind, "name": value,
                                                  "line": line, "col": col}

    if not routes:
        if not diags:
            diags.append(diag("AN1301", "no @HttpRoute method found", "", severity="Warning"))
        write_diags(out, diags)
        return 0

    groups = {}
    for route in routes:
        groups.setdefault(route["owner"], []).append(route)

    plans = {}
    for owner in sorted(groups):
        sym = by_full.get(owner)
        if not sym or sym.get("kind") != "Class":
            diags.append(diag("AN1301", "route owner is not a class: " + owner, owner))
            continue
        methods = {m.get("name"): m for m in sym.get("methods", [])}
        class_routes = groups[owner]
        seen = {}
        route_plans = []
        for route in class_routes:
            method = methods.get(route["method"])
            if method is None:
                diags.append(diag("AN1301", "route method not found: " + owner + "#" + route["method"], owner, line=route["line"], col=route["col"]))
                continue
            if simple(method.get("return", "")) != "HttpResponse":
                diags.append(diag("AN1306", route["method"] + " must return HttpResponse", owner))
                continue
            path_names = validate_template(route["path"], owner + "#" + route["method"], diags)
            if path_names is None:
                continue
            key = route["httpMethod"] + " " + route["path"]
            if key in seen:
                diags.append(diag("AN1303", "duplicate route: " + key, owner))
                continue
            seen[key] = True
            method_params = method.get("params", [])
            param_annotations = params.get(owner + "#" + route["method"] + "(" + ",".join(route["types"]) + ")", {})
            bound = []
            ok = True
            for idx, param in enumerate(method_params):
                pname = param.get("name", "")
                ptype = param.get("type", "")
                annotation = param_annotations.get(idx)
                kind = "path" if annotation is None else annotation["kind"]
                source_name = pname if annotation is None else annotation["name"]
                nullable = ptype.endswith("?")
                base = ptype[:-1] if nullable else ptype
                if kind == "path":
                    if source_name not in path_names:
                        diags.append(diag("AN1304", "no path segment binds parameter: " + pname, owner))
                        ok = False
                        break
                    if base not in SCALARS or nullable:
                        diags.append(diag("AN1304", "unsupported path parameter type: " + ptype + " (" + pname + ")", owner))
                        ok = False
                        break
                elif kind == "query" or kind == "header":
                    if source_name == "":
                        diags.append(diag("AN1302", "empty binding name: " + pname, owner))
                        ok = False
                        break
                    if base not in SCALARS:
                        diags.append(diag("AN1304", "unsupported " + kind + " parameter type: " + ptype + " (" + pname + ")", owner))
                        ok = False
                        break
                    if nullable and base != "String":
                        diags.append(diag("AN1304", "optional " + kind + " only supports String: " + ptype, owner))
                        ok = False
                        break
                else:
                    if base == "String" or base == "Bytes":
                        if nullable:
                            diags.append(diag("AN1304", "@Body cannot be optional: " + ptype, owner))
                            ok = False
                            break
                    else:
                        full_body = ptype[:-1] if nullable else ptype
                        resolved = full_body if full_body in by_full else None
                        if resolved is None:
                            for candidate in by_full:
                                if simple(candidate) == simple(full_body):
                                    resolved = candidate
                                    break
                        if resolved is None or resolved not in body_types:
                            diags.append(diag("AN1305", "@Body type has no @Serializable codec: " + ptype, owner))
                            ok = False
                            break
                        base = simple(resolved)
                bound.append({"name": pname, "type": ptype, "base": base, "nullable": nullable,
                              "kind": kind, "source": source_name})
            if not ok:
                continue
            route_plans.append({"httpMethod": route["httpMethod"], "path": route["path"],
                                "method": route["method"], "params": bound})
        if route_plans:
            plans[owner] = {"simple": sym.get("simpleName"), "routes": route_plans}

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0

    if not plans:
        write_diags(out, diags)
        return 0

    package = by_full[next(iter(plans))].get("package", "") or "app.http"
    lines = [
        "// generated by http_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.net.http",
        "import xdk.net.uri",
        "import xdk.codec",
        "import xdk.errors",
        "import xdk.text",
        "import xdk.math",
        "",
        "static Bool httpGenPathMatches(String template, String path) {",
        "    List<String> left = template.split(\"/\")",
        "    List<String> right = path.split(\"/\")",
        "    if left.length() != right.length() { return false }",
        "    Int index = 0",
        "    while index < left.length() {",
        "        String segment = left.get(index)",
        "        if segment.startsWith(\"{\") {",
        "            if !segment.endsWith(\"}\") { return false }",
        "        } else if segment != right.get(index) {",
        "            return false",
        "        }",
        "        index = index + 1",
        "    }",
        "    return true",
        "}",
        "",
        "static String? httpGenPathValue(String template, String path, String name) {",
        "    List<String> left = template.split(\"/\")",
        "    List<String> right = path.split(\"/\")",
        "    if left.length() != right.length() { return null }",
        "    String marker = \"{\" + name + \"}\"",
        "    Int index = 0",
        "    while index < left.length() {",
        "        if left.get(index) == marker { return right.get(index) }",
        "        index = index + 1",
        "    }",
        "    return null",
        "}",
        "",
        "static HttpResponse httpGenBadRequest(String message) {",
        "    HttpResponse response = HttpResponse.of(400)",
        "    return response.withBody(HttpBody.fromText(message))",
        "}",
        "",
        "static Result<Long, Error> httpGenParseLong(String text) {",
        "    if text == \"\" { return Err(new BasicError(ErrorKind.InvalidArgument, \"invalid long\")) }",
        "    Int index = 0",
        "    Bool negative = false",
        "    if text.substring(0, 1) == \"-\" { negative = true; index = 1 }",
        "    if index >= text.length() { return Err(new BasicError(ErrorKind.InvalidArgument, \"invalid long\")) }",
        "    Long value = 0",
        "    String digits = \"0123456789\"",
        "    while index < text.length() {",
        "        Int digit = digits.indexOf(text.substring(index, 1))",
        "        if digit < 0 { return Err(new BasicError(ErrorKind.InvalidArgument, \"invalid long\")) }",
        "        value = value * 10 + digit",
        "        index = index + 1",
        "    }",
        "    if negative { value = -value }",
        "    return Ok(value)",
        "}",
        "",
    ]

    for owner in sorted(plans):
        plan = plans[owner]
        simple_name = plan["simple"]
        router = simple_name + "Router"
        lines.append("class " + router + " {")
        lines.append("    final " + simple_name + " _handler")
        lines.append("    " + router + "(" + simple_name + " handler) {")
        lines.append("        if handler == null { throw \"" + router + ": null handler\" }")
        lines.append("        self._handler = handler")
        lines.append("    }")
        lines.append("")
        lines.append("    Bool matches(HttpMethod method, String path) {")
        for route in plan["routes"]:
            lines.append("        if method == HttpMethod." + route["httpMethod"] + " && httpGenPathMatches(" + json.dumps(route["path"]) + ", path) { return true }")
        lines.append("        return false")
        lines.append("    }")
        lines.append("")
        lines.append("    HttpResponse dispatch(HttpRequest request) {")
        lines.append("        if request == null { throw \"" + router + ".dispatch: null request\" }")
        lines.append("        HttpMethod method = request.method()")
        lines.append("        String path = request.uri().path()")
        lines.append("        Bool pathMatched = false")
        lines.append("        String allow = \"\"")
        for idx, route in enumerate(plan["routes"]):
            path_lit = json.dumps(route["path"])
            lines.append("        if httpGenPathMatches(" + path_lit + ", path) {")
            lines.append("            pathMatched = true")
            lines.append("            if allow != \"\" { allow = allow + \",\" }")
            lines.append("            allow = allow + \"" + route["httpMethod"].upper() + "\"")
            lines.append("            if method == HttpMethod." + route["httpMethod"] + " {")
            artifacts = []
            for pidx, param in enumerate(route["params"]):
                var = "arg" + str(idx) + "_" + str(pidx)
                raw = "raw" + str(idx) + "_" + str(pidx)
                if param["kind"] == "path":
                    lines.append("                String? " + raw + " = httpGenPathValue(" + path_lit + ", path, " + json.dumps(param["source"]) + ")")
                    lines.append("                if " + raw + " == null { return httpGenBadRequest(\"missing path: " + param["source"] + "\") }")
                    lines.append("                String " + var + "Raw = " + raw + " as String")
                elif param["kind"] == "query":
                    lines.append("                String? " + raw + " = request.uri().query().getOrNull(" + json.dumps(param["source"]) + ")")
                    if param["nullable"]:
                        lines.append("                String? " + var + " = " + raw)
                        artifacts.append((var, param))
                        continue
                    lines.append("                if " + raw + " == null { return httpGenBadRequest(\"missing query: " + param["source"] + "\") }")
                    lines.append("                String " + var + "Raw = " + raw + " as String")
                elif param["kind"] == "header":
                    lines.append("                String? " + raw + " = request.headers().getOrNull(" + json.dumps(param["source"]) + ")")
                    if param["nullable"]:
                        lines.append("                String? " + var + " = " + raw)
                        artifacts.append((var, param))
                        continue
                    lines.append("                if " + raw + " == null { return httpGenBadRequest(\"missing header: " + param["source"] + "\") }")
                    lines.append("                String " + var + "Raw = " + raw + " as String")
                else:
                    if param["base"] == "String":
                        lines.append("                Result<String, Error> " + raw + "Result = request.body().readText(maxLongValue())")
                        lines.append("                if " + raw + "Result.isErr() { return httpGenBadRequest(\"body read failed\") }")
                        lines.append("                String " + var + " = " + raw + "Result.value()")
                        artifacts.append((var, param))
                        continue
                    elif param["base"] == "Bytes":
                        lines.append("                Result<Bytes, Error> " + raw + "Result = request.body().readAll(maxLongValue())")
                        lines.append("                if " + raw + "Result.isErr() { return httpGenBadRequest(\"body read failed\") }")
                        lines.append("                Bytes " + var + " = " + raw + "Result.value()")
                        artifacts.append((var, param))
                        continue
                    else:
                        lines.append("                Result<String, Error> " + raw + "Text = request.body().readText(maxLongValue())")
                        lines.append("                if " + raw + "Text.isErr() { return httpGenBadRequest(\"body read failed\") }")
                        lines.append("                Result<JsonValue, Error> " + raw + "Json = Json.parse(" + raw + "Text.value())")
                        lines.append("                if " + raw + "Json.isErr() { return httpGenBadRequest(\"invalid body json\") }")
                        lines.append("                Result<" + param["base"] + ", Error> " + raw + "Value = " + param["base"] + "FromJson(" + raw + "Json.value())")
                        lines.append("                if " + raw + "Value.isErr() { return httpGenBadRequest(\"invalid body: " + param["name"] + "\") }")
                        lines.append("                " + param["base"] + " " + var + " = " + raw + "Value.value()")
                        artifacts.append((var, param))
                        continue
                if param["base"] == "String":
                    lines.append("                String " + var + " = " + var + "Raw")
                elif param["base"] == "Int":
                    lines.append("                Result<Int, Error> " + var + "Parsed = parseInt(" + var + "Raw)")
                    lines.append("                if " + var + "Parsed.isErr() { return httpGenBadRequest(\"invalid " + param["kind"] + ": " + param["source"] + "\") }")
                    lines.append("                Int " + var + " = " + var + "Parsed.value()")
                else:
                    lines.append("                Result<Long, Error> " + var + "Parsed = httpGenParseLong(" + var + "Raw)")
                    lines.append("                if " + var + "Parsed.isErr() { return httpGenBadRequest(\"invalid " + param["kind"] + ": " + param["source"] + "\") }")
                    lines.append("                Long " + var + " = " + var + "Parsed.value()")
                artifacts.append((var, param))
            args_text = ", ".join("arg" + str(idx) + "_" + str(i) for i in range(len(route["params"])))
            lines.append("                HttpResponse response = self._handler." + route["method"] + "(" + args_text + ")")
            lines.append("                return response")
            lines.append("            }")
            lines.append("        }")
        lines.append("        if pathMatched {")
        lines.append("            HttpResponse response = HttpResponse.of(405)")
        lines.append("            return response.withHeader(\"Allow\", allow)")
        lines.append("        }")
        lines.append("        return HttpResponse.of(404)")
        lines.append("    }")
        lines.append("}")
        lines.append("")

    (out / "HttpGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    if diags:
        write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
