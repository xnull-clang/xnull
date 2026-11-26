# `xdk.api` 包设计（API 服务框架）

| 项 | 值 |
| --- | --- |
| 包 | `xdk.api` |
| 层 | L8 solutions |
| 依赖 | `xdk.net.http`、`xdk.net.uri`、`xdk.net.mime`、`xdk.codec`、`xdk.validate`、`xdk.errors`、`xdk.execution` |
| 被依赖 | 应用、服务、Agent、工具、嵌入式/计算产品 |
| 稳定性 | `preview`；不进入 1.0 公共承诺 |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件；类型文件 14 段 |

---

## 1. 包定位

`xdk.api` 是建立在 [`xdk.net.http`](../../network/net/http/README.md) 之上的 **HTTP API 框架层**：

- 路由、路由元数据、中间件链、请求处理器；
- `ApiContext` 统一读取路径参数、查询参数、头、body，并生成响应；
- 通过 `xdk.validate` 做请求校验，通过 `xdk.codec` 做 JSON 编解码；
- 用 `ProblemDetails`（RFC 7807/9457）表达 4xx/5xx；
- OpenAPI 3.1 文档与构建器；
- Basic/Bearer/API key 认证协议（只验证，不提供身份提供方）；
- 限流、CORS、SSE、内容协商；
- 停机委托给 `HttpServer`，不复制 HTTP 服务器、请求、响应类型。

不做：

- 模板引擎、静态站点、管理后台；
- ORM、SQL 驱动、数据库迁移；
- RPC 框架、GraphQL、gRPC；
- 身份提供方、登录页、令牌签发、Session 存储；
- 反射式依赖注入、注解扫描、自动对象映射；
- OpenAPI 全量校验器、`$ref` 解析器、代码生成器；
- WebSocket Hub、HTTP/3、QUIC、反向代理。

---

## 1.5 实现状态（M23.4）

已实现 14/15：`ProblemDetails`、`AuthScheme`、`CorsPolicy`、`RateLimitPolicy`、
`ApiOptions`、`ApiHandler`、`ApiMiddleware`、`Authenticator`、`ApiRoute`、`ApiRouter`、
`ApiContext`、`OpenApiDocument`、`OpenApiBuilder`、`ApiServer`；`SseStream` 留 M23.5。

- `ApiOptions`：中间件/认证/限流/CORS/body 上限/SSE 缓冲/detail/autoOptions/problemTypeBase/
  `openApi`/`openApiPath`/copy；`openApiPath` 默认 `/openapi.json`，空串关闭。
- `ApiHandler`/`ApiMiddleware`/`Authenticator`：协议；`Authenticator.authenticate` 写入
  principal/roles。
- `ApiRoute`：`{name}` 整段参数、尾部 `*` 通配、路径参数百分号解码、路由中间件/认证/限流
  覆盖、publicAccess、requestValidator/requestSchema/operationName/copy。
- `ApiRouter`：前缀、route/get/post/put/patch/delete/head/options、重复注册
  `AlreadyExists`、静态优先 + HEAD 回退 GET、allowedMethods。
- `ApiContext`：请求读取、body 缓存与上限、JSON 缓存、路径参数注入、principal/roles/
  属性、状态/响应头、respondJson/Text/Empty/Problem、幂等 close。
- 命名受限：无重载，setter/getter 用 `get*`/`with*`；`ApiContext` 响应带状态版本为
  `respondJsonWithStatus`/`respondTextWithStatus`。
- 与 `ApiRoute.md` 的差异：本实现额外支持尾部 `*` 通配（合同尚未收录；作为兼容扩展保留，
  以合同为准的调用方不应依赖）。
- `OpenApiDocument`：`parse`/`fromJson` 校验 `openapi` 与 `info.title/version`；缺失 `paths`
  归一为空对象；getter 返回副本；`operationCount` 统计 8 个方法；`toJsonText(pretty)`。
- `OpenApiBuilder`：summary/description/terms/contact/license/dialect/externalDocs/server/tag、
  Basic/Bearer 与三种 API key 安全方案、组件 schema/response/parameter、webhook、
  `globalSecurity`、`addRoute`/`addRouter`（幂等）；`build` 输出 `openapi: 3.1.0`，
  自动补 `components.schemas.ProblemDetails` 与 `default` 问题响应。
- `operationId`：显式优先；否则 method + 分段路径生成稳定名（如 `get_users_id`），
  非法字符转 `_`，冲突追加 `_2`。
