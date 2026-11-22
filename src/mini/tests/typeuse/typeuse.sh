#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

for src in "$HERE"/typeuse_*.x; do
    exp=${src%.x}.out
    "$XNULL" --bootstrap --engine=mini run "$src" >"$TMP"
    diff -u "$exp" "$TMP"
done
"$ROOT/src/mini/bin/mini" --ast "$HERE/typeuse_registry.x" >"$TMP"
grep -q 'TypeUse' "$TMP"
grep -q 'AnnotationUse: TU' "$TMP"
"$HERE/typeuse_negative.sh"
echo "typeuse: PASS"
