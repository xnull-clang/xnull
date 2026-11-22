# `Database`

| 项 | 值 |
| --- | --- |
| 类型 | `class Database` |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | `DatabasePool`、`DatabaseConfig`、`DbBatch`、`RowMapper`、`DatabasePoolStats`、`SqlStatement`、`SqlOptions`、`SqlResult`、`SqlConnection`、`SqlTransaction`、`Context`、`Error` |
| 被依赖 | 应用服务、[`Db`](Db.md)、[`MigrationRunner`](MigrationRunner.md)、[`DatabaseHealth`](DatabaseHealth.md) |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

应用级数据库句柄：拥有连接池，按操作自动借还连接，提供单语句执行、行映射查询、批量执行、显式事务、池访问/统计与幂等关闭。

不做：ORM/实体映射、SQL 构建/解析、驱动注册、全局池、自动重连、分布式事务、每事务隔离级别、流式游标、连接级负载均衡、裸句柄导出。

---

## 2. 设计逻辑

- `Database` 是**薄门面**：唯一可变资源是 `DatabasePool`；所有操作最终落到 `SqlConnection`/`SqlTransaction`，不复制 `xdk.sql` 语义。
- 创建路径：`Db.open(context, driver, config)` 创建池并构造 `Database`，是推荐入口；`Database(DatabasePool)` 构造器主要供宿主/测试/高级包装使用，并接管池所有权。
- 自动借还：
  - `execute`/`query`/`queryOne`/`executeBatch` 每次调用借一条租约，操作结束关闭租约（归还或丢弃）；
  - 操作错误优先返回原始 SQL 错误；归还错误是诊断，不覆盖主错误；
  - 成功操作但归还失败时返回归还错误（资源状态不可忽略）。
- 显式事务：
  - `begin(context)` 委托 `DatabasePool.begin`；返回的 `SqlTransaction` 在 `commit`/`rollback`/`close` 后自动归还租约；
  - 事务打开期间调用方应只在事务上执行；不要同时用 `Database.execute` 期望同一会话；
  - 一个事务绑定一条连接；嵌套事务、保存点不支持。
- 隔离级别：
  - 池级，来自 `DatabaseConfig.isolationLevel`；`Database.begin` 不接受隔离级别参数；
  - 需要不同级别时使用独立 `Database`/`DatabasePool`；
  - 驱动不支持时 `Db.open`/`DatabasePool.open` 返回 `Unsupported`。
- 批量：
  - `executeBatch` 在**一条连接**上顺序执行，不自动开启事务；遇到第一个错误停止并返回错误，已完成语句已生效（自动提交或数据库默认），结果列表不返回；
  - `executeBatchAtomic` 在**一个事务**内顺序执行；任一失败回滚并返回错误；全部成功才提交并返回结果；
  - 两者都按 `DbBatch` 顺序返回 `List<SqlResult>`；空批次返回空列表且不借连接；
  - 同一 `SqlOptions` 应用于批次中的每条语句；需要不同控制面时拆分批次。
- 行映射：
  - `query` 要求结果是查询（`SqlResult.isQuery()=true`），先调用 `mapper.start(context, columns)`，再按行调用 `mapper.mapRow`；
  - 返回映射行数 `Int`，应用值由 mapper 实现持有；
  - `queryOne` 通过 `maxRows=1` 最多映射一行，返回是否映射到；
  - mapper 失败立即停止；已映射部分保留在 mapper 中；
  - 映射期间检查 `Context` 取消。
- 关闭：
  - `close` 幂等；关闭池；不等待活动租约；活动租约归还时关闭；
  - 关闭后新操作从池得到 `Unavailable`；
  - `Database` 不关闭驱动对象。
- 错误：
  - 参数 null/非法契约 panic；
  - 可恢复失败 `Result`；错误 kind 由 `xdk.sql`/池决定；
  - 错误文本不含 URI、口令、选项值、参数值、SQL 正文；可含池名、驱动名、行数/列数。
