# `SqlTransaction`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol SqlTransaction` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SqlStatement`、`SqlOptions`、`SqlResult`、`Error` |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

显式事务作用域：在事务内执行语句、提交、回滚、关闭。

不做：嵌套事务、保存点、隔离级别设置、只读事务、分布式事务、连接池借还、自动重试。

---

## 2. 设计逻辑

- 由 [`SqlConnection.begin`](SqlConnection.md) 创建；创建后立即进入打开状态。
- 事务打开期间独占连接的会话；连接不直接执行，事务是唯一执行入口。
- `execute` 在事务内运行，不自动提交；两参是基线签名，三参重载承载 `SqlOptions`，语义与连接一致。
- `commit`/`rollback` 结束事务；成功后 `isOpen=false`，连接恢复自动提交。
- `close` 对未结束事务先尽力 rollback，再释放；`close` 幂等。
- `commit`/`rollback` 只允许一次；第二次返回 `InvalidArgument`。
- 提交是危险边界：发送 COMMIT 前检查取消；发送前已取消则保持打开，发送后的任何错误都可能留下“结果不确定”的事务。
- 提交/回滚在发送后出错则事务结束（`isOpen=false`）；连接是否可复用由驱动判断，调用方以 `connection.isOpen()` 为准。
- 状态机：`Open`（可执行/可提交/可回滚）、`Finished`（已提交/已回滚/已关闭）、`Indeterminate`（提交/回滚结果未知，`isOpen=false`）。
- 不暴露连接或驱动句柄；实现内部可持有连接引用与不透明 `Long` 句柄。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `isOpen()` 在 `begin` 成功后为 true；在 commit/rollback/close 后为 false（提交/回滚发送前取消除外）。
- 事务打开期间只允许一个 `execute`/`commit`/`rollback`；不得重入。
- 一个连接最多一个活动事务；事务打开时连接 `execute` 返回 `InvalidArgument`。
- `commit`/`rollback` 成功后事务不可再用；再次调用返回 `InvalidArgument`。
- `commit`/`rollback` 在发送后返回错误则事务已结束；结果可能不确定时 `isOpen=false`，连接由驱动判定是否可复用。
- `close` 幂等；第一次关闭未结束事务时尝试 rollback；再次关闭返回 `Ok(unit)`。
- 连接关闭会使事务失效；事务后续 `execute`/`commit`/`rollback` 返回 `InvalidArgument`，`close` 仍幂等返回 `Ok(unit)`。
- 不暴露裸句柄/文件描述符/指针。

---

## 4. 生命周期

`SqlConnection.begin` 创建；使用到 commit/rollback/close；结束后不可重用。

- 提交成功：`Finished`；连接可继续自动提交执行。
- 回滚成功：`Finished`；连接可继续自动提交执行。
- `close` 且未结束：先 rollback，再 `Finished`；rollback 失败仍结束并返回错误。
- 提交/回滚在发送后失败：可能进入 `Indeterminate`；调用方以 `connection.isOpen()` 为准，无法确认结果时关闭连接并重新 `open`。
- 连接先关闭：事务立即失效；后续 `execute`/`commit`/`rollback` 返回 `InvalidArgument`，`close` 仍返回 `Ok(unit)`。

---

## 5. 构造契约

协议无构造。唯一创建路径是 [`SqlConnection.begin`](SqlConnection.md)：

- 成功返回的事务必须处于打开状态，且绑定到该连接。
- `begin` 失败不得返回半打开事务。
- 实现类可以有不公开的构造；不得要求调用方直接 `new` 事务实现。
- 事务不接受隔离级别/只读参数；这些属于驱动 open options 或后续扩展。

---

## 6. 字段表

