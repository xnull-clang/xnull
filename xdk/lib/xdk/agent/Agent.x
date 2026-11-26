// xdk.agent —— 遥测核心与协议（M25.1）
//
// 实现 TelemetryKind/TelemetryRecord/TelemetryBatch/Receiver/Processor/
// PipelineExporter/Connector/AgentHealth；AgentPipeline/AgentConfig/Agent 留 M25.2/M25.3。
package xdk.agent
import xdk.errors
import xdk.codec
import xdk.metrics
import xdk.trace
import xdk.log
import xdk.runtime
import xdk.time
import xdk.os.memory
import xdk.net.http
import xdk.net.uri

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

// ---------- AgentPipeline ----------
class AgentPipeline {
    final String _name
    final TelemetryKind _kind
    final List<Receiver> _receivers
    final List<Processor> _processors
    final List<PipelineExporter> _exporters
    final List<Connector> _inputConnectors
    final List<Connector> _outputConnectors
    final RuntimeMonitor _monitor
    Context? _context
    Bool _starting
    Bool _failed
    Bool _started
    Bool _running
    Bool _draining
    Bool _closed
    Bool _closeFailed
    String _closeMessage

    AgentPipeline(String name, TelemetryKind kind, List<Receiver> receivers,
                  List<Processor> processors, List<PipelineExporter> exporters,
                  List<Connector> inputConnectors,
                  List<Connector> outputConnectors) {
        if name == null || name == "" { throw "AgentPipeline: empty name" }
        if name.indexOf("\n") >= 0 || name.indexOf("\t") >= 0 {
            throw "AgentPipeline: invalid name"
        }
        if kind == TelemetryKind.Unknown { throw "AgentPipeline: invalid kind" }
        if receivers == null || processors == null || exporters == null ||
            inputConnectors == null || outputConnectors == null {
            throw "AgentPipeline: null component list"
        }
        if receivers.length() + inputConnectors.length() == 0 {
            throw "AgentPipeline: no source"
        }
        if exporters.length() + outputConnectors.length() == 0 {
            throw "AgentPipeline: no sink"
        }
        List<Receiver> receiverCopy = []
        Int index = 0
        while index < receivers.length() {
            Receiver receiver = receivers.get(index)
            if receiver == null { throw "AgentPipeline: null receiver" }
            if receiver.kind() != kind {
                throw "AgentPipeline: receiver kind mismatch"
            }
            receiverCopy.push(receiver)
            index = index + 1
        }
        List<Processor> processorCopy = []
        index = 0
        while index < processors.length() {
            Processor processor = processors.get(index)
            if processor == null { throw "AgentPipeline: null processor" }
            if processor.kind() != kind {
                throw "AgentPipeline: processor kind mismatch"
            }
            processorCopy.push(processor)
            index = index + 1
        }
        List<PipelineExporter> exporterCopy = []
        index = 0
        while index < exporters.length() {
            PipelineExporter exporter = exporters.get(index)
            if exporter == null { throw "AgentPipeline: null exporter" }
            if exporter.kind() != kind {
                throw "AgentPipeline: exporter kind mismatch"
            }
            exporterCopy.push(exporter)
            index = index + 1
        }
        List<Connector> inputCopy = []
        index = 0
        while index < inputConnectors.length() {
            Connector connector = inputConnectors.get(index)
            if connector == null { throw "AgentPipeline: null input connector" }
            if connector.outputKind() != kind {
                throw "AgentPipeline: input connector kind mismatch"
            }
            inputCopy.push(connector)
            index = index + 1
        }
        List<Connector> outputCopy = []
        index = 0
        while index < outputConnectors.length() {
            Connector connector = outputConnectors.get(index)
            if connector == null { throw "AgentPipeline: null output connector" }
            if connector.inputKind() != kind {
                throw "AgentPipeline: output connector kind mismatch"
            }
            outputCopy.push(connector)
            index = index + 1
        }
        self._name = name
        self._kind = kind
        self._receivers = receiverCopy
        self._processors = processorCopy
        self._exporters = exporterCopy
        self._inputConnectors = inputCopy
        self._outputConnectors = outputCopy
        self._monitor = new RuntimeMonitor()
        self._context = null
        self._starting = false
        self._failed = false
        self._started = false
        self._running = false
        self._draining = false
        self._closed = false
        self._closeFailed = false
        self._closeMessage = ""
    }

    String name() { return self._name }
    TelemetryKind kind() { return self._kind }
    Int receiverCount() { return self._receivers.length() }
    Int processorCount() { return self._processors.length() }
    Int exporterCount() { return self._exporters.length() }
    Int inputConnectorCount() { return self._inputConnectors.length() }
    Int outputConnectorCount() { return self._outputConnectors.length() }
    Bool isRunning() { return self._running }
    Bool isClosed() { return self._closed }
    List<Receiver> receivers() { return self._receivers.copy() }
    List<Processor> processors() { return self._processors.copy() }
    List<PipelineExporter> exporters() { return self._exporters.copy() }
    List<Connector> inputConnectors() { return self._inputConnectors.copy() }
    List<Connector> outputConnectors() { return self._outputConnectors.copy() }

