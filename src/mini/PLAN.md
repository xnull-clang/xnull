# Mini Compiler Plan

目标：在 `src/mini/` 实现新的最小 XNull 编译器，逐场景接管旧编译器
`src/compiler/`；当新实现覆盖旧实现的全部能力时，作为一个稳定里程碑并迁移到src接管。

## 1. 基本原则

- 旧编译器冻结为 bootstrap / oracle；只允许修最小闭环必须的阻断，不重构。
- 新编译器独立实现完整流程：装载 → 词法 → 语法 → AST → 语义 → 脱糖 →
  C 代码生成 → 诊断。
- 运行时、XDK、绑定、CLI 输出合同与旧编译器共用，不维护第二套语义。
- 每个能力必须同时满足：新引擎单跑通过、旧引擎差分一致、失败负例可读。
- `auto` 只能在新引擎明确声明支持时接管，不能静默假装支持。

## 2. 引擎合同

命令行：

```text
mini --emit-c <entry.x> [-o <out.c>]
mini --check <entry.x>
mini --supports <entry.x>
```

退出码：

```text
0  成功 / 支持
1  源码诊断（带 file:line:col）
2  用法或环境错误
3  当前最小实现不支持（仅 --supports / auto 使用）
```

C 代码输出必须能被现有 `src/runtime/` 编译链接；诊断格式与旧工具链一致。

## 3. 完整流水线

```text
源文件
  → package / import 装载
  → 词法
  → 语法 AST
  → 名称解析
  → 类型检查
  → 脱糖（容器字面量、for-in、Result/try/defer 等）
  → C 代码生成
  → 运行时链接
  → 可执行文件 / 精确输出
```

评测同时覆盖：

- 正例：stdout、stderr、退出码。
- 负例：诊断位置、诊断码、退出码。
- 冷启动时间。
- 新旧引擎差分。
- 自举：新引擎编译自身。

## 4. 里程碑

### M0 引擎骨架

- `src/mini/` 源码骨架与构建脚本。
- `src/cli/xnull` 支持 `--engine=legacy|mini|auto`。
- `src/toolchain/xnull-build.sh` 接入新引擎。
- `--supports` 与 `auto` 回退协议。
- 差分测试脚本。

验收：`--engine=legacy` 行为不变；`--engine=mini` 在未实现能力时明确报不支持。

### M1 装载与词法

- 源文件读取、UTF-8 字节处理、行列计数。
- `package`、`import`、标识符、关键字、数字、字符串、字符、注释、运算符。
- 诊断：非法字符、未闭合字符串/注释、非法数字。

验收：token 流与旧编译器对最小源文件一致；负例带位置。

### M2 语法与 AST

- 顶层声明、函数、参数、局部声明、表达式、语句。
- 最小控制流：`if`、`while`、`return`、调用、赋值。
- AST 打印与旧引擎可比对。
- 语法错误恢复与位置。

验收：L0 `hello` 源文件解析通过；负例不崩溃。

### M3 语义与类型

- 作用域、名称解析、重复声明、未定义符号。
- `Int` / `String` / `Bool` / `Unit`。
- 调用参数数量/类型检查。
- 最小诊断码。

验收：L0 类型检查通过；错误函数名/参数类型负例可读。

### M4 最小代码生成

- C 预置运行时代码、字符串常量、整数字面量、`print`、函数调用、返回。
- `main` 入口与退出码。
- 链接既有 C runtime。

验收：`--engine=mini run src/examples/hello.x` 与旧引擎输出逐字节一致。

### M5 对象与控制流

- `class`、`final` 字段、构造器、方法、`self`、`new`。
- `if` / `while` / 赋值 / 复合赋值 / 比较 / 逻辑运算。
- 字符串拼接、字符串插值。

验收：L1 class 场景与旧引擎一致。

### M6 语言核心面

- `struct`、`enum`、`protocol`、继承/实现、接口派发。
- `Result` / `Ok` / `Err` / `try` / `defer` / `errdefer` / `throw`。
- `List` / `Map` / `Set`、字面量脱糖、`for-in` / `iterator()`。
- 泛型最小面、Lambda、闭包值、switch、标签 break/continue。

