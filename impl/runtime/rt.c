/*
 * rt.c — XNull C 运行时核心实现（M3.1）
 *
 * 终结链时序（S3 §14，强制语义，不得改变）：
 *   release 计数到零 → 置 terminated 标志（此后任何 retain 拒绝、任何 release 不再递减）
 *   → 调用类型描述符 deinit（对象内部引用在此释放）→ 释放分配。
 * 防复活：terminated 置位后 retain 触发 rt_fatal（S3 §15 复活检测，终止进程）。
 */
#include "rt.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static void *rt_alloc(rt_kind kind, const rt_type *type, size_t payload) {
    rt_object *obj = malloc(sizeof(rt_header) + payload);
    if (obj == NULL) {
        abort(); /* OOM：运行期不可恢复（S3 合同：分配失败即 fatal） */
    }
    obj->hdr.kind = kind;
    obj->hdr.type = type;
    atomic_init(&obj->hdr.refcount, 1); /* 新对象计数从 1 起（§7） */
    obj->hdr.terminated = 0;
    return obj;
}

void *rt_payload(void *obj) { return (char *)obj + sizeof(rt_header); }

void *rt_retain(void *obj) {
    if (obj == NULL) {
        return NULL;
    }
    rt_header *h = &((rt_object *)obj)->hdr;
    if (h->terminated) {
        /* 复活检测（S3 §15：deinit 存 self 存入外部状态是程序错误，
         * 运行时检测到复活行为必须终止进程） */
        rt_fatal("复活检测：对已终结对象 retain（S3 §15）");
    }
    atomic_fetch_add_explicit(&h->refcount, 1, memory_order_relaxed);
    return obj;
}

void rt_release(void *obj) {
    if (obj == NULL) {
        return;
    }
    rt_header *h = &((rt_object *)obj)->hdr;
    if (h->terminated) {
        return; /* 双重 release 不递减（§14 防御） */
    }
    if (atomic_fetch_sub_explicit(&h->refcount, 1, memory_order_acq_rel) == 1) {
        /* 到零：终结链（S3 §14 时序） */
        h->terminated = 1;
        rt_weak_clear_slots(obj); /* 终结链第 1 步：清除弱引用（S3 §14.1） */
        rt_scan_unregister(obj); /* 再从 GC 扫描链注销（不变量 6：终结前清除） */
        if (h->type != NULL && h->type->deinit != NULL) {
            h->type->deinit(obj); /* 载荷内引用在此释放 */
        }
        rt_quarantine_push(obj); /* 终结与回收分离（S3 §13）：隔离区暂存，
                                  * 内存保持有效——复活检测（retain 已终结对象）
                                  * 是确定性行为；下次回收会合时统一释放 */
    }
}

int64_t rt_refcount(void *obj) {
    if (obj == NULL) {
        return 0;
    }
    return atomic_load_explicit(&((rt_object *)obj)->hdr.refcount, memory_order_relaxed);
}

/* ---- 字符串 ---- */

static void string_deinit(void *payload) {
    /* rt_string 当前无引用字段；保留钩子位（未来 Text/编码缓存接入）。 */
    (void)payload;
}

const rt_type RT_TYPE_STRING = {
    .name = "String", .payload_size = 0, .deinit = string_deinit,
};

rt_string *rt_string_new(const char *utf8, size_t len) {
    rt_string *s = rt_alloc(RT_KIND_ARC, &RT_TYPE_STRING, sizeof(size_t) + len + 1);
    s->len = len;
    if (len > 0) {
        memcpy(s->bytes, utf8, len);
    }
    s->bytes[len] = '\0';
    return s;
}

rt_string *rt_string_from_c(const char *cstr) {
    return rt_string_new(cstr, strlen(cstr));
}

/* ---- fatal（S3 §14/§15：终结链 panic、复活检测 → 终止进程） ---- */

static rt_fatal_handler g_fatal_handler = NULL;

void rt_set_fatal_handler(rt_fatal_handler h) { g_fatal_handler = h; }

void rt_fatal(const char *reason) {
    if (g_fatal_handler != NULL) {
        g_fatal_handler(reason); /* 宿主处理器（测试/嵌入）；处理器需自行终止 */
    }
    fprintf(stderr, "xnull runtime fatal: %s\n", reason);
    abort();
}

/* ---- 隔离区（S3 §13 回收会合：终结后内存暂存，复活检测确定性） ---- */

static rt_object *g_quarantine = NULL;

void rt_quarantine_push(rt_object *o) {
    o->hdr.gc_next = g_quarantine; /* 复用链字段（对象已终结，不再属于任何清单） */
    g_quarantine = o;
}

size_t rt_quarantine_flush(void) {
    size_t n = 0;
    while (g_quarantine != NULL) {
        rt_object *o = g_quarantine;
        g_quarantine = o->hdr.gc_next;
        free(o);
        n++;
    }
    return n;
}
