# `MigrationRunner`

| 项 | 值 |
| --- | --- |
| 类型 | `class MigrationRunner` |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | `Database`、`Migration`、`SqlStatement`、`SqlResult`、`SqlTransaction`、`SqlOptions`、`Context`、`Error` |
| 被依赖 | 应用启动流程、部署工具、管理 CLI |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

有序迁移执行器：校验显式迁移列表、读取/维护历史表、获取迁移锁、按版本升序应用 up、按应用逆序执行 down、校验/修复校验和。

不做：全局迁移注册表、文件扫描/命名约定、schema diff/自动生成、占位符替换、回调、基线/标记已应用、分支/合并图、失败行保留、跨库分布式迁移、自动重试。

---

## 2. 设计逻辑

- **显式迁移列表**：每次调用传入 `List<Migration>`；runner 不保存列表、不扫描文件、不按类名/包名发现。排序/去重只作用于本次副本，不修改调用方列表。
- **历史表**：runner 在数据库中维护一张历史表，记录已应用版本、名称、校验和、应用顺序、完成时间、执行耗时。表名由调用方指定；runner 只接受简单标识符，不加 schema 前缀（schema 由连接 URI/默认 schema 决定）。
- **迁移锁**：历史表旁维护一张锁表，单行、带 owner 与过期时间；`migrate*`/`rollback*`/`repair` 在操作期间持有锁。获取失败按 `lockTimeoutMillis` 等待；进程崩溃后锁租约到期可被接管。
  - 锁过期时间用**墙钟毫秒**，因为跨进程共享；不是 `nowMono`。
  - 调用方应保证主机时钟同步（NTP）；时钟回拨会延长/缩短锁租约。
  - 锁租约是“最长单次迁移”的上界；runner 在每个迁移前刷新，但单个超长迁移仍可能被接管。默认 1 小时。
- **版本与顺序**：`Migration` 已定义点分十进制排序；runner 对本次列表排序，要求版本唯一。应用顺序严格升序；若存在“版本小于已应用最大版本且未应用”的迁移，默认拒绝（out-of-order），不做自动插入。
- **校验和**：每次 `migrate*`/`validate`/`pending` 都校验已应用迁移的版本/名称/校验和；不一致返回 `DataCorrupted`，不自动覆盖。`repair` 是显式修复入口，只更新名称/校验和，不改变应用顺序/时间。
- **事务边界**：每个迁移一个事务：执行全部 up（或 down）+ 写/删历史行 + 提交。数据库支持事务性 DDL 时原子；不支持时可能留下部分 schema，runner 不假装原子。跨多个迁移不是一个大事务；失败时之前成功的迁移保持已应用。
- **回滚**：`rollbackLast` 回滚最后应用的一个；`rollbackTo` 回滚到指定已应用版本（不含该版本）；`rollbackAll` 回滚全部。执行前预检所有目标迁移都有 down 语句；任一缺失返回 `Unsupported`，不开始任何回滚。回滚顺序按历史 `applied_order` 逆序；单个迁移内 down 语句按定义顺序执行。
- **无失败行**：失败的迁移不写历史；事务回滚。若 DDL 不可回滚，可能留下部分对象且历史无记录；再次迁移可能失败。`repair` 不删除“失败行”（没有这种行），也不做 schema 清理。
- **无基线/标记**：v1 不提供 `baseline`/`stamp`；接管既有库需要外部受控流程。见包 README 缺口。
- **无全局锁对象**：锁是数据库表行，不是进程内 Mutex；可跨进程/主机（时钟同步前提下）。
- **错误脱敏**：错误不含 SQL 正文、参数值、URI；可含版本、名称、历史表名、错误 kind。
- **关闭**：runner 无 close；借用 `Database`，不拥有连接/池。数据库关闭后操作返回 `Unavailable`（来自池）。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_database` | `Database` | final | 借用；不关闭 |
| `_historyTable` | `String` | final | 简单标识符；1..56；字母/下划线开头 |
| `_lockTable` | `String` | final | `_historyTable + "_lock"`；≤64 |
| `_lockTimeoutMillis` | `Long` | final | `≥0`；0 = 无限等待（只受 Context 约束） |
| `_lockLeaseMillis` | `Long` | final | `≥1000`；锁租约 |

不变量：

- `_database` 非 null；`_historyTable`/`_lockTable` 合法且不同。
- 锁表名由历史表名派生；长度不超过 64。
- runner 不持有迁移列表、连接、事务、锁状态；每次调用独立。
- 历史表逻辑列：`version`、`name`、`checksum`、`applied_order`、`applied_at_millis`、`execution_millis`；`version` 唯一；`applied_order` 严格递增且唯一。
- 锁表逻辑列：`lock_name`、`owner`、`expires_at_millis`；固定单行 `lock_name="migration"`；owner 空串表示空闲。
- 历史行一旦写入，除 `repair` 更新名称/校验和外，不被 runner 改写。
- 迁移执行前必须已获取锁；读方法（`pending`/`appliedVersions`/`validate`）不加锁，可能观察到并发迁移中间态。
- 关闭数据库后 runner 不缓存状态；再次调用由池返回 `Unavailable`。

---

## 4. 生命周期

由构造器创建；长期存在；无 close；GC 管理内存。

- 创建不访问数据库、不建表、不获取锁。
- 第一次写操作（`migrate*`/`rollback*`/`repair`）按需创建历史表/锁表。
- 读操作（`pending`/`appliedVersions`/`validate`）只读；历史表不存在时视为空历史，不建表。
- runner 不拥有数据库；数据库关闭后停止使用；需要继续时创建新 runner/新 Database。
- 锁在每次写操作结束时释放；异常路径也必须释放；进程崩溃由租约过期兜底。
- 无后台线程；不自动定时迁移。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MigrationRunner(Database database, String historyTable)` | database/historyTable | 非 null；合法标识符 | 非法 → panic |
| `MigrationRunner(Database database, String historyTable, Long lockTimeoutMillis)` | 三个参数 | 同上；timeout ≥0 | 非法 → panic |
| `MigrationRunner(Database database, String historyTable, Long lockTimeoutMillis, Long lockLeaseMillis)` | 四个参数 | 同上；lease ≥1000 | 非法 → panic |

默认值：

| 字段 | 默认 |
| --- | --- |
| `lockTimeoutMillis` | 30000 |
| `lockLeaseMillis` | 3600000（1 小时） |

