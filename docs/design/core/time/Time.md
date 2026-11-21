# `Time`

| 项 | 值 |
| --- | --- |
| 类型 | `class Time` |
| 包 | `xdk.time` |
| 稳定性 | `stable` |
| 依赖 | `Duration` |

---

## 1. 定位

一天内的时分秒毫秒值对象；用于显示/日期时间拆分。

不做：时区、日期、闰秒、24 小时制以外的格式。

---

## 2. 设计逻辑

- 字段 `_hour`、`_minute`、`_second`、`_millisecond`。
- 不可变；值语义。
- `plus/minus` 以 24 小时为周期回绕；`Duration` 可正可负。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_hour` | `Int` | 0..23 |
| `_minute` | `Int` | 0..59 |
| `_second` | `Int` | 0..59 |
| `_millisecond` | `Int` | 0..999 |

不变量：字段范围合法；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Time(Int hour, Int minute, Int second, Int millisecond)` | 四个字段 | 各自范围 | 越界 → panic |
| `Time.of(...)` | 同上 | 同上 | 越界 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `hour` | 时 | 无 | `Int` | 无 |
| `minute` | 分 | 无 | `Int` | 无 |
| `second` | 秒 | 无 | `Int` | 无 |
| `millisecond` | 毫秒 | 无 | `Int` | 无 |
| `plus` | 加时长（回绕） | `Duration duration` | `Time` | null → panic |
| `minus` | 减时长（回绕） | `Duration duration` | `Time` | null → panic |
| `compare` | 比较 | `Time other` | `Int` | null → panic |
| `equals` | 值相等 | `Time other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 日内毫秒；
- 24 小时回绕；
- floorMod；
- 文本填充。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、String；
- 运行时：整数运算；
- 接口：`Duration`、`floorMod`。

---

## 10. 依赖的特性/接口/类

`Duration`、`floorMod`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`Time.of(23,59,59,999).plus(Duration.ofMillis(1))` → 00:00:00.000。  
反例：期望 Time 携带日期；用 Time 做时区转换；越界 24:00。

---

## 13. 测试/场景义务

边界 00:00:00.000/23:59:59.999；plus/minus 回绕；compare/equals；toString；非法字段。

---

## 14. XNull 伪代码

```xnull
class Time {
    final Int _hour
    final Int _minute
    final Int _second
    final Int _millisecond

    Time(Int hour, Int minute, Int second, Int millisecond) {
        if hour < 0 || hour > 23 || minute < 0 || minute > 59
            || second < 0 || second > 59 || millisecond < 0 || millisecond > 999 {
            throw "Time: invalid field"
        }
        _hour = hour
        _minute = minute
        _second = second
        _millisecond = millisecond
    }

    static Time of(Int hour, Int minute, Int second, Int millisecond) {
        return new Time(hour, minute, second, millisecond)
    }

    Int hour() { return _hour }
    Int minute() { return _minute }
    Int second() { return _second }
    Int millisecond() { return _millisecond }

    Long totalMillis() {
        return _hour * 3600000 + _minute * 60000 + _second * 1000 + _millisecond
    }

    Time plus(Duration duration) {
        if duration == null { throw "Time.plus: null" }
        Long total = floorMod(self.totalMillis() + duration.millis(), 86400000)
        Int hour = (total / 3600000) as Int
        Int minute = ((total % 3600000) / 60000) as Int
        Int second = ((total % 60000) / 1000) as Int
        Int millisecond = (total % 1000) as Int
        return new Time(hour, minute, second, millisecond)
    }

    Time minus(Duration duration) {
        if duration == null { throw "Time.minus: null" }
        return self.plus(new Duration(0 - duration.millis()))
    }

    Int compare(Time other) {
        if other == null { throw "Time.compare: null" }
        if self.totalMillis() < other.totalMillis() { return -1 }
        if self.totalMillis() > other.totalMillis() { return 1 }
        return 0
    }

    Bool equals(Time other) {
        if other == null { return false }
        return self.totalMillis() == other.totalMillis()
    }

    String toString() {
        return padLeftNum(str(_hour), 2) + ":" + padLeftNum(str(_minute), 2) + ":"
            + padLeftNum(str(_second), 2) + "." + padLeftNum(str(_millisecond), 3)
    }
}
```
