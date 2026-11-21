# `Schedule`

| 项 | 值 |
| --- | --- |
| 类型 | `class Schedule` |
| 包 | `xdk.schedule` |
| 稳定性 | `preview` |
| 依赖 | `ScheduleKind`、`CronExpression`、`Error` |

---

## 1. 定位

调度规格值对象：一次性相对/绝对、固定频率、固定延迟、cron。

不做：执行、misfire、时区、句柄、动态修改。

---

## 2. 设计逻辑

- 不可变；kind 决定有效字段。
- `Once`：`delayMillis` 或 `atEpochMillis`（absolute）。
- `FixedRate`：initialDelay + period；下一次按计划时间推进。
- `FixedDelay`：initialDelay + delay；下一次在上次结束后计算。
- `Cron`：持有 `CronExpression`。
- 工厂校验参数；无效 panic；字符串 cron 解析失败返回 `Result`。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_kind` | `ScheduleKind` | 类型 |
| `_delayMillis` | `Long` | Once 相对延迟 |
| `_initialDelayMillis` | `Long` | 固定周期初始延迟 |
| `_periodMillis` | `Long` | FixedRate 周期 / FixedDelay 延迟 |
| `_cron` | `CronExpression?` | Cron |
| `_atEpochMillis` | `Long` | Once 绝对时间 |
| `_absolute` | `Bool` | Once 是否绝对 |

不变量：Once 的 delay/at 非负；FixedRate/FixedDelay 的 period>0；Cron 的 cron 非 null；非 Cron 的 cron 为 null。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Schedule(...)` | 内部 | 见不变量 | 私有；非法 → panic |

应用使用静态工厂。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `once` | 相对一次 | `Long delayMillis` | `Schedule` | 负数 → panic |
| `at` | 绝对一次 | `Long epochMillis` | `Schedule` | 无 |
| `fixedRate` | 固定频率 | `Long periodMillis` | `Schedule` | ≤0 → panic |
| `fixedRate` | 带初始延迟 | `Long initialDelayMillis, Long periodMillis` | `Schedule` | 非法 → panic |
| `fixedDelay` | 固定延迟 | `Long delayMillis` | `Schedule` | ≤0 → panic |
| `fixedDelay` | 带初始延迟 | `Long initialDelayMillis, Long delayMillis` | `Schedule` | 非法 → panic |
| `cron` | 已有表达式 | `CronExpression expression` | `Schedule` | null → panic |
| `cron` | 解析文本 | `String text` | `Result<Schedule, Error>` | `InvalidArgument` |
| `kind` | 类型 | 无 | `ScheduleKind` | 无 |
| `delayMillis` | 相对延迟 | 无 | `Long` | 无 |
| `initialDelayMillis` | 初始延迟 | 无 | `Long` | 无 |
| `periodMillis` | 周期/延迟 | 无 | `Long` | 无 |
| `cronExpression` | cron/无 | 无 | `CronExpression?` | 无 |
| `atEpochMillis` | 绝对时间 | 无 | `Long` | 无 |
| `isAbsolute` | 是否绝对 | 无 | `Bool` | 无 |
| `describe` | 描述 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变规格；
- 工厂校验；
- 标签联合（kind + 可空字段）；
- cron 组合。

---

## 9. 需要的支撑

- 语言：class、Long、Bool、String、Result；
- 运行时：无；
- 接口：`ScheduleKind`、`CronExpression`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`ScheduleKind`、`CronExpression`、`Error`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`Schedule.fixedRate(60000)`；`Schedule.cron("0 3 * * *")`。  
反例：fixedRate period=0；Once 负数延迟；Cron 字段为 null；把 FixedRate 当 FixedDelay。

---

## 13. 测试/场景义务

每个工厂；kind 字段有效；describe；非法参数；cron 文本解析失败；不可变；相同输入相等语义（按引用）。

---

## 14. XNull 伪代码

```xnull
class Schedule {
    final ScheduleKind _kind
    final Long _delayMillis
    final Long _initialDelayMillis
    final Long _periodMillis
    final CronExpression? _cron
    final Long _atEpochMillis
    final Bool _absolute

    private Schedule(ScheduleKind kind, Long delayMillis, Long initialDelayMillis,
                     Long periodMillis, CronExpression? cron, Long atEpochMillis,
                     Bool absolute) {
        if kind == null { throw "Schedule: null kind" }
        if kind == ScheduleKind.Cron && cron == null {
            throw "Schedule: cron kind without expression"
        }
        if kind != ScheduleKind.Cron && cron != null {
            throw "Schedule: non-cron kind with expression"
        }
        _kind = kind
        _delayMillis = delayMillis
        _initialDelayMillis = initialDelayMillis
        _periodMillis = periodMillis
        _cron = cron
        _atEpochMillis = atEpochMillis
        _absolute = absolute
    }

    static Schedule once(Long delayMillis) {
        if delayMillis < 0 { throw "Schedule.once: negative delay" }
        return new Schedule(ScheduleKind.Once, delayMillis, 0, 0, null, 0, false)
    }

    static Schedule at(Long epochMillis) {
        return new Schedule(ScheduleKind.Once, 0, 0, 0, null, epochMillis, true)
    }

    static Schedule fixedRate(Long periodMillis) {
        return Schedule.fixedRate(0, periodMillis)
    }

    static Schedule fixedRate(Long initialDelayMillis, Long periodMillis) {
        if initialDelayMillis < 0 { throw "Schedule.fixedRate: negative initial delay" }
        if periodMillis <= 0 { throw "Schedule.fixedRate: period <= 0" }
        return new Schedule(ScheduleKind.FixedRate, 0, initialDelayMillis, periodMillis,
            null, 0, false)
    }

    static Schedule fixedDelay(Long delayMillis) {
        return Schedule.fixedDelay(0, delayMillis)
    }

    static Schedule fixedDelay(Long initialDelayMillis, Long delayMillis) {
        if initialDelayMillis < 0 { throw "Schedule.fixedDelay: negative initial delay" }
        if delayMillis <= 0 { throw "Schedule.fixedDelay: delay <= 0" }
        return new Schedule(ScheduleKind.FixedDelay, 0, initialDelayMillis, delayMillis,
            null, 0, false)
    }

    static Schedule cron(CronExpression expression) {
        if expression == null { throw "Schedule.cron: null expression" }
        return new Schedule(ScheduleKind.Cron, 0, 0, 0, expression, 0, false)
    }

    static Result<Schedule, Error> cron(String text) {
        Result<CronExpression, Error> parsed = CronExpression.parse(text)
        if parsed.isErr() { return Err(parsed.error()) }
        return Ok(Schedule.cron(parsed.value()))
    }

    ScheduleKind kind() { return _kind }
    Long delayMillis() { return _delayMillis }
    Long initialDelayMillis() { return _initialDelayMillis }
    Long periodMillis() { return _periodMillis }
    CronExpression? cronExpression() { return _cron }
    Long atEpochMillis() { return _atEpochMillis }
    Bool isAbsolute() { return _absolute }

    String describe() {
        if _kind == ScheduleKind.Once {
            if _absolute { return "once at " + str(_atEpochMillis) }
            return "once after " + str(_delayMillis) + "ms"
        }
        if _kind == ScheduleKind.FixedRate {
            return "fixedRate(" + str(_periodMillis) + "ms)"
        }
        if _kind == ScheduleKind.FixedDelay {
            return "fixedDelay(" + str(_periodMillis) + "ms)"
        }
        return "cron(" + (_cron as CronExpression).text() + ")"
    }
}
```
