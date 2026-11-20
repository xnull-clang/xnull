# XDK T0 核心包详细设计 v1.2 · 总览

| 项 | 值 |
| --- | --- |
| 版本 | 1.2.0（替代 v1.1） |
| 状态 | 决策冻结；01 v1.3、04/06 v1.2 已修订，其余包待写 |
| 依据 | S0 v1.1.0、S1 v3.4.0、S2 v3.4.0（struct 引用字段修订）、S3 v3.2.0、S4 v1.2.0、S5 v1.3.0、S6 v3.0.0 |
| 目标 | 把 T0 从“包/文件清单”推进到“类级能力契约” |
| 组织 | 一个包一份设计、一个验收门；实现可分内部提交 |

> v1.0 回答“有哪些包、放哪些文件”；v1.1 回答“每个类具备什么能力”；
> v1.2 回答“哪些决策已经冻结、哪些实现缺口必须登记”。只写方法名、不写契约
> 的条目，在评审中视为未设计；保留“或/待定/严格版”双义条目的，同样视为未设计。

---

## 0. 权威与状态

### 0.1 优先级（冻结）

发生冲突时按以下顺序处理：

1. **S1–S6 规范**：语言语义、错误/取消/资源合同、包边界；
2. **T0 设计契约**：在规范未覆盖处细化 API；新增约定必须回写 S6 或作为 S6 errata；
3. **`src/mini` 实现**：当前实现事实；与规范冲突时登记为实现缺口，按独立提交修复；

规则：

- 规范没写的，不许由实现或场景自行发明；先改规范或 S6 errata。
- 设计说“已冻结”的条目，不允许再出现“或/待定/见下/严格版”两套语义。
- mini 能跑不等于规范正确；规范说错也不行。发现规范错误时先改规范，再改实现。
- `Source` 不是最终权威；源码是实现，契约以规范 + 设计为准。

### 0.2 状态标签

| 标签 | 含义 |
| --- | --- |
| `Draft` | 结构有了，决策未冻结 |
| `Decided` | 决策已冻结，可开始实现 |
| `Implemented` | 代码存在，场景未全绿 |
| `Verified` | 场景、回归、差分通过 |
| `Blocked` | 依赖的语言/运行时能力未完成，不得宣称可用 |
| `Partial` | 包内部分能力完成，但未达到 `complete` |

只有 `Verified` 才能标记包 `complete`；`Partial` 不允许用 T0-K 冒充整包完成。

### 0.3 已确认的用户决策

- `struct` 可以包含 `String` 或其他引用字段；复制是字段槽复制 + 引用句柄浅复制。
- `Int` 32 位、`Long` 64 位；公开 API 不使用 `Int32/Int64/UInt64` 别名。
- 不允许同名换义；方法名必须清晰、唯一。
- P0 契约必须冻结，不允许默认两可、待定或矛盾。
- 旧 `src` 内容以 mini 为准；语言规范与 mini 冲突时，先改规范或修 mini。
- S6 的旧说法可以更新；以当前 mini/T0 设计为准做 errata。
- “一个包一个提交”改为“一个包一个验收门，实现可分内部提交”。
- T0-X 阻塞不阻止 T0-K 交付；包状态标 `Partial`，不宣称 `complete`。
- API 预算数量不是质量指标，只作参考。

---

## 1. 什么算“类级设计”

### 1.1 通用 12 项

每个公开 **class** 必须包含以下 12 项；缺一项即未达到 v1.2 交付标准：

