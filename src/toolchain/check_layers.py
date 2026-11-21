#!/usr/bin/env python3
"""Verify XDK layer ownership, symbol closure, and source mirrors.

Gates:
  G1 ownership    — every capability has one package owner and unique symbols.
  G2 closure      — every declared L1/L2 symbol and test/scenario path exists.
  G3 mirrors      — src/xdk, src/ffi, src/runtime match their xdk/ copies.

Violations can be suppressed only by src/toolchain/layer-allowlist.tsv.
Each allowlist row must carry a remove_batch. A 1.0.0 release requires an
empty allowlist.

Usage:
  python3 src/toolchain/check_layers.py [--json] [--release 0.9.0]
Exit: 0 = PASS, 1 = FAIL.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAPABILITIES = ROOT / "src/ffi/capabilities.tsv"
ALLOWLIST = ROOT / "src/toolchain/layer-allowlist.tsv"
XDK_SOURCE = ROOT / "src/xdk"
FFI_SOURCE = ROOT / "src/ffi"
RUNTIME_SOURCE = ROOT / "src/runtime"

CAP_HEADER = [
    "package", "capability", "owner", "l2", "l1",
    "c_test", "x_scenario", "parity", "status",
]
ALLOW_HEADER = [
    "kind", "symbol", "caller", "owner", "reason", "remove_batch",
]
ALLOWED_PACKAGES = {
    "xdk.errors", "xdk.runtime", "xdk.meta", "xdk.bytes", "xdk.text",
    "xdk.collections", "xdk.math", "xdk.time", "xdk.io", "xdk.fs",
    "xdk.sys", "xdk.log", "xdk.config", "xdk.cli",
}
ALLOWED_STATUS = {"verified", "partial", "blocked", "deferred"}

MIRRORS = [
    ("xdk/lib", XDK_SOURCE, ROOT / "xdk/lib/xdk"),
    ("xdk/ffi", FFI_SOURCE, ROOT / "xdk/ffi"),
    ("xdk/runtime", RUNTIME_SOURCE, ROOT / "xdk/runtime"),
]

EXCLUDED_PARTS = {"__pycache__", ".git", "bin", ".cache"}
EXCLUDED_SUFFIXES = {".o", ".a", ".dylib", ".so", ".dSYM", ".tmp", ".log"}
EXCLUDED_PREFIXES = ("test_", "libxnrt")


def read_tsv(path, expected_header):
    if not path.is_file():
        raise SystemExit("check_layers: missing %s" % path)
    rows = []
    with path.open(encoding="utf-8") as handle:
        header = handle.readline().rstrip("\n").split("\t")
        if header != expected_header:
            raise SystemExit(
                "check_layers: %s header mismatch\nexpected: %s\ngot:      %s"
                % (path, "\t".join(expected_header), "\t".join(header))
            )
        for lineno, line in enumerate(handle, 2):
            line = line.rstrip("\n")
            if not line:
                continue
            fields = line.split("\t")
            if len(fields) != len(expected_header):
                raise SystemExit(
                    "check_layers: %s:%d has %d fields, expected %d"
                    % (path, lineno, len(fields), len(expected_header))
                )
            row = dict(zip(expected_header, fields))
            row["_line"] = lineno
            rows.append(row)
    return rows


def split_symbols(value):
    if value.strip() in ("", "-"):
        return []
    return [item.strip() for item in value.split(";") if item.strip()]


def source_files(root, suffix):
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_PARTS]
        for name in files:
            if name.endswith(suffix):
                yield Path(dirpath) / name


def symbol_declared(symbol, files):
    pattern = re.compile(
        r"\b(?:class|enum|protocol|struct)\s+%s\b|"
        r"\b%s\s*(?:<[^>]*>)?\s*\("
        % (re.escape(symbol), re.escape(symbol))
    )
    for path in files:
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if pattern.search(text):
            return True
    return False


def primitive_declared(symbol, files):
    pattern = re.compile(r"\b%s\b" % re.escape(symbol))
    for path in files:
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if pattern.search(text):
            return True
    return False


def mirror_files(root):
    result = {}
    for path in source_files(root, ""):
        rel = path.relative_to(root)
        if any(part in EXCLUDED_PARTS for part in rel.parts):
            continue
        if path.name.startswith(EXCLUDED_PREFIXES):
            continue
        if path.suffix in EXCLUDED_SUFFIXES:
            continue
        try:
            result[str(rel)] = path.read_bytes()
        except OSError:
            pass
    return result


def add_violation(out, kind, symbol, caller, owner, detail):
    out.append({
        "kind": kind,
        "symbol": symbol,
        "caller": caller,
        "owner": owner,
        "detail": detail,
    })


def check_capabilities(rows, out):
    seen_capabilities = {}
    seen_symbols = {}
    xdk_files = list(source_files(XDK_SOURCE, ".x"))
    primitive_files = list(source_files(FFI_SOURCE, ".xfb")) + list(
        source_files(RUNTIME_SOURCE, ".c")) + list(source_files(RUNTIME_SOURCE, ".h"))

    for row in rows:
        package = row["package"]
        capability = row["capability"]
        owner = row["owner"]
        if package not in ALLOWED_PACKAGES:
            add_violation(out, "g1", package, package, owner,
                          "package is not one of the 14 T0 1.0 packages")
        if owner != package:
            add_violation(out, "g1", "%s.%s" % (package, capability), package, owner,
                          "owner must equal package")
        if not capability:
            add_violation(out, "g1", package, package, owner, "empty capability")
        if capability in seen_capabilities:
            add_violation(out, "g1", "%s.%s" % (package, capability), package, owner,
                          "duplicate capability (first at %s)"
                          % seen_capabilities[capability])
        else:
            seen_capabilities[capability] = "%s:%d" % (package, row["_line"])
        if row["status"] not in ALLOWED_STATUS:
            add_violation(out, "g1", "%s.%s" % (package, capability), package, owner,
                          "invalid status: %s" % row["status"])

        l1_symbols = split_symbols(row["l1"])
        if not l1_symbols:
            add_violation(out, "g1", package, package, owner, "no L1 symbol")
        for symbol in l1_symbols:
            key = (symbol, package)
            if symbol in seen_symbols and seen_symbols[symbol] != package:
                add_violation(out, "g1", "%s.%s" % (package, symbol), package, owner,
                              "symbol also owned by %s" % seen_symbols[symbol])
            else:
                seen_symbols[symbol] = package

        for symbol in l1_symbols:
            if not symbol_declared(symbol, xdk_files):
                add_violation(out, "g2", "%s.%s" % (package, symbol), package, owner,
                              "L1 symbol not declared in src/xdk")
        for symbol in split_symbols(row["l2"]):
            if not primitive_declared(symbol, primitive_files):
                add_violation(out, "g2", "%s.%s" % (package, symbol), package, owner,
                              "L2 primitive not found in src/ffi or src/runtime")
        for key in ("c_test", "x_scenario"):
            for rel in split_symbols(row[key]):
                if not (ROOT / rel).is_file():
                    add_violation(out, "g2", "%s.%s:%s" % (package, key, rel),
                                  package, owner, "missing %s" % key)


def check_mirrors(out):
    for name, source, target in MIRRORS:
        left = mirror_files(source)
        right = mirror_files(target)
        for rel in sorted(set(left) - set(right)):
            add_violation(out, "g3", "%s:%s" % (name, rel), name, name,
                          "missing in mirror")
        for rel in sorted(set(right) - set(left)):
            add_violation(out, "g3", "%s:%s" % (name, rel), name, name,
                          "extra in mirror")
        for rel in sorted(set(left) & set(right)):
            if left[rel] != right[rel]:
                add_violation(out, "g3", "%s:%s" % (name, rel), name, name,
                              "content differs")


def check_allowlist(entries, release, out):
    if release == "1.0.0" and entries:
        add_violation(out, "allowlist", "non-empty", "1.0.0", "toolchain",
                      "1.0.0 requires an empty allowlist")
    for row in entries:
        if not row["remove_batch"].strip():
            add_violation(out, "allowlist", row["symbol"], row["caller"],
                          row["owner"], "missing remove_batch")
        if row["kind"] not in {"g1", "g2", "g3"}:
            add_violation(out, "allowlist", row["symbol"], row["caller"],
                          row["owner"], "invalid kind: %s" % row["kind"])


def suppress(violations, entries):
    used = set()
    remaining = []
    for violation in violations:
        matched = False
        for index, entry in enumerate(entries):
            if entry["kind"] != violation["kind"]:
                continue
            if entry["symbol"] != violation["symbol"]:
                continue
            if entry["caller"] and entry["caller"] != violation["caller"]:
                continue
            if entry["owner"] and entry["owner"] != violation["owner"]:
                continue
            used.add(index)
            matched = True
            break
        if not matched:
            remaining.append(violation)
    return remaining, used


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--release", default="0.9.0")
    args = parser.parse_args(argv[1:])

    capabilities = read_tsv(CAPABILITIES, CAP_HEADER)
    allowlist = read_tsv(ALLOWLIST, ALLOW_HEADER)

    violations = []
    check_capabilities(capabilities, violations)
    check_mirrors(violations)
    check_allowlist(allowlist, args.release, violations)

    raw_counts = {"g1": 0, "g2": 0, "g3": 0, "allowlist": 0}
    for violation in violations:
        raw_counts[violation["kind"]] = raw_counts.get(violation["kind"], 0) + 1
    remaining, used = suppress(violations, allowlist)
    counts = {"g1": 0, "g2": 0, "g3": 0, "allowlist": 0}
    for violation in remaining:
        counts[violation["kind"]] = counts.get(violation["kind"], 0) + 1
    result = {
        "root": str(ROOT),
        "release": args.release,
        "status": "PASS" if not remaining else "FAIL",
        "raw_counts": raw_counts,
        "counts": counts,
        "allowlist": {
            "entries": len(allowlist),
            "used": len(used),
        },
        "violations": remaining,
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        for violation in remaining:
            print("%s %s [%s] %s: %s" % (
                violation["kind"], violation["symbol"],
                violation["owner"], violation["caller"], violation["detail"]))
        print("check_layers: %s (g1=%d g2=%d g3=%d allowlist=%d/%d; raw g1=%d g2=%d g3=%d)" % (
            result["status"], counts.get("g1", 0), counts.get("g2", 0),
            counts.get("g3", 0), len(used), len(allowlist),
            raw_counts.get("g1", 0), raw_counts.get("g2", 0), raw_counts.get("g3", 0)))
    return 0 if not remaining else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
