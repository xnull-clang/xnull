# XNull 实现状态总览

| 项 | 值 |
| --- | --- |
| 日期 | 2026-11-26 |
| 权威来源 | `src/xdk/xdk2-packages.tsv`、`docs/design/ANNOTATION-CATALOG.md`、各包门禁 |
| 包计数 | **76 包 / 704 类型** |
| 包状态 | `1.x` 14 包 / 169 类型；`implemented` 48 包 / 432 类型；`design` 14 包 / 103 类型 |
| 注解计数 | **98 条**：implemented 56、reserved 4、planned 38 |
| 结论口径 | `design` = 合同已写；`implemented` = 有源码、场景、门禁；不等于文档里的每个类型/算法都已实现 |

> 本文件回答“docs/design 的设计是否全部做完”，不复制逐类型合同。
> 逐批剩余与质量缺口见 [`2X-REMAINING.md`](2X-REMAINING.md)。
> `COVERAGE.md`/`PACKAGE-MAP.md` 仍写 75/698，是旧口径；以本文件与 tsv 为准。

---

## 1. 结论

**没有全部做完。**

- 76 个包中：**48 个 implemented、14 个仅设计、14 个 1.x 基线**。
- 98 条注解中：**56 implemented、38 planned、4 reserved**。
- 已实现的 48 个包里，部分只是**子集**：`xdk.net.http`（40 类型文档中实现 19）、`xdk.crypto`（17 文档类型中实现 6）、`xdk.jwt`（仅 HS256）、`xdk.sql`/`xdk.db`（仅内存驱动）。
- 仍有 **14 个包纯设计**；已 implemented 的包多数是**子集**；C7 的 1.x→2.x 验证随 B5 收口。

一句话：**注解平台与多数领域已实现子集；剩余主要矛盾是 14 个设计包、B5 core 2.x 验证和已实现包的深度缺口。**

L8 solutions 里程碑已关闭：8/10 包 implemented，`xdk.accel`/`xdk.embedded` 因缺硬件原语保持 blocked；详见 [`L8-CLOSURE.md`](L8-CLOSURE.md)。

---

## 2. 按层汇总

| 层 | 包 | 类型 | `1.x` | `implemented` | `design` |
| --- | ---: | ---: | ---: | ---: | ---: |
| L0 annotations | 1 | 14 | 0 | 1 | 0 |
| L1 runtime/execution | 2 | 25 | 1 | 1 | 0 |
| L2 core 基础 | 7 | 80 | 7 | 0 | 0 |
| L3 core 系统 | 6 | 81 | 6 | 0 | 0 |
| L4 数据/编码 | 12 | 76 | 0 | 11 | 1 |
| L5 网络/数据 | 9 | 125 | 0 | 8 | 1 |
| L6 平台/计算 | 17 | 93 | 0 | 7 | 10 |
| L7 应用服务 | 12 | 82 | 0 | 12 | 0 |
| L8 解决方案 | 10 | 128 | 0 | 8 | 2 |
| **合计** | **76** | **704** | **14** | **48** | **14** |

---

## 3. 已实现包（48）

