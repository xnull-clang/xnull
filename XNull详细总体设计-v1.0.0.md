# XNull 详细总体设计

| 项 | 值 |
| --- | --- |
| 文档编号 | XNULL-DESIGN-002 |
| 文档版本 | 1.0.0 |
| 文档性质 | 工程设计文档（非规范性；规范冲突时以 S1—S8 母本为准） |
| 编制日期 | 2026-11-07 |
| 代码基线 | `ea6fdf3`（2026-11-07，M6-B0 进行中） |
| 适用工具链 | `xnull 0.1.0-dev` |
| 适用规范 | S1 v3.3.0、S2 v3.3.0、S3 v3.0.0、S4 v1.0.0、S5 v1.0.0、S6 v1.1.0、S7 v1.0.0、S8 v5.2.0 |
| 配套文档 | 《XNull 软件总体设计》`XNull软件总体设计-v1.0.0.md` |
| 别名说明 | 本文 S4/S5/S6/S7/S8 分别指第 4/5/6/7/8 部分；与索引历史别名不一致时，以部分号为准 |

## 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| 1.0.0 | 2026-11-07 | 首版。按当前代码基线展开模块结构、关键数据结构、算法、接口、测试与自举准备度。 |

---

## 0. 阅读指南

### 0.1 本文与总体设计的分工

《XNull 软件总体设计》回答“系统由什么组成、为什么这样分层、外部接口是什么”。本文回答“每个模块内部怎么组织、关键数据怎么表示、算法怎么走、接口签名是什么、当前实现到哪一步”。

本文不替代规范母本。涉及语言语义的最终解释以 S1—S8 为准；涉及实现行为以当前代码为基线。若本文与代码不一致，先按代码核实，再回写本文，避免“文档成为第二套实现”。

### 0.2 标记约定

| 标记 | 含义 |
| --- | --- |
| **已实现** | 当前代码存在，且有测试或可复现命令 |
| **部分** | 主路径存在，但覆盖不完整或缺少端到端接线 |
| **设计目标** | 合同/文档已定义，代码尚未接入 |
| **显式拒绝** | 当前实现主动报错，不做静默降级 |
| `文件:行号` | 直接指向实现位置；行号随代码变动，仅作定位起点 |

### 0.3 代码基线

- 工具链模块：`xnull.dev/xnull`，Go 1.27；
- 入口：`impl/cmd/xnull/main.go`；
- 构建：`cd impl && go build -o xnull ./cmd/xnull`；
- 测试：`go vet ./... && go test ./... -count=1`；
- C 运行时：`sh impl/runtime/build_rt.sh`；
- 当前代码基线：`ea6fdf3`。

---

## 1. 代码组织与依赖

### 1.1 目录树

```
impl/
├── cmd/xnull/main.go             CLI 入口、信号处理
├── internal/
│   ├── cli/                      命令分派、run/build/policy/dev
│   ├── xfront/                   词法、语法、AST、打印、编译单元
│   ├── sema/                     名称、确定赋值、类型、类型声明、策略、清理规则
│   ├── codegen/                  AST → C、类、容器、字符串、Result、多文件、构建
│   │   └── ffi/                  .xfb 解析、合同校验、注册表、包装生成
│   ├── interp/                   tree-walking 解释器（--interp）
│   ├── xpd/                      XPD 词法/文法/AST
│   ├── devtool/                  check / ledger / res
│   ├── diag/                     诊断结构与渲染
│   └── exitcode/                 退出码常量
├── runtime/                      C 运行时、稳定 ABI、XDK 原语、C 测试
├── lib/xdk/                      XDK 公开 API 的 XNull 源码（种子）
├── docs/                         实现设计、合同、一致性状态
└── go.mod

bindings/xdk/                     XDK 的 .xfb 绑定声明
examples/                         可运行示例（含 multi/ 与自举种子）
ci/                               CI 入口与步骤库
evidence/                         证据目录
```

### 1.2 生产依赖方向

```
cmd/xnull
  └── internal/cli
        ├── internal/xfront
        ├── internal/sema
        ├── internal/codegen
        │     ├── internal/xfront
        │     ├── internal/sema
        │     ├── internal/codegen/ffi
        │     └── internal/diag
        ├── internal/interp
        │     └── internal/xfront
        ├── internal/devtool
        ├── internal/xpd
        ├── internal/diag
        └── internal/exitcode
```

约束：

1. `codegen` 只消费 `sema` 的检查结果，不重新做语义判定；
2. `ffi` 只依赖 `diag`，不反向依赖 `codegen`；
3. `interp` 只依赖 `xfront`，不依赖 `sema` 或 `codegen`；
4. `sema` 不依赖 `codegen`；
5. 生产代码不得形成循环依赖；测试可以跨包引用。

### 1.3 包职责速查

| 包 | 入口 | 输出 | 备注 |
| --- | --- | --- | --- |
| `xfront` | `Lex`、`ParseExpr`、`ParseStmts`、`ParseUnit`、`PrintUnit` | AST、诊断 | 语法层全部；类型声明在 `types.go` |
| `sema` | `Analyze`、`AnalyzeWith` | 诊断、`Result.Strategies` | 多遍分析 |
| `codegen` | `EmitC`、`LoadUnits`、`Build`/`BuildWithOptions` | C 文本、可执行文件、诊断 | 生成文本是验收面 |
| `ffi` | `Load`、`EmitCall`、`EmitSupport`、`LinkArgs` | 注册表、C 片段、链接参数 | 只 include `xrt.h` |
| `interp` | `Run` | 退出码、错误 | Go 值模型；不模拟 ARC |
| `xpd` | `Parse` | XPD AST、诊断 | 只做解析 |
| `devtool` | `CheckSpecs`、`GenerateLedger`、`GenerateResources` | 文本、C 源 | 仓库维护 |
| `diag` | `Diagnostic.String` | 诊断文本 | 统一格式 |
| `exitcode` | 常量 | 退出码 | 0/1/2/130 |

---

## 2. 前端 `internal/xfront`

### 2.1 词法分析

入口：`Lex(file, src string) ([]Token, []diag.Diagnostic)`（`impl/internal/xfront/lexer.go:36`）。

#### 2.1.1 输入规范化

| 项 | 行为 | 规范依据 |
| --- | --- | --- |
| 编码 | UTF-8；按 rune 扫描 | S1 §1.1 |
| BOM | 仅允许文件开头；不参与列号 | S1 §1.1 |
| 换行 | CRLF 归一化为 LF | S1 §1.1 |
| 列号 | 按 Unicode 标量计数，1 基 | S1 §1.1 |
| 注释 | 行注释、块注释、文档注释；块注释不嵌套 | S1 §1.2 |
| 诊断 | 词法错误不中断，可报多条 | S1 §1.7 |

#### 2.1.2 Token 模型

`Kind` 枚举（`token.go`）：

| 类别 | 值 | 说明 |
| --- | --- | --- |
| `EOF` | 文件结束 | |
| `Semi` | `;` | 含自动分号插入 |
| `Ident` | 标识符 | |
| `Keyword` | 关键字 | |
| `Annotation` | `@name` | 注解 token |
| `IntLit` / `FloatLit` / `CharLit` / `StrLit` | 字面量 | 字符串带 `StrKind`、`Value`、`Segs`、`Interps` |
| `Op` | 运算符 | 最长匹配 |
| `LParen` / `RParen` / `LBrace` / `RBrace` / `LBrack` / `RBrack` / `Comma` | 标点 | |

`Token` 关键字段：

```go
type Token struct {
    Kind Kind
    Text string   // Ident/Keyword/Op/Annotation 原文；字面量源文本
    Pos  Pos      // Line, Col（1 基）
    Str     StrKind
    Value   string
    Segs    []string // 插值串静态段
    Interps []string // 插值表达式原文
    Char    rune
}
```

#### 2.1.3 字面量与运算符

- 整数字面量：十进制/十六进制/八进制/二进制，支持 `L`/`U`/`UL` 后缀；
- 浮点：小数与指数，支持 `f` 后缀；
- 字符：转义与 `\u{…}` 标量校验；
- 字符串：普通、raw、多行、raw 多行、插值五种形态；
- 运算符按最长匹配；`as?` 是单 token；
- 自动分号插入：可插入集合、`}` 后 `else`/`while` 不插、空行与注释行不触发、EOF 前补插。

#### 2.1.4 词法诊断

| 码 | 语义 |
| --- | --- |
| `LEX-101` | 无法识别的字符 |
| `LEX-102` | 未闭合的注释/字符串/字符字面量 |
| `LEX-103` | 未知转义、位数不足、非法标量值 |
| `LEX-104` | 非法数字格式、下划线位置错误、后缀冲突 |
| `LEX-105` | 非法插值表达式边界 |
| `LEX-106` | 空字符字面量、多字符、跨行 |

### 2.2 AST

#### 2.2.1 顶层接口

```go
type Expr interface { Pos() Pos; exprNode() }
type Stmt interface { Pos() Pos; stmtNode() }
type TypeRef interface { Pos() Pos; typeNode() }
type TopDecl interface { Pos() Pos; topDecl() }
```

#### 2.2.2 表达式节点

| 节点 | 用途 |
| --- | --- |
| `IdentExpr` | 标识符 |
| `IntLitExpr` / `FloatLitExpr` / `CharLitExpr` / `BoolLit` / `NullLit` | 字面量 |
| `StrLitExpr` | 字符串/插值串（`Parts []StrPart`，每段 `Text` 或 `Expr`） |
| `Paren` | 括号 |
| `Tuple` | 元组字面量 |
| `ArrayLit` / `MapLit` | 数组/映射字面量 |
| `Unary` / `Binary` / `Ternary` | 一元/二元/三元 |
| `Member` / `TupleMember` | 成员访问 / 元组位置访问 |
| `Call` | 调用（含泛型实参） |
| `Index` | 下标 |
| `New` / `NewArray` | 类实例化 / 数组分配 |
| `Lambda` | 闭包字面量 |
| `TypeAsExpr` | `is` / `as` / `as?`（由 parser 定义） |

#### 2.2.3 语句节点

| 节点 | 用途 |
| --- | --- |
| `Block` | 块 |
| `ReturnStmt` | return |
| `ExprStmt` | 表达式语句 |
| `LocalDeclStmt` | 局部声明 |
| `AssignStmt` | 赋值（含复合赋值运算符记录） |
| `IncDecStmt` | 自增/自减（仅语句） |
| `IfStmt` / `WhileStmt` / `DoWhileStmt` | 条件/循环 |
| `ForStmt` | `for x in src`（容器或区间） |
| `SwitchStmt` / `SwitchCase` | switch（无隐式贯穿） |
| `DeferStmt` | `defer` / `errdefer` |
| `BreakStmt` / `ContinueStmt` / `GotoStmt` / `LabeledStmt` | 跳转 |
| `ThrowStmt` | `throw fatal` |
| `EmptyStmt` | 空语句 |

#### 2.2.4 类型引用

| 节点 | 形态 |
| --- | --- |
| `NamedType` | `Name` + 可选泛型实参 `Args` + 点分限定 `Qual` |
| `SuffixedType` | 后缀 `[]`、`?` 等 |
| `FuncTypeRef` | 函数类型 |
| `TupleTypeRef` | 元组类型 |

