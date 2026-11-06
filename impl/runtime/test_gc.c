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
    gnode_t *n = payload;
    n->a = NULL; /* 不变量 6：ARC 释放时清除引用，避免悬挂 */
    n->b = NULL;
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

/* 简单字符串（ARC，无 GC 引用）——清扫释放目标。 */
static rt_string *arc_str(const char *c) { return rt_string_from_c(c); }

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
    rt_string *s = arc_str("held-by-gc");
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

    printf("gc tests passed (invariants 2/3/5/6)\n");
    return 0;
}
