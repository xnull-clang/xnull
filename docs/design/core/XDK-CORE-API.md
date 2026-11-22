# XDK 核心层 API 设计 v1.0

> **已由 [`core/`](README.md) 取代（2026-11-21）**：本文件是 v1 扁平 API 快照，不再作为 API 权威，也不再回写。
> 新设计见 `core/`；客户端/服务器画像见 `core/CORE-PROFILES.md`；平台/硬件边界见 `core/PLATFORM-BOUNDARY.md`。

| 项 | 值 |
| --- | --- |
| 文档性质 | 设计基线；只写方案与 API 面，不写代码，不讨论编译器/FFI/实现 |
| 范围 |  核心层：14 个公共包 + 执行层内建 |
| 依据 | S7 v3.0、`00-overview.md` v1.2、`01`–`16` 包设计、`MINI-1.0.md` 的 P9=B |
| 目标 | 回答“核心层能做什么”，并给出每个包、每个公开类/协议/枚举的能力与方法面 |
| 状态 | Draft for review；本文与旧包文档冲突处，以本文 §2 的契约决策为准，后续回写各包文档 |
| 场景 | 见 `XDK-SCENARIOS.md`；本文只定义 API，场景负责验证 API 是否够用 |

---

## 0. 先分析：现在的资料是什么

### 0.1 资料盘点

| 层 | 内容 | 作用 | 问题 |
| --- | --- | --- | --- |
| 规范层 | S0–S10 | 语言语义、错误/并发/资源合同、XDK 分层 | 与  设计存在少量口径差异 |
| 包设计层 | `docs/design/01`–`16` | 包能力、K/X、部分类契约 | 成熟度不均，部分只有能力级描述 |
| 范围决策层 | `MINI-1.0.md`、`AUDIT.md` | 1.0 包清单、阶段状态 | 16 包与 14 包口径未统一 |

### 0.2 现有设计的成熟度

| 等级 | 包 | 判断 |
| --- | --- | --- |
| A：类级契约较完整 | `errors`、`bytes`、`collections` | 有类型、方法、失败、所有权、边界；可作为样板 |
| B：能力级完整、类级不完整 | `runtime`、`meta`、`math`、`time`、`tasks`、`sync`、`log`、`config`、`cli` | 能说清“做什么”，但类的生命周期/并发/失败面不齐 |
| C：能力级为主、类面缺失 | `text`、`io`、`fs`、`sys` | 设计文档没有逐类 API；且包归属有冲突 |

### 0.3 六个必须先解决的问题

1. **范围口径**：`00-overview.md` 写 16 个  包；`MINI-1.0.md` 的 P9=B 把 `tasks`/`sync` 降为语言内建 + deprecated 命名空间，1.0 只保留 14 个包。核心层设计必须选一个口径。
2. **包归属**：`File`、`Dir`、`Path` 在现有 API 面中属于 `xdk.sys`，设计文档却把它们归 `xdk.fs`；`xdk.fs` 与 `xdk.sys` 同时暴露 `exists/readText/writeText` 类函数。
3. **类级 API 缺口**：`text` 的 `Format/Regex/Match/Utf16`、`io` 的 `Reader/Writer`、`fs` 的 `Path/File/Dir`、`sys` 的 `Process/ProcessResult` 没有完整类契约。
4. **合同错误**：`TaskGroup.spawn` 返回 `Task<T>` 却声明可失败；`Channel.send/receive` 用 `CancelledError` 表达关闭；旧文档把无成功值的 `Result` 写成 `void` 成功类型，与 S1 的 `Result<Unit,...>` 冲突；`Map.put` 在文档里同时写 `Bool` 和 `Int?`。
5. **命名冲突**：`isEmpty`（bytes/text）、`count`（text/collections）、`flatten`（errors/collections）、`readText/writeText/exists`（fs/sys）会在“同时导入全部核心包”时冲突或产生双语义。
6. **依赖口径**：`time` 文档写依赖 runtime，现有 API 面却出现 sys 依赖；`fs` 与 `sys` 互相声称被对方依赖；`config` 是否依赖 codec 也有旧说法。

### 0.4 本文的选择

- 核心层按 **14 个公共包 + 执行层内建** 设计：
  - 14 包：`errors`、`runtime`、`meta`、`bytes`、`text`、`collections`、`math`、`time`、`io`、`fs`、`sys`、`log`、`config`、`cli`。
  - 执行层内建：`Context`、`Task<T>`、`TaskGroup`、`Channel<T>`、`Mutex<T>`、`AtomicInt/Bool/Ref<T>`；`xdk.tasks`/`xdk.sync` 只作为 deprecated 兼容命名空间，不计入 1.0 公共包承诺。
- 核心层按“能力”而不是“文件”组织；K 是验收底线，X 是同阶段扩展。
- 本文冻结的是 **API 形态与语义**，不讨论实现方式，也不把设计当成 `Verified`。

---

## 1. 核心层能做什么

### 1.1 四个能力域

| 能力域 | 包 | 核心层让调用方能做什么 |
| --- | --- | --- |
| 基础与治理 | `errors`、`runtime`、`meta`、`log`、`config`、`cli` | 分类和构造错误、诊断/退出/时钟、版本与平台、分级日志、配置快照、命令行解析 |
| 数据与计算 | `bytes`、`text`、`collections`、`math`、`time` | 处理字节和文本、解析/格式化、容器与算法、整数/浮点/Int128、时长与日期 |
| 外部世界 | `io`、`fs`、`sys` | 内存/文件/标准流、路径/文件/目录、进程/环境/平台/内嵌资源 |
| 并发执行 | 内建 `tasks`/`sync` | 任务、任务组、取消、截止等待、互斥、通道、原子量 |

### 1.2 端到端能力链

核心层不是“16 个互不相干的包”，而是能支撑下面这些完整程序：

```text
CLI 工具：
  cli(Args) → config(Config) → fs(Path/File) → text(parse/format)
  → collections(List/Map) → log(Logger) → runtime(exit)

协议/字节处理：
  bytes(ByteReader/ByteWriter/Endian) → text(UTF-8/Regex)
  → collections → fs/io → errors(Result)

数据批处理：
  io/fs 读取 → text split/parse → collections sort/group
  → math 统计/checked → time(Duration/DateTime) → log

并发处理器：
  内建 TaskGroup/Task → Channel/Mutex/Atomic
  → errors(Cancelled/Timeout) → log/runtime
```

### 1.3 核心层明确不做什么

- 不做网络、HTTP、TLS、WebSocket（）。
- 不做数据库驱动、协议栈、Web 框架、模板引擎（ecosystem）。
- 不做完整正则引擎、完整 Unicode 大小写/规范化（ 或 X 子集）。
- 不做随机数、UUID、压缩、加密（）。
- 不做 UI、图形、图像、张量、线性代数（）。
- 不做硬实时、内核、裸机、手动内存管理。
- 不提供全局可变单例、隐式初始化/清理、线程局部隐式状态。

---

## 2. 跨包 API 契约（冻结）

### 2.1 失败通道

每个可能失败的公开方法只能属于以下一种：

| 通道 | 用法 |
| --- | --- |
| `Result<T, Error>` | 可恢复失败；错误分类用 `ErrorKind` |
| `Result<Unit, Error>` | 可恢复失败且没有成功值；禁止用 `void` 作成功类型 |
| 合同错误（panic/fatal） | 调用方违反前置条件：越界、非法 shift、负 count、重复 join 等 |
| 无失败 | 纯读取、纯值操作 |

规则：

- 不允许返回 `void` 却声明“非法参数 → InvalidArgument”。
- 不允许用 `null`、`0`、空串同时表示“缺失”和“合法值”。
- 不允许用 `throw` 表达文件不存在、解析失败、通道关闭等可恢复失败。
- `Option`/nullable 只用于“合法缺失”，不用于承载错误分类。

### 2.2 资源与关闭

- 持有 OS 资源的类必须提供显式 `close()`，`deinit` 不是唯一关闭路径。
- `close()` 幂等：第一次关闭后，第二次返回 `Ok(unit)`，不做事。
- 关闭失败与未关闭是两种状态：`Err` 只报告诊断，资源仍视为已释放。
- `AlreadyExists` 不用于重复 close；重复 close 不是错误。
- 资源类必须提供 `Bool isOpen()`；关闭后操作返回 `Unavailable`。

### 2.3 取消与超时

- 可阻塞方法首参为 `Context`；取消返回 `Err`，其 `kind() == Cancelled`。
- 超时是 deadline；超时返回 `Timeout`，不得伪装成 `Cancelled`。
- 取消后对象必须回到可预测状态：已关闭、未消费、未半写。
- `ErrorGroup.kind()` 遇到 `Cancelled` 必须返回 `Cancelled`，不得被其他错误掩盖。
- 内存操作、纯计算不接受 `Context`；长循环由调用方自行检查取消。

### 2.4 所有权与别名

| 种类 | 语义 |
| --- | --- |
| `class` | 引用语义；赋值共享句柄；持 OS 资源的类必须 `close()` |
| `struct` | 值语义；字段槽复制；引用字段浅复制 |
| 容器 | 持有元素引用；`remove/pop` 转移所有权 |
| 返回容器 | 明确是副本还是转移；`toBytes()` 返回副本，`takeBytes()` 转移 |
| 借用 | 方法参数默认借用；函数不得长期保留引用，除非文档声明 |
| 快照 | `keys()/values()/details()/causes()` 返回快照，不暴露内部可变结构 |

### 2.5 命名与命名空间

- 公开参数必须写全名：`text`、`prefix`、`separator`、`index`、`context`、`maximumBytes`。
- 方法用 lowerCamelCase 动词；布尔读取用 `isX`/`hasX`/`canX`。
- 类型 PascalCase；私有字段 `_name`；枚举成员 PascalCase。
- 同一包内不重载同名函数；跨包同名顶层函数必须消除冲突。
- 公开签名不得出现 `internal` 类型。

**核心层已发现的同名冲突与处理：**

| 名字 | 冲突包 | 处理 |
| --- | --- | --- |
| `isEmpty` | `bytes` / `text` | bytes 保留 `isEmptyBytes`；text 保留 `isEmpty` |
| `count` | `text` / `collections` | text 改为 `countText`；collections 改为 `countIf` |
| `flatten` | `errors` / `collections` | errors 改为 `flattenResult`；collections 改为 `flattenList` |
| `exists/readText/writeText` | `fs` / `sys` | 只保留在 `fs`；`sys` 删除文件便捷面 |
| `fileExists/readFileText/writeFileText` | `sys` / `fs` | 只保留 `fs`；`sys` 不再提供 |
| `fileMtime/pathJoin` | `fs` / `sys` | 归 `fs` |
| `platform` | `meta` / `sys` | `meta.targetPlatform()` 是构建目标；`sys.platform()` 是运行平台；语义分开，不得互换 |
| `env` | `sys` / `config` | `sys` 提供环境读取；`config.loadEnv` 只做白名单快照 |
| `nowMono/nowWall` | `runtime` / `time` | `runtime` 是原语；`time` 只做毫秒包装 |
| `sleep` | `time` / `tasks` | 归 `time`；任务取消通过 `Context` 传入 time 的取消版本 |
| `format` | `text` / `log` | `text.Format` 是格式化构造器；log 记录格式是内部实现 |

### 2.6 相等、排序与 Map 键

| 类型 | 相等 | 可否作为 Map 键 |
| --- | --- | --- |
| `Int/Long/Bool/Char/简单枚举` | 数值相等 | 可以 |
| `String` | 内容相等 | 可以 |
| `Double` | 64 位位模式相等 | 可以，但需明确 NaN/±0 |
| `Bytes` | `==` 是引用身份；值比较用 `equals` | 引用身份可作键，不推荐 |
| `class`/协议 | 引用身份 | 可以，但键生命周期由调用方保证 |
| `struct` | 字段值语义 | 可以，前提是字段可比较 |
| `List/Map/Set` | 引用身份 | 不推荐；可变对象不得作键 |

### 2.7 依赖方向

