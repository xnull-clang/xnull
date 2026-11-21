# `McpServer`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpServer` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `McpServerInfo`、`McpTool`、`McpToolResult`、`McpResource`、`McpContent`、`McpPrompt`、`McpTransport` |

---

## 1. 定位

MCP 服务端：注册 tools/resources/prompts，分派 JSON-RPC 请求，发送进度/日志通知，驱动传输读循环。

不做：进程启动、认证、TLS、工具执行沙箱、shell 拼接、任务扩展、订阅长流、缓存。

---

## 2. 设计逻辑

- 服务端是“注册表 + 分派器”，不是框架：业务 handler 由应用提供，本类型只校验方法/参数并组织响应。
- 注册项与 handler 分离：`McpTool` 是声明，handler 是执行；资源/prompt 同理。
- handler 首参 `Context`，便于取消/超时；handler 返回 `Result`，失败映射为 JSON-RPC 内部错误。
- handler 额外接收请求 id，用于 `notifyProgress`/`notifyLog` 关联；通知只发给当前请求。
- `serve` 借用 transport，不拥有它；HTTP 每次 exchange 一个 transport，stdio 一个长循环。
- modern 结果带 `resultType:"complete"`；legacy 不带。`server/discover` 必须 modern。
- 服务端不得主动执行 shell；工具是否执行命令由应用 handler 决定，并必须在应用层做 allowlist/确认/输入校验。
- 注册/分派无全局状态；每个 `McpServer` 独立。
- 关闭幂等；关闭后注册与分派返回 `Unavailable`。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_info` | `McpServerInfo` | final | 身份/能力/版本 |
| `_tools` | `Map<String, McpTool>` | final | 按名称 |
| `_toolHandlers` | `Map<String, ...>` | final | 工具执行器 |
| `_resources` | `Map<String, McpResource>` | final | 按 URI |
| `_resourceHandlers` | `Map<String, ...>` | final | 资源读取器 |
| `_prompts` | `Map<String, McpPrompt>` | final | 按名称 |
| `_promptHandlers` | `Map<String, ...>` | final | prompt 解析器 |
| `_open` | `Bool` | 可变 | 是否可用 |
| `_activeTransport` | `McpTransport?` | 可变 | serve 期间 |
| `_cancelled` | `Set<String>` | final | 已取消请求 id 文本 |
| `_progressTokens` | `Map<String, JsonRpcId>` | final | 请求 id → progress token |
| `_requestLogLevels` | `Map<String, String>` | final | 请求 id → log level |
| `_initialized` | `Bool` | 可变 | legacy initialized |
| `_legacyProtocolVersion` | `McpProtocolVersion?` | 可变 | 非 null 表示 legacy 模式 |

不变量：info 非 null；注册表键与声明一致；同一时刻最多一个 `serve`；legacy 模式下 `_legacyProtocolVersion` 非 null；modern 模式为 null；关闭后 open=false。

---

## 4. 生命周期

构造后可用；注册项可增删；`serve` 阻塞直到传输关闭/取消；必须 `close`；close 幂等；不关闭借用的 transport；handler 资源由应用关闭。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpServer(McpServerInfo info)` | info | 非 null | null → panic |

