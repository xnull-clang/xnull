#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/builder.x" >"$TMP"
diff -u "$HERE/builder.out" "$TMP"
"$HERE/builder_negative.sh"
echo "a8_builder: PASS"
