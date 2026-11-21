# `SessionHandler`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol SessionHandler` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`Session`、`Error` |

---

## 1. 定位

会话处理器：接收 `Session` 的打开、消息、关闭、错误四类回调。

不做：accept 循环、连接包装、帧解析、连接计数、重连、背压策略实现、会话持久化。

`SessionHandler` 是 `Server.serve` 与 `NetworkService.startServer/startClient` 的会话级入口；原始字节场景使用 `ConnectionHandler`。

---

## 2. 设计逻辑

- 单会话回调由 `Session.run` 串行调用：`onOpen` → `onMessage` 零或多次 → `onError` 至多一次 → `onClose` 恰好一次。
- `onOpen` 返回 `Err` 立即终止；运行时随后调用 `onError` 与 `onClose`。
- `onMessage` 返回 `Err` 立即终止；运行时随后调用 `onError` 与 `onClose`。
- `onError` 只报告失败；返回值不改变关闭流程，只用于诊断。
- `onClose` 在会话关闭后调用；`cause` 为 null 表示有序 EOF/主动关闭，非 null 表示错误或取消。
- handler 不拥有 `Session`；运行时拥有并最终关闭连接。handler 可调用 `session.close()` 提前终止。
- 一个 handler 实例可被多个会话共享；每会话状态放在 `Session` 属性或 handler 自行同步。
- 消息是读取块，不是协议帧；分帧由实现负责。
- 无泛型；不提供 `onHeartbeat`；心跳由 `HeartbeatPolicy` 与读截止实现。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- 对同一会话，四类回调不并发；
- 不在 `onClose` 后再收到 `onMessage`；
- 不保留 `message` 的引用，除非复制；
- 不替换/包装传入的 `Session`；
- 不递归调用 `Session.run`；
- 返回值只表达可恢复失败，不用异常控制流程。

---

## 4. 生命周期

协议无构造；实现由调用方创建并持有。handler 生命周期可长于单个会话；会话结束后仍可复用。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `onOpen` | 会话已建立 | `Context context, Session session` | `Result<Unit, Error>` | 业务/初始化失败；终止会话 |
| `onMessage` | 收到消息块 | `Context context, Session session, Bytes message` | `Result<Unit, Error>` | 业务/解析失败；终止会话 |
| `onClose` | 会话已关闭 | `Context context, Session session, Error? cause` | `Result<Unit, Error>` | 清理失败；仅诊断 |
| `onError` | 会话发生错误 | `Context context, Session session, Error error` | `Result<Unit, Error>` | 诊断失败；不改变关闭流程 |

说明：

- `context` 与会话生命周期绑定；取消后 handler 应尽快返回。
- `session` 借用；可读 ID、连接、属性、计数，可 `send`/`close`。
- `message` 借用；只在本次回调内有效；长度受 `ServiceOptions.readBufferBytes` 约束。
- `cause == null` 表示正常 EOF 或主动关闭；`cause.kind() == Cancelled` 表示取消。
- `onError` 可在 `onOpen` 失败后立即调用；此时尚未收到任何 `onMessage`。
- `onClose` 必须执行；即使 `onOpen` 失败也要释放资源。

---

## 8. 使用的技术

- 非泛型协议；
- 会话生命周期；
- 借用消息；
- 串行回调；
- Result 失败通道。

---

## 9. 需要的支撑

- 语言：protocol、Context、Bytes、Result、可空引用；
- 运行时：`Session.run` 或服务端分派；
- 接口：`Session`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`Bytes`、`Session`、`Error`、`ErrorKind`、`Session.run`。

---

## 11. 所有权与并发

`Session` 借用；`message` 借用；实现可被多会话共享；同一会话回调串行；不同会话可并发。
实现若持有可变状态，必须自行同步；不得假设运行时加锁。

---

## 12. 示例与反例

正确：`onOpen` 在 `session.setAttribute` 写入协议状态；`onMessage` 分帧后 `session.send` 响应；`onClose` 清理。  
反例：在 `onMessage` 保存 `message` 引用；在 handler 字段保存单会话状态导致串话；`onClose` 不释放资源；在 `onOpen` 递归 `session.run`；把 `onError` 当可恢复重试。

---

## 13. 测试/场景义务

正常打开/消息/关闭；EOF；对端重置；`onOpen` 失败；`onMessage` 失败；`onClose` 失败；取消；心跳超时；多会话并发；共享 handler 状态；消息借用不保留；重复 close；错误顺序（`onError` 在 `onClose` 前）。

---

## 14. XNull 伪代码

```xnull
protocol SessionHandler {
    Result<Unit, Error> onOpen(Context context, Session session);

    Result<Unit, Error> onMessage(Context context, Session session,
        Bytes message);

    Result<Unit, Error> onClose(Context context, Session session,
        Error? cause);

    Result<Unit, Error> onError(Context context, Session session,
        Error error);
}
```
