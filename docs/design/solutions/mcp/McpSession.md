# `McpSession`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpSession` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `McpProtocolVersion`、`McpServerInfo`、`McpClientInfo`、`McpCapability` |

---

## 1. 定位

一次 MCP 协商后的只读快照：协议版本、服务端/客户端信息、legacy 会话标识、是否已初始化、是否仍打开。

不做：传输、消息队列、会话存储、重连、认证、任务状态。

---

## 2. 设计逻辑

- modern 无协议会话；`McpSession` 只记录本客户端当前选定的版本与对端信息。
- legacy HTTP 可有 `MCP-Session-Id`；stdio 没有；字段用空串表示无，不用 null。
- `_modern` 是冗余但显式的派生快照，避免调用方反复判断版本。
- `_initialized` 表示 `initialize` 完成或 `server/discover` 成功；modern 没有 `notifications/initialized`。
- `_open` 是快照；真正关闭由 `McpClient`/传输负责。
- 不可变；无 close；可共享。
- 会话标识是敏感值：不得写入日志、URL、错误 message。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_protocolVersion` | `McpProtocolVersion` | final | 已选定版本 |
| `_serverInfo` | `McpServerInfo` | final | 服务端声明 |
| `_clientInfo` | `McpClientInfo` | final | 客户端声明 |
| `_sessionIdentifier` | `String` | final | legacy HTTP 会话 id；无则空串 |
| `_modern` | `Bool` | final | 是否 modern |
| `_initialized` | `Bool` | final | 是否完成初始化/发现 |
| `_open` | `Bool` | final | 快照时是否可用 |

不变量：`_modern == isModernMcpProtocolVersion(_protocolVersion)`；sessionIdentifier 非 null；server/client info 非 null。

---

## 4. 生命周期

构造后不可变；无 close；不拥有传输；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpSession(McpProtocolVersion protocolVersion, McpServerInfo serverInfo, McpClientInfo clientInfo, String sessionIdentifier, Bool modern, Bool initialized, Bool open)` | 七参数 | 非 null；modern 与版本一致 | 非法 → panic |

由 `McpClient.initialize` 构造；应用不直接创建。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `protocolVersion` | 协议版本 | 无 | `McpProtocolVersion` | 无 |
| `serverInfo` | 服务端信息 | 无 | `McpServerInfo` | 无 |
| `clientInfo` | 客户端信息 | 无 | `McpClientInfo` | 无 |
| `sessionIdentifier` | legacy 会话 id | 无 | `String` | 无 |
| `hasSessionIdentifier` | 是否有会话 id | 无 | `Bool` | 无 |
| `isModern` | 是否 modern | 无 | `Bool` | 无 |
| `isLegacy` | 是否 legacy | 无 | `Bool` | 无 |
| `isInitialized` | 是否已初始化 | 无 | `Bool` | 无 |
| `isOpen` | 快照是否打开 | 无 | `Bool` | 无 |
| `serverSupports` | 服务端能力 | `McpCapability capability` | `Bool` | null → panic |
| `clientSupports` | 客户端能力 | `McpCapability capability` | `Bool` | null → panic |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `sessionIdentifier` 返回快照值；不得用于日志/URL。
- `serverSupports`/`clientSupports` 分别查两个 info，不交叉。
- `describe` 只输出版本、modern、initialized、open 与是否有 session id，不输出 id 本身。

---

## 8. 使用的技术

- 不可变快照；
- 派生布尔；
- 能力查询委托。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：无；
- 接口：`McpProtocolVersion`、`McpServerInfo`、`McpClientInfo`、`McpCapability`。

---

## 10. 依赖的特性/接口/类

`McpProtocolVersion`、`McpServerInfo`、`McpClientInfo`、`McpCapability`、`isModernMcpProtocolVersion`。

---

## 11. 所有权与并发

不可变；持有 info 引用（不可变）；无资源；可共享；无锁。

---

## 12. 示例与反例

正确：`session.isModern()` 决定是否给每个请求加 `_meta`；`session.serverSupports(McpCapability.Tools)` 决定是否 list。  
反例：把 `McpSession` 当可变连接状态；在 modern 会话发 `initialize`；把 session id 写日志；会话关闭后继续用快照发请求。

---

## 13. 测试/场景义务

modern/legacy 构造；modern 标记不一致拒绝；空/非空 session id；initialized/open 组合；server/client 能力查询；describe 不泄密；快照独立性。

---

## 14. XNull 伪代码

```xnull
class McpSession {
    final McpProtocolVersion _protocolVersion
    final McpServerInfo _serverInfo
    final McpClientInfo _clientInfo
    final String _sessionIdentifier
    final Bool _modern
    final Bool _initialized
    final Bool _open

    McpSession(McpProtocolVersion protocolVersion, McpServerInfo serverInfo,
               McpClientInfo clientInfo, String sessionIdentifier, Bool modern,
               Bool initialized, Bool open) {
        if protocolVersion == null || serverInfo == null || clientInfo == null {
            throw "McpSession: null argument"
        }
        if sessionIdentifier == null { throw "McpSession: null session id" }
        if modern != isModernMcpProtocolVersion(protocolVersion) {
            throw "McpSession: modern flag mismatch"
        }
        _protocolVersion = protocolVersion
        _serverInfo = serverInfo
        _clientInfo = clientInfo
        _sessionIdentifier = sessionIdentifier
        _modern = modern
        _initialized = initialized
        _open = open
    }

    McpProtocolVersion protocolVersion() { return _protocolVersion }
    McpServerInfo serverInfo() { return _serverInfo }
    McpClientInfo clientInfo() { return _clientInfo }
    String sessionIdentifier() { return _sessionIdentifier }
    Bool hasSessionIdentifier() { return _sessionIdentifier != "" }
    Bool isModern() { return _modern }
    Bool isLegacy() { return !_modern }
    Bool isInitialized() { return _initialized }
    Bool isOpen() { return _open }
    Bool serverSupports(McpCapability capability) {
        if capability == null { throw "McpSession.serverSupports: null" }
        return _serverInfo.supports(capability)
    }
    Bool clientSupports(McpCapability capability) {
        if capability == null { throw "McpSession.clientSupports: null" }
        return _clientInfo.supports(capability)
    }

    String describe() {
        return "session " + mcpProtocolVersionText(_protocolVersion)
            + " modern=" + str(_modern)
            + " initialized=" + str(_initialized)
            + " open=" + str(_open)
            + " sessionId=" + str(_sessionIdentifier != "")
    }
}
```
