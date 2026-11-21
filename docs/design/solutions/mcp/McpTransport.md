# `McpTransport`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol McpTransport` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`JsonRpcId`、`JsonRpcRequest`、`JsonRpcResponse`、`McpProtocolVersion`、`Error` |

---

## 1. 定位

MCP 消息传输：客户端发送请求/通知/取消，服务端接收请求/回复，双方关闭。

不做：JSON-RPC 语义、MCP 方法分派、认证、连接池、重试、TLS 配置、进程启动。

---

## 2. 设计逻辑

- 在 `JsonRpcPeer` 的出站面上增加 `receive`、`sessionIdentifier` 与通知回调，覆盖 stdio 和 HTTP 两种角色。
- 同一个 transport 一次只承担一个角色：客户端（request/notify/cancel）或服务端（receive/respond）。
- `request` 的 `notificationHandler` 接收请求级通知（progress/message）；这是 HTTP SSE 与 stdio 共有的回调面。
- `cancel` 抽象两种语义：stdio 发 `notifications/cancelled`；HTTP 关闭该请求的 SSE 响应流。
- `sessionIdentifier` 只用于 legacy HTTP；modern 与 stdio 返回 null。
- `receive` 只返回请求/通知，不返回响应；响应关联由 `request` 内部完成。
- 不自动重试、不自动重连、不解释 MCP 能力；失败统一 `Result`。
- 关闭幂等；关闭后所有方法 `Unavailable`。

---

## 3. 表示与不变量

协议无字段。实现保证：

- 请求 id 在未完成集合内唯一；
- 通知不产生响应；
- `receive` 与 `request` 不在同一角色上并发使用；
- `cancel` 只影响指定 id；
- 关闭后不再读写；
- session id 只在 legacy HTTP 出现，且不写入日志。

---

## 4. 生命周期

协议无构造；实现持有连接/流/子进程句柄；`close` 幂等；关闭后 `isOpen` 为 false。

---

## 5. 构造契约

协议无构造；实现必须确定角色、消息大小上限、超时、最大并发请求、认证配置。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `request` | 发请求并等待响应 | `Context context, JsonRpcRequest request, Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler` | `Result<JsonRpcResponse, Error>` | `InvalidArgument`/`Network`/`Timeout`/`Cancelled`/`DataCorrupted`/`Unavailable` |
| `selectProtocolVersion` | 选择协议版本 | `Context context, McpProtocolVersion version` | `Result<Unit, Error>` | `Unsupported`/`Unavailable` |
| `notify` | 发通知 | `Context context, JsonRpcRequest notification` | `Result<Unit, Error>` | `InvalidArgument`/`Network`/`Timeout`/`Cancelled`/`Unavailable` |
| `receive` | 接收下一个请求/通知 | `Context context` | `Result<JsonRpcRequest, Error>` | `Network`/`Timeout`/`Cancelled`/`DataCorrupted`/`Unavailable` |
| `respond` | 回复请求 | `Context context, JsonRpcResponse response` | `Result<Unit, Error>` | `InvalidArgument`/`Network`/`Cancelled`/`Unavailable` |
| `acknowledge` | 确认通知 | `Context context` | `Result<Unit, Error>` | `Network`/`Cancelled`/`Unavailable` |
| `cancel` | 取消请求 | `Context context, JsonRpcId identifier, String reason` | `Result<Unit, Error>` | `InvalidArgument`/`Network`/`Cancelled`/`Unavailable` |
| `sessionIdentifier` | legacy 会话 id | 无 | `String?` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `request`：request 必须带 id；notificationHandler 非 null；响应必须匹配 id；超时/取消后不再投递迟到响应。
- `selectProtocolVersion`：客户端在协商后设置后续请求的版本；stdio no-op；HTTP 更新 `MCP-Protocol-Version`；服务端可据此校验支持列表。
- `notify`：notification 必须无 id。
- `receive`：服务端角色；返回请求或通知（通知作为无 id 的 `JsonRpcRequest`）；不返回响应。
- `respond`：response 非 null；只对应已接收请求；重复回复 `InvalidArgument`。
- `acknowledge`：服务端接受通知后调用；stdio no-op；HTTP 返回 202 无 body；客户端角色 `Unsupported`。
- `cancel`：identifier 非 null；reason 可为空；未知 id 不报错（幂等/竞态）。
- `sessionIdentifier`：legacy HTTP 返回 `MCP-Session-Id`；其他返回 null。
- `close`：关闭流/连接/子进程管道；未完成请求以 `Cancelled`/`Unavailable` 结束。

---

## 8. 使用的技术

- 非泛型协议；
- Result/Context；
- 回调通知；
- 请求 id 关联；
- 角色分离。

---

## 9. 需要的支撑

- 语言：protocol、String、Bool、Result；
- 运行时：由实现提供；
- 接口：`Context`、`JsonRpcId`、`JsonRpcRequest`、`JsonRpcResponse`、`McpProtocolVersion`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`JsonRpcId`、`JsonRpcRequest`、`JsonRpcResponse`、`McpProtocolVersion`、`Error`、`JsonRpcError`。

---

## 11. 所有权与并发

- 请求/响应借用；实现不保留调用方可变容器。
- `request` 可并发；实现必须序列化写与 id 关联。
- `receive` 单消费者；不得并发调用。
- `notify`/`respond`/`cancel` 可并发；写操作串行化。
- `close` 可与调用并发；关闭后调用 `Unavailable`。
- 回调在实现线程/任务上调用；回调不得重入 `request`/`receive`（实现文档必须声明）。

---

## 12. 示例与反例

正确：客户端 `request(context, request, notificationHandler)`；服务端循环 `receive` → `McpServer.handle` → `respond`。  
反例：同一 transport 同时 `request` 与 `receive`；用 `notify` 发请求；HTTP 2026 发 `MCP-Session-Id`；关闭后继续读；把 JSON-RPC 响应交给 `respond`。

---

## 13. 测试/场景义务

请求/响应；通知；服务端 receive/respond；取消 stdio/HTTP；session id legacy；超时；断流；并发请求；重复回复；关闭幂等；关闭后调用；通知回调异常隔离。

---

## 14. XNull 伪代码

```xnull
protocol McpTransport {
    Result<JsonRpcResponse, Error> request(Context context, JsonRpcRequest request,
        Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler);
    Result<Unit, Error> selectProtocolVersion(Context context, McpProtocolVersion version);
    Result<Unit, Error> notify(Context context, JsonRpcRequest notification);
    Result<JsonRpcRequest, Error> receive(Context context);
    Result<Unit, Error> respond(Context context, JsonRpcResponse response);
    Result<Unit, Error> acknowledge(Context context);
    Result<Unit, Error> cancel(Context context, JsonRpcId identifier, String reason);
    String? sessionIdentifier();
    Result<Unit, Error> close();
    Bool isOpen();
}
```

> 实现限制：`request` 必须拒绝通知；`notify` 必须拒绝带 id 请求；`receive` 单消费者；`close` 幂等；通知回调抛出的业务错误不得破坏传输读循环，实现必须隔离并记录计数。
