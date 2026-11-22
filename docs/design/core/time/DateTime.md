# `DateTime`

| 项 | 值 |
| --- | --- |
| 类型 | `struct DateTime` |
| 包 | `xdk.time` |
| 稳定性 | `stable` |
| 依赖 | `Duration`、`Instant`、`Date`、`Time`、`Month`、`Weekday`、`DateTimeFormatter`、`DateTimeParser` |

---

> 类型选择：`struct DateTime`；唯一字段是 Long，全部为值类型，使用原生值语义，不需要 `@Value`。

## 1. 定位

UTC 日期时间：epoch 毫秒 + 年月日时分秒毫秒派生；支持加减/比较/格式化/解析。

不做：IANA 时区规则、闰秒、locale、日历系统。

---

## 2. 设计逻辑

- 唯一字段 `_epochMillis: Long`；内部 UTC。
- 派生字段按需用 civil 算法换算，不缓存。
- `toLocal`  直通 UTC；`toUTC` 返回 self。
- 所有 epoch/毫秒运算用 `Long`；不得 `as Int` 截断。
- 不可变；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_epochMillis` | `Long` | UTC epoch 毫秒 |

不变量：值 = epochMillis；派生字段合法；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DateTime.of` | year, Month, day, hour, minute, second | 字段合法 | 非法 → panic |
| `DateTime.ofMs` | 同上 + millisecond | 字段合法 | 非法 → panic |
| `DateTime.fromTimestamp` | epochMillis | 任意 Long | 无 |
| `DateTime.parse` | text | ISO 8601 | `InvalidArgument` |
| `DateTime.now` | 无 | 墙钟 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 组 | 方法 |
| --- | --- |
| 读取 | `timestamp`、`instant`、`date`、`time`、`civil`、`year`、`month`、`day`、`hour`、`minute`、`second`、`millisecond`、`weekday`、`dayOfYear`、`weekOfYear`、`isLeapYear` |
| 修改 | `withYear`、`withMonth`、`withDay`、`withHour`、`withMinute`、`withSecond`、`withMillisecond`、`add(Duration)`、`addYears`、`addMonths`、`addDays`、`addHours`、`addMinutes`、`addSeconds`、`addMillis`、`subtract(...)` |
| 比较/转换 | `before`、`after`、`compare`、`equals`、`toInstant`、`toUTC`、`toLocal`、`startOfDay`、`endOfDay`、`startOfMonth`、`endOfMonth` |
| 格式化 | `format(DateTimeFormatter)`、`format(String)`、`iso8601`、`rfc3339`、`toString` |

详细契约：

- `month()` 返回 `Month`；`weekday()` 返回 ISO `Weekday`。
- `addMonths` 月末钳制；`addYears` 2/29 钳制到 2/28。
- `startOfDay` 00:00:00.000；`endOfDay` 23:59:59.999。
- `format(String)` 是有限布局令牌，不承诺完整 strftime。
- `parse` 由 `DateTimeParser` 完成。

---

## 8. 使用的技术

- epoch 毫秒；
- Howard Hinnant `daysFromCivil/civilFromDays`；
- floor div/mod；
- 年末/月末钳制；
- 格式化/解析委托。

---

## 9. 需要的支撑

- 语言：struct、Long、Int、Bool、String、Result；
- 运行时：无（`now` 用 `runtime.nowWall`）；
- 接口：`Duration`、`Instant`、`Date`、`Time`、`Month`、`Weekday`、`DateTimeFormatter`、`DateTimeParser`、`civilDaysInMonth`、`civilIsLeap`、`daysFromCivil`、`civilFromDays`、`floorDiv`、`floorMod`。

---

## 10. 依赖的特性/接口/类

`Duration`、`Instant`、`Date`、`Time`、`Month`、`Weekday`、`DateTimeFormatter`、`DateTimeParser`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`DateTime.of(2026, Month.November, 21, 12, 0, 0).iso8601()`。  
反例：用 `DateTime` 做时区本地时间；`as Int` 截断 epoch；月末 `addMonths` 期望溢出。

---

## 13. 测试/场景义务

闰年/月末/年末；epoch 正/负；日期/时间派生；weekday/dayOfYear；add 各字段；比较；格式化/解析；toLocal 直通。

---

## 14. XNull 伪代码

