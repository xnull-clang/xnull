# XNull 2.x 包地图

| 项 | 值 |
| --- | --- |
| 状态 | Draft；与 [`ARCHITECTURE.md`](ARCHITECTURE.md) 配套，P0 签字后冻结 |
| 计数 | **75 包 / 698 类型** |
| 1.x 基线 | `docs/design/t0` + `src/xdk`；14 个公开包 / 160 symbols |
| 已移除 | UI/desktop（`platform/os/desktop` 15 个文件） |
| 文档目录 | `core/`、`utils/`、`solutions/` 只是文档分组，不是包名前缀 |
| 状态词 | `1.x`：已实现/部分实现；`2.x`：设计完成、待实现 |

---

## 1. 怎么读这张表

### 1.1 角色记号

| 记号 | 角色 | 含义 |
| --- | --- | --- |
| `V` | Value | 不可变值/快照 |
| `P` | Protocol | 可替换行为合同 |
| `S` | Service | 有生命周期的服务/门面 |
| `H` | Handle | 资源句柄，`close()` 幂等 |
| `B` | Builder | 配置/选项构造 |
| `R` | Registry | 查找/注册表 |
| `X` | Processor | 编译期处理器/上下文 |
| `E` | Enum | 封闭分类 |
| `Er` | Error | 错误/诊断值 |

### 1.2 计数口径

- 只统计公开类型文件，不含 README/PLAN/OVERVIEW/API-SURFACE。
- `xdk.net.service` 归 L5 网络层，因此 L5 是 9 包/125 类型，L8 是 9 包/122 类型。
- `xdk.reflect` 保留为 L4 只读类型元数据包，不并入 `xdk.meta`；两者职责不同。
- `xdk.runtime` 的 8 个公开类型不含内部原语 `RuntimeMonitor`；它由 P2 作为运行时原语补齐。

---

## 2. 层汇总

| 层 | 包 | 类型 | 说明 |
| --- | ---: | ---: | --- |
| L0 annotations | 1 | 14 | 编译器/元模型/处理器合同 |
| L1 runtime/execution | 2 | 25 | 运行时信息、任务、同步、取消 |
| L2 core foundation | 7 | 80 | errors/meta/bytes/text/collections/math/time |
| L3 core system | 6 | 81 | io/fs/sys/log/config/cli |
| L4 data/encoding | 12 | 76 | codec/crypto/compress/random/uuid/stats/functional/graph/reflect/toml/yaml/xml |
| L5 network/data | 9 | 125 | net/uri/mime/tls/http/websocket/net.service/jwt/sql |
| L6 platform/compute | 17 | 93 | os.* + gpu/tensor/linalg/geo/serial/device |
| L7 application services | 12 | 82 | validate/cache/queue/schedule/event/resilience/metrics/trace/audit/terminal/i18n/test |
| L8 solutions | 9 | 122 | api/db/ml/agent/numerics/jsonrpc/mcp/accel/embedded |
| **合计** | **75** | **698** | |

---

## 3. L0 Language / Compiler

| 包 | 类型 | 公共结构（角色） | 依赖 | 阶段 | 状态 |
| --- | ---: | --- | --- | --- | --- |
| `xdk.annotations` | 14 | `AnnotationValue/Info/Set`（V）；`AnnotationProcessor`（P）；`AnnotationProcessorContext/AnnotationProcessingResult`（X）；`AnnotationRegistry`（R）；`AnnotationElement`（V）；`AnnotationDiagnostic`（Er）；`AnnotationTarget/Retention/ValueKind/DiagnosticSeverity/ProcessorPhase`（E） | 语言核心标量/容器 | P1 | 2.x 设计；编译器 0 |

---

## 4. L1 Runtime / Execution

| 包 | 类型 | 公共结构（角色） | 依赖 | 阶段 | 状态 |
| --- | ---: | --- | --- | --- | --- |
| `xdk.runtime` | 8 | `RuntimeInfo/MemoryStats/TaskStats/TaskSnapshot`（V）；`HealthState/HealthReport`（V）；`HealthCheck`（P）；`HealthRegistry`（R）；内部原语 `RuntimeMonitor`（P2，不计入 8） | FFI/runtime | P2 | 1.x 部分；2.x 设计 |
| `xdk.execution` | 17 | `Context`（V/S）；`TaskHandle`（P）；`TaskGroup/Mutex/Channel/Executor/Semaphore/RwLock/WaitGroup/Once/Pool`（S/H）；`Task/Future/Promise`（H）；`AtomicInt/AtomicBool/AtomicRef`（V） | errors/runtime | P2/P3 | 1.x `tasks`/`sync` 内建部分；2.x 合并 |

