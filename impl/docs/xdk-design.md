# XDK 前置设计（impl/docs/xdk-design.md）

> **2026-11-15 作废**：§2.1/§2.3 的 `<layer>/<domain>` 物理布局、`base`/`full` 双面、`*_full.x`、`xdk-raw` 桥均无规范依据，全部作废。
> 规范原文：S7-01 §2.1「`xdk.*` 不按文件装载；由语义阶段的 XDK 符号表处理」、§2.3「`xdk.*` 不落文件系统」；S6 §2 只定义 8 个平铺包。
> 按规范，XDK 不在文件装载路径上；源码化布局须先修订规范（S7-01/S6）。本文只作历史参考。

> 编制：运行时侧（C）　日期：2026-11-06
> 性质：**阶段 A 纯设计**。阶段 B 实现（M4.6）开工条件：M4 收口过门或书面放行。
> 规范依据：S6 v1.1.0（§1.4 架构、§2 包结构、§3 合同原则七条、§4 逐包合同、§8 验收矩阵）、S3 §18/§19、S5、S9 §5.6/§7、S7 附录 A §A.8（`@unsafe`）。
> 配套：`impl/docs/runtime-contract.md`（运行时 ABI）、`impl/docs/ffi-contract.md`（绑定声明与校验）、`impl/docs/ffi-design.md`（三形态+租约+错误码）。

## 0. 立场

- XDK 的**公开 API 面全部是 XNull 源码**（`impl/lib/xdk/*.x`）：类型、函数、合同文档都在源码里，可被编译器做类型检查、可被解释器执行、也是自举前最早的真实 XNull 代码；
- C 层只提供**私有原语**（`impl/runtime/rt_std_*.c`），经 `.xfb` 绑定声明以 FFI 合同（三形态 + 逐参数租约 + 错误码）暴露——不新开公共通道；
- 应用代码只经 XDK 包层使用运行时能力（S6 §1.4.1）；本设计不引入绕过包层的导出符号；
- 首版切片按**自举最小需求集**排序（编译器自身要读写文件、格式化、报错），并发族依赖调度器切片，排在其后。

## 1. S6 合规映射表