| 包 | 文档类型 | 真实范围 / 边界 |
| --- | ---: | --- |
| `xdk.annotations` | 14 | IR v1/v2、Builtin Registry v2、manifest、阶段调度、生成源码、沙箱、诊断合并、增量缓存、注解面门禁 |
| `xdk.codec` | 13 | JSON、CSV、Base64、Hex；YAML/TOML/XML 未实现 |
| `xdk.crypto` | 17 | Hash/Hmac/Checksum/ConstantTime（MD5/SHA-1/SHA-256/SHA-512 + HMAC）；Cipher/Kdf/Asymmetric 未实现 |
| `xdk.stats` | 7 | BucketHistogram/Summary 等统计值类型 |
| `xdk.execution` | 17 | Semaphore/WaitGroup/Once/RwLock/Pool/Promise/Future/Executor + 运行时 Task/Context；`Once` 方法名为 `run` |
| `xdk.random` | 4 | Random/SecureRandom/RandomSource/WeightedChoice；OS CSPRNG + 可种子 PRNG |
| `xdk.compress` | 13 | 实现 10/13：CompressionLevel/Gzip/Zlib/Deflate/TarEntry/Tar/ZipEntry/ZipOptions/ZipArchive/ZipWriter；Zstd/Lz4/Brotli planned |
| `xdk.toml` | 2 | Toml/TomlOptions；子集解析/规范化输出，日期/多行/inf-nan 显式 Unsupported |
| `xdk.xml` | 3 | Xml/XmlElement/XmlOptions；元素树、实体/数字引用、CDATA、DOCTYPE 安全默认 |
| `xdk.yaml` | 5 | Yaml/YamlDocument/YamlOptions/YamlPropertySource/YamlVersion；多文档、profile、锚点/合并、属性扁平化 |
| `xdk.uuid` | 3 | Uuid v4/v7/UuidVersion/Ulid；ULID 同毫秒单调 |
| `xdk.functional` | 3 | 函数组合基础 |
| `xdk.graph` | 2 | 图结构 |
| `xdk.net.uri` | 2 | URI/Query/percent 编解码 |
| `xdk.net.mime` | 2 | MediaType 等 |
| `xdk.net` | 28 | 实现 12/28：IP/前缀/SocketAddress/TCP 核心；Dns/Udp/连接池/TLS/HTTP2 planned |
| `xdk.net.websocket` | 12 | 实现 12/12：ws 握手/帧/掩码/分片/关闭、服务端、显式重连客户端 |
| `xdk.net.service` | 13 | 实现 13/13：服务端/客户端/NetworkService、连接/会话、策略与统计；TLS/多线程/背压队列未实现 |
| `xdk.os` | 5 | 实现 5/5：OsKind/OsFamily/OsCapability/OsInfo/OsProfile + 本机 detect；OsHost/domain 子包 planned |
| `xdk.os.cpu` | 5 | 实现 5/5：CpuCore/CpuCache/CpuTopology 检测 + CpuAffinity 生命周期；绑核 Unsupported |
| `xdk.os.memory` | 3 | 实现 3/3：NumaNode/MemoryModule/PhysicalMemory；DIMM 与深度 NUMA planned |
| `xdk.os.storage` | 5 | 实现 5/5：挂载点→Partition/Device、totals/查询；SMART/SSD 探测 planned |
| `xdk.queue` | 5 | 实现 5/5：BoundedQueue 三策略、BatchQueue、DelayQueue、QueueStats；无持久化/优先级 |
| `xdk.schedule` | 8 | 实现 8/8：cron/一次性/固定频率/固定延迟、JobHandle、单循环调度；无持久化/多 worker |
| `xdk.event` | 3 | 实现 3/3：同步 EventBus、精确 topic、锁外回调、首错短路 |
| `xdk.terminal` | 8 | 实现 8/8：Color/Ansi/Style/Terminal/Table + ProgressBar/Spinner/Prompt |
| `xdk.i18n` | 7 | 实现 6/7：Locale/PluralRules/NumberFormat/Catalog/Formatter/Translator；DateFormat planned |
| `xdk.numerics` | 12 | 12/12 类型：核心 11 + BigFloat 算术/开方/舍入/转换；exp/log/pow planned |
| `xdk.jsonrpc` | 5 | 实现 5/5：Id/Error/Request/Response/Peer；仅消息与协议形状 |
| `xdk.mcp` | 16 | 实现 16/16：消息模型 + Stdio/Client/Server/Registry/HttpTransport（JSON + 完整 SSE 体） |
| `xdk.ml` | 20 | 实现 20/20 合同：模型/会话/数据管道/损失；`openSession/run` 因无运行时适配器返回 Unsupported |
| `xdk.agent` | 17 | 实现 11/17：遥测核心/管线/Agent；具体 receiver/exporter 未实现 |
| `xdk.api` | 15 | 实现 15/15：ProblemDetails/路由/上下文/OpenAPI/ApiServer/SseStream（同步 chunked） |
| `xdk.net.http` | 40 | 路由闭环子集 19 类型：Method/Status/Headers/Body/Request/Response/Form/Cookie + client/server（text-only）；无 TLS/HTTP2/proxy/multipart/流式 |
| `xdk.jwt` | 6 | HS256 encode/decode/verify + JwtAuthenticator；HS384/512、RS/PS/ES/EdDSA 未实现 |
| `xdk.auth` | 6 | AuthScheme/Credential/Principal/Authenticator/AuthService/AuthHeaders；Bearer/JWT + API key |
| `xdk.sql` | 12 | 值模型、参数、语句、结果、驱动/连接/事务协议；内存驱动 |
| `xdk.tensor` | 5 | B4 张量闭环 |
| `xdk.linalg` | 7 | B4 线代闭环 |
| `xdk.geo` | 6 | B4 地理计算 |
| `xdk.validate` | 8 | Rule/Rules/Schema/FieldRule/Result/Error/Context/Validator + 5 注解 |
| `xdk.cache` | 4 | LRU+TTL+权重+统计 + 2 注解 |
| `xdk.resilience` | 7 | Retry/CircuitBreaker/RateLimiter/Bulkhead/Timeout/Fallback + 4 注解 |
| `xdk.metrics` | 11 | Counter/Gauge/Histogram/Timer/Registry + Exporter 协议 + `@Metered`；无内置编码器 |
| `xdk.trace` | 9 | Span/Tracer/W3C traceparent/采样 + `@Traced`；当前 span 为 tracer 级，非任务本地 |
| `xdk.audit` | 5 | AuditEvent/Level/Sink/Logger/Redactor + `@Audited` |
| `xdk.test` | 7 | Test/TestSuite/TestRunner/Assert/TestContext/TestResult/TestStatus + 4 注解 |
| `xdk.db` | 11 | Config/Pool/Stats/Database/Batch/RowMapper/Isolation/Migration/Runner/Health/Db；内存驱动，池锁仅进程内 |

