# `AnnotationTarget`

| 项 | 值 |
| --- | --- |
| 类型 | `enum AnnotationTarget` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

注解可应用的声明位置枚举。编译器用它校验 `@Target`，`AnnotationInfo`/`AnnotationElement` 记录目标种类，`AnnotationRegistry` 按目标种类建立只读索引。

不做：不表示运行时类结构，不表示权限，不表示注解语义，不表示处理器阶段；不包含表达式、控制体、块注解；包含 `Deinit`。

> S2 §12 把 `deinit` 列为可注解位置；本模型显式包含 `Deinit`，与语言规范一致。

---

## 2. 设计逻辑

- 目标集合固定为 11 项，只允许追加，不允许改名或改序号。
- `Package` 与 `Type` 分开：包级注解用于模块/包治理，类型级注解用于声明生成与校验。
- `TypeParameter` 独立于 `Type`：泛型参数的注解不自动落到类型本体。
- `Field` 与 `EnumItem` 分开：枚举项不是字段，注解生成与校验规则不同。
- `Method` 与 `Constructor` 分开：构造器没有返回类型，生成规则和签名匹配规则不同。
- `Deinit` 独立于 `Method`：`deinit` 没有参数与返回类型，生命周期诊断/生成规则不同。
- `Parameter` 独立于 `Method`：参数注解必须绑定到具体参数下标，不能退化成方法注解。
- `TypeUse` 表示源码中的类型使用位置，例如字段类型、参数类型、返回类型；它不改变类型本身。
- 目标只描述“放在哪里”，不描述“是否保留”“是否可重复”“是否强制”；这些分别由 `AnnotationRetention`、`@Repeatable` 和编译器规则表达。
- 枚举是值类型，可作 `Map` 键，可跨任务只读共享。

---

## 3. 表示与不变量

| 序号 | 成员 | 含义 |
| --- | --- | --- |
| 0 | `Package` | 包声明 |
| 1 | `Type` | 类、结构、枚举、单例、工厂等类型声明 |
| 2 | `Annotation` | `@annotation` 声明（元注解目标） |
| 3 | `TypeParameter` | 类型参数声明 |
| 4 | `Field` | 字段声明 |
| 5 | `Method` | 方法声明 |
| 6 | `Constructor` | 构造器声明 |
| 7 | `Deinit` | `deinit` 声明 |
| 8 | `Parameter` | 方法/构造器参数声明 |
| 9 | `TypeUse` | 源码中的类型使用位置 |
| 10 | `EnumItem` | 枚举项声明 |

不变量：成员固定为上述 11 项；序号稳定；值语义；不存在 null 成员；可作 `Map` 键；新增目标必须提升版本并更新编译器目标表。

---

## 4. 生命周期

值类型；无 close；无资源；编译期与运行时元数据中都只作为常量使用；可被任意数量的 `AnnotationInfo`、`AnnotationElement` 和注册表查询共享。

---

## 5. 构造契约

枚举成员直接使用，无构造器。非法输入不是本类型的职责；编译器在解析 `@Target` 元注解时负责拒绝未知目标。

默认目标：注解声明未写 `@Target` 时，允许所有声明目标（`Package`、`Type`、`Annotation`、`TypeParameter`、`Field`、`Method`、`Constructor`、`Deinit`、`Parameter`、`EnumItem`）；`TypeUse` 必须显式声明。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

`AnnotationTarget` 没有实例方法。名称、解析和目标校验由编译器目标表与 `xdk.annotations` 的查询方法承担。

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| 无 | 枚举只提供成员 | 无 | 无 | 无 |

说明：

- `AnnotationInfo.target()` 和 `AnnotationElement.target()` 返回本枚举值。
- `AnnotationRegistry.ofTarget` 用本枚举值加目标名定位注解集合。
- 不为枚举添加 `name`/`fromName` 实例方法；XNull 简单枚举没有方法，名称映射由编译器/工具链维护。

---

## 8. 使用的技术

- 简单枚举；
- 稳定序号；
- 编译期目标表；
- 值语义。

---

## 9. 需要的支撑

- 语言：enum、String 常量、Map 键；
- 运行时：无；
- 接口：`AnnotationInfo`、`AnnotationElement`、`AnnotationRegistry`。

---

## 10. 依赖的特性/接口/类

无。目标枚举是 `xdk.annotations` 的最底层类型之一。

---

## 11. 所有权与并发

值语义；复制即复制枚举值；可跨任务共享；无同步需求；相等按枚举值。

---

## 12. 示例与反例

正确：

```xnull
AnnotationInfo marker = new AnnotationInfo(
    "app.Marker",
    AnnotationTarget.Type,
    "app.Device",
    ["name": AnnotationValue.ofString("device")],
    1
)
Bool onType = marker.target() == AnnotationTarget.Type
```

反例：把 `TypeUse` 当作 `Type` 使用；把 `Parameter` 注解折叠成 `Method` 注解；把 `EnumItem` 当字段；把 `Deinit` 折叠成 `Method` 或忽略 `Deinit` 目标；在应用代码里扩展目标枚举。

---

## 13. 测试/场景义务

- 11 个成员逐一存在且序号稳定；
- `@Target` 校验接受合法目标、拒绝非法目标；
- `AnnotationInfo` 保存的目标可原样读回；
- `AnnotationRegistry.ofTarget` 对每个目标种类可命中；
- 未知/缺失目标产生编译诊断；
- 目标枚举作为 `Map` 键的相等行为。

---

## 14. XNull 伪代码

```xnull
enum AnnotationTarget {
    Package,
    Type,
    Annotation,
    TypeParameter,
    Field,
    Method,
    Constructor,
    Deinit,
    Parameter,
    TypeUse,
    EnumItem,
}
```