    Result<Unit, Error> start(Context context) {
        if context == null { throw "AgentPipeline.start: null context" }
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "pipeline closed"))
        }
        if self._started {
            self._monitor.exit()
            return Ok()
        }
        if self._starting {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "pipeline starting"))
        }
        self._starting = true
        self._failed = false
        Context internal = Context.withCancel(context)
        self._context = internal
        self._monitor.exit()
        Int exporterIndex = 0
        while exporterIndex < self._exporters.length() {
            Result<Unit, Error> started = self._exporters.get(exporterIndex).start(internal)
            if started.isErr() {
                self.closeStartedExporters(exporterIndex)
                self.failStart(internal)
                return started
            }
            exporterIndex = exporterIndex + 1
        }
        Result<Unit, Error>(TelemetryBatch) downstream = self.bindDelivery(internal)
        Int processorIndex = self._processors.length() - 1
        Int startedProcessors = 0
        while processorIndex >= 0 {
            Processor processor = self._processors.get(processorIndex)
            Result<Unit, Error> started = processor.start(internal, downstream)
            if started.isErr() {
                self.closeStartedProcessors(startedProcessors)
                self.closeStartedExporters(self._exporters.length())
                self.failStart(internal)
                return started
            }
            downstream = self.bindProcessor(internal, processor)
            startedProcessors = startedProcessors + 1
            processorIndex = processorIndex - 1
        }
        Result<Unit, Error>(TelemetryBatch) consumeDownstream = self.bindConsume(internal)
        Int receiverIndex = 0
        while receiverIndex < self._receivers.length() {
            Result<Unit, Error> started = self._receivers.get(receiverIndex).start(
                internal, consumeDownstream)
            if started.isErr() {
                self.closeStartedReceivers(receiverIndex)
                self.closeStartedProcessors(self._processors.length())
                self.closeStartedExporters(self._exporters.length())
                self.failStart(internal)
                return started
            }
            receiverIndex = receiverIndex + 1
        }
        self._monitor.enter()
        self._starting = false
        self._started = true
        self._running = true
        self._monitor.exit()
        return Ok()
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "AgentPipeline.stop: null context" }
        self._monitor.enter()
        if self._starting || self._draining {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "pipeline transitioning"))
        }
        if self._closed || !self._running {
            self._monitor.exit()
            return Ok()
        }
        self._running = false
        self._monitor.exit()
        Result<Unit, Error> first = Ok()
        Int index = 0
        while index < self._receivers.length() {
            Result<Unit, Error> stopped = self._receivers.get(index).stop(context)
            if stopped.isErr() && first.isOk() { first = stopped }
            index = index + 1
        }
        return first
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "AgentPipeline.drain: null context" }
        self._monitor.enter()
        if self._starting {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "pipeline starting"))
        }
        if self._closed {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "pipeline closed"))
        }
        if self._draining {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "pipeline draining"))
        }
        self._draining = true
        self._monitor.exit()
        Result<Unit, Error> first = Ok()
        Int index = 0
        while index < self._receivers.length() {
            Result<Unit, Error> drained = self._receivers.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < self._processors.length() {
            Result<Unit, Error> drained = self._processors.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < self._exporters.length() {
            Result<Unit, Error> drained = self._exporters.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        self._monitor.enter()
        self._draining = false
        self._monitor.exit()
        return first
    }

    Result<Unit, Error> close() {
        self._monitor.enter()
        if self._starting || self._draining {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "pipeline transitioning"))
        }
        if self._closed {
            Bool failed = self._closeFailed
            String message = self._closeMessage
            self._monitor.exit()
            if failed { return Err(new BasicError(ErrorKind.Io, message)) }
            return Ok()
        }
        self._closed = true
        self._running = false
        self._starting = false
        if self._context != null {
            Context internal = self._context as Context
            internal.cancel()
        }
        self._monitor.exit()
        Result<Unit, Error> first = Ok()
        Int index = 0
        while index < self._receivers.length() {
            Result<Unit, Error> closed = self._receivers.get(index).close()
            if closed.isErr() && first.isOk() { first = closed }
            index = index + 1
        }
        index = 0
        while index < self._processors.length() {
            Result<Unit, Error> closed = self._processors.get(index).close()
            if closed.isErr() && first.isOk() { first = closed }
            index = index + 1
        }
        index = 0
        while index < self._exporters.length() {
            Result<Unit, Error> closed = self._exporters.get(index).close()
            if closed.isErr() && first.isOk() { first = closed }
            index = index + 1
        }
        self._monitor.enter()
        if first.isErr() {
            self._closeFailed = true
            self._closeMessage = first.error().describe()
        }
        self._monitor.exit()
        return first
    }

    Result<Unit, Error> consume(Context context, TelemetryBatch batch) {
        if context == null { throw "AgentPipeline.consume: null context" }
        if batch == null { throw "AgentPipeline.consume: null batch" }
        if batch.kind() != self._kind {
            throw "AgentPipeline.consume: batch kind mismatch"
        }
        self._monitor.enter()
        if self._closed || !self._started {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable,
                "pipeline not started"))
        }
        Result<Unit, Error> result = Ok()
        if self._processors.length() == 0 {
            result = self.deliver(context, batch)
        } else {
            result = self._processors.get(0).process(context, batch)
        }
        self._monitor.exit()
        return result
    }

    Result<Unit, Error> deliver(Context context, TelemetryBatch batch) {
        Result<Unit, Error> first = Ok()
        Int index = 0
        while index < self._exporters.length() {
            Result<Unit, Error> exported = self._exporters.get(index).export(context, batch)
            if exported.isErr() && first.isOk() { first = exported }
            index = index + 1
        }
        index = 0
        while index < self._outputConnectors.length() {
            Result<Unit, Error> consumed = self._outputConnectors.get(index).consume(
                context, batch)
            if consumed.isErr() && first.isOk() { first = consumed }
            index = index + 1
        }
        return first
    }

    Result<Unit, Error>(TelemetryBatch) bindProcessor(Context context,
                                                       Processor processor) {
        return (TelemetryBatch batch) -> processor.process(context, batch)
    }

    Result<Unit, Error>(TelemetryBatch) bindDelivery(Context context) {
        return (TelemetryBatch batch) -> self.deliver(context, batch)
    }

    Result<Unit, Error>(TelemetryBatch) bindConsume(Context context) {
        return (TelemetryBatch batch) -> self.consume(context, batch)
    }

    private Void failStart(Context internal) {
        self._monitor.enter()
        self._starting = false
        self._failed = true
        internal.cancel()
        self._monitor.exit()
    }

    private Void closeStartedExporters(Int count) {
        Int index = 0
        while index < count {
            self._exporters.get(index).close()
            index = index + 1
        }
    }

    private Void closeStartedProcessors(Int count) {
        Int index = self._processors.length() - count
        while index < self._processors.length() {
            self._processors.get(index).close()
            index = index + 1
        }
    }

    private Void closeStartedReceivers(Int count) {
        Int index = 0
        while index < count {
            self._receivers.get(index).close()
            index = index + 1
        }
    }

    HealthReport health() {
        if self._closed {
            return agHealth(HealthState.Stopped, "pipeline closed")
        }
        if self._failed {
            return agHealth(HealthState.Unhealthy, "pipeline start failed")
        }
        if !self._running {
            if self._started {
                return agHealth(HealthState.Stopped, "pipeline stopped")
            }
            return agHealth(HealthState.Starting, "pipeline not running")
        }
        Bool healthy = true
        Int index = 0
        while index < self._receivers.length() {
            if !self._receivers.get(index).isHealthy() { healthy = false }
            index = index + 1
        }
        index = 0
        while index < self._processors.length() {
            if !self._processors.get(index).isHealthy() { healthy = false }
            index = index + 1
        }
        index = 0
        while index < self._exporters.length() {
            if !self._exporters.get(index).isHealthy() { healthy = false }
            index = index + 1
        }
        if !healthy {
            return agHealth(HealthState.Unhealthy, "component unhealthy")
        }
        return agHealth(HealthState.Healthy, "pipeline running")
    }

    String describe() {
        return self._name + " " + telemetryKindName(self._kind) + " receivers=" +
            str(self._receivers.length()) + " processors=" +
            str(self._processors.length()) + " exporters=" +
            str(self._exporters.length())
    }
}

// ---------- AgentConfig ----------
class AgentConfig {
    final String _serviceName
    final String _instanceName
    final List<AgentPipeline> _pipelines
    final List<Connector> _connectors

    private AgentConfig(String serviceName, String instanceName,
                        List<AgentPipeline> pipelines, List<Connector> connectors) {
        self._serviceName = serviceName
        self._instanceName = instanceName
        self._pipelines = pipelines.copy()
        self._connectors = connectors.copy()
    }

    static Result<AgentConfig, Error> create(String serviceName, String instanceName,
                                              List<AgentPipeline> pipelines,
                                              List<Connector> connectors) {
        if serviceName == null || serviceName == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty serviceName"))
        }
        if instanceName == null || instanceName == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty instanceName"))
        }
        if pipelines == null || connectors == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null config list"))
        }
        if pipelines.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty pipelines"))
        }
        Result<Unit, Error> valid = agValidateConfig(pipelines, connectors)
        if valid.isErr() { return Err(valid.error()) }
        return Ok(new AgentConfig(serviceName, instanceName, pipelines, connectors))
    }

    static Result<AgentConfig, Error> of(String serviceName,
                                          List<AgentPipeline> pipelines) {
        if pipelines == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null pipelines"))
        }
        List<Connector> noConnectors = []
        return AgentConfig.create(serviceName, "default", pipelines, noConnectors)
    }

    Result<AgentConfig, Error> withPipeline(AgentPipeline pipeline) {
        if pipeline == null { throw "AgentConfig.withPipeline: null" }
        List<AgentPipeline> next = self._pipelines.copy()
        next.push(pipeline)
        return AgentConfig.create(self._serviceName, self._instanceName, next,
            self._connectors)
    }

    Result<AgentConfig, Error> withConnector(Connector connector) {
        if connector == null { throw "AgentConfig.withConnector: null" }
        List<Connector> next = self._connectors.copy()
        next.push(connector)
        return AgentConfig.create(self._serviceName, self._instanceName,
            self._pipelines, next)
    }

    String serviceName() { return self._serviceName }
    String instanceName() { return self._instanceName }
    List<AgentPipeline> pipelines() { return self._pipelines.copy() }
    List<Connector> connectors() { return self._connectors.copy() }

    AgentPipeline? pipeline(String name) {
        if name == null { throw "AgentConfig.pipeline: null name" }
        Int index = 0
        while index < self._pipelines.length() {
            if self._pipelines.get(index).name() == name {
                return self._pipelines.get(index)
            }
            index = index + 1
        }
        return null
    }

    Connector? connector(String name) {
        if name == null { throw "AgentConfig.connector: null name" }
        Int index = 0
        while index < self._connectors.length() {
            if self._connectors.get(index).name() == name {
                return self._connectors.get(index)
            }
            index = index + 1
        }
        return null
    }

    String describe() {
        return "agent config service=" + self._serviceName + " instance=" +
            self._instanceName + " pipelines=" + str(self._pipelines.length()) +
            " connectors=" + str(self._connectors.length())
    }
}

