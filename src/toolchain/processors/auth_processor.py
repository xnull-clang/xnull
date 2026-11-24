#!/usr/bin/env python3
"""M16.2: generate explicit authorization wrappers from auth annotations."""
import argparse
import json
import sys
from pathlib import Path

AUTH = "xdk.auth.Auth"
ALLOW_ANONYMOUS = "xdk.auth.AllowAnonymous"
REQUIRE_ROLE = "xdk.auth.RequireRole"
REQUIRE_PERMISSION = "xdk.auth.RequirePermission"
REQUIRE_CLAIM = "xdk.auth.RequireClaim"
AUTH_ANNOTATIONS = {AUTH, ALLOW_ANONYMOUS, REQUIRE_ROLE, REQUIRE_PERMISSION, REQUIRE_CLAIM}


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


def order_key(use):
    return (use.get("line", 1), use.get("col", 1), use.get("repeatIndex", 0))


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

    class_auth = {}
    method_uses = {}
    diags = []
    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        if name not in AUTH_ANNOTATIONS:
            continue
        target = use.get("target")
        target_name = use.get("targetName", "")
        line = use.get("line", 1)
        col = use.get("col", 1)
        if target == "Type":
            if name == ALLOW_ANONYMOUS:
                diags.append(diag("AN2706", "@AllowAnonymous is not allowed on a type", target_name, line, col))
            elif name in (REQUIRE_ROLE, REQUIRE_PERMISSION, REQUIRE_CLAIM):
                diags.append(diag("AN2707", "@" + simple(name) + " is not allowed on a type", target_name, line, col))
            elif name == AUTH:
                class_auth[target_name] = use
            continue
        if target != "Method":
            diags.append(diag("AN2701", "@" + simple(name) + " must target a method", target_name, line, col))
            continue
        method_uses.setdefault(target_name, []).append(use)

    plans = []
    for target_name in sorted(method_uses):
        uses_for_method = sorted(method_uses[target_name], key=order_key)
        owner, method_name, types = split_signature(target_name)
        sym = symbols.get(owner)
        if not sym or sym.get("kind") != "Class":
            diags.append(diag("AN2703", "auth method owner is not a class: " + target_name, target_name))
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
            diags.append(diag("AN2703", "auth method not found: " + target_name, target_name))
            continue
        if method.get("static"):
            diags.append(diag("AN2703", "auth method must be an instance method: " + target_name, target_name))
            continue
        success = parse_result(method.get("return", ""))
        if success is None:
            diags.append(diag("AN2703", "auth method must return Result<T, Error>: " + target_name, target_name))
            continue
        allow = any(u.get("resolvedName") == ALLOW_ANONYMOUS for u in uses_for_method)
        method_auth = [u for u in uses_for_method if u.get("resolvedName") == AUTH]
        requires = [u for u in uses_for_method if u.get("resolvedName") in (REQUIRE_ROLE, REQUIRE_PERMISSION, REQUIRE_CLAIM)]
        if allow and (method_auth or requires):
            diags.append(diag("AN2704", "@AllowAnonymous conflicts with auth requirements: " + target_name, target_name))
            continue
        if allow:
            continue
        scheme = ""
        if method_auth:
            scheme = text_arg(method_auth[0], 0, "").strip()
        elif owner in class_auth:
            scheme = text_arg(class_auth[owner], 0, "").strip()
        roles = []
        permissions = []
        claims = []
        for req in requires:
            name = req.get("resolvedName")
            value = text_arg(req, 0, "")
            if name == REQUIRE_ROLE:
                if value.strip() == "":
                    diags.append(diag("AN2702", "empty role", target_name, req.get("line", 1), req.get("col", 1)))
                elif value.strip() in roles:
                    diags.append(diag("AN2705", "duplicate role: " + value, target_name,
                                      req.get("line", 1), req.get("col", 1), "Warning"))
                else:
                    roles.append(value.strip())
            elif name == REQUIRE_PERMISSION:
                if value.strip() == "":
                    diags.append(diag("AN2702", "empty permission", target_name, req.get("line", 1), req.get("col", 1)))
                elif value.strip() in permissions:
                    diags.append(diag("AN2705", "duplicate permission: " + value, target_name,
                                      req.get("line", 1), req.get("col", 1), "Warning"))
                else:
                    permissions.append(value.strip())
            else:
                claim_value = text_arg(req, 1, "")
                if value.strip() == "" or claim_value == "":
                    diags.append(diag("AN2702", "empty claim name or value", target_name,
                                      req.get("line", 1), req.get("col", 1)))
                else:
                    duplicate = False
                    for existing in claims:
                        if existing[0] == value.strip() and existing[1] == claim_value:
                            duplicate = True
                    if duplicate:
                        diags.append(diag("AN2705", "duplicate claim: " + value, target_name,
                                          req.get("line", 1), req.get("col", 1), "Warning"))
                    else:
                        claims.append((value.strip(), claim_value))
        type_name = sym.get("simpleName") or simple(owner)
        plans.append({"sym": sym, "method": method, "owner": owner, "name": method_name,
                      "type": type_name, "success": success, "scheme": scheme,
                      "roles": roles, "permissions": permissions, "claims": claims,
                      "target": target_name})

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0
    if not plans:
        write_diags(out, diags)
        return 0

    package = plans[0]["sym"].get("package", "") or "app.auth"
    lines = [
        "// generated by auth_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.auth",
        "import xdk.errors",
        "",
    ]
    for plan in sorted(plans, key=lambda p: (p["owner"], p["name"])):
        method = plan["method"]
        params = method.get("params", [])
        param_list = ", ".join(p.get("type", "") + " " + p.get("name", "") for p in params)
        call_args = ", ".join(p.get("name", "") for p in params)
        wrapper = plan["type"] + "_" + plan["name"] + "Authorized"
        signature = ("Result<" + plan["success"] + ", Error> " + wrapper + "(" + plan["type"] +
                     " target, Principal principal")
        if param_list:
            signature += ", " + param_list
        signature += ")"
        lines.append(signature + " {")
        lines.append('    if target == null { throw "' + wrapper + ': null target" }')
        lines.append('    if principal == null || !principal.isAuthenticated() {')
        lines.append('        return Err(new BasicError(ErrorKind.PermissionDenied, "authentication required"))')
        lines.append("    }")
        if plan["scheme"] != "":
            lines.append('    if authSchemeName(principal.scheme()).toLower() != ' +
                         json.dumps(plan["scheme"].lower()) + ' {')
            lines.append('        return Err(new BasicError(ErrorKind.PermissionDenied, ' +
                         json.dumps("authentication scheme required: " + plan["scheme"]) + '))')
            lines.append("    }")
        for role in plan["roles"]:
            lines.append('    if !principal.hasRole(' + json.dumps(role) + ') {')
            lines.append('        return Err(new BasicError(ErrorKind.PermissionDenied, ' +
                         json.dumps("missing role: " + role) + '))')
            lines.append("    }")
        for permission in plan["permissions"]:
            lines.append('    if !principal.hasPermission(' + json.dumps(permission) + ') {')
            lines.append('        return Err(new BasicError(ErrorKind.PermissionDenied, ' +
                         json.dumps("missing permission: " + permission) + '))')
            lines.append("    }")
        for claim_name, claim_value in plan["claims"]:
            lines.append('    String? claim' + str(plan["claims"].index((claim_name, claim_value))) +
                         ' = principal.claimOrNull(' + json.dumps(claim_name) + ')')
            lines.append('    if claim' + str(plan["claims"].index((claim_name, claim_value))) +
                         ' == null {')
            lines.append('        return Err(new BasicError(ErrorKind.PermissionDenied, ' +
                         json.dumps("missing claim: " + claim_name) + '))')
            lines.append("    }")
            lines.append('    String value' + str(plan["claims"].index((claim_name, claim_value))) +
                         ' = claim' + str(plan["claims"].index((claim_name, claim_value))) + ' as String')
            lines.append('    if value' + str(plan["claims"].index((claim_name, claim_value))) +
                         ' != ' + json.dumps(claim_value) + ' {')
            lines.append('        return Err(new BasicError(ErrorKind.PermissionDenied, ' +
                         json.dumps("missing claim: " + claim_name) + '))')
            lines.append("    }")
        lines.append("    return target." + plan["name"] + "(" + call_args + ")")
        lines.append("}")
        lines.append("")

    (out / "AuthGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
