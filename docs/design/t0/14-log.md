# xdk.log —— T0 日志 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.log` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.runtime`、`xdk.text`、`xdk.time` |
| 被依赖 | config、cli、metrics（T1） |
| 对应源码 | `src/xdk/log/Log.x` |
| 当前状态 | Verified（mini；Field/Sink/Console/Memory） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 级别 | Debug/Info/Warn/Error 顺序 | `Level` |
| CAP-2 阈值 | 最低级别过滤 | `Logger.enabled` |
| CAP-3 输出 | 名称 + 消息 + 级别 | `Logger.log` |
| CAP-4 便捷方法 | debug/info/warn/error | `Logger` |
| CAP-5 字段 | 结构化 key/value | `Field`、`LogRecord` |
| CAP-6 输出端 | Console/Memory sink，可扩展 | `Sink`、`ConsoleSink`、`MemorySink` |

**非目标**：File sink、过滤链、脱敏、采样（T1）。

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
}

class Field { Field(String key, String value) }
class LogRecord { LogRecord(Level level, String loggerName, String message, List<Field> fields) }
protocol Sink { void write(LogRecord record); }
class ConsoleSink implements Sink { ConsoleSink(); void write(LogRecord record) }
class MemorySink implements Sink {
    MemorySink()
    void write(LogRecord record)
    List<String> lines()
    void clear()
}
```

- 级别顺序：Debug < Info < Warn < Error。
- 输出固定：`[LEVEL] name: message`；写入 stdout。
- `enabled(level)`：`level >= minimum`。
- 日志失败不改变业务控制流；T0 最小 sink 不做 I/O 错误传播。
- `withField`/`withSink` 返回新 `Logger`，原实例不变。
- `ConsoleSink` 输出 `[LEVEL] name: message key=value...`；无字段时与旧格式一致。
- `MemorySink` 追加格式化行；`lines()` 返回已记录行，`clear()` 清空。
- Sink 写入失败不改变业务控制流；File sink 属于 T1。
- `Logger`/sink 不持有 OS 资源，无 `close()`。

## 3. 测试义务

- 阈值过滤；
- 四个级别输出格式；
- 名称不同互不影响；
- 字段输出与 `withField` 不可变复制；
- MemorySink 行数与内容；
- base/full 输出一致。

场景：`xdk_log.x`。

## 4. 后续（T1）

- File sink、过滤、脱敏、采样；
- 时间戳/单调时钟字段。
