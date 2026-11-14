# XNull 软件总体设计

> **2026-11-15 更正**：G6「XDK 公开 API 用 XNull 写」是实现目标，不是规范要求，且与 S9-01 §2.3「`xdk.*` 不落文件系统」冲突；
> 本文描述的 Go 组件架构已不存在。现行约定见 `死命令.md` / `PLAN.md`，本文只作历史参考。

| 项 | 值 |
| --- | --- |
| 文档编号 | XNULL-DESIGN-001 |
| 文档版本 | 1.0.0 |
| 文档性质 | 工程设计文档（非规范性；规范冲突时以 S1—S8 母本为准） |
| 编制日期 | 2026-11-07 |
| 代码基线 | `ea6fdf3`（2026-11-07，M6-B0 进行中） |
| 适用工具链 | `xnull 0.1.0-dev` |
| 适用规范 | S1 v3.3.0、S2 v3.3.0、S3 v3.0.0、S4 v1.0.0、S5 v1.0.0、S6 v1.1.0、S7 v1.0.0、S8 v5.2.0 |
| 配套文档 | 《XNull 详细总体设计》`XNull详细总体设计-v1.0.0.md` |
| 别名说明 | 本文 S4/S5/S6/S7/S8 分别指第 4/5/6/7/8 部分；与索引历史别名不一致时，以部分号为准 |

## 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| 1.0.0 | 2026-11-07 | 首版。按当前实现基线建立系统级总体设计，覆盖工具链、运行时、XDK、FFI、工程配置、验证与自举路线。 |

---

## 0. 摘要

XNull 不是一个单独的编译器，而是一套由**语言规范、工具链、C 运行时、标准库、FFI 合同、工程系统和证据体系**共同组成的软件开发平台。其工程目标可以概括为三句话：

1. **语义由规范决定**：源码文本 + S1—S8 母本决定程序行为；实现不得引入规范之外的隐式行为。
2. **执行由编译路径承担**：默认 `xnull run` 走“XNull → C → 系统 `cc` → 可执行文件”，解释器仅作为调试路径与对照 oracle。
3. **实现最终由 XNull 自身承担**：当前编译器、CLI、维护工具用 Go 实现，这是自举脚手架；B0—B4 五道门通过后，Go 版删除，工具链由上一版 XNull 编译产生。

当前系统已经形成一条可运行的纵向切片：

```
.x 源文件
  → xfront（词法 / 语法 / AST）
  → sema（名称解析 / 确定赋值 / 类型检查 / 内存策略判定）
  → codegen（XNull AST → C）
  → 系统 cc（C11）
  → C 运行时（ARC / GC / 策略执行器 / 稳定 ABI / XDK 原语）
  → 可执行文件
```

与本管线并行的还有解释器调试路径、`.xfb` FFI 绑定子系统、XDK 三层库结构、XPD 工程配置解析器、规范守门与台账生成工具。当前实现是**部分覆盖**而非全语言完成：codegen 对未支持构造原则上显式报错、不静默降级（插值串表达式段是已记录的例外，见 R-11）；一致性状态以 `impl/docs/conformance/status.tsv` 与《XNull 一致性用例台账》为准。

---

## 1. 文档目的与范围

### 1.1 目的

本文回答系统级问题：

- XNull 软件由哪些部分组成，各部分边界与依赖方向是什么；
- 一次编译、构建、运行、FFI 调用、资源打包分别经过哪些阶段；
- 哪些接口是稳定的、哪些是内部实现细节；
- 质量属性如何定义、如何验证、当前证据到什么程度；
- 自举（B0—B4）如何改变系统结构，哪些部分长期保留。

本文不逐函数、逐数据结构描述实现；这些内容见配套的《XNull 详细总体设计》。

### 1.2 范围

**在范围内：**

- `xnull` 命令行工具链及其子命令；
- `impl/internal/xfront` 前端；
- `impl/internal/sema` 语义分析；
- `impl/internal/codegen` 代码生成与 `impl/internal/codegen/ffi` 绑定子系统；
- `impl/runtime` C 运行时与 `xrt_*` 稳定 ABI；
- `impl/lib/xdk`、`bindings/xdk` 与 `rt_std_*` 组成的 XDK 三层结构；
- `impl/internal/xpd` 工程配置解析；
- `impl/internal/interp` 解释器调试路径；
- `impl/internal/devtool` 维护工具；
- 测试、CI、证据与一致性台账；
- 自举门禁 B0—B4 对架构的约束。

**不在范围内：**

- S1—S8 的语义细节与条款解释（以母本为准）；
- 具体算法与数据结构的逐行说明（见详细设计）；
- 组织治理、排期、发布运营；
- 第三方库生态、IDE、包仓库托管服务；
- 性能基准数字与对外性能承诺。

### 1.3 文档关系

| 文档 | 性质 | 与本文关系 |
| --- | --- | --- |
| `XNull解决方案-第1—8部分-*.md` | 规范性 | 语义与合同的唯一来源；与本文冲突时以母本为准 |
| `XNull规范索引-v1.0.0.md` | 工作文档 | 规范清单、引用图谱、版本与决策记录 |
| `XNull一致性用例台账-v1.0.0.md` | 工作文档 | 规范锚点 × 实现证据的逐条状态 |
| `impl/README.md` | 实现说明 | 构建、运行、解释器范围、Go 选型风险 |
| `impl/docs/*.md` | 实现设计 | 运行时合同、codegen、FFI、XDK 的领域设计 |
| 本文 | 工程设计 | 系统级架构、边界、接口、质量与演进 |
| 《XNull 详细总体设计》 | 工程设计 | 模块级结构、算法、数据布局与接口细节 |

---

## 2. 目标、非目标与约束

### 2.1 工程目标

| 编号 | 目标 | 可判定的完成信号 |
| --- | --- | --- |
| G1 | 把 S1—S8 的定案语义落成可执行实现 | 台账对应锚点有真实用例证据 |
| G2 | 默认路径可编译、可运行、可诊断 | 示例经 `xnull build` / `xnull run` 跑通，退出码符合合同 |
| G3 | 编译路径与解释路径行为一致 | 同一程序的 stdout/退出码逐字节一致 |
| G4 | 内存策略由编译器判定、运行时执行 | `Strategy` 与 `rt_policy_input` 逐字段映射，判定行可复核 |
| G5 | FFI 只经合同边界 | `.xfb` 校验、包装 ABI、`xrt_*` 稳定 ABI 三层齐备 |
| G6 | XDK 公开 API 用 XNull 写 | `impl/lib/xdk/*.x` 可解析、可语义检查、可生成 C |
| G7 | 工程配置可解析、可校验、可复现 | XPD 解析器通过规范文法样例，构建纪律可审计 |
| G8 | 工具链最终自举 | B0—B4 五道门全部通过，产品范围内 Go 源码/二进制为 0 |
| G9 | 所有交付可追溯 | 代码、命令、差分、SHA-256、日志、回执齐全 |

### 2.2 非目标（设计性拒绝）

以下不是“尚未做”，而是当前语言与系统的明确边界：

