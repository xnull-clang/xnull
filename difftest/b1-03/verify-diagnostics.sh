#!/usr/bin/env bash
# QA1-B1-03 诊断项复验（XNull xnfmt）：缺文件 / 目录 / 无参数 / 非法 UTF-8。
# 用法：bash verify-diagnostics.sh            # 从 E4_SHA 构建并测
#       XNFMT_BIN=/path/xnfmt bash verify-diagnostics.sh
set -uo pipefail

REPO=${REPO:-/Users/vjs/Desktop/XNull-Lang}
E4_SHA=${E4_SHA:-0d8c985}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/qa-b1-diag.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

BIN=${XNFMT_BIN:-}
if [ -z "$BIN" ]; then
    mkdir -p "$TMP/e4"
    git -C "$REPO" archive --format=tar "$E4_SHA" | tar -x -C "$TMP/e4" || exit 2
    ( cd "$TMP/e4/impl" && go build -o "$TMP/xnull" ./cmd/xnull ) || exit 2
    ( cd "$TMP/e4" && "$TMP/xnull" build impl/xnfmt/xnfmt.x -o "$TMP/xnfmt-x" ) >"$TMP/build.log" 2>&1 || {
        echo "XNull xnfmt 构建失败"; tail -5 "$TMP/build.log"; exit 2; }
    BIN=$TMP/xnfmt-x
fi

mkdir -p "$TMP/dir"
printf '\xff\xfe' >"$TMP/bad.x"

ok=0
check() { # name expect_rc needle cmd...
    local name=$1 want=$2 needle=$3; shift 3
    "$@" >"$TMP/$name.out" 2>"$TMP/$name.err"; local rc=$?
    local good=0
    [ "$rc" = "$want" ] && grep -q "$needle" "$TMP/$name.err" && good=1
    [ $good -eq 1 ] && ok=$((ok+1))
    printf '%-12s rc=%s  期望=%s/%s  %s\n' "$name" "$rc" "$want" "$needle" "$([ $good -eq 1 ] && echo PASS || echo FAIL)"
}

check noargs    2 'FMT-104' "$BIN"
check missing   2 'FMT-104' "$BIN" "$TMP/nope.x"
check directory 2 'FMT-104' "$BIN" "$TMP/dir"
check badutf8   2 'FMT-102' "$BIN" "$TMP/bad.x"

echo "诊断项：$ok/4"
[ "$ok" -eq 4 ] && exit 0 || exit 1
