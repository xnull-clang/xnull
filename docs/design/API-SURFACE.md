# XDK API 面总览（旧版广度稿）

> **2.x 状态**：本文件是旧版 API 广度稿，不是实现依据。包名以 [`PACKAGE-MAP.md`](PACKAGE-MAP.md) 为准；类型签名以逐类型合同为准；已知冲突见 [`DESIGN-CONSISTENCY.md`](DESIGN-CONSISTENCY.md)。`xdk.utils.*` 是旧写法，2.x 包名是 `xdk.codec`、`xdk.crypto` 等；本文件将按合同重新生成，不再手写。

> 当前领域设计见 [`README.md`](README.md)；本文件是 core/net/utils 的 API 广度总览（对照用），不声明当前目录/顺序。

| 项 | 值 |
| --- | --- |
| 文档性质 | XDK API 面；只写方案与 API，不写代码 |
| 范围 | `xdk.core`、`xdk.net`、`xdk.utils` 三组；注解系统作为跨切面契约层 |
| 不讨论 | 编译器/FFI/运行时实现细节、测试脚本；注解只讨论能力面与对接，不展开处理器实现 |
| 目标 | 把 XDK 从“能跑的骨架”提升到“对齐业界 API 面、能支撑真实程序”的标准库 |
| 状态 | 设计对照；覆盖 core/net/utils 的 API 广度，场景与实现仍需后续对齐 |

---

## 0. 为什么需要 API 面

旧版设计的问题不是“缺几个函数”，而是三类系统性不足：

1. **方法面太薄**：很多类只有 3–8 个方法，连 Demo 级程序都要自己补循环/工具函数。
2. **能力分层太低**：只覆盖“最小可用”，没有覆盖业界标准库的常规能力，例如：
   - 集合缺少 `map/filter/reduce/groupBy/partition/range/iterator`；
   - IO 缺少 `Buffered/Line/Chain/Tee/Limit/Counting/Stdio`；
   - FS 缺少 `Metadata/OpenOptions/Temp/Walk/Glob/Atomic/Permissions`；
   - 网络缺少 `Cookie/Form/Multipart/Proxy/HTTP2/连接池/DNS 缓存`；
   - 工具组没有 `codec/crypto/compress/random/uuid/regex/stats/validate/cache/queue`。
3. **没有场景闭环**：API 是“按包列函数”，不是“按程序验证能力”。

API 面的验收标准：

- 三类程序可以直接用 XDK 写出来：**后台服务、监控程序、中间件/代理**。
- 核心类的方法面接近 Go/Java/Python/.NET 的同级标准库。
- 每个包有明确的层级、依赖、K/X 边界和场景。
- 最后给出分层能力详细分析，而不是“包清单”。

---

## 1. 三组划分

### 1.1 `xdk.core`

语言和系统的基础能力：

```text
xdk.errors     错误分类/构造/报告/聚合/重试
xdk.runtime    诊断/退出/时钟/运行时信息
xdk.meta       版本/目标平台/构建信息
xdk.bytes      字节序列/缓冲/读写/端序/位
xdk.text       文本/格式化/解析/Unicode/正则
xdk.collections 列表/映射/集合/算法/专用容器
xdk.math       数学/整数/Decimal/统计/Int128
xdk.time       时长/时间点/日期/时区/格式化
xdk.io         流/缓冲/行/组合/Stdio
xdk.fs         路径/文件/目录/元数据/临时/原子/遍历
xdk.sys        进程/环境/平台/信号/资源
xdk.log        分级日志/字段/Sink/过滤/格式化
xdk.config     配置快照/来源/覆盖/类型化/校验
xdk.cli        参数/选项/命令/帮助/补全
xdk.execution  任务/任务组/上下文/执行器/定时器/同步原语
```

### 1.2 `xdk.net`

网络传输与协议：

