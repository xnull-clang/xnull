/* rt_sync.c — 同步原语运行时（S5-03；S5-00 接口冻结面）
 *
 * Channel：有界环形缓冲；send/receive 为可取消挂起点（协作式，5ms 轮询上下文取消）；
 *          关闭唤醒挂起者并释放队列剩余元素。
 * Mutex：数据携锁 + 作用域回调（with_lock），回调期间持锁，返回即解锁。
 * Atomic*：顺序一致（seq_cst）；AtomicRef 用 ops 管理引用（retain/release）。
 *
 * 所有权（与 S5-00 §五一致）：
 *   - Channel send 成功消费 +1；CANCELLED/CLOSED 不消费；
 *   - receive 成功取得 +1；close 释放队列剩余（ops.release）；
 *   - Mutex 创建时取得 data +1，deinit 释放；
 *   - AtomicRef new 取得 +1；store/CAS 成功时持有新值 +1、释放旧值。
 */
#include "xrt.h"
#include "rt.h"
#include "rt_gc.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ---- RuntimeMonitor ---- */
/*
 * 执行层内部监视器原语（B3.1）。不是 XDK 公共类型：
 *   - enter/exit 成对持有/释放内部互斥量；
 *   - wait 等待一次通知（可能虚假唤醒，调用方循环重查条件）；
 *   - wait_context 每 5ms 轮询取消位，返回 0 = 已取消，1 = 通知/关闭；
 *   - notify/notifyAll 唤醒等待者；
 *   - close 幂等：标记关闭并唤醒等待者；之后 wait 立即返回，不再阻塞。
 *
 * 生命周期：句柄由进程级分配，close 只改状态、不释放内存，避免关闭与等待者
 * 竞争释放；进程退出时统一回收。monitor 只允许在 enter/exit 之间 wait。
 */
struct xrt_monitor {
    pthread_mutex_t mu;
    pthread_cond_t  cv;
    atomic_int      closed;
};

xrt_monitor *xrt_monitor_new(void) {
    xrt_monitor *m = (xrt_monitor *)calloc(1, sizeof(*m));
    if (m == NULL) {
        rt_fatal("RuntimeMonitor：分配失败（S3 §2）");
    }
    pthread_mutex_init(&m->mu, NULL);
    pthread_cond_init(&m->cv, NULL);
    atomic_init(&m->closed, 0);
    return m;
}

void xrt_monitor_enter(xrt_monitor *m) {
    if (m == NULL) {
        rt_fatal("RuntimeMonitor.enter：监视器为空");
    }
    pthread_mutex_lock(&m->mu);
}

void xrt_monitor_exit(xrt_monitor *m) {
    if (m == NULL) {
        rt_fatal("RuntimeMonitor.exit：监视器为空");
    }
    pthread_mutex_unlock(&m->mu);
}

void xrt_monitor_wait(xrt_monitor *m) {
    if (m == NULL) {
        rt_fatal("RuntimeMonitor.wait：监视器为空");
    }
    if (atomic_load_explicit(&m->closed, memory_order_acquire)) {
        return;
    }
    pthread_cond_wait(&m->cv, &m->mu);
}

int32_t xrt_monitor_wait_context(xrt_monitor *m, xrt_context *ctx) {
    if (m == NULL) {
        rt_fatal("RuntimeMonitor.wait：监视器为空");
    }
    if (atomic_load_explicit(&m->closed, memory_order_acquire)) {
        return 1;
    }
    if (xrt_context_check_cancel(ctx) == XRT_ERR_CANCELLED) {
        return 0;
    }
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_nsec += 5 * 1000 * 1000;
    if (ts.tv_nsec >= 1000000000L) {
        ts.tv_sec++;
        ts.tv_nsec -= 1000000000L;
    }
    /* 超时也返回 1：让调用方重查谓词，避免错过通知后永久等待。 */
    pthread_cond_timedwait(&m->cv, &m->mu, &ts);
    return 1;
}

void xrt_monitor_notify_all(xrt_monitor *m) {
    if (m == NULL) {
        rt_fatal("RuntimeMonitor.notifyAll：监视器为空");
    }
    pthread_cond_broadcast(&m->cv);
}

void xrt_monitor_close(xrt_monitor *m) {
    if (m == NULL) {
        return;
    }
    atomic_store_explicit(&m->closed, 1, memory_order_release);
    pthread_cond_broadcast(&m->cv);
}

