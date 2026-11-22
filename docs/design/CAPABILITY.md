# XDK API 面 — 分层能力详细分析

> **2.x 状态**：本文件是设计覆盖分析，不是实现依据。包名/类型以 [`PACKAGE-MAP.md`](PACKAGE-MAP.md) 与逐类型合同为准；旧名对照见 [`DESIGN-CONSISTENCY.md`](DESIGN-CONSISTENCY.md)。

> 当前领域设计见 [`README.md`](README.md)；本文件分析 core/net/utils 的设计覆盖，不声明当前目录/顺序。


| 项 | 值 |
| --- | --- |
| 文档性质 | 能力分析；基于 [`API-SURFACE.md`](API-SURFACE.md) 与 [`SCENARIOS.md`](SCENARIOS.md)，不写代码 |
| 范围 | `xdk.core`、`xdk.net`、`xdk.utils` |
| 目标 | 回答“XDK 每一层能做什么、到什么程度、还缺什么” |
| 注意 | 本文评的是**设计覆盖**，不是实现验证；实现状态另算 |

---

## 0. 分析口径

### 0.1 六个维度

每个包按六个维度评估：

| 维度 | 问题 |
| --- | --- |
| 能力面 | 能做什么？覆盖哪些业界常规能力？ |
| 方法深度 | 类上有多少方法/重载/边界操作？ |
| 场景闭环 | 能否支撑真实程序，而不是示例？ |
| 契约完整 | 失败/取消/资源/所有权/并发是否清楚？ |
| 可扩展 | 是否有 X/扩展点，不堵死后续？ |
| 注解契约 | 哪些声明可由注解在编译期检查/生成，且不引入运行时反射？ |

### 0.2 成熟度

| 等级 | 含义 |
| --- | --- |
| C0 | 只有名字/骨架 |
| C1 | 最小 Demo，方法面很窄 |
| C2 | 对齐业界常规 API，能写真实程序 |
| C3 | 覆盖边界/错误/取消/资源/并发，有场景 |
| C4 | 生态级：扩展点/可观测/性能/兼容承诺 |

> API 面的目标：core/net 设计到 C3，utils 到 C2–C3。  
> 本文的等级是**设计覆盖等级**，不是“已实现/已验证”。

### 0.3 旧版 → API 面的变化

| 维度 | 旧版 | API 面 |
| --- | --- | --- |
| 包范围 | core 14 + net 6（网络只到基础） | core 15 + net 6（含 X）+ utils 24 |
| 类方法面 | 很多类 3–8 个方法 | 常规类 10–30 个方法，容器/文本/HTTP 更多 |
| 容器 | List/Map/Set 基础 | + Deque/Stack/Queue/MultiMap/BiMap/LRUCache/Range/Iterator/算法族 |
| 文本 | trim/split/parse | + StringBuilder/Joiner/Format/Unicode/Escape/完整 Regex |
| IO | Reader/Writer 内存 | + Buffered/Line/Chain/Tee/Limit/Counting/Peek/Stdio/协议 |
| FS | exists/read/write | + Path/OpenOptions/File/Dir/Metadata/Permissions/Temp/FileSystem/Atomic |
| SYS | Process/Env 最小 | + ProcessBuilder/SystemInfo/Cpu/Memory/Disk/User/Signal |
| 网络 | TCP/UDP/HTTP/WS 基础 | + 代理/CONNECT/HTTP2/连接池/DNS 缓存/mTLS/WS 重连 |
| 工具 | 基本没有 | + 24 个单一职责工具包 |
| 场景 | 核心/网络少量 | 8 个端到端场景，覆盖服务/监控/中间件/CLI/协议/推送/传输/mTLS |

---

## 1. 分层总图

> 层号只表示依赖方向，不是目录结构、发布顺序或实现顺序；各领域文档才是契约权威。

```text
L8 应用
  ▲
L7 工具组 utils
  ▲
L6 网络协议 http / websocket / mime
  ▲
L5 网络传输 net.uri / net / tls
  ▲
L4 执行层 tasks / sync
  ▲
L3 IO 与系统 io / fs / sys / log / config / cli
  ▲
L2 数据与计算 bytes / text / collections / math / time
  ▲
L1 基础 errors / runtime / meta
  ▲
L0 语言原语
```

依赖原则：

- 上层依赖下层；反向依赖禁止。
- `net` 不进入 `core`；`core` 保持无网络。
- `utils` 可以依赖 `core`/`net`；不得被 `core`/`net` 反向依赖（除必要的 codec/crypto 适配由上层注入）。
- 执行层 `tasks/sync` 是语言内建；包名只做兼容。

