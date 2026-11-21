# `ReflectKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ReflectKind` |
| 包 | `xdk.reflect` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

类型元数据分类：Class、Protocol、Enum、Primitive。

不做：实例类型检查、`Object` 根类型、继承图算法、动态调用、动态构造。

---

## 2. 设计逻辑

- 四个成员固定；只表达“这个 `TypeInfo` 属于哪一类声明”，不携带字段。
- `Class`：名义引用类型；成员可含字段与方法；`supertypes` 表示直接父类/实现的协议名。
- `Protocol`：行为合同；成员以方法为主；`supertypes` 表示直接扩展的协议名。
- `Enum`：命名常量集合；常量在元数据中以静态字段出现；`supertypes` 表示实现的协议名。
- `Primitive`：语言内建值类型；元数据必须没有成员、没有父类型；可赋值性只按名称同一判断。
- `Reflect.resolve` 负责填充 kind；`TypeInfo.kind()` 只读取，不重新推断。
- 序号不稳定，不写入持久化数据；跨进程只使用 `reflectKindName` 的稳定小写名。
- 值语义；无 close；可作 `Map` 键。

---

## 3. 表示与不变量

| 成员 | 语义 | 元数据约定 |
| --- | --- | --- |
| `Class` | 类 | 可有字段/方法/父类型 |
| `Protocol` | 协议 | 成员以方法为主；可有父协议 |
| `Enum` | 枚举 | 常量以静态字段出现；可实现协议 |
| `Primitive` | 内建值类型 | 无成员、无父类型 |

不变量：成员固定四项；`Primitive` 的 `TypeInfo` 必须为空元数据；kind 构造后不可变；不存在 `Object`/`Any`/`Interface` 等隐式成员。

---

## 4. 生命周期

值类型；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 枚举成员 | 无 | 固定四项 | 无 |

说明：

- 直接使用成员，不提供整数转换。
- 不提供 `parse`；配置/协议层必须显式映射，未知文本视为配置错误。
- 不从序号恢复语义，避免版本间序号变化导致误读。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法。

包级函数：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `reflectKindName` | 稳定小写名 | `ReflectKind kind` | `String` | 无 |

说明：

- `reflectKindName` 只用于诊断/描述；不承担解析。
- 名称固定为 `class`、`protocol`、`enum`、`primitive`。
- `TypeInfo.describe` 使用该名称；不直接拼接枚举。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称映射；
- 元数据分类约定；
- 描述时按 kind 分派。

---

## 9. 需要的支撑

- 语言：enum、String、if；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；不可变；可共享；可并发比较；无资源。

---

## 12. 示例与反例

正确：`type.kind() == ReflectKind.Class`；`Reflect.resolve("Int").value().kind() == ReflectKind.Primitive`。  
反例：用 kind 直接构造实例；假设枚举序号稳定；把 `Protocol` 当可实例化 `Class`；期望 `Primitive` 有成员；把 `Enum` 常量当实例字段。

---

## 13. 测试/场景义务

四个成员；`reflectKindName` 映射；switch/if 覆盖全部成员；作为 `Map` 键；跨模块比较；未知文本拒绝；`Primitive` 元数据为空；`Class`/`Protocol`/`Enum` 的 kind 与 `TypeInfo` 一致。

---

## 14. XNull 伪代码

```xnull
enum ReflectKind {
    Class,
    Protocol,
    Enum,
    Primitive,
}

String reflectKindName(ReflectKind kind) {
    if kind == ReflectKind.Class { return "class" }
    if kind == ReflectKind.Protocol { return "protocol" }
    if kind == ReflectKind.Enum { return "enum" }
    return "primitive"
}
```
