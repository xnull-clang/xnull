/* xrt.h — XNull 运行时稳定 ABI（S7 §6.1 / S3 §22，M4.5a 骨架）
 *
 * 合同：
 *   - 本头文件是运行时对外的唯一 ABI 面；符号与签名一经定稿冻结为 ABI 承诺，
 *     变更走主版本（S7 §6.1、附录 B）。
 *   - 编译器生成代码与绑定层/原生侧只经本头管理内存（INV-FFI-7）；
 *     内部实现头 rt.h 不随 SDK 分发。
 *   - 实现为对内部 rt_* 的薄封装（零语义改写；M3 已验收代码不动）。
 *
 * 初始化顺序合同（S7 §6.3 最小面）：xrt_runtime_init 之前、以及 safepoint
 * 可用之前不得创建对象；完整嵌入 API 属非承诺，不提供。
 */
#ifndef XNULL_XRT_H
#define XNULL_XRT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 对象种类（与运行时分配头一致；数值是 ABI 面的一部分）。 */
typedef enum {
    XRT_KIND_ARC = 1, /* 引用计数 */
    XRT_KIND_GC  = 2  /* 标记—清扫 */
} xrt_kind;

/* 类型描述符（S7 §6.1 分配入口的入参；字段布局与运行时内部同构，
 * 调用方只应通过编译生成的描述符构造，不手工解释字段）。 */
typedef struct xrt_type {
    const char *name;
    size_t      payload_size;
    void      (*deinit)(void *payload);
    void      (*scan)(void *payload, void (*visit)(void *ref));
} xrt_type;

typedef struct xrt_string    xrt_string;    /* 不透明（长度与字节经访问器） */
typedef struct xrt_weak_slot xrt_weak_slot; /* 不透明弱槽位 */

/* ---- 分配与计数（S3 §22） ---- */

void       *xrt_alloc(xrt_kind kind, const xrt_type *type);
void       *xrt_retain(void *obj);
void        xrt_release(void *obj);
int64_t     xrt_refcount(void *obj);

/* ---- 弱表（S7 §6.2：入口只对 FFI 合同层开放，原生代码不得直接调用） ---- */

xrt_weak_slot *xrt_weak_bind(void *target);
void          *xrt_weak_read(xrt_weak_slot *slot);
void           xrt_weak_clear(xrt_weak_slot *slot);

/* ---- 屏障、根与安全点（S3 §8/§12/§22） ---- */

void xrt_write_barrier(void *obj);   /* 单线程骨架期无增量屏障：仅存活校验 */
void xrt_register_root(void *obj);   /* 全局根（静态/顶层/单例/枚举项） */
void xrt_unregister_root(void *obj);
void xrt_safepoint(void);            /* 回收会合点：刷新隔离区（S3 §13） */

/* ---- 任务根（S7 §5.2：trampoline env 登记/注销） ---- */

void xrt_task_root_bind(void *obj);
void xrt_task_root_unbind(void *obj);

/* ---- 初始化（S7 §6.3 最小顺序合同） ---- */

void xrt_runtime_init(void); /* 幂等；未初始化时创建对象属调用方违约 */

/* ---- 边界字符串（S7 §3.4：ptr + byte_len，NUL 不作合同） ---- */

xrt_string *xrt_string_new(const char *utf8, size_t len);
xrt_string *xrt_string_from_c(const char *cstr);
size_t      xrt_string_len(const xrt_string *s);
const char *xrt_string_bytes(const xrt_string *s);

#ifdef __cplusplus
}
#endif
#endif /* XNULL_XRT_H */
