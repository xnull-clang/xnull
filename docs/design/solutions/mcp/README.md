# `xdk.mcp` Model Context Protocol

| 项 | 值 |
| --- | --- |
| 包 | `xdk.mcp` |
| 层 | L8 solutions |
| 依赖 | `xdk.jsonrpc`、`xdk.net.http`、`xdk.codec`、`xdk.io`、`xdk.execution` |
| 被依赖 | XDK CLI、Agent、工具宿主、嵌入式/服务产品 |
| 稳定性 | `preview` |
| 协议版本 | `2026-07-28`（modern）与 `2025-11-25` 及更早（legacy） |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.mcp` 提供 Model Context Protocol 的客户端/服务端类型与传输实现：

- 协议版本协商、能力集合、服务端/客户端身份；
- tools：`tools/list`、`tools/call`；
- resources：`resources/list`、`resources/read`；
- prompts：`prompts/list`、`prompts/get`；
- 内容块：text/image/audio/resource_link/embedded resource；
- 传输：stdio（`Reader`/`Writer`）与 Streamable HTTP（`HttpClient`/`HttpServer`）；
- 客户端：初始化/发现、列出/调用、进度、取消、确认与工具 allowlist；
- 服务端：注册工具/资源/prompt、分派请求、进度通知、关闭；
- 注册表：按名称登记服务器端点，不提供全局注册表。

本包不做：

- LLM 推理、采样结果生成、Agent 编排；
- OAuth 授权服务器、令牌签发、完整 OAuth 客户端流程（由 `xdk.net.http`/应用提供）；
- MCP 任务扩展（tasks）的实现；标记 X；
- `subscriptions/listen` 的完整流式订阅；标记 X；
- 图标、annotations、缓存 TTL 的完整模型；标记 X；
- 任意 shell 执行、命令拼接、文件系统沙箱；
- MCP 注册中心（registry service）或网络目录服务。

MCP 服务端实现只在  `xdk.mcp`；`xdk.core` 不包含 MCP 服务端、传输或注册表。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 版本显式 | 每个 modern 请求携带协议版本与客户端能力；legacy 先握手 |
| 能力驱动 | 只调用对端声明过的能力；缺失能力返回 `MissingRequiredClientCapability` |
| 传输可替换 | `McpTransport` 隔离 stdio/HTTP；上层不读字节 |
| 无全局 | 无全局客户端、服务器、注册表、id 生成器 |
| 服务端只做分派 | 工具/资源/prompt 的业务实现由应用注册；本包不内建 shell |
| 确认与 allowlist | 客户端调用工具前检查 allowlist；敏感工具必须确认 |
| 大小/超时 | 消息、body、SSE 事件、行长度、请求超时都有上限 |
| 取消协作 | `Context` 取消；stdio 发 `notifications/cancelled`；HTTP 关闭响应流 |
| 错误分层 | JSON-RPC 协议错误与工具执行错误（`isError`）分开 |
| 不泄密 | 日志/错误不写令牌、Cookie、完整请求体、工具敏感参数 |

---

## 3. 类型索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `McpProtocolVersion` | enum | 协议版本与 legacy/modern 判定 | [`McpProtocolVersion.md`](McpProtocolVersion.md) |
| `McpCapability` | enum | 客户端/服务端能力 | [`McpCapability.md`](McpCapability.md) |
| `McpServerInfo` | class | 服务端身份、能力、版本、instructions | [`McpServerInfo.md`](McpServerInfo.md) |
| `McpClientInfo` | class | 客户端身份、能力、支持版本 | [`McpClientInfo.md`](McpClientInfo.md) |
| `McpTool` | class | 工具定义与输入/输出 Schema | [`McpTool.md`](McpTool.md) |
| `McpToolResult` | class | 工具结果、结构化内容、执行错误 | [`McpToolResult.md`](McpToolResult.md) |
| `McpContent` | class | 文本/图像/音频/资源链接/内嵌资源/资源读取内容 | [`McpContent.md`](McpContent.md) |
| `McpResource` | class | 资源元数据 | [`McpResource.md`](McpResource.md) |
| `McpPrompt` | class | prompt 模板与解析结果 | [`McpPrompt.md`](McpPrompt.md) |
| `McpSession` | class | 一次协商后的只读快照 | [`McpSession.md`](McpSession.md) |
| `McpServer` | class | 服务端注册、分派、进度、关闭 | [`McpServer.md`](McpServer.md) |
| `McpClient` | class | 初始化/发现、list/call/read/get、取消 | [`McpClient.md`](McpClient.md) |
| `McpTransport` | protocol | 请求/通知/接收/响应/取消/关闭 | [`McpTransport.md`](McpTransport.md) |
| `McpStdioTransport` | class | 换行分隔 JSON-RPC over Reader/Writer | [`McpStdioTransport.md`](McpStdioTransport.md) |
| `McpHttpTransport` | class | Streamable HTTP 客户端/单次 exchange 服务端 | [`McpHttpTransport.md`](McpHttpTransport.md) |
| `McpRegistry` | class | 按名称登记服务器端点 | [`McpRegistry.md`](McpRegistry.md) |

X：tasks 扩展、`subscriptions/listen`、缓存/`ttlMs`/`cacheScope`、icons/annotations、legacy 服务端主动 sampling/roots/elicitation、SSE 断点续传、分页游标自动遍历。

---

## 4. 跨类型规则

### 4.1 协议时代

| 时代 | 版本 | 初始化 | 请求元数据 | HTTP 会话 |
| --- | --- | --- | --- | --- |
| legacy | `2025-11-25` 及更早 | `initialize` + `notifications/initialized` | 连接级能力 | 可有 `MCP-Session-Id` |
| modern | `2026-07-28` 及以后 | 无握手；可用 `server/discover` | 每请求 `_meta` | 无协议会话；不发送 session id |

- modern 请求的 `params._meta` 必须包含 `io.modelcontextprotocol/protocolVersion` 与 `io.modelcontextprotocol/clientCapabilities`；`clientInfo` 为 SHOULD。
- legacy 客户端在 `initialize` 后，后续 HTTP 请求必须带 `MCP-Protocol-Version`。
- 未知/不支持版本：modern 返回 `UnsupportedProtocolVersion`（-32022）；legacy 在 `initialize` 中协商或断开。
- 双重时代实现：modern 请求按 modern 处理；收到 `initialize` 按 legacy 处理。不得在同一连接上混用两种语义。

### 4.2 能力

- 服务端能力：`Tools`、`Resources`、`Prompts`、`Logging`、`Completions`、`Tasks`、`Extensions`、`Experimental` 及其子能力。
- 客户端能力：`Sampling`、`Roots`、`Elicitation`、`Tasks`、`Extensions`、`Experimental` 及其子能力。
- 只调用对端声明过的能力；服务端不得向未声明 sampling/elicitation/roots 的客户端发送对应输入请求。
- `McpServer` 的注册项会推导能力；`McpServerInfo` 声明的能力是上限，不表示每个请求都可用。
- 认证可按请求变化：`tools/list` 可按令牌 scope 裁剪；不得按连接状态变化。

### 4.3 方法与结果

| 方法 | 方向 | 结果类型 | 说明 |
| --- | --- | --- | --- |
| `initialize` | 客户端→服务端 | `InitializeResult` | legacy only |
| `notifications/initialized` | 客户端→服务端 | 无 | legacy only |
| `server/discover` | 客户端→服务端 | `DiscoverResult` | modern 必须实现 |
| `tools/list` | 客户端→服务端 | `ListToolsResult` | 可分页/缓存 |
| `tools/call` | 客户端→服务端 | `CallToolResult` 或 `InputRequiredResult` | 支持 MRTR |
| `resources/list` | 客户端→服务端 | `ListResourcesResult` | 可分页/缓存 |
| `resources/read` | 客户端→服务端 | `ReadResourceResult` 或 `InputRequiredResult` | 可多内容 |
| `prompts/list` | 客户端→服务端 | `ListPromptsResult` | 可分页/缓存 |
| `prompts/get` | 客户端→服务端 | `GetPromptResult` 或 `InputRequiredResult` | 参数必填校验 |
| `notifications/cancelled` | 双向 | 无 | stdio 取消；legacy 服务器也可发 |
| `notifications/progress` | 服务端→客户端 | 无 | 请求级 token |
| `notifications/message` | 服务端→客户端 | 无 | 受请求 `logLevel` 约束 |
| `subscriptions/listen` | 客户端→服务端 | 流 | X |

modern 结果必须含 `resultType`：`complete` 或 `input_required`；缺失按 `complete` 兼容旧服务端。`input_required` 只允许作为 `tools/call`、`resources/read`、`prompts/get` 的结果。

### 4.4 输入请求回调

- sampling/roots/elicitation 不建独立类型：`McpClient` 的 `inputHandler` 接收 `elicitation/create`、`sampling/createMessage`、`roots/list` 三种方法名与参数，返回结果 JSON 对象。
- modern 服务端通过 `InputRequiredResult.inputRequests` 发起；客户端用 `inputResponses` + `requestState` 重试。
- legacy 服务端主动请求（SSE/stdio 反向请求）为 X；`McpServer` 当前只处理 MRTR，不主动发采样/roots/elicitation 请求。
- 输入回调必须由人确认；表单模式禁止收集密码/令牌/支付凭据。

### 4.5 错误码

| 码 | 名称 | 用途 |
| --- | --- | --- |
| -32700 | Parse error | JSON 无法解析 |
| -32600 | Invalid Request | 不是合法 JSON-RPC 请求 |
| -32601 | Method not found | 方法不存在/未实现 |
| -32602 | Invalid params | 参数、未知工具、资源不存在（modern） |
| -32603 | Internal error | 服务端内部错误 |
| -32002 | Resource not found（legacy） | 仅兼容读取；modern 不再发送 |
| -32020 | HeaderMismatch | HTTP 头与 body 不匹配（modern） |
| -32021 | MissingRequiredClientCapability | 缺少客户端能力（modern） |
| -32022 | UnsupportedProtocolVersion | 不支持的协议版本（modern） |

- 工具执行错误不占用 JSON-RPC 错误码：返回 `McpToolResult.isError == true`，让模型自纠。
- 未知工具用 -32602；资源不存在 modern 用 -32602；内部错误用 -32603。
- 本地超时/断连不是 JSON-RPC 错误；由 `Result` 的 `Timeout`/`Network` 表达，不得伪造对端错误码。

### 4.6 大小、计数与时间

- 消息/body/SSE 事件字节数：`Long`；行长度/事件长度上限由传输设置。
- 工具/资源/prompt 数量、分页条数、消息条数：`Int`。
- 超时：`Long timeoutMillis`；进度值/总值为 `Double`；进度 token 为 `JsonRpcId` 兼容的 String/整数。
- 资源 `size` 用 `Long sizeBytes`；未知大小用 null，不用 0 冒充。

### 4.7 生命周期与所有权

- `McpClient`、`McpServer`、传输、注册表都必须 `close()`；`close` 幂等。
- `McpTransport` 的所有权：客户端传输由 `McpClient` 持有；服务端每次 HTTP exchange 创建一个短生命周期传输。
- `McpServer` 不拥有业务 handler 的资源；handler 由应用关闭。
- `McpSession` 是快照；不持有传输，不负责关闭。
- 列表/内容返回副本或只读快照；调用方不得依赖内部可变容器。

---

## 5. 顶层函数

无；协议版本/能力解析使用对应枚举文件的静态入口或顶层函数。

---

## 6. 场景

### M1：XDK CLI 暴露工具

`McpServer` 注册只读工具 → `McpStdioTransport` 包装 stdin/stdout → `serve(context, transport)`；工具 handler 执行业务逻辑，不拼接 shell。

### M2：Agent 消费远程服务器

`McpHttpTransport(HttpClient, Uri)` → `McpClient.initialize(context)` → `server/discover` 或 `initialize` → `listTools` → `callTool`（allowlist + 确认）→ `close`。

### M3：本地 stdio 服务器

CLI 启动子进程，拿到 stdin/stdout 的 `Reader`/`Writer` → `McpStdioTransport` → `McpClient.initialize`。本包不负责进程启动。

### M4：资源读取

`resources/list` → `resources/read(uri)` → `List<McpContent>`；文本/二进制分别处理；URI 必须由应用做路径/权限校验。

### M5：进度与取消

长工具调用带 `progressToken` → 客户端 progress 回调；用户取消 → stdio 发 `notifications/cancelled`，HTTP 关闭响应流。

### M6：MRTR 输入请求

`tools/call` 返回 `InputRequiredResult` → 客户端按 `inputRequests` 调用 elicitation/sampling/roots 回调 → 带 `inputResponses` 与 `requestState` 用新 id 重试。

### M7：注册表

`McpRegistry.register("local", transport)` → `connect(context, "local", clientInfo)` → 客户端初始化；注册表不提供全局单例。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| tasks 扩展 | X；2026 已移出核心，2025 为实验 |
| `subscriptions/listen` | X；当前只支持 list_changed 的服务端通知方法，不实现长流 |
| 缓存 `ttlMs`/`cacheScope` | X；客户端不缓存列表 |
| legacy `logging/setLevel` | X；modern 用请求 `_meta.logLevel` |
| icons/annotations | X；当前丢弃，避免半模型 |
| legacy 服务端主动请求 | X；modern 用 MRTR |
| SSE 断点续传 | 不做；2026 已移除，断流即重发新请求 |
| HTTP 实时进度流 | 当前在响应前缓冲 SSE 事件；真正边执行边推送 X |
| HTTP+SSE（2024-11-05） | 不做 |
| 分页自动遍历 | 当前单页；游标由调用方显式传，X 自动遍历 |
| OAuth 客户端 | 由 `xdk.net.http`/应用组合；本包只消费调用方提供的 Authorization 头 |
| 任务/会话存储 | 应用负责；本包无数据库、无跨进程状态 |
| shell 工具 | 不内建；应用可注册，但必须 allowlist + 确认 + 输入校验 |

---

## 8. 安全

### 8.1 传输

- Streamable HTTP 服务端必须校验 `Origin`；无效 Origin → 403。默认只监听 localhost。
- 所有 HTTP 请求必须认证（OAuth 2.1 Bearer 或应用自定义）；令牌必须绑定 audience，禁止 token passthrough。
- `MCP-Protocol-Version`、`Mcp-Method`、`Mcp-Name` 必须与 body 一致；不一致 → 400 + -32020。
- stdio 的 stdout 只能写 JSON-RPC；日志写 stderr；不得把 stderr 当协议通道。

### 8.2 工具与资源

- 客户端默认拒绝未在 allowlist 的工具；敏感工具调用前必须确认。
- 服务端必须验证工具输入/资源 URI/prompt 参数；不得把未验证字符串拼进 shell、SQL、路径。
- 资源 `file://` 必须做目录穿越与符号链接校验；只暴露允许的根。
- 工具输出可能含不可信内容；客户端渲染前必须转义/限长。
- 工具 annotations 不可信；不能仅凭 `readOnlyHint` 跳过确认。

