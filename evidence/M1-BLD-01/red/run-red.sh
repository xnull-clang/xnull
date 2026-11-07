#!/bin/sh
# BLD-01 红证据执行器（只读）
#
# 边界：
#   - 不修改 impl/**；只在 /tmp 构建 xnull 二进制；
#   - 期望值来自规范（cases.tsv），不来自实现；
#   - 每条记录：期望 vs 实际 + 程序退出码 + 原始 stdout/stderr + 耗时。
#
# 用法：sh evidence/M1-BLD-01/red/run-red.sh
# 产物：evidence/M1-BLD-01/red/results/{<id>.out,<id>.err,<id>.exit,<id>.time,<id>.expected,summary.tsv,summary.txt,env.txt}
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)   # wt/c2-rd2
IMPL="$ROOT/impl"
BIN=${XNULL_BIN:-/tmp/xnull-bld01-bld01}
RES="$HERE/results"
FIX="$HERE/fixtures"
CASES="$HERE/cases.tsv"

mkdir -p "$RES"
rm -f "$RES"/*.out "$RES"/*.err "$RES"/*.exit "$RES"/*.time "$RES"/*.expected "$RES"/summary.tsv "$RES"/summary.txt "$RES"/env.txt

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

echo "构建 xnull -> $BIN"
( cd "$IMPL" && go build -o "$BIN" ./cmd/xnull ) || { echo "BUILD FAIL"; exit 2; }

# 预热：首次执行新建二进制可能触发系统扫描，不计入任何用例耗时。
( cd "$ROOT" && "$BIN" run --interp "$FIX/c01_string_members.x" ) >/dev/null 2>&1 || true

{
    echo "time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "root=$ROOT"
    echo "git_sha=$(git -C "$ROOT" rev-parse HEAD)"
    echo "git_branch=$(git -C "$ROOT" branch --show-current)"
    echo "go=$(go version)"
    echo "cc=$(cc --version | head -1)"
    echo "bin=$BIN"
    echo "bin_sha256=$(shasum -a 256 "$BIN" | awk '{print $1}')"
    echo "uname=$(uname -srm)"
} > "$RES/env.txt"

TOTAL=0
RED=0
GREEN=0
: > "$RES/summary.tsv"
{
    echo "# BLD-01 红证据（期望取自规范；实际为本轮运行）"
    echo "# 列：id	判定	期望退出	实际退出	耗时ms	说明"
} > "$RES/summary.txt"
{
    printf 'id\tstatus\texpect_exit\tactual_exit\telapsed_ms\tnote\treason\n'
} > "$RES/summary.tsv"

TAB=$(printf '\t')
while IFS="$TAB" read -r id fixture exp_exit exp_out max_ms note; do
    case "$id" in ''|\#*) continue ;; esac
    TOTAL=$((TOTAL + 1))

    t0=$(now_ms)
    ( cd "$ROOT" && "$BIN" run --interp "$FIX/$(basename "$fixture")" ) > "$RES/$id.out" 2> "$RES/$id.err"
    code=$?
    t1=$(now_ms)
    elapsed=$((t1 - t0))

    printf '%s\n' "$code" > "$RES/$id.exit"
    printf '%s\n' "$elapsed" > "$RES/$id.time"

    status=GREEN
    reason=""

    if [ "$exp_exit" = "nonzero" ]; then
        if [ "$code" -eq 0 ]; then
            status=RED
            reason="期望非零退出（编译错误），实际 0"
        fi
        if ! grep -q 'error\[' "$RES/$id.err"; then
            status=RED
            reason="$reason; stderr 未含诊断码 error["
        fi
    else
        if [ "$code" -ne "$exp_exit" ]; then
            status=RED
            reason="期望 exit=${exp_exit}，实际 ${code}"
        fi
        if [ "$exp_out" != "-" ]; then
            printf '%b' "$exp_out" > "$RES/$id.expected"
            if ! cmp -s "$RES/$id.expected" "$RES/$id.out"; then
                status=RED
                reason="$reason; stdout 与期望不一致"
            fi
        fi
        if [ "$max_ms" != "0" ] && [ "$elapsed" -gt "$max_ms" ]; then
            status=RED
            reason="$reason; 耗时 ${elapsed}ms > 上限 ${max_ms}ms"
        fi
    fi

    if [ "$status" = "RED" ]; then
        RED=$((RED + 1))
    else
        GREEN=$((GREEN + 1))
    fi

    printf '%-4s %-26s exit=%-3s %6sms  %s\n' "$status" "$id" "$code" "$elapsed" "$reason" | tee -a "$RES/summary.txt"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$status" "$exp_exit" "$code" "$elapsed" "$note" "$reason" >> "$RES/summary.tsv"

    if [ "$status" = "RED" ] && [ "$exp_out" != "-" ] && [ -f "$RES/$id.expected" ]; then
        {
            echo "---- $id stdout diff (expected vs actual) ----"
            diff -u "$RES/$id.expected" "$RES/$id.out" | head -16
            echo
        } >> "$RES/summary.txt"
    fi
done < "$CASES"

{
    echo
    echo "TOTAL=$TOTAL RED=$RED GREEN=$GREEN"
    echo "证据目录：$HERE"
    echo "用例表：$CASES"
    echo "原始输出：$RES/<id>.{out,err,exit,time}"
} | tee -a "$RES/summary.txt"

exit 0
