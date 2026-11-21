# XDK 网络层 API 设计 v1.0

| 项 | 值 |
| --- | --- |
| 文档性质 | 网络层 API 方案；只写设计，不写代码 |
| 范围 | `xdk.net.*` 网络包：地址/DNS/TCP/UDP/TLS/HTTP/WebSocket/URI/MIME |
| 不讨论 | 编译器、FFI、运行时实现、测试脚本 |
| 目标 | 回答“网络层能做什么”，给出每个包、每个类的 API 面与场景边界 |
| 配套 | `NET-SCENARIOS.md` 用真实程序验证 API；X 深面见 `NET-EXTENDED-API.md`/`NET-EXTENDED-SCENARIOS.md`；核心层 API 见 `../../core/XDK-CORE-API.md` |

---

## 0. 定位

网络层是 **应用包**，不进入 `xdk.core` 核心层。核心层保持“无网络、无全局状态”；网络层在此之上提供：

```text
应用
  │
  ├─ xdk.net.http        HTTP 客户端/服务端
  ├─ xdk.net.websocket   WebSocket
  ├─ xdk.net.tls         TLS
  ├─ xdk.net             IP/地址/DNS/TCP/UDP/ByteStream
  ├─ xdk.net.uri         URI/URL
  └─ xdk.net.mime        MediaType
        │
        ▼
   核心层：errors / runtime / bytes / text / collections /
           io / fs / sys / time / log / config / tasks / sync
```

### 0.1 网络层不做什么

- 不做应用协议：HTTP 之上的 REST/RPC/GraphQL、MQTT、SIP、Modbus 等属于应用或 ecosystem。
- 不做数据库驱动、Web 框架、模板引擎。
- 不做 DNS 服务器、NTP、代理自动配置。
- 不做 GPU/硬件卸载、内核旁路、自定义 TCP 栈。
- 不暴露裸文件描述符、裸 socket 句柄、裸 TLS 上下文。
- 不提供全局连接池/全局 DNS 缓存；所有状态挂在显式对象上。

---

## 1. 包与依赖

| 包 | 职责 | 依赖 | 稳定性 |
| --- | --- | --- | --- |
| `xdk.net.uri` | URI/URL 解析、构造、百分号编码 | `errors`、`text` | K stable |
| `xdk.net` | IP 地址、Socket 地址、DNS、TCP、UDP、字节流 | `errors`、`bytes`、`io`、`tasks`、`time`、`net.uri` | K stable |
| `xdk.net.tls` | 证书、私钥、信任库、TLS 配置、TLS 流 | `net`、`bytes`、`crypto`、`time` | K stable |
| `xdk.net.http` | HTTP 方法/头/请求/响应/客户端/服务端/Cookie/Multipart | `net`、`net.uri`、`net.tls`、`bytes`、`text`、`io`、`tasks`、`time` | K stable |
| `xdk.net.websocket` | WebSocket 客户端/服务端、消息、关闭 | `net.http`、`net.tls`、`net.uri`、`bytes`、`text` | K stable |
| `xdk.net.mime` | MediaType、扩展名映射 | `text` | K stable |

依赖方向：

```text
net.uri ──► text/errors
net     ──► net.uri, bytes, io, tasks, time, errors
net.tls ──► net, bytes, crypto, time
net.http──► net, net.uri, net.tls, bytes, text, io, tasks, time
net.websocket ──► net.http, net.tls, net.uri, bytes, text
net.mime──► text
```

规则：

- 网络层只能依赖核心层和同层网络包；不得反向依赖 。
- `net.http` 不依赖 `net.websocket`；WebSocket 通过 HTTP upgrade 返回的裸 `ByteStream` 自行握手。
- `net.tls` 不依赖 `net.http`；HTTP 可以组合 TLS。
- `net.mime` 不依赖 `net.http`；HTTP 使用它，而不是反过来。

---

## 2. 跨包 API 契约

### 2.1 失败通道

- 所有可恢复失败返回 `Result<T, Error>`；无成功值用 `Result<Unit, Error>`。
- 网络层不定义新的错误分类体系；统一使用 `ErrorKind`。
- HTTP 状态码不是 `Err`：`HttpResponse.status()` 是正常值；只有传输/协议/握手失败才是 `Err`。
- WebSocket 正常关闭不是 `Err`：通过 `WebSocketMessageKind.Close` 或 `close()` 表达；关闭后继续操作返回 `Unavailable`。

典型错误映射：

| 情况 | `ErrorKind` |
| --- | --- |
| 地址/URI/端口非法 | `InvalidArgument` |
| DNS 名称不存在 | `NotFound` |
| DNS/连接/传输失败 | `Network` |
| 连接被拒绝/不可达 | `Network`/`Unavailable` |
| 操作超时 | `Timeout` |
| 取消 | `Cancelled` |
| TLS 证书校验失败 | `PermissionDenied` |
| TLS 协议/握手数据损坏 | `DataCorrupted`/`Network` |
| HTTP 报文格式错误 | `DataCorrupted` |
| 对端关闭/本地已关闭 | `Unavailable` |
| 平台不支持（如 IPv6、HTTP/2） | `Unsupported` |

### 2.2 取消与超时

- 每个可阻塞方法首参 `Context`：`connect`、`accept`、`read`、`write`、`sendTo`、`receiveFrom`、`request`、`serve`、`receive`、`sendText`。
- `Context` 取消 → `Err(kind = Cancelled)`；超时 → `Err(kind = Timeout)`。
- socket 级 deadline 通过 `setReadDeadline`/`setWriteDeadline` 设置；与 `Context` 同时存在时，先到者生效。
- `close()` 可以并发调用；关闭后阻塞操作返回 `Unavailable`。
- 取消后不得继续产生外部可见副作用：不写半帧、不提交半响应、不 ack 未完成消息。

### 2.3 资源与关闭

所有持有 OS 网络资源的类型必须：

- 提供 `Bool isOpen()`；
- 提供 `Result<Unit, Error> close()`；
- `close()` 幂等：第二次返回 `Ok(unit)`；
- 关闭失败只报告诊断，资源仍视为已释放；
- 关闭后所有读写返回 `Unavailable`。

资源类型：`TcpListener`、`TcpStream`、`UdpSocket`、`TlsStream`、`HttpClient`、`HttpServer`、`WebSocket`。

