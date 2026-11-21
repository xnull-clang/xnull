# `McpHttpTransport`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpHttpTransport implements McpTransport` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `HttpClient`、`HttpServer`、`HttpExchange`、`HttpRequest`、`HttpResponse`、`HttpBody`、`ByteStream`、`Uri`、`Base64`、`McpProtocolVersion` |

---

## 1. 定位

Streamable HTTP 传输：客户端角色用一个 MCP endpoint 发 POST；服务端角色包装一次 `HttpExchange`，读取请求并写 JSON 或 SSE 响应。

不做：HTTP/3、HTTP+SSE（2024-11-05）、GET 独立流、`Last-Event-ID` 续传、OAuth 授权服务器、反向代理、连接池。

---

## 2. 设计逻辑

- 一次 HTTP POST 只承载一个 JSON-RPC 请求或通知；客户端不得发送 JSON-RPC 响应。
- 客户端：`request` POST，接受 `application/json` 或 `text/event-stream`；通知 POST 期望 202。
- 服务端：一个 `McpHttpTransport` 只包装一个 exchange；`receive` 读一次请求，`respond` 写一次响应，`acknowledge` 写 202。
- modern 请求带 `MCP-Protocol-Version`、`Mcp-Method`、可选 `Mcp-Name`；头与 body 必须一致，否则 -32020。
- legacy 2025 可使用 `MCP-Session-Id`；modern 不发送、不生成、不持久化 session id。
- SSE 只在单个请求的响应流内；通知（progress/message）先于最终响应；不做跨请求 GET 流。
- Origin 校验在服务端角色执行；认证由应用/`HttpServer` 中间件完成，本类型不签发/不验证令牌。
- 大小限制：请求 body、响应 body、SSE 事件都使用 `Long maximumBodyBytes`；超时由调用方 `Context` 或 `HttpClientOptions` 提供。
- 不自动重试；断流即失败；调用方用新 id 重发。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_client` | `HttpClient?` | final | 客户端角色 |
| `_endpoint` | `Uri?` | final | 客户端 MCP endpoint |
| `_exchange` | `HttpExchange?` | final | 服务端角色 |
| `_protocolVersion` | `McpProtocolVersion?` | 可变 | 客户端使用版本；协商后可更新 |
| `_supportedVersions` | `List<McpProtocolVersion>` | final | 服务端接受版本 |
| `_authorizationHeader` | `String` | final | 客户端 Authorization；空=无 |
| `_allowedOrigins` | `Set<String>` | final | 服务端允许 Origin；空=只允许无 Origin |
| `_maximumBodyBytes` | `Long` | final | >0 |
| `_open` | `Bool` | 可变 | 是否可用 |
| `_activeStreams` | `Map<String, ByteStream>` | final | 客户端进行中的 SSE |
| `_cancelled` | `Set<String>` | final | 服务端已取消 id |
| `_sessionIdentifier` | `String` | 可变 | legacy HTTP session id；无则空 |
| `_received` | `Bool` | 可变 | 服务端已读请求 |
| `_responded` | `Bool` | 可变 | 服务端已写响应 |
| `_pendingNotifications` | `List<JsonValue>` | final | 服务端待发通知（progress/log） |
| `_notificationFailures` | `Int` | 可变 | 回调失败计数 |

不变量：客户端角色 client/endpoint 非空；服务端角色 exchange 非空；max>0；服务端每个 exchange 最多 `receive` 一次、`respond`/`acknowledge` 一次；modern 不写 session id；关闭后 open=false。

---

## 4. 生命周期

构造后可用；必须 close；close 幂等；客户端 close 关闭活动 SSE，不关闭借用的 `HttpClient`；服务端 close 关闭 exchange；关闭后所有方法 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpHttpTransport(HttpClient client, Uri endpoint)` | client/endpoint | 非 null | null → panic |
| `McpHttpTransport(HttpClient client, Uri endpoint, McpProtocolVersion protocolVersion, String authorizationHeader, Long maximumBodyBytes)` | 五参数 | 非 null；max>0；header 无 CR/LF | 非法 → panic |
| `McpHttpTransport(HttpExchange exchange, Set<String> allowedOrigins)` | exchange/origins | exchange 非 null；origins 非 null | null → panic |
| `McpHttpTransport(HttpExchange exchange, Set<String> allowedOrigins, List<McpProtocolVersion> supportedVersions, Long maximumBodyBytes)` | 四参数 | exchange/origins/versions 非空；max>0 | 非法 → panic |

