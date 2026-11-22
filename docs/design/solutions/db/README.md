# `xdk.db` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.db` |
| 层 | L8 solutions |
| 依赖 | `xdk.core`、`xdk.sql`、`xdk.crypto`（迁移校验和） |
| 被依赖 | 应用服务、后台任务、CLI 工具、数据导入/导出、管理面 |
| 稳定性 | `preview`；不进入 1.0 公共承诺 |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件；公开类型共 11 个 |

> 上层索引见 [`../README.md`](../README.md)；SQL 接口基线见 [`../../network/sql/README.md`](../../network/sql/README.md)。

---

## 1. 包定位

`xdk.db` 是**应用级数据库工具箱**，构建在 `xdk.sql` 之上：

- 管理数据库句柄、连接池、连接租约、事务作用域与关闭；
- 提供批量执行、行映射、健康快照与迁移执行；
- 把连接、超时、池参数、迁移顺序与校验和收敛为一套显式契约；
- 驱动仍由生态实现，`xdk.db` 不内置任何数据库驱动。

`xdk.db` **不是**：

- 不是 ORM：不做实体映射、关系加载、变更跟踪、懒加载、身份映射；
- 不是 SQL 构建器/解析器：SQL 文本与参数仍由调用方通过 `SqlStatement` 提供；
- 不是驱动注册表：不提供服务加载、自动发现、全局连接池；
- 不是数据库抽象层的新方言：方言、值模型、执行协议仍归 `xdk.sql`；
- 不是迁移脚本生成器：不做 schema diff、自动生成、模型反射。

```text
应用
  │
  ▼
xdk.db
  ├─ Db.open / Db.openPool        静态入口，无全局状态
  ├─ Database                     应用句柄，按操作借还
  ├─ DatabasePool                 连接池，显式创建、显式关闭
  ├─ DbBatch / RowMapper            批量与逐行映射
  ├─ DatabaseHealth               健康快照与主动刷新
  └─ MigrationRunner              有序迁移、回滚、校验、锁
        │
        ▼
xdk.sql（SqlDriver / SqlConnection / SqlTransaction / SqlStatement / SqlResult）
        │
        ▼
生态 SQL 驱动（Postgres / MySQL / SQLite / SQL Server / Oracle / ...）
```

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式依赖 | `SqlDriver` 由调用方注入；`Db` 不查全局注册表 |
| 池显式 | 连接池由 `Db.openPool` 或 `Db.open` 创建，有名字、有上限、可观测、必须关闭 |
| 无全局池 | 每次 `Db.open`/`Db.openPool` 返回独立实例；不按 URI 隐式复用 |
| 事务显式 | 自动提交只发生在单条 `execute`；多条原子操作使用 `Database.begin` 或 `DbBatch` 原子执行 |
| SQL 归 `xdk.sql` | `xdk.db` 不重定义 `SqlStatement`、`SqlResult`、`SqlTransaction` |
| 值不可变 | 配置、统计、迁移、批量快照在构造时复制列表/映射，读取返回副本 |
| 超时统一 | 池获取超时用 `Long` 毫秒；执行超时仍用 `SqlOptions`；`Context` 取消优先 |
| 关闭幂等 | `Database`、`DatabasePool`、连接租约、池化事务的 `close` 可重复调用 |
| 错误统一 | 只用 core `ErrorKind`；不新增数据库专用错误码枚举 |
| 迁移有序 | 版本显式排序、校验和固定、历史表记录、迁移锁串行化 |
| 无秘密日志 | URI、口令、令牌、SQL 参数值、迁移正文不进入诊断文本 |
| 无裸句柄 | 驱动句柄只存在于实现内部；公共 API 不暴露指针/文件描述符 |

---

## 3. 架构与生命周期

### 3.1 创建

```text
Db.open(context, driver, config)
  └─ DatabasePool.open(context, driver, config)
       ├─ 校验 config
       ├─ failFast=true：建立并验证初始连接
       └─ 返回 Database（拥有 pool）
```

- `Db.open` 返回的 `Database` 拥有连接池；`Database.close` 关闭池。
- `Db.openPool` 只返回 `DatabasePool`，由调用方管理生命周期。
- 驱动对象由调用方持有；`xdk.db` 不关闭驱动（`SqlDriver` 协议无 `close`）。
- `failFast=false` 允许数据库暂时不可用时先创建句柄；第一次取连接才暴露连接错误。
- 连接池不会在后台隐式重建；数据库重启后由调用方关闭旧池并重新打开。

### 3.2 使用

