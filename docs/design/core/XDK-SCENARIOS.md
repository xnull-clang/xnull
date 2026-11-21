# XDK 核心层场景设计 v1.0

> **历史场景快照（2026-11-21）**：本文件不再作为验收依据。
> 新场景见各包 `core/<pkg>/README.md`、`core/CORE-PROFILES.md`、`core/PLATFORM-BOUNDARY.md`。

| 项 | 值 |
| --- | --- |
| 文档性质 | 场景设计方案；只写 API 使用方式与能力验证，不写代码 |
| 范围 |  核心层：14 个公共包 + 执行层内建 |
| 不讨论 | 编译器、FFI、运行时实现、测试脚本 |
| 目的 | 用真实程序形态验证核心层 API 是否“够用、好用、边界清楚” |
| 配套 | `XDK-CORE-API.md` 定义 API 面；本文定义场景与 API 缺口 |

---

## 0. 三条规矩

1. **只写方案，不写代码。** 本文中的 API 调用序列是设计符号，不是可编译代码。
2. **只关心 XDK API。** 编译器、FFI、运行时实现不在本文范围；需要它们的地方只写“由运行时提供”。
3. **场景驱动。** 每个场景必须回答：用哪些 API、为什么够用、哪里不够、失败/取消/资源怎么处理。

### 0.1 场景与  的边界

核心层不含网络、HTTP、JSON、消息队列、定时调度、指标系统。  
网络层已单独设计：见 `../net/NET-API.md` 与 `../net/NET-SCENARIOS.md`。  
因此后台服务器、监控、中间件场景中的这些能力按 ** 外部边界** 处理：

```text
[] transport / codec / queue / scheduler
        │
        ▼
  核心层 API：config / log / errors / tasks / sync /
              bytes / text / collections / io / fs / sys / time
        │
        ▼
  应用业务逻辑
```

本文不设计 `[]` 的内部 API；只验证核心层是否为它们提供了足够的支撑面。  
如果某个场景必须依赖  才能成立，会在场景中明确标注，不把  当成核心层能力。

### 0.2 场景模板

每个场景按固定结构写：

1. 目标与边界；
2. 参与者与组件；
3. 主流程（阶段表）；
4. 核心层 API 演练（阶段 → API → 目的）；
5. 失败、取消、资源；
6. 数据与所有权；
7. 暴露的 API 缺口/决策；
8. 场景验收谓词（不是测试脚本）。

---

## 1. 场景总览

| # | 场景 | 主要验证的核心层能力 |
| --- | --- | --- |
| S1 | 后台 HTTP 服务 | config/log/errors/tasks/sync/time/fs/io/text/bytes/collections/cli/sys |
| S2 | 监控采集程序 | sys/fs/time/collections/math/log/config/cli/tasks/sync |
| S3 | 消息中间件/转换管道 | bytes/text/collections/io/fs/log/errors/tasks/sync/config |
| S4 | CLI 数据处理工具 | cli/config/fs/io/text/collections/math/errors/log |
| S5 | 二进制协议网关 | bytes/io/text/collections/errors/tasks/sync/math |
| S6 | 后台任务编排/批处理 | tasks/sync/time/errors/log/config/fs/collections/cli/math |

共同覆盖：

- **错误**：每个场景都必须有可恢复失败路径，不允许用 panic 代替。
- **取消**：每个长流程都必须有 `Context`/取消边界。
- **资源**：每个文件/进程/通道都必须有 `close()` 或明确的生命周期。
- **配置**：每个可部署程序都必须有 profile/env 覆盖。
- **日志**：每个场景都必须能定位失败上下文。
- **退出码**：CLI/服务/批处理都必须有明确退出语义。

---

## 2. S1：后台 HTTP 服务

### 2.1 目标与边界

**目标**：一个长期运行的订单/用户服务；启动时加载配置，处理请求，共享少量内存状态，支持优雅停机。

**边界**：

- `[] xdk.net.http`：监听、路由、请求体 `Reader`、响应 `Writer`、每请求 `Context`。
- `[] xdk.codec`：JSON 编解码。
- 核心层负责：配置、日志、错误、任务组、互斥、时间、文件、流、文本、字节、集合、CLI、系统环境。

### 2.2 参与者

| 组件 | 职责 |
| --- | --- |
| `main` | 解析参数、加载配置、初始化日志、启动服务 |
| `Service` | 持有配置、日志、共享状态、根 `TaskGroup` |
| `Handler` | 每个请求的业务处理；返回 `Result<Response, Error>` |
| `Store` | 共享内存状态；用 `Mutex`/`Atomic*` 保护 |
| `[] HttpServer` | 监听端口、创建请求上下文、调用 Handler |

### 2.3 主流程

