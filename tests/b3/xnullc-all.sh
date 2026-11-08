#!/usr/bin/env bash
# B3-09 全量门禁入口。用法：
#   xnullc-all.sh [--shard k/n] [--parallel N] [--go-bin P] [--xnullc P]
#   xnullc-all.sh --all-shards N [--parallel N]   # 跑全部 shard 后聚合
#   xnullc-all.sh --aggregate                     # 聚合已有 shard 结果
#   xnullc-all.sh --inline-args                   # 兼容旧位置参数（K-07 合同 1.1）
# 默认把 AST/bundle 写临时文件，走 K-07 文件形态（合同 1.2）。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
GO_BIN=${XNULL_BIN:-/tmp/xnull-b3-all}
XNAST_BIN=${XNAST_BIN:-/tmp/xnast-b3-all}
if [ ! -x "$GO_BIN" ]; then ( cd "$ROOT/impl" && go build -o "$GO_BIN" ./cmd/xnull ) || exit 1; fi
if [ ! -x "$XNAST_BIN" ]; then ( cd "$ROOT/impl" && go build -o "$XNAST_BIN" ./cmd/xnast ) || exit 1; fi
args=(); all=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all-shards) all=$2; shift 2;;
    *) args+=("$1"); shift;;
  esac
done
if [ -n "$all" ]; then
  rc=0
  for k in $(seq 1 "$all"); do
    python3 "$HERE/xnullc_all.py" --root "$ROOT" --go-bin "$GO_BIN" --xnast-bin "$XNAST_BIN" --shard "$k/$all" "${args[@]}" || rc=1
  done
  python3 "$HERE/xnullc_all.py" --root "$ROOT" --go-bin "$GO_BIN" --xnast-bin "$XNAST_BIN" --aggregate "${args[@]}" || rc=1
  exit $rc
fi
exec python3 "$HERE/xnullc_all.py" --root "$ROOT" --go-bin "$GO_BIN" --xnast-bin "$XNAST_BIN" "${args[@]}"
