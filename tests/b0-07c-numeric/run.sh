#!/usr/bin/env bash
# tests/b0-07c-numeric/run.sh —— B0-07c numeric 前置测试包执行器
#
# 用法：
#   bash tests/b0-07c-numeric/run.sh --root /path/to/xnull-repo
#   bash tests/b0-07c-numeric/run.sh --root ... --bin /path/to/xnull
#   bash tests/b0-07c-numeric/run.sh --root ... --case t03
#
# 判据：每个 case 的退出码 == expect-exit；expect-files/* 逐字节一致。
# 构建失败不会被笼统记为 FAIL：按诊断分类为 BLOCKED 并给出归属标签（见 README）。
#
# 只读：不修改被测树；所有产物写在临时目录。

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
RUNTIME=${XNULL_RUNTIME:-}
ONLY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT=$(cd "$2" && pwd); shift 2 ;;
        --bin) BIN=$2; shift 2 ;;
        --runtime) RUNTIME=$2; shift 2 ;;
        --case) ONLY=$2; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

[ -d "$ROOT/impl" ] || { echo "ROOT 下缺 impl/：$ROOT" >&2; exit 2; }
[ -d "$ROOT/bindings" ] || { echo "ROOT 下缺 bindings/：$ROOT" >&2; exit 2; }

# ---- 预检 1：运行时句柄修复必须在被测树内（B0-07c e83f93c） ----
XRT_ABI="$ROOT/impl/runtime/xrt_abi.c"
if [ -f "$XRT_ABI" ] && ! grep -q "rt_payload(payload)" "$XRT_ABI"; then
    echo "警告：$XRT_ABI 未包含 handle_deinit 修复（e83f93c）" >&2
    echo "      症状：close 后仍打印「xrt: 句柄泄漏」，t01/t02 会被误判。" >&2
    echo "      处置：git cherry-pick e83f93c（pod/e5-runtime）后重跑。" >&2
    echo >&2
fi

# ---- 预检 2：构建/定位 xnull ----
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b0-07c-num.XXXXXX")
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT

if [ -z "$BIN" ]; then
    BIN=$TMP/xnull
    echo "构建 xnull：$ROOT/impl"
    ( cd "$ROOT/impl" && go build -o "$BIN" ./cmd/xnull ) || { echo "xnull 构建失败" >&2; exit 1; }
fi
[ -x "$BIN" ] || { echo "xnull 不可执行：$BIN" >&2; exit 2; }
[ -z "$RUNTIME" ] && [ -d "$ROOT/impl/runtime" ] && RUNTIME=$ROOT/impl/runtime
[ -n "$RUNTIME" ] && export XNULL_RUNTIME="$RUNTIME"

echo "xnull   ：$BIN"
echo "root    ：$ROOT"
echo "runtime ：${XNULL_RUNTIME:-（默认）}"
echo

# classify：从构建日志提取归属标签（只做分层，不替代真实修复）。
classify() {
    local log=$1
    local tags=""
    grep -q "类型 Int32 未支持" "$log" && tags="$tags CG-INT32"
    grep -q "类型 Int64 未支持" "$log" && tags="$tags CG-INT64"
    grep -q "可空类型 xrt_handle" "$log" && tags="$tags CG-OPTION-HANDLE"
    grep -q '未定义的名称 `Bytes`' "$log" && tags="$tags SEMA-BYTES"
    if grep -q '未定义的名称 `fileRead`' "$log" || grep -q '未定义的名称 `fileWrite`' "$log"; then
        tags="$tags CG-ERRORCODE"
    fi
    grep -q "参数 buf 类型 Bytes 未纳入" "$log" && tags="$tags CG-BYTES-ARG"
    grep -q "不能赋给形参 File" "$log" && tags="$tags SEMA-NARROW"
    grep -q "handle 实参仅支持变量" "$log" && tags="$tags CG-HANDLE-ARG"
    grep -q "Int32 未纳入 P-09\|返回标量 Int32" "$log" && tags="$tags CG-INT32-RET"
    tags=$(echo "$tags" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ')
    tags=${tags% }
    [ -z "$tags" ] && tags="UNEXPECTED"
    echo "$tags"
}

pass=0; blocked=0; fail=0
for dir in "$HERE"/cases/*/; do
    name=$(basename "$dir")
    [ -n "$ONLY" ] && case "$name" in *"$ONLY"*) ;; *) continue ;; esac
    prog=$dir/case.x
    [ -f "$prog" ] || continue
    want_exit=0
    [ -f "$dir/expect-exit" ] && want_exit=$(tr -d '[:space:]' < "$dir/expect-exit")
    owner="未标注"
    [ -f "$dir/OWNER" ] && owner=$(tr -d '\n' < "$dir/OWNER")

    work=$TMP/$name
    mkdir -p "$work"
    cp -a "$ROOT/bindings" "$work/bindings"
    # 拷进工作目录再构建：绝对路径含双斜杠会触发 multifile.go 的
    # filepath.Clean(entryPath) 键不一致（入口被判“无法读取”）。
    cp "$prog" "$work/case.x"
    if [ -d "$dir/files" ]; then
        cp -a "$dir/files/." "$work/"
    fi

    echo "===== $name"
    if ! ( cd "$work" && "$BIN" build "case.x" -o "$work/prog" ) >"$work/build.log" 2>&1; then
        tags=$(classify "$work/build.log")
        echo "  BLOCKED [$tags]"
        echo "  归属：$owner"
        sed 's/^/    /' "$work/build.log" | grep -E "error\[|代码生成失败|提示" | head -8
        blocked=$((blocked + 1))
        continue
    fi

    rc=0
    ( cd "$work" && ./prog ) >"$work/stdout.txt" 2>"$work/stderr.txt" || rc=$?
    if [ "$rc" -ne "$want_exit" ]; then
        echo "  FAIL exit=$rc want=$want_exit（归属：$owner）"
        sed 's/^/    /' "$work/stderr.txt" | head -8
        fail=$((fail + 1))
        continue
    fi

    mismatch=0
    if [ -d "$dir/expect-files" ]; then
        for want in "$dir/expect-files"/*; do
            [ -e "$want" ] || continue
            base=$(basename "$want")
            if ! cmp -s "$want" "$work/$base"; then
                echo "  MISMATCH $base（归属：$owner）"
                if [ -f "$work/$base" ]; then
                    cmp -l "$want" "$work/$base" | head -5 | sed 's/^/    /'
                else
                    echo "    产物缺失：$work/$base"
                fi
                mismatch=1
            fi
        done
    fi
    if [ "$mismatch" -ne 0 ]; then
        fail=$((fail + 1))
        continue
    fi

    echo "  PASS（exit=${rc}）"
    pass=$((pass + 1))
done

echo
echo "汇总：PASS=$pass BLOCKED=$blocked FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
[ "$blocked" -eq 0 ] || exit 3
exit 0