| 台账 | S6 条款 | 要求摘要 | 实现层决策 | 切片 |
| --- | --- | --- | --- | --- |
| XDK-01 | §2 包结构、§1.4.3 依赖矩阵 | 8 包齐备；依赖方向与矩阵一致 | 8 包 = `impl/lib/xdk/` 下 8 个源单元（errors/tasks/sync/runtime/collections/text/sys/net）；包间依赖**单向**：sys→errors→runtime→text→collections（collections 不依赖 sys）；tasks/sync 只依赖 errors/runtime | M4.6a（包骨架 + 依赖检查工具） |
| XDK-02 | §3 七条合同原则 | 错误/资源/取消/命名/无隐式/稳定性行/架构知情 | 机械核验项入 `tools/check_xdk.py`：①公开 API 返回 `Result`（可失败操作）白名单例外；②持资源类型必须有 `close()`（与 `xrt_handle` 绑定）；③可阻塞 API 首参 `Context`；④命名规范（正则）；⑤无全局可变 `static`（源码扫描 + 绑定表审计）；⑥每个 API 有稳定性标注（源码文档注释 `@stable/@preview/@internal`）；⑦包文档含依赖矩阵条目 | M4.6a（工具）/ 全程 |
| XDK-03 | §4.1 | `ErrorKind` 14 项；`wrap/mapErr/report`；`cause` 约定字段不改协议 | `core/errors/Errors.x`：`Error` 协议 + `ErrorKind` 枚举（14 项按 S5 附录 A）；`wrap` 构造新错误丢弃原因（定案 3-a-1 反向语义：丢弃换新）、`mapErr` 走 `Result` 变换、`report` 返回原 `Result` 并调用 `runtime.diagnose`；原因链为结构体字段 `cause: Error?` | M4.6a |
| XDK-04 | §4.2 | 结构化并发；组是唯一 spawn 入口；关闭唯一终结路径；取消/超时错误面一致 | `concurrent/tasks/Tasks.x` 公开面无裸 `spawn`；`TaskGroup.spawn` 为唯一入口；`TaskGroup.close()` 幂等并 join；`Context.isCancelled/checkCancel` 依赖调度器挂起点——**无调度器时** `checkCancel` 只做标志检查（语义可测），挂起语义随调度器切片 | M4.6d（结构面）/ 完成面依赖调度器 |
| XDK-05 | §4.3 | `Mutex.withLock` 作用域化；`Channel` 有界且挂起点可取消；`AtomicRef<T>` 限引用 | `concurrent/sync/Sync.x`：`withLock(body)` 以闭包参数形式保证锁不外泄（类型层面不可返回锁）；`Channel(capacity)` 有界，`send/receive` 携 `Context`；`AtomicInt/AtomicBool/AtomicRef<T>` 由 `rt_std_sync.c` 的 C11 atomics 支撑（`AtomicRef` 只接受引用类型，绑定层以 `Handle` 形态传对象指针 + `xrt_retain/release`） | M4.6d |
| XDK-06 | §4.4 | `diagnose` 单行无分配；`exit` 不执行 defer；`nowMono` 单调；`nowWall` UTC 毫秒可回拨；`env` 不可变快照 | `core/runtime/Runtime.x` → C 原语：`diagnose`（`write(2)` 单次、无格式化分配）、`exit`（`_Exit(code)` 不经 defer/终结链）、`nowMono`（`clock_gettime(CLOCK_MONOTONIC)`）、`nowWall`（`time()` × 1000，允许回拨）、`env`（首次读取即快照进不可变表，重复调用返回同一快照） | M4.6a |
| XDK-07 | §4.5 | 内建容器语义不变；算法函数 + 4 特化容器 | `core/collections/Collections.x` 只做算法（`sort/groupBy/dedup/find`，稳定排序，键函数为闭包）与 4 特化容器（`RingBuffer`/`PriorityQueue` 先行，`OrderedMap`/`BTreeMap` 随后）；内建 `T[]/List/Map/Set/StringBuilder` 不动（否决方案 C 不复议） | M4.6c |
| XDK-08 | §4.6 | builder 式格式化；编码转换与解析；`Regex` 动态编译可恢复错误 | `text/full/Text.x` + `rt_std_text.c`：`Format` 链式构造器（`Format.int(x).width(4).pad('0').build()`）；UTF-8↔UTF-16 转换（C 层无状态函数）；`parseInt/parseFloat` 严格化（全串消费、溢出报错）；`Regex` 动态编译（POSIX ERE 起步，编译失败 → `Result` 错误，不 panic） | M4.6a（格式化/解析）/ M4.6c（Regex） |
| XDK-09 | §4.7 | sys/net 句柄合同；双形态 I/O；net 独立 | `io/system/Sys.x`：`File`/`Dir`/`Process` 均包 `xrt_handle`（close 幂等、不以 deinit 为唯一路径，S7 附录 A §A.4.3 同款）；异步形态命名带 `Async`，首参 `Context`；plain 形态为无后缀基础函数并声明阻塞分类；`net/network/Net.x` 独立包（socket 句柄 + 异步形态） | M4.6b（sys）/ M4.6d（net） |
| XDK-10 | §4.8 资源读取 | 5 API + 7 条强制约束 | `io/system/Sys.x` 内 `resourceExists/readResource/readResourceText/listResources/resourceSize`；资源表由构建期从 `src/main/resources` 生成 C 常量表（`rt_resource_table.c`，只读、无句柄、字典序索引）；路径规则在 `xdk-resource` 单一实现（绝对路径/`..`/空段/反斜杠 → `InvalidArgument`）；不回退文件系统（表内未命中即 `NotFound`） | M4.6b |
| （矩阵外） | §1.4 架构知情 | 依赖矩阵可审计 | 每个包文档头列"依赖的运行时服务 + 跨 FFI 边界条目"；`tools/check_xdk.py` 比对 §1.4.3 矩阵，未登记依赖即失败 | M4.6a |

## 2. 实现层划分

