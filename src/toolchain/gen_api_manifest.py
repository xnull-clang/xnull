#!/usr/bin/env python3
"""Generate src/ffi/api-manifest.tsv, one row per public symbol.

L1 symbols come only from capabilities.tsv; signatures are found in src/xdk.
Missing symbol/signature/design/stability is a hard error (RED), not a blank.
"""
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CAPS = os.path.join(ROOT, "src/ffi/capabilities.tsv")
DOCS = os.path.join(ROOT, "docs/design/t0")
XDK = os.path.join(ROOT, "src/xdk")
OUT = os.path.join(ROOT, "src/ffi/api-manifest.tsv")

SYMBOL_EVIDENCE = {
    ("xdk.bytes", "ByteBuffer"): (
        "src/mini/tests/xdk_bytes_extra.x;src/mini/tests/xdk_bytes_strict.x",
        "src/runtime/test_std.c",
        "xdk.sh",
        "src/mini/tests/xdk_bytes_extra.x && src/mini/tests/xdk_bytes_strict.x && src/runtime/test_std.c",
    ),
    ("xdk.runtime", "dumpTasks"): (
        "src/mini/tests/ref/u2_task_dump.x",
        "src/runtime/test_rt.c",
        "ref.sh",
        "XNULL_CARRIERS=1 src/mini/tests/ref/u2_task_dump.x && src/runtime/test_rt.c",
    ),
}

DOC_BY_PACKAGE = {
    "xdk.errors": "01-errors.md", "xdk.runtime": "02-runtime.md",
    "xdk.meta": "03-meta.md", "xdk.bytes": "04-bytes.md",
    "xdk.text": "05-text.md", "xdk.collections": "06-collections.md",
    "xdk.math": "07-math.md", "xdk.time": "08-time.md",
    "xdk.io": "09-io.md", "xdk.fs": "10-fs.md", "xdk.sys": "11-sys.md",
    "xdk.log": "14-log.md", "xdk.config": "15-config.md", "xdk.cli": "16-cli.md",
}


def source_lines():
    for dirpath, dirs, files in os.walk(XDK):
        dirs[:] = sorted(d for d in dirs if d not in {"__pycache__"})
        for name in sorted(files):
            if name.endswith(".x"):
                path = os.path.join(dirpath, name)
                with open(path, encoding="utf-8") as handle:
                    for number, line in enumerate(handle, 1):
                        yield path, number, line.rstrip("\n")


LINES = list(source_lines())


def find_signature(symbol):
    type_re = re.compile(
        r"^\s*(?:class|enum|protocol|struct)\s+%s\b" % re.escape(symbol))
    func_re = re.compile(
        r"^\s*(?:static\s+)?(?:[A-Za-z_][\w.<>\[\]?, ]*\s+)?"
        r"%s\s*(?:<[^>]*>)?\s*\(" % re.escape(symbol))
    for path, number, line in LINES:
        if line.lstrip().startswith("//"):
            continue
        if type_re.match(line) or func_re.match(line):
            signature = line.strip()
            if signature.endswith("{"):
                signature = signature[:-1].rstrip()
            return signature, path, number
    return None, None, None


def stability(path):
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("| 稳定性 |"):
                raw = line.split("|")[2].strip().replace("`", "")
                stable = "stable" in raw
                preview = "preview" in raw
                if stable and preview:
                    return "stable/preview"
                if stable:
                    return "stable"
                if preview:
                    return "preview"
                break
    raise SystemExit("missing stability: " + path)


def main():
    rows = []
    with open(CAPS, encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            package = row["package"]
            if package not in DOC_BY_PACKAGE:
                raise SystemExit("no design doc for " + package)
            design = os.path.join(DOCS, DOC_BY_PACKAGE[package])
            if not os.path.isfile(design):
                raise SystemExit("missing design: " + design)
            stability_value = stability(design)
            for symbol in [s.strip() for s in row["l1"].split(";") if s.strip()]:
                signature, source, line = find_signature(symbol)
                if signature is None:
                    raise SystemExit("missing signature for %s.%s" % (package, symbol))
                scenario, test, gate, evidence = (
                    SYMBOL_EVIDENCE[(package, symbol)]
                    if (package, symbol) in SYMBOL_EVIDENCE
                    else (row["x_scenario"], row["c_test"], "xdk.sh/ref.sh",
                          "%s && %s" % (row["x_scenario"], row["c_test"]))
                )
                rows.append([
                    package, symbol, signature, stability_value,
                    row["owner"], scenario, test, gate, evidence,
                ])
    header = ["package", "symbol", "signature", "stability", "owner",
              "scenario", "test", "gate", "evidence"]
    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("\t".join(header) + "\n")
        for row in rows:
            handle.write("\t".join(row) + "\n")
    print("api manifest: %d symbols / %d packages" % (len(rows), len({r[0] for r in rows})))


if __name__ == "__main__":
    main()