```text
Database.execute/query/queryOne/batch
  └─ DatabasePool.acquire(context) → 连接租约 → 归还/丢弃

Database.begin(context)
  └─ 连接租约 + SqlTransaction → 事务结束自动归还/丢弃连接
```

- `Database.execute` 自动借还，适合短操作；多条语句需要原子性时用 `Database.begin`。
- `DatabasePool.acquire` 返回的 `SqlConnection` 是**租约包装**；`close` 把物理连接归还池，而不是关闭数据库会话。
- 租约包装的 `isOpen=false` 或池已关闭时，`close` 丢弃物理连接。
- 池化事务在 `commit`/`rollback`/`close` 后自动归还租约；失败且连接不可判定时丢弃。
- `DbBatch` 只持有语句；执行由 `Database.executeBatch` / `executeBatchAtomic` 完成。

### 3.3 关闭

```text
Database.close()
  └─ DatabasePool.close()
       ├─ 标记关闭，拒绝新获取
       ├─ 关闭空闲连接
       └─ 活动租约在归还时关闭
```

- `close` 幂等；第二次返回 `Ok(unit)`。
- 关闭后新操作返回 `Unavailable`；已借出租约上的操作按 `xdk.sql` 返回 `InvalidArgument`。
- `DatabasePool.close` 不无限等待活动租约；活动租约释放时丢弃连接。
- `MigrationRunner`、`DatabaseHealth` 不拥有数据库，不提供 `close`；它们只借用 `Database`。

---

## 4. 类型索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Database` | class | 应用句柄：执行、查询、批量、事务、池访问、关闭 | [`Database.md`](Database.md) |
| `DatabaseConfig` | class | 不可变配置：URI、驱动选项、池大小、超时、隔离级别、校验语句 | [`DatabaseConfig.md`](DatabaseConfig.md) |
| `DatabasePool` | class | 连接池：获取/归还租约、池化事务、预热、统计、关闭 | [`DatabasePool.md`](DatabasePool.md) |
| `DatabasePoolStats` | class | 不可变池统计快照：连接数、等待、计数、饱和判定 | [`DatabasePoolStats.md`](DatabasePoolStats.md) |
| `IsolationLevel` | enum | ReadUncommitted/ReadCommitted/RepeatableRead/Serializable | [`IsolationLevel.md`](IsolationLevel.md) |
| `Migration` | class | 不可变迁移：版本、名称、up/down 语句、校验和、排序 | [`Migration.md`](Migration.md) |
| `MigrationRunner` | class | 有序应用/回滚、审计、校验、修复、迁移锁 | [`MigrationRunner.md`](MigrationRunner.md) |
| `RowMapper` | protocol | 逐行映射到应用值；非泛型回调 | [`RowMapper.md`](RowMapper.md) |
| `DbBatch` | class | 语句批量构建器；由 `Database` 执行 | [`DbBatch.md`](DbBatch.md) |
| `DatabaseHealth` | class | 池/数据库健康快照；缓存 + 主动刷新 | [`DatabaseHealth.md`](DatabaseHealth.md) |
| `Db` | class | 静态入口：打开 Database/Pool、隔离级别选项键 | [`Db.md`](Db.md) |

> 类型索引 11 项 = 11 个类型文件。`DatabaseHealth` 实现 `xdk.runtime.HealthCheck`；其余类型不重复 core 已有类型。

---

## 5. 跨类型规则

| 规则 | 说明 |
| --- | --- |
| `Context` 首参 | 所有可能阻塞的公开方法首参为 `Context context`；`close`/纯读取除外 |
| `Result` 失败 | 可恢复失败返回 `Result<T, Error>`；参数 null/非法契约用 panic |
| 关闭幂等 | `Database`、`DatabasePool`、租约、池化事务的 `close` 幂等 |
| 池参数 | 连接数是 `Int`；累计计数/等待毫秒是 `Long`；时间量是 `Long` 毫秒 |
| 池上限 | `maximumPoolSize ≥ 1`；`minimumIdle` 在 `0..maximumPoolSize` |
| 池获取 | 等待受 `Context` 取消和 `acquireTimeoutMillis` 共同约束，先到者生效 |
| 池归还 | 归还前检查 `isOpen`、生命周期、空闲超时；不满足则关闭并丢弃 |
| 租约语义 | `DatabasePool.acquire` 返回 `SqlConnection` 租约；`close` 归还，不是物理关闭 |
| 事务语义 | `Database.begin`/`DatabasePool.begin` 返回 `SqlTransaction`；结束后自动归还租约 |
| 隔离级别 | 池级固定；通过保留 open option 传给驱动；驱动不支持返回 `Unsupported` |
| 批量顺序 | 结果列表与语句顺序一一对应；遇到错误停止，不继续后续语句 |
| 批量原子 | `executeBatchAtomic` 在单事务内执行；失败回滚；DDL 是否可回滚由数据库决定 |
| 行映射 | `RowMapper.start` 先收到列元数据，再逐行 `mapRow`；非泛型，应用值由实现持有 |
| 迁移顺序 | `version` 是点分十进制段；同一列表版本唯一；应用顺序按版本升序 |
| 迁移校验和 | 校验和覆盖版本、名称、up/down SQL 文本；不覆盖参数值 |
| 迁移历史 | 历史表由 runner 创建/维护；调用方不直接写 |
| 迁移锁 | 历史表旁的锁表行实现串行化；租约到期可被接管 |
| 无全局状态 | 无静态池、无静态注册表、无进程级迁移列表 |
| 驱动不重复配置 | `SqlDriver` 由 `Db.open`/`DatabasePool.open` 参数显式提供；`DatabaseConfig` 只带 open options，不再存驱动名/驱动实例，避免两处冲突 |
| 错误脱敏 | 诊断只含池名、驱动名、计数、错误 kind；不含 URI/口令/参数值/SQL 正文 |
| 裸句柄 | 公共签名不出现驱动句柄；内部可用不透明 `Long` |

