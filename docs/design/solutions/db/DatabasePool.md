# `DatabasePool`

| 项 | 值 |
| --- | --- |
| 类型 | `class DatabasePool` |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | `SqlDriver`、`SqlConnection`、`SqlTransaction`、`DatabaseConfig`、`DatabasePoolStats`、`Context`、`Error` |
| 被依赖 | [`Database`](Database.md)、[`Db`](Db.md) |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

有界连接池：按配置打开/复用/校验/回收 `SqlConnection`，向调用方借出**租约**，提供池化事务、预热、统计与幂等关闭。

不做：驱动注册/发现、全局池、按 URI 隐式共享池、自动重连/故障转移、每事务隔离级别、事务管理器/XA、语句缓存、后台定时维护、连接级负载均衡、裸句柄导出。

---

## 2. 设计逻辑

- 池由 `DatabasePool.open(context, driver, config)` 创建；`Db.open`/`Db.openPool` 是公开入口。驱动显式注入；无全局注册表。
- 池的 `name` 来自 `DatabaseConfig.name`，用于日志/指标；不参与 URI 匹配，也不自动复用同名池。
- 连接创建路径唯一：`SqlDriver.open(context, connectionUri, openOptions)`。池在 open options 中：
  - 复制调用方驱动选项；
  - 若配置了隔离级别，加入保留键 `xdk.isolationLevel`，值为 `isolationLevelName`；
  - 不改写 URI，不拼接 SQL。
- 连接生命周期：
  - **空闲**：在 `_idle` 列表；
  - **活跃**：已借出租约；
  - **正在打开**：已保留容量槽位，等待驱动返回；
  - 空闲连接超过 `idleTimeoutMillis` 或总寿命超过 `maximumLifetimeMillis` 时，在下次获取/归还/预热时关闭；不使用后台定时器。
- 借出使用**租约包装** `SqlConnection`：
  - `execute`/`begin`/`dialect` 委托给物理连接；
  - `close` 把物理连接归还池，而不是关闭数据库会话；
  - `isOpen` 同时反映租约与物理连接状态；
  - 租约关闭幂等；关闭后 I/O 返回 `InvalidArgument`（与 `xdk.sql` 一致）。
- 归还时若池已关闭、物理连接 `isOpen=false`、超过寿命，或空闲超时已到，则关闭并丢弃，不回到池。
- `DatabasePool.begin` 返回**池化事务**包装；租约上的 `begin` 也返回一层租约事务包装，用于跟踪活动事务：
  - 内部先 `acquire`，再 `SqlConnection.begin`；
  - `commit`/`rollback`/`close` 结束后自动归还租约；
  - 提交/回滚结果不确定或连接不可用时，租约关闭会丢弃物理连接；
  - 调用方不需要也不应该再关闭底层连接。
- 等待与超时：
  - 获取受 `acquireTimeoutMillis` 与 `Context` 取消共同约束，先到者生效；
  - `acquireTimeoutMillis=0` 表示只受 `Context` 约束，可能无限等待；
  - 等待不保证严格 FIFO；高并发下可能有饥饿，池不承诺公平性。
- 校验：
  - `validateOnAcquire=true` 时，借出前检查 `isOpen`；若配置了 `validationStatement`，在 `validationTimeoutMillis` 内执行该语句；`validationTimeoutMillis=0` 时以 `acquireTimeoutMillis` 作为整体上界（两者都 0 则不单独限时）；
  - 校验失败：空闲连接丢弃后继续尝试；新打开连接校验失败则返回该错误（数据库可能不可用），不做无限重试；
  - 校验失败递增 `validationFailureCount`，不把坏连接交给调用方。
- `minimumIdle` 是**尽力维持**的空闲下限：`warmUp`/获取/归还路径会补充；没有后台填充线程。`DatabasePool.open` 在 `failFast=true` 时至少建立并验证一条连接（即使 `minimumIdle=0`）。
- 统计在锁内读取 gauge/counter；不在持锁期间执行驱动 I/O。泄漏检测只做诊断：获取/归还/`stats` 时扫描活跃租约，超过阈值递增计数，不强制关闭、不记录日志。
- 关闭：
  - 标记关闭、拒绝新获取、唤醒等待者；
  - 关闭所有空闲连接；
  - 活动租约在归还时关闭；`close` 不无限等待；
  - 幂等：第二次 `close` 返回 `Ok(unit)`。
