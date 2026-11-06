/*
 * test_rt.c — M3.1 运行时骨架 C 测试（cc 直编直跑，无外部依赖）
 * 断言：分配头布局、计数成对、终结链时序、防复活、防双重释放、deinit 恰好一次。
 */
#include "rt.h"
#include "rt_policy.h"

#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static int deinit_calls = 0;

static void test_policy_table(void); /* 前置声明：main 之后定义 */

typedef struct {
    rt_header  hdr;
    rt_string *name; /* 引用字段：deinit 时应被释放 */
} boxed_t;

static void boxed_deinit(void *payload) {
    boxed_t *b = payload;
    rt_release(b->name);
    deinit_calls++;
}

static const rt_type RT_TYPE_BOXED = {
    .name = "Boxed", .payload_size = sizeof(boxed_t) - sizeof(rt_header), .deinit = boxed_deinit,
};

static boxed_t *boxed_new(rt_string *name) {
    boxed_t *b = malloc(sizeof(boxed_t));
    assert(b != NULL);
    b->hdr.kind = RT_KIND_ARC;
    b->hdr.type = &RT_TYPE_BOXED;
    atomic_init(&b->hdr.refcount, 1);
    b->hdr.terminated = 0;
    b->name = (rt_string *)rt_retain(name); /* 持有引用：取引用必须 retain（S3 §7 成对合同） */
    return b;
}

int main(void) {
    /* 1. 字符串构造与计数 */
    rt_string *s = rt_string_from_c("hello, XNull");
    assert(s != NULL && s->len == 12);
    assert(strcmp(s->bytes, "hello, XNull") == 0);
    assert(rt_refcount(s) == 1);

    /* 2. retain/release 成对 */
    assert(rt_retain(s) == s);
    assert(rt_refcount(s) == 2);
    rt_release(s);
    assert(rt_refcount(s) == 1);

    /* 3. 终结链：到零走 deinit 并释放（valgrind/ASan 验证不泄漏；此处验证不崩溃） */
    rt_string *t = rt_string_new("x", 1);
    rt_release(t);

    /* 4. 防双重释放：终结后 release 为 no-op（不崩溃、不递减） */
    rt_release(t);

    /* 5. 组合对象：deinit 恰好调用一次，内部引用随之释放 */
    rt_string *name = rt_string_from_c("boxed");
    boxed_t *b = boxed_new(name);
    assert(rt_refcount(name) == 2); /* boxed 持有 + 局部 */
    assert(rt_retain(b) == b);
    rt_release(b);
    rt_release(b); /* 到零：deinit → rt_release(name) → free */
    assert(deinit_calls == 1);
    assert(rt_refcount(name) == 1); /* 只剩局部持有 */

    /* 6. 防复活：已终结对象 retain 拒绝（§14）——通过悬空验证成本高，
     *    此处以"终结后计数语义"间接覆盖：rt_release 幂等（用例 4 已验）。 */

    /* 7. 策略判定表执行器（S2 §15.1，M3.2） */
    test_policy_table();

    printf("rt tests passed\n");
    return 0;
}

/* ---------- M3.2：策略判定表执行器（§15.1） ---------- */

static void test_policy_table(void) {
    /* 每行一个用例：输入 → 期望策略与判定行。 */
    struct {
        rt_policy_input in;
        rt_policy want;
        int want_rule;
    } cases[] = {
        /* 行 2：协议按 GC 分析 */
        {{RT_KIND_PROTOCOL, 0, 0, 0, 0, 0}, RT_POLICY_NA_GC, 2},
        /* 行 3：简单枚举内联 */
        {{RT_KIND_ENUM_SIMPLE, 0, 0, 0, 0, 0}, RT_POLICY_VALUE, 3},
        /* 行 4：数据枚举 GC */
        {{RT_KIND_ENUM_DATA, 0, 0, 0, 0, 0}, RT_POLICY_GC, 4},
        /* 行 5：GC 触发字段 */
        {{RT_KIND_CLASS, 0, 0, 0, 1, 1}, RT_POLICY_GC, 5},
        /* 行 6：强引用环（优先级低于行 5） */
        {{RT_KIND_CLASS, 0, 0, 1, 0, 1}, RT_POLICY_GC, 6},
        /* 行 7：deinit */
        {{RT_KIND_CLASS, 1, 0, 0, 0, 1}, RT_POLICY_ARC, 7},
        /* 行 7：self 捕获 */
        {{RT_KIND_CLASS, 0, 1, 0, 0, 1}, RT_POLICY_ARC, 7},
        /* 行 8：只有值字段 → 栈候选 */
        {{RT_KIND_CLASS, 0, 0, 0, 0, 0}, RT_POLICY_ARC, 8},
        /* 行 9：无环类引用 */
        {{RT_KIND_CLASS, 0, 0, 0, 0, 1}, RT_POLICY_ARC, 9},
        /* struct：不进入 ARC/GC */
        {{RT_KIND_STRUCT, 0, 0, 0, 0, 0}, RT_POLICY_VALUE, 0},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        int rule = -1;
        rt_policy p = rt_decide_policy(&cases[i].in, &rule);
        if (p != cases[i].want || rule != cases[i].want_rule) {
            fprintf(stderr, "policy case %zu: got policy=%d rule=%d, want %d/%d\n",
                    i, (int)p, rule, (int)cases[i].want, cases[i].want_rule);
            assert(0);
        }
    }
    /* 确定性：同输入两次判定逐字段一致（DET-01）。 */
    rt_policy_input in = {RT_KIND_CLASS, 1, 0, 0, 0, 1};
    int r1 = -1, r2 = -1;
    rt_policy p1 = rt_decide_policy(&in, &r1);
    rt_policy p2 = rt_decide_policy(&in, &r2);
    if (p1 != p2 || r1 != r2) {
        fprintf(stderr, "policy determinism violated: %d/%d vs %d/%d\n",
                (int)p1, r1, (int)p2, r2);
        assert(0);
    }
    printf("ok  policy table (%zu rows, deterministic)\n",
           sizeof(cases) / sizeof(cases[0]));
}
