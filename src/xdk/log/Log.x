// Tier: T0；依赖：xdk.runtime、xdk.text；稳定性：preview。
// xdk.log —— 结构化日志（W5 首个可运行面）
//
// 面：Level 阈值、Logger 名称、debug/info/warn/error 便捷方法、stdout sink。
// 字段（fields）与可插拔 sink 为后续切片；本切片只承诺可执行的最小契约。
package xdk.log
import xdk.runtime

enum Level {
    Debug,
    Info,
    Warn,
    Error
}

static Int levelRank(Level level) {
    if level == Level.Debug {
        return 0
    }
    if level == Level.Info {
        return 1
    }
    if level == Level.Warn {
        return 2
    }
    return 3
}

static String levelName(Level level) {
    if level == Level.Debug {
        return "DEBUG"
    }
    if level == Level.Info {
        return "INFO"
    }
    if level == Level.Warn {
        return "WARN"
    }
    return "ERROR"
}

@Value
class Field {
    final String key
    final String value

    Field(String key, String value) {
        self.key = key
        self.value = value
    }
}

// 时钟注入：默认 SystemClock；测试可用固定实现获得确定性时间戳。
protocol Clock {
    Long wallMs();
    Long monoMs();
}

class SystemClock implements Clock {
    SystemClock() {
    }

    @Override
    Long wallMs() {
        return nowWall()
    }

    @Override
    Long monoMs() {
        return nowMono()
    }
}

class LogRecord {
    final Level level
    final String loggerName
    final String message
    final List<Field> fields
    Long timestampMs
    Long monotonicMs

    LogRecord(Level level, String loggerName, String message, List<Field> fields) {
        self.level = level
        self.loggerName = loggerName
        self.message = message
        self.fields = fields
        self.timestampMs = 0
        self.monotonicMs = 0
    }

    Long timestamp() {
        return self.timestampMs
    }

    Long monotonic() {
        return self.monotonicMs
    }
}

protocol Sink {
    Void write(LogRecord record);
}

String recordText(LogRecord record) {
    String text = "[" + levelName(record.level) + "] " + record.loggerName + ": " + record.message
    Int index = 0
    while index < record.fields.length() {
        Field field = record.fields.get(index)
        text = text + " " + field.key + "=" + field.value
        index = index + 1
    }
    return text
}

// 带墙钟毫秒前缀的显式格式；recordText 保持旧格式，避免改变既有输出。
String recordTextWithTime(LogRecord record) {
    return str(record.timestampMs) + " " + recordText(record)
}

class ConsoleSink implements Sink {
    ConsoleSink() {
    }

    @Override
    Void write(LogRecord record) {
        print(recordText(record))
    }
}

class MemorySink implements Sink {
    List<String> entries
    List<LogRecord> records

    MemorySink() {
        self.entries = []
        self.records = []
    }

    @Override
    Void write(LogRecord record) {
        self.entries.push(recordText(record))
        self.records.push(record)
    }

    List<String> lines() {
        return self.entries
    }

    List<LogRecord> captured() {
        return self.records
    }

    Void clear() {
        self.entries = []
        self.records = []
    }
}

// ---------- 过滤 / 脱敏 / 采样（B8） ----------
//
// 三者都是协议钩子，Logger 只依赖协议；默认实现保持既有行为不变。
// 顺序：级别 -> filter -> sampler -> redactor -> sink。采样只统计已通过
// 级别与 filter 的记录，因此同一输入序列始终得到同一保留集合。

protocol Filter {
    Bool allow(LogRecord record);
}

class PredicateFilter implements Filter {
    Bool(LogRecord) predicate

    PredicateFilter(Bool(LogRecord) predicate0) {
        self.predicate = predicate0
    }

    @Override
    Bool allow(LogRecord record) {
        return self.predicate(record)
    }
}

class KeepAllFilter implements Filter {
    KeepAllFilter() {
    }

    @Override
    Bool allow(LogRecord record) {
        return true
    }
}

protocol Redactor {
    String redact(String value);
}

class ReplaceRedactor implements Redactor {
    String needle
    String replacement

