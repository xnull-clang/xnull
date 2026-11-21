# `CircuitBreaker`

| 项 | 值 |
| --- | --- |
| 类型 | `class CircuitBreaker` |
| 包 | `xdk.resilience` |
| 稳定性 | `preview` |
| 依赖 | `CircuitState`、`Context`、`RuntimeMonitor`、`Error` |

---

## 1. 定位

进程内熔断器：失败阈值、打开时长、半开探测并发上限、成功/失败记录、手动复位/熔断。

不做：分布式熔断、跨进程状态、自适应阈值、指标导出、按错误码细分窗口。

---

## 2. 设计逻辑

- 字段：阈值、打开毫秒、半开并发上限、状态、失败计数、打开时刻、半开在途数、监视器。
- `tryAcquire` 是唯一放行入口：Closed 放行；Open 未到期快速失败；到期惰性转 HalfOpen；HalfOpen 限制在途探测数。
- `recordSuccess`：Closed 清零失败；HalfOpen 回 Closed。
- `recordFailure`：Closed 达阈值转 Open；HalfOpen 立即回 Open。
- `execute` 组合 acquire + operation + record；operation 用 `Result` 表达失败。
- 取消不记为失败；半开槽位释放，状态不变。
- 时间用 `nowMono`；Open→HalfOpen 不依赖后台定时器，由下一次请求触发。
- 线程安全；`RuntimeMonitor` 保护全部状态；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_failureThreshold` | `Int` | ≥1 |
| `_openMillis` | `Long` | ≥1 |
| `_halfOpenMaxCalls` | `Int` | ≥1 |
| `_monitor` | `RuntimeMonitor` | 状态保护 |
| `_state` | `CircuitState` | 当前状态 |
| `_failureCount` | `Int` | 0..阈值 |
| `_openedAtMono` | `Long` | Open 起始单调毫秒 |
| `_halfOpenInFlight` | `Int` | 0..半开上限 |

不变量：阈值/时长/半开上限 ≥1；Closed 时 `_openedAtMono` 无意义；HalfOpen 在途数不超过上限；状态只按定义迁移。

---

## 4. 生命周期

构造后长期使用；无 close；状态可 `reset`；跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CircuitBreaker(Int failureThreshold, Long openMillis, Int halfOpenMaxCalls)` | 全部 | 均 ≥1 | 非法 → panic |
| `CircuitBreaker(Int failureThreshold)` | threshold | ≥1 | 非法 → panic；默认 30s/1 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `execute<T>` | 放行并执行 | `Context, Result<T,Error>() operation` | `Result<T, Error>` | `Unavailable`/`Cancelled`/操作错误 |
| `tryAcquire` | 申请放行 | `Context` | `Result<Unit, Error>` | `Unavailable`/`Cancelled` |
| `recordSuccess` | 记录成功 | 无 | `void` | 无 |
| `recordFailure` | 记录失败 | 无 | `void` | 无 |
| `state` | 当前状态 | 无 | `CircuitState` | 无 |
| `failureCount` | 当前失败数 | 无 | `Int` | 无 |
| `failureThreshold` | 阈值 | 无 | `Int` | 无 |
| `openMillis` | 打开时长 | 无 | `Long` | 无 |
| `halfOpenMaxCalls` | 半开上限 | 无 | `Int` | 无 |
| `reset` | 强制关闭 | 无 | `void` | 无 |
| `trip` | 强制打开 | 无 | `void` | 无 |

说明：

- `tryAcquire` 在 Open 未到期返回 `Unavailable`；到期转 HalfOpen 并占用一个探测槽。
- `recordSuccess`/`recordFailure` 对 Open 状态的迟到结果忽略（成功）或保持 Open（失败）。
- `execute` 遇到操作返回 `Cancelled` 时释放半开槽，不增加失败计数。
- `execute` 的 operation 若抛出致命异常，不记录结果；半开槽可能保持占用，需 `reset`。operation 应使用 `Result`。
- `reset` 立即 Closed、清零；`trip` 立即 Open、失败数置为阈值。

---

## 8. 使用的技术

- 三态状态机；
- 单调时钟；
- 失败计数；
- 半开并发限制；
- 运行时监视器；
- 取消感知。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool、Result、Unit、泛型方法；
- 运行时：`RuntimeMonitor.enter/exit/notifyAll`、`nowMono`；
- 接口：`Context`、`CircuitState`、`Error`、`isCancellation`、`cancelledError`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`CircuitState`、`Context`、`RuntimeMonitor`、`Error`、`nowMono`、错误辅助函数。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；`execute` 可并发；`reset`/`trip` 与请求并发安全；无资源。

---

## 12. 示例与反例

正确：阈值 5、30s、半开 2；失败 5 次后快速失败；30s 后放行 2 个探测。  
反例：取消也计失败；Open 时继续打后端；半开放行无限并发；期望 Open 自动切回；在 operation 抛异常后期望计数准确。

---

