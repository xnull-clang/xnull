# `RetryPolicy`

| 项 | 值 |
| --- | --- |
| 类型 | `class RetryPolicy` |
| 包 | `xdk.errors` |
| 稳定性 | `preview` |
| 依赖 | `ErrorKind`、`Error` |

---

## 1. 定位

不可变重试策略：最大次数、初始/最大延迟、倍数、抖动、可重试分类。

只做决策，不做休眠、不循环、不调度、不日志。

---

## 2. 设计逻辑

- 不依赖 `time.Duration`，用 `Long` 毫秒，避免 `errors -> time -> errors`。
- 不可变，可共享/缓存。
- 抖动需要随机数，但 errors 不依赖 random；由调用方传 `[0,1)` 随机值。
- 实际重试循环/休眠由调用方或 `xdk.utils` 执行。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_maxAttempts` | `Int` | final | ≥1 |
| `_initialDelayMillis` | `Long` | final | ≥0 |
| `_maxDelayMillis` | `Long` | final | ≥initial |
| `_multiplier` | `Double` | final | ≥1.0 |
| `_jitter` | `Double` | final | 0.0..1.0 |
| `_retryOn` | `List<ErrorKind>` | final | 去重分类 |

不变量：maxAttempts ≥1；initial ≥0；max ≥ initial；multiplier ≥1；jitter ∈ [0,1]；retryOn 非 null、无重复。

---

## 4. 生命周期

- 构造后不可变；无 close；可跨任务共享。
- `with*` 返回新实例。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `RetryPolicy()` | 无 | 默认 3 次/100ms/5000ms/2.0/0.1/四类 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxAttempts` | 最大次数 | 无 | `Int` | 无 |
| `initialDelayMillis` | 初始延迟 | 无 | `Long` | 无 |
| `maxDelayMillis` | 最大延迟 | 无 | `Long` | 无 |
| `multiplier` | 倍数 | 无 | `Double` | 无 |
| `jitter` | 抖动 | 无 | `Double` | 无 |
| `retryOn` | 分类快照 | 无 | `List<ErrorKind>` | 无 |
| `withMaxAttempts` | 派生 | `Int count` ≥1 | `RetryPolicy` | 非法 → panic |
| `withInitialDelayMillis` | 派生 | `Long` ≥0 | `RetryPolicy` | 非法 → panic |
| `withMaxDelayMillis` | 派生 | `Long` ≥initial | `RetryPolicy` | 非法 → panic |
| `withMultiplier` | 派生 | `Double` ≥1.0 | `RetryPolicy` | 非法 → panic |
| `withJitter` | 派生 | `Double` 0..1 | `RetryPolicy` | 非法 → panic |
| `withRetryOn` | 派生 | `List<ErrorKind>` | `RetryPolicy` | null → panic |
| `shouldRetry` | 是否重试 | `Error error`、`Int attempt` | `Bool` | null/attempt<1 → panic |
| `delayFor` | 确定性延迟 | `Int attempt` | `Long` | attempt<1 → panic |
| `delayForJittered` | 抖动延迟 | `Int attempt`、`Double randomUnit` | `Long` | 非法 → panic |
| `copy` | 复制 | 无 | `RetryPolicy` | 无 |
| `describe` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 指数退避；
- 上限钳制；
- 去重分类；
- 随机值注入（不内置随机源）。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Double、Bool、List、String；
- 运行时：无；
- 接口：`ErrorKind`、`Error`。

---

## 10. 依赖的特性/接口/类

`ErrorKind`、`Error`。

---

## 11. 所有权与并发

- 不可变；可跨任务共享。
- `retryOn()` 返回快照。
- 无资源、无 close。

---

## 12. 示例与反例

正确：默认策略第 1 次失败等 100ms、第 2 次等 200ms、第 3 次不再重试。  
反例：attempt=0 → panic；retryOn 为空 → 永不重试；在 errors 里 sleep → 越界。

---

## 13. 测试/场景义务

默认值；每个 `with*`；非法参数；可重试/不可重试；延迟指数/上限；抖动范围；复制独立性。

---

## 14. XNull 伪代码

