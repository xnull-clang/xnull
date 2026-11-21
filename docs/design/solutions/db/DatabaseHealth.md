# `DatabaseHealth`

| 项 | 值 |
| --- | --- |
| 类型 | `class DatabaseHealth implements HealthCheck` |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | `Database`、`HealthCheck`、`HealthReport`、`HealthState`、`Context`、`Error` |
| 被依赖 | 应用健康端点、指标导出、`HealthRegistry` 适配器 |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

数据库健康适配器：缓存最近一次健康快照，并提供**显式主动刷新** `refresh(context)`；`check()` 只读缓存，满足 core `HealthCheck` 的非阻塞合同。

不做：HTTP 端点、指标注册、定时调度、自动重试、连接池修复、SQL 诊断、慢查询分析、连接级明细、全局健康注册表。

---

## 2. 设计逻辑

- `xdk.runtime.HealthCheck` 要求 `check()` 非阻塞；数据库探测必然可能阻塞，因此拆成两层：
  - `refresh(context)`：借一条池租约，验证池/连接可用，生成新 `HealthReport` 并更新缓存；
  - `check()`：返回最近快照，不碰数据库、不阻塞。
- 应用负责调度 `refresh`（后台任务、定时器、管理端点触发）；本类不创建线程/定时器，也不持有全局状态。
- 主动检查复用池的获取路径：
  - `Database.borrow(context)` 会执行池的 `validateOnAcquire` 策略；若配置了 `validationStatement`，池会执行它；
  - 因此 `DatabaseHealth` 不需要重新实现校验语句、超时或驱动能力；
  - 若 `validateOnAcquire=false`，健康检查只证明“能借到一条 `isOpen` 的连接”，不证明数据库可执行查询；这是配置取舍，文档明确。
- 健康分类：
  - `Healthy`：借到连接、租约可用、池未饱和；
  - `Degraded`：借到连接，但池饱和/有等待者，或归还诊断失败；仍可服务；
  - `Unhealthy`：获取连接失败（非取消/关闭）、租约不可用、池状态不可用；
  - 初始 `Starting`：尚未刷新。
- `refresh` 的错误通道：
  - `context == null`/`database == null` 是合同错误（panic）；
  - `Cancelled` 原样返回 `Err`，不更新缓存（避免把一次取消误报为数据库不健康）；
  - `Unavailable`（数据库/池已关闭）原样返回 `Err`，可同时把缓存更新为 `Unhealthy`；
  - 其他获取/校验失败转为 `Ok(HealthReport.unhealthy(...))`，因为“数据库不可达”是健康结果，不是调用错误。
- 错误文本只含 `errorKindName` 与池名/计数；不含 URI、SQL、参数值、用户名。
- 快照更新用内部锁保护；`check()` 读取不可变 `HealthReport`，可跨任务并发；多个 `refresh` 并发时最后完成的快照生效（不承诺顺序）。
- 不阻塞 `check()`；`refresh` 可阻塞，首参 `Context`，受池获取超时/取消约束。
- 无 close；不拥有 `Database`；数据库关闭后 `refresh` 返回 `Unavailable`，`check()` 仍返回最后快照（可能过期）。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_database` | `Database` | final | 借用；不拥有；不关闭 |
| `_name` | `String` | final | 健康检查名；非空、稳定、单行 |
| `_lastReport` | `HealthReport` | 可变引用 | 最近快照；非 null；不可变对象 |
| `_monitor` | `RuntimeMonitor` | final | 保护 `_lastReport` 更新/读取 |

不变量：

- `_database` 非 null；`_name` 非 null、trim 后非空、无换行/制表。
- `_lastReport` 始终非 null；初始为 `HealthState.Starting`。
- 快照的 `timestampMono` 单调不减（后一次刷新不早于前一次；并发时以完成顺序为准）。
- `check()` 不修改状态；`refresh()` 更新引用一次，不修改旧快照。
- 不持有租约；`refresh` 结束前关闭租约（无论成功/失败）。
- 不注册到全局注册表；实例由调用方创建/持有。
- 无 close；`_database` 生命周期由调用方管理。

---

## 4. 生命周期

由构造器创建；长期存在（通常与进程/服务同寿命）；无 close；GC 管理内存。

- 创建后 `check()` 返回 `Starting`；第一次 `refresh` 后进入 `Healthy`/`Degraded`/`Unhealthy`。
- `refresh` 可反复调用；每次生成新快照，旧快照不影响。
- `Database` 关闭后：`refresh` 返回 `Err(Unavailable)`（或更新为 unhealthy 后返回），`check()` 仍可读上次快照；调用方应停止调度。
- 本类不自动停止刷新；调度器生命周期由应用管理。
- 不拥有数据库/池；不得在 `DatabaseHealth` 中关闭 `Database`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DatabaseHealth(Database database)` | database | 非 null | null → panic |
| `DatabaseHealth(Database database, String name)` | database/name | database 非 null；name 非空、单行 | 非法 → panic |