| # | 项目 | 必须回答的问题 |
| --- | --- | --- |
| 1 | 能力声明 | 这个类让调用方“能做什么”，不做什么 |
| 2 | 表示与不变量 | 内部字段代表什么；任何时候都必须成立的条件 |
| 3 | 生命周期 | 创建、使用、关闭/终结；能否重复关闭 |
| 4 | 构造契约 | 每个构造参数的合法域；非法输入如何失败 |
| 5 | 字段表 | 每个字段的类型、可变性、所有权、可见性 |
| 6 | 方法契约 | 前置条件、后置条件、返回值、失败、复杂度 |
| 7 | 所有权与别名 | 参数是否借用/消费；返回值是否 +1；能否别名 |
| 8 | 并发与重入 | 线程/任务安全；可否跨任务共享；可否重入 |
| 9 | 取消点 | 哪些方法可阻塞、在哪检查 `Context`、取消后状态 |
| 10 | 相等/排序/哈希 | 是否有值语义；能否作为 Map 键；排序规则 |
| 11 | 示例与反例 | 最小正确用法；最常见的错误用法及后果 |
| 12 | 测试义务 | 成功、失败、边界、取消、并发、资源泄漏的断言 |

### 1.2 按类型种类取舍

12 项不要求 enum/protocol/struct 机械照抄；按种类给最低要求：

| 种类 | 必须有 |
| --- | --- |
| `class` | 12 项全量；字段表、生命周期、并发/取消不能省 |
| `struct` | 表示、字段限制、复制/别名、相等、示例、测试；无 close |
| `enum` | 成员表、稳定序号、语义、跨版本规则、示例、测试 |
| `protocol` | 能力、方法签名、实现者限制、失败语义、实现检查、测试 |
| 顶层函数 | 签名、前置/后置、失败、复杂度、纯度、示例、测试 |

方法契约统一用下表表达，禁止只写“方法名 + 返回类型”：

| 方法 | 签名 | 前置条件 | 后置条件 | 失败 | 复杂度 | 并发/取消 |
| --- | --- | --- | --- | --- | --- | --- |

### 1.3 失败通道（冻结）

每个可能失败的公开方法必须且只能属于以下一种：

- `Result<T, Error>`：可恢复失败；
- **合同错误（panic）**：调用方违反前置条件，如越界、非法 shift、非法 key；
- **无失败**：纯读取/纯值操作。

不允许：

- 返回 `Void` 却声明“非法参数 → InvalidArgument”；
- 用 `null`/`0`/空串同时表示“缺失”和“合法值”；
- 同一方法既“原样返回”又“返回 InvalidArgument”。

---

## 1.4 参数命名规则（强制）

**公开 API 的参数必须写全名，禁止单字母/缩写。** 方法名不是接口，参数名也不是
占位符；调用方在 IDE/补全里看到的是 `text`，不是 `s`。

规则：

- 值参数用完整英文 `lowerCamelCase`：`text`、`prefix`、`separator`、`value`、
  `index`、`length`、`count`、`context`、`maximumBytes`。
- 单字母只允许用于**类型参数**（`T`、`K`、`V`、`E`、`A`、`B`）和实现代码里
  的循环下标；公开签名里的值参数不允许 `i/j/n/s/e/r/f/v/c`。
- 禁止缩写表：

| 禁止 | 改用 |
| --- | --- |
| `s`, `str` | `text`, `sourceText` |
| `e`, `err` | `error` |
| `r`, `res` | `result`, `response` |
| `f`, `fn` | `function`, `callback`, `transform`, `predicate` |
| `v`, `val` | `value` |
| `c`, `ch` | `character`, `codePoint` |
| `n`, `len` | `count`, `length`, `maximumCount` |
| `i`, `j`, `idx` | `index`, `offset`, `position` |
| `xs` | `items`, `values` |
| `m`, `msg` | `map`, `message` |
| `ctx` | `context` |
| `args` | `arguments` |
| `cmp` | `compare`, `comparator` |
| `eq` | `equals`, `equality` |
| `pred` | `predicate` |
| `sep` | `separator` |
| `pad` | `padding` |
| `ms` | `milliseconds` |
| `buf` | `buffer` |
| `num` | `number`, `amount` |
| `obj` | `object` |
| `tmp` | `temporary` |
| `init` | `initial`, `initialValue` |
| `max`/`min` | `maximum`/`minimum` |