验收：语言核心正例、负例全部与旧引擎一致。

### M7 XDK 与 FFI

- `import xdk.<pkg>` 装载。
- `xdk.errors` / `xdk.runtime` / `xdk.meta`。
- 按场景追加 `xdk.text` / `xdk.sys`。
- `.xfb` 绑定、raw FFI、错误码映射。
- XDK 包依赖方向检查。

验收：L2—L6 场景全部通过；新旧引擎输出一致。

### M8 工具链能力

- `check`、`build`、`run`。
- 工程模式、资源表、`--json`、`--bootstrap`。
- 诊断格式、退出码、冷启动预算。
- 构建产物可复现。

验收：现有 CLI 场景全部由 mini 接管，必要时回退旧引擎。

### M9 自举与覆盖判定

- 用旧引擎编译 mini。
- 用 mini 编译 mini。
- 用 mini 编译全量最小场景。
- 新旧引擎差分全绿。
- 生成能力覆盖表，旧引擎仅保留 oracle 角色。

达到 M9 后，新的全部能力覆盖旧能力，允许默认切换并申请删除旧引擎。

## 5. 当前进度

- M0：完成。引擎选择、mini 构建、`--supports` 回退协议已建立。
- M1：词法核心完成。`mini --check` 可读取源文件并输出 token；覆盖标识符、
  关键字、整数、字符串、字符、注释、常用运算符、诊断位置，并有
  `src/mini/tests/lex.sh`。
- M2：语法与 AST 核心完成。`mini --ast` 支持顶层函数、参数、局部声明、
  表达式、调用、`return`、`if`、`while` 和块；有 `src/mini/tests/parser.sh`。
  类/结构/协议、完整表达式优先级与旧引擎 AST 差分留到后续里程碑。
- M3：语义核心完成。`mini --sema` 支持作用域、重复声明、未定义符号、
  Int/String/Bool/Unit/Char/Double、调用数量/参数类型、返回类型、条件类型；
  诊断码 SEM-001..SEM-005，有 `src/mini/tests/sema.sh`。
- M4：最小 C 代码生成完成。`--emit-c` 可生成 `main`、`print`、字符串/整数、
  局部变量、用户函数、`str`、字符串拼接；`--engine=mini` 和 `auto` 已能跑
  `src/examples/hello.x`，有 `src/mini/tests/codegen.sh`。
- M5：对象与控制流核心完成。支持 `class`、字段、方法、`self`、`new`、
  字段赋值、方法调用；支持 `if`/`while`、比较与逻辑运算、赋值；
  有 `src/mini/tests/class.sh` 与 `src/mini/tests/flow.sh`。
- M6.1：数组/`List<Int>` 核心完成。支持 `Int[]` 字面量、索引、`length()`、
  `for-in`；有 `src/mini/tests/array.sh`。
- M6.2：容器核心完成。支持 `List<Int>`、`Map<String,Int>`、map 字面量、
  `push/get/length`、`put/getOr`；`src/examples/classes.x` 已由 mini 接管，
  有 `src/mini/tests/containers.sh`。
- M6.3：`Result<Int,String>` / `try` / `defer` / `errdefer` 完成；
  `result-try.x` 与 `defer-cleanup.x` 已由 mini 接管，有 `result.sh` / `defer.sh`。
- M6.4：`enum` / `struct` / `protocol` / `Set<Int>` 最小场景完成。
  `src/mini/tests/m6_4.x` 覆盖枚举常量、结构体字段/方法、类 `implements`
  协议、`Set.of/length/has`；有 `src/mini/tests/m6_4.sh`。
  结构体按指针实现、协议只做静态直接调用，完整值复制/动态派发后续细化。
- M7.1：`import xdk.<pkg>` 装载与 `xdk.errors` / `xdk.meta` 完成；
  `src/mini/tests/xdk.sh` 覆盖。
- M7.2：`xdk.runtime` 的 `diagnose` / `nowMono` / `nowWall` FFI 桥完成；
  同一 `xdk.sh` 覆盖。
