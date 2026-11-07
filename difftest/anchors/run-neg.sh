#!/usr/bin/env bash
# NEG-01 复验：导出 --sha 树 → 注入台账 60 项检查表 → go test ./Tests。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
QA1=$(cd "$HERE/../.." && pwd)
REPO=$(git -C "$QA1" rev-parse --show-toplevel)
SHA=main
NEG_REF=pod/c3-rd3
NEG_PATH=impl/Tests/neg_test.go
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --sha) SHA=$2; shift 2 ;;
        --neg-ref) NEG_REF=$2; shift 2 ;;
        --neg-path) NEG_PATH=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        -h|--help) sed -n '1,12p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

T=$(mktemp -d "${TMPDIR:-/tmp}/qa1-neg.XXXXXX")
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/src"
git -C "$REPO" archive "$SHA" | tar -x -C "$T/src" || exit 2
mkdir -p "$T/src/impl/Tests"
git -C "$REPO" show "$NEG_REF:$NEG_PATH" > "$T/src/impl/Tests/neg_test.go" || exit 2

LOG=$T/neg.out
( cd "$T/src/impl" && go test ./Tests -run '^TestDiagMatrixS1$' -count=1 -v ) >"$LOG" 2>&1
RC=$?

PASS=$(grep -c '^    --- PASS:' "$LOG" || true)
FAIL=$(grep -c '^    --- FAIL:' "$LOG" || true)
echo "===== NEG-01 @ ${SHA}（用例源 ${NEG_REF}:${NEG_PATH}）"
echo "PASS=$PASS / FAIL=$FAIL"
grep '^    --- FAIL:' "$LOG" || true
grep -E '^(ok|FAIL)[[:space:]]' "$LOG" || true
if [ -n "$OUT" ]; then
    mkdir -p "$OUT"
    cp "$LOG" "$OUT/neg01.log"
    { echo "SHA=$SHA"; git -C "$REPO" rev-parse "$SHA"; echo "NEG_REF=$NEG_REF"; } > "$OUT/neg01-sha.txt"
fi
exit "$RC"
