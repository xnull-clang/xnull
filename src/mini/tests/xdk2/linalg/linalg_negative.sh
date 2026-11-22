#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/nullmatrix.x" <<'X'
import xdk.linalg
import xdk.tensor
static Int main() {
    Tensor t = Linalg.tensorFromMatrix(null)
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP/nullmatrix.x" >"$TMP/out" 2>"$TMP/err"; then
    echo "linalg_negative: tensorFromMatrix(null) accepted" >&2
    exit 1
fi
grep -q 'tensorFromMatrix: null matrix' "$TMP/err"
echo "linalg_negative: PASS"
