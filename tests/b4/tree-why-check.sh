#!/usr/bin/env bash
# B4b-04a 自检：tree / why 输出与 Go golden 逐字节一致。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
S="$HERE/xnull-build.sh"
P="$HERE/fixtures/proj02/app-main"
pass=0 fail=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

cmp_case() { # 名称 命令输出文件 golden
  local name=$1 got=$2 want=$3
  if diff -u "$want" "$got" > /tmp/tree-why.diff 2>&1; then
    ok "$name"
  else
    bad "$name"; head -8 /tmp/tree-why.diff
  fi
}

"$S" tree "$P" > /tmp/tree-why-tree.out 2>/tmp/tree-why-tree.err \
  && cmp_case "tree（模块/传递依赖/缩进）" /tmp/tree-why-tree.out "$HERE/fixtures/proj02/tree.golden" \
  || bad "tree 执行失败"

for c in lib-core lib-codec lib-util; do
  "$S" why "$P" "io.xnull:$c" > "/tmp/tree-why-why-$c.out" 2>&1 \
    && cmp_case "why $c" "/tmp/tree-why-why-$c.out" "$HERE/fixtures/proj02/why-$c.golden" \
    || bad "why $c 执行失败"
done

# 负例：未解析坐标
out=$("$S" why "$P" io.xnull:nope 2>&1); rc=$?
if [ $rc -eq 2 ] && printf '%s' "$out" | grep -q '未被解析'; then
  ok "why 未解析坐标退出 2"
else
  bad "why 未解析坐标（rc=$rc）"
fi

echo "B4b-04a tree/why 自检：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
