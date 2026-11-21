# `Future<T>`

| 项 | 值 |
| --- | --- |
| 类型 | `class Future<T>` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Promise<T>`、`Context`、`Error` |

---

## 1. 定位

一次性结果的只读视图：多个读者等待同一个完成值；支持取消与截止等待。

不做：写入结果（`Promise`）、任务调度、结果消费、重试、流式多值。

---

## 2. 设计逻辑

- `Future<T>` 持有 `Promise<T>`；状态由 Promise 管理。
- 通常通过 `Promise.future()` 获取；公共构造器只用于共享/包装。
- `get` 等待完成；成功返回值，失败返回错误；多个读者可同时等待。
- `getDeadline` 超时返回 `Timeout`，不取消 Promise；结果仍可稍后读取。
- `isDone`/`isCancelled` 不阻塞。
- 无 close；无资源；结果按值/引用语义由 T 决定。
- 不消费结果；与 `Task.join` 的单消费者语义不同。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_promise` | `Promise<T>` | 非 null；共享状态 |

不变量：promise 非 null；Future 不修改 promise；完成后状态不再变化。

---

## 4. 生命周期

由 `Promise.future()` 或构造器创建；无 close；Promise 完成后仍可读取。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Future(Promise<T> promise)` | promise | 非 null | null → panic |

业务代码优先使用 `Promise.future()`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `get` | 等待结果 | `Context context` | `Result<T, Error>` | `Cancelled`；Promise 错误；null → panic |
| `getDeadline` | 截止等待 | `Context context, Long deadlineMonoMillis` | `Result<T, Error>` | `Timeout`/`Cancelled`；Promise 错误 |
| `isDone` | 是否完成 | 无 | `Bool` | 无 |
| `isCancelled` | 是否取消 | 无 | `Bool` | 无 |

说明：

- `get` 不消费；可多次调用/多读者。
- `getDeadline` 的 deadline 是单调毫秒；超时不取消。
- 已完成时 `getDeadline` 立即返回结果，即使 deadline 已过。
- `isCancelled` 等价于失败错误 `kind() == Cancelled`。

---

## 8. 使用的技术

- 一次性状态共享；
- 多读者等待；
- 截止等待；
- Result。

---

## 9. 需要的支撑

- 语言：class、泛型、Bool、Long、Result；
- 运行时：`Promise` 的等待/截止原语；
- 接口：`Promise`、`Context`、`Error`、`cancelledError`。

---

## 10. 依赖的特性/接口/类

`Promise<T>`、`Context`、`Error`。

---

## 11. 所有权与并发

引用语义；线程安全；可多读者；不消费；无资源；无取消写入。
相等：引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
Promise<Int> promise = new Promise<Int>()
Future<Int> future = promise.future()
promise.complete(42)
Result<Int, Error> value = future.get(ctx)
```

反例：Future 上调用 complete；把 Future 当 Task 只允许一个读者；超时后认为 Promise 已取消；
重复等待期望值变化。

---

## 13. 测试/场景义务

完成/失败/取消；多读者；截止超时/已完成；取消等待者；isDone/isCancelled；
值类型/引用类型 T；并发完成/读取；不消费。

---

## 14. XNull 伪代码

```xnull
class Future<T> {
    final Promise<T> _promise

    Future(Promise<T> promise) {
        if promise == null { throw "Future: null promise" }
        _promise = promise
    }

    Result<T, Error> get(Context context) {
        if context == null { throw "Future.get: null context" }
        return _promise.await(context)
    }

    Result<T, Error> getDeadline(Context context, Long deadlineMonoMillis) {
        if context == null { throw "Future.getDeadline: null context" }
        return _promise.awaitDeadline(context, deadlineMonoMillis)
    }

    Bool isDone() {
        return _promise.isDone()
    }

    Bool isCancelled() {
        return _promise.isCancelled()
    }
}
```
