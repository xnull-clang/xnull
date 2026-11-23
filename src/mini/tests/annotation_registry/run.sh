#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$HERE/registry.x" -o "$TMP/registry" >"$TMP/build.log" 2>&1
"$TMP/registry" >"$TMP/registry.out"
diff -u "$HERE/registry.out" "$TMP/registry.out"
echo "annotation_registry: PASS"
