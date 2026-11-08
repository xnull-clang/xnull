#!/usr/bin/env bash
# B2-02 L2 差分：XNull xparser.x 与 Go xnast --ast 在表达式/语句子集逐字节比较。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
ORACLE=${XNAST_BIN:-}
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b2 ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b2; fi
if [ -z "$ORACLE" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnast-b2 ./cmd/xnast ) || exit 1; ORACLE=/tmp/xnast-b2; fi
XPARSE="$ROOT/impl/lib/b2/xparser.x"
pass=0 fail=0
for f in "$HERE"/parser_cases/*.x; do
  p=${f#"$ROOT"/}
  "$ORACLE" --ast "$f" > /tmp/b2-go.ast 2>/dev/null
  SRC="$(cat "$f")"$'\n'
  ( cd "$ROOT/impl" && "$BIN" run --interp "$XPARSE" "$SRC" > /tmp/b2-xn.ast 2>/tmp/b2-xn.err )
  if cmp -s /tmp/b2-go.ast /tmp/b2-xn.ast; then
    echo "PASS L2 $p"; pass=$((pass+1))
  else
    echo "FAIL L2 $p"; diff -u /tmp/b2-go.ast /tmp/b2-xn.ast | head -20; fail=$((fail+1))
  fi
done
for f in "$HERE"/parser_neg/*.x; do
  base=${f%.x}; want=$(cat "$base.diag")
  SRC="$(cat "$f")"$'\n'
  got=$( cd "$ROOT/impl" && "$BIN" run --interp "$XPARSE" -- --diags "$SRC" 2>/tmp/b2-neg.err | tail -n +2 | head -1 )
  if [ "$got" = "$want" ]; then
    echo "PASS NEG $(basename "$f")"; pass=$((pass+1))
  else
    echo "FAIL NEG $(basename "$f"): got=$got want=$want"; fail=$((fail+1))
  fi
done
echo "汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
