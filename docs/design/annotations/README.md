# `xdk.annotations` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.annotations` |
| 层 | annotations / `xdk.annotations` |
| 稳定性 | `preview`（设计基线；实现未开始） |
| 上游依赖 | 语言核心标量与容器（`String`、`Int`、`Long`、`Float`、`Double`、`Char`、`Bool`、`List`、`Map`）；无其他 XDK 包 |
| 下游使用 | 编译器前端/语义分析/生成器、构建调度器、运行时注册表查询方、IDE/文档工具、各领域注解 |
| 权威设计 | [`ANNOTATION-SYSTEM.md`](../ANNOTATION-SYSTEM.md) |
| 语言语法 | [`solution-02-object-programming.md`](../../solution-02-object-programming.md) §12（由 `ANNOTATION-SYSTEM.md` 升级） |
| 计划背景 | [`ANNOTATION-PLAN.md`](../ANNOTATION-PLAN.md) |
| 目录规范 | [`../core/README.md`](../core/README.md) |

---

## 1. 包定位

`xdk.annotations` 是 XNull 的**注解元模型与处理器合同包**，位于编译期层，先于 `xdk.errors` 和其他 core 包冻结。

它回答四个问题：

1. 注解可以放在哪些目标上（`AnnotationTarget`）；
2. 注解在编译产物和运行时如何保留（`AnnotationRetention`）；
3. 注解参数如何表示为不可变常量值树（`AnnotationValueKind`/`AnnotationValue`/`AnnotationInfo`/`AnnotationSet`）；
4. 编译期处理器如何读取元素、返回诊断与生成源码（`AnnotationElement`/`AnnotationDiagnostic*`/`AnnotationProcessor*`）。

它不回答：

- 具体领域注解的语义（`@Data`、`@Serializable`、`@Route` 等归所属包）；
- 编译器内部 AST/符号表；
- 构建系统如何调度、缓存、落盘；
- 运行时如何反射读取注解（**永远不做**）；
- 注解语言本身的解析规则（归语言规范与编译器）。

运行时只提供 `AnnotationRegistry` 的只读查询。`Runtime` 保留的注解由编译器生成静态注册表，**不是反射、不是类路径扫描、不是动态代理、不是注解类加载**。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 编译期契约 | 注解是声明、检查、生成入口；不是运行时魔法 |
| 无反射 | 不加载注解类、不扫描类路径、不读取类文件、不生成动态代理 |
| 生成而非反射 | `Runtime` 注解由编译器生成静态表，运行时只查表 |
| 不可变快照 | 值树、注解信息、集合、注册表、元素、上下文、结果构造后不可变 |
| 显式缺失 | 字段未提供用“映射中不存在”表达，不用 `null` 混淆 |
| 确定性 | 处理器输出可重现；生成源码/注册表格式带版本；不依赖时间/随机/绝对路径/哈希顺序 |
| 显式启用 | 处理器由构建清单显式启用；依赖包不能自动带入处理器 |
| 沙箱 | 处理器不得直接写文件、联网、反射、加载类、启动进程；生成源码通过结果返回 |
| 领域归属 | `xdk.annotations` 只放元模型、元注解、处理器合同；通用派生注解由语言/标准处理器定义，领域注解在领域包 |
| 无隐式全局 | 没有全局注解注册表、没有隐式 DI/路由/序列化扫描 |
| 诊断优先 | 用户错误返回 `AnnotationDiagnostic`，不抛异常；半成品不返回 |
| 追加兼容 | 目标/保留/字段/默认值/处理器行为都是 API；删除或收紧是破坏性变更 |

---

## 3. 14 类型索引

