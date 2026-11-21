# `Counter`

| 项 | 值 |
| --- | --- |
| 类型 | `class Counter implements Metric` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | `Metric`、`MetricFamily`、`MetricSample`、`MetricKind`、`RuntimeMonitor`、`nowMono` |

---

## 1. 定位

单调累计计数器：从 0 开始，只增不减，支持 `inc`/`add`/`get`/`reset` 与族快照。

不做：瞬时值（用 `Gauge`）、分布统计（用 `Histogram`）、时长统计（用 `Timer`）、持久化、导出编码。

---

## 2. 设计逻辑

- 唯一数值 `_value: Double`，初始 0.0。
- `inc()` 等价于 `add(1.0)`；只保留 Double 版本，避免 Double/Long 混用。
- `add(delta)` 要求 delta 有限且 ≥0；NaN、±Inf、负值 → panic。
- 累加结果必须有限；溢出 → panic，避免导出非有限累计值。
- `reset()` 归零；不从注册表移除，不改变名称/标签/元数据。
- 每次快照产生一个样本：名称 = 指标名，值 = 当前累计，时间戳 = `nowMono()`。
- 线程安全：`RuntimeMonitor` 保护 `_value`；元数据不可变。
- 无 close；无资源；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 指标名；非空 |
| `_help` | `String` | 说明；可为空 |
| `_unit` | `String` | 单位；可为空 |
| `_labels` | `Map<String,String>` | 标签快照 |
| `_monitor` | `RuntimeMonitor` | 数值保护 |
| `_value` | `Double` | ≥0 的有限累计值 |

不变量：`_value` 有限且 ≥0；元数据不可变；标签不可变；`snapshot` 的 kind 恒为 `Counter`。

---

## 4. 生命周期

构造后长期使用；`reset` 可重复调用；无 close；无资源；可从注册表移除但引用仍有效。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Counter(String name, String help, String unitName, Map<String,String> labels)` | 全部 | 名称非空且合法；help/unit 非 null；labels 非 null | 非法 → panic |
| `Counter(String name)` | name | 同上 | 非法 → panic；help/unit 为空，labels 为空 |

说明：

- 名称规则：非空、无空白、无 `{`/`}`/`"`/`,`。
- 标签键规则：非空、无空白、无 `{`/`}`/`"`/`,`/`=`；标签值非 null。
- 构造器复制 labels；调用方后续修改不影响计数器。
- 不接受初始值；所有 Counter 从 0 开始。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `inc` | 加 1 | 无 | `void` | 溢出 → panic |
| `add` | 加 delta | `Double delta` | `void` | 非有限/负值/溢出 → panic |
| `get` | 当前值 | 无 | `Double` | 无 |
| `reset` | 归零 | 无 | `void` | 无 |
| `name` | 指标名 | 无 | `String` | 无 |
| `kind` | 语义分类 | 无 | `MetricKind` | 无 |
| `help` | 说明 | 无 | `String` | 无 |
| `unit` | 单位 | 无 | `String` | 无 |
| `labels` | 标签快照 | 无 | `Map<String,String>` | 无 |
| `snapshot` | 族快照 | 无 | `MetricFamily` | 无 |

说明：

- `add(0.0)` 合法，不改变值。
- `reset` 与 `add` 并发时，结果取决于锁顺序；不承诺“重置后无增量”。
- `snapshot` 先读值再取时间戳；不保证时间戳与值来自同一纳秒。
- `snapshot` 返回的 family 含一个样本，样本名为指标名。

---

## 8. 使用的技术

- 加锁 Double 累加；
- 单调性校验；
- 溢出检查；
- 快照；
- 标签防御性复制。

---

## 9. 需要的支撑

- 语言：class、String、Double、Bool、Map、void；
- 运行时：`RuntimeMonitor.enter/exit`、`nowMono`、`isFinite`；
- 接口：`Metric`、`MetricFamily`、`MetricSample`、`MetricKind`。