---

## 5. L2 Core Foundation

| 包 | 类型 | 公共结构（角色） | 依赖 | 阶段 | 状态 |
| --- | ---: | --- | --- | --- | --- |
| `xdk.errors` | 16 | `ErrorKind`（E）；`Error/DetailedError`（P）；`BasicError/ErrorDetail/ErrorReport/ErrorGroup`（V/Er）；`RetryPolicy/RetryState/ErrorMatcher/ErrorCollector/ErrorCode`（V）；`ErrorSink`（P）；`DiagnosticErrorSink/MemoryErrorSink`（S）；`ErrorCodeRegistry`（R） | 无 | P3 | 1.x 核心 Verified |
| `xdk.meta` | 11 | `Capability/CapabilitySet/CoreProfile/ProfileBuilder/BuildInfo/TargetInfo/ResourceLimits/DependencyInfo`（V/B）；`RuntimeRole/IoModel/ShutdownPolicy`（E） | 构建期/FFI | P3 | 1.x 部分 |
| `xdk.bytes` | 7 | `Bytes/BytesBuilder/BitSet`（V）；`ByteBuffer/ByteReader/ByteWriter`（H）；`ByteOrder`（E） | errors | P3 | 1.x 部分 |
| `xdk.text` | 11 | `Format/Regex/Match/Utf16/Unicode/Escape/TextAlign/Normalization/RegexOptions`（V）；`StringBuilder/Joiner`（B） | errors/bytes | P3 | 1.x 部分 |
| `xdk.collections` | 17 | `List/Map/Set`（语言容器）；`Deque/Stack/Queue/PriorityQueue/RingBuffer/OrderedMap/BTreeMap/MultiMap/BiMap/LRUCache/Pair/Triple/IntRange`（V）；`Iterator`（P） | errors | P3 | 1.x Verified |
| `xdk.math` | 4 | `Int128/Decimal/Complex`（V）；`RoundingMode`（E）；标量函数 | errors/text | P3 | 1.x 部分 |
| `xdk.time` | 14 | `Duration/Instant/DateTime/Date/Time/TimeZone`（V）；`Clock/Timer`（S）；`DateTimeFormatter/DateTimeParser`（P）；`Month/Weekday/TimeUnit`（E） | errors/runtime | P3 | 1.x 部分 |

---

## 6. L3 Core System

| 包 | 类型 | 公共结构（角色） | 依赖 | 阶段 | 状态 |
| --- | ---: | --- | --- | --- | --- |
| `xdk.io` | 22 | `Reader/Writer/Seekable/Closer`（P）；`ByteArrayReader/Writer/StringReader/Writer/Buffered/Line/Chain/Tee/Limit/Counting/Peek`（H）；`Stdio`（S） | errors/bytes | P3 | 1.x Verified |
| `xdk.fs` | 12 | `Path/Metadata/DirEntry/Permissions/PathMatcher`（V）；`OpenOptions`（B）；`File/Dir/TempFile/TempDir/FileLock`（H）；`FileSystem`（P） | errors/bytes/io | P3 | 1.x Verified |
| `xdk.sys` | 8 | `Env/Platform/SystemInfo/ProcessResult`（V）；`ProcessBuilder`（B）；`Process/Resource`（H）；`Signal`（E） | errors/runtime/io | P3 | 1.x Verified |
| `xdk.log` | 10 | `Level`（E）；`Field/LogRecord/TextFormatter`（V）；`Sink/Formatter`（P）；`ConsoleSink/MemorySink/Logger/LoggerFactory`（S） | errors/runtime/text/time/io | P3 | 1.x Verified；1.x Filter/Redactor/Sampler 需回写 2.x |
| `xdk.config` | 12 | `Config/ConfigEntry/ConfigSchema/ConfigField`（V）；`ConfigSource`（P）；`MapSource/FileSource/EnvSource/OverlaySource/ProfileSource/ConfigProfileSource/ConfigLoader`（S） | errors/meta/text/fs/sys | P3 | 1.x Verified |
| `xdk.cli` | 17 | `Args/OptionSpec/Command/ParseResult/HelpFormatter/CommandResult/CommandOutput/SystemResource/SystemSnapshot`（V）；`Parser/Shell/CommandLine/CliRuntime`（S） | errors/bytes/io/sys/time/execution | P3 | 1.x Verified |

