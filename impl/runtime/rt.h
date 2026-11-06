/*
 * rt.h — XNull C 运行时核心头（M3.1 值模型与引用计数子切片）
 *
 * 规范依据：S3 §2（分配头与布局）、§7（引用计数基础）、§8（标记—清扫基础）、§14（终结链）。
 * 合同：
 *   - 堆对象统一分配头：对象种类（ARC/GC）、类型描述符、计数、扫描信息（S3 §2）；
 *   - ARC 计数原子（S3 §7；本骨架使用 C11 atomics，跨编译单元唯一格式）；
 *   - retain/release 成对；release 到零触发终结链（S3 §7/§14）；
 *   - 终结链时序：先置终结标志（防复活/双重释放）→ 调用类型描述符 deinit → 释放内存；
 *   - 字段按 8 字节对齐（S3 §2）；更紧凑打包是 §20 优化方向，当前不承诺。
 */
#ifndef XNULL_RT_H
#define XNULL_RT_H

#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 对象种类（S3 §2）。 */
typedef enum {
    RT_KIND_ARC = 1, /* ARC 管理：引用计数 */
    RT_KIND_GC  = 2  /* GC 管理：标记—清扫（本子切片仅登记种类，清扫在 M3.4） */
} rt_kind;

/* 类型描述符（S3 §2 合同：支持动态类型检查与终结分派）。
 * is/as 与协议检查的完整面在类型系统子切片扩展；当前承载终结钩子与大小。 */
typedef struct rt_type {
    const char *name;                     /* 类型名（诊断与 is 检查基础） */
    size_t      payload_size;             /* 载荷字节数 */
    void      (*deinit)(void *payload);   /* 终结钩子（可为 NULL：无引用字段） */
    /* 扫描钩子（S3 §2：扫描信息）：参数为完整对象指针（与 deinit 同约定），
     * 枚举载荷中的强引用字段，逐个调用 visit(ref)。
     * GC 对象必须有 scan（标记与清扫遍历依据，S3 §8）；
     * ARC 对象仅在持有 GC 引用时需要（不变量 2：登记为扫描对象，§15.6）。 */
    void      (*scan)(void *payload, void (*visit)(void *ref));
} rt_type;

/* 分配头（S3 §2）。字段按 8 字节对齐。 */
struct rt_object;

typedef struct rt_header {
    rt_kind             kind;
    const rt_type      *type;      /* 类型描述符 */
    atomic_int_fast64_t refcount;  /* ARC 计数（原子，S3 §7） */
    int                 terminated; /* 终结标志：release→0 先置位（§14 防复活） */
    /* GC 交互（S3 §8、S2 §15.6）：
     * marked       GC 标记位（仅 RT_KIND_GC）；
     * gc_next      全 GC 对象清单（清扫遍历）；
     * scan_next    ARC 扫描对象链（不变量 2：ARC 持 GC 引用时登记为根）；
     * in_scan_list 该 ARC 对象是否在扫描链上（终结时先注销，不变量 6）。 */
    int                 marked;
    struct rt_object   *gc_next;
    struct rt_object   *scan_next;
    int                 in_scan_list;
    struct rt_weak_slot *weak_head; /* 弱槽位侧链（S3 §16；不构成强引用） */
} rt_header;

/* 堆对象 = 分配头 + 载荷。 */
typedef struct rt_object {
    rt_header hdr;
    /* 载荷紧跟其后（flexible array 由各具体类型使用）。 */
} rt_object;

/* ---- 字符串（首个堆对象类型；S1 §2 String 为引用类型） ---- */

typedef struct rt_string {
    rt_header hdr;
    size_t    len;    /* UTF-8 字节数（§9.2 length 语义） */
    char      bytes[]; /* NUL 结尾便于 FFI 互操作；len 为权威长度 */
} rt_string;

/* 生命周期（S3 §7：retain/release 成对；计数从 1 起）。 */
void       *rt_retain(void *obj);
void        rt_release(void *obj);
int64_t     rt_refcount(void *obj); /* 测试与诊断用 */
void       *rt_payload(void *obj);  /* 载荷指针 = 对象 + 头大小 */

/* ARC 扫描链注销（rt_gc.c 实现；终结链在 deinit 前调用，不变量 6）。 */
struct rt_object;
void        rt_scan_unregister(struct rt_object *o);
void        rt_quarantine_push(struct rt_object *o); /* 终结后入隔离区（S3 §13） */
size_t      rt_quarantine_flush(void); /* 回收会合：释放隔离区，返回释放数 */

/* 字符串构造。 */
rt_string  *rt_string_new(const char *utf8, size_t len);
rt_string  *rt_string_alloc(size_t len); /* 定长、内容未初始化、NUL 结尾 */
rt_string  *rt_string_from_c(const char *cstr);

/* 类型描述符（运行时导出，供 is/as 与编译器登记）。 */
extern const rt_type RT_TYPE_STRING;

/* fatal（S3 §14/§15：终结链 panic、复活检测、隐式 fatal 路径 → 终止进程）。
 * 默认打印 reason 后 abort；宿主可安装处理器（测试/嵌入场景）。 */
typedef void (*rt_fatal_handler)(const char *reason);
void        rt_set_fatal_handler(rt_fatal_handler h);
void        rt_fatal(const char *reason);

/* 弱引用表（S3 §16：运行时内部机制，不变量 4）。 */
typedef struct rt_weak_slot rt_weak_slot;
rt_weak_slot *rt_weak_create(void *target); /* 建立弱槽位（不持强引用） */
void         *rt_weak_get(rt_weak_slot *s); /* 终结后返回 NULL，禁止观察到已终结目标 */
void          rt_weak_destroy(rt_weak_slot *s); /* 槽位摘除与复用 */
void          rt_weak_clear_slots(void *target); /* 终结链第 1 步：清除全部弱槽位 */

#ifdef __cplusplus
}
#endif
#endif /* XNULL_RT_H */
