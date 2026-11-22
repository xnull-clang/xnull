# 注解目录（Annotation Catalog）

| 项 | 值 |
| --- | --- |
| 范围 | 语言内建、A8 派生、领域注解、块注解；不含 `@arc`/`@gc`（非法，不属于注解系统） |
| 权威语义 | [`solution-02-object-programming.md`](../solution-02-object-programming.md) §12（S2 3.5.0）、[`ANNOTATION-SYSTEM.md`](ANNOTATION-SYSTEM.md)、[`ANNOTATION-PLAN.md`](ANNOTATION-PLAN.md) |
| 状态含义 | `implemented` = 编译器已识别/强制并有测试；`reserved` = 保留词，不改变语义；`planned` = 合同已列、处理器未实现 |
| 计数 | 93 条：`implemented` 12、`reserved` 4、`planned` 77（S5 2 + A8 2 + 领域 73） |
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
| `@tasks` | 块内结构化并发 | Block / Source | S5 | 语言 S5 | planned（S5） |
| `@arena` | 块内区域分配 | Block / Source | S5 | 语言 S5 | planned（S5） |

## 2. 语言内建派生（A8）

| 注解 | 生成 | 目标 / 保留 | 主要诊断 | 状态 |
| --- | --- | --- | --- | --- |
| `@Value` | 不可变值语义：`equals`/`toString`/`copy`；hash 仍 planned；core 6 类型实际采用 | Type / Source | 非 final 字段、构造器顺序/既有方法冲突 | implemented (A8 core) |
| `@Data` | 数据类语义：`equals`/`toString`/`copy`；hash 仍 planned | Type / Source | 字段/方法名冲突 | implemented (A8 core) |
| `@Builder` | builder 类型、`build()`、必填校验 | Type / Source | 缺必填、重复设置、构造不可见 | planned |
| `@Copy` | `copy()` 与逐字段 `withX` | Type / Source | 不可复制字段、命名冲突 | implemented (A8 core) |
| `@Delegate` | 到指定字段的转发方法 | Type/Field / Source | 目标缺失、签名冲突、可见性不足 | planned |

A8 约束：只读输入 AST；沙箱生成；确定性输出；生成/校验失败整批回滚；不得写任意文件、联网、反射或启动进程。当前 `@Value`/`@Data`/`@Copy` 已生成真实 AST 方法；`@Builder`/`@Delegate` 仍 planned。`hash` 因语言无 hash 原语仍 planned，不得写成已生成。`@Value`/`@Data` 的 `copy()` 必须走 canonical 构造器，保留不变量。

## 3. 领域注解

领域注解随所属包实现，不放进 `xdk.annotations`。下表状态均为 `planned`，验收统一为“包实现 + 处理器 + 生成代码 + 场景”。

### 3.1 CLI

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 |
| --- | --- | --- | --- | --- |
| `@CliCommand` | 声明命令节点 | `String name`、`String summary = ""` | Type / Runtime | CliAnnotationProcessor → 命令树/帮助元数据 |
| `@CliSubcommand` | 声明子命令 | `String name` | Type / Runtime | CliAnnotationProcessor → 子命令表 |
| `@Option` | 声明选项 | `String name`、`String shortName = ""`、`Bool required = false` | Field/Parameter / Runtime | CliAnnotationProcessor → 解析表/补全元数据 |
| `@Arg` | 声明位置参数 | `String name`、`Bool required = true` | Field/Parameter / Runtime | CliAnnotationProcessor → 参数表/用法文本 |

### 3.2 HTTP / WebSocket / JWT

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 |
| --- | --- | --- | --- | --- |
| `@HttpRoute` | 绑定 HTTP 路径与方法 | `String path`、`HttpMethod method = HttpMethod.Get` | Method / Source | HttpAnnotationProcessor → 路由表 |
| `@Header` | 绑定请求/响应头 | `String value` | Parameter / Source | HttpAnnotationProcessor → 头绑定 |
| `@Query` | 绑定查询参数 | `String value` | Parameter / Source | HttpAnnotationProcessor → 查询绑定 |
| `@Body` | 绑定请求/响应 body | 无 | Parameter / Source | HttpAnnotationProcessor → body 绑定 |
| `@StatusCode` | 标记返回状态 | 无 | Method / Source | HttpAnnotationProcessor → 状态映射 |
| `@WsHandler` | 注册 WebSocket handler | 无 | Type / Source | WebSocketAnnotationProcessor → handler 表 |
| `@JwtClaim` | 绑定 claim 字段 | `String value` | Field / Source | JwtAnnotationProcessor → claims 映射 |
| `@JwtHeaderField` | 绑定 header 字段 | `String value` | Field / Source | JwtAnnotationProcessor → header 映射 |

