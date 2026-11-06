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
