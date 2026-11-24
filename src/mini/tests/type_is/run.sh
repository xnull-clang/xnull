#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.run.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

"$XNULL" --bootstrap --engine=mini build "$HERE/type_is.x" -o "$TMP/type_is" >"$TMP/build.log" 2>&1
"$TMP/type_is" >"$TMP/out"
diff -u "$HERE/type_is.out" "$TMP/out"

cat >"$TMP/unknown.x" <<'X'
package type_is_negative
protocol P { Int x(); }
class A implements P { Int x() { return 1 } }
static Int main() {
    P a = new A()
    print(a is Nope)
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini build "$TMP/unknown.x" -o "$TMP/unknown" >"$TMP/unknown.log" 2>&1; then
    echo "type_is: unknown type accepted" >&2
    exit 1
fi
grep -q 'unknown type in is: Nope' "$TMP/unknown.log"

cat >"$TMP/unit.x" <<'X'
package type_is_negative
protocol P { Int x(); }
class A implements P { Int x() { return 1 } }
static Int main() {
    P a = new A()
    print(a is Unit)
    return 0
}
X
if "$XNULL" --bootstrap --engine=mini build "$TMP/unit.x" -o "$TMP/unit" >"$TMP/unit.log" 2>&1; then
    echo "type_is: Unit target accepted" >&2
    exit 1
fi
grep -q 'is does not support target type: Unit' "$TMP/unit.log"

echo "type_is: PASS"
