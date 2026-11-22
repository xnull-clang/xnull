# XNull 注解系统设计

| 项 | 值 |
| --- | --- |
| 位置 | 注解层核心；语言/编译器/runtime/工具链 |
| 权威语义 | [`solution-03-annotation.md`](../solution-03-annotation.md)（S3 1.0.0）；Part 2 §12 是语法摘要 |
| 语言摘要 | [`solution-02-object-programming.md`](../solution-02-object-programming.md) §12（S2 3.6.0） |
| 覆盖 | 语言、XDK、编译器、runtime、工具链、基线 |
| 状态 | 编译器 B1/B2、`xdk.annotations` 14 类型、A8 5 个派生已实现；A9 工具提取、领域处理器为 planned |
| 原则 | 注解是编译期契约与生成入口，不是运行时反射魔法 |
| 实施 | P1 编译器/元模型/处理器计划见 [`ANNOTATION-PLAN.md`](ANNOTATION-PLAN.md)；逐条状态见 [`ANNOTATION-CATALOG.md`](ANNOTATION-CATALOG.md) |

### 0.1 实现状态

| 能力 | 状态 | 证据 |
| --- | --- | --- |
| `@annotation` 声明/使用/参数/目标/保留/重复 | 已实现 | `src/mini/main.x`、`src/mini/tests/annotations*` |
| 内建 `@ReadOnly`/`@Override`/`@Deprecated`/`@SuppressWarnings` | 已实现 | 编译器诊断与测试 |
| 静态 `AnnotationRegistry` 生成与查询 | 已实现 | `src/mini/tests/xdk2/annotations_types/annotations_types_runtime_registry.x` |
| `xdk.annotations` 14 类型 | 已实现 | `src/xdk/annotations/Annotations.x` |
| `@Value`/`@Data`/`@Builder`/`@Copy`/`@Delegate` 派生处理器 | 已实现（A8，含限制） | Part 3 §5；本文件 §3.2.1 |
| 领域注解处理器（HTTP/SQL/codec/validate/MCP/CLI/设备/GPU 等） | planned | [`ANNOTATION-CATALOG.md`](ANNOTATION-CATALOG.md) 与各包 README |
| 运行时反射/类路径扫描/动态代理 | 永不做 | 语言与 XDK 均为编译期生成 |

---

## 1. 定位

注解是 XNull 的**跨切面契约层**：

- 协议解决“运行时多态”；
- 注解解决“编译期声明、检查、生成、元数据”；
- 继承解决“复用”，注解解决“复用 + 生成 + 约束”，且不引入脆弱基类；
- 注解不替代显式 API，而是把重复的样板、横切规则、外部映射交给编译器/工具链。

目标能力：

| 能力 | 例子 |
| --- | --- |
| 编译期检查 | `@ReadOnly`、`@Override`、`@MustUse`、`@Target` |
| 派生成员 | `@Data`、`@Value`、`@Builder`、`@Copy`、`@Delegate` |
| 序列化映射 | `@Serializable`、`@JsonName`、`@YamlName`、`@XmlName` |
| 校验 | `@Validate`、`@Min`、`@Max`、`@Pattern` |
| 框架适配 | `@HttpRoute`、`@Entity`、`@Inject`、`@Tool`、`@Resource` |
| 资源/FFI | `@Packed`、`@Align`、`@Device`、`@GpuKernel` |
| 可观测/治理 | `@Retryable`、`@Cacheable`、`@Traced`、`@Audited` |
| 测试/调度 | `@TestCase`、`@Benchmark`、`@Scheduled` |

不做：

- 通用运行时反射、动态类加载、任意注解扫描；
- 注解处理器在运行时执行；
- 通过注解绕过类型系统/错误模型/所有权；
- 依赖注入容器式隐式全局注册；
- 命名参数、注解继承、无限嵌套。

---

## 2. 语言模型

### 2.1 声明

```x
@annotation Marker {
    final String name = "";
}
```

- 注解类型只作为编译期声明；
- 字段必须 `final`，类型为常量类型；
- 支持：`Bool`、整数、`Float`/`Double`、`Char`、`String`、简单枚举、常量数组、嵌套注解、`Type`/`TypeRef` 引用；
- 字段可有常量初值；无初值的字段是必填字段，使用点必须提供；
- 不允许方法、构造器、`deinit`、静态成员、泛型、继承、协议实现；
- 注解类型不能 `new`，不能作为运行时值传递。

### 2.2 使用

```x
@Marker("x")
class Device { }
```

