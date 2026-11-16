#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini run "$ROOT/src/examples/classes.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2
    exit 1
}
diff -u "$HERE/classes.out" "$TMP"

"$XNULL" --bootstrap --engine=legacy run "$ROOT/src/examples/classes.x" > "$TMP.legacy" 2>/dev/null
diff -u "$HERE/classes.out" "$TMP.legacy"

"$XNULL" --bootstrap --engine=mini run "$ROOT/src/examples/containers.x" > "$TMP.containers" 2>"$TMP.containers.err" || {
    cat "$TMP.containers.err" >&2; exit 1
}
"$XNULL" --bootstrap --engine=legacy run "$ROOT/src/examples/containers.x" > "$TMP.containers.legacy" 2>/dev/null
diff -u "$TMP.containers.legacy" "$TMP.containers"

echo "mini containers: PASS"
