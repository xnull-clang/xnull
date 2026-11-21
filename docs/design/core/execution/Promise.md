# `Promise<T>`

| 项 | 值 |
| --- | --- |
| 类型 | `class Promise<T>` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Future<T>`、`Context`、`Error`、`RuntimeMonitor` |

---

## 1. 定位

一次性完成状态：写入一个值或错误，暴露可多读者等待的 `Future<T>`。

不做：多值流、重试、取消传播树、任务调度、异步回调注册。

---

## 2. 设计逻辑

- 字段 `_done`、`_value: T?`、`_error: Error?`、`_monitor`。
- `complete`/`fail` 只能成功一次；后续调用返回 false，不覆盖结果。
- `cancel(reason)` 等价于 `fail(BasicError(Cancelled, reason))`。
- `future()` 返回共享同一状态的只读视图；可多次调用，返回等价视图。
- `await`/`awaitDeadline` 可多读者；不消费。
- 等待中取消返回 `Cancelled`，不改变 Promise 状态。
- 无 close；完成后状态只读；可跨任务共享。
- `T` 可为值/引用类型；成功值按 T 的复制/句柄语义返回。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_done` | `Bool` | 是否完成 |
| `_value` | `T?` | 成功值；未完成/失败为 null |
| `_error` | `Error?` | 失败值；成功为 null |
| `_monitor` | `RuntimeMonitor` | 等待/通知 |

不变量：done 后恰有 value 或 error 之一；done 后不再改变；value/error 不双设。

---

## 4. 生命周期

构造后使用；`complete/fail/cancel` 一次；完成后读取；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Promise()` | 无 | 未完成 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `future` | 只读视图 | 无 | `Future<T>` | 无 |
| `complete` | 完成成功 | `T value` | `Bool` | 已完成后 false |
| `fail` | 完成失败 | `Error error` | `Bool` | null → panic；已完成后 false |
| `cancel` | 取消 | `String reason` | `Bool` | null → panic；已完成后 false |
| `isDone` | 是否完成 | 无 | `Bool` | 无 |
| `isCancelled` | 是否取消 | 无 | `Bool` | 无 |
| `failure` | 失败值 | 无 | `Error?` | 无 |
| `await` | 等待结果 | `Context context` | `Result<T, Error>` | `Cancelled`；null → panic |
| `awaitDeadline` | 截止等待 | `Context context, Long deadlineMonoMillis` | `Result<T, Error>` | `Timeout`/`Cancelled` |

说明：

- `complete(null)` 对引用类型合法；`T` 为值类型时按值。
- `fail` 后 `await` 返回该错误。
- `awaitDeadline` 超时返回 `Timeout`，不改变 Promise。
- `failure` 未完成返回 null；成功后返回 null。
- `future()` 多次调用返回不同视图但共享状态。

---

## 8. 使用的技术

- 一次性状态机；
- 运行时监视器；
- 截止等待；
- 多读者广播；
- Result。

---

## 9. 需要的支撑

- 语言：class、泛型、Bool、Long、Result；
- 运行时：`RuntimeMonitor.enter/exit/wait(Context)/waitDeadline(Context, Long)/notifyAll`、
  `nowMono`；`waitDeadline` 返回 0 = 通知、1 = 取消、2 = 超时；
- 接口：`Future`、`Context`、`Error`、`BasicError`、`ErrorKind`、`cancelledError`。

---

## 10. 依赖的特性/接口/类

`Future<T>`、`Context`、`Error`、`RuntimeMonitor`、`BasicError`、`ErrorKind`、
`cancelledError`、`timeoutError`。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；多读者；写入一次性；无资源。
相等：引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
Promise<String> promise = new Promise<String>()
Future<String> future = promise.future()
promise.complete("ok")
Result<String, Error> value = future.get(ctx)
```

反例：完成两次；fail 后 complete；等待者取消后写入者停止；把 Promise 当可重置 Future；
在 Promise 上阻塞写线程。

---

## 13. 测试/场景义务

完成/失败/取消；重复完成；null 错误；多读者；取消等待者；截止超时/已完成；
值/引用类型；`failure`；`future` 多视图；并发写入/读取。

---

## 14. XNull 伪代码

```xnull
class Promise<T> {
    Bool _done = false
    T? _value
    Error? _error
    final RuntimeMonitor _monitor

    Promise() {
        _monitor = new RuntimeMonitor()
    }

    Future<T> future() {
        return new Future<T>(self)
    }

    Bool complete(T value) {
        _monitor.enter()
        if _done {
            _monitor.exit()
            return false
        }
        _value = value
        _done = true
        _monitor.notifyAll()
        _monitor.exit()
        return true
    }

    Bool fail(Error error) {
        if error == null { throw "Promise.fail: null error" }
        _monitor.enter()
        if _done {
            _monitor.exit()
            return false
        }
        _error = error
        _done = true
        _monitor.notifyAll()
        _monitor.exit()
        return true
    }

    Bool cancel(String reason) {
        if reason == null { throw "Promise.cancel: null reason" }
        return self.fail(new BasicError(ErrorKind.Cancelled, reason))
    }

    Bool isDone() {
        _monitor.enter()
        Bool result = _done
        _monitor.exit()
        return result
    }

    Bool isCancelled() {
        _monitor.enter()
        Bool result = _done && _error != null
            && _error.kind() == ErrorKind.Cancelled
        _monitor.exit()
        return result
    }

    Error? failure() {
        _monitor.enter()
        Error? result = _error
        _monitor.exit()
        return result
    }

    Result<T, Error> await(Context context) {
        if context == null { throw "Promise.await: null context" }
        _monitor.enter()
        while !_done {
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("promise await"))
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("promise await"))
            }
        }
        if _error != null {
            Error error = _error as Error
            _monitor.exit()
            return Err(error)
        }
        T value = _value as T
        _monitor.exit()
        return Ok(value)
    }

    Result<T, Error> awaitDeadline(Context context, Long deadlineMonoMillis) {
        if context == null { throw "Promise.awaitDeadline: null context" }
        _monitor.enter()
        while !_done {
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("promise await"))
            }
            Long now = nowMono()
            if now >= deadlineMonoMillis {
                _monitor.exit()
                return Err(timeoutError("promise await"))
            }
            Int state = _monitor.waitDeadline(context, deadlineMonoMillis)
            if state == 1 {
                _monitor.exit()
                return Err(cancelledError("promise await"))
            }
            if state == 2 {
                _monitor.exit()
                return Err(timeoutError("promise await"))
            }
        }
        if _error != null {
            Error error = _error as Error
            _monitor.exit()
            return Err(error)
        }
        T value = _value as T
        _monitor.exit()
        return Ok(value)
    }
}
```
