# `AgentConfig`

| 项 | 值 |
| --- | --- |
| 类型 | `class AgentConfig` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `AgentPipeline`、`Connector`、`Error`、`Result` |

---

## 1. 定位

Agent 的显式配置对象图：服务名、实例名、管线列表、连接器列表，以及跨管线连接图校验。

`AgentConfig` 是**已构造好的组件图**，不是 YAML/JSON 文本；默认不从文件、环境、网络或配置中心读取。

不做：配置解析、远程拉取、热更新、组件工厂注册、密钥管理、默认组件注入。

---

## 2. 设计逻辑

- 配置即对象图：应用先构造 `AgentPipeline` 与 `Connector`，再交给 `AgentConfig`；
- 列表构造时复制；读取返回副本；`with*` 返回新配置，不修改原配置；
- 语义校验集中在 `create`：名称非空/唯一、管线非空、连接器唯一入/出、kind 匹配、无环；
- 构造器私有；`create`/`of` 返回 `Result`，把可恢复的配置错误交给调用方；
- `withPipeline`/`withConnector` 复用 `create` 重新校验，失败返回 `InvalidArgument`；
- 不提供默认管线/默认导出器；没有“只配置不启用”的隐式行为：列表内的组件就是启用；
- 不持有运行时资源；不 close；可复制/共享给 Agent 构造。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_serviceName` | `String` | 非空、单行 |
| `_instanceName` | `String` | 非空、单行；同一服务内唯一 |
| `_pipelines` | `List<AgentPipeline>` | 非空；名称唯一；元素非 null |
| `_connectors` | `List<Connector>` | 名称唯一；元素非 null；每个恰好一次输入/输出接入 |

不变量：管线名称唯一；连接器名称唯一；每个连接器恰好接入一条源管线和一条目标管线；
连接器 kind 与接入管线 kind 匹配；连接图无环；列表为私有快照；对象不可变。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务只读共享；`Agent` 构造时复制其列表。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 私有构造器 | `String serviceName, String instanceName, List<AgentPipeline> pipelines, List<Connector> connectors` | 非 null；名称非空 | 非法 → panic |
| `create` | 同上 | 名称非空/唯一；管线非空；连接器图合法 | 语义非法 → `InvalidArgument` |
| `of` | `String serviceName, List<AgentPipeline> pipelines` | serviceName 非空；管线非空 | 语义非法 → `InvalidArgument` |

说明：

- `of` 使用 `serviceName` 作为 `instanceName`，连接器列表为空；适用于无连接器的单实例 Agent；
- `create` 先做 null/空串 panic，再做语义校验；语义错误不 panic，返回 `Err`；
- 语义错误包括：重复管线名、重复连接器名、连接器未接入/接入多次、接入管线 kind 不匹配、
  连接图成环、`_connectors` 中存在未接入的实例、管线引用了未列入 `_connectors` 的连接器；
- 连接器接入信息来自管线列表：`inputConnectors()` 与 `outputConnectors()`；
- 配置不解析文本；应用负责把外部配置映射为对象图。

---

## 6. 字段表

见 §3；字段私有且 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `create` | 构造并校验 | `String serviceName, String instanceName, List<AgentPipeline> pipelines, List<Connector> connectors` | `Result<AgentConfig, Error>` | `InvalidArgument` |
| `of` | 单实例便捷构造 | `String serviceName, List<AgentPipeline> pipelines` | `Result<AgentConfig, Error>` | `InvalidArgument` |
| `withPipeline` | 派生并追加管线 | `AgentPipeline pipeline` | `Result<AgentConfig, Error>` | null → panic；语义非法 → `InvalidArgument` |
| `withConnector` | 派生并追加连接器 | `Connector connector` | `Result<AgentConfig, Error>` | null → panic；语义非法 → `InvalidArgument` |
| `serviceName` | 服务名 | 无 | `String` | 无 |
| `instanceName` | 实例名 | 无 | `String` | 无 |
| `pipelines` | 管线快照 | 无 | `List<AgentPipeline>` | 无 |
| `connectors` | 连接器快照 | 无 | `List<Connector>` | 无 |
| `pipeline` | 按名称查找管线 | `String name` | `AgentPipeline?` | null → panic |
| `connector` | 按名称查找连接器 | `String name` | `Connector?` | null → panic |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `create` 对 null 列表/名称 → panic；语义错误 → `InvalidArgument`；
- `withPipeline`/`withConnector` 复制当前列表并追加，然后调用 `create` 重新校验；
- `pipelines()`/`connectors()` 返回新列表；元素本身是运行时对象，仍可被 Agent 使用；
- `pipeline`/`connector` 按名称精确匹配；未找到返回 null；
- `describe` 只用于诊断，不输出连接器配置或敏感信息。

---

## 8. 使用的技术

- 不可变配置对象；
- 防御性复制；
- 名称唯一性校验；
- 连接器图唯一入/出校验；
- 环检测；
- Result 配置错误。

---

## 9. 需要的支撑

- 语言：class、List、Map、String、Bool、Result；
- 运行时：无（纯校验）；
- 接口：`AgentPipeline`、`Connector`、`TelemetryKind`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`AgentPipeline`、`Connector`、`TelemetryKind`、`Error`、`BasicError`、`ErrorKind`、`Result`、`Unit`。

---

## 11. 所有权与并发

- 配置不可变；可跨任务只读共享；
- 配置不拥有管线/连接器的运行时资源；`Agent` 构造时复制列表并取得运行所有权；
- `with*` 不修改原配置；新旧配置可共存；
- `pipeline`/`connector` 查找无锁；列表快照隔离；
- 无 close；无取消点。

---

## 12. 示例与反例

正确：

```xnull
Result<AgentConfig, Error> created = AgentConfig.create(
    "edge-agent",
    "node-01",
    [metricsPipeline, logsPipeline],
    []
)
if created.isErr() { return created }
Agent agent = new Agent(created.value())
```

反例：从 YAML 直接反射成组件实例；一个连接器接入两条源管线；连接器列表与管线引用不一致；
重复管线名；把 `AgentConfig` 当全局单例；在配置中放 token 明文并 `describe` 输出。

---

## 13. 测试/场景义务

空/重复名称；空管线列表；连接器唯一入/出；连接器未接入/多次接入；kind 不匹配；环检测；
`of` 默认实例名；`withPipeline`/`withConnector` 重新校验；列表副本；查找命中/未命中；
`describe` 不泄露敏感信息；并发读取。

---

## 14. XNull 伪代码

```xnull
class AgentConfig {
    final String _serviceName
    final String _instanceName
    final List<AgentPipeline> _pipelines
    final List<Connector> _connectors

