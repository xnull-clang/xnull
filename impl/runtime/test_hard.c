/*
 * test_hard.c — M3.4 硬语义测试（S3 §14/§15/§16、S2 §15.6 不变量 4）
 * 用例：复活检测终止进程（deinit 存 self）、弱引用终结前清除（时序）、
 *       弱引用不阻止 GC 回收、弱 get 禁止观察已终结目标、槽位复用。
 */
#include "rt.h"
#include "rt_gc.h"

#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>

/* ---- 复活检测：deinit 把 self 存入全局（S3 §15：必须终止进程） ---- */

typedef struct {
    rt_header hdr;
} self_saver_t;

static void *g_saved_self = NULL;

static void self_saver_deinit(void *payload) {
    self_saver_t *o = payload;
    g_saved_self = o; /* 程序错误：deinit 存 self */
}

static const rt_type RT_TYPE_SELF_SAVER = {
    .name = "SelfSaver", .payload_size = sizeof(self_saver_t) - sizeof(rt_header),
    .deinit = self_saver_deinit,
};

/* ---- 弱清除时序：deinit 内读自身弱槽位必须是 NULL（S3 §14.1 先于 deinit） ---- */

typedef struct {
    rt_header     hdr;
    rt_weak_slot *self_weak;
} weak_target_t;

static size_t g_weak_cleared_before_deinit = 0;

static void weak_target_deinit(void *payload) {
    weak_target_t *o = payload;
    if (rt_weak_get(o->self_weak) == NULL) {
        g_weak_cleared_before_deinit++;
    }
}

static const rt_type RT_TYPE_WEAK_TARGET = {
    .name = "WeakTarget", .payload_size = sizeof(weak_target_t) - sizeof(rt_header),
    .deinit = weak_target_deinit,
};

/* ---- GC 对象弱槽：弱槽不是强引用，scan 不访问（不变量 4） ---- */

typedef struct {
    rt_header     hdr;
    rt_weak_slot *w;
} gc_weak_t;

static void gc_weak_scan(void *payload, void (*visit)(void *)) {
    (void)payload;
    (void)visit; /* 弱槽不构成强引用：标记不沿弱槽走 */
}

static size_t g_gc_weak_deinit = 0;

static void gc_weak_deinit(void *payload) {
    gc_weak_t *g = payload;
    if (rt_weak_get(g->w) == NULL) {
        g_gc_weak_deinit++;
    }
    g->w = NULL;
}

static const rt_type RT_TYPE_GC_WEAK = {
    .name = "GcWeak", .payload_size = sizeof(gc_weak_t) - sizeof(rt_header),
    .deinit = gc_weak_deinit, .scan = gc_weak_scan,
};

static jmp_buf      g_fatal_jmp;
static const char  *g_fatal_reason = NULL;

static void test_fatal_handler(const char *reason) {
    g_fatal_reason = reason;
    longjmp(g_fatal_jmp, 1);
}

int main(void) {
    /* 1. 复活检测：终结后 retain → rt_fatal（S3 §15：检测到复活必须终止进程） */
    rt_set_fatal_handler(test_fatal_handler);
    self_saver_t *saver = rt_arc_new(&RT_TYPE_SELF_SAVER);
    if (setjmp(g_fatal_jmp) == 0) {
        rt_release(saver); /* 到零：deinit 把 self 存入全局（错误） */
        assert(g_saved_self != NULL);
        rt_retain(g_saved_self); /* 复活尝试 → 必须 longjmp 回这里 */
        fprintf(stderr, "resurrection was not detected\n");
        assert(0);
    }
    assert(g_fatal_reason != NULL);
    g_saved_self = NULL;
    printf("ok  resurrection detection terminates (fatal handler)\n");

    /* 2. 弱引用时序：建立 → 读取 → 终结（弱清除先于 deinit） */
    weak_target_t *wt = rt_arc_new(&RT_TYPE_WEAK_TARGET);
    wt->self_weak = rt_weak_create(wt);
    assert(rt_weak_get(wt->self_weak) == wt); /* 存活：可读 */
    rt_release(wt); /* 到零：第 1 步清弱槽 → deinit 验证 */
    assert(g_weak_cleared_before_deinit == 1);
    assert(rt_weak_get(wt->self_weak) == NULL); /* 终结后读 → NULL */

    /* 3. 不变量 4：弱引用不阻止 GC 回收；清扫同样先清弱槽 */
    gc_weak_t *g = rt_gc_new(&RT_TYPE_GC_WEAK);
    g->w = rt_weak_create(g);
    assert(rt_weak_get(g->w) == g);
    rt_gc_collect(); /* 无根：清扫回收（弱槽不阻止） */
    assert(rt_gc_live() == 0);
    assert(g_gc_weak_deinit == 1); /* 清扫 deinit 时弱槽已清除 */
    assert(rt_weak_get(g->w) == NULL);

    /* 4. 槽位复用：销毁后目标侧链正确摘除（S3 §16） */
    weak_target_t *w2 = rt_arc_new(&RT_TYPE_WEAK_TARGET);
    rt_weak_slot *s1 = rt_weak_create(w2);
    rt_weak_slot *s2 = rt_weak_create(w2);
    assert(rt_weak_get(s1) == w2 && rt_weak_get(s2) == w2);
    rt_weak_destroy(s1);
    assert(rt_weak_get(s2) == w2); /* 另一槽位不受影响 */
    rt_weak_destroy(s2);
    rt_release(w2); /* 清除空链不崩溃 */
    printf("ok  weak slots (invariant 4, cleared before deinit, reusable)\n");

    printf("hard-semantics tests passed\n");
    return 0;
}
