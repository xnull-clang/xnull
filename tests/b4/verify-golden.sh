#!/usr/bin/env bash
# B4c-03：无 Go 验证（冻结 golden vs bootstrap 原生工具链）。
#
# 依赖：bootstrap/bin/{xparser,xn-s4}（缺失时自动 bootstrap/build.sh）、python3、cc。
# 比对基准：evidence/B4c/golden/{hashes.tsv,negatives.tsv,examples.tsv}
#
# 口径：
#   入口 C：单文件全量 + 多文件（tests/b4/native-bundle.py 生成 AST bundle）；
#           投影按 golden 的 proj 列复现（A = 入口目录 .xfb；B = 入口 + 直接 xdk 依赖）；
#           via=interp 的 6 条为冻结时 Go 解释器生成，原生编译器自编译仍段错误 → BLOCKED；
#           impl/lib/b2/xparser.x 用冻结的 B4c-03 前源（xparser-pre-b4c03.x）比对旧 golden，
#           该文件已被 B4c-03 修复，当前源的 C 单独验证。
#   负例：  原生无 sema/entry 诊断实现（Go 前端已删除）→ 全部 BLOCKED，不伪装 PASS；
#   示例：  9/9 构建 + 运行 + C 哈希。
#
# 退出码：仅 FAIL>0 非零；BLOCKED 计入汇总并写入 verify-summary.txt。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
G="$ROOT/evidence/B4c/golden"
BIN="$ROOT/bootstrap/bin"
W=$(mktemp -d "${TMPDIR:-/tmp}/b4c03.XXXXXX")
FROZEN_XP=0
restore_frozen_xp() {
  if [ "$FROZEN_XP" = "1" ] && [ -f "$W/xparser.current" ]; then
    cp "$W/xparser.current" "$ROOT/impl/lib/b2/xparser.x"
  fi
  rm -rf "$W"
}
trap restore_frozen_xp EXIT

[ -x "$BIN/xn-s4" ] && [ -x "$BIN/xparser" ] || "$ROOT/bootstrap/build.sh" >/dev/null || {
  echo "verify: bootstrap 构建失败" >&2; exit 1;
}

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# 固定点源：xparser.x 在 B4c-03 被修复，旧 golden 对应旧源。
if grep -q '^impl/lib/b2/xparser\.x	' "$G/hashes.tsv"; then
  cp "$ROOT/impl/lib/b2/xparser.x" "$W/xparser.current"
  cp "$G/xparser-pre-b4c03.x" "$ROOT/impl/lib/b2/xparser.x"
  FROZEN_XP=1
fi

proj_A() { # rel
  local dir; dir=$(dirname "$1")
  if find "$dir" -name '*.xfb' 2>/dev/null | grep -q .; then
    python3 "$ROOT/tests/b3/xfb-projection.py" "$dir"
  fi
}

printf 'entry\tkind\tstatus\tsha\tvia\tproj\n' > "$W/entries.tsv"
entry_pass=0; entry_fail=0; entry_block=0
while IFS=$'\t' read -r rel kind want via proj; do
  [ -n "${rel:-}" ] || continue
  if [ "$via" = "interp" ]; then
    entry_block=$((entry_block+1))
    printf 'entry\t%s\tBLOCKED\t-\t%s\t%s\n' "$rel" "$via" "$proj" >> "$W/entries.tsv"
    continue
  fi
  if [ "$proj" = "B" ]; then
    projtext=$(python3 "$ROOT/tests/b4/proj-b.py" "$ROOT" "$rel")
  else
    projtext=$(proj_A "$rel")
  fi
  if ! "$BIN/xparser" --file "$rel" > "$W/a.ast" 2>/dev/null; then
    entry_fail=$((entry_fail+1))
    printf 'entry\t%s\tFAIL(ast)\t-\t%s\t%s\n' "$rel" "$via" "$proj" >> "$W/entries.tsv"
    echo "FAIL entry ${rel}（xparser）"; continue
  fi
  args=(--ast-file "$W/a.ast" --project "$projtext")
  if [ "$kind" = "多文件" ]; then
    if ! python3 "$ROOT/tests/b4/native-bundle.py" "$ROOT" "$BIN/xparser" "$rel" > "$W/b.json" 2>/dev/null; then
      entry_fail=$((entry_fail+1))
      printf 'entry\t%s\tFAIL(bundle)\t-\t%s\t%s\n' "$rel" "$via" "$proj" >> "$W/entries.tsv"
      echo "FAIL entry ${rel}（bundle）"; continue
    fi
    args+=(--bundle-file "$W/b.json")
  fi
  if ! "$BIN/xn-s4" "$rel" "${args[@]}" > "$W/a.c" 2>/dev/null; then
    entry_fail=$((entry_fail+1))
    printf 'entry\t%s\tFAIL(c)\t-\t%s\t%s\n' "$rel" "$via" "$proj" >> "$W/entries.tsv"
    echo "FAIL entry ${rel}（xn-s4）"; continue
  fi
  got=$(sha "$W/a.c")
  if [ "$got" = "$want" ]; then
    entry_pass=$((entry_pass+1))
    printf 'entry\t%s\tPASS\t%s\t%s\t%s\n' "$rel" "$got" "$via" "$proj" >> "$W/entries.tsv"
  else
    entry_fail=$((entry_fail+1))
    printf 'entry\t%s\tFAIL(sha)\t%s\t%s\t%s\n' "$rel" "$got" "$via" "$proj" >> "$W/entries.tsv"
    echo "FAIL entry ${rel}（sha $got != $want）"
  fi
