# XNull 2.x 架构基线

| 项 | 值 |
| --- | --- |
| 状态 | Draft for architecture sign-off；不含实现 |
| 范围 | `docs/design` 的 2.x 设计树；UI/desktop 已移除 |
| 1.x 基线 | `docs/design/t0` + `src/xdk`；14 个公开包 / 160 symbols / 8 个严格 Verified |
| 2.x 目标 | 75 包 / 698 类型；逐包见 [`PACKAGE-MAP.md`](PACKAGE-MAP.md) |
| 第一实现层 | 注解（语言/编译器/元数据/处理器），先于 core |
| 原则 | 包是能力合同，类是包的结构；只在替换边界抽象；不按现有目录堆包 |

---

## 1. 为什么要重做

当前设计树是按“目录 + 包清单”长出来的：76 包、712 类型，但包与包之间的能力边界、类的角色、依赖方向没有统一。结果是：

- 同一能力有多个实现面：`core.LRUCache` 与 `xdk.cache.Cache`、`log.Redactor` 与 `audit.Redactor`、`net.tls.PrivateKey` 与 `crypto.PrivateKey`；
- 同一简单名在不同包换义：`Histogram`、`Timer`、`ServiceState`、`Signal`、`ReconnectPolicy`；
- 新 core 文档比 t0 旧，删掉了 1.x 已实现的能力：`RuntimeStats/stats`、`joinWith`/`Entry`、log `Filter`/`Redactor`/`Sampler`、CLI 短选项/补全、sys 进程组/stdio；
- `xdk.core.*`、`xdk.utils.*` 被当成包名使用，但源码里的真实包是 `xdk.errors`、`xdk.log` 等；`xdk.execution` 曾被加上 `core.` 前缀；
- 大量包把“具体类”当公共 API，导致 mock、替换、跨平台都不可能。

2.x 不再按现有目录继续加文件，而是先定“能力合同 + 类角色 + 抽象边界”，再让包和类归位。

---

## 2. XNull 风格（硬约束）

1. **协议 + 组合**：行为用 protocol 表达，不用继承；公共 API 优先暴露协议、不可变值、工厂，不暴露具体实现类。
2. **Result 而不是异常**：可恢复失败走 `Result<T, Error>`；`panic`/`throw` 只用于合同错误。
3. **Context 取消**：可阻塞方法首参 `Context`；取消返回 `Cancelled`。
4. **资源句柄**：`close()` 幂等；`isOpen()`；不暴露裸 fd/指针。
5. **编译期注解，无运行时反射**：注解由编译器/处理器生成代码或静态元数据；运行时只读注册表。
6. **无全局状态**：依赖通过构造器/Options/Context 注入；不提供全局注册表、全局连接池、全局 logger。
7. **有界抽象**：只在“可替换边界”抽协议；不为抽象而抽象，不做通用框架。
8. **1.x 兼容线**：1.x 已发布能力保留在 `release/1.0` + `docs/design/t0`；2.0 的破坏性变化必须有迁移表和适配器。

---

## 3. 分层

```text
L0  Language / Compiler     注解、语法、语义、诊断、codegen、FFI lowering
L1  Runtime / Execution     内存、任务、同步、时间、IO 原语
L2  Core Foundation         errors/meta/bytes/text/collections/math/time
L3  Core System             io/fs/sys/log/config/cli
L4  Data / Encoding         codec/crypto/compress/random/uuid/stats/
                            functional/graph/reflect/toml/yaml/xml
L5  Network / Data          net/uri/mime/tls/http/websocket/net.service/jwt/sql
L6  Platform / Compute      os.* + gpu/tensor/linalg/geo/serial/device
L7  Application Services    validate/cache/queue/schedule/event/resilience/
                            metrics/trace/audit/terminal/i18n/test
L8  Solutions               api/db/ml/agent/numerics/jsonrpc/mcp/accel/embedded
```

依赖方向只能向下：

```text
L8 → L7/L6/L5/L4/L3/L2/L1
L7 → L6/L5/L4/L3/L2/L1
L6 → L5/L4/L3/L2/L1
L5 → L4/L3/L2/L1
L4 → L3/L2/L1
L3 → L2/L1
L2 → L1/L0
L1 → L0
```

