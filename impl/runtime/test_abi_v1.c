/* test_abi_v1.c — S7-05 最小验收：ABI v1 版本宏 + xrt_runtime_init 顺序
 *
 * 1) _Static_assert 证明 XRT_ABI_VERSION == 1（稳定 v1 版本宏可编译期消费）；
 * 2) 正例：xrt_runtime_init() 后 xrt_alloc 成功；
 * 3) 负例：子进程不调 init 直接 xrt_alloc → 必须 fatal（S7 §6.3）。
 *
 * 只 include xrt.h（不包含 rt.h/rt_gc.h）。
 */
#define XRT_BINDINGS_LAYER 1
#include "xrt.h"

#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

_Static_assert(XRT_ABI_VERSION == 1, "S7-05: xrt.h 必须是稳定 ABI v1");

typedef struct {
    int64_t v;
} payload;

static int g_deinit = 0;
static void deinit(void *p) { (void)p; g_deinit++; }
static const xrt_type T = {"V1Probe", sizeof(payload), deinit, NULL};

static const char *g_self = NULL;

static int spawn_self(const char *mode) {
    pid_t pid = fork();
    if (pid == 0) {
        execl(g_self, g_self, mode, (char *)NULL);
        _exit(127);
    }
    if (pid < 0) {
        return -1;
    }
    int st = 0;
    if (waitpid(pid, &st, 0) != pid) {
        return -1;
    }
    return (WIFEXITED(st) && WEXITSTATUS(st) == 0) ? 0 : 1; /* 1 = 非零/信号 */
}

int main(int argc, char **argv) {
    g_self = argv[0];
    if (argc > 1 && strcmp(argv[1], "uninit") == 0) {
        (void)xrt_alloc(XRT_KIND_ARC, &T); /* 未 init → 必须 fatal */
        return 0;
    }

    xrt_runtime_init();
    xrt_runtime_init(); /* 幂等 */

    void *o = xrt_alloc(XRT_KIND_ARC, &T);
    if (o == NULL) {
        fprintf(stderr, "FAIL: xrt_alloc 返回 NULL\n");
        return 1;
    }
    xrt_release(o);
    if (g_deinit != 1) {
        fprintf(stderr, "FAIL: deinit 未执行（%d）\n", g_deinit);
        return 1;
    }

    if (spawn_self("uninit") != 1) {
        fprintf(stderr, "FAIL: 未 init 的 xrt_alloc 未 fatal（S7 §6.3）\n");
        return 1;
    }

    printf("abi v1 tests passed (XRT_ABI_VERSION=%d, init order)\n", XRT_ABI_VERSION);
    return 0;
}
