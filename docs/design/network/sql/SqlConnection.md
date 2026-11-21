# `SqlConnection`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol SqlConnection` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SqlDialect`、`SqlStatement`、`SqlOptions`、`SqlResult`、`SqlTransaction`、`Error` |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

单个逻辑数据库会话：报告方言、自动提交执行、开始显式事务、关闭。

不做：连接池、驱动注册、SQL 构建/解析、嵌套事务、流式游标、自动重连、健康检查、裸句柄导出。

---

## 2. 设计逻辑

- 连接由 `SqlDriver.open` 创建；打开后 `isOpen=true`，关闭后 `isOpen=false`。
- 基线保留 `execute(Context, SqlStatement)`；它在无活动事务时自动提交，等价于传入全零 `SqlOptions`。
- 另提供 `execute(Context, SqlStatement, SqlOptions)` 重载，承载单次超时/行数/取数提示；不把 options 塞进语句。
- `begin(Context)` 创建一个 `SqlTransaction`；事务打开期间连接不直接执行，避免自动提交与显式事务交错。
- 一个连接最多一个活动事务；事务结束（commit/rollback/close）后连接恢复自动提交。
- 连接不跨任务共享业务操作；同一时刻一个 I/O 操作；实现必须允许另一个任务仅调用 `close` 中止连接自身的在途 `execute`/`begin`。
- 方言在连接生命周期内固定；`dialect()` 是元数据，关闭后仍可读取。
- 关闭后 I/O 返回 `InvalidArgument`（状态非法）；不引入 `Unavailable`。
- 不暴露驱动句柄；实现内部可用不透明 `Long`，协议不声明。
- 失败的语句 `InvalidArgument` 不关闭连接；`Network`/`Io` 可能使连接不可用，以 `isOpen` 为准。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `dialect()` 在连接生命周期内返回同一值；非 null。
- `isOpen()` 初始为 true；`close()` 成功后为 false。
- 活动事务最多一个；事务打开时 `execute` 与再次 `begin` 返回 `InvalidArgument`。
- 事务结束后活动事务清空；连接可再次 `begin` 或直接 `execute`。
- `execute` 返回完整 `SqlResult` 快照，不返回活游标。
- 语句与参数不被修改；`SqlStatement` 不可变。
- 三参 `execute` 在调用开始时读取 `SqlOptions` 三个数值；之后修改 options 不影响本次执行。
- 实现不得把裸句柄/文件描述符/指针暴露给调用方。

---

## 4. 生命周期

`SqlDriver.open` 创建并返回；使用期间保持打开；必须 `close`；`close` 幂等。

- 关闭后 `dialect()` 仍可读；`execute`/`begin` 返回 `InvalidArgument`。
- 关闭时有活动事务：先尽力 rollback，再释放连接；无论 rollback 是否成功，连接都已关闭。
- 关闭时 rollback 失败：`close` 返回该错误；再次 `close` 返回 `Ok(unit)`。
- 致命 I/O/网络错误后，驱动可主动把 `isOpen` 置为 false；调用方应关闭并重新 `open`。

---

## 5. 构造契约

协议无构造。唯一创建路径是 [`SqlDriver.open`](SqlDriver.md)：

- 成功返回的连接必须已打开、`dialect()` 可用、可执行。
- 失败必须返回 `Err`，不得返回半打开连接。
- 实现类可以有不公开的构造；不得要求调用方直接 `new` 连接实现。

---

## 6. 字段表

