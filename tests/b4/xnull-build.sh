#!/usr/bin/env bash
# B4b-01：不依赖 Go CLI 的构建/运行管线原型。
#
# 管线：
#   <entry.x> --xnast--ast--> AST（Go oracle，B4c 前允许）
#   <entry.x> --xnull--emit-ast-bundle--> bundle（仅多文件入口需要）
#   xfb-projection.py --> --project 注册表
#   AST+bundle+project --native xnullc--> 生成 C
#   cc + impl/runtime 14 个 C 源 + 空资源表 --> 可执行文件
#
# 用法：
#   tests/b4/xnull-build.sh build <entry.x> [-o out] [--emit-c-only]
#   tests/b4/xnull-build.sh run <entry.x> [-- 程序参数...]
#   tests/b4/xnull-build.sh verify <entry.x>     # C 与 Go --emit-c 逐字节对比 + 双路径运行一致
#   tests/b4/xnull-build.sh examples             # 9 个示例全量验收
#   tests/b4/xnull-build.sh bootstrap-xnullc [-o out]   # 用解释器自举原生 xnullc（xn-s1）
#   tests/b4/xnull-build.sh bootstrap-xparser [-o out]  # 用 native xnullc 自举原生 xparser
#   tests/b4/xnull-build.sh ast-check [入口...]        # 原生 xparser AST vs xnast AST（全量深度）
#   tests/b4/xnull-build.sh bootstrap-model [-o dir]   # 自举 xpd / xmanifest（B4b-03a）
#   tests/b4/xnull-build.sh validate <project>         # 清单校验：模块/依赖边/拓扑（不编译）
#   tests/b4/xnull-build.sh build-project <dir> [-o d] # 聚合构建（library→对象，app→链接）
#   tests/b4/xnull-build.sh run-project <dir> [-- args] # 聚合构建并运行
#   tests/b4/xnull-build.sh tree <dir>                 # 依赖树（对齐 Go xnull tree）
#   tests/b4/xnull-build.sh why <dir> <coord>          # 依赖理由（对齐 Go xnull why）
#   tests/b4/xnull-build.sh install <dir> [--repo d]  # 聚合构建 + 安装到本地仓库
#   tests/b4/xnull-build.sh repro <dir>               # 连建两次，比较 C/对象/app 的 SHA-256
#   tests/b4/xnull-build.sh xmeta <dir>               # 生成模块 .xmeta（字段对齐 Go）
#   tests/b4/xnull-build.sh info
#
# 环境变量：
#   XNULLC_BIN       原生 xnullc（默认探测 /tmp/xn-s4 → /tmp/xn-s1）
#   XNULL_GO_BIN     Go oracle `xnull`（仅 AST/bundle/对比用；缺省按需 go build）
#   XNAST_BIN        Go oracle `xnast`（缺省按需 go build）
#   XNULL_B4_WORK    工作目录（默认 mktemp -d）
#   XNULL_FRONTEND   传给 oracle 的前端（默认 go，避免 auto 前端拖慢）
#
# 退出码：0 成功；1 构建/运行/比对失败；2 参数或环境错误。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
RUNTIME="$ROOT/impl/runtime"
REV=$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo work)
export XNULL_FRONTEND=${XNULL_FRONTEND:-go}

# 与 Go codegen 保持一致的运行时 C 源顺序（impl/internal/codegen/build.go:36）。
RUNTIME_SRCS=(
  rt.c rt_gc.c rt_policy.c rt_weak.c xrt_abi.c
  rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c rt_std_net.c
  rt_task.c rt_sync.c rt_std_res.c rt_std_res_empty.c
)

die() { echo "xnull-build: $*" >&2; exit 2; }
fail() { echo "xnull-build: $*" >&2; exit 1; }

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

# oracle 二进制（仅 AST/bundle 与验收对比；不参与生成 C）
go_bin() {
  if [ -n "${XNULL_GO_BIN:-}" ]; then echo "$XNULL_GO_BIN"; return; fi
  local p="/tmp/xnull-b4-$REV"
  [ -x "$p" ] || ( cd "$ROOT/impl" && go build -o "$p" ./cmd/xnull ) || fail "构建 oracle xnull 失败" >&2
  echo "$p"
}
xnast_bin() {
  if [ -n "${XNAST_BIN:-}" ]; then echo "$XNAST_BIN"; return; fi
  local p="/tmp/xnast-b4-$REV"
  [ -x "$p" ] || ( cd "$ROOT/impl" && go build -o "$p" ./cmd/xnast ) || fail "构建 oracle xnast 失败" >&2
  echo "$p"
}

# 原生 xnullc：显式指定优先，其次 /tmp/xn-s4、/tmp/xn-s1。
xnullc_bin() {
  local c=""
  for c in "${XNULLC_BIN:-}" /tmp/xn-s4 /tmp/xn-s1; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  cat >&2 <<'EOF'
xnull-build: 找不到原生 xnullc。任选其一：
  1) 指定已有二进制：XNULLC_BIN=/path/to/xnullc tests/b4/xnull-build.sh ...
  2) 自举一份：tests/b4/xnull-build.sh bootstrap-xnullc -o /tmp/xn-s1
