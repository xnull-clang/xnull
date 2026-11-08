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
# S7-05：稳定 ABI v1 原生链接测试（只 include xrt.h）+ 初始化顺序 + 弱表门禁
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_abi_link \
  test_abi_link.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_std_bytes.c
/tmp/xnull_test_abi_link
# S7-05 最小验收：XRT_ABI_VERSION 编译期断言 + init 顺序（正例/子进程负例）
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_abi_v1 \
  test_abi_v1.c rt.c rt_gc.c rt_weak.c xrt_abi.c
/tmp/xnull_test_abi_v1
# 弱表 bindings-only：应用层（未定义 XRT_BINDINGS_LAYER）引用必须编译失败
printf '#include "xrt.h"\nint main(void) { return xrt_weak_bind(0) != 0; }\n' > /tmp/xnull_weak_app.c
if cc -std=c11 -I. -c /tmp/xnull_weak_app.c -o /tmp/xnull_weak_app.o 2>/dev/null; then
  echo "弱表门禁失败：应用层引用 xrt_weak_* 竟然编译通过（S7 §6.2）" >&2
  exit 1
fi
# 绑定层定义宏后可编译
printf '#define XRT_BINDINGS_LAYER 1\n#include "xrt.h"\nint main(void) { return xrt_weak_bind(0) != 0; }\n' > /tmp/xnull_weak_bind.c
cc -std=c11 -I. -c /tmp/xnull_weak_bind.c -o /tmp/xnull_weak_bind.o
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_std test_std.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c
/tmp/xnull_test_std
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_task test_task.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c
/tmp/xnull_test_task
# S7-06：.unaware + @longRunning 伴生路由压力/一致性
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_companion test_companion.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c
/tmp/xnull_test_companion
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_sync test_sync.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c rt_sync.c
/tmp/xnull_test_sync
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_sysasync test_sysasync.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c rt_std_sys.c
/tmp/xnull_test_sysasync
# S6-09/ADR-009：socket plain/Async + net.http 最小面
cc -std=c11 -Wall -Wextra -Werror -O2 -pthread -o /tmp/xnull_test_net test_net.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_task.c rt_std_net.c
/tmp/xnull_test_net
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
