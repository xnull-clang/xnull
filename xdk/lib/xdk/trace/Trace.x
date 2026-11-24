package xdk.trace
import xdk.errors
import xdk.runtime
import xdk.time
import xdk.math
import xdk.text

enum SpanKind {
    Unknown,
    Internal,
    Server,
    Client,
    Producer,
    Consumer,
}

String spanKindName(SpanKind kind) {
    if kind == SpanKind.Internal { return "internal" }
    if kind == SpanKind.Server { return "server" }
    if kind == SpanKind.Client { return "client" }
    if kind == SpanKind.Producer { return "producer" }
    if kind == SpanKind.Consumer { return "consumer" }
    return "unknown"
}

enum SpanStatus {
    Unknown,
    Unset,
    Ok,
    Error,
}

String spanStatusName(SpanStatus status) {
    if status == SpanStatus.Unset { return "unset" }
    if status == SpanStatus.Ok { return "ok" }
    if status == SpanStatus.Error { return "error" }
    return "unknown"
}

static String traceHex(Long value, Int width) {
    String digits = "0123456789abcdef"
    String out = ""
    Long current = value
    Int count = 0
    while count < width {
        Int nibble = (current & 15) as Int
        out = digits.substring(nibble, 1) + out
        current = current >> 4
        count = count + 1
    }
    return out
}

static String traceHex64(Long value) { return traceHex(value, 16) }

static Bool traceIsHex(String text) {
    String digits = "0123456789abcdef"
    Int index = 0
    while index < text.length() {
        if digits.indexOf(text.substring(index, 1)) < 0 { return false }
        index = index + 1
    }
    return true
}

static Bool traceIsZero(String text) {
    Int index = 0
    while index < text.length() {
        if text.substring(index, 1) != "0" { return false }
        index = index + 1
    }
    return true
}

static Map<String, String> traceCopyMap(Map<String, String> source) {
    Map<String, String> copy = [:]
    List<String> keys = source.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        copy.put(key, source.getOr(key, ""))
        index = index + 1
    }
    return copy
}

static Map<String, String> traceEmptyMap() {
    Map<String, String> empty = [:]
    return empty
}

class SpanContext {
    final String _traceId
    final String _spanId
    final String? _parentSpanId
    final Bool _sampled
    final Map<String, String> _baggage

    SpanContext(String traceId, String spanId, String? parentSpanId, Bool sampled,
                Map<String, String> baggage) {
        if traceId == null || spanId == null || baggage == null {
            throw "SpanContext: null argument"
        }
        self._traceId = traceId.toLower()
        self._spanId = spanId.toLower()
        if parentSpanId == null {
            self._parentSpanId = null
        } else {
            String parent = parentSpanId as String
            self._parentSpanId = parent.toLower()
        }
        self._sampled = sampled
        self._baggage = traceCopyMap(baggage)
    }

    String traceId() { return self._traceId }
    String spanId() { return self._spanId }
    String? parentSpanId() { return self._parentSpanId }
    Bool sampled() { return self._sampled }
    Map<String, String> baggage() { return traceCopyMap(self._baggage) }
    Bool isRoot() { return self._parentSpanId == null }

    Bool isValid() {
        if self._traceId.length() != 32 { return false }
        if !traceIsHex(self._traceId) { return false }
        if traceIsZero(self._traceId) { return false }
        if self._spanId.length() != 16 { return false }
        if !traceIsHex(self._spanId) { return false }
        if traceIsZero(self._spanId) { return false }
        if self._parentSpanId != null {
            String parent = self._parentSpanId as String
            if parent.length() != 16 { return false }
            if !traceIsHex(parent) { return false }
            if traceIsZero(parent) { return false }
            if parent == self._spanId { return false }
        }
        if self._baggage.length() > 64 { return false }
        List<String> keys = self._baggage.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null || key.length() == 0 || key.length() > 256 { return false }
            String value = self._baggage.getOr(key, "")
            if value.length() > 1024 { return false }
            index = index + 1
        }
        return true
    }

    SpanContext copy() {
        return new SpanContext(self._traceId, self._spanId, self._parentSpanId,
            self._sampled, self._baggage)
    }
}

