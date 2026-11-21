# `HostMetricsReceiver`

| 项 | 值 |
| --- | --- |
| 类型 | `class HostMetricsReceiver implements Receiver` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `Receiver`、`TelemetryKind`、`TelemetryBatch`、`TelemetryRecord`、`MetricFamily`、`MetricSample`、`MetricKind`、`OsHost`、`SystemInfo`、`Timer`、`Context`、`Error` |

---

## 1. 定位

主机指标接收器：按固定间隔 scrape 本机 CPU、内存、负载、文件系统、网络、分页、进程数与系统信息，
生成 Metrics 批次并推送给管线。

它面向节点 Agent / sidecar / 网关旁路，不采集应用内指标，不暴露 HTTP 端点。

不做：逐进程指标（X）、GPU/温度/硬件传感器（X）、容器编排指标、远程主机抓取、
Prometheus 抓取客户端、告警。

---

## 2. 设计逻辑

- 实现 `Receiver`；`kind()` 固定 Metrics；
- 每个采集周期生成一个 `TelemetryBatch`；资源属性来自构造器 `resource`，记录属性放样本标签；
- 每个指标族一个 `MetricFamily`；每个族至少一个 `MetricSample`；
- `scrapers` 是显式白名单；未知名称构造时拒绝；平台不支持时跳过该 scraper，不致命；
- 采集间隔/首次延迟显式；使用 `Timer` 周期调度；
- 下游 `Busy` 时按溢出策略处理：`reject` 跳过本次、`drop_oldest`/`drop_newest` 对单批次效果相同，
  都计为丢弃；主机指标是周期快照，丢一次可接受；
- 采集错误不使 Agent 崩溃：记录 `_lastError`、`_healthy=false`；下一次成功恢复；
- `stop` 取消定时器；`drain` 无内部队列，直接返回；`close` 关闭 Timer；
- `collectOnce` 公开用于测试/手动采集；未启动返回 `Unavailable`；
- 不拥有 `OsHost`；不关闭注入的宿主。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空、单行 |
| `_host` | `OsHost` | 非 null；不拥有 |
| `_collectionIntervalMillis` | `Long` | >0 |
| `_initialDelayMillis` | `Long` | ≥0 |
| `_scrapers` | `List<String>` | 非空；去重；合法名称 |
| `_resource` | `Map<String,String>` | 非 null；构造时复制 |
| `_overflowPolicy` | `String` | `reject`/`drop_oldest`/`drop_newest` |
| `_timer` | `Timer` | 非 null；接收器拥有 |
| `_timerHandle` | `Long` | ≥0；未调度为 0 |
| `_downstream` | `Result<Unit, Error>(TelemetryBatch)?` | start 后非 null |
| `_running` | `Bool` | start 后 true；stop 后 false |
| `_closed` | `Bool` | 只从 false 变 true |
| `_healthy` | `Bool` | 最近采集是否成功 |
| `_lastError` | `String` | 可为空；不含敏感信息 |
| `_lastSuccessMono` | `Long` | ≥0；0 表示尚未成功 |
| `_collectedBatches` | `Int` | ≥0 |
| `_droppedBatches` | `Int` | ≥0 |
| `_refusedBatches` | `Int` | ≥0 |

不变量：interval >0；initial ≥0；scrapers 非空且去重；resource 复制；timer 归接收器所有；
stop 后不再采集；close 后不再调度；错误不导致 panic。

---

## 4. 生命周期

```text
构造 → start（首次延迟 + 周期调度）→ collectOnce（周期/手动）→ stop → drain → close
```

