# xdk.tasks —— T0 任务与取消 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.tasks` |
| 层级 | T0 |
| 稳定性 | `preview` |
| 依赖 | `xdk.errors`、`xdk.runtime` |
| 被依赖 | sync、log、config、cli |
| 对应源码 | `src/xdk/concurrent/tasks/Tasks.x`（运行时绑定） |
| 当前状态 | Verified（mini） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 任务 | 可 join 的并发执行体 | `Task<T>` |
| CAP-2 任务组 | 结构化生命周期、首个错误 | `TaskGroup` |
| CAP-3 上下文 | 取消、父子传递 | `Context` |
| CAP-4 截止等待 | join 超时 | `Task.joinDeadline` |
| CAP-5 取消 | 协作取消 | `Context.cancel`、`TaskGroup.cancel` |

**非目标**：select/race、Context 值、取消作用域、线程池调优。

## 2. 契约

```text
class Context {
    static Context background()
    Bool isCancelled()
    void cancel()
}

class TaskGroup {
    static TaskGroup create(Context parent)
    Task<T> spawn(Result<T,TaskError>() body)
    void cancel()
    Result<void, TaskError> close()
}

class Task<T> {
    Result<T, TaskError> join()
    Result<T, TaskError> joinDeadline(Long deadlineMonoMs)
}
```

| 方法 | 前置 | 后置 | 失败 |
| --- | --- | --- | --- |
| `TaskGroup.create(parent)` | parent 非 null | 子组继承取消 | 无 |
| `spawn(body)` | body 非 null | 返回任务；组关闭后不得 spawn | `Unavailable` |
| `join()` | 任务未被消费 | 返回结果并消费任务 | `Cancelled`/`TaskError` |
| `joinDeadline(deadline)` | deadline 为单调毫秒 | 超时返回 `Timeout` 且不消费结果 | `Timeout` |
| `close()` | 无 | 取消组、等待任务、返回首个非取消错误 | 幂等；二次 `Ok` |
| `Context.cancel()` | 无 | 标记取消；已取消为 no-op | 无 |

- 取消是错误值，不抛异常；`CancelledError` 的 `kind()` 为 `Cancelled`。
- `close` 是资源释放路径；不得依赖 `deinit`。
- 任务结果所有权在 `join` 后转移；重复 join 是合同错误。

## 3. 测试义务

- Ok/Err join；
- 组 close 的首个非取消错误；
- cancel 后任务返回 Cancelled；
- joinDeadline 超时且任务继续；
- close 幂等。

场景：`xdk_tasks.x`、`xdk_cancel.x`。

## 4. 后续（T0-X）

- `select`/`race`；
- Context 值与取消作用域；
- 任务组结果聚合、错误组；
- 线程归属/执行器。
