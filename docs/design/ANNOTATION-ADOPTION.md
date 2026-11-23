# XNull 注解采用矩阵

| 项 | 值 |
| --- | --- |
| 目的 | 把 XNull 注解系统落到 75 个包；注解是编译期契约/生成入口，不是装饰 |
| 权威 | [`solution-03-annotation.md`](../solution-03-annotation.md)（S3 1.0.0）；语法摘要 [`solution-02-object-programming.md`](../solution-02-object-programming.md) §12（S2 3.6.0）；[`ANNOTATION-CATALOG.md`](ANNOTATION-CATALOG.md)、[`PACKAGE-MAP.md`](PACKAGE-MAP.md) |
| 状态 | 编译器内建与 Registry 已实现；A8 `@Value`/`@Data`/`@Copy`/`@Builder`/`@Delegate` 已实现；领域处理器为 planned |
| 覆盖 | 75 包/组：1 annotations + 15 core + 9 network + 17 platform + 24 utils + 9 solutions |
| 规则 | 构建期处理；运行时只读静态 `AnnotationRegistry`；无反射/扫描/动态代理 |

---

## 0. 根因与修复

| 问题 | 证据 | 修复 |
| --- | --- | --- |
| 注解没有真正进入设计 | 早期类型文件几乎无 `@annotation`；75 个包 README 只有 2 个有注解清单 | 75 包 README 全部补“声明/消费/处理器/生成物/具体落点”；73 个领域注解有 `@annotation` 合同与使用示例 |
| 语言规范与注解设计冲突 | S2 §12.3 写元注解“识别但不强制”；§12.4 写“不支持处理器/运行期查询/代码生成” | S2 升到 3.6.0 并由 S3 1.0.0 接管完整语义：元注解强制、构建期处理器/生成、`Runtime` 静态 Registry；明确禁止反射/扫描 |
| 注解名与同包类型同名 | 早期 `@Command`/`HttpMethod`/`JwtHeader`/`SerialPort`/`Test`/`Retry`/`CircuitBreaker`/`Timeout`/`Receiver`/`Processor`/`WebSocketHandler`/`Model`/`AgentPipeline` 与类型冲突 | 改名为 `@CliCommand`、`@HttpRoute`（含 method 字段）、`@JwtHeaderField`、`@SerialBinding`、`@TestCase`、`@Retryable`、`@CircuitBreakerPolicy`、`@TimeoutPolicy`、`@AgentReceiver`、`@AgentProcessor`、`@WsHandler`、`@ModelSpec`、`@PipelineSpec`；碰撞检查 0 |
| 值类型没有体现 XNull 类型选择 | 早期文档 512 个 class、0 个 struct；部分纯值类型被写成 class | `Duration`/`Instant`/`Date`/`Time`/`DateTime`/`GeoPoint`/`GeoBounds` 改为合法 `struct`；含 `String`/`List` 的值类型继续 `class` + `@Value` |
| 类型合同没有注解证据 | 采用矩阵只写包级表，类型文件没有注解使用 | 11 个代表类型补“注解合同”并标注生成物；7 个纯值类型补 `struct` 类型选择；领域包 README 给出可编译形态的声明/使用示例 |

---

## 1. XNull 设计规则

### 1.1 注解声明

- 领域注解必须用 `@annotation` 声明，字段只允许 `final` 常量类型；必须有 `@Target`/`@Retention`。
- 注解名在同一包内不得与已有类型同名；本矩阵已避开 `Command`/`HttpMethod`/`JwtHeader`/`SerialPort`/`Test`/`Retry`/`CircuitBreaker`/`Timeout`/`Receiver`/`Processor`/`WebSocketHandler`/`Model`/`AgentPipeline` 等冲突。
- 需要运行期发现的注解用 `@Retention(Runtime)`；只生成代码的用 `Source`；只给编译器/工具读的 FFI 布局用 `Binary`。
- 注解本身不做运行时对象；参数在编译期求值；处理器失败不落半成品。
- 每个领域注解是一个 PascalCase 类型，按 XDK 目录规范单独成文件（如 `HttpRoute.x`/`HttpRoute.md`）；不得把多个注解塞进 `annotations.x` 大文件。
- 处理器是构建期类型，不计入运行时包类型数；生成源码放 `<package>/generated/<Name>Generated.x`，带 `generated` 标记，禁止手改。

### 1.2 类型选择

- 纯值且字段全是值类型（数值/Bool/枚举/其他合法 struct）→ `struct`。已落地：`Duration`、`Instant`、`Date`、`Time`、`DateTime`、`GeoPoint`、`GeoBounds`。
- 值语义但含 `String`/`List`/`Map` 等引用字段 → `class` + `@Value`；不要为了“像值”强行写非法 `struct`。`ErrorDetail`、`HttpHeader`、`SqlColumn`、`ValidationError` 等走这条路径。
- 需要身份/共享/生命周期 → `class`；需要可替换行为 → `protocol`；封闭分类 → `enum`。
- 选项/多字段构造 → `@Builder`；已有显式 `with*`/`build()` 的 builder（如 `OpenOptions`、`TlsConfig`、`ProcessBuilder`）不再叠加 `@Builder`。不可变更新 → `@Copy`；协议实现 → 使用 `@Override` 时强制匹配签名。
- 不使用 getter/setter 访问器模式；字段直接读写；校验/计算用动词方法或校验器注解。协议方法/只读查询（如 `kind()`）不是 property 访问器，按 1.x 合同保留；不要新增 `getX`/`setX` 命名。

### 1.3 生成与运行时

- 处理器显式启用，按 `Resolve → Validate → Generate → Finalize` 多轮固定点执行；生成源码带 `generated` 标记。
- 领域处理器只在构建期运行；运行时通过 `xdkAnnotationRegistry()` 读取 `Runtime` 注解，不加载注解类、不扫描类路径。
- `Source`/`Binary` 注解运行时不可查询；`Runtime` 注解由编译器发射静态表。
- 生成失败整批回滚；处理器不得联网、写任意文件、反射、启动进程。

### 1.4 状态口径

- `implemented`：编译器/XDK 已有实现与测试。
- `planned`：合同已写，处理器/生成物未实现；不得在包 README 或汇报中写成已生效。
- 本矩阵中除 `xdk.annotations` 的元模型和编译器内建外，领域注解均为 `planned`。

---

## 2. 75 包采用矩阵

> “具体落点”是设计与采用目标；只有明确标 `implemented` 的类型才是已落地。A8 能力已实现，但各包采用范围是 partial；领域注解均为 planned。

