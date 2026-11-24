package app.audit
import xdk.audit
import xdk.errors
import generated.AuditGenerated

static Error auditFailure() {
    return new BasicError(ErrorKind.Network, "audit failure")
}

static Error closedFailure() {
    return closedFailure()
}

static Error sinkFailure() {
    return new BasicError(ErrorKind.Io, "sink failure")
}

class MemorySink implements AuditSink {
    List<AuditEvent> events
    Bool open
    Bool failWrites
    MemorySink() {
        self.events = []
        self.open = true
        self.failWrites = false
    }
    Result<Unit, Error> write(AuditEvent event) {
        if !self.open { return Err(closedFailure()) }
        if self.failWrites { return Err(sinkFailure()) }
        self.events.push(event)
        return Ok()
    }
    Result<Unit, Error> flush() {
        if !self.open { return Err(closedFailure()) }
        return Ok()
    }
    Void close() { self.open = false }
    Bool isOpen() { return self.open }
}

class Service {
    Int successes
    Int failures
    Service() {
        self.successes = 0
        self.failures = 0
    }
    Result<Int, Error> login(Int id) {
        self.successes = self.successes + 1
        return Ok(id)
    }
    Result<Int, Error> fail(Int id) {
        self.failures = self.failures + 1
        return Err(auditFailure())
    }
}

static Int main() {
    MemorySink sink = new MemorySink()
    AuditLogger logger = new AuditLogger(sink)
    Service service = new Service()

    Result<Int, Error> login = Service_loginAudited(service, logger, "alice", 7)
    AuditEvent successEvent = sink.events.get(0)
    print("login=" + str(login.isOk()) + "," + str(login.value()) + "," + str(service.successes))
    print("success-event=" + successEvent.actor() + "," + successEvent.action() + "," +
        successEvent.resource() + "," + successEvent.outcome() + "," + auditLevelName(successEvent.level()))

    Result<Int, Error> failed = Service_failAudited(service, logger, "bob", 5)
    AuditEvent failureEvent = sink.events.get(1)
    print("fail=" + str(failed.isErr()) + "," + errorKindName(failed.error().kind()) + "," + str(service.failures))
    print("failure-event=" + failureEvent.actor() + "," + failureEvent.action() + "," +
        failureEvent.resource() + "," + failureEvent.outcome() + "," +
        failureEvent.fields().getOr("errorKind", "") + "," + auditLevelName(failureEvent.level()))

    logger.close()
    Result<Int, Error> closedSuccess = Service_loginAudited(service, logger, "carol", 8)
    Result<Int, Error> closedFailure = Service_failAudited(service, logger, "dave", 9)
    print("closed-success=" + errorKindName(closedSuccess.error().kind()) + "," + str(service.successes))
    print("closed-failure=" + errorKindName(closedFailure.error().kind()) + "," + str(service.failures))

    MemorySink failingSink = new MemorySink()
    AuditLogger failingLogger = new AuditLogger(failingSink)
    failingSink.failWrites = true
    Service failingService = new Service()
    Result<Int, Error> writeFailure = Service_loginAudited(failingService, failingLogger, "erin", 1)
    Result<Int, Error> methodFailure = Service_failAudited(failingService, failingLogger, "frank", 2)
    print("write-failure=" + errorKindName(writeFailure.error().kind()) + "," + str(writeFailure.isErr()))
    print("method-failure=" + errorKindName(methodFailure.error().kind()) + "," + str(methodFailure.isErr()))
    return 0
}
