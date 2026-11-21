# `Gauge`

| 项 | 值 |
| --- | --- |
| 类型 | `class Gauge implements Metric` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | `Metric`、`MetricFamily`、`MetricSample`、`MetricKind`、`RuntimeMonitor`、`nowMono` |

---

## 1. 定位

瞬时值仪表：可设置、增减、读取、重置；适合队列深度、连接数、温度等可升可降的量。

不做：单调累计（用 `Counter`）、分布统计、时长统计、持久化、导出编码。

---

## 2. 设计逻辑

- 唯一数值 `_value: Double`，初始 0.0。
- `set` 直接替换；`add`/`sub` 增减；`reset` 归零。
- 值必须有限；NaN/±Inf → panic；运算结果也必须有限，溢出 → panic。
- 允许负值；不限制单调性。
- 每次快照产生一个样本：名称 = 指标名，值 = 当前值，时间戳 = `nowMono()`。
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
| `_value` | `Double` | 有限瞬时值 |

不变量：`_value` 有限；元数据不可变；标签不可变；`snapshot` 的 kind 恒为 `Gauge`。

---

## 4. 生命周期

构造后长期使用；`set`/`add`/`sub`/`reset` 可重复；无 close；无资源；可从注册表移除但引用仍有效。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Gauge(String name, String help, String unitName, Map<String,String> labels)` | 全部 | 名称非空且合法；help/unit 非 null；labels 非 null | 非法 → panic |
| `Gauge(String name)` | name | 同上 | 非法 → panic；help/unit 为空，labels 为空 |

说明：

- 名称/标签规则与 `Counter` 一致。
- 构造器复制 labels；调用方后续修改不影响仪表。
- 不接受初始值；所有 Gauge 从 0.0 开始。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `set` | 设置值 | `Double value` | `void` | 非有限 → panic |
| `get` | 当前值 | 无 | `Double` | 无 |
| `add` | 增加 | `Double delta` | `void` | 非有限/溢出 → panic |
| `sub` | 减少 | `Double delta` | `void` | 非有限/溢出 → panic |
| `reset` | 归零 | 无 | `void` | 无 |
| `name` | 指标名 | 无 | `String` | 无 |
| `kind` | 语义分类 | 无 | `MetricKind` | 无 |
| `help` | 说明 | 无 | `String` | 无 |
| `unit` | 单位 | 无 | `String` | 无 |
| `labels` | 标签快照 | 无 | `Map<String,String>` | 无 |
| `snapshot` | 族快照 | 无 | `MetricFamily` | 无 |

说明：

- `add(0.0)`/`sub(0.0)` 合法，不改变值。
- `sub(-1.0)` 等价于加 1.0；不禁止负 delta，但结果必须有限。
- `reset` 置 0.0，不是恢复构造初值（构造初值也是 0.0）。
- `snapshot` 返回的 family 含一个样本，样本名为指标名。

---

## 8. 使用的技术

- 加锁 Double 更新；
- 有限性/溢出校验；
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

引用语义；线程安全；`set`/`add`/`sub`/`get`/`reset`/`snapshot` 可并发；元数据只读；无资源；无 close。

---

## 12. 示例与反例

正确：`Gauge queueDepth = new Gauge("queue_depth")`；`queueDepth.set(12.0)`；`queueDepth.sub(1.0)`。  
反例：用 Gauge 记录请求总数（应使用 Counter）；`set(NaN)`；用 `sub` 绕过有限性校验；期望 `snapshot` 自动归零；把 `labels()` 当可变视图。

---

## 13. 测试/场景义务

初始 0；`set` 正/负/零；`add`/`sub`；非有限值；溢出；`get`；`reset`；并发 set/add；`snapshot` 值/标签/时间戳；`labels` 副本；元数据；接口分派；移除后仍可读。

---

## 14. XNull 伪代码

```xnull
class Gauge implements Metric {
    final String _name
    final String _help
    final String _unit
    final Map<String, String> _labels
    final RuntimeMonitor _monitor
    Double _value = 0.0

    Gauge(String name, String help, String unitName, Map<String, String> labels) {
        if name == null || name == "" { throw "Gauge: empty name" }
        if name.indexOf(" ") >= 0 || name.indexOf("{") >= 0 || name.indexOf("}") >= 0 {
            throw "Gauge: invalid name"
        }
        if name.indexOf("\"") >= 0 || name.indexOf(",") >= 0 {
            throw "Gauge: invalid name"
        }
        if help == null { throw "Gauge: null help" }
        if unitName == null { throw "Gauge: null unit" }
        if labels == null { throw "Gauge: null labels" }
        Map<String, String> copy = [:]
        List<String> keys = labels.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            String labelValue = labels.get(key)
            if key == "" { throw "Gauge: empty label key" }
            if labelValue == null { throw "Gauge: null label value" }
            copy.put(key, labelValue)
            index = index + 1
        }
        _name = name
        _help = help
        _unit = unitName
        _labels = copy
        _monitor = new RuntimeMonitor()
    }

    Gauge(String name) {
        if name == null || name == "" { throw "Gauge: empty name" }
        if name.indexOf(" ") >= 0 || name.indexOf("{") >= 0 || name.indexOf("}") >= 0 {
            throw "Gauge: invalid name"
        }
        if name.indexOf("\"") >= 0 || name.indexOf(",") >= 0 {
            throw "Gauge: invalid name"
        }
        _name = name
        _help = ""
        _unit = ""
        _labels = [:]
        _monitor = new RuntimeMonitor()
    }

    String name() { return _name }
    MetricKind kind() { return MetricKind.Gauge }
    String help() { return _help }
    String unit() { return _unit }
    Map<String, String> labels() { return _labels.copy() }

    void set(Double value) {
        if !isFinite(value) { throw "Gauge.set: non-finite value" }
        _monitor.enter()
        _value = value
        _monitor.exit()
    }

    Double get() {
        _monitor.enter()
        Double value = _value
        _monitor.exit()
        return value
    }

    void add(Double delta) {
        if !isFinite(delta) { throw "Gauge.add: non-finite delta" }
        _monitor.enter()
        Double next = _value + delta
        if !isFinite(next) {
            _monitor.exit()
            throw "Gauge.add: overflow"
        }
        _value = next
        _monitor.exit()
    }

    void sub(Double delta) {
        if !isFinite(delta) { throw "Gauge.sub: non-finite delta" }
        _monitor.enter()
        Double next = _value - delta
        if !isFinite(next) {
            _monitor.exit()
            throw "Gauge.sub: overflow"
        }
        _value = next
        _monitor.exit()
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
        return new MetricFamily(_name, MetricKind.Gauge, _help, _unit, samples)
    }
}
```
