# XDK 2.x 剩余工作与质量缺口

| 项 | 值 |
| --- | --- |
| 口径 | `src/xdk/xdk2-packages.tsv` + 各包门禁；`implemented` = 有源码/场景/门禁，不等于每个类型/算法都完整 |
| 包计数 | **76 包 / 704 类型** |
| 包状态 | **48 implemented、14 design、14 个 1.x 基线** |
| 注解 | **98 条：56 implemented、4 reserved、38 planned** |
| L8 | Closed（10/10 包 implemented；accel/embedded 执行面硬件阻塞），见 [`L8-CLOSURE.md`](L8-CLOSURE.md) |
| 结论 | 不是“大部分没做”，而是“多数包有子集，14 包纯设计，B5 core 2.x 验证未收” |

---

## 1. 计划阶梯

| 批次 | 范围 | 当前状态 | 剩余 |
| --- | --- | --- | --- |
| B0–B4 | 架构、注解、runtime prelude、首批纯包 | 已完成 | 无 |
| L0–L8 | 包阶梯 | L0–L7 有实现子集；L8 已关闭 | 12 个 design 包 + 子集缺口 |
| B5 | L1–L3 core 15 包 2.x 化 | **未开工**（15 包仍是 1.x） | 15 包 Verified |
| B6 | data/encoding 12 包 | 11 implemented + 1 design | `xdk.reflect` + 子集 |
| B7 | network 9 包 | 8 implemented + 1 design | `xdk.net.tls` + 子集 |
| B8 | platform 17 包 | 7 implemented + 10 design | 10 包纯设计 |
| B9 | application services 12 包 | 12 implemented | 质量缺口（DateFormat/持久化/导出器） |
| B10 | solutions 10 包 | 10 implemented（2 个合同面/执行面 blocked） | agent 组件、ML 运行时、accel/embedded 执行面 |

> `EXECUTION-PLAN.md` 仍写“B5–B10 未开工”，是计划状态旧口径；实际包状态以本表和 tsv 为准。

---

## 2. B5：core 15 包（全部还是 1.x）

| 组 | 包 | 已知 Partial / 待验证 |
| --- | --- | --- |
| foundation | `errors`、`meta`、`bytes`、`text`、`collections`、`math`、`time` | `text`/`collections` 有 Partial 边界；需按 2.x 合同逐类型验证 |
| io/fs/sys | `io`、`fs`、`sys` | `io`/`fs`/`sys` 有 Partial；缺 2.x 合同覆盖的场景 |
| log/config/cli | `log`、`config`、`cli` | `log` 的 `Sampler` 实现改名为 `LogSampler`（与 `trace.Sampler` 冲突，C-0241）；需合同/文档同步 |
| execution | `runtime`、`execution` | `runtime` 仅 8 类型 1.x；`execution` 已 implemented，`Once` 方法名为 `run` |

**B5 出口**：15 包按逐类型合同 Verified；C7 的 11 包 1.x 实现/验证关闭；`xdk2` + `xdk` + `xdk_core` + 文档门禁全绿。

---

## 3. B6：data/encoding 12 包

| 包 | 状态 | 未做好/缺口 |
| --- | --- | --- |
| `xdk.codec` | implemented | JSON/CSV/Base64/Hex；YAML/TOML/XML 在独立包，codec 本身不覆盖 |
| `xdk.crypto` | implemented 子集 | **6/17**：Hash/Hmac/Checksum/ConstantTime；Cipher/Kdf/Asymmetric/KeyPair 未实现 |
| `xdk.compress` | implemented 子集 | **10/13**：Zstd/LZ4/Brotli 缺外部库 |
| `xdk.random` | implemented | OS CSPRNG + 可种子 PRNG |
| `xdk.uuid` | implemented | v4/v7/ULID |
| `xdk.stats` | implemented | 统计值类型 |
| `xdk.functional` | implemented | 函数组合基础 |
| `xdk.graph` | implemented | 图结构 |
| `xdk.reflect` | **design** | 需要编译器生成类型元数据表；当前不可靠实现 |
| `xdk.toml` | implemented 子集 | 日期/多行/inf-nan 显式 Unsupported |
| `xdk.yaml` | implemented 子集 | 多文档/profile/锚点/合并/属性扁平化子集 |
| `xdk.xml` | implemented 子集 | 元素树/实体/CDATA/DOCTYPE；未覆盖完整 XML 规范 |

---

## 4. B7：network 9 包

