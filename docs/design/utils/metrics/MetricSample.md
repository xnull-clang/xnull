# `MetricSample`

| 项 | 值 |
| --- | --- |
| 类型 | `class MetricSample` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | `xdk.math`、`xdk.collections` |

---

## 1. 定位

不可变单点指标样本：名称、标签快照、数值、单调时间戳。

不做：指标聚合、标签派生、导出编码、时间戳换算、可变更新。

---

## 2. 设计逻辑

- 字段 `_name`、`_labels: Map<String,String>`、`_value: Double`、`_timestampMono: Long`。
- 构造时复制标签；`labels()` 每次返回副本；样本不可变。
- `_value` 允许 NaN/±Inf：空统计的 min/max/mean、直方图总和溢出等需要表达非有限值；由导出器按格式编码。
- `_timestampMono` 使用单调毫秒；不从墙钟取，避免回拨。
- `withValue` 返回新样本，名称/标签/时间戳不变。
- 名称/标签键做基本字符校验；标签值可为空字符串，但不可为 null。
- 无 close；无资源；可作值对象比较。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空；无空白/`{`/`}`/`"`/`,` |
| `_labels` | `Map<String,String>` | 私有快照；键非空；值非 null |
| `_value` | `Double` | 可为 NaN/±Inf |
| `_timestampMono` | `Long` | ≥0 的单调毫秒 |

不变量：标签集合在构造后不变；样本不修改来源 Map；时间戳不因读取而变化；相等性包含名称、标签、值、时间戳。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MetricSample(String name, Map<String,String> labels, Double value, Long timestampMono)` | 全部 | 名称非空且合法；labels 非 null；键非空；值非 null；时间戳 ≥0 | 非法 → panic |

说明：

- 名称规则与指标名一致：非空、无空白、无 `{`/`}`/`"`/`,`。
- 标签键规则：非空、无空白、无 `{`/`}`/`"`/`,`/`=`；标签值只要求非 null。
- `value` 不校验有限性；NaN/±Inf 是合法样本值。
- `labels` 复制后存储，调用方后续修改不影响样本。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 样本名 | 无 | `String` | 无 |
| `labels` | 标签快照 | 无 | `Map<String,String>` | 无 |
| `value` | 数值 | 无 | `Double` | 无 |
| `timestampMono` | 单调时间戳 | 无 | `Long` | 无 |
| `withValue` | 派生同标签样本 | `Double value` | `MetricSample` | 无 |
| `equals` | 值相等 | `MetricSample other` | `Bool` | 无 |
| `toString` | 诊断文本 | 无 | `String` | 无 |

说明：

- `labels()` 返回副本；调用方不能通过它修改样本。
- `withValue` 保留名称/标签/时间戳，只替换值；不修改原样本。
- `equals` 对 NaN 使用“同为 NaN 即相等”；其余值按 `Double` 比较；标签按键集合比较，顺序无关。
- `toString` 的标签按键排序，便于稳定日志/测试；不作为导出格式。

---

## 8. 使用的技术

- 不可变值对象；
- 防御性复制；
- 标签排序；
- NaN 感知相等；
- 单调时间戳。

---

## 9. 需要的支撑

- 语言：class、String、Map、List、Double、Long、Bool、Int；
- 运行时：`isNaN`、`sortedBy`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`xdk.math.isNaN`、`xdk.collections.sortedBy`。

---

## 11. 所有权与并发

不可变；引用可共享；标签为私有快照；无资源；无并发写。

---

## 12. 示例与反例

正确：`new MetricSample("http_requests", ["method":"GET"], 42.0, nowMono())`。  
反例：修改传入 labels 期望样本变化；用墙钟填 `timestampMono`；把样本当可变累加器；依赖 `toString` 作为 Prometheus 输出。

---

## 13. 测试/场景义务

空标签/多标签；名称/标签键非法；null labels/值；时间戳 0/负值；NaN/±Inf 值；`withValue`；`equals` 顺序无关；标签副本独立；`toString` 排序；并发读取。

---

## 14. XNull 伪代码

```xnull
class MetricSample {
    final String _name
    final Map<String, String> _labels
    final Double _value
    final Long _timestampMono

    MetricSample(String name, Map<String, String> labels, Double value, Long timestampMono) {
        if name == null || name == "" { throw "MetricSample: empty name" }
        if name.indexOf(" ") >= 0 || name.indexOf("{") >= 0 || name.indexOf("}") >= 0 {
            throw "MetricSample: invalid name"
        }
        if name.indexOf("\"") >= 0 || name.indexOf(",") >= 0 {
            throw "MetricSample: invalid name"
        }
        if labels == null { throw "MetricSample: null labels" }
        if timestampMono < 0 { throw "MetricSample: negative timestamp" }
        Map<String, String> copy = [:]
        List<String> keys = labels.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            String labelValue = labels.get(key)
            if key == "" { throw "MetricSample: empty label key" }
            if labelValue == null { throw "MetricSample: null label value" }
            copy.put(key, labelValue)
            index = index + 1
        }
        _name = name
        _labels = copy
        _value = value
        _timestampMono = timestampMono
    }

    String name() { return _name }
    Map<String, String> labels() { return _labels.copy() }
    Double value() { return _value }
    Long timestampMono() { return _timestampMono }

    MetricSample withValue(Double value) {
        return new MetricSample(_name, _labels, value, _timestampMono)
    }

    Bool equals(MetricSample other) {
        if other == null { return false }
        if _name != other._name { return false }
        if _timestampMono != other._timestampMono { return false }
        if isNaN(_value) != isNaN(other._value) { return false }
        if !isNaN(_value) && _value != other._value { return false }
        if _labels.length() != other._labels.length() { return false }
        List<String> keys = _labels.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if !other._labels.has(key) { return false }
            if _labels.get(key) != other._labels.get(key) { return false }
            index = index + 1
        }
        return true
    }

    String toString() {
        List<String> keys = sortedBy(_labels.keys(), (String a, String b) -> a < b)
        String text = _name
        if keys.length() > 0 {
            text = text + "{"
            Int index = 0
            while index < keys.length() {
                if index > 0 { text = text + "," }
                String key = keys.get(index)
                text = text + key + "=\"" + _labels.get(key) + "\""
                index = index + 1
            }
            text = text + "}"
        }
        return text + " " + str(_value) + " " + str(_timestampMono)
    }
}
```