| 阶段 | 动作 | 核心层 API |
| --- | --- | --- |
| 启动 | 解析 `--profile`、`--config` | `cli.Args.has/valueOrNull/valueOr`、`cli.usage`、`cli.exitCodeFor` |
| 启动 | 读取配置文件 | `fs.exists/readText`、`config.Config`、`config.ConfigSource`（X） |
| 启动 | 环境覆盖 | `config.loadEnv`、`sys.envOrNull/envOr` |
| 启动 | 初始化日志 | `log.Logger`、`log.Level`、`log.Field`（X） |
| 启动 | 版本/平台诊断 | `meta.languageVersion/xdkVersion/targetPlatform`、`sys.platform/arch/hostname/pid` |
| 启动 | 创建根任务组 | `TaskGroup.create(Context.background())` |
| 请求 | 读取请求体 | `[] HttpServer` 提供 `Reader`；`bytes.ByteReader` 解析 |
| 请求 | JSON 解码 | `[] codec`；失败映射 `ErrorKind.DataCorrupted` |
| 请求 | 校验字段 | `text.isEmpty/isBlank/parseInt`、`collections.List/Map` |
| 请求 | 业务处理 | `errors.Result`、`errors.mapErr`、`errors.report` |
| 请求 | 共享状态 | `sync.Mutex.withLock`、`sync.AtomicInt` |
| 请求 | 读写文件 | `fs.File`、`fs.Path`、`io.Reader/Writer` |
| 请求 | 记录日志 | `Logger.info/warn/error`、`Logger.withField`（X） |
| 响应 | 编码并写回 | `[] codec`、`io.Writer` |
| 停机 | 取消根上下文 | `Context.cancel` |
| 停机 | 等待请求结束 | `TaskGroup.close` |
| 停机 | 关闭文件/进程 | `File.close`、`Process.close` |
| 停机 | 退出 | `runtime.exit`、`cli.exitCodeFor` |

### 2.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 参数 | `Args.has("--profile")`、`Args.valueOr("--profile", "dev")` | 选择配置 profile |
| 配置 | `Config.getOr("http.port", "8080")`、`Config.tryGet`（X） | 读取端口/超时/路径 |
| 配置来源 | `FileSource.load(Context)`（X） | 从文件加载 key=value |
| 日志 | `Logger.info("listening")`、`Logger.error(error.describe())` | 启动/错误观测 |
| 请求作用域 | `TaskGroup.create(requestContext)` | 每请求子任务 |
| 取消 | `Context.isCancelled()` | 长循环检查 |
| 共享状态 | `Mutex.withLock(body)` | 保护订单表 |
| 计数器 | `AtomicInt.addAndGet(1)`（X）/`compareExchange` | 请求计数 |
| 文件 | `openFileRead(path)`、`File.readText()`、`File.close()` | 静态资源/模板 |
| 流 | `Reader.readBytes(count)`、`Writer.writeBytes(data)` | 请求/响应体 |
| 错误 | `mapErr(result, (error) -> ...)`、`report(result)` | 错误转换与边界观测 |
| 超时 | `Duration`、`time.nowMs()`、`Task.joinDeadline(deadline)` | 请求截止 |
| 退出 | `runtime.exit(0)` | 正常停机 |

### 2.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 配置缺失 | `Config.getOr` 用默认值；必填项用 `tryGet` → `NotFound`，启动失败退出 |
| 端口占用 | `[] HttpServer` 返回 `Unavailable`/`Io`；核心层只负责映射与日志 |
| 请求超时 | 请求 `Context` 取消；`Task.joinDeadline` 返回 `Timeout`；Handler 返回 `Err(Timeout)` |
| 客户端断开 | `[]` 取消请求 `Context`；Handler 检查 `isCancelled`，停止写文件/响应 |
| 校验失败 | `ErrorGroup` 聚合字段错误；映射为 400（） |
| 存储失败 | `fs.File.writeText` 返回 `Result`；`ErrorKind.Io`；请求返回 500 |
| 停机 | 取消根 `Context`；`TaskGroup.close` 幂等；文件/进程逐个 `close` |
| 资源泄漏 | 所有 `File`/`Dir`/`Process` 必须在 `defer` 或显式路径关闭 |

### 2.6 数据与所有权

- 请求体 `Reader` 借用  缓冲区；Handler 不得跨请求保留。
- `Map`/`List` 共享状态由 `Mutex` 保护；返回快照给日志/响应，避免外部修改内部容器。
- `File` 每请求打开/关闭，或使用短生命周期句柄；不跨请求共享写句柄。
- `Logger` 可跨任务共享；sink 线程安全由 `[]` 或 X `Sink` 保证。

