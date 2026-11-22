# `Histogram`

| 项 | 值 |
| --- | --- |
| 类型 | `class Histogram implements Metric` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | `Metric`、`MetricFamily`、`MetricSample`、`MetricKind`、`xdk.stats.BucketHistogram`、`HistogramBucket`、`RuntimeMonitor`、`nowMono` |

---

## 1. 定位

带标签/注册表面的桶直方图：固定边界、计数、总和、最值、均值、近似分位、桶快照、重置。

不做：动态边界、精确分位（Timer 使用 `Summary`）、持久化、分布式合并、桶算法复制。

---

## 2. 设计逻辑

- 桶数学全部委托 `xdk.stats.BucketHistogram`；本类型只增加名称/标签/快照面，不复制边界查找或桶计数算法。
- 构造时复制并校验边界；边界严格递增，空边界表示单一无界桶。
- `observe` 拒绝 NaN；允许 ±Inf（落入首/末桶），总和/均值可能因此变为 NaN/±Inf。
- `count`/`sum`/`min`/`max`/`mean`/`percentile`/`buckets` 直接委托；空统计的 min/max/mean/percentile 为 NaN。
- `percentile(percentileValue)` 的 percentileValue 使用 0..100 百分位，与 `stats.BucketHistogram.percentile` 一致；不转换为 0..1。
- 快照按 Prometheus 约定生成：每个桶一个 `_bucket` 样本，标签含 `le`（上界文本，最后桶为 `+Inf`），累计计数；另有 `_sum`、`_count`。
- 线程安全：`RuntimeMonitor` 保护委托对象；元数据不可变。
- 无 close；无资源；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 指标名；非空 |
| `_help` | `String` | 说明；可为空 |
| `_unit` | `String` | 单位；可为空 |
| `_labels` | `Map<String,String>` | 标签快照；不含 `le` |
| `_boundaries` | `List<Double>` | 私有边界副本；严格递增 |
| `_delegate` | `xdk.stats.BucketHistogram` | 桶数学委托 |
| `_monitor` | `RuntimeMonitor` | 委托对象保护 |

不变量：边界严格递增且无 NaN；标签不含 `le`；`_delegate` 与 `_boundaries` 对应；快照 kind 恒为 `Histogram`。

---

## 4. 生命周期

构造后长期使用；`observe`/`reset` 可重复；无 close；无资源；可从注册表移除但引用仍有效。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Histogram(String name, String help, String unitText, Map<String,String> labels, List<Double> boundaries)` | 全部 | 名称合法；help/unit 非 null；labels 非 null 且无 `le`；boundaries 非 null、严格递增、无 NaN | 非法 → panic |
| `Histogram(String name, List<Double> boundaries)` | name/boundaries | 同上 | 非法 → panic；help/unit 为空，labels 为空 |

说明：

- 名称/标签规则与 `Counter` 一致。
- `le` 是保留标签；用户标签含 `le` 会被拒绝，避免与桶上界冲突。
- 边界复制后传给委托对象；调用方后续修改原列表不影响直方图。
- 空边界合法，表示单一 `(-∞,+∞)` 桶。

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
| `percentile` | 近似分位 | `Double percentileValue` | `Double` | percentileValue 非有限 → panic；空 → NaN |
| `buckets` | 桶快照 | 无 | `List<HistogramBucket>` | 无 |
| `boundaries` | 边界快照 | 无 | `List<Double>` | 无 |
| `reset` | 清空 | 无 | `void` | 无 |
| `name` | 指标名 | 无 | `String` | 无 |
| `kind` | 语义分类 | 无 | `MetricKind` | 无 |
| `help` | 说明 | 无 | `String` | 无 |
| `unit` | 单位 | 无 | `String` | 无 |
| `labels` | 标签快照 | 无 | `Map<String,String>` | 无 |
| `snapshot` | 族快照 | 无 | `MetricFamily` | 无 |

说明：

- `percentile` 的 percentileValue 小于 0 按 0、大于 100 按 100 由委托对象钳制；NaN/±Inf 在入口拒绝。
- `buckets` 返回委托对象的新列表，元素为不可变 `HistogramBucket`。
- `snapshot` 的桶样本是累计计数；委托 `buckets()` 返回的是单桶计数。
- `snapshot` 不包含 min/max 样本；Prometheus 直方图只需桶、总和、计数。

---

## 8. 使用的技术

- 委托组合；
- 固定边界桶计数；
- 累计桶快照；
- 单调时间戳；
- 运行时监视器。

---

## 9. 需要的支撑

- 语言：class、String、Double、Long、Int、Bool、Map、List、void；
- 运行时：`RuntimeMonitor.enter/exit`、`nowMono`、`isNaN`、`isFinite`；
- 接口：`Metric`、`MetricFamily`、`MetricSample`、`MetricKind`、`xdk.stats.BucketHistogram`、`HistogramBucket`。

---

## 10. 依赖的特性/接口/类

`Metric`、`MetricFamily`、`MetricSample`、`MetricKind`、`xdk.stats.BucketHistogram`、`HistogramBucket`、`RuntimeMonitor`、`nowMono`、`xdk.math.isNaN`、`xdk.math.isFinite`。

---

## 11. 所有权与并发

引用语义；线程安全；`observe`/`reset`/`snapshot` 可并发；委托对象不暴露；元数据只读；无资源；无 close。

---

## 12. 示例与反例

正确：`new Histogram("request_ms", [5.0, 10.0, 25.0])`；`observe(12.0)`；`percentile(95.0)`。  
反例：在本类重新实现桶查找；`observe(NaN)`；用 `percentile(0.95)` 期望 95 分位；传乱序边界；在用户标签里使用 `le`；期望空直方图的 `min()` 返回 0。

---

## 13. 测试/场景义务

空/单/多桶；边界值；负值；±Inf；NaN 拒绝；count/sum/min/max/mean；percentile 0/50/95/100；`buckets` 单桶计数；`snapshot` 累计计数/`le`/`+Inf`/`_sum`/`_count`；`boundaries` 副本；reset；并发；边界非法；`le` 冲突。

---

## 14. XNull 伪代码

```xnull
class Histogram implements Metric {
    final String _name
    final String _help
    final String _unit
    final Map<String, String> _labels
    final List<Double> _boundaries
    final xdk.stats.BucketHistogram _delegate
    final RuntimeMonitor _monitor