- `ApiRoute` 新增 summary/description/tags/queryParameter/headerParameter/response 元数据；
  path 参数输出为 `in: path` 的 string schema，requestSchema 输出为 `application/json` requestBody。
- `ApiServer`：`bind`/`bindWithOptions`（`HttpServerOptions` 暂只做非空校验并忽略，README 记录）、
  `serve` 循环 `HttpServer.serve(..., 1)`、`handle` 管线：CORS 预检 → OpenAPI 端点 → 路由匹配
  （404/405/auto-OPTIONS）→ 路径参数 → 实际 CORS 头 → 认证（401/403/503/504/500 + 挑战头）→
  限流（429 + `Retry-After`）→ 请求校验（400 ProblemDetails）→ 全局/router/route 中间件 →
  业务 handler；未响应返回 204。
- 端到端证据：`server-basic=200,hello,404,405,true,204,true,200,0,1,127.0.0.1:19140,true`；
  `server-auth=401,Basic realm="realm1",403,...`；`server-rate=200,429,1,true,200,200`；
  `server-openapi=200,application/json; charset=utf-8,...`。
- `localhost` 绑定使用 `HttpServer.bind(host, port)`；`bindTls`/SSE/HTTP2/keep-alive 不做。
- `Authenticator` 只定义协议，不内置具体认证器；`ProblemDetails.withStatus` 用于把校验错误
  从 422 调整为管线约定的 400。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 组合而非继承 | `ApiServer` 组合 `HttpServer`；`SseStream` 组合 `HttpExchange`/`HttpBody`；不重定义  类型 |
| 显式装配 | 路由、中间件、认证器、策略由调用方显式注册；无全局 Router、无静态注册表 |
| 上下文优先 | 阻塞方法首参 `Context`；每个请求一个 `ApiContext`，不跨请求复用 |
| Result 失败 | 可恢复失败用 `Result<T, Error>`；4xx/5xx 是正常 HTTP 响应，不是传输错误 |
| 幂等关闭 | `ApiServer`、`ApiContext`、`SseStream` 的 `close` 幂等；重复关闭返回首次结果或无操作 |
| 标准优先 | OpenAPI 3.1、RFC 7807/9457、RFC 9110 状态语义、Fetch CORS、WHATWG SSE、IETF RateLimit 头字段 |
| JSON 优先但不锁死 | 默认 JSON；`produces`/`consumes` 与 `Accept`/`Content-Type` 显式协商 |
| 安全默认 | 无凭据通配 CORS 禁止；默认不暴露内部错误 detail；认证失败不泄露用户是否存在 |
| 无反射 | 元数据由 `ApiRoute` 显式声明；不从类型/注解/反射推导 |
| 可测试 | 路由匹配、上下文读取、ProblemDetails、CORS、限流、SSE 编解码均可脱离真实 socket 测试 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `ApiServer` | class implements `HttpHandler` | 绑定/服务/关闭、分派管线、OpenAPI 端点 | [`ApiServer.md`](ApiServer.md) |
| `ApiOptions` | class | 全局中间件、认证、限流、CORS、OpenAPI、body/SSE 上限 | [`ApiOptions.md`](ApiOptions.md) |
| `ApiRouter` | class | 路由注册、前缀、匹配、允许方法 | [`ApiRouter.md`](ApiRouter.md) |
| `ApiRoute` | class | 方法/模式/处理器、元数据、校验器、策略覆盖 | [`ApiRoute.md`](ApiRoute.md) |
| `ApiHandler` | protocol | 业务处理器入口 | [`ApiHandler.md`](ApiHandler.md) |
| `ApiMiddleware` | protocol | 可组合中间件，显式 `next` | [`ApiMiddleware.md`](ApiMiddleware.md) |
| `ApiContext` | class | 请求读取、认证身份、属性、校验、响应、SSE | [`ApiContext.md`](ApiContext.md) |
| `ProblemDetails` | class | RFC 7807/9457 问题详情 | [`ProblemDetails.md`](ProblemDetails.md) |
| `OpenApiDocument` | class | OpenAPI 3.1 文档快照 | [`OpenApiDocument.md`](OpenApiDocument.md) |
| `OpenApiBuilder` | class | 从路由/显式组件构建 OpenAPI 3.1 | [`OpenApiBuilder.md`](OpenApiBuilder.md) |
| `Authenticator` | protocol | 认证协议；成功写入 principal/roles | [`Authenticator.md`](Authenticator.md) |
| `AuthScheme` | enum | Basic/Bearer/API key 位置 | [`AuthScheme.md`](AuthScheme.md) |
| `RateLimitPolicy` | class | 固定窗口限流与标准响应头 | [`RateLimitPolicy.md`](RateLimitPolicy.md) |
| `CorsPolicy` | class | 允许源/方法/头、预检、实际请求 | [`CorsPolicy.md`](CorsPolicy.md) |
| `SseStream` | class implements `ByteStream` | SSE 事件编码、缓冲、反压、写任务 | [`SseStream.md`](SseStream.md) |

