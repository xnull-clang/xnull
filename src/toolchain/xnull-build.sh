#!/usr/bin/env bash
# 不依赖 Go CLI 的构建/运行管线原型。
#
# 管线：
#   <entry.x> --xnast--ast--> AST（Go oracle，旧对照前允许）
#   <entry.x> --xnull--emit-ast-bundle--> bundle（仅多文件入口需要）
#   xfb-projection.py --> --project 注册表
#   AST+bundle+project --native xnullc--> 生成 C
#   cc + src/runtime 14 个 C 源 + 空资源表 --> 可执行文件
#
# 用法：
#   src/toolchain/xnull-build.sh build <entry.x> [-o out] [--emit-c-only]
#   src/toolchain/xnull-build.sh run <entry.x> [-- 程序参数...]
#   src/toolchain/xnull-build.sh verify <entry.x>     # C 与 Go --emit-c 逐字节对比 + 双路径运行一致
#   src/toolchain/xnull-build.sh examples             # 9 个示例全量验收
#   src/toolchain/xnull-build.sh bootstrap-xnullc [-o out]   # 用解释器自举原生 xnullc（xn-s1）
#   src/toolchain/xnull-build.sh bootstrap-xparser [-o out]  # 用 native xnullc 自举原生 xparser
#   src/toolchain/xnull-build.sh ast-check [入口...]        # 原生 xparser AST vs xnast AST（全量深度）
#   src/toolchain/xnull-build.sh bootstrap-model [-o dir]   # 自举 xpd / xmanifest（当前）
#   src/toolchain/xnull-build.sh validate <project>         # 清单校验：模块/依赖边/拓扑（不编译）
#   src/toolchain/xnull-build.sh build-project <dir> [-o d] # 聚合构建（library→对象，app→链接）
#   src/toolchain/xnull-build.sh lock <dir> [--update|--check] # 生成/校验 xnull.lock
#   src/toolchain/xnull-build.sh run-project <dir> [-- args] # 聚合构建并运行
#   src/toolchain/xnull-build.sh tree <dir>                 # 依赖树（对齐 Go xnull tree）
#   src/toolchain/xnull-build.sh why <dir> <coord>          # 依赖理由（对齐 Go xnull why）
#   src/toolchain/xnull-build.sh install <dir> [--repo d]  # 聚合构建 + 安装到本地仓库
#   src/toolchain/xnull-build.sh repro <dir>               # 连建两次，比较 C/对象/app 的 SHA-256
#   src/toolchain/xnull-build.sh xmeta <dir>               # 生成模块 .xmeta（字段对齐 Go）
#   src/toolchain/xnull-build.sh info
#
# 环境变量：
#   XNULLC_BIN       原生 xnullc（默认探测 /tmp/xn-s4 → /tmp/xn-s1）
#   XNULL_GO_BIN     Go oracle `xnull`（仅 AST/bundle/对比用；缺省按需 go build）
#   XNAST_BIN        Go oracle `xnast`（缺省按需 go build）
#   XNULL_WORK    工作目录（默认 mktemp -d）
#   XNULL_MODEL_DIR  自举 xpd/xmanifest/reactor 目录（默认 /tmp；测试可隔离）
#   XNULL_TOOL_DIR   自举 resman/artifact/config/deps/xmeta 目录（默认 /tmp）
#   XNULL_FRONTEND   传给 oracle 的前端（默认 go，避免 auto 前端拖慢）
#
# 退出码：0 成功；1 构建/运行/比对失败；2 参数或环境错误。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
RUNTIME="$ROOT/src/runtime"
CACHE_DIR=${XNULL_CACHE_DIR:-$ROOT/.cache/xnull}
mkdir -p "$CACHE_DIR" 2>/dev/null || true
cache_hash() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$@" | awk '{print $1}' | shasum -a 256 | awk '{print $1}'
  else
    sha256sum "$@" | awk '{print $1}' | sha256sum | awk '{print $1}'
  fi
}
REV=$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo work)
# Go oracle 已删除：没有 impl/ 或没有 go 时自动使用 bootstrap/bin 的原生工具。
if [ -x "$ROOT/src/bootstrap/bin/xn-s4" ] && [ -x "$ROOT/src/bootstrap/bin/xparser" ]; then
  if [ ! -d "$ROOT/impl" ] || ! command -v go >/dev/null 2>&1; then
    export XNULL_BOOTSTRAP=1
    export XNULLC_BIN=${XNULLC_BIN:-$ROOT/src/bootstrap/bin/xn-s4}
    export XPARSER_BIN=${XPARSER_BIN:-$ROOT/src/bootstrap/bin/xparser}
  fi
fi
export XNULL_FRONTEND=${XNULL_FRONTEND:-go}

# 与 Go codegen 保持一致的运行时 C 源顺序（impl/internal/codegen/build.go:36）。
RUNTIME_SRCS=(
  rt.c rt_gc.c rt_policy.c rt_weak.c xrt_abi.c
  rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c rt_std_net.c
  rt_task.c rt_sync.c rt_std_res.c rt_std_res_empty.c rt_std_ext.c
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
  if [ -x "$p" ]; then echo "$p"; return; fi
  # 没有 Go oracle 时，把原生 xparser 的 --file 接口适配成 reactor 需要的
  # `xnast --ast <entry>` 接口；xparser 输出已经是 xnast v1 文本。
  local xp
  if xp=$(xparser_bin); then
    p="/tmp/xnast-native-$REV"
    cat > "$p" <<EOF
#!/bin/sh
if [ "\${1:-}" = "--ast" ]; then
  shift
  exec "$xp" --file "\$@"
fi
exec "$xp" "\$@"
EOF
    chmod +x "$p"
    echo "$p"
    return
  fi
  [ -x "$p" ] || ( cd "$ROOT/impl" && go build -o "$p" ./cmd/xnast ) || fail "构建 oracle xnast 失败" >&2
  echo "$p"
}

# 原生 xnullc：显式指定优先，其次 /tmp/xn-s4、/tmp/xn-s1。
xnullc_bin() {
  local c=""
  for c in "${XNULLC_BIN:-}" "$ROOT/src/bootstrap/bin/xn-s4" /tmp/xn-s4 /tmp/xn-s1; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  cat >&2 <<'EOF'
xnull-build: 找不到原生 xnullc。任选其一：
  1) 指定已有二进制：XNULLC_BIN=/path/to/xnullc src/toolchain/xnull-build.sh ...
  2) 自举一份：src/toolchain/xnull-build.sh bootstrap-xnullc -o /tmp/xn-s1
EOF
  return 1
}

# 原生 xparser（当前）：显式指定优先，其次 /tmp/xparser-native（bootstrap-xparser 产出）。
xparser_bin() {
  local c=""
  for c in "${XPARSER_BIN:-}" "$ROOT/src/bootstrap/bin/xparser" /tmp/xparser-native; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

# AST 来源：优先原生 xparser --file；失败（崩溃/空输出）回退 Go oracle（旧对照前允许）。
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
  if [ -n "${XNULL_WORK:-}" ]; then mkdir -p "$XNULL_WORK"; echo "$XNULL_WORK"; return; fi
  mktemp -d "${TMPDIR:-/tmp}/b4b01.XXXXXX"
}

has_split() {
  [ -f "${1%.x}/.xsplit.json" ] || [ -f "$(dirname "$1")/.xsplit.json" ]
}

