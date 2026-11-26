// xdk.agent —— 遥测核心与协议（M25.1）
//
// 实现 TelemetryKind/TelemetryRecord/TelemetryBatch/Receiver/Processor/
// PipelineExporter/Connector/AgentHealth；AgentPipeline/AgentConfig/Agent 留 M25.2/M25.3。
package xdk.agent
import xdk.errors
import xdk.metrics
import xdk.trace
import xdk.log
import xdk.runtime

// ---------- TelemetryKind ----------
// Unknown 放首位：编译器把枚举 0 当作 null。
enum TelemetryKind {
    Unknown,
    Metrics,
    Traces,
    Logs,
}

String telemetryKindName(TelemetryKind telemetryKind) {
    if telemetryKind == TelemetryKind.Metrics { return "metrics" }
    if telemetryKind == TelemetryKind.Traces { return "traces" }
    if telemetryKind == TelemetryKind.Logs { return "logs" }
    return "unknown"
}

// ---------- TelemetryRecord ----------
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

    private TelemetryRecord(TelemetryKind kind, MetricFamily? metricFamily, String name,
                            Map<String, String> attributes, SpanContext? spanContext,
                            SpanKind? spanKind, SpanStatus? spanStatus,
                            Long spanDurationMillis, List<SpanEvent> spanEvents,
                            LogRecord? logRecord, Long timestampMono,
                            Long timestampWall) {
        if kind == TelemetryKind.Unknown { throw "TelemetryRecord: invalid kind" }
        if name == null || name == "" { throw "TelemetryRecord: empty name" }
        if name.indexOf("\n") >= 0 || name.indexOf("\t") >= 0 ||
            name.length() > 1024 {
            throw "TelemetryRecord: invalid name"
        }
        if timestampMono < 0 as Long || timestampWall < 0 as Long {
            throw "TelemetryRecord: negative timestamp"
        }
        if attributes == null || spanEvents == null {
            throw "TelemetryRecord: null container"
        }
        Int payloadCount = 0
        if metricFamily != null { payloadCount = payloadCount + 1 }
        if spanContext != null { payloadCount = payloadCount + 1 }
        if logRecord != null { payloadCount = payloadCount + 1 }
        if payloadCount != 1 { throw "TelemetryRecord: payload mismatch" }
        if spanDurationMillis < 0 as Long {
            throw "TelemetryRecord: negative duration"
        }
        self._kind = kind
        self._metricFamily = metricFamily
        self._name = name
        self._attributes = agCopyStringMap(attributes)
        self._spanContext = spanContext
        self._spanKind = spanKind
        self._spanStatus = spanStatus
        self._spanDurationMillis = spanDurationMillis
        self._spanEvents = spanEvents.copy()
        self._logRecord = logRecord
        self._timestampMono = timestampMono
        self._timestampWall = timestampWall
        self._estimatedBytes = self.estimateBytes()
    }

    static TelemetryRecord metric(MetricFamily family, Long timestampMono,
                                  Long timestampWall) {
        if family == null { throw "TelemetryRecord.metric: null family" }
        Map<String, String> attributes = [:]
        List<SpanEvent> events = []
        return new TelemetryRecord(TelemetryKind.Metrics, family, family.name(),
            attributes, null, null, null, 0 as Long, events, null, timestampMono,
            timestampWall)
    }

    static TelemetryRecord span(String name, SpanContext context, SpanKind kind,
                                SpanStatus status, Long durationMillis,
                                Map<String, String> attributes,
                                List<SpanEvent> events, Long timestampMono,
                                Long timestampWall) {
        if context == null || !context.isValid() {
            throw "TelemetryRecord.span: invalid context"
        }
        if kind == null || kind == SpanKind.Unknown || status == null {
            throw "TelemetryRecord.span: null kind/status"
        }
        if durationMillis < 0 as Long {
            throw "TelemetryRecord.span: negative duration"
        }
        return new TelemetryRecord(TelemetryKind.Traces, null, name, attributes,
            context, kind, status, durationMillis, events, null, timestampMono,
            timestampWall)
    }

    static TelemetryRecord log(LogRecord record) {
        if record == null { throw "TelemetryRecord.log: null record" }
        Map<String, String> attributes = [:]
        List<SpanEvent> events = []
        return new TelemetryRecord(TelemetryKind.Logs, null, record.loggerName,
            attributes, null, null, null, 0 as Long, events, record,
            record.monotonic(), record.timestamp())
    }

    static TelemetryRecord fromSpan(Span span) {
        if span == null { throw "TelemetryRecord.fromSpan: null span" }
        return TelemetryRecord.span(span.name(), span.context(), span.kind(),
            span.status(), span.duration().millis(), span.attributes(),
            span.events(), nowMono(), nowWall())
    }

    TelemetryKind kind() { return self._kind }
    String name() { return self._name }
    MetricFamily? metricFamily() { return self._metricFamily }
    SpanContext? spanContext() { return self._spanContext }
    SpanKind? spanKind() { return self._spanKind }
    SpanStatus? spanStatus() { return self._spanStatus }
    Long spanDurationMillis() { return self._spanDurationMillis }
    Map<String, String> spanAttributes() { return agCopyStringMap(self._attributes) }
    List<SpanEvent> spanEvents() { return self._spanEvents.copy() }
    LogRecord? logRecord() { return self._logRecord }
    Long timestampMono() { return self._timestampMono }
    Long timestampWall() { return self._timestampWall }
    Long estimatedBytes() { return self._estimatedBytes }

    Long estimateFamilyBytes(MetricFamily family) {
        Long total = family.name().length() as Long + family.help().length() as Long +
            family.unit().length() as Long
        List<MetricSample> samples = family.samples()
        Int sampleIndex = 0
        while sampleIndex < samples.length() {
            MetricSample sample = samples.get(sampleIndex)
            total = total + 96 as Long + sample.name().length() as Long
            Map<String, String> labels = sample.labels()
            List<String> labelKeys = labels.keys()
            Int labelIndex = 0
            while labelIndex < labelKeys.length() {
                String key = labelKeys.get(labelIndex)
                total = total + key.length() as Long +
                    labels.getOr(key, "").length() as Long
                labelIndex = labelIndex + 1
            }
            sampleIndex = sampleIndex + 1
        }
        return total
    }

    Long estimateBytes() {
        Long total = 96 as Long + self._name.length() as Long
        List<String> keys = self._attributes.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            total = total + key.length() as Long +
                self._attributes.getOr(key, "").length() as Long
            index = index + 1
        }
        if self._metricFamily != null {
            MetricFamily family = self._metricFamily as MetricFamily
            total = total + self.estimateFamilyBytes(family)
        }
        if self._logRecord != null {
            LogRecord record = self._logRecord as LogRecord
            total = total + record.message.length() as Long + 64 as Long
        }
        Int eventIndex = 0
        while eventIndex < self._spanEvents.length() {
            total = total + self._spanEvents.get(eventIndex).name().length() as Long +
                48 as Long
            eventIndex = eventIndex + 1
        }
        return total
    }

    String describe() {
        return telemetryKindName(self._kind) + " record=" + self._name + " bytes=" +
            str(self._estimatedBytes)
    }
}

