# `TelemetryRecord`

| 项 | 值 |
| --- | --- |
| 类型 | `class TelemetryRecord` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `TelemetryKind`、`MetricFamily`、`SpanContext`、`SpanKind`、`SpanStatus`、`SpanEvent`、`Span`、`LogRecord`、`xdk.metrics`、`xdk.trace`、`xdk.log` |

---

## 1. 定位

不可变的单条遥测记录：kind 标签 + 恰好一个 kind 专用载荷 + 时间戳与大小估算。

- Metrics 载荷：`MetricFamily`（一个族，可含多条样本）；
- Traces 载荷：span 快照（名称、上下文、kind、状态、时长、属性、事件）；
- Logs 载荷：`LogRecord`。

不做：批次聚合、资源属性（归 `TelemetryBatch`）、导出编码、协议解析、可变更新、span 生命周期。

---

## 2. 设计逻辑

- XNull 禁止泛型协议；用 kind 标签 + 可空载荷表达三种记录，而不是泛型 `Record<T>`；
- 构造后不变；`with*`/`copy` 返回新对象；属性 Map、事件 List 防御性复制；
- 三种载荷互斥：`metricFamily`、`spanContext`、`logRecord` 恰好一个非 null；
- Metrics 记录的名称必须等于 `MetricFamily.name()`；Traces 记录名称是 span 名；Logs 记录名称是
  `LogRecord.loggerName()`；