#### 2.2.5 顶层声明

| 节点 | 文件 | 说明 |
| --- | --- | --- |
| `PackageDecl` / `ImportDecl` | `unit.go` | 包与导入 |
| `TopFunc` / `TopField` | `unit.go` | 顶层函数/字段 |
| `ClassDecl` | `types.go` | 类：字段、方法、构造器、基类、协议 |
| `StructDecl` | `types.go` | 纯值结构体 |
| `ProtocolDecl` | `types.go` | 协议方法签名 |
| `EnumDecl` | `types.go` | 简单/数据枚举 |

`ClassDecl` 关键字段：

```go
type ClassDecl struct {
    P         Pos
    Annos     []*AnnotationNode
    Mod       TypeModifiers
    Name      string
    TypePars  []string
    Primary   *CtorDecl
    Base      TypeRef
    Protocols []*NamedType
    Fields    []*FieldDecl
    Methods   []*MethodDecl
    Ctors     []*CtorDecl
}
```

`FieldDecl` 的 `Canonical` 字段保存私有字段规范名（S2 §7.4）；`MethodDecl.IsDeinit` 归一 `void deinit()`。

### 2.3 语法分析

#### 2.3.1 入口

| 函数 | 用途 |
| --- | --- |
| `ParseExpr(file, src)` | 解析单个表达式 |
| `ParseStmts(file, src)` | 解析语句序列 |
| `ParseUnit(file, src)` | 解析完整编译单元 |

`ParseUnit` 顺序：

1. `Lex` 得到 token 与词法诊断；
2. `dropSemiInAnnotation` 丢弃注解与所附声明之间的自动分号；
3. 解析可选的 `package`；
4. 解析零个或多个 `import`；
5. 循环 `parseTopDecl` 直到 EOF；
6. 返回 AST 与全部诊断（不中断）。

#### 2.3.2 表达式优先级

从低到高：

| 层级 | 运算符/形态 | 解析函数 |
| --- | --- | --- |
| 1 | 三元 `?:` | `parseTernary` |
| 2 | `??` | `parseCoalesce` |
| 3 | `||` | `parseLogicalOr` |
| 4 | `&&` | `parseLogicalAnd` |
| 5 | `|` | `parseBitOr` |
| 6 | `^` | `parseBitXor` |
| 7 | `&` | `parseBitAnd` |
| 8 | `==` `!=` | `parseEquality` |
| 9 | `<` `<=` `>` `>=` | `parseComparison` |
| 10 | 区间 | `parseRange` |
| 11 | `<<` `>>` | `parseShift` |
| 12 | `+` `-` | `parseAdditive` |
| 13 | `*` `/` `%` | `parseMultiplicative` |
| 14 | 一元 `!` `-` `+` `~` 等 | `parseUnary` |
| 15 | 后缀：调用、成员、下标、`new` 等 | `parsePostfix` |
| 16 | 主表达式 | `parsePrimary` |

关键歧义处理：

- `(` 起头：括号、元组、Lambda 三态，通过回溯与参数形态判定；
- `Type name` 局部声明 vs 表达式：`tryLocalDecl` / `tryTypeRefQuiet` 回溯；
- `new Type(`：`(` 是构造实参，不是函数类型；
- 泛型实参：`tryTypeArgs` 前瞻尖括号配平；
- `as?` 单 token，避免与 `as` + `?` 混淆；
- 类型声明：`parseTopDecl` 识别 `class/struct/protocol/enum`，`singleton/extension/annotation` 仍报 `SYN-110`；
- 注解行：`dropSemiInAnnotation` 避免自动分号切断注解与声明。

#### 2.3.3 语句解析

- 体强制花括号：`if/while/for/switch` 体非块即 `SYN-101`；
- 语句终止：显式 `;`、换行、`}`、EOF；同一行缺分号 `SYN-108`；
- 赋值目标校验：括号/可选链目标不在 Assignable 集即 `SYN-109`；
- `switch`：`case`/`default` 标签豁免语句终止检查；`default` 最多一个且在最后；子句独立作用域；
- `defer`/`errdefer`：体可以是块或单条语句；
- 标签：`name:` 与语句同层解析；`name: ;` 合法。

#### 2.3.4 语法诊断

| 码 | 语义 |
| --- | --- |
| `SYN-101` | 期望某 token 却遇到其他 |
| `SYN-102` | 比较运算不可链式 |
| `SYN-103` | 范围运算不可链式 |
| `SYN-104` | 元组字面量/类型至少两个元素 |
| `SYN-105` | `new` 后必须是 `(` 或 `[` |
| `SYN-106` | 表达式结束后存在未消费输入 |
| `SYN-107` | 范围只允许出现在 for-in 源位置（解析不报；语义层约束尚未接入） |
| `SYN-108` | 同一行缺分号 |
| `SYN-109` | 赋值/自增目标不在 Assignable 集 |
| `SYN-110` | 类型声明属后续批次（singleton/extension/annotation 等） |
| `SYN-111` | 用户包名使用保留命名空间 `xdk` |

### 2.4 打印器

`printer.go` 提供：

- `PrintExpr(e Expr) string`
- `PrintStmt(s Stmt) string`
- `PrintUnit(u *CompilationUnit) string`
- `PrintType(t TypeRef) string`

用途：

- 测试中断言 AST 结构；
- 解析器的可读诊断；
- 未来 `xnfmt`（B1）的基础；当前 `PrintUnit` 输出 AST 形态、不是源码格式化器，且类型声明打印尚未覆盖，不承诺与 Go 版逐字节一致。

### 2.5 编译单元与多文件加载

`LoadUnits` 在 `impl/internal/codegen/multifile.go`，虽然位于 codegen 包，但逻辑属于“编译单元装载”：

| 规则 | 行为 |
| --- | --- |
| import 映射 | `import p1.p2` → 入口所在目录的 `p1/p2.x` |
| `xdk.*` | 由 sema 处理，加载器不解析为文件 |
| 环检测 | 访问中再次到达 → `RES-108` |
| 缺失文件 | `RES-106` |
| 重复导入 | 同一文件只加载一次；import 列表去重 |
| 包一致性 | 子文件包名必须与入口一致，否则 `RES-109` |
| 默认包 | 默认包跨文件组合视为同一编译单元的分片 |
| 合并顺序 | 依赖优先的后序；同一 import 列表按源码书写顺序 |
| 子文件缺 package | `RES-110` |

`LoadUnits` 的输出是**单一** `CompilationUnit`，`Decls` 按依赖先后合并；解释器与编译路径共用它，保证双路径看到同一组声明。

### 2.6 前端当前边界

| 能力 | 状态 |
| --- | --- |
| 词法全矩阵 | 已实现，LEX-01 PASS |
| 表达式/语句/编译单元 | 已实现，STMT-01 PASS |
| class/struct/protocol/enum 解析 | 已实现（M2.5.1） |
| singleton/extension/annotation 声明 | 显式 `SYN-110` |
| 完整格式化器 | 未实现；`PrintUnit` 仅打印 AST |
| 跨包多包编译 | 不支持；`RES-109`，属工程清单批次 |

---

## 3. 语义分析 `internal/sema`

### 3.1 分析管线

入口：

```go
func Analyze(file string, u *xfront.CompilationUnit) []diag.Diagnostic
func AnalyzeWith(file string, u *xfront.CompilationUnit) (*Result, []diag.Diagnostic)
```

`AnalyzeWith` 顺序（`impl/internal/sema/sema.go:56`）：

```
1. analyzeImports      导入可见性、XDK 包、别名、歧义
2. checkTypeDecls      类型声明结构检查（class/struct/protocol/enum）
3. collectTop          顶层函数/字段名字空间
4. walkBlock           名称解析（局部/参数/类型参数 → 顶层 → 导入 → 限定名）
5. analyzeAssign       确定赋值与返回路径（数据流）
6. analyzeTypes        类型检查（可赋值性、推断、调用、运算符、成员）
7. ComputeStrategies   内存策略判定（按需由 Result.Strategies 调用）
```

诊断不中断：一个编译单元可返回多条；顺序由遍历顺序决定，最终输出前可按位置稳定排序。

### 3.2 名称解析

`analyzer` 保存：

```go
type analyzer struct {
    file      string
    diags     []diag.Diagnostic
    tops      map[string]bool // 当前包顶层声明
    hasImp    bool
    imported  map[string]bool // 导入可见简单名
    ambiguous map[string]bool // 未消歧简单名
    tc        *typeCheckCtx
    seenTop   map[string]bool
}
```

`nscope` 是词法作用域链，支持：

- `define`：当前作用域声明；
- `declared`：沿链查找；
- `declaredHere`：仅当前作用域；
- 遮蔽合法性按 S1 §5.2 检查；
- 同一作用域重复声明 → `RES-102`；
- 名称不可见 → `RES-101`。

四级解析（S1 §3.3）：

1. 局部变量、参数、类型参数；
2. 当前包顶层；
3. 导入符号；
4. 完全限定名。

导入族诊断：

| 码 | 语义 |
| --- | --- |
| `RES-103` | 导入别名冲突 |
| `RES-104` | 未消歧的简单名 |
| `RES-105` | XDK 包未显式导入 |
| `RES-106` | 包或符号不存在 |
| `RES-107` | 非冲突场景使用 `as` 别名 |

XDK 符号表在 `sema/xdk.go`：只登记 S6 定案的公开 API；未定案名称不猜。`import xdk.sys` 后，`checkTypeXdkUse` / `checkXdkUse` 校验使用点。

### 3.3 确定赋值

`assign.go` 用路径状态集合实现 S1 §5.3：

```go
type dstate struct {
    assigned   map[string]bool
    final      map[string]bool
    unreachable bool
}
```

规则：

- `mergeDstates` 对分支状态取交集：只有所有路径都赋值的变量才算确定赋值；
- `if`/`else`、`while`/`do-while`、`for`、`switch`、`break`/`continue`/`return`/`goto` 都参与汇合；
- `&&`/`||`/`??`/`try` 的路径合并按规范；
- `final`/`const` 声明后再次赋值 → `DA-102`；
- 非 `void` 函数存在正常返回路径 → `DA-103`；
- 读取可能未赋值变量 → `DA-101`。

### 3.4 类型检查

`ty.go` 的 `texpr` 是轻量静态类型：

```go
type texpr struct {
    key string // 规范化类型串；"" 未知；"void" 表示 void
    lit int    // 0 普通；1 整数字面量；2 浮点字面量；3 字符串字面量；4 null
}
```

`typeKey` 把 `TypeRef` 转为规范串；`assignable(from, to)` 实现 S1 §2.6：

- 同一类型；
- `null` 到可空类型；
- 字面量适配（整数/浮点/字符串）；
- 容器字面量；
- 闭包目标检查；
- `Any` 装箱与 `Object` 根；
- 隐式数值转换拒绝。

类型推断：

- `inferExpected(x, want)` 在目标类型已知时推断 `Ok`/`Err`、Lambda、容器字面量；
- `infer` 处理字面量、标识符、成员、调用、二元、三元、`new`、下标、元组等；
- 函数调用按 `funcs` 签名表做重载/参数检查；
- 成员调用按内建容器/String/Result/类方法分派；
- 运算符按 `arith`/比较/逻辑规则检查。