---

## 7. L4 Data / Encoding

| 包 | 类型 | 公共结构（角色） | 依赖 | 阶段 | 状态 |
| --- | ---: | --- | --- | --- | --- |
| `xdk.codec` | 13 | `JsonKind`（E）；`JsonNumber/JsonValue/JsonObject/JsonArray/JsonOptions/CsvOptions`（V）；`Json/Csv/CsvReader/CsvWriter/Base64/Hex`（S） | errors/bytes/text/io/collections | P4 | 2.x 设计；JSON/Base64 先行 |
| `xdk.crypto` | 17 | `HashAlgorithm/ChecksumAlgorithm/KdfAlgorithm/CipherAlgorithm/CipherPadding/AsymmetricAlgorithm/SignatureScheme`（E）；`Hash/Hmac/Checksum/Kdf/Cipher/Asymmetric/ConstantTime`（S）；`PublicKey/PrivateKey/KeyPair`（V） | errors/bytes/text/io/random | P4 | 2.x 设计；raw 子集 |
| `xdk.compress` | 13 | `CompressionLevel`（E）；`Gzip/Zlib/Deflate/Zstd/Lz4/Brotli/Tar`（S）；`ZipEntry/ZipOptions/TarEntry`（V）；`ZipArchive/ZipWriter`（H） | errors/bytes/fs | P4 | 2.x 设计 |
| `xdk.random` | 4 | `RandomSource`（P）；`Random/SecureRandom`（S）；`WeightedChoice`（V） | errors/bytes/collections | P4 | 2.x 设计 |
| `xdk.uuid` | 3 | `Uuid/Ulid`（V）；`UuidVersion`（E） | errors/bytes/random | P4 | 2.x 设计 |
| `xdk.stats` | 7 | `HistogramBucket/BucketHistogram/Summary/RunningStats/Regression/MovingAverage/Ema`（V） | math/collections | P4 | 2.x 设计；零阻塞 |
| `xdk.functional` | 3 | `Seq/Sequences/Lazy`（V） | collections | P4 | 2.x 设计；零阻塞 |
| `xdk.graph` | 2 | `Graph/GraphEdge`（V） | errors/collections | P4 | 2.x 设计；零阻塞 |
| `xdk.reflect` | 4 | `ReflectKind`（E）；`TypeInfo/MemberInfo`（V）；`Reflect`（S） | errors/collections + 元数据原语 | P4 | 2.x 设计；只读 |
| `xdk.toml` | 2 | `Toml`（S）；`TomlOptions`（B） | codec/errors | P4 | 2.x 设计 |
| `xdk.yaml` | 5 | `Yaml`（S）；`YamlDocument/YamlOptions/YamlPropertySource`（V）；`YamlVersion`（E） | codec/config/errors | P4 | 2.x 设计 |
| `xdk.xml` | 3 | `Xml`（S）；`XmlElement/XmlOptions`（V） | codec/errors | P4 | 2.x 设计 |

---

## 8. L5 Network / Data

