/* rt_task.c — 任务运行时调度器核心（S5-01；S5-00 接口冻结面 v0）
 *
 * 范围：
 *   - 任务对象/任务组/上下文；单载体线程 + 全局 FIFO 队列；
 *   - spawn/join/join_deadline/close/cancel；取消协作式；
 *   - 任务 env 在存活期登记为 GC 根（xrt_task_root_bind/unbind）；
 *   - 合同错误（重复 join/close、关闭后 spawn）→ rt_fatal。
 *
 * 未覆盖（后续卡）：
 *   - Channel/Mutex/Atomic*（S5-03）；
 *   - 多载体线程与并发 GC（S3-06 原子弱表/屏障后）。
 *
 * 线程安全：任务/组状态由组互斥量保护；GC 根表本身仍为单线程结构，
 * 首版以「主线程等待 join/close 时不并发触达 GC」为使用前提（S5-00 §七）。
 */
#include "xrt.h"
#include "rt.h"
#include "rt_gc.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ---- 上下文 ---- */

typedef struct {
    rt_header       hdr;
    xrt_context    *parent;  /* ARC 持有 */
    int             cancelled;
    int64_t         deadline; /* 单调毫秒；0 = 无截止 */
} context_obj;

static void context_deinit(void *obj) {
    context_obj *c = obj; /* deinit 收完整对象指针（rt.h 约定） */
    rt_release(c->parent);
    c->parent = NULL;
}

static const rt_type RT_TYPE_XRT_CONTEXT = {
    "xrt_context", sizeof(context_obj) - sizeof(rt_header), context_deinit, NULL
};

static xrt_context *context_alloc(xrt_context *parent, int64_t deadline) {
    rt_object *o = rt_arc_new(&RT_TYPE_XRT_CONTEXT);
    context_obj *c = (context_obj *)o;
    c->parent = (xrt_context *)rt_retain(parent);
    c->cancelled = 0;
    c->deadline = deadline;
    return (xrt_context *)o;
}

static context_obj *context_of(const xrt_context *ctx) {
    return ctx == NULL ? NULL : (context_obj *)(void *)ctx;
}

int64_t xrt_clock_mono_ms(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        rt_fatal("xrt_clock_mono_ms：单调时钟不可用（S5 §6）");
    }
    return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
}

xrt_context *xrt_context_background(void) {
    return context_alloc(NULL, 0);
}

xrt_context *xrt_context_child(xrt_context *parent) {
    return context_alloc(parent, 0);
}

xrt_context *xrt_context_with_deadline(xrt_context *parent, int64_t deadline_mono_ms) {
    return context_alloc(parent, deadline_mono_ms);
}

/* 返回 1 表示该上下文（或其祖先）已取消/到期；到期时把自身置取消。 */
static int context_cancelled_flag(context_obj *c) {
    if (c == NULL) {
        return 0;
    }
    if (c->cancelled) {
        return 1;
    }
    if (c->deadline != 0 && xrt_clock_mono_ms() >= c->deadline) {
        c->cancelled = 1;
        return 1;
    }
    return 0;
}

int32_t xrt_context_check_cancel(const xrt_context *ctx) {
    for (context_obj *c = context_of(ctx); c != NULL; c = context_of(c->parent)) {
        if (context_cancelled_flag(c)) {
            return XRT_ERR_CANCELLED;
        }
    }
    return 0;
}

int32_t xrt_context_cancelled(const xrt_context *ctx) {
    return xrt_context_check_cancel(ctx) == XRT_ERR_CANCELLED ? 1 : 0;
}

xrt_cancel_token *xrt_context_token(xrt_context *ctx) {
    return (xrt_cancel_token *)ctx; /* 借用：token 即 context 自身 */
}

void xrt_context_cancel(xrt_context *ctx) {
    context_obj *c = context_of(ctx);
    if (c != NULL) {
        c->cancelled = 1;
    }
}

/* ---- 任务 / 组 ---- */

struct xrt_task {
    rt_header       hdr;
    void           *env;
    xrt_task_body   body;
    xrt_task_group *group;   /* 借用：组必须晚于任务终结释放 */
    int             state;   /* 0 待运行 / 1 运行中 / 2 已终结 */
    int             joined;  /* 0/1：join 一次性 */
    xrt_task_result result;
    struct xrt_task *next;   /* 队列链 */
};

struct xrt_task_group {
    rt_header       hdr;
    xrt_context    *ctx;
    pthread_mutex_t mu;
    pthread_cond_t  cv;
    int             closed;
    int             active;
    xrt_task      **tasks;
    size_t          ntasks;
    size_t          cap;
    int             have_error;
    xrt_task_result first_error; /* 仅保留 kind（value/error 仍归 join） */
};

static void task_deinit(void *obj) {
    struct xrt_task *t = obj;
    (void)t; /* 结果所有权归 join；未 join 属合同使用错误 */
}

