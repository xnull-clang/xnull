# `ApiServer`

| 项 | 值 |
| --- | --- |
| 类型 | `class ApiServer implements HttpHandler` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`TlsConfig`、`HttpServer`、`HttpServerOptions`、`HttpExchange`、`HttpHandler`、`ApiRouter`、`ApiRoute`、`ApiOptions`、`ApiContext`、`OpenApiDocument`、`Error` |

---

## 1. 定位

已绑定的 API 服务端：组合 `HttpServer`，把每次 `HttpExchange` 分派到路由、认证、限流、校验、中间件和处理器，并提供可选的 OpenAPI 端点。

不做：路由存储（由 `ApiRouter` 负责）、TLS 实现、HTTP 解析、进程生命周期、在途请求排空超时、模板/ORM/RPC。

---

## 2. 设计逻辑

- 组合而非继承 `HttpServer`；`ApiServer` 实现  的 `HttpHandler`，`serve` 时把 `self` 交给 `HttpServer.serve`。
- bind 时对路由与选项做快照：之后修改 `ApiRouter`/`ApiOptions` 不影响已绑定实例。
- 分派顺序固定：全局中间件 → CORS → OpenAPI → 路由匹配 → 认证 → 限流 → 内容协商/校验 → 路由中间件 → 处理器。
- 内置 OpenAPI 端点路径是保留路径；业务路由同路径时内置端点优先；用 `openApiPath("")` 关闭。
- 每个请求创建一个 `ApiContext`；请求结束必定关闭 `HttpExchange`。
- 路由未命中生成 404；方法不匹配生成 405 + `Allow`；`autoOptions` 打开时生成 OPTIONS 204。
- 认证/限流/校验失败由内建阶段生成 `ProblemDetails`，不进入应用中间件。
- SSE 由 `ApiContext.openSse` 打开；处理器返回后 `finishSse` 等待写任务结束。
- close 委托 `HttpServer.close`，幂等；关闭后 `serve`/`handle` 返回 `Unavailable`。
- 无全局服务器、无全局路由器。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_httpServer` | `HttpServer` | 底层 HTTP 服务端 |
| `_routes` | `List<ApiRoute>` | bind 时的路由快照 |
| `_routerMiddleware` | `List<ApiMiddleware>` | 路由器级中间件快照 |
| `_options` | `ApiOptions` | 选项快照 |
| `_openApi` | `OpenApiDocument?` | 可选 OpenAPI 文档 |
| `_open` | `Bool` | 是否可服务 |

不变量：字段非 null（`_openApi` 除外）；`_routes` 中 method+pattern 唯一；`_open=false` 后不再服务；close 幂等。

---

## 4. 生命周期

`bind`/`bindTls` 创建并绑定；`serve` 运行接受循环；`close` 停止并释放监听；close 幂等。`serve` 只能一个循环；`handle` 由服务器调用，也可用于嵌入测试。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `bind(Context, SocketAddress, ApiRouter, ApiOptions)` | 全部非 null | 路由/选项合法 | 绑定/构建失败 |
| `bind(Context, SocketAddress, ApiRouter, ApiOptions, HttpServerOptions)` | + 服务器选项 | 非 null | 同上 |
| `bindTls(Context, SocketAddress, TlsConfig, ApiRouter, ApiOptions)` | + TLS | 非 null | 绑定/TLS/构建失败 |
| `bindTls(Context, SocketAddress, TlsConfig, ApiRouter, ApiOptions, HttpServerOptions)` | 全部 | 非 null | 同上 |

构造器私有；业务代码使用静态 `bind`/`bindTls`。

---

## 6. 字段表

见 §3；字段私有。`_httpServer` 拥有监听句柄；`_routes` 是 `ApiRoute.copy()` 的快照；`_options` 是 `ApiOptions.copy()` 的快照。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `bind` | 明文绑定 | `Context context, SocketAddress local, ApiRouter router, ApiOptions options` | `Result<ApiServer, Error>` | `InvalidArgument`/`PermissionDenied`/`Network` |
| `bind` | 明文绑定+服务器选项 | `Context, SocketAddress, ApiRouter, ApiOptions, HttpServerOptions` | `Result<ApiServer, Error>` | 同上 |
| `bindTls` | TLS 绑定 | `Context, SocketAddress, TlsConfig, ApiRouter, ApiOptions` | `Result<ApiServer, Error>` | 绑定/TLS |
| `bindTls` | TLS 绑定+服务器选项 | `Context, SocketAddress, TlsConfig, ApiRouter, ApiOptions, HttpServerOptions` | `Result<ApiServer, Error>` | 同上 |
| `serve` | 接受/分派 | `Context context` | `Result<Unit, Error>` | `Cancelled`/`Unavailable`/`Network` |
| `handle` | 处理单次交换 | `Context context, HttpExchange exchange` | `Result<Unit, Error>` | 传输/分派失败 |
| `localAddress` | 实际监听地址 | 无 | `SocketAddress` | 无 |
| `isOpen` | 是否可服务 | 无 | `Bool` | 无 |
| `close` | 关闭服务端 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `openApiDocument` | OpenAPI 快照 | 无 | `OpenApiDocument?` | 无 |
| `routeCount` | 路由数量 | 无 | `Int` | 无 |

说明：

- `bind` 复制选项、复制路由、构建 OpenAPI；任何一步失败都不创建监听。
- `serve` 把 `self` 作为 `HttpHandler` 交给底层服务端；重复 serve 由 `HttpServer` 拒绝。
- `handle` 在 `_open=false` 时返回 `Unavailable`；正常分派后返回 `Ok(unit)`，即使响应是 4xx/5xx。
- `handle` 返回 `Err` 只表示传输/关闭失败或请求已取消；不表示 HTTP 状态。
- `close` 关闭底层 `HttpServer`；在途连接由  运行时处理；不提供排空超时。
- `openApiDocument` 返回 bind 时构建的不可变文档；未配置时为 null。
- `routeCount` 返回快照数量，用于诊断/测试。

---

## 8. 使用的技术

- 组合 `HttpServer` + `HttpHandler`；
- 路由快照与线性匹配；
- 中间件链；
- ProblemDetails 错误映射；
- CORS/认证/限流/校验阶段；
- OpenAPI 构建；
- SSE 完成等待；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、protocol 实现、List、Map、Bool、Int、String、Result；
- 运行时：无直接 HTTP 原语（经 `HttpServer`）；
- 接口：`Context`、`SocketAddress`、`TlsConfig`、`HttpServer`、`HttpServerOptions`、`HttpExchange`、`HttpHandler`、`ApiRouter`、`ApiRoute`、`ApiOptions`、`ApiContext`、`ApiMiddleware`、`ApiHandler`、`Authenticator`、`RateLimitPolicy`、`CorsPolicy`、`ProblemDetails`、`OpenApiBuilder`、`OpenApiDocument`、`Validator`、`ValidationResult`、`HttpStatus`、`Error`、`ErrorKind`、`BasicError`、`unavailableError`、`httpMethodName`、`authSchemeChallenge`、`errorKindName`。
- 内部辅助：`ApiFunctionHandler implements ApiHandler`（把函数调用适配为处理器）、`ApiChain`（按列表构建/运行中间件链）。两者不是公开类型。

---

## 10. 依赖的特性/接口/类

`HttpServer`、`HttpServerOptions`、`HttpExchange`、`HttpHandler`、`HttpResponse`、`HttpHeaders`、`HttpMethod`、`HttpStatus`、`Context`、`ApiRouter`、`ApiRoute`、`ApiOptions`、`ApiContext`、`ApiMiddleware`、`ApiHandler`、`Authenticator`、`RateLimitPolicy`、`CorsPolicy`、`ProblemDetails`、`OpenApiBuilder`、`OpenApiDocument`、`ValidationResult`、`Error`、`ErrorKind`、`BasicError`、`unavailableError`、`httpMethodName`、`authSchemeChallenge`、`errorKindName`。

---

## 11. 所有权与并发

引用语义；拥有 `HttpServer`；`serve` 单循环；`handle` 可被服务器并发调用。路由/选项/文档在 bind 后只读，可跨任务共享；`_open` 的读写由服务器/close 竞争，close 幂等。每个 `handle` 使用独立 `ApiContext`，不共享请求状态。

---

## 12. 示例与反例

正确：

```text
ApiRouter router = new ApiRouter("/api")
router.get("/health", healthHandler).value().publicAccess()
ApiOptions options = new ApiOptions().corsPolicy(cors).rateLimitPolicy(limit)
ApiServer server = ApiServer.bind(context, address, router, options).value()
server.serve(context)
```

反例：

- bind 后继续改 router 期望生效；
- 多个 serve 循环；
- 用 `Err` 表示 404；
- handler 不响应；
- close 后继续 serve；
- 在全局中间件里吞掉认证失败并继续。

---

## 13. 测试/场景义务

- 明文/TLS bind；选项/路由快照独立性；
- GET/POST/PUT/PATCH/DELETE/HEAD 分派；
- HEAD 回退 GET 且无 body；
- 404/405/自动 OPTIONS/Allow；
- 认证 401/403/挑战头；公开路由；
- 限流 429/Retry-After/RateLimit 头；
- CORS 预检/实际请求；
- 内容协商 406/415；
- 自动校验 400/413/422；
- handler Err 映射；未响应 500；
- SSE 打开/发送/关闭/等待；
- Context 取消；close 幂等；close 后 handle/serve。

---

## 14. XNull 伪代码

> 非可执行设计伪代码；内部辅助 `ApiFunctionHandler`/`ApiChain` 不是公开类型。

```xnull
class ApiServer implements HttpHandler {
    final HttpServer _httpServer
    final List<ApiRoute> _routes
    final List<ApiMiddleware> _routerMiddleware
    final ApiOptions _options
    final OpenApiDocument? _openApi
    Bool _open