- 位置参数，按字段声明顺序绑定；尾部字段可省略；
- 参数必须是编译期常量；
- 目标：Package、Type、Annotation、TypeParameter、Field、Method、Constructor、Deinit、Parameter、TypeUse、EnumItem；
- 未知注解、错目标、错参数、重复注解都是编译错误；
- `@Repeatable` 允许同一目标重复；重复项按出现顺序保留；
- 注解不改变控制流、对象模型或内存策略。

### 2.3 保留策略

| 策略 | 编译器 | 产物 | 运行时 |
| --- | --- | --- | --- |
| `Source` | 处理器可见 | 不保留 | 不可查询 |
| `Binary` | 处理器可见 | 元数据供工具/IDE | 不可查询 |
| `Runtime` | 处理器可见 | 生成静态注册表 | 通过 `AnnotationRegistry` 只读查询 |

运行时不是“反射读取类文件”，而是编译器生成静态表；没有动态扫描。

### 2.4 元注解

- `@Target`：限制注解可应用目标；未声明时允许所有声明目标，`TypeUse` 必须显式；
- `@Retention`：选择 Source/Binary/Runtime；默认 `Binary`；
- `@Repeatable`：允许重复使用；
- `@Deprecated`：标记废弃；
- `@SuppressWarnings`：诊断抑制；
- `@Inherited` 不支持（XNull 不依赖类继承多态）。

### 2.5 注解目录分层

| 类别 | 例子 | 归属 |
| --- | --- | --- |
| 元注解 | `@Target`、`@Retention`、`@Repeatable` | 语言内建 |
| 生命周期/检查 | `@Deprecated`、`@SuppressWarnings`、`@ReadOnly`、`@Override` | 语言内建 |
| 通用派生 | `@Value`、`@Data`、`@Builder`、`@Copy`、`@Delegate` | 语言内建 + 构建期处理器 |
| 领域注解 | `@Serializable`、`@HttpRoute`、`@Entity`、`@Tool` | 所属 XDK 包 |
| 元模型/处理器合同 | `AnnotationTarget`、`AnnotationValue`、`AnnotationProcessor` 等 | `xdk.annotations` 14 类型 |

- `xdk.annotations` 不定义 `@Data`/`@Serializable` 等具体注解；它们是语言内建或领域包声明。
- 通用派生注解必须由编译器/标准处理器实现，不能由用户代码在运行时解释。
- 领域注解必须声明目标/保留，并绑定所属包处理器。

### 2.6 内建注解

| 注解 | 目标 | 强制 | 说明 |
| --- | --- | --- | --- |
| `@ReadOnly` | Field | 是 | 外部只读、内部可写 |
| `@Override` | Method | 使用即强制 | 必须匹配协议方法；不要求每个实现都标注 |
| `@Deprecated` | Declaration | 是（警告） | 使用点诊断 |
| `@SuppressWarnings` | Declaration | 是（诊断） | 仅抑制指定诊断码 |
| `@Target`/`@Retention`/`@Repeatable` | Annotation | 是 | 元注解 |
| `@MustUse` | Type/Method | 是 | `Result` 丢弃诊断；不是普通注解 |
| `@tasks`/`@arena` | Block | 按 S6 | 不进入通用注解系统 |
| `@Immediate`/`@NoAlloc`/`@Pure`/`@Sendable` | — | 预留 | 语义冻结前禁止使用 |

---

## 3. 处理模型

### 3.1 处理器

注解处理器是**构建期插件**，不是运行时组件：

```text
Source/Binary/Runtime
  → 解析/目标/常量检查
  → Resolve 处理器
  → Validate 处理器
  → Generate 处理器（可多轮）
  → Finalize 处理器
  → 生成源码 + 元数据 + 诊断
```

- 处理器声明支持的阶段；
- 每轮只读取已解析元素，生成新声明；
- 生成声明进入下一轮，直到无新生成；
- 生成必须确定性、可重现、带来源标注；
- 处理器不得执行网络、任意文件写入、运行时反射；
- 处理器不得修改已有声明，只能新增成员/文件；
- 生成文件默认不进入源码目录，构建产物归档。

### 3.2 生成能力

| 能力 | 用途 |
| --- | --- |
| 生成成员 | `@Data` 的 equals/toString/copy；`@Delegate` 转发 |
| 生成协议实现 | 为类生成缺失的协议方法 |
| 生成独立类型 | 序列化器、校验器、路由表、DAO、Mapper |
| 生成元数据 | `AnnotationRegistry`、路由表、测试清单 |
| 生成诊断 | 冲突、缺失、非法组合 |
| 生成文档/IDE 信息 | 注解说明、生成代码导航 |

#### 3.2.1 A8 派生合同