class SpanEvent {
    final String _name
    final Long _timestampMono
    final Map<String, String> _attributes

    SpanEvent(String name, Long timestampMono, Map<String, String> attributes) {
        if name == null || attributes == null { throw "SpanEvent: null argument" }
        if name.length() == 0 || name.length() > 256 { throw "SpanEvent: invalid name" }
        if timestampMono < 0 { throw "SpanEvent: negative timestamp" }
        self._name = name
        self._timestampMono = timestampMono
        self._attributes = traceCopyMap(attributes)
    }

    String name() { return self._name }
    Long timestampMono() { return self._timestampMono }
    Map<String, String> attributes() { return traceCopyMap(self._attributes) }

    SpanEvent copy() {
        return new SpanEvent(self._name, self._timestampMono, self._attributes)
    }
}

class Sampler {
    final Int _mode
    final Double _ratio

    private Sampler(Int mode, Double ratio) {
        self._mode = mode
        self._ratio = ratio
    }

    static Sampler alwaysOn() { return new Sampler(0, 1.0) }
    static Sampler alwaysOff() { return new Sampler(1, 0.0) }

    static Sampler ratio(Double value) {
        if isNaN(value) || value < 0.0 || value > 1.0 {
            throw "Sampler.ratio: value outside [0,1]"
        }
        return new Sampler(2, value)
    }

    Bool shouldSample(SpanContext context) {
        if context == null { throw "Sampler.shouldSample: null context" }
        if !context.isValid() { return false }
        if self._mode == 0 { return true }
        if self._mode == 1 { return false }
        if self._ratio <= 0.0 { return false }
        if self._ratio >= 1.0 { return true }
        return Sampler.sampleUnit(context.traceId()) < self._ratio
    }

    String describe() {
        if self._mode == 0 { return "always_on" }
        if self._mode == 1 { return "always_off" }
        return "ratio(" + str(self._ratio) + ")"
    }

    private static Double sampleUnit(String traceId) {
        String digits = "0123456789abcdef"
        Long hash = 2166136261 as Long
        Int index = 0
        while index < traceId.length() {
            String ch = traceId.substring(index, 1)
            Int code = digits.indexOf(ch)
            if code < 0 { code = 16 }
            hash = hash ^ ((code + 1) as Long)
            hash = (hash * (16777619 as Long)) & (4294967295 as Long)
            index = index + 1
        }
        return (hash as Double) / 4294967296.0
    }
}

class TraceOptions {
    String _serviceName
    Sampler _sampler
    Int _maxAttributes
    Int _maxEvents

    TraceOptions() {
        self._serviceName = "unknown_service"
        self._sampler = Sampler.alwaysOn()
        self._maxAttributes = 128
        self._maxEvents = 128
    }

    TraceOptions serviceName(String value) {
        if value == null { throw "TraceOptions.serviceName: null" }
        String normalized = value.trim()
        if normalized.length() == 0 || normalized.length() > 255 {
            throw "TraceOptions.serviceName: invalid"
        }
        self._serviceName = normalized
        return self
    }

    TraceOptions sampler(Sampler value) {
        if value == null { throw "TraceOptions.sampler: null" }
        self._sampler = value
        return self
    }

    TraceOptions maxAttributes(Int value) {
        if value < 0 || value > 1024 { throw "TraceOptions.maxAttributes: outside 0..1024" }
        self._maxAttributes = value
        return self
    }

    TraceOptions maxEvents(Int value) {
        if value < 0 || value > 1024 { throw "TraceOptions.maxEvents: outside 0..1024" }
        self._maxEvents = value
        return self
    }

