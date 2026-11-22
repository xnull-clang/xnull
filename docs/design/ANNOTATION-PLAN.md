# XDK 注解实施计划（P1）

| 项 | 值 |
| --- | --- |
| 位置 | 注解层；语言/编译器/工具链前置计划 |
| 权威语义 | [`solution-03-annotation.md`](../solution-03-annotation.md)（S3 1.0.0）；Part 2 §12 是语法摘要 |
| 相关规范 | S1 `@mustUse`、S6 `@tasks`/`@arena`、S8 工具链 |
| IR v1 | [`ANNOTATION-IR.md`](ANNOTATION-IR.md) |
| 处理器清单 | [`ANNOTATION-PROCESSOR-MANIFEST.md`](ANNOTATION-PROCESSOR-MANIFEST.md) |
| 状态 | P1.0–P1.5 与 A8 5 个派生已实现（含限制）；A8 已迁入 Internal Processor 注册表（`a8Processors()`）；P1.6 平台处理器、A9、领域处理器为 planned；mini 1.0 平台工作包见 [`ANNOTATION-PLATFORM-PLAN.md`](ANNOTATION-PLATFORM-PLAN.md) |
| 约束 | 不再只写设计：P1 直接改 `src/mini`；不引入运行时反射/注解扫描 |
| 第一出口 | mini 已能解析、校验、生成注解元数据；`xdk.annotations` 14 类型可查询 |

---

## 1. 为什么注解必须先做

后续 2.x 包大量依赖“编译期生成”，而不是运行时反射：

- `@Serializable`/`@JsonName` → 序列化器；
- `@Validate`/`@Min`/`@Max`/`@Pattern` → 校验器；
- `@HttpRoute`/`@Header`/`@Query` → 路由表/参数绑定；
- `@Sql`/`@Param`/`@Row` → DAO/行映射；
- `@JwtClaim`/`@JwtHeaderField` → claims/header 映射；
- `@TestCase`/`@Scheduled` → 测试清单/作业注册；
- `@Packed`/`@Align`/`@Device`/`@GpuKernel` → FFI 布局/设备/算子入口。

没有注解，这些包只能：

1. 手写重复样板；或
2. 退化为运行时反射/类路径扫描；或
3. 用宏/代码复制绕过类型系统。

三条路都与 XNull 风格冲突。因此注解是 P1，不是“顺手补一个语法”。

---

## 2. 语言基线（S2 §12 摘要；完整方案见 S3）

### 2.1 声明

```x
@annotation Marker {
    final String name = "";
}
```

- 只允许 `final` 字段；
- 字段类型限编译期常量类型：`Bool`、整数、`Float`/`Double`、`Char`、`String`、简单枚举、常量数组、嵌套注解、类型引用字符串；
- 字段必须有编译期常量初值；
- 不允许方法、构造器、`deinit`、静态成员、泛型、继承、协议实现；
- 注解类型只在编译期存在，不生成运行时对象，不能 `new`，不能作为值传递。

### 2.2 使用

- 形式：`@Name` 或 `@Name(arg1, arg2, ...)`；
- 只支持位置参数；按字段声明顺序绑定；省略尾部字段用默认值；
- 参数必须是编译期常量；类型必须可赋给字段；
- 目标 11 项：`Package/Type/Annotation/TypeParameter/Field/Method/Constructor/Deinit/Parameter/TypeUse/EnumItem`；
- `TypeUse` 使用前缀形式 `@Foo Type`，允许字段类型、参数类型、返回类型、局部变量类型；必须显式 `@Target(TypeUse)`；
- 声明前缀消歧：仅 `TypeUse` → 类型使用；仅声明目标 → 声明；同时声明 `TypeUse` 与声明目标 → 编译错误；
- 不能用于表达式、控制体、类型实参、类型参数声明；
- 未知注解、错目标、错参数、重复注解都是编译错误；
- `@Repeatable` 允许同一目标重复，重复项按出现顺序保留；
- 注解不改变控制流/对象模型；`@arc`/`@gc` 不属于注解系统。

### 2.3 保留策略

| 策略 | 编译器 | 产物 | 运行时 |
| --- | --- | --- | --- |
| `Source` | 处理器可见 | 不保留 | 不可查询 |
| `Binary` | 处理器可见 | 元数据供工具/IDE | 不可查询 |
| `Runtime` | 处理器可见 | 编译器生成静态注册表 | 通过 `AnnotationRegistry` 只读查询 |

