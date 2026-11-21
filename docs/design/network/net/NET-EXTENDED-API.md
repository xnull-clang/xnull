# XDK 网络层 X 扩展 API 设计 v1.0

| 项 | 值 |
| --- | --- |
| 文档性质 | X 扩展 API 方案；只写设计，不写代码 |
| 范围 | HTTP 深面、代理/CONNECT、HTTP/2、WebSocket 深面、UDP 高级、DNS 缓存、连接池、TLS 高级 |
| 前置 | `NET-API.md`（K 基础面） |
| 不讨论 | 编译器、FFI、运行时实现、测试脚本 |
| 状态 | preview；不承诺 K 稳定性 |

---

## 0. 定位

`NET-API.md` 冻结了 K：地址、TCP、UDP、TLS 基础、HTTP/1.1、WebSocket 基础、URI、MIME。  
本文补 X：让网络层能支撑更真实的服务端/客户端/代理/多路复用场景。

```text
K 基础面
  ├─ net.uri / net / net.tls / net.http / net.websocket / net.mime
  │
X 扩展（本文）
  ├─ HTTP：Cookie、Form、Multipart、Auth、代理、CONNECT、HTTP/2、连接池
  ├─ WebSocket：子协议、心跳、背压、压缩、自动重连
  ├─ UDP：组播、广播、connected UDP、接收时间戳
  ├─ DNS：解析器对象、缓存、TTL
  └─ TLS：mTLS、证书链、校验策略、ALPN、会话缓存
```

### 0.1 X 的共同规则

- 所有可恢复失败返回 `Result<T, Error>`；无值用 `Result<Unit, Error>`。
- 所有阻塞操作首参 `Context`；取消返回 `Cancelled`，超时返回 `Timeout`。
- 所有资源类有 `isOpen()` + 幂等 `close()`。
- 不引入全局可变状态：CookieJar、DnsResolver、ConnectionPool、WebSocketClient 都是显式对象。
- 不写代码；本文中的签名是设计符号。

---

## 1. HTTP 深面

### 1.1 `Cookie` 与 `CookieJar`

#### `SameSite`（enum）

`Strict`、`Lax`、`None`。

#### `Cookie`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Cookie(String name, String value)` | 名称/值 | 非法名 → panic |
| `parseSetCookie` | `static Result<Cookie, Error> parseSetCookie(String header)` | 解析单个 Set-Cookie | `InvalidArgument` |
| `parseCookieHeader` | `static Result<List<Cookie>, Error> parseCookieHeader(String header)` | 解析 Cookie 请求头 | `InvalidArgument` |
| `name` | `String name()` | 名称 | 无 |
| `value` | `String value()` | 值 | 无 |
| `domain` | `String domain()` | 域；无 → 空串 | 无 |
| `path` | `String path()` | 路径；无 → 空串 | 无 |
| `expiresMillis` | `Long? expiresMillis()` | 过期时间；会话 → null | 无 |
| `isSecure` | `Bool isSecure()` | Secure | 无 |
| `isHttpOnly` | `Bool isHttpOnly()` | HttpOnly | 无 |
| `sameSite` | `SameSite? sameSite()` | SameSite；未设置 → null | 无 |
| `headerValue` | `String headerValue()` | Set-Cookie 值 | 无 |
| `matches` | `Bool matches(Uri requestUri)` | 域/路径/Secure 匹配 | 无 |

#### `CookieJar`（class）

**能力**：客户端 Cookie 存储；按请求 URI 生成 Cookie 头。  
**生命周期**：可变；非线程安全；无 close；建议每客户端一个实例。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `CookieJar()` | 空 jar | 无 |
| `storeFromResponse` | `Result<Unit, Error> storeFromResponse(Uri requestUri, HttpResponse response)` | 解析 Set-Cookie 并存储 | `InvalidArgument` |
| `headerForRequest` | `String headerForRequest(Uri requestUri)` | 生成 Cookie 头；无 → 空串 | 无 |
| `cookies` | `List<Cookie> cookies()` | 快照 | 无 |
| `removeExpired` | `Int removeExpired(Long nowMillis)` | 删除过期；返回数量 | 无 |
| `clear` | `void clear()` | 清空 | 无 |
| `length` | `Int length()` | 数量 | 无 |