    private ApiServer(HttpServer server, List<ApiRoute> routes,
                      List<ApiMiddleware> routerMiddleware,
                      ApiOptions options, OpenApiDocument? openApi) {
        if server == null || routes == null || routerMiddleware == null || options == null {
            throw "ApiServer: null argument"
        }
        _httpServer = server
        _routes = routes.copy()
        _routerMiddleware = routerMiddleware.copy()
        _options = options
        _openApi = openApi
        _open = true
    }

    static Result<ApiServer, Error> bind(Context context, SocketAddress local,
                                         ApiRouter router, ApiOptions options) {
        return ApiServer.bind(context, local, router, options, new HttpServerOptions())
    }

    static Result<ApiServer, Error> bind(Context context, SocketAddress local,
                                         ApiRouter router, ApiOptions options,
                                         HttpServerOptions serverOptions) {
        if context == null || local == null || router == null
            || options == null || serverOptions == null {
            throw "ApiServer.bind: null argument"
        }
        ApiOptions snapshot = options.copy()
        List<ApiRoute> routes = router.routes()
        List<ApiMiddleware> routerMiddleware = router.middleware()
        Result<OpenApiDocument?, Error> document = ApiServer.buildOpenApi(snapshot, router)
        if document.isErr() { return Err(document.error()) }
        Result<HttpServer, Error> bound = HttpServer.bind(context, local, serverOptions.copy())
        if bound.isErr() { return Err(bound.error()) }
        return Ok(new ApiServer(bound.value(), routes, routerMiddleware,
            snapshot, document.value()))
    }