int32_t xrt_monitor_closed(const xrt_monitor *m) {
    if (m == NULL) {
        return 1;
    }
    return atomic_load_explicit(&m->closed, memory_order_acquire) ? 1 : 0;
}

/* FFI 投影：句柄以 int64_t 传递，避免生成端需要知道不透明指针类型。 */
int64_t xdkc_monitor_new(void) {
    return (int64_t)(intptr_t)xrt_monitor_new();
}

void xdkc_monitor_enter(int64_t handle) {
    xrt_monitor_enter((xrt_monitor *)(intptr_t)handle);
}

void xdkc_monitor_exit(int64_t handle) {
    xrt_monitor_exit((xrt_monitor *)(intptr_t)handle);
}

void xdkc_monitor_wait(int64_t handle) {
    xrt_monitor_wait((xrt_monitor *)(intptr_t)handle);
}

int32_t xdkc_monitor_wait_context(int64_t handle, void *ctx) {
    return xrt_monitor_wait_context((xrt_monitor *)(intptr_t)handle, (xrt_context *)ctx);
}

void xdkc_monitor_notify_all(int64_t handle) {
    xrt_monitor_notify_all((xrt_monitor *)(intptr_t)handle);
}

void xdkc_monitor_close(int64_t handle) {
    xrt_monitor_close((xrt_monitor *)(intptr_t)handle);
}

int32_t xdkc_monitor_closed(int64_t handle) {
    return xrt_monitor_closed((const xrt_monitor *)(intptr_t)handle);
}

/* ---- Channel ---- */

struct xrt_channel {
    rt_header       hdr;
    pthread_mutex_t mu;
    pthread_cond_t  not_empty;
    pthread_cond_t  not_full;
    size_t          cap;
    size_t          len;
    size_t          head;
    void          **buf;
    int             closed;
    xrt_channel_ops ops;
};

static void channel_release(xrt_channel *ch, void *v) {
    if (ch->ops.release != NULL) {
        ch->ops.release(v);
    }
}

static void channel_deinit(void *obj) {
    xrt_channel *ch = obj;
    if (ch->buf != NULL) {
        for (size_t i = 0; i < ch->len; i++) {
            channel_release(ch, ch->buf[(ch->head + i) % ch->cap]);
        }
        free(ch->buf);
    }
    pthread_cond_destroy(&ch->not_empty);
    pthread_cond_destroy(&ch->not_full);
    pthread_mutex_destroy(&ch->mu);
}

static const rt_type RT_TYPE_XRT_CHANNEL = {
    "xrt_channel", sizeof(struct xrt_channel) - sizeof(rt_header), channel_deinit, NULL
};

/* 5ms 轮询等待：用于协作式取消（无外部 signal 时也能及时发现取消）。 */
static void wait_tick(pthread_cond_t *cv, pthread_mutex_t *mu) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_nsec += 5 * 1000 * 1000;
    if (ts.tv_nsec >= 1000000000L) {
        ts.tv_sec++;
        ts.tv_nsec -= 1000000000L;
    }
    pthread_cond_timedwait(cv, mu, &ts);
}

xrt_channel *xrt_channel_new(size_t capacity, const xrt_channel_ops *ops) {
    if (capacity == 0) {
        rt_fatal("channel_new：容量必须 > 0（S5 §7.1）");
    }
    rt_object *o = rt_arc_new(&RT_TYPE_XRT_CHANNEL);
    xrt_channel *ch = (xrt_channel *)o;
    ch->cap = capacity;
    ch->len = 0;
    ch->head = 0;
    ch->buf = calloc(capacity, sizeof(void *));
    if (ch->buf == NULL) {
        rt_fatal("channel_new：缓冲区分配失败（S3 §2）");
    }
    ch->closed = 0;
    if (ops != NULL) {
        ch->ops = *ops;
    } else {
        ch->ops.retain = NULL;
        ch->ops.release = NULL;
    }
    pthread_mutex_init(&ch->mu, NULL);
    pthread_cond_init(&ch->not_empty, NULL);
    pthread_cond_init(&ch->not_full, NULL);
    return ch;
}