规则：

- 域匹配不实现公共后缀表（PSL）；应用可用 `CookiePolicy`（X）接管。
- `Secure` Cookie 只对 `https` 返回。
- `HttpOnly` 只影响客户端脚本（不适用于 XDK）；仍保留标志。
- `SameSite` 只保留值，不自动决定跨站策略；应用/HTTP 客户端可配置。

#### `CookiePolicy`（class，X）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `accept` | `Bool accept(Uri requestUri, Cookie cookie)` | 是否接受 |
| `headerFor` | `String headerFor(Uri requestUri, List<Cookie> cookies)` | 自定义头 |

`HttpClientOptions.cookieJar(CookieJar)` / `cookiePolicy(CookiePolicy)` 接入。

---

### 1.2 `Form`（application/x-www-form-urlencoded）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Form()` | 空表单 | 无 |
| `parse` | `static Result<Form, Error> parse(String text)` | 解析 `a=1&b=2` | `DataCorrupted` |
| `set` | `void set(String name, String value)` | 设置/覆盖 | 非法名 → panic |
| `add` | `void add(String name, String value)` | 追加多值 | 非法名 → panic |
| `get` | `String? get(String name)` | 首个值；无 → null | 无 |
| `getOr` | `String getOr(String name, String fallback)` | 无 → fallback | 无 |
| `getAll` | `List<String> getAll(String name)` | 全部值 | 无 |
| `remove` | `Bool remove(String name)` | 删除 | 无 |
| `entries` | `List<FormEntry> entries()` | 快照 | 无 |
| `encode` | `String encode()` | URL 编码 | 无 |
| `toBody` | `HttpBody toBody()` | `application/x-www-form-urlencoded` body | 无 |

`FormEntry`（class）：

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `name` | `String name()` | 字段名 |
| `value` | `String value()` | 字段值 |

---

### 1.3 Multipart

#### `MultipartOptions`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `MultipartOptions()` | 默认 |
| `maxParts` | `MultipartOptions maxParts(Int count)` | 最大 part 数 |
| `maxPartBytes` | `MultipartOptions maxPartBytes(Long bytes)` | 单 part 上限 |
| `maxTotalBytes` | `MultipartOptions maxTotalBytes(Long bytes)` | 总上限 |
| `memoryThreshold` | `MultipartOptions memoryThreshold(Long bytes)` | 超过后落临时文件（X） |

#### `MultipartPart`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `name` | `String name()` | 表单名 |
| `fileName` | `String? fileName()` | 文件名；无 → null |
| `headers` | `HttpHeaders headers()` | part 头 |
| `body` | `HttpBody body()` | 内容 |
| `size` | `Long? size()` | 已知大小；未知 → null |
| `close` | `Result<Unit, Error> close()` | 释放 body |

#### `MultipartForm`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `parse` | `static Result<MultipartForm, Error> parse(Context context, HttpRequest request, MultipartOptions options)` | 解析 multipart | `InvalidArgument`/`DataCorrupted`/`Cancelled` |
| `parts` | `List<MultipartPart> parts()` | 快照 | 无 |
| `get` | `MultipartPart? get(String name)` | 按名查找 | 无 |
| `getAll` | `List<MultipartPart> getAll(String name)` | 多值 | 无 |
| `close` | `Result<Unit, Error> close()` | 关闭全部 part body | `Io`（诊断） |

#### `MultipartWriter`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `MultipartWriter(ByteStream target, String boundary)` | 写入目标流 | 非法 boundary → panic |
| `addPart` | `Result<Unit, Error> addPart(String name, HttpHeaders headers, HttpBody body)` | 添加 part | `Io`/`Cancelled` |
| `addFile` | `Result<Unit, Error> addFile(String name, String fileName, MediaType type, HttpBody body)` | 添加文件 part | 同上 |
| `finish` | `Result<Unit, Error> finish()` | 写结束边界 | 同上 |
| `close` | `Result<Unit, Error> close()` | 关闭；幂等 | `Io`（诊断） |

---

