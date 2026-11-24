package xdk.audit
import xdk.collections
import xdk.errors
import xdk.runtime
import xdk.text

enum AuditLevel {
    Unknown,
    Info,
    Warning,
    Critical,
}

String auditLevelName(AuditLevel level) {
    if level == AuditLevel.Info { return "info" }
    if level == AuditLevel.Warning { return "warning" }
    if level == AuditLevel.Critical { return "critical" }
    return "unknown"
}

AuditLevel? auditLevelFromName(String name) {
    if name == null { return null }
    String value = name.toLower()
    if value == "info" { return AuditLevel.Info }
    if value == "warning" { return AuditLevel.Warning }
    if value == "critical" { return AuditLevel.Critical }
    return null
}

Int auditLevelRank(AuditLevel level) {
    if level == AuditLevel.Info { return 0 }
    if level == AuditLevel.Warning { return 1 }
    if level == AuditLevel.Critical { return 2 }
    return -1
}

class AuditEvent {
    final String _actor
    final String _action
    final String _resource
    final String _outcome
    final AuditLevel _level
    final Long _timestampMono
    final Map<String, String> _fields

    AuditEvent(String actor, String action, String resource, String outcome,
               AuditLevel level, Long timestampMono, Map<String, String> fields) {
        if actor == null || actor == "" { throw "AuditEvent: empty actor" }
        if action == null || action == "" { throw "AuditEvent: empty action" }
        if resource == null { throw "AuditEvent: null resource" }
        if outcome == null || outcome == "" { throw "AuditEvent: empty outcome" }
        if level == null { throw "AuditEvent: null level" }
        if timestampMono < 0 { throw "AuditEvent: negative timestamp" }
        if fields == null { throw "AuditEvent: null fields" }
        self._actor = actor
        self._action = action
        self._resource = resource
        self._outcome = outcome
        self._level = level
        self._timestampMono = timestampMono
        Map<String, String> fieldCopy = [:]
        self._fields = fieldCopy
        List<String> keys = fields.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null || key == "" { throw "AuditEvent: empty field key" }
            String value = fields.getOr(key, "")
            if value == null { throw "AuditEvent: null field value" }
            self._fields.put(key, value)
            index = index + 1
        }
    }

    static AuditEvent of(String actor, String action, String resource, String outcome) {
        Map<String, String> emptyFields = [:]
        return new AuditEvent(actor, action, resource, outcome, AuditLevel.Info, nowMono(), emptyFields)
    }

    String actor() { return self._actor }
    String action() { return self._action }
    String resource() { return self._resource }
    String outcome() { return self._outcome }
    AuditLevel level() { return self._level }
    Long timestampMono() { return self._timestampMono }
    Map<String, String> fields() {
        Map<String, String> result = [:]
        List<String> keys = self._fields.keys()
        Int index = 0
        while index < keys.length() {
            result.put(keys.get(index), self._fields.getOr(keys.get(index), ""))
            index = index + 1
        }
        return result
    }

    AuditEvent withField(String key, String value) {
        if key == null || key == "" { throw "AuditEvent.withField: empty key" }
        if value == null { throw "AuditEvent.withField: null value" }
        Map<String, String> next = self.fields()
        next.put(key, value)
        return new AuditEvent(self._actor, self._action, self._resource, self._outcome,
            self._level, self._timestampMono, next)
    }

    AuditEvent withLevel(AuditLevel level) {
        if level == null { throw "AuditEvent.withLevel: null level" }
        return new AuditEvent(self._actor, self._action, self._resource, self._outcome,
            level, self._timestampMono, self._fields)
    }

    String describe() {
        return auditLevelName(self._level) + " mono=" + str(self._timestampMono) +
            " actor=" + self._actor + " action=" + self._action +
            " resource=" + self._resource + " outcome=" + self._outcome +
            " fields=" + str(self._fields.keys().length())
    }
}

protocol AuditSink {
    Result<Unit, Error> write(AuditEvent event);
    Result<Unit, Error> flush();
    Void close();
    Bool isOpen();
}

class AuditRedactor {
    final RuntimeMonitor _monitor
    final List<Regex> _patterns
    final List<String> _replacements

    AuditRedactor() {
        self._monitor = new RuntimeMonitor()
        self._patterns = []
        self._replacements = []
    }

    AuditRedactor addPattern(Regex pattern, String replacement) {
        if pattern == null { throw "AuditRedactor.addPattern: null pattern" }
        if replacement == null || replacement == "" {
            throw "AuditRedactor.addPattern: empty replacement"
        }
        self._monitor.enter()
        self._patterns.push(pattern)
        self._replacements.push(replacement)
        self._monitor.exit()
        return self
    }

    String _apply(String text, List<Regex> patterns, List<String> replacements) {
        String result = text
        Int index = 0
        while index < patterns.length() {
            result = patterns.get(index).replaceAll(result, replacements.get(index))
            index = index + 1
        }
        return result
    }

