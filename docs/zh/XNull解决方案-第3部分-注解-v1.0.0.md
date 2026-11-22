# XNull 解决方案 第 3 部分：注解

| 项 | 值 |
| --- | --- |
| 文档编号 | 第 3 部分（S3） |
| 文档版本 | 1.0.0 |
| 规范状态 | 正式；开放决策见 §14，尚未冻结 |
| 发布日期 | 2026-11-23 |
| 适用对象 | XNull 语言、编译器、XDK、工具链与 IDE 实现 |
| 相关部分 | 第 0 部分；第 1 部分 v3.4.0；第 2 部分 v3.6.0；第 4 部分 v3.2.0；第 5 部分 v1.2.0；第 6 部分 v1.3.0；第 7 部分 v3.0.0；第 8 部分 v2.2.0；第 9 部分 v2.0.0；第 10 部分 v5.3.0 |

> 英文正式版：[`solution-03-annotation.md`](../solution-03-annotation.md)。中文译文与英文冲突时以英文为准。

版本规则：修订号用于不改变语义的澄清，次版本用于向后兼容的新增，主版本用于破坏性变更。历史版本见 git 记录。

修订说明：1.0.0（2026-11-23）建立独立注解解决方案。第 2 部分 §12 仍是对象模型语法摘要；本文件是完整注解合同。

## 决策摘要

- 注解是编译期声明。它提供静态检查、构建期代码生成和只读元数据，不是运行时反射。
- 协议表达行为；注解表达声明性元数据、映射意图和生成意图。注解不替代协议或显式 API。
- XNull 注解语法与第 2 部分 §12 一致：`@annotation`、`@Name`、位置参数、11 个目标、三种保留策略。本文件定义完整执行模型，以及语言、包、工具链、运行时的边界。
- 编译器负责注解解析、目标/保留/重复检查、常量求值、内建检查、A8 派生成员和静态注册表。领域包负责自己的领域注解和构建期生成器。
- 只有 `Runtime` 注解进入编译器生成的 `AnnotationRegistry`。不存在类路径扫描、反射、动态加载、动态代理或运行时处理器。
- `@Value`、`@Data`、`@Copy`、`@Builder`、`@Delegate` 已在编译器中实现，但有限制（§5.7）。领域注解在所属包处理器和生成物存在前保持 `planned`。
- 派生成员、生成类型、生成注册表和诊断都是版本化 API。删除注解、改变目标/保留或改变生成行为都是破坏性变更。

## 0. 规范基础

### 0.1 范围

本方案规定：

- 第 2 部分 §12 语法摘要之外的注解执行模型；
- 注解与 XNull 对象模型、协议、错误模型、内存模型和有限泛型的适配；
- 内建注解、派生注解、领域注解和处理器边界；
- 构建期处理器生命周期和运行时 `AnnotationRegistry` 边界；
- 公共 API 文档的强制注解面；
- 兼容性规则、示例、验收标准和开放决策。

### 0.2 非目标

本方案不规定：

- 对象模型和类型声明语义（第 2 部分）；
- 内存策略、ARC/GC、资源清理或 FFI 所有权（第 4 部分）；
- `Result`、`try`、`Error`、`ErrorKind` 或边界转换（第 5 部分）；
- 任务、取消或同步语义（第 6 部分）；
- XDK 包目录和 API 命名（第 7 部分）；
- CLI/构建/FFI 实现机制（第 8 部分）；
- IDE/编辑器行为（第 9 部分）；
- 工程清单语法（第 10 部分）；
- 编译器、处理器、生成器或测试的实现。

### 0.3 规范用语

**MUST**、**MUST NOT**、**SHOULD**、**SHOULD NOT**、**MAY** 按 RFC 2119 语义使用。

实现 MUST 以稳定诊断和源码位置拒绝违反 MUST/MUST NOT 的程序。扩展 MUST 显式启用，且 MUST NOT 改变标准注解的含义。相同源码、编译器版本、处理器集合和选项 MUST 产生确定性诊断与生成输出。

### 0.4 术语

| 术语 | 含义 |
| --- | --- |
| 注解声明 | `@annotation Name { ... }`，一种编译期类型 |
| 注解使用 | 声明位置上的 `@Name` 或 `@Name(arg1, arg2, ...)` |
| 内建注解 | 编译器识别的注解，如 `@ReadOnly` 或 `@Override` |
| 派生注解 | 生成成员的 A8 注解：`@Value`/`@Data`/`@Copy`/`@Builder`/`@Delegate` |
| 领域注解 | 由 XDK 包拥有的注解，如 `@HttpRoute` 或 `@Sql` |
| 处理器 | 校验注解和/或生成源码的构建期组件 |
| 生成源码 | 带 generated 标记的编译器/处理器输出 |
| 注册表 | 编译器为 `Runtime` 注解生成的只读 `AnnotationRegistry` |
| `implemented` | 所述行为已有代码和测试 |
| `reserved` | 已识别，但除识别外不承诺语义 |
| `planned` | 合同已写，实现不存在 |
| `open` | 决策缺少 owner 签字记录 |

### 0.5 状态规则

功能状态由可执行证据决定，不由本文件文字决定。领域注解在以下四项全部存在前 MUST NOT 记为 `implemented`：

1. 注解类型已在所属包声明；
2. 处理器/生成器已在构建清单注册；
3. 已产生并测试生成源码或元数据；
4. 已有场景覆盖声明、生成、诊断和运行时行为。

## 1. 定位与边界

### 1.1 编译期元数据与生成

注解是编译期声明，其值是编译期常量。编译器可以：

- 校验目标、保留、重复、参数和内建规则；
- 向构建期处理器暴露不可变注解元素；
- 生成成员、类型、注册表和诊断；
- 为 `Runtime` 注解发射静态注册表。

运行时只能查询生成的注册表。它 MUST NOT 从类文件、源码、包或模块元数据中发现注解。

### 1.2 注解 vs 协议 vs 显式 API

| 机制 | 主要职责 | 运行时行为 | 替代规则 |
| --- | --- | --- | --- |
| `protocol` | 行为合同与动态派发 | 有；协议派发 | 注解 MUST NOT 替代协议 |
| 显式 API | 命名操作、状态、生命周期、错误 | 有 | 注解 MAY 去掉样板，但生成代码 MUST 调用显式 API |
| 注解 | 编译期元数据、检查、生成意图 | 无运行时对象；可选静态注册表查询 | 注解 MUST NOT 隐藏必需的显式 API |

示例：

- `@Serializable` 可以生成 codec，但 codec 类型及其方法仍是显式公共 API。
- `@HttpRoute` 可以生成路由表，但 handler 方法仍是带显式签名的显式方法。
- `@Sql` 可以生成 DAO 方法体，但 SQL 文本、参数和返回类型仍在源码中可见。
- `@Value` 可以生成 `equals`/`toString`/`copy`，但类、字段和构造器仍是显式的。

