# M1-TUPLE-01 自检结论（执行侧，不构成验收签署）

**执行状态：DONE（检查表 11/11）——无执行侧阻塞；未测项属验收点之外的跨域边界。**

- 锚点：TUPLE-01（S1 §2.11）
- 主责：E2（worktree `wt/e2-sema`，分支 `pod/e2-sema`）
- 基线：`db74cc7`
- 预算：T0=2026-11-07 03:30，5h（T+5）
- 证据目录：`evidence/M1-TUPLE-01/`
- 红证据：`before/`（2 个测试包 exit=1）
- 绿证据：`after/`、`dualpath/`、`cli/`

## 检查表（台账验收要点逐项，11/11）

| # | 台账验收要点 | 结果 | 实现/测试映射 |
|---|---|---|---|
| T1 | 类型身份（长度+元素类型逐一；结构化、嵌套） | ✅ | `sema/tuple_test.go:TestTupleIdentity`；`splitTupleKey`（`ty.go`） |
| T2 | 字面量（至少两元素；按目标元素适配） | ✅ | `TestTupleLiteralAdaptation`；`texpr.elems` + `assignable` 元组分支 |
| T3 | 元素访问（`.0`/`.1`、`?.N`、无成员/方法、可赋值位置） | ✅ | `TestTupleElementAccess`、`TestTupleElementAssignment`、`TestTupleNullSafeElement` |
| T4 | 推断（`var` 得元组类型） | ✅ | `TestTupleInference`、`TestTupleInferenceAndNested` |
| T5 | 可赋值性（同型才可赋；无子类型；元素逐一） | ✅ | `TestTupleAssignability`、`TestTupleIdentity` 负例 |
| T6 | 相等与插值（`==/!=`、`===/!==`、`(a, b)`、不可格式化拒绝） | ✅ | `TestTupleEqualityAndInterpolation`、`TestTupleElementAssignmentAndEquality`；`valuesEqual/valuesIdentical`、`checkTupleInterp` |
| T7 | 越界选择器被拒绝（编译错误） | ✅ | `TestTupleOutOfRangeSelector`；`TY-106`（越界选择器） |
| T8 | 单元素/零元元组被拒绝 | ✅ | `TestTupleArityRejected`（语法层） |
| T9 | 解构被拒绝 | ✅ | `TestTupleDestructuringRejected`（语法层） |
| T10 | 元组 `switch` 被拒绝 | ✅ | `TestTupleSwitchRejected`；`TY-106` |
| T11 | 元组 `const` 被拒绝 | ✅ | `TestTupleConstRejected`（语法层） |

附加（§2.11 直接相关）：同型 `as` 恒等、异型 `as` 拒绝 → `TestTupleTypeAs` ✅。

## 红 → 绿

- 红：`before/sema.out`、`before/interp.out`，exit 均为 1。失败覆盖：
  - sema：类型身份负例、字面量适配、`pair.length`、插值不可格式化、越界、元组 switch、元素赋值、异型 as；
  - interp：元素赋值、值复制独立性、`===/!==`、插值。
- 绿：`after/sema-tuple.out`（13 PASS）、`after/interp-tuple.out`（5 PASS），exit 均为 0。

## 命令与结果

- `go test ./internal/sema/ -run 'TestTuple' -v -count=1` → PASS，exit 0
- `go test ./internal/interp/ -run 'TestTuple' -v -count=1` → PASS，exit 0
- `go test ./internal/sema/ ./internal/interp/ -count=1` → PASS
- `go test ./... -count=1 -timeout 600s` → 全部包 PASS，exit 0
- `go vet ./...` → exit 0
- 双路径：既有 9 个示例 `examples/*.x`，解释/编译 stdout 逐字节一致、退出码一致（`dualpath/summary.txt`，9/9）
- CLI 解释路径：正例 `tuple-ok.x` exit 0，输出 `pair=(1, one) / copy=(2, one) / true / false`；负例 `tuple-oob.x`、`tuple-switch.x` exit 1（`TY-106`）

## 未测项（明确边界）

1. **元组位于顶层函数返回类型 / 顶层字段**：`xfront` 的 `parseTopType` 只接受命名类型+后缀，不接受 `(T1,T2)`；属语法域改动，本轮未动（避免跨域）。
2. **可空元组声明 `(T1,T2)?`**：`tryTupleTypeDecl` 不接受 `)` 后 `?`；`?.N` 已在非空元组上测通，null 传播未测。
3. **元组进入泛型实参 / 容器元素 / 闭包捕获**：parser/sema 未做专项用例；容器插入时的值复制未验证。
4. **编译路径（codegen）元组**：`internal/codegen` 目前无元组实现；双路径仅回归既有 9 示例，未新增元组示例（新增会引入跨域 codegen 工作）。
5. **元组存入容器时的深拷贝**：当前只在作用域绑定（局部/赋值/参数）复制元组值；`List.push`/数组字面量等容器路径未加复制，未测。
6. 台账 `status.tsv` 仍为“部分”：执行侧不手改状态，等 QA1/CEO1 独立验收后按流程更新。

## 声明

执行侧自检，不构成验收签署；未改现有测试期望、未删测试、未 push/合并。
