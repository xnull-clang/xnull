# XDK 网络层 X 场景设计 v1.0

| 项 | 值 |
| --- | --- |
| 文档性质 | X 场景方案；只写 API 使用方式与能力验证，不写代码 |
| 范围 | 代理/CONNECT、HTTP/2、WebSocket 深面、UDP 高级、DNS/连接池、上传下载、mTLS |
| 前置 | `NET-API.md`、`NET-EXTENDED-API.md` |
| 不讨论 | 编译器、FFI、运行时实现、测试脚本 |

---

## 0. 场景总览

| # | 场景 | 主要验证 |
| --- | --- | --- |
| X1 | HTTP 反向代理 + CONNECT 隧道 | `HttpProxyServer`、`HttpProxyExchange`、`HttpTunnel`、`copyStream` |
| X2 | HTTP/2 多路复用客户端 | `HttpClientOptions.http2`、`ConnectionPool`、ALPN |
| X3 | WebSocket 推送：心跳/重连/背压 | `WebSocketOptions`、`WebSocketClient`、`ReconnectPolicy`、`trySend*` |
| X4 | UDP 组播发现 | `UdpSocket.joinMulticast`、`MulticastOptions`、`Datagram` |
| X5 | DNS 缓存 + 连接池 | `DnsResolver`、`DnsResolverOptions`、`ConnectionPool` |
| X6 | 文件上传/下载服务 | Cookie、Form、Multipart、`HttpBody` 流式 |
| X7 | mTLS 服务 + 证书轮换 | `TlsConfig`、`ClientAuthMode`、`Certificate`、`TrustStore` |

---

## 1. X1：HTTP 反向代理 + CONNECT 隧道

### 1.1 目标与边界

**目标**：一个代理进程同时支持：

- HTTP 反向代理：接收请求，转发到上游，流式回传；
- CONNECT 隧道：客户端通过代理建立 TCP 隧道（例如 HTTPS）。

**边界**：不设计负载均衡/服务发现；上游选择由应用完成。

### 1.2 参与者

| 组件 | 职责 |
| --- | --- |
| `ProxyServer` | 监听、认证、路由 |
| `UpstreamSelector` | 选择上游 |
| `HttpProxyExchange` | 转发/隧道 |
| `HttpClient` | 反向代理上游 |
| `TcpStream` | CONNECT 隧道 |

### 1.3 主流程

| 阶段 | 动作 | API |
| --- | --- | --- |
| 启动 | 绑定代理 | `HttpProxyServer.bind(context, local, options)` |
| 认证 | Proxy-Authorization | `HttpProxyOptions.requireAuth` |
| 请求 | 普通 HTTP | `exchange.request()` |
| 转发 | 上游请求 | `exchange.forward(context, target)` |
| 隧道 | CONNECT | `exchange.openTunnel(context, target)` |
| 复制 | 双向字节 | `copyStream`/`TaskGroup` |
| 关闭 | 连接/服务 | `exchange.close`、`server.close` |

### 1.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 代理配置 | `HttpProxyOptions.allowTarget(...)` | 白名单 |
| 认证 | `HttpProxyOptions.requireAuth(user, pass)` | 基础认证 |
| 普通转发 | `HttpProxyExchange.forward` | 反向代理 |
| 隧道 | `HttpProxyExchange.openTunnel` | CONNECT |
| 双向复制 | `copyStream` ×2 + `TaskGroup` | 隧道数据 |
| 半关闭 | `TcpStream.shutdown(Write)` | 一端 EOF |
| 超时 | `idleTimeout`、`setReadDeadline` | 空闲连接 |
| 取消 | 子 `Context` | 客户端断开 |

### 1.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 目标不在白名单 | `PermissionDenied`/403；关闭 |
| 代理认证失败 | 407；关闭 |
| 上游不可达 | `Network`；HTTP 502 / 隧道关闭 |
| 客户端断开 | 取消子任务；关闭上游 |
| 隧道半关闭 | `shutdown(Write)` 传递 EOF；另一方向继续 |
| 停机 | 取消根 Context；等待连接；`close` 幂等 |
| 资源 | 每条连接两个流；`TaskGroup` 持有；全部关闭 |

### 1.6 数据与所有权

