# `McpCapability`

| 项 | 值 |
| --- | --- |
| 类型 | `enum McpCapability` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `JsonObject`、`JsonValue`、`Set`、`Error` |

---

## 1. 定位

MCP 能力标识：服务端能力（tools/resources/prompts/logging/completions/tasks）与客户端能力（sampling/roots/elicitation/tasks），含子能力（listChanged/subscribe/tools/form/url）。

不做：能力实现、权限判定、扩展 schema、按请求动态能力计算。

---

## 2. 设计逻辑

- 顶层能力与子能力使用同一个枚举，便于 `Set<McpCapability>` 表达完整能力集合。
- 每个子能力有唯一父能力；`mcpCapabilityParent` 用于“声明子能力即隐含父能力”的推导。
- 方向固定：客户端能力不能被服务端声明，反之亦然；`Tasks`、`Extensions`、`Experimental` 双向。
- 能力 JSON 的生成/解析集中在本文件，避免 `McpServerInfo`/`McpClientInfo` 各写一套。
- 未知顶层能力键在解析时忽略，保持向前兼容；未知子键也忽略，但值必须是 Object。
- 空 `{}` 的 `elicitation` 等价于 form 模式；解析时补 `ElicitationForm`。
- 成员只允许追加；名称映射稳定。

---

## 3. 表示与不变量

| 成员 | 父能力 | 方向 | JSON 位置 |
| --- | --- | --- | --- |
| `Tools` | 自身 | 服务端 | `tools` |
| `ToolsListChanged` | `Tools` | 服务端 | `tools.listChanged` |
| `Resources` | 自身 | 服务端 | `resources` |
| `ResourcesListChanged` | `Resources` | 服务端 | `resources.listChanged` |
| `ResourcesSubscribe` | `Resources` | 服务端 | `resources.subscribe` |
| `Prompts` | 自身 | 服务端 | `prompts` |
| `PromptsListChanged` | `Prompts` | 服务端 | `prompts.listChanged` |
| `Logging` | 自身 | 服务端 | `logging` |
| `Completions` | 自身 | 服务端 | `completions` |
| `Tasks` | 自身 | 双向 | `tasks` |
| `Sampling` | 自身 | 客户端 | `sampling` |
| `SamplingTools` | `Sampling` | 客户端 | `sampling.tools` |
| `Roots` | 自身 | 客户端 | `roots` |
| `Elicitation` | 自身 | 客户端 | `elicitation` |
| `ElicitationForm` | `Elicitation` | 客户端 | `elicitation.form` |
| `ElicitationUrl` | `Elicitation` | 客户端 | `elicitation.url` |
| `Extensions` | 自身 | 双向 | `extensions` |
| `Experimental` | 自身 | 双向 | `experimental` |

不变量：父能力存在；方向分类互斥（`Tasks`/`Extensions`/`Experimental` 除外，二者都 true）；名称唯一；JSON 生成对同一集合稳定。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享；无资源；无取消点。

---

## 5. 构造契约

枚举项直接使用；集合通过 `Set<McpCapability>` 构造。`mcpCapabilitiesJson` 接受空集，生成空对象。

---

## 6. 字段表

无实例字段；成员表见 §3。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `mcpCapabilityName` | 稳定诊断名 | `McpCapability capability` | `String` | null → panic |
| `mcpCapabilityParent` | 父能力 | `McpCapability capability` | `McpCapability` | null → panic |
| `parseMcpCapability` | 名称解析 | `String text` | `Result<McpCapability, Error>` | `InvalidArgument` |
| `isClientMcpCapability` | 是否客户端能力 | `McpCapability capability` | `Bool` | null → panic |
| `isServerMcpCapability` | 是否服务端能力 | `McpCapability capability` | `Bool` | null → panic |
| `mcpCapabilitiesJson` | 能力集合转 JSON | `Set<McpCapability> capabilities` | `JsonObject` | null → panic |
| `parseMcpCapabilities` | JSON 转能力集合 | `JsonObject capabilities` | `Result<Set<McpCapability>, Error>` | `InvalidArgument` |

说明：

