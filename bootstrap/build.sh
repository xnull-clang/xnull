#!/usr/bin/env bash
# B4c-02a：无 Go 引导（只依赖 cc + impl/runtime 的 14 个 C 源）。
#
# 产物（bootstrap/bin/，不入库）：
#   xn-s4    —— 原生 xnullc（B3-10 固定点 C：sha256 347908a9…，116,085 行）
#   xparser  —— 原生 xparser（由 Go oracle `xnull build --emit-c impl/lib/b2/xparser.x` 生成）
#
# 用法：bootstrap/build.sh            # 幂等重建
# 环境：CC（默认 cc）、XNULL_RUNTIME（默认 <repo>/impl/runtime）
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
RT=${XNULL_RUNTIME:-$ROOT/impl/runtime}
CC=${CC:-cc}
OUT="$HERE/bin"
mkdir -p "$OUT"

[ -f "$RT/rt.h" ] || { echo "bootstrap: 找不到运行时源码：$RT/rt.h" >&2; exit 1; }

SRCS=(
  rt.c rt_gc.c rt_policy.c rt_weak.c xrt_abi.c
  rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c rt_std_net.c
  rt_task.c rt_sync.c rt_std_res.c rt_std_res_empty.c
)
RUNTIME_PATHS=()
for f in "${SRCS[@]}"; do RUNTIME_PATHS+=("$RT/$f"); done

# 零资源工程空资源表（与 impl/internal/codegen/build.go 的 emptyResourceTableC 等价）
cat > "$OUT/res.c" <<'EOF'
/* 由 bootstrap/build.sh 生成：零资源工程空表（S8 §5.6） */
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

build_one() { # name
  local name=$1
  echo "  cc -o $OUT/$name $HERE/$name.c <14 runtime> res.c"
  "$CC" -std=c11 -O2 -pthread -I "$RT" -o "$OUT/$name" \
    "$HERE/$name.c" "${RUNTIME_PATHS[@]}" "$OUT/res.c"
}

echo "bootstrap: 编译（无 Go）"
build_one xn-s4
build_one xparser

if command -v shasum >/dev/null 2>&1; then
  echo "bootstrap: 产物"
  ( cd "$OUT" && shasum -a 256 xn-s4 xparser )
fi
echo "bootstrap: 完成 → $OUT"