### 1.4 `HttpAuth`

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `basic` | `static String basic(String username, String password)` | Basic 头值 | 无 |
| `bearer` | `static String bearer(String token)` | Bearer 头值 | 无 |
| `parse` | `static Result<HttpCredentials, Error> parse(String header)` | 解析 Authorization | `InvalidArgument` |
| `scheme` | `String scheme()` | 方案名（`basic`/`bearer`/自定义） | 无 |
| `parameter` | `String? parameter(String name)` | 参数；无 → null | 无 |

`HttpCredentials`（class）：

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `scheme` | `String scheme()` | 方案名 |
| `parameter` | `String? parameter(String name)` | 参数；无 → null |
| `parameters` | `Map<String, String> parameters()` | 参数快照 |

`HttpCredentials` 只保存方案与参数；不自动附加到请求，调用方显式设置头。

---

### 1.5 代理与 CONNECT

#### `ProxyMode`（enum）

`Forward`、`Reverse`、`Tunnel`。

#### `HttpProxyConfig`（class，客户端代理配置）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `HttpProxyConfig(Uri proxyUri)` | 代理地址 |
| `withBasicAuth` | `HttpProxyConfig withBasicAuth(String username, String password)` | Proxy-Authorization |
| `withHeader` | `HttpProxyConfig withHeader(String name, String value)` | 额外头 |
| `withNoProxy` | `HttpProxyConfig withNoProxy(List<String> hosts)` | 直连列表 |
| `withConnectTimeout` | `HttpProxyConfig withConnectTimeout(Duration timeout)` | 隧道连接超时 |
| `mode` | `ProxyMode mode()` | 代理模式 |

#### `HttpTunnel`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `connect` | `static Result<ByteStream, Error> connect(Context context, ByteStream transport, SocketAddress target, HttpProxyConfig config)` | 发 CONNECT，返回隧道流 | `Network`/`PermissionDenied`/`Timeout`/`Cancelled`/`DataCorrupted` |

- 成功后 `transport` 归 `ByteStream` 所有；失败时调用方关闭 `transport`。
- 返回的流是裸字节流；TLS/HTTP 可以继续在其上组合。

#### `HttpProxyServer`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `bind` | `static Result<HttpProxyServer, Error> bind(Context context, SocketAddress local, HttpProxyOptions options)` | 绑定代理 | `InvalidArgument`/`PermissionDenied`/`Network` |
| `serve` | `Result<Unit, Error> serve(Context context, HttpProxyHandler handler)` | 接受循环 | `Cancelled`/`Unavailable`/`Network` |
| `localAddress` | `SocketAddress localAddress()` | 实际地址 | 无 |
| `isOpen` | `Bool isOpen()` | 是否监听 | 无 |
| `close` | `Result<Unit, Error> close()` | 停止；幂等 | `Io`（诊断） |

#### `HttpProxyOptions`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `HttpProxyOptions()` | 默认 |
| `allowTarget` | `HttpProxyOptions allowTarget(String hostPattern, Int port)` | 允许目标 |
| `maxConnections` | `HttpProxyOptions maxConnections(Int count)` | 最大连接 |
| `connectTimeout` | `HttpProxyOptions connectTimeout(Duration timeout)` | 上游连接超时 |
| `idleTimeout` | `HttpProxyOptions idleTimeout(Duration timeout)` | 空闲超时 |
| `requireAuth` | `HttpProxyOptions requireAuth(String username, String password)` | 代理认证 |
| `logger` | `HttpProxyOptions logger(Logger logger)` | 诊断日志 |

#### `HttpProxyExchange`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `request` | `HttpRequest request()` | 代理请求 | 无 |
| `forward` | `Result<HttpResponse, Error> forward(Context context, Uri target)` | 转发普通 HTTP 请求 | `Network`/`Timeout`/`Cancelled` |
| `openTunnel` | `Result<ByteStream, Error> openTunnel(Context context, SocketAddress target)` | CONNECT 隧道 | 同上 |
| `respond` | `Result<Unit, Error> respond(HttpResponse response)` | 返回代理错误/响应 | `Io`/`Cancelled` |
| `close` | `Result<Unit, Error> close()` | 关闭交换 | `Io`（诊断） |

#### `HttpProxyHandler`（protocol）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `handle` | `Result<Unit, Error> handle(Context context, HttpProxyExchange exchange)` | 处理一次代理 |

