// xdk.runtime —— 诊断、退出、时钟、运行时信息与统计（T0-A/T0-X）
// Tier: T0；依赖：runtime_raw.xfb；稳定性：stable。
//
// 原语由 runtime_raw.xfb 提供；env 在后续切片补齐，dumpTasks 已接入。
package xdk.runtime

Void diagnose(String msg) {
    Int rc = diagnoseRaw(msg)
    if rc != 0 {
        diagnoseRaw("diagnose failed")
    }
}

Void exit(Int code) {
    Int rc = exitRaw(code)
    if rc != 0 {
        diagnose("exit failed")
    }
}

Long nowMono() {
    return nowMonoRaw()
}

Long nowWall() {
    return nowWallRaw()
}

void dumpTasks() {
    dumpTasksRaw()
}


enum HealthState {
    Unknown,
    Healthy,
    Degraded,
    Starting,
    Stopping,
    Stopped,
    Unhealthy,
}

// ---------- RuntimeMonitor（B3.1；执行层内部原语） ----------
// 不是 xdk.runtime 的 8 个公开类型之一；供 xdk.execution 的 Mutex/Once/
// WaitGroup/TaskGroup 等内部同步使用。
//
// mini 不支持同名方法重载，因此无上下文等待用 wait()，可取消等待用
// waitContext(Context)；两者语义对应设计文档的 wait() / wait(Context)。
class RuntimeMonitor {
    final Long _handle

    RuntimeMonitor() {
        self._handle = monitorNewRaw()
    }

    void enter() {
        monitorEnterRaw(self._handle)
    }

    void exit() {
        monitorExitRaw(self._handle)
    }

    // 等待一次通知；可能虚假唤醒，调用方必须循环重查条件。
    void wait() {
        monitorWaitRaw(self._handle)
    }

    // 可取消等待：true = 被通知/已关闭；false = Context 已取消。
    Bool waitContext(Context context) {
        return monitorWaitContextRaw(self._handle, context) != 0
    }

    void notifyAll() {
        monitorNotifyAllRaw(self._handle)
    }

    // notify 是 notifyAll 的单数别名；语义一致（唤醒全部等待者）。
    void notify() {
        monitorNotifyAllRaw(self._handle)
    }

    // 幂等关闭：重复调用安全；关闭后等待者被唤醒，wait 不再阻塞。
    void close() {
        monitorCloseRaw(self._handle)
    }

    Bool isClosed() {
        return monitorClosedRaw(self._handle) != 0
    }
}


// ---------- Health（T0-X；服务健康元数据） ----------

String healthStateName(HealthState state) {
    if state == HealthState.Unknown { return "unknown" }
    if state == HealthState.Healthy { return "healthy" }
    if state == HealthState.Degraded { return "degraded" }
    if state == HealthState.Starting { return "starting" }
    if state == HealthState.Stopping { return "stopping" }
    if state == HealthState.Stopped { return "stopped" }
    return "unhealthy"
}

HealthState? healthStateFromName(String name) {
    if name == null { return null }
    String value = name.toLower()
    if value == "healthy" { return HealthState.Healthy }
    if value == "degraded" { return HealthState.Degraded }
    if value == "starting" { return HealthState.Starting }
    if value == "stopping" { return HealthState.Stopping }
    if value == "stopped" { return HealthState.Stopped }
    if value == "unhealthy" { return HealthState.Unhealthy }
    return null
}

Int healthStateRank(HealthState state) {
    if state == HealthState.Unknown { return 6 }
    if state == HealthState.Healthy { return 0 }
    if state == HealthState.Degraded { return 1 }
    if state == HealthState.Starting { return 2 }
    if state == HealthState.Stopping { return 3 }
    if state == HealthState.Stopped { return 4 }
    return 5
}

Bool healthStateIsHealthy(HealthState state) {
    return state == HealthState.Healthy
}

Bool healthStateIsReady(HealthState state) {
    return state == HealthState.Healthy || state == HealthState.Degraded
}

class HealthReport {
    final HealthState _state
    final String _message
    final Long _timestampMono
    final Map<String, String> _details

