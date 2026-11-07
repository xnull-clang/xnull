#!/usr/bin/env bash
# GEN-01 独立验收执行器：构建 main xnull（或 --bin），跑 26 项。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BIN=${XNULL_BIN:-}
while [ $# -gt 0 ]; do
    case "$1" in
        --bin) BIN=$2; shift 2 ;;
        --root) ROOT=$(cd "$2" && pwd); shift 2 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done
if [ -z "$BIN" ]; then
    BIN=$HERE/.bin/xnull
    mkdir -p "$HERE/.bin"
    ( cd "$ROOT/impl" && go build -o "$BIN" ./cmd/xnull ) || exit 2
fi
python3 "$HERE/run_gen01.py" "$BIN" "$ROOT"
