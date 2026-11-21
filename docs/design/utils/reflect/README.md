# `xdk.reflect` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.reflect` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.collections`；编译器/运行时只读类型元数据原语 |
| 被依赖 | 应用诊断、测试、插件/组件元数据检查 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.reflect` 提供**只读类型元数据**：

- 按名字解析类型，得到 `TypeInfo`；
- 读取成员列表，按名查找字段/方法；
- 做纯元数据可赋值判断；
- 生成稳定单行描述。

不做：动态调用/构造（X）、基于实例的 `typeOf`、`Object` 根类型、运行时类型注册表、注解/泛型/参数/可见性、外部程序集加载、序列化、缓存。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 元数据只读 | 只有解析与查询；不改变类型或成员 |
| 按名解析 | `resolve` 是唯一运行时类型入口；不提供实例 `typeOf`，不设 `Object` 根 |
| 快照不可变 | `TypeInfo`/`MemberInfo` 构造后不可变；列表返回副本 |
| 无全局注册表 | 元数据由编译期写入二进制；禁止 `register`/`unregister`/`allTypes` |
| 稳定顺序 | 成员与父类型保持声明顺序；`describe` 输出稳定 |
| 纯 CPU | 无 `Context`、无 I/O、无取消；不依赖 graph/event/log |
| 边界清晰 | 动态调用/构造、参数/注解/泛型细节留给 X |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `ReflectKind` | enum | Class/Protocol/Enum/Primitive | [`ReflectKind.md`](ReflectKind.md) |
| `MemberInfo` | class | 不可变成员元数据 | [`MemberInfo.md`](MemberInfo.md) |
| `TypeInfo` | class | 不可变类型元数据/成员查找 | [`TypeInfo.md`](TypeInfo.md) |
| `Reflect` | class | 静态解析/查询/可赋值/描述 | [`Reflect.md`](Reflect.md) |

X：动态调用/构造、参数/注解/泛型元数据。

---

## 4. 顶层函数

`reflectKindName(ReflectKind kind) -> String`：稳定小写名称 `class`/`protocol`/`enum`/`primitive`，仅用于诊断与 `describe`；不承担解析。

---

## 5. 技术/支撑/依赖

- 技术：只读元数据快照、按名解析、线性成员查找、名称图传递闭包、visited 集合防环、稳定格式化。
- 支撑：`reflectResolveRaw` 编译器/运行时只读元数据原语；`List`/`Set`；`str`；`BasicError`。
- 依赖：`xdk.errors`、`xdk.collections`；不依赖 `xdk.graph`、`xdk.event`、`xdk.log`。

---

## 6. 场景

### RF1：解析类型元数据

`Reflect.resolve("Point")` → `TypeInfo`（kind `Class`）；未知类型 → `NotFound`；null/空名 → `InvalidArgument`。

### RF2：检查成员

`Reflect.members(point)` 读取直接成员快照；`Reflect.field(point,"x")` / `Reflect.method(point,"distance")` 按名查找；缺失 → `NotFound`。

### RF3：元数据可赋值

`Reflect.isAssignable(point, base)` 沿直接父类型做传递判断；协议实现同样按 `supertypes` 名称判断；`Primitive` 只接受同名类型。

### RF4：诊断描述

`Reflect.describe(point)` → `class Point : Base, Named (members=3)`；与 `TypeInfo.describe` 完全一致；不触发调用/构造。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 动态调用/构造 | X；`Reflect` 不提供 |
| 构造器元数据 | 不做；构造器不进入 `MemberInfo`，动态构造 X |
| 实例 `typeOf` / `Object` 根 | 不做；只按名 `resolve` |
| 参数/返回签名细节 | 不做；`MemberInfo.typeName` 只记字段类型或方法返回类型 |
| 注解/泛型/可见性 | 不做；不进入元数据模型 |
| 全局注册表/运行时注册 | 禁止；只读编译器元数据 |
| 外部程序集加载 | 不做；只解析当前二进制内元数据 |
| 类型序列化 | 不做；由 codec 或应用负责 |
| 缓存 | 不做；每次返回独立快照，避免陈旧与锁 |
| graph/event/log 依赖 | 禁止；保持 X 包边界 |
| 字段与方法同名 | 允许；`field`/`method` 分流，`TypeInfo` 按种类去重 |
| `Primitive` 元数据 | 强制为空；可赋值性仅名称同一 |