| # | 包 | 声明 | 消费 | 处理器 | 生成物 |
| ---: | --- | --- | --- | --- | --- |
| 1 | `xdk.annotations` | 无领域注解 | 无（本包定义元模型，不消费领域注解） | 无（处理器合同由构建期实现） | 14 类型、AnnotationRegistry 查询面、处理器上下文/结果合同 |
| 2 | `xdk.errors` | 无领域注解 | `@Value`、`@Copy`、`@Override`、`@Deprecated` | 标准 A8 / 编译器内建 | 派生相等/复制、协议签名校验、弃用诊断 |
| 3 | `xdk.runtime` | 无领域注解 | `@Value`、`@Copy`、`@Override` | 标准 A8 / 编译器内建 | 运行信息/健康快照的派生成员、协议签名校验 |
| 4 | `xdk.meta` | 无领域注解 | `@Value`、`@Data`、`@Builder`、`@Copy` | 标准 A8 | 能力/画像/构建信息派生成员、ProfileBuilder |
| 5 | `xdk.bytes` | 无领域注解 | `@Data`、`@Value`、`@Builder`、`@Copy` | 标准 A8 | 字节容器/构建器派生成员与复制 |
| 6 | `xdk.text` | 无领域注解 | `@Value`、`@Builder`、`@Copy`、`@Override` | 标准 A8 / 编译器内建 | 匹配/格式/正则选项派生成员 |
| 7 | `xdk.collections` | 无领域注解 | `@Data`、`@Value`、`@Builder`、`@Copy` | 标准 A8 | Pair/Triple/Entry 值语义、容器快照 |
| 8 | `xdk.math` | 无领域注解 | `@Value`、`@Builder`、`@Copy` | 标准 A8 | Decimal/Complex 值语义、构造/舍入选项 |
| 9 | `xdk.time` | 无领域注解 | `@Data`、`@Builder`、`@Copy` | 标准 A8 | Duration/Instant/Date/Time/DateTime 用合法 struct；格式化器用数据类/ builder |
| 10 | `xdk.io` | 无领域注解 | `@Override`、`@Deprecated` | 编译器内建 | 协议签名校验、1.x 迁移诊断；流是资源，不套 `@Value`/`@Data` |
| 11 | `xdk.fs` | 无领域注解 | `@Value`、`@Builder`、`@Override` | 标准 A8 / 编译器内建 | 路径/元数据/权限值语义、OpenOptions builder |
| 12 | `xdk.sys` | 无领域注解 | `@Value`、`@Copy`、`@Override` | 标准 A8 / 编译器内建 | 进程结果/系统信息值语义；ProcessBuilder 已是显式 builder，不重复生成 |
| 13 | `xdk.log` | 无领域注解 | `@Value`、`@Builder`、`@Override` | 标准 A8 / 编译器内建 | 日志记录值语义、Sink/Formatter/Filter 签名校验 |
| 14 | `xdk.config` | 无领域注解 | `@Value`、`@Data`、`@Builder`、`@Override` | 标准 A8 / 编译器内建 | 配置条目/字段值语义、Schema builder、ConfigSource 签名 |
| 15 | `xdk.cli` | `@CliCommand`、`@CliSubcommand`、`@Option`、`@Arg` | `@Value`、`@Builder`、`@Copy`、`@Deprecated` | CliAnnotationProcessor（Resolve/Validate/Generate） | 命令树、选项/参数表、帮助/补全元数据、解析器绑定 |
| 16 | `xdk.execution` | 无领域注解 | `@Value`、`@Override` | 标准 A8 / 编译器内建 | Context/Task 快照值语义、协议签名；原子/锁是状态资源，不套 `@Data` |
| 17 | `xdk.net` | 无领域注解 | `@Value`、`@Builder`、`@Override` | 标准 A8 / 编译器内建 | 地址/统计值语义、Socket/连接池选项 builder |
| 18 | `xdk.net.uri` | 无领域注解 | `@Value`、`@Copy` | 标准 A8 | Uri/Query 值语义与复制；解析构造保持显式 `parse`/构造器 |
| 19 | `xdk.net.mime` | 无领域注解 | `@Value` | 标准 A8 | MediaType 值语义；参数由显式构造/parse 提供 |
| 20 | `xdk.net.tls` | 无领域注解 | `@Value`、`@Builder`、`@Override` | 标准 A8 / 编译器内建 | 证书/会话值语义、TLS 配置 builder、handler 签名 |
| 21 | `xdk.net.http` | `@HttpRoute`、`@Header`、`@Query`、`@Body`、`@StatusCode` | `@Value`、`@Builder`、`@Serializable`、`@JsonName` | HttpAnnotationProcessor（Resolve/Validate/Generate） | 路由表、参数绑定、状态映射、body DTO codec |
| 22 | `xdk.net.websocket` | `@WsHandler` | `@Value`、`@Builder`、`@Override` | WebSocketAnnotationProcessor（Validate/Generate） | handler 注册、消息类型映射 |
| 23 | `xdk.jwt` | `@JwtClaim`、`@JwtHeaderField` | `@Value`、`@Builder`、`@Serializable`、`@JsonName` | JwtAnnotationProcessor（Validate/Generate） | claims/header 映射、序列化元数据 |
| 24 | `xdk.sql` | `@Sql`、`@Param`、`@Row`、`@Column` | `@Value`、`@Builder` | SqlAnnotationProcessor（Resolve/Validate/Generate） | DAO 方法、行 mapper、参数绑定、列映射 |
| 25 | `xdk.net.service` | 无领域注解 | `@Value`、`@Builder`、`@Override` | 标准 A8 / 编译器内建 | 服务选项/统计值语义、连接/会话 handler 签名 |
| 26 | `xdk.os` | 无领域注解 | `@Value`、`@Builder` | 标准 A8 | OS 信息/画像值语义与构造 |
| 27 | `xdk.os.host` | 无领域注解 | `@Override` | 编译器内建 | OsHost 实现签名；Os 是门面，不套派生注解 |
| 28 | `xdk.os.cpu` | 无领域注解 | `@Value` | 标准 A8 | CPU 拓扑/核心/缓存值语义；Affinity 是句柄 |
| 29 | `xdk.os.memory` | 无领域注解 | `@Value` | 标准 A8 | 内存/模组/NUMA 值语义 |
| 30 | `xdk.os.hardware` | `@Packed`、`@Align`、`@NativeLayout` | `@Value`、`@Builder`、`@Serializable` | HardwareLayoutProcessor（Validate/Generate） | FFI 布局/对齐校验、硬件清单序列化 |
| 31 | `xdk.os.storage` | 无领域注解 | `@Value` | 标准 A8 | 存储清单/设备/分区/SMART 值语义 |
| 32 | `xdk.os.gpu` | 无领域注解 | `@Value` | 标准 A8 | 适配器/设备/显存/队列值语义；GpuDevice/GpuQueue 若持原生句柄则按资源 class 处理 |
| 33 | `xdk.os.firewall` | 无领域注解 | `@Value`、`@Builder`、`@Audited` | 标准 A8 / 审计处理器 | 规则值语义、规则构造、变更审计 |
| 34 | `xdk.os.container` | 无领域注解 | `@Value`、`@Builder` | 标准 A8 | 命名空间/Cgroup/容器信息值语义 |
| 35 | `xdk.os.virt` | 无领域注解 | `@Value`、`@Builder` | 标准 A8 | Hypervisor/VM 值语义 |
| 36 | `xdk.os.service` | 无领域注解 | `@Value`、`@Builder` | 标准 A8 | 服务信息值语义 |
| 37 | `xdk.gpu` | `@GpuKernel` | `@Builder`、`@TensorOp` | GpuAnnotationProcessor（Validate/Generate） | kernel 注册、后端/队列校验；buffer/program/fence 是资源句柄，不套 `@Value` |
| 38 | `xdk.tensor` | `@TensorOp`、`@TensorSpec` | `@Value`、`@Builder`、`@LinalgOp` | TensorAnnotationProcessor（Validate/Generate） | 算子注册、shape/dtype 校验 |
| 39 | `xdk.linalg` | `@LinalgOp` | `@Value`、`@Builder` | LinalgAnnotationProcessor（Validate/Generate） | 算子注册、矩阵约束校验 |
| 40 | `xdk.geo` | 无领域注解 | `@Value`、`@Builder`、`@Copy` | 标准 A8 | GeoPoint/GeoBounds 用合法 struct；Path/Polygon 含列表，用 class + `@Value` |
| 41 | `xdk.serial` | `@SerialBinding` | `@Value`、`@Builder`、`@Packed`、`@Align` | SerialAnnotationProcessor（Validate/Generate） | 串口配置、端口信息、布局校验 |
| 42 | `xdk.device` | `@Device`、`@Gpio`、`@I2cAddress` | `@Value`、`@Builder`、`@Packed`、`@Align`、`@NativeLayout` | DeviceAnnotationProcessor（Validate/Generate） | 设备/引脚/地址目录、布局校验 |
| 43 | `xdk.codec` | `@Serializable`、`@JsonName`、`@CsvName` | `@Value`、`@Builder`、`@Copy` | CodecAnnotationProcessor（Resolve/Validate/Generate） | JSON/CSV 编解码器、字段名映射、静态元数据 |
| 44 | `xdk.crypto` | 无领域注解 | `@Value`、`@Deprecated` | 标准 A8 / 编译器内建 | `KeyPair` 值语义、弃用诊断；密钥句柄不套 `@Value` |
| 45 | `xdk.compress` | 无领域注解 | `@Value`、`@Builder`、`@Override` | 标准 A8 / 编译器内建 | 压缩条目/选项值语义、归档句柄签名 |
| 46 | `xdk.random` | 无领域注解 | `@Value`、`@Override` | 标准 A8 / 编译器内建 | 权重选择值语义、RandomSource 签名 |
| 47 | `xdk.uuid` | 无领域注解 | `@Value`、`@Builder` | 标准 A8 | Uuid/Ulid 值语义与构造 |
| 48 | `xdk.stats` | 无领域注解 | `@Value`、`@Builder` | 标准 A8 | 统计快照/直方图/回归值语义 |
| 49 | `xdk.functional` | 无领域注解 | `@Value` | 标准 A8 | 序列/惰性视图的值语义范围按实现确认；视图不强行 `@Value` |
| 50 | `xdk.graph` | 无领域注解 | `@Value`、`@Builder` | 标准 A8 | 图/边值语义 |
| 51 | `xdk.reflect` | 无领域注解 | `@Value`、`@Builder` | 标准 A8 | 只读类型/成员信息快照 |
| 52 | `xdk.toml` | `@TomlName` | `@Value`、`@Builder`、`@Serializable` | TomlAnnotationProcessor（Validate/Generate） | TOML 字段名映射、编解码元数据 |
| 53 | `xdk.yaml` | `@YamlName` | `@Value`、`@Builder`、`@Serializable` | YamlAnnotationProcessor（Validate/Generate） | YAML 字段名映射、文档元数据 |
| 54 | `xdk.xml` | `@XmlName` | `@Value`、`@Builder`、`@Serializable` | XmlAnnotationProcessor（Validate/Generate） | XML 元素/属性名映射、文档元数据 |
| 55 | `xdk.validate` | `@Validate`、`@Min`、`@Max`、`@Pattern`、`@Email` | `@Value`、`@Builder` | ValidateAnnotationProcessor（Validate/Generate） | 校验器、字段规则、错误路径 |
| 56 | `xdk.cache` | `@Cacheable`、`@CacheEvict` | `@Value`、`@Builder` | CacheAnnotationProcessor（Validate/Generate） | 缓存键/包装器、淘汰元数据 |
| 57 | `xdk.queue` | 无领域注解 | `@Value` | 标准 A8 | 队列统计值语义；队列本身是状态资源 |
| 58 | `xdk.schedule` | `@Scheduled` | `@Value`、`@Builder` | ScheduleAnnotationProcessor（Validate/Generate） | 作业注册、cron 元数据 |
| 59 | `xdk.event` | 无领域注解 | `@Value`、`@Override` | 标准 A8 / 编译器内建 | 事件值语义、订阅/总线签名 |
| 60 | `xdk.resilience` | `@Retryable`、`@CircuitBreakerPolicy`、`@RateLimit`、`@TimeoutPolicy` | `@Value`、`@Builder` | ResilienceAnnotationProcessor（Validate/Generate） | 重试/熔断/限流/超时包装器 |
| 61 | `xdk.metrics` | `@Metered` | `@Value`、`@Builder` | MetricsAnnotationProcessor（Validate/Generate） | 指标注册/包装器 |
| 62 | `xdk.trace` | `@Traced` | `@Value`、`@Builder` | TraceAnnotationProcessor（Validate/Generate） | span/包装器元数据 |
| 63 | `xdk.audit` | `@Audited` | `@Value`、`@Builder` | AuditAnnotationProcessor（Validate/Generate） | 审计包装器/脱敏元数据 |
| 64 | `xdk.terminal` | 无领域注解 | `@Value` | 标准 A8 | 颜色/样式值语义；提示/表格是服务 |
| 65 | `xdk.i18n` | 无领域注解 | `@Value`、`@Builder` | 标准 A8 | Locale/目录/格式化值语义 |
| 66 | `xdk.test` | `@TestCase`、`@Before`、`@After`、`@Benchmark` | `@Value`、`@Builder` | TestAnnotationProcessor（Validate/Generate） | 测试清单、生命周期/基准元数据 |
| 67 | `xdk.jsonrpc` | 无领域注解 | `@Value`、`@Builder` | 标准 A8 | JSON-RPC 请求/响应/错误值语义 |
| 68 | `xdk.mcp` | `@Tool`、`@ToolParam`、`@Resource`、`@Prompt` | `@Value`、`@Builder`、`@Serializable` | McpAnnotationProcessor（Validate/Generate） | 工具/资源/prompt 清单、输入 schema |
| 69 | `xdk.ml` | `@ModelSpec`、`@MlPipeline` | `@Value`、`@Builder`、`@TensorSpec` | MlAnnotationProcessor（Validate/Generate） | 模型/流水线目录、输入输出 spec |
| 70 | `xdk.numerics` | 无领域注解 | `@Value`、`@Builder`、`@Copy` | 标准 A8 | 大数/多项式/信号值语义 |
| 71 | `xdk.db` | `@Entity`、`@Table`、`@Id`、`@Transactional` | `@Value`、`@Builder`、`@Sql`、`@Column`、`@Param`、`@Row` | db_processor（Generate） | 实体/表/列/DAO 映射、事务包装（内存驱动） |
| 72 | `xdk.api` | `@Api`、`@Operation`、`@Middleware`、`@Inject`、`@Component`、`@Configuration`、`@Bean` | `@Value`、`@Builder`、`@HttpRoute`、`@Header`、`@Query`、`@Body`、`@StatusCode` | ApiAnnotationProcessor（Resolve/Validate/Generate） | 路由表、OpenAPI、参数绑定、装配元数据 |
| 73 | `xdk.agent` | `@AgentReceiver`、`@AgentProcessor`、`@AgentExporter`、`@PipelineSpec` | `@Value`、`@Builder`、`@Metered`、`@Traced` | AgentAnnotationProcessor（Validate/Generate） | 管线/组件注册、观测元数据 |
| 74 | `xdk.accel` | 无领域注解 | `@Builder`、`@GpuKernel`、`@TensorOp` | 无自有处理器；消费 GPU/Tensor 生成物 | 设备/程序/队列是句柄/服务；kernel 入口复用 GPU/Tensor 处理器 |
| 75 | `xdk.embedded` | 无领域注解 | `@Builder`、`@Device`、`@Gpio`、`@I2cAddress`、`@SerialBinding`、`@Packed`、`@Align` | 无自有处理器；消费 Device/Serial/FFI 生成物 | 板级/引脚描述、设备目录、布局校验；设备句柄不套 `@Value` |

