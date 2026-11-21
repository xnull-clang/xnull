# `xdk.core` 客户端/服务器能力画像设计

| 项 | 值 |
| --- | --- |
| 文档性质 | 跨包能力分析与设计补齐；只写设计与 XNull 声明，不写实现 |
| 范围 | `xdk.core` L1–L4，以及与 L5/L6 `xdk.net` 的能力衔接 |
| 目标 | 回答“客户端和服务器分别需要什么核心底层能力”，并补齐缺失的枚举、协议、类、抽象与泛型 |
| 规则 | 语法只使用 XNull；不新增语言构造；不复制 L5/L6 已有类型 |
| 状态 | Draft for review；新增类型标 `preview`，不改变既有 K 契约 |
| 实现状态 | 本文只补设计；新增类型尚未在 `src/xdk` 实现 |
| 配套 | `README.md`、`meta/`、`execution/`、`runtime/`、`config/`；网络具体类型见 `docs/design/network/net` |

---

## 0. 问题定义

“核心层”过去按包组织，回答的是“有哪些包、每个类有哪些方法”。这只解决了**通用能力**，
没有回答两个更底层的问题：

1. 一个程序在构建时到底是**客户端、服务器、工具还是库**？
2. 不同角色允许使用哪些能力、允许多少并发/连接/内存、关闭时如何排空？

这两个问题不能靠应用自己散落判断。否则会出现：

- 客户端把服务器才有的监听、进程监督、信号能力带进安装包；
- 服务器把客户端的 Cookie/代理/重定向逻辑带进核心路径；
- 两边都假设“无限并发、无限队列、无限内存”，直到线上才暴露；
- 同一个核心 API 在客户端和服务器上语义不同，却没有声明。

本文的结论是：

> **一个核心内核，多个能力画像（profile）。**
> 公共内核只提供与角色无关的失败、时间、字节、文本、容器、流、配置、日志、执行原语；
> 客户端/服务器各自通过 `CoreProfile` 声明可用能力、资源上限、I/O 模型和关闭策略。
> 具体网络能力仍归 `xdk.net`，核心层只定义“如何选择和约束”，不复制网络 API。

### 0.1 业界核心层对照

不同语言并没有统一的“core”边界；它们的共同点不是包名，而是**分层职责**：

| 语言/平台 | 核心层 | 客户端/服务器位置 | 可借鉴的点 | 不照搬的点 |
| --- | --- | --- | --- | --- |
| Go | `runtime` + 小 stdlib；`context` 管取消 | `net/http` 同时有 Client/Server | 小核心、显式 Context、无全局状态 | `net/http` 把 client/server 放同一包，类型面过大 |
| Java | `java.base` 模块；`java.net.http` | HTTP Client 在 JDK；Server 在 Jakarta/容器 | 分层模块、接口抽象、服务提供者 | 类库/反射/注解过重 |
| Rust | `core`/`alloc`/`std` 三层；无内置运行时 | `std::net` + 生态 crate | `core` 不依赖 OS；能力分层 | 无统一标准库服务端抽象；async 生态分裂 |
| .NET | `System.Private.CoreLib`；`System.Net.*` | `HttpClient` 与 ASP.NET Core 分离 | Options/DI/健康检查/优雅停机 | 容器/宿主框架过重 |
| Python | 小 stdlib + `asyncio` | `http.client`/`http.server`，框架在外 | 核心小、协议库可选 | 全局解释器/隐式运行时太多 |
| Node | 核心模块 + `http` | client/server 同模块，框架在外 | 事件驱动、流 | 回调/隐式全局、类型弱 |

结论：

1. 共同内核应只含**失败、时间、字节、文本、容器、流、配置、日志、执行原语**；
2. 客户端/服务器的差异应由**角色/能力/资源上限**表达，而不是复制一套核心；
3. 网络 client/server 应分类型、共享字节流与地址；
4. 取消、关闭、健康、限额必须是显式合同，不能藏进运行时；
5. 抽象用非泛型协议，参数化用泛型类/函数——这与 XNull 的语言约束一致。

XDK 的取舍是：

