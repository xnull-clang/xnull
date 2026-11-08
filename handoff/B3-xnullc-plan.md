# 接力棒：B3 / xnullc 架构盘点

- **卡片ID**：B3（XNull 写完整 `xnullc`，AST → C）
- **输入**：`XNull解决方案-第9部分-工具链-模块01-编译前端与C代码生成-v1.0.0.md`、归档判决 v1.9.0/ADR-009 的 B3 定义、当前 Go 版 `impl/internal/codegen/**`
- **输出文件**：本文件（只盘点，不实现）
- **基线**：`main` 已含 S1–S8 全绿；E3 工作树代码面等于 `main`（S6/S7 已合入）
- **性质**：只读盘点；未改生产代码、未动 oracle

## 一、结论摘要

1. Go 版代码生成层约 **1.48 万行生产代码**（`impl/internal/codegen/*.go`，不含测试）+ **2100 行 FFI 子包**，单文件 `codegen.go` 占 4934 行、`classes.go` 1172 行。B3 不是“翻译一个函数”，而是**重写一个有状态的两遍发射器 + 8 类语言面 + FFI/内存策略/构建边界**。
2. 分层清晰但**高度耦合于 Go 的 `gen`/`scope` 可变状态**：XNull 版必须先定“显式状态对象 + 纯函数发射”的接口，否则会复制出不可测的巨型类。
3. 可复用 XNull 库目前只有 `xdk.errors/text/collections` 较完整；`sys/runtime/tasks/sync/net` 仍是骨架或仅解释器语义，**B3 开始前必须优先补齐 `sys` 的文件读写源码面**（否则 xnullc 无法读 AST/写 C）。
4. Oracle 口径建议严格按“同一 AST 输入 → C 文本逐字节一致 + 双路径 stdio/退出码一致 + 两次生成逐字节一致”；不以“能编译运行”替代文本差分。
5. 建议拆 **B3-00 差分基座 + B3-01..B3-09 九个实现卡 + B3-10 收口门**；先基础面后对象/泛型，FFI/S5/S6 面最后接入。

## 二、现有分层与模块清单

### 2.1 端到端数据流（当前 Go 版）

```
.x + import 闭包
  → codegen.LoadUnits（multifile.go）
  → xfront.ParseUnit（AST）
  → sema.Analyze/AnalyzeWith + Strategy（类型/策略）
  → EmitC*（codegen）
  → C 文本
  → codegen.BuildWithOptions（写 .c + cc + LinkArgs + 资源表）
  → 可执行体
```

### 2.2 代码生成包内模块

| 模块 | 文件 | 行数 | 职责 |
|---|---|---:|---|
| 核心发射器 | `codegen.go` | 4934 | `gen`/`scope` 状态、prelude、表达式/语句/函数/入口、Result、字符串、内建调用、两遍发射 |
| 容器 | `containers.go` / `containers_expr.go` | 667 / 619 | 按元素类型生成数组/List/Set/Map 结构与助手；字面量/成员/下标发射 |
| 类与对象 | `classes.go` / `classes_expr.go` | 1172 / 749 | 类布局、类型描述符、ARC、构造/方法/deinit、字段/成员表达式、继承/协议 vtable |
| 协议 | `protocol.go` | 392 | 协议签名、vtable 槽位、动态派发 |
| 泛型 | `generics.go` / `generic_class.go` | 316 / 172 | 函数/类单态化、实例命名、深替换、展开上限 |
| 元组 | `tuple.go` | 405 | 元组结构体、字面量/访问/赋值/相等/插值 |
| 结构体 | `struct.go` | 361 | 值布局、复制、方法/构造器 |
| 枚举/单例/工厂/扩展 | `enum.go` / `singleton.go` / `factory.go` / `extension.go` | 285 / 257 / 139 / 118 | 各声明的 C 发射面 |
| 字符串成员 | `strmethods.go` | 109 | `length/substring/indexOf/trim/toUpper/toLower/startsWith/endsWith` |
| 轻量类型推断 | `types.go` | 420 | 仅服务分派/返回类型的生成期推断 |
| Any/Object | `any.go` | 169 | 装箱/拆箱与类型描述符 |
| 内存策略 | `stack.go` | 337 | 逃逸分类消费、栈对象发射 |
| S3/S4/S5/S6 内建面 | `s304.go` / `s402.go` / `s504.go` / `s603.go` / `s604.go` | 150 / 218 / 528 / 533 / 212 | Text/StringBuilder、errors、任务内存、sys 双形态、资源读取 |
| FFI 接线 | `ffi_gen.go` + `ffi/` | 464 + 2100 | `LoadFFI`→`InjectFFI`→`EmitCWithFFI`；`.xfb` 解析/校验/包装生成/LinkArgs |
| 构建 | `build.go` | 183 | C 源清单、`cc`、`LinkArgs`、`MemPolicy`/`Stats`/`ResC` |
| 多文件 | `multifile.go` | 175 | import 闭包、环检测、XDK 单元装载、顺序合并 |
| XDK 合同 | `xdk_contract.go` | 683 | XDK 包依赖/稳定性机械核验 |
| 入口/诊断 | `codegen.go` 内 | — | `RequireEntry`、入口签名、错误诊断 |

