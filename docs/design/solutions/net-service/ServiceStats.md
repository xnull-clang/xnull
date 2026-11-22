# `ServiceStats`

| 项 | 值 |
| --- | --- |
| 类型 | `class ServiceStats` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

网络服务统计快照：当前/累计连接、当前/累计会话、累计字节、累计消息、重连、背压事件、错误、运行时长。

不做：实时指标导出、直方图、每连接明细、日志、计费、SLA 计算。

统计是某一时刻的只读快照；不同字段可能来自不同计数器，不保证跨字段原子一致。

---

## 2. 设计逻辑

- 全部字段 `final`；构造后不可变。
- 当前数量用 `Int`；累计数量/字节/时长用 `Long`。
- 计数从 0 开始；`uptimeMillis` 是服务启动至今的单调毫秒差。
- `rejectedConnections` 只统计因上限/背压被拒绝的连接；正常关闭不计入。
- `backpressureEvents` 统计暂停接受、暂停读取、显式拒绝的次数；一次事件可对应多个连接。
- `errors` 统计导致连接/会话异常结束或启动/重连失败的次数。
- `activeSessions <= activeConnections` 在单连接至多一会话的实现中成立；快照不强制校验。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_activeConnections` | `Int` | 当前活动连接，≥0 |
| `_totalConnections` | `Long` | 累计接受/建立连接，≥0 |
| `_rejectedConnections` | `Long` | 累计拒绝，≥0 |
| `_activeSessions` | `Int` | 当前活动会话，≥0 |
| `_totalSessions` | `Long` | 累计创建会话，≥0 |
| `_bytesRead` | `Long` | 累计读取字节，≥0 |
| `_bytesWritten` | `Long` | 累计写入字节，≥0 |
| `_messagesReceived` | `Long` | 累计接收消息，≥0 |
| `_messagesSent` | `Long` | 累计发送消息，≥0 |
| `_reconnectAttempts` | `Long` | 累计重连尝试，≥0 |
| `_backpressureEvents` | `Long` | 累计背压事件，≥0 |
| `_errors` | `Long` | 累计错误，≥0 |
| `_uptimeMillis` | `Long` | 运行时长，≥0 |

不变量：全部非负；不可变；列表/引用无；快照不保证跨字段原子。

---

## 4. 生命周期

构造后不可变；无 close；可共享；新快照由服务查询生成。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ServiceStats` | 13 个字段（见 §3） | 全部 ≥0 | 负值 → panic |

构造器主要供运行时/服务实现使用；调用方通常只读。

---

## 6. 字段表

见 §3；字段私有且 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `activeConnections` | 当前连接 | 无 | `Int` | 无 |
| `totalConnections` | 累计连接 | 无 | `Long` | 无 |
| `rejectedConnections` | 累计拒绝 | 无 | `Long` | 无 |
| `activeSessions` | 当前会话 | 无 | `Int` | 无 |
| `totalSessions` | 累计会话 | 无 | `Long` | 无 |
| `bytesRead` | 累计读字节 | 无 | `Long` | 无 |
| `bytesWritten` | 累计写字节 | 无 | `Long` | 无 |
| `messagesReceived` | 累计收消息 | 无 | `Long` | 无 |
| `messagesSent` | 累计发消息 | 无 | `Long` | 无 |
| `reconnectAttempts` | 累计重连 | 无 | `Long` | 无 |
| `backpressureEvents` | 累计背压 | 无 | `Long` | 无 |
| `errors` | 累计错误 | 无 | `Long` | 无 |
| `uptimeMillis` | 运行时长 | 无 | `Long` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `copy` | 复制快照 | 无 | `ServiceStats` | 无 |

说明：

- `describe` 只输出计数，不输出地址、会话属性或载荷。
- `copy` 返回独立值对象；字段均为值类型。
- 读取无锁、无阻塞；快照生成后不再变化。

---

## 8. 使用的技术

- 不可变快照；
- 单调运行时长；
- 计数聚合；
- 单行诊断。

---

## 9. 需要的支撑

- 语言：class、final 字段、Int、Long、String；
- 运行时：`monotonicMillis`（生成快照时）、`str`；
- 接口：`Server`、`Client`、`NetworkService`。

---

## 10. 依赖的特性/接口/类