- 方法覆写、抽象方法、反射、异常展开；
- 访问器/getter/setter 模式；
- 源码级裸指针、地址运算、手动 `free`；
- 内核、驱动、裸机、硬件寄存器直访；
- 严格硬实时保证；
- GPU 内核与设备侧代码生成；
- 任意 C 结构体布局直接共享；
- 动态装载/卸载托管插件；
- 用 Rust、Zig 等第三方语言替换 Go 完成自举。

这些边界的理由与条款落点见 S1 §0.6、S2 §0.4、S3 §19/§26、S4 §9、S7 §11 与《XNull 语言能力与应用边界》。

### 2.3 工程约束

1. **规范优先**：实现不得修改语义来迁就代码；语义变更必须先改母本并留痕。
2. **C 运行时不可替换**：ARC/GC、终结时序、弱表、策略执行器必须由 C 承载；Go 的 GC 与调度语义不能替代。
3. **Go 只做脚手架**：当前 Go 代码是借力实现；B4 后产品工具链不得依赖 Go。
4. **确定性**：同一输入 + 同一工具链版本 → 相同诊断顺序、相同 C 文本、相同程序输出；map 参与输出必须排序。
5. **禁网构建**：构建与测试不依赖网络；依赖解析只认清单与约定目录。
6. **显式失败**：未支持构造必须报错或记入 `Problems`，不得静默降级、不得“先跑再说”。
7. **平台边界**：工具链可交叉编译；C 运行时的系统原语首批按 POSIX 实现，Windows 走后续实现分支。

---

## 3. 系统上下文

### 3.1 上下文图

```
                         ┌──────────────────────────────┐
                         │ 语言用户 / IDE / CI / 发布流程 │
                         └──────────────┬───────────────┘
                                        │ CLI、源文件、清单、资源
                                        v
┌──────────────────────────────────────────────────────────────────┐
│                        XNull 工具链（当前 Go）                     │
│  xnull run / build / policy / dev check / ledger / res            │
│  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌──────────────┐       │
│  │ xfront  │→ │  sema   │→ │ codegen  │→ │ 生成 C 源文件 │       │
│  └─────────┘  └─────────┘  └────┬─────┘  └──────┬───────┘       │
│        │             │           │ ffi 注册表     │               │
│        │             │           v                v               │
│        │             │      ┌─────────┐     ┌──────────┐         │
│        │             └─────→│ interp  │     │ 系统 cc  │         │
│        │                    └─────────┘     └────┬─────┘         │
└────────┼──────────────────────────────────────────┼───────────────┘
         │                                          │ 链接
         v                                          v
┌──────────────────────┐                  ┌────────────────────────┐
│ 规范母本 / 台账 / 证据 │                  │ C 运行时 + XDK 原语     │
│ S1—S8、status.tsv     │                  │ rt*.c、xrt_abi.c、     │
│ evidence/、收件箱回执  │                  │ rt_std_*.c、资源表     │
└──────────────────────┘                  └───────────┬────────────┘
                                                      │
                                                      v
                                            ┌──────────────────┐
                                            │ 可执行文件 / 进程 │
                                            └──────────────────┘
```

### 3.2 参与者与外部系统

| 参与者/系统 | 交互 | 合同 |
| --- | --- | --- |
| 语言用户 | 写 `.x`、运行 `xnull`、读诊断 | S1—S8、CLI 退出码、诊断格式 |
| 工具链开发者 | 修改 `impl/`、跑测试、产生证据 | `impl/README.md`、`impl/docs/*`、CI |
| 绑定/原生库作者 | 写 `.xfb`、提供原生符号与链接库 | S7、`ffi-contract.md`、`link.libraries` |
| 系统 C 编译器 | 接收生成的 C 与运行时 C 源 | C11、`cc`、平台 ABI |
| 操作系统/libc | 文件、目录、进程、时钟、环境变量 | POSIX 优先；资源读取由运行时表承担 |
| 运行时 | 提供分配、计数、GC、弱表、句柄、字符串 | `rt.h`（内部）/`xrt.h`（稳定 ABI） |
| 规范与台账 | 约束语义与验收 | S1—S8、`status.tsv`、台账 |
| 自举后的上一版 XNull | 编译下一版工具链 | B4 不动点合同 |

### 3.3 外部接口清单

| 接口 | 生产者 | 消费者 | 形态 |
| --- | --- | --- | --- |
| `.x` 源文件 | 用户/XDK/自举代码 | xfront | UTF-8 文本 |
| `.xfb` 绑定声明 | 绑定层 | ffi 子模块 | 受控小方言 |
| `xnull.project` / `xnull.lock` | 工程 | XPD 解析器/构建 | XPD 段落树 |
| `application.properties` | 服务部署 | 运行时配置层 | flat properties（S8 §6） |
| CLI 参数 | 用户/CI | `internal/cli` | 子命令 + 旗标 |
| 生成 C | codegen | 系统 cc | C11 文本 |
| 原生库 | 系统/第三方 | 链接器 | `.a` / `.so` / `.dylib` / `.dll` |
| 诊断 | 工具链 | 用户/CI | `file:line:col: error[CODE]: message` |
| 退出码 | 工具链/程序 | shell/CI | 0/1/2/130；程序 fatal 134 |
| 证据 | 开发/QA | 验收 | `evidence/`、回执、SHA-256 |

---

## 4. 架构总览

### 4.1 架构原则

| 原则 | 落地方式 |
| --- | --- |
| 规范与实现分离 | 规范母本只描述语义；实现文档只描述决策与证据 |
| 管线单向 | 源文件 → 前端 → 语义 → 代码生成 → C → 链接；不反向依赖 |
| 单一事实源 | AST 由 xfront 定义；sema 结果由 sema 定义；运行时布局由 `rt.h` 定义 |
| 显式边界 | 模块之间用小型接口与值类型连接；FFI 用 `.xfb` 注册表；运行时不暴露内部头 |
| 确定性优先 | 所有集合输出排序；临时变量编号按遍历顺序；诊断按位置排序 |
| 证据驱动 | 每条能力有测试文件、状态行、必要时有差分报告 |
| 可替换前端/后端 | 自举时替换 xfront/codegen，不替换 C 运行时与 ABI |

### 4.2 分层视图

| 层 | 内容 | 主要目录 | 稳定性 |
| --- | --- | --- | --- |
| L0 规范与合同 | S1—S8、运行时合同、FFI 合同、台账 | 根目录、`impl/docs/` | 规范冻结；合同按变更单 |
| L1 语法前端 | 词法、语法、AST、打印 | `impl/internal/xfront` | 内部接口，随语言版本演进 |
| L2 语义分析 | 名称、确定赋值、类型、策略、错误/清理规则 | `impl/internal/sema` | 内部接口 |
| L3 代码生成 | AST → C、容器/类/字符串/Result、FFI 调用 | `impl/internal/codegen` | 内部接口；生成文本是验收面 |
| L4 运行时与 ABI | ARC/GC/策略/弱表/句柄/字符串 | `impl/runtime` | `xrt.h` 稳定；`rt.h` 内部 |
| L5 标准库 | XDK 源码层 + 绑定层 + C 原语 | `impl/lib/xdk`、`bindings/xdk`、`rt_std_*.c` | API 按 S6 版本化 |
| L6 工程与工具 | CLI、XPD、devtool、构建驱动 | `impl/cmd`、`impl/internal/cli`、`xpd`、`devtool` | CLI 面稳定；dev 内部 |
| L7 验证与证据 | 单元/黄金/双路径/C 套件/CI/证据 | `impl/**/*_test.go`、`runtime/test_*.c`、`ci/`、`evidence/` | 证据格式稳定 |

