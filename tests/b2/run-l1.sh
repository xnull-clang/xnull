#!/usr/bin/env bash
# B2-01 L1 差分：XNull xlex.x 与 Go xnast --tokens 逐字节比较；负例比 LEX 码/位置。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
ORACLE=${XNAST_BIN:-}
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b2 ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b2; fi
if [ -z "$ORACLE" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnast-b2 ./cmd/xnast ) || exit 1; ORACLE=/tmp/xnast-b2; fi
XLEX="$ROOT/impl/lib/b2/xlex.x"
pass=0 fail=0
while IFS=$'\t' read -r h p; do
  case "$h" in \#*|"") continue;; esac
  f="$ROOT/$p"
  "$ORACLE" --tokens "$f" > /tmp/b2-go.tok 2>/dev/null
  SRC="$(cat "$f")"$'\n'
  ( cd "$ROOT/impl" && "$BIN" run --interp "$XLEX" "$SRC" > /tmp/b2-xn.tok 2>/tmp/b2-xn.err )
  if cmp -s /tmp/b2-go.tok /tmp/b2-xn.tok; then
    echo "PASS L1 $p"; pass=$((pass+1))
  else
    echo "FAIL L1 $p"; diff -u /tmp/b2-go.tok /tmp/b2-xn.tok | head -20; fail=$((fail+1))
  fi
done < "$HERE/corpus.tsv"
for f in "$HERE"/lex_neg/*.x; do
  base=${f%.x}; want=$(cat "$base.diag")
  SRC="$(cat "$f")"$'\n'
  got=$( cd "$ROOT/impl" && "$BIN" run --interp "$XLEX" -- --diags "$SRC" 2>/tmp/b2-neg.err | tail -n +2 )
  if [ "$got" = "$want" ]; then
    echo "PASS LEX $(basename "$f")"; pass=$((pass+1))
  else
    echo "FAIL LEX $(basename "$f"): got=$got want=$want"; fail=$((fail+1))
  fi
done
echo "汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
