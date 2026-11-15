/* rt_policy.c —— §15.1 判定表：按行序执行，命中即返回（确定性）。 */
#include "rt_policy.h"

rt_policy rt_decide_policy(const rt_policy_input *in, int *rule_out) {
    int rule = 0;
    rt_policy p = RT_POLICY_ARC;
    if (in->kind == RT_KIND_STRUCT) {
        rule = 0; /* struct 恒为值（§15.1 说明） */
        p = RT_POLICY_VALUE;
    } else if (in->kind == RT_KIND_PROTOCOL) {
        rule = 2;
        p = RT_POLICY_NA_GC;
    } else if (in->kind == RT_KIND_ENUM_SIMPLE) {
        rule = 3;
        p = RT_POLICY_VALUE;
    } else if (in->kind == RT_KIND_ENUM_DATA) {
        rule = 4;
        p = RT_POLICY_GC;
    } else if (in->gc_field) {
        rule = 5;
        p = RT_POLICY_GC;
    } else if (in->ref_cycle) {
        rule = 6;
        p = RT_POLICY_GC;
    } else if (in->has_deinit || in->self_captured) {
        rule = 7;
        p = RT_POLICY_ARC;
    } else if (!in->has_ref_field) {
        rule = 8; /* 只有值字段：栈候选（§14.2 逃逸后提升） */
        p = RT_POLICY_ARC;
    } else {
        rule = 9; /* 其余无环类引用 */
        p = RT_POLICY_ARC;
    }
    if (rule_out) {
        *rule_out = rule;
    }
    return p;
}

const char *rt_policy_rule_name(int rule) {
    switch (rule) {
    case 0: return "value";
    case 1: return "singleton-gc";
    case 2: return "protocol-na";
    case 3: return "enum-inline";
    case 4: return "enum-data-gc";
    case 5: return "gc-field";
    case 6: return "ref-cycle";
    case 7: return "deinit-or-capture";
    case 8: return "stack-candidate";
    case 9: return "plain-arc";
    default: return "unknown";
    }
}
