/* test_sync.c — S5-03 同步原语合同测试（Channel/Mutex/Atomic*） */
#include "xrt.h"
#include "rt.h"
#include "rt_gc.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* ---- 通道任务体 ---- */

static int32_t body_recv(void *env, xrt_context *ctx, xrt_task_result *out) {
    void *v = NULL;
    int rc = xrt_channel_receive((xrt_channel *)env, &v, ctx);
    if (rc == XRT_ERR_CANCELLED) {
        out->ok = 0;
        out->kind = XRT_ERR_CANCELLED;
        return 0;
    }
    if (rc != 0) {
        out->ok = 1;
        out->value = (void *)(intptr_t)rc; /* CLOSED 终态 */
        return 0;
    }
    out->ok = 1;
    out->value = v;
    return 0;
}

typedef struct {
    xrt_channel *req;
    xrt_channel *resp;
} exchange_env;

static int32_t body_exchange(void *env, xrt_context *ctx, xrt_task_result *out) {
    exchange_env *e = (exchange_env *)env;
    void *v = NULL;
    int rc = xrt_channel_receive(e->req, &v, ctx);
    if (rc != 0 || (intptr_t)v != 7) {
        out->ok = 0;
        out->kind = rc != 0 ? XRT_ERR_CANCELLED : XRT_ERR_INTERNAL;
        return 0;
    }
    rc = xrt_channel_send(e->resp, (void *)(intptr_t)8, ctx);
    out->ok = (rc == 0) ? 1 : 0;
    out->value = (void *)(intptr_t)rc;
    return 0;
}

/* ---- ARC 测试对象（ops 计数） ---- */

typedef struct {
    rt_header hdr;
    int       value;
} box_t;

static int g_box_deinit = 0;

static void box_deinit(void *obj) {
    (void)obj;
    g_box_deinit++;
}
static const rt_type RT_TYPE_BOX = {
    "SyncBox", sizeof(box_t) - sizeof(rt_header), box_deinit, NULL
};
static box_t *box_new(int v) {
    box_t *b = (box_t *)rt_arc_new(&RT_TYPE_BOX);
    b->value = v;
    return b;
}

/* ---- 测试 ---- */

static void test_atomics(void) {
    xrt_atomic_int *ai = xrt_atomic_int_new(1);
    assert(xrt_atomic_int_load(ai) == 1);
    xrt_atomic_int_store(ai, 5);
    assert(xrt_atomic_int_load(ai) == 5);
    assert(xrt_atomic_int_cas(ai, 5, 9) == 1);
    assert(xrt_atomic_int_load(ai) == 9);
    assert(xrt_atomic_int_cas(ai, 5, 1) == 0);
    xrt_release(ai);

    xrt_atomic_bool *ab = xrt_atomic_bool_new(0);
    assert(xrt_atomic_bool_load(ab) == 0);
    xrt_atomic_bool_store(ab, 1);
    assert(xrt_atomic_bool_load(ab) == 1);
    assert(xrt_atomic_bool_cas(ab, 1, 0) == 1);
    assert(xrt_atomic_bool_load(ab) == 0);
    xrt_release(ab);

    g_box_deinit = 0;
    box_t *a = box_new(1);
    box_t *b = box_new(2);
    box_t *c = box_new(3);
    xrt_channel_ops ops = { rt_retain, rt_release };
    xrt_atomic_ref *ar = xrt_atomic_ref_new(a, &ops); /* a 2 */
    assert(rt_refcount(a) == 2);
    assert(xrt_atomic_ref_load(ar) == a);
    xrt_atomic_ref_store(ar, b); /* b 2, a 1 */
    assert(rt_refcount(a) == 1 && rt_refcount(b) == 2);
    assert(xrt_atomic_ref_load(ar) == b);
    assert(xrt_atomic_ref_cas(ar, b, c) == 1); /* c 2, b 1 */
    assert(xrt_atomic_ref_load(ar) == c);
    assert(xrt_atomic_ref_cas(ar, b, a) == 0);
    xrt_release(ar); /* c 1 */
    xrt_release(a);
    xrt_release(b);
    xrt_release(c);
    assert(g_box_deinit == 3);
}

