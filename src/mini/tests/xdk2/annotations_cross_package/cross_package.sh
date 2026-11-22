#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/pkg"
cp "$HERE/fixture/pkg/a.x.txt" "$TMP/pkg/a.x"
cp "$HERE/fixture/pkg/b.x.txt" "$TMP/pkg/b.x"
cp "$HERE/fixture/main_b.x.txt" "$TMP/main_b.x"
cp "$HERE/fixture/main_both.x.txt" "$TMP/main_both.x"
cp "$HERE/fixture/main_ambig.x.txt" "$TMP/main_ambig.x"

"$XNULL" --bootstrap --engine=mini run "$TMP/main_b.x" >"$TMP/b.out" 2>"$TMP/b.err"
printf 'true\n' >"$TMP/b.expected"
diff -u "$TMP/b.expected" "$TMP/b.out"

"$XNULL" --bootstrap --engine=mini run "$TMP/main_both.x" >"$TMP/both.out" 2>"$TMP/both.err"
printf 'true\ntrue\n' >"$TMP/both.expected"
diff -u "$TMP/both.expected" "$TMP/both.out"

if "$XNULL" --bootstrap --engine=mini run "$TMP/main_ambig.x" >"$TMP/ambig.out" 2>"$TMP/ambig.err"; then
    echo "cross_package: ambiguous simple name compiled" >&2
    exit 1
fi
grep -q 'AN0001' "$TMP/ambig.err"
grep -q 'ambiguous annotation @Marker' "$TMP/ambig.err"
grep -q 'pkg.a' "$TMP/ambig.err"
grep -q 'pkg.b' "$TMP/ambig.err"
echo "annotations cross package: PASS"
