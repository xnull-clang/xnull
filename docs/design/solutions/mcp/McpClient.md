# `McpClient`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpClient` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `McpTransport`、`McpClientInfo`、`McpSession`、`McpTool`、`McpToolResult`、`McpResource`、`McpContent`、`McpPrompt` |

---

## 1. 定位

MCP 客户端：协商版本/能力、列出/调用工具、列出/读取资源、列出/获取 prompt、进度、取消、工具 allowlist 与确认。

不做：LLM 推理、采样实现、Agent 编排、进程启动、OAuth 授权服务器、工具沙箱、任务扩展。

---

## 2. 设计逻辑

- `McpClient` 持有一个 `McpTransport`，不关心 stdio/HTTP 细节。
- 初始化支持两种时代：modern 先 `server/discover`，失败回退 legacy `initialize`；legacy 成功后发 `notifications/initialized`。
- modern 每个请求注入 `_meta`：协议版本、clientInfo、clientCapabilities；legacy 只在 progress 时注入 `_meta.progressToken`。
- 工具默认拒绝：`_allowedTools` 为空表示一个都不允许；调用前检查 allowlist。
- 确认默认开启：`requireConfirmation` 为 true 时，`callTool` 必须提供确认回调；回调拒绝 → `PermissionDenied`。
- 工具结果 `isError` 是正常返回，不转成 `Err`；协议错误才转 `Err`。
- MRTR：结果 `resultType:"input_required"` 时，按 `inputRequests` 调用输入回调，带 `inputResponses`/`requestState` 用新 id 重试；最多 8 轮。
- 进度：请求 id 作为 progress token；通知回调按 token 找到对应 handler；结束后清理。
- 不自动重试；断流/超时由调用方用新 id 重发。
- 单客户端非线程安全；并发调用需调用方串行化（X 可加内部多路复用）。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_transport` | `McpTransport` | final | 已连接传输 |
| `_clientInfo` | `McpClientInfo` | final | 客户端声明 |
| `_allowedTools` | `Set<String>` | final | 工具 allowlist；空=全拒绝 |
| `_requireConfirmation` | `Bool` | final | 是否要求确认 |
| `_nextIdentifier` | `Long` | 可变 | 请求 id 递增 |
| `_session` | `McpSession?` | 可变 | 初始化后快照 |
| `_open` | `Bool` | 可变 | 是否可用 |
| `_tools` | `Map<String, McpTool>` | final | `tools/list` 缓存 |
| `_progressHandlers` | `Map<String, ...>` | final | token → 进度回调 |
| `_logLevel` | `String` | 可变 | modern 请求的日志级别；空=不请求 |
| `_logHandler` | 函数? | 可变 | `notifications/message` 回调 |
| `_notificationFailures` | `Int` | 可变 | 通知回调失败计数 |

不变量：transport/clientInfo 非 null；`_session != null` 时 initialized；allowlist 元素非空；progress handler 在请求结束后移除；关闭后 open=false。

---

## 4. 生命周期

构造后未初始化；必须 `initialize` 后才能调用业务方法；必须 `close`；close 幂等；关闭后所有方法 `Unavailable`；不拥有 transport 之外的资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpClient(McpTransport transport, McpClientInfo clientInfo)` | transport/clientInfo | 非 null | null → panic |
| `McpClient(McpTransport transport, McpClientInfo clientInfo, Set<String> allowedTools, Bool requireConfirmation)` | 四参数 | 非 null；allowlist 元素非空 | 非法 → panic |