### 4.3 组件关系

```
                         ┌──────────────┐
                         │ cmd/xnull    │
                         └──────┬───────┘
                                v
                         ┌──────────────┐
                         │ internal/cli │
                         └──┬───┬───┬───┘
              ┌─────────────┘   │   └──────────────┐
              v                 v                  v
       ┌────────────┐   ┌────────────┐    ┌──────────────┐
       │  xfront    │   │  devtool   │    │     xpd      │
       └─────┬──────┘   └────────────┘    └──────────────┘
             v
       ┌────────────┐
       │    sema    │
       └─────┬──────┘
             v
       ┌────────────┐      ┌──────────────────┐
       │  codegen   │─────→│ codegen/ffi      │
       └─────┬──────┘      │ (.xfb 注册表)     │
             │             └────────┬─────────┘
             v                      v
       ┌────────────┐      ┌──────────────────┐
       │  生成 C    │      │ xrt 稳定 ABI      │
       └─────┬──────┘      └────────┬─────────┘
             v                      v
       ┌─────────────────────────────────────┐
       │ C 运行时 / XDK 原语 / 系统 cc / libc │
       └─────────────────────────────────────┘

       xfront ──→ interp（--interp 调试路径；与 codegen 共享 AST）
```

依赖方向约束：

- `xfront` 只依赖 `diag`；
- `sema` 只依赖 `xfront`、`diag`；
- `codegen` 依赖 `xfront`、`sema`、`ffi`、`diag`；
- `ffi` 只依赖 `diag`，不反向依赖 `codegen`；
- `interp` 只依赖 `xfront`；
- `cli` 是唯一组装层；
- `devtool` 不依赖语言前端，只处理规范文本、台账与资源；
- 测试可以跨包引用，但生产代码不得形成环。

### 4.4 四条主流程

#### 4.4.1 编译/构建流程

```
LoadUnits(entry)
  → xfront.ParseUnit（逐文件）
  → 合并编译单元（依赖优先、后序确定）
  → sema.Analyze（三遍 + 策略）
  → codegen.EmitC（单翻译单元 C 文本）
  → 写 <out>.c
  → cc -std=c11 -O2 -I <runtime> -o <out> <cfile> <runtime C sources...> [LinkArgs]
  → <out>
```

要点：

- 多文件加载器 `LoadUnits` 负责 import 闭包、环检测、重复导入去重、包一致性检查；
- `sema.Analyze` 的诊断全部在 codegen 之前返回；codegen 不新增语义诊断段位；
- `codegen.BuildWithOptions` 是端到端入口；`Options.LinkArgs` 只由调用方生成，构建侧保证顺序；
- C 编译清单固定顺序（`impl/internal/codegen/build.go:22`）：`rt.c`、`rt_gc.c`、`rt_policy.c`、`rt_weak.c`、`xrt_abi.c`、`rt_std_runtime.c`、`rt_std_text.c`、`rt_std_sys.c`；
- 当前实现直接把运行时 C 源与生成 C 一起交给 `cc`，不依赖预编译静态库缓存。

#### 4.4.2 运行流程

```
xnull run file.x
  → runFile 扫描 --interp
  → 默认 runCompiled：临时目录构建 → 启动子进程 → 透传 stdout/stderr/退出码
  → --interp：LoadUnits → sema → interp.Run（同一 AST）
```

退出码：

| 码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 1 | 工具链语法/语义/构建失败；程序自身返回 1 也表现为 1 |
| 2 | 用法错误、文件不可读、运行时目录找不到 |
| 其他 | 程序自身 `main` 的返回值透传（`run` 子进程路径） |
| 130 | 工具链被 SIGINT/SIGTERM 中断 |
| 134 | 程序 `throw fatal` / 运行时 hard fatal |

#### 4.4.3 FFI 流程

```
bindings/**/*.xfb
  → ffi.Load：词法/语法/合同校验
  → Registry：入口、布局、句柄、错误映射、阻塞分类
  → codegen/ffi.EmitSupport：布局结构、canary、错误分类、包装函数
  → 调用点 xn_ffi_<entry>
  → 原生符号
```

要点：

- `.x` 文法零改动：FFI 声明只在 `.xfb`；
- 每个入口必须声明 `@ffiEntry`、逐参数 `@lease`、`@blocking`；
- `String` 只能借出，`Bytes` 可借出/移交/归还，`Result`/容器/闭包等不跨界；
- 未知错误码一律归 `Internal`，绝不当 `Ok`；
- 生成代码只 include `xrt.h`，不触达内部 `rt_*`。

#### 4.4.4 维护工具流程

```
xnull dev check  [根]  → 规范守门：头部/待定词/§ 引用/二进制/EN 快照
xnull dev ledger [根]  → 从 S1—S8 抽取锚点，连接 status.tsv，生成台账
xnull dev res <dir> <out.c> → 资源根 → 只读 C 资源表
```

这些工具不属于语言用户稳定 CLI 面；但 B4 加严后同样必须由 XNull 重写。

---

## 5. 组件设计（系统级）

### 5.1 组件清单

| ID | 组件 | 目录 | 职责 | 当前状态 |
| --- | --- | --- | --- | --- |
| C1 | CLI | `impl/cmd/xnull`、`impl/internal/cli` | 命令分派、参数、退出码、run/build/policy/dev | 部分：文件模式已通；工程模式多数子命令未实现 |
| C2 | 前端 | `impl/internal/xfront` | 词法、语法、AST、打印、编译单元 | 语法层四级齐备；S2 类型声明解析已接入 |
| C3 | 语义 | `impl/internal/sema` | 名称解析、确定赋值、类型检查、类型声明检查、策略判定、错误/清理规则 | 多遍管线已接入；部分类型/对象面显式标注 |
| C4 | 代码生成 | `impl/internal/codegen` | AST → C、类/容器/字符串/Result、多文件、构建 | 子集覆盖；未支持构造显式报错 |
| C5 | FFI | `impl/internal/codegen/ffi` | `.xfb` 解析、合同校验、注册表、包装生成、链接参数 | 校验与生成完成；trampoline 预留 |
| C6 | 解释器 | `impl/internal/interp` | tree-walking 解释执行、调试路径、对照 oracle | 覆盖主要语法与对象/容器面 |
| C7 | 运行时 | `impl/runtime` | ARC/GC/策略/弱表/隔离区/句柄/字符串/std 原语 | M3 合同已落地；并发域未开工 |
| C8 | XDK | `impl/lib/xdk`、`bindings/xdk` | 公开 API 源码层、绑定声明、C 原语 | 种子 + C 层部分完成；完整 API 面未齐 |
| C9 | 工程配置 | `impl/internal/xpd` | XPD 词法/文法/AST | 解析器完成；继承/依赖/锁/生命周期未接入 |
| C10 | 维护工具 | `impl/internal/devtool` | check/ledger/res | 完成；B4 后需迁 XNull |
| C11 | 诊断/退出码 | `impl/internal/diag`、`exitcode` | 统一诊断渲染、退出码常量 | 完成 |
| C12 | 验证 | 测试文件、`ci/`、`evidence/` | 单元、C 套件、黄金、双路径、证据 | Go/C 测试在跑；CI 04—09 仍为 SKIP 桩 |