static void test_channel_basic(void) {
    xrt_channel *ch = xrt_channel_new(2, NULL);
    assert(xrt_channel_send(ch, (void *)(intptr_t)1, NULL) == 0);
    assert(xrt_channel_send(ch, (void *)(intptr_t)2, NULL) == 0);
    void *v = NULL;
    assert(xrt_channel_receive(ch, &v, NULL) == 0 && (intptr_t)v == 1);
    assert(xrt_channel_receive(ch, &v, NULL) == 0 && (intptr_t)v == 2);
    xrt_channel_close(ch);
    assert(xrt_channel_receive(ch, &v, NULL) == XRT_STATUS_CLOSED);
    assert(xrt_channel_send(ch, (void *)(intptr_t)3, NULL) == XRT_STATUS_CLOSED);
    xrt_channel_close(ch); /* 幂等 */
    xrt_release(ch);

    /* 队列剩余元素在 close 时释放（ops.release） */
    g_box_deinit = 0;
    box_t *b = box_new(7);
    xrt_channel_ops ops = { rt_retain, rt_release };
    xrt_channel *c2 = xrt_channel_new(2, &ops);
    assert(xrt_refcount(b) == 1);
    assert(xrt_channel_send(c2, b, NULL) == 0); /* 消费 +1 */
    xrt_channel_close(c2);                      /* 未取走 → release */
    assert(g_box_deinit == 1);
    xrt_release(c2);
}

static void test_channel_cancel_and_close_wake(void) {
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    xrt_channel *ch = xrt_channel_new(1, NULL);
    xrt_task *t = NULL;
    assert(xrt_task_group_spawn(g, body_recv, ch, &t) == 0);
    struct timespec d = {0, 20000000};
    nanosleep(&d, NULL);
    xrt_task_result r;
    assert(xrt_task_group_close(g, NULL) == 0); /* 取消阻塞中的 receive */
    assert(xrt_task_join(t, &r) == 0);
    assert(r.ok == 0 && r.kind == XRT_ERR_CANCELLED);
    xrt_release(t);
    xrt_release(g);
    xrt_release(ctx);
    xrt_channel_close(ch);
    xrt_release(ch);

    /* close 唤醒阻塞 receive → CLOSED 终态 */
    ctx = xrt_context_background();
    g = xrt_task_group_new(ctx);
    ch = xrt_channel_new(1, NULL);
    t = NULL;
    assert(xrt_task_group_spawn(g, body_recv, ch, &t) == 0);
    nanosleep(&d, NULL);
    xrt_channel_close(ch);
    assert(xrt_task_join(t, &r) == 0);
    assert(r.ok == 1 && (intptr_t)r.value == XRT_STATUS_CLOSED);
    xrt_release(t);
    xrt_task_result fe;
    assert(xrt_task_group_close(g, &fe) == 0);
    xrt_release(g);
    xrt_release(ctx);
    xrt_release(ch);
}

static void test_channel_task_exchange(void) {
    xrt_context *ctx = xrt_context_background();
    xrt_task_group *g = xrt_task_group_new(ctx);
    xrt_channel *req = xrt_channel_new(1, NULL);
    xrt_channel *resp = xrt_channel_new(1, NULL);
    exchange_env env = { req, resp };
    xrt_task *t = NULL;
    assert(xrt_task_group_spawn(g, body_exchange, &env, &t) == 0);
    assert(xrt_channel_send(req, (void *)(intptr_t)7, NULL) == 0);
    void *v = NULL;
    assert(xrt_channel_receive(resp, &v, NULL) == 0);
    assert((intptr_t)v == 8);
    xrt_task_result r;
    assert(xrt_task_join(t, &r) == 0 && r.ok == 1);
    xrt_release(t);
    xrt_task_result fe;
    assert(xrt_task_group_close(g, &fe) == 0);
    xrt_release(g);
    xrt_release(ctx);
    xrt_channel_close(req);
    xrt_channel_close(resp);
    xrt_release(req);
    xrt_release(resp);
}

static int32_t body_lock(void *data, void *env, xrt_context *ctx) {
    (void)ctx;
    box_t *b = data;
    int *hits = env;
    b->value += 1;
    *hits += 1;
    return 0;
}

static void test_mutex(void) {
    g_box_deinit = 0;
    box_t *b = box_new(5);
    xrt_channel_ops ops = { rt_retain, rt_release };
    xrt_mutex *m = xrt_mutex_new(b, &ops); /* b 2 */
    assert(rt_refcount(b) == 2);
    int hits = 0;
    assert(xrt_mutex_with_lock(m, body_lock, &hits, NULL) == 0);
    assert(hits == 1 && b->value == 6);
    xrt_release(m); /* 释放 data：b 1 */
    assert(rt_refcount(b) == 1);
    xrt_release(b);
    assert(g_box_deinit == 1);
}

int main(void) {
    test_atomics();
    test_channel_basic();
    test_channel_cancel_and_close_wake();
    test_channel_task_exchange();
    test_mutex();
    printf("sync tests passed (channel/mutex/atomic/cancel)\n");
    return 0;
}
