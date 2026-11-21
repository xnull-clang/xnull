# `DateFormat`

| 项 | 值 |
| --- | --- |
| 类型 | `class DateFormat` |
| 包 | `xdk.i18n` |
| 稳定性 | `preview` |
| 依赖 | `Locale`、`TimeZone`、`DateTime`、`Instant`、`DateTimeFormatter`、`BasicError`、`ErrorKind` |

---

## 1. 定位

locale 日期/时间格式化与解析：locale 模式解析、固定偏移时区换算、数字日期输出。

不做：完整 `DateTimeFormatter` 引擎复制、月份/星期名称、12 小时制 AM/PM、IANA tzdb/DST、日历系统、相对时间。

---

## 2. 设计逻辑

- 字段：locale、pattern、timeZone、核心 `DateTimeFormatter`；不可变。
- 模式只接受核心 `DateTimeFormatter` 支持的令牌：`yyyy`、`MM`、`dd`、`HH`、`mm`、`ss`、`SSS`；`T` 作为 ISO 字面量允许；其他 ASCII 字母报错，其他字符按字面量。
- `format` 不复制令牌替换算法：把 UTC `DateTime` 按 `TimeZone` 偏移平移后，委托 `DateTimeFormatter.format`。
- `parse` 是按模式字段顺序的受限扫描器；它只接受 `format` 能产生的数字模式，不实现核心通用解析引擎。
- `ofStyle` 用 locale 表把 `date`/`time`/`dateTime`/`iso` 解析成具体 pattern；未知 style 返回 `InvalidArgument`。
- 缺失字段用默认值：日期缺省 1970-01-01，时间缺省 00:00:00.000；解析结果按同一时区偏移转回 UTC。
- 时区只用 `xdk.time.TimeZone` 固定偏移；DST/X。
- 没有全局 locale/pattern。

| locale 子集 | `date` 模式 |
| --- | --- |
| `en-US` | `MM/dd/yyyy` |
| 其他 `en-*` | `dd/MM/yyyy` |
| `de`、`ru`、`uk`、`pl` | `dd.MM.yyyy` |
| `fr`、`es`、`it`、`pt` | `dd/MM/yyyy` |
| `nl` | `dd-MM-yyyy` |
| `ja`、`zh` | `yyyy年MM月dd日` |
| `ko` | `yyyy년 MM월 dd일` |
| root | `yyyy-MM-dd` |

`time` 统一为 `HH:mm:ss`；`dateTime` 为日期模式 + 空格 + 时间模式。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_locale` | `Locale` | 格式 locale |
| `_pattern` | `String` | 核心令牌模式 |
| `_timeZone` | `TimeZone` | 展示/解析时区 |
| `_formatter` | `DateTimeFormatter` | 核心格式化器 |

不变量：pattern 非空；只含受支持令牌、`T` 与字面量；timeZone 非 null；不可变。

---

## 4. 生命周期

不可变；构造期校验 pattern 并创建核心 formatter；无 close；可共享；`withPattern`/`withTimeZone` 返回新实例。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DateFormat(Locale locale, String pattern, TimeZone timeZone)` | 三者 | pattern 合法 | null/非法 pattern → panic |
| `DateFormat.ofStyle(Locale locale, String style, TimeZone timeZone)` | 三者 | style 四选一 | 未知 style → `InvalidArgument` |
| `withPattern(String pattern)` | pattern | 合法 | 非法 → panic |
| `withTimeZone(TimeZone timeZone)` | timeZone | 非 null | null → panic |

已知 style：`date`、`time`、`dateTime`、`iso`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `format` | 格式化 DateTime | `DateTime value` | `String` | null → panic |
| `format` | 格式化 Instant | `Instant value` | `String` | null → panic |
| `parse` | 解析文本 | `String text` | `Result<DateTime, Error>` | `InvalidArgument` |
| `ofStyle` | 样式构造 | `Locale, String, TimeZone` | `Result<DateFormat, Error>` | 未知 style |
| `withPattern` | 换模式 | `String pattern` | `DateFormat` | 非法 → panic |
| `withTimeZone` | 换时区 | `TimeZone timeZone` | `DateFormat` | null → panic |
| `locale` | locale | 无 | `Locale` | 无 |
| `pattern` | 模式 | 无 | `String` | 无 |
| `timeZone` | 时区 | 无 | `TimeZone` | 无 |

