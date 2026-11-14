#!/usr/bin/env bash
# B2-01 L1 差分：XNull xlex.x 与 Go xnast --tokens 逐字节比较；负例比 LEX 码/位置。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
B2_TMP=${B2_TMP:-$(mktemp -d "${TMPDIR:-/tmp}/b2-run.XXXXXX")}
trap '[ -n "${B2_TMP_KEEP:-}" ] || rm -rf "$B2_TMP"' EXIT
mkdir -p "$B2_TMP"
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
ORACLE=${XNAST_BIN:-}
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b2 ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b2; fi
if [ -z "$ORACLE" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnast-b2 ./cmd/xnast ) || exit 1; ORACLE=/tmp/xnast-b2; fi
CORPUS=${B2_CORPUS:-$HERE/corpus.tsv}
XLEX=$(python3 "$ROOT/tests/b4/materialize_legacy.py" "$ROOT" "$ROOT/impl/lib/xdk/compiler/lexer/Lexer.x") || exit 1
pass=0 fail=0
while IFS=$'\t' read -r h p; do
  case "$h" in \#*|"") continue;; esac
  f="$ROOT/$p"
  "$ORACLE" --tokens "$f" > "$B2_TMP"/b2-go.tok 2>/dev/null
  SRC="$(cat "$f")"$'\n'
  ( cd "$ROOT/impl" && "$BIN" run --interp "$XLEX" "$SRC" > "$B2_TMP"/b2-xn.tok 2>"$B2_TMP"/b2-xn.err )
  if cmp -s "$B2_TMP"/b2-go.tok "$B2_TMP"/b2-xn.tok; then
    echo "PASS L1 $p"; pass=$((pass+1))
  else
    echo "FAIL L1 $p"; diff -u "$B2_TMP"/b2-go.tok "$B2_TMP"/b2-xn.tok | head -20; fail=$((fail+1))
  fi
done < "$CORPUS"
for f in "$HERE"/lex_extra/*.x; do
  [ -e "$f" ] || continue
  p=${f#"$ROOT"/}
  "$ORACLE" --tokens "$f" > "$B2_TMP"/b2-go.tok 2>/dev/null
  SRC="$(cat "$f")"$'\n'
  ( cd "$ROOT/impl" && "$BIN" run --interp "$XLEX" "$SRC" > "$B2_TMP"/b2-xn.tok 2>"$B2_TMP"/b2-xn.err )
  if cmp -s "$B2_TMP"/b2-go.tok "$B2_TMP"/b2-xn.tok; then
    echo "PASS EXTRA $p"
  else
    echo "FAIL EXTRA $p"; diff -u "$B2_TMP"/b2-go.tok "$B2_TMP"/b2-xn.tok | head -20; fail=$((fail+1))
  fi
done
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
