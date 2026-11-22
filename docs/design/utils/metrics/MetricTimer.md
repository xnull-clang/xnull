# `MetricTimer`

| 项 | 值 |
| --- | --- |
| 类型 | `class MetricTimer implements Metric` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | `Metric`、`MetricFamily`、`MetricSample`、`MetricKind`、`xdk.stats.Summary`、`Duration`、`RuntimeMonitor`、`nowMono` |

---

## 1. 定位

时长计时器：用单调时钟起停，用 `xdk.stats.Summary` 保存毫秒样本；支持计数、总和、均值、最大值、精确分位。

不做：墙钟时间、跨进程累计、固定内存分位、分布式合并、导出编码。

---

## 2. 设计逻辑

- `start()` 只返回 `nowMono()`，不保存活动状态；`stop(startMono)` 计算差值、钳制负值、记录并返回 `Duration`。
- `observe(Duration)` 直接记录毫秒；负时长 → panic；零时长合法。
- 单位固定为 `"ms"`；不提供单位换算，避免同一族混用秒/毫秒。
- 分位由 `stats.Summary.quantile` 精确计算；`percentile(percentileValue)` 使用 0..100，内部除以 100。
- `Summary` 保存全部样本，内存随观测数增长；这是精确分位的代价，长期高频计时器应限制观测或改用 X 固定内存方案。
- 线程安全：`RuntimeMonitor` 保护 `Summary`；`start` 无共享状态。
- 无 close；无资源；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 指标名；非空 |
| `_help` | `String` | 说明；可为空 |
| `_unit` | `String` | 固定 `"ms"` |
| `_labels` | `Map<String,String>` | 标签快照 |
| `_summary` | `Summary` | 毫秒样本摘要 |
| `_monitor` | `RuntimeMonitor` | 摘要保护 |

不变量：`_unit == "ms"`；样本非负；快照 kind 恒为 `MetricTimer`；`start` 不修改任何字段。

---

## 4. 生命周期

构造后长期使用；`observe`/`reset` 可重复；`start` 可多次调用；无 close；无资源；可从注册表移除但引用仍有效。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MetricTimer(String name, String help, Map<String,String> labels)` | 全部 | 名称合法；help 非 null；labels 非 null | 非法 → panic |
| `MetricTimer(String name)` | name | 同上 | 非法 → panic；help 为空，labels 为空 |

说明：

- 名称/标签规则与 `Counter` 一致。
- 构造器复制 labels；调用方后续修改不影响计时器。
- 不接受初始时长；所有 MetricTimer 从空摘要开始。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `observe` | 记录时长 | `Duration duration` | `void` | null/负值 → panic |
| `start` | 取起始单调时刻 | 无 | `Long` | 无 |
| `stop` | 计算并记录 | `Long startMono` | `Duration` | 负起点 → panic |
| `count` | 样本数 | 无 | `Long` | 无 |
| `total` | 总时长 | 无 | `Duration` | 溢出 → panic |
| `mean` | 平均毫秒 | 无 | `Double` | 空 → NaN |
| `max` | 最大毫秒 | 无 | `Double` | 空 → NaN |
| `percentile` | 精确分位毫秒 | `Double percentileValue` | `Double` | percentileValue 非有限 → panic；空 → NaN |
| `reset` | 清空 | 无 | `void` | 无 |
| `name` | 指标名 | 无 | `String` | 无 |
| `kind` | 语义分类 | 无 | `MetricKind` | 无 |
| `help` | 说明 | 无 | `String` | 无 |
| `unit` | 单位 | 无 | `String` | 无 |
| `labels` | 标签快照 | 无 | `Map<String,String>` | 无 |
| `snapshot` | 族快照 | 无 | `MetricFamily` | 无 |

说明：

- `start` 返回的时间戳可被多个 `stop` 使用；每次都记录一次，调用方负责避免重复计时。
- `stop` 遇到 `nowMono() < startMono` 时把差值钳为 0，并记录 0ms；不 panic。
- `percentile(95.0)` 是 95 分位；`percentile(0.95)` 是 0.95 分位，不是 95 分位。
- `mean`/`max`/`percentile` 返回毫秒 `Double`，保留 Summary 的精度；需要 `Duration` 时显式 `Duration.ofMillis(value as Long)`。
- `snapshot` 生成 `_count`、`_sum` 以及非空时的 `_max` 样本；空计时器不输出 `_max`，避免把“无样本”误报为 0。

---

## 8. 使用的技术

- 单调时钟；
- 精确摘要/分位；
- 加锁更新；
- 快照；
- 时长换算。

---

## 9. 需要的支撑

- 语言：class、String、Double、Long、Bool、Map、void；
- 运行时：`RuntimeMonitor.enter/exit`、`nowMono`、`isFinite`；
- 接口：`Metric`、`MetricFamily`、`MetricSample`、`MetricKind`、`Summary`、`Duration`。

---

## 10. 依赖的特性/接口/类

`Metric`、`MetricFamily`、`MetricSample`、`MetricKind`、`xdk.stats.Summary`、`Duration`、`RuntimeMonitor`、`nowMono`、`xdk.math.isFinite`。

---

## 11. 所有权与并发

引用语义；线程安全；`observe`/`stop`/`count`/`total`/`mean`/`max`/`percentile`/`reset`/`snapshot` 可并发；`start` 无状态；无资源；无 close。

---

## 12. 示例与反例

正确：`Long start = timer.start()`；调用；`Duration elapsed = timer.stop(start)`。  
反例：用墙钟计算时长；对同一 `start` 调用两次 `stop` 期望只记一次；`observe(Duration.ofMillis(-1))`；期望固定内存；把 `percentile(0.95)` 当 P95；在快照中把空 `_max` 写成 0。

---

## 13. 测试/场景义务

空/单/多样本；零时长；负时长拒绝；`start`/`stop`；负起点；时钟回拨钳制；count/total/mean/max；percentile 0/50/95/100；非法 p；snapshot 样本；空 `_max` 省略；reset；并发；Duration 边界。

---

## 14. XNull 伪代码

```xnull
class MetricTimer implements Metric {
    final String _name
    final String _help
    final String _unit
    final Map<String, String> _labels
    final Summary _summary
    final RuntimeMonitor _monitor