- `forward` 返回的 `HttpResponse.body` 由代理关闭。
- `openTunnel` 返回的 `ByteStream` 归代理；两个复制任务共享同一个流的不同方向。
- 白名单/认证配置构建后只读。

### 1.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `copyBidirectional` 未内建 | 两条 `copyStream` 组合 | X 可加便利函数 |
| hop-by-hop 头过滤未内建 | 反向代理易错 | `HttpHeaders.removeHopByHop`（X） |
| CONNECT 的 TLS 拦截不在 API | MITM 代理 | 不属于 XDK；应用自行组合 |
| 上游负载均衡/健康检查 | 无 | 应用/ecosystem |
| 代理认证只有 Basic | 不够 | `HttpProxyHandler` 自定义 |

### 1.8 场景验收谓词

- 非白名单目标必须拒绝，不得转发。
- CONNECT 成功后 HTTP 层不再解析隧道数据。
- 一端 EOF 后另一方向仍可继续。
- 停机/取消后所有连接关闭，`TaskGroup.close` 幂等。

---

## 2. X2：HTTP/2 多路复用客户端

### 2.1 目标与边界

**目标**：一个后端服务同时向多个上游发请求；使用 HTTP/2 多路复用、连接池、超时、取消。

**边界**：TLS + ALPN h2；不设计 h2c。

### 2.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Client` | 业务请求 |
| `HttpClient` | 连接池/协议选择 |
| `ConnectionPool` | 连接复用 |
| `DnsResolver` | 上游解析 |
| `Http2Session` | 高级调试/自定义流 |

### 2.3 主流程

| 阶段 | 动作 | API |
| --- | --- | --- |
| 启动 | 配置 DNS/池/TLS | `DnsResolver`、`ConnectionPool`、`TlsConfig` |
| 请求 | 并发发请求 | `HttpClient.request` |
| 协议 | ALPN h2 | `HttpClientOptions.http2(true)` |
| 流控 | body 流式 | `HttpBody` |
| 超时 | 每请求 Context | `Context`/`Timeout` |
| 调试 | H2 会话 | `Http2Session`/`Http2Stream` |
| 关闭 | 客户端/池 | `HttpClient.close`、`ConnectionPool.close` |

### 2.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 连接池 | `ConnectionPoolOptions.maxPerKey(4)` | 上游连接上限 |
| 复用 | `PooledConnection.isReused()` | 观察复用 |
| H2 | `HttpClientOptions.http2(true)` | ALPN |
| DNS | `HttpClientOptions.dnsResolver(resolver)` | 自定义解析 |
| 并发 | `TaskGroup` + `HttpClient.request` | 并发请求 |
| 流式 | `HttpBody.fromStream`/`stream` | 大 body |
| 取消 | `Context.cancel` | 中断 |
| 统计 | `ConnectionPool.stats()` | 调优 |

### 2.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 上游不支持 h2 | 回退 HTTP/1.1（按配置） |
| 流被 RST | `DataCorrupted`/`Network`；请求失败 |
| 连接池满 | `Busy`/等待；由 Context 取消 |
| DNS 失败 | `NotFound`/`Network` |
| 取消 | 关闭流/归还连接；不泄漏 |
| 关闭池 | 关闭 idle/active；`close` 幂等 |

### 2.6 数据与所有权

- `PooledConnection` 从池借出，必须 `release` 或 `close`。
- `HttpResponse.body` 流归调用方；关闭后连接可复用。
- H2 `Http2Stream` 事件归调用方；`close` 释放。
- DNS 记录是值对象；TTL 过期由 resolver 处理。

### 2.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| h2c 是 X | 内网明文 H2 | 先 TLS；X 可加 |
| 连接池健康检查策略 | 复用坏连接 | `healthCheck` 已有，细化策略 |
| HTTP/2 优先级/依赖 | 调优 | 不承诺 |
| 服务端推送 | 少用 | 不承诺 |
| 代理 + H2 | 组合 | 先 HTTP/1.1 代理 |

### 2.8 场景验收谓词

- 并发请求不串行化；连接复用可见。
- 取消单个请求不影响其他流。
- 连接池关闭后不再借出；`close` 幂等。
- H2 失败可回退或报错，不静默降级。

---

## 3. X3：WebSocket 推送：心跳/重连/背压

### 3.1 目标与边界

**目标**：长连接推送服务；客户端断线自动重连；服务端心跳检测；慢客户端不拖垮服务。

