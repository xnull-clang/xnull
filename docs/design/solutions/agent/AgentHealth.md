# `AgentHealth`

| 项 | 值 |
| --- | --- |
| 类型 | `class AgentHealth implements HealthCheck` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `HealthCheck`、`HealthReport`、`HealthState`、`RuntimeMonitor`、`Error` |

---

## 1. 定位

Agent 健康/就绪快照：状态、消息、管线就绪数、丢弃/失败计数、最近错误；实现 `xdk.runtime.HealthCheck`。

它供 `HealthRegistry`、探针、运维工具读取；不提供 HTTP 端点、告警、指标导出、自动重启。
组件级健康由 `AgentPipeline.health()` 提供；`AgentHealth` 记录 Agent 生命周期、就绪数与显式上报的
丢弃/失败，不代替逐组件诊断。

不做：HTTP 健康服务器、告警路由、进程守护、依赖注入、远程上报、历史趋势。

---

## 2. 设计逻辑

- 实现 `HealthCheck`：`name()` 稳定，`check()` 非阻塞返回 `HealthReport`；
- 状态机：`Starting` → `Healthy`/`Degraded`/`Unhealthy` → `Stopping` → `Stopped`；
- 就绪：`isReady()` 仅在可服务状态且 `readyPipelines == pipelineCount` 时为 true；
- 存活：`isLive()` 在未 `Stopped` 时为 true；`Unhealthy` 仍算存活（进程在，但不能服务）；
- 丢弃/失败计数单调递增；`Degraded` 表示仍可服务但存在丢弃/部分失败；
- `Unhealthy` 表示启动失败/关键错误/组件不可用；
- `check()` 返回快照，不修改状态；细节键值单行，错误描述截断，避免泄露 token/日志正文；
- 由 Agent 调用 `mark*`/`record*`；应用只读；mutator 公开是为了跨类调用，不构成稳定业务 API；
- 线程安全；可被多个探针并发读取。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空、单行、稳定 |
| `_serviceName` | `String` | 非空、单行 |
| `_pipelineCount` | `Int` | ≥0 |
| `_state` | `HealthState` | 初始 `Unhealthy` |
| `_message` | `String` | 单行；可为空 |
| `_startedMono` | `Long` | ≥0；首次启动时间 |
| `_updatedMono` | `Long` | ≥0；最近状态更新时间 |
| `_readyPipelines` | `Int` | 0..pipelineCount |
| `_droppedBatches` | `Int` | ≥0；单调递增 |
| `_failedOperations` | `Int` | ≥0；单调递增 |
| `_lastError` | `String` | 单行；可为空 |
| `_monitor` | `RuntimeMonitor` | 状态保护 |

不变量：name/serviceName 非空；pipelineCount ≥0；readyPipelines 在 [0, pipelineCount]；
计数不减少；状态转换只由 mutator 执行；`check()` 不阻塞；details 键/值单行；不可泄露敏感信息。

---

## 4. 生命周期

```text
构造（Unhealthy/not started）→ markStarting → markRunning → markStopping → markStopped
                              ↘ markFailed → markFailed/Unhealthy
```

