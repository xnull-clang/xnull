# `PrometheusExporter`

| 项 | 值 |
| --- | --- |
| 类型 | `class PrometheusExporter implements PipelineExporter` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `PipelineExporter`、`TelemetryKind`、`TelemetryBatch`、`MetricFamily`、`MetricSample`、`MetricKind`、`Writer`、`Context`、`Error` |

---

## 1. 定位

Prometheus 导出器：接收 Metrics 批次，保存最新指标视图，按 Prometheus 文本格式渲染到调用方 `Writer`，
供应用自己的 HTTP handler/抓取端点读取。

它对齐 OTel `prometheus` exporter 的“pull/抓取”语义；基线不内置 HTTP 服务器，不监听端口。

不做：HTTP 服务器、TLS、认证、OpenMetrics、native histogram、exemplars、远程写、Push Gateway、
Prometheus 查询、告警。

---

## 2. 设计逻辑

- 实现 `PipelineExporter`；`kind()` 固定 Metrics；非 Metrics 批次拒绝；
- `export` 合并到内存中的族表：同族同标签样本替换，新样本追加；保留 kind/help/unit；
- 不持久化；不排队；导出是内存更新，`drain` 无操作；
- `scrape` 遍历族表，按名称排序，输出 `# HELP`/`# TYPE` 与样本行；
- 过期：`metricExpirationMillis >0` 时，超过该时长未更新的族不输出并从内存移除；0 表示不过期；
- 常量标签与命名空间在渲染时应用；样本标签优先于常量标签（同名时样本值保留）；
- `sendTimestamps` 为 true 时，每行追加抓取时刻的墙钟毫秒；不伪装样本单调时间；
- 转义：HELP 转义 `\`/换行；标签值转义 `\`/`"`/换行；非法指标名/标签名由导出器清洗或拒绝；
- 浮点 NaN/±Inf 按 Prometheus 文本 `NaN`/`+Inf`/`-Inf` 输出；
- `scrape` 不关闭/不 flush 调用方 Writer；Writer 所有权归应用；
- `close` 清空内存并置关闭；幂等；关闭后 `scrape` 返回 `Unavailable`；
- `isHealthy` 未启动/关闭为 false；启动后即使无样本也为 true。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空、单行 |
| `_namespace` | `String` | 可为空；非空时前缀 |
| `_constantLabels` | `Map<String,String>` | 构造时复制 |
| `_metricExpirationMillis` | `Long` | ≥0；0 表示不过期 |
| `_sendTimestamps` | `Bool` | 是否输出抓取时间 |
| `_families` | `Map<String,MetricFamily>` | 族名 → 当前快照 |
| `_updatedMono` | `Map<String,Long>` | 族名 → 最近更新时间 |
| `_started` | `Bool` | start 后 true |
| `_closed` | `Bool` | 只从 false 变 true |
| `_monitor` | `RuntimeMonitor` | 族表保护 |

不变量：族表 kind 全为 Metrics；同族元数据稳定；样本标签合并遵循“样本优先”；
过期清理只影响内存视图；scrape 不修改族表（除过期清理）；关闭后不再导出/渲染。

---

## 4. 生命周期

```text
构造 → start → export（更新视图）→ scrape（应用抓取）→ drain/close
```

- `start`：置启动；无网络/文件资源；重复 start 返回 `Ok(unit)`；
- `export`：合并族表；可多次；关闭后 `Unavailable`；
- `scrape`：渲染当前视图；可多次；关闭后 `Unavailable`；
- `drain`：无队列，返回 `Ok(unit)`；
- `close`：清空族表；幂等；关闭后 `export`/`scrape` 返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PrometheusExporter` | `String name, String namespace, Map<String,String> constantLabels, Long metricExpirationMillis, Bool sendTimestamps` | name 非空；expiration ≥0；labels 非 null | 非法 → panic |

说明：

- `namespace` 为空串表示不加前缀；非空时必须是合法 Prometheus 名称片段（`[a-zA-Z_:][a-zA-Z0-9_:]*`）；
- `constantLabels` 键/值非 null；键必须是合法标签名；值可为空串；
- `metricExpirationMillis == 0` 表示不过期；>0 表示过期窗口；
- `sendTimestamps` 默认 false；时间戳为抓取时刻墙钟毫秒；
- `name` 同一 Agent 内唯一，通常为 `"prometheus"`；
- 不配置 endpoint/端口；HTTP 由应用接线。

---

## 6. 字段表

见 §3；配置字段为 `final`；族表由监视器保护。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 固定 Metrics | 无 | `TelemetryKind` | 无 |
| `name` | 导出器名 | 无 | `String` | 无 |
| `start` | 启动 | `Context context` | `Result<Unit, Error>` | `Unavailable`/`Cancelled` |
| `export` | 更新指标视图 | `Context context, TelemetryBatch batch` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled`/`Internal` |
| `drain` | 无队列 | `Context context` | `Result<Unit, Error>` | `Cancelled`/`Unavailable` |
| `close` | 清空/关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |
| `scrape` | 渲染文本 | `Context context, Writer writer` | `Result<Unit, Error>` | `Io`/`Cancelled`/`Unavailable` |
| `sampleCount` | 样本数 | 无 | `Int` | 无 |
| `familyCount` | 族数 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `start` 对 null context → panic；已关闭 → `Unavailable`；重复 start → `Ok(unit)`；
- `export` 对 null context/batch → panic；batch.kind 非 Metrics → `InvalidArgument`；
  未启动/关闭 → `Unavailable`；同族 kind/help/unit 不一致 → `InvalidArgument`；
