# `xdk.time` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.time` |
| 层 | `xdk.core` / L2 |
| 依赖 | `xdk.errors`、`xdk.runtime` |
| 被依赖 | `log`、`config`、`metrics`、`net.http` |
| 稳定性 | 基础 `stable`；Timer/格式解析 `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.time` 提供时钟、时长、时间点、日期、时间、时区、计时器：

- 单调/墙钟；
- `Duration`/`Instant`/`DateTime`/`Date`/`Time`；
- `TimeZone`（UTC/固定偏移）；
- `Clock`/`Stopwatch`/`Timer`；
- `DateTimeFormatter`/`DateTimeParser`；
- `Month`/`Weekday`/`TimeUnit` 枚举。

不做：IANA 时区数据库（X）、NTP、闰秒、完整 locale、日历系统。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 毫秒基准 | 内部 epoch/时长统一毫秒；微秒仅显式 API |
| UTC 优先 | DateTime 内部 UTC；`toLocal`  直通 |
| 单调 vs 墙钟 | deadline 用 `nowMono`；展示用 `nowWall` |
| 不可变值对象 | Duration/Instant/DateTime/Date/Time 不可变 |
| 显式单位 | 参数名写 `milliseconds`/`seconds`，不混用 |
| 无全局时区 | 时区显式传入/默认 UTC |
| 可取消 | `sleepContext` 可取消；`sleepMs`/`sleep` 不可取消 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Month` | enum | 月份 | [`Month.md`](Month.md) |
| `Weekday` | enum | 星期 | [`Weekday.md`](Weekday.md) |
| `TimeUnit` | enum | 时间单位换算 | [`TimeUnit.md`](TimeUnit.md) |
| `Duration` | class | 毫秒精度时长 | [`Duration.md`](Duration.md) |
| `Instant` | class | epoch 时间点 | [`Instant.md`](Instant.md) |
| `DateTime` | class | UTC 日期时间 | [`DateTime.md`](DateTime.md) |
| `Date` | class | 年月日 | [`Date.md`](Date.md) |
| `Time` | class | 时分秒毫秒 | [`Time.md`](Time.md) |
| `TimeZone` | class | UTC/固定偏移 | [`TimeZone.md`](TimeZone.md) |
| `Clock` | class | 系统/单调/固定时钟 | [`Clock.md`](Clock.md) |
| `Stopwatch` | class | 单调计时 | [`Stopwatch.md`](Stopwatch.md) |
| `Timer` | class | 延迟/周期任务（X） | [`Timer.md`](Timer.md) |
| `DateTimeFormatter` | class | 日期时间格式化 | [`DateTimeFormatter.md`](DateTimeFormatter.md) |
| `DateTimeParser` | class | 日期时间解析 | [`DateTimeParser.md`](DateTimeParser.md) |

---

## 4. 顶层函数

### 4.1 时钟/休眠

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `nowMs` | 单调毫秒 | 无 | `Long` | 无 |
| `nowWallMs` | epoch 毫秒 | 无 | `Long` | 无 |
| `millis` | 单调毫秒别名 | 无 | `Long` | 无 |
| `micros` | 单调微秒 | 无 | `Long` | 无 |
| `sleepMs` | 阻塞休眠 | `Long milliseconds` | `void` | 负值 → panic |
| `sleep` | 阻塞休眠 | `Duration duration` | `void` | 负时长 → panic |
| `sleepContext` | 可取消休眠 | `Context context, Duration duration` | `Result<Unit, Error>` | `Cancelled`；负时长 → panic |
| `sleepCancellable` | `sleepContext` 的旧名别名 | 同上 | 同上 | 同上 |

### 4.2 构造/转换

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `durationOfMillis` | 构造 | `Long milliseconds` | `Duration` | 无 |
| `durationOfSeconds` | 构造 | `Long seconds` | `Duration` | 溢出 → panic |
| `durationOfMinutes` | 构造 | `Long minutes` | `Duration` | 溢出 → panic |
| `durationOfHours` | 构造 | `Long hours` | `Duration` | 溢出 → panic |
| `durationOfDays` | 构造 | `Long days` | `Duration` | 溢出 → panic |
| `dateTimeOf` | 构造 UTC | `Int year, Month month, Int day, Int hour, Int minute, Int second` | `DateTime` | 非法字段 → panic |
| `dateTimeOfMs` | 带毫秒 | 同上 + `Int millisecond` | `DateTime` | 非法字段 → panic |
| `dateTimeFromTimestamp` | epoch 构造 | `Long epochMillis` | `DateTime` | 无 |
| `now` | 当前墙钟 | 无 | `DateTime` | 无 |
| `parseDateTime` | 解析 ISO | `String text` | `Result<DateTime, Error>` | `InvalidArgument` |
| `parseDateTimeLayout` | 按布局解析 | `String text, String layout` | `Result<DateTime, Error>` | `InvalidArgument` |
| `civilIsLeap` | 闰年 | `Int year` | `Bool` | 无 |
| `civilDaysInMonth` | 月天数 | `Int year, Month month` | `Int` | 非法 month/year → panic |

### 4.3 技术/支撑/依赖

- 技术：epoch 毫秒、单调时钟、Howard Hinnant 历法算法、格式化/解析、时区偏移。
- 支撑：`runtime.nowMono/nowWall`、`sleep` 原语、整数运算。
- 依赖：`errors`、`runtime`、`Duration`、`Instant`、`DateTime`、`Date`、`Time`、`TimeZone`、`Month`、`Weekday`、`TimeUnit`、`DateTimeFormatter`、`DateTimeParser`。

### 4.4 关键函数伪代码

```xnull
Long nowMs() {
    return nowMono()
}

