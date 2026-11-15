/* test_companion.c — S7-06：.unaware + @longRunning 伴生执行器压力/一致性用例
 *
 * 合同（S5 §2.2 / S7 §7.3）：
 *   - 长阻塞 .unaware 调用提交到 xrt_companion_submit/wait，不占载体线程；
 *   - 等待可被 Context 取消（返回 XRT_ERR_CANCELLED），原生调用继续；
 *   - 分类一致性：worker 线程上 xrt_companion_on_worker()==1，主/载体线程为 0；
 *   - 压力：多任务排队 + 取消风暴 + 正常任务不被伴生池阻塞。
 */
#define _POSIX_C_SOURCE 200809L
#include "xrt.h"

#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

typedef struct {
    int         id;
    pthread_t   tid;
    atomic_int *done;
} job_t;

static void *worker(void *arg) {
    job_t *j = arg;
    assert(xrt_companion_on_worker() == 1); /* 必须运行在伴生 worker 上 */
    j->tid = pthread_self();
    struct timespec ts = {0, 2000000}; /* 2ms：模拟长阻塞 */
    nanosleep(&ts, NULL);
    atomic_fetch_add(j->done, 1);
    return j;
}

static atomic_int g_flag;
static int32_t body_flag(void *env, xrt_context *ctx, xrt_task_result *out) {
    (void)ctx;
    atomic_store((atomic_int *)env, 1);
    out->ok = 1;
    return 0;
}

int main(void) {
    /* 在首次提交前设置池大小；xrt_companion_thread_count 会触发初始化。 */
    assert(setenv("XNULL_COMPANIONS", "4", 1) == 0);
    assert(xrt_companion_thread_count() == 4);
    assert(xrt_companion_on_worker() == 0);

    pthread_t main_tid = pthread_self();

    /* 1) 压力：64 个长阻塞调用排队，全部完成且结果正确。 */
    enum { N = 64 };
    job_t jobs[N];
    xrt_future *fs[N];
    atomic_int done = 0;
    for (int i = 0; i < N; i++) {
        jobs[i].id = i;
        jobs[i].done = &done;
        fs[i] = xrt_companion_submit(worker, &jobs[i]);
        assert(fs[i] != NULL);
    }

    /* 2) 分类一致性：伴生池忙时，普通任务仍能在载体上按时完成。 */
    atomic_store(&g_flag, 0);
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    xrt_task *t = NULL;
    assert(xrt_task_group_spawn(g, body_flag, &g_flag, &t) == 0);
    xrt_task_result r;
    assert(xrt_task_join_deadline(t, xrt_clock_mono_ms() + 200, &r) == 0 && r.ok == 1);
    assert(atomic_load(&g_flag) == 1);
    xrt_release(t);
    xrt_task_result fe;
    assert(xrt_task_group_close(g, &fe) == 0);
    xrt_release(g);
    xrt_release(ctx);

    for (int i = 0; i < N; i++) {
        void *out = NULL;
        assert(xrt_companion_wait(fs[i], NULL, &out) == 0);
        assert(out == &jobs[i]);
        assert(!pthread_equal(jobs[i].tid, main_tid));
        xrt_release(fs[i]);
    }
    assert(atomic_load(&done) == N);

    /* 3) 取消风暴：等待立即返回 Cancelled；原生调用继续，稍后再取结果。 */
    enum { M = 16 };
    job_t cjobs[M];
    xrt_future *cfs[M];
    atomic_int cdone = 0;
    xrt_context *dead = xrt_context_with_deadline(xrt_context_background(),
                                                  xrt_clock_mono_ms() - 1);
    for (int i = 0; i < M; i++) {
        cjobs[i].id = i;
        cjobs[i].done = &cdone;
        cfs[i] = xrt_companion_submit(worker, &cjobs[i]);
        assert(cfs[i] != NULL);
        void *out = NULL;
        assert(xrt_companion_wait(cfs[i], dead, &out) == XRT_ERR_CANCELLED);
    }
    for (int i = 0; i < M; i++) {
        void *out = NULL;
        assert(xrt_companion_wait(cfs[i], NULL, &out) == 0);
        assert(out == &cjobs[i]);
        xrt_release(cfs[i]);
    }
    assert(atomic_load(&cdone) == M);
    xrt_release(dead);

    printf("companion tests passed (pool=4, stress=%d+cancel=%d, carrier-free)\n", N, M);
    return 0;
}