### 2.4 流抽象：`ByteStream`

TCP/TLS/HTTP 正文/WebSocket 底层都需要一个统一的字节流协议。

```text
protocol ByteStream {
    Result<Int, Error> read(Context context, Bytes buffer)
    Result<Int, Error> write(Context context, Bytes data)
    Result<Unit, Error> writeAll(Context context, Bytes data)
    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis)
    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis)
    Bool isOpen()
    Result<Unit, Error> close()
}
```

契约：

- `read`：把最多 `buffer.length()` 字节写入调用方缓冲区，返回实际字节数；`0` 表示 EOF。
- `write`：写入至多 `data.length()` 字节，返回实际写入数；短写是正常结果，调用方需重试。
- `writeAll`：写完全部或返回错误；不允许静默短写。
- `setReadDeadline`/`setWriteDeadline`：`Long` 是单调毫秒；过期立即 `Timeout`。
- `close`：幂等；关闭后 `isOpen()` 为 false。
- `ByteStream` 不暴露 socket 地址；地址在 `TcpStream`/`TlsStream` 等具体类型上。
- 并发：允许一个 reader 与一个 writer 并发；多个 reader 或多个 writer 不承诺安全。

`TcpStream` 和 `TlsStream` 实现 `ByteStream`；HTTP/WebSocket 只依赖 `ByteStream`，不直接依赖 TCP/TLS。

### 2.5 所有权与缓冲区

| 类型 | 所有权 |
| --- | --- |
| `Bytes` 读缓冲 | 调用方持有；`read` 只写入，不保留 |
| `Bytes` 写数据 | 调用方持有；`write/writeAll` 不保留引用 |
| `Datagram` | 拥有数据副本；接收方拥有 |
| `HttpBody` | 拥有可选流；`close()` 释放 |
| `WebSocketMessage` | 拥有文本/字节；接收方拥有 |
| `Certificate`/`PrivateKey` | 不可变；无 close |
| `TlsConfig` | 不可变配置快照；无 close |
| `HttpHeaders` | 可变构建期；发送后调用方不得修改 |

### 2.6 并发承诺

| 类型 | 并发 |
| --- | --- |
| `TcpListener` | 一个 `accept` 循环；`close` 可与 `accept` 并发 |
| `TcpStream` | 一个 reader + 一个 writer 可并发；`close` 可并发 |
| `UdpSocket` | `sendTo` 可并发；`receiveFrom` 单消费者 |
| `TlsStream` | 同底层 `ByteStream`；一个 reader + 一个 writer |
| `HttpClient` | 可并发 `request`；内部连接池 |
| `HttpServer` | 一个 `serve` 循环；每连接内部任务 |
| `WebSocket` | 一个 `receive` + 多个 `send` 可并发；发送内部串行化 |

---

## 3. `xdk.net.uri`

### 3.1 能力

- 解析绝对/相对 URI；
- 构造 URI；
- 组件读写；
- 百分号编码/解码；
- 相对引用解析。

### 3.2 `Uri`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `parse` | `static Result<Uri, Error> parse(String text)` | 解析 URI | `InvalidArgument` |
| `scheme` | `String scheme()` | 方案；无 → 空串 | 无 |
| `userInfo` | `String userInfo()` | 用户信息；无 → 空串 | 无 |
| `host` | `String host()` | 主机；无 → 空串 | 无 |
| `port` | `Int? port()` | 端口；无 → null | 无 |
| `path` | `String path()` | 路径 | 无 |
| `query` | `String query()` | 查询串 | 无 |
| `fragment` | `String fragment()` | 片段 | 无 |
| `isAbsolute` | `Bool isAbsolute()` | 是否有 scheme | 无 |
| `text` | `String text()` | 规范化文本 | 无 |
| `resolve` | `Uri resolve(Uri reference)` | 相对引用解析 | 无 |
| `withScheme` | `Uri withScheme(String scheme)` | 返回新 URI | 非法 → panic |
| `withHost` | `Uri withHost(String host)` | 返回新 URI | 无 |
| `withPort` | `Uri withPort(Int? port)` | 返回新 URI | 非法端口 → panic |
| `withPath` | `Uri withPath(String path)` | 返回新 URI | 无 |
| `withQuery` | `Uri withQuery(String query)` | 返回新 URI | 无 |
| `withFragment` | `Uri withFragment(String fragment)` | 返回新 URI | 无 |

- 不可变值对象；无 close；可跨任务共享。
- `port` 用 `Int?`，不使用 `-1` 哨兵。
- `text()` 是规范化输出，不保证与输入逐字符相同。

### 3.3 `UriBuilder`（class，X）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `UriBuilder()` | 空 builder |
| `scheme` | `UriBuilder scheme(String scheme)` | 设置方案 |
| `authority` | `UriBuilder authority(String host, Int? port)` | 设置主机/端口 |
| `path` | `UriBuilder path(String path)` | 设置路径 |
| `query` | `UriBuilder query(String query)` | 设置查询串 |
| `fragment` | `UriBuilder fragment(String fragment)` | 设置片段 |
| `build` | `Result<Uri, Error> build()` | 生成 URI | 

### 3.4 百分号编码

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `percentEncode` | `String percentEncode(String text, String allowed)` | 按允许字符集编码 | 无 |
| `percentDecode` | `Result<String, Error> percentDecode(String text)` | 解码 | `DataCorrupted` |
| `queryEncode` | `String queryEncode(String text)` | 查询串编码 | 无 |
| `queryDecode` | `Result<String, Error> queryDecode(String text)` | 查询串解码 | `DataCorrupted` |

---

## 4. `xdk.net`

### 4.1 类型总览

| 类型 | 种类 | 能力 |
| --- | --- | --- |
| `IpFamily` | enum | IPv4/IPv6/未指定 |
| `IpAddress` | class | IP 地址解析/格式化/分类 |
| `SocketAddress` | class | IP + 端口 |
| `Dns` | class | 正向/反向解析 |
| `ByteStream` | protocol | 统一字节流 |
| `TcpListener` | class | TCP 监听/接受 |
| `TcpStream` | class | TCP 连接读写 |
| `UdpSocket` | class | UDP 数据报收发 |
| `Datagram` | class | UDP 数据报 |
| `SocketOptions` | class | 通用 socket 选项 |
| `ShutdownMode` | enum | 半关闭模式 |

