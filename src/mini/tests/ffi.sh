#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
E=$(mktemp)
trap 'rm -f "$E"' EXIT
OUT=$("$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/ffi_demo.x" 2>"$E")
[ "$OUT" = "true" ] || { cat "$E" >&2; exit 1; }
echo "mini ffi: PASS"