类型数：15 个公开类型 + 本 README，共 16 个文件。

---

## 4. 顶层函数

无；全部能力通过类型的静态入口或实例方法提供。

---

## 5. 技术、支撑与依赖

- 技术：HTTP/1.1 服务端、路由匹配、中间件链、内容协商、JSON、RFC 7807、OpenAPI 3.1、CORS、SSE、固定窗口限流。
- 支撑：`HttpServer`/`HttpHandler`/`HttpExchange`/`HttpRequest`/`HttpResponse`/`HttpBody`/`HttpHeaders`/`HttpMethod`/`HttpStatus`；`Uri`/`Query`/`percentDecode`；`MediaType`；`Json`/`JsonValue`/`JsonObject`/`JsonArray`；`Schema`/`Validator`/`ValidationContext`/`ValidationResult`；`Context`/`TaskGroup`/`Task`/`Mutex`/`RuntimeMonitor`；`BasicError`/`ErrorKind`。
- 依赖方向：`xdk.api` → net/utils/core；core/net/os/utils 不依赖 `xdk.api`。
- 关键依赖文档：[`HttpServer`](../../network/net/http/HttpServer.md)、[`xdk.validate`](../../utils/validate/README.md)、[`xdk.codec`](../../utils/codec/README.md)、[`Context`](../../core/execution/Context.md)。

---

## 6. 能力面对齐

| 能力 | FastAPI | ASP.NET Core | Spring Boot | `xdk.api` |
| --- | --- | --- | --- | --- |
| 路由声明 | 装饰器 | `MapGet`/`MapPost` | `@GetMapping` | `ApiRouter.route` 与 `get/post/...` |
| 路径/查询/头/body | 参数绑定 | 参数绑定 | 注解绑定 | `ApiContext` 显式读取 |
| 请求校验 | Pydantic | DataAnnotations/Filter | Bean Validation | `ApiRoute.requestValidator` + `xdk.validate` |
| 错误响应 | `HTTPException` | `ProblemDetails` | `ProblemDetail` | `ProblemDetails` |
| 中间件 | `add_middleware` | 中间件管线 | Filter/Interceptor | `ApiMiddleware` 协议 |
| 认证 | `Security` | Authentication | Spring Security | `Authenticator` 协议 |
| 限流 | 扩展 | RateLimiter | Bucket4j/生态 | `RateLimitPolicy` |
| CORS | `CORSMiddleware` | `UseCors` | `CorsRegistry` | `CorsPolicy` |
| OpenAPI | 自动生成 | 内置 | springdoc | `OpenApiBuilder` 显式构建 |
| SSE | `StreamingResponse` | `ServerSentEvents` | `SseEmitter` | `SseStream` |
| 优雅停机 | lifespan | Host 生命周期 | 生命周期 | 委托 `HttpServer.close` |
| 依赖注入 | 有 | 有 | 有 | 不做；显式构造与 `ApiContext` 属性 |
| 模板/ORM/RPC | 生态 | EF Core 等 | Spring Data 等 | 不做 |

对齐结论：

- 覆盖 API 框架的**核心请求面、错误面、文档面、安全面、流式面**；
- 主动放弃注解/反射/容器/模板/ORM，避免把生态框架塞进 ；
- 以 `ApiContext` 替代参数绑定，以 `ApiRoute` 元数据替代反射生成。

---

## 7. 跨类型规则

### 7.1 分派顺序

1. `ApiOptions.middleware`（全局，最外层；可短路）；
2. `CorsPolicy`（预检在此结束）；
3. 内置 OpenAPI 端点（若配置）；
4. 路由匹配（404/405/自动 OPTIONS）；
5. 认证（`Authenticator`）；
6. 限流（`RateLimitPolicy`）；
7. 内容协商/请求 Content-Type/自动校验；
8. `ApiRouter.middleware`；
9. `ApiRoute.middleware`；
10. `ApiHandler`。

