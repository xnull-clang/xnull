# `IsolationLevel`

| 项 | 值 |
| --- | --- |
| 类型 | `enum IsolationLevel` |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | 无 |
| 被依赖 | [`DatabaseConfig`](DatabaseConfig.md)、[`DatabasePool`](DatabasePool.md) |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

连接池级事务隔离级别标识：`ReadUncommitted`、`ReadCommitted`、`RepeatableRead`、`Serializable`。

用于 `DatabaseConfig` 声明“这个池打开的连接应使用哪个隔离级别”，由驱动在打开连接时落实；不是每次事务的覆盖参数。

不做：方言 SQL 生成、隔离级别能力探测、每事务切换、只读事务、快照隔离、线性化隔离、数据库默认级别枚举项。

---

## 2. 设计逻辑

- 隔离级别是封闭集合，用 enum 而不是字符串；驱动不能私造值。
- 只覆盖 JDBC/ADO.NET/`database/sql`/SQLAlchemy 共同承认的四级；`Snapshot`、`Linearizable`、`WriteCommitted` 等生态扩展不进入基线。
- **没有 `Default` 成员**：`DatabaseConfig.isolationLevel` 为 `null` 表示不指定，使用驱动/数据库默认值。这样“未设置”和“显式要求 ReadCommitted”不会混淆。
- 隔离级别是池级属性：所有从同一池借出的连接使用同一级别；v1 不支持单个事务覆盖。需要不同级别时创建独立 `Database`/`DatabasePool`。
- 驱动落实方式由 `xdk.sql` open options 承载：`DatabasePool` 在打开连接时加入保留键 `xdk.isolationLevel`，值为 `isolationLevelName`。参与 `xdk.db` 的驱动必须：
  - 支持该级别时，对每个新连接设置并验证；
  - 不支持时返回 `Unsupported`；
  - 不得静默忽略，也不得降级到其他级别。
- 驱动返回 `InvalidArgument`（不识别保留键）表示驱动未参与该约定；调用方应升级驱动或去掉隔离级别配置。`DatabasePool.open` 原样返回该错误，不猜测修复。
- 名称稳定、小写、ASCII，供配置/日志使用；不提供数值码，避免持久化枚举序号。
- 值语义；无 close；可共享；可作 `Map` 键。

---

实现状态：implemented。内部增加 `Unknown` 0 号占位以规避 optional 枚举 0/null 歧义；`isolationLevelFromName` 未知名称仍返回 null。

## 3. 表示与不变量

| 成员 | 名称 | 语义 | 备注 |
| --- | --- | --- | --- |
| `ReadUncommitted` | `read_uncommitted` | 可读未提交数据（脏读） | 部分数据库不支持或映射为更高级别 |
| `ReadCommitted` | `read_committed` | 只读已提交数据 | 多数数据库默认 |
| `RepeatableRead` | `repeatable_read` | 同一事务内重复读一致 | 快照/锁实现由数据库决定 |
| `Serializable` | `serializable` | 可串行化 | 可能伴随重试/锁等待 |

不变量：

- 成员固定；只允许在后续大版本追加；
- 名称唯一、稳定、小写 ASCII；
- 不存在 `Default`/`Unknown` 成员；
- 枚举值不映射为 Int 序号；
- 值语义，可安全跨任务共享。

---

## 4. 生命周期

值类型；无构造器、无 close、无资源；编译期常量；可长期缓存/共享。

---

## 5. 构造契约

枚举成员直接使用，不提供文本 `parse` 构造。

