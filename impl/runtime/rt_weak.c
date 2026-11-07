/* rt_weak.c —— 弱引用表（S3 §16，M3.4）。
 *
 * 设计：目标对象头挂弱槽位侧链（hdr.weak_head），槽位只存目标指针，
 * 不构成强引用（不变量 4：不阻止回收）。目标进入终结链第 1 步前
 * （rt_release 到零 / GC 清扫，均先于 deinit）由 rt_weak_clear_slots
 * 清除全部槽位；rt_weak_get 对已清除或已终结目标一律返回 NULL
 * （合同：禁止观察到已终结目标）。单线程骨架；并发清除的原子化在
 * 并发子切片接入（S3 §12），接口已按原子语义设计。
 */
#include "rt.h"

#include <stdlib.h>

struct rt_weak_slot {
    rt_object           *target; /* 目标（不持有强引用） */
    struct rt_weak_slot *next;   /* 目标侧链 */
    int                  cleared;
};

rt_weak_slot *rt_weak_create(void *target) {
    rt_object *o = target;
    if (o == NULL) {
        return NULL;
    }
    rt_weak_slot *s = malloc(sizeof(rt_weak_slot));
    if (s == NULL) {
        abort();
    }
    s->target = o;
    s->cleared = 0;
    s->next = o->hdr.weak_head; /* 头插：目标侧链 */
    o->hdr.weak_head = s;
    return s;
}

void *rt_weak_get(rt_weak_slot *s) {
    if (s == NULL || s->cleared || s->target == NULL) {
        return NULL; /* 不变量 4：目标死亡即清除；禁止观察已终结目标 */
    }
    if (s->target->hdr.terminated) {
        return NULL;
    }
    return s->target;
}

void rt_weak_destroy(rt_weak_slot *s) {
    if (s == NULL) {
        return;
    }
    /* 仅“存活且未清除”的槽位需要从目标侧链摘除（S3 §16）。
     * 目标死亡时 rt_weak_clear_slots 已把 target 置 NULL；此时目标内存可能
     * 已被隔离区/GC 释放，绝不能再解引用（S2 审计 S2-E5-06 的 UAF）。 */
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
    s->cleared = 1;
    s->target = NULL;
    free(s);
}

/* 诊断（测试/运行时内部）：清除后槽位必须与目标解绑，destroy 才能不触达已释放目标。 */
int rt_weak_is_detached(const rt_weak_slot *s) {
    return s == NULL || s->target == NULL;
}

/* 清除目标的全部弱槽位（终结链第 1 步；rt.c 与 rt_gc.c 调用）。
 * 关键：同时把槽位的 target 置 NULL 并清空目标的侧链——目标随后会被隔离区
 * 或 GC 释放，槽位此后不得再解引用目标（S2 审计 S2-E5-06 的 UAF 根因）。 */
void rt_weak_clear_slots(void *target) {
    rt_object *o = target;
    if (o == NULL) {
        return;
    }
    for (rt_weak_slot *s = o->hdr.weak_head; s != NULL; s = s->next) {
        s->cleared = 1;
        s->target = NULL;
    }
    o->hdr.weak_head = NULL;
}