### 4.2 `IpFamily`（enum）

`Ipv4`、`Ipv6`、`Unspecified`。

### 4.3 `IpAddress`（class）

**能力**：解析、格式化、分类、字节表示。  
**生命周期**：不可变值对象；无 close；可跨任务共享。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `parse` | `static Result<IpAddress, Error> parse(String text)` | 解析 IPv4/IPv6 | `InvalidArgument` |
| `loopback` | `static IpAddress loopback(IpFamily family)` | 回环地址 | `Unsupported`（family 不支持） |
| `any` | `static IpAddress any(IpFamily family)` | 通配地址 | `Unsupported` |
| `family` | `IpFamily family()` | 地址族 | 无 |
| `text` | `String text()` | 规范文本 | 无 |
| `bytes` | `Bytes bytes()` | 4/16 字节表示 | 无 |
| `isLoopback` | `Bool isLoopback()` | 是否回环 | 无 |
| `isUnspecified` | `Bool isUnspecified()` | 是否通配 | 无 |
| `isMulticast` | `Bool isMulticast()` | 是否组播 | 无 |
| `equals` | `Bool equals(IpAddress other)` | 值相等 | 无 |

### 4.4 `SocketAddress`（class）

**能力**：IP + 端口；解析 `ip:port` / `[ipv6]:port`。  
**生命周期**：不可变值对象；无 close。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `SocketAddress(IpAddress address, Int port)` | 地址 + 端口 | 端口越界 → panic |
| `parse` | `static Result<SocketAddress, Error> parse(String text)` | 解析文本 | `InvalidArgument` |
| `address` | `IpAddress address()` | IP | 无 |
| `port` | `Int port()` | 端口 0..65535 | 无 |
| `text` | `String text()` | 规范文本 | 无 |
| `equals` | `Bool equals(SocketAddress other)` | 值相等 | 无 |

### 4.5 `Dns`（class）

**能力**：正向/反向解析。  
**并发**：静态函数无全局可变缓存；可并发调用。  
**取消**：首参 `Context`；阻塞解析可取消。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `resolve` | `static Result<List<IpAddress>, Error> resolve(Context context, String host)` | 解析全部地址 | `NotFound`/`Network`/`Timeout`/`Cancelled` |
| `resolveOne` | `static Result<IpAddress, Error> resolveOne(Context context, String host, IpFamily family)` | 解析首个匹配地址 | 同上 |
| `reverse` | `static Result<String, Error> reverse(Context context, IpAddress address)` | 反向解析 | `NotFound`/`Network` |

**X**：`DnsResolver` 对象（自定义 DNS 服务器、缓存、TTL、family 策略）。K 不提供全局缓存。

### 4.6 `ByteStream`（protocol）

见 §2.4。`TcpStream`、`TlsStream` 实现；HTTP/WebSocket 只依赖它。

### 4.7 `TcpListener`（class）

**能力**：绑定本地地址，接受 TCP 连接。  
**生命周期**：`bind` 创建；必须 `close()`；close 幂等。  
**并发**：一个 accept 循环；`close` 可并发。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `bind` | `static Result<TcpListener, Error> bind(Context context, SocketAddress local)` | 绑定/监听 | `InvalidArgument`/`PermissionDenied`/`Network`/`Unavailable` |
| `bind` | `static Result<TcpListener, Error> bind(Context context, SocketAddress local, SocketOptions options)` | 带选项绑定 | 同上 |
| `accept` | `Result<TcpStream, Error> accept(Context context)` | 等待新连接 | `Cancelled`/`Timeout`/`Unavailable`/`Network` |
| `localAddress` | `SocketAddress localAddress()` | 实际绑定地址 | 无 |
| `isOpen` | `Bool isOpen()` | 是否监听 | 无 |
| `close` | `Result<Unit, Error> close()` | 停止监听；幂等 | `Io`（诊断） |

- `accept` 返回的连接由调用方拥有，必须 `close()`。
- `close` 后 `accept` 返回 `Unavailable`；已接受的连接不受影响。

### 4.8 `TcpStream`（class，implements `ByteStream`）

**能力**：TCP 连接读写、半关闭、socket 选项。  
**生命周期**：`connect`/`accept` 创建；必须 `close()`；close 幂等。  
**并发**：一个 reader + 一个 writer 可并发；`close` 可并发。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `connect` | `static Result<TcpStream, Error> connect(Context context, SocketAddress remote)` | 直接连接 IP | `Network`/`Timeout`/`Cancelled` |
| `connect` | `static Result<TcpStream, Error> connect(Context context, String host, Int port)` | DNS + 连接 | `NotFound`/`Network`/`Timeout`/`Cancelled` |
| `connect` | `static Result<TcpStream, Error> connect(Context context, SocketAddress remote, SocketOptions options)` | 带选项连接 | 同上 |
| `read` | `Result<Int, Error> read(Context context, Bytes buffer)` | 读；0 = EOF | `Unavailable`/`Network`/`Timeout`/`Cancelled` |
| `write` | `Result<Int, Error> write(Context context, Bytes data)` | 写；可能短写 | 同上 |
| `writeAll` | `Result<Unit, Error> writeAll(Context context, Bytes data)` | 写全 | 同上 |
| `shutdown` | `Result<Unit, Error> shutdown(ShutdownMode mode)` | 半关闭 | `Unavailable`/`Network` |
| `localAddress` | `SocketAddress localAddress()` | 本地地址 | 无 |
| `remoteAddress` | `SocketAddress remoteAddress()` | 对端地址 | 无 |
| `setNoDelay` | `Result<Unit, Error> setNoDelay(Bool enabled)` | TCP_NODELAY | `Unavailable`/`Unsupported` |
| `setKeepAlive` | `Result<Unit, Error> setKeepAlive(Bool enabled)` | SO_KEEPALIVE | 同上 |
| `setReadBuffer` | `Result<Unit, Error> setReadBuffer(Int bytes)` | 接收缓冲 | 同上 |
| `setWriteBuffer` | `Result<Unit, Error> setWriteBuffer(Int bytes)` | 发送缓冲 | 同上 |
| `setReadDeadline` | `Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis)` | 读截止 | `InvalidArgument`/`Unavailable` |
| `setWriteDeadline` | `Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis)` | 写截止 | 同上 |
| `isOpen` | `Bool isOpen()` | 是否打开 | 无 |
| `close` | `Result<Unit, Error> close()` | 关闭；幂等 | `Io`（诊断） |

