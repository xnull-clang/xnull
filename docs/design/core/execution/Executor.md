# `Executor`

| 项 | 值 |
| --- | --- |
| 类型 | `class Executor` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Task`、`TaskGroup`、`Semaphore`、`AtomicBool`、`Error` |

---

## 1. 定位

有界并发提交器：限制同时运行的任务数；`submit` 返回 `Task<T>`；`close` 取消并等待。

不做：工作窃取、优先级、定时调度、结果聚合、全局线程池、无界队列。

---

## 2. 设计逻辑

- 字段 `_group: TaskGroup`、`_semaphore: Semaphore`、`_parallelism: Int`、`_closed: AtomicBool`。
- `submit` 先获取许可（可取消/可阻塞），再在 `TaskGroup` 中启动任务；任务体退出时释放许可。
- 没有隐藏队列：许可满时 `submit` 阻塞；需要排队时由调用方使用 `Channel`。
- `submit` 返回 `Task<T>`；结果消费仍是单消费者 `join`。
- `close` 先关闭信号量（唤醒等待者），再 `TaskGroup.close` 取消并等待在途任务；幂等。
- `close` 不杀任务；忽略取消的任务会使 close 等待。
- 可跨任务并发 `submit`；`close` 可并发。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_group` | `TaskGroup` | 拥有任务生命周期 |
| `_semaphore` | `Semaphore` | 并发许可 |
| `_parallelism` | `Int` | >0 |
| `_closed` | `AtomicBool` | 是否关闭；并发可见 |

不变量：parallelism > 0；closed 后 submit 返回 `Unavailable`；任务数 ≤ parallelism；
close 幂等。

---

## 4. 生命周期

构造创建组与信号量；`submit` 使用；`close` 取消/等待/回收；close 幂等；无 `deinit` 依赖。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Executor(Context parent, Int parallelism)` | parent/parallelism | 非 null；>0 | null/≤0 → panic |
| `fixed(Context parent, Int parallelism)` | 同上 | 同上 | 同上 |
| `single(Context parent)` | parent | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `fixed` | 固定并发 | `Context parent, Int parallelism` | `Executor` | null/≤0 → panic |
| `single` | 单并发 | `Context parent` | `Executor` | null → panic |
| `submit` | 提交任务 | `Context context, Result<T, Error>(Context) body` | `Result<Task<T>, Error>` | `Cancelled`/`Unavailable`；null → panic |
| `close` | 关闭并等待 | 无 | `Result<Unit, Error>` | 首个非取消任务错误 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `parallelism` | 并发上限 | 无 | `Int` | 无 |
| `activeCount` | 当前运行数 | 无 | `Int` | 无 |
| `availablePermits` | 可用许可 | 无 | `Int` | 无 |

说明：

- `submit` 在许可满时阻塞；`context` 取消返回 `Cancelled`。
- `submit` 在 closed 后（含等待中被 close）返回 `Unavailable`。
- `body` 接收任务子上下文；必须检查取消。
- `close` 返回 `TaskGroup.close` 的结果；重复 close 返回同一结果。
- `activeCount` 是瞬时值；`parallelism - availablePermits`。

---

## 8. 使用的技术

- 有界并发；
- 信号量许可；
- 结构化任务组；
- 取消传播；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、泛型方法、Int、Bool、Result、闭包；
- 运行时：`TaskGroup`、`Semaphore`、`Context`；
- 接口：`Task`、`TaskGroup`、`Semaphore`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Task`、`TaskGroup`、`Semaphore`、`AtomicBool`、`Error`、`unavailableError`。

---

## 11. 所有权与并发

引用语义；拥有 TaskGroup/Semaphore；可并发 submit；close 可并发；Task 结果由调用方消费；
无全局执行器。
相等：引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
Executor executor = Executor.fixed(root, 8)
Result<Task<Int>, Error> task = executor.submit(ctx, (Context taskContext) -> {
    return Ok(1)
})
Result<Unit, Error> closed = executor.close()
```

反例：用 Executor 当无界队列；重复 join 同一 Task；close 后 submit；忽略 Cancelled；
在任务体内 `executor.close()`（等待自身）。

---

## 13. 测试/场景义务

并发上限；submit 阻塞/取消；closed 后 submit；close 取消/等待；重复 close；任务错误；
任务忽略取消；activeCount/availablePermits；多任务竞争；客户端小池/服务器大池。

---

## 14. XNull 伪代码

```xnull
class Executor {
    final TaskGroup _group
    final Semaphore _semaphore
    final Int _parallelism
    final AtomicBool _closed

    Executor(Context parent, Int parallelism) {
        if parent == null { throw "Executor: null parent" }
        if parallelism <= 0 { throw "Executor: parallelism <= 0" }
        _group = TaskGroup.create(parent)
        _semaphore = new Semaphore(parallelism)
        _parallelism = parallelism
        _closed = new AtomicBool(false)
    }

    static Executor fixed(Context parent, Int parallelism) {
        return new Executor(parent, parallelism)
    }

    static Executor single(Context parent) {
        return new Executor(parent, 1)
    }

    Result<Task<T>, Error> submit<T>(Context context, Result<T, Error>(Context) body) {
        if context == null || body == null {
            throw "Executor.submit: null argument"
        }
        if _closed.load() {
            return Err(unavailableError("executor submit"))
        }
        Result<Unit, Error> permit = _semaphore.acquire(context)
        if permit.isErr() { return Err(permit.error()) }
        Result<Task<T>, Error> spawned = _group.spawn((Context taskContext) -> {
            defer { _semaphore.release() }
            return body(taskContext)
        })
        if spawned.isErr() {
            _semaphore.release()
            return Err(spawned.error())
        }
        return spawned
    }

    Result<Unit, Error> close() {
        _closed.store(true)
        _semaphore.close()
        return _group.close()
    }

    Bool isClosed() { return _closed.load() }
    Int parallelism() { return _parallelism }

    Int activeCount() {
        return _parallelism - _semaphore.available()
    }

    Int availablePermits() {
        return _semaphore.available()
    }
}
```
