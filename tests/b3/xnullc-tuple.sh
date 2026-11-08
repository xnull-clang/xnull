#!/usr/bin/env bash
# B3-06b：元组基础黄金 C 差分（basic）。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}; XNAST=${XNAST_BIN:-}; XNULLC=${XNULLC_FILE:-"$ROOT/impl/lib/b3/xnullc.x"}
[ -n "$BIN" ] || ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3-tp ./cmd/xnull >/dev/null 2>&1 ) || exit 1
[ -n "$BIN" ] || BIN=/tmp/xnull-b3-tp
[ -n "$XNAST" ] || ( cd "$ROOT/impl" && go build -o /tmp/xnast-b3-tp ./cmd/xnast >/dev/null 2>&1 ) || exit 1
[ -n "$XNAST" ] || XNAST=/tmp/xnast-b3-tp
cd "$ROOT" || exit 2
pass=0; fail=0
for f in "$HERE"/fixtures/tuple/*.x; do
  rel=${f#"$ROOT"/}; ast=$("$XNAST" --ast "$rel")
  "$BIN" build --emit-c "$rel" > /tmp/tp.go 2>/dev/null || { echo "FAIL oracle $rel"; fail=$((fail+1)); continue; }
  "$BIN" run --interp "$XNULLC" -- "$rel" "$ast" > /tmp/tp.xn 2>/dev/null || { echo "FAIL xnullc $rel"; fail=$((fail+1)); continue; }
  if cmp -s /tmp/tp.go /tmp/tp.xn; then echo "PASS $rel"; pass=$((pass+1)); else echo "FAIL cdiff $rel"; diff -u /tmp/tp.go /tmp/tp.xn | head -10; fail=$((fail+1)); fi
done
echo "xnullc-tuple 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