---

## 4. 仅设计、未实现（14）

| 层 | 包 |
| --- | --- |
| L4 | `xdk.reflect` |
| L5 | `xdk.net.tls` |
| L6 | `xdk.os.host`、`xdk.os.hardware`、`xdk.os.gpu`、`xdk.os.firewall`、`xdk.os.container`、`xdk.os.virt`、`xdk.os.service`、`xdk.gpu`、`xdk.serial`、`xdk.device` |
| L8 | `xdk.accel`、`xdk.embedded` |

这些包在 `docs/design/` 下有合同/类型文档，但 `src/xdk/` 无实现或仅有设计占位。

---

## 5. 1.x 基线（14）

`xdk.runtime`、`xdk.errors`、`xdk.meta`、`xdk.bytes`、`xdk.text`、`xdk.collections`、`xdk.math`、`xdk.time`、`xdk.io`、`xdk.fs`、`xdk.sys`、`xdk.log`、`xdk.config`、`xdk.cli`。

状态以 `docs/design/core/STATUS.md` 为准：多数 Verified（mini），`text`/`collections`/`io`/`fs`/`sys` 有 Partial 边界。`xdk.runtime` 本轮新增 `RuntimeMonitor.waitDeadline`；`xdk.time` 新增 `Instant`/`TimeZone`（UTC/固定偏移，M21.0）。

---

## 6. 注解题材（98 条）

- **implemented 56**：内建/元模型 9、A8 派生 5、领域 42。
- **领域已完成**：CLI 4、codec 3、validate 5、http 4、sql 4、db 4、resilience 4、cache 2、audit 1、test 4、metrics 1、trace 1、auth 5。
- **planned 38**（主要分组）：
  - `@StatusCode`
  - `@JwtClaim` / `@JwtHeaderField`
  - `@YamlName` / `@TomlName` / `@XmlName`
  - `@WsHandler`
  - `@Scheduled`
  - API/DI：`@Api` / `@Operation` / `@Middleware` / `@Inject` / `@Component` / `@Configuration` / `@Bean`
  - 硬件/设备/GPU/Tensor/Linalg/ML/Agent/Serial 等领域注解
  - S6：`@tasks` / `@arena`