- M7.3：`xdk.text` / `xdk.sys` 最小面完成：
  `padLeft` / `repeatText` / `contains`、`fileExists`；有 `xdk.sh` 覆盖。
  项目 `.xfb` 无参标量桥已通；租约/错误码完整映射仍未做。
- M8.1：`check` 单文件命令完成，mini 引擎输出诊断到 stderr；
  `src/mini/tests/check.sh` 覆盖。
- M8.2：简单工程模式、资源表和 `check --json` 完成，按 `entryFile` 构建/运行；
  `src/mini/tests/project.sh`、`resources.sh` 与 `check.sh` 覆盖。
- M9 前置：`List<T>`、String 子集和顶层字段已支持；mini1/mini2 固定点通过。
- 下一里程碑：M7/M8 剩余项、M9-PAR 全场景差分，最后才讨论默认切换。

## 6. 能力覆盖表

| 类别 | 旧能力 | 新状态 | 里程碑 |
| --- | --- | --- | --- |
| 装载 | package/import/单文件 | 单文件读取已做；包装载待 M7 | M1/M7 |
| 词法 | 全 token 面 | 核心 token 已做 | M1 |
| 语法 | 顶层/表达式/语句 | 核心、类/构造器/控制流已做；高级语句待后续 | M2/M5 |
| 类型 | 基础类型/类/协议/泛型 | 基础类型/类已做；协议/泛型待后续 | M3/M6 |
| 对象 | class/struct/enum/protocol | class/struct/enum/protocol 最小场景已做 | M5/M6 |
| 控制流 | if/while/for/switch/defer | if/while/比较/赋值已做；其余待后续 | M5/M6 |
| 容器 | List/Map/Set/字面量/迭代 | List/Map/Set/Int[]/List<T>/for-in 已做 | M6/M9 |
| 结果 | Result/try/throw/report | Result/try/defer 已做；report 待 XDK | M6/M7 |
| XDK | errors/runtime/meta/text/sys | 五包最小面已做 | M7 |
| FFI | .xfb/raw/错误码 | runtime 固定桥与项目无参标量 .xfb 已做；完整租约/错误码待后续 | M7 |
| 工具链 | check/build/run/工程模式 | check/build/run + 简单工程模式已接通 | M8 |
| 自举 | 旧编译新、新编译新 | mini1/mini2 固定点已完成 | M9 |

## 7. 不变量

- 旧引擎路径始终可用，直到 M9 通过。
- 新引擎不复制运行时/XDK 的语义实现。
- 任何新增 mini 能力必须有场景、有新旧差分、有负例。
- 不因新引擎而修改旧编译器的非阻断代码。

## 8. 状态计划表

| ID | 项 | 状态 | 证据 / 测试 | 缺口 / 备注 |
| --- | --- | --- | --- | --- |
| M0 | 引擎选择、mini 构建、auto 回退 | 完成 | mini lex/parser/sema/codegen | — |
| M1 | 源文件读取、词法、token 诊断 | 完成 | lex.sh | 仅 ASCII 标识符；无浮点、Unicode 标识符 |
| M2 | 顶层函数、局部、表达式、if/while、AST | 完成 | parser.sh | 无完整优先级/泛型 AST 差分 |
| M3 | 作用域、重复声明、基础类型、调用检查 | 完成 | sema.sh | 诊断码仅 SEM-001..005 |
| M4 | main/print/局部/函数/str/字符串拼接 C 生成 | 完成 | codegen.sh | 仅最小表达式面 |
| M5 | class/字段/方法/self/new/控制流/比较 | 完成 | class.sh、flow.sh | 无继承、无完整对象数组 |
| M6.1 | Int[]、索引、length、for-in | 完成 | array.sh | 仅 Int 元素 |
| M6.2 | List<Int>、Map<String,Int>、字面量、常见方法 | 完成 | containers.sh、classes.x | 仅这两组容器类型 |
| M6.3 | Result<Int,String>、Ok/Err、try、defer/errdefer | 完成 | result.sh、defer.sh | 仅 Int/String；无通用 Result/Error、throw/report |
| M6.4 | enum/struct/protocol 最小面、Set<Int> | 完成 | m6_4.sh | struct 为指针实现；protocol 无动态派发；Set 仅 Int |
| M7.1 | import xdk.errors/meta、ErrorKind/isRetryable、版本 API | 完成 | xdk.sh | 仅这两个包的最小面 |
| M7.2 | xdk.runtime diagnose/nowMono/nowWall | 完成 | xdk.sh | 固定 FFI 桥，非通用 .xfb |
| M7.3 | xdk.text/xdk.sys 最小面 | 部分 | xdk.sh | 使用 mini 专用最小文件；不是完整 XDK；无通用 .xfb/错误码 |
| M8.1 | check 单文件命令、stderr 诊断 | 完成 | check.sh | 仅单文件；无完整诊断码 |
| M8.2 | 简单工程模式、check --json、资源表 | 部分 | project.sh、check.sh、resources.sh | 仅 entryFile 工程；资源目录已接入；无模块/依赖/拓扑；build/run --json 缺失 |
| M8.3 | 资源表、可复现构建、安装/锁 | 部分 | resources.sh | 资源表已完成；lock/install/repro 未做 |
| M9 | mini 编译自身、固定点、覆盖旧能力 | 部分 | self-host 固定点、17+1 回归 | mini1/mini2 生成 C 一致；全场景差分和默认切换未做 |

