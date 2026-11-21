# xdk.time ——  时间与日期 v1.0

> **1.x legacy**：本文件是旧 core 包级设计/状态账本，不是 2.x 类型合同。2.x 以 [`core/`](README.md) 的逐包目录与 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准；执行层统一为 `xdk.execution`。

> **状态（2026-11-21）**：本文件是  v1 包级设计/实现状态账本。
> 公开类型与方法形态以 [`core/`](README.md) 为准；状态汇总见 [`STATUS.md`](STATUS.md)；
> 本文件的 `当前状态`、源码路径与 K/X 明细继续保留。

| 项 | 值 |
| --- | --- |
| 包 | `xdk.time` |
| 层级 |  |
| 稳定性 | `preview` |
| 依赖 | `xdk.runtime`、`xdk.errors` |
| 被依赖 | log、config、metrics（） |
| 对应源码 | `src/xdk/core/time/*.x` |
| 当前状态 | Verified（mini） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 时钟 | 单调毫秒、墙钟毫秒 | `nowMs`、`nowWallMs`、`millis`、`micros` |
| CAP-2 时长 | 毫秒精度加减/换算 | `Duration` |
| CAP-3 时间点 | epoch 毫秒、UTC 日历 | `DateTime` |
| CAP-4 日历 | 年月日、闰年、月天数 | `Civil`、civil* 函数 |
| CAP-5 格式化 | ISO 8601 / RFC 3339 / layout | `DateTime.iso8601`、`format` |
| CAP-6 解析 | 日期时间字符串 | X `parseDateTime` |

**非目标**：IANA 时区数据库、硬实时定时器、NTP/时钟同步、完整 locale。

## 2. `Duration`（class）

```text
class Duration {
    Duration(Long milliseconds)
    Long millis()
    Long seconds()
    Long micros()
    Duration plus(Duration other)
    Duration minus(Duration other)
}
```

- 精度固定毫秒；`micros()` 只是乘 1000，不产生更高精度。
- 允许负值；加减溢出按 `Long` 回绕，调用方负责范围。
- 无资源、无 `close()`、非线程安全（值对象）。

## 3. `DateTime`（class）

```text
class DateTime {
    DateTime(Long epochMillis)
    Long timestamp()
    Civil civil()
    Int year() / month() / day()
    Int hour() / minute() / second() / millisecond()
    Int weekday() / dayOfYear()
    DateTime add(Duration duration)
    Duration diff(DateTime other)
    Bool before(DateTime other) / after(DateTime other)
    Int compare(DateTime other)
    String iso8601() / rfc3339()
    String format(String layout)
}
```

- 内部统一 UTC epoch 毫秒；`civil()` 是派生值。
- `toUTC/toLocal` 首版直通，不静默改变已有输出。
- `compare` 返回 <0/0/>0。
- 非法 layout 原样输出或返回固定文本； 不承诺完整 strftime。

## 4. 顶层函数

```text
Long nowMs()
Long nowWallMs()
Long millis()
Long micros()
void sleepMs(Long milliseconds)
void sleep(Duration duration)
Duration durationOfMillis(Long milliseconds)
Duration durationOfSeconds(Long seconds)
Duration durationOfMinutes(Long minutes)
Duration durationOfHours(Long hours)
Duration durationOfDays(Long days)
DateTime now()
DateTime dateTimeOf(Int year, Int month, Int day, Int hour, Int minute, Int second)
DateTime dateTimeOfMs(Int year, Int month, Int day, Int hour, Int minute, Int second, Int millisecond)
DateTime dateTimeFromTimestamp(Long epochMillis)
Result<DateTime, Error> parseDateTime(String text)
```

- 所有 epoch/毫秒参数用 `Long`；`Int` 只用于年月日/时分秒字段。
- `sleepMs` 不接受 `Context`， 不可取消；取消版本属于 X。
- `nowWallMs` 可回拨，不能用于超时；超时用 `nowMs`。

## 5. 测试义务

- `Duration` 正负加减、单位换算；
- `DateTime` 年月日/闰年/ISO 格式；
- `nowMs` 单调、`nowWallMs > 0`；
- `parseDateTime` 成功/非法；
- base/full 输出一致。

场景：`xdk_time.x`。

## 6. 后续（X/）

- `TimeZone`、`DateTime.toZone`；
- 完整 layout 解析/格式化；
- 可取消 sleep、Stopwatch；
- 日历加减边界。