诊断：

| 码 | 语义 |
| --- | --- |
| `TY-101` | 可赋值性失败 |
| `TY-103` | `null` → 非可空值类型 |
| `TY-104` | 条件必须是 Bool |
| `TY-105` | 无效运算操作数 |

### 3.5 类型声明检查

`typedecl.go` 在名称解析前运行，建立 `typeInfo` 表：

```go
type typeInfo struct {
    kind   string // class/struct/protocol/enum
    mod    xfront.TypeModifiers
    class  *xfront.ClassDecl
    strct  *xfront.StructDecl
    // ...
}
```

检查项：

| 码 | 语义 |
| --- | --- |
| `TY-201` | 修饰符位置/组合非法；`@arc`/`@gc` 源码使用 |
| `TY-202` | 继承/协议环、final 父类、非法基类 |
| `TY-203` | 方法覆写/同签名冲突 |
| `TY-204` | 结构体值字段限制、递归值包含、deinit 禁止 |
| `TY-205` | 协议形式（方法签名、重复、修饰符） |
| `TY-206` | 枚举项唯一/值唯一/简单与数据形式混用 |
| `TY-207` | 私有字段规范名与外部访问规则 |

其他检查：

- 类字段类型、方法签名、构造器、主构造器；
- `struct` 只允许值字段；
- `protocol` 方法签名无体；
- 数据枚举字段/构造器/方法；
- `super` 链与 `deinit` 约束；
- `self` 捕获（保守：闭包体内出现 `self` 即视为捕获）。

### 3.6 错误与清理规则

`error.go` 的 ERR-2xx：

| 码 | 语义 |
| --- | --- |
| `ERR-201` | `Result` 值未使用/必须显式观测 |
| `ERR-202` | `Ok`/`Err` 构造参数不匹配 |
| `ERR-203` | `Result` 成员不合法 |
| `ERR-204` | `try` 上下文非法 |
| `ERR-205` | 清理体（defer/errdefer）包含禁止语句 |
| `ERR-206` | `errdefer` 上下文非法 |

清理体限制：不允许 `return`/`throw` 等改变控制流的语句，保证代码生成可静态展开。

### 3.7 内存策略判定

`policy.go` 的 `Strategy` 是冻结结构：

```go
type Strategy struct {
    Decl          string `json:"decl"`
    Kind          string `json:"kind"`   // class/struct/enum/protocol
    DataEnum      bool   `json:"data"`
    Policy        string `json:"policy"` // value/arc/gc/na-gc
    StackEligible bool   `json:"stackEligible"`
    Deinit        bool   `json:"deinit"`
    SelfCaptured  bool   `json:"selfCaptured"`
    RefCycle      bool   `json:"refCycle"`
    Escape        string `json:"escape"` // 对象级逃逸；类型级 "n/a"
    Rule          int    `json:"rule"`
}
```

判定行（`rt_policy.c`）：

| 行 | 条件 | 策略 |
| --- | --- | --- |
| 0 | struct | value |
| 2 | protocol | na-gc |
| 3 | 简单枚举 | value |
| 4 | 数据枚举 | gc |
| 5 | 存在直触发 GC 的强引用字段 | gc |
| 6 | 强引用环 | gc |
| 7 | 有 deinit 或捕获 self | arc |
| 8 | 只有值字段 | arc（栈候选） |
| 9 | 其余无环类引用 | arc |

字段分类（`fieldRefClass`）：

| 分类 | 含义 |
| --- | --- |
| `value` | 标量/简单枚举/struct/值元组/可空值 |
| `gc` | `Any`/`Object`/协议/未单态化泛型/`Result`/含引用元组/函数类型 |
| `ref` | 内建引用类型、数据枚举 |
| `class:Name` | 具体类引用，参与环分析 |

确定性：`ComputeStrategies` 按 `Decl` 名称排序；`rt_decide_policy` 是纯函数。

### 3.8 语义分析当前边界

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| 名称解析第 1/2 级 | 已实现 | 局部/参数/顶层 |
| 导入符号/限定名 | 部分 | XDK 符号表 + 导入诊断；完整多包符号表未接入 |
| 确定赋值 | 已实现 | DA-101—103 |
| 类型检查基础 | 已实现 | TY-101/103/104/105 |
| 类/结构/协议/枚举结构检查 | 部分 | TY-201—207；完整对象面与运行时联动未齐 |
| 泛型/单态化 | 部分 | 泛型参数解析、策略判定；完整实例化未实现 |
| 协议派发 | 未实现 | DISP-01 |
| 注解语义 | 未实现 | ANN-01 |
| 整数宽度/128 位 | 部分 | 词法接受；执行层不支持 |

---

## 4. 代码生成 `internal/codegen`

### 4.1 生成架构

入口：

```go
func EmitC(u *xfront.CompilationUnit) (string, error)
```

`gen` 保存：

```go
type gen struct {
    results map[string]string     // Result 实例化名 → v 成员类型
    cs      *containers           // 容器实例化注册表
    fnRet   map[string]string     // 顶层函数名 → 返回 C 类型
    classes map[string]*classInfo // 类名 → 生成信息
    tmp     int
}
```

生成流程：

```
1. collectResult：扫描顶层函数与局部声明，登记 Result 实例化
2. registerClassNames：预登记类名，支持前向引用
3. collectClass：收集类字段/方法签名
4. 建立 fnRet：顶层函数返回 C 类型（检查重载）
5. 第一遍试生成：收集 Result/容器/类实例化（产物丢弃）
6. 第二遍正式生成：按声明顺序输出函数/类
7. 拼接 prelude、Result typedef、容器助手、类结构/方法、入口垫片
```

第一遍/第二遍的原因：容器与 Result 需要先知道所有实例化，才能生成对应结构体与助手；`tmp` 在第二遍前重置，保证输出稳定。

### 4.2 C 类型映射

`cType` 当前支持：

| XNull 类型 | C 表示 | 备注 |
| --- | --- | --- |
| `Int` | `int64_t` | |
| `Bool` | `int` | 0/1 |
| `String` | `rt_string *` | 单一所有权字符串 |
| `Result<Int,String>` | `xn_Result_Int_String` | `{ int ok; int64_t v; rt_string *err; }` |
| `Result<Bool,String>` | `xn_Result_Bool_String` | `v` 为 `int` |
| `T[]` / `List<T>` | `xn_arr_<mangle>` | 元素限 Int/Bool/String/类引用 |
| `Set<T>` | `xn_set_<mangle>` | 内含 `xn_arr_<mangle>` |
| `Map<K,V>` | `xn_map_<k>_<v>` | 键/值限支持类型 |
| 类 `C` | `xn_Cls_C *` | 单类、无继承/协议 |
| `void` | `void` | |

当前**显式拒绝**或未覆盖：

| 类型/构造 | 行为 |
| --- | --- |
| `Float` / `Double` | `codegen：Float 未支持` |
| `Char` | `codegen：Char 未支持` |
| `null` | `codegen：null 未支持` |
| `Int128` / `UInt128` | 执行层不支持 |
| 元组 | 顶层声明/类型未接入 |
| 可选 `T?` | 未接入 |
| 函数类型/闭包 | 未接入 |
| `struct` / `protocol` / `enum` 顶层声明 | `EmitC` 只处理 `TopFunc`/`ClassDecl`，其余显式错误 |
| `Result` 值类型 | 仅 Int/Bool；错误类型仅 String |
| 继承/协议实现 | 类生成显式拒绝 |
| 带参构造器 | `emitNewClass` 显式拒绝 |

### 4.3 命名与 mangle

| 对象 | 规则 | 代码位置 |
| --- | --- | --- |
| 顶层函数 | `xn_<name>` | `codegen.go` |
| 函数参数 | `xn_p_<name>` | `codegen.go` |
| 类结构 | `xn_Cls_<Name>` | `classes.go:48` |
| 类方法 | `xn_Cls_<Name>_<method>` | `classes.go:50` |
| 类型描述符 | `RT_TYPE_XN_<Name>` | `classes.go:49` |
| Result | `xn_Result_<T>_<E>` | `codegen.go:332` |
| 数组 | `xn_arr_<mangle>` | `containers.go:89` |
| Set | `xn_set_<mangle>` | `containers.go:94` |
| Map | `xn_map_<k>_<v>` | `containers.go:99` |
| 临时变量 | `xn_t<N>` | `scope.tmp` |
| FFI 包装 | `xn_ffi_<entry>` | `ffi/emit.go` |

mangle：

```go
int64_t      → i
int          → b
rt_string *  → s
xn_Cls_X *   → o_X
```

mangle 是纯函数；同一类型在容器/Result/函数签名中始终得到同一后缀。

### 4.4 Result 表示

生成：

```c
typedef struct { int ok; int64_t v; rt_string *err; } xn_Result_Int_String;
typedef struct { int ok; int v;       rt_string *err; } xn_Result_Bool_String;
```

约定：

- `Ok(v)` → `{ ok = 1, v, err = NULL }`；
- `Err(e)` → `{ ok = 0, v = 0, err = e }`；
- `try` 检查 `!r.ok`；
- `isOk()` / `isErr()` 读 `ok`；
- `unwrapOr(d)` 读 `ok ? v : d`；
- `error()` 复制 err 串（`xn_result_error_copy_rt`）；
- Result 布局不进入运行时 ABI；成员访问由 codegen 内联。

### 4.5 容器表示

`containers.go` 的私有表示：

```c
/* T[] / List<T> */
typedef struct { size_t len, cap; <elem> *data; } xn_arr_<mangle>;

/* Set<T> */
typedef struct { xn_arr_<mangle> a; } xn_set_<mangle>;

/* Map<K,V> */
typedef struct { size_t len, cap; <K> *keys; <V> *vals; } xn_map_<k>_<v>;
```

助手函数按元素类型实例化，静态生成；不使用运行期元素描述符注册表（P-03 评审结论）。

所有权：

- 局部容器在作用域退出 `free`（`deferItem` 记录）；
- 函数参数为借用，不 `free`；
- 元素为 `String` 或类引用时，入容器 `retain`，覆盖/移除/`free` 时 `release`；
- 读取成员（`get`/`first`）返回借用；调用方长期持有需自行策略；
- Map 键序为插入序；`keys()` 未纳入当前面，DET-01 不受影响。

支持的方法：

| 容器 | 语句方法 | 值方法 |
| --- | --- | --- |
| Array/List | `push`、`set`、`remove`、`clear` | `length`、`get`、`has` |
| Set | `add` | `length`、`has`、`add`（值上下文） |
| Map | `put`、`remove`、`clear` | `length`、`has`、`getOr` |

显式未支持：`List.insert`、Set 其他成员、Map 其他成员、嵌套数组、引用元素之外的类型。

### 4.6 类表示

生成结构：

```c
typedef struct xn_Cls_Node {
    rt_header hdr;              /* ARC/GC 分配头 */
    <field C types> ...;        /* 字段，按声明顺序 */
} xn_Cls_Node;

static const rt_type RT_TYPE_XN_Node = {
    .name = "Node",
    .payload_size = sizeof(xn_Cls_Node),
    .deinit = xn_Cls_Node_deinit,
    .scan = NULL,               /* 当前；含 GC 字段时需补 scan */
};
```

