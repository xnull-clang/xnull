# `DatabasePoolStats`

| 项 | 值 |
| --- | --- |
| 类型 | `class DatabasePoolStats` |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | 无 |
| 被依赖 | [`DatabasePool`](DatabasePool.md)、[`Database`](Database.md)、[`DatabaseHealth`](DatabaseHealth.md) |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

连接池某一时刻的不可变统计快照：连接数、空闲/活跃/正在打开/等待、累计创建/关闭/获取/超时/校验失败/泄漏计数、等待毫秒、快照时间与关闭标志。

用于日志、指标导出、健康判定、容量评估与测试断言；不用于计费、精确审计或控制池行为。

不做：修改池、关闭连接、重置计数、按时间窗口聚合、直方图、每连接明细、阻塞等待。

---

## 2. 设计逻辑

- 快照而不是活对象：`DatabasePool.stats()` 在锁内读取计数并返回新对象；之后池变化不影响快照。
- 计数分两类：
  - **gauge**（当前值）：`total`/`idle`/`active`/`opening`/`waiting`，用 `Int`；
  - **counter**（池生命周期累计）：创建/关闭/获取/超时/校验失败/泄漏/等待次数与毫秒，用 `Long`，避免长时间运行溢出。
- 不变量 `totalConnections == idleConnections + activeConnections + openingConnections`；`total <= maximumConnections`。这使容量判断不需要调用方自己加总。
- `openingConnections` 表示已保留槽位、尚未完成 `SqlDriver.open` 的连接；它计入总量上限，但不计入 idle/active。
- `waitingRequests` 是当前等待连接的请求数；`waitCount` 是曾等待过的获取次数，两者不同。
- `acquireCount` 只统计成功借出；`acquireTimeoutCount` 统计因获取超时失败；`validationFailureCount` 统计校验失败并丢弃的连接；`leakedLeaseCount` 统计超过泄漏阈值仍被持有的租约（诊断计数，不强制回收）。
- `waitMillisTotal` 是所有发生等待的获取累计等待毫秒；`maximumWaitMillis` 是单次最大等待；`waitCount` 是发生等待的次数；平均等待由三者计算。
- `isSaturated` 表示“池已满且有人在等”，不是“池已坏”；`isIdle` 表示当前没有活跃租约和等待者。
- `utilization` 是 `(active + opening) / maximum`，钳制到 `0.0..1.0`；`maximumConnections >= 1`，不会除零。
- 时间戳用单调毫秒 `timestampMono`，避免墙钟回拨影响排序/差值；它不是墙钟展示时间。
- 不可变；无 close；可跨任务共享；快照中的字符串只有池名，不含 URI/口令。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 池名；非空 |
| `_maximumConnections` | `Int` | final | `≥1` |
| `_minimumIdle` | `Int` | final | `0.._maximumConnections` |
| `_totalConnections` | `Int` | final | idle + active + opening |
| `_idleConnections` | `Int` | final | `≥0` |
| `_activeConnections` | `Int` | final | `≥0` |
| `_openingConnections` | `Int` | final | `≥0`；已保留槽位 |
| `_waitingRequests` | `Int` | final | `≥0` |
| `_createdCount` | `Long` | final | 成功打开的累计连接数 |
| `_closedCount` | `Long` | final | 已关闭的累计连接数 |
| `_acquireCount` | `Long` | final | 成功借出的累计次数 |
| `_acquireTimeoutCount` | `Long` | final | 获取超时的累计次数 |
| `_validationFailureCount` | `Long` | final | 校验失败并丢弃的累计次数 |
| `_leakedLeaseCount` | `Long` | final | 超过泄漏阈值的累计租约数 |
| `_waitCount` | `Long` | final | 发生过等待的累计获取次数 |
| `_waitMillisTotal` | `Long` | final | 累计等待毫秒 |
| `_maximumWaitMillis` | `Long` | final | 单次最大等待毫秒 |
| `_timestampMono` | `Long` | final | 快照单调毫秒 |
| `_isClosed` | `Bool` | final | 快照时池是否已关闭 |

不变量：

- `_name` 非 null 且非空。
- `_maximumConnections >= 1`；`0 <= _minimumIdle <= _maximumConnections`。
- 所有连接数/等待数 `≥0`；`_totalConnections == _idleConnections + _activeConnections + _openingConnections`。
- `_totalConnections <= _maximumConnections`。
- 所有 counter `≥0`；`_maximumWaitMillis <= _waitMillisTotal`。
- `_timestampMono >= 0`。
- 对象不可变；无 close。

---