    String getServiceName() { return self._serviceName }
    Sampler getSampler() { return self._sampler }
    Int getMaxAttributes() { return self._maxAttributes }
    Int getMaxEvents() { return self._maxEvents }

    TraceOptions copy() {
        TraceOptions result = new TraceOptions()
        result.serviceName(self._serviceName)
        result.sampler(self._sampler)
        result.maxAttributes(self._maxAttributes)
        result.maxEvents(self._maxEvents)
        return result
    }
}

protocol Propagator {
    String name();
    List<String> fields();
    Void inject(SpanContext context, Map<String, String> carrier);
    SpanContext? extract(Map<String, String> carrier);
}

class W3cPropagator implements Propagator {
    W3cPropagator() { }

    String name() { return "w3c" }

    List<String> fields() {
        List<String> result = []
        result.push("traceparent")
        result.push("tracestate")
        return result
    }

    Void inject(SpanContext context, Map<String, String> carrier) {
        if context == null || carrier == null { throw "W3cPropagator.inject: null argument" }
        if !context.isValid() { return }
        String flags = "00"
        if context.sampled() { flags = "01" }
        carrier.put("traceparent", "00-" + context.traceId() + "-" + context.spanId() + "-" + flags)
    }

    SpanContext? extract(Map<String, String> carrier) {
        if carrier == null { throw "W3cPropagator.extract: null carrier" }
        String value = carrier.getOr("traceparent", "")
        if value == "" { return null }
        List<String> parts = value.split("-")
        if parts.length() != 4 { return null }
        if parts.get(0) != "00" { return null }
        String traceId = parts.get(1)
        String spanId = parts.get(2)
        String flags = parts.get(3)
        if traceId.length() != 32 || spanId.length() != 16 || flags.length() != 2 { return null }
        if !traceIsHex(traceId) || !traceIsHex(spanId) || !traceIsHex(flags) { return null }
        Bool sampled = flags == "01"
        SpanContext context = new SpanContext(traceId, spanId, null, sampled, traceEmptyMap())
        if !context.isValid() { return null }
        return context
    }
}

class TraceRuntime {
    final String _serviceName
    final RuntimeMonitor _monitor
    Long _counter
    Bool _closed

    TraceRuntime(String serviceName) {
        self._serviceName = serviceName
        self._monitor = new RuntimeMonitor()
        self._counter = 0
        self._closed = false
    }

    String serviceName() { return self._serviceName }

    Bool isClosed() {
        self._monitor.enter()
        Bool value = self._closed
        self._monitor.exit()
        return value
    }

    String newTraceId() {
        self._monitor.enter()
        self._counter = self._counter + 1
        Long counter = self._counter
        Long tick = nowMono()
        Long left = tick ^ (counter * (1099511628211 as Long))
        Long right = (counter * (1469598103934665603 as Long)) ^ (tick * 31 as Long)
        self._monitor.exit()
        if left == 0 && right == 0 { right = 1 }
        return traceHex64(left) + traceHex64(right)
    }

    String newSpanId() {
        self._monitor.enter()
        self._counter = self._counter + 1
        Long counter = self._counter
        Long value = (nowMono() * 31 as Long) ^ (counter * (1099511628211 as Long))
        self._monitor.exit()
        if value == 0 { value = 1 }
        return traceHex64(value)
    }

    Result<Unit, Error> close() {
        self._monitor.enter()
        self._closed = true
        self._monitor.exit()
        return Ok()
    }
}

class Span {
    final String _name
    final SpanContext _context
    final SpanKind _kind
    final Tracer _tracer
    final RuntimeMonitor _monitor
    final Long _startedMono
    Map<String, String> _attributes
    List<SpanEvent> _events
    SpanStatus _status
    String _statusDescription
    Bool _ended
    Long _endedMono
    Bool _recording
    Int _maxAttributes
    Int _maxEvents
    Int _droppedAttributes
    Int _droppedEvents