    private AgentConfig(String serviceName, String instanceName,
                        List<AgentPipeline> pipelines,
                        List<Connector> connectors) {
        if serviceName == null || serviceName == "" {
            throw "AgentConfig: empty service name"
        }
        if instanceName == null || instanceName == "" {
            throw "AgentConfig: empty instance name"
        }
        if pipelines == null || connectors == null {
            throw "AgentConfig: null list"
        }
        _serviceName = serviceName
        _instanceName = instanceName
        _pipelines = pipelines.copy()
        _connectors = connectors.copy()
    }

    static Result<AgentConfig, Error> create(String serviceName,
                                             String instanceName,
                                             List<AgentPipeline> pipelines,
                                             List<Connector> connectors) {
        AgentConfig config = new AgentConfig(serviceName, instanceName,
            pipelines, connectors)
        Result<Unit, Error> valid = config.validate()
        if valid.isErr() { return Err(valid.error()) }
        return Ok(config)
    }

    static Result<AgentConfig, Error> of(String serviceName,
                                         List<AgentPipeline> pipelines) {
        return AgentConfig.create(serviceName, serviceName, pipelines, [])
    }

    Result<AgentConfig, Error> withPipeline(AgentPipeline pipeline) {
        if pipeline == null { throw "AgentConfig.withPipeline: null" }
        List<AgentPipeline> next = _pipelines.copy()
        next.push(pipeline)
        return AgentConfig.create(_serviceName, _instanceName, next, _connectors)
    }

    Result<AgentConfig, Error> withConnector(Connector connector) {
        if connector == null { throw "AgentConfig.withConnector: null" }
        List<Connector> next = _connectors.copy()
        next.push(connector)
        return AgentConfig.create(_serviceName, _instanceName, _pipelines, next)
    }

    String serviceName() { return _serviceName }
    String instanceName() { return _instanceName }
    List<AgentPipeline> pipelines() { return _pipelines.copy() }
    List<Connector> connectors() { return _connectors.copy() }

    AgentPipeline? pipeline(String name) {
        if name == null { throw "AgentConfig.pipeline: null name" }
        Int index = 0
        while index < _pipelines.length() {
            AgentPipeline candidate = _pipelines.get(index)
            if candidate.name() == name { return candidate }
            index = index + 1
        }
        return null
    }

