# XNull 解决方案 第 8 部分：工具链（模块 01：编译前端与 C 代码生成）

> **2026-11-15**：本文档是内部实现基线，不属于语言规范序列；实现细节（含 `.xfb` 等格式）可按实现需要修正。

> 本文是第 8 部分模块 01，只落实第 1—4 部分已定义的行为；内部实现选择不构成语言语义；与第 1—8 部分冲突时以母本为准。

| 项 | 值 |
| --- | --- |
| 文档编号 | 第 8 部分（T8） |
| 模块 | 01 编译前端与 C 代码生成 / 10 |
| 文档版本 | 1.0.0 |
| 规范状态 | 工程实现基线（受第 1—8 部分约束） |
| 文档性质 | 第 8 部分模块详细设计；不新增语言语义 |
| 编制日期 | 2026-11-07 |
| 代码基线 | `f63fcba`（编制时点；工作区可能继续前进） |
| 设计依据 | 第 1—4 部分 |
| 组件 | 编译前端与代码生成：源文件装载、词法、语法、AST、语义分析、C 代码生成 |
| 上游输入 | `.x` 源文件、import 闭包、FFI 注册表、编译选项 |
| 下游输出 | C 翻译单元、诊断、策略判定结果 |
| 明确不含 | CLI 参数、C 编译/链接、C 运行时、`xrt` ABI、`.xfb` 合同校验、工程生命周期、诊断渲染 |
| 配套文档 | 第 8 部分总览；模块 05、06、07 |

## 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| 1.0.0 | 2026-11-07 | 首版。界定编译器的输入输出、前端/语义/代码生成三段结构与行为边界。 |

---

## 0. 范围与边界

### 0.1 组件定位

编译器负责把 XNull 源码转换为 C 翻译单元。它不负责启动 `cc`、不链接运行时、不执行程序，也不处理工程清单的生命周期。

```
.x 源文件 + import 闭包
        │
        ▼
  源文件装载（多文件合并）
        │
        ▼
  词法 → 语法 → AST
        │
        ▼
  语义分析（名称/赋值/类型/策略/清理规则）
        │
        ▼
  C 代码生成（AST → C 文本）
        │
        ▼
  C 翻译单元 + 诊断 + 策略 JSON
```

### 0.2 输入

| 输入 | 来源 | 说明 |
| --- | --- | --- |
| 入口 `.x` 文件 | 用户/XDK/自举代码 | UTF-8 源文件 |
| import 依赖文件 | 入口所在目录的相对路径 | `import p1.p2` → `p1/p2.x` |
| `.xfb` 注册表 | FFI 合同层 | 代码生成调用 `xn_ffi_<entry>` 时使用 |
| 编译选项 | CLI/构建层 | 当前主要影响输出路径与运行时目录，不改变语义 |
| 外部声明 | XDK 包符号表 | 语义分析可见的 `xdk.*` 导出符号 |

### 0.3 输出

| 输出 | 形态 | 消费者 |
| --- | --- | --- |
| C 翻译单元 | C11 文本 | C 编译/链接层 |
| 诊断 | 结构化诊断值 | 诊断渲染层 |
| 策略判定 | 每类型一条 `Strategy` | `policy` 命令、运行时/验收 |
| 编译失败信号 | 错误/退出码由上层转换 | CLI/构建层 |

### 0.4 明确不做

- 不解析 CLI 参数；
- 不执行 `cc`、不生成可执行文件；
- 不读工程清单、不做依赖解析、不执行生命周期；
- 不渲染诊断；
- 不实现运行时内存管理；
- 不校验 `.xfb` 合同（只消费 FFI 层产出的注册表）；
- 不承诺未支持语言构造的降级执行。

---

## 1. 总体架构

### 1.1 三段式