> 计数：1 个 annotations 包 + 74 个领域/基础包 = 75 包/组。

---

## 3. 逐包落点

### `xdk.annotations`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `AnnotationRegistry`/`AnnotationSet` | — | 静态注册表只读查询 |
| `AnnotationProcessor` | — | 构建期处理器合同 |
| `AnnotationElement` | — | 处理器只读元素视图 |

状态：已实现（B1/B2）。

### `xdk.errors`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `ErrorDetail` | `@Value` implemented (A8 core) | equals/toString/copy |
| `BasicError` | `@Value`/`@Copy` planned | 未采用 |
| `Error`/`DetailedError` 实现 | `@Override` | 签名校验 |

状态：无领域注解；`@Value` implemented（ErrorDetail）；其余类型未采用 A8；编译器内建 implemented。

### `xdk.runtime`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `RuntimeInfo`/`RuntimeStats` | `@Value` implemented (A8 core) | equals/toString/copy |
| `MemoryStats`/`TaskStats`/`TaskSnapshot` | `@Value` planned | 未采用 |
| `HealthReport` | `@Value` | 快照相等/文本 |
| `HealthCheck` 实现 | `@Override` | 签名校验 |

状态：无领域注解；`@Value`/`@Builder` implemented（RuntimeInfo；RuntimeStats 仅 @Value）；其余类型未采用 A8；编译器内建 implemented。

