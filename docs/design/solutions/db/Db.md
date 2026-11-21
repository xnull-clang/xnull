# `Db`

| 项 | 值 |
| --- | --- |
| 类型 | `class Db`（静态入口） |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SqlDriver`、`DatabaseConfig`、`Database`、`DatabasePool`、`Error` |
| 被依赖 | 应用启动、CLI、管理工具、测试 |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

`xdk.db` 的静态入口：显式打开 `Database` 或独立 `DatabasePool`，并暴露隔离级别保留 open option 键。

不做：全局池、驱动注册/发现、连接缓存、`closeAll`、配置解析、迁移列表注册、健康注册、服务定位。

---

## 2. 设计逻辑

- 为什么是 class：提供稳定的包级命名空间；不是 protocol，因为没有多实现；不是单例，因为无实例状态。
- 静态无状态：不缓存 `SqlDriver`/`Database`/`DatabasePool`，不保存 `Context`，不按 URI 复用池。
- `open(context, driver, config)`：
  - 创建独立 `DatabasePool`；
  - 把池所有权转给新 `Database`；
  - 返回 `Database`，由调用方关闭（关闭会关闭池）。
- `openPool(context, driver, config)`：
  - 只创建独立 `DatabasePool`；
  - 调用方拥有并必须 `close`；
  - 适合需要直接控制 `acquire`/`begin`/`warmUp` 的应用。
- 两个入口都直接委托 [`DatabasePool.open`](DatabasePool.md)，不复制校验/连接逻辑；`failFast`/隔离级别/超时语义完全由池定义。
- `isolationOpenOptionKey()` 返回保留键 `"xdk.isolationLevel"`，与 [`DatabaseConfig`](DatabaseConfig.md) 的内部校验、[`DatabasePool`](DatabasePool.md) 的 open options 注入必须一致。生态驱动用该函数识别键，不硬编码字符串。
- 无全局状态；静态方法可并发调用；每次调用返回独立实例。相同配置多次 `open` 得到互不影响的池/句柄。
- 失败不返回半初始化对象；`open` 失败时池已关闭/未创建，不泄漏连接。
- 不提供 `openAll`/`default`/`fromUri`：驱动与配置必须显式注入。
- 不提供 `closeAll`：入口不追踪已打开实例；每个 `Database`/`DatabasePool` 由调用方关闭。
- 错误脱敏：入口不拼接 URI/选项；驱动/池错误原样返回，错误文本由下层保证不含口令/完整连接串。

---

## 3. 表示与不变量

无实例字段。`Db` 是静态入口，不持有驱动、池、数据库、配置、迁移或健康状态。

不变量：

- 不可实例化；所有方法静态；无全局可变状态。
- `open`/`openPool` 不缓存、不按 URI 匹配、不自动复用。
- 成功返回的 `Database` 拥有其池；成功返回的 `DatabasePool` 由调用方拥有。
- `open` 失败不返回半初始化 `Database`；已创建的池/连接被关闭。
- `openPool` 失败不返回半初始化池；已建立连接被关闭。
- `isolationOpenOptionKey()` 返回稳定、非空、小写 ASCII 字符串；不随驱动/配置变化。
- 不保存 `Context`；不跨调用保留任何状态。
- 不提供 `close`/`closeAll`；实例生命周期由调用方管理。

---

## 4. 生命周期

静态类；无实例；无 close；无全局资源；无 `deinit` 依赖。

- `open` 返回的 `Database` 生命周期由调用方管理；`Database.close` 关闭其池。
- `openPool` 返回的池生命周期由调用方管理；`DatabasePool.close` 关闭物理连接。
- `Db` 不延长任何实例生命周期，也不感知实例关闭。
- 静态入口本身可长期存在；不随数据库/池关闭而失效。
- 没有后台线程/定时器；不自动重连/重试。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Db()` | 无 | 私有；禁止实例化 | 无 |

