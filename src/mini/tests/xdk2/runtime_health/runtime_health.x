package xdk2.runtime_health
import xdk.runtime
import xdk.tasks
import xdk.time

class SignalFlag {
    Bool done
    SignalFlag() { self.done = false }
}

static Int main() {
    print("state-names=" + healthStateName(HealthState.Healthy) + "," + healthStateName(HealthState.Degraded) + "," + healthStateName(HealthState.Starting) + "," + healthStateName(HealthState.Stopping) + "," + healthStateName(HealthState.Stopped) + "," + healthStateName(HealthState.Unhealthy))
    HealthState? healthy = healthStateFromName("HeAlThY")
    HealthState healthyValue = healthy as HealthState
    print("state-parse=" + healthStateName(healthyValue) + "," + str(healthStateFromName("bogus") == null))
    print("state-rank=" + str(healthStateRank(HealthState.Healthy)) + "," + str(healthStateRank(HealthState.Unhealthy)))
    print("state-flags=" + str(healthStateIsHealthy(HealthState.Healthy)) + "," + str(healthStateIsHealthy(HealthState.Degraded)) + "," + str(healthStateIsReady(HealthState.Degraded)) + "," + str(healthStateIsReady(HealthState.Starting)))

    HealthReport healthyReport = HealthReport.healthy("all good")
    print("report=" + str(healthyReport.isHealthy()) + "," + str(healthyReport.isReady()) + "," + str(healthyReport.isTerminal()) + "," + str(healthyReport.timestampMono() >= 0))
    HealthReport degradedReport = HealthReport.degraded("slow")
    HealthReport unhealthyReport = HealthReport.unhealthy("bad")
    Map<String, String> noDetails = [:]
    print("report-flags=" + str(degradedReport.isReady()) + "," + str(unhealthyReport.isHealthy()) + "," + str(HealthReport.of(HealthState.Stopped, "done", noDetails).isTerminal()))

    Map<String, String> details = [:]
    details.put("node", "a")
    details.put("pool", "2")
    HealthReport detailed = HealthReport.of(HealthState.Degraded, "partial", details)
    print("details=" + str(detailed.detailCount()) + "," + detailed.detailOr("node", "?") + "," + str(detailed.hasDetail("pool")) + "," + detailed.detailOr("missing", "fallback"))
    HealthReport messageChanged = detailed.withMessage("changed")
    HealthReport detailChanged = detailed.withDetail("region", "eu")
    print("immutable=" + detailed.message() + "," + messageChanged.message() + "," + str(detailed.detailCount()) + "," + str(detailChanged.detailCount()) + "," + detailChanged.detailOr("region", "?"))
    HealthReport copied = detailed.copy()
    print("report-compare=" + str(copied.equals(detailed)) + "," + str(detailed.describe().indexOf("state=degraded") >= 0))

    RuntimeMonitor monitor = new RuntimeMonitor()
    print("monitor-closed=" + str(monitor.isClosed()))
    monitor.enter()
    monitor.exit()
    monitor.close()
    print("monitor-close=" + str(monitor.isClosed()))
    monitor.close()
    print("monitor-close-idempotent=" + str(monitor.isClosed()))

    Context cancelled = Context.background()
    cancelled.cancel()
    print("wait-cancelled=" + str(monitor.waitContext(cancelled)))

    RuntimeMonitor notifier = new RuntimeMonitor()
    Context context = Context.background()
    TaskGroup group = TaskGroup.create(context)
    SignalFlag flag = new SignalFlag()
    Task<Int> waiter = group.spawn(() -> {
        Bool signalled = notifier.waitContext(context)
        flag.done = signalled
        return Ok(1)
    })
    Int guard = 0
    while guard < 400 && !flag.done {
        notifier.notifyAll()
        sleepMs(2)
        guard = guard + 1
    }
    Result<Int, TaskError> joined = waiter.joinDeadline(nowMono() + 2000)
    print("wait-notify=" + str(joined.isOk()) + "," + str(flag.done))
    print("group-close=" + str(group.close().isOk()))
    notifier.close()
    print("notifier-wait-closed=" + str(notifier.waitContext(Context.background())) + "," + str(notifier.isClosed()))
    return 0
}