- 时间参数写单位：`milliseconds`、`deadlineMillis`、`timeoutMillis`；不要 `ms`。
- 回调参数按角色命名：`predicate`、`comparator`、`transform`、`combine`、
  `equals`、`keySelector`；不要统一叫 `f`。
- 布尔参数以 `is/has/can/should` 开头：`isAppend`、`hasHeader`。
- 参数名必须出现在签名里，不能只写类型（如 `fromUtf8(String)` 不合格，
  必须 `fromUtf8(String text)`）。
- 例外：FFI/ABI 声明可按 C 约定使用短名，但必须标 `internal`，且不得出现在
  XDK 公开 API。
- 自动检查：`src/toolchain/check_doc_naming.py` 扫描本目录与 v1.0 提纲；
  `src/mini/tests/xdk.sh` 已把它纳入回归。源码公开签名也必须遵守；源码 lint
  在实现阶段补齐，未补齐前不得用“文档合规”冒充“源码合规”。

---

## 2. 能力模型

T0 的设计单位是**能力**，不是文件：

```text
能力（capability）
  → 由哪个类型承载
  → 类型暴露哪些方法
  → 每个方法的契约
  → 哪个场景证明它
```

例如“有界等待队列”是能力，`Channel<T>` 是承载类型，`send/receive/close`
是方法，`xdk_channel.x` 是场景。文件只是实现组织，不能反过来定义能力。

---

## 3. T0-K 与 T0-X

每个包分两层：

- **T0-K（Kernel）**：没有它，该包不能算可用；是该包的验收底线。
- **T0-X（Extended）**：常用扩展，同属该包阶段；不得用空实现冒充。

K/X 是**范围标签，不是子阶段**：一个包一个验收门、一份最终提交；实现可以拆
内部提交。若 X 被编译器/运行时外部依赖阻塞：

- T0-K 可以继续交付并标 `Implemented`/`Verified`；
- 包状态标 `Partial`，不得标 `complete`；
- 阻塞项必须登记到 `src/xdk/PLAN.md`，写明依赖、场景、解除条件。

| 包 | T0-K（验收底线） | T0-X（同阶段完成） |
| --- | --- | --- |
| errors | ErrorKind、Error、BasicError、DetailedError、ErrorDetail、toErrorReport/annotate、ErrorGroup、同类型 ResultOps、跨类型 map/collectOk/flatten、FFI 码 | 复杂方法调用返回值推断、错误码命名空间工具 |
| runtime | diagnose、exit、nowMono/nowWall | stdio 流、RuntimeInfo、断言、fatal 边界 |
| meta | language/xdk/target 版本 | BuildInfo、目标能力矩阵、构建元数据 |
| bytes | Bytes 转换/切片/比较、ByteReader/Writer 严格读取、Endian、Bits | ByteBuffer 定位、NUL 边界工具 |
| text | trim/split/replace、parseInt/Float、Format | StringBuilder、Unicode、转义、数字格式化、Regex（POSIX 子集） |
| collections | List（Int/String）、Map<String,Int>、Map<Int,Int>、Set<Int>、Set<String>、成员面、排序/查找/去重、PriorityQueue/RingBuffer | Map<Int,Int>.entries、其他 Map/Set 组合、OrderedMap/BTreeMap、groupBy（T0-X） |
| math | 常量、abs/clamp、floor/ceil/round、pow/sqrt/log、三角 | Int128 checked、其他整数 saturating、统计、组合数学 |
| time | Instant/Duration/DateTime 基础换算 | 解析/格式化全量、日历加减、TimeZone、Stopwatch |
| io | Reader/Writer 协议、内存流、readAll/copy | Buffered、Chain/Tee/Limit、LineReader、stdio |
| fs | Path/File/Dir、exists/read/write/close | Metadata、walk/glob、Temp、Atomic、权限/链接 |
| sys | Process、env、platform、cwd | stdio 管道、信号、环境枚举、进程组、内嵌资源读取子集 |
| tasks | Task/TaskGroup/Context、取消、joinDeadline | select/race、Context 值、取消作用域 |
| sync | Mutex、Channel、AtomicInt/Bool/Ref | RwLock、Semaphore、WaitGroup、Once、Barrier、select |
| log | Level、Logger、ConsoleSink | Field/Sink 分层、File/Memory sink、过滤、redaction |
| config | Config 快照、getOr/set、env allowlist | typed getter、overlay、Source、FileSource、校验 |
| cli | Args、usage、exitCode | OptionSpec、Command、子命令、help、补全 |

