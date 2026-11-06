/* rt_policy.h —— 内存策略判定表执行器（S2 §15.1，M3.2）。
 *
 * 输入结构与 Go 侧 impl/internal/sema/policy.go 的 Strategy 冻结对应
 * （见 README "策略判定接口"）。判定是确定性的纯函数（DET-01）：
 * 同一输入恒产生同一策略与同一判定行号。
 */
#ifndef XNULL_RT_POLICY_H
#define XNULL_RT_POLICY_H

#ifdef __cplusplus
extern "C" {
#endif

/* 类型种类（§15.1 判定输入：种类）。 */
typedef enum {
    RT_KIND_CLASS = 0,     /* 引用类型 */
    RT_KIND_STRUCT = 1,    /* 纯值类型（不进入 ARC/GC） */
    RT_KIND_ENUM_SIMPLE = 2, /* 简单枚举（stack/内联整数） */
    RT_KIND_ENUM_DATA = 3, /* 数据枚举（GC，§8.3） */
    RT_KIND_PROTOCOL = 4   /* 无实例；分析按 GC */
} rt_type_kind;

/* 内存策略（§15.1 判定输出）。 */
typedef enum {
    RT_POLICY_VALUE = 0, /* 值：不进入 ARC/GC */
    RT_POLICY_ARC = 1,   /* 引用计数 */
    RT_POLICY_GC = 2,    /* 全局 GC 图 */
    RT_POLICY_NA_GC = 3  /* 无实例，分析按 GC（协议） */
} rt_policy;

/* 判定输入：种类与源码结构事实（全部来自单态化后的类型结构，§15.1）。 */
typedef struct {
    rt_type_kind kind;
    int has_deinit;    /* 类存在 deinit（行 7） */
    int self_captured; /* 类方法在闭包中捕获 self（行 7） */
    int ref_cycle;     /* 强引用环（行 6；sema 字段类型图已判定） */
    int gc_field;      /* 存在直触发 GC 的强引用字段：Any/Object/协议/
                          未单态化泛型/含引用元组/Result（行 5） */
    int has_ref_field; /* 存在引用字段（行 9 的前提；无则为行 8 值字段） */
} rt_policy_input;

/* 执行判定表：返回策略；*rule_out 写命中行号（1–9；struct 为 0）。 */
rt_policy rt_decide_policy(const rt_policy_input *in, int *rule_out);

/* 判定行号的可读名（诊断与测试输出用）。 */
const char *rt_policy_rule_name(int rule);

#ifdef __cplusplus
}
#endif
#endif /* XNULL_RT_POLICY_H */