### 3.3 SQL / 数据访问

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 |
| --- | --- | --- | --- | --- |
| `@Sql` | 绑定 SQL 文本 | `String value` | Method / Source | SqlAnnotationProcessor → DAO 方法 |
| `@Param` | 绑定命名参数 | `String value` | Parameter / Source | SqlAnnotationProcessor → 参数绑定 |
| `@Row` | 标记行映射类型 | 无 | Type / Source | SqlAnnotationProcessor → 行 mapper |
| `@Column` | 绑定列名 | `String value` | Field / Source | SqlAnnotationProcessor → 列映射 |
| `@Entity` | 标记实体 | `String table` | Type / Source | DbAnnotationProcessor → 实体元数据 |
| `@Table` | 绑定表名 | `String name` | Type / Source | DbAnnotationProcessor → 表映射 |
| `@Id` | 标记主键 | 无 | Field / Source | DbAnnotationProcessor → 主键元数据 |
| `@Transactional` | 事务包装 | `Bool readOnly = false` | Method / Source | DbAnnotationProcessor → 事务包装 |

### 3.4 编解码 / 文档格式

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 |
| --- | --- | --- | --- | --- |
| `@Serializable` | 标记可序列化类型 | 无 | Type / Source | CodecAnnotationProcessor → 编解码器 |
| `@JsonName` | JSON 字段名 | `String value` | Field / Source | CodecAnnotationProcessor → JSON 映射 |
| `@CsvName` | CSV 列名 | `String value` | Field / Source | CodecAnnotationProcessor → CSV 映射 |
| `@YamlName` | YAML 字段名 | `String value` | Field / Source | YamlAnnotationProcessor → YAML 映射 |
| `@TomlName` | TOML 字段名 | `String value` | Field / Source | TomlAnnotationProcessor → TOML 映射 |
| `@XmlName` | XML 元素/属性名 | `String value` | Field / Source | XmlAnnotationProcessor → XML 映射 |

### 3.5 校验 / 韧性 / 观测

| 注解 | 做什么 | 字段 | 目标 / 保留 | 处理器 / 生成 |
| --- | --- | --- | --- | --- |
| `@Validate` | 标记校验入口 | 无 | Type/Field / Source | ValidateAnnotationProcessor → 校验器 |
| `@Min` | 数值下界 | `Long value` | Field/Parameter / Source | ValidateAnnotationProcessor → 规则 |
| `@Max` | 数值上界 | `Long value` | Field/Parameter / Source | ValidateAnnotationProcessor → 规则 |
| `@Pattern` | 正则约束 | `String value` | Field/Parameter / Source | ValidateAnnotationProcessor → 规则 |
| `@Email` | 邮箱约束 | 无 | Field/Parameter / Source | ValidateAnnotationProcessor → 规则 |
| `@Cacheable` | 声明可缓存 | `String value`、`String key = ""` | Method / Source | CacheAnnotationProcessor → 缓存包装 |
| `@CacheEvict` | 声明缓存淘汰 | `String value`、`String key = ""` | Method / Source | CacheAnnotationProcessor → 淘汰包装 |
| `@Retryable` | 重试策略 | `Int maxAttempts = 3`、`Long initialDelayMillis = 100` | Method / Source | ResilienceAnnotationProcessor → 重试包装 |
| `@CircuitBreakerPolicy` | 熔断策略 | `String name`、`Int failureThreshold = 5` | Method / Source | ResilienceAnnotationProcessor → 熔断包装 |
| `@RateLimit` | 限流策略 | `String name`、`Int permits`、`Long perMillis` | Method / Source | ResilienceAnnotationProcessor → 限流包装 |
| `@TimeoutPolicy` | 超时策略 | `Long timeoutMillis` | Method / Source | ResilienceAnnotationProcessor → 超时包装 |
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
- `@arc`/`@gc` 不是注解系统成员，使用即编译错误；块注解 `@tasks`/`@arena` 归语言 S5。
