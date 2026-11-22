# `BucketHistogram`

| 项 | 值 |
| --- | --- |
| 类型 | `class BucketHistogram` |
| 包 | `xdk.stats` |
| 稳定性 | `preview` |
| 依赖 | `HistogramBucket`、`xdk.math`、`xdk.collections` |

---

## 1. 定位

有状态桶直方图：固定边界、计数、总和/最值、近似分位、桶快照、重置、合并。

不做：动态边界、精确分位（用 `Summary`）、持久化、标签维度。

---

## 2. 设计逻辑

- 边界构造时复制并严格递增；空边界表示单一 `(-∞,+∞)` 桶。
- `observe` 对 NaN panic；值落入第一个 `value <= boundary` 的桶，否则最后无界桶。
- 记录 count/sum/sumSquares/min/max，支持均值/标准差。
- `percentile` 是桶级近似：返回累计计数达到目标所在桶的上界；最后桶返回 max。
- `merge` 要求边界完全相同；否则返回 false，不修改。
- 非线程安全；跨任务共享需外部同步。
- 无 close；可重置。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_boundaries` | `List<Double>` | 严格递增上界 |
| `_counts` | `List<Long>` | 长度 = 边界数+1 |
| `_count` | `Long` | 总样本数 |
| `_sum` | `Double` | 总和 |
| `_sumSquares` | `Double` | 平方和 |
| `_min` | `Double` | 最小值 |
| `_max` | `Double` | 最大值 |
| `_hasValues` | `Bool` | 是否有样本 |

不变量：counts 每项 ≥0；count = counts 之和；边界无 NaN 且严格递增；hasValues=false 时 count=0。

---

## 4. 生命周期

构造后可变；`reset` 清空；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BucketHistogram(List<Double> boundaries)` | boundaries | 非 null；严格递增；无 NaN | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `observe` | 记录值 | `Double value` | `void` | NaN → panic |
| `count` | 样本数 | 无 | `Long` | 无 |
| `sum` | 总和 | 无 | `Double` | 无 |
| `min` | 最小值 | 无 | `Double` | 空 → NaN |
| `max` | 最大值 | 无 | `Double` | 空 → NaN |
| `mean` | 均值 | 无 | `Double` | 空 → NaN |
| `stddev` | 总体标准差 | 无 | `Double` | 空 → NaN |
| `percentile` | 近似分位 | `Double percentileValue` | `Double` | 空 → NaN；percentileValue 钳制 |
| `buckets` | 桶快照 | 无 | `List<HistogramBucket>` | 无 |
| `merge` | 合并 | `BucketHistogram other` | `Bool` | null → panic；边界不同 false |
| `reset` | 清空 | 无 | `void` | 无 |

说明：

- `percentile(95.0)` 使用百分位；percentileValue 小于 0 按 0，大于 100 按 100。
- `merge` 同时合并计数、总和、平方和、最值。
- `stddev` 使用总体方差 `sumSquares/count - mean²`，负值钳制为 0。
- `buckets` 返回新对象，不暴露内部计数数组。

---

## 8. 使用的技术

- 有序边界二分/线性查找；
- 桶计数；
- 在线矩统计；
- 近似分位；
- 合并。

---

## 9. 需要的支撑

- 语言：class、List、Double、Long、Bool、Int；
- 运行时：`isNaN`、`sqrt`；
- 接口：`HistogramBucket`。

---

## 10. 依赖的特性/接口/类

`HistogramBucket`、`xdk.math.isNaN`、`xdk.math.sqrt`。

---

## 11. 所有权与并发

引用语义；非线程安全；`observe`/`reset`/`merge` 不可并发；无资源。

---

## 12. 示例与反例

正确：`new BucketHistogram([1.0,5.0,10.0])`；observe 3 → 第二桶。  
反例：边界乱序；observe NaN；空直方图取 min 当有效值；合并不同边界。

---

## 13. 测试/场景义务

