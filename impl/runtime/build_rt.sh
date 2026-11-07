#!/bin/sh
# M3 运行时构建与测试（验收基线：-O2 -Werror 零缺陷）
set -e
cd "$(dirname "$0")"
cc -std=c11 -Wall -Wextra -Werror -O2 -o /tmp/xnull_test_rt test_rt.c rt.c rt_policy.c rt_gc.c rt_weak.c
/tmp/xnull_test_rt
cc -std=c11 -Wall -Wextra -Werror -O2 -o /tmp/xnull_test_gc test_gc.c rt.c rt_gc.c rt_weak.c
/tmp/xnull_test_gc
cc -std=c11 -Wall -Wextra -Werror -O2 -o /tmp/xnull_test_hard test_hard.c rt.c rt_gc.c rt_weak.c
/tmp/xnull_test_hard
cc -std=c11 -Wall -Wextra -Werror -O2 -o /tmp/xnull_test_abi test_abi.c rt.c rt_gc.c rt_weak.c xrt_abi.c
/tmp/xnull_test_abi
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_std test_std.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c
/tmp/xnull_test_std
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_task test_task.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c
/tmp/xnull_test_task
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_sync test_sync.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c rt_sync.c
/tmp/xnull_test_sync
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_sysasync test_sysasync.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c rt_std_sys.c
/tmp/xnull_test_sysasync
# 资源表（S8 §5.6）：构建期生成器 + 手工样例验证合同
XNULL_RES_DIR=$(mktemp -d)
printf 'hello' > "$XNULL_RES_DIR/a.txt"
printf '\x01\x02\xff' > "$XNULL_RES_DIR/b.bin"
XNULL_RES_C=$(mktemp -d)/res_table.c
(cd .. && go run ./cmd/xnull dev res "$XNULL_RES_DIR" "$XNULL_RES_C") || exit 1
rm -rf "$XNULL_RES_DIR"
cc -std=c11 -Wall -Wextra -Werror -O2 -I. -o /tmp/xnull_test_res test_res.c "$XNULL_RES_C"
/tmp/xnull_test_res
# 资源读取 5 API（S6 §4.8 / XDK-10）：资源表进构建 + 运行时 rt_std_res.c
XNULL_RES_API_DIR=$(mktemp -d)
printf 'hello' > "$XNULL_RES_API_DIR/a.txt"
printf '\x01\x02\xff' > "$XNULL_RES_API_DIR/b.bin"
printf '\xff\xfe' > "$XNULL_RES_API_DIR/bad.txt"
mkdir -p "$XNULL_RES_API_DIR/dir1" "$XNULL_RES_API_DIR/dir2"
printf 'x' > "$XNULL_RES_API_DIR/dir1/x.txt"
printf 'yy' > "$XNULL_RES_API_DIR/dir1/y.txt"
printf 'zzz' > "$XNULL_RES_API_DIR/dir2/z.txt"
printf 'R' > "$XNULL_RES_API_DIR/xres_only.txt"
XNULL_RES_API_C=$(mktemp -d)/res_api_table.c
(cd .. && go run ./cmd/xnull dev res "$XNULL_RES_API_DIR" "$XNULL_RES_API_C") || exit 1
rm -rf "$XNULL_RES_API_DIR"
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -I. -o /tmp/xnull_test_res_api \
  test_res_api.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c \
  rt_std_res.c rt_std_bytes.c rt_std_text.c rt_std_sys.c "$XNULL_RES_API_C"
/tmp/xnull_test_res_api
# 零资源工程 / 手工 cc 测试：rt_std_res_empty.c 弱兜底闭合 xrt_resource_* 符号
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -I. -o /tmp/xnull_test_res_empty \
  test_res_empty.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c \
  rt_std_res.c rt_std_res_empty.c rt_std_bytes.c rt_std_text.c
/tmp/xnull_test_res_empty
