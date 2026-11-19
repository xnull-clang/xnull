# XDK T0 核心包详细设计 v1.1 · 总览

| 项 | 值 |
| --- | --- |
| 版本 | 1.1.0（替代 v1.0 提纲） |
| 状态 | Draft / 逐包评审中 |
| 依据 | S0 v1.1.0、S6 v3.0.0、S1–S5 |
| 目标 | 把 T0 从“包/文件清单”推进到“类级能力契约” |
| 组织 | 一个包一份设计，一份设计一次提交 |

> v1.0 回答“有哪些包、放哪些文件”；v1.1 回答“每个类具备什么能力、
> 每个方法在什么条件下做什么、失败是什么、调用后状态是什么”。
> 只写方法名、不写契约的条目，在评审中视为未设计。

---

## 1. 什么算“类级设计”

每个公开类必须包含以下 12 项；缺一项即未达到 v1.1 交付标准：

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

方法契约统一用下表表达，禁止只写“方法名 + 返回类型”：

| 方法 | 签名 | 前置条件 | 后置条件 | 失败 | 复杂度 | 并发/取消 |
| --- | --- | --- | --- | --- | --- | --- |

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

避免“一口画大饼”，每个包分两层：

- **T0-K（Kernel）**：没有它，该包不能算可用；必须先冻结、先实现、先回归。
- **T0-X（Extended）**：常用但可后补；不得阻塞 T0-K，也不得用空实现冒充。

| 包 | T0-K（必须先有） | T0-X（随后补齐） |
| --- | --- | --- |
| errors | ErrorKind、Error、BasicError、wrap、report | ErrorGroup、ResultOps、FFI code 映射、重试分类 |
| runtime | diagnose、exit、nowMono/nowWall | stdio 流、RuntimeInfo、断言、fatal 边界 |
| meta | language/xdk/target 版本 | 目标能力矩阵、构建元数据 |
| bytes | Bytes 基本转换/切片/比较、ByteReader/Writer | ByteBuffer 定位、Bits、varint、Cursor、Builder |
| text | trim/split/replace、parseInt/Float、Format | StringBuilder、Unicode、转义、数字格式化 |
| collections | List/Map/Set 契约、Iterator、sortBy/dedup/find | HashMap/Set、Deque、BitSet、算法族、适配器 |
| math | 常量、abs/clamp、floor/ceil/round、pow/sqrt/log、三角 | checked/saturating、Int128、统计、组合数学 |
| time | Instant/Duration/DateTime 基础换算 | 解析/格式化全量、日历加减、TimeZone、Stopwatch |
| io | Reader/Writer 协议、内存流、readAll/copy | Buffered、Chain/Tee/Limit、LineReader、stdio |
| fs | Path/File/Dir、exists/read/write/close | Metadata、walk/glob、Temp、Atomic、权限/链接 |
| sys | Process、env、platform、cwd | stdio 管道、信号、环境枚举、进程组 |
| tasks | Task/TaskGroup/Context、取消、joinDeadline | select/race、Context 值、取消作用域 |
| sync | Mutex、Channel、AtomicInt/Bool/Ref | RwLock、Semaphore、WaitGroup、Once、Barrier、select |
| log | Level、Logger、ConsoleSink | Field/Sink 分层、File/Memory sink、过滤、redaction |
| config | Config 快照、getOr/set、env allowlist | typed getter、overlay、Source、FileSource、校验 |
| cli | Args、usage、exitCode | OptionSpec、Command、子命令、help、补全 |

实现顺序仍按依赖：errors → runtime → meta → bytes → text → collections →
math → time → io → fs → sys → tasks → sync → log → config → cli。

---

## 4. 边界修正（v1.0 的错误）

| 能力 | v1.0 位置 | v1.1 归属 | 处理 |
| --- | --- | --- | --- |
| Regex | `xdk.text` | `xdk.regex`（T1） | 从 T0 文本面移出；text 只保留字面量匹配/查找，不提交正则引擎 |
| Random | `xdk.math` | `xdk.random`（T1） | math 只保留确定性算法；RNG 移出 |
| 内嵌资源 | `xdk.sys` | `xdk.resource`（T1） | sys 只保留文件/进程/环境；资源读取作为 T1 包 |
| 结构化配置解码 | `xdk.config` 依赖 codec | `ConfigSource` 注入 | T0 只做 `key=value`/env/内存快照 |

> 边界不是“以后再说”：T0 公开签名不得出现 T1 类型；T1 适配器通过协议注入。

---

## 5. 跨包契约

### 5.1 错误

- `Result<T,E>` 是唯一可恢复失败面；`ErrorKind` 是唯一跨包分类。
- 公开签名优先 `Error`；需要结构化字段时用 `DetailedError`。
- 不使用 `throw` 表达“文件不存在/解析失败/通道关闭”。

