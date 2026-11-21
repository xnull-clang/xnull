# `WaitGroup`

| 项 | 值 |
| --- | --- |
| 类型 | `class WaitGroup` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`RuntimeMonitor` |

---

## 1. 定位

等待一组任务完成：`add` 增加计数，`done` 减少计数，`wait` 等待计数归零；等待可取消。

不做：任务启动、结果收集、错误聚合、自动取消、跨进程等待。

---

## 2. 设计逻辑

- 字段 `_count`、`_monitor`。
- `add(count)` 增加计数；`count` 必须 ≥0；0 是 no-op。
- `done()` 减少计数；计数已为 0 时是合同错误（panic）。
- `wait(Context)` 在计数 >0 时等待；取消返回 `Cancelled`；计数为 0 立即返回 `Ok(unit)`。
- 允许多个等待者；`notifyAll` 唤醒后重新检查条件。
- 不跟踪谁 add/done；调用方保证配对。
- 可跨任务共享；线程安全；不承诺公平。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_count` | `Int` | ≥0；未完成数 |
| `_monitor` | `RuntimeMonitor` | 等待/通知 |

不变量：`_count >= 0`；done 不得使计数为负；wait 返回后计数为 0（或已取消）。

---

## 4. 生命周期

构造后使用；计数归零后可继续 add 复用；无 close；无 OS 资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `WaitGroup()` | 无 | 初始计数 0 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 增加计数 | `Int count` | `void` | 负值 → panic |
| `done` | 减少计数 | 无 | `void` | 计数为 0 → panic |
| `wait` | 等待归零 | `Context context` | `Result<Unit, Error>` | `Cancelled`；null → panic |
| `count` | 当前计数 | 无 | `Int` | 无 |

说明：

- `add` 可在 `wait` 前或计数非 0 时调用；不要在计数归零后与 `wait` 竞争。
- `wait` 取消时计数不变，调用方可重试或放弃。
- `count` 是瞬时快照。

---

## 8. 使用的技术

- 计数器；
- 运行时监视器；
- 取消感知等待；
- 多等待者广播。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、Result、Unit；
- 运行时：`RuntimeMonitor.enter/exit/wait(Context)/notifyAll`；
- 接口：`Context`、`Error`、`cancelledError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`RuntimeMonitor`、`cancelledError`。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；无所有者跟踪；无资源。
相等：引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
WaitGroup group = new WaitGroup()
group.add(2)
spawnWorker(group)
spawnWorker(group)
Result<Unit, Error> done = group.wait(ctx)
```

反例：done 多于 add；计数归零后与 wait 竞争 add；忽略 Cancelled；用 WaitGroup 收集结果。

---

## 13. 测试/场景义务

add/done 配对；多等待者；取消；计数归零立即返回；负 add；多余 done panic；
复用；高并发压力。

---

## 14. XNull 伪代码

```xnull
class WaitGroup {
    Int _count = 0
    final RuntimeMonitor _monitor

    WaitGroup() {
        _monitor = new RuntimeMonitor()
    }

    void add(Int count) {
        if count < 0 { throw "WaitGroup.add: negative count" }
        if count == 0 { return }
        _monitor.enter()
        _count = _count + count
        _monitor.exit()
    }

    void done() {
        _monitor.enter()
        if _count <= 0 {
            _monitor.exit()
            throw "WaitGroup.done: counter is zero"
        }
        _count = _count - 1
        if _count == 0 {
            _monitor.notifyAll()
        }
        _monitor.exit()
    }

    Result<Unit, Error> wait(Context context) {
        if context == null { throw "WaitGroup.wait: null context" }
        _monitor.enter()
        while _count > 0 {
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("wait group"))
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("wait group"))
            }
        }
        _monitor.exit()
        return Ok(unit)
    }

    Int count() {
        _monitor.enter()
        Int result = _count
        _monitor.exit()
        return result
    }
}
```
