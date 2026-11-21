# `HttpProxyOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpProxyOptions` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

HTTP 代理服务器配置：最大连接、连接/空闲超时、是否要求认证。

不做：访问控制规则、认证后端、日志/TLS。

---

## 2. 设计逻辑

- 可变 builder；服务器复制。
- 默认 128 连接、10s 连接、60s 空闲、不要求认证。
- 值 >0；非法 panic。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxConnections` | `Int` | 最大连接 |
| `_connectTimeoutMillis` | `Long` | 连接超时 |
| `_idleTimeoutMillis` | `Long` | 空闲超时 |
| `_requireAuth` | `Bool` | 认证 |

---

## 4. 生命周期

可变；代理复制；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpProxyOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxConnections` | 设置 | `Int` | `HttpProxyOptions` | ≤0 → panic |
| `connectTimeoutMillis` | 设置 | `Long` | `HttpProxyOptions` | ≤0 → panic |
| `idleTimeoutMillis` | 设置 | `Long` | `HttpProxyOptions` | ≤0 → panic |
| `requireAuth` | 设置 | `Bool` | `HttpProxyOptions` | 无 |
| `getMaxConnections` | 读取 | 无 | `Int` | 无 |
| `getConnectTimeoutMillis` | 读取 | 无 | `Long` | 无 |
| `getIdleTimeoutMillis` | 读取 | 无 | `Long` | 无 |
| `isRequireAuth` | 读取 | 无 | `Bool` | 无 |
| `copy` | 快照 | 无 | `HttpProxyOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 超时/上限。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：`new HttpProxyOptions().requireAuth(true)`。  
反例：0 连接；负超时；修改 options 期望已有代理变化。

---

## 13. 测试/场景义务

默认；setter；非法；copy；快照；认证开关。

---

## 14. XNull 伪代码

```xnull
class HttpProxyOptions {
    Int _maxConnections = 128
    Long _connectTimeoutMillis = 10000
    Long _idleTimeoutMillis = 60000
    Bool _requireAuth = false

    HttpProxyOptions() {
    }

    HttpProxyOptions maxConnections(Int value) {
        if value <= 0 { throw "HttpProxyOptions.maxConnections: invalid" }
        _maxConnections = value
        return self
    }

    HttpProxyOptions connectTimeoutMillis(Long value) {
        if value <= 0 { throw "HttpProxyOptions.connectTimeoutMillis: invalid" }
        _connectTimeoutMillis = value
        return self
    }

    HttpProxyOptions idleTimeoutMillis(Long value) {
        if value <= 0 { throw "HttpProxyOptions.idleTimeoutMillis: invalid" }
        _idleTimeoutMillis = value
        return self
    }

    HttpProxyOptions requireAuth(Bool value) {
        _requireAuth = value
        return self
    }

    Int getMaxConnections() { return _maxConnections }
    Long getConnectTimeoutMillis() { return _connectTimeoutMillis }
    Long getIdleTimeoutMillis() { return _idleTimeoutMillis }
    Bool isRequireAuth() { return _requireAuth }

    HttpProxyOptions copy() {
        HttpProxyOptions result = new HttpProxyOptions()
        result.maxConnections(_maxConnections)
        result.connectTimeoutMillis(_connectTimeoutMillis)
        result.idleTimeoutMillis(_idleTimeoutMillis)
        result.requireAuth(_requireAuth)
        return result
    }
}
```
