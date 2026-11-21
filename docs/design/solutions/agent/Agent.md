# `Agent`

| 项 | 值 |
| --- | --- |
| 类型 | `class Agent` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `AgentConfig`、`AgentPipeline`、`Connector`、`AgentHealth`、`HealthReport`、`Context`、`Error` |

---

## 1. 定位

Agent 运行时入口：拥有配置、管线与连接器，编排启动、停止、冲刷、关闭，并维护健康快照。

它是进程内/节点侧的“小型 Collector”：不解析配置、不注册全局组件、不接管应用生命周期。

不做：远程配置、组件热替换、全局单例、进程守护、信号处理、HTTP 管理端点。

---

## 2. 设计逻辑

- `Agent` 拥有 `AgentPipeline` 与 `Connector` 的运行时生命周期；管线拥有接收器/处理器/导出器；
- 构造时复制配置中的列表；不修改 `AgentConfig`；
- 启动顺序：先启动连接器（绑定目标管线 downstream），再按“目标管线先于源管线”的顺序启动管线；
  这样源管线开始推送时，目标管线已就绪；
- 管线启动顺序由连接器图的后序 DFS 得到；图无环由 `AgentConfig` 保证；
- 停止顺序：源管线先 `stop`（停止入口），按源到目标 drain，再 drain 连接器，再 drain 目标管线，
  最后 close 连接器与管线；
- `stop` 是优雅停机（stop → drain → close）；`close` 是立即中止（不 drain）；两者都幂等；
- `drain` 可在运行中调用，用于检查点/手动冲刷；并发 drain 返回 `Busy`；
- 状态转换用运行时监视器保护；调用组件时不持有监视器，避免组件回调 `consume` 造成不可重入死锁；
- 健康由 `AgentHealth` 维护；启动/停止/失败/丢弃都更新健康；
- 无全局 Agent；每个 Agent 独立；关闭后不可重启。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_config` | `AgentConfig` | 非 null；构造时复制列表 |
| `_pipelines` | `List<AgentPipeline>` | 非空；名称唯一 |
| `_connectors` | `List<Connector>` | 可为空；名称唯一 |
| `_health` | `AgentHealth` | 非 null；由 Agent 更新 |
| `_monitor` | `RuntimeMonitor` | 状态转换串行化 |
| `_context` | `Context?` | start 后内部子上下文 |
| `_starting` | `Bool` | 启动中 |
| `_started` | `Bool` | 已启动 |
| `_running` | `Bool` | 运行中 |
| `_stopping` | `Bool` | 停止中 |
| `_draining` | `Bool` | 防止并发 drain |
| `_closed` | `Bool` | 已关闭 |
| `_stopResult` | `Result<Unit, Error>?` | 优雅停机幂等结果 |
| `_closeResult` | `Result<Unit, Error>?` | 立即关闭幂等结果 |

不变量：管线/连接器非 null 且名称唯一；启动最多一次；`start` 成功后 `_running` 为 true；
`stop`/`close` 后不可重启；`stop`/`close` 幂等；关闭后 `start`/`drain` 返回 `Unavailable`。

---

## 4. 生命周期

```text
构造 → start → 运行 → stop（优雅：stop+drain+close）或 close（立即中止）
```

- 构造：复制配置列表；创建 `AgentHealth`；不启动组件；
- `start`：非阻塞；启动连接器与管线；失败回滚已启动组件；重复 start 返回 `Ok(unit)`；
- `stop`：优雅停机；重复调用返回第一次结果；关闭后不可重启；
- `drain`：运行中冲刷；不改变运行状态；取消返回 `Cancelled`；
- `close`：立即中止；不 drain；关闭组件与连接器；幂等；
- 关闭后 `start`/`drain` 返回 `Unavailable`；`isRunning` 为 false。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Agent` | `AgentConfig config` | 非 null；配置已通过校验 | null → panic；配置不一致 → panic |

说明：

- `Agent` 不重新解析配置；`AgentConfig.create` 已完成名称/连接图校验；
- 构造时复制 `pipelines()`/`connectors()`；调用方后续修改配置列表不影响 Agent；
- `AgentHealth` 名称使用 `"agent/" + instanceName`，避免多 Agent 注册冲突；
- 构造不启动组件；未 `start` 时 `isRunning` 为 false；
- 配置中的管线/连接器实例归 Agent 运行期所有；应用不应在 Agent 运行期间直接操作它们。

---

## 6. 字段表