构造：

- 分配 `xn_Cls_<Name> *`，初始化 `hdr`；
- 字段初值按声明顺序执行；
- 支持 B0-04 的字段初值形态；自引用初值显式拒绝；
- 无参构造；带参构造显式拒绝。

方法：

- `xn_Cls_<Name>_<method>`；
- 参数按 `xn_p_<name>`；
- `self` 映射为接收者指针；
- 私有字段使用规范名 `_name`；
- 编译器生成字段清理函数；用户声明的 `deinit` 方法体当前不生成，完整 ARC 对象生命周期子集仍在推进。

当前类生成边界：

- 单类、无继承、无协议；
- 字段类型限已支持类型（含容器/类引用）；
- 方法重名视为重载未支持，显式报错；
- 类引用赋值/返回有专门 retain/release 纪律；
- `for-in` 源支持容器局部变量/字段链；
- 用户声明的 `deinit` 方法当前不生成方法体；类型描述符的 `deinit` 只做字段释放；
- 类型描述符的 `scan` 当前为 `NULL`；含 GC 引用字段的类尚未生成扫描钩子，需显式拒绝或补 scan（见 O-05）。

### 4.7 表达式生成

#### 4.7.1 临时变量提升

原则：有副作用或需要语句位次的子表达式提升为临时：

- 字符串拼接、插值、容器字面量、闭包、`new`、`try`、返回引用类型的调用、短路分支中的调用；
- 标量临时：`int64_t xn_t<N> = ...;`
- 引用临时：`rt_string *xn_t<N> = ...;`
- 求值顺序严格左→右。

#### 4.7.2 字符串

- 字面量：`rt_string_from_c("...")`；
- `+`：`xn_concat(a, b)`，接管两侧所有权；
- 标识符：`rt_retain(name)` 生成 owned 副本（供 concat 消费）；
- 类字段：`rt_retain(obj->field)`；
- 下标/容器 get：借用，不 retain；
- `str(x)`：当前仅 `xn_str_int`（Int）；Bool/其他类型未覆盖；
- String 成员：`length`、`indexOf`、`startsWith`、`endsWith`、`substring`、`trim`、`toUpper`、`toLower`；
- 字符串相等：`xn_str_eq`。

**已知缺口**：`plainText` 只拼接 `StrLitExpr.Parts` 的静态文本；含表达式段的插值串在 codegen 当前没有生成表达式求值。该形态不在已验收子集内，按“显式失败”原则应补齐检查或生成；列入第 13 节开放问题。

#### 4.7.3 标量/布尔/比较

- `intExpr` 支持字面量、局部/参数、二元算术/位运算/比较、`str` 之外的调用、成员、下标、`new`（类）、一元 `-`/`+`/`~`/`!`；
- `boolExpr` 支持 Bool 字面量、逻辑/比较；
- `cond` 生成 C 条件；条件产生前置语句时降级 `while(1){...}` 形态；
- `&&`/`||` 直映射 C 短路；
- `??` 对可选值展开（当前可选面未完整接入）。

#### 4.7.4 调用/成员/下标

- 顶层函数调用：`xn_<name>(args)`；
- 类方法调用：`xn_Cls_X_method(recv, args)`；
- 类字段访问：`recv->field`（私有字段 `_name`）；
- 容器成员：按 `containerMemberValue` / `containerMemberStmt` 分派；
- String 成员：按 `strMemberValue` 分派；
- 下标读：数组/Map 生成对应 `*_get`；越界走 `xn_fatal_oob`（exit 134）；
- 下标写：数组/Map 生成对应 `*_set`/`*_put`。

#### 4.7.5 `new` / 数组字面量 / Map 字面量

- `new C()`：分配 + 初始化 + 构造；
- 数组字面量：创建 `xn_arr_<mangle>`，逐个 push；
- Map 字面量：创建 `xn_map_<k>_<v>`，逐个 put；
- 未支持形态：显式错误。

### 4.8 语句生成

`emitStmtInner` 当前支持：

| 语句 | 生成形态 | 备注 |
| --- | --- | --- |
| `ExprStmt` | 表达式语句 | `print`/`str` 特殊处理 |
| `LocalDeclStmt` | 声明 + 初始化 | 支持局部 `Result` |
| `AssignStmt` | `=` | 复合赋值显式未支持 |
| `ReturnStmt` | 清理 + return | String/类/Result/标量分支 |
| `IfStmt` | `if/else` | 条件有前置语句时处理 |
| `WhileStmt` | `while` 或 `while(1)` 降级 | 条件重算 |
| `ForStmt` | 容器索引循环 | 区间 for-in 未接入 codegen |
| `DeferStmt` | 注册清理项，不立即生成 | LIFO |
| `ThrowStmt` | `xn_throw`（exit 134） | 不展开 defer |
| `BreakStmt` / `ContinueStmt` | `break;` / `continue;` | |

当前**未生成**的语句（会落入默认错误）：

- `DoWhileStmt`
- `SwitchStmt`
- `IncDecStmt`
- `GotoStmt` / `LabeledStmt`
- `EmptyStmt`

这些与解释器支持面不一致，是后续补齐项；codegen 不会静默降级。

### 4.9 `defer` / `errdefer` / `try`

#### 4.9.1 defer 静态展开

`scope.defers` 保存本块注册的清理项；`emitCleanup` 逆序生成：

- 普通 `defer`：无条件执行；
- `errdefer`：仅当 `hasResult && condErr` 时生成 `if (!xn_ret.ok) { ... }`；
- 普通块退出：`condErr=false`，errdefer 不触发；
- `return`/`try` 传播：`condErr=true`，errdefer 按 `xn_ret.ok` 判定。

`return` 分支：

- String/类引用返回：先 `retain` 返回值，再执行清理（清理会 release 本层引用），最后 return；
- Result 返回：写入 `xn_ret`，执行清理，return `xn_ret`；
- 标量返回：执行清理，return 表达式。

#### 4.9.2 try 展开

`emitTryInto`：

```c
xn_Result_Int_String xn_tN = xn_callee(args);
if (!xn_tN.ok) {
    xn_ret = xn_tN;
    /* 本层 defer 逆序 + errdefer 条件执行 */
    return xn_ret;
}
/* 成功：读取 xn_tN.v */
```

#### 4.9.3 throw fatal

`xn_throw(msg)`：

```c
fprintf(stderr, "fatal: %.*s\n", (int)msg->len, msg->bytes);
exit(134);
```

不执行 defer/errdefer，符合 S1 §10.4。

### 4.10 所有权与 ARC 插入

当前 codegen 的所有权规则是**子集实现**，不是完整的 §3.3 八条：

| 场景 | 当前做法 |
| --- | --- |
| 字符串字面量 | 新串，计数 1 |
| 字符串 `+` | `xn_concat` 接管两侧所有权 |
| 字符串标识符作为消费值 | `rt_retain` 后交给 concat |
| 字符串字段读取 | `rt_retain` |
| 字符串返回 | 标识符返回前 `retain`，清理抵消 |
| String 局部赋值 | 新串接管，旧串 release |
| 类引用赋值 | 新值求值 → release 旧值 → 赋值；标识符右值先 retain |
| 类引用返回 | 标识符 retain 后返回；`new` 产物直接移交 |
| 容器元素（String/类引用） | 入容器 retain；覆盖/移除/free 时 release |
| 容器局部 | 作用域退出 free |
| 函数参数 | 借用，不 free |
| `deinit` | 生成字段清理；完整对象生命周期仍在推进 |

尚未统一的部分：

- §3.3 的“传参 retain / 返回 retain 移交”在字符串上采用 move/消耗语义，与规约条文有差异（runtime-contract C 段已记录）；
- CSE/冗余 retain-release 优化未做；
- GC 对象的 scan 钩子与全局根登记在 codegen 中尚未完整生成；
- 对象级逃逸分类 `escape` 仍为 `"n/a"`（类型级），对象级回填未完成。

### 4.11 FFI 接入

`codegen` 与 `ffi` 的边界：

```go
// ffi 包对外接口
func Load(root string) (*Registry, []Diagnostic, error)
func (r *Registry) EmitCall(entry string, args []ArgExpr, dst TempName) (Snippet, error)
func (r *Registry) EmitSupport() Snippet
func LinkArgs(libs []LinkLib) []string
```

当前 codegen 的 FFI 接入状态：

- `.xfb` 注册表可加载、校验、生成包装；
- `EmitSupport` 生成布局、canary、错误分类、包装函数；
- codegen 调用点注入 `xn_ffi_<entry>` 属 P-09，按 B0 推进；
- `xnull build` 的 C 清单已纳入 `xrt_abi.c`、`rt_std_*.c`（P-10）；
- `LinkArgs` 去重 + 升序，排在全部目标文件之后。

### 4.12 构建

`BuildWithOptions`：

```go
func BuildWithOptions(srcPath, outPath, runtimeDir string, opts Options, stderr io.Writer) int
```

流程：

1. `LoadUnits(srcPath)`；
2. `sema.Analyze`；
3. `EmitC`；
4. 写 `<outPath>.c`；
5. `cc` 参数：

```
-std=c11 -O2 -I <runtimeDir> -o <outPath> <outPath>.c
<runtimeDir>/rt.c
<runtimeDir>/rt_gc.c
<runtimeDir>/rt_policy.c
<runtimeDir>/rt_weak.c
<runtimeDir>/xrt_abi.c
<runtimeDir>/rt_std_runtime.c
<runtimeDir>/rt_std_text.c
<runtimeDir>/rt_std_sys.c
<LinkArgs...>
```

固定顺序由 `runtimeCSources` 保证；`LinkArgs` 由调用方生成，构建侧不再排序。

### 4.13 代码生成支持矩阵

| 语言面 | 解释器 | 代码生成 | 说明 |
| --- | --- | --- | --- |
| 标量 Int/Bool | 支持 | 支持 | |
| String | 支持 | 支持 | 成员子集 |
| Float/Char | 部分 | 显式拒绝 | |
| Result/try/defer/errdefer | 支持 | 支持 | Result 仅 Int/Bool + String |
| if/while/for-in | 支持 | 支持 | for-in 仅容器 |
| do-while/switch | 支持 | 显式拒绝 | |
| break/continue | 支持 | 支持 | |
| goto/label | 支持 | 显式拒绝 | |
| 类 | 支持（Go GC） | 单类子集 | 无继承/协议/带参构造 |
| 容器 | 支持 | 子集 | Int/Bool/String/类引用 |
| 元组 | 支持 | 显式拒绝 | |
| 闭包 | 支持 | 显式拒绝 | |
| 插值串 | 支持 | 静态段可用；表达式段缺口 | 见 §13 |
| `is`/`as` | 支持 | 显式拒绝 | |
| 泛型 | 部分 | 显式拒绝 | |

---

## 5. C 运行时 `impl/runtime`

### 5.1 文件与职责