- 历史表名：1..56 字符；首字符字母或 `_`；其余字母/数字/`_`；不允许空白/引号/点/分号。大小写按数据库标识符规则处理；调用方必须在所有环境使用一致写法。
- 锁表名自动加 `_lock`；若派生名超 64 或与历史表同名，构造 panic（当前派生规则不会同名，但保留校验）。
- `database` 非 null；不做 I/O；不探测表是否存在。
- `lockTimeoutMillis=0` 表示无限等待；必须提供可取消 `Context`。
- `lockLeaseMillis` 必须 ≥1000；默认 1 小时；应大于最长单次迁移耗时。
- 不提供从配置/URI 构造；连接信息归 `Database`。
- 不提供全局单例/注册表；每个 runner 显式绑定一个 `Database` 与历史表。

---

## 6. 字段表

见 §3；字段私有。

历史表/锁表的物理类型由实现按方言映射；逻辑列名固定。表名进入 SQL 标识符位置，必须来自构造校验，不能直接拼接调用方原始字符串之外的内容。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `migrate` | 应用到最新 | `Context context, List<Migration> migrations` | `Result<Int, Error>` | 校验/锁/SQL/提交错误 | 返回应用数；空列表 0 |
| `migrateTo` | 应用到目标版本 | `Context context, List<Migration> migrations, String targetVersion` | `Result<Int, Error>` | 同上；目标不存在 `InvalidArgument` | 目标已应用则 0 |
| `rollbackLast` | 回滚最后一个 | `Context context, List<Migration> migrations` | `Result<Int, Error>` | 校验/锁/`Unsupported`/SQL | 返回 0 或 1 |
| `rollbackTo` | 回滚到目标之后 | `Context context, List<Migration> migrations, String targetVersion` | `Result<Int, Error>` | 目标未应用 `InvalidArgument`；缺 down `Unsupported` | 不含目标版本 |
| `rollbackAll` | 回滚全部 | `Context context, List<Migration> migrations` | `Result<Int, Error>` | 缺 down `Unsupported`/SQL | 返回回滚数 |
| `pending` | 待应用快照 | `Context context, List<Migration> migrations` | `Result<List<Migration>, Error>` | 校验错误 | 不加锁；可能观察到并发中间态 |
| `appliedVersions` | 已应用版本 | `Context context` | `Result<List<String>, Error>` | 读错误 | 按应用顺序；不加锁 |
| `validate` | 校验历史 | `Context context, List<Migration> migrations` | `Result<Unit, Error>` | `DataCorrupted`/`InvalidArgument` | 不执行迁移；不加锁 |
| `repair` | 修复名称/校验和 | `Context context, List<Migration> migrations` | `Result<Int, Error>` | 未知版本/锁/SQL | 显式危险操作；返回更新数 |
| `historyTable` | 历史表名 | 无 | `String` | 无 | 非敏感 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 不含 SQL/URI |

详细契约：

#### 通用

- 所有 `Context` 参数非 null；`migrations` 非 null；列表中的 null 元素返回 `InvalidArgument`；`targetVersion` 非 null。null 参数是合同错误（panic）；未知/非法 `targetVersion` 返回 `InvalidArgument`，不是 panic。
- 输入列表不修改；runner 复制并排序。版本重复 → `InvalidArgument`。
- 历史表不存在：`migrate*` 创建；`rollback*` 返回 0；`pending` 返回全部迁移；`appliedVersions` 返回空；`validate` 返回 `Ok(unit)`；`repair` 返回 0（不创建历史表；锁表可能按写路径创建）。
- 历史表存在但读失败：`PermissionDenied`/`Network`/`Io` 等原样返回。
- 历史中的版本不在本次列表：`DataCorrupted`（不能静默忽略未知迁移）。
- 历史名称/校验和与当前定义不一致：`DataCorrupted`；只有 `repair` 可在显式调用下更新。
- 历史 `applied_order` 非严格递增/重复：`DataCorrupted`。
- 本次列表存在版本小于已应用最大版本且未应用：`migrate*`/`validate` 返回 `InvalidArgument`（out-of-order）；`pending` 仍列出该迁移但不应用。
- 锁定失败：等待超过 `lockTimeoutMillis` → `Timeout`；`Context` 取消 → `Cancelled`；释放时丢失 owner → `Busy`。
- 迁移执行错误：回滚当前事务，释放锁，返回原始 SQL 错误；之前已提交的迁移保持应用。
- 提交错误：返回错误；事务可能结果不确定；历史可能已写/未写；调用方用 `appliedVersions`/`validate` 检查。
- 锁释放错误在主操作成功后返回；主操作失败时主错误优先。
- 错误文本只含版本/名称/表名/kind；不含 SQL 正文/参数值/URI。

#### `migrate`

- 空列表返回 `Ok(0)`，不建表、不取锁。
- 目标为列表中最大版本；等价 `migrateTo(context, migrations, 最大版本)`。
- 先校验输入/历史，再获取锁；锁内再次读取历史（避免 TOCTOU），然后应用。
- 每个迁移：刷新锁租约 → 开启事务 → 执行 up → 插入历史行 → 提交。
- 返回本次成功应用的迁移数；已是最新返回 0。
- 失败时之前成功的迁移保持；不返回部分计数。

#### `migrateTo`

- `targetVersion` 必须在本次列表中；否则 `InvalidArgument`。
- 只应用版本 ≤ 目标的 pending；目标已应用时校验历史后返回 0。
- 若 pending 中有版本小于已应用最大版本且 ≤ 目标，返回 out-of-order `InvalidArgument`。
- 返回本次成功应用数。
- 目标版本不能是“跳过中间缺失版本”的占位；列表必须包含从已应用到目标的全部迁移；缺失中间版本不会自动补，按顺序应用现有 pending（版本跳跃是允许的，历史记录实际版本）。out-of-order 只针对低于已应用最大版本的新迁移。

#### `rollbackLast`

- 读取历史；无已应用迁移返回 0。
- 最后一行按 `applied_order` 最大者；对应迁移必须在本次列表中，且有 down；否则 `DataCorrupted`/`Unsupported`。
- 单事务执行 down（按定义顺序）+ 删除历史行；提交；返回 1。
- 失败回滚当前事务；历史不变；返回原始错误。

#### `rollbackTo`

- `targetVersion` 必须在本次列表中且已应用；否则 `InvalidArgument`。
- 回滚所有 `applied_order` 大于目标行的迁移；目标行保留。
- 预检所有将被回滚的迁移都有 down；任一缺失 → `Unsupported`，不执行任何回滚。
- 每个迁移独立事务；逆序执行；部分失败时已回滚的保持回滚，返回错误；调用方用 `appliedVersions` 检查。
- 返回回滚数；目标就是最后一行时返回 0。

#### `rollbackAll`

