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
  通用 `.xfb` 仍只覆盖当前使用的桥接函数。
- M8.1：`check` 单文件命令完成，mini 引擎输出诊断到 stderr；
  `src/mini/tests/check.sh` 覆盖。
- M8.2：简单工程模式和 `check --json` 完成，按 `entryFile` 构建/运行；
  `src/mini/tests/project.sh` 与 `check.sh` 覆盖。资源表仍待补。
- 下一里程碑：资源表，然后 M9 尝试 mini 编译自身。

## 6. 能力覆盖表

| 类别 | 旧能力 | 新状态 | 里程碑 |
| --- | --- | --- | --- |
| 装载 | package/import/单文件 | 单文件读取已做；包装载待 M7 | M1/M7 |
| 词法 | 全 token 面 | 核心 token 已做 | M1 |
| 语法 | 顶层/表达式/语句 | 核心已做；类/协议待后续 | M2/M5 |
| 类型 | 基础类型/类/协议/泛型 | 基础类型/类已做；协议/泛型待后续 | M3/M6 |
| 对象 | class/struct/enum/protocol | class/struct/enum/protocol 最小场景已做 | M5/M6 |
| 控制流 | if/while/for/switch/defer | if/while/比较/赋值已做；其余待后续 | M5/M6 |
| 容器 | List/Map/Set/字面量/迭代 | List/Map/Set/Int[]/for-in 已做 | M6 |
| 结果 | Result/try/throw/report | Result/try/defer 已做；report 待 XDK | M6/M7 |
| XDK | errors/runtime/meta/text/sys | 五包最小面已做 | M7 |
| FFI | .xfb/raw/错误码 | runtime 固定桥已做；通用 .xfb 待后续 | M7 |
| 工具链 | check/build/run/工程模式 | check/build/run + 简单工程模式已接通 | M8 |
| 自举 | 旧编译新、新编译新 | 待做 | M9 |

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
| M8.2 | 简单工程模式、check --json | 部分 | project.sh、check.sh | 仅 entryFile 工程；无模块/依赖/拓扑；资源表缺失；build/run --json 缺失 |
| M8.3 | 资源表、可复现构建、安装/锁 | 未做 | — | 需工程模式稳定后实现 |
| M9 | mini 编译自身、固定点、覆盖旧能力 | 未做 | — | 需对象 List<T>、String 方法、完整语言面 |

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
| M7-F2 | `xdk.text` 完整面（parse/format/UTF/Regex） | S：场景调用 mini text 子集之外的 API；D：M7-F1 | M7-F1 | 文本场景 + 旧引擎差分 | 部分（仅 padLeft/repeatText/contains） |
| M7-F3 | `xdk.sys` 完整面（文件/目录/进程/资源） | S：场景调用 `fileExists` 之外的 sys API；D：M7-F1 | M7-F1 | sys 场景 + 负例 | 部分（仅 fileExists） |
| M7-F4 | 其他 T0 包（log/config/io/fs/...） | S：应用导入该包；D：M7-F1 | M7-F1 | 每包最小场景 | 未做 |
| M8-P1 | 模块/依赖/拓扑工程 | S：`xnull.project` 含 `modules` 或跨模块 import；D：M8.2 | M8.2 | validate/tree/build-project 测试 | 未做 |
| M8-P2 | 资源表（`src/main/resources`） | S：工程含资源目录或调用资源 API | M8-P1 | 资源读取/缺失负例 | 完成（resources.sh） |
| M8-P3 | `build/run --json` | S：IDE/CI 场景传 `--json`；D：M8.1 | M8.1 | JSON 正例 + 失败负例 | 部分（check --json 已通；build/run 未） |
| M8-P4 | lock/install/repro | S：依赖工程或发布场景；D：M8-P1 | M8-P1 | lock/install/repro 测试 | 未做 |
| M8-P5 | 完整诊断码/退出码矩阵 | R：任一负例格式/退出码错误；D：M8.1 | M8.1 | 负例矩阵 | 部分 |
| M9-C1 | 对象元素容器 `List<T>` / `T[]` | S：`List<Node>`/`List<String>` 场景；D：M6.2 | M6.2 | 容器场景 + mini 自编译门 | 未做 |
| M9-C2 | String 方法完整面（split/startsWith/substring/indexOf/...） | S：mini 源码或用户场景用到；D：M6.2 | M6.2 | String 场景 | 部分（substring/indexOf 已有） |
| M9-C3 | 泛型函数/泛型类型实例化 | S：自身源码或用户场景需要；D：M6.4/M7 | M6.4/M7 | 泛型正例/负例 | 未做 |
| M9-C4 | 继承、数据 enum、lambda、switch、do/for-range、标签控制、throw | S：对应语言场景出现；D：M5/M6 | M5/M6 | 每特性场景 + 负例 | 未做 |
| M9-S1 | mini 编译 mini（第一代） | D：M9-C1/C2/C3 完成；U：用户明确启动 | M9-C1..C3 | mini1 产物可运行全部回归 | 未做（自源码仍有顶层字段/对象容器解析缺口） |
| M9-S2 | 固定点：mini1 编译 mini2 | D：M9-S1；R：mini1 回归 | M9-S1 | mini1/mini2 行为一致 | 未做 |
| M9-PAR | 新旧引擎覆盖差分 | D：M9-S2；S：全量场景 | M9-S2 | 全场景 stdout/stderr/退出码差分 | 未做 |
| M9-CUT | 默认切换/旧引擎退居 oracle | G：M9-PAR 全绿 + 用户批准 | M9-PAR | 默认命令全绿；旧引擎仅 oracle | 未做 |
| LANG-1 | Float/Double 字面量、nullable、大整数 | S：场景使用；D：M2/M3 | M2/M3 | 对应场景 | 未做 |
| LANG-2 | 空容器/类型推断/对象容器 | S：场景使用；D：M6.2 | M6.2 | 对应场景 | 未做 |
| CACHE-1 | AST + C 结果缓存 | P：冷构建 >10 分钟或重复构建 | — | warm build <30 秒 | 完成（约 5 秒） |
| SYNC-1 | `src/xdk` 与 `xdk/` 交付物同步 | 任何 src/xdk 变更；G：发布前 | — | `diff -qr` 为空 + 安装测试 | 每次变更执行 |

### 9.3 当前激活

- 当前没有自动激活的 M7-F1/M8-P1 场景；相关项保持等待。
- M9-C1/C2/C3 可以在用户提供/批准 `List<T>`、String、泛型场景后启动。
- 在 M9-C1..C3 完成前，不执行 mini 自编译。
