# XDK 网络层场景设计 v1.0

| 项 | 值 |
| --- | --- |
| 文档性质 | 网络层场景方案；只写 API 使用方式与能力验证，不写代码 |
| 范围 |  网络包：`net.uri`、`net`、`net.tls`、`net.http`、`net.websocket`、`net.mime` |
| 不讨论 | 编译器、FFI、运行时实现、测试脚本 |
| 目标 | 用真实网络程序验证 API 是否够用，暴露缺口 |
| 配套 | `NET-API.md` 定义 API 面；X 深面见 `NET-EXTENDED-API.md`/`NET-EXTENDED-SCENARIOS.md`；核心层场景见 `../../core/XDK-SCENARIOS.md` |

---

## 0. 场景边界

网络层本身是 ，不改变核心层“无网络”的定位。场景中的分层：

```text
应用协议/业务
  │
  ├─ HTTP / WebSocket
  ├─ TLS
  ├─ TCP / UDP
  └─ DNS / 地址 / URI

核心层只提供：errors、runtime、bytes、text、collections、
              io、fs、sys、time、log、config、tasks、sync
```

网络层场景只验证 XDK 网络 API；不设计 Web 框架、RPC、MQTT、数据库驱动。

---

## 1. 场景总览

| # | 场景 | 主要验证的网络 API |
| --- | --- | --- |
| N1 | TCP 聊天/回声服务 | `TcpListener`、`TcpStream`、`ByteStream`、`TaskGroup`、`Channel` |
| N2 | UDP 监控采集 | `UdpSocket`、`Datagram`、`IpAddress`、`SocketAddress` |
| N3 | HTTP JSON 服务 | `HttpServer`、`HttpExchange`、`HttpRequest/Response`、`HttpHeaders`、`HttpBody` |
| N4 | WebSocket 推送服务 | `WebSocket`、`WebSocketMessage`、`WebSocketOptions`、HTTP upgrade |
| N5 | HTTP 客户端/下载器 | `HttpClient`、`Uri`、`TlsConfig`、`HttpBody` 流式下载 |
| N6 | TCP/HTTP 中间件代理 | `TcpListener/TcpStream`、`HttpServer`、`HttpClient`、`copyStream` |

覆盖：

- TCP：连接、半关闭、短写、EOF、并发连接。
- UDP：数据报、截断、无连接、并发发送。
- TLS：握手、证书校验、SNI、ALPN。
- HTTP：请求/响应、头、body、流式、keep-alive、upgrade。
- WebSocket：握手、文本/二进制、ping/pong、关闭。
- 中间件：双向复制、背压、取消、超时。

---

## 2. N1：TCP 聊天/回声服务

### 2.1 目标与边界

**目标**：一个 TCP 服务，支持多连接；每个连接可以发送消息，服务端广播给其他连接；支持优雅关闭。

**边界**：纯 TCP；不涉及 HTTP/WebSocket/TLS。  
**场景价值**：验证 `TcpListener`/`TcpStream`/`ByteStream` 的连接、读写、并发、关闭语义。

### 2.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Server` | 监听、接受连接、管理客户端集合 |
| `Connection` | 单连接读写循环 |
| `Broadcaster` | 把消息发给其他连接 |
| `Client` | 外部 TCP 客户端 |

### 2.3 主流程

| 阶段 | 动作 | 网络 API |
| --- | --- | --- |
| 启动 | 绑定地址 | `TcpListener.bind(Context, SocketAddress)` |
| 启动 | 创建根任务组 | `TaskGroup.create(Context.background())` |
| 接受 | 等待连接 | `TcpListener.accept(Context)` |
| 接受 | 每连接子任务 | `TaskGroup.spawn` |
| 读取 | 读一行/一帧 | `TcpStream.read(Context, Bytes)` |
| 广播 | 发给其他连接 | `TcpStream.writeAll(Context, Bytes)` |
| 关闭 | 客户端断开 | `read` 返回 0 → `close()` |
| 关闭 | 服务端停止 | `Context.cancel`、`TaskGroup.close`、`TcpListener.close` |