实现顺序仍按依赖：errors → runtime → meta → bytes → text → collections →
math → time → io → fs → sys → tasks → sync → log → config → cli。

---

## 4. 边界修正（相对 v1.0）

| 能力 | v1.0 位置 | v1.2 归属 | 处理 |
| --- | --- | --- | --- |
| Regex | `xdk.text` | `xdk.text` T0-X（POSIX 子集）；完整引擎 `xdk.regex`（T1） | T0-X 保留已验收子集，T1 再做完整引擎 |
| Random | `xdk.math` | `xdk.random`（T1） | math 只保留确定性算法 |
| 内嵌资源 | `xdk.sys` | `xdk.sys` T0-X（读取子集）；独立 `xdk.resource`（T1） | T0-X 保留已验收读取面，T1 再做独立包 |
| 结构化配置解码 | `xdk.config` 依赖 codec | `ConfigSource` 注入 | T0 只做 `key=value`/env/内存快照 |
| 通用迭代器 | `xdk.collections` | 后续语言扩展 | T0 无 `Iterator<T>`/`Iterable<T>`；`for-in` 编译器展开 |
| 通用 Map/Set | T0-K | T0-X 扩展 | 当前有 `Map<String,Int>`、`Map<Int,Int>`、`Set<Int>`、`Set<String>`；其他组合为 T0-X |

> 边界不是“以后再说”：T0 公开签名不得出现 T1 类型；T1 适配器通过协议注入。

---

## 5. 跨包契约

### 5.1 错误

- `Error` 是唯一基础错误协议：`kind()` + `describe()`；
- `DetailedError` 是独立扩展协议：`message/code`；`details/causes` 是 `BasicError` 类方法；
- `ErrorKind` 是唯一跨包分类；
- `wrap`/`mapErr`/`report` 保留 S4 语义，不得同名换义；
- 步骤记录用 `toErrorReport`/`annotate`/`withStep`；
- `collectOk`/`flatten`/跨类型 `mapOk/mapErr` 已实现；复杂方法调用返回值推断仍为 T0-X；
- 不使用 `throw` 表达“文件不存在/解析失败/通道关闭”。

### 5.2 所有权

- `struct`：值语义；字段槽复制，引用字段浅复制（S2 §3.2/§3.3）。
- `class`：引用语义；持 OS 资源的类必须 `close()`。
- 方法签名必须写明：`borrow`（借用）/`consume`（消费）/`returnOwned`（返回新所有权）。
- `Result.value()` 返回借用还是所有权，逐类型写明，不靠猜。

### 5.3 取消

- 可阻塞方法首参 `Context`；取消返回 `CancelledError`。
- 取消后对象必须回到可预测状态（已关闭、未消费、未半写）。
- 超时是 deadline；`joinDeadline` 超时映射 `Timeout`，不伪装 `Cancelled`。
- `ErrorGroup.kind()` 遇到 `Cancelled` 必须返回 `Cancelled`，不得被其他错误掩盖。

### 5.4 关闭

- `close()` 幂等：第一次关闭后，第二次返回 `Ok(unit)`，不做事。
- `AlreadyExists` 不用于重复 close。
- 关闭失败与未关闭是两种状态；`Err` 只报告诊断，不等于句柄未释放。

### 5.5 稳定性