static Result<Unit, Error> agValidateConfig(List<AgentPipeline> pipelines,
                                            List<Connector> connectors) {
    List<String> pipelineNames = []
    Int index = 0
    while index < pipelines.length() {
        AgentPipeline pipeline = pipelines.get(index)
        if pipeline == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null pipeline"))
        }
        if agContainsString(pipelineNames, pipeline.name()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "duplicate pipeline name"))
        }
        pipelineNames.push(pipeline.name())
        index = index + 1
    }
    List<String> connectorNames = []
    index = 0
    while index < connectors.length() {
        Connector connector = connectors.get(index)
        if connector == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null connector"))
        }
        if agContainsString(connectorNames, connector.name()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "duplicate connector name"))
        }
        connectorNames.push(connector.name())
        index = index + 1
    }
    List<Int> inputAttachments = []
    List<Int> outputAttachments = []
    index = 0
    while index < connectors.length() {
        inputAttachments.push(0)
        outputAttachments.push(0)
        index = index + 1
    }
    Int pipelineIndex = 0
    while pipelineIndex < pipelines.length() {
        AgentPipeline pipeline = pipelines.get(pipelineIndex)
        Int inputIndex = 0
        while inputIndex < pipeline.inputConnectors().length() {
            Connector connector = pipeline.inputConnectors().get(inputIndex)
            Int located = agIndexOfString(connectorNames, connector.name())
            if located < 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "pipeline references unlisted connector"))
            }
            inputAttachments.set(located, inputAttachments.get(located) + 1)
            inputIndex = inputIndex + 1
        }
        Int outputIndex = 0
        while outputIndex < pipeline.outputConnectors().length() {
            Connector connector = pipeline.outputConnectors().get(outputIndex)
            Int located = agIndexOfString(connectorNames, connector.name())
            if located < 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "pipeline references unlisted connector"))
            }
            outputAttachments.set(located, outputAttachments.get(located) + 1)
            outputIndex = outputIndex + 1
        }
        pipelineIndex = pipelineIndex + 1
    }
    index = 0
    while index < inputAttachments.length() {
        if inputAttachments.get(index) != 1 ||
            outputAttachments.get(index) != 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "connector must have one input and one output attachment"))
        }
        index = index + 1
    }
    List<Bool> visited = []
    List<Bool> stack = []
    index = 0
    while index < pipelines.length() {
        visited.push(false)
        stack.push(false)
        index = index + 1
    }
    pipelineIndex = 0
    while pipelineIndex < pipelines.length() {
        if agConfigCycle(pipelines, pipelineIndex, visited, stack) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "connector cycle"))
        }
        pipelineIndex = pipelineIndex + 1
    }
    return Ok()
}

static Bool agConfigCycle(List<AgentPipeline> pipelines, Int current,
                          List<Bool> visited, List<Bool> stack) {
    if stack.get(current) { return true }
    if visited.get(current) { return false }
    visited.set(current, true)
    stack.set(current, true)
    AgentPipeline pipeline = pipelines.get(current)
    Int outputIndex = 0
    while outputIndex < pipeline.outputConnectors().length() {
        Connector connector = pipeline.outputConnectors().get(outputIndex)
        Int nextIndex = 0
        while nextIndex < pipelines.length() {
            AgentPipeline next = pipelines.get(nextIndex)
            Bool consumes = false
            Int inputIndex = 0
            while inputIndex < next.inputConnectors().length() {
                if next.inputConnectors().get(inputIndex).name() == connector.name() {
                    consumes = true
                }
                inputIndex = inputIndex + 1
            }
            if consumes {
                if agConfigCycle(pipelines, nextIndex, visited, stack) { return true }
            }
            nextIndex = nextIndex + 1
        }
        outputIndex = outputIndex + 1
    }
    stack.set(current, false)
    return false
}

static Result<Unit, Error> agOk() { return Ok() }

static HealthReport agHealth(HealthState state, String message) {
    Map<String, String> details = [:]
    return new HealthReport(state, message, nowMono(), details)
}

static Bool agContainsString(List<String> values, String target) {
    return agIndexOfString(values, target) >= 0
}

static Int agIndexOfString(List<String> values, String target) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == target { return index }
        index = index + 1
    }
    return -1
}

// ---------- Agent ----------
class Agent {
    final AgentConfig _config
    final List<AgentPipeline> _pipelines
    final List<Connector> _connectors
    final AgentHealth _health
    final RuntimeMonitor _monitor
    Context? _context
    Bool _starting
    Bool _started
    Bool _running
    Bool _stopping
    Bool _draining
    Bool _closed
    Bool _stopFailed
    String _stopMessage
    Bool _closeFailed
    String _closeMessage

    Agent(AgentConfig config) {
        if config == null { throw "Agent: null config" }
        self._config = config
        self._pipelines = config.pipelines()
        self._connectors = config.connectors()
        self._health = new AgentHealth("agent/" + config.instanceName(),
            config.serviceName(), self._pipelines.length())
        self._monitor = new RuntimeMonitor()
        self._context = null
        self._starting = false
        self._started = false
        self._running = false
        self._stopping = false
        self._draining = false
        self._closed = false
        self._stopFailed = false
        self._stopMessage = ""
        self._closeFailed = false
        self._closeMessage = ""
    }