    MetricTimer(String name, String help, Map<String, String> labels) {
        if name == null || name == "" { throw "MetricTimer: empty name" }
        if name.indexOf(" ") >= 0 || name.indexOf("{") >= 0 || name.indexOf("}") >= 0 {
            throw "MetricTimer: invalid name"
        }
        if name.indexOf("\"") >= 0 || name.indexOf(",") >= 0 {
            throw "MetricTimer: invalid name"
        }
        if help == null { throw "MetricTimer: null help" }
        if labels == null { throw "MetricTimer: null labels" }
        Map<String, String> copy = [:]
        List<String> keys = labels.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            String labelValue = labels.get(key)
            if key == "" { throw "MetricTimer: empty label key" }
            if labelValue == null { throw "MetricTimer: null label value" }
            copy.put(key, labelValue)
            index = index + 1
        }
        _name = name
        _help = help
        _unit = "ms"
        _labels = copy
        _summary = new Summary()
        _monitor = new RuntimeMonitor()
    }

    MetricTimer(String name) {
        if name == null || name == "" { throw "MetricTimer: empty name" }
        if name.indexOf(" ") >= 0 || name.indexOf("{") >= 0 || name.indexOf("}") >= 0 {
            throw "MetricTimer: invalid name"
        }
        if name.indexOf("\"") >= 0 || name.indexOf(",") >= 0 {
            throw "MetricTimer: invalid name"
        }
        _name = name
        _help = ""
        _unit = "ms"
        _labels = [:]
        _summary = new Summary()
        _monitor = new RuntimeMonitor()
    }

    String name() { return _name }
    MetricKind kind() { return MetricKind.MetricTimer }
    String help() { return _help }
    String unit() { return _unit }
    Map<String, String> labels() { return _labels.copy() }

    void observe(Duration duration) {
        if duration == null { throw "MetricTimer.observe: null duration" }
        if duration.isNegative() { throw "MetricTimer.observe: negative duration" }
        Double millis = duration.millis() as Double
        _monitor.enter()
        _summary.observe(millis)
        _monitor.exit()
    }

    Long start() {
        return nowMono()
    }

    Duration stop(Long startMono) {
        if startMono < 0 { throw "MetricTimer.stop: negative start" }
        Long elapsed = nowMono() - startMono
        if elapsed < 0 { elapsed = 0 }
        Duration duration = Duration.ofMillis(elapsed)
        self.observe(duration)
        return duration
    }

    Long count() {
        _monitor.enter()
        Long value = _summary.count()
        _monitor.exit()
        return value
    }

    Duration total() {
        _monitor.enter()
        Double value = _summary.sum()
        _monitor.exit()
        if value > 9223372036854775807.0 {
            throw "MetricTimer.total: overflow"
        }
        return Duration.ofMillis(value as Long)
    }

    Double mean() {
        _monitor.enter()
        Double value = _summary.mean()
        _monitor.exit()
        return value
    }

    Double max() {
        _monitor.enter()
        Double value = _summary.max()
        _monitor.exit()
        return value
    }

    Double percentile(Double percentileValue) {
        if !isFinite(percentileValue) { throw "MetricTimer.percentile: non-finite percentile" }
        _monitor.enter()
        Double value = _summary.quantile(percentileValue / 100.0)
        _monitor.exit()
        return value
    }

    void reset() {
        _monitor.enter()
        _summary.reset()
        _monitor.exit()
    }

    MetricFamily snapshot() {
        _monitor.enter()
        Long count = _summary.count()
        Double sum = _summary.sum()
        Double maximum = 0.0
        if count > 0 { maximum = _summary.max() }
        _monitor.exit()
        Long timestamp = nowMono()
        List<MetricSample> samples = []
        samples.push(new MetricSample(_name + "_count", _labels, count as Double, timestamp))
        samples.push(new MetricSample(_name + "_sum", _labels, sum, timestamp))
        if count > 0 {
            samples.push(new MetricSample(_name + "_max", _labels, maximum, timestamp))
        }
        return new MetricFamily(_name, MetricKind.MetricTimer, _help, _unit, samples)
    }
}
```