### 5.2 关键组件边界

| 边界 | 允许的跨边界数据 | 禁止 |
| --- | --- | --- |
| xfront → sema | AST 值类型、位置、诊断 | sema 反改 AST；sema 依赖 codegen |
| sema → codegen | 已检查 AST + 策略结果 | codegen 重新做语义判定；codegen 新增语义诊断 |
| codegen → 运行时 | 生成 C 文本、`xrt_*` 调用、类型描述符 | 生成代码直接操作 `rt_*` 内部符号 |
| codegen → ffi | `Registry`、`EmitCall`/`EmitSupport` 片段 | ffi 反向依赖 codegen |
| 程序 ↔ 原生库 | 值、句柄、缓冲区（`.xfb` 三形态） | `rt_object*` 跨语言地址；`Result`/容器/闭包直传 |
| 用户代码 ↔ XDK | XDK 公开 API | 绕过包层直接调用 C 原语 |
| 工具链 ↔ 工程 | `xnull.project`、`xnull.lock`、资源目录 | 环境变量隐式改变构建选项（`XNULL_REPO` 例外） |

---

## 6. 关键设计决策

### D-01 借力先行，自举收口

**决策**：当前编译器、CLI、维护工具用 Go；运行时用 C；后端用系统 `cc`。B0—B4 五道门逐步把前端、代码生成器、CLI、devtool 迁到 XNull，B4 后删除 Go 实现。

**理由**：Go 提供快速迭代、单文件静态产物、跨平台交叉编译；C 运行时承载 ARC/GC 硬语义；XNull 自举保证工具链自洽。

**后果**：

- 短期存在“Go 工具链 + C 运行时”双语言结构；
- B2 前不得对外宣称“已自举/自举中”；
- B4 的验收不是“Go 版还能跑”，而是“仓库里没有 Go 也能跑”。

**拒绝的替代**：Rust/Zig 重写编译器；永远保留双实现；把自举当性能优化宣传。

### D-02 规范优先与一致性台账

**决策**：S1—S8 是语义唯一来源；实现层用 `status.tsv` + 台账记录“规范锚点 × 证据”；无证据 = 未实现。

**理由**：避免“代码即规范”的漂移；让未实现面可见、可追踪；支撑自举前语义冻结。

**后果**：实现未覆盖时必须在台账标注归属，不得用“部分完成”申请过门；测试文件是状态行的证据。

### D-03 编译默认，解释器降级

**决策**：`xnull run` 默认编译路径；`--interp` 强制解释器；解释器与 codegen 共享 xfront AST 与 sema 结果。

**理由**：编译路径是正式交付面；解释器提供快速调试与行为对照；共享 AST 避免两套语义漂移。

**后果**：两条路径的输出必须逐字节一致；解释器不是运行时，不模拟 ARC 时序。

### D-04 确定性 DET-01

**决策**：同一源程序 + 同一工具链版本 → 相同诊断顺序、相同 C 文本、相同程序输出。凡 map 参与输出或影响执行顺序，键必须排序；临时变量编号按遍历顺序；注册表/台账/资源表按名称排序。

**理由**：可复现构建、可差分验收、自举不动点（B4 逐字节一致）都依赖确定性。

**后果**：禁止依赖 Go map 遍历顺序、文件系统枚举顺序、声明顺序以外的隐式顺序；新增集合输出必须显式排序并有用例。

### D-05 编译器判定内存策略，运行时执行

**决策**：源码不表达引用强度。`sema` 按 S2 §15.1 判定表输出 `Strategy`；C 运行时 `rt_decide_policy` 执行同一张表；ARC/GC 混合图由运行时维护。

**理由**：保持“源码 + 规范决定一切”；把复杂内存策略从用户手里收回编译器；运行时用 C 承载硬时序。

**后果**：

- `Strategy` 字段自 M2.5.2 冻结，C 侧逐字段映射；
- `escape` 字段为对象级逃逸预留，当前类型级为 `"n/a"`；
- 全 ARC 环由编译器分析改判；至少一个 GC 节点的环由 GC 回收。

### D-06 错误是值，fatal 是边界

**决策**：可恢复失败走 `Result<T,E>` + `try` + `defer`/`errdefer`；`throw fatal`、越界、空引用、复活检测等走 `rt_fatal`/`exit(134)`，不展开 defer。

**理由**：无隐式异常传播；错误处理可见、可类型检查；fatal 路径保持进程终止语义，避免半恢复状态。

**后果**：服务端高可用需要按进程边界设计隔离；`Result` 表示由 codegen 内联，不进运行时；FFI 未知错误码不得降级为 `Ok`。

### D-07 FFI 合同先行

**决策**：FFI 不新增语言关键字；绑定声明放 `.xfb`；跨边界只允许值、句柄、缓冲区；每个入口必须有租约、阻塞分类、错误码映射；生成代码只经 `xrt.h`。

**理由**：把“能否调用”变成机械可校验的合同；防止任意原生函数直调虚增语言能力；稳定 ABI 支撑自举与第三方绑定。

**后果**：`.xfb` 校验器是构建门槛；未覆盖形态记入 `Problems` 并使构建失败；trampoline 依赖调度器切片。

### D-08 XDK 三层结构

**决策**：XDK 公开 API 用 XNull 源码写（`impl/lib/xdk/*.x`）；绑定声明放 `bindings/xdk/*.xfb`；C 原语放 `impl/runtime/rt_std_*.c`，经 `xrt_*` 与 `.xfb` 暴露。

**理由**：API 约束（`Result`、`Context`、`withLock`）只有 XNull 类型系统能表达；绑定层复用 FFI 校验；C 层只做 OS/内核原语；为自举提供第一块真实 XNull 代码。

**后果**：XDK 不是编译器内置；解释器路径需要 Go 桥接同名函数；完整 API 面依赖 P-09 外部调用钩子与类/枚举面稳定。

### D-09 显式不支持，不静默降级

**决策**：codegen、sema、ffi、xpd 遇到未覆盖构造原则上报错或记录问题；不得生成“看起来能跑”的降级代码。已发现的例外必须登记为风险并限期补齐。

**理由**：静默降级会破坏“源码 + 规范决定行为”的公理；也会让台账与双路径对照失真。

**后果**：当前可用子集小于规范全集；用户会看到明确诊断；实现进度可按错误分支清点。已知例外：codegen 插值串表达式段（R-11 / O-01）。

