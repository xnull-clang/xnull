/* xrt.h — XNull 运行时稳定 ABI（S7 §6.1 / S3 §22，M4.5a 骨架）
 *
 * 状态：**ABI v1 候选冻结**（EXP-012，2026-11-07）。符号与签名冻结为候选消费面，
 *   不承诺跨版本二进制稳定；numeric 变体（句柄 + Bytes + @errorCode）端到端
 *   通过后转“稳定 v1”，此后变更走主版本。状态口径见 docs/runtime-contract.md A0。
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
/* 定长构造：分配头初始化、内容未定义、NUL 结尾；len 为权威长度。
 * 替代生成代码手写分配头（P-08 迁移清单）。 */
xrt_string *xrt_string_alloc(size_t len);
/* String 的类型描述符（S3 §2：is/as 与终结分派用同一描述符实例）。 */
const xrt_type *xrt_type_string_descriptor(void);
size_t      xrt_string_len(const xrt_string *s);
const char *xrt_string_bytes(const xrt_string *s);

/* ---- 边界缓冲区视图（S7 §3.4；FFI 借出时由调用方填 data/len） ---- */

typedef struct xrt_bytes {
    void  *data;
    size_t len;
} xrt_bytes;

/* ---- Text / StringBuilder（S1 §9.7 / S3 §10：GC 对象，字节区免扫描） ---- */

typedef struct xrt_text xrt_text;
typedef struct xrt_sb   xrt_sb;

xrt_text   *xrt_text_from_string(const char *bytes, size_t len);
size_t      xrt_text_length(const xrt_text *t);
int64_t     xrt_text_code_point_count(const xrt_text *t);
xrt_string *xrt_text_to_string(const xrt_text *t);
int32_t     xrt_text_compare_to(const xrt_text *a, const xrt_text *b);

xrt_sb     *xrt_sb_new(void);
void        xrt_sb_append_str(xrt_sb *sb, const char *bytes, size_t len);
void        xrt_sb_append_int(xrt_sb *sb, int64_t v);
size_t      xrt_sb_length(const xrt_sb *sb);
xrt_string *xrt_sb_to_string(const xrt_sb *sb);

/* ---- 可变字节缓冲（Bytes 语言类型；S1 §9.7 / S3 §188） ----
 *
 * 合同：
 *   - 长度权威，允许内嵌 NUL，不要求 NUL 终止（S7 §3.4）；
 *   - 字节区免扫描（S3 §188）；对象无引用字段；
 *   - get/set/slice 越界 → xrt_fatal（S1 §9.7“越界 panic”）；push/set 取低 8 位；
 *   - FFI 借出：生成代码传 (xrt_bytes_data(b), xrt_bytes_len(b))，包装层做 canary
 *     拷贝进出（ffi-contract §5.1）。
 *   - 分配种类：当前 ARC（与 String/类/容器一致）；S3 §188 的 GC 分类切换只改
 *     实现内部 kind，本组符号与签名不变。
 */
typedef struct xrt_bytes_buf xrt_bytes_buf; /* 不透明对象 */
typedef xrt_bytes_buf xrt_bytes_obj;        /* B0-07c codegen 契约别名 */

xrt_bytes_buf *xrt_bytes_new(void);                          /* 空缓冲 */
xrt_bytes_buf *xrt_bytes_alloc(size_t len);                  /* 定长、内容清零 */
xrt_bytes_buf *xrt_bytes_from_c(const void *data, size_t len); /* 复制构造 */
xrt_bytes_buf *xrt_bytes_from_string(const char *bytes, size_t len); /* from_c 别名 */
size_t         xrt_bytes_len(const xrt_bytes_buf *b);
void          *xrt_bytes_data(xrt_bytes_buf *b);
int32_t        xrt_bytes_get(const xrt_bytes_buf *b, size_t i);
void           xrt_bytes_set(xrt_bytes_buf *b, size_t i, int32_t v);
void           xrt_bytes_push(xrt_bytes_buf *b, int32_t v);
void           xrt_bytes_append(xrt_bytes_buf *b, const xrt_bytes_buf *src);
xrt_bytes_buf *xrt_bytes_slice(const xrt_bytes_buf *b, size_t start, size_t end);

/* ---- 不透明句柄（S7 §4.3） ----
 *
 * 合同：
 *   - 句柄是普通 ARC 对象，载荷为原生指针；ARC/GC 不解释原生对象（S7 §9 INV-FFI-4）；
 *   - close 显式且幂等：重复关闭返回成功且不再调用原生 close_fn；
 *   - deinit 不自动 close，只把泄漏打到诊断通道（S7 §4.3：不得以 deinit 为唯一关闭路径）；
 *   - 已关闭句柄再取原生指针返回 NULL（拒绝使用后访问）。
 */
typedef struct xrt_handle xrt_handle;

xrt_handle *xrt_handle_new(void *native, void (*close_fn)(void *native), const char *what);
void       *xrt_handle_native(xrt_handle *h); /* 已关闭 → NULL */
int         xrt_handle_close(xrt_handle *h);  /* 幂等；返回 0 表示已关闭（含重复关闭） */
void        xrt_handle_mark_closed(xrt_handle *h); /* 已经原生 close 的语义登记：不再触达 close_fn */
int         xrt_handle_is_closed(const xrt_handle *h);

/* ---- ErrorKind 稳定枚举与 FFI 分类骨架（S4 §3/§7.3/附录 A） ----
 *
 * 枚举值跨版本只追加、不改名/删除（S4 §3.3）；数值是 ABI 面。
 * FFI 绑定层把原生错误码映射到本枚举；Cancelled/Timeout 不得降级为 Internal。
 */