---

## 2. L1：基础层

### 2.1 能力概览

| 包 | 能做什么 | 方法深度 | 设计成熟度 | 主要缺口 |
| --- | --- | --- | --- | --- |
| `errors` | 分类/构造/包装/报告/聚合/重试/Result 组合 | 高：BasicError 15+、ErrorGroup 15+、ResultOps 15+ | C3 | 错误码注册表、错误链可视化、i18n 消息 |
| `runtime` | 诊断/退出/时钟/运行时信息/内存/任务统计 | 中：RuntimeInfo 10+、MemoryStats/TaskStats | C2–C3 | 堆/GC 细节、帧栈格式 |
| `meta` | 版本/目标/构建/能力矩阵 | 中：BuildInfo/TargetInfo/Capability | C2 | 编译器/依赖元数据边界（不讨论实现） |

### 2.2 分析

- `errors` 是 API 面 最完整的包之一：不再只有 `BasicError`，而是“分类 + 构造 + 聚合 + 重试 + 匹配 + 收集 + Sink”。
- `runtime` 仍然刻意保持小；它不应该变成 sys/env/config 的重复入口。
- `meta` 的价值在“可诊断/可条件分支”，不是构建系统；构建元数据只读。

**结论**：L1 设计达到 C3（errors）/C2–C3（runtime/meta），可以作为所有层的稳定地基。

---

## 3. L2：数据与计算层

### 3.1 能力矩阵

| 包 | 核心能力 | 业界对齐 | 设计成熟度 | 关键缺口 |
| --- | --- | --- | --- | --- |
| `bytes` | Bytes/Builder/ByteBuffer/Reader/Writer/BitSet/端序/位 | Go bytes、Java ByteBuffer、.NET Span | C3 | 零拷贝视图、内存映射、SIMD 加速 |
| `text` | 查找/变换/构建/格式化/解析/Unicode/Regex | Go strings、Java String、Python str、.NET string | C3 | 完整 Unicode 规范化、ICU 级大小写、模板引擎 |
| `collections` | List/Map/Set/Deque/Stack/Queue/专用容器/算法族 | Java Collections、Go slices/maps、.NET Collections | C3 | 持久化容器、并发容器、惰性迭代器性能 |
| `math` | 常量/取整/幂/三角/数论/Int128/Decimal/统计 | Go math、Java Math/BigDecimal、Python statistics | C2–C3 | 任意精度、矩阵/张量（）、高级统计 |
| `time` | Duration/Instant/DateTime/Date/Time/Zone/Clock/格式化 | Go time、Java java.time、.NET DateTime | C2–C3 | IANA 时区库、完整 locale、日历系统 |

### 3.2 方法深度

- `bytes`：从 4 个运行时成员扩到 30+ 方法（Bytes/Builder/ByteBuffer/BitSet/Reader/Writer）。
- `text`：从 15 个函数扩到 50+（StringBuilder/Joiner/Format/Unicode/Escape/Regex）。
- `collections`：从基础容器扩到 20+ 类型、80+ 算法/方法。
- `math`：从函数组扩到 Decimal/RoundingMode/统计/回归/直方图。
- `time`：从 Duration/DateTime 扩到 Instant/Date/Time/Zone/Clock/Formatter/Parser/Stopwatch/Timer。

### 3.3 分析

- L2 是 API 面 提升最大的层：旧版 很多“要用户自己写循环”的能力现在进入标准库。
- 但仍要避免“为了方法多而方法多”：每个方法必须有场景/契约。
- `collections` 的泛型/迭代器是最大语言依赖点；设计上保留 `Iterator<T>`/`Iterable<T>` 为 X。
- `math` 的 `Decimal` 是金额/精确计算的关键；`Int128` 是语言标量，不是类。
- `time` 的时区数据库是 X；core 只保证 UTC/固定偏移。

**结论**：L2 设计达到 C3，具备“真实数据处理程序”的方法面；性能/内存/迭代器是后续重点。

---

## 4. L3：IO 与系统层

### 4.1 能力矩阵

