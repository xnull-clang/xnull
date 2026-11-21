# XDK API 面 — 场景设计

> **2.x 状态**：本文件是场景广度稿，不是实现依据。包名/类型以 [`PACKAGE-MAP.md`](PACKAGE-MAP.md) 与逐类型合同为准；旧名对照见 [`DESIGN-CONSISTENCY.md`](DESIGN-CONSISTENCY.md)。

> 当前领域设计见 [`README.md`](README.md)；本文件用真实程序形态验证 API 面，不声明当前目录/顺序。


| 项 | 值 |
| --- | --- |
| 文档性质 | 场景方案；只写 API 使用方式与能力验证，不写代码 |
| 范围 | `xdk.core` + `xdk.net` + `xdk.utils` |
| 不讨论 | 编译器、FFI、运行时实现、测试脚本 |
| 目的 | 用真实程序形态验证 API 面是否够用，而不是只列包 |

---

## 0. 场景总览

| # | 场景 | 主要验证 |
| --- | --- | --- |
| S1 | API 后台服务 | core + HTTP + codec/validate/cache/metrics/trace/runtime |
| S2 | 监控采集 Agent | core + TCP/UDP + stats/compress/runtime |
| S3 | 消息中间件/转换管道 | core + net + codec/queue/cache/compress |
| S4 | CLI 数据处理工具 | core + codec/text.Regex/stats |
| S5 | 二进制协议网关 | bytes/io + TCP/UDP + crypto/compress |
| S6 | WebSocket 推送服务 | HTTP/WS + metrics/trace/runtime |
| S7 | 文件传输服务 | fs/io + HTTP/TLS + compress/crypto |
| S8 | mTLS 服务 | TLS + crypto/audit |

---

## 1. S1：API 后台服务

### 1.1 目标与边界

一个订单/用户 API 服务：启动配置、HTTP 路由、JSON 请求、校验、缓存、指标、追踪、健康检查、优雅停机。  
不设计 Web 框架；路由/中间件是应用层组合。

### 1.2 主流程

| 阶段 | 动作 | API |
| --- | --- | --- |
| 启动 | 参数/配置 | `cli.Parser`、`config.Config`、`FileSource`、`EnvSource` |
| 启动 | 日志/追踪/指标 | `log.Logger`、`trace.Tracer`、`metrics.Registry` |
| 启动 | 健康检查 | `runtime.HealthRegistry` |
| 请求 | 路由 | `http.HttpRouter`（X）或应用 `Map` |
| 请求 | JSON 解析 | `codec.Json.parse` |
| 请求 | 校验 | `validate.Schema`、`ValidationResult` |
| 业务 | 缓存 | `cache.LruCache`/`TtlCache` |
| 业务 | 领域逻辑 | `xdk.errors`、`xdk.collections`、`xdk.time` |
| 响应 | JSON/错误映射 | `codec.Json.stringify`、`http.HttpResponse` |
| 观测 | 指标/日志 | `metrics.Counter/Timer`、`Logger.withField` |
| 停机 | 优雅关闭 | `HttpServer.gracefulShutdown`、`TaskGroup.close` |

### 1.3 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 配置 | `Config.getIntOr("port",8080)` | 端口 |
| JSON | `Json.parseObject(text)`、`Json.stringify(obj)` | 请求/响应 |
| 校验 | `Schema.field("email", Rules.email())` | 字段 |
| 缓存 | `LruCache(1000).getOrLoad(key, loader)` | 热点数据 |
| 指标 | `registry.counter("requests")`、`timer.start()/stop()` | 观测 |
| 追踪 | `tracer.startSpan("GET /orders")` | 链路 |
| 健康 | `healthRegistry.checkAll(context)` | readiness |
| 错误 | `mapErr(result, ...)`、`report` | 错误映射 |

### 1.4 失败/取消/资源

- 校验失败 → `ValidationResult.errors` → 400；不是 `Err` 传输错误。
- 业务失败 → `Result` → 映射 4xx/5xx。
- 请求取消 → `Context` 取消；停止缓存写入/DB 调用。
- 停机 → 停止 accept，等待在途，关闭缓存/追踪/日志 sink。