    Result<Unit, Error> start(Context context) {
        if context == null { throw "Agent.start: null context" }
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "agent closed"))
        }
        if self._started {
            self._monitor.exit()
            return Ok()
        }
        if self._starting || self._stopping || self._draining {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "agent transitioning"))
        }
        self._starting = true
        Context internal = Context.withCancel(context)
        self._context = internal
        self._health.markStarted()
        self._monitor.exit()
        Int connectorIndex = 0
        while connectorIndex < self._connectors.length() {
            Connector connector = self._connectors.get(connectorIndex)
            AgentPipeline? destination = self.destinationFor(connector)
            if destination == null {
                self.failStart("connector destination missing")
                return Err(new BasicError(ErrorKind.Internal,
                    "connector destination missing"))
            }
            AgentPipeline target = destination as AgentPipeline
            Result<Unit, Error>(TelemetryBatch) downstream =
                self.bindPipeline(internal, target)
            Result<Unit, Error> started = connector.start(internal, downstream)
            if started.isErr() {
                self.closeConnectors(connectorIndex)
                self.failStart(started.error().describe())
                return started
            }
            connectorIndex = connectorIndex + 1
        }
        List<AgentPipeline> order = self.buildStartOrder()
        Int pipelineIndex = 0
        while pipelineIndex < order.length() {
            Result<Unit, Error> started = order.get(pipelineIndex).start(internal)
            if started.isErr() {
                self.closePipelines(order, pipelineIndex)
                self.closeConnectors(self._connectors.length())
                self.failStart(started.error().describe())
                return started
            }
            pipelineIndex = pipelineIndex + 1
        }
        self._monitor.enter()
        self._starting = false
        self._started = true
        self._running = true
        self._health.markReady(self._pipelines.length())
        self._monitor.exit()
        return Ok()
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "Agent.stop: null context" }
        self._monitor.enter()
        if self._closed || !self._started {
            Bool failed = self._stopFailed
            String message = self._stopMessage
            self._monitor.exit()
            if failed { return Err(new BasicError(ErrorKind.Io, message)) }
            self._health.markStopped()
            return Ok()
        }
        if self._starting || self._stopping || self._draining {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "agent transitioning"))
        }
        self._stopping = true
        self._running = false
        self._monitor.exit()
        Result<Unit, Error> first = Ok()
        List<AgentPipeline> startOrder = self.buildStartOrder()
        Int index = 0
        while index < startOrder.length() {
            Result<Unit, Error> stopped = startOrder.get(index).stop(context)
            if stopped.isErr() && first.isOk() { first = stopped }
            index = index + 1
        }
        index = 0
        while index < startOrder.length() {
            Result<Unit, Error> drained = startOrder.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < self._connectors.length() {
            Result<Unit, Error> drained = self._connectors.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < startOrder.length() {
            Result<Unit, Error> drained = startOrder.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < self._connectors.length() {
            Result<Unit, Error> closed = self._connectors.get(index).close()
            if closed.isErr() && first.isOk() { first = closed }
            index = index + 1
        }
        index = 0
        while index < startOrder.length() {
            Result<Unit, Error> closed = startOrder.get(index).close()
            if closed.isErr() && first.isOk() { first = closed }
            index = index + 1
        }
        self._monitor.enter()
        self._stopping = false
        self._started = false
        self._closed = true
        Context? internalValue = self._context
        if internalValue != null {
            Context internal = internalValue as Context
            internal.cancel()
        }
        if first.isErr() {
            self._stopFailed = true
            self._stopMessage = first.error().describe()
            self._closeFailed = true
            self._closeMessage = self._stopMessage
        }
        self._health.markStopped()
        self._monitor.exit()
        return first
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "Agent.drain: null context" }
        self._monitor.enter()
        if self._closed || !self._running {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "agent not running"))
        }
        if self._starting || self._stopping || self._draining {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "agent transitioning"))
        }
        self._draining = true
        self._monitor.exit()
        Result<Unit, Error> first = Ok()
        List<AgentPipeline> startOrder = self.buildStartOrder()
        Int index = 0
        while index < startOrder.length() {
            Result<Unit, Error> drained = startOrder.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < self._connectors.length() {
            Result<Unit, Error> drained = self._connectors.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < startOrder.length() {
            Result<Unit, Error> drained = startOrder.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        self._monitor.enter()
        self._draining = false
        self._monitor.exit()
        return first
    }

    Result<Unit, Error> close() {
        self._monitor.enter()
        if self._starting || self._stopping || self._draining {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "agent transitioning"))
        }
        if self._closed {
            Bool failed = self._closeFailed
            String message = self._closeMessage
            self._monitor.exit()
            if failed { return Err(new BasicError(ErrorKind.Io, message)) }
            return Ok()
        }
        self._closed = true
        self._running = false
        self._starting = false
        self._stopping = false
        Context? internalValue = self._context
        if internalValue != null {
            Context internal = internalValue as Context
            internal.cancel()
        }
        self._monitor.exit()
        Result<Unit, Error> first = Ok()
        Int connectorIndex = 0
        while connectorIndex < self._connectors.length() {
            Result<Unit, Error> closed = self._connectors.get(connectorIndex).close()
            if closed.isErr() && first.isOk() { first = closed }
            connectorIndex = connectorIndex + 1
        }
        List<AgentPipeline> order = self.buildStartOrder()
        Int pipelineIndex = 0
        while pipelineIndex < order.length() {
            Result<Unit, Error> closed = order.get(pipelineIndex).close()
            if closed.isErr() && first.isOk() { first = closed }
            pipelineIndex = pipelineIndex + 1
        }
        self._monitor.enter()
        if first.isErr() {
            self._closeFailed = true
            self._closeMessage = first.error().describe()
            self._stopFailed = true
            self._stopMessage = self._closeMessage
        }
        self._health.markStopped()
        self._monitor.exit()
        return first
    }

    Bool isRunning() { return self._running }
    String serviceName() { return self._config.serviceName() }
    String instanceName() { return self._config.instanceName() }
    List<AgentPipeline> pipelines() { return self._pipelines.copy() }
    List<Connector> connectors() { return self._connectors.copy() }
    AgentHealth health() { return self._health }

    List<AgentPipeline> buildStartOrder() {
        List<AgentPipeline> order = []
        List<String> visited = []
        Int index = 0
        while index < self._pipelines.length() {
            self.visitStart(self._pipelines.get(index), visited, order)
            index = index + 1
        }
        return order
    }

    private Void visitStart(AgentPipeline pipeline, List<String> visited,
                            List<AgentPipeline> order) {
        if agContainsString(visited, pipeline.name()) { return }
        List<Connector> inputs = pipeline.inputConnectors()
        Int index = 0
        while index < inputs.length() {
            AgentPipeline? source = self.sourceFor(inputs.get(index))
            if source != null {
                self.visitStart(source as AgentPipeline, visited, order)
            }
            index = index + 1
        }
        visited.push(pipeline.name())
        order.push(pipeline)
    }

    private AgentPipeline? destinationFor(Connector connector) {
        Int index = 0
        while index < self._pipelines.length() {
            AgentPipeline pipeline = self._pipelines.get(index)
            List<Connector> inputs = pipeline.inputConnectors()
            Int inputIndex = 0
            while inputIndex < inputs.length() {
                if inputs.get(inputIndex).name() == connector.name() {
                    return pipeline
                }
                inputIndex = inputIndex + 1
            }
            index = index + 1
        }
        return null
    }

    private AgentPipeline? sourceFor(Connector connector) {
        Int index = 0
        while index < self._pipelines.length() {
            AgentPipeline pipeline = self._pipelines.get(index)
            List<Connector> outputs = pipeline.outputConnectors()
            Int outputIndex = 0
            while outputIndex < outputs.length() {
                if outputs.get(outputIndex).name() == connector.name() {
                    return pipeline
                }
                outputIndex = outputIndex + 1
            }
            index = index + 1
        }
        return null
    }

    private List<AgentPipeline> reverse(List<AgentPipeline> values) {
        List<AgentPipeline> result = []
        Int index = values.length() - 1
        while index >= 0 {
            result.push(values.get(index))
            index = index - 1
        }
        return result
    }

    private Result<Unit, Error>(TelemetryBatch) bindPipeline(Context context,
                                                              AgentPipeline pipeline) {
        return (TelemetryBatch batch) -> pipeline.consume(context, batch)
    }

    private Void failStart(String message) {
        self._monitor.enter()
        self._starting = false
        self._started = false
        self._running = false
        Context? internalValue = self._context
        if internalValue != null {
            Context internal = internalValue as Context
            internal.cancel()
        }
        self._health.markUnhealthy(message)
        self._monitor.exit()
    }

    private Void closeConnectors(Int count) {
        Int index = 0
        while index < count {
            self._connectors.get(index).close()
            index = index + 1
        }
    }

    private Void closePipelines(List<AgentPipeline> order, Int count) {
        Int index = count - 1
        while index >= 0 {
            order.get(index).close()
            index = index - 1
        }
    }

    String describe() {
        return "agent " + self._config.serviceName() + "/" +
            self._config.instanceName() + " pipelines=" +
            str(self._pipelines.length()) + " connectors=" +
            str(self._connectors.length()) + " running=" + str(self._running)
    }
}

// ---------- BatchProcessor ----------
class BatchProcessor implements Processor {
    final String _name
    final TelemetryKind _kind
    final Int _sendBatchSize
    final Long _timeoutMillis
    final Int _sendBatchMaxSize
    final Int _maximumPendingRecords
    final String _overflowPolicy
    final RuntimeMonitor _monitor
    final List<TelemetryBatch> _pending
    Int _pendingRecords
    Int _droppedRecords
    Int _sentBatches
    Bool _started
    Bool _closed
    Bool _flushing
    Result<Unit, Error>(TelemetryBatch) _downstream
    Bool _hasDownstream
    Context? _context
    TaskGroup? _group