### `xdk.meta`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `BuildInfo` | `@Value` implemented (A8 core) | equals/toString/copy |
| `CapabilitySet`/`CoreProfile`/`TargetInfo`/`DependencyInfo` | `@Value` planned | 未采用 |
| `ResourceLimits` | `@Data` | 数据类成员 |
| `ProfileBuilder` | — | 已是显式 builder，不叠加 `@Builder` |

状态：无领域注解；`@Value`/`@Builder` implemented（BuildInfo）；其余类型未采用 A8；编译器内建 implemented。

### `xdk.bytes`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Bytes`/`BytesBuilder`/`BitSet` | `@Data` | 数据类成员/复制 |
| `ByteOrder` | — | enum，无派生 |
| `ByteBuffer` | `@Builder` | 选项构造 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.text`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Match`/`Format` | `@Value` | 值语义成员 |
| `RegexOptions` | `@Builder` | 选项构造 |
| `Regex`/`Unicode` 等入口 | — | 静态/实例方法，不强行套派生 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.collections`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Pair`/`IntPair`/`Entry` | `@Data`/`@Copy` implemented (A8 core) | equals/toString/copy + withX |
| `Triple` | `@Data` planned | 未采用 |
| `IntRange` | `@Value` | 值语义成员 |
| `LRUCache` 等容器 | — | 可变容器不套 `@Value` |

状态：无领域注解；`@Data`/`@Copy` implemented（Pair/IntPair/Entry）；其余类型未采用 A8；编译器内建 implemented。

### `xdk.math`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Decimal`/`Complex` | `@Value` | 值语义成员 |
| `RoundingMode` | — | enum |
| `Decimal` 构造选项 | `@Builder` | builder/build 校验 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.time`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Duration`/`Instant`/`Date`/`Time`/`DateTime` | `struct` | 原生值语义；无需 `@Value` |
| `TimeZone`/`DateTimeFormatter`/`DateTimeParser` | `@Data`/`@Builder` | 配置快照/构造 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.io`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Reader`/`Writer`/`Seekable`/`Closer` 实现 | `@Override` | 签名校验 |
| 1.x 适配入口 | `@Deprecated` | 迁移警告 |
| `BufferedReader`/`ByteArrayReader` 等 | — | 资源/组合器，保持显式 class |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.fs`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Path`/`Metadata`/`Permissions`/`DirEntry` | `@Value` | 值语义成员 |
| `OpenOptions` | — | 已是显式 with* builder，不叠加 `@Builder` |
| `FileSystem` 实现 | `@Override` | 签名校验 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.sys`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `ProcessResult`/`SystemInfo`/`Env`/`Platform` | `@Value` | 值语义成员 |
| `ProcessBuilder` | — | 已是显式 builder，不叠加 `@Builder` |
| `Process`/`Resource` | `@Override` | close 协议签名 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.log`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Field` | `@Value` implemented (A8 core) | equals/toString/copy |
| `LogRecord`/`TextFormatter` | `@Value` planned | 未采用 |
| `LogRecord` 构造 | `@Builder` | 多字段构造 |
| `Sink`/`Formatter`/`Filter`/`Redactor`/`Sampler` 实现 | `@Override` | 签名校验 |

状态：无领域注解；`@Value` implemented（Field）；其余类型未采用 A8；编译器内建 implemented。

### `xdk.config`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `ConfigEntry` | `@Value` implemented (A8 core) | equals/toString/copy |
| `ConfigField` | `@Value` planned | 未采用 |
| `Config` | `@Data` | 可变配置快照 |
| `ConfigSchema` | `@Builder` | schema 构造 |
| `ConfigSource` 实现 | `@Override` | 签名校验 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.cli`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 命令类 | `@CliCommand` | 命令树/帮助元数据 |
| 子命令类 | `@CliSubcommand` | 子命令表 |
| 命令字段/参数 | `@Option`/`@Arg` | 解析表/默认值/必填校验 |
| `Command`/`ParseResult` | `@Value` | 值语义/复制 |
| `OptionSpec` | — | 已是显式 builder，不叠加 `@Builder` |

状态：`@CliCommand`/`@CliSubcommand`/`@Option`/`@Arg` 为 `implemented (M2 pilot)`：生成 `CliGenerated.x` 命令树/选项表/help/positional help。方法执行器与 positionals 执行未做（M2.2 planned）。

声明：