默认 allowlist 为空（全拒绝），`requireConfirmation` 为 true。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `initialize` | 版本/能力协商 | `Context context` | `Result<McpSession, Error>` | `Network`/`Timeout`/`Cancelled`/`DataCorrupted`/`Unsupported`/`Unavailable` |
| `session` | 会话快照 | 无 | `McpSession?` | 无 |
| `isInitialized` | 是否已初始化 | 无 | `Bool` | 无 |
| `protocolVersion` | 当前版本 | 无 | `McpProtocolVersion?` | 无 |
| `serverInfo` | 服务端信息 | 无 | `McpServerInfo?` | 无 |
| `listTools` | 列出工具 | `Context context` | `Result<List<McpTool>, Error>` | 协议/网络/取消 |
| `callTool` | 调用工具（简化） | `Context context, String toolName, JsonObject arguments` | `Result<McpToolResult, Error>` | `PermissionDenied`/`NotFound`/协议/网络/取消 |
| `callTool` | 调用工具（完整） | `Context context, String toolName, JsonObject arguments, Result<Bool, Error>(Context, McpTool, JsonObject) confirm, Result<Unit, Error>(Context, Double, Double, String) progress, Result<JsonObject, Error>(Context, String, JsonObject) inputHandler` | `Result<McpToolResult, Error>` | 同上 |
| `listResources` | 列出资源 | `Context context` | `Result<List<McpResource>, Error>` | 协议/网络/取消 |
| `readResource` | 读取资源（简化） | `Context context, String resourceUri` | `Result<List<McpContent>, Error>` | `NotFound`/协议/网络/取消 |
| `readResource` | 读取资源（支持输入） | `Context context, String resourceUri, Result<JsonObject, Error>(Context, String, JsonObject) inputHandler` | `Result<List<McpContent>, Error>` | 同上 |
| `listPrompts` | 列出 prompt | `Context context` | `Result<List<McpPrompt>, Error>` | 协议/网络/取消 |
| `getPrompt` | 获取 prompt | `Context context, String promptName, JsonObject arguments, Result<JsonObject, Error>(Context, String, JsonObject) inputHandler` | `Result<McpPrompt, Error>` | `NotFound`/协议/网络/取消 |
| `cancel` | 取消请求 | `Context context, JsonRpcId requestIdentifier, String reason` | `Result<Unit, Error>` | `Unavailable` |
| `setLogLevel` | 设置请求日志级别 | `String level` | `Result<Unit, Error>` | `InvalidArgument` |
| `logLevel` | 当前日志级别 | 无 | `String` | 无 |
| `setLogHandler` | 设置日志回调 | `Result<Unit, Error>(Context, String, String, JsonValue) handler` | `Result<Unit, Error>` | `InvalidArgument` |
| `clearLogHandler` | 清除日志回调 | 无 | `Unit` | 无 |
| `allowTool` | 加入 allowlist | `String name` | `Result<Unit, Error>` | `InvalidArgument` |
| `denyTool` | 移出 allowlist | `String name` | `Bool` | 无 |
| `allowedTools` | allowlist 副本 | 无 | `Set<String>` | 无 |
| `requireConfirmation` | 是否要求确认 | 无 | `Bool` | 无 |
| `notificationFailureCount` | 回调失败数 | 无 | `Int` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `initialize` 幂等：已初始化返回当前 session；失败不设置 session。
- 内部 `call` 不公开，避免绕过 allowlist/确认；业务方法统一经 `listTools`/`callTool`/`readResource`/`getPrompt`。
- `callTool` 简化版在 `requireConfirmation` 为 true 时返回 `PermissionDenied`；完整版使用回调。
- `readResource` 返回 `resource_content` 内容块；`getPrompt` 把 name 补进结果再解析。
- `cancel` 对未知 id 幂等；HTTP 关闭流，stdio 发通知。
- `setLogLevel` 接受 syslog 八级；modern 请求 `_meta` 注入 `io.modelcontextprotocol/logLevel`；legacy 不发送（X 的 `logging/setLevel` 不做）。
- `setLogHandler` 接收 `notifications/message` 的 level/logger/data；未设置时忽略日志通知。
- `close` 关闭 transport；不清空 allowlist；再次 close 幂等。

---

## 8. 使用的技术

- 状态机（未初始化/已初始化/关闭）；
- modern/legacy 双协议；
- JSON `_meta` 注入；
- MRTR 重试；
- 进度 token 关联；
- allowlist/确认；
- Result/Context。

---

## 9. 需要的支撑

- 语言：class、String、Long、Int、Bool、Double、List、Map、Set、Result；
- 运行时：无；
- 接口：`McpTransport`、`McpClientInfo`、`McpSession`、`McpTool`、`McpToolResult`、`McpResource`、`McpContent`、`McpPrompt`、`Json`、`JsonRpcRequest`、`JsonRpcResponse`、`JsonRpcId`、`Error`。

---

## 10. 依赖的特性/接口/类

`McpTransport`、`McpClientInfo`、`McpServerInfo`、`McpSession`、`McpTool`、`McpToolResult`、`McpResource`、`McpContent`、`McpPrompt`、`McpProtocolVersion`、`JsonObject`、`JsonValue`、`JsonArray`、`JsonRpcRequest`、`JsonRpcResponse`、`JsonRpcError`、`JsonRpcId`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 11. 所有权与并发

