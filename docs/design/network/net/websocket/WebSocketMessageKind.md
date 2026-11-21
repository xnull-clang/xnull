# `WebSocketMessageKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum WebSocketMessageKind` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

WebSocket 消息类型：Text/Binary/Ping/Pong/Close。

不做：分片类型、压缩、HTTP/2 帧。

---

## 2. 设计逻辑

- 简单枚举；`WebSocketMessage.kind()` 返回。
- 分片对调用方透明；控制帧作为消息暴露。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Text` | UTF-8 文本 |
| `Binary` | 二进制 |
| `Ping` | Ping |
| `Pong` | Pong |
| `Close` | Close |

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
| `webSocketMessageKindName` | 稳定名 | `WebSocketMessageKind kind` | `String` | 无 |

---

## 8. 使用的技术

- 简单枚举。

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

正确：`message.kind() == WebSocketMessageKind.Text`。  
反例：把 Ping 当业务消息；自动跳过 Close。

---

## 13. 测试/场景义务

五成员；名称；消息构造；控制帧。

---

## 14. XNull 伪代码

```xnull
enum WebSocketMessageKind {
    Text,
    Binary,
    Ping,
    Pong,
    Close,
}

String webSocketMessageKindName(WebSocketMessageKind kind) {
    if kind == WebSocketMessageKind.Text { return "text" }
    if kind == WebSocketMessageKind.Binary { return "binary" }
    if kind == WebSocketMessageKind.Ping { return "ping" }
    if kind == WebSocketMessageKind.Pong { return "pong" }
    return "close"
}
```