- 构造后状态 `Unhealthy`，message `"not started"`；
- `markStarting`：首次记录 `_startedMono`，状态 `Starting`；
- `markRunning`：状态 `Healthy`，设置 ready 数；
- `setPipelineReadiness`：运行中按 ready 数切换 `Healthy`/`Degraded`；
- `recordDroppedBatches`/`recordFailure`：计数并可能降级；
- `markStopping`/`markStopped`：停止转换；不可回到 Healthy；
- 无 close；无资源；Agent 关闭后仍可读取最后快照。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AgentHealth` | `String name, String serviceName, Int pipelineCount` | name/serviceName 非空；pipelineCount ≥0 | 非法 → panic |

说明：

- `name` 建议 `"agent/" + instanceName`，避免多 Agent 注册冲突；
- `_state` 初始 `Unhealthy`，`_message` 为 `"not started"`；
- `_startedMono` 初始 0；`markStarting` 首次设置；
- `_readyPipelines` 初始 0；`_droppedBatches`/`_failedOperations` 初始 0；
- 不持有 Agent/管线引用，避免循环引用；Agent 负责调用 mutator。

---

## 6. 字段表

见 §3；`_name`/`_serviceName`/`_pipelineCount`/`_monitor` 为 `final`；状态/计数可变但由监视器保护。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 健康检查名 | 无 | `String` | 无 |
| `check` | 健康快照 | 无 | `HealthReport` | 无 |
| `isReady` | 是否就绪 | 无 | `Bool` | 无 |
| `isLive` | 是否存活 | 无 | `Bool` | 无 |
| `state` | 当前状态 | 无 | `HealthState` | 无 |
| `message` | 当前消息 | 无 | `String` | 无 |
| `pipelineCount` | 管线总数 | 无 | `Int` | 无 |
| `readyPipelines` | 就绪管线数 | 无 | `Int` | 无 |
| `droppedBatches` | 丢弃批次数 | 无 | `Int` | 无 |
| `failedOperations` | 失败操作数 | 无 | `Int` | 无 |
| `lastError` | 最近错误 | 无 | `String` | 无 |
| `startedMono` | 首次启动时间 | 无 | `Long` | 无 |
| `updatedMono` | 最近更新时间 | 无 | `Long` | 无 |
| `markStarting` | 进入启动 | 无 | `void` | 无 |
| `markRunning` | 进入运行 | `Int readyPipelines` | `void` | 越界 → panic |
| `markStopping` | 进入停止 | 无 | `void` | 无 |
| `markStopped` | 已停止 | 无 | `void` | 无 |
| `markFailed` | 启动/运行失败 | `String message` | `void` | null → panic |
| `setPipelineReadiness` | 更新就绪数 | `Int readyPipelines, Int totalPipelines` | `void` | 越界/不匹配 → panic |
| `recordDroppedBatches` | 记录丢弃 | `Int count` | `void` | 负值 → panic |
| `recordFailure` | 记录失败 | `Error error` | `void` | null → panic |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `check()` 复制状态后构造 `HealthReport`；details 包含 `service`、`pipelinesReady`、
  `pipelinesTotal`、`droppedBatches`、`failedOperations`、`lastError`；
- `check()` 不阻塞、不调用组件、不做 I/O；
- `isReady` = `healthStateIsReady(state)` 且 `readyPipelines == pipelineCount`；
- `isLive` = `state != HealthState.Stopped`；`Unhealthy` 仍为 true；
- `markStarting` 幂等；已 Stopped 后忽略；首次设置 `_startedMono`；
- `markRunning` 校验 0..pipelineCount；状态置 `Healthy`；`readyPipelines` 设为参数；
- `markFailed` 状态置 `Unhealthy`；`_failedOperations++`；`_lastError` 截断到 256 字符；
- `setPipelineReadiness` 要求 total == pipelineCount；ready 在 [0,total]；若当前
  `Starting/Stopping/Stopped` 只更新计数，不改变状态；运行中 ready < total → `Degraded`，
  ready == total → `Healthy`（除非当前 Unhealthy）；
- `recordDroppedBatches` 增加计数；count >0 且当前 Healthy → `Degraded`；
- `recordFailure` 增加失败数、设置 `_lastError`；当前 Healthy → `Degraded`；当前
  `Starting` → `Unhealthy`；
- `markStopping` 置 `Stopping`；`markStopped` 置 `Stopped` 并清空 ready；
- `describe` 不输出错误详情/token。

---

## 8. 使用的技术

- 健康状态机；
- 单调时间戳；
- 计数；
- 快照；
- 运行时监视器；
- `HealthCheck` 适配；
- 错误描述截断。

---

## 9. 需要的支撑

- 语言：class、String、Int、Long、Bool、Map；
- 运行时：`RuntimeMonitor`、`nowMono`、`healthStateIsReady`、`healthStateName`、`truncate`；
- 接口：`HealthCheck`、`HealthReport`、`HealthState`、`Error`。

---

## 10. 依赖的特性/接口/类

`HealthCheck`、`HealthReport`、`HealthState`、`healthStateIsReady`、`healthStateName`、
`RuntimeMonitor`、`Error`、`truncate`、`nowMono`。

---

## 11. 所有权与并发

- Agent 拥有 `AgentHealth`；应用只读；
- `check`/读数可并发；mutator 由监视器串行化；
- `check()` 不阻塞、不做 I/O；适合探针高频调用；
- 不持有 Agent/管线引用；无资源；无 close；
- 同一实例不跨 Agent 共享；一个 Agent 一个健康对象。

---

## 12. 示例与反例

正确：

```xnull
AgentHealth health = agent.health()
HealthReport report = health.check()
if !health.isReady() {
    diagnose(report.describe())
}
```

反例：在 `check()` 里做 HTTP/数据库调用；把 `Degraded` 当不可就绪；把 `Unhealthy` 当进程已死；
计数回退；把日志正文/token 放进 `lastError`；应用直接调用 `markRunning` 伪造状态。

---

## 13. 测试/场景义务

构造校验；初始状态；markStarting/Running/Stopping/Stopped；markFailed；ready 数边界；
setPipelineReadiness 合法/非法/total 不匹配；丢弃/失败计数；Healthy→Degraded；
Starting→Unhealthy；Stopped 不可回 Healthy；check details；isReady/isLive；并发 check/mutator；
describe 不泄露；错误截断。

---

## 14. XNull 伪代码

```xnull
class AgentHealth implements HealthCheck {
    final String _name
    final String _serviceName
    final Int _pipelineCount
    final RuntimeMonitor _monitor
    HealthState _state = HealthState.Unhealthy
    String _message = "not started"
    Long _startedMono = 0
    Long _updatedMono = 0
    Int _readyPipelines = 0
    Int _droppedBatches = 0
    Int _failedOperations = 0
    String _lastError = ""