禁止反向依赖；`core` 不得依赖 `net`/`platform`/`data`/`services`/`solutions`。

同一层内允许单向依赖（例如 `random → uuid`、`codec → toml/yaml/xml`、`net → net.tls → net.http`），但必须无环；层不是全序，包表里的依赖列才是实现顺序。

> 层号只表示依赖方向，不表示目录、发布顺序或实现顺序。权威包/类型清单见 [`PACKAGE-MAP.md`](PACKAGE-MAP.md)。

---

## 4. 包 = 能力合同

**包不是目录，也不是文件分组；包是一个可独立验收的能力合同。**

每个包必须回答：

1. 它提供什么能力，明确不提供什么；
2. 它的公共协议/值/工厂/句柄是什么；
3. 它的依赖方向和被依赖方；
4. 它的失败通道、取消语义、资源生命周期；
5. 它的场景、门禁、稳定性标签；
6. 它的公共简单名是否与其他包冲突，冲突时谁拥有该名字。

### 4.1 命名规则

- 公共包名必须是能力名，不是分层名：`xdk.codec`、`xdk.crypto`、`xdk.cache`，不是 `xdk.codec`。
- `xdk.core` / `xdk.utils` / `xdk.solutions` 只作为**文档分组/层名**，不作为包名前缀。
- 源码包名以 `src/xdk` 和 `src/ffi/api-manifest.tsv` 为准：`xdk.errors`、`xdk.runtime`、`xdk.io`、`xdk.fs`、`xdk.sys`、`xdk.log`、`xdk.config`、`xdk.cli`。
- 执行层统一为 `xdk.execution`；`xdk.tasks`/`xdk.sync` 是 1.x 语言/运行时内建，不是 2.x 公共包。
- `xdk.net.service` 是网络服务编排包，归 L5，不归 solutions。
- `xdk.reflect` 是**只读类型元数据查询**，不是动态反射；不提供动态调用/构造/类加载。
- 一个简单名只能有一个语义 owner；跨包同名必须改名或始终包名限定，登记在 [`DESIGN-CONSISTENCY.md`](DESIGN-CONSISTENCY.md)。

### 4.2 包状态

只有三种完成状态：

| 状态 | 含义 |
| --- | --- |
| `design` | 合同完整，实现未开始 |
| `implemented` | 代码存在，场景未全绿 |
| `verified` | 场景、回归、门禁通过 |

`preview` 是稳定性标签，不是完成状态。1.x 与 2.x 分开记账，不共享 `Verified`。

### 4.3 包不因“文件多”而拆

拆包只允许三种理由：

1. 能力边界不同（例如 `xdk.net` 与 `xdk.net.http`）；
2. 替换边界不同（例如 `xdk.crypto` 与 `xdk.net.tls`）；
3. 依赖方向不同（例如 `xdk.codec` 必须低于 `xdk.net.http`）。

不为“一个类一个包”、不为目录对称、不为减少文件数而拆。

---

## 5. 类 = 包的结构

每个公开类型必须属于以下角色之一：

| 角色 | 用途 | 例子 |
| --- | --- | --- |
| Value | 不可变值/快照 | `Bytes`、`Duration`、`ConfigEntry`、`HttpHeader` |
| Protocol | 可替换行为 | `Reader`、`Writer`、`Sink`、`Codec`、`Transport`、`SqlDriver` |
| Service | 有生命周期的服务 | `Logger`、`ConfigLoader`、`HttpServer`、`Scheduler`、`Executor` |
| Handle | 资源句柄 | `File`、`Dir`、`Process`、`Channel`、`Mutex`、`TlsStream` |
| Builder | 配置构造 | `OpenOptions`、`HttpClientOptions`、`ProfileBuilder` |
| Registry | 查找/注册 | `AnnotationRegistry`、`MetricRegistry`、`Command` 树 |
| Processor | 编译期处理 | `AnnotationProcessor`、`AnnotationProcessorContext` |
| Error | 诊断/错误值 | `ErrorKind`、`BasicError`、`ErrorReport` |
| Enum | 封闭分类 | `HttpMethod`、`Signal`、`LogLevel`、`GpuBackend` |

禁止：

