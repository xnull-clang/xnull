#!/usr/bin/env bash
# B3-00：负例清单——未支持/非法输入必须同样失败，不静默降级。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
[ -n "$BIN" ] || BIN=$(command -v xnull || true)
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3 ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b3; fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b3-neg.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0
while IFS=$'\t' read -r rel want; do
  case "$rel" in \#*|"") continue;; esac
  f="$HERE/$rel"
  [ -f "$f" ] || { echo "SKIP $rel"; continue; }
  "$BIN" build --emit-c "$f" >"$TMP/o.c" 2>"$TMP/e.log"; code=$?
  if [ "$code" -ne 0 ]; then echo "PASS neg $rel exit=$code"; pass=$((pass+1)); else echo "FAIL neg $rel exit=$code"; fail=$((fail+1)); fi
done < "$HERE/negative.tsv"
echo "negative 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
