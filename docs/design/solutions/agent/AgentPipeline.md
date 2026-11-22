# `AgentPipeline`

| 项 | 值 |
| --- | --- |
| 类型 | `class AgentPipeline` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `Receiver`、`Processor`、`PipelineExporter`、`Connector`、`TelemetryKind`、`TelemetryBatch`、`HealthReport`、`HealthState`、`Context`、`Error` |

---

## 1. 定位

一条遥测管线的装配与运行：同 kind 的接收器 → 处理器链 → 导出器 fan-out，并可挂接输入/输出连接器。

管线负责：组件启动顺序、处理器链、fan-out、生命周期、健康聚合。它不负责：配置解析、
组件选择、连接器生命周期、全局注册。

不做：跨 kind 混合、采样、远程配置、组件热替换、持久化队列。

---

## 2. 设计逻辑

- 管线 kind 固定；接收器/处理器/导出器必须同 kind；输入连接器输出 kind、输出连接器输入 kind
  必须匹配；
- 构造时复制组件列表并校验非空、kind、重名；至少一个源（接收器或输入连接器）和一个汇
  （导出器或输出连接器）；
- 启动顺序：导出器 → 处理器（从后往前）→ 接收器；保证下游先就绪；
- 处理器链：最后一个处理器的 downstream 是管线 fan-out；前一个处理器的 downstream 调用后一个
  处理器的 `process`；没有处理器时直接 fan-out；
- fan-out：依次调用每个导出器与输出连接器；每个收到同一不可变批次；尝试全部，返回第一个错误；
- `consume` 是管线入口，供接收器与输入连接器使用；用运行时监视器串行化，保证处理器顺序；
- 输入连接器由 Agent 启动，downstream 指向 `consume`；管线不启动/关闭连接器；
- `stop` 只停止接收器入口；`drain` 依次冲刷接收器、处理器、导出器；`close` 关闭组件；
- 健康取组件最严重状态；未启动为 `Starting`，停止后 `Stopped`，组件不健康为 `Unhealthy`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空、单行、Agent 内唯一 |
| `_kind` | `TelemetryKind` | 非 null |
| `_receivers` | `List<Receiver>` | 构造时复制；元素非 null；kind 一致 |
| `_processors` | `List<Processor>` | 构造时复制；元素非 null；kind 一致 |
| `_exporters` | `List<PipelineExporter>` | 构造时复制；元素非 null；kind 一致 |
| `_inputConnectors` | `List<Connector>` | 输出 kind 与管线一致 |
| `_outputConnectors` | `List<Connector>` | 输入 kind 与管线一致 |
| `_monitor` | `RuntimeMonitor` | 串行化 consume/生命周期 |
| `_context` | `Context?` | start 后为内部子上下文 |
| `_starting` | `Bool` | 启动中；并发 start 返回 `Busy` |
| `_failed` | `Bool` | 启动失败；健康为 `Unhealthy` |
| `_started` | `Bool` | 只从 false 变 true |
| `_running` | `Bool` | start 后 true；stop 后 false |
| `_draining` | `Bool` | 防止并发 drain |
| `_closed` | `Bool` | 只从 false 变 true |
| `_closeResult` | `Result<Unit, Error>?` | 幂等关闭结果 |

不变量：列表非 null；至少一个源和一个汇；kind 一致；start 最多一次；close 幂等；
`consume` 只在 running 时交付；关闭后不再调用组件。

---

## 4. 生命周期

```text
构造 → start → consume（多次）→ stop → drain → close
```

