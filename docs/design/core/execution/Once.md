# `Once`

| 项 | 值 |
| --- | --- |
| 类型 | `class Once` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`RuntimeMonitor` |

---

## 1. 定位

保证一段初始化/清理逻辑在进程内只执行一次；其他调用者等待首次执行完成。

不做：失败重试、返回值缓存、跨进程一次性、可重置。

---

## 2. 设计逻辑

- 字段 `_done`、`_running`、`_monitor`。
- `do`：已完成直接返回；否则首个调用者执行 `body`，其他调用者在 `_running` 上等待。
- `body` 成功返回后标记 `_done`；`body` 是 `void()`，不表达可恢复失败。
- `body` panic 是 fatal，进程终止；不存在“失败后重试”的语义。
- 等待中取消返回 `Cancelled`；首个调用者的 `body` 继续执行，完成后 `_done` 仍为 true。
- 不可重入：`body` 内再次调用同一个 `Once.do` 会等待自身，死锁；文档禁止。
- 线程安全；可跨任务共享；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_done` | `Bool` | 是否已成功执行 |
| `_running` | `Bool` | 是否正在执行 |
| `_monitor` | `RuntimeMonitor` | 等待/通知 |

不变量：`_done` 为 true 时 `_running` 为 false；`_running` 为 true 时恰有一个执行者；
done 一旦为 true 不再回退。

---

## 4. 生命周期

构造后使用；`do` 可多次；无 close；无 OS 资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Once()` | 无 | 未执行 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `do` | 执行一次 | `Context context, void() body` | `Result<Unit, Error>` | `Cancelled`；null → panic |
| `isDone` | 是否已完成 | 无 | `Bool` | 无 |

说明：

- `do` 在取消时返回 `Err(Cancelled)`，不执行 `body`；若已在执行，等待者取消不影响执行者。
- `body` 返回后 `do` 返回 `Ok(unit)`；等待者同样返回 `Ok(unit)`。
- 无 `reset`；需要可重置的一次性逻辑改用 `AtomicBool`/`Mutex`。

---

## 8. 使用的技术

- 一次性状态机；
- 运行时监视器；
- 取消感知等待；
- 广播唤醒。

---

## 9. 需要的支撑

- 语言：class、Bool、Result、Unit、闭包；
- 运行时：`RuntimeMonitor.enter/exit/wait(Context)/notifyAll`；
- 接口：`Context`、`Error`、`cancelledError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`RuntimeMonitor`、`cancelledError`。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；不可重入；无资源。
相等：引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：`once.do(ctx, () -> { loadConfig() })`。  
反例：`body` 内再次 `do` 同一对象；把 `Once` 当缓存失败重试；等待者取消后认为执行者已停止；
依赖 `Once` 清理进程级资源。

---

## 13. 测试/场景义务

首次执行；并发只执行一次；等待者；取消；执行者完成后等待者返回；不可重入检测（设计约束）；
`isDone`；panic 终止路径（子进程）。

---

## 14. XNull 伪代码

```xnull
class Once {
    Bool _done = false
    Bool _running = false
    final RuntimeMonitor _monitor

    Once() {
        _monitor = new RuntimeMonitor()
    }

    Result<Unit, Error> do(Context context, void() body) {
        if context == null || body == null {
            throw "Once.do: null argument"
        }
        _monitor.enter()
        if _done {
            _monitor.exit()
            return Ok(unit)
        }
        while _running {
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("once"))
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("once"))
            }
        }
        if _done {
            _monitor.exit()
            return Ok(unit)
        }
        _running = true
        _monitor.exit()
        body()
        _monitor.enter()
        _running = false
        _done = true
        _monitor.notifyAll()
        _monitor.exit()
        return Ok(unit)
    }

    Bool isDone() {
        _monitor.enter()
        Bool result = _done
        _monitor.exit()
        return result
    }
}
```