- 时间戳同时保留单调毫秒与墙钟毫秒：排序/超时用单调值，展示/导出用墙钟值；
- `estimatedBytes` 是队列/内存限制的估算值，不承诺等于编码后字节数；
- `fromSpan` 只读取 `Span` 的公开快照方法；调用方应在 `Span.end()` 后调用，否则时长为 0；
- 无 close；无资源；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_kind` | `TelemetryKind` | 非 null |
| `_metricFamily` | `MetricFamily?` | Metrics 时非 null；其他 kind 为 null |
| `_name` | `String` | Metrics 族名 / span 名 / logger 名；非空 |
| `_attributes` | `Map<String,String>` | 仅 Traces 使用；其他 kind 为空 Map |
| `_spanContext` | `SpanContext?` | Traces 时非 null 且有效 |
| `_spanKind` | `SpanKind?` | Traces 时非 null |
| `_spanStatus` | `SpanStatus?` | Traces 时非 null |
| `_spanDurationMillis` | `Long` | Traces 时 ≥0；其他 kind 为 0 |
| `_spanEvents` | `List<SpanEvent>` | Traces 事件快照；其他 kind 为空列表 |
| `_logRecord` | `LogRecord?` | Logs 时非 null |
| `_timestampMono` | `Long` | ≥0 的单调毫秒 |
| `_timestampWall` | `Long` | ≥0 的 epoch 毫秒 |
| `_estimatedBytes` | `Long` | ≥0 的估算大小 |

不变量：kind 非 null；三个载荷恰好一个非 null；名称非空；时间戳 ≥0；列表/Map 非 null；
不可变；Traces 的上下文 `isValid()` 为 true；Metrics 的族名与记录名一致。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务只读共享；GC 管理。

---

## 5. 构造契约

构造器私有；由静态工厂创建。工厂负责 kind 专用校验与载荷互斥。

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 私有构造器 | 12 个字段 | 载荷互斥；名称非空；时间戳 ≥0；非 null 容器 | 非法 → panic |
| `metric` | `MetricFamily family, Long timestampMono, Long timestampWall` | family 非 null；时间戳 ≥0 | null/负值 → panic |
| `span` | 9 个参数 | name 非空；context 有效；kind/status 非 null；duration ≥0；时间戳 ≥0 | 非法 → panic |
| `log` | `LogRecord record` | record 非 null | null → panic |
| `fromSpan` | `Span span` | span 非 null；name/context/kind/status 有效 | null → panic |

说明：

- `metric` 的名称从 `family.name()` 读取；attributes 为空 Map；
- `span` 复制 attributes 与 events；不持有 `Span` 引用；
- `log` 的时间戳从 `LogRecord.timestampMono()`/`timestampWall()` 读取；
- `fromSpan` 使用 `Span.duration().millis()`；未结束 span 的时长为 0；
- `fromSpan` 的 `timestampMono` 是导出时刻，不是 span 开始时刻；span 开始时间由导出器按
  `timestampMono - durationMillis` 推导；
- 名称规则：非空、无换行、无制表；长度上限 1024 字符。

---

## 6. 字段表

见 §3；字段私有且 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `metric` | 构造指标记录 | `MetricFamily family, Long timestampMono, Long timestampWall` | `TelemetryRecord` | 非法 → panic |
| `span` | 构造 span 记录 | 9 个参数 | `TelemetryRecord` | 非法 → panic |
| `log` | 构造日志记录 | `LogRecord record` | `TelemetryRecord` | null → panic |
| `fromSpan` | 从活动 span 快照 | `Span span` | `TelemetryRecord` | null → panic |
| `kind` | 遥测种类 | 无 | `TelemetryKind` | 无 |
| `name` | 记录名 | 无 | `String` | 无 |
| `metricFamily` | 指标载荷 | 无 | `MetricFamily?` | 无 |
| `spanContext` | span 上下文 | 无 | `SpanContext?` | 无 |
| `spanKind` | span 类型 | 无 | `SpanKind?` | 无 |
| `spanStatus` | span 状态 | 无 | `SpanStatus?` | 无 |
| `spanDurationMillis` | span 时长 | 无 | `Long` | 无 |
| `spanAttributes` | span 属性快照 | 无 | `Map<String,String>` | 无 |
| `spanEvents` | span 事件快照 | 无 | `List<SpanEvent>` | 无 |
| `logRecord` | 日志载荷 | 无 | `LogRecord?` | 无 |
| `timestampMono` | 单调时间戳 | 无 | `Long` | 无 |
| `timestampWall` | 墙钟时间戳 | 无 | `Long` | 无 |
| `estimatedBytes` | 估算大小 | 无 | `Long` | 无 |
| `withName` | 派生 span 名 | `String name` | `TelemetryRecord` | 非 Traces/非法 → panic |
| `withSpanAttributes` | 派生 span 属性 | `Map<String,String> attributes` | `TelemetryRecord` | 非 Traces/null → panic |
| `isValid` | 载荷互斥/格式校验 | 无 | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `copy` | 独立副本 | 无 | `TelemetryRecord` | 无 |

说明：

- `metricFamily`/`spanContext`/`logRecord` 对不适用的 kind 返回 null；调用方先看 `kind()`；
- `spanAttributes`/`spanEvents` 对非 Traces 返回空容器，不返回 null；
- `withName` 只允许 Traces；Metrics 名称由族名决定，Logs 名称由 `LogRecord` 决定；
- `withSpanAttributes` 只允许 Traces；复制新 Map，不修改原记录；
- `estimatedBytes` 在构造时计算；对 Metrics 按族名、样本标签、样本数估算；对 Traces 按名称、
  上下文标识、属性、事件估算；对 Logs 按 logger 名、消息、字段估算；
- `copy` 复制 Map/List；底层 `MetricFamily`/`SpanContext`/`LogRecord` 不可变，可共享引用；
- `describe` 只用于诊断，不是导出格式。

---

## 8. 使用的技术

- kind 标签联合；
- 不可变快照；
- 防御性复制；
- 载荷互斥校验；
- 单调/墙钟双时间戳；
- 字节估算。

---

## 9. 需要的支撑

- 语言：class、enum、可空引用、Map、List、String、Long、Bool；
- 运行时：`nowMono`、`nowWall`、`str`；
- 接口：`TelemetryKind`、`MetricFamily`、`SpanContext`、`SpanKind`、`SpanStatus`、`SpanEvent`、
  `Span`、`LogRecord`。

---

## 10. 依赖的特性/接口/类

`TelemetryKind`、`MetricFamily`、`MetricSample`、`SpanContext`、`SpanKind`、`SpanStatus`、
`SpanEvent`、`Span`、`Duration`、`LogRecord`、`nowMono`、`nowWall`。

---

## 11. 所有权与并发

不可变；可跨任务共享；`spanAttributes()`/`spanEvents()`/`copy()` 返回副本；
无资源；无取消点；`fromSpan` 只读 span，不改变 span 状态。
相等：引用身份；需要值比较时逐字段比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
TelemetryRecord record = TelemetryRecord.fromSpan(span)
TelemetryBatch batch = TelemetryBatch.of(TelemetryKind.Traces, ["service.name":"orders"], [record])
```

