# XNull 注解系统设计

| 项 | 值 |
| --- | --- |
| 位置 | 注解层核心；语言/编译器/runtime/工具链 |
| 权威语法 | [`solution-02-object-programming.md`](../solution-02-object-programming.md) §12（2026-11-22 扩展） |
| 覆盖 | 语言、XDK、编译器、runtime、工具链、基线 |
| 状态 | 设计基线；实现未开始 |
| 原则 | 注解是编译期契约与生成入口，不是运行时反射魔法 |
| 实施 | P1 编译器/元模型/处理器计划见 [`ANNOTATION-PLAN.md`](ANNOTATION-PLAN.md) |

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
| 框架适配 | `@Route`、`@Entity`、`@Inject`、`@Tool`、`@Resource` |
| 资源/FFI | `@Packed`、`@Align`、`@Device`、`@GpuKernel` |
| 可观测/治理 | `@Retry`、`@Cacheable`、`@Traced`、`@Audited` |
| 测试/调度 | `@Test`、`@Benchmark`、`@Scheduled` |

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
- 支持：`Bool`、整数、`Float`/`Double`、`Char`、`String`、简单枚举、常量数组、嵌套注解、类型引用字符串；
- 字段必须有常量初值；
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
| 领域注解 | `@Serializable`、`@Route`、`@Entity`、`@Tool` | 所属 XDK 包 |
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
| `@tasks`/`@arena` | Block | 按 S5 | 不进入通用注解系统 |
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
| 生成成员 | `@Data` 的 equals/hash/toString/copy；`@Delegate` 转发 |
| 生成协议实现 | 为类生成缺失的协议方法 |
| 生成独立类型 | 序列化器、校验器、路由表、DAO、Mapper |
| 生成元数据 | `AnnotationRegistry`、路由表、测试清单 |
| 生成诊断 | 冲突、缺失、非法组合 |
| 生成文档/IDE 信息 | 注解说明、生成代码导航 |

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

| 层 | 注解/处理器 | 对接能力 |
| --- | --- | --- |
| core | `@ReadOnly`、`@Override`、`@Deprecated`、`@SuppressWarnings` | 字段/协议/API 生命周期 |
| annotations | `@Target`、`@Retention`、`@Repeatable`、`@Data`、`@Value`、`@Builder`、`@Copy`、`@Delegate` | 生成/派生/元数据 |
| net | `@HttpRoute`、`@HttpMethod`、`@Header`、`@Query`、`@Body`、`@StatusCode`、`@WebSocketHandler` | 路由/参数绑定/协议适配 |
|  sql | `@Sql`、`@Param`、`@Row`、`@Column` | SQL 映射/DAO 生成 |
|  jwt | `@JwtClaim`、`@JwtHeader` | claims 映射 |
| os/device | `@Packed`、`@Align`、`@NativeLayout`、`@Device`、`@Gpio`、`@I2cAddress`、`@SerialPort` | FFI/设备布局 |
|  gpu/tensor/linalg | `@GpuKernel`、`@TensorOp`、`@LinalgOp` | kernel/算子生成 |
|  codec | `@Serializable`、`@JsonName` | JSON 编解码器生成 |
|  yaml/toml/xml | `@YamlName`、`@TomlName`、`@XmlName` | 文档字段名映射 |
|  validate | `@Validate`、`@Min`、`@Max`、`@Pattern`、`@Email` | 校验器生成 |
|  cache/resilience | `@Cacheable`、`@CacheEvict`、`@Retry`、`@CircuitBreaker`、`@RateLimit`、`@Timeout` | 包装器/策略生成 |
|  metrics/trace/audit | `@Metered`、`@Traced`、`@Audited` | 观测/审计包装 |
|  test/schedule | `@Test`、`@Before`、`@After`、`@Benchmark`、`@Scheduled`、`@Cron` | 测试清单/作业注册 |
|  api | `@Api`、`@Operation`、`@Middleware`、`@Inject`、`@Component`、`@Configuration`、`@Bean` | 路由/DI/配置生成 |
|  db | `@Entity`、`@Table`、`@Id`、`@Transactional` | ORM/DAO/事务包装 |
|  ml | `@Model`、`@Pipeline`、`@TensorSpec` | 模型/流水线描述 |
|  mcp | `@Tool`、`@Resource`、`@Prompt` | MCP 能力清单 |
|  agent | `@Receiver`、`@Processor`、`@Exporter`、`@Pipeline` | 采集/处理/导出管线 |

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
