# 验收：M1-GEN-01（泛型）

> **验收人**：QA1（独立质量线）
> **结论：PASS 26/26**
> **复验点**：main `1ca2153`（含 G9 `c55dd81`、G11 `b23fa42`、泛型 codegen 随 `3174618` 合入）
> **用例**：`difftest/gen01/cases.json`（QA1 自写 26 项，不引用 E2 测试）
> **时间**：2026-11-07

---

## 一、结论

| 项 | 结果 |
|---|---|
| 用例总数 | 26 |
| PASS | **26** |
| FAIL | **0** |
| 双路径 accept 项 | 18 项均 `--interp` 与编译路径一致 |
| reject 项 | 8 项均按期望码拒绝 |

原 G9（签名位置类型参数泄漏落到 codegen）与 G11（列表形参元素 `get` 触发容器越界）
均已在本复验点转绿。

---

## 二、逐项结果

| # | 用例 | 验收点 | 模式 | 期望 | 结果 |
|---:|---|---|---|---|---|
| 1 | G1a | 显式类型实参 `identity<Int>(7)` | accept | `7` | PASS |
| 2 | G1b | 显式实参个数错误 | reject | `GEN-101` | PASS |
| 3 | G2a | 单参泛型推断 | accept | `7` | PASS |
| 4 | G2b | `List<T>` 形参推断（`head(xs)`） | accept | `1` | PASS |
| 5 | G2c | 双参同型推断 | accept | `1` | PASS |
| 6 | G2d | 无返回类型无法推断 | reject | `GEN-102` | PASS |
| 7 | G3 | 推断冲突 `pick(1, "s")` | reject | `GEN-102` | PASS |
| 8 | G4 | 类型参数未绑定 | reject | `GEN-102` | PASS |
| 9 | G5a | 非泛型与泛型同名重载解析 | accept | `4` | PASS |
| 10 | G5b | 重载歧义（`List<T>` 两候选） | reject | `GEN-103` | PASS |
| 11 | G5c | 重载实参类型不匹配 | reject | `TY-101` | PASS |
| 12 | G6a | 同一泛型多实例化（Int/String） | accept | `7` / `ok` | PASS |
| 13 | G6b | 多实例 `count<T>`（Int/String 列表） | accept | `2` / `3` | PASS |
| 14 | G7 | 无限递归实例化 | reject | `GEN-104` | PASS |
| 15 | G8 | `Result<T,String>` 作为泛型实参 | accept | `5` / `9` | PASS |
| 16 | **G9** | 签名位置 `static T g(T x)` 类型参数泄漏 | reject | `RES-101` | **PASS** |
| 17 | G10 | 重复类型参数名 `f<T,T>` | reject | `RES-102` | PASS |
| 18 | **G11** | `List<T> box=[local]; box.get(0)` 编译路径 | accept | `4` | **PASS** |
| 19 | G12 | 泛型函数作值 `Any f = identity<Int>` | reject | `SYN-*` | PASS |
| 20 | G13 | `identity<void>()` | reject | `GEN-101` | PASS |
| 21 | G14 | 泛型内 `is Int` 静态判定 | accept | `true` / `false` | PASS |
| 22 | G15 | `new T()` | reject | `GEN-104` | PASS |
| 23 | G16 | 跨文件泛型 `import lib.generic` | accept | `8` | PASS |
| 24 | G17 | 泛型约束 `T: Comparable`（当前不支持） | reject | `SYN-*` | PASS |
| 25 | G18 | 重载 + 显式/推断混合实例化 | accept | `4` / `s` | PASS |
| 26 | G19 | `id(null)` 无类型实参 | reject | `GEN-102` | PASS |

说明：accept 项在 `--interp` 与编译路径各跑一次，stdout 与退出码须同时一致；
reject 项以 `xnull build` 的 stderr 含期望码为准。

---

## 三、G9 / G11 闭环

| 项 | 原状 | 修复 | 本轮实测 |
|---|---|---|---|
| G9 | sema 未在签名位置报 `RES-101`，落到 codegen“类型 T 未支持” | `c55dd81` | `RES-101`（`g9.x:1:8`）→ PASS |
| G11 | `List<Int> box=[v]; box.get(0)` 编译路径 `fatal: 容器下标越界` exit 134 | `b23fa42`（return 先求值到临时变量再清理） | 输出 `4`，exit 0 → PASS |

G11 的泛型形态 `boxFirst<T>` 依赖泛型 codegen（随 `3174618` 合入）后同样通过。

---

## 四、已跑命令与结果

```bash
cd /Users/vjs/Desktop/XNull-Lang/wt/qa-1
bash difftest/anchors/run-gen.sh --sha 1ca2153 --out evidence/QA1-verify-2026-11-07
```

原样输出：

```
GEN-QA 26/26
```

历史对照：main `d349f6a` 为 24/26（G9/G11 FAIL）；`pod/e2-sema@1f960b0` 上已 26/26，
本轮在 main 独立复跑确认。

---

## 五、证据路径

- 汇总日志：`evidence/QA1-verify-2026-11-07/gen01.log`
- 被测 sha：`evidence/QA1-verify-2026-11-07/sha.txt`（`1ca2153…`）
- G9/G11 定点证据：`evidence/GEN-G11-reverify/targeted.log`、`gen01-reverify.log`
- 用例：`difftest/gen01/cases.json`；执行器：`difftest/gen01/run.sh`、`difftest/anchors/run-gen.sh`

---

## 六、未跑 / 边界

1. G7 的嵌套 `grow<List<T>>` 源码级用例仍受 xfront `>>` 拆分限制（EXP-008），本轮按直接自递归验收。
2. 泛型实例展开上限沿用 `maxInstDepth=64`；跨包泛型只验到 `LoadUnits` 合并可见。
3. 变异 / 覆盖率未跑（不属本卡）。