| 文件 | 职责 |
| --- | --- |
| `rt.h` / `rt.c` | 分配头、ARC、字符串、fatal、隔离区 |
| `rt_gc.h` / `rt_gc.c` | 标记—清扫、根、ARC 扫描链、不变量 |
| `rt_policy.h` / `rt_policy.c` | 策略判定表执行器 |
| `rt_weak.c` | 弱引用表 |
| `xrt.h` / `xrt_abi.c` | 稳定 ABI 薄封装、句柄、Bytes |
| `rt_std_runtime.c` | diagnose/exit/nowMono/nowWall/env 快照 |
| `rt_std_text.c` | parseInt/parseFloat/Format/UTF 转换/Regex 子集 |
| `rt_std_sys.c` | 文件/目录/存在性/子进程 |
| `test_rt.c` / `test_gc.c` / `test_hard.c` / `test_abi.c` / `test_std.c` / `test_res.c` | C 套件 |
| `build_rt.sh` | 构建与运行全部 C 套件 |

### 5.2 分配头

```c
typedef struct rt_header {
    rt_kind             kind;       /* ARC / GC */
    const rt_type      *type;       /* 类型描述符 */
    atomic_int_fast64_t refcount;   /* 原子计数 */
    int                 terminated; /* 终结标志 */
    int                 marked;     /* GC 标记 */
    struct rt_object   *gc_next;    /* GC 对象链 / 隔离区链复用 */
    struct rt_object   *scan_next;  /* ARC 扫描链 */
    int                 in_scan_list;
    struct rt_weak_slot *weak_head;
} rt_header;
```

对象 = `rt_header` + 载荷；载荷按 8 字节对齐。

`rt_type`：

```c
typedef struct rt_type {
    const char *name;
    size_t      payload_size;
    void      (*deinit)(void *payload);
    void      (*scan)(void *payload, void (*visit)(void *ref));
} rt_type;
```

### 5.3 ARC 生命周期

`rt_retain`：

- `NULL` 原样返回；
- 已终结对象 → `rt_fatal("复活检测…")`；
- 原子 +1。

`rt_release`：

- `NULL` 直接返回；
- 已终结对象直接返回（防双释放）；
- 原子 -1；到 0：
  1. `terminated = 1`；
  2. `rt_weak_clear_slots`；
  3. `rt_scan_unregister`；
  4. `type->deinit`；
  5. `rt_quarantine_push`。

`rt_quarantine_flush`：释放隔离区，返回释放数；`main` 返回前调用。

### 5.4 GC 与混合图

`rt_gc_new`：分配 GC 对象，加入全 GC 对象链，计数 1，要求 `type->scan != NULL`。

`rt_arc_new`：分配 ARC 对象；若 `type->scan != NULL`，登记扫描链（不变量 2）。

根：

- `rt_gc_root_add/remove`：全局根（静态/顶层字段、单例、数据枚举项）；
- ARC 扫描链：持有 GC 引用的 ARC 对象；
- 栈槽位根在 codegen 接入前由全局根 API 覆盖（设计目标）。

回收：

```
mark：根 + ARC 扫描链可达 → marked
sweep：遍历全 GC 对象链；未标记者：
        - 对其 scan 到的 ARC 引用 release
        - 释放 GC 对象
```

不变量 1/2/3/5/6 已落地并有 `test_gc.c` 覆盖；不变量 4（弱引用）由 `rt_weak.c`/`test_hard.c` 覆盖。

### 5.5 弱引用

- `rt_weak_create(target)`：建立弱槽位，不持强引用；
- `rt_weak_get(slot)`：目标终结后返回 `NULL`；
- `rt_weak_destroy(slot)`：摘除/复用；
- `rt_weak_clear_slots(target)`：终结链第 1 步清除全部弱槽位。

### 5.6 策略判定执行器

`rt_policy_input`：

```c
typedef struct {
    rt_type_kind kind;
    int has_deinit;
    int self_captured;
    int ref_cycle;
    int gc_field;
    int has_ref_field;
} rt_policy_input;
```

`rt_decide_policy` 按行序执行，命中即返回；`rt_policy_rule_name` 提供行名。

### 5.7 稳定 ABI `xrt.h`

| 组 | 函数/类型 | 说明 |
| --- | --- | --- |
| 分配/计数 | `xrt_alloc`、`xrt_retain`、`xrt_release`、`xrt_refcount` | 只经此管理内存 |
| 弱表 | `xrt_weak_bind`、`xrt_weak_read`、`xrt_weak_clear` | 只对合同层开放 |
| 屏障/根/安全点 | `xrt_write_barrier`、`xrt_register_root`、`xrt_unregister_root`、`xrt_safepoint` | 单线程骨架期 |
| 任务根 | `xrt_task_root_bind/unbind` | trampoline env 预留 |
| 初始化 | `xrt_runtime_init` | 幂等；未初始化不得建对象 |
| 字符串 | `xrt_string_new/from_c/alloc/len/bytes`、`xrt_type_string_descriptor` | `len` 权威，NUL 便利 |
| Bytes | `xrt_bytes { data, len }` | 边界缓冲区 |
| 句柄 | `xrt_handle_new/native/close/mark_closed/is_closed` | close 幂等；deinit 不自动 close |
| fatal | `xrt_fatal` | 跨界违约终止 |

### 5.8 标准原语

| 文件 | 能力 | 状态 |
| --- | --- | --- |
| `rt_std_runtime.c` | diagnose、exit、nowMono、nowWall、env 快照 | 完成 |
| `rt_std_text.c` | parseInt/parseFloat、Format 追加、UTF-8↔UTF-16、Regex ERE 子集 | 完成（C 层） |
| `rt_std_sys.c` | 文件打开/读/写/关闭、目录、存在性、子进程状态 | 完成（POSIX） |
| `rt_std_sync.c` / `rt_std_net.c` | 同步原语 / Socket | 未开工（依赖调度器切片） |
| 资源表 | `dev res` 生成只读 C 表 | 完成 |

### 5.9 运行时构建

`build_rt.sh`：

```
test_rt   : test_rt.c rt.c rt_policy.c rt_gc.c rt_weak.c
test_gc   : test_gc.c rt.c rt_gc.c rt_weak.c
test_hard : test_hard.c rt.c rt_gc.c rt_weak.c
test_abi  : test_abi.c rt.c rt_gc.c rt_weak.c xrt_abi.c
test_std  : test_std.c rt.c rt_gc.c rt_weak.c xrt_abi.c rt_std_runtime.c rt_std_text.c rt_std_sys.c
test_res  : 生成资源表 + test_res.c
```

基线：`-std=c11 -Wall -Wextra -Werror -O2`。

---

## 6. FFI 子系统 `internal/codegen/ffi`

### 6.1 边界模型

只允许三形态跨界：

| 形态 | 表示 | 方向 |
| --- | --- | --- |
| 值 | 标量、`layout(c)` 结构 | 双向 |
| 句柄 | `xrt_handle*`（不透明） | 双向 |
| 缓冲区 | `String`（借出）、`Bytes`、标量/布局数组 | 借出/移交/归还按租约 |

禁止：`Result`、可选、引用对象、闭包、容器、元组、`String` 移交、`rt_object*` 地址。

### 6.2 `.xfb` 方言

示例：

```
ffi sqlite {
  layout(c) struct Stat {
    Int64 size
    Int32 mode
  }

  @ffiEntry(cName = "sqlite3_open")
  @lease(path = .borrow, db = .transfer)
  @errorCode(codeParam = .result)
  @blocking(.unaware)
  Int ffiSqliteOpen(Bytes path, Handle db);

  @ffiEntry(cName = "sqlite3_close")
  @lease(db = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.aware)
  Int ffiSqliteClose(Handle db);
}
```

语义规则：

1. 每个入口必须有 `@ffiEntry(cName=…)`、逐参数 `@lease(...)`、`@blocking(...)`；
2. `@errorCode` 可选；无错误码入口可返回 void/标量；
3. `.transfer` 必须有同库 `.reclaim` 入口或 `neverReclaim = "理由"`；
4. `Handle` 必须经 `handle` 块声明 `close`；
5. `@unsafe` 必须有 `contract = "..."`，且文件位于 `bindings/`；
6. `layout(c)` 字段限标量或嵌套 `layout(c)`；递归/重名/空结构拒绝；
7. 入口不得出现 `Result`/可选/引用/闭包/容器/元组/`String` 移交；
8. 诊断按声明序；注册表按名称排序。

### 6.3 校验器

`ffi.Load(root)`：

1. 递归查找 `.xfb`（按路径字典序）；
2. 词法/语法解析；
3. 收集入口/布局/句柄/错误映射；
4. 逐项合同校验；
5. 跨文件重名检测；
6. 产出 `Registry` 与全部诊断。

诊断码：

| 码 | 语义 |
| --- | --- |
| `FFI-100` | 声明语法错误 |
| `FFI-101` | 入口合同缺失/不完整 |
| `FFI-102` | `.transfer` 缺对称 `.reclaim` |
| `FFI-103` | `String`/`Text` 移交/归还 |
| `FFI-104` | 嵌套数组/元素非法 |
| `FFI-105` | 类型不跨界 |
| `FFI-106` | 错误码声明非法 |
| `FFI-107` | 阻塞分类缺失/非法/长阻塞缺伴生入口 |
| `FFI-108` | 裸指针/指针长度合同违规 |
| `FFI-109` | `layout(c)` 违规 |
| `FFI-110` | `@unsafe` 缺合同文本/位置违规 |
| `FFI-111` | 重复声明（入口/结构/句柄） |

### 6.4 注册表模型

`Registry`：

```go
type Registry struct {
    Entries []Entry
    Layouts []Layout
    Handles []Handle
}

type Entry struct {
    Name         string
    CName        string
    Region       string
    Ret          BoundType
    Params       []Param
    Lease        []LeaseKind
    ErrorCode    string
    ErrorCodeRet bool
    ErrorMap     []ErrRule
    Blocking     Blocking
    LongRunning  bool
    Unsafe       bool
    ContractText string
    CloseOf      string
}
```

`BoundKind`：`Void/Scalar/String/Text/Bytes/Array/Layout/Handle`。

`sortAll` 按名称排序；`sortDiags` 按文件/行/列/码排序。

### 6.5 包装 ABI

```c
static int32_t xn_ffi_<entry>(<入参...>[, <retC> *xn_out]);
```

- 返回 0 = 成功；非 0 = 原生错误码；
- 分类经 `xn_ffi_<region>_error_kind(code)`；未知码 → `Internal`；
- 生成代码只 include `xrt.h`；
- 原生符号声明可用 `XN_FFI_NATIVE_DECLS` 关闭。

编组：

| 类型 | 入参 | 返回 |
| --- | --- | --- |
| 标量 | 对应 C 类型 | 出参 + 错误码 |
| `String` | `const char *bytes, size_t len` | `xrt_string*` 出参，复制接管 |
| `Bytes` | `void *data, size_t len` + canary | 不支持（当前） |
| 数组 | `T *items, size_t n` | 不支持（当前） |
| `layout(c)` | `xn_layout_<Name> *` | 不支持（当前） |
| `Handle` 借入 | `xrt_handle *`，取原生指针 | 出参 |
| `Handle` 移交 | `xrt_handle **out` | 包装 `xrt_handle_new` |
| `Handle` 归还 | `xrt_handle *`，调用即登记关闭 | — |

### 6.6 句柄、canary、trampoline

句柄：

