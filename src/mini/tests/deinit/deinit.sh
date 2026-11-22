#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

for src in "$HERE"/deinit_*.x; do
    exp=${src%.x}.out
    "$XNULL" --bootstrap --engine=mini run "$src" >"$TMP"
    diff -u "$exp" "$TMP"
done
"$HERE/deinit_negative.sh"
echo "deinit: PASS"
