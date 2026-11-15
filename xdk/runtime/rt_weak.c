/* rt_weak.c —— 弱引用表（S3 §16 / S3-06 并发内存收口）
 *
 * 设计：目标对象头挂弱槽位侧链（hdr.weak_head），槽位只存目标指针，不构成强引用
 * （不变量 4：不阻止回收）。目标进入终结链第 1 步前（rt_release 到零 / GC 清扫，
 * 均先于 deinit）由 rt_weak_clear_slots 清除全部槽位。
 *
 * 并发合同：
 *   - create/get/destroy/clear_slots/is_detached 全部在 g_weak_mu 临界区内完成；
 *     槽位字段（target/cleared/next）与目标 weak_head 不再被无锁读写；
 *   - 目标死亡清除与槽位销毁互斥：destroy 不会在 clear_slots 迭代期间释放槽位；
 *   - 槽位销毁进入复用池（不 free），create 优先复用；池操作同受 g_weak_mu 保护；
 *   - rt_weak_get 只保证“临界区内观测到已清除/已终结 → NULL”；返回后目标可能在
 *     下一次安全点死亡，调用方需按弱引用合同使用（不得无同步解引用）。
 */
#include "rt.h"

#include <pthread.h>
#include <stdlib.h>

struct rt_weak_slot {
    rt_object           *target; /* 目标（不持有强引用） */
    struct rt_weak_slot *next;   /* 目标侧链 / 复用池链 */
    int                  cleared;
};

static pthread_mutex_t g_weak_mu = PTHREAD_MUTEX_INITIALIZER;
static rt_weak_slot   *g_free_slots = NULL;
static size_t          g_free_count = 0;

static rt_weak_slot *slot_alloc_locked(void) {
    rt_weak_slot *s = g_free_slots;
    if (s != NULL) {
        g_free_slots = s->next;
        g_free_count--;
    } else {
        s = malloc(sizeof(*s));
        if (s == NULL) {
            abort();
        }
    }
    s->target = NULL;
    s->next = NULL;
    s->cleared = 0;
    return s;
}

static void slot_free_locked(rt_weak_slot *s) {
    s->target = NULL;
    s->cleared = 1;
    s->next = g_free_slots;
    g_free_slots = s;
    g_free_count++;
}

rt_weak_slot *rt_weak_create(void *target) {
    rt_object *o = target;
    if (o == NULL) {
        return NULL;
    }
    pthread_mutex_lock(&g_weak_mu);
    rt_weak_slot *s = slot_alloc_locked();
    s->target = o;
    s->next = o->hdr.weak_head; /* 头插：目标侧链 */
    o->hdr.weak_head = s;
    pthread_mutex_unlock(&g_weak_mu);
    return s;
}

void *rt_weak_get(rt_weak_slot *s) {
    if (s == NULL) {
        return NULL;
    }
    pthread_mutex_lock(&g_weak_mu);
    void *out = NULL;
    if (!s->cleared && s->target != NULL && !s->target->hdr.terminated) {
        out = s->target;
    }
    pthread_mutex_unlock(&g_weak_mu);
    return out; /* 不变量 4：目标死亡即清除；禁止观察已终结目标 */
}

void rt_weak_destroy(rt_weak_slot *s) {
    if (s == NULL) {
        return;
    }
    pthread_mutex_lock(&g_weak_mu);
    /* 仅“存活且未清除”的槽位需要从目标侧链摘除；目标死亡时 clear_slots 已把
     * target 置 NULL，目标内存可能已被隔离区/GC 释放，绝不能再解引用。 */
    if (!s->cleared && s->target != NULL) {
        rt_weak_slot **link = (rt_weak_slot **)&s->target->hdr.weak_head;
        while (*link != NULL) {
            if (*link == s) {
                *link = s->next;
                break;
            }
            link = &(*link)->next;
        }
    }
    slot_free_locked(s); /* 复用池：并发安全，不 free */
    pthread_mutex_unlock(&g_weak_mu);
}

/* 诊断（测试/运行时内部）：清除后槽位必须与目标解绑。 */
int rt_weak_is_detached(const rt_weak_slot *s) {
    if (s == NULL) {
        return 1;
    }
    pthread_mutex_lock(&g_weak_mu);
    int detached = s->target == NULL;
    pthread_mutex_unlock(&g_weak_mu);
    return detached;
}

/* 测试诊断：复用池空闲槽位数。 */
size_t rt_weak_pool_size(void) {
    pthread_mutex_lock(&g_weak_mu);
    size_t n = g_free_count;
    pthread_mutex_unlock(&g_weak_mu);
    return n;
}

/* 清除目标的全部弱槽位（终结链第 1 步；rt.c 与 rt_gc.c 调用）。
 * 与 create/destroy/get 共用 g_weak_mu：destroy 不会在迭代中释放槽位；
 * 清除后 target=NULL，destroy 不再解引用已释放目标（S2 审计 S2-E5-06）。 */
void rt_weak_clear_slots(void *target) {
    rt_object *o = target;
    if (o == NULL) {
        return;
    }
    pthread_mutex_lock(&g_weak_mu);
    for (rt_weak_slot *s = o->hdr.weak_head; s != NULL; s = s->next) {
        s->cleared = 1;
        s->target = NULL;
    }
    o->hdr.weak_head = NULL;
    pthread_mutex_unlock(&g_weak_mu);
}