```text
xdk.core        公共内核 + 画像/限额/健康/执行原语
xdk.net         L5 传输：地址/DNS/TCP/UDP/TLS
xdk.net.http    L6 协议：HttpClient 与 HttpServer 分类型
xdk.net.websocket  WebSocketClient 与 WebSocket 服务端分类型
```

不把 client/server 塞进同一个“万能 core”，也不为两者各复制一份 L1/L2。

---

## 1. 现状审计

### 1.1 已有能力

| 层 | 包 | 已设计内容 | 对客户端的价值 | 对服务器的价值 |
| --- | --- | --- | --- | --- |
| L1 | `errors` | `ErrorKind`、`Error`、`DetailedError`、`BasicError`、`ErrorGroup`、`RetryPolicy` | 可恢复失败、重试分类 | 错误聚合、重试/退避 |
| L1 | `runtime` | 诊断、退出、时钟、`RuntimeInfo`、`MemoryStats`、`TaskStats` | 启动诊断、版本 | 运行观测、任务转储 |
| L1 | `meta` | `BuildInfo`、`TargetInfo`、`Capability` | 目标能力判断 | 目标能力判断 |
| L2 | `bytes` | `Bytes`、`ByteReader/Writer`、`ByteBuffer`、`BitSet`、端序 | 协议/文件解析 | 协议/帧解析 |
| L2 | `text` | 文本、`Format`、`Unicode`、`Regex`、`StringBuilder` | 参数/界面文本 | 日志/协议文本 |
| L2 | `collections` | `List/Map/Set`、专用容器、算法 | 本地状态 | 路由/索引/聚合 |
| L2 | `math` | 常量、checked/saturating、统计、`Decimal` | 计算 | 指标/限额计算 |
| L2 | `time` | `Instant/Duration/DateTime/Clock/Stopwatch` | 超时/重试 | 截止/调度/日历 |
| L3 | `io` | `Reader/Writer`、缓冲、行、组合、Stdio | 文件/标准流 | 流式请求/响应 |
| L3 | `fs` | `Path/File/Dir/Metadata/OpenOptions/Temp` | 本地文件 | 配置/日志/上传 |
| L3 | `sys` | `Process/Env/Platform/Signal/SystemInfo` | 启动外部工具 | 进程监督/系统信息 |
| L3 | `log` | `Level/Logger/Field/Sink/Formatter` | 控制台日志 | 结构化日志 |
| L3 | `config` | `Config`、来源、Schema | 本地配置 | 环境/文件/覆盖 |
| L3 | `cli` | `Args/OptionSpec/Command/Parser` | 命令行 | 运维子命令 |
| L4 | 执行层 | `Context/Task/TaskGroup/Mutex/Channel/Atomic*` | 并发请求 | 结构化并发 |

### 1.2 已暴露的缺口

| # | 缺口 | 现状 | 对客户端的影响 | 对服务器的影响 |
| --- | --- | --- | --- | --- |
| G1 | 没有角色模型 | `meta.Capability` 只表示“目标支持” | 无法裁剪安装包 | 无法声明“必须支持监听” |
| G2 | 没有统一资源上限 | 各包各自约定 | 无界队列/连接 | 无界并发/内存 |
| G3 | 没有统一关闭策略 | 各资源自行 `close()` | 退出时请求被硬切 | 无法优雅排空 |
| G4 | 执行层缺高层原语 | 只有 `spawn/join` | 缺 `Future/Promise`、结果多读 | 缺 `RwLock/Semaphore/WaitGroup/Executor` |
| G5 | 没有健康/就绪面 | `TaskStats` 只是统计 | 无连接健康 | 无 readiness/liveness |
| G6 | 配置不能选择画像 | `Config` 只有键值 | profile 散落应用 | 部署参数与能力脱节 |
| G7 | 文档存在非 XNull 语法 | 多处 `self(...)` 构造器委托 | 设计不可照写 | 设计不可照写 |
| G8 | 抽象只能用非泛型协议 | XNull 禁止泛型协议、泛型枚举 | 需要用泛型类/函数补足 | 同左 |

### 1.3 判断