| 段 | 职责 | 主要产物 | 主要诊断段位 |
| --- | --- | --- | --- |
| 前端 | 源文件装载、词法、语法、AST | `CompilationUnit` | LEX-1xx、SYN-1xx、RES-1xx（装载） |
| 语义 | 名称、确定赋值、类型、类型声明、策略、清理规则 | 诊断、`Strategy` | RES-1xx、DA-1xx、TY-1xx/2xx、ERR-2xx |
| 代码生成 | AST → C，容器/类/Result/FFI 调用 | C 文本 | 代码生成错误（不新增语义码段） |

### 1.2 依赖方向

```
frontend (xfront)
   ↑
semantic (sema) ──依赖──> xfront
   ↑
codegen ──依赖──> xfront + sema + FFI 注册表 + diag
```

- 前端不依赖语义或代码生成；
- 语义只依赖前端；
- 代码生成只消费“已经过语义检查”的 AST 与策略结果；
- 编译器不反向依赖 CLI 或工程配置。

### 1.3 编译单元

`CompilationUnit` 是编译器的核心输入/中间产物：

```go
type CompilationUnit struct {
    P       Pos
    Package *PackageDecl
    Imports []*ImportDecl
    Decls   []TopDecl
}
```

多文件装载后合并为**单一** `CompilationUnit`，`Decls` 按依赖优先后序排列。解释器与代码生成共享这一结构，保证双路径看到同一组声明。

---

## 2. 源文件装载

### 2.1 装载规则

| 规则 | 行为 |
| --- | --- |
| import 路径映射 | `import p1.p2` → 入口所在目录的 `p1/p2.x` |
| `xdk.*` | 不按文件装载；由语义阶段的 XDK 符号表处理 |
| 重复导入 | 同一文件只加载一次；import 声明去重 |
| 环检测 | 访问中再次到达 → `RES-108` |
| 缺失文件 | `RES-106` |
| 跨包导入 | 命名包可以导入命名包；符号在同一翻译单元内扁平链接，包前缀属后续切片 |
| 默认包 | 默认包跨文件组合视为同一编译单元的多个分片 |
| 默认包被命名包导入 | `RES-110`（装载）/`RES-111`（语义包检查） |
| 合并顺序 | 依赖优先的后序；同一 import 列表按源码书写顺序 |

### 2.2 确定性

- 依赖遍历顺序来自源码 import 列表，不依赖文件系统枚举；
- 同一 import 键 `path|alias` 只保留一次；
- 诊断按发现顺序返回，最终渲染层可稳定排序；
- 同一输入 + 同一版本必须得到同一合并声明序列。

### 2.3 边界

- 命名包可以导入命名包；当前符号在单一翻译单元内扁平链接，完整包前缀/独立编译单元属后续切片；
- 命名包不得导入默认包文件（`RES-110`/`RES-111`）；
- 默认包跨文件组合只作为同一编译单元的分片；
- `xdk.*` 不落文件系统；
- 不对 import 路径做环境变量或搜索路径展开。

---

## 3. 词法分析

### 3.1 输入规范化

| 项 | 行为 |
| --- | --- |
| 编码 | UTF-8，按 rune 扫描 |
| BOM | 仅允许文件开头；不参与列号 |
| 换行 | CRLF 归一化为 LF |
| 列号 | 1 基，按 Unicode 标量计数 |
| 注释 | 行注释、块注释、文档注释；块注释不嵌套 |
| 错误 | 不中断，可一次返回多条 |

### 3.2 Token 模型

```go
type Token struct {
    Kind Kind
    Text string
    Pos  Pos
    Str     StrKind
    Value   string
    Segs    []string
    Interps []string
    Char    rune
}
```

Token 类别：`EOF`、`Semi`、`Ident`、`Keyword`、`Annotation`、`IntLit`、`FloatLit`、`CharLit`、`StrLit`、`Op`、括号/花括号/方括号/逗号。

### 3.3 字面量

- 整数：十/十六/八/二进制，`L`/`U`/`UL` 后缀；
- 浮点：小数/指数，`f` 后缀；
- 字符：转义与 `\u{…}` 标量校验；
- 字符串：普通、raw、多行、raw 多行、插值五种；
- 插值串保留静态段 `Segs` 与表达式原文 `Interps`。