### 2.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `Context` 不携带请求 ID/值 | 日志无法自动关联请求 | X `Context` 值或显式 `Logger.withField` |
| `log.Field`/`Sink` 是 X | 生产日志不够结构化 | X 先落 `Field` + `ConsoleSink` |
| `Config` 类型化 getter 是 X | 端口/超时需手动 `parseInt` | X `getIntOr/tryGetInt` |
| `Config.FileSource` 是 X | 启动配置只能内存/env | X `FileSource` |
| `sys.Signal` 是 X | 优雅停机只能依赖  server | X `Signal` + 信号监听 |
| `File`/`Dir` 是 K，但 `Metadata` 是 X | 静态资源/缓存校验缺 mtime | X `Metadata` |
| `Reader/Writer` 资源流 close 是 X |  请求体关闭责任不清 | X 明确 `Reader.close` 契约 |

### 2.8 场景验收谓词

- 启动失败必须给出 `Result`/诊断，不允许静默使用空配置。
- 每个请求的失败必须落到 `ErrorKind`，不得用 panic 表达 404/400/500。
- 请求取消后不得继续写响应或文件。
- 停机后 `TaskGroup.close` 返回 `Ok` 或首个非取消错误；重复 close 幂等。
- 所有文件/进程句柄在正常/异常/取消三条路径都关闭。

---

## 3. S2：监控采集程序

### 3.1 目标与边界

**目标**：周期性采集主机/进程/文件指标，聚合后写报告或推送；支持优雅停止。

**边界**：

- `[] xdk.timer` / `xdk.schedule`：周期触发。
- `[] xdk.metrics`：指标注册/导出（可选）。
- 核心层负责：采集、聚合、配置、日志、文件、时间、错误、任务。

### 3.2 参与者

| 组件 | 职责 |
| --- | --- |
| `main` | 解析参数、加载配置、启动采集循环 |
| `Collector` | 采集单个目标（进程/文件/主机） |
| `Aggregator` | 聚合样本、计算 min/max/mean/quantile |
| `Reporter` | 写文件/stdout/日志 |
| `[] Timer` | 周期触发 `Collector` |

### 3.3 主流程

| 阶段 | 动作 | 核心层 API |
| --- | --- | --- |
| 启动 | 解析参数/配置 | `cli.Args`、`config.Config`、`config.loadEnv` |
| 启动 | 初始化日志 | `Logger`、`Level` |
| 采集 | 平台/主机信息 | `sys.platform/arch/hostname/pid`、`sys.envOrNull` |
| 采集 | 进程状态 | `sys.runProcessResult`、`Process.wait`、`Process.close` |
| 采集 | 文件状态 | `fs.exists`、`fs.fileMtime`、`fs.File.size`、`Dir.entries` |
| 采集 | 时间戳 | `time.nowMs`、`time.nowWallMs`、`DateTime.iso8601` |
| 聚合 | 列表/映射 | `collections.List/Map`、`sortBy`、`reduce` |
| 聚合 | 统计 | `math.sum/mean/median/variance/stddev/quantile` |
| 判定 | 阈值/告警 | `config.Config`、`log.warn/error`、`errors.ErrorGroup` |
| 输出 | 写报告 | `fs.writeText`、`File.writeText`、`io.Writer` |
| 循环 | 周期/取消 | `[] Timer` 或 `time.sleep`；`Context.isCancelled` |
| 停止 | 关闭资源 | `Process.close`、`File.close`、`TaskGroup.close` |

### 3.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 环境 | `sys.envOr("MONITOR_INTERVAL", "5")` | 读取间隔 |
| 进程 | `runProcessResult("ps ...")` | 采集进程输出/退出码 |
| 文件 | `File.size()`、`fileMtime(path)` | 文件大小/修改时间 |
| 目录 | `openDir(path)`、`Dir.next()` | 遍历采集目录 |
| 时间 | `nowMs()`、`Duration`、`DateTime.format` | 采样时间/耗时 |
| 聚合 | `List.push`、`sortBy`、`List.get` | 样本排序/取值 |
| 统计 | `mean(values)`、`quantile(values, 0.95)` | 指标聚合 |
| 告警 | `ErrorGroup.add`、`Logger.warn` | 多目标失败聚合 |
| 报告 | `writeText(path, text)` | 输出报告 |
| 取消 | `Context.isCancelled`、`TaskGroup.cancel` | 停止采集 |

### 3.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 单个目标失败 | `Collector` 返回 `Err`；`Aggregator` 用 `ErrorGroup` 聚合，不中断其他目标 |
| 进程不存在 | `Process.wait`/`runProcessResult` → `NotFound`/`Io`；记录并继续 |
| 文件权限不足 | `fs.File`/`fileMtime` → `PermissionDenied`；记录并继续 |
| 报告写失败 | `writeText` → `Io`；保留上一次报告，不半写（X 原子写） |
| 取消 | 周期触发检查 `Context`；当前采集完成后停止，不启动新采集 |
| 资源 | 每个 `Process`/`File`/`Dir` 在采集结束关闭；失败路径也关闭 |

