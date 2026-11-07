#!/usr/bin/env bash
# EXP-004 黄金用例库执行器：规范构造 × 路径矩阵 + AST 快照
# 判据：解释/编译两条路径 stdout 与退出码逐字节一致；AST S 表达式与快照一致。
# 示例集只做回归，本库不引用 examples/。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BIN=${XNULL_BIN:-$HERE/.bin/xnull}
AST=${ASTDUMP_BIN:-$HERE/.bin/astdump}
CAT=$HERE/catalog.tsv
OUT=$HERE/.out
LEDGER=$ROOT/XNull一致性用例台账-v1.0.0.md
pass=0
fail=0
covered=()

while [ $# -gt 0 ]; do
    case "$1" in
        --bin) BIN=$2; shift 2 ;;
        --ast) AST=$2; shift 2 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

[ -x "$BIN" ] || { echo "缺少 xnull：$BIN（先跑 golden/build-tools.sh）" >&2; exit 2; }
[ -x "$AST" ] || { echo "缺少 astdump：$AST（先跑 golden/build-tools.sh）" >&2; exit 2; }
rm -rf "$OUT"; mkdir -p "$OUT"

while IFS=$'\t' read -r anchor case note; do
    case "$anchor" in ''|'#'*) continue ;; esac
    dir=$HERE/cases/$case
    [ -d "$dir" ] || { echo "FAIL  缺失用例目录 $case"; fail=$((fail+1)); continue; }
    covered+=("$anchor")
    o=$OUT/$case; mkdir -p "$o"

    ( cd "$ROOT" && "$BIN" run --interp "$dir/src.x" ) >"$o/interp.out" 2>"$o/interp.err"; ie=$?
    ( cd "$ROOT" && "$BIN" run "$dir/src.x" ) >"$o/compiled.out" 2>"$o/compiled.err"; ce=$?
    "$AST" "$dir/src.x" >"$o/ast.out" 2>"$o/ast.err"; ae=$?

    want_exit=$(cat "$dir/exit.txt")
    ok=1; why=""
    [ "$ie" = "$want_exit" ] || { ok=0; why="$why 解释 exit=$ie"; }
    [ "$ce" = "$want_exit" ] || { ok=0; why="$why 编译 exit=$ce"; }
    cmp -s "$dir/stdout.txt" "$o/interp.out" || { ok=0; why="$why 解释 stdout"; }
    cmp -s "$dir/stdout.txt" "$o/compiled.out" || { ok=0; why="$why 编译 stdout"; }
    cmp -s "$dir/ast.txt" "$o/ast.out" || { ok=0; why="$why AST"; }
    [ "$ae" = 0 ] || { ok=0; why="$why astdump exit=$ae"; }

    if [ $ok -eq 1 ]; then
        printf 'PASS  %-9s %-18s\n' "$anchor" "$case"
        pass=$((pass+1))
    else
        printf 'FAIL  %-9s %-18s%s\n' "$anchor" "$case" "$why"
        for f in interp.err compiled.err ast.err; do
            [ -s "$o/$f" ] && sed -n '1,3p' "$o/$f" | sed 's/^/        /'
        done
        fail=$((fail+1))
    fi
done <"$CAT"

echo
echo "用例：PASS=$pass FAIL=$fail"
if [ -f "$LEDGER" ]; then
    total=$(grep '^| [A-Z]\{2,6\}-[0-9]' "$LEDGER" | grep -E '\| (PASS|部分) \|' | wc -l | tr -d ' ')
    miss=""
    while read -r a; do
        case " ${covered[*]} " in *" $a "*) ;; *) miss="$miss $a" ;; esac
    done < <(grep '^| [A-Z]\{2,6\}-[0-9]' "$LEDGER" | grep -E '\| (PASS|部分) \|' | sed 's/^| \([A-Z0-9-]*\) |.*/\1/')
    cnt=0
    for a in "${covered[@]}"; do cnt=$((cnt+1)); done
    echo "台账覆盖：$cnt 个锚点 / $total 个 PASS+部分；未覆盖：${miss:- 无}"
fi
[ "$fail" -eq 0 ] && exit 0 || exit 1
