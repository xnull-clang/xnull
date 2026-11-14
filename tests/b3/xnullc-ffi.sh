#!/usr/bin/env bash
# B3-08：FFI/XDK 锚点——黄金 C 差分 + 包装文本 diff + 双路径。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
XNAST=${XNAST_BIN:-}
XNULLC=${XNULLC_FILE:-}; [ -n "$XNULLC" ] || XNULLC=$(python3 "$ROOT/tests/b4/materialize_legacy.py" "$ROOT" "$ROOT/impl/lib/xdk/compiler/codegen/Codegen.x") || exit 1
RUNTIME=${XNULL_RUNTIME:-"$ROOT/impl/runtime"}
if [ -z "$BIN" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3-ffi ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-b3-ffi; fi
if [ -z "$XNAST" ]; then ( cd "$ROOT/impl" && go build -o /tmp/xnast-b3-ffi ./cmd/xnast ) || exit 1; XNAST=/tmp/xnast-b3-ffi; fi
[ -f "$XNULLC" ] || { echo "缺少 xnullc：$XNULLC"; exit 2; }
cd "$ROOT" || exit 2
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b3-ffi.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
RT_SRCS="rt.c rt_gc.c rt_policy.c rt_weak.c xrt_abi.c rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c rt_std_net.c rt_task.c rt_sync.c rt_std_res.c rt_std_res_empty.c"
pass=0; fail=0

run_case() {
  local rel=$1 native=$2 envs=${3:-}
  local name=${rel#"tests/b3/"}
  local dir
  dir=$(dirname "$rel")
  local proj
  proj=$(python3 "$HERE/xfb-projection.py" "$dir") || { echo "FAIL projection $name"; fail=$((fail+1)); return; }
  local ast
  ast=$("$XNAST" --ast "$rel") || { echo "FAIL ast $name"; fail=$((fail+1)); return; }
  "$BIN" build --emit-c "$rel" > "$TMP/go.c" 2>"$TMP/go.err" || { echo "FAIL oracle $name"; cat "$TMP/go.err"; fail=$((fail+1)); return; }
  "$BIN" run --interp "$XNULLC" -- "$rel" "$ast" "$proj" > "$TMP/xn.c" 2>"$TMP/xn.err" || { echo "FAIL xnullc $name"; cat "$TMP/xn.err"; fail=$((fail+1)); return; }
  if ! cmp -s "$TMP/go.c" "$TMP/xn.c"; then
    echo "FAIL cdiff $name"; diff -u "$TMP/go.c" "$TMP/xn.c" | head -16; fail=$((fail+1)); return
  fi
  local extra=""
  [ -n "$native" ] && extra=$native
  cc -std=c11 -O2 -pthread -I "$RUNTIME" -o "$TMP/gobin" "$TMP/go.c" $(for s in $RT_SRCS; do printf '%s ' "$RUNTIME/$s"; done) $extra >"$TMP/gocc.log" 2>&1 || { echo "FAIL gocc $name"; tail -5 "$TMP/gocc.log"; fail=$((fail+1)); return; }
  cc -std=c11 -O2 -pthread -I "$RUNTIME" -o "$TMP/xnbin" "$TMP/xn.c" $(for s in $RT_SRCS; do printf '%s ' "$RUNTIME/$s"; done) $extra >"$TMP/xncc.log" 2>&1 || { echo "FAIL xncc $name"; tail -5 "$TMP/xncc.log"; fail=$((fail+1)); return; }
  env $envs "$TMP/gobin" > "$TMP/i.out" 2>"$TMP/i.err"; local ic=$?
  env $envs "$TMP/xnbin" > "$TMP/n.out" 2>"$TMP/n.err"; local nc=$?
  if [ "$ic" = "$nc" ] && cmp -s "$TMP/i.out" "$TMP/n.out"; then
    echo "PASS $name"; pass=$((pass+1))
  else
    echo "FAIL dual $name exit $ic/$nc"; diff -u "$TMP/i.out" "$TMP/n.out" | head -10; fail=$((fail+1))
  fi
}

run_case "tests/b3/ffi-cases/basic/add.x" "$ROOT/tests/b3/ffi-cases/basic/native.c"
run_case "tests/b3/ffi-cases/err/wrap.x" "$ROOT/tests/b3/ffi-cases/err/native.c"
run_case "tests/b3/ffi-cases/comp/exec.x" "$ROOT/tests/b3/ffi-cases/comp/native.c" "XNULL_COMPANIONS=1"
run_case "tests/b3/fixtures/xdk/runtime.x" ""
run_case "tests/b3/fixtures/xdk/exit.x" ""

echo "xnullc-ffi 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