| 注解 | 前置条件 | 生成 | 不生成 |
| --- | --- | --- | --- |
| `@Value` | class；实例字段全 `final`；构造器与字段顺序/类型匹配 | `equals(other)`、`toString()`、`copy()` | `hash()`、访问器、setter、深拷贝、运行时反射 |
| `@Data` | class；构造器与字段顺序/类型匹配 | `equals`、`toString`、`copy()` | `hash()`、访问器/setter/property 语法 |
| `@Builder` | 非泛型 class；构造器匹配字段 | `<Type>Builder`、`withField(value)`、`build()`、缺字段诊断 | 泛型展开、运行时 builder 注册、全局缓存 |
| `@Copy` | 类型可复制；字段可读 | `copy()`、逐字段 `withField(value)` | 深拷贝、隐式共享 |
| `@Delegate` | class 字段；目标是非泛型 class | 到目标字段的实例方法转发 | 静态转发、协议实现推导、动态代理 |

规则：

- 当前 `@Value` 只做浅校验（class、final 字段、构造器匹配）；不证明引用字段可值比较，也不生成 `hash()`。这是明确限制，不得写成深度值验证。
- `@Value` 的 `copy()` 必须走 canonical 构造器，保留构造器中的防御性复制/校验；不得直接复制私有字段绕过不变量。
- `@Data` 不生成访问器；XNull 字段直接读写。需要计算/校验时写动词方法或使用领域注解。
- `@Builder` 的 `build()` 必须校验必填字段和跨字段不变量；失败返回诊断或 panic（按目标类型的失败通道），不得返回半成品。
- `@Value`/`@Data` 生成成员与手写成员同名时，处理器报错；实现必须删除手写成员，不能“注解 + 手写”并存。
- `@Copy`/`@Builder` 的生成名不得与已有成员冲突；冲突是错误，不是覆盖。
- A8 已实现，但 `@Builder`/`@Delegate` 仅支持非泛型；`@Value`/`@Data` 不生成 `hash()`。合同中的深校验/泛型支持是未来扩展，不是当前行为。

### 3.3 安全与确定性

- 处理器必须在构建清单显式启用；
- 依赖包默认不能自动带入处理器；
- 生成代码带 `generated` 标记，禁止手改；
- 处理器输入哈希 + 版本参与增量缓存；
- 生成失败不产生半成品；
- 注解参数只在编译期求值；
- 运行时不加载注解类、不扫描类路径。

---

## 4. Runtime 模型

`xdk.annotations` 包（见 [`annotations`](annotations/README.md)）提供只读运行时元数据与处理器合同：

- `AnnotationTarget`：目标枚举；
- `AnnotationRetention`：保留策略；
- `AnnotationValueKind`/`AnnotationValue`：常量值树；
- `AnnotationInfo`：单个注解使用；
- `AnnotationSet`：同一目标上的注解集合；
- `AnnotationRegistry`：编译器生成的静态注册表；
- `AnnotationElement`：处理器看到的元素模型；
- `AnnotationProcessor*`：构建期处理器合同。

运行时查询只查生成表：

```xnull
AnnotationSet set = registry.ofType("app.Device")
AnnotationValue? name = set.first("Marker")?.valueOrNull("name")
```

没有 `Class.forName`、没有类路径扫描、没有动态代理。

---

## 5. XDK 对接矩阵

