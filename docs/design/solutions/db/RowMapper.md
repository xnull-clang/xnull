# `RowMapper`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol RowMapper` |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SqlColumn`、`SqlRow`、`Error` |
| 被依赖 | [`Database`](Database.md) |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

逐行映射协议：查询开始时接收列元数据，随后按结果顺序把每个 `SqlRow` 映射到应用值。

`RowMapper` 是**非泛型回调**：协议不返回 `List<T>`，而是由实现把应用值积累在自己的字段/集合中，并由实现暴露类型化的读取方法。这样在 XNull 不允许泛型协议的前提下，应用仍能得到强类型结果。

不做：实体/关系映射、反射、自动列名到字段绑定、变更跟踪、懒加载、结果集更新、流式游标、批量映射、跨查询复用、关闭资源。

---

## 2. 设计逻辑

- `xdk.sql` 的结果是 `SqlResult` 快照，`SqlRow` 是不可变值行；`RowMapper` 只消费快照，不持有连接/事务/游标。
- 两阶段协议：
  1. `start(context, columns)`：查询开始、尚未读取行时调用一次；实现可校验必需列、建立列名到索引的映射、清空/初始化应用集合。
  2. `mapRow(context, row)`：每行调用一次，顺序与 `SqlResult.rows()` 一致；实现读取 `SqlValue` 并构造应用值。
- `start` 即使结果为零行也会被调用，因此“缺列”在空结果时也能被发现；这对迁移/配置错误很重要。
- 协议不提供 `finish`：`Database.query` 返回即表示映射结束；实现不需要提交/关闭。若实现持有外部资源，应在自己的生命周期内关闭，而不是依赖协议。
- 非泛型：应用值类型由实现决定；调用方在调用 `Database.query` 前持有 mapper，之后通过 mapper 的具体方法读取结果。`Database.query` 返回映射行数 `Int`，不返回泛型列表。
- 失败即停止：`start` 返回 `Err` 时不会调用 `mapRow`；`mapRow` 返回 `Err` 时后续行不再映射，`Database.query` 原样返回该错误。已映射的部分保留在 mapper 中，调用方需按失败处理。
- `Context` 首参：`Database` 在行间检查取消；mapper 也可检查 `context.isCancelled()` 并返回 `Cancelled`。
- 错误分类由实现决定：缺少必需列通常 `InvalidArgument`；值解码失败可 `InvalidArgument`/`DataCorrupted`/`Unsupported`；取消 `Cancelled`；超时 `Timeout`。错误文本只含列名/索引/kind，不含行值。
- 不做隐式类型转换：`SqlValue.asInt`/`asLong`/`asString` 等已做 kind 检查；mapper 需要跨类型转换时显式决定。
- 无 close；实现可有自己的 `close`，但不进入协议；`Database` 不调用它。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `start` 在 `mapRow` 之前调用，且每次查询最多调用一次。
- `start` 收到的 `columns` 非 null、非空；元素 `SqlColumn` 非 null；列表是快照，元素不可变。
- `mapRow` 收到的 `row` 非 null；行长度等于列数；`SqlValue` 元素非 null。
- `mapRow` 只在该查询的单任务内顺序调用，不并发。
- 实现不修改 `columns`/`row`；不把 `SqlRow` 当作可变缓冲。
- 实现返回的 `Error` 单行、脱敏；不包含行值、参数值、完整连接串。
- 实现若保留 `SqlRow`/`SqlColumn`，可安全长期持有（不可变）；但保留大结果会增加内存。
- 实现若在 `start` 中建立状态，`mapRow` 必须能看到同一状态；不得假设跨查询复用。

---

## 4. 生命周期

由应用构造；一次 `Database.query`/`queryOne` 调用期间使用；查询返回后由应用读取结果。协议无 close。