### 1.3 禁止行为

注解 MUST NOT：

- 引入运行时反射、类路径扫描、动态类加载或动态代理；
- 在运行时执行处理器；
- 改变控制流、对象身份、内存策略、所有权或错误通道；
- 在生成源码之外静默注册服务、路由、codec 或 DI 图；
- 绕过类型检查、`Result`、`@MustUse` 或资源 `close()`；
- 替代调用方需要发现、测试或配置的显式 API。

`@arc` 和 `@gc` 不是本系统中的注解。使用它们是编译错误。

### 1.4 成功标准

只有在以下条件满足时，注解设计才算成功：

- 生成代码可见、确定、可独立测试；
- 读者能看出正在生成或调用哪个显式 API；
- 失败尽可能在编译期可诊断；
- 运行时没有隐藏发现路径；
- 注解可以通过机械迁移移除，回到显式代码。

## 2. XNull 约束与适用性

### 2.1 影响设计的约束

| 约束 | 对注解的后果 |
| --- | --- |
| 无默认参数、命名参数或可变参数 | 注解参数是位置参数；可选尾字段依赖声明默认值 |
| 协议是主要抽象 | 行为留在协议中；注解只生成/校验实现 |
| 无 `async` / `await` | 注解不能发明异步控制流或调度 |
| 泛型有限，无泛型协议 | 当前实现中 `@Builder`/`@Delegate` 非泛型；泛型扩展是开放项 |
| 无运行时反射 | 无注解发现、类加载、动态代理或运行时 DI |
| 无源码级内存策略 | `@arc`/`@gc` 非法；注解不能选择 ARC/GC/栈 |
| 显式错误模型 | 生成的失败 API MUST 返回 `Result`；无隐藏异常 |
| 显式资源生命周期 | 注解可以生成包装器，但 `close()` 仍显式且幂等 |
| 名义类型，无结构类型 | 生成类型是有稳定名字的显式声明 |
| 类静态继承，仅协议派发 | 注解不能创建可覆盖方法槽或类层次多态 |

### 2.2 适合的问题

| 问题 | 为什么适合注解 | 典型产物 |
| --- | --- | --- |
| 外部名称映射 | 字段/类型元数据是静态的 | JSON/CSV/YAML/TOML/XML 映射 |
| 重复生成成员 | 规则统一且局部 | `equals`/`toString`/`copy`/`withX` |
| 声明式路由/绑定 | 路径和参数角色是静态的 | 路由表、binder 函数 |
| SQL/行映射 | SQL 文本和列名是静态的 | DAO 方法体、行 mapper |
| FFI 布局 | 布局规则是编译期的 | 布局检查、偏移、对齐诊断 |
| 测试/作业发现 | 声明是静态的 | 生成的测试清单或作业表 |
| 能力清单 | 名字和描述是静态的 | tool/resource/prompt 表 |
| 校验规则 | 约束是静态的 | 校验器函数和错误路径 |

### 2.3 不适合的问题

| 问题 | 为什么不适合注解 | 改用 |
| --- | --- | --- |
| 运行时服务定位 | 需要发现和可变注册表 | 显式构造器/参数注入 |
| 运行时动态改路由 | 路由集不是静态的 | 显式 router API |
| 事务/重试/熔断行为 | 运行时改变控制流和策略 | 显式包装器/组合器 |
| 分布式调度 | 需要持久化和协调 | 显式 scheduler/service |
| 内存策略选择 | 语言禁止 | 第 4 部分的编译器/运行时规则 |
| 安全授权 | 需要运行时策略和上下文 | 显式授权 API + 审计 |
| 惰性依赖图 | 隐藏构造顺序和生命周期 | 显式 factory/构造器 |

### 2.4 适用性决策表

| 问题 | 是 | 否 |
| --- | --- | --- |
| 信息在编译期已知且为常量？ | 注解候选 | 使用显式运行时 API |
| 只生成/校验局部声明？ | 候选 | 使用协议/服务 |
| 生成代码能作为普通源码阅读和测试？ | 候选 | 拒绝该注解 |
| 需要运行时发现、反射或动态加载？ | 拒绝 | 候选 |
| 会改变控制流、内存或错误通道？ | 不要用注解；用显式 API | 候选 |

## 3. 语法与语义

第 2 部分 §12 是语法摘要。本节是完整合同。

### 3.1 声明

```x
@annotation Marker {
    final String name = "";
    final Int priority = 0;
}
```

- 注解声明是编译期类型；不产生运行时注解对象。
- 字段 MUST 为 `final`。
- 字段类型 MUST 是编译期常量类型：`Bool`、整数类型、`Float`/`Double`、`Char`、`String`、简单枚举、上述类型的常量数组、嵌套注解类型，以及 `Type`/`TypeRef` 引用。
- 字段 MAY 有编译期常量初值。没有初值的字段在每个使用点都是必填。
- 注解 MUST NOT 声明方法、构造器、`deinit`、静态成员、泛型参数、继承或协议实现。
- 注解不能被 `new`，也不能作为运行时值传递。

### 3.2 使用

```x
@Marker
class Device { }

@Marker("device", 2)
class Router { }
```

- 使用形式为 `@Name` 和 `@Name(arg1, arg2, ...)`。
- 参数是位置参数，按字段声明顺序绑定。
- 尾部可选字段可省略；中间字段不能跳过。
- 不支持命名参数、可变参数和运行时表达式。
- 参数 MUST 是可赋给字段类型的编译期常量。
- 多余参数、缺少必填参数、类型不匹配都是编译错误。

### 3.3 目标

11 个目标是：

| 目标 | 适用位置 |
| --- | --- |
| `Package` | 包声明 |
| `Type` | class、struct、enum、singleton、factory、annotation、extension |
| `Annotation` | `@annotation` 声明（元注解） |
| `TypeParameter` | 类型参数声明 |
| `Field` | 字段声明 |
| `Method` | 方法声明 |
| `Constructor` | 构造器声明 |
| `Deinit` | `deinit` 声明 |
| `Parameter` | 方法/构造器参数 |
| `TypeUse` | 字段类型、参数类型、返回类型、局部变量类型 |
| `EnumItem` | 枚举项 |

未写 `@Target` 的注解可用于声明目标，但不能用于 `TypeUse`。`TypeUse` MUST 显式声明。块注解 `@tasks`/`@arena` 归第 6 部分所有，不属于 11 个通用声明目标。

### 3.4 TypeUse

类型使用注解使用前缀形式：

```x
@NonEmpty List<String> names;
```

它记录为 `AnnotationTarget.TypeUse`，不是声明注解。目标名由外层声明推导：

