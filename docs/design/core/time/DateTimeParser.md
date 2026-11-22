# `DateTimeParser`

| 项 | 值 |
| --- | --- |
| 类型 | `class DateTimeParser` |
| 包 | `xdk.time` |
| 稳定性 | `preview` |
| 依赖 | `DateTime`、`Month`、`errors` |

---

## 1. 定位

日期时间解析： 支持 ISO 8601（`yyyy-MM-ddTHH:mm:ss[.SSS]`，可选 `Z`）。

不做：任意 pattern 解析（由顶层 `parseDateTimeLayout` 提供）、locale、时区规则、相对时间。

---

## 2. 设计逻辑

- 不可变；字段 `_pattern` 固定为 ISO。
- `iso8601()` 返回标准解析器。
- `parse` 失败返回 `InvalidArgument`，不 panic。
- 只接受 UTC/`Z`；其他偏移 X。
- 秒/毫秒可选；长度/分隔符严格。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_pattern` | `String` | 模式标识 |

不变量：不可变； pattern = ISO。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DateTimeParser.iso8601()` | 无 | ISO | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析 DateTime | `String text` | `Result<DateTime, Error>` | `InvalidArgument` |
| `parseDate` | 解析 Date | `String text` | `Result<Date, Error>` | `InvalidArgument` |
| `parseTime` | 解析 Time | `String text` | `Result<Time, Error>` | `InvalidArgument` |
| `pattern` | 模式 | 无 | `String` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 固定位置解析；
- 十进制定长；
- 月枚举转换；
- 严格分隔符。

---

## 9. 需要的支撑

- 语言：class、String、Int、Result；
- 运行时：字符串/整数解析；
- 接口：`DateTime`、`Date`、`Time`、`Month`、`monthFromNumber`、`parseInt`、`BasicError`。

---

## 10. 依赖的特性/接口/类

`DateTime`、`Date`、`Time`、`Month`、`monthFromNumber`、`parseInt`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`DateTimeParser.iso8601().parse("2026-11-21T12:00:00Z")`；任意 layout 用顶层 `parseDateTimeLayout(text, layout)`。

反例：期望任意 pattern；接受非 `Z` 偏移；非法日期静默归一。

---

## 13. 测试/场景义务

完整/无秒/有毫秒/`Z`；非法长度/分隔符/字段；闰年；超范围；parseDate/parseTime。

---

## 14. XNull 伪代码

```xnull
class DateTimeParser {
    final String _pattern

    DateTimeParser(String pattern) {
        _pattern = pattern
    }

    static DateTimeParser iso8601() {
        return new DateTimeParser("iso8601")
    }

    Result<DateTime, Error> parse(String text) {
        if text == null || text.length() < 19 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid datetime"))
        }
        if text.substring(4, 1) != "-" || text.substring(7, 1) != "-"
            || text.substring(10, 1) != "T" || text.substring(13, 1) != ":"
            || text.substring(16, 1) != ":" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid datetime separator"))
        }
        Result<Int, Error> year = parseInt(text.substring(0, 4))
        Result<Int, Error> monthValue = parseInt(text.substring(5, 2))
        Result<Int, Error> day = parseInt(text.substring(8, 2))
        Result<Int, Error> hour = parseInt(text.substring(11, 2))
        Result<Int, Error> minute = parseInt(text.substring(14, 2))
        Result<Int, Error> second = parseInt(text.substring(17, 2))
        if year.isErr() || monthValue.isErr() || day.isErr()
            || hour.isErr() || minute.isErr() || second.isErr() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid datetime field"))
        }
        Result<Month, Error> month = monthFromNumber(monthValue.value())
        if month.isErr() {
            return Err(month.error())
        }
        Int millisecond = 0
        Int position = 19
        if position < text.length() && text.substring(position, 1) == "." {
            if position + 4 > text.length() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "invalid milliseconds"))
            }
            Result<Int, Error> parsedMillis = parseInt(text.substring(position + 1, 3))
            if parsedMillis.isErr() {
                return Err(parsedMillis.error())
            }
            millisecond = parsedMillis.value()
            position = position + 4
        }
        if position < text.length() {
            if text.substring(position, 1) != "Z" || position + 1 != text.length() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "unsupported timezone"))
            }
        }
        return Ok(DateTime.ofMs(
            year.value(),
            month.value(),
            day.value(),
            hour.value(),
            minute.value(),
            second.value(),
            millisecond
        ))
    }

    Result<Date, Error> parseDate(String text) {
        if text == null || text.length() != 10 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid date"))
        }
        Result<Int, Error> year = parseInt(text.substring(0, 4))
        Result<Int, Error> monthValue = parseInt(text.substring(5, 2))
        Result<Int, Error> day = parseInt(text.substring(8, 2))
        if year.isErr() || monthValue.isErr() || day.isErr() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid date field"))
        }
        Result<Month, Error> month = monthFromNumber(monthValue.value())
        if month.isErr() {
            return Err(month.error())
        }
        return Ok(new Date(year.value(), month.value(), day.value()))
    }

    Result<Time, Error> parseTime(String text) {
        if text == null || text.length() < 8 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid time"))
        }
        Result<Int, Error> hour = parseInt(text.substring(0, 2))
        Result<Int, Error> minute = parseInt(text.substring(3, 2))
        Result<Int, Error> second = parseInt(text.substring(6, 2))
        if hour.isErr() || minute.isErr() || second.isErr() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid time field"))
        }
        Int millisecond = 0
        if text.length() > 8 {
            if text.length() != 12 || text.substring(8, 1) != "." {
                return Err(new BasicError(ErrorKind.InvalidArgument, "invalid milliseconds"))
            }
            Result<Int, Error> parsedMillis = parseInt(text.substring(9, 3))
            if parsedMillis.isErr() {
                return Err(parsedMillis.error())
            }
            millisecond = parsedMillis.value()
        }
        return Ok(new Time(hour.value(), minute.value(), second.value(), millisecond))
    }

    String pattern() { return _pattern }
    String toString() { return "DateTimeParser(" + _pattern + ")" }
}
```