- `xrt_handle` 是普通 ARC 对象，载荷 `void* native` + `close_fn` + `closed`；
- `close` 幂等；重复关闭返回成功，不再调用原生 `close_fn`；
- 已关闭句柄再取原生指针返回 `NULL`；
- deinit 不自动 close，只诊断泄漏。

canary：

- `Bytes` 借出时分配 `n + 2*16` 缓冲，前后填充 `0xA5`/`0x5A`；
- 调用返回后校验；越界即 `xrt_fatal`；
- 只在借出 `Bytes`/数组时插入，标量/String 不插。

trampoline：

- `EmitTrampoline` 当前返回 `ErrTrampolineReserved`；
- 依赖调度器栈 pin/根登记与 P-09 后续钩子；
- 不做“半成品回调”。

### 6.7 链接

`LinkArgs`：

- 只接受清单声明的库；
- 去重 + 升序；
- 生成 `-l<name>`；
- 由构建侧保证排在全部目标文件之后；
- `-L` 由 CLI 收集、排序、放在 `-l` 前。

`xnull build` 当前支持 `-l`/`-L`；`link.libraries` 清单接入属工程层批次。

### 6.8 FFI 当前边界

| 能力 | 状态 |
| --- | --- |
| `.xfb` 解析/校验/注册表 | 完成 |
| 标量/String/Bytes/数组/布局/句柄编组 | 完成（部分形态显式 `Problems`） |
| 错误码归一 | 完成 |
| 句柄 close 幂等/移交/归还 | 完成 |
| canary | 完成 |
| trampoline | 接口预留 |
| codegen 调用点注入 | B0/P-09 推进 |
| 跨任务句柄并发规则 | 随调度器切片 |

---

## 7. XDK 三层结构

### 7.1 分层

```
impl/lib/xdk/<layer>/<domain>/*.x
                          XNull 源码层：公开 API（类型/函数/合同文档）
        │  import xdk.*
        ▼
bindings/xdk/*.xfb        绑定声明：三形态/租约/错误码/阻塞分类
        ▼
impl/runtime/rt_std_*.c   C 原语层：OS/内核服务（xdkc_* 内部符号）
        ▼
impl/runtime/xrt*.c       稳定 ABI（分配/计数/根/弱表/句柄）
```

> 物理目录按“分层/域”两级组织（`build`、`compiler`、`core`、`text`、`data`、
> `io`、`net`、`concurrent`、`util`），包名保持 `xdk.errors`、`xdk.text` 等冻结名称；
> 解析器用 `tests/b4/package_resolver.py` 的 `XDK_LAYOUT` 做映射。

理由：

1. 合同一次校验：所有 OS 接触面进 `.xfb`，复用 FFI 校验器；
2. API 用 XNull 写：`Result`、`Context`、`withLock` 等约束只有类型系统能表达；
3. 自举铺垫：`impl/lib/xdk/` 是编译器重写的第一块真实 XNull 代码；
4. 解释器一致：同一份 `.x` 在 `--interp` 下也执行。

### 7.2 包与依赖

| 包 | 内容 | 依赖 |
| --- | --- | --- |
| `xdk.errors` | `Error` 协议、`ErrorKind` 14 项、`wrap`/`mapErr`/`report` | — |
| `xdk.runtime` | `diagnose`/`exit`/`nowMono`/`nowWall`/`env` | errors |
| `xdk.text` | `Format`、编码转换、`parseInt`/`parseFloat`、`Regex` | errors/runtime |
| `xdk.collections` | `sort`/`groupBy`/`dedup`/`find`、`RingBuffer`/`PriorityQueue`/`OrderedMap`/`BTreeMap` | errors/text |
| `xdk.sys` | `File`/`Dir`/`Process`、资源读取五 API | errors/runtime |
| `xdk.tasks` | `Task`/`TaskGroup`/`Context` | errors/runtime |
| `xdk.sync` | `Mutex`/`Channel`/`Atomic*` | errors/runtime |
| `xdk.net` | Socket/listener | errors/runtime |

依赖方向单向：`sys → errors → runtime → text → collections`；`tasks/sync` 只依赖 `errors/runtime`；`net` 独立。

### 7.3 C 原语

| 文件 | 内容 |
| --- | --- |
| `rt_std_runtime.c` | `xdkc_diagnose`、`xdkc_exit`、`xdkc_now_mono_ms`、`xdkc_now_wall_ms`、`xdkc_env_get` |
| `rt_std_text.c` | `xdkc_parse_int`、`xdkc_parse_float`、`xdkc_format_int`、`xdkc_fmt_append_*`、`xdkc_regex_match`、UTF 转换 |
| `rt_std_sys.c` | `xdkc_file_*`、`xdkc_dir_*`、`xdkc_path_exists`、`xdkc_proc_status` |
| `rt_std_sync.c` / `rt_std_net.c` | 未开工 |

### 7.4 资源读取

- 资源根：`src/main/resources`；测试根 `src/test/resources`；
- 制品内前缀 `resources/`；
- 路径分隔符 `/`；绝对路径、空段、`..`、反斜杠 → `InvalidArgument`；
- 只读、无句柄、不回退文件系统；
- 缺失 → `NotFound`；
- `listResources` 字典序；
- 资源表由 `xnull dev res` 生成：递归、按名升序、空目录零条目、符号链接按目标读取、断链/越界失败。

### 7.5 XDK 当前状态

| 项 | 状态 |
| --- | --- |
| C 层 runtime/text/sys | 完成（POSIX） |
| 绑定 `bindings/xdk/runtime.xfb`、`sys.xfb` | 完成 |
| XNull 源码层 | 种子（`text.x`） |
| 完整 8 包 API | 未齐；依赖 P-09 外部调用钩子与类/枚举面 |
| tasks/sync/net | 未开工（依赖调度器） |

---

## 8. 工程配置 `internal/xpd`

### 8.1 词法

| 记号 | 规则 |
| --- | --- |
| 空白 | 空格/制表符；换行是语句终止符 |
| 注释 | `#` 到行尾 |
| 标点 | `{ } = [ ] ( ) ,` |
| 标识符 | `[A-Za-z][A-Za-z0-9-]*` |
| 键名 | 小写字母/数字/点/连字符，不以点开头或结尾；只允许出现在 `configuration` 段 |
| 裸词 | `[A-Za-z0-9._:/\\*?\-]` 与 `${…}` |
| 字符串 | `"`…`"`，仅 `\"`/`\\` 转义 |
| 变量 | `${标识符}`，可出现在裸词/字符串内 |

### 8.2 AST

```go
type File struct { Path string; Items []Node }
type Field struct { Name string; Value Value; Pos Pos }
type Block struct { Name string; Args []Value; Children []Node; Pos Pos; Leaf bool }
type Value struct { Kind ValueKind; Text string; Elems []Value; LoIncl, HiIncl bool; Pos Pos }
```

`ValueKind`：`StringValue`、`BareValue`、`ListValue`、`RangeValue`。

### 8.3 文法

```text
文件    = { 换行 | 条目 } ;
条目    = 字段 | 条目块 ;
字段    = 名称 "=" 值 ;
条目块  = 名称 { 参数 } [ "{" { 换行 | 条目 } "}" ] ;
参数    = 值 ;
名称    = 标识符 | 键名 ;
值      = 字符串 | 裸词 | 列表 | 范围 ;
列表    = "[" [ 值 { "," 值 } ] "]" ;
范围    = ( "[" | "(" ) 值 "," 值 ( "]" | ")" ) ;
```

### 8.4 语义约束

- 根层只允许一个 `project`/`lock`/`plugin`/`settings`；
- 段落嵌套与字段合法组合由 S8 表规定；
- 不可重复段落重复 → 错误；
- 键名只允许出现在 `configuration`；
- 块体可省略的条目按 S8 表；
- 值一律字符串；列表字段必须给列表；
- 范围只用于 `language-version`；
- 列表/范围不得跨行；字段/条目未以换行或 `}` 收尾 → 错误；
- 错误报告行、列、段落路径。

### 8.5 工程模型

| 部分 | 内容 | 当前实现 |
| --- | --- | --- |
| GAV | `groupId`/`artifactId`/`version`/`packaging` 每模块必写 | 解析器就绪；校验未接入 |
| parent/modules | 单父、聚合 | 未接入 |
| properties | 变量替换 | 未接入 |
| dependencyManagement/dependencies | 版本仲裁、scope、exclusions | 未接入 |
| repositories/lock | 默认仓库、锁文件 | 未接入 |
| build | mode/warnings/entry/resources/plugins | 未接入 |
| link | libraries/unsafe | 部分（CLI `-l/-L`） |
| profiles | 条件覆盖 | 未接入 |
| configuration | 服务配置五层覆盖 | 未接入 |
| 资源 | `src/main/resources`、glob、打包 | `dev res` 完成；构建接入未完成 |

### 8.6 XPD 诊断

| 段位 | 类别 |
| --- | --- |
| `XPD-0xx` | 词法 |
| `XPD-1xx` | 文法/结构 |
| `XPD-2xx` | 段落/字段语义 |
| `XPD-3xx` | 坐标/继承 |
| `XPD-4xx` | 依赖/锁 |
| `XPD-5xx` | 插件 |
| `XPD-6xx` | 配置 |
| `XPD-7xx` | 元数据 |
| `XPD-8xx` | 资源/打包 |

### 8.7 XPD 当前边界

`internal/xpd` 只做词法/文法/AST；不执行继承展开、变量替换、依赖解析、锁校验、生命周期、插件、资源打包。CLI 对工程模式多数命令返回“尚未实现”。

---

## 9. CLI、解释器与维护工具

### 9.1 CLI 分派

`internal/cli/cli.go`：

```go
func Run(env Env) int
```

- `Env` 注入 stdout/stderr/args；
- 无参数 → usage，退出 0；
- `-h/--help/help`、`-v/--version/version`；
- 未知命令 → CLI-001；未知长旗标 → CLI-002；
- `parseFlags` 只校验长旗标形态；
- 命令表：`policy`、`build`、`run`、`test`、`fmt`、`lock`、`dev`；
- `run` 扫描 `.x` 后缀进入文件模式；
- `build` 首参 `.x` 进入文件模式；
- `policy` 首参 `.x` 进入策略输出；
- 其余工程命令若找不到 `xnull.project` → CLI-003；
- 未实现 → `notImplemented`（CLI-901，退出 2）。

### 9.2 `run` / `build` 细节

`runCompiled`：

1. 解析运行时目录：`impl/runtime`、`../impl/runtime`、`../../impl/runtime`、`../../runtime`、`runtime`；
2. 找不到则用 `XNULL_RUNTIME`；
3. 创建临时目录；
4. `codegen.Build`；
5. 启动子进程，透传 stdout/stderr；
6. 透传退出码。

`buildFile`：

- `-o` 输出名；
- `--runtime` 运行时目录；
- `-l`/`-L` 链接库/目录；
- `LinkArgs`：`-L` 去重排序在前，`ffi.LinkArgs` 去重排序在后；
- 传给 `codegen.BuildWithOptions`。

`interpFile`：

- `LoadUnits` + `sema.Analyze` + `interp.Run`；
- 与编译路径共享加载器与语义检查。

### 9.3 解释器

`internal/interp` 是 tree-walking 解释器：