typedef enum xrt_error_kind {
    XRT_ERR_INVALID_ARGUMENT = 0,
    XRT_ERR_NOT_FOUND        = 1,
    XRT_ERR_ALREADY_EXISTS   = 2,
    XRT_ERR_PERMISSION_DENIED = 3,
    XRT_ERR_IO               = 4,
    XRT_ERR_NETWORK          = 5,
    XRT_ERR_TIMEOUT          = 6,
    XRT_ERR_CANCELLED        = 7,
    XRT_ERR_BUSY             = 8,
    XRT_ERR_UNAVAILABLE      = 9,
    XRT_ERR_DATA_CORRUPTED   = 10,
    XRT_ERR_UNSUPPORTED      = 11,
    XRT_ERR_OUT_OF_MEMORY    = 12,
    XRT_ERR_INTERNAL         = 13
} xrt_error_kind;

const char     *xrt_error_kind_name(xrt_error_kind kind);
xrt_error_kind  xrt_error_kind_parse(const char *name); /* NULL/未知 → XRT_ERR_INTERNAL */

/* ---- 分配统计与 GC 指标（S3 §21/§23；默认关闭） ---- */

typedef struct xrt_stats {
    uint64_t allocs;
    uint64_t frees;
    uint64_t bytes;         /* 累计分配字节（含分配头） */
    uint64_t gc_collections;
    uint64_t gc_freed;
} xrt_stats;

void xrt_stats_reset(void);
void xrt_stats_get(xrt_stats *out);
void xrt_stats_set_enabled(int on);
int  xrt_stats_enabled(void);
void xrt_stats_report(void); /* 单行写 stderr（工具能力，非语言语义） */

/* ---- 回调环境 / trampoline（S7 §5.1/§5.2） ----
 *
 * 合同：
 *   - env 是运行时根：创建即登记，销毁即注销（S7 §5.2）；
 *   - 销毁后原生再调用 → xrt_fatal（原生侧合同违规，不静默）；
 *   - 目标 ABI 由绑定层以 xrt_callback_fn 提供（闭包调用约定由生成方负责）；
 *   - env 为 GC 对象；闭包引用生命周期由绑定层管理（env 只存裸指针）。
 */
typedef int32_t (*xrt_callback_fn)(void *closure, const void *args, size_t nargs, void *result);
typedef struct xrt_callback_env xrt_callback_env;

xrt_callback_env *xrt_callback_env_new(void *closure, xrt_callback_fn fn);
int32_t xrt_callback_env_invoke(xrt_callback_env *env, const void *args, size_t nargs, void *result);
void    xrt_callback_env_destroy(xrt_callback_env *env); /* 幂等；注销根 */
int     xrt_callback_env_alive(const xrt_callback_env *env);
void   *xrt_callback_env_closure(const xrt_callback_env *env);

/* ---- 任务运行时（S5-00 冻结面 v0；S5-01 调度器核心） ---- */

typedef struct xrt_task         xrt_task;         /* ARC 句柄：join 一次 */
typedef struct xrt_task_group   xrt_task_group;   /* ARC 资源：close 唯一终结路径 */
typedef struct xrt_context      xrt_context;      /* ARC 句柄：取消 + 截止 */
typedef struct xrt_cancel_token xrt_cancel_token; /* 借用：内嵌于 context */

typedef struct xrt_task_result {
    int32_t        ok;     /* 1 = Ok；0 = Err */
    void          *value;  /* Ok：+1/拥有 */
    xrt_error_kind kind;   /* Err：S4 ErrorKind */
    void          *error;  /* Err：错误值 +1（可为 NULL） */
} xrt_task_result;

typedef int32_t (*xrt_task_body)(void *env, xrt_context *ctx, xrt_task_result *out);

#define XRT_STATUS_CLOSED 100 /* 通道关闭终态（状态域，非 ErrorKind；S5-00 §六） */

/* Context / 时钟 */
xrt_context *xrt_context_background(void); /* +1；仅 main/测试 */
xrt_context *xrt_context_child(xrt_context *parent);
xrt_context *xrt_context_with_deadline(xrt_context *parent, int64_t deadline_mono_ms);
int32_t      xrt_context_check_cancel(const xrt_context *ctx); /* 0 或 XRT_ERR_CANCELLED */
int32_t      xrt_context_cancelled(const xrt_context *ctx);
xrt_cancel_token *xrt_context_token(xrt_context *ctx); /* 借用 */
int32_t      xrt_cancel_token_cancelled(const xrt_cancel_token *token); /* 0/1；原子读 */
void         xrt_context_cancel(xrt_context *ctx);     /* 幂等 */
int64_t      xrt_clock_mono_ms(void);

/* Task / TaskGroup */
xrt_task_group *xrt_task_group_new(xrt_context *parent);
int32_t xrt_task_group_spawn(xrt_task_group *g, xrt_task_body body, void *env, xrt_task **out);
void    xrt_task_group_cancel(xrt_task_group *g);
int32_t xrt_task_group_close(xrt_task_group *g, xrt_task_result *first_error);
int32_t xrt_task_join(xrt_task *t, xrt_task_result *out);
int32_t xrt_task_join_deadline(xrt_task *t, int64_t deadline_mono_ms, xrt_task_result *out);

/* ---- 跨界违约终止（S7 §9 INV-FFI-8：跨界 panic 一律终止进程） ---- */

void xrt_fatal(const char *reason);

#ifdef __cplusplus
}
#endif
#endif /* XNULL_XRT_H */
