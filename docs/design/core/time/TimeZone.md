# `TimeZone`

| 项 | 值 |
| --- | --- |
| 类型 | `class TimeZone` |
| 包 | `xdk.time` |
| 稳定性 | `preview` |
| 依赖 | `Instant` |

---

## 1. 定位

UTC/固定偏移时区；用于偏移展示/简单本地化。

不做：IANA 规则、DST 数据库、历史偏移（X）。

---

## 2. 设计逻辑

- 字段 `_id: String`、`_offsetMillis: Int`。
- `utc()` 偏移 0；`fixed(offset)` 固定偏移。
- `offsetAt(instant)`  返回固定偏移；X 按规则。
- 不可变；值语义；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_id` | `String` | 时区 ID |
| `_offsetMillis` | `Int` | 偏移毫秒 |

不变量：id 非空；offset 合理范围（±18h）。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TimeZone.utc()` | 无 | 0 | 无 |
| `TimeZone.fixed(Int offsetMillis)` | offsetMillis | ±64800000 | 越界 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | ID | 无 | `String` | 无 |
| `offsetMillis` | 偏移 | 无 | `Int` | 无 |
| `offsetAt` | 指定时刻偏移 | `Instant instant` | `Int` | null → panic |
| `abbreviation` | 缩写 | 无 | `String` | 无 |
| `equals` | 值相等 | `TimeZone other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 固定偏移；
- 时区 ID；
- 偏移格式化。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool；
- 运行时：无；
- 接口：`Instant`。

---

## 10. 依赖的特性/接口/类

`Instant`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`TimeZone.utc()`；`fixed(8*3600000)`。  
反例：期望 DST；用 TimeZone 替代完整 tzdb；偏移越界。

---

## 13. 测试/场景义务

UTC；固定正/负偏移；offsetAt；equals；toString；越界。

---

## 14. XNull 伪代码

```xnull
class TimeZone {
    final String _id
    final Int _offsetMillis

    TimeZone(String zoneId, Int offsetMillis) {
        if zoneId == "" {
            throw "TimeZone: empty id"
        }
        if offsetMillis < -64800000 || offsetMillis > 64800000 {
            throw "TimeZone: offset out of range"
        }
        _id = zoneId
        _offsetMillis = offsetMillis
    }

    static TimeZone utc() {
        return new TimeZone("UTC", 0)
    }

    static TimeZone fixed(Int offsetMillis) {
        String sign = "+"
        Int absolute = offsetMillis
        if absolute < 0 {
            sign = "-"
            absolute = 0 - absolute
        }
        Int hours = absolute / 3600000
        Int minutes = (absolute % 3600000) / 60000
        String id = "UTC" + sign + padLeftNum(str(hours), 2) + ":" + padLeftNum(str(minutes), 2)
        return new TimeZone(id, offsetMillis)
    }

    String id() { return _id }
    Int offsetMillis() { return _offsetMillis }

    Int offsetAt(Instant instant) {
        if instant == null { throw "TimeZone.offsetAt: null" }
        return _offsetMillis
    }

    String abbreviation() {
        if _offsetMillis == 0 { return "UTC" }
        return _id
    }

    Bool equals(TimeZone other) {
        if other == null { return false }
        return _id == other._id && _offsetMillis == other._offsetMillis
    }

    String toString() {
        return _id
    }
}
```