| 包 | 核心能力 | 业界对齐 | 设计成熟度 | 关键缺口 |
| --- | --- | --- | --- | --- |
| `io` | Reader/Writer/Seekable/Closer + Buffered/Line/Chain/Tee/Limit/Counting/Peek/Stdio | Go io/bufio、Java IO/NIO、.NET Stream | C3 | 异步 IO、零拷贝、内存映射 |
| `fs` | Path/OpenOptions/File/Dir/Metadata/Permissions/Temp/FileSystem/Atomic | Go os/path/filepath、Java NIO、Python pathlib | C3 | WatchService、文件锁、扩展属性 |
| `sys` | ProcessBuilder/Process/Env/Platform/Signal/SystemInfo/Cpu/Memory/Disk/User | Go os/exec、Java ProcessBuilder、.NET Process | C2–C3 | 进程组/PTY、cgroup、容器信息 |
| `log` | Level/Logger/Factory/Field/Record/Sink/Filter/Formatter/Redactor/Rotation/Async | Go slog、SLF4J/Logback、.NET ILogger | C3 | 采样策略、远程 sink、结构化日志协议 |
| `config` | Config/Source/Loader/Schema/Typed/Snapshot/Watcher | Viper、Spring Config、dynaconf、.NET Config | C2–C3 | 热更新、远程配置、密钥管理 |
| `cli` | Args/OptionSpec/Flag/Command/CommandGroup/Parser/Help/Completion/ExitCode | Cobra、picocli、argparse、System.CommandLine | C2–C3 | shell 补全脚本、交互式 TUI |

### 4.2 分析

- `io` 从“内存 Reader/Writer”提升为“流协议 + 组合器 + Stdio”，这是旧版最大的实用缺口之一。
- `fs` 从 3 个函数提升为完整文件系统面；`OpenOptions`/`Metadata`/`Permissions`/`Temp`/`Atomic` 是生产必需。
- `sys` 的 `ProcessBuilder` 是进程管理的关键；`SystemInfo` 让监控程序不需要自己解析 `/proc`。
- `log`/`config`/`cli` 是“可部署程序”的三件套；API 面 已从最小面提升到可配置、可观测、可帮助。
- 仍要避免把“Web 框架/模板/ORM”塞进 L3。

**结论**：L3 设计达到 C3（io/fs/log）/C2–C3（sys/config/cli），能支撑本地工具、服务端、监控程序。

---

## 5. L4：执行层

### 5.1 能力矩阵

| 包 | 核心能力 | 设计成熟度 | 关键缺口 |
| --- | --- | --- | --- |
| `tasks` | Context/Task/TaskGroup/Executor/Timer/Future/Promise/Select | C2–C3 | 调度公平性、优先级、实时性 |
| `sync` | Mutex/RwLock/Semaphore/WaitGroup/Once/Barrier/Channel/Atomic/Lazy/Broadcast/PubSub | C2–C3 | 无锁容器、并发 Map/Queue、公平锁 |

### 5.2 分析

- API 面 把旧版缺的 `RwLock/Semaphore/WaitGroup/Once/Barrier` 补齐，`Executor/Timer/Future/Promise/Select` 让并发不只是 `spawn/join`。
- 语言内建 `Context/Task/TaskGroup/Channel/Mutex/Atomic` 仍是底座；包只做兼容/扩展。
- 并发设计最怕“API 很多但语义不清”；API 面必须坚持：取消、关闭、幂等、死锁边界写清楚。
- 不承诺公平性/实时性；这些是 X/。

**结论**：L4 设计达到 C2–C3；真实程序可用，但并发压力/竞态/公平性需要实现验证。

---

## 6. L5：网络传输层

### 6.1 能力矩阵

| 包 | 核心能力 | 设计成熟度 | 关键缺口 |
| --- | --- | --- | --- |
| `net.uri` | Uri/Builder/Query/Url/PercentCodec/Template | C2–C3 | IDN、URI 模板高级语法 |
| `net` | IP/Prefix/SocketAddress/DNS/ByteStream/TCP/UDP/连接池/网卡 | C3 | 多路径、零拷贝、IO uring、QUIC 底层 |
| `net.tls` | 证书/私钥/信任库/TlsConfig/TlsStream/mTLS/ALPN | C2–C3 | OCSP/CRL、HSM、热轮换、QUIC TLS |

### 6.2 分析

- `net` 从“Socket 基础”提升到“地址 + DNS 缓存 + TCP/UDP + 连接池 + ByteStream”，这是服务端/代理的基础。
- `net.uri` 补齐 Query/Url/PercentCodec/Builder，避免用户自己拼 URL。
- `net.tls` 补齐证书链/mTLS/ALPN/校验策略，能从“能握手”到“能上生产”。
- 仍不设计 QUIC/HTTP3；QUIC 是 /后续，不应硬塞进 TCP/TLS API。
- 不暴露裸 socket/TLS 上下文；保持资源/取消/错误合同。

