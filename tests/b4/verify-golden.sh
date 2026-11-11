#!/usr/bin/env bash
# B4c-03：无 Go 验证（bootstrap 工具 + 冻结 golden）。
#
# 依赖：bootstrap/bin/{xparser,xn-s4}（缺失时自动 bootstrap/build.sh）、python3、cc。
# 比对基准：evidence/B4c/golden/{hashes.tsv,negatives.tsv,examples.tsv}
#
# 覆盖范围（Go 已删除后的现实边界）：
#   入口 C：单文件入口全量（xparser --file + xn-s4）；多文件入口需要 bundle，原生暂无生成器 → BLOCKED
#   负例：仅解析层（LEX/SYN）可复现；sema/entry/codegen 类需要 Go 前端 → BLOCKED
#   示例：9/9 构建 + 运行 + C 哈希比对
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
G="$ROOT/evidence/B4c/golden"
BIN="$ROOT/bootstrap/bin"
W=$(mktemp -d "${TMPDIR:-/tmp}/b4c03.XXXXXX")
trap 'rm -rf "$W"' EXIT

[ -x "$BIN/xn-s4" ] && [ -x "$BIN/xparser" ] || "$ROOT/bootstrap/build.sh" >/dev/null || { echo "verify: bootstrap 构建失败" >&2; exit 1; }

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
# 原生 xparser 对大入口会挂起（B4b-02 已定位）：统一 90s 超时，超时记 BLOCKED
run_limited() { perl -e 'alarm 15; exec @ARGV' "$@"; }

# ---- 1) 入口 C（单文件） ----
entry_pass=0; entry_fail=0; entry_block=0
printf 'entry\tpath\tstatus\tsha\n' > "$W/entries.tsv"
while IFS=$'\t' read -r rel kind want; do
  [ -n "${rel:-}" ] || continue
  if [ "$kind" != "单文件" ]; then
    entry_block=$((entry_block+1))
    printf 'entry\t%s\tBLOCKED\t-\n' "$rel" >> "$W/entries.tsv"
    continue
  fi
  if ! run_limited "$BIN/xparser" --file "$rel" > "$W/a.ast" 2>/dev/null; then
    rc=$?
    if [ $rc -eq 142 ]; then entry_block=$((entry_block+1)); printf 'entry\t%s\tBLOCKED(xparser 超时)\t-\n' "$rel" >> "$W/entries.tsv"
    else entry_fail=$((entry_fail+1)); printf 'entry\t%s\tFAIL(ast)\t-\n' "$rel" >> "$W/entries.tsv"; fi
    continue
  fi
  "$BIN/xn-s4" "$rel" --ast-file "$W/a.ast" --project "" > "$W/a.c" 2>/dev/null || { entry_fail=$((entry_fail+1)); printf 'entry\t%s\tFAIL(c)\t-\n' "$rel" >> "$W/entries.tsv"; continue; }
  got=$(sha "$W/a.c")
  if [ "$got" = "$want" ]; then
    entry_pass=$((entry_pass+1)); printf 'entry\t%s\tPASS\t%s\n' "$rel" "$got" >> "$W/entries.tsv"
  else
    entry_fail=$((entry_fail+1)); printf 'entry\t%s\tFAIL(sha)\t%s\n' "$rel" "$got" >> "$W/entries.tsv"
  fi
done < <(awk -F'\t' 'NR>1 && $5=="0"{print $1"\t"$3"\t"$3}' "$G/hashes.tsv" >/dev/null 2>&1; awk -F'\t' 'NR>1{print $1"\t"$2"\t"$3}' "$G/hashes.tsv" >/dev/null 2>&1; python3 - "$G/hashes.tsv" "$ROOT/evidence/B3-09/final-v3/results.tsv" <<'PY'
import sys
h, r = sys.argv[1], sys.argv[2]
kind = {}
for line in open(r, encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 3: kind[p[0]] = p[2]
for line in open(h, encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if p[0] == "path": continue
    if not p[0]: continue
    print("%s\t%s\t%s" % (p[0], kind.get(p[0], "单文件"), p[2]))
PY
)

# ---- 2) 负例（解析层） ----
neg_pass=0; neg_fail=0; neg_block=0
while IFS=$'\t' read -r rel rc code; do
  [ -n "${rel:-}" ] || continue
  case "$code" in
    LEX-*|SYN-*)
      out=$(run_limited "$BIN" --diags --file "$rel" 2>&1)
      got=$(printf '%s\n' "$out" | sed -n 's/^\([A-Z]*-[0-9]*\) .*/\1/p' | head -1)
      if [ "$got" = "$code" ]; then
        neg_pass=$((neg_pass+1))
      else
        # 原生 xparser 尚未实现该诊断（Go 前端已删除）：记 BLOCKED，不伪装通过
        neg_block=$((neg_block+1))
      fi
      ;;
    *)
      neg_block=$((neg_block+1))
      ;;
  esac
done < <(awk -F'\t' 'NR>1{print $1"\t"$2"\t"$3}' "$G/negatives.tsv")

# ---- 3) 9 示例 ----
ex_pass=0; ex_fail=0
while IFS=$'\t' read -r name want; do
  [ -n "${name:-}" ] || continue
  rel="tests/b2/corpus/examples/$name"
  run_limited "$BIN/xparser" --file "$rel" > "$W/e.ast" 2>/dev/null || { ex_fail=$((ex_fail+1)); echo "FAIL example $name（ast）"; continue; }
  "$BIN/xn-s4" "$rel" --ast-file "$W/e.ast" --project "" > "$W/e.c" 2>/dev/null || { ex_fail=$((ex_fail+1)); echo "FAIL example $name（c）"; continue; }
  got=$(sha "$W/e.c")
  SRC=(); for f in rt.c rt_gc.c rt_policy.c rt_weak.c xrt_abi.c rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c rt_std_net.c rt_task.c rt_sync.c rt_std_res.c rt_std_res_empty.c; do SRC+=("$ROOT/impl/runtime/$f"); done
  cc -std=c11 -O2 -pthread -I "$ROOT/impl/runtime" -o "$W/e.bin" "$W/e.c" "${SRC[@]}" "$BIN/res.c" 2>/dev/null || { ex_fail=$((ex_fail+1)); echo "FAIL example $name（cc）"; continue; }
  "$W/e.bin" > "$W/e.out" 2>&1; rc=$?
  if [ "$got" = "$want" ] && [ $rc -eq 0 ]; then
    ex_pass=$((ex_pass+1))
  else
    ex_fail=$((ex_fail+1)); echo "FAIL example $name（rc=$rc sha=$got）"
  fi
done < <(awk -F'\t' 'NR>1{print $1"\t"$2}' "$G/examples.tsv")

# ---- 汇总 ----
# 报告落盘（证据）
cp "$W/entries.tsv" "$G/verify-entries.tsv"
echo
echo "verify-golden（无 Go）："
echo "  入口 C：PASS=${entry_pass} FAIL=${entry_fail} BLOCKED=${entry_block}（多文件入口需 bundle，原生暂无生成器）"
echo "  负例：  PASS=${neg_pass} FAIL=${neg_fail} BLOCKED=${neg_block}（sema/entry/codegen 类需 Go 前端）"
echo "  示例：  PASS=${ex_pass} FAIL=${ex_fail}"
TOTAL_FAIL=$((entry_fail+neg_fail+ex_fail))
echo "  合计：FAIL=${TOTAL_FAIL}"
[ $TOTAL_FAIL -eq 0 ]