默认 `Binary`；`Runtime` 不是反射，不加载注解类、不扫描类路径。

---

## 3. 内建注解

| 注解 | 目标 | 强制 | 语义 | XDK 使用策略 |
| --- | --- | --- | --- | --- |
| `@ReadOnly` | 字段 | 是 | 外部只读，声明类型内可写 | 只在需要外部只读语义时使用 |
| `@Override` | 方法 | 使用即强制 | 必须匹配协议方法签名 | 允许；不要求每个实现都标注 |
| `@WriteOnly` | 字段 | 否 | 识别但不强制 | XDK 不使用；不得作为安全边界 |
| `@Target` | 注解 | 是 | 限制目标 | 编译期强制 |
| `@Retention` | 注解 | 是 | Source/Binary/Runtime | 编译期强制 |
| `@Repeatable` | 注解 | 是 | 允许重复使用 | 编译期强制；顺序保留 |
| `@Deprecated` | 声明 | 是（警告） | 使用点警告 | 用于 deprecated 命名空间/API |
| `@SuppressWarnings` | 声明 | 是（诊断） | 抑制指定诊断码 | 仅工具/诊断使用 |
| `@Immediate`/`@NoAlloc`/`@Pure`/`@Sendable` | — | 否 | 预留，不改变语义 | 语义冻结前禁止使用 |
| `@MustUse` | 语言规则 | 是 | `Result` 丢弃是编译错误 | 不是用户注解；不作为 `@annotation` 使用 |
| `@tasks`/`@arena` | 块注解 | 按 S6 | 并发/内存作用域 | 按 S6；不进入通用注解系统 |

---

## 4. XDK 使用边界

| 规则 | 内容 |
| --- | --- |
| 构建期 + 只读运行时 | 处理器/代码生成只在构建期；运行时只读 `AnnotationRegistry`；无 DI/序列化扫描 |
| 无通用反射 | 不做类路径扫描/动态加载；`xdk.reflect` 只读类型元数据，不承担注解查询 |
| 无隐式魔法 | 处理器必须显式启用；生成代码可审计；运行时不得靠注解隐式注册/分配 |
| 显式契约 | 生成代码仍需显式类型/方法；注解只减少样板，不绕过类型/错误/资源模型 |
| 最小内建集 | XDK 公共 API 优先使用 `@Deprecated`、`@ReadOnly`、`@Override` |
| 自定义注解 | 用户可声明；处理器可在构建期解释；运行时只读生成元数据 |
| 文档义务 | 包 README 若使用注解，必须列出目标、是否强制、失败诊断 |
| 兼容性 | 识别但不强制的注解不得被当作语义承诺；可被未来版本收紧 |

---

## 5. 决策冻结

| # | 决策 | 结论 |
| --- | --- | --- |
| D1 | `@Override` 是否进入 XDK 风格 | **允许**；使用即强制签名匹配；不要求每个实现都标注 |
| D2 | `@Deprecated` 是否产生警告 | **是**；1.x/2.x 均产生使用点警告 |
| D3 | `@Target`/`@Retention`/`@Repeatable` | **实现强制**；不是“识别不强制” |
| D4 | 自定义注解的用途 | **构建期处理器**可用；运行期无处理器、无扫描 |
| D5 | 注解字段默认值/位置参数 | 位置参数、尾部省略；不支持命名参数；`@Repeatable` 支持重复 |
| D6 | 块注解 `@tasks`/`@arena` | 归 S6；不进入通用注解系统 |
| D7 | 运行时注册表格式 | 编译器生成；带版本号；只读；不做反射 |
| D8 | 处理器失败原子性 | 生成失败不落半成品；不修改已有声明 |

---

## 6. 编译器/工具链工作项

