#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini build "$HERE/generic_lambda2.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/generic_lambda2.out" "$TMP/run.out"

cat >"$TMP/negative.x" <<'X'
package app.genericlambda2negative
static Int main() {
    Int value = (Int item) -> { return item }
    return value
}
X
if "$XNULL" --bootstrap --engine=mini build "$TMP/negative.x" -o "$TMP/negative" >"$TMP/negative.log" 2>&1; then
    echo "generic_lambda2: negative unexpectedly compiled" >&2
    exit 1
fi
grep -q "lambda is missing a function type context" "$TMP/negative.log"
echo "generic_lambda2: PASS"