### 2.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 地址 | `IpAddress.parse("0.0.0.0")`、`SocketAddress(address, 9000)` | 绑定 |
| 监听 | `TcpListener.bind(context, local)` | 启动服务 |
| 接受 | `listener.accept(context)` | 新连接 |
| 读 | `stream.read(context, buffer)` | 读数据；0=EOF |
| 写 | `stream.writeAll(context, data)` | 广播 |
| 半关闭 | `stream.shutdown(ShutdownMode.Write)` | 发完关闭写端 |
| 超时 | `stream.setReadDeadline(deadline)` | 空闲连接超时 |
| 关闭 | `stream.close()`、`listener.close()` | 资源释放 |
| 并发 | `TaskGroup.spawn`、`Context` | 每连接任务 |
| 广播表 | `Mutex<Map<String, TcpStream>>` | 客户端集合 |

### 2.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 端口占用 | `bind` → `Unavailable`/`PermissionDenied`；启动失败退出 |
| 客户端断开 | `read` 返回 0；关闭连接；从广播表移除 |
| 慢客户端 | `writeAll` 可能阻塞；设置写截止；超时关闭该连接 |
| 广播失败 | 单个 `writeAll` 失败只移除该客户端，不影响其他连接 |
| 服务端取消 | `accept` 返回 `Cancelled`；停止接受；等待连接任务；`close` 幂等 |
| 资源 | 每个 `TcpStream` 由连接任务关闭；`TcpListener` 由 Server 关闭 |

### 2.6 数据与所有权

- `read` 写入调用方缓冲区；不保留引用。
- 广播数据由发送方拥有；`writeAll` 不保留。
- 客户端表 `Map` 由 `Mutex` 保护；遍历时复制 key 快照，避免持锁写网络。
- `TcpStream` 不跨任务共享读写；每个连接一个 reader 任务 + 一个 writer 任务（如需要）。

### 2.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `Channel.select` 是核心 X | 多连接事件聚合不便 | 先每连接任务；X select |
| `TcpStream` 无 `isReadable/isWritable` | 事件驱动困难 | 阻塞模型足够；事件驱动 X |
| `ByteStream.copy` 只有 `copyStream` | 双向代理需两个任务 | 提供 `copyStream` 单向后组合 |
| `Mutex` 不可重入 | 广播时持锁调用网络会阻塞 | 复制快照后释放锁 |
| `TcpListener` 多 accept 线程 | 设计只保证一个 accept 循环 | 单 accept 循环分配任务 |

### 2.8 场景验收谓词

- 每个连接在正常/异常/取消路径都关闭。
- `read` 的 0=EOF 不被误判为“无数据”。
- 慢客户端不阻塞其他客户端（按任务/超时设计）。
- `listener.close` 后 `accept` 返回 `Unavailable`，已有连接不受影响。
- 服务端取消后不再接受新连接。

---

## 3. N2：UDP 监控采集

### 3.1 目标与边界

**目标**：UDP 服务接收监控 Agent 上报的指标包，解析、聚合、可选回执；支持大量短报文。

**边界**：纯 UDP；不涉及 TCP/HTTP。  
**场景价值**：验证 `UdpSocket`/`Datagram` 的无连接、截断、并发发送语义。

### 3.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Collector` | 绑定 UDP 端口，接收数据报 |
| `Decoder` | 字节 → 指标 |
| `Aggregator` | 聚合/统计 |
| `Reporter` | 写文件/日志/回执 |
| `Agent` | 外部 UDP 发送方 |

### 3.3 主流程

| 阶段 | 动作 | 网络 API |
| --- | --- | --- |
| 启动 | 绑定 UDP | `UdpSocket.bind(Context, SocketAddress)` |
| 接收 | 收数据报 | `UdpSocket.receiveFrom(Context, maximumBytes)` |
| 解析 | 字节 → 指标 | `Datagram.data()`、`ByteReader` |
| 聚合 | 更新统计 | `Map`、`List`、`math` |
| 回执 | 发送确认 | `UdpSocket.sendTo(Context, Datagram)` |
| 停止 | 取消/关闭 | `Context.cancel`、`UdpSocket.close` |

