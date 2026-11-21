# `Retry`

| 项 | 值 |
| --- | --- |
| 类型 | `class Retry` |
| 包 | `xdk.resilience` |
| 稳定性 | `preview` |
| 依赖 | `RetryPolicy`、`Context`、`RuntimeMonitor`、`Error` |

---

## 1. 定位

重试执行器：按 `RetryPolicy` 的次数/退避/抖动/错误分类重试同步操作，等待可取消。

不做：异步重试、后台调度、hedging、分布式重试、指标导出、按错误码细分（X）。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `execute` 使用确定性退避 `delayFor`；`executeWith` 使用抖动退避和自定义可重试谓词。
- 首次失败后 `attempt=1`；`RetryPolicy.shouldRetry` 判断是否继续并隐含最大次数。
- 取消错误永不重试；`Context` 取消立即返回 `Cancelled`。
- 等待使用局部 `RuntimeMonitor.waitDeadline` 作为可取消睡眠；不持有全局定时器。
- 原错误保留：不重试或次数耗尽时返回最后一次错误。
- 线程安全；无全局状态；无 close。

---

## 3. 表示与不变量

无实例字段。

不变量：attempt ≥1；不重试取消；等待不持有调用方锁；总尝试次数不超过 policy 上限；返回值是最后一次操作结果或取消错误。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Retry()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `execute<T>` | 确定性退避重试 | `Context, RetryPolicy, Result<T,Error>() operation` | `Result<T, Error>` | 最后错误/`Cancelled` |
| `executeWith<T>` | 抖动+谓词重试 | `Context, RetryPolicy, Double() randomUnit, Result<T,Error>() operation, Bool(Error) isRetryable` | `Result<T, Error>` | 最后错误/`Cancelled` |

说明：

- `execute` 的延迟 = `policy.delayFor(attempt)`，无抖动。
- `executeWith` 的延迟 = `policy.delayForJittered(attempt, randomUnit())`；`randomUnit` 必须返回 `[0,1]`，否则 policy panic。
- `isRetryable` 在 `policy.shouldRetry` 之前判断；返回 false 表示不再重试。
- 操作返回 `Cancelled` 时无论谓词如何都停止。
- `Context` 在等待前/等待中取消返回 `Cancelled`，不继续操作。
- `sleepCancellable` 是私有辅助，不对外。

---

## 8. 使用的技术

- 指数退避/抖动；
- 可取消等待；
- 错误分类；
- 同步循环；
- 监视器截止等待。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Double、Bool、Result、Unit、泛型方法、函数类型；
- 运行时：`RuntimeMonitor.enter/exit/waitDeadline`、`nowMono`；
- 接口：`Context`、`RetryPolicy`、`Error`、`isCancellation`、`cancelledError`。

---

## 10. 依赖的特性/接口/类

`RetryPolicy`、`Context`、`RuntimeMonitor`、`Error`、`nowMono`、错误辅助函数。

---

## 11. 所有权与并发

无状态；可并发；`RetryPolicy` 不可变可共享；`randomUnit` 由调用方保证线程安全；无资源。

---

## 12. 示例与反例

正确：`Retry.execute(ctx, policy, () -> call())`。  
反例：重试取消错误；在持有锁时 sleep；用无上限 policy；随机源返回 1.5；忽略最后错误。

---

## 13. 测试/场景义务

一次成功；多次失败后成功；次数耗尽；不可重试分类；自定义谓词；取消错误；等待中取消；零/负延迟；抖动边界；最大次数 1；错误保留；并发调用。

---

## 14. XNull 伪代码

```xnull
class Retry {
    private Retry() {
    }

    static Result<T, Error> execute<T>(Context context, RetryPolicy policy,
                                       Result<T, Error>() operation) {
        if context == null || policy == null || operation == null {
            throw "Retry.execute: null argument"
        }
        Int attempt = 1
        while true {
            if context.isCancelled() {
                return Err(cancelledError("retry execute"))
            }
            Result<T, Error> result = operation()
            if result.isOk() { return result }
            Error error = result.error()
            if isCancellation(error) { return result }
            if !policy.shouldRetry(error, attempt) { return result }
            Long delay = policy.delayFor(attempt)
            if !Retry.sleepCancellable(context, delay) {
                return Err(cancelledError("retry sleep"))
            }
            attempt = attempt + 1
        }
    }

    static Result<T, Error> executeWith<T>(Context context, RetryPolicy policy,
                                           Double() randomUnit,
                                           Result<T, Error>() operation,
                                           Bool(Error) isRetryable) {
        if context == null || policy == null || randomUnit == null {
            throw "Retry.executeWith: null argument"
        }
        if operation == null || isRetryable == null {
            throw "Retry.executeWith: null function"
        }
        Int attempt = 1
        while true {
            if context.isCancelled() {
                return Err(cancelledError("retry execute"))
            }
            Result<T, Error> result = operation()
            if result.isOk() { return result }
            Error error = result.error()
            if isCancellation(error) { return result }
            if !isRetryable(error) { return result }
            if !policy.shouldRetry(error, attempt) { return result }
            Double unit = randomUnit()
            Long delay = policy.delayForJittered(attempt, unit)
            if !Retry.sleepCancellable(context, delay) {
                return Err(cancelledError("retry sleep"))
            }
            attempt = attempt + 1
        }
    }

    private static Bool sleepCancellable(Context context, Long millis) {
        if millis <= 0 { return !context.isCancelled() }
        RuntimeMonitor monitor = new RuntimeMonitor()
        monitor.enter()
        Int state = monitor.waitDeadline(context, nowMono() + millis)
        monitor.exit()
        return state != 1
    }
}
```
