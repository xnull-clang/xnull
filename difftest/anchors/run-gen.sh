#!/usr/bin/env bash
# GEN-01 独立复验：导出 --sha 树 → 构建 xnull → 跑 QA1 自写 26 项。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
QA1=$(cd "$HERE/../.." && pwd)
REPO=$(git -C "$QA1" rev-parse --show-toplevel)
SHA=main
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --sha) SHA=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        -h|--help) sed -n '1,12p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

T=$(mktemp -d "${TMPDIR:-/tmp}/qa1-gen.XXXXXX")
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/src"
git -C "$REPO" archive "$SHA" | tar -x -C "$T/src" || exit 2
( cd "$T/src/impl" && go build -o "$T/xnull" ./cmd/xnull ) || exit 2

LOG=$T/gen.out
bash "$QA1/difftest/gen01/run.sh" --bin "$T/xnull" --root "$T/src" >"$LOG" 2>&1
RC=$?

echo "===== GEN-01 @ $SHA"
cat "$LOG"
if [ -n "$OUT" ]; then
    mkdir -p "$OUT"
    cp "$LOG" "$OUT/gen01.log"
    echo "SHA=$SHA" > "$OUT/sha.txt"
    git -C "$REPO" rev-parse "$SHA" >> "$OUT/sha.txt"
fi
exit "$RC"