说明：

- `format(DateTime)` 把 `value.timestamp() + timeZone.offsetAt(value.toInstant())` 作为本地墙钟，再委托核心 formatter。
- `format(Instant)` 先 `toDateTime()`，再走同一路径。
- `parse` 逐段匹配 pattern 与 text；字面量必须完全一致；结束后不接受尾随字符。
- `parse` 的字段范围：月 1–12，日按 `civilDaysInMonth`，时 0–23，分/秒 0–59，毫秒 0–999；非法返回 `InvalidArgument`，不 panic。
- `parse` 构造本地 `DateTime` 后减去 `timeZone.offsetAt(local)`，返回 UTC `DateTime`。
- `ofStyle` 的 locale 表只覆盖数字模式；`en-US` 为 `MM/dd/yyyy`，多数欧洲语言为 `dd/MM/yyyy` 或 `dd.MM.yyyy`，中日韩使用 `yyyy年MM月dd日`/`yyyy년 MM월 dd일`，root 为 `yyyy-MM-dd`。
- `time` 固定 `HH:mm:ss`；12 小时制/AM-PM 属于 X。
- 支持日期/时间令牌和 `T` 字面量；不支持月份名 `MMM`/`MMMM`；这类 pattern 在构造期报错。

---

## 8. 使用的技术

- locale 模式表；
- 核心 `DateTimeFormatter` 令牌替换；
- 固定偏移时区平移；
- 受限顺序解析；
- 字段范围校验；
- Result 错误传播。

---

## 9. 需要的支撑

- 语言：class、String、Int、Long、Bool、Result、List；
- 运行时：`DateTime`、`Instant`、`TimeZone`、`DateTimeFormatter`、`Month`、`civilDaysInMonth`、`monthFromNumber`；
- 接口：`Locale`、`trim`、`isNumeric`、`parseInt`、`startsWith`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Locale`、`TimeZone`、`DateTime`、`Instant`、`DateTimeFormatter`、`Month`、`civilDaysInMonth`、`monthFromNumber`、`BasicError`、`ErrorKind`、`xdk.text` 数字/字符串函数。

---

## 11. 所有权与并发

不可变；引用语义；可跨任务共享；无资源；`format`/`parse` 无内部可变状态。

---

## 12. 示例与反例

正确：`DateFormat.ofStyle(Locale.parse("en-US").value(), "date", TimeZone.utc()).value().format(dt)`。  
正确：`DateFormat.ofStyle(Locale.parse("de-DE").value(), "dateTime", TimeZone.fixed(3600000)).value().format(instant)`。  
正确：`parse("21.11.2026")`（de-DE，`dd.MM.yyyy`）→ UTC `DateTime`。  
反例：期望 `MMMM` 输出月份名；期望 DST 自动调整；用 `DateTime` 直接当本地时间；期望 12 小时制；期望解析尾部多余字符；期望 `DateFormat` 重新实现核心 `yyyy/MM/dd` 引擎。

---

## 13. 测试/场景义务

每个令牌；字面量；CJK 字面量；pattern 校验（未知字母、`MMM`、空、`yyyyy`）；date/time/dateTime/iso 四 style；en-US/de-DE/fr-FR/ja-JP/zh-CN/ko-KR/root 模式；UTC/正偏移/负偏移；DateTime/Instant；parse 往返；缺字段默认值；月/日/时/分/秒/毫秒边界；闰年；尾随字符；字面量不匹配；withPattern/withTimeZone；并发只读。

---

## 14. XNull 伪代码

```xnull
class DateFormat {
    final Locale _locale
    final String _pattern
    final TimeZone _timeZone
    final DateTimeFormatter _formatter