| 包 | 状态 | 未做好/缺口 |
| --- | --- | --- |
| `xdk.net` | implemented 子集 | **12/28**：IP/前缀/SocketAddress/TCP；Dns/Udp/连接池/TLS/HTTP2 未实现 |
| `xdk.net.uri` | implemented | URI/Query/percent 编解码 |
| `xdk.net.mime` | implemented | MediaType |
| `xdk.net.tls` | **design** | 需要 TLS 库/安全传输原语（握手、证书校验、SNI、ALPN） |
| `xdk.net.http` | implemented 子集 | **19/40**：text-only client/server；无 TLS/HTTP2/proxy/multipart；client 不解析 chunked |
| `xdk.net.websocket` | implemented 12/12 | 无 TLS（wss） |
| `xdk.net.service` | implemented 13/13 | 无 TLS、多线程、背压队列 |
| `xdk.jwt` | implemented 子集 | 仅 HS256；HS384/512、RS/PS/ES/EdDSA 未实现 |
| `xdk.sql` | implemented 子集 | 值模型/协议 + 内存驱动；无真实数据库驱动 |

---

## 5. B8：platform 17 包

### 已实现（7）

| 包 | 状态 | 缺口 |
| --- | --- | --- |
| `xdk.os` | 5/5 | `OsHost`/domain 子包仍 design |
| `xdk.os.cpu` | 5/5 | CpuAffinity 绑核 Unsupported |
| `xdk.os.memory` | 3/3 | DIMM/深度 NUMA planned |
| `xdk.os.storage` | 5/5 | SMART/SSD 探测 planned |
| `xdk.tensor` | 5/5 | B4 闭环 |
| `xdk.linalg` | 7/7 | B4 闭环 |
| `xdk.geo` | 6/6 | B4 闭环 |

### 纯设计（10）

`xdk.os.host`(2)、`xdk.os.hardware`(7)、`xdk.os.gpu`(6)、`xdk.os.firewall`(6)、`xdk.os.container`(5)、`xdk.os.virt`(5)、`xdk.os.service`(3)、`xdk.gpu`(8)、`xdk.serial`(6)、`xdk.device`(9)。

阻塞原语见 [`platform/HARDWARE-PRIMITIVES.md`](platform/HARDWARE-PRIMITIVES.md)：IOKit/sysctl/PCI/DRM、cgroup/namespace、systemd/launchd、termios/IOKit serial、USB/PCI 枚举。

---

## 6. B9：application services 12 包（全部 implemented，但有质量缺口）

| 包 | 缺口 |
| --- | --- |
| `xdk.validate` | 8 类型 + 5 注解，基本完整 |
| `xdk.cache` | 单进程 LRU/TTL/权重；无分布式/持久化 |
| `xdk.queue` | 无持久化、无优先级 |
| `xdk.schedule` | 单循环；无持久化/多 worker；`@Scheduled` 宿主未接入 |
| `xdk.event` | 同步 EventBus；无异步/持久化 |
| `xdk.resilience` | Retry/CircuitBreaker/RateLimiter/Bulkhead/Timeout/Fallback |
| `xdk.metrics` | Counter/Gauge/Histogram/Timer/Registry + Exporter 协议；无内置 OTLP/Prometheus 编码器 |
| `xdk.trace` | Span/Tracer/W3C traceparent/采样；span 是 tracer 级，非任务本地 |
| `xdk.audit` | AuditEvent/Level/Sink/Logger/Redactor |
| `xdk.terminal` | Color/Ansi/Style/Terminal/Table/ProgressBar/Spinner/Prompt |
| `xdk.i18n` | **6/7**：DateFormat 缺 `DateTimeFormatter` |
| `xdk.test` | TestSuite/Runner/Assert/Result + 4 注解 |

---

## 7. B10：solutions 10 包