- 默认名称固定 `"database"`；同一 `HealthRegistry` 中多个实例应使用不同名称。
- 构造不执行 I/O；不借连接；初始快照 `Starting`。
- 不复制 `Database`（引用语义）；不持有池/连接。
- 名称进入 `HealthRegistry` 与诊断；不得放秘密。
- 不提供从配置/URI 构造的重载；连接信息归 `Database`。

---

## 6. 字段表

见 §3；字段私有。

`_lastReport` 是唯一可变引用；`HealthReport` 本身不可变，读取无需深拷贝。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `name` | 检查名 | 无 | `String` | 无 | 协议方法；稳定 |
| `check` | 缓存快照 | 无 | `HealthReport` | 无 | 协议方法；非阻塞 |
| `refresh` | 主动检查 | `Context context` | `Result<HealthReport, Error>` | `Cancelled`/`Unavailable`；其他失败转 unhealthy 报告 | 可阻塞；更新缓存 |
| `lastReport` | 最近快照 | 无 | `HealthReport` | 无 | 等价 `check`；显式命名 |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 | `HealthState.Healthy` |
| `describe` | 单行诊断 | 无 | `String` | 无 | 不含 URI/SQL |

详细契约：

- `name()`：返回构造时名称；生命周期内不变；非空、单行。
- `check()`：内部锁读取 `_lastReport` 引用并返回；不阻塞、不分配大对象、不访问数据库；可跨任务并发。
- `refresh(context)`：
  - `context` 非 null；先检查 `_database.isOpen()`；false → `Err(Unavailable)`，缓存更新为 `Unhealthy`（如果尚未）。
  - `database.borrow(context)`：
    - `Cancelled` → `Err(Cancelled)`，不更新缓存；
    - `Unavailable` → `Err(Unavailable)`，缓存更新为 `Unhealthy`；
    - 其他错误 → `Ok(unhealthy("borrow failed: " + errorKindName(...)))`，更新缓存；
  - 借到租约后读取 `database.poolStats()`；租约 `isOpen()` 为 false → `Unhealthy`；否则：
    - `stats.isSaturated()` 或 `stats.waitingRequests() > 0` → `Degraded`，消息 `"pool pressure"`；
    - 否则 `Healthy`，消息 `"database reachable"`。
  - 关闭租约；关闭失败且报告仍是 `Healthy`/`Degraded` 时降为 `Degraded`，消息 `"lease release failed: " + errorKindName(...)`；已是 `Unhealthy` 时保留更严重状态；仍返回 `Ok(report)`。
  - 详情键：`pool`、`active`、`idle`、`total`、`waiting`、`max`、`closed`、`validation`（`"pool"` 或 `"isOpen"`，取决于配置可见性；本类不读取配置，只写 `"pool"` 表示走池获取路径）。不要写 URI/用户名。
  - 更新缓存后返回同一报告对象；报告不可变。
- `lastReport()`：与 `check()` 相同，便于非 `HealthCheck` 调用方显式读取。
- `isHealthy()`：`_lastReport.isHealthy()`；`Degraded` 返回 false（core 语义；`isReady` 才把 Degraded 视为可服务）。
- `describe()`：形如 `"DatabaseHealth(name=primary-db state=healthy)"`；使用 `healthStateName`；不含详情值/URI。
- 不提供 `checkNow`/`ping` 别名；主动检查统一叫 `refresh`，避免与协议 `check` 混淆。
- 不提供 `close`；不拥有数据库；不注册/注销健康检查。
- 不提供 `score`/`latency`；需要延迟指标时在调用方计时，不在健康报告塞未定义字段。