### 3.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 绑定 | `UdpSocket.bind(context, SocketAddress(any, 9999))` | 监听 |
| 接收 | `receiveFrom(context, 65535)` | 收包 |
| 数据 | `datagram.data()`、`datagram.length()` | 解析 |
| 截断 | `datagram.isTruncated()` | 丢弃/告警 |
| 远端 | `datagram.remote()` | 回执地址 |
| 发送 | `sendTo(context, Datagram(data, remote))` | 确认 |
| 并发 | `sendTo` 可并发 | 多回执 |
| 关闭 | `socket.close()` | 释放 |

### 3.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 数据报过大 | `Datagram.isTruncated()` → 丢弃/告警；不静默当完整 |
| 非法包 | `DataCorrupted`/`InvalidArgument`；记录并继续 |
| 发送失败 | `Network`；记录；UDP 不保证送达 |
| 停止 | `receiveFrom` 返回 `Cancelled`/`Unavailable`；`close` 幂等 |
| 资源 | `UdpSocket` 由 Collector 关闭；无每包资源 |

### 3.6 数据与所有权

- `Datagram.data()` 返回副本；Collector 拥有。
- `receiveFrom` 的 `maximumBytes` 是上限；截断标记必须检查。
- `sendTo` 不保留 `Datagram` 引用。
- 聚合表由单接收任务持有；多发送任务只读快照或加锁。

### 3.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `UdpSocket.receiveFrom` 单消费者 | 多核收包需多 socket | 多 socket + `SO_REUSEPORT` X |
| 组播/广播是 X | 发现/采集场景不足 | X `joinMulticast`/`setBroadcast` |
| `Datagram` 无接收时间戳 | 监控延迟测量不便 | X `receivedAtMono()` |
| `UdpSocket` 无 `connect` | 回执需每次 sendTo | X connected UDP |
| `Channel.select` 是 X | 多 socket 聚合不便 | X select |

### 3.8 场景验收谓词

- 截断数据报必须可见，不得静默丢字段。
- 单个坏包不终止服务。
- 取消后不再接收/发送。
- `close` 幂等；端口释放。

---

## 4. N3：HTTP JSON 服务

### 4.1 目标与边界

**目标**：一个 HTTP/1.1 JSON API 服务；支持路由、请求体、头、Cookie、错误映射、可选 TLS、优雅停机。

**边界**：

- `[] xdk.codec`：JSON 编解码（不属于网络层）。
- 网络层提供 `HttpServer`/`HttpExchange`/`HttpRequest`/`HttpResponse`/`HttpHeaders`/`HttpBody`。
- 不设计 Web 框架；路由由应用用 `Map` 实现。

### 4.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Server` | 绑定、TLS、serve |
| `Router` | 路径 → Handler |
| `Handler` | 业务处理 |
| `[] Codec` | JSON |
| `Client` | 外部 HTTP 客户端 |

### 4.3 主流程

| 阶段 | 动作 | 网络 API |
| --- | --- | --- |
| 启动 | 绑定明文/TLS | `HttpServer.bind` / `bindTls` |
| 启动 | 服务端证书 | `TlsConfig.withServerCertificate`、`TrustStore` |
| 启动 | 配置/日志 | 核心层 `Config`/`Logger` |
| 请求 | 读取请求 | `HttpExchange.request()` |
| 路由 | 方法与路径 | `HttpRequest.method()`、`Uri.path()` |
| 读体 | body | `HttpRequest.body()`、`HttpBody.readAll` |
| 业务 | 处理 | 核心层 + `[] codec` |
| 响应 | 状态/头/体 | `HttpResponse.of`、`withHeader`、`withBody`、`exchange.respond` |
| 错误 | 4xx/5xx | `ErrorKind` → 状态码；`HttpResponse` |
| 停机 | 取消 | `Context.cancel`、`HttpServer.close` |

