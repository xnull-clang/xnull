#!/usr/bin/env bash
# B3-06c：可选值黄金 C 差分。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}; XNAST=${XNAST_BIN:-}; XNULLC=${XNULLC_FILE:-}; [ -n "$XNULLC" ] || XNULLC=$(python3 "$ROOT/tests/b4/materialize_legacy.py" "$ROOT" "$ROOT/impl/lib/xdk/compiler/codegen/Codegen.x") || exit 1
[ -n "$BIN" ] || ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3-ty ./cmd/xnull >/dev/null 2>&1 ) || exit 1
[ -n "$BIN" ] || BIN=/tmp/xnull-b3-ty
[ -n "$XNAST" ] || ( cd "$ROOT/impl" && go build -o /tmp/xnast-b3-ty ./cmd/xnast >/dev/null 2>&1 ) || exit 1
[ -n "$XNAST" ] || XNAST=/tmp/xnast-b3-ty
cd "$ROOT" || exit 2
pass=0; fail=0
for f in "$HERE"/fixtures/type/*.x; do
  rel=${f#"$ROOT"/}; ast=$("$XNAST" --ast "$rel")
  "$BIN" build --emit-c "$rel" > /tmp/ty.go 2>/dev/null || { echo "FAIL oracle $rel"; fail=$((fail+1)); continue; }
  "$BIN" run --interp "$XNULLC" -- "$rel" "$ast" > /tmp/ty.xn 2>/dev/null || { echo "FAIL xnullc $rel"; fail=$((fail+1)); continue; }
  if cmp -s /tmp/ty.go /tmp/ty.xn; then echo "PASS $rel"; pass=$((pass+1)); else echo "FAIL cdiff $rel"; diff -u /tmp/ty.go /tmp/ty.xn | head -10; fail=$((fail+1)); fi
done
echo "xnullc-type 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
