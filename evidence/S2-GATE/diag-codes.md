# S2 诊断码表（sema，E2）

> 基线：`pod/e2-sema`；范围：`impl/internal/sema`。格式：码 / 含义 / 典型触发 / 位置保证。

## RES（名称/导入）

| 码 | 含义 | 典型触发 |
|---|---|---|
| RES-101 | 未定义名称/类型 | `print(nope)`；签名位置泄漏 `T` |
| RES-102 | 同一作用域重复声明 | 局部/类型/类型参数重名 |
| RES-103 | 导入别名冲突 | 同包不同符号共用别名；别名与裸导入同名 |
| RES-104 | 未消歧简单名 | 多来源同名简单名 |
| RES-105 | XDK 符号未显式导入 | 未 import 使用 `diagnose` |
| RES-106 | 包/符号不存在 | `import xdk.nonexist` |
| RES-107 | 非消歧场景使用 as | 无同名歧义的符号别名 |
| RES-108 | 包导入环 | 多文件 import 环 |
| RES-110 | 子文件缺 package | 默认包跨包导入 |
| RES-111 | 默认包被跨包导入 | `import default` |

## DA（确定赋值）

| 码 | 含义 | 典型触发 |
|---|---|---|
| DA-101 | 可能未赋值即读取 | `Int x; print(x)` |
| DA-102 | final/const 重复赋值 | `final Int x=1; x=2` |
| DA-103 | 非 void 返回路径缺失 | `Int f(){ print("x") }` |

## TY（类型/对象）

| 码 | 含义 | 典型触发 |
|---|---|---|
| TY-101 | 可赋值性失败 | 数值隐式转换、void 位置 |
| TY-103 | null → 非可空值类型 | `Result<Int,String> r = null` |
| TY-104 | 条件必须 Bool | `if 1` |
| TY-105 | 无效运算操作数 | 混合数值运算、异型比较 |
| TY-106 | 元组规则 | 越界 `.N`、元组成员、switch、插值、as |
| TY-107 | Map 键类型不支持 | `Map<Bool,Int>` |
| TY-201 | 修饰符非法 | `abstract struct`、`abstract final` |
| TY-202 | 继承/协议结构错误 | 父类 final/kind、环、implements 目标 |
| TY-203 | 方法同签名/字段隐藏 | 子类同签名、基名冲突 |
| TY-204 | 结构体值规则 | 引用字段、递归值包含、泛型非值实参 |
| TY-205 | 协议形式错误 | 协议 private/static 方法 |
| TY-206 | 枚举规则 | 重复项/值、混合形式、数据枚举字段 |
| TY-207 | 私有字段规范名 | `private _x`、`self._x`、外部访问 |
| TY-208 | 协议实现检查 | 缺方法/父协议/签名/@Override |
| TY-209 | 成员可见性 | protected/private 外部访问 |
| TY-210 | new abstract | `new A()` 抽象类 |
| TY-211 | 协议成员限制 | 协议变量调用协议外方法/字段 |
| TY-212 | PCTOR/final 字段 | 非 final 主构造参数、混用、final 重赋值 |
| TY-213 | 枚举 switch/default | 遗漏/未知/重复项、default 非最后 |
| TY-214 | 静态成员用类类型参数 | `static T value` |
| TY-215 | singleton instance 只读 | `AppInfo.instance = null` |
| TY-216 | new singleton/factory | `new AppInfo()` |
| TY-217 | factory Target/类型使用 | Target 缺失/泛型/非 class、factory 当类型 |
| TY-218 | 数据枚举不可变 | 字段写入、方法写字段、new 项 |
| TY-219 | 跨包 factory 私有访问 | 跨包调用私有/受保护构造器 |
| TY-220 | factory 返回类型 | `static Int make()` 对 class Target |
| TY-221 | factory 使用 self/super | `self`/`super` 出现在工厂方法 |
| TY-222 | singleton 规则 | abstract singleton、前向引用 |
| TY-223 | 注解声明/使用/目标 | 未知/重复注解、参数、注解作类型/值/new |
| TY-224 | final 字段二次写 | 构造外写 final 字段 |
| TY-225 | extension 规则 | 跨包/泛型/预定义目标、重复、同签名、私有访问 |
| TY-226 | new 非 class 类型 | `new P()` 协议、`new E()` 枚举 |

## GEN（泛型）

| 码 | 含义 | 典型触发 |
|---|---|---|
| GEN-101 | 显式类型实参 | 数量不符、void、非泛型函数 |
| GEN-102 | 推断 | 冲突绑定、未绑定、null 不能定 T |
| GEN-103 | 重载 | 歧义、零候选 |
| GEN-104 | 作用域/构造/展开 | `T` 越界、`new T()`、无限展开 |

## ERR（错误处理）

| 码 | 含义 | 典型触发 |
|---|---|---|
| ERR-201 | Result @mustUse | 裸 Result 变量/调用/构造、defer 内未处理 |
| ERR-202 | Result 构造 | 实参数量/void E/类型不符 |
| ERR-203 | Result 成员 | 未知成员、带参、void 成员 |
| ERR-204 | try 上下文 | main/构造器/deinit、非 Result、错误类型 |
| ERR-205 | 清理体限制 | defer/errdefer 单条局部声明 |
| ERR-206 | errdefer 上下文 | 非 Result 函数内 errdefer |

## 位置保证

`sema` 全部诊断经 `errf` 使用 AST 节点位置；`LocalDeclStmt` 清理体诊断走 `Type`/`defer` 关键字回退。守门：`TestAllDiagPositionsNonZero`（31 个单文件可触发码）与 `TestERR205CleanupLocalDeclPosition`。