`info` 的能力是声明上限；实际能力由注册表推导，二者取并集（注册项自动补 Tools/Resources/Prompts）。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `info` | 服务端信息 | 无 | `McpServerInfo` | 无 |
| `capabilities` | 当前能力 | 无 | `Set<McpCapability>` | 无 |
| `registerTool` | 注册工具 | `McpTool tool, Result<McpToolResult, Error>(Context, JsonRpcId, JsonObject) handler` | `Result<Unit, Error>` | `InvalidArgument`/`AlreadyExists`/`Unavailable` |
| `unregisterTool` | 注销工具 | `String name` | `Bool` | 无 |
| `registerResource` | 注册资源 | `McpResource resource, Result<McpContent, Error>(Context, JsonRpcId) handler` | `Result<Unit, Error>` | `InvalidArgument`/`AlreadyExists`/`Unavailable` |
| `unregisterResource` | 注销资源 | `String uri` | `Bool` | 无 |
| `registerPrompt` | 注册 prompt | `McpPrompt prompt, Result<McpPrompt, Error>(Context, JsonRpcId, JsonObject) handler` | `Result<Unit, Error>` | `InvalidArgument`/`AlreadyExists`/`Unavailable` |
| `unregisterPrompt` | 注销 prompt | `String name` | `Bool` | 无 |
| `tools` | 工具快照 | 无 | `List<McpTool>` | 无 |
| `resources` | 资源快照 | 无 | `List<McpResource>` | 无 |
| `prompts` | prompt 快照 | 无 | `List<McpPrompt>` | 无 |
| `findTool` | 按名称查 | `String name` | `McpTool?` | 无 |
| `findResource` | 按 URI 查 | `String uri` | `McpResource?` | 无 |
| `findPrompt` | 按名称查 | `String name` | `McpPrompt?` | 无 |
| `handle` | 分派一条消息 | `Context context, JsonRpcRequest request` | `Result<JsonRpcResponse?, Error>` | `InvalidArgument`/`Unavailable` |
| `serve` | 读循环 | `Context context, McpTransport transport` | `Result<Unit, Error>` | `Busy`/`Network`/`Timeout`/`Cancelled`/`Io`/`Unavailable` |
| `notifyProgress` | 发进度 | `Context context, JsonRpcId requestIdentifier, Double progress, Double total, String message` | `Result<Unit, Error>` | `InvalidArgument`/`Unsupported`/`Unavailable` |
| `notifyLog` | 发日志 | `Context context, JsonRpcId requestIdentifier, String level, String logger, JsonValue data` | `Result<Unit, Error>` | `InvalidArgument`/`Unsupported`/`Unavailable` |
| `isCancelled` | 是否已取消 | `JsonRpcId requestIdentifier` | `Bool` | null → panic |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Unavailable`/`Io` |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `register*`：名称/URI 非空且唯一；资源 name 非空；handler 非 null；关闭后 `Unavailable`；重复 `AlreadyExists`。资源 handler 必须返回 `resource_content` 内容块；prompt handler 必须返回 `isResolved()` 为 true 的 prompt。
- `handle`：请求返回响应；通知返回 null；协议错误作为 `JsonRpcResponse.failure` 返回，不抛异常；只有关闭/内部不变量返回 `Err`。
- `serve`：同一时刻只允许一个；读到 `Unavailable` 且已处理至少一条消息视为正常结束（HTTP 单 exchange）。
- `notifyProgress`：只在请求带 progressToken 时可用；progress 必须递增由 handler 保证；total 可为 null? 参数为 `Double`，用负数表示未知；消息可空。HTTP 传输在响应前缓冲 SSE 事件，stdio 立即写。
- `notifyLog`：只在请求 `_meta.logLevel` 存在时可用；否则 `Unsupported`，不发通知；HTTP 同样缓冲到响应流。
- `close`：置 open=false，清空取消/进度/日志映射；不关闭 transport。

---

## 8. 使用的技术

- 注册表 + 分派；
- 函数类型 handler；
- JSON-RPC 结果构建；
- legacy/modern 双时代；
- 进度/日志通知；
- Result/Context。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、Double、List、Map、Set、Result；
- 运行时：无；
- 接口：`McpServerInfo`、`McpTool`、`McpToolResult`、`McpResource`、`McpContent`、`McpPrompt`、`McpTransport`、`Json`、`JsonRpcRequest`、`JsonRpcResponse`、`JsonRpcError`、`JsonRpcId`、`Error`。

---

## 10. 依赖的特性/接口/类

`McpServerInfo`、`McpCapability`、`McpProtocolVersion`、`McpTool`、`McpToolResult`、`McpResource`、`McpContent`、`McpPrompt`、`McpTransport`、`JsonObject`、`JsonValue`、`JsonArray`、`JsonRpcRequest`、`JsonRpcResponse`、`JsonRpcError`、`JsonRpcId`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 11. 所有权与并发

- 注册表由 server 拥有；返回列表是副本。
- `serve` 借用 transport；同一 server 不可并发 `serve`；`Busy`。
- `handle` 可在测试/自定义循环中调用；非线程安全，调用方串行化。
- `notifyProgress`/`notifyLog` 可在 handler 内调用；底层 transport 写串行化。
- `close` 可与其他调用并发；关闭后注册/分派/通知 `Unavailable`。
- handler 在 `serve` 的任务上执行；长任务应响应 `Context` 与 `isCancelled`。

---

## 12. 示例与反例

正确：`server.registerTool(tool, handler)` → `server.serve(context, new McpStdioTransport(stdin, stdout))`。  
反例：handler 直接拼接 shell；把未验证 URI 当文件路径；在 handler 外发送 progress；modern 结果缺 `resultType`；关闭后继续注册；并发 `serve`。

---

## 13. 测试/场景义务

注册/注销/重复；能力推导；tools/list/call；未知工具；资源 list/read；prompt list/get；legacy initialize/initialized；modern discover；缺 `_meta`；进度 token；日志级别缺失；取消；handler 错误；通知无响应；HTTP 单 exchange 正常结束；close 幂等；并发 serve。

---

## 14. XNull 伪代码

```xnull
class McpServer {
    final McpServerInfo _info
    final Map<String, McpTool> _tools
    final Map<String, Result<McpToolResult, Error>(Context, JsonRpcId, JsonObject)> _toolHandlers
    final Map<String, McpResource> _resources
    final Map<String, Result<McpContent, Error>(Context, JsonRpcId)> _resourceHandlers
    final Map<String, McpPrompt> _prompts
    final Map<String, Result<McpPrompt, Error>(Context, JsonRpcId, JsonObject)> _promptHandlers
    Bool _open
    McpTransport? _activeTransport
    final Set<String> _cancelled
    final Map<String, JsonRpcId> _progressTokens
    final Map<String, String> _requestLogLevels
    Bool _initialized
    McpProtocolVersion? _legacyProtocolVersion

