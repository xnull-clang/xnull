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
cc -std=c11 -Wall -Wextra -Werror -O2 -o /tmp/xnull_test_std test_std.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_std_runtime.c rt_std_text.c rt_std_sys.c
/tmp/xnull_test_std
# 资源表（S8 §5.6）：构建期生成器 + 手工样例验证合同
XNULL_RES_DIR=$(mktemp -d)
printf 'hello' > "$XNULL_RES_DIR/a.txt"
printf '\x01\x02\xff' > "$XNULL_RES_DIR/b.bin"
XNULL_RES_C=$(mktemp -d)/res_table.c
python3 ../tools/gen_resources.py "$XNULL_RES_DIR" "$XNULL_RES_C" || exit 1
rm -rf "$XNULL_RES_DIR"
cc -std=c11 -Wall -Wextra -Werror -O2 -I. -o /tmp/xnull_test_res test_res.c "$XNULL_RES_C"
/tmp/xnull_test_res
