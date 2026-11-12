#!/bin/sh
# QA 侧复现脚本：S6-09 取消/错误/关闭补充夹具（只读产品代码，不修改）
set -e
cd "$(dirname "$0")/../../.."
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -I impl/runtime \
  -o /tmp/xnull_qa_net_cancel evidence/S6-QA/XDK-09c/qa_net_cancel.c \
  impl/runtime/rt.c impl/runtime/rt_gc.c impl/runtime/rt_weak.c \
  impl/runtime/xrt_abi.c impl/runtime/rt_task.c impl/runtime/rt_std_net.c \
  impl/runtime/rt_std_bytes.c
/tmp/xnull_qa_net_cancel
