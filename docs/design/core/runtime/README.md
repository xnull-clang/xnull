# `xdk.runtime` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.runtime` |
| 层 | `xdk.core` / L1 |
| 依赖 | 无（只使用运行时服务；不依赖其他 core 包） |
| 被依赖 | `errors`、`time`、`log`、`config`、`cli` 等 |
| 稳定性 | 核心 `stable`；统计/转储 `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.runtime` 提供运行时观测与控制：

- 诊断输出（stderr）；
- 进程退出/中止；
- 单调时钟/墙钟；
- 运行时信息快照；
- 内存/任务统计；
- 任务转储；
- 当前栈文本；
- 健康/就绪聚合。

不提供：日志、环境变量/进程管理、休眠/日期、错误类型、全局错误处理/钩子。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 不依赖 errors | 避免 `errors -> runtime -> errors` 环；runtime 不返回 `Result` |
| 不依赖 time | time 依赖 runtime 的时钟；runtime 只给 `Long` 毫秒/微秒 |
| 不依赖 text | diagnose 只写字符串；格式化由调用方/log 完成 |
| 无全局状态 | 不做全局日志/错误钩子 |
| 快照只读 | 统计信息是不可变快照，不是控制器 |
| 终止性明确 | exit/abort 不返回；不做隐式清理 |
| 诊断不失败 | diagnose 写失败只再诊断，不抛业务错误 |

---

## 3. 能力与边界

| 能力 | 承载 | 说明 |
| --- | --- | --- |
| 诊断 | `diagnose` | 写 stderr 一行 |
| 退出 | `exit` | 0..255；终止 |
| 中止 | `abort` | 诊断 + 134 |
| 单调时钟 | `nowMono`/`nowMicros` | 超时/耗时 |
| 墙钟 | `nowWall` | epoch 毫秒 |
| 运行时信息 | `RuntimeInfo`/`runtimeInfo` | 版本/平台/pid/cwd/启动时间 |
| 内存统计 | `MemoryStats`/`memoryStats` | 堆/外部/峰值/GC |
| 任务统计 | `TaskStats`/`taskStats` | active/queued/completed/failed/cancelled |
| 分配统计 | `RuntimeStats`/`stats`/`statsEnabled`/`statsSetEnabled`/`statsReset` | 分配/释放/字节/GC 计数与开关 |
| 任务转储 | `dumpTasks` | 诊断输出任务快照 |
| 栈文本 | `stackTrace` | 当前栈；诊断 |
| 健康/就绪 | `HealthRegistry`/`HealthReport` | 客户端连接健康、服务器 readiness/liveness |

非目标：日志级别/字段/Sink、全局错误处理器、GC/堆调优、profiler、信号处理、环境/进程启动、日期/时区、休眠。

---

## 4. 类设计索引

| 类型 | 文件 |
| --- | --- |
| `RuntimeInfo` | [`RuntimeInfo.md`](RuntimeInfo.md) |
| `MemoryStats` | [`MemoryStats.md`](MemoryStats.md) |
| `TaskStats` | [`TaskStats.md`](TaskStats.md) |
| `RuntimeStats` | [`RuntimeStats.md`](RuntimeStats.md) |
| `TaskSnapshot`（内部） | [`TaskSnapshot.md`](TaskSnapshot.md) |
| `HealthState` | [`HealthState.md`](HealthState.md) |
| `HealthReport` | [`HealthReport.md`](HealthReport.md) |
| `HealthCheck` | [`HealthCheck.md`](HealthCheck.md) |
| `HealthRegistry` | [`HealthRegistry.md`](HealthRegistry.md) |

## 5. 顶层函数

### 1. `diagnose`

| 项 | 内容 |
| --- | --- |
| 签名 | `void diagnose(String message)` |
| 用途 | 向 stderr 写一行诊断 |
| 参数 | `message`：诊断文本；null 按空串；换行/制表归一为空格 |
| 返回 | 无 |
| 失败 | 无；写失败只再尝试一次诊断 |
| 并发 | 任意任务；底层写串行化 |
| 技术 | 单行归一、stderr 写 |
| 支撑 | 运行时 stderr 写原语 |
| 依赖 | 无 |

```xnull
void diagnose(String message) {
    if message == null {
        message = ""
    }
    String line = message.replace("\n", " ")
    line = line.replace("\r", " ")
    line = line.replace("\t", " ")
    writeStderr(line + "\n")
}
```

### 2. `exit`