### 明确跳过的能力

- 类型：Float/Double 字面量、Byte/Short/Long 全族、Int128/UInt128、nullable、泛型实例化。
- 语法/语义：继承、数据 enum、泛型函数、lambda/闭包、switch、do/for-range、标签 break/continue、goto、完整字符串插值、throw。
- 容器：List<String>/List<T> 对象元素、Map 其他键值、Set 其他元素、空容器类型推断。
- XDK：完整 text/sys，以及 log/config/io/fs/resource/... 其他包。
- FFI：通用 `.xfb` 解析、租约/错误码完整映射；目前仅硬编码当前使用的桥。
- 工具链：模块/依赖工程、资源表、build/run JSON、lock/install、可复现构建。
- 验证：旧引擎逐场景差分、完整负例矩阵、冷启动预算。

### 记录规则

后续每完成、跳过或部分完成一项，必须更新本表；只写“完成”而没有测试/证据的行视为未完成。

## 9. 详细计划表

### 9.1 触发规则

| 代码 | 触发类型 | 含义 |
| --- | --- | --- |
| S | 场景触发 | 出现一个可运行 `.x` 场景或明确负例；没有场景不开工 |
| D | 依赖触发 | 前置项状态为“完成”，且验收证据存在 |
| R | 回归触发 | 已有测试失败、输出漂移或诊断格式错误 |
| U | 用户/规范触发 | 用户明确要求，或规范修订后新增合同 |
| P | 性能触发 | 冷构建超过 10 分钟，或 warm build 超过 30 秒 |
| G | 发布门触发 | 默认切换、删除旧引擎、发布前 |

规则：

- 没有 S/D/U 触发，任务保持“等待”，不得提前写实现。
- “完成”必须有命令、测试或产物证据；只有文字描述不算。
- 任何跳过的能力必须在本表登记；新增/修改后同步更新。
- 任务触发后先补场景/负例，再改实现。

### 9.2 执行表