## 4. 生命周期

由 `DatabasePool.stats()` 创建；构造后不可变；无 close；GC 管理内存；可跨任务共享。

- 每次 `stats()` 返回独立快照；旧快照保留当时的数值。
- 把快照导出到指标系统时，counter 应按差值计算速率；gauge 直接使用。
- 池关闭后仍可读取最后快照；`isClosed=true`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DatabasePoolStats(String name, Int maximumConnections, Int minimumIdle, Int totalConnections, Int idleConnections, Int activeConnections, Int openingConnections, Int waitingRequests, Long createdCount, Long closedCount, Long acquireCount, Long acquireTimeoutCount, Long validationFailureCount, Long leakedLeaseCount, Long waitCount, Long waitMillisTotal, Long maximumWaitMillis, Long timestampMono, Bool isClosed)` | 19 个字段 | 见 §3 | 非法 → panic |

构造不访问池；所有值由 `DatabasePool` 在锁内读取。非法组合是池实现 bug，因此 panic，不返回 `Result`。

---

## 6. 字段表

见 §3；字段私有。

`_name` 是唯一字符串字段；不包含 URI、主机、用户、口令或 SQL。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `name` | 池名 | 无 | `String` | 无 | 非敏感 |
| `maximumConnections` | 总量上限 | 无 | `Int` | 无 | ≥1 |
| `minimumIdle` | 空闲下限 | 无 | `Int` | 无 | 0..max |
| `totalConnections` | 当前总量 | 无 | `Int` | 无 | idle+active+opening |
| `idleConnections` | 空闲数 | 无 | `Int` | 无 | ≥0 |
| `activeConnections` | 活跃租约数 | 无 | `Int` | 无 | ≥0 |
| `openingConnections` | 正在打开数 | 无 | `Int` | 无 | 已保留槽位 |
| `waitingRequests` | 等待请求数 | 无 | `Int` | 无 | ≥0 |
| `createdCount` | 累计创建 | 无 | `Long` | 无 | ≥0 |
| `closedCount` | 累计关闭 | 无 | `Long` | 无 | ≥0 |
| `acquireCount` | 累计成功获取 | 无 | `Long` | 无 | ≥0 |
| `acquireTimeoutCount` | 累计获取超时 | 无 | `Long` | 无 | ≥0 |
| `validationFailureCount` | 累计校验失败 | 无 | `Long` | 无 | ≥0 |
| `leakedLeaseCount` | 累计泄漏诊断 | 无 | `Long` | 无 | ≥0 |
| `waitCount` | 累计发生等待的获取 | 无 | `Long` | 无 | ≥0 |
| `waitMillisTotal` | 累计等待毫秒 | 无 | `Long` | 无 | ≥0 |
| `maximumWaitMillis` | 单次最大等待 | 无 | `Long` | 无 | ≥0 |
| `timestampMono` | 快照时间 | 无 | `Long` | 无 | 单调毫秒 |
| `isClosed` | 池是否已关闭 | 无 | `Bool` | 无 | 快照时值 |
| `utilization` | 使用率 | 无 | `Double` | 无 | `(active+opening)/max`，钳制 |
| `averageWaitMillis` | 平均等待 | 无 | `Double` | 无 | 无等待时为 0.0 |
| `isSaturated` | 是否饱和 | 无 | `Bool` | 无 | 满且有人在等 |
| `isIdle` | 是否空闲 | 无 | `Bool` | 无 | 无活跃/等待 |
| `copy` | 独立副本 | 无 | `DatabasePoolStats` | 无 | 新对象 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 只含计数/池名 |

详细契约：

- `utilization()`：`maximumConnections == 0` 不会发生（构造 panic）；`(active + opening) / maximum` 使用浮点除法；小于 0 返回 0.0，大于 1 返回 1.0。`opening` 计入使用率，因为已占用上限槽位。
- `averageWaitMillis()`：`waitCount == 0` 返回 0.0；否则 `waitMillisTotal / waitCount`；不承诺与单次最大等待一致。
- `isSaturated()`：`totalConnections >= maximumConnections && waitingRequests > 0`。池满但无人等待不算饱和；有人等待但还有空闲也不算。
- `isIdle()`：`activeConnections == 0 && waitingRequests == 0`；`opening > 0` 时仍可能为 true（正在预热），文档明确。
- `copy()` 逐字段复制；返回对象与快照独立（字段均为值类型/String 不可变）。
- `describe()` 形如 `"DatabasePoolStats(name=orders total=5 idle=3 active=2 opening=0 waiting=0 max=10 acquired=120 timeouts=1 validationFailures=0 leaks=0)"`；不输出 URI/选项/用户名。
- 不提供 `equals`/哈希：快照按引用身份比较；需要比较时逐字段读取。数值快照频繁变化，不推荐作 `Map` 键。
- 不提供 `reset`/`set`；统计只读。
- 不提供连接级明细：需要诊断单条租约时用泄漏阈值与租约自身的 `isOpen`/错误，不在此快照中暴露。

---

## 8. 使用的技术

- 不可变快照；
- gauge/counter 分离；
- `Int` 当前计数 + `Long` 累计计数；
- 钳制浮点比率；
- 饱和/空闲判定；
- 无敏感字段诊断。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Long、Double、Bool；
- 运行时：`nowMono`、`str(Int)`、`str(Long)`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无其他 XDK 类型。由 [`DatabasePool.stats`](DatabasePool.md) 创建；被 [`DatabaseHealth`](DatabaseHealth.md) 读取用于健康详情。

---

## 11. 所有权与并发

- 不可变；可跨任务共享；无资源；无取消点。
- 构造不复制容器（没有容器字段）；String 不可变，直接持有。
- 相等：引用身份；不提供 `equals`/哈希；不推荐作 `Map` 键。
- 排序：不提供；需要按时间比较时用 `timestampMono`。
- 计数器是池生命周期累计值，不是快照之间的差值；指标导出应保存上一快照并自行求差。

---

## 12. 示例与反例

正确：

```text
DatabasePoolStats stats = database.poolStats()
if stats.isSaturated() {
    diagnose("db pool saturated: " + stats.describe())
}
```

```text
Long acquired = stats.acquireCount() - previous.acquireCount()
Double utilization = stats.utilization()
```

反例：

- 把 `totalConnections` 当作“已创建总数”；累计创建用 `createdCount`。
- 把 `isSaturated()` 当作“池坏了”；它只表示容量压力。
- 用 `waitingRequests` 当累计等待次数。
- 用墙钟时间解释 `timestampMono`。
- 在快照中期望看到连接串/用户名；安全契约禁止。
- 修改快照期望影响池；快照只读。
- 用 `createdCount - closedCount` 精确推算当前总量；`opening` 不包含在 created 中，且计数是尽力快照。
- 把 `leakedLeaseCount` 当“已强制回收连接数”；它只是诊断计数。

---

## 13. 测试/场景义务

- 构造 19 个字段的边界：0/1/max、负值、total 不等于三项和、total > max、min > max；
- counter 负值、`maximumWaitMillis > waitMillisTotal` panic；
- `utilization`：0、半满、满、opening 计入、钳制；
- `averageWaitMillis`：0 等待、单次、多次；
- `isSaturated`：满+等待、满无等待、未满+等待、关闭；
- `isIdle`：有活跃、有等待、仅 opening；
- `copy` 独立；
- `describe` 不含 URI/选项；
- 池运行中多次 `stats()` 快照不互相影响；
- 关闭后 `isClosed=true`，其他值仍可读；
- 并发 `stats()` 与借还、关闭。

---

## 14. XNull 伪代码

```xnull
class DatabasePoolStats {
    final String _name
    final Int _maximumConnections
    final Int _minimumIdle
    final Int _totalConnections
    final Int _idleConnections
    final Int _activeConnections
    final Int _openingConnections
    final Int _waitingRequests
    final Long _createdCount
    final Long _closedCount
    final Long _acquireCount
    final Long _acquireTimeoutCount
    final Long _validationFailureCount
    final Long _leakedLeaseCount
    final Long _waitCount
    final Long _waitMillisTotal
    final Long _maximumWaitMillis
    final Long _timestampMono
    final Bool _isClosed