### 3.6 数据与所有权

- 样本 `List<Double>` 由 Aggregator 持有；报告只读快照。
- `ProcessResult` 是值对象；`stdout/stderr` 由调用方持有。
- `Dir.next` 返回 nullable；遍历结束后不再调用。
- 报告写入使用 `File`/`writeText`；不共享写句柄。

### 3.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `sys.Env` 快照是 X | 多环境变量读取逐个调用 | X `Env.snapshot` |
| `sys.Signal` 是 X | 无法优雅响应 SIGTERM | X `Signal` |
| `File.Metadata` 是 X | 权限/链接信息不足 | X `Metadata` |
| `DirEntry` 是 X | `Dir.next` 只给名字 | X `DirEntry` |
| `fs.writeText` 原子写是 X | 报告可能半写 | X `writeTextAtomic` |
| `[] Timer` | 核心层无周期调度 | 由  提供；核心层只提供 `Duration`/`sleep` |
| `[] Metrics` | 指标注册/导出 | 由  提供；核心层不抢 |

### 3.8 场景验收谓词

- 单个采集目标失败不导致整个程序退出；错误必须被聚合/记录。
- 取消后不再启动新采集；当前采集资源必须关闭。
- 报告写入失败必须可见，不得静默产生空报告。
- 进程句柄不得泄漏；`Process.close` 在成功/失败/取消路径都执行。

---

## 4. S3：消息中间件/转换管道

### 4.1 目标与边界

**目标**：从队列/传输层消费消息，解码、校验、转换、路由、落盘/转发；支持死信、重试、背压。

**边界**：

- `[] xdk.queue` / `xdk.net`：消息来源/目的地。
- `[] xdk.codec`：JSON/CSV 等结构化编码。
- 核心层负责：字节/文本处理、集合、流、文件、错误分类、任务/通道、配置、日志。

### 4.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Consumer` | 从  队列取消息 |
| `Decoder` | 字节 → 文本/结构 |
| `Validator` | 字段/格式校验 |
| `Transformer` | 字段映射/过滤/富化 |
| `Router` | 按规则选择目的地 |
| `DeadLetter` | 写失败消息 |
| `WorkerPool` | 有界并发/背压 |

### 4.3 主流程

| 阶段 | 动作 | 核心层 API |
| --- | --- | --- |
| 启动 | 加载路由/重试配置 | `Config`、`cli.Args`、`config.loadEnv` |
| 消费 | 取消息 | `[] queue` → `Bytes`/`Reader` |
| 解码 | 帧/文本 | `ByteReader`、`toUtf8`、`split`、`[] codec` |
| 校验 | 字段/格式 | `text.isEmpty/isBlank/parseInt`、`Regex.isMatch` |
| 转换 | 映射/过滤 | `collections.List/Map/Set`、`text.replace`、`bytes` |
| 路由 | 规则表 | `Map<String, Route>`、`Config.getOr` |
| 落盘 | 死信/审计 | `File.writeText`、`fs.writeText`、`writeLine` |
| 确认 | ack/nack | `[] queue`；`Result` 决定 |
| 重试 | 分类/退避 | `errors.isRetryable`、`time.sleep`、`[] timer` |
| 背压 | 有界队列 | `Channel<T>`、`TaskGroup` |
| 停机 | 取消/关闭 | `Context.cancel`、`Channel.close`、`TaskGroup.close` |

### 4.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 帧读取 | `ByteReader.readExact(count)`、`tryReadU8` | 解析消息头 |
| 文本 | `toUtf8(bytes)`、`split(text, separator)` | 解码/分段 |
| 校验 | `Regex.isMatch`、`parseInt` | 格式/数字校验 |
| 转换 | `replace`、`Map.getOr`、`Set.add` | 字段映射/去重 |
| 路由 | `Map<String, String>`、`keys/values/entries` | 路由表 |
| 死信 | `File` append、`writeText` | 记录失败消息 |
| 重试 | `isRetryable(kind)`、`ErrorGroup` | 可重试/不可重试分类 |
| 背压 | `Channel(capacity)`、`send/receive` | 有界缓冲 |
| 并发 | `TaskGroup.spawn`、`close` | 工作者生命周期 |
| 日志 | `Logger.withField`（X） | 消息 ID/路由 |

### 4.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 解码失败 | `DataCorrupted`；写死信；ack 原消息（避免毒消息循环） |
| 校验失败 | `ErrorGroup` 聚合字段错误；死信 + 原因 |
| 路由缺失 | `NotFound`；默认路由或死信 |
| 目的地暂时不可用 | `Unavailable`；`isRetryable` → 重试；超过次数 → 死信 |
| 背压 | `Channel.send` 阻塞；停机时 `Context` 取消 → `Cancelled` |
| 停机 | 停止接收；等待在途消息；`Channel.close`；`TaskGroup.close` |
| 文件句柄 | 每条消息/每批打开关闭；死信 writer 可批量但必须 flush/close |