### 2.3 对外接口（B3 必须保持的语义契约）

| 接口 | 现状 | B3 对等物 |
|---|---|---|
| `LoadUnits(entry) (*CompilationUnit, []diag)` | Go 版装载 | B2 前端/装载提供（XNull 或复用） |
| `EmitC(u)` / `EmitCWithFFI(u, reg)` / `EmitCWithBuildOptions(...)` | C 文本 | `xnullc` 命令行/库入口（AST→C） |
| `sema.Analyze/AnalyzeWith` + `Strategy` | 诊断/内存策略 | B2/B3 消费；XNull 版需策略结构 |
| `ffi.Registry`（`.xfb` 合同投影） | 结构体注册表 | B3 输入，不重写 `.xfb` 解析 |
| `RequireEntry(u)` | 入口唯一/签名 | 对等错误行为 |
| `BuildWithOptions` | C→cc→产物 | B4/构建层，B3 可只到 C 文本 |

### 2.4 核心状态（XNull 化的关键难点）

- `gen`：约 45 个 map/slice 字段（Result/容器/类/泛型实例/协议槽/枚举/单例/工厂/扩展/临时编号/延迟原型/策略/栈候选…）。
- `scope`：约 17 个字段（父块、返回槽、defer 栈、pending 临时、params/locals/self、staticRefs、root 帧、task 体上下文）。
- 两遍发射：第一遍“试生成”收集实例，第二遍正式输出并重置临时编号；文本稳定性依赖 map 遍历禁用与显式排序。
- 所有权：字符串 `rt_retain/rt_release` 与 `xn_concat` 接管、类引用 ARC、容器元素 retain/release、defer 栈内联展开。

## 三、C 输出分层（B3 需要逐层对齐）

1. **Prelude**：`rt.h/rt_gc.h/xrt.h`、print/str、可选值、字符串助手、div/mod fatal、Any 助手、Result 基础助手。
2. **类型定义层**：Result 实例、容器结构/助手、元组结构体、类/struct 结构体与类型描述符、vtable、枚举常量。
3. **函数与对象方法层**：按声明顺序（类/结构体/单例/扩展/泛型实例）发射；入口 `main` 垫片。
4. **FFI 支撑层**：`xn_ffi_<entry>` 包装、错误码分类、句柄/租约/canary。
5. **确定性末尾**：临时编号、实例/类型按名称排序、延迟原型顺序稳定。

## 四、可复用的 XNull 库（当前状态）