**边界**：WebSocket over TLS；消息重放由应用负责。

### 3.2 参与者

| 组件 | 职责 |
| --- | --- |
| `PushServer` | 连接/频道/广播 |
| `WebSocket` | 单连接 |
| `WebSocketClient` | 客户端重连 |
| `ReconnectPolicy` | 退避 |
| `Producer` | 通知 |

### 3.3 主流程

| 阶段 | 动作 | API |
| --- | --- | --- |
| 服务端 | HTTP upgrade | `HttpExchange.upgrade` |
| 服务端 | 接受 WS | `WebSocket.accept` |
| 心跳 | Ping/Pong | `WebSocketOptions.pingInterval/pongTimeout` |
| 推送 | 文本/二进制 | `sendText/sendBinary` |
| 背压 | 队列上限 | `maxSendQueueBytes`、`trySend*` |
| 客户端 | 连接/重连 | `WebSocketClient.connect`、`ReconnectPolicy` |
| 关闭 | 正常/异常 | `close(code, reason)` |
| 统计 | 连接质量 | `WebSocketStats` |

### 3.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 子协议 | `WebSocketOptions.subprotocols([...])` | 协商 |
| 压缩 | `WebSocketOptions.compression(PermessageDeflate)` | 带宽 |
| 心跳 | `pingInterval`/`pongTimeout` | 保活 |
| 背压 | `trySendText` → `Busy` | 慢客户端 |
| 统计 | `stats()` | 观察 |
| 重连 | `WebSocketClient` + `ReconnectPolicy` | 客户端 |
| 关闭 | `WebSocketCloseCode` | 语义 |

### 3.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| Pong 超时 | 关闭连接；标记 `GoingAway`/`PolicyViolation` |
| 慢客户端 | 队列满：`send` 阻塞/`trySend` Busy；超时关闭 |
| 客户端断线 | `receive` → `Unavailable`；重连 |
| 重连失败 | 退避/上限；`Cancelled` 停止 |
| 压缩协商失败 | 回退 None 或 `Unsupported` |
| 关闭 | `close` 握手超时 → 强制关闭；幂等 |

### 3.6 数据与所有权

- `WebSocketMessage` 归接收方；不保留。
- 发送队列由 WebSocket 拥有；`maxSendQueueBytes` 限制。
- `WebSocketClient` 拥有当前 `WebSocket`；重连时替换。
- 重连不重放消息；应用队列负责。

### 3.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| 消息重放/去重 | 断线恢复 | 应用/队列 |
| 多频道广播 | 框架 | 应用 `Set`/`Channel` |
| WebSocket over HTTP/2 | 多路复用 | X 后续 |
| 压缩上下文接管 | 性能 | 不承诺 |
| 连接迁移 | 移动网络 | 不承诺 |

### 3.8 场景验收谓词

- 心跳超时必须关闭，不得僵尸连接。
- 慢客户端不阻塞其他客户端。
- 关闭/重连路径不泄漏底层流。
- `trySend` 在队列满时返回 `Busy`，不丢消息。

---

## 4. X4：UDP 组播发现

### 4.1 目标与边界

**目标**：监控 Agent 通过 UDP 组播发现 Collector；Collector 加入组播组，接收上报，单播回执。

**边界**：局域网组播；不做跨网段发现。

### 4.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Collector` | 加入组播、收包、回执 |
| `Agent` | 发组播/单播 |
| `Discovery` | 解析发现报文 |

### 4.3 主流程

| 阶段 | 动作 | API |
| --- | --- | --- |
| 启动 | 绑定 UDP | `UdpSocket.bind` |
| 加入 | 组播组 | `joinMulticast` + `MulticastOptions` |
| 收包 | 数据报 | `receiveFrom` |
| 解析 | 发现报文 | `Datagram.data`、`ByteReader` |
| 回执 | 单播 | `sendTo` |
| 退出 | 离开组 | `leaveMulticast`、`close` |

### 4.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 组播 | `joinMulticast(context, group, options)` | 加入 |
| 网卡 | `MulticastOptions.interfaceName` | 指定接口 |
| TTL | `MulticastOptions.ttl` | 范围 |
| 回环 | `MulticastOptions.loopback` | 本机测试 |
| 广播 | `setBroadcast(true)` | 广播发现 |
| 时间戳 | `Datagram.receivedAtMono` | 延迟 |
| 截断 | `isTruncated` | 丢弃/告警 |

