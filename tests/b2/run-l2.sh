#!/usr/bin/env bash
# B2 L2/L3 差分：XNull xparser.x 与 Go xnast 比较。
#   L2：parser_cases 子集 + corpus.tsv 全语料，AST 逐字节一致。
#   L3：parser_neg 负例，诊断码与位置序列一致（以 Go oracle 为准）。
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
XPARSE=${XPARSE:-$ROOT/impl/lib/b2/xparser.x}
pass=0 fail=0

l2_case() {
  local f="$1" label="$2"
  "$ORACLE" --ast "$f" > "$B2_TMP"/b2-go.ast 2>/dev/null
  SRC="$(cat "$f")"$'\n'
  ( cd "$ROOT/impl" && "$BIN" run --interp "$XPARSE" "$SRC" > "$B2_TMP"/b2-xn.ast 2>"$B2_TMP"/b2-xn.err )
  if cmp -s "$B2_TMP"/b2-go.ast "$B2_TMP"/b2-xn.ast; then
    echo "PASS L2 $label"; pass=$((pass+1))
  else
    echo "FAIL L2 $label"; diff -u "$B2_TMP"/b2-go.ast "$B2_TMP"/b2-xn.ast | head -20; fail=$((fail+1))
  fi
}

for f in "$HERE"/parser_cases/*.x; do
  l2_case "$f" "${f#"$ROOT"/}"
done

while IFS=$'\t' read -r hash rel; do
  case "$hash" in \#*|"") continue;; esac
  l2_case "$ROOT/$rel" "$rel"
done < "$HERE/corpus.tsv"

# L3：诊断序列（Code Line Col）与 Go oracle 完全一致。
diag_code_pos() {
  sed -n 's/.*(Line \([0-9]*\)) (Col \([0-9]*\)) (Code "\([^"]*\)").*/\3 \1 \2/p'
}
for f in "$HERE"/parser_neg/*.x; do
  rel=${f#"$ROOT"/}
  want=$( "$ORACLE" --diags "$f" 2>/dev/null | diag_code_pos )
  SRC="$(cat "$f")"$'\n'
  got=$( cd "$ROOT/impl" && "$BIN" run --interp "$XPARSE" -- --diags "$SRC" 2>/tmp/b2-neg.err | tail -n +2 )
  if [ "$got" = "$want" ]; then
    echo "PASS NEG $rel"; pass=$((pass+1))
  else
    echo "FAIL NEG $rel"; diff -u <(printf '%s\n' "$want") <(printf '%s\n' "$got") | head -20; fail=$((fail+1))
  fi
done

echo "汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
