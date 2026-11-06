# XDK 前置设计（impl/docs/xdk-design.md）

> 编制：运行时侧（C）　日期：2026-11-06
> 性质：**阶段 A 纯设计**。阶段 B 实现（M4.6）开工条件：M4 收口过门或书面放行。
> 规范依据：S6 v1.1.0（§1.4 架构、§2 包结构、§3 合同原则七条、§4 逐包合同、§8 验收矩阵）、S3 §18/§19、S5、S8 §5.6/§7、S7 §8（`@unsafe`）。
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
| XDK-03 | §4.1 | `ErrorKind` 14 项；`wrap/mapErr/report`；`cause` 约定字段不改协议 | `errors.x`：`Error` 协议 + `ErrorKind` 枚举（14 项按 S5 附录 A）；`wrap` 构造新错误丢弃原因（定案 3-a-1 反向语义：丢弃换新）、`mapErr` 走 `Result` 变换、`report` 返回原 `Result` 并调用 `runtime.diagnose`；原因链为结构体字段 `cause: Error?` | M4.6a |
| XDK-04 | §4.2 | 结构化并发；组是唯一 spawn 入口；关闭唯一终结路径；取消/超时错误面一致 | `tasks.x` 公开面无裸 `spawn`；`TaskGroup.spawn` 为唯一入口；`TaskGroup.close()` 幂等并 join；`Context.isCancelled/checkCancel` 依赖调度器挂起点——**无调度器时** `checkCancel` 只做标志检查（语义可测），挂起语义随调度器切片 | M4.6d（结构面）/ 完成面依赖调度器 |
| XDK-05 | §4.3 | `Mutex.withLock` 作用域化；`Channel` 有界且挂起点可取消；`AtomicRef<T>` 限引用 | `sync.x`：`withLock(body)` 以闭包参数形式保证锁不外泄（类型层面不可返回锁）；`Channel(capacity)` 有界，`send/receive` 携 `Context`；`AtomicInt/AtomicBool/AtomicRef<T>` 由 `rt_std_sync.c` 的 C11 atomics 支撑（`AtomicRef` 只接受引用类型，绑定层以 `Handle` 形态传对象指针 + `xrt_retain/release`） | M4.6d |
| XDK-06 | §4.4 | `diagnose` 单行无分配；`exit` 不执行 defer；`nowMono` 单调；`nowWall` UTC 毫秒可回拨；`env` 不可变快照 | `runtime.x` → C 原语：`diagnose`（`write(2)` 单次、无格式化分配）、`exit`（`_Exit(code)` 不经 defer/终结链）、`nowMono`（`clock_gettime(CLOCK_MONOTONIC)`）、`nowWall`（`time()` × 1000，允许回拨）、`env`（首次读取即快照进不可变表，重复调用返回同一快照） | M4.6a |
| XDK-07 | §4.5 | 内建容器语义不变；算法函数 + 4 特化容器 | `collections.x` 只做算法（`sort/groupBy/dedup/find`，稳定排序，键函数为闭包）与 4 特化容器（`RingBuffer`/`PriorityQueue` 先行，`OrderedMap`/`BTreeMap` 随后）；内建 `T[]/List/Map/Set/StringBuilder` 不动（否决方案 C 不复议） | M4.6c |
| XDK-08 | §4.6 | builder 式格式化；编码转换与解析；`Regex` 动态编译可恢复错误 | `text.x` + `rt_std_text.c`：`Format` 链式构造器（`Format.int(x).width(4).pad('0').build()`）；UTF-8↔UTF-16 转换（C 层无状态函数）；`parseInt/parseFloat` 严格化（全串消费、溢出报错）；`Regex` 动态编译（POSIX ERE 起步，编译失败 → `Result` 错误，不 panic） | M4.6a（格式化/解析）/ M4.6c（Regex） |
| XDK-09 | §4.7 | sys/net 句柄合同；双形态 I/O；net 独立 | `sys.x`：`File`/`Dir`/`Process` 均包 `xrt_handle`（close 幂等、不以 deinit 为唯一路径，S7 §4.3 同款）；异步形态命名带 `Async`，首参 `Context`；plain 形态为无后缀基础函数并声明阻塞分类；`net.x` 独立包（socket 句柄 + 异步形态） | M4.6b（sys）/ M4.6d（net） |
| XDK-10 | §4.8 资源读取 | 5 API + 7 条强制约束 | `sys.x` 内 `resourceExists/readResource/readResourceText/listResources/resourceSize`；资源表由构建期从 `src/main/resources` 生成 C 常量表（`rt_resource_table.c`，只读、无句柄、字典序索引）；路径规则在 `xdk-resource` 单一实现（绝对路径/`..`/空段/反斜杠 → `InvalidArgument`）；不回退文件系统（表内未命中即 `NotFound`） | M4.6b |
| （矩阵外） | §1.4 架构知情 | 依赖矩阵可审计 | 每个包文档头列"依赖的运行时服务 + 跨 FFI 边界条目"；`tools/check_xdk.py` 比对 §1.4.3 矩阵，未登记依赖即失败 | M4.6a |

