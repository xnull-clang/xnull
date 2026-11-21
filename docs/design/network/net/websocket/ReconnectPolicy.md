# `ReconnectPolicy`

| 项 | 值 |
| --- | --- |
| 类型 | `class ReconnectPolicy` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

WebSocket 自动重连退避策略：初始延迟、最大延迟、倍数、最大次数、抖动。

不做：重连执行、消息重放、DNS 缓存。

---

## 2. 设计逻辑

- 不可变字段；`shouldRetry`/`delayFor` 纯计算。
- 默认 1s 初始、30s 最大、倍数 2、最多 5 次、抖动开启。
- 次数从 0 开始；超过 maxAttempts 返回 false。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_initialDelayMillis` | `Long` | 初始 |
| `_maxDelayMillis` | `Long` | 最大 |
| `_multiplier` | `Double` | 倍数 |
| `_maxAttempts` | `Int` | 最大次数 |
| `_jitter` | `Bool` | 抖动 |

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ReconnectPolicy()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `shouldRetry` | 是否重试 | `Int attempt` | `Bool` | 负值 → panic |
| `delayMillis` | 退避延迟 | `Int attempt` | `Long` | 负值 → panic |
| `getInitialDelayMillis` | 初始 | 无 | `Long` | 无 |
| `getMaxDelayMillis` | 最大 | 无 | `Long` | 无 |
| `getMultiplier` | 倍数 | 无 | `Double` | 无 |
| `getMaxAttempts` | 最大次数 | 无 | `Int` | 无 |
| `isJitter` | 抖动 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 指数退避；
- 抖动；
- 纯函数。

---

## 9. 需要的支撑

- 语言：class、Long、Int、Double、Bool；
- 运行时：`retryDelayRaw`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`retryDelayRaw`。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`policy.delayMillis(0)`。  
反例：负数尝试；无限重试；把延迟当精确值（抖动）。

---

## 13. 测试/场景义务

边界次数；倍增长；最大延迟；抖动范围；默认值。

---

## 14. XNull 伪代码

```xnull
class ReconnectPolicy {
    final Long _initialDelayMillis
    final Long _maxDelayMillis
    final Double _multiplier
    final Int _maxAttempts
    final Bool _jitter

    ReconnectPolicy() {
        _initialDelayMillis = 1000
        _maxDelayMillis = 30000
        _multiplier = 2.0
        _maxAttempts = 5
        _jitter = true
    }

    private ReconnectPolicy(Long initialDelayMillis, Long maxDelayMillis,
                            Double multiplier, Int maxAttempts, Bool jitter) {
        if initialDelayMillis < 0 || maxDelayMillis < initialDelayMillis {
            throw "ReconnectPolicy: invalid delay"
        }
        if multiplier < 1.0 { throw "ReconnectPolicy: invalid multiplier" }
        if maxAttempts < 0 { throw "ReconnectPolicy: negative attempts" }
        _initialDelayMillis = initialDelayMillis
        _maxDelayMillis = maxDelayMillis
        _multiplier = multiplier
        _maxAttempts = maxAttempts
        _jitter = jitter
    }

    Bool shouldRetry(Int attempt) {
        if attempt < 0 { throw "ReconnectPolicy.shouldRetry: negative" }
        return attempt < _maxAttempts
    }

    Long delayMillis(Int attempt) {
        if attempt < 0 { throw "ReconnectPolicy.delayMillis: negative" }
        return retryDelayRaw(_initialDelayMillis, _maxDelayMillis, _multiplier, attempt, _jitter)
    }

    Long getInitialDelayMillis() { return _initialDelayMillis }
    Long getMaxDelayMillis() { return _maxDelayMillis }
    Double getMultiplier() { return _multiplier }
    Int getMaxAttempts() { return _maxAttempts }
    Bool isJitter() { return _jitter }
}
```
