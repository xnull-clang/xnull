# `xdk.net.http` 包设计（HTTP/1.1 + HTTP/2 核心）

| 项 | 值 |
| --- | --- |
| 包 | `xdk.net.http` |
| 层 | `xdk.net` / L5 |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.text`、`xdk.io`、`xdk.execution`、`net`、`net.uri`、`net.tls`、`net.mime` |
| 被依赖 | `net.websocket`、应用 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.net.http` 提供 HTTP/1.0/1.1/2 客户端/服务端核心：

- `HttpMethod`、`HttpVersion`、`HttpStatus`；
- `HttpHeader`/`HttpHeaders`；
- `HttpBody`（缓冲/流式）；
- `HttpRequest`/`HttpResponse`；
- `HttpExchange`/`HttpHandler` 服务端；
- `HttpClient`/`HttpClientOptions`；
- `HttpServer`/`HttpServerOptions`；
- `Cookie`/`SameSite`/`CookieJar`；
- HTTP/2：`Http2Settings`/`Http2Session`/`Http2Stream`/`Http2Event`/states/errors。

不做：HTTP/3/QUIC、Router/Middleware、WebSocket 高层封装（升级原语由 `HttpExchange.upgrade` 提供）。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 状态码不是 Err | 4xx/5xx 是正常响应 |
| 头大小写不敏感 | 名称归一化；值保留 |
| Body 所有权 | 流式 body 由持有者 close |
| Context 可取消 | 请求/服务/读写首参 `Context` |
| 资源幂等 | `HttpClient`/`HttpServer` close 幂等 |
| 无全局状态 | 无全局客户端/服务端/CookieJar |
| 不内建框架 | 无 Router/Middleware/DI |
| 明确升级边界 | `upgrade` 后 HTTP 层不再读写连接 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `HttpMethod` | enum | 请求方法 | [`HttpMethod.md`](HttpMethod.md) |
| `HttpVersion` | enum | HTTP/1.0、1.1、2 | [`HttpVersion.md`](HttpVersion.md) |
| `HttpStatus` | class | 状态码/类别 | [`HttpStatus.md`](HttpStatus.md) |
| `HttpHeader` | class | 单条头 | [`HttpHeader.md`](HttpHeader.md) |
| `HttpHeaders` | class | 大小写不敏感多值头 | [`HttpHeaders.md`](HttpHeaders.md) |
| `HttpBody` | class | 缓冲/流式 body | [`HttpBody.md`](HttpBody.md) |
| `HttpRequest` | class | 请求值对象 | [`HttpRequest.md`](HttpRequest.md) |
| `HttpResponse` | class | 响应值对象 | [`HttpResponse.md`](HttpResponse.md) |
| `HttpExchange` | class | 服务端单次交换 | [`HttpExchange.md`](HttpExchange.md) |
| `HttpHandler` | protocol | 服务端处理入口 | [`HttpHandler.md`](HttpHandler.md) |
| `HttpClientOptions` | class | 客户端配置 | [`HttpClientOptions.md`](HttpClientOptions.md) |
| `HttpClient` | class | 客户端 | [`HttpClient.md`](HttpClient.md) |
| `HttpServerOptions` | class | 服务端配置 | [`HttpServerOptions.md`](HttpServerOptions.md) |
| `HttpServer` | class | 服务端 | [`HttpServer.md`](HttpServer.md) |
| `Http2Settings` | class | HTTP/2 SETTINGS | [`Http2Settings.md`](Http2Settings.md) |
| `Http2SessionState` | enum | HTTP/2 会话状态 | [`Http2SessionState.md`](Http2SessionState.md) |
| `Http2StreamState` | enum | HTTP/2 流状态 | [`Http2StreamState.md`](Http2StreamState.md) |
| `Http2ErrorCode` | enum | HTTP/2 错误码 | [`Http2ErrorCode.md`](Http2ErrorCode.md) |
| `Http2EventKind` | enum | HTTP/2 事件类型 | [`Http2EventKind.md`](Http2EventKind.md) |
| `Http2Event` | class | HTTP/2 事件 | [`Http2Event.md`](Http2Event.md) |
| `Http2Stream` | class | HTTP/2 流 | [`Http2Stream.md`](Http2Stream.md) |
| `Http2Session` | class | HTTP/2 会话 | [`Http2Session.md`](Http2Session.md) |
| `Form` | class | 表单 | [`Form.md`](Form.md) |
| `FormEntry` | class | 表单条目 | [`FormEntry.md`](FormEntry.md) |
| `MultipartOptions` | class | multipart 限制 | [`MultipartOptions.md`](MultipartOptions.md) |
| `MultipartPart` | class | multipart part | [`MultipartPart.md`](MultipartPart.md) |
| `MultipartForm` | class | multipart 解析 | [`MultipartForm.md`](MultipartForm.md) |
| `MultipartWriter` | class | multipart 写出 | [`MultipartWriter.md`](MultipartWriter.md) |
| `HttpAuth` | class | Basic/Bearer/解析 | [`HttpAuth.md`](HttpAuth.md) |
| `HttpCredentials` | class | Authorization 凭据 | [`HttpCredentials.md`](HttpCredentials.md) |
| `ProxyMode` | enum | 代理模式 | [`ProxyMode.md`](ProxyMode.md) |
| `HttpProxyConfig` | class | 客户端代理配置 | [`HttpProxyConfig.md`](HttpProxyConfig.md) |
| `HttpTunnel` | class | CONNECT 隧道 | [`HttpTunnel.md`](HttpTunnel.md) |
| `HttpProxyOptions` | class | 代理服务器配置 | [`HttpProxyOptions.md`](HttpProxyOptions.md) |
| `HttpProxyExchange` | class | 代理交换 | [`HttpProxyExchange.md`](HttpProxyExchange.md) |
| `HttpProxyHandler` | protocol | 代理处理入口 | [`HttpProxyHandler.md`](HttpProxyHandler.md) |
| `HttpProxyServer` | class | 代理服务器 | [`HttpProxyServer.md`](HttpProxyServer.md) |
| `Cookie` | class | Cookie 值/解析 | [`Cookie.md`](Cookie.md) |
| `SameSite` | enum | Cookie SameSite | [`SameSite.md`](SameSite.md) |
| `CookieJar` | class | 客户端 Cookie 存储 | [`CookieJar.md`](CookieJar.md) |