- 用 class 冒充 protocol（例如把 `Reader` 写成 class，再另造一个 `Readable`）；
- 公共 API 返回内部实现类；
- 同一个简单名在不同包表达不同语义而不限定；
- 用“万能 Manager/Helper/Util”承载多个能力；
- 把 Builder 当运行时对象长期持有。

---

## 6. 抽象边界

只在以下边界抽协议；其他位置优先具体值/具体类：

| 边界 | 协议 | 具体实现放哪 |
| --- | --- | --- |
| 字节流 | `Reader`/`Writer`/`Seekable`/`Closer` | `xdk.io` 的 ByteArray/String/Buffered/Chain/Tee/Limit |
| 编解码 | `Codec`/`Decoder`/`Encoder` | `xdk.codec` 的 Json/Csv/Base64/Hex，`xdk.toml/yaml/xml` |
| 网络传输 | `ByteStream`/`Listener`/`Transport`/`Connection` | `xdk.net` 的 TCP/UDP，`xdk.net.tls` 的 TlsStream |
| 存储 | `FileSystem`/`File`/`Dir`/`Metadata` | `xdk.fs` 的本地文件系统 |
| 执行 | `Executor`/`TaskGroup`/`Channel`/`Mutex`/`Semaphore`/`RwLock` | `xdk.execution` + runtime |
| 可观测 | `Sink`/`Exporter`/`Sampler`/`Filter`/`Redactor` | `xdk.log`/`xdk.metrics`/`xdk.trace`/`xdk.audit` |
| 数据访问 | `SqlDriver`/`SqlConnection`/`SqlTransaction`/`ConfigSource`/`Cache`/`Queue` | `xdk.sql`/`xdk.config`/`xdk.cache`/`xdk.queue` |
| 注解 | `AnnotationProcessor`/`AnnotationRegistry`/`AnnotationElement` | `xdk.annotations` + 编译器 |
| 平台 | `OsHost`/`GpuAdapter`/`GpuDevice`/`SerialPort`/`DeviceManager` | `xdk.os.*` + FFI 适配器 |

抽象时机：

- 有第二个真实实现，或存在明确的替换边界（OS/TLS/存储/测试）时才抽协议；
- 单实现、单调用方的内部逻辑先用具体类，不预留“未来可能”的接口；
- 协议只描述行为，不描述存储；方法必须写清失败、取消、所有权；
- 协议非泛型；泛型只用于 class/函数/方法；
- 不在协议里放“方便方法”，方便方法放顶层函数或扩展包。

---

## 7. 注解优先

注解是 2.x 的第一个实现层。原因不是“注解很酷”，而是后续包的大量样板必须由编译器生成，否则抽象会退化成宏、代码复制或运行时反射。

### 7.1 注解能力边界

- 注解是**编译期声明、检查、生成入口**；
- 运行时只读编译器生成的静态注册表；
- 不做类路径扫描、动态加载、动态代理、运行时处理器；
- `@MustUse` 是语言规则，不是用户注解；
- `@tasks`/`@arena` 是块注解，归语言 S5，不进入通用注解系统；
- 领域注解定义在所属包，不全部塞进 `xdk.annotations`。

### 7.2 编译器管线

```text
lexer/parser
  → AST（@annotation 声明 / @Name 使用）
  → 语义解析（类型/目标/保留/重复）
  → 常量求值（默认值/数组/嵌套注解/类型引用）
  → 内建强制（ReadOnly/Override/Deprecated/SuppressWarnings/MustUse）
  → 处理器调度（Resolve → Validate → Generate → Finalize，多轮固定点）
  → 生成源码/静态元数据
  → 运行时只读 AnnotationRegistry
```

### 7.3 冻结的注解语义

- 目标 11 项：`Package/Type/Annotation/TypeParameter/Field/Method/Constructor/Deinit/Parameter/TypeUse/EnumItem`；
- 保留 3 项：`Source/Binary/Runtime`；
- `@Repeatable` 允许重复并保序；
- 参数只支持位置参数；尾部字段可省略；必须是编译期常量；
- 内建强制：`@ReadOnly`、`@Override`（使用即校验签名）、`@Deprecated`、`@SuppressWarnings`；
- 未知注解、错目标、重复、错参数、非法常量必须有稳定诊断码；
- 处理器必须显式启用，生成确定性、可重现、带来源标记；
- 处理器不得写任意文件、联网、反射、加载类、启动进程。