## 13. 测试/场景义务

Closed 成功/失败；阈值边界；Open 快速失败；到期半开；半开并发上限；半开成功/失败/取消；迟到结果；reset/trip；并发竞争；时间边界；参数非法。

---

## 14. XNull 伪代码

```xnull
class CircuitBreaker {
    final Int _failureThreshold
    final Long _openMillis
    final Int _halfOpenMaxCalls
    final RuntimeMonitor _monitor
    CircuitState _state = CircuitState.Closed
    Int _failureCount = 0
    Long _openedAtMono = 0
    Int _halfOpenInFlight = 0

    CircuitBreaker(Int failureThreshold, Long openMillis, Int halfOpenMaxCalls) {
        if failureThreshold < 1 || openMillis < 1 || halfOpenMaxCalls < 1 {
            throw "CircuitBreaker: invalid configuration"
        }
        _failureThreshold = failureThreshold
        _openMillis = openMillis
        _halfOpenMaxCalls = halfOpenMaxCalls
        _monitor = new RuntimeMonitor()
    }

    CircuitBreaker(Int failureThreshold) {
        if failureThreshold < 1 { throw "CircuitBreaker: invalid threshold" }
        _failureThreshold = failureThreshold
        _openMillis = 30000
        _halfOpenMaxCalls = 1
        _monitor = new RuntimeMonitor()
    }

    Result<T, Error> execute<T>(Context context, Result<T, Error>() operation) {
        if context == null || operation == null {
            throw "CircuitBreaker.execute: null argument"
        }
        Result<Unit, Error> permit = self.tryAcquire(context)
        if permit.isErr() { return Err(permit.error()) }
        Result<T, Error> result = operation()
        if result.isOk() {
            self.recordSuccess()
            return result
        }
        Error error = result.error()
        if isCancellation(error) {
            self.releaseHalfOpenSlot()
        } else {
            self.recordFailure()
        }
        return result
    }

    Result<Unit, Error> tryAcquire(Context context) {
        if context == null { throw "CircuitBreaker.tryAcquire: null context" }
        _monitor.enter()
        if context.isCancelled() {
            _monitor.exit()
            return Err(cancelledError("circuit breaker acquire"))
        }
        if _state == CircuitState.Open {
            Long now = nowMono()
            if now - _openedAtMono >= _openMillis {
                _state = CircuitState.HalfOpen
                _failureCount = 0
                _halfOpenInFlight = 0
            } else {
                _monitor.exit()
                return Err(unavailableError("circuit breaker is open"))
            }
        }
        if _state == CircuitState.HalfOpen {
            if _halfOpenInFlight >= _halfOpenMaxCalls {
                _monitor.exit()
                return Err(unavailableError("circuit breaker half-open is busy"))
            }
            _halfOpenInFlight = _halfOpenInFlight + 1
        }
        _monitor.exit()
        return Ok(unit)
    }

    void recordSuccess() {
        _monitor.enter()
        if _state == CircuitState.HalfOpen {
            _state = CircuitState.Closed
            _failureCount = 0
            _halfOpenInFlight = 0
            _monitor.notifyAll()
        } else if _state == CircuitState.Closed {
            _failureCount = 0
        }
        _monitor.exit()
    }

    void recordFailure() {
        _monitor.enter()
        if _state == CircuitState.HalfOpen {
            _state = CircuitState.Open
            _openedAtMono = nowMono()
            _failureCount = _failureThreshold
            _halfOpenInFlight = 0
            _monitor.notifyAll()
        } else if _state == CircuitState.Closed {
            _failureCount = _failureCount + 1
            if _failureCount >= _failureThreshold {
                _state = CircuitState.Open
                _openedAtMono = nowMono()
                _monitor.notifyAll()
            }
        }
        _monitor.exit()
    }

    void releaseHalfOpenSlot() {
        _monitor.enter()
        if _state == CircuitState.HalfOpen && _halfOpenInFlight > 0 {
            _halfOpenInFlight = _halfOpenInFlight - 1
        }
        _monitor.exit()
    }

    CircuitState state() {
        _monitor.enter()
        CircuitState result = _state
        _monitor.exit()
        return result
    }

    Int failureCount() {
        _monitor.enter()
        Int result = _failureCount
        _monitor.exit()
        return result
    }

    Int failureThreshold() { return _failureThreshold }
    Long openMillis() { return _openMillis }
    Int halfOpenMaxCalls() { return _halfOpenMaxCalls }

    void reset() {
        _monitor.enter()
        _state = CircuitState.Closed
        _failureCount = 0
        _openedAtMono = 0
        _halfOpenInFlight = 0
        _monitor.notifyAll()
        _monitor.exit()
    }

    void trip() {
        _monitor.enter()
        _state = CircuitState.Open
        _openedAtMono = nowMono()
        _failureCount = _failureThreshold
        _halfOpenInFlight = 0
        _monitor.notifyAll()
        _monitor.exit()
    }
}
```