- 同一个 mapper 不应并发用于两个查询；需要并发时每个查询一个 mapper。
- 可以在一次查询失败后读取已映射的部分结果；实现应文档化失败时的状态。
- 查询结束后可复用同一个 mapper 再次查询，前提是实现 `start` 会重置状态；协议不强制重置，实现必须明确。
- mapper 的资源（文件、缓冲区）由实现管理；`Database` 不负责关闭。

---

## 5. 构造契约

协议无构造。实现类定义自己的构造器与依赖注入；不得要求 `Database` 反射构造 mapper。

- 必需列、目标集合、值转换器由实现构造器注入。
- 构造器参数非法由实现决定 panic 或返回失败；协议不规定。
- 不得通过全局注册表查找 mapper；调用方显式传入。

---

## 6. 字段表

无协议字段。实现内部状态（列索引、应用值集合、错误计数）不进入公共契约。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `start` | 初始化/校验列 | `Context context, List<SqlColumn> columns` | `Result<Unit, Error>` | `InvalidArgument`/`Unsupported`/`Cancelled`/`Timeout` | 每次查询一次；零行也调用 |
| `mapRow` | 映射一行 | `Context context, SqlRow row` | `Result<Unit, Error>` | 实现定义；`Cancelled`/`Timeout` 应透传 | 按结果顺序；失败停止 |

详细契约：

- 两个方法都要求非 null 参数；null 是合同错误（panic），不是 `Err`。
- `start` 的 `columns` 是 `SqlResult.columns()` 的副本；实现可建立 `Map<String,Int>` 列索引。列名允许重复；按名查找时必须定义重名策略（通常拒绝或取第一个），并在实现文档中说明。
- `start` 返回 `Err` 后，`Database` 不再调用 `mapRow`；查询连接仍会被归还/丢弃。
- `mapRow` 的 `row.length()` 等于 `columns.length()`；实现可用 `row.get(index)` 或 `row.tryGet(index)`。`tryGet` 返回 null 只表示索引不存在，不表示 SQL NULL；SQL NULL 用 `value.isNull()`。
- `mapRow` 返回 `Err` 后，`Database` 停止映射并返回该错误；不自动回滚（查询通常无写入）；若在事务中由调用方决定回滚。
- 实现应在每行开始或结束时检查 `context.isCancelled()`；不强制，但取消响应越早越好。
- 错误文本：可含列名、列索引、期望/实际 `SqlKind`；不得含 `SqlValue` 载荷、整行内容、SQL 文本或参数值。
- 不提供 `mapRows(List<SqlRow>)`：批量映射会隐藏逐行失败位置，且增加中间列表；逐行回调更可控。
- 不提供 `finish`/`close`：查询结束由 `Database.query` 返回表达；资源由实现自己管理。
- 不提供 `columns()` 读取：`start` 已提供；实现可自行保存副本。
- 不提供泛型返回：应用值由实现字段/方法暴露；这是非泛型协议的明确取舍。

---

## 8. 使用的技术

- 非泛型协议；
- 两阶段回调（列初始化 + 逐行映射）；
- 不可变行/列快照；
- 应用侧状态累积；
- 类型检查读取（`SqlValue.as*`）；
- 失败即停止；
- 脱敏错误。

---

## 9. 需要的支撑

- 语言：protocol、Result、Unit、List、Int、String、Bool；
- 运行时：无（实现可使用 `Map`/`List`）；
- 接口：`Context`、`SqlColumn`、`SqlRow`、`SqlValue`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