- L1–L4 的**数据与 I/O 能力**已经够用；缺的不是“更多函数”，而是**角色、上限、生命周期、执行原语**。
- 客户端和服务器的差异不在 `bytes/text/collections`，而在：
  - 连接方向（出站 vs 入站）；
  - 并发模型（少量阻塞请求 vs 大量会话/事件循环）；
  - 关闭语义（快速退出 vs 排空）；
  - 资源上限（单机小池 vs 大池/多核）；
  - 观测面（连接状态 vs 就绪/存活/会话）。
- 因此补齐点集中在 `meta`、`runtime`、`config`、执行层，而不是重写 L2/L3。

---

## 2. 能力画像模型

### 2.1 四个概念

```text
RuntimeRole     程序在构建时的角色：Client / Server / Tool / Library
Capability      目标平台或构建允许的能力标记
CapabilitySet   不可变能力集合
CoreProfile     角色 + 能力集合 + 资源上限 + I/O 模型 + 关闭策略
```

`CoreProfile` 是**只读快照**，由构建常量、配置文件或测试代码构造；不做全局可变单例。

### 2.2 角色

| 角色 | 典型程序 | 默认 I/O 模型 | 默认关闭策略 |
| --- | --- | --- | --- |
| `Client` | 桌面/移动/CLI 客户端、SDK 调用方 | `Blocking` | `Immediate` |
| `Server` | API 服务、代理、推送、批处理守护进程 | `EventDriven` 或 `ThreadPerConnection` | `Deadline` |
| `Tool` | 一次性 CLI、脚本、数据转换 | `Blocking` | `Immediate` |
| `Library` | 被其他程序嵌入的库 | `Blocking` | `Immediate` |

`Library` 默认不声明任何可选能力；由宿主显式添加，避免库偷偷要求网络/进程/信号。

### 2.3 能力分层

| 能力组 | 成员 | 客户端 | 服务器 | 工具 | 库 |
| --- | --- | --- | --- | --- | --- |
| 基础 | `Threads`、`Filesystem`、`Unicode`、`Regex`、`Compression`、`Crypto`、`Random`、`DynamicLibrary` | 需要 | 需要 | 需要 | 由宿主决定 |
| 出站 | `NetworkClient`、`DnsResolver`、`TlsClient`、`HttpClient`、`WebSocketClient`、`ProxyClient`、`CookieStore` | 可选/常用 | 少数需要 | 可选 | 默认无 |
| 入站 | `NetworkServer`、`TlsServer`、`HttpServer`、`WebSocketServer`、`ProxyServer` | 无 | 需要 | 无 | 默认无 |
| 平台 | `Process`、`Signals`、`Pty`、`FileWatch`、`Stdio`、`ProcessSupervision`、`Multicore` | 可选 | 常用 | 常用 | 默认无 |
| 安全 | `SecureRandom`、`Tls` | 需要 | 需要 | 可选 | 由宿主决定 |
| 国际化 | `Locale`、`TimeZoneDatabase` | 可选 | 可选 | 可选 | 由宿主决定 |

规则：

- `Capability` 表示“目标/构建允许”，不表示“当前进程一定成功”；运行时失败仍走 `Result`。
- 入站能力不能由客户端画像默认开启；出站能力不能由服务器画像强制开启。
- 能力只追加，不删除；未知能力映射为“不支持”，不 panic。

### 2.4 资源上限

`ResourceLimits` 统一表达：

| 字段 | 含义 | `0` 的语义 |
| --- | --- | --- |
| `maxConcurrentTasks` | 同时运行任务数 | 不限制 |
| `maxConnections` | 同时连接/会话数 | 不限制 |
| `maxQueuedRequests` | 等待队列长度 | 不排队 |
| `maxRequestBytes` | 单请求/单消息入站字节 | 不限制 |
| `maxResponseBytes` | 单响应/单消息出站字节 | 不限制 |
| `maxOpenFiles` | 同时打开文件数 | 不限制 |
| `maxHeapBytes` | 建议堆上限；运行时尽力 | 不限制 |
| `maxRetryAttempts` | 默认重试次数 | 不重试 |
| `defaultTimeoutMillis` | 默认操作截止 | 无默认截止 |
| `shutdownDeadlineMillis` | 排空关闭的最长等待 | 无限等待 |

