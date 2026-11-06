#!/bin/sh
# B0-02（P-10）自动驱动：一条命令复现红→绿与样例。
#   1) 红：旧 4 源清单链接 ABI/STD 样例 → 失败
#   2) 绿：新 8 源清单链接同一样例 → 通过并运行
#   3) 样例：xnull build 产物确实包含 xrt_/xdkc_ 符号（ABI/STD 已进链接清单）
#   4) 回归：go vet / go test / build_rt
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RT="$ROOT/impl/runtime"
P="$ROOT/evidence/B0-02/probe/probe.c"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0

echo "== 1 红：旧 4 源清单（rt.c rt_gc.c rt_policy.c rt_weak.c） =="
if cc -std=c11 -O2 -I "$RT" -o "$TMP/probe-old" "$P" \
      "$RT/rt.c" "$RT/rt_gc.c" "$RT/rt_policy.c" "$RT/rt_weak.c" >"$TMP/old.log" 2>&1; then
  echo "FAIL：旧清单不应通过"; fail=1
else
  echo "PASS：旧清单链接失败（预期红）"
  grep -m3 'undefined\|_xrt_\|_xdkc_' "$TMP/old.log" || true
fi

echo
echo "== 2 绿：新 8 源清单 =="
if cc -std=c11 -O2 -I "$RT" -o "$TMP/probe-new" "$P" \
      "$RT/rt.c" "$RT/rt_gc.c" "$RT/rt_policy.c" "$RT/rt_weak.c" \
      "$RT/xrt_abi.c" "$RT/rt_std_runtime.c" "$RT/rt_std_text.c" "$RT/rt_std_sys.c" \
      >"$TMP/new.log" 2>&1; then
  "$TMP/probe-new" || fail=1
else
  echo "FAIL：新清单链接失败"; cat "$TMP/new.log"; fail=1
fi

echo
echo "== 3 样例：xnull build 产物包含 ABI/STD 符号 =="
( cd "$ROOT/impl" && go build -o "$TMP/xnull" ./cmd/xnull ) || fail=1
"$TMP/xnull" build "$ROOT/examples/hello.x" -o "$TMP/hello" -l m -L /usr/lib -l m || fail=1
"$TMP/hello"
n=$(nm "$TMP/hello" | grep -c '_xrt_\|_xdkc_')
echo "产物内 xrt_/xdkc_ 符号数：$n"
[ "$n" -gt 0 ] || { echo "FAIL：产物不含 ABI/STD 符号"; fail=1; }

echo
echo "== 4 回归 =="
( cd "$ROOT/impl" && go vet ./... ) || fail=1
( cd "$ROOT/impl" && go test ./internal/codegen ./internal/codegen/ffi ./internal/cli -count=1 -timeout 300s ) || fail=1
sh "$ROOT/impl/runtime/build_rt.sh" >/dev/null 2>&1 && echo "build_rt.sh：PASS" || { echo "build_rt.sh：FAIL"; fail=1; }

echo
[ "$fail" -eq 0 ] && echo "B0-02 驱动：全部通过" || echo "B0-02 驱动：存在失败"
exit "$fail"
