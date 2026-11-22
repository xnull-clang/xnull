#!/bin/sh
# XDK 2.x gate: every .x under xdk2/ has a matching .out.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP" "$TMP.err"' EXIT


python3 - "$ROOT/src/xdk/xdk2-packages.tsv" "$ROOT" <<'PY'
import csv, os, sys
path, root = sys.argv[1], sys.argv[2]
rows = list(csv.DictReader(open(path, encoding="utf-8"), delimiter="\t"))
assert len(rows) == 75, len(rows)
assert sum(int(r["types"]) for r in rows) == 698
for r in rows:
    assert r["package"].startswith("xdk.")
    assert r["path"].startswith("src/xdk/")
    assert r["status"] in {"1.x", "design"}
    if r["status"] == "1.x":
        assert os.path.isfile(os.path.join(root, r["path"])), r["path"]
for d in ("annotations", "execution"):
    assert os.path.isdir(os.path.join(root, "src/xdk", d)), d
print("xdk2 packages: 75 packages / 698 types")
PY

count=0
for src in $(find "$HERE/xdk2" -name '*.x' | sort); do
    exp=${src%.x}.out
    [ -f "$exp" ] || { echo "xdk2: missing expected output for $src" >&2; exit 1; }
    "$XNULL" --bootstrap --engine=mini run "$src" >"$TMP" 2>"$TMP.err" || {
        cat "$TMP.err" >&2; exit 1
    }
    diff -u "$exp" "$TMP"
    count=$((count + 1))
done

[ "$count" -gt 0 ] || { echo "xdk2: no scenarios" >&2; exit 1; }
echo "xdk2: PASS ($count scenario(s))"
