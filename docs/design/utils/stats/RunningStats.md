# `RunningStats`

| 项 | 值 |
| --- | --- |
| 类型 | `class RunningStats` |
| 包 | `xdk.stats` |
| 稳定性 | `preview` |
| 依赖 | `xdk.math` |

---

## 1. 定位

常数内存在线统计：count/sum/min/max/均值/总体与样本方差/标准差/合并。

不做：分位数、直方图、原始值保留、线程安全、持久化。

---

## 2. 设计逻辑

- 使用 Welford 在线算法维护 count/mean/m2；同时维护 sum/min/max。
- 内存与样本数无关；适合长期指标。
- `merge` 使用并行方差合并公式，不重放样本。
- 空数据：mean/variance/stddev 返回 NaN，sum=0，count=0。
- 非线程安全；无 close；可 reset。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_count` | `Long` | 样本数 |
| `_mean` | `Double` | 在线均值 |
| `_m2` | `Double` | 离差平方和 |
| `_sum` | `Double` | 总和 |
| `_min` | `Double` | 最小值 |
| `_max` | `Double` | 最大值 |
| `_hasValues` | `Bool` | 是否有样本 |

不变量：count ≥0；m2 ≥0（数值误差允许极小负值）；hasValues=false 时 count=0。

---

## 4. 生命周期

构造后可变；`reset` 清空；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `RunningStats()` | 无 | 空 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 记录值 | `Double value` | `void` | 无 |
| `count` | 样本数 | 无 | `Long` | 无 |
| `sum` | 总和 | 无 | `Double` | 无 |
| `mean` | 均值 | 无 | `Double` | 空 → NaN |
| `min` | 最小值 | 无 | `Double` | 空 → NaN |
| `max` | 最大值 | 无 | `Double` | 空 → NaN |
| `variance` | 总体方差 | 无 | `Double` | 空 → NaN |
| `sampleVariance` | 样本方差 | 无 | `Double` | <2 → NaN |
| `stddev` | 总体标准差 | 无 | `Double` | 空 → NaN |
| `sampleStddev` | 样本标准差 | 无 | `Double` | <2 → NaN |
| `merge` | 合并 | `RunningStats other` | `RunningStats` | null → panic |
| `reset` | 清空 | 无 | `void` | 无 |

说明：

- `add(NaN)` 会把统计污染为 NaN；调用方应过滤。
- `variance` 使用 `m2/count`；`sampleVariance` 使用 `m2/(count-1)`。
- `merge` 后 count/mean/m2/sum/min/max 与逐条 add 等价（浮点误差除外）。

---

## 8. 使用的技术

- Welford 在线均值/方差；
- 并行合并公式；
- 最值维护；
- 常数内存。

---

## 9. 需要的支撑

- 语言：class、Double、Long、Bool；
- 运行时：`sqrt`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`xdk.math.sqrt`。

---

## 11. 所有权与并发

引用语义；非线程安全；`add`/`merge`/`reset` 不可并发；无资源。

---

## 12. 示例与反例

正确：长期指标每个样本 `add`；定期 `mean`/`stddev`。  
反例：期望 `RunningStats` 给分位；把 NaN 计入；并发 add；合并后与原地统计假设完全一致。

---

## 13. 测试/场景义务

空/单/多；负值；NaN；大数/小数；mean/variance/sampleVariance/stddev；merge 交换律；reset；count/sum/min/max。

---

## 14. XNull 伪代码

```xnull
class RunningStats {
    Long _count = 0
    Double _mean = 0.0
    Double _m2 = 0.0
    Double _sum = 0.0
    Double _min = 0.0
    Double _max = 0.0
    Bool _hasValues = false

    RunningStats() {
    }

    void add(Double value) {
        _count = _count + 1
        Double delta = value - _mean
        _mean = _mean + delta / (_count as Double)
        Double delta2 = value - _mean
        _m2 = _m2 + delta * delta2
        _sum = _sum + value
        if !_hasValues {
            _min = value
            _max = value
            _hasValues = true
        } else {
            if value < _min { _min = value }
            if value > _max { _max = value }
        }
    }

    Long count() { return _count }
    Double sum() { return _sum }

    Double mean() {
        if _count == 0 { return NaN }
        return _mean
    }

    Double min() {
        if !_hasValues { return NaN }
        return _min
    }

    Double max() {
        if !_hasValues { return NaN }
        return _max
    }

    Double variance() {
        if _count == 0 { return NaN }
        Double result = _m2 / (_count as Double)
        if result < 0.0 { return 0.0 }
        return result
    }

    Double sampleVariance() {
        if _count < 2 { return NaN }
        Double result = _m2 / ((_count - 1) as Double)
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

    RunningStats merge(RunningStats other) {
        if other == null { throw "RunningStats.merge: null" }
        if other._count == 0 { return self }
        if _count == 0 {
            _count = other._count
            _mean = other._mean
            _m2 = other._m2
            _sum = other._sum
            _min = other._min
            _max = other._max
            _hasValues = other._hasValues
            return self
        }
        Long total = _count + other._count
        Double delta = other._mean - _mean
        Double totalCount = total as Double
        Double meanValue = (_mean * (_count as Double) + other._mean * (other._count as Double)) / totalCount
        Double m2 = _m2 + other._m2 + delta * delta * (_count as Double) * (other._count as Double) / totalCount
        _count = total
        _mean = meanValue
        _m2 = m2
        _sum = _sum + other._sum
        if other._min < _min { _min = other._min }
        if other._max > _max { _max = other._max }
        return self
    }

    void reset() {
        _count = 0
        _mean = 0.0
        _m2 = 0.0
        _sum = 0.0
        _min = 0.0
        _max = 0.0
        _hasValues = false
    }
}
```