---

## 6. 关键场景

### S1：打开、执行、关闭

`Db.open(context, driver, config)` → `database.execute(context, statement)` → `database.close()`。`execute` 自动借还；`close` 幂等。

### S2：显式连接池

`Db.openPool(context, driver, config)` → `pool.acquire(context)` 得到租约 → `lease.execute(...)` → `lease.close()` 归还；`pool.stats()` 观察活跃/空闲/等待；`pool.close()` 结束。

### S3：事务

`database.begin(context)` → `transaction.execute(context, statement)` → `transaction.commit(context)`；事务结束自动归还连接。异常路径 `rollback(context)` 或 `close()`。

### S4：批量导入

`new DbBatch().add(insertStatement).add(...)` → `database.executeBatchAtomic(context, batch)`；全部成功提交，任一失败回滚；返回按顺序排列的 `List<SqlResult>`。

### S5：逐行映射

`database.query(context, statement, mapper)`：先 `mapper.start(context, columns)` 校验列，再逐行 `mapper.mapRow(context, row)`；返回映射行数，应用值保存在 mapper 实现中。

### S6：迁移

`new MigrationRunner(database, "app_schema_history")` → `runner.migrate(context, migrations)`：校验版本/校验和、获取锁、按序执行 up、写历史、释放锁。`rollbackTo`/`rollbackAll` 反向执行 down。

### S7：健康检查

`DatabaseHealth health = new DatabaseHealth(database, "primary-db")`；后台任务定期 `health.refresh(context)`；HTTP/指标适配器读取 `health.check()` 的非阻塞缓存快照。

### S8：数据库重启

旧连接上的 `Network`/`Io` 使 `isOpen=false`；租约归还时被丢弃。调用方关闭旧 `Database`/`DatabasePool`，重新 `Db.open`；不在库内自动重连。

---

## 7. 迁移与锁策略

- **版本**：`1`、`1.2`、`2026.11.22` 这类点分十进制段；每段无前导零，最多 18 位；版本字符串最长 64。
- **顺序**：逐段比较；段多者更大；不做 SemVer 预发布/构建元数据语义。
- **校验和**：`ChecksumAlgorithm.Fnv1a64` 对规范化文本计算；用于发现“已应用脚本被改写”，不是加密完整性保护。
- **历史表**：逻辑列 `version`、`name`、`checksum`、`applied_order`、`applied_at_millis`、`execution_millis`；物理类型按方言映射。
- **锁**：锁表单行；`owner` + `expires_at_millis`；获取用条件更新/插入，释放用带 owner 的条件更新；进程崩溃后租约到期可接管。
- **事务**：每个迁移在独立事务内执行 up + 写历史；数据库不支持事务性 DDL 时可能留下部分 schema，runner 不假装原子。
- **无全局注册表**：每次调用显式传入 `List<Migration>`；runner 只保留数据库、表名、锁参数。
- **不做基线/标记已应用**：v1 不提供 `baseline`/`stamp`；接管既有库时用一次受控的 `migrate` 或外部脚本建立历史，后续版本再评估。
- **不做自动生成**：没有 schema diff、模型反射、自动回滚脚本生成。

---

## 8. 安全