空/单/多桶；边界值；负值；+Inf；NaN；count/sum/min/max/mean/stddev；percentile 0/50/95/100；merge 同/异边界；reset；空边界。

---

## 14. XNull 伪代码

```xnull
class BucketHistogram {
    final List<Double> _boundaries
    final List<Long> _counts
    Long _count = 0
    Double _sum = 0.0
    Double _sumSquares = 0.0
    Double _min = 0.0
    Double _max = 0.0
    Bool _hasValues = false

    BucketHistogram(List<Double> boundaries) {
        if boundaries == null { throw "BucketHistogram: null boundaries" }
        List<Double> copy = []
        Int index = 0
        while index < boundaries.length() {
            Double boundary = boundaries.get(index)
            if isNaN(boundary) { throw "BucketHistogram: NaN boundary" }
            if copy.length() > 0 && boundary <= copy.get(copy.length() - 1) {
                throw "BucketHistogram: boundaries not increasing"
            }
            copy.push(boundary)
            index = index + 1
        }
        _boundaries = copy
        List<Long> counts = []
        Int bucket = 0
        while bucket <= copy.length() {
            counts.push(0 as Long)
            bucket = bucket + 1
        }
        _counts = counts
    }

    void observe(Double value) {
        if isNaN(value) { throw "BucketHistogram.observe: NaN" }
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
        Int bucket = 0
        while bucket < _boundaries.length() && value > _boundaries.get(bucket) {
            bucket = bucket + 1
        }
        _counts.set(bucket, _counts.get(bucket) + 1)
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

    Double stddev() {
        if _count == 0 { return NaN }
        Double meanValue = self.mean()
        Double variance = _sumSquares / (_count as Double) - meanValue * meanValue
        if variance < 0.0 { variance = 0.0 }
        return sqrt(variance)
    }

    Double percentile(Double percentileValue) {
        if _count == 0 { return NaN }
        Double q = percentileValue
        if q < 0.0 { q = 0.0 }
        if q > 100.0 { q = 100.0 }
        Double target = (_count as Double) * q / 100.0
        if target <= 0.0 { return self.min() }
        Long cumulative = 0
        Int index = 0
        while index < _counts.length() {
            cumulative = cumulative + _counts.get(index)
            if (cumulative as Double) >= target {
                if index >= _boundaries.length() { return self.max() }
                return _boundaries.get(index)
            }
            index = index + 1
        }
        return self.max()
    }

    List<HistogramBucket> buckets() {
        List<HistogramBucket> result = []
        Int index = 0
        while index < _counts.length() {
            Double? lower = null
            Double? upper = null
            if index > 0 { lower = _boundaries.get(index - 1) }
            if index < _boundaries.length() { upper = _boundaries.get(index) }
            result.push(new HistogramBucket(lower, upper, _counts.get(index)))
            index = index + 1
        }
        return result
    }

    Bool merge(BucketHistogram other) {
        if other == null { throw "BucketHistogram.merge: null" }
        if _boundaries.length() != other._boundaries.length() { return false }
        Int index = 0
        while index < _boundaries.length() {
            if _boundaries.get(index) != other._boundaries.get(index) { return false }
            index = index + 1
        }
        _count = _count + other._count
        _sum = _sum + other._sum
        _sumSquares = _sumSquares + other._sumSquares
        if other._hasValues {
            if !_hasValues {
                _min = other._min
                _max = other._max
                _hasValues = true
            } else {
                if other._min < _min { _min = other._min }
                if other._max > _max { _max = other._max }
            }
        }
        index = 0
        while index < _counts.length() {
            _counts.set(index, _counts.get(index) + other._counts.get(index))
            index = index + 1
        }
        return true
    }

    void reset() {
        _count = 0
        _sum = 0.0
        _sumSquares = 0.0
        _min = 0.0
        _max = 0.0
        _hasValues = false
        Int index = 0
        while index < _counts.length() {
            _counts.set(index, 0 as Long)
            index = index + 1
        }
    }
}
```