见 §3；`_config`/`_pipelines`/`_connectors`/`_health`/`_monitor` 为 `final`；状态字段可变但只在监视器内转换。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `start` | 启动 Agent | `Context context` | `Result<Unit, Error>` | `Busy`/`Unavailable`/`Cancelled`/组件错误 |
| `stop` | 优雅停机 | `Context context` | `Result<Unit, Error>` | `Busy`/`Cancelled`/组件错误 |
| `drain` | 冲刷在途 | `Context context` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable`/组件错误 |
| `close` | 立即中止 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isRunning` | 是否运行 | 无 | `Bool` | 无 |
| `serviceName` | 服务名 | 无 | `String` | 无 |
| `instanceName` | 实例名 | 无 | `String` | 无 |
| `pipelines` | 管线快照 | 无 | `List<AgentPipeline>` | 无 |
| `connectors` | 连接器快照 | 无 | `List<Connector>` | 无 |
| `health` | 健康对象 | 无 | `AgentHealth` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `start` 对 null context → panic；已关闭 → `Unavailable`；启动中/已启动 → `Busy`/`Ok(unit)`；
- `start` 先启动连接器，再按目标优先顺序启动管线；失败时关闭已启动组件并置 `Unhealthy`；
- `stop` 对 null context → panic；未启动 → 标记 `Stopped` 并返回 `Ok(unit)`；
  启动中/停止中/排空中 → `Busy`；已停止/关闭 → 返回缓存结果；
- `stop` 顺序：源管线 stop → 源管线 drain → 连接器 drain → 目标管线 drain → 连接器 close → 管线 close；
- `drain` 对 null context → panic；未运行/关闭 → `Unavailable`；启动/停止/并发 drain → `Busy`；
- `drain` 顺序：源管线 drain → 连接器 drain → 目标管线 drain；运行中 drain 不停止接收器，
  新数据可能继续进入；需要零丢失时先停止源接收器；
- `close` 幂等；启动/停止/排空中 → `Busy`；不 drain；先置关闭标记/取消上下文，再关闭连接器与管线；
- `health()` 返回 Agent 持有的 `AgentHealth`；应用只读，不直接调用 `mark*`；
- `pipelines()`/`connectors()` 返回新列表；元素是运行时对象，不应在运行期被外部修改。

---

## 8. 使用的技术

- 对象图所有权；
- 后序 DFS 拓扑排序；
- 生命周期编排；
- 运行时监视器；
- 优雅停机/立即中止双路径；
- 健康状态机；
- 幂等结果缓存。

---

## 9. 需要的支撑

- 语言：class、List、Map、String、Bool、Result、Unit；
- 运行时：`RuntimeMonitor`、`Context.withCancel`、`nowMono`；
- 接口：`AgentConfig`、`AgentPipeline`、`Connector`、`AgentHealth`、`HealthReport`、`HealthState`、
  `Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`AgentConfig`、`AgentPipeline`、`Connector`、`AgentHealth`、`HealthReport`、`HealthState`、
`Context`、`RuntimeMonitor`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- Agent 拥有配置快照、管线、连接器、健康对象；
- 管线拥有接收器/处理器/导出器；连接器由 Agent 拥有；应用拥有注入的 OsHost/Writer 等；
- `start`/`stop`/`drain`/`close` 用监视器保护状态转换；调用组件时不持有监视器；
- 并发 `start`/`stop`/`drain` 在状态转换中返回 `Busy`；`start` 进行中调用 `close` 由实现拒绝或等待；
- `RuntimeMonitor` 不可重入；禁止在组件回调内再次进入同一 Agent 的 `start`/`stop`/`drain`；
- `isRunning`/`health`/列表快照可并发读取；
- 同一 Agent 不跨进程/任务共享；一个管线/连接器实例只属于一个 Agent。

---

## 12. 示例与反例

正确：

```xnull
Result<AgentConfig, Error> created = AgentConfig.create(
    "edge-agent", "node-01", [metricsPipeline, logsPipeline], [])
if created.isErr() { return created }
Agent agent = new Agent(created.value())
Result<Unit, Error> started = agent.start(context)
if started.isErr() { return started }
Result<Unit, Error> stopped = agent.stop(context)
if stopped.isErr() { diagnose(stopped.error().describe()) }
```

反例：把 Agent 当全局单例；start 失败不回滚；stop 不 drain 直接 close 却宣称零丢失；
close 后再次 start；多个 Agent 共享同一管线；在组件回调中调用 `agent.stop` 造成监视器重入；
把 `AgentHealth` 的 `mark*` 暴露给应用。

---

## 13. 测试/场景义务

构造复制/校验；start 顺序（目标管线先于源）；start 失败回滚；重复 start；stop 顺序与幂等；
stop 未启动；drain 运行中/未运行/并发；close 幂等/不 drain；连接器 start 一次/close 一次；
健康状态转换；启动/停止中并发；组件错误传播；列表快照；null 参数；关闭后行为。

---

## 14. XNull 伪代码

```xnull
class Agent {
    final AgentConfig _config
    final List<AgentPipeline> _pipelines
    final List<Connector> _connectors
    final AgentHealth _health
    final RuntimeMonitor _monitor
    Context? _context
    Bool _starting = false
    Bool _started = false
    Bool _running = false
    Bool _stopping = false
    Bool _draining = false
    Bool _closed = false
    Result<Unit, Error>? _stopResult
    Result<Unit, Error>? _closeResult

