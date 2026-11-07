/* test_task.c — S5-01 调度器核心合同测试（任务/组/上下文/取消/超时/panic） */
#include "xrt.h"
#include "rt.h"
#include "rt_gc.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int32_t body_ok(void *env, xrt_context *ctx, xrt_task_result *out) {
    (void)env;
    (void)ctx;
    out->ok = 1;
    out->value = (void *)(intptr_t)42;
    return 0;
}

static int32_t body_err(void *env, xrt_context *ctx, xrt_task_result *out) {
    (void)env;
    (void)ctx;
    out->ok = 0;
    out->kind = XRT_ERR_NOT_FOUND;
    return 0;
}

static int32_t body_cancel(void *env, xrt_context *ctx, xrt_task_result *out) {
    (void)env;
    while (xrt_context_check_cancel(ctx) == 0) {
        struct timespec ts = {0, 1000000}; /* 1ms */
        nanosleep(&ts, NULL);
    }
    out->ok = 0;
    out->kind = XRT_ERR_CANCELLED;
    return 0;
}

static int32_t body_slow(void *env, xrt_context *ctx, xrt_task_result *out) {
    (void)env;
    (void)ctx;
    struct timespec ts = {0, 30000000}; /* 30ms */
    nanosleep(&ts, NULL);
    out->ok = 1;
    out->value = (void *)(intptr_t)7;
    return 0;
}

static int32_t body_panic(void *env, xrt_context *ctx, xrt_task_result *out) {
    (void)env;
    (void)ctx;
    (void)out;
    rt_fatal("任务内 panic（S5 §8：进程级终止）");
    return 0;
}

typedef struct {
    rt_header hdr;
    int       marker;
} test_env_t;

static const rt_type RT_TYPE_TEST_ENV = {
    "TestEnv", sizeof(test_env_t) - sizeof(rt_header), NULL, NULL
};

static void test_ok_and_err(void) {
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    xrt_task *t = NULL;
    assert(xrt_task_group_spawn(g, body_ok, NULL, &t) == 0);
    xrt_task_result r;
    assert(xrt_task_join(t, &r) == 0);
    assert(r.ok == 1 && (intptr_t)r.value == 42);
    xrt_release(t);

    assert(xrt_task_group_spawn(g, body_err, NULL, &t) == 0);
    assert(xrt_task_join(t, &r) == 0);
    assert(r.ok == 0 && r.kind == XRT_ERR_NOT_FOUND);
    xrt_release(t);

    xrt_task_result fe;
    assert(xrt_task_group_close(g, &fe) == 0);
    /* 首个非取消错误 = NotFound（close 不消费 join 结果） */
    assert(fe.ok == 0 && fe.kind == XRT_ERR_NOT_FOUND);
    xrt_release(g);
    xrt_release(ctx);
}

static void test_cancel_close(void) {
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    xrt_task *t = NULL;
    assert(xrt_task_group_spawn(g, body_cancel, NULL, &t) == 0);
    xrt_task_result fe;
    assert(xrt_task_group_close(g, &fe) == 0); /* 取消 + 等待终结 */
    xrt_task_result r;
    assert(xrt_task_join(t, &r) == 0);
    assert(r.ok == 0 && r.kind == XRT_ERR_CANCELLED);
    xrt_release(t);
    xrt_release(g);
    xrt_release(ctx);
}

static void test_join_deadline(void) {
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    xrt_task *t = NULL;
    assert(xrt_task_group_spawn(g, body_slow, NULL, &t) == 0);
    xrt_task_result r;
    int rc = xrt_task_join_deadline(t, xrt_clock_mono_ms() + 5, &r);
    assert(rc == XRT_ERR_TIMEOUT);
    assert(xrt_task_join(t, &r) == 0);
    assert(r.ok == 1 && (intptr_t)r.value == 7);
    xrt_release(t);
    xrt_task_result fe;
    assert(xrt_task_group_close(g, &fe) == 0);
    xrt_release(g);
    xrt_release(ctx);
}

static void test_env_root(void) {
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    test_env_t *env = rt_gc_new(&RT_TYPE_TEST_ENV);
    xrt_weak_slot *w = xrt_weak_bind(env);
    xrt_task *t = NULL;
    assert(xrt_task_group_spawn(g, body_ok, env, &t) == 0);
    xrt_task_result r;
    assert(xrt_task_join(t, &r) == 0);
    assert(xrt_weak_read(w) == env); /* 存活期间可达（join 前） */
    rt_gc_collect();                 /* 任务已终结：env 根已注销 */
    assert(xrt_weak_read(w) == NULL);
    xrt_weak_clear(w);
    xrt_release(t);
    xrt_task_result fe;
    assert(xrt_task_group_close(g, &fe) == 0);
    xrt_release(g);
    xrt_release(ctx);
}

static const char *g_self_path = NULL;

static void run_repeat_join(void) {
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    xrt_task *t = NULL;
    if (xrt_task_group_spawn(g, body_ok, NULL, &t) != 0) {
        _exit(0);
    }
    xrt_task_result r;
    (void)xrt_task_join(t, &r);
    (void)xrt_task_join(t, &r); /* 合同错误 → fatal */
    _exit(0);
}

static void run_panic(void) {
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    xrt_task *t = NULL;
    if (xrt_task_group_spawn(g, body_panic, NULL, &t) != 0) {
        _exit(0);
    }
    xrt_task_result r;
    (void)xrt_task_join(t, &r);
    _exit(0);
}

static int spawn_self(const char *mode) {
    pid_t pid = fork();
    if (pid == 0) {
        execl(g_self_path, g_self_path, mode, (char *)NULL);
        _exit(127);
    }
    if (pid < 0) {
        return -1;
    }
    int st = 0;
    if (waitpid(pid, &st, 0) != pid) {
        return -1;
    }
    return (WIFEXITED(st) && WEXITSTATUS(st) == 0) ? 0 : 1;
}

static void test_contract_fatal(void) {
    /* 重复 join → fatal（子进程 exec 自身，避免继承父进程线程状态） */
    int rc = spawn_self("repeat-join");
    assert(rc == 1);
}

static void test_panic_fatal(void) {
    int rc = spawn_self("panic");
    assert(rc == 1); /* 任务内 panic → 进程终止 */
}

int main(int argc, char **argv) {
    g_self_path = argv[0];
    if (argc > 1 && strcmp(argv[1], "repeat-join") == 0) {
        run_repeat_join();
        return 0;
    }
    if (argc > 1 && strcmp(argv[1], "panic") == 0) {
        run_panic();
        return 0;
    }
    test_ok_and_err();
    test_cancel_close();
    test_join_deadline();
    test_env_root();
    test_contract_fatal();
    test_panic_fatal();
    printf("task tests passed (spawn/join/close/cancel/timeout/root/panic)\n");
    return 0;
}