- 字段：`<owner>#<field>`；
- 参数：`<owner>#<method>(<paramTypes>)#<index>`；
- 返回：`<owner>#<method>(<paramTypes>)#return`；
- 局部变量：`<owner>#<method>(<paramTypes>)#local:<name>`。

TypeUse 注解 MUST NOT 用于泛型实参、表达式、控制体或类型参数声明。

### 3.5 消歧

在声明前缀处，注解按声明的目标绑定：

- 只有 `TypeUse`：绑定到后面的类型使用；
- 只有声明目标：绑定到声明；
- 同时有 `TypeUse` 和声明目标：编译错误；必须拆分或收窄注解。

只有声明目标的注解永远不会被重新解释为类型使用注解。

### 3.6 保留策略

| 保留策略 | 编译器 | 构建产物 | 运行时 |
| --- | --- | --- | --- |
| `Source` | 处理器可见 | 不保留 | 不可查询 |
| `Binary` | 处理器可见 | 工具/IDE 元数据 | 不可查询 |
| `Runtime` | 处理器可见 | 编译器生成的静态注册表 | 可通过 `AnnotationRegistry` 查询 |

默认保留策略是 `Binary`。

`Runtime` 不是反射。编译器生成静态表；运行时不读取类文件、源码、包或模块元数据。

### 3.7 Repeatable

- `@Repeatable` 允许同一目标多次使用。
- 使用保持源码顺序。
- 编译器按注解类型/目标记录从 1 开始的 `repeatIndex`。
- 重复使用未标 `@Repeatable` 的注解是编译错误。
- `@Repeatable` 用在非注解声明上或带参数是编译错误。

### 3.8 诊断

注解语法/语义错误使用稳定码：

| 码 | 含义 | 状态 |
| --- | --- | --- |
| `AN0001` | 未知注解 | implemented |
| `AN0002` | 注解不允许用于该目标 | implemented |
| `AN0003` | 未标 `@Repeatable` 的重复注解 | implemented |
| `AN0004` | 缺少必填参数 | implemented |
| `AN0005` | 参数过多 | implemented |
| `AN0006` | 参数类型不匹配 | implemented |
| `AN0007` | 参数不是编译期常量 | implemented |
| `AN0008` | 注解字段/默认值非法 | implemented |
| `AN0009` | `@Target` 非法 | implemented |
| `AN0010` | `@Retention` 非法 | implemented |
| `AN0011` | `@Repeatable` 非法 | implemented |
| `AN0012` | `@ReadOnly` 写违规 | implemented |
| `AN0013` | `@Override` 签名不匹配 | implemented |
| `AN0014` | 使用已废弃声明 | implemented（warning） |
| `AN0015` | `@SuppressWarnings` 码非法/不支持 | implemented（warning） |
| `AN0016` | 处理器未启用/未知 | planned |
| `AN0017` | 处理器阶段/轮次违规 | planned |
| `AN0018` | 生成声明冲突 | planned |
| `AN0019` | 注册表版本不匹配 | planned |
| `AN0020` | 注解用于不支持的声明/表达式/块 | implemented |
| `AN0021` | A8 要求 class；`@Value` 要求字段全 final | implemented |
| `AN0022` | 构造器参数与字段不匹配 | implemented |
| `AN0023` | 生成方法与已有方法冲突 | implemented |
| `AN0024` | 生成的 builder 类已存在 | implemented |
| `AN0025` | 泛型 `@Builder` 不支持 | implemented |
| `AN0026` | `@Delegate` 方法冲突 | implemented |
| `AN0027` | `@Delegate` 目标不是 class | implemented |
| `AN0028` | `@Delegate` 目标是泛型 | implemented |

领域处理器使用保留区段：

- `AN0100`–`AN0199`：处理器清单、调度、生成和注册表管线；
- `AN1000`–`AN1999`：领域专用诊断，按包分配并记录在包注解合同中。

领域诊断码在包的注解表和生成源码测试中出现前不算稳定。

### 3.9 限制

注解 MUST NOT 用于：

- 表达式；
- 控制体；
- 泛型实参；
- 类型参数声明（`TypeUse` 是类型使用位置，不是类型参数声明）；
- 运行时值；
- 改变内存策略或对象模型规则。

## 4. 内建注解

### 4.1 完整表

| 注解 | 用途 | 目标 | 保留 | 强制程度 | 诊断 | 示例 | 反例 | 状态 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `@Target` | 限制注解目标 | Annotation | Binary | 是 | `AN0009` | `@Target(Field)` | `@Target(Expr)` | implemented |
| `@Retention` | 选择保留策略 | Annotation | Binary | 是 | `AN0010` | `@Retention(Runtime)` | `@Retention(Class)` | implemented |
| `@Repeatable` | 允许重复并保序 | Annotation | Binary | 是 | `AN0011` | 重复的 `@Tag` | 重复未标重复的注解 | implemented |
| `@ReadOnly` | 字段对外只读 | Field | Binary | 是 | `AN0012` | `@ReadOnly Int count` | 外部写 | implemented |
| `@WriteOnly` | 标记只写字段 | Field | Binary | 仅识别 | — | `@WriteOnly String secret` | 把它当安全边界 | implemented（识别） |
| `@Override` | 要求匹配协议方法 | Method | Binary | 是 | `AN0013` | `@Override String describe()` | 标记父类方法 | implemented |
| `@Deprecated` | 使用点警告 | Declaration | Binary | 是（warning） | `AN0014` | `@Deprecated void old()` | 只写注释不标注解 | implemented |
| `@SuppressWarnings` | 抑制指定诊断 | Declaration | Source | 是 | `AN0015` | `@SuppressWarnings("AN0014")` | 抑制未知/不支持码 | implemented |
| `@MustUse` | 结果必须使用 | Type/Method | Binary | 语言规则 | — | 语言规则作用于 `Result` | 当作普通用户注解 | implemented（规则） |
| `@Immediate` | 预留执行提示 | Declaration | Binary | 否 | 非法组合用 `AN0020` | — | 依赖调度语义 | reserved |
| `@NoAlloc` | 预留分配提示 | Declaration | Binary | 否 | `AN0020` | — | 声称分配保证 | reserved |
| `@Pure` | 预留纯函数提示 | Method | Binary | 否 | `AN0020` | — | 据此优化 | reserved |
| `@Sendable` | 预留跨任务提示 | Type/Method | Binary | 否 | `AN0020` | — | 当作安全证明 | reserved |
| `@tasks` | 结构化任务作用域 | Block（第 6 部分；不属于 11 个通用目标） | Source | 第 6 部分语义 | 第 6 部分诊断 | `@tasks { ... }` | 当普通声明注解用 | planned（第 6 部分） |
| `@arena` | 区域分配作用域 | Block（第 6 部分；不属于 11 个通用目标） | Source | 第 6 部分语义 | 第 6 部分诊断 | `@arena { ... }` | 用在声明上 | planned（第 6 部分） |

