package xdk2.agent
import xdk.agent
import xdk.metrics
import xdk.trace
import xdk.log
import xdk.runtime
import xdk.errors

class FakeReceiver implements Receiver {
    Bool _running
    final TelemetryKind _kind
    FakeReceiver(TelemetryKind kind) { self._running = false; self._kind = kind }
    TelemetryKind kind() { return self._kind }
    String name() { return "fake-receiver" }
    Result<Unit, Error> start(Context context,
            Result<Unit, Error>(TelemetryBatch) downstream) {
        self._running = true
        return Ok()
    }
    Result<Unit, Error> stop(Context context) { self._running = false; return Ok() }
    Result<Unit, Error> drain(Context context) { return Ok() }
    Result<Unit, Error> close() { return Ok() }
    Bool isRunning() { return self._running }
    Bool isHealthy() { return true }
}

class FakeProcessor implements Processor {
    Int _marker
    final TelemetryKind _kind
    FakeProcessor(TelemetryKind kind) { self._marker = 1; self._kind = kind }
    TelemetryKind kind() { return self._kind }
    String name() { return "fake-processor" }
    Result<Unit, Error> start(Context context,
            Result<Unit, Error>(TelemetryBatch) downstream) { return Ok() }
    Result<Unit, Error> process(Context context, TelemetryBatch batch) { return Ok() }
    Result<Unit, Error> drain(Context context) { return Ok() }
    Result<Unit, Error> close() { return Ok() }
    Bool isHealthy() { return true }
}

class FakeExporter implements PipelineExporter {
    Int _marker
    final TelemetryKind _kind
    FakeExporter(TelemetryKind kind) { self._marker = 1; self._kind = kind }
    TelemetryKind kind() { return self._kind }
    String name() { return "fake-exporter" }
    Result<Unit, Error> start(Context context) { return Ok() }
    Result<Unit, Error> export(Context context, TelemetryBatch batch) { return Ok() }
    Result<Unit, Error> drain(Context context) { return Ok() }
    Result<Unit, Error> close() { return Ok() }
    Bool isHealthy() { return true }
}

class FakeConnector implements Connector {
    Int _marker
    final TelemetryKind _inputKind
    final TelemetryKind _outputKind
    FakeConnector(TelemetryKind inputKind, TelemetryKind outputKind) {
        self._marker = 1
        self._inputKind = inputKind
        self._outputKind = outputKind
    }
    String name() { return "fake-connector" }
    TelemetryKind inputKind() { return self._inputKind }
    TelemetryKind outputKind() { return self._outputKind }
    Result<Unit, Error> start(Context context,
            Result<Unit, Error>(TelemetryBatch) downstream) { return Ok() }
    Result<Unit, Error> consume(Context context, TelemetryBatch batch) { return Ok() }
    Result<Unit, Error> drain(Context context) { return Ok() }
    Result<Unit, Error> close() { return Ok() }
    Bool isHealthy() { return true }
}

static MetricFamily agFamily() {
    Map<String, String> labels = [:]
    labels.put("route", "/x")
    List<MetricSample> samples = []
    samples.push(new MetricSample("requests", labels, 3.0, 5 as Long))
    return new MetricFamily("requests", MetricKind.Counter, "request count", "1",
        samples)
}

static SpanContext agContext() {
    Map<String, String> baggage = [:]
    return new SpanContext("0123456789abcdef0123456789abcdef",
        "0123456789abcdef", null, true, baggage)
}

static SpanEvent agEvent() {
    Map<String, String> attributes = [:]
    attributes.put("k", "v")
    return new SpanEvent("event", 7 as Long, attributes)
}

static LogRecord agLogRecord() {
    List<Field> fields = []
    LogRecord record = new LogRecord(Level.Info, "api.logger", "hello", fields)
    record.timestampMs = 10 as Long
    record.monotonicMs = 8 as Long
    return record
}