### 3.4 自动分号

- 可插入集合、`}` 后 `else`/`while` 不插、空行与注释行不触发、EOF 前补插；
- 注解与所附声明之间的自动分号被 `dropSemiInAnnotation` 丢弃，避免切断注解。

### 3.5 词法诊断

| 码 | 语义 |
| --- | --- |
| `LEX-101` | 无法识别的字符 |
| `LEX-102` | 未闭合的注释/字符串/字符字面量 |
| `LEX-103` | 未知转义、位数不足、非法标量值 |
| `LEX-104` | 非法数字格式、下划线位置错误、后缀冲突 |
| `LEX-105` | 非法插值表达式边界 |
| `LEX-106` | 空字符字面量、多字符、跨行 |

---

## 4. 语法分析与 AST

### 4.1 AST 接口

```go
type Expr interface { Pos() Pos; exprNode() }
type Stmt interface { Pos() Pos; stmtNode() }
type TypeRef interface { Pos() Pos; typeNode() }
type TopDecl interface { Pos() Pos; topDecl() }
```

### 4.2 表达式节点

| 节点 | 用途 |
| --- | --- |
| `IdentExpr` | 标识符 |
| `IntLitExpr`/`FloatLitExpr`/`CharLitExpr`/`BoolLit`/`NullLit` | 字面量 |
| `StrLitExpr` | 字符串/插值串 |
| `Paren`/`Tuple`/`ArrayLit`/`MapLit` | 括号、元组、数组、映射 |
| `Unary`/`Binary`/`Ternary` | 一元/二元/三元 |
| `Member`/`TupleMember` | 成员/元组位置 |
| `Call`/`Index` | 调用/下标 |
| `New`/`NewArray` | 实例化/数组分配 |
| `Lambda` | 闭包字面量 |
| `TypeAsExpr` | `is`/`as`/`as?` |

### 4.3 语句节点

| 节点 | 用途 |
| --- | --- |
| `Block` | 块 |
| `ReturnStmt`/`ExprStmt` | 返回/表达式语句 |
| `LocalDeclStmt`/`AssignStmt`/`IncDecStmt` | 声明/赋值/自增自减 |
| `IfStmt`/`WhileStmt`/`DoWhileStmt`/`ForStmt` | 条件/循环 |
| `SwitchStmt`/`SwitchCase` | switch |
| `DeferStmt` | defer/errdefer |
| `BreakStmt`/`ContinueStmt`/`GotoStmt`/`LabeledStmt` | 跳转 |
| `ThrowStmt`/`EmptyStmt` | fatal/空语句 |

### 4.4 类型引用

| 节点 | 形态 |
| --- | --- |
| `NamedType` | 名称 + 泛型实参 + 点分限定 |
| `SuffixedType` | `[]`、`?` 等后缀 |
| `FuncTypeRef` | 函数类型 |
| `TupleTypeRef` | 元组类型 |

### 4.5 顶层声明

| 节点 | 说明 |
| --- | --- |
| `PackageDecl`/`ImportDecl` | 包与导入 |
| `TopFunc`/`TopField` | 顶层函数/字段 |
| `ClassDecl` | 类：字段、方法、构造器、基类、协议 |
| `StructDecl` | 纯值结构体 |
| `ProtocolDecl` | 协议方法签名 |
| `EnumDecl` | 简单/数据枚举 |

### 4.6 表达式优先级

从低到高：

| 层 | 运算符/形态 |
| --- | --- |
| 1 | 三元 `?:` |
| 2 | `??` |
| 3 | `||` |
| 4 | `&&` |
| 5 | `|` |
| 6 | `^` |
| 7 | `&` |
| 8 | `==`/`!=` |
| 9 | `<`/`<=`/`>`/`>=` |
| 10 | 区间 |
| 11 | `<<`/`>>` |
| 12 | `+`/`-` |
| 13 | `*`/`/`/`%` |
| 14 | 一元 |
| 15 | 后缀：调用/成员/下标/new |
| 16 | 主表达式 |

