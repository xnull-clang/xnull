/* rt_gc.c —— 标记—清扫与混合引用图实现（S3 §5/§8、S2 §15.6，M3.3）。
 *
 * 结构：
 *   - 全 GC 对象清单：侵入式单链（hdr.gc_next），清扫遍历用；
 *   - ARC 扫描链：侵入式单链（hdr.scan_next），不变量 2 的根来源；
 *   - 全局根：动态数组（编译器登记静态/顶层/单例/枚举项槽位）。
 * 单线程骨架（S3 §12 写屏障/安全点在并发子切片接入；当前收集点即安全点）。
 */
#include "rt_gc.h"

#include <pthread.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static rt_object *g_gc_list  = NULL; /* 全 GC 对象清单 */
static rt_object *g_scan_list = NULL; /* ARC 扫描链（不变量 2） */
static void     **g_roots    = NULL;
static size_t     g_root_n   = 0;
static size_t     g_root_cap = 0;
static int        g_collecting = 0;
static uintptr_t  g_gc_min = UINTPTR_MAX;
static uintptr_t  g_gc_max = 0;
static int        g_scan_stack = -1;

/* ---- 分配 ---- */

static void *alloc_sized(const rt_type *type, rt_kind kind, size_t payload) {
    rt_object *o = malloc(sizeof(rt_header) + payload);
    if (o == NULL) {
        return NULL; /* 分配失败是 panic（S2 §2.7） */
    }
    memset(o, 0, sizeof(rt_header) + payload);
    o->hdr.kind = kind;
    o->hdr.type = type;
    atomic_init(&o->hdr.refcount, 1); /* 计数从 1 起（S3 §7） */
    o->hdr.terminated = 0;
    rt_stats_note_alloc(sizeof(rt_header) + payload);
    uintptr_t address = (uintptr_t)o;
    if (address < g_gc_min) { g_gc_min = address; }
    if (address + sizeof(rt_header) + payload > g_gc_max) {
        g_gc_max = address + sizeof(rt_header) + payload;
    }
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

static void *alloc_common(const rt_type *type, rt_kind kind) {
    return alloc_sized(type, kind, type->payload_size);
}

void *rt_gc_new(const rt_type *type) { return alloc_common(type, RT_KIND_GC); }

void *rt_gc_new_size(const rt_type *type, size_t payload) {
    return alloc_sized(type, RT_KIND_GC, payload);
}

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

typedef struct {
    uintptr_t begin;
    uintptr_t end;
    rt_object *object;
} rt_gc_range;

static int range_compare(const void *left, const void *right) {
    const rt_gc_range *a = (const rt_gc_range *)left;
    const rt_gc_range *b = (const rt_gc_range *)right;
    if (a->begin < b->begin) { return -1; }
    if (a->begin > b->begin) { return 1; }
    return 0;
}

static void mark_stack_roots(void) {
    if (g_scan_stack < 0) {
        const char *setting = getenv("XNULL_GC_STACK_SCAN");
        g_scan_stack = (setting != NULL && strcmp(setting, "0") == 0) ? 0 : 1;
#if defined(__APPLE__)
        if (strcmp(getprogname(), "mini") == 0) { g_scan_stack = 0; }
#endif
    }
    if (!g_scan_stack) { return; }
    jmp_buf registers;
    (void)setjmp(registers);
    volatile char marker = 0;
    uintptr_t low = (uintptr_t)&marker;
    uintptr_t high = low;
#if defined(__APPLE__)
    void *top = pthread_get_stackaddr_np(pthread_self());
    size_t size = pthread_get_stacksize_np(pthread_self());
    if (top != NULL && size > 0) {
        uintptr_t stack_top = (uintptr_t)top;
        uintptr_t stack_low = stack_top - size;
        if (low < stack_low) { low = stack_low; }
        high = stack_top;
    }
#elif defined(__linux__)
    pthread_attr_t attr;
    if (pthread_getattr_np(pthread_self(), &attr) == 0) {
        void *base = NULL;
        size_t size = 0;
        if (pthread_attr_getstack(&attr, &base, &size) == 0 && base != NULL && size > 0) {
            uintptr_t stack_low = (uintptr_t)base;
            uintptr_t stack_top = stack_low + size;
            if (low < stack_low) { low = stack_low; }
            high = stack_top;
        }
        pthread_attr_destroy(&attr);
    }
#endif
    if (high <= low) { return; }
    size_t count = 0;
    for (rt_object *o = g_gc_list; o != NULL; o = o->hdr.gc_next) { count++; }
    for (rt_object *o = g_scan_list; o != NULL; o = o->hdr.scan_next) { count++; }
    if (count == 0) { return; }
    rt_gc_range *ranges = (rt_gc_range *)malloc(count * sizeof(rt_gc_range));
    if (ranges == NULL) { return; }
    size_t index = 0;
    for (rt_object *o = g_gc_list; o != NULL; o = o->hdr.gc_next) {
        ranges[index].begin = (uintptr_t)o;
        ranges[index].end = ranges[index].begin + sizeof(rt_header) + o->hdr.type->payload_size;
        ranges[index].object = o;
        index++;
    }
    for (rt_object *o = g_scan_list; o != NULL; o = o->hdr.scan_next) {
        ranges[index].begin = (uintptr_t)o;
        ranges[index].end = ranges[index].begin + sizeof(rt_header) + o->hdr.type->payload_size;
        ranges[index].object = o;
        index++;
    }
    qsort(ranges, count, sizeof(rt_gc_range), range_compare);
    low = (low + sizeof(void *) - 1) & ~(uintptr_t)(sizeof(void *) - 1);
    while (low + sizeof(void *) <= high) {
        uintptr_t candidate = *(uintptr_t *)low;
        if (candidate >= g_gc_min && candidate < g_gc_max) {
            size_t left = 0;
            size_t right = count;
            while (left < right) {
                size_t mid = left + (right - left) / 2;
                if (ranges[mid].begin <= candidate) { left = mid + 1; } else { right = mid; }
            }
            if (left > 0) {
                rt_gc_range *range = &ranges[left - 1];
                if (candidate < range->end) { mark_ref(range->object); }
            }
        }
        low += sizeof(void *);
    }
    free(ranges);
}

static void mark_all(void) {
    for (size_t i = 0; i < g_root_n; i++) {
        mark_ref(g_roots[i]);
    }
    /* ARC 扫描链是根（不变量 2：存活期间其 GC 引用当作根） */
    for (rt_object *o = g_scan_list; o != NULL; o = o->hdr.scan_next) {
        mark_ref(o);
    }
    mark_stack_roots();
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
    /* 两阶段清扫（P0-BND10 / S2 §6.4）：
     *   1) 从存活表摘下死亡对象，逐个 terminated/清弱槽/调 deinit；
     *      此阶段不释放任何死亡对象的内存，deinit 之间的字段互读不会命中已释放内存。
     *   2) 统一 release ARC 引用（scan）并 free。
     */
    rt_object *dead = NULL;
    size_t n = 0;
    rt_object **link = &g_gc_list;
    while (*link != NULL) {
        rt_object *o = *link;
        if (o->hdr.marked) {
            o->hdr.marked = 0;
            link = &o->hdr.gc_next;
            continue;
        }
        *link = o->hdr.gc_next;
        o->hdr.gc_next = dead;
        dead = o;
        n++;
    }
    for (rt_object *o = dead; o != NULL; o = o->hdr.gc_next) {
        o->hdr.terminated = 1;
        rt_weak_clear_slots(o);
        if (o->hdr.type->deinit != NULL) {
            o->hdr.type->deinit(o);
        }
    }
    while (dead != NULL) {
        rt_object *o = dead;
        dead = o->hdr.gc_next;
        if (o->hdr.type->scan != NULL) {
            o->hdr.type->scan(o, sweep_release_arc_ref);
        }
        free(o);
        rt_stats_note_free();
    }
    return n;
}

size_t rt_gc_collect(void) {
    if (g_collecting) { return 0; }
    g_collecting = 1;
    rt_quarantine_flush(); /* 回收会合：上次终结链隔离的内存在此释放（S3 §13） */
    mark_all();
    size_t freed = sweep();
    rt_stats_note_gc(freed);
    g_collecting = 0;
    return freed;
}

size_t xdkc_gc_collect(void) { return rt_gc_collect(); }

size_t rt_gc_collect_shutdown(void) {
    int previous = g_scan_stack;
    g_scan_stack = 0;
    size_t freed = rt_gc_collect();
    g_scan_stack = previous;
    return freed;
}

void rt_gc_set_stack_scan_enabled(int enabled) { g_scan_stack = enabled ? 1 : 0; }

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
