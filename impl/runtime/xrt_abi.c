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

#include <stdio.h>
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

xrt_string *xrt_string_alloc(size_t len) {
    return (xrt_string *)rt_string_alloc(len);
}

const xrt_type *xrt_type_string_descriptor(void) {
    return (const xrt_type *)&RT_TYPE_STRING;
}

const char *xrt_string_bytes(const xrt_string *s) {
    return ((const rt_string *)s)->bytes;
}

/* ---- 句柄（S7 §4.3）：ARC 包装 + 显式幂等关闭 ---- */

typedef struct {
    void  *native;
    void (*close_fn)(void *native);
    int    closed;
} handle_payload;

static void handle_deinit(void *payload) {
    /* deinit/scan 钩子收到的是完整对象指针（rt.h rt_type 约定），不是载荷起点：
     * 必须先取 rt_payload，否则会把分配头当 handle_payload 读（B0-07c 假泄漏）。 */
    handle_payload *p = rt_payload(payload);
    if (p->native != NULL && !p->closed) {
        /* 不以 deinit 作唯一关闭路径（S7 §4.3）：只把泄漏暴露到诊断通道 */
        fprintf(stderr, "xrt: 句柄泄漏：未显式 close（S7 §4.3）\n");
    }
}

static const rt_type RT_TYPE_XRT_HANDLE = {
    "xrt_handle", sizeof(handle_payload), handle_deinit, NULL
};

xrt_handle *xrt_handle_new(void *native, void (*close_fn)(void *native), const char *what) {
    (void)what; /* 诊断归属保留位（S7 §4.3；M4.5c 接入任务根后使用） */
    rt_object *o = rt_arc_new(&RT_TYPE_XRT_HANDLE);
    handle_payload *p = rt_payload(o);
    p->native = native;
    p->close_fn = close_fn;
    p->closed = (native == NULL);
    return (xrt_handle *)o;
}

static handle_payload *handle_of(xrt_handle *h) {
    return h == NULL ? NULL : rt_payload((rt_object *)h);
}

void *xrt_handle_native(xrt_handle *h) {
    handle_payload *p = handle_of(h);
    if (p == NULL || p->closed || p->native == NULL) {
        return NULL;
    }
    return p->native;
}

int xrt_handle_close(xrt_handle *h) {
    handle_payload *p = handle_of(h);
    if (p == NULL) {
        return 0;
    }
    if (p->closed || p->native == NULL) {
        p->closed = 1;
        p->native = NULL;
        return 0; /* 幂等：重复关闭不再触达原生（S7 §4.3 / INV-FFI-9） */
    }
    if (p->close_fn != NULL) {
        p->close_fn(p->native);
    }
    p->closed = 1;
    p->native = NULL;
    return 0;
}

void xrt_handle_mark_closed(xrt_handle *h) {
    handle_payload *p = handle_of(h);
    if (p == NULL) {
        return;
    }
    /* 原生侧已完成关闭（绑定 close 入口调用成功）：只登记状态，不重复触达 */
    p->closed = 1;
    p->native = NULL;
}

int xrt_handle_is_closed(const xrt_handle *h) {
    const handle_payload *p = h == NULL ? NULL : (const void *)((const char *)h + sizeof(rt_header));
    return p == NULL ? 1 : p->closed;
}

void xrt_fatal(const char *reason) { rt_fatal(reason); }

/* ---- ErrorKind 稳定枚举（S4 §3/§7.3） ---- */

static const char *const g_error_kind_names[] = {
    "InvalidArgument", "NotFound", "AlreadyExists", "PermissionDenied",
    "Io", "Network", "Timeout", "Cancelled", "Busy", "Unavailable",
    "DataCorrupted", "Unsupported", "OutOfMemory", "Internal",
};

const char *xrt_error_kind_name(xrt_error_kind kind) {
    if ((int)kind < 0 || (size_t)kind >= sizeof(g_error_kind_names) / sizeof(g_error_kind_names[0])) {
        return "Internal";
    }
    return g_error_kind_names[kind];
}