### 4.7 歧义处理

| 歧义 | 处理 |
| --- | --- |
| `(` 起头 | 括号/元组/Lambda 三态回溯 |
| `Type name` | 局部声明 vs 表达式，回溯判定 |
| `new Type(` | `(` 是构造实参，不是函数类型 |
| 泛型实参 | 尖括号配平前瞻 |
| `as?` | 单 token，避免 `as` + `?` 混淆 |
| 类型声明 | `class`/`struct`/`protocol`/`enum` 正式解析；`singleton`/`extension`/`annotation` 报 `SYN-110` |
| 注解行 | 自动分号预处理，避免切断注解 |

### 4.8 语法诊断

| 码 | 语义 |
| --- | --- |
| `SYN-101` | 期望 token 不符 |
| `SYN-102` | 比较运算不可链式 |
| `SYN-103` | 范围运算不可链式 |
| `SYN-104` | 元组至少两个元素 |
| `SYN-105` | `new` 后必须是 `(`/`[` |
| `SYN-106` | 表达式结束后存在未消费输入 |
| `SYN-107` | 范围只允许 for-in 源位置 |
| `SYN-108` | 同一行缺分号 |
| `SYN-109` | 赋值/自增目标非法 |
| `SYN-110` | 类型声明属后续批次 |
| `SYN-111` | 用户包名使用 `xdk` 保留命名空间 |

---

## 5. 语义分析

### 5.1 分析顺序

```
1. analyzeImports      导入可见性、XDK 包、别名、歧义
2. checkTypeDecls      类型声明结构检查
3. collectTop          顶层函数/字段名字空间
4. walkBlock           名称解析
5. analyzeAssign       确定赋值与返回路径
6. analyzeTypes        类型检查
7. ComputeStrategies   内存策略判定（按需）
```

诊断不中断；一个编译单元可返回多条。

### 5.2 名称解析

四级解析：

1. 局部变量、参数、类型参数；
2. 当前包顶层；
3. 导入符号；
4. 完全限定名。

规则：

- 同一作用域重复声明 → `RES-102`；
- 名称不可见 → `RES-101`；
- 遮蔽合法性按作用域规则；
- 顶层函数允许重载；同名字段/函数冲突由类型检查判定；
- 导入族：`RES-103` 别名冲突、`RES-104` 未消歧简单名、`RES-105` XDK 未显式导入、`RES-106` 符号不存在、`RES-107` 非冲突场景别名。

包符号表（`sema/pkg.go`）：

- `Package` 保存导入路径、包声明、公开顶层符号、该包自身的 import；
- `NewPackage` 从编译单元提取符号表；顶层 `private`/`protected` 不跨包导出；
- `AnalyzeWithDeps` 在给定依赖包表时执行严格导入解析；
- 无依赖表时保持旧行为：用户包导入无法解析时延后未定义检查；
- 包导入环 `RES-108`；默认包被命名包导入 `RES-111`；
- 跨包符号当前在单一翻译单元内扁平链接；包前缀属后续切片。

### 5.3 XDK 符号可见性

- 语义阶段维护 `xdk.*` 包的导出符号表；
- 只有显式 import 的 XDK 包符号可见；
- 未定案名称不猜测，不进入符号表；
- 用户包名以 `xdk` 开头被解析阶段拒绝（`SYN-111`）。

### 5.4 确定赋值

- 路径状态集合：已赋值、final/const、不可达；
- 分支汇合取交集；
- `if`/`else`、`while`/`do-while`、`for`、`switch`、`break`/`continue`/`return`/`goto` 参与汇合；
- `&&`/`||`/`??`/`try` 按路径合并；
- 读取可能未赋值 → `DA-101`；
- final/const 重复赋值 → `DA-102`；
- 非 void 函数正常返回路径缺失 → `DA-103`。

