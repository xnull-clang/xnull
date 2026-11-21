# `Semaphore`

| 项 | 值 |
| --- | --- |
| 类型 | `class Semaphore` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`RuntimeMonitor` |

---

## 1. 定位

计数信号量：限制同时进入某段工作的任务数；等待可被 `Context` 取消。

不做：所有权跟踪、公平性保证、跨进程信号量、优先级继承。

---

## 2. 设计逻辑

- 字段 `_permits`（初始许可）、`_available`（当前可用）、`_closed`、`_monitor`。
- `acquire` 在 available 为 0 时等待；取消返回 `Cancelled`，不改变计数。
- `release` 归还一个许可；超过初始许可视为调用方错误，返回 false。
- `close` 唤醒全部等待者并拒绝新 acquire；已持有许可的调用方仍可 release（但 closed 后 release 返回 false）。
- 等待使用 `RuntimeMonitor.wait(context)`；虚假唤醒时循环重试。
- 不承诺 FIFO/公平；不跟踪哪个任务持有许可。
- 可跨任务共享；`acquire/release` 线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_permits` | `Int` | ≥0；初始许可 |
| `_available` | `Int` | 0..permits |
| `_closed` | `Bool` | 是否关闭 |
| `_monitor` | `RuntimeMonitor` | 等待/通知 |

不变量：`0 <= _available <= _permits`；closed 后 acquire 立即失败；close 幂等。

---

## 4. 生命周期

构造后使用；`close` 结束；close 幂等；无 OS 资源；不依赖 `deinit`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Semaphore(Int permits)` | permits | ≥0 | 负值 → panic |

`permits == 0` 合法：所有 acquire 都等待，直到外部 release；用于测试/一次性闸门。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `acquire` | 获取许可 | `Context context` | `Result<Unit, Error>` | `Cancelled`/`Unavailable`；null → panic |
| `tryAcquire` | 非阻塞获取 | 无 | `Bool` | 无 |
| `release` | 归还许可 | 无 | `Bool` | 无 |
| `available` | 当前可用 | 无 | `Int` | 无 |
| `permits` | 初始许可 | 无 | `Int` | 无 |
| `close` | 关闭 | 无 | `void` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |

说明：

- `acquire` 成功使 available 减 1。
- `release` 成功使 available 加 1；closed 或 available == permits 返回 false。
- `close` 清空等待者；不重置计数。
- `tryAcquire` closed 时返回 false。

---

## 8. 使用的技术

- 计数信号量；
- 运行时监视器；
- 取消感知等待；
- 关闭广播。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、Result、Unit；
- 运行时：`RuntimeMonitor.enter/exit/wait(Context)/notifyAll`；
- 接口：`Context`、`Error`、`cancelledError`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`RuntimeMonitor`、`cancelledError`、`unavailableError`。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；许可无所有者；close 可并发；无资源。
相等：引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：`Semaphore gate = new Semaphore(64)`；工作前 `acquire(ctx)`，完成后 `defer gate.release()`。  
反例：release 多于 acquire；close 后继续 acquire；把信号量当互斥锁；期望公平唤醒。

---

## 13. 测试/场景义务

0/1/N 许可；阻塞/唤醒；取消；tryAcquire；超量 release；close 唤醒；关闭后 acquire；
多任务竞争；available/permits；重复 close。

---

## 14. XNull 伪代码

```xnull
class Semaphore {
    final Int _permits
    Int _available
    Bool _closed = false
    final RuntimeMonitor _monitor

    Semaphore(Int permits) {
        if permits < 0 { throw "Semaphore: negative permits" }
        _permits = permits
        _available = permits
        _monitor = new RuntimeMonitor()
    }

    Result<Unit, Error> acquire(Context context) {
        if context == null { throw "Semaphore.acquire: null context" }
        _monitor.enter()
        while true {
            if _closed {
                _monitor.exit()
                return Err(unavailableError("semaphore acquire"))
            }
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("semaphore acquire"))
            }
            if _available > 0 {
                _available = _available - 1
                _monitor.exit()
                return Ok(unit)
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("semaphore acquire"))
            }
        }
    }

    Bool tryAcquire() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return false
        }
        if _available <= 0 {
            _monitor.exit()
            return false
        }
        _available = _available - 1
        _monitor.exit()
        return true
    }

    Bool release() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return false
        }
        if _available >= _permits {
            _monitor.exit()
            return false
        }
        _available = _available + 1
        _monitor.notifyAll()
        _monitor.exit()
        return true
    }

    Int available() {
        _monitor.enter()
        Int result = _available
        _monitor.exit()
        return result
    }

    Int permits() { return _permits }

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
}
```