## 2. 实现层划分

### 2.1 三层结构

```
impl/lib/xdk/*.x         XNull 源码层：公开 API（类型/函数/合同文档）
        │  经 .xfb 绑定调用
        ▼
bindings/xdk/*.xfb        绑定声明（FFI 合同：三形态/租约/错误码/阻塞分类）
        ▼
impl/runtime/rt_std_*.c   C 原语层：OS 与内核服务（不对外导出公共 API 名）
        ▼
impl/runtime/xrt*.c       稳定 ABI（S7 §6.1）：分配/计数/根/弱表/句柄
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

目录与单元（每包一个单元，内含该包全部公开 API 与内部实现）：

```
impl/lib/xdk/errors.x        Error 协议 / ErrorKind / wrap / mapErr / report
impl/lib/xdk/runtime.x       diagnose / exit / nowMono / nowWall / env
impl/lib/xdk/text.x          Format / 编码转换 / parseInt / parseFloat / Regex
impl/lib/xdk/collections.x   sort / groupBy / dedup / find / RingBuffer / OrderedMap / BTreeMap / PriorityQueue
impl/lib/xdk/sys.x           File / Dir / Process / resourceExists / readResource / listResources ...
impl/lib/xdk/tasks.x         Task / TaskGroup / Context
impl/lib/xdk/sync.x          Mutex / Channel / Atomic*
impl/lib/xdk/net.x           Socket / listener（M4.6d）
```

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

1. **编译产物链接**：`libxrt.a` 扩为包含 `rt.c/rt_gc.c/rt_weak.c/rt_policy.c/xrt_abi.c/rt_std_*.c/rt_resource_table.c`（内容哈希键控缓存，P-07 不变）；XDK 的 `.xfb` 绑定声明映射到 `xdkc_*` 符号，属工具链内部库，**不需要用户在 `link.libraries` 声明**（S8 §7：运行时 ABI 符号自动链接，同款规则）；
2. **codegen 头文件**：生成代码与 XDK 绑定代码只 include `xrt.h`（P-08）。当前 M4.1 生成代码 include `rt.h`，M4.5b 切换时一次性迁移（编译器侧负责，不改语义）；
3. **入口垫片**：`main` 由用户单元提供（P-06）；XDK 不提供入口；`runtime.exit` 直接终止进程（不经 defer），与垫片返回值路径互斥但语义清晰；
4. **资源打包**：构建期按 S8 §5.6 收集 `src/main/resources`，生成 `rt_resource_table.c`（只读、字典序、`/` 分隔）；单文件产物因此可携带资源，且文件 API 与资源 API 的路径空间隔离（S6 §4.8 约束 5/7）；
5. **诊断通道**：`diagnose` 输出为单行 stderr（与编译器诊断同流不同格式），不参与退出码；`exit` 退出码由用户传入，遵守 S8 §5.1 约定（0/1/2/130 为工具链保留值，用户程序可自由取值）。

## 4. 切片建议（阶段 B = M4.6）

| 切片 | 内容 | 依赖 | 验收锚点 | 台账 |
| --- | --- | --- | --- | --- |
| **M4.6a** 包骨架 + errors/runtime/text 核心 | 8 单元骨架与依赖检查工具；`errors.x`（14 项 ErrorKind、wrap/mapErr/report、cause 字段）；`runtime.x`（diagnose/exit/nowMono/nowWall/env）；`text.x`（Format builder、编码转换、parseInt/parseFloat） | M4 收口（M4.3 起 `--interp` 并存）；M4.5b 的 `xrt_*` 生成面 | 14 项枚举齐备；`report` 返回原 Result；`exit` 不执行 defer（用例：defer 打印不出现）；`nowMono` 单调（连续调用不减）；`env` 快照（设置后两次读取一致）；Format 输出逐字符比对 | XDK-01 部分、XDK-02、XDK-03、XDK-06、XDK-08 部分 |
| **M4.6b** sys 文件/目录/进程 + 资源读取 | `rt_std_sys.c` + `sys.x`：File/Dir/Process 句柄（close 必达、幂等）；plain 形态 + 异步形态签名；`resourceExists/readResource/readResourceText/listResources/resourceSize` 五 API | M4.5c（`xrt_handle`）；M4.6a（errors） | 打开/读/写/关闭；重复 close 安全；句柄泄漏检测（进程退出前未关闭 → 诊断）；资源 7 条约束逐条用例（非法路径四类 → InvalidArgument、缺失 → NotFound、listResources 字典序、无 close、可取消、不回退 FS、文件 API 读不到资源） | XDK-09 部分、XDK-10 |
| **M4.6c** collections + Regex | `collections.x`（算法 + 4 特化容器）；`text.x` 的 `Regex` 动态编译 | M4.6a | 内建容器语义不变（回归既有容器用例）；4 容器各自契约用例（RingBuffer 覆盖写、PriorityQueue 稳定性、OrderedMap 迭代序、BTreeMap 范围查询）；Regex 编译失败 → 可恢复错误 | XDK-07、XDK-08 完整 |
| **M4.6d** net + tasks/sync 结构面 | `net.x` socket plain 形态；`tasks.x` TaskGroup/Context；`sync.x` Mutex/Channel/Atomic* | 调度器切片（并发语义） | 组外 spawn 不可达（编译期无入口）；组关闭幂等；withLock 不可外泄（类型层用例）；Channel 有界（容量满时行为按挂起点合同）；AtomicRef 拒绝值类型 | XDK-04、XDK-05、XDK-09 完整 |

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
6. **XDK 版本与语言版本解耦**（S6 §5）：XDK 单元头声明所需语言版本，编译器按 S8 声明机制校验，版本不足即构建失败。

## 6. 实施状态与顺序调整（2026-11-06 追加）

**调整**：原计划 M4.6a 先出 8 包骨架 + errors/runtime/text 的 XNull 单元。实际开工时语言面为 Int/Bool/String + Result + 类/容器刚落地、**尚无 extern 调用钩子**（编译器侧 P-09 待接入）。据此按"C 原语先行、XNull 包装随后"重排：

| 项 | 状态 | 证据 |
| --- | --- | --- |
| C 层 `rt_std_runtime.c`（diagnose/exit/nowMono/nowWall/env 快照） | 完成 | `runtime/test_std.c`：单行折叠、exit 跳过 atexit、单调性、UTC 毫秒、快照不可变 |
| C 层 `rt_std_text.c`（parse/format/UTF-8↔UTF-16） | 完成 | 严格解析（全串消费/溢出分离）、非法序列拒绝、代理对往返 |
| C 层 `rt_std_sys.c`（文件读写 + 幂等关闭） | 完成 | 读满/读到尾/重复关闭/缺失文件 |
| 绑定声明 `bindings/xdk/runtime.xfb`、`sys.xfb` | 完成 | 合同校验 + 包装生成 + 与 C 层联合编译运行（`internal/codegen/ffi/xdk_test.go`） |
| XNull 源码层（`impl/lib/xdk/`） | 种子 | `text.x`（repeatText/repeatJoined/isPositive 纯函数）：可解析、可语义检查、可生成 C（`internal/codegen/xdk_seed_test.go`）；完整 API 面待 extern 钩子与类/枚举面稳定 |
| C 层目录/存在性/子进程（M4.6b-2） | 完成 | `rt_std_sys.c`：dirOpen/dirRead（内部缓冲、下次调用前有效）/dirClose 幂等/pathExists/procStatus（退出码，信号/失败 -1）；`test_std.c` 覆盖 |
| 资源表（S8 §5.6） | 完成（生成器+样例验证） | `xnull dev res`（升序、重名报错、空表零成本）+ `test_res.c`；接入 build 清单按 P-10 条件 1（import 闭包）执行 |
| Regex（POSIX ERE 子集）+ Format 追加族 | 完成（C 层） | `rt_std_text.c`：`xdkc_regex_match`（0/1/2 显式区分语法错误）、`fmt_append_raw/int`（调用方游标，失败不推进）；XNull API 面随 P-09 后的包装层 |
| `rt_std_sync.c` / `rt_std_net.c` | 未开工 | 依赖调度器切片（S6 §5 / S8 §5） |

**接口缺口（已记入 runtime-contract 提案）**：

1. P-09：codegen 把 `.xfb` 入口作为包级可调用声明注入，调用点使用 `xn_ffi_<entry>`；
2. P-10：`xnull build` 的 C 编译清单纳入 `xrt_abi.c` 与 `rt_std_*.c`，并注入 `link.libraries`（`LinkArgs`）；
3. 标量出参当前用"返回值为值 + 错误码出参"形态表达；完整 out 参数形态待 M4.6c 提案。

