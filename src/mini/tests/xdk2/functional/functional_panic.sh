#!/bin/sh
# Null function/list arguments must not silently succeed.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/mapnull.x" <<'X'
import xdk.functional
static Int main() {
    List<Int> items = [1]
    Seq<Int> seq = new Seq<Int>(items)
    Seq<Int> bad = seq.map(null)
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP/mapnull.x" >"$TMP/out" 2>"$TMP/err"; then
    echo "functional_panic: Seq.map(null) unexpectedly passed" >&2
    exit 1
fi
cat > "$TMP/lazynull.x" <<'X'
import xdk.functional
static Int main() {
    Lazy<Int> bad = new Lazy<Int>(null)
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini run "$TMP/lazynull.x" >"$TMP/out2" 2>"$TMP/err2"; then
    echo "functional_panic: Lazy(null) unexpectedly passed" >&2
    exit 1
fi
echo "functional_panic: PASS"
