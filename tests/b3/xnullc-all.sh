#!/usr/bin/env bash
# B3-09 全量门禁入口。用法：
#   xnullc-all.sh [--shard k/n] [--parallel N] [--go-bin P] [--xnullc P]
#   xnullc-all.sh [--rebuild]                    # 强制重建默认二进制
#   xnullc-all.sh --all-shards N [--parallel N]   # 跑全部 shard 后聚合
#   xnullc-all.sh --aggregate                     # 聚合已有 shard 结果
#   xnullc-all.sh --inline-args                   # 兼容旧位置参数（K-07 合同 1.1）
# 默认把 AST/bundle 写临时文件，走 K-07 文件形态（合同 1.2）。
#
# 二进制新鲜度（门禁硬规则）：默认二进制路径带 git HEAD 短 SHA（每个提交一份），
# 不存在才构建；--rebuild 强制重建。显式传入 --go-bin/--xnast-bin 或设置
# XNULL_BIN/XNAST_BIN 时由调用方保证新鲜度（门禁脚本不静默复用无版本的旧二进制）。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
REV=$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo work)
D_GO=${XNULL_BIN:-/tmp/xnull-b3-all-$REV}
D_XNAST=${XNAST_BIN:-/tmp/xnast-b3-all-$REV}
GO_BIN=""; XNAST_BIN=""; rebuild=0; all=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --all-shards) all=$2; shift 2;;
    --rebuild) rebuild=1; shift;;
    --go-bin) GO_BIN=$2; shift 2;;
    --xnast-bin) XNAST_BIN=$2; shift 2;;
    *) args+=("$1"); shift;;
  esac
done
[ -n "$GO_BIN" ] || GO_BIN=$D_GO
[ -n "$XNAST_BIN" ] || XNAST_BIN=$D_XNAST
# --rebuild 只强制重建默认（版本化）路径；显式外部二进制不覆盖。
if [ "$rebuild" = 1 ]; then
  [ "$GO_BIN" = "$D_GO" ] && rm -f "$GO_BIN"
  [ "$XNAST_BIN" = "$D_XNAST" ] && rm -f "$XNAST_BIN"
fi
if [ ! -x "$GO_BIN" ]; then ( cd "$ROOT/impl" && go build -o "$GO_BIN" ./cmd/xnull ) || exit 1; fi
if [ ! -x "$XNAST_BIN" ]; then ( cd "$ROOT/impl" && go build -o "$XNAST_BIN" ./cmd/xnast ) || exit 1; fi
if [ -n "$all" ]; then
  rc=0
  for k in $(seq 1 "$all"); do
    python3 "$HERE/xnullc_all.py" --root "$ROOT" --go-bin "$GO_BIN" --xnast-bin "$XNAST_BIN" --shard "$k/$all" "${args[@]}" || rc=1
  done
  python3 "$HERE/xnullc_all.py" --root "$ROOT" --go-bin "$GO_BIN" --xnast-bin "$XNAST_BIN" --aggregate "${args[@]}" || rc=1
  exit $rc
fi
exec python3 "$HERE/xnullc_all.py" --root "$ROOT" --go-bin "$GO_BIN" --xnast-bin "$XNAST_BIN" "${args[@]}"