- 并发：
  - `Database` 线程安全；多任务可并发执行/查询/批量/事务，各自借不同连接；
  - 单条租约/事务不跨任务共享；
  - `close` 可与操作并发；在途操作可能失败 `Unavailable`/`Cancelled`；
  - 不要在 mapper 内对同一池发起需要同一连接的递归查询；池上限为 1 时可能自锁。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_pool` | `DatabasePool` | final | 拥有；关闭 `Database` 会关闭池 |

不变量：

- `_pool` 非 null；创建后不再替换。
- `Database` 不持有连接/事务/语句/结果的可变引用；每次操作独立借还。
- `isOpen()` 等价于 `!_pool.isClosed()`；关闭后不再变为打开。
- `pool()` 返回借用的池引用；调用方不得关闭它（关闭后 `Database` 也不可用）。
- `close` 幂等；第一次可能返回池关闭诊断错误，后续返回 `Ok(unit)`。
- 所有公开方法不修改传入的 `SqlStatement`/`SqlOptions`/`DbBatch`/`RowMapper`；`SqlOptions` 由执行方按次快照。
- 不暴露物理连接/驱动句柄。

---

## 4. 生命周期

`Db.open` 创建；使用期间持有池；必须 `close`。

- 创建成功：`isOpen=true`；`failFast=true` 时池已预连；`failFast=false` 时可能尚未连接。
- 使用：每个操作独立借还；事务在结束前独占一条连接。
- `close`：关闭池；幂等；不等待活动租约。关闭后 `execute`/`query`/`begin`/`borrow`/`warmUp` 等返回 `Unavailable`。
- `close` 后 `poolStats()`/`describe()` 仍可读；`pool()` 仍返回已关闭池（借用）。
- 数据库重启/网络中断：操作返回 `Network`/`Io`，池丢弃坏连接；调用方关闭旧 `Database` 并重新 `Db.open`。本类不自动重连。
- 驱动对象由调用方持有；`Database.close` 不关闭驱动。

---

## 5. 构造契约

| 构造/工厂 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Database(DatabasePool pool)` | pool | 非 null；已打开 | null → panic；接管池所有权 |
| `Db.open(Context context, SqlDriver driver, DatabaseConfig config)` | 见 [`Db`](Db.md) | 非 null；config 合法 | `Result`；失败不返回半初始化 Database |

- 推荐使用 `Db.open`；直接 `new Database(pool)` 主要供宿主/测试/高级包装，调用方必须转移池所有权并在之后只通过该 `Database` 关闭。
- `Db.open` 先创建 `DatabasePool`；失败直接返回错误，不构造 `Database`。
- `Database` 构造不执行 I/O；连接建立由池负责。
- `Database` 不接受语句/映射器/批量作为构造参数；它们是每次操作参数。

---

## 6. 字段表