客户端默认取较小值，服务器默认取较大值；`Library` 默认全 0，由宿主决定。

### 2.5 I/O 模型

| 模型 | 含义 | 适用 |
| --- | --- | --- |
| `Blocking` | 每操作阻塞当前任务 | 客户端、工具、简单服务器 |
| `ThreadPerConnection` | 每连接一个任务/线程 | 中小服务器、协议网关 |
| `EventDriven` | 单/少事件循环 + 回调或任务 | 高连接数服务器、代理 |
| `Hybrid` | 事件循环 + 工作池 | 混合负载 |

模型是**偏好**，不是实现承诺；`net` 可以选择最接近的实现，但必须在文档中声明实际行为。

### 2.6 关闭策略

| 策略 | 语义 |
| --- | --- |
| `Immediate` | 立即取消所有任务/连接；不再接受新工作 |
| `Drain` | 停止接受新工作；等待在途工作自然结束，无截止 |
| `Deadline` | 停止接受；等待到 `shutdownDeadlineMillis`；超时后取消剩余 |

关闭顺序固定：

```text
stop accepting
  → cancel/close listeners
  → drain or cancel in-flight sessions
  → close channels/queues
  → close files/processes/sockets
  → flush/close log sinks
  → exit
```

客户端可跳过 drain；服务器必须实现 `Drain` 或 `Deadline`。

### 2.7 包级角色矩阵

| 包 | Client | Server | Tool | Library | 角色差异 |
| --- | --- | --- | --- | --- | --- |
| `errors` | 必需 | 必需 | 必需 | 必需 | 无 |
| `runtime` | 必需 | 必需 | 必需 | 必需 | 服务器额外用健康/统计 |
| `meta` | 必需 | 必需 | 必需 | 必需 | 画像不同 |
| `bytes` | 必需 | 必需 | 必需 | 可选 | 无 |
| `text` | 必需 | 必需 | 必需 | 可选 | 无 |
| `collections` | 必需 | 必需 | 必需 | 可选 | 服务器偏向大 Map/索引 |
| `math` | 可选 | 可选 | 可选 | 可选 | 无 |
| `time` | 必需 | 必需 | 必需 | 可选 | 服务器用截止/调度 |
| `io` | 必需 | 必需 | 必需 | 可选 | 服务器流式 body |
| `fs` | 可选 | 必需 | 必需 | 由宿主 | 客户端沙箱；服务器日志/配置/上传 |
| `sys` | 可选 | 必需 | 必需 | 由宿主 | 服务器进程监督/信号 |
| `log` | 必需 | 必需 | 必需 | 可选 | 客户端控制台；服务器结构化 sink |
| `config` | 必需 | 必需 | 必需 | 由宿主 | 客户端本地；服务器 env/文件/覆盖 |
| `cli` | 可选 | 可选 | 必需 | 不做 | 服务器运维子命令 |
| 执行层 | 必需 | 必需 | 可选 | 可选 | 客户端小池；服务器大池/读写锁/信号量 |
| `net.uri` | 可选 | 可选 | 可选 | 不做 | 客户端 URL；服务器路由/代理 |
| `net` | 出站 | 入站 | 可选 | 不做 | 客户端连接；服务器监听 |
| `net.tls` | 客户端 | 服务端 | 可选 | 不做 | 证书/SNI/mTLS |
| `net.http` | 客户端 | 服务端 | 可选 | 不做 | 请求/响应 vs 路由/分派 |
| `net.websocket` | 客户端 | 服务端 | 不做 | 不做 | 连接/重连 vs 接受/广播 |
| `net.mime` | 可选 | 可选 | 可选 | 不做 | 无 |
| `utils.*` | 可选 | 可选 | 可选 | 由宿主 | ，不进核心 |

结论：客户端与服务器的真正差异集中在 **L3 `fs/sys/log/config` 的使用方式、执行层并发原语、L5/L6 的入站/出站角色**；
L1/L2 是共同内核，不应按角色复制。