### 1.5 暴露的缺口

| 缺口 | 建议 |
| --- | --- |
| `HttpRouter` 是 X | 先应用 `Map` 路由；确认是否进 1.0 |
| 指标导出器 | `Exporter` 先做 Text/Prometheus |
| 配置热更新 | `ConfigWatcher` X |
| ORM/DB | ecosystem，不进 XDK |

### 1.6 验收谓词

- 启动缺配置必须失败且可诊断。
- 4xx/5xx 是正常 `HttpResponse`，不是 `Err`。
- 请求取消后不产生副作用。
- 指标/追踪/健康检查在停机和异常路径可用。

---

## 2. S2：监控采集 Agent

### 2.1 目标与边界

周期采集主机/进程/文件指标，聚合、压缩、上报；支持优雅停止。  
不设计服务端存储/告警平台。

### 2.2 主流程

| 阶段 | 动作 | API |
| --- | --- | --- |
| 启动 | 配置 | `Config`、`EnvSource` |
| 采集 | 系统信息 | `sys.SystemInfo`、`sys.Env`、`sys.ProcessBuilder` |
| 采集 | 文件/目录 | `fs.FileSystem`、`Metadata`、`walk` |
| 采集 | 时间 | `time.Clock`、`DateTime` |
| 聚合 | 统计 | `stats.Stats`、`Histogram` |
| 压缩 | 上报包 | `compress.Gzip` |
| 上报 | UDP/TCP | `UdpSocket.sendTo`、`TcpStream.writeAll` |
| 观测 | 日志/健康 | `Logger`、`HealthRegistry` |
| 停止 | 取消 | `Context`、`TaskGroup.close` |

### 2.3 API 演练

`sys.memory().used`、`sys.cpu().usagePercent`、`fs.metadata(path).modifiedMillis()`、`stats.mean(values)`、`Gzip.compress(payload)`、`UdpSocket.sendTo`、`HealthRegistry.checkAll`。  
失败：单目标失败用 `ErrorGroup` 聚合，不中止其他目标。

### 2.4 缺口

- 周期调度：`xdk.schedule` 或 core `Timer`。
- 系统信息深度：`CpuInfo/MemoryInfo/DiskInfo` 为 X。
- 上报重试：应用 `RetryPolicy`。
- 采集插件：应用层。

### 2.5 验收谓词

- 单个采集失败不影响整体。
- 压缩/上报失败可见。
- 取消后不再采集，进程/文件句柄关闭。

---

## 3. S3：消息中间件/转换管道

### 3.1 目标与边界

从队列/网络消费消息，解码、校验、转换、路由、死信、重试。  
不设计 MQ 协议栈；transport 是 /外部。

### 3.2 主流程

| 阶段 | 动作 | API |
| --- | --- | --- |
| 消费 | 有界队列 | `xdk.queue.BlockingQueue` |
| 解码 | JSON/CSV/bytes | `Json`、`Csv`、`ByteReader` |
| 校验 | 规则 | `validate.Schema` |
| 转换 | 集合/文本 | `collections`、`text` |
| 路由 | 映射 | `Map`、`cache` |
| 重试 | 分类/退避 | `RetryPolicy`、`Scheduler` |
| 死信 | 文件/队列 | `fs.File`、`queue` |
| 压缩 | 批包 | `Gzip` |
| 观测 | 指标/追踪 | `metrics`、`trace` |
| 停机 | 关闭 | `Channel.close`、`TaskGroup.close` |

### 3.3 缺口

- MQ 协议/客户端：ecosystem。
- 消息幂等：`cache`/应用。
- 批量确认：应用/transport。
- 死信重放：应用。

### 3.4 验收谓词

- 毒消息不死循环；死信路径明确。
- 背压有界；取消不丢 ack 状态。
- 转换失败可定位到消息/字段。

---

## 4. S4：CLI 数据处理工具