- `read` 的 `0 = EOF` 是流语义的明确例外，不是“缺失哨兵”。
- `write` 短写不是错误；`writeAll` 负责循环。
- `shutdown(Write)` 后对端读 EOF；本地仍可读。

### 4.9 `UdpSocket`（class）

**能力**：UDP 数据报绑定/收发。  
**生命周期**：`bind` 创建；必须 `close()`；close 幂等。  
**并发**：`sendTo` 可并发；`receiveFrom` 单消费者。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `bind` | `static Result<UdpSocket, Error> bind(Context context, SocketAddress local)` | 绑定本地 | `InvalidArgument`/`PermissionDenied`/`Network` |
| `bind` | `static Result<UdpSocket, Error> bind(Context context, SocketAddress local, SocketOptions options)` | 带选项绑定 | 同上 |
| `sendTo` | `Result<Unit, Error> sendTo(Context context, Datagram datagram)` | 发送数据报 | `InvalidArgument`/`Network`/`Timeout`/`Cancelled` |
| `receiveFrom` | `Result<Datagram, Error> receiveFrom(Context context, Int maximumBytes)` | 接收 | `InvalidArgument`/`Network`/`Timeout`/`Cancelled`/`Unavailable` |
| `localAddress` | `SocketAddress localAddress()` | 本地地址 | 无 |
| `isOpen` | `Bool isOpen()` | 是否打开 | 无 |
| `close` | `Result<Unit, Error> close()` | 关闭；幂等 | `Io`（诊断） |

**X**：connected UDP（`connect`/`send`/`receive`）、组播加入/离开、广播开关。

### 4.10 `Datagram`（class）

**能力**：UDP 数据报值对象。  
**生命周期**：值对象；无 close；接收方拥有数据。

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `Datagram(Bytes data, SocketAddress remote)` | 发送用数据报 |
| 构造 | `Datagram(Bytes data, SocketAddress remote, Bool truncated)` | 接收用；标记截断 |
| `data` | `Bytes data()` | 数据副本 |
| `remote` | `SocketAddress remote()` | 远端地址 |
| `length` | `Int length()` | 数据字节数 |
| `isTruncated` | `Bool isTruncated()` | 接收缓冲不足时为 true |

- 接收时若数据报大于 `maximumBytes`，返回 `truncated = true` 的 `Datagram`，不静默丢包。
- `Datagram` 不保留源缓冲引用；`data()` 返回副本。

### 4.11 `SocketOptions`（class）

**能力**：通用 socket 选项快照。  
**生命周期**：可变构建期；无 close；传给 `bind`/`connect` 后由实现读取，不长期持有。

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `SocketOptions()` | 默认选项 |
| `reuseAddress` | `SocketOptions reuseAddress(Bool enabled)` | SO_REUSEADDR |
| `noDelay` | `SocketOptions noDelay(Bool enabled)` | TCP_NODELAY |
| `keepAlive` | `SocketOptions keepAlive(Bool enabled)` | SO_KEEPALIVE |
| `receiveBuffer` | `SocketOptions receiveBuffer(Int bytes)` | 接收缓冲 |
| `sendBuffer` | `SocketOptions sendBuffer(Int bytes)` | 发送缓冲 |
| `readTimeout` | `SocketOptions readTimeout(Duration timeout)` | 读超时 |
| `writeTimeout` | `SocketOptions writeTimeout(Duration timeout)` | 写超时 |

### 4.12 `ShutdownMode`（enum）

`Read`、`Write`、`Both`。

### 4.13 顶层函数

| 函数 | 签名 | 语义 |
| --- | --- | --- |
| `copyStream` | `Result<Long, Error> copyStream(Context context, ByteStream source, ByteStream target, Int bufferSize)` | 双向/单向复制辅助；代理/隧道使用 |
| `formatIp` | `String formatIp(IpAddress address)` | 规范文本（等价 `address.text()`） |

---

## 5. `xdk.net.tls`

### 5.1 类型总览

| 类型 | 种类 | 能力 |
| --- | --- | --- |
| `TlsVersion` | enum | TLS 1.2 / 1.3 |
| `Certificate` | class | X.509 证书解析/属性 |
| `PrivateKey` | class | 私钥解析/属性（不导出裸密钥） |
| `TrustStore` | class | 信任证书集合 |
| `TlsConfig` | class | 客户端/服务端 TLS 配置 |
| `TlsStream` | class | 在 `ByteStream` 上做 TLS，implements `ByteStream` |
| `TlsSessionInfo` | class | 协商结果 |

### 5.2 `TlsVersion`（enum）

`Tls12`、`Tls13`。

### 5.3 `Certificate`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `parsePem` | `static Result<Certificate, Error> parsePem(String pem)` | 解析 PEM | `DataCorrupted` |
| `parseDer` | `static Result<Certificate, Error> parseDer(Bytes der)` | 解析 DER | `DataCorrupted` |
| `subject` | `String subject()` | 主题 | 无 |
| `issuer` | `String issuer()` | 颁发者 | 无 |
| `notBeforeMillis` | `Long notBeforeMillis()` | 生效时间 | 无 |
| `notAfterMillis` | `Long notAfterMillis()` | 过期时间 | 无 |
| `der` | `Bytes der()` | DER 副本 | 无 |
| `fingerprintSha256` | `String fingerprintSha256()` | 指纹 | 无 |

### 5.4 `PrivateKey`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `parsePem` | `static Result<PrivateKey, Error> parsePem(String pem)` | 解析私钥 | `DataCorrupted`/`Unsupported` |
| `algorithm` | `String algorithm()` | 算法名 | 无 |
| `bits` | `Int bits()` | 位数 | 无 |

- 不提供 `bytes()`/`der()` 导出；私钥不得进入日志/错误消息。

### 5.5 `TrustStore`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `TrustStore()` | 空信任库 |
| `system` | `static TrustStore system()` | 平台/系统信任库快照 |
| `addCertificate` | `void addCertificate(Certificate certificate)` | 添加 |
| `addPem` | `Result<Unit, Error> addPem(String pem)` | 解析并添加 |
| `contains` | `Bool contains(Certificate certificate)` | 是否包含 |
| `length` | `Int length()` | 证书数 |