### 4.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 不支持组播 | `Unsupported`；降级广播/单播 |
| 网卡不存在 | `InvalidArgument`/`NotFound` |
| 数据报截断 | `isTruncated`；丢弃/告警 |
| 退出 | `leaveMulticast`；`close` 幂等 |
| 取消 | `receiveFrom` → `Cancelled` |

### 4.6 数据与所有权

- `Datagram.data` 副本；接收方拥有。
- 组播配置对象构建后只读。
- 回执地址来自 `Datagram.remote`；不伪造。

### 4.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| 多网卡同时加入 | 复杂拓扑 | 多 socket |
| IGMP 版本控制 | 兼容 | 不承诺 |
| 组播 DNS/mDNS | 服务发现 | 应用/ecosystem |
| 批量收发 | 高吞吐 | X 可选 |

### 4.8 场景验收谓词

- 加入/离开组播幂等；关闭后不再收包。
- 截断可见；坏包不终止服务。
- 不支持组播明确报 `Unsupported`，不静默失败。

---

## 5. X5：DNS 缓存 + 连接池

### 5.1 目标与边界

**目标**：高并发客户端；DNS 结果缓存、连接复用、每目标限流、故障隔离。

**边界**：客户端 only；不设计服务发现/负载均衡策略。

### 5.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Client` | 业务请求 |
| `DnsResolver` | 解析/缓存 |
| `ConnectionPool` | 连接复用 |
| `HttpClient` | 组合 |

### 5.3 主流程

| 阶段 | 动作 | API |
| --- | --- | --- |
| 启动 | DNS 配置 | `DnsResolverOptions` |
| 启动 | 池配置 | `ConnectionPoolOptions` |
| 请求 | 解析 | `DnsResolver.resolve` |
| 请求 | 取连接 | `ConnectionPool.acquire` |
| 请求 | 发送 | `TcpStream`/`TlsStream`/`HttpClient` |
| 归还 | release | `PooledConnection.release` |
| 观察 | 统计 | `cacheStats`、`pool.stats` |
| 关闭 | 池/解析器 | `close` |

### 5.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 正缓存 | `positiveTtl` | 减少解析 |
| 负缓存 | `negativeTtl` | 快速失败 |
| 上限 | `maxCacheEntries` | 内存 |
| 后台刷新 | `backgroundRefresh` | 避免过期抖动 |
| 池上限 | `maxTotal`/`maxPerKey` | 保护上游 |
| 空闲回收 | `idleTimeout` | 资源 |
| 统计 | `DnsCacheStats`/`ConnectionPoolStats` | 调优 |
| 关闭 | `close` | 生命周期 |

### 5.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| NXDOMAIN | 负缓存 `NotFound`；不缓存 Timeout |
| DNS 超时 | `Timeout`；不缓存 |
| 池满 | `Busy`/等待；Context 取消 |
| 坏连接 | `healthCheck` 淘汰 |
| 关闭 | 停止后台刷新；关闭 idle；active 由调用方释放 |
| 取消 | 解析/等待可取消 |

### 5.6 数据与所有权

- `DnsRecord` 值对象；TTL 过期由 resolver 处理。
- `PooledConnection` 借出所有权；必须 release/close。
- `DnsResolver`/`ConnectionPool` 是显式对象；不全局共享。

### 5.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| DNS SRV/服务发现 | 动态后端 | 应用/ecosystem |
| 池的公平性 | 高并发 | 不承诺 |
| 健康检查策略 | 坏连接 | X 细化 |
| 多 DNS 服务器竞速 | 延迟 | X 可选 |

### 5.8 场景验收谓词

- 负缓存只缓存 NotFound；Timeout/Cancelled 不缓存。
- 池满时等待可取消；不无限阻塞。
- 关闭池后不再借出；active 连接最终释放。
- 统计与实际连接数一致。

---

## 6. X6：文件上传/下载服务

### 6.1 目标与边界

**目标**：HTTP 服务支持表单、Cookie 会话、multipart 文件上传；下载支持流式 body。

**边界**：不设计对象存储；文件落本地/临时文件。

### 6.2 参与者

