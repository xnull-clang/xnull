package xdk2.agent
import xdk.agent
import xdk.metrics
import xdk.trace
import xdk.log
import xdk.runtime
import xdk.errors
import xdk.time
import xdk.execution

static TelemetryBatch metricBatch(Int count, String name) {
    List<MetricSample> samples = []
    Map<String, String> sampleLabels = [:]
    MetricSample sample = new MetricSample(name, sampleLabels, 3.0, 1 as Long)
    samples.push(sample)
    MetricFamily family = new MetricFamily(name, MetricKind.Gauge, "test gauge", "", samples)
    List<TelemetryRecord> records = []
    Int index = 0
    while index < count {
        records.push(TelemetryRecord.metric(family, 10 as Long, 20 as Long))
        index = index + 1
    }
    Map<String, String> resource = [:]
    return new TelemetryBatch(TelemetryKind.Metrics, resource, records, 0, 30 as Long)
}

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

class OrderReceiver implements Receiver {
    final TelemetryKind _kind
    final List<String> _trace
    Bool _fail
    Bool _healthy
    OrderReceiver(TelemetryKind kind, List<String> trace) {
        self._kind = kind
        self._trace = trace
        self._fail = false
        self._healthy = true
    }
    TelemetryKind kind() { return self._kind }
    String name() { return "order-receiver" }
    Result<Unit, Error> start(Context context,
            Result<Unit, Error>(TelemetryBatch) downstream) {
        self._trace.push("receiver:start")
        if self._fail { return Err(mlSinkError("receiver start")) }
        return Ok()
    }
    Result<Unit, Error> stop(Context context) {
        self._trace.push("receiver:stop")
        return Ok()
    }
    Result<Unit, Error> drain(Context context) {
        self._trace.push("receiver:drain")
        return Ok()
    }
    Result<Unit, Error> close() {
        self._trace.push("receiver:close")
        return Ok()
    }
    Bool isRunning() { return true }
    Bool isHealthy() { return self._healthy }
}

class OrderProcessor implements Processor {
    final TelemetryKind _kind
    final String _label
    final List<String> _trace
    Result<Unit, Error>(TelemetryBatch) _downstream
    OrderProcessor(TelemetryKind kind, String label, List<String> trace) {
        self._kind = kind
        self._label = label
        self._trace = trace
        Result<Unit, Error>(TelemetryBatch) placeholder =
            (TelemetryBatch batch) -> Ok()
        self._downstream = placeholder
    }
    TelemetryKind kind() { return self._kind }
    String name() { return self._label }
    Result<Unit, Error> start(Context context,
            Result<Unit, Error>(TelemetryBatch) downstream) {
        self._trace.push(self._label + ":start")
        self._downstream = downstream
        return Ok()
    }
    Result<Unit, Error> process(Context context, TelemetryBatch batch) {
        self._trace.push(self._label + ":process")
        return self._downstream(batch)
    }
    Result<Unit, Error> drain(Context context) {
        self._trace.push(self._label + ":drain")
        return Ok()
    }
    Result<Unit, Error> close() {
        self._trace.push(self._label + ":close")
        return Ok()
    }
    Bool isHealthy() { return true }
}

class OrderExporter implements PipelineExporter {
    final TelemetryKind _kind
    final String _label
    final List<String> _trace
    Bool _failStart
    Bool _failExport
    OrderExporter(TelemetryKind kind, String label, List<String> trace) {
        self._kind = kind
        self._label = label
        self._trace = trace
        self._failStart = false
        self._failExport = false
    }
    TelemetryKind kind() { return self._kind }
    String name() { return self._label }
    Result<Unit, Error> start(Context context) {
        self._trace.push(self._label + ":start")
        if self._failStart { return Err(mlSinkError("exporter start")) }
        return Ok()
    }
    Result<Unit, Error> export(Context context, TelemetryBatch batch) {
        self._trace.push(self._label + ":export")
        if self._failExport { return Err(mlSinkError("exporter export")) }
        return Ok()
    }
    Result<Unit, Error> drain(Context context) {
        self._trace.push(self._label + ":drain")
        return Ok()
    }
    Result<Unit, Error> close() {
        self._trace.push(self._label + ":close")
        return Ok()
    }
    Bool isHealthy() { return true }
}