| # | 类型 | 种类 | 职责 | 文件 |
| --- | --- | --- | --- | --- |
| 1 | `AnnotationTarget` | enum | 11 个注解目标位置 | [`AnnotationTarget.md`](AnnotationTarget.md) |
| 2 | `AnnotationRetention` | enum | `Source`/`Binary`/`Runtime` 保留策略 | [`AnnotationRetention.md`](AnnotationRetention.md) |
| 3 | `AnnotationValueKind` | enum | 12 个常量值标签 | [`AnnotationValueKind.md`](AnnotationValueKind.md) |
| 4 | `AnnotationValue` | class | 不可变标签值树 | [`AnnotationValue.md`](AnnotationValue.md) |
| 5 | `AnnotationInfo` | class | 单次注解使用快照 | [`AnnotationInfo.md`](AnnotationInfo.md) |
| 6 | `AnnotationSet` | class | 同目标有序不可变集合 | [`AnnotationSet.md`](AnnotationSet.md) |
| 7 | `AnnotationRegistry` | class | 编译器生成的只读注册表 | [`AnnotationRegistry.md`](AnnotationRegistry.md) |
| 8 | `AnnotationElement` | class | 处理器看到的元素视图 | [`AnnotationElement.md`](AnnotationElement.md) |
| 9 | `AnnotationDiagnosticSeverity` | enum | `Error`/`Warning`/`Note` | [`AnnotationDiagnosticSeverity.md`](AnnotationDiagnosticSeverity.md) |
| 10 | `AnnotationDiagnostic` | class | 单条不可变诊断 | [`AnnotationDiagnostic.md`](AnnotationDiagnostic.md) |
| 11 | `AnnotationProcessorPhase` | enum | `Resolve`/`Validate`/`Generate`/`Finalize` | [`AnnotationProcessorPhase.md`](AnnotationProcessorPhase.md) |
| 12 | `AnnotationProcessorContext` | class | 单次处理器调用上下文 | [`AnnotationProcessorContext.md`](AnnotationProcessorContext.md) |
| 13 | `AnnotationProcessingResult` | class | 诊断 + 生成源码结果 | [`AnnotationProcessingResult.md`](AnnotationProcessingResult.md) |
| 14 | `AnnotationProcessor` | protocol | 非泛型处理器合同 | [`AnnotationProcessor.md`](AnnotationProcessor.md) |

计数：5 个 enum + 8 个 class + 1 个 protocol = 14 个公开类型文件；加本 README 共 15 个文件。没有小写辅助文件。

---

## 4. 顺序与依赖（P1）

2.x 逻辑顺序调整为：

```text
P1 annotations
  → P2 runtime/execution 前置
    → P3 core（errors/runtime/meta/bytes/text/collections/math/time/io/fs/sys/log/config/cli/execution）
```

1.x 的 W01–W15 / 01–16 编号只作历史账本，不用于 2.x 排序。

规则：

- `annotations` 先冻结，因为编译器/工具链/各领域包都依赖注解目标、保留、值树和处理器合同。
- 2.x 顺序以 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准；1.x 旧账本不回改。
- 本包不依赖 `xdk.errors`、`xdk.runtime`、`xdk.meta`；处理器结果用诊断对象，不用 `Result`，因此不会形成 `annotations → errors → annotations` 环。
- 领域注解包可以依赖本包；本包不得反向依赖领域包。

包内建议冻结顺序：

```text
AnnotationTarget
AnnotationRetention
AnnotationValueKind
AnnotationDiagnosticSeverity
AnnotationProcessorPhase
        ↓
AnnotationValue ⇄ AnnotationInfo
        ↓
AnnotationSet
        ↓
AnnotationRegistry
AnnotationElement
        ↓
AnnotationProcessorContext
AnnotationProcessingResult
        ↓
AnnotationProcessor
```

说明：

- `AnnotationValue` 与 `AnnotationInfo` 是**刻意互相引用**的值树对：`AnnotationInfo.values` 含 `AnnotationValue`，`AnnotationValue.Annotation` 负载含 `AnnotationInfo`。两者必须一起评审、一起冻结，不能只改一边。
- 五个 enum 没有互相依赖，可先冻结；它们只是标签/阶段/级别。
- `AnnotationSet` 依赖 `AnnotationInfo` 的 `target`/`targetName`/`repeatIndex` 不变量；`AnnotationRegistry` 依赖 `AnnotationSet` 的分组行为。
- `AnnotationElement` 独立于 `AnnotationSet` 的注册表用途，但共享同一套注解集合。
- `AnnotationProcessor` 只依赖 `AnnotationProcessorContext`/`AnnotationProcessingResult`/`AnnotationProcessorPhase`；不依赖注册表，避免把构建期处理器和运行时元数据耦合。

