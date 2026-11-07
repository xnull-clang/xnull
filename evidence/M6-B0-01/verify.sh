#!/bin/sh
# M6-B0-01 一键复现：codegen 生成 -> 手工 cc 清单（含原生符号；P-10 归 E6）-> 运行 -> 与解释 oracle 比对。
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SAM="$ROOT/evidence/M6-B0-01/sample"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

cd "$ROOT/impl"

echo "== 1) xnull build (C generation+compilation OK; link needs native symbols = P-10)"
set +e
go run ./cmd/xnull build "$SAM/main.x" -o "$OUT/prog" > "$OUT/build.txt" 2>&1
BUILD_RC=$?
set -e
tail -5 "$OUT/build.txt"
echo "xnull_build_rc=$BUILD_RC (non-zero is the P-10 link-manifest gap)"

echo "== 2) manual cc (P-09 acceptance surface)"
cc -std=c11 -O2 -Wno-unused-function -I runtime -o "$OUT/prog-ffi" \
   "$OUT/prog.c" "$SAM/native.c" \
   runtime/rt.c runtime/rt_gc.c runtime/rt_policy.c runtime/rt_weak.c runtime/xrt_abi.c

echo "== 3) run"
"$OUT/prog-ffi" > "$OUT/compiled.txt"

echo "== 4) interpreter oracle"
go run ./cmd/xnull run "$SAM/oracle.x" --interp > "$OUT/interp.txt"

echo "== 5) double-path diff"
diff -u "$OUT/interp.txt" "$OUT/compiled.txt"
cat "$OUT/compiled.txt"
echo "OK: compiled == interp"
