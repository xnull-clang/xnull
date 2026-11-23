# 注解目录（Annotation Catalog）

| 项 | 值 |
| --- | --- |
| 范围 | 语言内建、A8 派生、领域注解、块注解；不含 `@arc`/`@gc`（非法，不属于注解系统） |
| 权威语义 | [`solution-03-annotation.md`](../solution-03-annotation.md)（S3 1.0.0）；语法摘要见 [`solution-02-object-programming.md`](../solution-02-object-programming.md) §12（S2 3.6.0） |
| 状态含义 | `implemented` = 编译器已识别/强制并有测试；`reserved` = 保留词，不改变语义；`planned` = 合同已列、处理器未实现 |
| 计数 | 93 条：`implemented` 33（内建/元模型 9 + A8 5 + 领域 19）、`reserved` 4、`planned` 56（S6 2 + 领域 54） |
| 保留默认 | 未写 `@Retention` 时为 `Binary`；未写 `@Target` 时允许所有声明目标（`TypeUse` 必须显式） |
| 处理阶段 | `Resolve → Validate → Generate → Finalize`；多轮固定点；失败原子 |

> 本目录只定义注解合同，不表示处理器已实现。领域注解的处理器在所属包实现并通过场景验收前，状态保持 `planned`。

## 1. 语言内建

| 注解 | 做什么 | 目标 / 保留 | 强制 | 归属 | 状态 |
| --- | --- | --- | --- | --- | --- |
| `@Target` | 限定注解可挂载目标 | Annotation / Binary | 是 | 编译器 + `xdk.annotations` | implemented |
| `@Retention` | 选择 Source/Binary/Runtime | Annotation / Binary | 是 | 编译器 + `xdk.annotations` | implemented |
| `@Repeatable` | 允许同一目标重复并保序 | Annotation / Binary | 是 | 编译器 + `xdk.annotations` | implemented |
| `@ReadOnly` | 字段对外只读 | Field / Binary | 是 | 编译器 | implemented |
| `@WriteOnly` | 标记只写字段 | Field / Binary | 否 | 编译器 | implemented（识别） |
| `@Override` | 校验协议方法签名 | Method / Binary | 是 | 编译器 | implemented |
| `@Deprecated` | 使用点弃用警告 | 声明目标 / Binary | 是（警告） | 编译器 | implemented |
| `@SuppressWarnings` | 按诊断码抑制警告 | 声明目标 / Source | 是 | 编译器 | implemented |
| `@MustUse` | 返回值必须使用 | Type/Method / Binary | 是 | 语言规则 | implemented（语言规则） |
| `@Immediate` | 预留执行策略标记 | 声明目标 / Binary | 否 | 编译器 | reserved |
| `@NoAlloc` | 预留无分配标记 | 声明目标 / Binary | 否 | 编译器 | reserved |
| `@Pure` | 预留纯函数标记 | Method / Binary | 否 | 编译器 | reserved |
| `@Sendable` | 预留跨任务安全标记 | Type/Method / Binary | 否 | 编译器 | reserved |
| `@tasks` | 块内结构化并发 | Block / Source | S6 | 语言 S6 | planned（S6） |
| `@arena` | 块内区域分配 | Block / Source | S6 | 语言 S6 | planned（S6） |

## 2. 语言内建派生（A8）

| 注解 | 生成 | 目标 / 保留 | 主要诊断 | 状态 |
| --- | --- | --- | --- | --- |
| `@Value` | 不可变值语义：`equals`/`toString`/`copy`；hash 仍 planned；core 6 类型实际采用 | Type / Source | `AN0021` 非 class/非 final；`AN0022` 构造器；`AN0023` 方法冲突 | implemented (A8 core) |
| `@Data` | 数据类语义：`equals`/`toString`/`copy`；hash 仍 planned | Type / Source | `AN0021` 非 class；`AN0022` 构造器；`AN0023` 方法冲突 | implemented (A8 core) |
| `@Builder` | 生成 `<Class>Builder`：withX 链式、required-by-set、缺失字段 build panic；非泛型；core BuildInfo/RuntimeInfo 实际采用 | Type / Source | `AN0022` 构造器；`AN0024` builder 类已存在；`AN0025` 泛型暂不支持 | implemented (A8 core) |
| `@Copy` | `copy()` 与逐字段 `withX`；core Pair/IntPair/Entry 实际采用 | Type / Source | `AN0022` 构造器；`AN0023` 命名冲突 | implemented (A8 core) |
| `@Delegate` | 字段方法转发：同名/同参数/同返回；不转发字段/ctor/static；非泛型 class 目标 | Field / Source | `AN0026` 方法冲突；`AN0027` 非 class；`AN0028` 泛型目标 | implemented (A8 core) |