| 库 | 状态 | B3 用途 | 风险 |
|---|---|---|---|
| `xdk.sys` | 骨架（源码面无 File/Dir 实现；C/绑定已有） | xnullc 读 AST/源、写 `.c` | **P0 前置**：需先补 `sys.x` 的 `File/Dir/readFileText/writeFileText` |
| `xdk.text` | Format/parse/UTF/Regex（源码单元已交；解释路径可用，编译路径受 E4 codegen 限制） | 生成文本、诊断格式化、UTF 处理 | 编译 xnullc 自身需要 E4 支持 `Result<_,Error>`/Char |
| `xdk.collections` | 4 算法 + 4 容器源码单元（解释路径过） | AST 表、实例注册表、排序/去重 | B3 编译器自身要用 `List/Map/Set`，优先内建容器 |
| `xdk.errors` | Error 协议/ErrorKind/wrap/mapErr/report | 诊断/构建错误 | 已对齐 S4 |
| `xdk.runtime` | 骨架（diagnose/exit/now* 绑定在 C 面） | 诊断/退出/时钟 | 源码面需补齐 |
| `xdk.tasks/sync/net` | 骨架/解释器语义 | B3 核心编译器不需要；并发/网络生成面后置 | 不阻塞 B3 主路径 |

**结论**：B3 的硬前置不是“再造一遍 codegen”，而是 **`xdk.sys` 源码面 + 编译器自身可执行所需的最小 XNull 语言面**（B2 前端 AST、类/容器/闭包/Result/通用字符串）。

## 五、Oracle 差分口径（建议冻结）

### 5.1 输入口径

- 输入统一为 **B2 前端产出的 AST**（Go 与 XNull 前端对全仓库 `.x` 的 AST 已逐字节一致）。
- 若 AST 文本比较成本高，用“同一源文件 + 同一 import 闭包 + 同一 `.xfb` 注册表 + 同一策略表”作为输入三元组；Go 版与新 `xnullc` 都从源码重跑前端，但**前端 AST 先单独验收**。
- 构建选项固定：`MemPolicy=auto`、`Stats=false`、无 `LinkArgs`（B3 只管 AST→C，不链接）。

### 5.2 输出口径

| 差分项 | 判定 |
|---|---|
| **C 文本** | `ca.c` 与 `cb.c` **逐字节一致**（包括 prelude、空行、临时编号、排序） |
| **退出码/诊断** | 成功=0；语义/生成失败码一致；错误消息按冻结文案逐字节一致（允许 B3 阶段先比错误码+位置，再收紧文案） |
| **双路径** | 同一 C 用同一 `cc`+同一运行时编译运行，9 示例 stdout/退出码逐字节一致（以 Go 版为 oracle） |
| **确定性** | 同一输入生成两次，C 文本 `sha256` 相同；不同目录不影响输出 |
| **负例** | 未支持构造必须同样失败（不静默降级），诊断位置/码一致 |

### 5.3 差分流水线（建议）

```bash
# Go oracle（B3 期间保留，B4 删除）
go build -o /tmp/xnullc-go ./cmd/xnullc-oracle
/tmp/xnullc-go --emit-c <entry> > /tmp/go.c

# XNull 版
xnull build xnullc.x -o /tmp/xnullc
/tmp/xnullc --emit-c <entry> > /tmp/xn.c

diff -u /tmp/go.c /tmp/xn.c
sha256sum /tmp/go.c /tmp/xn.c       # 两次生成再比一次
cc -std=c11 -I impl/runtime ...     # 双路径运行比对
```

## 六、风险清单

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | `gen`/`scope` 状态 45+17 字段在 XNull 中变成巨型类，难测 | 迁移慢、回归难定位 | B3-01 先定 `Emitter{...}` 显式状态 + 每个语言面一个函数文件；禁止全局可变 |
| R2 | 两遍发射 + 临时编号 + map 排序 | C 文本无法逐字节一致 | 所有注册表显式排序；临时编号第二遍重置；确定性测试前置 |
| R3 | 所有权/ARC/GC/栈策略 | 运行期崩溃或泄漏，双路径差异 | 按 S3 八条所有权逐条对拍；栈/GC 卡独立验收 |
| R4 | Result/字符串/容器助手命名与签名 | C 文本差异 | 冻结 naming/mangle/prelude 契约（模块 01 §6.3） |
| R5 | 泛型/类单态化实例发现顺序 | 实例名/输出顺序不一致 | 实例表按名称排序；64 轮上限沿用 |
| R6 | FFI/P-09/`.xfb` 注册表 | 调用点/包装差异 | B3 只消费注册表；包装生成用单独卡对拍 |
| R7 | XDK 源码面缺 `sys` | xnullc 无法读写文件 | B3 前置卡（S6-03/08 的 `sys.x` 源码面） |
| R8 | oracle 自身有未支持面/已知 bug | 把 bug 当规范 | 差分前冻结 oracle commit；负例清单登记；不以“oracle 绿”代替规范 |
| R9 | XNull 编译 xnullc 体积/性能 | 构建时长/内存 | 先用 List/Map 内建容器；避免闭包深递归；B4 再优化 |
| R10 | B3 期间 Go 依赖未清零 | 误称自举 | 严格执行 B3 只做 oracle 差分，B4 才删 Go |