    DatabasePoolStats(String name, Int maximumConnections, Int minimumIdle,
                      Int totalConnections, Int idleConnections,
                      Int activeConnections, Int openingConnections,
                      Int waitingRequests, Long createdCount, Long closedCount,
                      Long acquireCount, Long acquireTimeoutCount,
                      Long validationFailureCount, Long leakedLeaseCount,
                      Long waitCount, Long waitMillisTotal,
                      Long maximumWaitMillis, Long timestampMono, Bool isClosed) {
        if name == null || name == "" {
            throw "DatabasePoolStats: empty name"
        }
        if maximumConnections < 1 {
            throw "DatabasePoolStats: maximumConnections < 1"
        }
        if minimumIdle < 0 || minimumIdle > maximumConnections {
            throw "DatabasePoolStats: invalid minimumIdle"
        }
        if idleConnections < 0 || activeConnections < 0
                || openingConnections < 0 || waitingRequests < 0 {
            throw "DatabasePoolStats: negative gauge"
        }
        if totalConnections != idleConnections + activeConnections + openingConnections {
            throw "DatabasePoolStats: inconsistent total"
        }
        if totalConnections > maximumConnections {
            throw "DatabasePoolStats: total above maximum"
        }
        if createdCount < 0 || closedCount < 0 || acquireCount < 0
                || acquireTimeoutCount < 0 || validationFailureCount < 0
                || leakedLeaseCount < 0 || waitCount < 0
                || waitMillisTotal < 0 || maximumWaitMillis < 0 {
            throw "DatabasePoolStats: negative counter"
        }
        if maximumWaitMillis > waitMillisTotal {
            throw "DatabasePoolStats: maximum wait above total"
        }
        if timestampMono < 0 {
            throw "DatabasePoolStats: negative timestamp"
        }
        _name = name
        _maximumConnections = maximumConnections
        _minimumIdle = minimumIdle
        _totalConnections = totalConnections
        _idleConnections = idleConnections
        _activeConnections = activeConnections
        _openingConnections = openingConnections
        _waitingRequests = waitingRequests
        _createdCount = createdCount
        _closedCount = closedCount
        _acquireCount = acquireCount
        _acquireTimeoutCount = acquireTimeoutCount
        _validationFailureCount = validationFailureCount
        _leakedLeaseCount = leakedLeaseCount
        _waitCount = waitCount
        _waitMillisTotal = waitMillisTotal
        _maximumWaitMillis = maximumWaitMillis
        _timestampMono = timestampMono
        _isClosed = isClosed
    }