A8 约束：只读输入 AST；沙箱生成；确定性输出；生成/校验失败整批回滚；不得写任意文件、联网、反射或启动进程。当前 `@Value`/`@Data`/`@Copy`/`@Builder`/`@Delegate` 均已生成真实 AST。`hash` 因语言无 hash 原语仍 planned，不得写成已生成。`@Value`/`@Data` 的 `copy()` 必须走 canonical 构造器，保留不变量。

## 3. 领域注解

领域注解随所属包实现，不放进 `xdk.annotations`。CLI 试点（@CliCommand/@CliSubcommand/@Option/@Arg）为 `implemented (M2 pilot)`；codec（@Serializable/@JsonName/@CsvName）为 `implemented (M3.2/M3.3)`，validate（@Validate/@Min/@Max/@Pattern/@Email）为 `implemented (M4.2/M4.3)`，http（@HttpRoute/@Header/@Query/@Body）为 `implemented (M5.2)`；@StatusCode 等仍 planned。验收统一为“包实现 + 处理器 + 生成代码 + 场景”。

### 3.1 CLI

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 | 状态 |
| --- | --- | --- | --- | --- | --- |
| `@CliCommand` | 声明命令节点 | `String name`、`String summary = ""` | Type / Source | cli_processor → 命令树/帮助/位置参数/binder | implemented (M2 pilot + M2.2) |
| `@CliSubcommand` | 声明子命令 | `String parent`、`String name`、`String summary = ""` | Type / Source | cli_processor → 子命令表/位置参数/binder | implemented (M2 pilot + M2.2) |
| `@Option` | 声明选项 | `String name`、`String short = ""`、`String help = ""`、`Bool required = false` | Field / Source | cli_processor → 解析表/帮助/binder | implemented (M2 pilot + M2.2) |
| `@Arg` | 声明位置参数 | `String name`、`String help = ""`、`Bool required = false` | Field / Source | cli_processor → 位置参数/ArgSpec/binder | implemented (M2 pilot + M2.2) |

### 3.2 HTTP / WebSocket / JWT

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 | 状态 |
| --- | --- | --- | --- | --- | --- |
| `@HttpRoute` | 绑定 HTTP 路径与方法 | `String path`、`HttpMethod method = HttpMethod.Get` | Method / Source | http_processor → 路由表 | implemented (M5.2) |
| `@Header` | 绑定请求/响应头 | `String value` | Parameter / Source | http_processor → 头绑定 | implemented (M5.2) |
| `@Query` | 绑定查询参数 | `String value` | Parameter / Source | http_processor → 查询绑定 | implemented (M5.2) |
| `@Body` | 绑定请求/响应 body | 无 | Parameter / Source | http_processor → body 绑定 | implemented (M5.2) |
| `@StatusCode` | 标记返回状态 | 无 | Method / Source | HttpAnnotationProcessor → 状态映射 | planned |
| `@WsHandler` | 注册 WebSocket handler | 无 | Type / Source | WebSocketAnnotationProcessor → handler 表 |
| `@JwtClaim` | 绑定 claim 字段 | `String value` | Field / Source | JwtAnnotationProcessor → claims 映射 |
| `@JwtHeaderField` | 绑定 header 字段 | `String value` | Field / Source | JwtAnnotationProcessor → header 映射 |

### 3.3 SQL / 数据访问

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 | 状态 |
| --- | --- | --- | --- | --- | --- |
| `@Sql` | 绑定 SQL 文本 | `String value` | Method / Source | sql_processor → DAO 方法；诊断 AN1401–AN1410 | implemented (M6.2) |
| `@Param` | 绑定命名参数 | `String value` | Parameter / Source | sql_processor → 参数绑定 | implemented (M6.2) |
| `@Row` | 标记行映射类型 | 无 | Type / Source | sql_processor → 行 mapper | implemented (M6.2) |
| `@Column` | 绑定列名 | `String value` | Field / Source | sql_processor → 列映射 | implemented (M6.2) |
| `@Entity` | 标记实体 | `String table` | Type / Source | db_processor → 表名/CRUD/行映射 | implemented (M6.5) |
| `@Table` | 绑定表名 | `String name` | Type / Source | db_processor → 表名/CRUD/行映射 | implemented (M6.5) |
| `@Id` | 标记主键 | 无 | Field / Source | db_processor → 主键列与按 id CRUD | implemented (M6.5) |
| `@Transactional` | 事务包装 | `Bool readOnly = false` | Method / Source | db_processor → begin/commit/rollback 包装 | implemented (M6.5) |