// ---------- TelemetryBatch ----------
class TelemetryBatch {
    final TelemetryKind _kind
    final Map<String, String> _resource
    final List<TelemetryRecord> _records
    final Int _droppedRecords
    final Long _timestampMono
    final Long _estimatedBytes

    TelemetryBatch(TelemetryKind kind, Map<String, String> resource,
                   List<TelemetryRecord> records, Int droppedRecords,
                   Long timestampMono) {
        if kind == TelemetryKind.Unknown { throw "TelemetryBatch: invalid kind" }
        if resource == null || records == null {
            throw "TelemetryBatch: null container"
        }
        if droppedRecords < 0 { throw "TelemetryBatch: negative dropped" }
        if timestampMono < 0 as Long { throw "TelemetryBatch: negative timestamp" }
        Map<String, String> resourceCopy = [:]
        List<String> resourceKeys = resource.keys()
        Int resourceIndex = 0
        while resourceIndex < resourceKeys.length() {
            String key = resourceKeys.get(resourceIndex)
            String value = resource.getOr(key, "")
            if key == "" || key.indexOf("\n") >= 0 || key.indexOf("\t") >= 0 ||
                key.indexOf("=") >= 0 {
                throw "TelemetryBatch: invalid resource key"
            }
            if value.indexOf("\n") >= 0 || value.indexOf("\t") >= 0 {
                throw "TelemetryBatch: invalid resource value"
            }
            resourceCopy.put(key, value)
            resourceIndex = resourceIndex + 1
        }
        List<TelemetryRecord> recordCopy = []
        Long totalBytes = 0 as Long
        Int recordIndex = 0
        while recordIndex < records.length() {
            TelemetryRecord record = records.get(recordIndex)
            if record == null { throw "TelemetryBatch: null record" }
            if record.kind() != kind {
                throw "TelemetryBatch: record kind mismatch"
            }
            recordCopy.push(record)
            totalBytes = totalBytes + record.estimatedBytes()
            recordIndex = recordIndex + 1
        }
        self._kind = kind
        self._resource = resourceCopy
        self._records = recordCopy
        self._droppedRecords = droppedRecords
        self._timestampMono = timestampMono
        self._estimatedBytes = totalBytes
    }

