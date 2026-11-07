# ERR-01 检查表（逐项抄自台账验收要点，不得漏项）

> 台账行：`XNull一致性用例台账-v1.0.0.md:26`
> 原文：错误处理；`Result` 构造/成员/`@mustUse`；`try` 传播与错误类型检查；`defer` / `errdefer` 的 LIFO、触发条件和清理体限制；`isOk` / `isErr` / `value` / `error` 的正确使用
> 基线：`pod/c1-rd2` @ `81ec33d`；主责 CEO1-RD2；会签 CEO1-QA1

## 一、12 项主检查表

| # | 台账要点（逐字） | 规范子项（S1 §10） | 现状 | 本轮处置 |
|---|---|---|---|---|
| ERR01-01 | `Result` 构造 | `Ok(value)`；`Ok()` 仅 `Result<void,E>`；`Err(error)`；`E` 不能 `void`；按目标类型推断；无目标类型必须显式/有上下文 | 部分：构造器返回 `Result<,>`，参数类型不查，无目标不报 | 实现 + 新增用例 |
| ERR01-02 | `Result` 成员 | `isOk()`/`isErr()` 无参；`value()`/`error()` 无参；`unwrapOr(T)` 恰一参且可赋给 `T`；`T/E=void` 时对应成员不可用；未知成员拒绝 | 部分：返回类型有，但 arity/void/未知成员不查 | 实现 + 新增用例 |
| ERR01-03 | `@mustUse` | 裸表达式语句丢弃 `Result` 为编译错误；返回/赋值/字段/容器/`try`/成员调用为合法使用；`defer` 体内未处理 `Result` 同样诊断 | 未实现：`ExprStmt` 只推断不判丢弃 | 实现 + 新增用例 |
| ERR01-04 | `try` 传播 | 仅作用于 `Result`；成功解包 `T`；失败从当前函数/闭包返回 `Err`；外层必须返回 `Result<_,E2>`；`E` 可赋给 `E2`；`Result<void,E>` 可作语句；可嵌套；禁止构造器/`deinit`/`main`/`defer`/`errdefer`；闭包目标必须 `Result` | 部分：只解包，不查上下文/错误类型/禁用位置 | 实现 + 新增用例 |
| ERR01-05 | 错误类型检查 | `Result<T,E>` 必须两个实参；`E != void`；`T` 可为 `void`；构造/`try`/赋值处 `T`、`E` 必须匹配；禁止隐式字符串化 | 部分：`Result<,>` 一律放行；`Result<Int,void>` 不拒 | 实现 + 新增用例 |
| ERR01-06 | `defer`/`errdefer` 的 LIFO | 同一作用域按注册逆序执行；错误路径 `defer` 与 `errdefer` 都执行；正常路径只执行 `defer` | 已覆盖 | 既有 `hard_test.go` 用例，不改 |
| ERR01-07 | `defer`/`errdefer` 的触发条件 | 正常作用域结束/`return`/`try`/`break`/`continue` 执行；`throw`/`goto`/进程退出不执行；`errdefer` 仅在函数/闭包以 `Err` 返回时执行；`errdefer` 只能出现在返回 `Result` 的函数/闭包 | 部分：运行时触发已覆盖；`errdefer` 上下文无编译检查 | 新增编译期检查 + 用例 |
| ERR01-08 | `defer`/`errdefer` 的清理体限制 | 体（含嵌套花括号）不得含 `return`/`break`/`continue`/`goto`/`try`/`throw`/`defer`/`errdefer`；不得分配闭包；单条语句体不得是局部声明 | 未实现：全部静默 | 实现 + 新增用例 |
| ERR01-09 | `isOk` 正确使用 | 无条件检查成功；无参；返回 `Bool` | 正向已覆盖；arity 未查 | 既有 `interp_test.go` 正向 + 新增 arity 用例 |
| ERR01-10 | `isErr` 正确使用 | 无条件检查失败；无参；返回 `Bool` | 正向已覆盖；arity 未查 | 同上 |
| ERR01-11 | `value` 正确使用 | 仅 `T != void`；无参；Err 上调用运行时 panic（§10.1） | 正向已覆盖；arity/void 未查；运行期 panic 行为已实现 | 新增编译负例 + 运行期证据（只读探针） |
| ERR01-12 | `error` 正确使用 | 仅 `E != void`；无参；Ok 上调用运行时 panic（§10.1） | 正向已覆盖；arity/void 未查；运行期 panic 行为已实现 | 同上 |

## 二、本轮新增用例映射（红→绿）

文件：`impl/internal/sema/err01_test.go`

| 用例 | 覆盖 |
|---|---|
| `TestERR01ResultConstructionPositive` | ERR01-01/05 正向 |
| `TestERR01ResultConstructionNegative` | ERR01-01/05 负向 |
| `TestERR01ResultMembersPositive` | ERR01-02/09—12 正向 |
| `TestERR01ResultMembersNegative` | ERR01-02/09—12 负向 |
| `TestERR01MustUse` | ERR01-03 |
| `TestERR01TryPositive` | ERR01-04 正向（含嵌套、`Result<void,E>`） |
| `TestERR01TryNegative` | ERR01-04 负向（上下文/错误类型/禁用位置） |
| `TestERR01ErrorTypeVoid` | ERR01-05（`E=void`、实参数量） |
| `TestERR01CleanupRestrictions` | ERR01-08 |
| `TestERR01ErrdeferContext` | ERR01-07 编译期 |
| `TestERR01LambdaTry` | ERR01-04 闭包规则 |

## 三、证据与验收口径

- 红输出：`evidence/M1-ERR-01/before/`（本检查表生成后、实现前）。
- 绿输出：`evidence/M1-ERR-01/after/`；全量包测试、示例双路径、确定性。
- 不改既有测试期望、不删测试；`status.tsv` 与台账状态由 CEO1/QA1 改，本卡不手改。