| # | 工作项 | 产物 | 依赖 |
| --- | --- | --- | --- |
| A0 | 冻结目标/保留/诊断码/元数据格式 | 本文件 §2/§3/§9 + `AnnotationTarget`/`AnnotationRetention` | S3 §3 |
| A1 | 词法/语法：`@annotation` 声明与 `@Name(...)` 使用 | `AnnotationDecl`/`AnnotationUse` AST 节点 | A0 |
| A2 | 注解类型解析 | 同包/导入解析；未知注解诊断 | 包/导入系统 |
| A3 | 目标校验 | 11 项目标表；非法目标诊断 | A1/A2 |
| A4 | 常量参数求值 | 标量/枚举/数组/嵌套注解/类型引用；尾部默认值；额外/跳位参数诊断 | 常量求值器 |
| A5 | 重复/保留诊断 | `@Repeatable` 保序；未标重复报错；Source/Binary/Runtime | A2 |
| A6 | 强制内建 | `@ReadOnly` 字段写检查；`@Override` 签名匹配；`@Deprecated` 警告；`@SuppressWarnings` 诊断过滤 | 类型检查器/诊断系统 |
| A7 | 元数据生成 | `AnnotationRegistry` 静态表：目标索引、重复项、版本号、排序 | A1–A5 |
| A8 | 处理器调度 | Resolve → Validate → Generate → Finalize；多轮固定点；显式启用；沙箱 | A1–A7 |
| A9 | 工具链/IDE 只读提取 | 文档/IDE 可读编译期元数据；不做运行时反射 | S8 |
| A10 | 测试矩阵 | 声明/使用/目标/常量/重复/未知/内建/处理器/注册表 | A1–A9 |

A8/A9 状态：**A8 已实现全部 5 个（`@Value`/`@Data`/`@Copy`/`@Builder`/`@Delegate`）并由 `A8Processor` 注册表承载（无 `expandA8Class` 分派），限制见 Part 3 §5.7：`@Builder`/`@Delegate` 非泛型、`@Value`/`@Data` 不生成 `hash()`、`@Value` 浅校验；A9 planned**。完整清单、归属、验收见 [`ANNOTATION-CATALOG.md`](ANNOTATION-CATALOG.md)。不得把未实现部分或领域注解写成已实现。

禁止工作项：

- 运行期注解对象；
- 运行期注解处理器/运行时代码生成；
- 反射扫描/DI/ORM/序列化；
- 通过注解改变内存策略（`@arc`/`@gc` 永远非法）；
- 命名参数、注解继承、未标 `@Repeatable` 的重复注解。

---

## 7. XDK 包采用计划

| 范围 | 采用方式 |
| --- | --- |
| `xdk.tasks`/`xdk.sync` deprecated 命名空间 | 标 `@Deprecated`，产生使用警告；2.x 映射到 `xdk.execution` |
| `Result` | 继续使用语言 `@MustUse` 规则，不新增用户注解 |
| 字段只读 | 仅在确实需要“外部只读、内部可写”时使用 `@ReadOnly`；普通不可变用 `final` |
| 协议实现 | 可用 `@Override`；使用即强制匹配协议签名 |
| 预留性能注解 | 全部禁止，直到语义/验证/工具链冻结 |
| 用户自定义注解 | 不属于 XDK 公共 API；应用/生态可在构建期处理器中使用 |
| XDK 领域注解 | 由所属包声明并作为该包公共合同；处理器由包/项目显式启用；不塞进 `xdk.annotations` |

---

## 8. 阶段计划

| 阶段 | 内容 | 完成条件 |
| --- | --- | --- |
| P1.0 | 冻结 A0：目标 11、保留 3、诊断码、注册表格式 | 已实现；`AnnotationTarget`/`AnnotationRetention`/诊断码冻结 |
| P1.1 | 词法/语法/AST | 已实现；`@annotation` 与 `@Name(...)` 可解析，非法语法有诊断 |
| P1.2 | 类型/目标/重复/保留 | 已实现；未知/错目标/错参数/重复诊断 |
| P1.3 | 常量求值/默认值 | 已实现；标量/枚举/数组/嵌套注解/类型引用；尾部省略 |
| P1.4 | 内建强制 | 已实现；`@ReadOnly`、`@Override`、`@Deprecated`、`@SuppressWarnings` |
| P1.5 | 元数据/注册表 | 已实现；`AnnotationRegistry` 只读查询；版本/排序/重复项 |
| P1.6 | 处理器调度 | planned；四阶段、多轮固定点、显式启用、失败原子性 |
| P1.7 | 测试矩阵/文档 | 部分完成；编译器正/负例已存在；领域处理器生成场景待实现；包 README 注解清单已建立 |

> P1.0–P1.5 是 `xdk.annotations` 14 类型与编译器的最小闭环；P1.6 才允许领域处理器接入。不要先写 `@Serializable` 处理器再补编译器。mini 1.0 的 IR、清单、调度、生成源码、沙箱、诊断合并与领域闭环工作包见 [`ANNOTATION-PLATFORM-PLAN.md`](ANNOTATION-PLATFORM-PLAN.md)。