- `start`：启动导出器、处理器、接收器；失败回滚已启动组件；重复 start 返回 `Ok(unit)`；
- `stop`：停止接收器；不停止连接器（Agent 拥有）；重复 stop 返回 `Ok(unit)`；
- `drain`：接收器 → 处理器 → 导出器；可在 stop 前/后调用；取消返回 `Cancelled`；
- `close`：关闭接收器/处理器/导出器；不关闭连接器；幂等；未 drain 数据由组件计数丢弃；
- 关闭后 `start`/`consume`/`drain` 返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AgentPipeline` | `String name, TelemetryKind kind, List<Receiver> receivers, List<Processor> processors, List<PipelineExporter> exporters, List<Connector> inputConnectors, List<Connector> outputConnectors` | name 非空；kind 非 null；列表非 null；至少一个源/汇；kind 匹配；元素非 null | 非法 → panic |

说明：

- 组件名由应用保证可诊断；`AgentConfig` 只校验管线名与连接器名唯一，不重写组件名；
- 接收器、处理器、导出器 kind 必须等于管线 kind；
- 输入连接器的 `outputKind()` 必须等于管线 kind；输出连接器的 `inputKind()` 必须等于管线 kind；
- 连接器不得同时在输入/输出列表重复出现；Agent 负责跨管线唯一性与无环校验；
- 列表复制；调用方后续修改不影响管线；
- 不允许 null 元素。

---

## 6. 字段表

见 §3；`_name`/`_kind`/组件列表/`_monitor` 为 `final`；状态字段可变但只在监视器内转换。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 管线名 | 无 | `String` | 无 |
| `kind` | 遥测种类 | 无 | `TelemetryKind` | 无 |
| `receiverCount` | 接收器数 | 无 | `Int` | 无 |
| `processorCount` | 处理器数 | 无 | `Int` | 无 |
| `exporterCount` | 导出器数 | 无 | `Int` | 无 |
| `inputConnectorCount` | 输入连接器数 | 无 | `Int` | 无 |
| `outputConnectorCount` | 输出连接器数 | 无 | `Int` | 无 |
| `isRunning` | 是否运行 | 无 | `Bool` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `receivers` | 接收器快照 | 无 | `List<Receiver>` | 无 |
| `processors` | 处理器快照 | 无 | `List<Processor>` | 无 |
| `exporters` | 导出器快照 | 无 | `List<PipelineExporter>` | 无 |
| `inputConnectors` | 输入连接器快照 | 无 | `List<Connector>` | 无 |
| `outputConnectors` | 输出连接器快照 | 无 | `List<Connector>` | 无 |
| `start` | 启动管线 | `Context context` | `Result<Unit, Error>` | `Busy`/`Unavailable`/`Cancelled`/组件错误 |
| `stop` | 停止接收器 | `Context context` | `Result<Unit, Error>` | `Busy`/`Cancelled`/组件错误 |
| `drain` | 冲刷管线 | `Context context` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable`/组件错误 |
| `close` | 关闭管线 | 无 | `Result<Unit, Error>` | `Busy`/`Io`（诊断） |
| `consume` | 管线入口 | `Context context, TelemetryBatch batch` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable`/组件错误 |
| `health` | 健康快照 | 无 | `HealthReport` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `start` 对 null context → panic；已关闭 → `Unavailable`；重复 start → `Ok(unit)`；启动中 → `Busy`；
- `start` 先 `exporter.start`，再 `processor.start`（从后往前），最后 `receiver.start`；
  任一步失败则关闭已启动组件并返回错误；
- `start` 只在状态检查/提交时持有监视器，启动组件时不持有，避免接收器同步回调 `consume` 死锁；
- `stop` 对 null context → panic；启动中/排空中 → `Busy`；未启动/已停止 → `Ok(unit)`；不 drain、不关闭；
- `drain` 对 null context → panic；启动中 → `Busy`；关闭后 → `Unavailable`；并发 drain → `Busy`；
  顺序：接收器 → 处理器 → 导出器；drain 组件时不持有监视器；运行中 drain 不停止接收器，
  需要零丢失时先 `stop`；
- `close` 幂等；启动中/排空中 → `Busy`；已关闭返回第一次结果；不关闭连接器；先置关闭标记并取消内部上下文，再关闭组件；
- `consume` 对 null context/batch → panic；kind 不匹配 → panic；未启动/已关闭 → `Unavailable`；
  `stop` 后未 `close` 仍接受连接器/drain 数据；用 `_monitor` 串行化；无处理器时直接 fan-out；
- fan-out 尝试全部导出器/输出连接器；返回第一个错误；已成功接收的导出器可能在下游重试时收到重复；
- `health` 聚合组件 `isHealthy()`；任一 false 为 `Unhealthy`；未运行/停止为 `Starting`/`Stopped`。

---

## 8. 使用的技术

- 组件链装配；
- 函数类型 downstream；
- fan-out；
- 有界/背压由组件承担；
- 运行时监视器；
- 幂等生命周期；
- 健康聚合。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Result、Unit、函数类型；
- 运行时：`RuntimeMonitor`、`Context.withCancel`、`nowMono`；
- 接口：`Receiver`、`Processor`、`PipelineExporter`、`Connector`、`TelemetryKind`、`TelemetryBatch`、
  `HealthReport`、`HealthState`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Receiver`、`Processor`、`PipelineExporter`、`Connector`、`TelemetryKind`、`TelemetryBatch`、