    Agent(AgentConfig config) {
        if config == null { throw "Agent: null config" }
        _config = config
        _pipelines = config.pipelines()
        _connectors = config.connectors()
        _health = new AgentHealth("agent/" + config.instanceName(),
            config.serviceName(), _pipelines.length())
        _monitor = new RuntimeMonitor()
    }

    Result<Unit, Error> start(Context context) {
        if context == null { throw "Agent.start: null context" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "agent closed"))
        }
        if _started {
            _monitor.exit()
            return Ok(unit)
        }
        if _starting || _stopping || _draining {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "agent transitioning"))
        }
        _starting = true
        _context = Context.withCancel(context)
        _health.markStarting()
        _monitor.exit()

        Int connectorIndex = 0
        while connectorIndex < _connectors.length() {
            Connector connector = _connectors.get(connectorIndex)
            AgentPipeline? destination = self.destinationFor(connector)
            if destination == null {
                self.failStart("connector destination missing")
                return Err(new BasicError(ErrorKind.Internal,
                    "connector destination missing"))
            }
            Result<Unit, Error> started = connector.start(_context,
                self.bindPipeline(_context, destination))
            if started.isErr() {
                self.closeConnectors(connectorIndex)
                self.failStart(started.error().describe())
                return started
            }
            connectorIndex = connectorIndex + 1
        }

        List<AgentPipeline> order = self.buildStartOrder()
        Int pipelineIndex = 0
        while pipelineIndex < order.length() {
            Result<Unit, Error> started = order.get(pipelineIndex).start(_context)
            if started.isErr() {
                self.closePipelines(order, pipelineIndex)
                self.closeConnectors(_connectors.length())
                self.failStart(started.error().describe())
                return started
            }
            _health.setPipelineReadiness(pipelineIndex + 1, _pipelines.length())
            pipelineIndex = pipelineIndex + 1
        }

        _monitor.enter()
        _starting = false
        _started = true
        _running = true
        _health.markRunning(_pipelines.length())
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "Agent.stop: null context" }
        _monitor.enter()
        if _closed || !_started {
            Result<Unit, Error>? cached = _stopResult
            _monitor.exit()
            if cached != null { return cached }
            _health.markStopped()
            return Ok(unit)
        }
        if _starting || _stopping || _draining {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "agent transitioning"))
        }
        _stopping = true
        _running = false
        _health.markStopping()
        _monitor.exit()

        Result<Unit, Error> first = Ok(unit)
        List<AgentPipeline> startOrder = self.buildStartOrder()
        List<AgentPipeline> stopOrder = self.reverse(startOrder)
        Int index = 0
        while index < stopOrder.length() {
            Result<Unit, Error> stopped = stopOrder.get(index).stop(context)
            if stopped.isErr() && first.isOk() { first = stopped }
            index = index + 1
        }
        index = 0
        while index < stopOrder.length() {
            Result<Unit, Error> drained = stopOrder.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < _connectors.length() {
            Result<Unit, Error> drained = _connectors.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < startOrder.length() {
            Result<Unit, Error> drained = startOrder.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < _connectors.length() {
            Result<Unit, Error> closed = _connectors.get(index).close()
            if closed.isErr() && first.isOk() { first = closed }
            index = index + 1
        }
        index = 0
        while index < startOrder.length() {
            Result<Unit, Error> closed = startOrder.get(index).close()
            if closed.isErr() && first.isOk() { first = closed }
            index = index + 1
        }
        _monitor.enter()
        _stopping = false
        _started = false
        _closed = true
        if _context != null { _context.cancel() }
        _stopResult = first
        _closeResult = first
        _health.markStopped()
        _monitor.exit()
        return first
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "Agent.drain: null context" }
        _monitor.enter()
        if _closed || !_running {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable,
                "agent not running"))
        }
        if _starting || _stopping || _draining {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "agent transitioning"))
        }
        _draining = true
        _monitor.exit()
        Result<Unit, Error> first = Ok(unit)
        List<AgentPipeline> startOrder = self.buildStartOrder()
        List<AgentPipeline> stopOrder = self.reverse(startOrder)
        Int index = 0
        while index < stopOrder.length() {
            Result<Unit, Error> drained = stopOrder.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < _connectors.length() {
            Result<Unit, Error> drained = _connectors.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        index = 0
        while index < startOrder.length() {
            Result<Unit, Error> drained = startOrder.get(index).drain(context)
            if drained.isErr() && first.isOk() { first = drained }
            index = index + 1
        }
        _monitor.enter()
        _draining = false
        _monitor.exit()
        return first
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _starting || _stopping || _draining {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "agent transitioning"))
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
        _stopping = false
        if _context != null { _context.cancel() }
        _monitor.exit()
        Result<Unit, Error> first = Ok(unit)
        Int connectorIndex = 0
        while connectorIndex < _connectors.length() {
            Result<Unit, Error> closed = _connectors.get(connectorIndex).close()
            if closed.isErr() && first.isOk() { first = closed }
            connectorIndex = connectorIndex + 1
        }
        List<AgentPipeline> order = self.buildStartOrder()
        Int pipelineIndex = 0
        while pipelineIndex < order.length() {
            Result<Unit, Error> closed = order.get(pipelineIndex).close()
            if closed.isErr() && first.isOk() { first = closed }
            pipelineIndex = pipelineIndex + 1
        }
        _monitor.enter()
        _closeResult = first
        _stopResult = first
        _health.markStopped()
        _monitor.exit()
        return first
    }

    Bool isRunning() { return _running }
    String serviceName() { return _config.serviceName() }
    String instanceName() { return _config.instanceName() }
    List<AgentPipeline> pipelines() { return _pipelines.copy() }
    List<Connector> connectors() { return _connectors.copy() }
    AgentHealth health() { return _health }

    List<AgentPipeline> buildStartOrder() {
        List<AgentPipeline> order = []
        List<String> visited = []
        Int index = 0
        while index < _pipelines.length() {
            self.visitStart(_pipelines.get(index), visited, order)
            index = index + 1
        }
        return order
    }

    void visitStart(AgentPipeline pipeline, List<String> visited,
                    List<AgentPipeline> order) {
        if self.contains(visited, pipeline.name()) { return }
        List<Connector> outputs = pipeline.outputConnectors()
        Int index = 0
        while index < outputs.length() {
            AgentPipeline? destination = self.destinationFor(outputs.get(index))
            if destination != null {
                self.visitStart(destination, visited, order)
            }
            index = index + 1
        }
        visited.push(pipeline.name())
        order.push(pipeline)
    }

    AgentPipeline? destinationFor(Connector connector) {
        Int index = 0
        while index < _pipelines.length() {
            AgentPipeline pipeline = _pipelines.get(index)
            if self.containsConnector(pipeline.inputConnectors(), connector) {
                return pipeline
            }
            index = index + 1
        }
        return null
    }

    Bool containsConnector(List<Connector> connectors, Connector connector) {
        Int index = 0
        while index < connectors.length() {
            if connectors.get(index) == connector { return true }
            index = index + 1
        }
        return false
    }

    Bool contains(List<String> names, String name) {
        Int index = 0
        while index < names.length() {
            if names.get(index) == name { return true }
            index = index + 1
        }
        return false
    }

    List<AgentPipeline> reverse(List<AgentPipeline> values) {
        List<AgentPipeline> result = []
        Int index = values.length() - 1
        while index >= 0 {
            result.push(values.get(index))
            index = index - 1
        }
        return result
    }

    Result<Unit, Error>(TelemetryBatch) bindPipeline(Context context,
                                                      AgentPipeline pipeline) {
        return (TelemetryBatch batch) -> pipeline.consume(context, batch)
    }

    void failStart(String message) {
        _monitor.enter()
        _starting = false
        _started = false
        _running = false
        if _context != null { _context.cancel() }
        _health.markFailed(message)
        _monitor.exit()
    }

    void closeConnectors(Int count) {
        Int index = 0
        while index < count {
            _connectors.get(index).close()
            index = index + 1
        }
    }

    void closePipelines(List<AgentPipeline> order, Int count) {
        Int index = count - 1
        while index >= 0 {
            order.get(index).close()
            index = index - 1
        }
    }

    String describe() {
        return "agent " + _config.serviceName() + "/" + _config.instanceName()
            + " pipelines=" + str(_pipelines.length())
            + " connectors=" + str(_connectors.length())
            + " running=" + str(_running)
    }
}
```