### 3.4 编解码 / 文档格式

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 | 状态 |
| --- | --- | --- | --- | --- | --- |
| `@Serializable` | 标记可序列化类型 | `Bool pretty = false` | Type / Source | codec_processor → `<Type>ToJson`/`<Type>FromJson` | implemented (M3.2) |
| `@JsonName` | JSON 字段名 | `String value` | Field / Source | codec_processor → JSON 字段名 | implemented (M3.2) |
| `@CsvName` | CSV 列名 | `String value` | Field / Source | csv_processor → CSV 列映射 | implemented (M3.3) |
| `@YamlName` | YAML 字段名 | `String value` | Field / Source | YamlAnnotationProcessor → YAML 映射 | planned |
| `@TomlName` | TOML 字段名 | `String value` | Field / Source | TomlAnnotationProcessor → TOML 映射 | planned |
| `@XmlName` | XML 元素/属性名 | `String value` | Field / Source | XmlAnnotationProcessor → XML 映射 | planned |

### 3.5 校验 / 韧性 / 观测

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 | 状态 |
| --- | --- | --- | --- | --- | --- |
| `@Validate` | 标记校验入口 | 无 | Type / Source | validate_processor → `Schema`/`ValidationResult` | implemented (M4.2) |
| `@Min` | 数值/字符串长度下界 | `Long value` | Field / Source | validate_processor → `range`/`minLength` | implemented (M4.2) |
| `@Max` | 数值/字符串长度上界 | `Long value` | Field / Source | validate_processor → `range`/`maxLength` | implemented (M4.2) |
| `@Pattern` | 正则约束 | `String value` | Field / Source | validate_processor → `Rules.pattern` | implemented (M4.2) |
| `@Email` | 邮箱约束 | 无 | Field / Source | validate_processor → `Rules.email` | implemented (M4.3) |
| `@Cacheable` | 声明可缓存 | `String value`、`String key = ""` | Method / Source | cache_processor → Cached 包装 | implemented (M8.4) |
| `@CacheEvict` | 声明缓存淘汰 | `String value`、`String key = ""` | Method / Source | cache_processor → Evict 包装 | implemented (M8.4) |
| `@Retryable` | 重试策略 | `Int maxAttempts = 3`、`Long initialDelayMillis = 100` | Method / Source | resilience_processor → Retry 包装 | implemented (M8.2) |
| `@CircuitBreakerPolicy` | 熔断策略 | `String name`、`Int failureThreshold = 5` | Method / Source | resilience_processor → CircuitBreaker 包装 | implemented (M8.2) |
| `@RateLimit` | 限流策略 | `String name`、`Int permits`、`Long perMillis` | Method / Source | resilience_processor → RateLimiter 包装 | implemented (M8.2) |
| `@TimeoutPolicy` | 超时策略 | `Long timeoutMillis` | Method / Source | resilience_processor → Timeout 包装 | implemented (M8.2) |
| `@Metered` | 指标埋点 | `String name`、`String unitName = ""` | Method / Source | MetricsAnnotationProcessor → 指标包装 |
| `@Traced` | trace span | `String name` | Method / Source | TraceAnnotationProcessor → span 包装 |
| `@Audited` | 审计事件 | `String action` | Method / Source | AuditAnnotationProcessor → 审计包装 |

### 3.6 测试 / 调度

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 |
| --- | --- | --- | --- | --- |
| `@TestCase` | 标记测试方法 | `String name = ""` | Method / Runtime | TestAnnotationProcessor → 测试清单 |
| `@Before` | 测试前置 | 无 | Method / Runtime | TestAnnotationProcessor → 生命周期表 |
| `@After` | 测试后置 | 无 | Method / Runtime | TestAnnotationProcessor → 生命周期表 |
| `@Benchmark` | 标记基准 | `String name = ""` | Method / Runtime | TestAnnotationProcessor → 基准清单 |
| `@Scheduled` | 声明调度任务 | `String cron = ""`、`Long fixedRateMillis = 0` | Method / Runtime | ScheduleAnnotationProcessor → 作业注册 |