    Span(String name, SpanContext context, SpanKind kind, Tracer tracer) {
        if name == null || context == null || kind == null || tracer == null {
            throw "Span: null argument"
        }
        if name.length() == 0 || name.length() > 256 { throw "Span: invalid name" }
        if !context.isValid() { throw "Span: invalid context" }
        if kind == SpanKind.Unknown { throw "Span: invalid kind" }
        self._name = name
        self._context = context
        self._kind = kind
        self._tracer = tracer
        self._monitor = new RuntimeMonitor()
        self._attributes = traceEmptyMap()
        self._events = []
        self._status = SpanStatus.Unset
        self._statusDescription = ""
        self._ended = false
        self._endedMono = 0
        self._recording = context.sampled()
        self._maxAttributes = 128
        self._maxEvents = 128
        self._droppedAttributes = 0
        self._droppedEvents = 0
        self._startedMono = nowMono()
    }

    String name() { return self._name }
    SpanContext context() { return self._context }
    SpanKind kind() { return self._kind }

    Void setLimits(Int maxAttributes, Int maxEvents) {
        self._maxAttributes = maxAttributes
        self._maxEvents = maxEvents
    }

    Void setRecording(Bool value) { self._recording = value }

    Bool _canRecord() {
        if !self._recording { return false }
        if self._ended { return false }
        if self._tracer.isClosed() { return false }
        return true
    }

    Void setAttribute(String key, String value) {
        if key == null || value == null { throw "Span.setAttribute: null argument" }
        if key.length() == 0 { throw "Span.setAttribute: empty key" }
        self._monitor.enter()
        if !self._canRecord() {
            self._monitor.exit()
            return
        }
        if key.length() > 256 || value.length() > 1024 {
            self._droppedAttributes = self._droppedAttributes + 1
            self._monitor.exit()
            return
        }
        if !self._attributes.has(key) && self._attributes.length() >= self._maxAttributes {
            self._droppedAttributes = self._droppedAttributes + 1
            self._monitor.exit()
            return
        }
        self._attributes.put(key, value)
        self._monitor.exit()
    }

    Void addEvent(String name, Map<String, String> attributes) {
        if name == null || attributes == null { throw "Span.addEvent: null argument" }
        if name.length() == 0 || name.length() > 256 { throw "Span.addEvent: invalid name" }
        self._monitor.enter()
        if !self._canRecord() {
            self._monitor.exit()
            return
        }
        if self._events.length() >= self._maxEvents {
            self._droppedEvents = self._droppedEvents + 1
            self._monitor.exit()
            return
        }
        Map<String, String> copied = [:]
        List<String> keys = attributes.keys()
        Int index = 0
        while index < keys.length() && index < self._maxAttributes {
            String key = keys.get(index)
            copied.put(key, attributes.getOr(key, ""))
            index = index + 1
        }
        self._events.push(new SpanEvent(name, nowMono(), copied))
        self._monitor.exit()
    }

    Void setStatus(SpanStatus status, String description) {
        if status == null || description == null { throw "Span.setStatus: null argument" }
        self._monitor.enter()
        if !self._canRecord() {
            self._monitor.exit()
            return
        }
        if status == SpanStatus.Unknown || status == SpanStatus.Unset {
            self._monitor.exit()
            return
        }
        if self._status == SpanStatus.Error {
            self._monitor.exit()
            return
        }
        if status == SpanStatus.Ok && self._status == SpanStatus.Ok {
            self._monitor.exit()
            return
        }
        String text = description
        if text.length() > 1024 { text = text.substring(0, 1024) }
        self._status = status
        self._statusDescription = text
        self._monitor.exit()
    }

    Void recordError(Error error) {
        if error == null { throw "Span.recordError: null error" }
        if !self.isRecording() { return }
        String description = error.describe()
        if description.length() > 1024 { description = description.substring(0, 1024) }
        Map<String, String> attributes = [:]
        attributes.put("exception.type", errorKindName(error.kind()))
        attributes.put("exception.message", description)
        self.setStatus(SpanStatus.Error, description)
        self.addEvent("exception", attributes)
    }