- 每个公开符号标注 `stable` / `preview` / `internal`；
- T0-K 目标 `stable`；场景/差分未通过前标 `preview`，不提前宣称 stable；
- `internal` 不属于公开 API，不得出现在公开签名。

---

## 6. API 预算（参考，不是门槛）

| 包 | T0-K 公开符号（参考） | T0-X 目标（参考） | 说明 |
| --- | --- | --- | --- |
| errors | 15 | 35 | 分类、构造、包装、报告、组合、映射 |
| runtime | 8 | 25 | 诊断、退出、时钟、stdio、信息 |
| meta | 6 | 15 | 版本、目标、能力 |
| bytes | 30 | 70 | 转换、游标、缓冲、位、端序 |
| text | 30 | 80 | 算法、Builder、Format、Parse、Unicode |
| collections | 30 | 90 | 容器、算法、特化容器 |
| math | 50 | 120 | 基础函数、溢出、统计、Int128 |
| time | 25 | 60 | 时钟、时长、日历、时区 |
| io | 20 | 60 | 协议、内存、缓冲、组合、stdio |
| fs | 25 | 70 | 路径、文件、目录、遍历、临时、原子 |
| sys | 20 | 50 | 进程、环境、平台、信号 |
| tasks | 15 | 40 | 任务、组、上下文、取消、select |
| sync | 20 | 50 | 锁、通道、原子、同步器 |
| log | 15 | 45 | 级别、记录器、字段、sink、过滤 |
| config | 15 | 40 | 快照、来源、类型、校验 |
| cli | 15 | 45 | 参数、选项、命令、帮助、补全 |

预算不是 KPI，也不是评审门槛。低于参考值不自动失败；高于参考值也不自动
拆分。评审看的是能力覆盖、契约密度、场景证据，不是符号数量。

---

## 7. 评审清单

一份包设计通过评审，必须满足：

- [ ] 每个 `class` 有 12 项完整契约；struct/enum/protocol/函数的必需项齐全；
- [ ] 每个方法有前置/后置/失败/复杂度/并发取消列；
- [ ] 每个失败点有且只有一个失败通道（Result / panic / 无失败）；
- [ ] 每个资源有 close 生命周期与关闭后行为；重复 close 幂等；
- [ ] 每个可阻塞点有取消语义；`Cancelled` 不被聚合掩盖；
- [ ] 有最小示例与反例；
- [ ] 有成功/失败/边界/取消/并发/泄漏测试义务；
- [ ] T0/T1 边界无违规；T0 签名不出现 T1 类型；
- [ ] 设计中的类型/协议/泛型/数值宽度已按 S1/S2 校验；
- [ ] 没有“或/待定/见下/严格版”双义条目；
- [ ] 没有同名换义；新增名字与 S4/S6 不冲突；
- [ ] 场景、回归、差分/缺口已命名；
- [ ] 代码、场景、回归、文档同一包交付；内部提交不宣称包完成。

---

## 8. 文档索引与完成度

| 文档 | 内容 | 状态 |
| --- | --- | --- |
| `00-overview.md` | 设计标准、权威、K/X、边界、流程 | Decided |
| `01-errors.md` | 错误协议、构造、包装、聚合、Result 组合、FFI 映射 | Verified（mini） |
| `04-bytes.md` | Bytes、ByteBuffer、游标、位、端序 | Verified（mini） |
| `06-collections.md` | 容器、算法、特化容器 | Partial（T0-K 成员面通过；其他 Map/Set 组合 T0-X） |
| `AUDIT.md` | T0 冻结前审计、Int 32 位、包状态、门禁 | 当前 |
| `02-runtime.md` | 诊断、退出、时钟、stdio、运行时信息 | Verified（mini） |
| `03-meta.md` | 版本、目标平台、目标能力 | Verified（mini） |
| `05-text.md` | 文本算法、Builder、Format、Parse、Unicode | Partial（base/full 通过；边界待补） |
| `07-math.md` | 数学函数、溢出、统计、Int128 | Partial（T0-K 通过；Int128 已落地；统计 T0-X） |
| `08-time.md` | Instant、Duration、DateTime、TimeZone | Verified（mini） |
| `09-io.md` | Reader/Writer、缓冲、组合、stdio | Partial（内存面通过；严格/副本待补） |
| `10-fs.md` | Path、File、Dir、遍历、临时、原子 | Partial（文本面通过；完整 File/Dir 为 X） |
| `11-sys.md` | Process、Env、Platform、Signal | Partial（简化文件面；File/Dir/Process X） |
| `12-tasks.md` | Task、TaskGroup、Context、取消 | Verified（mini） |
| `13-sync.md` | Mutex、Channel、Atomics、同步器 | Partial（typed channel 待补） |
| `14-log.md` | Level、Logger、Field、Sink、过滤 | Verified（最小面） |
| `15-config.md` | Config、Source、Profile、校验 | Verified（内存/环境面） |
| `16-cli.md` | Args、OptionSpec、Command、usage | Verified（最小面） |