    BatchProcessor(String name, TelemetryKind kind, Int sendBatchSize, Long timeoutMillis,
                   Int sendBatchMaxSize, Int maximumPendingRecords, String overflowPolicy) {
        if name == null || name == "" { throw "BatchProcessor: empty name" }
        if kind == null || kind == TelemetryKind.Unknown { throw "BatchProcessor: invalid kind" }
        if sendBatchSize <= 0 { throw "BatchProcessor: invalid batch size" }
        if timeoutMillis < 0 as Long { throw "BatchProcessor: negative timeout" }
        if sendBatchMaxSize != 0 && sendBatchMaxSize < sendBatchSize {
            throw "BatchProcessor: invalid max size"
        }
        if maximumPendingRecords < sendBatchSize {
            throw "BatchProcessor: invalid pending limit"
        }
        if overflowPolicy != "reject" && overflowPolicy != "drop_oldest" &&
            overflowPolicy != "drop_newest" {
            throw "BatchProcessor: invalid overflow policy"
        }
        self._name = name
        self._kind = kind
        self._sendBatchSize = sendBatchSize
        self._timeoutMillis = timeoutMillis
        self._sendBatchMaxSize = sendBatchMaxSize
        self._maximumPendingRecords = maximumPendingRecords
        self._overflowPolicy = overflowPolicy
        self._monitor = new RuntimeMonitor()
        List<TelemetryBatch> pending = []
        self._pending = pending
        self._pendingRecords = 0
        self._droppedRecords = 0
        self._sentBatches = 0
        self._started = false
        self._closed = false
        self._flushing = false
        self._hasDownstream = false
        self._context = null
        self._group = null
    }

    TelemetryKind kind() { return self._kind }
    String name() { return self._name }

    Result<Unit, Error> start(Context context,
            Result<Unit, Error>(TelemetryBatch) downstream) {
        if context == null { throw "BatchProcessor.start: null context" }
        if self._closed { return Err(new BasicError(ErrorKind.Unavailable, "batch processor closed")) }
        if self._started { return Ok() }
        self._downstream = downstream
        self._hasDownstream = true
        Context child = Context.withCancel(context)
        self._context = child
        self._started = true
        return Ok()
    }

    Result<Unit, Error> process(Context context, TelemetryBatch batch) {
        if context == null || batch == null { throw "BatchProcessor.process: null argument" }
        if self._closed || !self._started {
            return Err(new BasicError(ErrorKind.Unavailable, "batch processor not running"))
        }
        if batch.kind() != self._kind {
            return Err(new BasicError(ErrorKind.InvalidArgument, "batch processor kind mismatch"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "batch processor cancelled"))
        }
        Int incoming = batch.recordCount()
        if self._pendingRecords + incoming > self._maximumPendingRecords {
            if self._overflowPolicy == "reject" {
                return Err(new BasicError(ErrorKind.Busy, "batch processor buffer full"))
            }
            if self._overflowPolicy == "drop_newest" {
                self._droppedRecords = self._droppedRecords + incoming
                return Ok()
            }
            while self._pending.length() > 0 &&
                self._pendingRecords + incoming > self._maximumPendingRecords {
                TelemetryBatch removed = self._pending.get(0)
                self._pending.remove(0)
                self._pendingRecords = self._pendingRecords - removed.recordCount()
                self._droppedRecords = self._droppedRecords + removed.recordCount()
            }
        }
        self._pending.push(batch)
        self._pendingRecords = self._pendingRecords + incoming
        if self._pendingRecords >= self._sendBatchSize || self._timeoutMillis == 0 as Long {
            return self.flush(context)
        }
        return Ok()
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "BatchProcessor.drain: null context" }
        if self._closed || !self._started {
            return Err(new BasicError(ErrorKind.Unavailable, "batch processor not running"))
        }
        return self.flush(context)
    }

    Result<Unit, Error> flush(Context context) {
        if self._closed || !self._started {
            return Err(new BasicError(ErrorKind.Unavailable, "batch processor not running"))
        }
        if self._flushing { return Ok() }
        self._flushing = true
        while self._pending.length() > 0 {
            TelemetryBatch batch = self._pending.get(0)
            List<TelemetryBatch> chunks = []
            if self._sendBatchMaxSize == 0 {
                chunks.push(batch)
            } else {
                chunks = batch.split(self._sendBatchMaxSize)
            }
            Int index = 0
            while index < chunks.length() {
                Result<Unit, Error> sent = self.deliver(context, chunks.get(index))
                if sent.isErr() {
                    self._flushing = false
                    return Err(sent.error())
                }
                index = index + 1
            }
            self._pending.remove(0)
            self._pendingRecords = self._pendingRecords - batch.recordCount()
            self._sentBatches = self._sentBatches + chunks.length()
        }
        self._flushing = false
        return Ok()
    }

    private Result<Unit, Error> deliver(Context context, TelemetryBatch batch) {
        if !self._hasDownstream {
            return Err(new BasicError(ErrorKind.Unavailable, "batch processor downstream missing"))
        }
        return self._downstream(batch)
    }

    Result<Unit, Error> close() {
        if self._closed { return Ok() }
        self._closed = true
        self._started = false
        if self._context != null {
            Context context = self._context as Context
            context.cancel()
        }
        self._droppedRecords = self._droppedRecords + self._pendingRecords
        self._pending.clear()
        self._pendingRecords = 0
        self._hasDownstream = false
        return Ok()
    }

    Bool isHealthy() { return self._started && !self._closed }
    Int pendingRecords() { return self._pendingRecords }
    Int droppedRecords() { return self._droppedRecords }
    Int sentBatches() { return self._sentBatches }
    String describe() { return "batch processor " + self._name + " kind=" + telemetryKindName(self._kind) }
}

// ---------- MemoryLimiterProcessor ----------
class MemoryLimiterProcessor implements Processor {
    final String _name
    final TelemetryKind _kind
    final Long _checkIntervalMillis
    final Long _hostTotalBytes
    final Long _hardLimitBytes
    final Long _softLimitBytes
    final Bool _dropWhenLimited
    final RuntimeMonitor _monitor
    Long _lastCheckMono
    Bool _limited
    Bool _started
    Bool _closed
    Int _refusedBatches
    Int _droppedBatches
    Int _droppedRecords
    Result<Unit, Error>(TelemetryBatch) _downstream
    Bool _hasDownstream
    Context? _context
    TaskGroup? _group

    MemoryLimiterProcessor(String name, TelemetryKind kind, Long checkIntervalMillis,
                           Long limitBytes, Int limitPercentage, Long spikeLimitBytes,
                           Int spikeLimitPercentage, Bool dropWhenLimited) {
        if name == null || name == "" { throw "MemoryLimiterProcessor: empty name" }
        if kind == null || kind == TelemetryKind.Unknown { throw "MemoryLimiterProcessor: invalid kind" }
        if checkIntervalMillis <= 0 as Long { throw "MemoryLimiterProcessor: invalid interval" }
        PhysicalMemory host = PhysicalMemory.detect()
        Long total = host.totalBytes()
        Long hard = limitBytes
        if hard <= 0 as Long {
            if limitPercentage < 1 || limitPercentage > 100 {
                throw "MemoryLimiterProcessor: invalid limit"
            }
            hard = total * (limitPercentage as Long) / 100 as Long
        }
        Long spike = spikeLimitBytes
        if spike <= 0 as Long {
            if spikeLimitPercentage > 0 {
                spike = hard * (spikeLimitPercentage as Long) / 100 as Long
            } else {
                spike = hard / 5 as Long
            }
        }
        Long soft = hard - spike
        if hard <= 0 as Long || soft <= 0 as Long || spike >= hard {
            throw "MemoryLimiterProcessor: invalid soft/hard limit"
        }
        self._name = name
        self._kind = kind
        self._checkIntervalMillis = checkIntervalMillis
        self._hostTotalBytes = total
        self._hardLimitBytes = hard
        self._softLimitBytes = soft
        self._dropWhenLimited = dropWhenLimited
        self._monitor = new RuntimeMonitor()
        self._lastCheckMono = 0 as Long
        self._limited = false
        self._started = false
        self._closed = false
        self._refusedBatches = 0
        self._droppedBatches = 0
        self._droppedRecords = 0
        self._hasDownstream = false
        self._context = null
        self._group = null
    }

