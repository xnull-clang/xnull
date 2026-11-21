# `WebSocketHandler`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol WebSocketHandler` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`WebSocket`、`Error` |

---

## 1. 定位

WebSocket 服务端处理入口：处理一个已握手连接。

不做：HTTP upgrade、路由、重连、认证。

---

## 2. 设计逻辑

- 单方法 `handle`；返回 `Result<Unit, Error>`。
- Handler 负责 receive/send/close；连接由服务器创建。
- 可并发处理多个连接；实现自行同步。

---

## 3. 表示与不变量

协议无字段。

---

## 4. 生命周期

协议无构造；实现决定。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `handle` | 处理连接 | `Context context, WebSocket socket` | `Result<Unit, Error>` | 业务/IO |

---

## 8. 使用的技术

- 非泛型协议。

---

## 9. 需要的支撑

- 语言：protocol、Result；
- 运行时：服务器分派；
- 接口：`Context`、`WebSocket`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`WebSocket`、`Error`。

---

## 11. 所有权与并发

可并发；实现自行同步；无全局。

---

## 12. 示例与反例

正确：`handle` 内 receive 循环。  
反例：不 close；多 receiver；忽略取消。

---

## 13. 测试/场景义务

正常收发；关闭；取消；Err；并发连接。

---

## 14. XNull 伪代码

```xnull
protocol WebSocketHandler {
    Result<Unit, Error> handle(Context context, WebSocket socket);
}
```
