# `Timeout`

| 项 | 值 |
| --- | --- |
| 类型 | `class Timeout` |
| 包 | `xdk.resilience` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`TaskGroup`、`Task`、`Error` |

---

## 1. 定位

任务级超时：在单独任务中执行操作，按单调截止等待；超时取消任务并返回 `Timeout`。

不做：异步返回句柄、超时不取消、硬杀线程、嵌套超时策略、服务端请求超时（由 `net.http` 处理）。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `timeoutMillis` 必须 >0；从调用时刻起算单调毫秒。
- 使用 `TaskGroup` 创建结构化子任务；`joinDeadline` 等待结果。
- 超时后 `group.close()` 取消并等待任务结束；操作应检查 `Context.isCancelled()`。
- 若操作忽略取消，`Timeout.execute` 可能超过 `timeoutMillis` 才返回；这是协作取消边界。
- `timeoutMillis` 是结果截止；不保证总延迟严格等于该值。
- 不吞任务错误：非超时错误原样返回。
- 线程安全；无全局状态。

---

## 3. 表示与不变量

无实例字段。

不变量：`timeoutMillis > 0`；任务属于本次调用创建的组；返回后组已 close；超时返回 `Timeout`。

---

## 4. 生命周期

静态命名空间；每次调用创建/关闭任务组；无 close 资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Timeout()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `execute<T>` | 超时执行 | `Context parent, Long timeoutMillis, Result<T,Error>(Context) operation` | `Result<T, Error>` | `Timeout`/父取消/操作错误/`InvalidArgument` |

说明：

- `timeoutMillis <= 0` 返回 `InvalidArgument`，不启动任务。
- 父上下文取消时返回 `Cancelled`，不返回 `Timeout`。
- `joinDeadline` 超时后 `group.close()` 先取消再等待；操作忽略取消时可能阻塞。
- `group.close()` 的错误不覆盖已取得的操作结果；超时场景统一返回 `Timeout`。
- 只支持同步结果；需要异步句柄用 `Task`/`TaskGroup`。

---

## 8. 使用的技术

- 结构化并发；
- 单调截止；
- 取消传播；
- 任务组关闭；
- 错误分类。

---

## 9. 需要的支撑

- 语言：class、Long、Bool、Result、泛型方法、函数类型；
- 运行时：`nowMono`；
- 接口：`Context`、`TaskGroup`、`Task`、`Error`、`BasicError`、`ErrorKind`、`timeoutError`。

---

## 10. 依赖的特性/接口/类

`Context`、`TaskGroup`、`Task`、`Error`、`nowMono`、`timeoutError`。

---

## 11. 所有权与并发

无状态；每次调用独立任务组；可并发；父上下文可共享；无资源泄漏（close 等待）。

---

## 12. 示例与反例

正确：`Timeout.execute(ctx, 3000, (Context c) -> call(c))`。  
反例：超时后认为线程已停止；operation 不检查取消；timeout=0；用 Timeout 包裹无限重试；忽略父取消。

---

## 13. 测试/场景义务

立即完成；超时；父取消；操作错误；取消错误；timeout 边界；operation 忽略取消（阻塞语义）；close 清理；并发调用；嵌套 Timeout。

---

## 14. XNull 伪代码

```xnull
class Timeout {
    private Timeout() {
    }

    static Result<T, Error> execute<T>(Context parent, Long timeoutMillis,
                                       Result<T, Error>(Context) operation) {
        if parent == null || operation == null {
            throw "Timeout.execute: null argument"
        }
        if timeoutMillis <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "timeout must be positive"))
        }
        TaskGroup group = TaskGroup.create(parent)
        Result<Task<T>, Error> spawned = group.spawn(operation)
        if spawned.isErr() {
            group.close()
            return Err(spawned.error())
        }
        Long deadline = nowMono() + timeoutMillis
        Result<T, Error> result = spawned.value().joinDeadline(deadline)
        group.close()
        if result.isErr() && result.error().kind() == ErrorKind.Timeout {
            return Err(timeoutError("timeout"))
        }
        return result
    }
}
```
