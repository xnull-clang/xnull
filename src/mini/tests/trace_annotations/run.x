package app.trace
import xdk.trace
import xdk.errors
import generated.TraceGenerated

static Error traceFailure() {
    return new BasicError(ErrorKind.Timeout, "operation timed out")
}

class Service {
    Int successes
    Int failures
    Service() {
        self.successes = 0
        self.failures = 0
    }
    Result<Int, Error> success(Int id) {
        self.successes = self.successes + 1
        return Ok(id)
    }
    Result<Int, Error> failure(Int id) {
        self.failures = self.failures + 1
        return Err(traceFailure())
    }
}

static Int main() {
    TraceOptions options = new TraceOptions()
    Tracer tracer = Tracer.create(options).value()
    Service service = new Service()

    Result<Int, Error> success = Service_successTraced(service, tracer, 7)
    List<Span> afterSuccess = tracer.completedSpans()
    Span successSpan = afterSuccess.get(0)
    print("success=" + str(success.isOk()) + "," + str(success.value()) + "," + str(service.successes))
    print("success-span=" + successSpan.name() + "," + spanStatusName(successSpan.status()) + "," +
        str(successSpan.events().length()) + "," + str(successSpan.duration().millis() >= 0))

    Result<Int, Error> failure = Service_failureTraced(service, tracer, 8)
    List<Span> afterFailure = tracer.completedSpans()
    Span failureSpan = afterFailure.get(1)
    print("failure=" + str(failure.isErr()) + "," + errorKindName(failure.error().kind()) + "," +
        str(service.failures))
    print("failure-span=" + failureSpan.name() + "," + spanStatusName(failureSpan.status()) + "," +
        str(failureSpan.events().length()) + "," + failureSpan.events().get(0).name() + "," +
        str(failureSpan.statusDescription().indexOf("operation timed out") >= 0))

    List<Span> snapshot = tracer.completedSpans()
    snapshot.clear()
    print("snapshot=" + str(tracer.completedSpans().length()))

    tracer.close()
    Result<Int, Error> afterClose = Service_successTraced(service, tracer, 9)
    List<Span> afterClosed = tracer.completedSpans()
    Span closedSpan = afterClosed.get(2)
    print("closed=" + str(afterClose.isOk()) + "," + str(afterClose.value()) + "," +
        str(service.successes) + "," + str(afterClosed.length()) + "," +
        spanStatusName(closedSpan.status()) + "," + str(closedSpan.isRecording()))

    TraceOptions loopOptions = new TraceOptions()
    Tracer loopTracer = Tracer.create(loopOptions).value()
    Int index = 0
    while index < 260 {
        Service_successTraced(service, loopTracer, index)
        index = index + 1
    }
    List<Span> capped = loopTracer.completedSpans()
    print("cap=" + str(capped.length()) + "," + capped.get(0).name() + "," +
        capped.get(capped.length() - 1).name())
    loopTracer.close()
    return 0
}
