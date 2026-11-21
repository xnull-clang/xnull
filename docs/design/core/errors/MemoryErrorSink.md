# `MemoryErrorSink`

| 项 | 值 |
| --- | --- |
| 类型 | `class MemoryErrorSink implements ErrorSink` |
| 包 | `xdk.errors` |
| 稳定性 | `preview` |
| 依赖 | `BasicError`、`Error`、`ErrorKind` |

---

## 1. 定位

保留最近 N 条错误，用于测试断言/诊断面板；不做持久化。

---

## 2. 设计逻辑

- 有界 FIFO：超过容量删除最旧，`dropped` 计数。
- 只存 `BasicError(kind, describe)`；非 BasicError 结构化字段会丢失。
- 非线程安全；共享需外部同步。
- `close` 幂等；关闭后 `report` 返回 `Unavailable`。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_capacity` | `Int` | final | >0 |
| `_errors` | `List<BasicError>` | 可变 | 最多 capacity |
| `_dropped` | `Int` | 可变 | 丢弃数量 |
| `_open` | `Bool` | 可变 | 是否可用 |

不变量：errors.length ≤ capacity；新错误追加；超容量删最旧；dropped 只增。

---

## 4. 生命周期

- 构造后可用；`close` 后不可用；无资源。
- 非线程安全；跨任务共享需外部同步。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MemoryErrorSink(Int capacity)` | capacity | >0 | ≤0 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `report` | 记录错误 | `Error error` | `Result<Unit, Error>` | 关闭 → `Unavailable`；null → panic |
| `records` | 快照 | 无 | `List<BasicError>` | 无 |
| `dropped` | 丢弃数 | 无 | `Int` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `flush` | no-op | 无 | `Result<Unit, Error>` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | 无 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 有界 FIFO；
- 错误值快照；
- 关闭标志。

---

## 9. 需要的支撑

- 语言：class、List、Int、Bool、Result；
- 运行时：无；
- 接口：`BasicError`、`Error`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`BasicError`、`Error`、`ErrorKind`、`Result`、`List`。

---

## 11. 所有权与并发

- 持有 `BasicError` 引用；错误不可变，安全共享。
- `records()` 返回新列表；外部修改不影响 sink。
- 非线程安全；无 close 资源。

---

## 12. 示例与反例

正确：测试 `MemoryErrorSink(10)`；断言 `records()`/`dropped()`；`clear()` 重用。  
反例：多任务同时 report 不加锁；期望保留自定义错误字段；关闭后继续 report。

---

## 13. 测试/场景义务

容量/FIFO/dropped；clear；records 快照；关闭后 Unavailable；null；并发外部同步。

---

## 14. XNull 伪代码

```xnull
class MemoryErrorSink implements ErrorSink {
    Int _capacity
    List<BasicError> _errors = []
    Int _dropped = 0
    Bool _open = true

    MemoryErrorSink(Int capacity) {
        if capacity <= 0 {
            throw "MemoryErrorSink: capacity <= 0"
        }
        _capacity = capacity
    }

    Result<Unit, Error> report(Error error) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "sink closed"))
        }
        if error == null {
            throw "MemoryErrorSink.report: null"
        }
        BasicError basic = new BasicError(error.kind(), error.describe())
        if _errors.length() >= _capacity {
            _errors.remove(0)
            _dropped = _dropped + 1
        }
        _errors.push(basic)
        return Ok(unit)
    }

    List<BasicError> records() {
        List<BasicError> result = []
        Int index = 0
        while index < _errors.length() {
            result.push(_errors.get(index))
            index = index + 1
        }
        return result
    }

    Int dropped() { return _dropped }

    void clear() {
        _errors.clear()
    }

    Result<Unit, Error> flush() {
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        _open = false
        return Ok(unit)
    }

    Bool isOpen() {
        return _open
    }
}
```