- 无后台线程、无全局状态；池对象可跨任务共享；所有公开方法线程安全。
- 不暴露驱动/物理连接句柄；内部可用不透明 `Long`/私有对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_driver` | `SqlDriver` | final | 调用方注入；不关闭 |
| `_driverName` | `String` | final | 打开时读取；稳定；用于诊断 |
| `_config` | `DatabaseConfig` | final | 不可变配置；含敏感 URI/选项，不导出 |
| `_name` | `String` | final | 池名 |
| `_idle` | `List<PoolEntry>` | 可变 | 空闲连接；元素非 null |
| `_active` | `List<PoolEntry>` | 可变 | 活跃租约；元素非 null |
| `_openingCount` | `Int` | 可变 | ≥0；已保留槽位 |
| `_waitingRequests` | `Int` | 可变 | ≥0 |
| `_closed` | `Bool` | 可变 | 关闭标记 |
| `_monitor` | `RuntimeMonitor` | final | 等待/通知 |
| `_createdCount` | `Long` | 可变 | 成功打开累计 |
| `_closedCount` | `Long` | 可变 | 已关闭累计 |
| `_acquireCount` | `Long` | 可变 | 成功借出累计 |
| `_acquireTimeoutCount` | `Long` | 可变 | 获取超时累计 |
| `_validationFailureCount` | `Long` | 可变 | 校验失败累计 |
| `_leakedLeaseCount` | `Long` | 可变 | 泄漏诊断累计 |
| `_waitCount` | `Long` | 可变 | 发生等待的获取累计 |
| `_waitMillisTotal` | `Long` | 可变 | 累计等待毫秒 |
| `_maximumWaitMillis` | `Long` | 可变 | 单次最大等待 |

不变量：

- `0 ≤ _openingCount`；`_idle`/`_active` 元素不重复且非 null；同一 `PoolEntry` 不同时在 idle 与 active。
- `_idle.length() + _active.length() + _openingCount ≤ _config.maximumPoolSize()`。
- `_closed=true` 后不再有新连接进入 idle/active；等待者被唤醒并收到 `Unavailable`。
- 所有 counter ≥0；`_maximumWaitMillis ≤ _waitMillisTotal`。
- 持锁期间不调用 `SqlDriver.open`、`SqlConnection.execute/begin/close` 等可能阻塞的驱动操作；驱动 I/O 在锁外完成。
- `stats()` 返回的快照满足 `total = idle + active + opening`。
- `close` 幂等；第一次可能返回关闭诊断错误，后续返回 `Ok(unit)`。
- 不暴露物理连接/驱动句柄；租约包装关闭后不再访问物理连接。

`PoolEntry` 是实现内部类型（不公开）：持有物理 `SqlConnection`、`createdAtMono`、`idleSinceMono`、`leasedAtMono`、`isLeased`、`leakReported`。`PooledConnection`/`PooledLeaseTransaction`/`PooledTransaction` 也是内部包装类型，不进入包索引。

---

## 4. 生命周期

`DatabasePool.open` 创建；使用期间持有物理连接；必须 `close`。

- `open` 成功：`isClosed=false`；`failFast=true` 时已有至少一条验证过的空闲连接；`failFast=false` 时可能尚无连接。
- `open` 失败：关闭已建立的连接，不返回半初始化池。
- 使用期：`acquire`/`begin`/`warmUp`/`stats` 可并发；`close` 可与它们并发。
- `close`：标记关闭、关闭空闲、唤醒等待者；活动租约归还时关闭。关闭后 `acquire`/`begin`/`warmUp` 返回 `Unavailable`。
- 第二次 `close`：`Ok(unit)`，不再重复关闭/报告第一次错误。
- 池不自动重连；数据库重启后旧连接在借出/使用时暴露错误，调用方关闭池并重新打开。
- 驱动对象生命周期由调用方管理；池关闭不影响驱动对象，也不关闭驱动（协议无 close）。

---

## 5. 构造契约

| 构造/工厂 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DatabasePool.open(Context context, SqlDriver driver, DatabaseConfig config)` | context/driver/config | 非 null；config 合法 | `Result`：驱动/连接错误、`Unsupported`、`Timeout`、`Cancelled` |
| 私有构造 | driver/config/name | 仅供 `open` 使用 | 不公开 |

- `open` 要求非 null `context`/`driver`/`config`；null 是合同错误（panic）。
- `open` 复制 `config` 所需值；之后替换配置不影响池。`config` 本身不可变。
- `open` 读取 `driver.name()` 一次；驱动名在池生命周期内稳定。
- `failFast=true`：建立 `max(minimumIdle, 1)` 条连接并逐条校验；任一失败则关闭已建立连接并返回该错误。
- `failFast=false`：不建立连接；只校验配置；首次 `acquire` 才暴露网络/认证错误。
- 隔离级别非 null 时，在 open options 中加入保留键；驱动不支持返回 `Unsupported`，不识别保留键返回 `InvalidArgument`；两种都原样返回。
- `open` 成功返回的池可立即 `acquire`；`failFast=false` 时第一次 `acquire` 可能阻塞/失败。
- 不使用全局池缓存；相同配置多次 `open` 得到互不影响的池。

---

## 6. 字段表

见 §3；字段私有。

`_config` 含连接 URI/驱动选项，禁止通过 `DatabasePool` 导出；`name()`/`driverName()`/`describe()` 只输出非敏感信息。`PoolEntry` 内部字段不进入公共契约。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `open` | 打开池 | `Context context, SqlDriver driver, DatabaseConfig config` | `Result<DatabasePool, Error>` | `InvalidArgument`/`PermissionDenied`/`Unsupported`/`Network`/`Io`/`Timeout`/`Cancelled` | 静态；`failFast` 控制是否预连 |
| `name` | 池名 | 无 | `String` | 无 | 非敏感 |
| `driverName` | 驱动名 | 无 | `String` | 无 | 打开时固定 |
| `maximumPoolSize` | 总量上限 | 无 | `Int` | 无 | ≥1 |
| `minimumIdle` | 空闲下限 | 无 | `Int` | 无 | 0..max |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 | 关闭后 true |
| `acquire` | 借出租约 | `Context context` | `Result<SqlConnection, Error>` | `Unavailable`/`Timeout`/`Cancelled`/驱动错误 | 租约 `close` 归还 |
| `begin` | 池化事务 | `Context context` | `Result<SqlTransaction, Error>` | 同上 + `Unsupported` | 结束自动归还 |
| `warmUp` | 补足空闲下限 | `Context context` | `Result<Int, Error>` | 同上 | 返回新建数；无后台填充 |
| `stats` | 统计快照 | 无 | `DatabasePoolStats` | 无 | 非阻塞；只读锁内 |
| `close` | 关闭池 | 无 | `Result<Unit, Error>` | `Io`/`Network`（诊断） | 幂等；不等待活动租约 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 不含 URI/选项 |

