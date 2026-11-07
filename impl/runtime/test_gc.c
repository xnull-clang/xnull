/*
 * test_gc.c — M3.3 GC 交互测试：标记—清扫 + 混合引用图不变量（S2 §15.6）
 * 用例：环回收（不变量 5）、ARC 持 GC 引用为根（不变量 2）、
 *       清扫释放 ARC 引用（不变量 3/6）、无重复释放。
 */
#include "rt.h"
#include "rt_gc.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

/* ---- 测试对象：两个 GC 引用字段（可成环） ---- */

typedef struct {
    rt_header hdr;
    void     *a; /* GC 或 ARC 引用 */
    void     *b;
} gnode_t;

static void gnode_scan(void *payload, void (*visit)(void *)) {
    gnode_t *n = payload;
    visit(n->a);
    visit(n->b);
}

static void gnode_deinit(void *payload) {
    /* S2 §6.4：deinit 执行时字段仍然有效；ARC 引用由 sweep 在 deinit 之后
     * 经 scan(sweep_release_arc_ref) 释放。此处不清空字段（清空等于放弃释放）。 */
    (void)payload;
}

static const rt_type RT_TYPE_GNODE = {
    .name = "GNode", .payload_size = sizeof(gnode_t) - sizeof(rt_header),
    .deinit = gnode_deinit, .scan = gnode_scan,
};

/* ARC 扫描对象：持一个 GC 引用（不变量 2）。 */
typedef struct {
    rt_header hdr;
    void     *gc_ref; /* GC 引用（不计数，靠追踪存活） */
} ascan_t;

static void ascan_deinit(void *payload) {
    ascan_t *a = payload;
    a->gc_ref = NULL; /* 不变量 6：终结前清除 GC 引用 */
}

static void ascan_scan(void *payload, void (*visit)(void *)) {
    ascan_t *a = payload;
    visit(a->gc_ref);
}

static const rt_type RT_TYPE_ASCAN = {
    .name = "AScan", .payload_size = sizeof(ascan_t) - sizeof(rt_header),
    .deinit = ascan_deinit, .scan = ascan_scan,
};

/* GC 对象持 ARC 引用：deinit 执行时字段必须仍然有效（S2 §6.4）。 */
typedef struct {
    rt_header hdr;
    void     *arc_ref;
} gcv_t;

static int g_gcv_seen_refcount = -1;

static void gcv_scan(void *payload, void (*visit)(void *)) {
    gcv_t *n = payload;
    visit(n->arc_ref);
}

static void gcv_deinit(void *payload) {
    gcv_t *n = payload;
    g_gcv_seen_refcount = (int)rt_refcount(n->arc_ref);
}

static const rt_type RT_TYPE_GCV = {
    .name = "GcValid", .payload_size = sizeof(gcv_t) - sizeof(rt_header),
    .deinit = gcv_deinit, .scan = gcv_scan,
};

/* 简单 ARC 对象（无 GC 引用）——清扫释放目标。
 * 注意：String 自 S3-04 起是 GC 对象，不能再作为 ARC 引用测试体。 */
typedef struct {
    rt_header hdr;
    int       marker;
} arcbox_t;

static void arcbox_deinit(void *payload) { (void)payload; }

static const rt_type RT_TYPE_ARCBOX = {
    .name = "ArcBox", .payload_size = sizeof(arcbox_t) - sizeof(rt_header),
    .deinit = arcbox_deinit,
};

static arcbox_t *arc_box(void) { return rt_arc_new(&RT_TYPE_ARCBOX); }

/* P0-BND10：死亡 GC 对象之间的字段在 deinit 阶段仍然有效（两阶段清扫）。 */
typedef struct {
    rt_header hdr;
    int       tag;
} gctarget_t;

typedef struct {
    rt_header hdr;
    gctarget_t *ref;
} gcholder_t;

static int g_holder_seen = -1;

static void gctarget_deinit(void *payload) {
    gctarget_t *t = payload;
    t->tag = 77;
}

static const rt_type RT_TYPE_GCTARGET = {
    .name = "GcTarget", .payload_size = sizeof(gctarget_t) - sizeof(rt_header),
    .deinit = gctarget_deinit,
};

static void gcholder_scan(void *payload, void (*visit)(void *)) {
    gcholder_t *h = payload;
    visit(h->ref);
}

static void gcholder_deinit(void *payload) {
    gcholder_t *h = payload;
    g_holder_seen = h->ref->tag;
}

static const rt_type RT_TYPE_GCHOLDER = {
    .name = "GcHolder", .payload_size = sizeof(gcholder_t) - sizeof(rt_header),
    .deinit = gcholder_deinit, .scan = gcholder_scan,
};

