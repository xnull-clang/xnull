# `RwLock<T>`

| 项 | 值 |
| --- | --- |
| 类型 | `class RwLock<T>` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`RuntimeMonitor` |

---

## 1. 定位

读写锁：多读者并发、单写者独占；等待可被 `Context` 取消；写者优先避免饥饿。

不做：可重入、升级/降级、公平队列、跨进程锁、优先级继承。

---

## 2. 设计逻辑

- 字段 `_value`、`_readers`、`_writer`、`_waitingWriters`、`_closed`、`_monitor`。
- `withRead`：无写者且无等待写者时进入；否则等待。
- `withWrite`：无读者且无写者时进入；否则等待；等待期间 `_waitingWriters` 加一。
- 写者优先：有等待写者时，新读者不插队，避免写者饥饿。
- 取消：等待中取消返回 `Cancelled`，不改变计数。
- `close`：拒绝新操作并唤醒等待者；已持有锁的调用继续到释放；close 幂等。
- 闭包体在持锁状态执行；不得保留 `T` 引用超过调用，不得在体内再次获取同一把锁（不可重入）。
- 不承诺公平；不跟踪读者身份。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_value` | `T` | 受保护值 |
| `_readers` | `Int` | 当前读者数 |
| `_writer` | `Bool` | 是否有写者 |
| `_waitingWriters` | `Int` | 等待写者数 |
| `_closed` | `Bool` | 是否关闭 |
| `_monitor` | `RuntimeMonitor` | 等待/通知 |

不变量：`_readers >= 0`；`_writer` 为 true 时 `_readers == 0`；`_waitingWriters >= 0`；
closed 后新操作返回 `Unavailable`。

---

## 4. 生命周期

构造后使用；`close` 停止新操作；无 OS 资源；不依赖 `deinit`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `RwLock(T value)` | value | 非 null（引用/值类型按 T） | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `withRead` | 读锁执行 | `Context context, void(T) body` | `Result<Unit, Error>` | `Cancelled`/`Unavailable`；null → panic |
| `withWrite` | 写锁执行 | `Context context, void(T) body` | `Result<Unit, Error>` | 同上 |
| `readerCount` | 读者数 | 无 | `Int` | 无 |
| `isWriteLocked` | 是否有写者 | 无 | `Bool` | 无 |
| `waitingWriters` | 等待写者数 | 无 | `Int` | 无 |
| `close` | 关闭 | 无 | `void` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |

说明：

- `withRead`/`withWrite` 的 `body` 在持锁状态调用；成功返回 `Ok(unit)`。
- `body` panic 时锁必须在作用域退出时释放；运行时/`defer` 负责。
- `close` 不等待在途操作；只停止新操作。
- `readerCount`/`isWriteLocked`/`waitingWriters` 是瞬时快照。

---

## 8. 使用的技术

- 读写计数；
- 写者优先；
- 运行时监视器；
- 取消感知等待；
- 作用域释放。

---

## 9. 需要的支撑

- 语言：class、泛型、泛型方法、Int、Bool、Result、闭包；
- 运行时：`RuntimeMonitor.enter/exit/wait(Context)/notifyAll`；
- 接口：`Context`、`Error`、`cancelledError`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`RuntimeMonitor`、`cancelledError`、`unavailableError`。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；`T` 借用给 body；不可重入；close 可并发；无资源。
相等：引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
RwLock<Cache> lock = new RwLock<Cache>(cache)
Int size = 0
Result<Unit, Error> read = lock.withRead(ctx, (Cache value) -> {
    size = value.size()
})
Result<Unit, Error> write = lock.withWrite(ctx, (Cache value) -> {
    value.put("k", 1)
})
```

反例：在 `withWrite` 内再次 `withWrite`；把 `value` 存到外部字段；忽略 `Cancelled`；
用读写锁保护纯值计算。

---

## 13. 测试/场景义务

多读者并发；写者独占；写者优先；取消读者/写者；close 唤醒；close 后操作；异常释放；
不可重入；计数快照；高竞争压力。

---

## 14. XNull 伪代码

```xnull
class RwLock<T> {
    final T _value
    Int _readers = 0
    Bool _writer = false
    Int _waitingWriters = 0
    Bool _closed = false
    final RuntimeMonitor _monitor

    RwLock(T value) {
        if value == null { throw "RwLock: null value" }
        _value = value
        _monitor = new RuntimeMonitor()
    }

    Result<Unit, Error> withRead(Context context, void(T) body) {
        if context == null || body == null {
            throw "RwLock.withRead: null argument"
        }
        _monitor.enter()
        while true {
            if _closed {
                _monitor.exit()
                return Err(unavailableError("rwlock read"))
            }
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("rwlock read"))
            }
            if !_writer && _waitingWriters == 0 {
                _readers = _readers + 1
                _monitor.exit()
                break
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("rwlock read"))
            }
        }
        defer { self.releaseRead() }
        body(_value)
        return Ok(unit)
    }

    Result<Unit, Error> withWrite(Context context, void(T) body) {
        if context == null || body == null {
            throw "RwLock.withWrite: null argument"
        }
        _monitor.enter()
        _waitingWriters = _waitingWriters + 1
        while true {
            if _closed {
                _waitingWriters = _waitingWriters - 1
                _monitor.exit()
                return Err(unavailableError("rwlock write"))
            }
            if context.isCancelled() {
                _waitingWriters = _waitingWriters - 1
                _monitor.exit()
                return Err(cancelledError("rwlock write"))
            }
            if !_writer && _readers == 0 {
                _writer = true
                _waitingWriters = _waitingWriters - 1
                _monitor.exit()
                break
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _waitingWriters = _waitingWriters - 1
                _monitor.exit()
                return Err(cancelledError("rwlock write"))
            }
        }
        defer { self.releaseWrite() }
        body(_value)
        return Ok(unit)
    }

    Int readerCount() {
        _monitor.enter()
        Int result = _readers
        _monitor.exit()
        return result
    }

    Bool isWriteLocked() {
        _monitor.enter()
        Bool result = _writer
        _monitor.exit()
        return result
    }

    Int waitingWriters() {
        _monitor.enter()
        Int result = _waitingWriters
        _monitor.exit()
        return result
    }

    void close() {
        _monitor.enter()
        if !_closed {
            _closed = true
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

    private void releaseRead() {
        _monitor.enter()
        _readers = _readers - 1
        _monitor.notifyAll()
        _monitor.exit()
    }

    private void releaseWrite() {
        _monitor.enter()
        _writer = false
        _monitor.notifyAll()
        _monitor.exit()
    }
}
```