    DateFormat(Locale locale, String pattern, TimeZone timeZone) {
        if locale == null || pattern == null || timeZone == null {
            throw "DateFormat: null argument"
        }
        if pattern == "" {
            throw "DateFormat: empty pattern"
        }
        DateFormat.validatePattern(pattern)
        _locale = locale
        _pattern = pattern
        _timeZone = timeZone
        _formatter = DateTimeFormatter.ofPattern(pattern)
    }

    static Result<DateFormat, Error> ofStyle(Locale locale, String style, TimeZone timeZone) {
        if locale == null || style == null || timeZone == null {
            throw "DateFormat.ofStyle: null argument"
        }
        String pattern = ""
        if style == "date" {
            pattern = DateFormat.datePattern(locale)
        } else if style == "time" {
            pattern = DateFormat.timePattern(locale)
        } else if style == "dateTime" {
            pattern = DateFormat.datePattern(locale) + " " + DateFormat.timePattern(locale)
        } else if style == "iso" {
            pattern = "yyyy-MM-ddTHH:mm:ss.SSS"
        } else {
            return Err(new BasicError(ErrorKind.InvalidArgument, "unknown date style: " + style))
        }
        return Ok(new DateFormat(locale, pattern, timeZone))
    }

    Locale locale() { return _locale }
    String pattern() { return _pattern }
    TimeZone timeZone() { return _timeZone }

    String format(DateTime value) {
        if value == null {
            throw "DateFormat.format: null value"
        }
        Long offset = _timeZone.offsetAt(value.toInstant()) as Long
        DateTime shifted = DateTime.fromTimestamp(value.timestamp() + offset)
        return _formatter.format(shifted)
    }

    String format(Instant value) {
        if value == null {
            throw "DateFormat.format: null instant"
        }
        return self.format(value.toDateTime())
    }