# oracle 三件套：ast / bundle 文件数 / 投影
oracle_inputs() {
  local entry=$1 outdir=$2 projdir=${3:-}
  # XDK 完整源码层默认编译；XNULL_XDK_SOURCE=0 可显式回到冻结兼容面。
  # 入口 import xdk.* 时，把完整 errors/text/sys/net AST 一并打包，
  # 并用 bridges（sys_raw/net_raw）投影 FFI；verify-golden 的独立路径不受影响。
  if [ "${XNULL_XDK_SOURCE:-1}" = "1" ]; then
    local xdk_entry="$entry"
    [ -f "$xdk_entry" ] || xdk_entry="$ROOT/$entry"
    if grep -q '^import xdk\.' "$xdk_entry" 2>/dev/null; then
      mkdir -p "$outdir"
      local nf
      nf=$(python3 "$ROOT/src/toolchain/xdk-bundle.py" "$ROOT" "$xdk_entry" "$outdir") \
        || fail "XDK 源码 bundle 失败：$entry"
      python3 - "$outdir/bundle.json" "$entry" "$outdir/ast.txt" <<'PY' || fail "入口 AST 提取失败：$entry"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
want = sys.argv[2]
for f in d["files"]:
    if f["path"].endswith(want):
        open(sys.argv[3], "w", encoding="utf-8").write(f["ast"])
        sys.exit(0)
sys.exit(1)
PY
      python3 "$ROOT/src/toolchain/xfb-projection.py" "$ROOT/src/ffi" > "$outdir/project.txt" 2>/dev/null || : > "$outdir/project.txt"
      echo "$nf"
      return 0
    fi
  fi

  # 无 Go 引导模式——AST 用 bootstrap/bin/xparser。
  # 普通包 import 走统一包解析器；XDK 源码模式在上面单独处理。
  if [ "${XNULL_BOOTSTRAP:-}" = "1" ]; then
    mkdir -p "$outdir"
    local xp=${XPARSER_BIN:-$ROOT/src/bootstrap/bin/xparser}
    [ -x "$xp" ] || fail "引导模式缺少 xparser：$xp"
    local ep="$ROOT/$entry"
    [ -f "$ep" ] || ep="$entry"
    local simple_ast=1
    if grep -qE '^[[:space:]]*import[[:space:]]' "$ep" 2>/dev/null || has_split "$entry"; then
      simple_ast=0
    fi
    local ast_key="" ast_cache=""
    if [ "$simple_ast" = 1 ]; then
      ast_key=$(cache_hash "$ep" "$xp")
      ast_cache="$CACHE_DIR/ast-$ast_key.txt"
    fi
    if [ -n "$ast_cache" ] && [ -f "$ast_cache" ]; then
      cp "$ast_cache" "$outdir/ast.txt"
    else
      ( cd "$ROOT" && "$xp" --file "$entry" ) > "$outdir/ast.txt" 2>"$outdir/ast.err" \
        || { sed -n 1,3p "$outdir/ast.err" >&2; fail "xparser 生成 AST 失败：$entry"; }
      [ -n "$ast_cache" ] && cp "$outdir/ast.txt" "$ast_cache"
    fi
    local pdir=${projdir:-$(dirname "$ROOT/$entry")}
    if [ -d "$pdir" ]; then
      python3 "$ROOT/src/toolchain/xfb-projection.py" "$pdir" > "$outdir/project.txt" \
        || fail "FFI 投影失败：$entry"
    else
      : > "$outdir/project.txt"
    fi
    if [ -d "$ROOT/src/ffi" ] && [ "$(cd "$pdir" && pwd)" != "$(cd "$ROOT/src/ffi" && pwd)" ]; then
      python3 "$ROOT/src/toolchain/xfb-projection.py" "$ROOT/src/ffi" >> "$outdir/project.txt" 2>/dev/null || true
    fi
    if has_split "$entry" || { grep -qE '^[[:space:]]*import[[:space:]]' "$entry" 2>/dev/null \
        && ! grep -qE '^[[:space:]]*import[[:space:]]+xdk\.' "$entry" 2>/dev/null; }; then
      python3 "$ROOT/src/toolchain/native-bundle.py" "$ROOT" "$xp" "$entry" > "$outdir/bundle.json" \
        || fail "包 bundle 生成失败：$entry"
      if has_split "$entry"; then
        python3 - "$outdir/bundle.json" "$outdir/ast.txt" <<'PY' || fail "受管入口 AST 提取失败：$entry"
import json, sys
b = json.load(open(sys.argv[1], encoding="utf-8"))
open(sys.argv[2], "w", encoding="utf-8").write(b["files"][-1]["ast"])
PY
      fi
      python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1],encoding="utf-8")).get("files",[])))' \
        "$outdir/bundle.json"
      return 0
    fi
    echo 1
    return 0
  fi
  local go; go=$(go_bin) || exit 1
  ast_dump "$entry" "$outdir/ast.txt" || exit 1
  ( cd "$ROOT" && "$go" --emit-ast-bundle "$entry" ) > "$outdir/bundle.json" || fail "bundle 生成失败：$entry"
  # 投影目录选择：
  #   - 显式传入优先（自举 xnullc 用 $ROOT/src/bindings）；
  #   - 入口 import xdk.*：用 repo 的 canonical bindings/（否则 xn_ffi_* 未定义）；
  #   - 其余：按入口目录投影，与 Go `--emit-c` 的差分口径一致（不多发未用 FFI 包装）。
  if [ -z "$projdir" ]; then
    if grep -q '^import xdk\.' "$ROOT/$entry" 2>/dev/null || grep -q '^import xdk\.' "$entry" 2>/dev/null; then
      projdir="$ROOT/src/bindings"
    else
      projdir=$(dirname "$ROOT/$entry")
    fi
  fi
  python3 "$ROOT/src/toolchain/xfb-projection.py" "$projdir" > "$outdir/project.txt" \
    || fail "FFI 投影失败：$entry"
  if [ -d "$ROOT/src/ffi" ] && [ "$(cd "$projdir" && pwd)" != "$(cd "$ROOT/src/ffi" && pwd)" ]; then
    python3 "$ROOT/src/toolchain/xfb-projection.py" "$ROOT/src/ffi" >> "$outdir/project.txt" 2>/dev/null || true
  fi
  python3 - "$outdir/bundle.json" <<'PY' || fail "bundle 解析失败：$entry"
import json, sys
b = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if len(b.get("files", [])) >= 1 else 1)
PY
  python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1],encoding="utf-8")).get("files",[])))' "$outdir/bundle.json"
}

# mini 引擎能力探测：只有明确支持时才让 auto 接管。
mini_supports() {
  local mini="$ROOT/src/mini/mini"
  [ -x "$mini" ] || return 1
  ( cd "$ROOT" && "$mini" --supports "$1" >/dev/null 2>&1 )
}