| 项 | 内容 |
| --- | --- |
| 签名 | `void exit(Int code)` |
| 用途 | 以退出码终止进程 |
| 参数 | `code`：0..255 |
| 返回 | 无（不返回） |
| 失败 | 越界 → 合同错误（panic） |
| 并发 | 终止性 |
| 技术 | 进程终止 |
| 支撑 | 运行时/OS 退出原语 |
| 依赖 | 无 |

```xnull
void exit(Int code) {
    if code < 0 || code > 255 {
        throw "runtime.exit: code out of range"
    }
    terminateProcess(code)
}
```

### 3. `abort`

| 项 | 内容 |
| --- | --- |
| 签名 | `void abort(String message)` |
| 用途 | 诊断 + 134 终止 |
| 参数 | `message`：诊断文本；可 null |
| 返回 | 无（不返回） |
| 失败 | 无（终止） |
| 并发 | 终止性 |
| 技术 | diagnose + exit 组合 |
| 支撑 | `diagnose`、`exit` |
| 依赖 | 无 |

```xnull
void abort(String message) {
    diagnose(message)
    exit(134)
}
```

### 4. 时钟

| 函数 | 用途 | 参数 | 返回 | 失败 | 技术/支撑 |
| --- | --- | --- | --- | --- | --- |
| `nowMono()` | 单调毫秒 | 无 | `Long` | 无 | 单调时钟原语 |
| `nowWall()` | epoch 毫秒 | 无 | `Long` | 无 | 系统墙钟原语 |
| `nowMicros()` | 单调微秒 | 无 | `Long` | 无 | 单调时钟原语 |

```xnull
Long nowMono() {
    return monotonicMillis()
}

Long nowWall() {
    return epochMillis()
}

Long nowMicros() {
    return monotonicMicros()
}
```

### 5. `runtimeInfo`

| 项 | 内容 |
| --- | --- |
| 签名 | `RuntimeInfo runtimeInfo()` |
| 用途 | 运行时信息快照 |
| 参数 | 无 |
| 返回 | 不可变 `RuntimeInfo` |
| 失败 | 无；未知字段空串/0 |
| 技术 | 运行时信息读取 + 快照构造 |
| 支撑 | 进程 ID/主机名/工作目录/启动时间 |
| 依赖 | `RuntimeInfo` |

```xnull
RuntimeInfo runtimeInfo() {
    return new RuntimeInfo(
        LANG_VERSION,
        XDK_VERSION,
        TARGET_PLATFORM,
        TARGET_ARCH,
        BUILD_MODE,
        processId(),
        hostName(),
        currentWorkingDirectory(),
        processStartMono()
    )
}
```

### 6. `memoryStats`

| 项 | 内容 |
| --- | --- |
| 签名 | `MemoryStats memoryStats()` |
| 用途 | 内存快照 |
| 参数 | 无 |
| 返回 | 不可变 `MemoryStats` |
| 失败 | 无；不支持字段为 0 |
| 技术 | 运行时内存读取 |
| 支撑 | 内存统计原语 |
| 依赖 | `MemoryStats` |

```xnull
MemoryStats memoryStats() {
    MemorySnapshot snapshot = readMemorySnapshot()
    return new MemoryStats(
        snapshot.heapUsed,
        snapshot.heapTotal,
        snapshot.external,
        snapshot.peak,
        snapshot.gcCount
    )
}
```

### 7. `taskStats`

| 项 | 内容 |
| --- | --- |
| 签名 | `TaskStats taskStats()` |
| 用途 | 任务快照 |
| 参数 | 无 |
| 返回 | 不可变 `TaskStats` |
| 失败 | 无；不支持字段为 0 |
| 技术 | 任务系统统计 |
| 支撑 | 任务统计原语 |
| 依赖 | `TaskStats` |

```xnull
TaskStats taskStats() {
    TaskSnapshotSet snapshot = readTaskSnapshot()
    return new TaskStats(
        snapshot.active,
        snapshot.queued,
        snapshot.completed,
        snapshot.failed,
        snapshot.cancelled,
        snapshot.total
    )
}
```

### 8. `dumpTasks`

| 项 | 内容 |
| --- | --- |
| 签名 | `void dumpTasks()` |
| 用途 | 诊断输出任务统计与任务列表 |
| 参数 | 无 |
| 返回 | 无 |
| 失败 | 无；写失败只诊断 |
| 技术 | 任务快照 + 诊断输出 |
| 支撑 | `taskStats`、任务快照、`diagnose` |
| 依赖 | `TaskStats`、`TaskSnapshot` |