- `start`：非阻塞；保存 downstream；调度首次采集与周期采集；重复 start 返回 `Ok(unit)`；
- `stop`：取消定时器；不丢弃已生成批次（无内部队列）；可重复；
- `drain`：无内部队列，返回 `Ok(unit)`；
- `close`：stop + `Timer.shutdown()`；幂等；关闭后 `collectOnce` 返回 `Unavailable`；
- 停止后仍可读取诊断计数/健康快照。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HostMetricsReceiver` | `String name, OsHost host, Long collectionIntervalMillis, Long initialDelayMillis, List<String> scrapers, Map<String,String> resource, String overflowPolicy` | name 非空；host 非 null；interval >0；initial ≥0；scrapers 非空且合法；policy 合法 | 非法 → panic |

合法 scraper：

`cpu`、`memory`、`load`、`filesystem`、`network`、`paging`、`processes`、`system`。

说明：

- `process`（逐进程）不在基线；需要时 X 增加独立接收器/处理器，避免权限与基数问题；
- `resource` 复制；建议至少包含 `host.name`、`service.name`；不强制补全；
- `overflowPolicy` 固定三种；大小写敏感，未知值 panic；
- `name` 默认由应用给出，例如 `"hostmetrics"`；同一 Agent 内唯一。

---

## 6. 字段表

见 §3；配置字段为 `final`；运行状态由接收器串行化。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 固定 Metrics | 无 | `TelemetryKind` | 无 |
| `name` | 接收器名 | 无 | `String` | 无 |
| `start` | 启动调度 | `Context context, Result<Unit, Error>(TelemetryBatch) downstream` | `Result<Unit, Error>` | `Unavailable`/`InvalidArgument`/`Cancelled` |
| `stop` | 停止调度 | `Context context` | `Result<Unit, Error>` | `Cancelled`/`Internal` |
| `drain` | 无队列 | `Context context` | `Result<Unit, Error>` | `Cancelled` |
| `close` | 关闭 Timer | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isRunning` | 是否运行 | 无 | `Bool` | 无 |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |
| `collectOnce` | 手动采集一次 | `Context context` | `Result<Unit, Error>` | `Unavailable`/`Cancelled`/`Unsupported`/`Internal` |
| `scrapers` | scraper 快照 | 无 | `List<String>` | 无 |
| `lastSuccessMono` | 最近成功时间 | 无 | `Long` | 无 |
| `collectedBatches` | 成功批次数 | 无 | `Int` | 无 |
| `droppedBatches` | 丢弃批次数 | 无 | `Int` | 无 |
| `refusedBatches` | 拒绝批次数 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `start` 对 null context/downstream → panic；已关闭 → `Unavailable`；重复 start → `Ok(unit)`；
- `start` 调度：`initialDelay` 后首次采集，之后每 `collectionIntervalMillis` 一次；
- `collectOnce` 对 null context → panic；未 start/已 close → `Unavailable`；
- `collectOnce` 至少一个 scraper 成功则返回 `Ok(unit)`，失败 scraper 记入 `_lastError`；
  全部失败返回第一个错误；`Unsupported` 不算失败，跳过；
- 下游 `Busy`：`reject` 增加 refused 计数并返回错误；`drop_oldest`/`drop_newest` 增加 dropped、
  提交本次采集并返回 `Ok(unit)`；不重试本周期；丢弃时健康降级；
- `stop` 对 null context → panic；未启动/已停止 → `Ok(unit)`；
- `drain` 对 null context → panic；无队列立即返回 `Ok(unit)`；
- `close` 幂等；已关闭返回 `Ok(unit)`；stop 后 close 不再调度；
- `isHealthy` 未启动/关闭为 false；最近采集成功为 true。

### 7.1 Scraper 与指标

| scraper | 指标名 | kind | 单位 | 来源 |
| --- | --- | --- | --- | --- |
| `cpu` | `system.cpu.utilization` | Gauge | `1` | `SystemInfo.cpuUsagePercent` |
| `cpu` | `system.cpu.logical.count` | Gauge | `{cpu}` | `CpuTopology.logicalCoreCount` |
| `memory` | `system.memory.usage` | Gauge | `By` | 总量 − 可用 |
| `memory` | `system.memory.available` | Gauge | `By` | `SystemInfo.memoryAvailable` |
| `memory` | `system.memory.total` | Gauge | `By` | `SystemInfo.memoryTotal` |
| `load` | `system.cpu.load_average.1m` | Gauge | `1` | 内部 `hostLoadAverageRaw` |
| `filesystem` | `system.filesystem.usage` | Gauge | `By` | 内部 `hostFilesystemUsageRaw` |
| `filesystem` | `system.filesystem.utilization` | Gauge | `1` | used / total |
| `network` | `system.network.io` | Counter | `By` | 内部 `hostNetworkCountersRaw` |
| `network` | `system.network.packets` | Counter | `{packet}` | 内部 `hostNetworkCountersRaw` |
| `paging` | `system.paging.usage` | Gauge | `By` | 内部 `hostPagingRaw` |
| `paging` | `system.paging.operations` | Counter | `{operation}` | 内部 `hostPagingRaw` |
| `processes` | `system.processes.count` | Gauge | `{process}` | 内部 `hostProcessCountRaw` |
| `system` | `system.uptime` | Gauge | `s` | `SystemInfo.uptimeMillis / 1000` |
| `system` | `system.cpu.logical.count` | Gauge | `{cpu}` | `CpuTopology.logicalCoreCount` |

