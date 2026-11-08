#!/usr/bin/env bash
# B2-04d 原生差分门禁：原生 xlex/xparser ↔ xnast oracle。
#
# 三层：
#   L1 tokens：native xlex <src>          ↔ xnast --tokens <file>
#   L2 AST   ：native xparser <src>       ↔ xnast --ast <file>
#   L3 diags ：native --diags <src>       ↔ xnast --diags <file>（规范化 code/line/col）
#
# 只作 B2-04d 门禁，不接入生产路径；默认前端仍为 go。
# 用法：
#   XNULL_NATIVE_XLEX=/path/xlex XNULL_NATIVE_XPARSER=/path/xparser bash tests/b2/native-diff.sh
# 退出码：0 全部一致；1 存在差异；2 环境/构建失败。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
XLEX=${XNULL_NATIVE_XLEX:-/tmp/native-xlex}
XPARSE=${XNULL_NATIVE_XPARSER:-/tmp/native-xparser}
ORACLE=${XNAST_BIN:-}
OUT=${NATIVE_DIFF_OUT:-"$ROOT/evidence/B2-04d/native-diff.tsv"}

if [ -z "$ORACLE" ]; then
  if ! ( cd "$ROOT/impl" && go build -o /tmp/xnast-native-diff ./cmd/xnast ); then
    echo "native-diff: 无法构建 xnast oracle" >&2
    exit 2
  fi
  ORACLE=/tmp/xnast-native-diff
fi
if [ ! -x "$XLEX" ]; then
  echo "native-diff: 缺少可执行的原生 xlex：$XLEX" >&2
  echo "  xnull build impl/lib/b2/xlex.x -o /tmp/native-xlex" >&2
  exit 2
fi
if [ ! -x "$XPARSE" ]; then
  echo "native-diff: 缺少可执行的原生 xparser：$XPARSE" >&2
  echo "  xnull build impl/lib/b2/xparser.x -o /tmp/native-xparser" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT")"
: > "$OUT"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/b2-native-diff.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

pass_l1=0; pass_l2=0; pass_l3=0
fail_l1=0; fail_l2=0; fail_l3=0
LAST_RC=0

# 保留文件末尾的换行（命令替换会剥掉）。
read_src() {
  local s
  s=$(cat "$1"; printf x)
  SRC=${s%x}
}

# 用子 shell 包一层：原生程序被信号杀死时，信号消息只进 err 文件，不污染差异清单。
run_native() {
  local out=$1 err=$2
  shift 2
  python3 - "$out" "$err" "$@" <<'PY'
import subprocess, sys
out, err = sys.argv[1], sys.argv[2]
args = sys.argv[3:]
with open(out, 'wb') as fo, open(err, 'wb') as fe:
    r = subprocess.run(args, stdout=fo, stderr=fe)
code = r.returncode
if code < 0:
    code = 128 - code
sys.exit(code)
PY
}

first_diff() {
  python3 - "$1" "$2" <<'PY'
import sys
a = open(sys.argv[1], 'rb').read()
b = open(sys.argv[2], 'rb').read()
i = 0
n = min(len(a), len(b))
while i < n and a[i] == b[i]:
    i += 1
print(i)
PY
}

snip() {
  python3 - "$1" "$2" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
i = int(sys.argv[2])
lo = max(0, i - 60)
hi = min(len(data), i + 120)
print(data[lo:hi].decode('utf-8', 'backslashreplace').replace('\n', '\\n'))
PY
}

report_fail() {
  local layer=$1 path=$2 want=$3 got=$4 idx w g
  idx=$(first_diff "$want" "$got")
  w=$(snip "$want" "$idx")
  g=$(snip "$got" "$idx")
  if [ "$LAST_RC" -ne 0 ]; then
    g="[exit $LAST_RC] $g"
  fi
  printf 'FAIL %-6s %s first-diff=%s\n' "$layer" "${path#"$ROOT"/}" "$idx"
  printf '  want: %s\n' "$w"
  printf '  got : %s\n' "$g"
  printf '%s\t%s\t%s\t%s\t%s\n' "$layer" "${path#"$ROOT"/}" "$idx" "$w" "$g" >> "$OUT"
}

