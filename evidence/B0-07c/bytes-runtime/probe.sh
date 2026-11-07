#!/bin/sh
# BYTES-RUNTIME 复现：只经 xrt.h 编译 + 运行 Bytes 对象探针。
# 用法：sh evidence/B0-07c/bytes-runtime/probe.sh /path/to/impl/runtime
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
RT=${1:-"$HERE/../../../impl/runtime"}
cc -std=c11 -Wall -Wextra -Werror -O2 -I"$RT" \
   -o /tmp/xnull_bytes_probe \
   "$HERE/probe.c" \
   "$RT/rt.c" "$RT/rt_gc.c" "$RT/rt_weak.c" "$RT/xrt_abi.c" "$RT/rt_std_bytes.c"
/tmp/xnull_bytes_probe