### 5.5 类型检查

- `typeKey` 规范化类型；
- 可赋值性：同一类型、`null` 到可空、字面量适配、容器字面量、闭包目标、`Any`/`Object`、隐式数值转换拒绝；
- 类型推断：字面量、标识符、成员、调用、二元、三元、`new`、下标、元组；
- 函数调用按签名表检查参数/重载；
- 成员调用按内建容器/String/Result/类方法分派；
- 运算符按算术/比较/逻辑规则检查。

诊断：

| 码 | 语义 |
| --- | --- |
| `TY-101` | 可赋值性失败 |
| `TY-103` | null → 非可空值类型 |
| `TY-104` | 条件非 Bool |
| `TY-105` | 无效运算操作数 |

泛型调用（`sema/generic.go`）：

- 显式类型实参：数量/void/非泛型校验；
- 无显式实参：推断/合一/冲突/未绑定/null；
- 重载：普通同名函数优先，泛型候选按实参匹配；
- 推断成功后把最终类型实参写回 `Call.TypeArgs`，供代码生成单态化；
- 诊断段位：`GEN-101` 显式实参、`GEN-102` 推断、`GEN-103` 重载、`GEN-104` 类型参数作用域/`new T()`/无限展开。

### 5.6 类型声明检查

| 码 | 语义 |
| --- | --- |
| `TY-201` | 修饰符位置/组合非法；源码使用 `@arc`/`@gc` |
| `TY-202` | 继承/协议环、final 父类、非法基类 |
| `TY-203` | 方法覆写/同签名冲突 |
| `TY-204` | 结构体值字段限制、递归值包含、deinit 禁止 |
| `TY-205` | 协议形式 |
| `TY-206` | 枚举项唯一/值唯一/形式混用 |
| `TY-207` | 私有字段规范名与外部访问 |

### 5.7 错误与清理规则

| 码 | 语义 |
| --- | --- |
| `ERR-201` | `Result` 值未使用/必须显式观测 |
| `ERR-202` | `Ok`/`Err` 构造参数错误 |
| `ERR-203` | `Result` 成员误用 |
| `ERR-204` | `try` 上下文非法 |
| `ERR-205` | 清理体包含禁止语句 |
| `ERR-206` | `errdefer` 上下文非法 |

清理体不得 `return`/`throw`，保证代码生成可静态展开。

### 5.8 内存策略判定

`Strategy`：

```go
type Strategy struct {
    Decl          string
    Kind          string
    DataEnum      bool
    Policy        string
    StackEligible bool
    Deinit        bool
    SelfCaptured  bool
    RefCycle      bool
    Escape        string
    Rule          int
}
```

判定行：

| 行 | 条件 | 策略 |
| --- | --- | --- |
| 0 | struct | value |
| 2 | protocol | na-gc |
| 3 | 简单枚举 | value |
| 4 | 数据枚举 | gc |
| 5 | 直触发 GC 的强引用字段 | gc |
| 6 | 强引用环 | gc |
| 7 | deinit/捕获 self | arc |
| 8 | 只有值字段 | arc（栈候选） |
| 9 | 其余无环类引用 | arc |

输出按声明名排序（DET-01）。

---

## 6. C 代码生成

### 6.1 生成阶段

```
1. collectResult       登记 Result 实例化
2. registerClassNames  预登记类名（前向引用）
3. collectClass        收集字段/方法签名
4. 建立函数返回类型表
5. 第一遍试生成        收集 Result/容器/类实例化（丢弃产物）
6. 第二遍正式生成      按声明顺序输出函数/类
7. 拼接 prelude、Result typedef、容器助手、类结构/方法、入口垫片
```

第一遍/第二遍的必要性：容器与 Result 需要先知道所有实例化才能生成对应结构；第二遍前重置临时变量编号，保证文本稳定。

### 6.2 C 类型映射

