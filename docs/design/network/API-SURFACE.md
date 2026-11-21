# `xdk.net` API 面

> 当前领域设计见 [`README.md`](README.md)；本文件列出 net 的 API 广度与方法面，不声明当前目录/顺序。
>
> JWT 与 SQL 不在本文件的 net API 广度内，分别见 [`jwt/README.md`](jwt/README.md)、[`sql/README.md`](sql/README.md)。


| 项 | 值 |
| --- | --- |
| 范围 | `net.uri`、`net`、`net.tls`、`net.http`、`net.websocket`、`net.mime` |
| 目标 | 对齐 Go net/http、Netty、Node、.NET、Python asyncio 的常规能力面 |
| 规则 | 只写方案；不写代码；不讨论编译器/FFI |
| 记号 | `K` = 基础面；`X` = 扩展面；`—` = 不在网络层 |

---

## 0. 通用规则

- 所有可阻塞 API 首参 `Context`；取消 `Cancelled`，超时 `Timeout`。
- 所有资源类：`isOpen()` + 幂等 `close()`。
- HTTP 状态码不是 `Err`；WebSocket 正常关闭不是 `Err`。
- 网络层不实现 Web 框架/消息队列/数据库驱动。
- 不提供全局连接池、全局 DNS 缓存、全局 CookieJar。

---

## 1. `xdk.net.uri`

**职责**：URI/URL 解析、构造、查询串、百分号编码。  
**业界对齐**：Go `net/url`、Java `URI`、Python `urllib.parse`、.NET `Uri`。

### 1.1 类型

`Uri`、`UriBuilder`、`Query`、`Url`、`PercentCodec`、`UriTemplate`（X）。

### 1.2 `Uri`

| 能力组 | 方法 |
| --- | --- |
| 构造/解析 | `Uri.parse(text)`、`Uri.of(scheme,host,port,path,query,fragment)`、`Uri.fromParts(...)` |
| 读取 | `scheme()`、`userInfo()`、`host()`、`port()`、`authority()`、`path()`、`query()`、`fragment()`、`isAbsolute()`、`isHierarchical()`、`text()`、`toString()` |
| 查询 | `queryParams()`、`queryParam(name)`、`queryParams(name)`、`hasQuery()` |
| 派生 | `withScheme`、`withUserInfo`、`withHost`、`withPort`、`withPath`、`withQuery`、`withQueryParams`、`withFragment`、`normalize()`、`resolve(reference)`、`relativize(base)` |
| 判定 | `equals(other)`、`compare(other)`、`startsWith(prefix)`、`endsWith(suffix)` |

### 1.3 `UriBuilder`

`UriBuilder()`、`scheme`、`userInfo`、`host`、`port`、`path`、`pathSegment`、`query`、`queryParam`、`fragment`、`build()`、`reset()`。

### 1.4 `Query`

`Query.parse(text)`、`Query()`、`add(name,value)`、`set(name,value)`、`get(name)`、`getOr`、`getAll(name)`、`remove(name)`、`has(name)`、`entries()`、`length()`、`encode()`、`clear()`。

### 1.5 `Url` / `PercentCodec`

`Url.parse(text)`、`scheme`、`host`、`port`、`path`、`query`、`fragment`、`isHttps`、`toUri()`。  
`PercentCodec`：`encode(text)`、`encodeComponent(text)`、`decode(text)`、`decodeComponent(text)`、`queryEncode`、`queryDecode`、`pathEncode`、`pathDecode`。

### 1.6 `UriTemplate`（X）

`UriTemplate.parse(template)`、`expand(values)`、`match(uri)`、`variables()`。

---

## 2. `xdk.net`

**职责**：IP、前缀、Socket 地址、DNS、字节流、TCP、UDP、连接池、网卡。  
**业界对齐**：Go `net`、Java NIO、Python `socket/asyncio`、.NET `Socket`。

### 2.1 类型

