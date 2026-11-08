/* test_weak.c — S3-06：弱表并发安全/复用池 + 仅安全点收集的写屏障合同 */
#define _POSIX_C_SOURCE 200809L
#define XRT_BINDINGS_LAYER 1
#include "xrt.h"
#include "rt.h"
#include "rt_gc.h"

#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

size_t rt_weak_pool_size(void); /* 测试诊断：复用池空闲槽位数 */

typedef struct { int64_t v; } arc_payload;
static void arc_deinit(void *p) { (void)p; }
static const xrt_type ARC_TYPE = {"WeakArc", sizeof(arc_payload), arc_deinit, NULL};

typedef struct { _Atomic(void *) child; } gc_payload;
static void gc_deinit(void *p) { (void)p; }
static void gc_scan(void *obj, void (*visit)(void *ref)) {
    gc_payload *p = rt_payload(obj);
    void *c = atomic_load(&p->child);
    if (c != NULL) {
        visit(c);
    }
}
static const xrt_type GC_TYPE = {"WeakGC", sizeof(gc_payload), gc_deinit, gc_scan};

static void test_weak_basic(void) {
    void *t = xrt_alloc(XRT_KIND_ARC, &ARC_TYPE);
    assert(t != NULL);
    rt_weak_slot *s = rt_weak_create(t);
    assert(s != NULL && rt_weak_get(s) == t);
    rt_weak_destroy(s);
    assert(rt_weak_pool_size() >= 1); /* 槽位进入复用池 */

    /* 目标死亡：终结链第 1 步清除槽位，之后 get 必须 NULL，destroy 不再触达目标 */
    s = rt_weak_create(t);
    assert(s != NULL);
    xrt_release(t);
    assert(rt_weak_get(s) == NULL);
    assert(rt_weak_is_detached(s) == 1);
    rt_weak_destroy(s);
}

typedef struct {
    void *target;
    int   loops;
} worker_arg;

static void *weak_worker(void *p) {
    worker_arg *a = p;
    for (int i = 0; i < a->loops; i++) {
        rt_weak_slot *s = rt_weak_create(a->target);
        assert(s != NULL);
        assert(rt_weak_get(s) == a->target);
        rt_weak_destroy(s);
    }
    return NULL;
}

static void test_weak_concurrent_pool(void) {
    void *t = xrt_alloc(XRT_KIND_ARC, &ARC_TYPE);
    assert(t != NULL);
    enum { N = 8 };
    pthread_t th[N];
    worker_arg a[N];
    for (int i = 0; i < N; i++) {
        a[i].target = t;
        a[i].loops = 20000;
        assert(pthread_create(&th[i], NULL, weak_worker, &a[i]) == 0);
    }
    for (int i = 0; i < N; i++) {
        assert(pthread_join(th[i], NULL) == 0);
    }
    assert(rt_weak_pool_size() >= 1);
    xrt_release(t);
}

typedef struct {
    rt_weak_slot *slot;
    atomic_int   *start;
} race_arg;

static void *weak_death_reader(void *p) {
    race_arg *a = p;
    while (!atomic_load(a->start)) {
        /* 等待主线程释放目标 */
    }
    void *v = rt_weak_get(a->slot);
    (void)v; /* 可能是目标或 NULL；不得崩溃/触达已释放目标 */
    rt_weak_destroy(a->slot);
    return NULL;
}

static void test_weak_death_race(void) {
    void *t = xrt_alloc(XRT_KIND_ARC, &ARC_TYPE);
    assert(t != NULL);
    enum { N = 8 };
    rt_weak_slot *slots[N];
    pthread_t th[N];
    race_arg args[N];
    atomic_int start = 0;
    for (int i = 0; i < N; i++) {
        slots[i] = rt_weak_create(t);
        assert(slots[i] != NULL);
        args[i].slot = slots[i];
        args[i].start = &start;
        assert(pthread_create(&th[i], NULL, weak_death_reader, &args[i]) == 0);
    }
    atomic_store(&start, 1);
    xrt_release(t); /* 并发清除全部弱槽位 */
    for (int i = 0; i < N; i++) {
        assert(pthread_join(th[i], NULL) == 0);
    }
    assert(rt_weak_pool_size() >= 1);
}

typedef struct {
    void *obj;
    void *child;
    int   loops;
} writer_arg;

static void *barrier_writer(void *p) {
    writer_arg *a = p;
    gc_payload *payload = rt_payload(a->obj);
    for (int i = 0; i < a->loops; i++) {
        atomic_store(&payload->child, a->child);
        xrt_write_barrier(a->obj);
    }
    return NULL;
}

static void test_write_barrier_safepoint_only(void) {
    assert(XRT_WRITE_BARRIER_SAFEPOINT_ONLY == 1);

    void *a = xrt_alloc(XRT_KIND_GC, &GC_TYPE);
    void *b = xrt_alloc(XRT_KIND_GC, &GC_TYPE);
    assert(a != NULL && b != NULL);
    xrt_register_root(a);
    gc_payload *pa = rt_payload(a);
    atomic_store(&pa->child, b);

    rt_weak_slot *wb = rt_weak_create(b);
    assert(wb != NULL);
    xrt_write_barrier(a); /* 仅存活校验；不在写点收集 */
    assert(rt_gc_live() >= 2);

    /* 多线程写同一对象并调用屏障；收集只在主线程安全点/显式 collect。 */
    enum { N = 8, M = 20000 };
    pthread_t th[N];
    writer_arg args[N];
    for (int i = 0; i < N; i++) {
        args[i].obj = a;
        args[i].child = b;
        args[i].loops = M;
        assert(pthread_create(&th[i], NULL, barrier_writer, &args[i]) == 0);
    }
    for (int i = 0; i < N; i++) {
        assert(pthread_join(th[i], NULL) == 0);
    }
    rt_gc_collect();
    assert(rt_weak_get(wb) == b); /* 安全点收集能看见写点引用 */

    xrt_unregister_root(a);
    rt_gc_collect();
    assert(rt_weak_get(wb) == NULL);
    rt_weak_destroy(wb);
}

int main(void) {
    xrt_runtime_init();
    test_weak_basic();
    test_weak_concurrent_pool();
    test_weak_death_race();
    test_write_barrier_safepoint_only();
    printf("weak/barrier tests passed (atomic pool + safepoint-only barrier)\n");
    return 0;
}