| XNull | C |
| --- | --- |
| `Int` | `int64_t` |
| `Bool` | `int` |
| `String` | `rt_string *` |
| `Result<Int,String>` | `xn_Result_Int_String` |
| `Result<Bool,String>` | `xn_Result_Bool_String` |
| `T[]`/`List<T>` | `xn_arr_<mangle>` |
| `Set<T>` | `xn_set_<mangle>` |
| `Map<K,V>` | `xn_map_<k>_<v>` |
| 类 `C` | `xn_Cls_C *` |
| `void` | `void` |

未覆盖：`Float`/`Double`、`Char`、`null`、`Int128`/`UInt128`、元组、可选、函数类型、闭包、`struct`/`protocol`/`enum` 顶层声明、继承/协议实现、带参构造器。未覆盖构造必须显式报错。

### 6.3 命名

| 对象 | 规则 |
| --- | --- |
| 顶层函数 | `xn_<name>` |
| 参数 | `xn_p_<name>` |
| 类结构 | `xn_Cls_<Name>` |
| 类方法 | `xn_Cls_<Name>_<method>` |
| 类型描述符 | `RT_TYPE_XN_<Name>` |
| Result | `xn_Result_<T>_<E>` |
| 容器 | `xn_arr_/xn_set_/xn_map_` |
| 临时变量 | `xn_t<N>` |
| FFI 包装 | `xn_ffi_<entry>` |

mangle：`int64_t→i`、`int→b`、`rt_string*→s`、`xn_Cls_X*→o_X`。

### 6.4 Result 表示

```c
typedef struct { int ok; int64_t v; rt_string *err; } xn_Result_Int_String;
typedef struct { int ok; int v;       rt_string *err; } xn_Result_Bool_String;
```

- `Ok`：`ok=1, v, err=NULL`；
- `Err`：`ok=0, v=0, err`；
- `try` 检查 `!ok`；
- `isOk`/`isErr` 读 `ok`；
- `unwrapOr` 读 `ok ? v : d`；
- 结果布局不进入运行时 ABI。

### 6.5 容器

```c
typedef struct { size_t len, cap; <elem> *data; } xn_arr_<mangle>;
typedef struct { xn_arr_<mangle> a; } xn_set_<mangle>;
typedef struct { size_t len, cap; <K> *keys; <V> *vals; } xn_map_<k>_<v>;
```

- 每元素类型生成一份静态助手，无运行期注册表；
- 引用元素入容器 retain，覆盖/移除/释放时 release；
- 局部容器作用域退出 free；函数参数借用；
- 支持的成员：数组/List 的 `push/set/remove/clear/length/get/has`；Set 的 `add/length/has`；Map 的 `put/remove/clear/length/has/getOr`；
- `List.insert`、其他成员、嵌套数组显式未支持。

### 6.6 类

```c
typedef struct xn_Cls_Node {
    rt_header hdr;
    <fields...>
} xn_Cls_Node;

static const rt_type RT_TYPE_XN_Node = {
    "Node", sizeof(xn_Cls_Node), xn_Cls_Node_deinit, NULL
};
```

- 单类、无继承、无协议；
- 无参构造；
- 字段初值按声明顺序；
- 字段清理函数释放 String/容器/类引用；
- 用户声明的 `deinit` 方法体当前不生成；含 GC 字段的类尚未生成 scan 钩子；
- 类引用赋值/返回有 retain/release 纪律。

### 6.7 表达式生成

- 临时变量提升：字符串拼接、插值、容器字面量、闭包、`new`、`try`、返回引用类型的调用；
- 求值顺序严格左→右；
- 字符串：字面量 `rt_string_from_c`、`+` 用 `xn_concat`、标识符 `rt_retain`、成员 `rt_retain`、下标/容器 get 借用；
- `str(x)` 当前仅 Int；
- String 成员：`length/indexOf/startsWith/endsWith/substring/trim/toUpper/toLower`；
- 类方法/字段、容器成员、下标读写按接收者类型分派；
- **已知缺口**：插值串表达式段未生成，`plainText` 只拼静态段；当前不在已验收子集内，需补生成或显式拒绝。