### 4.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 监听 | `HttpServer.bind(context, address)` | 启动 |
| TLS | `HttpServer.bindTls(context, address, tlsConfig)` | HTTPS |
| 服务 | `server.serve(context, handler)` | 接受循环 |
| 请求 | `exchange.request()` | 读取 |
| 头 | `headers.getOr("content-type", "")` | 内容类型 |
| Body | `body.readAll(context, maxBytes)` | 读取 |
| 响应 | `HttpResponse.of(200).withHeader(...).withBody(...)` | 构造 |
| 写回 | `exchange.respond(response)` | 发送 |
| Cookie | `Cookie.parse`、`Cookie.headerValue` | 会话 |
| 升级 | `exchange.upgrade("websocket")` | WebSocket（N4） |
| 关闭 | `exchange.close()`、`server.close()` | 资源 |

### 4.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 请求体过大 | `HttpBody.readAll` → `InvalidArgument`；返回 413 |
| JSON 非法 | `[] codec` → `DataCorrupted`；返回 400 |
| 路由缺失 | 应用返回 404；不是网络错误 |
| Handler 返回 Err | 未响应 → 服务器 500；已响应 → 记录并关闭 |
| 客户端断开 | 子 `Context` 取消；`respond` 返回 `Cancelled`/`Unavailable` |
| 停机 | `serve` 取消；等待在途；`server.close` 幂等 |
| 请求 body | Handler 或 `exchange.close` 关闭 |

### 4.6 数据与所有权

- `HttpRequest`/`HttpResponse` 值对象；headers 发送后只读。
- `HttpBody` 拥有流；`exchange.close` 释放。
- `HttpExchange` 由 server 拥有；handler 不跨请求保留。
- 路由表 `Map` 构建后只读。

### 4.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| HTTP/2 是 X | 高并发/多路复用不足 | 先 HTTP/1.1；X H2 |
| 代理是 X | 出站代理需应用自己接 | `HttpClientOptions.proxy` X |
| 压缩是 （compress） | gzip body 需外部 | 保持  |
| 路由/中间件不在网络层 | 框架职责 | 应用/ecosystem |
| `HttpServerOptions` 关闭超时是 X | 停机可能等待长请求 | X 明确 |
| 表单 multipart 是 K 但大 body 流式 | 内存/磁盘策略 | 明确 `MultipartForm.parse` 上限 |

### 4.8 场景验收谓词

- 4xx/5xx 是正常 `HttpResponse`，不是 `Err`。
- Handler 不得重复响应；未响应由服务器兜底 500。
- 请求体/流在成功/失败/取消路径都关闭。
- `serve` 取消后不再接受新连接；`close` 幂等。
- 头部大小/body 大小有上限。

---

## 5. N4：WebSocket 推送服务

### 5.1 目标与边界

**目标**：HTTP 服务升级 WebSocket；客户端订阅频道，服务端推送通知；支持心跳、关闭、背压。

**边界**：WebSocket over HTTP/1.1（可选 TLS）；不涉及 HTTP/2 WebSocket。  
**场景价值**：验证 `HttpExchange.upgrade` + `WebSocket` 的组合。

### 5.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Server` | HTTP 监听/升级 |
| `Hub` | 连接/频道管理 |
| `Connection` | 单 WebSocket 收发 |
| `Producer` | 产生通知 |
| `Client` | 外部 WS 客户端 |

### 5.3 主流程

