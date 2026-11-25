# `xdk.net.service` 网络服务层

| 项 | 值 |
| --- | --- |
| 包 | `xdk.net.service` |
| 层 | L5 网络/数据（文档在 solutions/） |
| 依赖 | `xdk.core`、`xdk.net`、`xdk.net.tls`、`xdk.execution` |
| 被依赖 | 应用、服务、Agent、工具；不反向依赖 core/net/os/utils |
| 稳定性 | `preview`；不进入 1.0 公共承诺 |
| 状态 | 实现（M19.5）：13/13 类型；TLS/多线程/背压队列未实现 |

---

## 1. 定位

`xdk.net.service` 在 `xdk.net` 之上提供**面向连接的服务编排**：

- 服务端：绑定、接受、连接/会话分派、连接上限、背压、优雅停机；
- 客户端：连接、重连、关闭、连接/会话访问；
- 连接：包装 `ByteStream`（`TcpStream`、`TlsStream` 或调用方提供的其他字节流）与本地/对端地址；
- 会话：每个连接至多一个 `Session`，携带生命周期、活动时间和属性；
- 处理协议：`ConnectionHandler` 处理原始字节，`SessionHandler` 处理会话消息；
- 策略：`ServiceReconnectPolicy`、`BackpressurePolicy`、`HeartbeatPolicy`。

UDP 是数据报，不建立连接/会话；本包不包装 UDP，直接使用 `xdk.net.UdpSocket`。因此“TCP/UDP 服务层”在这里指传输面覆盖，服务编排只对面向连接的流生效。

不做：HTTP、WebSocket、MIME、HTTP/2、HTTP/3、路由、中间件、认证、协议编解码、连接池、服务发现、负载均衡、TLS 证书管理、裸 socket、Unix domain、QUIC、TUN/TAP。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 复用传输层 | `Connection` 只包装 `ByteStream`；`Server`/`Client` 组合 `TcpListener`/`TcpClient`/`TcpStream`/`TlsStream`，不复制  类型 |
| 分层清晰 | 字节层用 `ConnectionHandler`；会话层用 `SessionHandler`；HTTP/WS 仍属 `xdk.net.http`/`xdk.net.websocket` |
| Context 先行 | 所有阻塞操作首参 `Context`；取消映射 `Cancelled`，超时映射 `Timeout` |
| 失败显式 | 可恢复失败一律 `Result<T, Error>`；合同错误才 panic |
| 资源幂等 | `close()` 幂等；关闭后 I/O 返回 `Unavailable`；半关闭不替代 `close()` |
| 无全局状态 | 无全局服务、全局会话表、全局连接池；服务实例由调用方持有 |
| 有界队列 | 接受队列、读缓冲、连接数都有上限；不提供无界应用层写队列 |
| 优雅可观测 | 停机分“停止接受 → 关闭空闲 → 排空活动 → 强制关闭”；状态与统计均为快照 |
| 无裸句柄 | 不暴露 fd、socket handle、TLS 上下文；运行时句柄只作为不透明字段 |
| 单角色 | 一个 `NetworkService` 只承载一个服务端或一个客户端角色，不混合 |

---

## 3. 类型索引

| 类型 | 种类 | 职责 | 文件 |
| --- | --- | --- | --- |
| `NetServiceState` | enum | 服务生命周期状态与稳定名 | [`NetServiceState.md`](NetServiceState.md) |
| `NetworkService` | class | 服务宿主：启动、停止、状态、统计 | [`NetworkService.md`](NetworkService.md) |
| `ServiceOptions` | class | 连接上限、队列、超时、策略、TLS 快照 | [`ServiceOptions.md`](ServiceOptions.md) |
| `ServiceStats` | class | 连接/会话/字节/错误计数快照 | [`ServiceStats.md`](ServiceStats.md) |
| `Server` | class | 绑定、serve、优雅停机、立即关闭 | [`Server.md`](Server.md) |
| `Client` | class | 连接、重连、关闭、当前连接 | [`Client.md`](Client.md) |
| `Connection` | class | 包装 `ByteStream` 与地址、计数、排空 | [`Connection.md`](Connection.md) |
| `Session` | class | 每连接一个会话、消息循环、属性、空闲判断 | [`Session.md`](Session.md) |
| `ConnectionHandler` | protocol | 原始字节连接的生命周期回调 | [`ConnectionHandler.md`](ConnectionHandler.md) |
| `SessionHandler` | protocol | 会话生命周期回调 | [`SessionHandler.md`](SessionHandler.md) |
| `ServiceReconnectPolicy` | class | 客户端重连退避与可重试分类 | [`ServiceReconnectPolicy.md`](ServiceReconnectPolicy.md) |
| `BackpressurePolicy` | class | 接受/读取水位与拒绝策略 | [`BackpressurePolicy.md`](BackpressurePolicy.md) |
| `HeartbeatPolicy` | class | 空闲检查节奏与超时阈值 | [`HeartbeatPolicy.md`](HeartbeatPolicy.md) |