### 6.8 语句生成

| 语句 | 生成 |
| --- | --- |
| 表达式语句 | 表达式语句；`print`/`str` 特殊处理 |
| 局部声明 | 声明 + 初始化 |
| 赋值 | `=`；复合赋值显式未支持 |
| 返回 | 清理 + return |
| if | if/else；条件前置语句处理 |
| while | while 或 `while(1)` 降级 |
| for-in | 容器索引循环；区间未接入 |
| defer/errdefer | 注册清理项，块/函数出口展开 |
| throw | `xn_throw`（exit 134） |
| break/continue | 直映射 |

未生成：`do-while`、`switch`、`incdec`、`goto`、`labeled`、`empty`。

### 6.9 defer/errdefer/try

- 清理项按注册逆序展开；
- `defer` 无条件；
- `errdefer` 仅在返回 `Result` 且错误路径触发；
- 普通块退出不触发 `errdefer`；
- `try` 失败：写入返回槽 → 执行清理 → 返回；
- `throw fatal` 不展开 defer。

### 6.10 所有权

- 字符串字面量新串；`xn_concat` 接管两侧；
- String 标识符作为消费值前 `rt_retain`；
- String 局部赋值旧串 release；
- 类引用赋值先求值新值、再 release 旧值、后赋值；
- 类引用返回标识符先 retain；`new` 产物直接移交；
- 容器元素引用 retain/release；
- 完整 §3.3 八条尚未全部兑现；GC 根/scan 生成仍不完整。

### 6.11 FFI 接入

代码生成消费 FFI 合同层产出的注册表：

- `EmitCall`/`EmitSupport` 生成包装与支撑代码；
- `ffi_gen.go` 负责 P-09 接线：`LoadFFI` → `InjectFFI`（包级可调用声明）→ `UnsupportedFFIEntries` 提示 → `EmitCWithFFI`；
- `InjectFFI` 当前只注入 void/Int/String 返回、Int/String 参数；`@errorCode`、句柄 close、Bytes/数组/布局/句柄等显式跳过；
- 调用点符号 `xn_ffi_<entry>`；String 实参当前只支持变量，生成 `->bytes`/`->len` 借出视图；
- 非零错误码输出 fatal 并 `exit(134)`；当前不映射为 `Result`；
- 生成代码只 include `xrt.h`；
- 未生成形态记入 `Problems`/提示，构建必须失败或显式告警；
- `LinkArgs` 由构建层消费，代码生成不负责链接。

详细边界见模块 05 §8.2。

### 6.12 确定性

- Result/容器/类实例化按名称排序；
- 临时变量编号在第二遍前重置；
- 诊断按位置稳定排序；
- 同一源程序 + 同一版本 → 相同 C 文本；
- 禁止依赖 map 遍历顺序或文件系统枚举顺序。

---

## 7. 诊断与失败

| 阶段 | 诊断来源 | 码段 |
| --- | --- | --- |
| 装载 | import/包一致性 | RES-106/108/110 |
| 词法 | xfront | LEX-101—106 |
| 语法 | xfront | SYN-101—111 |
| 名称/导入 | sema | RES-101—108、RES-111 |
| 确定赋值 | sema | DA-101—103 |
| 类型 | sema | TY-101/103/104/105 |
| 类型声明 | sema | TY-201—207 |
| 清理规则 | sema | ERR-201—206 |
| 代码生成 | codegen | 显式错误文本；不新增语义码段 |

约束：

- 前端/语义诊断先于代码生成返回；
- 代码生成失败视为内部/未支持构造，不静默降级；
- 诊断值由上层统一渲染；编译器不直接写 stderr；
- 同一输入诊断顺序可复现。

---

## 8. 接口

### 8.1 源文件装载

```go
func LoadUnits(entryPath string) (*xfront.CompilationUnit, []diag.Diagnostic)
```

### 8.2 前端

