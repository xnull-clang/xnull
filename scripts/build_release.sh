#!/bin/sh
# 构建发布产物：xnull + xnfmt + SHA256SUMS（B1：工具必须进入正式发布物）
# 用法：sh scripts/build_release.sh [输出目录，缺省 dist/]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/dist"}
mkdir -p "$OUT"
( cd "$ROOT/impl" \
  && go build -trimpath -o "$OUT/xnull" ./cmd/xnull \
  && go build -trimpath -o "$OUT/xnfmt" ./cmd/xnfmt )
( cd "$OUT" && shasum -a 256 xnull xnfmt > SHA256SUMS )
echo "发布产物：$OUT"
cat "$OUT/SHA256SUMS"