    Void end() {
        self._monitor.enter()
        if self._ended {
            self._monitor.exit()
            return
        }
        self._ended = true
        self._endedMono = nowMono()
        self._monitor.exit()
        self._tracer.onSpanEnd(self)
    }

    Bool isRecording() {
        self._monitor.enter()
        Bool value = self._canRecord()
        self._monitor.exit()
        return value
    }

    Duration duration() {
        self._monitor.enter()
        Bool ended = self._ended
        Long end = self._endedMono
        self._monitor.exit()
        if !ended { return durationOfMillis(0) }
        Long elapsed = end - self._startedMono
        if elapsed < 0 { elapsed = 0 }
        return durationOfMillis(elapsed)
    }

    SpanStatus status() { return self._status }
    String statusDescription() { return self._statusDescription }
    Map<String, String> attributes() { return traceCopyMap(self._attributes) }
    List<SpanEvent> events() { return self._events.copy() }
    Int droppedAttributes() { return self._droppedAttributes }
    Int droppedEvents() { return self._droppedEvents }
}

class Tracer {
    final TraceOptions _options
    final Propagator _propagator
    final TraceRuntime _runtime
    final RuntimeMonitor _monitor
    final List<Span> _stack
    final List<Span> _completed
    Bool _closed
    Error? _closeError

    private Tracer(TraceOptions options, Propagator propagator, TraceRuntime runtime) {
        self._options = options
        self._propagator = propagator
        self._runtime = runtime
        self._monitor = new RuntimeMonitor()
        self._stack = []
        self._completed = []
        self._closed = false
        self._closeError = null
    }