static const rt_type RT_TYPE_XRT_TASK = {
    "xrt_task", sizeof(struct xrt_task) - sizeof(rt_header), task_deinit, NULL
};

static void group_deinit(void *obj) {
    struct xrt_task_group *g = obj;
    if (g->active > 0) {
        rt_fatal("任务组在未关闭/未终结时释放（S5 §3.2 合同错误）");
    }
    pthread_cond_destroy(&g->cv);
    pthread_mutex_destroy(&g->mu);
    rt_release(g->ctx);
    for (size_t i = 0; i < g->ntasks; i++) {
        rt_release(g->tasks[i]);
    }
    free(g->tasks);
}

static const rt_type RT_TYPE_XRT_TASK_GROUP = {
    "xrt_task_group", sizeof(struct xrt_task_group) - sizeof(rt_header), group_deinit, NULL
};

/* 全局 FIFO 队列 + 单载体线程 */
static pthread_mutex_t g_qmu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_qcv = PTHREAD_COND_INITIALIZER;
static struct xrt_task *g_qhead = NULL;
static struct xrt_task *g_qtail = NULL;
static pthread_once_t  g_worker_once = PTHREAD_ONCE_INIT;

static void *worker_main(void *arg) {
    (void)arg;
    for (;;) {
        pthread_mutex_lock(&g_qmu);
        while (g_qhead == NULL) {
            pthread_cond_wait(&g_qcv, &g_qmu);
        }
        struct xrt_task *t = g_qhead;
        g_qhead = t->next;
        if (g_qhead == NULL) {
            g_qtail = NULL;
        }
        pthread_mutex_unlock(&g_qmu);

        struct xrt_task_group *g = t->group;
        pthread_mutex_lock(&g->mu);
        t->state = 1;
        pthread_mutex_unlock(&g->mu);

        xrt_task_result r;
        memset(&r, 0, sizeof(r));
        r.ok = 0;
        r.kind = XRT_ERR_INTERNAL;
        int32_t rc = t->body(t->env, g->ctx, &r);
        if (rc != 0) {
            r.ok = 0;
            r.kind = XRT_ERR_INTERNAL;
            r.value = NULL;
        }

        xrt_task_root_unbind(t->env);
        pthread_mutex_lock(&g->mu);
        t->result = r;
        t->state = 2;
        if (g->active > 0) {
            g->active--;
        }
        if (!r.ok && r.kind != XRT_ERR_CANCELLED && !g->have_error) {
            g->have_error = 1;
            g->first_error.ok = 0;
            g->first_error.kind = r.kind;
            g->first_error.value = NULL;
            g->first_error.error = NULL;
        }
        pthread_cond_broadcast(&g->cv);
        pthread_mutex_unlock(&g->mu);
    }
    return NULL;
}

static void worker_init(void) {
    pthread_t th;
    if (pthread_create(&th, NULL, worker_main, NULL) != 0) {
        rt_fatal("调度器：载体线程创建失败（S5 §2.2）");
    }
    pthread_detach(th);
}

xrt_task_group *xrt_task_group_new(xrt_context *parent) {
    rt_object *o = rt_arc_new(&RT_TYPE_XRT_TASK_GROUP);
    struct xrt_task_group *g = (struct xrt_task_group *)o;
    g->ctx = (xrt_context *)xrt_context_background();
    if (parent != NULL) {
        rt_release(g->ctx);
        g->ctx = (xrt_context *)rt_retain(parent);
    }
    pthread_mutex_init(&g->mu, NULL);
    pthread_cond_init(&g->cv, NULL);
    g->closed = 0;
    g->active = 0;
    g->tasks = NULL;
    g->ntasks = 0;
    g->cap = 0;
    g->have_error = 0;
    memset(&g->first_error, 0, sizeof(g->first_error));
    return (xrt_task_group *)o;
}

int32_t xrt_task_group_spawn(xrt_task_group *grp, xrt_task_body body, void *env, xrt_task **out) {
    if (grp == NULL || body == NULL || out == NULL) {
        rt_fatal("task_group_spawn：参数为空（S5-00 §三）");
    }
    struct xrt_task_group *g = (struct xrt_task_group *)grp;
    pthread_once(&g_worker_once, worker_init);

    pthread_mutex_lock(&g->mu);
    if (g->closed) {
        pthread_mutex_unlock(&g->mu);
        rt_fatal("task_group_spawn：组已关闭（S5 §3.2）");
    }
    if (g->ntasks == g->cap) {
        size_t cap = g->cap ? g->cap * 2 : 8;
        xrt_task **nt = realloc(g->tasks, cap * sizeof(*nt));
        if (nt == NULL) {
            pthread_mutex_unlock(&g->mu);
            rt_fatal("task_group_spawn：任务表扩容失败（S3 §2）");
        }
        g->tasks = nt;
        g->cap = cap;
    }
    rt_object *o = rt_arc_new(&RT_TYPE_XRT_TASK);
    struct xrt_task *t = (struct xrt_task *)o;
    t->env = env;
    t->body = body;
    t->group = grp;
    t->state = 0;
    t->joined = 0;
    memset(&t->result, 0, sizeof(t->result));
    t->next = NULL;
    g->active++;
    g->tasks[g->ntasks++] = (xrt_task *)o; /* 组持有 +1 */
    pthread_mutex_unlock(&g->mu);

    xrt_task_root_bind(env);
    pthread_mutex_lock(&g_qmu);
    if (g_qtail != NULL) {
        g_qtail->next = t;
    } else {
        g_qhead = t;
    }
    g_qtail = t;
    pthread_cond_signal(&g_qcv);
    pthread_mutex_unlock(&g_qmu);

    *out = (xrt_task *)o; /* 返回调用方 +1（创建计数） */
    return 0;
}