### 4.6 数据与所有权

- 消息 `Bytes` 由 Consumer 持有；Decoder 返回文本/结构副本，不长期保留原始缓冲区。
- `Channel<T>` 传递引用类型时按引用；发送后发送方不得修改。
- `File` 写死信；失败消息内容必须完整写入后再 ack。
- `Map` 路由表构建后只读；运行期不修改，避免并发问题。

### 4.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `Channel.select` 是 X | 多通道聚合/超时不便 | X `select` |
| `groupBy` 是 X | 按路由/类型分组统计不便 | X `groupBy` |
| `File` 原子写是 X | 死信/审计可能半写 | X `writeTextAtomic` |
| `Map.entries` 任意 K/V 是 X | 路由表值对象受限 | X 通用 entries |
| `Text`/`Regex` 完整能力是 X | 复杂消息格式受限 | 按需扩展 |
| `[] codec/queue` | JSON/消息传输不在核心层 | 保持边界，不在核心层实现 |

### 4.8 场景验收谓词

- 毒消息不得无限重试；必须有死信路径。
- 背压必须有界；不得无限堆积内存。
- 停机时在途消息要么完成并 ack，要么明确 nack/重投；不得静默丢失。
- 取消后不得再产生外部可见副作用（ack/写死信/转发）。

---

## 5. S4：CLI 数据处理工具

### 5.1 目标与边界

**目标**：读取一个或多个输入文件，解析、过滤、排序、聚合，输出文本/二进制报告；支持参数、配置、退出码。

**边界**：核心层 only；无网络/队列。

### 5.2 参与者

| 组件 | 职责 |
| --- | --- |
| `main` | 参数/配置/退出码 |
| `Input` | 文件/标准输入读取 |
| `Parser` | 文本/字节解析 |
| `Pipeline` | 过滤/排序/聚合 |
| `Output` | 文件/stdout 写入 |

### 5.3 主流程

| 阶段 | 动作 | 核心层 API |
| --- | --- | --- |
| 参数 | 解析 flags/位置参数 | `cli.Args`、`usage`、`exitCodeFor` |
| 配置 | profile/env | `Config`、`loadEnv` |
| 输入 | 存在性/读取 | `fs.exists`、`readText`、`openFileRead` |
| 流式读取 | 大文件 | `File.read(maxBytes)`、`io.Reader` |
| 解析 | 文本/数字 | `split`、`parseInt`、`parseFloat`、`ByteReader` |
| 过滤 | 条件 | `collections.find/any/all/countIf` |
| 排序 | 比较器 | `sortBy`、`sortedBy` |
| 聚合 | 分组/统计 | `Map`、`math.sum/mean/median`、`groupBy`（X） |
| 输出 | 文本/二进制 | `Writer`、`File.writeText`、`fs.writeText` |
| 退出 | 错误映射 | `exitCodeFor`、`runtime.exit` |

### 5.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 参数 | `Args.valueOrNull("--input")`、`Args.positionals()` | 输入/输出路径 |
| 缺参 | `Args.tryValue("--input")`（X） | `NotFound` → usage |
| 文件 | `readText(path)` | 小文件读取 |
| 流 | `openFileRead(path)`、`read(maxBytes)` | 大文件分块 |
| 解析 | `parseInt(line)`、`split(line, ",")` | CSV/行解析 |
| 集合 | `List.push`、`sortBy`、`dedup` | 清洗/排序 |
| 统计 | `mean`、`median`、`quantile` | 汇总 |
| 输出 | `Writer.writeBytes`、`File.writeText` | 报告 |
| 错误 | `Result`、`ErrorGroup`、`report` | 失败路径 |
| 退出 | `exitCodeFor("usage")` | 退出码 |

### 5.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 输入缺失 | `NotFound`；输出 usage；退出码 2 |
| 解析失败 | `InvalidArgument`；报告行号/字段；退出码 1 |
| 大文件 | 流式读；分块处理；不一次性加载 |
| 输出失败 | `Io`/`PermissionDenied`；不产生半文件（X 原子写） |
| Ctrl-C | `Context` 取消；关闭输入/输出；退出码 130（应用约定） |
| 资源 | `File`/`Reader`/`Writer` 关闭；stdout 不关闭 |

### 5.6 数据与所有权

- `List<String>` 解析后由 Pipeline 持有；输出只读。
- `File` 读取返回副本；不保留内部缓冲区。
- `Writer.toBytes()` 是副本；`takeBytes()` 是转移（X）。
- 大文件不使用 `readText`；使用 `File.read`/`Reader.readBytes`。