    McpServer(McpServerInfo info) {
        if info == null { throw "McpServer: null info" }
        _info = info
        _tools = new Map<String, McpTool>()
        _toolHandlers = new Map<String, Result<McpToolResult, Error>(Context, JsonRpcId, JsonObject)>()
        _resources = new Map<String, McpResource>()
        _resourceHandlers = new Map<String, Result<McpContent, Error>(Context, JsonRpcId)>()
        _prompts = new Map<String, McpPrompt>()
        _promptHandlers = new Map<String, Result<McpPrompt, Error>(Context, JsonRpcId, JsonObject)>()
        _open = true
        _activeTransport = null
        _cancelled = new Set<String>()
        _progressTokens = new Map<String, JsonRpcId>()
        _requestLogLevels = new Map<String, String>()
        _initialized = false
        _legacyProtocolVersion = null
    }

    McpServerInfo info() { return _info }
    Bool isOpen() { return _open }

    Set<McpCapability> capabilities() {
        Set<McpCapability> result = _info.capabilities()
        if _tools.length() > 0 { result.add(McpCapability.Tools) }
        if _resources.length() > 0 { result.add(McpCapability.Resources) }
        if _prompts.length() > 0 { result.add(McpCapability.Prompts) }
        return result
    }

    JsonObject capabilitiesJson() { return mcpCapabilitiesJson(self.capabilities()) }

