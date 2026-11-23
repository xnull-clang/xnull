#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini build "$HERE/generic_lambda.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/generic_lambda.out" "$TMP/run.out"

cat >"$TMP/negative.x" <<'X'
import xdk.errors
static Int main() {
    Int value = (Int item) -> {
        return Ok(item)
    }
    return value
}
X
if "$XNULL" --bootstrap --engine=mini build "$TMP/negative.x" -o "$TMP/negative" >"$TMP/negative.log" 2>&1; then
    echo "generic_lambda: negative unexpectedly compiled" >&2
    exit 1
fi
grep -q "Ok requires Result return type" "$TMP/negative.log"
echo "generic_lambda: PASS"
