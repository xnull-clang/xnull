# `DateTimeFormatter`

| 项 | 值 |
| --- | --- |
| 类型 | `class DateTimeFormatter` |
| 包 | `xdk.time` |
| 稳定性 | `preview` |
| 依赖 | `DateTime`、`Date`、`Time`、`Month`、`Weekday` |

---

## 1. 定位

日期时间格式化：有限布局令牌；用于日志/显示/ISO。

不做：完整 strftime、locale 名称、时区规则、解析。

---

## 2. 设计逻辑

- 不可变；字段 `_pattern`。
- 令牌：`yyyy`、`MM`、`dd`、`HH`、`mm`、`ss`、`SSS`；其他字符原样。
- 所有替换值为纯数字，避免二次替换。
-  只 UTC；不处理时区名/偏移。
- 非法 pattern/null → panic（构造时）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_pattern` | `String` | 布局 |

不变量：pattern 非空；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DateTimeFormatter.ofPattern(String pattern)` | pattern | 非空 | 空 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `format` | 格式化 DateTime | `DateTime value` | `String` | null → panic |
| `formatDate` | 格式化 Date | `Date value` | `String` | null → panic |
| `formatTime` | 格式化 Time | `Time value` | `String` | null → panic |
| `pattern` | 布局 | 无 | `String` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 字符串替换；
- 数字补零；
- 固定令牌；
- 不可变。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool；
- 运行时：字符串替换；
- 接口：`DateTime`、`Date`、`Time`、`Month`、`Weekday`、`padLeftNum`、`number`。

---

## 10. 依赖的特性/接口/类

`DateTime`、`Date`、`Time`、`Month`、`Weekday`、`padLeftNum`、`number`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").format(dt)`。  
反例：期望 locale 月份名；用 pattern 做解析；用格式化做时区转换。

---

## 13. 测试/场景义务

每个令牌；字面字符；`yyyy` 4 位；`SSS` 3 位；Date/Time；空 pattern；null。

---

## 14. XNull 伪代码

```xnull
class DateTimeFormatter {
    final String _pattern

    DateTimeFormatter(String pattern) {
        if pattern == "" {
            throw "DateTimeFormatter: empty pattern"
        }
        _pattern = pattern
    }

    static DateTimeFormatter ofPattern(String pattern) {
        return new DateTimeFormatter(pattern)
    }

    String format(DateTime value) {
        if value == null { throw "DateTimeFormatter.format: null" }
        String result = _pattern
        result = replace(result, "yyyy", padLeftNum(str(value.year()), 4))
        result = replace(result, "MM", padLeftNum(str(number(value.month())), 2))
        result = replace(result, "dd", padLeftNum(str(value.day()), 2))
        result = replace(result, "HH", padLeftNum(str(value.hour()), 2))
        result = replace(result, "mm", padLeftNum(str(value.minute()), 2))
        result = replace(result, "ss", padLeftNum(str(value.second()), 2))
        result = replace(result, "SSS", padLeftNum(str(value.millisecond()), 3))
        return result
    }

    String formatDate(Date value) {
        if value == null { throw "DateTimeFormatter.formatDate: null" }
        String result = _pattern
        result = replace(result, "yyyy", padLeftNum(str(value.year()), 4))
        result = replace(result, "MM", padLeftNum(str(value.monthNumber()), 2))
        result = replace(result, "dd", padLeftNum(str(value.day()), 2))
        return result
    }

    String formatTime(Time value) {
        if value == null { throw "DateTimeFormatter.formatTime: null" }
        String result = _pattern
        result = replace(result, "HH", padLeftNum(str(value.hour()), 2))
        result = replace(result, "mm", padLeftNum(str(value.minute()), 2))
        result = replace(result, "ss", padLeftNum(str(value.second()), 2))
        result = replace(result, "SSS", padLeftNum(str(value.millisecond()), 3))
        return result
    }

    String pattern() { return _pattern }
    String toString() { return "DateTimeFormatter(" + _pattern + ")" }
}
```
