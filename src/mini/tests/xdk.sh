#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_errors.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'errors ok\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_meta.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '3.4.0\n0.1.0\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=auto run "$HERE/xdk_errors.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'errors ok\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_runtime.x" > "$TMP" 2>"$TMP.rt.err" || {
    cat "$TMP.err" "$TMP.rt.err" >&2; exit 1
}
printf 'true\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"
grep -q '^runtime ok$' "$TMP.rt.err"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_text.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf '007\nabab\ntrue\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

"$XNULL" --bootstrap --engine=mini run "$HERE/xdk_sys.x" > "$TMP" 2>"$TMP.err" || {
    cat "$TMP.err" >&2; exit 1
}
printf 'true\nfalse\n' > "$TMP.exp"
diff -u "$TMP.exp" "$TMP"

echo "mini xdk: PASS"
