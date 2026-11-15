#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
MINI="$ROOT/src/mini/mini"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

"$MINI" --check "$HERE/lex_hello.x" > "$TMP"
diff -u "$HERE/lex_hello.out" "$TMP"

printf 'static Int main() { "oops }\n' > "$TMP.x"
if "$MINI" --check "$TMP.x" > "$TMP" 2>&1; then
    echo "expected unterminated-string failure" >&2
    exit 1
fi
grep -q 'unterminated string' "$TMP"

: > "$TMP.empty"
if "$MINI" --check "$TMP.empty" > "$TMP" 2>&1; then
    echo "expected empty-input failure" >&2
    exit 1
fi

echo "mini lex: PASS"