- Handler 负责 `forward` 或 `openTunnel` 或 `respond`。
- 必须关闭 `forward` 返回的 `HttpResponse.body`。

---

### 1.6 HTTP/2

#### `Http2Settings`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `Http2Settings()` | 默认设置 |
| `headerTableSize` | `Http2Settings headerTableSize(Int bytes)` | HPACK 表 |
| `enablePush` | `Http2Settings enablePush(Bool enabled)` | 服务端推送 |
| `maxConcurrentStreams` | `Http2Settings maxConcurrentStreams(Int count)` | 并发流 |
| `initialWindowSize` | `Http2Settings initialWindowSize(Int bytes)` | 初始窗口 |
| `maxFrameSize` | `Http2Settings maxFrameSize(Int bytes)` | 最大帧 |
| `maxHeaderListSize` | `Http2Settings maxHeaderListSize(Int bytes)` | 最大头 |

#### `Http2ErrorCode`（enum）

`NoError`、`ProtocolError`、`InternalError`、`FlowControlError`、`SettingsTimeout`、`StreamClosed`、`FrameSizeError`、`RefusedStream`、`Cancel`、`CompressionError`、`ConnectError`、`EnhanceYourCalm`、`InadequateSecurity`、`Http11Required`。

#### `Http2StreamState`（enum）

`Idle`、`ReservedLocal`、`ReservedRemote`、`Open`、`HalfClosedLocal`、`HalfClosedRemote`、`Closed`。

#### `Http2EventKind`（enum）

`Headers`、`Data`、`EndStream`、`Reset`、`WindowUpdate`、`GoAway`。

#### `Http2Event`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `kind` | `Http2EventKind kind()` | 事件类型 |
| `headers` | `HttpHeaders? headers()` | Headers 事件 |
| `data` | `Bytes? data()` | Data 事件 |
| `errorCode` | `Http2ErrorCode? errorCode()` | Reset/GoAway |
| `windowSize` | `Int? windowSize()` | WindowUpdate |

#### `Http2Stream`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `id` | `Int id()` | 流 ID | 无 |
| `state` | `Http2StreamState state()` | 状态 | 无 |
| `sendHeaders` | `Result<Unit, Error> sendHeaders(Context context, HttpHeaders headers, Bool endStream)` | 发送头 | `Unavailable`/`Cancelled`/`Network` |
| `sendData` | `Result<Unit, Error> sendData(Context context, Bytes data, Bool endStream)` | 发送数据（受流控） | 同上 |
| `receive` | `Result<Http2Event, Error> receive(Context context)` | 接收事件 | 同上 |
| `reset` | `Result<Unit, Error> reset(Http2ErrorCode code)` | RST_STREAM | `Unavailable` |
| `close` | `Result<Unit, Error> close()` | 关闭流 | `Io`（诊断） |

#### `Http2Session`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `connect` | `static Result<Http2Session, Error> connect(Context context, ByteStream transport, Http2Settings settings)` | 客户端会话 | `Network`/`DataCorrupted`/`Timeout`/`Cancelled` |
| `accept` | `static Result<Http2Session, Error> accept(Context context, ByteStream transport, Http2Settings settings)` | 服务端会话 | 同上 |
| `newStream` | `Result<Http2Stream, Error> newStream(Context context)` | 新建流 | `Unavailable`/`Network` |
| `sendSettings` | `Result<Unit, Error> sendSettings(Context context, Http2Settings settings)` | 发送设置 | `Network` |
| `ping` | `Result<Unit, Error> ping(Context context, Bytes payload)` | PING | 同上 |
| `goAway` | `Result<Unit, Error> goAway(Http2ErrorCode code, String debugData)` | GOAWAY | 同上 |
| `peerSettings` | `Http2Settings peerSettings()` | 对端设置 | 无 |
| `state` | `Http2SessionState state()` | 会话状态 | 无 |
| `isOpen` | `Bool isOpen()` | 是否打开 | 无 |
| `close` | `Result<Unit, Error> close()` | 关闭；幂等 | `Io`（诊断） |

`Http2SessionState`（enum）：`Connecting`、`Open`、`Closing`、`Closed`。