    AgentHealth(String name, String serviceName, Int pipelineCount) {
        if name == null || name == "" {
            throw "AgentHealth: empty name"
        }
        if serviceName == null || serviceName == "" {
            throw "AgentHealth: empty service name"
        }
        if pipelineCount < 0 {
            throw "AgentHealth: negative pipeline count"
        }
        _name = name
        _serviceName = serviceName
        _pipelineCount = pipelineCount
        _monitor = new RuntimeMonitor()
    }

    String name() { return _name }

    HealthReport check() {
        _monitor.enter()
        HealthState state = _state
        String message = _message
        Long timestampMono = nowMono()
        Int ready = _readyPipelines
        Int dropped = _droppedBatches
        Int failed = _failedOperations
        String lastError = _lastError
        _monitor.exit()
        Map<String, String> details = [:]
        details.put("service", self.singleLine(_serviceName))
        details.put("pipelinesReady", str(ready))
        details.put("pipelinesTotal", str(_pipelineCount))
        details.put("droppedBatches", str(dropped))
        details.put("failedOperations", str(failed))
        details.put("lastError", self.singleLine(lastError))
        return new HealthReport(state, message, timestampMono, details)
    }

    Bool isReady() {
        _monitor.enter()
        HealthState state = _state
        Int ready = _readyPipelines
        _monitor.exit()
        return healthStateIsReady(state) && ready == _pipelineCount
    }

    Bool isLive() {
        _monitor.enter()
        HealthState state = _state
        _monitor.exit()
        return state != HealthState.Stopped
    }

    HealthState state() { return _state }
    String message() { return _message }
    Int pipelineCount() { return _pipelineCount }
    Int readyPipelines() { return _readyPipelines }
    Int droppedBatches() { return _droppedBatches }
    Int failedOperations() { return _failedOperations }
    String lastError() { return _lastError }
    Long startedMono() { return _startedMono }
    Long updatedMono() { return _updatedMono }