class OrderConnector implements Connector {
    final String _name
    final TelemetryKind _inputKind
    final TelemetryKind _outputKind
    final List<String> _trace
    OrderConnector(String name, TelemetryKind inputKind, TelemetryKind outputKind,
                   List<String> trace) {
        self._name = name
        self._inputKind = inputKind
        self._outputKind = outputKind
        self._trace = trace
    }
    String name() { return self._name }
    TelemetryKind inputKind() { return self._inputKind }
    TelemetryKind outputKind() { return self._outputKind }
    Result<Unit, Error> start(Context context,
            Result<Unit, Error>(TelemetryBatch) downstream) {
        self._trace.push(self._name + ":start")
        return Ok()
    }
    Result<Unit, Error> consume(Context context, TelemetryBatch batch) {
        self._trace.push(self._name + ":consume")
        return Ok()
    }
    Result<Unit, Error> drain(Context context) { return Ok() }
    Result<Unit, Error> close() { return Ok() }
    Bool isHealthy() { return true }
}

class SlowReceiver implements Receiver {
    final TelemetryKind _kind
    final List<String> _trace
    SlowReceiver(TelemetryKind kind, List<String> trace) {
        self._kind = kind
        self._trace = trace
    }
    TelemetryKind kind() { return self._kind }
    String name() { return "slow-receiver" }
    Result<Unit, Error> start(Context context,
            Result<Unit, Error>(TelemetryBatch) downstream) { return Ok() }
    Result<Unit, Error> stop(Context context) { return Ok() }
    Result<Unit, Error> drain(Context context) {
        sleepMs(120 as Long)
        return Ok()
    }
    Result<Unit, Error> close() { return Ok() }
    Bool isRunning() { return true }
    Bool isHealthy() { return true }
}

static Error mlSinkError(String message) {
    return new BasicError(ErrorKind.Io, message)
}

static TelemetryBatch agEmptyBatch(TelemetryKind kind) {
    Map<String, String> resource = [:]
    List<TelemetryRecord> records = []
    return new TelemetryBatch(kind, resource, records, 0, 1 as Long)
}