#### HTTP 客户端/服务端接入

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `HttpClientOptions.http2` | `HttpClientOptions http2(Bool enabled)` | ALPN 协商 h2 |
| `HttpClientOptions.pool` | `HttpClientOptions pool(ConnectionPool pool)` | 连接池 |
| `HttpServerOptions.http2` | `HttpServerOptions http2(Bool enabled)` | TLS ALPN h2 |
| `HttpServerOptions.http2Settings` | `HttpServerOptions http2Settings(Http2Settings settings)` | H2 设置 |

- HTTP/2 只通过 TLS ALPN 启用；h2c（明文）为 X 的 X，不默认。
- `HttpClient`/`HttpServer` 对调用方仍暴露 `HttpRequest`/`HttpResponse`；H2 细节不泄漏。
- `Http2Session`/`Http2Stream` 是给需要自定义协议/调试的高级 API。

---

### 1.7 连接池

#### `PoolKey`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `PoolKey(String scheme, SocketAddress address)` | 连接键 |
| `scheme` | `String scheme()` | `http`/`https`/`tcp`/`tls` |
| `address` | `SocketAddress address()` | 目标地址 |
| `equals` | `Bool equals(PoolKey other)` | 值相等 |

#### `ConnectionPoolOptions`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `ConnectionPoolOptions()` | 默认 |
| `maxTotal` | `ConnectionPoolOptions maxTotal(Int count)` | 总连接上限 |
| `maxPerKey` | `ConnectionPoolOptions maxPerKey(Int count)` | 每目标上限 |
| `idleTimeout` | `ConnectionPoolOptions idleTimeout(Duration timeout)` | 空闲回收 |
| `maxLifetime` | `ConnectionPoolOptions maxLifetime(Duration lifetime)` | 最大寿命 |
| `connectTimeout` | `ConnectionPoolOptions connectTimeout(Duration timeout)` | 建连超时 |
| `healthCheck` | `ConnectionPoolOptions healthCheck(Bool enabled)` | 健康检查 |

#### `PooledConnection`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `stream` | `ByteStream stream()` | 底层连接 |
| `key` | `PoolKey key()` | 连接键 |
| `isReused` | `Bool isReused()` | 是否复用 |
| `ageMillis` | `Long ageMillis()` | 已存活时间 |
| `release` | `Result<Unit, Error> release()` | 归还池 |
| `close` | `Result<Unit, Error> close()` | 直接关闭（不归还） |

#### `ConnectionPool`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `ConnectionPool(ConnectionPoolOptions options)` | 创建池 | 无 |
| `acquire` | `Result<PooledConnection, Error> acquire(Context context, PoolKey key)` | 取连接/建连 | `Network`/`Timeout`/`Cancelled`/`Busy` |
| `release` | `Result<Unit, Error> release(PooledConnection connection)` | 归还 | `InvalidArgument` |
| `stats` | `ConnectionPoolStats stats()` | 统计 | 无 |
| `close` | `Result<Unit, Error> close()` | 关闭全部；幂等 | `Io`（诊断） |

#### `ConnectionPoolStats`（class）

`total()`、`idle()`、`active()`、`waiting()`、`reused()`、`created()`。

---

### 1.8 DNS 解析器与缓存

#### `DnsRecord`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `address` | `IpAddress address()` | 地址 |
| `ttlSeconds` | `Long ttlSeconds()` | TTL |
| `expiresAtMillis` | `Long expiresAtMillis()` | 过期时间 |

#### `DnsResolverOptions`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `DnsResolverOptions()` | 默认（系统解析器） |
| `servers` | `DnsResolverOptions servers(List<SocketAddress> servers)` | 自定义 DNS |
| `timeout` | `DnsResolverOptions timeout(Duration timeout)` | 查询超时 |
| `maxCacheEntries` | `DnsResolverOptions maxCacheEntries(Int count)` | 缓存上限 |
| `positiveTtl` | `DnsResolverOptions positiveTtl(Duration ttl)` | 正向缓存 |
| `negativeTtl` | `DnsResolverOptions negativeTtl(Duration ttl)` | 负缓存 |
| `family` | `DnsResolverOptions family(IpFamily family)` | 地址族偏好 |
| `searchDomains` | `DnsResolverOptions searchDomains(List<String> domains)` | 搜索域 |
| `backgroundRefresh` | `DnsResolverOptions backgroundRefresh(Bool enabled)` | 临近过期刷新 |