    static TelemetryBatch of(TelemetryKind kind, Map<String, String> resource,
                             List<TelemetryRecord> records) {
        return new TelemetryBatch(kind, resource, records, 0, nowMono())
    }

    TelemetryKind kind() { return self._kind }
    Map<String, String> resource() { return agCopyStringMap(self._resource) }
    List<TelemetryRecord> records() { return self._records.copy() }
    Int recordCount() { return self._records.length() }
    Bool isEmpty() { return self._records.length() == 0 }
    Int droppedRecords() { return self._droppedRecords }
    Long timestampMono() { return self._timestampMono }
    Long estimatedBytes() { return self._estimatedBytes }

    TelemetryBatch withRecords(List<TelemetryRecord> records) {
        return new TelemetryBatch(self._kind, self._resource, records,
            self._droppedRecords, self._timestampMono)
    }

    TelemetryBatch withAdditionalDropped(Int count) {
        if count < 0 { throw "TelemetryBatch.withAdditionalDropped: negative" }
        if self._droppedRecords > 2147483647 - count {
            throw "TelemetryBatch.withAdditionalDropped: overflow"
        }
        return new TelemetryBatch(self._kind, self._resource, self._records,
            self._droppedRecords + count, self._timestampMono)
    }

    Result<TelemetryBatch, Error> merge(TelemetryBatch other) {
        if other == null { throw "TelemetryBatch.merge: null batch" }
        if other._kind != self._kind {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "TelemetryBatch.merge: kind mismatch"))
        }
        if !agSameResource(self._resource, other._resource) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "TelemetryBatch.merge: resource mismatch"))
        }
        List<TelemetryRecord> merged = self._records.copy()
        Int index = 0
        while index < other._records.length() {
            merged.push(other._records.get(index))
            index = index + 1
        }
        Long earlier = self._timestampMono
        if other._timestampMono < earlier { earlier = other._timestampMono }
        return Ok(new TelemetryBatch(self._kind, self._resource, merged,
            self._droppedRecords + other._droppedRecords, earlier))
    }

    List<TelemetryBatch> split(Int maximumRecords) {
        if maximumRecords <= 0 {
            throw "TelemetryBatch.split: maximumRecords <= 0"
        }
        List<TelemetryBatch> result = []
        if self._records.length() == 0 { return result }
        Int offset = 0
        while offset < self._records.length() {
            Int end = offset + maximumRecords
            if end > self._records.length() { end = self._records.length() }
            List<TelemetryRecord> slice = []
            Int index = offset
            while index < end {
                slice.push(self._records.get(index))
                index = index + 1
            }
            Int dropped = 0
            if offset == 0 { dropped = self._droppedRecords }
            result.push(new TelemetryBatch(self._kind, self._resource, slice, dropped,
                self._timestampMono))
            offset = end
        }
        return result
    }

    String describe() {
        return telemetryKindName(self._kind) + " records=" +
            str(self._records.length()) + " dropped=" + str(self._droppedRecords) +
            " bytes=" + str(self._estimatedBytes)
    }
}

