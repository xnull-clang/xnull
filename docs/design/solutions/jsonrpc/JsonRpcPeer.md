# `JsonRpcPeer`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol JsonRpcPeer` |
| 包 | `xdk.jsonrpc` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`JsonRpcRequest`、`JsonRpcResponse`、`Error` |

---

## 1. 定位

传输无关的 JSON-RPC 对端：发送请求并等待响应、发送通知、回复请求、关闭。

不做：建立连接、帧格式、读写流、认证、TLS、重试、超时、批量、方法分派。

---

## 2. 设计逻辑

- 协议只定义“消息面”，不定义“字节面”；stdio/HTTP/WebSocket 由实现包提供。
- `request` 负责 id 关联；实现必须保证同一时刻未完成 id 唯一。
- `notify` 只接受通知；`request` 只接受带 id 请求；`respond` 发送响应。
- `respond` 用于实现收到请求后回复；具体分派由实现或上层框架负责。
- 不提供 `receive`：入站读取和分派属于传输实现；本协议只约束出站调用面。
- 失败统一 `Result`；关闭后 `Unavailable`；取消由 `Context` 传入；超时由实现按 Context 截止时间映射。
- 无全局连接、无全局 id 生成器、无自动重试。

---

## 3. 表示与不变量

协议无字段。实现保证：

- 每个未完成请求的 id 唯一；
- 响应只投递给 id 匹配的请求；
- 未知/迟到响应被丢弃，不投递给其他请求；
- 通知不产生响应；
- 关闭后所有方法返回 `Unavailable`（`close` 幂等）。

---

## 4. 生命周期

协议无构造；实现决定。资源由实现持有；`close` 幂等；关闭后 `isOpen` 返回 false。

---

## 5. 构造契约

协议无构造；实现必须在构造或初始化时确定传输、超时、最大消息大小与认证配置。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `request` | 发请求并等待响应 | `Context context, JsonRpcRequest request` | `Result<JsonRpcResponse, Error>` | `InvalidArgument`/`Network`/`Timeout`/`Cancelled`/`DataCorrupted`/`Unavailable` |
| `notify` | 发通知 | `Context context, JsonRpcRequest notification` | `Result<Unit, Error>` | `InvalidArgument`/`Network`/`Timeout`/`Cancelled`/`Unavailable` |
| `respond` | 回复请求 | `Context context, JsonRpcResponse response` | `Result<Unit, Error>` | `InvalidArgument`/`Network`/`Cancelled`/`Unavailable` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `request`：request 必须是带 id 请求；通知 → `InvalidArgument`；实现发送后等待匹配 id 的响应。等待必须响应 `Context` 取消与截止时间。
- `notify`：notification 必须是通知；带 id → `InvalidArgument`。实现不得为通知创建待完成项。
- `respond`：response 非 null；id 必须对应已收到的请求；重复回复 → `InvalidArgument`；实现不得缓存响应体。
- `close`：幂等；关闭后不再接受新请求；未完成请求以 `Unavailable` 或 `Cancelled` 结束，具体在实现文档声明。
- `isOpen`：纯读取；关闭后 false。

---

## 8. 使用的技术

- 非泛型协议；
- Result/Context；
- id 关联；
- 单工/双工由实现决定。

---

## 9. 需要的支撑

- 语言：protocol、Result、Unit、Bool；
- 运行时：无（由实现提供）；
- 接口：`Context`、`JsonRpcRequest`、`JsonRpcResponse`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`JsonRpcRequest`、`JsonRpcResponse`、`JsonRpcId`、`Error`。

---

## 11. 所有权与并发

- 请求/响应借用；实现不保留调用方可变容器引用。
- `request` 可并发调用；实现必须序列化 id 分配与响应关联。
- `notify`/`respond` 可并发调用；写操作由实现串行化。
- `close` 可与调用并发；关闭后调用返回 `Unavailable`。
- 实现不得要求调用方加锁。

---

## 12. 示例与反例

正确：`peer.request(context, new JsonRpcRequest(identifier, "tools/list", Json.object()))`。  
反例：用 `request` 发通知；用 `notify` 发带 id 请求；重复回复同一请求；把迟到响应投递给新请求；关闭后继续调用。

---

## 13. 测试/场景义务

请求/响应关联；通知不回复；重复 id 拒绝；未知响应丢弃；取消；超时；关闭幂等；并发请求；响应乱序；最大消息大小；错误响应原样返回。

---

## 14. XNull 伪代码

```xnull
protocol JsonRpcPeer {
    Result<JsonRpcResponse, Error> request(Context context, JsonRpcRequest request);
    Result<Unit, Error> notify(Context context, JsonRpcRequest notification);
    Result<Unit, Error> respond(Context context, JsonRpcResponse response);
    Result<Unit, Error> close();
    Bool isOpen();
}
```

> 实现限制：`request` 必须拒绝通知；`notify` 必须拒绝带 id 请求；`respond` 必须拒绝重复回复与未知 id。协议不定义读取循环，入站分派由实现负责。