```xnull
void dumpTasks() {
    TaskStats stats = taskStats()
    diagnose("tasks: " + stats.describe())
    List<TaskSnapshot> tasks = snapshotTasks()
    Int index = 0
    while index < tasks.length() {
        diagnose(tasks.get(index).describe())
        index = index + 1
    }
}
```

### 9. `stackTrace`

| 项 | 内容 |
| --- | --- |
| 签名 | `String stackTrace()` |
| 用途 | 返回当前栈文本 |
| 参数 | 无 |
| 返回 | 文本；不支持时返回空串 |
| 失败 | 无 |
| 技术 | 栈帧捕获 + 文本拼接 |
| 支撑 | 运行时栈捕获原语 |
| 依赖 | 无 |

```xnull
String stackTrace() {
    List<String> frames = captureStackFrames()
    if frames == null {
        return ""
    }
    String result = ""
    Int index = 0
    while index < frames.length() {
        result = result + frames.get(index) + "\n"
        index = index + 1
    }
    return result
}
```

### 10. 健康状态函数

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `healthStateName` | 稳定名称 | `HealthState state` | `String` | 无 |
| `healthStateFromName` | 名称解析 | `String name` | `HealthState?` | 无 |
| `healthStateRank` | 严重度 | `HealthState state` | `Int` | 无 |
| `healthStateIsHealthy` | 是否健康 | `HealthState state` | `Bool` | 无 |
| `healthStateIsReady` | 是否可服务 | `HealthState state` | `Bool` | 无 |
| `healthStateIsTerminal` | 是否终态 | `HealthState state` | `Bool` | 无 |

详见 [`HealthState.md`](HealthState.md)。健康检查注册见 [`HealthRegistry.md`](HealthRegistry.md)。

### 11. 运行时支撑原语

以下不是 XDK 公共 API，而是 `xdk.runtime` 依赖的运行时底座。它们由运行时/平台提供，XDK 只调用，不在本包重新实现：

| 原语 | 用途 | 返回 | 失败 |
| --- | --- | --- | --- |
| `writeStderr(text)` | 写 stderr | 无 | 无（底层失败只诊断） |
| `terminateProcess(code)` | 终止进程 | 不返回 | 无 |
| `monotonicMillis()` | 单调毫秒 | `Long` | 无 |
| `epochMillis()` | epoch 毫秒 | `Long` | 无 |
| `monotonicMicros()` | 单调微秒 | `Long` | 无 |
| `processId()` | 当前进程 ID | `Int` | 无 |
| `hostName()` | 主机名 | `String` | 无（不可用空串） |
| `currentWorkingDirectory()` | 工作目录 | `String` | 无（不可用空串） |
| `processStartMono()` | 进程启动单调时间 | `Long` | 无 |
| `readMemorySnapshot()` | 内存快照 | `MemorySnapshot` | 无（不支持字段 0） |
| `readTaskSnapshot()` | 任务统计快照 | `TaskSnapshotSet` | 无（不支持字段 0） |
| `snapshotTasks()` | 任务列表快照 | `List<TaskSnapshot>` | 无 |
| `captureStackFrames()` | 当前栈帧 | `List<String>` | 无（不支持空列表） |

`MemorySnapshot`、`TaskSnapshotSet`、`TaskSnapshot` 是运行时内部诊断结构，不属于 XDK 公共类型；`TaskSnapshot` 的 XDK 侧包装见 §7。

### 12. 分配统计

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `stats` | 当前分配/GC 快照 | 无 | `RuntimeStats` | 无；不支持字段 0 |
| `statsEnabled` | 统计是否开启 | 无 | `Bool` | 无 |
| `statsSetEnabled` | 开启/关闭后续计数 | `Bool enabled` | `void` | 无 |
| `statsReset` | 清零计数 | 无 | `void` | 无；不改变开关状态 |

```xnull
RuntimeStats stats() {
    return new RuntimeStats(statsAllocsRaw(), statsFreesRaw(), statsBytesRaw(),
        statsGcCollectionsRaw(), statsGcFreedRaw())
}

Bool statsEnabled() { return statsEnabledRaw() != 0 }
void statsSetEnabled(Bool enabled) { statsSetEnabledRaw(enabled ? 1 : 0) }
void statsReset() { statsResetRaw() }
```

`RuntimeStats.live()` = `allocs - frees`，是近似计数，不是精确堆普查；统计默认关闭。

---

## 6. 场景

### R1：CLI 可恢复失败 vs fatal

文件缺失 → `Result` + `report`；用法错误 → `diagnose` + `exit(2)`；内部不变量破坏 → `abort`；正常 → `exit(0)`。验收：可恢复失败不 abort；fatal 134；诊断单行。