```text
L1 XDK public API
  ↑
L0 application

 包依赖（只允许向下）：
errors  runtime  meta
  ├─ bytes
  ├─ collections
  ├─ math
  ├─ text      → bytes
  ├─ time      → runtime
  ├─ io        → bytes
  ├─ fs        → io, bytes
  ├─ sys       → runtime, bytes
  ├─ log       → runtime, text, time
  ├─ config    → text, fs, sys
  └─ cli       → text, sys
```

规则：

-  不得依赖 /。
- 包依赖图必须无环。
- `fs` 不依赖 `sys`；`sys` 不依赖 `fs`。
- `time` 不依赖 `sys`；时间原语来自 `runtime`。
- `config` 不依赖 codec；结构化格式通过 X `ConfigSource` 注入。
- `xdk.internal.*` 不是公共 API，应用不得导入。

---

## 3. 包与类 API 面

> 记号：`K` = K，`X` = X，`` = 不属于核心层。  
> 稳定性：`stable` / `preview` / `internal`。  
> 方法表中的“失败”列只列可恢复失败；合同错误统一写“panic”。

---

### 3.1 `xdk.errors`

| 项 | 值 |
| --- | --- |
| 职责 | 错误分类、构造、包装、报告、聚合、Result 组合、稳定错误码映射 |
| 依赖 | L2 诊断；不依赖其他  包 |
| 被依赖 | 所有  包 |
| 稳定性 | 核心 `stable`；报告/聚合 `preview` |

#### 类型总览

| 类型 | 种类 | 能力 | 层级 | 稳定性 |
| --- | --- | --- | --- | --- |
| `ErrorKind` | enum | 14 类稳定失败分类 | K | stable |
| `Error` | protocol | 最小错误协议：`kind` + `describe` | K | stable |
| `DetailedError` | protocol | 带 `message`/`code` 的扩展错误协议 | K | stable |
| `ErrorDetail` | class | 不可变 key/value 诊断细节 | K | stable |
| `BasicError` | class | 基础错误实现，支持 code/details/causes | K | stable |
| `ErrorReport` | class | 给错误附加步骤链 | K | preview |
| `ErrorGroup` | class | 聚合多个错误，Cancelled 优先 | K | preview |

#### `ErrorKind`（enum，stable）

14 个成员，序号 0..13 固定，只允许追加：

`InvalidArgument`、`NotFound`、`AlreadyExists`、`PermissionDenied`、`Io`、`Network`、`Timeout`、`Cancelled`、`Busy`、`Unavailable`、`DataCorrupted`、`Unsupported`、`OutOfMemory`、`Internal`。

- 值语义，可比较，可作 Map 键。
- 不得由应用扩展；未知码映射 `Internal`，不得 panic 或静默成功。

#### `Error`（protocol，stable）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `kind` | `ErrorKind kind()` | 纯读取；生命周期内不变 |
| `describe` | `String describe()` | 单行、稳定、无换行/控制字符 |

- 只有 `class` 可以实现；`cause` 不是协议成员。

#### `DetailedError`（protocol，stable）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `kind` | `ErrorKind kind()` | 同 `Error` |
| `describe` | `String describe()` | 固定格式：`[code] KindName: message` 或 `KindName: message` |
| `message` | `String message()` | 非空、单行 |
| `code` | `String code()` | 空串或 `[a-z0-9_.-]+` |

- 独立协议，不继承 `Error`；实现类必须同时声明 `implements Error, DetailedError`。
- `details()`/`causes()` 是类方法，不在协议里。

#### `ErrorDetail`（class，stable）

- 表示：`final String key`、`final String value`。
- 不变量：key 非空且匹配 `[a-z0-9_.-]`；value 可为空但不能含换行/制表/控制字符。
- 生命周期：不可变；无 `close()`；可跨任务只读共享。
- 方法：仅构造器 `ErrorDetail(String key, String value)`；非法输入 panic。
- 外部输入用 `tryErrorDetail` 获取 `Result`。

#### `BasicError`（class，stable）

**能力**：基础错误值；支持 code、details、causes；`with*` 返回新实例。  
**不变量**：`kind` 非空；`message` 非空（空串按 kind 名生成）；`code` 为空或合法；`details/causes` 外部只拿快照；`causes` 不含 self，最多 8 条。  
**生命周期**：不可变；无 close；只读可跨任务共享。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `BasicError(ErrorKind kind, String message)` | 空 message 用 kind 显示名 | 无 |
| `kind` | `ErrorKind kind()` | 返回分类 | 无 |
| `message` | `String message()` | 返回消息 | 无 |
| `code` | `String code()` | 返回错误码/空串 | 无 |
| `describe` | `String describe()` | 单行描述 | 无 |
| `details` | `List<ErrorDetail> details()` | 快照 | 无 |
| `causes` | `List<BasicError> causes()` | 快照 | 无 |
| `withCode` | `BasicError withCode(String code)` | 返回带 code 的新实例 | 非法 code → panic |
| `withDetail` | `BasicError withDetail(String key, String value)` | 追加 detail 的新实例 | 非法 key/value → panic |
| `withCause` | `BasicError withCause(BasicError cause)` | 追加 cause 的新实例 | null/self → panic |

#### `ErrorReport`（class，preview）

**能力**：在根错误上记录“在哪一步失败”；不改变错误分类。  
**不变量**：root 非空；steps 最多 16 条；steps 返回快照。  
**生命周期**：不可变；无 close。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `ErrorReport(BasicError root)` | 根错误非空 | 无 |
| `kind/message/code/describe` | 同 `DetailedError` | 委托根错误；describe 带步骤链 | 无 |
| `details` | `List<ErrorDetail> details()` | 根 details 快照 | 无 |
| `causes` | `List<BasicError> causes()` | `[root]` | 无 |
| `steps` | `List<String> steps()` | 按加入顺序快照 | 无 |
| `withStep` | `ErrorReport withStep(String step)` | 追加步骤；16 条上限 | 非法/超限 → panic |
| `tryWithStep` | `Result<ErrorReport, Error> tryWithStep(String step)` | checked 版本 | `InvalidArgument` |

#### `ErrorGroup`（class，preview）

**能力**：一次返回多个失败；`Cancelled` 优先。  
**不变量**：只存 `BasicError`；空组 `kind() == InvalidArgument`；`details()` 键加 `<index>.` 前缀。  
**生命周期**：可变构建期；非线程安全；构建完成后只读共享需外部同步。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `ErrorGroup()` | 空组 | 无 |
| `add` | `void add(BasicError error)` | 追加；null/self 拒绝 | null/self → panic |
| `length` | `Int length()` | 数量 | 无 |
| `isEmpty` | `Bool isEmpty()` | 是否为空 | 无 |
| `first` | `BasicError? first()` | 首个；空 → null | 无 |
| `kind` | `ErrorKind kind()` | 有 Cancelled → Cancelled；否则首个非 Cancelled | 无 |
| `message` | `String message()` | `N errors; first: ...` | 无 |
| `code` | `String code()` | 恒为空串 | 无 |
| `describe` | `String describe()` | 单行摘要，最多 3 条 | 无 |
| `details` | `List<ErrorDetail> details()` | 聚合子 details | 无 |
| `causes` | `List<BasicError> causes()` | 子错误快照 | 无 |

#### 顶层函数

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `tryErrorDetail` | `Result<ErrorDetail, Error> tryErrorDetail(String key, String value)` | checked 构造 | `InvalidArgument` |
| `isValidDetailKey` | `Bool isValidDetailKey(String key)` | 校验 key | 无 |
| `isValidDetailValue` | `Bool isValidDetailValue(String value)` | 校验 value | 无 |
| `isValidErrorCode` | `Bool isValidErrorCode(String code)` | 校验 code | 无 |
| `wrap` | `Result<T, E> wrap<T, E>(Result<T, E> result, E error)` | 失败换新错误；成功原样 | 无 |
| `report` | `Result<T, Error> report<T>(Result<T, Error> result)` | 失败时诊断输出；返回原 Result | 无 |
| `isRetryable` | `Bool isRetryable(ErrorKind kind)` | Network/Timeout/Busy/Unavailable → true | 无 |
| `isRetryableError` | `Bool isRetryableError(Error error)` | 委托 kind | 无 |
| `errorKindName` | `String errorKindName(ErrorKind kind)` | 稳定小写名 | 无 |
| `errorKindDisplayName` | `String errorKindDisplayName(ErrorKind kind)` | 枚举显示名 | 无 |
| `errorKindFromName` | `Result<ErrorKind, Error> errorKindFromName(String name)` | 大小写不敏感 | `InvalidArgument` |
| `errorKindCode` | `Int errorKindCode(ErrorKind kind)` | 0..13 | 无 |
| `errorKindFromCode` | `ErrorKind errorKindFromCode(Int code)` | 未知 → Internal | 无 |
| `toErrorReport` | `ErrorReport toErrorReport(BasicError error)` | 创建报告 | 无 |
| `annotate` | `ErrorReport annotate(BasicError error, String step)` | 报告 + 一步 | 非法 step → panic |
| `mapOk` | `Result<U, E> mapOk<T, U, E>(Result<T, E> result, U(T) transform)` | Ok 映射 | 无 |
| `mapErr` | `Result<T, F> mapErr<T, E, F>(Result<T, E> result, F(E) transformError)` | Err 映射 | 无 |
| `andThen` | `Result<U, E> andThen<T, U, E>(Result<T, E> result, Result<U, E>(T) next)` | Ok 串联 | 无 |
| `unwrapOr` | `T unwrapOr<T, E>(Result<T, E> result, T fallback)` | Err 兜底 | 无 |
| `collectOk` | `Result<List<T>, ErrorGroup> collectOk<T>(List<Result<T, Error>> results)` | 全 Ok 收集；否则聚合 | 无 |
| `flattenResult` | `Result<T, E> flattenResult<T, E>(Result<Result<T, E>, E> nestedResult)` | 展平一层 | 无 |
| `check` | `Result<Unit, Error> check(Bool condition, ErrorKind kind, String message)` | 条件不成立返回 Err | 无 |

**X**：错误码命名空间工具（签名待定，不进入 1.0 API 面）；自定义 `DetailedError` 直接聚合（ 先转 `BasicError`）。

---

### 3.2 `xdk.runtime`

| 项 | 值 |
| --- | --- |
| 职责 | 诊断、退出、单调/墙钟、运行时信息 |
| 依赖 | 运行时服务（诊断/退出/时钟） |
| 被依赖 | 所有  包 |
| 稳定性 | K `stable`；X `preview` |

**K 没有公开 class；能力由顶层函数承载。**

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `diagnose` | `void diagnose(String message)` | 向 stderr 写一行诊断；不改变控制流 | 底层写失败不再抛错 |
| `exit` | `void exit(Int code)` | 以 0..255 退出码终止进程 | 非法 code 由调用方保证 |
| `nowMono` | `Long nowMono()` | 单调毫秒，用于耗时/超时 | 无 |
| `nowWall` | `Long nowWall()` | UNIX epoch 毫秒，可回拨 | 无 |

**X**：

| 类型/函数 | 签名 | 语义 |
| --- | --- | --- |
| `RuntimeInfo` | class | 语言/XDK/编译器版本、平台、架构、构建模式 |
| `runtimeInfo` | `RuntimeInfo runtimeInfo()` | 返回当前运行信息快照 |
| `dumpTasks` | `void dumpTasks()` | 诊断输出任务转储 |
| `taskStats` | `String taskStats()` | 返回任务统计文本 |
| `assert`/`fatal` | 边界 API | 断言失败/不可恢复错误的统一出口；不替代 `Result` |

`RuntimeInfo` 建议方法：`languageVersion()`、`xdkVersion()`、`targetPlatform()`、`architecture()`、`buildMode()`、`describe()`。

---

### 3.3 `xdk.meta`

| 项 | 值 |
| --- | --- |
| 职责 | 语言/XDK 版本、构建目标平台、构建信息 |
| 依赖 | 无（编译期常量） |
| 被依赖 | 诊断、日志、CLI、配置 |
| 稳定性 | K `stable`；X `preview` |

**K 没有公开 class。**

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `languageVersion` | `String languageVersion()` | 语言规范版本 `major.minor.patch` | 无 |
| `xdkVersion` | `String xdkVersion()` | XDK 版本 | 无 |
| `targetPlatform` | `String targetPlatform()` | 构建目标平台名；未知 → `"unknown"` | 无 |

