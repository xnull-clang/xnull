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
