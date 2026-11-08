#!/usr/bin/env bash
# B3-00：--emit-c 两次生成逐字节一致 + sha256 记录。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
[ -n "$BIN" ] || BIN=$(command -v xnull || true)
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3 ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b3; fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b3-emit.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0
for f in "$ROOT"/tests/b2/corpus/examples/*.x; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  "$BIN" build --emit-c "$f" > "$TMP/a.c" 2>"$TMP/a.err" || { echo "FAIL emit $name"; fail=$((fail+1)); continue; }
  "$BIN" build --emit-c "$f" > "$TMP/b.c" 2>"$TMP/b.err" || { echo "FAIL emit2 $name"; fail=$((fail+1)); continue; }
  if cmp -s "$TMP/a.c" "$TMP/b.c"; then
    echo "PASS emit $name $(sha256sum "$TMP/a.c" | cut -d' ' -f1)"; pass=$((pass+1))
  else
    echo "FAIL diff $name"; diff -u "$TMP/a.c" "$TMP/b.c" | head -10; fail=$((fail+1))
  fi
done
echo "emit-diff 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
