# `TaskGroup`

| 项 | 值 |
| --- | --- |
| 类型 | `class TaskGroup` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Task`、`TaskHandle`、`Error`、`RuntimeMonitor` |

---

## 1. 定位

结构化任务组：创建子上下文、启动任务、取消、等待全部结束、回收首个非取消错误。

不做：线程池调优、任务优先级、错误聚合、任务重试、全局任务注册。

---

## 2. 设计逻辑

- 字段：组上下文、任务句柄列表、接受新任务标志、closing/closed 状态、首个非取消错误。
- `spawn` 在组上下文中创建子上下文，启动运行时任务，返回 `Task<T>`；任务实现 `TaskHandle`，组用 `List<TaskHandle>` 持有异构任务。
- `cancel` 停止接受新任务，取消组上下文和所有已登记任务；不等待。
- `close` 停止接受、取消、等待所有任务、记录首个非取消错误；幂等且并发安全。
- 第二次 `close` 返回同一结果；若首次失败，仍返回该错误。
- `close` 不得从组内任务调用；否则等待自身，可能死锁。
- 任务忽略取消时，`close` 可能一直等待；这是协作取消的边界。
- 无全局任务组；由调用方持有。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_context` | `Context` | 组上下文 |
| `_monitor` | `RuntimeMonitor` | 内部同步 |
| `_tasks` | `List<TaskHandle>` | 已启动任务 |
| `_accepting` | `Bool` | 是否接受 spawn |
| `_closing` | `Bool` | close 进行中 |
| `_closed` | `Bool` | close 完成 |
| `_firstError` | `Error?` | 首个非取消错误 |

不变量：closed 后不再接受任务；closing 时 close 等待；`_firstError` 只记录首个非取消错误；`_tasks` 只追加。

---

## 4. 生命周期

`TaskGroup.create` 创建；`spawn` 使用；`cancel` 停止；`close` 取消/等待/回收；close 幂等；无 `deinit` 依赖。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TaskGroup.create(Context parent)` | parent | 非 null | null → panic |

构造器私有；业务代码不直接 `new TaskGroup`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `create` | 创建组 | `Context parent` | `TaskGroup` | null → panic |
| `context` | 组上下文 | 无 | `Context` | 无 |
| `isClosed` | 是否已关闭 | 无 | `Bool` | 无 |
| `spawn` | 启动任务 | `Result<T, Error>(Context) body` | `Result<Task<T>, Error>` | 已关闭 → `Unavailable` |
| `cancel` | 取消组 | 无 | `void` | 无 |
| `close` | 取消/等待/回收 | 无 | `Result<Unit, Error>` | 首个非取消任务错误 |

说明：

- `spawn` 的 body 接收任务子上下文；body 必须检查取消。
- `spawn` 在 `cancel`/`close` 后返回 `Unavailable`。
- `cancel` 不等待；`close` 等待。
- `close` 对每个任务先 `cancel` 再 `awaitDone`，再读 `failure`。
- `close` 跳过 `Cancelled` 错误；只保留首个非取消错误。
- `close` 的重复调用返回同一结果。
- `close` 线程安全；并发 close 的后来者等待首次 close 完成。

---

## 8. 使用的技术

- 结构化并发；
- 运行时监视器；
- 任务句柄列表；
- 取消传播；
- 首个错误保留。

---

## 9. 需要的支撑

- 语言：class、List、Bool、Result；
- 运行时：`RuntimeMonitor`、`spawnRaw`、`TaskRuntimeHandle<T>`；
- 接口：`Context`、`Task`、`TaskHandle`、`Error`、`isCancellation`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Task`、`TaskHandle`、`Error`、`RuntimeMonitor`、`spawnRaw`、`unavailableError`、`isCancellation`。

---

## 11. 所有权与并发

引用语义；线程安全；组持有任务句柄；任务可单独 join；close 后不再 spawn；无资源句柄。

---

## 12. 示例与反例

正确：`TaskGroup g = TaskGroup.create(ctx); Task<Int> t = g.spawn((Context c) -> {...}).value(); g.close()`。  
反例：close 后 spawn；从组内任务调用 close；忽略 cancellation 期望 close 立即返回；依赖错误聚合。

---

## 13. 测试/场景义务

spawn 成功/关闭后失败；cancel 传播；close 等待；首个非取消错误；仅取消 → Ok；重复/并发 close；父上下文取消；body 收到子上下文。

---

## 14. XNull 伪代码

```xnull
class TaskGroup {
    final Context _context
    final RuntimeMonitor _monitor
    List<TaskHandle> _tasks = []
    Bool _accepting = true
    Bool _closing = false
    Bool _closed = false
    Error? _firstError = null

    private TaskGroup(Context context) {
        _context = context
        _monitor = new RuntimeMonitor()
    }

    static TaskGroup create(Context parent) {
        if parent == null { throw "TaskGroup.create: null parent" }
        return new TaskGroup(Context.withCancel(parent))
    }

    Context context() { return _context }

    Bool isClosed() {
        _monitor.enter()
        Bool result = _closed
        _monitor.exit()
        return result
    }

    Result<Task<T>, Error> spawn<T>(Result<T, Error>(Context) body) {
        if body == null { throw "TaskGroup.spawn: null body" }
        _monitor.enter()
        if !_accepting {
            _monitor.exit()
            return Err(unavailableError("task group"))
        }
        Context child = Context.withCancel(_context)
        Result<TaskRuntimeHandle<T>, Error> spawned = spawnRaw(child, body)
        if spawned.isErr() {
            child.cancel()
            _monitor.exit()
            return Err(spawned.error())
        }
        Task<T> task = new Task<T>(child, spawned.value())
        _tasks.push(task)
        _monitor.exit()
        return Ok(task)
    }

    void cancel() {
        _monitor.enter()
        _accepting = false
        List<TaskHandle> snapshot = _tasks.copy()
        _monitor.exit()
        _context.cancel()
        Int index = 0
        while index < snapshot.length() {
            snapshot.get(index).cancel()
            index = index + 1
        }
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _closed {
            Error? existing = _firstError
            _monitor.exit()
            if existing == null { return Ok(unit) }
            return Err(existing as Error)
        }
        if _closing {
            while !_closed {
                _monitor.wait()
            }
            Error? existing = _firstError
            _monitor.exit()
            if existing == null { return Ok(unit) }
            return Err(existing as Error)
        }
        _closing = true
        _accepting = false
        List<TaskHandle> snapshot = _tasks.copy()
        _monitor.exit()
        _context.cancel()
        Int index = 0
        while index < snapshot.length() {
            TaskHandle task = snapshot.get(index)
            task.cancel()
            task.awaitDone()
            Error? failure = task.failure()
            if failure != null {
                Error taskError = failure as Error
                if !isCancellation(taskError) {
                    _monitor.enter()
                    if _firstError == null {
                        _firstError = taskError
                    }
                    _monitor.exit()
                }
            }
            index = index + 1
        }
        _monitor.enter()
        _closed = true
        _closing = false
        _monitor.notifyAll()
        Error? result = _firstError
        _monitor.exit()
        if result == null { return Ok(unit) }
        return Err(result as Error)
    }
}
```

> `RuntimeMonitor` 提供 `enter`、`exit`、`wait`、`notifyAll`；`spawnRaw` 返回 `TaskRuntimeHandle<T>`；两者都是运行时原语，不是 XDK 公共类型。`spawnRaw` 在返回前不得同步执行 body，否则会与组监视器冲突；任务由调度器在之后运行。