check_pair() {
  local layer=$1 path=$2 want=$3 got=$4
  if [ "$LAST_RC" -eq 0 ] && cmp -s "$want" "$got"; then
    case "$layer" in
      L1) pass_l1=$((pass_l1 + 1)) ;;
      L2) pass_l2=$((pass_l2 + 1)) ;;
      L3) pass_l3=$((pass_l3 + 1)) ;;
    esac
    return 0
  fi
  report_fail "$layer" "$path" "$want" "$got"
  case "$layer" in
    L1) fail_l1=$((fail_l1 + 1)) ;;
    L2) fail_l2=$((fail_l2 + 1)) ;;
    L3) fail_l3=$((fail_l3 + 1)) ;;
  esac
}

check_tokens() {
  local f=$1
  "$ORACLE" --tokens "$f" > "$TMP/want.tok" 2>/dev/null
  read_src "$f"
  run_native "$TMP/got.tok" "$TMP/native.err" "$XLEX" "$SRC"
  LAST_RC=$?
  check_pair L1 "$f" "$TMP/want.tok" "$TMP/got.tok"
}

check_ast() {
  local f=$1
  "$ORACLE" --ast "$f" > "$TMP/want.ast" 2>/dev/null
  read_src "$f"
  run_native "$TMP/got.ast" "$TMP/native.err" "$XPARSE" "$SRC"
  LAST_RC=$?
  check_pair L2 "$f" "$TMP/want.ast" "$TMP/got.ast"
}

norm_oracle_diags() {
  sed -n 's/.*(Line \([0-9]*\)) (Col \([0-9]*\)) (Code "\([^"]*\)").*/\3 \1 \2/p'
}

check_diags() {
  local tool=$1 f=$2
  "$ORACLE" --diags "$f" 2>/dev/null | norm_oracle_diags > "$TMP/want.diag"
  read_src "$f"
  run_native "$TMP/raw.diag" "$TMP/native.err" "$tool" --diags "$SRC"
  LAST_RC=$?
  tail -n +2 "$TMP/raw.diag" > "$TMP/got.diag"
  check_pair L3 "$f" "$TMP/want.diag" "$TMP/got.diag"
}

# 预热：macOS 首次执行新建二进制可能很慢。
read_src "$ROOT/examples/hello.x"
run_native "$TMP/warm.out" "$TMP/warm.err" "$XLEX" "$SRC" || true
run_native "$TMP/warm.out" "$TMP/warm.err" "$XPARSE" "$SRC" || true

# 1) 冻结语料：三层全跑。
while IFS=$'\t' read -r hash rel; do
  case "$hash" in \#*|"") continue ;; esac
  f="$ROOT/$rel"
  check_tokens "$f"
  check_ast "$f"
  check_diags "$XPARSE" "$f"
done < "$HERE/corpus.tsv"

# 2) 正例：AST
for f in "$HERE"/parser_cases/*.x; do
  [ -e "$f" ] || continue
  check_ast "$f"
done

# 3) lexer 附加正例：tokens
for f in "$HERE"/lex_extra/*.x; do
  [ -e "$f" ] || continue
  check_tokens "$f"
done

# 4) lexer 负例：tokens + diags
for f in "$HERE"/lex_neg/*.x; do
  [ -e "$f" ] || continue
  check_tokens "$f"
  check_diags "$XLEX" "$f"
done

# 5) parser 负例：AST + diags
for f in "$HERE"/parser_neg/*.x; do
  [ -e "$f" ] || continue
  check_ast "$f"
  check_diags "$XPARSE" "$f"
done

total_pass=$((pass_l1 + pass_l2 + pass_l3))
total_fail=$((fail_l1 + fail_l2 + fail_l3))
echo "汇总：L1 PASS=${pass_l1} FAIL=${fail_l1}；L2 PASS=${pass_l2} FAIL=${fail_l2}；L3 PASS=${pass_l3} FAIL=${fail_l3}"
echo "总计：PASS=${total_pass} FAIL=${total_fail}；差异清单：${OUT#"$ROOT"/}"
[ "$total_fail" -eq 0 ]
