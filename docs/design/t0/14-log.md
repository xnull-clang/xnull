# xdk.log —— T0 日志 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.log` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.runtime`、`xdk.text`、`xdk.time` |
| 被依赖 | config、cli、metrics（T1） |
| 对应源码 | `src/xdk/log/Log.x` |
| 当前状态 | Verified（mini；Field/Sink/Console/Memory/时间戳/过滤/脱敏/采样） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 级别 | Debug/Info/Warn/Error 顺序 | `Level` |
| CAP-2 阈值 | 最低级别过滤 | `Logger.enabled` |
| CAP-3 输出 | 名称 + 消息 + 级别 | `Logger.log` |
| CAP-4 便捷方法 | debug/info/warn/error | `Logger` |
| CAP-5 字段 | 结构化 key/value | `Field`、`LogRecord` |
| CAP-6 输出端 | Console/Memory sink，可扩展 | `Sink`、`ConsoleSink`、`MemorySink` |
| CAP-7 时间字段 | 每条记录的墙钟/单调毫秒 | `LogRecord.timestampMs`、`LogRecord.monotonicMs` |
| CAP-8 时钟注入 | 默认系统时钟；测试可替换 | `Clock`、`SystemClock`、`Logger.withClock` |
| CAP-9 管道钩子 | 过滤 predicate、脱敏、确定性采样 | `Filter`/`PredicateFilter`、`Redactor`/`ReplaceRedactor`、`Sampler`/`EveryNSampler`、`Logger.withFilter/withRedactor/withSampler` |

**非目标**：File sink、异步/批量 sink、时间格式与 locale（T1）。

## 2. 契约

```text
enum Level { Debug, Info, Warn, Error }

class Logger {
    Logger(String name, Level minimum)
    Bool enabled(Level level)
    void log(Level level, String message)
    void debug(String message)
    void info(String message)
    void warn(String message)
    void error(String message)
    Logger withField(String key, String value)
    Logger withSink(Sink sink)
    Logger withClock(Clock clock)
    Logger withFilter(Filter filter)
    Logger withRedactor(Redactor redactor)
    Logger withSampler(Sampler sampler)
}

protocol Filter { Bool allow(LogRecord record); }
class PredicateFilter implements Filter { PredicateFilter(Bool(LogRecord) predicate) }
class KeepAllFilter implements Filter { KeepAllFilter() }

protocol Redactor { String redact(String value); }
class ReplaceRedactor implements Redactor { ReplaceRedactor(String needle, String replacement) }
class IdentityRedactor implements Redactor { IdentityRedactor() }

protocol Sampler { Bool keep(LogRecord record); }
class EveryNSampler implements Sampler { EveryNSampler(Int interval); Int count() }
class KeepAllSampler implements Sampler { KeepAllSampler() }

class Field { Field(String key, String value) }
class LogRecord {
    LogRecord(Level level, String loggerName, String message, List<Field> fields)
    Long timestampMs
    Long monotonicMs
    Long timestamp()
    Long monotonic()
}
protocol Clock { Long wallMs(); Long monoMs(); }
class SystemClock implements Clock { SystemClock(); Long wallMs(); Long monoMs(); }
protocol Sink { void write(LogRecord record); }
class ConsoleSink implements Sink { ConsoleSink(); void write(LogRecord record) }
class MemorySink implements Sink {
    MemorySink()
    void write(LogRecord record)
    List<String> lines()
    List<LogRecord> captured()
    void clear()
}
String recordTextWithTime(LogRecord record)
```

- 级别顺序：Debug < Info < Warn < Error。
- 输出固定：`[LEVEL] name: message`；写入 stdout。
- `enabled(level)`：`level >= minimum`。
- 日志失败不改变业务控制流；T0 最小 sink 不做 I/O 错误传播。
- `withField`/`withSink`/`withClock` 返回新 `Logger`，原实例不变，并保留其余配置。
- `ConsoleSink` 输出 `[LEVEL] name: message key=value...`；无字段时与旧格式一致。
- `MemorySink` 追加格式化行；`lines()` 返回已记录行，`captured()` 返回原始
  `LogRecord`（含时间字段），`clear()` 清空两者。
- `Logger.log` 在写入 sink 前用当前 `Clock` 填充 `timestampMs`（墙钟毫秒）和
  `monotonicMs`（单调毫秒）；`recordText` 不包含时间，保持既有输出稳定；
  `recordTextWithTime` 显式返回 `<timestamp> <recordText>`。
- 管道顺序固定为：级别阈值 → `Filter.allow` → `Sampler.keep` → `Redactor`
  → `Sink`。默认 `KeepAllFilter`/`KeepAllSampler`/`IdentityRedactor` 保持旧
  行为不变；`with*` 派生新 `Logger` 并保留其余配置。
- `ReplaceRedactor` 同时作用于 message 与每个 `Field.value`；空 needle 不改写。
- `EveryNSampler` 只统计已通过级别与过滤的记录，每第 N 条保留一条；
  `count()` 返回该 sampler 实例观察到的记录数，状态不跨实例共享。
- 默认时钟是 `SystemClock`（`xdk.runtime.nowWall/nowMono`）；测试用
  `withClock` 注入固定时钟即可获得确定性时间戳。
- Sink 写入失败不改变业务控制流；File sink 属于 T1。
- `Logger`/sink 不持有 OS 资源，无 `close()`。

## 3. 测试义务

- 阈值过滤；
- 四个级别输出格式；
- 名称不同互不影响；
- 字段输出与 `withField` 不可变复制；
- MemorySink 行数与内容；
- 每条记录的时间戳/单调字段来自注入时钟且不可变；
- `withField`/`withSink` 保留注入时钟；
- `recordText` 不因时间字段改变，`recordTextWithTime` 有显式前缀；
- filter 拒绝的记录不进入 sink 或 sampler；
- redactor 同时改写 message 与字段值；
- `EveryNSampler` 的保留集合由输入顺序确定，`count()` 与通过前置条件的
  记录数一致；
- 组合顺序为级别 → filter → sampler → redactor → sink；
- base/full 输出一致。

场景：`xdk_log.x`、`r4/log_timestamp.x`、`r4/log_pipeline.x`。

## 4. 后续（T1）

- File sink、异步/批量 sink；
- 时间格式/locale 与时钟源选择（当前只有毫秒 + 系统/注入时钟）。
