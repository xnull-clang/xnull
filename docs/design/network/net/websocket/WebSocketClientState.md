# `WebSocketClientState`

| 项 | 值 |
| --- | --- |
| 类型 | `enum WebSocketClientState` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

自动重连客户端状态：Idle/Connecting/Open/Reconnecting/Closed。

不做：单连接状态（`WebSocketState`）、HTTP 状态。

---

## 2. 设计逻辑

- 简单枚举；`WebSocketClient.state()` 返回。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Idle` | 未连接 |
| `Connecting` | 首次连接 |
| `Open` | 已连接 |
| `Reconnecting` | 重连中 |
| `Closed` | 已关闭 |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `webSocketClientStateName` | 名称 | `WebSocketClientState state` | `String` | 无 |

---

## 8. 使用的技术

- 简单枚举。

---

## 9. 需要的支撑

- 语言：enum、String。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源。

---

## 12. 示例与反例

正确：`client.state() == WebSocketClientState.Reconnecting`。  
反例：把 Open 当 socket 一定 Open；Closed 后重连。

---

## 13. 测试/场景义务

五成员；名称；状态迁移。

---

## 14. XNull 伪代码

```xnull
enum WebSocketClientState {
    Idle,
    Connecting,
    Open,
    Reconnecting,
    Closed,
}

String webSocketClientStateName(WebSocketClientState state) {
    if state == WebSocketClientState.Idle { return "idle" }
    if state == WebSocketClientState.Connecting { return "connecting" }
    if state == WebSocketClientState.Open { return "open" }
    if state == WebSocketClientState.Reconnecting { return "reconnecting" }
    return "closed"
}
```