| 包 | 类型 | 公共结构（角色） | 依赖 | 阶段 | 状态 |
| --- | ---: | --- | --- | --- | --- |
| `xdk.net` | 28 | `IpFamily/SocketState/ShutdownMode`（E）；`IpAddress/IpPrefix/SocketAddress/DnsRecord/DnsCacheStats/SocketOptions/MulticastOptions/NetworkInterface/PoolKey/PooledConnection/ConnectionPoolOptions/ConnectionPoolStats/Datagram`（V）；`ByteStream/TcpHandler`（P）；`Dns/DnsResolver/TcpListener/TcpStream/TcpServer/TcpClient/UdpSocket/ConnectionPool`（S） | errors/bytes/execution/uri | P5 | 2.x 设计；runtime 仅 plain TCP |
| `xdk.net.uri` | 2 | `Uri/Query`（V） | errors/text/bytes | P5 | 2.x 设计；纯 XDK 可先行 |
| `xdk.net.mime` | 2 | `MediaType/MimeTypes`（V） | errors/text | P5 | 2.x 设计；纯 XDK 可先行 |
| `xdk.net.tls` | 10 | `TlsVersion`（E）；`Certificate/PrivateKey/TrustStore/TlsConfig/TlsSessionInfo`（V）；`TlsStream`（H）；`TlsHandler`（P）；`TlsServer/TlsClient`（S） | errors/bytes/execution/net/crypto | P5 | 2.x 设计；TLS FFI 0 |
| `xdk.net.http` | 40 | `HttpMethod/HttpVersion/HttpStatus`（E）；`HttpHeader/HttpHeaders/HttpBody/HttpRequest/HttpResponse/Form/Multipart/Auth/Proxy/Cookie`（V）；`HttpHandler/HttpMiddleware`（P）；`HttpServer/HttpClient/HttpExchange`（S）；`Http2Session/Http2Stream`（H） | net/uri/mime/tls/execution/codec/compress | P5 | 2.x 设计；HTTP/2 最后 |
| `xdk.net.websocket` | 12 | `WebSocketCloseCode`（E）；`WebSocketMessage/WebSocketOptions/WebSocketStats/ReconnectPolicy`（V）；`WebSocket`（H）；`WebSocketServer/WebSocketClient`（S） | net/http/execution | P5 | 2.x 设计 |
| `xdk.net.service` | 13 | `ServiceState`（E）；`ServiceOptions/ServiceStats/ReconnectPolicy/BackpressurePolicy/HeartbeatPolicy`（V）；`NetworkService/Server/Client/Connection/Session`（S/H）；`ConnectionHandler/SessionHandler`（P） | net/tls/execution | P5 | 2.x 设计；从 solutions 归位 |
| `xdk.jwt` | 6 | `JwtAlgorithm`（E）；`JwtHeader/JwtClaims/JwtToken/JwtOptions`（V）；`Jwt`（S） | errors/bytes/text/codec/crypto | P5 | 2.x 设计 |
| `xdk.sql` | 12 | `SqlDialect/SqlKind`（E）；`SqlValue/SqlColumn/SqlRow/SqlParameter/SqlStatement/SqlOptions/SqlResult`（V）；`SqlDriver`（P）；`SqlConnection/SqlTransaction`（H） | core only | P5 | 2.x 设计；驱动归生态 |

---

## 9. L6 Platform / Compute