    static Result<ApiServer, Error> bindTls(Context context, SocketAddress local,
                                            TlsConfig tlsConfig, ApiRouter router,
                                            ApiOptions options) {
        return ApiServer.bindTls(context, local, tlsConfig, router, options,
            new HttpServerOptions())
    }

    static Result<ApiServer, Error> bindTls(Context context, SocketAddress local,
                                            TlsConfig tlsConfig, ApiRouter router,
                                            ApiOptions options,
                                            HttpServerOptions serverOptions) {
        if context == null || local == null || tlsConfig == null || router == null
            || options == null || serverOptions == null {
            throw "ApiServer.bindTls: null argument"
        }
        ApiOptions snapshot = options.copy()
        List<ApiRoute> routes = router.routes()
        List<ApiMiddleware> routerMiddleware = router.middleware()
        Result<OpenApiDocument?, Error> document = ApiServer.buildOpenApi(snapshot, router)
        if document.isErr() { return Err(document.error()) }
        Result<HttpServer, Error> bound = HttpServer.bindTls(
            context, local, tlsConfig, serverOptions.copy())
        if bound.isErr() { return Err(bound.error()) }
        return Ok(new ApiServer(bound.value(), routes, routerMiddleware,
            snapshot, document.value()))
    }

    private static Result<OpenApiDocument?, Error> buildOpenApi(
            ApiOptions options, ApiRouter router) {
        OpenApiBuilder? builder = options.openApiBuilder()
        if builder == null || options.openApiPath() == "" {
            return Ok(null)
        }
        OpenApiBuilder documentBuilder = builder as OpenApiBuilder
        Result<Unit, Error> added = documentBuilder.addRouter(router)
        if added.isErr() { return Err(added.error()) }
        Authenticator? authenticator = options.authenticator()
        if authenticator != null {
            Authenticator globalAuthenticator = authenticator as Authenticator
            documentBuilder.securitySchemeFor(globalAuthenticator, "Global authentication")
            documentBuilder.globalSecurity(globalAuthenticator.name(), [])
        }
        Result<OpenApiDocument, Error> built = documentBuilder.build()
        if built.isErr() { return Err(built.error()) }
        return Ok(built.value())
    }