### 5.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `parseLong` 是 X | 64 位数字解析需手写 | X `parseLong` |
| `groupBy` 是 X | 分组统计不便 | X `groupBy` |
| 类型化 config getter 是 X | 配置数字/布尔转换重复 | X getter |
| `Args.tryValue` 是 X | 缺参只能用空串判断 | X checked 取值 |
| `File` 原子写是 X | 输出失败可能留半文件 | X `writeTextAtomic` |
| `Writer.takeBytes` 是 X | 大输出多一次复制 | X take 语义 |

### 5.8 场景验收谓词

- 缺参/非法参数必须走 usage 退出码，不得 panic。
- 解析失败必须报告位置/原因，不得静默跳过。
- 大文件不得一次性读入内存。
- 输出失败不得留下“部分成功”的假象；原子写是 X 目标。

---

## 6. S5：二进制协议网关

### 6.1 目标与边界

**目标**：从连接读取二进制帧，校验头部/长度/校验和，解码 payload，路由并返回响应；支持并发连接、半包、粘包、坏帧。

**边界**：

- `[] transport`：TCP/串口/管道；提供 `Reader`/`Writer` 和 `Context`。
- 核心层负责：字节游标、端序、位操作、文本、集合、错误、任务/通道、文件（抓包/回放）。

### 6.2 参与者

| 组件 | 职责 |
| --- | --- |
| `Connection` | 单连接读写循环 |
| `FrameDecoder` | 读头/长度/payload |
| `Validator` | magic/version/checksum |
| `Dispatcher` | 按消息类型路由 |
| `Responder` | 编码响应 |
| `Capture` | 可选抓包/回放 |

### 6.3 主流程

| 阶段 | 动作 | 核心层 API |
| --- | --- | --- |
| 连接 | 获取 Reader/Writer/Context | `[] transport` → `io.Reader/Writer` |
| 读头 | 固定头 | `ByteReader.readExact`、`Endian.readShortBE` |
| 长度 | 读 payload 长度 | `ByteReader.intBE`、`Bits` |
| 校验 | magic/version/checksum | `tryRead*`、`Bits.popCount`、`[] crypto`（可选） |
| 读体 | 恰好读取 | `ByteReader.readExact(count)` |
| 解码 | 文本/字段 | `toUtf8`、`text.split`、`collections.Map` |
| 路由 | 类型表 | `Map<Int, Handler>`、`getOr` |
| 响应 | 写头/体 | `ByteWriter.writeU16BE`、`Writer.writeBytes` |
| 并发 | 连接任务 | `TaskGroup.spawn`、`Channel` |
| 抓包 | 文件 | `File.write`、`fs` |
| 关闭 | 取消/关闭 | `Context.cancel`、`Reader/Writer.close`（X） |

### 6.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 半包 | `ByteReader.readExact(count)` | 不足 → `DataCorrupted`，位置不变 |
| 头解析 | `readShortBE/readIntBE` | 大端字段 |
| 无符号 | `readIntBE` → `Long` | 0..4294967295 |
| 位 | `popCount`、`shiftRight` | 标志位/校验 |
| 文本 | `utf8ToUtf16`/`fromCodePoint` | 字符串字段 |
| 路由 | `Map<Int, String>` | 消息类型表 |
| 响应 | `ByteWriter.writeBytes` | 组帧 |
| 取消 | `Context.isCancelled` | 连接关闭 |
| 并发 | `TaskGroup`/`Channel` | 每连接任务/工作者 |
| 抓包 | `File.write` | 原始帧落盘 |

### 6.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 半包/截断 | `readExact` → `DataCorrupted`；关闭连接；不消费半帧 |
| 坏 magic | `InvalidArgument`/`DataCorrupted`；记录并关闭 |
| 长度超限 | `InvalidArgument`；拒绝分配大缓冲 |
| 未知类型 | `Unsupported`；返回错误帧或忽略 |
| 校验和失败 | `DataCorrupted`；抓包保留原始帧 |
| 连接取消 | `Context.cancel`；停止读写；`close` 幂等 |
| 资源 | `Reader/Writer` 由 transport 关闭；`File` 抓包句柄显式关闭 |

### 6.6 数据与所有权

- `ByteReader` 借用源 `Bytes`；读取期间源不得修改。
- `readExact` 返回副本；响应组帧使用独立 `ByteWriter`。
- `TaskGroup` 持有连接任务；`close` 等待。
- 抓包文件每连接/每批打开关闭；不共享写句柄。

