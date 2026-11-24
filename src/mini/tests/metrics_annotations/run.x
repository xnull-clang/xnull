package app.metrics
import xdk.metrics
import xdk.errors
import xdk.time
import xdk.tasks
import xdk.io
import generated.MetricsGenerated

static Error runFailure() {
    return new BasicError(ErrorKind.Network, "operation failed")
}

static Error exporterUnavailable() {
    return new BasicError(ErrorKind.Unavailable, "exporter closed")
}

static Error exporterCancelled() {
    return new BasicError(ErrorKind.Cancelled, "cancelled")
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
        sleepMs(5)
        return Ok(id)
    }
    Result<Int, Error> failure(Int id) {
        self.failures = self.failures + 1
        sleepMs(5)
        return Err(runFailure())
    }
}

class MemoryExporter implements Exporter {
    Bool open
    Int exports
    Int flushes

    MemoryExporter() {
        self.open = true
        self.exports = 0
        self.flushes = 0
    }

    MetricsFormat format() { return 1 as MetricsFormat }
    Bool isOpen() { return self.open }

    Result<Unit, Error> export(Context context, Registry registry, Writer writer) {
        if context == null || registry == null || writer == null {
            throw "MemoryExporter.export: null argument"
        }
        if !self.open { return Err(exporterUnavailable()) }
        if context.isCancelled() { return Err(exporterCancelled()) }
        List<MetricFamily> families = registry.snapshot()
        writer.writeU8(65)
        self.exports = self.exports + 1
        return Ok()
    }

    Result<Unit, Error> flush() {
        if !self.open { return Err(exporterUnavailable()) }
        self.flushes = self.flushes + 1
        return Ok()
    }

    Result<Unit, Error> close() {
        if !self.open { return Ok() }
        self.open = false
        return Ok()
    }
}

static Int main() {
    Context context = Context.background()
    Service service = new Service()
    Registry registry = new Registry()

    Result<Int, Error> success = Service_successMetered(service, registry, 7)
    print("success=" + str(success.isOk()) + "," + str(success.value()) + "," + str(service.successes))
    Metric? successMetric = registry.get("op.success")
    MetricTimer successTimer = successMetric as MetricTimer
    print("success-timer=" + str(successTimer.count()) + "," + str(successTimer.total().millis() > 0))

    Result<Int, Error> failure = Service_failureMetered(service, registry, 8)
    print("failure=" + str(failure.isErr()) + "," + errorKindName(failure.error().kind()) + "," +
        str(service.failures))
    Metric? failureMetric = registry.get("Service.failure")
    MetricTimer failureTimer = failureMetric as MetricTimer
    print("failure-timer=" + str(failureTimer.count()) + "," + str(failureTimer.total().millis() > 0))

    Registry conflictRegistry = new Registry()
    Result<Gauge, Error> conflictGauge = conflictRegistry.gauge("op.success")
    Int before = service.successes
    Result<Int, Error> conflict = Service_successMetered(service, conflictRegistry, 9)
    print("conflict=" + str(conflict.isOk()) + "," + str(conflict.value()) + "," +
        str(service.successes == before + 1) + "," + str(conflictGauge.isOk()) + "," +
        str(conflictRegistry.get("op.success") != null))

    MemoryExporter exporter = new MemoryExporter()
    Writer writer = new Writer()
    Registry exported = new Registry()
    Result<Counter, Error> created = exported.counter("requests")
    created.value().inc()
    Result<Unit, Error> result = exporter.export(context, exported, writer)
    print("exporter=" + metricsFormatName(exporter.format()) + "," + str(result.isOk()) + "," +
        str(exporter.exports) + "," + str(writer.length()) + "," + str(writer.isClosed()) + "," +
        str(exporter.isOpen()))
    Result<Unit, Error> flush = exporter.flush()
    print("flush=" + str(flush.isOk()) + "," + str(exporter.flushes))
    Result<Unit, Error> closed = exporter.close()
    Result<Unit, Error> closedAgain = exporter.close()
    print("close=" + str(closed.isOk()) + "," + str(closedAgain.isOk()) + "," + str(exporter.isOpen()))
    Result<Unit, Error> afterClose = exporter.export(context, exported, writer)
    Result<Unit, Error> flushAfterClose = exporter.flush()
    print("closed-export=" + errorKindName(afterClose.error().kind()) + "," +
        errorKindName(flushAfterClose.error().kind()))
    print("writer-after=" + str(writer.isClosed()) + "," + str(writer.length()))

    Context cancelled = Context.background()
    cancelled.cancel()
    Writer cancelledWriter = new Writer()
    MemoryExporter cancelledExporter = new MemoryExporter()
    Result<Unit, Error> cancelledResult = cancelledExporter.export(cancelled, exported, cancelledWriter)
    print("cancelled=" + errorKindName(cancelledResult.error().kind()) + "," +
        str(cancelledWriter.length()) + "," + str(cancelledExporter.exports))
    return 0
}