// ---------- 管线协议 ----------
protocol Receiver {
    TelemetryKind kind();
    String name();
    Result<Unit, Error> start(Context context,
        Result<Unit, Error>(TelemetryBatch) downstream);
    Result<Unit, Error> stop(Context context);
    Result<Unit, Error> drain(Context context);
    Result<Unit, Error> close();
    Bool isRunning();
    Bool isHealthy();
}

protocol Processor {
    TelemetryKind kind();
    String name();
    Result<Unit, Error> start(Context context,
        Result<Unit, Error>(TelemetryBatch) downstream);
    Result<Unit, Error> process(Context context, TelemetryBatch batch);
    Result<Unit, Error> drain(Context context);
    Result<Unit, Error> close();
    Bool isHealthy();
}

protocol PipelineExporter {
    TelemetryKind kind();
    String name();
    Result<Unit, Error> start(Context context);
    Result<Unit, Error> export(Context context, TelemetryBatch batch);
    Result<Unit, Error> drain(Context context);
    Result<Unit, Error> close();
    Bool isHealthy();
}

protocol Connector {
    String name();
    TelemetryKind inputKind();
    TelemetryKind outputKind();
    Result<Unit, Error> start(Context context,
        Result<Unit, Error>(TelemetryBatch) downstream);
    Result<Unit, Error> consume(Context context, TelemetryBatch batch);
    Result<Unit, Error> drain(Context context);
    Result<Unit, Error> close();
    Bool isHealthy();
}

// ---------- AgentHealth ----------
class AgentHealth implements HealthCheck {
    final String _name
    final String _serviceName
    final Int _pipelineCount
    final RuntimeMonitor _monitor
    HealthState _state
    String _message
    Long _startedMono
    Long _updatedMono
    Int _readyPipelines
    Int _droppedBatches
    Int _failedOperations
    String _lastError

    AgentHealth(String name, String serviceName, Int pipelineCount) {
        if name == null || name == "" { throw "AgentHealth: empty name" }
        if serviceName == null || serviceName == "" {
            throw "AgentHealth: empty serviceName"
        }
        if pipelineCount < 0 { throw "AgentHealth: negative pipeline count" }
        self._name = name
        self._serviceName = serviceName
        self._pipelineCount = pipelineCount
        self._monitor = new RuntimeMonitor()
        self._state = HealthState.Unhealthy
        self._message = "not started"
        self._startedMono = 0 as Long
        self._updatedMono = nowMono()
        self._readyPipelines = 0
        self._droppedBatches = 0
        self._failedOperations = 0
        self._lastError = ""
    }

    String name() { return self._name }

    HealthReport check() {
        self._monitor.enter()
        HealthState state = self._state
        String message = self._message
        Long timestampMono = nowMono()
        Int ready = self._readyPipelines
        Int dropped = self._droppedBatches
        Int failed = self._failedOperations
        String lastError = self._lastError
        self._monitor.exit()
        Map<String, String> details = [:]
        details.put("service", agSingleLine(self._serviceName))
        details.put("pipelinesReady", str(ready))
        details.put("pipelinesTotal", str(self._pipelineCount))
        details.put("droppedBatches", str(dropped))
        details.put("failedOperations", str(failed))
        details.put("lastError", agSingleLine(lastError))
        return new HealthReport(state, message, timestampMono, details)
    }

    Bool isReady() {
        self._monitor.enter()
        HealthState state = self._state
        Int ready = self._readyPipelines
        self._monitor.exit()
        return healthStateIsReady(state) && ready == self._pipelineCount
    }

    Bool isLive() {
        self._monitor.enter()
        HealthState state = self._state
        self._monitor.exit()
        return state != HealthState.Stopped
    }

    HealthState state() {
        self._monitor.enter()
        HealthState value = self._state
        self._monitor.exit()
        return value
    }

    String message() {
        self._monitor.enter()
        String value = self._message
        self._monitor.exit()
        return value
    }

    Int pipelineCount() { return self._pipelineCount }

    Int readyPipelines() {
        self._monitor.enter()
        Int value = self._readyPipelines
        self._monitor.exit()
        return value
    }

    Int droppedBatches() {
        self._monitor.enter()
        Int value = self._droppedBatches
        self._monitor.exit()
        return value
    }