```x
@Target(Type)
@Retention(Runtime)
@annotation CliCommand {
    final String name
    final String summary = ""
}

@Target(Type)
@Retention(Runtime)
@annotation CliSubcommand {
    final String name
}

@Target(Field, Parameter)
@Retention(Runtime)
@annotation Option {
    final String name
    final String shortName = ""
    final Bool required = false
}

@Target(Field, Parameter)
@Retention(Runtime)
@annotation Arg {
    final String name
    final Bool required = true
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@CliCommand("deploy", "Deploy an artifact")
class DeployCommand {
    @Option("--env", "-e") String env = "dev"
    @Arg("artifact") String artifact
}

@CliSubcommand("status")
class StatusCommand {
    @Option("--json") Bool json = false
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.execution`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Context`/`TaskSnapshot` | `@Value` | 值语义成员 |
| `AtomicInt`/`AtomicBool`/`AtomicRef`/`Mutex`/`RwLock` | — | 状态资源，保持显式 class |
| `TaskHandle` 实现 | `@Override` | 签名校验 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.net`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `IpAddress`/`IpPrefix`/`SocketAddress`/`DnsRecord`/`PoolKey` | `@Value` | 值语义成员 |
| `SocketOptions`/`MulticastOptions`/`TcpServerOptions`/`ConnectionPoolOptions` | `@Builder` | 选项构造 |
| `ByteStream`/`TcpHandler` 实现 | `@Override` | 签名校验 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.net.uri`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Uri`/`Query` | `@Value` | equals/toString/copy |
| `Uri.parse`/`Query.parse` | — | 显式解析入口，不叠加 builder |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.net.mime`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `MediaType` | `@Value` | 值语义成员 |
| `MimeTypes` | — | 常量入口，不套派生 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.net.tls`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Certificate`/`TlsPrivateKey`/`TrustStore`/`TlsSessionInfo` | `@Value` | 值语义成员 |
| `TlsConfig` | — | 已是显式 with* builder，不叠加 `@Builder` |
| `TlsHandler` 实现 | `@Override` | 签名校验 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.net.http`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `HttpHeader`/`HttpStatus` | `@Value` | 值语义成员 |
| `HttpRequest`/`HttpResponse` | — | 含 headers/body 引用字段；不强行 `@Value`，保留显式构造/with* |
| `HttpClientOptions`/`HttpServerOptions` | `@Builder` | 选项构造 |
| handler 方法 | `@HttpRoute` | 路由表/方法绑定 |
| handler 参数 | `@Header`/`@Query`/`@Body` | 参数绑定 |
| handler 方法 | `@StatusCode` | 响应状态 |
| body DTO | `@Serializable`/`@JsonName` | JSON 编解码 |

声明：

```x
@Target(Method)
@Retention(Source)
@annotation HttpRoute {
    final String path
    final HttpMethod method = HttpMethod.Get
}

@Target(Parameter)
@Retention(Source)
@annotation Header {
    final String value
}

@Target(Parameter)
@Retention(Source)
@annotation Query {
    final String value
}

@Target(Parameter)
@Retention(Source)
@annotation Body {
}

@Target(Method)
@Retention(Source)
@annotation StatusCode {
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class UserApi {
    @HttpRoute("/users/{id}", HttpMethod.Get)
    @StatusCode
    HttpResponse getUser(@Query("id") Long id, @Header("Accept") String accept) {
        // ...
    }

    @HttpRoute("/users", HttpMethod.Post)
    HttpResponse create(@Body UserDto body) {
        // ...
    }
}
```

状态：`@HttpRoute`/`@Header`/`@Query`/`@Body` implemented (M5.2)：生成 `<Class>Router`，支持方法/路径模板、query/header/body 绑定、404/405/400；`@StatusCode` planned；client/server/HTTP2/proxy/streaming 见 M5.3 planned。

### `xdk.net.websocket`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| handler 类 | `@WsHandler` | handler 表 |
| `WebSocketMessage`/`WebSocketOptions`/`WebSocketStats` | `@Value`/`@Builder` | 值语义/选项 |
| `WebSocketHandler` 实现 | `@Override` | 签名校验 |

声明：

```x
@Target(Type)
@Retention(Source)
@annotation WsHandler {
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@WsHandler
class ChatHandler {
    Result<Unit, Error> onMessage(WebSocketMessage message) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.jwt`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| claims 类 | `@JwtClaim` | claim 字段映射 |
| header 类 | `@JwtHeaderField` | header 字段映射 |
| `JwtClaims`/`JwtHeader`/`JwtToken`/`JwtOptions` | `@Value`/`@Builder` | 值语义/选项 |
| claims/header DTO | `@Serializable`/`@JsonName` | JSON 编解码 |

声明：

```x
@Target(Field)
@Retention(Source)
@annotation JwtClaim {
    final String value
}

@Target(Field)
@Retention(Source)
@annotation JwtHeaderField {
    final String value
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Serializable
class AccessClaims {
    @JwtClaim("sub") String subject
    @JwtClaim("exp") Long expiresAt
}

@Serializable
class JwtHeaderFields {
    @JwtHeaderField("alg") String algorithm
    @JwtHeaderField("kid") String keyId
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.sql`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| DAO 方法 | `@Sql` | SQL 文本/返回映射 |
| DAO 参数 | `@Param` | 命名参数绑定 |
| 行类型 | `@Row` | 行 mapper |
| 行字段 | `@Column` | 列映射 |
| `SqlColumn` | `@Value` | 列元数据值语义 |
| `SqlValue`/`SqlRow`/`SqlStatement`/`SqlResult` | — | 含 tagged value/List 字段；按字段可值比较性再决定，不强行全量 `@Value` |

声明：

```x
@Target(Method)
@Retention(Source)
@annotation Sql {
    final String value
}

@Target(Parameter)
@Retention(Source)
@annotation Param {
    final String value
}

@Target(Type)
@Retention(Source)
@annotation Row {
}

@Target(Field)
@Retention(Source)
@annotation Column {
    final String value
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Row
class UserRow {
    @Column("user_id") final Long id
    @Column("display_name") final String name
}

class UserDao {
    @Sql("SELECT user_id, display_name FROM users WHERE user_id = :id")
    Result<UserRow, Error> find(@Param("id") Long recordId) {
        // ...
    }
}
```

状态：`@Sql`/`@Param`/`@Row`/`@Column` implemented (M6.2)：生成 `SqlStatement`/DAO 执行函数/`FromRow`，以内存驱动闭环；无真实数据库。注解文件 `@Sql` 因实现文件同名放在 `SqlAnnotation.x`。

### `xdk.net.service`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `ServiceOptions`/`ServiceStats`/`BackpressurePolicy`/`HeartbeatPolicy` | `@Value`/`@Builder` | 值语义/选项 |
| `ConnectionHandler`/`SessionHandler` 实现 | `@Override` | 签名校验 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `OsInfo`/`OsProfile` | `@Value` | 值语义成员 |
| `OsProfile` 构造 | `@Builder` | 多字段构造 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os.host`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `OsHost` 实现 | `@Override` | 签名校验 |
| `Os` 门面 | — | 门面/装配，保持显式 class |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os.cpu`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `CpuTopology`/`CpuCore`/`CpuCache` | `@Value` | 值语义成员 |
| `CpuAffinity` | — | 资源/句柄，保持显式 class |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os.memory`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `PhysicalMemory`/`MemoryModule`/`NumaNode` | `@Value` | 值语义成员 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os.hardware`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 原生布局类型 | `@Packed`/`@Align`/`@NativeLayout` | 布局/对齐校验 |
| `HardwareInventory`/`BoardInfo`/`BiosInfo`/`PciDevice`/`UsbDevice`/`SensorReading` | `@Value`/`@Builder` | 值语义/构造 |