```xnull
class RetryPolicy {
    Int _maxAttempts = 3
    Long _initialDelayMillis = 100
    Long _maxDelayMillis = 5000
    Double _multiplier = 2.0
    Double _jitter = 0.1
    List<ErrorKind> _retryOn = [ErrorKind.Network, ErrorKind.Timeout, ErrorKind.Busy, ErrorKind.Unavailable]

    RetryPolicy() {
    }

    Int maxAttempts() { return _maxAttempts }
    Long initialDelayMillis() { return _initialDelayMillis }
    Long maxDelayMillis() { return _maxDelayMillis }
    Double multiplier() { return _multiplier }
    Double jitter() { return _jitter }

    List<ErrorKind> retryOn() {
        List<ErrorKind> result = []
        Int index = 0
        while index < _retryOn.length() {
            result.push(_retryOn.get(index))
            index = index + 1
        }
        return result
    }

    RetryPolicy withMaxAttempts(Int count) {
        if count < 1 {
            throw "RetryPolicy.withMaxAttempts: count < 1"
        }
        RetryPolicy result = self.copy()
        result._maxAttempts = count
        return result
    }

    RetryPolicy withInitialDelayMillis(Long milliseconds) {
        if milliseconds < 0 {
            throw "RetryPolicy.withInitialDelayMillis: negative"
        }
        RetryPolicy result = self.copy()
        result._initialDelayMillis = milliseconds
        return result
    }

    RetryPolicy withMaxDelayMillis(Long milliseconds) {
        if milliseconds < _initialDelayMillis {
            throw "RetryPolicy.withMaxDelayMillis: max < initial"
        }
        RetryPolicy result = self.copy()
        result._maxDelayMillis = milliseconds
        return result
    }

    RetryPolicy withMultiplier(Double factor) {
        if factor < 1.0 {
            throw "RetryPolicy.withMultiplier: factor < 1"
        }
        RetryPolicy result = self.copy()
        result._multiplier = factor
        return result
    }

    RetryPolicy withJitter(Double ratio) {
        if ratio < 0.0 || ratio > 1.0 {
            throw "RetryPolicy.withJitter: out of range"
        }
        RetryPolicy result = self.copy()
        result._jitter = ratio
        return result
    }

    RetryPolicy withRetryOn(List<ErrorKind> kinds) {
        RetryPolicy result = self.copy()
        result._retryOn = []
        Int index = 0
        while index < kinds.length() {
            ErrorKind kind = kinds.get(index)
            if !result._retryOn.contains(kind) {
                result._retryOn.push(kind)
            }
            index = index + 1
        }
        return result
    }

    Bool shouldRetry(Error error, Int attempt) {
        if error == null {
            throw "RetryPolicy.shouldRetry: null error"
        }
        if attempt < 1 {
            throw "RetryPolicy.shouldRetry: attempt < 1"
        }
        if attempt >= _maxAttempts {
            return false
        }
        return _retryOn.contains(error.kind())
    }

    Long delayFor(Int attempt) {
        if attempt < 1 {
            throw "RetryPolicy.delayFor: attempt < 1"
        }
        Long delay = _initialDelayMillis
        Int index = 1
        while index < attempt {
            delay = delay * _multiplier
            if delay >= _maxDelayMillis {
                return _maxDelayMillis
            }
            index = index + 1
        }
        return delay
    }

    Long delayForJittered(Int attempt, Double randomUnit) {
        if randomUnit < 0.0 || randomUnit > 1.0 {
            throw "RetryPolicy.delayForJittered: randomUnit out of range"
        }
        Long base = self.delayFor(attempt)
        Double factor = 1.0 - _jitter + 2.0 * _jitter * randomUnit
        Long value = (base * factor) as Long
        if value < 0 {
            return 0
        }
        if value > _maxDelayMillis {
            return _maxDelayMillis
        }
        return value
    }

    RetryPolicy copy() {
        RetryPolicy result = new RetryPolicy()
        result._maxAttempts = _maxAttempts
        result._initialDelayMillis = _initialDelayMillis
        result._maxDelayMillis = _maxDelayMillis
        result._multiplier = _multiplier
        result._jitter = _jitter
        result._retryOn = self.retryOn()
        return result
    }

    String describe() {
        return "retry max=" + str(_maxAttempts)
            + " initial=" + str(_initialDelayMillis) + "ms"
            + " max=" + str(_maxDelayMillis) + "ms"
            + " multiplier=" + str(_multiplier)
            + " jitter=" + str(_jitter)
    }
}
```