```text
xdk.net.uri        URI/URL/Query/百分号编码
xdk.net            IP/前缀/Socket 地址/DNS/ByteStream/TCP/UDP
xdk.net.tls        证书/私钥/信任库/TLS 流/mTLS
xdk.net.http       HTTP/1.1 client/server 子集（M5.3a/M5.3b）；HTTP/2、代理/Multipart planned
xdk.net.websocket  WebSocket 客户端/服务端/消息/心跳/重连
xdk.net.mime       MediaType/扩展名
```

> `xdk.jwt`、`xdk.sql` 同属 network 领域，但不在本文件的 net API 广度内；见 [`network/jwt/README.md`](network/jwt/README.md)、[`network/sql/README.md`](network/sql/README.md)。

### 1.3 `xdk.utils`

**不是单一的 `util` 大杂烩**，而是“可复用工具包组”。每个子包单一职责。

> 旧版口径的 `regex`/`health`/`resource` 已分别归 `xdk.text`/`xdk.runtime`/`xdk.sys`；当前 utils 为 24 包，完整索引见 [`utils/OVERVIEW.md`](utils/OVERVIEW.md)。

```text
codec/crypto/compress/random/uuid/stats/
functional/resilience/validate/cache/queue/schedule/
metrics/trace/audit/terminal/i18n/test/
event/reflect/graph/yaml/toml/xml
```

> 如果团队坚持 S7 的 `xdk.codec`/`xdk.crypto` 命名，可以把 `xdk.utils.*` 视为分组别名；但本设计按“三组”组织。

---

## 2. 分层模型

```text
L8 应用
  ▲
L7 工具组 xdk.utils
  ▲
L6 网络协议 xdk.net.http / websocket / mime
  ▲
L5 网络传输 xdk.net.uri / net / tls
  ▲
L4 执行层 tasks / sync
  ▲
L3 IO 与系统 io / fs / sys / log / config / cli
  ▲
L2 数据与计算 bytes / text / collections / math / time
  ▲
L1 基础 errors / runtime / meta
  ▲
L0 语言原语（不属于 XDK）
```

规则：

- 上层可以依赖下层；下层不得依赖上层。
- `xdk.net` 不进入 `xdk.core`；核心层保持“无网络”。
- `xdk.utils` 可以依赖 `core` 和 `net`，但不得反向依赖应用。
- 执行层统一为 `xdk.execution`；`xdk.tasks`/`xdk.sync` 只作 1.x 兼容命名空间。
- 同层内允许有向依赖，但不得成环。

---

## 3. 包地图

