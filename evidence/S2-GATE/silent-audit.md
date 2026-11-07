# 无静默降级审计（S2 sema 面）

> 方法：扫描 `internal/codegen` / `internal/interp` 的显式“未支持”分支，对照 sema 是否已在 check 阶段拒绝。
> 结论：语言非法构造全部由 sema 拒绝；剩余 `check rc=0 → codegen/interp 报错` 是**实现能力边界**，属 E4/E5，不应由 sema 把合法程序判非法。

## 已修（本次 GATE-01）

| 构造 | 之前 | 现在 |
|---|---|---|
| `new P()`（协议） | check rc=0，codegen 才报 | `TY-226` check 拒绝 |
| `new E()`（枚举） | check rc=0，codegen 才报 | `TY-226` check 拒绝 |
| `new abstract` | 已修 | `TY-210` |
| 注解 `new`/作类型/作值 | 已修 | `TY-223` |
| 跨包 factory 私有构造器 | 已修 | `TY-219` |
| extension 跨包/泛型目标 | 已修 | `TY-225` |

## 仍为跨域能力边界（sema 不误拒）

| codegen/interp 报错点 | 合法语言构造 | owner | 处置 |
|---|---|---|---|
| `Float`/`Char` 表达式/打印未支持 | S1 允许 Float/Double/Char | E4 | 补 codegen，不由 sema 拒绝 |
| `null` 表达式、可空链部分形态 | S1 允许 | E4 | 补 codegen |
| 类引用接收者链/字段链、`self` 构造器绑定 | S2 合法 | E4/E3 | 补 codegen/interp |
| 容器/可空表达式部分成员 | S1/S2 合法 | E4 | 补 codegen |
| 协议值调用部分返回/接收者形态 | S2 §4.4 合法 | E4 | 补 codegen |
| 泛型类继承/协议单态化 | S2 §13 合法 | E4 | 补 codegen |
| extension 方法发射 | S2 §11 合法 | E4 | 补 codegen（sema 已检查规则） |
| singleton 静态字段/方法发射 | S2 §9 合法 | E4 | 补 codegen |
| 顶层非泛型函数重载 C 侧发射 | S1 §4.4 合法 | E4 | mangle 实例名 |
| 元组编译路径部分形态 | S1 §2.11 合法 | E4 | 补 codegen |
| 结构体赋值/类返回部分形态 | S2 §3/§5 合法 | E4 | 补 codegen |

## 判定

- 上述“仍为跨域”项均为合法源码；若在 sema 拒绝，会把语言能力错误地判负，违反 S2 规范。
- GATE-01 的 `check` 阶段职责限定为：**语言禁止构造必须拒绝**；本卡补 `new` 非 class 两类，其余禁止构造已在前序卡全覆盖。
- 建议 GATE 门报告把该表作为 E4/E5 能力缺口清单，而不是 sema 静默降级。