详细契约：

#### `open`

- `context` 非 null；取消/截止在建立连接期间到达时，关闭已建连接并返回 `Cancelled`/`Timeout`。
- `failFast=true` 的初始连接逐条建立；第一条失败即停止并回滚已建连接；错误原样返回。
- `failFast=false` 不执行 I/O；`config` 非法仍 panic（构造期已校验）。
- 隔离级别通过保留键传递；驱动不支持时返回 `Unsupported`，不得静默降级。驱动不识别保留键返回 `InvalidArgument`。
- 错误文本不含 URI/口令/选项值。

#### `acquire`

- 前置条件：`context` 非 null；池未关闭。关闭后返回 `Unavailable`。
- 获取顺序：
  1. 池内有空闲：取一条（LIFO；最后归还的先复用），标记活跃，校验后返回；
  2. 未达上限：保留槽位，锁外 `driver.open`，校验后转为活跃；
  3. 已达上限：等待归还/关闭/取消，受 `acquireTimeoutMillis` 与 `Context` 约束。
- 空闲连接在借出前检查 `isOpen`、`maximumLifetimeMillis`、`idleTimeoutMillis`；任一不满足则关闭丢弃并继续。
- 校验失败：丢弃连接、递增 `validationFailureCount`；空闲路径继续尝试；新开连接路径返回校验错误。
- 成功返回租约 `SqlConnection`；调用方必须 `close` 归还。租约不跨任务共享（与 `SqlConnection` 一致）。
- 获取超时返回 `Timeout`；显式取消返回 `Cancelled`；两者都不改变池中已有连接（正在打开的连接会被关闭）。
- 获取失败不返回半借出租约；已保留槽位/已打开连接都要回收。
- `acquireTimeoutMillis=0` 表示无限等待，只受 `Context` 约束；调用方必须提供可取消的 context。
- 不保证 FIFO；持续竞争下可能饥饿；不要在单任务中先借满 `maximumPoolSize` 再等待下一条。
- 租约 `close` 幂等；租约关闭后 `execute`/`begin` 返回 `InvalidArgument`；`dialect` 仍可读（租约缓存）。
- `acquire` 返回的租约上调用 `begin` 得到租约事务包装；租约不会自动归还，调用方必须在事务结束后 `lease.close()`。若租约关闭时事务仍未结束，池会关闭物理连接并丢弃。
- 事务 `commit`/`rollback`/`close` 返回错误会把租约标记为 broken；后续 `lease.close()` 强制丢弃物理连接，不回到池。broken 租约上的 `execute`/`begin` 返回 `Unavailable`。需要自动归还时用 `DatabasePool.begin`/`Database.begin`。

#### `begin`

- 先 `acquire`，再 `SqlConnection.begin`；任一步失败都归还/丢弃租约。
- 成功返回池化事务；`commit`/`rollback`/`close` 后自动关闭租约（归还或丢弃）。
- 事务能力由驱动决定；驱动不支持事务返回 `Unsupported`，此时租约归还，连接仍可用。
- 池化事务关闭后再次 `commit`/`rollback` 返回 `InvalidArgument`；`close` 幂等。
- 提交/回滚发送后失败可能结果不确定；包装器关闭租约时以底层 `isOpen` 决定归还或丢弃；调用方以 `database.isOpen()`/池统计为准。
- 不在事务上设置隔离级别；隔离级别是池级配置。

#### `warmUp`

- 目标：`idle` 数量达到 `minimumIdle`，且不超过 `maximumPoolSize`。
- 返回本次新建连接数；已满足返回 0；`minimumIdle=0` 返回 0。
- 逐条建立/校验；失败返回错误，已建连接保留在池中（不回滚已成功的预热），除非池已关闭。
- 并发 `warmUp` 可能由一方补足、另一方返回 0；不保证精确调用次数。
- 无后台填充；空闲连接被回收后不会自动补足，直到下次获取/`warmUp`。

#### `stats`

- 非阻塞读取；在锁内复制 gauge/counter；不在锁内执行驱动 I/O。
- 触发泄漏诊断扫描：活跃租约超过 `leakDetectionThresholdMillis` 且未报告过时，递增 `leakedLeaseCount`；不关闭连接、不记录日志。
- 快照满足 `total = idle + active + opening`；`opening` 计入上限。
- 关闭后仍可读；`isClosed=true`。

#### `close`

- 幂等；第一次标记关闭、唤醒等待者、关闭所有空闲连接；活动租约不等待。
- 关闭空闲连接时继续处理其余连接，返回第一个 `Io`/`Network` 诊断错误；后续 `close` 返回 `Ok(unit)`。
- 关闭后新 `acquire`/`begin`/`warmUp` 返回 `Unavailable`；等待者被唤醒并返回 `Unavailable`。
- 活动租约在归还时关闭；租约上的操作可能已失败，调用方应按 `xdk.sql` 错误处理。
- `close` 不关闭驱动，不删除统计。
- `close` 与 `acquire` 并发安全；关闭期间已保留槽位的打开操作完成后会看到 `_closed`，关闭新连接并返回 `Unavailable`。

