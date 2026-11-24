package xdk2.trace
import xdk.trace
import xdk.errors
import xdk.math

static Error traceFailure() {
    return new BasicError(ErrorKind.Timeout, "boom")
}

static Map<String, String> bag(String key, String value) {
    Map<String, String> result = [:]
    result.put(key, value)
    return result
}

static Int main() {
    String traceId = "4bf92f3577b34da6a3ce929d0e0e4736"
    String spanId = "00f067aa0ba902b7"
    SpanContext rootContext = new SpanContext(traceId, spanId, null, true, bag("user", "alice"))
    SpanContext childContext = new SpanContext(traceId, "00f067aa0ba902b8", spanId, false, bag("k", "v"))
    print("context=" + str(rootContext.isValid()) + "," + str(rootContext.isRoot()) + "," +
        str(childContext.isRoot()) + "," + str(childContext.sampled()))
    Map<String, String> bagCopy = rootContext.baggage()
    bagCopy.put("user", "bob")
    print("context-baggage=" + rootContext.baggage().getOr("user", ""))
    SpanContext copied = rootContext.copy()
    print("context-copy=" + str(copied.traceId() == rootContext.traceId()) + "," +
        str(copied.baggage().getOr("user", "")))
    SpanContext badTrace = new SpanContext("abc", spanId, null, true, bag("a", "b"))
    SpanContext zeroSpan = new SpanContext(traceId, "0000000000000000", null, true, bag("a", "b"))
    SpanContext selfParent = new SpanContext(traceId, spanId, spanId, true, bag("a", "b"))
    print("invalid=" + str(badTrace.isValid()) + "," + str(zeroSpan.isValid()) + "," +
        str(selfParent.isValid()))

    SpanContext badContext = new SpanContext("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", spanId, null, true, bag("a", "b"))
    Bool ratioFirst = Sampler.ratio(0.5).shouldSample(rootContext)
    Bool ratioSecond = Sampler.ratio(0.5).shouldSample(rootContext)
    print("sampler=" + str(Sampler.alwaysOn().shouldSample(rootContext)) + "," +
        str(Sampler.alwaysOff().shouldSample(rootContext)) + "," +
        str(Sampler.ratio(0.0).shouldSample(rootContext)) + "," +
        str(Sampler.ratio(1.0).shouldSample(rootContext)) + "," +
        str(ratioFirst == ratioSecond) + "," +
        str(Sampler.alwaysOn().shouldSample(badContext)))
    print("sampler-desc=" + Sampler.alwaysOn().describe() + "," + Sampler.alwaysOff().describe() + "," +
        str(Sampler.ratio(0.25).describe().startsWith("ratio(")))

    W3cPropagator propagator = new W3cPropagator()
    Map<String, String> headers = bag("keep", "yes")
    propagator.inject(rootContext, headers)
    String traceparent = headers.getOr("traceparent", "")
    SpanContext? extracted = propagator.extract(headers)
    SpanContext remote = extracted as SpanContext
    print("w3c=" + propagator.name() + "," + str(propagator.fields().length()) + "," +
        str(traceparent == "00-" + traceId + "-" + spanId + "-01") + "," + str(remote.isValid()) + "," +
        str(remote.traceId() == traceId) + "," + str(remote.spanId() == spanId) + "," +
        str(remote.sampled()) + "," + headers.getOr("keep", ""))
    Map<String, String> unsampledHeaders = [:]
    propagator.inject(childContext, unsampledHeaders)
    SpanContext? extractedUnsampled = propagator.extract(unsampledHeaders)
    SpanContext resolvedUnsampled = extractedUnsampled as SpanContext
    print("w3c-unsampled=" + str(resolvedUnsampled.sampled()) + "," +
        str(unsampledHeaders.getOr("traceparent", "").endsWith("-00")))
    Map<String, String> emptyHeaders = [:]
    print("w3c-bad=" + str(propagator.extract(emptyHeaders) == null) + "," +
        str(propagator.extract(bag("traceparent", "bad")) == null) + "," +
        str(propagator.extract(bag("traceparent", "00-" + traceId + "-" + spanId)) == null) + "," +
        str(propagator.extract(bag("traceparent", "00-00000000000000000000000000000000-" + spanId + "-01")) == null))

    TraceOptions defaults = new TraceOptions()
    print("options=" + defaults.getServiceName() + "," + defaults.getSampler().describe() + "," +
        str(defaults.getMaxAttributes()) + "," + str(defaults.getMaxEvents()))
    TraceOptions options = new TraceOptions()
    options.serviceName(" orders ")
    options.sampler(Sampler.alwaysOn())
    options.maxAttributes(2)
    options.maxEvents(1)
    TraceOptions snapshot = options.copy()
    options.maxAttributes(4)
    print("options-custom=" + snapshot.getServiceName() + "," + str(snapshot.getMaxAttributes()) + "," +
        str(snapshot.getMaxEvents()) + "," + str(options.getMaxAttributes()))

    Result<Tracer, Error> created = Tracer.create(snapshot)
    Tracer tracer = created.value()
    print("tracer=" + str(created.isOk()) + "," + tracer.options().getServiceName() + "," +
        tracer.propagator().name() + "," + str(tracer.isClosed()))
    Span root = tracer.startSpanKind("root", SpanKind.Server)
    print("root=" + str(root.context().isValid()) + "," + str(root.context().isRoot()) + "," +
        str(root.kind() == SpanKind.Server) + "," + str(root.isRecording()) + "," +
        str(root.context().traceId().length()) + "," + str(root.context().spanId().length()) + "," +
        str(root.duration().millis() == 0))
    Span child = tracer.startSpanKind("child", SpanKind.Client)
    Span? currentChild = tracer.currentSpan()
    Span resolvedChild = currentChild as Span
    String? childParent = child.context().parentSpanId()
    String parentId = childParent as String
    print("child=" + str(resolvedChild == child) + "," +
        str(child.context().traceId() == root.context().traceId()) + "," +
        str(parentId == root.context().spanId()) + "," +
        str(child.isRecording()))
    child.setAttribute("db.system", "sql")
    child.addEvent("cache.miss", bag("key", "value"))
    child.setStatus(SpanStatus.Ok, "ok")
    child.setStatus(SpanStatus.Error, "failed")
    child.setStatus(SpanStatus.Ok, "ignored")
    print("span-write=" + str(child.attributes().getOr("db.system", "")) + "," +
        str(child.events().length()) + "," + str(spanStatusName(child.status())) + "," +
        child.statusDescription())
    child.end()
    child.end()
    Span? currentRoot = tracer.currentSpan()
    print("end=" + str((currentRoot as Span) == root) + "," + str(child.isRecording()) + "," +
        str(child.duration().millis() >= 0))
    root.end()
    print("current-none=" + str(tracer.currentSpan() == null))

    TraceOptions limitOptions = new TraceOptions()
    limitOptions.maxAttributes(2)
    limitOptions.maxEvents(1)
    Result<Tracer, Error> limited = Tracer.create(limitOptions)
    Tracer limitTracer = limited.value()
    Span limitSpan = limitTracer.startSpan("limits")
    limitSpan.setAttribute("a", "1")
    limitSpan.setAttribute("b", "2")
    limitSpan.setAttribute("a", "3")
    limitSpan.setAttribute("c", "4")
    limitSpan.addEvent("first", bag("k", "v"))
    limitSpan.addEvent("second", bag("k", "v"))
    print("limits=" + str(limitSpan.attributes().length()) + "," +
        limitSpan.attributes().getOr("a", "") + "," + str(limitSpan.events().length()) + "," +
        str(limitSpan.droppedAttributes()) + "," + str(limitSpan.droppedEvents()))
    limitSpan.end()

    TraceOptions errorOptions = new TraceOptions()
    Result<Tracer, Error> errorTracerResult = Tracer.create(errorOptions)
    Tracer errorTracer = errorTracerResult.value()
    Span errorSpan = errorTracer.startSpan("error")
    errorSpan.recordError(traceFailure())
    print("record-error=" + str(errorStatus(errorSpan)) + "," + str(errorSpan.events().length()) + "," +
        errorSpan.events().get(0).name())
    errorSpan.end()

    TraceOptions offOptions = new TraceOptions()
    offOptions.sampler(Sampler.alwaysOff())
    Result<Tracer, Error> offResult = Tracer.create(offOptions)
    Tracer offTracer = offResult.value()
    Span offSpan = offTracer.startSpan("off")
    offSpan.setAttribute("a", "1")
    print("unsampled=" + str(offSpan.isRecording()) + "," + str(offSpan.attributes().length()))
    offSpan.end()
    print("unsampled-end=" + str(offSpan.isRecording()) + "," + str(offTracer.currentSpan() == null))

    TraceOptions closedOptions = new TraceOptions()
    Result<Tracer, Error> closedResult = Tracer.create(closedOptions)
    Tracer closedTracer = closedResult.value()
    Result<Unit, Error> firstClose = closedTracer.close()
    Result<Unit, Error> secondClose = closedTracer.shutdown()
    Span closedSpan = closedTracer.startSpan("after-close")
    print("closed=" + str(firstClose.isOk()) + "," + str(secondClose.isOk()) + "," +
        str(closedTracer.isClosed()) + "," + str(closedSpan.isRecording()) + "," +
        str(closedTracer.currentSpan() == null))
    closedSpan.end()

    Span unique1 = tracer.startSpanFromKind("u1", null, SpanKind.Internal)
    unique1.end()
    Span unique2 = tracer.startSpanFromKind("u2", null, SpanKind.Internal)
    unique2.end()
    print("unique=" + str(unique1.context().spanId() != unique2.context().spanId()) + "," +
        str(unique1.context().spanId().length()) + "," + str(unique1.context().traceId().length()))
    return 0
}

static String errorStatus(Span span) {
    return spanStatusName(span.status())
}