见 §3；字段私有。唯一字段 `_pool` 是最终引用；池内部字段不进入 `Database` 公共契约。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `name` | 数据库/池名 | 无 | `String` | 无 | 非敏感 |
| `driverName` | 驱动名 | 无 | `String` | 无 | 打开时固定 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 | 池未关闭 |
| `pool` | 借用连接池 | 无 | `DatabasePool` | 无 | 不得关闭；生命周期归 Database |
| `poolStats` | 池统计 | 无 | `DatabasePoolStats` | 无 | 非阻塞快照 |
| `borrow` | 借出租约 | `Context context` | `Result<SqlConnection, Error>` | `Unavailable`/`Timeout`/`Cancelled`/驱动错误 | 调用方必须 `close` |
| `execute` | 单语句执行 | `Context context, SqlStatement statement` | `Result<SqlResult, Error>` | SQL/池错误 | 自动借还；等价全零 options |
| `execute` | 带选项执行 | `Context context, SqlStatement statement, SqlOptions options` | `Result<SqlResult, Error>` | 同上 | options 调用开始时快照 |
| `query` | 逐行映射 | `Context context, SqlStatement statement, RowMapper mapper` | `Result<Int, Error>` | SQL/映射/池错误 | 返回映射行数；等价全零 options |
| `query` | 带选项映射 | `Context context, SqlStatement statement, RowMapper mapper, SqlOptions options` | `Result<Int, Error>` | 同上 | 结果必须是查询 |
| `queryOne` | 映射至多一行 | `Context context, SqlStatement statement, RowMapper mapper` | `Result<Bool, Error>` | 同上 | 内部 `maxRows=1` |
| `queryOne` | 带选项映射一行 | `Context context, SqlStatement statement, RowMapper mapper, SqlOptions options` | `Result<Bool, Error>` | 同上 | 复制 options 后设 `maxRows=1` |
| `executeBatch` | 非原子批量 | `Context context, DbBatch batch` | `Result<List<SqlResult>, Error>` | SQL/池错误 | 单连接；失败停止；不自动事务 |
| `executeBatch` | 带选项非原子批量 | `Context context, DbBatch batch, SqlOptions options` | `Result<List<SqlResult>, Error>` | 同上 | 同一 options 用于每条 |
| `executeBatchAtomic` | 原子批量 | `Context context, DbBatch batch` | `Result<List<SqlResult>, Error>` | SQL/池/提交错误 | 单事务；失败回滚 |
| `executeBatchAtomic` | 带选项原子批量 | `Context context, DbBatch batch, SqlOptions options` | `Result<List<SqlResult>, Error>` | 同上 | 同一 options 用于每条 |
| `begin` | 开启事务 | `Context context` | `Result<SqlTransaction, Error>` | `Unavailable`/`Unsupported`/SQL/池错误 | 结束自动归还租约 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`/`Network`（诊断） | 幂等；不等待租约 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 不含 URI/选项 |

详细契约：

#### 通用

- 所有方法要求非 null 参数；null `context`/`statement`/`options`/`mapper`/`batch` 是合同错误（panic）。
- 关闭后 `borrow`/`execute`/`query`/`queryOne`/`executeBatch`/`executeBatchAtomic`/`begin` 返回 `Unavailable`（由池产生）；`close` 仍幂等成功。
- `SqlOptions` 在调用开始时读取；执行期间修改 options 不影响本次；批量中每条语句读取同一快照。
- 错误消息不得包含参数值、口令、完整连接串、SQL 正文；可含行数/列数/错误 kind。
- 租约归还失败：如果主操作失败，返回主错误；如果主操作成功，返回归还错误（资源状态优先暴露）。

#### `execute`

- 两参等价于三参传入全零 `SqlOptions`。
- 借一条连接，执行一条语句，关闭租约。
- SQL 语法/约束/参数错误通常 `InvalidArgument`；连接仍可用，租约归还。
- `Network`/`Io` 可能使连接不可用；租约关闭时池按 `isOpen` 丢弃。
- `Timeout`/`Cancelled` 由 `SqlOptions`/`Context` 决定；自动提交语句在超时/取消后可能已提交，需要原子性时用 `begin`。
- 不跨任务共享返回的 `SqlResult` 以外的连接；`SqlResult` 是不可变快照，可共享。

#### `query`

- 执行语句后先判断 `result.isQuery()`；false 返回 `InvalidArgument`（命令结果不能映射）。
- 调用 `mapper.start(context, result.columns())`；失败则不映射任何行。
- 逐行调用 `mapper.mapRow(context, row)`；行顺序与 `SqlResult.rows()` 一致。
- 每行前检查 `context.isCancelled()`；取消返回 `Cancelled`，已映射部分保留。
- 返回成功映射的行数 `Int`；零行返回 0。
- `maxRows` 由 options 控制；`queryOne` 额外设 `maxRows=1`（复制 options，不修改调用方对象）。
- mapper 在 `start`/`mapRow` 中返回的错误原样返回；不包装、不重试。
- 查询期间不持有池锁；mapper 可以执行其他非数据库工作。mapper 内递归查询同一池需注意容量。

#### `queryOne`

- 复制传入 options（或全零），设置 `maxRows=1`，调用 `query`。
- 返回 true 表示映射了 1 行；false 表示 0 行。不会返回多行。
- `maxRows=1` 是硬上限；若驱动无法遵守，`execute` 返回 `Unsupported`。
- mapper 的 `start` 仍会收到完整列元数据；零行时也调用。

#### `executeBatch`

- `batch.statements()` 取快照；空批次返回 `Ok([])`，不借连接。
- 借一条连接；按序执行每条语句；每条都使用同一 `SqlOptions` 快照。
- 任一条失败：停止，关闭租约，返回该错误；前面已成功的语句不会回滚（没有隐式事务）。
- 全部成功：关闭租约，返回与语句顺序一一对应的结果列表；列表是新对象，元素 `SqlResult` 不可变。
- 单连接保证会话状态连续（临时表、会话变量）在同一批次内可见；不保证跨批次。
- 失败后不返回部分结果；调用方需要部分结果时逐条 `execute`。

#### `executeBatchAtomic`

- 空批次返回 `Ok([])`，不开启事务。
- `begin(context)` 获取池化事务；按序执行；全部成功后 `commit`；返回结果列表。
- 任一执行失败：`rollback(context)`，关闭事务；返回原始执行错误；回滚错误作为诊断被忽略（主错误优先）。
- `commit` 失败：返回提交错误；事务可能结果不确定，连接由包装器按 `isOpen` 归还/丢弃；不返回结果列表。
- DDL 是否可回滚由数据库决定；数据库不支持事务性 DDL 时，回滚不能撤销已执行的 DDL。`xdk.db` 不假装原子。
- 事务期间连接独占；不要在同一事务上并发执行；不要嵌套 `begin`。
- 批量中的每条语句使用同一 `SqlOptions`；`maxRows` 对命令无意义，对查询返回结果但不被 `executeBatch` 消费。

#### `begin`

- 委托 `DatabasePool.begin`；返回的 `SqlTransaction` 已绑定一条租约。
- 事务结束（commit/rollback/close）自动归还/丢弃租约；调用方不需要关闭连接。
- 事务打开期间，连接不参与池外其他操作；同一 `Database` 的其他调用会借其他连接。
- 一个连接最多一个活动事务；再次 `begin` 会借另一条连接（不是嵌套事务），直到池上限；不要在单任务中无限嵌套。
- 隔离级别固定为池配置；`begin` 不接受级别参数。
- `commit`/`rollback` 二次调用返回 `InvalidArgument`；`close` 幂等。
- 提交/回滚发送后错误可能结果不确定；调用方以事务 `isOpen`/`Database.isOpen` 为准。

#### `borrow`

- 直接借出租约，适合需要多条语句在同一会话但不便使用事务的场景。
- 租约是池包装；`close` 归还，不是物理关闭。
- 调用方必须保证每一条成功借出的租约都被 `close`；异常路径也要关闭。
- 租约上的 `begin` 返回租约事务包装，不会自动归还租约；事务结束后仍需 `lease.close()`。若租约关闭时事务未结束或事务结束出错，池会关闭物理连接并丢弃。需要自动归还时用 `begin`。
- 租约不跨任务共享；同一时刻一个 I/O。

#### `pool` / `poolStats`

- `pool()` 返回借用引用；所有权仍归 `Database`；调用方不得 `close` 它。高级用法（`warmUp`、`acquire`、`begin`）可直接使用返回池，但关闭责任仍在 `Database`。
- `poolStats()` 委托 `stats()`；关闭后仍可读。
- `pool()` 不复制池；不要长期缓存超过 `Database` 生命周期。

#### `close`

- 委托 `DatabasePool.close`；标记关闭、关闭空闲、唤醒等待者；活动租约归还时关闭。
- 幂等；第一次可能返回 `Io`/`Network` 诊断错误；后续 `Ok(unit)`。
- `close` 不等待活动租约；不关闭驱动对象。
- `close` 与在途操作并发安全；在途操作可能收到 `Unavailable`/`Cancelled`。
- 关闭后 `poolStats`/`describe` 可读；`isOpen=false`。

#### `describe`

- 形如 `"Database(name=orders driver=postgres open=true)"`；不含 URI、用户名、选项值、SQL。
- 不输出池统计明细；需要时用 `poolStats().describe()`。

---

## 8. 使用的技术

- 门面（facade）与依赖注入；
- 自动借还（acquire/release）；
- 池化事务自动归还；
- 批量顺序执行与事务包装；
- 回调式行映射；
- 选项按次快照；
- 幂等关闭；
- 错误优先级（主错误 vs 归还诊断）；
- 无全局状态、无裸句柄。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Bool、Long、String、Result、Unit；
- 运行时：`List.copy`、`str(Int)`、`str(Bool)`；
- 驱动/池：`DatabasePool.acquire/begin/stats/close`、`SqlConnection.execute`、`SqlTransaction.execute/commit/rollback/close`；
- 接口：`DatabasePool`、`DatabasePoolStats`、`DbBatch`、`RowMapper`、`SqlStatement`、`SqlOptions`、`SqlResult`、`SqlRow`、`SqlConnection`、`SqlTransaction`、`Context`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

[`DatabasePool`](DatabasePool.md)、[`DatabasePoolStats`](DatabasePoolStats.md)、[`DatabaseConfig`](DatabaseConfig.md)、[`DbBatch`](DbBatch.md)、[`RowMapper`](RowMapper.md)、[`Db`](Db.md)、[`SqlStatement`](../../network/sql/SqlStatement.md)、[`SqlOptions`](../../network/sql/SqlOptions.md)、[`SqlResult`](../../network/sql/SqlResult.md)、[`SqlRow`](../../network/sql/SqlRow.md)、[`SqlConnection`](../../network/sql/SqlConnection.md)、[`SqlTransaction`](../../network/sql/SqlTransaction.md)、[`Context`](../../core/execution/Context.md)、[`Error`](../../core/errors/Error.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

- `Database` 拥有池；池拥有物理连接；驱动借用；调用方拥有 `Database`。
- `Database` 线程安全；可跨任务共享；每次操作独立借还。
- 单条租约/事务不跨任务共享；事务打开期间连接独占。
- `close` 可与其他方法并发；关闭后新操作失败；在途操作可能被取消/失败。
- 语句/选项/mapper/batch 借用；`SqlOptions` 调用开始时快照；`DbBatch` 执行开始时快照。
- `SqlResult` 返回所有权给调用方，不可变，可共享。
- `pool()` 返回借用引用，不转移所有权；不得关闭。
- 相等：引用身份；不提供 `equals`；不同 `Database` 永不相等。
- 无裸句柄；所有权不通过句柄转移。

---

## 12. 示例与反例

正确：

```text
Database database = Db.open(context, driver, config).value()