- `export` 合并样本：键为“样本名 + 排序后的标签”；同键替换，新键追加；`MetricFamily` 重建；
- `scrape` 对 null context/writer → panic；未启动/关闭 → `Unavailable`；
  过期清理后按族名排序输出；Writer 错误原样返回；不关闭 writer；
- `drain` 对 null context → panic；无队列返回 `Ok(unit)`；
- `close` 幂等；已关闭返回 `Ok(unit)`；
- `sampleCount`/`familyCount` 可并发读取。

### 7.1 Prometheus 文本映射

| `MetricKind` | TYPE | 样本约定 |
| --- | --- | --- |
| `Counter` | `counter` | 样本名按族名/`_total` 约定；值单调 |
| `Gauge` | `gauge` | 单样本或标签序列 |
| `Histogram` | `histogram` | `_bucket`（含 `le`）/`_sum`/`_count` |
| `Timer` | `summary` | `_sum`/`_count`/`_max` |

渲染格式：

```text
# HELP <name> <help>
# TYPE <name> <type>
<name>{<labels>} <value> [<timestampMillis>]
```

说明：

- `<name>` 应用 namespace；样本名已是族名或带后缀，namespace 前缀加在最前；
- HELP/TYPE 每族一次；样本按名称/标签排序，保证测试稳定；
- 标签键排序；标签值转义；常量标签与样本标签合并；
- 非有限值输出 `NaN`/`+Inf`/`-Inf`；
- 不输出 `# EOF`（非 OpenMetrics）；exemplars/native histogram 为 X。

---

## 8. 使用的技术

- 内存族表；
- 样本级合并；
- 标签排序/转义；
- 过期清理；
- Prometheus 文本渲染；
- Writer 所有权分离；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、String、Int、Long、Bool、Double、List、Map、Result；
- 运行时：`RuntimeMonitor`、`nowMono`、`nowWall`、`toUtf8`、`isNaN`、`isFinite`；
- 接口：`TelemetryRecord`、`MetricFamily`、`MetricSample`、`MetricKind`、`Writer`、`Context`、
  `Error`、`BasicError`、`ErrorKind`；
- 辅助：`metricKindName`、`sortedBy`、`truncate`。

---

## 10. 依赖的特性/接口/类

`PipelineExporter`、`TelemetryKind`、`TelemetryBatch`、`TelemetryRecord`、`MetricFamily`、`MetricSample`、
`MetricKind`、`Writer`、`Context`、`RuntimeMonitor`、`StringBuilder`、`nowMono`、`nowWall`、
`isNaN`、`isFinite`、`Error`、`BasicError`、`ErrorKind`、`metricKindName`、`sortedBy`、`toUtf8`。

---

## 11. 所有权与并发

- 导出器拥有族表与计数；不拥有 Writer、HTTP 服务器；
- `export`/`scrape`/`close` 可并发；族表由监视器保护；
- `scrape` 快照族表后渲染，尽量缩短持锁时间；Writer 写入不在锁内；
- `sampleCount`/`familyCount`/`isHealthy` 可并发读取；
- 同一实例可由多个 HTTP handler 并发 scrape；渲染只读快照；
- 同一实例不跨 Agent 共享。

---

## 12. 示例与反例

正确：

```xnull
PrometheusExporter exporter = new PrometheusExporter(
    "prometheus", "app", ["env":"prod"], 300000, false)
Result<Unit, Error> started = exporter.start(context)
if started.isErr() { return started }
Result<Unit, Error> exported = exporter.export(context, metricsBatch)
if exported.isErr() { return exported }
Result<Unit, Error> rendered = exporter.scrape(context, responseWriter)
if rendered.isErr() { diagnose(rendered.error().describe()) }
```

反例：在导出器里启动 HTTP 服务器；scrape 关闭 Writer；同族样本无限累积；标签不转义；
用单调时间戳当 Prometheus 时间戳；把 Timer 当 `timer` TYPE 输出；忽略过期清理。