- `Value` 值模型（标量/字符串/数组/映射/元组/Result/闭包/对象）；
- `scope` 词法作用域；
- `exec` 语句执行；`eval` 表达式求值；
- `defer`/`errdefer` 用 `ditem` 栈，LIFO；
- `try`/`Result` 用 `ctrlErr` 控制流；
- `throw` 用 `fatal` 控制流，不展开 defer；
- 对象用 `objv` 包装，由 Go GC 托管；不模拟 ARC 时序；
- 容器用 Go slice/map；`canonKey` 提供 Map 键规范化；
- 内建函数 `print`、`str`；`Ok`/`Err` 是语言构造器。

限制：

- 不是正式运行时；内存时序不作为验收面；
- 不支持面与 codegen 不完全一致（解释器更宽）；
- 双路径只断言 stdout/退出码，不断言内存行为。

### 9.4 维护工具

`internal/devtool`：

| 函数 | 作用 |
| --- | --- |
| `CheckSpecs(root, out)` | 规范守门：头部一致、零待定、§ 引用、二进制拦截、EN 快照 |
| `GenerateLedger(root, out)` | 从 S1—S8 抽取锚点，连接 `status.tsv` 生成台账 |
| `GenerateResources(srcDir, outPath)` | 资源根 → 只读 C 表 |

`check` 的 EN 同步判据是“文件名版本 + 母本内容 SHA-256”，不是 mtime；清单在 `impl/docs/conformance/en-source.sha256`。

`ledger` 的双布局：

- 工作区：索引在仓库根；
- 公开副本：索引在 `Root/spec`；
- `findLayout` 优先选择同时存在 `impl/` 的候选。

`res`：

- 递归收录常规文件；
- 资源名 = 相对路径，`/` 分隔；
- 按名升序；
- 空目录不产生条目；
- 符号链接按目标内容读取；断链/目录/越界失败；
- 输出 C 常量表。

---

## 10. 测试与验证

### 10.1 Go 测试分布

| 包 | 测试文件 | 重点 |
| --- | --- | --- |
| `xfront` | `lexer_test.go`、`parser_test.go`、`stmt_test.go`、`unit_test.go` | 词法矩阵、表达式、语句、编译单元 |
| `sema` | `sema_test.go`、`assign_test.go`、`ty_test.go`、`typedecl_test.go`、`policy_test.go`、`err01_test.go`、`det01_test.go`、`xdk_test.go`、`list_remove_test.go`、`type01_optional_test.go` | 名称/赋值/类型/声明/策略/清理/确定性 |
| `codegen` | `codegen_test.go`、`build_test.go`、`multifile_test.go`、`b0_04_test.go`、`xdk_seed_test.go` | 黄金 C、构建参数、多文件、字段初值、XDK 种子 |
| `codegen/ffi` | `ffi_test.go`、`emit_test.go`、`xdk_test.go`、`xdk_write_test.go` | 合同校验、包装、XDK 绑定 |
| `interp` | `interp_test.go`、`values_test.go`、`hard_test.go` | 语句/值/硬语义 |
| `cli` | `cli_test.go`、`build_test.go`、`dev_test.go` | 命令、退出码、构建 |
| `xpd` | `parser_test.go` | 文法样例 |
| `devtool` | `specs_test.go`、`ledger_test.go`、`resources_test.go` | 守门/台账/资源 |
| `diag` | `diag_test.go` | 渲染 |

### 10.2 C 测试套件

| 套件 | 覆盖 |
| --- | --- |
| `test_rt.c` | 分配头、计数、终结链、字符串、策略表 |
| `test_gc.c` | 环回收、根、ARC 持 GC、清扫 release、双路可达 |
| `test_hard.c` | 弱引用、复活检测、硬语义 |
| `test_abi.c` | `xrt_*` 迁移、句柄、弱表、根 |
| `test_std.c` | runtime/text/sys 原语 |
| `test_res.c` | 资源表生成与查询 |

### 10.3 确定性测试

- `interp.TestDeterminismByteIdentical`：同一程序多次运行逐字节一致；
- `sema` 策略输出按声明名排序；
- `codegen` 容器/Result 实例化排序；
- `ffi` 注册表/诊断排序；
- `devtool` 资源表升序；
- 构建产物 C 文本可用 `cmp` 做逐字节对照。

### 10.4 双路径对照

- 编译路径 vs `--interp`：stdout/退出码逐字节一致；
- 示例集：`hello.x`、`result-try.x`、`defer-cleanup.x`、`classes.x`、`containers.x`、`multi/main.x`、`lexer-seed.x`、`parser-seed.x`、`ast-seed.x`、`objlist.x`；
- 当前台账中 ENTRY-01/TUPLE-01 等仍有“部分”，以 status.tsv 为准。

### 10.5 CI

`ci/run.sh` 10 项：

| 步骤 | 内容 | 状态 |
| --- | --- | --- |
| 01 | gofmt + vet | 真实现 |
| 02 | go test | 真实现 |
| 03 | C 运行时构建 | 真实现 |
| 04 | 示例双路径 | SKIP |
| 05 | check_specs 守门（六检标签） | SKIP |
| 06 | 台账再生成 diff | SKIP |
| 07 | 泄漏扫描 | SKIP |
| 08 | 产物与 sha | SKIP |
| 09 | 汇总 JSON | SKIP |
| 10 | 文件名扫描 | 真实现 |

SKIP 不等于 PASS；CI 输出 `steps.jsonl` 记录每步状态与日志。

### 10.6 一致性台账

- 台账 = 规范锚点（S1—S8） × 实现证据；
- `status.tsv` = 有证据子集；
- 未登记 = 未实现；
- `ledger-restructure.md` 记录 101 锚点 → 30 行证据旁表的映射；
- 状态变更必须有测试文件或明确归属。

### 10.7 当前测试缺口

| 缺口 | 影响 |
| --- | --- |
| codegen 插值串表达式段 | 可能丢失表达式；需补显式检查/生成 |
| codegen do-while/switch/incdec/goto | 与解释器支持面不一致 |
| 类继承/协议/带参构造 | 未覆盖 |
| 元组/闭包/可选 | 未覆盖 |
| 工程生命周期/锁/插件/资源打包 | 未接入 |
| CI 04—09 | 未实装 |
| 并发/调度器 | 未开工 |
| FFI trampoline | 预留 |
| Windows 运行时 | POSIX 优先 |

---

## 11. 构建与部署细节

### 11.1 构建命令

```bash
cd impl
go build -o xnull ./cmd/xnull
./xnull run ../examples/hello.x
./xnull build ../examples/hello.x -o /tmp/hello
/tmp/hello
```

### 11.2 运行时目录解析

`runCompiled` / `buildFile` 顺序：

1. 显式 `--runtime`（build）；
2. `XNULL_RUNTIME`；
3. 相对探测：`impl/runtime`、`../impl/runtime`、`../../impl/runtime`、`../../runtime`、`runtime`。

### 11.3 C 编译清单

固定顺序：

```
rt.c
rt_gc.c
rt_policy.c
rt_weak.c
xrt_abi.c
rt_std_runtime.c
rt_std_text.c
rt_std_sys.c
```

旗标：`-std=c11 -O2 -I <runtime> -o <out>`。

### 11.4 平台

| 平台 | 工具链 | 运行时 |
| --- | --- | --- |
| macOS | Go 交叉/本机构建 | POSIX 原语，clang 17 基线 |
| Linux | Go 交叉/本机构建 | POSIX 原语 |
| Windows | Go 可交叉编译 | `rt_std_sys.c` 需实现分支；当前未完成 |

### 11.5 产物与目录

| 产物 | 位置 |
| --- | --- |
| 工具链 | `impl/xnull` |
| 生成 C | `<out>.c` |
| 可执行文件 | `<out>` |
| 运行时测试 | `/tmp/xnull_test_*` |
| 资源表 | 调用方指定 |
| 工程产物 | `target/`（设计目标；当前未接入） |

### 11.6 发布前检查

```bash
cd impl
gofmt -l .
go vet ./...
go test ./... -count=1
sh runtime/build_rt.sh
cd ..
./impl/xnull dev check .
```

公开前额外检查：EN 快照、内部治理词汇、任务编号、二进制文档拦截。

---

## 12. 接口参考

### 12.1 Go 公开接口

#### `xfront`

```go
func Lex(file, src string) ([]Token, []diag.Diagnostic)
func ParseExpr(file, src string) (Expr, []diag.Diagnostic)
func ParseStmts(file, src string) ([]Stmt, []diag.Diagnostic)
func ParseUnit(file, src string) (*CompilationUnit, []diag.Diagnostic)
func PrintExpr(e Expr) string
func PrintStmt(s Stmt) string
func PrintUnit(u *CompilationUnit) string
func PrintType(t TypeRef) string
```

#### `sema`

```go
func Analyze(file string, u *xfront.CompilationUnit) []diag.Diagnostic
func AnalyzeWith(file string, u *xfront.CompilationUnit) (*Result, []diag.Diagnostic)
func (r *Result) Strategies(u *xfront.CompilationUnit) []Strategy
```

#### `codegen`

```go
func EmitC(u *xfront.CompilationUnit) (string, error)
func LoadUnits(entryPath string) (*xfront.CompilationUnit, []diag.Diagnostic)
func Build(srcPath, outPath, runtimeDir string, stderr io.Writer) int
func BuildWithOptions(srcPath, outPath, runtimeDir string, opts Options, stderr io.Writer) int
```

#### `ffi`

```go
func Load(root string) (*Registry, []Diagnostic, error)
func (r *Registry) EmitCall(entry string, args []ArgExpr, dst TempName) (Snippet, error)
func (r *Registry) EmitSupport() Snippet
func (r *Registry) EmitTrampoline(entry string) (Snippet, error)
func LinkArgs(libs []LinkLib) []string
func DeclareDiagnostics() []DiagSpec
```

#### `interp`

```go
func Run(u *xfront.CompilationUnit, out io.Writer, progArgs []string) (code int, err error)
```

#### `xpd`

```go
func Parse(file, src string) (*File, []diag.Diagnostic)
```

#### `devtool`

```go
func CheckSpecs(start string, out io.Writer) (int, error)
func GenerateLedger(start string, out io.Writer) error
func GenerateResources(srcDir, outPath string) error
```

### 12.2 C 接口

#### 内部 `rt.h`

| 函数 | 作用 |
| --- | --- |
| `rt_retain` / `rt_release` / `rt_refcount` | 计数 |
| `rt_payload` | 载荷指针 |
| `rt_string_new` / `rt_string_alloc` / `rt_string_from_c` | 字符串 |
| `rt_fatal` / `rt_set_fatal_handler` | 致命错误 |
| `rt_quarantine_push` / `rt_quarantine_flush` | 隔离区 |
| `rt_scan_unregister` | 扫描链注销 |
| `rt_weak_create` / `rt_weak_get` / `rt_weak_destroy` / `rt_weak_clear_slots` | 弱表 |

#### 稳定 `xrt.h`