- 4 条 reserved 不改变语义。

---

## 7. 仍未完成的“大设计”

| 项 | 现状 |
| --- | --- |
| B5–B10 | B5 的 15 个 core 包仍是 1.x；B6–B10 多数包已 implemented 子集，仍有 14 个 design 包和若干运行时/硬件缺口 |
| C7 | 合同已整合，实现/验证随 B5 未开始 |
| 平台/OS/GPU/Serial/Device | 14 包仅设计；需平台原语与场景 |
| 网络/TLS/WebSocket | 无 TLS/HTTP2 运行时原语；WebSocket 已实现 12/12 但无 TLS；HTTP client 仍为 text-only |
| 格式 | YAML/TOML/XML 包已实现子集；对应 `@YamlName`/`@TomlName`/`@XmlName` 注解仍 planned |
| 调度 | `xdk.schedule` 单循环已实现；`@Scheduled` 宿主仍待接入 |
| API/DI/ML/Agent | `xdk.api` 15/15；`xdk.ml` 合同完成但无运行时；`xdk.agent` 11/17；DI 未实现 |
| 密码学扩展 | Cipher/Kdf/Asymmetric/KeyPair 未实现（无对应运行时原语） |
| 可观测性 | metrics/trace/audit 已有核心；无 OTLP/导出器/内置 Prometheus 编码器 |
| 编译/运行时债 | `String? == String?` 指针比较、泛型内联 lambda 捕获、跨线程 GC 根、枚举 0 与 null、泛型 `Pair` 冲突、大 Long 负字面量、execution 计时 flake、门禁时长（xdk2 >700s） |

---

## 8. 文档漂移（需同步）

| 文档 | 漂移 |
| --- | --- |
| `COVERAGE.md` | 仍写 75/698，且“L4/L5/L6/L7/L8 未实现”已被部分推翻 |
| `PACKAGE-MAP.md` | 75/698，缺 `xdk.auth` 行（实际 76/704） |
| `ARCHITECTURE.md` / `EXECUTION-PLAN.md` | 75/698；“下一步 B5”未反映注解/领域闭环 |
| `PLAN.md` | “B0–B4 已完成；B5–B10 未开工”仍成立，但未记录注解平台完成 |
| `ANNOTATION-CATALOG.md` | 已更新为 98/56/38/4；逐行状态仍有少数缺列 |
| `core/STATUS.md` | 1.x 视角；未列 2.x 新包 |

建议：以本文件为当前总览；下一次文档批次统一把 75/698 改为 76/704，并把注解平台/认证/观测/缓存/测试/DB 加入计划状态。

---

## 9. 下一步优先级（建议）

1. B5：L1–L3 core 15 包 2.x 实现/验证（`text`/`collections`/`io`/`fs`/`sys` 的 Partial 边界先收）
2. B6：`xdk.reflect`（需类型元数据表）；`@YamlName`/`@TomlName`/`@XmlName` 可先做
3. B7：TLS 原语；`xdk.net` 的 DNS/UDP/连接池/HTTP2；`@WsHandler` 可基于已实现 WebSocket
4. B8：平台/OS/GPU/Serial/Device 原语（见 `platform/HARDWARE-PRIMITIVES.md`）
5. B10：`xdk.agent` 具体组件、`xdk.accel`/`xdk.embedded`、`BigFloat.exp/log/pow`、ML 运行时
6. 注解：`@JwtClaim`/`@JwtHeaderField`、`@Scheduled`、API/DI 注解

---

## 10. 维护

- 包/类型/状态先改 `src/xdk/xdk2-packages.tsv`；注解状态先改 `ANNOTATION-CATALOG.md`。
- 本文件只做汇总，不替代逐包合同与门禁。
- `implemented` 必须同时有：源码、场景、门禁；缺一保持 `design`。