### 7.4 14 个元模型类型

`xdk.annotations` 只定义元模型、处理器合同和只读注册表：

- Value：`AnnotationValue`、`AnnotationInfo`、`AnnotationSet`；
- Protocol：`AnnotationProcessor`；
- Service/Processor：`AnnotationProcessorContext`、`AnnotationProcessingResult`；
- Registry：`AnnotationRegistry`；
- Element：`AnnotationElement`；
- Diagnostic：`AnnotationDiagnostic`、`AnnotationDiagnosticSeverity`；
- Enum：`AnnotationTarget`、`AnnotationRetention`、`AnnotationValueKind`、`AnnotationProcessorPhase`。

### 7.5 为什么先做

- `@Serializable`/`@Validate`/`@HttpRoute`/`@Sql`/`@JwtClaim` 都依赖生成；
- 没有注解，后续包只能手写重复代码，抽象会退化成宏/代码复制；
- 注解处理器是编译器能力，不是 XDK 运行时包；必须先落编译器，再落包。

> 实施计划见 [`ANNOTATION-PLAN.md`](ANNOTATION-PLAN.md)；权威语义见 [`ANNOTATION-SYSTEM.md`](ANNOTATION-SYSTEM.md)。

---

## 8. 1.x / 2.x 分层

| 项 | 1.x | 2.x |
| --- | --- | --- |
| 目录 | `docs/design/t0` | `docs/design/{annotations,core,network,platform,utils,solutions}` |
| 源码 | `src/xdk` 现有实现 | 新包/新签名 |
| 状态 | 已发布、已实现、已验收 | 设计基线，按阶段实现 |
| 兼容 | `release/1.0` + ABI v1 | 2.0 可破坏，但必须有迁移表/适配器 |
| 计数 | 14 包 / 160 symbols / 8 Verified | 75 包 / 698 类型 |
| 权威 | t0 + `src/xdk` + `api-manifest.tsv` | 本文件 + `PACKAGE-MAP.md` + 逐类型合同 |

规则：

- 1.x 已发布线不因 2.x 设计而回改；1.x 的 bug 修复走 1.x 分支。
- 2.x 不静默覆盖 1.x 同名公共符号；需要同名换义时，先在 `DESIGN-CONSISTENCY.md` 登记并给出迁移。
- 2.x 的新 core 必须先从 1.x 同步已实现能力，再加新类型；不得把已实现 API 从文档里删掉。
- 1.x 的 `t0` 文档保留为 release evidence，不参与 2.x 实现排序，不删除、不改写历史结论。

> 1.x 旧档清单与使用规则见 [`LEGACY-1.0.md`](LEGACY-1.0.md)。

---

## 9. 包地图摘要

| 层 | 包 | 类型 | 代表抽象 |
| --- | ---: | ---: | --- |
| L0 annotations | 1 | 14 | AnnotationProcessor / Registry |
| L1 runtime/execution | 2 | 25 | Context/Task/Executor/Channel |
| L2 core foundation | 7 | 80 | Error/Bytes/Text/Collections/Math/Time/Meta |
| L3 core system | 6 | 81 | Reader/File/Process/Logger/Config/CLI |
| L4 data/encoding | 12 | 76 | Codec/Crypto/Compress/Stats/Graph |
| L5 network/data | 9 | 125 | ByteStream/Http/Tls/SqlDriver/Service |
| L6 platform/compute | 17 | 93 | OsHost/GpuAdapter/Tensor/Serial |
| L7 application services | 12 | 82 | Cache/Queue/Metrics/Trace/Audit |
| L8 solutions | 9 | 122 | ApiServer/Db/Agent/Mcp/Ml |
| **合计** | **75** | **698** | |

完整包/类型/角色/阶段见 [`PACKAGE-MAP.md`](PACKAGE-MAP.md)。

---

## 10. 实施阶段

严格顺序；上一阶段出口不绿，不开下一阶段。

