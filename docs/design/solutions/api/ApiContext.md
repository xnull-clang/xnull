# `ApiContext`

| 项 | 值 |
| --- | --- |
| 类型 | `class ApiContext` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`HttpExchange`、`HttpRequest`、`HttpResponse`、`HttpHeaders`、`HttpBody`、`HttpMethod`、`Uri`、`Query`、`MediaType`、`Bytes`、`JsonValue`、`Validator`、`ValidationResult`、`ProblemDetails`、`SseStream`、`ApiOptions`、`ApiRoute`、`Error` |

---

## 1. 定位

单次 API 请求的上下文：读取方法/路径/头/查询/路径参数/body，保存认证身份与属性，执行校验与内容协商，生成 JSON/文本/字节/空/ProblemDetails 响应，或打开 SSE。

不做：路由匹配、认证验证、限流计数、CORS 判定、HTTP 连接管理、模板渲染、对象映射。

---

## 2. 设计逻辑

- 每个 `HttpExchange` 一个 `ApiContext`；不跨请求复用。
- 请求读取委托 `HttpRequest`；路径参数由 `ApiServer` 匹配后 `attachRoute` 注入；注入的是路由快照，处理器修改不影响服务器路由表。
- body 只读一次并缓存：先读 bytes，再按需解码文本/JSON；缓存避免流被消费两次。
- 响应头与状态先在上下文中累积；`respond*` 时合并为 `HttpResponse` 并写一次。
- `_responseStarted` 表示已响应或已打开 SSE；此后禁止再次响应。
- 响应方法统一处理 HEAD/204/304：抑制 body，HEAD 保留 `Content-Length`。
- ProblemDetails 使用 `application/problem+json`；JSON 使用 `application/json`。
- 内容协商基于 `Accept` 的 q 值与通配符；`matchesContentType` 基于请求 `Content-Type`。
- 认证器通过 `setPrincipal`/`setRoles`/`setAttribute` 写入身份；principal 只能设置一次。
- SSE 由 `SseStream` 拥有写任务；`finishSse` 关闭并等待写任务，`close` 只发关闭信号。
- 请求级对象非线程安全；除 `finishSse`/`close` 外不承诺跨任务并发。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_exchange` | `HttpExchange` | final，底层交换 |
| `_options` | `ApiOptions` | final，服务器快照 |
| `_responseHeaders` | `HttpHeaders` | 累积响应头 |
| `_route` | `ApiRoute?` | 匹配后注入 |
| `_pathParameters` | `Map<String,String>` | 匹配后注入 |
| `_status` | `Int` | 默认 200，100..599 |
| `_responseStarted` | `Bool` | 已响应/已开 SSE |
| `_bodyRead` | `Bool` | body 是否已读 |
| `_bodyBytes` | `Bytes?` | body 缓存 |
| `_bodyJsonParsed` | `Bool` | JSON 是否已解析 |
| `_bodyJson` | `JsonValue?` | JSON 缓存（JSON null 也是非 null 对象） |
| `_principalName` | `String?` | 认证主体 |
| `_roles` | `List<String>` | 角色 |
| `_attributes` | `JsonObject` | 请求级属性 |
| `_sse` | `SseStream?` | 打开的 SSE |
| `_closed` | `Bool` | 是否关闭 |

不变量：`_responseHeaders`/`_attributes` 非 null；`_status` 合法；`_responseStarted` 后不再响应；`_bodyRead` 为 true 时 `_bodyBytes` 非 null；`_bodyJsonParsed` 为 true 时 `_bodyJson` 非 null；`_closed` 后读取/响应返回 `Unavailable`。

---

## 4. 生命周期

由 `ApiServer` 在每次请求创建；处理器/中间件使用；`finishSse` 等待流；`close` 关闭交换；close 幂等。不得跨请求保存。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ApiContext(HttpExchange exchange, ApiOptions options)` | 非 null | 新建上下文 | null → panic |

