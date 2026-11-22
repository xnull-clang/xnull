#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
for name in package_adoption package_adoption2; do
    "$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/$name.x" >"$TMP"
    diff -u "$HERE/$name.out" "$TMP"
done
"$HERE/package_negative.sh"
echo "a8_packages: PASS"