Result<SqlResult, Error> result = database.execute(context, statement)

UserRowMapper mapper = new UserRowMapper()
Result<Int, Error> mapped = database.query(context, queryStatement, mapper)
```

```text
Result<SqlTransaction, Error> started = database.begin(context)
if started.isOk() {
    SqlTransaction transaction = started.value()
    Result<SqlResult, Error> inserted =
        transaction.execute(context, insertStatement)
    if inserted.isOk() {
        transaction.commit(context)
    } else {
        transaction.rollback(context)
    }
}
```

```text
DbBatch batch = new DbBatch().add(statementA).add(statementB)
Result<List<SqlResult>, Error> applied =
    database.executeBatchAtomic(context, batch)
```

反例：

- 在 `database.begin` 的事务打开期间，用 `database.execute` 期望同一会话；会借另一条连接，不是同一事务。
- 事务忘记 `commit`/`rollback`/`close`；租约泄漏直到池耗尽。
- 在 mapper 中递归查询同一池且池上限为 1；可能自锁。
- 把 `executeBatch` 当原子操作；失败不会回滚已执行语句。
- 用 `executeBatchAtomic` 执行不支持事务性 DDL 的迁移并期望完整回滚。
- 关闭 `database.pool()` 返回的池；`Database` 随即不可用。
- 关闭后继续 `execute`；应处理 `Unavailable`。
- 用 `Database` 做全局单例跨不同配置共享；每个配置独立句柄。
- 期望 `query` 返回命令结果；命令结果用 `execute`。
- 期望 `queryOne` 在零行时返回错误；它返回 `Ok(false)`。
- 把 `SqlOptions` 跨任务共享并在执行中修改；执行方只读快照，但共享可变对象易出错。
- 把 URI/参数值拼进错误文本。

---

## 13. 测试/场景义务

- `Db.open` 成功/失败；`Database` 不泄漏池；
- `execute` 两参/三参、查询/命令、错误、超时、取消；租约归还；
- `query` 零行/单行/多行；`isQuery=false` 失败；mapper `start` 失败/`mapRow` 失败；取消；返回行数；
- `queryOne` 零行/一行/多行（最多一行）；options 复制不改原对象；`maxRows` 覆盖；
- `executeBatch` 空/单条/多条/中途失败；顺序；结果列表；会话状态连续；不自动事务；
- `executeBatchAtomic` 空/成功/失败回滚/提交失败；DDL 不可回滚场景文档化；
- `begin` 成功/失败；commit/rollback/close 自动归还；二次 commit/rollback 失败；提交后错误丢弃连接；事务期间其他调用借新连接；
- `borrow` 租约关闭幂等；关闭后 execute/begin 失败；`pool()` 借用/不得关闭；
- `poolStats` 快照/关闭后读取；`close` 幂等/活动租约/并发；
- 关闭后所有操作 `Unavailable`；
- 并发 execute/query/batch/begin/close；无全局状态；两个 Database 互不影响；
- 错误文本不含 URI/参数值/SQL；
- 无裸句柄；无 ORM/反射。

---

## 14. XNull 伪代码

```xnull
class Database {
    final DatabasePool _pool