---

## 3. 新增类型总表

### 3.1 `xdk.meta`

| 类型 | 种类 | 能力 | 稳定性 |
| --- | --- | --- | --- |
| `RuntimeRole` | enum | 构建角色 | `stable` |
| `IoModel` | enum | I/O 偏好 | `preview` |
| `ShutdownPolicy` | enum | 关闭策略 | `preview` |
| `CapabilitySet` | class | 不可变能力集合 | `preview` |
| `ResourceLimits` | class | 资源上限快照 | `preview` |
| `CoreProfile` | class | 角色画像 | `preview` |
| `ProfileBuilder` | class | 画像构造器 | `preview` |

### 3.2 `xdk.config`

| 类型 | 种类 | 能力 | 稳定性 |
| --- | --- | --- | --- |
| `ProfileSource` | protocol | 画像来源 | `preview` |
| `ConfigProfileSource` | class | 从 `Config` 读取画像 | `preview` |

### 3.3 执行层内建

| 类型 | 种类 | 能力 | 稳定性 |
| --- | --- | --- | --- |
| `Executor` | class | 有界并发提交 | `preview` |
| `Semaphore` | class | 许可计数 | `preview` |
| `RwLock<T>` | class | 读写锁 | `preview` |
| `WaitGroup` | class | 等待计数 | `preview` |
| `Once` | class | 只执行一次 | `preview` |
| `Pool<T>` | class | 通用对象池 | `preview` |
| `Future<T>` | class | 多读者结果 | `preview` |
| `Promise<T>` | class | 一次性完成 | `preview` |

### 3.4 `xdk.runtime`

| 类型 | 种类 | 能力 | 稳定性 |
| --- | --- | --- | --- |
| `HealthState` | enum | 健康状态 | `preview` |
| `HealthReport` | class | 健康快照 | `preview` |
| `HealthCheck` | protocol | 单项健康检查 | `preview` |
| `HealthRegistry` | class | 聚合健康检查 | `preview` |

### 3.5 明确不新增

- 不新增 `xdk.net` 的客户端/服务器类型；`TlsClient/TlsServer/HttpClient/HttpServer/WebSocketClient/WebSocketServer` 已在 L5/L6 设计。
- 不新增全局连接池、全局 DNS 缓存、全局画像单例。
- 不把 `RuntimeRole` 做成运行时可变开关；构建后只读。
- 不新增泛型协议、泛型枚举或 `new T()`；XNull 不支持。

### 3.6 类型形态覆盖

| 形态 | 已有/新增代表 | 用途 |
| --- | --- | --- |
| 简单枚举 | `ErrorKind`、`Level`、`ExitCode`、`RoundingMode`、`RuntimeRole`、`IoModel`、`ShutdownPolicy`、`HealthState` | 封闭分类、稳定序号 |
| 数据枚举 | 本设计不新增；状态用简单枚举 + 类承载 | 需要字段的封闭项可用数据枚举 |
| 非泛型协议 | `Error`、`Reader`、`Writer`、`Sink`、`ConfigSource`、`ValueParser`、`TaskHandle`、`ProfileSource`、`HealthCheck` | 能力合同/依赖注入 |
| 普通类 | `BasicError`、`Config`、`Logger`、`Process`、`File`、`HealthReport` | 引用语义/资源/身份 |
| 泛型类 | `List<T>`、`Map<K,V>`、`Channel<T>`、`Mutex<T>`、`Task<T>`、`Pool<T>`、`RwLock<T>`、`Future<T>`、`Promise<T>` | 参数化容器/状态 |
| 泛型方法 | `TaskGroup.spawn<T>`、`Executor.submit<T>`、`Map.getOr` 等既有方法 | 参数化操作 |
| 抽象 | 协议 + 具体实现类；`abstract class` 仅用于复用，不声明抽象方法 | XNull 的唯一多态入口是协议 |
| 扩展 | `extension`（语言能力）用于非泛型目标的方法补充 | 不给核心类型加“万能工具” |

约束：

