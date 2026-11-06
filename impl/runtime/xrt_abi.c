/* xrt_abi.c — 稳定 ABI 薄封装实现（M4.5a 骨架）
 *
 * 原则：
 *   - 只做转接，不改语义（终结链时序、计数合同、根登记语义全部由 rt_* 承担）；
 *   - 描述符与字符串类型与内部实现同构（见 rt.h），此处以指针转换对接，
 *     不复制结构定义，避免双份布局漂移。
 */
#include "xrt.h"
#include "rt.h"
#include "rt_gc.h"

#include <string.h>

static int g_runtime_inited = 0;

void xrt_runtime_init(void) {
    if (g_runtime_inited) {
        return;
    }
    g_runtime_inited = 1; /* 骨架期无资源需要初始化；顺序约束见 xrt.h 头注释 */
}

void *xrt_alloc(xrt_kind kind, const xrt_type *type) {
    if (type == NULL) {
        rt_fatal("xrt_alloc：类型描述符为空（S7 §6.1）");
    }
    const rt_type *t = (const rt_type *)type;
    if (kind == XRT_KIND_GC) {
        if (t->scan == NULL) {
            /* GC 对象必须有 scan（S3 §8：标记遍历依据） */
            rt_fatal("xrt_alloc：GC 对象缺少 scan 钩子（S3 §8）");
        }
        return rt_gc_new(t);
    }
    return rt_arc_new(t);
}

void *xrt_retain(void *obj) { return rt_retain(obj); }

void xrt_release(void *obj) { rt_release(obj); }

int64_t xrt_refcount(void *obj) { return rt_refcount(obj); }

/* ---- 弱表 ---- */

xrt_weak_slot *xrt_weak_bind(void *target) {
    return (xrt_weak_slot *)rt_weak_create(target);
}

void *xrt_weak_read(xrt_weak_slot *slot) { return rt_weak_get((rt_weak_slot *)slot); }

void xrt_weak_clear(xrt_weak_slot *slot) { rt_weak_destroy((rt_weak_slot *)slot); }

/* ---- 屏障、根、安全点 ---- */

void xrt_write_barrier(void *obj) {
    /* 单线程骨架期：无增量屏障（S3 §12 并发子切片接入）。
     * 仍做存活校验：对已终结对象写入属违约，检测到即终止（S3 §14/§15）。 */
    if (obj != NULL && ((rt_object *)obj)->hdr.terminated) {
        rt_fatal("xrt_write_barrier：写入已终结对象（S3 §15）");
    }
}

void xrt_register_root(void *obj) { rt_gc_root_add(obj); }

void xrt_unregister_root(void *obj) { rt_gc_root_remove(obj); }

void xrt_safepoint(void) {
    /* 回收会合：释放隔离区（终结与回收分离，S3 §13）。
     * 完整收集由分配阈值/显式调用驱动（GC 子切片），此处只做会合。 */
    (void)rt_quarantine_flush();
}

/* ---- 任务根（S7 §5.2） ---- */

void xrt_task_root_bind(void *obj) { rt_gc_root_add(obj); }

void xrt_task_root_unbind(void *obj) { rt_gc_root_remove(obj); }

/* ---- 字符串 ---- */

xrt_string *xrt_string_new(const char *utf8, size_t len) {
    return (xrt_string *)rt_string_new(utf8, len);
}

xrt_string *xrt_string_from_c(const char *cstr) {
    return (xrt_string *)rt_string_from_c(cstr);
}

size_t xrt_string_len(const xrt_string *s) {
    return ((const rt_string *)s)->len;
}

const char *xrt_string_bytes(const xrt_string *s) {
    return ((const rt_string *)s)->bytes;
}
