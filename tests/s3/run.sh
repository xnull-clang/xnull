#!/usr/bin/env bash
# S3 参考用例执行器（E2 提供，QA 独立复验用）
# 用法：bash tests/s3/run.sh --root <repo> [--bin <xnull>]
# 默认解释路径；--compiled 同时跑编译路径（MEM-05/06 编译面可能 BLOCKED）。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
MODE=interp
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT=$(cd "$2" && pwd); shift 2;;
    --bin) BIN=$2; shift 2;;
    --compiled) MODE=both; shift;;
    *) echo "未知参数：$1" >&2; exit 2;;
  esac
done
[ -z "$BIN" ] && { ( cd "$ROOT/impl" && go build -o /tmp/xnull-s3-ref ./cmd/xnull ) || exit 1; BIN=/tmp/xnull-s3-ref; }
pass=0 fail=0
for g in mem05 mem06 mem03; do
  for f in "$HERE/$g"/*.x; do
    n=$(basename "$f" .x)
    out=$("$BIN" run --interp "$f" 2>/tmp/s3.err); rc=$?
    want=$(cat "$HERE/$g/$n.expect")
    if [ "$rc" -eq 0 ] && [ "$out" = "$want" ]; then
      echo "PASS  $g/$n  interp=$out"; pass=$((pass+1))
    else
      echo "FAIL  $g/$n  rc=$rc out=$out want=$want err=$(head -1 /tmp/s3.err)"; fail=$((fail+1))
    fi
    if [ "$MODE" = both ]; then
      cout=$("$BIN" run "$f" 2>/tmp/s3c.err); crc=$?
      if [ "$crc" -eq 0 ] && [ "$cout" = "$want" ]; then
        echo "PASS  $g/$n  compiled=$cout"
      else
        echo "BLOCKED/FAIL  $g/$n  compiled rc=$crc err=$(head -1 /tmp/s3c.err)"
      fi
    fi
  done
done
echo "汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