---

## 13. 测试/场景义务

构造校验；start 重复；export 空/单族/多族/多标签；同键替换/新键追加；kind/help/unit 冲突；
非 Metrics 拒绝；scrape 排序/HELP/TYPE/标签转义/NaN/Inf/timestamp; namespace/常量标签冲突；
过期清理；Writer 错误/取消；close 后 export/scrape；drain；并发 export/scrape；计数；describe。

---

## 14. XNull 伪代码

```xnull
class PrometheusExporter implements PipelineExporter {
    final String _name
    final String _namespace
    final Map<String, String> _constantLabels
    final Long _metricExpirationMillis
    final Bool _sendTimestamps
    Map<String, MetricFamily> _families = [:]
    Map<String, Long> _updatedMono = [:]
    Bool _started = false
    Bool _closed = false
    final RuntimeMonitor _monitor

    PrometheusExporter(String name, String namespace,
                       Map<String, String> constantLabels,
                       Long metricExpirationMillis, Bool sendTimestamps) {
        if name == null || name == "" {
            throw "PrometheusExporter: empty name"
        }
        if namespace == null {
            throw "PrometheusExporter: null namespace"
        }
        if metricExpirationMillis < 0 {
            throw "PrometheusExporter: negative expiration"
        }
        if constantLabels == null {
            throw "PrometheusExporter: null labels"
        }
        _name = name
        _namespace = namespace
        _constantLabels = constantLabels.copy()
        _metricExpirationMillis = metricExpirationMillis
        _sendTimestamps = sendTimestamps
        _monitor = new RuntimeMonitor()
    }

    TelemetryKind kind() { return TelemetryKind.Metrics }
    String name() { return _name }
    Bool isHealthy() { return _started && !_closed }

    Result<Unit, Error> start(Context context) {
        if context == null { throw "PrometheusExporter.start: null context" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "closed"))
        }
        _started = true
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> export(Context context, TelemetryBatch batch) {
        if context == null { throw "PrometheusExporter.export: null context" }
        if batch == null { throw "PrometheusExporter.export: null batch" }
        if batch.kind() != TelemetryKind.Metrics {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "prometheus exporter requires metrics"))
        }
        _monitor.enter()
        if !_started || _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "not running"))
        }
        List<TelemetryRecord> records = batch.records()
        Int index = 0
        while index < records.length() {
            MetricFamily? family = records.get(index).metricFamily()
            if family != null {
                Result<Unit, Error> merged = self.mergeFamily(family)
                if merged.isErr() {
                    _monitor.exit()
                    return merged
                }
            }
            index = index + 1
        }
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> mergeFamily(MetricFamily incoming) {
        String familyName = incoming.name()
        if _families.has(familyName) {
            MetricFamily existing = _families.getOr(familyName, incoming)
            if existing.kind() != incoming.kind() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "prometheus kind conflict"))
            }
            if existing.help() != incoming.help()
                || existing.unit() != incoming.unit() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "prometheus metadata conflict"))
            }
            Map<String, MetricSample> samples = [:]
            Int existingIndex = 0
            List<MetricSample> existingSamples = existing.samples()
            while existingIndex < existingSamples.length() {
                MetricSample sample = existingSamples.get(existingIndex)
                samples.put(self.sampleKey(sample), sample)
                existingIndex = existingIndex + 1
            }
            Int incomingIndex = 0
            List<MetricSample> incomingSamples = incoming.samples()
            while incomingIndex < incomingSamples.length() {
                MetricSample sample = incomingSamples.get(incomingIndex)
                samples.put(self.sampleKey(sample), sample)
                incomingIndex = incomingIndex + 1
            }
            List<MetricSample> merged = []
            List<String> keys = sortedBy(samples.keys(), (String left, String right) -> left < right)
            Int keyIndex = 0
            while keyIndex < keys.length() {
                merged.push(samples.get(keys.get(keyIndex)))
                keyIndex = keyIndex + 1
            }
            MetricFamily combined = new MetricFamily(familyName, incoming.kind(),
                incoming.help(), incoming.unit(), merged)
            _families.put(familyName, combined)
        } else {
            _families.put(familyName, incoming)
        }
        _updatedMono.put(familyName, nowMono())
        return Ok(unit)
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "PrometheusExporter.drain: null context" }
        if !_started || _closed {
            return Err(new BasicError(ErrorKind.Unavailable, "not running"))
        }
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Ok(unit)
        }
        _closed = true
        _started = false
        _families.clear()
        _updatedMono.clear()
        _monitor.exit()
        return Ok(unit)
    }

    Int sampleCount() {
        Int total = 0
        List<String> names = _families.keys()
        Int index = 0
        while index < names.length() {
            total = total + _families.get(names.get(index)).samples().length()
            index = index + 1
        }
        return total
    }

    Int familyCount() { return _families.length() }

    Result<Unit, Error> scrape(Context context, Writer writer) {
        if context == null { throw "PrometheusExporter.scrape: null context" }
        if writer == null { throw "PrometheusExporter.scrape: null writer" }
        _monitor.enter()
        if !_started || _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "not running"))
        }
        self.removeExpired()
        List<String> names = sortedBy(_families.keys(), (String left, String right) -> left < right)
        Map<String, MetricFamily> snapshot = [:]
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            snapshot.put(name, _families.get(name))
            index = index + 1
        }
        _monitor.exit()
        StringBuilder text = new StringBuilder()
        List<String> familyNames = sortedBy(snapshot.keys(), (String left, String right) -> left < right)
        index = 0
        while index < familyNames.length() {
            self.renderFamily(text, snapshot.get(familyNames.get(index)))
            index = index + 1
        }
        return writer.writeAll(context, toUtf8(text.toString()))
    }

    void renderFamily(StringBuilder text, MetricFamily family) {
        String renderedName = self.prefixed(family.name())
        text.append("# HELP " + renderedName + " " + self.escapeHelp(family.help()) + "\n")
        text.append("# TYPE " + renderedName + " " + self.prometheusType(family.kind()) + "\n")
        List<MetricSample> samples = family.samples()
        Int index = 0
        while index < samples.length() {
            MetricSample sample = samples.get(index)
            String sampleName = self.prefixed(sample.name())
            Map<String, String> labels = self.mergedLabels(sample.labels())
            text.append(sampleName)
            if labels.length() > 0 {
                text.append("{")
                List<String> keys = sortedBy(labels.keys(), (String left, String right) -> left < right)
                Int keyIndex = 0
                while keyIndex < keys.length() {
                    if keyIndex > 0 { text.append(",") }
                    String key = keys.get(keyIndex)
                    text.append(key + "=\"" + self.escapeLabel(labels.getOr(key, "")) + "\"")
                    keyIndex = keyIndex + 1
                }
                text.append("}")
            }
            text.append(" " + self.formatValue(sample.value()))
            if _sendTimestamps {
                text.append(" " + str(nowWall()))
            }
            text.append("\n")
            index = index + 1
        }
    }

    void removeExpired() {
        if _metricExpirationMillis == 0 { return }
        Long threshold = nowMono() - _metricExpirationMillis
        List<String> names = _updatedMono.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            if _updatedMono.getOr(name, 0) < threshold {
                _families.remove(name)
                _updatedMono.remove(name)
            }
            index = index + 1
        }
    }

    String sampleKey(MetricSample sample) {
        String key = sample.name()
        List<String> labels = sortedBy(sample.labels().keys(),
            (String left, String right) -> left < right)
        Int index = 0
        while index < labels.length() {
            String label = labels.get(index)
            key = key + "\u0000" + label + "\u0001" + sample.labels().getOr(label, "")
            index = index + 1
        }
        return key
    }

    Map<String, String> mergedLabels(Map<String, String> labels) {
        Map<String, String> merged = _constantLabels.copy()
        List<String> keys = labels.keys()
        Int index = 0
        while index < keys.length() {
            merged.put(keys.get(index), labels.getOr(keys.get(index), ""))
            index = index + 1
        }
        return merged
    }

    String prefixed(String name) {
        if _namespace == "" { return name }
        return _namespace + "_" + name
    }

    String prometheusType(MetricKind kind) {
        if kind == MetricKind.Counter { return "counter" }
        if kind == MetricKind.Gauge { return "gauge" }
        if kind == MetricKind.Histogram { return "histogram" }
        return "summary"
    }

    String formatValue(Double value) {
        if isNaN(value) { return "NaN" }
        if !isFinite(value) {
            if value > 0 { return "+Inf" }
            return "-Inf"
        }
        return str(value)
    }

    String escapeHelp(String text) {
        String result = text
        result = result.replaceAll("\\", "\\\\")
        result = result.replaceAll("\n", "\\n")
        return result
    }

    String escapeLabel(String text) {
        String result = text
        result = result.replaceAll("\\", "\\\\")
        result = result.replaceAll("\"", "\\\"")
        result = result.replaceAll("\n", "\\n")
        return result
    }

    String describe() {
        return "prometheus " + _name + " families=" + str(_families.length())
            + " samples=" + str(self.sampleCount())
    }
}
```

> `MetricSample` 的 `timestampMono` 是单调时间，不能直接作为 Prometheus 时间戳；`sendTimestamps`
> 使用抓取时刻 `nowWall()`。同族样本合并为基线能力；跨资源同名但标签相同的样本会互相覆盖。