### 4.1 目标

读取 CSV/JSON/日志，过滤、排序、统计，输出 CSV/JSON/文本；支持参数/配置/退出码。

### 4.2 主流程

`cli.Parser` → `Config` → `fs.File`/`io.Reader` → `Csv`/`Json` → `collections`/`stats`/`text.Regex` → `Csv`/`Json`/`Writer` → `ExitCode`。

### 4.3 API 演练

`Parser.parse`、`OptionSpec`、`CsvReader.readRecord`、`Json.parse`、`Regex.findAll`、`sortBy`、`groupBy`、`Stats.mean`、`CsvWriter.writeRecord`、`ExitCode.Usage`。

### 4.4 缺口

- 大文件流式：`CsvReader` + `File.read` 已覆盖。
- 表格渲染：`terminal.Table`。
- 压缩输入：`Gzip.reader`。
- 断点/续跑：应用。

### 4.5 验收谓词

- 缺参/非法参数 → usage 退出码。
- 解析失败报告位置/原因。
- 大文件不一次性加载。
- 输出失败不留半文件（atomic write）。

---

## 5. S5：二进制协议网关

### 5.1 目标

TCP/UDP 收二进制帧，解析头/长度/校验和，路由，响应；支持并发连接。

### 5.2 主流程

`TcpListener`/`UdpSocket` → `ByteReader`/`Datagram` → `Endian`/`Bits` → `crypto.Crc32`/`Hash` → `compress.Gzip` → `Map` 路由 → `ByteWriter`/`Writer` → `TcpStream.writeAll`。

### 5.3 API 演练

`ByteReader.readExact`、`readU16BE/readU32BE`、`BitSet`、`Crc32.compute`、`Gzip.decompress`、`Map.getOr`、`ByteWriter.writeU32BE`、`TcpStream.writeAll`。

### 5.4 缺口

- 零拷贝视图：`BytesView` X。
- 协议编解码框架：ecosystem。
- 加密协议：应用组合 crypto。
- 连接限流：`Semaphore`/应用。

### 5.5 验收谓词

- 半包/截断 → `DataCorrupted`，位置不变。
- 未知类型/坏校验和 → 明确分类。
- 取消后不写半帧。

---

## 6. S6：WebSocket 推送服务

### 6.1 目标

HTTP 升级 WebSocket，频道订阅，服务端推送，心跳、背压、指标、追踪。

### 6.2 主流程

`HttpServer` → `HttpExchange.upgrade` → `WebSocket.accept` → 频道 `Map`/`Set` → `sendText/sendBinary` → `ping/pong` → `close`。  
客户端：`WebSocketClient` + `ReconnectPolicy`。

### 6.3 API 演练

`WebSocketOptions.pingInterval`、`maxSendQueueBytes`、`trySendText`、`WebSocketStats`、`metrics.Registry`、`trace.Tracer`、`runtime.HealthRegistry`。

### 6.4 缺口

- 频道广播框架：应用。
- 消息重放：应用/queue。
- WebSocket over HTTP/2：X。
- 压缩：`WebSocketCompression.PermessageDeflate`。

### 6.5 验收谓词

- Pong 超时关闭；慢客户端不阻塞其他连接。
- 关闭/重连不泄漏流。
- `trySend` 队列满返回 `Busy`。

---

## 7. S7：文件传输服务

### 7.1 目标

HTTP 上传/下载大文件，压缩/加密，断点/校验和，临时文件/原子落盘。

### 7.2 主流程

`HttpServer` → `MultipartForm`/`HttpBody` → `fs.File` → `Gzip`/`crypto` → `fs.writeTextAtomic`/`persist` → `HttpResponse` 流式下载。

### 7.3 API 演练

`MultipartOptions.maxPartBytes`、`MultipartPart.body.stream`、`File.writeAll`、`Gzip.writer`、`Hash.sha256`、`TempFile.persist`、`writeTextAtomic`、`HttpBody.fromStream`。

### 7.4 缺口