无协议字段。实现内部字段不进入公共契约；连接引用与句柄必须私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `execute` | 事务内执行 | `Context context, SqlStatement statement` | `Result<SqlResult, Error>` | `InvalidArgument`/`PermissionDenied`/`Unsupported`/`Network`/`Io`/`Timeout`/`Cancelled` | 不自动提交；等价全零 options |
| `execute` | 带选项执行 | `Context context, SqlStatement statement, SqlOptions options` | `Result<SqlResult, Error>` | 同上 | options 调用开始时快照 |
| `commit` | 提交 | `Context context` | `Result<Unit, Error>` | `InvalidArgument`/`Network`/`Io`/`Timeout`/`Cancelled` | 成功后结束；失败可能不确定 |
| `rollback` | 回滚 | `Context context` | `Result<Unit, Error>` | `InvalidArgument`/`Network`/`Io`/`Timeout`/`Cancelled` | 成功后结束；发送后失败仍结束 |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 | 结束后 false |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`/`Network`（诊断） | 幂等；未结束先 rollback |

详细契约：

- 所有方法要求非 null 参数；null `context`/`statement`/`options` 是合同错误（panic）。
- `execute` 前置条件：`isOpen=true`；否则 `InvalidArgument`。
- 三参 `execute` 的 `timeoutMillis`/`maxRows`/`fetchSize` 语义与连接一致；`maxRows` 是硬上限，`fetchSize` 是提示；无法遵守时返回 `Unsupported`。
- SQL 语法/约束/参数错误：`InvalidArgument`；事务可能被数据库标记为 aborted，调用方应 `rollback`。事务对象仍可 `rollback` 时 `isOpen=true`。
- 错误消息不得包含参数值、口令、完整连接串；可含 SQL 状态/位置/列名，便于诊断。
- `Network`/`Io` 后事务可能失效；调用方必须检查 `isOpen`，为 false 时关闭连接。
- `Timeout`/`Cancelled` 对单条语句：若数据库已取消语句，事务可继续；若驱动无法保证，事务进入 `Indeterminate` 并 `isOpen=false`。以 `isOpen` 为准。
- `commit` 前置条件：`isOpen=true`。实现必须在发送 COMMIT 前检查 `context`：已取消则返回 `Cancelled`，事务保持打开，调用方可改走 rollback。
- COMMIT 发送后，任何错误（`InvalidArgument`/`Network`/`Io`/`Timeout`/`Cancelled`）都使事务结束（`isOpen=false`），结果可能不确定。驱动能证明数据库已回滚且会话同步时，可保持 `connection.isOpen=true`；否则必须关闭连接。调用方以 `connection.isOpen()` 为准。
- `rollback` 前置条件：`isOpen=true`。实现必须在发送 ROLLBACK 前检查 `context`：已取消则返回 `Cancelled`，事务保持打开；发送后失败同样结束事务；网络/IO 失败应关闭连接。`rollback` 成功只表示数据库确认回滚，不提供其他保证。
- `commit`/`rollback`/`execute` 在 `isOpen=false` 时返回 `InvalidArgument`；`commit` 二次调用不是幂等成功。
- `close` 幂等；未结束时先尽力 rollback，再释放。`rollback` 失败时 `close` 返回该错误，但事务已结束；再次 `close` 返回 `Ok(unit)`。对已结束或已中止事务按成功关闭处理；只透传 rollback 的 `Io`/`Network` 诊断错误。`close` 返回 `Ok(unit)` 只表示事务对象已结束，不代表提交结果确定或连接可复用；`Indeterminate` 后仍需检查 `connection.isOpen()`。
- `close` 不接收 `Context`，应尽快返回；不得无限等待。
- `close` 不得与 `execute`/`commit`/`rollback` 并发；调用方必须串行化这些操作。事务不跨任务共享。

---

## 8. 使用的技术

- 事务状态机；
- 连接会话独占；
- 提交前取消检查；
- 提交后结果不确定处理；
- 尽力回滚；
- 幂等关闭；
- 结果快照；
- 不透明句柄封装。

---

## 9. 需要的支撑

- 语言：protocol、Result、Bool、Unit、String；
- 运行时/驱动：BEGIN/COMMIT/ROLLBACK、语句执行、取消、事务状态跟踪；实现内部可用不透明 `Long` 句柄；
- 接口：`Context`、`SqlStatement`、`SqlOptions`、`SqlResult`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

[`SqlStatement`](SqlStatement.md)、[`SqlOptions`](SqlOptions.md)、[`SqlResult`](SqlResult.md)、[`Context`](../../core/execution/Context.md)、[`Error`](../../core/errors/Error.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。由 [`SqlConnection.begin`](SqlConnection.md) 创建。

---

## 11. 所有权与并发

- 事务在打开期间独占连接的会话；调用方拥有事务对象，必须 commit/rollback/close。
- 不可跨任务共享；同一时刻一个操作；`execute`/`commit`/`rollback`/`close` 不得并发重入。
- `close` 与 `commit`/`rollback` 必须串行；与 `execute` 也应由调用方串行化，避免回滚与执行交错。
- 连接关闭会使事务失效；事务不拥有连接对象的生命周期。
- `SqlStatement` 借用且不可变；`SqlOptions` 调用开始时快照；`Context` 借用。
- 相等：协议引用身份；不提供 `equals`；不同事务永不相等。
- 无裸句柄；所有权不通过句柄转移。

---

## 12. 示例与反例

正确：`connection.begin(context)` 后 `transaction.execute(context, statement)`，全部成功再 `commit(context)`；异常路径 `rollback(context)`；提前退出用 `close()`。  
反例：忘记 commit/rollback 直接丢弃（资源泄漏）；commit 二次调用期望幂等；事务中再 `begin`；事务打开时在连接上 `execute`；commit 超时后继续复用连接而不检查 `isOpen`；在 commit 在途时并发 `close` 事务；把 `close` 当提交。

---

## 13. 测试/场景义务

begin 后 `isOpen=true`；事务内查询/命令；commit 成功；rollback 成功；close 未结束自动 rollback；close 幂等；commit/rollback 二次调用失败；结束后 execute 失败；连接 close 使事务失效；连接事务中 execute 失败；提交前取消保持打开；提交发送后超时/取消结束且 `isOpen=false`；提交约束错误后的连接状态；rollback 网络错误关闭连接；options 超时/`maxRows`；并发重入拒绝；无裸句柄。

---

## 14. XNull 伪代码

```xnull
protocol SqlTransaction {
    Result<SqlResult, Error> execute(Context context, SqlStatement statement);
    Result<SqlResult, Error> execute(Context context, SqlStatement statement,
        SqlOptions options);
    Result<Unit, Error> commit(Context context);
    Result<Unit, Error> rollback(Context context);
    Bool isOpen();
    Result<Unit, Error> close();
}
```