### 5.6 `TlsConfig`（class）

**能力**：不可变 TLS 配置；通过 `with*` 派生新配置。  
**生命周期**：无 close；可跨任务共享。

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `TlsConfig()` | 默认配置（验证对端、系统信任库） |
| `withServerName` | `TlsConfig withServerName(String serverName)` | SNI/证书主机名 |
| `withTrustStore` | `TlsConfig withTrustStore(TrustStore trustStore)` | 自定义信任库 |
| `withServerCertificate` | `TlsConfig withServerCertificate(Certificate certificate, PrivateKey privateKey)` | 服务端证书/私钥 |
| `withClientCertificate` | `TlsConfig withClientCertificate(Certificate certificate, PrivateKey privateKey)` | 客户端证书 |
| `withMinVersion` | `TlsConfig withMinVersion(TlsVersion version)` | 最低版本 |
| `withMaxVersion` | `TlsConfig withMaxVersion(TlsVersion version)` | 最高版本 |
| `withAlpn` | `TlsConfig withAlpn(List<String> protocols)` | ALPN |
| `withVerifyPeer` | `TlsConfig withVerifyPeer(Bool enabled)` | 证书校验开关 |
| `withSessionCache` | `TlsConfig withSessionCache(Bool enabled)` | 会话缓存（X） |

### 5.7 `TlsStream`（class，implements `ByteStream`）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `connect` | `static Result<TlsStream, Error> connect(Context context, ByteStream transport, TlsConfig config)` | 客户端握手 | `Network`/`PermissionDenied`/`DataCorrupted`/`Timeout`/`Cancelled` |
| `accept` | `static Result<TlsStream, Error> accept(Context context, ByteStream transport, TlsConfig config)` | 服务端握手 | 同上 |
| `read/write/writeAll` | 同 `ByteStream` | 加密读写 | 同 `ByteStream` |
| `setReadDeadline/setWriteDeadline` | 同 `ByteStream` | 截止 | 同 `ByteStream` |
| `sessionInfo` | `TlsSessionInfo sessionInfo()` | 协商信息 | 无 |
| `isOpen` | `Bool isOpen()` | 是否打开 | 无 |
| `close` | `Result<Unit, Error> close()` | 关闭；幂等 | `Io`（诊断） |

- `TlsStream` 拥有底层 `ByteStream`；`close()` 同时关闭底层。
- 握手失败时底层流由调用方负责关闭（文档必须写清）。

### 5.8 `TlsSessionInfo`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `version` | `TlsVersion version()` | 协商版本 |
| `cipherSuite` | `String cipherSuite()` | 密码套件 |
| `serverName` | `String serverName()` | SNI |
| `peerCertificate` | `Certificate? peerCertificate()` | 对端证书 |
| `isResumed` | `Bool isResumed()` | 是否会话恢复 |

---

## 6. `xdk.net.http`

### 6.1 类型总览

| 类型 | 种类 | 能力 |
| --- | --- | --- |
| `HttpMethod` | enum | 请求方法 |
| `HttpVersion` | enum | HTTP/1.0、1.1、2 |
| `HttpHeader` | class | 单条头 |
| `HttpHeaders` | class | 大小写不敏感头集合 |
| `HttpBody` | class | 缓冲/流式正文 |
| `HttpRequest` | class | 请求值对象 |
| `HttpResponse` | class | 响应值对象 |
| `HttpExchange` | class | 服务端单次交换 |
| `HttpHandler` | protocol | 服务端处理入口 |
| `HttpClient` | class | 客户端 |
| `HttpServer` | class | 服务端 |
| `HttpClientOptions` | class | 客户端配置 |
| `HttpServerOptions` | class | 服务端配置 |
| `Cookie` | class | Cookie |
| `SameSite` | enum | Cookie SameSite |
| `MultipartForm`/`MultipartPart` | class | multipart 表单 |

### 6.2 `HttpMethod`（enum）

`Get`、`Post`、`Put`、`Delete`、`Patch`、`Head`、`Options`、`Trace`、`Connect`。

### 6.3 `HttpVersion`（enum）

`Http10`、`Http11`、`Http2`（HTTP/2 为 X）。

### 6.4 `HttpHeader`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `HttpHeader(String name, String value)` | 单条头 |
| `name` | `String name()` | 名称 |
| `value` | `String value()` | 值 |

### 6.5 `HttpHeaders`（class）

**能力**：大小写不敏感、多值头集合。  
**生命周期**：可变构建期；发送后不得修改；无 close。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `HttpHeaders()` | 空集合 | 无 |
| `add` | `void add(String name, String value)` | 追加值 | 非法名 → panic |
| `set` | `void set(String name, String value)` | 替换全部值 | 非法名 → panic |
| `get` | `String? get(String name)` | 首个值；无 → null | 无 |
| `getOr` | `String getOr(String name, String fallback)` | 无 → fallback | 无 |
| `getAll` | `List<String> getAll(String name)` | 全部值快照 | 无 |
| `has` | `Bool has(String name)` | 是否存在 | 无 |
| `remove` | `void remove(String name)` | 删除 | 无 |
| `entries` | `List<HttpHeader> entries()` | 快照 | 无 |
| `length` | `Int length()` | 头数量 | 无 |
| `clear` | `void clear()` | 清空 | 无 |
| `clone` | `HttpHeaders clone()` | 深拷贝 | 无 |

### 6.6 `HttpBody`（class）

**能力**：请求/响应正文；支持缓冲与流式。  
**生命周期**：拥有可选 `ByteStream`；`close()` 释放；无 body 时 close 无操作。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `empty` | `static HttpBody empty()` | 空 body | 无 |
| `fromBytes` | `static HttpBody fromBytes(Bytes data)` | 缓冲 body | 无 |
| `fromText` | `static HttpBody fromText(String text)` | UTF-8 文本 body | 无 |
| `fromStream` | `static HttpBody fromStream(ByteStream stream, Long? contentLength)` | 流式 body | 无 |
| `isEmpty` | `Bool isEmpty()` | 是否为空 | 无 |
| `contentLength` | `Long? contentLength()` | 已知长度；未知 → null | 无 |
| `bytes` | `Bytes? bytes()` | 缓冲内容；流式 → null | 无 |
| `stream` | `ByteStream? stream()` | 流式内容；缓冲 → null | 无 |
| `readAll` | `Result<Bytes, Error> readAll(Context context, Long maximumBytes)` | 读全；超限 `InvalidArgument` | `InvalidArgument`/`Io`/`Cancelled` |
| `writeTo` | `Result<Unit, Error> writeTo(Context context, ByteStream target)` | 写到目标流 | `Io`/`Cancelled` |
| `close` | `Result<Unit, Error> close()` | 关闭拥有的流 | `Io`（诊断） |

