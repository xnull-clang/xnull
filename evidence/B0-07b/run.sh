#!/bin/sh
# M6-B0-07b 驱动：文本变体 API（readFileText/writeFileText）端到端 2/2。
# 用法：sh evidence/B0-07b/run.sh [<qa-1 工作树>]
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
QA=${1:-/Users/vjs/Desktop/XNull-Lang/wt/qa-1}
PROG="$QA/evidence/M6-B0-06/program/read_parse_write_text.x"
FIX="$QA/evidence/M6-B0-06/fixtures"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b0-07b.XXXXXX")
TMP=$(cd "$TMP" && pwd)   # 归一化路径：TMPDIR 末尾的 / 会产生 //，入口解析会误判
trap 'rm -rf "$TMP"' EXIT

[ -f "$PROG" ] || { echo "缺少 QA 程序：$PROG" >&2; exit 2; }

mkdir -p "$TMP/bindings/xdk" "$TMP/run"
cp "$ROOT"/bindings/xdk/*.xfb "$TMP/bindings/xdk/"
cp "$PROG" "$TMP/prog.x"

( cd "$ROOT/impl" && go build -o "$TMP/xnull" ./cmd/xnull ) || exit 1
"$TMP/xnull" build "$TMP/prog.x" -o "$TMP/prog.bin" > "$TMP/build.log" 2>&1
brc=$?
echo "build exit=$brc"
if [ "$brc" -ne 0 ]; then
    sed 's/^/  /' "$TMP/build.log" | head -30
    exit 1
fi
echo "生成告警数：$(grep -c 'warning:' "$TMP/build.log" || true)"

pass=0
fail=0
for pair in "in1.x:expected1.txt" "in2.x:expected2.txt"; do
    in=${pair%%:*}
    want=${pair##*:}
    cp "$FIX/$in" "$TMP/run/m6-input.x"
    rm -f "$TMP/run/m6-output.txt"
    ( cd "$TMP/run" && "$TMP/prog.bin" )
    rc=$?
    if [ "$rc" -eq 0 ] && cmp -s "$FIX/$want" "$TMP/run/m6-output.txt"; then
        echo "PASS  $in  exit=0  sha256=$(shasum -a 256 "$TMP/run/m6-output.txt" | awk '{print $1}')"
        pass=$((pass + 1))
    else
        echo "FAIL  $in  exit=$rc"
        diff -u "$FIX/$want" "$TMP/run/m6-output.txt" 2>/dev/null | head -10
        fail=$((fail + 1))
    fi
done
echo "汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