static String agentStateName(HealthState state) {
    return healthStateName(state)
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

    List<String> pipelineTrace = []
    OrderReceiver pipelineReceiver = new OrderReceiver(TelemetryKind.Metrics,
        pipelineTrace)
    OrderProcessor firstProcessor = new OrderProcessor(TelemetryKind.Metrics, "p1",
        pipelineTrace)
    OrderProcessor secondProcessor = new OrderProcessor(TelemetryKind.Metrics, "p2",
        pipelineTrace)
    OrderExporter pipelineExporter = new OrderExporter(TelemetryKind.Metrics, "exp",
        pipelineTrace)
    OrderConnector outputConnector = new OrderConnector("out", TelemetryKind.Metrics,
        TelemetryKind.Logs, pipelineTrace)
    List<Receiver> pipelineReceivers = []
    pipelineReceivers.push(pipelineReceiver)
    List<Processor> pipelineProcessors = []
    pipelineProcessors.push(firstProcessor)
    pipelineProcessors.push(secondProcessor)
    List<PipelineExporter> pipelineExporters = []
    pipelineExporters.push(pipelineExporter)
    List<Connector> noInputConnectors = []
    List<Connector> pipelineOutputConnectors = []
    pipelineOutputConnectors.push(outputConnector)
    AgentPipeline pipeline = new AgentPipeline("metrics-pipe", TelemetryKind.Metrics,
        pipelineReceivers, pipelineProcessors, pipelineExporters, noInputConnectors,
        pipelineOutputConnectors)
    Result<Unit, Error> pipelineStart = pipeline.start(Context.background())
    String startTrace = pipelineTrace.join(",")
    pipelineTrace.clear()
    Result<Unit, Error> consumed = pipeline.consume(Context.background(),
        agEmptyBatch(TelemetryKind.Metrics))
    String consumeTrace = pipelineTrace.join(",")
    print("pipeline-start=" + str(pipelineStart.isOk()) + "," + startTrace + "," +
        str(pipeline.isRunning()) + "," + str(pipeline.receiverCount()) + "," +
        str(pipeline.processorCount()) + "," + str(pipeline.exporterCount()) + "," +
        pipeline.describe())
    print("pipeline-consume=" + str(consumed.isOk()) + "," + consumeTrace)

    Result<Unit, Error> duplicateStart = pipeline.start(Context.background())
    Result<Unit, Error> pipelineStop = pipeline.stop(Context.background())
    String stopTrace = pipelineTrace.join(",")
    pipelineTrace.clear()
    Result<Unit, Error> afterStopConsume = pipeline.consume(Context.background(),
        agEmptyBatch(TelemetryKind.Metrics))
    String afterStopTrace = pipelineTrace.join(",")
    print("pipeline-lifecycle=" + str(duplicateStart.isOk()) + "," +
        str(pipelineStop.isOk()) + "," + stopTrace + "," +
        str(afterStopConsume.isOk()) + "," + afterStopTrace + "," +
        str(pipeline.isRunning()))

    pipelineTrace.clear()
    Result<Unit, Error> firstClose = pipeline.close()
    Result<Unit, Error> secondClose = pipeline.close()
    Result<Unit, Error> closedConsume = pipeline.consume(Context.background(),
        agEmptyBatch(TelemetryKind.Metrics))
    Result<Unit, Error> closedDrain = pipeline.drain(Context.background())
    print("pipeline-close=" + str(firstClose.isOk()) + "," +
        str(secondClose.isOk()) + "," + str(pipeline.isClosed()) + "," +
        errorKindName(closedConsume.error().kind()) + "," +
        errorKindName(closedDrain.error().kind()) + "," +
        pipelineTrace.join(","))

    List<String> failTrace = []
    OrderReceiver failReceiver = new OrderReceiver(TelemetryKind.Logs, failTrace)
    OrderProcessor failProcessor = new OrderProcessor(TelemetryKind.Logs, "fp",
        failTrace)
    OrderExporter failExporter = new OrderExporter(TelemetryKind.Logs, "fexp",
        failTrace)
    failExporter._failStart = true
    List<Receiver> failReceivers = []
    failReceivers.push(failReceiver)
    List<Processor> failProcessors = []
    failProcessors.push(failProcessor)
    List<PipelineExporter> failExporters = []
    failExporters.push(failExporter)
    List<Connector> failNoConnectors = []
    AgentPipeline failPipeline = new AgentPipeline("fail-pipe", TelemetryKind.Logs,
        failReceivers, failProcessors, failExporters, failNoConnectors,
        failNoConnectors)
    Result<Unit, Error> failedStart = failPipeline.start(Context.background())
    print("pipeline-fail=" + str(failedStart.isErr()) + "," + failTrace.join(",") +
        "," + healthStateName(failPipeline.health().state()) + "," +
        str(failPipeline.isRunning()))
    failPipeline.close()

    List<String> fanTrace = []
    OrderReceiver fanReceiver = new OrderReceiver(TelemetryKind.Traces, fanTrace)
    OrderExporter fanOne = new OrderExporter(TelemetryKind.Traces, "one", fanTrace)
    OrderExporter fanTwo = new OrderExporter(TelemetryKind.Traces, "two", fanTrace)
    OrderConnector fanConnector = new OrderConnector("fanout", TelemetryKind.Traces,
        TelemetryKind.Metrics, fanTrace)
    List<Receiver> fanReceivers = []
    fanReceivers.push(fanReceiver)
    List<Receiver> noReceivers = []
    List<Processor> noProcessors = []
    List<PipelineExporter> noExporters = []
    List<PipelineExporter> fanExporters = []
    fanExporters.push(fanOne)
    fanExporters.push(fanTwo)
    List<Connector> fanOutputs = []
    fanOutputs.push(fanConnector)
    AgentPipeline fanPipeline = new AgentPipeline("fan-pipe", TelemetryKind.Traces,
        fanReceivers, noProcessors, fanExporters, failNoConnectors, fanOutputs)
    fanPipeline.start(Context.background())
    fanTrace.clear()
    fanOne._failExport = true
    Result<Unit, Error> fanResult = fanPipeline.consume(Context.background(),
        agEmptyBatch(TelemetryKind.Traces))
    print("pipeline-fanout=" + str(fanResult.isErr()) + "," + fanTrace.join(","))
    fanPipeline.close()

    List<String> drainTrace = []
    OrderReceiver drainReceiver = new OrderReceiver(TelemetryKind.Metrics, drainTrace)
    OrderProcessor drainProcessor = new OrderProcessor(TelemetryKind.Metrics, "dp",
        drainTrace)
    OrderExporter drainExporter = new OrderExporter(TelemetryKind.Metrics, "dexp",
        drainTrace)
    List<Receiver> drainReceivers = []
    drainReceivers.push(drainReceiver)
    List<Processor> drainProcessors = []
    drainProcessors.push(drainProcessor)
    List<PipelineExporter> drainExporters = []
    drainExporters.push(drainExporter)
    AgentPipeline drainPipeline = new AgentPipeline("drain-pipe", TelemetryKind.Metrics,
        drainReceivers, drainProcessors, drainExporters, failNoConnectors,
        failNoConnectors)
    drainPipeline.start(Context.background())
    drainTrace.clear()
    Result<Unit, Error> drained = drainPipeline.drain(Context.background())
    print("pipeline-drain=" + str(drained.isOk()) + "," + drainTrace.join(","))
    drainPipeline.close()

    List<String> slowTrace = []
    SlowReceiver slowReceiver = new SlowReceiver(TelemetryKind.Metrics, slowTrace)
    List<Receiver> slowReceivers = []
    slowReceivers.push(slowReceiver)
    List<PipelineExporter> slowExporters = []
    slowExporters.push(new OrderExporter(TelemetryKind.Metrics, "slow-exp", slowTrace))
    AgentPipeline slowPipeline = new AgentPipeline("slow-pipe", TelemetryKind.Metrics,
        slowReceivers, noProcessors, slowExporters, failNoConnectors,
        failNoConnectors)
    slowPipeline.start(Context.background())
    TaskGroup drainGroup = TaskGroup.create(Context.withCancel(Context.background()))
    Task<Int> drainTask = drainGroup.spawn((Context taskContext) -> {
        slowPipeline.drain(taskContext)
        return Ok(0)
    })
    sleepMs(20 as Long)
    Result<Unit, Error> concurrentDrain = slowPipeline.drain(Context.background())
    drainTask.join()
    drainGroup.close()
    print("pipeline-drain-busy=" + errorKindName(concurrentDrain.error().kind()))
    slowPipeline.close()

    List<String> configTrace = []
    OrderReceiver configReceiver = new OrderReceiver(TelemetryKind.Metrics, configTrace)
    OrderExporter configExporter = new OrderExporter(TelemetryKind.Traces, "config-exp",
        configTrace)
    OrderConnector configConnector = new OrderConnector("m2t", TelemetryKind.Metrics,
        TelemetryKind.Traces, configTrace)
    List<Receiver> configReceivers = []
    configReceivers.push(configReceiver)
    List<Connector> configOutputs = []
    configOutputs.push(configConnector)
    List<Connector> noConnectors = []
    AgentPipeline configSource = new AgentPipeline("source", TelemetryKind.Metrics,
        configReceivers, noProcessors, noExporters, noConnectors, configOutputs)
    List<PipelineExporter> configExporters = []
    configExporters.push(configExporter)
    List<Connector> configInputs = []
    configInputs.push(configConnector)
    AgentPipeline configSink = new AgentPipeline("sink", TelemetryKind.Traces,
        noReceivers, noProcessors, configExporters, configInputs, noConnectors)
    List<AgentPipeline> configPipelines = []
    configPipelines.push(configSource)
    configPipelines.push(configSink)
    List<Connector> configConnectors = []
    configConnectors.push(configConnector)
    Result<AgentConfig, Error> config = AgentConfig.create("svc", "inst",
        configPipelines, configConnectors)
    AgentConfig validConfig = config.value()
    AgentPipeline? foundPipeline = validConfig.pipeline("sink")
    Connector? foundConnector = validConfig.connector("m2t")
    print("config=" + str(config.isOk()) + "," + validConfig.describe() + "," +
        str(foundPipeline != null) + "," + str(foundConnector != null) + "," +
        str(validConfig.pipeline("missing") == null))

    List<AgentPipeline> duplicatePipelines = []
    duplicatePipelines.push(configSource)
    duplicatePipelines.push(configSource)
    Result<AgentConfig, Error> duplicateConfig = AgentConfig.create("svc", "inst",
        duplicatePipelines, configConnectors)
    List<Connector> unattachedConnectors = []
    unattachedConnectors.push(configConnector)
    unattachedConnectors.push(new OrderConnector("extra", TelemetryKind.Logs,
        TelemetryKind.Metrics, configTrace))
    Result<AgentConfig, Error> unattachedConfig = AgentConfig.create("svc", "inst",
        configPipelines, unattachedConnectors)
    List<Connector> missingConnectors = []
    Result<AgentConfig, Error> missingConfig = AgentConfig.create("svc", "inst",
        configPipelines, missingConnectors)
    print("config-errors=" + errorKindName(duplicateConfig.error().kind()) + "," +
        errorKindName(unattachedConfig.error().kind()) + "," +
        errorKindName(missingConfig.error().kind()))

    OrderConnector cycleOne = new OrderConnector("c1", TelemetryKind.Metrics,
        TelemetryKind.Traces, configTrace)
    OrderConnector cycleTwo = new OrderConnector("c2", TelemetryKind.Traces,
        TelemetryKind.Metrics, configTrace)
    List<Connector> cycleOneOut = []
    cycleOneOut.push(cycleOne)
    List<Connector> cycleTwoIn = []
    cycleTwoIn.push(cycleOne)
    List<Connector> cycleTwoOut = []
    cycleTwoOut.push(cycleTwo)
    List<Connector> cycleOneIn = []
    cycleOneIn.push(cycleTwo)
    AgentPipeline cycleA = new AgentPipeline("cycle-a", TelemetryKind.Metrics,
        configReceivers, noProcessors, noExporters, cycleOneIn, cycleOneOut)
    List<PipelineExporter> cycleExporters = []
    cycleExporters.push(configExporter)
    AgentPipeline cycleB = new AgentPipeline("cycle-b", TelemetryKind.Traces,
        noReceivers, noProcessors, cycleExporters, cycleTwoIn, cycleTwoOut)
    List<AgentPipeline> cyclePipelines = []
    cyclePipelines.push(cycleA)
    cyclePipelines.push(cycleB)
    List<Connector> cycleConnectors = []
    cycleConnectors.push(cycleOne)
    cycleConnectors.push(cycleTwo)
    Result<AgentConfig, Error> cycleConfig = AgentConfig.create("svc", "inst",
        cyclePipelines, cycleConnectors)
    Result<AgentConfig, Error> derived = validConfig.withPipeline(new AgentPipeline(
        "extra", TelemetryKind.Logs, failReceivers, noProcessors, failExporters,
        noConnectors, noConnectors))
    Result<AgentConfig, Error> derivedConnector = validConfig.withConnector(
        new OrderConnector("unused", TelemetryKind.Logs, TelemetryKind.Metrics,
            configTrace))
    print("config-cycle=" + errorKindName(cycleConfig.error().kind()) + "," +
        str(derived.isOk()) + "," + str(derivedConnector.isErr()))

    List<String> agentTrace = []
    OrderReceiver agentSourceReceiver = new OrderReceiver(TelemetryKind.Metrics,
        agentTrace)
    List<Receiver> agentSourceReceivers = []
    agentSourceReceivers.push(agentSourceReceiver)
    OrderConnector agentConnector = new OrderConnector("agent-c", TelemetryKind.Metrics,
        TelemetryKind.Traces, agentTrace)
    List<Connector> agentEmptyConnectors = []
    List<PipelineExporter> agentNoExporters = []
    List<Connector> agentSourceOutputs = []
    agentSourceOutputs.push(agentConnector)
    AgentPipeline agentSource = new AgentPipeline("agent-source", TelemetryKind.Metrics,
        agentSourceReceivers, noProcessors, agentNoExporters, agentEmptyConnectors,
        agentSourceOutputs)
    OrderExporter agentSinkExporter = new OrderExporter(TelemetryKind.Traces,
        "agent-exp", agentTrace)
    List<PipelineExporter> agentSinkExporters = []
    agentSinkExporters.push(agentSinkExporter)
    List<Connector> agentSinkInputs = []
    agentSinkInputs.push(agentConnector)
    AgentPipeline agentSink = new AgentPipeline("agent-sink", TelemetryKind.Traces,
        noReceivers, noProcessors, agentSinkExporters, agentSinkInputs,
        agentEmptyConnectors)
    List<AgentPipeline> agentPipelines = []
    agentPipelines.push(agentSource)
    agentPipelines.push(agentSink)
    List<Connector> agentConnectors = []
    agentConnectors.push(agentConnector)
    AgentConfig agentConfig = AgentConfig.create("agent-svc", "agent-inst",
        agentPipelines, agentConnectors).value()
    Agent agent = new Agent(agentConfig)
    Result<Unit, Error> agentStart = agent.start(Context.background())
    String agentStartTrace = agentTrace.join(",")
    print("agent-start=" + str(agentStart.isOk()) + "," + agentStartTrace + "," +
        str(agent.isRunning()) + "," + agent.describe() + "," +
        agentStateName(agent.health().state()))

    Result<Unit, Error> agentRepeatStart = agent.start(Context.background())
    agentTrace.clear()
    Result<Unit, Error> agentDrain = agent.drain(Context.background())
    String agentDrainTrace = agentTrace.join(",")
    print("agent-drain=" + str(agentRepeatStart.isOk()) + "," +
        str(agentDrain.isOk()) + "," + agentDrainTrace)

    agentTrace.clear()
    Result<Unit, Error> agentStop = agent.stop(Context.background())
    String agentStopTrace = agentTrace.join(",")
    Result<Unit, Error> agentStopAgain = agent.stop(Context.background())
    Result<Unit, Error> agentDrainStopped = agent.drain(Context.background())
    Result<Unit, Error> agentStartClosed = agent.start(Context.background())
    print("agent-stop=" + str(agentStop.isOk()) + "," + agentStopTrace + "," +
        str(agentStopAgain.isOk()) + "," +
        errorKindName(agentDrainStopped.error().kind()) + "," +
        errorKindName(agentStartClosed.error().kind()) + "," +
        str(agent.isRunning()) + "," + agentStateName(agent.health().state()) +
        "," + str(agent.health().isLive()))

    Result<Unit, Error> agentClose = agent.close()
    print("agent-close=" + str(agentClose.isOk()) + "," + str(agent.close().isOk()))

    List<String> unstartedTrace = []
    OrderReceiver unstartedReceiver = new OrderReceiver(TelemetryKind.Metrics,
        unstartedTrace)
    List<Receiver> unstartedReceivers = []
    unstartedReceivers.push(unstartedReceiver)
    List<PipelineExporter> unstartedExporters = []
    unstartedExporters.push(new OrderExporter(TelemetryKind.Metrics, "u-exp",
        unstartedTrace))
    AgentPipeline unstartedPipeline = new AgentPipeline("unstarted",
        TelemetryKind.Metrics, unstartedReceivers, noProcessors, unstartedExporters,
        agentEmptyConnectors, agentEmptyConnectors)
    List<AgentPipeline> unstartedPipelines = []
    unstartedPipelines.push(unstartedPipeline)
    AgentConfig unstartedConfig = AgentConfig.create("agent-svc", "unstarted",
        unstartedPipelines, agentEmptyConnectors).value()
    Agent unstartedAgent = new Agent(unstartedConfig)
    Result<Unit, Error> unstartedStop = unstartedAgent.stop(Context.background())
    print("agent-unstarted=" + str(unstartedStop.isOk()) + "," +
        agentStateName(unstartedAgent.health().state()) + "," +
        str(unstartedAgent.isRunning()))
    unstartedAgent.close()

    List<String> failAgentTrace = []
    OrderReceiver failAgentReceiver = new OrderReceiver(TelemetryKind.Metrics,
        failAgentTrace)
    List<Receiver> failAgentReceivers = []
    failAgentReceivers.push(failAgentReceiver)
    OrderConnector failAgentConnector = new OrderConnector("fail-c",
        TelemetryKind.Metrics, TelemetryKind.Traces, failAgentTrace)
    List<Connector> failAgentSourceOutputs = []
    failAgentSourceOutputs.push(failAgentConnector)
    AgentPipeline failAgentSource = new AgentPipeline("fail-source",
        TelemetryKind.Metrics, failAgentReceivers, noProcessors, agentNoExporters,
        agentEmptyConnectors, failAgentSourceOutputs)
    OrderExporter failAgentExporter = new OrderExporter(TelemetryKind.Traces,
        "fail-exp", failAgentTrace)
    failAgentExporter._failStart = true
    List<PipelineExporter> failAgentExporters = []
    failAgentExporters.push(failAgentExporter)
    List<Connector> failAgentInputs = []
    failAgentInputs.push(failAgentConnector)
    AgentPipeline failAgentSink = new AgentPipeline("fail-sink", TelemetryKind.Traces,
        noReceivers, noProcessors, failAgentExporters, failAgentInputs,
        agentEmptyConnectors)
    List<AgentPipeline> failAgentPipelines = []
    failAgentPipelines.push(failAgentSource)
    failAgentPipelines.push(failAgentSink)
    List<Connector> failAgentConnectors = []
    failAgentConnectors.push(failAgentConnector)
    AgentConfig failAgentConfig = AgentConfig.create("agent-svc", "fail-agent",
        failAgentPipelines, failAgentConnectors).value()
    Agent failAgent = new Agent(failAgentConfig)
    Result<Unit, Error> failAgentStart = failAgent.start(Context.background())
    print("agent-fail=" + str(failAgentStart.isErr()) + "," +
        failAgentTrace.join(",") + "," + agentStateName(failAgent.health().state()) +
        "," + str(failAgent.isRunning()))
    failAgent.close()

    List<TelemetryBatch> batchSink = []
    BatchProcessor batchProcessor = new BatchProcessor("batch", TelemetryKind.Metrics, 2,
        100 as Long, 0, 8, "reject")
    Context batchContext = Context.background()
    Result<Unit, Error>(TelemetryBatch) batchSinkFn = (TelemetryBatch pendingBatch) -> {
        batchSink.push(pendingBatch)
        return Ok()
    }
    batchProcessor.start(batchContext, batchSinkFn)
    batchProcessor.process(batchContext, metricBatch(1, "b1"))
    batchProcessor.process(batchContext, metricBatch(1, "b2"))
    batchProcessor.drain(batchContext)
    print("batch-processor=" + str(batchSink.length()) + "," +
        str(batchProcessor.sentBatches()) + "," + str(batchProcessor.pendingRecords()) +
        "," + str(batchProcessor.isHealthy()))
    batchProcessor.close()

    BatchProcessor dropProcessor = new BatchProcessor("drop", TelemetryKind.Metrics, 4,
        100 as Long, 0, 4, "drop_newest")
    List<TelemetryBatch> dropSink = []
    Result<Unit, Error>(TelemetryBatch) dropSinkFn = (TelemetryBatch pendingBatch) -> {
        dropSink.push(pendingBatch)
        return Ok()
    }
    dropProcessor.start(batchContext, dropSinkFn)
    dropProcessor.process(batchContext, metricBatch(3, "d1"))
    dropProcessor.process(batchContext, metricBatch(2, "d2"))
    print("batch-overflow=" + str(dropProcessor.droppedRecords()) + "," +
        str(dropProcessor.pendingRecords()) + "," + str(dropSink.length()))
    dropProcessor.close()

    MemoryLimiterProcessor limiter = new MemoryLimiterProcessor("mem", TelemetryKind.Metrics,
        10 as Long, 1 as Long, 0, 0 as Long, 0, true)
    List<TelemetryBatch> limitSink = []
    Result<Unit, Error>(TelemetryBatch) limitSinkFn = (TelemetryBatch pendingBatch) -> {
        limitSink.push(pendingBatch)
        return Ok()
    }
    limiter.start(batchContext, limitSinkFn)
    Result<Unit, Error> limitedDrop = limiter.process(batchContext, metricBatch(1, "m1"))
    print("memory-limiter=" + str(limiter.isLimited()) + "," + str(limitedDrop.isOk()) +
        "," + str(limiter.droppedBatches()) + "," + str(limitSink.length()) +
        "," + str(limiter.hardLimitBytes() >= 1 as Long))
    limiter.close()

    Map<String, String> promLabels = [:]
    PrometheusExporter prometheus = new PrometheusExporter("prom", "xdk", promLabels, 0 as Long, false)
    prometheus.start(batchContext)
    prometheus.export(batchContext, metricBatch(2, "requests"))
    String promText = prometheus.scrapeText(batchContext)
    print("prometheus=" + str(promText != "") + "," + str(prometheus.familyCount()) +
        "," + str(prometheus.sampleCount()) + "," +
        str(promText.indexOf("# TYPE xdk_requests gauge") >= 0) + "," +
        str(promText.indexOf("xdk_requests 3") >= 0))
    prometheus.close()
    return 0
}