---

## 10. 依赖的特性/接口/类

`Metric`、`MetricFamily`、`MetricSample`、`MetricKind`、`RuntimeMonitor`、`nowMono`、`xdk.math.isFinite`。

---

## 11. 所有权与并发

引用语义；线程安全；`inc`/`add`/`get`/`reset`/`snapshot` 可并发；元数据只读；无资源；无 close。

---

## 12. 示例与反例

正确：`Counter requests = new Counter("http_requests")`；`requests.inc()`；`requests.add(5.0)`。  
反例：用 Counter 表示在途请求数（应使用 Gauge）；`add(-1.0)` 试图递减；用 `reset` 代替移除；并发修改 `labels()` 返回值；期望 `snapshot` 自动清零。

---

## 13. 测试/场景义务

初始 0；`inc`；`add` 0/正常/大值；负值/NaN/±Inf；溢出；`get`；`reset`；并发 inc；并发 reset；`snapshot` 值/标签/时间戳；`labels` 副本；元数据；接口分派；移除后仍可读。

---

## 14. XNull 伪代码

```xnull
class Counter implements Metric {
    final String _name
    final String _help
    final String _unit
    final Map<String, String> _labels
    final RuntimeMonitor _monitor
    Double _value = 0.0

    Counter(String name, String help, String unitName, Map<String, String> labels) {
        if name == null || name == "" { throw "Counter: empty name" }
        if name.indexOf(" ") >= 0 || name.indexOf("{") >= 0 || name.indexOf("}") >= 0 {
            throw "Counter: invalid name"
        }
        if name.indexOf("\"") >= 0 || name.indexOf(",") >= 0 {
            throw "Counter: invalid name"
        }
        if help == null { throw "Counter: null help" }
        if unitName == null { throw "Counter: null unit" }
        if labels == null { throw "Counter: null labels" }
        Map<String, String> copy = [:]
        List<String> keys = labels.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            String labelValue = labels.get(key)
            if key == "" { throw "Counter: empty label key" }
            if labelValue == null { throw "Counter: null label value" }
            copy.put(key, labelValue)
            index = index + 1
        }
        _name = name
        _help = help
        _unit = unitName
        _labels = copy
        _monitor = new RuntimeMonitor()
    }

    Counter(String name) {
        if name == null || name == "" { throw "Counter: empty name" }
        if name.indexOf(" ") >= 0 || name.indexOf("{") >= 0 || name.indexOf("}") >= 0 {
            throw "Counter: invalid name"
        }
        if name.indexOf("\"") >= 0 || name.indexOf(",") >= 0 {
            throw "Counter: invalid name"
        }
        _name = name
        _help = ""
        _unit = ""
        _labels = [:]
        _monitor = new RuntimeMonitor()
    }

    String name() { return _name }
    MetricKind kind() { return MetricKind.Counter }
    String help() { return _help }
    String unit() { return _unit }
    Map<String, String> labels() { return _labels.copy() }

    void inc() {
        self.add(1.0)
    }

    void add(Double delta) {
        if !isFinite(delta) { throw "Counter.add: non-finite delta" }
        if delta < 0.0 { throw "Counter.add: negative delta" }
        _monitor.enter()
        Double next = _value + delta
        if !isFinite(next) {
            _monitor.exit()
            throw "Counter.add: overflow"
        }
        _value = next
        _monitor.exit()
    }

    Double get() {
        _monitor.enter()
        Double value = _value
        _monitor.exit()
        return value
    }

    void reset() {
        _monitor.enter()
        _value = 0.0
        _monitor.exit()
    }

    MetricFamily snapshot() {
        _monitor.enter()
        Double value = _value
        _monitor.exit()
        Long timestamp = nowMono()
        List<MetricSample> samples = []
        samples.push(new MetricSample(_name, _labels, value, timestamp))
        return new MetricFamily(_name, MetricKind.Counter, _help, _unit, samples)
    }
}
```