静态入口不提供工厂构造；所有能力通过静态方法获取。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open`（静态） | 打开 Database | `Context context, SqlDriver driver, DatabaseConfig config` | `Result<Database, Error>` | 同 `DatabasePool.open` |
| `openPool`（静态） | 打开独立池 | `Context context, SqlDriver driver, DatabaseConfig config` | `Result<DatabasePool, Error>` | 同 `DatabasePool.open` |
| `isolationOpenOptionKey`（静态） | 隔离级别保留键 | 无 | `String` | 无 |

说明：

- `open`：
  - `context == null`/`driver == null`/`config == null` → panic。
  - 直接调用 `DatabasePool.open`；驱动/配置/网络/认证/隔离级别错误原样返回。
  - 成功构造 `Database` 并转移池所有权；调用方必须 `Database.close()`。
  - `failFast=true` 时打开即建立并验证初始连接；false 时惰性。
  - 失败不返回半初始化对象；池已关闭。
  - 不使用全局池；相同配置多次调用互相独立。
- `openPool`：
  - 参数校验与 `open` 相同。
  - 直接返回池；调用方必须 `DatabasePool.close()`。
  - 不自动包装 `Database`；需要执行/映射/事务时调用池的 `acquire`/`begin`，或自行构造 `Database`（构造器主要供宿主/测试使用）。
  - 失败语义同 `DatabasePool.open`。
- `isolationOpenOptionKey`：
  - 返回 `"xdk.isolationLevel"`；无参数、无失败。
  - 驱动应使用该函数识别保留键；`DatabaseConfig` 拒绝调用方手动设置同名 open option。
  - 值由 `isolationLevelName` 提供（`read_uncommitted`/`read_committed`/`repeatable_read`/`serializable`）。
  - 键名稳定；不得按驱动/方言变化。
- 不提供 `openDefault`/`openFromConfig`/`fromEnvironment`；配置来源由应用决定。
- 不提供 `closeAll`：入口不追踪实例。
- 不提供 `migrate` 便捷方法：迁移需要显式历史表与迁移列表，使用 `MigrationRunner`。
- 不提供 `health` 便捷方法：健康需要名称与刷新策略，使用 `DatabaseHealth`。
- 所有方法 O(1) 委托/常量返回；`open`/`openPool` 可阻塞，取消/超时透传。

---

## 8. 使用的技术

- 静态入口；
- 纯委托；
- 显式所有权转移；
- 无常驻状态；
- 保留 open option 键常量；
- `Context`/`Result`；
- 无全局池/注册表。

---

## 9. 需要的支撑

- 语言：class、static、私有构造器、String、Result；
- 运行时/驱动：无额外原语；
- 接口：`Context`、`SqlDriver`、`DatabaseConfig`、`Database`、`DatabasePool`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

[`Context`](../../core/execution/Context.md)、[`SqlDriver`](../../network/sql/SqlDriver.md)、[`DatabaseConfig`](DatabaseConfig.md)、[`Database`](Database.md)、[`DatabasePool`](DatabasePool.md)、[`IsolationLevel`](IsolationLevel.md)、[`Error`](../../core/errors/Error.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

- 静态方法可并发调用；无共享可变状态；每次返回独立实例。
- `open` 成功后池所有权转移给 `Database`；`Db` 不再持有。
- `openPool` 成功后池所有权转移给调用方；`Db` 不持有。
- `driver`/`config` 借用；池只读取/复制所需值，不修改；`config` 不可变。
- `Context` 借用；入口不保存。
- 相等：静态类无实例；不提供 `equals`。
- 无 close；无资源所有权保留。
- 不要在 `open` 返回后继续使用已传给它的可变配置期望影响池；池已复制。

---

## 12. 示例与反例

正确：

```text
Result<Database, Error> opened = Db.open(context, driver, config)
if opened.isOk() {
    Database database = opened.value()
    Result<SqlResult, Error> result = database.execute(context, statement)
    database.close()
}
```

```text
Result<DatabasePool, Error> poolResult =
    Db.openPool(context, driver, config)
if poolResult.isOk() {
    DatabasePool pool = poolResult.value()
    Result<SqlConnection, Error> lease = pool.acquire(context)
    pool.close()
}
```

```text
String isolationKey = Db.isolationOpenOptionKey()
if optionKey == isolationKey {
    diagnose("driver received xdk isolation option")
}
```

反例：

- 期望 `Db.open` 复用同名/同 URI 的池；每次调用独立。
- 打开后不关闭 `Database`/`DatabasePool`；连接泄漏。
- 通过 `Db` 获取全局单例；没有这种入口。
- 关闭 `Db.open` 返回的 `Database` 后再使用其池；`Database.close` 已关闭池。
- 把 `isolationOpenOptionKey()` 的返回值改写/按驱动替换；驱动应使用稳定键。
- 直接设置同名 open option 又设置 `isolationLevel`；`DatabaseConfig` 会拒绝。
- 用空配置/空驱动打开；null 是合同错误。
- 期望 `open` 自动执行迁移/健康检查；职责分离。
- 把 `open` 的 `Err` 当“稍后会自动重连”；没有自动重连。
- 把 URI/口令放进 `describe`；`Db` 不提供 `describe`，池/配置也不输出秘密。

---

## 13. 测试/场景义务

- `open` 成功返回独立 `Database`；`openPool` 成功返回独立池；两者互不影响；
- `open`/`openPool` 失败无泄漏；`failFast` true/false；
- 相同配置多次打开得到不同实例；无全局池；
- 隔离级别保留键常量稳定性；与 `DatabaseConfig`/`DatabasePool` 一致；
- 驱动 `Unsupported`/`InvalidArgument` 透传；
- `Context` 取消/超时透传；
- null 参数 panic；
- `Db` 不可实例化；无静态状态；
- 关闭 Database/Pool 后不自动重开；
- 错误文本不含 URI/口令；
- 并发 `open`/`openPool`；
- 驱动对象被丢弃后已打开实例仍可用（由驱动/池契约保证）；
- 无 `closeAll`/全局注册表。

---

## 14. XNull 伪代码

```xnull
class Db {
    private Db() {
    }

    static Result<Database, Error> open(Context context, SqlDriver driver,
            DatabaseConfig config) {
        if context == null || driver == null || config == null {
            throw "Db.open: null argument"
        }
        Result<DatabasePool, Error> opened =
            DatabasePool.open(context, driver, config)
        if opened.isErr() {
            return Err(opened.error())
        }
        DatabasePool pool = opened.value()
        Database database = new Database(pool)
        return Ok(database)
    }

    static Result<DatabasePool, Error> openPool(Context context,
            SqlDriver driver, DatabaseConfig config) {
        if context == null || driver == null || config == null {
            throw "Db.openPool: null argument"
        }
        return DatabasePool.open(context, driver, config)
    }

    static String isolationOpenOptionKey() {
        return "xdk.isolationLevel"
    }
}
```

> 伪代码非可执行。`Database(DatabasePool)` 构造器主要供 `Db.open`/宿主/测试使用，并接管池所有权；`Db` 本身不保存任何实例。