| ID | 工作项 | 触发条件 | 前置 | 验收证据 | 状态 |
| --- | --- | --- | --- | --- | --- |
| M7-F1 | 通用 `.xfb` 解析、租约、错误码映射 | S：新增一个使用非当前硬编码桥的 `.xfb` 场景；D：M7.2 完成 | M7.2 | 自定义 `.xfb` 正例 + 错误码负例 | 部分（项目 .xfb 无参标量已通；租约/错误码未全） |
| M7-F2 | `xdk.text` 完整面（parse/format/UTF/Regex） | S：场景调用 mini text 子集之外的 API；D：M7-F1 | M7-F1 | 文本场景 + 旧引擎差分 | 部分（已切到 full/Text.x；mini text shim 已删除；完整 API/差分未做） |
| M7-F3 | `xdk.sys` 完整面（文件/目录/进程/资源） | S：场景调用 `fileExists` 之外的 sys API；D：M7-F1 | M7-F1 | sys 场景 + 负例 | 部分（已切 `io/base/Sys.x`，文件/资源基础面通过；完整 `io/system` raw FFI 未接入） |
| M7-F4 | 其他 T0 包（log/config/io/fs/...） | S：应用导入该包；D：M7-F1 | M7-F1 | 每包最小场景 | 未做 |
| M8-P1 | 模块/依赖/拓扑工程 | S：`xnull.project` 含 `modules` 或跨模块 import；D：M8.2 | M8.2 | validate/tree/build-project 测试 | 完成（modules fixture；validate/build/run/install/repro） |
| M8-P2 | 资源表（`src/main/resources`） | S：工程含资源目录或调用资源 API | M8.2 | 资源读取/缺失负例 | 完成（resources.sh） |
| M8-P3 | `build/run --json` | S：IDE/CI 场景传 `--json`；D：M8.1 | M8.1 | JSON 正例 + 失败负例 | 完成（file/project build/run/check；m8.sh） |
| M8-P4 | lock/install/repro | S：依赖工程或发布场景；D：M8-P1 | M8-P1 | lock/install/repro 测试 | 完成（workspace lock/install/repro；外部仓库解析不在 Mini 1.0） |
| M8-P5 | 完整诊断码/退出码矩阵 | R：任一负例格式/退出码错误；D：M8.1 | M8.1 | 负例矩阵 | 部分（SEM-001/JSON、退出 1/2/程序返回码已覆盖；完整码表未做） |
| M9-C1 | 对象元素容器 `List<T>` / `T[]` | S：`List<Node>`/`List<String>` 场景；D：M6.2 | M6.2 | 容器场景 + mini 自编译门 | 完成（object_list.sh；自源码 List<AstNode>/List<Token>） |
| M9-C2 | String 方法完整面（split/startsWith/substring/indexOf/...） | S：mini 源码或用户场景用到；D：M6.2 | M6.2 | String 场景 | 部分（length/indexOf/substring/startsWith/split 已通；trim/replace/UTF 等未做） |
| M9-C3 | 泛型函数/泛型类型实例化 | S：自身源码或用户场景需要；D：M6.4/M7 | M6.4/M7 | 泛型正例/负例 | 部分（泛型函数/类、显式/字面量推断、嵌套类；约束/函数类型未做；generics.sh） |
| M9-C4 | 继承、数据 enum、lambda、switch、do/for-range、标签控制、throw | S：对应语言场景出现；D：M5/M6 | M5/M6 | 每特性场景 + 负例 | 部分（throw/插值/nullable/Double/位运算/三元/静态方法；高级项未做；c4.sh） |
| M9-S1 | mini 编译 mini（第一代） | D：M9-C1/C2 可用；U：用户明确启动 | M9-C1/C2 | mini1 产物可运行全部回归 | 完成（self-host 构建；21 回归通过） |
| M9-S2 | 固定点：mini1 编译 mini2 | D：M9-S1；R：mini1 回归 | M9-S1 | mini1/mini2 行为一致 | 完成（selfhost.sh：mini1/mini2 生成的 main.x C 完全一致） |
| M9-PAR | 新旧引擎覆盖差分 | D：M9-S2；S：全量场景 | M9-S2 | 全场景 stdout/stderr/退出码差分 | 未做 |
| M9-CUT | 默认切换/旧引擎退居 oracle | G：M9-PAR 全绿 + 用户批准 | M9-PAR | 默认命令全绿；旧引擎仅 oracle | 未做 |
| LANG-1 | Float/Double 字面量、nullable、大整数 | S：场景使用；D：M2/M3 | M2/M3 | 对应场景 | 未做 |
| LANG-2 | 空容器/类型推断/对象容器 | S：场景使用；D：M6.2 | M6.2 | 对应场景 | 未做 |
| CACHE-1 | AST + C 结果缓存 | P：冷构建 >10 分钟或重复构建 | — | warm build <30 秒 | 完成（约 5 秒） |
| SYNC-1 | `src/xdk` 与 `xdk/` 交付物同步 | 任何 src/xdk 变更；G：发布前 | — | `diff -qr` 为空 + 安装测试 | 每次变更执行 |