int32_t xrt_channel_send(xrt_channel *ch, void *value, xrt_context *ctx) {
    if (ch == NULL) {
        rt_fatal("channel_send：通道为空（S5 §7.1）");
    }
    pthread_mutex_lock(&ch->mu);
    for (;;) {
        if (ch->closed) {
            pthread_mutex_unlock(&ch->mu);
            return XRT_STATUS_CLOSED;
        }
        if (ch->len < ch->cap) {
            ch->buf[(ch->head + ch->len) % ch->cap] = value;
            ch->len++;
            pthread_cond_signal(&ch->not_empty);
            pthread_mutex_unlock(&ch->mu);
            return 0; /* 消费 +1 */
        }
        if (xrt_context_check_cancel(ctx) == XRT_ERR_CANCELLED) {
            pthread_mutex_unlock(&ch->mu);
            return XRT_ERR_CANCELLED;
        }
        wait_tick(&ch->not_full, &ch->mu);
    }
}

int32_t xrt_channel_receive(xrt_channel *ch, void **value, xrt_context *ctx) {
    if (ch == NULL || value == NULL) {
        rt_fatal("channel_receive：参数为空（S5 §7.1）");
    }
    pthread_mutex_lock(&ch->mu);
    for (;;) {
        if (ch->len > 0) {
            void *v = ch->buf[ch->head];
            ch->head = (ch->head + 1) % ch->cap;
            ch->len--;
            pthread_cond_signal(&ch->not_full);
            pthread_mutex_unlock(&ch->mu);
            *value = v; /* 取得 +1 */
            return 0;
        }
        if (ch->closed) {
            pthread_mutex_unlock(&ch->mu);
            return XRT_STATUS_CLOSED;
        }
        if (xrt_context_check_cancel(ctx) == XRT_ERR_CANCELLED) {
            pthread_mutex_unlock(&ch->mu);
            return XRT_ERR_CANCELLED;
        }
        wait_tick(&ch->not_empty, &ch->mu);
    }
}

void xrt_channel_close(xrt_channel *ch) {
    if (ch == NULL) {
        return;
    }
    pthread_mutex_lock(&ch->mu);
    if (ch->closed) {
        pthread_mutex_unlock(&ch->mu);
        return;
    }
    ch->closed = 1;
    while (ch->len > 0) {
        void *v = ch->buf[ch->head];
        ch->head = (ch->head + 1) % ch->cap;
        ch->len--;
        channel_release(ch, v);
    }
    pthread_cond_broadcast(&ch->not_empty);
    pthread_cond_broadcast(&ch->not_full);
    pthread_mutex_unlock(&ch->mu);
}

/* ---- Mutex ---- */

struct xrt_mutex {
    rt_header       hdr;
    pthread_mutex_t mu;
    void           *data;
    xrt_channel_ops ops;
};

static void mutex_deinit(void *obj) {
    xrt_mutex *m = obj;
    if (m->ops.release != NULL && m->data != NULL) {
        m->ops.release(m->data);
    }
    pthread_mutex_destroy(&m->mu);
}

static const rt_type RT_TYPE_XRT_MUTEX = {
    "xrt_mutex", sizeof(struct xrt_mutex) - sizeof(rt_header), mutex_deinit, NULL
};

xrt_mutex *xrt_mutex_new(void *data, const xrt_channel_ops *ops) {
    rt_object *o = rt_arc_new(&RT_TYPE_XRT_MUTEX);
    xrt_mutex *m = (xrt_mutex *)o;
    m->data = data;
    if (ops != NULL) {
        m->ops = *ops;
    } else {
        m->ops.retain = NULL;
        m->ops.release = NULL;
    }
    if (m->ops.retain != NULL && data != NULL) {
        m->ops.retain(data);
    }
    pthread_mutex_init(&m->mu, NULL);
    return m;
}

int32_t xrt_mutex_with_lock(xrt_mutex *m, xrt_with_lock_body body, void *env, xrt_context *ctx) {
    if (m == NULL || body == NULL) {
        rt_fatal("mutex_with_lock：参数为空（S5 §7.2）");
    }
    pthread_mutex_lock(&m->mu);
    int32_t rc = body(m->data, env, ctx);
    pthread_mutex_unlock(&m->mu);
    return rc;
}

/* ---- AtomicInt / AtomicBool / AtomicRef ---- */

struct xrt_atomic_int {
    rt_header hdr;
    atomic_llong v;
};

struct xrt_atomic_bool {
    rt_header hdr;
    atomic_int v;
};

struct xrt_atomic_ref {
    rt_header hdr;
    _Atomic(void *) v;
    xrt_channel_ops ops;
};

