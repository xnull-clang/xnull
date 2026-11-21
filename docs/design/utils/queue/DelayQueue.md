# `DelayQueue`

| 项 | 值 |
| --- | --- |
| 类型 | `class DelayQueue<T>` |
| 包 | `xdk.queue` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`QueueStats`、`RuntimeMonitor`、`Error` |

---

## 1. 定位

延迟队列：元素在指定单调延迟后可见；`take` 阻塞等待，可取消；支持 tryTake/nextReadyAt/统计。

不做：优先级、持久化、分布式、定时回调、自动重试。

---

## 2. 设计逻辑

- 字段：值列表、就绪时间列表、监视器、关闭标志、计数器。
- `put` 追加值和 `nowMono()+delay`；delay=0 立即可见。
- `take` 找到最早就绪元素；未到期时用 `waitDeadline` 等到该时刻；期间可被取消或新元素唤醒。
- `tryTake` 只取已到期元素。
- `close` 清空并把当前元素计入 dropped；唤醒等待者。
- 线程安全；无 close 资源；关闭后 `take` 返回 `Unavailable`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_values` | `List<T>` | 元素 |
| `_readyAt` | `List<Long>` | 单调就绪毫秒 |
| `_monitor` | `RuntimeMonitor` | 等待/通知 |
| `_closed` | `Bool` | 是否关闭 |
| `_pushed` | `Long` | 入队 |
| `_popped` | `Long` | 出队 |
| `_dropped` | `Long` | 关闭/清空丢弃 |

不变量：values.length = readyAt.length；readyAt 非负；closed 后两者为空。

---

## 4. 生命周期

构造后使用；`close` 清空并结束；close 幂等；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DelayQueue()` | 无 | 空 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `put` | 延迟入队 | `T value, Long delayMillis` | `Bool` | null value/负延迟 → panic |
| `take` | 等待取 | `Context context` | `Result<T, Error>` | `Cancelled`/`Unavailable` |
| `tryTake` | 非阻塞取 | 无 | `T?` | 无 |
| `nextReadyAt` | 最早就绪时刻 | 无 | `Long?` | 无 |
| `size` | 当前数量 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `close` | 关闭清空 | 无 | `void` | 无；幂等 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `stats` | 统计快照 | 无 | `QueueStats` | 无 |

说明：

- `put` 返回 false 表示已关闭。
- `take` 只消费已到期元素；等待中取消不消费。
- `nextReadyAt` 返回最早元素的绝对单调毫秒，可能已过期。
- `clear`/`close` 丢弃当前元素并计入 dropped。
- `stats` 的 rejected 恒为 0。

---

## 8. 使用的技术

- 单调截止；
- 监视器等待/通知；
- 线性扫描最早元素；
- 取消感知。

---

## 9. 需要的支撑

- 语言：class、泛型、List、Long、Int、Bool、Result；
- 运行时：`RuntimeMonitor.enter/exit/wait/waitDeadline/notifyAll`、`nowMono`；
- 接口：`Context`、`QueueStats`、`Error`、`cancelledError`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`QueueStats`、`RuntimeMonitor`、`nowMono`、错误辅助函数。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；等待可取消；无资源。

---

## 12. 示例与反例

正确：`put(task, 30000)`；30s 后 `take(ctx)` 返回。  
反例：负延迟；关闭后 take 期望旧值；取消后认为已消费；用墙钟计算延迟。

---

## 13. 测试/场景义务

delay 0/正；顺序与到期；take 等待/唤醒/取消；tryTake；nextReadyAt；clear/close；统计；关闭后操作；并发 put/take。

---

## 14. XNull 伪代码

```xnull
class DelayQueue<T> {
    final List<T> _values
    final List<Long> _readyAt
    final RuntimeMonitor _monitor
    Bool _closed = false
    Long _pushed = 0
    Long _popped = 0
    Long _dropped = 0

    DelayQueue() {
        _values = []
        _readyAt = []
        _monitor = new RuntimeMonitor()
    }

    Bool put(T value, Long delayMillis) {
        if value == null { throw "DelayQueue.put: null value" }
        if delayMillis < 0 { throw "DelayQueue.put: negative delay" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return false
        }
        _values.push(value)
        _readyAt.push(nowMono() + delayMillis)
        _pushed = _pushed + 1
        _monitor.notifyAll()
        _monitor.exit()
        return true
    }

    Result<T, Error> take(Context context) {
        if context == null { throw "DelayQueue.take: null context" }
        _monitor.enter()
        while true {
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("delay queue take"))
            }
            if _values.isEmpty() {
                if _closed {
                    _monitor.exit()
                    return Err(unavailableError("delay queue is closed"))
                }
                Bool woke = _monitor.wait(context)
                if !woke {
                    _monitor.exit()
                    return Err(cancelledError("delay queue take"))
                }
                continue
            }
            Int index = self.earliestIndex()
            Long ready = _readyAt.get(index)
            Long now = nowMono()
            if ready <= now {
                T value = _values.get(index)
                _values.remove(index)
                _readyAt.remove(index)
                _popped = _popped + 1
                _monitor.notifyAll()
                _monitor.exit()
                return Ok(value)
            }
            Int state = _monitor.waitDeadline(context, ready)
            if state == 1 {
                _monitor.exit()
                return Err(cancelledError("delay queue take"))
            }
        }
    }

    T? tryTake() {
        _monitor.enter()
        if _values.isEmpty() {
            _monitor.exit()
            return null
        }
        Int index = self.earliestIndex()
        Long now = nowMono()
        if _readyAt.get(index) > now {
            _monitor.exit()
            return null
        }
        T value = _values.get(index)
        _values.remove(index)
        _readyAt.remove(index)
        _popped = _popped + 1
        _monitor.notifyAll()
        _monitor.exit()
        return value
    }

    Long? nextReadyAt() {
        _monitor.enter()
        if _values.isEmpty() {
            _monitor.exit()
            return null
        }
        Long result = _readyAt.get(self.earliestIndex())
        _monitor.exit()
        return result
    }

    Int size() {
        _monitor.enter()
        Int result = _values.length()
        _monitor.exit()
        return result
    }

    Bool isEmpty() {
        _monitor.enter()
        Bool result = _values.isEmpty()
        _monitor.exit()
        return result
    }

    void clear() {
        _monitor.enter()
        _dropped = _dropped + (_values.length() as Long)
        _values.clear()
        _readyAt.clear()
        _monitor.notifyAll()
        _monitor.exit()
    }

    void close() {
        _monitor.enter()
        if !_closed {
            _closed = true
            _dropped = _dropped + (_values.length() as Long)
            _values.clear()
            _readyAt.clear()
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

    QueueStats stats() {
        _monitor.enter()
        QueueStats result = new QueueStats(_values.length(), _pushed, _popped,
            _dropped, 0, _closed)
        _monitor.exit()
        return result
    }

    private Int earliestIndex() {
        if _values.isEmpty() { return -1 }
        Int result = 0
        Int index = 1
        while index < _readyAt.length() {
            if _readyAt.get(index) < _readyAt.get(result) {
                result = index
            }
            index = index + 1
        }
        return result
    }
}
```