### 4.2 说明

- `@WriteOnly` 只识别，不强制。它 MUST NOT 被描述为安全边界。
- `@MustUse` 是语言规则，不是 `@annotation` 声明。不能作为普通用户注解使用。
- 预留注解在其合同和检查冻结前 MUST NOT 改变语义。
- `@tasks`/`@arena` 是第 6 部分拥有的块注解；本文件不重新定义其语法和语义。

## 5. 派生注解（A8）

A8 派生注解由编译器实现。它们生成显式成员，不生成运行时反射或隐藏行为。

### 5.1 通用规则

- 目标只能是 `class`。`struct`、`enum`、`protocol`、`annotation` 都会以 `AN0021` 拒绝。
- 类构造器参数 MUST 按顺序和类型匹配实例字段（`AN0022`）。
- 生成成员 MUST NOT 与已有成员冲突（`AN0023`）。
- 生成声明带 generated 标记且确定性。
- 失败是原子的：不保留部分生成成员。
- 生成代码是普通 XNull 源码，可阅读、测试和审计。

### 5.2 `@Value`

| 项 | 合同 |
| --- | --- |
| 前置条件 | `class`；所有实例字段 `final`；构造器匹配字段 |
| 生成 | `equals(other)`、`toString()`、`copy()` |
| 不生成 | `hash()`、访问器、setter、深拷贝、运行时反射 |
| 诊断 | `AN0021` 非 class/非 final；`AN0022` 构造器不匹配；`AN0023` 方法冲突 |
| 状态 | implemented；浅校验（只检查 final 字段） |

当前实现的 `@Value` 校验刻意保持浅层。它不证明每个引用字段都可值比较。生成的相等比较按语言字段相等规则比较字段；需要更深比较的类型 MUST 显式实现，或等待 §14 的开放决策。

### 5.3 `@Data`

| 项 | 合同 |
| --- | --- |
| 前置条件 | `class`；构造器匹配字段 |
| 生成 | `equals(other)`、`toString()`、`copy()` |
| 不生成 | `hash()`、访问器、setter、深拷贝 |
| 诊断 | `AN0021` 非 class；`AN0022` 构造器不匹配；`AN0023` 方法冲突 |
| 状态 | implemented；不生成 `hash()` |

### 5.4 `@Copy`

| 项 | 合同 |
| --- | --- |
| 前置条件 | `class`；构造器匹配字段 |
| 生成 | `copy()` 和每个实例字段一个 `with<Field>(value)` |
| 诊断 | `AN0022`；已有方法冲突 `AN0023` |
| 状态 | implemented |

### 5.5 `@Builder`

| 项 | 合同 |
| --- | --- |
| 前置条件 | 非泛型 `class`；构造器匹配字段 |
| 生成 | `<Type>Builder`，含 `with<Field>(value)`、`build()`；缺失必填字段时 `build()` panic |
| 诊断 | `AN0022`；builder 类已存在 `AN0024`；泛型类 `AN0025` |
| 状态 | implemented；仅非泛型 |

### 5.6 `@Delegate`

| 项 | 合同 |
| --- | --- |
| 前置条件 | `class`；一个或多个字段标 `@Delegate`；目标是非泛型 class |
| 生成 | 转发目标实例方法的实例方法 |
| 不生成 | 静态转发、协议推导、动态代理 |
| 诊断 | 方法冲突 `AN0026`；目标不是 class `AN0027`；泛型目标 `AN0028` |
| 状态 | implemented；仅非泛型 |

### 5.7 实现范围与限制

| 能力 | 已实现 | 限制 |
| --- | --- | --- |
| `@Value` | 是 | 仅 class；final 字段；浅校验；无 `hash()` |
| `@Data` | 是 | 仅 class；无 `hash()`；无访问器 |
| `@Copy` | 是 | 仅 class；构造器必须匹配字段 |
| `@Builder` | 是 | 仅非泛型 class |
| `@Delegate` | 是 | 仅非泛型目标 class |
| 生成代码标记 | 是 | 生成成员带 A8 标记 |
| 失败原子性 | 是 | 诊断阻止部分展开 |
| 泛型扩展 | 否 | 开放决策 |

这些限制是 API 可见的。未来实现 MUST NOT 静默改变生成名、成员集合或诊断。

### 5.8 示例

```x
@Value
class Point {
    final Int x
    final Int y

    Point(Int x, Int y) {
        self.x = x
        self.y = y
    }
}
```

生成 API（概念性、确定性）：

```x
Bool equals(Point other)
String toString()
Point copy()
```

```x
@Builder
class ServerOptions {
    final String host
    final Int port

    ServerOptions(String host, Int port) {
        self.host = host
        self.port = port
    }
}
```

生成：`ServerOptionsBuilder.withHost(String)`、`withPort(Int)`、`build()`。缺失字段会让 `build()` 以稳定消息 panic。

## 6. 领域注解与处理器模型

### 6.1 归属与文件布局

- 领域注解归拥有该能力的包，不放进 `xdk.annotations`。
- 每个注解是一个 PascalCase 类型，单独成文件，例如 `HttpRoute.x`。
- 处理器是构建期类型，不是运行时包类型。
- 生成源码放在 `<package>/generated/<Name>Generated.x`，带 generated 标记。
- 构建清单显式列出启用的处理器。依赖不会自动启用处理器。

### 6.2 分类

| 类别 | 示例 | 原因 |
| --- | --- | --- |
| 必须生成代码 | `@Serializable`/`@JsonName`、`@HttpRoute`/`@Header`/`@Query`、`@Sql`/`@Param`/`@Row`、`@Packed`/`@Align`、`@CliCommand`/`@Option`/`@Arg`、`@TestCase`/`@Scheduled` | 映射或注册是静态且机械的 |
| 编译期校验 | `@Validate`/`@Min`/`@Max`/`@Pattern`/`@Email` | 规则可在运行时前检查 |
| 更适合显式 API | `@Retryable`、`@Cacheable`、`@CacheEvict`、`@Metered`、`@Traced`、`@Audited` | 它们改变控制流/包装；显式包装器更易测试和推理 |
| 延后 | 依赖未实现包或运行时设施的注解 | 尚无处理器、生成物或场景 |

完整的 93 条目录和 75 包采用矩阵维护在：

- [`design/ANNOTATION-CATALOG.md`](../design/ANNOTATION-CATALOG.md)
- [`design/ANNOTATION-ADOPTION.md`](../design/ANNOTATION-ADOPTION.md)

本方案定义模型；目录定义每个注解的精确字段和状态；采用矩阵定义每个包的预期用法。

### 6.3 75 包分析

75 个包/包组分为四类采用方式：