客户端默认使用 `latestMcpProtocolVersion()`；服务端默认只接受 latest。`authorizationHeader` 由应用提供，必须是完整头值（如 `Bearer ...`），本类型不解析、不刷新、不记录。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `request` | 客户端 POST 请求 | `Context context, JsonRpcRequest request, Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler` | `Result<JsonRpcResponse, Error>` | `InvalidArgument`/`Network`/`Timeout`/`Cancelled`/`DataCorrupted`/`PermissionDenied`/`Unavailable` |
| `selectProtocolVersion` | 更新协议版本 | `Context context, McpProtocolVersion version` | `Result<Unit, Error>` | `Unsupported`/`Unavailable` |
| `notify` | 客户端 POST 通知；服务端缓存到当前 exchange | `Context context, JsonRpcRequest notification` | `Result<Unit, Error>` | `InvalidArgument`/`Network`/`Timeout`/`Cancelled`/`PermissionDenied`/`Unavailable` |
| `receive` | 服务端读请求 | `Context context` | `Result<JsonRpcRequest, Error>` | `InvalidArgument`/`PermissionDenied`/`DataCorrupted`/`Unavailable` |
| `respond` | 服务端写响应 | `Context context, JsonRpcResponse response` | `Result<Unit, Error>` | `InvalidArgument`/`Io`/`Unavailable` |
| `acknowledge` | 服务端 202 | `Context context` | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `cancel` | 取消 | `Context context, JsonRpcId identifier, String reason` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable` |
| `sessionIdentifier` | legacy 会话 id | 无 | `String?` | 无 |
| `isCancelled` | 服务端查询取消 | `JsonRpcId identifier` | `Bool` | null → panic |
| `notificationFailureCount` | 回调失败数 | 无 | `Int` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `request`：客户端角色；校验 request 带 id；POST 后按响应 Content-Type 解析 JSON 或 SSE；SSE 中的通知交给回调，最终响应按 id 匹配。
- `selectProtocolVersion`：客户端更新后续请求的 `MCP-Protocol-Version`；服务端校验版本在支持列表；stdio 不适用。
- `notify`：客户端角色；POST 通知；202/200/204 视为成功；其他 2xx 也接受。服务端角色把通知缓存到当前 exchange，`respond` 时以 SSE 事件先于最终响应写出。
- `receive`：服务端角色；校验 Origin、协议版本头、`Mcp-Method`/`Mcp-Name` 与 body 一致；失败写 400/403 并返回 `InvalidArgument`/`PermissionDenied`。
- `respond`：服务端角色；无缓存通知时写 `application/json`；有 progress/log 时写 `text/event-stream`，最后一条为 JSON-RPC 响应。
- `acknowledge`：服务端角色；`HttpExchange.respondStatus(202)`。
- `cancel`：客户端关闭对应 SSE；服务端把 id 放入取消集合；未知 id 幂等。
- `sessionIdentifier`：legacy 客户端从响应头 `MCP-Session-Id` 保存；modern 恒 null；服务端从请求头读取。
- `close`：客户端关闭活动 SSE；服务端关闭 exchange；不关闭借用的 client。

---

## 8. 使用的技术

- HTTP POST；
- SSE 事件解析；
- Base64 头值；
- Origin 校验；
- 头/body 一致性校验；
- 有界 body/事件读取。

---

## 9. 需要的支撑

- 语言：class、String、Long、Int、Bool、Result；
- 运行时：`sseReadDataRaw(ByteStream, Long, Context)`（读下一个 `data` 载荷；EOF null；超限 `DataCorrupted`）；`Base64.encode/decode`；`toUtf8/fromUtf8`；
- 接口：`HttpClient`、`HttpServer`、`HttpExchange`、`HttpRequest`、`HttpResponse`、`HttpBody`、`ByteStream`、`Uri`、`Json`、`Context`、`McpProtocolVersion`、`JsonRpcRequest`、`JsonRpcResponse`、`Error`。

---

## 10. 依赖的特性/接口/类

`HttpClient`、`HttpExchange`、`HttpRequest`、`HttpResponse`、`HttpBody`、`HttpHeaders`、`HttpMethod`、`ByteStream`、`Uri`、`Json`、`JsonObject`、`JsonValue`、`JsonArray`、`Base64`、`JsonRpcRequest`、`JsonRpcResponse`、`JsonRpcError`、`McpProtocolVersion`、`Error`。

---

## 11. 所有权与并发

- 客户端借用 `HttpClient`；不关闭它；活动 SSE 由本类型关闭。
- 服务端拥有 exchange 的使用权；close 调用 `exchange.close()`。
- `request` 可并发；每个请求独立 POST/SSE；`_activeStreams` 用 id 作键。
- `receive`/`respond`/`acknowledge` 单 exchange 单次；不得重复。
- `close` 可并发；关闭后 `Unavailable`。
- 通知回调在请求任务上调用；不得重入 `request`。

---

## 12. 示例与反例

正确：`new McpHttpTransport(client, uri, latestMcpProtocolVersion(), "Bearer ...", 16777216L)`；服务端 `new McpHttpTransport(exchange, allowedOrigins, [latest], 16777216L)`。  
反例：modern 发送 `MCP-Session-Id`；GET 开独立 SSE；头 `Mcp-Name` 与 body 不一致；把 401 当 JSON-RPC 错误；在日志打印 Authorization；SSE 断流后自动续传。

---

## 13. 测试/场景义务

JSON 响应；SSE 通知+响应；202 通知；Origin 允许/拒绝；缺协议头；未知版本；`Mcp-Method`/`Mcp-Name` 不一致；Base64 头值；401/403/404/500；断流；取消；legacy session id；modern 不写 session；大 body/事件；close 幂等；回调失败计数。

---

## 14. XNull 伪代码

```xnull
class McpHttpTransport implements McpTransport {
    final HttpClient? _client
    final Uri? _endpoint
    final HttpExchange? _exchange
    McpProtocolVersion? _protocolVersion
    final List<McpProtocolVersion> _supportedVersions
    final String _authorizationHeader
    final Set<String> _allowedOrigins
    final Long _maximumBodyBytes
    Bool _open
    final Map<String, ByteStream> _activeStreams
    final Set<String> _cancelled
    String _sessionIdentifier
    Bool _received
    Bool _responded
    final List<JsonValue> _pendingNotifications
    Int _notificationFailures

