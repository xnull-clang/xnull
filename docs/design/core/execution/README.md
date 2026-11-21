# 执行层内建（原 `tasks` / `sync`）

| 项 | 值 |
| --- | --- |
| 范围 | `xdk.execution` / L1 运行时与执行 |
| 依赖 | `xdk.errors`、`xdk.runtime` |
| 被依赖 | 所有并发/取消/阻塞 API |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 定位

执行层提供结构化并发、协作取消、互斥、消息传递和原子操作：

- `Context`：取消传播；
- `TaskHandle` / `Task`：任务句柄与单消费者结果；
- `TaskGroup`：结构化任务生命周期；
- `Mutex<T>`：闭包式互斥；
- `Channel<T>`：有界消息队列；
- `AtomicInt` / `AtomicBool` / `AtomicRef<T>`：顺序一致的原子操作；
- `Executor`：有界并发提交；
- `Semaphore` / `RwLock<T>` / `WaitGroup` / `Once`：并发协调；
- `Pool<T>`：通用对象池；
- `Future<T>` / `Promise<T>`：一次性多读者结果。

这些类型是语言/运行时内建；历史 `xdk.tasks` / `xdk.sync` 只作 1.x 兼容命名，不计入 1.x 公共包承诺；2.x 统一为 `xdk.execution`。

不做：线程池调优、工作窃取、实时调度、`Select`/`race`、`Timer`、`Barrier`、`Lazy`、`Broadcast`、`PubSub`。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 协作取消 | 取消只设置标记；不杀线程、不强制中断 |
| 结构化生命周期 | `TaskGroup.close` 取消、等待、回收；不依赖 `deinit` |
| 取消是错误值 | `Result` + `ErrorKind.Cancelled`，不抛业务异常 |
| 阻塞可取消 | 锁等待、通道收发接受 `Context`；任务等待用 `joinDeadline` |
| 单消费者 join | `Task.join` 只允许一次；重复是合同错误 |
| 不提供裸锁 | `Mutex` 只暴露闭包式 `withLock` |
| 关闭幂等 | `TaskGroup.close`、`Channel.close` 可重复调用 |
| 无全局执行器 | 任务由调用方持有 `TaskGroup`，不偷用全局线程池 |
| 有界优先 | `Executor`/`Semaphore`/`Pool` 都有显式上限，不提供无界队列 |
| 结果多读 | `Future` 可多读者；`Task.join` 仍是单消费者 |
| 关闭幂等 | `TaskGroup.close`、`Channel.close`、`Semaphore.close`、`Pool.close` 可重复调用 |
| 顺序一致 | Atomic 操作顺序一致；不承诺无锁/公平 |
| 明确边界 | 不承诺公平性、实时性、无饥饿 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Context` | class | 取消传播 | [`Context.md`](Context.md) |
| `TaskHandle` | protocol | 任务完成/取消/等待 | [`TaskHandle.md`](TaskHandle.md) |
| `Task` | class | 单消费者结果 | [`Task.md`](Task.md) |
| `TaskGroup` | class | 结构化任务组 | [`TaskGroup.md`](TaskGroup.md) |
| `Mutex` | class | 闭包式互斥 | [`Mutex.md`](Mutex.md) |
| `Channel` | class | 有界通道 | [`Channel.md`](Channel.md) |
| `AtomicInt` | class | 整数原子 | [`AtomicInt.md`](AtomicInt.md) |
| `AtomicBool` | class | 布尔原子 | [`AtomicBool.md`](AtomicBool.md) |
| `AtomicRef` | class | 引用原子 | [`AtomicRef.md`](AtomicRef.md) |
| `Executor` | class | 有界并发提交 | [`Executor.md`](Executor.md) |
| `Semaphore` | class | 许可计数 | [`Semaphore.md`](Semaphore.md) |
| `RwLock` | class | 读写锁 | [`RwLock.md`](RwLock.md) |
| `WaitGroup` | class | 等待计数 | [`WaitGroup.md`](WaitGroup.md) |
| `Once` | class | 只执行一次 | [`Once.md`](Once.md) |
| `Pool` | class | 通用对象池 | [`Pool.md`](Pool.md) |
| `Future` | class | 多读者结果 | [`Future.md`](Future.md) |
| `Promise` | class | 一次性完成 | [`Promise.md`](Promise.md) |

X 未纳入本批：`Timer`（归 `xdk.time`）、`Select`、`CancellationScope`、`Context` 值/截止时间、
`Barrier`、`Lazy`、`Broadcast`、`PubSub`、`Channel(0)` 会合通道、`trySend/tryReceive`、
`withLockResult`、任务错误聚合。

---

## 4. 顶层函数

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `isCancellation` | 是否取消错误 | `Error error` | `Bool` | null → panic |
| `cancelledError` | 构造取消错误 | `String operation` | `Error` | 无 |
| `timeoutError` | 构造超时错误 | `String operation` | `Error` | 无 |
| `unavailableError` | 构造不可用错误 | `String operation` | `Error` | 无 |

### 4.1 顶层函数伪代码

```xnull
Bool isCancellation(Error error) {
    if error == null { throw "isCancellation: null error" }
    return error.kind() == ErrorKind.Cancelled
}