| 包 | 类型 | 公共结构（角色） | 依赖 | 阶段 | 状态 |
| --- | ---: | --- | --- | --- | --- |
| `xdk.os` | 5 | `OsKind/OsFamily/OsCapability`（E）；`OsInfo/OsProfile`（V） | core | P6 | 2.x 设计 |
| `xdk.os.host` | 2 | `OsHost`（P）；`Os`（S） | os + domain | P6 | 2.x 设计；desktop 方法已移除 |
| `xdk.os.cpu` | 5 | `CpuTopology/CpuCore/CpuCache`（V）；`CpuCacheKind`（E）；`CpuAffinity`（H） | os | P6 | 2.x 设计 |
| `xdk.os.memory` | 3 | `PhysicalMemory/MemoryModule/NumaNode`（V） | os | P6 | 2.x 设计 |
| `xdk.os.hardware` | 7 | `HardwareInventory/BoardInfo/BiosInfo/PciDevice/UsbDevice/SensorReading`（V）；`SensorKind`（E） | os | P6 | 2.x 设计 |
| `xdk.os.storage` | 5 | `StorageInventory/StorageDevice/Partition/SmartHealth/SmartInfo`（V） | os | P6 | 2.x 设计 |
| `xdk.os.gpu` | 6 | `GpuBackend/GpuQueueKind`（E）；`GpuAdapter/GpuDevice/GpuMemoryInfo/GpuQueue`（V） | os/FFI | P6 | 2.x 设计 |
| `xdk.os.firewall` | 6 | `FirewallAction/Direction/Protocol`（E）；`FirewallRule/FirewallStatus`（V）；`FirewallController`（S） | os/net | P6 | 2.x 设计；特权 |
| `xdk.os.container` | 5 | `NamespaceKind`（E）；`Namespace/Cgroup/ContainerInfo`（V）；`ContainerHost`（S） | os/FFI | P6 | 2.x 设计；特权 |
| `xdk.os.virt` | 5 | `HypervisorKind/VirtualMachineState`（E）；`Hypervisor/VirtualMachine`（V）；`VirtualizationHost`（S） | os/FFI | P6 | 2.x 设计；特权 |
| `xdk.os.service` | 3 | `ServiceState`（E）；`ServiceInfo`（V）；`ServiceManager`（S） | os/FFI | P6 | 2.x 设计；特权 |
| `xdk.gpu` | 8 | `GpuBufferUsage/GpuProgramKind`（E）；`GpuProgram/GpuPipeline/GpuFence`（V）；`GpuBuffer/GpuCommandBuffer`（H）；`GpuCompute`（S） | os.gpu/execution | P6 | 2.x 设计 |
| `xdk.tensor` | 5 | `TensorDType`（E）；`TensorShape/Tensor/TensorView`（V）；`TensorOps`（S） | core | P6 | 2.x 设计；纯 XDK |
| `xdk.linalg` | 7 | `Vector/Matrix/LuDecomposition/QrDecomposition/Svd/EigenDecomposition`（V）；`Linalg`（S） | math/tensor | P6 | 2.x 设计；纯 XDK |
| `xdk.geo` | 6 | `GeoPoint/GeoBounds/GeoPath/GeoPolygon`（V）；`GeoProjection`（E）；`Geo`（S） | math/collections | P6 | 2.x 设计；纯 XDK |
| `xdk.serial` | 6 | `SerialParity/SerialStopBits`（E）；`SerialOptions/SerialPortInfo`（V）；`SerialPort`（H）；`Serial`（S） | core/os.hardware/FFI | P6 | 2.x 设计 |
| `xdk.device` | 9 | `DeviceBus/GpioDirection/CameraPixelFormat`（E）；`CameraFrame`（V）；`GpioPin/I2cBus/SpiBus/CameraDevice`（H）；`DeviceManager`（S） | core/os.hardware/FFI | P6 | 2.x 设计 |

---

## 10. L7 Application Services

| 包 | 类型 | 公共结构（角色） | 依赖 | 阶段 | 状态 |
| --- | ---: | --- | --- | --- | --- |
| `xdk.validate` | 8 | `Rule/Rules/Schema/FieldRule/ValidationResult/ValidationError/ValidationContext`（V）；`Validator`（P/S） | errors/text/collections | P7 | 2.x 设计 |
| `xdk.cache` | 4 | `EvictionReason`（E）；`CacheOptions`（B）；`CacheStats`（V）；`Cache`（S） | errors/execution/runtime | P7 | 2.x 设计 |
| `xdk.queue` | 5 | `DropPolicy`（E）；`QueueStats`（V）；`BoundedQueue/BatchQueue/DelayQueue`（S） | errors/execution/runtime/time | P7 | 2.x 设计 |
| `xdk.schedule` | 8 | `ScheduleKind/MisfirePolicy`（E）；`CronExpression/Schedule/SchedulerOptions`（V）；`Job`（P）；`JobHandle`（H）；`Scheduler`（S） | errors/execution/runtime/time | P7 | 2.x 设计 |
| `xdk.event` | 3 | `Event`（V）；`EventSubscription`（H）；`EventBus`（S） | errors/runtime/codec | P7 | 2.x 设计 |
| `xdk.resilience` | 7 | `CircuitState`（E）；`CircuitBreaker/RateLimiter/Bulkhead/Retry/Fallback/Timeout`（S） | errors/execution/runtime | P7 | 2.x 设计 |
| `xdk.metrics` | 11 | `MetricKind/MetricsFormat`（E）；`MetricSample/MetricFamily`（V）；`Metric/Exporter`（P）；`Counter/Gauge/Histogram/Timer/Registry`（S） | errors/execution/runtime/time/io/collections/math/stats | P7 | 2.x 设计 |
| `xdk.trace` | 9 | `SpanKind/SpanStatus`（E）；`SpanContext/SpanEvent/TraceOptions/Sampler`（V）；`Propagator`（P）；`Span`（H）；`Tracer`（S） | errors/time/runtime/math/text/collections | P7 | 2.x 设计 |
| `xdk.audit` | 5 | `AuditLevel`（E）；`AuditEvent`（V）；`AuditSink`（P）；`AuditLogger/AuditRedactor`（S） | errors/text/runtime | P7 | 2.x 设计 |
| `xdk.terminal` | 8 | `Color/Style`（V）；`Terminal/Ansi/ProgressBar/Spinner/Prompt/Table`（S） | errors/io/text/collections/execution | P7 | 2.x 设计；CLI 呈现，不是桌面 UI |
| `xdk.i18n` | 7 | `Locale/MessageCatalog/PluralRules/NumberFormat/DateFormat`（V）；`MessageFormatter/Translator`（S） | errors/text/collections/io/bytes/fs/time/math/execution | P7 | 2.x 设计 |
| `xdk.test` | 7 | `Assert/Test/TestSuite/TestResult/TestContext`（V）；`TestStatus`（E）；`TestRunner`（S） | core | P7 | 2.x 设计 |