#### `DnsCacheStats`（class）

`entries()`、`hits()`、`misses()`、`evictions()`。

#### `DnsResolver`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `DnsResolver()` | 系统解析器 + 默认缓存 | 无 |
| 构造 | `DnsResolver(DnsResolverOptions options)` | 自定义 | 无 |
| `resolve` | `Result<List<DnsRecord>, Error> resolve(Context context, String host)` | 正向解析（带缓存） | `NotFound`/`Network`/`Timeout`/`Cancelled` |
| `resolveOne` | `Result<IpAddress, Error> resolveOne(Context context, String host, IpFamily family)` | 首个匹配 | 同上 |
| `reverse` | `Result<String, Error> reverse(Context context, IpAddress address)` | 反向解析 | 同上 |
| `clearCache` | `void clearCache()` | 清空 | 无 |
| `cacheStats` | `DnsCacheStats cacheStats()` | 统计 | 无 |
| `isOpen` | `Bool isOpen()` | 是否可用 | 无 |
| `close` | `Result<Unit, Error> close()` | 停止后台刷新/释放 | `Io`（诊断） |

- 无全局缓存；`DnsResolver` 实例可注入 `HttpClientOptions.dnsResolver`。
- 负缓存只缓存 `NotFound`，不缓存 `Timeout`/`Cancelled`。

---

## 2. WebSocket 深面

### 2.1 `WebSocketCompression`（enum）

`None`、`PermessageDeflate`。

### 2.2 `WebSocketOptions` 扩展

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `subprotocols` | `WebSocketOptions subprotocols(List<String> protocols)` | 子协议列表 |
| `maxFrameBytes` | `WebSocketOptions maxFrameBytes(Long bytes)` | 单帧上限 |
| `maxMessageBytes` | `WebSocketOptions maxMessageBytes(Long bytes)` | 消息上限 |
| `maxSendQueueBytes` | `WebSocketOptions maxSendQueueBytes(Long bytes)` | 发送队列上限 |
| `pingInterval` | `WebSocketOptions pingInterval(Duration interval)` | 自动心跳 |
| `pongTimeout` | `WebSocketOptions pongTimeout(Duration timeout)` | Pong 超时 |
| `closeTimeout` | `WebSocketOptions closeTimeout(Duration timeout)` | 关闭握手超时 |
| `compression` | `WebSocketOptions compression(WebSocketCompression mode)` | 压缩 |
| `header` | `WebSocketOptions header(String name, String value)` | 额外头 |
| `origin` | `WebSocketOptions origin(String origin)` | Origin |
| `tlsConfig` | `WebSocketOptions tlsConfig(TlsConfig config)` | wss |

### 2.3 `WebSocketStats`（class）

`messagesSent()`、`messagesReceived()`、`bytesSent()`、`bytesReceived()`、`pingsSent()`、`pongsReceived()`、`sendQueueBytes()`、`lastPongMillis()`。

### 2.4 `WebSocket` 扩展

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `trySendText` | `Result<Unit, Error> trySendText(Context context, String text)` | 队列满 → `Busy` | `Busy`/`Unavailable`/`Cancelled` |
| `trySendBinary` | `Result<Unit, Error> trySendBinary(Context context, Bytes data)` | 队列满 → `Busy` | 同上 |
| `sendQueueBytes` | `Long sendQueueBytes()` | 当前队列字节 | 无 |
| `stats` | `WebSocketStats stats()` | 统计快照 | 无 |
| `setPingInterval` | `Result<Unit, Error> setPingInterval(Duration interval)` | 动态心跳 | `InvalidArgument`/`Unavailable` |
| `setPongTimeout` | `Result<Unit, Error> setPongTimeout(Duration timeout)` | Pong 超时 | 同上 |
| `subprotocol` | `String? subprotocol()` | 协商子协议 | 无 |

**背压规则**：

- `sendText/sendBinary` 在队列满时阻塞，直到有空间或 `Context` 取消。
- `trySend*` 在队列满时立即返回 `Busy`，不阻塞。
- `maxSendQueueBytes` 是硬上限；超过时 `send*` 阻塞/`trySend*` 返回 `Busy`。
- 关闭/取消时，未发送队列丢弃；发送方收到 `Unavailable`/`Cancelled`。

