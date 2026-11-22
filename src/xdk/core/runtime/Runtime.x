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