| 组件 | 职责 |
| --- | --- |
| `UploadHandler` | 解析表单/文件 |
| `CookieJar` | 会话 |
| `MultipartForm` | part 读取 |
| `File` | 落盘 |
| `DownloadHandler` | 流式下载 |

### 6.3 主流程

| 阶段 | 动作 | API |
| --- | --- | --- |
| 会话 | Cookie | `CookieJar.headerForRequest`、`storeFromResponse` |
| 表单 | URL-encoded | `Form.parse` |
| 上传 | multipart | `MultipartForm.parse` |
| 落盘 | 文件 | `File.write`/`writeText` |
| 下载 | 流式响应 | `HttpBody.fromStream` |
| 限制 | 大小/数量 | `MultipartOptions`、`HttpServerOptions.maxBodyBytes` |
| 关闭 | body/file | `close` |

### 6.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| Cookie | `CookieJar` | 会话 |
| 表单 | `Form.getOr` | 字段 |
| 文件 | `MultipartForm.get("file")` | part |
| 文件名 | `MultipartPart.fileName` | 保存名 |
| 流式 | `MultipartPart.body.stream` | 大文件 |
| 下载 | `HttpResponse.withBody(HttpBody.fromStream(...))` | 流式 |
| 限制 | `maxParts`/`maxPartBytes` | 防护 |
| 清理 | `MultipartForm.close` | 临时文件 |

### 6.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 超限 | `InvalidArgument`/413；关闭 |
| 非 multipart | `InvalidArgument`/415 |
| 文件写失败 | `Io`；返回 500；关闭 part |
| 客户端断开 | `Cancelled`；关闭 part/file |
| 临时文件 | `MultipartForm.close` 删除 |
| 下载取消 | `Cancelled`；关闭 body |

### 6.6 数据与所有权

- `MultipartPart.body` 拥有流；`MultipartForm.close` 释放。
- `CookieJar` 由客户端/会话持有；不全局。
- 下载 `HttpBody` 拥有源流；响应发送后由 server 关闭。

### 6.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| 临时文件落盘是 X | 大文件内存 | `memoryThreshold` |
| multipart 嵌套 | 复杂表单 | 不承诺 |
| 断点上传 | 大文件 | 应用 |
| 病毒扫描/内容校验 | 安全 | 应用 |
| Cookie PSL | 安全 | `CookiePolicy` |

### 6.8 场景验收谓词

- 超限请求被拒绝，不写半文件。
- `MultipartForm.close` 清理临时资源。
- 下载流式，不一次性加载。
- Cookie 不跨域泄漏（按域/路径/Secure）。

---

## 7. X7：mTLS 服务 + 证书轮换

### 7.1 目标与边界

**目标**：服务端要求客户端证书；支持证书链、信任库、轮换；不重启服务更新证书（X）。

**边界**：TLS 层；不设计 PKI/CA 服务。

### 7.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Server` | TLS 监听 |
| `TlsConfig` | 服务端证书/客户端认证 |
| `TrustStore` | 客户端 CA |
| `Certificate` | 证书 |
| `Client` | 客户端证书 |

### 7.3 主流程

| 阶段 | 动作 | API |
| --- | --- | --- |
| 启动 | 配置服务端证书链 | `TlsConfig.withServerCertificateChain` |
| 启动 | 要求客户端证书 | `withClientAuth(Require)` |
| 启动 | 信任库 | `TrustStore.system`/`addPem` |
| 握手 | 校验客户端证书 | TLS 内部；失败 `PermissionDenied` |
| 观察 | 对端证书 | `TlsStream.peerCertificates` |
| 轮换 | 更新配置 | 新建 `HttpServer`/`TlsConfig`（X） |

### 7.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 服务端证书 | `withServerCertificateChain` | 证书链 |
| 客户端认证 | `withClientAuth(Require)` | mTLS |
| 校验策略 | `withCertificateVerification(System/TrustStore/None)` | 安全 |
| 信任库 | `TrustStore.addPem` | 自定义 CA |
| 观察 | `peerCertificates()` | 审计 |
| 会话 | `TlsSessionInfo` | 版本/套件 |
| 关闭 | `close` | 资源 |

### 7.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 无客户端证书 | `PermissionDenied`；握手失败 |
| 证书过期 | `PermissionDenied` |
| 不受信任 | `PermissionDenied` |
| 私钥不匹配 | `DataCorrupted`/`InvalidArgument` |
| 轮换 | 新配置/新 server；旧连接自然结束 |
| 关闭 | 关闭 listener/连接；幂等 |

