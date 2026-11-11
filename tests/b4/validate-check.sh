#!/usr/bin/env bash
# B4b-03a 自检：validate 输出与 Go oracle golden 一致；负例必须报错。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
S="$HERE/xnull-build.sh"
pass=0 fail=0

ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# 正例：聚合工程 proj02
got=$("$S" validate "$HERE/fixtures/proj02" 2>&1 | grep -v '^validate:' | grep -v '^#')
want=$(grep -v '^#' "$HERE/fixtures/proj02/expected.model.tsv")
if [ "$(printf '%s\n' "$got" | sort)" = "$(printf '%s\n' "$want" | sort)" ]; then
  ok "proj02 模型与 Go oracle 一致"
else
  bad "proj02 模型与 Go oracle 不一致"
  diff <(printf '%s\n' "$want" | sort) <(printf '%s\n' "$got" | sort) | head -10
fi

# 正例：单模块（非聚合）
if "$S" validate "$HERE/fixtures/proj02/lib-core" >/dev/null 2>&1; then
  ok "lib-core 单工程 validate"
else
  bad "lib-core 单工程 validate"
fi

# 负例：模块目录缺失
if "$S" validate "$HERE/fixtures/bad-module" >/dev/null 2>&1; then
  bad "bad-module 应失败"
else
  ok "bad-module 报错（模块目录不存在）"
fi

# 负例：依赖无版本
out=$("$S" validate "$HERE/fixtures/bad-dep" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$out" | grep -q '无版本'; then
  ok "bad-dep 报错（依赖无版本）"
else
  bad "bad-dep 应报依赖无版本"
fi

echo "B4b-03a validate 自检：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