- 缓冲 body 与流式 body 二选一，不允许同时存在。
- HTTP/1.1 chunked 由实现处理；调用方只看到 body。

### 6.7 `HttpRequest`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `HttpRequest(HttpMethod method, Uri uri)` | 请求起点 |
| `method` | `HttpMethod method()` | 方法 |
| `uri` | `Uri uri()` | URI |
| `version` | `HttpVersion version()` | 版本 |
| `headers` | `HttpHeaders headers()` | 头集合 |
| `body` | `HttpBody body()` | 正文 |
| `withHeader` | `HttpRequest withHeader(String name, String value)` | 派生新请求 |
| `withBody` | `HttpRequest withBody(HttpBody body)` | 派生新请求 |
| `withVersion` | `HttpRequest withVersion(HttpVersion version)` | 派生新请求 |

- 不可变值对象（headers 在构造后按约定只读）；无 close。
- 服务端请求的 body 由 `HttpExchange` 负责关闭。

### 6.8 `HttpResponse`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `of` | `static HttpResponse of(Int status)` | 状态码构造 |
| `status` | `Int status()` | 状态码 100..599 |
| `version` | `HttpVersion version()` | 版本 |
| `headers` | `HttpHeaders headers()` | 头集合 |
| `body` | `HttpBody body()` | 正文 |
| `withHeader` | `HttpResponse withHeader(String name, String value)` | 派生新响应 |
| `withBody` | `HttpResponse withBody(HttpBody body)` | 派生新响应 |
| `isSuccess` | `Bool isSuccess()` | 2xx |
| `isRedirect` | `Bool isRedirect()` | 3xx |
| `isClientError` | `Bool isClientError()` | 4xx |
| `isServerError` | `Bool isServerError()` | 5xx |

### 6.9 `HttpExchange`（class，服务端）

**能力**：单次请求/响应交换；支持普通响应与协议升级。  
**生命周期**：由 `HttpServer` 创建；`respond`/`upgrade` 只能二选一；`close()` 释放请求 body。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `request` | `HttpRequest request()` | 请求 | 无 |
| `respond` | `Result<Unit, Error> respond(HttpResponse response)` | 写响应 | `Unavailable`/`Io`/`Cancelled` |
| `upgrade` | `Result<ByteStream, Error> upgrade(String protocol)` | 发 101，返回裸流 | `InvalidArgument`/`Unavailable`/`Io` |
| `isUpgraded` | `Bool isUpgraded()` | 是否已升级 | 无 |
| `close` | `Result<Unit, Error> close()` | 关闭交换/请求 body | `Io`（诊断） |

- `upgrade` 成功后，HTTP 层不再读写该连接；返回的 `ByteStream` 由调用方拥有。
- `respond` 之后再次 `respond/upgrade` 是合同错误。
- 未调用 `respond/upgrade` 就返回，服务器生成 500 并关闭。

### 6.10 `HttpHandler`（protocol）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `handle` | `Result<Unit, Error> handle(Context context, HttpExchange exchange)` | 处理一次交换 |

- Handler 返回 `Err` 时，若尚未响应，服务器生成 500；不得重复响应。
- Handler 必须关闭请求 body（或由 `exchange.close()`）。

### 6.11 `HttpClient`（class）

**能力**：HTTP 客户端；连接池、重定向、TLS、流式 body。  
**生命周期**：必须 `close()`；close 幂等。  
**并发**：可并发 `request`。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `HttpClient()` | 默认客户端 | 无 |
| 构造 | `HttpClient(HttpClientOptions options)` | 带配置 | 无 |
| `request` | `Result<HttpResponse, Error> request(Context context, HttpRequest request)` | 发起请求 | `Network`/`Timeout`/`Cancelled`/`DataCorrupted`/`PermissionDenied` |
| `get` | `Result<HttpResponse, Error> get(Context context, Uri uri)` | GET 便捷 | 同上 |
| `post` | `Result<HttpResponse, Error> post(Context context, Uri uri, HttpBody body)` | POST 便捷 | 同上 |
| `put` | `Result<HttpResponse, Error> put(Context context, Uri uri, HttpBody body)` | PUT 便捷 | 同上 |
| `delete` | `Result<HttpResponse, Error> delete(Context context, Uri uri)` | DELETE 便捷 | 同上 |
| `close` | `Result<Unit, Error> close()` | 关闭连接池；幂等 | `Io`（诊断） |

**`HttpClientOptions`**：

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `HttpClientOptions()` | 默认 |
| `tlsConfig` | `HttpClientOptions tlsConfig(TlsConfig config)` | TLS |
| `connectTimeout` | `HttpClientOptions connectTimeout(Duration timeout)` | 连接超时 |
| `readTimeout` | `HttpClientOptions readTimeout(Duration timeout)` | 读超时 |
| `followRedirects` | `HttpClientOptions followRedirects(Bool enabled)` | 重定向 |
| `maxRedirects` | `HttpClientOptions maxRedirects(Int count)` | 最大重定向 |
| `userAgent` | `HttpClientOptions userAgent(String value)` | User-Agent |
| `maxConnections` | `HttpClientOptions maxConnections(Int count)` | 连接池大小 |
| `proxy` | `HttpClientOptions proxy(Uri? proxyUri)` | 代理（X） |

### 6.12 `HttpServer`（class）

