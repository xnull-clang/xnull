# XNull 实现说明（impl/）

> 内部实现文档。规范以仓库根《XNull 解决方案》八部分为准；本文只记实现层决策。

## 构建与运行

- 工具链：**Go ≥ 1.27**（`go.mod` 的 `go 1.27` 指令锁定最低版本；风险点 4 落实）。
- 构建：`cd impl && go build -o xnull ./cmd/xnull`
- 运行单文件（最小可运行闭环）：

```
xnull run examples/hello.x
```

退出码：0 成功；1 语法/运行错误（含 fatal）；2 文件不可读或用法错误；130 中断。

## 内部维护工具（xnull dev）

仓库维护工具全部由 Go 提供，不再依赖 Python：

```
xnull dev check  [仓库根]    # 规范守门：头部一致/零待定/§ 引用/二进制拦截/EN 快照
xnull dev ledger [仓库根]    # 从 S1—S8 母本重生成《一致性用例台账》
xnull dev res <目录> <out.c> # 生成资源表 C 源（S8 §5.6）
```

`dev` 只服务仓库维护，不属于语言用户的稳定 CLI 面。EN 快照滞后判据为**文件名版本 + 母本内容 SHA-256**
（清单 `impl/docs/conformance/en-source.sha256`），与文件 mtime 无关（mtime 在 clone/checkout 后会刷新，不可作为判据）。`impl/runtime/build_rt.sh` 以
`go run ./cmd/xnull dev res` 调用资源表生成器（构建期工具，不进入运行时产物、不携带 Go 运行时）。
`dev res` 按 S8 §5.6 递归收录资源根下全部常规文件，资源名为**相对资源根的 `/` 分隔路径**（如
`templates/mail/a.html`），按名升序输出；空目录不产生条目；符号链接按目标内容读取，断链、指向目录或越出资源根一律失败。

## 解释器范围（internal/interp）

tree-walking 解释器（最小可运行闭环），支持：顶层函数/字段、局部声明、赋值与复合赋值、自增/自减、
if/while/do-while/for-in 区间、switch（无隐式贯穿）、break/continue（含标签）、
`Result`/`Ok`/`Err`/`try` 传播（S1 §10.1—10.2）、`defer`/`errdefer` LIFO（§10.3）、
`throw` fatal（§10.4，不执行 defer）、字符串插值、三元、`??`、逻辑短路。

内置函数（≤ 3）：`print(x)`、`str(x)`。`Ok`/`Err` 是语言构造器，不是内置函数。

不支持（后续切片）：对象/类、容器值与遍历、元组值、闭包值、goto、类型运算 `is`/`as`、
静态类型检查（名称解析 §3.3、确定赋值 §5.3、类型检查 §2.6 均在语义分析切片）。

## Go 选型风险点落实

### 1. map 遍历随机 vs DET-01 确定性

- 解释器**没有 map 运行值**，输出路径无随机源；`internal/interp/interp_test.go`
  的 `TestDeterminismByteIdentical` 固化"多次运行逐字节一致"。
- **长期规则**：后续引入 map 值后，凡 map 参与输出或影响执行顺序的边界（遍历顺序、
  键枚举、诊断排序），必须按键排序；违反即缺陷。此规则同时约束编译器诊断的输出顺序。

### 2. Int128 / UInt128：版本化延后

- Go 无原生 128 位整数。决策：**版本化延后**——与 S1 §实现边界一致
  （"`Int128`/`UInt128` 尚未提供真实的 128 位后端布局；不得依赖其宽度和溢出行为"）。
- 词法层已按规范接受 `Int128`/`UInt128` 类型名；执行层不支持，用到即报
  解释器不支持诊断（不静默）。
- 后续如需支持，用模拟实现（`math/bits` 双字或 `math/big`）另立切片，不做悬空承诺。

### 3. 运行时必须用 C，不能用 Go

- **编译器前端用 Go**（词法/语法/后续语义分析）——工程效率优先，前端无运行时语义。
- **运行时（ARC/GC、`deinit` 时序、内存判定表执行）必须用 C 实现**：S3/S5 已把
  运行时语义锁死（清扫时序、release→`deinit`→回收、不复活等强制语义），
  Go 的 GC 与 goroutine 栈语义无法承载这些合同；Go 不承载运行时。
- 解释器是过渡交付物，不是运行时；正式运行时按 S3/S5 用 C 落地。

### 4. 工具链版本锁定

- `go.mod`：`go 1.27`。
- 构建环境要求：Go 1.27+；交叉编译验证矩阵：windows/amd64、linux/arm64
  （每次全量测试时一并验证）。

## 目录

```
cmd/xnull/        命令行入口
internal/cli/     命令分派与退出码
internal/xfront/  词法分析器、解析器、AST、打印器（M1 语法层，四级齐备）
internal/interp/  tree-walking 解释器（最小可运行闭环）
internal/sema/    语义分析（名称解析先行；诊断码 RES-1xx）
internal/xpd/     XPD 解析器（设计提案格式）
internal/diag/    诊断结构
internal/exitcode/ 退出码常量（S9 §5.1）
docs/conformance/ 一致性状态（status.tsv → xnull dev ledger 生成台账）
internal/devtool/ 维护工具：check（规范守门）/ ledger（台账生成）/ res（资源表生成）
```

## 测试

```
go vet ./... && go test ./... -count=1
```

确定性验收：`go test ./internal/interp/ -run TestDeterminismByteIdentical`。