### 2.1 三层结构

```
impl/lib/xdk/<layer>/<domain>/*.x
                          XNull 源码层：公开 API（类型/函数/合同文档）
        │  经 .xfb 绑定调用
        ▼
bindings/xdk/*.xfb        绑定声明（FFI 合同：三形态/租约/错误码/阻塞分类）
        ▼
impl/runtime/rt_std_*.c   C 原语层：OS 与内核服务（不对外导出公共 API 名）
        ▼
impl/runtime/xrt*.c       稳定 ABI（S7 附录 A §A.6.1）：分配/计数/根/弱表/句柄
```

理由：

1. **合同一次校验**：XDK 对 OS 的全部接触面都进 `.xfb`，复用 M4.5a 的校验器（租约、类型白名单、错误码映射），不需要第二套规则；
2. **API 用 XNull 写**：`withLock` 的作用域化、`Result` 变换、闭包参数这类约束只有 XNull 类型系统能表达；C 层写不了；
3. **自举铺垫**：`impl/lib/xdk/` 是 M5.1 编译器重写时第一个"用 XNull 写的大块代码"，编译器成熟度提前受检验；
4. **解释器一致**：`.x` 源码在 `--interp` 下同样执行（§2.3），两条路径共享同一份 API 源码，避免双实现漂移。

### 2.2 C 层：`rt_std_*.c` 与既有 API 的关系

| 文件 | 内容 | 与既有/提案 API 的关系 |
| --- | --- | --- |
| `rt_std_runtime.c` | `diagnose` / `exit` / `nowMono` / `nowWall` / `env` 快照 | 复用 `xrt_*` 做字符串生命周期；**不新增公共符号名**，符号为 `xdkc_*`（内部库，随 `libxrt.a` 静态编入） |
| `rt_std_text.c` | UTF 转换、`parseInt/parseFloat`、`Format` 缓冲 | 字符串构造/拼接直接用 `rt_string`（P-02 `rt_string_concat` 在 M4.5b 落地）；`Format` 内部用栈缓冲 + 单次 `rt_string_new`，不引入新分配器 |
| `rt_std_sync.c` | `Atomic*`、`Mutex`、`Channel` 的原始操作 | `AtomicRef` 用 `xrt_retain/release` 管理载荷对象引用（INV-FFI-4 不破：对象指针只在运行时内部流转，不交给原生侧） |
| `rt_std_sys.c` | 文件/目录/子进程/资源表查询 | 句柄一律 `xrt_handle`（M4.5c 落地，`xrt_handle_new(void*, close_fn)`）；`errno` → 错误码按 `.xfb` 的 `errorMap` 映射 |
| `rt_std_net.c` | Socket 基础（connect/listen/accept/read/write/close） | 同上；异步形态由调度器切片接管（M4.6d 只做 plain 形态 + 声明） |
| `rt_resource_table.c` | 构建期生成的只读资源表（路径 → 偏移/长度） | 只读段；无句柄（S6 §4.8 约束 2） |

**不重复造**：`concat / str_from_* / print / array / closure` 等属 P-02/P-03 提案（M4.1/M4.5b 消费面），XDK C 层直接消费，不另立等价函数。

### 2.3 XNull 源码层：`impl/lib/xdk/`

物理目录按**分层/域**两级组织；运行时包名保持 S6 定案的 `xdk.errors`、`xdk.text`
等冻结名称，编译器/构建包使用 `xdk.compiler.*`、`xdk.build.*`。解析器
（`tests/toolchain/package_resolver.py` 的 `XDK_LAYOUT`）负责包名到物理路径的映射。
同一包有默认冻结面与完整实现两套源码时，用 `base` / `full` 域区分。