---

## 3.5 实现状态（M19.5）

已实现 13 类型：`NetServiceState`、`ServiceOptions`、`HeartbeatPolicy`、
`BackpressurePolicy`、`ServiceReconnectPolicy`、`ServiceStats`、`ConnectionHandler`、
`SessionHandler`、`Connection`、`Session`、`Server`、`Client`、`NetworkService`。

- `Server`：`TcpListener` 单线程 accept；每连接 `Connection` + `Session`，会话回调闭环；
  连接/统计/状态/幂等 close；端口 0 由 `localAddress` 返回实际地址；
- `Client`：`TcpClient` 连接、会话读循环、连接失败/断线按 `ServiceReconnectPolicy`
  退避重试；同一 `connect` 调用内成功后重置 attempt，重连次数受策略约束；
- `NetworkService`：后台 `TaskGroup` 启动 Server 或 Client，二者互斥（`AlreadyExists`），
  `stop` 关闭并等待，`close` 幂等；关闭后启动返回 `Unavailable`；
- `Connection` 包装 `ByteStream`，`read/write/writeAll`、排空、单会话、`process` 闭环；
- `Session` 提供 `send/receive` 语义（`send` 走 `Connection.writeAll`，`run` 驱动读取）；
- deadline 委托 `ByteStream`；`TcpStream` 当前返回 `Unsupported`；
- 实现限制：编译器不支持方法重载，`Server.bind` 默认选项用 `bindDefault`，
  `NetworkService.startClient` 默认策略用 `startClient`、显式策略用 `startClientWithPolicy`，
  `shouldRetry(Int,Error)` 以 `shouldRetryError` 提供；
- `Server.shutdown` 与 `Connection.serveConnections` 未实现；停机关闭 listener/连接；
- `ServiceOptions` 暂不含 `socketOptions`/`tlsConfig`/`tcpServerOptions`，因为
  `xdk.net` 尚无 `SocketOptions`、`xdk.net.tls` 尚未实现；
- TLS、多线程 accept、应用层写队列明确未实现。

## 4. 跨类型规则

- `NetworkService` 是可选宿主；也可以直接使用 `Server`/`Client`。两者共享同一套 `ServiceOptions` 语义，但 `NetworkService` 负责后台任务与聚合生命周期。
- `ServiceOptions` 在 `Server.bind`、`Client` 构造、`NetworkService` 构造时复制；运行中的服务不受后续修改影响。
- 一个 `NetworkService` 只能启动一次，且只能选择 `startServer` 或 `startClient` 之一；重复或混合启动返回 `AlreadyExists`。
- `Server` 生命周期：`bind` → `serve`/`serveConnections`（二选一，一次）→ `shutdown`（优雅）→ `close`（释放）；或在任意阶段直接 `close`（立即）。
- `Client` 生命周期：构造 → `connect` → 零或多次 `reconnect` → `close`；同一时刻最多一个活动连接。
- `Connection` 拥有底层 `ByteStream`；关闭连接即关闭流。一个 reader 与一个 writer 可并发；多个 reader 或多个 writer 不承诺安全。
- `Session` 借用 `Connection`，每个连接至多一个会话；`Session.close()` 会关闭连接，`Connection.close()` 也会使会话失效；两者都幂等。
- `ConnectionHandler` 与 `SessionHandler` 的 `onOpen` 至多一次，`onMessage` 零或多次，`onError` 至多一次，`onClose` 恰好一次；顺序固定为 `onOpen` → `onMessage*` → `onError?` → `onClose`。
- `onMessage` 的 `Bytes` 只在回调期间有效；需要保留时由实现复制。消息是读取块而非协议帧；分帧由实现负责。
- `BackpressurePolicy` 只作用于服务端接受与读取水位；写侧背压来自 TCP 发送窗口与 `writeTimeoutMillis`，不建立无界写队列。
- `HeartbeatPolicy` 只做空闲检测，不注入协议帧；WebSocket ping/pong 仍由 `xdk.net.websocket` 负责。
- `ServiceReconnectPolicy` 只由客户端使用；服务端不自动重连。它不替代 `xdk.net.websocket.ServiceReconnectPolicy`，后者仍服务 WebSocket 握手语义。
- `TLS` 由 `ServiceOptions.tlsConfig` 开启：服务端执行 `TlsStream.accept`，客户端执行 `TlsStream.connect`；本包不管理证书生命周期。
- 统计中的累计量为 `Long`，当前连接/会话数为 `Int`；统计是快照，不保证与其他查询原子组合。
- 失败分类沿用 `ErrorKind`：连接拒绝 `Network`、截止 `Timeout`、取消 `Cancelled`、容量满 `Busy`、关闭后 `Unavailable`、配置错误 `InvalidArgument`。
- UDP 无连接语义，不套 `Connection`/`Session`；需要 UDP 时直接使用 `xdk.net.UdpSocket`。本包的服务编排只覆盖面向连接的流。