int main(void) {
    /* 1. 不变量 5：GC 对象环不可达 → 回收 */
    assert(rt_gc_live() == 0);
    gnode_t *x = rt_gc_new(&RT_TYPE_GNODE);
    gnode_t *y = rt_gc_new(&RT_TYPE_GNODE);
    x->a = y; /* GC 引用：不计数 */
    y->a = x; /* 成环 */
    x->b = NULL;
    y->b = NULL;
    assert(rt_gc_live() == 2);
    /* 环不可达（未登记根）→ 一轮清扫全部回收 */
    size_t freed = rt_gc_collect();
    assert(freed == 2);
    assert(rt_gc_live() == 0);

    /* 2. 不变量 5：环被根持有 → 存活；解除根后回收 */
    gnode_t *p = rt_gc_new(&RT_TYPE_GNODE);
    gnode_t *q = rt_gc_new(&RT_TYPE_GNODE);
    p->a = q;
    q->a = p;
    p->b = NULL;
    q->b = NULL;
    rt_gc_root_add(p);
    rt_gc_collect();
    assert(rt_gc_live() == 2); /* 根可达：环存活 */
    rt_gc_root_remove(p);
    rt_gc_collect();
    assert(rt_gc_live() == 0); /* 环由 GC 回收 */

    /* 3. 不变量 2：ARC 对象持 GC 引用 → ARC 存活期间 GC 引用是根 */
    ascan_t *box = rt_arc_new(&RT_TYPE_ASCAN);
    gnode_t *g = rt_gc_new(&RT_TYPE_GNODE);
    g->a = NULL;
    g->b = NULL;
    box->gc_ref = g; /* GC 引用：不 retain（追踪而非计数，§15.6.1） */
    rt_gc_collect();
    assert(rt_gc_live() == 1); /* box 在扫描链上 → g 存活 */
    /* box 终结：注销扫描链 + 清除 GC 引用（不变量 6）→ g 不可达 */
    rt_release(box);
    rt_gc_collect();
    assert(rt_gc_live() == 0);

    /* 4. 不变量 3/6：GC 对象持 ARC 引用 → 清扫时 release，无泄漏无重复释放 */
    gnode_t *holder = rt_gc_new(&RT_TYPE_GNODE);
    arcbox_t *s = arc_box();
    holder->a = s; /* ARC 引用：持有时必须 retain（成对合同） */
    (void)rt_retain(s);
    holder->b = NULL;
    assert(rt_refcount(s) == 2); /* 局部 + GC 对象 */
    holder = NULL;               /* holder 不可达 */
    rt_gc_collect();             /* holder 死亡 → release(s) */
    assert(rt_refcount(s) == 1); /* 只剩局部；清扫恰好 release 一次 */
    rt_release(s);               /* 局部释放：到零终结 */
    assert(rt_gc_live() == 0);

    /* 5. 混合图：GC 对象经 ARC 扫描对象与根双路可达，标记收敛不重复计数 */
    ascan_t *box2 = rt_arc_new(&RT_TYPE_ASCAN);
    gnode_t *shared = rt_gc_new(&RT_TYPE_GNODE);
    shared->a = NULL;
    shared->b = NULL;
    box2->gc_ref = shared;
    rt_gc_root_add(shared); /* 根 + 扫描链双路可达 */
    rt_gc_collect();
    assert(rt_gc_live() == 1);
    rt_gc_root_remove(shared);
    rt_release(box2);
    rt_gc_collect();
    assert(rt_gc_live() == 0);

    /* 6. S2 §6.4：GC deinit 执行时 ARC 字段仍然有效；释放发生在 deinit 之后 */
    gcv_t *hv = rt_gc_new(&RT_TYPE_GCV);
    arcbox_t *valid = arc_box();
    (void)rt_retain(valid);
    hv->arc_ref = valid;
    assert(rt_refcount(valid) == 2); /* 局部 + GC 对象 */
    hv = NULL;
    rt_gc_collect();
    assert(g_gcv_seen_refcount == 2); /* deinit 时字段仍有效 */
    assert(rt_refcount(valid) == 1);  /* sweep 在 deinit 后恰好 release 一次 */
    rt_release(valid);

    /* 7. P0-BND10：holder 先分配、target 后分配 → LIFO 清扫先释放 target；
     * 两阶段清扫保证 holder deinit 仍能读到 target 字段。 */
    gctarget_t *gt = rt_gc_new(&RT_TYPE_GCTARGET);
    gcholder_t *gh = rt_gc_new(&RT_TYPE_GCHOLDER);
    gh->ref = gt;
    gt->tag = 11;
    gh = NULL;
    gt = NULL;
    rt_gc_collect();
    assert(g_holder_seen == 77);

    printf("gc tests passed (invariants 2/3/5/6)\n");
    return 0;
}
