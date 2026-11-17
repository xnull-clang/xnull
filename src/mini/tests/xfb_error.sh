#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
SRC="$HERE/xfb_error"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

mkdir -p "$D/xfb"
cp "$SRC/xfb_error.xfb.in" "$D/xfb/xfb_error.xfb"
python3 "$ROOT/src/toolchain/xfb-projection.py" "$D/xfb" > "$D/project.txt"
"$ROOT/src/mini/bin/mini" --emit-c "$SRC/xfb_error.x" \
    --xdk-root "$ROOT/src/xdk" --project-file "$D/project.txt" > "$D/error.c"
cc -std=c11 -O2 -pthread \
    -I "$ROOT/src/runtime" -I "$ROOT/src/mini/support" \
    -o "$D/error" "$D/error.c" "$SRC/xfb_error_helper.c" \
    "$ROOT/src/mini/support/io.c" "$ROOT/src/runtime/libxnrt.a" -lz

"$D/error" > "$D/out"
printf '5\ntrue\n0\ntrue\ntrue\n' > "$D/expected"
diff -u "$D/expected" "$D/out"

echo "mini xfb-error: PASS"
