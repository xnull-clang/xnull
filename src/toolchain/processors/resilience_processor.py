#!/usr/bin/env python3
"""M8.2: generate explicit resilience wrapper functions."""
import argparse
import json
import sys
from pathlib import Path

POLICIES = {
    "xdk.resilience.Retryable": "retry",
    "xdk.resilience.TimeoutPolicy": "timeout",
    "xdk.resilience.CircuitBreakerPolicy": "circuit",
    "xdk.resilience.RateLimit": "rate",
}


def diag(code, message, target="", severity="Error"):
    return {"code": code, "severity": severity, "message": message,
            "line": 1, "col": 1, "target": target}


def write_diags(out, diags):
    out.mkdir(parents=True, exist_ok=True)
    ordered = sorted(diags, key=lambda d: (d["code"], d["target"], d["message"]))
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


def int_arg(use, index, default):
    try:
        return int(text_arg(use, index, str(default)))
    except ValueError:
        return default


def supported_type(ftype):
    text = ftype.strip()
    if "->" in text or "(" in text or text == "Any" or text == "Object":
        return False
    return True


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

    diags = []
    plans = {}
    for use in uses:
        name = use.get("resolvedName") or use.get("name")
        target = use.get("target")
        target_name = use.get("targetName", "")
        if name not in POLICIES:
            continue
        if target != "Method":
            diags.append(diag("AN1904", name + " must target a method: " + target_name, target_name))
            continue
        owner, method, types = split_signature(target_name)
        if not method:
            diags.append(diag("AN1904", name + " has invalid method target", target_name))
            continue
        plans.setdefault(target_name, []).append({"policy": POLICIES[name], "use": use,
                                                   "owner": owner, "method": method, "types": types})

    generated = []
    for target_name in sorted(plans):
        entries = plans[target_name]
        if len(entries) > 1:
            diags.append(diag("AN1902", "only one resilience policy per method: " + target_name, target_name))
            continue
        entry = entries[0]
        owner = entry["owner"]
        sym = symbols.get(owner)
        if not sym or sym.get("kind") != "Class":
            diags.append(diag("AN1904", "target owner must be a class: " + owner, target_name))
            continue
        method = None
        for candidate in sym.get("methods", []):
            if candidate.get("name") != entry["method"]:
                continue
            cparams = [p.get("type", "") for p in candidate.get("params", [])]
            if [simple(t) for t in cparams] == [simple(t) for t in entry["types"]]:
                method = candidate
                break
        if method is None:
            diags.append(diag("AN1904", "resilience method not found: " + target_name, target_name))
            continue
        if method.get("static"):
            diags.append(diag("AN1903", "static methods are not supported: " + target_name, target_name))
            continue
        success = parse_result(method.get("return", ""))
        if success is None:
            diags.append(diag("AN1901", "method must return Result<T, Error>: " + target_name, target_name))
            continue
        params = method.get("params", [])
        bad = False
        for param in params:
            if not supported_type(param.get("type", "")):
                diags.append(diag("AN1903", "unsupported parameter type: " + target_name, target_name))
                bad = True
                break
        if not supported_type(success):
            diags.append(diag("AN1903", "unsupported result type: " + target_name, target_name))
            bad = True
        if bad:
            continue
        generated.append({"entry": entry, "sym": sym, "method": method, "success": success,
                          "target": target_name})

    if any(d["severity"] == "Error" for d in diags):
        write_diags(out, diags)
        return 0
    if not generated:
        write_diags(out, diags)
        return 0

    package = generated[0]["sym"].get("package", "") or "app.svc"
    lines = [
        "// generated by resilience_processor; DO NOT EDIT",
        "package " + package,
        "import xdk.resilience",
        "import xdk.errors",
        "",
    ]

    for plan in sorted(generated, key=lambda p: (p["sym"].get("fullName", ""), p["entry"]["method"])):
        entry = plan["entry"]
        type_name = plan["sym"].get("simpleName") or simple(entry["owner"])
        method = plan["method"]
        params = method.get("params", [])
        param_list = ", ".join(p.get("type", "") + " " + p.get("name", "") for p in params)
        call_args = ", ".join(p.get("name", "") for p in params)
        call = "target." + entry["method"] + "(" + call_args + ")"
        ret = method.get("return", "").strip()
        policy = entry["policy"]
        wrapper = type_name + "_" + entry["method"]
        signature_tail = "Context context"
        if policy == "circuit":
            signature_tail += ", CircuitBreaker breaker"
        elif policy == "rate":
            signature_tail += ", RateLimiter limiter"
        if param_list:
            signature_tail += ", " + param_list
        if policy == "retry":
            wrapper += "Retry"
        elif policy == "timeout":
            wrapper += "Timeout"
        elif policy == "circuit":
            wrapper += "Circuit"
        else:
            wrapper += "Rate"
        lines.append(ret + " " + wrapper + "(" + type_name + " target, " + signature_tail + ") {")
        lines.append('    if target == null || context == null { throw "' + wrapper + ': null argument" }')
        if policy == "retry":
            max_attempts = int_arg(entry["use"], 0, 3)
            initial = int_arg(entry["use"], 1, 100)
            lines.append("    RetryPolicy policy = new RetryPolicy()")
            lines.append("    policy = policy.withMaxAttempts(" + str(max_attempts) + ")")
            lines.append("    policy = policy.withInitialDelayMillis(" + str(initial) + ")")
            lines.append("    return Retry.execute(context, policy, () -> { return " + call + "; })")
        elif policy == "timeout":
            timeout = int_arg(entry["use"], 0, 1000)
            lines.append("    return Timeout.execute(context, " + str(timeout) + ", (Context inner) -> { return " + call + "; })")
        elif policy == "circuit":
            name = text_arg(entry["use"], 0, "")
            threshold = int_arg(entry["use"], 1, 5)
            lines.append("    // circuit=" + name + " threshold=" + str(threshold) + "; breaker supplied by caller")
            lines.append("    return breaker.execute(context, () -> { return " + call + "; })")
        else:
            name = text_arg(entry["use"], 0, "")
            permits = int_arg(entry["use"], 1, 1)
            per_millis = int_arg(entry["use"], 2, 1000)
            lines.append("    // rate=" + name + " permits=" + str(permits) + " perMillis=" + str(per_millis))
            lines.append("    Result<Unit, Error> acquired = limiter.acquire(context)")
            lines.append("    if acquired.isErr() { return Err(acquired.error()) }")
            lines.append("    return " + call)
        lines.append("}")
        lines.append("")

    (out / "ResilienceGenerated.x").write_text("\n".join(lines), encoding="utf-8")
    write_diags(out, diags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