- `mcpCapabilityName` 使用点分层：`"tools"`、`"tools.listChanged"`、`"elicitation.url"`；仅用于诊断/配置，不作为 JSON 键。
- `parseMcpCapability` 只接受稳定名；未知名称 `InvalidArgument`。
- `mcpCapabilitiesJson` 为每个父能力生成一个 Object；无子能力时为空对象；不输出未声明的父能力。
- `parseMcpCapabilities` 只读取已知顶层键；非 Object 的能力值 → `InvalidArgument`；`elicitation:{}` 补 `ElicitationForm`。
- 能力集合不保证顺序；JSON 对象键顺序不影响语义。

---

## 8. 使用的技术

- 简单枚举；
- 父子映射；
- 集合；
- JSON 对象构建/解析。

---

## 9. 需要的支撑

- 语言：enum、String、Bool、Set、Result；
- 运行时：无；
- 接口：`JsonObject`、`JsonValue`、`Set`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`JsonObject`、`JsonValue`、`Set`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

值语义；`mcpCapabilitiesJson` 返回新对象；`parseMcpCapabilities` 返回新集合；无资源；可共享；无锁。

---

## 12. 示例与反例

正确：`mcpCapabilitiesJson({Tools, ToolsListChanged, Elicitation, ElicitationForm})`。  
反例：服务端声明 `Sampling`；只声明 `ToolsListChanged` 而不推导 `Tools`；把 `elicitation:{}` 解析成无能力；把未知能力键当错误。

---

## 13. 测试/场景义务

18 个成员名称往返；父子映射；方向分类；空集合 JSON；每个子能力 JSON；`elicitation:{}`；未知顶层键忽略；非对象能力值拒绝；`set` 去重；能力集合往返。

---

## 14. XNull 伪代码

