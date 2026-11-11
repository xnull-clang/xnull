#!/usr/bin/env bash
# B4c-01：冻结 golden（不删除任何 Go）。
#
# 依据：B3-09 的 142 个入口（evidence/B3-09/final-v3/results.tsv，status=PASS0）
#       + 97 个负例（NEG-PASS）+ 9 个示例（tests/b2/corpus/examples）。
#
# 产物（默认 evidence/B4c/golden/）：
#   hashes.tsv      path / go_sha256 / xn_sha256 / lines / diff / b309_raw
#   negatives.tsv   path / go_exit / code / first_line
#   examples.tsv    example / go_c / xn_c / c_diff / go_run / xn_run / out_diff
#   b309-results.tsv（B3-09 原始结果副本）
#   cli-parity.txt  （B4b CLI 对拍矩阵快照）
#   main-commit.txt （冻结时的 main 提交）
#
# 用法：tests/b4/freeze-golden.sh
#   XNULL_GO_BIN   Go CLI（默认 /tmp/xnull-parity，缺失则 go build）
#   XNULLC_BIN     原生 xnullc（默认 /tmp/xn-s4）
#   XNAST_BIN      原生 oracle xnast（默认 /tmp/xnast-b4c01，缺失则 go build）
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
SRC=${B309_RESULTS:-$ROOT/evidence/B3-09/final-v3/results.tsv}
OUT=${GOLDEN_OUT:-$ROOT/evidence/B4c/golden}
W=$(mktemp -d "${TMPDIR:-/tmp}/b4c01.XXXXXX")
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"

GO=${XNULL_GO_BIN:-/tmp/xnull-parity}
[ -x "$GO" ] || ( cd "$ROOT/impl" && go build -o "$GO" ./cmd/xnull ) || { echo "freeze: 构建 Go CLI 失败" >&2; exit 1; }
XNAST=${XNAST_BIN:-/tmp/xnast-b4c01}
[ -x "$XNAST" ] || ( cd "$ROOT/impl" && go build -o "$XNAST" ./cmd/xnast ) || { echo "freeze: 构建 xnast 失败" >&2; exit 1; }
XN=${XNULLC_BIN:-/tmp/xn-s4}
[ -x "$XN" ] || { echo "freeze: 找不到原生 xnullc（/tmp/xn-s4）；用 XNULLC_BIN 指定" >&2; exit 1; }

export XNULL_FRONTEND=go

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# 投影候选：
#   A = 入口目录自带 .xfb 则按目录投影，否则空投影（B3-09 口径）；
#   B = 入口 import xdk.* 时，只保留「入口 + 被 import 模块源码」引用到的绑定条目（E 行）。
proj_A() { # rel out
  local rel=$1 out=$2 dir
  dir=$(dirname "$ROOT/$rel")
  : > "$out"
  if find "$dir" -name '*.xfb' 2>/dev/null | grep -q .; then
    python3 "$ROOT/tests/b3/xfb-projection.py" "$dir" > "$out"
  fi
}

proj_B() { # rel out
  local rel=$1 out=$2 mod src
  : > "$out"
  grep -q '^import xdk\.' "$ROOT/$rel" 2>/dev/null || return 0
  src="$W/srcs.txt"
  cat "$ROOT/$rel" > "$src"
  while IFS= read -r mod; do
    [ -f "$ROOT/impl/lib/xdk/$mod.x" ] && cat "$ROOT/impl/lib/xdk/$mod.x" >> "$src"
  done < <(sed -nE 's/^import xdk\.([a-z]+).*/\1/p' "$ROOT/$rel")
  python3 "$ROOT/tests/b3/xfb-projection.py" "$ROOT/bindings" > "$W/proj.all"
  awk -F'|' -v src="$src" 'BEGIN{while((getline l < src)>0) t=t"\n"l} $1=="E"{ if(index(t,$3"(")>0) print }' "$W/proj.all" > "$out"
}