EOF
  return 1
}

# 原生 xparser（B4b-02）：显式指定优先，其次 /tmp/xparser-native（bootstrap-xparser 产出）。
xparser_bin() {
  local c=""
  for c in "${XPARSER_BIN:-}" /tmp/xparser-native; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

# AST 来源：优先原生 xparser --file；失败（崩溃/空输出）回退 Go oracle（B4c 前允许）。
ast_dump() {
  local entry=$1 out=$2
  local xp=""
  if xp=$(xparser_bin); then
    # 原生 xparser 对个别输入会挂起/输出非 AST：限时 60s 且校验首行，否则回退 oracle。
    ( cd "$ROOT" && perl -e 'alarm 60; exec @ARGV' "$xp" --file "$entry" ) > "$out" 2>"$out.err"
    if [ $? -eq 0 ] && [ -s "$out" ] && [ "$(head -c 9 "$out")" = "(xnast v1" ]; then return 0; fi
    echo "xnull-build: 原生 xparser 失败或无输出（$(wc -c < "$out") 字节），回退 xnast：$entry" >&2
  fi
  local xnast; xnast=$(xnast_bin) || exit 1
  ( cd "$ROOT" && "$xnast" --ast --dump-depth 100000 "$entry" ) > "$out" \
    || fail "AST 生成失败：$entry"
}

workdir() {
  if [ -n "${XNULL_B4_WORK:-}" ]; then mkdir -p "$XNULL_B4_WORK"; echo "$XNULL_B4_WORK"; return; fi
  mktemp -d "${TMPDIR:-/tmp}/b4b01.XXXXXX"
}

# oracle 三件套：ast / bundle 文件数 / 投影
oracle_inputs() {
  local entry=$1 outdir=$2 projdir=${3:-}
  local go; go=$(go_bin) || exit 1
  ast_dump "$entry" "$outdir/ast.txt" || exit 1
  ( cd "$ROOT" && "$go" --emit-ast-bundle "$entry" ) > "$outdir/bundle.json" || fail "bundle 生成失败：$entry"
  # 投影目录选择：
  #   - 显式传入优先（自举 xnullc 用 $ROOT/bindings）；
  #   - 入口 import xdk.*：用 repo 的 canonical bindings/（否则 xn_ffi_* 未定义）；
  #   - 其余：按入口目录投影，与 Go `--emit-c` 的差分口径一致（不多发未用 FFI 包装）。
  if [ -z "$projdir" ]; then
    if grep -q '^import xdk\.' "$ROOT/$entry" 2>/dev/null || grep -q '^import xdk\.' "$entry" 2>/dev/null; then
      projdir="$ROOT/bindings"
    else
      projdir=$(dirname "$ROOT/$entry")
    fi
  fi
  python3 "$ROOT/tests/b3/xfb-projection.py" "$projdir" > "$outdir/project.txt" \
    || fail "FFI 投影失败：$entry"
  python3 - "$outdir/bundle.json" <<'PY' || fail "bundle 解析失败：$entry"
import json, sys
b = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if len(b.get("files", [])) >= 1 else 1)
PY
  python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1],encoding="utf-8")).get("files",[])))' "$outdir/bundle.json"
}

# 生成 C：原生 xnullc + oracle AST/bundle/project
emit_c() {
  local entry=$1 outdir=$2 out=$3
  mkdir -p "$outdir"
  local nf; nf=$(oracle_inputs "$entry" "$outdir") || exit 1
  local xc; xc=$(xnullc_bin) || exit 1
  local args=("$entry" --ast-file "$outdir/ast.txt" --project "$(cat "$outdir/project.txt")")
  if [ "$nf" -gt 1 ]; then
    args+=(--bundle-file "$outdir/bundle.json")
  fi
  ( cd "$ROOT" && "$xc" "${args[@]}" ) > "$out" 2> "$outdir/xnullc.err"
  local rc=$?
  if [ $rc -ne 0 ]; then
    sed -n 1,5p "$outdir/xnullc.err" >&2
    fail "原生 xnullc 生成 C 失败：${entry}（exit ${rc}）"
  fi
  echo "$nf"
}

# 零资源工程的空资源表（与 impl/internal/codegen/build.go emptyResourceTableC 等价）
write_empty_res() {
  cat > "$1" <<'EOF'
/* 由 xnull build 生成：零资源工程空表（S8 §5.6） */
#include <stddef.h>
#include <string.h>

size_t xrt_resource_count(void) { return 0; }

int xrt_resource_get(const char *name, size_t nlen,
                     const unsigned char **out, size_t *out_len) {
    (void)name; (void)nlen;
    *out = 0; *out_len = 0;
    return 1;
}

int xrt_resource_at(size_t i, const char **name, size_t *nlen,
                    const unsigned char **out, size_t *out_len) {
    (void)i;
    *name = 0; *nlen = 0; *out = 0; *out_len = 0;
    return 1;
}
EOF
}