**结论**：L5 设计达到 C3（net）/C2–C3（uri/tls），能支撑 TCP/UDP/TLS 服务与客户端。

---

## 7. L6：网络协议层

### 7.1 能力矩阵

| 包 | 核心能力 | 设计成熟度 | 关键缺口 |
| --- | --- | --- | --- |
| `net.http` | HTTP/1.1、HTTP/2、客户端/服务端、代理/CONNECT、Cookie/Form/Multipart/Auth/连接池 | C3 | HTTP/3、HTTP/2 优先级、代理 MITM、Web 框架 |
| `net.websocket` | 客户端/服务端、文本/二进制、ping/pong、背压、压缩、重连 | C3 | 消息重放、HTTP/2 WebSocket、连接迁移 |
| `net.mime` | MediaType/参数/扩展名 | C2–C3 | 完整 IANA 表、内容嗅探 |

### 7.2 分析

- `net.http` 是 API 面 网络层最大的提升：从“请求/响应”扩到 Cookie/Form/Multipart/Auth/代理/CONNECT/HTTP2/连接池。
- `HttpExchange` 解决了流式 body + upgrade 的关键问题；`HttpRouter`/`HttpMiddleware` 只作为 X，不把 XDK 变成 Web 框架。
- `net.websocket` 从“收发文本”提升到心跳/背压/压缩/重连/统计，能支撑推送服务。
- 仍不设计 MQTT/AMQP/SIP/Modbus 等应用协议；这些是 ecosystem。
- HTTP/3/QUIC 不进 1.0；WebSocket over HTTP/2 是 X。

**结论**：L6 设计达到 C3（http/websocket）/C2–C3（mime），能支撑 API 服务、推送服务、反向代理/隧道。

---

## 8. L7：工具组

### 8.1 能力矩阵

| 子包 | 核心能力 | 业界对齐 | 设计成熟度 |
| --- | --- | --- | --- |
| `xdk.codec` | JSON/CSV/Base64/Hex/URL | encoding/json、Jackson、Python json/csv | C3 |
| `xdk.crypto` | Hash/HMAC/AES/ChaCha/KDF/常量时间/CRC | Go crypto、JCA、Python cryptography | C2–C3 |
| `xdk.compress` | gzip/zlib/zip | Go compress、Java zip、.NET Compression | C2–C3 |
| `xdk.random` | PRNG/SecureRandom/采样/洗牌 | Go math/rand、Java Random、.NET Random | C3 |
| `xdk.uuid` | UUID v4/v7/ULID/Snowflake | google/uuid、Java UUID、.NET Guid | C3 |
| `xdk.functional` | Seq/序列/惰性/组合 | Guava、Kotlin Sequences | C2 |
| `xdk.stats` | 统计/直方图/回归/移动平均 | Python statistics、Commons Math | C2–C3 |
| `xdk.resilience` | 熔断/限流/重试/降级/并发舱 | Resilience4j、Polly | C2 |
| `xdk.validate` | 规则/Schema/错误聚合 | Jakarta Validation、pydantic | C2–C3 |
| `xdk.cache` | LRU/TTL/Loading/统计 | Guava/Caffeine、MemoryCache | C3 |
| `xdk.queue` | 有界/阻塞/批处理 | Java BlockingQueue、.NET Channels | C2–C3 |
| `xdk.schedule` | cron/周期/JobHandle | Quartz、cron、.NET Timer | C2–C3 |
| `xdk.metrics` | Counter/Gauge/Histogram/MetricTimer/Registry/Exporter | Micrometer、Prometheus | C2–C3 |
| `xdk.trace` | Tracer/Span/Propagator/Sampler | OpenTelemetry | C2 |
| `xdk.audit` | 审计事件/Sink/脱敏 | 审计日志 | C2 |
| `xdk.event` | 事件/订阅/同步发布 | Guava EventBus、.NET events | C2 |
| `xdk.reflect` | 只读类型元数据 | Go reflect、Java reflection | C2 |
| `xdk.graph` | 图/遍历/拓扑/最短路 | JGraphT | C2 |
| `xdk.terminal` | TTY/ANSI/进度/表格/提示 | ANSI/progress/prompt | C2–C3 |
| `xdk.i18n` | Locale/消息/复数/格式 | ICU、ResourceBundle | C2 |
| `xdk.test` | 断言/Suite/Runner | JUnit、pytest、xUnit | C2 |
| `xdk.yaml` | 多文档/属性源/profiles/锚点 | Spring Boot、SnakeYAML | C2–C3 |
| `xdk.toml` | 解析/生成 | TOML 1.0 | C2 |
| `xdk.xml` | 解析/生成/树 | XML DOM | C2 |