---

## 5. 编译器 / 运行时 / 工具链边界

| 边界 | 责任 | 不负责 / 禁止 |
| --- | --- | --- |
| 语言前端 | 解析 `@annotation` 声明与 `@Name(args)` 使用；位置参数；常量参数；目标语法 | 不做运行时注解对象 |
| 语义分析 | 解析注解类型；检查目标/未知/重复/参数类型；绑定字段；解析 `@Target`/`@Retention`/`@Repeatable` | 不执行处理器 |
| 常量求值 | 计算注解参数；尾部字段默认值；类型可赋值；数组/嵌套注解 | 不求值运行时表达式 |
| 处理器调度（构建期） | 读取处理器清单；按阶段/轮次调用；固定点；沙箱；增量缓存；生成目录 | 不在运行时执行处理器 |
| `xdk.annotations` | 元模型类型、值树、注册表查询、元素视图、诊断、处理器协议 | 不做反射/类路径扫描/动态代理/注解类加载 |
| 生成器 | 生成成员/类型/序列化器/路由表/注册表；确定性；来源标记；版本号 | 不手改生成代码；不产生半成品 |
| 运行时 | 只读 `AnnotationRegistry`；普通对象/容器 | 不加载注解类；不扫描；不动态注册 |
| 领域包 | 声明领域注解并标注 `@Target`/`@Retention`；启用处理器 | 不把领域注解塞进 `xdk.annotations` |
| IDE/文档 | 读取 `Binary` 元数据/生成源码；注解索引；生成代码导航 | 不依赖运行时反射 |
| 构建系统 | 处理器清单、沙箱、生成目录、缓存键、失败原子性 | 不把处理器自动带入依赖包 |

### 5.1 编译器生成的注册表入口

B2.3 由编译器发射 Runtime 注解静态表；X 代码通过两个生成入口读取：

| 入口 | 返回 | 语义 |
| --- | --- | --- |
| `xdkAnnotationRegistry()` | `AnnotationRegistry` | 只读注册表；只含 `Runtime` 注解 |
| `xdkAnnotationRegistryVersion()` | `Int` | 注册表格式版本；当前为 `1` |

生成表规则：

- 输入是编译器收集的 `AnnotationInfo` 扁平列表；
- 只发射 `@Retention(Runtime)` 注解；`Source`/`Binary`/默认 `Binary` 不进入；
- 同一目标保留源码出现顺序，`repeatIndex` 从 1 递增；
- 目标索引使用 `target + targetName`，包括 `Package`/`Type`/`Annotation`/
  `TypeParameter`/`Field`/`Method`/`Constructor`/`Deinit`/`Parameter`/`TypeUse`/`EnumItem`；
- `types()` 只列 `Type` 目标并按字典序排序；
- 运行时只读该表，不反射、不扫描、不动态注册。

关键边界：

- `Source`：处理器可见，编译后不保留；运行时无查询。
- `Binary`：处理器可见，产物保留工具/IDE 元数据；运行时无查询。
- `Runtime`：处理器可见，编译器生成静态注册表；运行时通过 `AnnotationRegistry` 只读查询。
- `AnnotationRegistry` 不知道保留策略；生成器只把 `Runtime` 项放进去。
- `AnnotationInfo` 不携带保留策略、不携带注解声明字段类型；这些是编译器内部模型。

---

## 6. 场景

### A1：声明与使用校验

```xnull
@annotation Marker {
    final String name = "";
}

@Marker("device")
class Device { }
```

验收：注解类型解析成功；目标 `Type` 合法；参数绑定到 `name`；未知注解/错目标/错参数/重复注解产生稳定诊断。