[`Context`](../../core/execution/Context.md)、[`SqlColumn`](../../network/sql/SqlColumn.md)、[`SqlRow`](../../network/sql/SqlRow.md)、[`SqlValue`](../../network/sql/SqlValue.md)、[`Error`](../../core/errors/Error.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。由 [`Database.query`](Database.md) 调用。

---

## 11. 所有权与并发

- 协议引用身份；实现拥有自己的状态；`Database` 不拥有 mapper。
- 单查询单任务；不得并发调用同一 mapper 的 `start`/`mapRow`。
- `columns` 列表借用；元素不可变；实现可复制后长期持有。
- `row` 借用；`SqlRow` 不可变；实现可保留引用。
- `Context` 借用；mapper 不得取消调用方的 context（只读检查）。
- 相等：协议无 `equals`；实现按引用身份。
- 无资源所有权转移；mapper 的资源由实现关闭。

---

## 12. 示例与反例

正确（应用实现，非协议成员）：

```text
class UserRowMapper implements RowMapper {
    final List<User> _users = []
    Int _nameIndex = -1
    Int _keyIndex = -1

    Result<Unit, Error> start(Context context, List<SqlColumn> columns) {
        _users.clear()
        _nameIndex = -1
        _keyIndex = -1
        Int index = 0
        while index < columns.length() {
            String name = columns.get(index).name()
            if name == "name" { _nameIndex = index }
            if name == "user_key" { _keyIndex = index }
            index = index + 1
        }
        if _nameIndex < 0 || _keyIndex < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "user mapper: missing required column"))
        }
        return Ok(unit)
    }

    Result<Unit, Error> mapRow(Context context, SqlRow row) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
        }
        Result<String, Error> name = row.get(_nameIndex).asString()
        if name.isErr() { return Err(name.error()) }
        Result<Long, Error> key = row.get(_keyIndex).asLong()
        if key.isErr() { return Err(key.error()) }
        _users.push(new User(key.value(), name.value()))
        return Ok(unit)
    }

    List<User> users() { return _users.copy() }
}
```

调用：

```text
UserRowMapper mapper = new UserRowMapper()
Result<Int, Error> mapped = database.query(context, statement, mapper)
if mapped.isOk() {
    List<User> users = mapper.users()
}
```

反例：

- 在 `mapRow` 里调用 `database.query` 查询同一连接池且池上限为 1；可能自锁。需要嵌套查询时用独立 mapper/连接或确保池容量。
- 用反射按字段名自动填充；本包不做 ORM/反射。
- 把 `SqlRow` 当可变缓冲修改；它不可变。
- 用 `tryGet(index) == null` 判断 SQL NULL；应使用 `SqlValue.isNull()`。
- 在错误消息中拼接 `row.get(...).asString()`；可能泄漏敏感数据。
- 在 `start` 中假设 `columns` 非空但结果为空；`start` 仍会被调用且列非空。
- 多个查询并发复用同一 mapper；状态会交错。
- 期望 `mapRow` 失败后 `Database` 自动回滚写入；查询通常只读，事务由调用方管理。
- 把 mapper 当结果对象长期共享而不加同步；查询后只读也要确保实现不再变更。

---

## 13. 测试/场景义务

- `start` 零行/单行/多行均调用；列元数据顺序正确；
- 必需列存在/缺失；重名列策略；
- `mapRow` 顺序、行数、每行类型读取；
- SQL NULL vs 缺失索引；`tryGet` 语义；
- 空结果：`start` 成功、`mapRow` 不调用、返回 0；
- `start` 失败：`mapRow` 不调用；
- `mapRow` 第 N 行失败：后续不调用，错误原样返回，已映射部分保留；
- `Context` 取消：返回 `Cancelled`，不再映射；
- 错误文本不含行值/参数值；
- 同一 mapper 顺序复用两次；`start` 重置；
- 并发查询使用不同 mapper；
- 非泛型协议无 `T`/`Object` 根类型；
- 大行/Unicode/二进制值映射；
- 与 `Database.queryOne` 配合：最多映射一行。

---

## 14. XNull 伪代码

```xnull
protocol RowMapper {
    Result<Unit, Error> start(Context context, List<SqlColumn> columns);
    Result<Unit, Error> mapRow(Context context, SqlRow row);
}
```

> 伪代码非可执行。实现不得修改 `columns`/`row`；`Database` 在调用 `start` 前已确认结果是查询且有非空列集。