| 阶段 | 动作 | 网络 API |
| --- | --- | --- |
| 启动 | HTTP 服务 | `HttpServer.bind/bindTls`、`serve` |
| 升级 | 检查 Upgrade 头 | `HttpRequest.headers()` |
| 升级 | 发 101 + 裸流 | `HttpExchange.upgrade("websocket")` |
| 握手 | 服务端 WebSocket | `WebSocket.accept(context, request, stream, options)` |
| 订阅 | 频道表 | `Mutex<Map<String, Set<WebSocket>>>` |
| 推送 | 发文本/二进制 | `WebSocket.sendText/sendBinary` |
| 心跳 | Ping/Pong | `sendPing`、`receive` 的 Pong |
| 接收 | 客户端消息 | `WebSocket.receive(context)` |
| 关闭 | Close 帧 | `WebSocket.close(code, reason)` |
| 停机 | 取消/关闭 | `Context.cancel`、`HttpServer.close` |

### 5.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 升级 | `exchange.upgrade("websocket")` | 返回 `ByteStream` |
| 接受 | `WebSocket.accept(context, request, stream, options)` | 服务端握手 |
| 选项 | `WebSocketOptions.subprotocol("chat")` | 子协议 |
| 文本 | `sendText(context, text)` | 推送 |
| 二进制 | `sendBinary(context, bytes)` | 推送 |
| 接收 | `receive(context)` | 客户端消息 |
| 心跳 | `sendPing(context, payload)` | 保活 |
| 关闭 | `close(context, WebSocketCloseCode.Normal, "bye")` | 正常关闭 |
| 状态 | `state()`、`isOpen()` | 连接管理 |
| 频道 | `Map`/`Set`/`Mutex` | 订阅表 |

### 5.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 非 Upgrade 请求 | 正常 HTTP 400/404；不升级 |
| 握手失败 | `WebSocket.accept` → `DataCorrupted`/`Unsupported`；关闭流 |
| 客户端断开 | `receive` → `Unavailable`；从 Hub 移除 |
| 推送慢 | `sendText` 阻塞/超时；超时关闭该连接 |
| 心跳超时 | 应用关闭连接 |
| 停机 | 取消根 Context；`WebSocket.close`；`HttpServer.close` |
| 资源 | `WebSocket.close` 关闭底层 `ByteStream`；Hub 清空 |

### 5.6 数据与所有权

- `upgrade` 返回的 `ByteStream` 所有权转移给 `WebSocket`。
- `WebSocketMessage` 拥有数据；推送后不保留。
- 订阅表 `Map<String, Set<WebSocket>>` 由 `Mutex` 保护；推送时复制快照。
- `WebSocket` 发送内部串行化；不允许多个 `receive` 并发。

### 5.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `Channel.select` 是 X | 多频道/心跳聚合不便 | 每连接任务 + 定时器  |
| 广播 fan-out 不在网络层 | 框架职责 | 应用用 `Set`/`Channel` |
| WebSocket 压缩是 X | 带宽 | 先不承诺 |
| HTTP/2 WebSocket 是 X | 多路复用 | 先 HTTP/1.1 |
| `WebSocketOptions.pingInterval` 是 X | 自动心跳 | X 或应用定时 |
| 背压策略不在 API | 慢客户端处理 | 应用超时/关闭 |

### 5.8 场景验收谓词

- 非 Upgrade 请求不会进入 WebSocket。
- 升级成功后 HTTP 层不再读写该连接。
- `receive` 返回 Close 后不再返回数据。
- 关闭握手/超时/断开三条路径都关闭底层流。
- 广播慢客户端不阻塞其他客户端（按快照/超时）。

---

## 6. N5：HTTP 客户端/下载器

### 6.1 目标与边界

**目标**：从 HTTP/HTTPS 下载文件到本地；支持重定向、TLS、超时、取消、流式写盘。

**边界**：客户端 only；不设计服务端。  
**场景价值**：验证 `HttpClient` + `HttpBody` 流式 + `TlsConfig` + `File` 组合。

### 6.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Downloader` | 参数/配置/请求 |
| `HttpClient` | 发请求 |
| `File` | 写盘 |
| `Progress` | 进度/日志 |

### 6.3 主流程