    Result<Unit, Error> serve(Context context) {
        if context == null { throw "ApiServer.serve: null context" }
        if !_open { return Err(unavailableError("api server")) }
        return _httpServer.serve(context, self)
    }

    Result<Unit, Error> handle(Context context, HttpExchange exchange) {
        if context == null || exchange == null {
            throw "ApiServer.handle: null argument"
        }
        if !_open { return Err(unavailableError("api server")) }
        ApiContext apiContext = new ApiContext(exchange, _options)
        ApiHandler terminal = new ApiFunctionHandler((Context requestContext) -> {
            return self.dispatch(requestContext, apiContext)
        })
        ApiHandler chain = ApiChain.build(_options.middleware(), terminal)
        Result<Unit, Error> outcome = chain.handle(context, apiContext)
        if outcome.isErr() && !apiContext.isResponded() {
            if outcome.error().kind() == ErrorKind.Cancelled {
                apiContext.close()
                return Err(outcome.error())
            }
            Result<Unit, Error> mapped = self.respondError(context, apiContext, outcome.error())
            if mapped.isErr() {
                apiContext.close()
                return Err(mapped.error())
            }
            outcome = Ok(unit)
        }
        if outcome.isErr() && apiContext.isResponded() {
            outcome = Ok(unit)
        }
        if outcome.isOk() && !apiContext.isResponded() {
            Error missing = new BasicError(ErrorKind.Internal, "api handler did not respond")
            Result<Unit, Error> mapped = self.respondError(context, apiContext, missing)
            if mapped.isErr() {
                apiContext.close()
                return Err(mapped.error())
            }
        }
        Result<Unit, Error> sse = apiContext.finishSse(context)
        if outcome.isOk() && sse.isErr() { outcome = Err(sse.error()) }
        if outcome.isErr() {
            apiContext.close()
            return outcome
        }
        Result<Unit, Error> closed = apiContext.close()
        if closed.isErr() { return Err(closed.error()) }
        return Ok(unit)
    }