| 组 | 包 | 层 | 职责 | 关键类型 |
| --- | --- | --- | --- | --- |
| core | `errors` | L1 | 错误分类/构造/报告/聚合/重试 | `ErrorKind`、`Error`、`BasicError`、`ErrorGroup`、`RetryPolicy` |
| core | `runtime` | L1 | 诊断/退出/时钟/运行时信息 | `RuntimeInfo`、`MemoryStats`、`TaskStats` |
| core | `meta` | L1 | 版本/目标平台/构建信息 | `BuildInfo`、`TargetInfo`、`Capability` |
| core | `bytes` | L2 | 字节/缓冲/读写/端序/位 | `Bytes`、`BytesBuilder`、`ByteBuffer`、`BitSet` |
| core | `text` | L2 | 文本/格式化/解析/Unicode/正则 | `StringBuilder`、`Format`、`Regex`、`Unicode` |
| core | `collections` | L2 | 容器/算法/专用容器 | `List`、`Map`、`Set`、`Deque`、`LRUCache` |
| core | `math` | L2 | 数学/整数/Decimal/统计 | `Decimal`、`Int128`、统计函数 |
| core | `time` | L2 | 时长/时间点/日期/时区 | `Duration`、`Instant`、`DateTime`、`TimeZone` |
| core | `io` | L3 | 流/缓冲/行/组合/Stdio | `Reader`、`Writer`、`BufferedReader`、`LineReader` |
| core | `fs` | L3 | 路径/文件/目录/元数据/临时/原子 | `Path`、`File`、`Dir`、`Metadata`、`FileSystem` |
| core | `sys` | L3 | 进程/环境/平台/信号/资源 | `ProcessBuilder`、`Process`、`Env`、`Signal` |
| core | `log` | L3 | 日志/字段/Sink/过滤/格式化 | `Logger`、`LogRecord`、`Sink`、`Formatter` |
| core | `config` | L3 | 配置/来源/覆盖/类型化/校验 | `Config`、`ConfigSource`、`ConfigSchema` |
| core | `cli` | L3 | 参数/选项/命令/帮助/补全 | `Args`、`OptionSpec`、`Command`、`Parser` |
| core | `execution` | L4 | 任务/上下文/锁/通道/原子/同步器 | `Context`、`Task`、`TaskGroup`、`Executor`、`Mutex`、`Channel` |
| net | `net.uri` | L5 | URI/URL/Query | `Uri`、`UriBuilder`、`Query` |
| net | `net` | L5 | IP/DNS/TCP/UDP | `IpAddress`、`DnsResolver`、`TcpStream`、`UdpSocket` |
| net | `net.tls` | L5 | TLS/mTLS/证书 | `TlsConfig`、`TlsStream`、`Certificate` |
| net | `net.http` | L6 | HTTP/1.1、HTTP/2、代理 | `HttpClient`、`HttpServer`、`HttpRequest`、`CookieJar` |
| net | `net.websocket` | L6 | WebSocket | `WebSocket`、`WebSocketClient`、`WebSocketMessage` |
| net | `net.mime` | L6 | MediaType | `MediaType`、`MimeTypes` |
| utils | `xdk.codec` | L7 | JSON/CSV/Base64/Hex/URL | `Json`、`Csv`、`Base64`、`Hex` |
| utils | `xdk.crypto` | L7 | 哈希/HMAC/AES/KDF | `Hash`、`Hmac`、`Aes`、`Kdf` |
| utils | `xdk.compress` | L7 | gzip/zlib/zip | `Gzip`、`Zlib`、`ZipArchive` |
| utils | `xdk.random` | L7 | PRNG/SecureRandom | `Random`、`SecureRandom` |
| utils | `xdk.uuid` | L7 | UUID/ULID | `Uuid`、`Ulid` |
| utils | `xdk.functional` | L7 | 序列/惰性/函数组合 | `Seq`、`Sequences`、`Lazy` |
| utils | `xdk.stats` | L7 | 统计/直方图/回归 | `Stats`、`BucketHistogram`、`Regression` |
| utils | `xdk.resilience` | L7 | 熔断/限流/重试/降级 | `CircuitBreaker`、`RateLimiter`、`Retry`、`Fallback` |
| utils | `xdk.validate` | L7 | 校验/模式 | `Validator`、`Schema`、`ValidationError` |
| utils | `xdk.cache` | L7 | LRU/TTL/Loading | `LruCache`、`TtlCache`、`LoadingCache` |
| utils | `xdk.queue` | L7 | 有界/批处理队列 | `BoundedQueue`、`BatchQueue` |
| utils | `xdk.schedule` | L7 | cron/周期任务 | `Scheduler`、`CronExpression`、`Job` |
| utils | `xdk.metrics` | L7 | 指标 | `Counter`、`Gauge`、`Histogram`、`Registry` |
| utils | `xdk.trace` | L7 | 追踪 | `Tracer`、`Span`、`SpanContext` |
| utils | `xdk.audit` | L7 | 审计/脱敏 | `AuditEvent`、`AuditSink`、`Redactor` |
| utils | `xdk.terminal` | L7 | TTY/ANSI/进度/表格 | `Terminal`、`Ansi`、`ProgressBar`、`Table` |
| utils | `xdk.i18n` | L7 | 国际化 | `Locale`、`MessageCatalog`、`PluralRules` |
| utils | `xdk.test` | L7 | 测试 | `Test`、`Assert`、`TestRunner` |
| utils | `xdk.event` | L7 | 事件/订阅/发布 | `Event`、`EventSubscription`、`EventBus` |
| utils | `xdk.reflect` | L7 | 只读类型元数据 | `Reflect`、`TypeInfo`、`MemberInfo` |
| utils | `xdk.graph` | L7 | 图/遍历/拓扑/最短路 | `Graph`、`GraphEdge` |
| utils | `xdk.yaml` | L7 | YAML 多文档/属性源 | `Yaml`、`YamlDocument`、`YamlPropertySource` |
| utils | `xdk.toml` | L7 | TOML 解析/生成 | `Toml`、`TomlOptions` |
| utils | `xdk.xml` | L7 | XML 解析/生成 | `Xml`、`XmlElement`、`XmlOptions` |