---

## 11. L8 Solutions

| 包 | 类型 | 公共结构（角色） | 依赖 | 阶段 | 状态 |
| --- | ---: | --- | --- | --- | --- |
| `xdk.jsonrpc` | 5 | `JsonRpcId/Request/Response/Error`（V）；`Peer`（S） | codec/io/execution | P8 | 2.x 设计 |
| `xdk.mcp` | 16 | `McpTool/McpResource/McpPrompt/...`（V）；`McpTransport`（P）；`McpServer/McpClient/McpSession/McpRegistry`（S/R） | jsonrpc/http/codec/io/execution | P8 | 2.x 设计 |
| `xdk.ml` | 20 | `Model/Session/Dataset/DataLoader/Trainer/Optimizer/Loss/...`（V/S） | tensor/linalg/random/codec | P8 | 2.x 设计 |
| `xdk.numerics` | 12 | `BigInt/BigFloat/Polynomial/Integration/Optimization/OdeSolver/Fft/SignalBuffer/Interpolation/RootFinder`（V/S） | math/linalg/tensor | P8 | 2.x 设计 |
| `xdk.db` | 11 | `Db/Database/DatabasePool/Migration/MigrationRunner/RowMapper/...`（V/S） | sql/crypto | P8 | 2.x 设计 |
| `xdk.api` | 15 | `ApiOptions/ApiRoute/ProblemDetails/OpenApiDocument/OpenApiBuilder/AuthScheme/RateLimitPolicy/CorsPolicy`（V）；`ApiHandler/ApiMiddleware/Authenticator`（P）；`ApiServer/ApiRouter/ApiContext/SseStream`（S/H） | http/uri/mime/codec/validate/errors/execution | P8 | 2.x 设计 |
| `xdk.agent` | 17 | `Agent/Pipeline/Receiver/Processor/PipelineExporter/Connector/Health/...`（V/S） | metrics/trace/audit/log/os/http | P8 | 2.x 设计 |
| `xdk.accel` | 14 | `Accel/Device/Program/Kernel/CommandBuffer/Memory/Fence/...`（V/H/S） | gpu/os.gpu/tensor | P8 | 2.x 设计 |
| `xdk.embedded` | 12 | `Embedded/Board/Gpio/Pwm/Uart/Can/Watchdog/Rtc/Flash/...`（V/H/S） | device/serial/os | P8 | 2.x 设计 |

---

## 12. 旧名 → 新名