    private Result<Unit, Error> dispatch(Context context, ApiContext apiContext) {
        CorsPolicy? cors = _options.corsPolicy()
        if cors != null {
            CorsPolicy corsPolicy = cors as CorsPolicy
            Result<Bool, Error> handled = corsPolicy.process(context, apiContext)
            if handled.isErr() { return Err(handled.error()) }
            if handled.value() { return Ok(unit) }
        }
        String path = apiContext.path()
        HttpMethod method = apiContext.method()
        if _openApi != null && path == _options.openApiPath() {
            OpenApiDocument document = _openApi as OpenApiDocument
            if method == HttpMethod.Get || method == HttpMethod.Head {
                return apiContext.respondJson(context, document.toJsonValue())
            }
            if method == HttpMethod.Options && _options.isAutoOptions() {
                apiContext.setHeader("Allow", "GET, HEAD, OPTIONS")
                return apiContext.respondEmpty(context, 204)
            }
            String openApiAllow = "GET, HEAD"
            if _options.isAutoOptions() { openApiAllow = openApiAllow + ", OPTIONS" }
            apiContext.setHeader("Allow", openApiAllow)
            return self.respondProblemStatus(context, apiContext, 405,
                "method_not_allowed", "Method not allowed")
        }
        ApiRoute? route = self.matchRoute(method, path)
        if route == null {
            List<HttpMethod> allowed = self.allowedMethods(path)
            if method == HttpMethod.Options && _options.isAutoOptions() && !allowed.isEmpty() {
                apiContext.setHeader("Allow", self.formatAllowed(allowed, true))
                return apiContext.respondEmpty(context, 204)
            }
            if !allowed.isEmpty() {
                apiContext.setHeader("Allow",
                    self.formatAllowed(allowed, _options.isAutoOptions()))
                return self.respondProblemStatus(context, apiContext, 405,
                    "method_not_allowed", "Method not allowed")
            }
            return self.respondProblemStatus(context, apiContext, 404,
                "not_found", "Not found")
        }
        Result<Map<String, String>, Error> pathParameters =
            route.extractPathParameters(path)
        if pathParameters.isErr() { return Err(pathParameters.error()) }
        apiContext.attachRoute(route, pathParameters.value())
        Long? requestLength = apiContext.request().headers().contentLength()
        if requestLength != null && requestLength > _options.maximumBodyBytes() {
            return self.respondProblemStatus(context, apiContext, 413,
                "payload_too_large", "Request body too large")
        }
        if !route.isPublicAccess() {
            Authenticator? authenticator = route.authenticator()
            if authenticator == null { authenticator = _options.authenticator() }
            if authenticator != null {
                Authenticator selectedAuthenticator = authenticator as Authenticator
                Result<Unit, Error> authenticated =
                    selectedAuthenticator.authenticate(context, apiContext)
                if authenticated.isErr() {
                    return self.respondAuthError(context, apiContext,
                        selectedAuthenticator, authenticated.error())
                }
            }
        }
        if !route.isRateLimitDisabled() {
            RateLimitPolicy? policy = route.rateLimitPolicy()
            if policy == null { policy = _options.rateLimitPolicy() }
            if policy != null {
                RateLimitPolicy selectedPolicy = policy as RateLimitPolicy
                Result<Unit, Error> acquired = selectedPolicy.acquire(context, apiContext)
                if acquired.isErr() {
                    if acquired.error().kind() == ErrorKind.Busy {
                        return self.respondProblemStatus(context, apiContext, 429,
                            "rate_limited", "Too many requests")
                    }
                    return self.respondError(context, apiContext, acquired.error())
                }
            }
        }
        if !route.consumes().isEmpty() {
            Bool hasBody = false
            Long? declaredLength = apiContext.request().headers().contentLength()
            if declaredLength != null && declaredLength > 0 { hasBody = true }
            if apiContext.request().headers().has("Transfer-Encoding") { hasBody = true }
            Bool matched = false
            if hasBody {
                Int consumeIndex = 0
                while consumeIndex < route.consumes().length() {
                    if apiContext.matchesContentType(route.consumes().get(consumeIndex)) {
                        matched = true
                    }
                    consumeIndex = consumeIndex + 1
                }
            } else {
                matched = true
            }
            if !matched {
                return self.respondProblemStatus(context, apiContext, 415,
                    "unsupported_media_type", "Unsupported media type")
            }
        }
        if !route.produces().isEmpty() {
            Bool accepted = false
            Int produceIndex = 0
            while produceIndex < route.produces().length() {
                if apiContext.accepts(route.produces().get(produceIndex)) {
                    accepted = true
                }
                produceIndex = produceIndex + 1
            }
            apiContext.addHeader("Vary", "Accept")
            if !accepted {
                return self.respondProblemStatus(context, apiContext, 406,
                    "not_acceptable", "Not acceptable")
            }
        }
        if route.requestValidator() != null && method != HttpMethod.Head {
            Validator validator = route.requestValidator() as Validator
            Result<ValidationResult, Error> validated =
                apiContext.validateBody(context, validator)
            if validated.isErr() {
                return self.respondBodyError(context, apiContext, validated.error())
            }
            if !validated.value().isValid() {
                ProblemDetails problem =
                    ProblemDetails.fromValidation(validated.value().errors())
                return apiContext.respondProblem(context, problem)
            }
        }
        ApiHandler routeChain = ApiChain.build(route.middleware(), route.handler())
        ApiHandler routerChain = ApiChain.build(_routerMiddleware, routeChain)
        return routerChain.handle(context, apiContext)
    }