**X**：

| 类型/函数 | 签名 | 语义 |
| --- | --- | --- |
| `BuildInfo` | class | 语言/XDK/编译器/平台/架构/模式 |
| `buildInfo` | `BuildInfo buildInfo()` | 构建元数据快照 |
| `targetCapabilities` | `List<String> targetCapabilities()` | 目标能力矩阵 |

`BuildInfo` 建议方法：`languageVersion()`、`xdkVersion()`、`targetPlatform()`、`architecture()`、`buildMode()`、`describe()`。

---

### 3.4 `xdk.bytes`

| 项 | 值 |
| --- | --- |
| 职责 | 字节序列、UTF-8/hex 转换、切片/比较、顺序读写、端序、位操作、可增长缓冲 |
| 依赖 | `xdk.errors` |
| 被依赖 | `text`、`io`、`fs`、`sys`、`log` |
| 稳定性 | K `stable`；X `preview` |

#### 类型总览

| 类型 | 种类 | 能力 | 层级 |
| --- | --- | --- | --- |
| `Bytes` | 运行时库类型 | 可变字节序列 | K |
| `ByteReader` | class | 带游标的严格/checked 读取 | K |
| `ByteWriter` | class | 追加写、定长整数写 | K |
| `ByteBuffer` | class | 随机定位读写、容量预留 | X |

#### `Bytes`（运行时库类型）

**表示**：可变、引用语义的字节序列；`length()` 以字节计。  
**不变量**：`0 <= length`；索引合法域 `[0, length-1]`；无 OS 资源、无 close。  
**相等**：`==` 是引用身份；值比较用 `equals`/`compare`。

| 成员 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `length` | `Int length()` | 字节数 | 无 |
| `get` | `Int get(Int index)` | 返回 0..255 | 越界 → panic |
| `set` | `void set(Int index, Int value)` | 写入低 8 位 | 越界 → panic |
| `push` | `void push(Int value)` | 追加低 8 位 | 无 |

> `Bytes.slice` 若是运行时成员，仅作为内部实现；公共 API 用顶层 `slice`。文档和示例不得同时暴露两套语义。

**顶层函数**：

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `fromUtf8` | `Bytes fromUtf8(String text)` | UTF-8 编码 | 无 |
| `toUtf8` | `String toUtf8(Bytes source)` | 解码；非法字节替换 U+FFFD | 无 |
| `fromHex` | `Bytes fromHex(String hexadecimal)` | 严格 hex 解码 | 非法/奇数长度 → panic |
| `tryFromHex` | `Result<Bytes, Error> tryFromHex(String hexadecimal)` | checked hex | `InvalidArgument` |
| `toHex` | `String toHex(Bytes source)` | 小写 hex | 无 |
| `byteLength` | `Int byteLength(Bytes source)` | 字节数 | 无 |
| `isEmptyBytes` | `Bool isEmptyBytes(Bytes source)` | 是否为空 | 无 |
| `concatBytes` | `Bytes concatBytes(Bytes first, Bytes second)` | 新序列拼接 | 无 |
| `copy` | `Bytes copy(Bytes source)` | 独立副本 | 无 |
| `equals` | `Bool equals(Bytes left, Bytes right)` | 长度 + 逐字节相等 | 无 |
| `compare` | `Int compare(Bytes left, Bytes right)` | 字典序 <0/0/>0 | 无 |
| `slice` | `Bytes slice(Bytes source, Int startIndex, Int endIndex)` | 钳制范围，返回副本 | 无 |
| `sliceChecked` | `Result<Bytes, Error> sliceChecked(Bytes source, Int startIndex, Int endIndex)` | 严格范围 | `InvalidArgument` |
| `tryGetByte` | `Result<Int, Error> tryGetByte(Bytes source, Int index)` | checked 读取 | `InvalidArgument` |
| `trySetByte` | `Result<Unit, Error> trySetByte(Bytes target, Int index, Int value)` | checked 写入 | `InvalidArgument` |

#### `ByteReader`（class，K）

**表示**：`Bytes _source` + `Int _position`；`0 <= _position <= length`。  
**生命周期**：无资源、无 close；需要重置时新建。  
**并发**：非线程安全；读取期间调用方不得修改源。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `ByteReader(Bytes source)` | 位置 0 | 无 |
| `position` | `Int position()` | 当前游标 | 无 |
| `remaining` | `Int remaining()` | `length - position` | 无 |
| `hasRemaining` | `Bool hasRemaining()` | 是否还有字节 | 无 |
| `seek` | `Result<Unit, Error> seek(Int offset)` | 设置游标；失败位置不变 | `InvalidArgument` |
| `readU8` | `Int readU8()` | 读 1 字节并前进 | EOF → panic |
| `tryReadU8` | `Result<Int, Error> tryReadU8()` | checked 读 1 字节 | `DataCorrupted` |
| `shortBE/LE` | `Int shortBE()` / `Int shortLE()` | 读 2 字节无符号 | 不足 → panic |
| `tryShortBE/LE` | `Result<Int, Error> ...` | checked 2 字节 | `DataCorrupted` |
| `intBE/LE` | `Long intBE()` / `Long intLE()` | 读 4 字节无符号（0..4294967295） | 不足 → panic |
| `tryIntBE/LE` | `Result<Long, Error> ...` | checked 4 字节 | `DataCorrupted` |
| `longBE/LE` | `Long longBE()` / `Long longLE()` | 读 8 字节位模式 | 不足 → panic |
| `tryLongBE/LE` | `Result<Long, Error> ...` | checked 8 字节 | `DataCorrupted` |
| `readBytes` | `Bytes readBytes(Int count)` | 钳制读取，返回副本 | 负 count → panic |
| `readExact` | `Result<Bytes, Error> readExact(Int count)` | 恰好读取；失败位置不变 | `DataCorrupted`；负 count → panic |

#### `ByteWriter`（class，K）

**表示**：内部只追加的字节序列。  
**生命周期**：无资源、无 close。  
**并发**：非线程安全。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `ByteWriter()` | 空 writer | 无 |
| `length` | `Int length()` | 当前长度 | 无 |
| `toBytes` | `Bytes toBytes()` | 当前内容副本 | 无 |
| `takeBytes` | `Bytes takeBytes()` | 转移内部序列并清空 | 无 |
| `writeU8` | `void writeU8(Int value)` | 追加低 8 位 | 无 |
| `writeBytes` | `void writeBytes(Bytes source)` | 追加副本 | 无 |
| `writeU16BE/LE` | `void writeU16BE(Int value)` 等 | 2 字节端序 | 越界 → panic |
| `writeU32BE/LE` | `void writeU32BE(Long value)` 等 | 4 字节端序 | 越界 → panic |
| `writeU64BE/LE` | `void writeU64BE(Long value)` 等 | 8 字节位模式 | 无 |
| `clear` | `void clear()` | 长度归零，容量保留 | 无 |

#### `ByteBuffer`（class，X）

**能力**：可增长缓冲，支持追加与定位读写；不暴露裸内存。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 工厂 | `ByteBuffer byteBufferFrom(Bytes initialContent)` | 复制初始内容 | 无 |
| 构造 | `ByteBuffer()` | 空缓冲 | 无 |
| `length` | `Int length()` | 当前长度 | 无 |
| `capacity` | `Int capacity()` | 当前容量 | 无 |
| `toBytes` | `Bytes toBytes()` | 内容副本 | 无 |
| `push` | `void push(Int value)` | 追加低 8 位 | 无 |
| `append` | `void append(Bytes source)` | 追加副本 | 无 |
| `put` | `Result<Unit, Error> put(Int index, Int value)` | 定位写 | `InvalidArgument` |
| `get` | `Result<Int, Error> get(Int index)` | 定位读 | `InvalidArgument` |
| `clear` | `void clear()` | 长度 0，容量保留 | 无 |
| `reserve` | `void reserve(Int minimumCapacity)` | 容量至少为指定值 | 负值 → panic |

#### `Endian`（函数组，K）

`u16BE/u16LE`、`u32BE/u32LE`、`u64BE/u64LE`；
`readShortBE/LE`、`readIntBE/LE`、`readLongBE/LE`；
`tryReadShortBE/LE`、`tryReadIntBE/LE`、`tryReadLongBE/LE`。

- 写函数要求值在范围内；越界 panic。
- 读函数要求 `offset + size <= length`；越界 panic。
- checked 版本返回 `Result`，越界 `InvalidArgument`。
- `u32/readInt` 用 `Long` 承载无符号 32 位。
- 不提供宿主端序隐式默认。

#### `Bits`（函数组，K）

32 位：`bitAnd`、`bitOr`、`bitXor`、`bitNot`、`shiftLeft`、`shiftRight`、`popCount`、`leadingZeros`、`trailingZeros`。
64 位：`shiftLeftLong`、`shiftRightLong`、`popCountLong`、`leadingZerosLong`、`trailingZerosLong`。

- 移位量必须 `0 <= count < 32`（或 `< 64`）；越界 panic。
- 位操作不隐式提升；`Int` 与 `Long` 显式选择。

---

### 3.5 `xdk.text`

| 项 | 值 |
| --- | --- |
| 职责 | 文本查找/变换/填充/解析/格式化、Unicode、正则 |
| 依赖 | `xdk.errors`、`xdk.bytes` |
| 被依赖 | `log`、`config`、`cli`、`codec`（） |
| 稳定性 | K `stable`；X `preview` |

#### 类型总览

| 类型 | 种类 | 能力 | 层级 |
| --- | --- | --- | --- |
| `Format` | class | 链式宽度/填充格式化 | K |
| `Regex` | class | 编译后的正则；匹配/查找/替换/切分 | K（编译/匹配）/ X（其余） |
| `Match` | class | 单个匹配结果与捕获组 | X |
| `Utf16` | class | UTF-16 码元序列包装 | X |
| `StringBuilder` | class | 可变字符串构建器 | X |

#### `Format`（class，K）

**能力**：`Format.int(7).width(4).pad('0').build()`；只做左填充，不实现 printf 全格式。  
**生命周期**：不可变链式构造；无 close；非线程安全（值对象）。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `int` | `static Format int(Int value)` | 整数格式化起点 | 无 |
| `float` | `static Format float(Double value)` | 浮点格式化起点 | 无 |
| `string` | `static Format string(String value)` | 字符串起点 | 无 |
| `bool` | `static Format bool(Bool value)` | 布尔起点 | 无 |
| `width` | `Format width(Int width)` | 目标宽度；`width < 0` panic | panic |
| `pad` | `Format pad(Char padding)` | 填充字符 | 无 |
| `build` | `String build()` | 左侧填充到 width | 无 |

**X**：`alignLeft`/`alignRight`、`precision`、符号/千分位等；不进入 K。

#### `Regex`（class，K/X）

**能力**：编译后的不可变正则；K 支持 `isMatch`，X 支持查找/替换/切分。  
**创建**：公共工厂 `regexCompile(String pattern)`；构造函数不作为公共入口。  
**生命周期**：不可变；无 close；可跨任务只读共享。  
**索引**：字节索引，不是 Unicode 码点索引。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `isMatch` | `Bool isMatch(String text)` | 是否存在匹配 | 无 |
| `find` | `Match? find(String text)` | 首个匹配；无 → null | 无 |
| `findAll` | `List<Match> findAll(String text)` | 全部非空匹配 | 无 |
| `replaceAll` | `String replaceAll(String text, String replacement)` | 替换全部非空匹配 | 无 |
| `split` | `List<String> split(String text)` | 按非空匹配切分 | 无 |
| `pattern` | `String pattern()` | 原始模式 | 无 |

**K 正则子集**：POSIX ERE 子集；编译失败返回 `InvalidArgument`，不 panic。

#### `Match`（class，X）

**能力**：单个匹配结果；`group(0)` 为整匹配，`group(i>=1)` 为捕获组。  
**不变量**：`0 <= start <= end <= text.length`；groups 快照。  
**生命周期**：不可变；无 close。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `start` | `Int start()` | 起始字节索引 | 无 |
| `end` | `Int end()` | 结束字节索引（不含） | 无 |
| `length` | `Int length()` | `end - start` | 无 |
| `group` | `String group(Int index)` | 捕获组；未捕获为空串 | 越界 → panic |
| `groups` | `List<String> groups()` | 捕获组快照 | 无 |