`01-errors.md`、`04-bytes.md`、`06-collections.md` 是后续包的样板：
达不到它们的契约密度，就不算完成；但不要复制它们已删除的旧写法
（泛型协议、宽松读取、`wrap/report` 同名换义、`HashMap/TreeMap` 空承诺）。

同目录 `appendices/` 放错误码表、所有权表、稳定性表、测试矩阵；当前尚未创建，
不阻塞包设计，但场景/回归落地前必须补齐。

---

## 9. 交付节奏

一个包一个验收门、一份最终提交；实现可分内部提交：

1. 先评设计（本文档对应包），状态从 `Draft` 到 `Decided`；
2. 设计通过后写场景（先失败）；
3. 实现 T0-K；实现可以拆内部提交，但不得单独宣称包完成；
4. 实现 T0-X；若被外部依赖阻塞，包标 `Partial`，登记阻塞项；
5. 跑 mini base/full；
6. 更新追溯矩阵与 `src/xdk/PLAN.md`；
7. 一次最终提交，状态从 `Implemented` 到 `Verified`，再标 `complete`。

不允许“先把 16 份文件生成出来，再回头补内容”；每一份包设计必须单独可评审。
也不允许把一个包拆成多个**验收门**；内部提交不算验收门。

---

## 10. S6 errata（待同步）

以下旧说法已由本版设计修正，S6 需要同步更新（不作为本文件的重复规范）：

1. `xdk.config` 不再依赖 `codec`；T0 只做 `key=value`/env/内存快照，
   结构化格式通过 `ConfigSource` 注入。
2. `xdk.text` 的 `Text` 类已不存在；T0 使用 `String`/`StringBuilder`。
3. `Regex` 的 T0-X 子集保留在 `xdk.text`；完整引擎归 `xdk.regex`（T1）。
4. `Random` 移到 `xdk.random`（T1）；`xdk.math` 只保留确定性算法。
5. 内嵌资源的 T0-X 读取子集保留在 `xdk.sys`；独立 `xdk.resource` 归 T1。
6. `xdk.errors` 增补 `DetailedError`、`ErrorDetail`、`ErrorGroup`、
   `toErrorReport`、`annotate`；`wrap`/`mapErr`/`report` 语义不变。
7. `xdk.collections` 的 T0-K 只承诺 `List`、`Map<String,Int>`、`Set<Int>`；
   通用 `Map<K,V>`/`Set<T>`、`Iterator` 不算 T0-K。
8. S6 的“API 以源码为权威”改为“规范 + T0 设计为权威，源码是实现”。

---

## 11. 变更记录

- v1.2：按用户决策修正 struct 引用字段、Int/Long 宽度、错误协议拆分、
  集合 T0 范围、提交粒度、X 阻塞策略、预算定位、权威顺序。
- v1.1：从文件清单推进到类级契约；增加 K/X 范围与命名规则。
- v1.0：包/文件总览（已被本版取代）。