- XNull 禁止泛型协议/泛型枚举；因此“泛型抽象”由泛型类 + 非泛型协议组合表达。
- XNull 的 `abstract` 类不能声明抽象方法；抽象行为必须由协议承载。
- `struct` 可以实现值语义快照，但不能实现协议；需要多态时用 `class`。
- 不为“类型齐全”强行给每个包加 enum/protocol；只在有语义边界时引入。

---

## 4. 客户端核心

### 4.1 能力需求

| 需求 | 核心支撑 | 网络支撑 |
| --- | --- | --- |
| 解析地址 | `DnsResolver`（L5） | `xdk.net` |
| 建立出站连接 | `CoreProfile` 出站能力 + `Context` | `TcpStream/TlsClient` |
| 请求/响应 | `Reader/Writer`、`bytes`、`text` | `HttpClient` |
| 长连接推送 | 执行层 `Task/TaskGroup/Channel` | `WebSocketClient` |
| 重试/退避 | `RetryPolicy`、`time` | 应用组合 |
| 代理/Cookie | 能力标记 + `Config` | `HttpProxyConfig/CookieJar` |
| 凭据 | `Config` 白名单 + `SecureRandom` | `TlsConfig` |
| 本地缓存 | `LRUCache`、`fs` | 应用组合 |
| 快速退出 | `ShutdownPolicy.Immediate` | `close()` |

### 4.2 客户端启动顺序

```text
main
  → cli.Args
  → config.Config（文件/环境/覆盖）
  → ConfigProfileSource.load
  → CoreProfile.client()
  → 校验 targetInfo() 能力与资源上限
  → log.Logger
  → net 客户端（HttpClient/WebSocketClient/TlsClient）
  → TaskGroup
  → 业务
  → close 资源
  → runtime.exit
```

### 4.3 客户端约束

- 默认 `ShutdownPolicy.Immediate`；长连接/上传场景显式改 `Drain`。
- 默认 `maxConnections` 较小；连接池必须显式持有，不能用全局池。
- 客户端不得默认启用 `NetworkServer/ProcessSupervision/Signals`。
- 所有阻塞调用首参 `Context`；取消返回 `Cancelled`，超时返回 `Timeout`。
- UI 线程/事件线程不得执行长阻塞调用；用 `Executor`/`Future` 转移到工作上下文。

---

## 5. 服务器核心

### 5.1 能力需求

| 需求 | 核心支撑 | 网络支撑 |
| --- | --- | --- |
| 绑定/监听 | `CoreProfile` 入站能力 | `TcpListener/TlsServer/HttpServer` |
| 接受/会话 | `TaskGroup/Executor` | `HttpExchange/WebSocket` |
| 并发上限 | `Semaphore/ResourceLimits` | `HttpServerOptions` |
| 共享状态 | `RwLock/Mutex/Atomic*` | 应用组合 |
| 背压 | `Channel`、`Semaphore` | `trySend`/队列 |
| 优雅停机 | `ShutdownPolicy`、`Signal` | `HttpServer.close` |
| 健康 | `HealthRegistry` | 应用组合 |
| 观测 | `log`、`TaskStats`、`MemoryStats` | 应用组合 |
| 进程监督 | `sys.Process`、`ProcessSupervision` | 应用组合 |

### 5.2 服务器启动顺序

```text
main
  → cli.Args
  → config.Config + ConfigProfileSource
  → CoreProfile.server()
  → 校验资源上限、入站能力与 targetInfo() 能力
  → log.Logger
  → HealthRegistry（注册 db/cache/queue 检查）
  → TaskGroup（根上下文）
  → TlsConfig/HttpServer.bind
  → 安装信号/取消钩子
  → serve
  → 收到信号/取消
  → 停止 accept
  → Drain/Deadline 等待在途
  → 关闭会话/通道/文件/进程
  → flush/close 日志
  → exit
```

### 5.3 服务器约束

