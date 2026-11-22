# `xdk.resilience` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.resilience` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.execution`、`xdk.runtime` |
| 被依赖 | 应用/客户端/服务端 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

容错策略：retry、circuit breaker、rate limiter、bulkhead、fallback、timeout。

不做：服务网格、分布式熔断、hedging（X）、全局策略注册表。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式对象 | 每个策略独立；调用方持有 |
| Context 可取消 | 所有等待接受 Context |
| 不吞错误 | 原错误保留；策略只决定是否继续 |
| 无全局 | 无全局熔断/限流 |
| 线程安全 | 策略内部同步；可跨任务共享 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `CircuitState` | enum | Closed/Open/HalfOpen | [`CircuitState.md`](CircuitState.md) |
| `CircuitBreaker` | class | 失败阈值/半开/重置 | [`CircuitBreaker.md`](CircuitBreaker.md) |
| `RateLimiter` | class | 令牌桶/等待 | [`RateLimiter.md`](RateLimiter.md) |
| `Bulkhead` | class | 并发上限/等待 | [`Bulkhead.md`](Bulkhead.md) |
| `Retry` | class | 重试执行 | [`Retry.md`](Retry.md) |
| `Fallback` | class | 主备降级 | [`Fallback.md`](Fallback.md) |
| `Timeout` | class | 任务级超时 | [`Timeout.md`](Timeout.md) |

X：Hedging、组合策略、分布式熔断、指标导出。

---

## 4. 顶层函数

无。

---

## 5. 技术/支撑/依赖

- 技术：滑动窗口/令牌桶/信号量/退避/任务截止。
- 支撑：`Context`、`RetryPolicy`、`RuntimeMonitor`、`TaskGroup`、`nowMono`。
- 依赖：`errors`、`execution`、`runtime`。

---

## 6. 场景

### R1：重试

`Retry.execute(ctx,policy,operation)`；需要抖动/谓词用 `Retry.executeWith(...)`。

### R2：熔断

`CircuitBreaker.execute(ctx,operation)`；Open 时 `Unavailable`。

### R3：限流

`RateLimiter.acquire(ctx)`；超时/取消。

### R4：并发隔离

`Bulkhead.execute(ctx,operation)`。

### R5：降级

`Fallback.execute(ctx,primary,fallback)`；取消不降级。

### R6：超时

`Timeout.execute(ctx,3000,operation)`；超时取消任务并返回 `Timeout`。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 分布式熔断 | 不做 |
| 全局注册表 | 禁止 |
| 公平性 | 不承诺 |
| Hedging | X |
| Timeout |  用任务截止实现；不接受 0/负值 |
| 退避 | 使用 `errors.RetryPolicy` |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Retryable`、`@CircuitBreakerPolicy`、`@RateLimit`、`@TimeoutPolicy` |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | ResilienceAnnotationProcessor（Validate/Generate） |
| 生成物 | 重试/熔断/限流/超时包装器 |
| 状态 | 领域注解 planned；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 服务方法 | `@Retryable`/`@CircuitBreakerPolicy`/`@RateLimit`/`@TimeoutPolicy` | 策略包装 |
| `Retry`/`CircuitBreaker`/`RateLimiter`/`Timeout` | `@Value`/`@Builder` | 值语义/策略构造 |

### 声明

```x
@Target(Method)
@Retention(Source)
@annotation Retryable {
    final Int maxAttempts = 3
    final Long initialDelayMillis = 100
}

@Target(Method)
@Retention(Source)
@annotation CircuitBreakerPolicy {
    final String name
    final Int failureThreshold = 5
}

@Target(Method)
@Retention(Source)
@annotation RateLimit {
    final String name
    final Int permits
    final Long perMillis
}

@Target(Method)
@Retention(Source)
@annotation TimeoutPolicy {
    final Long timeoutMillis
}
```

### 使用

```x
class UserService {
    @Retryable(3, 100)
    @CircuitBreakerPolicy("users", 5)
    @TimeoutPolicy(2000)
    User find(Long id) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