    McpHttpTransport(HttpClient client, Uri endpoint) {
        if client == null || endpoint == null {
            throw "McpHttpTransport: null client/endpoint"
        }
        _client = client
        _endpoint = endpoint
        _exchange = null
        _protocolVersion = latestMcpProtocolVersion()
        _supportedVersions = []
        _authorizationHeader = ""
        _allowedOrigins = new Set<String>()
        _maximumBodyBytes = 16777216L
        _open = true
        _activeStreams = new Map<String, ByteStream>()
        _cancelled = new Set<String>()
        _sessionIdentifier = ""
        _received = false
        _responded = false
        _pendingNotifications = []
        _notificationFailures = 0
    }

    McpHttpTransport(HttpClient client, Uri endpoint, McpProtocolVersion protocolVersion,
                     String authorizationHeader, Long maximumBodyBytes) {
        if client == null || endpoint == null || protocolVersion == null {
            throw "McpHttpTransport: null argument"
        }
        if maximumBodyBytes <= 0 { throw "McpHttpTransport: invalid maximum" }
        if authorizationHeader.contains("\n") || authorizationHeader.contains("\r") {
            throw "McpHttpTransport: invalid authorization header"
        }
        _client = client
        _endpoint = endpoint
        _exchange = null
        _protocolVersion = protocolVersion
        _supportedVersions = []
        _authorizationHeader = authorizationHeader
        _allowedOrigins = new Set<String>()
        _maximumBodyBytes = maximumBodyBytes
        _open = true
        _activeStreams = new Map<String, ByteStream>()
        _cancelled = new Set<String>()
        _sessionIdentifier = ""
        _received = false
        _responded = false
        _pendingNotifications = []
        _notificationFailures = 0
    }