# 用「oracle AST + 原生 xnullc」生成 C（与 Go --emit-c 同口径）；
# 原生失败或与 Go 不一致时，用 interp 跑同一 xnullc.x 重试（B3-09 的口径），并记录 via。
emit_xn_c() { # entry out.c projfile
  local rel=$1 out=$2 projfile=$3 ast bundle nf
  ( cd "$ROOT" && "$XNAST" --ast --dump-depth 100000 "$rel" ) > "$W/ast.txt" 2>/dev/null || return 1
  ( cd "$ROOT" && "$GO" --emit-ast-bundle "$rel" ) > "$W/bundle.json" 2>/dev/null || return 1
  nf=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["files"]))' "$W/bundle.json")
  local args=("$rel" --ast-file "$W/ast.txt" --project "$(cat "$projfile")")
  [ "$nf" -gt 1 ] && args+=(--bundle-file "$W/bundle.json")
  ( cd "$ROOT" && "$XN" "${args[@]}" ) > "$out" 2>"$W/xn.err" || return 1
  return 0
}

emit_interp_c() { # entry out.c projfile
  local rel=$1 out=$2 projfile=$3 ast bundle nf
  ( cd "$ROOT" && "$XNAST" --ast --dump-depth 100000 "$rel" ) > "$W/ast.txt" 2>/dev/null || return 1
  ( cd "$ROOT" && "$GO" --emit-ast-bundle "$rel" ) > "$W/bundle.json" 2>/dev/null || return 1
  nf=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["files"]))' "$W/bundle.json")
  local args=("$rel" --ast-file "$W/ast.txt" --project "$(cat "$projfile")")
  [ "$nf" -gt 1 ] && args+=(--bundle-file "$W/bundle.json")
  ( cd "$ROOT" && "$GO" run --interp "$ROOT/impl/lib/b3/xnullc.x" -- "${args[@]}" ) > "$out" 2>"$W/interp.err" || return 1
  return 0
}