### 8.3 数据与日志

- 日志不得含 Authorization、Cookie、令牌、密码、完整工具参数。
- 错误 message/data 不回显原始请求体；只给稳定错误码与必要上下文。
- MRTR/elicitation 的 `requestState` 视为攻击者可控输入；服务端必须完整性保护并校验 TTL/主体/请求绑定。
- 采样/elicitation 必须有人工确认；表单模式禁止收集密码/令牌/支付凭据；敏感交互用 URL 模式。

### 8.4 资源上限

- 消息/行/body/SSE 事件有 `Long` 上限；超限返回 `DataCorrupted`/`InvalidArgument`，不继续分配。
- 所有阻塞调用首参 `Context`；超时由调用方 `Context` + `xdk.resilience.Timeout` 或 HTTP 客户端选项提供；本包不内建计时器。
- 列表/内容/工具结果的业务条数上限由应用 handler/调用方控制；传输层只保证字节上限。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Tool`、`@ToolParam`、`@Resource`、`@Prompt` |
| 本包消费 | `@Value`、`@Builder`、`@Serializable` |
| 处理器 | McpAnnotationProcessor（Validate/Generate） |
| 生成物 | 工具/资源/prompt 清单、输入 schema |
| 状态 | 领域注解 planned；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 工具方法 | `@Tool` | 工具清单 |
| 工具参数 | `@ToolParam` | 输入 schema |
| 资源方法 | `@Resource` | 资源清单 |
| prompt 方法 | `@Prompt` | prompt 清单 |
| MCP DTO | `@Value`/`@Builder`/`@Serializable` | 值语义/schema |

### 声明

```x
@Target(Method)
@Retention(Runtime)
@annotation Tool {
    final String name
    final String description
}

@Target(Parameter)
@Retention(Runtime)
@annotation ToolParam {
    final String name
    final String description = ""
    final Bool required = true
}

@Target(Method)
@Retention(Runtime)
@annotation Resource {
    final String uri
    final String mimeType
}

@Target(Method)
@Retention(Runtime)
@annotation Prompt {
    final String name
    final String description = ""
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
class WeatherTools {
    @Tool("weather.current", "Get current weather")
    Result<WeatherReport, Error> current(@ToolParam("city") String city) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
