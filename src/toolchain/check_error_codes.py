#!/usr/bin/env python3
"""Validate the W6 diagnostic error-code registry.

The registry is the source of truth for diagnostic code ownership and meaning.
This checker enforces:

  * the registry header and code format;
  * one row per code (duplicate codes are RED);
  * namespace prefix matches the namespace column;
  * every diagnostic code emitted by a scanned source is registered.

Usage:
  python3 src/toolchain/check_error_codes.py
  python3 src/toolchain/check_error_codes.py --registry FILE --source FILE [...]

Exit: 0 = PASS, 1 = FAIL.
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REGISTRY = ROOT / "docs/design/t0/appendices/error-codes.tsv"
DEFAULT_SOURCES = [
    ROOT / "src/mini/main.x",
    ROOT / "src/cli/xnull",
]
HEADER = ["code", "namespace", "owner", "severity", "description", "status"]
CODE_RE = re.compile(r"\b([A-Z]{2,6}-\d{3})\b")
STATUSES = {"active", "reserved"}


def fail(message):
    print("check_error_codes: " + message, file=sys.stderr)
    return 1


def read_registry(path):
    rows = []
    with path.open(encoding="utf-8") as handle:
        header = handle.readline().rstrip("\n").split("\t")
        if header != HEADER:
            raise SystemExit(
                "check_error_codes: %s header mismatch\nexpected: %s\ngot:      %s"
                % (path, "\t".join(HEADER), "\t".join(header))
            )
        for number, line in enumerate(handle, 2):
            line = line.rstrip("\n")
            if not line:
                continue
            fields = line.split("\t")
            if len(fields) != len(HEADER):
                raise SystemExit(
                    "check_error_codes: %s:%d has %d fields, expected %d"
                    % (path, number, len(fields), len(HEADER))
                )
            rows.append((dict(zip(HEADER, fields)), number))
    return rows


def check_registry(rows):
    seen = {}
    for row, number in rows:
        code = row["code"]
        if not CODE_RE.fullmatch(code):
            return fail("%s:%d invalid code format: %s" % (path, number, code))
        if code in seen:
            return fail(
                "%s:%d duplicate error code: %s (first at line %d)"
                % (path, number, code, seen[code])
            )
        seen[code] = number
        namespace = row["namespace"]
        if not code.startswith(namespace.upper() + "-"):
            return fail(
                "%s:%d code %s does not match namespace %s"
                % (path, number, code, namespace)
            )
        if row["status"] not in STATUSES:
            return fail("%s:%d invalid status: %s" % (path, number, row["status"]))
        if not row["owner"]:
            return fail("%s:%d empty owner" % (path, number))
        if not row["description"]:
            return fail("%s:%d empty description" % (path, number))
    return seen


def check_sources(sources, registered):
    rc = 0
    for source in sources:
        if not source.is_file():
            return fail("missing source: %s" % source)
        text = source.read_text(encoding="utf-8", errors="replace")
        for match in CODE_RE.finditer(text):
            code = match.group(1)
            if code not in registered:
                line = text.count("\n", 0, match.start()) + 1
                print(
                    "check_error_codes: %s:%d unregistered error code: %s"
                    % (source, line, code),
                    file=sys.stderr,
                )
                rc = 1
    return rc


def main(argv):
    global path
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", default=str(DEFAULT_REGISTRY))
    parser.add_argument("--source", action="append", default=None)
    args = parser.parse_args(argv)

    path = Path(args.registry)
    if not path.is_file():
        return fail("missing registry: %s" % path)
    sources = [Path(item) for item in args.source] if args.source else DEFAULT_SOURCES

    rows = read_registry(path)
    registered = check_registry(rows)
    if isinstance(registered, int):
        return registered

    rc = check_sources(sources, registered)
    if rc != 0:
        return rc
    print(
        "check_error_codes: PASS (%d codes, %d sources)"
        % (len(registered), len(sources))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
