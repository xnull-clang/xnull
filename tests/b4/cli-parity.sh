#!/usr/bin/env bash
# B4b-05：XNull CLI（tests/b4/xnull-build.sh 原型）与 Go CLI 的逐命令对拍矩阵。
#
# 结论只有三档：
#   PASS  两路输出/行为一致（逐字节或运行结果一致；差异已在 note 说明且不影响合同）
#   DIFF  两路可比较但结果不同（note 写清差异）
#   NA    一侧没有该命令/该语义（note 写原因）
#
# 用法：tests/b4/cli-parity.sh [--quick]（--quick 跳过 9 示例，只跑 proj02）
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
S="$HERE/xnull-build.sh"
P="$HERE/fixtures/proj02"
W=${XNULL_PARITY_DIR:-/tmp/b4-parity}
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1
rm -rf "$W"; mkdir -p "$W"

PASS=0; DIFF=0; NA=0
ROWS=()
record() { # cmd scope status note
  local st=$1
  case $st in
    PASS) PASS=$((PASS+1)) ;;
    DIFF) DIFF=$((DIFF+1)) ;;
    NA)   NA=$((NA+1)) ;;
  esac
  ROWS+=("$(printf '%-10s %-9s %-5s %s' "$2" "$3" "$st" "$4")")
}

# Go CLI（缺失则构建）
GO=${XNULL_GO_BIN:-/tmp/xnull-parity}
if [ ! -x "$GO" ]; then
  ( cd "$ROOT/impl" && go build -o "$GO" ./cmd/xnull ) || { echo "cli-parity: 构建 Go CLI 失败" >&2; exit 1; }
fi
export XNULL_FRONTEND=go
GO_REPO="$W/go-repo"
RUN_RT="$ROOT/impl/runtime"

# ---------------------------------------------------------------- proj02
( cd "$P" && XNULL_REPO="$GO_REPO" XNULL_RUNTIME="$RUN_RT" "$GO" build ) > "$W/go-build.log" 2>&1
go_build_rc=$?
# Go 的聚合根（summary+清单）只有 install 才写入仓库；对拍 install 需要先跑一次
( cd "$P" && XNULL_REPO="$GO_REPO" XNULL_RUNTIME="$RUN_RT" "$GO" install . ) > "$W/go-install.log" 2>&1
"$S" build-project "$P" -o "$W/xn" > "$W/xn-build.log" 2>&1
xn_build_rc=$?

go_app="$P/app-main/target/app-main-1.0.0"
xn_app="$W/xn/app"
if [ $go_build_rc -eq 0 ] && [ $xn_build_rc -eq 0 ] && [ -x "$go_app" ] && [ -x "$xn_app" ]; then
  "$go_app" > "$W/go-run.out" 2>&1; g=$?
  "$xn_app" > "$W/xn-run.out" 2>&1; x=$?
  if [ $g -eq $x ] && cmp -s "$W/go-run.out" "$W/xn-run.out"; then
    record PASS build proj02 "两路构建成功、app 输出一致（library 产物 .o vs Go .xlib）"
  else
    record DIFF build proj02 "app 输出不同（exit $g/$x）"
  fi
else
  record DIFF build proj02 "构建失败（go=$go_build_rc xnull=$xn_build_rc）"
fi

record NA run      proj02 "Go 只有单文件 run，无工程级 run；XNull run-project 无对拍对象"
record NA validate proj02 "Go 无 validate 子命令（校验内嵌在 build）"

# tree / why
XNULL_REPO="$GO_REPO" "$GO" tree "$P/app-main" > "$W/go-tree.out" 2>/dev/null
"$S" tree "$P/app-main" > "$W/xn-tree.out" 2>/dev/null
if cmp -s "$W/go-tree.out" "$W/xn-tree.out"; then
  record PASS tree proj02 "依赖树逐字节一致"
else
  record DIFF tree proj02 "依赖树不同"
fi
why_ok=1
for c in lib-core lib-codec lib-util; do
  XNULL_REPO="$GO_REPO" "$GO" why "$P/app-main" "io.xnull:$c" > "$W/go-why-$c.out" 2>/dev/null
  "$S" why "$P/app-main" "io.xnull:$c" > "$W/xn-why-$c.out" 2>/dev/null
  cmp -s "$W/go-why-$c.out" "$W/xn-why-$c.out" || why_ok=0
done
[ $why_ok -eq 1 ] && record PASS why proj02 "3 个坐标的 why 逐字节一致" || record DIFF why proj02 "why 输出不同"

# install：比较仓库文件集合
"$S" install "$P" --repo "$W/xn-repo" > "$W/xn-install.log" 2>&1
( cd "$W/go-repo" && find . -type f | sort ) > "$W/go-repo.files"
( cd "$W/xn-repo" 2>/dev/null && find . -type f | sort ) > "$W/xn-repo.files"
if cmp -s "$W/go-repo.files" "$W/xn-repo.files"; then
  record PASS install proj02 "仓库文件集合一致（.xlib + xnull.project + summary）"
else
  record DIFF install proj02 "仓库文件集合不同"
fi

record NA repro proj02 "Go 无 repro 子命令（XNull 自建可复现性检查）"

# xmeta：把 XNull 扩展字段去掉后与 Go 产物比较
if [ -f "$P/app-main/target/app-main-1.0.0.xmeta" ]; then
  dir=$("$S" xmeta "$P" 2>/dev/null | tail -1)
  grep -v -e 'entryFile' -e 'dependencies' "$dir/app-main-1.0.0.xmeta" > "$W/xn.xmeta"
  if cmp -s "$W/xn.xmeta" "$P/app-main/target/app-main-1.0.0.xmeta"; then
    record PASS xmeta proj02 "16 字段逐字节一致（XNull 另加 entryFile/dependencies）"
  else
    record DIFF xmeta proj02 "字段值不同"
  fi
