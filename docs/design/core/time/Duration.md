# `Duration`

| 项 | 值 |
| --- | --- |
| 类型 | `struct Duration` |
| 包 | `xdk.time` |
| 稳定性 | `stable` |
| 依赖 | `TimeUnit`、`errors` |

---

> 类型选择：`struct Duration`；唯一字段是 Long，全部为值类型，使用原生值语义，不需要 `@Value`。

## 1. 定位

毫秒精度时长；可正可负；支持加减/乘除/比较/单位换算。

不做：纳秒精度、日历月/年、可取消休眠。

---

## 2. 设计逻辑

- 唯一字段 `_millis: Long`；精度固定毫秒。
- 不可变；`plus/minus` 返回新实例。
- 溢出按 `Long` 回绕？不：构造/运算检查，溢出 panic 或 Result？本设计用 `Long` 回绕并文档化？更好：`plus/minus` 返回 `Result`? 但 API 简单性。现有文档说“溢出按 Long 回绕，调用方负责范围”。保留该决策，文档明确。
- `seconds/minutes/hours/days` 截断除法。
- `nanos` 是 `millis * 1_000_000`，可能溢出；文档。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_millis` | `Long` | 毫秒数 |

不变量：值 = `_millis`；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Duration.ofMillis(Long)` | milliseconds | 任意 | 无 |
| `Duration.ofSeconds(Long)` | seconds | 乘法不溢出 | 溢出 → panic |
| `Duration.ofMinutes(Long)` | minutes | 同上 | 溢出 → panic |
| `Duration.ofHours(Long)` | hours | 同上 | 溢出 → panic |
| `Duration.ofDays(Long)` | days | 同上 | 溢出 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `millis` | 毫秒 | 无 | `Long` | 无 |
| `seconds` | 秒（截断） | 无 | `Long` | 无 |
| `minutes` | 分（截断） | 无 | `Long` | 无 |
| `hours` | 时（截断） | 无 | `Long` | 无 |
| `days` | 天（截断） | 无 | `Long` | 无 |
| `nanos` | 纳秒（可能溢出） | 无 | `Long` | 溢出 → panic |
| `plus` | 加 | `Duration other` | `Duration` | null → panic；Long 回绕 |
| `minus` | 减 | `Duration other` | `Duration` | null → panic；Long 回绕 |
| `multipliedBy` | 乘 | `Long factor` | `Duration` | 溢出 → panic |
| `dividedBy` | 除 | `Long divisor` | `Duration` | 0 → panic |
| `negated` | 取负 | 无 | `Duration` | MIN 回绕 |
| `abs` | 绝对值 | 无 | `Duration` | MIN 回绕 |
| `compare` | 比较 | `Duration other` | `Int` | null → panic |
| `isZero` | 是否 0 | 无 | `Bool` | 无 |
| `isNegative` | 是否负 | 无 | `Bool` | 无 |
| `toMillis` | 毫秒 | 无 | `Long` | 无 |
| `toSeconds` | 秒 | 无 | `Long` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `Duration` | 无 |

---

## 8. 使用的技术

- 毫秒基准；
- Long 算术；
- 截断除法；
- 文本格式化。

---

## 9. 需要的支撑

- 语言：struct、Long、Int、Bool、String；
- 运行时：整数算术；
- 接口：`TimeUnit`、`BasicError`。

---

## 10. 依赖的特性/接口/类

`TimeUnit`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`Duration.ofSeconds(2).plus(Duration.ofMillis(500))` → 2500ms。  
反例：用 `nanos` 做精确时长（溢出）；用 Duration 表示日历月；依赖回绕做安全计算。

---

## 13. 测试/场景义务

正/负/零；单位换算；plus/minus；乘除；比较；溢出；toString。

---

## 14. XNull 伪代码

```xnull
struct Duration {
    final Long _millis

    Duration(Long milliseconds) {
        _millis = milliseconds
    }

    static Duration ofMillis(Long milliseconds) {
        return new Duration(milliseconds)
    }

    static Duration ofSeconds(Long seconds) {
        return new Duration(checkedMultiply(seconds, 1000))
    }

    static Duration ofMinutes(Long minutes) {
        return new Duration(checkedMultiply(minutes, 60000))
    }

    static Duration ofHours(Long hours) {
        return new Duration(checkedMultiply(hours, 3600000))
    }

    static Duration ofDays(Long days) {
        return new Duration(checkedMultiply(days, 86400000))
    }

    Long millis() { return _millis }
    Long seconds() { return _millis / 1000 }
    Long minutes() { return _millis / 60000 }
    Long hours() { return _millis / 3600000 }
    Long days() { return _millis / 86400000 }
    Long nanos() { return checkedMultiply(_millis, 1000000) }

    Duration plus(Duration other) {
        if other == null { throw "Duration.plus: null" }
        return new Duration(_millis + other._millis)
    }

    Duration minus(Duration other) {
        if other == null { throw "Duration.minus: null" }
        return new Duration(_millis - other._millis)
    }

    Duration multipliedBy(Long factor) {
        return new Duration(checkedMultiply(_millis, factor))
    }

    Duration dividedBy(Long divisor) {
        if divisor == 0 { throw "Duration.dividedBy: zero" }
        return new Duration(_millis / divisor)
    }

    Duration negated() {
        return new Duration(0 - _millis)
    }

    Duration abs() {
        if _millis < 0 {
            return self.negated()
        }
        return new Duration(_millis)
    }

    Int compare(Duration other) {
        if other == null { throw "Duration.compare: null" }
        if _millis < other._millis { return -1 }
        if _millis > other._millis { return 1 }
        return 0
    }

    Bool isZero() { return _millis == 0 }
    Bool isNegative() { return _millis < 0 }
    Long toMillis() { return _millis }
    Long toSeconds() { return _millis / 1000 }

    String toString() {
        return str(_millis) + "ms"
    }

    Duration copy() {
        return new Duration(_millis)
    }
}

Long checkedMultiply(Long left, Long right) {
    Int128 product = (left as Int128) * (right as Int128)
    if product > 9223372036854775807 || product < -9223372036854775808 {
        throw "Duration: overflow"
    }
    return product as Long
}
```
