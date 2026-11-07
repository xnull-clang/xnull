#!/usr/bin/env bash
# B1-03 差分重跑（权威口径）：以 main f63fcba 的 155 个 .x 为基线 + 本树 union。
# 用法：在仓库根执行 ./evidence/M6-B1-03/e4/run.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="$HERE/rerun"
BASE="${1:-f63fcba}"
WORK="$(mktemp -d "${TMPDIR:-/private/var/folders/zr/vyzqhmcn20ggrvrkdpblvchm0000gn/T/opencode}/b103.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

cd "$ROOT"
echo "== head: $(git rev-parse HEAD)  base: $BASE" > "$OUT/env.txt"
git rev-parse HEAD >> "$OUT/env.txt"

echo "== build" >> "$OUT/env.txt"
( cd impl && go build -o "$WORK/xnfmt-go" ./cmd/xnfmt && go build -o "$WORK/xnull" ./cmd/xnull ) >> "$OUT/build.log" 2>&1 || { echo "BUILD FAIL"; exit 1; }
( cd impl && XNULL_RUNTIME=runtime "$WORK/xnull" build xnfmt/xnfmt.x -o "$WORK/xnfmt-x" ) >> "$OUT/build.log" 2>&1 || { echo "XNULLFMT BUILD FAIL"; exit 1; }
shasum -a 256 "$WORK/xnfmt-go" "$WORK/xnfmt-x" > "$OUT/artifact.sha256"

# 语料
git ls-tree -r --name-only "$BASE" | grep '\.x$' > "$OUT/files-155.txt"
git ls-files '*.x' > "$OUT/files-union.txt"

run_corpus() { # $1=list  $2=tag
  local list="$1"
  local tag="$2"
  local g="$WORK/g-$tag"
  local x="$WORK/x-$tag"
  mkdir -p "$g" "$x"
  while IFS= read -r f; do
    mkdir -p "$g/$(dirname "$f")" "$x/$(dirname "$f")"
    git show "$BASE:$f" > "$g/$f" 2>/dev/null || cp "$f" "$g/$f"
    cp "$g/$f" "$x/$f"
  done < "$list"
  ( cd "$g" && find . -name '*.x' -print0 | xargs -0 "$WORK/xnfmt-go" ) > "$OUT/$tag-go.out" 2> "$OUT/$tag-go.err"
  ( cd "$x" && while IFS= read -r f; do "$WORK/xnfmt-x" "$f" >> "$OUT/$tag-x.out" 2>> "$OUT/$tag-x.err" || echo "FAIL $f" | tee -a "$OUT/$tag-x.out"; done < "$list" )
  diff -rq "$g" "$x" > "$OUT/$tag-diff.txt" 2>&1
  echo "diff_$tag=$?" >> "$OUT/exit_code.txt"
  # 幂等：两侧再格式化一次
  cp -R "$g" "$WORK/g2-$tag"; cp -R "$x" "$WORK/x2-$tag"
  ( cd "$WORK/g2-$tag" && find . -name '*.x' -print0 | xargs -0 "$WORK/xnfmt-go" ) >/dev/null 2>&1
  ( cd "$WORK/x2-$tag" && while IFS= read -r f; do "$WORK/xnfmt-x" "$f" >/dev/null 2>&1; done < "$list" )
  diff -rq "$g" "$WORK/g2-$tag" > "$OUT/$tag-idem-go.txt" 2>&1
  local ig=$?
  diff -rq "$x" "$WORK/x2-$tag" > "$OUT/$tag-idem-x.txt" 2>&1
  local ix=$?
  echo "idem_go_$tag=$ig" >> "$OUT/exit_code.txt"
  echo "idem_x_$tag=$ix" >> "$OUT/exit_code.txt"
}

: > "$OUT/exit_code.txt"
run_corpus "$OUT/files-155.txt" base155
run_corpus "$OUT/files-union.txt" union

# 诊断（4 项）
{
  echo "== 缺文件"; "$WORK/xnfmt-x" "$WORK/no-such.x"; echo "rc=$?"
  echo "== 目录"; "$WORK/xnfmt-x" "$WORK"; echo "rc=$?"
  echo "== 无参数"; "$WORK/xnfmt-x"; echo "rc=$?"
  echo "== 非法 UTF-8"; printf 'static Int main() { print("\xff")\n return 0 }\n' > "$WORK/bad.x"; "$WORK/xnfmt-x" "$WORK/bad.x"; echo "rc=$?"
} > "$OUT/diagnostics.log" 2>&1

# 回归
( cd impl && go test ./... -count=1 -timeout 1200s ) > "$OUT/go-test-all.log" 2>&1
echo "go_test_all=$?" >> "$OUT/exit_code.txt"

cat "$OUT/exit_code.txt"
echo "---- 差异行数（base155 / union）"
wc -l < "$OUT/base155-diff.txt"; wc -l < "$OUT/union-diff.txt"