说明：

- 指标名采用 OTel hostmetrics 语义命名；单位使用 UCUM 风格；
- 内部 `host*Raw` 是运行时/OS 适配器原语，不是公开类型；平台不支持时返回 `Unsupported`；
- 所有字节/计数用 `Long`；比例用 `Double`；核数/进程数用 `Int`/`Long`（样本值统一 `Double`，
  计数类指标在导出时按整数值处理）；
- 样本标签至少包含 `host.name`（若资源没有则由接收器补）；文件系统/网络/分页按设备/接口/
  挂载点分标签；不把序列号、MAC 写入标签；
- 采集失败不生成伪造 0 值；缺数据就不发该族。

---

## 8. 使用的技术

- 周期调度；
- 快照采集；
- 指标族/样本构造；
- 有界批次（单批）；
- 下游背压/显式丢弃；
- 健康快照；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、String、Long、Int、Double、Bool、List、Map、Result；
- 运行时：`Timer.after/every/cancel/shutdown`、`Context`、`nowMono`、`nowWall`、`hostname`；
- 接口：`OsHost`、`SystemInfo`、`CpuTopology`、`PhysicalMemory`、`StorageInventory`、
  `MetricFamily`、`MetricSample`、`MetricKind`、`TelemetryRecord`、`TelemetryBatch`；
- 内部原语：`hostLoadAverageRaw`、`hostFilesystemUsageRaw`、`hostNetworkCountersRaw`、
  `hostPagingRaw`、`hostProcessCountRaw`。

---

## 10. 依赖的特性/接口/类

`Receiver`、`TelemetryKind`、`TelemetryBatch`、`TelemetryRecord`、`MetricFamily`、`MetricSample`、
`MetricKind`、`SystemInfo`、`CpuTopology`、`PhysicalMemory`、`StorageInventory`、`OsHost`、
`Timer`、`Duration`、`Context`、`hostname`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- 接收器拥有 Timer 与自己的诊断状态；不拥有 `OsHost`、`SystemInfo` 快照、downstream；
- `start`/`stop`/`close` 串行化状态；`collectOnce` 可由调度器或测试并发调用，但实现应串行化采集；
- `downstream` 只在接收器任务中调用，串行化；
- `scrapers`/计数/健康可并发读取；
- 同一接收器不跨 Agent 共享；需要多份采集时创建多个实例（不同间隔/名称）。

---

## 12. 示例与反例

正确：

```xnull
HostMetricsReceiver receiver = new HostMetricsReceiver(
    "hostmetrics",
    Os.host(),
    60000,
    1000,
    ["cpu", "memory", "load", "filesystem", "network", "paging", "processes", "system"],
    ["service.name":"edge-agent", "host.name":hostname()],
    "reject"
)
```

反例：默认采集所有逐进程指标导致高基数；把 `Unsupported` 当致命错误；采集失败发 0 值；
在标签里写 MAC/序列号；用墙钟计算采集间隔；`stop` 后继续调度；多个 Agent 共享同一接收器。

---

## 13. 测试/场景义务

构造校验（interval/initial/scrapers/policy）；首次延迟/周期；每个 scraper 的指标名/kind/单位；
CPU 拓扑/内存/磁盘/网络/分页/进程数；平台不支持跳过；采集错误健康降级/恢复；
下游 Busy 的三种策略/计数；stop/start/close 顺序；重复 start/stop/close；collectOnce 未启动；
并发采集；资源属性复制；不泄露敏感标签；describe。

---

## 14. XNull 伪代码