---

## 5. 场景

### S1：会话回显服务端

`Server.bind(context, local, options)` → `serve(context, sessionHandler)`；每个连接由运行时包装 `Connection` 与 `Session`；`onMessage` 用 `session.send` 回显；`shutdown(context)` 排空后返回。

### S2：原始分帧服务端

`Server.bind` → `serveConnections(context, connectionHandler)`；handler 在 `onMessage` 中把读取块追加到自己的帧缓冲，处理完整帧并用 `connection.writeAll` 发送；适用于自定义二进制协议。

### S3：客户端断线重连

`new Client(options)` → `connect(context, remote)` → 读取失败后 `reconnect(context)`；`ServiceReconnectPolicy` 决定延迟、次数与可重试分类；成功后 `attempt` 归零。

### S4：优雅停机

`Server.shutdown(context)` 停止接受、关闭空闲会话、排空活动会话；`context` 或 `gracefulShutdownTimeoutMillis` 先到则强制关闭剩余连接并返回 `Timeout`；`close()` 可随后立即释放。

### S5：背压

`BackpressurePolicy` 的连接/队列水位触发暂停接受或显式拒绝；`ServiceOptions.acceptQueueCapacity` 是硬上限；运行时记录 `backpressureEvents`，不静默丢弃。

### S6：TLS 服务

`ServiceOptions.tlsConfig` 配置服务端证书/私钥；`Server` 接受后执行 `TlsStream.accept`，再用 `TlsStream` 构造 `Connection`；客户端对应执行 `TlsStream.connect`。

### S7：失败与取消

handler 返回 `Err` 时先 `onError`、再关闭资源、最后 `onClose`；连接关闭后 I/O 返回 `Unavailable`。`Server.shutdown` 超时返回 `Timeout` 并强制关闭；`Client.reconnect` 在 `Context` 取消时返回 `Cancelled`；所有 `close()` 重复调用成功。

---

## 6. 缺口

| 项 | 决策 |
| --- | --- |
| UDP 服务编排 | 不使用伪连接；直接 `UdpSocket`；X 再评估数据报处理器 |
| HTTP/WebSocket | 属于 `xdk.net.http`/`xdk.net.websocket`；本包不重复 |
| 协议编解码/分帧 | 由 handler 或上层 codec 负责；本包只交付字节块 |
| 连接池 |  `ConnectionPool`；本包不重复 |
| 多监听器/多端点 | 单 `Server` 单监听；多端点由多个实例组合 |
| DNS 重解析 | `reconnect` 使用最近一次解析地址；需要重解析时重新 `connect(host, port)` |
| 连接建立超时 | 由 `Context` 截止控制；独立 connect timeout 策略为 X |
| 客户端默认读写截止 | 服务端由运行时应用 `ServiceOptions`；客户端由调用方设置 `Connection` 截止或启用心跳；统一客户端默认值为 X |
| TLS 证书热更新/ACME | 不在本包；由 TLS/生态负责 |
| 指标导出/追踪 | 只提供 `ServiceStats`；导出由  metrics/trace 组合 |
| 会话持久化/恢复 | 不做；会话是进程内对象 |
| 认证/授权 | 上层中间件或协议负责 |
| 压缩/加密载荷 | TLS 之外不做 |
| QUIC/Unix domain/raw socket | 不做 |
| 客户端优雅排空 | `Client.close()` 立即关闭；协议级半关闭由调用方使用 `Connection`/底层流 |

---

## 7. 安全

| 义务 | 规则 |
| --- | --- |
| 资源上限 | 必须设置 `maxConnections`、`acceptQueueCapacity`、`readBufferBytes`；不得无界缓冲 |
| 超时 | 生产服务应启用 `idleTimeoutMillis`/`readTimeoutMillis`/`writeTimeoutMillis` 或 `HeartbeatPolicy`；默认 0 表示关闭，需显式评估 |
| TLS | 默认验证对端；服务端必须提供证书与私钥；客户端必须设置 `serverName`；失败即拒绝，不降级明文 |
| 输入 | `onMessage` 的字节来自不可信网络；分帧、长度、内容校验由 handler 负责 |
| 日志 | 不记录私钥、证书内容、会话属性中的敏感值；错误摘要不含原始载荷 |
| 背压 | 水位满时暂停或显式拒绝；不得静默丢弃或无限排队 |
| 停机 | 先停止接受，再排空；超时强制关闭；`close` 幂等 |
| 取消 | Context 取消传播到读写；取消不是“立即杀线程”，handler 必须检查 |
| 句柄 | 不暴露 fd/socket handle/TLS 上下文；运行时不透明句柄只由包内使用 |
| 处理器 | handler 视为可信代码；其阻塞、异常返回或慢消费会影响连接；单连接回调串行 |

