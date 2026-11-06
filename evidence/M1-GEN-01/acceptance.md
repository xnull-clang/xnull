# M1-GEN-01 验收记录（当前状态：BLOCKED，等待跨域派单）

> 锚点：`GEN-01`（S1）｜主责：CEO1-RD3｜会签：CEO1-QA2
> 基线：`pod/c1-rd3` @ `dfcf033`｜记录时间：2026-11-07 03:40 CST（T+10min）

## 1. 结论

**BLOCKED（按 v1.7.0 §3.2 停止条件第 1 条：需要跨域改文件）。**

| 项 | 值 |
|---|---|
| 检查表总项 | 26 |
| 达标 | **1 / 26**（G17：类型约束确实被拒绝，但诊断是 10 条级联 SYN-101，质量不合格） |
| 未达标 | 24 / 26 |
| 不可测 | 1 / 26（G12：当前语言面无函数值语法） |

**不判 PASS，不判"部分通过"。** 按 v1.7.1 §4「没有条件通过」。

## 2. 本域（codegen）已交付、已绿

| 证据 | 文件 | 结果 |
|---|---|---|
| 单态化半边 7 个用例 | `after-codegen-half.log` | 7/7 PASS |
| 回归（既有 9 + 新增 7） | `regression.log` | 16/16 PASS，退出码 0 |
| 先红（端到端 26 项） | `before/go-test-gen01-before.log`、`stdout.txt` | 24 FAIL / 1 SKIP / 1 PASS，退出码 1 |
| 既有套件基线 | `before/baseline-existing-suite.log` | PASS（证明缺口未被既有测试覆盖） |
| CLI 双侧探针 12 例 | `before/cli-probes.log` | 见清单 §3 |

**未改任何现有测试期望，未删测试，未改 xfront/sema/interp。**

## 3. 阻塞明细（详见 `checklist.md` §4）

| 编号 | 归属 | 内容 | 估时 |
|---|---|---|---|
| B1 | RD1（xfront） | 多类型参数不解析（`Comma` token 不是 `Op`），`unit.go:352-368` | 0.5h |
| B1b | RD1（xfront） | 嵌套类型实参 `>>` 被当成运算符，`parser.go:392` | 1h |
| B2 | RD2（sema） | 类型参数未进作用域、`Call.TypeArgs` 无人读、无推断/合一、重载解析形态错误、无单态化、无展开上限 | 6h |
| B3 | 二司 RD1（interp） | 解释器零泛型支持，双路径无法验收 | 3h |

## 4. 接线契约（已写入 CEO2 请求）

**sema 推断成功后把最终类型实参写回 `Call.TypeArgs`。** 满足后，codegen 侧零改动即可覆盖
G1a/G2a/G6a/G6b/G8/G11/G18 的发射与运行。

## 5. 未测项（明确声明，不掩盖）

1. **G12**（§8.1 泛型函数不能作为值）：当前语言面无函数值/闭包语法，条款不可表达。
2. **G7 源码级用例**（§8.3 无限展开）：需嵌套类型实参 `grow<List<T>>(v)`，被 B1b 的 `>>` 词法阻断；
   本域已实现 `maxInstDepth=64` 的轮次上限与诊断，但无法用源码触发。
3. **双路径**：解释器无泛型，任何泛型用例的"编译 vs 解释"一致性都无法验收（B3）。
4. **跨包泛型**（G16）：`TestGEN01CrossFile` 已写，当前 RED（原因同 B2），未达绿。

## 6. 证据七件套索引

| 件 | 文件 |
|---|---|
| command | `command.txt` |
| stdout | `stdout.txt` |
| stderr | `stderr.txt` |
| exit_code | `exit_code.txt`（=1） |
| sha | `sha.txt` |
| artifact.sha256 | `artifacts/artifact.sha256` |
| acceptance | 本文件 |