    static Result<Tracer, Error> create(TraceOptions options) {
        if options == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "trace options is null"))
        }
        return Tracer.createWithPropagator(options, new W3cPropagator())
    }

    static Result<Tracer, Error> createWithPropagator(TraceOptions options, Propagator propagator) {
        if options == null || propagator == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "trace option or propagator is null"))
        }
        TraceOptions snapshot = options.copy()
        return Ok(new Tracer(snapshot, propagator, new TraceRuntime(snapshot.getServiceName())))
    }

    TraceOptions options() { return self._options.copy() }
    Propagator propagator() { return self._propagator }

    Bool isClosed() {
        self._monitor.enter()
        Bool value = self._closed
        self._monitor.exit()
        return value
    }

    Void _push(Span span) {
        self._monitor.enter()
        if !self._closed { self._stack.push(span) }
        self._monitor.exit()
    }

    Void onSpanEnd(Span span) {
        self._monitor.enter()
        Int index = -1
        Int scan = 0
        while scan < self._stack.length() {
            if self._stack.get(scan) == span { index = scan; break }
            scan = scan + 1
        }
        if index >= 0 { self._stack.remove(index) }
        self._completed.push(span)
        if self._completed.length() > 256 {
            self._completed.remove(0)
        }
        self._monitor.exit()
    }

    List<Span> completedSpans() {
        self._monitor.enter()
        List<Span> result = self._completed.copy()
        self._monitor.exit()
        return result
    }

    Span? currentSpan() {
        self._monitor.enter()
        Span? result = null
        if !self._closed && self._stack.length() > 0 {
            result = self._stack.get(self._stack.length() - 1)
        }
        self._monitor.exit()
        return result
    }

    Span _newSpan(String name, SpanContext context, SpanKind kind, Bool recording) {
        Span span = new Span(name, context, kind, self)
        span.setLimits(self._options.getMaxAttributes(), self._options.getMaxEvents())
        if !recording { span.setRecording(false) }
        return span
    }

    Span _startRoot(String name, SpanKind kind) {
        String traceId = self._runtime.newTraceId()
        String spanId = self._runtime.newSpanId()
        SpanContext probe = new SpanContext(traceId, spanId, null, true, traceEmptyMap())
        Bool sampled = self._options.getSampler().shouldSample(probe)
        SpanContext context = new SpanContext(traceId, spanId, null, sampled, traceEmptyMap())
        Span span = self._newSpan(name, context, kind, sampled)
        self._push(span)
        return span
    }

    Span _startChild(String name, SpanContext parent, SpanKind kind) {
        String spanId = self._runtime.newSpanId()
        Bool sampled = parent.sampled()
        SpanContext context = new SpanContext(parent.traceId(), spanId, parent.spanId(), sampled,
            parent.baggage())
        Span span = self._newSpan(name, context, kind, sampled)
        self._push(span)
        return span
    }

    Span _startClosed(String name, SpanContext? parent, SpanKind kind) {
        String traceId = self._runtime.newTraceId()
        String spanId = self._runtime.newSpanId()
        String? parentId = null
        Bool sampled = false
        if parent != null {
            SpanContext resolved = parent as SpanContext
            traceId = resolved.traceId()
            parentId = resolved.spanId()
            sampled = resolved.sampled()
        }
        SpanContext context = new SpanContext(traceId, spanId, parentId, sampled, traceEmptyMap())
        Span span = new Span(name, context, kind, self)
        span.setLimits(self._options.getMaxAttributes(), self._options.getMaxEvents())
        span.setRecording(false)
        return span
    }

    Span startSpan(String name) { return self.startSpanKind(name, SpanKind.Internal) }

    Span startSpanKind(String name, SpanKind kind) {
        if name == null || kind == null { throw "Tracer.startSpanKind: null argument" }
        if name.length() == 0 || name.length() > 256 { throw "Tracer.startSpanKind: invalid name" }
        if kind == SpanKind.Unknown { throw "Tracer.startSpanKind: invalid kind" }
        if self.isClosed() { return self._startClosed(name, null, kind) }
        Span? parent = self.currentSpan()
        if parent == null { return self._startRoot(name, kind) }
        Span resolved = parent as Span
        return self._startChild(name, resolved.context(), kind)
    }

    Span startSpanFrom(String name, SpanContext? parent) {
        return self.startSpanFromKind(name, parent, SpanKind.Internal)
    }

    Span startSpanFromKind(String name, SpanContext? parent, SpanKind kind) {
        if name == null || kind == null { throw "Tracer.startSpanFromKind: null argument" }
        if name.length() == 0 || name.length() > 256 { throw "Tracer.startSpanFromKind: invalid name" }
        if kind == SpanKind.Unknown { throw "Tracer.startSpanFromKind: invalid kind" }
        if parent != null {
            SpanContext checkedParent = parent as SpanContext
            if !checkedParent.isValid() { throw "Tracer.startSpanFromKind: invalid parent" }
        }
        if self.isClosed() { return self._startClosed(name, parent, kind) }
        if parent == null { return self._startRoot(name, kind) }
        SpanContext resolved = parent as SpanContext
        return self._startChild(name, resolved, kind)
    }

    Void inject(SpanContext context, Map<String, String> carrier) {
        if context == null || carrier == null { throw "Tracer.inject: null argument" }
        Propagator propagator = self._propagator
        if context.isValid() { propagator.inject(context, carrier) }
    }

    SpanContext? extract(Map<String, String> carrier) {
        if carrier == null { throw "Tracer.extract: null carrier" }
        return self._propagator.extract(carrier)
    }

    Result<Unit, Error> close() {
        self._monitor.enter()
        if self._closed {
            Error? cached = self._closeError
            self._monitor.exit()
            if cached != null { return Err(cached as Error) }
            return Ok()
        }
        self._closed = true
        Result<Unit, Error> result = self._runtime.close()
        if result.isErr() { self._closeError = result.error() }
        self._monitor.exit()
        return result
    }

    Result<Unit, Error> shutdown() { return self.close() }
}
