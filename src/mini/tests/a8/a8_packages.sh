#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/package_adoption.x" >"$TMP"
diff -u "$HERE/package_adoption.out" "$TMP"
echo "a8_packages: PASS"