    TelemetryKind kind() { return self._kind }
    String name() { return self._name }

    Result<Unit, Error> start(Context context,
            Result<Unit, Error>(TelemetryBatch) downstream) {
        if context == null { throw "MemoryLimiterProcessor.start: null context" }
        if self._closed { return Err(new BasicError(ErrorKind.Unavailable, "memory limiter closed")) }
        if self._started { return Ok() }
        self._downstream = downstream
        self._hasDownstream = true
        Context child = Context.withCancel(context)
        self._context = child
        self._started = true
        return Ok()
    }

    Result<Unit, Error> process(Context context, TelemetryBatch batch) {
        if context == null || batch == null { throw "MemoryLimiterProcessor.process: null argument" }
        if self._closed || !self._started {
            return Err(new BasicError(ErrorKind.Unavailable, "memory limiter not running"))
        }
        if batch.kind() != self._kind {
            return Err(new BasicError(ErrorKind.InvalidArgument, "memory limiter kind mismatch"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "memory limiter cancelled"))
        }
        Long now = nowMono()
        if now - self._lastCheckMono >= self._checkIntervalMillis {
            self.checkNow()
        }
        if self._limited {
            if self._dropWhenLimited {
                self._droppedBatches = self._droppedBatches + 1
                self._droppedRecords = self._droppedRecords + batch.recordCount()
                return Ok()
            }
            self._refusedBatches = self._refusedBatches + 1
            return Err(new BasicError(ErrorKind.Busy, "memory limiter active"))
        }
        if !self._hasDownstream {
            return Err(new BasicError(ErrorKind.Unavailable, "memory limiter downstream missing"))
        }
        return self._downstream(batch)
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "MemoryLimiterProcessor.drain: null context" }
        if self._closed || !self._started {
            return Err(new BasicError(ErrorKind.Unavailable, "memory limiter not running"))
        }
        return Ok()
    }

    Bool checkNow() {
        self._lastCheckMono = nowMono()
        PhysicalMemory host = PhysicalMemory.detect()
        Long total = host.totalBytes()
        if total <= 0 as Long { total = self._hostTotalBytes }
        Long used = total - host.availableBytes()
        if used < 0 as Long { used = 0 as Long }
        self._limited = used >= self._softLimitBytes
        return self._limited
    }

    Bool isLimited() { return self._limited }
    Long currentUsageBytes() {
        PhysicalMemory host = PhysicalMemory.detect()
        Long total = host.totalBytes()
        if total <= 0 as Long { total = self._hostTotalBytes }
        Long used = total - host.availableBytes()
        if used < 0 as Long { return 0 as Long }
        return used
    }
    Long hardLimitBytes() { return self._hardLimitBytes }
    Long softLimitBytes() { return self._softLimitBytes }
    Int refusedBatches() { return self._refusedBatches }
    Int droppedBatches() { return self._droppedBatches }
    Int droppedRecords() { return self._droppedRecords }

    Result<Unit, Error> close() {
        if self._closed { return Ok() }
        self._closed = true
        self._started = false
        if self._context != null {
            Context context = self._context as Context
            context.cancel()
        }
        self._hasDownstream = false
        return Ok()
    }

    Bool isHealthy() { return self._started && !self._closed && !self._limited }
    String describe() { return "memory limiter " + self._name + " kind=" + telemetryKindName(self._kind) }
}

// ---------- PrometheusExporter ----------
protocol AgentWriter {
    Result<Unit, Error> writeAll(Context context, Bytes data);
}

class PrometheusExporter implements PipelineExporter {
    final String _name
    final String _namespace
    final Map<String, String> _constantLabels
    final Long _metricExpirationMillis
    final Bool _sendTimestamps
    final RuntimeMonitor _monitor
    final Map<String, MetricFamily> _families
    final Map<String, Long> _updatedMono
    Bool _started
    Bool _closed

    PrometheusExporter(String name, String namespace, Map<String, String> constantLabels,
                       Long metricExpirationMillis, Bool sendTimestamps) {
        if name == null || name == "" { throw "PrometheusExporter: empty name" }
        if namespace == null { throw "PrometheusExporter: null namespace" }
        if constantLabels == null { throw "PrometheusExporter: null labels" }
        if metricExpirationMillis < 0 as Long { throw "PrometheusExporter: invalid expiration" }
        self._name = name
        self._namespace = namespace
        Map<String, String> labels = [:]
        List<String> keys = constantLabels.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            labels.put(key, constantLabels.getOr(key, ""))
            index = index + 1
        }
        self._constantLabels = labels
        self._metricExpirationMillis = metricExpirationMillis
        self._sendTimestamps = sendTimestamps
        self._monitor = new RuntimeMonitor()
        Map<String, MetricFamily> families = [:]
        self._families = families
        Map<String, Long> updated = [:]
        self._updatedMono = updated
        self._started = false
        self._closed = false
    }

    TelemetryKind kind() { return TelemetryKind.Metrics }
    String name() { return self._name }

    Result<Unit, Error> start(Context context) {
        if context == null { throw "PrometheusExporter.start: null context" }
        if self._closed { return Err(new BasicError(ErrorKind.Unavailable, "prometheus closed")) }
        self._started = true
        return Ok()
    }

    Result<Unit, Error> export(Context context, TelemetryBatch batch) {
        if context == null || batch == null { throw "PrometheusExporter.export: null argument" }
        if self._closed || !self._started {
            return Err(new BasicError(ErrorKind.Unavailable, "prometheus not running"))
        }
        if batch.kind() != TelemetryKind.Metrics {
            return Err(new BasicError(ErrorKind.InvalidArgument, "prometheus needs metrics"))
        }
        Long now = nowMono()
        self._monitor.enter()
        List<TelemetryRecord> records = batch.records()
        Int index = 0
        while index < records.length() {
            MetricFamily? family = records.get(index).metricFamily()
            if family != null {
                MetricFamily actual = family as MetricFamily
                self._families.put(actual.name(), actual)
                self._updatedMono.put(actual.name(), now)
            }
            index = index + 1
        }
        self._monitor.exit()
        return Ok()
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "PrometheusExporter.drain: null context" }
        if self._closed { return Err(new BasicError(ErrorKind.Unavailable, "prometheus closed")) }
        return Ok()
    }

    String scrapeText(Context context) {
        if context == null { throw "PrometheusExporter.scrapeText: null context" }
        if self._closed || !self._started {
            return ""
        }
        Long now = nowMono()
        String text = ""
        self._monitor.enter()
        List<String> keys = self._families.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            MetricFamily family = self._families.getOr(key, null)
            Long updated = self._updatedMono.getOr(key, now)
            Bool expired = self._metricExpirationMillis > 0 as Long &&
                now - updated >= self._metricExpirationMillis
            if !expired {
                text = text + prometheusFamily(family, self._namespace, self._constantLabels,
                    self._sendTimestamps, now)
            }
            index = index + 1
        }
        self._monitor.exit()
        return text
    }

    Result<Unit, Error> scrape(Context context, AgentWriter writer) {
        if context == null || writer == null { throw "PrometheusExporter.scrape: null argument" }
        if self._closed || !self._started {
            return Err(new BasicError(ErrorKind.Unavailable, "prometheus not running"))
        }
        String text = self.scrapeText(context)
        return writer.writeAll(context, Bytes.fromString(text))
    }

    Result<Unit, Error> close() {
        if self._closed { return Ok() }
        self._closed = true
        self._started = false
        self._families.clear()
        self._updatedMono.clear()
        return Ok()
    }

    Bool isHealthy() { return self._started && !self._closed }
    Int familyCount() { return self._families.length() }
    Int sampleCount() {
        Int total = 0
        List<String> keys = self._families.keys()
        Int index = 0
        while index < keys.length() {
            MetricFamily family = self._families.getOr(keys.get(index), null)
            if family != null { total = total + family.samples().length() }
            index = index + 1
        }
        return total
    }
    String describe() { return "prometheus exporter " + self._name }
}

