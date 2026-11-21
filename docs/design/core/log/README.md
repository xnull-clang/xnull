# `xdk.log` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.log` |
| 层 | `xdk.core` / L3 |
| 依赖 | `xdk.errors`、`xdk.runtime`、`xdk.text`、`xdk.time`、`xdk.io` |
| 被依赖 | `config`、`cli`、`net` |
| 稳定性 | 基础 `stable`；结构化/Sink `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.log` 提供分级日志：Level/Field/Record/Sink/Formatter/Logger/Factory。

不做：全局 logger、远程日志协议、文件轮转完整实现、采样/脱敏（X）。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式 logger | 无全局单例；Factory 由调用方持有 |
| 结构化 | Field/Record；纯文本也走 Formatter |
| 不改变控制流 | 日志失败只诊断，不抛业务错误 |
| 无隐式上下文 | 不读环境/全局变量；字段显式 |
| 资源 close | Sink 可持资源；close 幂等 |
| 非线程安全 | Sink 线程安全由实现声明 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Level` | enum | 日志级别 | [`Level.md`](Level.md) |
| `Field` | class | 键值字段 | [`Field.md`](Field.md) |
| `LogRecord` | class | 日志记录 | [`LogRecord.md`](LogRecord.md) |
| `Sink` | protocol | 输出目标 | [`Sink.md`](Sink.md) |
| `ConsoleSink` | class | 控制台输出 | [`ConsoleSink.md`](ConsoleSink.md) |
| `MemorySink` | class | 内存记录 | [`MemorySink.md`](MemorySink.md) |
| `Formatter` | protocol | 记录→文本 | [`Formatter.md`](Formatter.md) |
| `TextFormatter` | class | 文本格式 | [`TextFormatter.md`](TextFormatter.md) |
| `Logger` | class | 级别/字段/输出 | [`Logger.md`](Logger.md) |
| `LoggerFactory` | class | 命名 logger 管理 | [`LoggerFactory.md`](LoggerFactory.md) |

X 未纳入本批：`FileSink`、`RotatingFileSink`、`AsyncSink`、`MultiSink`、`Filter`、`LevelFilter`、`FieldFilter`、`Redactor`、`Sampler`、`JsonFormatter`。它们必须在后续批次单独设计，不得塞进现有类。

---

## 4. 技术/支撑/依赖

- 技术：级别比较、结构化字段、Sink 协议、Formatter、有界内存队列。
- 支撑：`Stdio`、`StringBuilder`、`time.nowMono/nowWall`、`Context`（异步 sink）。
- 依赖：`errors`、`runtime`、`text`、`time`、`io`、`Level`、`Field`、`LogRecord`、`Sink`、`Formatter`。

---

## 5. 场景

### L1：CLI 日志

`Logger` + `ConsoleSink`；级别过滤；stdout/stderr 选择由 sink 决定。

### L2：测试断言

`MemorySink`；`records()` 快照；容量/丢弃。

### L3：结构化字段

`Logger.withField`；`LogRecord.fields`；Formatter 输出 `key=value`。

### L4：服务边界

日志失败不改变 Result；`Context` 取消不阻塞日志。

---

## 6. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 全局 logger | 禁止 |
| 文件 sink/轮转 | X |
| 异步 sink | X |
| 过滤链 | X； 只有级别阈值 |
| 脱敏/采样 | X |
| JSON 格式 | X（依赖 codec） |
| 线程安全 | 实现声明；默认非线程安全 |
| 日志失败 | 诊断，不抛业务错误 |