### 8.2 分析

- 工具组从“没有”到 24 个子包，覆盖数据编码、安全、压缩、随机、标识、函数式、统计、韧性、校验、缓存、队列、调度、指标、追踪、审计、终端、i18n、测试、事件、反射、图、YAML/TOML/XML。
- 这些包不是“每个都做到 C4”；API 面目标是 C2–C3，先覆盖常规能力，再按场景加深。
- 最关键的是 `codec/cache/queue/metrics/trace` 以及 `xdk.runtime` 的健康检查：它们让服务端/中间件从“能跑”到“可运维”。
- 安全相关（crypto/tls/audit/validate）必须谨慎：默认安全、显式降级、私钥不入日志。
- 工具组不得变成“util 垃圾场”：每个子包单一职责；公共 API 不放杂项。

**结论**：L7 设计覆盖 C2–C3；`codec/crypto/cache/queue/metrics` 是优先实现对象；`regex/health/resource` 分别由 `xdk.text`/`xdk.runtime`/`xdk.sys` 承担。

---

## 9. 跨层能力

### 9.1 错误

| 层 | 错误面 |
| --- | --- |
| L1 | ErrorKind/BasicError/ErrorGroup/RetryPolicy |
| L2 | 解析/越界/编码错误 → Result |
| L3 | 文件/进程/配置/CLI 错误 → Result + ErrorKind |
| L4 | Cancelled/Timeout/Unavailable |
| L5/L6 | Network/Timeout/PermissionDenied/DataCorrupted/Unsupported |
| L7 | Codec/Validation/Crypto/Queue 错误 → Result |

结论：错误模型是统一的；没有“每层一套错误”。

### 9.2 取消与超时

- L3 的阻塞 IO、L5/L6 的网络、L7 的队列/调度都接受 `Context`。
- 取消不吞、不伪装；`ErrorGroup` 遇到 `Cancelled` 优先返回 `Cancelled`。
- 超时是 `Timeout`；不把超时伪装成 `Cancelled`。

### 9.3 资源

- L3 文件/目录/进程；L5 TCP/TLS；L6 HTTP/WS；L7 文件/队列/缓存（可选 close）。
- 统一 `isOpen()` + 幂等 `close()`。
- 关闭失败只诊断，资源视为释放。

### 9.4 所有权

- L2 容器/字节：借用/副本/转移明确。
- L3 文件/流：句柄所有权明确。
- L5/L6 网络：连接/流/body 所有权明确。
- L7 缓存/队列：元素引用/副本明确。

### 9.5 可观测

- L1 诊断/运行时信息。
- L3 日志。
- L7 指标/追踪/健康/审计。
- 四者组合可以支撑生产服务，而不是只有 `print`。

### 9.6 安全

- L5 TLS/mTLS/证书校验。
- L7 crypto/validate/audit/redactor。
- 默认安全：证书校验默认开启；`None` 必须显式；私钥不入日志；审计可脱敏。

### 9.7 注解

注解是**跨层编译期契约与生成入口**，不是运行时反射：

| 层 | 注解面 | 编译期产物 |
| --- | --- | --- |
|  | `@Target`/`@Retention`/`@Repeatable`、`@Data`/`@Value`/`@Builder`/`@Copy`/`@Delegate`、元模型/处理器合同 | 元模型、派生成员、`AnnotationRegistry` |
|  / L1 | `@ReadOnly`/`@Override`/`@Deprecated`/`@SuppressWarnings` | 字段/协议/API 生命周期检查 |
| L5/L6 | `@HttpRoute`/`@HttpMethod`/`@Header`/`@Query`/`@Body`/`@StatusCode`/`@WebSocketHandler`、`@Sql`/`@Param`/`@Row`/`@Column`、`@JwtClaim`/`@JwtHeader` | 路由表、参数绑定、DAO/行映射、claims 映射 |
|  / L7 | `@Serializable`/`@JsonName` 等、`@Validate`、`@Cacheable`/`@Retry` 等、`@Metered`/`@Traced`/`@Audited`、`@Test`/`@Scheduled` | 编解码器、校验器、包装器、测试清单/作业注册 |
| / | `@Packed`/`@Align`/`@NativeLayout`/`@Device`/`@Gpio`/`@I2cAddress`/`@SerialPort`/`@GpuKernel`/`@TensorOp`/`@LinalgOp`；`@Api`/`@Entity`/`@Transactional`/`@Tool`/`@Resource`/`@Prompt`/`@Pipeline` 等 | 布局校验、设备/能力注册、路由/DI/ORM/MCP/管线 |