- 拥有 transport；close 关闭它。
- 非线程安全；同一 client 的 `call`/`initialize` 需串行化。
- `cancel` 可在其他任务调用（只调用 transport.cancel）；不保证与请求并发安全，由传输实现声明。
- 进度回调在 transport 请求任务上调用；不得重入 `call`。
- `_tools` 缓存由 `listTools` 更新；`callTool` 可隐式 list 一次。

---

## 12. 示例与反例

正确：`client.initialize(context)` → `client.listTools(context)` → `client.callTool(context, name, arguments, confirm, progress, inputHandler)`。  
反例：不初始化就调用；allowlist 为空仍调用；确认回调恒 true；把 `isError` 当协议错误；在进度回调里再发请求；modern 请求漏 `_meta`。

---

## 13. 测试/场景义务

initialize modern/legacy/回退；重复 initialize；缺 `_meta`；list/call；未知工具；allowlist；确认拒绝；工具 `isError`；资源读；prompt get；MRTR 一轮/多轮/超轮；进度通知；取消；close 幂等；HTTP session id；通知回调失败计数。

---

## 14. XNull 伪代码

```xnull
class McpClient {
    final McpTransport _transport
    final McpClientInfo _clientInfo
    final Set<String> _allowedTools
    final Bool _requireConfirmation
    Long _nextIdentifier
    McpSession? _session
    Bool _open
    final Map<String, McpTool> _tools
    final Map<String, Result<Unit, Error>(Context, Double, Double, String)> _progressHandlers
    String _logLevel
    Result<Unit, Error>(Context, String, String, JsonValue)? _logHandler
    Int _notificationFailures

    McpClient(McpTransport transport, McpClientInfo clientInfo) {
        if transport == null || clientInfo == null {
            throw "McpClient: null argument"
        }
        _transport = transport
        _clientInfo = clientInfo
        _allowedTools = new Set<String>()
        _requireConfirmation = true
        _nextIdentifier = 0L
        _session = null
        _open = true
        _tools = new Map<String, McpTool>()
        _progressHandlers = new Map<String, Result<Unit, Error>(Context, Double, Double, String)>()
        _logLevel = ""
        _logHandler = null
        _notificationFailures = 0
    }

    McpClient(McpTransport transport, McpClientInfo clientInfo,
              Set<String> allowedTools, Bool requireConfirmation) {
        if transport == null || clientInfo == null || allowedTools == null {
            throw "McpClient: null argument"
        }
        _transport = transport
        _clientInfo = clientInfo
        _allowedTools = allowedTools.copy()
        _requireConfirmation = requireConfirmation
        _nextIdentifier = 0L
        _session = null
        _open = true
        _tools = new Map<String, McpTool>()
        _progressHandlers = new Map<String, Result<Unit, Error>(Context, Double, Double, String)>()
        _logLevel = ""
        _logHandler = null
        _notificationFailures = 0
    }

    JsonRpcId nextIdentifier() {
        _nextIdentifier = _nextIdentifier + 1L
        if _nextIdentifier <= 0L { _nextIdentifier = 1L }
        return new JsonRpcId(_nextIdentifier)
    }

    Result<McpSession, Error> initialize(Context context) {
        if context == null { throw "McpClient.initialize: null context" }
        if !_open { return Err(unavailableError("mcp client")) }
        if _session != null { return Ok(_session) }
        List<McpProtocolVersion> versions = _clientInfo.protocolVersions()
        Bool supportsModern = false
        Bool supportsLegacy = false
        Int index = 0
        while index < versions.length() {
            if isModernMcpProtocolVersion(versions.get(index)) { supportsModern = true }
            if isLegacyMcpProtocolVersion(versions.get(index)) { supportsLegacy = true }
            index = index + 1
        }
        if supportsModern {
            Result<McpSession, Error> modern = self.initializeModern(context, versions)
            if modern.isOk() {
                _session = modern.value()
                return modern
            }
            if !supportsLegacy {
                return modern
            }
            if modern.error().kind() != ErrorKind.Unsupported
                && modern.error().kind() != ErrorKind.NotFound {
                return modern
            }
        }
        if supportsLegacy {
            return self.initializeLegacy(context, versions)
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "McpClient: no supported protocol version"))
    }

    private Result<McpSession, Error> initializeModern(Context context,
        List<McpProtocolVersion> versions) {
        McpProtocolVersion version = versions.get(0)
        Result<JsonObject, Error> discovered = Err(new BasicError(ErrorKind.Unsupported,
            "McpClient: no modern version"))
        Int index = 0
        while index < versions.length() {
            if isModernMcpProtocolVersion(versions.get(index)) {
                version = versions.get(index)
                Result<Unit, Error> selected =
                    _transport.selectProtocolVersion(context, version)
                if selected.isErr() { return Err(selected.error()) }
                JsonObject parameters = new JsonObject()
                JsonObject meta = new JsonObject()
                meta.set("io.modelcontextprotocol/protocolVersion",
                    JsonValue.string(mcpProtocolVersionText(version)))
                meta.set("io.modelcontextprotocol/clientInfo",
                    JsonValue.object(_clientInfo.toIdentityJson()))
                meta.set("io.modelcontextprotocol/clientCapabilities",
                    JsonValue.object(_clientInfo.toCapabilitiesJson()))
                parameters.set("_meta", JsonValue.object(meta))
                discovered = self.callInternal(context, "server/discover",
                    parameters, version, null, null)
                if discovered.isOk() { break }
                if discovered.error().kind() != ErrorKind.Unsupported
                    && discovered.error().kind() != ErrorKind.NotFound {
                    return Err(discovered.error())
                }
            }
            index = index + 1
        }
        if discovered.isErr() { return Err(discovered.error()) }
        Result<McpServerInfo, Error> server = McpServerInfo.parse(
            JsonValue.object(discovered.value()))
        if server.isErr() { return Err(server.error()) }
        McpProtocolVersion chosen = version
        Bool found = false
        index = 0
        while index < versions.length() {
            if isModernMcpProtocolVersion(versions.get(index))
                && server.value().supportsProtocolVersion(versions.get(index)) {
                chosen = versions.get(index)
                found = true
                break
            }
            index = index + 1
        }
        if !found {
            return Err(new BasicError(ErrorKind.Unsupported,
                "McpClient: no common modern version"))
        }
        Result<Unit, Error> chosenResult = _transport.selectProtocolVersion(context, chosen)
        if chosenResult.isErr() { return Err(chosenResult.error()) }
        String? sessionId = _transport.sessionIdentifier()
        String identifier = ""
        if sessionId != null { identifier = sessionId }
        McpSession session = new McpSession(chosen, server.value(), _clientInfo,
            identifier, true, true, true)
        _session = session
        return Ok(session)
    }

    private Result<McpSession, Error> initializeLegacy(Context context,
        List<McpProtocolVersion> versions) {
        McpProtocolVersion version = McpProtocolVersion.V2025_11_25
        Bool found = false
        Int index = 0
        while index < versions.length() {
            if isLegacyMcpProtocolVersion(versions.get(index)) {
                version = versions.get(index)
                found = true
                break
            }
            index = index + 1
        }
        if !found {
            return Err(new BasicError(ErrorKind.Unsupported,
                "McpClient: no legacy version"))
        }
        Result<Unit, Error> selected = _transport.selectProtocolVersion(context, version)
        if selected.isErr() { return Err(selected.error()) }
        JsonObject parameters = new JsonObject()
        parameters.set("protocolVersion", JsonValue.string(mcpProtocolVersionText(version)))
        parameters.set("capabilities", JsonValue.object(_clientInfo.toCapabilitiesJson()))
        parameters.set("clientInfo", JsonValue.object(_clientInfo.toIdentityJson()))
        Result<JsonObject, Error> initialized = self.callInternal(context,
            "initialize", parameters, version, null, null)
        if initialized.isErr() { return Err(initialized.error()) }
        Result<McpServerInfo, Error> server = McpServerInfo.parse(
            JsonValue.object(initialized.value()))
        if server.isErr() { return Err(server.error()) }
        JsonValue? returnedVersion = initialized.value().getOrNull("protocolVersion")
        if returnedVersion == null || !returnedVersion.isString() {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "McpClient: initialize missing protocolVersion"))
        }
        Result<McpProtocolVersion, Error> negotiated =
            parseMcpProtocolVersion(returnedVersion.asString())
        if negotiated.isErr() || !_clientInfo.supportsProtocolVersion(negotiated.value()) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "McpClient: server version unsupported"))
        }
        Result<Unit, Error> negotiatedResult =
            _transport.selectProtocolVersion(context, negotiated.value())
        if negotiatedResult.isErr() { return Err(negotiatedResult.error()) }
        JsonRpcRequest initializedNotification =
            new JsonRpcRequest("notifications/initialized")
        Result<Unit, Error> notified = _transport.notify(context, initializedNotification)
        if notified.isErr() { return Err(notified.error()) }
        String? sessionId = _transport.sessionIdentifier()
        String identifier = ""
        if sessionId != null { identifier = sessionId }
        McpSession session = new McpSession(negotiated.value(), server.value(), _clientInfo,
            identifier, false, true, true)
        _session = session
        return Ok(session)
    }

    private Result<JsonObject, Error> call(Context context, String method, JsonObject parameters,
        Result<Unit, Error>(Context, Double, Double, String) progress,
        Result<JsonObject, Error>(Context, String, JsonObject) inputHandler) {
        if context == null || method == null || parameters == null {
            throw "McpClient.call: null argument"
        }
        if !_open { return Err(unavailableError("mcp client")) }
        if _session == null { return Err(unavailableError("mcp client not initialized")) }
        return self.callInternal(context, method, parameters,
            _session.protocolVersion(), progress, inputHandler)
    }

    private Result<JsonObject, Error> callInternal(Context context, String method,
        JsonObject parameters, McpProtocolVersion version,
        Result<Unit, Error>(Context, Double, Double, String) progress,
        Result<JsonObject, Error>(Context, String, JsonObject) inputHandler) {
        JsonObject currentParameters = parameters.copy()
        Int rounds = 0
        while rounds < 8 {
            JsonRpcId identifier = self.nextIdentifier()
            JsonObject meta = new JsonObject()
            JsonValue? existingMeta = currentParameters.getOrNull("_meta")
            if existingMeta != null && existingMeta.isObject() {
                meta = existingMeta.asObject().copy()
            }
            if isModernMcpProtocolVersion(version) {
                meta.set("io.modelcontextprotocol/protocolVersion",
                    JsonValue.string(mcpProtocolVersionText(version)))
                meta.set("io.modelcontextprotocol/clientInfo",
                    JsonValue.object(_clientInfo.toIdentityJson()))
                meta.set("io.modelcontextprotocol/clientCapabilities",
                    JsonValue.object(_clientInfo.toCapabilitiesJson()))
                if _logLevel != "" {
                    meta.set("io.modelcontextprotocol/logLevel",
                        JsonValue.string(_logLevel))
                }
            }
            if progress != null {
                meta.set("progressToken", JsonValue.string(identifier.wireText()))
                _progressHandlers.put(identifier.wireText(), progress)
            }
            if meta.length() > 0 {
                currentParameters.set("_meta", JsonValue.object(meta))
            }
            JsonRpcRequest request = new JsonRpcRequest(identifier, method,
                JsonValue.object(currentParameters))
            Result<JsonRpcResponse, Error> response =
                _transport.request(context, request, self.handleNotification)
            _progressHandlers.remove(identifier.wireText())
            if response.isErr() { return Err(response.error()) }
            if response.value().error() != null {
                return Err(self.mapError(response.value().error()))
            }
            JsonValue? resultValue = response.value().result()
            if resultValue == null || !resultValue.isObject() {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "McpClient: result must be object"))
            }
            JsonObject result = resultValue.asObject()
            JsonValue? resultTypeValue = result.getOrNull("resultType")
            String resultType = "complete"
            if resultTypeValue != null {
                if !resultTypeValue.isString() {
                    return Err(new BasicError(ErrorKind.DataCorrupted,
                        "McpClient: invalid resultType"))
                }
                resultType = resultTypeValue.asString()
            }
            if resultType == "complete" { return Ok(result) }
            if resultType != "input_required" {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "McpClient: unknown resultType"))
            }
            if inputHandler == null {
                return Err(new BasicError(ErrorKind.Unsupported,
                    "McpClient: input required but no handler"))
            }
            JsonValue? requestsValue = result.getOrNull("inputRequests")
            JsonValue? stateValue = result.getOrNull("requestState")
            if requestsValue == null && stateValue == null {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "McpClient: empty input_required result"))
            }
            JsonObject responses = new JsonObject()
            if requestsValue != null {
                if !requestsValue.isObject() {
                    return Err(new BasicError(ErrorKind.DataCorrupted,
                        "McpClient: inputRequests must be object"))
                }
                JsonObject requests = requestsValue.asObject()
                List<String> keys = requests.keys()
                Int index = 0
                while index < keys.length() {
                    String key = keys.get(index)
                    JsonValue requestValue = requests.get(key)
                    if !requestValue.isObject() {
                        return Err(new BasicError(ErrorKind.DataCorrupted,
                            "McpClient: input request must be object"))
                    }
                    JsonValue? inputMethodValue = requestValue.asObject().getOrNull("method")
                    if inputMethodValue == null || !inputMethodValue.isString() {
                        return Err(new BasicError(ErrorKind.DataCorrupted,
                            "McpClient: input request missing method"))
                    }
                    String inputMethod = inputMethodValue.asString()
                    if inputMethod != "elicitation/create"
                        && inputMethod != "sampling/createMessage"
                        && inputMethod != "roots/list" {
                        return Err(new BasicError(ErrorKind.Unsupported,
                            "McpClient: unsupported input request"))
                    }
                    JsonObject inputParameters = new JsonObject()
                    JsonValue? inputParamsValue = requestValue.asObject().getOrNull("params")
                    if inputParamsValue != null {
                        if !inputParamsValue.isObject() {
                            return Err(new BasicError(ErrorKind.DataCorrupted,
                                "McpClient: input params must be object"))
                        }
                        inputParameters = inputParamsValue.asObject()
                    }
                    Result<JsonObject, Error> inputResult =
                        inputHandler(context, inputMethod, inputParameters)
                    if inputResult.isErr() {
                        return Err(inputResult.error())
                    }
                    responses.set(key, JsonValue.object(inputResult.value()))
                    index = index + 1
                }
            }
            currentParameters = parameters.copy()
            if stateValue != null { currentParameters.set("requestState", stateValue) }
            if responses.length() > 0 {
                currentParameters.set("inputResponses", JsonValue.object(responses))
            }
            rounds = rounds + 1
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "McpClient: too many input rounds"))
    }

    private Result<Unit, Error> handleNotification(Context context, JsonRpcRequest notification) {
        if notification == null { throw "McpClient.handleNotification: null" }
        if notification.method() == "notifications/message" {
            if _logHandler == null { return Ok(unit) }
            JsonValue? parametersValue = notification.parameters()
            if parametersValue == null || !parametersValue.isObject() { return Ok(unit) }
            JsonObject parameters = parametersValue.asObject()
            String level = ""
            String logger = ""
            JsonValue? levelValue = parameters.getOrNull("level")
            if levelValue != null && levelValue.isString() { level = levelValue.asString() }
            JsonValue? loggerValue = parameters.getOrNull("logger")
            if loggerValue != null && loggerValue.isString() { logger = loggerValue.asString() }
            JsonValue? data = parameters.getOrNull("data")
            if data == null { data = JsonValue.nullValue() }
            Result<Unit, Error> handled = _logHandler(context, level, logger, data)
            if handled.isErr() { _notificationFailures = _notificationFailures + 1 }
            return Ok(unit)
        }
        if notification.method() != "notifications/progress" { return Ok(unit) }
        JsonValue? parametersValue = notification.parameters()
        if parametersValue == null || !parametersValue.isObject() { return Ok(unit) }
        JsonObject parameters = parametersValue.asObject()
        JsonValue? tokenValue = parameters.getOrNull("progressToken")
        if tokenValue == null { return Ok(unit) }
        Result<JsonRpcId, Error> token = JsonRpcId.parse(tokenValue)
        if token.isErr() { return Ok(unit) }
        String key = token.value().wireText()
        if !_progressHandlers.has(key) { return Ok(unit) }
        Double current = 0.0
        Double total = -1.0
        String message = ""
        JsonValue? progressValue = parameters.getOrNull("progress")
        if progressValue != null && progressValue.isNumber() {
            Result<Double, Error> parsed = progressValue.asNumber().asDouble()
            if parsed.isOk() { current = parsed.value() }
        }
        JsonValue? totalValue = parameters.getOrNull("total")
        if totalValue != null && totalValue.isNumber() {
            Result<Double, Error> parsed = totalValue.asNumber().asDouble()
            if parsed.isOk() { total = parsed.value() }
        }
        JsonValue? messageValue = parameters.getOrNull("message")
        if messageValue != null && messageValue.isString() {
            message = messageValue.asString()
        }
        Result<Unit, Error> handled =
            _progressHandlers.get(key)(context, current, total, message)
        if handled.isErr() { _notificationFailures = _notificationFailures + 1 }
        return Ok(unit)
    }

    private Error mapError(JsonRpcError error) {
        ErrorKind kind = ErrorKind.Internal
        if error.code() == -32601 { kind = ErrorKind.Unsupported }
        if error.code() == -32602 { kind = ErrorKind.InvalidArgument }
        if error.code() == -32021 { kind = ErrorKind.PermissionDenied }
        if error.code() == -32022 { kind = ErrorKind.Unsupported }
        BasicError mapped = new BasicError(kind,
            "MCP error " + str(error.code()) + ": " + error.message())
        return mapped.withCode(str(error.code()))
    }

    Result<List<McpTool>, Error> listTools(Context context) {
        Result<JsonObject, Error> result = self.call(context, "tools/list",
            new JsonObject(), null, null)
        if result.isErr() { return Err(result.error()) }
        JsonValue? toolsValue = result.value().getOrNull("tools")
        if toolsValue == null || !toolsValue.isArray() {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "McpClient: tools must be array"))
        }
        List<McpTool> tools = []
        JsonArray array = toolsValue.asArray()
        Int index = 0
        while index < array.length() {
            Result<McpTool, Error> tool = McpTool.parse(array.get(index))
            if tool.isErr() { return Err(tool.error()) }
            tools.push(tool.value())
            _tools.put(tool.value().name(), tool.value())
            index = index + 1
        }
        return Ok(tools)
    }

    Result<McpToolResult, Error> callTool(Context context, String toolName,
        JsonObject arguments) {
        return self.callTool(context, toolName, arguments, null, null, null)
    }

    Result<McpToolResult, Error> callTool(Context context, String toolName,
        JsonObject arguments, Result<Bool, Error>(Context, McpTool, JsonObject) confirm,
        Result<Unit, Error>(Context, Double, Double, String) progress,
        Result<JsonObject, Error>(Context, String, JsonObject) inputHandler) {
        if context == null || toolName == null || arguments == null {
            throw "McpClient.callTool: null argument"
        }
        if !_allowedTools.has(toolName) {
            return Err(new BasicError(ErrorKind.PermissionDenied,
                "McpClient: tool not allowlisted"))
        }
        if _requireConfirmation && confirm == null {
            return Err(new BasicError(ErrorKind.PermissionDenied,
                "McpClient: confirmation required"))
        }
        if !_tools.has(toolName) {
            Result<List<McpTool>, Error> listed = self.listTools(context)
            if listed.isErr() { return Err(listed.error()) }
        }
        if !_tools.has(toolName) {
            return Err(new BasicError(ErrorKind.NotFound,
                "McpClient: unknown tool " + toolName))
        }
        McpTool tool = _tools.get(toolName)
        if _requireConfirmation {
            if confirm == null {
                return Err(new BasicError(ErrorKind.PermissionDenied,
                    "McpClient: confirmation required"))
            }
            Result<Bool, Error> confirmed = confirm(context, tool, arguments)
            if confirmed.isErr() { return Err(confirmed.error()) }
            if !confirmed.value() {
                return Err(new BasicError(ErrorKind.PermissionDenied,
                    "McpClient: tool call declined"))
            }
        }
        JsonObject parameters = new JsonObject()
        parameters.set("name", JsonValue.string(toolName))
        parameters.set("arguments", JsonValue.object(arguments))
        Result<JsonObject, Error> result = self.call(context, "tools/call",
            parameters, progress, inputHandler)
        if result.isErr() { return Err(result.error()) }
        return McpToolResult.parse(JsonValue.object(result.value()))
    }

    Result<List<McpResource>, Error> listResources(Context context) {
        Result<JsonObject, Error> result = self.call(context, "resources/list",
            new JsonObject(), null, null)
        if result.isErr() { return Err(result.error()) }
        JsonValue? resourcesValue = result.value().getOrNull("resources")
        if resourcesValue == null || !resourcesValue.isArray() {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "McpClient: resources must be array"))
        }
        List<McpResource> resources = []
        JsonArray array = resourcesValue.asArray()
        Int index = 0
        while index < array.length() {
            Result<McpResource, Error> resource = McpResource.parse(array.get(index))
            if resource.isErr() { return Err(resource.error()) }
            resources.push(resource.value())
            index = index + 1
        }
        return Ok(resources)
    }

    Result<List<McpContent>, Error> readResource(Context context, String resourceUri) {
        return self.readResource(context, resourceUri, null)
    }

    Result<List<McpContent>, Error> readResource(Context context, String resourceUri,
        Result<JsonObject, Error>(Context, String, JsonObject) inputHandler) {
        if context == null || resourceUri == null {
            throw "McpClient.readResource: null argument"
        }
        JsonObject parameters = new JsonObject()
        parameters.set("uri", JsonValue.string(resourceUri))
        Result<JsonObject, Error> result = self.call(context, "resources/read",
            parameters, null, inputHandler)
        if result.isErr() { return Err(result.error()) }
        JsonValue? contentsValue = result.value().getOrNull("contents")
        if contentsValue == null || !contentsValue.isArray() {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "McpClient: contents must be array"))
        }
        List<McpContent> contents = []
        JsonArray array = contentsValue.asArray()
        Int index = 0
        while index < array.length() {
            Result<McpContent, Error> content = McpContent.parse(array.get(index))
            if content.isErr() { return Err(content.error()) }
            contents.push(content.value())
            index = index + 1
        }
        return Ok(contents)
    }

    Result<List<McpPrompt>, Error> listPrompts(Context context) {
        Result<JsonObject, Error> result = self.call(context, "prompts/list",
            new JsonObject(), null, null)
        if result.isErr() { return Err(result.error()) }
        JsonValue? promptsValue = result.value().getOrNull("prompts")
        if promptsValue == null || !promptsValue.isArray() {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "McpClient: prompts must be array"))
        }
        List<McpPrompt> prompts = []
        JsonArray array = promptsValue.asArray()
        Int index = 0
        while index < array.length() {
            Result<McpPrompt, Error> prompt = McpPrompt.parse(array.get(index))
            if prompt.isErr() { return Err(prompt.error()) }
            prompts.push(prompt.value())
            index = index + 1
        }
        return Ok(prompts)
    }

    Result<McpPrompt, Error> getPrompt(Context context, String promptName,
        JsonObject arguments, Result<JsonObject, Error>(Context, String, JsonObject) inputHandler) {
        if context == null || promptName == null || arguments == null {
            throw "McpClient.getPrompt: null argument"
        }
        JsonObject parameters = new JsonObject()
        parameters.set("name", JsonValue.string(promptName))
        parameters.set("arguments", JsonValue.object(arguments))
        Result<JsonObject, Error> result = self.call(context, "prompts/get",
            parameters, null, inputHandler)
        if result.isErr() { return Err(result.error()) }
        JsonObject withName = result.value().copy()
        if !withName.has("name") {
            withName.set("name", JsonValue.string(promptName))
        }
        return McpPrompt.parse(JsonValue.object(withName))
    }

    Result<Unit, Error> cancel(Context context, JsonRpcId requestIdentifier, String reason) {
        if context == null || requestIdentifier == null {
            throw "McpClient.cancel: null argument"
        }
        if !_open { return Err(unavailableError("mcp client")) }
        return _transport.cancel(context, requestIdentifier, reason)
    }

    Result<Unit, Error> setLogLevel(String level) {
        if level == null { throw "McpClient.setLogLevel: null" }
        if level != "debug" && level != "info" && level != "notice"
            && level != "warning" && level != "error" && level != "critical"
            && level != "alert" && level != "emergency" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpClient.setLogLevel: invalid level"))
        }
        _logLevel = level
        return Ok(unit)
    }

    String logLevel() { return _logLevel }

    Result<Unit, Error> setLogHandler(
        Result<Unit, Error>(Context, String, String, JsonValue) handler) {
        if handler == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpClient.setLogHandler: null"))
        }
        _logHandler = handler
        return Ok(unit)
    }

    Unit clearLogHandler() {
        _logHandler = null
        return unit
    }

    Result<Unit, Error> allowTool(String name) {
        if name == null || name == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpClient.allowTool: empty"))
        }
        _allowedTools.add(name)
        return Ok(unit)
    }

    Bool denyTool(String name) {
        if name == null { throw "McpClient.denyTool: null" }
        return _allowedTools.remove(name)
    }

    Set<String> allowedTools() { return _allowedTools.copy() }
    Bool requireConfirmation() { return _requireConfirmation }
    McpSession? session() { return _session }
    Bool isInitialized() { return _session != null }
    McpProtocolVersion? protocolVersion() {
        if _session == null { return null }
        return _session.protocolVersion()
    }
    McpServerInfo? serverInfo() {
        if _session == null { return null }
        return _session.serverInfo()
    }
    Int notificationFailureCount() { return _notificationFailures }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        _session = null
        _tools.clear()
        _progressHandlers.clear()
        _logHandler = null
        return _transport.close()
    }
}
```
