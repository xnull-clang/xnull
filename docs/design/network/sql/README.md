# `xdk.sql` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.sql` |
| 层 | L5 网络/数据（数据访问接口） |
| 依赖 | `xdk.core`（`Context`、`Error`、`ErrorKind`、`Result`、`Bytes`、`Map`、`isNaN`） |
| 被依赖 | 生态 SQL 驱动、应用服务；不进入 `xdk.net` 依赖链 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

> 层索引由集成者统一更新；本目录只定义 `xdk.sql`。 其余包见 [`../README.md`](../README.md)。

---

## 1. 包定位

`xdk.sql` 定义通用 SQL 接口，不定义具体数据库驱动：

- 方言与值模型：`SqlDialect`、`SqlKind`、`SqlValue`；
- 结果模型：`SqlColumn`、`SqlRow`、`SqlResult`；
- 语句与参数：`SqlParameter`、`SqlStatement`；
- 执行控制：`SqlOptions`；
- 会话与事务：`SqlConnection`、`SqlTransaction`；
- 驱动注入：`SqlDriver`。

类型关系：

- `SqlDriver.open` 创建 `SqlConnection`；
- `SqlConnection.execute` 接收 `SqlStatement`，返回 `SqlResult`；
- `SqlConnection.begin` 创建 `SqlTransaction`；
- `SqlStatement` 由 `SqlParameter` 组成，参数持有 `SqlValue`；
- `SqlOptions` 由 `execute` 的三参重载消费；
- `SqlResult` 由 `SqlColumn` 与 `SqlRow` 组成。

`xdk.sql` 不是驱动，不是 ORM，不是 SQL 构建器/解析器：

- 驱动由生态实现，`SqlDriver` 是唯一注入协议；核心不内置驱动类型；
- 连接池、负载均衡、健康检查由调用方或生态构建；
- SQL 文本由调用方提供，`xdk.sql` 不解析、不改写、不拼接；
- 不暴露裸驱动句柄、文件描述符、socket、指针；
- 不提供全局注册表、全局连接池、全局缓存。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 接口而非驱动 | 公共 API 只描述连接/事务/驱动协议，具体协议由生态实现 |
| 驱动显式注入 | 调用方持有 `SqlDriver`，核心不做服务发现 |
| NULL 显式 | SQL NULL 用 `SqlValue.nullValue()`，不用 null 引用表示 |
| 参数化 | `SqlStatement` 只携带 SQL 文本与参数，禁止把值拼进 SQL |
| 值不可变 | `SqlValue`、`SqlColumn`、`SqlRow`、`SqlParameter`、`SqlStatement`、`SqlResult` 不可变 |
| 快照结果 | `execute` 返回完整 `SqlResult` 快照，不返回活游标 |
| 事务显式 | 自动提交只发生在连接直接 `execute`；显式事务用 `SqlTransaction` |
| 会话独占 | 一个连接同一时刻只服务于一个任务；事务打开期间连接不直接执行 |
| 资源幂等 | `close` 幂等；关闭后 I/O 返回 `InvalidArgument` 状态错误 |
| 方言只做元数据 | `SqlDialect` 不驱动 SQL 生成、引用或占位符改写 |
| 错误统一 | 只使用 core `ErrorKind`；数据库语句错误归 `InvalidArgument` |
| 无全局状态 | 无全局注册表、无全局池、无全局语句缓存 |
| 无裸句柄 | 实现内部可用不透明 `Long` 句柄；协议不暴露 |
| 可移植子集 | 值类型限定为 `SqlKind` 的 7 项；驱动负责数据库类型映射 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `SqlDialect` | enum | Postgres/MySql/Sqlite/Mssql/Oracle/Generic | [`SqlDialect.md`](SqlDialect.md) |
| `SqlKind` | enum | Null/Bool/Int/Long/Double/String/Bytes | [`SqlKind.md`](SqlKind.md) |
| `SqlValue` | class | 非泛型值 + 类型检查读取 | [`SqlValue.md`](SqlValue.md) |
| `SqlColumn` | class | 列名/类型名/可空性 | [`SqlColumn.md`](SqlColumn.md) |
| `SqlRow` | class | 不可变值行 | [`SqlRow.md`](SqlRow.md) |
| `SqlParameter` | class | 索引/命名参数 + 值 | [`SqlParameter.md`](SqlParameter.md) |
| `SqlStatement` | class | SQL 文本 + 参数、绑定/清空 | [`SqlStatement.md`](SqlStatement.md) |
| `SqlOptions` | class | 超时/最大行数/取数提示 | [`SqlOptions.md`](SqlOptions.md) |
| `SqlResult` | class | 列/行/影响行数/查询标志 | [`SqlResult.md`](SqlResult.md) |
| `SqlConnection` | protocol | 方言、自动提交执行、事务开始、关闭 | [`SqlConnection.md`](SqlConnection.md) |
| `SqlTransaction` | protocol | 事务内执行、提交、回滚、关闭 | [`SqlTransaction.md`](SqlTransaction.md) |
| `SqlDriver` | protocol | 名称、打开连接 | [`SqlDriver.md`](SqlDriver.md) |