- 断点续传：X。
- 对象存储：ecosystem。
- 分片上传：应用。
- 病毒扫描：应用。

### 7.5 验收谓词

- 超限请求拒绝，不写半文件。
- 临时文件清理；失败不覆盖目标。
- 下载流式，不一次性加载。
- 校验和不匹配可见。

---

## 8. S8：mTLS 服务

### 8.1 目标

服务端要求客户端证书，证书链/信任库/轮换，审计客户端身份。

### 8.2 主流程

`TlsConfig.withServerCertificateChain` → `withClientAuth(Require)` → `TrustStore` → `HttpServer.bindTls` → `TlsStream.peerCertificates` → `audit.AuditLogger`。

### 8.3 API 演练

`Certificate.parsePem`、`PrivateKey.parsePem`、`TrustStore.addPem`、`TlsConfig.withCertificateVerification`、`TlsSessionInfo.alpnProtocol`、`AuditEvent`。

### 8.4 缺口

- 证书热轮换：`TlsConfigProvider` X。
- OCSP/CRL：X。
- HSM：ecosystem。
- 证书选择：应用。

### 8.5 验收谓词

- 无/坏客户端证书拒绝。
- 私钥不入日志。
- 轮换不影响旧连接。
- 关闭路径释放 TLS/底层流。

---

## 9. 场景到包的覆盖矩阵

| 包 | S1 | S2 | S3 | S4 | S5 | S6 | S7 | S8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| xdk.errors | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| xdk.collections | 是 | 是 | 是 | 是 | 是 | 是 | 是 | — |
| xdk.text | 是 | — | 是 | 是 | 是 | 是 | — | — |
| xdk.bytes | 是 | — | 是 | 是 | 是 | — | 是 | — |
| xdk.io/fs | 是 | 是 | 是 | 是 | 是 | — | 是 | 是 |
| xdk.sys | — | 是 | — | — | — | — | — | — |
| xdk.log/config/cli | 是 | 是 | 是 | 是 | — | 是 | 是 | 是 |
| core.tasks/sync | 是 | 是 | 是 | — | 是 | 是 | 是 | 是 |
| net.tcp/udp | — | 是 | — | — | 是 | — | — | — |
| net.http | 是 | — | — | — | — | 是 | 是 | 是 |
| net.websocket | — | — | — | — | — | 是 | — | — |
| net.tls | 是 | — | — | — | — | 是 | 是 | 是 |
| xdk.codec | 是 | — | 是 | 是 | 是 | — | 是 | — |
| xdk.crypto | — | — | — | — | 是 | — | 是 | 是 |
| xdk.compress | — | 是 | 是 | 是 | 是 | — | 是 | — |
| xdk.random/uuid | 是 | 是 | 是 | — | 是 | 是 | 是 | 是 |
| xdk.text | 是 | — | 是 | 是 | — | — | — | — |
| xdk.stats | 是 | 是 | 是 | 是 | — | 是 | — | — |
| xdk.validate | 是 | — | 是 | 是 | — | — | — | — |
| xdk.cache | 是 | — | 是 | — | — | 是 | — | — |
| xdk.queue | — | 是 | 是 | — | 是 | 是 | — | — |
| xdk.schedule | — | 是 | 是 | — | — | 是 | — | — |
| xdk.metrics/trace/runtime | 是 | 是 | 是 | — | — | 是 | — | — |
| xdk.audit | — | — | — | — | — | — | — | 是 |
| xdk.terminal | — | — | — | 是 | — | — | — | — |
| xdk.i18n | 是 | — | — | 是 | — | — | — | — |
| xdk.test | — | — | — | — | — | — | — | — |

---

## 10. 场景评审结论

- API 面的 core/net/utils 方法面足以支撑服务、监控、中间件、CLI、协议、推送、文件传输、mTLS 八类程序。
- 场景暴露的缺口主要是 X 级扩展，不是核心能力缺失。
- 网络层不再被当成“核心层内部”，而是独立的 L5/L6 层。
- 工具组不再是“零散函数”，而是有明确职责的子包。