    Database(DatabasePool pool) {
        if pool == null {
            throw "Database: null pool"
        }
        _pool = pool
    }

    String name() { return _pool.name() }
    String driverName() { return _pool.driverName() }
    Bool isOpen() { return !_pool.isClosed() }
    DatabasePool pool() { return _pool }
    DatabasePoolStats poolStats() { return _pool.stats() }

    Result<SqlConnection, Error> borrow(Context context) {
        if context == null { throw "Database.borrow: null context" }
        return _pool.acquire(context)
    }

    Result<SqlResult, Error> execute(Context context, SqlStatement statement) {
        return execute(context, statement, new SqlOptions())
    }

    Result<SqlResult, Error> execute(Context context, SqlStatement statement,
            SqlOptions options) {
        if context == null || statement == null || options == null {
            throw "Database.execute: null argument"
        }
        Result<SqlConnection, Error> acquired = _pool.acquire(context)
        if acquired.isErr() {
            return Err(acquired.error())
        }
        SqlConnection lease = acquired.value()
        Result<SqlResult, Error> executed =
            lease.execute(context, statement, options)
        if executed.isErr() {
            lease.close()
            return Err(executed.error())
        }
        SqlResult result = executed.value()
        Result<Unit, Error> released = lease.close()
        if released.isErr() {
            return Err(released.error())
        }
        return Ok(result)
    }

