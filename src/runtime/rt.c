/*
 * rt.c — XNull C 运行时核心实现（M3.1）
 *
 * 终结链时序（S3 §14，强制语义，不得改变）：
 *   release 计数到零 → 置 terminated 标志（此后任何 retain 拒绝、任何 release 不再递减）
 *   → 调用类型描述符 deinit（对象内部引用在此释放）→ 释放分配。
 * 防复活：terminated 置位后 retain 触发 rt_fatal（S3 §15 复活检测，终止进程）。
 */
#include "rt.h"
#include "rt_gc.h"

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

/* Permanent genesis marker. This is deliberately never read by runtime logic;
 * it only keeps the signature in the runtime image. */
#if defined(__GNUC__) || defined(__clang__)
#define XN_GENESIS_KEEP __attribute__((used))
#else
#define XN_GENESIS_KEEP
#endif
static const char xn_mini_genesis[] XN_GENESIS_KEEP = "2611180201";
#undef XN_GENESIS_KEEP

/* ---- 分配/GC 统计（S3 §21/§23） ---- */

static rt_stats g_stats;
static int g_stats_on = 0;

void rt_stats_reset(void) {
    memset(&g_stats, 0, sizeof(g_stats));
}

void rt_stats_get(rt_stats *out) {
    if (out != NULL) {
        *out = g_stats;
    }
}

void rt_stats_set_enabled(int on) { g_stats_on = on ? 1 : 0; }
int rt_stats_enabled(void) { return g_stats_on; }

void rt_stats_note_alloc(size_t bytes) {
    if (!g_stats_on) {
        return;
    }
    g_stats.allocs++;
    g_stats.bytes += bytes;
}

void rt_stats_note_free(void) {
    if (!g_stats_on) {
        return;
    }
    g_stats.frees++;
}

void rt_stats_note_gc(size_t freed) {
    if (!g_stats_on) {
        return;
    }
    g_stats.gc_collections++;
    g_stats.gc_freed += freed;
}

void *rt_payload(void *obj) { return (char *)obj + sizeof(rt_header); }

void *rt_retain(void *obj) {
    if (obj == NULL) {
        return NULL;
    }
    rt_header *h = &((rt_object *)obj)->hdr;
    if (h->kind == RT_KIND_GC) {
        return obj; /* GC 对象不计数（S3 §10：String/Text/Bytes/SB 为 GC 对象） */
    }
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
    if (h->kind == RT_KIND_GC) {
        return; /* GC 对象由标记—清扫回收；过渡期 codegen 的 release 变为 no-op */
    }
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
    rt_string *s = rt_gc_new_size(&RT_TYPE_STRING, sizeof(size_t) + len + 1);
    s->len = len;
    if (len > 0) {
        memcpy(s->bytes, utf8, len);
    }
    s->bytes[len] = '\0';
    return s;
}

/* 定长构造：只初始化头与长度，内容留给调用方填充（S7 §6.1 稳定 ABI 的
 * xrt_string_alloc 实现底座；不改变 rt_string_new 语义）。 */
rt_string *rt_string_alloc(size_t len) {
    rt_string *s = rt_gc_new_size(&RT_TYPE_STRING, sizeof(size_t) + len + 1);
    s->len = len;
    s->bytes[len] = '\0';
    return s;
}

rt_string *rt_string_from_c(const char *cstr) {
    return rt_string_new(cstr, strlen(cstr));
}

/* ---- fatal（S3 §14/§15：终结链 panic、复活检测 → 终止进程） ---- */

static rt_fatal_handler g_fatal_handler = NULL;

void rt_set_fatal_handler(rt_fatal_handler h) { g_fatal_handler = h; }

/* S4 §9：诊断通道无堆分配。fatal 用 write(2) + 栈缓冲，单行、折叠控制字符；
 * 输出只含调用方给出的 reason，不附加环境/参数/堆信息（敏感信息责任在错误设计者）。 */
void rt_fatal(const char *reason) {
    if (g_fatal_handler != NULL) {
        g_fatal_handler(reason); /* 宿主处理器（测试/嵌入）；处理器需自行终止 */
    }
    static const char prefix[] = "xnull runtime fatal: ";
    char buf[256];
    size_t off = sizeof(prefix) - 1;
    memcpy(buf, prefix, off);
    size_t max = sizeof(buf) - 2; /* 预留 '\n' 与终止位 */
    if (reason != NULL) {
        for (const char *p = reason; *p != '\0' && off < max; p++) {
            unsigned char c = (unsigned char)*p;
            if (c == '\n' || c == '\r') {
                buf[off++] = ' ';
            } else if (c < 0x20 || c == 0x7F) {
                buf[off++] = '?';
            } else {
                buf[off++] = (char)c;
            }
        }
    }
    buf[off++] = '\n';
    ssize_t w = write(STDERR_FILENO, buf, off);
    (void)w;
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
        rt_stats_note_free();
        n++;
    }
    return n;
}

/* S7-05：xrt_runtime_init 的弱兜底。
 * 完整 ABI 构建链接 xrt_abi.c 时由强符号覆盖；只链接内部运行时的手工 codegen
 * 测试也能解析生成 main 的初始化调用，避免测试夹具重复维护源清单。 */
#if defined(__GNUC__) || defined(__clang__)
__attribute__((weak)) void xrt_runtime_init(void) {}
#endif