xrt_error_kind xrt_error_kind_parse(const char *name) {
    if (name == NULL) {
        return XRT_ERR_INTERNAL;
    }
    /* 绑定层 errorMap 的短名（S4 附录 A 映射） */
    if (strcmp(name, "Invalid") == 0) return XRT_ERR_INVALID_ARGUMENT;
    if (strcmp(name, "NotFound") == 0) return XRT_ERR_NOT_FOUND;
    if (strcmp(name, "Conflict") == 0) return XRT_ERR_ALREADY_EXISTS;
    if (strcmp(name, "Permission") == 0) return XRT_ERR_PERMISSION_DENIED;
    if (strcmp(name, "Limit") == 0) return XRT_ERR_BUSY;
    if (strcmp(name, "Cancelled") == 0) return XRT_ERR_CANCELLED;
    if (strcmp(name, "Timeout") == 0) return XRT_ERR_TIMEOUT;
    if (strcmp(name, "Unavailable") == 0) return XRT_ERR_UNAVAILABLE;
    if (strcmp(name, "Internal") == 0) return XRT_ERR_INTERNAL;
    /* 全名（附录 A） */
    for (size_t i = 0; i < sizeof(g_error_kind_names) / sizeof(g_error_kind_names[0]); i++) {
        if (strcmp(name, g_error_kind_names[i]) == 0) {
            return (xrt_error_kind)i;
        }
    }
    return XRT_ERR_INTERNAL;
}

/* ---- 分配统计与 GC 指标（S3 §21/§23） ---- */

void xrt_stats_reset(void) { rt_stats_reset(); }

void xrt_stats_get(xrt_stats *out) {
    if (out == NULL) {
        return;
    }
    rt_stats s;
    rt_stats_get(&s);
    out->allocs = s.allocs;
    out->frees = s.frees;
    out->bytes = s.bytes;
    out->gc_collections = s.gc_collections;
    out->gc_freed = s.gc_freed;
}

void xrt_stats_set_enabled(int on) { rt_stats_set_enabled(on); }
int xrt_stats_enabled(void) { return rt_stats_enabled(); }

void xrt_stats_report(void) {
    xrt_stats s;
    xrt_stats_get(&s);
    fprintf(stderr, "xrt stats: allocs=%llu frees=%llu live=%lld bytes=%llu gc_collections=%llu gc_freed=%llu\n",
            (unsigned long long)s.allocs, (unsigned long long)s.frees,
            (long long)(s.allocs - s.frees), (unsigned long long)s.bytes,
            (unsigned long long)s.gc_collections, (unsigned long long)s.gc_freed);
}

/* ---- 回调环境 / trampoline（S7 §5.1/§5.2） ---- */

typedef struct {
    void            *closure;
    xrt_callback_fn  fn;
    int              destroyed;
} callback_payload;

static void callback_scan(void *obj, void (*visit)(void *)) {
    (void)obj;
    (void)visit; /* 闭包引用由绑定层管理；env 只承载生命周期与根登记 */
}

static const rt_type RT_TYPE_CALLBACK_ENV = {
    "xrt_callback_env", sizeof(callback_payload), NULL, callback_scan
};

static callback_payload *callback_of(xrt_callback_env *env) {
    return env == NULL ? NULL : rt_payload((rt_object *)env);
}

xrt_callback_env *xrt_callback_env_new(void *closure, xrt_callback_fn fn) {
    rt_object *o = rt_gc_new(&RT_TYPE_CALLBACK_ENV);
    callback_payload *p = rt_payload(o);
    p->closure = closure;
    p->fn = fn;
    p->destroyed = 0;
    rt_gc_root_add(o); /* S7 §5.2：env 在存活期间是运行时根 */
    return (xrt_callback_env *)o;
}

int32_t xrt_callback_env_invoke(xrt_callback_env *env, const void *args, size_t nargs, void *result) {
    callback_payload *p = callback_of(env);
    if (p == NULL || p->destroyed) {
        rt_fatal("trampoline：已注销的 env 被调用（S7 §5.2 合同违规）");
    }
    if (p->fn == NULL) {
        rt_fatal("trampoline：env 缺少回调目标（S7 §5.1）");
    }
    return p->fn(p->closure, args, nargs, result);
}

void xrt_callback_env_destroy(xrt_callback_env *env) {
    callback_payload *p = callback_of(env);
    if (p == NULL || p->destroyed) {
        return; /* 幂等 */
    }
    p->destroyed = 1;
    rt_gc_root_remove(env); /* S7 §5.2：销毁即注销根 */
}

int xrt_callback_env_alive(const xrt_callback_env *env) {
    const callback_payload *p = env == NULL ? NULL : (const void *)((const char *)env + sizeof(rt_header));
    return p != NULL && !p->destroyed;
}

void *xrt_callback_env_closure(const xrt_callback_env *env) {
    const callback_payload *p = env == NULL ? NULL : (const void *)((const char *)env + sizeof(rt_header));
    return p == NULL ? NULL : p->closure;
}
