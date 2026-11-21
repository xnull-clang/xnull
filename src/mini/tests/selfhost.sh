#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
"$ROOT/src/mini/bin/mini" --emit-c "$HERE/../main.x" --xdk-root "$ROOT/src/xdk" >"$D/a.c"
cc -std=c11 -O2 -pthread -I "$ROOT/src/runtime" -I "$HERE/../support" \
  -o "$D/mini1" "$D/a.c" "$HERE/../support/io.c" "$ROOT/src/runtime/libxnrt.a" -lz 2>"$D/cc1.err"
"$D/mini1" --emit-c "$HERE/../main.x" --xdk-root "$ROOT/src/xdk" >"$D/b.c"
cmp "$D/a.c" "$D/b.c"
cc -std=c11 -O2 -pthread -I "$ROOT/src/runtime" -I "$HERE/../support" \
  -o "$D/mini2" "$D/b.c" "$HERE/../support/io.c" "$ROOT/src/runtime/libxnrt.a" -lz 2>"$D/cc2.err"
[ "$("$D/mini2" --version)" = "mini 1.0.0" ]
echo "mini selfhost: PASS"