`IpFamily`、`IpAddress`、`IpPrefix`、`SocketAddress`、`DnsRecord`、`DnsResolver`、`DnsResolverOptions`、`DnsCacheStats`、`ByteStream`、`TcpListener`、`TcpStream`、`UdpSocket`、`Datagram`、`SocketOptions`、`MulticastOptions`、`ShutdownMode`、`NetworkInterface`、`ConnectionPool`、`PoolKey`、`PooledConnection`、`ConnectionPoolOptions`、`ConnectionPoolStats`。

### 2.2 `IpAddress`

`IpAddress.parse(text)`、`IpAddress.loopback(family)`、`IpAddress.any(family)`、`family()`、`text()`、`bytes()`、`isLoopback()`、`isUnspecified()`、`isMulticast()`、`isPrivate()`、`isLinkLocal()`、`isGlobal()`、`toIpv4()`、`toIpv6()`、`compare(other)`、`equals(other)`、`toString()`。

### 2.3 `IpPrefix`

`IpPrefix.parse(text)`、`IpPrefix(address,prefixLength)`、`address()`、`prefixLength()`、`network()`、`broadcast()`、`contains(address)`、`containsPrefix(prefix)`、`text()`、`equals(other)`。

### 2.4 `SocketAddress`

`SocketAddress(address,port)`、`SocketAddress.parse(text)`、`address()`、`port()`、`text()`、`equals(other)`、`compare(other)`、`toString()`。

### 2.5 `DnsResolver`

| 能力组 | 方法 |
| --- | --- |
| 构造 | `DnsResolver()`、`DnsResolver(options)`、`close()`、`isOpen()` |
| 查询 | `resolve(Context,host)`、`resolveAll(Context,host)`、`resolveOne(Context,host,family)`、`resolveRecords(Context,host)`、`reverse(Context,address)`、`lookup(Context,host,type)`（X） |
| 缓存 | `clearCache()`、`cacheStats()`、`preload(records)` |
| 配置 | `options()`、`setOptions(options)` |

`DnsRecord`：`address()`、`ttlSeconds()`、`expiresAtMillis()`、`isExpired(now)`。  
`DnsResolverOptions`：`servers`、`timeout`、`maxCacheEntries`、`positiveTtl`、`negativeTtl`、`family`、`searchDomains`、`backgroundRefresh`、`recursionDesired`、`edns`（X）。  
`DnsCacheStats`：`entries`、`hits`、`misses`、`evictions`、`negativeEntries`。

### 2.6 `ByteStream`

`read(Context,buffer)`、`readExact(Context,count)`、`readAll(Context)`、`write(Context,data)`、`writeAll(Context,data)`、`copyTo(Context,target)`、`setReadDeadline(deadline)`、`setWriteDeadline(deadline)`、`isOpen()`、`close()`。

### 2.7 `TcpListener`

`TcpListener.bind(Context,local)`、`bind(Context,local,options)`、`accept(Context)`、`acceptDeadline(Context,deadline)`、`localAddress()`、`isOpen()`、`setReuseAddress(bool)`、`close()`。

### 2.8 `TcpStream`

| 能力组 | 方法 |
| --- | --- |
| 连接 | `TcpStream.connect(Context,address)`、`connect(Context,host,port)`、`connect(Context,address,options)` |
| 读 | `read`、`readExact`、`readAll`、`readInto`、`peek`（X） |
| 写 | `write`、`writeAll`、`flush`（no-op/底层） |
| 关闭 | `shutdown(mode)`、`close()`、`isOpen()` |
| 地址 | `localAddress()`、`remoteAddress()` |
| 选项 | `setNoDelay`、`setKeepAlive`、`setReadBuffer`、`setWriteBuffer`、`setReadDeadline`、`setWriteDeadline`、`setLinger`（X） |
| 状态 | `isReadable()`、`isWritable()`、`state()`（X） |

### 2.9 `UdpSocket`

`UdpSocket.bind(Context,local)`、`bind(Context,local,options)`、`sendTo(Context,datagram)`、`receiveFrom(Context,maximumBytes)`、`send(Context,data)`（connected）、`receive(Context,maximumBytes)`（connected）、`connect(Context,remote)`、`disconnect()`、`joinMulticast(Context,group,options)`、`leaveMulticast(Context,group,options)`、`setBroadcast(bool)`、`localAddress()`、`isOpen()`、`close()`。