#### `Utf16`（class，X）

**能力**：UTF-16 码元序列包装，避开 `Result<List<...>>` 的类型折叠。  
**生命周期**：不可变；无 close。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Utf16(List<UInt16> units)` | 包装码元序列 | 无 |
| `length` | `Int length()` | 码元数 | 无 |
| `get` | `UInt16 get(Int index)` | 取码元 | 越界 → panic |
| `units` | `List<UInt16> units()` | 快照 | 无 |

#### `StringBuilder`（class，X）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `StringBuilder()` | 空 builder | 无 |
| `append` | `StringBuilder append(String text)` | 追加文本 | 无 |
| `appendChar` | `StringBuilder appendChar(Char character)` | 追加字符 | 无 |
| `appendInt` | `StringBuilder appendInt(Int value)` | 追加整数 | 无 |
| `appendLine` | `StringBuilder appendLine(String text)` | 追加文本 + 换行 | 无 |
| `length` | `Int length()` | 当前长度 | 无 |
| `clear` | `void clear()` | 清空 | 无 |
| `build` | `String build()` | 生成字符串 | 无 |

#### 顶层函数

**判断/查找**

| 函数 | 签名 | 语义 |
| --- | --- | --- |
| `contains` | `Bool contains(String text, String searchText)` | 是否包含子串 |
| `startsWith` | `Bool startsWith(String text, String prefix)` | 前缀 |
| `endsWith` | `Bool endsWith(String text, String suffix)` | 后缀 |
| `indexOf` | `Int indexOf(String text, String searchText)` | 首次位置；无 → -1 |
| `lastIndexOf` | `Int lastIndexOf(String text, String searchText)` | 末次位置；无 → -1 |
| `countText` | `Int countText(String text, String searchText)` | 非重叠出现次数（原 `count` 改名） |
| `isEmpty` | `Bool isEmpty(String text)` | 空串 |
| `isBlank` | `Bool isBlank(String text)` | 全空白 |
| `equalsIgnoreCase` | `Bool equalsIgnoreCase(String left, String right)` | 忽略大小写 |
| `isDigit` | `Bool isDigit(String text)` | 单字符数字 |
| `isAlpha` | `Bool isAlpha(String text)` | 单字符字母 |
| `isAlnum` | `Bool isAlnum(String text)` | 单字符字母数字 |
| `isSpace` | `Bool isSpace(String text)` | 单字符空白 |
| `isUpper` | `Bool isUpper(String text)` | 单字符大写 |
| `isLower` | `Bool isLower(String text)` | 单字符小写 |
| `isHexDigit` | `Bool isHexDigit(String text)` | 单字符 hex |

**变换**

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `trim` | `String trim(String text)` | 去首尾空白 | 无 |
| `trimStart` | `String trimStart(String text)` | 去首部空白 | 无 |
| `trimEnd` | `String trimEnd(String text)` | 去尾部空白 | 无 |
| `split` | `List<String> split(String text, String separator)` | 分段；空 separator 不分段 | 无 |
| `replace` | `String replace(String text, String searchText, String replacementText)` | 字面量替换 | 无 |
| `reverse` | `String reverse(String text)` | 反转 | 无 |
| `capitalize` | `String capitalize(String text)` | 首字母大写 | 无 |
| `truncate` | `String truncate(String text, Int maximumBytes)` | 截断到最大字节数 | 负值 → panic |
| `padLeft` | `String padLeft(String text, Int width, String padding)` | 左填充 | 负 width → panic |
| `padRight` | `String padRight(String text, Int width, String padding)` | 右填充 | 负 width → panic |
| `repeatText` | `String repeatText(String text, Int repetitions)` | 重复 | 负值 → panic |
| `repeatJoined` | `String repeatJoined(String text, String separator, Int repetitions)` | 带分隔符重复 | 负值 → panic |

**解析/格式化**

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `parseInt` | `Result<Int, Error> parseInt(String text)` | 十进制、全串消费、32 位 | `InvalidArgument` |
| `parseFloat` | `Result<Double, Error> parseFloat(String text)` | 十进制/小数/指数、全串消费 | `InvalidArgument` |
| `formatInt` | `Format formatInt(Int value)` | 整数 Format 起点 | 无 |
| `formatFloat` | `Format formatFloat(Double value)` | 浮点 Format 起点 | 无 |
| `formatString` | `Format formatString(String value)` | 字符串 Format 起点 | 无 |
| `formatBool` | `Format formatBool(Bool value)` | 布尔 Format 起点 | 无 |

**Unicode / 正则**

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `utf8ToUtf16` | `Result<Utf16, Error> utf8ToUtf16(Bytes source)` | UTF-8 → UTF-16 | `DataCorrupted` |
| `utf16ToUtf8` | `Result<Bytes, Error> utf16ToUtf8(List<UInt16> units)` | UTF-16 → UTF-8 | `DataCorrupted` |
| `codePoints` | `List<Int> codePoints(String text)` | 码点序列 | 无 |
| `codePointAt` | `Int codePointAt(String text, Int byteIndex)` | 指定字节位置的码点 | 越界/非法 → panic |
| `codePointLen` | `Int codePointLen(String text, Int byteIndex)` | 该码点字节长度 | 越界/非法 → panic |
| `fromCodePoint` | `String fromCodePoint(Int codePoint)` | 码点转字符串 | 非法 → panic |
| `decodeCodePoint` | `Int decodeCodePoint(String text, Int byteIndex)` | 解码一个码点 | 非法 → panic |
| `regexCompile` | `Result<Regex, Error> regexCompile(String pattern)` | 编译正则 | `InvalidArgument` |

**X**：`parseLong`、完整 Unicode 大小写/规范化、转义/反转义工具、完整 layout/格式。

**内部类型（internal，不属于公共 API）**：`RegexTree`、`RegexParser`、`RegexMatcher`、`RegexMatchState`。它们只服务 `Regex` 实现，可随实现变更。

---

### 3.6 `xdk.collections`

| 项 | 值 |
| --- | --- |
| 职责 | 序列、映射、集合、排序/查找/聚合算法、专用容器 |
| 依赖 | `xdk.errors` |
| 被依赖 | 业务包、`text`/`codec`/`config`/`cli` |
| 稳定性 | K `stable`；X `preview` |

#### 类型总览

| 类型 | 种类 | 能力 | 层级 |
| --- | --- | --- | --- |
| `List<T>` | 语言容器 | 有序、可重复、按索引 | K |
| `Map<K,V>` | 语言容器 | 键唯一、查找/替换/删除/快照 | K |
| `Set<T>` | 语言容器 | 元素唯一、成员判断 | K |
| `Pair` | class | `Map<String,Int>.entries` 的值对象 | K |
| `IntPair` | class | `Map<Int,Int>.entries` 的值对象 | K |
| `PriorityQueue<T>` | class | 最小堆 | K |
| `RingBuffer<T>` | class | 固定容量环形缓冲 | K |
| `OrderedMap<V>` | class | Int 键、插入序映射 | X |
| `BTreeMap<V>` | class | Int 键、键升序映射 | X |

#### `List<T>`（语言容器，K）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `length` | `Int length()` | 元素数 | 无 |
| `get` | `T get(Int index)` | 借用元素 | 越界 → panic |
| `tryGet` | `Result<T, Error> tryGet(Int index)` | checked | `InvalidArgument` |
| `set` | `void set(Int index, T value)` | 替换 | 越界 → panic |
| `trySet` | `Result<Unit, Error> trySet(Int index, T value)` | checked | `InvalidArgument` |
| `push` | `void push(T value)` | 末尾追加 | 无 |
| `insert` | `void insert(Int index, T value)` | 插入；`index == length` 允许 | 越界 → panic |
| `tryInsert` | `Result<Unit, Error> tryInsert(Int index, T value)` | checked | `InvalidArgument` |
| `remove` | `T remove(Int index)` | 删除并返回 | 越界 → panic |
| `tryRemove` | `Result<T, Error> tryRemove(Int index)` | checked | `InvalidArgument` |
| `clear` | `void clear()` | 清空 | 无 |

- 引用类型；`==` 是引用身份。
- 遍历期间禁止结构性修改；`set` 替换允许。
- 元素类型 K 覆盖 `Int`、`String`；其他类型按运行时能力，未验证前不承诺。

#### `Map<K,V>`（语言容器，K）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `length` | `Int length()` | 键数 | 无 |
| `has` | `Bool has(K key)` | 是否存在 | 无 |
| `getOr` | `V getOr(K key, V fallback)` | 存在 → 值；否则 fallback；不插入 | 无 |
| `tryGet` | `Result<V, Error> tryGet(K key)` | 缺失 → NotFound | `NotFound` |
| `put` | `Bool put(K key, V value)` | 替换 → true；插入 → false | 无 |
| `remove` | `Bool remove(K key)` | 删除 → true；不存在 → false | 无 |
| `removeOr` | `V removeOr(K key, V fallback)` | 删除并返回旧值；无 → fallback | 无 |
| `keys` | `List<K> keys()` | 快照；顺序不承诺 | 无 |
| `values` | `List<V> values()` | 快照 | 无 |
| `entries` | `List<Pair>` / `List<IntPair>` | 快照；K 仅两种 | 无 |
| `clear` | `void clear()` | 清空 | 无 |

**冻结说明**：

- `put`/`remove` 返回 `Bool`，不返回旧值；需要旧值先 `getOr`/`tryGet`。
- 旧文档 §5.2 的“返回 `Int?`”作废；统一按本表。
- 泛型 `Map<K,V>` 的键/值类别见 §2.6；可空 `V` 不作为“无旧值”的双重含义。
- `entries()` 的任意 K/V 值对象是 X；K 只支持 `Pair`/`IntPair`。

#### `Set<T>`（语言容器，K）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `length` | `Int length()` | 元素数 | 无 |
| `has` | `Bool has(T value)` | 是否存在 | 无 |
| `add` | `Bool add(T value)` | 新增 → true；已存在 → false | 无 |
| `remove` | `Bool remove(T value)` | 删除 → true；不存在 → false | 无 |
| `clear` | `void clear()` | 清空 | 无 |

- `Set.of(...)` 是编译器脱糖；重复元素“后者忽略”。
- 元素相等规则同 §2.6。

#### `Pair` / `IntPair`（class，K）

| 类型 | 字段 | 构造 |
| --- | --- | --- |
| `Pair` | `String first`、`Int second` | `Pair(String first, Int second)` |
| `IntPair` | `Int first`、`Int second` | `IntPair(Int first, Int second)` |

-  作为 class 载体，字段公开只读；值语义按约定，不作为 `Map` 键的推荐类型。
- X 若 `List<struct>` 完整支持，可迁移为 `struct`。

#### `PriorityQueue<T>`（class，K）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `PriorityQueue(Bool(T, T) lessThan)` | 创建空最小堆 | null/非严格弱序 → panic |
| `length` | `Int length()` | 元素数 | 无 |
| `isEmpty` | `Bool isEmpty()` | 是否为空 | 无 |
| `push` | `void push(T value)` | 插入并上浮 | 无 |
| `peek` | `T? peek()` | 堆顶；空 → null | 无 |
| `pop` | `T? pop()` | 移除并返回堆顶；空 → null | 无 |
| `clear` | `void clear()` | 清空 | 无 |

- 不稳定；相等优先级顺序不承诺。
- `lessThan` 必须满足严格弱序。

#### `RingBuffer<T>`（class，K）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `RingBuffer(Int capacity)` | 固定容量 | `capacity <= 0` → panic |
| `length` | `Int length()` | 当前元素数 | 无 |
| `capacity` | `Int capacity()` | 容量 | 无 |
| `isEmpty` | `Bool isEmpty()` | 是否为空 | 无 |
| `isFull` | `Bool isFull()` | 是否已满 | 无 |
| `push` | `Bool push(T value)` | 未满写入 true；满 false 且不写入 | 无 |
| `pop` | `T? pop()` | 取最旧；空 → null | 无 |
| `peek` | `T? peek()` | 看最旧；空 → null | 无 |
| `clear` | `void clear()` | 清空 | 无 |

- 满时行为冻结为“返回 false，不覆盖”；不提供覆盖模式。
- 容量构造后不变。

#### `OrderedMap<V>`（class，X）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `length` | `Int length()` | 键数 |
| `has` | `Bool has(Int key)` | 是否存在 |
| `get` | `V? get(Int key)` | 缺失 → null |
| `getOr` | `V getOr(Int key, V fallback)` | 缺失 → fallback |
| `put` | `Bool put(Int key, V value)` | 替换 true / 插入 false |
| `remove` | `Bool remove(Int key)` | 删除 true / 不存在 false |
| `keys` | `List<Int> keys()` | 插入序快照 |
| `values` | `List<V> values()` | 插入序快照 |
| `clear` | `void clear()` | 清空 |

#### `BTreeMap<V>`（class，X）

与 `OrderedMap<V>` 同方法面，但 `keys()` 按键升序；查找 O(log n)，插入/删除首版 O(n)。

#### 算法（K）

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `sortBy` | `List<T> sortBy<T>(List<T> items, Bool(T, T) lessThan)` | 原地稳定排序，返回同一列表 | 无 |
| `sortedBy` | `List<T> sortedBy<T>(List<T> items, Bool(T, T) lessThan)` | 返回新列表 | 无 |
| `isSortedBy` | `Bool isSortedBy<T>(List<T> items, Bool(T, T) lessThan)` | 是否已排序 | 无 |
| `binarySearchBy` | `Int binarySearchBy<T>(List<T> items, T target, Int(T, T) compare)` | 找到返回索引；否则 `-(插入点+1)` | 无 |
| `find` | `T? find<T>(List<T> items, Bool(T) predicate)` | 首个满足；无 → null | 无 |
| `findIndex` | `Int? findIndex<T>(List<T> items, Bool(T) predicate)` | 首个下标；无 → null | 无 |
| `dedup` | `List<T> dedup<T>(List<T> items, Bool(T, T) equals)` | 保序去重 | 无 |
| `any` | `Bool any<T>(List<T> items, Bool(T) predicate)` | 任一满足 | 无 |
| `all` | `Bool all<T>(List<T> items, Bool(T) predicate)` | 全部满足 | 无 |
| `countIf` | `Int countIf<T>(List<T> items, Bool(T) predicate)` | 满足个数（原 `count` 改名） | 无 |
| `reduce` | `T reduce<T>(List<T> items, T initialValue, T(T, T) combine)` | 左折叠 | 无 |
| `partition` | `Pair<List<T>, List<T>> partition<T>(List<T> items, Bool(T) predicate)` | 满足/不满足两组，保序 | 无 |
| `chunks` | `List<List<T>> chunks<T>(List<T> items, Int chunkSize)` | 分块；末块可短 | `chunkSize <= 0` → panic |
| `windows` | `List<List<T>> windows<T>(List<T> items, Int windowSize)` | 滑动窗口 | `windowSize <= 0` → panic |
| `zip` | `List<Pair> zip<A, B>(List<A> left, List<B> right)` | 取较短长度 | 无 |
| `flattenList` | `List<T> flattenList<T>(List<List<T>> nestedItems)` | 展平一层（原 `flatten` 改名） | 无 |
| `join` | `String join(List<String> items, String separator)` | 拼接字符串列表 | 无 |

**X**：`groupBy`/`groupByInt`、`Map.entries` 任意 K/V、`OrderedMap`/`BTreeMap`、`Iterator<T>`（）。

---

### 3.7 `xdk.math`

| 项 | 值 |
| --- | --- |
| 职责 | 常量、取整/比较、幂/对数、三角、插值、数论、checked/saturating、Int128、组合、统计 |
| 依赖 | `xdk.errors` |
| 被依赖 | `time`、`stats`（）、`metrics`（） |
| 稳定性 | `preview` |

**K 没有公开 class；`Int128` 是语言标量，不是 class。**  
`Int128` 支持宽字面量、四则/比较、`print`/`str`、函数参数/返回值、`Result<Int128,Error>`；不提供方法面，运算由语言和顶层 checked 函数承载。

#### 函数组

| 组 | 代表函数 | 语义/失败 |
| --- | --- | --- |
| 常量 | `PI()`、`E()`、`TAU()`、`Inf()`、`NaN()` | 无失败 |
| 分类 | `isNaN(Double)`、`isInf(Double)`、`sign(Double)` | 无失败 |
| 取绝对值/比较 | `abs(Double)`、`absI(Int)`、`min/max(Double,Double)`、`minI/maxI(Int,Int)`、`clamp/clampI` | 无失败 |
| 取整 | `floor/ceil/round/trunc(Double)`、`floorToInt/ceilToInt/roundToInt/truncToInt` | 无失败 |
| 幂/指数/对数 | `pow`、`sqrt`、`cbrt`、`exp`、`log`、`log2`、`log10` | IEEE 754；域错误返回 NaN/Inf |
| 三角 | `sin/cos/tan/asin/acos/atan/atan2`、`sinh/cosh/tanh`、`deg2rad/rad2deg` | 无失败 |
| 插值 | `lerp`、`mapRange` | 无失败 |
| 数论 | `gcd`、`lcm`、`isPrime`、`factorial` | `factorial` 负数/超 32 位 → `InvalidArgument` |
| Int128 | `int128Min/Max`、`add/sub/mul/div/mod/neg/absI128Checked` | 溢出/除零 → `InvalidArgument` |
| Int/Long | `max/minIntValue`、`max/minLongValue`、`add/sub/mul/div/mod/neg/abs` checked、`add/sub/mul` saturating | 溢出/除零 → `InvalidArgument`；saturating 钳制 |
| 组合 | `permutations`、`combinations` | 参数非法/超 Long → `InvalidArgument` |
| 统计 | `sum/mean/median/variance/stddev/quantile` | 空列表规则：sum=0，mean/median=NaN；quantile q 钳制 [0,1] |

**规则**：

- `Int` 32 位、`Long` 64 位；溢出按位宽回绕；需要安全运算用 checked/saturating。
- `mod` 的结果符号固定为与除数同号；`Int128` 的 `/`/`%` 与 C 一致（商向零截断，余数跟随被除数）。
- `sqrt(-1)`、`log(-1)` 返回 NaN/Inf，不 panic。
- `factorial` 只保证 32 位结果；`n > 12` 返回 `InvalidArgument`。

**X/**：`random`（）、`stats`（）、任意精度、矩阵/张量（）。

---

### 3.8 `xdk.time`

| 项 | 值 |
| --- | --- |
| 职责 | 时钟、时长、时间点、UTC 日历、格式化/解析 |
| 依赖 | `xdk.runtime`、`xdk.errors` |
| 被依赖 | `log`、`config`、`metrics`（） |
| 稳定性 | `preview` |

#### 类型总览

| 类型 | 种类 | 能力 | 层级 |
| --- | --- | --- | --- |
| `Duration` | class | 毫秒精度时长 | K |
| `DateTime` | class | UTC epoch 毫秒 + 日历派生 | K |
| `Civil` | class | 年月日值对象 | K |
| `TimeZone` | class | 时区偏移/规则 | X |
| `Stopwatch` | class | 单调计时器 | X |

#### `Duration`（class，K）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Duration(Long milliseconds)` | 毫秒精度；允许负值 | 无 |
| `millis` | `Long millis()` | 毫秒 | 无 |
| `seconds` | `Long seconds()` | 秒（截断） | 无 |
| `micros` | `Long micros()` | 微秒（乘 1000，不增加精度） | 无 |
| `plus` | `Duration plus(Duration other)` | 相加；溢出按 Long 回绕 | 无 |
| `minus` | `Duration minus(Duration other)` | 相减 | 无 |