- 预检全部已应用迁移都有 down；否则 `Unsupported`，不执行。
- 逆序逐个回滚；每个独立事务；返回回滚数。
- 空历史返回 0。

#### `pending`

- 校验输入/历史（版本未知/校验和不一致 → `DataCorrupted`），返回本次列表中未应用的迁移，按版本升序。
- 不检查 out-of-order；不获取锁；不建表；不执行 SQL 写入。
- 并发迁移期间可能返回过渡快照；需要一致性时在迁移完成后调用。

#### `appliedVersions`

- 历史表不存在返回空列表；否则按 `applied_order` 升序返回版本字符串。
- 不校验本次迁移列表；不获取锁；不建表。
- 返回列表副本；修改不影响历史。

#### `validate`

- 不执行迁移；不获取锁；不建表。
- 校验：输入版本唯一/合法；历史版本均存在；名称/校验和一致；`applied_order` 严格递增；无 out-of-order pending。
- 历史不存在 → `Ok(unit)`。
- `DataCorrupted` 表示历史/定义漂移；`InvalidArgument` 表示输入列表/顺序问题。

#### `repair`

- 显式危险操作：读取历史；对每个历史版本找到对应迁移；若名称/校验和不同，更新历史行的名称/校验和；不改变 `applied_order`/时间/版本。
- 历史中有本次列表不存在的版本 → `DataCorrupted`，不更新任何行（先全量校验，再更新）。
- 返回更新行数；无需更新返回 0；历史表不存在返回 0。
- 获取锁；全部更新在一个事务内完成；任一失败回滚并返回错误，不留下部分更新。
- 不删除历史行、不删除 schema 对象、不修复部分失败的 DDL。
- 不自动调用；调用方必须明确知道脚本变更原因。

#### `historyTable` / `describe`

- `historyTable()` 返回构造时的名称；不含 schema/URI。
- `describe()` 形如 `"MigrationRunner(history=app_schema_history lockTimeoutMs=30000 lockLeaseMs=3600000)"`；不含 SQL/URI。

---

## 8. 使用的技术

- 显式迁移列表 + 版本排序；
- 历史表审计；
- FNV-1a 校验和漂移检测；
- 每迁移事务；
- 表行迁移锁（owner + 墙钟过期）；
- 锁租约刷新；
- 预检回滚能力；
- 只读状态查询；
- 显式修复；
- 无全局注册表、无文件扫描、无 schema diff。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Long、Bool、String、Result、Unit；
- 运行时：`nowMono`（耗时）、`nowWall`（锁/历史时间）、`randomLong`（锁 owner）、`sleepMillis(Context, Long)`、`str(Int/Long/Bool)`、`trim(String)`、`substring`、`indexOf`；
- 数据库：`Database.execute/begin/poolStats`、`SqlConnection.execute`、`SqlTransaction.execute/commit/rollback/close`、`SqlStatement`、`SqlValue`、`SqlResult.rows/rowsAffected`、`SqlRow`、`SqlOptions`；
- 接口：`Migration`、`compareVersion`、`Database`、`Context`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