# 生成 C：原生 xnullc + oracle AST/bundle/project；或 mini 引擎。
emit_c() {
  local entry=$1 outdir=$2 out=$3
  mkdir -p "$outdir"
  local engine=${XNULL_ENGINE:-legacy}
  local mini="$ROOT/src/mini/mini"
  local use_mini=0
  if [ "$engine" = "mini" ]; then
    use_mini=1
  elif [ "$engine" = "auto" ] && mini_supports "$entry"; then
    use_mini=1
  fi
  if [ "$use_mini" = 1 ]; then
    [ -x "$mini" ] || fail "mini 引擎不存在：$mini"
    local mpdir
    mpdir=$(dirname "$ROOT/$entry")
    python3 "$ROOT/src/toolchain/xfb-projection.py" "$mpdir" > "$outdir/project.txt" 2>/dev/null || true
    ( cd "$ROOT" && "$mini" --emit-c "$entry" --xdk-root "$ROOT/src/xdk" --project-file "$outdir/project.txt" ) > "$out" 2> "$outdir/mini.err"
    local mrc=$?
    if [ $mrc -eq 0 ]; then
      echo 1
      return 0
    fi
    if [ "$engine" = "auto" ] && [ $mrc -eq 3 ]; then
      : # 明确不支持，回退旧引擎
    else
      sed -n 1,8p "$outdir/mini.err" >&2
      # mini 的 CLI 诊断部分走 stdout；失败时保留它，避免 JSON 只看到通用错误。
      sed -n 1,8p "$out" >&2
      fail "mini 生成 C 失败：${entry}（exit ${mrc}）"
    fi
  fi
  local nf; nf=$(oracle_inputs "$entry" "$outdir") || exit 1
  local xc; xc=$(xnullc_bin) || exit 1
  local ckey cfile
  ckey=$(cache_hash "$outdir/ast.txt" "$outdir/project.txt" "$xc" "$ROOT/src/toolchain/xdk-ffi-fix.py")
  [ -f "$outdir/bundle.json" ] && ckey=$(cache_hash "$outdir/ast.txt" "$outdir/bundle.json" "$outdir/project.txt" "$xc" "$ROOT/src/toolchain/xdk-ffi-fix.py")
  cfile="$CACHE_DIR/c-$ckey.c"
  if [ -f "$cfile" ]; then
    cp "$cfile" "$out"
    echo "$nf"
    return 0
  fi
  local args=("$entry" --ast-file "$outdir/ast.txt" --project "$(cat "$outdir/project.txt")")
  if [ "$nf" -gt 1 ] || has_split "$entry"; then
    args+=(--bundle-file "$outdir/bundle.json")
  fi
  ( cd "$ROOT" && "$xc" "${args[@]}" ) > "$out" 2> "$outdir/xnullc.err"
  local rc=$?
  if [ $rc -ne 0 ]; then
    sed -n 1,5p "$outdir/xnullc.err" >&2
    fail "原生 xnullc 生成 C 失败：${entry}（exit ${rc}）"
  fi
  if [ "${XNULL_XDK_SOURCE:-1}" = "1" ]; then
    python3 "$ROOT/src/toolchain/xdk-ffi-fix.py" "$outdir/project.txt" "$out" \
      >> "$outdir/ffi-fix.log" 2>&1 || fail "FFI 包装器修复失败：$entry"
  fi
  cp "$out" "$cfile" 2>/dev/null || true
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
  if ! cc -std=c11 -O2 -pthread -I "$RUNTIME" -o "$out" "$cfile" "${srcs[@]}" "$res" -lz 2> "${out}.cc.log"; then
    sed -n 1,10p "${out}.cc.log" >&2
    fail "cc 链接失败：$cfile"
  fi
}
# 注：rt_std_ext.c 需要 -lz（gzip/zip 后端）；zlib 为平台标准库。

json_has_flag() {
  local flag=$1; shift
  local a
  for a in "$@"; do [ "$a" = "$flag" ] && return 0; done
  return 1
}

json_emit() {
  local ok=$1 file=$2 output=$3 code=$4 diag=$5 log=$6
  python3 "$ROOT/src/toolchain/json_result.py" "$ok" "$file" "$output" "$code" "$diag" "$log"
}

cmd_build_json() {
  local entry="" out="" a
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) shift ;;
      -o|--output) out=${2:-}; shift 2 ;;
      -*) echo "xnull: 未知参数：$1" >&2; return 2 ;;
      *) entry=$1; shift ;;
    esac
  done
  [ -n "$entry" ] || { echo "xnull: build 缺少入口" >&2; return 2; }
  if [ -d "$entry" ] && [ -f "$entry/xnull.project" ]; then
    if [ -n "$out" ]; then cmd_build_project_json "$entry" -o "$out"; else cmd_build_project_json "$entry"; fi
    return $?
  fi
  local so se
  so=$(mktemp); se=$(mktemp)
  local rc=0 path=""
  if [ -n "$out" ]; then
    ( cmd_build "$entry" -o "$out" ) >"$so" 2>"$se" || rc=$?
  else
    ( cmd_build "$entry" ) >"$so" 2>"$se" || rc=$?
  fi
  if [ "$rc" = 0 ]; then
    path=$(tail -n 1 "$so")
  fi
  json_emit "$rc" "$entry" "$path" "$rc" "$se" "$se"
  rm -f "$so" "$se"
  return "$rc"
}

cmd_run_json() {
  local entry="" a extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) shift ;;
      --) shift; extra=("$@"); break ;;
      -*) echo "xnull: 未知参数：$1" >&2; return 2 ;;
      *) entry=$1; shift ;;
    esac
  done
  [ -n "$entry" ] || { echo "xnull: run 缺少入口" >&2; return 2; }
  if [ -d "$entry" ] && [ -f "$entry/xnull.project" ]; then
    if [ ${#extra[@]} -gt 0 ]; then cmd_run_project_json "$entry" -- "${extra[@]}"; else cmd_run_project_json "$entry"; fi
    return $?
  fi
  local bo be po pe bin rc=0 arc=0
  bo=$(mktemp); be=$(mktemp); po=$(mktemp); pe=$(mktemp)
  ( cmd_build "$entry" ) >"$bo" 2>"$be" || rc=$?
  if [ "$rc" = 0 ]; then
    bin=$(tail -n 1 "$bo")
    if [ -n "$bin" ] && [ -x "$bin" ]; then
      if [ ${#extra[@]} -gt 0 ]; then
        "$bin" "${extra[@]}" >"$po" 2>"$pe" || arc=$?
      else
        "$bin" >"$po" 2>"$pe" || arc=$?
      fi
    else
      echo "xnull: 构建未产出可执行文件：$entry" >"$be"
      arc=1
    fi
  else
    arc=$rc
  fi
  cat "$be" "$pe" > "$be.log" 2>/dev/null || true
  json_emit "$arc" "$entry" "$(cat "$po")" "$arc" "$be" "$be.log"
  rm -f "$bo" "$be" "$po" "$pe" "$be.log"
  return "$arc"
}

cmd_build_project_json() {
  local proj="" out="" a
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) shift ;;
      -o|--output) out=${2:-}; shift 2 ;;
      -*) echo "xnull: 未知参数：$1" >&2; return 2 ;;
      *) proj=$1; shift ;;
    esac
  done
  [ -n "$proj" ] || { echo "xnull: build-project 缺少工程目录" >&2; return 2; }
  [ -n "$out" ] || out=${XNULL_OUT:-/tmp/xnull-proj-$(basename "$proj")}
  local se rc=0
  se=$(mktemp)
  if [ -n "${out:-}" ]; then
    ( cmd_build_project "$proj" -o "$out" ) > /dev/null 2>"$se" || rc=$?
  else
    ( cmd_build_project "$proj" ) > /dev/null 2>"$se" || rc=$?
  fi
  local bin=""
  [ -x "$out/app" ] && bin="$out/app"
  json_emit "$rc" "$proj" "$bin" "$rc" "$se" "$se"
  rm -f "$se"
  return "$rc"
}