    private ApiRoute? matchRoute(HttpMethod method, String path) {
        Int index = 0
        while index < _routes.length() {
            ApiRoute route = _routes.get(index)
            if route.method() == method && route.pattern() == path {
                return route
            }
            index = index + 1
        }
        if method == HttpMethod.Head {
            index = 0
            while index < _routes.length() {
                ApiRoute route = _routes.get(index)
                if route.method() == HttpMethod.Get && route.pattern() == path {
                    return route
                }
                index = index + 1
            }
        }
        ApiRoute? best = null
        Int bestStatic = -1
        Int bestPriority = -1
        index = 0
        while index < _routes.length() {
            ApiRoute route = _routes.get(index)
            Int priority = 0
            if route.method() == method {
                priority = 2
            } else if method == HttpMethod.Head && route.method() == HttpMethod.Get {
                priority = 1
            }
            if priority > 0 && route.matchesPath(path) {
                Int staticCount = self.staticSegmentCount(route.pattern())
                if staticCount > bestStatic
                    || (staticCount == bestStatic && priority > bestPriority) {
                    best = route
                    bestStatic = staticCount
                    bestPriority = priority
                }
            }
            index = index + 1
        }
        return best
    }

    private Int staticSegmentCount(String pattern) {
        List<String> segments = pattern.split("/")
        Int count = 0
        Int index = 0
        while index < segments.length() {
            String segment = segments.get(index)
            if segment != "" && !(segment.startsWith("{") && segment.endsWith("}")) {
                count = count + 1
            }
            index = index + 1
        }
        return count
    }

    private List<HttpMethod> allowedMethods(String path) {
        List<HttpMethod> result = []
        Int index = 0
        while index < _routes.length() {
            ApiRoute route = _routes.get(index)
            if route.matchesPath(path) {
                Bool exists = false
                Int scan = 0
                while scan < result.length() {
                    if result.get(scan) == route.method() { exists = true }
                    scan = scan + 1
                }
                if !exists { result.push(route.method()) }
                if route.method() == HttpMethod.Get {
                    Bool hasHead = false
                    scan = 0
                    while scan < result.length() {
                        if result.get(scan) == HttpMethod.Head { hasHead = true }
                        scan = scan + 1
                    }
                    if !hasHead { result.push(HttpMethod.Head) }
                }
            }
            index = index + 1
        }
        return result
    }

    private String formatAllowed(List<HttpMethod> allowed, Bool includeOptions) {
        String result = ""
        Int index = 0
        while index < allowed.length() {
            if result != "" { result = result + ", " }
            result = result + httpMethodName(allowed.get(index))
            index = index + 1
        }
        if includeOptions {
            if result != "" { result = result + ", " }
            result = result + "OPTIONS"
        }
        return result
    }

