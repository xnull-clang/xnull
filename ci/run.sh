#!/usr/bin/env bash
# ci/run.sh — XNull CI 唯一入口（无 Go 版，B4c-02b）
#
# 用法：
#   bash ci/run.sh              执行全部步骤
#   bash ci/run.sh --list       只列步骤
#   bash ci/run.sh --only 02    只跑第 02 步
#
# 退出码：全部 PASS=0；任一 FAIL=1；无 PASS 且只有 SKIP=2。
#
# 说明：Go 构建/测试已随 B4c-02b 删除；依赖 Go oracle 的旧步骤保留为 SKIP（不伪装 PASS），
# 对应的 legacy 脚本在 tests/b3（仅存档，不作门禁）。

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/ci/lib.sh"

CI_OUT_DIR=${CI_OUT_DIR:-"$ROOT/ci/.out"}
mkdir -p "$CI_OUT_DIR"
: > "$CI_OUT_DIR/steps.jsonl"
ci_color_init

STEP_IDS="01 02 03 04 05 06 07 08 09"
step_name() {
  case "$1" in
    01) echo "xnfmt 格式检查（定向）" ;;
    02) echo "golden 验证（142/97/9）" ;;
    03) echo "C 运行时构建与测试" ;;
    04) echo "9 示例（bootstrap 路径）" ;;
    05) echo "文件名扫描（禁旧扩展名）" ;;
    06) echo "B2 双路径差分（legacy）" ;;
    07) echo "check_specs（legacy）" ;;
    08) echo "台账/汇总 JSON（legacy）" ;;
    09) echo "发布产物构建" ;;
    *)  echo "unknown" ;;
  esac
}

if [ "${1:-}" = "--list" ]; then
  for id in $STEP_IDS; do printf '%s  %s\n' "$id" "$(step_name "$id")"; done
  exit 0
fi
ONLY=""
if [ "${1:-}" = "--only" ]; then ONLY=${2:-}; fi

run() { # id cmd
  local id=$1 cmd=$2
  [ -n "$ONLY" ] && [ "$ONLY" != "$id" ] && return 0
  run_step "$id" "$(step_name "$id")" "$ROOT" "$cmd"
}
skip() { # id reason
  local id=$1 reason=$2
  [ -n "$ONLY" ] && [ "$ONLY" != "$id" ] && return 0
  skip_step "$id" "$(step_name "$id")" "$reason"
}

START=$(ci_now_ms)

# 01 xnfmt 格式检查：只查 XNull 工具链源码（impl/lib/b4），格式化器即 xnfmt 原生实现
run 01 '"$ROOT/bin/xnull" fmt --check impl/lib/b4/*.x'

# 02 golden：142 入口 C / 97 负例 / 9 示例
if [ -x "$ROOT/tests/b4/verify-golden.sh" ]; then
  run 02 '"$ROOT/tests/b4/verify-golden.sh"'
else
  skip 02 "verify-golden.sh 尚未就绪（B4c-03）"
fi

# 03 C 运行时（cc 全量测试）
run 03 'sh impl/runtime/build_rt.sh'

# 04 9 示例（引导路径，不依赖 Go）
run 04 'env XNULL_USE_BOOTSTRAP=1 "$ROOT/bin/xnull" examples'

# 05 文件名扫描：仓库内禁止旧扩展名（.pyc/.o/.a 等构建残留；.c/.x/.md 允许）
run 05 'bash -c "! find . -path ./bootstrap/bin -prune -o -path ./.git -prune -o \
  \( -name \"*.pyc\" -o -name \"*.o\" -o -name \"*.a\" \) -print | grep -q ."'

# 06–08：依赖被删除的 Go 工具链（oracle/devtool/台账），保留 SKIP 不伪装通过
skip 06 "B2 差分需要 Go oracle（已删除）；legacy 脚本在 tests/b3/b2-*"
skip 07 "check_specs 由 internal/devtool 实现（Go 已删除）"
skip 08 "台账/SSOT 汇总由董事会脚本维护，不在本仓库 CI 范围"

# 09 发布产物（bootstrap + 统一 CLI）
run 09 '"$ROOT/scripts/build_release.sh"'

ci_summary "$START"