```xnull
enum McpCapability {
    Tools,
    ToolsListChanged,
    Resources,
    ResourcesListChanged,
    ResourcesSubscribe,
    Prompts,
    PromptsListChanged,
    Logging,
    Completions,
    Tasks,
    Sampling,
    SamplingTools,
    Roots,
    Elicitation,
    ElicitationForm,
    ElicitationUrl,
    Extensions,
    Experimental,
}

String mcpCapabilityName(McpCapability capability) {
    if capability == null { throw "mcpCapabilityName: null" }
    if capability == McpCapability.Tools { return "tools" }
    if capability == McpCapability.ToolsListChanged { return "tools.listChanged" }
    if capability == McpCapability.Resources { return "resources" }
    if capability == McpCapability.ResourcesListChanged { return "resources.listChanged" }
    if capability == McpCapability.ResourcesSubscribe { return "resources.subscribe" }
    if capability == McpCapability.Prompts { return "prompts" }
    if capability == McpCapability.PromptsListChanged { return "prompts.listChanged" }
    if capability == McpCapability.Logging { return "logging" }
    if capability == McpCapability.Completions { return "completions" }
    if capability == McpCapability.Tasks { return "tasks" }
    if capability == McpCapability.Sampling { return "sampling" }
    if capability == McpCapability.SamplingTools { return "sampling.tools" }
    if capability == McpCapability.Roots { return "roots" }
    if capability == McpCapability.Elicitation { return "elicitation" }
    if capability == McpCapability.ElicitationForm { return "elicitation.form" }
    if capability == McpCapability.ElicitationUrl { return "elicitation.url" }
    if capability == McpCapability.Extensions { return "extensions" }
    return "experimental"
}

McpCapability mcpCapabilityParent(McpCapability capability) {
    if capability == null { throw "mcpCapabilityParent: null" }
    if capability == McpCapability.ToolsListChanged { return McpCapability.Tools }
    if capability == McpCapability.ResourcesListChanged { return McpCapability.Resources }
    if capability == McpCapability.ResourcesSubscribe { return McpCapability.Resources }
    if capability == McpCapability.PromptsListChanged { return McpCapability.Prompts }
    if capability == McpCapability.SamplingTools { return McpCapability.Sampling }
    if capability == McpCapability.ElicitationForm { return McpCapability.Elicitation }
    if capability == McpCapability.ElicitationUrl { return McpCapability.Elicitation }
    return capability
}

Result<McpCapability, Error> parseMcpCapability(String text) {
    if text == null { throw "parseMcpCapability: null" }
    if text == "tools" { return Ok(McpCapability.Tools) }
    if text == "tools.listChanged" { return Ok(McpCapability.ToolsListChanged) }
    if text == "resources" { return Ok(McpCapability.Resources) }
    if text == "resources.listChanged" { return Ok(McpCapability.ResourcesListChanged) }
    if text == "resources.subscribe" { return Ok(McpCapability.ResourcesSubscribe) }
    if text == "prompts" { return Ok(McpCapability.Prompts) }
    if text == "prompts.listChanged" { return Ok(McpCapability.PromptsListChanged) }
    if text == "logging" { return Ok(McpCapability.Logging) }
    if text == "completions" { return Ok(McpCapability.Completions) }
    if text == "tasks" { return Ok(McpCapability.Tasks) }
    if text == "sampling" { return Ok(McpCapability.Sampling) }
    if text == "sampling.tools" { return Ok(McpCapability.SamplingTools) }
    if text == "roots" { return Ok(McpCapability.Roots) }
    if text == "elicitation" { return Ok(McpCapability.Elicitation) }
    if text == "elicitation.form" { return Ok(McpCapability.ElicitationForm) }
    if text == "elicitation.url" { return Ok(McpCapability.ElicitationUrl) }
    if text == "extensions" { return Ok(McpCapability.Extensions) }
    if text == "experimental" { return Ok(McpCapability.Experimental) }
    return Err(new BasicError(ErrorKind.InvalidArgument,
        "unknown MCP capability: " + text))
}

Bool isClientMcpCapability(McpCapability capability) {
    if capability == null { throw "isClientMcpCapability: null" }
    if capability == McpCapability.Sampling { return true }
    if capability == McpCapability.SamplingTools { return true }
    if capability == McpCapability.Roots { return true }
    if capability == McpCapability.Elicitation { return true }
    if capability == McpCapability.ElicitationForm { return true }
    if capability == McpCapability.ElicitationUrl { return true }
    if capability == McpCapability.Tasks { return true }
    if capability == McpCapability.Extensions { return true }
    if capability == McpCapability.Experimental { return true }
    return false
}

Bool isServerMcpCapability(McpCapability capability) {
    if capability == null { throw "isServerMcpCapability: null" }
    if capability == McpCapability.Tools { return true }
    if capability == McpCapability.ToolsListChanged { return true }
    if capability == McpCapability.Resources { return true }
    if capability == McpCapability.ResourcesListChanged { return true }
    if capability == McpCapability.ResourcesSubscribe { return true }
    if capability == McpCapability.Prompts { return true }
    if capability == McpCapability.PromptsListChanged { return true }
    if capability == McpCapability.Logging { return true }
    if capability == McpCapability.Completions { return true }
    if capability == McpCapability.Tasks { return true }
    if capability == McpCapability.Extensions { return true }
    if capability == McpCapability.Experimental { return true }
    return false
}

JsonObject mcpCapabilitiesJson(Set<McpCapability> capabilities) {
    if capabilities == null { throw "mcpCapabilitiesJson: null" }
    JsonObject result = new JsonObject()
    if capabilities.has(McpCapability.Tools)
        || capabilities.has(McpCapability.ToolsListChanged) {
        JsonObject tools = new JsonObject()
        if capabilities.has(McpCapability.ToolsListChanged) {
            tools.set("listChanged", JsonValue.bool(true))
        }
        result.set("tools", JsonValue.object(tools))
    }
    if capabilities.has(McpCapability.Resources)
        || capabilities.has(McpCapability.ResourcesListChanged)
        || capabilities.has(McpCapability.ResourcesSubscribe) {
        JsonObject resources = new JsonObject()
        if capabilities.has(McpCapability.ResourcesListChanged) {
            resources.set("listChanged", JsonValue.bool(true))
        }
        if capabilities.has(McpCapability.ResourcesSubscribe) {
            resources.set("subscribe", JsonValue.bool(true))
        }
        result.set("resources", JsonValue.object(resources))
    }
    if capabilities.has(McpCapability.Prompts)
        || capabilities.has(McpCapability.PromptsListChanged) {
        JsonObject prompts = new JsonObject()
        if capabilities.has(McpCapability.PromptsListChanged) {
            prompts.set("listChanged", JsonValue.bool(true))
        }
        result.set("prompts", JsonValue.object(prompts))
    }
    if capabilities.has(McpCapability.Logging) {
        result.set("logging", JsonValue.object(new JsonObject()))
    }
    if capabilities.has(McpCapability.Completions) {
        result.set("completions", JsonValue.object(new JsonObject()))
    }
    if capabilities.has(McpCapability.Tasks) {
        result.set("tasks", JsonValue.object(new JsonObject()))
    }
    if capabilities.has(McpCapability.Sampling)
        || capabilities.has(McpCapability.SamplingTools) {
        JsonObject sampling = new JsonObject()
        if capabilities.has(McpCapability.SamplingTools) {
            sampling.set("tools", JsonValue.object(new JsonObject()))
        }
        result.set("sampling", JsonValue.object(sampling))
    }
    if capabilities.has(McpCapability.Roots) {
        result.set("roots", JsonValue.object(new JsonObject()))
    }
    if capabilities.has(McpCapability.Elicitation)
        || capabilities.has(McpCapability.ElicitationForm)
        || capabilities.has(McpCapability.ElicitationUrl) {
        JsonObject elicitation = new JsonObject()
        if capabilities.has(McpCapability.ElicitationForm) {
            elicitation.set("form", JsonValue.object(new JsonObject()))
        }
        if capabilities.has(McpCapability.ElicitationUrl) {
            elicitation.set("url", JsonValue.object(new JsonObject()))
        }
        result.set("elicitation", JsonValue.object(elicitation))
    }
    if capabilities.has(McpCapability.Extensions) {
        result.set("extensions", JsonValue.object(new JsonObject()))
    }
    if capabilities.has(McpCapability.Experimental) {
        result.set("experimental", JsonValue.object(new JsonObject()))
    }
    return result
}

Result<Set<McpCapability>, Error> parseMcpCapabilities(JsonObject capabilities) {
    if capabilities == null { throw "parseMcpCapabilities: null" }
    Set<McpCapability> result = new Set<McpCapability>()
    List<String> keys = capabilities.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        JsonValue value = capabilities.getOrNull(key)
        if value == null || !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "MCP capability must be object: " + key))
        }
        if key == "tools" {
            result.add(McpCapability.Tools)
            JsonValue? listChanged = value.asObject().getOrNull("listChanged")
            if listChanged != null && listChanged.isBool() && listChanged.asBool() {
                result.add(McpCapability.ToolsListChanged)
            }
        } else if key == "resources" {
            result.add(McpCapability.Resources)
            JsonValue? listChanged = value.asObject().getOrNull("listChanged")
            if listChanged != null && listChanged.isBool() && listChanged.asBool() {
                result.add(McpCapability.ResourcesListChanged)
            }
            JsonValue? subscribe = value.asObject().getOrNull("subscribe")
            if subscribe != null && subscribe.isBool() && subscribe.asBool() {
                result.add(McpCapability.ResourcesSubscribe)
            }
        } else if key == "prompts" {
            result.add(McpCapability.Prompts)
            JsonValue? listChanged = value.asObject().getOrNull("listChanged")
            if listChanged != null && listChanged.isBool() && listChanged.asBool() {
                result.add(McpCapability.PromptsListChanged)
            }
        } else if key == "logging" {
            result.add(McpCapability.Logging)
        } else if key == "completions" {
            result.add(McpCapability.Completions)
        } else if key == "tasks" {
            result.add(McpCapability.Tasks)
        } else if key == "sampling" {
            result.add(McpCapability.Sampling)
            if value.asObject().getOrNull("tools") != null {
                result.add(McpCapability.SamplingTools)
            }
        } else if key == "roots" {
            result.add(McpCapability.Roots)
        } else if key == "elicitation" {
            result.add(McpCapability.Elicitation)
            JsonValue? form = value.asObject().getOrNull("form")
            JsonValue? url = value.asObject().getOrNull("url")
            if form == null && url == null {
                result.add(McpCapability.ElicitationForm)
            } else {
                if form != null { result.add(McpCapability.ElicitationForm) }
                if url != null { result.add(McpCapability.ElicitationUrl) }
            }
        } else if key == "extensions" {
            result.add(McpCapability.Extensions)
        } else if key == "experimental" {
            result.add(McpCapability.Experimental)
        }
        index = index + 1
    }
    return Ok(result)
}
```