| 层/包 | 注解/处理器 | 对接能力 | 状态 |
| --- | --- | --- | --- |
| annotations/core | `@Target`、`@Retention`、`@Repeatable`、`@ReadOnly`、`@Override`、`@Deprecated`、`@SuppressWarnings` | 声明校验/生命周期/诊断 | implemented |
| annotations A8 | `@Value`、`@Data`、`@Builder`、`@Copy`、`@Delegate` | 派生成员/构造器/复制/转发 | implemented（含限制） |
| `xdk.cli` | `@CliCommand`、`@Option`、`@Arg`、`@CliSubcommand` | 命令树、解析、帮助/补全元数据 | planned |
| `xdk.net.http` | `@HttpRoute`、`@Header`、`@Query`、`@Body`、`@StatusCode` | 路由表、参数绑定、响应状态 | planned |
| `xdk.net.websocket` | `@WsHandler` | handler 注册/消息映射 | planned |
| `xdk.jwt` | `@JwtClaim`、`@JwtHeaderField` | claims/header 映射 | planned |
| `xdk.sql` | `@Sql`、`@Param`、`@Row`、`@Column` | DAO/行映射/参数绑定 | planned |
| `xdk.codec` | `@Serializable`、`@JsonName`、`@CsvName` | JSON/CSV 编解码器与字段名 | planned |
| `xdk.yaml`/`toml`/`xml` | `@YamlName`、`@TomlName`、`@XmlName` | 文档字段名映射 | planned |
| `xdk.validate` | `@Validate`、`@Min`、`@Max`、`@Pattern`、`@Email` | 校验器/字段规则/错误路径 | planned |
| `xdk.cache` | `@Cacheable`、`@CacheEvict` | 缓存键/淘汰包装 | planned |
| `xdk.schedule` | `@Scheduled` | 作业注册/cron 元数据 | planned |
| `xdk.resilience` | `@Retryable`、`@CircuitBreakerPolicy`、`@RateLimit`、`@TimeoutPolicy` | 重试/熔断/限流/超时包装 | planned |
| `xdk.metrics`/`trace`/`audit` | `@Metered`、`@Traced`、`@Audited` | 观测/审计包装 | planned |
| `xdk.test` | `@TestCase`、`@Before`、`@After`、`@Benchmark` | 测试清单/生命周期/基准 | planned |
| `xdk.os.hardware` | `@Packed`、`@Align`、`@NativeLayout` | FFI 布局/对齐校验 | planned |
| `xdk.serial` | `@SerialBinding` | 串口配置/布局 | planned |
| `xdk.device` | `@Device`、`@Gpio`、`@I2cAddress` | 设备/引脚/地址清单 | planned |
| `xdk.gpu` | `@GpuKernel` | kernel 注册/后端校验 | planned |
| `xdk.tensor` | `@TensorOp`、`@TensorSpec` | 算子注册/shape/dtype | planned |
| `xdk.linalg` | `@LinalgOp` | 算子注册/矩阵约束 | planned |
| `xdk.api` | `@Api`、`@Operation`、`@Middleware`、`@Inject`、`@Component`、`@Configuration`、`@Bean` | 路由/OpenAPI/装配 | planned |
| `xdk.db` | `@Entity`、`@Table`、`@Id`、`@Transactional` | 实体/表/事务 | planned |
| `xdk.ml` | `@ModelSpec`、`@MlPipeline` | 模型/流水线描述 | planned |
| `xdk.mcp` | `@Tool`、`@ToolParam`、`@Resource`、`@Prompt` | 工具/参数 schema/资源/prompt | planned |
| `xdk.agent` | `@AgentReceiver`、`@AgentProcessor`、`@AgentExporter`、`@PipelineSpec` | 采集/处理/导出管线 | planned |

规则：

- 领域注解定义在所属包，不全部塞进 `xdk.annotations`；
- `xdk.annotations` 只定义元模型、元注解、处理器合同；通用派生注解由语言/标准处理器定义；
- 领域注解必须声明 `@Target`/`@Retention`；
- 处理器必须由包/项目显式启用；
- 运行时只读生成元数据，不反射。

---

## 6. 工具链

| 工具 | 责任 |
| --- | --- |
| 编译器前端 | 解析 `@annotation`/使用、目标、常量参数 |
| 语义分析 | 注解类型解析、重复/未知/目标/参数诊断 |
| 处理器调度 | 阶段、轮次、依赖、生成、固定点 |
| 代码生成 | 生成成员/类型/元数据；确定性；来源标记 |
| 构建系统 | 处理器清单、沙箱、增量缓存、生成目录 |
| IDE/LSP | 注解提示、生成代码导航、诊断 |
| 文档 | 注解索引、目标/保留/处理器说明 |
| 测试 | 注解解析/校验/生成/运行时注册表矩阵 |

---

## 7. 版本与兼容

- 注解类型是 API：目标、保留、字段、默认值、处理器行为都算契约；
- 删除/收紧目标或保留策略是破坏性变更；
- `@Deprecated` 至少保留一个次版本；
- 生成代码格式/注册表格式需要版本号；
- 处理器版本与编译器版本记录在生成元数据；
- 旧注解未知时编译错误，不静默忽略。

---

## 8. 顺序

层顺序调整为：

```text
annotations        ← 语言/元数据/处理器合同
core               ← errors/runtime/meta/.../execution
net/jwt/sql
os/平台/计算
utils
solutions
```

core 既有 `01`–`16` 文件名保持不变，避免破坏 `core-batches.sh` 与旧账本。

 实现前必须先冻结：

1. 注解语言语法/保留/目标；
2. `xdk.annotations` 元模型；
3. 处理器阶段/生成/诊断；
4. XDK 各层注解矩阵；
5. 运行时注册表格式。

---

## 9. 验收

```text
注解语言语法冻结
注解元模型类型完整（14 类）
编译器解析/目标/常量/重复/未知诊断
处理器阶段/轮次/生成/确定性
运行时 AnnotationRegistry 只读查询
各层注解矩阵无缺口
基线 注解能力章节更新
无运行时反射/类路径扫描/动态代理
```