```xnull
struct DateTime {
    final Long _epochMillis

    DateTime(Long epochMillis) {
        _epochMillis = epochMillis
    }

    static DateTime of(Int year, Month month, Int day, Int hour, Int minute, Int second) {
        return DateTime.ofMs(year, month, day, hour, minute, second, 0)
    }

    static DateTime ofMs(Int year, Month month, Int day, Int hour, Int minute, Int second, Int millisecond) {
        if hour < 0 || hour > 23 || minute < 0 || minute > 59
            || second < 0 || second > 59 || millisecond < 0 || millisecond > 999 {
            throw "DateTime.ofMs: invalid time"
        }
        Int monthNumber = number(month)
        Int daysInMonth = civilDaysInMonth(year, month)
        if day < 1 || day > daysInMonth {
            throw "DateTime.ofMs: invalid day"
        }
        Long days = daysFromCivil(year, monthNumber, day) as Long
        Long millis = days * 86400000
            + hour * 3600000 + minute * 60000 + second * 1000 + millisecond
        return new DateTime(millis)
    }

    static DateTime fromTimestamp(Long epochMillis) {
        return new DateTime(epochMillis)
    }

    static DateTime now() {
        return new DateTime(nowWall())
    }

    Long timestamp() { return _epochMillis }
    Instant instant() { return new Instant(_epochMillis) }

    Civil civil() {
        return civilFromDays(floorDiv(_epochMillis, 86400000) as Int)
    }

    Date date() {
        Civil civilDate = self.civil()
        return new Date(civilDate.year, civilDate.month, civilDate.day)
    }

    Time time() {
        Long dayMillis = floorMod(_epochMillis, 86400000)
        Int hour = (dayMillis / 3600000) as Int
        Int minute = ((dayMillis % 3600000) / 60000) as Int
        Int second = ((dayMillis % 60000) / 1000) as Int
        Int millisecond = (dayMillis % 1000) as Int
        return new Time(hour, minute, second, millisecond)
    }

    Int year() { return self.civil().year }
    Month month() { return new Civil(self.civil().year, self.civil().month, self.civil().day).monthEnum() }
    Int day() { return self.civil().day }
    Int hour() { return self.time().hour() }
    Int minute() { return self.time().minute() }
    Int second() { return self.time().second() }
    Int millisecond() { return self.time().millisecond() }

    Weekday weekday() {
        Long days = floorDiv(_epochMillis, 86400000)
        Int iso = floorMod(days + 3, 7) as Int + 1
        return weekdayFromIso(iso).value()
    }

    Int dayOfYear() {
        Int result = self.date().day()
        Int index = 1
        while index < number(self.month()) {
            result = result + civilDaysInMonth(self.year(), monthFromNumber(index).value())
            index = index + 1
        }
        return result
    }

    Int weekOfYear() {
        return (self.dayOfYear() - 1) / 7 + 1
    }

    Bool isLeapYear() {
        return civilIsLeap(self.year())
    }

    DateTime add(Duration duration) {
        if duration == null { throw "DateTime.add: null" }
        return new DateTime(_epochMillis + duration.millis())
    }

    DateTime addDays(Int days) {
        return new DateTime(_epochMillis + (days as Long) * 86400000)
    }

    DateTime addHours(Int hours) {
        return new DateTime(_epochMillis + (hours as Long) * 3600000)
    }

    DateTime addMinutes(Int minutes) {
        return new DateTime(_epochMillis + (minutes as Long) * 60000)
    }

    DateTime addSeconds(Int seconds) {
        return new DateTime(_epochMillis + (seconds as Long) * 1000)
    }

    DateTime addMillis(Long milliseconds) {
        return new DateTime(_epochMillis + milliseconds)
    }

    DateTime addMonths(Int months) {
        Date current = self.date()
        Int targetMonth = current.monthNumber() + months
        Int targetYear = current.year() + floorDiv(targetMonth - 1, 12)
        Int normalizedMonth = floorMod(targetMonth - 1, 12) + 1
        Month target = monthFromNumber(normalizedMonth).value()
        Int targetDay = current.day()
        Int maximum = civilDaysInMonth(targetYear, target)
        if targetDay > maximum { targetDay = maximum }
        return DateTime.ofMs(targetYear, target, targetDay, self.hour(), self.minute(), self.second(), self.millisecond())
    }

    DateTime addYears(Int years) {
        return self.addMonths(years * 12)
    }

    DateTime subtract(Duration duration) {
        if duration == null { throw "DateTime.subtract: null" }
        return new DateTime(_epochMillis - duration.millis())
    }

    Bool before(DateTime other) {
        if other == null { throw "DateTime.before: null" }
        return _epochMillis < other._epochMillis
    }

    Bool after(DateTime other) {
        if other == null { throw "DateTime.after: null" }
        return _epochMillis > other._epochMillis
    }

    Int compare(DateTime other) {
        if other == null { throw "DateTime.compare: null" }
        if _epochMillis < other._epochMillis { return -1 }
        if _epochMillis > other._epochMillis { return 1 }
        return 0
    }

    Bool equals(DateTime other) {
        if other == null { return false }
        return _epochMillis == other._epochMillis
    }

    Instant toInstant() { return new Instant(_epochMillis) }
    DateTime toUTC() { return self }
    DateTime toLocal() { return self }

    DateTime startOfDay() {
        Date current = self.date()
        return DateTime.ofMs(current.year(), current.month(), current.day(), 0, 0, 0, 0)
    }

    DateTime endOfDay() {
        Date current = self.date()
        return DateTime.ofMs(current.year(), current.month(), current.day(), 23, 59, 59, 999)
    }

    DateTime startOfMonth() {
        Date current = self.date()
        return DateTime.ofMs(current.year(), current.month(), 1, 0, 0, 0, 0)
    }

    DateTime endOfMonth() {
        Date current = self.date()
        Int last = civilDaysInMonth(current.year(), current.month())
        return DateTime.ofMs(current.year(), current.month(), last, 23, 59, 59, 999)
    }

    String format(DateTimeFormatter formatter) {
        if formatter == null { throw "DateTime.format: null formatter" }
        return formatter.format(self)
    }

    String format(String layout) {
        return DateTimeFormatter.ofPattern(layout).format(self)
    }

    String iso8601() {
        return self.format("yyyy-MM-ddTHH:mm:ss.SSS")
    }

    String rfc3339() {
        return self.format("yyyy-MM-ddTHH:mm:ss") + "Z"
    }

    String toString() {
        return self.iso8601()
    }
}
```

> `Civil` 是 time 包内部历法结构；`floorDiv/floorMod/daysFromCivil/civilFromDays` 是内部历法辅助。`monthFromNumber`、`weekdayFromIso` 是顶层/枚举辅助。