### 6.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `io.Reader/Writer` 资源 close 是 X | 连接关闭责任不清 | X `close()` + `isOpen()` |
| `ByteBuffer` position/limit 是 X | 零拷贝组帧不便 | X 明确 position/limit |
| checksum/crypto 是  | 协议校验需外部 | 保持  |
| `Channel.select` 是 X | 多连接事件聚合不便 | X select |
| `Bytes` 零拷贝视图是 X/ | 大帧复制成本 | 暂不承诺 |

### 6.8 场景验收谓词

- 半包/截断必须返回 `DataCorrupted`，不得读越界或返回半帧。
- 未知类型/坏 magic 必须有明确分类，不得 panic。
- 取消后不得继续写响应/抓包。
- 连接关闭后 `close` 幂等；资源不泄漏。

---

## 7. S6：后台任务编排/批处理

### 7.1 目标与边界

**目标**：生产者-工作者批处理；有界并发、重试、进度、错误聚合、优雅停机。

**边界**：

- `[] xdk.schedule` / `xdk.executor`：定时/执行器（可选）。
- 核心层负责：任务/任务组、通道、互斥、原子量、时间、错误、日志、配置、文件、集合、统计。

### 7.2 参与者

| 组件 | 职责 |
| --- | --- |
| `main` | 参数/配置/启动 |
| `Producer` | 产生任务/读取输入 |
| `WorkerPool` | N 个工作者 |
| `RetryPolicy` | 可重试分类/次数 |
| `Progress` | 进度/计数 |
| `Reporter` | 结果/错误输出 |

### 7.3 主流程

| 阶段 | 动作 | 核心层 API |
| --- | --- | --- |
| 启动 | 参数/配置 | `cli.Args`、`Config` |
| 启动 | 根上下文/任务组 | `Context.background`、`TaskGroup.create` |
| 生产 | 有界队列 | `Channel<T>(capacity)`、`send` |
| 工作者 | 并发消费 | `TaskGroup.spawn`、`receive` |
| 互斥 | 共享计数/输出 | `Mutex`、`AtomicInt` |
| 工作 | 文件/文本/集合 | `fs`、`io`、`text`、`collections` |
| 重试 | 分类/退避 | `isRetryable`、`time.sleep` |
| 聚合 | 错误/结果 | `ErrorGroup`、`collections` |
| 进度 | 计数/日志 | `AtomicInt.addAndGet`（X）、`Logger` |
| 停机 | 取消/关闭 | `Context.cancel`、`Channel.close`、`TaskGroup.close` |

### 7.4 API 演练

| 能力 | API | 作用 |
| --- | --- | --- |
| 任务 | `TaskGroup.spawn(body)` | 工作者 |
| 结果 | `Task.join`/`joinDeadline` | 等待/超时 |
| 通道 | `Channel(capacity)`、`send/receive` | 有界队列 |
| 互斥 | `Mutex.withLock` | 共享输出/计数 |
| 原子 | `AtomicInt.compareExchange/addAndGet` | 进度/去重 |
| 错误 | `ErrorGroup.add`、`kind()` | 聚合失败 |
| 重试 | `isRetryable(kind)` | 分类 |
| 时间 | `Duration`、`sleep` | 退避 |
| 日志 | `Logger.warn/error` | 进度/失败 |
| 关闭 | `TaskGroup.close`、`Channel.close` | 优雅停机 |

### 7.5 失败、取消、资源

| 情况 | 设计 |
| --- | --- |
| 单个任务失败 | 记录/聚合；是否中止由配置决定 |
| 取消 | 根 `Context` 取消；工作者停止取新任务；在途任务决定是否完成 |
| 通道关闭 | `send` → `Unavailable`；`receive` 取完剩余后 `Unavailable` |
| 任务组关闭 | 取消子任务；等待；返回首个非取消错误；幂等 |
| 重试 | 仅 `isRetryable` 分类；次数/退避有上限；取消立即停止 |
| 资源 | 每个任务关闭自己的文件/进程；共享 writer 由 owner 关闭 |

### 7.6 数据与所有权

- `Channel<T>` 传递任务引用；发送后发送方不修改。
- `ErrorGroup` 只在协调任务中构建；工作者返回 `Err`，不直接写共享组。
- `AtomicInt` 用于进度；复杂状态用 `Mutex`。
- `TaskGroup.close` 后不再 spawn；重复 `close` 幂等。

### 7.7 暴露的 API 缺口

| 缺口 | 影响 | 建议 |
| --- | --- | --- |
| `Channel.close` 后剩余元素语义 | 工作者是否处理剩余不明确 | 明确“关闭后 receive 取完剩余再 Unavailable” |
| `Channel.select` 是 X | 多队列/超时不便 | X select |
| 可取消 `sleep` 是 X | 重试退避无法及时取消 | X `sleep(Context, Duration)` |
| `AtomicInt.addAndGet` 是 X | 进度需 CAS 循环 | X 原子算术 |
| `[] executor/schedule` | 核心层无线程池/定时 | 由  提供；核心层只给任务原语 |
| `[] metrics` | 进度指标导出 | 由  提供 |

