# xdk.time —— T0 时间与日期 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.time` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.runtime`、`xdk.errors` |
| 被依赖 | log、config、metrics（T1） |
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
| CAP-6 解析 | ISO 8601 / RFC 3339 子集与全量 layout | `parseDateTime`、`parseDateTimeLayout` |
| CAP-7 计时 | 单调 Stopwatch 开始/停止/复位/读数 | `Stopwatch` |
| CAP-8 日历加减 | 日/月/年加减与月末收敛 | `DateTime.addDays`、`addMonths`、`addYears` |
| CAP-9 可取消 sleep | 上下文取消时及时返回 | `sleepContext` |

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
    DateTime addDays(Int days)
    DateTime addMonths(Int months)
    DateTime addYears(Int years)
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
- 非法 layout 原样输出或返回固定文本；T0 不承诺完整 strftime。
- `addDays` 按 UTC 86400000ms/天；`addMonths`/`addYears` 在目标月天数不足时
  收敛到月末（`1/31 +1M` 在闰年为 `2/29`，平年为 `2/28`），并保留时分秒。
- `format`/`parseDateTimeLayout` 使用同一令牌集合：`yyyy`、`MM`、`MMM`、
  `MMMM`、`dd`、`ddd`、`dddd`、`EEE`、`EEEE`、`HH`、`mm`、`ss`、`SSS`；
  采用最长匹配，名称令牌区分大小写。

## 4. 顶层函数

```text
Long nowMs()
Long nowWallMs()
Long millis()
Long micros()
void sleepMs(Long milliseconds)
void sleep(Duration duration)
Result<Unit, Error> sleepContext(Context context, Duration duration)
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
Result<DateTime, Error> parseDateTimeLayout(String text, String layout)

class Stopwatch {
    Stopwatch()
    void start()
    Long stop()
    Long reset()
    Bool isRunning()
    Long elapsedMs()
    Duration elapsed()
}
```

- 所有 epoch/毫秒参数用 `Long`；`Int` 只用于年月日/时分秒字段。
- `sleepMs`/`sleep` 不接受 `Context`，不可取消；`sleepContext` 在上下文被取消
  或祖先/截止到期时返回 `Err(Cancelled)`，否则睡满后返回 `Ok()`。
- `Stopwatch` 构造即开始；`stop` 冻结读数，`reset` 清零并继续计时。
- `nowWallMs` 可回拨，不能用于超时；超时用 `nowMs`。
- `parseDateTimeLayout` 缺失字段按 `1970-01-01 00:00:00.000` 补齐；重复字段、
  非法字段、星期不一致和尾随字符均返回 `Err(InvalidArgument)`。

## 5. 测试义务

- `Duration` 正负加减、单位换算；
- `DateTime` 年月日/闰年/ISO 格式；
- `nowMs` 单调、`nowWallMs > 0`；
- `parseDateTime`/`parseDateTimeLayout` 成功与非法输入；
- `format`/`parseDateTimeLayout` 令牌往返一致；
- `Stopwatch` 开始/停止/复位/读数单调；
- `sleepContext` 睡满与取消两条路径；
- `addDays`/`addMonths`/`addYears` 跨月、跨年、闰日与负值；
- base/full 输出一致。

场景：`xdk_time.x`、`r4/time_stopwatch.x`、`r4/time_sleep_cancel.x`、
`r4/time_layout_parse.x`、`r4/time_calendar_edges.x`。

## 6. 后续（T1）

- `TimeZone`、`DateTime.toZone`；
- 完整 strftime 兼容（当前仅本文件列出的令牌集合）。