| 类别 | 包（示例） | 注解使用 | 状态 |
| --- | --- | --- | --- |
| 语言/编译器 | `xdk.annotations` | 元模型、注册表、处理器合同 | 14 类型已实现 |
| 核心值/API | `xdk.errors`、`xdk.runtime`、`xdk.meta`、`xdk.bytes`、`xdk.text`、`xdk.collections`、`xdk.math`、`xdk.time`、`xdk.io`、`xdk.fs`、`xdk.sys`、`xdk.log`、`xdk.config`、`xdk.cli`、`xdk.execution` | A8 派生成员、`@Override`、`@Deprecated`、迁移 | A8/编译器已实现；领域注解 planned |
| 领域代码生成 | `xdk.net.http`、`xdk.net.websocket`、`xdk.jwt`、`xdk.sql`、`xdk.codec`、`xdk.yaml`、`xdk.toml`、`xdk.xml`、`xdk.validate`、`xdk.cli`、`xdk.device`、`xdk.serial`、`xdk.gpu`、`xdk.tensor`、`xdk.linalg`、`xdk.db`、`xdk.api`、`xdk.mcp`、`xdk.ml`、`xdk.agent` | 包拥有的注解 + 构建期生成器 | planned |
| 显式 API 优先 | `xdk.cache`、`xdk.resilience`、`xdk.metrics`、`xdk.trace`、`xdk.audit`、`xdk.schedule`、`xdk.test` | 只在生成/校验明显局部时用注解；否则显式 API | 混合 planned |

完整 75 行矩阵见附录 B。包不能仅因为出现在附录 B 中就声称领域注解已实现；包必须满足 §0.5。

### 6.4 处理器架构方案

| 方案 | 描述 | 优点 | 缺点 |
| --- | --- | --- | --- |
| A. 纯编译器 | 所有注解都在编译器内处理 | 简单、确定、单一管线 | 每个领域变更都要发编译器；包归属差；编译器膨胀 |
| B. 完整处理器调度器 | 通用 `AnnotationProcessor` 插件调度器，含发现和依赖图 | 可扩展；统一合同；生态处理器 | 复杂；插件发现/安全；有“类运行时魔法”风险；领域包出现前过度设计 |
| C. 混合（推荐） | 语言/A8 内建在编译器；领域包使用清单显式列出的构建期生成器，共享 `AnnotationProcessor` 合同和阶段 | 编译器核心小；包归属清晰；无运行时发现；清单确定 | 需要清单 schema 和生成器沙箱；处理器依赖仅限构建期 |

推荐：**方案 C**。编译器仍是注解语法、目标、保留、内建、A8 和注册表的唯一权威。领域包提供显式启用并沙箱化的构建期生成器。第一实现不需要通用插件发现机制。

该推荐在 owner 签字前是 `OPEN`（§14，OPEN-1）。如果生态处理器需要稳定调度器，方案 B 仍是未来扩展。

### 6.5 处理器阶段

```text
Resolve → Validate → Generate（固定点） → Finalize
```

- **Resolve**：读取声明和注解集合；解析类型和符号。
- **Validate**：检查目标、常量、语义约束、冲突和生成名可用性。
- **Generate**：产生源码/声明；生成声明进入下一轮。
- **Finalize**：发出最终元数据/诊断；MUST NOT 生成新声明。

处理器声明支持的阶段。调度器只按顺序调用已声明阶段。`Generate` 可以多轮执行，直到不再产生新声明。

### 6.6 清单、沙箱、确定性、原子性

| 规则 | 要求 |
| --- | --- |
| 清单 | 显式处理器列表、选项、输出根；不隐式激活依赖 |
| 沙箱 | 只读输入 AST/元素视图；无网络、任意文件写、进程、反射或运行时加载 |
| 确定性 | 相同输入 + 处理器集合 + 选项 + 编译器版本 = 字节级相同输出和稳定诊断顺序 |
| 原子性 | 任一错误回滚整个处理器批次；无半生成文件或半修改 AST |
| 缓存 | 输入哈希 + 处理器身份/版本 + 选项参与增量缓存 |
| 输出 | 生成源码只在声明的输出根下，带 generated 标记 |
| 诊断 | 稳定码；适用时带源码位置；不含绝对路径/时间戳/随机值 |
| 安全 | 生成代码是普通源码，按手写代码审查/测试 |

### 6.7 运行时注册表

- 只有 `Runtime` 注解进入注册表。
- 注册表格式带版本；当前编译器使用版本 1。
- 注册表构造后不可变，可并发只读。
- 查询未命中返回空集合，不返回 `null`。
- 运行时查询 API 在 `xdk.annotations`；其他包不得实现竞争注册表。
- `Source` 和 `Binary` 注解运行时不可查询。
- 注册表条目保留重复顺序和从 1 开始的 `repeatIndex`。

### 6.8 状态

领域处理器为 `planned`。编译器当前实现注解解析、内建、A8 和静态注册表。包的注解在其处理器、生成物、诊断和场景存在前不算 `implemented`。

## 7. 与其他部分的关系

| 部分 | 负责 | S3 关系 |
| --- | --- | --- |
| 第 0 部分 | 能力地图、应用边界 | S3 增加注解能力行；不改变应用边界 |
| 第 1 部分 | 词法、类型、表达式、语句、泛型、错误核心 | S3 使用其语法和类型规则；不重新定义 |
| 第 2 部分 | 对象模型、声明、协议、struct、enum、可见性、注解语法摘要 | S3 拥有完整注解执行模型；第 2 部分 §12 是摘要并指向这里 |
| 第 4 部分 | 内存策略、ARC/GC、生命周期、FFI 所有权 | S3 不能改变内存策略；`@arc`/`@gc` 非法 |
| 第 5 部分 | `Result`、`try`、`Error`、`ErrorKind`、错误观察 | 生成的失败 API 使用 `Result`；S3 不重新定义错误 |
| 第 6 部分 | 任务、取消、超时、同步 | `@tasks`/`@arena` 块语义归第 6 部分；S3 只定义注解语法边界 |
| 第 7 部分 | XDK 包目录、包归属、API 命名 | 领域注解归 XDK 包；S3 定义模型，不定义包 API |
| 第 8 部分 | 工具链、构建、CLI、FFI 合同 | 处理器是构建期工具链输入；S3 定义合同，第 8 部分实现构建 |
| 第 9 部分 | IDE/编辑器合同 | IDE 读取注解元数据和生成源码导航；S3 定义暴露内容 |
| 第 10 部分 | 工程清单、依赖、仓库、资源 | 处理器启用/选项是清单输入；S3 不定义清单语法 |

规则：

- S3 MUST NOT 重新定义对象模型、内存、错误、任务、XDK、工具链、IDE 或清单语义。
- 领域注解生成 API 时，API 的名字/生命周期/错误遵循所属部分和 S7 XDK 包合同。
- 注解与块/作用域交互（`@tasks`/`@arena`）时，第 6 部分拥有语义；S3 只拥有注解语法目标和保留边界。

