/* rt_gc.h —— 标记—清扫 GC 与混合引用图（S3 §5/§8、S2 §15.6，M3.3）。
 *
 * 不变量映射（§15.6）：
 *   1 强引用要么计数要么追踪 —— ARC 引用走 rt_retain/release；
 *     GC 引用只存在两类持有者：GC 对象（scan 枚举）与 ARC 扫描对象（登记追踪）。
 *   2 ARC 持 GC 引用 → 分配时登记进扫描链，存活期间其 GC 引用是根。
 *   3 GC 持 ARC 引用 → 标记 ARC 目标可达；清扫死亡 GC 对象时 release 其 ARC 引用。
 *   5 至少一个 GC 节点的环由 GC 回收（全 ARC 环由编译器分析改判，§15.1.1）。
 *   6 ARC 终结前从扫描链注销并清除 GC 引用；清扫只处理存活期内的引用，无重复释放。
 *
 * 根集合（S3 §8）：全局根（静态/顶层字段、单例、数据枚举项——编译器登记）
 * + ARC 扫描链（不变量 2）。栈槽位根在代码生成接入（M4.1）前由全局根 API 覆盖。
 */
#ifndef XNULL_RT_GC_H
#define XNULL_RT_GC_H

#include "rt.h"

#ifdef __cplusplus
extern "C" {
#endif

/* GC 对象分配：入全 GC 对象清单，计数从 1 起（与其他持有者成对释放）。
 * type->scan 必须非空。 */
void *rt_gc_new(const rt_type *type);

/* 持 GC 引用的 ARC 对象分配：type->scan 非空时登记进扫描链（不变量 2）。 */
void *rt_arc_new(const rt_type *type);

/* 全局根登记（静态/顶层字段、单例、数据枚举项；S3 §8 根集合）。
 * 同一对象重复登记幂等；移除未登记对象为 no-op。 */
void rt_gc_root_add(void *obj);
void rt_gc_root_remove(void *obj);

/* 触发回收：标记（根 + 扫描链可达）→ 清扫（死亡 GC 对象 release ARC 引用后释放）。
 * 返回本次清扫释放的 GC 对象数（诊断用）。 */
size_t rt_gc_collect(void);

/* 存活 GC 对象数（测试与诊断）。 */
size_t rt_gc_live(void);

#ifdef __cplusplus
}
#endif
#endif /* XNULL_RT_GC_H */