    McpHttpTransport(HttpExchange exchange, Set<String> allowedOrigins) {
        if exchange == null || allowedOrigins == null {
            throw "McpHttpTransport: null exchange/origins"
        }
        _client = null
        _endpoint = null
        _exchange = exchange
        _protocolVersion = null
        _supportedVersions = [latestMcpProtocolVersion()]
        _authorizationHeader = ""
        _allowedOrigins = allowedOrigins.copy()
        _maximumBodyBytes = 16777216L
        _open = true
        _activeStreams = new Map<String, ByteStream>()
        _cancelled = new Set<String>()
        _sessionIdentifier = ""
        _received = false
        _responded = false
        _pendingNotifications = []
        _notificationFailures = 0
    }

    McpHttpTransport(HttpExchange exchange, Set<String> allowedOrigins,
                     List<McpProtocolVersion> supportedVersions, Long maximumBodyBytes) {
        if exchange == null || allowedOrigins == null || supportedVersions == null {
            throw "McpHttpTransport: null argument"
        }
        if supportedVersions.length() == 0 || maximumBodyBytes <= 0 {
            throw "McpHttpTransport: invalid server configuration"
        }
        _client = null
        _endpoint = null
        _exchange = exchange
        _protocolVersion = null
        _supportedVersions = supportedVersions.copy()
        _authorizationHeader = ""
        _allowedOrigins = allowedOrigins.copy()
        _maximumBodyBytes = maximumBodyBytes
        _open = true
        _activeStreams = new Map<String, ByteStream>()
        _cancelled = new Set<String>()
        _sessionIdentifier = ""
        _received = false
        _responded = false
        _pendingNotifications = []
        _notificationFailures = 0
    }

    static Bool isSafeHeaderValue(String value) {
        if value == null || value == "" { return false }
        if value.startsWith("=?base64?") { return false }
        if value.startsWith(" ") || value.endsWith(" ") { return false }
        Int index = 0
        while index < value.length() {
            Int codePoint = value.codePointAt(index)
            if codePoint < 32 || codePoint > 126 { return false }
            index = index + 1
        }
        return true
    }

    static String encodeHeaderValue(String value) {
        if isSafeHeaderValue(value) { return value }
        return "=?base64?" + Base64.encode(fromUtf8(value)) + "?="
    }

    static Result<String, Error> decodeHeaderValue(String value) {
        if value == null { throw "decodeHeaderValue: null" }
        if !value.startsWith("=?base64?") || !value.endsWith("?=") {
            return Ok(value)
        }
        String encoded = value.substring(9, value.length() - 2)
        Result<Bytes, Error> decoded = Base64.decode(encoded)
        if decoded.isErr() { return Err(decoded.error()) }
        return Ok(toUtf8(decoded.value()))
    }

    static String mcpNameFor(JsonRpcRequest request) {
        JsonValue? parametersValue = request.parameters()
        if parametersValue == null || !parametersValue.isObject() { return "" }
        JsonObject parameters = parametersValue.asObject()
        if request.method() == "tools/call" || request.method() == "prompts/get" {
            JsonValue? nameValue = parameters.getOrNull("name")
            if nameValue != null && nameValue.isString() { return nameValue.asString() }
            return ""
        }
        if request.method() == "resources/read" {
            JsonValue? uriValue = parameters.getOrNull("uri")
            if uriValue != null && uriValue.isString() { return uriValue.asString() }
            return ""
        }
        return ""
    }

    Result<Unit, Error> selectProtocolVersion(Context context, McpProtocolVersion version) {
        if context == null || version == null {
            throw "McpHttpTransport.selectProtocolVersion: null argument"
        }
        if !_open { return Err(unavailableError("http transport")) }
        if _client != null {
            _protocolVersion = version
            return Ok(unit)
        }
        if _exchange != null {
            if !_supportedVersions.contains(version) {
                return Err(new BasicError(ErrorKind.Unsupported,
                    "McpHttpTransport: unsupported protocol version"))
            }
            return Ok(unit)
        }
        return Err(unavailableError("http transport"))
    }