### 2.10 `Datagram` / `SocketOptions` / `MulticastOptions` / `ShutdownMode`

`Datagram`：`Datagram(data,remote)`、`data()`、`remote()`、`local()`、`length()`、`isTruncated()`、`receivedAtMono()`、`interfaceIndex()`。  
`SocketOptions`：`reuseAddress`、`noDelay`、`keepAlive`、`receiveBuffer`、`sendBuffer`、`readTimeout`、`writeTimeout`、`linger`（X）。  
`MulticastOptions`：`interfaceName`、`loopback`、`ttl`、`blockSource`（X）。  
`ShutdownMode`：`Read`、`Write`、`Both`。

### 2.11 `NetworkInterface`（X）

`NetworkInterface.list()`、`name()`、`displayName()`、`addresses()`、`isUp()`、`isLoopback()`、`isMulticast()`、`mtu()`、`hardwareAddress()`。

### 2.12 连接池

`PoolKey`：`PoolKey(scheme,address)`、`scheme()`、`address()`、`equals()`。  
`ConnectionPoolOptions`：`maxTotal`、`maxPerKey`、`idleTimeout`、`maxLifetime`、`connectTimeout`、`healthCheck`、`waitTimeout`。  
`PooledConnection`：`stream()`、`key()`、`isReused()`、`ageMillis()`、`release()`、`close()`。  
`ConnectionPool`：`ConnectionPool(options)`、`acquire(Context,key)`、`release(connection)`、`stats()`、`close()`、`isOpen()`。  
`ConnectionPoolStats`：`total`、`idle`、`active`、`waiting`、`reused`、`created`、`closed`。

---

## 3. `xdk.net.tls`

**职责**：证书、私钥、信任库、TLS 配置、TLS 流、mTLS、ALPN。  
**业界对齐**：Go `crypto/tls`、Java SSL、Python `ssl`、.NET `SslStream`。

### 3.1 类型

`TlsVersion`、`ClientAuthMode`、`CertificateVerification`、`Certificate`、`PrivateKey`、`TrustStore`、`TlsConfig`、`TlsStream`、`TlsSessionInfo`、`CertificateChain`。

### 3.2 `Certificate`

`Certificate.parsePem(pem)`、`parseDer(der)`、`subject()`、`issuer()`、`serialNumber()`、`notBeforeMillis()`、`notAfterMillis()`、`der()`、`pem()`、`fingerprintSha256()`、`sanDnsNames()`、`sanIpAddresses()`、`isCa()`、`isExpired(now)`、`chain()`、`toString()`。

### 3.3 `PrivateKey` / `TrustStore` / `CertificateChain`

`PrivateKey`：`parsePem(pem)`、`algorithm()`、`bits()`、`publicKeyFingerprint()`；不导出私钥字节。  
`TrustStore`：`TrustStore()`、`TrustStore.system()`、`addCertificate`、`addPem`、`addDer`、`contains`、`length`、`clear`。  
`CertificateChain`：`CertificateChain(list)`、`leaf()`、`issuers()`、`length()`、`validate(trustStore, now)`。

### 3.4 `TlsConfig`

`TlsConfig()`、`withServerName`、`withTrustStore`、`withServerCertificate`、`withServerCertificateChain`、`withClientCertificate`、`withClientAuth`、`withCertificateVerification`、`withMinVersion`、`withMaxVersion`、`withAlpn`、`withSessionCache`、`withSessionCacheSize`、`withCipherSuites`（X）、`withCurves`（X）、`copy()`。

### 3.5 `TlsStream` / `TlsSessionInfo`

`TlsStream.connect(Context,transport,config)`、`accept(Context,transport,config)`、`read`、`readExact`、`readAll`、`write`、`writeAll`、`setReadDeadline`、`setWriteDeadline`、`sessionInfo()`、`peerCertificates()`、`isOpen()`、`close()`。  
`TlsSessionInfo`：`version()`、`cipherSuite()`、`serverName()`、`alpnProtocol()`、`peerCertificate()`、`peerCertificates()`、`isResumed()`、`sessionId()`。

---