### 9.3 冻结基线（2026-11-15）

以下成果冻结，后续 M8/M9/M7 工作不得无意回退：

| 项 | 冻结内容 | 验收命令 |
| --- | --- | --- |
| 自举 | `mini1` 编译 `mini2`，两者生成的 `main.x` C 完全一致 | `./src/mini/tests/selfhost.sh` |
| 回归 | 21 个 mini 回归 + 资源场景全部通过 | `for t in src/mini/tests/*.sh; do "$t"; done` |
| 构建 | `src/mini/build.sh` 优先自编译，缺少种子时回退 legacy | `./src/mini/build.sh` |
| 默认引擎 | 仍为 `legacy`；M9-PAR/M9-CUT 通过前不切换 | `src/cli/xnull --help` |
| 容器 | `List<T>` / `List<String>` / `List<Node>` 与 String 子集可用 | `./src/mini/tests/object_list.sh` |

冻结期的例外只有回归修复。任何语言面扩展必须保持上述命令全绿。

后续顺序固定为：

1. M8 工具链接口（M8-P1/P3/P4/P5）
2. M9-C3 泛型、M9-C4 高级语言面
3. M7 全量 XDK
4. M9-PAR 全场景差分、M9-CUT 默认切换

### 9.4 当前激活

- P0 自举可复现性已完成：`cmd_bootstrap_model`/tools/reactor 不再依赖 Go oracle；`m8.sh` 用测试私有目录强制冷启动。
- M8-P1/P2/P3/P4 已完成 workspace 场景；M8-P5 部分完成，完整诊断码矩阵仍待补。
- M9-C1 完成，M9-C3/C4 进入部分实现；M9-S1/S2 已完成，`./src/mini/build.sh` 优先自编译。
- M9-PAR 全场景差分、M9-CUT 默认切换仍未完成。
- M7 已开始向完整 XDK 推进：包内多文件加载、Bytes、静态类方法、Double、泛型 Result 和 XDK raw projection 已接入；`text/full/Text.x` 与 `core/math/Math.x` 可生成 C；`text/mini` 与 `io/mini` shim 均已删除，mini 当前走 `text/full` 与 `io/base`；完整 `io/system` raw FFI 仍未接入。

### 9.5 下一阶段执行清单（dev 分支）

`dev` 为日常开发分支；`main` 只接收通过门禁的合并。当前 `main` 与
`reset/minimal-xnull` 为稳定基线 `1a0a5041`，`dev` 已在其上增加清理和恢复文档；
未通过冻结回归前不得改变默认引擎。

| 优先级 | 工作项 | 具体切片 | 完成判定 |
| --- | --- | --- | --- |
| P0 | 回归冻结 | 每次改动后跑 21 个 `src/mini/tests/*.sh`；先补失败场景再改实现 | 全绿且 selfhost 固定点不漂移；m8 使用独立自举目录，冷启动可复现 |
| P1 | M8-P4 | workspace lock 条目；`install` 生成确定性 `.xlib`；外部依赖只做 LOCK-002 负例 | workspace lock 正例 + 外部依赖负例；`repro` SHA 一致 |
| P1 | M8-P5 | 统一 `CLI-*`/`SEM-*`/`PROJ-*` 诊断码；退出码 0/1/2/130/134 矩阵 | JSON 与 stderr 字段一致 |
| P2 | M9-C2 | String `trim`/`replace`/大小写/UTF 边界；补齐 `parseInt`/`parseFloat` 场景 | 文本场景 + 旧引擎差分 |
| P2 | M9-C3 | 泛型函数/类推断、嵌套实例化、函数类型参数；明确不支持项的负例 | `generics.sh` 扩展并通过 |
| P3 | M9-C4 | 按场景逐项：switch、data enum、继承/协议分派、lambda、do/for-range、标签控制 | 每特性正例 + 负例，不一次性伪造全部能力 |
| P3 | M7-F3 | 先修 `io/system/Sys.x` CGen 崩溃；再补 raw handle/Bytes/Result 类型 | `--sema` + `--emit-c` + C 编译通过 |
| P3 | M7-F1 | 通用 `.xfb` 参数/返回值、租约、错误码映射；替换硬编码桥 | 自定义 `.xfb` 正例 + 错误负例 |
| P4 | M7-F2/F4 | 完整 text/sys 及 T0 包按实际 import 场景接入；不再新增 mini 专用重复 API | 每包场景 + 旧引擎差分 |
| P5 | M9-PAR | 全量 stdout/stderr/退出码差分 | 差分矩阵全绿 |
| Gate | M9-CUT | 仅在 M9-PAR 全绿且用户批准后切换默认引擎 | 默认命令全绿；legacy 退居 oracle |

