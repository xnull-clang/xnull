#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../../.." && pwd)
TMP=$(mktemp -d "$HERE/.run.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/pkg"
cp "$HERE/pkg/a.x.txt" "$TMP/pkg/a.x"
cp "$HERE/pkg/b.x.txt" "$TMP/pkg/b.x"
cp "$HERE/main_both.x.txt" "$TMP/main_both.x"
cp "$HERE/main_b.x.txt" "$TMP/main_b.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$TMP/main_b.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$TMP/main_both.x"
