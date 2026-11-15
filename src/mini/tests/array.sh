#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini run "$HERE/array.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2
    exit 1
}
diff -u "$HERE/array.out" "$TMP"

echo "mini array: PASS"