---

## 4. 设计原则

### 4.1 失败通道

- 可恢复失败：`Result<T, Error>`；无值：`Result<Unit, Error>`。
- 合同错误：越界、非法 shift、负 count、重复 close/join 等。
- 无失败：纯读取/纯计算。

### 4.2 资源与生命周期

- 持 OS 资源：`isOpen()` + 幂等 `close()`。
- 关闭失败只报告诊断，资源视为已释放。
- 禁止隐式全局初始化/清理。

### 4.3 取消与超时

- 可阻塞方法首参 `Context`。
- 取消 → `Cancelled`；超时 → `Timeout`。
- 取消后不得产生外部可见副作用。

### 4.4 所有权

- `class` 引用语义；`struct` 值语义。
- 缓冲参数借用；返回容器明确副本/转移。
- `toBytes` 副本；`takeBytes` 转移；`keys/values/entries` 快照。

### 4.5 命名与稳定性

- 参数全名，禁止 `s/e/f/xs` 之类缩写。
- 每个公开符号标 `stable`/`preview`/`internal`。
- 跨包同名顶层函数必须消除；同一能力只定义一个名字。

### 4.6 对齐业界 API

不是“照抄某个语言”，而是对齐能力面：

| 能力 | 业界参考 |
| --- | --- |
| 错误/Result | Go `errors`、Rust `Result`、Java exceptions、.NET exceptions |
| 字节 | Go `bytes`、Java `ByteBuffer`、.NET `Span<byte>` |
| 文本 | Go `strings`、Java `String`、Python `str`、.NET `string` |
| 集合 | Java Collections、Go slices/maps、Python list/dict/set、.NET Collections |
| 时间 | Go `time`、Java `java.time`、Python `datetime`、.NET `DateTime` |
| IO | Go `io/bufio`、Java `java.io/nio`、Python `io`、.NET `Stream` |
| FS | Go `os/path/filepath`、Java `java.nio.file`、Python `pathlib`、.NET `File/Directory` |
| 进程 | Go `os/exec`、Java `ProcessBuilder`、Python `subprocess`、.NET `Process` |
| 日志 | Go `log/slog`、SLF4J/Logback、Python `logging`、.NET `ILogger` |
| 配置 | Viper、Spring Config、Python dynaconf、.NET Configuration |
| CLI | Cobra、picocli、argparse、System.CommandLine |
| 并发 | Go context/goroutine、Java Executor/Future、Python asyncio、.NET Task |
| URI/URL | Go `net/url`、Java `URI`、Python `urllib.parse`、.NET `Uri` |
| Socket | Go `net`、Java NIO、Python `socket/asyncio`、.NET `Socket` |
| TLS | Go `crypto/tls`、Java SSL、Python `ssl`、.NET `SslStream` |
| HTTP | Go `net/http`、Netty、Python `aiohttp`、Node `http`、.NET `HttpClient/Kestrel` |
| WebSocket | gorilla/websocket、Java WebSocket、Python `websockets`、Node `ws`、.NET `ClientWebSocket` |
| JSON/CSV | `encoding/json`、Jackson、Python `json/csv`、.NET `System.Text.Json` |
| 加密 | Go `crypto`、JCA、Python `hashlib/cryptography`、.NET Cryptography |
| 压缩 | Go `compress`、Java `zip`、Python `gzip/zipfile`、.NET Compression |
| 随机/UUID | Go `math/rand`、Java `Random/UUID`、Python `random/uuid`、.NET `Random/Guid` |
| 正则 | Go `regexp`、Java `Pattern`、Python `re`、.NET `Regex` |
| 统计 | Python `statistics`、Apache Commons Math、.NET MathNet |
| 校验 | Jakarta Validation、FluentValidation、pydantic |
| 缓存/队列 | Guava/Caffeine、Java BlockingQueue、.NET Channels |
| 指标/追踪 | Micrometer、Prometheus、OpenTelemetry |
| 健康/审计 | Spring Actuator、.NET HealthChecks、审计日志 |

