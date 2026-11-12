#define XRT_BINDINGS_LAYER 1
/* MEM-09 只读探针：两个任务共享同一 GC env；先完成者不得撤掉仍存活任务的根。 */
#include "xrt.h"
#include "rt.h"
#include "rt_gc.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

typedef struct { rt_header hdr; int tag; } env_t;
static const rt_type RT_TYPE_ENV = { "Mem09Env", sizeof(env_t) - sizeof(rt_header), NULL, NULL };

static int32_t body_fast(void *env, xrt_context *ctx, xrt_task_result *out) {
    (void)env; (void)ctx;
    out->ok = 1; out->value = (void *)(long)1; return 0;
}
static int32_t body_slow(void *env, xrt_context *ctx, xrt_task_result *out) {
    (void)ctx;
    env_t *e = env;
    struct timespec ts = {0, 50000000}; /* 50ms：保持任务存活 */
    nanosleep(&ts, NULL);
    out->ok = 1; out->value = (void *)(long)e->tag; return 0;
}

int main(void) {
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    env_t *env = rt_gc_new(&RT_TYPE_ENV);
    env->tag = 42;
    xrt_weak_slot *w = xrt_weak_bind(env);

    xrt_task *a = NULL, *b = NULL;
    assert(xrt_task_group_spawn(g, body_fast, env, &a) == 0);
    assert(xrt_task_group_spawn(g, body_slow, env, &b) == 0);

    xrt_task_result r;
    assert(xrt_task_join(a, &r) == 0 && r.ok == 1);
    rt_gc_collect(); /* A 完成；B 仍存活，env 应仍被 B 的根保活 */
    int alive = xrt_weak_read(w) == env;

    int jb = xrt_task_join(b, &r);
    printf("alive=%d joinB=%d ok=%d value=%ld\n", alive, jb, r.ok, (long)r.value);
    rt_gc_collect(); /* B 完成并 unbind 后，env 应可回收 */
    int collected = xrt_weak_read(w) == NULL;

    printf("shared_env_alive_during_slow_task=%d collected_after_both=%d\n", alive, collected);
    xrt_weak_clear(w);
    xrt_release(a); xrt_release(b);
    xrt_task_result fe;
    assert(xrt_task_group_close(g, &fe) == 0);
    xrt_release(g); xrt_release(ctx);
    return (alive && collected) ? 0 : 1;
}
