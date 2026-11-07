# 回执：M1-ERR-01（CEO1-RD2）

> **状态**：`DONE`｜**检查表 12/12**｜**commit** `09367e8`（`pod/c1-rd2`，未 push、未合并）
> **时间**：T0 03:30 起红测试 → T+0:06（约 03:36）实现转绿 → 03:37 证据落盘
> **依据**：v1.7.0 第 2/3 条、v1.7.1 第 2/3/4 条；台账 `XNull一致性用例台账-v1.0.0.md:26`
> **证据**：`wt/c1-rd2/evidence/M1-ERR-01/`（七件套 + `before/` 红输出）

---

## 一、五行

1. **完成**：ERR-01 四项缺口全部在 `impl/internal/sema` 落地——`Result` 构造/成员、`@mustUse`、`try` 传播与错误类型、清理体限制；新增诊断码 `ERR-201`—`ERR-206`。
2. **完成**：T+1 检查点提前达成——红测试 03:30 落 `before/test.log`（8 个测试函数、43 个子用例失败），实现后 8/8、全部子用例转绿，未改既有测试期望、未删测试。
3. **完成**：回归全绿——`sema` 全量、`interp` 全量、`go test ./... -timeout 300s`、`go vet ./...`、`gofmt -l .` 均 exit 0；9 个示例双路径 PASS（含 `result-try.x`、`defer-cleanup.x`）；两次运行归一化 diff 为空。
4. **边界**：`Err.value()` / `Ok.error()` 的运行期 panic 已用解释器探针证明 exit 134（`after/illegal-*`），但**对应 `internal/interp` 单元测试未入库**——该目录属二司，按 v1.7.0 §3.2 停止条件未跨域，交 CEO2-QA1 补一条负向用例。
5. **需决策**：`E → E2` 的类/协议子类型可赋值依赖 TYPE-01 子类型规则（本锚点未实现），当前 `try` 错误类型检查支持同型 + `Object`/`Any`；若 M1 门要求子类型错误链，请把 TYPE-01 子类型补口排进 T+8 前。

## 二、逐项打勾（12/12，依据台账验收要点逐字拆分）

- [x] **ERR01-01 `Result` 构造**：`Ok(value)`/`Ok()`（仅 `Result<void,E>`）/`Err(error)`；按目标类型推断；无目标类型报 `ERR-202`；`E != void`
- [x] **ERR01-02 `Result` 成员**：`isOk()`/`isErr()`/`value()`/`error()` 无参；`unwrapOr(T)` 恰一参且可赋给 `T`；`T=void` 禁 `value`/`unwrapOr`；未知成员报 `ERR-203`
- [x] **ERR01-03 `@mustUse`**：裸变量/裸调用/裸 `Ok`/`defer` 内未处理 → `ERR-201`；返回、赋值、字段/容器、`try`、成员调用均合法
- [x] **ERR01-04 `try` 传播**：仅 `Result`；外层必须返回 `Result<_,E2>`；`E` 可赋 `E2`；`Result<void,E>` 可作语句；可嵌套；main/构造器/`deinit`/清理体禁用；闭包按目标函数类型检查
- [x] **ERR01-05 错误类型检查**：`Result` 必须两个实参；`E != void`；`Ok`/`Err` 实参与 `T`/`E` 匹配；`try` 的错误类型匹配
- [x] **ERR01-06 `defer`/`errdefer` LIFO**：既有 `hard_test.go` 三组用例 + `interp` 全量通过
- [x] **ERR01-07 触发条件**：既有 Ok/错误/try 路径用例；新增 `errdefer` 非 Result 上下文 → `ERR-206`
- [x] **ERR01-08 清理体限制**：return/break/continue/goto/try/throw/嵌套 defer/errdefer/闭包/单条局部声明 → `ERR-205`
- [x] **ERR01-09 `isOk` 正确使用**：既有正向 + 新增 arity/返回 `Bool` 用例
- [x] **ERR01-10 `isErr` 正确使用**：同上
- [x] **ERR01-11 `value` 正确使用**：正向既有 + `Result<void,E>` 禁用/arity；运行期 Err→`value` panic 探针 exit 134
- [x] **ERR01-12 `error` 正确使用**：同上；运行期 Ok→`error` panic 探针 exit 134

## 三、未测项（不隐瞒）

1. **`internal/interp` 负向单测未入库**：跨域（二司文件），仅有解释器探针证据；建议 CEO2-QA1 在 T+5 前补 `Err.value()` / `Ok.error()` 两条。
2. **`E → E2` 子类型可赋值**：类继承/协议实现规则未实现，`Result<Int, SubError>` → `Result<Int, BaseError>` 会保守报错；同型与 `Object`/`Any` 已覆盖。
3. **无目标类型的闭包体**：仅在闭包被赋给函数类型目标时检查；`var f = () -> ...` 的闭包体仍不遍历（既有边界，未扩大改动面）。
4. **类字段 `Result` 初始化式**：实现已检查，但未加专项用例；由 `defer-cleanup.x` 双路径间接覆盖。

## 四、改动与证据

| 项 | 内容 |
|---|---|
| 生产代码 | `impl/internal/sema/error.go`（新增，ERR-2xx 与检查器）、`ty.go`（目标导向推断/成员/try/mustUse）、`typedecl.go`（方法/构造器/字段初始化上下文） |
| 测试 | `impl/internal/sema/err01_test.go`（新增 11 个测试函数、43 个子用例）；未改既有测试 |
| 红证据 | `evidence/M1-ERR-01/before/test.log`（FAIL，exit 1） |
| 七件套 | `command.txt` / `stdout.txt` / `stderr.txt` / `exit_code.txt` / `sha.txt` / `artifact.sha256` / `acceptance.md` |
| 双路径 | `after/codegen-examples.log`：9/9 PASS |
| 确定性 | `after/determinism.diff`：归一化后空 diff |
| 未改 | `status.tsv`、台账状态、`internal/interp/**`、`xfront/**`、`codegen/**`、既有测试期望 |

**是否越界**：否。写入仅 `wt/c1-rd2/impl/internal/sema/**` 与 `wt/c1-rd2/evidence/M1-ERR-01/**`；提交仅 `pod/c1-rd2`；未 push、未合并、未碰他人文件。