**心跳规则**：

- `pingInterval` 非 0 时自动发送 Ping；`pongTimeout` 内未收到 Pong 则关闭连接并标记 `GoingAway`/`PolicyViolation`（由应用选择）。
- `receive` 仍可返回 Ping/Pong；调用方可以忽略。
- 心跳不阻塞应用 `receive`；内部定时器由实现管理。

### 2.5 `WebSocketClient`（class，X）

**能力**：客户端自动重连/退避；适合推送/订阅长连接。  
**生命周期**：显式 `close()`；重连期间状态可见。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `WebSocketClient(WebSocketOptions options, ReconnectPolicy policy)` | 创建客户端 | 无 |
| `connect` | `Result<Unit, Error> connect(Context context, Uri uri)` | 首次连接 | `Network`/`PermissionDenied`/`DataCorrupted`/`Timeout`/`Cancelled` |
| `socket` | `WebSocket? socket()` | 当前连接；未连接 → null | 无 |
| `state` | `WebSocketClientState state()` | 状态 | 无 |
| `reconnect` | `Result<Unit, Error> reconnect(Context context)` | 主动重连 | 同上 |
| `close` | `Result<Unit, Error> close()` | 停止重连并关闭 | `Io`（诊断） |

`WebSocketClientState`（enum）：`Idle`、`Connecting`、`Open`、`Backoff`、`Closed`。

### 2.6 `ReconnectPolicy`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `ReconnectPolicy()` | 默认 |
| `initialDelay` | `ReconnectPolicy initialDelay(Duration delay)` | 首次退避 |
| `maxDelay` | `ReconnectPolicy maxDelay(Duration delay)` | 最大退避 |
| `multiplier` | `ReconnectPolicy multiplier(Double factor)` | 退避倍数 |
| `maxAttempts` | `ReconnectPolicy maxAttempts(Int count)` | 最大次数；0 = 无限 |
| `jitter` | `ReconnectPolicy jitter(Double ratio)` | 抖动 |

- 重连只重建连接，不重放未确认消息；消息重放由应用/队列负责。
- 取消 `Context` 立即停止退避。

---

## 3. UDP 高级

### 3.1 `MulticastOptions`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `MulticastOptions()` | 默认 |
| `interfaceName` | `MulticastOptions interfaceName(String name)` | 网卡 |
| `loopback` | `MulticastOptions loopback(Bool enabled)` | 本机回环 |
| `ttl` | `MulticastOptions ttl(Int ttl)` | 组播 TTL |

### 3.2 `UdpSocket` 扩展

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `joinMulticast` | `Result<Unit, Error> joinMulticast(Context context, IpAddress group, MulticastOptions options)` | 加入组播 | `InvalidArgument`/`Unsupported`/`Network` |
| `leaveMulticast` | `Result<Unit, Error> leaveMulticast(Context context, IpAddress group, MulticastOptions options)` | 离开组播 | 同上 |
| `setBroadcast` | `Result<Unit, Error> setBroadcast(Bool enabled)` | 广播开关 | `Unsupported`/`Network` |
| `connect` | `Result<Unit, Error> connect(Context context, SocketAddress remote)` | connected UDP | `Network`/`Timeout`/`Cancelled` |
| `send` | `Result<Unit, Error> send(Context context, Bytes data)` | connected UDP 发送 | `Unavailable`/`Network`/`Timeout`/`Cancelled` |
| `receive` | `Result<Datagram, Error> receive(Context context, Int maximumBytes)` | connected UDP 接收 | 同上 |

### 3.3 `Datagram` 扩展

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `receivedAtMono` | `Long receivedAtMono()` | 接收单调时间；发送构造 → 0 |
| `interfaceIndex` | `Int interfaceIndex()` | 接收网卡索引；未知 → -1 |

---

## 4. TLS 高级

### 4.1 `ClientAuthMode`（enum）

`None`、`Request`、`Require`。

### 4.2 `CertificateVerification`（enum）

`System`、`TrustStore`、`None`。

