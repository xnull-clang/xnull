# `HistogramBucket`

| 项 | 值 |
| --- | --- |
| 类型 | `class HistogramBucket` |
| 包 | `xdk.stats` |
| 稳定性 | `preview` |
| 依赖 | `xdk.math` |

---

## 1. 定位

直方图桶快照：下界、上界、计数；边界可为无界。

不做：累计计数、分位计算、可变更新、桶合并。

---

## 2. 设计逻辑

- 不可变值对象；`lower == null` 表示负无穷，`upper == null` 表示正无穷。
- 下界/上界同时为 null 表示单一无界桶。
- 计数非负；`contains` 只做区间判断，不修改。
- NaN 不属于任何桶；`contains(NaN)` 返回 false。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_lower` | `Double?` | 下界；null = -∞ |
| `_upper` | `Double?` | 上界；null = +∞ |
| `_count` | `Long` | 桶内计数 |

不变量：count ≥0；若上下界都存在，则 lower < upper；边界不含 NaN。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HistogramBucket(Double? lower, Double? upper, Long count)` | 边界/计数 | 见不变量 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `lower` | 下界/无 | 无 | `Double?` | 无 |
| `upper` | 上界/无 | 无 | `Double?` | 无 |
| `count` | 计数 | 无 | `Long` | 无 |
| `contains` | 是否落入 | `Double value` | `Bool` | 无 |
| `toString` | 摘要 | 无 | `String` | 无 |

说明：

- 桶区间按 `(lower, upper]` 语义；下界无界时包含所有小于等于 upper 的值。
- `contains` 对 NaN 返回 false。

---

## 8. 使用的技术

- 不可变值对象；
- 可空边界表示无界；
- 区间判断。

---

## 9. 需要的支撑

- 语言：class、Double、Long、Bool、String、可空；
- 运行时：`isNaN`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`xdk.math.isNaN`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new HistogramBucket(0.0, 10.0, 5)`；`contains(10.0)` true。  
反例：lower ≥ upper；count 负数；把 null 当 0；用 NaN 做边界。

---

## 13. 测试/场景义务

有界/单边无界/双边无界；边界值；NaN；count 0；toString；contains 开闭区间。

---

## 14. XNull 伪代码

```xnull
class HistogramBucket {
    final Double? _lower
    final Double? _upper
    final Long _count

    HistogramBucket(Double? lower, Double? upper, Long count) {
        if count < 0 { throw "HistogramBucket: negative count" }
        if lower != null && isNaN(lower) { throw "HistogramBucket: NaN lower" }
        if upper != null && isNaN(upper) { throw "HistogramBucket: NaN upper" }
        if lower != null && upper != null && lower >= upper {
            throw "HistogramBucket: lower >= upper"
        }
        _lower = lower
        _upper = upper
        _count = count
    }

    Double? lower() { return _lower }
    Double? upper() { return _upper }
    Long count() { return _count }

    Bool contains(Double value) {
        if isNaN(value) { return false }
        if _lower != null && value <= (_lower as Double) { return false }
        if _upper != null && value > (_upper as Double) { return false }
        return true
    }

    String toString() {
        String lowerText = "-inf"
        String upperText = "+inf"
        if _lower != null { lowerText = str(_lower as Double) }
        if _upper != null { upperText = str(_upper as Double) }
        return "(" + lowerText + ", " + upperText + "]=" + str(_count)
    }
}
```
