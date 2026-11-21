# `MemorySink`

| 项 | 值 |
| --- | --- |
| 类型 | `class MemorySink implements Sink` |
| 包 | `xdk.log` |
| 稳定性 | `preview` |
| 依赖 | `LogRecord` |

---

## 1. 定位

有界内存 sink：保留最近 N 条记录；测试/诊断面板。

不做：持久化、远程、按字段索引。

---

## 2. 设计逻辑

- 字段 `_capacity`、`_records`、`_dropped`、`_open`。
- 容量满删除最旧；`dropped` 计数。
- records 返回快照；clear 清空。
- close 后 write 返回 `Unavailable`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_capacity` | `Int` | >0 |
| `_records` | `List<LogRecord>` | 记录 |
| `_dropped` | `Long` | 丢弃 |
| `_open` | `Bool` | 可用 |

不变量：records.length ≤ capacity。

---

## 4. 生命周期

构造后使用；close 幂等；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MemorySink(Int capacity)` | capacity | >0 | ≤0 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 记录 | `LogRecord` | `Result<Unit, Error>` | `Unavailable` |
| `records` | 快照 | 无 | `List<LogRecord>` | 无 |
| `dropped` | 丢弃数 | 无 | `Long` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `flush` | no-op | 无 | `Result<Unit, Error>` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | 无 |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 有界 FIFO；
- 快照；
- 关闭标志。

---

## 9. 需要的支撑

- 语言：class、List、Int、Long、Bool、Result；
- 运行时：无；
- 接口：`Sink`、`LogRecord`。

---

## 10. 依赖的特性/接口/类

`Sink`、`LogRecord`。

---

## 11. 所有权与并发

持有 record 引用（不可变）；非线程安全；records 快照。

---

## 12. 示例与反例

正确：测试断言 records；容量/丢弃。  
反例：多任务同时 write 不加锁；期望无限增长；修改 records 快照。

---

## 13. 测试/场景义务

容量/FIFO；dropped；clear；records 快照；关闭后；并发外部同步。

---

## 14. XNull 伪代码

```xnull
class MemorySink implements Sink {
    Int _capacity
    List<LogRecord> _records
    Long _dropped
    Bool _open

    MemorySink(Int capacity) {
        if capacity <= 0 { throw "MemorySink: capacity <= 0" }
        _capacity = capacity
        _records = []
        _dropped = 0
        _open = true
    }

    Result<Unit, Error> write(LogRecord record) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "sink closed"))
        }
        if record == null { throw "MemorySink.write: null" }
        if _records.length() >= _capacity {
            _records.remove(0)
            _dropped = _dropped + 1
        }
        _records.push(record)
        return Ok(unit)
    }

    List<LogRecord> records() { return _records.copy() }
    Long dropped() { return _dropped }
    void clear() { _records.clear() }
    Result<Unit, Error> flush() { return Ok(unit) }

    Result<Unit, Error> close() {
        _open = false
        return Ok(unit)
    }

    Bool isOpen() { return _open }
}
```
