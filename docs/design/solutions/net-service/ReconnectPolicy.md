# `ReconnectPolicy`

| 项 | 值 |
| --- | --- |
| 类型 | `class ReconnectPolicy` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | `Error`、`ErrorKind`、`retryDelayRaw` |

---

## 1. 定位

客户端重连退避策略：初始延迟、最大延迟、增长倍数、最大次数、抖动、可重试错误分类。

不做：实际连接、消息重放、DNS 重解析、连接迁移、服务端重连、会话恢复。

本类型与 [`xdk.net.websocket.ReconnectPolicy`](../../network/net/websocket/ReconnectPolicy.md) 同名但职责不同：后者只服务 WebSocket 客户端握手；本类型增加 `ErrorKind` 过滤，供通用 TCP/TLS 客户端使用。两者不互相替代。

---

## 2. 设计逻辑

- 可变 builder；`Client` 构造时复制，运行中修改不影响已创建客户端。
- 默认初始 1s、最大 30s、倍数 2.0、最多 5 次、抖动开启。
- 默认可重试分类：`Network`、`Timeout`、`Unavailable`、`Busy`。
- 次数从 0 开始；`attempt >= maxAttempts` 返回 false；`maxAttempts=0` 表示不重连。
- `delayMillis` 为纯计算；抖动由 `retryDelayRaw` 生成，返回值可能小于名义值。
- 错误分类过滤在 `shouldRetry` 中完成；`Cancelled` 与 `InvalidArgument` 默认不重试。
- 无 close；可共享；非线程安全（builder 阶段）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_initialDelayMillis` | `Long` | 初始延迟，≥0 |
| `_maxDelayMillis` | `Long` | 最大延迟，≥initial |
| `_multiplier` | `Double` | 增长倍数，≥1.0 |
| `_maxAttempts` | `Int` | 最大尝试次数，≥0 |
| `_jitter` | `Bool` | 是否抖动 |
| `_retryableKinds` | `List<ErrorKind>` | 可重试分类；非 null，无 null 元素 |

不变量：`initial <= max`；`multiplier >= 1.0`；`maxAttempts >= 0`；列表可空但元素非 null；允许重复分类，匹配时忽略重复。

---

## 4. 生命周期

构造后可变；`Client` 构造时复制；无 close；复制后可独立修改。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ReconnectPolicy()` | 无 | 默认值 | 无 |
| `ReconnectPolicy(ReconnectPolicy other)` | 非 null | 非 null | null → panic |

构造后通过 setter 调整；非法值属于合同错误（panic）。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `initialDelayMillis` | 设置初始延迟 | `Long value` | `ReconnectPolicy` | <0 → panic |
| `maxDelayMillis` | 设置最大延迟 | `Long value` | `ReconnectPolicy` | <initial → panic |
| `multiplier` | 设置倍数 | `Double value` | `ReconnectPolicy` | <1.0/NaN → panic |
| `maxAttempts` | 设置最大次数 | `Int value` | `ReconnectPolicy` | <0 → panic |
| `jitter` | 设置抖动 | `Bool value` | `ReconnectPolicy` | 无 |
| `retryKind` | 加入可重试分类 | `ErrorKind kind` | `ReconnectPolicy` | null → panic |
| `clearRetryKinds` | 清空分类 | 无 | `ReconnectPolicy` | 无 |
| `getInitialDelayMillis` | 读初始延迟 | 无 | `Long` | 无 |
| `getMaxDelayMillis` | 读最大延迟 | 无 | `Long` | 无 |
| `getMultiplier` | 读倍数 | 无 | `Double` | 无 |
| `getMaxAttempts` | 读最大次数 | 无 | `Int` | 无 |
| `isJitter` | 读抖动 | 无 | `Bool` | 无 |
| `retryableKinds` | 分类快照 | 无 | `List<ErrorKind>` | 无 |
| `isRetryableKind` | 分类是否可重试 | `ErrorKind kind` | `Bool` | null → panic |
| `shouldRetry` | 仅按次数判断 | `Int attempt` | `Bool` | <0 → panic |
| `shouldRetry` | 按次数与错误判断 | `Int attempt, Error error` | `Bool` | <0/null → panic |
| `delayMillis` | 退避延迟 | `Int attempt` | `Long` | <0 → panic |
| `copy` | 独立快照 | 无 | `ReconnectPolicy` | 无 |

说明：

- `initialDelayMillis` 大于当前 `maxDelayMillis` 时 panic；先降低初始值或先提高最大值。
- `maxAttempts` 是“最多尝试次数”，不是“最多重试次数”；`attempt=0` 是第一次重连尝试。
- `shouldRetry(attempt, error)` 先检查次数，再检查 `error.kind()` 是否在列表中。
- `delayMillis` 不改变状态；同参数可重复调用。
- `retryableKinds` 返回副本；修改副本不影响策略。

---

## 8. 使用的技术

- 指数退避；
- 抖动；
- 错误分类过滤；
- 纯函数判定；
- builder 快照。