static String prometheusFamily(MetricFamily family, String namespace,
                               Map<String, String> constantLabels,
                               Bool sendTimestamps, Long now) {
    String name = family.name()
    if namespace != "" { name = namespace + "_" + name }
    String type = "gauge"
    if family.kind() == MetricKind.Counter { type = "counter" }
    else if family.kind() == MetricKind.Histogram { type = "histogram" }
    else if family.kind() == MetricKind.Timer { type = "summary" }
    String text = "# HELP " + name + " " + family.help() + "\n"
    text = text + "# TYPE " + name + " " + type + "\n"
    List<MetricSample> samples = family.samples()
    Int index = 0
    while index < samples.length() {
        MetricSample sample = samples.get(index)
        String sampleName = sample.name()
        if sampleName == family.name() { sampleName = name }
        else if sampleName.startsWith(family.name() + "_") {
            sampleName = name + sampleName.substring(family.name().length(),
                sampleName.length() - family.name().length())
        }
        text = text + sampleName + prometheusLabels(constantLabels, sample.labels())
        text = text + " " + prometheusDouble(sample.value())
        if sendTimestamps { text = text + " " + str(now) }
        text = text + "\n"
        index = index + 1
    }
    return text
}

static String prometheusLabels(Map<String, String> constantLabels,
                               Map<String, String> sampleLabels) {
    if constantLabels.length() == 0 && sampleLabels.length() == 0 { return "" }
    String text = "{"
    Bool first = true
    List<String> keys = constantLabels.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        if !first { text = text + "," }
        text = text + key + "=\"" + prometheusEscape(constantLabels.getOr(key, "")) + "\""
        first = false
        index = index + 1
    }
    keys = sampleLabels.keys()
    index = 0
    while index < keys.length() {
        String key = keys.get(index)
        if !first { text = text + "," }
        text = text + key + "=\"" + prometheusEscape(sampleLabels.getOr(key, "")) + "\""
        first = false
        index = index + 1
    }
    return text + "}"
}

static String prometheusEscape(String value) {
    String text = value.replace("\\", "\\\\")
    text = text.replace("\"", "\\\"")
    text = text.replace("\n", "\\n")
    return text
}

static String prometheusDouble(Double value) {
    if isNaN(value) { return "NaN" }
    if value == 1.0 / 0.0 { return "+Inf" }
    if value == 0.0 - 1.0 / 0.0 { return "-Inf" }
    return str(value)
}

static Result<JsonValue, Error> otlpEncode(TelemetryBatch batch) {
    if batch.kind() != TelemetryKind.Metrics {
        return Err(new BasicError(ErrorKind.Unsupported, "otlp encode: only metrics baseline"))
    }
    JsonValue root = Json.object()
    JsonObject rootObject = root.asObject() as JsonObject
    JsonValue resourceMetrics = Json.array()
    JsonArray resourceArray = resourceMetrics.asArray() as JsonArray
    JsonValue resourceMetric = Json.object()
    JsonObject metricObject = resourceMetric.asObject() as JsonObject
    JsonValue resource = Json.object()
    JsonObject resourceObject = resource.asObject() as JsonObject
    JsonValue attributes = Json.array()
    JsonArray attributeArray = attributes.asArray() as JsonArray
    Map<String, String> resourceValues = batch.resource()
    List<String> resourceKeys = resourceValues.keys()
    Int resourceIndex = 0
    while resourceIndex < resourceKeys.length() {
        String key = resourceKeys.get(resourceIndex)
        JsonValue attribute = Json.object()
        JsonObject attributeObject = attribute.asObject() as JsonObject
        attributeObject.set("key", Json.string(key))
        JsonValue value = Json.object()
        JsonObject valueObject = value.asObject() as JsonObject
        valueObject.set("stringValue", Json.string(resourceValues.getOr(key, "")))
        attributeObject.set("value", value)
        attributeArray.add(attribute)
        resourceIndex = resourceIndex + 1
    }
    resourceObject.set("attributes", attributes)
    metricObject.set("resource", resource)
    JsonValue scopeMetrics = Json.array()
    JsonArray scopeArray = scopeMetrics.asArray() as JsonArray
    JsonValue scopeMetric = Json.object()
    JsonObject scopeObject = scopeMetric.asObject() as JsonObject
    JsonValue scope = Json.object()
    JsonObject scopeInner = scope.asObject() as JsonObject
    scopeInner.set("name", Json.string("xdk.agent"))
    scopeObject.set("scope", scope)
    JsonValue metrics = Json.array()
    JsonArray metricArray = metrics.asArray() as JsonArray
    List<TelemetryRecord> records = batch.records()
    Int index = 0
    while index < records.length() {
        MetricFamily? family = records.get(index).metricFamily()
        if family != null {
            MetricFamily actual = family as MetricFamily
            JsonValue metric = Json.object()
            JsonObject metricValue = metric.asObject() as JsonObject
            metricValue.set("name", Json.string(actual.name()))
            metricValue.set("unit", Json.string(actual.unit()))
            String kindKey = "gauge"
            if actual.kind() == MetricKind.Counter { kindKey = "sum" }
            else if actual.kind() == MetricKind.Histogram { kindKey = "histogram" }
            JsonValue data = Json.object()
            JsonObject dataObject = data.asObject() as JsonObject
            JsonValue points = Json.array()
            JsonArray pointArray = points.asArray() as JsonArray
            List<MetricSample> samples = actual.samples()
            Int sampleIndex = 0
            while sampleIndex < samples.length() {
                MetricSample sample = samples.get(sampleIndex)
                JsonValue point = Json.object()
                JsonObject pointObject = point.asObject() as JsonObject
                pointObject.set("asDouble", Json.number(str(sample.value())))
                pointObject.set("timeUnixNano", Json.string(str(sample.timestampMono() * 1000000 as Long)))
                JsonValue pointAttributes = Json.array()
                JsonArray pointAttributeArray = pointAttributes.asArray() as JsonArray
                Map<String, String> labels = sample.labels()
                List<String> labelKeys = labels.keys()
                Int labelIndex = 0
                while labelIndex < labelKeys.length() {
                    String labelKey = labelKeys.get(labelIndex)
                    JsonValue label = Json.object()
                    JsonObject labelObject = label.asObject() as JsonObject
                    labelObject.set("key", Json.string(labelKey))
                    JsonValue labelValue = Json.object()
                    JsonObject labelValueObject = labelValue.asObject() as JsonObject
                    labelValueObject.set("stringValue", Json.string(labels.getOr(labelKey, "")))
                    labelObject.set("value", labelValue)
                    pointAttributeArray.add(label)
                    labelIndex = labelIndex + 1
                }
                pointObject.set("attributes", pointAttributes)
                pointArray.add(point)
                sampleIndex = sampleIndex + 1
            }
            dataObject.set("dataPoints", points)
            metricValue.set(kindKey, data)
            metricArray.add(metric)
        }
        index = index + 1
    }
    scopeObject.set("metrics", metrics)
    scopeArray.add(scopeMetric)
    metricObject.set("scopeMetrics", scopeMetrics)
    resourceArray.add(resourceMetric)
    rootObject.set("resourceMetrics", resourceMetrics)
    return Ok(root)
}