    private Result<Unit, Error> respondAuthError(Context context,
                                                 ApiContext apiContext,
                                                 Authenticator authenticator,
                                                 Error error) {
        if error.kind() == ErrorKind.Cancelled { return Err(error) }
        if error.kind() == ErrorKind.PermissionDenied {
            return self.respondProblemStatus(context, apiContext, 403,
                "forbidden", "Forbidden")
        }
        if error.kind() == ErrorKind.Unavailable || error.kind() == ErrorKind.Busy {
            return self.respondProblemStatus(context, apiContext, 503,
                "service_unavailable", "Service unavailable")
        }
        if error.kind() == ErrorKind.Timeout {
            return self.respondProblemStatus(context, apiContext, 504,
                "auth_timeout", "Authentication timeout")
        }
        if error.kind() == ErrorKind.Io || error.kind() == ErrorKind.Network
            || error.kind() == ErrorKind.DataCorrupted
            || error.kind() == ErrorKind.Internal
            || error.kind() == ErrorKind.OutOfMemory {
            return self.respondProblemStatus(context, apiContext, 500,
                "auth_failure", "Authentication failure")
        }
        String challenge = authSchemeChallenge(authenticator.scheme(), authenticator.realm())
        if challenge != "" {
            apiContext.setHeader("WWW-Authenticate", challenge)
        }
        return self.respondProblemStatus(context, apiContext, 401,
            "unauthorized", "Unauthorized")
    }

    private Result<Unit, Error> respondBodyError(Context context,
                                                 ApiContext apiContext, Error error) {
        if error.kind() == ErrorKind.Unsupported {
            return self.respondProblemStatus(context, apiContext, 415,
                "unsupported_media_type", "Unsupported media type")
        }
        if error.kind() == ErrorKind.DataCorrupted {
            return self.respondProblemStatus(context, apiContext, 400,
                "bad_request", "Malformed request body")
        }
        if error.kind() == ErrorKind.InvalidArgument {
            return self.respondProblemStatus(context, apiContext, 413,
                "payload_too_large", "Request body too large")
        }
        return self.respondError(context, apiContext, error)
    }

    private Result<Unit, Error> respondError(Context context,
                                             ApiContext apiContext, Error error) {
        Int status = self.statusFor(error.kind())
        if status == 0 { return Err(error) }
        String typeName = errorKindName(error.kind())
        ProblemDetails problem = ProblemDetails.of(status)
            .withType(self.problemType(typeName))
            .withTitle(self.titleFor(status))
        if _options.isIncludeErrorDetail() {
            problem = problem.withDetail(error.describe())
        }
        return apiContext.respondProblem(context, problem)
    }

    private Result<Unit, Error> respondProblemStatus(Context context,
                                                     ApiContext apiContext,
                                                     Int status, String typeName,
                                                     String title) {
        ProblemDetails problem = ProblemDetails.of(status)
            .withType(self.problemType(typeName))
            .withTitle(title)
        return apiContext.respondProblem(context, problem)
    }

    private Int statusFor(ErrorKind kind) {
        if kind == ErrorKind.InvalidArgument { return 400 }
        if kind == ErrorKind.NotFound { return 404 }
        if kind == ErrorKind.AlreadyExists { return 409 }
        if kind == ErrorKind.PermissionDenied { return 403 }
        if kind == ErrorKind.Unsupported { return 415 }
        if kind == ErrorKind.Busy { return 429 }
        if kind == ErrorKind.Timeout { return 504 }
        if kind == ErrorKind.Unavailable { return 503 }
        if kind == ErrorKind.Cancelled { return 0 }
        return 500
    }

    private String titleFor(Int status) {
        String reason = HttpStatus.of(status).reason()
        if reason == "" { return "HTTP " + str(status) }
        return reason
    }

    private String problemType(String name) {
        String base = _options.problemTypeBase()
        if base == "" { return "urn:xdk:api:" + name }
        return base + "/" + name
    }

    SocketAddress localAddress() { return _httpServer.localAddress() }
    Bool isOpen() { return _open }
    OpenApiDocument? openApiDocument() { return _openApi }
    Int routeCount() { return _routes.length() }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return _httpServer.close()
    }
}
```

> `ApiFunctionHandler` 把 `Result<Unit, Error>(Context)` 函数适配为 `ApiHandler`；`ApiChain.build` 按“先添加者在外层”构造链，并在最后一环调用终端处理器。两者是内部辅助，不是公共类型。