**能力**：HTTP/1.1 服务端；每连接任务；TLS 可选；支持 upgrade。  
**生命周期**：`bind` 创建；必须 `close()`；close 幂等。  
**并发**：一个 `serve` 循环；内部每连接任务。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `bind` | `static Result<HttpServer, Error> bind(Context context, SocketAddress local)` | 明文监听（默认选项） | `InvalidArgument`/`PermissionDenied`/`Network` |
| `bind` | `static Result<HttpServer, Error> bind(Context context, SocketAddress local, HttpServerOptions options)` | 明文监听 | 同上 |
| `bindTls` | `static Result<HttpServer, Error> bindTls(Context context, SocketAddress local, TlsConfig config)` | TLS 监听（默认选项） | 同上 |
| `bindTls` | `static Result<HttpServer, Error> bindTls(Context context, SocketAddress local, TlsConfig config, HttpServerOptions options)` | TLS 监听 | 同上 |
| `serve` | `Result<Unit, Error> serve(Context context, HttpHandler handler)` | 接受并处理，直到取消/关闭 | `Cancelled`/`Unavailable`/`Network` |
| `localAddress` | `SocketAddress localAddress()` | 实际地址 | 无 |
| `isOpen` | `Bool isOpen()` | 是否监听 | 无 |
| `close` | `Result<Unit, Error> close()` | 停止监听；幂等 | `Io`（诊断） |

**`HttpServerOptions`**：

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `HttpServerOptions()` | 默认 |
| `maxHeaderBytes` | `HttpServerOptions maxHeaderBytes(Int bytes)` | 头上限 |
| `maxBodyBytes` | `HttpServerOptions maxBodyBytes(Long bytes)` | body 上限 |
| `readTimeout` | `HttpServerOptions readTimeout(Duration timeout)` | 读超时 |
| `writeTimeout` | `HttpServerOptions writeTimeout(Duration timeout)` | 写超时 |
| `keepAlive` | `HttpServerOptions keepAlive(Bool enabled)` | keep-alive |
| `maxConnections` | `HttpServerOptions maxConnections(Int count)` | 最大连接 |
| `logger` | `HttpServerOptions logger(Logger logger)` | 错误日志（可选） |

- `serve` 的取消会停止 accept，并等待在途请求；等待策略由 `HttpServerOptions` 的关闭超时决定（X）。
- 每连接有子 `Context`；客户端断开 → 取消子任务。

### 6.13 `Cookie` / `SameSite`

`SameSite`（enum）：`Strict`、`Lax`、`None`。

`Cookie`（class）：

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `Cookie(String name, String value)` | 名称/值 |
| `parse` | `static Result<List<Cookie>, Error> parse(String header)` | 解析 Cookie 头 |
| `name`/`value` | `String name()` / `String value()` | 字段 |
| `domain`/`path` | `String domain()` / `String path()` | 作用域 |
| `expiresMillis` | `Long? expiresMillis()` | 过期时间；会话 → null |
| `isSecure`/`isHttpOnly` | `Bool isSecure()` / `Bool isHttpOnly()` | 标志 |
| `sameSite` | `SameSite? sameSite()` | SameSite |
| `headerValue` | `String headerValue()` | Set-Cookie 值 |

### 6.14 `MultipartForm` / `MultipartPart`

**`MultipartPart`**：

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `name` | `String name()` | 表单名 |
| `fileName` | `String? fileName()` | 文件名；无 → null |
| `headers` | `HttpHeaders headers()` | part 头 |
| `body` | `HttpBody body()` | part 内容 |

**`MultipartForm`**：

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `parse` | `static Result<MultipartForm, Error> parse(Context context, HttpRequest request, Long maximumBytes)` | 解析 multipart |
| `parts` | `List<MultipartPart> parts()` | 全部 part |
| `get` | `MultipartPart? get(String name)` | 按名查找 |
| `close` | `Result<Unit, Error> close()` | 释放 part body |

---

## 7. `xdk.net.websocket`

### 7.1 类型总览

| 类型 | 种类 | 能力 |
| --- | --- | --- |
| `WebSocketState` | enum | Connecting/Open/Closing/Closed |
| `WebSocketMessageKind` | enum | Text/Binary/Ping/Pong/Close |
| `WebSocketCloseCode` | enum | 标准关闭码 |
| `WebSocketOptions` | class | 客户端/服务端选项 |
| `WebSocketMessage` | class | 收到的消息 |
| `WebSocket` | class | 连接/收发/关闭 |
| `WebSocketHandler` | protocol | 服务端处理入口 |

### 7.2 `WebSocketState`（enum）

`Connecting`、`Open`、`Closing`、`Closed`。

### 7.3 `WebSocketMessageKind`（enum）

`Text`、`Binary`、`Ping`、`Pong`、`Close`。

### 7.4 `WebSocketCloseCode`（enum）

`Normal`、`GoingAway`、`ProtocolError`、`UnsupportedData`、`NoStatus`、`Abnormal`、`InvalidPayload`、`PolicyViolation`、`MessageTooBig`、`MandatoryExtension`、`InternalError`、`TlsHandshake`。

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `code` | `Int code()` | 标准数值 |

自定义关闭码用 `closeWithCode(Int code, String reason)`（X）。

### 7.5 `WebSocketOptions`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `WebSocketOptions()` | 默认 |
| `header` | `WebSocketOptions header(String name, String value)` | 额外头 |
| `subprotocol` | `WebSocketOptions subprotocol(String protocol)` | 子协议 |
| `maxMessageBytes` | `WebSocketOptions maxMessageBytes(Long bytes)` | 消息上限 |
| `pingInterval` | `WebSocketOptions pingInterval(Duration interval)` | 心跳间隔（X） |
| `origin` | `WebSocketOptions origin(String origin)` | Origin |
| `tlsConfig` | `WebSocketOptions tlsConfig(TlsConfig config)` | wss 客户端 TLS |

### 7.6 `WebSocketMessage`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `kind` | `WebSocketMessageKind kind()` | 消息类型 |
| `text` | `String text()` | 文本；非文本 → 空串 |
| `binary` | `Bytes binary()` | 二进制；非二进制 → 空 |
| `isText`/`isBinary` | `Bool isText()` / `Bool isBinary()` | 类型判断 |
| `isPing`/`isPong`/`isClose` | `Bool ...()` | 控制帧判断 |
| `closeCode` | `Int closeCode()` | 关闭码；非 Close → 0 |
| `closeReason` | `String closeReason()` | 关闭原因 |

### 7.7 `WebSocket`（class）

