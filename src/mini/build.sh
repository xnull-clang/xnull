#!/bin/sh
# Build mini from a seed compiled from committed mini.c; never trust bin/mini.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
mkdir -p "$HERE/bin"
"$ROOT/src/runtime/build_rt.sh" --lib
[ -f "$HERE/bin/mini.c" ] || { echo "mini: missing committed src/mini/bin/mini.c" >&2; exit 2; }
SEED="$HERE/bin/mini.seed"
TMPC="$HERE/bin/mini.c.tmp.c"
NEWBIN="$HERE/bin/mini.new"
rm -f "$SEED" "$TMPC" "$NEWBIN"
if ! cc -std=c11 -O2 -pthread -I "$ROOT/src/runtime" -I "$HERE/support" \
    -o "$SEED" "$HERE/bin/mini.c" "$HERE/support/io.c" "$ROOT/src/runtime/libxnrt.a" -lz; then
    echo "mini: seed compile failed; existing compiler left untouched" >&2
    rm -f "$SEED"; exit 1
fi
if ! "$SEED" --emit-c "$HERE/main.x" --xdk-root "$ROOT/src/xdk" > "$TMPC" 2>"$HERE/bin/mini.self.err"; then
    echo "mini: self-host codegen failed; existing compiler left untouched" >&2
    sed -n 1,20p "$HERE/bin/mini.self.err" >&2
    rm -f "$TMPC" "$SEED"; exit 1
fi
if ! cc -std=c11 -O2 -pthread -I "$ROOT/src/runtime" -I "$HERE/support" \
    -o "$NEWBIN" "$TMPC" "$HERE/support/io.c" "$ROOT/src/runtime/libxnrt.a" -lz; then
    echo "mini: self-host compile failed; existing compiler left untouched" >&2
    rm -f "$TMPC" "$NEWBIN" "$SEED"; exit 1
fi
mv "$TMPC" "$HERE/bin/mini.c"
mv "$NEWBIN" "$HERE/bin/mini"
rm -f "$SEED"
echo "[build] mini self-host: PASS"