立即开始顺序：

1. `M8-P4/P5`：先把工程生命周期和机器接口收口。
2. `M9-C2/C3/C4`：优先满足自举与真实 XDK 源码。
3. `M7-F3/F1/F2/F4`：完成 Sys、FFI、文本和其他 T0。
4. `M9-PAR/M9-CUT`：最后做差分和默认切换。

每条工作项必须绑定一个可运行场景或负例；没有场景的能力登记为“等待”，不得以空实现宣称完成。

### 9.6 里程碑口径与工作量

先把“最小 XNull”拆成三个不同口径，避免把自举、可用和默认切换混在一起：

| 口径 | 含义 | 当前 |
| --- | --- | --- |
| M9-SELFHOST | mini 编译 mini，mini1/mini2 固定点 | 已完成 |
| M9-MIN | mini 自举 + M8 工程接口 + 核心 XDK（errors/runtime/meta/text/sys）+ 选定场景差分 | 未完成 |
| M9-FULL | M9-MIN + 全部 T0 XDK、完整语言面、全量旧/新引擎差分、默认切换 | 未完成 |

### 9.6.1 M9-MIN 估算（从当前基线）

以下按一个熟悉本仓库的全职开发者、无外部阻塞估算，单位为 dev-day；每个工作包含实现、场景和回归，不只是改代码。

| 工作包 | 内容 | 估算 |
| --- | --- | ---: |
| A. M8 收口 | M8-P4/P5：workspace lock、install/repro、外部依赖负例、完整诊断/退出码矩阵 | 3–5 |
| B. M9 语言面 | M9-C2、M9-C3 当前缺口 | 2–3 |
| C. 核心 XDK | `text/full`、`io/base`、errors/runtime/meta 组合场景 | 1–2 |
| D. 集成门 | 选定 M9-PAR、回归、默认 `legacy` 保持不变 | 1–2 |
| **合计** | **M9-MIN 从当前基线** | **7–12** |

这里的 7–12 是**当前剩余量**，不是从零做 mini 的总量。当前自举和文本/基础 sys
已经完成，不能再用从零估算的 28–43 天计算当前排期。

### 9.6.2 完整 M9 估算

在 M9-MIN 之上，补齐：

- M7-F4 其余 T0 包；
- M9-C4 的完整高级语言面；
- 全量 XDK 包和全量旧/新引擎差分；
- M9-CUT 发布门。

预计再增加 **30–50 dev-day**，合计约 **60–90 dev-day**。这是产品级默认切换的估算，不是自举所需。

### 9.6.3 执行纪律

接下来的工作不再按“想到一项记一项”推进，而是固定按 §9.5 的 A→B→C→D 工作包执行：

- 每个工作包开始时只确认验收命令和场景；
- 工作包内不新增待办，不因局部完成停下来改计划；
- 每个工作包完成后才更新状态、估算和下一包入口；
- 任何没有场景的需求保持“等待”，不进入当前工作包。

### 9.7 Mini 1.0 七日执行计划（dev）

目标：在 `dev` 上完成一个可交付的 Mini 1.0；**不切换默认引擎**，`main` 仍保持
`legacy` 为默认。计划单位为 dev-day，按一个熟悉本仓库的全职开发者估算。

本阶段范围：

