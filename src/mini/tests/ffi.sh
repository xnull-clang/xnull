#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
OUT=$("$ROOT/src/cli/xnull" --bootstrap --engine=mini run "$HERE/ffi_demo.x" 2>"$HERE/ffi.err")
[ "$OUT" = "true" ] || { cat "$HERE/ffi.err" >&2; exit 1; }
echo "mini ffi: PASS"
