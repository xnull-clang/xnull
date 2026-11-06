#!/usr/bin/env bash
# ci/run.sh — XNull CI 唯一入口
#
# 用法：
#   bash ci/run.sh              顺序执行 10 项
#   bash ci/run.sh --list       只列 10 项
#   bash ci/run.sh --only 02    只跑第 02 项
#
# 退出码：全部 PASS=0；任一 FAIL=1；无 PASS 且只有 SKIP=2。
#
# 本轮实现范围：01–03 真实现，04–09 为 SKIP 桩（不伪装 PASS），10 文件名扫描（S0-04b/S1-22 门禁）真实现。

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMPL="$ROOT/impl"
. "$ROOT/ci/lib.sh"

CI_OUT_DIR=${CI_OUT_DIR:-"$ROOT/ci/.out"}
mkdir -p "$CI_OUT_DIR"
: > "$CI_OUT_DIR/steps.jsonl"
ci_color_init

# ---------- 步骤表 ----------
STEP_IDS="01 02 03 04 05 06 07 08 09 10"
step_name() {
  case "$1" in
    01) echo "gofmt+vet" ;;
    02) echo "go test -timeout 120s ./..." ;;
    03) echo "C 运行时构建" ;;
    04) echo "示例双路径" ;;
    05) echo "check_specs 六检" ;;
    06) echo "台账再生成 diff" ;;
    07) echo "泄漏扫描" ;;
    08) echo "产物与 sha" ;;
    09) echo "汇总 JSON" ;;
    10) echo "文件名扫描（禁旧扩展名）" ;;
    *)  echo "unknown" ;;
  esac
}

do_list() {
  for _id in $STEP_IDS; do
    printf '%s %s\n' "$_id" "$(step_name "$_id")"
  done
}

# ---------- 01 gofmt + go vet ----------
step_01() {
  run_step 01 "gofmt+vet" "$IMPL" '
    unformatted=$(gofmt -l .) || exit 1
    if [ -n "$unformatted" ]; then
      echo "gofmt 未通过的 Go 文件："
      echo "$unformatted"
      exit 1
    fi
    go vet ./...
  '
}

# ---------- 02 go test ----------
step_02() {
  run_step 02 "go test -timeout 120s ./..." "$IMPL" 'go test -timeout 120s ./...'
}

# ---------- 03 C 运行时构建 ----------
step_03() {
  run_step 03 "C 运行时构建" "$IMPL" 'sh ./runtime/build_rt.sh'
}

# ---------- 04–09：本轮为 SKIP 桩 ----------
step_04() {
  skip_step 04 "示例双路径" "S0-04 桩：本轮只实现 01–03，未实现"
}
step_05() {
  skip_step 05 "check_specs 六检" "S0-04 桩：本轮只实现 01–03，未实现"
}
step_06() {
  skip_step 06 "台账再生成 diff" "S0-04 桩：本轮只实现 01–03，未实现"
}
step_07() {
  skip_step 07 "泄漏扫描" "S0-04 桩：本轮只实现 01–03，未实现"
}
step_08() {
  skip_step 08 "产物与 sha" "S0-04 桩：本轮只实现 01–03，未实现"
}
step_09() {
  skip_step 09 "汇总 JSON" "S0-04 桩：汇总由 run.sh 自身输出，第 09 项待实现"
}

# ---------- 10 文件名扫描（S1-22 门禁） ----------
# 判据（董事会令 S1-22 第 3 条第 1、3 项）：
#   1) 仓库根递归不得存在旧扩展名文件（排除 .git、wt/、xnull/）；
#   2) 活引用 git grep '点 x n + 词边界'（即旧扩展名正则）排除 日志/收件箱/evidence 后必须为 0。
# 注意：旧扩展名在本文件里**不写成字面量**——否则本项会匹配到自身的规则定义。
# 下面用相邻引号拼接出「点 x n」与「点 x n + 词边界」。
step_10() {
  OLD_EXT='.x''n'
  REF_RE='\.x''n\b'
  export OLD_EXT REF_RE
  run_step 10 "文件名扫描（禁旧扩展名）" "$ROOT" '
    hits=$(find . -path ./.git -prune -o -path ./wt -prune -o -path ./xnull -prune -o -name "*$OLD_EXT" -print)
    if [ -n "$hits" ]; then
      echo "发现旧扩展名文件（S1-22 后应为 0）："
      echo "$hits"
      exit 1
    fi
    refs=$(git grep -n "$REF_RE" -- ":!日志/**" ":!收件箱/**" ":!evidence/**" || true)
    if [ -n "$refs" ]; then
      echo "发现旧扩展名活引用（S1-22 后应为 0）："
      echo "$refs"
      exit 1
    fi
    echo "旧扩展名文件 0，活引用 0"
  '
}

run_one() {
  case "$1" in
    01) step_01 ;;
    02) step_02 ;;
    03) step_03 ;;
    04) step_04 ;;
    05) step_05 ;;
    06) step_06 ;;
    07) step_07 ;;
    08) step_08 ;;
    09) step_09 ;;
    10) step_10 ;;
    *)  printf '未知步骤：%s\n' "$1" >&2; return 64 ;;
  esac
}

usage() {
  cat <<'EOF'
用法：bash ci/run.sh [--list] [--only NN]

  --list      只列 10 项，不执行
  --only NN   只执行第 NN 项（01–10）

退出码：全部 PASS=0；任一 FAIL=1；无 PASS 且只有 SKIP=2。
EOF
}

main() {
  _main_start=$(ci_now_ms)
  _only=""
  _mode="run"

  while [ $# -gt 0 ]; do
    case "$1" in
      --list) _mode="list"; shift ;;
      --only)
        shift
        if [ $# -eq 0 ]; then printf -- '--only 缺少步骤号\n' >&2; return 64; fi
        _only=$1; shift
        ;;
      --only=*) _only=${1#--only=}; shift ;;
      -h|--help) usage; return 0 ;;
      *) printf '未知参数：%s\n' "$1" >&2; usage >&2; return 64 ;;
    esac
  done

  if [ "$_mode" = "list" ]; then
    do_list
    return 0
  fi

  if [ -n "$_only" ]; then
    case "$_only" in
      [0-9]) _only="0$_only" ;;
    esac
    case "$_only" in
      01|02|03|04|05|06|07|08|09|10) ;;
      *) printf '未知步骤：%s（应为 01–10）\n' "$_only" >&2; return 64 ;;
    esac
    printf 'XNull CI（单步 %s）  工作树=%s\n\n' "$_only" "$ROOT"
    run_one "$_only"
    ci_summary "$_main_start"
    return $?
  fi

  printf 'XNull CI  工作树=%s\n' "$ROOT"
  printf '日志目录=%s\n\n' "$CI_OUT_DIR"
  for _id in $STEP_IDS; do
    run_one "$_id"
  done
  ci_summary "$_main_start"
  return $?
}

main "$@"