### 5.2 所有权

- `struct`：值复制，无 close。
- `class`：引用语义；持 OS 资源的类必须 `close()`。
- 方法签名必须写明：`borrow`（借用）/`consume`（消费）/`returnOwned`（返回新所有权）。
- `Result` 的 `value()` 返回借用还是所有权，逐类型写明，不靠猜。

### 5.3 取消

- 可阻塞方法首参 `Context`；取消返回 `CancelledError`。
- 取消后对象必须回到可预测状态（已关闭、未消费、未半写）。
- 超时是 deadline；`joinDeadline` 超时映射 `Timeout`，不伪装 `Cancelled`。

### 5.4 稳定性

每个公开符号标注 `stable` / `preview` / `internal`；T0-K 优先 `stable`。

---

## 6. API 预算（防止再次写成提纲）

| 包 | T0-K 公开符号（下限） | T0-X 目标 | 说明 |
| --- | --- | --- | --- |
| errors | 15 | 35 | 分类、构造、包装、报告、组合、映射 |
| runtime | 8 | 25 | 诊断、退出、时钟、stdio、信息 |
| meta | 6 | 15 | 版本、目标、能力 |
| bytes | 30 | 70 | 转换、游标、缓冲、位、端序 |
| text | 30 | 80 | 算法、Builder、Format、Parse、Unicode |
| collections | 40 | 120 | 容器、迭代器、算法、特化 |
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

预算不是 KPI，而是评审尺子：低于下限说明能力没设计完；高于目标要拆分或
降级到 T0-X/T1。

---

## 7. 评审清单

一份包设计通过评审，必须满足：

- [ ] 每个类有 12 项完整契约；
- [ ] 每个方法有前置/后置/失败/复杂度/并发取消列；
- [ ] 每个失败点有 `ErrorKind` 与可读消息；
- [ ] 每个资源有 close 生命周期与关闭后行为；
- [ ] 每个可阻塞点有取消语义；
- [ ] 有最小示例与反例；
- [ ] 有成功/失败/边界/取消/并发/泄漏测试义务；
- [ ] T0/T1 边界无违规；
- [ ] 场景、回归、差分/缺口已命名；
- [ ] 代码、场景、回归、文档同一提交。

---

## 8. 文档索引与完成度

| 文档 | 内容 | 状态 |
| --- | --- | --- |
| `00-overview.md` | 设计标准、能力模型、T0-K/X、边界修正 | 完成 |
| `01-errors.md` | 错误协议、构造、包装、聚合、Result 组合、FFI 映射 | 完成（样板） |
| `04-bytes.md` | Bytes、ByteBuffer、游标、位、端序 | 完成（样板） |
| `02-runtime.md` | 诊断、退出、时钟、stdio、运行时信息 | 待写 |
| `03-meta.md` | 版本、目标平台、目标能力 | 待写 |
| `05-text.md` | 文本算法、Builder、Format、Parse、Unicode | 待写 |
| `06-collections.md` | 容器、迭代器、算法、特化容器 | 完成（样板） |
| `07-math.md` | 数学函数、溢出、统计、Int128 | 待写 |
| `08-time.md` | Instant、Duration、DateTime、TimeZone | 待写 |
| `09-io.md` | Reader/Writer、缓冲、组合、stdio | 待写 |
| `10-fs.md` | Path、File、Dir、遍历、临时、原子 | 待写 |
| `11-sys.md` | Process、Env、Platform、Signal | 待写 |
| `12-tasks.md` | Task、TaskGroup、Context、取消 | 待写 |
| `13-sync.md` | Mutex、Channel、Atomics、同步器 | 待写 |
| `14-log.md` | Level、Logger、Field、Sink、过滤 | 待写 |
| `15-config.md` | Config、Source、Profile、校验 | 待写 |
| `16-cli.md` | Args、OptionSpec、Command、usage | 待写 |

已完成的 `01-errors.md`、`04-bytes.md`、`06-collections.md` 是后面的评审样板：
达不到它们的契约密度，就不算完成。

同目录 `appendices/` 放错误码表、所有权表、稳定性表、测试矩阵。

---

## 9. 交付节奏

一个包一份设计、一份实现、一份场景、一份回归、一次提交：

1. 先评设计（本文档对应包）；
2. 设计通过后写场景（先失败）；
3. 实现 T0-K；
4. 补 T0-X（可拆下一提交）；
5. 跑 mini/legacy/base/full；
6. 更新追溯矩阵与 `src/xdk/PLAN.md`。

不允许“先把 16 份文件生成出来，再回头补内容”；每一份包设计必须单独可评审。