---

## 5. 成熟度模型

| 等级 | 含义 |
| --- | --- |
| C0 骨架 | 只有类型/签名，没有可用语义 |
| C1 可用 | 能覆盖最小场景，方法面很窄 |
| C2 标准 | 对齐业界常规方法面，能写真实程序 |
| C3 完整 | 覆盖边界/错误/取消/资源/并发，有场景 |
| C4 生态级 | 有扩展点/插件/可观测/性能承诺 |

API 面目标：

- `xdk.core`：C3；
- `xdk.net`：C3（HTTP/1.1、WebSocket、TCP/UDP、TLS 基础）；
- `xdk.utils`：C2–C3（按包）；
- 不允许再把 C1 包装成“完成”。

---

## 6. 非目标

- 不做 Web 框架、RPC 框架、模板引擎。
- 不做数据库驱动、消息队列协议栈（MQTT/AMQP 等）。
- 不做 GPU/张量/训练框架。
- 不做 UI/图形/图像。
- 不做硬实时、内核、裸机。
- 不提供全局可变状态、隐式初始化、线程局部隐式状态。

---

## 7. 注解面（Annotation Surface）

公共 API 文档必须把注解当作 API 合同的一部分。完整规范见 [`solution-03-annotation.md`](../solution-03-annotation.md) §8；本节只规定 XDK API 面模板。

### 7.1 强制模板

每个公共类型/成员必须给出：

| 项 | 内容 |
| --- | --- |
| 类型/成员 | 规范名/签名 |
| 可用注解 | 注解名；没有就写“无” |
| 目标/保留 | 精确 `@Target` / `@Retention` |
| 所属包/处理器 | owner 包 + 构建期处理器 |
| 生成物 | 生成的成员/类型/文件/目录 |
| 诊断码 | 稳定码 + 严重度 |
| 状态 | `implemented` / `reserved` / `planned` / `open` |
| 反例 | 至少一个禁用位置/失败模式 |

### 7.2 状态口径

- `implemented`：注解 + 处理器/生成 + 测试都存在；仅表示注解能力，不表示整个包已实现。
- `reserved`：识别但不承诺语义。
- `planned`：合同已写，处理器/生成未实现；不得用现在时描述行为。
- `open`：决策/签字缺失；不得写成冻结。

### 7.3 已实现与计划中的示例

已实现（A8，编译器）：

```markdown
| 可用注解 | `@Value` |
| 目标/保留 | `Type` / `Source` |
| 所属包/处理器 | 编译器 A8 |
| 生成物 | `equals`、`toString`、`copy`；不生成 `hash()` |
| 诊断码 | `AN0021`–`AN0023` |
| 状态 | implemented（含限制） |
```

计划中（领域包）：

```markdown
| 可用注解 | `@HttpRoute`、`@Header`、`@Query`、`@Body` |
| 目标/保留 | `Method`/`Parameter` / `Source` |
| 所属包/处理器 | `xdk.net.http` / `http_processor` |
| 生成物 | `generated/HttpGenerated.x`: Router/dispatch/参数绑定 |
| 诊断码 | `AN1301`–`AN1307` |
| 状态 | implemented (M5.2)；`@StatusCode` planned |
```