### A2：派生成员生成

`@Data` 处理器声明 `Validate` + `Generate`；在 `Validate` 检查目标字段，在 `Generate` 生成 `equals`/`hash`/`toString`/`copy`。验收：生成源码确定性；相同输入字节级一致；生成文件带来源标记；失败不落半成品。

### A3：运行时注册表查询

```xnull
AnnotationSet set = registry.ofType("app.Device")
AnnotationValue? name = set.first("app.Marker")?.valueOrNull("name")
```

验收：未命中返回空集合；`valueOrNull` 对缺失返回 null；不触发反射/类加载；`types()` 只列带注解类型。

### A4：序列化映射

`@Serializable`/`@JsonName` 在编译期生成编解码器；运行时注册表只保存需要的元数据。验收：字段名映射来自注解参数；生成器不修改原类型；处理器不联网/不写文件。

### A5：处理器诊断

处理器对缺失字段产生 `Error`，对可选字段产生 `Warning`，对生成来源产生 `Note`。验收：`success()` 仅在无 `Error` 时为 true；诊断码稳定；`describe()` 可读；构建系统不降级/忽略 `Error`。

### A6：可重复注解

`@Repeatable` 注解在同一目标出现多次；`AnnotationSet.all` 按出现顺序返回；`repeatIndex` 从 1 递增；`first` 返回第一个。验收：重复项保留；同一 `typeName + repeatIndex` 被拒绝；不同目标不混放。

### A7：保留策略

`Source` 注解只进处理器；`Binary` 注解进工具元数据；`Runtime` 注解进静态注册表。验收：三者互不越界；`Binary` 运行时查询为空；`Runtime` 查询不依赖反射。

### A8：确定性与增量

处理器输入哈希 + 选项 + 版本参与缓存；同一输入重复构建输出一致；生成源码不依赖绝对路径/时间/随机数。验收：缓存命中不改变输出；缓存失效可重现；失败路径不污染生成目录。

---

## 7. 缺口与决策

| # | 缺口/冲突 | 现状 | 处置 |
| --- | --- | --- | --- |
| G1 | S2 §12 与 `ANNOTATION-PLAN.md` 的同步 | S2 §12.4/§12.5 已清理冲突：构建期处理器/生成支持，运行期处理器不支持；计划已更新 | 已关闭（正式 3.5 合并待评审） |
| G2 | `deinit` 目标 | 已新增 `AnnotationTarget.Deinit`，与 S2 §12 对齐 | 已关闭 |
| G3 | `@Repeatable` 语义 | S2 内建表已改为强制；重复注解保留顺序 | 已关闭 |
| G4 | 注解声明模型 | `@annotation` 字段/默认值/常量类型不在本包 14 类型内 | 编译器内部模型；需要单独设计文档或语言规范章节 |
| G5 | 保留策略执行 | `AnnotationRegistry` 不判断保留策略 | 生成器负责过滤；需要生成器规范 |
| G6 | 注册表格式版本 | B2.3 定义 v1：`xdkAnnotationRegistryVersion() == 1`，扁平 `AnnotationInfo` 列表按目标分组 | 已定义 |
| G7 | `TypeParameter`/`TypeUse`/`Deinit` 运行时查询 | 只有 `ofTarget` 通用入口，无专用便捷方法 | 若领域需要，后续版本增加专用方法；当前不扩 API |
| G8 | 处理器依赖/轮次 API | 本包只定义阶段与上下文，不定义依赖图 | 构建系统/调度器设计负责 |
| G9 | 值树深比较 | `AnnotationValue`/`AnnotationInfo`/`AnnotationSet` 无 `equals` | 需要确定性哈希/比较时增加专用比较器，不把 `==` 当值比较 |
| G10 | 领域注解矩阵 | 各层注解清单不在本包 | 各领域包 README 维护；本包只冻结元模型 |
| G11 | 内建注解强制 | `@ReadOnly`/`@Override` 等强制在编译器 | 编译器设计负责；本包只提供目标/保留模型 |
| G12 | `@MustUse`/`@tasks`/`@arena`/`@arc`/`@gc` | 不属于通用注解系统 | 保持现状；不进入本包 |
| G13 | S2 §12 与 `TypeParameter`/`TypeUse` | S2 §12 已加入类型参数/类型使用目标 | 已关闭 |
| G14 | 默认保留策略/默认 `@Target` | 默认 `Binary`；未写 `@Target` 允许所有声明目标，`TypeUse` 必须显式 | 已冻结；补测试矩阵 |
| G15 |  总目录/`core/README.md` 列出 `annotations` | 已加入  地图/统计/包顺序 | 已关闭 |
| G16 | 元注解的 `Annotation` 目标 | 已新增 `AnnotationTarget.Annotation` | 已关闭 |