cmd_run_project_json() {
  local proj="" a extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) shift ;;
      --) shift; extra=("$@"); break ;;
      -*) echo "xnull: 未知参数：$1" >&2; return 2 ;;
      *) proj=$1; shift ;;
    esac
  done
  [ -n "$proj" ] || { echo "xnull: run-project 缺少工程目录" >&2; return 2; }
  local so se rc=0
  so=$(mktemp); se=$(mktemp)
  if [ ${#extra[@]} -gt 0 ]; then
    ( cmd_run_project "$proj" -- "${extra[@]}" ) >"$so" 2>"$se" || rc=$?
  else
    ( cmd_run_project "$proj" ) >"$so" 2>"$se" || rc=$?
  fi
  json_emit "$rc" "$proj" "$(cat "$so")" "$rc" "$se" "$se"
  rm -f "$so" "$se"
  return "$rc"
}

cmd_build() {
  local entry="" out="" emit_only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -o|--output) out=${2:-}; shift 2 ;;
      --resources) XNULL_RESOURCES=${2:-}; shift 2 ;;
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
  if [ -n "${XNULL_RESOURCES:-}" ] && [ -d "${XNULL_RESOURCES}" ]; then
    python3 "$ROOT/src/toolchain/gen_res_table.py" "$XNULL_RESOURCES" "$base.res.c" \
      || fail "资源表生成失败：$XNULL_RESOURCES"
  else
    write_empty_res "$base.res.c"
  fi
  cc_link "$base.c" "$base" "$base.res.c" || exit 1
  echo "$base"
}

cmd_check_json() {
  local entry="" a
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) shift ;;
      -*) echo "xnull: 未知参数：$1" >&2; return 2 ;;
      *) entry=$1; shift ;;
    esac
  done
  [ -n "$entry" ] || { echo "xnull: check 缺少入口" >&2; return 2; }
  local so se rc=0
  so=$(mktemp); se=$(mktemp)
  ( cmd_check "$entry" ) >"$so" 2>"$se" || rc=$?
  json_emit "$rc" "$entry" "" "$rc" "$se" "$se"
  rm -f "$so" "$se"
  return "$rc"
}

