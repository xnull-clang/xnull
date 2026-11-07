#!/usr/bin/env bash
# 一次跑完 GEN-01 / NEG-01 / PKG-01，汇总退出码。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SHA=main
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --sha) SHA=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        -h|--help) sed -n '1,10p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

rc=0
bash "$HERE/run-gen.sh" --sha "$SHA" ${OUT:+--out "$OUT"} || rc=1
bash "$HERE/run-neg.sh" --sha "$SHA" ${OUT:+--out "$OUT"} || rc=1
bash "$HERE/run-pkg.sh" --sha "$SHA" ${OUT:+--out "$OUT"} || rc=1
exit "$rc"