```
impl/lib/xdk/
  build/                 构建编排层（工程模型）
    artifact/            artifact 上下文
    config/              配置上下文
    deps/                依赖图
    manifest/            清单加载
    reactor/             聚合构建驱动
    resource/            资源管理
    meta/                模块元数据
    project/             工程描述（xpd）
  compiler/              编译器层
    lexer/               词法器（xlex）
    parser/              语法器（xparser）
    codegen/             代码生成（xnullc，包名 xdk.compiler.codegen）
  core/                  语言核心层（对应 java.lang / Foundation）
    errors/              Error / ErrorKind / wrap / mapErr / report
    runtime/             diagnose / exit / 时钟 / env 骨架
    collections/         sort / groupBy / dedup / find + 4 特化容器
    math/               数学函数 + Random
    time/               Duration / Civil / DateTime
  text/                  文本层（对应 java.text / CoreText）
    base/               默认冻结文本面
    full/               完整文本实现（Format / Regex / 编码 / 解析）
  data/                  数据层（对应 java.sql / CoreData）
    codec/              Base64 / URL / JSON / CSV / 二进制
  io/                    输入输出层（对应 java.io / Foundation）
    base/               默认冻结 sys 面
    system/             完整文件 / 目录 / 进程实现
    resource/           内嵌资源子单元
  net/                   网络层（对应 java.net / Network）
    base/               默认冻结网络面
    network/            完整 Socket / Listener / HTTP 实现
  concurrent/            并发层（对应 java.util.concurrent / Dispatch）
    tasks/              任务与任务组骨架
    sync/               互斥 / 通道 / 原子骨架
  util/                  工具层（对应 java.util）
    tool/               哈希 / UUID / 压缩 / 日志 / 参数 / 断言
```

约束：第一层与第二层目录名必须是单个单词，禁止 `net_full`、`text_full`、
`sys_res` 这类词组/下划线命名；类文件仍使用 PascalCase 且与类同名。
兼容例外：默认冻结面 `io/base/Sys.x` 为保持 冻结 golden 的 AST 逐字节一致，
保留无 `package` 的 legacy 形态；完整实现 `io/system/Sys.x` 声明 `package xdk.sys`。
其余包主单元均声明 `package`。
并入记录（2026-11-15）：原 `impl/lib/b2`、`b3`、`b4` 已迁入 `xdk/compiler` 与
`xdk/build`，旧目录删除；`xlex`/`xparser` 包名改为 `xdk.compiler.lexer`/
`xdk.compiler.parser`，编译器/构建包名改为 `xdk.compiler.codegen`/`xdk.build.*`。
`compiler/codegen` 的完整单文件 AST 仍受原生 xparser 超时阻塞，manifest 以
`baseline_blocked` 标记；源码哈希、类文件和 75 类纳管校验正常，后续修解析器后
再补 AST 基线。

编译期集成（三选一，定 A）：

| 方案 | 说明 | 结论 |
| --- | --- | --- |
| **A 按需编译单元**（采纳） | 编译器解析 `import xdk.sys` 时把对应 `.x` 单元加入编译集（与用户单元同一 codegen 管线），产物中每单元一个 `.c` | 类型系统全程参与；无二进制分发问题；增量编译按单元粒度 |
| B 预编译为 C 静态库 | 提前把 XDK 编成 `.a` | XNull 类型信息丢失、`Result`/闭包 ABI 需稳定化——过早冻结 |
| C 内建进编译器 | API 写死在 Go 里 | 与"XDK 用 XNull 写"目的相反；自举时无法复用 |

- 依赖声明：`.x` 单元头 `import xdk.errors` 显式引入；编译器校验包依赖方向（XDK-01）；
- 稳定性标注：源码文档注释 `@stable` / `@preview` / `@internal`，`tools/check_xdk.py` 机械核验（S6 §3 第 6 条）。

### 2.4 解释器过渡（`--interp`，M4.3 之后为调试路径）

- `print` / `str` 保持语言内建（S1），不属于 XDK；
- XDK `.x` 单元在解释器下同样解释执行——**同一份源码**，不维护第二套实现；
- 解释器缺的是 C 原语：`diagnose/exit/nowMono/nowWall/env/文件/资源/时钟` 需要 Go 侧桥接函数（命名与签名同绑定声明，标注 `internal`，不出现在语言文档）；
- 一致性要求：`--interp` 与编译路径对同一程序输出逐字节一致（M4.3 完成定义），桥接函数因此必须复用与 C 层相同的格式与错误分类（`diagnose` 单行、`exit` 不经 defer、时间精度按 §4.4 合同）。

