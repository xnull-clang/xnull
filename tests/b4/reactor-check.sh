#!/usr/bin/env bash
# B4b-03b-1 自检：proj02 聚合构建 → 运行输出与 golden 一致；库对象存在。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
S="$HERE/xnull-build.sh"
OUT=${XNULL_B4_OUT:-/tmp/b4-proj-proj02}
pass=0 fail=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

got=$("$S" run-project "$HERE/fixtures/proj02" 2>/dev/null)
want=$(cat "$HERE/fixtures/proj02/expected.app.out")
if [ "$got" = "$want" ]; then
  ok "proj02 运行输出与 golden 一致"
else
  bad "proj02 运行输出不一致"
  diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | head -10
fi

for o in lib_core.o lib_codec.o; do
  if [ -f "$OUT/$o" ]; then ok "库对象存在 $o"; else bad "缺少库对象 $o"; fi
done
if [ -x "$OUT/app" ]; then ok "app 产物可执行"; else bad "缺少 app 产物"; fi

# B4b-03b-2：资源表与产物落盘
if [ -f "$OUT/res.c" ] && grep -q 'app.txt' "$OUT/res.c" && grep -q 'settings.ini' "$OUT/res.c"; then
  ok "资源表包含 app.txt / settings.ini"
else
  bad "资源表缺少资源条目"
fi
if nm "$OUT/app" 2>/dev/null | grep -q '_xrt_resource_get'; then
  ok "app 链接了资源表符号"
else
  bad "app 未链接资源表"
fi
if [ -f "$HERE/fixtures/proj02/target/app-main-1.0.0" ]; then
  ok "产物已落盘 target/app-main-1.0.0"
else
  bad "缺少 target/app-main-1.0.0"
fi

echo "B4b-03b-2 聚合构建自检：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