    Connector? connector(String name) {
        if name == null { throw "AgentConfig.connector: null name" }
        Int index = 0
        while index < _connectors.length() {
            Connector candidate = _connectors.get(index)
            if candidate.name() == name { return candidate }
            index = index + 1
        }
        return null
    }

    Result<Unit, Error> validate() {
        if _pipelines.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "AgentConfig: no pipeline"))
        }
        List<String> pipelineNames = []
        Int pipelineIndex = 0
        while pipelineIndex < _pipelines.length() {
            String name = _pipelines.get(pipelineIndex).name()
            if self.contains(pipelineNames, name) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "AgentConfig: duplicate pipeline " + name))
            }
            pipelineNames.push(name)
            pipelineIndex = pipelineIndex + 1
        }
        List<String> connectorNames = []
        Int connectorIndex = 0
        while connectorIndex < _connectors.length() {
            String name = _connectors.get(connectorIndex).name()
            if self.contains(connectorNames, name) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "AgentConfig: duplicate connector " + name))
            }
            connectorNames.push(name)
            connectorIndex = connectorIndex + 1
        }
        Int index = 0
        while index < _connectors.length() {
            Connector connector = _connectors.get(index)
            Int inputCount = 0
            Int outputCount = 0
            Int scan = 0
            while scan < _pipelines.length() {
                AgentPipeline pipeline = _pipelines.get(scan)
                if self.containsConnector(pipeline.inputConnectors(), connector) {
                    inputCount = inputCount + 1
                    if connector.outputKind() != pipeline.kind() {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "AgentConfig: connector output kind mismatch"))
                    }
                }
                if self.containsConnector(pipeline.outputConnectors(), connector) {
                    outputCount = outputCount + 1
                    if connector.inputKind() != pipeline.kind() {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "AgentConfig: connector input kind mismatch"))
                    }
                }
                scan = scan + 1
            }
            if inputCount != 1 || outputCount != 1 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "AgentConfig: connector attachment count"))
            }
            index = index + 1
        }
        Int pipelineScan = 0
        while pipelineScan < _pipelines.length() {
            AgentPipeline pipeline = _pipelines.get(pipelineScan)
            List<Connector> inputConnectors = pipeline.inputConnectors()
            List<Connector> outputConnectors = pipeline.outputConnectors()
            Int inputIndex = 0
            while inputIndex < inputConnectors.length() {
                if !self.containsConnector(_connectors,
                    inputConnectors.get(inputIndex)) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "AgentConfig: input connector not listed"))
                }
                inputIndex = inputIndex + 1
            }
            Int outputIndex = 0
            while outputIndex < outputConnectors.length() {
                if !self.containsConnector(_connectors,
                    outputConnectors.get(outputIndex)) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "AgentConfig: output connector not listed"))
                }
                outputIndex = outputIndex + 1
            }
            pipelineScan = pipelineScan + 1
        }
        if self.hasCycle() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "AgentConfig: connector cycle"))
        }
        return Ok(unit)
    }

    Bool contains(List<String> names, String name) {
        Int index = 0
        while index < names.length() {
            if names.get(index) == name { return true }
            index = index + 1
        }
        return false
    }

    Bool containsConnector(List<Connector> connectors, Connector connector) {
        Int index = 0
        while index < connectors.length() {
            if connectors.get(index) == connector { return true }
            index = index + 1
        }
        return false
    }

    Bool hasCycle() {
        List<String> visited = []
        List<String> stack = []
        Int index = 0
        while index < _pipelines.length() {
            if self.visit(_pipelines.get(index), visited, stack) {
                return true
            }
            index = index + 1
        }
        return false
    }

    Bool visit(AgentPipeline pipeline, List<String> visited,
               List<String> stack) {
        if self.contains(stack, pipeline.name()) { return true }
        if self.contains(visited, pipeline.name()) { return false }
        stack.push(pipeline.name())
        List<Connector> outputs = pipeline.outputConnectors()
        Int index = 0
        while index < outputs.length() {
            Connector connector = outputs.get(index)
            Int scan = 0
            while scan < _pipelines.length() {
                AgentPipeline destination = _pipelines.get(scan)
                if self.containsConnector(destination.inputConnectors(), connector) {
                    if self.visit(destination, visited, stack) { return true }
                }
                scan = scan + 1
            }
            index = index + 1
        }
        stack.pop()
        visited.push(pipeline.name())
        return false
    }

    String describe() {
        return "agent " + _serviceName + "/" + _instanceName
            + " pipelines=" + str(_pipelines.length())
            + " connectors=" + str(_connectors.length())
    }
}
```
