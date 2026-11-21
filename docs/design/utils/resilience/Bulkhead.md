# `Bulkhead`

| 项 | 值 |
| --- | --- |
| 类型 | `class Bulkhead` |
| 包 | `xdk.resilience` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`RuntimeMonitor`、`Error` |

---

## 1. 定位

并发隔离舱：限制同时执行的操作数，超出时等待或快速失败；支持关闭与排空等待。

不做：分布式并发限制、优先级、公平队列、按租户配额、自动扩容。

---

## 2. 设计逻辑

- 字段：最大并发、当前在途、关闭标志、监视器。
- `acquire` 在未满时增加在途并返回；满时等待；取消返回 `Cancelled`。
- `release` 减少在途并唤醒等待者；即使已关闭也允许释放，保证排空。
- `close` 拒绝新请求并唤醒等待者；不等待在途结束。
- `awaitIdle` 等待在途归零；`closeAndAwait` 组合关闭与排空。
- `execute` 获取许可后执行 operation，`defer` 保证释放。
- 线程安全；无全局状态。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxConcurrent` | `Int` | ≥1 |
| `_monitor` | `RuntimeMonitor` | 保护计数 |
| `_inFlight` | `Int` | 0..max |
| `_closed` | `Bool` | 是否拒绝新请求 |

不变量：`0 <= _inFlight <= _maxConcurrent`；closed 后 acquire 失败；release 不会低于 0；close 幂等。

---

## 4. 生命周期

构造后长期使用；`close` 结束接收；在途操作自行结束；无 close 资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Bulkhead(Int maxConcurrent)` | maxConcurrent | ≥1 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `execute<T>` | 隔离执行 | `Context, Result<T,Error>() operation` | `Result<T, Error>` | `Unavailable`/`Cancelled`/操作错误 |
| `acquire` | 获取许可 | `Context` | `Result<Unit, Error>` | `Unavailable`/`Cancelled` |
| `tryAcquire` | 非阻塞获取 | 无 | `Bool` | 无 |
| `release` | 归还许可 | 无 | `Bool` | 无 |
| `inFlight` | 当前在途 | 无 | `Int` | 无 |
| `maxConcurrent` | 最大并发 | 无 | `Int` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `close` | 停止接收 | 无 | `void` | 无；幂等 |
| `awaitIdle` | 等待排空 | `Context` | `Result<Unit, Error>` | `Cancelled` |
| `closeAndAwait` | 关闭并排空 | `Context` | `Result<Unit, Error>` | `Cancelled` |

说明：

- `release` 在没有在途时返回 false；closed 后仍可释放。
- `awaitIdle` 不自动关闭；若仍有新请求进入，可能永远不空闲。
- `execute` 在 operation 抛异常时也通过 `defer` 释放许可。
- `tryAcquire` closed 或已满返回 false。

---

## 8. 使用的技术

- 计数信号量语义；
- 运行时监视器；
- 取消感知等待；
- 关闭广播；
- 闭包式执行。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、Result、Unit、泛型方法；
- 运行时：`RuntimeMonitor.enter/exit/wait/notifyAll`；
- 接口：`Context`、`Error`、`cancelledError`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`RuntimeMonitor`、`Error`、错误辅助函数。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；许可无所有者；close 与 release 并发安全；无资源。

---

## 12. 示例与反例

正确：`Bulkhead bulk = new Bulkhead(16)`；`bulk.execute(ctx, operation)`。  
反例：release 多于 acquire；closed 后继续 acquire；忘记释放；用 awaitIdle 代替 close；期望公平唤醒。

---

## 13. 测试/场景义务

1/N 并发；满时等待；取消；tryAcquire；release 边界；close 唤醒；close 后 acquire；close 后 release；awaitIdle；closeAndAwait；execute 异常释放；并发竞争。

---

## 14. XNull 伪代码

```xnull
class Bulkhead {
    final Int _maxConcurrent
    final RuntimeMonitor _monitor
    Int _inFlight = 0
    Bool _closed = false

    Bulkhead(Int maxConcurrent) {
        if maxConcurrent < 1 { throw "Bulkhead: maxConcurrent < 1" }
        _maxConcurrent = maxConcurrent
        _monitor = new RuntimeMonitor()
    }

    Result<T, Error> execute<T>(Context context, Result<T, Error>() operation) {
        if context == null || operation == null {
            throw "Bulkhead.execute: null argument"
        }
        Result<Unit, Error> acquired = self.acquire(context)
        if acquired.isErr() { return Err(acquired.error()) }
        defer self.release()
        return operation()
    }

    Result<Unit, Error> acquire(Context context) {
        if context == null { throw "Bulkhead.acquire: null context" }
        _monitor.enter()
        while true {
            if _closed {
                _monitor.exit()
                return Err(unavailableError("bulkhead is closed"))
            }
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("bulkhead acquire"))
            }
            if _inFlight < _maxConcurrent {
                _inFlight = _inFlight + 1
                _monitor.exit()
                return Ok(unit)
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("bulkhead acquire"))
            }
        }
    }

    Bool tryAcquire() {
        _monitor.enter()
        if _closed || _inFlight >= _maxConcurrent {
            _monitor.exit()
            return false
        }
        _inFlight = _inFlight + 1
        _monitor.exit()
        return true
    }

    Bool release() {
        _monitor.enter()
        if _inFlight <= 0 {
            _monitor.exit()
            return false
        }
        _inFlight = _inFlight - 1
        _monitor.notifyAll()
        _monitor.exit()
        return true
    }

    Int inFlight() {
        _monitor.enter()
        Int result = _inFlight
        _monitor.exit()
        return result
    }

    Int maxConcurrent() { return _maxConcurrent }

    Bool isClosed() {
        _monitor.enter()
        Bool result = _closed
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

    Result<Unit, Error> awaitIdle(Context context) {
        if context == null { throw "Bulkhead.awaitIdle: null context" }
        _monitor.enter()
        while _inFlight > 0 {
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("bulkhead await idle"))
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("bulkhead await idle"))
            }
        }
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> closeAndAwait(Context context) {
        self.close()
        return self.awaitIdle(context)
    }
}
```