echo "== 冻结 142 入口 C =="
printf 'path\tgo_sha256\txn_sha256\tlines\tdiff\tb309_raw\tvia\tproj\n' > "$OUT/hashes.tsv"
: > "$OUT/native-fallbacks.txt"
n_entry=0; n_diff=0
while IFS=$'\t' read -r rel raw; do
  [ -n "${rel:-}" ] || continue
  n_entry=$((n_entry+1))
  ( cd "$ROOT" && "$GO" build --emit-c "$rel" ) > "$W/go.c" 2>"$W/go.err"
  go_rc=$?
  if [ $go_rc -ne 0 ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "GO-FAIL($go_rc)" "-" "-" "1" "${raw:-}" "-" "-" >> "$OUT/hashes.tsv"
    n_diff=$((n_diff+1)); continue
  fi
  gs=$(sha "$W/go.c")
  via="-"; proj="-"; ok=0; xs="-"
  for p in A B; do
    if [ "$p" = A ]; then proj_A "$rel" "$W/proj.txt"; else proj_B "$rel" "$W/proj.txt"; fi
    if emit_xn_c "$rel" "$W/xn.c" "$W/proj.txt" && [ "$(sha "$W/xn.c")" = "$gs" ]; then
      via=native; proj=$p; ok=1; break
    fi
    if emit_interp_c "$rel" "$W/xn2.c" "$W/proj.txt" && [ "$(sha "$W/xn2.c")" = "$gs" ]; then
      cp "$W/xn2.c" "$W/xn.c"; via=interp; proj=$p; ok=1; break
    fi
  done
  [ -f "$W/xn.c" ] && xs=$(sha "$W/xn.c")
  lines=$(wc -l < "$W/go.c" | tr -d ' ')
  if [ $ok -eq 1 ]; then d=0; else d=1; n_diff=$((n_diff+1)); fi
  [ "$via" = interp ] && echo "$rel" >> "$OUT/native-fallbacks.txt"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$gs" "$xs" "$lines" "$d" "${raw:-}" "$via" "$proj" >> "$OUT/hashes.tsv"
  if [ $((n_entry % 25)) -eq 0 ]; then echo "  … ${n_entry} 个入口（diff=${n_diff}）"; fi
done < <(awk -F'\t' 'NR>1 && $9=="PASS0"{print $1"\t"$7}' "$SRC")
echo "入口：${n_entry} 个，diff=${n_diff}"

echo "== 冻结 97 负例 =="
printf 'path\tgo_exit\tcode\tfirst_line\n' > "$OUT/negatives.tsv"
n_neg=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  n_neg=$((n_neg+1))
  ( cd "$ROOT" && "$GO" build --emit-c "$rel" ) > /dev/null 2> "$W/neg.err"
  rc=$?
  first=$(head -1 "$W/neg.err")
  code=$(grep -oE 'error\[[A-Z]+-[0-9]+\]' "$W/neg.err" | head -1 | tr -d 'error[]')
  [ -n "$code" ] || code="-"
  printf '%s\t%s\t%s\t%s\n' "$rel" "$rc" "$code" "$first" >> "$OUT/negatives.tsv"
done < <(awk -F'\t' 'NR>1 && $9=="NEG-PASS"{print $1}' "$SRC")
echo "负例：${n_neg} 个"

echo "== 冻结 9 示例（C + 双路径运行）=="
printf 'example\tgo_c\txn_c\tc_diff\tgo_run\txn_run\tout_diff\n' > "$OUT/examples.tsv"
n_ex=0; n_exdiff=0
for f in "$ROOT"/tests/b2/corpus/examples/*.x; do
  [ -f "$f" ] || continue
  rel=${f#"$ROOT/"}
  name=$(basename "$f")
  n_ex=$((n_ex+1))
  ( cd "$ROOT" && "$GO" build --emit-c "$rel" ) > "$W/ex-go.c" 2>/dev/null || { n_exdiff=$((n_exdiff+1)); continue; }
  proj_A "$rel" "$W/ex-proj.txt"
  emit_xn_c "$rel" "$W/ex-xn.c" "$W/ex-proj.txt" || { n_exdiff=$((n_exdiff+1)); continue; }
  gs=$(sha "$W/ex-go.c"); xs=$(sha "$W/ex-xn.c")
  if [ "$gs" = "$xs" ]; then cd_=0; else cd_=1; n_exdiff=$((n_exdiff+1)); fi
  # 两路二进制
  ( cd "$ROOT" && "$GO" build "$rel" -o "$W/ex-go.bin" ) >/dev/null 2>&1
  "$ROOT/tests/b4/xnull-build.sh" build "$rel" -o "$W/ex-xn.bin" >/dev/null 2>&1
  if [ -x "$W/ex-go.bin" ]; then "$W/ex-go.bin" > "$W/ex-go.out" 2>&1; gr=$?; else gr=127; fi
  if [ -x "$W/ex-xn.bin" ]; then "$W/ex-xn.bin" > "$W/ex-xn.out" 2>&1; xr=$?; else xr=127; fi
  if [ "$gr" = "$xr" ] && cmp -s "$W/ex-go.out" "$W/ex-xn.out"; then od=0; else od=1; n_exdiff=$((n_exdiff+1)); fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$gs" "$xs" "$cd_" "$gr" "$xr" "$od" >> "$OUT/examples.tsv"
done
echo "示例：${n_ex} 个，diff=${n_exdiff}"

echo "== 保存基线证据 =="
cp "$SRC" "$OUT/b309-results.tsv"
"$ROOT/tests/b4/cli-parity.sh" > "$OUT/cli-parity.txt" 2>&1 || true
git -C "$ROOT" rev-parse HEAD > "$OUT/main-commit.txt"
git -C "$ROOT" rev-parse --abbrev-ref HEAD >> "$OUT/main-commit.txt"

echo
echo "hashes.tsv    $(($(wc -l < "$OUT/hashes.tsv")-1)) 行（diff=${n_diff}）"
echo "negatives.tsv $(($(wc -l < "$OUT/negatives.tsv")-1)) 行"
echo "examples.tsv  $(($(wc -l < "$OUT/examples.tsv")-1)) 行（diff=${n_exdiff}）"
TOTAL_DIFF=$((n_diff+n_exdiff))
echo "freeze-golden: diff=$TOTAL_DIFF"
[ $TOTAL_DIFF -eq 0 ]
