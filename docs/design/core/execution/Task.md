# `Task`

| 项 | 值 |
| --- | --- |
| 类型 | `class Task<T> implements TaskHandle` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Context`、`TaskHandle`、`TaskRuntimeHandle<T>`、`Error` |

---

## 1. 定位

单个任务的公开句柄：等待完成、读取结果、取消、查询状态、读取任务上下文。

不做：任务调度、任务组生命周期、结果聚合、重复消费。

---

## 2. 设计逻辑

- `Task<T>` 包装运行时 `TaskRuntimeHandle<T>`；公开 API 不暴露运行时句柄。
- 实现 `TaskHandle`，让 `TaskGroup` 能用 `List<TaskHandle>` 持有异构任务。
- `join` 是单消费者：等待完成后标记 `_consumed`，再返回结果；重复 join 是合同错误。
- `joinDeadline` 超时返回 `Timeout` 且不消费；任务继续运行。
- `failure` 不消费，可在完成后多次读取。
- `cancel` 只取消任务上下文，不等待；幂等。
- `Task` 由 `TaskGroup.spawn` 创建；业务代码不直接构造。
- 无 close；任务结束后由运行时释放。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_context` | `Context` | 任务子上下文 |
| `_handle` | `TaskRuntimeHandle<T>` | 运行时句柄 |
| `_consumed` | `Bool` | 是否已被 join 消费 |

不变量：context/handle 非 null；join 成功后 consumed=true；timeout 不改变 consumed；不可重复 join。

---

## 4. 生命周期

`TaskGroup.spawn` 创建；任务完成后句柄仍可查询；`join` 消费结果；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Task(Context context, TaskRuntimeHandle<T> handle)` | context/handle | 非 null | null → panic |

构造器主要供 `TaskGroup`/运行时使用；业务代码不应直接构造。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `context` | 任务上下文 | 无 | `Context` | 无 |
| `isDone` | 是否完成 | 无 | `Bool` | 无 |
| `cancel` | 请求取消 | 无 | `void` | 无 |
| `awaitDone` | 等待完成 | 无 | `void` | 无 |
| `failure` | 失败值 | 无 | `Error?` | 未完成 → panic |
| `join` | 等待并消费 | 无 | `Result<T, Error>` | 重复 join → panic；任务错误 |
| `joinDeadline` | 截止等待 | `Long deadlineMonoMillis` | `Result<T, Error>` | `Timeout`/任务错误；重复 join → panic |

说明：

- `join` 等待任务完成；任务返回 `Err` 时仍消费结果。
- `joinDeadline` 的 deadline 是单调毫秒；超时返回 `Timeout`，任务继续。
- 若任务已完成，`joinDeadline` 立即返回结果，即使 deadline 已过。
- `failure` 不改变消费状态；只应在 `isDone` 后调用。
- `awaitDone` 可多等待者；不消费。
- `cancel` 不保证任务立即结束；任务必须检查 `context.isCancelled()`。

---

## 8. 使用的技术

- 运行时任务句柄；
- 单消费者标志；
- 截止等待；
- 取消传播。

---

## 9. 需要的支撑

- 语言：class、protocol 实现、泛型、Bool、Long、Result；
- 运行时：`TaskRuntimeHandle<T>`、`awaitDone`、`awaitDoneDeadline`；
- 接口：`Context`、`TaskHandle`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`TaskHandle`、`Error`、`TaskRuntimeHandle<T>`。

---

## 11. 所有权与并发

引用语义；`join` 单消费者，不可并发 join；`isDone`/`cancel`/`awaitDone`/`failure` 可并发；无资源。

---

## 12. 示例与反例

正确：`Result<Int,Error> r = task.join()`；超时后 `task.join()` 仍可消费。  
反例：重复 join；joinDeadline 超时后认为任务已取消；并发两个 join；未完成调用 failure。

---

## 13. 测试/场景义务

Ok/Err join；取消；joinDeadline 超时/已完成/已取消；failure 多读；重复 join；多等待者 awaitDone；上下文取消传播。

---

## 14. XNull 伪代码

```xnull
class Task<T> implements TaskHandle {
    final Context _context
    final TaskRuntimeHandle<T> _handle
    Bool _consumed = false

    Task(Context context, TaskRuntimeHandle<T> handle) {
        if context == null || handle == null {
            throw "Task: null argument"
        }
        _context = context
        _handle = handle
    }

    Context context() { return _context }
    Bool isDone() { return _handle.isDone() }
    void cancel() { _handle.cancel() }
    void awaitDone() { _handle.awaitDone() }
    Error? failure() { return _handle.failure() }

    Result<T, Error> join() {
        if _consumed { throw "Task.join: already consumed" }
        _handle.awaitDone()
        _consumed = true
        return _handle.result()
    }

    Result<T, Error> joinDeadline(Long deadlineMonoMillis) {
        if _consumed { throw "Task.joinDeadline: already consumed" }
        Result<Unit, Error> waited = _handle.awaitDoneDeadline(deadlineMonoMillis)
        if waited.isErr() { return Err(waited.error()) }
        _consumed = true
        return _handle.result()
    }
}
```

> `TaskRuntimeHandle<T>` 是运行时原语，提供 `isDone`、`cancel`、`awaitDone`、`awaitDoneDeadline`、`result`、`failure`；不是 XDK 公共类型。
