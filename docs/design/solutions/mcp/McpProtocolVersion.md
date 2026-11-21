# `McpProtocolVersion`

| 项 | 值 |
| --- | --- |
| 类型 | `enum McpProtocolVersion` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

MCP 协议修订版本：固定日期字符串，区分 legacy 握手时代与 modern 每请求元数据时代。

不做：任意版本字符串、语义版本比较、扩展版本、运行时动态注册版本。

---

## 2. 设计逻辑

- MCP 版本是日期标识（`YYYY-MM-DD`），不是 semver；枚举固定当前公开修订。
- 当前支持 2024-11-05、2025-03-26、2025-06-18、2025-11-25、2026-07-28。
- `2025-11-25` 及更早为 legacy：需要 `initialize`；`2026-07-28` 及以后为 modern：每请求 `_meta`。
- 只允许追加成员；不得改变已有成员的文本或时代判定。
- 解析未知版本返回 `InvalidArgument`；服务端在协商错误中返回支持列表，不把未知值映射到“最新”。
- 文本映射稳定；日志、HTTP 头、`_meta` 使用同一文本。

---

## 3. 表示与不变量

| 成员 | 文本 | 时代 | 说明 |
| --- | --- | --- | --- |
| `V2024_11_05` | `2024-11-05` | legacy | 初始版本；HTTP+SSE 传输已废弃 |
| `V2025_03_26` | `2025-03-26` | legacy | Streamable HTTP 引入 |
| `V2025_06_18` | `2025-06-18` | legacy | 移除 JSON-RPC 批量 |
| `V2025_11_25` | `2025-11-25` | legacy | tasks 实验、elicitation URL、sampling tools |
| `V2026_07_28` | `2026-07-28` | modern | 无状态、`server/discover`、MRTR、订阅流 |

不变量：成员固定；文本唯一；`latestMcpProtocolVersion()` 返回 `V2026_07_28`；legacy/modern 判定与文本表一致。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享；无资源；无取消点。

---

## 5. 构造契约

枚举项直接使用；解析使用 `parseMcpProtocolVersion`。不接受空串、通配符、`"latest"`、`"draft"`。

---

## 6. 字段表

无实例字段；成员表见 §3。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `mcpProtocolVersionText` | 稳定文本 | `McpProtocolVersion version` | `String` | null → panic |
| `parseMcpProtocolVersion` | 文本解析 | `String text` | `Result<McpProtocolVersion, Error>` | `InvalidArgument` |
| `isLegacyMcpProtocolVersion` | 是否 legacy | `McpProtocolVersion version` | `Bool` | null → panic |
| `isModernMcpProtocolVersion` | 是否 modern | `McpProtocolVersion version` | `Bool` | null → panic |
| `latestMcpProtocolVersion` | 最新版本 | 无 | `McpProtocolVersion` | 无 |
| `isSupportedMcpProtocolVersion` | 是否当前支持 | `McpProtocolVersion version` | `Bool` | null → panic |

说明：

- `parseMcpProtocolVersion` 只接受表中五个完整日期；不做大小写/空白归一。
- `isLegacyMcpProtocolVersion` 对四个旧成员返回 true；`isModern...` 只对 `V2026_07_28` 返回 true；两者互斥且覆盖全部成员。
- `latestMcpProtocolVersion` 是编译期常量函数，不读取环境/配置。
- `isSupportedMcpProtocolVersion` 当前对所有成员返回 true；保留给未来移除旧版本时使用。

---

## 8. 使用的技术

- 简单枚举；
- 稳定日期文本；
- 时代分类；
- Result 解析。

---

## 9. 需要的支撑

- 语言：enum、String、Bool、Result；
- 运行时：无；
- 接口：`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

值语义；无资源；可共享；纯函数；无锁。

---

## 12. 示例与反例

正确：`mcpProtocolVersionText(McpProtocolVersion.V2026_07_28)` → `"2026-07-28"`。  
反例：把 `"2026-7-28"` 当合法；把未知版本回退到最新；用字符串比较判断新旧。

---

## 13. 测试/场景义务

五个成员文本往返；未知/空/大小写错误；legacy/modern 判定互斥；最新版本；HTTP 头文本；`_meta` 文本；错误响应中的支持列表。

---

## 14. XNull 伪代码

```xnull
enum McpProtocolVersion {
    V2024_11_05,
    V2025_03_26,
    V2025_06_18,
    V2025_11_25,
    V2026_07_28,
}

String mcpProtocolVersionText(McpProtocolVersion version) {
    if version == null { throw "mcpProtocolVersionText: null" }
    if version == McpProtocolVersion.V2024_11_05 { return "2024-11-05" }
    if version == McpProtocolVersion.V2025_03_26 { return "2025-03-26" }
    if version == McpProtocolVersion.V2025_06_18 { return "2025-06-18" }
    if version == McpProtocolVersion.V2025_11_25 { return "2025-11-25" }
    return "2026-07-28"
}

Result<McpProtocolVersion, Error> parseMcpProtocolVersion(String text) {
    if text == null { throw "parseMcpProtocolVersion: null" }
    if text == "2024-11-05" { return Ok(McpProtocolVersion.V2024_11_05) }
    if text == "2025-03-26" { return Ok(McpProtocolVersion.V2025_03_26) }
    if text == "2025-06-18" { return Ok(McpProtocolVersion.V2025_06_18) }
    if text == "2025-11-25" { return Ok(McpProtocolVersion.V2025_11_25) }
    if text == "2026-07-28" { return Ok(McpProtocolVersion.V2026_07_28) }
    return Err(new BasicError(ErrorKind.InvalidArgument,
        "unknown MCP protocol version: " + text))
}

Bool isLegacyMcpProtocolVersion(McpProtocolVersion version) {
    if version == null { throw "isLegacyMcpProtocolVersion: null" }
    return version != McpProtocolVersion.V2026_07_28
}

Bool isModernMcpProtocolVersion(McpProtocolVersion version) {
    if version == null { throw "isModernMcpProtocolVersion: null" }
    return version == McpProtocolVersion.V2026_07_28
}

McpProtocolVersion latestMcpProtocolVersion() {
    return McpProtocolVersion.V2026_07_28
}

Bool isSupportedMcpProtocolVersion(McpProtocolVersion version) {
    if version == null { throw "isSupportedMcpProtocolVersion: null" }
    return true
}
```