---

## 9. 需要的支撑

- 语言：class、Long、Int、Double、Bool、List、Result；
- 运行时：`retryDelayRaw`；
- 接口：`Error`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Error`、`ErrorKind`、`retryDelayRaw`、`Client`。

---

## 11. 所有权与并发

可变；非线程安全；`Client` 构造时复制；无资源；副本独立。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`new ReconnectPolicy().maxAttempts(8).initialDelayMillis(500).maxDelayMillis(20000)`；失败后按 `shouldRetry(attempt, error)` 与 `delayMillis(attempt)` 重连。  
反例：无限重试；对 `Cancelled` 重试；`maxAttempts=0` 仍期望重连；把抖动延迟当精确值；运行中修改策略期望已创建客户端变化。

---

## 13. 测试/场景义务

默认值；每个 setter；非法值；顺序约束；次数边界；分类匹配/不匹配；清空分类；抖动范围；最大延迟封顶；copy 独立；`ErrorKind` 全分类；`Cancelled` 不重试；`maxAttempts=0`。

---

## 14. XNull 伪代码

```xnull
class ReconnectPolicy {
    Long _initialDelayMillis = 1000
    Long _maxDelayMillis = 30000
    Double _multiplier = 2.0
    Int _maxAttempts = 5
    Bool _jitter = true
    List<ErrorKind> _retryableKinds = [
        ErrorKind.Network,
        ErrorKind.Timeout,
        ErrorKind.Unavailable,
        ErrorKind.Busy,
    ]

    ReconnectPolicy() {
    }

    ReconnectPolicy(ReconnectPolicy other) {
        if other == null { throw "ReconnectPolicy: null other" }
        _initialDelayMillis = other.getInitialDelayMillis()
        _maxDelayMillis = other.getMaxDelayMillis()
        _multiplier = other.getMultiplier()
        _maxAttempts = other.getMaxAttempts()
        _jitter = other.isJitter()
        _retryableKinds = other.retryableKinds()
    }

    ReconnectPolicy initialDelayMillis(Long value) {
        if value < 0 { throw "ReconnectPolicy.initialDelayMillis: negative" }
        if value > _maxDelayMillis {
            throw "ReconnectPolicy.initialDelayMillis: exceeds max"
        }
        _initialDelayMillis = value
        return self
    }

    ReconnectPolicy maxDelayMillis(Long value) {
        if value < _initialDelayMillis {
            throw "ReconnectPolicy.maxDelayMillis: below initial"
        }
        _maxDelayMillis = value
        return self
    }

    ReconnectPolicy multiplier(Double value) {
        if value < 1.0 { throw "ReconnectPolicy.multiplier: below one" }
        if value != value { throw "ReconnectPolicy.multiplier: NaN" }
        _multiplier = value
        return self
    }

    ReconnectPolicy maxAttempts(Int value) {
        if value < 0 { throw "ReconnectPolicy.maxAttempts: negative" }
        _maxAttempts = value
        return self
    }

    ReconnectPolicy jitter(Bool value) {
        _jitter = value
        return self
    }

    ReconnectPolicy retryKind(ErrorKind kind) {
        if kind == null { throw "ReconnectPolicy.retryKind: null" }
        if !self.isRetryableKind(kind) {
            _retryableKinds.push(kind)
        }
        return self
    }

    ReconnectPolicy clearRetryKinds() {
        _retryableKinds = []
        return self
    }

    Long getInitialDelayMillis() { return _initialDelayMillis }
    Long getMaxDelayMillis() { return _maxDelayMillis }
    Double getMultiplier() { return _multiplier }
    Int getMaxAttempts() { return _maxAttempts }
    Bool isJitter() { return _jitter }
    List<ErrorKind> retryableKinds() { return _retryableKinds.copy() }

    Bool isRetryableKind(ErrorKind kind) {
        if kind == null { throw "ReconnectPolicy.isRetryableKind: null" }
        Int index = 0
        while index < _retryableKinds.length() {
            if _retryableKinds.get(index) == kind { return true }
            index = index + 1
        }
        return false
    }

    Bool shouldRetry(Int attempt) {
        if attempt < 0 { throw "ReconnectPolicy.shouldRetry: negative" }
        return attempt < _maxAttempts
    }

    Bool shouldRetry(Int attempt, Error error) {
        if attempt < 0 { throw "ReconnectPolicy.shouldRetry: negative" }
        if error == null { throw "ReconnectPolicy.shouldRetry: null error" }
        if !self.shouldRetry(attempt) { return false }
        return self.isRetryableKind(error.kind())
    }

    Long delayMillis(Int attempt) {
        if attempt < 0 { throw "ReconnectPolicy.delayMillis: negative" }
        return retryDelayRaw(_initialDelayMillis, _maxDelayMillis,
            _multiplier, attempt, _jitter)
    }

    ReconnectPolicy copy() {
        return new ReconnectPolicy(self)
    }
}
```