> 类型索引 12 项 = 12 个类型文件。协议、枚举均独立成文件；包 README 不含类伪代码。两个枚举各带一个稳定名函数 `sqlDialectName`/`sqlKindName`，定义在对应文件。

明确不做/不承诺：内置驱动、连接池、ORM、SQL 解析/构建、方言 SQL 生成、流式游标、批量/多结果集、保存点/嵌套事务、时间/Decimal/UUID/JSON 专用 kind、全局注册表、裸句柄。

---

## 4. 跨类型规则

| 规则 | 说明 |
| --- | --- |
| 参数索引从 1 开始 | `SqlParameter.indexed` 的 `parameterIndex` 合法域为 `1..n`；0 只用于命名参数哨兵 |
| 命名参数不带前缀 | `name` 是逻辑名，例如 `userId`；不写 `:userId`、`@userId`、`$1` |
| 参数风格单一 | 一条 `SqlStatement` 只能全索引或全命名；混用是合同错误 |
| 语句不可变 | `bind`/`withParameter`/`clear` 返回新语句；原语句可安全复用 |
| 结果行非 null | `SqlRow` 的每个元素都是 `SqlValue`；SQL NULL 是 `SqlValue.nullValue()` |
| 结果快照 | `SqlResult` 在 `execute` 返回时已完整；`columns`/`rows` 返回列表副本 |
| 查询标志 | `isQuery=true` 表示有结果集；`isQuery=false` 时列与行必须为空 |
| 影响行数 | `rowsAffected` 为 `Long`；查询语句通常为 0，0 也可能表示“未知” |
| 选项按次快照 | 三参 `execute` 在调用开始时复制 `SqlOptions` 值；之后修改 options 不影响本次执行 |
| 零值语义 | `timeoutMillis=0` 无超时；`maxRows=0` 不限制；`fetchSize=0` 用驱动默认 |
| 连接/事务独占 | 连接不跨任务共享；事务打开期间连接不直接执行；一个连接最多一个活动事务 |
| 关闭幂等 | `close` 可重复调用；关闭后 I/O 返回 `InvalidArgument`，不再返回 `Unavailable` |
| 驱动注入 | `SqlDriver` 由调用方提供；核心不提供注册表、工厂、自动发现 |
| 统一执行入口 | `SqlConnection`/`SqlTransaction` 只接收 `SqlStatement`；不提供 raw SQL/方言注入旁路 |
| 错误分类 | 语法/约束/参数不匹配归 `InvalidArgument`；权限归 `PermissionDenied`；缺能力归 `Unsupported` |
| 错误脱敏 | 错误消息不得包含参数值、口令、完整连接串；可含 SQL 状态/位置/列名 |
| 无 SQL 拼接 | 调用方不得把值拼进 SQL；`SqlStatement` 不解析占位符数量，驱动在 `execute` 校验 |

---

## 5. 场景

### S1：索引参数查询

`SqlDriver.open` → `SqlConnection.execute` → `new SqlStatement("select user_key from users where user_key = ?").bind(SqlValue.ofLong(42))` → `SqlResult.columns()`/`rows()`。

### S2：命名参数查询

`new SqlStatement("select user_key from users where name = :name").withParameter(SqlParameter.named("name", SqlValue.ofString("Ada")))` → `execute`；驱动把逻辑名映射到自己的占位符语法。

### S3：显式事务提交

`connection.begin(context)` → `transaction.execute(context, statement)` → `transaction.commit(context)`；提交成功后事务 `isOpen=false`，连接可继续自动提交执行。

### S4：事务回滚/关闭

`transaction.rollback(context)` 或 `transaction.close()`；`close` 对未结束事务先尽力 rollback。连接在事务干净结束后恢复可用；失败时以 `connection.isOpen()` 为准。