    String redact(String text) {
        if text == null { throw "AuditRedactor.redact: null text" }
        self._monitor.enter()
        List<Regex> patterns = self._patterns.copy()
        List<String> replacements = self._replacements.copy()
        self._monitor.exit()
        return self._apply(text, patterns, replacements)
    }

    AuditEvent redactEvent(AuditEvent event) {
        if event == null { throw "AuditRedactor.redactEvent: null event" }
        self._monitor.enter()
        List<Regex> patterns = self._patterns.copy()
        List<String> replacements = self._replacements.copy()
        self._monitor.exit()
        Map<String, String> source = event.fields()
        Map<String, String> fields = [:]
        List<String> keys = source.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            fields.put(key, self._apply(source.getOr(key, ""), patterns, replacements))
            index = index + 1
        }
        return new AuditEvent(
            self._apply(event.actor(), patterns, replacements),
            self._apply(event.action(), patterns, replacements),
            self._apply(event.resource(), patterns, replacements),
            self._apply(event.outcome(), patterns, replacements),
            event.level(), event.timestampMono(), fields)
    }

    Void clear() {
        self._monitor.enter()
        self._patterns.clear()
        self._replacements.clear()
        self._monitor.exit()
    }
}

class AuditLogger {
    final AuditSink _sink
    final RuntimeMonitor _monitor
    final RuntimeMonitor _sinkMonitor
    final Map<String, String> _fields
    AuditRedactor? _redactor
    Bool _closed

    AuditLogger(AuditSink sink) {
        if sink == null { throw "AuditLogger: null sink" }
        self._sink = sink
        self._monitor = new RuntimeMonitor()
        self._sinkMonitor = new RuntimeMonitor()
        Map<String, String> fieldCopy = [:]
        self._fields = fieldCopy
        self._redactor = null
        self._closed = false
    }

    Error _closedError() {
        return new BasicError(ErrorKind.Unavailable, "audit logger is closed")
    }

    AuditLogger withField(String key, String value) {
        if key == null || key == "" { throw "AuditLogger.withField: empty key" }
        if value == null { throw "AuditLogger.withField: null value" }
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            throw "AuditLogger.withField: closed"
        }
        self._fields.put(key, value)
        self._monitor.exit()
        return self
    }

    AuditLogger withRedactor(AuditRedactor redactor) {
        if redactor == null { throw "AuditLogger.withRedactor: null redactor" }
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            throw "AuditLogger.withRedactor: closed"
        }
        self._redactor = redactor
        self._monitor.exit()
        return self
    }

    AuditEvent _mergeDefaults(AuditEvent event) {
        Map<String, String> merged = event.fields()
        List<String> keys = self._fields.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if !merged.has(key) {
                merged.put(key, self._fields.getOr(key, ""))
            }
            index = index + 1
        }
        return new AuditEvent(event.actor(), event.action(), event.resource(), event.outcome(),
            event.level(), event.timestampMono(), merged)
    }

    Result<Unit, Error> log(AuditEvent event) {
        if event == null { throw "AuditLogger.log: null event" }
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return Err(self._closedError())
        }
        AuditEvent prepared = self._mergeDefaults(event)
        AuditRedactor? redactor = self._redactor
        self._monitor.exit()
        if redactor != null {
            AuditRedactor concrete = redactor as AuditRedactor
            prepared = concrete.redactEvent(prepared)
        }
        self._sinkMonitor.enter()
        self._monitor.enter()
        Bool closed = self._closed
        self._monitor.exit()
        if closed {
            self._sinkMonitor.exit()
            return Err(self._closedError())
        }
        Result<Unit, Error> written = self._sink.write(prepared)
        self._sinkMonitor.exit()
        return written
    }

    Result<Unit, Error> logAction(String actor, String action, String resource, String outcome) {
        return self.log(AuditEvent.of(actor, action, resource, outcome))
    }

    Result<Unit, Error> flush() {
        self._monitor.enter()
        Bool closed = self._closed
        self._monitor.exit()
        if closed { return Err(self._closedError()) }
        self._sinkMonitor.enter()
        self._monitor.enter()
        closed = self._closed
        self._monitor.exit()
        if closed {
            self._sinkMonitor.exit()
            return Err(self._closedError())
        }
        Result<Unit, Error> result = self._sink.flush()
        self._sinkMonitor.exit()
        return result
    }

    Result<Unit, Error> close() {
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return Ok()
        }
        self._closed = true
        self._monitor.exit()
        self._sinkMonitor.enter()
        Result<Unit, Error> flushed = self._sink.flush()
        self._sink.close()
        self._sinkMonitor.exit()
        if flushed.isErr() { return flushed }
        return Ok()
    }

    Bool isClosed() {
        self._monitor.enter()
        Bool result = self._closed
        self._monitor.exit()
        return result
    }
}