## 8. API 文档注解面

### 8.1 注解是 API 合同

对公共类型或成员，其注解面是 API 合同的一部分。以下都是破坏性变更：

- 删除生成公共成员的注解；
- 改变 `@Target`/`@Retention`；
- 改变会改变生成行为的字段默认值；
- 改变生成名、签名或诊断码；
- 把处理器从显式改为隐式，或反之。

### 8.2 必填字段

每个公共 API 文档 MUST 包含：

| 字段 | 要求 |
| --- | --- |
| 类型/成员 | 规范名和签名 |
| 可用注解 | 注解名；没有就写“无” |
| 目标/保留 | 精确 `@Target` 和 `@Retention` |
| 所属包/处理器 | owner 包和处理器名 |
| 生成物 | 成员、类型、文件、输出路径 |
| 诊断 | 稳定码和严重度 |
| 状态 | `implemented`、`reserved`、`planned` 或 `open` |
| 反例 | 至少一个禁用用法或失败模式 |

### 8.3 模板

```markdown
### Annotation Surface

| Item | Value |
| --- | --- |
| Type/member | `Type.member(...)` |
| Available annotations | `@Foo`, `@Bar` |
| Target / retention | `Field` / `Source` |
| Owner / processor | `xdk.example` / `ExampleAnnotationProcessor` |
| Generated artifacts | `generated/TypeFoo.x`: `foo()`; members `a`, `b` |
| Diagnostics | `AN1001` missing field; `AN1002` duplicate name |
| Status | `planned`; processor not implemented |
| Counterexample | `@Foo` on a method |
```

### 8.4 状态词汇

| 状态 | API 文档含义 |
| --- | --- |
| `implemented` | 注解和处理器/生成已有测试 |
| `reserved` | 已识别；无生成 API，也无运行时语义 |
| `planned` | 合同已写；处理器/生成不存在 |
| `open` | 决策或 owner 签字缺失 |

文档 MUST NOT 在没有上述状态之一时使用“supported/支持”。

### 8.5 示例

已实现（A8）：

```markdown
| Available annotations | `@Value` |
| Target / retention | `Type` / `Source` |
| Owner / processor | compiler A8 |
| Generated artifacts | `equals`, `toString`, `copy` |
| Diagnostics | `AN0021`, `AN0022`, `AN0023` |
| Status | implemented; no `hash()` |
```

计划中（HTTP）：

```markdown
| Available annotations | `@HttpRoute`, `@Header`, `@Query`, `@Body`, `@StatusCode` |
| Target / retention | `Method`/`Parameter` / `Source` |
| Owner / processor | `xdk.net.http` / `HttpAnnotationProcessor` |
| Generated artifacts | `generated/routes.x`: route table and binder functions |
| Diagnostics | `AN1101` empty path; `AN1102` duplicate route; `AN1103` unsupported binding |
| Status | planned; processor not implemented |
```

### 8.6 评审规则

- 没有注解面的公共 API 文档视为不完整。
- “无”是合法注解面，但必须显式。
- planned 注解 MUST NOT 用现在时描述行为。
- 生成物 MUST 有稳定路径/名字或记录命名规则。
- 诊断 MUST 是稳定码，不能只有自由文本消息。

## 9. 兼容性与版本

### 9.1 注解 API

以下都是 API：

- 注解类型名和包；
- `@Target` 集合；
- `@Retention`；
- 字段名、类型、顺序和默认值；
- 处理器名、阶段、生成名和生成成员集合；
- 诊断码和严重度；
- 注册表格式和查询语义。

### 9.2 兼容变更

- 新增注解；
- 新增带默认值的可选尾字段；
- 新增目标（除非与 `TypeUse` 产生歧义）；
- 新增诊断码；
- 新增不与现有名字冲突的生成成员；
- 在显式清单启用后新增处理器。

### 9.3 破坏性变更

- 删除/重命名注解；
- 删除/收紧目标或保留；
- 删除/重排字段或改变默认值；
- 改变生成名/签名/可见性；
- 改变诊断码或严重度；
- 把处理器从显式激活改为隐式；
- 让 `Runtime` 元数据依赖反射或类加载。

### 9.4 弃用

- 公共注解/API 迁移 MUST 使用 `@Deprecated`。
- 被弃用注解至少保留一个次版本仍被识别。
- 不再生成代码的弃用注解 MUST 仍能解析并产生弃用警告。
- 删除需要主版本和迁移表。

### 9.5 注册表版本

- 注册表格式带版本；当前版本为 1。
- 运行时 MUST 拒绝版本不匹配，而不是静默误读元数据。
- 注册表顺序稳定：目标键、注解类型名、repeat index。
- `Source`/`Binary` 保留的条目 MUST NOT 出现。

### 9.6 无隐式语义变化

注解 MUST NOT 改变现有声明的含义，除非注解存在。给类型加注解不得改变无关类型、调用点或运行时行为，超出已记录的生成合同。

## 10. 示例与反例

每个示例展示声明 → 生成/显式 API → 运行时行为。任何示例都不使用反射、扫描或运行时处理器。

### 10.1 CLI

```x
@CliCommand("deploy", "Deploy an artifact")
class DeployCommand {
    @Option("--env", "-e") String env = "dev"
    @Arg("artifact") String artifact
}
```

生成：命令树节点和解析器 binder。运行时：parser 读取 `argv` 并写入字段；无全局命令注册表。反例：扫描包发现的全局 parser。

### 10.2 序列化

```x
@Serializable
class UserDto {
    @JsonName("user_id") final Long id
    @JsonName("display_name") final String name
}
```

生成：带 `encode`/`decode` 的 `UserDtoJsonCodec`。运行时：调用方调用显式 codec；不对字段反射。反例：运行时字段扫描或动态类加载。

### 10.3 校验

```x
@Validate
class SignupForm {
    @Email String email
    @Min(18) @Max(120) Int age
    @Pattern("^[a-z0-9_]+$") String handle
}
```

生成：`SignupFormValidator.validate(value)`，返回 `Result<Unit, ErrorGroup>`。运行时：显式调用校验器；错误路径稳定。反例：把校验藏在序列化器或 DI 容器中。

### 10.4 HTTP 路由

```x
class UserApi {
    @HttpRoute("/users/{id}", HttpMethod.Get)
    @StatusCode
    HttpResponse getUser(@Query("id") Long id, @Header("Accept") String accept) {
        // explicit handler body
    }
}
```

生成：路由表和参数 binder；handler 体保持显式。运行时：服务端派发到生成的 binder，再调用方法。反例：启动时扫描 handler 类。

### 10.5 SQL 行映射

