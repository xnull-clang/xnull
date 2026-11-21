# `xdk.jsonrpc` JSON-RPC 2.0 基础

| 项 | 值 |
| --- | --- |
| 包 | `xdk.jsonrpc` |
| 层 | L8 solutions |
| 依赖 | `xdk.errors`、`xdk.codec`、`xdk.io`、`xdk.execution` |
| 被依赖 | `xdk.mcp`、Agent、CLI 工具、进程间调用 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.jsonrpc` 提供 JSON-RPC 2.0 的值类型、错误类型和传输无关的 Peer 协议：

- `JsonRpcId`：请求/响应关联标识（String 或整数）；
- `JsonRpcRequest`：请求或通知；
- `JsonRpcResponse`：结果或错误响应；
- `JsonRpcError`：错误对象与标准错误码；
- `JsonRpcPeer`：可发送请求、通知和响应的对端协议。

本包不做：

- 传输：stdio、HTTP、WebSocket、SSE 均在调用方或 `xdk.mcp` 实现；
- 连接、重试、认证、限流、超时策略；
- 批量（batch）请求：MCP 自 2025-06-18 起不使用 JSON-RPC 批量；
- 对象映射、反射序列化、JSON Schema；
- JSON-RPC 1.0。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 值对象优先 | `JsonRpcId`/`JsonRpcRequest`/`JsonRpcResponse`/`JsonRpcError` 只在构造后读取 |
| 严格 2.0 | `jsonrpc` 必须为 `"2.0"`；缺失、大小写错误都拒绝 |
| id 不含 null | 请求 id 必须是 String 或整数；通知显式省略 id |
| 结果与错误互斥 | 响应只能有 `result` 或 `error`，不能同时存在 |
| 错误是值 | 协议错误不抛异常；作为 `JsonRpcError` 构造失败响应 |
| 无传输 | 本包不读取/写入任何流；Peer 只定义消息面 |
| 无全局 | 无全局 id 生成器、无全局编解码器、无全局注册表 |
| 边界显式 | 消息大小、深度、超时由传输实现负责 |

---

## 3. 类型索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `JsonRpcId` | class | String/整数 id、比较、JSON 互转 | [`JsonRpcId.md`](JsonRpcId.md) |
| `JsonRpcRequest` | class | 请求/通知、方法、参数 | [`JsonRpcRequest.md`](JsonRpcRequest.md) |
| `JsonRpcResponse` | class | 成功/错误响应 | [`JsonRpcResponse.md`](JsonRpcResponse.md) |
| `JsonRpcError` | class | 错误码、消息、data、标准错误 | [`JsonRpcError.md`](JsonRpcError.md) |
| `JsonRpcPeer` | protocol | 发送请求/通知/响应 | [`JsonRpcPeer.md`](JsonRpcPeer.md) |

X：批量请求、JSON-RPC 1.0 兼容层、取消扩展、进度扩展。MCP 语义（tools/resources/prompts）不在本包，见 [`../mcp/README.md`](../mcp/README.md)。

---

## 4. 跨类型规则

1. `jsonrpc` 字段固定为 `"2.0"`；`JsonRpcRequest.parse` 与 `JsonRpcResponse.parse` 都校验。
2. 请求 id 只允许 String 或整数；`null`、布尔、小数、对象、数组一律 `InvalidArgument`。响应 id 允许省略或为 `null`，仅用于无法读取原请求 id 的错误响应。
3. 无 id 的请求是通知；通知不得收到响应。Peer 的 `notify` 只接受通知，`request` 只接受带 id 请求。
4. `params` 仅允许对象或数组；省略表示无参数。按名称传参由方法处理器校验。
5. 响应必须且只能包含 `result` 或 `error`；`result` 可以是 JSON `null`，但键必须存在。
6. 错误码必须是整数；-32768 至 -32000 为规范保留区，应用自定义错误应放在该区间之外。
7. 同一发送方不得让两个未完成请求使用相同 id；id 复用只发生在原请求已完成后。
8. 不实现批量：收到数组顶层消息按 `InvalidRequest` 处理；MCP 传输不发送批量。
9. JSON 解析/生成统一使用 `xdk.codec`；本包不引入第二套 JSON 实现。
10. 所有 parse 入口对重复键、尾随内容、超深嵌套的行为由 `JsonOptions` 决定；默认严格。

---

## 5. 顶层函数

无；id、请求、响应、错误均由各类型的静态入口构造和解析。

---

## 6. 场景

### J1：请求/响应

`JsonRpcRequest(identifier, "tools/list", parameters)` → Peer `request` → `JsonRpcResponse.success(identifier, result)`。

### J2：通知

`JsonRpcRequest("notifications/initialized")` → Peer `notify`；接收方不得回复。

### J3：错误响应

处理器返回 `JsonRpcError.invalidParams("missing argument")` → `JsonRpcResponse.failure(identifier, error)`。

### J4：解析失败

传输收到非法 JSON 或非法请求 → 本地 `JsonRpcResponse.failure(null, JsonRpcError.parseError(...))`；不得把原始负载回显给对端。

### J5：传输适配

`xdk.mcp` 的 stdio/HTTP 传输实现 `JsonRpcPeer`，但本包不依赖任何传输类型。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 批量请求 | 不做；MCP 不使用 |
| JSON-RPC 1.0 | 不做；只识别 2.0 |
| 取消/进度 | 由 MCP 通知承载，不在基础包定义 |
| 超时/重试 | 传输或调用方负责；Peer 不自动重试 |
| 认证 | 传输层负责；本包不读取凭据 |
| id 生成 | 调用方负责；不提供全局生成器 |
| 大整数 | id 整数使用 `Long`；超出范围拒绝 |
| 浮点 id | 拒绝；JSON-RPC 不建议小数 id |

---

## 8. 安全

- 错误 `message`/`data` 不得包含凭据、令牌、Cookie、完整请求体。
- 解析前限制消息字节数与嵌套深度；解析后再做结构与 id 校验。
- 不得根据对端提供的 `id` 反射任意对象；只接受 String/整数。
- 未知响应 id 应丢弃并记录计数，不得投递给其他请求。
- Peer 实现不得把 `params` 直接拼接为命令、SQL 或路径；业务层必须验证。
- 批量拒绝路径不得放大错误：每个输入最多产生一个错误响应。