static Int main() {
    print("kind=" + telemetryKindName(TelemetryKind.Metrics) + "," +
        telemetryKindName(TelemetryKind.Traces) + "," +
        telemetryKindName(TelemetryKind.Logs) + "," +
        telemetryKindName(TelemetryKind.Unknown))

    TelemetryRecord metricRecord = TelemetryRecord.metric(agFamily(), 5 as Long,
        10 as Long)
    TelemetryKind metricKind = metricRecord.kind()
    MetricFamily metricFamily = metricRecord.metricFamily() as MetricFamily
    print("metric-record=" + telemetryKindName(metricKind) + "," +
        metricRecord.name() + "," + str(metricFamily.samples().length()) + "," +
        str(metricRecord.estimatedBytes() > 0 as Long) + "," +
        str(metricRecord.timestampMono()) + "," +
        str(metricRecord.timestampWall()) + "," + metricRecord.describe())

    Map<String, String> spanAttributes = [:]
    spanAttributes.put("http.method", "GET")
    List<SpanEvent> spanEvents = []
    spanEvents.push(agEvent())
    TelemetryRecord spanRecord = TelemetryRecord.span("GET /x", agContext(),
        SpanKind.Server, SpanStatus.Ok, 12 as Long, spanAttributes, spanEvents,
        20 as Long, 30 as Long)
    SpanKind spanKind = spanRecord.spanKind() as SpanKind
    SpanStatus spanStatus = spanRecord.spanStatus() as SpanStatus
    print("span-record=" + spanRecord.name() + "," +
        spanKindName(spanKind) + "," + spanStatusName(spanStatus) + "," +
        str(spanRecord.spanDurationMillis()) + "," +
        spanRecord.spanAttributes().getOr("http.method", "") + "," +
        str(spanRecord.spanEvents().length()) + "," +
        str(spanRecord.spanContext() != null) + "," +
        str(spanRecord.estimatedBytes() > 0 as Long))

    TelemetryRecord logRecord = TelemetryRecord.log(agLogRecord())
    print("log-record=" + logRecord.name() + "," +
        str(logRecord.logRecord() != null) + "," +
        str(logRecord.timestampMono()) + "," + str(logRecord.timestampWall()))

    List<TelemetryRecord> records = []
    records.push(metricRecord)
    Map<String, String> resource = [:]
    resource.put("service.name", "api")
    TelemetryBatch batch = new TelemetryBatch(TelemetryKind.Metrics, resource, records,
        1, 5 as Long)
    List<TelemetryRecord> noRecords = []
    TelemetryBatch emptyBatch = batch.withRecords(noRecords)
    TelemetryBatch droppedBatch = batch.withAdditionalDropped(2)
    print("batch=" + batch.describe() + "," + str(batch.recordCount()) + "," +
        str(batch.isEmpty()) + "," + str(emptyBatch.isEmpty()) + "," +
        str(emptyBatch.estimatedBytes()) + "," + str(droppedBatch.droppedRecords()) +
        "," + batch.resource().getOr("service.name", ""))

    List<TelemetryRecord> secondRecords = []
    secondRecords.push(metricRecord)
    TelemetryBatch secondBatch = new TelemetryBatch(TelemetryKind.Metrics, resource,
        secondRecords, 1, 3 as Long)
    TelemetryBatch merged = batch.merge(secondBatch).value()
    List<TelemetryBatch> split = merged.split(1)
    print("batch-merge=" + str(merged.recordCount()) + "," +
        str(merged.droppedRecords()) + "," + str(merged.timestampMono()) + "," +
        str(split.length()) + "," + str(split.get(0).droppedRecords()) + "," +
        str(split.get(1).droppedRecords()))

    List<TelemetryRecord> logRecords = []
    logRecords.push(logRecord)
    Map<String, String> differentResource = [:]
    differentResource.put("service.name", "other")
    TelemetryBatch logBatch = new TelemetryBatch(TelemetryKind.Logs, resource,
        logRecords, 0, 5 as Long)
    Result<TelemetryBatch, Error> kindMismatch = batch.merge(logBatch)
    TelemetryBatch otherResourceBatch = new TelemetryBatch(TelemetryKind.Metrics,
        differentResource, records, 0, 5 as Long)
    Result<TelemetryBatch, Error> resourceMismatch = batch.merge(otherResourceBatch)
    print("batch-errors=" + errorKindName(kindMismatch.error().kind()) + "," +
        errorKindName(resourceMismatch.error().kind()))

    FakeReceiver receiver = new FakeReceiver(TelemetryKind.Metrics)
    Result<Unit, Error> started = receiver.start(Context.background(),
        (TelemetryBatch delivered) -> Ok())
    Result<Unit, Error> stopped = receiver.stop(Context.background())
    FakeProcessor processor = new FakeProcessor(TelemetryKind.Metrics)
    FakeExporter exporter = new FakeExporter(TelemetryKind.Traces)
    FakeConnector connector = new FakeConnector(TelemetryKind.Metrics, TelemetryKind.Traces)
    print("fakes=" + str(started.isOk()) + "," + str(stopped.isOk()) + "," +
        receiver.name() + "," + processor.name() + "," + exporter.name() + "," +
        connector.name() + "," + str(connector.inputKind() == TelemetryKind.Metrics) +
        "," + str(connector.outputKind() == TelemetryKind.Traces))

    AgentHealth health = new AgentHealth("agent-health", "api", 2)
    health.markStarted()
    health.markReady(1)
    print("health-start=" + healthStateName(health.state()) + "," +
        str(health.readyPipelines()) + "," + str(health.isReady()) + "," +
        str(health.isLive()) + "," + health.message())
    health.recordDrop(2)
    print("health-drop=" + healthStateName(health.state()) + "," +
        str(health.droppedBatches()) + "," + health.message())
    Error failure = new BasicError(ErrorKind.Io, "network down")
    health.recordFailure(failure)
    print("health-fail=" + healthStateName(health.state()) + "," +
        str(health.failedOperations()) + "," + health.lastError())
    health.markReady(2)
    print("health-ready=" + healthStateName(health.state()) + "," +
        str(health.isReady()) + "," + health.describe())
    health.markUnhealthy("boom")
    HealthReport report = health.check()
    print("health-unhealthy=" + healthStateName(health.state()) + "," +
        str(health.isLive()) + "," + healthStateName(report.state()) + "," +
        report.message() + "," + report.detailOr("pipelinesTotal", "") + "," +
        report.detailOr("lastError", ""))
    health.markStopped()
    print("health-stopped=" + healthStateName(health.state()) + "," +
        str(health.isLive()) + "," + str(health.readyPipelines()) + "," +
        health.message())
    return 0
}