cmd_check() {
  local entry=${1:-} json=0
  [ -n "$entry" ] || usage
  [ "${2:-}" = "--json" ] && json=1
  [ -f "$ROOT/$entry" ] || [ -f "$entry" ] || die "入口不存在：$entry"
  [ -f "$entry" ] && entry=${entry#"$ROOT/"}
  local engine=${XNULL_ENGINE:-legacy}
  if [ "$engine" = "mini" ] || [ "$engine" = "auto" ]; then
    local out rc
    out=$("$ROOT/src/mini/mini" --sema "$entry" --xdk-root "$ROOT/src/xdk" 2>&1)
    rc=$?
    if [ "$json" = 1 ]; then
      if [ $rc -eq 0 ]; then
        printf '{"ok":true}\n'
      else
        local msg=${out//\"/\\\"}
        printf '{"ok":false,"diagnostic":"%s"}\n' "$msg"
      fi
      return $rc
    fi
    if [ $rc -eq 0 ]; then
      printf '%s\n' "$out"
      return 0
    fi
    printf '%s\n' "$out" >&2
    return 1
  fi
  local w; w=$(workdir) || exit 1
  emit_c "$entry" "$w" "$w/check.c" > /dev/null || exit 1
  if [ "$json" = 1 ]; then
    printf '{"ok":true}\n'
  else
    echo "check ok"
  fi
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

# 示例全量验收（src/examples/*.x，不含 multi/ 目录）
cmd_examples() {
  local pass=0 failn=0 f name
  # 无 Go 模式——用 bootstrap 工具构建并运行，C 与冻结 golden 哈希比对
  if [ "${XNULL_BOOTSTRAP:-}" = "1" ]; then
    local golden="" w
    w=$(workdir) || exit 1
    for f in "$ROOT"/src/examples/*.x; do
      [ -f "$f" ] || continue
      name=$(basename "$f")
      rel=${f#"$ROOT/"}
      local bin="$w/$name.bin"
      if ! cmd_build "$rel" -o "$bin" > /dev/null 2>&1; then echo "FAIL build ${name}"; failn=$((failn+1)); continue; fi
      local out rc
      out=$("$bin" 2>&1); rc=$?
      local want="" got
      [ -n "$golden" ] && [ -f "$golden" ] && want=$(awk -F'\t' -v n="$name" '$1==n{print $2}' "$golden")
      got=$(shasum -a 256 "$bin.c" | cut -d' ' -f1)
      if [ $rc -eq 0 ] && [ -n "$want" ] && [ "$got" = "$want" ]; then
        echo "PASS ${name}（C 与 golden 一致）"; pass=$((pass+1))
      elif [ $rc -eq 0 ] && [ -z "$want" ]; then
        echo "PASS ${name}（运行 ok；无 golden 比对）"; pass=$((pass+1))
      else
        echo "FAIL ${name}（rc=${rc}，C=${got}）"; failn=$((failn+1))
      fi
    done
    echo " bootstrap examples：PASS=$pass FAIL=$failn"
    [ "$failn" -eq 0 ]
    return
  fi
  for f in "$ROOT"/src/examples/*.x; do
    [ -f "$f" ] || continue
    name=${f#"$ROOT/"}
    if cmd_verify "$name"; then pass=$((pass+1)); else echo "FAIL $name"; failn=$((failn+1)); fi
  done
  echo "当前 examples：PASS=$pass FAIL=$failn"
  [ "$failn" -eq 0 ]
}

# 自举原生 xnullc：解释执行 xnullc.x 生成 C，再 cc 成二进制（xn-s1）
cmd_bootstrap() {
  local out=/tmp/xn-s1
  if [ "${1:-}" = "-o" ]; then out=${2:-}; [ -n "$out" ] || die "-o 缺少路径"; fi
  local w; w=$(workdir) || exit 1
  local entry=src/compiler/codegen/Codegen.x
  # 自举 xnullc 用 repo 的 canonical bindings 目录投影：整仓投影会撞上 src/xnfmt、evidence 下的
  # 同名 .xfb，导致 xn_ffi_<name> 重复定义。
  local nf; nf=$(oracle_inputs "$entry" "$w" "$ROOT/src/bindings") || exit 1
  local go; go=$(go_bin) || exit 1
  local compiler; compiler=$(python3 "$ROOT/src/toolchain/materialize_legacy.py" "$ROOT" "$ROOT/$entry") || exit 1
  local args=("$ROOT/$entry" --ast-file "$w/ast.txt" --project "$(cat "$w/project.txt")")
  { [ "$nf" -gt 1 ] || has_split "$entry"; } && args+=(--bundle-file "$w/bundle.json")
  ( cd "$ROOT" && "$go" run --interp "$compiler" -- "${args[@]}" ) > "$w/xnullc.c" 2> "$w/self.err" \
    || { sed -n 1,5p "$w/self.err" >&2; fail "自举生成 C 失败"; }
  write_empty_res "$w/res.c"
  cc_link "$w/xnullc.c" "$out" "$w/res.c" || exit 1
  echo "$out"
}

# 用 Go interp 跑 xnullc.x 生成 C（native xnullc 对部分模式不稳定时的可靠回退）。
# 用法：emit_c_interp <entry.x> <out.c> [投影目录]
emit_c_interp() {
  local entry=$1 out=$2 projdir=${3:-$ROOT/src/bindings}
  local w; w=$(workdir) || exit 1
  local nf; nf=$(oracle_inputs "$entry" "$w" "$projdir") || exit 1
  local go; go=$(go_bin) || exit 1
  local compiler; compiler=$(python3 "$ROOT/src/toolchain/materialize_legacy.py" "$ROOT" "$ROOT/src/compiler/codegen/Codegen.x") || exit 1
  local args=("$entry" --ast-file "$w/ast.txt" --project "$(cat "$w/project.txt")")
  if [ "$nf" -gt 1 ] || has_split "$entry"; then args+=(--bundle-file "$w/bundle.json"); fi
  ( cd "$ROOT" && "$go" run --interp "$compiler" -- "${args[@]}" ) > "$out" 2> "$w/interp.err" \
    || { sed -n 1,5p "$w/interp.err" >&2; fail "interp 生成 C 失败：$entry"; }
  write_empty_res "$w/res.c"
  echo "$w/res.c"
}

# 自举 resman/config/artifact（当前）：原生 xnullc 编译；deps 走冻结兼容面。
cmd_bootstrap_tools() {
  local dir=/tmp
  if [ "${1:-}" = "-o" ]; then dir=${2:-}; [ -n "$dir" ] || die "-o 缺少目录"; mkdir -p "$dir"; fi
  local t entry res w
  for t in resman artifact config deps xmeta; do
    case "$t" in
      resman) entry="src/build/resource/Resource.x" ;;
      artifact) entry="src/build/artifact/Artifact.x" ;;
      config) entry="src/build/config/Config.x" ;;
      deps) entry="src/build/deps/Deps.x" ;;
      xmeta) entry="src/build/meta/Meta.x" ;;
    esac
    [ -f "$ROOT/$entry" ] || continue
    w=$(workdir) || exit 1
    # deps 的类方法 walk 与完整 Sys.walk 在原生 CGen 下同名；该工具只需读文件，
    # 用冻结兼容面（base Sys）编译，避免引入完整 Sys 的 walk。
    if [ "$t" = "deps" ]; then
      XNULL_XDK_SOURCE=0 emit_c "$entry" "$w/$t" "$dir/$t.c" > /dev/null || exit 1
    else
      XNULL_XDK_SOURCE=1 emit_c "$entry" "$w/$t" "$dir/$t.c" > /dev/null || exit 1
    fi
    write_empty_res "$dir/$t.res.c"
    cc_link "$dir/$t.c" "$dir/$t" "$dir/$t.res.c" || exit 1
    echo "$dir/$t"
  done
}

# 自举 reactor（当前）：聚合构建驱动
cmd_bootstrap_reactor() {
  local dir=/tmp
  if [ "${1:-}" = "-o" ]; then dir=${2:-}; [ -n "$dir" ] || die "-o 缺少目录"; mkdir -p "$dir"; fi
  XNULL_XDK_SOURCE=1 emit_c src/build/reactor/Reactor.x "$dir/.reactor" "$dir/.reactor/reactor.c" > /dev/null || exit 1
  write_empty_res "$dir/.reactor/res.c"
  cc_link "$dir/.reactor/reactor.c" "$dir/reactor" "$dir/.reactor/res.c" || exit 1
  echo "$dir/reactor"
}

# 准备清单 TSV（root.tsv + m/*.tsv），失败返回 1
prepare_model() {
  local proj=$1 w=$2
  local mdir=${XNULL_MODEL_DIR:-/tmp}
  local xpd=${XPD_BIN:-$mdir/xpd}
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
  local mdir=${XNULL_MODEL_DIR:-/tmp}
  local xpd=${XPD_BIN:-$mdir/xpd}
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

# 元数据输入（当前）：按 Go projectManifest.xmeta 的口径计算摘要
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

# 模块元数据（当前）：xmeta <project>
cmd_xmeta() {
  local proj=${1:-}; [ -n "$proj" ] || usage
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  local mdir=${XNULL_MODEL_DIR:-/tmp} tdir=${XNULL_TOOL_DIR:-/tmp}
  local xpd=${XPD_BIN:-$mdir/xpd} xm=${XMETA_BIN:-$tdir/xmeta}
  if [ ! -x "$xpd" ]; then
    cmd_bootstrap_model -o "$mdir" > /dev/null || exit 1
    [ -x "$xpd" ] || xpd="$mdir/xpd"
  fi
  if [ ! -x "$xm" ]; then
    cmd_bootstrap_tools -o "$tdir" > /dev/null || exit 1
    [ -x "$xm" ] || xm="$tdir/xmeta"
  fi
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

# 可复现性（当前）：连续两次构建，比较 C/对象/app 的 SHA-256
cmd_repro() {
  local proj=${1:-}; [ -n "$proj" ] || usage
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  local base=${XNULL_OUT:-/tmp/xnull-repro-$(basename "$proj")}
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

# 依赖树（当前）：tree <project>
cmd_tree() {
  local proj=${1:-}; [ -n "$proj" ] || usage
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  [ -f "$proj/xnull.project" ] || fail "缺少 xnull.project：$proj"
  local mdir=${XNULL_MODEL_DIR:-/tmp} tdir=${XNULL_TOOL_DIR:-/tmp}
  local xpd=${XPD_BIN:-$mdir/xpd} deps=${DEPS_BIN:-$tdir/deps}
  if [ ! -x "$xpd" ]; then
    cmd_bootstrap_model -o "$mdir" > /dev/null || exit 1
    [ -x "$xpd" ] || xpd="$mdir/xpd"
  fi
  if [ ! -x "$deps" ]; then
    cmd_bootstrap_tools -o "$tdir" > /dev/null || exit 1
    [ -x "$deps" ] || deps="$tdir/deps"
  fi
  local w; w=$(workdir) || exit 1
  prepare_graph "$proj" "$w" || exit 1
  local files=("$w/target.tsv") f
  for f in "$w"/agg-*.tsv; do [ -e "$f" ] && files+=("$f"); done
  "$deps" tree "${files[@]}"
}

# 依赖理由（当前）：why <project> <groupId:artifactId>
cmd_why() {
  local proj=${1:-} coord=${2:-}
  [ -n "$proj" ] && [ -n "$coord" ] || usage
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  local mdir=${XNULL_MODEL_DIR:-/tmp} tdir=${XNULL_TOOL_DIR:-/tmp}
  local xpd=${XPD_BIN:-$mdir/xpd} deps=${DEPS_BIN:-$tdir/deps}
  if [ ! -x "$xpd" ]; then
    cmd_bootstrap_model -o "$mdir" > /dev/null || exit 1
    [ -x "$xpd" ] || xpd="$mdir/xpd"
  fi
  if [ ! -x "$deps" ]; then
    cmd_bootstrap_tools -o "$tdir" > /dev/null || exit 1
    [ -x "$deps" ] || deps="$tdir/deps"
  fi
  local w; w=$(workdir) || exit 1
  prepare_graph "$proj" "$w" || exit 1
  local files=("$w/target.tsv") f
  for f in "$w"/agg-*.tsv; do [ -e "$f" ] && files+=("$f"); done
  "$deps" why "$coord" "${files[@]}"
}

# 聚合工程构建（当前）：拓扑序 → 每模块 emit-c → library 出对象 → app 链接。
# 用法：build-project <dir> [-o 输出目录]
# 统一的 reactor 调用：确保工具就绪后执行 build-project
run_reactor() {
  local proj=$1 out=$2 repo=${3:-}
  local mdir=${XNULL_MODEL_DIR:-/tmp} tdir=${XNULL_TOOL_DIR:-/tmp}
  local xpd=${XPD_BIN:-$mdir/xpd} xmf=${XMANIFEST_BIN:-$mdir/xmanifest} rct=${REACTOR_BIN:-$mdir/reactor}
  if [ ! -x "$xpd" ] || [ ! -x "$xmf" ]; then
    cmd_bootstrap_model -o "$mdir" > /dev/null || exit 1
    [ -x "$xpd" ] || xpd="$mdir/xpd"
    [ -x "$xmf" ] || xmf="$mdir/xmanifest"
  fi
  if [ ! -x "$rct" ]; then
    cmd_bootstrap_reactor -o "$mdir" > /dev/null || exit 1
    [ -x "$rct" ] || rct="$mdir/reactor"
  fi
  local toolArgs=()
  local t
  for t in resman artifact config deps xmeta; do
    if [ ! -x "$tdir/$t" ]; then cmd_bootstrap_tools -o "$tdir" > /dev/null || exit 1; break; fi
  done
  [ -x "$tdir/resman" ] && toolArgs+=(--resman "$tdir/resman")
  [ -x "$tdir/artifact" ] && toolArgs+=(--artifact "$tdir/artifact")
  [ -x "$tdir/config" ] && toolArgs+=(--config "$tdir/config")
  local xc; xc=$(xnullc_bin) || exit 1
  local xnast; xnast=$(xnast_bin) || exit 1
  local extra=()
  [ -n "$repo" ] && extra+=(--repo "$repo")
  # bash 3.2 + set -u：空数组展开需显式保护
  "$rct" build-project "$proj" \
    --xpd "$xpd" --xmanifest "$xmf" --xnullc "$xc" --xnast "$xnast" \
    --runtime "$ROOT/src/runtime" --out "$out" \
    ${extra[@]+"${extra[@]}"} ${toolArgs[@]+"${toolArgs[@]}"}
}

project_needs_reactor() {
  local proj=$1
  local f="$proj/xnull.project"
  [ -f "$f" ] || return 1
  grep -Eq '^[[:space:]]*(modules|dependencies)[[:space:]]*\{' "$f" && return 0
  grep -Eq '^[[:space:]]*packaging[[:space:]]*=[[:space:]]*(pom|library|starter)' "$f" && return 0
  return 1
}

cmd_build_project() {
  local proj=${1:-} out=""
  [ -n "$proj" ] || usage
  shift || true
  if [ "${1:-}" = "-o" ]; then out=${2:-}; fi
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  [ -n "$out" ] || out=${XNULL_OUT:-/tmp/xnull-proj-$(basename "$proj")}
  local entry=""
  if [ -f "$proj/xnull.project" ]; then
    entry=$(sed -n 's/.*entryFile[[:space:]]*=[[:space:]]*//p' "$proj/xnull.project" | head -1 | tr -d '\r' | sed 's/}.*//; s/[[:space:]]*$//')
  fi
  if [ -n "$entry" ] && [ -f "$proj/$entry" ] && ! project_needs_reactor "$proj"; then
    mkdir -p "$out"
    if [ -d "$proj/src/main/resources" ]; then
      XNULL_RESOURCES="$proj/src/main/resources" cmd_build "$proj/$entry" -o "$out/app" >&2 || return 1
    else
      cmd_build "$proj/$entry" -o "$out/app" >&2 || return 1
    fi
    return 0
  fi
  run_reactor "$proj" "$out"
}

# 安装（当前）：build-project + 每模块落本地仓库
# 用法：install <project> [--repo <dir>]（默认 $XNULL_REPO 或 /tmp/xnull-install-repo）
cmd_install() {
  local proj=${1:-} repo=""
  [ -n "$proj" ] || usage
  shift || true
  if [ "${1:-}" = "--repo" ]; then repo=${2:-}; fi
  [ -n "$repo" ] || repo=${XNULL_REPO:-/tmp/xnull-install-repo}
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  local out=${XNULL_OUT:-/tmp/xnull-proj-$(basename "$proj")}
  run_reactor "$proj" "$out" || exit 1
  [ -f "$out/model.tsv" ] || fail "缺少模型：$out/model.tsv"
  python3 - "$proj" "$out" "$repo" "$HERE/pack_xlib.py" <<'PY'
import hashlib, os, shutil, subprocess, sys
proj, out, repo, packer = sys.argv[1:5]
modules, edges, order, root = [], [], [], {}
for line in open(os.path.join(out, "model.tsv"), encoding="utf-8"):
    ps = line.rstrip("\n").split("\t")
    if ps[0] == "project":
        root = {"coord": ps[1], "ver": ps[2], "pack": ps[3]}
    elif ps[0] == "module" and len(ps) >= 5:
        modules.append({"rel": ps[1], "coord": ps[2], "ver": ps[3], "pack": ps[4]})
    elif ps[0] == "edge" and len(ps) >= 4:
        edges.append({"from": ps[1], "coord": ps[2], "ver": ps[3]})
    elif ps[0] == "order":
        order = [x for x in ps[1].split(",") if x]
seq = order or [m["rel"] for m in modules]
byrel = {m["rel"]: m for m in modules}
def gav(coord, ver):
    g, a = coord.split(":", 1)
    return g.replace(".", "/"), a, ver
def sha(path):
    h = hashlib.sha256(); h.update(open(path, "rb").read()); return h.hexdigest()
lines = []
for rel in seq:
    m = byrel.get(rel)
    if not m or m["pack"] != "library":
        continue
    gp, art, ver = gav(m["coord"], m["ver"])
    d = os.path.join(repo, gp, art, ver)
    os.makedirs(d, exist_ok=True)
    moddir = os.path.join(proj, rel)
    deps = []
    for e in edges:
        if e["from"] == m["rel"]:
            deps.append("%s:%s" % (e["coord"], e["ver"]))
    xlib = os.path.join(d, "%s-%s.xlib" % (art, ver))
    subprocess.run([sys.executable, packer, xlib, moddir] + list(gav(m["coord"], m["ver"])) + [m["pack"]] + deps,
                   check=True, stdout=subprocess.DEVNULL)
    shutil.copy2(os.path.join(moddir, "xnull.project"), os.path.join(d, "xnull.project"))
    lines.append("module %s %s %s" % (rel, xlib, sha(xlib)))
    print("install\t" + xlib)
gp, art, ver = gav(root["coord"], root["ver"])
d = os.path.join(repo, gp, art, ver)
os.makedirs(d, exist_ok=True)
summary = os.path.join(d, "reactor-summary.txt")
with open(summary, "w", encoding="utf-8") as f:
    f.write("# reactor 聚合摘要（脚本生成，手改即作废）\n" + "\n".join(lines) + "\n")
shutil.copy2(os.path.join(proj, "xnull.project"), os.path.join(d, "xnull.project"))
print("install\t" + summary)
PY
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
  local out=${XNULL_OUT:-/tmp/xnull-proj-$(basename "$proj")}
  cmd_build_project "$proj" >&2 || exit 1
  [ -x "$out/app" ] || fail "没有 app 产物：$out/app"
  if [ ${#extra[@]} -gt 0 ]; then "$out/app" "${extra[@]}"; else "$out/app"; fi
}

# 锁文件：仅冻结当前可解析的 workspace 依赖；外部仓库依赖未接入时明确失败。
cmd_lock() {
  local proj="" update=0 check=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --update) update=1; shift ;;
      --check) check=1; shift ;;
      -*) die "lock: 未知参数：$1" ;;
      *) proj=$1; shift ;;
    esac
  done
  [ -n "$proj" ] || usage
  proj=$(cd "$proj" && pwd) || die "目录不存在"
  local root=$proj dir=$proj
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/xnull.project" ] && grep -Eq '^[[:space:]]*packaging[[:space:]]*=[[:space:]]*pom' "$dir/xnull.project"; then
      root=$dir
    fi
    [ "$dir" = "$ROOT" ] && break
    dir=$(dirname "$dir")
  done
  local mdir=${XNULL_MODEL_DIR:-/tmp}
  local xpd=${XPD_BIN:-$mdir/xpd} xmf=${XMANIFEST_BIN:-$mdir/xmanifest}
  if [ ! -x "$xpd" ] || [ ! -x "$xmf" ]; then
    cmd_bootstrap_model -o "$mdir" > /dev/null || exit 1
    [ -x "$xpd" ] || xpd="$mdir/xpd"
    [ -x "$xmf" ] || xmf="$mdir/xmanifest"
  fi
  local w; w=$(workdir) || exit 1
  prepare_model "$root" "$w" || exit 1
  local files=("$w/root.tsv") f rel
  while IFS= read -r rel; do
    f="$w/m/$(printf '%s' "$rel" | tr '/' '_').tsv"
    [ -f "$f" ] && files+=("$f")
  done < <(awk -F'\t' '$1=="module"{print $2}' "$w/root.tsv")
  "$xmf" "${files[@]}" > "$w/model.tsv" || die "lock: 工程模型解析失败"
  local lock="$root/xnull.lock" tmp="$w/xnull.lock"
  python3 - "$w/model.tsv" "$root" "$tmp" "$HERE/pack_xlib.py" <<'PYLOCK'
import hashlib
import os
import subprocess
import sys

model, root, out, packer = sys.argv[1:5]
mods = {}
edges = []
for line in open(model, encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if p and p[0] == "module" and len(p) >= 5:
        mods[p[2]] = {"rel": p[1], "ver": p[3], "pack": p[4]}
    elif p and p[0] == "edge" and len(p) >= 4:
        edges.append((p[1], p[2], p[3]))

external = sorted({(coord, ver) for _owner, coord, ver in edges if coord not in mods})
if external:
    for coord, ver in external:
        print("lock: error LOCK-002 外部依赖未接入仓库解析：%s %s" % (coord, ver), file=sys.stderr)
    sys.exit(2)

# 只锁定作为 workspace 依赖目标的库模块；聚合根和未成为依赖的模块不入锁。
targets = sorted({coord for _owner, coord, _ver in edges if coord in mods})
entries = []
for coord in targets:
    m = mods[coord]
    if m["pack"] != "library":
        print("lock: error LOCK-002 workspace 依赖不是可安装的 library：%s" % coord, file=sys.stderr)
        sys.exit(2)
    group, artifact = coord.split(":", 1)
    deps = []
    for owner, dep_coord, dep_ver in edges:
        if owner == m["rel"]:
            deps.append("%s:%s" % (dep_coord, dep_ver))
    xlib = os.path.join(os.path.dirname(os.path.abspath(out)), "lock-%s-%s.xlib" % (group.replace(".", "_"), artifact))
    subprocess.run(
        [sys.executable, packer, xlib, os.path.join(root, m["rel"]),
         group.replace(".", "/"), artifact, m["ver"], m["pack"]] + sorted(deps),
        check=True,
    )
    digest = hashlib.sha256(open(xlib, "rb").read()).hexdigest()
    os.unlink(xlib)
    entries.append((coord, m["ver"], digest))

lines = ["lock {", "  version = 1"]
for coord, ver, digest in entries:
    lines.append("")
    lines.append("  entry %s %s {" % (coord, ver))
    lines.append("    kind       = dependency")
    lines.append("    repository = workspace")
    lines.append("    sha256     = %s" % digest)
    lines.append("  }")
lines.append("}")
with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PYLOCK
  local rc=$?
  [ "$rc" = 0 ] || return "$rc"
  if [ "$check" = 1 ]; then
    if [ ! -f "$lock" ] || ! cmp -s "$lock" "$tmp"; then
      echo "lock: FAIL（需要更新：${lock}）" >&2
      return 1
    fi
    echo "lock: OK（${lock}）"
    return 0
  fi
  if [ -f "$lock" ] && ! cmp -s "$lock" "$tmp" && [ "$update" != 1 ]; then
    echo "lock: FAIL（锁文件不一致；使用 --update 更新）" >&2
    return 1
  fi
  cp "$tmp" "$lock"
  echo "lock: OK（${lock}）"
}

# 自举工程模型工具（当前）：xpd（清单→TSV）+ xmanifest（TSV→模块/依赖/拓扑）
cmd_bootstrap_model() {
  local dir=/tmp
  if [ "${1:-}" = "-o" ]; then dir=${2:-}; [ -n "$dir" ] || die "-o 缺少目录"; mkdir -p "$dir"; fi
  XNULL_XDK_SOURCE=0 emit_c src/build/project/Project.x "$dir/.xpd" "$dir/.xpd/xpd.c" > /dev/null || exit 1
  write_empty_res "$dir/.xpd/res.c"
  cc_link "$dir/.xpd/xpd.c" "$dir/xpd" "$dir/.xpd/res.c" || exit 1
  XNULL_XDK_SOURCE=0 emit_c src/build/manifest/Manifest.x "$dir/.xm" "$dir/.xm/manifest.c" > /dev/null || exit 1
  write_empty_res "$dir/.xm/res.c"
  cc_link "$dir/.xm/manifest.c" "$dir/xmanifest" "$dir/.xm/res.c" || exit 1
  echo "$dir/xpd"
  echo "$dir/xmanifest"
}

# 清单校验（当前）：只跑清单解析与工程模型，不编译、不碰 xnullc 之外的产物。
# 用法：validate <project 目录或 xnull.project 路径>
cmd_validate() {
  local proj=${1:-}
  [ -n "$proj" ] || usage
  if [ -f "$proj" ]; then proj=$(cd "$(dirname "$proj")" && pwd); else proj=$(cd "$proj" && pwd) || die "目录不存在"; fi
  [ -f "$proj/xnull.project" ] || fail "缺少 xnull.project：$proj"
  local mdir=${XNULL_MODEL_DIR:-/tmp}
  local xpd=${XPD_BIN:-$mdir/xpd}
  local xmf=${XMANIFEST_BIN:-$mdir/xmanifest}
  if [ ! -x "$xpd" ] || [ ! -x "$xmf" ]; then
    cmd_bootstrap_model -o "$mdir" > /dev/null || exit 1
    [ -x "$xpd" ] || xpd="$mdir/xpd"
    [ -x "$xmf" ] || xmf="$mdir/xmanifest"
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

# 自举原生 xparser（当前）：用当前 native xnullc 把 xparser.x 编成可执行文件
cmd_bootstrap_xparser() {
  local out=/tmp/xparser-native
  if [ "${1:-}" = "-o" ]; then out=${2:-}; [ -n "$out" ] || die "-o 缺少路径"; fi
  local w; w=$(workdir) || exit 1
  emit_c src/compiler/parser/Parser.x "$w" "$w/xparser.c" > /dev/null || exit 1
  write_empty_res "$w/res.c"
  cc_link "$w/xparser.c" "$out" "$w/res.c" || exit 1
  echo "$out"
}

# AST 一致性验收：原生 xparser --file 与 xnast --ast（全量深度）逐字节比较
cmd_ast_check() {
  local entries=("$@")
  if [ ${#entries[@]} -eq 0 ]; then
    for f in "$ROOT"/src/examples/*.x; do [ -f "$f" ] && entries+=("${f#"$ROOT/"}"); done
    entries+=(src/compiler/parser/Parser.x src/compiler/lexer/Lexer.x src/xnfmt/xnfmt.x)
  fi
  local xp; xp=$(xparser_bin) || { echo "xnull-build: 没有原生 xparser（先跑 bootstrap-xparser）" >&2; exit 2; }
  local xnast; xnast=$(xnast_bin) || exit 1
  local w; w=$(workdir) || exit 1
  local pass=0 failn=0 e
  for e in "${entries[@]}"; do
    local source=$e
    if has_split "$e"; then
      source=$(python3 "$ROOT/src/toolchain/materialize_legacy.py" "$ROOT" "$ROOT/$e") || exit 1
    fi
    ( cd "$ROOT" && "$xnast" --ast --dump-depth 100000 "$source" ) > "$w/go.ast" 2>/dev/null
    if has_split "$e"; then
      python3 "$ROOT/src/toolchain/native-bundle.py" "$ROOT" "$xp" "$e" > "$w/b.json" 2>"$w/xp.err"; local rc=$?
      python3 - "$w/b.json" "$w/xp.ast" <<'PY'
import json, sys
bundle = json.load(open(sys.argv[1], encoding="utf-8"))
open(sys.argv[2], "w", encoding="utf-8").write(bundle["files"][-1]["ast"])
PY
    else
      ( cd "$ROOT" && "$xp" --file "$e" ) > "$w/xp.ast" 2>"$w/xp.err"; local rc=$?
    fi
    if [ $rc -eq 0 ] && cmp -s "$w/go.ast" "$w/xp.ast"; then
      pass=$((pass+1)); echo "PASS $e"
    else
      failn=$((failn+1)); echo "DIFF ${e}（rc=${rc}，oracle=$(wc -c < "$w/go.ast") 字节，xparser=$(wc -c < "$w/xp.ast") 字节）"
    fi
  done
  echo "AST 一致性：PASS=$pass DIFF=$failn"
  [ "$failn" -eq 0 ]
}

# 版本信息（ 对拍用；格式仿 Go `-v`，无 specs 行）
cmd_version() {
  echo "xnull 0.1.0-dev"
  echo "commit: dev"
  echo "build date: unknown"
  echo "abi: v1"
}


# 版本信息（）：specs 行从仓库根规范文件名推导（与 Go version.SpecSet 一致）
cmd_version() {
  local specs
  specs=$(ls "$ROOT"/XNull解决方案-第[1-8]部分-*.md 2>/dev/null \
    | sed -E 's#.*第([1-8])部分.*-(v[0-9]+\.[0-9]+\.[0-9]+)\.md#S\1 \2#' \
    | grep -E '^S[1-8] ' | sort -V | paste -sd',' - | sed 's/,/, /g')
  echo "xnull 0.1.0-dev"
  echo "commit: dev"
  echo "build date: unknown"
  echo "specs: ${specs}"
  echo "abi: v1"
}

# 清理（）：与 Go `xnull clean` 同语义——删除 <dir>/target（--all 另清本地仓库）
cmd_clean() {
  local root="." all=0 a
  for a in "$@"; do
    if [ "$a" = "--all" ]; then all=1; elif [ "${a#-}" = "$a" ]; then root=$a; fi
  done
  local target="$root/target"
  [ "$root" = "." ] && target="target"
  rm -rf "$target" || { echo "xnull: 清理 $target 失败" >&2; return 1; }
  echo "已清理 $target"
  if [ "$all" = 1 ]; then
    local repo=${XNULL_REPO:-$HOME/.xnull/repository}
    [ -n "$repo" ] && rm -rf "$repo" && echo "已清理本地仓库缓存 $repo"
  fi
  return 0
}

# 环境自检（）：字段与 Go `xnull doctor` 一致（cc/runtime/repo/manifest/lock）
cmd_doctor() {
  local root="." a failed=0
  for a in "$@"; do [ "${a#-}" = "$a" ] && root=$a; done
  local lvl
  if ccbin=$(command -v cc 2>/dev/null); then echo "[ok] cc：$ccbin"
  else echo "[fail] cc：未找到 C 编译器（cc）"; failed=1; fi
  local rt="$ROOT/src/runtime"
  if [ -f "$rt/rt.h" ]; then echo "[ok] runtime：$rt"
  else echo "[fail] runtime：找不到运行时源码目录（rt.h）"; failed=1; fi
  local repo=${XNULL_REPO:-$HOME/.xnull/repository}
  if [ -z "$repo" ]; then echo "[warn] repo：未设置本地仓库"
  elif [ -d "$repo" ]; then echo "[ok] repo：$repo"
  else echo "[warn] repo：本地仓库尚未创建：$repo"; fi
  local dir=$root proj=""
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/xnull.project" ]; then proj=$dir; break; fi
    dir=$(dirname "$dir")
  done
  if [ -z "$proj" ]; then echo "[warn] manifest：当前目录不在工程内（无 xnull.project）"
  else echo "[ok] manifest：$proj"; fi
  local lockdir=$root
  [ -n "$proj" ] && lockdir=$proj
  if [ -f "$lockdir/xnull.lock" ]; then
    local n; n=$(grep -c '^  entry ' "$lockdir/xnull.lock" 2>/dev/null || echo 0)
    echo "[ok] lock：$lockdir/xnull.lock（$n 条）"
  else
    echo "[warn] lock：未找到 xnull.lock（首次构建后可生成）"
  fi
  [ "$failed" = 1 ] && return 1
  return 0
}

# 格式化（）：包装 src/xnfmt/xnfmt.x；--check 不改文件，只报告
cmd_fmt() {
  local check=0 files=() a
  for a in "$@"; do
    if [ "$a" = "--check" ]; then check=1; else files+=("$a"); fi
  done
  [ ${#files[@]} -gt 0 ] || { echo "xnull: fmt 需要文件" >&2; return 2; }
  local xnfmt=${XNFMT_BIN:-/tmp/xnfmt}
  if [ ! -x "$xnfmt" ]; then
    emit_c src/xnfmt/xnfmt.x "$(workdir)/xnfmt" >/dev/null 2>&1 || { echo "xnull: 构建 xnfmt 失败" >&2; return 1; }
    xnfmt="$XNULL_WORK/xnfmt"
    [ -x "$xnfmt" ] || xnfmt=/tmp/xnfmt
  fi
  local f rc=0 tmp
  for f in "${files[@]}"; do
    [ -f "$f" ] || { echo "xnull: fmt 需要可读文件：$f" >&2; return 2; }
    if [ "$check" = 1 ]; then
      tmp=$(mktemp "${TMPDIR:-/tmp}/fmt.XXXXXX")
      cp "$f" "$tmp"
      "$xnfmt" "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
      if ! cmp -s "$f" "$tmp"; then echo "xnull: 需要格式化 $f"; rc=1; fi
      rm -f "$tmp"
    else
      "$xnfmt" "$f" >/dev/null 2>&1 || rc=1
    fi
  done
  return $rc
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
  build)
    if json_has_flag --json "$@"; then cmd_build_json "$@"; else cmd_build "$@"; fi ;;
  run)
    if json_has_flag --json "$@"; then cmd_run_json "$@"; else cmd_run "$@"; fi ;;
  check)
    if json_has_flag --json "$@"; then cmd_check_json "$@"; else cmd_check "$@"; fi ;;
  verify) [ $# -ge 1 ] || usage; cmd_verify "$1" ;;
  examples) cmd_examples ;;
  bootstrap-xnullc) cmd_bootstrap "$@" ;;
  bootstrap-xparser) cmd_bootstrap_xparser "$@" ;;
  bootstrap-model) cmd_bootstrap_model "$@" ;;
  bootstrap-reactor) cmd_bootstrap_reactor "$@" ;;
  bootstrap-tools) cmd_bootstrap_tools "$@" ;;
  build-project)
    if json_has_flag --json "$@"; then cmd_build_project_json "$@"; else cmd_build_project "$@"; fi ;;
  lock) cmd_lock "$@" ;;
  tree) cmd_tree "$@" ;;
  install) cmd_install "$@" ;;
  xmeta) cmd_xmeta "$@" ;;
  repro) cmd_repro "$@" ;;
  why) cmd_why "$@" ;;
  run-project)
    if json_has_flag --json "$@"; then cmd_run_project_json "$@"; else cmd_run_project "$@"; fi ;;
  validate) cmd_validate "$@" ;;
  ast-check) cmd_ast_check "$@" ;;
  info) cmd_info ;;
  version) cmd_version ;;
  clean) cmd_clean "$@" ;;
  doctor) cmd_doctor "$@" ;;
  fmt) cmd_fmt "$@" ;;
  -h|--help|help) usage ;;
  *) die "未知子命令：$sub" ;;
esac
