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

- 字段 `_name`、`_minimum`、`_sink`、`_formatter`、`_fields`、`_filter`、`_redactor`、`_sampler`。
- `enabled` = levelRank >= minimum。
- `log` 管道固定：级别阈值 → `_filter.allow` → `_sampler.keep` → `_redactor`（message 与字段值）→ `_sink.write`；失败只诊断。
- `withField/withFields/withSink/withFormatter/withFilter/withRedactor/withSampler` 返回新 Logger。
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
| `_filter` | `Filter` | 过滤；默认 `KeepAllFilter` |
| `_redactor` | `Redactor` | 脱敏；默认 `IdentityRedactor` |
| `_sampler` | `Sampler` | 采样；默认 `KeepAllSampler` |

不变量：name/sink/formatter/filter/redactor/sampler 非 null；不可变。

---

## 4. 生命周期

不可变；无 close；Sink 生命周期由调用方管理。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Logger(String name, Level minimum, Sink sink)` | name/min/sink | name 非空；sink 非 null | 非法 → panic |

构造时默认 `KeepAllFilter`/`IdentityRedactor`/`KeepAllSampler`；默认配置与 1.x 行为一致。`withFilter/withRedactor/withSampler` 只替换对应环节，保留其余配置。

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
| `withFilter` | 派生过滤器 | `Filter` | `Logger` | null → panic |
| `withRedactor` | 派生脱敏器 | `Redactor` | `Logger` | null → panic |
| `withSampler` | 派生采样器 | `Sampler` | `Logger` | null → panic |
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
- 接口：`Level`、`Field`、`Sink`、`Formatter`、`LogRecord`、`Filter`、`Redactor`、`Sampler`。

---

## 10. 依赖的特性/接口/类

`Level`、`Field`、`Sink`、`Formatter`、`LogRecord`、`Filter`、`Redactor`、`Sampler`、`runtime`。

---

## 11. 所有权与并发

不可变；可共享；Sink 线程安全由实现声明。

---

## 12. 示例与反例

正确：`logger.withField("request.id","abc").info("started")`。

正确：`logger.withFilter(new PredicateFilter(...)).withSampler(new EveryNSampler(10)).withRedactor(new ReplaceRedactor("secret","***"))`。

反例：全局 logger；日志失败抛业务异常；多任务共享非线程安全 sink；在 filter 里写 sink；期望 redactor 只改 message 不改字段值。

---

## 13. 测试/场景义务

阈值；字段；格式化；sink 失败；派生独立性；flush；记录时间戳；filter 拒绝不进入 sampler/redactor/sink；sampler 只统计通过前置条件的记录；redactor 同时改 message 与字段值；四个 with* 的默认值/替换/保留其余配置。

---

## 14. XNull 伪代码

```xnull
class Logger {
    final String _name
    final Level _minimum
    final Sink _sink
    final Formatter _formatter
    final List<Field> _fields
    final Filter _filter
    final Redactor _redactor
    final Sampler _sampler

    Logger(String name, Level minimum, Sink sink) {
        if name == "" || sink == null { throw "Logger: invalid argument" }
        _name = name
        _minimum = minimum
        _sink = sink
        _formatter = new TextFormatter()
        _fields = []
        _filter = new KeepAllFilter()
        _redactor = new IdentityRedactor()
        _sampler = new KeepAllSampler()
    }

    String name() { return _name }
    Level level() { return _minimum }
    Bool enabled(Level level) { return levelRank(level) >= levelRank(_minimum) }
    List<Field> fields() { return _fields.copy() }

    void log(Level level, String message) {
        if !self.enabled(level) { return }
        LogRecord record = new LogRecord(level, _name, message, _fields,
            nowMono(), nowWall(), null)
        self.emit(record)
    }

    void logRecord(LogRecord record) {
        if record == null { throw "Logger.logRecord: null" }
        if !self.enabled(record.level()) { return }
        self.emit(record)
    }

    void emit(LogRecord record) {
        if !_filter.allow(record) { return }
        if !_sampler.keep(record) { return }
        List<Field> redactedFields = []
        List<Field> fields = record.fields()
        Int index = 0
        while index < fields.length() {
            Field field = fields.get(index)
            redactedFields.push(new Field(field.key(), _redactor.redact(field.value())))
            index = index + 1
        }
        LogRecord output = new LogRecord(record.level(), record.loggerName(),
            _redactor.redact(record.message()), redactedFields,
            record.timestampMono(), record.timestampWall(), record.error())
        Result<Unit, Error> written = _sink.write(output)
        if written.isErr() {
            diagnose("[log] " + written.error().describe())
        }
    }

    void debug(String message) { self.log(Level.Debug, message) }
    void info(String message) { self.log(Level.Info, message) }
    void warn(String message) { self.log(Level.Warn, message) }
    void error(String message) { self.log(Level.Error, message) }

    Logger withField(String key, String value) {
        Logger result = self.copyWith(_fields, _sink, _formatter, _filter, _redactor, _sampler)
        result._fields.push(new Field(key, value))
        return result
    }

    Logger withFields(List<Field> fields) {
        Logger result = self.copyWith(_fields, _sink, _formatter, _filter, _redactor, _sampler)
        result._fields = _fields.copy()
        result._fields.pushAll(fields)
        return result
    }

    Logger withSink(Sink sink) {
        if sink == null { throw "Logger.withSink: null" }
        return self.copyWith(_fields, sink, _formatter, _filter, _redactor, _sampler)
    }

    Logger withFormatter(Formatter formatter) {
        if formatter == null { throw "Logger.withFormatter: null" }
        return self.copyWith(_fields, _sink, formatter, _filter, _redactor, _sampler)
    }

    Logger withFilter(Filter filter) {
        if filter == null { throw "Logger.withFilter: null" }
        return self.copyWith(_fields, _sink, _formatter, filter, _redactor, _sampler)
    }

    Logger withRedactor(Redactor redactor) {
        if redactor == null { throw "Logger.withRedactor: null" }
        return self.copyWith(_fields, _sink, _formatter, _filter, redactor, _sampler)
    }

    Logger withSampler(Sampler sampler) {
        if sampler == null { throw "Logger.withSampler: null" }
        return self.copyWith(_fields, _sink, _formatter, _filter, _redactor, sampler)
    }

    void flush() {
        Result<Unit, Error> result = _sink.flush()
        if result.isErr() { diagnose("[log] " + result.error().describe()) }
    }

    Logger copyWith(List<Field> fields, Sink sink, Formatter formatter,
                    Filter filter, Redactor redactor, Sampler sampler) {
        Logger result = new Logger(_name, _minimum, sink)
        result._fields = fields.copy()
        result._formatter = formatter
        result._filter = filter
        result._redactor = redactor
        result._sampler = sampler
        return result
    }
}
```