### R2：服务启动与诊断

启动 `runtimeInfo().describe()`；运行 `memoryStats().describe()`/`taskStats().describe()`；异常 `dumpTasks()`/`stackTrace()`。验收：横幅含版本/平台/pid；快照可读；转储不阻塞。

### R3：时钟选择

超时/耗时用 `nowMono`/`nowMicros`；日志/日历用 `nowWall`；deadline 不用墙钟。验收：墙钟回拨不影响超时；单位不混用。

### R4：任务卡死

`taskStats` → `dumpTasks` → `stackTrace` → `exit(70)`/`abort`。验收：能看到 active/queued/任务状态；转储不改变任务状态。

### R5：测试/嵌入

`exit`/`abort` 是终止性的，测试用子进程；诊断出口内部可注入；快照断言格式不依赖精确数值。验收：子进程观察退出码；生产不可替换。

### R6：服务器就绪/存活

`HealthRegistry` 注册 db/cache/queue；`checkAll()` 聚合最严重状态；`isReady` 决定是否接流量。
验收：空注册表视为健康；单项失败不被掩盖；检查非阻塞；details 可定位依赖。

### R7：客户端连接健康

客户端注册 outbound 连接检查；`HealthReport` 记录最近成功/失败时间与错误消息；UI 读取快照。
验收：检查不阻塞 UI；取消/超时不被误报为健康；恢复后状态回到 `Healthy`。

---

## 7. 缺口与决策

| 项 | 决策/缺口 |
| --- | --- |
| diagnose 格式化 | 不支持；调用方拼接或 `log` |
| diagnose 级别 | 无；`log` 负责分级 |
| exit 清理 | 不执行；调用方先 close/flush |
| dumpTasks 格式 | 文本；JSON 为 X |
| stackTrace 符号化 | 不保证完整；文档要求脱敏 |
| MemoryStats 字段 | 因平台而异；缺失为 0 |
| RuntimeStats vs MemoryStats | `RuntimeStats` 是 1.x 分配/GC 计数；`MemoryStats` 是 2.x 内存快照；两者并存，不互相替代 |
| TaskStats 一致性 | 快照尽力；不用于计费 |
| 测试注入 | 内部机制；不进入公共 API |
| 健康检查 | `HealthRegistry` 非阻塞；HTTP 端点/指标导出归  |
| 健康聚合 | 取最严重状态；不提供自动轮询/告警 |
| QUIC/网络 | 不属于 runtime |
| 信号/环境/进程 | 属于 `xdk.sys` |

## 9. 1.x 兼容合同（C7）

| 1.x API | 2.x 合同 | 失败/边界 |
| --- | --- | --- |
| `RuntimeStats` | [`RuntimeStats.md`](RuntimeStats.md)；`allocs/frees/bytes/gcCollections/gcFreed/live` | 计数不可用为 0；`live()` 近似 |
| `stats()` | 顶层 `stats`；返回不可变快照 | 无 |
| `statsEnabled()` / `statsSetEnabled(Bool)` / `statsReset()` | 同签名；默认关闭；reset 不改开关 | 无 |
| `dumpTasks()` | 顶层 `dumpTasks`；诊断 stderr | 格式不作为稳定契约 |
| `nowMicros()` | 顶层 `nowMicros`；单调微秒 | 1.x runtime 只有 `nowMono/nowWall`；`nowMicros` 是 2.x 增量，不得用于墙钟 |
| `sleepContext` | 不属于 runtime；见 [`../time/README.md`](../time/README.md) 的 `sleepContext(Context, Duration)` | 取消返回 `Cancelled`；runtime 不重复暴露 sleep |

示例：

```xnull
RuntimeStats snapshot = stats()
statsSetEnabled(true)
statsReset()
dumpTasks()
Long startMicros = nowMicros()
```

测试义务：统计默认关闭/开关/reset；五个计数与 `live()`；`dumpTasks` 不改变任务状态；`nowMicros` 单调；`sleepContext` 在 time 包测试。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Copy`、`@Override` |
| 处理器 | 标准 A8 / 编译器内建 |
| 生成物 | 运行信息/健康快照的派生成员、协议签名校验 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `RuntimeInfo`/`MemoryStats`/`TaskStats`/`TaskSnapshot` | `@Value` | 值语义成员 |
| `HealthReport` | `@Value` | 快照相等/文本 |
| `HealthCheck` 实现 | `@Override` | 签名校验 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