### S5：超时与行数上限

`connection.execute(context, statement, options)`；`options.timeoutMillis(2000).maxRows(1000).fetchSize(100)`。`maxRows` 是硬上限，`fetchSize` 是驱动提示。

### S6：驱动接入

生态实现 `SqlDriver`、`SqlConnection`、`SqlTransaction`；内部持有不透明句柄，外部只返回协议值；错误映射到 core `ErrorKind`；不暴露驱动类型。

### S7：错误后的状态判断

语句错误 `InvalidArgument`：连接通常仍可用。`Network`/`Io`：连接可能已关闭，以 `isOpen` 为准；事务提交发送后出错：事务结束，连接是否可复用由驱动判断。

---

## 6. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 具体驱动 | 生态实现；`xdk.sql` 不内置 Postgres/MySQL/SQLite/MSSQL/Oracle 驱动类型 |
| 连接池 | 不提供；调用方或生态在 `SqlDriver`/`SqlConnection` 上构建，并负责独占借出 |
| ORM | 不做；实体映射、关系加载、变更跟踪不属于本包 |
| SQL 解析/构建 | 不做；`SqlStatement` 只带文本与参数，不校验占位符数量 |
| 方言 SQL 生成 | 不做；不提供按方言拼接、引用标识符、改写占位符的入口 |
| 流式结果/游标 | v1 不提供；`SqlResult` 是快照，大结果用 `maxRows` 或生态游标 |
| 事务隔离级别/只读 | 不进入协议；由驱动 open options 或后续扩展决定 |
| 保存点/嵌套事务 | 不做；一个连接最多一个活动事务 |
| 批量/多结果集 | 不做；一次 `execute` 一个语句、一个结果 |
| 存储过程/输出参数 | 不做；驱动可用自己的扩展，不进入 `xdk.sql` 协议 |
| 时间/Decimal/UUID/JSON | 无专用 kind；驱动映射到 String/Bytes 并文档化，核心不做隐式转换 |
| 连接健康检查/重连 | 不做；无 `ping`、无自动重连；调用方关闭并重新 `open` |
| 全局注册表/服务发现 | 不做；`SqlDriver` 显式注入 |
| 裸句柄/文件描述符 | 不暴露；实现内部可用不透明 `Long` 句柄 |
| 错误细分 | 只用 core `ErrorKind`；约束/语法错误归 `InvalidArgument`，不新增数据库错误码类型 |
| `rowsAffected` 未知 | 用 0 表示；0 也可能表示确实为 0，精确值需驱动扩展或单独查询 |
| `maxRows` 截断标志 | 不提供；结果最多 `maxRows` 行，调用方需自行判断是否还有数据 |
| 凭证管理 | 驱动 open options 负责；核心不存储、不记录、不回显口令 |
| `SqlOptions` 传递 | 通过三参 `execute` 重载；两参形式等价于全零默认 options |
| 驱动生命周期 | 协议无 `close`；驱动应保持轻量，进程级资源由生态实现自行管理 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Sql`、`@Param`、`@Row`、`@Column` |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | SqlAnnotationProcessor（Resolve/Validate/Generate） |
| 生成物 | DAO 方法、行 mapper、参数绑定、列映射 |
| 状态 | 领域注解 planned；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| DAO 方法 | `@Sql` | SQL 文本/返回映射 |
| DAO 参数 | `@Param` | 命名参数绑定 |
| 行类型 | `@Row` | 行 mapper |
| 行字段 | `@Column` | 列映射 |
| `SqlColumn` | `@Value` | 列元数据值语义 |
| `SqlValue`/`SqlRow`/`SqlStatement`/`SqlResult` | — | 含 tagged value/List 字段；按字段可值比较性再决定，不强行全量 `@Value` |

### 声明

```x
@Target(Method)
@Retention(Source)
@annotation Sql {
    final String value
}

@Target(Parameter)
@Retention(Source)
@annotation Param {
    final String value
}

@Target(Type)
@Retention(Source)
@annotation Row {
}

@Target(Field)
@Retention(Source)
@annotation Column {
    final String value
}
```

### 使用

```x
@Row
class UserRow {
    @Column("user_id") final Long id
    @Column("display_name") final String name
}

class UserDao {
    @Sql("SELECT user_id, display_name FROM users WHERE user_id = :id")
    Result<UserRow, Error> find(@Param("id") Long id) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