## 3. 与 M4 集成点

1. **编译产物链接**：`libxrt.a` 扩为包含 `rt.c/rt_gc.c/rt_weak.c/rt_policy.c/xrt_abi.c/rt_std_*.c/rt_resource_table.c`（内容哈希键控缓存，P-07 不变）；XDK 的 `.xfb` 绑定声明映射到 `xdkc_*` 符号，属工具链内部库，**不需要用户在 `link.libraries` 声明**（S9 §7：运行时 ABI 符号自动链接，同款规则）；
2. **codegen 头文件**：生成代码与 XDK 绑定代码只 include `xrt.h`（P-08）。当前 M4.1 生成代码 include `rt.h`，M4.5b 切换时一次性迁移（编译器侧负责，不改语义）；
3. **入口垫片**：`main` 由用户单元提供（P-06）；XDK 不提供入口；`runtime.exit` 直接终止进程（不经 defer），与垫片返回值路径互斥但语义清晰；
4. **资源打包**：构建期按 S9 §5.6 收集 `src/main/resources`，生成 `rt_resource_table.c`（只读、字典序、`/` 分隔）；单文件产物因此可携带资源，且文件 API 与资源 API 的路径空间隔离（S6 §4.8 约束 5/7）；
5. **诊断通道**：`diagnose` 输出为单行 stderr（与编译器诊断同流不同格式），不参与退出码；`exit` 退出码由用户传入，遵守 S9 §5.1 约定（0/1/2/130 为工具链保留值，用户程序可自由取值）。

## 4. 切片建议（阶段 B = M4.6）

| 切片 | 内容 | 依赖 | 验收锚点 | 台账 |
| --- | --- | --- | --- | --- |
| **M4.6a** 包骨架 + errors/runtime/text 核心 | 8 单元骨架与依赖检查工具；`core/errors/Errors.x`（14 项 ErrorKind、wrap/mapErr/report、cause 字段）；`core/runtime/Runtime.x`（diagnose/exit/nowMono/nowWall/env）；`text/full/Text.x`（Format builder、编码转换、parseInt/parseFloat） | M4 收口（M4.3 起 `--interp` 并存）；M4.5b 的 `xrt_*` 生成面 | 14 项枚举齐备；`report` 返回原 Result；`exit` 不执行 defer（用例：defer 打印不出现）；`nowMono` 单调（连续调用不减）；`env` 快照（设置后两次读取一致）；Format 输出逐字符比对 | XDK-01 部分、XDK-02、XDK-03、XDK-06、XDK-08 部分 |
| **M4.6b** sys 文件/目录/进程 + 资源读取 | `rt_std_sys.c` + `io/system/Sys.x`：File/Dir/Process 句柄（close 必达、幂等）；plain 形态 + 异步形态签名；`resourceExists/readResource/readResourceText/listResources/resourceSize` 五 API | M4.5c（`xrt_handle`）；M4.6a（errors） | 打开/读/写/关闭；重复 close 安全；句柄泄漏检测（进程退出前未关闭 → 诊断）；资源 7 条约束逐条用例（非法路径四类 → InvalidArgument、缺失 → NotFound、listResources 字典序、无 close、可取消、不回退 FS、文件 API 读不到资源） | XDK-09 部分、XDK-10 |
| **M4.6c** collections + Regex | `core/collections/Collections.x`（算法 + 4 特化容器）；`text/full/Text.x` 的 `Regex` 动态编译 | M4.6a | 内建容器语义不变（回归既有容器用例）；4 容器各自契约用例（RingBuffer 覆盖写、PriorityQueue 稳定性、OrderedMap 迭代序、BTreeMap 范围查询）；Regex 编译失败 → 可恢复错误 | XDK-07、XDK-08 完整 |
| **M4.6d** net + tasks/sync 结构面 | `net/network/Net.x` socket plain 形态；`concurrent/tasks/Tasks.x` TaskGroup/Context；`concurrent/sync/Sync.x` Mutex/Channel/Atomic* | 调度器切片（并发语义） | 组外 spawn 不可达（编译期无入口）；组关闭幂等；withLock 不可外泄（类型层用例）；Channel 有界（容量满时行为按挂起点合同）；AtomicRef 拒绝值类型 | XDK-04、XDK-05、XDK-09 完整 |