### D-10 可复现构建与离线纪律

**决策**：构建不读网络；依赖只认清单与约定目录；输出排序；缓存键包含源内容哈希、旗标、工具链版本（设计目标）；产物写目标目录。

**理由**：可复现、可审计、可自举；避免“构建成功依赖本机环境”。

**后果**：当前 `BuildWithOptions` 直接编译运行时源，缓存设计尚未落地；XPD 生命周期接入后需补齐锁文件与缓存键。

### D-11 工程配置用 XPD

**决策**：`xnull.project` 使用自研 XPD 段落树；GAV 坐标每模块必写且不从 parent 继承；生命周期五阶段；插件受控；资源目录与打包规则由 S8 §5.6 规定。

**理由**：结构语法强、无隐式类型、可机械校验；避免 YAML/TOML 的歧义与脚本化配置。

**后果**：当前只完成 XPD 解析器；继承展开、依赖仲裁、锁、生命周期、插件执行尚未接入 CLI。

### D-12 证据是交付物

**决策**：每门/每卡交付四件套：代码 + 可复现命令、逐字节对照/差分、SHA-256、日志 + 回执；无证据 = 未完成。

**理由**：自举与运行时硬语义无法靠口头保证；证据让验收可重放。

**后果**：测试、CI、证据目录是工程结构的一部分，不是附属品。

---

## 7. 运行视图

### 7.1 工具链进程生命周期

1. `cmd/xnull/main.go` 注册 SIGINT/SIGTERM 处理器；收到信号打印 `xnull: 已中断` 并以 130 退出。
2. `cli.Run` 解析命令与旗标；未知命令/旗标返回用法诊断（CLI-001/CLI-002）。
3. `run`/`build` 进入文件模式或工程模式；文件模式要求 `.x` 后缀。
4. 诊断写 stderr；正常输出写 stdout；退出码由 `exitcode` 常量统一。
5. 子进程运行（`runCompiled`）时透传 stdout/stderr 与退出码；工具链自身不吞程序输出。

### 7.2 编译期时序

```
[读取]  LoadUnits
          ├─ 入口文件不存在 → RES-106 / 用法错误
          ├─ import 环 → RES-108
          ├─ 跨包 → RES-109
          └─ 子文件缺 package → RES-110
[解析]  xfront.ParseUnit
          ├─ 词法诊断 LEX-101—106
          └─ 语法诊断 SYN-101—111
[语义]  sema.Analyze
          ├─ 名称解析 RES-101/102（+ 导入族 RES-103—107）
          ├─ 确定赋值 DA-101—103
          ├─ 类型检查 TY-101/103/104/105
          ├─ 类型声明 TY-201—207
          └─ 错误/清理 ERR-201—206
[策略]  ComputeStrategies（按声明名排序）
[生成]  EmitC
          ├─ 收集 Result/容器/类实例化
          ├─ 两遍生成（第一遍收集，第二遍稳定输出）
          └─ 未支持构造 → 显式错误
[编译]  cc -std=c11 -O2 -I <runtime> ...
[链接]  全部运行时 C 源 + LinkArgs（目标文件之后）
```

失败点与退出码：

| 阶段 | 失败表现 | 退出码 |
| --- | --- | --- |
| 读取/用法 | 文件不可读、找不到运行时、未知旗标 | 2 |
| 解析/语义 | 诊断输出 | 1 |
| 代码生成 | 显式错误 | 1 |
| C 编译/链接 | cc 错误 | 1 |
| 程序正常返回 | `main` 返回值透传 | 用户值（常见 0/1） |
| 程序 fatal | 进程终止 | 134 |

### 7.3 生成程序生命周期

```c
int main(void) {
    int64_t xn_r = xn_main();      /* 或 void main → 0 */
    rt_quarantine_flush();          /* 回收会合：释放隔离区 */
    return (int)xn_r;               /* Int 退出码直通 */
}
```

- 入口垫片由 codegen 生成；用户 `main` 被重命名为 `xn_main`；
- `throw fatal` 走 `xn_throw`：打印 `fatal: ...` 后 `exit(134)`，不展开 defer；
- 运行时 `rt_fatal` 默认打印 `xnull runtime fatal: ...` 后 `abort`；
- 字符串/容器/类对象在作用域退出按插入的 release/free 序列清理；
- `rt_quarantine_flush` 在 `main` 返回前释放隔离区，保证终结与回收分离。

### 7.4 内存生命周期

```
分配：rt_alloc / rt_arc_new / rt_gc_new → 计数 1
持有：rt_retain（+1）
释放：rt_release（-1）
     └─ 到 0：
         置 terminated（防复活/双释放）
         → 清弱槽位
         → 从 GC 扫描链注销
         → 调用 type->deinit
         → 入隔离区
         → 下次 safepoint/flush 释放内存
GC：标记（全局根 + ARC 扫描链）→ 清扫（死亡 GC 对象 release 其 ARC 引用）→ 释放
```

### 7.5 FFI 调用生命周期

```
调用点
  → 入参编组（标量直传 / String 借出 / Bytes canary 拷贝 / 数组指针+长度 / 句柄取原生指针）
  → 原生函数
  → 返回编组 + 错误码映射
  → Result 构造（codegen 调用点消费）
  → 借出缓冲区 canary 校验；句柄 close 状态登记
```

### 7.6 工程生命周期（S8 目标态）

| 阶段 | 动作 | 当前实现 |
| --- | --- | --- |
| validate | 清单语法/语义、继承展开、变量替换、入口、锁一致性 | 仅 XPD 解析器；其余未接入 |
| compile | 编译 `src/main/x` | 文件模式已通；工程目录模式未接入 |
| test | 运行 `src/test/x` | 未接入 |
| package | 产出 `target/<artifactId>-<version>.<ext>` + `.xmeta` | 未接入 |
| install | 安装到本地仓库 | 未接入 |

---

## 8. 数据设计

### 8.1 数据实体

| 实体 | 形态 | 生产者 | 消费者 | 确定性要求 |
| --- | --- | --- | --- | --- |
| 源文件 `.x` | UTF-8 文本 | 用户/XDK/自举 | xfront | 无 |
| AST | Go 结构体树 | xfront | sema/codegen/interp/printer | 遍历顺序固定 |
| 诊断 | `diag.Diagnostic` | xfront/sema/ffi/xpd/cli | CLI/测试 | 按文件/行/列/码排序 |
| Strategy | JSON/Go 结构体 | sema | 运行时/`policy` 命令 | 按 `decl` 排序 |
| 生成 C | C11 文本 | codegen | cc/审计 | 逐字节确定 |
| `.xfb` 注册表 | Go 结构体 | ffi.Load | codegen | 按名称排序 |
| XPD AST | Go 结构体树 | xpd | 后续工程层 | 条目顺序保持源码序 |
| 资源表 | C 源 | devtool.res | 运行时 | 按资源名升序 |
| status.tsv | TSV | 维护者 | devtool.ledger | 行序固定 |
| 证据 | Markdown/日志/SHA | 开发/QA | 验收 | 可复现 |

