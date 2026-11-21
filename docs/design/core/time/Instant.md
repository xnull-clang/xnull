# `Instant`

| 项 | 值 |
| --- | --- |
| 类型 | `class Instant` |
| 包 | `xdk.time` |
| 稳定性 | `stable` |
| 依赖 | `Duration`、`DateTime` |

---

## 1. 定位

epoch 毫秒时间点；用于时间戳/比较/与 DateTime 转换。

不做：时区/日历字段、纳秒精度、闰秒。

---

## 2. 设计逻辑

- 唯一字段 `_epochMillis: Long`；UTC epoch。
- 不可变；`plus/minus` 返回新实例。
- `epochSeconds` 截断除法。
- `toDateTime` 转为 UTC DateTime。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_epochMillis` | `Long` | UNIX epoch 毫秒 |

不变量：值 = epochMillis；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Instant.ofEpochMillis(Long)` | epochMillis | 任意 Long | 无 |
| `Instant.ofEpochSeconds(Long)` | seconds | 乘法不溢出 | 溢出 → panic |
| `Instant.now()` | 无 | 墙钟 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `epochMillis` | epoch 毫秒 | 无 | `Long` | 无 |
| `epochSeconds` | epoch 秒 | 无 | `Long` | 无 |
| `plus` | 加时长 | `Duration duration` | `Instant` | null → panic |
| `minus` | 减时长 | `Duration duration` | `Instant` | null → panic |
| `isBefore` | 是否早于 | `Instant other` | `Bool` | null → panic |
| `isAfter` | 是否晚于 | `Instant other` | `Bool` | null → panic |
| `compare` | 比较 | `Instant other` | `Int` | null → panic |
| `toDateTime` | 转 UTC | 无 | `DateTime` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `Instant` | 无 |

---

## 8. 使用的技术

- epoch 毫秒；
- Long 算术；
- 截断秒；
- 文本。

---

## 9. 需要的支撑

- 语言：class、Long、Int、Bool、String；
- 运行时：`nowWall`；
- 接口：`Duration`、`DateTime`。

---

## 10. 依赖的特性/接口/类

`Duration`、`DateTime`、`runtime.nowWall`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`Instant.ofEpochMillis(0).toDateTime().iso8601()` → 1970-01-01T00:00:00.000。  
反例：用 Instant 做日历字段；用 epochSeconds 做毫秒精度；把 Instant 当本地时间。

---

## 13. 测试/场景义务

epoch 正/负/0；plus/minus；比较；toDateTime；now；toString。

---

## 14. XNull 伪代码

```xnull
class Instant {
    final Long _epochMillis

    Instant(Long epochMillis) {
        _epochMillis = epochMillis
    }

    static Instant ofEpochMillis(Long epochMillis) {
        return new Instant(epochMillis)
    }

    static Instant ofEpochSeconds(Long seconds) {
        return new Instant(checkedMultiply(seconds, 1000))
    }

    static Instant now() {
        return new Instant(nowWall())
    }

    Long epochMillis() { return _epochMillis }
    Long epochSeconds() { return _epochMillis / 1000 }

    Instant plus(Duration duration) {
        if duration == null { throw "Instant.plus: null" }
        return new Instant(_epochMillis + duration.millis())
    }

    Instant minus(Duration duration) {
        if duration == null { throw "Instant.minus: null" }
        return new Instant(_epochMillis - duration.millis())
    }

    Bool isBefore(Instant other) {
        if other == null { throw "Instant.isBefore: null" }
        return _epochMillis < other._epochMillis
    }

    Bool isAfter(Instant other) {
        if other == null { throw "Instant.isAfter: null" }
        return _epochMillis > other._epochMillis
    }

    Int compare(Instant other) {
        if other == null { throw "Instant.compare: null" }
        if _epochMillis < other._epochMillis { return -1 }
        if _epochMillis > other._epochMillis { return 1 }
        return 0
    }

    DateTime toDateTime() {
        return new DateTime(_epochMillis)
    }

    String toString() {
        return "instant(" + str(_epochMillis) + "ms)"
    }

    Instant copy() {
        return new Instant(_epochMillis)
    }
}

Long checkedMultiply(Long left, Long right) {
    Int128 product = (left as Int128) * (right as Int128)
    if product > 9223372036854775807 || product < -9223372036854775808 {
        throw "Instant: overflow"
    }
    return product as Long
}
```