#### `describe`

- 形如 `"DatabasePool(name=orders driver=postgres max=10 idle=0 closed=false)"`；不含 URI、用户名、选项值。
- 不输出连接级明细。

---

## 8. 使用的技术

- 有界连接池（idle/active/opening 三态）；
- 租约包装与幂等归还；
- 池化事务包装；
- 取消感知等待 + 获取超时；
- 获取时校验（`isOpen` + 可选语句）；
- 空闲/寿命回收（惰性，无后台线程）；
- 统计快照与泄漏诊断；
- 惰性预热；
- 关闭广播；
- 无驱动 I/O 持锁；
- 无全局状态、无裸句柄。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Map、Int、Long、Bool、String、Result、Unit；
- 运行时：`RuntimeMonitor.enter/exit/waitDeadline(Context, Long)/notifyAll`、`nowMono`；
- 驱动：`SqlDriver.open`、`SqlConnection.execute/begin/isOpen/close/dialect`、`SqlTransaction.execute/commit/rollback/isOpen/close`；
- 接口：`DatabaseConfig`、`IsolationLevel`、`isolationLevelName`、`DatabasePoolStats`、`SqlDialect`、`SqlOptions`、`Error`、`BasicError`、`ErrorKind`、`Context`。

---

## 10. 依赖的特性/接口/类

