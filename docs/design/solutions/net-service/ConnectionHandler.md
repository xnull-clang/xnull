# `ConnectionHandler`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol ConnectionHandler` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`Connection`、`Error` |

---

## 1. 定位

原始字节连接处理器：接收 `Connection` 的打开、数据块、关闭、错误四类回调。

不做：accept 循环、连接计数、帧解析、TLS 握手、会话属性、重连、背压策略实现。

适用于自定义二进制协议、隧道、代理或需要自己维护帧缓冲的场景。需要会话级抽象时使用 `SessionHandler`。

---

## 2. 设计逻辑

- 单连接回调由运行时串行调用：`onOpen` → `onMessage` 零或多次 → `onError` 至多一次 → `onClose` 恰好一次。
- `onOpen` 返回 `Err` 立即终止；运行时随后调用 `onError` 与 `onClose`。
- `onMessage` 返回 `Err` 立即终止；运行时随后调用 `onError` 与 `onClose`。
- `onError` 只报告失败；其返回值不改变已经确定的关闭流程，只用于诊断。
- `onClose` 在连接关闭后调用；`cause` 为 null 表示有序 EOF/主动关闭，非 null 表示错误或取消。
- handler 不拥有 `Connection`；运行时拥有并负责最终 `close()`。handler 可调用 `close()` 提前终止，运行时容忍重复关闭。
- handler 不得启动第二个 reader；读取循环由 `Connection.process`/服务运行时拥有。
- 一个 handler 实例可被多个连接共享；每连接状态必须放在 `Connection` 之外或 handler 自行同步。
- 无泛型；消息是读取块，不是协议帧。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- 对同一连接，四类回调不并发；
- 不在 `onClose` 后再收到 `onMessage`；
- 不保留 `message` 的引用，除非复制；
- 不替换/包装传入的 `Connection`；
- 返回值只表达可恢复失败，不用异常控制流程。

---

## 4. 生命周期

协议无构造；实现由调用方创建并持有。handler 生命周期可长于单个连接；连接结束后仍可复用。

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
| `onOpen` | 连接已建立 | `Context context, Connection connection` | `Result<Unit, Error>` | 业务/初始化失败；终止连接 |
| `onMessage` | 收到字节块 | `Context context, Connection connection, Bytes message` | `Result<Unit, Error>` | 业务/解析失败；终止连接 |
| `onClose` | 连接已关闭 | `Context context, Connection connection, Error? cause` | `Result<Unit, Error>` | 清理失败；仅诊断 |
| `onError` | 连接发生错误 | `Context context, Connection connection, Error error` | `Result<Unit, Error>` | 诊断失败；不改变关闭流程 |

说明：

- `context` 与连接生命周期绑定；取消后 handler 应尽快返回。
- `connection` 借用；可读地址、ID、计数，可 `write`/`writeAll`/`close`。
- `message` 借用；只在本次回调内有效；长度受运行时读缓冲约束。
- `cause == null` 表示正常 EOF 或主动关闭；`cause.kind() == Cancelled` 表示取消。
- `onError` 可在 `onOpen` 失败后立即调用；此时尚未收到任何 `onMessage`。
- `onClose` 必须执行；即使 `onOpen` 失败也要释放资源。

---

## 8. 使用的技术

- 非泛型协议；
- 生命周期回调；
- 借用消息；
- 串行回调；
- Result 失败通道。

---

## 9. 需要的支撑

- 语言：protocol、Context、Bytes、Result、可空引用；
- 运行时：`Connection.process` 或服务端分派；
- 接口：`Connection`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`Bytes`、`Connection`、`Error`、`ErrorKind`、`Connection.process`。

---

## 11. 所有权与并发

`Connection` 借用；`message` 借用；实现可被多连接共享；同一连接回调串行；不同连接可并发。
实现若持有可变状态，必须自行同步；不得假设运行时加锁。

---

## 12. 示例与反例

正确：`onOpen` 初始化每连接解析器；`onMessage` 追加到帧缓冲并处理完整帧；`onClose` 释放缓冲。  
反例：在 `onMessage` 保存 `message` 引用；启动第二个 reader；`onClose` 不释放资源；返回 `Err` 后继续写；在 `onOpen` 阻塞等待更多数据。

---

## 13. 测试/场景义务

正常打开/消息/关闭；EOF；对端重置；`onOpen` 失败；`onMessage` 失败；`onClose` 失败；取消；多连接并发；共享 handler 状态；消息借用不保留；重复 close；错误顺序（`onError` 在 `onClose` 前）。

---

## 14. XNull 伪代码

```xnull
protocol ConnectionHandler {
    Result<Unit, Error> onOpen(Context context, Connection connection);

    Result<Unit, Error> onMessage(Context context, Connection connection,
        Bytes message);

    Result<Unit, Error> onClose(Context context, Connection connection,
        Error? cause);

    Result<Unit, Error> onError(Context context, Connection connection,
        Error error);
}
```