X：Router/Middleware、连接池高级策略。HTTP/3/QUIC 不做。

---

## 4. 顶层函数

无；HTTP 方法/版本解析使用 `HttpMethod.parse` 等静态入口（见类型文件）。

---

## 5. 技术/支撑/依赖

- 技术：HTTP/1.0/1.1 报文、头集合、chunked、keep-alive、流式 body、TLS 组合。
- 支撑：`HttpClientHandle`/`HttpServerHandle`、`http*Raw` 运行时原语、`Context`、`ByteStream`、`TlsStream`。
- 依赖：`errors`、`bytes`、`text`、`io`、`execution`、`net`、`net.uri`、`net.tls`、`net.mime`。

---

## 5.1 HTTP 版本能力矩阵

| 版本 | 能力 | 设计 |
| --- | --- | --- |
| HTTP/1.0 | 基本请求/响应；连接通常不复用 | `HttpVersion.Http10` |
| HTTP/1.1 | keep-alive、chunked、upgrade、Host | `HttpVersion.Http11` + 核心类型 |
| HTTP/2 | 多路复用、SETTINGS、流、PING/GOAWAY、HPACK | `Http2Session`/`Http2Stream` 等 |
| HTTP/3 | QUIC 传输、0-RTT | 不做；需要 QUIC 层 |

## 5.2 M5.1 实现子集与裁剪

当前 `implemented` 只覆盖 `@HttpRoute` 业务闭环所需子集：