```x
@Row
class UserRow {
    @Column("user_id") final Long id
    @Column("display_name") final String name
}

class UserDao {
    @Sql("SELECT user_id, display_name FROM users WHERE user_id = :id")
    Result<UserRow, Error> find(@Param("id") Long id) {
        // explicit fallback or generated body
    }
}
```

生成：行 mapper 和参数 binder。运行时：驱动返回 `SqlResult`；mapper 构造 `UserRow`；无反射。反例：运行时 ORM 扫描字段名。

### 10.6 FFI 布局

```x
@Packed
@Align(8)
@NativeLayout
class CHeader {
    @Align(4) Int code
    Long payload
}
```

生成：布局检查、偏移和对齐诊断。运行时：FFI 绑定使用同一布局；无动态布局探测。反例：运行时猜 C 布局。

### 10.7 测试与调度

```x
class UserTests {
    @Before void setUp() { }
    @TestCase("find missing") void findMissing() { }
    @After void tearDown() { }
}

class Jobs {
    @Scheduled("0 */5 * * * *") void refreshCache() { }
}
```

生成：测试清单和作业表。运行时：测试运行器/调度器查询生成的表；无命名约定扫描。反例：按方法名前缀发现测试。

### 10.8 反例

| 反例 | 为什么无效 |
| --- | --- |
| 运行时注解扫描 | 禁止；无反射/类路径扫描 |
| 纯注解 DI 容器 | 隐藏构造/生命周期；不是 XNull |
| `@Retry` 隐式改变控制流 | 使用显式重试包装器/组合器 |
| 在含引用字段的类上用 `@Packed` | 布局不可表示；拒绝 |
| 在 `struct` 上用 `@Value` | A8 要求 class；struct 已有值语义 |
| 在泛型类上用 `@Builder` | 当前不支持（`AN0025`） |
| 把 `@Delegate` 指向泛型类 | 当前不支持（`AN0028`） |
| 用 `@TestCase` 通过反射发现测试 | 生成清单是唯一发现路径 |

## 11. 验收标准

符合规范的实现 MUST 满足：

1. 注解语法、11 目标、三种保留、重复保序和诊断与 §3 一致。
2. 内建注解与 §4 一致，包括强制状态。
3. A8 生成成员和诊断与 §5、§14 状态一致。
4. 领域注解有 owner、target、retention、processor、生成物、诊断和状态；planned 注解不得描述为 implemented。
5. 处理器阶段、清单启用、沙箱、确定性、原子性和输出布局与 §6 一致。
6. 运行时元数据只通过生成的注册表读取；无反射/扫描/动态加载。
7. 公共 API 文档包含 §8 的注解面模板。
8. 执行 §9 兼容性规则。
9. §10 示例可被未来编译器/处理器实现验证，且不改变含义。
10. 文档链接、部分编号和文件名符合 11 部分结构（第 0 部分 + 第 1–10 部分）。

## 12. 从第 2 部分 §12 和注解设计文档迁移

- 第 2 部分 §12 仍是对象模型语法摘要；完整模型指向本文件。
- `ANNOTATION-SYSTEM.md` 是设计/实现概览；规范性注解语义必须服从本方案。
- `ANNOTATION-CATALOG.md` 是逐注解目录；模型和状态词汇必须服从本方案。
- `ANNOTATION-ADOPTION.md` 是 75 包采用矩阵；处理器架构和状态规则必须服从本方案。
- `ANNOTATION-PLAN.md` 是实施计划；可以描述工作项，但不得重新定义注解语义。
- 冲突时，注解语义以本方案为准；对象模型语法以第 2 部分为准；构建/工具链机制以第 8 部分为准。

## 13. 安全与安全边界

- 注解参数是编译期常量；无运行时表达式求值。
- 处理器是沙箱化构建期代码；无网络、任意文件写、进程执行、反射或类加载。
- 生成源码在审查/测试前不可信；带 generated 标记和确定性来源。
- `@WriteOnly` 不是安全边界。`@ReadOnly` 是编译期写检查，不是运行时访问控制。
- `@Deprecated` 是警告，不是删除机制。
- 运行时注册表数据是元数据，不是权限；授权和秘密不得依赖注解。
- 诊断消息 MUST NOT 包含秘密、绝对路径、时间戳或随机值。

## 14. 开放决策

以下决策明确为 `OPEN`，本文件不冻结它们。

| ID | 决策 | 现状 | 建议 | Owner 签字 |
| --- | --- | --- | --- | --- |
| OPEN-1 | 处理器架构 A/B/C | §6.4 分析 | C：编译器 A8 + 包构建期生成器 | pending |
| OPEN-2 | 领域诊断码分配 | §3.8 提议区段 | 按包分配 `AN1000–AN1999` 并记录到目录 | pending |
| OPEN-3 | `@Value`/`@Data` 的 `hash()` 生成 | 未生成 | 在 hash 合同存在前保持不生成 | pending |
| OPEN-4 | 泛型 `@Builder` | `AN0025` | 1.x 只支持非泛型 class；随泛型扩展再议 | pending |
| OPEN-5 | 泛型 `@Delegate` | `AN0028` | 1.x 只支持非泛型目标 class | pending |
| OPEN-6 | `@Value` 深字段校验 | 浅 final 字段检查 | 字段比较合同存在后增加值可比较检查 | pending |
| OPEN-7 | CLI/MCP/设备清单的 Runtime 保留 | Runtime/Source 混合 | 优先生成静态清单；只在运行时发现 API 用 Runtime | pending |
| OPEN-8 | 领域注解实现前冻结 API | planned | 每个包实现开始时冻结对应注解 | pending |

`OPEN` 项 MUST NOT 在包文档中描述为 implemented、冻结或保证。

## 附录 A：核心诊断码

| 区段 | Owner | 含义 |
| --- | --- | --- |
| `AN0001`–`AN0028` | 编译器/注解前端 | 语法、目标、保留、内建、A8 |
| `AN0100`–`AN0199` | 工具链/处理器调度 | 清单、阶段、生成、注册表管线 |
| `AN1000`–`AN1999` | 领域包 | 包专用注解诊断 |

## 附录 B：75 包采用矩阵

矩阵维护在 [`design/ANNOTATION-ADOPTION.md`](../design/ANNOTATION-ADOPTION.md)。共 75 行：1 个 annotations 包 + 15 core + 9 network + 17 platform + 24 utils + 9 solutions。每行记录声明注解、消费注解、处理器、生成物、具体类型/成员落点和状态。

下表是完整 75 行包矩阵。逐包权威细节在采用文档中。

| 类别 | 包 | 状态 |
| --- | --- | --- |
| annotations | `xdk.annotations` | 14 类型已实现；注册表已实现 |
| core 值/API | 15 包 | A8/编译器已实现；领域注解 planned |
| network/data | 9 包 | 领域注解 planned |
| platform/compute | 17 包 | 领域注解 planned |
| utils | 24 包 | A8/编译器已实现；领域注解 planned |
| solutions | 9 包 | 领域注解 planned |

