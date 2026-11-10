#!/usr/bin/env bash
# K-07 双路径回归：xdk.sys.readFileText 在解释器与 Go 编译 C 产物上输出一致。
# 覆盖：2 MiB 文件长度 + 前 64 字节十六进制；缺失文件两条路径均非 0 退出且信息明确。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
BIN=${XNULL_BIN:-}
RUNTIME=${XNULL_RUNTIME:-"$ROOT/impl/runtime"}
if [ -z "$BIN" ]; then
  ( cd "$ROOT/impl" && go build -o /tmp/xnull-b3-k07 ./cmd/xnull ) || exit 1
  BIN=/tmp/xnull-b3-k07
fi
[ -d "$RUNTIME" ] || { echo "缺少运行时目录：$RUNTIME"; exit 2; }

TMPROOT=${TMPDIR:-/tmp}
TMPROOT=${TMPROOT%/}
TMP=$(mktemp -d "$TMPROOT/b3-k07.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# 入口目录即 FFI 绑定根：把测试源与 sys.xfb 放进同一临时工程。
cp "$HERE/k07_readfile.x" "$TMP/k07_readfile.x" || exit 1
mkdir -p "$TMP/bindings/xdk"
cp "$ROOT/bindings/xdk/sys.xfb" "$TMP/bindings/xdk/sys.xfb" || exit 1

DATA="$TMP/data.txt"
python3 - "$DATA" <<'PY' || exit 1
import sys
path = sys.argv[1]
line = "The quick brown fox jumps over the lazy dog 0123456789\n"
n = 2 * 1024 * 1024
data = (line * (n // len(line) + 1))[:n]
open(path, "wb").write(data.encode("ascii"))
PY

pass=0 fail=0
SRC="$TMP/k07_readfile.x"

# 独立期望值（不依赖被测实现）：长度 + 前 64 字节十六进制。
want_len=$(wc -c < "$DATA" | tr -d ' ')
want_head=$(od -An -tx1 -N 64 "$DATA" | tr -d ' \n')
want="len=$want_len head=$want_head"

"$BIN" run --interp "$SRC" -- "$DATA" > "$TMP/i.out" 2>"$TMP/i.err"; ic=$?
"$BIN" run "$SRC" --runtime "$RUNTIME" -- "$DATA" > "$TMP/c.out" 2>"$TMP/c.err"; cc=$?
if [ "$ic" -ne 0 ] || [ "$cc" -ne 0 ]; then
  echo "FAIL 2MiB 运行：interp=$ic compile=$cc"
  sed -n '1,5p' "$TMP/i.err"; sed -n '1,5p' "$TMP/c.err"
  fail=$((fail+1))
elif ! cmp -s "$TMP/i.out" "$TMP/c.out"; then
  echo "FAIL 2MiB 双路径 stdout 不一致"
  diff -u "$TMP/i.out" "$TMP/c.out" | head -10
  fail=$((fail+1))
elif [ "$(cat "$TMP/i.out")" != "$want" ]; then
  echo "FAIL 2MiB 期望值不符：got=$(cat "$TMP/i.out") want=$want"
  fail=$((fail+1))
else
  echo "PASS 2MiB len=$want_len head=${want_head:0:16}…"
  pass=$((pass+1))
fi

MISSING="$TMP/no-such-file.txt"
for mode in interp compile; do
  if [ "$mode" = interp ]; then
    "$BIN" run --interp "$SRC" -- "$MISSING" > /dev/null 2>"$TMP/m.err"; mc=$?
  else
    "$BIN" run "$SRC" --runtime "$RUNTIME" -- "$MISSING" > /dev/null 2>"$TMP/m.err"; mc=$?
  fi
  if [ "$mc" -eq 0 ]; then
    echo "FAIL 缺失文件($mode)：退出码为 0"
    fail=$((fail+1))
  elif ! grep -q "readFileText" "$TMP/m.err" || ! grep -q "$MISSING" "$TMP/m.err"; then
    echo "FAIL 缺失文件($mode)：错误信息未点名 readFileText/路径"
    sed -n '1,3p' "$TMP/m.err"
    fail=$((fail+1))
  else
    echo "PASS 缺失文件($mode) exit=$mc"
    pass=$((pass+1))
  fi
done

echo "k07-readfile 汇总：PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