---

## 8. 使用的技术

- core `HealthCheck` 适配器；
- 缓存快照 + 主动刷新分层；
- 非阻塞读取、阻塞刷新；
- 池获取路径复用校验；
- 健康状态分类（Healthy/Degraded/Unhealthy/Starting）；
- 内部锁保护引用；
- 脱敏诊断；
- 无定时器、无全局注册表。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、Result；
- 运行时：`RuntimeMonitor.enter/exit`、`nowMono`；
- 接口：`Database`、`DatabasePoolStats`、`SqlConnection`、`HealthCheck`、`HealthReport`、`HealthState`、`healthStateName`、`Context`、`Error`、`BasicError`、`ErrorKind`、`errorKindName`。

---

## 10. 依赖的特性/接口/类

[`Database`](Database.md)、[`DatabasePoolStats`](DatabasePoolStats.md)、[`SqlConnection`](../../network/sql/SqlConnection.md)、[`HealthCheck`](../../core/runtime/HealthCheck.md)、[`HealthReport`](../../core/runtime/HealthReport.md)、[`HealthState`](../../core/runtime/HealthState.md)、[`healthStateName`](../../core/runtime/HealthState.md)、[`Context`](../../core/execution/Context.md)、[`Error`](../../core/errors/Error.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)。

---

## 11. 所有权与并发

- `DatabaseHealth` 借用 `Database`，不拥有；不关闭数据库/池。
- `check()` 可跨任务并发；`refresh()` 可并发，最后完成的快照生效；不承诺刷新顺序。
- 内部锁只保护 `_lastReport` 引用，不覆盖数据库 I/O；`refresh` 不在锁内借连接/关闭租约。
- `HealthReport` 不可变，可安全跨任务共享；详情映射是快照。
- 相等：引用身份；不提供 `equals`；不同实例永不相等。
- 无 close；无资源所有权转移。
- 名称在 `HealthRegistry` 中应唯一；重复由注册表拒绝，本类不维护全局名称表。

---

## 12. 示例与反例

正确：

```text
DatabaseHealth health = new DatabaseHealth(database, "primary-db")

Result<HealthReport, Error> refreshed = health.refresh(context)
if refreshed.isOk() {
    HealthReport report = refreshed.value()
    if report.isReady() {
        diagnose("db ready: " + report.describe())
    }
}

HealthReport cached = health.check()
```

后台调度（应用侧）：

```text
while !context.isCancelled() {
    health.refresh(context)
    sleepMillis(context, 15000)
}
```

反例：

- 在 `check()` 中执行 `select 1`；违反 core 非阻塞合同。
- 每次 HTTP 健康请求都同步 `refresh` 且无超时；慢数据库拖垮探针。
- 把 `Cancelled` 当成数据库不健康并写入缓存；取消是调用方行为。
- 在 `DatabaseHealth` 中关闭 `Database`；所有权不属于它。
- 把 URI/用户名放进 `HealthReport.details`；安全契约禁止。
- 期望 `Degraded` 时 `isHealthy()` 为 true；应使用 `isReady()`。
- 多个健康检查共用同一名称注册；注册表会拒绝或覆盖，取决于注册表实现。
- 数据库关闭后继续无限刷新；应停止调度并处理 `Unavailable`。
- 把健康检查当连接池修复/重连；它只报告，不修复。

---

## 13. 测试/场景义务

- 初始 `check()` 为 `Starting`；
- `refresh` 成功 → `Healthy`，详情含池计数、不含 URI；
- 池饱和/有等待者 → `Degraded`；
- 获取失败 → `Ok(unhealthy)`，缓存更新；错误 kind 出现在消息；
- `Cancelled` → `Err(Cancelled)`，缓存不变；
- 数据库关闭 → `Err(Unavailable)`，缓存 `Unhealthy`；
- 租约 `isOpen=false` → `Unhealthy`；租约关闭失败 → `Degraded`；
- `check()` 不阻塞、不访问数据库；并发 `check`/`refresh`；
- 快照时间戳单调不减；旧快照不被修改；
- `name` 非空/单行/稳定；默认名称；
- `isHealthy` 与 `isReady` 语义区分；
- `describe` 不含敏感信息；
- 不注册全局状态；两个实例互不影响；
- 无 close；数据库生命周期由调用方管理。