声明：

```x
@Target(Type, Field)
@Retention(Binary)
@annotation Packed {
}

@Target(Type, Field)
@Retention(Binary)
@annotation Align {
    final Int value
}

@Target(Type)
@Retention(Binary)
@annotation NativeLayout {
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Packed
@Align(8)
@NativeLayout
class CHeader {
    @Align(4) Int code
    Long payload
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os.storage`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `StorageInventory`/`StorageDevice`/`Partition`/`SmartInfo` | `@Value` | 值语义成员 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os.gpu`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `GpuAdapter`/`GpuMemoryInfo` | `@Value` | 值语义成员 |
| `GpuDevice`/`GpuQueue` | — | 若持原生句柄，保持资源 class |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os.firewall`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `FirewallRule`/`FirewallStatus` | `@Value`/`@Builder` | 值语义/构造 |
| `FirewallController` 变更方法 | `@Audited` | 审计事件 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os.container`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Namespace`/`Cgroup`/`ContainerInfo` | `@Value` | 值语义成员 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os.virt`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Hypervisor`/`VirtualMachine` | `@Value` | 值语义成员 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.os.service`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `ServiceInfo` | `@Value` | 值语义成员 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.gpu`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| kernel 方法 | `@GpuKernel` | kernel 注册 |
| `GpuPipeline` 描述/选项 | `@Builder` | pipeline 构造 |
| `GpuBuffer`/`GpuProgram`/`GpuFence` | — | 资源句柄，保持显式 class/close |

声明：

```x
@Target(Method)
@Retention(Runtime)
@annotation GpuKernel {
    final String name
    final String backend = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class Kernels {
    @GpuKernel("vector_add", "spirv")
    void vectorAdd(GpuBuffer out, GpuBuffer left, GpuBuffer right) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.tensor`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 算子方法 | `@TensorOp` | 算子注册 |
| 张量参数/字段 | `@TensorSpec` | shape/dtype 校验 |
| `TensorShape` | `@Value` | shape 值语义 |
| `Tensor`/`TensorView` | — | 持有数据/视图，保持显式 class |

声明：

```x
@Target(Method)
@Retention(Runtime)
@annotation TensorOp {
    final String name
}

@Target(Field, Parameter)
@Retention(Runtime)
@annotation TensorSpec {
    final String shape
    final String dtype
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class TensorKernels {
    @TensorOp("matmul")
    Tensor matmul(@TensorSpec("M,K", "f32") Tensor left,
                  @TensorSpec("K,N", "f32") Tensor right) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.linalg`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 算子方法 | `@LinalgOp` | 算子注册 |
| `Vector`/`Matrix`/`LuDecomposition`/`QrDecomposition`/`Svd`/`EigenDecomposition` | `@Value`/`@Builder` | 值语义/构造 |

声明：

```x
@Target(Method)
@Retention(Runtime)
@annotation LinalgOp {
    final String name
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class LinalgKernels {
    @LinalgOp("solve")
    Vector solve(Matrix matrix, Vector rhs) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.geo`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `GeoPoint`/`GeoBounds` | `struct` | 原生值语义；无需 `@Value` |