配置层需要从文本恢复时使用 [`isolationLevelFromName`](#7-方法总表--详表)；未知名称返回 `null`，由配置层决定报错还是使用默认值。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

无实例方法。相关顶层函数：

| 函数 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `isolationLevelName` | 稳定小写名 | `IsolationLevel level` | `String` | `level == null` → panic | 供配置/日志/保留 open option 使用 |
| `isolationLevelFromName` | 名称解析 | `String name` | `IsolationLevel?` | null/未知 → null | 大小写不敏感；不 panic |

详细契约：

- `isolationLevelName(ReadUncommitted)` 返回 `"read_uncommitted"`；其余依次为 `"read_committed"`、`"repeatable_read"`、`"serializable"`。
- `isolationLevelFromName` 先 `trim` 再转小写；`"READ COMMITTED"`、`"read_committed"` 都可解析；空串、null、未知名称返回 null。
- 不提供 `isolationLevelCode`/`fromCode`：禁止持久化序号。
- 不提供 `toSql`/`quote`：隔离级别 SQL 由驱动按方言生成；`xdk.db` 不拼接方言 SQL。
- 不提供 `isSupported`：支持性只能在驱动打开连接时判断；`DatabasePool.open` 的 `Unsupported` 是唯一权威结果。

---

## 8. 使用的技术

- 简单封闭枚举；
- 稳定名称表；
- 大小写不敏感解析；
- 值语义；
- 保留 open option 传递（不生成方言 SQL）。

---

## 9. 需要的支撑

- 语言：enum、String、Bool、nullable 类型；
- 运行时：`trim(String)`、`toLowerAscii(String)`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。被 [`DatabaseConfig`](DatabaseConfig.md) 持有，由 [`DatabasePool`](DatabasePool.md) 转换为保留 open option；驱动返回 `Unsupported` 时由 [`Db.open`](Db.md) 透传。

---

## 11. 所有权与并发

- 值语义；可跨任务共享；无资源；无取消点。
- 相等按成员身份；可作 `Map`/`Set` 键。
- 不提供排序；需要展示顺序时按枚举声明顺序或业务决定。
- 不持有数据库能力信息；同一枚举值在不同驱动上可能有不同实现语义，以驱动文档为准。

---

## 12. 示例与反例

正确：

```text
DatabaseConfig config = DatabaseConfig.of("orders", "postgres://db/app")
    .withIsolationLevel(IsolationLevel.ReadCommitted)
```

```text
String name = isolationLevelName(IsolationLevel.Serializable)
IsolationLevel? parsed = isolationLevelFromName("repeatable_read")
```

反例：

- 用 `IsolationLevel.ReadCommitted` 期望在 SQLite 上获得锁语义；SQLite 可能拒绝或映射。
- 在事务开始后调用一个不存在的 `setIsolation`；v1 没有每事务覆盖。
- 把枚举序号写入配置文件；后续追加成员会改变含义。
- 驱动不支持 `Serializable` 时静默使用 `ReadCommitted`；必须返回 `Unsupported`。
- 把 `null` 当作 `ReadCommitted`；null 只表示驱动默认。
- 用字符串比较代替枚举比较。

---

## 13. 测试/场景义务

- 四个成员完整性；名称稳定性；`isolationLevelName` 对 null panic；
- `isolationLevelFromName` 大小写/空白/未知/null；
- 无 `Default` 成员；无 Int 转换；
- 配置带隔离级别打开池，驱动收到保留键与正确名称；
- 驱动不支持时 `DatabasePool.open` 返回 `Unsupported`，且没有半打开连接泄漏；
- 驱动不识别保留键时返回 `InvalidArgument`，错误文本不回显连接串；
- 同池所有连接使用同一级别；需要不同级别时两个池互不影响；
- 枚举作 `Map` 键；
- 日志只出现稳定名称，不出现连接串。

---

## 14. XNull 伪代码

```xnull
enum IsolationLevel {
    ReadUncommitted,
    ReadCommitted,
    RepeatableRead,
    Serializable,
}

String isolationLevelName(IsolationLevel level) {
    if level == null {
        throw "isolationLevelName: null level"
    }
    if level == IsolationLevel.ReadUncommitted { return "read_uncommitted" }
    if level == IsolationLevel.ReadCommitted { return "read_committed" }
    if level == IsolationLevel.RepeatableRead { return "repeatable_read" }
    return "serializable"
}

IsolationLevel? isolationLevelFromName(String name) {
    if name == null {
        return null
    }
    String normalized = toLowerAscii(trim(name))
    if normalized == "read_uncommitted" { return IsolationLevel.ReadUncommitted }
    if normalized == "read_committed" { return IsolationLevel.ReadCommitted }
    if normalized == "repeatable_read" { return IsolationLevel.RepeatableRead }
    if normalized == "serializable" { return IsolationLevel.Serializable }
    return null
}
```

> 伪代码非可执行。`isolationLevelName` 的名称同时作为保留 open option 的取值；驱动不得改变大小写或分隔符。