### 7.6 数据与所有权

- `Certificate`/`PrivateKey` 不可变；不导出私钥。
- `TlsConfig` 快照；轮换创建新配置，不修改旧配置。
- `TlsStream.peerCertificates` 返回副本。
- 日志只记录主题/指纹，不记录私钥。

### 7.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| 热轮换 | 不重启 | X：`TlsConfigProvider` 回调 |
| OCSP/CRL | 吊销 | X/实现 |
| 证书透明度 | 合规 | 不承诺 |
| HSM/密钥库 | 安全 | X/ecosystem |
| 客户端证书选择 | 多证书 | 应用配置 |

### 7.8 场景验收谓词

- 无/坏客户端证书必须拒绝。
- 私钥不出现在日志/错误。
- 轮换不破坏旧连接；新连接用新证书。
- 关闭/失败路径释放 TLS/底层流。

---

## 8. 覆盖矩阵

| API/能力 | X1 代理 | X2 H2 | X3 WS | X4 UDP | X5 DNS/池 | X6 上传 | X7 mTLS |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Cookie/Form/Multipart | — | — | — | — | — | 是 | — |
| Proxy/CONNECT | 是 | — | — | — | — | — | — |
| HTTP/2 | — | 是 | — | — | — | — | — |
| WebSocket 深面 | — | — | 是 | — | — | — | — |
| UDP 组播 | — | — | — | 是 | — | — | — |
| DNS 缓存 | — | 是 | — | — | 是 | — | — |
| 连接池 | — | 是 | — | — | 是 | — | — |
| TLS 高级 | 是 | 是 | 是 | — | — | — | 是 |

结论：

- X 覆盖代理、H2、WS 深面、UDP 发现、DNS/池、上传下载、mTLS。
- 每个场景都验证了取消/超时/资源关闭。
- 没有把 Web 框架/消息队列/数据库驱动塞进 XDK。

---

## 9. 评审结论

### 9.1 够用的部分

- `HttpProxyServer` + `HttpTunnel` 能支撑正向/反向代理与 CONNECT。
- `HttpClientOptions.http2` + `ConnectionPool` 能支撑多路复用与连接复用。
- `WebSocketOptions` + `WebSocketClient` 能支撑心跳/重连/背压。
- `UdpSocket` 高级 API 能支撑组播发现。
- `DnsResolver` + `ConnectionPool` 能支撑高并发客户端。
- `MultipartForm`/`CookieJar` 能支撑上传/会话。
- `TlsConfig` 高级面能支撑 mTLS。

### 9.2 仍需补的 API

| 优先级 | 缺口 | 场景 | 建议 |
| --- | --- | --- | --- |
| P0 | `copyBidirectional` / hop-by-hop 头 | X1 | 便利函数/头工具 |
| P0 | H2 流控/GOAWAY 细节 | X2 | `Http2Session` 事件面 |
| P0 | WebSocket 重连消息语义 | X3 | 应用队列；文档明确 |
| P1 | multipart 临时文件策略 | X6 | `memoryThreshold` |
| P1 | TLS 热轮换 | X7 | `TlsConfigProvider` |
| P1 | DNS SRV/服务发现 | X5 | 应用/ecosystem |
| P2 | UDP 批量/多网卡 | X4 | X 可选 |

### 9.3 不改变的原则

- 网络层是 ，不进入核心层。
- 不设计 Web 框架、RPC、MQTT、数据库驱动。
- 所有阻塞 API 首参 `Context`；所有资源有 `close()`。
- HTTP 状态码不是 `Err`；WebSocket 正常关闭不是 `Err`。
- 不提供全局 CookieJar/DNS 缓存/连接池。

---

## 10. 下一步

如果这版方向认可，下一步只做设计：

1. 评审 X 的 API 命名与所有权；
2. 确认 HTTP/2 是否进入 1.0，还是只保留 `HttpClient` 自动协商；
3. 确认 WebSocket 自动重连是否属于 XDK，还是应用层；
4. 补 TLS 热轮换、HTTP 代理认证、Multipart 临时文件策略；
5. 不改实现，不写测试脚本，不讨论编译器/FFI。