// ---------- OtlpExporter ----------
class OtlpExporter implements PipelineExporter {
    final String _name
    final TelemetryKind _kind
    final String _endpoint
    final Map<String, String> _headers
    final Long _requestTimeoutMillis
    final RetryPolicy _retryPolicy
    final Int _queueCapacity
    final String _overflowPolicy
    final RuntimeMonitor _monitor
    final List<TelemetryBatch> _queue
    Bool _started
    Bool _closed
    Bool _sending
    Bool _healthy
    Int _sentBatches
    Int _droppedBatches
    Int _failedRequests
    HttpClient? _client

    OtlpExporter(String name, TelemetryKind kind, String endpoint, String protocolName,
                 Map<String, String> headers, Long requestTimeoutMillis,
                 String compression, RetryPolicy retryPolicy, Int queueCapacity,
                 String overflowPolicy) {
        if name == null || name == "" { throw "OtlpExporter: empty name" }
        if kind == null || kind == TelemetryKind.Unknown { throw "OtlpExporter: invalid kind" }
        if endpoint == null || endpoint == "" { throw "OtlpExporter: empty endpoint" }
        if protocolName != "http_json" { throw "OtlpExporter: unsupported protocol" }
        if headers == null { throw "OtlpExporter: null headers" }
        if requestTimeoutMillis <= 0 as Long { throw "OtlpExporter: invalid timeout" }
        if compression != "none" { throw "OtlpExporter: unsupported compression" }
        if retryPolicy == null { throw "OtlpExporter: null retry policy" }
        if queueCapacity <= 0 { throw "OtlpExporter: invalid queue capacity" }
        if overflowPolicy != "reject" && overflowPolicy != "drop_oldest" &&
            overflowPolicy != "drop_newest" {
            throw "OtlpExporter: invalid overflow policy"
        }
        self._name = name
        self._kind = kind
        self._endpoint = endpoint
        Map<String, String> copy = [:]
        List<String> keys = headers.keys()
        Int index = 0
        while index < keys.length() {
            copy.put(keys.get(index), headers.getOr(keys.get(index), ""))
            index = index + 1
        }
        self._headers = copy
        self._requestTimeoutMillis = requestTimeoutMillis
        self._retryPolicy = retryPolicy
        self._queueCapacity = queueCapacity
        self._overflowPolicy = overflowPolicy
        self._monitor = new RuntimeMonitor()
        List<TelemetryBatch> queue = []
        self._queue = queue
        self._started = false
        self._closed = false
        self._sending = false
        self._healthy = true
        self._sentBatches = 0
        self._droppedBatches = 0
        self._failedRequests = 0
        self._client = null
    }

    TelemetryKind kind() { return self._kind }
    String name() { return self._name }

    Result<Unit, Error> start(Context context) {
        if context == null { throw "OtlpExporter.start: null context" }
        if self._closed { return Err(new BasicError(ErrorKind.Unavailable, "otlp closed")) }
        if self._started { return Ok() }
        self._client = new HttpClient()
        self._started = true
        return Ok()
    }

    Result<Unit, Error> export(Context context, TelemetryBatch batch) {
        if context == null || batch == null { throw "OtlpExporter.export: null argument" }
        if self._closed || !self._started {
            return Err(new BasicError(ErrorKind.Unavailable, "otlp not running"))
        }
        if batch.kind() != self._kind {
            return Err(new BasicError(ErrorKind.InvalidArgument, "otlp kind mismatch"))
        }
        if self._queue.length() >= self._queueCapacity {
            if self._overflowPolicy == "reject" {
                return Err(new BasicError(ErrorKind.Busy, "otlp queue full"))
            }
            if self._overflowPolicy == "drop_newest" {
                self._droppedBatches = self._droppedBatches + 1
                return Ok()
            }
            TelemetryBatch removed = self._queue.get(0)
            self._queue.remove(0)
            self._droppedBatches = self._droppedBatches + 1
        }
        self._queue.push(batch)
        return self.drain(context)
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "OtlpExporter.drain: null context" }
        if self._closed || !self._started {
            return Err(new BasicError(ErrorKind.Unavailable, "otlp not running"))
        }
        if self._sending { return Ok() }
        self._sending = true
        while self._queue.length() > 0 {
            TelemetryBatch batch = self._queue.get(0)
            Result<Unit, Error> sent = self.sendWithRetry(context, batch)
            if sent.isErr() {
                self._sending = false
                self._healthy = false
                return Err(sent.error())
            }
            self._queue.remove(0)
            self._sentBatches = self._sentBatches + 1
        }
        self._sending = false
        self._healthy = true
        return Ok()
    }

    private Result<Unit, Error> sendWithRetry(Context context, TelemetryBatch batch) {
        if self._client == null {
            return Err(new BasicError(ErrorKind.Unavailable, "otlp client missing"))
        }
        Int attempts = self._retryPolicy.maxAttempts()
        Int attempt = 1
        Long delay = self._retryPolicy.initialDelayMillis()
        while attempt <= attempts {
            Result<Unit, Error> sent = self.sendOnce(context, batch)
            if sent.isOk() { return Ok() }
            Error error = sent.error()
            self._failedRequests = self._failedRequests + 1
            Bool retryable = error.kind() == ErrorKind.Network ||
                error.kind() == ErrorKind.Timeout ||
                error.kind() == ErrorKind.Unavailable ||
                error.kind() == ErrorKind.Busy
            if !retryable || attempt == attempts { return Err(error) }
            if delay > 0 as Long { sleepMs(delay) }
            Long nextDelay = (delay as Double * self._retryPolicy.multiplier()) as Long
            if nextDelay > self._retryPolicy.maxDelayMillis() {
                nextDelay = self._retryPolicy.maxDelayMillis()
            }
            delay = nextDelay
            attempt = attempt + 1
        }
        return Err(new BasicError(ErrorKind.Internal, "otlp retry exhausted"))
    }

    private Result<Unit, Error> sendOnce(Context context, TelemetryBatch batch) {
        Result<JsonValue, Error> encoded = otlpEncode(batch)
        if encoded.isErr() { return Err(encoded.error()) }
        String path = "/v1/metrics"
        if self._kind == TelemetryKind.Traces { path = "/v1/traces" }
        if self._kind == TelemetryKind.Logs { path = "/v1/logs" }
        Result<Uri, Error> uri = Uri.parse(self._endpoint + path)
        if uri.isErr() { return Err(uri.error()) }
        HttpRequest request = new HttpRequest(HttpMethod.Post, uri.value())
        request = request.withHeader("Content-Type", "application/json")
        List<String> keys = self._headers.keys()
        Int index = 0
        while index < keys.length() {
            request = request.withHeader(keys.get(index), self._headers.getOr(keys.get(index), ""))
            index = index + 1
        }
        request = request.withBody(HttpBody.fromText(Json.stringify(encoded.value())))
        HttpClient client = self._client as HttpClient
        Result<HttpResponse, Error> response = client.request(context, request)
        if response.isErr() { return Err(response.error()) }
        Int status = response.value().status().code()
        if status >= 200 && status <= 299 { return Ok() }
        if status == 429 || status >= 500 {
            return Err(new BasicError(ErrorKind.Unavailable, "otlp server error"))
        }
        return Err(new BasicError(ErrorKind.InvalidArgument, "otlp rejected"))
    }

    Result<Unit, Error> close() {
        if self._closed { return Ok() }
        self._closed = true
        self._started = false
        self._droppedBatches = self._droppedBatches + self._queue.length()
        self._queue.clear()
        if self._client != null {
            HttpClient client = self._client as HttpClient
            client.close()
        }
        return Ok()
    }

    Bool isHealthy() { return self._started && !self._closed && self._healthy }
    Int queueLength() { return self._queue.length() }
    Int sentBatches() { return self._sentBatches }
    Int droppedBatches() { return self._droppedBatches }
    Int failedRequests() { return self._failedRequests }
    String describe() { return "otlp " + self._name + " endpoint=" + self._endpoint }
}
