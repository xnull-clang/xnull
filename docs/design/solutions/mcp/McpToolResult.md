# `McpToolResult`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpToolResult` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `McpContent`、`JsonObject`、`JsonValue`、`List` |

---

## 1. 定位

MCP `tools/call` 结果：非结构化内容列表、可选结构化内容、工具执行错误标志。

不做：JSON Schema 校验、业务错误类型、LLM 渲染、结果缓存、任务状态。

---

## 2. 设计逻辑

- 非结构化内容用 `List<McpContent>`；可混合文本/图像/音频/资源链接/内嵌资源。工具结果不得使用 `resource_content`（那是 `resources/read` 的裸内容形态）。
- 结构化内容 `structuredContent` 保留任意 JSON 值（2026 放宽；不再限定 Object）。
- `isError` 只标记**工具执行错误**，不是 JSON-RPC 协议错误；客户端应把内容交给模型自纠。
- 协议错误（未知工具、参数不合法）由 `JsonRpcError` 表达，不进入本类型。
- 构造后不可变；列表返回副本；无 close。
- 输出 Schema 校验由工具层/客户端执行；本类型只携带数据。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_contents` | `List<McpContent>` | final | 非 null；可为空 |
| `_structuredContent` | `JsonValue?` | final | 任意 JSON 值 |
| `_isError` | `Bool` | final | 默认 false |

不变量：contents 非 null；structuredContent 为 null 或合法 JSON；isError 非 null。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpToolResult(List<McpContent> contents)` | contents | 非 null；元素非 null | 非法 → panic |
| `McpToolResult(List<McpContent> contents, JsonValue? structuredContent, Bool isError)` | 三参数 | contents 非 null；元素非 null | 非法 → panic |
| `parse(JsonValue value)` | value | JSON Object | 非法 → `InvalidArgument` |

`structuredContent` 为 null 表示没有结构化内容；不能用 `JsonValue.nullValue()` 表示“没有”，它表示合法的 JSON null。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `contents` | 内容副本 | 无 | `List<McpContent>` | 无 |
| `contentCount` | 内容条数 | 无 | `Int` | 无 |
| `structuredContent` | 结构化内容 | 无 | `JsonValue?` | 无 |
| `hasStructuredContent` | 是否有结构化内容 | 无 | `Bool` | 无 |
| `isError` | 是否执行错误 | 无 | `Bool` | 无 |
| `toJson` | JSON 对象 | 无 | `JsonObject` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<McpToolResult, Error>` | `InvalidArgument` |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `toJson` 总是写 `content` 数组；有结构化内容时写 `structuredContent`；`isError` 只在 true 时写，减少噪声。
- `parse` 要求 `content` 为 Array；缺失 `content` 视为空数组（兼容部分服务端），但 `tools/call` 结果通常应包含内容。
- `parse` 对 `isError` 非 Bool 返回 `InvalidArgument`；缺失为 false。
- `describe` 只输出内容条数与 isError，不输出内容文本。

---

## 8. 使用的技术

- 不可变值对象；
- 内容列表；
- 任意 JSON 结构化值；
- 错误标志。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、List、Result；
- 运行时：无；
- 接口：`McpContent`、`JsonObject`、`JsonValue`、`JsonArray`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`McpContent`、`JsonObject`、`JsonValue`、`JsonArray`、`List`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；`contents()` 返回副本（元素为 `McpContent` 引用，不可变）；`structuredContent` 返回内部 JSON 引用；无资源；可共享；无锁。

---

## 12. 示例与反例

正确：`new McpToolResult([McpContent.text("ok")], null, false)`；`new McpToolResult([], structured, true)`。  
反例：用 `isError` 表示协议错误；把结构化内容限定为 Object；把 `JsonValue.nullValue()` 当“无结构化内容”；把工具输出直接当日志。

---

## 13. 测试/场景义务

空内容；多内容混合；结构化 Object/Array/null/标量；isError true/false；toJson 往返；parse 缺失 content/isError；非法 content 元素；describe 不泄密。

---

## 14. XNull 伪代码

```xnull
class McpToolResult {
    final List<McpContent> _contents
    final JsonValue? _structuredContent
    final Bool _isError

    McpToolResult(List<McpContent> contents) {
        if contents == null { throw "McpToolResult: null contents" }
        Int index = 0
        while index < contents.length() {
            if contents.get(index) == null {
                throw "McpToolResult: null content"
            }
            index = index + 1
        }
        _contents = contents.copy()
        _structuredContent = null
        _isError = false
    }

    McpToolResult(List<McpContent> contents, JsonValue? structuredContent, Bool isError) {
        if contents == null { throw "McpToolResult: null contents" }
        Int index = 0
        while index < contents.length() {
            if contents.get(index) == null {
                throw "McpToolResult: null content"
            }
            index = index + 1
        }
        _contents = contents.copy()
        _structuredContent = structuredContent
        _isError = isError
    }

    static Result<McpToolResult, Error> parse(JsonValue value) {
        if value == null { throw "McpToolResult.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpToolResult: not an object"))
        }
        JsonObject object = value.asObject()
        List<McpContent> contents = []
        JsonValue? contentValue = object.getOrNull("content")
        if contentValue != null {
            if !contentValue.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpToolResult: content must be array"))
            }
            JsonArray array = contentValue.asArray()
            Int index = 0
            while index < array.length() {
                Result<McpContent, Error> parsed = McpContent.parse(array.get(index))
                if parsed.isErr() { return Err(parsed.error()) }
                contents.push(parsed.value())
                index = index + 1
            }
        }
        JsonValue? structuredContent = object.getOrNull("structuredContent")
        Bool isError = false
        JsonValue? errorValue = object.getOrNull("isError")
        if errorValue != null {
            if !errorValue.isBool() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpToolResult: isError must be boolean"))
            }
            isError = errorValue.asBool()
        }
        return Ok(new McpToolResult(contents, structuredContent, isError))
    }

    List<McpContent> contents() { return _contents.copy() }
    Int contentCount() { return _contents.length() }
    JsonValue? structuredContent() { return _structuredContent }
    Bool hasStructuredContent() { return _structuredContent != null }
    Bool isError() { return _isError }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        JsonArray array = new JsonArray()
        Int index = 0
        while index < _contents.length() {
            array.add(JsonValue.object(_contents.get(index).toJson()))
            index = index + 1
        }
        object.set("content", JsonValue.array(array))
        if _structuredContent != null {
            object.set("structuredContent", _structuredContent)
        }
        if _isError { object.set("isError", JsonValue.bool(true)) }
        return object
    }

    String describe() {
        return "tool result contents=" + str(_contents.length())
            + " structured=" + str(_structuredContent != null)
            + " error=" + str(_isError)
    }
}
```
