#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/generic_field.x" >"$TMP"
diff -u "$HERE/generic_field.out" "$TMP"
echo "generic_field: PASS"