- current self-host fixed point；
- M8 工程接口收口；
- `xdk.text` 使用 `text/full`；
- `xdk.sys` 使用 `io/base`；
- errors/runtime/meta 基础面；
- 21 个现有回归 + 选定场景差分。

明确不在本阶段：完整 `io/system/Sys.x` raw FFI、全部 T0 XDK、完整 M9-C4、
全量 M9-PAR、默认切换。

| Day | 工作 | 产出/验收 |
| --- | --- | --- |
| D1 | 基线冻结 + M8-P4 | 完成：默认 CLI、fixture、workspace lock、install/repro、m8/回归 |
| D2 | M8-P5 + 工程边界 | JSON 字段、诊断码、退出码 0/1/2/130/134；modules 边界负例 |
| D3 | M9-C2 | String trim/replace/toUpper/toLower/UTF 边界；文本场景回归 |
| D4 | M9-C3 | 泛型推断、嵌套实例化、函数类型参数；不支持项负例 |
| D5 | XDK 集成 | `text/full`、`io/base`、resources/errors 组合场景；`src/xdk`/`xdk` 同步 |
| D6 | 选定 M9-PAR | 10–20 个代表性场景的 stdout/stderr/退出码新旧差分 |
| D7 | 收口 | 21 回归 + selfhost + M8 回归全绿；更新 README/PLAN；提交 dev |

#### D1 单一工作包（已完成，2026-11-16）

状态：完成。验证：默认 legacy build/run 不带 `--bootstrap` 通过；
workspace lock/`--check`/`--update` 通过；外部依赖 `LOCK-002` 且不写锁；
install 两次 `.xlib` SHA 一致且与 lock 摘要一致；21 回归 + selfhost 全绿；
m8 热 C 缓存约 43s、全新 C 缓存约 124s。

当前基线 `e312f8da` 已关闭 P0 自举可复现性；D1 作为一个工作包一次完成，
以下只是已执行的内部顺序，不设独立审批门，不拆成多次提交：

1. 默认 CLI 在缺少 `impl/` 时自动走 bootstrap；统一
   `XNULL_MODEL_DIR`/`XNULL_TOOL_DIR`，补齐 `prepare_model`/`prepare_graph`/
   `xmeta`/`tree`/`why`；补不带 `--bootstrap` 的回归。
2. 增加 workspace 依赖 fixture、外部依赖负例、缺版本/缺坐标/锁不一致负例。
3. 先补 workspace lock 规范页，再实现 `entry`、坐标排序、
   `repository=workspace`、确定性 `.xlib` 的 SHA-256、`--check`/`--update`。
4. `install` 产出确定性 `.xlib`；连续两次 SHA 一致；lock 摘要与安装产物一致。
5. 扩展 m8，记录热/冷缓存时间，跑 21 回归 + selfhost，更新 PLAN/RESUME，
   一次提交 `dev`。

D1 锁定口径：

- 外部仓库依赖**不做成功解析**，只验证 `LOCK-002` 负例；本地仓库只用于
  `install` 产物和摘要校验。
- workspace 锁条目采用 `repository = workspace`，`sha256` 取确定性 `.xlib`
  的 SHA-256；该约定未写入现有规范，必须先补一页规范再改代码。
- `LOCK-002` 作为 D1 的临时内部码保留；D2 统一到规范 `XPD-4xx` 时补映射，
  不在 D1 发明新的 `XPD-4xx` 具体码。
- 默认 CLI 修复属于 D1；不带 `--bootstrap` 是交付门禁。
- Mini 1.0 剩余估算统一为 **7–12 dev-day**；计时区分热 C 缓存与全新 C 缓存。

阶段门：

```text
21 个 mini 回归全绿
mini selfhost 固定点不漂移
m8.sh 全绿（冷缓存）
默认 legacy build/run 不带 --bootstrap 可用
workspace lock 字节稳定；外部依赖不产生伪造锁
选定 M9-PAR 场景全绿
main 默认仍是 legacy
```

如果 D1–D7 中发现必须扩大范围，不能静默加塞；必须登记到 §9.5 的下一个工作包，
保持 Mini 1.0 的范围不变。
