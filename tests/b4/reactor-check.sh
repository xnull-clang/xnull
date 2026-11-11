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

echo "B4b-03b-1 聚合构建自检：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