| 阶段 | 动作 | 网络 API |
| --- | --- | --- |
| 启动 | 解析 URL | `Uri.parse` |
| 启动 | TLS 配置 | `TlsConfig`、`TrustStore` |
| 请求 | 发 GET | `HttpClient.get(context, uri)` |
| 响应 | 状态/头 | `HttpResponse.status()`、`headers` |
| 下载 | 流式 body | `HttpBody.stream()`、`read`/`writeAll` |
| 写盘 | 文件 | 核心层 `File.write` |
| 重定向 | 跟随 | `HttpClientOptions.followRedirects` |
| 取消 | 用户中断 | `Context.cancel` |
| 关闭 | 客户端/文件 | `HttpClient.close`、`File.close` |

### 6.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| URL | `Uri.parse("https://...")` | 解析 |
| TLS | `TlsConfig().withServerName(host)` | HTTPS |
| 客户端 | `HttpClient(options)` | 连接池 |
| 请求 | `client.get(context, uri)` | GET |
| 状态 | `response.status()` | 200/3xx/4xx |
| 头 | `headers.getOr("content-length","")` | 长度 |
| Body | `response.body().stream()` | 流式 |
| 读 | `stream.read(context, buffer)` | 分块 |
| 写 | `file.write(bytes)` | 落盘 |
| 进度 | `Logger.info`/`AtomicInt` | 进度 |
| 取消 | `Context.cancel` | 中断 |
| 关闭 | `client.close()`、`file.close()` | 资源 |

### 6.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| DNS 失败 | `NotFound`/`Network`；报告 |
| TLS 证书失败 | `PermissionDenied`；不下载 |
| 4xx/5xx | 正常 `HttpResponse`；应用决定是否报错 |
| 重定向过多 | `InvalidArgument`/`Network`；停止 |
| 下载中断 | `Cancelled`/`Network`；删除半文件或保留 `.part`（应用策略） |
| 写盘失败 | `Io`；关闭 body/文件 |
| 超时 | `Timeout`；关闭连接 |
| 资源 | `HttpResponse.body` 关闭；`HttpClient.close`；`File.close` |

### 6.6 数据与所有权

- `HttpBody` 拥有流；下载完成/失败都要 `close`。
- `read` 写入调用方缓冲；`File.write` 不保留。
- `Uri`/`TlsConfig` 可跨任务共享。
- `HttpClient` 可并发请求；下载任务独立。

### 6.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `HttpBody` 流式到 `File` 需手动循环 | 代码重复 | 提供 `copyStream`；或 `HttpBody.writeTo(File)`（不赞成特化） |
| 断点续传是 X | 大文件下载 | `Range` 头 + 应用逻辑 |
| 代理是 X | 企业网络 | `HttpClientOptions.proxy` |
| 压缩是  `compress` | gzip 下载 | 应用组合 |
| 进度回调是应用层 | 无全局 hook | 循环中 `Logger`/`AtomicInt` |
| `HttpClient` 连接池配置是 X | 调优 | `maxConnections` 已有，细化 X |

### 6.8 场景验收谓词

- 非 2xx 不被当成传输错误；由应用决定。
- 取消后停止读/写，关闭 body/文件。
- 下载失败不留“完整文件”假象（临时文件/原子 rename 是应用策略）。
- TLS 校验失败不得降级继续。

---

## 7. N6：TCP/HTTP 中间件代理

### 7.1 目标与边界

**目标**：一个中间件代理；支持 TCP 隧道和 HTTP 反向代理；验证双向流复制、背压、半关闭、取消、超时。

**边界**：

- TCP 代理：`TcpListener` + `TcpStream` + `copyStream`。
- HTTP 代理：`HttpServer` + `HttpClient` + `HttpBody` 流式。
- 不设计负载均衡策略/服务发现；应用层。

### 7.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Proxy` | 监听/接受 |
| `Upstream` | 连接后端 |
| `Pipe` | 双向复制 |
| `Router` | 选择上游 |
| `[] ServiceRegistry` | 服务发现（可选） |

### 7.3 主流程（TCP）