反例：用同一个记录同时携带 metricFamily 与 spanContext；在 `Span.end()` 前 `fromSpan` 并期望时长；
修改 `spanAttributes()` 返回值期望影响记录；把 `estimatedBytes` 当精确计费字节；用 wall clock
排序跨进程事件。

---

## 13. 测试/场景义务

三种工厂各字段；载荷互斥；名称/时间戳/时长非法；`withName`/`withSpanAttributes`；`copy` 独立性；
`isValid` 对三类记录；Metrics 族名一致性；Logs 时间戳继承；`fromSpan` 未结束/已结束；
`estimatedBytes` 非负；并发读取；`describe`。

---

## 14. XNull 伪代码

```xnull
class TelemetryRecord {
    final TelemetryKind _kind
    final MetricFamily? _metricFamily
    final String _name
    final Map<String, String> _attributes
    final SpanContext? _spanContext
    final SpanKind? _spanKind
    final SpanStatus? _spanStatus
    final Long _spanDurationMillis
    final List<SpanEvent> _spanEvents
    final LogRecord? _logRecord
    final Long _timestampMono
    final Long _timestampWall
    final Long _estimatedBytes

    private TelemetryRecord(TelemetryKind kind, MetricFamily? metricFamily,
                            String name, Map<String, String> attributes,
                            SpanContext? spanContext, SpanKind? spanKind,
                            SpanStatus? spanStatus, Long spanDurationMillis,
                            List<SpanEvent> spanEvents, LogRecord? logRecord,
                            Long timestampMono, Long timestampWall) {
        if kind == null { throw "TelemetryRecord: null kind" }
        if name == null || name == "" { throw "TelemetryRecord: empty name" }
        if name.indexOf("\n") >= 0 || name.indexOf("\t") >= 0 {
            throw "TelemetryRecord: invalid name"
        }
        if timestampMono < 0 || timestampWall < 0 {
            throw "TelemetryRecord: negative timestamp"
        }
        if attributes == null || spanEvents == null {
            throw "TelemetryRecord: null container"
        }
        Int payloadCount = 0
        if metricFamily != null { payloadCount = payloadCount + 1 }
        if spanContext != null { payloadCount = payloadCount + 1 }
        if logRecord != null { payloadCount = payloadCount + 1 }
        if payloadCount != 1 {
            throw "TelemetryRecord: payload mismatch"
        }
        if spanDurationMillis < 0 { throw "TelemetryRecord: negative duration" }
        _kind = kind
        _metricFamily = metricFamily
        _name = name
        _attributes = attributes.copy()
        _spanContext = spanContext
        _spanKind = spanKind
        _spanStatus = spanStatus
        _spanDurationMillis = spanDurationMillis
        _spanEvents = spanEvents.copy()
        _logRecord = logRecord
        _timestampMono = timestampMono
        _timestampWall = timestampWall
        _estimatedBytes = self.estimateBytes()
    }

    static TelemetryRecord metric(MetricFamily family, Long timestampMono,
                                  Long timestampWall) {
        if family == null { throw "TelemetryRecord.metric: null family" }
        return new TelemetryRecord(TelemetryKind.Metrics, family, family.name(),
            [:], null, null, null, 0, [], null, timestampMono, timestampWall)
    }

    static TelemetryRecord span(String name, SpanContext context, SpanKind kind,
                                SpanStatus status, Long durationMillis,
                                Map<String, String> attributes,
                                List<SpanEvent> events, Long timestampMono,
                                Long timestampWall) {
        if context == null || !context.isValid() {
            throw "TelemetryRecord.span: invalid context"
        }
        if kind == null || status == null {
            throw "TelemetryRecord.span: null kind/status"
        }
        if durationMillis < 0 {
            throw "TelemetryRecord.span: negative duration"
        }
        return new TelemetryRecord(TelemetryKind.Traces, null, name, attributes,
            context, kind, status, durationMillis, events, null,
            timestampMono, timestampWall)
    }

    static TelemetryRecord log(LogRecord record) {
        if record == null { throw "TelemetryRecord.log: null record" }
        return new TelemetryRecord(TelemetryKind.Logs, null, record.loggerName(),
            [:], null, null, null, 0, [], record,
            record.timestampMono(), record.timestampWall())
    }

    static TelemetryRecord fromSpan(Span span) {
        if span == null { throw "TelemetryRecord.fromSpan: null span" }
        return TelemetryRecord.span(span.name(), span.context(), span.kind(),
            span.status(), span.duration().millis(), span.attributes(),
            span.events(), nowMono(), nowWall())
    }

    TelemetryKind kind() { return _kind }
    String name() { return _name }
    MetricFamily? metricFamily() { return _metricFamily }
    SpanContext? spanContext() { return _spanContext }
    SpanKind? spanKind() { return _spanKind }
    SpanStatus? spanStatus() { return _spanStatus }
    Long spanDurationMillis() { return _spanDurationMillis }
    Map<String, String> spanAttributes() { return _attributes.copy() }
    List<SpanEvent> spanEvents() { return _spanEvents.copy() }
    LogRecord? logRecord() { return _logRecord }
    Long timestampMono() { return _timestampMono }
    Long timestampWall() { return _timestampWall }
    Long estimatedBytes() { return _estimatedBytes }

    Long estimateFamilyBytes(MetricFamily family) {
        Long total = family.name().length() + family.help().length()
        total = total + family.unit().length()
        List<MetricSample> samples = family.samples()
        Int sampleIndex = 0
        while sampleIndex < samples.length() {
            MetricSample sample = samples.get(sampleIndex)
            total = total + 96 + sample.name().length()
            Map<String, String> labels = sample.labels()
            List<String> labelKeys = labels.keys()
            Int labelIndex = 0
            while labelIndex < labelKeys.length() {
                String labelKey = labelKeys.get(labelIndex)
                total = total + labelKey.length()
                total = total + labels.getOr(labelKey, "").length()
                labelIndex = labelIndex + 1
            }
            sampleIndex = sampleIndex + 1
        }
        return total
    }

    Long estimateBytes() {
        Long total = 96 + _name.length()
        List<String> keys = _attributes.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            total = total + key.length() + _attributes.getOr(key, "").length()
            index = index + 1
        }
        if _metricFamily != null {
            total = total + self.estimateFamilyBytes(_metricFamily)
        }
        if _logRecord != null {
            total = total + _logRecord.message().length() + 64
        }
        Int eventIndex = 0
        while eventIndex < _spanEvents.length() {
            total = total + _spanEvents.get(eventIndex).name().length() + 48
            eventIndex = eventIndex + 1
        }
        return total
    }

    TelemetryRecord withName(String name) {
        if _kind != TelemetryKind.Traces {
            throw "TelemetryRecord.withName: not a span"
        }
        return TelemetryRecord.span(name, _spanContext, _spanKind, _spanStatus,
            _spanDurationMillis, _attributes, _spanEvents,
            _timestampMono, _timestampWall)
    }

    TelemetryRecord withSpanAttributes(Map<String, String> attributes) {
        if _kind != TelemetryKind.Traces {
            throw "TelemetryRecord.withSpanAttributes: not a span"
        }
        if attributes == null {
            throw "TelemetryRecord.withSpanAttributes: null attributes"
        }
        return TelemetryRecord.span(_name, _spanContext, _spanKind, _spanStatus,
            _spanDurationMillis, attributes, _spanEvents,
            _timestampMono, _timestampWall)
    }

    Bool isValid() {
        if _kind == TelemetryKind.Metrics {
            return _metricFamily != null && _metricFamily.name() == _name
        }
        if _kind == TelemetryKind.Traces {
            if _spanContext == null || !_spanContext.isValid() { return false }
            if _spanKind == null || _spanStatus == null { return false }
            return _spanDurationMillis >= 0
        }
        return _logRecord != null
    }

    TelemetryRecord copy() {
        return new TelemetryRecord(_kind, _metricFamily, _name, _attributes,
            _spanContext, _spanKind, _spanStatus, _spanDurationMillis,
            _spanEvents, _logRecord, _timestampMono, _timestampWall)
    }

    String describe() {
        return telemetryKindName(_kind) + " " + _name
            + " bytes=" + str(_estimatedBytes)
    }
}
```

> 伪代码中的 `estimateFamilyBytes` 是 `TelemetryRecord` 私有估算辅助，只用于队列/内存决策，不承诺等于编码字节数。
> 伪代码非可执行，只用于冻结字段、失败通道与互斥规则。