### 8.2 命名与 mangle

| 对象 | 规则 | 示例 |
| --- | --- | --- |
| 顶层函数 | `xn_<name>` | `xn_main` |
| 函数参数 | `xn_p_<name>` | `xn_p_n` |
| 类结构 | `xn_Cls_<Name>` | `xn_Cls_Node` |
| 类方法 | `xn_Cls_<Name>_<method>` | `xn_Cls_Node_next` |
| 类型描述符 | `RT_TYPE_XN_<Name>` | `RT_TYPE_XN_Node` |
| Result | `xn_Result_<T>_<E>` | `xn_Result_Int_String` |
| 数组 | `xn_arr_<mangle>` | `xn_arr_i` |
| Set | `xn_set_<mangle>` | `xn_set_s` |
| Map | `xn_map_<k>_<v>` | `xn_map_s_i` |
| 临时变量 | `xn_tmp<N>` | `xn_tmp12` |
| FFI 包装 | `xn_ffi_<entry>` | `xn_ffi_ffiSqliteOpen` |

mangle 规则：`int64_t → i`、`int → b`、`rt_string * → s`、`xn_Cls_X * → o_X`。规则是纯函数，保证同一类型同一后缀。

### 8.3 确定性规则

1. 所有 map 参与输出前必须转 slice 并排序；禁止直接 `range map` 写输出。
2. `ComputeStrategies`、FFI 注册表、容器实例化、Result 实例化、资源表均按名称排序。
3. 诊断按 `File`、`Line`、`Col`、`Code` 稳定排序。
4. 多文件合并按依赖优先后序；同一 import 列表按源码书写顺序。
5. 生成 C 的临时变量编号在每次生成前重置；第一遍收集、第二遍正式输出。
6. 测试断言“两次运行逐字节一致”，而不是只断言“内容相等”。

---

## 9. 接口设计（系统级）

### 9.1 CLI 合同

| 命令 | 作用 | 当前状态 |
| --- | --- | --- |
| `xnull run <file.x>` | 编译并运行（默认） | 文件模式可用 |
| `xnull run --interp <file.x>` | 解释执行（调试） | 可用 |
| `xnull build <file.x> [-o out] [--runtime dir] [-l lib] [-L dir]` | 编译为可执行文件 | 文件模式可用 |
| `xnull policy <file.x>` | 输出内存策略判定 JSON | 可用 |
| `xnull dev check [根]` | 规范守门 | 可用 |
| `xnull dev ledger [根]` | 生成台账 | 可用 |
| `xnull dev res <dir> <out.c>` | 生成资源表 | 可用 |
| `xnull test` / `xnull lock` / `xnull fmt` | 工程生命周期/锁/格式化 | 未实现（清单模式） |

旗标（当前已注册）：`--update-lock`、`--skip`、`--profile`、`--check`、`--emit`、`--offline`、`--verbose`、`--interp`、`--runtime`、`-o`。未知长旗标返回 CLI-002。

### 9.2 诊断合同

格式：

```
file:line:col: error[CODE]: message
  <行号> | <源码行>
        |   ^^^ hint
```

段位：

| 段位 | 归属 |
| --- | --- |
| LEX-101—106 | 词法 |
| SYN-101—111 | 语法 |
| RES-101—110 | 名称解析/导入/多文件 |
| DA-101—103 | 确定赋值 |
| TY-101/103/104/105、TY-201—207 | 类型检查/类型声明 |
| ERR-201—206 | Result/清理规则 |
| FFI-100—111 | 绑定声明与合同 |
| XPD-0xx—8xx | 工程配置 |
| CLI-001—003、CLI-901 | 命令行 |

### 9.3 运行时 ABI 合同

- **`rt.h` 是内部头**：分配头、ARC/GC、弱表、隔离区、致命错误；不随 SDK 分发。
- **`xrt.h` 是唯一对外稳定 ABI**：`xrt_alloc/retain/release/refcount`、弱表、根登记、安全点、任务根、字符串、Bytes、句柄、`xrt_fatal`、`xrt_runtime_init`。
- 符号与签名一经定稿冻结；变更走主版本（S7 §6.1、附录 B）。
- 生成代码与绑定代码只 include `xrt.h`；`rt_*` 不对外。

### 9.4 FFI 合同

- `.xfb` 声明文件；每个入口：`@ffiEntry(cName=…)` + `@lease(...)` + `@blocking(...)`；`@errorCode` 可选。
- 允许跨界：标量、`String`（借出）、`Bytes`、标量/`layout(c)` 数组、`layout(c)` 结构、`Handle`。
- 禁止跨界：`Result`、可选、引用对象、闭包、容器、元组、`String` 移交。
- 错误码：返回 0 成功；非 0 映射为 `ErrorKind`；未知码 → `Internal`。
- 句柄：`xrt_handle`，close 显式且幂等；deinit 不自动 close；已关闭句柄再取原生指针返回 NULL。

### 9.5 XDK 合同

- 8 包：`errors`、`tasks`、`sync`、`runtime`、`collections`、`text`、`sys`、`net`。
- 依赖方向单向：`sys → errors → runtime → text → collections`；`tasks/sync` 只依赖 `errors/runtime`。
- 可失败 API 返回 `Result`；持资源类型必须有 `close()`；可阻塞 API 首参 `Context`；公开 API 有稳定性标注。
- 资源读取五 API：`resourceExists`、`readResource`、`readResourceText`、`listResources`、`resourceSize`；只读、无句柄、不回退文件系统。

### 9.6 工程配置合同

- 清单：`xnull.project`，XPD 段落树；根块唯一；GAV 每模块必写。
- 锁：`xnull.lock`；`--update-lock` 是唯一重生成入口。
- 生命周期：`validate → compile → test → package → install`。
- 插件：精确版本、固定阶段、显式 goal、只写 `target/`、禁网、禁环境读取。
- 资源：`src/main/resources` 缺省根；制品内 `resources/` 前缀；冲突失败。
- 配置：`application.properties`，五层覆盖；未知键/缺必需键/类型失败即启动失败。

---

## 10. 质量属性与验证

### 10.1 质量属性

| 属性 | 定义 | 当前保障 |
| --- | --- | --- |
| 正确性 | 实现符合规范语义 | sema 用例、双路径、C 运行时套件、台账 |
| 确定性 | 同一输入同一输出 | DET-01 测试、排序规则、C 产物比对 |
| 可诊断性 | 错误有位置、码、提示 | 统一 `diag` 渲染；段位表 |
| 可复现性 | 干净 clone 可构建；产物可核对 | 构建脚本、证据、SHA-256 |
| 可移植性 | 工具链跨平台；运行时 POSIX 优先 | Go 交叉编译、C11、`build_rt.sh` |
| 安全性 | 跨界不越权、不越界 | FFI 合同、canary、句柄状态、`xrt.h` 边界 |
| 可维护性 | 模块边界清晰、文档可追溯 | 单向依赖、设计文档、台账 |
| 性能 | 无明显退化；不虚构排名 | 暂以算法与分配路径为主，未做基准承诺 |