`Server`、`Client`、`NetworkService`、`NetServiceState`、`monotonicMillis`、`str`。

---

## 11. 所有权与并发

不可变；无资源；可共享；无取消点。
相等：引用身份；需要比较时逐字段比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`stats.activeConnections()` 观察负载；`stats.errors()` 与日志关联；`describe()` 写单行监控。  
反例：把快照当实时计数器；用 `activeConnections` 推断队列长度；把 `bytesRead` 当应用消息长度；把 `uptimeMillis` 当墙上时间；期望跨字段严格一致。

---

## 13. 测试/场景义务

构造/取值；负值拒绝；全零；大 `Long` 值；`describe` 格式；`copy` 独立；与 `Server.stats`/`Client.stats`/`NetworkService.stats` 组合；关闭后快照仍可读；错误/拒绝/背压计数语义。

---

## 14. XNull 伪代码

```xnull
class ServiceStats {
    final Int _activeConnections
    final Long _totalConnections
    final Long _rejectedConnections
    final Int _activeSessions
    final Long _totalSessions
    final Long _bytesRead
    final Long _bytesWritten
    final Long _messagesReceived
    final Long _messagesSent
    final Long _reconnectAttempts
    final Long _backpressureEvents
    final Long _errors
    final Long _uptimeMillis

    ServiceStats(Int activeConnections, Long totalConnections,
                 Long rejectedConnections, Int activeSessions,
                 Long totalSessions, Long bytesRead, Long bytesWritten,
                 Long messagesReceived, Long messagesSent,
                 Long reconnectAttempts, Long backpressureEvents,
                 Long errors, Long uptimeMillis) {
        if activeConnections < 0 || totalConnections < 0
            || rejectedConnections < 0 || activeSessions < 0
            || totalSessions < 0 || bytesRead < 0 || bytesWritten < 0
            || messagesReceived < 0 || messagesSent < 0
            || reconnectAttempts < 0 || backpressureEvents < 0
            || errors < 0 || uptimeMillis < 0 {
            throw "ServiceStats: negative value"
        }
        _activeConnections = activeConnections
        _totalConnections = totalConnections
        _rejectedConnections = rejectedConnections
        _activeSessions = activeSessions
        _totalSessions = totalSessions
        _bytesRead = bytesRead
        _bytesWritten = bytesWritten
        _messagesReceived = messagesReceived
        _messagesSent = messagesSent
        _reconnectAttempts = reconnectAttempts
        _backpressureEvents = backpressureEvents
        _errors = errors
        _uptimeMillis = uptimeMillis
    }

    Int activeConnections() { return _activeConnections }
    Long totalConnections() { return _totalConnections }
    Long rejectedConnections() { return _rejectedConnections }
    Int activeSessions() { return _activeSessions }
    Long totalSessions() { return _totalSessions }
    Long bytesRead() { return _bytesRead }
    Long bytesWritten() { return _bytesWritten }
    Long messagesReceived() { return _messagesReceived }
    Long messagesSent() { return _messagesSent }
    Long reconnectAttempts() { return _reconnectAttempts }
    Long backpressureEvents() { return _backpressureEvents }
    Long errors() { return _errors }
    Long uptimeMillis() { return _uptimeMillis }

    String describe() {
        return "connections active=" + str(_activeConnections)
            + " total=" + str(_totalConnections)
            + " rejected=" + str(_rejectedConnections)
            + " sessions active=" + str(_activeSessions)
            + " total=" + str(_totalSessions)
            + " bytesIn=" + str(_bytesRead)
            + " bytesOut=" + str(_bytesWritten)
            + " messagesIn=" + str(_messagesReceived)
            + " messagesOut=" + str(_messagesSent)
            + " reconnects=" + str(_reconnectAttempts)
            + " backpressure=" + str(_backpressureEvents)
            + " errors=" + str(_errors)
            + " uptimeMillis=" + str(_uptimeMillis)
    }

    ServiceStats copy() {
        return new ServiceStats(_activeConnections, _totalConnections,
            _rejectedConnections, _activeSessions, _totalSessions,
            _bytesRead, _bytesWritten, _messagesReceived, _messagesSent,
            _reconnectAttempts, _backpressureEvents, _errors, _uptimeMillis)
    }
}
```
