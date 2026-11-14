#!/usr/bin/env bash
# B3-01：xnullc 骨架验收——空 main 与 hello.x 的 C 文本与 Go --emit-c 逐字节一致。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
XNAST=${XNAST_BIN:-}
XNULLC=${XNULLC_FILE:-}; [ -n "$XNULLC" ] || XNULLC=$(python3 "$ROOT/tests/b4/materialize_legacy.py" "$ROOT" "$ROOT/impl/lib/xdk/compiler/codegen/Codegen.x") || exit 1
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3-skel ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b3-skel; fi
if [ -z "$XNAST" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnast-b3-skel ./cmd/xnast ) || exit 1; XNAST=/tmp/xnast-b3-skel; fi
[ -f "$XNULLC" ] || { echo "缺少 xnullc：$XNULLC"; exit 2; }

cd "$ROOT" || exit 2
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b3-skel.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
for rel in tests/b3/fixtures/empty_main.x examples/hello.x; do
  ast=$("$XNAST" --ast "$rel") || { echo "FAIL ast $rel"; fail=$((fail+1)); continue; }
  "$BIN" build --emit-c "$rel" > "$TMP/go.c" 2>"$TMP/go.err" || { echo "FAIL oracle $rel"; cat "$TMP/go.err"; fail=$((fail+1)); continue; }
  "$BIN" run --interp "$XNULLC" -- "$rel" "$ast" > "$TMP/xn.c" 2>"$TMP/xn.err" || { echo "FAIL xnullc $rel"; cat "$TMP/xn.err"; fail=$((fail+1)); continue; }
  if cmp -s "$TMP/go.c" "$TMP/xn.c"; then
    echo "PASS skel $rel"
    pass=$((pass+1))
  else
    echo "FAIL skel $rel"
    diff -u "$TMP/go.c" "$TMP/xn.c" | head -20
    fail=$((fail+1))
  fi
done
echo "xnullc-skeleton 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