    Histogram(String name, String help, String unitText, Map<String, String> labels,
              List<Double> boundaries) {
        if name == null || name == "" { throw "Histogram: empty name" }
        if name.indexOf(" ") >= 0 || name.indexOf("{") >= 0 || name.indexOf("}") >= 0 {
            throw "Histogram: invalid name"
        }
        if name.indexOf("\"") >= 0 || name.indexOf(",") >= 0 {
            throw "Histogram: invalid name"
        }
        if help == null { throw "Histogram: null help" }
        if unitText == null { throw "Histogram: null unit" }
        if labels == null { throw "Histogram: null labels" }
        if boundaries == null { throw "Histogram: null boundaries" }
        Map<String, String> copy = [:]
        List<String> keys = labels.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            String labelValue = labels.get(key)
            if key == "" { throw "Histogram: empty label key" }
            if key == "le" { throw "Histogram: reserved label le" }
            if labelValue == null { throw "Histogram: null label value" }
            copy.put(key, labelValue)
            index = index + 1
        }
        _name = name
        _help = help
        _unit = unitText
        _labels = copy
        _boundaries = boundaries.copy()
        _delegate = new xdk.stats.BucketHistogram(_boundaries)
        _monitor = new RuntimeMonitor()
    }

    Histogram(String name, List<Double> boundaries) {
        if name == null || name == "" { throw "Histogram: empty name" }
        if name.indexOf(" ") >= 0 || name.indexOf("{") >= 0 || name.indexOf("}") >= 0 {
            throw "Histogram: invalid name"
        }
        if name.indexOf("\"") >= 0 || name.indexOf(",") >= 0 {
            throw "Histogram: invalid name"
        }
        if boundaries == null { throw "Histogram: null boundaries" }
        _name = name
        _help = ""
        _unit = ""
        _labels = [:]
        _boundaries = boundaries.copy()
        _delegate = new xdk.stats.BucketHistogram(_boundaries)
        _monitor = new RuntimeMonitor()
    }

    String name() { return _name }
    MetricKind kind() { return MetricKind.Histogram }
    String help() { return _help }
    String unit() { return _unit }
    Map<String, String> labels() { return _labels.copy() }

    void observe(Double value) {
        if isNaN(value) { throw "Histogram.observe: NaN" }
        _monitor.enter()
        _delegate.observe(value)
        _monitor.exit()
    }

    Long count() {
        _monitor.enter()
        Long value = _delegate.count()
        _monitor.exit()
        return value
    }

    Double sum() {
        _monitor.enter()
        Double value = _delegate.sum()
        _monitor.exit()
        return value
    }

    Double min() {
        _monitor.enter()
        Double value = _delegate.min()
        _monitor.exit()
        return value
    }

    Double max() {
        _monitor.enter()
        Double value = _delegate.max()
        _monitor.exit()
        return value
    }

    Double mean() {
        _monitor.enter()
        Double value = _delegate.mean()
        _monitor.exit()
        return value
    }

    Double percentile(Double percentileValue) {
        if !isFinite(percentileValue) { throw "Histogram.percentile: non-finite percentile" }
        _monitor.enter()
        Double value = _delegate.percentile(percentileValue)
        _monitor.exit()
        return value
    }

    List<HistogramBucket> buckets() {
        _monitor.enter()
        List<HistogramBucket> value = _delegate.buckets()
        _monitor.exit()
        return value
    }

    List<Double> boundaries() { return _boundaries.copy() }

    void reset() {
        _monitor.enter()
        _delegate.reset()
        _monitor.exit()
    }

    MetricFamily snapshot() {
        _monitor.enter()
        Long count = _delegate.count()
        Double sum = _delegate.sum()
        List<HistogramBucket> buckets = _delegate.buckets()
        _monitor.exit()
        Long timestamp = nowMono()
        List<MetricSample> samples = []
        Long cumulative = 0
        Int index = 0
        while index < buckets.length() {
            HistogramBucket bucket = buckets.get(index)
            cumulative = cumulative + bucket.count()
            Map<String, String> bucketLabels = _labels.copy()
            if bucket.upper() == null {
                bucketLabels.put("le", "+Inf")
            } else {
                bucketLabels.put("le", str(bucket.upper() as Double))
            }
            samples.push(new MetricSample(_name + "_bucket", bucketLabels,
                                          cumulative as Double, timestamp))
            index = index + 1
        }
        samples.push(new MetricSample(_name + "_sum", _labels, sum, timestamp))
        samples.push(new MetricSample(_name + "_count", _labels, count as Double, timestamp))
        return new MetricFamily(_name, MetricKind.Histogram, _help, _unit, samples)
    }
}
```

> `xdk.stats.BucketHistogram` 使用全限定名，以区别于本包的 `Histogram`；`HistogramBucket` 来自 `xdk.stats`。
