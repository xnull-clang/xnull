/* test_abi_link.c — 原生侧只包含 xrt.h 的 ABI 链接/运行测试（S7-05 / FFI-06）
 *
 * 目的：
 *   - 证明稳定 v1 符号（xrt_alloc/retain/release/weak/root/handle/callback/string/bytes）
 *     可被“只 include xrt.h”的原生 TU 编译并链接（不包含 rt.h/rt_gc.h，INV-FFI-7）；
 *   - 证明 xrt_runtime_init 必须在 xrt_alloc 之前（S7 §6.3）；
 *   - 证明弱表默认不对应用层声明（XRT_BINDINGS_LAYER 门禁）。
 */
#define XRT_BINDINGS_LAYER 1 /* 本测试扮演绑定层；应用层不定义此宏 */

#include "xrt.h"

#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int g_failures = 0;
#define CHECK(cond)                                                          \
    do {                                                                     \
        if (!(cond)) {                                                       \
            g_failures++;                                                    \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);   \
        }                                                                    \
    } while (0)

typedef struct {
    int64_t v;
} payload;

static int g_close_calls = 0;
static void close_fn(void *native) { (void)native; g_close_calls++; }
static void deinit(void *p) { (void)p; }
static void scan(void *p, void (*visit)(void *)) { (void)p; (void)visit; }

static const xrt_type T_ARC = {"LinkArc", sizeof(payload), deinit, NULL};
static const xrt_type T_GC = {"LinkGC", sizeof(payload), NULL, scan};

static int32_t callback(void *closure, const void *args, size_t nargs, void *result) {
    (void)args;
    (void)nargs;
    *(int32_t *)result = (*(int32_t *)closure) + 1;
    return 7;
}

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
        /* 未 init 就分配：必须 fatal（S7 §6.3）。 */
        (void)xrt_alloc(XRT_KIND_ARC, &T_ARC);
        return 0;
    }
    if (argc > 1 && strcmp(argv[1], "after-destroy") == 0) {
        xrt_runtime_init();
        int32_t n = 1;
        xrt_callback_env *env = xrt_callback_env_new(&n, callback);
        xrt_callback_env_destroy(env);
        (void)xrt_callback_env_invoke(env, NULL, 0, &n); /* 注销后调用 → fatal */
        return 0;
    }

    CHECK(XRT_ABI_VERSION == 1);
    xrt_runtime_init();
    xrt_runtime_init(); /* 幂等 */

    /* ARC 分配/计数/终结 */
    payload *a = (payload *)xrt_alloc(XRT_KIND_ARC, &T_ARC);
    CHECK(a != NULL && xrt_refcount(a) == 1);
    CHECK(xrt_retain(a) == a && xrt_refcount(a) == 2);
    xrt_release(a);
    CHECK(xrt_refcount(a) == 1);

    /* 弱表（绑定层可见） */
    xrt_weak_slot *w = xrt_weak_bind(a);
    CHECK(w != NULL && xrt_weak_read(w) == a);
    xrt_release(a); /* 终结链清除弱槽位 */
    CHECK(xrt_weak_read(w) == NULL);
    xrt_weak_clear(w);
    xrt_safepoint();

    /* GC + 根/屏障/安全点 */
    payload *g = (payload *)xrt_alloc(XRT_KIND_GC, &T_GC);
    CHECK(g != NULL);
    xrt_write_barrier(g);
    xrt_register_root(g);
    xrt_safepoint();
    xrt_unregister_root(g);
    xrt_safepoint();

    /* 句柄：显式 close、幂等、已关闭不再触达 */
    payload marker = {9};
    xrt_handle *h = xrt_handle_new(&marker, close_fn, "link");
    CHECK(h != NULL && xrt_handle_native(h) == &marker);
    CHECK(xrt_handle_close(h) == 0 && g_close_calls == 1);
    CHECK(xrt_handle_close(h) == 0 && g_close_calls == 1); /* 幂等 */
    CHECK(xrt_handle_is_closed(h) == 1 && xrt_handle_native(h) == NULL);
    xrt_release(h);

    /* 回调 env：创建/调用/销毁 */
    int32_t seed = 41;
    int32_t out = 0;
    xrt_callback_env *env = xrt_callback_env_new(&seed, callback);
    CHECK(env != NULL && xrt_callback_env_alive(env) == 1);
    CHECK(xrt_callback_env_invoke(env, NULL, 0, &out) == 7 && out == 42);
    CHECK(xrt_callback_env_closure(env) == &seed);
    xrt_callback_env_destroy(env);
    CHECK(xrt_callback_env_alive(env) == 0);

    /* String / Bytes 访问器（只经 xrt.h） */
    xrt_string *s = xrt_string_new("abc", 3);
    CHECK(xrt_string_len(s) == 3 && memcmp(xrt_string_bytes(s), "abc", 3) == 0);
    xrt_release(s);

    xrt_bytes_buf *b = xrt_bytes_from_c("xy", 2);
    CHECK(xrt_bytes_len(b) == 2 && memcmp(xrt_bytes_data(b), "xy", 2) == 0);
    xrt_release(b);

    /* 错误分类名可链接 */
    CHECK(strcmp(xrt_error_kind_name(XRT_ERR_CANCELLED), "Cancelled") == 0);

    /* 初始化顺序负例：未 init 的 xrt_alloc 必须 fatal */
    CHECK(spawn_self("uninit") == 1);
    /* 注销后回调必须 fatal */
    CHECK(spawn_self("after-destroy") == 1);

    if (g_failures != 0) {
        fprintf(stderr, "abi link 测试失败 %d 项\n", g_failures);
        return 1;
    }
    printf("abi link tests passed (xrt.h only, init order, weak gate, handle/callback)\n");
    return 0;
}