    Result<Unit, Error> registerTool(McpTool tool,
        Result<McpToolResult, Error>(Context, JsonRpcId, JsonObject) handler) {
        if tool == null || handler == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpServer.registerTool: null"))
        }
        if !_open { return Err(unavailableError("mcp server")) }
        if _tools.has(tool.name()) {
            return Err(new BasicError(ErrorKind.AlreadyExists, "tool already registered"))
        }
        _tools.put(tool.name(), tool)
        _toolHandlers.put(tool.name(), handler)
        return Ok(unit)
    }

    Result<Unit, Error> registerResource(McpResource resource,
        Result<McpContent, Error>(Context, JsonRpcId) handler) {
        if resource == null || handler == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpServer.registerResource: null"))
        }
        if resource.name() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpServer.registerResource: empty name"))
        }
        if !_open { return Err(unavailableError("mcp server")) }
        if _resources.has(resource.uri()) {
            return Err(new BasicError(ErrorKind.AlreadyExists, "resource already registered"))
        }
        _resources.put(resource.uri(), resource)
        _resourceHandlers.put(resource.uri(), handler)
        return Ok(unit)
    }

    Result<Unit, Error> registerPrompt(McpPrompt prompt,
        Result<McpPrompt, Error>(Context, JsonRpcId, JsonObject) handler) {
        if prompt == null || handler == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpServer.registerPrompt: null"))
        }
        if !_open { return Err(unavailableError("mcp server")) }
        if _prompts.has(prompt.name()) {
            return Err(new BasicError(ErrorKind.AlreadyExists, "prompt already registered"))
        }
        _prompts.put(prompt.name(), prompt)
        _promptHandlers.put(prompt.name(), handler)
        return Ok(unit)
    }

    Bool unregisterTool(String name) {
        Bool removedTool = _tools.remove(name)
        Bool removedHandler = _toolHandlers.remove(name)
        return removedTool || removedHandler
    }
    Bool unregisterResource(String uri) {
        Bool removedResource = _resources.remove(uri)
        Bool removedHandler = _resourceHandlers.remove(uri)
        return removedResource || removedHandler
    }
    Bool unregisterPrompt(String name) {
        Bool removedPrompt = _prompts.remove(name)
        Bool removedHandler = _promptHandlers.remove(name)
        return removedPrompt || removedHandler
    }

    List<McpTool> tools() { return _tools.values() }
    List<McpResource> resources() { return _resources.values() }
    List<McpPrompt> prompts() { return _prompts.values() }
    McpTool? findTool(String name) {
        if _tools.has(name) { return _tools.get(name) }
        return null
    }
    McpResource? findResource(String uri) {
        if _resources.has(uri) { return _resources.get(uri) }
        return null
    }
    McpPrompt? findPrompt(String name) {
        if _prompts.has(name) { return _prompts.get(name) }
        return null
    }

    Result<JsonRpcResponse?, Error> handle(Context context, JsonRpcRequest request) {
        if context == null || request == null {
            throw "McpServer.handle: null argument"
        }
        if !_open { return Err(unavailableError("mcp server")) }
        if request.isNotification() {
            if request.method() == "notifications/initialized" {
                _initialized = true
                return Ok(null)
            }
            if request.method() == "notifications/cancelled" {
                self.handleCancelled(request)
                return Ok(null)
            }
            return Ok(null)
        }
        if request.method() == "initialize" {
            return self.handleInitialize(context, request)
        }
        if request.method() == "server/discover" {
            return self.handleDiscover(context, request)
        }
        if _legacyProtocolVersion == null {
            Result<JsonObject, Error> meta = self.requireModernMeta(request)
            if meta.isErr() {
                if meta.error().kind() == ErrorKind.Unsupported {
                    return Ok(self.failure(request,
                        new JsonRpcError(-32022, "Unsupported protocol version")))
                }
                return Ok(self.failure(request,
                    new JsonRpcError(-32602, meta.error().describe())))
            }
        }
        if request.method() == "tools/list" {
            JsonObject result = new JsonObject()
            JsonArray array = new JsonArray()
            List<McpTool> values = _tools.values()
            Int index = 0
            while index < values.length() {
                array.add(JsonValue.object(values.get(index).toJson()))
                index = index + 1
            }
            result.set("tools", JsonValue.array(array))
            return Ok(self.success(request, result))
        }
        if request.method() == "tools/call" {
            return self.handleToolCall(context, request)
        }
        if request.method() == "resources/list" {
            JsonObject result = new JsonObject()
            JsonArray array = new JsonArray()
            List<McpResource> values = _resources.values()
            Int index = 0
            while index < values.length() {
                array.add(JsonValue.object(values.get(index).toJson()))
                index = index + 1
            }
            result.set("resources", JsonValue.array(array))
            return Ok(self.success(request, result))
        }
        if request.method() == "resources/read" {
            return self.handleResourceRead(context, request)
        }
        if request.method() == "prompts/list" {
            JsonObject result = new JsonObject()
            JsonArray array = new JsonArray()
            List<McpPrompt> values = _prompts.values()
            Int index = 0
            while index < values.length() {
                array.add(JsonValue.object(values.get(index).toJson()))
                index = index + 1
            }
            result.set("prompts", JsonValue.array(array))
            return Ok(self.success(request, result))
        }
        if request.method() == "prompts/get" {
            return self.handlePromptGet(context, request)
        }
        return Ok(self.failure(request, JsonRpcError.methodNotFound(request.method())))
    }

    private Result<JsonRpcResponse?, Error> handleInitialize(Context context, JsonRpcRequest request) {
        JsonValue? parametersValue = request.parameters()
        if parametersValue == null || !parametersValue.isObject() {
            return Ok(self.failure(request, JsonRpcError.invalidParams("initialize params")))
        }
        JsonObject parameters = parametersValue.asObject()
        JsonValue? versionValue = parameters.getOrNull("protocolVersion")
        if versionValue == null || !versionValue.isString() {
            return Ok(self.failure(request, JsonRpcError.invalidParams("protocolVersion")))
        }
        Result<McpProtocolVersion, Error> version =
            parseMcpProtocolVersion(versionValue.asString())
        if version.isErr() || !isLegacyMcpProtocolVersion(version.value())
            || !_info.supportsProtocolVersion(version.value()) {
            JsonObject data = new JsonObject()
            data.set("supported", JsonValue.array(self.supportedVersionsJson()))
            JsonRpcError error = new JsonRpcError(-32602, "Unsupported protocol version")
            return Ok(self.failure(request, error.withData(JsonValue.object(data))))
        }
        _legacyProtocolVersion = version.value()
        _initialized = false
        JsonObject result = new JsonObject()
        result.set("protocolVersion", JsonValue.string(mcpProtocolVersionText(version.value())))
        result.set("capabilities", JsonValue.object(self.capabilitiesJson()))
        result.set("serverInfo", JsonValue.object(_info.toIdentityJson()))
        if _info.instructions() != "" {
            result.set("instructions", JsonValue.string(_info.instructions()))
        }
        return Ok(JsonRpcResponse.success(request.identifier(), JsonValue.object(result)))
    }

    private Result<JsonRpcResponse?, Error> handleDiscover(Context context, JsonRpcRequest request) {
        Result<JsonObject, Error> meta = self.requireModernMeta(request)
        if meta.isErr() {
            if meta.error().kind() == ErrorKind.Unsupported {
                return Ok(self.failure(request,
                    new JsonRpcError(-32022, "Unsupported protocol version")))
            }
            return Ok(self.failure(request, new JsonRpcError(-32602, meta.error().describe())))
        }
        JsonObject result = new JsonObject()
        result.set("resultType", JsonValue.string("complete"))
        result.set("supportedVersions", JsonValue.array(self.supportedVersionsJson()))
        result.set("capabilities", JsonValue.object(self.capabilitiesJson()))
        JsonObject metaResult = new JsonObject()
        metaResult.set("io.modelcontextprotocol/serverInfo",
            JsonValue.object(_info.toIdentityJson()))
        result.set("_meta", JsonValue.object(metaResult))
        if _info.instructions() != "" {
            result.set("instructions", JsonValue.string(_info.instructions()))
        }
        return Ok(JsonRpcResponse.success(request.identifier(), JsonValue.object(result)))
    }

    private Result<JsonRpcResponse?, Error> handleToolCall(Context context, JsonRpcRequest request) {
        JsonValue? parametersValue = request.parameters()
        if parametersValue == null || !parametersValue.isObject() {
            return Ok(self.failure(request, JsonRpcError.invalidParams("tools/call params")))
        }
        JsonObject parameters = parametersValue.asObject()
        JsonValue? nameValue = parameters.getOrNull("name")
        if nameValue == null || !nameValue.isString() {
            return Ok(self.failure(request, JsonRpcError.invalidParams("tool name")))
        }
        String name = nameValue.asString()
        if !_tools.has(name) || !_toolHandlers.has(name) {
            return Ok(self.failure(request, JsonRpcError.invalidParams("unknown tool: " + name)))
        }
        JsonObject arguments = new JsonObject()
        JsonValue? argumentsValue = parameters.getOrNull("arguments")
        if argumentsValue != null {
            if !argumentsValue.isObject() {
                return Ok(self.failure(request, JsonRpcError.invalidParams("arguments")))
            }
            arguments = argumentsValue.asObject()
        }
        String key = request.identifier().wireText()
        self.captureRequestMeta(request, key)
        Result<McpToolResult, Error> executed =
            _toolHandlers.get(name)(context, request.identifier(), arguments)
        self.releaseRequestMeta(key)
        if executed.isErr() {
            return Ok(self.failure(request,
                JsonRpcError.internalError("tool execution failed")))
        }
        JsonObject result = executed.value().toJson()
        return Ok(self.success(request, result))
    }

    private Result<JsonRpcResponse?, Error> handleResourceRead(Context context, JsonRpcRequest request) {
        JsonValue? parametersValue = request.parameters()
        if parametersValue == null || !parametersValue.isObject() {
            return Ok(self.failure(request, JsonRpcError.invalidParams("resources/read params")))
        }
        JsonValue? uriValue = parametersValue.asObject().getOrNull("uri")
        if uriValue == null || !uriValue.isString() {
            return Ok(self.failure(request, JsonRpcError.invalidParams("resource uri")))
        }
        String uri = uriValue.asString()
        if !_resources.has(uri) || !_resourceHandlers.has(uri) {
            return Ok(self.failure(request, JsonRpcError.invalidParams("unknown resource")))
        }
        String key = request.identifier().wireText()
        self.captureRequestMeta(request, key)
        Result<McpContent, Error> content =
            _resourceHandlers.get(uri)(context, request.identifier())
        self.releaseRequestMeta(key)
        if content.isErr() || !content.value().isResourceContent() {
            return Ok(self.failure(request,
                JsonRpcError.internalError("resource read failed")))
        }
        JsonObject result = new JsonObject()
        JsonArray contents = new JsonArray()
        contents.add(JsonValue.object(content.value().toJson()))
        result.set("contents", JsonValue.array(contents))
        return Ok(self.success(request, result))
    }

    private Result<JsonRpcResponse?, Error> handlePromptGet(Context context, JsonRpcRequest request) {
        JsonValue? parametersValue = request.parameters()
        if parametersValue == null || !parametersValue.isObject() {
            return Ok(self.failure(request, JsonRpcError.invalidParams("prompts/get params")))
        }
        JsonObject parameters = parametersValue.asObject()
        JsonValue? nameValue = parameters.getOrNull("name")
        if nameValue == null || !nameValue.isString() {
            return Ok(self.failure(request, JsonRpcError.invalidParams("prompt name")))
        }
        String name = nameValue.asString()
        if !_prompts.has(name) || !_promptHandlers.has(name) {
            return Ok(self.failure(request, JsonRpcError.invalidParams("unknown prompt")))
        }
        JsonObject arguments = new JsonObject()
        JsonValue? argumentsValue = parameters.getOrNull("arguments")
        if argumentsValue != null {
            if !argumentsValue.isObject() {
                return Ok(self.failure(request, JsonRpcError.invalidParams("arguments")))
            }
            arguments = argumentsValue.asObject()
        }
        String key = request.identifier().wireText()
        self.captureRequestMeta(request, key)
        Result<McpPrompt, Error> resolved =
            _promptHandlers.get(name)(context, request.identifier(), arguments)
        self.releaseRequestMeta(key)
        if resolved.isErr() || !resolved.value().isResolved() {
            return Ok(self.failure(request,
                JsonRpcError.internalError("prompt resolution failed")))
        }
        JsonObject result = new JsonObject()
        if resolved.value().description() != "" {
            result.set("description", JsonValue.string(resolved.value().description()))
        }
        JsonArray messages = new JsonArray()
        List<McpContent> contents = resolved.value().messages()
        Int index = 0
        while index < contents.length() {
            JsonObject message = new JsonObject()
            message.set("role", JsonValue.string(resolved.value().messageRole(index)))
            message.set("content", JsonValue.object(contents.get(index).toJson()))
            messages.add(JsonValue.object(message))
            index = index + 1
        }
        result.set("messages", JsonValue.array(messages))
        return Ok(self.success(request, result))
    }

    private Result<JsonObject, Error> requireModernMeta(JsonRpcRequest request) {
        JsonValue? parametersValue = request.parameters()
        if parametersValue == null || !parametersValue.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "missing params"))
        }
        JsonValue? metaValue = parametersValue.asObject().getOrNull("_meta")
        if metaValue == null || !metaValue.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "missing _meta"))
        }
        JsonObject meta = metaValue.asObject()
        JsonValue? versionValue = meta.getOrNull(
            "io.modelcontextprotocol/protocolVersion")
        if versionValue == null || !versionValue.isString() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "missing protocolVersion"))
        }
        Result<McpProtocolVersion, Error> version =
            parseMcpProtocolVersion(versionValue.asString())
        if version.isErr() || !isModernMcpProtocolVersion(version.value())
            || !_info.supportsProtocolVersion(version.value()) {
            return Err(new BasicError(ErrorKind.Unsupported, "unsupported protocol version"))
        }
        JsonValue? capabilitiesValue = meta.getOrNull(
            "io.modelcontextprotocol/clientCapabilities")
        if capabilitiesValue == null || !capabilitiesValue.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "missing clientCapabilities"))
        }
        return Ok(meta)
    }

    private void captureRequestMeta(JsonRpcRequest request, String key) {
        JsonValue? parametersValue = request.parameters()
        if parametersValue == null || !parametersValue.isObject() { return }
        JsonValue? metaValue = parametersValue.asObject().getOrNull("_meta")
        if metaValue == null || !metaValue.isObject() { return }
        JsonObject meta = metaValue.asObject()
        JsonValue? tokenValue = meta.getOrNull("progressToken")
        if tokenValue != null {
            Result<JsonRpcId, Error> token = JsonRpcId.parse(tokenValue)
            if token.isOk() { _progressTokens.put(key, token.value()) }
        }
        JsonValue? levelValue = meta.getOrNull("io.modelcontextprotocol/logLevel")
        if levelValue != null && levelValue.isString() {
            _requestLogLevels.put(key, levelValue.asString())
        }
    }

    private void releaseRequestMeta(String key) {
        _progressTokens.remove(key)
        _requestLogLevels.remove(key)
        _cancelled.remove(key)
    }

    private void handleCancelled(JsonRpcRequest request) {
        JsonValue? parametersValue = request.parameters()
        if parametersValue == null || !parametersValue.isObject() { return }
        JsonValue? identifierValue = parametersValue.asObject().getOrNull("requestId")
        if identifierValue == null { return }
        Result<JsonRpcId, Error> identifier = JsonRpcId.parse(identifierValue)
        if identifier.isOk() {
            _cancelled.add(identifier.value().wireText())
        }
    }

    private JsonRpcResponse? success(JsonRpcRequest request, JsonObject result) {
        if request.isNotification() { return null }
        if request.identifier() == null { return null }
        if _legacyProtocolVersion == null {
            result.set("resultType", JsonValue.string("complete"))
        }
        return JsonRpcResponse.success(request.identifier(), JsonValue.object(result))
    }

    private JsonRpcResponse? failure(JsonRpcRequest request, JsonRpcError error) {
        if request.isNotification() { return null }
        return JsonRpcResponse.failure(request.identifier(), error)
    }

    private JsonArray supportedVersionsJson() {
        JsonArray versions = new JsonArray()
        List<McpProtocolVersion> values = _info.protocolVersions()
        Int index = 0
        while index < values.length() {
            versions.add(JsonValue.string(mcpProtocolVersionText(values.get(index))))
            index = index + 1
        }
        return versions
    }

    Result<Unit, Error> serve(Context context, McpTransport transport) {
        if context == null || transport == null {
            throw "McpServer.serve: null argument"
        }
        if !_open { return Err(unavailableError("mcp server")) }
        if _activeTransport != null {
            return Err(new BasicError(ErrorKind.Busy, "McpServer: already serving"))
        }
        _activeTransport = transport
        Int handled = 0
        while _open {
            Result<JsonRpcRequest, Error> incoming = transport.receive(context)
            if incoming.isErr() {
                _activeTransport = null
                if handled > 0 && incoming.error().kind() == ErrorKind.Unavailable {
                    return Ok(unit)
                }
                return Err(incoming.error())
            }
            Result<JsonRpcResponse?, Error> response = self.handle(context, incoming.value())
            if response.isErr() {
                _activeTransport = null
                return response
            }
            if response.value() == null {
                Result<Unit, Error> acknowledged = transport.acknowledge(context)
                if acknowledged.isErr() {
                    _activeTransport = null
                    return acknowledged
                }
            } else {
                Result<Unit, Error> sent = transport.respond(context, response.value())
                if sent.isErr() {
                    _activeTransport = null
                    return sent
                }
            }
            handled = handled + 1
        }
        _activeTransport = null
        return Ok(unit)
    }

    Result<Unit, Error> notifyProgress(Context context, JsonRpcId requestIdentifier,
        Double progress, Double total, String message) {
        if context == null || requestIdentifier == null {
            throw "McpServer.notifyProgress: null argument"
        }
        if _activeTransport == null { return Err(unavailableError("mcp server not serving")) }
        String key = requestIdentifier.wireText()
        if !_progressTokens.has(key) {
            return Err(new BasicError(ErrorKind.Unsupported, "no progress token"))
        }
        JsonObject parameters = new JsonObject()
        parameters.set("progressToken", _progressTokens.get(key).toJsonValue())
        parameters.set("progress", JsonValue.number(new JsonNumber(str(progress))))
        if total >= 0.0 {
            parameters.set("total", JsonValue.number(new JsonNumber(str(total))))
        }
        if message != "" { parameters.set("message", JsonValue.string(message)) }
        JsonRpcRequest notification = new JsonRpcRequest("notifications/progress",
            JsonValue.object(parameters))
        return _activeTransport.notify(context, notification)
    }

    Result<Unit, Error> notifyLog(Context context, JsonRpcId requestIdentifier,
        String level, String logger, JsonValue data) {
        if context == null || requestIdentifier == null || data == null {
            throw "McpServer.notifyLog: null argument"
        }
        if _activeTransport == null { return Err(unavailableError("mcp server not serving")) }
        String key = requestIdentifier.wireText()
        if !_requestLogLevels.has(key) {
            return Err(new BasicError(ErrorKind.Unsupported, "log level not requested"))
        }
        JsonObject parameters = new JsonObject()
        parameters.set("level", JsonValue.string(level))
        if logger != "" { parameters.set("logger", JsonValue.string(logger)) }
        parameters.set("data", data)
        JsonRpcRequest notification = new JsonRpcRequest("notifications/message",
            JsonValue.object(parameters))
        return _activeTransport.notify(context, notification)
    }

    Bool isCancelled(JsonRpcId requestIdentifier) {
        if requestIdentifier == null { throw "McpServer.isCancelled: null" }
        return _cancelled.has(requestIdentifier.wireText())
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        _activeTransport = null
        _cancelled.clear()
        _progressTokens.clear()
        _requestLogLevels.clear()
        return Ok(unit)
    }
}
```

> 私有辅助方法 `requireModernMeta`、`captureRequestMeta`、`releaseRequestMeta`、`handleCancelled`、`success`、`failure`、`supportedVersionsJson` 已在上方给出：分别校验 modern `_meta`、登记进度/日志 token、清理请求级状态、登记取消、补 `resultType`、对通知抑制响应、序列化支持版本。它们不是公开 API，不进入方法总表。
