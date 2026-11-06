/* test_abi.c — 稳定 ABI 封装层骨架测试（M4.5a）
 *
 * 覆盖：初始化幂等、ARC 分配/计数/终结、双重释放防御、弱表绑定与清除、
 * 写屏障存活校验、全局根登记与 GC 收集、字符串边界访问器。
 */
#include "xrt.h"
#include "rt_gc.h" /* 仅测试使用：rt_gc_live / rt_gc_collect 诊断入口 */

#include <stdio.h>
#include <string.h>

static int g_failures = 0;

#define CHECK(cond)                                                          \
    do {                                                                     \
        if (!(cond)) {                                                       \
            g_failures++;                                                    \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);   \
        }                                                                    \
    } while (0)

typedef struct {
    int64_t v;
} payload_int;

static int g_arc_deinit = 0;
static int g_gc_deinit = 0;
static int g_gc_scan = 0;

static void arc_deinit(void *payload) {
    (void)payload;
    g_arc_deinit++;
}

static void gc_deinit(void *payload) {
    (void)payload;
    g_gc_deinit++;
}

static void gc_scan(void *payload, void (*visit)(void *ref)) {
    (void)payload;
    (void)visit; /* 无引用字段：仅供 GC 标记/清扫遍历 */
    g_gc_scan++;
}

static const xrt_type T_BOX = {"Box", sizeof(payload_int), arc_deinit, NULL};
static const xrt_type T_NODE = {"Node", sizeof(payload_int), gc_deinit, gc_scan};

int main(void) {
    xrt_runtime_init();
    xrt_runtime_init(); /* 幂等 */

    /* ---- ARC：分配与计数 ---- */
    void *a = xrt_alloc(XRT_KIND_ARC, &T_BOX);
    CHECK(a != NULL);
    CHECK(xrt_refcount(a) == 1);
    CHECK(xrt_retain(a) == a);
    CHECK(xrt_refcount(a) == 2);
    xrt_release(a);
    CHECK(xrt_refcount(a) == 1);
    xrt_release(a);
    CHECK(g_arc_deinit == 1);
    /* 双重释放：不重复 deinit（S3 §14 防御） */
    xrt_release(a);
    CHECK(g_arc_deinit == 1);
    xrt_safepoint(); /* 隔离区会合：释放终结对象内存 */

    /* ---- 弱表（S7 §6.2 入口面） ---- */
    void *b = xrt_alloc(XRT_KIND_ARC, &T_BOX);
    xrt_weak_slot *w = xrt_weak_bind(b);
    CHECK(w != NULL);
    CHECK(xrt_weak_read(w) == b);
    xrt_release(b); /* 终结链第 1 步清除弱槽位（S3 §16） */
    CHECK(xrt_weak_read(w) == NULL);
    xrt_weak_clear(w);
    xrt_safepoint();

    /* ---- 写屏障（单线程骨架：存活校验） ---- */
    void *c = xrt_alloc(XRT_KIND_ARC, &T_BOX);
    xrt_write_barrier(c);
    xrt_release(c);
    xrt_safepoint();

    /* ---- 全局根与 GC 收集 ---- */
    void *g = xrt_alloc(XRT_KIND_GC, &T_NODE);
    CHECK(g != NULL);
    CHECK(rt_gc_live() == 1);
    xrt_register_root(g);
    rt_gc_collect();
    CHECK(rt_gc_live() == 1); /* 有根：存活 */
    xrt_unregister_root(g);
    rt_gc_collect();
    CHECK(rt_gc_live() == 0); /* 无根：清扫 */
    CHECK(g_gc_deinit == 1);
    CHECK(g_gc_scan >= 1);
    xrt_safepoint();

    /* ---- 任务根（trampoline env 语义同全局根） ---- */
    void *t = xrt_alloc(XRT_KIND_GC, &T_NODE);
    xrt_task_root_bind(t);
    rt_gc_collect();
    CHECK(rt_gc_live() == 1);
    xrt_task_root_unbind(t);
    rt_gc_collect();
    CHECK(rt_gc_live() == 0);

    /* ---- 字符串边界访问器（长度权威，非 NUL 合同） ---- */
    xrt_string *s = xrt_string_new("hello, XNull", 12);
    CHECK(xrt_string_len(s) == 12);
    CHECK(memcmp(xrt_string_bytes(s), "hello, XNull", 12) == 0);
    xrt_string *s2 = xrt_string_from_c("abc");
    CHECK(xrt_string_len(s2) == 3);
    xrt_release(s);
    xrt_release(s2);
    xrt_safepoint();

    if (g_failures != 0) {
        fprintf(stderr, "abi 测试失败 %d 项\n", g_failures);
        return 1;
    }
    printf("abi 测试通过\n");
    return 0;
}