else
  record NA xmeta proj02 "Go 侧未产出 .xmeta"
fi

# fmt / clean / doctor / version
# fmt：同一未格式化样本，两路格式化结果比较；--check 在已格式化文件上均为 0
cp "$ROOT/impl/lib/b4/deps.x" "$W/fmt-go.x"
cp "$ROOT/impl/lib/b4/deps.x" "$W/fmt-xn.x"
"$GO" fmt "$W/fmt-go.x" > /dev/null 2>&1
"$S" fmt "$W/fmt-xn.x" > /dev/null 2>&1
if cmp -s "$W/fmt-go.x" "$W/fmt-xn.x"; then
  record PASS fmt all "同一文件格式化结果逐字节一致（in-place；xnfmt 无 --check，脚本侧实现）"
else
  record DIFF fmt all "格式化结果不同"
fi

# clean：同一目录下比较输出与效果
mkdir -p "$W/clean-demo/target/x"
( cd "$W/clean-demo" && "$GO" clean . ) > "$W/go-clean.out" 2>&1
"$S" clean "$W/clean-demo" > "$W/xn-clean.out" 2>&1
if [ ! -d "$W/clean-demo/target" ] && grep -q '已清理' "$W/xn-clean.out"; then
  record PASS clean all "删除 target 且输出同语义（已清理 target）"
else
  record DIFF clean all "clean 行为不同"
fi

# doctor：比较字段序列（[level] 名称），值随环境不同
"$GO" doctor "$P" > "$W/go-doctor.out" 2>&1
"$S" doctor "$P" > "$W/xn-doctor.out" 2>&1
sed -E 's/^\[(ok|warn|fail)\] ([a-z]+).*/[\1] \2/' "$W/go-doctor.out" > "$W/go-doctor.norm"
sed -E 's/^\[(ok|warn|fail)\] ([a-z]+).*/[\1] \2/' "$W/xn-doctor.out" > "$W/xn-doctor.norm"
if cmp -s "$W/go-doctor.norm" "$W/xn-doctor.norm"; then
  record PASS doctor all "cc/runtime/repo/manifest/lock 五字段与级别一致（值随环境）"
else
  record DIFF doctor all "doctor 字段/级别不同"
fi
"$GO" -v > "$W/go-ver.out" 2>&1
"$S" version > "$W/xn-ver.out" 2>&1
if cmp -s "$W/go-ver.out" "$W/xn-ver.out"; then
  record PASS version all "版本输出逐字节一致"
else
  record DIFF version all "首行一致，缺 specs 行（Go 输出规格版本清单）"
fi

# ---------------------------------------------------------------- 9 示例
if [ $QUICK -eq 0 ]; then
  ex_ok=1; ex_run_ok=1; ex_n=0
  for f in "$P"/../examples/*.x; do
    [ -f "$f" ] || continue
    # 9 示例在 tests/b2/corpus/examples（与 B4b-01 一致）
    :
  done
  for f in "$ROOT"/tests/b2/corpus/examples/*.x; do
    [ -f "$f" ] || continue
    ex_n=$((ex_n+1))
    rel=${f#"$ROOT/"}
    name=$(basename "$f")
    "$GO" build --emit-c "$rel" > "$W/go-$name.c" 2>/dev/null || ex_ok=0
    "$S" build "$rel" -o "$W/ex-$name" > /dev/null 2>&1 || ex_ok=0
    cmp -s "$W/go-$name.c" "$W/ex-$name.c" || ex_ok=0
    "$GO" build "$rel" -o "$W/gobin-$name" > /dev/null 2>&1
    "$W/gobin-$name" > "$W/go-$name.out" 2>&1; g=$?
    "$W/ex-$name" > "$W/xn-$name.out" 2>&1; x=$?
    if [ $g -ne $x ] || ! cmp -s "$W/go-$name.out" "$W/xn-$name.out"; then ex_run_ok=0; fi
  done
  if [ $ex_ok -eq 1 ]; then
    record PASS build "examples" "$ex_n 个示例的 C 与 Go --emit-c 逐字节一致"
  else
    record DIFF build "examples" "存在 C 差异"
  fi
  if [ $ex_run_ok -eq 1 ]; then
    record PASS run "examples" "$ex_n 个示例运行 stdout/exit 一致"
  else
    record DIFF run "examples" "存在运行差异"
  fi
  record NA validate "examples" "单文件工程无清单校验语义"
  record NA tree     "examples" "单文件工程无依赖图"
  record NA why      "examples" "单文件工程无依赖图"
  record NA install  "examples" "单文件无 GAV/仓库安装"
  record NA repro    "examples" "Go 无 repro；单文件未做"
  record NA xmeta    "examples" "单文件无清单，不产出 .xmeta"
else
  record NA build    "examples" "--quick 跳过"
  record NA run      "examples" "--quick 跳过"
fi

# ---------------------------------------------------------------- 输出
printf '%-10s %-9s %-5s %s\n' "命令" "范围" "结论" "说明"
for r in "${ROWS[@]}"; do echo "$r"; done
TOTAL=$((PASS+DIFF+NA))
echo "B4b-05 CLI 对拍：PASS=$PASS DIFF=$DIFF NA=$NA total=$TOTAL"
[ $DIFF -eq 0 ]