- 无 close；值对象；非线程安全。
- 不支持 `Duration` 作为 Map 键的推荐类型（无值相等协议）。

#### `DateTime`（class，K）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `DateTime(Long epochMillis)` | UTC epoch 毫秒 |
| `timestamp` | `Long timestamp()` | epoch 毫秒 |
| `civil` | `Civil civil()` | UTC 年月日 |
| `year/month/day` | `Int year()` 等 | 日历字段 |
| `hour/minute/second/millisecond` | `Int ...()` | 时间字段 |
| `weekday` | `Int weekday()` | 0=周日 … 6=周六 |
| `dayOfYear` | `Int dayOfYear()` | 1..366 |
| `add` | `DateTime add(Duration duration)` | 加时长 |
| `diff` | `Duration diff(DateTime other)` | 时间差 |
| `before/after` | `Bool before(DateTime other)` 等 | 比较 |
| `compare` | `Int compare(DateTime other)` | <0/0/>0 |
| `toUTC` | `DateTime toUTC()` |  直通（仅 UTC） |
| `toLocal` | `DateTime toLocal()` |  直通；不静默改变输出 |
| `format` | `String format(String layout)` | 令牌：`yyyy MM dd HH mm ss SSS` |
| `iso8601` | `String iso8601()` | ISO 8601 |
| `rfc3339` | `String rfc3339()` | RFC 3339（UTC `Z`） |

**不变量**：内部统一 UTC epoch 毫秒；所有 epoch/毫秒运算必须用 `Long`，不得 `as Int` 截断。  
**生命周期**：不可变值对象；无 close；可跨任务只读共享。

#### `Civil`（class，K）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `Civil(Int year, Int month, Int day)` | 年月日 |
| 字段 | `year`、`month`、`day` | 只读值 |

- 只表示公历年月日；不携带时区/时间。
- 与 `DateTime` 的转换由 `civil()`/`dateTimeOf()` 承载。

#### 顶层函数

| 函数 | 签名 | 语义 |
| --- | --- | --- |
| `nowMs` | `Long nowMs()` | 单调毫秒 |
| `nowWallMs` | `Long nowWallMs()` | UNIX epoch 毫秒 |
| `millis` | `Long millis()` | 单调毫秒别名 |
| `micros` | `Long micros()` | 原始微秒 |
| `sleepMs` | `void sleepMs(Long milliseconds)` | 阻塞休眠； 不可取消 |
| `sleep` | `void sleep(Duration duration)` | 阻塞休眠 |
| `durationOfMillis/Seconds/Minutes/Hours/Days` | `Duration durationOfMillis(Long value)` 等 | 构造 Duration |
| `dateTimeOf` | `DateTime dateTimeOf(Int year, Int month, Int day, Int hour, Int minute, Int second)` | 构造 UTC 时间 |
| `dateTimeOfMs` | `DateTime dateTimeOfMs(Int year, Int month, Int day, Int hour, Int minute, Int second, Int millisecond)` | 带毫秒 |
| `dateTimeFromTimestamp` | `DateTime dateTimeFromTimestamp(Long epochMillis)` | 从 epoch 构造 |
| `now` | `DateTime now()` | 当前墙钟 |
| `parseDateTime` | `Result<DateTime, Error> parseDateTime(String text)` | ISO 8601 解析 |
| `civilIsLeap` | `Bool civilIsLeap(Int year)` | 闰年 |
| `civilDaysInMonth` | `Int civilDaysInMonth(Int year, Int month)` | 月天数 |

**X**：

| 类型/函数 | 签名 | 语义 |
| --- | --- | --- |
| `TimeZone` | class | `TimeZone.utc()`、`TimeZone.fixed(Int offsetMillis)`、`id()`、`offsetMillis()` |
| `DateTime.toZone` | `DateTime toZone(TimeZone zone)` | 时区转换 |
| `Stopwatch` | class | `start()`、`elapsedMillis()`、`reset()` |
| `sleep` 取消版 | `Result<Unit, Error> sleep(Context context, Duration duration)` | 可取消休眠 |
| 完整布局 | `parseDateTime`/`format` 全量 | 日历加减、完整 strftime 子集 |

---

### 3.9 `xdk.io`

| 项 | 值 |
| --- | --- |
| 职责 | 流与内存 I/O：顺序读、顺序写、缓冲、组合、stdio |
| 依赖 | `xdk.bytes`、`xdk.errors` |
| 被依赖 | `fs`、`sys`、`log`、`config` |
| 稳定性 | `preview` |

#### 类型总览