[`DatabaseConfig`](DatabaseConfig.md)、[`IsolationLevel`](IsolationLevel.md)、[`DatabasePoolStats`](DatabasePoolStats.md)、[`Database`](Database.md)、[`Db`](Db.md)、[`SqlDriver`](../../network/sql/SqlDriver.md)、[`SqlConnection`](../../network/sql/SqlConnection.md)、[`SqlTransaction`](../../network/sql/SqlTransaction.md)、[`SqlOptions`](../../network/sql/SqlOptions.md)、[`SqlDialect`](../../network/sql/SqlDialect.md)、[`Context`](../../core/execution/Context.md)、[`Error`](../../core/errors/Error.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

- 池拥有物理连接；调用方拥有池，必须 `close`。驱动借用，不转移所有权。
- 租约借用物理连接；租约 `close` 归还/丢弃；租约不拥有池/驱动。
- 池化事务拥有租约直到结束；结束后自动关闭租约；调用方不持有底层连接。
- 池线程安全，可跨任务共享；`acquire`/`begin`/`warmUp`/`stats`/`close` 可并发。
- 同一租约不得跨任务共享；租约上的 I/O 遵守 `xdk.sql` 的单任务约定。
- 不在持锁期间调用驱动 I/O；等待使用 `RuntimeMonitor`；关闭唤醒所有等待者。
- 不承诺公平性；不承诺 FIFO；调用方应避免“借满再等”的自锁模式。
- 相等：引用身份；不提供 `equals`；不同池永不相等。
- 无裸句柄；所有权不通过句柄转移。

---

## 12. 示例与反例

正确：

```text
DatabasePool pool = Db.openPool(context, driver, config)
Result<SqlConnection, Error> leased = pool.acquire(context)
if leased.isOk() {
    SqlConnection connection = leased.value()
    Result<SqlResult, Error> result = connection.execute(context, statement)
    Result<Unit, Error> closed = connection.close()
}
```

```text
Result<SqlTransaction, Error> started = pool.begin(context)
if started.isOk() {
    SqlTransaction transaction = started.value()
    Result<Unit, Error> committed = transaction.commit(context)
}
```

```text
Int created = pool.warmUp(context).value()
DatabasePoolStats stats = pool.stats()
Result<Unit, Error> closed = pool.close()
```

反例：

- 在 `acquire` 返回的租约上调用 `close` 期望关闭数据库会话；它归还池。若租约上仍有未结束事务，`close` 会关闭物理连接并丢弃，而不是把带事务的连接放回池。
- 租约使用后不 `close`；连接泄漏，最终耗尽池。
- 在同一任务中借满 `maximumPoolSize` 后继续等待；自锁。
- 关闭池后继续 `acquire`；应处理 `Unavailable`。
- 把池当全局单例跨配置共享；不同 URI/隔离级别必须不同池。
- 在 `validationStatement` 中放含秘密参数的 DML；校验语句应无副作用、无秘密。
- 依赖 FIFO/公平唤醒；池不承诺。
- 在 `stats()` 中期望强制回收空闲连接；它只读。
- 把 `close` 当“等待所有租约归还”；它不等待。
- 直接关闭物理连接后再归还；租约 `isOpen=false` 时会被丢弃。
- 把 `DatabasePoolStats.createdCount` 当当前连接数；当前数用 `totalConnections`。

---

## 13. 测试/场景义务

- `open` 的 `failFast` true/false；初始连接成功/失败；失败无泄漏；隔离级别保留键；驱动 `Unsupported`/`InvalidArgument`；
- `acquire` 空闲复用、创建新连接、达到上限等待、归还唤醒、超时、取消、关闭唤醒；
- 空闲超时/寿命回收；使用中的连接不被回收；归还时过期丢弃；
- 校验：`isOpen`、校验语句成功/失败、校验超时、校验失败计数、坏连接不交付；
- `begin` 成功/失败；`commit`/`rollback`/`close` 自动归还；二次提交失败；提交后错误丢弃连接；
- 租约 `close` 幂等；关闭后 execute/begin `InvalidArgument`；dialect 关闭后可读；
- `warmUp` 0/补足/已满足/失败/并发；
- `stats` 不变量、计数、饱和、泄漏诊断、关闭后读取；
- `close` 幂等、关闭空闲、活动租约归还时关闭、等待者 `Unavailable`、错误汇总；
- 并发 acquire/release/close/stats；不持锁 I/O；无死锁（单任务借满场景文档化）；
- 无全局池：两个同配置池互不影响；
- 错误文本不含 URI/口令/选项值；无裸句柄；
- 连接打开后配置替换不影响池。

---

## 14. XNull 伪代码

```xnull
class DatabasePool {
    final SqlDriver _driver
    final String _driverName
    final DatabaseConfig _config
    final String _name
    final List<PoolEntry> _idle
    final List<PoolEntry> _active
    Int _openingCount
    Int _waitingRequests
    Bool _closed
    final RuntimeMonitor _monitor
    Long _createdCount
    Long _closedCount
    Long _acquireCount
    Long _acquireTimeoutCount
    Long _validationFailureCount
    Long _leakedLeaseCount
    Long _waitCount
    Long _waitMillisTotal
    Long _maximumWaitMillis

    private DatabasePool(SqlDriver driver, DatabaseConfig config) {
        _driver = driver
        _config = config
        _driverName = driver.name()
        _name = config.name()
        _idle = []
        _active = []
        _openingCount = 0
        _waitingRequests = 0
        _closed = false
        _monitor = new RuntimeMonitor()
        _createdCount = 0
        _closedCount = 0
        _acquireCount = 0
        _acquireTimeoutCount = 0
        _validationFailureCount = 0
        _leakedLeaseCount = 0
        _waitCount = 0
        _waitMillisTotal = 0
        _maximumWaitMillis = 0
    }

    static Result<DatabasePool, Error> open(Context context,
            SqlDriver driver, DatabaseConfig config) {
        if context == null || driver == null || config == null {
            throw "DatabasePool.open: null argument"
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "pool open cancelled"))
        }
        DatabasePool pool = new DatabasePool(driver, config)
        if config.failFast() {
            Int target = config.minimumIdle()
            if target < 1 { target = 1 }
            Result<Int, Error> seeded = pool.warmUpTo(context, target)
            if seeded.isErr() {
                pool.close()
                return Err(seeded.error())
            }
        }
        return Ok(pool)
    }

    String name() { return _name }
    String driverName() { return _driverName }
    Int maximumPoolSize() { return _config.maximumPoolSize() }
    Int minimumIdle() { return _config.minimumIdle() }

    Bool isClosed() {
        _monitor.enter()
        Bool result = _closed
        _monitor.exit()
        return result
    }

    Result<SqlConnection, Error> acquire(Context context) {
        if context == null { throw "DatabasePool.acquire: null context" }
        Long started = nowMono()
        Long deadline = 0
        if _config.acquireTimeoutMillis() > 0 {
            deadline = started + _config.acquireTimeoutMillis()
        }
        Bool waited = false
        while true {
            _monitor.enter()
            if _closed {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Unavailable, "pool closed"))
            }
            if context.isCancelled() {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "pool acquire cancelled"))
            }
            if deadline > 0 && nowMono() >= deadline {
                _acquireTimeoutCount = _acquireTimeoutCount + 1
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Timeout, "pool acquire timeout"))
            }
            if _idle.length() > 0 {
                PoolEntry entry = _idle.remove(_idle.length() - 1)
                Long currentMono = nowMono()
                if !entry._connection.isOpen() || isExpired(entry, currentMono) {
                    _closedCount = _closedCount + 1
                    _monitor.exit()
                    entry._connection.close()
                    continue
                }
                entry._isLeased = true
                entry._leasedAtMono = currentMono
                entry._leakReported = false
                _active.push(entry)
                _monitor.exit()
                Result<Unit, Error> valid = validateEntry(context, entry)
                if valid.isOk() {
                    _monitor.enter()
                    _acquireCount = _acquireCount + 1
                    _monitor.exit()
                    return Ok(new PooledConnection(self, entry))
                }
                discardActive(entry)
                if !isRetryableValidation(valid.error()) || context.isCancelled() {
                    return Err(valid.error())
                }
                continue
            }
            if _idle.length() + _active.length() + _openingCount
                    < _config.maximumPoolSize() {
                _openingCount = _openingCount + 1
                _monitor.exit()
                Result<SqlConnection, Error> opened = createConnection(context)
                if opened.isErr() {
                    _monitor.enter()
                    _openingCount = _openingCount - 1
                    _monitor.notifyAll()
                    _monitor.exit()
                    return Err(opened.error())
                }
                SqlConnection connection = opened.value()
                PoolEntry entry = new PoolEntry(connection)
                Result<Unit, Error> valid = validateEntry(context, entry)
                if valid.isErr() {
                    connection.close()
                    _monitor.enter()
                    _openingCount = _openingCount - 1
                    _validationFailureCount = _validationFailureCount + 1
                    _monitor.notifyAll()
                    _monitor.exit()
                    return Err(valid.error())
                }
                _monitor.enter()
                _openingCount = _openingCount - 1
                if _closed {
                    _monitor.notifyAll()
                    _monitor.exit()
                    connection.close()
                    return Err(new BasicError(ErrorKind.Unavailable, "pool closed"))
                }
                entry._isLeased = true
                entry._leasedAtMono = nowMono()
                _active.push(entry)
                _createdCount = _createdCount + 1
                _acquireCount = _acquireCount + 1
                _monitor.notifyAll()
                _monitor.exit()
                return Ok(new PooledConnection(self, entry))
            }
            if !waited {
                waited = true
                _waitCount = _waitCount + 1
            }
            _waitingRequests = _waitingRequests + 1
            Long waitStarted = nowMono()
            _monitor.exit()
            Bool woke = _monitor.waitDeadline(context, deadline)
            Long waitedMillis = nowMono() - waitStarted
            _monitor.enter()
            _waitingRequests = _waitingRequests - 1
            _waitMillisTotal = _waitMillisTotal + waitedMillis
            if waitedMillis > _maximumWaitMillis {
                _maximumWaitMillis = waitedMillis
            }
            if _closed {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Unavailable, "pool closed"))
            }
            if context.isCancelled() {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "pool acquire cancelled"))
            }
            if !woke && deadline > 0 && nowMono() >= deadline {
                _acquireTimeoutCount = _acquireTimeoutCount + 1
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Timeout, "pool acquire timeout"))
            }
            _monitor.notifyAll()
            _monitor.exit()
        }
    }

    Result<SqlTransaction, Error> begin(Context context) {
        if context == null { throw "DatabasePool.begin: null context" }
        Result<SqlConnection, Error> acquired = acquire(context)
        if acquired.isErr() {
            return Err(acquired.error())
        }
        SqlConnection lease = acquired.value()
        Result<SqlTransaction, Error> started = lease.begin(context)
        if started.isErr() {
            lease.close()
            return Err(started.error())
        }
        return Ok(new PooledTransaction(lease, started.value()))
    }

    Result<Int, Error> warmUp(Context context) {
        if context == null { throw "DatabasePool.warmUp: null context" }
        return warmUpTo(context, _config.minimumIdle())
    }

    private Result<Int, Error> warmUpTo(Context context, Int target) {
        Int created = 0
        while true {
            _monitor.enter()
            if _closed {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Unavailable, "pool closed"))
            }
            if _idle.length() >= target {
                _monitor.exit()
                return Ok(created)
            }
            if _idle.length() + _active.length() + _openingCount
                    >= _config.maximumPoolSize() {
                _monitor.exit()
                return Ok(created)
            }
            _openingCount = _openingCount + 1
            _monitor.exit()
            Result<SqlConnection, Error> opened = createConnection(context)
            if opened.isErr() {
                _monitor.enter()
                _openingCount = _openingCount - 1
                _monitor.notifyAll()
                _monitor.exit()
                return Err(opened.error())
            }
            SqlConnection connection = opened.value()
            PoolEntry entry = new PoolEntry(connection)
            Result<Unit, Error> valid = validateEntry(context, entry)
            if valid.isErr() {
                connection.close()
                _monitor.enter()
                _openingCount = _openingCount - 1
                _validationFailureCount = _validationFailureCount + 1
                _monitor.notifyAll()
                _monitor.exit()
                return Err(valid.error())
            }
            _monitor.enter()
            _openingCount = _openingCount - 1
            if _closed {
                _monitor.notifyAll()
                _monitor.exit()
                connection.close()
                return Err(new BasicError(ErrorKind.Unavailable, "pool closed"))
            }
            entry._idleSinceMono = nowMono()
            _idle.push(entry)
            _createdCount = _createdCount + 1
            created = created + 1
            _monitor.notifyAll()
            _monitor.exit()
        }
    }

    DatabasePoolStats stats() {
        _monitor.enter()
        scanLeaks()
        Int idle = _idle.length()
        Int active = _active.length()
        Int opening = _openingCount
        DatabasePoolStats result = new DatabasePoolStats(_name,
            _config.maximumPoolSize(), _config.minimumIdle(),
            idle + active + opening, idle, active, opening,
            _waitingRequests, _createdCount, _closedCount, _acquireCount,
            _acquireTimeoutCount, _validationFailureCount, _leakedLeaseCount,
            _waitCount, _waitMillisTotal, _maximumWaitMillis,
            nowMono(), _closed)
        _monitor.exit()
        return result
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Ok(unit)
        }
        _closed = true
        List<PoolEntry> closing = _idle.copy()
        _idle.clear()
        _monitor.notifyAll()
        _monitor.exit()
        Error? first = null
        Int index = 0
        while index < closing.length() {
            Result<Unit, Error> closedResult =
                closing.get(index)._connection.close()
            _monitor.enter()
            _closedCount = _closedCount + 1
            _monitor.exit()
            if closedResult.isErr() && first == null {
                first = closedResult.error()
            }
            index = index + 1
        }
        if first != null {
            return Err(first)
        }
        return Ok(unit)
    }

    String describe() {
        _monitor.enter()
        Bool closed = _closed
        _monitor.exit()
        return "DatabasePool(name=" + _name
            + " driver=" + _driverName
            + " max=" + str(_config.maximumPoolSize())
            + " idle=" + str(_config.minimumIdle())
            + " closed=" + str(closed) + ")"
    }

    private Result<SqlConnection, Error> createConnection(Context context) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "connection open cancelled"))
        }
        Map<String, String> options = _config.openOptions()
        if _config.isolationLevel() != null {
            IsolationLevel level = _config.isolationLevel() as IsolationLevel
            options.put("xdk.isolationLevel", isolationLevelName(level))
        }
        Result<SqlConnection, Error> opened = _driver.open(context,
            _config.connectionUri(), options)
        if opened.isErr() {
            return Err(opened.error())
        }
        SqlConnection connection = opened.value()
        if context.isCancelled() {
            connection.close()
            return Err(new BasicError(ErrorKind.Cancelled, "connection open cancelled"))
        }
        return Ok(connection)
    }

    private Result<Unit, Error> validateEntry(Context context, PoolEntry entry) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "validation cancelled"))
        }
        if !entry._connection.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "connection closed"))
        }
        if isExpired(entry, nowMono()) {
            return Err(new BasicError(ErrorKind.Unavailable, "connection expired"))
        }
        if !_config.validateOnAcquire() {
            return Ok(unit)
        }
        if _config.validationStatement() == null {
            return Ok(unit)
        }
        SqlOptions options = new SqlOptions()
        Long validationTimeout = _config.validationTimeoutMillis()
        if validationTimeout == 0 {
            validationTimeout = _config.acquireTimeoutMillis()
        }
        if validationTimeout > 0 {
            options.timeoutMillis(validationTimeout)
        }
        Result<SqlResult, Error> checked = entry._connection.execute(
            context, _config.validationStatement(), options)
        if checked.isErr() {
            return Err(checked.error())
        }
        return Ok(unit)
    }

    private Bool isExpired(PoolEntry entry, Long currentMono) {
        if _config.maximumLifetimeMillis() > 0
                && currentMono - entry._createdAtMono
                    >= _config.maximumLifetimeMillis() {
            return true
        }
        if entry._isLeased {
            return false
        }
        if _config.idleTimeoutMillis() > 0
                && currentMono - entry._idleSinceMono
                    >= _config.idleTimeoutMillis() {
            return true
        }
        return false
    }

    private void discardActive(PoolEntry entry) {
        _monitor.enter()
        removeEntry(_active, entry)
        _closedCount = _closedCount + 1
        _validationFailureCount = _validationFailureCount + 1
        _monitor.notifyAll()
        _monitor.exit()
        entry._connection.close()
    }

    private Result<Unit, Error> releaseEntry(PoolEntry entry, Bool forceDiscard) {
        Long currentMono = nowMono()
        Bool discard = false
        _monitor.enter()
        entry._isLeased = false
        entry._leasedAtMono = 0
        entry._idleSinceMono = currentMono
        removeEntry(_active, entry)
        if forceDiscard || _closed || !entry._connection.isOpen()
                || isExpired(entry, currentMono) {
            discard = true
            _closedCount = _closedCount + 1
        } else {
            _idle.push(entry)
        }
        _monitor.notifyAll()
        _monitor.exit()
        if discard {
            return entry._connection.close()
        }
        return Ok(unit)
    }

    private void scanLeaks() {
        if _config.leakDetectionThresholdMillis() <= 0 {
            return
        }
        Long currentMono = nowMono()
        Int index = 0
        while index < _active.length() {
            PoolEntry entry = _active.get(index)
            if !entry._leakReported
                    && currentMono - entry._leasedAtMono
                        >= _config.leakDetectionThresholdMillis() {
                entry._leakReported = true
                _leakedLeaseCount = _leakedLeaseCount + 1
            }
            index = index + 1
        }
    }

    private void removeEntry(List<PoolEntry> entries, PoolEntry entry) {
        Int index = 0
        while index < entries.length() {
            if entries.get(index) == entry {
                entries.remove(index)
                return
            }
            index = index + 1
        }
    }

    private Bool isRetryableValidation(Error error) {
        ErrorKind kind = error.kind()
        return kind == ErrorKind.Unavailable
            || kind == ErrorKind.Network
            || kind == ErrorKind.Io
            || kind == ErrorKind.Timeout
    }
}

class PooledConnection implements SqlConnection {
    final DatabasePool _pool
    final PoolEntry _entry
    final SqlConnection _connection
    final SqlDialect _dialect
    Bool _closed
    Bool _activeTransaction
    Bool _broken

    PooledConnection(DatabasePool pool, PoolEntry entry) {
        _pool = pool
        _entry = entry
        _connection = entry._connection
        _dialect = entry._connection.dialect()
        _closed = false
        _activeTransaction = false
        _broken = false
    }

    SqlDialect dialect() { return _dialect }

    Result<SqlResult, Error> execute(Context context, SqlStatement statement) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "lease closed"))
        }
        if _broken {
            return Err(new BasicError(ErrorKind.Unavailable, "lease broken"))
        }
        return _connection.execute(context, statement)
    }

    Result<SqlResult, Error> execute(Context context, SqlStatement statement,
            SqlOptions options) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "lease closed"))
        }
        if _broken {
            return Err(new BasicError(ErrorKind.Unavailable, "lease broken"))
        }
        return _connection.execute(context, statement, options)
    }

    Result<SqlTransaction, Error> begin(Context context) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "lease closed"))
        }
        if _broken {
            return Err(new BasicError(ErrorKind.Unavailable, "lease broken"))
        }
        Result<SqlTransaction, Error> started = _connection.begin(context)
        if started.isErr() {
            return Err(started.error())
        }
        _activeTransaction = true
        return Ok(new PooledLeaseTransaction(self, started.value()))
    }

    void transactionFinished() {
        _activeTransaction = false
    }

    void markBroken() {
        _broken = true
    }

    Bool isOpen() {
        return !_closed && !_broken && _connection.isOpen()
    }

    Result<Unit, Error> close() {
        if _closed {
            return Ok(unit)
        }
        _closed = true
        if _activeTransaction || _broken {
            _activeTransaction = false
            Result<Unit, Error> closedConnection = _connection.close()
            Result<Unit, Error> released = _pool.releaseEntry(_entry, true)
            if closedConnection.isErr() {
                return Err(closedConnection.error())
            }
            return released
        }
        return _pool.releaseEntry(_entry, false)
    }
}

class PooledLeaseTransaction implements SqlTransaction {
    final PooledConnection _lease
    final SqlTransaction _transaction
    Bool _closed

    PooledLeaseTransaction(PooledConnection lease, SqlTransaction transaction) {
        _lease = lease
        _transaction = transaction
        _closed = false
    }

    Result<SqlResult, Error> execute(Context context, SqlStatement statement) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "transaction closed"))
        }
        return _transaction.execute(context, statement)
    }

    Result<SqlResult, Error> execute(Context context, SqlStatement statement,
            SqlOptions options) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "transaction closed"))
        }
        return _transaction.execute(context, statement, options)
    }

    Result<Unit, Error> commit(Context context) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "transaction closed"))
        }
        Result<Unit, Error> committed = _transaction.commit(context)
        _closed = true
        if committed.isErr() {
            _lease.markBroken()
            if _transaction.isOpen() {
                _transaction.close()
            }
        }
        _lease.transactionFinished()
        return committed
    }

    Result<Unit, Error> rollback(Context context) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "transaction closed"))
        }
        Result<Unit, Error> rolledBack = _transaction.rollback(context)
        _closed = true
        if rolledBack.isErr() {
            _lease.markBroken()
            if _transaction.isOpen() {
                _transaction.close()
            }
        }
        _lease.transactionFinished()
        return rolledBack
    }

    Bool isOpen() {
        return !_closed && _transaction.isOpen()
    }

    Result<Unit, Error> close() {
        if _closed {
            return Ok(unit)
        }
        _closed = true
        Result<Unit, Error> closedTransaction = Ok(unit)
        if _transaction.isOpen() {
            closedTransaction = _transaction.close()
        }
        if closedTransaction.isErr() {
            _lease.markBroken()
        }
        _lease.transactionFinished()
        return closedTransaction
    }
}

class PooledTransaction implements SqlTransaction {
    final SqlConnection _lease
    final SqlTransaction _transaction
    Bool _closed

    PooledTransaction(SqlConnection lease, SqlTransaction transaction) {
        _lease = lease
        _transaction = transaction
        _closed = false
    }

    Result<SqlResult, Error> execute(Context context, SqlStatement statement) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "transaction closed"))
        }
        return _transaction.execute(context, statement)
    }

    Result<SqlResult, Error> execute(Context context, SqlStatement statement,
            SqlOptions options) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "transaction closed"))
        }
        return _transaction.execute(context, statement, options)
    }

    Result<Unit, Error> commit(Context context) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "transaction closed"))
        }
        Result<Unit, Error> committed = _transaction.commit(context)
        _closed = true
        Result<Unit, Error> released = _lease.close()
        if committed.isErr() {
            return Err(committed.error())
        }
        return released
    }

    Result<Unit, Error> rollback(Context context) {
        if _closed {
            return Err(new BasicError(ErrorKind.InvalidArgument, "transaction closed"))
        }
        Result<Unit, Error> rolledBack = _transaction.rollback(context)
        _closed = true
        Result<Unit, Error> released = _lease.close()
        if rolledBack.isErr() {
            return Err(rolledBack.error())
        }
        return released
    }

    Bool isOpen() {
        return !_closed && _transaction.isOpen()
    }

    Result<Unit, Error> close() {
        if _closed {
            return Ok(unit)
        }
        _closed = true
        Result<Unit, Error> closedTransaction = Ok(unit)
        if _transaction.isOpen() {
            closedTransaction = _transaction.close()
        }
        Result<Unit, Error> released = _lease.close()
        if closedTransaction.isErr() {
            return Err(closedTransaction.error())
        }
        return released
    }
}

class PoolEntry {
    final SqlConnection _connection
    final Long _createdAtMono
    Long _idleSinceMono
    Long _leasedAtMono
    Bool _isLeased
    Bool _leakReported

    PoolEntry(SqlConnection connection) {
        _connection = connection
        _createdAtMono = nowMono()
        _idleSinceMono = _createdAtMono
        _leasedAtMono = 0
        _isLeased = false
        _leakReported = false
    }
}
```

> 伪代码非可执行。`PoolEntry`、`PooledConnection`、`PooledLeaseTransaction`、`PooledTransaction` 是文件内实现类型，不属于公开类型索引；`releaseEntry(entry, forceDiscard)` 是文件内私有归还入口，仅供同文件租约包装调用；活动事务未结束时强制丢弃。`RuntimeMonitor.waitDeadline`、`nowMono` 是运行时原语；`removeEntry`/`scanLeaks` 在持锁时调用，不执行驱动 I/O。`DatabasePool.open` 的 `warmUpTo` 在 `failFast=false` 时不会被调用。