    Result<DateTime, Error> parse(String text) {
        if text == null {
            throw "DateFormat.parse: null text"
        }
        Int patternIndex = 0
        Int textIndex = 0
        Int year = 1970
        Int month = 1
        Int day = 1
        Int hour = 0
        Int minute = 0
        Int second = 0
        Int millisecond = 0
        while patternIndex < _pattern.length() {
            if DateFormat.tokenAt(_pattern, patternIndex, "yyyy") {
                Result<Int, Error> parsed = self.readField(text, textIndex, 4, "year")
                if parsed.isErr() { return Err(parsed.error()) }
                year = parsed.value()
                patternIndex = patternIndex + 4
                textIndex = textIndex + 4
            } else if DateFormat.tokenAt(_pattern, patternIndex, "MM") {
                Result<Int, Error> parsed = self.readField(text, textIndex, 2, "month")
                if parsed.isErr() { return Err(parsed.error()) }
                month = parsed.value()
                patternIndex = patternIndex + 2
                textIndex = textIndex + 2
            } else if DateFormat.tokenAt(_pattern, patternIndex, "dd") {
                Result<Int, Error> parsed = self.readField(text, textIndex, 2, "day")
                if parsed.isErr() { return Err(parsed.error()) }
                day = parsed.value()
                patternIndex = patternIndex + 2
                textIndex = textIndex + 2
            } else if DateFormat.tokenAt(_pattern, patternIndex, "HH") {
                Result<Int, Error> parsed = self.readField(text, textIndex, 2, "hour")
                if parsed.isErr() { return Err(parsed.error()) }
                hour = parsed.value()
                patternIndex = patternIndex + 2
                textIndex = textIndex + 2
            } else if DateFormat.tokenAt(_pattern, patternIndex, "mm") {
                Result<Int, Error> parsed = self.readField(text, textIndex, 2, "minute")
                if parsed.isErr() { return Err(parsed.error()) }
                minute = parsed.value()
                patternIndex = patternIndex + 2
                textIndex = textIndex + 2
            } else if DateFormat.tokenAt(_pattern, patternIndex, "ss") {
                Result<Int, Error> parsed = self.readField(text, textIndex, 2, "second")
                if parsed.isErr() { return Err(parsed.error()) }
                second = parsed.value()
                patternIndex = patternIndex + 2
                textIndex = textIndex + 2
            } else if DateFormat.tokenAt(_pattern, patternIndex, "SSS") {
                Result<Int, Error> parsed = self.readField(text, textIndex, 3, "millisecond")
                if parsed.isErr() { return Err(parsed.error()) }
                millisecond = parsed.value()
                patternIndex = patternIndex + 3
                textIndex = textIndex + 3
            } else {
                if textIndex >= text.length() {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "missing date literal"))
                }
                if text.charAt(textIndex) != _pattern.charAt(patternIndex) {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "date literal mismatch"))
                }
                patternIndex = patternIndex + 1
                textIndex = textIndex + 1
            }
        }
        if textIndex != text.length() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "trailing date text"))
        }
        if month < 1 || month > 12 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid month"))
        }
        Result<Month, Error> monthValue = monthFromNumber(month)
        if monthValue.isErr() {
            return Err(monthValue.error())
        }
        if day < 1 || day > civilDaysInMonth(year, monthValue.value()) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid day"))
        }
        if hour < 0 || hour > 23 || minute < 0 || minute > 59
            || second < 0 || second > 59
            || millisecond < 0 || millisecond > 999 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid time"))
        }
        DateTime local = DateTime.ofMs(
            year, monthValue.value(), day, hour, minute, second, millisecond)
        Long offset = _timeZone.offsetAt(local.toInstant()) as Long
        return Ok(DateTime.fromTimestamp(local.timestamp() - offset))
    }

    DateFormat withPattern(String pattern) {
        return new DateFormat(_locale, pattern, _timeZone)
    }

    DateFormat withTimeZone(TimeZone timeZone) {
        return new DateFormat(_locale, _pattern, timeZone)
    }

    private Result<Int, Error> readField(String text, Int index, Int count, String field) {
        if index + count > text.length() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "missing date field: " + field))
        }
        String part = text.substring(index, count)
        if !isNumeric(part) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid date field: " + field))
        }
        Result<Int, Error> parsed = parseInt(part)
        if parsed.isErr() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid date field: " + field))
        }
        return parsed
    }

    private static void validatePattern(String pattern) {
        Int index = 0
        while index < pattern.length() {
            if DateFormat.tokenAt(pattern, index, "yyyy") {
                index = index + 4
            } else if DateFormat.tokenAt(pattern, index, "MM") {
                index = index + 2
            } else if DateFormat.tokenAt(pattern, index, "dd") {
                index = index + 2
            } else if DateFormat.tokenAt(pattern, index, "HH") {
                index = index + 2
            } else if DateFormat.tokenAt(pattern, index, "mm") {
                index = index + 2
            } else if DateFormat.tokenAt(pattern, index, "ss") {
                index = index + 2
            } else if DateFormat.tokenAt(pattern, index, "SSS") {
                index = index + 3
            } else if pattern.charAt(index) == 'T' {
                index = index + 1
            } else {
                Char character = pattern.charAt(index)
                if (character >= 'A' && character <= 'Z')
                    || (character >= 'a' && character <= 'z') {
                    throw "DateFormat: unsupported pattern token"
                }
                index = index + 1
            }
        }
    }

    private static Bool tokenAt(String pattern, Int index, String token) {
        if index + token.length() > pattern.length() {
            return false
        }
        return pattern.substring(index, token.length()) == token
    }

    private static String datePattern(Locale locale) {
        String language = locale.language()
        String country = locale.country()
        if locale.isRoot() {
            return "yyyy-MM-dd"
        }
        if language == "en" && country == "US" {
            return "MM/dd/yyyy"
        }
        if language == "en" {
            return "dd/MM/yyyy"
        }
        if language == "ja" || language == "zh" {
            return "yyyy年MM月dd日"
        }
        if language == "ko" {
            return "yyyy년 MM월 dd일"
        }
        if language == "de" || language == "ru" || language == "uk" || language == "pl" {
            return "dd.MM.yyyy"
        }
        if language == "nl" {
            return "dd-MM-yyyy"
        }
        return "dd/MM/yyyy"
    }

    private static String timePattern(Locale locale) {
        return "HH:mm:ss"
    }
}
```