| 包 | 状态 | 未做好/缺口 |
| --- | --- | --- |
| `xdk.auth` | 6/6 | Bearer/JWT + API key；认证与授权分离 |
| `xdk.jsonrpc` | 5/5 | 消息/Peer 形状 |
| `xdk.mcp` | 16/16 | HttpTransport 只解析完整 SSE 响应体；无流式 SSE/GET 独立流/连接池 |
| `xdk.ml` | 20/20 合同 | **无宿主推理运行时**；`openSession/run` Unsupported；Trainer 仅协议 |
| `xdk.numerics` | 12/12 类型 | `BigFloat.exp/log/pow` Unsupported；SpecialFunctions 部分为渐近/递推子集 |
| `xdk.db` | 11/11 | 仅内存驱动；池锁仅进程内 |
| `xdk.api` | 15/15 | `SseStream` 同步 chunked，无后台写任务/反压；无 TLS/HTTP2 |
| `xdk.agent` | **15/17** | 缺 HostMetricsReceiver/FileLogReceiver |
| `xdk.accel` | implemented 14（合同面） | Metal/CUDA/ROCm/Vulkan 执行路径 Unsupported；`fromGpuAdapter` 缺 `GpuAdapter` |
| `xdk.embedded` | implemented 12（合同面） | GPIO/I2C/SPI/UART/ADC/PWM/Watchdog/RTC/Flash 执行路径 Unsupported |

---

## 8. 注解剩余（38 planned）

| 组 | 注解 | 能否现在做 |
| --- | --- | --- |
| HTTP | `@StatusCode` | 可以（`HttpStatus` 已实现） |
| JWT | `@JwtClaim`、`@JwtHeaderField` | 可以（HS256 claims 已实现） |
| 格式 | `@YamlName`、`@TomlName`、`@XmlName` | 可以（三个解析包已实现子集） |
| WebSocket | `@WsHandler` | 可以（WebSocket 12/12） |
| 调度 | `@Scheduled` | 可以（schedule 8/8，需宿主接入） |
| API/DI | `@Api`、`@Operation`、`@Middleware`、`@Inject`、`@Component`、`@Configuration`、`@Bean` | API 注解可做；DI 容器未实现 |
| 硬件/设备 | GPU/Tensor/Linalg/ML/Agent/Serial 等领域注解 | 依赖对应包或原语 |
| S6 | `@tasks`、`@arena` | reserved，不在 1.0 范围 |

---

## 9. “implemented 但没做好”清单（硬缺口）

| 严重度 | 项 | 证据/影响 | 下一步 |
| --- | --- | --- | --- |
| 高 | `xdk.net.tls` 纯设计 | HTTPS/wss/安全服务全部不可用 | 接 TLS 库原语 |
| 高 | `xdk.reflect` 纯设计 | 运行时类型元数据不可用 | 编译器生成元数据表 |
| 高 | B8 平台 10 包纯设计 | 主机/硬件/GPU/防火墙/容器/虚拟化/串口/设备不可用 | 按原语清单补 |
| 高 | `xdk.accel`/`xdk.embedded` 执行面 | 合同面已实现，真实设备/内核/引脚操作 Unsupported | Metal + Linux 目标板后端 |
| 高 | `xdk.agent` 11/17 | 无主机指标/文件日志/批处理/限流/OTLP/Prometheus | 先做 4 个纯组件 |
| 中 | `xdk.crypto` 6/17 | 无对称加密/非对称/KDF | 接 OpenSSL/CommonCrypto 原语 |
| 中 | `xdk.net` 12/28 | 无 DNS/UDP/连接池/HTTP2 | 先 DNS/UDP |
| 中 | `xdk.net.http` 19/40 | 无 TLS/HTTP2/proxy/multipart；client 无 chunked | 先 client chunked + TLS |
| 中 | `xdk.sql`/`xdk.db` 内存驱动 | 不能连真实数据库 | 驱动 SPI + 一个真实驱动 |
| 中 | `xdk.ml` 无运行时 | 推理不可用 | 宿主适配器接口 |
| 中 | `xdk.numerics.BigFloat` 超越函数 | exp/log/pow Unsupported | 任意精度级数 |
| 中 | `xdk.api.SseStream` 同步 | 无后台写任务/反压 | 写任务 + 缓冲 |
| 低 | `xdk.i18n.DateFormat` | 日期格式化缺失 | `DateTimeFormatter` |
| 低 | `xdk.metrics` 无 OTLP/Prometheus | 导出器缺失 | agent 组件一起做 |
| 低 | `xdk.schedule`/`queue` 无持久化 | 仅进程内 | 存储适配器 |
| 低 | 1.x core Partial | text/collections/io/fs/sys | B5 收口 |

---

## 10. 工程债 / 文档漂移