static const rt_type RT_TYPE_XRT_ATOMIC_INT = { "xrt_atomic_int", sizeof(struct xrt_atomic_int) - sizeof(rt_header), NULL, NULL };
static const rt_type RT_TYPE_XRT_ATOMIC_BOOL = { "xrt_atomic_bool", sizeof(struct xrt_atomic_bool) - sizeof(rt_header), NULL, NULL };

static void atomic_ref_deinit(void *obj) {
    xrt_atomic_ref *a = obj;
    void *v = atomic_load(&a->v);
    if (a->ops.release != NULL && v != NULL) {
        a->ops.release(v);
    }
}

static const rt_type RT_TYPE_XRT_ATOMIC_REF = { "xrt_atomic_ref", sizeof(struct xrt_atomic_ref) - sizeof(rt_header), atomic_ref_deinit, NULL };

xrt_atomic_int *xrt_atomic_int_new(int64_t v) {
    xrt_atomic_int *a = (xrt_atomic_int *)rt_arc_new(&RT_TYPE_XRT_ATOMIC_INT);
    atomic_init(&a->v, (long long)v);
    return a;
}
int64_t xrt_atomic_int_load(const xrt_atomic_int *a) { return (int64_t)atomic_load(&((xrt_atomic_int *)a)->v); }
void xrt_atomic_int_store(xrt_atomic_int *a, int64_t v) { atomic_store(&a->v, (long long)v); }
int32_t xrt_atomic_int_cas(xrt_atomic_int *a, int64_t expect, int64_t desired) {
    long long e = (long long)expect;
    return atomic_compare_exchange_strong(&a->v, &e, (long long)desired) ? 1 : 0;
}

xrt_atomic_bool *xrt_atomic_bool_new(int v) {
    xrt_atomic_bool *a = (xrt_atomic_bool *)rt_arc_new(&RT_TYPE_XRT_ATOMIC_BOOL);
    atomic_init(&a->v, v ? 1 : 0);
    return a;
}
int32_t xrt_atomic_bool_load(const xrt_atomic_bool *a) { return atomic_load(&((xrt_atomic_bool *)a)->v) ? 1 : 0; }
void xrt_atomic_bool_store(xrt_atomic_bool *a, int v) { atomic_store(&a->v, v ? 1 : 0); }
int32_t xrt_atomic_bool_cas(xrt_atomic_bool *a, int expect, int desired) {
    int e = expect ? 1 : 0;
    return atomic_compare_exchange_strong(&a->v, &e, desired ? 1 : 0) ? 1 : 0;
}

xrt_atomic_ref *xrt_atomic_ref_new(void *v, const xrt_channel_ops *ops) {
    xrt_atomic_ref *a = (xrt_atomic_ref *)rt_arc_new(&RT_TYPE_XRT_ATOMIC_REF);
    if (ops != NULL) {
        a->ops = *ops;
    } else {
        a->ops.retain = NULL;
        a->ops.release = NULL;
    }
    atomic_init(&a->v, v);
    if (a->ops.retain != NULL && v != NULL) {
        a->ops.retain(v);
    }
    return a;
}

xrt_atomic_ref *xdkc_atomic_ref_new(void *v) {
    static const xrt_channel_ops ops = { rt_retain, rt_release };
    return xrt_atomic_ref_new(v, &ops);
}

void *xrt_atomic_ref_load(const xrt_atomic_ref *a) {
    return atomic_load(&((xrt_atomic_ref *)a)->v);
}

void xrt_atomic_ref_store(xrt_atomic_ref *a, void *v) {
    if (a->ops.retain != NULL && v != NULL) {
        a->ops.retain(v);
    }
    void *old = atomic_exchange(&a->v, v);
    if (a->ops.release != NULL && old != NULL) {
        a->ops.release(old);
    }
}

int32_t xrt_atomic_ref_cas(xrt_atomic_ref *a, void *expect, void *desired) {
    if (a->ops.retain != NULL && desired != NULL) {
        a->ops.retain(desired);
    }
    void *e = expect;
    if (atomic_compare_exchange_strong(&a->v, &e, desired)) {
        if (a->ops.release != NULL && e != NULL) {
            a->ops.release(e);
        }
        return 1;
    }
    if (a->ops.release != NULL && desired != NULL) {
        a->ops.release(desired);
    }
    return 0;
}
