#!/usr/bin/env bash
# B3-09 §2.4：9 个示例的 Go C 与 xnullc C 各自 cc 编译运行，stdout/退出码一致。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
XNAST=${XNAST_BIN:-}
XNULLC=${XNULLC_FILE:-"$ROOT/impl/lib/b3/xnullc.x"}
RUNTIME=${XNULL_RUNTIME:-"$ROOT/impl/runtime"}
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3-ex ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b3-ex; fi
if [ -z "$XNAST" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnast-b3-ex ./cmd/xnast ) || exit 1; XNAST=/tmp/xnast-b3-ex; fi
[ -f "$XNULLC" ] || { echo "缺少 xnullc：$XNULLC"; exit 2; }
cd "$ROOT" || exit 2
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b3-ex.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
RT_SRCS="rt.c rt_gc.c rt_policy.c rt_weak.c xrt_abi.c rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c rt_std_net.c rt_task.c rt_sync.c rt_std_res.c rt_std_res_empty.c"
pass=0; fail=0
for f in "$ROOT"/examples/*.x; do
  [ -f "$f" ] || continue
  rel=${f#"$ROOT"/}
  name=$(basename "$f")
  ast=$("$XNAST" --ast "$rel") || { echo "FAIL ast $name"; fail=$((fail+1)); continue; }
  proj=$(python3 "$HERE/xfb-projection.py" examples) || { echo "FAIL projection $name"; fail=$((fail+1)); continue; }
  "$BIN" build --emit-c "$rel" > "$TMP/go.c" 2>"$TMP/go.err" || { echo "FAIL oracle $name"; tail -3 "$TMP/go.err"; fail=$((fail+1)); continue; }
  "$BIN" run --interp "$XNULLC" -- "$rel" "$ast" "$proj" > "$TMP/xn.c" 2>"$TMP/xn.err" || { echo "FAIL xnullc $name"; tail -3 "$TMP/xn.err"; fail=$((fail+1)); continue; }
  if ! cmp -s "$TMP/go.c" "$TMP/xn.c"; then
    echo "FAIL cdiff $name"; diff -u "$TMP/go.c" "$TMP/xn.c" | head -12; fail=$((fail+1)); continue
  fi
  "$BIN" run --interp "$XNULLC" -- "$rel" "$ast" "$proj" > "$TMP/xn2.c" 2>"$TMP/xn2.err" || { echo "FAIL xnullc2 $name"; tail -3 "$TMP/xn2.err"; fail=$((fail+1)); continue; }
  if ! cmp -s "$TMP/xn.c" "$TMP/xn2.c"; then
    echo "FAIL determinism $name"; fail=$((fail+1)); continue
  fi
  cc -std=c11 -O2 -pthread -I "$RUNTIME" -o "$TMP/gobin" "$TMP/go.c" $(for s in $RT_SRCS; do printf '%s ' "$RUNTIME/$s"; done) >"$TMP/gocc.log" 2>&1 || { echo "FAIL gocc $name"; tail -3 "$TMP/gocc.log"; fail=$((fail+1)); continue; }
  cc -std=c11 -O2 -pthread -I "$RUNTIME" -o "$TMP/xnbin" "$TMP/xn.c" $(for s in $RT_SRCS; do printf '%s ' "$RUNTIME/$s"; done) >"$TMP/xncc.log" 2>&1 || { echo "FAIL xncc $name"; tail -3 "$TMP/xncc.log"; fail=$((fail+1)); continue; }
  "$TMP/gobin" > "$TMP/i.out" 2>"$TMP/i.err"; ic=$?
  "$TMP/xnbin" > "$TMP/n.out" 2>"$TMP/n.err"; nc=$?
  if [ "$ic" = "$nc" ] && cmp -s "$TMP/i.out" "$TMP/n.out"; then
    echo "PASS $name"
    pass=$((pass+1))
  else
    echo "FAIL dual $name exit $ic/$nc"; diff -u "$TMP/i.out" "$TMP/n.out" | head -10; fail=$((fail+1))
  fi
done
echo "xnullc-examples 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