# cc 链接：生成的 C + 14 个运行时源 + 空资源表
cc_link() {
  local cfile=$1 out=$2 res=$3
  local srcs=()
  local s
  for s in "${RUNTIME_SRCS[@]}"; do srcs+=("$RUNTIME/$s"); done
  if ! cc -std=c11 -O2 -pthread -I "$RUNTIME" -o "$out" "$cfile" "${srcs[@]}" "$res" 2> "${out}.cc.log"; then
    sed -n 1,10p "${out}.cc.log" >&2
    fail "cc 链接失败：$cfile"
  fi
}

cmd_build() {
  local entry="" out="" emit_only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -o|--output) out=${2:-}; shift 2 ;;
      --emit-c-only) emit_only=1; shift ;;
      -*) die "未知参数：$1" ;;
      *) entry=$1; shift ;;
    esac
  done
  [ -n "$entry" ] || usage
  [ -f "$ROOT/$entry" ] || [ -f "$entry" ] || die "入口不存在：$entry"
  [ -f "$entry" ] && entry=${entry#"$ROOT/"}
  local w; w=$(workdir) || exit 1
  local base
  if [ -n "$out" ]; then
    base=${out%.c}; base=${base%.exe}
  else
    base="$w/a.out"
  fi
  mkdir -p "$(dirname "$base")"
  emit_c "$entry" "$w" "$base.c" > /dev/null || exit 1
  if [ "$emit_only" = 1 ]; then echo "$base.c"; return 0; fi
  write_empty_res "$base.res.c"
  cc_link "$base.c" "$base" "$base.res.c" || exit 1
  echo "$base"
}