done < <(python3 - "$G/hashes.tsv" "$ROOT/evidence/B3-09/final-v3/results.tsv" <<'PY'
import sys
kind = {}
for line in open(sys.argv[2], encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 3 and p[0] != "path":
        kind[p[0]] = p[2]
for line in open(sys.argv[1], encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if p[0] == "path" or not p[0]:
        continue
    print("\t".join([p[0], kind.get(p[0], "单文件"), p[2], p[6], p[7]]))
PY
)

# ---- 负例：原生无 sema/entry 诊断 → BLOCKED（按码段盘点）----
neg_total=0; neg_block=0
declare -a neg_codes=()
while IFS=$'\t' read -r rel go_exit code first; do
  [ -n "${rel:-}" ] || continue
  neg_total=$((neg_total+1)); neg_block=$((neg_block+1))
  neg_codes+=("$code")
done < <(awk -F'\t' 'NR>1{print $1"\t"$2"\t"$3"\t"$4}' "$G/negatives.tsv")

# ---- 9 示例 ----
ex_pass=0; ex_fail=0
SRC=(); for f in rt.c rt_gc.c rt_policy.c rt_weak.c xrt_abi.c rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c rt_std_net.c rt_task.c rt_sync.c rt_std_res.c rt_std_res_empty.c; do SRC+=("$ROOT/impl/runtime/$f"); done
while IFS=$'\t' read -r name want; do
  [ -n "${name:-}" ] || continue
  rel="tests/b2/corpus/examples/$name"
  if ! "$BIN/xparser" --file "$rel" > "$W/e.ast" 2>/dev/null; then
    ex_fail=$((ex_fail+1)); echo "FAIL example ${name}（ast）"; continue
  fi
  if ! "$BIN/xn-s4" "$rel" --ast-file "$W/e.ast" --project "" > "$W/e.c" 2>/dev/null; then
    ex_fail=$((ex_fail+1)); echo "FAIL example ${name}（c）"; continue
  fi
  got=$(sha "$W/e.c")
  if ! cc -std=c11 -O2 -pthread -I "$ROOT/impl/runtime" -o "$W/e.bin" "$W/e.c" "${SRC[@]}" "$BIN/res.c" 2>/dev/null; then
    ex_fail=$((ex_fail+1)); echo "FAIL example ${name}（cc）"; continue
  fi
  "$W/e.bin" > "$W/e.out" 2>&1; rc=$?
  if [ "$got" = "$want" ] && [ $rc -eq 0 ]; then
    ex_pass=$((ex_pass+1))
  else
    ex_fail=$((ex_fail+1)); echo "FAIL example ${name}（rc=$rc sha=$got）"
  fi
done < <(awk -F'\t' 'NR>1{print $1"\t"$3}' "$G/examples.tsv")

# ---- 汇总 ----
cp "$W/entries.tsv" "$G/verify-entries.tsv" 2>/dev/null || true
{
  echo "verify-golden（无 Go）："
  echo "  入口 C：PASS=$entry_pass FAIL=$entry_fail BLOCKED=${entry_block}（via=interp：原生自编译段错误）"
  echo "  负例：  PASS=0 FAIL=0 BLOCKED=${neg_block}（sema/entry/codegen 诊断未移植）"
  echo "  示例：  PASS=$ex_pass FAIL=$ex_fail"
  echo "  特殊：  impl/lib/b2/xparser.x 使用冻结旧源 xparser-pre-b4c03.x 比对旧 golden"
} | tee "$G/verify-summary.txt"
TOTAL_FAIL=$((entry_fail+ex_fail))
echo "  合计：FAIL=$TOTAL_FAIL"
[ $TOTAL_FAIL -eq 0 ]
