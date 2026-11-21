#!/usr/bin/env python3
"""Generate src/ffi/api-manifest.tsv from capabilities + package designs.

No symbol is invented here: L1 symbols come from capabilities.tsv, and
stability comes from the package design header. Missing design/stability is a
hard error (RED), not a blank cell.
"""
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CAPS = os.path.join(ROOT, "src/ffi/capabilities.tsv")
DOCS = os.path.join(ROOT, "docs/design/t0")
OUT = os.path.join(ROOT, "src/ffi/api-manifest.tsv")

DOC_BY_PACKAGE = {
    "xdk.errors": "01-errors.md",
    "xdk.runtime": "02-runtime.md",
    "xdk.meta": "03-meta.md",
    "xdk.bytes": "04-bytes.md",
    "xdk.text": "05-text.md",
    "xdk.collections": "06-collections.md",
    "xdk.math": "07-math.md",
    "xdk.time": "08-time.md",
    "xdk.io": "09-io.md",
    "xdk.fs": "10-fs.md",
    "xdk.sys": "11-sys.md",
    "xdk.log": "14-log.md",
    "xdk.config": "15-config.md",
    "xdk.cli": "16-cli.md",
}


def stability(path):
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("| 稳定性 |"):
                value = line.split("|")[2].strip()
                if not value:
                    break
                return value.replace("`", "")
    raise SystemExit("missing stability: " + path)


def normalize_stability(raw):
    has_stable = "stable" in raw
    has_preview = "preview" in raw
    if has_stable and has_preview:
        return "stable/preview"
    if has_stable:
        return "stable"
    if has_preview:
        return "preview"
    raise SystemExit("unknown stability: " + raw)


def main():
    rows = []
    with open(CAPS, encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            package = row["package"]
            if package not in DOC_BY_PACKAGE:
                raise SystemExit("no design doc for " + package)
            symbols = [s for s in row["l1"].split(";") if s]
            if not symbols:
                raise SystemExit("no L1 symbols for " + package)
            design = os.path.join(DOCS, DOC_BY_PACKAGE[package])
            if not os.path.isfile(design):
                raise SystemExit("missing design: " + design)
            rows.append([
                package,
                ";".join(symbols),
                normalize_stability(stability(design)),
                row["owner"],
                row["x_scenario"],
                row["c_test"],
                "xdk.sh/ref.sh",
                "%s && %s" % (row["x_scenario"], row["c_test"]),
            ])
    header = ["package", "public_symbols", "stability", "owner",
              "scenario", "test", "gate", "evidence"]
    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("\t".join(header) + "\n")
        for row in rows:
            handle.write("\t".join(row) + "\n")
    print("api manifest: %d packages" % len(rows))


if __name__ == "__main__":
    main()
