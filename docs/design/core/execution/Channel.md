# `Channel`

| 项 | 值 |
| --- | --- |
| 类型 | `class Channel<T>` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`RuntimeMonitor` |

---

## 1. 定位

有界消息通道：阻塞发送/接收、关闭、容量/长度查询；等待可被 `Context` 取消。

不做：无界通道、容量 0 会合通道、`select`、公平调度、超时收发、队列持久化。

---

## 2. 设计逻辑

- 字段 `_capacity`、`_queue: List<T>`、`_closed`、`_monitor`。
- `capacity` 必须 ≥1； 不支持 0 会合通道（X）。
- `send` 在队列满时等待；`receive` 在队列空时等待。
- 等待中使用 `context.isCancelled` / `RuntimeMonitor.wait(context)`；取消返回 `Cancelled`，不消费值、不改变队列。
- `close` 幂等；关闭时清空队列并唤醒所有等待者；关闭后收发返回 `Unavailable`。
- 关闭丢弃队列是  决策；需要 drain 语义走 X。
- 多生产者/多消费者安全；公平性不承诺。
- T 可以是值类型或引用类型；值类型入队复制，引用类型复制句柄。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_capacity` | `Int` | >0 |
| `_queue` | `List<T>` | 当前排队值 |
| `_closed` | `Bool` | 是否关闭 |
| `_monitor` | `RuntimeMonitor` | 等待/通知 |

不变量：queue.length ≤ capacity；closed 后 queue 为空；close 后不再接受发送。

---

## 4. 生命周期

构造后使用；`close` 结束通道；close 幂等；无 `deinit` 依赖。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Channel(Int capacity)` | capacity | ≥1 | ≤0 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `send` | 发送 | `Context context, T value` | `Result<Unit, Error>` | `Cancelled`/`Unavailable`；null → panic |
| `receive` | 接收 | `Context context` | `Result<T, Error>` | `Cancelled`/`Unavailable`；null → panic |
| `close` | 关闭 | 无 | `void` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `length` | 当前排队数 | 无 | `Int` | 无 |
| `capacity` | 容量 | 无 | `Int` | 无 |

说明：

- `send` 成功入队后返回；容量满时等待。
- `send` 取消时不入队；关闭后不等待，直接 `Unavailable`。
- `receive` 成功出队后返回；队列空时等待。
- `receive` 取消时不消费；关闭且队列空时 `Unavailable`。
- `close` 清空队列；队列中的值不会交付。
- `length` 只反映当前排队数；不承诺与其他操作原子组合。
- 公平性不承诺；不保证 FIFO 跨生产者。

---

## 8. 使用的技术

- 有界 FIFO；
- 运行时监视器；
- 取消感知等待；
- 关闭广播。

---

## 9. 需要的支撑

- 语言：class、泛型、List、Int、Bool、Result；
- 运行时：`RuntimeMonitor` 的 `enter/exit/wait(Context)/notifyAll`；
- 接口：`Context`、`Error`、`cancelledError`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`RuntimeMonitor`、`cancelledError`、`unavailableError`。

---

## 11. 所有权与并发

引用语义；线程安全；队列元素按值/句柄复制；公平性不承诺；无资源句柄。

---

## 12. 示例与反例

正确：`Channel(8)`；生产者 `send(ctx, 1)`，消费者 `receive(ctx)`。  
反例：`Channel(0)`；关闭后继续 send；期望 close 保留队列；期望公平唤醒；取消后以为值已发送。

---

## 13. 测试/场景义务

容量满/空；阻塞与唤醒；取消发送/接收；关闭唤醒；关闭后收发；重复 close；length/capacity；多生产者/消费者；值类型/引用类型。

---

## 14. XNull 伪代码

```xnull
class Channel<T> {
    final Int _capacity
    List<T> _queue = []
    Bool _closed = false
    final RuntimeMonitor _monitor

    Channel(Int capacity) {
        if capacity <= 0 { throw "Channel: capacity <= 0" }
        _capacity = capacity
        _monitor = new RuntimeMonitor()
    }

    Result<Unit, Error> send(Context context, T value) {
        if context == null { throw "Channel.send: null context" }
        _monitor.enter()
        while true {
            if _closed {
                _monitor.exit()
                return Err(unavailableError("channel send"))
            }
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("channel send"))
            }
            if _queue.length() < _capacity {
                _queue.push(value)
                _monitor.notifyAll()
                _monitor.exit()
                return Ok(unit)
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("channel send"))
            }
        }
    }

    Result<T, Error> receive(Context context) {
        if context == null { throw "Channel.receive: null context" }
        _monitor.enter()
        while true {
            if _closed {
                _monitor.exit()
                return Err(unavailableError("channel receive"))
            }
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("channel receive"))
            }
            if _queue.length() > 0 {
                T value = _queue.remove(0)
                _monitor.notifyAll()
                _monitor.exit()
                return Ok(value)
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("channel receive"))
            }
        }
    }

    void close() {
        _monitor.enter()
        if !_closed {
            _closed = true
            _queue.clear()
            _monitor.notifyAll()
        }
        _monitor.exit()
    }

    Bool isClosed() {
        _monitor.enter()
        Bool result = _closed
        _monitor.exit()
        return result
    }

    Int length() {
        _monitor.enter()
        Int result = _queue.length()
        _monitor.exit()
        return result
    }

    Int capacity() { return _capacity }
}
```