| 类型 | 种类 | 能力 | 层级 |
| --- | --- | --- | --- |
| `Reader` | class | 顺序读字节 | K |
| `Writer` | class | 顺序写字节 | K |
| `BufferedReader` | class | 带缓冲读取 | X |
| `BufferedWriter` | class | 带缓冲写入 | X |
| `LineReader` | class | 按行读取 | X |
| `ChainReader` | class | 串联多个 Reader | X |
| `TeeWriter` | class | 同时写两个 Writer | X |
| `LimitReader` | class | 限制读取上限 | X |
| `Stdio` | class | 标准输入/输出/错误流 | X |

**与 `xdk.bytes` 的分工（冻结）**：

- `ByteReader`/`ByteWriter`：低层、有界、面向协议编解码的字节游标；不持有 OS 资源。
- `Reader`/`Writer`：应用级流；K 为内存实现，X 接入文件/网络/stdio；公共方法语义必须与 `ByteReader`/`ByteWriter` 对齐。
- 不允许同一个方法在两套类型里有不同的 EOF/副本语义。

#### `Reader`（class，K）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Reader(Bytes source)` | 从源读取；借用源 | 无 |
| `remaining` | `Int remaining()` | 剩余字节数 | 无 |
| `hasRemaining` | `Bool hasRemaining()` | 是否还有字节 | 无 |
| `readU8` | `Int readU8()` | 读 1 字节并前进 | EOF → panic |
| `readBytes` | `Bytes readBytes(Int count)` | 钳制读取，返回副本 | 负 count → panic |

- 读取期间调用方不得修改源。
- 无 close（内存流无资源）；X 的文件/网络流必须有 close。

**X**：`Result<Int, Error> tryReadU8()`、`Result<Bytes, Error> readExact(Int count)`、`Int position()`、`Result<Unit, Error> seek(Int offset)`、`Bool isOpen()`、`Result<Unit, Error> close()`（仅资源流）。

#### `Writer`（class，K）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Writer()` | 空 writer | 无 |
| `length` | `Int length()` | 当前长度 | 无 |
| `toBytes` | `Bytes toBytes()` | 当前内容副本 | 无 |
| `writeU8` | `void writeU8(Int value)` | 追加低 8 位 | 无 |
| `writeBytes` | `void writeBytes(Bytes source)` | 追加副本 | 无 |

**X**：`void clear()`、`Bytes takeBytes()`、`Result<Unit, Error> flush()`、`Result<Unit, Error> close()`（仅资源流）。

#### X 类方法面

| 类型 | 方法 |
| --- | --- |
| `BufferedReader` | `BufferedReader(Reader source, Int capacity)`；`remaining()`、`hasRemaining()`、`readU8()`、`readBytes(Int count)`、`close()` |
| `BufferedWriter` | `BufferedWriter(Writer target, Int capacity)`；`writeU8`、`writeBytes`、`flush`、`close` |
| `LineReader` | `LineReader(Reader source)`；`String? readLine()`（null = EOF）、`Result<String?, Error> tryReadLine()` |
| `ChainReader` | `ChainReader(List<Reader> sources)`；按顺序读，自动切换 |
| `TeeWriter` | `TeeWriter(Writer first, Writer second)`；写入同时转发 |
| `LimitReader` | `LimitReader(Reader source, Long limit)`；最多读 limit 字节 |
| `Stdio` | `Stdio.stdin()`、`Stdio.stdout()`、`Stdio.stderr()`；返回对应流 |

---

### 3.10 `xdk.fs`

| 项 | 值 |
| --- | --- |
| 职责 | 路径、文件、目录、元数据、临时文件、原子写、遍历 |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.io` |
| 被依赖 | `config`、`cli`、`log` |
| 稳定性 | `preview` |

> **归属冻结**：`Path`、`File`、`Dir`、`Metadata`、临时/原子/遍历 API 全部归 `xdk.fs`。`xdk.sys` 不再提供文件/目录/路径 API，也不再提供 `readFileText/fileExists/writeFileText`。本文只定义目标 API，不涉及迁移方式。

#### 类型总览

| 类型 | 种类 | 能力 | 层级 |
| --- | --- | --- | --- |
| `Path` | class | 路径字符串视图/拼接/规范化 | K |
| `File` | class | 文件句柄读写/定位/关闭 | K |
| `Dir` | class | 目录迭代/关闭 | K |
| `Metadata` | class | 文件元数据 | X |
| `DirEntry` | class | 目录项 | X |
| `TempFile` | class | 临时文件生命周期 | X |

#### `Path`（class，K）

**能力**：路径字符串的轻量视图，不访问文件系统。  
**生命周期**：不可变值对象；无 close；可跨任务共享。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Path(String text)` | 保存原始路径 | 无 |
| `toString` | `String toString()` | 原始路径 | 无 |
| `isAbsolute` | `Bool isAbsolute()` | 是否绝对路径 | 无 |
| `name` | `String name()` | 最后一段 | 无 |
| `parent` | `String parent()` | 父目录；无分隔符 → `"."` | 无 |
| `extension` | `String extension()` | 扩展名（不含点）；无 → 空串 | 无 |
| `join` | `Path join(String child)` | 拼接子路径 | 无 |
| `normalize` | `Path normalize()` | 规范化 `.`/`..`/重复分隔符 | 无 |
| `equals` | `Bool equals(Path other)` | 路径字符串相等 | 无 |

#### `File`（class，K）

**能力**：文件句柄；读/写/定位/关闭。  
**生命周期**：由 `openFileRead/Write/Append` 创建；必须 `close()`；close 幂等。  
**并发**：非线程安全；跨任务共享需外部同步。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 工厂 | `Result<File, Error> openFileRead(String path)` | 只读打开 | `NotFound`/`PermissionDenied`/`Io` |
| 工厂 | `Result<File, Error> openFileWrite(String path)` | 创建/截断写 | 同上 |
| 工厂 | `Result<File, Error> openFileAppend(String path)` | 创建/追加写 | 同上 |
| `isOpen` | `Bool isOpen()` | 是否打开 | 无 |
| `isWritable` | `Bool isWritable()` | 是否可写 | 无 |
| `position` | `Long position()` | 当前偏移 | 无 |
| `seek` | `Result<Unit, Error> seek(Long offset)` | 设置读偏移；负值 `InvalidArgument` | `InvalidArgument` |
| `size` | `Result<Long, Error> size()` | 当前文件字节数 | `NotFound`/`Io` |
| `readAll` | `Result<Bytes, Error> readAll()` | 从当前位置读到末尾 | `Unavailable`/`Io` |
| `read` | `Result<Bytes, Error> read(Long maximumBytes)` | 最多读指定字节 | `InvalidArgument`/`Unavailable`/`Io` |
| `readText` | `Result<String, Error> readText()` | 从当前位置读到末尾并按 UTF-8 解码 | `Unavailable`/`DataCorrupted` |
| `write` | `Result<Long, Error> write(Bytes data)` | 写入；写模式按当前位置，追加模式写末尾 | `Unavailable`/`PermissionDenied`/`Io` |
| `writeText` | `Result<Long, Error> writeText(String text)` | UTF-8 写入 | 同上 |
| `writeLine` | `Result<Long, Error> writeLine(String line)` | 写入 + 换行 | 同上 |
| `flush` | `Result<Unit, Error> flush()` | 刷新缓冲 | `Io` |
| `close` | `Result<Unit, Error> close()` | 关闭；幂等 | `Io`（诊断） |

**打开模式语义**：

- `openFileRead`：只读；`write/writeText/writeLine` 返回 `InvalidArgument`。
- `openFileWrite`：创建/截断；写从当前位置开始；`seek` 只影响读。
- `openFileAppend`：创建/追加；写总是到末尾；`seek` 只影响读。
- 关闭后所有 I/O 返回 `Unavailable`；`size` 可以在关闭后读取元数据（X 可选）。

#### `Dir`（class，K）

**能力**：目录迭代。  
**生命周期**：由 `openDir` 创建；必须 `close()`；close 幂等。  
**并发**：非线程安全。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 工厂 | `Result<Dir, Error> openDir(String path)` | 打开目录 | `NotFound`/`PermissionDenied`/`Io` |
| `isOpen` | `Bool isOpen()` | 是否打开 | 无 |
| `next` | `Result<String?, Error> next()` | 下一个条目；null = 结束 | `Unavailable`/`Io` |
| `entries` | `Result<List<String>, Error> entries()` | 读取剩余全部条目 | `Unavailable`/`Io` |
| `close` | `Result<Unit, Error> close()` | 关闭；幂等 | `Io` |

- `next()` 不用空串哨兵；null 表示结束。
- `entries()` 不包含 `"."`/`".."`；需要原始项时用 X `DirEntry`。

#### X 类

| 类型 | 方法/字段 |
| --- | --- |
| `Metadata` | `Long size()`、`Long modifiedMillis()`、`Bool isFile()`、`Bool isDirectory()`、`Bool isSymlink()`、`Int permissions()` |
| `DirEntry` | `String name()`、`Bool isDirectory()`、`Bool isFile()`、`Long size()` |
| `TempFile` | `Path path()`、`File file()`、`Result<Unit, Error> close()`、`Result<Unit, Error> persist(String path)` |

#### 顶层函数

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `exists` | `Bool exists(String path)` | 存在性；不区分权限/缺失 | 无 |
| `readText` | `Result<String, Error> readText(String path)` | 读取 UTF-8 文本 | `NotFound`/`PermissionDenied`/`DataCorrupted` |
| `writeText` | `Result<Long, Error> writeText(String path, String text)` | 覆盖写，返回字节数 | `PermissionDenied`/`Io` |
| `readBytes` | `Result<Bytes, Error> readBytes(String path)` | 读取二进制 | 同上 |
| `writeBytes` | `Result<Long, Error> writeBytes(String path, Bytes data)` | 覆盖写二进制 | 同上 |
| `removeFile` | `Result<Unit, Error> removeFile(String path)` | 删除文件 | `NotFound`/`PermissionDenied` |
| `renameFile` | `Result<Unit, Error> renameFile(String sourcePath, String targetPath)` | 重命名 | `NotFound`/`AlreadyExists`/`Io` |
| `copyFile` | `Result<Unit, Error> copyFile(String sourcePath, String targetPath)` | 复制 | `NotFound`/`Io` |
| `makeDir` | `Result<Unit, Error> makeDir(String path)` | 创建单层目录 | `AlreadyExists`/`Io` |
| `removeDir` | `Result<Unit, Error> removeDir(String path)` | 删除空目录 | `NotFound`/`Io` |
| `mkdirAll` | `Result<Unit, Error> mkdirAll(String path)` | 递归创建 | `Io` |
| `dirExists` | `Bool dirExists(String path)` | 目录存在性 | 无 |
| `isDir` | `Bool isDir(String path)` | 是否目录 | 无 |
| `fileMtime` | `Result<Long, Error> fileMtime(String path)` | 修改时间 epoch 毫秒 | `NotFound`/`Io` |
| `walk` | `Result<List<String>, Error> walk(String root)` | 递归遍历 | `NotFound`/`Io` |
| `glob` | `Result<List<String>, Error> glob(String pattern)` | 通配符匹配（X） | `InvalidArgument`/`Io` |
| `pathJoin` | `String pathJoin(String left, String right)` | 路径拼接便捷函数 | 无 |

**X**：`writeTextAtomic`、`writeBytesAtomic`、`withTempFile`、`symlink`/`readLink`、权限/链接语义。

---

### 3.11 `xdk.sys`

| 项 | 值 |
| --- | --- |
| 职责 | 进程、环境、平台、信号、内嵌资源读取 |
| 依赖 | `xdk.runtime`、`xdk.errors`、`xdk.bytes` |
| 被依赖 | `cli`、`config` |
| 稳定性 | `preview` |

> **归属冻结**：`File`、`Dir`、`Path`、`exists/readText/writeText` 不在 `xdk.sys`。  
> `xdk.sys` 只保留进程、环境、平台、信号、资源；文件系统 API 归 `xdk.fs`。

#### 类型总览

| 类型 | 种类 | 能力 | 层级 |
| --- | --- | --- | --- |
| `Process` | class | 子进程句柄 | K |
| `ProcessResult` | class | 退出码 + 输出 | K |
| `Env` | class | 环境变量快照 | X |
| `Signal` | enum | 跨平台信号 | X |