| # | 包 | 声明领域注解 | 处理器/生成 | 状态 |
| ---: | --- | --- | --- | --- |
| 1 | `xdk.annotations` | 无领域注解 | 无（处理器合同由构建期实现） | 已实现（14 类型 + Registry） |
| 2 | `xdk.errors` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 3 | `xdk.runtime` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 4 | `xdk.meta` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 5 | `xdk.bytes` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 6 | `xdk.text` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 7 | `xdk.collections` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 8 | `xdk.math` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 9 | `xdk.time` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 10 | `xdk.io` | 无领域注解 | 编译器内建 | A8/编译器；部分采用 |
| 11 | `xdk.fs` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 12 | `xdk.sys` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 13 | `xdk.log` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 14 | `xdk.config` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 15 | `xdk.cli` | `@CliCommand`、`@CliSubcommand`、`@Option`、`@Arg` | CliAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 16 | `xdk.execution` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 17 | `xdk.net` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 18 | `xdk.net.uri` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 19 | `xdk.net.mime` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 20 | `xdk.net.tls` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 21 | `xdk.net.http` | `@HttpRoute`、`@Header`、`@Query`、`@Body`、`@StatusCode` | HttpAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 22 | `xdk.net.websocket` | `@WsHandler` | WebSocketAnnotationProcessor（Validate/Generate） | planned |
| 23 | `xdk.jwt` | `@JwtClaim`、`@JwtHeaderField` | JwtAnnotationProcessor（Validate/Generate） | planned |
| 24 | `xdk.sql` | `@Sql`、`@Param`、`@Row`、`@Column` | SqlAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 25 | `xdk.net.service` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 26 | `xdk.os` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 27 | `xdk.os.host` | 无领域注解 | 编译器内建 | A8/编译器；部分采用 |
| 28 | `xdk.os.cpu` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 29 | `xdk.os.memory` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 30 | `xdk.os.hardware` | `@Packed`、`@Align`、`@NativeLayout` | HardwareLayoutProcessor（Validate/Generate） | planned |
| 31 | `xdk.os.storage` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 32 | `xdk.os.gpu` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 33 | `xdk.os.firewall` | 无领域注解 | 标准 A8 / 审计处理器 | A8/编译器；部分采用 |
| 34 | `xdk.os.container` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 35 | `xdk.os.virt` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 36 | `xdk.os.service` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 37 | `xdk.gpu` | `@GpuKernel` | GpuAnnotationProcessor（Validate/Generate） | planned |
| 38 | `xdk.tensor` | `@TensorOp`、`@TensorSpec` | TensorAnnotationProcessor（Validate/Generate） | planned |
| 39 | `xdk.linalg` | `@LinalgOp` | LinalgAnnotationProcessor（Validate/Generate） | planned |
| 40 | `xdk.geo` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 41 | `xdk.serial` | `@SerialBinding` | SerialAnnotationProcessor（Validate/Generate） | planned |
| 42 | `xdk.device` | `@Device`、`@Gpio`、`@I2cAddress` | DeviceAnnotationProcessor（Validate/Generate） | planned |
| 43 | `xdk.codec` | `@Serializable`、`@JsonName`、`@CsvName` | CodecAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 44 | `xdk.crypto` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 45 | `xdk.compress` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 46 | `xdk.random` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 47 | `xdk.uuid` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 48 | `xdk.stats` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 49 | `xdk.functional` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 50 | `xdk.graph` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 51 | `xdk.reflect` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 52 | `xdk.toml` | `@TomlName` | TomlAnnotationProcessor（Validate/Generate） | planned |
| 53 | `xdk.yaml` | `@YamlName` | YamlAnnotationProcessor（Validate/Generate） | planned |
| 54 | `xdk.xml` | `@XmlName` | XmlAnnotationProcessor（Validate/Generate） | planned |
| 55 | `xdk.validate` | `@Validate`、`@Min`、`@Max`、`@Pattern`、`@Email` | ValidateAnnotationProcessor（Validate/Generate） | planned |
| 56 | `xdk.cache` | `@Cacheable`、`@CacheEvict` | CacheAnnotationProcessor（Validate/Generate） | planned |
| 57 | `xdk.queue` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 58 | `xdk.schedule` | `@Scheduled` | ScheduleAnnotationProcessor（Validate/Generate） | planned |
| 59 | `xdk.event` | 无领域注解 | 标准 A8 / 编译器内建 | A8/编译器；部分采用 |
| 60 | `xdk.resilience` | `@Retryable`、`@CircuitBreakerPolicy`、`@RateLimit`、`@TimeoutPolicy` | ResilienceAnnotationProcessor（Validate/Generate） | planned |
| 61 | `xdk.metrics` | `@Metered` | MetricsAnnotationProcessor（Validate/Generate） | planned |
| 62 | `xdk.trace` | `@Traced` | TraceAnnotationProcessor（Validate/Generate） | planned |
| 63 | `xdk.audit` | `@Audited` | AuditAnnotationProcessor（Validate/Generate） | planned |
| 64 | `xdk.terminal` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 65 | `xdk.i18n` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 66 | `xdk.test` | `@TestCase`、`@Before`、`@After`、`@Benchmark` | TestAnnotationProcessor（Validate/Generate） | planned |
| 67 | `xdk.jsonrpc` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 68 | `xdk.mcp` | `@Tool`、`@ToolParam`、`@Resource`、`@Prompt` | McpAnnotationProcessor（Validate/Generate） | planned |
| 69 | `xdk.ml` | `@ModelSpec`、`@MlPipeline` | MlAnnotationProcessor（Validate/Generate） | planned |
| 70 | `xdk.numerics` | 无领域注解 | 标准 A8 | A8/编译器；部分采用 |
| 71 | `xdk.db` | `@Entity`、`@Table`、`@Id`、`@Transactional` | DbAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 72 | `xdk.api` | `@Api`、`@Operation`、`@Middleware`、`@Inject`、`@Component`、`@Configuration`、`@Bean` | ApiAnnotationProcessor（Resolve/Validate/Generate） | planned |
| 73 | `xdk.agent` | `@AgentReceiver`、`@AgentProcessor`、`@AgentExporter`、`@PipelineSpec` | AgentAnnotationProcessor（Validate/Generate） | planned |
| 74 | `xdk.accel` | 无领域注解 | 无自有处理器；消费 GPU/Tensor 生成物 | A8/编译器；部分采用 |
| 75 | `xdk.embedded` | 无领域注解 | 无自有处理器；消费 Device/Serial/FFI 生成物 | A8/编译器；部分采用 |

包在满足 §0.5 前 MUST NOT 标为注解完成。
