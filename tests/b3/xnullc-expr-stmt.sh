#!/usr/bin/env bash
# B3-02：EXPR/STMT 黄金 C 差分 + 双路径（interp vs xnullc 生成的 C）。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
XNAST=${XNAST_BIN:-}
XNULLC=${XNULLC_FILE:-"$ROOT/impl/lib/b3/xnullc.x"}
RUNTIME=${XNULL_RUNTIME:-"$ROOT/impl/runtime"}
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3-es ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b3-es; fi
if [ -z "$XNAST" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnast-b3-es ./cmd/xnast ) || exit 1; XNAST=/tmp/xnast-b3-es; fi
[ -f "$XNULLC" ] || { echo "缺少 xnullc：$XNULLC"; exit 2; }
cd "$ROOT" || exit 2
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b3-es.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
RT_SRCS="rt.c rt_gc.c rt_policy.c rt_weak.c xrt_abi.c rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c rt_std_net.c rt_task.c rt_sync.c rt_std_res.c rt_std_res_empty.c"
pass=0; fail=0
for f in "$HERE"/fixtures/expr/*.x "$HERE"/fixtures/stmt/*.x; do
  [ -f "$f" ] || continue
  rel=${f#"$ROOT"/}
  name=${rel#tests/b3/fixtures/}
  ast=$("$XNAST" --ast "$rel") || { echo "FAIL ast $name"; fail=$((fail+1)); continue; }
  "$BIN" build --emit-c "$rel" > "$TMP/go.c" 2>"$TMP/go.err" || { echo "FAIL oracle $name"; cat "$TMP/go.err"; fail=$((fail+1)); continue; }
  "$BIN" run --interp "$XNULLC" -- "$rel" "$ast" > "$TMP/xn.c" 2>"$TMP/xn.err" || { echo "FAIL xnullc $name"; cat "$TMP/xn.err"; fail=$((fail+1)); continue; }
  if ! cmp -s "$TMP/go.c" "$TMP/xn.c"; then
    echo "FAIL cdiff $name"; diff -u "$TMP/go.c" "$TMP/xn.c" | head -16; fail=$((fail+1)); continue
  fi
  # 双路径：Go 原生构建 vs xnullc 生成的 C（同一 cc/运行时）
  "$BIN" build "$rel" -o "$TMP/gobin" >"$TMP/gobuild.log" 2>&1 || { echo "FAIL gobuild $name"; tail -5 "$TMP/gobuild.log"; fail=$((fail+1)); continue; }
  "$TMP/gobin" > "$TMP/i.out" 2>"$TMP/i.err"; ic=$?
  cc -std=c11 -O2 -pthread -I "$RUNTIME" -o "$TMP/prog" "$TMP/xn.c" $(for s in $RT_SRCS; do printf '%s ' "$RUNTIME/$s"; done) >"$TMP/cc.log" 2>&1 || { echo "FAIL cc $name"; tail -5 "$TMP/cc.log"; fail=$((fail+1)); continue; }
  "$TMP/prog" > "$TMP/n.out" 2>"$TMP/n.err"; nc=$?
  if [ "$ic" = "$nc" ] && cmp -s "$TMP/i.out" "$TMP/n.out"; then
    echo "PASS $name"; pass=$((pass+1))
  else
    echo "FAIL dual $name exit $ic/$nc"; diff -u "$TMP/i.out" "$TMP/n.out" | head -10; fail=$((fail+1))
  fi
done
echo "xnullc-expr-stmt 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