- 默认 `ShutdownPolicy.Deadline`，必须有排空上限；不允许无界等待。
- `maxConcurrentTasks`、`maxConnections`、`maxQueuedRequests` 必须显式或由服务器默认给出。
- 入站能力必须由 `CoreProfile` 声明；未声明而调用监听/服务端 TLS 是配置错误。
- 每个会话一个 `Context`；客户端断开/超时必须取消该会话上下文。
- 健康检查不得阻塞请求路径；慢检查用缓存快照。
- 日志 sink、文件、进程、连接必须在正常/失败/取消三条路径关闭。

---

## 6. 抽象与泛型的 XNull 约束

XNull 不支持泛型协议、泛型枚举、协议关联类型、协议泛型方法和 `where` 约束。因此本设计遵循：

| 需求 | 允许的表达 | 不允许的表达 |
| --- | --- | --- |
| 通用能力合同 | 非泛型 `protocol`（如 `HealthCheck`） | `protocol Repository<T>` |
| 参数化容器/状态 | 泛型 `class`（如 `Pool<T>`、`RwLock<T>`、`Future<T>`） | 泛型 `protocol` |
| 参数化算法 | 泛型函数/方法（如 `submit<U>`、`withRead<U>`） | 泛型闭包 |
| 错误分类 | `enum ErrorKind` | 泛型枚举 |
| 配置快照 | 不可变 class + `with*` | 全局可变单例 |
| 回调 | 函数类型（如 `Result<T,Error>()`） | 泛型协议 + 关联类型 |
| 类型选择 | `Capability` + `CoreProfile` | 运行时反射/宏 |

这条约束必须在评审中显式检查，避免设计出语言无法表达的 API。

---

## 7. 依赖与分层

```text
L1 meta        RuntimeRole / Capability / CapabilitySet /
               ResourceLimits / CoreProfile / ProfileBuilder
L1 runtime     HealthState / HealthReport / HealthCheck / HealthRegistry
L1 errors      RetryPolicy / ErrorGroup / ResultOps
L2 bytes/text/collections/math/time
L3 io/fs/sys/log/config/cli
L4 execution   Executor / Semaphore / RwLock<T> / WaitGroup /
               Once / Pool<T> / Future<T> / Promise<T>
L5 net         Tcp/Tls/Udp/Dns/Pool
L6 net.http/ws/mime
```

规则：

- `meta` 不依赖其他包；`CoreProfile` 不返回 `Result`，避免 `meta -> errors`。
- `config` 新增 `meta` 依赖；`ProfileSource` 用 `Result` 表达加载失败。
- `runtime` 的健康面不依赖 `errors`、`execution`；检查必须非阻塞。
- 执行层新类型只依赖 `errors`、`runtime`、`Context`。
- 网络具体类型仍在 L5/L6；核心不复制 `TcpStream/HttpServer`。
- 硬件/OS/桌面/GPU/防火墙不在 core；归属见 [`PLATFORM-BOUNDARY.md`](PLATFORM-BOUNDARY.md)，
包设计见 [`../platform/os/README.md`](../platform/os/README.md)。

---

## 8. 场景验证

### P1：桌面客户端

```text
CoreProfile.client()
  → HttpClient
  → Executor.fixed(ctx, 4)
  → Future<Response> 并发拉取
  → 取消按钮 → Context.cancel
  → close 客户端
```

验收：客户端画像不含入站能力；取消后不再写缓存；退出不等待网络排空。

### P2：API 服务器

```text
CoreProfile.server()
  → HealthRegistry
  → HttpServer.bindTls
  → Semaphore(1024) 限制在途
  → RwLock<Cache> 共享缓存
  → SIGTERM → 停止 accept → Drain(30s)
```

验收：超限请求返回 `Busy`/`Unavailable`；健康检查可读；停机不丢在途响应。

### P3：CLI 工具

```text
CoreProfile.tool()
  → fs/io/text/collections
  → runProcessResult
  → exitCode
```

验收：不隐含网络/信号能力；文件句柄在失败路径关闭。

### P4：嵌入式库

```text
CoreProfile.library()
  → 宿主注入能力
  → 无全局状态
```

验收：库不启动监听、不读取全局配置、不创建全局执行器。

### 8.5 最小 XNull 装配示例

客户端：