| `GeoPath`/`GeoPolygon` | `@Value`/`@Builder` | 值语义/构造 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.serial`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 端口配置字段/参数 | `@SerialBinding` | 端口绑定 |
| `SerialOptions`/`SerialPortInfo` | `@Value`/`@Builder` | 值语义/选项 |

声明：

```x
@Target(Field, Parameter)
@Retention(Source)
@annotation SerialBinding {
    final String path
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class ConsoleConfig {
    @SerialBinding("/dev/ttyUSB0") String port
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.device`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 板级/设备类 | `@Device` | 设备目录 |
| 引脚字段/参数 | `@Gpio` | 引脚目录 |
| I2C 字段/参数 | `@I2cAddress` | 地址目录 |
| `CameraFrame` | `@Value` | 不可变帧快照 |
| `GpioPin`/`I2cBus`/`SpiBus`/`CameraDevice` | — | 资源句柄，保持显式 class/close |

声明：

```x
@Target(Type)
@Retention(Runtime)
@annotation Device {
    final String kind
}

@Target(Field, Parameter)
@Retention(Runtime)
@annotation Gpio {
    final Int pin
    final GpioDirection direction = GpioDirection.In
}

@Target(Field, Parameter)
@Retention(Runtime)
@annotation I2cAddress {
    final Int address
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Device("board")
class Board {
    @Gpio(17, GpioDirection.Out) Int statusLed
    @I2cAddress(0x3C) Int display
}
```

状态：`@Serializable`/`@JsonName` implemented (M3.2)，`@CsvName` implemented (M3.3)：生成 JSON 与 CSV 编解码；CSV 支持 String/Int/Long/Double/Bool，其他字段 AN1605 warning 跳过；`List<T>` JSON planned；无反射。

### `xdk.codec`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| DTO 类型 | `@Serializable` | 编解码器 |
| DTO 字段 | `@JsonName`/`@CsvName` | 字段名映射 |
| `JsonValue`/`JsonNumber`/`JsonOptions`/`CsvOptions` | `@Value`/`@Builder` | 值语义/选项 |

声明：

```x
@Target(Type)
@Retention(Source)
@annotation Serializable {
}

@Target(Field)
@Retention(Source)
@annotation JsonName {
    final String value
}

@Target(Field)
@Retention(Source)
@annotation CsvName {
    final String value
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Serializable
class UserDto {
    @JsonName("user_id") final Long id
    @JsonName("display_name") final String name
}
```

状态：`@Serializable`/`@JsonName` implemented (M3.2)，`@CsvName` implemented (M3.3)：生成 JSON 与 CSV 编解码；CSV 支持 String/Int/Long/Double/Bool，其他字段 AN1605 warning 跳过；`List<T>` JSON planned；无反射。

### `xdk.crypto`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `KeyPair` | `@Value` | 值语义成员 |
| `PublicKey`/`PrivateKey` | — | 句柄/权限资源，保持显式 class |
| 废弃算法入口 | `@Deprecated` | 迁移警告 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.compress`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `ZipEntry`/`TarEntry` | `@Value` | 值语义成员 |
| `ZipOptions` | `@Builder` | 选项构造 |
| `ZipArchive`/`ZipWriter` | `@Override` | 关闭/写入签名 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.random`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `WeightedChoice` | `@Value` | 值语义成员 |
| `RandomSource` 实现 | `@Override` | 签名校验 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.uuid`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Uuid`/`Ulid` | `@Value` | equals/toString/copy |
| `Uuid` 构造 | `@Builder` | 版本/变体构造 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.stats`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `HistogramBucket`/`BucketHistogram`/`Summary`/`RunningStats`/`Regression`/`MovingAverage`/`Ema` | `@Value` | 值语义成员 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.functional`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Seq`/`Sequences` | `@Value` | 值语义成员（若不可变） |
| `Lazy` | — | 惰性视图，保持显式 class |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.graph`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Graph`/`GraphEdge` | `@Value` | 值语义成员 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.reflect`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `TypeInfo`/`MemberInfo` | `@Value` | 只读快照 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.toml`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| DTO 字段 | `@TomlName` | 字段名映射 |
| `Toml`/`TomlOptions` | `@Builder` | 选项构造 |

声明：

```x
@Target(Field)
@Retention(Source)
@annotation TomlName {
    final String value
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Serializable
class ServiceConfig {
    @TomlName("service_name") String name
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.yaml`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| DTO 字段 | `@YamlName` | 字段名映射 |
| `YamlDocument`/`YamlOptions`/`YamlPropertySource` | `@Value`/`@Builder` | 值语义/选项 |

声明：

```x
@Target(Field)
@Retention(Source)
@annotation YamlName {
    final String value
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Serializable
class ServiceConfig {
    @YamlName("service_name") String name
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.xml`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| DTO 字段 | `@XmlName` | 元素/属性名映射 |
| `XmlElement`/`XmlOptions` | `@Value`/`@Builder` | 值语义/选项 |

声明：

```x
@Target(Field)
@Retention(Source)
@annotation XmlName {
    final String value
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Serializable
class ServiceConfig {
    @XmlName("serviceName") String name
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.validate`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 表单/请求类型 | `@Validate` | 校验入口 |
| 数值字段/参数 | `@Min`/`@Max` | 范围规则 |
| 字符串字段/参数 | `@Pattern`/`@Email` | 格式规则 |
| `ValidationError`/`ValidationResult`/`FieldRule` | `@Value`/`@Builder` | 值语义/规则构造 |

声明：

```x
@Target(Type)
@Retention(Source)
@annotation Validate {
}

@Target(Field)
@Retention(Source)
@annotation Min {
    final Long value
}

@Target(Field)
@Retention(Source)
@annotation Max {
    final Long value
}

@Target(Field)
@Retention(Source)
@annotation Pattern {
    final String value
}

@Target(Field, Parameter)
@Retention(Source)
@annotation Email {
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Validate
class SignupForm {
    @Email String email
    @Min(18) @Max(120) Int age
    @Pattern("^[a-z0-9_]+$") String handle
}
```

状态：`@Validate`/`@Min`/`@Max`/`@Pattern`/`@Email` implemented (M4.2/M4.3)：生成 `<Type>Schema()`/`<Type>Validate(JsonValue)`，覆盖标量与可空 String；`@Email` 追加 `Rules.email()`，仅 String/String? 生效；List、嵌套类型、可空数值由 AN1205 warning 跳过，非 String 的 `@Email` 由 AN1207 warning 跳过规则。

### `xdk.cache`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 服务方法 | `@Cacheable`/`@CacheEvict` | 缓存/淘汰包装 |
| `CacheOptions`/`CacheStats` | `@Value`/`@Builder` | 值语义/选项 |

声明：

```x
@Target(Method)
@Retention(Source)
@annotation Cacheable {
    final String value
    final String key = ""
}

@Target(Method)
@Retention(Source)
@annotation CacheEvict {
    final String value
    final String key = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class UserService {
    @Cacheable("users", "id")
    User find(Long id) {
        // ...
    }

    @CacheEvict("users", "id")
    void update(Long recordId, User user) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.queue`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `QueueStats` | `@Value` | 值语义成员 |
| `BoundedQueue`/`BatchQueue`/`DelayQueue` | — | 状态资源，保持显式 class/close |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.schedule`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 作业方法 | `@Scheduled` | 作业注册 |
| `CronExpression`/`Schedule`/`SchedulerOptions` | `@Value`/`@Builder` | 值语义/选项 |

声明：

```x
@Target(Method)
@Retention(Runtime)
@annotation Scheduled {
    final String cron = ""
    final Long fixedRateMillis = 0
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class Jobs {
    @Scheduled("0 */5 * * * *")
    void refreshCache() {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.event`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Event` | `@Value` | 值语义成员 |
| `EventSubscription`/`EventBus` | `@Override` | 订阅/关闭签名；不套 builder |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.resilience`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 服务方法 | `@Retryable`/`@CircuitBreakerPolicy`/`@RateLimit`/`@TimeoutPolicy` | 策略包装 |
| `Retry`/`CircuitBreaker`/`RateLimiter`/`Timeout` | `@Value`/`@Builder` | 值语义/策略构造 |

声明：

```x
@Target(Method)
@Retention(Source)
@annotation Retryable {
    final Int maxAttempts = 3
    final Long initialDelayMillis = 100
}

@Target(Method)
@Retention(Source)
@annotation CircuitBreakerPolicy {
    final String name
    final Int failureThreshold = 5
}

@Target(Method)
@Retention(Source)
@annotation RateLimit {
    final String name
    final Int permits
    final Long perMillis
}

@Target(Method)
@Retention(Source)
@annotation TimeoutPolicy {
    final Long timeoutMillis
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class UserService {
    @Retryable(3, 100)
    @CircuitBreakerPolicy("users", 5)
    @TimeoutPolicy(2000)
    User find(Long id) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.metrics`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 服务方法 | `@Metered` | 指标包装 |
| `MetricSample`/`MetricFamily`/`Histogram` | `@Value`/`@Builder` | 值语义/构造 |

声明：

```x
@Target(Method)
@Retention(Source)
@annotation Metered {
    final String name
    final String unitName = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class UserService {
    @Metered("user.find", "requests")
    User find(Long id) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.trace`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 服务方法 | `@Traced` | span 包装 |
| `SpanContext`/`SpanEvent`/`TraceOptions` | `@Value`/`@Builder` | 值语义/选项 |

声明：

```x
@Target(Method)
@Retention(Source)
@annotation Traced {
    final String name
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class UserService {
    @Traced("user.find")
    User find(Long id) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.audit`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 敏感方法 | `@Audited` | 审计事件 |
| `AuditEvent` | `@Value`/`@Builder` | 值语义/构造 |

声明：

```x
@Target(Method)
@Retention(Source)
@annotation Audited {
    final String action
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class UserService {
    @Audited("user.delete")
    void delete(Long recordId) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.terminal`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Color`/`Style` | `@Value` | 值语义成员 |
| `ProgressBar`/`Table`/`Prompt` | — | 服务/呈现，保持显式 class |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.i18n`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Locale`/`MessageCatalog`/`PluralRules`/`NumberFormat`/`DateFormat` | `@Value` | 值语义成员 |
| `MessageCatalog` 构造 | `@Builder` | 目录构造 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.test`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 测试方法 | `@TestCase` | 测试清单 |
| 前置/后置方法 | `@Before`/`@After` | 生命周期表 |
| 基准方法 | `@Benchmark` | 基准清单 |
| `TestResult`/`TestContext` | `@Value`/`@Builder` | 值语义/上下文 |

声明：

```x
@Target(Method)
@Retention(Runtime)
@annotation TestCase {
    final String name = ""
}

@Target(Method)
@Retention(Runtime)
@annotation Before {
}

@Target(Method)
@Retention(Runtime)
@annotation After {
}

@Target(Method)
@Retention(Runtime)
@annotation Benchmark {
    final String name = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class UserTests {
    @Before void setUp() {
        // ...
    }

    @TestCase("find missing")
    void findMissing() {
        // ...
    }

    @After void tearDown() {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.jsonrpc`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `JsonRpcRequest`/`JsonRpcResponse`/`JsonRpcError` | `@Value`/`@Builder` | 值语义/构造 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.mcp`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 工具方法 | `@Tool` | 工具清单 |
| 工具参数 | `@ToolParam` | 输入 schema |
| 资源方法 | `@Resource` | 资源清单 |
| prompt 方法 | `@Prompt` | prompt 清单 |
| MCP DTO | `@Value`/`@Builder`/`@Serializable` | 值语义/schema |

声明：

```x
@Target(Method)
@Retention(Runtime)
@annotation Tool {
    final String name
    final String description
}

@Target(Parameter)
@Retention(Runtime)
@annotation ToolParam {
    final String name
    final String description = ""
    final Bool required = true
}

@Target(Method)
@Retention(Runtime)
@annotation Resource {
    final String uri
    final String mimeType
}

@Target(Method)
@Retention(Runtime)
@annotation Prompt {
    final String name
    final String description = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
class WeatherTools {
    @Tool("weather.current", "Get current weather")
    Result<WeatherReport, Error> current(@ToolParam("city") String city) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.ml`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 模型类 | `@ModelSpec` | 模型目录 |
| 流水线类 | `@MlPipeline` | 流水线目录 |
| 输入/输出字段 | `@TensorSpec` | shape/dtype 校验 |

声明：

```x
@Target(Type)
@Retention(Runtime)
@annotation ModelSpec {
    final String name
}

@Target(Type)
@Retention(Runtime)
@annotation MlPipeline {
    final String name
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@ModelSpec("sentiment")
class SentimentModel {
    // ...
}

@MlPipeline("batch-infer")
class BatchInference {
    // ...
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.numerics`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `BigInt`/`BigFloat`/`Polynomial`/`SignalBuffer` | `@Value`/`@Builder` | 值语义/构造 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.db`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 实体类 | `@Entity`/`@Table` | 实体/表元数据 |
| 主键字段 | `@Id` | 主键元数据 |
| 事务方法 | `@Transactional` | 事务包装 |
| DAO 方法/参数/行 | `@Sql`/`@Param`/`@Row`/`@Column` | SQL 映射 |

声明：

```x
@Target(Type)
@Retention(Source)
@annotation Entity {
    final String table
}

@Target(Type)
@Retention(Source)
@annotation Table {
    final String name
}

@Target(Field)
@Retention(Source)
@annotation Id {
}

@Target(Method)
@Retention(Source)
@annotation Transactional {
    final Bool readOnly = false
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Entity("users")
class User {
    @Id Long id
    @Column("display_name") String name
}

class UserRepository {
    @Sql("SELECT id, display_name FROM users WHERE id = :id")
    Result<User, Error> find(@Param("id") Long recordId) {
        // ...
    }
}
```

状态：`@Entity`/`@Table`/`@Id`/`@Transactional` implemented (M6.5，内存驱动)；A8 派生 implemented（含限制）；编译器内建 implemented。迁移/真实数据库 planned。

### `xdk.api`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| API 类 | `@Api` | OpenAPI/路由前缀 |
| 路由方法 | `@HttpRoute`/`@Operation` | 路由/operation |
| 中间件类 | `@Middleware` | 中间件链 |
| 组件/配置/Bean | `@Component`/`@Configuration`/`@Bean` | 装配表 |
| 装配字段/构造/参数 | `@Inject` | 装配代码 |

声明：

```x
@Target(Type)
@Retention(Source)
@annotation Api {
    final String prefix
    final String title
}

@Target(Method)
@Retention(Source)
@annotation Operation {
    final String summary
}

@Target(Type)
@Retention(Source)
@annotation Middleware {
}

@Target(Field, Constructor, Parameter)
@Retention(Source)
@annotation Inject {
}

@Target(Type)
@Retention(Source)
@annotation Component {
    final String name = ""
}

@Target(Type)
@Retention(Source)
@annotation Configuration {
}

@Target(Method)
@Retention(Source)
@annotation Bean {
    final String name = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@Api("/v1", "User API")
class UserApi {
    @HttpRoute("/users/{id}", HttpMethod.Get)
    @Operation("Get user")
    HttpResponse getUser(@Query("id") Long id) {
        // ...
    }
}

@Component("userService")
class UserService {
    @Inject UserRepository repository

    @Transactional(readOnly = true)
    Result<User, Error> find(Long recordId) {
        // ...
    }
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.agent`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| receiver 类 | `@AgentReceiver` | receiver 表 |
| processor 类 | `@AgentProcessor` | processor 表 |
| exporter 类 | `@AgentExporter` | exporter 表 |
| 管线类 | `@PipelineSpec` | 管线表 |

声明：

```x
@Target(Type)
@Retention(Runtime)
@annotation AgentReceiver {
    final String name
}

@Target(Type)
@Retention(Runtime)
@annotation AgentProcessor {
    final String name
}

@Target(Type)
@Retention(Runtime)
@annotation AgentExporter {
    final String name
}

@Target(Type)
@Retention(Runtime)
@annotation PipelineSpec {
    final String name
}
```

声明文件：每个注解单独一个 PascalCase 文件（如 `HttpRoute.x`）；处理器为构建期类型；生成代码在 `<package>/generated/`。

使用：

```x
@AgentReceiver("otlp")
class OtlpReceiver {
    // ...
}

@AgentProcessor("redact")
class RedactProcessor {
    // ...
}

@AgentExporter("otlp")
class OtlpExporter {
    // ...
}

@PipelineSpec("traces")
class TracePipeline {
    // ...
}
```

状态：领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.accel`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Accelerator`/`AcceleratorDevice`/`AcceleratorProgram`/`AcceleratorQueue` | — | 句柄/服务，保持显式 class/close |
| kernel 方法 | `@GpuKernel`/`@TensorOp` | 复用 GPU/Tensor 处理器 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

### `xdk.embedded`

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 板级类型 | `@Device` | 复用 Device 处理器 |
| 引脚/地址字段 | `@Gpio`/`@I2cAddress` | 复用 Device 处理器 |
| 串口字段 | `@SerialBinding` | 复用 Serial 处理器 |
| 原生布局类型 | `@Packed`/`@Align` | 复用 FFI 布局处理器 |

状态：无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented。

---

## 4. 验收谓词

- 75 个包 README 都有“注解与生成”段，且声明/消费/处理器/生成物与实际包职责一致。
- 每个 `@annotation` 都有 `@Target`/`@Retention`；注解名不与同包类型冲突。
- 每个领域注解在 `ANNOTATION-CATALOG.md` 有条目，状态不是 `implemented` 时不得写成已实现。
- 每个 `Runtime` 注解只通过 `AnnotationRegistry` 查询；无反射/扫描/动态代理。
- 值类型按 1.2 选择 `struct`/`class` + `@Value`，不得用非法 struct 承载引用字段。
- 类型文件的 XNull 伪代码在适用时展示注解声明/使用与生成物。