[`Migration`](Migration.md)、[`Database`](Database.md)、[`DatabasePoolStats`](DatabasePoolStats.md)、[`SqlStatement`](../../network/sql/SqlStatement.md)、[`SqlResult`](../../network/sql/SqlResult.md)、[`SqlRow`](../../network/sql/SqlRow.md)、[`SqlTransaction`](../../network/sql/SqlTransaction.md)、[`SqlOptions`](../../network/sql/SqlOptions.md)、[`SqlValue`](../../network/sql/SqlValue.md)、[`Context`](../../core/execution/Context.md)、[`Error`](../../core/errors/Error.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

- runner 借用 `Database`；不拥有连接/池；不关闭数据库。
- 每次写操作独立获取/释放锁；不持有进程内全局锁；两个 runner 对同一历史表通过锁表串行化。
- 读方法不加锁；可与迁移并发，结果是过渡快照；需要一致视图时在迁移完成后读取。
- 同一 runner 可跨任务并发调用；锁表保证写操作串行，但等待者可能超时；不要在同一任务内递归 `migrate`（会等待自己持有的锁直到超时）。
- 输入迁移列表借用；runner 复制/排序副本，不修改调用方列表；`Migration` 不可变。
- 历史表/锁表由 runner 维护；调用方不应直接写；直接写会破坏不变量并可能导致 `DataCorrupted`。
- 相等：引用身份；不提供 `equals`；不同 runner 永不相等。
- 无 close；无资源所有权转移。

---

## 12. 示例与反例

正确：

```text
List<Migration> migrations = [migration1, migration2, migration3]
MigrationRunner runner = new MigrationRunner(database, "app_schema_history")

Result<Int, Error> applied = runner.migrate(context, migrations)
Result<List<Migration>, Error> waiting = runner.pending(context, migrations)
Result<Unit, Error> checked = runner.validate(context, migrations)
```

回滚：

```text
Result<Int, Error> rolledBack = runner.rollbackTo(context, migrations, "1.2")
Result<Int, Error> all = runner.rollbackAll(context, migrations)
```

反例：

- 期望 runner 扫描目录/类路径自动发现迁移；列表必须显式传入。
- 修改已应用迁移的 SQL 后直接 `migrate`；会得到 `DataCorrupted`，应显式评估后用 `repair`。
- 在多个实例同时启动时依赖“先查后插”无锁；必须让 runner 获取锁。
- 把 `lockTimeoutMillis=0` 且不可取消 context 用于生产；可能无限等待。
- 把锁租约设得比最长迁移短；另一个实例可能接管并重复执行。
- 期望 `rollbackTo` 回滚目标版本自身；它保留目标版本。
- 期望跨多个迁移的大事务；每个迁移独立事务。
- 期望 DDL 在 MySQL/Oracle 等自动提交环境中完整回滚。
- 在 `pending` 中期望一致快照；它不加锁。
- 用 `repair` 删除历史行/清理失败 schema；它只更新名称/校验和。
- 在迁移名称中放秘密；名称进入历史表/错误文本。
- 在单任务中先 `migrate` 再递归 `migrate`；会等待自己持有的锁。

---

## 13. 测试/场景义务

- 构造：表名合法/非法/超长/大小写；timeout/lease 边界；database null；
- 输入：空列表、单条、多条、重复版本、未排序、非法版本/空 up（构造期）；
- 历史不存在：migrate 创建/应用；rollback 0；pending 全部；applied []；validate Ok；repair 0；
- migrate 从空/部分/最新；migrateTo 目标已应用/未应用/不存在；out-of-order 拒绝；
- 历史校验：未知版本、名称/校验和漂移、applied_order 重复/倒退；
- 每个迁移事务：up 成功+历史写入；up 失败回滚；历史插入失败回滚；提交失败；
- 回滚：last/to/all；目标自身保留；缺 down 预检不执行；逆序；部分失败；
- 锁：获取/等待/超时/取消/释放/丢失 owner/过期接管/刷新；两个 runner 并发串行；
- 锁租约过期后接管；墙钟回拨场景文档化；
- repair：更新名称/校验和、未知版本不更新、返回计数；
- pending/appliedVersions/validate 不加锁/不建表/不修改；
- 错误文本不含 SQL/参数/URI；版本/名称出现在诊断；
- 历史表/锁表物理类型映射（各方言）；
- 数据库关闭后操作 `Unavailable`；无全局状态；runner 不修改迁移列表；
- 并发读+迁移的过渡快照；单任务递归 migrate 超时；
- 锁表/历史表被外部破坏时的 `DataCorrupted`/错误。

---

## 14. XNull 伪代码

```xnull
class MigrationRunner {
    final Database _database
    final String _historyTable
    final String _lockTable
    final Long _lockTimeoutMillis
    final Long _lockLeaseMillis

    MigrationRunner(Database database, String historyTable) {
        if database == null {
            throw "MigrationRunner: null database"
        }
        validateTableName(historyTable)
        if historyTable.length() > 56 {
            throw "MigrationRunner: history table name too long"
        }
        _database = database
        _historyTable = historyTable
        _lockTable = historyTable + "_lock"
        validateTableName(_lockTable)
        _lockTimeoutMillis = 30000
        _lockLeaseMillis = 3600000
    }

    MigrationRunner(Database database, String historyTable,
            Long lockTimeoutMillis) {
        if database == null {
            throw "MigrationRunner: null database"
        }
        validateTableName(historyTable)
        if historyTable.length() > 56 {
            throw "MigrationRunner: history table name too long"
        }
        if lockTimeoutMillis < 0 {
            throw "MigrationRunner: negative lock timeout"
        }
        _database = database
        _historyTable = historyTable
        _lockTable = historyTable + "_lock"
        validateTableName(_lockTable)
        _lockTimeoutMillis = lockTimeoutMillis
        _lockLeaseMillis = 3600000
    }

    MigrationRunner(Database database, String historyTable,
            Long lockTimeoutMillis, Long lockLeaseMillis) {
        if database == null {
            throw "MigrationRunner: null database"
        }
        validateTableName(historyTable)
        if historyTable.length() > 56 {
            throw "MigrationRunner: history table name too long"
        }
        if lockTimeoutMillis < 0 {
            throw "MigrationRunner: negative lock timeout"
        }
        if lockLeaseMillis < 1000 {
            throw "MigrationRunner: lock lease below 1000"
        }
        _database = database
        _historyTable = historyTable
        _lockTable = historyTable + "_lock"
        validateTableName(_lockTable)
        _lockTimeoutMillis = lockTimeoutMillis
        _lockLeaseMillis = lockLeaseMillis
    }

    String historyTable() { return _historyTable }

    Result<Int, Error> migrate(Context context, List<Migration> migrations) {
        if context == null || migrations == null {
            throw "MigrationRunner.migrate: null argument"
        }
        if migrations.length() == 0 {
            return Ok(0)
        }
        Result<List<Migration>, Error> sortedResult = sortedMigrations(migrations)
        if sortedResult.isErr() {
            return Err(sortedResult.error())
        }
        List<Migration> sorted = sortedResult.value()
        String targetVersion = sorted.get(sorted.length() - 1).version()
        return migrateTo(context, sorted, targetVersion)
    }

    Result<Int, Error> migrateTo(Context context, List<Migration> migrations,
            String targetVersion) {
        if context == null || migrations == null || targetVersion == null {
            throw "MigrationRunner.migrateTo: null argument"
        }
        Result<List<Migration>, Error> sortedResult = sortedMigrations(migrations)
        if sortedResult.isErr() {
            return Err(sortedResult.error())
        }
        List<Migration> sorted = sortedResult.value()
        Migration? target = findMigration(sorted, targetVersion)
        if target == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "migration target not found: " + targetVersion))
        }
        String owner = newLockOwner()
        Result<Unit, Error> locked = acquireLock(context, owner)
        if locked.isErr() {
            return Err(locked.error())
        }
        Result<Int, Error> applied = applyTo(context, sorted, targetVersion, owner)
        Result<Unit, Error> released = releaseLock(context, owner)
        if applied.isErr() {
            return Err(applied.error())
        }
        if released.isErr() {
            return Err(released.error())
        }
        return applied
    }

    Result<Int, Error> rollbackLast(Context context,
            List<Migration> migrations) {
        if context == null || migrations == null {
            throw "MigrationRunner.rollbackLast: null argument"
        }
        Result<List<Migration>, Error> sortedResult = sortedMigrations(migrations)
        if sortedResult.isErr() {
            return Err(sortedResult.error())
        }
        List<Migration> sorted = sortedResult.value()
        String owner = newLockOwner()
        Result<Unit, Error> locked = acquireLock(context, owner)
        if locked.isErr() {
            return Err(locked.error())
        }
        Result<List<HistoryRow>, Error> historyResult = readHistory(context)
        if historyResult.isErr() {
            releaseLock(context, owner)
            return Err(historyResult.error())
        }
        List<HistoryRow> history = historyResult.value()
        if history.length() == 0 {
            Result<Unit, Error> releasedEmpty = releaseLock(context, owner)
            if releasedEmpty.isErr() {
                return Err(releasedEmpty.error())
            }
            return Ok(0)
        }
        Long lastOrder = history.get(history.length() - 1).appliedOrder()
        Long targetOrder = lastOrder - 1
        if targetOrder < 0 { targetOrder = 0 }
        Result<Int, Error> rolled = rollbackToOrder(context, sorted, history,
            targetOrder, owner)
        Result<Unit, Error> released = releaseLock(context, owner)
        if rolled.isErr() {
            return Err(rolled.error())
        }
        if released.isErr() {
            return Err(released.error())
        }
        return rolled
    }

    Result<Int, Error> rollbackTo(Context context, List<Migration> migrations,
            String targetVersion) {
        if context == null || migrations == null || targetVersion == null {
            throw "MigrationRunner.rollbackTo: null argument"
        }
        Result<List<Migration>, Error> sortedResult = sortedMigrations(migrations)
        if sortedResult.isErr() {
            return Err(sortedResult.error())
        }
        List<Migration> sorted = sortedResult.value()
        if findMigration(sorted, targetVersion) == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "rollback target not found: " + targetVersion))
        }
        String owner = newLockOwner()
        Result<Unit, Error> locked = acquireLock(context, owner)
        if locked.isErr() {
            return Err(locked.error())
        }
        Result<List<HistoryRow>, Error> historyResult = readHistory(context)
        if historyResult.isErr() {
            releaseLock(context, owner)
            return Err(historyResult.error())
        }
        List<HistoryRow> history = historyResult.value()
        HistoryRow? targetRow = findHistoryRow(history, targetVersion)
        if targetRow == null {
            releaseLock(context, owner)
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "rollback target not applied: " + targetVersion))
        }
        Result<Int, Error> rolled = rollbackToOrder(context, sorted, history,
            targetRow.appliedOrder(), owner)
        Result<Unit, Error> released = releaseLock(context, owner)
        if rolled.isErr() {
            return Err(rolled.error())
        }
        if released.isErr() {
            return Err(released.error())
        }
        return rolled
    }

    Result<Int, Error> rollbackAll(Context context,
            List<Migration> migrations) {
        if context == null || migrations == null {
            throw "MigrationRunner.rollbackAll: null argument"
        }
        Result<List<Migration>, Error> sortedResult = sortedMigrations(migrations)
        if sortedResult.isErr() {
            return Err(sortedResult.error())
        }
        List<Migration> sorted = sortedResult.value()
        String owner = newLockOwner()
        Result<Unit, Error> locked = acquireLock(context, owner)
        if locked.isErr() {
            return Err(locked.error())
        }
        Result<List<HistoryRow>, Error> historyResult = readHistory(context)
        if historyResult.isErr() {
            releaseLock(context, owner)
            return Err(historyResult.error())
        }
        Result<Int, Error> rolled = rollbackToOrder(context, sorted,
            historyResult.value(), 0, owner)
        Result<Unit, Error> released = releaseLock(context, owner)
        if rolled.isErr() {
            return Err(rolled.error())
        }
        if released.isErr() {
            return Err(released.error())
        }
        return rolled
    }

    Result<List<Migration>, Error> pending(Context context,
            List<Migration> migrations) {
        if context == null || migrations == null {
            throw "MigrationRunner.pending: null argument"
        }
        Result<List<Migration>, Error> sortedResult = sortedMigrations(migrations)
        if sortedResult.isErr() {
            return Err(sortedResult.error())
        }
        List<Migration> sorted = sortedResult.value()
        Result<List<HistoryRow>, Error> historyResult = readHistory(context)
        if historyResult.isErr() {
            return Err(historyResult.error())
        }
        List<HistoryRow> history = historyResult.value()
        Result<Unit, Error> checked = checkHistory(sorted, history, false)
        if checked.isErr() {
            return Err(checked.error())
        }
        List<Migration> result = []
        Int index = 0
        while index < sorted.length() {
            Migration migration = sorted.get(index)
            if findHistoryRow(history, migration.version()) == null {
                result.push(migration)
            }
            index = index + 1
        }
        return Ok(result)
    }

    Result<List<String>, Error> appliedVersions(Context context) {
        if context == null {
            throw "MigrationRunner.appliedVersions: null context"
        }
        Result<List<HistoryRow>, Error> historyResult = readHistory(context)
        if historyResult.isErr() {
            return Err(historyResult.error())
        }
        List<HistoryRow> history = historyResult.value()
        List<String> result = []
        Int index = 0
        while index < history.length() {
            result.push(history.get(index).version())
            index = index + 1
        }
        return Ok(result)
    }

    Result<Unit, Error> validate(Context context,
            List<Migration> migrations) {
        if context == null || migrations == null {
            throw "MigrationRunner.validate: null argument"
        }
        Result<List<Migration>, Error> sortedResult = sortedMigrations(migrations)
        if sortedResult.isErr() {
            return Err(sortedResult.error())
        }
        List<Migration> sorted = sortedResult.value()
        Result<List<HistoryRow>, Error> historyResult = readHistory(context)
        if historyResult.isErr() {
            return Err(historyResult.error())
        }
        return checkHistory(sorted, historyResult.value(), true)
    }

    Result<Int, Error> repair(Context context, List<Migration> migrations) {
        if context == null || migrations == null {
            throw "MigrationRunner.repair: null argument"
        }
        Result<List<Migration>, Error> sortedResult = sortedMigrations(migrations)
        if sortedResult.isErr() {
            return Err(sortedResult.error())
        }
        List<Migration> sorted = sortedResult.value()
        String owner = newLockOwner()
        Result<Unit, Error> locked = acquireLock(context, owner)
        if locked.isErr() {
            return Err(locked.error())
        }
        Result<Int, Error> repaired = repairLocked(context, sorted)
        Result<Unit, Error> released = releaseLock(context, owner)
        if repaired.isErr() {
            return Err(repaired.error())
        }
        if released.isErr() {
            return Err(released.error())
        }
        return repaired
    }

    String describe() {
        return "MigrationRunner(history=" + _historyTable
            + " lockTimeoutMs=" + str(_lockTimeoutMillis)
            + " lockLeaseMs=" + str(_lockLeaseMillis) + ")"
    }

    private Result<Int, Error> applyTo(Context context,
            List<Migration> sorted, String targetVersion, String owner) {
        Result<Unit, Error> ensured = ensureHistoryTable(context)
        if ensured.isErr() {
            return Err(ensured.error())
        }
        Result<List<HistoryRow>, Error> historyResult = readHistory(context)
        if historyResult.isErr() {
            return Err(historyResult.error())
        }
        List<HistoryRow> history = historyResult.value()
        Result<Unit, Error> checked = checkHistory(sorted, history, true)
        if checked.isErr() {
            return Err(checked.error())
        }
        Long maxOrder = 0
        String maxVersion = ""
        if history.length() > 0 {
            HistoryRow last = history.get(history.length() - 1)
            maxOrder = last.appliedOrder()
            maxVersion = last.version()
        }
        Int applied = 0
        Int index = 0
        while index < sorted.length() {
            Migration migration = sorted.get(index)
            if findHistoryRow(history, migration.version()) != null {
                index = index + 1
                continue
            }
            if Migration.compareVersion(migration.version(), targetVersion) > 0 {
                break
            }
            if maxVersion != ""
                    && Migration.compareVersion(migration.version(), maxVersion) < 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "out-of-order migration: " + migration.version()))
            }
            Result<Unit, Error> refreshed = refreshLock(context, owner)
            if refreshed.isErr() {
                return Err(refreshed.error())
            }
            Long order = maxOrder + 1
            Result<Unit, Error> one = applyMigration(context, migration,
                order, owner)
            if one.isErr() {
                return Err(one.error())
            }
            maxOrder = order
            maxVersion = migration.version()
            applied = applied + 1
            index = index + 1
        }
        return Ok(applied)
    }

    private Result<Unit, Error> applyMigration(Context context,
            Migration migration, Long appliedOrder, String owner) {
        Long started = nowMono()
        Result<SqlTransaction, Error> startedTransaction =
            _database.begin(context)
        if startedTransaction.isErr() {
            return Err(startedTransaction.error())
        }
        SqlTransaction transaction = startedTransaction.value()
        List<SqlStatement> statements = migration.upStatements()
        Int index = 0
        while index < statements.length() {
            Result<SqlResult, Error> executed =
                transaction.execute(context, statements.get(index))
            if executed.isErr() {
                transaction.rollback(context)
                transaction.close()
                return Err(executed.error())
            }
            index = index + 1
        }
        Long executionMillis = nowMono() - started
        Result<Unit, Error> recorded = insertHistory(context, transaction,
            migration, appliedOrder, executionMillis)
        if recorded.isErr() {
            transaction.rollback(context)
            transaction.close()
            return Err(recorded.error())
        }
        Result<Unit, Error> committed = transaction.commit(context)
        if committed.isErr() {
            return Err(committed.error())
        }
        return Ok(unit)
    }

    private Result<Int, Error> rollbackToOrder(Context context,
            List<Migration> sorted, List<HistoryRow> history,
            Long targetOrder, String owner) {
        Result<Unit, Error> checked = checkHistory(sorted, history, false)
        if checked.isErr() {
            return Err(checked.error())
        }
        List<HistoryRow> targets = []
        Int index = 0
        while index < history.length() {
            HistoryRow row = history.get(index)
            if row.appliedOrder() > targetOrder {
                targets.push(row)
            }
            index = index + 1
        }
        index = 0
        while index < targets.length() {
            HistoryRow row = targets.get(index)
            Migration? migration = findMigration(sorted, row.version())
            if migration == null {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "history version missing: " + row.version()))
            }
            if !migration.hasRollback() {
                return Err(new BasicError(ErrorKind.Unsupported,
                    "migration has no down statements: " + row.version()))
            }
            index = index + 1
        }
        Int rolledBack = 0
        index = targets.length() - 1
        while index >= 0 {
            HistoryRow row = targets.get(index)
            Migration? found = findMigration(sorted, row.version())
            if found == null {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "history version missing: " + row.version()))
            }
            Migration migration = found as Migration
            Result<Unit, Error> refreshed = refreshLock(context, owner)
            if refreshed.isErr() {
                return Err(refreshed.error())
            }
            Result<Unit, Error> one = rollbackMigration(context, migration, row)
            if one.isErr() {
                return Err(one.error())
            }
            rolledBack = rolledBack + 1
            index = index - 1
        }
        return Ok(rolledBack)
    }

    private Result<Unit, Error> rollbackMigration(Context context,
            Migration migration, HistoryRow row) {
        Result<SqlTransaction, Error> started = _database.begin(context)
        if started.isErr() {
            return Err(started.error())
        }
        SqlTransaction transaction = started.value()
        List<SqlStatement> statements = migration.downStatements()
        Int index = 0
        while index < statements.length() {
            Result<SqlResult, Error> executed =
                transaction.execute(context, statements.get(index))
            if executed.isErr() {
                transaction.rollback(context)
                transaction.close()
                return Err(executed.error())
            }
            index = index + 1
        }
        Result<Unit, Error> deleted = deleteHistory(context, transaction,
            row.version())
        if deleted.isErr() {
            transaction.rollback(context)
            transaction.close()
            return Err(deleted.error())
        }
        Result<Unit, Error> committed = transaction.commit(context)
        if committed.isErr() {
            return Err(committed.error())
        }
        return Ok(unit)
    }

    private Result<Int, Error> repairLocked(Context context,
            List<Migration> sorted) {
        Result<Bool, Error> historyExistsResult = historyExists(context)
        if historyExistsResult.isErr() {
            return Err(historyExistsResult.error())
        }
        if !historyExistsResult.value() {
            return Ok(0)
        }
        Result<List<HistoryRow>, Error> historyResult = readHistory(context)
        if historyResult.isErr() {
            return Err(historyResult.error())
        }
        List<HistoryRow> history = historyResult.value()
        Long previousOrder = 0
        String previousVersion = ""
        Int index = 0
        while index < history.length() {
            HistoryRow row = history.get(index)
            if row.appliedOrder() <= previousOrder {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "history order invalid: " + row.version()))
            }
            if previousVersion != ""
                    && Migration.compareVersion(row.version(), previousVersion) <= 0 {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "history version order invalid: " + row.version()))
            }
            if findMigration(sorted, row.version()) == null {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "history version missing: " + row.version()))
            }
            previousOrder = row.appliedOrder()
            previousVersion = row.version()
            index = index + 1
        }
        Result<SqlTransaction, Error> started = _database.begin(context)
        if started.isErr() {
            return Err(started.error())
        }
        SqlTransaction transaction = started.value()
        Int updated = 0
        index = 0
        while index < history.length() {
            HistoryRow row = history.get(index)
            Migration? found = findMigration(sorted, row.version())
            if found == null {
                transaction.rollback(context)
                transaction.close()
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "history version missing: " + row.version()))
            }
            Migration migration = found as Migration
            if row.name() != migration.name()
                    || row.checksum() != migration.checksum() {
                Result<Unit, Error> repaired = updateHistoryChecksum(
                    context, transaction, row.version(), migration.name(),
                    migration.checksum())
                if repaired.isErr() {
                    transaction.rollback(context)
                    transaction.close()
                    return Err(repaired.error())
                }
                updated = updated + 1
            }
            index = index + 1
        }
        Result<Unit, Error> committed = transaction.commit(context)
        if committed.isErr() {
            return Err(committed.error())
        }
        return Ok(updated)
    }

    private Result<Unit, Error> checkHistory(List<Migration> sorted,
            List<HistoryRow> history, Bool checkOutOfOrder) {
        Long previousOrder = 0
        String maxVersion = ""
        Int index = 0
        while index < history.length() {
            HistoryRow row = history.get(index)
            if row.appliedOrder() <= previousOrder {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "history order invalid: " + row.version()))
            }
            Migration? migration = findMigration(sorted, row.version())
            if migration == null {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "history version missing: " + row.version()))
            }
            if row.name() != migration.name()
                    || row.checksum() != migration.checksum() {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "migration checksum mismatch: " + row.version()))
            }
            if maxVersion != ""
                    && Migration.compareVersion(row.version(), maxVersion) <= 0 {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "history version order invalid: " + row.version()))
            }
            previousOrder = row.appliedOrder()
            maxVersion = row.version()
            index = index + 1
        }
        if !checkOutOfOrder || maxVersion == "" {
            return Ok(unit)
        }
        index = 0
        while index < sorted.length() {
            Migration migration = sorted.get(index)
            if findHistoryRow(history, migration.version()) == null
                    && Migration.compareVersion(migration.version(),
                        maxVersion) < 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "out-of-order pending migration: "
                        + migration.version()))
            }
            index = index + 1
        }
        return Ok(unit)
    }

    private Result<List<Migration>, Error> sortedMigrations(
            List<Migration> migrations) {
        List<Migration> copy = migrations.copy()
        Int index = 0
        while index < copy.length() {
            if copy.get(index) == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "null migration at " + str(index)))
            }
            index = index + 1
        }
        index = 1
        while index < copy.length() {
            Migration current = copy.get(index)
            Int scan = index - 1
            while scan >= 0 && copy.get(scan).compareTo(current) > 0 {
                copy.set(scan + 1, copy.get(scan))
                scan = scan - 1
            }
            copy.set(scan + 1, current)
            index = index + 1
        }
        index = 1
        while index < copy.length() {
            if copy.get(index - 1).compareTo(copy.get(index)) == 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "duplicate migration version: "
                        + copy.get(index).version()))
            }
            index = index + 1
        }
        return Ok(copy)
    }

    private Migration? findMigration(List<Migration> migrations,
            String version) {
        Int index = 0
        while index < migrations.length() {
            if migrations.get(index).version() == version {
                return migrations.get(index)
            }
            index = index + 1
        }
        return null
    }

    private HistoryRow? findHistoryRow(List<HistoryRow> history,
            String version) {
        Int index = 0
        while index < history.length() {
            if history.get(index).version() == version {
                return history.get(index)
            }
            index = index + 1
        }
        return null
    }

    private String newLockOwner() {
        return _database.name() + ":" + str(nowWall()) + ":"
            + str(randomLong())
    }

    private Result<Unit, Error> acquireLock(Context context, String owner) {
        Result<Unit, Error> ensured = ensureLockTable(context)
        if ensured.isErr() {
            return Err(ensured.error())
        }
        Long deadline = 0
        if _lockTimeoutMillis > 0 {
            deadline = nowMono() + _lockTimeoutMillis
        }
        while true {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "migration lock cancelled"))
            }
            Long expires = nowWall() + _lockLeaseMillis
            SqlStatement update = new SqlStatement(
                "update " + _lockTable
                + " set owner = ?, expires_at_millis = ?"
                + " where lock_name = 'migration'"
                + " and (owner = '' or expires_at_millis <= ?)")
                .bind(SqlValue.ofString(owner))
                .bind(SqlValue.ofLong(expires))
                .bind(SqlValue.ofLong(nowWall()))
            Result<SqlResult, Error> updated =
                _database.execute(context, update)
            if updated.isErr() {
                return Err(updated.error())
            }
            if updated.value().rowsAffected() == 1 {
                return Ok(unit)
            }
            SqlStatement insert = new SqlStatement(
                "insert into " + _lockTable
                + " (lock_name, owner, expires_at_millis)"
                + " values ('migration', ?, ?)")
                .bind(SqlValue.ofString(owner))
                .bind(SqlValue.ofLong(expires))
            Result<SqlResult, Error> inserted =
                _database.execute(context, insert)
            if inserted.isOk() {
                return Ok(unit)
            }
            ErrorKind insertKind = inserted.error().kind()
            if insertKind != ErrorKind.AlreadyExists
                    && insertKind != ErrorKind.InvalidArgument {
                return Err(inserted.error())
            }
            if deadline > 0 && nowMono() >= deadline {
                return Err(new BasicError(ErrorKind.Timeout,
                    "migration lock timeout"))
            }
            Result<Unit, Error> slept = sleepMillis(context, 100)
            if slept.isErr() {
                return Err(slept.error())
            }
        }
    }

    private Result<Unit, Error> refreshLock(Context context, String owner) {
        Long expires = nowWall() + _lockLeaseMillis
        SqlStatement statement = new SqlStatement(
            "update " + _lockTable
            + " set expires_at_millis = ?"
            + " where lock_name = 'migration' and owner = ?")
            .bind(SqlValue.ofLong(expires))
            .bind(SqlValue.ofString(owner))
        Result<SqlResult, Error> updated =
            _database.execute(context, statement)
        if updated.isErr() {
            return Err(updated.error())
        }
        if updated.value().rowsAffected() != 1 {
            return Err(new BasicError(ErrorKind.Busy,
                "migration lock lost"))
        }
        return Ok(unit)
    }

    private Result<Unit, Error> releaseLock(Context context, String owner) {
        SqlStatement statement = new SqlStatement(
            "update " + _lockTable
            + " set owner = '', expires_at_millis = 0"
            + " where lock_name = 'migration' and owner = ?")
            .bind(SqlValue.ofString(owner))
        Result<SqlResult, Error> updated =
            _database.execute(context, statement)
        if updated.isErr() {
            return Err(updated.error())
        }
        if updated.value().rowsAffected() != 1 {
            return Err(new BasicError(ErrorKind.Busy,
                "migration lock release lost"))
        }
        return Ok(unit)
    }

    private Result<Unit, Error> ensureHistoryTable(Context context) {
        Result<Bool, Error> exists = historyExists(context)
        if exists.isErr() {
            return Err(exists.error())
        }
        if exists.value() {
            return Ok(unit)
        }
        SqlStatement create = new SqlStatement(
            "create table " + _historyTable
            + " (version varchar(64) primary key,"
            + " name varchar(200) not null,"
            + " checksum bigint not null,"
            + " applied_order bigint not null unique,"
            + " applied_at_millis bigint not null,"
            + " execution_millis bigint not null)")
        Result<SqlResult, Error> created =
            _database.execute(context, create)
        Result<Bool, Error> verified = historyExists(context)
        if verified.isErr() {
            return Err(verified.error())
        }
        if !verified.value() {
            if created.isErr() {
                return Err(created.error())
            }
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "migration history table unavailable"))
        }
        return Ok(unit)
    }

    private Result<Unit, Error> ensureLockTable(Context context) {
        Result<Bool, Error> exists = tableExists(context, _lockTable)
        if exists.isErr() {
            return Err(exists.error())
        }
        if exists.value() {
            return Ok(unit)
        }
        SqlStatement create = new SqlStatement(
            "create table " + _lockTable
            + " (lock_name varchar(64) primary key,"
            + " owner varchar(160) not null,"
            + " expires_at_millis bigint not null)")
        Result<SqlResult, Error> created =
            _database.execute(context, create)
        Result<Bool, Error> verified = tableExists(context, _lockTable)
        if verified.isErr() {
            return Err(verified.error())
        }
        if !verified.value() {
            if created.isErr() {
                return Err(created.error())
            }
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "migration lock table unavailable"))
        }
        return Ok(unit)
    }

    private Result<Bool, Error> historyExists(Context context) {
        return tableExists(context, _historyTable)
    }

    private Result<Bool, Error> tableExists(Context context, String tableName) {
        SqlStatement probe = new SqlStatement(
            "select 1 from " + tableName + " where 1 = 0")
        Result<SqlResult, Error> probed = _database.execute(context, probe)
        if probed.isOk() {
            return Ok(true)
        }
        if probed.error().kind() == ErrorKind.InvalidArgument
                || probed.error().kind() == ErrorKind.NotFound {
            return Ok(false)
        }
        return Err(probed.error())
    }

    private Result<List<HistoryRow>, Error> readHistory(Context context) {
        Result<Bool, Error> exists = historyExists(context)
        if exists.isErr() {
            return Err(exists.error())
        }
        if !exists.value() {
            return Ok([])
        }
        SqlStatement query = new SqlStatement(
            "select version, name, checksum, applied_order,"
            + " applied_at_millis, execution_millis from " + _historyTable
            + " order by applied_order")
        Result<SqlResult, Error> queried = _database.execute(context, query)
        if queried.isErr() {
            return Err(queried.error())
        }
        SqlResult result = queried.value()
        if !result.isQuery() {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "migration history is not a query"))
        }
        List<HistoryRow> history = []
        List<SqlRow> rows = result.rows()
        Int index = 0
        while index < rows.length() {
            SqlRow row = rows.get(index)
            Result<String, Error> version = row.get(0).asString()
            Result<String, Error> name = row.get(1).asString()
            Result<Long, Error> checksum = row.get(2).asLong()
            Result<Long, Error> order = row.get(3).asLong()
            Result<Long, Error> appliedAt = row.get(4).asLong()
            Result<Long, Error> execution = row.get(5).asLong()
            if version.isErr() || name.isErr() || checksum.isErr()
                    || order.isErr() || appliedAt.isErr()
                    || execution.isErr() {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "migration history row malformed"))
            }
            history.push(new HistoryRow(version.value(), name.value(),
                checksum.value(), order.value(), appliedAt.value(),
                execution.value()))
            index = index + 1
        }
        return Ok(history)
    }

    private Result<Unit, Error> insertHistory(Context context,
            SqlTransaction transaction, Migration migration,
            Long appliedOrder, Long executionMillis) {
        SqlStatement insert = new SqlStatement(
            "insert into " + _historyTable
            + " (version, name, checksum, applied_order,"
            + " applied_at_millis, execution_millis)"
            + " values (?, ?, ?, ?, ?, ?)")
            .bind(SqlValue.ofString(migration.version()))
            .bind(SqlValue.ofString(migration.name()))
            .bind(SqlValue.ofLong(migration.checksum()))
            .bind(SqlValue.ofLong(appliedOrder))
            .bind(SqlValue.ofLong(nowWall()))
            .bind(SqlValue.ofLong(executionMillis))
        Result<SqlResult, Error> inserted =
            transaction.execute(context, insert)
        if inserted.isErr() {
            return Err(inserted.error())
        }
        return Ok(unit)
    }

    private Result<Unit, Error> deleteHistory(Context context,
            SqlTransaction transaction, String version) {
        SqlStatement delete = new SqlStatement(
            "delete from " + _historyTable + " where version = ?")
            .bind(SqlValue.ofString(version))
        Result<SqlResult, Error> deleted =
            transaction.execute(context, delete)
        if deleted.isErr() {
            return Err(deleted.error())
        }
        return Ok(unit)
    }

    private Result<Unit, Error> updateHistoryChecksum(Context context,
            SqlTransaction transaction, String version, String name,
            Long checksum) {
        SqlStatement update = new SqlStatement(
            "update " + _historyTable
            + " set name = ?, checksum = ? where version = ?")
            .bind(SqlValue.ofString(name))
            .bind(SqlValue.ofLong(checksum))
            .bind(SqlValue.ofString(version))
        Result<SqlResult, Error> updated =
            transaction.execute(context, update)
        if updated.isErr() {
            return Err(updated.error())
        }
        if updated.value().rowsAffected() != 1 {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "history update missed: " + version))
        }
        return Ok(unit)
    }

    private static void validateTableName(String tableName) {
        if tableName == null || tableName.length() == 0 || tableName.length() > 64 {
            throw "MigrationRunner: invalid table name length"
        }
        String first = tableName.substring(0, 1)
        if !isAsciiLetter(first) && first != "_" {
            throw "MigrationRunner: invalid table name start"
        }
        Int index = 1
        while index < tableName.length() {
            String character = tableName.substring(index, 1)
            if !isAsciiLetter(character) && !isAsciiDigit(character)
                    && character != "_" {
                throw "MigrationRunner: invalid table name character"
            }
            index = index + 1
        }
    }
}

class HistoryRow {
    final String _version
    final String _name
    final Long _checksum
    final Long _appliedOrder
    final Long _appliedAtMillis
    final Long _executionMillis

    HistoryRow(String version, String name, Long checksum,
               Long appliedOrder, Long appliedAtMillis,
               Long executionMillis) {
        _version = version
        _name = name
        _checksum = checksum
        _appliedOrder = appliedOrder
        _appliedAtMillis = appliedAtMillis
        _executionMillis = executionMillis
    }

    String version() { return _version }
    String name() { return _name }
    Long checksum() { return _checksum }
    Long appliedOrder() { return _appliedOrder }
    Long appliedAtMillis() { return _appliedAtMillis }
    Long executionMillis() { return _executionMillis }
}
```

> 伪代码非可执行。`HistoryRow` 是文件内实现类型；`validateTableName` 为类内私有静态校验辅助。历史/锁表 SQL 是固定内部模板，不是通用 SQL 构建器；表名只来自构造校验。`sleepMillis`、`randomLong`、`nowWall` 是运行时原语；锁过期跨进程使用墙钟，部署需时钟同步。`readHistory` 的实现应校验列数与 `tryGet`，畸形行返回 `DataCorrupted`；伪代码简化为按索引 `get`。