注解不改变 API 面的分层与包计数，只作为第六个能力维度评估；运行时只读生成表，无反射/类路径扫描/动态代理。完整矩阵见 [`ANNOTATION-SYSTEM.md`](ANNOTATION-SYSTEM.md) §5。

---

## 10. 依赖分析

### 10.1 合法依赖

```text
xdk.errors/runtime/meta
  ├─ xdk.bytes
  ├─ xdk.collections
  ├─ xdk.math
  ├─ xdk.text → bytes
  ├─ xdk.time → runtime
  ├─ xdk.io → bytes
  ├─ xdk.fs → io, bytes
  ├─ xdk.sys → runtime, bytes
  ├─ xdk.log → runtime, text, time
  ├─ xdk.config → text, fs, sys
  ├─ xdk.cli → text, sys
  ├─ core.tasks/sync → errors, runtime
  ├─ net.uri → text, errors
  ├─ net → uri, bytes, io, tasks, time
  ├─ net.tls → net, xdk.crypto, time
  ├─ net.http → net, net.uri, net.tls（不依赖 codec；JSON 由应用组合）
  ├─ net.websocket → net.http, net.tls
  ├─ net.mime → text
  └─ utils.* → core (+ net where needed)
```

### 10.2 禁止依赖

- core → net/utils。
- net → utils（除 codec/crypto/compress 的显式注入；不能反向依赖应用工具）。
- utils → 应用。
- 任何环。

### 10.3 风险点

| 风险 | 说明 | 处理 |
| --- | --- | --- |
| `net.http` 依赖 codec | JSON 不是 HTTP 核心 | HTTP 只处理 bytes/stream；JSON 由应用组合 `xdk.codec` |
| `net.tls` 依赖 crypto | 正常分层 | crypto 只提供算法，不依赖 net |
| `utils` 反向依赖 | 工具包容易变大 | 明确依赖方向；不把 utils 作为万能层 |
| 执行层跨层 | tasks/sync 被所有层使用 | 作为 L4 内建；不依赖具体包 |

---

## 11. 场景覆盖分析

### 11.1 覆盖矩阵

| 场景 | L1 | L2 | L3 | L4 | L5 | L6 | L7 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S1 API 服务 | errors/runtime/meta | text/collections/time | io/fs/log/config/cli | tasks/sync | net.uri/net/tls | http | codec/validate/cache/metrics/trace/runtime |
| S2 监控 Agent | errors/runtime | bytes/collections/math/time | fs/sys/log/config | tasks/sync | net | — | compress/stats/runtime |
| S3 中间件 | errors | bytes/text/collections | io/fs/log/config | tasks/sync | net | — | codec/queue/cache/compress |
| S4 CLI 工具 | errors | text/collections/math | io/fs/log/config/cli | — | — | — | codec/text/stats/terminal |
| S5 协议网关 | errors/runtime | bytes/text/collections/math | io/fs/log | tasks/sync | net | — | crypto/compress |
| S6 WS 推送 | errors | text/collections/time | log/config | tasks/sync | net/http/tls | websocket | metrics/trace/runtime |
| S7 文件传输 | errors | bytes/text | io/fs/log/config | tasks/sync | net/tls | http | compress/crypto |
| S8 mTLS | errors | time | log/config | tasks/sync | net/tls | http | crypto/audit |

### 11.2 结论

- 八类场景都能在 API 面上闭环。
- 网络层不再是“黑盒外部”，而是 L5/L6 的明确能力层。
- 工具组是“可运维”的关键：没有 metrics/trace/runtime/cache/queue，服务端只能算 Demo。

---

## 12. 业界对齐分析

### 12.1 核心

