# `xdk.functional` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.functional` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.collections` |
| 被依赖 | 应用 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

函数式/集合管线：Seq 变换、静态序列生成、Lazy 延迟值。

不做：Stream 并行、响应式、持久化集合、宏。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式求值 | `Seq` 是 eager 快照；Lazy 显式 |
| 不修改入参 | 变换返回新 Seq |
| 无全局 | 无全局缓存/调度 |
| 泛型类/方法 | 使用 XNull 泛型，不用泛型协议 |
| 顺序稳定 | map/filter/zip 保持顺序 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Seq` | class | map/filter/flatMap/group/chunk/zip | [`Seq.md`](Seq.md) |
| `Sequences` | class | range/repeat/generate/concat | [`Sequences.md`](Sequences.md) |
| `Lazy` | class | 延迟/缓存值 | [`Lazy.md`](Lazy.md) |

X：真正惰性 Seq、并行管线、无限序列。

---

## 4. 顶层函数

无。

---

## 5. 技术/支撑/依赖

- 技术：泛型集合管线、闭包、快照。
- 支撑：`List`、`Map`、`Pair`、`Set`。
- 依赖：`collections`。

---

## 6. 场景

### F1：数据变换

`Seq.of(rows).filter(...).map(...).toList()`。

### F2：分组/窗口

`groupBy`、`chunk`、`window`、`zip`。

### F3：延迟初始化

`new Lazy<T>(() -> expensive())`；`get()` 只计算一次。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 惰性 Seq | X |
| 并行 | X |
| 无限序列 | X |
| 自定义比较器 | `sorted(Int(T,T))` |
| 相等语义 | 使用 `==`；类按引用 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value` |
| 处理器 | 标准 A8 |
| 生成物 | 序列/惰性视图的值语义范围按实现确认；视图不强行 `@Value` |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Seq`/`Sequences` | `@Value` | 值语义成员（若不可变） |
| `Lazy` | — | 惰性视图，保持显式 class |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