    String name() { return _name }
    Int maximumConnections() { return _maximumConnections }
    Int minimumIdle() { return _minimumIdle }
    Int totalConnections() { return _totalConnections }
    Int idleConnections() { return _idleConnections }
    Int activeConnections() { return _activeConnections }
    Int openingConnections() { return _openingConnections }
    Int waitingRequests() { return _waitingRequests }
    Long createdCount() { return _createdCount }
    Long closedCount() { return _closedCount }
    Long acquireCount() { return _acquireCount }
    Long acquireTimeoutCount() { return _acquireTimeoutCount }
    Long validationFailureCount() { return _validationFailureCount }
    Long leakedLeaseCount() { return _leakedLeaseCount }
    Long waitCount() { return _waitCount }
    Long waitMillisTotal() { return _waitMillisTotal }
    Long maximumWaitMillis() { return _maximumWaitMillis }
    Long timestampMono() { return _timestampMono }
    Bool isClosed() { return _isClosed }

    Double utilization() {
        Double used = _activeConnections + _openingConnections
        Double ratio = used / _maximumConnections
        if ratio < 0.0 { return 0.0 }
        if ratio > 1.0 { return 1.0 }
        return ratio
    }

    Double averageWaitMillis() {
        if _waitCount == 0 {
            return 0.0
        }
        return _waitMillisTotal / _waitCount
    }

    Bool isSaturated() {
        return _totalConnections >= _maximumConnections
            && _waitingRequests > 0
    }

    Bool isIdle() {
        return _activeConnections == 0 && _waitingRequests == 0
    }

    DatabasePoolStats copy() {
        return new DatabasePoolStats(_name, _maximumConnections, _minimumIdle,
            _totalConnections, _idleConnections, _activeConnections,
            _openingConnections, _waitingRequests, _createdCount, _closedCount,
            _acquireCount, _acquireTimeoutCount, _validationFailureCount,
            _leakedLeaseCount, _waitCount, _waitMillisTotal,
            _maximumWaitMillis, _timestampMono, _isClosed)
    }

    String describe() {
        return "DatabasePoolStats(name=" + _name
            + " total=" + str(_totalConnections)
            + " idle=" + str(_idleConnections)
            + " active=" + str(_activeConnections)
            + " opening=" + str(_openingConnections)
            + " waiting=" + str(_waitingRequests)
            + " max=" + str(_maximumConnections)
            + " acquired=" + str(_acquireCount)
            + " timeouts=" + str(_acquireTimeoutCount)
            + " validationFailures=" + str(_validationFailureCount)
            + " leaks=" + str(_leakedLeaseCount)
            + " closed=" + str(_isClosed)
            + ")"
    }
}
```

> 伪代码非可执行。`Double` 除法为浮点除法；`str(Bool)` 输出 `true`/`false`。快照不持有池锁，构造后不再访问池。