void xrt_task_group_cancel(xrt_task_group *grp) {
    struct xrt_task_group *g = grp == NULL ? NULL : (struct xrt_task_group *)grp;
    if (g != NULL) {
        xrt_context_cancel(g->ctx);
    }
}

int32_t xrt_task_group_close(xrt_task_group *grp, xrt_task_result *first_error) {
    if (grp == NULL) {
        rt_fatal("task_group_close：组为空（S5 §3.2）");
    }
    struct xrt_task_group *g = (struct xrt_task_group *)grp;
    pthread_mutex_lock(&g->mu);
    if (g->closed) {
        pthread_mutex_unlock(&g->mu);
        rt_fatal("task_group_close：重复关闭（S5 §3.2 合同错误）");
    }
    g->closed = 1;
    xrt_context_cancel(g->ctx);
    while (g->active > 0) {
        pthread_cond_wait(&g->cv, &g->mu);
    }
    int have = g->have_error;
    xrt_task_result e = g->first_error;
    pthread_mutex_unlock(&g->mu);

    if (first_error != NULL) {
        memset(first_error, 0, sizeof(*first_error));
        if (have) {
            *first_error = e; /* 仅 kind；value/error 仍归对应 join */
        } else {
            first_error->ok = 1;
        }
    }
    return 0;
}

/* 等待任务终结：0=已终结；XRT_ERR_TIMEOUT=截止先到。调用方持 g->mu。 */
static int wait_done(struct xrt_task_group *g, struct xrt_task *t, int64_t deadline) {
    while (t->state != 2) {
        if (deadline == 0) {
            pthread_cond_wait(&g->cv, &g->mu);
            continue;
        }
        int64_t now = xrt_clock_mono_ms();
        if (now >= deadline) {
            return XRT_ERR_TIMEOUT;
        }
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        int64_t delta = deadline - now;
        ts.tv_sec += (time_t)(delta / 1000);
        ts.tv_nsec += (long)((delta % 1000) * 1000000);
        if (ts.tv_nsec >= 1000000000L) {
            ts.tv_sec++;
            ts.tv_nsec -= 1000000000L;
        }
        pthread_cond_timedwait(&g->cv, &g->mu, &ts);
    }
    return 0;
}

int32_t xrt_task_join(xrt_task *task, xrt_task_result *out) {
    if (task == NULL || out == NULL) {
        rt_fatal("task_join：参数为空（S5 §3.1）");
    }
    struct xrt_task *t = (struct xrt_task *)task;
    struct xrt_task_group *g = (struct xrt_task_group *)t->group;
    pthread_mutex_lock(&g->mu);
    if (t->joined) {
        pthread_mutex_unlock(&g->mu);
        rt_fatal("task_join：重复 join（S5 §3.1 合同错误）");
    }
    (void)wait_done(g, t, 0);
    *out = t->result;
    memset(&t->result, 0, sizeof(t->result));
    t->joined = 1;
    pthread_mutex_unlock(&g->mu);
    return 0;
}

int32_t xrt_task_join_deadline(xrt_task *task, int64_t deadline_mono_ms, xrt_task_result *out) {
    if (task == NULL || out == NULL) {
        rt_fatal("task_join_deadline：参数为空（S5 §3.1）");
    }
    struct xrt_task *t = (struct xrt_task *)task;
    struct xrt_task_group *g = (struct xrt_task_group *)t->group;
    pthread_mutex_lock(&g->mu);
    if (t->joined) {
        pthread_mutex_unlock(&g->mu);
        rt_fatal("task_join_deadline：重复 join（S5 §3.1 合同错误）");
    }
    int rc = wait_done(g, t, deadline_mono_ms == 0 ? 0 : deadline_mono_ms);
    if (rc == XRT_ERR_TIMEOUT) {
        pthread_mutex_unlock(&g->mu);
        return XRT_ERR_TIMEOUT; /* 不消费结果，任务继续 */
    }
    *out = t->result;
    memset(&t->result, 0, sizeof(t->result));
    t->joined = 1;
    pthread_mutex_unlock(&g->mu);
    return 0;
}