Error cancelledError(String operation) {
    if operation == null { throw "cancelledError: null operation" }
    return new BasicError(ErrorKind.Cancelled, operation + " cancelled")
}

Error timeoutError(String operation) {
    if operation == null { throw "timeoutError: null operation" }
    return new BasicError(ErrorKind.Timeout, operation + " timed out")
}

Error unavailableError(String operation) {
    if operation == null { throw "unavailableError: null operation" }
    return new BasicError(ErrorKind.Unavailable, operation + " unavailable")
}
```

---

## 5. 技术/支撑/依赖

- 技术：取消令牌树、任务句柄、结构化 join、运行时监视器、有界队列、顺序一致原子。
- 依赖：`xdk.errors`、`xdk.runtime`。

运行时支撑原语（不是 XDK 公共类型）：

| 原语 | 用途 | 返回 | 失败/语义 |
| --- | --- | --- | --- |
| `RuntimeMonitor.enter/exit` | 进入/离开内部临界区 | `void` | 无；不可重入 |
| `RuntimeMonitor.wait()` | 等待通知 | `void` | 无；可能虚假唤醒，调用方循环 |
| `RuntimeMonitor.wait(Context)` | 可取消等待 | `Bool` | false = 已取消；true = 被通知/虚假唤醒 |
| `RuntimeMonitor.notifyAll()` | 唤醒全部等待者 | `void` | 无 |
| `spawnRaw(Context, Result<T,Error>(Context))` | 启动运行时任务 | `Result<TaskRuntimeHandle<T>, Error>` | `Unavailable`/`Io`；返回前不得同步执行 body |
| `TaskRuntimeHandle<T>.isDone/cancel/awaitDone` | 任务状态/取消/等待 | `Bool`/`void`/`void` | 无 |
| `TaskRuntimeHandle<T>.awaitDoneDeadline(Long)` | 截止等待 | `Result<Unit, Error>` | `Timeout` |
| `TaskRuntimeHandle<T>.result/failure` | 结果/失败 | `Result<T,Error>`/`Error?` | 未完成调用是合同错误 |
| 原子 load/store/CAS/add | 顺序一致原子操作 | 原值/`Bool`/新值 | 无；不承诺无锁 |


---

## 6. 场景

### E1：结构化子任务

`TaskGroup.create(ctx)`；`spawn` 两个子任务；`close` 取消、等待、返回首个非取消错误。

### E2：取消传播

父 `Context` 取消；组上下文与任务上下文通过 `isCancelled` 看到取消；任务返回 `Cancelled` 错误。

### E3：超时等待

`Task.joinDeadline(nowMono() + 100)`；超时返回 `Timeout`，任务继续，随后 `cancel` 或再 `join`。

### E4：生产者/消费者

`Channel(8)`；生产者 `send(ctx, value)`，消费者 `receive(ctx)`；关闭后收发返回 `Unavailable`，队列丢弃。

### E5：互斥更新

`Mutex<Counter>`；`withLock(ctx, (Counter c) -> { c.value = c.value + 1 })`；等待可取消。

### E6：原子计数

`AtomicInt.addAndGet` / `getAndAdd`；CAS 循环；`AtomicRef` 按引用身份 CAS。

### E7：有界并发

`Executor.fixed(ctx, 8)`；`submit` 在许可满时阻塞；任务体退出释放许可；`close` 取消并等待。

### E8：读写分离

`RwLock<Cache>`；并发 `withRead`；单个 `withWrite`；写者优先；取消等待。

### E9：初始化一次

`Once.do(ctx, () -> { loadConfig() })`；并发只执行一次；等待者取消不影响执行者。

### E10：请求结果多读

`Promise<Response>`；`complete/fail/cancel` 一次；`Future.get` 多读者；截止等待。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 全局执行器/线程池 | 不做；由运行时/调用方决定 |
| `Context` 值、截止时间 | X |
| `CancellationScope` | X |
| `Executor`/`Future`/`Promise` | 已设计（`preview`） |
| `Select` | X；需要时用 `Channel` + `TaskGroup` 组合 |
| `RwLock`/`Semaphore`/`WaitGroup`/`Once` | 已设计（`preview`） |
| `Barrier` | X；一次性场景用 `WaitGroup` |
| `Pool<T>` | 已设计（`preview`）；健康检查/空闲超时由上层组合 |
| `Timer` | 归 `xdk.time`；执行层不重复 |
| `Task.join` 并发/重复 | 单消费者；重复 join 合同错误 |
| `TaskGroup.close` 并发 | 线程安全；第二个 close 等待并返回同一结果 |
| 任务错误聚合 | X； 只保留首个非取消错误 |
| 忽略取消的任务 | close 可能一直等待；文档明确 |
| `Mutex` 重入 | 不支持；同任务重复加锁死锁 |
| `Mutex<T>` 的值类型 | T 应为引用类型；值类型场景 X |
| `Channel` 容量 0 | X； 要求 capacity ≥ 1 |
| `Channel.close` 队列 | 丢弃剩余元素；需要 drain 语义走 X |
| `Channel` 公平性 | 不承诺 |
| Atomic 顺序 | 顺序一致；不承诺无锁 |
| Atomic 溢出 | 按 `Int` 回绕 |
| 线程终止 | 不支持；取消是协作式 |