### 7.8 场景验收谓词

- 任务失败不得导致泄漏或无限重试；必须有上限/分类。
- 取消后不再 spawn/取新任务；在途任务有明确完成/取消语义。
- `TaskGroup.close` 幂等；重复 close 返回 `Ok`。
- 通道关闭后发送返回 `Unavailable`；接收取完剩余后返回 `Unavailable`。
- 进度计数不丢失；并发下不重复/不跳过（按设计承诺）。

---

## 8. 场景到 API 的覆盖矩阵

| 包/API 面 | S1 服务 | S2 监控 | S3 中间件 | S4 CLI | S5 协议 | S6 批处理 |
| --- | --- | --- | --- | --- | --- | --- |
| `errors` | 是 | 是 | 是 | 是 | 是 | 是 |
| `runtime` | 是 | 是 | 是 | 是 | 是 | 是 |
| `meta` | 是 | 是 | 是 | 是 | 是 | 是 |
| `bytes` | 是 | — | 是 | 是 | 是 | — |
| `text` | 是 | — | 是 | 是 | 是 | 是 |
| `collections` | 是 | 是 | 是 | 是 | 是 | 是 |
| `math` | — | 是 | — | 是 | 是 | 是 |
| `time` | 是 | 是 | 是 | 是 | 是 | 是 |
| `io` | 是 | — | 是 | 是 | 是 | 是 |
| `fs` | 是 | 是 | 是 | 是 | 是 | 是 |
| `sys` | 是 | 是 | — | — | — | 是 |
| `log` | 是 | 是 | 是 | 是 | 是 | 是 |
| `config` | 是 | 是 | 是 | 是 | 是 | 是 |
| `cli` | 是 | 是 | — | 是 | — | 是 |
| 执行层 tasks/sync | 是 | 是 | 是 | — | 是 | 是 |

结论：

- 核心层 API 能覆盖六类程序的骨架。
- 网络/队列/调度/JSON/指标必须由  提供；核心层不抢这些职责。
- 场景暴露的缺口集中在 X：结构化日志、类型化配置、文件元数据、原子写、可取消 sleep、`select`、`groupBy`、`parseLong`、`AtomicInt` 算术。

---

## 9. 场景评审结论

### 9.1 够用的部分

- **错误/取消/资源**三套契约能贯穿服务、监控、中间件、CLI、协议、批处理六类程序。
- **config/log/cli** 能支撑可部署程序的基本治理面。
- **bytes/text/collections** 能支撑协议解析、数据清洗、路由与聚合。
- **fs/io/sys** 能支撑文件、进程、环境、资源读取。
- **tasks/sync** 能支撑请求作用域、生产者-消费者、有界队列、共享状态。

### 9.2 必须先补的 API（按场景）

| 优先级 | 缺口 | 触发场景 | 建议 |
| --- | --- | --- | --- |
| P0 | `Config` 类型化 getter | S1/S2/S4 | X `getIntOr/tryGetInt` 等 |
| P0 | `log.Field`/`Sink` | S1/S3/S6 | X 结构化日志 |
| P0 | `File`/`Dir` 的 `Result` 面与 `close` | S1/S2/S3/S5 | 已在 API 面中定义，需冻结 |
| P0 | `Channel` 关闭/取消语义 | S3/S6 | 已在 API 面中修正 |
| P1 | `writeTextAtomic` | S2/S3/S4 | X 原子写 |
| P1 | 可取消 `sleep` | S6 | X `sleep(Context, Duration)` |
| P1 | `groupBy` | S3/S4/S6 | X |
| P1 | `parseLong` | S4/S5 | X |
| P1 | `Metadata`/`DirEntry` | S2 | X |
| P2 | `select` | S3/S5/S6 | X |
| P2 | `AtomicInt.addAndGet` | S6 | X |
| P2 | `Context` 值/请求 ID | S1 | X 或显式日志字段 |

### 9.3 场景不改变的原则

- 核心层不实现网络/HTTP/队列/JSON/调度/指标；这些是 。
- 核心层不引入全局可变状态；配置/日志/任务都是显式对象。
- 核心层不把“能跑”当成“API 够用”；场景只验证 API 面是否闭合。
- 场景中的 `[]` 只作为边界，不作为核心层 API 承诺。

---

## 10. 下一步

如果这版场景方向认可，下一步只做设计工作：

1. 用 S1–S6 逐项回写 `XDK-CORE-API.md` 的缺口/决策；
2. 为每个场景补“最小 API 路径”和“禁止路径”；
3. 对每个 X 缺口给出“是否进入 1.0”的签字项；
4. 不改实现，不写测试脚本，不讨论编译器/FFI。
