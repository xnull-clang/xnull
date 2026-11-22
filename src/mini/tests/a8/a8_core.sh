#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
for name in data value copy generic_box package_adoption; do
    src="$HERE/$name.x"
    exp="$HERE/$name.out"
    "$XNULL" --bootstrap --engine=mini run "$src" >"$TMP"
    diff -u "$exp" "$TMP"
done
"$HERE/a8_negative.sh"
"$ROOT/src/mini/bin/mini" --ast "$HERE/data.x" >"$TMP.ast"
grep -q 'Generated: A8' "$TMP.ast"
rm -f "$TMP.ast"
echo "a8_core: PASS"