#### `Process`（class，K）

**能力**：创建/等待/终止/关闭子进程。  
**生命周期**：由 `spawnProcess` 创建；必须 `close()`；close 幂等。  
**并发**：非线程安全；`wait` 可重复读取同一退出状态。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 工厂 | `Result<Process, Error> spawnProcess(String command)` | 启动子进程 | `Unavailable`/`Io` |
| `isOpen` | `Bool isOpen()` | 句柄是否打开 | 无 |
| `wait` | `Result<Int, Error> wait()` | 阻塞等待；返回退出码（信号终止按 128+signal） | `Unavailable`/`Io` |
| `kill` | `Result<Unit, Error> kill(Int signal)` | 发送信号 | `Unavailable`/`InvalidArgument`/`Io` |
| `close` | `Result<Unit, Error> close()` | 未终结则终止并回收；幂等 | `Io` |

**X**：`Long id()`、`Result<Unit, Error> waitDeadline(Context context, Long deadlineMonoMillis)`、`spawnProcessArgs(List<String> arguments)`、stdio 管道。

#### `ProcessResult`（class，K）

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| `status` | `Int status()` | 退出码 |
| `stdout` | `String stdout()` | 标准输出 |
| `stderr` | `String stderr()` | 标准错误（X） |
| `isSuccess` | `Bool isSuccess()` | `status == 0` |

#### X 类

| 类型 | 方法/字段 |
| --- | --- |
| `Env` | `Env.snapshot()`；`String? get(String name)`、`Bool has(String name)`、`List<String> keys()`、`Map<String, String> all()` |
| `Signal` | 枚举成员：`Hangup`、`Interrupt`、`Kill`、`Terminate`、`User1`、`User2`；`Int number()` |

#### 顶层函数（K）

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `runProcess` | `Int runProcess(String command)` | 运行并返回退出码 | 无（底层失败返回非零） |
| `runProcessResult` | `Result<ProcessResult, Error> runProcessResult(String command)` | 运行并捕获输出/退出码 | `Unavailable`/`Io` |
| `envOrNull` | `String? envOrNull(String name)` | 环境变量；缺失 → null | 无 |
| `envOr` | `String envOr(String name, String fallback)` | 缺失 → fallback | 无 |
| `envHas` | `Bool envHas(String name)` | 是否存在 | 无 |
| `platform` | `String platform()` | 运行平台名 | 无 |
| `arch` | `String arch()` | 架构名 | 无 |
| `hostname` | `String hostname()` | 主机名 | 无 |
| `pid` | `Int pid()` | 当前进程 ID | 无 |
| `cwd` | `String cwd()` | 当前工作目录 | 无 |
| `chdir` | `Bool chdir(String path)` | 切换目录 | 无 |

> `env` 的空串哨兵作废；新代码用 `envOrNull`/`envOr`。

#### 内嵌资源（X，归 `xdk.sys`）

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `resourceExists` | `Bool resourceExists(String path)` | 资源是否存在 | 无 |
| `resourceSize` | `Long? resourceSize(String path)` | 资源大小；缺失 → null | 无 |
| `readResource` | `Result<Bytes, Error> readResource(Context context, String path)` | 读取资源字节；可取消 | `NotFound`/`Cancelled`/`Io` |
| `readResourceText` | `Result<String, Error> readResourceText(Context context, String path)` | 读取 UTF-8 文本 | 同上 |
| `listResources` | `Result<List<String>, Error> listResources(Context context, String prefix)` | 列出前缀下资源 | 同上 |

