# `LoggerFactory`

| 项 | 值 |
| --- | --- |
| 类型 | `class LoggerFactory` |
| 包 | `xdk.log` |
| 稳定性 | `preview` |
| 依赖 | `Logger`、`Level`、`Sink` |

---

## 1. 定位

显式 logger 工厂/注册表：按名称复用 Logger，统一默认级别/Sink。

不做：全局单例、远程配置、热更新。

---

## 2. 设计逻辑

- 字段 `_loggers: Map<String,Logger>`、`_defaultLevel`、`_defaultSink`。
- `getLogger(name)` 缓存；新 logger 用默认配置。
- `configure(level,sink)` 更新默认；已建 logger 不自动改。
- `shutdown` flush/close 所有 sink（仅默认 sink？设计：关闭默认 sink；各 logger 共享默认 sink，不重复关）。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_loggers` | `Map<String,Logger>` | 注册表 |
| `_defaultLevel` | `Level` | 默认阈值 |
| `_defaultSink` | `Sink` | 默认 sink |

不变量：名称唯一；sink 非 null。

---

## 4. 生命周期

构造后使用；shutdown 后不再 getLogger；无全局。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `LoggerFactory(Sink sink)` | sink | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `getLogger` | 获取/创建 | `String name` | `Logger` | 空名 → panic |
| `root` | 根 logger | 无 | `Logger` | 无 |
| `configure` | 默认配置 | `Level, Sink` | `void` | null → panic |
| `setDefaultLevel` | 默认级别 | `Level` | `void` | 无 |
| `setDefaultSink` | 默认 sink | `Sink` | `void` | null → panic |
| `loggers` | 名称快照 | 无 | `List<String>` | 无 |
| `shutdown` | 刷新/关闭 | 无 | `void` | 无 |

---

## 8. 使用的技术

- 名称注册表；
- 默认配置；
- 显式生命周期。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、void；
- 运行时：无；
- 接口：`Logger`、`Level`、`Sink`。

---

## 10. 依赖的特性/接口/类

`Logger`、`Level`、`Sink`。

---

## 11. 所有权与并发

可变；非线程安全；持有 logger/sink 引用。

---

## 12. 示例与反例

正确：Factory 持有默认 sink；getLogger 复用。  
反例：全局 factory；configure 期望旧 logger 自动变；shutdown 后继续用。

---

## 13. 测试/场景义务

getLogger 缓存；默认配置；configure；root；loggers；shutdown；空名。

---

## 14. XNull 伪代码

```xnull
class LoggerFactory {
    Map<String, Logger> _loggers
    Level _defaultLevel
    Sink _defaultSink
    Bool _shutdown

    LoggerFactory(Sink sink) {
        if sink == null { throw "LoggerFactory: null sink" }
        _loggers = [:]
        _defaultLevel = Level.Info
        _defaultSink = sink
        _shutdown = false
    }

    Logger getLogger(String name) {
        if name == "" { throw "LoggerFactory.getLogger: empty name" }
        if _shutdown { throw "LoggerFactory: shutdown" }
        if _loggers.has(name) {
            return _loggers.getOr(name, null)
        }
        Logger created = new Logger(name, _defaultLevel, _defaultSink)
        _loggers.put(name, created)
        return created
    }

    Logger root() { return self.getLogger("root") }

    void configure(Level level, Sink sink) {
        if sink == null { throw "LoggerFactory.configure: null sink" }
        _defaultLevel = level
        _defaultSink = sink
    }

    void setDefaultLevel(Level level) { _defaultLevel = level }

    void setDefaultSink(Sink sink) {
        if sink == null { throw "LoggerFactory.setDefaultSink: null" }
        _defaultSink = sink
    }

    List<String> loggers() { return _loggers.keys() }

    void shutdown() {
        if _shutdown { return }
        _shutdown = true
        Int index = 0
        List<String> names = _loggers.keys()
        while index < names.length() {
            _loggers.getOr(names.get(index), null).flush()
            index = index + 1
        }
        Result<Unit, Error> closed = _defaultSink.close()
        if closed.isErr() { diagnose("[log] " + closed.error().describe()) }
    }
}
```