| 函数 | 作用 |
| --- | --- |
| `xrt_runtime_init` | 初始化 |
| `xrt_alloc` / `xrt_retain` / `xrt_release` / `xrt_refcount` | 分配/计数 |
| `xrt_weak_bind` / `xrt_weak_read` / `xrt_weak_clear` | 弱表 |
| `xrt_write_barrier` / `xrt_register_root` / `xrt_unregister_root` / `xrt_safepoint` | 屏障/根/安全点 |
| `xrt_task_root_bind` / `xrt_task_root_unbind` | 任务根 |
| `xrt_string_new` / `xrt_string_from_c` / `xrt_string_alloc` / `xrt_string_len` / `xrt_string_bytes` | 字符串 |
| `xrt_type_string_descriptor` | 类型描述符 |
| `xrt_handle_new` / `xrt_handle_native` / `xrt_handle_close` / `xrt_handle_mark_closed` / `xrt_handle_is_closed` | 句柄 |
| `xrt_fatal` | 跨界违约终止 |

### 12.3 诊断码汇总

| 段位 | 码 | 归属 |
| --- | --- | --- |
| 词法 | LEX-101—106 | xfront |
| 语法 | SYN-101—111 | xfront |
| 名称/导入 | RES-101—110 | sema/codegen |
| 确定赋值 | DA-101—103 | sema |
| 类型 | TY-101—105 | sema |
| 类型声明 | TY-201—207 | sema |
| 错误/清理 | ERR-201—206 | sema |
| FFI | FFI-100—111 | ffi |
| 工程 | XPD-0xx—8xx | xpd |
| CLI | CLI-001—003、CLI-901 | cli |

### 12.4 文件格式

| 文件 | 格式 | 解析器 |
| --- | --- | --- |
| `.x` | XNull 源文件 | xfront |
| `.xfb` | FFI 声明方言 | ffi |
| `xnull.project` | XPD | xpd |
| `xnull.lock` | XPD `lock` 块 | xpd（结构） |
| `application.properties` | flat properties | 运行时配置层（设计目标） |
| `status.tsv` | TSV | devtool |
| `.xmeta` | XPD | 工程层（设计目标） |

---

## 13. 追踪矩阵与自举准备度

### 13.1 规范 → 模块 → 证据

| 规范 | 主模块 | 关键接口 | 证据 |
| --- | --- | --- | --- |
| S1 词法/语法 | xfront | `Lex`/`ParseUnit` | `lexer_test.go`、`parser_test.go`、`stmt_test.go`、`unit_test.go` |
| S1 表达式/语句 | interp/codegen | `Run`/`EmitC` | `interp_test.go`、`codegen_test.go` |
| S1 类型系统 | sema | `AnalyzeWith` | `ty_test.go`、`type01_optional_test.go` |
| S1 包/导入 | sema/codegen | `analyzeImports`/`LoadUnits` | `sema_test.go`、`xdk_test.go`、`multifile_test.go` |
| S1 错误/清理 | sema/codegen/interp | `error.go`/`emitCleanup` | `err01_test.go`、`hard_test.go` |
| S2 对象 | xfront/types、sema/typedecl、codegen/classes | `ClassDecl`/`Strategy` | `typedecl_test.go`、`policy_test.go`、`b0_04_test.go` |
| S3 内存 | sema/policy、runtime | `Strategy`/`rt_*` | `policy_test.go`、`test_rt.c`、`test_gc.c`、`test_hard.c` |
| S4 错误处理 | interp/sema/codegen | `Result`/`try` | `hard_test.go`、`err01_test.go` |
| S5 任务/并发 | XDK/runtime（未来） | `tasks.x`/`sync.x` | 未开工 |
| S6 XDK | lib/xdk、bindings、rt_std_* | 8 包 | `test_std.c`、`ffi/xdk_test.go`、`xdk_seed_test.go` |
| S7 FFI | ffi/runtime | `Load`/`EmitSupport` | `ffi_test.go`、`emit_test.go`、`test_abi.c` |
| S8 工程 | xpd/cli/devtool | `Parse`/CLI | `parser_test.go`、`cli_test.go`、`devtool/*_test.go` |

### 13.2 B0 硬依赖与代码落点

| 卡片 | 内容 | 代码落点 | 当前状态 |
| --- | --- | --- | --- |
| B0-01 | P-09 `.xfb` 入口注入 | `internal/codegen/ffi`、调用点 | 进行中；注册表/包装已备，codegen 注入按卡推进 |
| B0-02 | P-10 C 清单 + LinkArgs | `internal/codegen/build.go:22`、`cli.go` | 已纳入 `xrt_abi.c`/`rt_std_*.c`；LinkArgs 去重升序 |
| B0-03 | 跨包 `import` | `internal/codegen/multifile.go` | 当前 `RES-109` 显式拒绝；待闭环 |
| B0-04 | 类字段初值 | `internal/codegen/classes.go` | B0-04 测试覆盖字段初值形态；继续补齐 |
| B0-05 | 容器/字符串成员 | `containers_expr.go`、`strmethods.go`、`codegen.go` | 成员覆盖矩阵推进；`List.insert` 等仍显式拒绝 |
| B0-06 | 读→解析→写 出口验证 | 示例 + 构建 | 进行中；以 QA 回执为准 |

说明：上表是代码落点，不是门禁结论；B0 是否通过以看板与回执为准。

### 13.3 B1—B4 对详细设计的影响

| 门 | 影响 |
| --- | --- |
| B1 `xnfmt` | 在 `xfront.PrintUnit` 之上建立稳定格式化规则；需与 Go 版逐字节一致 |
| B2 前端 | xfront 的 AST/诊断/打印接口成为自举版接口；Go 版作为 oracle |
| B3 代码生成 | codegen 的 C 文本/命名/排序规则成为自举版合同；以 Go 版差分 |
| B4 不动点 | CLI/devtool 迁 XNull；构建链去掉 Go；C 运行时/ABI 不变 |

### 13.4 自举前必须补齐的能力

| 能力 | 关联 | 状态 |
| --- | --- | --- |
| `.xfb` 入口注入 | B0-01 | 进行中 |
| 构建清单/LinkArgs | B0-02 | 已接入 |
| 跨包 import | B0-03 | 未闭环 |
| 类字段初值全形态 | B0-04 | 推进中 |
| 容器/String 成员 | B0-05 | 推进中 |
| 读→解析→写 | B0-06 | 进行中 |
| 文件/目录/资源 XDK | B1/B3 | C 层完成，API 层未齐 |
| 稳定格式化 | B1 | 未实现 |
| AST 打印/差分 | B2 | `PrintUnit` 基础存在 |
| 全量 C 生成 | B3 | 子集 |
| CLI/devtool 自举 | B4 | 未开始 |

### 13.5 开放问题

| 编号 | 问题 | 影响 | 处理建议 |
| --- | --- | --- | --- |
| O-01 | codegen 插值串只拼静态段 | 含表达式插值可能丢失 | 在 `strExpr` 对 `StrLitExpr` 的 `Expr` 段生成求值，或在 sema/codegen 显式拒绝 |
| O-02 | codegen 未覆盖 do-while/switch/incdec/goto | 与解释器支持面不一致 | 按自举代码实际使用面补齐；未用则保持显式拒绝 |
| O-03 | 类继承/协议/带参构造未生成 | 对象模型不完整 | M4.4b/M5 后续切片 |
| O-04 | `escape` 对象级回填未完成 | 栈分配/ARC 决策不完整 | 与 M4.4b 逃逸分析一起落地 |
| O-05 | 全局根/扫描钩子生成不完整 | GC 混合图在生成代码中不完整 | 与 GC 代码生成切片一起补 |
| O-06 | XPD 生命周期未接入 | 工程模式不可用 | 按 S8 五阶段接入 |
| O-07 | CI 04—09 为 SKIP | 质量门不完整 | 逐步实装；不得把 SKIP 当 PASS |
| O-08 | FFI trampoline 预留 | 回调面不完整 | 随调度器栈 pin/根登记 |
| O-09 | 并发/调度器未开工 | S5/XDK tasks/sync 无法完整验收 | 单独立项 |
| O-10 | Windows 运行时原语缺失 | 平台覆盖不足 | 保持接口，补实现分支 |

---

## 14. 附录

### 14.1 生成 C 骨架（hello 形态）

```c
/* 由 XNull 编译器生成 */
#include "rt.h"
#include "rt_gc.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static rt_string *xn_str_int(int64_t v) { ... }
static rt_string *xn_concat(rt_string *a, rt_string *b) { ... }
static void xn_throw(rt_string *msg) { ... exit(134); }

static int64_t xn_main(void) {
    rt_string *xn_t1 = rt_string_from_c("hello, XNull");
    xn_print_str(xn_t1);
    rt_release(xn_t1);
    rt_string *xn_t2 = xn_concat(rt_string_from_c("1 + 2 = "), xn_str_int(3));
    xn_print_str(xn_t2);
    rt_release(xn_t2);
    return 0;
}

int main(void) {
    int64_t xn_r = xn_main();
    rt_quarantine_flush();
    return (int)xn_r;
}
```

实际生成还包含 Result typedef、容器助手、类结构等；以 `EmitC` 输出为准。

### 14.2 `.xfb` 示例

```
ffi demo {
  handle File {
    close = ffiClose
  }

  @ffiEntry(cName = "demo_open")
  @lease(path = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.aware)
  Handle ffiOpen(String path);

  @ffiEntry(cName = "demo_close")
  @lease(file = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.aware)
  Int ffiClose(Handle file);
}
```

### 14.3 XPD 示例

```xpd
project {
  groupId    = com.example
  artifactId = hello
  version    = 1.0.0
  packaging  = app

  properties {
    language-version = [3.3, 4.0)
  }

  build {
    mode         = release
    entryFile    = src/main/x/main.x
    entryPackage = com.example.hello
  }

  link {
    unsafe = false
    libraries {
    }
  }
}
```

### 14.4 术语

| 术语 | 含义 |
| --- | --- |
| AST | 抽象语法树 |
| ARC | 自动引用计数 |
| GC | 标记—清扫垃圾回收 |
| DET-01 | 确定性要求 |
| oracle | 作为对照基准的实现（当前为 Go 版） |
| 双路径 | 编译路径与解释路径 |
| 台账 | 规范锚点 × 证据 |
| XPD | 工程清单方言 |
| XDK | 标准库 |
| `.xfb` | FFI 绑定声明 |
| `xn-s1/2/3` | 自举阶段编译器产物 |
| B0—B4 | 自举五道门 |

---

## 15. 结论

当前 XNull 的详细实现是一条**已打通但覆盖不完整**的纵向切片：前端、语义、C 代码生成、C 运行时、FFI、XDK 原语、XPD 解析、CLI 与维护工具都有真实代码与测试，且未支持面大多显式报错。系统级设计的关键约束已经稳定：

- 规范是语义唯一来源；
- 编译路径是正式路径，解释器是调试/oracle；
- 内存策略由编译器判定、C 运行时执行；
- FFI 只经 `.xfb` 合同与 `xrt.h` 稳定 ABI；
- XDK 公开 API 用 XNull 写；
- 所有交付以证据为准；
- B0—B4 决定 Go 脚手架何时退出。

下一步的详细设计工作应集中在 B0 的六个硬依赖、codegen 未覆盖语句/插值、XPD 生命周期接入、CI 04—09 实装，以及自举前端的 AST 打印/差分接口。每次能力变化都应同时更新本文、总体设计与台账，避免设计文档成为过期副本。
