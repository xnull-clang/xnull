#!/usr/bin/env bash
# QA1 独立验证 xdkc_utf8_valid（S1 §9.2）：只测公开 C 入口，不引用 E5 单测。
# 用法：bash verify-utf8-runtime.sh            # 从 E5_SHA 导出并编译
#       RUNTIME_DIR=<path> bash verify-utf8-runtime.sh
set -uo pipefail

REPO=${REPO:-/Users/vjs/Desktop/XNull-Lang}
E5_SHA=${E5_SHA:-c9e8a5d}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/qa-utf8.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

RT=${RUNTIME_DIR:-}
if [ -z "$RT" ]; then
    git -C "$REPO" archive --format=tar "$E5_SHA" | tar -x -C "$TMP" || exit 2
    RT=$TMP/impl/runtime
fi

cc -std=c11 -Wall -Wextra -Werror -O2 -I"$RT" -o "$TMP/probe" \
    "$HERE/utf8_valid_probe.c" \
    "$RT/rt.c" "$RT/rt_gc.c" "$RT/rt_weak.c" "$RT/xrt_abi.c" \
    "$RT/rt_std_runtime.c" "$RT/rt_std_text.c" "$RT/rt_std_sys.c" || exit 2

"$TMP/probe"
