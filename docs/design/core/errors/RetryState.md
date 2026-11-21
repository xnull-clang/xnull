# `RetryState`

| 项 | 值 |
| --- | --- |
| 类型 | `class RetryState` |
| 包 | `xdk.errors` |
| 稳定性 | `preview` |
| 依赖 | `RetryPolicy`、`BasicError` |

---

## 1. 定位

一次重试过程的可变状态：已失败次数、最后错误、下一次延迟、是否停止。

不做：休眠、循环、日志、调度。

---

## 2. 设计逻辑

- `RetryPolicy` 是不可变配置；`RetryState` 是可变运行状态。
- 一次重试过程一个实例，避免并发共享。
- `shouldContinue`/`nextDelay` 都记录一次失败；同一轮只能调用一个。
- 停止后不再重试；`reset` 可复用。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_policy` | `RetryPolicy` | final | 非空 |
| `_attempt` | `Int` | 可变 | 0..maxAttempts |
| `_lastError` | `BasicError?` | 可变 | 最后错误 |
| `_nextDelayMillis` | `Long` | 可变 | ≥0 |
| `_stopped` | `Bool` | 可变 | 停止标志 |

不变量：attempt ≥0；attempt ≤ policy.maxAttempts；nextDelay ≥0；stopped 后不再重试。

---

## 4. 生命周期

- 构造后随重试过程变化；无 close；非线程安全。
- 一次重试过程一个实例；跨任务共享需外部同步。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `RetryState(RetryPolicy policy)` | policy | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `attempt` | 已失败次数 | 无 | `Int` | 无 |
| `lastError` | 最后错误 | 无 | `BasicError?` | 无 |
| `nextDelayMillis` | 下次延迟 | 无 | `Long` | 无 |
| `isStopped` | 是否停止 | 无 | `Bool` | 无 |
| `shouldContinue` | 记录失败并判断 | `BasicError error` | `Bool` | null → panic |
| `nextDelay` | 记录失败并取延迟 | `BasicError error` | `Long` | null → panic |
| `reset` | 重置 | 无 | `void` | 无 |
| `describe` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 可变状态机；
- 指数退避委托给 `RetryPolicy`；
- 停止标志；
- 错误链引用。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool、String；
- 运行时：无；
- 接口：`RetryPolicy`、`BasicError`。

---

## 10. 依赖的特性/接口/类

`RetryPolicy`、`BasicError`。

---

## 11. 所有权与并发

- 可变；非线程安全。
- `lastError` 借用不可变错误。
- 无资源、无 close。

---

## 12. 示例与反例

正确：循环中每轮失败调用一次 `nextDelay`；返回 0 时停止；成功则 `reset`。  
反例：同一轮同时调 `shouldContinue` 和 `nextDelay` → attempt 加两次；多任务共享不加锁 → 数据竞争。

---

## 13. 测试/场景义务

初始状态；递增；可重试/不可重试；耗尽；reset；describe；取消不重试。

---

## 14. XNull 伪代码

```xnull
class RetryState {
    RetryPolicy _policy
    Int _attempt = 0
    BasicError? _lastError = null
    Long _nextDelayMillis = 0
    Bool _stopped = false

    RetryState(RetryPolicy policy) {
        if policy == null {
            throw "RetryState: null policy"
        }
        _policy = policy
    }

    Int attempt() { return _attempt }
    BasicError? lastError() { return _lastError }
    Long nextDelayMillis() { return _nextDelayMillis }
    Bool isStopped() { return _stopped }

    Bool shouldContinue(BasicError error) {
        if error == null {
            throw "RetryState.shouldContinue: null error"
        }
        _lastError = error
        if _stopped {
            return false
        }
        if !_policy.shouldRetry(error, _attempt + 1) {
            _stopped = true
            _nextDelayMillis = 0
            return false
        }
        _attempt = _attempt + 1
        _nextDelayMillis = _policy.delayFor(_attempt)
        return true
    }

    Long nextDelay(BasicError error) {
        if self.shouldContinue(error) {
            return _nextDelayMillis
        }
        return 0
    }

    void reset() {
        _attempt = 0
        _lastError = null
        _nextDelayMillis = 0
        _stopped = false
    }

    String describe() {
        return "attempt=" + str(_attempt)
            + " stopped=" + str(_stopped)
            + " nextDelay=" + str(_nextDelayMillis) + "ms"
    }
}
```