### 10.2 验证金字塔

```
                   ┌─────────────────────┐
                   │ 证据/门禁/发布验收    │  evidence/、回执、SHA-256
                   ├─────────────────────┤
                   │ 双路径/黄金/差分      │  examples 双路径、C 产物逐字节
                   ├─────────────────────┤
                   │ 集成测试              │  CLI build/run、FFI 端到端
                   ├─────────────────────┤
                   │ 单元测试              │  Go 包测试（34 文件/197 Test）
                   ├─────────────────────┤
                   │ C 运行时套件          │  test_rt/test_gc/test_hard/test_abi/test_std/test_res
                   └─────────────────────┘
```

### 10.3 测试与命令

```bash
cd impl
gofmt -l .
go vet ./...
go test ./... -count=1
sh runtime/build_rt.sh
```

CI 入口：

```bash
bash ci/run.sh
bash ci/run.sh --list
bash ci/run.sh --only 02
```

当前 CI 状态：

| 步骤 | 内容 | 状态 |
| --- | --- | --- |
| 01 | gofmt + vet | 真实现 |
| 02 | go test | 真实现 |
| 03 | C 运行时构建 | 真实现 |
| 04 | 示例双路径 | SKIP 桩 |
| 05 | check_specs 守门（六检标签） | SKIP 桩 |
| 06 | 台账再生成 diff | SKIP 桩 |
| 07 | 泄漏扫描 | SKIP 桩 |
| 08 | 产物与 sha | SKIP 桩 |
| 09 | 汇总 JSON | SKIP 桩 |
| 10 | 文件名扫描（禁旧扩展名） | 真实现 |

### 10.4 一致性台账

- 台账从 S1—S8 母本抽取锚点，连接 `impl/docs/conformance/status.tsv`；
- `status.tsv` 是“有证据子集”，不是规范条目全集；
- 未登记行 = 未实现；
- 台账与 status.tsv 的口径差异由 `impl/docs/conformance/ledger-restructure.md` 说明；
- 任何状态变更必须有测试文件或明确归属，不接受口头翻绿。

### 10.5 当前证据基线（编制时点）

- Go 测试文件 34 个，`Test*` 函数 197 个；
- C 测试套件 6 个：`test_rt.c`、`test_gc.c`、`test_hard.c`、`test_abi.c`、`test_std.c`、`test_res.c`；
- status.tsv 当前 35 条证据行（另有 1 行表头注释）；PASS/部分/未实现以文件为准；
- 示例 10 个（含 `multi/main.x`、`lexer-seed.x`、`parser-seed.x`、`ast-seed.x`、`objlist.x`）；
- 具体数字会随开发变化，本文只记录基线。

---

## 11. 构建、部署与发布

### 11.1 构建前提

| 项 | 要求 |
| --- | --- |
| Go | 1.27+（`impl/go.mod` 锁定 `go 1.27`） |
| C 编译器 | 支持 C11；默认 `cc`，可经 `CC` 环境变量覆盖（设计目标） |
| 平台 | macOS/Linux 优先；Windows 走运行时实现分支 |
| 网络 | 构建不依赖网络 |
| 运行时源码 | `impl/runtime`，可用 `--runtime` 或 `XNULL_RUNTIME` 指定 |

### 11.2 构建命令

```bash
cd impl
go build -o xnull ./cmd/xnull

./xnull run examples/hello.x
./xnull build examples/hello.x -o hello
./hello
```

### 11.3 产物

| 产物 | 位置 | 说明 |
| --- | --- | --- |
| 工具链 | `impl/xnull` | Go 构建产物（B4 前） |
| 生成 C | `<out>.c` | codegen 输出 |
| 可执行文件 | `<out>` | 单文件模式 |
| 运行时测试 | `/tmp/xnull_test_*` | `build_rt.sh` |
| 资源表 | 指定 `.c` | `dev res` |
| 证据 | `evidence/<卡片>/` | 日志、差分、SHA-256 |
| 回执 | `收件箱/回执箱/<司>/` | 交付留痕 |

### 11.4 发布纪律

- 公开空间只放用户需要的内容；内部治理词汇、任务编号、角色名不得泄漏；
- 规范母本变更后，公开前完成 EN 同步（`dev check` 第 5 检）；
- 发布前跑 `dev check`、`gofmt`、`vet`、`go test`、`build_rt.sh`；
- 里程碑发布以门禁证据为准，不以日期为准。

---

## 12. 演进路线与自举

### 12.1 已完成的阶段（按任务链）

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| M0 | CLI 骨架、前端四级、解释器、三示例 | 完成 |
| M1 | 语法层收口 | 完成（门通过） |
| M2 | 语义分析（名称/确定赋值/类型） | 完成（门通过） |
| M2.5 | 类型声明解析与策略判定前置 | 完成 |
| M3 | C 运行时（ARC/策略/GC/硬语义） | 完成（门通过） |
| M4 | 端到端编译（C 后端、build、解释器降级） | 完成（门通过） |
| M4.4 | 类与容器代码生成 | 完成 |
| M4.5 | FFI（声明/校验/包装/句柄/pin） | 大部分完成；trampoline 预留 |
| M4.6 | XDK（C 层 + 种子） | 部分完成 |
| M5.1 | 自举子集重写（词法器/AST/对象容器） | 进行中 |
| M5.2 | 多文件编译单元 | 前置完成 |

### 12.2 自举五道门

| 门 | 内容 | 完成定义 | 架构影响 |
| --- | --- | --- | --- |
| B0 地面准备 | P-09/P-10、跨包 import、类字段初值、容器/字符串成员 | XNull 程序能“读文件 → 解析 → 写文件”，`xnull build` 能编译运行 | 补齐自举硬依赖；不改语言语义 |
| B1 首件工具 | XNull 写 `xnfmt` | 全仓库 `.x` 输出与 Go 版逐字节一致；进入正式发布物 | 第一个真实 XNull 工具 |
| B2 前端 | XNull 重写 lexer + parser → AST | AST 与 Go 版逐字节一致；解释器/编译器改用新前端 | 前端替换；运行时/ABI 不动 |
| B3 全量编译器 | XNull 写完整 `xnullc` | C 产物文本一致；9 示例双路径一致 | 代码生成器替换 |
| B4 不动点 | `Go → xn-s1 → xn-s2 → xn-s3` | `xn-s2` 与 `xn-s3` 逐字节一致；删 Go 后全量测试绿 | Go 清零；CLI/devtool 也迁 XNull |

### 12.3 自举后的目标结构

```
上一版 XNull 编译器（二进制）
  → 读取 XNull 工具链源码（.x）
  → 生成 C
  → 系统 cc + C 运行时
  → 新一版 XNull 编译器（二进制）
  → 不动点：xn-s2 == xn-s3
```

长期保留：C 运行时、`xrt.h` ABI、系统 `cc`、平台 ABI。

不保留：Go 版编译器、Go 版 CLI、Go 版 devtool、Go 构建链。

### 12.4 当前状态声明