未决问题必须在  实现前冻结，尤其是 G1–G3、G13；否则编译器、处理器和领域包会各自解释注解语义。

---

## 8. 依赖与兼容

### 8.1 上游

- 语言核心标量：`String`、`Int`、`Long`、`Float`、`Double`、`Char`、`Bool`；
- 语言核心容器：`List`、`Map`；
- 语言特性：`class`、`enum`、`protocol`、`final` 字段、可空类型、函数类型（仅示例）、`String.trim`、`List.copy`/`push`/`sortBy`；
- 无 `xdk.errors`、无 `xdk.runtime`、无 `xdk.meta`、无反射/类加载 API。

### 8.2 下游

- 编译器前端/语义分析：目标、保留、常量、重复、未知诊断；
- 处理器调度/构建系统：阶段、轮次、生成目录、沙箱、缓存；
- 运行时：`AnnotationRegistry` 查询；
- IDE/文档：`Binary` 元数据、生成代码导航、注解索引；
- 各领域包：声明领域注解并启用处理器。

### 8.3 兼容规则

- 注解类型是 API：目标、保留、字段、默认值、处理器行为都算契约。
- 删除/收紧目标或保留策略是破坏性变更。
- `@Deprecated` 至少保留一个次版本。
- 生成代码格式/注册表格式需要版本号；处理器版本与编译器版本记录在生成元数据。
- 旧注解未知时编译错误，不静默忽略。
- 本包 14 类型标 `preview`；冻结后按 `stable` 管理。

---

## 9. 验收

- [ ] 本目录只有 README + 14 个 PascalCase 类型文件，无小写辅助文件；
- [ ] 每个类型文件恰好 14 个章节，章节名与模板一致；
- [ ] README 索引 14 个类型，链接全部存在且文件名与类型名一致；
- [ ] 每个 enum 有成员表、序号/语义、不变量、示例、测试义务、XNull 伪代码；
- [ ] 每个 class 有字段表、构造契约、方法表、所有权/并发、示例/反例、测试义务；
- [ ] `AnnotationProcessor` 是非泛型协议，`process` 返回 `AnnotationProcessingResult`；
- [ ] 无语言禁用返回类型、无空成功构造、无私有字段 `self` 前缀、无构造器委托简写、无泛型 `new` 简写、无省略式伪代码；
- [ ] 无运行时反射/类路径扫描/动态代理/注解类加载；
- [ ] `check_doc_naming.py` 通过；
- [ ] 14 节、禁用模式、索引、链接检查通过。

---

## 10. 变更记录

- 2026-11-22：首版。按 `ANNOTATION-SYSTEM.md` 建立 `xdk.annotations`  包，交付 14 个类型文件与包 README；标注 S2 §12/`ANNOTATION-PLAN.md` 与新设计的冲突为待冻结缺口。
- 2026-11-22：`AnnotationTarget` 对齐为 11 目标（含 `Deinit` 与元注解目标 `Annotation`），并补 `AnnotationInfo` 规范名、`AnnotationElement` 视图和 `AnnotationRegistry.targetKey`。
- 2026-11-22：B2.3 定义 Runtime 注册表 v1 与生成入口；B2-fix 统一 `annotation:` 目标键、枚举不可为 null、Float 作为 Double 别名。
