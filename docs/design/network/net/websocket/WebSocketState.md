# `WebSocketState`

| 项 | 值 |
| --- | --- |
| 类型 | `enum WebSocketState` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

WebSocket 连接状态：Connecting/Open/Closing/Closed。

不做：HTTP 状态、TLS 状态、重连状态。

---

## 2. 设计逻辑

- 简单枚举；`WebSocket.state()` 返回。
- `Closing` 表示关闭握手已开始；`Closed` 表示不可再用。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Connecting` | 握手中 |
| `Open` | 可收发 |
| `Closing` | 关闭握手中 |
| `Closed` | 已关闭 |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `webSocketStateName` | 稳定名 | `WebSocketState state` | `String` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源。

---

## 12. 示例与反例

正确：`socket.state() == WebSocketState.Open`。  
反例：Closed 后发送；把 Connecting 当可发送。

---

## 13. 测试/场景义务

四成员；名称；状态迁移；关闭后。

---

## 14. XNull 伪代码

```xnull
enum WebSocketState {
    Connecting,
    Open,
    Closing,
    Closed,
}

String webSocketStateName(WebSocketState state) {
    if state == WebSocketState.Connecting { return "connecting" }
    if state == WebSocketState.Open { return "open" }
    if state == WebSocketState.Closing { return "closing" }
    return "closed"
}
```
