#!/bin/sh
# Build the mini compiler: self-host when a seed binary exists, legacy bootstrap otherwise.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
mkdir -p "$HERE/bin"
CACHE=${XNULL_CACHE_DIR:-$ROOT/.cache/xnull}
mkdir -p "$CACHE"

"$ROOT/src/runtime/build_rt.sh" --lib
MODE=${XNULL_MINI_BOOTSTRAP:-auto}
TMPC="$HERE/bin/mini.c.tmp"
USED_LEGACY=0
if [ ! -x "$HERE/bin/mini" ] && [ "$MODE" != "legacy" ]; then
    MODE=legacy
fi
if [ "$MODE" != "legacy" ] && [ -x "$HERE/bin/mini" ]; then
    if "$HERE/bin/mini" --emit-c "$HERE/main.x" --xdk-root "$ROOT/src/xdk" > "$TMPC" 2>"$HERE/bin/mini.self.err"; then
        mv "$TMPC" "$HERE/bin/mini.c"
        printf '[build] mini self-host\n'
    else
        printf '[build] mini self-host failed, fallback legacy\n' >&2
        rm -f "$TMPC"
        MODE=legacy
    fi
fi
if [ "$MODE" = "legacy" ] || [ ! -f "$HERE/bin/mini.c" ]; then
    if command -v shasum >/dev/null 2>&1; then
        KEY=$(shasum -a 256 "$HERE/main.x" "$HERE/mini_io.xfb" "$HERE/support/io.c" \
            "$ROOT/src/runtime/libxnrt.a" "$ROOT/src/bootstrap/bin/xn-s4" \
            "$ROOT/src/toolchain/xnull-build.sh" | shasum -a 256 | awk '{print $1}')
    else
        KEY=$(sha256sum "$HERE/main.x" "$HERE/mini_io.xfb" "$HERE/support/io.c" \
            "$ROOT/src/runtime/libxnrt.a" "$ROOT/src/bootstrap/bin/xn-s4" \
            "$ROOT/src/toolchain/xnull-build.sh" | sha256sum | awk '{print $1}')
    fi
    CFILE="$CACHE/mini-$KEY.c"
    if [ -f "$CFILE" ]; then
        cp "$CFILE" "$HERE/bin/mini.c"
        printf '[cache] mini C hit\n'
    else
        "$ROOT/src/cli/xnull" --bootstrap --engine=legacy build --emit-c-only \
            "$HERE/main.x" -o "$HERE/bin/mini.c"
        cp "$HERE/bin/mini.c" "$CFILE"
        printf '[cache] mini C miss\n'
    fi
    USED_LEGACY=1
fi

# bootstrap 期由旧引擎生成的 C 使用固定 safepoint 阈值；旧 root 更新缺口会在
# 自编译大源码时提前回收局部 AST。mini 输出不依赖中途 GC，因此引导期禁用
# 中途回收，保证 M9 自编译可以完成。
if [ "$USED_LEGACY" = 1 ] && grep -q '#define XN_GC_SAFEPOINT_THRESHOLD 1024' "$HERE/bin/mini.c"; then
    sed 's/#define XN_GC_SAFEPOINT_THRESHOLD 1024/#define XN_GC_SAFEPOINT_THRESHOLD 1000000000/' \
        "$HERE/bin/mini.c" > "$HERE/bin/mini.c.tmp"
    mv "$HERE/bin/mini.c.tmp" "$HERE/bin/mini.c"
fi


cc -std=c11 -O2 -pthread \
    -I "$ROOT/src/runtime" -I "$HERE/support" \
    -o "$HERE/bin/mini" \
    "$HERE/bin/mini.c" "$HERE/support/io.c" \
    "$ROOT/src/runtime/libxnrt.a" -lz
