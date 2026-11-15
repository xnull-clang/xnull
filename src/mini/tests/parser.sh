#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
MINI="$ROOT/src/mini/mini"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

"$MINI" --ast "$HERE/lex_hello.x" > "$TMP"
diff -u "$HERE/ast_hello.out" "$TMP"
"$MINI" --ast "$HERE/ast_local.x" > "$TMP"
diff -u "$HERE/ast_local.out" "$TMP"

printf 'static Int main( {\n' > "$TMP.bad.x"
if "$MINI" --ast "$TMP.bad.x" > "$TMP" 2>&1; then
    echo "expected parser failure" >&2
    exit 1
fi
grep -q 'expected\|unexpected' "$TMP"

echo "mini parser: PASS"
