# `ConnectionPoolOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class ConnectionPoolOptions` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

连接池配置：总上限、每键上限、空闲/寿命、连接/等待超时、健康检查开关。

不做：TLS 配置、DNS、具体连接创建（由 connector 提供）。

---

## 2. 设计逻辑

- 可变构建期；池构造时复制。
- 默认：总 32、每键 8、空闲 60s、寿命 300s、连接 10s、等待 10s、健康检查关闭。
- 所有上限 >0；超时 ≥0。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxTotal` | `Int` | 总连接上限 |
| `_maxPerKey` | `Int` | 单键上限 |
| `_idleTimeoutMillis` | `Long` | 空闲超时 |
| `_maxLifetimeMillis` | `Long` | 最大寿命 |
| `_connectTimeoutMillis` | `Long` | 建连超时 |
| `_waitTimeoutMillis` | `Long` | 等待借出超时 |
| `_healthCheck` | `Bool` | 复用前检查 |

不变量：maxTotal/maxPerKey >0；超时 ≥0；不可变快照由池持有。

---

## 4. 生命周期

构造后可变；无 close；池构造时复制。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ConnectionPoolOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxTotal` | 总上限 | `Int value` | `ConnectionPoolOptions` | ≤0 → panic |
| `maxPerKey` | 单键上限 | `Int value` | `ConnectionPoolOptions` | ≤0 → panic |
| `idleTimeoutMillis` | 空闲超时 | `Long value` | `ConnectionPoolOptions` | <0 → panic |
| `maxLifetimeMillis` | 最大寿命 | `Long value` | `ConnectionPoolOptions` | <0 → panic |
| `connectTimeoutMillis` | 建连超时 | `Long value` | `ConnectionPoolOptions` | <0 → panic |
| `waitTimeoutMillis` | 等待超时 | `Long value` | `ConnectionPoolOptions` | <0 → panic |
| `healthCheck` | 健康检查 | `Bool value` | `ConnectionPoolOptions` | 无 |
| `getMaxTotal` | 总上限 | 无 | `Int` | 无 |
| `getMaxPerKey` | 单键上限 | 无 | `Int` | 无 |
| `getIdleTimeoutMillis` | 空闲超时 | 无 | `Long` | 无 |
| `getMaxLifetimeMillis` | 寿命 | 无 | `Long` | 无 |
| `getConnectTimeoutMillis` | 建连超时 | 无 | `Long` | 无 |
| `getWaitTimeoutMillis` | 等待超时 | 无 | `Long` | 无 |
| `isHealthCheck` | 健康检查 | 无 | `Bool` | 无 |
| `copy` | 独立快照 | 无 | `ConnectionPoolOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 上限/超时；
- 快照。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；池复制；无资源。

---

## 12. 示例与反例

正确：`new ConnectionPoolOptions().maxTotal(64).idleTimeoutMillis(30000)`。  
反例：maxTotal 0；负超时；修改 options 期望已有池变化。

---

## 13. 测试/场景义务

默认值；setter；非法；copy 独立；池快照；健康检查。

---

## 14. XNull 伪代码

```xnull
class ConnectionPoolOptions {
    Int _maxTotal = 32
    Int _maxPerKey = 8
    Long _idleTimeoutMillis = 60000
    Long _maxLifetimeMillis = 300000
    Long _connectTimeoutMillis = 10000
    Long _waitTimeoutMillis = 10000
    Bool _healthCheck = false

    ConnectionPoolOptions() {
    }

    ConnectionPoolOptions maxTotal(Int value) {
        if value <= 0 { throw "ConnectionPoolOptions.maxTotal: invalid" }
        _maxTotal = value
        return self
    }

    ConnectionPoolOptions maxPerKey(Int value) {
        if value <= 0 { throw "ConnectionPoolOptions.maxPerKey: invalid" }
        _maxPerKey = value
        return self
    }

    ConnectionPoolOptions idleTimeoutMillis(Long value) {
        if value < 0 { throw "ConnectionPoolOptions.idleTimeoutMillis: negative" }
        _idleTimeoutMillis = value
        return self
    }

    ConnectionPoolOptions maxLifetimeMillis(Long value) {
        if value < 0 { throw "ConnectionPoolOptions.maxLifetimeMillis: negative" }
        _maxLifetimeMillis = value
        return self
    }

    ConnectionPoolOptions connectTimeoutMillis(Long value) {
        if value < 0 { throw "ConnectionPoolOptions.connectTimeoutMillis: negative" }
        _connectTimeoutMillis = value
        return self
    }

    ConnectionPoolOptions waitTimeoutMillis(Long value) {
        if value < 0 { throw "ConnectionPoolOptions.waitTimeoutMillis: negative" }
        _waitTimeoutMillis = value
        return self
    }

    ConnectionPoolOptions healthCheck(Bool value) {
        _healthCheck = value
        return self
    }

    Int getMaxTotal() { return _maxTotal }
    Int getMaxPerKey() { return _maxPerKey }
    Long getIdleTimeoutMillis() { return _idleTimeoutMillis }
    Long getMaxLifetimeMillis() { return _maxLifetimeMillis }
    Long getConnectTimeoutMillis() { return _connectTimeoutMillis }
    Long getWaitTimeoutMillis() { return _waitTimeoutMillis }
    Bool isHealthCheck() { return _healthCheck }

    ConnectionPoolOptions copy() {
        ConnectionPoolOptions result = new ConnectionPoolOptions()
        result.maxTotal(_maxTotal)
        result.maxPerKey(_maxPerKey)
        result.idleTimeoutMillis(_idleTimeoutMillis)
        result.maxLifetimeMillis(_maxLifetimeMillis)
        result.connectTimeoutMillis(_connectTimeoutMillis)
        result.waitTimeoutMillis(_waitTimeoutMillis)
        result.healthCheck(_healthCheck)
        return result
    }
}
```