Long nowWallMs() {
    return nowWall()
}

void sleepMs(Long milliseconds) {
    if milliseconds < 0 {
        throw "sleepMs: negative duration"
    }
    sleepMillisRaw(milliseconds)
}

Result<Unit, Error> sleepContext(Context context, Duration duration) {
    if context == null || duration == null {
        throw "sleepContext: null argument"
    }
    if duration.millis() < 0 {
        throw "sleepContext: negative duration"
    }
    if context.isCancelled() {
        return Err(new BasicError(ErrorKind.Cancelled, "sleepContext: cancelled"))
    }
    Int result = sleepContextRaw(context, duration.millis())
    if result != 0 {
        return Err(new BasicError(ErrorKind.Cancelled, "sleepContext: cancelled"))
    }
    return Ok(unit)
}

Result<DateTime, Error> parseDateTimeLayout(String text, String layout) {
    if text == null || layout == null {
        throw "parseDateTimeLayout: null argument"
    }
    return parseDateTimeLayoutRaw(text, layout)
}

Bool civilIsLeap(Int year) {
    if year % 400 == 0 { return true }
    if year % 100 == 0 { return false }
    return year % 4 == 0
}

Int civilDaysInMonth(Int year, Month month) {
    if month == Month.February {
        if civilIsLeap(year) { return 29 }
        return 28
    }
    if month == Month.April || month == Month.June
        || month == Month.September || month == Month.November {
        return 30
    }
    return 31
}
```

---

## 5. 场景

### S2：服务 deadline

`nowMono` + `Duration` + `Task.joinDeadline`；不用墙钟；超时 `Timeout`。

### S3：日志时间戳

`nowWallMs`/`DateTime.iso8601`；墙钟可回拨；日志只展示。

### S4：定时任务

`Timer.after/every` 或 `Stopwatch`；取消/关闭；周期任务不重叠（应用策略）。

### S5：日期计算

`Date.plusDays/plusMonths`；闰年/月末边界；`DateTime.add(Duration)`。

### S5：解析/格式化

`DateTimeParser`/`DateTimeFormatter`；ISO/RFC3339；非法输入 `InvalidArgument`。

### S6：时区展示

`TimeZone.utc`/`fixed`；`offsetAt`； 不做 IANA 规则。

---

## 6. 缺口与决策

| 项 | 决策 |
| --- | --- |
| IANA 时区数据库 | X； 只 UTC/固定偏移 |
| 闰秒 | 不处理 |
| locale/日历系统 |  `i18n` |
| 可取消 sleep | `sleepContext` 已纳入；`sleepMs`/`sleep` 保持不可取消 |
| 高精度时钟 | 毫秒基准；`micros` 只读 |
| 定时器公平性/漂移 | 不承诺 |
| 日期加减月末 | 钳制到月末；文档固定 |
| `toLocal` |  直通 UTC；不静默改变 |
| 时间范围 | `Long` epoch 毫秒；不处理超出范围 |

## 9. 1.x 兼容合同（C7）

| 1.x API | 2.x 合同 | 失败/边界 |
| --- | --- | --- |
| `sleepContext(Context, Duration)` | 顶层 `sleepContext`；睡满 `Ok()`，取消 `Err(Cancelled)`；`sleepCancellable` 为旧名别名 | null → panic；负时长 → panic；`sleepMs`/`sleep` 仍不可取消 |
| `Stopwatch` | [`Stopwatch.md`](Stopwatch.md)；`start/stop/reset/elapsed/elapsedMillis/isRunning` | 2.x 构造器不自动开始；1.x 构造即开始、`stop/reset` 返回 `Long`，迁移为显式 `start()` + `elapsedMillis()`；见 §15 |
| `parseDateTimeLayout(String, String)` | 顶层 `parseDateTimeLayout`；令牌集与 `DateTimeFormatter` 一致 | 重复字段/非法字段/星期不一致/尾随字符 → `InvalidArgument`；缺失字段按 1970-01-01 补齐 |
| `DateTime.format(String)` | `DateTimeFormatter.ofPattern(layout).format(dateTime)` | 2.x 令牌集见 [`DateTimeFormatter.md`](DateTimeFormatter.md)；不做 locale 名称 |

示例：

```xnull
Result<Unit, Error> slept = sleepContext(context, durationOfMillis(100))
Stopwatch watch = new Stopwatch()
watch.start()
watch.stop()
Long elapsed = watch.elapsedMillis()
Result<DateTime, Error> parsed = parseDateTimeLayout("2026-11-22 12:00:00", "yyyy-MM-dd HH:mm:ss")
```

测试义务：`sleepContext` 睡满/取消；`Stopwatch` 未启动/启动/停止/复位/读数；`parseDateTimeLayout` 成功与非法输入；`format` 与 `parseDateTimeLayout` 令牌往返一致；`sleepMs`/`sleep` 仍不可取消。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Data`、`@Builder`、`@Copy` |
| 处理器 | 标准 A8 |
| 生成物 | Duration/Instant/Date/Time/DateTime 用合法 struct；格式化器用数据类/ builder |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Duration`/`Instant`/`Date`/`Time`/`DateTime` | `struct` | 原生值语义；无需 `@Value` |
| `TimeZone`/`DateTimeFormatter`/`DateTimeParser` | `@Data`/`@Builder` | 配置快照/构造 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
