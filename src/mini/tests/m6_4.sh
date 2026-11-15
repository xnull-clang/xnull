#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini run "$HERE/m6_4.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2
    exit 1
}
diff -u "$HERE/m6_4.out" "$TMP"

"$XNULL" --bootstrap --engine=auto run "$HERE/m6_4.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2
    exit 1
}
diff -u "$HERE/m6_4.out" "$TMP"

echo "mini m6.4: PASS"