### 4.3 `TlsConfig` 扩展

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `withServerCertificateChain` | `TlsConfig withServerCertificateChain(List<Certificate> chain, PrivateKey privateKey)` | 服务端证书链 |
| `withClientAuth` | `TlsConfig withClientAuth(ClientAuthMode mode)` | 服务端要求客户端证书 |
| `withCertificateVerification` | `TlsConfig withCertificateVerification(CertificateVerification mode)` | 校验策略 |
| `withSessionCacheSize` | `TlsConfig withSessionCacheSize(Int entries)` | 会话缓存 |
| `withAlpn` | `TlsConfig withAlpn(List<String> protocols)` | ALPN（已有） |
| `withMinVersion` / `withMaxVersion` | `TlsConfig ...` | 版本范围（已有） |

### 4.4 `TlsStream` / `TlsSessionInfo` 扩展

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `peerCertificates` | `List<Certificate> peerCertificates()` | 对端证书链 |
| `alpnProtocol` | `String? alpnProtocol()` | 协商 ALPN；无 → null |
| `isResumed` | `Bool isResumed()` | 会话恢复（已有） |

**规则**：

- `CertificateVerification.None` 必须显式设置；默认 `System`。
- `ClientAuthMode.Require` 时，无客户端证书 → `PermissionDenied`。
- 证书/私钥不得出现在日志/错误消息；`describe()` 只给主题/指纹。

---

## 5. MIME 扩展

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `MediaType.withParameter` | `MediaType withParameter(String name, String value)` | 派生新类型 |
| `MediaType.isFormUrlEncoded` | `Bool isFormUrlEncoded()` | `application/x-www-form-urlencoded` |
| `MediaType.isMultipart` | `Bool isMultipart()` | `multipart/*` |
| `MimeTypes.json` | `static MediaType json()` | `application/json` |
| `MimeTypes.text` | `static MediaType text()` | `text/plain; charset=utf-8` |
| `MimeTypes.octetStream` | `static MediaType octetStream()` | `application/octet-stream` |
| `MimeTypes.formUrlEncoded` | `static MediaType formUrlEncoded()` | 表单 |
| `MimeTypes.multipartFormData` | `static MediaType multipartFormData()` | multipart |

---

## 6. API 决策

| # | 决策 | 理由 |
| --- | --- | --- |
| X1 | CookieJar 显式对象，无全局 cookie | 避免隐式全局状态 |
| X2 | Multipart 支持流式 + 上限；大文件落临时文件是 X | 防止内存爆炸 |
| X3 | 代理分客户端配置 (`HttpProxyConfig`) 与服务端 (`HttpProxyServer`) | 两个方向的 API 不混 |
| X4 | CONNECT 返回裸 `ByteStream` | TLS/HTTP 可继续组合 |
| X5 | HTTP/2 只通过 TLS ALPN；h2c 为 X | 先保证安全/兼容 |
| X6 | `Http2Session` 是高级 API；普通用户用 `HttpClient/Server` | 不把帧细节泄漏给应用 |
| X7 | 连接池显式对象，无全局池 | 可测试/可注入 |
| X8 | DNS 解析器实例化，有无缓存由选项决定 | 避免隐式缓存 |
| X9 | WebSocket 背压用 `send` 阻塞 + `trySend` Busy | 不丢消息、不无限堆积 |
| X10 | WebSocket 自动重连只重连，不重放 | 消息语义由应用决定 |
| X11 | UDP 组播/广播显式 API | 避免“默认开启”带来的安全/网络问题 |
| X12 | TLS `None` 校验必须显式 | 安全默认 |

---

## 7. 评审清单

- [ ] Cookie 域/路径/Secure/SameSite 规则明确。
- [ ] Multipart 有 part/总量/内存上限，流式 body 所有权明确。
- [ ] 代理 CONNECT 成功/失败时底层流传所有权明确。
- [ ] HTTP/2 流控/GOAWAY/Reset 的取消语义明确。
- [ ] 连接池 acquire/release/close 的竞态与幂等明确。
- [ ] DNS 正/负缓存 TTL、取消、关闭语义明确。
- [ ] WebSocket 心跳/背压/关闭/重连语义明确。
- [ ] UDP 组播/广播/connected 的失败分类明确。
- [ ] TLS mTLS/证书链/校验策略不泄漏私钥。
- [ ] 所有 X 不改变 K 的公共语义；不冒充 stable。