| 项 | 说明 |
| --- | --- |
| 枚举 0 与 null | 多个包用 `Unknown` 哨兵；合同/实现有偏差，需编译器修 |
| 泛型 `Pair` 冲突 | `BigInt.divideAndRemainder` 改用 `BigIntPair`；待编译器修复 |
| `String? == String?` | 指针比较 bug；JWT 用 `jwtSameText` 规避 |
| 泛型内联 lambda 捕获 | 部分闭包需显式函数变量/工作区 |
| 跨线程 GC 根 | 保守栈根已加，字段/容器扫描仍不完整 |
| 大 Long 负字面量 | 解析 bug 未修 |
| execution 计时 flake | `exec=2,4,false,true` 偶发；测试已用原子计数硬化 |
| `xdk2` 时长 | 817s，超过 ~700s 预算 |
| 无重载 | setter/getter 用 `get*`/`with*` 命名；合同与实现有偏差 |
| `Result<enum>` | 编译器不支持，解析用 `Unknown` 哨兵 |
| 计划文档 | `COVERAGE.md`/`PACKAGE-MAP.md`/`ARCHITECTURE.md`/`EXECUTION-PLAN.md` 仍写 75/698；`PLAN.md` 写 B5–B10 未开工 |
| `PACKAGE-MAP.md` | 缺 `xdk.auth` 行 |
| `core/STATUS.md` | 1.x 视角，未列 2.x 新包 |

---

## 11. 建议执行顺序

1. **B5.1**：foundation 7 包按 2.x 合同验证（先 `text`/`collections`）。
2. **B5.2**：io/fs/sys；**B5.3** log/config/cli；**B5.4** runtime/execution。
3. **注解快赢**：`@StatusCode`、`@JwtClaim`、`@JwtHeaderField`、`@YamlName`、`@TomlName`、`@XmlName`、`@WsHandler`、`@Scheduled`。
4. **B10 可做项**：`xdk.agent` 的 BatchProcessor/MemoryLimiter/Prometheus/Otlp；`BigFloat.exp/log/pow`。
5. **B7 关键路径**：TLS 原语 → HTTPS/wss；net DNS/UDP。
6. **B8/B10 硬件**：Metal accel + Linux embedded 目标后端；其余保持 blocked。
7. **文档收口**：统一 76/704；更新计划状态；补 `xdk.auth` 行。

---

## 12. 执行队列（按顺序，不跳批）

| ID | 批次 | 内容 | 状态 |
| --- | --- | --- | --- |
| L8-1 | accel 合同面 | 14 类型 + 描述符/校验 + 硬件执行 Unsupported | implemented |
| L8-2 | embedded 合同面 | 12 类型 + 板级描述 + 硬件执行 Unsupported | implemented |
| L8-3 | agent 纯组件 | BatchProcessor/MemoryLimiterProcessor/PrometheusExporter/OtlpExporter | implemented |
| L8-4 | agent 硬件组件 | HostMetricsReceiver/FileLogReceiver（依赖 OsHost/PathMatcher） | blocked |
| L8-5 | BigFloat 超越函数 | exp/log/pow + 任意精度级数 | queued |
| B5-1 | core foundation | errors/meta/bytes/text/collections/math/time 2.x 验证 | queued |
| B5-2 | core io/fs/sys | io/fs/sys 2.x 验证 | queued |
| B5-3 | core log/config/cli | log/config/cli 2.x 验证 | queued |
| B5-4 | core runtime/execution | runtime/execution 2.x 验证 | queued |
| B6-1 | 格式注解 | @YamlName/@TomlName/@XmlName | queued |
| B6-2 | reflect | 编译器类型元数据表 | blocked |
| B6-3 | crypto/compress | Cipher/Kdf/Asymmetric；Zstd/LZ4/Brotli | blocked |
| B7-1 | TLS | 握手/证书/SNI/ALPN | blocked |
| B7-2 | net DNS/UDP | Dns/Udp/连接池 | queued |
| B7-3 | http client | chunked 解码 + TLS | queued |
| B8-1 | 平台原语 | Metal accel、Linux GPIO/I2C/SPI/UART | blocked |
| B9-1 | DateFormat | DateTimeFormatter + @Scheduled 宿主 | queued |
| B9-2 | 导出器 | OTLP/Prometheus 编码器 | queued |
| AN-1 | 注解快赢 | @StatusCode/@JwtClaim/@JwtHeaderField/@WsHandler | queued |
| AN-2 | DI 注解 | @Inject/@Component/@Configuration/@Bean | blocked（无 DI 容器） |

规则：每批必须有源码、场景、门禁、提交；blocked 必须有原语清单和复现证据；不得用“下批再做”作为批末状态。