| 阶段 | 内容 | 出口 |
| --- | --- | --- |
| P0 架构冻结 | 本文件 + 包地图 + 一致性表 + 1.x/2.x 分层 + desktop 清理 + 计数/链接统一 | 架构签字；0 dangling；0 计数冲突 |
| P1 注解 | 语法/AST、目标/保留、常量、内建、诊断、元数据、处理器调度、14 类型 | 注解正/负例 + 生成场景绿 |
| P2 执行/core 前置 | `RuntimeMonitor`、`Context/Timer`、泛型 `Pair`、`isFinite`、`Bytes.alloc`、errors helpers、core 1.x 同步 | 1.x 回归绿；core 契约冻结 |
| P3 core 包 | `errors`…`cli` + `execution` 实现/补齐 | 每包场景 + 门禁 |
| P4 数据/编码 | `codec`、`random`/`uuid`、`stats`、`functional`、`graph`、`reflect`、`compress`/`crypto` 最小面、`toml`/`yaml`/`xml` | 依赖闭包绿；JSON/Base64 先行 |
| P5 网络/数据 | `net.uri`/`net.mime`、TCP/UDP/DNS、TLS、HTTP/1.1、WebSocket、JWT、SQL；HTTP/2 最后 | 端到端网络场景绿 |
| P6 平台/计算 | `os.*` 模型/只读面/控制器、`gpu`/`tensor`/`linalg`/`geo`/`serial`/`device` | 模型/只读/控制面分级绿 |
| P7 应用服务 | `validate`、`cache`、`queue`、`schedule`、`event`、`resilience`、`metrics`、`trace`、`audit`、`terminal`、`i18n`、`test` | 依赖闭包绿 |
| P8 solutions | `jsonrpc`、`mcp`、`numerics`、`db`、`api`、`agent`、`accel`、`embedded`、`ml` | 各组依赖闭合后逐组绿 |

顺序理由：

- 注解是编译器能力，必须先于所有“生成型”包；
- `RuntimeMonitor`、`Context`、`Pair`、`Json` 是跨包最大阻塞，先修它们；
- codec/crypto/compress 必须低于网络，否则 `net.http`/`net.tls` 会反向依赖；
- 网络必须先于平台/解决方案，因为 agent/api/mcp 都要真实传输；
- solutions 最后，因为它们组合前面所有层。

---

## 11. 架构决策（建议默认值）

以下决策需要在 P0 签字；未签字前，实现不得自行选择。

| # | 决策 | 建议 |
| --- | --- | --- |
| D1 | `Reader`/`Writer` | 2.x 用 protocol；具体 `ByteArrayReader/Writer`、`StringReader/Writer`；1.x class 保留适配器 |
| D2 | `Pair` | 2.x 泛型 `Pair<A,B>`；1.x 固定 `Pair` 标 deprecated，提供适配 |
| D3 | `Map.put` | `Bool`：替换 true、插入 false；`putIfAbsent` 返回旧值 `V?` |
| D4 | 执行层命名 | 2.x 只保留 `xdk.execution`；`xdk.tasks`/`xdk.sync` 仅 1.x 兼容 |
| D5 | `ConfigSource.load` | 带 `Context`；`Sink.write` 返回 `Result<Unit, Error>`；`Process.id` 用 `Long` |
| D6 | `API-SURFACE` | 不再手写；按逐类型合同生成，旧文件只作广度对照 |
| D7 | desktop/UI | 2.x 永久移除；不另立 3.x 讨论 |
| D8 | `net.service` | 归 L5 网络层；计数从 solutions 移到 network |
| D9 | `reflect` | 只读类型元数据；不提供动态调用/构造/注解查询；注解查询只走 `AnnotationRegistry` |
| D10 | 同名冲突 | 先改名；不能改名时始终包名限定，并在一致性表登记 |

---

## 12. 架构冻结验收

```text
ARCHITECTURE.md / PACKAGE-MAP.md / DESIGN-CONSISTENCY.md / LEGACY-1.0.md 存在且互相链接
75 包 / 698 类型计数一致
0 个 xdk.core.* / xdk.utils.* 包名引用
0 个 desktop/UI 服务引用（OsInfo.desktop 仅作为 OS 会话字符串保留）
0 个同名换义未登记
0 个 dangling 相对链接
1.x t0 25 个旧档完整保留
P1 注解实施的编译器工作项、诊断码、出口条件已冻结
```