无协议字段。实现内部字段不进入公共契约；句柄必须以不透明 `Long` 或私有对象保存。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `dialect` | 方言元数据 | 无 | `SqlDialect` | 无 | 生命周期内固定；关闭后可读 |
| `execute` | 自动提交执行 | `Context context, SqlStatement statement` | `Result<SqlResult, Error>` | `InvalidArgument`/`PermissionDenied`/`Unsupported`/`Network`/`Io`/`Timeout`/`Cancelled` | 无活动事务；等价全零 options |
| `execute` | 带选项执行 | `Context context, SqlStatement statement, SqlOptions options` | `Result<SqlResult, Error>` | 同上 | options 调用开始时快照 |
| `begin` | 开始事务 | `Context context` | `Result<SqlTransaction, Error>` | `InvalidArgument`/`PermissionDenied`/`Unsupported`/`Network`/`Io`/`Timeout`/`Cancelled` | 一个连接最多一个活动事务 |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 | 关闭/致命错误后 false |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`/`Network`（诊断） | 幂等；有事务先尽力 rollback |

详细契约：

- 所有方法要求非 null 参数；null `context`/`statement`/`options` 是合同错误（panic）。
- `dialect` 不执行 I/O；关闭后仍返回固定方言。
- `execute` 前置条件：`isOpen=true` 且无活动事务。关闭或事务打开时返回 `InvalidArgument`。
- 两参 `execute` 使用全零 options：无超时、无行数上限、驱动默认 fetch size。
- 三参 `execute` 必须在发送语句前读取 options 数值；`timeoutMillis` 与 `Context` 截止时间同时存在时先到者生效；`maxRows` 是硬上限；`fetchSize` 是提示。实现无法遵守 `maxRows`/`timeout` 时返回 `Unsupported`，不得静默忽略。
- SQL 语法错误、约束冲突、参数数量/类型不匹配：`InvalidArgument`；连接通常仍可用。
- 权限/认证：`PermissionDenied`；缺少能力：`Unsupported`；网络：`Network`；本地 I/O：`Io`；截止：`Timeout`；显式取消：`Cancelled`。
- 错误消息不得包含参数值、口令、完整连接串；可含 SQL 状态/位置/列名，便于诊断。
- 自动提交语句在 `Timeout`/`Cancelled` 后可能已提交，结果不确定；需要原子性时使用显式事务。
- `Network`/`Io` 后连接可能已关闭；调用方必须检查 `isOpen`，为 false 时丢弃连接。
- `begin` 前置条件：打开且无活动事务；驱动不支持事务返回 `Unsupported`。事务打开后独占连接，连接 `execute`/再次 `begin` 返回 `InvalidArgument`。
- `begin` 不接受隔离级别/只读选项；这些属于驱动 open options 或后续扩展。
- `close` 幂等；有活动事务时先尽力 rollback，再释放。对已结束或已中止的事务按成功关闭处理；只透传 rollback/释放的 `Io`/`Network` 诊断错误。`close` 不接收 `Context`，实现应尽快返回，不得无限等待。
- `close` 不得与活动事务的 `commit`/`rollback` 并发；调用方必须先结束事务或等待其返回。
- `close` 与连接自身的 `execute`/`begin` 可并发；在途操作应返回 `Cancelled`，已开始释放后不得再访问已释放资源。活动事务的 `execute`/`commit`/`rollback`/`close` 必须在 `close` 前结束。

---

## 8. 使用的技术

- 会话状态机（打开/事务中/关闭）；
- 自动提交与显式事务切换；
- 事务独占连接；
- 参数绑定（由驱动实现）；
- 结果快照；
- 相对超时与 Context 截止时间合并；
- 幂等关闭与在途取消；
- 不透明句柄封装。

---

## 9. 需要的支撑

- 语言：protocol、Result、Bool、Unit、String、Long；
- 运行时/驱动：数据库会话、语句执行、事务命令、结果集读取、取消；实现内部可用不透明 `Long` 句柄；
- 接口：`Context`、`SqlDialect`、`SqlStatement`、`SqlOptions`、`SqlResult`、`SqlTransaction`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

[`SqlDialect`](SqlDialect.md)、[`SqlStatement`](SqlStatement.md)、[`SqlOptions`](SqlOptions.md)、[`SqlResult`](SqlResult.md)、[`SqlTransaction`](SqlTransaction.md)、[`Context`](../../core/execution/Context.md)、[`Error`](../../core/errors/Error.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。由 [`SqlDriver.open`](SqlDriver.md) 创建。

---

## 11. 所有权与并发

- 连接拥有数据库会话；调用方拥有连接对象，必须 `close`。
- 不可跨任务共享业务操作；同一时刻一个 `execute`/`begin`；实现应拒绝或串行化并发 I/O；`close` 是唯一允许从另一个任务调用的方法。
- `close` 可与连接自身的 `execute`/`begin` 并发以中止在途操作；不得与活动事务的 `execute`/`commit`/`rollback`/`close` 并发。
- 事务打开期间，事务独占连接；连接对象仍归调用方，但连接 I/O 必须经事务。
- `SqlStatement` 借用且不可变，实现可在调用期间安全读取；`SqlOptions` 在调用开始时快照；`Context` 借用。
- 相等：协议引用身份；不提供 `equals`；不同连接永不相等。
- 无裸句柄；所有权不通过句柄转移。

---

## 12. 示例与反例

正确：`driver.open(context, connectionUri, openOptions)` 后 `connection.execute(context, statement)`；带控制面时 `connection.execute(context, statement, options)`；需要多条语句原子性时 `connection.begin(context)`。  
反例：跨任务共享同一连接；事务打开时仍在连接上 `execute`；`close` 后继续执行；忽略 `isOpen` 复用网络错误后的连接；把 `rowsAffected` 当查询行数；在 `close` 与事务 `commit` 之间并发；把驱动句柄暴露给业务层。

---

## 13. 测试/场景义务

open 后 `isOpen=true`/`dialect` 固定；查询/命令执行；索引/命名参数；两参/三参 options；超时/取消；`maxRows` 截断；`fetchSize` 提示；begin 后第二次 begin 失败；事务中连接 execute 失败；commit/rollback 后连接恢复；close 幂等；关闭后 execute/begin `InvalidArgument`；关闭后 dialect 可读；有事务时 close 触发 rollback；rollback 失败仍关闭；`Network`/`Io` 后 `isOpen` 状态；并发 close 中止在途 execute；无裸句柄。

---

## 14. XNull 伪代码

```xnull
protocol SqlConnection {
    SqlDialect dialect();
    Result<SqlResult, Error> execute(Context context, SqlStatement statement);
    Result<SqlResult, Error> execute(Context context, SqlStatement statement,
        SqlOptions options);
    Result<SqlTransaction, Error> begin(Context context);
    Bool isOpen();
    Result<Unit, Error> close();
}
```