| 阶段 | 动作 | 网络 API |
| --- | --- | --- |
| 监听 | 绑定 | `TcpListener.bind` |
| 接受 | 客户端连接 | `accept` |
| 上游 | 连接后端 | `TcpStream.connect` |
| 复制 | 客户端→上游 | `copyStream(context, client, upstream, bufferSize)` |
| 复制 | 上游→客户端 | `copyStream(context, upstream, client, bufferSize)` |
| 半关闭 | 一端 EOF | `shutdown(ShutdownMode.Write)` |
| 关闭 | 两端 | `close()` |
| 取消 | 停机 | `Context.cancel`、`TaskGroup.close` |

### 7.4 主流程（HTTP）

| 阶段 | 动作 | 网络 API |
| --- | --- | --- |
| 监听 | HTTP 服务 | `HttpServer.bind` |
| 请求 | 读取 | `HttpExchange.request()` |
| 转发 | 调上游 | `HttpClient.request(context, upstreamRequest)` |
| 流式 | body | `HttpBody.stream()`/`writeTo` |
| 响应 | 回写 | `exchange.respond(response)` |
| 头 | 过滤 hop-by-hop | `HttpHeaders` |
| 取消 | 客户端断开 | 子 `Context` 取消 |
| 关闭 | 服务/客户端 | `close` |

### 7.5 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 复制 | `copyStream(context, source, target, 32*1024)` | 双向管道 |
| 半关闭 | `shutdown(Write)` | 一端结束后通知另一端 |
| 超时 | `setReadDeadline`/`setWriteDeadline` | 空闲/慢连接 |
| HTTP 转发 | `HttpClient.request` | 反向代理 |
| 头过滤 | `headers.remove("connection")` 等 | hop-by-hop |
| body | `HttpBody.writeTo(context, target)` | 流式转发 |
| 取消 | `Context` 子任务 | 客户端断开 |
| 关闭 | `TaskGroup.close` | 连接生命周期 |

### 7.6 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 上游不可达 | `Network`；返回 502（HTTP）或关闭（TCP） |
| 客户端断开 | 取消子任务；关闭上游；停止复制 |
| 上游断开 | 关闭客户端；复制结束 |
| 半关闭 | `shutdown(Write)` 传递 EOF；另一方向继续 |
| 慢连接 | 读写截止；超时关闭；不影响其他连接 |
| 停机 | 取消根 Context；等待复制任务；关闭所有流 |
| 资源 | 每条连接两个流；`TaskGroup` 持有；`close` 幂等 |

### 7.7 数据与所有权

- `copyStream` 使用调用方 buffer；不保留。
- TCP 代理每条连接两个方向任务；`TaskGroup` 等待。
- HTTP 代理的 `HttpBody` 流所有权转移给上游请求/响应；必须关闭。
- 头过滤复制到新 `HttpHeaders`；不修改原请求。

### 7.8 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| 双向复制需两个 `copyStream` | 代码重复 | 提供 `copyBidirectional`（X）或应用组合 |
| HTTP hop-by-hop 头列表不内建 | 代理易错 | `HttpHeaders` 提供 `removeHopByHop()`（X） |
| 连接池/上游选择是应用层 | 无负载均衡 | 应用/ ecosystem |
| 代理协议（CONNECT）是 X | HTTPS 隧道 | 先 TCP 隧道 + HTTP 反代 |
| `Channel.select` 是 X | 多事件聚合 | X |
| 服务发现是  ecosystem | 动态上游 | 应用层 |

### 7.9 场景验收谓词

- 一端 EOF 后另一方向仍可继续（半关闭）。
- 客户端取消后上游连接关闭，无泄漏。
- 慢连接不阻塞其他连接。
- HTTP 代理不转发 hop-by-hop 头。
- 停机后所有连接关闭，`TaskGroup.close` 幂等。

---

## 8. 场景到 API 的覆盖矩阵