```xnull
class HostMetricsReceiver implements Receiver {
    final String _name
    final OsHost _host
    final Long _collectionIntervalMillis
    final Long _initialDelayMillis
    final List<String> _scrapers
    final Map<String, String> _resource
    final String _overflowPolicy
    final Timer _timer
    Long _timerHandle = 0
    Result<Unit, Error>(TelemetryBatch)? _downstream
    Bool _running = false
    Bool _closed = false
    Bool _healthy = false
    String _lastError = ""
    Long _lastSuccessMono = 0
    Int _collectedBatches = 0
    Int _droppedBatches = 0
    Int _refusedBatches = 0
    final RuntimeMonitor _monitor

    HostMetricsReceiver(String name, OsHost host, Long collectionIntervalMillis,
                        Long initialDelayMillis, List<String> scrapers,
                        Map<String, String> resource, String overflowPolicy) {
        if name == null || name == "" {
            throw "HostMetricsReceiver: empty name"
        }
        if host == null { throw "HostMetricsReceiver: null host" }
        if collectionIntervalMillis <= 0 {
            throw "HostMetricsReceiver: interval <= 0"
        }
        if initialDelayMillis < 0 {
            throw "HostMetricsReceiver: negative initial delay"
        }
        if scrapers == null || scrapers.length() == 0 {
            throw "HostMetricsReceiver: no scraper"
        }
        if !self.validPolicy(overflowPolicy) {
            throw "HostMetricsReceiver: invalid overflow policy"
        }
        List<String> scraperCopy = []
        Int index = 0
        while index < scrapers.length() {
            String scraper = scrapers.get(index)
            if !self.validScraper(scraper) {
                throw "HostMetricsReceiver: unknown scraper"
            }
            if self.contains(scraperCopy, scraper) {
                throw "HostMetricsReceiver: duplicate scraper"
            }
            scraperCopy.push(scraper)
            index = index + 1
        }
        _name = name
        _host = host
        _collectionIntervalMillis = collectionIntervalMillis
        _initialDelayMillis = initialDelayMillis
        _scrapers = scraperCopy
        _resource = resource.copy()
        _overflowPolicy = overflowPolicy
        _timer = new Timer()
        _monitor = new RuntimeMonitor()
    }

    TelemetryKind kind() { return TelemetryKind.Metrics }
    String name() { return _name }

    Result<Unit, Error> start(Context context,
        Result<Unit, Error>(TelemetryBatch) downstream) {
        if context == null || downstream == null {
            throw "HostMetricsReceiver.start: null argument"
        }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "closed"))
        }
        if _running {
            _monitor.exit()
            return Ok(unit)
        }
        _downstream = downstream
        _running = true
        _monitor.exit()
        Result<Long, Error> first = _timer.after(context,
            Duration.ofMillis(_initialDelayMillis),
            () -> self.collectTick(context))
        if first.isErr() {
            _monitor.enter()
            _running = false
            _monitor.exit()
            return Err(first.error())
        }
        _monitor.enter()
        _timerHandle = first.value()
        Result<Long, Error> periodic = _timer.every(context,
            Duration.ofMillis(_collectionIntervalMillis),
            () -> self.collectTick(context))
        if periodic.isErr() {
            _timer.cancel(_timerHandle)
            _timerHandle = 0
            _running = false
            _monitor.exit()
            return Err(periodic.error())
        }
        _timerHandle = periodic.value()
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "HostMetricsReceiver.stop: null context" }
        _monitor.enter()
        if !_running {
            _monitor.exit()
            return Ok(unit)
        }
        _running = false
        if _timerHandle != 0 { _timer.cancel(_timerHandle) }
        _timerHandle = 0
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "HostMetricsReceiver.drain: null context" }
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Ok(unit)
        }
        _closed = true
        _running = false
        if _timerHandle != 0 { _timer.cancel(_timerHandle) }
        _timerHandle = 0
        _monitor.exit()
        _timer.shutdown()
        return Ok(unit)
    }

    Bool isRunning() { return _running }
    Bool isHealthy() { return _running && _healthy }
    List<String> scrapers() { return _scrapers.copy() }
    Long lastSuccessMono() { return _lastSuccessMono }
    Int collectedBatches() { return _collectedBatches }
    Int droppedBatches() { return _droppedBatches }
    Int refusedBatches() { return _refusedBatches }

    Result<Unit, Error> collectOnce(Context context) {
        if context == null {
            throw "HostMetricsReceiver.collectOnce: null context"
        }
        if !_running { return Err(new BasicError(ErrorKind.Unavailable,
            "not running")) }
        return self.collect(context)
    }

    void collectTick(Context context) {
        self.collectScheduled(context)
    }

    Result<Unit, Error> collectScheduled(Context context) {
        if !_running || context.isCancelled() { return Ok(unit) }
        Result<Unit, Error> result = self.collect(context)
        if result.isErr() {
            _monitor.enter()
            _healthy = false
            _lastError = result.error().describe()
            _monitor.exit()
        }
        return result
    }

    Result<Unit, Error> collect(Context context) {
        SystemInfo info = SystemInfo.snapshot()
        List<TelemetryRecord> records = []
        List<String> failures = []
        Bool anySuccess = false
        Int index = 0
        while index < _scrapers.length() {
            String scraper = _scrapers.get(index)
            if scraper == "cpu" {
                records.pushAll(self.scrapeCpu(context, info))
                anySuccess = true
            } else if scraper == "memory" {
                records.pushAll(self.scrapeMemory(info))
                anySuccess = true
            } else if scraper == "load" {
                records.pushAll(self.scrapeLoad())
                anySuccess = true
            } else if scraper == "filesystem" {
                records.pushAll(self.scrapeFilesystem())
                anySuccess = true
            } else if scraper == "network" {
                records.pushAll(self.scrapeNetwork())
                anySuccess = true
            } else if scraper == "paging" {
                records.pushAll(self.scrapePaging())
                anySuccess = true
            } else if scraper == "processes" {
                records.pushAll(self.scrapeProcesses())
                anySuccess = true
            } else {
                records.pushAll(self.scrapeSystem(info))
                anySuccess = true
            }
            index = index + 1
        }
        if !anySuccess {
            _monitor.enter()
            _healthy = false
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Internal, "no scraper produced"))
        }
        if _downstream == null {
            return Err(new BasicError(ErrorKind.Unavailable,
                "no downstream"))
        }
        TelemetryBatch batch = new TelemetryBatch(TelemetryKind.Metrics,
            _resource, records, 0, nowMono())
        Result<Unit, Error> delivered = _downstream(batch)
        _monitor.enter()
        if delivered.isErr() {
            _lastError = delivered.error().describe()
            if _overflowPolicy == "reject" {
                _refusedBatches = _refusedBatches + 1
                _healthy = false
                _monitor.exit()
                return delivered
            }
            _droppedBatches = _droppedBatches + 1
            _collectedBatches = _collectedBatches + 1
            _lastSuccessMono = nowMono()
            _healthy = false
            _monitor.exit()
            return Ok(unit)
        }
        _collectedBatches = _collectedBatches + 1
        _lastSuccessMono = nowMono()
        _healthy = true
        _monitor.exit()
        return Ok(unit)
    }

    List<TelemetryRecord> scrapeCpu(Context context, SystemInfo info) {
        List<TelemetryRecord> records = []
        Double ratio = info.cpuUsagePercent() / 100.0
        MetricSample sample = new MetricSample("system.cpu.utilization",
            ["host.name":self.hostLabel()], ratio, nowMono())
        MetricFamily family = new MetricFamily("system.cpu.utilization",
            MetricKind.Gauge, "CPU utilization", "1", [sample])
        records.push(TelemetryRecord.metric(family, nowMono(), nowWall()))
        Result<CpuTopology, Error> topology = _host.cpuTopology(context)
        if topology.isOk() {
            Double cores = topology.value().logicalCoreCount() as Double
            MetricSample coreSample = new MetricSample("system.cpu.logical.count",
                ["host.name":self.hostLabel()], cores, nowMono())
            MetricFamily coreFamily = new MetricFamily("system.cpu.logical.count",
                MetricKind.Gauge, "Logical CPU count", "{cpu}", [coreSample])
            records.push(TelemetryRecord.metric(coreFamily, nowMono(), nowWall()))
        }
        return records
    }

    List<TelemetryRecord> scrapeMemory(SystemInfo info) {
        List<TelemetryRecord> records = []
        Long used = info.memoryTotal() - info.memoryAvailable()
        if used < 0 { used = 0 }
        records.push(self.metric("system.memory.usage", MetricKind.Gauge,
            "Memory usage", "By", used as Double, ["host.name":self.hostLabel()]))
        records.push(self.metric("system.memory.available", MetricKind.Gauge,
            "Memory available", "By", info.memoryAvailable() as Double,
            ["host.name":self.hostLabel()]))
        records.push(self.metric("system.memory.total", MetricKind.Gauge,
            "Memory total", "By", info.memoryTotal() as Double,
            ["host.name":self.hostLabel()]))
        return records
    }

    List<TelemetryRecord> scrapeLoad() {
        Double load = hostLoadAverageRaw(1)
        return [self.metric("system.cpu.load_average.1m", MetricKind.Gauge,
            "1m load average", "1", load, ["host.name":self.hostLabel()])]
    }

    List<TelemetryRecord> scrapeFilesystem() {
        List<TelemetryRecord> records = []
        List<FilesystemUsage> usages = hostFilesystemUsageRaw()
        Int index = 0
        while index < usages.length() {
            FilesystemUsage usage = usages.get(index)
            records.push(self.metric("system.filesystem.usage",
                MetricKind.Gauge, "Filesystem usage", "By", usage.usedBytes() as Double,
                ["host.name":self.hostLabel(), "mount":usage.mountPoint()]))
            records.push(self.metric("system.filesystem.utilization",
                MetricKind.Gauge, "Filesystem utilization", "1", usage.ratio(),
                ["host.name":self.hostLabel(), "mount":usage.mountPoint()]))
            index = index + 1
        }
        return records
    }

    List<TelemetryRecord> scrapeNetwork() {
        List<TelemetryRecord> records = []
        List<NetworkCounters> counters = hostNetworkCountersRaw()
        Int index = 0
        while index < counters.length() {
            NetworkCounters counter = counters.get(index)
            records.push(self.metric("system.network.io", MetricKind.Counter,
                "Network bytes", "By", counter.bytes() as Double,
                ["host.name":self.hostLabel(),
                "interface":counter.interfaceName()]))
            records.push(self.metric("system.network.packets", MetricKind.Counter,
                "Network packets", "{packet}", counter.packets() as Double,
                ["host.name":self.hostLabel(),
                "interface":counter.interfaceName()]))
            index = index + 1
        }
        return records
    }

    List<TelemetryRecord> scrapePaging() {
        List<TelemetryRecord> records = []
        records.push(self.metric("system.paging.usage", MetricKind.Gauge,
            "Paging usage", "By", hostPagingUsageRaw() as Double,
            ["host.name":self.hostLabel()]))
        records.push(self.metric("system.paging.operations", MetricKind.Counter,
            "Paging operations", "{operation}", hostPagingOperationsRaw() as Double,
            ["host.name":self.hostLabel()]))
        return records
    }

    List<TelemetryRecord> scrapeProcesses() {
        return [self.metric("system.processes.count", MetricKind.Gauge,
            "Process count", "{process}", hostProcessCountRaw() as Double,
            ["host.name":self.hostLabel()])]
    }

    List<TelemetryRecord> scrapeSystem(SystemInfo info) {
        Double uptimeSeconds = info.uptimeMillis() / 1000.0
        return [
            self.metric("system.uptime", MetricKind.Gauge, "System uptime",
                "s", uptimeSeconds, ["host.name":self.hostLabel()])
        ]
    }

    TelemetryRecord metric(String name, MetricKind kind, String help,
                           String unitName, Double value,
                           Map<String, String> labels) {
        MetricSample sample = new MetricSample(name, labels, value, nowMono())
        MetricFamily family = new MetricFamily(name, kind, help,
            unitName, [sample])
        return TelemetryRecord.metric(family, nowMono(), nowWall())
    }

    String hostLabel() {
        return _resource.getOr("host.name", hostname())
    }

    Bool validScraper(String scraper) {
        return scraper == "cpu" || scraper == "memory" || scraper == "load"
            || scraper == "filesystem" || scraper == "network"
            || scraper == "paging" || scraper == "processes"
            || scraper == "system"
    }

    Bool validPolicy(String policy) {
        return policy == "reject" || policy == "drop_oldest"
            || policy == "drop_newest"
    }

    Bool contains(List<String> values, String value) {
        Int index = 0
        while index < values.length() {
            if values.get(index) == value { return true }
            index = index + 1
        }
        return false
    }

    String describe() {
        return "hostmetrics " + _name + " scrapers=" + str(_scrapers.length())
            + " interval=" + str(_collectionIntervalMillis) + "ms"
    }
}
```

> 伪代码中的 `FilesystemUsage`、`NetworkCounters` 与 `host*Raw` 是内部 OS 适配器类型/原语，
> 不属于 `xdk.agent` 公开类型；基线只暴露 `HostMetricsReceiver` 与指标记录。
