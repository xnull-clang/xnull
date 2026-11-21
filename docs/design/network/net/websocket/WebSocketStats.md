# `WebSocketStats`

| 项 | 值 |
| --- | --- |
| 类型 | `class WebSocketStats` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

WebSocket 统计快照：消息/字节/ping/pong/发送队列/最后 pong。

不做：实时指标、Prometheus 导出、业务统计。

---

## 2. 设计逻辑

- 不可变快照；计数 ≥0。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 |
| --- | --- |
| `_messagesSent` | `Long` |
| `_messagesReceived` | `Long` |
| `_bytesSent` | `Long` |
| `_bytesReceived` | `Long` |
| `_pingsSent` | `Long` |
| `_pongsReceived` | `Long` |
| `_sendQueueBytes` | `Long` |
| `_lastPongMillis` | `Long` |

---

## 4. 生命周期

快照；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `WebSocketStats(...)` | 见字段 | ≥0 | 负值 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 |
| --- | --- | --- | --- |
| `messagesSent` | 发送数 | 无 | `Long` |
| `messagesReceived` | 接收数 | 无 | `Long` |
| `bytesSent` | 发送字节 | 无 | `Long` |
| `bytesReceived` | 接收字节 | 无 | `Long` |
| `pingsSent` | ping | 无 | `Long` |
| `pongsReceived` | pong | 无 | `Long` |
| `sendQueueBytes` | 队列 | 无 | `Long` |
| `lastPongMillis` | 最后 pong | 无 | `Long` |

---

## 8. 使用的技术

- 不可变快照。

---

## 9. 需要的支撑

- 语言：class、Long；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；无资源。

---

## 12. 示例与反例

正确：`stats.bytesReceived()`。  
反例：修改 stats 期望变化；负计数；把快照当实时。

---

## 13. 测试/场景义务

零值；各字段；快照；负值 panic。

---

## 14. XNull 伪代码

```xnull
class WebSocketStats {
    final Long _messagesSent
    final Long _messagesReceived
    final Long _bytesSent
    final Long _bytesReceived
    final Long _pingsSent
    final Long _pongsReceived
    final Long _sendQueueBytes
    final Long _lastPongMillis

    WebSocketStats(Long messagesSent, Long messagesReceived, Long bytesSent,
                   Long bytesReceived, Long pingsSent, Long pongsReceived,
                   Long sendQueueBytes, Long lastPongMillis) {
        if messagesSent < 0 || messagesReceived < 0 || bytesSent < 0 || bytesReceived < 0 {
            throw "WebSocketStats: negative counter"
        }
        if pingsSent < 0 || pongsReceived < 0 || sendQueueBytes < 0 || lastPongMillis < 0 {
            throw "WebSocketStats: negative value"
        }
        _messagesSent = messagesSent
        _messagesReceived = messagesReceived
        _bytesSent = bytesSent
        _bytesReceived = bytesReceived
        _pingsSent = pingsSent
        _pongsReceived = pongsReceived
        _sendQueueBytes = sendQueueBytes
        _lastPongMillis = lastPongMillis
    }

    Long messagesSent() { return _messagesSent }
    Long messagesReceived() { return _messagesReceived }
    Long bytesSent() { return _bytesSent }
    Long bytesReceived() { return _bytesReceived }
    Long pingsSent() { return _pingsSent }
    Long pongsReceived() { return _pongsReceived }
    Long sendQueueBytes() { return _sendQueueBytes }
    Long lastPongMillis() { return _lastPongMillis }
}
```
