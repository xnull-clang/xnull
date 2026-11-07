#!/usr/bin/env bash
# PKG-01 逐项复验：
#   1) 导出 --sha 树 → 注入 QA2 独立用例（49 子项）→ go test ./internal/sema
#   2) 构建 xnull → 跑 f1/f2/f3/c1 四个 CLI 例，按 §3.5 断言码型
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
QA1=$(cd "$HERE/../.." && pwd)
REPO=$(git -C "$QA1" rev-parse --show-toplevel)
SHA=main
OUT=""
REQUIRE_CLI=0

while [ $# -gt 0 ]; do
    case "$1" in
        --sha) SHA=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        --require-cli) REQUIRE_CLI=1; shift ;;
        -h|--help) sed -n '1,12p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

T=$(mktemp -d "${TMPDIR:-/tmp}/qa1-pkg.XXXXXX")
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/src"
git -C "$REPO" archive "$SHA" | tar -x -C "$T/src" || exit 2
cp "$HERE/cases/qa2_pkg_accept_test.go" "$T/src/impl/internal/sema/qa2_pkg_accept_test.go"
cp -R "$HERE/cases/pkg" "$T/pkg"

GLOG=$T/pkg-go.out
( cd "$T/src/impl" && go test ./internal/sema -run '^TestQA2' -count=1 -v ) >"$GLOG" 2>&1
GRC=$?

GPASS=$(grep -c '^    --- PASS:' "$GLOG" || true)
GFAIL=$(grep -c '^    --- FAIL:' "$GLOG" || true)

( cd "$T/src/impl" && go build -o "$T/xnull" ./cmd/xnull ) || exit 2
export XNULL_RUNTIME="$T/src/impl/runtime"

# expect_accept(name) / expect_code(name, code)
CLOG=$T/pkg-cli.out
: > "$CLOG"
CLI_BAD=0

expect_code() {
    local name=$1 want=$2
    ( cd "$T/pkg" && "$T/xnull" build "$name.x" -o "$T/$name.bin" ) >"$T/$name.out" 2>"$T/$name.err"
    local rc=$?
    if [ "$rc" -ne 0 ] && grep -q "error\[$want\]" "$T/$name.err"; then
        echo "PASS $name  rc=$rc  $want" | tee -a "$CLOG"
    else
        echo "FAIL $name  want=$want rc=$rc  $(head -1 "$T/$name.err")" | tee -a "$CLOG"
        CLI_BAD=$((CLI_BAD+1))
    fi
}

expect_accept() {
    local name=$1
    ( cd "$T/pkg" && "$T/xnull" build "$name.x" -o "$T/$name.bin" ) >"$T/$name.out" 2>"$T/$name.err"
    local rc=$?
    if [ "$rc" -eq 0 ] && ! grep -q 'error\[' "$T/$name.err"; then
        echo "PASS $name  rc=0  accepted" | tee -a "$CLOG"
    else
        echo "FAIL $name  want=accept rc=$rc  $(head -1 "$T/$name.err")" | tee -a "$CLOG"
        CLI_BAD=$((CLI_BAD+1))
    fi
}

expect_code f1 RES-103
expect_accept f2
expect_code f3 RES-103
expect_code c1 RES-103

echo "===== PKG-01 @ ${SHA}"
echo "Go 独立用例：PASS=${GPASS} / FAIL=${GFAIL}（exit ${GRC}）"
grep '^    --- FAIL:' "$GLOG" || true
echo "CLI 例：$((4-CLI_BAD))/4 通过（补充观察；CLI 尚未接 AnalyzeWithDeps，不计入 49 项）"
cat "$CLOG"

if [ -n "$OUT" ]; then
    mkdir -p "$OUT"
    cp "$GLOG" "$OUT/pkg-go.log"
    cp "$CLOG" "$OUT/pkg-cli.log"
    { echo "SHA=$SHA"; git -C "$REPO" rev-parse "$SHA"; } > "$OUT/pkg-sha.txt"
fi

[ "$GRC" -eq 0 ] || exit 1
if [ "$REQUIRE_CLI" -eq 1 ] && [ "$CLI_BAD" -ne 0 ]; then
    exit 1
fi
exit 0