    void markStarting() {
        _monitor.enter()
        if _state == HealthState.Stopped {
            _monitor.exit()
            return
        }
        if _startedMono == 0 { _startedMono = nowMono() }
        _state = HealthState.Starting
        _message = "starting"
        _updatedMono = nowMono()
        _monitor.exit()
    }

    void markRunning(Int readyPipelines) {
        if readyPipelines < 0 || readyPipelines > _pipelineCount {
            throw "AgentHealth.markRunning: invalid ready count"
        }
        _monitor.enter()
        if _state == HealthState.Stopped {
            _monitor.exit()
            return
        }
        _state = HealthState.Healthy
        _readyPipelines = readyPipelines
        _message = "running"
        _updatedMono = nowMono()
        _monitor.exit()
    }

    void markStopping() {
        _monitor.enter()
        if _state == HealthState.Stopped {
            _monitor.exit()
            return
        }
        _state = HealthState.Stopping
        _message = "stopping"
        _updatedMono = nowMono()
        _monitor.exit()
    }

    void markStopped() {
        _monitor.enter()
        _state = HealthState.Stopped
        _readyPipelines = 0
        _message = "stopped"
        _updatedMono = nowMono()
        _monitor.exit()
    }

    void markFailed(String message) {
        if message == null { throw "AgentHealth.markFailed: null message" }
        _monitor.enter()
        _state = HealthState.Unhealthy
        _message = self.singleLine(truncate(message, 256))
        _failedOperations = _failedOperations + 1
        _lastError = self.singleLine(truncate(message, 256))
        _updatedMono = nowMono()
        _monitor.exit()
    }

    void setPipelineReadiness(Int readyPipelines, Int totalPipelines) {
        if totalPipelines != _pipelineCount {
            throw "AgentHealth.setPipelineReadiness: total mismatch"
        }
        if readyPipelines < 0 || readyPipelines > totalPipelines {
            throw "AgentHealth.setPipelineReadiness: invalid ready count"
        }
        _monitor.enter()
        _readyPipelines = readyPipelines
        if _state == HealthState.Healthy || _state == HealthState.Degraded {
            if readyPipelines < totalPipelines {
                _state = HealthState.Degraded
                _message = "pipeline degraded"
            } else {
                _state = HealthState.Healthy
                _message = "running"
            }
        }
        _updatedMono = nowMono()
        _monitor.exit()
    }

    void recordDroppedBatches(Int count) {
        if count < 0 { throw "AgentHealth.recordDroppedBatches: negative" }
        _monitor.enter()
        _droppedBatches = _droppedBatches + count
        if count > 0 && _state == HealthState.Healthy {
            _state = HealthState.Degraded
            _message = "dropping data"
        }
        _updatedMono = nowMono()
        _monitor.exit()
    }

    void recordFailure(Error error) {
        if error == null { throw "AgentHealth.recordFailure: null error" }
        _monitor.enter()
        _failedOperations = _failedOperations + 1
        _lastError = self.singleLine(truncate(error.describe(), 256))
        if _state == HealthState.Healthy {
            _state = HealthState.Degraded
            _message = "operation failed"
        } else if _state == HealthState.Starting {
            _state = HealthState.Unhealthy
            _message = "start failed"
        }
        _updatedMono = nowMono()
        _monitor.exit()
    }

    String singleLine(String text) {
        String result = text
        result = result.replaceAll("\n", " ")
        result = result.replaceAll("\t", " ")
        return result
    }

    String describe() {
        return "agent " + _name + " " + healthStateName(_state)
            + " ready=" + str(_readyPipelines) + "/" + str(_pipelineCount)
            + " dropped=" + str(_droppedBatches)
            + " failed=" + str(_failedOperations)
    }
}
```