| API/包 | N1 TCP | N2 UDP | N3 HTTP | N4 WS | N5 Client | N6 Proxy |
| --- | --- | --- | --- | --- | --- | --- |
| `net.uri` | — | — | 是 | 是 | 是 | 是 |
| `net`（地址/DNS） | 是 | 是 | 是 | 是 | 是 | 是 |
| `TcpListener/TcpStream` | 是 | — | 底层 | 底层 | 底层 | 是 |
| `UdpSocket/Datagram` | — | 是 | — | — | — | — |
| `ByteStream` | 是 | — | 是 | 是 | 是 | 是 |
| `net.tls` | — | — | 是 | 是 | 是 | 是 |
| `net.http` | — | — | 是 | 是 | 是 | 是 |
| `net.websocket` | — | — | — | 是 | — | — |
| `net.mime` | — | — | 是 | — | 是 | 是 |
| 核心 `tasks/sync` | 是 | 是 | 是 | 是 | 是 | 是 |
| 核心 `fs/io` | — | 是 | 是 | — | 是 | 是 |
| 核心 `log/errors` | 是 | 是 | 是 | 是 | 是 | 是 |

结论：

- 网络层 API 覆盖 TCP/UDP/HTTP/WebSocket/代理五类程序。
- TLS 是可选组合，不侵入 TCP/HTTP 公共面。
- WebSocket 通过 HTTP upgrade + `ByteStream` 组合，不与 HTTP 包形成循环依赖。
- 代理场景验证了 `ByteStream`/`copyStream`/半关闭/取消的必要性。

---

## 9. 场景评审结论

### 9.1 够用的部分

- `TcpListener/TcpStream` + `ByteStream` 能支撑 TCP 服务、隧道、代理。
- `UdpSocket/Datagram` 能支撑监控上报/采集。
- `HttpServer/HttpExchange` 能支撑 API 服务、流式 body、upgrade。
- `HttpClient` 能支撑下载器、反向代理。
- `WebSocket` 能支撑推送/聊天。
- `TlsStream` 能作为 TCP/HTTP/WS 的统一加密层。

### 9.2 必须先补的 API（按场景）

| 优先级 | 缺口 | 触发场景 | 建议 |
| --- | --- | --- | --- |
| P0 | `ByteStream.read/write/writeAll` EOF/短写语义 | N1/N5/N6 | 已在 `NET-API` 冻结 |
| P0 | `TcpStream.shutdown` 半关闭 | N6 | 已在 `NET-API` 定义 |
| P0 | `HttpExchange.upgrade` | N4 | 已在 `NET-API` 定义 |
| P0 | `HttpBody` 缓冲/流式二选一 | N3/N5/N6 | 已在 `NET-API` 定义 |
| P0 | `WebSocket` 关闭/状态/控制帧 | N4 | 已在 `NET-API` 定义 |
| P1 | `copyStream` / 双向复制 | N6 | 已有 `copyStream`；双向组合 |
| P1 | HTTP hop-by-hop 头处理 | N6 | X `removeHopByHop` |
| P1 | `Channel.select` | N1/N4/N6 | 核心 X |
| P1 | 连接池/代理配置 | N5/N6 | X |
| P2 | UDP 组播/connected UDP | N2 | X |
| P2 | HTTP/2/WebSocket 压缩 | N3/N4 | X |

### 9.3 场景不改变的原则

- 网络层是 ，不进入核心层。
- 网络层不实现 Web 框架/消息队列/数据库驱动。
- 所有阻塞 API 首参 `Context`；所有资源有 `close()`。
- HTTP 状态码不是 `Err`；WebSocket 正常关闭不是 `Err`。
- 不暴露裸 socket/TLS 上下文。

---

## 10. 下一步

如果这版方向认可，下一步只做设计工作：

1. 评审 `NET-API.md` 的包边界与类面；
2. 用 N1–N6 逐项确认 K/X 切分；
3. 补 `xdk.net.http` 的 Cookie/Multipart/Proxy 细节；
4. 补 `xdk.net.websocket` 的子协议/心跳/背压策略；
5. 不改实现，不写测试脚本，不讨论编译器/FFI。
