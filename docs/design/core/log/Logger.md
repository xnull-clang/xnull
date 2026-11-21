# `Logger`

| 项 | 值 |
| --- | --- |
| 类型 | `class Logger` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `Level`、`Field`、`Sink`、`Formatter`、`LogRecord` |

---

## 1. 定位

命名 logger：级别阈值、显式字段、Sink/Formatter、便捷方法。

不做：全局 logger、隐式上下文、异步队列。

---

## 2. 设计逻辑

- 字段 `_name`、`_minimum`、`_sink`、`_formatter`、`_fields`。
- `enabled` = levelRank >= minimum。
- `log` 构造 LogRecord（mono/wall 时间戳 + 字段快照），调 sink.write；失败只诊断。
- `withField/withFields/withSink/withFormatter` 返回新 Logger。
- 不持有 OS 资源；Sink 由外部拥有。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空 |
| `_minimum` | `Level` | 阈值 |
| `_sink` | `Sink` | 输出 |
| `_formatter` | `Formatter` | 格式 |
| `_fields` | `List<Field>` | 固定字段 |

不变量：name/sink/formatter 非 null；不可变。

---

## 4. 生命周期

不可变；无 close；Sink 生命周期由调用方管理。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Logger(String name, Level minimum, Sink sink)` | name/min/sink | name 非空；sink 非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 名称 | 无 | `String` | 无 |
| `level` | 阈值 | 无 | `Level` | 无 |
| `enabled` | 是否启用 | `Level` | `Bool` | 无 |
| `log` | 写日志 | `Level, String` | `void` | 无 |
| `logRecord` | 写记录 | `LogRecord` | `void` | 无 |
| `debug/info/warn/error` | 便捷 | `String` | `void` | 无 |
| `withField` | 派生 | `String, String` | `Logger` | 非法 → panic |
| `withFields` | 派生 | `List<Field>` | `Logger` | null → panic |
| `withSink` | 派生 | `Sink` | `Logger` | null → panic |
| `withFormatter` | 派生 | `Formatter` | `Logger` | null → panic |
| `flush` | 刷新 sink | 无 | `void` | 无 |
| `fields` | 字段快照 | 无 | `List<Field>` | 无 |

---

## 8. 使用的技术

- 级别阈值；
- 不可变派生；
- 记录构造；
- Sink/Formatter 组合。

---

## 9. 需要的支撑

- 语言：class、String、List、Bool、void；
- 运行时：`nowMono/nowWall`、`diagnose`；
- 接口：`Level`、`Field`、`Sink`、`Formatter`、`LogRecord`。

---

## 10. 依赖的特性/接口/类

`Level`、`Field`、`Sink`、`Formatter`、`LogRecord`、`runtime`。

---

## 11. 所有权与并发

不可变；可共享；Sink 线程安全由实现声明。

---

## 12. 示例与反例

正确：`logger.withField("request.id","abc").info("started")`。  
反例：全局 logger；日志失败抛业务异常；多任务共享非线程安全 sink。

---

## 13. 测试/场景义务

阈值；字段；格式化；sink 失败；派生独立性；flush；记录时间戳。

---

## 14. XNull 伪代码

```xnull
class Logger {
    final String _name
    final Level _minimum
    final Sink _sink
    final Formatter _formatter
    final List<Field> _fields

    Logger(String name, Level minimum, Sink sink) {
        if name == "" || sink == null { throw "Logger: invalid argument" }
        _name = name
        _minimum = minimum
        _sink = sink
        _formatter = new TextFormatter()
        _fields = []
    }

    String name() { return _name }
    Level level() { return _minimum }
    Bool enabled(Level level) { return levelRank(level) >= levelRank(_minimum) }
    List<Field> fields() { return _fields.copy() }

    void log(Level level, String message) {
        if !self.enabled(level) { return }
        LogRecord record = new LogRecord(level, _name, message, _fields,
            nowMono(), nowWall(), null)
        Result<Unit, Error> written = _sink.write(record)
        if written.isErr() {
            diagnose("[log] " + written.error().describe())
        }
    }

    void logRecord(LogRecord record) {
        if record == null { throw "Logger.logRecord: null" }
        if !self.enabled(record.level()) { return }
        Result<Unit, Error> written = _sink.write(record)
        if written.isErr() {
            diagnose("[log] " + written.error().describe())
        }
    }

    void debug(String message) { self.log(Level.Debug, message) }
    void info(String message) { self.log(Level.Info, message) }
    void warn(String message) { self.log(Level.Warn, message) }
    void error(String message) { self.log(Level.Error, message) }

    Logger withField(String key, String value) {
        Logger result = self.copyWith(_fields, _sink, _formatter)
        result._fields.push(new Field(key, value))
        return result
    }

    Logger withFields(List<Field> fields) {
        Logger result = self.copyWith(_fields, _sink, _formatter)
        result._fields = _fields.copy()
        result._fields.pushAll(fields)
        return result
    }

    Logger withSink(Sink sink) {
        if sink == null { throw "Logger.withSink: null" }
        return self.copyWith(_fields, sink, _formatter)
    }

    Logger withFormatter(Formatter formatter) {
        if formatter == null { throw "Logger.withFormatter: null" }
        return self.copyWith(_fields, _sink, formatter)
    }

    void flush() {
        Result<Unit, Error> result = _sink.flush()
        if result.isErr() { diagnose("[log] " + result.error().describe()) }
    }

    Logger copyWith(List<Field> fields, Sink sink, Formatter formatter) {
        Logger result = new Logger(_name, _minimum, sink)
        result._fields = fields.copy()
        result._formatter = formatter
        return result
    }
}
```
