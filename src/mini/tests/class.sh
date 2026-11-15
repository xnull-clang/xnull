#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini run "$HERE/class_basic.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2
    exit 1
}
diff -u "$HERE/class_basic.out" "$TMP"

"$XNULL" --bootstrap --engine=auto run "$HERE/class_basic.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2
    exit 1
}
diff -u "$HERE/class_basic.out" "$TMP"

echo "mini class: PASS"