    Result<Int, Error> query(Context context, SqlStatement statement,
            RowMapper mapper) {
        return query(context, statement, mapper, new SqlOptions())
    }

    Result<Int, Error> query(Context context, SqlStatement statement,
            RowMapper mapper, SqlOptions options) {
        if context == null || statement == null || mapper == null
                || options == null {
            throw "Database.query: null argument"
        }
        Result<SqlConnection, Error> acquired = _pool.acquire(context)
        if acquired.isErr() {
            return Err(acquired.error())
        }
        SqlConnection lease = acquired.value()
        Result<SqlResult, Error> executed =
            lease.execute(context, statement, options)
        if executed.isErr() {
            lease.close()
            return Err(executed.error())
        }
        SqlResult result = executed.value()
        if !result.isQuery() {
            lease.close()
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Database.query: result is not a query"))
        }
        Result<Unit, Error> started = mapper.start(context, result.columns())
        if started.isErr() {
            lease.close()
            return Err(started.error())
        }
        List<SqlRow> rows = result.rows()
        Int mapped = 0
        Int index = 0
        while index < rows.length() {
            if context.isCancelled() {
                lease.close()
                return Err(new BasicError(ErrorKind.Cancelled,
                    "Database.query: cancelled"))
            }
            Result<Unit, Error> mappedRow =
                mapper.mapRow(context, rows.get(index))
            if mappedRow.isErr() {
                lease.close()
                return Err(mappedRow.error())
            }
            mapped = mapped + 1
            index = index + 1
        }
        Result<Unit, Error> released = lease.close()
        if released.isErr() {
            return Err(released.error())
        }
        return Ok(mapped)
    }

