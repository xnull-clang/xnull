# `MetricFamily`

| 项 | 值 |
| --- | --- |
| 类型 | `class MetricFamily` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | `MetricKind`、`MetricSample` |

---

## 1. 定位

不可变指标族快照：族名、kind、help、unit、样本列表。

不做：指标存储、注册表查找、标签聚合、导出编码、时间序列数据库。

---

## 2. 设计逻辑

- 一个族对应一个逻辑指标名；同族可有多个标签序列，每个序列贡献样本。
- `_samples` 构造时复制；`samples()` 每次返回副本。
- 样本名必须是族名本身，或以 `族名_` 为前缀，避免跨族混装。
- `kind` 决定样本命名约定：Counter/Gauge 只有族名样本；Histogram 使用 `_bucket`/`_sum`/`_count`；Timer 使用 `_count`/`_sum`/`_max`。
- help/unit 允许空字符串；unit 为空表示无量纲或未声明。
- 不可变；无 close；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 族名；非空 |
| `_kind` | `MetricKind` | 语义分类 |
| `_help` | `String` | 说明；可为空 |
| `_unit` | `String` | 单位；可为空 |
| `_samples` | `List<MetricSample>` | 私有快照；元素非 null |

不变量：族名非空；kind 非 null；help/unit 非 null；样本非 null；每个样本名等于族名或以 `族名_` 开头；不可变。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MetricFamily(String name, MetricKind kind, String help, String unit, List<MetricSample> samples)` | 全部 | 名称非空；kind 非 null；help/unit 非 null；samples 非 null 且元素非 null | 非法 → panic |

说明：

- `samples` 允许为空，用于“已声明但尚无样本”的导出视图。
- 构造器复制列表，不持有调用方列表引用。
- 构造器校验样本名前缀，拒绝跨族样本。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 族名 | 无 | `String` | 无 |
| `kind` | 语义分类 | 无 | `MetricKind` | 无 |
| `help` | 说明 | 无 | `String` | 无 |
| `unit` | 单位 | 无 | `String` | 无 |
| `samples` | 样本快照 | 无 | `List<MetricSample>` | 无 |
| `sampleCount` | 样本数 | 无 | `Int` | 无 |
| `isEmpty` | 是否无样本 | 无 | `Bool` | 无 |
| `toString` | 诊断文本 | 无 | `String` | 无 |

说明：

- `samples()` 返回新列表；元素本身不可变，可安全共享。
- `sampleCount` 等价于 `samples().length()`，避免复制。
- `toString` 只用于诊断，格式为 `kind name (N samples)`，不作导出格式。

---

## 8. 使用的技术

- 不可变容器；
- 防御性复制；
- 样本命名约定校验；
- 族级元数据。

---

## 9. 需要的支撑

- 语言：class、String、List、Int、Bool；
- 运行时：无；
- 接口：`MetricKind`、`MetricSample`、`metricKindName`。

---

## 10. 依赖的特性/接口/类

`MetricKind`、`MetricSample`、`startsWith`、`metricKindName`。

---

## 11. 所有权与并发

不可变；引用可共享；样本列表私有；无资源；无并发写。

---

## 12. 示例与反例

正确：`new MetricFamily("http_requests", MetricKind.Counter, "Requests", "1", samples)`。  
反例：把不同族样本塞入同一 family；修改传入 samples 期望快照变化；用 family 当可变累加器；把 `kind` 与样本命名约定混用。

---

## 13. 测试/场景义务

空/单/多样本；元数据读取；样本副本独立；null 参数；样本名前缀校验；跨族样本拒绝；`sampleCount`/`isEmpty`；`toString`；并发读取。

---

## 14. XNull 伪代码

```xnull
class MetricFamily {
    final String _name
    final MetricKind _kind
    final String _help
    final String _unit
    final List<MetricSample> _samples

    MetricFamily(String name, MetricKind kind, String help, String unit,
                 List<MetricSample> samples) {
        if name == null || name == "" { throw "MetricFamily: empty name" }
        if kind == null { throw "MetricFamily: null kind" }
        if help == null { throw "MetricFamily: null help" }
        if unit == null { throw "MetricFamily: null unit" }
        if samples == null { throw "MetricFamily: null samples" }
        List<MetricSample> copy = []
        Int index = 0
        while index < samples.length() {
            MetricSample sample = samples.get(index)
            if sample == null { throw "MetricFamily: null sample" }
            if sample.name() != name && !sample.name().startsWith(name + "_") {
                throw "MetricFamily: sample name does not belong to family"
            }
            copy.push(sample)
            index = index + 1
        }
        _name = name
        _kind = kind
        _help = help
        _unit = unit
        _samples = copy
    }

    String name() { return _name }
    MetricKind kind() { return _kind }
    String help() { return _help }
    String unit() { return _unit }

    List<MetricSample> samples() { return _samples.copy() }
    Int sampleCount() { return _samples.length() }
    Bool isEmpty() { return _samples.isEmpty() }

    String toString() {
        return metricKindName(_kind) + " " + _name + " (" + str(_samples.length()) + " samples)"
    }
}
```
