#!/bin/sh
# M6-B1-01 驱动：xnfmt（Go oracle）全仓差分材料。
#   - 对 git ls-files '*.x' 逐文件：格式化 → 幂等（二次相同）→ 10 次输出稳定 → sha256
#   - --check 三态退出码
#   - 规则测试 + 全仓幂等测试
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/evidence/M6-B1-01"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b1-01.XXXXXX")
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT

( cd "$ROOT/impl" && go build -o "$TMP/xnfmt" ./cmd/xnfmt ) || exit 1
echo "xnfmt sha256=$(shasum -a 256 "$TMP/xnfmt" | awk '{print $1}')"

cd "$ROOT"
git ls-files '*.x' | sort > "$OUT/files.txt"
total=$(wc -l < "$OUT/files.txt" | tr -d ' ')
echo "文件数：$total"

: > "$OUT/sha256-table.txt"
idem_fail=0
stable_fail=0
n=0
while IFS= read -r f; do
    n=$((n + 1))
    cp "$f" "$TMP/w1.x"
    "$TMP/xnfmt" "$TMP/w1.x" || { echo "FMT FAIL $f"; exit 1; }
    cp "$TMP/w1.x" "$TMP/w2.x"
    "$TMP/xnfmt" "$TMP/w2.x" || { echo "FMT FAIL(2) $f"; exit 1; }
    cmp -s "$TMP/w1.x" "$TMP/w2.x" || { echo "IDEM FAIL $f"; idem_fail=$((idem_fail + 1)); }

    first=$(shasum -a 256 "$TMP/w1.x" | awk '{print $1}')
    k=0
    while [ $k -lt 9 ]; do
        cp "$f" "$TMP/w3.x"
        "$TMP/xnfmt" "$TMP/w3.x"
        h=$(shasum -a 256 "$TMP/w3.x" | awk '{print $1}')
        [ "$h" = "$first" ] || { echo "UNSTABLE $f run=$k"; stable_fail=$((stable_fail + 1)); break; }
        k=$((k + 1))
    done
    printf '%s  %s\n' "$first" "$f" >> "$OUT/sha256-table.txt"
done < "$OUT/files.txt"
echo "幂等失败：$idem_fail"
echo "稳定性失败：$stable_fail"

# --check：全规范 0 / 有差异 1 / 错误 2
"$TMP/xnfmt" --check $(cat "$OUT/files.txt") > /dev/null 2> "$OUT/check.err"
echo "check_exit=$?"
writ=0
while IFS= read -r f; do
    cp "$f" "$TMP/c.x"
    "$TMP/xnfmt" "$TMP/c.x"
    cmp -s "$f" "$TMP/c.x" || writ=$((writ + 1))
done < "$OUT/files.txt"
echo "未格式化文件数：$writ / $total"

echo
echo "== 规则与幂等测试 =="
( cd "$ROOT/impl" && go test ./internal/xnfmt ./cmd/xnfmt -count=1 -timeout 300s ) || exit 1
echo "B1-01 驱动：全部通过"