**X/**：信号、进程组、stdio 管道、环境枚举、独立 `xdk.resource`（）。

---

### 3.12 执行层内建：`Context` / `Task` / `TaskGroup`

> 按 `MINI-1.0.md` 的 P9=B：这些类型是语言/运行时内建；`xdk.tasks` 只保留 deprecated 兼容命名空间，不计入 1.0 公共包承诺。  
> 本节定义 API 面，不把包当成 1.0 公共包。

#### `Context`（内建 class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `background` | `static Context background()` | 根上下文 | 无 |
| `isCancelled` | `Bool isCancelled()` | 是否已取消 | 无 |
| `cancel` | `void cancel()` | 标记取消；已取消为 no-op | 无 |

- 取消是协作式的；不杀线程。
- 可跨任务共享；无 close。

#### `TaskGroup`（内建 class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `create` | `static TaskGroup create(Context parent)` | 创建子组；继承取消 | 无 |
| `spawn` | `Result<Task<T>, TaskError> spawn(Result<T, TaskError>() body)` | 启动任务；组关闭后失败 | `Unavailable` |
| `cancel` | `void cancel()` | 取消组及其任务 | 无 |
| `close` | `Result<Unit, TaskError> close()` | 取消、等待、返回首个非取消错误；幂等 | `TaskError` |

**合同修正**：旧设计 `spawn` 返回 `Task<T>` 却声明可失败，自相矛盾；本设计改为 `Result<Task<T>, TaskError>`。

#### `Task<T>`（内建 class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `join` | `Result<T, TaskError> join()` | 等待并消费任务；重复 join 是合同错误 | `Cancelled`/`TaskError` |
| `joinDeadline` | `Result<T, TaskError> joinDeadline(Long deadlineMonoMillis)` | 截止等待；超时返回 `Timeout`，不消费结果 | `Timeout`/`Cancelled` |

- `TaskError` 必须实现 `Error`；`CancelledError` 是 `kind() == Cancelled` 的具体错误值。
- `joinDeadline` 超时后任务继续运行；调用方仍可用 `join()` 或 `TaskGroup.cancel()`。
- 任务结果所有权在 `join` 后转移；重复 join 是合同错误（panic）。

#### `TaskError` / `CancelledError`（内建错误值）

| 类型 | 能力 | 方法 | 说明 |
| --- | --- | --- | --- |
| `TaskError` | 任务失败通道 | `ErrorKind kind()`、`String describe()` | 必须实现 `Error`；不得把 `Cancelled` 伪装成其他分类 |
| `CancelledError` | 取消错误值 | `ErrorKind kind()`、`String describe()` | `kind() == Cancelled`；可被 `TaskError` 通道承载 |

- `TaskError` 的具体表示由 S6/运行时定义；XDK 只承诺它实现 `Error`，并能表达 `Cancelled`、`Timeout`、`Unavailable`。
- `TaskError` 不是新的业务错误分类；细粒度信息用 `describe()` 或具体错误类承载。

---

### 3.13 执行层内建：`Mutex` / `Channel` / `Atomic*`

> 同 P9=B：语言/运行时内建；`xdk.sync` 只保留 deprecated 兼容命名空间。

#### `Mutex<T>`（内建 class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Mutex(T value)` | 保护值 | 无 |
| `withLock` | `Result<Unit, TaskError> withLock(void(T) body)` | 闭包持锁执行；返回 Err 也释放 | `TaskError` |
| `withLockResult` | `Result<U, TaskError> withLockResult<U>(Result<U, TaskError>(T) body)` | X：闭包可返回失败 | `TaskError` |

- 不提供裸 `lock/unlock`。
- 非重入；同任务重复加锁会死锁（合同错误）。

#### `Channel<T>`（内建 class）

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Channel(Int capacity)` | `capacity >= 0`；0 = 同步通道 | 负容量 → panic |
| `send` | `Result<Unit, Error> send(T value)` | 满则阻塞；取消 → Cancelled；关闭 → Unavailable | `Cancelled`/`Unavailable` |
| `receive` | `Result<T, Error> receive()` | 空则阻塞；取消 → Cancelled；关闭 → Unavailable | `Cancelled`/`Unavailable` |
| `close` | `void close()` | 幂等；关闭后队列剩余元素丢弃 | 无 |
| `isClosed` | `Bool isClosed()` | 是否关闭 | 无 |
| `length` | `Int length()` | 当前排队数 | 无 |
| `capacity` | `Int capacity()` | 容量 | 无 |

**合同修正**：旧设计 `send/receive` 返回 `Result<..., CancelledError>`，无法表达关闭后的 `Unavailable`；本设计改为 `Error`，取消仍通过 `kind() == Cancelled` 表达。

**X**：`trySend`、`tryReceive`、`sendDeadline`、`receiveDeadline`、`select`。

#### `AtomicInt` / `AtomicBool` / `AtomicRef<T>`

| 类型 | 方法 | 签名 | 语义 |
| --- | --- | --- | --- |
| `AtomicInt` | 构造 | `AtomicInt(Int initialValue)` | 初始值 |
| | `load` | `Int load()` | 读 |
| | `store` | `void store(Int value)` | 写 |
| | `compareExchange` | `Bool compareExchange(Int expected, Int replacement)` | CAS；成功 true |
| | `addAndGet` | `Int addAndGet(Int delta)` | 加并返回新值（X） |
| | `getAndAdd` | `Int getAndAdd(Int delta)` | 加并返回旧值（X） |
| `AtomicBool` | 构造 | `AtomicBool(Bool initialValue)` | 初始值 |
| | `load/store/compareExchange` | 同上 | 布尔原子操作 |
| `AtomicRef<T>` | 构造 | `AtomicRef(T value)` | 引用原子 |
| | `load/store/compareExchange` | 同上 | 引用身份原子操作 |

- 顺序一致；不承诺无锁实现。
- X：`RwLock<T>`、`Semaphore`、`WaitGroup`、`Once`、`Barrier`、`select`。

---

### 3.14 `xdk.log`

| 项 | 值 |
| --- | --- |
| 职责 | 分级日志、阈值过滤、结构化字段、可插拔 sink |
| 依赖 | `xdk.runtime`、`xdk.text`、`xdk.time` |
| 被依赖 | `config`、`cli`、`metrics`（） |
| 稳定性 | K `preview`；X `preview` |

#### `Level`（enum，K）

`Debug`、`Info`、`Warn`、`Error`；顺序固定 0..3，只允许追加。

#### `Logger`（class，K）

**能力**：命名 logger + 最低级别 + 输出。  
**生命周期**：无 OS 资源；无 close；可跨任务共享（线程安全由 sink 决定）。  
**K 输出**：stdout，固定 `[LEVEL] name: message`。

| 方法 | 签名 | 语义 |
| --- | --- | --- |
| 构造 | `Logger(String name, Level minimum)` | 名称 + 阈值 |
| `enabled` | `Bool enabled(Level level)` | `level >= minimum` |
| `log` | `void log(Level level, String message)` | 过滤后输出 |
| `debug/info/warn/error` | `void debug(String message)` 等 | 便捷方法 |

**X**：

| 类型 | 方法/字段 |
| --- | --- |
| `Field` | `Field(String key, String value)`、`String key()`、`String value()` |
| `LogRecord` | `Level level()`、`String loggerName()`、`String message()`、`List<Field> fields()`、`Long timestampMono()` |
| `Sink`（protocol） | `void write(LogRecord record)`；sink 失败只诊断，不改变业务控制流 |
| `ConsoleSink` | `ConsoleSink()`；写 stdout |
| `MemorySink` | `MemorySink()`；`List<LogRecord> records()`、`void clear()` |
| `Logger` 扩展 | `Logger withSink(Sink sink)`、`Logger withField(String key, String value)`、`void logRecord(LogRecord record)` |

- 不提供全局 logger；不隐式读取环境/配置。
- 日志失败不传播为业务错误； 最小 sink 不做 I/O 错误传播。
- 脱敏/采样/过滤链已纳入 2.x log 合同：`Filter`/`Redactor`/`Sampler` 与 `Logger.with*` 见 [`log/README.md`](log/README.md) §9。

---

### 3.15 `xdk.config`

| 项 | 值 |
| --- | --- |
| 职责 | 配置快照、覆盖、环境白名单、来源注入 |
| 依赖 | `xdk.errors`、`xdk.text`、`xdk.fs`、`xdk.sys` |
| 被依赖 | `cli`、`log`、应用主逻辑 |
| 稳定性 | K `preview`；X `preview` |

#### `Config`（class，K）

**能力**：profile + 有序键值快照；`set` 覆盖同键；环境白名单导入。  
**不变量**：键非空、不含 `=`/换行；值可含 `=`；插入顺序稳定；`render` 仅诊断。  
**生命周期**：可变构建期；非线程安全；构建完成后只读共享需外部同步；无 close。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Config(String profile)` | 空配置 | 无 |
| `length` | `Int length()` | 键值数 | 无 |
| `has` | `Bool has(String key)` | 是否存在 | 无 |
| `set` | `void set(String key, String value)` | 覆盖/插入 | 非法 key → panic |
| `getOr` | `String getOr(String key, String fallback)` | 读取；缺失 → fallback | 无 |
| `tryGet` | `Result<String, Error> tryGet(String key)` | 缺失 → NotFound（X） | `NotFound` |
| `loadEnv` | `void loadEnv(List<String> keys)` | 只导入白名单；缺失不改原值 | 无 |
| `render` | `String render()` | `profile:key=value,...`，诊断用 | 无 |

**X**：

| 类型/方法 | 签名 | 语义 |
| --- | --- | --- |
| `ConfigEntry` | class | `String key()`、`String value()` |
| `ConfigSource` | protocol | `Result<List<ConfigEntry>, Error> load(Context context)` |
| `MapSource` | class | 内存来源 |
| `FileSource` | class | 文件来源；UTF-8 `key=value` |
| `Overlay` | class | 多来源覆盖：后者覆盖前者 |
| typed getter | `Int getIntOr(String key, Int fallback)`、`Bool getBoolOr(String key, Bool fallback)`、`Result<Int, Error> tryGetInt(String key)` | 类型化读取 |
| 校验 | `Result<Unit, Error> validate()` | 键/值/必填校验，错误聚合 |

---

### 3.16 `xdk.cli`

| 项 | 值 |
| --- | --- |
| 职责 | 参数视图、flag/值读取、位置参数、用法文本、退出码、选项/子命令 |
| 依赖 | `xdk.errors`、`xdk.text`、`xdk.sys` |
| 被依赖 | 工具程序入口 |
| 稳定性 | K `preview`；X `preview` |

#### `Args`（class，K）

**能力**：原始 argv 视图；`--name value` 与 `--name=value`；位置参数。  
**生命周期**：借用 argv 列表；不修改；无 close；非线程安全（只读可共享）。

| 方法 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| 构造 | `Args(List<String> raw)` | 保存 argv | 无 |
| `length` | `Int length()` | 参数数 | 无 |
| `get` | `String get(Int index)` | 按索引 | 越界 → panic |
| `has` | `Bool has(String flag)` | `--flag` 或 `--flag=value` | 无 |
| `valueOrNull` | `String? valueOrNull(String flag)` | 取值；缺失 → null（推荐） | 无 |
| `valueOr` | `String valueOr(String flag, String fallback)` | 缺失 → fallback | 无 |
| `tryValue` | `Result<String, Error> tryValue(String flag)` | 缺失 → NotFound（X） | `NotFound` |
| `positionals` | `List<String> positionals()` | 非 option 序列 | 无 |
| `value` | `String value(String flag)` | **deprecated**：缺失返回空串；新代码用 `valueOrNull` | 无 |

**X**：

| 类型 | 方法 |
| --- | --- |
| `OptionSpec` | `OptionSpec(String name, Bool hasValue, Bool isRequired, String? defaultValue, String description)`；`name()`、`hasValue()`、`isRequired()`、`defaultValue()`、`description()` |
| `Command` | `Command(String name, String summary)`；`addOption(OptionSpec)`、`addSubcommand(Command)`、`Result<Args, Error> parse(List<String> arguments)`、`String help()` |
| `Completion` | `List<String> complete(String prefix)` |
| `Args` 扩展 | `List<String> values(String flag)`、`Bool hasFlag(String flag)`、`--` 终止符 |

**顶层函数**：

| 函数 | 签名 | 语义 |
| --- | --- | --- |
| `usage` | `String usage(String program, String summary)` | 生成用法文本，不写 stdout/stderr |
| `exitCodeFor` | `Int exitCodeFor(String outcome)` | `ok=0`、`usage=2`、其他=1 |

> 与 S5 §6.2 的“64 = usage”约定不同： 保留 `2` 作为 CLI 应用约定；S5 的 64 是建议值，不是语言错误。若 1.0 要统一，需要同时改 CLI 设计和用户文档。

---

## 4. 核心层 API 总表（按包）

| 包 | 公开 class/protocol/enum | 顶层函数组 |
| --- | --- | --- |
| `errors` | `ErrorKind`、`Error`、`DetailedError`、`ErrorDetail`、`BasicError`、`ErrorReport`、`ErrorGroup` | 构造/校验、包装/报告、重试、名称/码、ResultOps |
| `runtime` | 无（X：`RuntimeInfo`） | diagnose/exit/clock |
| `meta` | 无（X：`BuildInfo`） | version/platform |
| `bytes` | `Bytes`、`ByteReader`、`ByteWriter`、`ByteBuffer`（X） | UTF-8/hex、切片/比较、Endian、Bits |
| `text` | `Format`、`Regex`、`Match`（X）、`Utf16`（X）、`StringBuilder`（X） | 查找/变换/填充、parse/format、Unicode、regex |
| `collections` | `List`、`Map`、`Set`、`Pair`、`IntPair`、`PriorityQueue`、`RingBuffer`、`OrderedMap`（X）、`BTreeMap`（X） | 排序/查找/去重/聚合 |
| `math` | 无（`Int128` 是标量） | 常量/取整/幂/三角/数论/checked/saturating/组合/统计 |
| `time` | `Duration`、`DateTime`、`Civil`（X：`TimeZone`、`Stopwatch`） | 时钟、构造、解析 |
| `io` | `Reader`、`Writer`（X：Buffered/Line/Chain/Tee/Limit/Stdio） | — |
| `fs` | `Path`、`File`、`Dir`（X：`Metadata`、`DirEntry`、`TempFile`） | exists/read/write/remove/rename/copy/mkdir/walk/glob |
| `sys` | `Process`、`ProcessResult`（X：`Env`、`Signal`） | run/spawn、env/platform、resource |
| 执行层 | `Context`、`Task<T>`、`TaskGroup`、`Mutex<T>`、`Channel<T>`、`AtomicInt/Bool/Ref<T>` | — |
| `log` | `Level`、`Logger`（X：`Field`、`LogRecord`、`Sink`、`ConsoleSink`、`MemorySink`） | — |
| `config` | `Config`（X：`ConfigEntry`、`ConfigSource`、`MapSource`、`FileSource`、`Overlay`） | — |
| `cli` | `Args`（X：`OptionSpec`、`Command`、`Completion`） | usage/exitCodeFor |

---

## 5. 设计决策与待回写项

### 5.1 本文已冻结的 API 决策

| # | 决策 | 影响 |
| --- | --- | --- |
| D1 | 核心层 = 14 公共包 + 执行层内建；`xdk.tasks`/`xdk.sync` 为 deprecated | 与 `MINI-1.0` P9=B 对齐；`00-overview` 的 16 包口径需回写 |
| D2 | `fs` 拥有 `Path/File/Dir/Metadata`；`sys` 拥有 `Process/Env/Signal/Resource` | 消除现有 API 面的文件/系统双入口 |
| D3 | 无值可恢复失败统一 `Result<Unit, Error>` | 旧文档的无成功值 `Result` 需回写为 `Unit` 成功类型 |
| D4 | 禁止哨兵：EOF=0、空串=缺失、null=缺失+合法值 | `Reader.readU8`、`Dir.next`、`cli.value` 需调整 |
| D5 | `Map.put`/`remove` 返回 `Bool`；`removeOr` 返回旧值 | 旧文档 §5.2 的 `Int?` 作废 |
| D6 | `TaskGroup.spawn` 返回 `Result<Task<T>, TaskError>` | 旧设计的 `Task<T>` + 可失败矛盾 |
| D7 | `Channel.send/receive` 返回 `Result<..., Error>` | 旧设计的 `CancelledError` 无法表达关闭 |
| D8 | `Regex` 公共入口为 `regexCompile`；`Match` 用 `length()` 而非 `len()` | 统一 `xdk.text` 的公共 API |
| D9 | `File.seek` 用 `Long`；`writeText/readText` 返回 `Result` | 消除大文件截断和无失败通道 |
| D10 | `count/flatten/isEmpty` 等跨包同名冲突按 §2.5 改名 | 需回写 `text`/`collections`/`errors` 文档与场景 |
| D11 | `platform` 语义拆分：`meta.targetPlatform` 构建目标；`sys.platform` 运行平台 | 避免“同名换义” |
| D12 | K 不引入 `Iterator<T>`/`Stream` 泛型协议；迭代器归  | 保持与当前语言能力一致 |

### 5.2 需要回写的旧文档

| 文档 | 需要修改的点 |
| --- | --- |
| `00-overview.md` | 16 包 → 14 包 + 执行层内建；类级标准引用本文 |
| `01-errors.md` | `flatten` → `flattenResult`；补充 `withCause(null)` 合同 |
| `04-bytes.md` | 明确 `Bytes.slice` 成员是内部还是公共；`ByteBuffer.reserve` 语义 |
| `05-text.md` | 补 `Format/Regex/Match/Utf16/StringBuilder` 类契约；`count` → `countText` |
| `06-collections.md` | `Map.put/remove` 统一为 `Bool`；`count` → `countIf`；`flatten` → `flattenList`；`Pair` 语义 |
| `08-time.md` | `Duration/DateTime/Civil` 类契约；所有 epoch 运算用 `Long`；`Civil` 字段命名 |
| `09-io.md` | `Reader/Writer` 类契约；EOF/副本语义；与 `ByteReader/ByteWriter` 分工 |
| `10-fs.md` | `Path/File/Dir` 完整类契约；Result 面；`writeText` 返回 `Result<Long,Error>`；从 sys 迁入 |
| `11-sys.md` | 删除文件/目录/路径 API；补 `Process/ProcessResult` 类契约；资源归 sys |
| `12-tasks.md` | `spawn` 返回 `Result`；`Result<Unit,...>`；P9=B 内建口径 |
| `13-sync.md` | `Channel` 错误类型；`Result<Unit,...>`；P9=B 内建口径 |
| `14-log.md` | `Level/Logger` 类契约；X `Field/LogRecord/Sink` |
| `15-config.md` | `Config` 类契约；键/值/render 规则；X 来源 |
| `16-cli.md` | `Args` 类契约；`value` 哨兵废弃；X 选项/子命令 |

### 5.3 仍需用户签字的点

1. **`fs`/`sys` 归属**：本文按 S7 把文件/目录/路径归 `fs`；这会改变现有 `xdk.sys` 的公开导入面。是否需要兼容期？
2. **`tasks`/`sync` 的 1.0 地位**：本文按 P9=B 作为语言内建；若要把它们重新纳入 1.0 公共包，需要改 P9 决策。
3. **破坏性改名**：`countText`、`countIf`、`flattenResult`、`flattenList`、`Tasks.spawn` 返回类型、`Channel` 错误类型、`Map.put` 返回类型。是否接受在 1.0 前一次性修正？
4. **`xdk.text` 的 API profile**：本文按“一个包、同一 API、能力分级（K/X）”设计；若允许两套 API，需要明确 feature gate。

---

## 6. 评审清单（核心层 API）

- [ ] 每个公开 class 有能力、不变量、生命周期、所有权、并发/取消、失败通道。
- [ ] 每个方法有签名、语义、失败；没有只写方法名不写契约。
- [ ] 每个可恢复失败只有一个通道：`Result<T, Error>` 或 `Result<Unit, Error>`。
- [ ] 每个资源有 `close()`，且幂等；关闭后行为明确。
- [ ] 每个可阻塞点有 `Context`；取消/超时不被聚合掩盖。
- [ ] 没有哨兵值；没有 `null`/空串/0 的双重含义。
- [ ] 没有跨包同名顶层函数；§2.5 的冲突已消除。
- [ ]  依赖图无环；`fs`/`sys`/`io` 边界清楚。
- [ ]  签名不出现 / 类型；`tasks`/`sync` 按内建或 deprecated 处理。
- [ ] 每个包有 K/X 边界；X 不被当成 K 承诺。
- [ ] 旧文档与本文的冲突已登记并回写。