    Int failedOperations() {
        self._monitor.enter()
        Int value = self._failedOperations
        self._monitor.exit()
        return value
    }

    String lastError() {
        self._monitor.enter()
        String value = self._lastError
        self._monitor.exit()
        return value
    }

    Long startedMono() {
        self._monitor.enter()
        Long value = self._startedMono
        self._monitor.exit()
        return value
    }

    Long updatedMono() {
        self._monitor.enter()
        Long value = self._updatedMono
        self._monitor.exit()
        return value
    }

    Void markStarted() {
        self._monitor.enter()
        if self._state == HealthState.Stopped {
            self._monitor.exit()
            return
        }
        if self._startedMono == 0 as Long { self._startedMono = nowMono() }
        self._state = HealthState.Starting
        self._message = "starting"
        self._updatedMono = nowMono()
        self._monitor.exit()
    }

    Void markReady(Int readyPipelines) {
        self._monitor.enter()
        if readyPipelines < 0 || readyPipelines > self._pipelineCount {
            self._monitor.exit()
            throw "AgentHealth.markReady: ready out of range"
        }
        self._state = HealthState.Healthy
        self._readyPipelines = readyPipelines
        self._message = "ready"
        self._updatedMono = nowMono()
        self._monitor.exit()
    }

    Void markUnhealthy(String message) {
        if message == null { throw "AgentHealth.markUnhealthy: null" }
        self._monitor.enter()
        self._state = HealthState.Unhealthy
        self._message = agSingleLine(message)
        self._failedOperations = self._failedOperations + 1
        self._lastError = agTruncate(agSingleLine(message), 256)
        self._updatedMono = nowMono()
        self._monitor.exit()
    }

    Void markStopped() {
        self._monitor.enter()
        self._state = HealthState.Stopped
        self._readyPipelines = 0
        self._message = "stopped"
        self._updatedMono = nowMono()
        self._monitor.exit()
    }

    Void recordDrop(Int count) {
        if count < 0 { throw "AgentHealth.recordDrop: negative" }
        if count == 0 { return }
        self._monitor.enter()
        if self._droppedBatches > 2147483647 - count {
            self._monitor.exit()
            throw "AgentHealth.recordDrop: overflow"
        }
        self._droppedBatches = self._droppedBatches + count
        if self._state == HealthState.Healthy { self._state = HealthState.Degraded }
        self._message = "dropped batches"
        self._updatedMono = nowMono()
        self._monitor.exit()
    }

    Void recordFailure(Error error) {
        if error == null { throw "AgentHealth.recordFailure: null" }
        self._monitor.enter()
        self._failedOperations = self._failedOperations + 1
        self._lastError = agTruncate(agSingleLine(error.describe()), 256)
        if self._state == HealthState.Healthy { self._state = HealthState.Degraded }
        if self._state == HealthState.Starting { self._state = HealthState.Unhealthy }
        self._message = "operation failed"
        self._updatedMono = nowMono()
        self._monitor.exit()
    }

    String describe() {
        self._monitor.enter()
        HealthState state = self._state
        Int ready = self._readyPipelines
        Int dropped = self._droppedBatches
        Int failed = self._failedOperations
        self._monitor.exit()
        return "agent " + self._name + " " + healthStateName(state) + " ready=" +
            str(ready) + "/" + str(self._pipelineCount) + " dropped=" +
            str(dropped) + " failed=" + str(failed)
    }
}

// ---------- helpers ----------
static Map<String, String> agCopyStringMap(Map<String, String> source) {
    Map<String, String> result = [:]
    List<String> keys = source.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        result.put(key, source.getOr(key, ""))
        index = index + 1
    }
    return result
}

static Bool agSameResource(Map<String, String> left, Map<String, String> right) {
    if left.length() != right.length() { return false }
    List<String> keys = left.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        if !right.has(key) { return false }
        if left.getOr(key, "") != right.getOr(key, "") { return false }
        index = index + 1
    }
    return true
}

static String agSingleLine(String text) {
    if text == null { return "" }
    return text.replace("\n", " ").replace("\r", " ").replace("\t", " ")
}

static String agTruncate(String text, Int maximum) {
    if text.length() <= maximum { return text }
    return text.substring(0, maximum)
}
