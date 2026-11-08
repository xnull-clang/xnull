#!/usr/bin/env bash
# S8-21：B2 差分批处理——L1 语料按 B2_JOBS 分片并行，L2/L3 并行跑一次。
# 用法：B2_JOBS=4 bash tests/b2/batch.sh
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
JOBS=${B2_JOBS:-4}
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b2-batch.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# 分片：行号取模，保留原文件相对路径语义。
awk -v n="$JOBS" 'BEGIN{i=0} /^#/ {print > ("'"$TMP"'/shard-" (i%n) ".tsv"); next} {print > ("'"$TMP"'/shard-" (i%n) ".tsv"); i++}' "$HERE/corpus.tsv"

# 预构建一次二进制，所有分片复用，避免并发重建。
( cd "$ROOT/impl" && go build -o "$TMP/xnull-b2" ./cmd/xnull ) || exit 1
( cd "$ROOT/impl" && go build -o "$TMP/xnast-b2" ./cmd/xnast ) || exit 1
export XNULL_BIN="$TMP/xnull-b2" XNAST_BIN="$TMP/xnast-b2"

pids=()
for i in $(seq 0 $((JOBS-1))); do
  B2_CORPUS="$TMP/shard-$i.tsv" B2_TMP="$TMP/run-$i" bash "$HERE/run-l1.sh" > "$TMP/l1-$i.out" 2>&1 &
  pids+=($!)
done
B2_TMP="$TMP/run-l2" bash "$HERE/run-l2.sh" > "$TMP/l2.out" 2>&1 &
pids+=($!)

fail=0
for pid in "${pids[@]}"; do
  wait "$pid" || fail=1
done

pass=$(cat "$TMP"/l1-*.out "$TMP/l2.out" 2>/dev/null | grep -c '^PASS' || true)
fails=$(cat "$TMP"/l1-*.out "$TMP/l2.out" 2>/dev/null | grep -c '^FAIL' || true)
echo "B2 批处理：PASS=${pass} FAIL=${fails} (JOBS=${JOBS})"
[ "$fail" -eq 0 ] && [ "$fails" -eq 0 ] && exit 0
cat "$TMP"/l1-*.out "$TMP/l2.out" 2>/dev/null | grep '^FAIL' | head -20
exit 1