    Result<Bool, Error> queryOne(Context context, SqlStatement statement,
            RowMapper mapper) {
        return queryOne(context, statement, mapper, new SqlOptions())
    }

    Result<Bool, Error> queryOne(Context context, SqlStatement statement,
            RowMapper mapper, SqlOptions options) {
        if options == null {
            throw "Database.queryOne: null options"
        }
        SqlOptions one = options.copy()
        one.maxRows(1)
        Result<Int, Error> mapped = query(context, statement, mapper, one)
        if mapped.isErr() {
            return Err(mapped.error())
        }
        return Ok(mapped.value() > 0)
    }

    Result<List<SqlResult>, Error> executeBatch(Context context, DbBatch batch) {
        return executeBatch(context, batch, new SqlOptions())
    }

    Result<List<SqlResult>, Error> executeBatch(Context context, DbBatch batch,
            SqlOptions options) {
        if context == null || batch == null || options == null {
            throw "Database.executeBatch: null argument"
        }
        List<SqlStatement> statements = batch.statements()
        if statements.length() == 0 {
            return Ok([])
        }
        Result<SqlConnection, Error> acquired = _pool.acquire(context)
        if acquired.isErr() {
            return Err(acquired.error())
        }
        SqlConnection lease = acquired.value()
        List<SqlResult> results = []
        Int index = 0
        while index < statements.length() {
            Result<SqlResult, Error> executed =
                lease.execute(context, statements.get(index), options)
            if executed.isErr() {
                lease.close()
                return Err(executed.error())
            }
            results.push(executed.value())
            index = index + 1
        }
        Result<Unit, Error> released = lease.close()
        if released.isErr() {
            return Err(released.error())
        }
        return Ok(results)
    }

    Result<List<SqlResult>, Error> executeBatchAtomic(Context context,
            DbBatch batch) {
        return executeBatchAtomic(context, batch, new SqlOptions())
    }

    Result<List<SqlResult>, Error> executeBatchAtomic(Context context,
            DbBatch batch, SqlOptions options) {
        if context == null || batch == null || options == null {
            throw "Database.executeBatchAtomic: null argument"
        }
        List<SqlStatement> statements = batch.statements()
        if statements.length() == 0 {
            return Ok([])
        }
        Result<SqlTransaction, Error> started = begin(context)
        if started.isErr() {
            return Err(started.error())
        }
        SqlTransaction transaction = started.value()
        List<SqlResult> results = []
        Int index = 0
        while index < statements.length() {
            Result<SqlResult, Error> executed =
                transaction.execute(context, statements.get(index), options)
            if executed.isErr() {
                transaction.rollback(context)
                transaction.close()
                return Err(executed.error())
            }
            results.push(executed.value())
            index = index + 1
        }
        Result<Unit, Error> committed = transaction.commit(context)
        if committed.isErr() {
            return Err(committed.error())
        }
        return Ok(results)
    }

    Result<SqlTransaction, Error> begin(Context context) {
        if context == null { throw "Database.begin: null context" }
        return _pool.begin(context)
    }

    Result<Unit, Error> close() {
        return _pool.close()
    }

    String describe() {
        String openText = "false"
        if !_pool.isClosed() {
            openText = "true"
        }
        return "Database(name=" + _pool.name()
            + " driver=" + _pool.driverName()
            + " open=" + openText + ")"
    }
}
```

> 伪代码非可执行。`queryOne` 通过复制 options 设置 `maxRows=1`，不修改调用方对象；批量结果列表是新对象，元素 `SqlResult` 不可变。推荐入口是 [`Db.open`](Db.md)；直接构造 `Database(pool)` 会接管池所有权。
