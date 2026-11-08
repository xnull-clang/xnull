#!/usr/bin/env bash
# B3-08c：xnullc 消费 AST bundle（入口 + import 闭包，依赖后序）。
# 验收面：sync/tasks/collections 多文件 C 逐字节 + 双路径；
# text 因既有 String/Text/Bytes 发射面缺口记 KNOWN-DIFF（不计入通过）。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
XNAST=${XNAST_BIN:-}
XNULLC=${XNULLC_FILE:-"$ROOT/impl/lib/b3/xnullc.x"}
RUNTIME=${XNULL_RUNTIME:-"$ROOT/impl/runtime"}
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3-bun ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b3-bun; fi
if [ -z "$XNAST" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnast-b3-bun ./cmd/xnast ) || exit 1; XNAST=/tmp/xnast-b3-bun; fi
[ -f "$XNULLC" ] || { echo "缺少 xnullc：$XNULLC"; exit 2; }
cd "$ROOT" || exit 2
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b3-bun.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
RT_SRCS="rt.c rt_gc.c rt_policy.c rt_weak.c xrt_abi.c rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c rt_std_net.c rt_task.c rt_sync.c rt_std_res.c rt_std_res_empty.c"
pass=0; fail=0

run_case() {
  local pkg=$1 expect=$2
  local dir="tests/b3/fixtures/bundle_$pkg"
  local rel="$dir/app.x"
  local name="bundle_$pkg"
  local ast proj bundle
  ast=$("$XNAST" --ast "$rel") || { echo "FAIL ast $name"; fail=$((fail+1)); return; }
  proj=$(python3 "$HERE/xfb-projection.py" "$dir")
  bundle=$(cat "$dir/app.bundle.json")
  "$BIN" build --emit-c "$rel" > "$TMP/go.c" 2>"$TMP/go.err" || { echo "FAIL oracle $name"; cat "$TMP/go.err"; fail=$((fail+1)); return; }
  "$BIN" run --interp "$XNULLC" -- "$rel" "$ast" "$proj" "$bundle" > "$TMP/xn.c" 2>"$TMP/xn.err" || { echo "FAIL xnullc $name"; cat "$TMP/xn.err"; fail=$((fail+1)); return; }
  if ! cmp -s "$TMP/go.c" "$TMP/xn.c"; then
    local d
    d=$(diff -u "$TMP/go.c" "$TMP/xn.c" | wc -l)
    if [ "$expect" = "known" ]; then
      echo "KNOWN-DIFF $name ($d lines; String/Text/Bytes emission gap)"
      return
    fi
    echo "FAIL cdiff $name"; diff -u "$TMP/go.c" "$TMP/xn.c" | head -16; fail=$((fail+1)); return
  fi
  cc -std=c11 -O2 -pthread -I "$RUNTIME" -o "$TMP/gobin" "$TMP/go.c" $(for s in $RT_SRCS; do printf '%s ' "$RUNTIME/$s"; done) >"$TMP/gocc.log" 2>&1 || { echo "FAIL gocc $name"; tail -5 "$TMP/gocc.log"; fail=$((fail+1)); return; }
  cc -std=c11 -O2 -pthread -I "$RUNTIME" -o "$TMP/xnbin" "$TMP/xn.c" $(for s in $RT_SRCS; do printf '%s ' "$RUNTIME/$s"; done) >"$TMP/xncc.log" 2>&1 || { echo "FAIL xncc $name"; tail -5 "$TMP/xncc.log"; fail=$((fail+1)); return; }
  "$TMP/gobin" > "$TMP/i.out" 2>"$TMP/i.err"; local ic=$?
  "$TMP/xnbin" > "$TMP/n.out" 2>"$TMP/n.err"; local nc=$?
  if [ "$ic" = "$nc" ] && cmp -s "$TMP/i.out" "$TMP/n.out"; then
    echo "PASS $name"; pass=$((pass+1))
  else
    echo "FAIL dual $name exit $ic/$nc"; diff -u "$TMP/i.out" "$TMP/n.out" | head -10; fail=$((fail+1))
  fi
}

run_case sync pass
run_case tasks pass
run_case collections pass
run_case text known

echo "xnullc-bundle 汇总：PASS=$pass FAIL=$fail (text=KNOWN-DIFF)"
[ "$fail" -eq 0 ]