## 七、卡拆分建议

| 卡 | 范围 | 依赖 | 验收 |
|---|---|---|---|
| **B3-00 差分基座** | 冻结 Go oracle commit；`--emit-c` 入口；C 文本/diff/sha/双路径脚本；负例清单 | S1–S8 定版（已） | 同一输入 Go 自比两次 0 diff；9 示例双路径基线 |
| **B3-01 xnullc 骨架** | XNull 版 CLI/库入口、`Emitter`/`Scope` 显式状态、prelude、装载/入口、空程序发射 | B3-00、B2 AST、`sys.x` 读写 | 空 `main`/hello 的 C 与 Go 逐字节一致 |
| **B3-02 基础表达式/语句** | Int/Bool/String/Char/Float/Double、运算符/短路/三元、if/while/for-in/switch/do-while、赋值/incdec、print/str、插值 | B3-01 | EXPR/STMT 黄金 C + 双路径 |
| **B3-03 Result/try/defer** | Result 实例化、`Ok/Err`、成员、`try` 传播、defer/errdefer 内联、throw/fatal | B3-02 | 清理/顺序/退出码用例（含 CLEAN/ERR 锚点） |
| **B3-04 容器** | 数组/List/Set/Map 结构/助手/字面量/成员/下标/所有权；XDK 容器方法 | B3-02/03 | 所有容器正例 + 边界 panic |
| **B3-05 对象面** | class/struct/协议/vtable/继承/构造/deinit/单例/工厂/扩展/枚举 | B3-03/04 | S2 全锚点黄金 C + 双路径 |
| **B3-06 泛型/元组/可选/Any** | 函数/类单态化、元组、可选值、Any/Object 装箱、is/as | B3-05 | GEN/TUPLE/TYPE 锚点 |
| **B3-07 内存策略** | arc/gc/栈候选、GC 根/scan、弱表接线、deinit 顺序 | B3-05 | S3 MEM 锚点 + 两次生成稳定 |
| **B3-08 FFI/XDK 面** | `.xfb` 注册表消费、P-09 注入、包装/错误码、S4/S5/S6 内建面 | B3-03/04 | FFI/XDK 锚点 + 包装文本 diff |
| **B3-09 全量收口** | 全仓库 `.x`、9 示例、负例矩阵、确定性、构建脚本 | B3-01..08 | C 文本全量 0 diff；双路径 9/9；全量测试绿 |
| **B3-10 B4 前置** | xn-s1 编译 xnullc、xn-s2 自编译、xn-s2==xn-s3、Go 删除清单 | B3-09 | B4 四件套（B4 卡细化） |

## 八、复现与证据

```bash
cd impl
go test ./internal/codegen -count=1                 # Go oracle 基线
go test ./... -count=1 -timeout 900s                # 19 包全绿基线
wc -l internal/codegen/*.go | tail -1               # 生产/测试规模
grep -n "type gen struct" -A 50 internal/codegen/codegen.go
grep -n "type scope struct" -A 25 internal/codegen/codegen.go
```

## 九、声明

本盘点只读：未改 `impl/**`、未新增构建系统、未动 oracle。B3 开工前需 owner 确认 **`sys.x` 源码面**与 **B2 AST 接口冻结**两项前置；本文件作为 B3 拆卡与差分口径的起点。