### 3.7 FFI / 设备 / 计算

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 |
| --- | --- | --- | --- | --- |
| `@Packed` | FFI 紧凑布局 | 无 | Type/Field / Binary | HardwareLayoutProcessor → 布局校验 |
| `@Align` | FFI 对齐 | `Int value` | Type/Field / Binary | HardwareLayoutProcessor → 对齐校验 |
| `@NativeLayout` | 原生布局校验 | 无 | Type / Binary | HardwareLayoutProcessor → 布局清单 |
| `@SerialBinding` | 串口配置 | `String path` | Field/Parameter / Source | SerialAnnotationProcessor → 端口配置 |
| `@Device` | 设备声明 | `String kind` | Type / Runtime | DeviceAnnotationProcessor → 设备目录 |
| `@Gpio` | GPIO 配置 | `Int pin`、`GpioDirection direction = GpioDirection.In` | Field/Parameter / Runtime | DeviceAnnotationProcessor → 引脚目录 |
| `@I2cAddress` | I2C 地址 | `Int address` | Field/Parameter / Runtime | DeviceAnnotationProcessor → 地址目录 |
| `@GpuKernel` | GPU kernel | `String name`、`String backend = ""` | Method / Runtime | GpuAnnotationProcessor → kernel 注册 |
| `@TensorOp` | 张量算子 | `String name` | Method / Runtime | TensorAnnotationProcessor → 算子注册 |
| `@TensorSpec` | 张量规格 | `String shape`、`String dtype` | Field/Parameter / Runtime | TensorAnnotationProcessor → shape/dtype 校验 |
| `@LinalgOp` | 线性代数算子 | `String name` | Method / Runtime | LinalgAnnotationProcessor → 算子注册 |

### 3.8 API / 解决方案

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 |
| --- | --- | --- | --- | --- |
| `@Api` | API 元数据 | `String prefix`、`String title` | Type / Source | ApiAnnotationProcessor → OpenAPI/路由 |
| `@Operation` | OpenAPI operation | `String summary` | Method / Source | ApiAnnotationProcessor → operation 元数据 |
| `@Middleware` | 中间件注册 | 无 | Type / Source | ApiAnnotationProcessor → 中间件链 |
| `@Inject` | 装配点 | 无 | Field/Constructor/Parameter / Source | ApiAnnotationProcessor → 装配代码 |
| `@Component` | 组件注册 | `String name = ""` | Type / Source | ApiAnnotationProcessor → 组件表 |
| `@Configuration` | 配置类 | 无 | Type / Source | ApiAnnotationProcessor → 配置模型 |
| `@Bean` | Bean 注册 | `String name = ""` | Method / Source | ApiAnnotationProcessor → Bean 表 |
| `@ModelSpec` | 模型元数据 | `String name` | Type / Runtime | MlAnnotationProcessor → 模型目录 |
| `@MlPipeline` | ML 流水线 | `String name` | Type / Runtime | MlAnnotationProcessor → 流水线目录 |
| `@Tool` | MCP 工具 | `String name`、`String description` | Method / Runtime | McpAnnotationProcessor → 工具清单 |
| `@ToolParam` | MCP 工具参数 | `String name`、`String description = ""`、`Bool required = true` | Parameter / Runtime | McpAnnotationProcessor → 输入 schema |
| `@Resource` | MCP 资源 | `String uri`、`String mimeType` | Method / Runtime | McpAnnotationProcessor → 资源清单 |
| `@Prompt` | MCP prompt | `String name`、`String description = ""` | Method / Runtime | McpAnnotationProcessor → prompt 清单 |
| `@AgentReceiver` | Agent receiver | `String name` | Type / Runtime | AgentAnnotationProcessor → 组件表 |
| `@AgentProcessor` | Agent processor | `String name` | Type / Runtime | AgentAnnotationProcessor → 组件表 |
| `@AgentExporter` | Agent exporter | `String name` | Type / Runtime | AgentAnnotationProcessor → 组件表 |
| `@PipelineSpec` | Agent 管线 | `String name` | Type / Runtime | AgentAnnotationProcessor → 管线表 |

## 4. 使用边界

- 注解是**构建期**元数据/检查/生成入口，不是运行时反射、扫描、动态代理或注解类加载。
- 处理器必须**显式启用**；未启用的处理器不运行，也不产生“已处理”承诺。
- 处理器在**沙箱**内运行：只读输入 AST，只写声明式输出；禁止任意文件、网络、进程、反射。
- **失败原子**：任一阶段失败，整批输出回滚；不得留下半生成文件或半修改 AST。
- **确定性**：同一输入、同一处理器集合、同一配置产生相同字节；排序、命名、重复项保序。
- 运行时只有 `Runtime` 注解进入编译器生成的静态 `AnnotationRegistry`；`Source`/`Binary` 不可运行时查询。
- 领域注解定义在**所属包**，不放进 `xdk.annotations`；`xdk.annotations` 只保留 14 个元模型类型、处理器合同和 Registry。
- 每个领域注解是一个 PascalCase 类型，单独成文件；处理器是构建期类型，不计入运行时包类型数；生成源码放 `<package>/generated/` 并带 `generated` 标记。
- 识别但不强制的注解（如 `@WriteOnly`、预留 `@Pure`）不是语义承诺；不得据此宣称行为已被检查。
- `@arc`/`@gc` 不是注解系统成员，使用即编译错误；块注解 `@tasks`/`@arena` 归语言 S6。