**能力**：WebSocket 客户端/服务端；文本/二进制/控制帧；关闭。  
**生命周期**：`connect`/`accept` 创建；必须 `close()`；close 幂等。  
**并发**：一个 `receive` + 多个 `send` 可并发；发送内部串行化。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `connect` | `static Result<WebSocket, Error> connect(Context context, Uri uri, WebSocketOptions options)` | `ws://`/`wss://` 连接 + 握手 | `InvalidArgument`/`Network`/`PermissionDenied`/`DataCorrupted`/`Timeout`/`Cancelled` |
| `accept` | `static Result<WebSocket, Error> accept(Context context, HttpRequest request, ByteStream stream, WebSocketOptions options)` | 服务端握手 | 同上 |
| `sendText` | `Result<Unit, Error> sendText(Context context, String text)` | 发送文本 | `Unavailable`/`Network`/`Timeout`/`Cancelled` |
| `sendBinary` | `Result<Unit, Error> sendBinary(Context context, Bytes data)` | 发送二进制 | 同上 |
| `sendPing` | `Result<Unit, Error> sendPing(Context context, Bytes payload)` | Ping | 同上 |
| `sendPong` | `Result<Unit, Error> sendPong(Context context, Bytes payload)` | Pong | 同上 |
| `receive` | `Result<WebSocketMessage, Error> receive(Context context)` | 接收下一条消息 | `Unavailable`/`Network`/`DataCorrupted`/`Timeout`/`Cancelled` |
| `close` | `Result<Unit, Error> close(Context context, WebSocketCloseCode code, String reason)` | 关闭握手 | `Network`/`Timeout` |
| `close` | `Result<Unit, Error> close(Context context)` | 正常关闭 | 同上 |
| `closeWithCode` | `Result<Unit, Error> closeWithCode(Context context, Int code, String reason)` | 自定义关闭码（X） | 同上 |
| `state` | `WebSocketState state()` | 状态 | 无 |
| `isOpen` | `Bool isOpen()` | 是否 Open | 无 |
| `subprotocol` | `String? subprotocol()` | 协商子协议 | 无 |
| `setReadDeadline` | `Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis)` | 读截止 | `InvalidArgument`/`Unavailable` |
| `setWriteDeadline` | `Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis)` | 写截止 | 同上 |

- 收到 Close 帧：`receive` 返回 `WebSocketMessageKind.Close`；之后 `receive` 返回 `Unavailable`。
- 自动回 Pong（默认）；`receive` 不自动跳过 Ping/Pong，调用方可选择处理/忽略。
- 分片消息对调用方透明；`receive` 返回完整消息。
- 消息超过 `maxMessageBytes` → `DataCorrupted`/`InvalidArgument`，连接关闭。

### 7.8 `WebSocketHandler`（protocol）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `handle` | `Result<Unit, Error> handle(Context context, WebSocket socket)` | 处理一个 WebSocket 连接 |

- 服务端典型流程：HTTP handler 调 `exchange.upgrade("websocket")`，再用 `WebSocket.accept` 包装，交给 `WebSocketHandler`。

---

## 8. `xdk.net.mime`

### 8.1 `MediaType`（class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `parse` | `static Result<MediaType, Error> parse(String text)` | 解析 `type/subtype; k=v` | `InvalidArgument` |
| `type` | `String type()` | 主类型 | 无 |
| `subtype` | `String subtype()` | 子类型 | 无 |
| `parameter` | `String? parameter(String name)` | 参数；无 → null | 无 |
| `parameters` | `Map<String, String> parameters()` | 参数快照 | 无 |
| `charset` | `String? charset()` | charset 参数 | 无 |
| `text` | `String text()` | 规范化文本 | 无 |
| `isText` | `Bool isText()` | `text/*` | 无 |
| `isJson` | `Bool isJson()` | `application/json` | 无 |

### 8.2 `MimeTypes`（class）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `fromExtension` | `static MediaType? fromExtension(String extension)` | 扩展名 → MediaType；未知 → null |
| `extensionFor` | `static String? extensionFor(MediaType type)` | MediaType → 扩展名；未知 → null |
| `charsetFor` | `static String? charsetFor(MediaType type)` | 默认 charset；无 → null |

---

## 9. 网络层 API 决策

| # | 决策 | 理由 |
| --- | --- | --- |
| N1 | `ByteStream` 放在 `xdk.net`，不放进核心 `xdk.io` | 核心层保持无网络抽象；网络层统一 TCP/TLS/HTTP/WS 流 |
| N2 | TCP/UDP 分开：`TcpListener/TcpStream` 与 `UdpSocket` 不共用 `Socket` 基类 | 流与数据报语义不同，避免“同名换义” |
| N3 | `read` 返回 `Int`，`0 = EOF` | 流读取的标准语义；这不是“缺失/合法值”歧义 |
| N4 | HTTP 状态码不是 `Err` | 4xx/5xx 是正常响应；只有传输/协议失败才是 `Err` |
| N5 | HTTP 服务端用 `HttpExchange`，不用裸 `Request → Response` | 支持 streaming body、upgrade、精确控制响应时机 |
| N6 | WebSocket 只公开消息级 API，帧级 API 内部化 | 避免调用方处理分片/掩码/控制帧细节 |
| N7 | TLS 只暴露 `TlsStream` + `TlsConfig`，不暴露裸上下文 | 保持资源/所有权/错误合同 |
| N8 | DNS K 无全局缓存 | 避免隐式全局状态；X 提供显式 `DnsResolver` |
| N9 | HTTP/2、代理、WebSocket 压缩为 X | 先冻结 HTTP/1.1 + WS 基础面 |
| N10 | 不设计数据库/消息队列/协议栈 | 这些属于 ecosystem，不属于 XDK 网络层 |

---

## 10. 评审清单

- [ ] 每个网络资源类有 `isOpen()`、幂等 `close()`、关闭后行为。
- [ ] 每个阻塞方法首参 `Context`；取消/超时映射 `Cancelled`/`Timeout`。
- [ ] 每个可恢复失败返回 `Result`；HTTP 状态码不被当成 `Err`。
- [ ] TCP/UDP/TLS/HTTP/WebSocket 的失败分类一致。
- [ ] `ByteStream` 的 `read/write/writeAll/EOF` 语义只定义一次。
- [ ] HTTP body 支持缓冲与流式，且所有权清楚。
- [ ] WebSocket 分片/控制帧/关闭握手不泄漏给调用方。
- [ ] DNS/连接池/HTTP 客户端没有隐式全局状态。
- [ ] 网络层不依赖 ；不把 ecosystem 协议塞进 XDK。
- [ ] 每个 X 能力有明确边界，不冒充 K。
