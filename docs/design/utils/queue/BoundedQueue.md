# `BoundedQueue`

| 项 | 值 |
| --- | --- |
| 类型 | `class BoundedQueue<T>` |
| 包 | `xdk.queue` |
| 稳定性 | `preview` |
| 依赖 | `DropPolicy`、`QueueStats`、`RuntimeMonitor` |

---

## 1. 定位

非阻塞有界队列：容量、满队列丢弃策略、统计、关闭。

不做：阻塞 put/take（用 `Channel`）、优先级、批处理、持久化。

---

## 2. 设计逻辑

- 字段：容量、策略、监视器、元素列表、关闭标志、计数器。
- `push` 非阻塞：未满入队；满时按策略 Error/DropNewest/DropOldest 处理。
- `pop`/`peek` 非阻塞；空返回 null。
- `clear`/`close` 丢弃当前元素并计入 dropped。
- 线程安全；无等待队列；无 close 资源。
- close 后 push 返回 false，pop 返回 null。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_capacity` | `Int` | ≥1 |
| `_policy` | `DropPolicy` | 满策略 |
| `_monitor` | `RuntimeMonitor` | 状态保护 |
| `_items` | `List<T>` | 当前元素 |
| `_closed` | `Bool` | 是否关闭 |
| `_pushed` | `Long` | 成功入队 |
| `_popped` | `Long` | 成功出队 |
| `_dropped` | `Long` | 丢弃 |
| `_rejected` | `Long` | 拒绝 |

不变量：0 ≤ items.length ≤ capacity；closed 后 items 为空；计数器非负。

---

## 4. 生命周期

构造后使用；`close` 清空并结束；close 幂等；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BoundedQueue(Int capacity, DropPolicy policy)` | capacity/policy | capacity≥1；policy 非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `push` | 非阻塞入队 | `T value` | `Bool` | null value → panic |
| `pop` | 出队 | 无 | `T?` | 无 |
| `peek` | 看队首 | 无 | `T?` | 无 |
| `size` | 当前大小 | 无 | `Int` | 无 |
| `capacity` | 容量 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `isFull` | 是否已满 | 无 | `Bool` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `close` | 关闭清空 | 无 | `void` | 无；幂等 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `stats` | 统计快照 | 无 | `QueueStats` | 无 |

说明：

- `push` 返回 true 表示新值已入队；DropNewest/Error 返回 false。
- DropOldest 删除最旧后入队并返回 true。
- `clear`/`close` 把当前元素数计入 dropped。
- `isFull` 在 closed 后为 false（已清空）。

---

## 8. 使用的技术

- 有界列表；
- 丢弃策略；
- 监视器同步；
- 计数。

---

## 9. 需要的支撑

- 语言：class、泛型、List、Int、Long、Bool；
- 运行时：`RuntimeMonitor.enter/exit`；
- 接口：`DropPolicy`、`QueueStats`。

---

## 10. 依赖的特性/接口/类

`DropPolicy`、`QueueStats`、`RuntimeMonitor`。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；无资源。

---

## 12. 示例与反例

正确：容量 2、DropOldest，push 1/2/3 → [2,3]。  
反例：期望 push 阻塞；把 DropNewest 返回 true；close 后继续 push；并发 pop 期望顺序保证。

---

## 13. 测试/场景义务

容量 1/N；三种策略；满/空；pop/peek；clear/close；统计；关闭后操作；并发 push/pop。

---

## 14. XNull 伪代码

```xnull
class BoundedQueue<T> {
    final Int _capacity
    final DropPolicy _policy
    final RuntimeMonitor _monitor
    final List<T> _items
    Bool _closed = false
    Long _pushed = 0
    Long _popped = 0
    Long _dropped = 0
    Long _rejected = 0

    BoundedQueue(Int capacity, DropPolicy policy) {
        if capacity < 1 { throw "BoundedQueue: capacity < 1" }
        if policy == null { throw "BoundedQueue: null policy" }
        _capacity = capacity
        _policy = policy
        _monitor = new RuntimeMonitor()
        _items = []
    }

    Bool push(T value) {
        if value == null { throw "BoundedQueue.push: null value" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return false
        }
        if _items.length() < _capacity {
            _items.push(value)
            _pushed = _pushed + 1
            _monitor.exit()
            return true
        }
        if _policy == DropPolicy.Error {
            _rejected = _rejected + 1
            _monitor.exit()
            return false
        }
        if _policy == DropPolicy.DropNewest {
            _dropped = _dropped + 1
            _monitor.exit()
            return false
        }
        _items.remove(0)
        _dropped = _dropped + 1
        _items.push(value)
        _pushed = _pushed + 1
        _monitor.exit()
        return true
    }

    T? pop() {
        _monitor.enter()
        if _items.isEmpty() {
            _monitor.exit()
            return null
        }
        T value = _items.remove(0)
        _popped = _popped + 1
        _monitor.exit()
        return value
    }

    T? peek() {
        _monitor.enter()
        if _items.isEmpty() {
            _monitor.exit()
            return null
        }
        T value = _items.get(0)
        _monitor.exit()
        return value
    }

    Int size() {
        _monitor.enter()
        Int result = _items.length()
        _monitor.exit()
        return result
    }

    Int capacity() { return _capacity }

    Bool isEmpty() {
        _monitor.enter()
        Bool result = _items.isEmpty()
        _monitor.exit()
        return result
    }

    Bool isFull() {
        _monitor.enter()
        Bool result = !_closed && _items.length() >= _capacity
        _monitor.exit()
        return result
    }

    void clear() {
        _monitor.enter()
        _dropped = _dropped + (_items.length() as Long)
        _items.clear()
        _monitor.exit()
    }

    void close() {
        _monitor.enter()
        if !_closed {
            _closed = true
            _dropped = _dropped + (_items.length() as Long)
            _items.clear()
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
        QueueStats result = new QueueStats(_items.length(), _pushed, _popped,
            _dropped, _rejected, _closed)
        _monitor.exit()
        return result
    }
}
```
