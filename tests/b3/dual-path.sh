#!/usr/bin/env bash
# B3-00：9 个示例 interp vs 原生构建运行（stdout/退出码一致）。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
[ -n "$BIN" ] || BIN=$(command -v xnull || true)
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3 ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b3; fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b3-dual.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0
for f in "$ROOT"/tests/b2/corpus/examples/*.x; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  ( cd "$ROOT/impl" && "$BIN" run --interp "$f" > "$TMP/i.out" 2>"$TMP/i.err" ); ic=$?
  "$BIN" build "$f" -o "$TMP/bin" >"$TMP/b.log" 2>&1; bc=$?
  if [ $bc -ne 0 ]; then echo "FAIL build $name"; fail=$((fail+1)); continue; fi
  "$TMP/bin" > "$TMP/n.out" 2>"$TMP/n.err"; nc=$?
  if [ "$ic" = "$nc" ] && cmp -s "$TMP/i.out" "$TMP/n.out"; then
    echo "PASS dual $name"; pass=$((pass+1))
  else
    echo "FAIL dual $name exit $ic/$nc"; diff -u "$TMP/i.out" "$TMP/n.out" | head -10; fail=$((fail+1))
  fi
done
echo "dual-path 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
