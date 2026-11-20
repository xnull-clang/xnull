#!/bin/sh
# Build the mini compiler by self-hosting the existing mini binary.
# mini is the only compiler.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
mkdir -p "$HERE/bin"

"$ROOT/src/runtime/build_rt.sh" --lib

if [ ! -x "$HERE/bin/mini" ]; then
    if [ -f "$HERE/bin/mini.c" ]; then
        cc -std=c11 -O2 -pthread \
            -I "$ROOT/src/runtime" -I "$HERE/support" \
            -o "$HERE/bin/mini" \
            "$HERE/bin/mini.c" "$HERE/support/io.c" \
            "$ROOT/src/runtime/libxnrt.a" -lz
        echo "[build] seed mini from committed C"
    else
        echo "mini: no seed binary and no committed mini.c" >&2
        exit 2
    fi
fi

TMPC="$HERE/bin/mini.c.tmp"
if ! "$HERE/bin/mini" --emit-c "$HERE/main.x" --xdk-root "$ROOT/src/xdk" > "$TMPC" 2>"$HERE/bin/mini.self.err"; then
    echo "mini: self-host codegen failed" >&2
    sed -n 1,20p "$HERE/bin/mini.self.err" >&2
    rm -f "$TMPC"
    exit 1
fi
mv "$TMPC" "$HERE/bin/mini.c"

cc -std=c11 -O2 -pthread \
    -I "$ROOT/src/runtime" -I "$HERE/support" \
    -o "$HERE/bin/mini" \
    "$HERE/bin/mini.c" "$HERE/support/io.c" \
    "$ROOT/src/runtime/libxnrt.a" -lz
echo "[build] mini self-host: PASS"