## 4. `xdk.net.http`

**职责**：HTTP/1.1、HTTP/2、客户端、服务端、代理、Cookie、表单、Multipart、连接池。  
**业界对齐**：Go `net/http`、Netty、Python `aiohttp`、Node `http`、.NET `HttpClient/Kestrel`。

### 4.1 类型

`HttpMethod`、`HttpVersion`、`HttpStatus`、`HttpHeader`、`HttpHeaders`、`HttpBody`、`HttpRequest`、`HttpResponse`、`HttpExchange`、`HttpHandler`、`HttpMiddleware`（X）、`HttpRouter`（X）、`HttpClient`、`HttpClientOptions`、`HttpServer`、`HttpServerOptions`、`Cookie`、`SameSite`、`CookieJar`、`CookiePolicy`、`Form`、`FormEntry`、`MultipartOptions`、`MultipartPart`、`MultipartForm`、`MultipartWriter`、`HttpAuth`、`HttpCredentials`、`HttpProxyConfig`、`HttpProxyOptions`、`HttpProxyServer`、`HttpProxyExchange`、`HttpProxyHandler`、`HttpTunnel`、`Http2Settings`、`Http2Session`、`Http2Stream`、`Http2Event`、`Http2ErrorCode`、`Http2SessionState`、`Http2StreamState`、`Http2EventKind`。

### 4.2 `HttpMethod` / `HttpVersion` / `HttpStatus`

`HttpMethod`：`Get`、`Post`、`Put`、`Delete`、`Patch`、`Head`、`Options`、`Trace`、`Connect`。  
`HttpVersion`：`Http10`、`Http11`、`Http2`。  
`HttpStatus`：`code`、`reason`、`isInformational`、`isSuccess`、`isRedirect`、`isClientError`、`isServerError`、`of(code)`、`toString`。

### 4.3 `HttpHeaders`

`HttpHeaders()`、`add(name,value)`、`set(name,value)`、`get(name)`、`getOr`、`getAll(name)`、`has(name)`、`remove(name)`、`entries()`、`length()`、`clear()`、`copy()`、`clone()`、`removeHopByHop()`（X）、`contentType()`、`contentLength()`、`userAgent()`、`setCookie()`、`cookies()`。

### 4.4 `HttpBody`

`HttpBody.empty()`、`fromBytes(data)`、`fromText(text)`、`fromForm(form)`、`fromMultipart(form)`、`fromStream(stream,contentLength)`、`isEmpty()`、`contentLength()`、`bytes()`、`stream()`、`readAll(Context,maximumBytes)`、`readText(Context,maximumBytes)`、`writeTo(Context,target)`、`copy()`、`close()`。

### 4.5 `HttpRequest` / `HttpResponse`

`HttpRequest`：`HttpRequest(method,uri)`、`method`、`uri`、`version`、`headers`、`body`、`withHeader`、`withHeaders`、`withBody`、`withVersion`、`withUri`、`copy()`。  
`HttpResponse`：`HttpResponse.of(status)`、`status`、`version`、`headers`、`body`、`withHeader`、`withHeaders`、`withBody`、`withStatus`、`isSuccess`、`isRedirect`、`isClientError`、`isServerError`、`copy()`。

### 4.6 `HttpExchange` / `HttpHandler` / `HttpMiddleware` / `HttpRouter`

`HttpExchange`：`request()`、`respond(response)`、`respondStatus(status)`、`upgrade(protocol)`、`isUpgraded()`、`remoteAddress()`、`localAddress()`、`close()`。  
`HttpHandler`：`handle(Context,exchange)`。  
`HttpMiddleware`（X）：`handle(Context,exchange,next)`；用于日志/鉴权/限流，不内建路由。  
`HttpRouter`（X）：`add(method,pattern,handler)`、`get/post/put/delete`、`route(request)`、`notFound(handler)`、`methodNotAllowed(handler)`；只做路由，不做框架。

### 4.7 `HttpClient` / `HttpClientOptions`

