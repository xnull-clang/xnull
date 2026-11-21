# `Summary`

| 项 | 值 |
| --- | --- |
| 类型 | `class Summary` |
| 包 | `xdk.stats` |
| 稳定性 | `preview` |
| 依赖 | `xdk.math`、`xdk.collections` |

---

## 1. 定位

精确流式摘要：记录全部样本，提供 count/sum/min/max/均值/方差/标准差/精确分位/合并。

不做：固定内存（用 `RunningStats`）、桶近似（用 `Histogram`）、持久化、线程安全。

---

## 2. 设计逻辑

- 保存原始 `List<Double>`，因此分位精确；内存随样本数增长。
- `observe` 更新 count/sum/sumSquares/min/max，并追加值。
- `quantile` 对副本排序后线性插值；quantileValue 钳制到 [0,1]。
- 空数据：min/max/mean/variance/stddev/quantile 返回 NaN；count=0，sum=0。
- `merge` 把另一个 Summary 的样本逐条 observe 到当前对象；返回 self。
- 非线程安全；无 close；可 reset。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_values` | `List<Double>` | 原始样本 |
| `_count` | `Long` | 样本数 |
| `_sum` | `Double` | 总和 |
| `_sumSquares` | `Double` | 平方和 |
| `_min` | `Double` | 最小值 |
| `_max` | `Double` | 最大值 |
| `_hasValues` | `Bool` | 是否有样本 |

不变量：count = values.length；sum/sumSquares 与 values 一致；hasValues=false 时 count=0。

---

## 4. 生命周期

构造后可变；`reset` 清空；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Summary()` | 无 | 空 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `observe` | 记录 | `Double value` | `void` | 无 |
| `count` | 样本数 | 无 | `Long` | 无 |
| `sum` | 总和 | 无 | `Double` | 无 |
| `min` | 最小值 | 无 | `Double` | 空 → NaN |
| `max` | 最大值 | 无 | `Double` | 空 → NaN |
| `mean` | 均值 | 无 | `Double` | 空 → NaN |
| `variance` | 总体方差 | 无 | `Double` | 空 → NaN |
| `sampleVariance` | 样本方差 | 无 | `Double` | <2 → NaN |
| `stddev` | 总体标准差 | 无 | `Double` | 空 → NaN |
| `sampleStddev` | 样本标准差 | 无 | `Double` | <2 → NaN |
| `quantile` | 精确分位 | `Double quantileValue` | `Double` | 空 → NaN；quantileValue 钳制 |
| `quantiles` | 多个分位 | `List<Double> quantileValues` | `List<Double>` | null → panic |
| `merge` | 合并 | `Summary other` | `Summary` | null → panic |
| `reset` | 清空 | 无 | `void` | 无 |

说明：

- `variance` 使用总体方差 `sumSquares/count - mean²`，负值钳制为 0。
- `sampleVariance` 使用 `(sumSquares - sum²/count)/(count-1)`。
- `quantile(0.5)` 为线性插值中位数；单样本返回该值。
- `merge(self)` 会把当前样本翻倍，这是显式行为。

---

## 8. 使用的技术

- 原始样本存储；
- 在线矩统计；
- 排序 + 线性插值分位；
- 合并。

---

## 9. 需要的支撑

- 语言：class、List、Double、Long、Bool、Int；
- 运行时：`sqrt`、`sortedBy`、`floorToInt`? 使用截断转换；
- 接口：`xdk.math`、`xdk.collections.sortedBy`。

---

## 10. 依赖的特性/接口/类

`xdk.math.sqrt`、`xdk.collections.sortedBy`。

---

## 11. 所有权与并发

引用语义；非线程安全；`observe`/`merge`/`reset` 不可并发；无资源。

---

## 12. 示例与反例

正确：`Summary s = new Summary()`；`s.observe(10.0)`；`s.quantile(0.5)`。  
反例：把 Summary 当固定内存；空数据取 mean 当 0；并发 observe；合并后期望自动去重。

---

## 13. 测试/场景义务

空/单/多样本；负值/NaN；count/sum/min/max/mean/variance/sampleVariance/stddev；quantile 0/0.5/1；quantiles；merge；reset。

---

## 14. XNull 伪代码

```xnull
class Summary {
    final List<Double> _values
    Long _count = 0
    Double _sum = 0.0
    Double _sumSquares = 0.0
    Double _min = 0.0
    Double _max = 0.0
    Bool _hasValues = false

    Summary() {
        _values = []
    }

    void observe(Double value) {
        if !_hasValues {
            _min = value
            _max = value
            _hasValues = true
        } else {
            if value < _min { _min = value }
            if value > _max { _max = value }
        }
        _count = _count + 1
        _sum = _sum + value
        _sumSquares = _sumSquares + value * value
        _values.push(value)
    }

    Long count() { return _count }
    Double sum() { return _sum }

    Double min() {
        if !_hasValues { return NaN }
        return _min
    }

    Double max() {
        if !_hasValues { return NaN }
        return _max
    }

    Double mean() {
        if _count == 0 { return NaN }
        return _sum / (_count as Double)
    }

    Double variance() {
        if _count == 0 { return NaN }
        Double meanValue = self.mean()
        Double result = _sumSquares / (_count as Double) - meanValue * meanValue
        if result < 0.0 { return 0.0 }
        return result
    }

    Double sampleVariance() {
        if _count < 2 { return NaN }
        Double meanValue = self.mean()
        Double result = (_sumSquares - _sum * meanValue) / ((_count - 1) as Double)
        if result < 0.0 { return 0.0 }
        return result
    }

    Double stddev() {
        Double value = self.variance()
        if isNaN(value) { return NaN }
        return sqrt(value)
    }

    Double sampleStddev() {
        Double value = self.sampleVariance()
        if isNaN(value) { return NaN }
        return sqrt(value)
    }

    Double quantile(Double quantileValue) {
        if _count == 0 { return NaN }
        Double clamped = quantileValue
        if clamped < 0.0 { clamped = 0.0 }
        if clamped > 1.0 { clamped = 1.0 }
        if _count == 1 { return _values.get(0) }
        List<Double> sorted = sortedBy(_values.copy(), (Double a, Double b) -> a < b)
        Double position = clamped * ((_count - 1) as Double)
        Int lower = position as Int
        Int upper = lower + 1
        if upper >= sorted.length() { return sorted.get(sorted.length() - 1) }
        Double fraction = position - (lower as Double)
        Double lowerValue = sorted.get(lower)
        Double upperValue = sorted.get(upper)
        return lowerValue + (upperValue - lowerValue) * fraction
    }

    List<Double> quantiles(List<Double> quantileValues) {
        if quantileValues == null { throw "Summary.quantiles: null" }
        List<Double> result = []
        Int index = 0
        while index < quantileValues.length() {
            result.push(self.quantile(quantileValues.get(index)))
            index = index + 1
        }
        return result
    }

    Summary merge(Summary other) {
        if other == null { throw "Summary.merge: null" }
        List<Double> values = other._values.copy()
        Int index = 0
        while index < values.length() {
            self.observe(values.get(index))
            index = index + 1
        }
        return self
    }

    void reset() {
        _values.clear()
        _count = 0
        _sum = 0.0
        _sumSquares = 0.0
        _min = 0.0
        _max = 0.0
        _hasValues = false
    }
}
```