| 能力 | 业界基线 | XDK API 面 对应 | 对齐程度 |
| --- | --- | --- | --- |
| 错误 | Go errors/Rust Result | errors + ResultOps | 高 |
| 字节 | Go bytes/Java ByteBuffer | bytes + ByteBuffer/BitSet | 高 |
| 文本 | Go strings/Java String | text + StringBuilder/Regex/Unicode | 高 |
| 容器 | Java Collections | collections + 算法族 | 高 |
| 数学 | Go math/Java Math | math + Decimal/Int128/Stats | 中高 |
| 时间 | Go time/Java java.time | time + Instant/Zone/Formatter | 中高 |
| IO | Go io/bufio | io + Buffered/Line/Chain | 高 |
| FS | Java NIO/Python pathlib | fs + Path/File/Metadata/Temp | 高 |
| 进程 | Go os/exec | sys + ProcessBuilder/SystemInfo | 高 |
| 日志 | slog/Logback | log + Field/Sink/Filter | 高 |
| 配置 | Viper/Spring | config + Source/Schema | 中高 |
| CLI | Cobra/picocli | cli + Command/Parser/Help | 中高 |
| 并发 | Go context/Java Executor | tasks/sync + Executor/Select | 中高 |

### 12.2 网络

| 能力 | 业界基线 | XDK API 面 对应 | 对齐程度 |
| --- | --- | --- | --- |
| URI | Go net/url | net.uri + Query/Builder | 高 |
| Socket | Go net/Java NIO | net + TCP/UDP/ByteStream | 高 |
| DNS | Go net.Resolver | net + DnsResolver/Cache | 中高 |
| TLS | Go crypto/tls | net.tls + mTLS/ALPN | 中高 |
| HTTP | Go net/http/Netty | net.http + H1/H2/Client/Server/Proxy | 高 |
| WebSocket | gorilla/ws/Node ws | net.websocket + heartbeat/backpressure | 高 |
| MIME | Go mime | net.mime | 中 |

### 12.3 工具

| 能力 | 业界基线 | XDK API 面 对应 | 对齐程度 |
| --- | --- | --- | --- |
| JSON/CSV | encoding/json/Jackson | xdk.codec | 高 |
| Crypto | Go crypto/JCA | xdk.crypto | 中高 |
| Compress | Go compress/zip | xdk.compress | 中高 |
| Random/UUID | math/rand/uuid | xdk.random/uuid | 高 |
| Regex | Go regexp/PCRE | xdk.text | 中高 |
| Stats | Python statistics | xdk.stats | 中高 |
| Validate | Jakarta/pydantic | xdk.validate | 中高 |
| Cache | Guava/Caffeine | xdk.cache | 高 |
| Queue | BlockingQueue/Channels | xdk.queue | 中高 |
| Schedule | Quartz/cron | xdk.schedule | 中高 |
| Metrics/Trace/Health | Micrometer/OTel/Actuator | xdk.metrics/trace/runtime | 中 |
| Terminal/i18n/Test | ANSI/ICU/JUnit | xdk.terminal/i18n/test | 中 |

---

## 13. 缺口与优先级

### 13.1 P0：没有就写不了真实程序

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `io` 组合器/Stdio | 所有 I/O 程序 | 先落 Buffered/Line/Chain/Tee/Limit/Stdio |
| `fs` File/Dir/Metadata/Temp/Atomic | 所有文件程序 | 先落 Path/File/Dir/Metadata/Atomic |
| `net` TCP/UDP/ByteStream | 所有网络程序 | 先落 TcpListener/TcpStream/UdpSocket/ByteStream |
| `net.http` Client/Server/Body/Headers | 所有 API 程序 | 先落 HTTP/1.1 + 流式 body |
| `xdk.codec` JSON | 所有 API/配置/数据程序 | 先落 JSON + Base64/Hex |
| `xdk.cache/queue` | 服务端/中间件 | 先落 LRU/TTL/有界队列 |
| `log` Field/Sink/Filter | 生产可观测 | 先落结构化日志 |
| `config` Source/Schema | 可部署程序 | 先落 File/Env/Overlay |

### 13.2 P1：生产可用

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| TLS mTLS/证书链 | 安全服务 | 先落证书/信任库/客户端认证 |
| WebSocket 心跳/背压 | 推送服务 | 先落 options/stats/trySend |
| HTTP 代理/CONNECT | 中间件 | 先落 HttpTunnel/ProxyServer |
| `xdk.crypto` | 安全 | 先落 SHA/HMAC/AES-GCM/KDF |
| `xdk.compress` | 传输/存储 | 先落 gzip/zlib |
| `xdk.metrics/trace/runtime` | 可运维 | 先落 Counter/Gauge/Histogram/Registry |
| `xdk.schedule` | 监控/批处理 | 先落 cron/periodic |
| `xdk.validate` | API 输入 | 先落 Rules/Schema |

