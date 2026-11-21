# `Mutex`

| 项 | 值 |
| --- | --- |
| 类型 | `class Mutex<T>` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`RuntimeMonitor` |

---

## 1. 定位

闭包式互斥锁：在持锁状态下执行 `void(T)` body；等待可被 `Context` 取消。

不做：裸 `lock/unlock`、重入锁、读写锁、公平锁、条件变量、超时加锁。

---

## 2. 设计逻辑

- 字段 `_value: T`、`_locked: Bool`、`_monitor`。
- `withLock` 获取锁、执行 body、释放锁；不暴露锁句柄。
- 等待锁时检查 `context.isCancelled()`；取消返回 `Cancelled`，不执行 body。
- body 无返回值；需要结果时由调用方捕获局部变量。`withLockResult` 为 X。
- T 应为引用类型；值类型副本无法通过 body 回写， 不支持。
- 非重入；同一任务重复加锁会死锁。
- 释放由 `defer` 保证；body 的 fatal throw 不保证清理（进程终止）。
- 无 close；锁随对象生命周期。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_value` | `T` | 受保护值 |
| `_locked` | `Bool` | 是否被持有 |
| `_monitor` | `RuntimeMonitor` | 等待/通知 |

不变量：`_locked` 只在持有时为 true；同一时刻至多一个 body；等待者可被取消。

---

## 4. 生命周期

构造后长期使用；无 close；锁在 body 返回/`Result` 返回时释放；进程终止不保证。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Mutex(T value)` | value | T 为引用类型 | 值类型实例不在  支持范围 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `withLock` | 持锁执行 | `Context context, void(T) body` | `Result<Unit, Error>` | `Cancelled`；null → panic |

说明：

- 获取锁前/等待中取消 → `Cancelled`，body 不执行。
- body 执行期间取消不会中断 body；body 应自行检查上下文。
- body 返回后释放锁并返回 `Ok(unit)`。
- 释放时唤醒所有等待者；公平性不承诺。
- 不提供 `isLocked`；查询会与持锁状态竞争。

---

## 8. 使用的技术

- 运行时监视器；
- 闭包式临界区；
- 取消感知等待；
- `defer` 释放。

---

## 9. 需要的支撑

- 语言：class、泛型、Bool、void、Result、defer；
- 运行时：`RuntimeMonitor` 的 `enter/exit/wait(Context)/notifyAll`；
- 接口：`Context`、`Error`、`cancelledError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`RuntimeMonitor`、`cancelledError`。

---

## 11. 所有权与并发

引用语义；线程安全；等待者不保证公平；非重入；无资源。

---

## 12. 示例与反例

正确：`mutex.withLock(ctx, (Counter c) -> { c.value = c.value + 1 })`。  
反例：裸 lock/unlock；同任务嵌套 withLock；用值类型 T 期望回写；期望取消中断正在执行的 body。

---

## 13. 测试/场景义务

串行更新；并发等待；取消等待；body 返回释放；非重入死锁边界；通知唤醒；null 参数。

---

## 14. XNull 伪代码

```xnull
class Mutex<T> {
    T _value
    Bool _locked = false
    final RuntimeMonitor _monitor

    Mutex(T value) {
        _value = value
        _monitor = new RuntimeMonitor()
    }

    Result<Unit, Error> withLock(Context context, void(T) body) {
        if context == null || body == null {
            throw "Mutex.withLock: null argument"
        }
        Result<Unit, Error> acquired = self.acquire(context)
        if acquired.isErr() { return Err(acquired.error()) }
        defer self.release()
        body(_value)
        return Ok(unit)
    }

    Result<Unit, Error> acquire(Context context) {
        _monitor.enter()
        if context.isCancelled() {
            _monitor.exit()
            return Err(cancelledError("mutex lock"))
        }
        while _locked {
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("mutex lock"))
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("mutex lock"))
            }
        }
        _locked = true
        _monitor.exit()
        return Ok(unit)
    }

    void release() {
        _monitor.enter()
        _locked = false
        _monitor.notifyAll()
        _monitor.exit()
    }
}
```

> `RuntimeMonitor.wait(Context)` 返回 false 表示等待被取消；返回 true 表示被通知或可能虚假唤醒，调用方必须循环重查条件。