    HealthReport(HealthState state, String message, Long timestampMono, Map<String, String> details) {
        if state == null { throw "HealthReport: null state" }
        if message == null { throw "HealthReport: null message" }
        if timestampMono < 0 { throw "HealthReport: negative timestamp" }
        if details == null { throw "HealthReport: null details" }
        self._state = state
        self._message = message
        self._timestampMono = timestampMono
        Map<String, String> copied = [:]
        List<String> keys = details.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null { throw "HealthReport: null detail key" }
            copied.put(key, details.getOr(key, ""))
            index = index + 1
        }
        self._details = copied
    }

    static HealthReport of(HealthState state, String message, Map<String, String> details) {
        return new HealthReport(state, message, nowMono(), details)
    }

    static HealthReport healthy(String message) {
        Map<String, String> empty = [:]
        return HealthReport.of(HealthState.Healthy, message, empty)
    }

    static HealthReport degraded(String message) {
        Map<String, String> empty = [:]
        return HealthReport.of(HealthState.Degraded, message, empty)
    }

    static HealthReport unhealthy(String message) {
        Map<String, String> empty = [:]
        return HealthReport.of(HealthState.Unhealthy, message, empty)
    }

    HealthState state() { return self._state }
    String message() { return self._message }
    Long timestampMono() { return self._timestampMono }

    Map<String, String> details() {
        Map<String, String> result = [:]
        List<String> keys = self._details.keys()
        Int index = 0
        while index < keys.length() {
            result.put(keys.get(index), self._details.getOr(keys.get(index), ""))
            index = index + 1
        }
        return result
    }

    String detailOr(String key, String fallback) {
        return self._details.getOr(key, fallback)
    }

    Bool hasDetail(String key) { return self._details.has(key) }
    Int detailCount() { return self._details.keys().length() }

    HealthReport withMessage(String message) {
        return new HealthReport(self._state, message, self._timestampMono, self._details)
    }

    HealthReport withDetail(String key, String value) {
        Map<String, String> next = self.details()
        next.put(key, value)
        return new HealthReport(self._state, self._message, self._timestampMono, next)
    }

    Bool isHealthy() { return self._state == HealthState.Healthy }
    Bool isReady() { return self._state == HealthState.Healthy || self._state == HealthState.Degraded }
    Bool isTerminal() { return self._state == HealthState.Stopped }

    String describe() {
        return "HealthReport(state=" + healthStateName(self._state) +
            " message=" + self._message + " timestampMono=" + str(self._timestampMono) +
            " details=" + str(self.detailCount()) + ")"
    }

    HealthReport copy() {
        return new HealthReport(self._state, self._message, self._timestampMono, self._details)
    }

    Bool equals(HealthReport other) {
        if other == null { return false }
        if self._state != other.state() { return false }
        if self._message != other.message() { return false }
        if self._timestampMono != other.timestampMono() { return false }
        if self.detailCount() != other.detailCount() { return false }
        List<String> keys = self._details.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if !other.hasDetail(key) { return false }
            if self._details.getOr(key, "") != other.detailOr(key, "") { return false }
            index = index + 1
        }
        return true
    }
}

// ---------- RuntimeInfo（T0-X） ----------

// 版本常量与 xdk.meta 保持一致；runtime 位于依赖底层，不反向导入 meta。
@Value
@Builder
class RuntimeInfo {
    final String languageVersion
    final String xdkVersion
    final String platform
    final String arch
    final String mode

    RuntimeInfo(String languageVersion0, String xdkVersion0, String platform0, String arch0, String mode0) {
        self.languageVersion = languageVersion0
        self.xdkVersion = xdkVersion0
        self.platform = platform0
        self.arch = arch0
        self.mode = mode0
    }

    Bool complete() {
        return self.languageVersion.length() > 0 &&
            self.xdkVersion.length() > 0 &&
            self.platform.length() > 0 &&
            self.arch.length() > 0 &&
            self.mode.length() > 0
    }

    String describe() {
        return "mini " + self.languageVersion + " / xdk " + self.xdkVersion +
            " / " + self.platform + "-" + self.arch + " / " + self.mode
    }
}

RuntimeInfo runtimeInfo() {
    return new RuntimeInfo("3.4.0", "1.0.0", runtimePlatformRaw(), runtimeArchRaw(), buildModeRaw())
}

// ---------- 分配/GC 统计（T0-X） ----------

@Value
class RuntimeStats {
    final Long allocs
    final Long frees
    final Long bytes
    final Long gcCollections
    final Long gcFreed

    RuntimeStats(Long allocs0, Long frees0, Long bytes0, Long gcCollections0, Long gcFreed0) {
        self.allocs = allocs0
        self.frees = frees0
        self.bytes = bytes0
        self.gcCollections = gcCollections0
        self.gcFreed = gcFreed0
    }

    Long live() {
        return self.allocs - self.frees
    }
}

RuntimeStats stats() {
    return new RuntimeStats(statsAllocsRaw(), statsFreesRaw(), statsBytesRaw(),
        statsGcCollectionsRaw(), statsGcFreedRaw())
}

Bool statsEnabled() {
    return statsEnabledRaw() != 0
}

void statsSetEnabled(Bool enabled) {
    statsSetEnabledRaw(enabled ? 1 : 0)
}

void statsReset() {
    statsResetRaw()
}
