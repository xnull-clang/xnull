#!/usr/bin/env bash
# B4b-04b-2 自检：repro 两次构建哈希一致；xmeta 字段与 Go golden 一致。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
S="$HERE/xnull-build.sh"
P="$HERE/fixtures/proj02"
pass=0 fail=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# repro：同一次运行里两次构建的 C/对象/app 全部相同
if out=$("$S" repro "$P" 2>&1); then
  n=$(printf '%s\n' "$out" | grep -c '^same	')
  if printf '%s' "$out" | grep -q 'diff=0' && [ "$n" -ge 9 ]; then
    ok "repro 两次构建一致（$n 个产物）"
  else
    bad "repro 汇总异常"; printf '%s\n' "$out" | tail -5
  fi
else
  bad "repro 存在差异"; printf '%s\n' "$out" | grep '^diff' | head -5
fi

# xmeta：生成后与 Go golden 比对（去掉 XNull 扩展字段）
dir=$("$S" xmeta "$P" 2>/dev/null | tail -1)
got="$dir/app-main-1.0.0.xmeta"
if [ -f "$got" ]; then
  grep -v -e 'entryFile' -e 'dependencies' "$got" > /tmp/repro-xmeta.got
  if diff -u "$P/expected-app-main.xmeta" /tmp/repro-xmeta.got > /tmp/repro-xmeta.diff 2>&1; then
    ok "xmeta 16 字段与 Go 一致（app-main）"
  else
    bad "xmeta 与 Go 不一致"; head -10 /tmp/repro-xmeta.diff
  fi
  if grep -q 'entryFile' "$got" && grep -q 'dependencies' "$got"; then
    ok "xmeta 含扩展字段 entryFile/dependencies"
  else
    bad "xmeta 缺扩展字段"
  fi
else
  bad "xmeta 未生成"
fi

# 模块元数据数量：4 模块 + 聚合根
n=$(ls "$dir"/*.xmeta 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" -eq 5 ]; then ok "共生成 5 个 .xmeta"; else bad "xmeta 数量=$n（期望 5）"; fi

echo "B4b-04b-2 repro/xmeta 自检：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
