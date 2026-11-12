#define XRT_BINDINGS_LAYER 1
#include "xrt.h"
#include "rt.h"
#include "rt_gc.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

typedef struct { rt_header hdr; int tag; } env_t;
static const rt_type RT_TYPE_ENV = { "Mem09Env", sizeof(env_t) - sizeof(rt_header), NULL, NULL };

static int32_t body_cancel(void *env, xrt_context *ctx, xrt_task_result *out) {
    env_t *e = env;
    while (xrt_context_check_cancel(ctx) == 0) {
        struct timespec ts = {0, 1000000};
        nanosleep(&ts, NULL);
    }
    /* 取消后的清理路径：期间 env 仍必须被根保活 */
    struct timespec clean = {0, 50000000};
    nanosleep(&clean, NULL);
    out->ok = 0;
    out->kind = XRT_ERR_CANCELLED;
    out->value = (void *)(long)e->tag;
    return 0;
}

int main(void) {
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    env_t *env = rt_gc_new(&RT_TYPE_ENV);
    env->tag = 42;
    xrt_weak_slot *w = xrt_weak_bind(env);
    xrt_task *t = NULL;
    assert(xrt_task_group_spawn(g, body_cancel, env, &t) == 0);

    xrt_task_group_cancel(g);
    rt_gc_collect(); /* 任务仍在取消后的清理路径：env 必须仍为根 */
    int alive_during_cancel = xrt_weak_read(w) == env;

    xrt_task_result r;
    assert(xrt_task_join(t, &r) == 0);
    int cancelled = (r.ok == 0 && r.kind == XRT_ERR_CANCELLED && (long)r.value == 42);
    rt_gc_collect(); /* 任务终结并 unbind 后才可回收 */
    int collected = xrt_weak_read(w) == NULL;

    printf("alive_during_cancel=%d cancelled=%d collected_after_join=%d\n",
           alive_during_cancel, cancelled, collected);
    xrt_weak_clear(w);
    xrt_release(t);
    xrt_task_result fe;
    assert(xrt_task_group_close(g, &fe) == 0);
    xrt_release(g); xrt_release(ctx);
    return (alive_during_cancel && cancelled && collected) ? 0 : 1;
}