---

## 8. 行业调研

| 模型 | 关键机制 | 采用 | 不采用 |
| --- | --- | --- | --- |
| Go `net/http` | `Server.Shutdown` 先关监听、再关空闲连接、等待活动连接；`Close` 立即；`Transport` 空闲连接与超时 | 优雅停机两阶段、Context 截止、客户端连接生命周期 | 全局 `DefaultClient`/`DefaultServeMux`、HTTP 语义 |
| Netty | `ChannelPipeline` 的 `channelActive`/`channelRead`/`channelInactive`；`IdleStateHandler`；`WriteBufferWaterMark`；EventLoop | handler 生命周期、空闲检测、读写水位、单连接串行回调 | 暴露 pipeline/EventLoop/ByteBuf |
| Tokio | `TcpListener.accept` 可取消；`select!` 停机；`CancellationToken`；有界 channel 背压 | Context 取消、接受循环可中断、有界队列 | 暴露运行时/任务调度器 |
| ASP.NET Kestrel | `MaxConcurrentConnections`、`KeepAliveTimeout`、`RequestHeadersTimeout`、`MinRequestBodyDataRate`、停机超时 | 连接上限、空闲/读写超时、低速率检测思路、停机预算 | HTTP 请求/响应模型、Kestrel 配置体系 |

参考：

- Go `net/http`：<https://pkg.go.dev/net/http#Server.Shutdown>
- Netty `ChannelPipeline`：<https://netty.io/4.1/api/io/netty/channel/ChannelPipeline.html>
- Netty `IdleStateHandler`：<https://netty.io/4.1/api/io/netty/handler/timeout/IdleStateHandler.html>
- Netty `WriteBufferWaterMark`：<https://netty.io/4.1/api/io/netty/channel/WriteBufferWaterMark.html>
- Tokio graceful shutdown：<https://tokio.rs/tokio/topics/shutdown>
- Tokio `TcpListener`：<https://docs.rs/tokio/latest/tokio/net/struct.TcpListener.html>
- ASP.NET Core Kestrel options：<https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/options>

---

## 9. 边界关系

| 相邻包 | 关系 |
| --- | --- |
| `xdk.net` | 提供 `ByteStream`、`TcpListener`、`TcpStream`、`UdpSocket`、`SocketAddress`、`SocketOptions`、`ConnectionPool` |
| `xdk.net.tls` | 提供 `TlsConfig`、`TlsStream`；本包只组合，不重复握手/证书类型 |
| `xdk.net.http` | HTTP 服务端/客户端仍在该包；本包不提供 HTTP 语义 |
| `xdk.net.websocket` | WebSocket 握手、帧、ping/pong 仍在该包；本包不重复 |
| `xdk.execution` | `Context`、`TaskGroup`、`TaskHandle`、`Mutex`、`Channel` 等执行原语 |
| `xdk.api` | 可基于 `xdk.net.http` 构建；不以本包替代 HTTP 服务 |

---

## 10. 验收清单

- [ ] 全部公开类型均有独立 PascalCase 文件；
- [ ] 每文件 14 段，段号与标题一致；
- [ ] 所有阻塞方法首参 `Context`；
- [ ] 所有可恢复失败使用 `Result`；
- [ ] `close()` 幂等；关闭后行为明确；
- [ ] 私有字段不使用 self 前缀；不把 self 当函数调用；无 Python 风格条件表达式；无省略式注释；
- [ ] 参数名完整，不使用 `id`/`unit`/`pad`/`to`/`q` 作为参数名；
- [ ] `Long` 表示大小/累计/时长，`Int` 表示计数/容量；
- [ ] 相对链接可达，未修改 `../../network/README.md` 与 `../README.md`。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder`、`@Override` |
| 处理器 | 标准 A8 / 编译器内建 |
| 生成物 | 服务选项/统计值语义、连接/会话 handler 签名 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `ServiceOptions`/`ServiceStats`/`BackpressurePolicy`/`HeartbeatPolicy` | `@Value`/`@Builder` | 值语义/选项 |
| `ConnectionHandler`/`SessionHandler` 实现 | `@Override` | 签名校验 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