约定：中间件列表“先添加者在外层”；`ApiMiddleware` 必须显式调用 `next` 才会继续；认证/限流失败由内建阶段直接生成 ProblemDetails，不进入后面的路由中间件。全局中间件位于安全阶段之前，短路时认证/限流不会执行，属于应用信任边界。

### 7.2 响应契约

- 每个请求最多响应一次；`ApiContext.respond*` 与 `openSse` 互斥；
- 处理器成功但未响应 → 500 ProblemDetails；
- 处理器返回 `Err` 且未响应 → 按 `ErrorKind` 映射状态；
- 已响应后再返回 `Err` 只作为诊断，不产生第二个响应；
- `HEAD` 走 `GET` 回退，响应体被抑制并保留 `Content-Length`；
- 4xx/5xx 是正常响应，不把 `HttpResponse` 当 `Err`。

### 7.3 错误映射

| `ErrorKind` | HTTP 状态 | 说明 |
| --- | ---: | --- |
| `InvalidArgument` | 400 | 参数/状态非法 |
| `NotFound` | 404 | 资源不存在 |
| `AlreadyExists` | 409 | 冲突 |
| `PermissionDenied` | 403 | 已认证但禁止 |
| `Unsupported` | 415 | 媒体类型/能力不支持 |
| `Busy` | 429 | 限流或资源忙 |
| `Timeout` | 504 | 下游超时 |
| `Unavailable` | 503 | 暂时不可用 |
| `Cancelled` | 无响应 | 客户端/服务端取消 |
| `Io`/`Network`/`DataCorrupted`/`OutOfMemory`/`Internal` | 500 | 服务端失败 |
| 请求体超过 `maximumBodyBytes` | 413 | `ApiContext`/`ApiServer` 预检 |
| 请求体 JSON 非法 | 400 | 自动校验/`bodyJson` |
| 请求体媒体类型不支持 | 415 | `consumes`/`bodyJson` |

`ApiOptions.includeErrorDetail` 为 true 时才把 `Error.describe()` 放入 `detail`；默认关闭。

### 7.4 认证与身份

- `Authenticator.authenticate` 只验证凭据，成功后写入 `principalName`/`roles`/属性；
- 401 附 `WWW-Authenticate`；403 不泄露用户是否存在；
- API key 没有标准挑战头，401 可不带挑战；
- 不做登录、令牌签发、Session、用户库、OAuth2/OIDC 流程。

### 7.5 限流

- 固定窗口，键 = 路由（可选）+ principal/指定头/远端地址；
- 成功与失败都写 `RateLimit-Limit`/`RateLimit-Remaining`/`RateLimit-Reset`；
- 超限返回 429 + `Retry-After`；
- 单实例内存状态；分布式限流不在本包。

### 7.6 CORS

- 仅允许显式 origin；`*` 与 `allowCredentials` 互斥；
- 预检 = `OPTIONS` + `Access-Control-Request-Method`；
- 实际请求回显 origin 时加 `Vary: Origin`；
- 不做通配子域、私有网络访问、凭据通配。

### 7.7 OpenAPI

- 文档版本固定为 3.1.x；Schema 使用 JSON Schema 2020-12 语义；
- 路径参数、查询/头参数、请求/响应 schema 由 `ApiRoute` 元数据生成；
- `operationId` 来自 `operationName` 或确定性生成，必须唯一；
- 不解析 `$ref`，不生成客户端，不做 3.0 → 3.1 迁移。

### 7.8 SSE

- 响应 `Content-Type: text/event-stream`，UTF-8，关闭压缩；
- `data` 多行拆分，`event`/`id`/`retry` 字段按 WHATWG 格式；
- `SseStream` 是有界缓冲；满时发送方阻塞；关闭后先排空再 EOF；
- 写响应在独立任务执行，处理器返回后由 `ApiContext.finishSse` 等待；
- `Last-Event-ID` 由应用读取并决定是否重放；不内建事件存储。

### 7.9 停机

- `Context.cancel` 或 `ApiServer.close` 停止接受新连接；
- `ApiServer.close` 幂等，直接关闭底层 `HttpServer`；
- 不承诺在途请求排空超时； `HttpServer` 未提供该能力；
- SSE/长连接在服务器关闭时收到传输错误。

