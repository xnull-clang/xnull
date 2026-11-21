# `RateLimiter`

| 项 | 值 |
| --- | --- |
| 类型 | `class RateLimiter` |
| 包 | `xdk.resilience` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`RuntimeMonitor`、`Error` |

---

## 1. 定位

进程内令牌桶限流：按每秒许可数补充令牌，支持突发容量、阻塞获取、非阻塞尝试。

不做：分布式限流、跨进程配额、公平排队、优先级、滑动日志精确限流。

---

## 2. 设计逻辑

- 字段：速率、桶容量、当前令牌、上次补充单调时间、监视器。
- 令牌按 `nowMono` 流逝时间补充，最多补到容量；不累积超过容量。
- `acquireMany` 在令牌不足时按缺口计算等待毫秒，使用 `waitDeadline` 可取消等待；超时后重新检查。
- `tryAcquireMany` 非阻塞；不足立即返回 false。
- 单次 `permits` 大于桶容量永远无法满足，返回 `InvalidArgument`。
- 不承诺 FIFO；并发等待者按唤醒/调度竞争。
- 线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_permitsPerSecond` | `Double` | >0 |
| `_capacity` | `Double` | ≥1 |
| `_monitor` | `RuntimeMonitor` | 保护令牌 |
| `_tokens` | `Double` | 0..capacity |
| `_lastRefillMono` | `Long` | 上次补充单调毫秒 |

不变量：`0 <= _tokens <= _capacity`；速率/容量有限且为正；等待不持有监视器；取消不消耗令牌。

---

## 4. 生命周期

构造后长期使用；无 close；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `RateLimiter(Double permitsPerSecond, Double burstCapacity)` | rate/capacity | rate>0；capacity≥1 | 非法 → panic |
| `RateLimiter(Double permitsPerSecond)` | rate | >0 | 非法 → panic；容量默认 1 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `acquire` | 获取 1 个许可 | `Context` | `Result<Unit, Error>` | `Cancelled`/`InvalidArgument` |
| `acquireMany` | 获取 n 个许可 | `Context, Int permits` | `Result<Unit, Error>` | 同上 |
| `tryAcquire` | 非阻塞 1 个 | 无 | `Bool` | 无 |
| `tryAcquireMany` | 非阻塞 n 个 | `Int permits` | `Bool` | 无 |
| `availablePermits` | 当前令牌 | 无 | `Double` | 无 |
| `permitsPerSecond` | 速率 | 无 | `Double` | 无 |
| `burstCapacity` | 桶容量 | 无 | `Double` | 无 |

说明：

- `permits < 1` 是合同错误（panic）；`permits > capacity` 返回 `InvalidArgument`。
- 等待时间至少 1ms，避免忙循环。
- `availablePermits` 先补充再读数；读数是瞬时快照。
- 取消时令牌保持不变；已消耗的令牌不退回。

---

## 8. 使用的技术

- 令牌桶；
- 单调时钟；
- 可取消截止等待；
- 监视器同步。

---

## 9. 需要的支撑

- 语言：class、Double、Int、Long、Bool、Result、Unit；
- 运行时：`RuntimeMonitor.enter/exit/notifyAll/waitDeadline`、`nowMono`；
- 接口：`Context`、`Error`、`cancelledError`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Context`、`RuntimeMonitor`、`Error`、`nowMono`、错误辅助函数。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；无资源；无 close。

---

## 12. 示例与反例

正确：`new RateLimiter(100.0, 10.0)`；`acquireMany(ctx, 3)`。  
反例：rate=0；capacity<1；请求 20 个但容量 10；把 availablePermits 当精确配额；期望公平唤醒。

---

## 13. 测试/场景义务

初始容量；补充速率；容量上限；单/多许可；容量边界；tryAcquire；取消；等待唤醒；时间跳跃；并发竞争；非有限参数；`availablePermits`。

---

## 14. XNull 伪代码

```xnull
class RateLimiter {
    final Double _permitsPerSecond
    final Double _capacity
    final RuntimeMonitor _monitor
    Double _tokens
    Long _lastRefillMono

    RateLimiter(Double permitsPerSecond, Double burstCapacity) {
        if !(permitsPerSecond > 0.0) {
            throw "RateLimiter: permitsPerSecond must be positive"
        }
        if !(burstCapacity >= 1.0) {
            throw "RateLimiter: burstCapacity must be at least 1"
        }
        _permitsPerSecond = permitsPerSecond
        _capacity = burstCapacity
        _tokens = burstCapacity
        _lastRefillMono = nowMono()
        _monitor = new RuntimeMonitor()
    }

    RateLimiter(Double permitsPerSecond) {
        if !(permitsPerSecond > 0.0) {
            throw "RateLimiter: permitsPerSecond must be positive"
        }
        _permitsPerSecond = permitsPerSecond
        _capacity = 1.0
        _tokens = 1.0
        _lastRefillMono = nowMono()
        _monitor = new RuntimeMonitor()
    }

    Result<Unit, Error> acquire(Context context) {
        return self.acquireMany(context, 1)
    }

    Result<Unit, Error> acquireMany(Context context, Int permits) {
        if context == null { throw "RateLimiter.acquireMany: null context" }
        if permits < 1 { throw "RateLimiter.acquireMany: permits < 1" }
        if (permits as Double) > _capacity {
            return Err(new BasicError(ErrorKind.InvalidArgument, "permits exceed burst capacity"))
        }
        while true {
            _monitor.enter()
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("rate limiter acquire"))
            }
            self.refill()
            if _tokens >= (permits as Double) {
                _tokens = _tokens - (permits as Double)
                _monitor.notifyAll()
                _monitor.exit()
                return Ok(unit)
            }
            Double missing = (permits as Double) - _tokens
            Long waitMillis = (missing * 1000.0 / _permitsPerSecond) as Long + 1
            if waitMillis < 1 { waitMillis = 1 }
            Int state = _monitor.waitDeadline(context, nowMono() + waitMillis)
            _monitor.exit()
            if state == 1 {
                return Err(cancelledError("rate limiter acquire"))
            }
        }
    }

    Bool tryAcquire() {
        return self.tryAcquireMany(1)
    }

    Bool tryAcquireMany(Int permits) {
        if permits < 1 { throw "RateLimiter.tryAcquireMany: permits < 1" }
        if (permits as Double) > _capacity { return false }
        _monitor.enter()
        self.refill()
        if _tokens < (permits as Double) {
            _monitor.exit()
            return false
        }
        _tokens = _tokens - (permits as Double)
        _monitor.notifyAll()
        _monitor.exit()
        return true
    }

    Double availablePermits() {
        _monitor.enter()
        self.refill()
        Double result = _tokens
        _monitor.exit()
        return result
    }

    Double permitsPerSecond() { return _permitsPerSecond }
    Double burstCapacity() { return _capacity }

    private void refill() {
        Long now = nowMono()
        Long elapsed = now - _lastRefillMono
        if elapsed <= 0 { return }
        Double added = (elapsed as Double) * _permitsPerSecond / 1000.0
        _tokens = _tokens + added
        if _tokens > _capacity { _tokens = _capacity }
        _lastRefillMono = now
    }
}
```