### 7.5 已实现领域注解面（M2–M6）

| 包 | 可用注解 | 目标/保留 | 处理器 | 生成物 | 诊断码 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| `xdk.cli` | `@CliCommand`、`@CliSubcommand`、`@Option`、`@Arg` | Type/Field / Source | `cli_processor` | `generated/CliGenerated.x` | `AN1001`–`AN1006` | implemented (M2) |
| `xdk.codec` | `@Serializable`、`@JsonName`、`@CsvName` | Type/Field / Source | `codec_processor`、`csv_processor` | `generated/CodecGenerated.x`、`CsvGenerated.x` | `AN1101`–`AN1102`、`AN1601`–`AN1605` | implemented (M3.2/M3.3) |
| `xdk.validate` | `@Validate`、`@Min`、`@Max`、`@Pattern` | Type/Field / Source | `validate_processor` | `generated/ValidateGenerated.x` | `AN1201`–`AN1206` | implemented (M4.2) |
| `xdk.net.http` | `@HttpRoute`、`@Header`、`@Query`、`@Body` | Method/Parameter / Source | `http_processor` | `generated/HttpGenerated.x` | `AN1301`–`AN1307` | implemented (M5.2) |
| `xdk.sql` | `@Sql`、`@Param`、`@Row`、`@Column` | Method/Parameter/Type/Field / Source | `sql_processor` | `generated/SqlGenerated.x` | `AN1401`–`AN1410` | implemented (M6.2) |

### 7.4 评审规则

- 没有“注解面”的公共 API 文档视为不完整；“无注解”也必须显式。
- `planned` 注解不得写成已生效；不得把编译器 A8 的 `implemented` 扩大到领域包。
- 删除/收紧注解、目标、保留、默认值或生成物属于破坏性变更。
- 生成物必须有稳定路径/命名规则；诊断必须是稳定码。

---

## 8. 文档索引

| 文档 | 内容 |
| --- | --- |
| [`core/API-SURFACE.md`](core/API-SURFACE.md) | `xdk.core` 包/类/方法面 |
| [`network/API-SURFACE.md`](network/API-SURFACE.md) | `xdk.net` 包/类/方法面 |
| [`utils/API-SURFACE.md`](utils/API-SURFACE.md) | `xdk.utils` 包/类/方法面 |
| [`SCENARIOS.md`](SCENARIOS.md) | 服务/监控/中间件/CLI/协议/推送等场景 |
| [`CAPABILITY.md`](CAPABILITY.md) | 分层能力详细分析、覆盖矩阵、缺口/优先级 |

> **注解系统**：完整方案见 [`solution-03-annotation.md`](../solution-03-annotation.md)；`xdk.annotations` 元模型、处理器合同与 XDK 对接矩阵见
> [`ANNOTATION-SYSTEM.md`](ANNOTATION-SYSTEM.md) 与 [`ANNOTATION-CATALOG.md`](ANNOTATION-CATALOG.md)。注解是**编译期契约 + 生成入口**，运行时只读编译器生成的静态元数据，不做反射/类路径扫描/动态代理；core/net/utils 的注解对接分别见各层设计。

> 客户端/服务器核心能力画像与资源上限见
> [`core/CORE-PROFILES.md`](core/CORE-PROFILES.md)。本文的 core/net/utils 分组是该画像的上一级视角。
>
> 平台/硬件层单独设计：见 [`platform/os/README.md`](platform/os/README.md)。`xdk.os` 不进入 core/net/utils。
>
> 工具/集成层设计见 [`utils/OVERVIEW.md`](utils/OVERVIEW.md)。
>
> 解决方案层（embedded/accel/db/ml/agent/net.service/api/numerics/mcp）见 [`solutions/README.md`](solutions/README.md)。
