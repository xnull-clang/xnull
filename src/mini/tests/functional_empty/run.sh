#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
for src in "$HERE"/*.x; do
    exp=${src%.x}.out
    "$XNULL" --bootstrap --engine=mini run "$src" >"$TMP"
    diff -u "$exp" "$TMP"
done
cat > "$TMP.x" <<'X'
import xdk.functional
static Int main() {
    Seq.empty()
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP.x" >"$TMP" 2>"$TMP.err"; then
    echo "functional_empty: uninferrable Seq.empty() compiled" >&2
    exit 1
fi
grep -q '__gm_Seq_empty' "$TMP.err"
echo "functional_empty: PASS"