    Result<JsonRpcResponse, Error> request(Context context, JsonRpcRequest request,
        Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler) {
        if context == null { throw "McpHttpTransport.request: null context" }
        if request == null || notificationHandler == null {
            throw "McpHttpTransport.request: null argument"
        }
        if request.isNotification() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpHttpTransport.request: notification"))
        }
        if _client == null || _endpoint == null {
            return Err(new BasicError(ErrorKind.Unsupported,
                "McpHttpTransport.request: not a client transport"))
        }
        if !_open { return Err(unavailableError("http transport")) }
        HttpRequest httpRequest = new HttpRequest(HttpMethod.Post, _endpoint)
        httpRequest = httpRequest.withHeader("Accept", "application/json, text/event-stream")
        httpRequest = httpRequest.withHeader("Content-Type", "application/json")
        httpRequest = httpRequest.withHeader("MCP-Protocol-Version",
            mcpProtocolVersionText(_protocolVersion))
        if isModernMcpProtocolVersion(_protocolVersion) {
            httpRequest = httpRequest.withHeader("Mcp-Method", request.method())
            String mcpName = mcpNameFor(request)
            if mcpName != "" {
                httpRequest = httpRequest.withHeader("Mcp-Name", encodeHeaderValue(mcpName))
            }
        } else if _sessionIdentifier != "" {
            httpRequest = httpRequest.withHeader("MCP-Session-Id", _sessionIdentifier)
        }
        if _authorizationHeader != "" {
            httpRequest = httpRequest.withHeader("Authorization", _authorizationHeader)
        }
        httpRequest = httpRequest.withBody(HttpBody.fromText(Json.stringify(request.toJsonValue())))
        Result<HttpResponse, Error> sent = _client.request(context, httpRequest)
        if sent.isErr() { return Err(sent.error()) }
        HttpResponse response = sent.value()
        String? sessionId = response.headers().getOrNull("MCP-Session-Id")
        if sessionId != null && !isModernMcpProtocolVersion(_protocolVersion) {
            _sessionIdentifier = sessionId
        }
        if response.isSuccess() {
            String? contentType = response.headers().getOrNull("Content-Type")
            if contentType != null && contentType.contains("text/event-stream") {
                return self.readSseResponse(context, request, response, notificationHandler)
            }
            Result<String, Error> body = response.body().readText(context, _maximumBodyBytes)
            if body.isErr() { return Err(body.error()) }
            Result<JsonValue, Error> parsed = Json.parse(body.value())
            if parsed.isErr() { return Err(parsed.error()) }
            Result<JsonRpcResponse, Error> rpcResponse = JsonRpcResponse.parse(parsed.value())
            if rpcResponse.isErr() { return Err(rpcResponse.error()) }
            if rpcResponse.value().identifier() == null
                || !rpcResponse.value().identifier().equals(request.identifier()) {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "McpHttpTransport: response id mismatch"))
            }
            return rpcResponse
        }
        Result<String, Error> errorBody = response.body().readText(context, _maximumBodyBytes)
        if errorBody.isOk() && errorBody.value() != "" {
            Result<JsonValue, Error> parsedError = Json.parse(errorBody.value())
            if parsedError.isOk() && parsedError.value().isObject() {
                Result<JsonRpcResponse, Error> rpcError =
                    JsonRpcResponse.parse(parsedError.value())
                if rpcError.isOk() { return rpcError }
            }
        }
        if response.status().code() == 401 || response.status().code() == 403 {
            return Err(new BasicError(ErrorKind.PermissionDenied,
                "McpHttpTransport: authorization failed"))
        }
        if response.status().code() == 404 {
            return Err(new BasicError(ErrorKind.NotFound,
                "McpHttpTransport: endpoint not found"))
        }
        return Err(new BasicError(ErrorKind.Network,
            "McpHttpTransport: HTTP status " + str(response.status().code())))
    }

    Result<JsonRpcResponse, Error> readSseResponse(Context context, JsonRpcRequest request,
        HttpResponse response, Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler) {
        ByteStream stream = response.body().stream()
        if stream == null {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "McpHttpTransport: missing SSE stream"))
        }
        String key = request.identifier().wireText()
        _activeStreams.put(key, stream)
        while true {
            Result<String?, Error> data = sseReadDataRaw(stream, _maximumBodyBytes, context)
            if data.isErr() {
                _activeStreams.remove(key)
                stream.close()
                return Err(data.error())
            }
            if data.value() == null {
                _activeStreams.remove(key)
                stream.close()
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "McpHttpTransport: SSE ended without response"))
            }
            Result<JsonValue, Error> parsed = Json.parse(data.value())
            if parsed.isErr() {
                _activeStreams.remove(key)
                stream.close()
                return Err(parsed.error())
            }
            if !parsed.value().isObject() {
                _activeStreams.remove(key)
                stream.close()
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "McpHttpTransport: non-object SSE message"))
            }
            JsonObject object = parsed.value().asObject()
            if object.has("method") {
                Result<JsonRpcRequest, Error> notification =
                    JsonRpcRequest.parse(parsed.value())
                if notification.isErr() {
                    _activeStreams.remove(key)
                    stream.close()
                    return Err(notification.error())
                }
                Result<Unit, Error> handled =
                    notificationHandler(context, notification.value())
                if handled.isErr() { _notificationFailures = _notificationFailures + 1 }
                continue
            }
            Result<JsonRpcResponse, Error> rpcResponse =
                JsonRpcResponse.parse(parsed.value())
            _activeStreams.remove(key)
            stream.close()
            if rpcResponse.isErr() { return Err(rpcResponse.error()) }
            if rpcResponse.value().identifier() == null
                || !rpcResponse.value().identifier().equals(request.identifier()) {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "McpHttpTransport: SSE response id mismatch"))
            }
            return rpcResponse
        }
    }

    Result<Unit, Error> notify(Context context, JsonRpcRequest notification) {
        if context == null { throw "McpHttpTransport.notify: null context" }
        if notification == null { throw "McpHttpTransport.notify: null" }
        if !notification.isNotification() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpHttpTransport.notify: request with id"))
        }
        if _client == null {
            if _exchange == null {
                return Err(new BasicError(ErrorKind.Unsupported,
                    "McpHttpTransport.notify: not a transport"))
            }
            if !_open { return Err(unavailableError("http transport")) }
            if _responded {
                return Err(new BasicError(ErrorKind.Unavailable,
                    "McpHttpTransport.notify: response already sent"))
            }
            _pendingNotifications.push(notification.toJsonValue())
            return Ok(unit)
        }
        if _endpoint == null {
            return Err(new BasicError(ErrorKind.Unsupported,
                "McpHttpTransport.notify: missing endpoint"))
        }
        if !_open { return Err(unavailableError("http transport")) }
        HttpRequest httpRequest = new HttpRequest(HttpMethod.Post, _endpoint)
        httpRequest = httpRequest.withHeader("Accept", "application/json, text/event-stream")
        httpRequest = httpRequest.withHeader("Content-Type", "application/json")
        httpRequest = httpRequest.withHeader("MCP-Protocol-Version",
            mcpProtocolVersionText(_protocolVersion))
        if !isModernMcpProtocolVersion(_protocolVersion) && _sessionIdentifier != "" {
            httpRequest = httpRequest.withHeader("MCP-Session-Id", _sessionIdentifier)
        }
        if _authorizationHeader != "" {
            httpRequest = httpRequest.withHeader("Authorization", _authorizationHeader)
        }
        httpRequest = httpRequest.withBody(HttpBody.fromText(
            Json.stringify(notification.toJsonValue())))
        Result<HttpResponse, Error> sent = _client.request(context, httpRequest)
        if sent.isErr() { return Err(sent.error()) }
        Int status = sent.value().status().code()
        if status == 202 || status == 200 || status == 204 { return Ok(unit) }
        if status == 401 || status == 403 {
            return Err(new BasicError(ErrorKind.PermissionDenied,
                "McpHttpTransport: authorization failed"))
        }
        return Err(new BasicError(ErrorKind.Network,
            "McpHttpTransport: notification rejected " + str(status)))
    }

    Result<JsonRpcRequest, Error> receive(Context context) {
        if context == null { throw "McpHttpTransport.receive: null context" }
        if _exchange == null {
            return Err(new BasicError(ErrorKind.Unsupported,
                "McpHttpTransport.receive: not a server transport"))
        }
        if !_open { return Err(unavailableError("http transport")) }
        if _received {
            return Err(unavailableError("http exchange already consumed"))
        }
        _received = true
        _pendingNotifications.clear()
        HttpRequest incoming = _exchange.request()
        String? incomingSession = incoming.headers().getOrNull("MCP-Session-Id")
        if incomingSession != null { _sessionIdentifier = incomingSession }
        String? origin = incoming.headers().getOrNull("Origin")
        if origin != null && !_allowedOrigins.has(origin) {
            self.respondError(context, null, new JsonRpcError(-32600, "Origin denied"), 403)
            return Err(new BasicError(ErrorKind.PermissionDenied,
                "McpHttpTransport: origin denied"))
        }
        Result<String, Error> body = incoming.body().readText(context, _maximumBodyBytes)
        if body.isErr() { return Err(body.error()) }
        Result<JsonValue, Error> parsed = Json.parse(body.value())
        if parsed.isErr() {
            self.respondError(context, null,
                JsonRpcError.parseError("invalid JSON"), 400)
            return Err(parsed.error())
        }
        if !parsed.value().isObject() {
            self.respondError(context, null,
                JsonRpcError.invalidRequest("non-object"), 400)
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "McpHttpTransport: non-object request"))
        }
        Result<JsonRpcRequest, Error> request = JsonRpcRequest.parse(parsed.value())
        if request.isErr() {
            self.respondError(context, null,
                JsonRpcError.invalidRequest("invalid request"), 400)
            return Err(request.error())
        }
        String? protocolHeader = incoming.headers().getOrNull("MCP-Protocol-Version")
        Result<Unit, Error> valid = self.validateIncoming(context, request.value(),
            protocolHeader, incoming.headers())
        if valid.isErr() { return Err(valid.error()) }
        return request
    }

    Result<Unit, Error> validateIncoming(Context context, JsonRpcRequest request,
        String? protocolHeader, HttpHeaders headers) {
        String? protocolText = protocolHeader
        if protocolText == null {
            JsonValue? metaValue = request.parameters()
            if metaValue != null && metaValue.isObject() {
                JsonValue? metaProtocol = metaValue.asObject().getOrNull("_meta")
                if metaProtocol != null && metaProtocol.isObject() {
                    JsonValue? value = metaProtocol.asObject().getOrNull(
                        "io.modelcontextprotocol/protocolVersion")
                    if value != null && value.isString() { protocolText = value.asString() }
                }
            }
        }
        if protocolText == null {
            self.respondError(context, request.identifier(),
                new JsonRpcError(-32020, "Missing MCP-Protocol-Version"), 400)
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpHttpTransport: missing protocol version"))
        }
        Result<McpProtocolVersion, Error> version = parseMcpProtocolVersion(protocolText)
        if version.isErr() || !_supportedVersions.contains(version.value()) {
            self.respondError(context, request.identifier(),
                new JsonRpcError(-32022, "Unsupported protocol version"), 400)
            return Err(new BasicError(ErrorKind.Unsupported,
                "McpHttpTransport: unsupported protocol version"))
        }
        if isModernMcpProtocolVersion(version.value()) {
            String? methodHeader = headers.getOrNull("Mcp-Method")
            if methodHeader == null || methodHeader != request.method() {
                self.respondError(context, request.identifier(),
                    new JsonRpcError(-32020, "Mcp-Method mismatch"), 400)
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpHttpTransport: method header mismatch"))
            }
            String expectedName = mcpNameFor(request)
            String? nameHeader = headers.getOrNull("Mcp-Name")
            if expectedName != "" {
                if nameHeader == null {
                    self.respondError(context, request.identifier(),
                        new JsonRpcError(-32020, "Missing Mcp-Name"), 400)
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpHttpTransport: missing name header"))
                }
                Result<String, Error> decoded = decodeHeaderValue(nameHeader)
                if decoded.isErr() || decoded.value() != expectedName {
                    self.respondError(context, request.identifier(),
                        new JsonRpcError(-32020, "Mcp-Name mismatch"), 400)
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpHttpTransport: name header mismatch"))
                }
            }
        }
        return Ok(unit)
    }

    Result<Unit, Error> respond(Context context, JsonRpcResponse response) {
        if context == null { throw "McpHttpTransport.respond: null context" }
        if response == null { throw "McpHttpTransport.respond: null" }
        if _exchange == null {
            return Err(new BasicError(ErrorKind.Unsupported,
                "McpHttpTransport.respond: not a server transport"))
        }
        if !_open { return Err(unavailableError("http transport")) }
        if _responded {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpHttpTransport.respond: already responded"))
        }
        _responded = true
        if _pendingNotifications.length() > 0 {
            String body = ""
            Int index = 0
            while index < _pendingNotifications.length() {
                body = body + "data: " + Json.stringify(_pendingNotifications.get(index)) + "\n\n"
                index = index + 1
            }
            body = body + "data: " + Json.stringify(response.toJsonValue()) + "\n\n"
            HttpResponse sseResponse = HttpResponse.of(200)
                .withHeader("Content-Type", "text/event-stream")
                .withHeader("X-Accel-Buffering", "no")
                .withBody(HttpBody.fromText(body))
            _pendingNotifications.clear()
            return _exchange.respond(sseResponse)
        }
        HttpResponse httpResponse = HttpResponse.of(200)
            .withHeader("Content-Type", "application/json")
            .withBody(HttpBody.fromText(Json.stringify(response.toJsonValue())))
        return _exchange.respond(httpResponse)
    }

    Result<Unit, Error> acknowledge(Context context) {
        if context == null { throw "McpHttpTransport.acknowledge: null context" }
        if _exchange == null {
            return Err(new BasicError(ErrorKind.Unsupported,
                "McpHttpTransport.acknowledge: not a server transport"))
        }
        if !_open { return Err(unavailableError("http transport")) }
        if _responded {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpHttpTransport.acknowledge: already responded"))
        }
        _responded = true
        _pendingNotifications.clear()
        return _exchange.respondStatus(202)
    }

    Result<Unit, Error> respondError(Context context, JsonRpcId? identifier,
        JsonRpcError error, Int status) {
        if _exchange == null { return Ok(unit) }
        if _responded { return Ok(unit) }
        _responded = true
        _pendingNotifications.clear()
        JsonRpcResponse response = JsonRpcResponse.failure(identifier, error)
        HttpResponse httpResponse = HttpResponse.of(status)
            .withHeader("Content-Type", "application/json")
            .withBody(HttpBody.fromText(Json.stringify(response.toJsonValue())))
        return _exchange.respond(httpResponse)
    }

    Result<Unit, Error> cancel(Context context, JsonRpcId identifier, String reason) {
        if context == null { throw "McpHttpTransport.cancel: null context" }
        if identifier == null { throw "McpHttpTransport.cancel: null identifier" }
        if !_open { return Err(unavailableError("http transport")) }
        String key = identifier.wireText()
        if _exchange == null {
            if _activeStreams.has(key) {
                ByteStream stream = _activeStreams.get(key)
                _activeStreams.remove(key)
                stream.close()
            }
            return Ok(unit)
        }
        _cancelled.add(key)
        return Ok(unit)
    }

    String? sessionIdentifier() {
        if _sessionIdentifier == "" { return null }
        return _sessionIdentifier
    }

    Bool isCancelled(JsonRpcId identifier) {
        if identifier == null { throw "McpHttpTransport.isCancelled: null" }
        return _cancelled.has(identifier.wireText())
    }

    Int notificationFailureCount() { return _notificationFailures }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        List<String> keys = _activeStreams.keys()
        Int index = 0
        while index < keys.length() {
            ByteStream stream = _activeStreams.get(keys.get(index))
            stream.close()
            index = index + 1
        }
        _activeStreams.clear()
        _pendingNotifications.clear()
        if _exchange != null { return _exchange.close() }
        return Ok(unit)
    }
}
```