主要供 `ApiServer`/测试使用；业务代码不直接构造。

---

## 6. 字段表

见 §3；字段私有。`_exchange`/`_options` 为 final；其余为请求级可变状态。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `request` | 原始请求 | 无 | `HttpRequest` | 无 |
| `method` | 方法 | 无 | `HttpMethod` | 无 |
| `uri` | URI | 无 | `Uri` | 无 |
| `path` | 原始路径 | 无 | `String` | 无 |
| `headers` | 请求头副本 | 无 | `HttpHeaders` | 无 |
| `header` | 首个头值 | `String name` | `String?` | 无 |
| `query` | 查询副本 | 无 | `Query` | 无 |
| `queryParameter` | 首个查询值 | `String name` | `String?` | 无 |
| `queryParameterAll` | 全部查询值 | `String name` | `List<String>` | 无 |
| `pathParameter` | 路径参数 | `String name` | `String?` | 无 |
| `pathParameters` | 路径参数快照 | 无 | `Map<String,String>` | 无 |
| `route` | 匹配路由 | 无 | `ApiRoute?` | 无 |
| `attachRoute` | 注入匹配结果 | `ApiRoute route, Map<String,String> pathParameters` | `ApiContext` | 已附加 → panic |
| `remoteAddress` | 远端地址 | 无 | `SocketAddress` | 无 |
| `localAddress` | 本地地址 | 无 | `SocketAddress` | 无 |
| `isAuthenticated` | 是否已认证 | 无 | `Bool` | 无 |
| `principalName` | 主体名 | 无 | `String?` | 无 |
| `setPrincipal` | 设置主体 | `String principalName` | `ApiContext` | 空/重复 → panic |
| `roles` | 角色快照 | 无 | `List<String>` | 无 |
| `setRoles` | 设置角色 | `List<String> roles` | `ApiContext` | 未认证/null → panic |
| `hasRole` | 是否有角色 | `String role` | `Bool` | 无 |
| `attribute` | 读取属性 | `String name` | `JsonValue?` | 无 |
| `setAttribute` | 设置属性 | `String name, JsonValue value` | `ApiContext` | 空/null → panic |
| `attributes` | 属性快照 | 无 | `JsonObject` | 无 |
| `status` | 当前状态 | 无 | `Int` | 无 |
| `setStatus` | 设置状态 | `Int status` | `ApiContext` | 越界/已响应 → panic |
| `responseHeaders` | 响应头副本 | 无 | `HttpHeaders` | 无 |
| `setHeader` | 设置响应头 | `String name, String value` | `ApiContext` | 已响应 → panic |
| `addHeader` | 追加响应头 | `String name, String value` | `ApiContext` | 已响应 → panic |
| `bodyBytes` | 读取 body | `Context context` | `Result<Bytes, Error>` | `InvalidArgument`/`Unsupported`/`Cancelled`/`Io` |
| `bodyText` | 读取文本 | `Context context` | `Result<String, Error>` | 同上 |
| `bodyJson` | 读取 JSON | `Context context` | `Result<JsonValue, Error>` | 同上/`DataCorrupted` |
| `validateBody` | 校验 JSON body | `Context context, Validator validator` | `Result<ValidationResult, Error>` | 同上 |
| `matchesContentType` | Content-Type 匹配 | `String mediaType` | `Bool` | 无 |
| `accepts` | Accept 是否接受 | `String mediaType` | `Bool` | 无 |
| `negotiate` | 选择媒体类型 | `List<String> offered` | `String?` | 无 |
| `respondJson` | JSON 响应 | `Context context, JsonValue value` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Io` |
| `respondJson` | JSON 响应+状态 | `Context context, Int status, JsonValue value` | `Result<Unit, Error>` | 同上 |
| `respondText` | 文本响应 | `Context context, String text` | `Result<Unit, Error>` | 同上 |
| `respondText` | 文本响应+状态 | `Context context, Int status, String text` | `Result<Unit, Error>` | 同上 |
| `respondBytes` | 字节响应 | `Context context, Bytes data, String contentType` | `Result<Unit, Error>` | 同上 |
| `respondBytes` | 字节响应+状态 | `Context context, Int status, Bytes data, String contentType` | `Result<Unit, Error>` | 同上 |
| `respondEmpty` | 空响应 | `Context context, Int status` | `Result<Unit, Error>` | 同上 |
| `respondProblem` | 问题响应 | `Context context, ProblemDetails problem` | `Result<Unit, Error>` | 同上 |
| `openSse` | 打开 SSE | `Context context` | `Result<SseStream, Error>` | `InvalidArgument`/`Unavailable`/`Io` |
| `finishSse` | 关闭/等待 SSE | `Context context` | `Result<Unit, Error>` | SSE 传输错误 |
| `isResponded` | 是否已响应 | 无 | `Bool` | 无 |
| `close` | 关闭交换 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

说明：

- `path()` 返回原始百分号编码路径；路径参数已逐段解码。
- `header` 缺失返回 null，不返回空串哨兵；多值头用 `headers().getAll`。
- `bodyBytes` 首次读取后缓存；后续调用返回独立副本。
- `bodyJson` 对空 body 返回 `JsonValue.nullValue()`；非空且非 JSON Content-Type 返回 `Unsupported`；返回的 JSON 树按只读约定使用。
- `validateBody` 只校验 JSON body；校验错误由 `ValidationResult` 返回，不抛异常。
- `accepts` 无 `Accept` 时返回 true；`negotiate` 对每个候选取最具体匹配的 q 值，再按 q、specificity、服务器顺序选择；无匹配返回 null。
- `respond*` 与 `openSse` 互斥；已响应后返回 `InvalidArgument`。
- `respondProblem` 状态取自 `ProblemDetails.status()`，覆盖上下文当前状态。
- `openSse` 要求当前状态为 200；状态/头会合并进 SSE 响应。
- `finishSse` 无 SSE 时无操作；有 SSE 时 `close` 后等待写任务。
- `close` 只发 SSE 关闭信号，不等待；`finishSse` 才等待。
- `close` 关闭交换；在 SSE 打开后调用会中止传输，通常只在放弃请求时使用。

---

## 8. 使用的技术

- 请求/响应包装；
- body 缓存；
- 内容协商；
- ProblemDetails；
- 认证身份与属性；
- SSE 流；
- HEAD/204/304 语义；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、List、Map、String、Bool、Int、Long、Result；
- 运行时/接口：`HttpExchange`、`HttpRequest`、`HttpResponse`、`HttpHeaders`、`HttpHeader`、`HttpBody`、`HttpMethod`、`Uri`、`Query`、`MediaType`、`Bytes`、`Json`、`JsonValue`、`JsonObject`、`Validator`、`ValidationContext`、`ValidationResult`、`ProblemDetails`、`SseStream`、`ApiOptions`、`ApiRoute`、`SocketAddress`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`toUtf8`、`toLong`、`str`、`parseDouble`、`copy`。

---

## 10. 依赖的特性/接口/类

`Context`、`HttpExchange`、`HttpRequest`、`HttpResponse`、`HttpHeaders`、`HttpHeader`、`HttpBody`、`HttpMethod`、`Uri`、`Query`、`MediaType`、`Bytes`、`Json`、`JsonValue`、`JsonObject`、`Validator`、`ValidationContext`、`ValidationResult`、`ProblemDetails`、`SseStream`、`ApiOptions`、`ApiRoute`、`SocketAddress`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`copy`。

---

## 11. 所有权与并发

引用语义；拥有 `HttpExchange` 的使用权（服务器拥有最终关闭权）；body 缓存归上下文；`SseStream` 由上下文与写任务共享；请求级非线程安全；`finishSse`/`close` 可与写任务并发；无全局状态。

---

## 12. 示例与反例

正确：

```text
Result<Unit, Error> handle(Context context, ApiContext exchange) {
    String userId = exchange.pathParameter("userId") as String
    Result<JsonValue, Error> body = exchange.bodyJson(context)
    if body.isErr() { return Err(body.error()) }
    return exchange.respondJson(context, 200, body.value())
}
```

反例：

- 读取 body 两次期望流可重放；
- `setHeader` 在响应后调用；
- 同时 `respondJson` 和 `openSse`；
- 用 `header("Content-Type")` 代替 `matchesContentType` 的全量解析；
- 在 `close` 后继续读 body；
- 把 `ApiContext` 存入静态 Map。

---

## 13. 测试/场景义务

路径/查询/头读取；多值查询；路径参数解码；body 空/文本/JSON/超限/非法；Content-Type 匹配；Accept q 值/通配/q=0；HEAD 抑制 body；204/304；JSON/文本/字节/空/Problem 响应；重复响应；认证 principal/roles/属性；SSE 打开/发送/关闭/等待；close 幂等；取消。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
class ApiContext {
    final HttpExchange _exchange
    final ApiOptions _options
    final HttpHeaders _responseHeaders
    ApiRoute? _route = null
    Map<String, String> _pathParameters = [:]
    Int _status = 200
    Bool _responseStarted = false
    Bool _bodyRead = false
    Bytes? _bodyBytes = null
    Bool _bodyJsonParsed = false
    JsonValue? _bodyJson = null
    String? _principalName = null
    List<String> _roles = []
    JsonObject _attributes = new JsonObject()
    SseStream? _sse = null
    Bool _closed = false

    ApiContext(HttpExchange exchange, ApiOptions options) {
        if exchange == null || options == null {
            throw "ApiContext: null argument"
        }
        _exchange = exchange
        _options = options
        _responseHeaders = new HttpHeaders()
    }

    HttpRequest request() { return _exchange.request() }
    HttpMethod method() { return _exchange.request().method() }
    Uri uri() { return _exchange.request().uri() }
    String path() { return _exchange.request().uri().path() }
    HttpHeaders headers() { return _exchange.request().headers() }
    String? header(String name) { return _exchange.request().headers().getOrNull(name) }
    Query query() { return _exchange.request().uri().query() }

    String? queryParameter(String name) {
        return _exchange.request().uri().query().getOrNull(name)
    }

    List<String> queryParameterAll(String name) {
        return _exchange.request().uri().query().getAll(name)
    }

    String? pathParameter(String name) {
        if name == null { return null }
        if !_pathParameters.has(name) { return null }
        return _pathParameters.getOr(name, "")
    }

    Map<String, String> pathParameters() { return _pathParameters.copy() }

    ApiRoute? route() { return _route }

    ApiContext attachRoute(ApiRoute route, Map<String, String> pathParameters) {
        if route == null || pathParameters == null {
            throw "ApiContext.attachRoute: null argument"
        }
        if _route != null { throw "ApiContext.attachRoute: already attached" }
        _route = route.copy()
        _pathParameters = pathParameters.copy()
        return self
    }

    SocketAddress remoteAddress() { return _exchange.remoteAddress() }
    SocketAddress localAddress() { return _exchange.localAddress() }

    Bool isAuthenticated() { return _principalName != null }
    String? principalName() { return _principalName }

    ApiContext setPrincipal(String principalName) {
        if principalName == null || principalName == "" {
            throw "ApiContext.setPrincipal: empty"
        }
        if _principalName != null {
            throw "ApiContext.setPrincipal: already authenticated"
        }
        _principalName = principalName
        return self
    }

    List<String> roles() { return _roles.copy() }

    ApiContext setRoles(List<String> roles) {
        if roles == null { throw "ApiContext.setRoles: null" }
        if _principalName == null {
            throw "ApiContext.setRoles: principal not set"
        }
        Int index = 0
        while index < roles.length() {
            if roles.get(index) == "" {
                throw "ApiContext.setRoles: empty role"
            }
            index = index + 1
        }
        _roles = roles.copy()
        return self
    }

    Bool hasRole(String role) {
        if role == null { return false }
        return _roles.indexOf(role) >= 0
    }

    JsonValue? attribute(String name) {
        if name == null { return null }
        return _attributes.getOrNull(name)
    }

    ApiContext setAttribute(String name, JsonValue value) {
        if name == null || name == "" {
            throw "ApiContext.setAttribute: empty name"
        }
        if value == null { throw "ApiContext.setAttribute: null value" }
        _attributes.set(name, value)
        return self
    }

    JsonObject attributes() { return _attributes.copy() }

    Int status() { return _status }

    ApiContext setStatus(Int status) {
        if status < 100 || status > 599 {
            throw "ApiContext.setStatus: invalid status"
        }
        if _responseStarted {
            throw "ApiContext.setStatus: response already started"
        }
        _status = status
        return self
    }

    HttpHeaders responseHeaders() { return _responseHeaders.copy() }

    ApiContext setHeader(String name, String value) {
        if _responseStarted {
            throw "ApiContext.setHeader: response already started"
        }
        _responseHeaders.set(name, value)
        return self
    }

    ApiContext addHeader(String name, String value) {
        if _responseStarted {
            throw "ApiContext.addHeader: response already started"
        }
        _responseHeaders.add(name, value)
        return self
    }

    Result<Bytes, Error> bodyBytes(Context context) {
        if context == null { throw "ApiContext.bodyBytes: null context" }
        if _closed { return Err(unavailableError("api context")) }
        if _bodyRead { return Ok(copy(_bodyBytes as Bytes)) }
        Long? contentLength = _exchange.request().headers().contentLength()
        if contentLength != null && contentLength > _options.maximumBodyBytes() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "request body exceeds limit"))
        }
        Result<Bytes, Error> read = _exchange.request().body().readAll(
            context, _options.maximumBodyBytes())
        if read.isErr() { return Err(read.error()) }
        _bodyBytes = read.value()
        _bodyRead = true
        return Ok(copy(read.value()))
    }

    Result<String, Error> bodyText(Context context) {
        if context == null { throw "ApiContext.bodyText: null context" }
        Result<Bytes, Error> read = self.bodyBytes(context)
        if read.isErr() { return Err(read.error()) }
        return Ok(toUtf8(read.value()))
    }

    Result<JsonValue, Error> bodyJson(Context context) {
        if context == null { throw "ApiContext.bodyJson: null context" }
        if _bodyJsonParsed { return Ok(_bodyJson as JsonValue) }
        Result<Bytes, Error> read = self.bodyBytes(context)
        if read.isErr() { return Err(read.error()) }
        Bytes data = read.value()
        if data.isEmpty() {
            _bodyJson = JsonValue.nullValue()
            _bodyJsonParsed = true
            return Ok(_bodyJson as JsonValue)
        }
        MediaType? requestType = _exchange.request().headers().contentType()
        if requestType == null {
            return Err(new BasicError(ErrorKind.Unsupported,
                "request body has no media type"))
        }
        if !(requestType as MediaType).isJson() {
            return Err(new BasicError(ErrorKind.Unsupported,
                "request body is not JSON"))
        }
        Result<JsonValue, Error> parsed = Json.parseBytes(data)
        if parsed.isErr() { return Err(parsed.error()) }
        _bodyJson = parsed.value()
        _bodyJsonParsed = true
        return Ok(parsed.value())
    }

    Result<ValidationResult, Error> validateBody(Context context,
                                                 Validator validator) {
        if context == null || validator == null {
            throw "ApiContext.validateBody: null argument"
        }
        Result<JsonValue, Error> parsed = self.bodyJson(context)
        if parsed.isErr() { return Err(parsed.error()) }
        ValidationContext validation = new ValidationContext()
        validator.validate(parsed.value(), validation)
        return Ok(ValidationResult.fromContext(validation))
    }

    Bool matchesContentType(String mediaType) {
        if mediaType == null || mediaType == "" { return false }
        Result<MediaType, Error> offered = MediaType.parse(mediaType)
        if offered.isErr() { return false }
        String? raw = _exchange.request().headers().getOrNull("Content-Type")
        if raw == null { return false }
        Result<MediaType, Error> actual = MediaType.parse(raw)
        if actual.isErr() { return false }
        MediaType actualType = actual.value()
        MediaType offeredType = offered.value()
        if offeredType.type() == "*" { return true }
        if offeredType.type() != actualType.type() { return false }
        if offeredType.subtype() == "*" { return true }
        return offeredType.subtype() == actualType.subtype()
    }

    Bool accepts(String mediaType) {
        if mediaType == null || mediaType == "" { return false }
        List<String> offered = []
        offered.push(mediaType)
        return self.negotiate(offered) != null
    }

    String? negotiate(List<String> offered) {
        if offered == null { throw "ApiContext.negotiate: null offered" }
        if offered.isEmpty() { return null }
        List<String> acceptValues = _exchange.request().headers().getAll("Accept")
        if acceptValues.isEmpty() { return offered.get(0) }
        String? best = null
        Double bestQuality = 0.0
        Int bestSpecificity = -1
        Int offerIndex = 0
        while offerIndex < offered.length() {
            Result<MediaType, Error> offeredParse = MediaType.parse(offered.get(offerIndex))
            if offeredParse.isOk() {
                MediaType offeredType = offeredParse.value()
                Double offerQuality = -1.0
                Int offerSpecificity = -1
                Int acceptIndex = 0
                while acceptIndex < acceptValues.length() {
                    List<String> parts = acceptValues.get(acceptIndex).split(",")
                    Int partIndex = 0
                    while partIndex < parts.length() {
                        Result<MediaType, Error> candidateParse =
                            MediaType.parse(parts.get(partIndex).trim())
                        if candidateParse.isOk() {
                            MediaType candidate = candidateParse.value()
                            Double quality = 1.0
                            String? qualityText = candidate.parameter("q")
                            if qualityText != null {
                                Result<Double, Error> parsedQuality = parseDouble(qualityText)
                                if parsedQuality.isOk() {
                                    quality = parsedQuality.value()
                                } else {
                                    quality = -1.0
                                }
                            }
                            Int specificity = -1
                            if candidate.type() == "*" && candidate.subtype() == "*" {
                                specificity = 0
                            } else if candidate.type() == offeredType.type()
                                && candidate.subtype() == "*" {
                                specificity = 1
                            } else if candidate.type() == offeredType.type()
                                && candidate.subtype() == offeredType.subtype() {
                                specificity = 2
                            }
                            if specificity >= 0 && quality >= 0.0 {
                                if specificity > offerSpecificity {
                                    offerSpecificity = specificity
                                    offerQuality = quality
                                } else if specificity == offerSpecificity
                                    && quality > offerQuality {
                                    offerQuality = quality
                                }
                            }
                        }
                        partIndex = partIndex + 1
                    }
                    acceptIndex = acceptIndex + 1
                }
                if offerQuality > 0.0
                    && (best == null
                        || offerQuality > bestQuality
                        || (offerQuality == bestQuality
                            && offerSpecificity > bestSpecificity)) {
                    best = offered.get(offerIndex)
                    bestQuality = offerQuality
                    bestSpecificity = offerSpecificity
                }
            }
            offerIndex = offerIndex + 1
        }
        return best
    }

    Result<Unit, Error> respondJson(Context context, JsonValue value) {
        return self.respondJson(context, _status, value)
    }

    Result<Unit, Error> respondJson(Context context, Int status, JsonValue value) {
        if context == null || value == null {
            throw "ApiContext.respondJson: null argument"
        }
        Bytes data = Json.toBytes(value)
        return self.send(context, status, "application/json; charset=utf-8", data)
    }

    Result<Unit, Error> respondText(Context context, String text) {
        return self.respondText(context, _status, text)
    }

    Result<Unit, Error> respondText(Context context, Int status, String text) {
        if context == null || text == null {
            throw "ApiContext.respondText: null argument"
        }
        return self.send(context, status, "text/plain; charset=utf-8",
            Bytes.fromUtf8(text))
    }

    Result<Unit, Error> respondBytes(Context context, Bytes data,
                                     String contentType) {
        return self.respondBytes(context, _status, data, contentType)
    }

    Result<Unit, Error> respondBytes(Context context, Int status, Bytes data,
                                     String contentType) {
        if context == null || data == null || contentType == null
            || contentType == "" {
            throw "ApiContext.respondBytes: invalid argument"
        }
        if contentType.indexOf("\n") >= 0 || contentType.indexOf("\r") >= 0 {
            throw "ApiContext.respondBytes: invalid content type"
        }
        return self.send(context, status, contentType, data)
    }

    Result<Unit, Error> respondEmpty(Context context, Int status) {
        if context == null { throw "ApiContext.respondEmpty: null context" }
        return self.send(context, status, "", Bytes.empty())
    }

    Result<Unit, Error> respondProblem(Context context, ProblemDetails problem) {
        if context == null || problem == null {
            throw "ApiContext.respondProblem: null argument"
        }
        Bytes data = Json.toBytes(problem.toJsonValue())
        return self.send(context, problem.status(),
            "application/problem+json; charset=utf-8", data)
    }

    Result<SseStream, Error> openSse(Context context) {
        if context == null { throw "ApiContext.openSse: null context" }
        if _closed || _responseStarted || _exchange.isResponded() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "response already started"))
        }
        if _status != 200 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SSE requires status 200"))
        }
        Result<SseStream, Error> opened = SseStream.open(
            context, _exchange, _status, _responseHeaders.copy(),
            _options.sseBufferBytes())
        if opened.isErr() { return Err(opened.error()) }
        _sse = opened.value()
        _responseStarted = true
        return opened
    }

    Result<Unit, Error> finishSse(Context context) {
        if context == null { throw "ApiContext.finishSse: null context" }
        if _sse == null { return Ok(unit) }
        SseStream stream = _sse as SseStream
        stream.close()
        return stream.await(context)
    }

    Bool isResponded() {
        return _responseStarted || _exchange.isResponded()
    }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        if _sse != null { (_sse as SseStream).close() }
        return _exchange.close()
    }

    private Result<Unit, Error> send(Context context, Int status,
                                     String contentType, Bytes data) {
        if context == null || data == null {
            throw "ApiContext.send: null argument"
        }
        if status < 100 || status > 599 {
            throw "ApiContext.send: invalid status"
        }
        if _closed {
            return Err(unavailableError("api context"))
        }
        if _responseStarted || _exchange.isResponded() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "response already started"))
        }
        Bool noBodyStatus = status == 204 || status == 304
        Bool headRequest = self.method() == HttpMethod.Head
        HttpHeaders headers = new HttpHeaders()
        List<HttpHeader> entries = _responseHeaders.entries()
        Int index = 0
        while index < entries.length() {
            headers.add(entries.get(index).name(), entries.get(index).value())
            index = index + 1
        }
        if contentType != "" { headers.set("Content-Type", contentType) }
        HttpBody body = HttpBody.empty()
        if !noBodyStatus && !headRequest {
            body = HttpBody.fromBytes(data)
        }
        if !noBodyStatus {
            headers.set("Content-Length", str(toLong(data.length())))
        }
        HttpResponse response = HttpResponse.of(status)
            .withHeaders(headers)
            .withBody(body)
        Result<Unit, Error> written = _exchange.respond(response)
        if written.isOk() { _responseStarted = true }
        return written
    }
}
```