### 4.1 八包优先级（自举最小需求集优先）

| 优先级 | 包 | 理由 |
| --- | --- | --- |
| P0 | `sys`（文件读写子集） | 编译器要读源文件、写 C 产物——**自举硬依赖** |
| P0 | `errors` | 一切可失败 API 的错误面 |
| P0 | `runtime` | 诊断与退出；`env` 供工具链 |
| P0 | `text`（Format/parse/编码） | 生成代码与诊断文本 |
| P1 | `collections` | 编译器内部数据结构（Map/List 已内建，算法与特化容器为增强） |
| P1 | `sys`（进程/资源读取） | 构建编排与单文件产物（非自举阻塞） |
| P2 | `net` | 服务端定位，自举不需要 |
| P2 | `tasks` / `sync` | 并发族，依赖调度器切片；单线程编译器不需要 |

## 5. 风险与开放点

1. **调度器依赖**：XDK-04/05 的"挂起点可取消"在无调度器时不可完整验收——切片 M4.6d 只交付结构与可测面，完成面挂并发切片，台账需按"部分"标注归属，不得虚报；
2. **`AtomicRef<T>` 与引用计数**：原子载荷必须持对象引用（`xrt_retain`），否则并发下可能提前终结；绑定层需保证"取值即持有、覆盖即释放"，用例覆盖；
3. **资源表规模**：单文件产物携带全部资源，大资源（模型/视频）不适用——首版声明上限（建议单资源 ≤ 8 MiB、总量 ≤ 64 MiB），超限构建期报错；
4. **Windows 平台**：`rt_std_sys.c` 首版按 POSIX（`open/read/write/posix_spawn`）实现，Windows 后端后置（接口不变，实现分支）；
5. **`Regex` 实现选择**：POSIX ERE 起步（无外部依赖）；若验收需要回溯/命名组，走次版本提案，不引第三方库（禁网纪律）；
6. **XDK 版本与语言版本解耦**（S6 §5）：XDK 单元头声明所需语言版本，编译器按 S9 声明机制校验，版本不足即构建失败。

## 6. 实施状态与顺序调整（2026-11-06 追加）

**调整**：原计划 M4.6a 先出 8 包骨架 + errors/runtime/text 的 XNull 单元。实际开工时语言面为 Int/Bool/String + Result + 类/容器刚落地、**尚无 extern 调用钩子**（编译器侧 P-09 待接入）。据此按"C 原语先行、XNull 包装随后"重排：

| 项 | 状态 | 证据 |
| --- | --- | --- |
| C 层 `rt_std_runtime.c`（diagnose/exit/nowMono/nowWall/env 快照） | 完成 | `runtime/test_std.c`：单行折叠、exit 跳过 atexit、单调性、UTC 毫秒、快照不可变 |
| C 层 `rt_std_text.c`（parse/format/UTF-8↔UTF-16） | 完成 | 严格解析（全串消费/溢出分离）、非法序列拒绝、代理对往返 |
| C 层 `rt_std_sys.c`（文件读写 + 幂等关闭） | 完成 | 读满/读到尾/重复关闭/缺失文件 |
| 绑定声明 `bindings/xdk/runtime.xfb`、`sys.xfb` | 完成 | 合同校验 + 包装生成 + 与 C 层联合编译运行（`internal/codegen/ffi/xdk_test.go`） |
| XNull 源码层（`impl/lib/xdk/`） | 种子 | `text/full/Text.x`（repeatText/repeatJoined/isPositive 纯函数）：可解析、可语义检查、可生成 C（`internal/codegen/xdk_seed_test.go`）；完整 API 面待 extern 钩子与类/枚举面稳定 |
| C 层目录/存在性/子进程（M4.6b-2） | 完成 | `rt_std_sys.c`：dirOpen/dirRead（内部缓冲、下次调用前有效）/dirClose 幂等/pathExists/procStatus（退出码，信号/失败 -1）；`test_std.c` 覆盖 |
| 资源表（S9 §5.6） | 完成（生成器+样例验证） | `xnull dev res`（升序、重名报错、空表零成本）+ `test_res.c`；接入 build 清单按 P-10 条件 1（import 闭包）执行 |
| Regex（POSIX ERE 子集）+ Format 追加族 | 完成（C 层） | `rt_std_text.c`：`xdkc_regex_match`（0/1/2 显式区分语法错误）、`fmt_append_raw/int`（调用方游标，失败不推进）；XNull API 面随 P-09 后的包装层 |
| `rt_std_sync.c` / `rt_std_net.c` | 未开工 | 依赖调度器切片（S6 §5 / S9 §5） |

