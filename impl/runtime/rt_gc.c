/* rt_gc.c —— 标记—清扫与混合引用图实现（S3 §5/§8、S2 §15.6，M3.3）。
 *
 * 结构：
 *   - 全 GC 对象清单：侵入式单链（hdr.gc_next），清扫遍历用；
 *   - ARC 扫描链：侵入式单链（hdr.scan_next），不变量 2 的根来源；
 *   - 全局根：动态数组（编译器登记静态/顶层/单例/枚举项槽位）。
 * 单线程骨架（S3 §12 写屏障/安全点在并发子切片接入；当前收集点即安全点）。
 */
#include "rt_gc.h"

#include <stdlib.h>
#include <string.h>

static rt_object *g_gc_list  = NULL; /* 全 GC 对象清单 */
static rt_object *g_scan_list = NULL; /* ARC 扫描链（不变量 2） */
static void     **g_roots    = NULL;
static size_t     g_root_n   = 0;
static size_t     g_root_cap = 0;

/* ---- 分配 ---- */

static void *alloc_common(const rt_type *type, rt_kind kind) {
    rt_object *o = malloc(sizeof(rt_header) + type->payload_size);
    if (o == NULL) {
        return NULL; /* 分配失败是 panic（S2 §2.7） */
    }
    memset(o, 0, sizeof(rt_header) + type->payload_size);
    o->hdr.kind = kind;
    o->hdr.type = type;
    atomic_init(&o->hdr.refcount, 1); /* 计数从 1 起（S3 §7） */
    o->hdr.terminated = 0;
    if (kind == RT_KIND_GC) {
        o->hdr.gc_next = g_gc_list;
        g_gc_list = o;
    } else if (type->scan != NULL) {
        /* 不变量 2：持 GC 引用的 ARC 对象登记为扫描对象 */
        o->hdr.scan_next = g_scan_list;
        g_scan_list = o;
        o->hdr.in_scan_list = 1;
    }
    return o;
}

void *rt_gc_new(const rt_type *type) { return alloc_common(type, RT_KIND_GC); }

void *rt_arc_new(const rt_type *type) { return alloc_common(type, RT_KIND_ARC); }

/* ---- 根集合 ---- */

void rt_gc_root_add(void *obj) {
    rt_object *o = obj;
    if (o == NULL) {
        return;
    }
    for (size_t i = 0; i < g_root_n; i++) { /* 幂等 */
        if (g_roots[i] == o) {
            return;
        }
    }
    if (g_root_n == g_root_cap) {
        g_root_cap = g_root_cap ? g_root_cap * 2 : 16;
        g_roots = realloc(g_roots, g_root_cap * sizeof(void *));
        if (g_roots == NULL) {
            abort();
        }
    }
    g_roots[g_root_n++] = o;
}

void rt_gc_root_remove(void *obj) {
    for (size_t i = 0; i < g_root_n; i++) {
        if (g_roots[i] == obj) {
            g_roots[i] = g_roots[--g_root_n];
            return;
        }
    }
}

/* ---- 标记（S3 §8：根集合出发，引用字段递归） ---- */

static void mark_ref(void *ref) {
    rt_object *o = ref;
    if (o == NULL || o->hdr.terminated) {
        return;
    }
    if (o->hdr.kind == RT_KIND_GC) {
        if (o->hdr.marked) {
            return;
        }
        o->hdr.marked = 1;
    }
    /* ARC 对象：不标记、不阻止其按计数终结（不变量 3 前半：保持可达由
     * 计数承载；GC 只沿其引用字段继续追踪，它若是扫描对象自身即是根）。 */
    if (o->hdr.type->scan != NULL) {
        o->hdr.type->scan(o, mark_ref); /* 钩子约定：完整对象指针（与 deinit 一致） */
    }
}

static void mark_all(void) {
    for (size_t i = 0; i < g_root_n; i++) {
        mark_ref(g_roots[i]);
    }
    /* ARC 扫描链是根（不变量 2：存活期间其 GC 引用当作根） */
    for (rt_object *o = g_scan_list; o != NULL; o = o->hdr.scan_next) {
        mark_ref(o);
    }
}

/* ---- 清扫（不变量 3/6：死亡 GC 对象 release 其 ARC 引用后释放） ---- */

static void sweep_release_arc_ref(void *ref) {
    rt_object *o = ref;
    if (o == NULL || o->hdr.kind != RT_KIND_ARC) {
        return; /* GC 引用随对象一起消亡；只 release ARC 引用 */
    }
    rt_release(o);
}

static size_t sweep(void) {
    size_t freed = 0;
    rt_object **link = &g_gc_list;
    while (*link != NULL) {
        rt_object *o = *link;
        if (o->hdr.marked) {
            o->hdr.marked = 0; /* 复位，供下轮收集 */
            link = &o->hdr.gc_next;
            continue;
        }
        /* 死亡：release 其持有的 ARC 引用（不变量 3 后半），再走 GC 终结
         * （S2 §15.5：GC 对象在清扫时调用 deinit）并释放。 */
        if (o->hdr.type->scan != NULL) {
            o->hdr.type->scan(o, sweep_release_arc_ref);
        }
        o->hdr.terminated = 1; /* 清扫终结：与 ARC 终结链同一防复活标志 */
        rt_weak_clear_slots(o); /* GC 终结同样先清弱槽（S3 §14.1/§15） */
        if (o->hdr.type->deinit != NULL) {
            o->hdr.type->deinit(o);
        }
        *link = o->hdr.gc_next;
        free(o);
        freed++;
    }
    return freed;
}

size_t rt_gc_collect(void) {
    rt_quarantine_flush(); /* 回收会合：上次终结链隔离的内存在此释放（S3 §13） */
    mark_all();
    return sweep();
}

size_t rt_gc_live(void) {
    size_t n = 0;
    for (rt_object *o = g_gc_list; o != NULL; o = o->hdr.gc_next) {
        n++;
    }
    return n;
}

/* ---- ARC 扫描链注销（rt.c 终结链调用；不变量 6） ---- */

void rt_scan_unregister(rt_object *o) {
    if (o == NULL || !o->hdr.in_scan_list) {
        return;
    }
    rt_object **link = &g_scan_list;
    while (*link != NULL) {
        if (*link == o) {
            *link = o->hdr.scan_next;
            o->hdr.scan_next = NULL;
            o->hdr.in_scan_list = 0;
            return;
        }
        link = &(*link)->hdr.scan_next;
    }
    o->hdr.in_scan_list = 0;
}