```go
func Lex(file, src string) ([]Token, []diag.Diagnostic)
func ParseExpr(file, src string) (Expr, []diag.Diagnostic)
func ParseStmts(file, src string) ([]Stmt, []diag.Diagnostic)
func ParseUnit(file, src string) (*CompilationUnit, []diag.Diagnostic)
func PrintUnit(u *CompilationUnit) string
```

### 8.3 语义

```go
func Analyze(file string, u *xfront.CompilationUnit) []diag.Diagnostic
func AnalyzeWith(file string, u *xfront.CompilationUnit) (*Result, []diag.Diagnostic)
func (r *Result) Strategies(u *xfront.CompilationUnit) []Strategy
```

### 8.4 代码生成

```go
func EmitC(u *xfront.CompilationUnit) (string, error)
```

---

## 9. 验证与边界

### 9.1 验证面

| 验证 | 内容 |
| --- | --- |
| 词法矩阵 | LEX-01 |
| 表达式/语句/编译单元 | EXPR-01、STMT-01 |
| 类型/赋值/声明 | TYPE-01/02、FIELD-01、INH-01 |
| 策略 | DET-01、MEM-01 可判定面 |
| 代码生成 | 黄金 C、示例双路径、构建参数 |
| 多文件 | import 闭包、环、包一致性、合并顺序 |
| 确定性 | 两次生成逐字节一致 |

### 9.2 当前边界

| 能力 | 状态 |
| --- | --- |
| 词法/表达式/语句/编译单元 | 已覆盖；singleton/extension/annotation 声明显式拒绝 |
| 名称/确定赋值/基础类型检查 | 主路径覆盖；泛型/包符号表已接入，协议/完整单态化部分 |
| 类型声明结构检查 | 部分（对象面随 S2 完整度） |
| 策略判定 | 类型级完整；对象级逃逸未回填 |
| 代码生成 | 子集；未支持构造显式拒绝 |
| 类生成 | 单类、无继承/协议/带参构造 |
| 容器 | 元素限 Int/Bool/String/类引用 |
| 闭包/元组/可选/`is`/`as` | 代码生成未接入 |
| 插值串表达式段 | 未生成（需补） |
| 多包编译 | 命名包可导入命名包；符号扁平链接；包前缀/独立编译单元后续 |

### 9.3 设计约束

- 代码生成不重新做语义判定；
- 不修改 AST 语义；
- 不把诊断写进 C 文本；
- 不对未支持构造生成“看起来能跑”的替代代码；
- 输出文本必须可复现；
- 任何新增语言构造都必须同时定义其 C 表示与错误边界。

---

## 规范依据与实现选择

### 规范依据

| 第 1—8 部分条款 | 本模块落实 |
| --- | --- |
| 第 1 部分 §1—§11 | 词法、表达式、语句、编译单元、入口、错误语法 |
| 第 2 部分 §1—§15 | 类/结构/协议/枚举声明、对象模型、布局与策略输入 |
| 第 3 部分 §4—§6、§15.1 | 策略判定输入、逃逸分类、判定行 |
| 第 4 部分 §10 | `Result`/`try`/`defer`/`errdefer` 语义 |

### 实现选择

- Go 包划分 `xfront`/`sema`/`codegen`；
- AST 结构体与位置字段；
- 两遍生成与临时变量编号；
- C 命名/mangle 规则；
- 未支持构造的显式错误文本。

以上均为实现选择，不新增语言语义；与第 1—4 部分冲突时以母本为准。

## 10. 参考

- `XNull解决方案-第1部分-基础语法-v3.4.0.md`
- `XNull解决方案-第2部分-对象编程-v3.4.0.md`
- `XNull解决方案-第3部分-内存管理-v3.1.0.md`
- `XNull解决方案-第4部分-错误处理-v1.1.0.md`
- `impl/internal/xfront/`
- `impl/internal/sema/`
- `impl/internal/codegen/`
- `impl/docs/m2-sema-plan.md`
- `impl/docs/m4-codegen-design.md`