| 能力组 | 方法 |
| --- | --- |
| 请求 | `request(Context,request)`、`get(Context,uri)`、`getBytes`、`getText`、`post(Context,uri,body)`、`put`、`delete`、`head`、`options`、`patch`、`send(Context,method,uri,headers,body)` |
| 配置 | `options()`、`setCookieJar(jar)`、`setDefaultHeaders(headers)`、`setBaseUri(uri)`、`close()` |
| 高级 | `stream(Context,request)`（返回 `HttpResponse` 流式 body）、`execute(Context,request)`（不跟随重定向/X） |

`HttpClientOptions`：`tlsConfig`、`connectTimeout`、`readTimeout`、`writeTimeout`、`followRedirects`、`maxRedirects`、`userAgent`、`maxConnections`、`pool`、`dnsResolver`、`cookieJar`、`cookiePolicy`、`proxy`、`http2`、`defaultHeaders`、`retryPolicy`（X）。

### 4.8 `HttpServer` / `HttpServerOptions`

`HttpServer.bind(Context,local)`、`bind(Context,local,options)`、`bindTls(Context,local,tlsConfig,options)`、`serve(Context,handler)`、`serveTls(Context,tlsConfig,handler)`、`localAddress()`、`isOpen()`、`close()`、`gracefulShutdown(Context,timeout)`（X）。

`HttpServerOptions`：`maxHeaderBytes`、`maxBodyBytes`、`readTimeout`、`writeTimeout`、`keepAlive`、`keepAliveTimeout`、`maxConnections`、`http2`、`http2Settings`、`logger`、`middleware`（X）、`router`（X）。

### 4.9 Cookie / Form / Multipart / Auth

`SameSite`：`Strict`、`Lax`、`None`。  
`Cookie`：`Cookie(name,value)`、`parseSetCookie`、`parseCookieHeader`、`name`、`value`、`domain`、`path`、`expiresMillis`、`isSecure`、`isHttpOnly`、`sameSite`、`headerValue`、`matches(uri)`。  
`CookieJar`：`storeFromResponse`、`headerForRequest`、`cookies`、`removeExpired`、`clear`、`length`。  
`CookiePolicy`：`accept(uri,cookie)`、`headerFor(uri,cookies)`。  
`Form`：`parse`、`set`、`add`、`get`、`getOr`、`getAll`、`remove`、`entries`、`encode`、`toBody`。  
`MultipartOptions`：`maxParts`、`maxPartBytes`、`maxTotalBytes`、`memoryThreshold`。  
`MultipartPart`：`name`、`fileName`、`headers`、`body`、`size`、`close`。  
`MultipartForm`：`parse(Context,request,options)`、`parts`、`get`、`getAll`、`close`。  
`MultipartWriter`：`addPart`、`addFile`、`finish`、`close`。  
`HttpAuth`：`basic`、`bearer`、`parse`、`scheme`、`parameter`。  
`HttpCredentials`：`scheme`、`parameter`、`parameters`。

### 4.10 代理 / CONNECT / HTTP/2 / 连接池

`HttpProxyConfig`：`HttpProxyConfig(uri)`、`withBasicAuth`、`withHeader`、`withNoProxy`、`withConnectTimeout`、`mode`。  
`HttpTunnel`：`connect(Context,transport,target,config)`。  
`HttpProxyServer`：`bind`、`serve`、`localAddress`、`isOpen`、`close`。  
`HttpProxyOptions`：`allowTarget`、`maxConnections`、`connectTimeout`、`idleTimeout`、`requireAuth`、`logger`。  
`HttpProxyExchange`：`request`、`forward(Context,target)`、`openTunnel(Context,target)`、`respond`、`close`。  
`HttpProxyHandler`：`handle(Context,exchange)`。  
`Http2Settings`：`headerTableSize`、`enablePush`、`maxConcurrentStreams`、`initialWindowSize`、`maxFrameSize`、`maxHeaderListSize`。  
`Http2Session`：`connect`、`accept`、`newStream`、`sendSettings`、`ping`、`goAway`、`peerSettings`、`state`、`isOpen`、`close`。  
`Http2Stream`：`id`、`state`、`sendHeaders`、`sendData`、`receive`、`reset`、`close`。  
`Http2Event`：`kind`、`headers`、`data`、`errorCode`、`windowSize`。  
`ConnectionPool`：`acquire`、`release`、`stats`、`close`。  
`PoolKey` / `PooledConnection` / `ConnectionPoolOptions` / `ConnectionPoolStats`：见 §2.12。