---

## 14. XNull 伪代码

```xnull
class DatabaseHealth implements HealthCheck {
    final Database _database
    final String _name
    HealthReport _lastReport
    final RuntimeMonitor _monitor

    DatabaseHealth(Database database) {
        if database == null {
            throw "DatabaseHealth: null database"
        }
        _database = database
        _name = "database"
        _lastReport = HealthReport.of(HealthState.Starting, "not checked")
        _monitor = new RuntimeMonitor()
    }

    DatabaseHealth(Database database, String name) {
        if database == null {
            throw "DatabaseHealth: null database"
        }
        if name == null || trim(name) == "" {
            throw "DatabaseHealth: empty name"
        }
        if name.indexOf("\n") >= 0 || name.indexOf("\r") >= 0
                || name.indexOf("\t") >= 0 {
            throw "DatabaseHealth: multiline name"
        }
        _database = database
        _name = name
        _lastReport = HealthReport.of(HealthState.Starting, "not checked")
        _monitor = new RuntimeMonitor()
    }

    String name() { return _name }

    HealthReport check() {
        _monitor.enter()
        HealthReport result = _lastReport
        _monitor.exit()
        return result
    }

    HealthReport lastReport() {
        return check()
    }

    Bool isHealthy() {
        return check().isHealthy()
    }

    Result<HealthReport, Error> refresh(Context context) {
        if context == null {
            throw "DatabaseHealth.refresh: null context"
        }
        if !_database.isOpen() {
            HealthReport closedReport = HealthReport.unhealthy("database closed")
            updateReport(closedReport)
            return Err(new BasicError(ErrorKind.Unavailable, "database closed"))
        }
        Result<SqlConnection, Error> borrowed = _database.borrow(context)
        if borrowed.isErr() {
            Error borrowError = borrowed.error()
            if borrowError.kind() == ErrorKind.Cancelled {
                return Err(borrowError)
            }
            if borrowError.kind() == ErrorKind.Unavailable {
                HealthReport closedReport = HealthReport.unhealthy("database unavailable")
                updateReport(closedReport)
                return Err(borrowError)
            }
            HealthReport failed = HealthReport.unhealthy(
                "borrow failed: " + errorKindName(borrowError.kind()))
            updateReport(failed)
            return Ok(failed)
        }
        SqlConnection lease = borrowed.value()
        DatabasePoolStats stats = _database.poolStats()
        HealthReport report = HealthReport.healthy("database reachable")
        if !lease.isOpen() {
            report = HealthReport.unhealthy("lease unavailable")
        } else if stats.isSaturated() || stats.waitingRequests() > 0 {
            report = HealthReport.degraded("pool pressure")
        }
        report = report.withDetail("pool", _database.name())
            .withDetail("active", str(stats.activeConnections()))
            .withDetail("idle", str(stats.idleConnections()))
            .withDetail("total", str(stats.totalConnections()))
            .withDetail("waiting", str(stats.waitingRequests()))
            .withDetail("max", str(stats.maximumConnections()))
            .withDetail("closed", str(stats.isClosed()))
            .withDetail("validation", "pool")
        Result<Unit, Error> released = lease.close()
        if released.isErr() && report.isReady() {
            report = HealthReport.degraded(
                "lease release failed: " + errorKindName(released.error().kind()))
                .withDetail("pool", _database.name())
                .withDetail("active", str(stats.activeConnections()))
                .withDetail("idle", str(stats.idleConnections()))
                .withDetail("total", str(stats.totalConnections()))
                .withDetail("waiting", str(stats.waitingRequests()))
                .withDetail("max", str(stats.maximumConnections()))
                .withDetail("closed", str(stats.isClosed()))
                .withDetail("validation", "pool")
        }
        updateReport(report)
        return Ok(report)
    }

    String describe() {
        return "DatabaseHealth(name=" + _name
            + " state=" + healthStateName(check().state()) + ")"
    }

    private void updateReport(HealthReport report) {
        _monitor.enter()
        _lastReport = report
        _monitor.exit()
    }
}
```

> 伪代码非可执行。`HealthReport.withDetail` 返回新快照；`report` 变量在关闭租约失败时重建以保持不可变。`refresh` 不在内部锁内执行数据库 I/O；`check` 只读引用。