    ReplaceRedactor(String needle0, String replacement0) {
        self.needle = needle0
        self.replacement = replacement0
    }

    @Override
    String redact(String value) {
        if self.needle.length() == 0 {
            return value
        }
        return value.replace(self.needle, self.replacement)
    }
}

class IdentityRedactor implements Redactor {
    IdentityRedactor() {
    }

    @Override
    String redact(String value) {
        return value
    }
}

protocol LogSampler {
    Bool keep(LogRecord record);
}

// 固定间隔采样：每第 N 条通过前置条件的记录保留一条。计数器随 sampler
// 实例走，同一 Logger 的 with* 派生共享该实例，便于确定性测试。
class EveryNSampler implements LogSampler {
    Int interval
    Int seen

    EveryNSampler(Int interval0) {
        if interval0 < 1 {
            throw "EveryNSampler: interval must be positive"
        }
        self.interval = interval0
        self.seen = 0
    }

    @Override
    Bool keep(LogRecord record) {
        self.seen = self.seen + 1
        return self.seen % self.interval == 0
    }

    Int count() {
        return self.seen
    }
}

class KeepAllSampler implements LogSampler {
    KeepAllSampler() {
    }

    @Override
    Bool keep(LogRecord record) {
        return true
    }
}

class Logger {
    String name
    Level min
    Sink sink
    List<Field> fields
    Clock clock
    Filter filter
    Redactor redactor
    LogSampler sampler

    Logger(String name, Level min) {
        self.name = name
        self.min = min
        self.sink = new ConsoleSink()
        self.fields = []
        self.clock = new SystemClock()
        self.filter = new KeepAllFilter()
        self.redactor = new IdentityRedactor()
        self.sampler = new KeepAllSampler()
    }

    Logger withSink(Sink sink) {
        Logger next = new Logger(self.name, self.min)
        next.sink = sink
        next.fields = self.fields
        next.clock = self.clock
        next.filter = self.filter
        next.redactor = self.redactor
        next.sampler = self.sampler
        return next
    }

    Logger withClock(Clock clock) {
        Logger next = self.withSink(self.sink)
        next.clock = clock
        return next
    }

    Logger withFilter(Filter filter) {
        Logger next = self.withSink(self.sink)
        next.filter = filter
        return next
    }

    Logger withRedactor(Redactor redactor) {
        Logger next = self.withSink(self.sink)
        next.redactor = redactor
        return next
    }

    Logger withSampler(LogSampler sampler) {
        Logger next = self.withSink(self.sink)
        next.sampler = sampler
        return next
    }

    Logger withField(String key, String value) {
        Logger next = self.withSink(self.sink)
        List<Field> copy = []
        Int index = 0
        while index < self.fields.length() {
            copy.push(self.fields.get(index))
            index = index + 1
        }
        copy.push(new Field(key, value))
        next.fields = copy
        return next
    }

    Bool enabled(Level level) {
        return levelRank(level) >= levelRank(self.min)
    }

    LogRecord redacted(LogRecord record) {
        List<Field> fields = []
        Int index = 0
        while index < record.fields.length() {
            Field field = record.fields.get(index)
            fields.push(new Field(field.key, self.redactor.redact(field.value)))
            index = index + 1
        }
        LogRecord out = new LogRecord(record.level, record.loggerName,
            self.redactor.redact(record.message), fields)
        out.timestampMs = record.timestampMs
        out.monotonicMs = record.monotonicMs
        return out
    }

    Void log(Level level, String message) {
        if self.enabled(level) {
            LogRecord record = new LogRecord(level, self.name, message, self.fields)
            record.timestampMs = self.clock.wallMs()
            record.monotonicMs = self.clock.monoMs()
            if !self.filter.allow(record) {
                return
            }
            if !self.sampler.keep(record) {
                return
            }
            self.sink.write(self.redacted(record))
        }
    }

    Void debug(String message) {
        self.log(Level.Debug, message)
    }

    Void info(String message) {
        self.log(Level.Info, message)
    }

    Void warn(String message) {
        self.log(Level.Warn, message)
    }

    Void error(String message) {
        self.log(Level.Error, message)
    }
}