---

## 5. `xdk.net.websocket`

**职责**：WebSocket 客户端/服务端、消息、控制帧、心跳、背压、重连。  
**业界对齐**：gorilla/websocket、Java WebSocket、Python `websockets`、Node `ws`、.NET `ClientWebSocket`。

### 5.1 类型

`WebSocketState`、`WebSocketMessageKind`、`WebSocketCloseCode`、`WebSocketCompression`、`WebSocketOptions`、`WebSocketMessage`、`WebSocket`、`WebSocketHandler`、`WebSocketClient`、`WebSocketClientState`、`ReconnectPolicy`、`WebSocketStats`。

### 5.2 `WebSocket`

`WebSocket.connect(Context,uri,options)`、`accept(Context,request,stream,options)`、`sendText`、`sendBinary`、`sendPing`、`sendPong`、`trySendText`、`trySendBinary`、`receive(Context)`、`close(Context,code,reason)`、`close(Context)`、`closeWithCode`、`state()`、`isOpen()`、`subprotocol()`、`setReadDeadline`、`setWriteDeadline`、`setPingInterval`、`setPongTimeout`、`sendQueueBytes`、`stats()`。

### 5.3 `WebSocketMessage` / `WebSocketOptions` / `WebSocketStats`

`WebSocketMessage`：`kind`、`text`、`binary`、`isText`、`isBinary`、`isPing`、`isPong`、`isClose`、`closeCode`、`closeReason`。  
`WebSocketOptions`：`header`、`subprotocol(s)`、`maxFrameBytes`、`maxMessageBytes`、`maxSendQueueBytes`、`pingInterval`、`pongTimeout`、`closeTimeout`、`compression`、`origin`、`tlsConfig`、`reconnect`（X）。  
`WebSocketStats`：`messagesSent`、`messagesReceived`、`bytesSent`、`bytesReceived`、`pingsSent`、`pongsReceived`、`sendQueueBytes`、`lastPongMillis`。

### 5.4 `WebSocketClient` / `ReconnectPolicy`

`WebSocketClient(options,policy)`、`connect(Context,uri)`、`socket()`、`state()`、`reconnect(Context)`、`close()`。  
`ReconnectPolicy`：`initialDelay`、`maxDelay`、`multiplier`、`maxAttempts`、`jitter`、`shouldRetry(attempt)`、`delayFor(attempt)`。

---

## 6. `xdk.net.mime`

**职责**：MediaType、参数、扩展名映射。  
**业界对齐**：Go `mime`、Java `MimeType`、Python `mimetypes`、.NET `MediaTypeHeaderValue`。

`MediaType.parse(text)`、`type()`、`subtype()`、`parameter(name)`、`parameters()`、`charset()`、`text()`、`withParameter(name,value)`、`isText()`、`isJson()`、`isFormUrlEncoded()`、`isMultipart()`、`equals(other)`。  
`MimeTypes.fromExtension(extension)`、`extensionFor(type)`、`charsetFor(type)`、`json()`、`text()`、`octetStream()`、`formUrlEncoded()`、`multipartFormData()`。

---

## 7. `xdk.net` 覆盖结论

| 包 | 旧版方法面 | API 面目标 |
| --- | --- | --- |
| net.uri | parse/组件 | + Query/Url/Codec/Builder/Template |
| net | TCP/UDP 基础 | + IpPrefix/NetworkInterface/连接池/DNS 缓存/更多 Socket 选项 |
| net.tls | 基础配置 | + 证书链/mTLS/校验策略/ALPN/会话信息 |
| net.http | HTTP/1.1 基础 | + Cookie/Form/Multipart/Auth/代理/CONNECT/HTTP2/连接池/路由（X） |
| net.websocket | 基础收发 | + 心跳/背压/压缩/重连/统计/子协议 |
| net.mime | parse/format | + 参数/扩展名/常用类型 |