**接口缺口（已记入 runtime-contract 提案）**：

1. P-09：codegen 把 `.xfb` 入口作为包级可调用声明注入，调用点使用 `xn_ffi_<entry>`；
2. P-10：`xnull build` 的 C 编译清单纳入 `xrt_abi.c` 与 `rt_std_*.c`，并注入 `link.libraries`（`LinkArgs`）；
3. 标量出参当前用"返回值为值 + 错误码出参"形态表达；完整 out 参数形态待 M4.6c 提案。


## 7. 源码层实现追加（2026-11-13，XDK-SRC-01）

`impl/lib/xdk/{text,sys,net}.x` 已从骨架推进到可用实现，并通过
`tests/xdk/source/run.sh` 四组 E2E（见 `evidence/XDK-SRC-01/`）：

- **text**：`Format`、`parseInt/parseFloat`、`Regex`、UTF-8↔UTF-16；补顶层工厂
  `formatInt/formatFloat/formatString/formatBool/regexCompile`（类静态方法调用
  在冻结编译器上不可用）。
- **sys**：`File`（整文件文本）、`Dir`、`Process`、资源 5 API；FFI 经
  `bindings/xdk/sys_raw.xfb` 的 Int64 句柄/hex 桥（Bytes 借出面待编译器修复）。
- **net**：`Socket`（文本收发）、`Request/Response`、`httpGet/httpPost`；
  `Listener.accept` 显式 Unsupported（运行时 listen/accept 未接入）。

接入方式：`XNULL_XDK_SOURCE=1 bin/xnull --bootstrap run <entry.x>`；
`tests/toolchain/xdk-bundle.py` 固定 bundle 布局（编译器 FFI 原型发射对文件数敏感）。
默认路径不变，冻结 golden 9/9 保持 PASS。

剩余：`TaskGroup`、`AtomicRef<T>` 需编译器发射面（编译器发射面）；二进制流与取消/挂起
随调度器切片。

### 7.1 IO 收口（2026-11-13）

- File 改为直接落盘：文本走 append 原语，二进制走 hex 桥（单次 1 MiB 上限）；
  `seek/position/size/read/readAll` 可用。
- 新增文件系统操作、`Path`、`Dir.entries`、`runProcessResult`（stdout+退出码）、
  `Socket.sendBytes/recvBytes`。
- `io/system/Sys.x` 的资源段拆到同包单元 `io/resource/Resource.x`：原生 xparser 对深嵌套资源函数存在
  解析退化（指数级变慢），拆分后恢复秒级解析。
- 冻结编译器在部分 bundle 组合下清空 FFI 参数；`tests/toolchain/xdk-ffi-fix.py`
  按投影重建原型/签名/调用参数，作为 编译器修复前的编译桥。
- 完整实现位于 `impl/lib/xdk/{sys,net,text}_full.x` + `io/resource/Resource.x`，默认构建仍用
  `io/system/Sys.x、net/network/Net.x、text/full/Text.x` 冻结面；`xdk-raw/` 承载 raw 绑定，避免改变默认投影。
- E2E：`tests/xdk/source/run.sh` 6/6 PASS；`verify-golden` 142/97/9 全绿。