`Context`、`RuntimeMonitor`、`HealthReport`、`HealthState`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- 管线拥有接收器/处理器/导出器；不拥有连接器、downstream、注入依赖；
- `consume` 用监视器串行化；并发接收器会排队/阻塞，形成背压；
- `start`/`stop`/`drain`/`close` 只用监视器保护状态转换；调用可能回调 `consume` 的组件时不持有监视器；
- 并发 `start` 返回 `Busy`；并发 `drain` 返回 `Busy`；`start` 进行中调用 `close` 由实现拒绝或等待，
  不保证同一时刻完成两段生命周期；
- `RuntimeMonitor` 不可重入；禁止在组件调用内再次进入同一管线的 `consume`（接收器应只调用下游）；
- 组件调用期间不持有监视器之外的其他锁；组件内部自行同步；
- `isRunning`/`isClosed`/计数/列表快照可并发读取；
- 同一管线不跨 Agent 共享；同一组件实例不跨管线共享。

---

## 12. 示例与反例

正确：

```xnull
AgentPipeline pipeline = new AgentPipeline(
    "metrics",
    TelemetryKind.Metrics,
    [hostReceiver],
    [memoryLimiter, batchProcessor],
    [otlpExporter],
    [],
    []
)
Result<Unit, Error> started = pipeline.start(context)
if started.isErr() { return started }
```

反例：把 traces 接收器放进 metrics 管线；启动顺序反过来（接收器先于导出器）；fan-out 只尝试
第一个导出器；`consume` 并发无串行化导致处理器乱序；管线 close 连接器；start 失败不回滚。

---

## 13. 测试/场景义务

构造校验（kind/空列表/重名/源汇）；start 顺序；start 失败回滚；stop 幂等；drain 顺序；
close 幂等；consume 运行/停止/关闭；kind 不匹配；无处理器 fan-out；多导出器部分失败；
输出连接器调用；health 聚合；并发 consume；列表快照；null 参数。

---

## 14. XNull 伪代码

