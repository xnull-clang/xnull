# `SchedulerOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class SchedulerOptions` |
| 包 | `xdk.schedule` |
| 稳定性 | `preview` |
| 依赖 | `MisfirePolicy`、`TimeZone` |

---

## 1. 定位

调度器选项：工作并发、最大作业数、misfire 策略、默认时区、关闭超时、追赶上限。

不做：作业定义、执行、持久化、分布式选举。

---

## 2. 设计逻辑

- 可变 builder；`Scheduler.create` 复制。
- 默认：1 worker、1024 作业、Skip、UTC、30s 关闭超时、追赶上限 10。
- `workerCount ≥1`；`maxPending ≥1`；`shutdownTimeoutMillis ≥0`（0=无限等待）；`catchUpLimit ≥0`。
- `defaultTimeZone` 非 null；`misfirePolicy` 非 null。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_workerCount` | `Int` | 并发 worker |
| `_maxPending` | `Int` | 最大作业数 |
| `_misfirePolicy` | `MisfirePolicy` | 错过策略 |
| `_defaultTimeZone` | `TimeZone` | cron 默认时区 |
| `_shutdownTimeoutMillis` | `Long` | 关闭等待上限 |
| `_catchUpLimit` | `Int` | 追赶次数上限 |

不变量：workerCount≥1；maxPending≥1；timeout≥0；catchUpLimit≥0；时区/策略非 null。

---

## 4. 生命周期

可变；无 close；复制后独立。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SchedulerOptions()` | 无 | 默认值 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `workerCount` | 设置 worker | `Int` | `SchedulerOptions` | <1 → panic |
| `maxPending` | 设置作业上限 | `Int` | `SchedulerOptions` | <1 → panic |
| `misfirePolicy` | 设置策略 | `MisfirePolicy` | `SchedulerOptions` | null → panic |
| `defaultTimeZone` | 设置时区 | `TimeZone` | `SchedulerOptions` | null → panic |
| `shutdownTimeoutMillis` | 设置关闭超时 | `Long` | `SchedulerOptions` | <0 → panic |
| `catchUpLimit` | 设置追赶上限 | `Int` | `SchedulerOptions` | <0 → panic |
| `getWorkerCount` | 读取 worker | 无 | `Int` | 无 |
| `getMaxPending` | 读取上限 | 无 | `Int` | 无 |
| `getMisfirePolicy` | 读取策略 | 无 | `MisfirePolicy` | 无 |
| `getDefaultTimeZone` | 读取时区 | 无 | `TimeZone` | 无 |
| `getShutdownTimeoutMillis` | 读取超时 | 无 | `Long` | 无 |
| `getCatchUpLimit` | 读取追赶上限 | 无 | `Int` | 无 |
| `copy` | 独立副本 | 无 | `SchedulerOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 边界校验；
- 防御性复制。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool；
- 运行时：无；
- 接口：`MisfirePolicy`、`TimeZone`。

---

## 10. 依赖的特性/接口/类

`MisfirePolicy`、`TimeZone`。

---

## 11. 所有权与并发

可变；非线程安全；无资源；传入 Scheduler 后被复制。

---

## 12. 示例与反例

正确：`new SchedulerOptions().workerCount(4).misfirePolicy(MisfirePolicy.Skip)`。  
反例：0 worker；负超时；CatchUp 上限 0 当无限；构造后修改期望生效。

---

## 13. 测试/场景义务

默认值；每个 setter；边界；copy 独立性；时区/策略；关闭超时 0；catchUpLimit 0。

---

## 14. XNull 伪代码

```xnull
class SchedulerOptions {
    Int _workerCount = 1
    Int _maxPending = 1024
    MisfirePolicy _misfirePolicy = MisfirePolicy.Skip
    TimeZone _defaultTimeZone = TimeZone.utc()
    Long _shutdownTimeoutMillis = 30000
    Int _catchUpLimit = 10

    SchedulerOptions() {
    }

    SchedulerOptions workerCount(Int value) {
        if value < 1 { throw "SchedulerOptions.workerCount: < 1" }
        _workerCount = value
        return self
    }

    SchedulerOptions maxPending(Int value) {
        if value < 1 { throw "SchedulerOptions.maxPending: < 1" }
        _maxPending = value
        return self
    }

    SchedulerOptions misfirePolicy(MisfirePolicy value) {
        if value == null { throw "SchedulerOptions.misfirePolicy: null" }
        _misfirePolicy = value
        return self
    }

    SchedulerOptions defaultTimeZone(TimeZone value) {
        if value == null { throw "SchedulerOptions.defaultTimeZone: null" }
        _defaultTimeZone = value
        return self
    }

    SchedulerOptions shutdownTimeoutMillis(Long value) {
        if value < 0 { throw "SchedulerOptions.shutdownTimeoutMillis: negative" }
        _shutdownTimeoutMillis = value
        return self
    }

    SchedulerOptions catchUpLimit(Int value) {
        if value < 0 { throw "SchedulerOptions.catchUpLimit: negative" }
        _catchUpLimit = value
        return self
    }

    Int getWorkerCount() { return _workerCount }
    Int getMaxPending() { return _maxPending }
    MisfirePolicy getMisfirePolicy() { return _misfirePolicy }
    TimeZone getDefaultTimeZone() { return _defaultTimeZone }
    Long getShutdownTimeoutMillis() { return _shutdownTimeoutMillis }
    Int getCatchUpLimit() { return _catchUpLimit }

    SchedulerOptions copy() {
        SchedulerOptions result = new SchedulerOptions()
        result._workerCount = _workerCount
        result._maxPending = _maxPending
        result._misfirePolicy = _misfirePolicy
        result._defaultTimeZone = _defaultTimeZone
        result._shutdownTimeoutMillis = _shutdownTimeoutMillis
        result._catchUpLimit = _catchUpLimit
        return result
    }
}
```