| 旧写法 | 2.x 写法 | 处理 |
| --- | --- | --- |
| `xdk.errors` | `xdk.errors` | 全量改名；`xdk.core` 只作层名 |
| `xdk.runtime` | `xdk.runtime` | 同上 |
| `xdk.execution` | `xdk.execution` | 同上；不再使用 `xdk.execution` 包名 |
| `xdk.core.<pkg>` | `xdk.<pkg>` | 同上 |
| `xdk.codec` | `xdk.codec` | 全量改名；`utils` 只作文档分组 |
| `xdk.utils.<pkg>` | `xdk.<pkg>` | 同上 |
| `xdk.codec`（简写） | `xdk.codec` | 文档中统一为全名 |
| `xdk.errors`（简写） | `xdk.errors` | 文档中统一为全名 |
| `xdk.tasks` / `xdk.sync` | `xdk.execution` | 1.x 兼容名；2.x 不新增 |
| `xdk.net.service`（solutions 计数） | `xdk.net.service`（L5 计数） | 包名不变，层级归位 |
| `xdk.stats.Histogram` | `xdk.stats.BucketHistogram` | 避免与 `xdk.metrics.Histogram` 换义 |
| `xdk.metrics.Timer` | `xdk.metrics.MetricTimer` | 避免与 `xdk.time.Timer` 换义 |
| `xdk.audit.Redactor` | `xdk.audit.AuditRedactor` | 避免与 `xdk.log.Redactor` 换义 |
| `xdk.net.service.ReconnectPolicy` | `xdk.net.service.ServiceReconnectPolicy` | 避免与 WebSocket `ReconnectPolicy` 换义 |
| `xdk.net.service.ServiceState` | `xdk.net.service.NetServiceState` | 避免与 `xdk.os.service.ServiceState` 换义 |
| `xdk.numerics.Signal` | `xdk.numerics.SignalBuffer` | 避免与 `xdk.sys.Signal` 换义 |
| `xdk.agent.Exporter` | `xdk.agent.PipelineExporter` | 避免与 `xdk.metrics.Exporter` 换义 |
| `xdk.db.Batch` / `xdk.ml.Batch` | `xdk.db.DbBatch` / `xdk.ml.MlBatch` | 同名换义 |

> 上表的类型改名在 P0 后续“命名归一”批次执行；本表先冻结目标名，避免实现时再猜。

---

## 13. 实施顺序与出口

```text
P0 架构冻结
  → P1 annotations
    → P2 execution/runtime 前置
      → P3 core
        → P4 data/encoding
          → P5 network
            → P6 platform/compute
              → P7 application services
                → P8 solutions
```

| 阶段 | 首批包 | 出口 |
| --- | --- | --- |
| P0 | 架构/包地图/一致性/legacy | 0 dangling；0 计数冲突；签名 |
| P1 | `annotations` + 编译器注解管线 | 正/负例、诊断码、生成场景绿 |
| P2 | `runtime`、`execution` | `RuntimeMonitor`/`Context`/`Timer`/`Pair`/`isFinite`/`Bytes.alloc` 就绪；1.x 回归绿 |
| P3 | `errors`…`cli` | 15 个 core 包场景 + 门禁 |
| P4 | `codec`、`random`、`uuid`、`stats`、`functional`、`graph`、`reflect` | JSON/Base64/统计/图/元数据场景绿 |
| P5 | `net.uri`、`net.mime`、`net`、`net.tls`、`net.http`、`net.websocket`、`net.service`、`jwt`、`sql` | 端到端网络场景绿 |
| P6 | `os.*`、`gpu`、`tensor`、`linalg`、`geo`、`serial`、`device` | 模型/只读/控制面分级绿 |
| P7 | `validate`、`cache`、`queue`、`schedule`、`event`、`resilience`、`metrics`、`trace`、`audit`、`terminal`、`i18n`、`test` | 依赖闭包绿 |
| P8 | `jsonrpc`、`mcp`、`numerics`、`db`、`api`、`agent`、`accel`、`embedded`、`ml` | 逐组端到端绿 |

---

## 14. 包冻结清单

每个包 README 必须包含：

1. 能力声明与明确非目标；
2. 公共角色（V/P/S/H/B/R/X/E/Er）与类型索引；
3. 依赖方向与被依赖方；
4. 失败通道、取消语义、资源生命周期；
5. 场景、门禁、稳定性标签；
6. 同名冲突与限定名；
7. 注解使用清单（若使用领域注解）。

每个类型文件必须包含 14 段合同；公开签名只使用 XNull 语法；阻塞方法首参 `Context`；资源 `close()` 幂等；不暴露裸句柄。

冻结前必须：

- `API-SURFACE.md` 按类型合同重新生成，不再手写；
- `DESIGN-CONSISTENCY.md` 的开放项清零或明确延期；
- 1.x 回归全绿（涉及 core 改动时）；
- `docs/design` 相对链接 0 broken；
- 计数与本表一致。

---

## 15. 1.x 旧档

`docs/design/t0` 的 22 篇 + `MINI-1.0.md`/`MINI-1.0-SIGNOFF.md`/`RELEASE-NOTES-1.0.0.md` 是 1.x 基线，不进入本表、不参与 2.x 实现排序。清单与使用规则见 [`LEGACY-1.0.md`](LEGACY-1.0.md)。