### 13.3 P2：生态级

- HTTP/2 细节、HTTP/3/QUIC、WebSocket over HTTP/2。
- 持久化容器、并发容器、无锁结构。
- ICU 级 i18n、完整时区库。
- 分布式追踪导出器、Prometheus exporter。
- PTY/进程组/cgroup/容器信息。
- 内存映射/零拷贝/IO uring。

---

## 14. 成熟度评估

### 14.1 按层

| 层 | 设计成熟度 | 说明 |
| --- | --- | --- |
| L1 基础 | C2–C3 | errors 最强；runtime/meta 刻意小 |
| L2 数据 | C3 | 方法面大幅补齐；性能/Unicode/迭代器是后续 |
| L3 IO/系统 | C2–C3 | io/fs 强；sys/config/cli 中高 |
| L4 执行 | C2–C3 | 类型齐；并发语义需实现验证 |
| L5 网络传输 | C2–C3 | TCP/UDP/TLS 完整；QUIC 不做 |
| L6 网络协议 | C3 | HTTP/WS 方法面强；框架不做 |
| L7 工具 | C2–C3 | 覆盖广；深度按包不同 |

### 14.2 按组

| 组 | 设计成熟度 | 主要风险 |
| --- | --- | --- |
| `xdk.core` | C3 | 容器/IO/FS 方法面大，API 冻结成本高 |
| `xdk.net` | C3 | 协议/安全复杂，测试/互操作成本高 |
| `xdk.utils` | C2–C3 | 包多，容易变成“什么都有一点” |

### 14.3 设计 vs 实现

本文的 C 级是**设计覆盖**，不是实现验证。真实状态必须是：

```text
设计覆盖 C3
  ≠ 实现完成
  ≠ 场景通过
  ≠ 性能达标
  ≠ 安全审计通过
```

后续必须补：

- API 清单签字；
- 场景/回归；
- 互操作测试（HTTP/TLS/WS）；
- 性能/内存/并发压力；
- 安全审计（TLS/crypto/validate）。

---

## 15. 风险分析

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| API 面过大 | 方法多但没人用 | 每个方法必须有场景；K/X 分层；不做空承诺 |
| 与业界“形似神不似” | 名字像但语义不同 | 对照业界契约写清失败/所有权/取消 |
| 网络层过度设计 | HTTP/2/代理/WS 太重 | K/X 分层；先 H1/WS/TCP/UDP |
| 工具组变成垃圾场 | utils 什么都放 | 子包单一职责；禁止跨域依赖 |
| 安全默认不安全 | TLS 校验/密钥/日志 | 默认安全；显式降级；审计 |
| 并发语义不清 | 取消/关闭/死锁 | 状态机 + 场景 + 压力测试 |
| 兼容性 | 方法多，冻结难 | stable/preview 标签；废弃周期 |

---

## 16. 结论

### 16.1 XDK API 面能做什么

- **后台服务**：HTTP/1.1/2、WebSocket、TLS/mTLS、配置、日志、指标、追踪、健康、缓存、队列、JSON、校验。
- **监控程序**：进程/环境/系统信息、文件/目录/元数据、时间、统计、压缩、TCP/UDP 上报、调度。
- **中间件/代理**：TCP 隧道、HTTP 反向代理、CONNECT、连接池、队列、背压、重试、死信。
- **CLI/数据工具**：参数/子命令/帮助、文件/流、CSV/JSON、正则、排序/分组/统计、终端输出。
- **协议网关**：字节/端序/位、TCP/UDP、校验和、压缩、加密、并发连接。
- **推送服务**：WebSocket 心跳/背压/重连/统计、HTTP upgrade、指标/追踪。
- **文件传输**：Multipart、流式上传/下载、临时文件、原子落盘、压缩/加密/校验和。
- **安全服务**：TLS/mTLS、证书链/信任库、审计、脱敏、常量时间比较。

### 16.2 仍然不是

- 不是 Web 框架（路由/中间件只是 X）。
- 不是消息队列/数据库驱动/协议栈。
- 不是 GPU/张量/训练框架。
- 不是硬实时/内核/裸机。
- 不是“方法多就完成”；实现、场景、性能、安全仍是后续。

### 16.3 一句话

> API 面把 XDK 从“包清单 + 少量函数”提升为“分层能力面”：core 能写程序，net 能写服务，utils 能上生产；方法面接近业界标准库，但实现与验证仍未完成。