- 已实现：`HttpMethod`、`HttpVersion`、`HttpStatus`、`HttpHeader`、`HttpHeaders`、`HttpBody`（仅缓冲字节）、`HttpRequest`、`HttpResponse`、`HttpServerOptions`、`Form`、`FormEntry`、`SameSite`、`Cookie`、`CookieJar`。
- 签名裁剪：不带 `Context`（核心 Context 未实现）。
- `HttpBody` 无 `ByteStream`：无 `stream()`/`writeTo`/`fromStream`，只做 `Bytes` + `readAll`/`readText`/`close`。
- planned：`HttpExchange`/`HttpHandler`、`HttpClient`/`HttpClientOptions`、`HttpServer`、HTTP/2、TLS、代理/CONNECT、multipart、流式 body、socket 网络栈。
- Cookie 过期只解析数字 `Max-Age`/`Expires`（`Expires` 不做 RFC HTTP-date）；`CookieJar` 只做精确 domain/path，不实现 PSL。
- `HttpHeaders.contentType/contentLength/userAgent` 已实现。

## 6. 场景

### H1：JSON 客户端

`HttpClient` → `HttpRequest(HttpMethod.Post, uri)` + headers/body → `request(ctx)` → `HttpResponse`。

### H2：HTTP 服务

`HttpServer.bind` → `serve(ctx, handler)` → `HttpExchange.respond`；每连接内部任务。

### H3：流式下载

`HttpResponse.body().stream()` → `readAll`/`copyStream` → close。

### H4：Cookie

`CookieJar.store`；`headerForRequest`；`HttpClientOptions.cookieJar`。

### H5：协议升级

`HttpExchange.upgrade("websocket")` → 裸 `ByteStream` → WebSocket 层。

### H6：取消/关闭

`Context.cancel` 或 `client.close`/`server.close`；请求返回 `Cancelled`/`Unavailable`。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| HTTP/3/QUIC | 不做；需要 QUIC 层 |
| 代理/CONNECT | 已设计 |
| Form/Multipart/Auth | 已设计 |
| Router/Middleware | 不做；应用层 |
| 连接池 | 由 `net.ConnectionPool`/客户端内部显式持有 |
| 重定向 | `HttpClientOptions` 显式开关；默认最多 5 次 |
| Cookie PSL | 不实现；X |
| 状态码 | 正常值，不是 `Err` |
| 流式 body | 持有 `ByteStream`，必须 close |
| 升级 | 返回裸流；HTTP 层停止 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@HttpRoute`、`@Header`、`@Query`、`@Body`、`@StatusCode` |
| 本包消费 | `@Value`、`@Builder`、`@Serializable`、`@JsonName` |
| 处理器 | HttpAnnotationProcessor（Resolve/Validate/Generate） |
| 生成物 | 路由表、参数绑定、状态映射、body DTO codec |
| 状态 | 领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `HttpHeader`/`HttpStatus` | `@Value` | 值语义成员 |
| `HttpRequest`/`HttpResponse` | — | 含 headers/body 引用字段；不强行 `@Value`，保留显式构造/with* |
| `HttpClientOptions`/`HttpServerOptions` | `@Builder` | 选项构造 |
| handler 方法 | `@HttpRoute` | 路由表/方法绑定 |
| handler 参数 | `@Header`/`@Query`/`@Body` | 参数绑定 |
| handler 方法 | `@StatusCode` | 响应状态 |
| body DTO | `@Serializable`/`@JsonName` | JSON 编解码 |

### 声明

```x
@Target(Method)
@Retention(Source)
@annotation HttpRoute {
    final String path
    final HttpMethod method = HttpMethod.Get
}

@Target(Parameter)
@Retention(Source)
@annotation Header {
    final String value
}

@Target(Parameter)
@Retention(Source)
@annotation Query {
    final String value
}

@Target(Parameter)
@Retention(Source)
@annotation Body {
}

@Target(Method)
@Retention(Source)
@annotation StatusCode {
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
class UserApi {
    @HttpRoute("/users/{id}", HttpMethod.Get)
    @StatusCode
    HttpResponse getUser(@Query("id") Long id, @Header("Accept") String accept) {
        // ...
    }

    @HttpRoute("/users", HttpMethod.Post)
    HttpResponse create(@Body UserDto body) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