---

## 9. 诊断码（已冻结 2026-11-22）

| 码 | 含义 | 严重度 |
| --- | --- | --- |
| `AN0001` | 未知注解 | Error |
| `AN0002` | 注解不允许用于该目标 | Error |
| `AN0003` | 重复注解（未标 `@Repeatable`） | Error |
| `AN0004` | 缺少必填参数 | Error |
| `AN0005` | 参数过多 | Error |
| `AN0006` | 参数类型不匹配 | Error |
| `AN0007` | 参数不是编译期常量 | Error |
| `AN0008` | 注解字段默认值非法 | Error |
| `AN0009` | `@Target` 成员非法 | Error |
| `AN0010` | `@Retention` 成员非法 | Error |
| `AN0011` | `@Repeatable` 用法非法 | Error |
| `AN0012` | `@ReadOnly` 字段写违规 | Error |
| `AN0013` | `@Override` 签名不匹配 | Error |
| `AN0014` | 使用已废弃声明 | Warning |
| `AN0015` | `@SuppressWarnings` 码不存在/不可抑制 | Warning |
| `AN0016` | 处理器未启用/未知 | Error |
| `AN0017` | 处理器阶段/轮次违规 | Error |
| `AN0018` | 生成声明冲突 | Error |
| `AN0019` | 元数据/注册表版本不匹配 | Error |
| `AN0020` | 注解用于不支持的声明/表达式/块 | Error |
| `AN0021` | A8 注解要求 class；`@Value` 要求字段全 final | Error |
| `AN0022` | 构造器参数与字段顺序/类型不匹配 | Error |
| `AN0023` | 生成方法/成员与已有方法冲突 | Error |
| `AN0024` | 生成的 builder 类已存在 | Error |
| `AN0025` | 泛型 `@Builder` 暂不支持 | Error |
| `AN0026` | `@Delegate` 转发方法冲突 | Error |
| `AN0027` | `@Delegate` 目标不是 class | Error |
| `AN0028` | `@Delegate` 目标是泛型 class | Error |

冻结状态：**已冻结 2026-11-22**（执行 owner 签字）。`AN0001`–`AN0028`
为 P1 的稳定码集，不得重编号；新增只能追加 `AN0029+`。

规则：

- 诊断码稳定，不随实现改名；
- 同一错误只报一次，避免级联噪声；
- 生成失败返回诊断，不落半成品；
- 诊断消息不包含绝对路径/时间/随机值，保证可重现。

---

## 10. 验收谓词

- S3 与 S2 §12/XDK 文档无矛盾；
- 所有 XDK 注解使用都在允许清单内；
- 不存在类路径扫描/动态加载/运行期处理器；运行时查询只读生成注册表；
- 未知/非法目标/非法参数/重复注解有稳定诊断；
- `@ReadOnly` 强制；
- `@Override` 使用即强制匹配协议签名；
- `@Deprecated` 产生使用警告；
- `@Target`/`@Retention`/`@Repeatable` 强制并作为语义承诺；
- `@MustUse` 不被误用为用户注解；
- `@tasks`/`@arena` 仍归 S6；
- `xdk.reflect` 明确不返回注解；
- 生成源码/注册表确定性、可重现、带版本号。

---

## 11. 当前缺口

1. 编译器注解 AST/解析/目标/保留/常量/内建/Registry 已实现；证据见 `src/mini/tests/annotations*` 与 `src/mini/tests/xdk2/annotations_types/*`。
2. `xdk.annotations` 14 类型已实现；`src/xdk/annotations/Annotations.x` 与 `xdk2.sh` 场景通过。
3. 诊断码表 §9 已冻结（2026-11-22）；编译器已使用 `AN0001`–`AN0028`（A8 使用 `AN0021`–`AN0028`）。
4. 处理器调度器、生成目录、增量缓存、沙箱尚未实现（P1.6）。
5. 各包 README 的领域注解清单已建立；`ANNOTATION-CATALOG.md` 与 `ANNOTATION-ADOPTION.md` 是权威索引。
6. A8 派生已实现（含限制）；领域处理器仍为 planned；不得把领域注解写成已实现。
7. `@Serializable`/`@Validate`/`@HttpRoute` 等处理器必须等 P1.6 + 对应包实现后再接，不能先写处理器空壳。
