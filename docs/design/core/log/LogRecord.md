# `LogRecord`

| 项 | 值 |
| --- | --- |
| 类型 | `class LogRecord` |
| 包 | `xdk.log` |
| 稳定性 | `preview` |
| 依赖 | `Level`、`Field`、`Error` |

---

## 1. 定位

日志记录快照：级别、logger 名、消息、字段、时间戳、可选错误。

不做：格式化、输出、过滤、脱敏。

---

## 2. 设计逻辑

- 不可变；字段复制快照。
- `timestampMono` 用于排序/耗时；`timestampWall` 用于展示。
- `error` 可选；只保存引用，不格式化。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_level` | `Level` | 级别 |
| `_loggerName` | `String` | logger 名 |
| `_message` | `String` | 消息 |
| `_fields` | `List<Field>` | 字段快照 |
| `_timestampMono` | `Long` | 单调毫秒 |
| `_timestampWall` | `Long` | epoch 毫秒 |
| `_error` | `Error?` | 可选错误 |

不变量：level/loggerName/message 非空；时间戳 ≥0；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；由 `Logger.logRecord` 创建。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `level` | 级别 | 无 | `Level` | 无 |
| `loggerName` | 名称 | 无 | `String` | 无 |
| `message` | 消息 | 无 | `String` | 无 |
| `fields` | 字段快照 | 无 | `List<Field>` | 无 |
| `field` | 按 key 取 | `String key` | `Field?` | 无 |
| `timestampMono` | 单调时间 | 无 | `Long` | 无 |
| `timestampWall` | 墙钟 | 无 | `Long` | 无 |
| `error` | 错误 | 无 | `Error?` | 无 |
| `describe` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 字段列表；
- 双时间戳。

---

## 9. 需要的支撑

- 语言：class、String、Long、List；
- 运行时：`nowMono/nowWall`；
- 接口：`Level`、`Field`、`Error`。

---

## 10. 依赖的特性/接口/类

`Level`、`Field`、`Error`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`record.fields()` 快照；`record.field("request.id")`。  
反例：修改 fields 期望记录变化；把 error 当字符串；依赖 wall 时间单调。

---

## 13. 测试/场景义务

字段快照；field 查找；时间戳；error 可选；describe；不可变。

---

## 14. XNull 伪代码

```xnull
class LogRecord {
    final Level _level
    final String _loggerName
    final String _message
    final List<Field> _fields
    final Long _timestampMono
    final Long _timestampWall
    final Error? _error

    LogRecord(Level level, String loggerName, String message, List<Field> fields,
              Long timestampMono, Long timestampWall, Error? error) {
        _level = level
        _loggerName = loggerName
        _message = message
        _fields = []
        Int index = 0
        while index < fields.length() {
            _fields.push(fields.get(index))
            index = index + 1
        }
        _timestampMono = timestampMono
        _timestampWall = timestampWall
        _error = error
    }

    Level level() { return _level }
    String loggerName() { return _loggerName }
    String message() { return _message }
    List<Field> fields() { return _fields.copy() }
    Long timestampMono() { return _timestampMono }
    Long timestampWall() { return _timestampWall }
    Error? error() { return _error }

    Field? field(String key) {
        Int index = 0
        while index < _fields.length() {
            if _fields.get(index).key() == key {
                return _fields.get(index)
            }
            index = index + 1
        }
        return null
    }

    String describe() {
        return "[" + levelName(_level) + "] " + _loggerName + ": " + _message
    }
}
```
