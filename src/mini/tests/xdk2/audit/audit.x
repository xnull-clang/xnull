package xdk2.audit
import xdk.audit
import xdk.errors
import xdk.tasks
import xdk.text

static Error auditError() {
    return new BasicError(ErrorKind.Unavailable, "sink closed")
}

static Error ioError() {
    return new BasicError(ErrorKind.Io, "sink failed")
}

class MemorySink implements AuditSink {
    List<AuditEvent> events
    Bool open
    Bool failWrites
    Bool failFlush
    Int flushes
    Int closes
    MemorySink() {
        self.events = []
        self.open = true
        self.failWrites = false
        self.failFlush = false
        self.flushes = 0
        self.closes = 0
    }
    Result<Unit, Error> write(AuditEvent event) {
        if !self.open { return Err(auditError()) }
        if self.failWrites { return Err(ioError()) }
        self.events.push(event)
        return Ok()
    }
    Result<Unit, Error> flush() {
        if !self.open { return Err(auditError()) }
        if self.failFlush { return Err(ioError()) }
        self.flushes = self.flushes + 1
        return Ok()
    }
    Void close() {
        self.open = false
        self.closes = self.closes + 1
    }
    Bool isOpen() { return self.open }
}

static Int main() {
    print("level=" + auditLevelName(AuditLevel.Info) + "," + auditLevelName(AuditLevel.Warning) + "," + auditLevelName(AuditLevel.Critical))
    AuditLevel? parsed = auditLevelFromName("WARNING")
    print("parse=" + auditLevelName(parsed as AuditLevel) + "," + str(auditLevelFromName("bogus") == null) + "," + str(auditLevelFromName(null) == null))
    print("rank=" + str(auditLevelRank(AuditLevel.Info)) + "," + str(auditLevelRank(AuditLevel.Warning)) + "," + str(auditLevelRank(AuditLevel.Critical)))

    Map<String, String> fields = [:]
    fields.put("role", "admin")
    AuditEvent event = new AuditEvent("alice", "role.grant", "project/42", "success", AuditLevel.Warning, 123, fields)
    fields.put("role", "guest")
    print("event=" + str(event.timestampMono()) + "," + str(event.level() == AuditLevel.Warning) + "," + event.fields().getOr("role", ""))
    AuditEvent derived = event.withField("role", "owner").withLevel(AuditLevel.Critical)
    print("derived=" + str(derived.fields().getOr("role", "")) + "," + str(derived.level() == AuditLevel.Critical) + "," + str(event.fields().getOr("role", "")))
    String description = event.describe()
    print("describe=" + str(description.indexOf("actor=alice") >= 0) + "," + str(description.indexOf("action=role.grant") >= 0) + "," + str(description.indexOf("fields=1") >= 0))
    print("of=" + auditLevelName(AuditEvent.of("bob", "login", "", "success").level()))

    AuditRedactor redactor = new AuditRedactor()
    Regex tokenPattern = Regex.compile("token=[^ ]+").value()
    Regex namePattern = Regex.compile("alice").value()
    redactor.addPattern(tokenPattern, "token=[REDACTED]")
    redactor.addPattern(namePattern, "bob")
    print("redact=" + redactor.redact("alice token=abc"))
    AuditEvent redactedEvent = redactor.redactEvent(event.withField("token", "token=abc"))
    print("redact-event=" + redactedEvent.actor() + "," + redactedEvent.fields().getOr("token", "") + "," +
        str(redactedEvent.level() == AuditLevel.Warning) + "," + str(redactedEvent.timestampMono()))
    print("redact-keys=" + str(redactedEvent.fields().has("token")))
    redactor.clear()
    redactor.clear()
    print("redact-clear=" + redactor.redact("alice token=abc"))

    MemorySink sink = new MemorySink()
    AuditLogger logger = new AuditLogger(sink)
    logger.withField("service", "auth")
    Result<Unit, Error> logged = logger.logAction("alice", "login", "", "success")
    print("log=" + str(logged.isOk()) + "," + str(sink.events.length()) + "," + sink.events.get(0).fields().getOr("service", ""))
    AuditEvent overrideEvent = AuditEvent.of("bob", "logout", "", "success").withField("service", "billing")
    logger.log(overrideEvent)
    print("override=" + sink.events.get(1).fields().getOr("service", ""))

    AuditRedactor loggerRedactor = new AuditRedactor()
    Regex actorPattern = Regex.compile("bob").value()
    loggerRedactor.addPattern(actorPattern, "masked")
    logger.withRedactor(loggerRedactor)
    logger.logAction("bob", "view", "", "success")
    print("logger-redact=" + sink.events.get(2).actor())

    sink.failWrites = true
    Result<Unit, Error> writeError = logger.logAction("alice", "fail", "", "success")
    print("write-error=" + str(writeError.isErr()) + "," + errorKindName(writeError.error().kind()))
    sink.failWrites = false
    sink.failFlush = true
    Result<Unit, Error> flushError = logger.flush()
    print("flush-error=" + str(flushError.isErr()) + "," + errorKindName(flushError.error().kind()))
    sink.failFlush = false
    Result<Unit, Error> firstClose = logger.close()
    Result<Unit, Error> secondClose = logger.close()
    print("close=" + str(firstClose.isOk()) + "," + str(secondClose.isOk()) + "," + str(sink.closes) + "," + str(logger.isClosed()))
    Result<Unit, Error> closedLog = logger.logAction("alice", "late", "", "success")
    Result<Unit, Error> closedFlush = logger.flush()
    print("closed=" + str(closedLog.error().kind() == ErrorKind.Unavailable) + "," + str(closedFlush.error().kind() == ErrorKind.Unavailable))

    MemorySink concurrentSink = new MemorySink()
    AuditLogger concurrentLogger = new AuditLogger(concurrentSink)
    TaskGroup group = TaskGroup.create(Context.background())
    Task<Int> first = group.spawn(() -> {
        Int index = 0
        while index < 20 {
            concurrentLogger.logAction("a", "write", "", "success")
            index = index + 1
        }
        return Ok(1)
    })
    Task<Int> second = group.spawn(() -> {
        Int index = 0
        while index < 20 {
            concurrentLogger.logAction("b", "write", "", "success")
            index = index + 1
        }
        return Ok(1)
    })
    Result<Int, TaskError> firstJoined = first.join()
    Result<Int, TaskError> secondJoined = second.join()
    group.close()
    print("concurrent=" + str(firstJoined.isOk()) + "," + str(secondJoined.isOk()) + "," + str(concurrentSink.events.length()))
    concurrentLogger.close()
    return 0
}