```xnull
class AgentPipeline {
    final String _name
    final TelemetryKind _kind
    final List<Receiver> _receivers
    final List<Processor> _processors
    final List<PipelineExporter> _exporters
    final List<Connector> _inputConnectors
    final List<Connector> _outputConnectors
    final RuntimeMonitor _monitor
    Context? _context
    Bool _starting = false
    Bool _failed = false
    Bool _started = false
    Bool _running = false
    Bool _draining = false
    Bool _closed = false
    Result<Unit, Error>? _closeResult

    AgentPipeline(String name, TelemetryKind kind, List<Receiver> receivers,
                  List<Processor> processors, List<PipelineExporter> exporters,
                  List<Connector> inputConnectors,
                  List<Connector> outputConnectors) {
        if name == null || name == "" {
            throw "AgentPipeline: empty name"
        }
        if kind == null { throw "AgentPipeline: null kind" }
        if receivers == null || processors == null || exporters == null
            || inputConnectors == null || outputConnectors == null {
            throw "AgentPipeline: null component list"
        }
        if receivers.length() + inputConnectors.length() == 0 {
            throw "AgentPipeline: no source"
        }
        if exporters.length() + outputConnectors.length() == 0 {
            throw "AgentPipeline: no sink"
        }
        Int receiverIndex = 0
        while receiverIndex < receivers.length() {
            Receiver receiver = receivers.get(receiverIndex)
            if receiver == null { throw "AgentPipeline: null receiver" }
            if receiver.kind() != kind {
                throw "AgentPipeline: receiver kind mismatch"
            }
            receiverIndex = receiverIndex + 1
        }
        Int processorIndex = 0
        while processorIndex < processors.length() {
            Processor processor = processors.get(processorIndex)
            if processor == null { throw "AgentPipeline: null processor" }
            if processor.kind() != kind {
                throw "AgentPipeline: processor kind mismatch"
            }
            processorIndex = processorIndex + 1
        }
        Int exporterIndex = 0
        while exporterIndex < exporters.length() {
            PipelineExporter exporter = exporters.get(exporterIndex)
            if exporter == null { throw "AgentPipeline: null exporter" }
            if exporter.kind() != kind {
                throw "AgentPipeline: exporter kind mismatch"
            }
            exporterIndex = exporterIndex + 1
        }
        Int inputIndex = 0
        while inputIndex < inputConnectors.length() {
            Connector connector = inputConnectors.get(inputIndex)
            if connector == null { throw "AgentPipeline: null input connector" }
            if connector.outputKind() != kind {
                throw "AgentPipeline: input connector kind mismatch"
            }
            inputIndex = inputIndex + 1
        }
        Int outputIndex = 0
        while outputIndex < outputConnectors.length() {
            Connector connector = outputConnectors.get(outputIndex)
            if connector == null { throw "AgentPipeline: null output connector" }
            if connector.inputKind() != kind {
                throw "AgentPipeline: output connector kind mismatch"
            }
            outputIndex = outputIndex + 1
        }
        _name = name
        _kind = kind
        _receivers = receivers.copy()
        _processors = processors.copy()
        _exporters = exporters.copy()
        _inputConnectors = inputConnectors.copy()
        _outputConnectors = outputConnectors.copy()
        _monitor = new RuntimeMonitor()
    }

    String name() { return _name }
    TelemetryKind kind() { return _kind }
    Int receiverCount() { return _receivers.length() }
    Int processorCount() { return _processors.length() }
    Int exporterCount() { return _exporters.length() }
    Int inputConnectorCount() { return _inputConnectors.length() }
    Int outputConnectorCount() { return _outputConnectors.length() }
    Bool isRunning() { return _running }
    Bool isClosed() { return _closed }
    List<Receiver> receivers() { return _receivers.copy() }
    List<Processor> processors() { return _processors.copy() }
    List<PipelineExporter> exporters() { return _exporters.copy() }
    List<Connector> inputConnectors() { return _inputConnectors.copy() }
    List<Connector> outputConnectors() { return _outputConnectors.copy() }

    Result<Unit, Error> start(Context context) {
        if context == null { throw "AgentPipeline.start: null context" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "pipeline closed"))
        }
        if _started {
            _monitor.exit()
            return Ok(unit)
        }
        if _starting {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "pipeline starting"))
        }
        _starting = true
        _failed = false
        _context = Context.withCancel(context)
        _monitor.exit()
        Int exporterIndex = 0
        while exporterIndex < _exporters.length() {
            Result<Unit, Error> started =
                _exporters.get(exporterIndex).start(_context)
            if started.isErr() {
                self.closeStarted(exporterIndex)
                _monitor.enter()
                _starting = false
                _failed = true
                if _context != null { _context.cancel() }
                _monitor.exit()
                return started
            }
            exporterIndex = exporterIndex + 1
        }
        Result<Unit, Error>(TelemetryBatch) downstream =
            self.bindDelivery(_context)
        Int processorIndex = _processors.length() - 1
        Int startedProcessors = 0
        while processorIndex >= 0 {
            Processor processor = _processors.get(processorIndex)
            Result<Unit, Error> started = processor.start(_context, downstream)
            if started.isErr() {
                self.closeStartedProcessors(startedProcessors)
                self.closeStarted(_exporters.length())
                _monitor.enter()
                _starting = false
                _failed = true
                if _context != null { _context.cancel() }
                _monitor.exit()
                return started
            }
            downstream = self.bindProcessor(_context, processor)
            startedProcessors = startedProcessors + 1
            processorIndex = processorIndex - 1
        }
        Int receiverIndex = 0
        while receiverIndex < _receivers.length() {
            Result<Unit, Error> started = _receivers.get(receiverIndex).start(
                _context, self.bindConsume(_context))
            if started.isErr() {
                self.closeStartedReceivers(receiverIndex)
                self.closeStartedProcessors(_processors.length())
                self.closeStarted(_exporters.length())
                _monitor.enter()
                _starting = false
                _failed = true
                if _context != null { _context.cancel() }
                _monitor.exit()
                return started
            }
            receiverIndex = receiverIndex + 1
        }
        _monitor.enter()
        _starting = false
        _started = true
        _running = true
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "AgentPipeline.stop: null context" }
        _monitor.enter()
        if _starting || _draining {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "pipeline transitioning"))
        }
        if _closed || !_running {
            _monitor.exit()
            return Ok(unit)
        }
        _running = false
        _monitor.exit()
        Result<Unit, Error> first = Ok(unit)
        Int index = 0
        while index < _receivers.length() {
            Result<Unit, Error> stopped = _receivers.get(index).stop(context)
            if stopped.isErr() && first.isOk() { first = stopped }
            index = index + 1
        }
        return first
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "AgentPipeline.drain: null context" }
        _monitor.enter()
        if _starting {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "pipeline starting"))
        }
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "pipeline closed"))
        }
        if _draining {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "pipeline draining"))
        }
        _draining = true
        _monitor.exit()
        Result<Unit, Error> first = Ok(unit)
        Int receiverIndex = 0
        while receiverIndex < _receivers.length() {
            Result<Unit, Error> drained =
                _receivers.get(receiverIndex).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            receiverIndex = receiverIndex + 1
        }
        Int processorIndex = 0
        while processorIndex < _processors.length() {
            Result<Unit, Error> drained =
                _processors.get(processorIndex).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            processorIndex = processorIndex + 1
        }
        Int exporterIndex = 0
        while exporterIndex < _exporters.length() {
            Result<Unit, Error> drained =
                _exporters.get(exporterIndex).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            exporterIndex = exporterIndex + 1
        }
        _monitor.enter()
        _draining = false
        _monitor.exit()
        return first
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _starting || _draining {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "pipeline transitioning"))
        }
        if _closed {
            Result<Unit, Error>? cached = _closeResult
            _monitor.exit()
            if cached == null { return Ok(unit) }
            return cached
        }
        _closed = true
        _running = false
        _starting = false
        if _context != null { _context.cancel() }
        _monitor.exit()
        Result<Unit, Error> first = Ok(unit)
        Int receiverIndex = 0
        while receiverIndex < _receivers.length() {
            Result<Unit, Error> closed = _receivers.get(receiverIndex).close()
            if closed.isErr() && first.isOk() { first = closed }
            receiverIndex = receiverIndex + 1
        }
        Int processorIndex = 0
        while processorIndex < _processors.length() {
            Result<Unit, Error> closed = _processors.get(processorIndex).close()
            if closed.isErr() && first.isOk() { first = closed }
            processorIndex = processorIndex + 1
        }
        Int exporterIndex = 0
        while exporterIndex < _exporters.length() {
            Result<Unit, Error> closed = _exporters.get(exporterIndex).close()
            if closed.isErr() && first.isOk() { first = closed }
            exporterIndex = exporterIndex + 1
        }
        _monitor.enter()
        _closeResult = first
        _monitor.exit()
        return first
    }

    Result<Unit, Error> consume(Context context, TelemetryBatch batch) {
        if context == null { throw "AgentPipeline.consume: null context" }
        if batch == null { throw "AgentPipeline.consume: null batch" }
        if batch.kind() != _kind {
            throw "AgentPipeline.consume: batch kind mismatch"
        }
        _monitor.enter()
        if _closed || !_started {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable,
                "pipeline not started"))
        }
        Result<Unit, Error> result = Ok(unit)
        if _processors.length() == 0 {
            result = self.deliver(context, batch)
        } else {
            result = _processors.get(0).process(context, batch)
        }
        _monitor.exit()
        return result
    }

    Result<Unit, Error> deliver(Context context, TelemetryBatch batch) {
        Result<Unit, Error> first = Ok(unit)
        Int exporterIndex = 0
        while exporterIndex < _exporters.length() {
            Result<Unit, Error> exported =
                _exporters.get(exporterIndex).export(context, batch)
            if exported.isErr() && first.isOk() { first = exported }
            exporterIndex = exporterIndex + 1
        }
        Int connectorIndex = 0
        while connectorIndex < _outputConnectors.length() {
            Result<Unit, Error> consumed =
                _outputConnectors.get(connectorIndex).consume(context, batch)
            if consumed.isErr() && first.isOk() { first = consumed }
            connectorIndex = connectorIndex + 1
        }
        return first
    }

    Result<Unit, Error>(TelemetryBatch) bindProcessor(Context context,
                                                       Processor processor) {
        return (TelemetryBatch batch) -> processor.process(context, batch)
    }

    Result<Unit, Error>(TelemetryBatch) bindDelivery(Context context) {
        return (TelemetryBatch batch) -> self.deliver(context, batch)
    }

    Result<Unit, Error>(TelemetryBatch) bindConsume(Context context) {
        return (TelemetryBatch batch) -> self.consume(context, batch)
    }

    void closeStarted(Int count) {
        Int index = 0
        while index < count {
            _exporters.get(index).close()
            index = index + 1
        }
    }

    void closeStartedProcessors(Int count) {
        Int index = _processors.length() - count
        while index < _processors.length() {
            _processors.get(index).close()
            index = index + 1
        }
    }

    void closeStartedReceivers(Int count) {
        Int index = 0
        while index < count {
            _receivers.get(index).close()
            index = index + 1
        }
    }

    HealthReport health() {
        if _closed {
            return HealthReport.of(HealthState.Stopped, "pipeline closed")
        }
        if _failed {
            return HealthReport.of(HealthState.Unhealthy, "pipeline start failed")
        }
        if !_running {
            if _started {
                return HealthReport.of(HealthState.Stopped, "pipeline stopped")
            }
            return HealthReport.of(HealthState.Starting, "pipeline not running")
        }
        Bool healthy = true
        Int index = 0
        while index < _receivers.length() {
            if !_receivers.get(index).isHealthy() { healthy = false }
            index = index + 1
        }
        index = 0
        while index < _processors.length() {
            if !_processors.get(index).isHealthy() { healthy = false }
            index = index + 1
        }
        index = 0
        while index < _exporters.length() {
            if !_exporters.get(index).isHealthy() { healthy = false }
            index = index + 1
        }
        if !healthy {
            return HealthReport.of(HealthState.Unhealthy, "component unhealthy")
        }
        return HealthReport.of(HealthState.Healthy, "pipeline running")
    }

    String describe() {
        return _name + " " + telemetryKindName(_kind)
            + " receivers=" + str(_receivers.length())
            + " processors=" + str(_processors.length())
            + " exporters=" + str(_exporters.length())
    }
}
```