cmd_run() {
  local entry="" extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --) shift; extra=("$@"); break ;;
      -*) die "未知参数：$1" ;;
      *) entry=$1; shift ;;
    esac
  done
  [ -n "$entry" ] || usage
  local bin; bin=$(cmd_build "$entry") || exit 1
  [ -n "$bin" ] && [ -x "$bin" ] || fail "构建未产出可执行文件：$entry"
  # bash 3.2 + set -u：空数组展开会报错，分开处理
  if [ ${#extra[@]} -gt 0 ]; then "$bin" "${extra[@]}"; else "$bin"; fi
}

# 验收单个示例：C 逐字节一致 + 二次生成可复现 + 原生/Go 两路运行一致 + interp 对照
cmd_verify() {
  local entry=$1
  local w; w=$(workdir) || exit 1
  local go; go=$(go_bin) || exit 1
  ( cd "$ROOT" && "$go" build --emit-c "$entry" ) > "$w/go.c" 2> "$w/go.err" \
    || { sed -n 1,3p "$w/go.err" >&2; fail "Go emit-c 失败：$entry"; }
  emit_c "$entry" "$w" "$w/native.c" > /dev/null || exit 1
  emit_c "$entry" "$w/n2" "$w/native2.c" > /dev/null || exit 1
  cmp -s "$w/go.c" "$w/native.c" || { diff -u "$w/go.c" "$w/native.c" | head -10 >&2; fail "C 与 Go 不一致：$entry"; }
  cmp -s "$w/native.c" "$w/native2.c" || fail "二次生成不一致：$entry"
  write_empty_res "$w/res.c"
  cc_link "$w/native.c" "$w/native.bin" "$w/res.c" || exit 1
  cc_link "$w/go.c" "$w/go.bin" "$w/res.c" || exit 1
  "$w/native.bin" > "$w/native.out" 2>"$w/native.err"; local nc=$?
  "$w/go.bin" > "$w/go.out" 2>"$w/go.err"; local gc=$?
  local ic=""
  ( cd "$ROOT" && "$go" run --interp "$ROOT/$entry" > "$w/interp.out" 2>"$w/interp.err" ); ic=$?
  if [ "$nc" != "$gc" ] || ! cmp -s "$w/native.out" "$w/go.out"; then
    fail "native/Go 两路运行不一致：${entry}（exit $nc/${gc}）"
  fi
  if [ "$nc" != "$ic" ] || ! cmp -s "$w/native.out" "$w/interp.out"; then
    fail "interp/native 双路径不一致：${entry}（exit $ic/${nc}）"
  fi
  echo "PASS $entry sha256=$(shasum -a 256 "$w/native.c" | awk '{print $1}')"
}

# 9 示例全量验收（tests/b2/corpus/examples/*.x，不含 multi/ 目录）
cmd_examples() {
  local pass=0 failn=0 f name
  for f in "$ROOT"/tests/b2/corpus/examples/*.x; do
    [ -f "$f" ] || continue
    name=${f#"$ROOT/"}
    if cmd_verify "$name"; then pass=$((pass+1)); else echo "FAIL $name"; failn=$((failn+1)); fi
  done
  echo "B4b-01 examples：PASS=$pass FAIL=$failn"
  [ "$failn" -eq 0 ]
}

# 自举原生 xnullc：解释执行 xnullc.x 生成 C，再 cc 成二进制（xn-s1）
cmd_bootstrap() {
  local out=/tmp/xn-s1
  if [ "${1:-}" = "-o" ]; then out=${2:-}; [ -n "$out" ] || die "-o 缺少路径"; fi
  local w; w=$(workdir) || exit 1
  local entry=impl/lib/b3/xnullc.x
  # 自举 xnullc 用 repo 的 canonical bindings 目录投影：整仓投影会撞上 impl/xnfmt、evidence 下的
  # 同名 .xfb，导致 xn_ffi_<name> 重复定义。
  local nf; nf=$(oracle_inputs "$entry" "$w" "$ROOT/bindings") || exit 1
  local go; go=$(go_bin) || exit 1
  local args=("$ROOT/$entry" --ast-file "$w/ast.txt" --project "$(cat "$w/project.txt")")
  [ "$nf" -gt 1 ] && args+=(--bundle-file "$w/bundle.json")
  ( cd "$ROOT" && "$go" run --interp "$ROOT/$entry" -- "${args[@]}" ) > "$w/xnullc.c" 2> "$w/self.err" \
    || { sed -n 1,5p "$w/self.err" >&2; fail "自举生成 C 失败"; }
  write_empty_res "$w/res.c"
  cc_link "$w/xnullc.c" "$out" "$w/res.c" || exit 1
  echo "$out"
}

# 用 Go interp 跑 xnullc.x 生成 C（native xnullc 对部分模式不稳定时的可靠回退）。
# 用法：emit_c_interp <entry.x> <out.c> [投影目录]
emit_c_interp() {
  local entry=$1 out=$2 projdir=${3:-$ROOT/bindings}
  local w; w=$(workdir) || exit 1
  local nf; nf=$(oracle_inputs "$entry" "$w" "$projdir") || exit 1
  local go; go=$(go_bin) || exit 1
  local args=("$entry" --ast-file "$w/ast.txt" --project "$(cat "$w/project.txt")")
  if [ "$nf" -gt 1 ]; then args+=(--bundle-file "$w/bundle.json"); fi
  ( cd "$ROOT" && "$go" run --interp "$ROOT/impl/lib/b3/xnullc.x" -- "${args[@]}" ) > "$out" 2> "$w/interp.err" \
    || { sed -n 1,5p "$w/interp.err" >&2; fail "interp 生成 C 失败：$entry"; }
  write_empty_res "$w/res.c"
  echo "$w/res.c"
}

# 自举 resman/config/artifact（B4b-03b-2）：统一走 interp 路径，避开 native xnullc 的模式缺陷
cmd_bootstrap_tools() {
  local dir=/tmp
  if [ "${1:-}" = "-o" ]; then dir=${2:-}; [ -n "$dir" ] || die "-o 缺少目录"; mkdir -p "$dir"; fi
  local t entry res
  for t in resman artifact config deps xmeta; do
    entry="impl/lib/b4/$t.x"
    [ -f "$ROOT/$entry" ] || continue
    res=$(emit_c_interp "$entry" "$dir/$t.c") || exit 1
    cc_link "$dir/$t.c" "$dir/$t" "$res" || exit 1
    echo "$dir/$t"
  done
}

# 自举 reactor（B4b-03b-1）：聚合构建驱动
cmd_bootstrap_reactor() {
  local dir=/tmp
  if [ "${1:-}" = "-o" ]; then dir=${2:-}; [ -n "$dir" ] || die "-o 缺少目录"; mkdir -p "$dir"; fi
  emit_c impl/lib/b4/reactor.x "$dir/.reactor" "$dir/.reactor/reactor.c" > /dev/null || exit 1
  write_empty_res "$dir/.reactor/res.c"
  cc_link "$dir/.reactor/reactor.c" "$dir/reactor" "$dir/.reactor/res.c" || exit 1
  echo "$dir/reactor"
}

# 准备清单 TSV（root.tsv + m/*.tsv），失败返回 1
prepare_model() {
  local proj=$1 w=$2
  local xpd=${XPD_BIN:-/tmp/xpd}
  mkdir -p "$w/m"
  "$xpd" "$proj/xnull.project" > "$w/root.tsv" || return 1
  local rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -f "$proj/$rel/xnull.project" ]; then
      echo "xnull-build: error XPD-201 模块缺少 xnull.project：$rel" >&2
      return 1
    fi
    "$xpd" "$proj/$rel/xnull.project" > "$w/m/$(printf '%s' "$rel" | tr '/' '_').tsv" || return 1
  done < <(awk -F'\t' '$1=="module"{print $2}' "$w/root.tsv")
}

# 准备依赖图 TSV：目标工程 + 其所属聚合的所有模块（近似 Go 从本地仓库读传递清单）
prepare_graph() {
  local proj=$1 w=$2
  local xpd=${XPD_BIN:-/tmp/xpd}
  mkdir -p "$w"
  "$xpd" "$proj/xnull.project" > "$w/target.tsv" || return 1
  local target_coord
  target_coord=$(awk -F'\t' '$1=="field" && $2=="groupId"{g=$3} $1=="field" && $2=="artifactId"{a=$3} END{print g":"a}' "$w/target.tsv")
  # 向上找聚合根（packaging = pom 且含 modules）
  local dir=$proj root=""
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/xnull.project" ] && awk -F'=' '/^[[:space:]]*packaging[[:space:]]*=/{v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print v; exit}' "$dir/xnull.project" | grep -qx pom; then
      root=$dir
    fi
    [ "$dir" = "$ROOT" ] && break
    dir=$(dirname "$dir")
  done
  [ -n "$root" ] || return 0
  "$xpd" "$root/xnull.project" > "$w/agg-root.tsv" || return 1
  local rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$root/$rel/xnull.project" ] || continue
    "$xpd" "$root/$rel/xnull.project" > "$w/agg-$(printf '%s' "$rel" | tr '/' '_').tsv" || return 1
  done < <(awk -F'\t' '$1=="module"{print $2}' "$w/agg-root.tsv")
  # 若目标本身不是聚合根，仍以目标作为根输出（其坐标已写入 target.tsv）
  return 0
}

# 元数据输入（B4b-04b-2）：按 Go projectManifest.xmeta 的口径计算摘要
gen_meta() {
  local proj=$1 out=$2
  python3 - "$proj" "$out" <<'PY'
import hashlib, os, sys, glob
proj, out = sys.argv[1], sys.argv[2]
def sha(b): return hashlib.sha256(b).hexdigest()
empty = sha(b"")
# 找 app 模块（packaging = app）
app = ""
for d in sorted(glob.glob(os.path.join(proj, "*", "xnull.project"))):
    txt = open(d, encoding="utf-8").read()
    if "packaging" in txt and "app" in txt:
        app = os.path.dirname(d)
res_dir = os.path.join(app, "src", "main", "resources") if app else ""
lines = []
if res_dir and os.path.isdir(res_dir):
    for name in sorted(os.listdir(res_dir)):
        p = os.path.join(res_dir, name)
        if os.path.isfile(p):
            data = open(p, "rb").read()
            lines.append("resources/" + name + "\x00" + sha(data))
ressha = sha("\n".join(lines).encode()) if lines else empty
lock = os.path.join(proj, "xnull.lock")
lockbytes = open(lock, "rb").read() if os.path.isfile(lock) else b""
locksha = sha(lockbytes) if lockbytes else empty
cfgsha = empty
pluginsha = empty
toolchain = "0.1.0-dev"
# Go 口径：参与 inputs 的是 **app 模块** 的清单原文（不是聚合根）
mpath = os.path.join(app, "xnull.project") if app else os.path.join(proj, "xnull.project")
manifest = open(mpath, "rb").read()
entry = b""
if app:
    ep = os.path.join(app, "src", "main", "x", "main.x")
    if os.path.isfile(ep):
        entry = open(ep, "rb").read()
h = hashlib.sha256()
for part in [manifest, entry, lockbytes, toolchain.encode(), (ressha + cfgsha + pluginsha).encode()]:
    h.update(part); h.update(b"\x00")
platform = "macos" if os.uname().sysname == "Darwin" else os.uname().sysname.lower()
with open(out, "w", encoding="utf-8") as f:
    f.write("platform\t%s\n" % platform)
    f.write("toolchainVersion\t%s\n" % toolchain)
    f.write("resourcesSha256\t%s\n" % ressha)
    f.write("lockSha256\t%s\n" % locksha)
    f.write("configSha256\t%s\n" % cfgsha)
    f.write("pluginsSha256\t%s\n" % pluginsha)
    f.write("inputs\t%s\n" % h.hexdigest())
PY
}

# 模块元数据（B4b-04b-2）：xmeta <project>
cmd_xmeta() {
  local proj=${1:-}; [ -n "$proj" ] || usage
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  local xpd=${XPD_BIN:-/tmp/xpd} xm=${XMETA_BIN:-/tmp/xmeta}
  [ -x "$xpd" ] || cmd_bootstrap_model -o /tmp > /dev/null || exit 1
  [ -x "$xm" ] || cmd_bootstrap_tools -o /tmp > /dev/null || exit 1
  local w; w=$(workdir) || exit 1
  prepare_graph "$proj" "$w" || exit 1
  gen_meta "$proj" "$w/meta.tsv" || exit 1
  local files=("$w/target.tsv") f
  for f in "$w"/agg-*.tsv; do
    [ -e "$f" ] || continue
    [ "$f" = "$w/agg-root.tsv" ] && continue
    files+=("$f")
  done
  "$xm" "$w/xmeta" "$w/meta.tsv" ${files[@]+"${files[@]}"}
  echo "$w/xmeta"
}

# 可复现性（B4b-04b-2）：连续两次构建，比较 C/对象/app 的 SHA-256
cmd_repro() {
  local proj=${1:-}; [ -n "$proj" ] || usage
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  local base=${XNULL_B4_OUT:-/tmp/b4-repro-$(basename "$proj")}
  rm -rf "$base"; mkdir -p "$base"
  local d
  for d in a b; do
    run_reactor "$proj" "$base/$d" > "$base/$d.log" 2>&1 || { echo "repro: 第 $d 次构建失败" >&2; tail -5 "$base/$d.log" >&2; return 1; }
  done
  local pass=0 failn=0 name sa sb
  for name in $(cd "$base/a" && ls *.c *.o app 2>/dev/null); do
    sa=$(shasum -a 256 "$base/a/$name" 2>/dev/null | cut -d' ' -f1)
    sb=$(shasum -a 256 "$base/b/$name" 2>/dev/null | cut -d' ' -f1)
    if [ "$sa" = "$sb" ] && [ -n "$sa" ]; then
      echo "same	$name	$sa"; pass=$((pass+1))
    else
      echo "diff	$name	$sa	$sb"; failn=$((failn+1))
    fi
  done
  echo "repro: same=${pass} diff=${failn}（${proj}）"
  [ "$failn" -eq 0 ]
}

# 依赖树（B4b-04a）：tree <project>
cmd_tree() {
  local proj=${1:-}; [ -n "$proj" ] || usage
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  [ -f "$proj/xnull.project" ] || fail "缺少 xnull.project：$proj"
  local xpd=${XPD_BIN:-/tmp/xpd} deps=${DEPS_BIN:-/tmp/deps}
  [ -x "$xpd" ] || cmd_bootstrap_model -o /tmp > /dev/null || exit 1
  [ -x "$deps" ] || cmd_bootstrap_tools -o /tmp > /dev/null || exit 1
  local w; w=$(workdir) || exit 1
  prepare_graph "$proj" "$w" || exit 1
  local files=("$w/target.tsv") f
  for f in "$w"/agg-*.tsv; do [ -e "$f" ] && files+=("$f"); done
  "$deps" tree "${files[@]}"
}

# 依赖理由（B4b-04a）：why <project> <groupId:artifactId>
cmd_why() {
  local proj=${1:-} coord=${2:-}
  [ -n "$proj" ] && [ -n "$coord" ] || usage
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  local xpd=${XPD_BIN:-/tmp/xpd} deps=${DEPS_BIN:-/tmp/deps}
  [ -x "$xpd" ] || cmd_bootstrap_model -o /tmp > /dev/null || exit 1
  [ -x "$deps" ] || cmd_bootstrap_tools -o /tmp > /dev/null || exit 1
  local w; w=$(workdir) || exit 1
  prepare_graph "$proj" "$w" || exit 1
  local files=("$w/target.tsv") f
  for f in "$w"/agg-*.tsv; do [ -e "$f" ] && files+=("$f"); done
  "$deps" why "$coord" "${files[@]}"
}

# 聚合工程构建（B4b-03b-1）：拓扑序 → 每模块 emit-c → library 出对象 → app 链接。
# 用法：build-project <dir> [-o 输出目录]
# 统一的 reactor 调用：确保工具就绪后执行 build-project
run_reactor() {
  local proj=$1 out=$2 repo=${3:-}
  local xpd=${XPD_BIN:-/tmp/xpd} xmf=${XMANIFEST_BIN:-/tmp/xmanifest} rct=${REACTOR_BIN:-/tmp/reactor}
  if [ ! -x "$xpd" ] || [ ! -x "$xmf" ]; then cmd_bootstrap_model -o /tmp > /dev/null || exit 1; fi
  [ -x "$rct" ] || cmd_bootstrap_reactor -o /tmp > /dev/null || exit 1
  local toolArgs=()
  local t
  for t in resman artifact config deps xmeta; do
    if [ ! -x "/tmp/$t" ]; then cmd_bootstrap_tools -o /tmp > /dev/null || exit 1; break; fi
  done
  [ -x /tmp/resman ] && toolArgs+=(--resman /tmp/resman)
  [ -x /tmp/artifact ] && toolArgs+=(--artifact /tmp/artifact)
  [ -x /tmp/config ] && toolArgs+=(--config /tmp/config)
  local xc; xc=$(xnullc_bin) || exit 1
  local xnast; xnast=$(xnast_bin) || exit 1
  local extra=()
  [ -n "$repo" ] && extra+=(--repo "$repo")
  # bash 3.2 + set -u：空数组展开需显式保护
  "$rct" build-project "$proj" \
    --xpd "$xpd" --xmanifest "$xmf" --xnullc "$xc" --xnast "$xnast" \
    --runtime "$ROOT/impl/runtime" --out "$out" \
    ${extra[@]+"${extra[@]}"} ${toolArgs[@]+"${toolArgs[@]}"}
}

cmd_build_project() {
  local proj=${1:-} out=""
  [ -n "$proj" ] || usage
  shift || true
  if [ "${1:-}" = "-o" ]; then out=${2:-}; fi
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  [ -n "$out" ] || out=${XNULL_B4_OUT:-/tmp/b4-proj-$(basename "$proj")}
  run_reactor "$proj" "$out"
}

# 安装（B4b-04b-1）：build-project + 每模块落本地仓库
# 用法：install <project> [--repo <dir>]（默认 $XNULL_REPO 或 /tmp/b4-install-repo）
cmd_install() {
  local proj=${1:-} repo=""
  [ -n "$proj" ] || usage
  shift || true
  if [ "${1:-}" = "--repo" ]; then repo=${2:-}; fi
  [ -n "$repo" ] || repo=${XNULL_REPO:-/tmp/b4-install-repo}
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  local out=${XNULL_B4_OUT:-/tmp/b4-proj-$(basename "$proj")}
  run_reactor "$proj" "$out" "$repo"
}

# 聚合工程构建并运行：run-project <dir> [-- 程序参数]
cmd_run_project() {
  local proj="" extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --) shift; extra=("$@"); break ;;
      *) proj=$1; shift ;;
    esac
  done
  [ -n "$proj" ] || usage
  local out=${XNULL_B4_OUT:-/tmp/b4-proj-$(basename "$proj")}
  cmd_build_project "$proj" >&2 || exit 1
  [ -x "$out/app" ] || fail "没有 app 产物：$out/app"
  if [ ${#extra[@]} -gt 0 ]; then "$out/app" "${extra[@]}"; else "$out/app"; fi
}

# 自举工程模型工具（B4b-03a）：xpd（清单→TSV）+ xmanifest（TSV→模块/依赖/拓扑）
cmd_bootstrap_model() {
  local dir=/tmp
  if [ "${1:-}" = "-o" ]; then dir=${2:-}; [ -n "$dir" ] || die "-o 缺少目录"; mkdir -p "$dir"; fi
  emit_c impl/lib/b4/xpd.x "$dir/.xpd" "$dir/.xpd/xpd.c" > /dev/null || exit 1
  write_empty_res "$dir/.xpd/res.c"
  cc_link "$dir/.xpd/xpd.c" "$dir/xpd" "$dir/.xpd/res.c" || exit 1
  emit_c impl/lib/b4/manifest.x "$dir/.xm" "$dir/.xm/manifest.c" > /dev/null || exit 1
  write_empty_res "$dir/.xm/res.c"
  cc_link "$dir/.xm/manifest.c" "$dir/xmanifest" "$dir/.xm/res.c" || exit 1
  echo "$dir/xpd"
  echo "$dir/xmanifest"
}

# 清单校验（B4b-03a）：只跑清单解析与工程模型，不编译、不碰 xnullc 之外的产物。
# 用法：validate <project 目录或 xnull.project 路径>
cmd_validate() {
  local proj=${1:-}
  [ -n "$proj" ] || usage
  if [ -f "$proj" ]; then proj=$(cd "$(dirname "$proj")" && pwd); else proj=$(cd "$proj" && pwd) || die "目录不存在"; fi
  [ -f "$proj/xnull.project" ] || fail "缺少 xnull.project：$proj"
  local xpd=${XPD_BIN:-/tmp/xpd}
  local xmf=${XMANIFEST_BIN:-/tmp/xmanifest}
  if [ ! -x "$xpd" ] || [ ! -x "$xmf" ]; then
    cmd_bootstrap_model -o "${XNULL_B4_MODEL_DIR:-/tmp}" > /dev/null || exit 1
  fi
  local w; w=$(workdir) || exit 1
  "$xpd" "$proj/xnull.project" > "$w/root.tsv" || fail "清单解析失败：$proj/xnull.project"
  local files=("$w/root.tsv") seen=() rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -d "$proj/$rel" ]; then
      echo "validate: error XPD-201 模块目录不存在：$rel" >&2
      return 1
    fi
    if [ ! -f "$proj/$rel/xnull.project" ]; then
      echo "validate: error XPD-201 模块缺少 xnull.project：$rel" >&2
      return 1
    fi
    "$xpd" "$proj/$rel/xnull.project" > "$w/m-${rel//\//_}.tsv" || fail "清单解析失败：$rel/xnull.project"
    files+=("$w/m-${rel//\//_}.tsv")
  done < <(awk -F'\t' '$1=="module"{print $2}' "$w/root.tsv")
  local out rc
  out=$("$xmf" "${files[@]}" 2>&1); rc=$?
  echo "$out"
  if [ $rc -ne 0 ]; then
    echo "validate: FAIL（${proj}）" >&2
    return 1
  fi
  local mods
  mods=$(awk -F'\t' '$1=="module"' "$w/root.tsv" | wc -l | tr -d ' ')
  if [ "$mods" -gt 0 ] && ! awk -F'\t' '$1=="project" && $4!="pom"{exit 1}' <<<"$out"; then
    echo "validate: error XPD-201 含 modules 的聚合根必须 packaging = pom" >&2
    return 1
  fi
  echo "validate: OK（${proj}，模块 ${mods} 个）"
}

# 自举原生 xparser（B4b-02）：用当前 native xnullc 把 xparser.x 编成可执行文件
cmd_bootstrap_xparser() {
  local out=/tmp/xparser-native
  if [ "${1:-}" = "-o" ]; then out=${2:-}; [ -n "$out" ] || die "-o 缺少路径"; fi
  local w; w=$(workdir) || exit 1
  emit_c impl/lib/b2/xparser.x "$w" "$w/xparser.c" > /dev/null || exit 1
  write_empty_res "$w/res.c"
  cc_link "$w/xparser.c" "$out" "$w/res.c" || exit 1
  echo "$out"
}

# AST 一致性验收：原生 xparser --file 与 xnast --ast（全量深度）逐字节比较
cmd_ast_check() {
  local entries=("$@")
  if [ ${#entries[@]} -eq 0 ]; then
    for f in "$ROOT"/tests/b2/corpus/examples/*.x; do [ -f "$f" ] && entries+=("${f#"$ROOT/"}"); done
    entries+=(impl/lib/b2/xparser.x impl/lib/b2/xlex.x impl/xnfmt/xnfmt.x)
  fi
  local xp; xp=$(xparser_bin) || { echo "xnull-build: 没有原生 xparser（先跑 bootstrap-xparser）" >&2; exit 2; }
  local xnast; xnast=$(xnast_bin) || exit 1
  local w; w=$(workdir) || exit 1
  local pass=0 failn=0 e
  for e in "${entries[@]}"; do
    ( cd "$ROOT" && "$xnast" --ast --dump-depth 100000 "$e" ) > "$w/go.ast" 2>/dev/null
    ( cd "$ROOT" && "$xp" --file "$e" ) > "$w/xp.ast" 2>"$w/xp.err"; local rc=$?
    if [ $rc -eq 0 ] && cmp -s "$w/go.ast" "$w/xp.ast"; then
      pass=$((pass+1)); echo "PASS $e"
    else
      failn=$((failn+1)); echo "DIFF ${e}（rc=${rc}，oracle=$(wc -c < "$w/go.ast") 字节，xparser=$(wc -c < "$w/xp.ast") 字节）"
    fi
  done
  echo "AST 一致性：PASS=$pass DIFF=$failn"
  [ "$failn" -eq 0 ]
}

# 版本信息（B4b-05 对拍用；格式仿 Go `-v`，无 specs 行）
cmd_version() {
  echo "xnull 0.1.0-dev"
  echo "commit: dev"
  echo "build date: unknown"
  echo "abi: v1"
}

cmd_info() {
  echo "root=$ROOT"
  echo "rev=$REV"
  local xc; xc=$(xnullc_bin) && echo "xnullc=$xc ($(shasum -a 256 "$xc" | awk '{print $1}'))" || echo "xnullc=（未找到）"
  echo "xnull=$(go_bin)"; echo "xnast=$(xnast_bin)"
  local xp; xp=$(xparser_bin) && echo "xparser=$xp" || echo "xparser=（未找到，AST 走 xnast）"
  echo "runtime=${RUNTIME}（${#RUNTIME_SRCS[@]} 个 C 源）"
  echo "frontend=$XNULL_FRONTEND"
}

[ $# -gt 0 ] || usage
sub=$1; shift
case "$sub" in
  build) cmd_build "$@" ;;
  run) cmd_run "$@" ;;
  verify) [ $# -ge 1 ] || usage; cmd_verify "$1" ;;
  examples) cmd_examples ;;
  bootstrap-xnullc) cmd_bootstrap "$@" ;;
  bootstrap-xparser) cmd_bootstrap_xparser "$@" ;;
  bootstrap-model) cmd_bootstrap_model "$@" ;;
  bootstrap-reactor) cmd_bootstrap_reactor "$@" ;;
  bootstrap-tools) cmd_bootstrap_tools "$@" ;;
  build-project) cmd_build_project "$@" ;;
  tree) cmd_tree "$@" ;;
  install) cmd_install "$@" ;;
  xmeta) cmd_xmeta "$@" ;;
  repro) cmd_repro "$@" ;;
  why) cmd_why "$@" ;;
  run-project) cmd_run_project "$@" ;;
  validate) cmd_validate "$@" ;;
  ast-check) cmd_ast_check "$@" ;;
  info) cmd_info ;;
  version) cmd_version ;;
  -h|--help|help) usage ;;
  *) die "未知子命令：$sub" ;;
esac