---

## 8. 场景

### A1：JSON CRUD

`ApiRouter.get("/users/{userId}", handler)`；`ApiContext.pathParameter("userId")`；`bodyJson` + `Schema.validateValue`；`respondJson`。

### A2：统一错误

校验失败 → `ProblemDetails.fromValidation(errors)` → 422 + `application/problem+json`；未处理异常 → 500，默认无内部 detail。

### A3：认证

`Authenticator` 读取 `Authorization`；成功 `setPrincipal`/`setRoles`；失败 401 + `WWW-Authenticate`；健康检查路由 `publicAccess()`。

### A4：限流

`RateLimitPolicy(100, 60000)` 作为全局策略；超限 429 + `Retry-After`；响应带 `RateLimit-*`。

### A5：CORS

`CorsPolicy().allowOrigin("https://app.example").allowMethod(HttpMethod.Post)`；预检 204；实际响应回显 origin + `Vary: Origin`。

### A6：OpenAPI

`OpenApiBuilder("Orders", "1.0.0")` → `addRouter(router)` → `ApiOptions.openApi(builder)`；`GET /openapi.json` 返回 3.1 文档。

### A7：SSE

`ApiContext.openSse(context)` → `sendEvent`/`sendJson` → `close`；`ApiServer` 等待写任务结束。

### A8：取消/关闭

请求 `Context` 取消 → 处理器返回 `Cancelled`；`ApiServer.close` 停止接受；重复 close 无操作。

---

## 9. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 模板引擎/静态文件 | 不做；由应用或 ecosystem 提供 |
| 表单/Multipart 高层绑定 | 不做；`ApiContext` 暴露 bytes/text/json，复杂表单用  `MultipartForm` |
| ORM/SQL | 不做；`xdk.db` 与 SQL 驱动在别处 |
| RPC/GraphQL | 不做；`xdk.jsonrpc`/`xdk.mcp` 独立 |
| 反射式 DI/参数绑定 | 不做；`ApiContext` 显式读取 |
| 全局 Router | 禁止；`ApiRouter` 实例显式传递 |
| HTTP/3/QUIC | 不做；由  决定 |
| CONNECT/TRACE | CONNECT 拒绝；TRACE 可注册但不建议在公网启用 |
| WebSocket Hub | 不做； upgrade 原语可用 |
| OAuth2/OIDC/mTLS | 不做；仅 Basic/Bearer/API key 验证 |
| 分布式限流 | 不做；单实例固定窗口 |
| 滑动窗口/令牌桶/并发限流 | 不做；记录为 X |
| 通配子域 CORS | 不做；安全风险 |
| 私有网络访问 CORS | 不做；草案能力 |
| OpenAPI 全量校验/`$ref` 解析 | 不做；只构建与快照 |
| 自动重放 SSE | 不做；应用读取 `Last-Event-ID` |
| 优雅停机排空超时 | 不做；`HttpServer` 无该接口 |
| 注解/装饰器 | 不做；XNull 显式 API |
| 自定义异常/错误映射器 | 不做；handler 直接返回 `ProblemDetails`，或使用标准 `ErrorKind` 映射 |

---

## 10. 安全

- TLS 由 `HttpServer.bindTls` 负责；认证凭据不得在明文链路传输。
- 不在日志/ProblemDetails/OpenAPI 示例中写入密码、令牌、Cookie。
- Basic 比较使用常量时间；Bearer/API key 使用常量时间比较；认证失败统一 401。
- CORS 只允许显式 origin；`*` 与凭据互斥；回显 origin 时加 `Vary`；CORS 不是访问控制，授权必须由 `Authenticator` 完成。
- 限流键优先使用已认证 principal；使用客户端头时必须由可信代理清洗；键上限触发共享 `overflow` 桶时，攻击者可能耗尽该桶，应配合边缘限流；限流在认证之后，未认证流量需由边缘防护。
- 请求 body 有 API 层上限；SSE 有缓冲上限；超出返回 413 或关闭流。
- 路由匹配按原始 `/` 分段后逐段解码；`%2F` 不改变分段，避免路径穿越；应用把路径参数用于文件/下游 URI 时必须再次规范化。
- 默认不暴露 5xx 内部 detail；`includeErrorDetail` 仅用于受控环境。
- OpenAPI 默认公开；敏感 API 应禁用端点或用全局中间件保护。
- SSE 事件 `data`/`event`/`id` 做 CR/LF/NUL 校验，防止字段注入。