- B0 **进行中**；具体卡片状态以 `收件箱/任务看板-M6-v1.0.0.md` 与回执为准；
- B1—B4 **未开始**；上一门未过不得开工；
- 对外不得使用“已自举/自举中”口径；
- 本设计文档的架构描述不构成门禁通过证据。

---

## 13. 风险与开放问题

| 编号 | 风险 | 影响 | 应对 |
| --- | --- | --- | --- |
| R-01 | Go 工具链依赖与 B4 清零 | 自举失败、构建链不独立 | 按 B0—B4 门推进；Go 代码只做脚手架；B4 硬判据 |
| R-02 | codegen 子集不足 | 自举代码无法表达 | B0 补齐 P-09/P-10/跨包/字段初值/容器成员；未支持显式报错 |
| R-03 | 运行时单线程与 GC 并发 | 任务/同步/取消无法完整验收 | 调度器切片；XDK-04/05 标注“部分” |
| R-04 | FFI trampoline 预留 | 回调面不完整 | 依赖调度器栈 pin/根登记；保持显式 `ErrTrampolineReserved` |
| R-05 | XPD 生命周期未接入 | 工程模式不可用 | 按 S8 五阶段逐步接入；锁/插件/资源后置 |
| R-06 | CI 04—09 为 SKIP 桩 | 质量门不完整 | 逐步实装；不得把 SKIP 当 PASS |
| R-07 | 规范与实现漂移 | 语义不一致 | 台账 + `dev check` + 证据；变更先改母本 |
| R-08 | 平台差异（Windows/POSIX） | 运行时系统原语不可用 | 接口不变，实现分支；首批 POSIX |
| R-09 | 性能未验证 | 对外表述风险 | 只做可验证的工程目标；不做排名承诺 |
| R-10 | 文档与代码基线漂移 | 设计文档失真 | 每次架构变更同步更新本文与详细设计；以代码为基线回写 |
| R-11 | codegen 插值串表达式段未生成 | 含表达式插值可能被静默丢弃静态文本 | 按“显式失败”原则补生成或补诊断；列入详细设计 O-01 |

---

## 14. 需求—模块—证据追踪矩阵

| 规范 | 主要模块 | 关键台账锚点 | 当前证据入口 |
| --- | --- | --- | --- |
| S1 基础语法 | xfront、interp、codegen | LEX-01、STMT-01、EXPR-01、CTRL-01、TYPE-01/02、TUPLE-01、PKG-01、ENTRY-01、DET-01、BLD-01 | `internal/xfront/*_test.go`、`internal/interp/*_test.go`、`internal/sema/*_test.go` |
| S2 对象编程 | xfront/types、sema/typedecl、sema/policy、codegen/classes | INH-01、DISP-01、STRUCT-01、PROTO-01、ENUM-01、INT-01、ANN-01、FIELD-01、MEM-01/02、BND-01—15 | `internal/sema/typedecl_test.go`、`policy_test.go`、`internal/codegen/classes*.go` |
| S3 内存管理 | sema/policy、runtime/rt*.c | MEM-01—13、DET-01 | `sema/policy_test.go`、`runtime/test_rt.c`、`test_gc.c`、`test_hard.c` |
| S4 错误处理 | interp、sema/error、codegen | ERR-01、KIND-01、OBS-01—03、CANCEL-01/02、CLEAN-01、BOUND-01—03 | `interp/hard_test.go`、`sema/err01_test.go` |
| S5 任务与并发 | XDK tasks/sync、runtime（未来） | TASK-01—04、SYNC-01—03、SCHED-01、BLOCK-01 | 尚未开工；设计见 `xdk-design.md` |
| S6 标准库 XDK | `impl/lib/xdk`、`bindings/xdk`、`rt_std_*` | XDK-01—10 | `runtime/test_std.c`、`codegen/ffi/xdk_test.go`、`xdk_seed_test.go` |
| S7 FFI | codegen/ffi、runtime/xrt_abi | FFI-01—07 | `codegen/ffi/*_test.go`、`runtime/test_abi.c` |
| S8 工程配置 | xpd、cli、devtool | PROJ-01—11 | `xpd/parser_test.go`、`cli/*_test.go`、`devtool/*_test.go` |

说明：台账锚点是规范母本的全集；`status.tsv` 只登记有证据的行。未登记不等于规范不存在，等于“当前无实现证据”。

---

## 15. 附录

### 15.1 术语

| 术语 | 含义 |
| --- | --- |
| S1—S8 | 八部分规范母本；S1 基础语法、S2 对象编程、S3 内存管理、S4 错误处理、S5 运行时任务与并发、S6 标准库 XDK、S7 FFI、S8 工程配置 |
| DET-01 | 确定性验收：同一输入同一输出；map 参与输出必须排序 |
| ARC/GC | 引用计数 / 标记—清扫；由编译器判定、运行时执行 |
| Strategy | sema 输出的内存策略判定结果，字段与 `rt_policy_input` 一一映射 |
| 双路径 | 编译路径与 `--interp` 解释路径；输出与退出码必须一致 |
| 台账 | 规范锚点 × 实现证据的状态表 |
| XPD | XNull Project Description，工程清单方言 |
| XDK | XNull Development Kit，标准库 8 包 |
| `.xfb` | FFI 绑定声明文件 |
| B0—B4 | 自举五道门 |
| `xn-s1/2/3` | 自举阶段编译器产物 |
| Oracle | 作为对照基准的 Go 版实现 |

### 15.2 参考文档

- `XNull解决方案-第1部分-基础语法-v3.4.0.md`
- `XNull解决方案-第2部分-对象编程-v3.4.0.md`
- `XNull解决方案-第3部分-内存管理-v3.1.0.md`
- `XNull解决方案-第4部分-错误处理-v1.1.0.md`
- `XNull解决方案-第5部分-运行时任务与并发-v1.1.0.md`
- `XNull解决方案-第6部分-标准库XDK-v1.1.0.md`
- `XNull解决方案-第7部分-FFI-v1.0.0.md`
- `XNull解决方案-第8部分-工程配置-v5.2.0.md`
- `XNull规范索引-v1.0.0.md`
- `XNull一致性用例台账-v1.0.0.md`
- `XNull开发任务规划.md`
- `死命令.md`
- `impl/README.md`
- `impl/docs/m4-codegen-design.md`
- `impl/docs/runtime-contract.md`
- `impl/docs/ffi-design.md`
- `impl/docs/ffi-contract.md`
- `impl/docs/xdk-design.md`
- `impl/docs/m2-sema-plan.md`
- `impl/docs/conformance/ledger-restructure.md`

### 15.3 状态快照（编制时点）

| 项 | 值 |
| --- | --- |
| 代码基线 | `ea6fdf3` |
| 工具链版本 | `0.1.0-dev` |
| 当前里程碑 | M5.1 / M6-B0 |
| B0 状态 | 进行中（以看板与回执为准） |
| Go 测试 | 34 文件 / 197 Test |
| C 测试 | 6 套件 |
| 示例 | 10 个 `.x` |
| 公开副本 | `xnull/` 工作副本；根目录为工作区 |