```xnull
static Int main(String[] arguments) {
    Config config = new Config("client")
    config.set("profile.role", "client")
    config.set("profile.maxConnections", "16")
    ProfileSource source = new ConfigProfileSource(config)
    Result<CoreProfile, Error> loaded = source.load(Context.background())
    if loaded.isErr() {
        diagnose("profile: " + loaded.error().describe())
        return 2
    }
    CoreProfile profile = loaded.value()
    if !profile.supports(Capability.HttpClient) {
        diagnose("http client capability missing")
        return 2
    }
    Executor executor = Executor.fixed(Context.background(), 4)
    Logger logger = new Logger("client", Level.Info, new ConsoleSink(Stdio.stdout()))
    logger.info("client profile: " + profile.describe())
    Result<Unit, Error> closed = executor.close()
    if closed.isErr() {
        diagnose("close: " + closed.error().describe())
        return 1
    }
    return 0
}
```

服务器：

```xnull
static Int main(String[] arguments) {
    Config config = new Config("server")
    config.set("profile.role", "server")
    config.set("profile.shutdown", "deadline")
    config.set("profile.shutdownDeadlineMillis", "30000")
    ProfileSource source = new ConfigProfileSource(config)
    Result<CoreProfile, Error> loaded = source.load(Context.background())
    if loaded.isErr() {
        diagnose("profile: " + loaded.error().describe())
        return 2
    }
    CoreProfile profile = loaded.value()
    if !profile.supports(Capability.HttpServer) {
        diagnose("http server capability missing")
        return 2
    }
    HealthRegistry health = new HealthRegistry()
    health.add(new ProcessHealthCheck("runtime"))
    Logger logger = new Logger("server", Level.Info, new ConsoleSink(Stdio.stdout()))
    logger.info("server profile: " + profile.describe())
    HealthReport report = health.checkAll()
    if !report.isReady() {
        diagnose("not ready: " + report.describe())
        return 1
    }
    return 0
}
```

> `ProcessHealthCheck` 是应用/测试实现，不在核心层定义；核心只提供 `HealthCheck` 合同。

---

## 9. 缺口处置

| 缺口 | 处置 | 文档 |
| --- | --- | --- |
| 角色模型 | 新增 `RuntimeRole`、`CoreProfile`、`ProfileBuilder` | `meta/` |
| 能力集合 | 新增 `CapabilitySet`；`Capability` 只追加 | `meta/` |
| 资源上限 | 新增 `ResourceLimits` | `meta/` |
| 画像配置 | 新增 `ProfileSource`、`ConfigProfileSource` | `config/` |
| 服务器并发 | 新增 `Executor/Semaphore/RwLock/WaitGroup/Once` | `execution/` |
| 客户端异步 | 新增 `Future/Promise` | `execution/` |
| 资源复用 | 新增 `Pool<T>` | `execution/` |
| 健康/就绪 | 新增 `HealthState/HealthReport/HealthCheck/HealthRegistry` | `runtime/` |
| 非 XNull 语法 | 修复 `self(...)` 等构造器委托写法 | 各文档 |
| 网络类型 | 复用 `docs/design/network/net`，不重复定义 | L5/L6 |

---

## 10. 验收谓词

- 每个新增公开类型有独立 PascalCase 文件、完整 12/14 项契约和 XNull 伪代码。
- 每个新增方法有用途、参数、返回、失败、并发/取消说明。
- `CoreProfile` 不依赖 `Error/Context`；`ProfileSource` 才返回 `Result`。
- 客户端画像默认不含入站能力；服务器画像默认含入站能力与关闭上限。
- 所有泛型只出现在 class/函数/方法上，不出现泛型 protocol/enum。
- 不出现 `self(...)`、`self._private`、`new T()`、`// ...` 等非 XNull 或省略写法。
- `docs/design/solutions/ml` 的类型索引与文件一一对应。
- 网络能力仍只由 L5/L6 定义，核心文档不复制 `TcpStream/HttpServer`。

---

## 11. 变更记录

- 2026-11-21：首版。补齐客户端/服务器能力画像、资源上限、关闭策略、健康面、执行层扩展与 XNull 约束。