| 面 | 要求 |
| --- | --- |
| 连接 URI | 可能含口令；`DatabaseConfig.describe` 只显示 `<redacted>`，错误不拼接 URI |
| 驱动选项 | 值可能含令牌；诊断只显示键数量，不显示键值 |
| SQL 参数 | `SqlStatement.describe` 不含值；`xdk.db` 不新增参数日志 |
| SQL 正文 | `Database`/`DbBatch` 诊断不含 SQL；迁移诊断不含 up/down 正文 |
| 迁移名称 | 可进入历史表和错误文本；调用方不得把秘密放进名称 |
| 健康详情 | 只含池名、计数、验证方式、错误 kind；不含连接串/查询结果 |
| 锁 owner | 随机/单调令牌；不含主机名、用户名、口令 |
| 错误文本 | 可含 SQL 状态/列名（由 `xdk.sql` 决定），不含参数值/完整连接串 |
| 权限 | 认证失败 `PermissionDenied`；权限不足不降级为“空结果” |

---

## 9. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 具体驱动 | 生态实现；`xdk.db` 不内置 Postgres/MySQL/SQLite/MSSQL/Oracle 驱动 |
| ORM/实体映射 | 不做；`RowMapper` 只做逐行回调，不提供实体/关系/变更跟踪 |
| SQL 构建/解析 | 不做；调用方提供 `SqlStatement`；内部仅用于历史表/锁表的固定 SQL |
| 全局连接池/注册表 | 不做；`Db` 无静态状态 |
| 每事务隔离级别覆盖 | v1 不做；隔离级别是池级，连接打开时固定；需要不同级别时使用独立 `Database`/池 |
| 分布式事务/XA | 不做 |
| 流式游标/增量取数 | 不做；`xdk.sql` 返回完整 `SqlResult` 快照 |
| 自动重连/故障转移 | 不做；调用方关闭旧池并重新打开 |
| 语句缓存/预编译缓存 | 不做；由驱动负责 |
| 多结果集/存储过程输出参数 | 不做 |
| 迁移自动生成/回滚生成 | 不做；`Migration` 的 up/down 由调用方提供 |
| 迁移基线/标记已应用 | v1 不做；见 §7 |
| 迁移回调/占位符替换 | 不做；需要时由调用方在构造 `Migration` 前完成 |
| 迁移并发 | 通过锁表串行化；锁租约过期可接管，超长迁移需增大租约 |
| 健康检查 | 缓存 `HealthReport` + 主动 `refresh`；不在 `check()` 内阻塞 |
| 秘密管理 | 由驱动 open options / 外部凭据提供者负责；本包不存储、不记录口令 |
| 裸句柄 | 不暴露；实现内部可用不透明 `Long` |

---

## 10. 质量门禁

- [x] 包 README 只做包级说明与类型索引，不放类方法表/类伪代码；
- [x] 11 个公开类型 = 11 个类型文件；
- [x] 每类型 14 段；枚举/协议独立成文件；
- [x] 所有阻塞方法首参 `Context`；`close`/纯读取除外；
- [x] 所有失败走 `Result` 或合同错误（panic）；
- [x] 资源类 `close` 幂等；租约/事务结束自动归还或丢弃；
- [x] 列表/映射构造时复制，读取返回副本；
- [x] 参数全名；计数用 `Int`，累计/时间用 `Long`；
- [x] 无 `self(...)`、无 `self._private`、无 `new T()`、无 `// ...`、无 Python 式条件表达式；
- [x] 无全局池、无全局注册表、无秘密日志；
- [x] 相对链接可达；不修改 `../../network/README.md` 与 `../README.md`。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Entity`、`@Table`、`@Id`、`@Transactional` |
| 本包消费 | `@Value`、`@Builder`、`@Sql`、`@Column`、`@Param`、`@Row` |
| 处理器 | DbAnnotationProcessor（Resolve/Validate/Generate） |
| 生成物 | 实体/表/列/DAO 映射、事务包装 |
| 状态 | 领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 实体类 | `@Entity`/`@Table` | 实体/表元数据 |
| 主键字段 | `@Id` | 主键元数据 |
| 事务方法 | `@Transactional` | 事务包装 |
| DAO 方法/参数/行 | `@Sql`/`@Param`/`@Row`/`@Column` | SQL 映射 |

### 声明

```x
@Target(Type)
@Retention(Source)
@annotation Entity {
    final String table
}

@Target(Type)
@Retention(Source)
@annotation Table {
    final String name
}

@Target(Field)
@Retention(Source)
@annotation Id {
}

@Target(Method)
@Retention(Source)
@annotation Transactional {
    final Bool readOnly = false
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
@Entity("users")
class User {
    @Id Long id
    @Column("display_name") String name
}

class UserRepository {
    @Sql("SELECT id, display_name FROM users WHERE id = :id")
    Result<User, Error> find(@Param("id") Long id) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
