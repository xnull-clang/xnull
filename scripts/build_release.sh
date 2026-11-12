#!/usr/bin/env bash
# 构建发布产物（无 Go 版，B4c-02b）。
#
# 产物目录（默认 dist/b4）：
#   xnull          统一 CLI（shell wrapper，指向 tests/b4/xnull-build.sh）
#   xn-s4          原生 XNull 编译器（bootstrap/bin）
#   xparser        原生解析器（bootstrap/bin）
#   tests/b4/      原型工具链脚本（构建/运行/校验/安装/冻结 golden 等）
#   SHA256SUMS
#
# 用法：scripts/build_release.sh [--out DIR]
# 依赖：cc（编译器）、python3（资源表/打包辅助）、shasum。
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
OUT=${1:-}
[ "${OUT:-}" = "--out" ] && OUT=${2:-}
[ -n "${OUT:-}" ] || OUT="$ROOT/dist/b4"

echo "release: 构建 bootstrap 工具（无 Go）"
"$ROOT/bootstrap/build.sh"

echo "release: 汇总到 $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$ROOT/bootstrap/bin/xn-s4" "$OUT/xn-s4"
cp "$ROOT/bootstrap/bin/xparser" "$OUT/xparser"
cp "$ROOT/bin/xnull" "$OUT/xnull"
chmod +x "$OUT/xnull"
cp -R "$ROOT/tests/b4" "$OUT/tests-b4"
rm -rf "$OUT/tests-b4/.cache" 2>/dev/null || true

( cd "$OUT" && shasum -a 256 xnull xn-s4 xparser > SHA256SUMS )
echo "release: 完成 → $OUT"
cat "$OUT/SHA256SUMS"