---

## 11. 质量门禁

- [ ] 15 个公开类型均有独立 PascalCase 文件，README 索引链接全部可达；
- [ ] 每个类型文件 1–14 段齐全，无省略实现；
- [ ] 协议非泛型；枚举独立；无 class 内嵌 enum/protocol；
- [ ] 公开签名只使用 XNull 语法；参数名为完整英文单词；
- [ ] 阻塞方法首参 `Context`；失败走 `Result`；`close` 幂等；
- [ ] 不重复 `HttpServer`/`HttpRequest`/`HttpResponse`/`HttpBody`；
- [ ] 链接可达；命名检查 PASS；
- [ ] 无代码/测试/脚本改动。

---

## 12. 参考规范与实现

- [FastAPI Features](https://fastapi.tiangolo.com/features/)：路由、依赖、校验、OpenAPI、中间件。
- [FastAPI CORS](https://fastapi.tiangolo.com/tutorial/cors/)：`CORSMiddleware` 能力面。
- [ASP.NET Core Minimal API 参数绑定](https://learn.microsoft.com/aspnet/core/fundamentals/minimal-apis/parameter-binding)：route/query/header/body 绑定来源。
- [ASP.NET Core Rate Limiting](https://learn.microsoft.com/aspnet/core/performance/rate-limit)：固定/滑动窗口、令牌桶、并发限制。
- [ASP.NET Core CORS](https://learn.microsoft.com/aspnet/core/security/cors)：策略、预检、凭据。
- [Spring Framework Error Responses](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-ann-rest-exceptions.html)：`ProblemDetail` 与 RFC 9457。
- [OpenAPI Specification 3.1.0](https://spec.openapis.org/oas/v3.1.0.html)：`jsonSchemaDialect`、`webhooks`、`mutualTLS`、Security Scheme。
- [RFC 7807](https://www.rfc-editor.org/rfc/rfc7807)：Problem Details 字段与扩展成员；[RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) 为其更新版。
- [MDN CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS)：预检、凭据、通配限制、`Vary: Origin`。
- [WHATWG Server-Sent Events](https://html.spec.whatwg.org/dev/server-sent-events.html)：事件流格式与 `Last-Event-ID`。
- [IETF RateLimit Header Fields](https://datatracker.ietf.org/doc/draft-ietf-httpapi-ratelimit-headers/)：`RateLimit-Limit`/`RateLimit-Remaining`/`RateLimit-Reset`。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Api`、`@Operation`、`@Middleware`、`@Inject`、`@Component`、`@Configuration`、`@Bean` |
| 本包消费 | `@Value`、`@Builder`、`@HttpRoute`、`@Header`、`@Query`、`@Body`、`@StatusCode` |
| 处理器 | ApiAnnotationProcessor（Resolve/Validate/Generate） |
| 生成物 | 路由表、OpenAPI、参数绑定、装配元数据 |
| 状态 | 领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| API 类 | `@Api` | OpenAPI/路由前缀 |
| 路由方法 | `@HttpRoute`/`@Operation` | 路由/operation |
| 中间件类 | `@Middleware` | 中间件链 |
| 组件/配置/Bean | `@Component`/`@Configuration`/`@Bean` | 装配表 |
| 装配字段/构造/参数 | `@Inject` | 装配代码 |

### 声明

```x
@Target(Type)
@Retention(Source)
@annotation Api {
    final String prefix
    final String title
}

@Target(Method)
@Retention(Source)
@annotation Operation {
    final String summary
}

@Target(Type)
@Retention(Source)
@annotation Middleware {
}

@Target(Field, Constructor, Parameter)
@Retention(Source)
@annotation Inject {
}

@Target(Type)
@Retention(Source)
@annotation Component {
    final String name = ""
}

@Target(Type)
@Retention(Source)
@annotation Configuration {
}

@Target(Method)
@Retention(Source)
@annotation Bean {
    final String name = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
@Api("/v1", "User API")
class UserApi {
    @HttpRoute("/users/{id}", HttpMethod.Get)
    @Operation("Get user")
    HttpResponse getUser(@Query("id") Long id) {
        // ...
    }
}

@Component("userService")
class UserService {
    @Inject UserRepository repository

    @Transactional(readOnly = true)
    Result<User, Error> find(Long recordId) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
