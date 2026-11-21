# `JsonRpcError`

| 项 | 值 |
| --- | --- |
| 类型 | `class JsonRpcError` |
| 包 | `xdk.jsonrpc` |
| 稳定性 | `preview` |
| 依赖 | `JsonValue`、`JsonObject`、`Error` |

---

## 1. 定位

JSON-RPC 2.0 错误对象：整数错误码、简短消息、可选 data；附带标准错误码工厂。

不做：异常类型层级、错误恢复、HTTP 状态码映射、MCP 专用错误语义、日志记录。

---

## 2. 设计逻辑

- 错误是普通值，不是抛出的异常；Peer/传输把它放进 `JsonRpcResponse.failure`。
- `_code` 为 `Int`，遵循 JSON-RPC 整数错误码；不限制应用自定义码，但文档标出保留区。
- `_message` 非空、单行、简短；不拼接请求体、路径、令牌。
- `_data` 为任意 JSON 值，可为 null；不解释结构，由调用方定义。
- 标准工厂只覆盖 -32700/-32600/-32601/-32602/-32603；服务端自定义错误用 `serverError`。
- 构造后不可变；可共享；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_code` | `Int` | final | 任意 32 位整数 |
| `_message` | `String` | final | 非空、单行 |
| `_data` | `JsonValue?` | final | 可选附加数据 |

不变量：message 非空；message 不含 CR/LF；data 为 null 或合法 JSON 值。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JsonRpcError(Int code, String message)` | code/message | message 非空单行 | 非法 → panic |
| `JsonRpcError(Int code, String message, JsonValue data)` | 三参数 | data 非 null | 非法 → panic |
| `parse(JsonValue value)` | value | JSON Object | 非法 → `InvalidArgument` |

标准工厂：

| 工厂 | 码 | 默认消息 |
| --- | --- | --- |
| `parseError(String detail)` | -32700 | Parse error |
| `invalidRequest(String detail)` | -32600 | Invalid Request |
| `methodNotFound(String method)` | -32601 | Method not found |
| `invalidParams(String detail)` | -32602 | Invalid params |
| `internalError(String detail)` | -32603 | Internal error |
| `serverError(Int code, String message)` | 调用方 | 调用方 |

`detail`/`method` 允许空串；空串时不追加分隔符。工厂返回新对象，不共享可变 data。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `code` | 错误码 | 无 | `Int` | 无 |
| `message` | 消息 | 无 | `String` | 无 |
| `data` | 附加数据 | 无 | `JsonValue?` | 无 |
| `hasData` | 是否有 data | 无 | `Bool` | 无 |
| `withData` | 附加数据 | `JsonValue data` | `JsonRpcError` | null → panic |
| `toJsonValue` | JSON 对象 | 无 | `JsonValue` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<JsonRpcError, Error>` | `InvalidArgument` |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `message` 只做非空与单行校验；不自动截断，超长消息由调用方约束。
- `withData` 保留 code/message，返回新对象。
- `parse` 要求 `code` 为整数 Number、`message` 为非空 String；`data` 可省略或为任意 JSON 值。
- `describe` 输出 `code + " " + message`，不输出 data。

---

## 8. 使用的技术

- 不可变值对象；
- 整数错误码；
- JSON data；
- 标准工厂。

---

## 9. 需要的支撑

- 语言：class、Int、String、Bool、Result；
- 运行时：无；
- 接口：`JsonValue`、`JsonObject`、`JsonNumber`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`JsonValue`、`JsonObject`、`JsonNumber`、`JsonKind`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；`data` 返回内部 JSON 引用；无资源；可共享；无锁。

---

## 12. 示例与反例

正确：`JsonRpcError.invalidParams("missing name")`；`new JsonRpcError(-32020, "Header mismatch", data)`。  
反例：把异常堆栈塞进 message；把令牌写进 data；用 -32000 至 -32099 自造新码（该区间保留）；用浮点错误码。

---

## 13. 测试/场景义务

五个标准工厂；自定义 serverError；message 空串/换行拒绝；data 省略与 JSON null；parse 非法 code/message；withData 独立性；toJsonValue 往返；describe 不含 data。

---

## 14. XNull 伪代码

```xnull
Result<Int, Error> toIntChecked(Long value) {
    if value < -2147483648L || value > 2147483647L {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "JsonRpcError: code out of Int range"))
    }
    return Ok(value as Int)
}

class JsonRpcError {
    final Int _code
    final String _message
    final JsonValue? _data

    JsonRpcError(Int code, String message) {
        if message == null || message == "" {
            throw "JsonRpcError: empty message"
        }
        if message.contains("\n") || message.contains("\r") {
            throw "JsonRpcError: multiline message"
        }
        _code = code
        _message = message
        _data = null
    }

    JsonRpcError(Int code, String message, JsonValue data) {
        if message == null || message == "" {
            throw "JsonRpcError: empty message"
        }
        if message.contains("\n") || message.contains("\r") {
            throw "JsonRpcError: multiline message"
        }
        if data == null { throw "JsonRpcError: null data" }
        _code = code
        _message = message
        _data = data
    }

    static JsonRpcError parseError(String detail) {
        if detail == "" { return new JsonRpcError(-32700, "Parse error") }
        return new JsonRpcError(-32700, "Parse error: " + detail)
    }

    static JsonRpcError invalidRequest(String detail) {
        if detail == "" { return new JsonRpcError(-32600, "Invalid Request") }
        return new JsonRpcError(-32600, "Invalid Request: " + detail)
    }

    static JsonRpcError methodNotFound(String method) {
        if method == "" { return new JsonRpcError(-32601, "Method not found") }
        return new JsonRpcError(-32601, "Method not found: " + method)
    }

    static JsonRpcError invalidParams(String detail) {
        if detail == "" { return new JsonRpcError(-32602, "Invalid params") }
        return new JsonRpcError(-32602, "Invalid params: " + detail)
    }

    static JsonRpcError internalError(String detail) {
        if detail == "" { return new JsonRpcError(-32603, "Internal error") }
        return new JsonRpcError(-32603, "Internal error: " + detail)
    }

    static JsonRpcError serverError(Int code, String message) {
        return new JsonRpcError(code, message)
    }

    static Result<JsonRpcError, Error> parse(JsonValue value) {
        if value == null { throw "JsonRpcError.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcError: not an object"))
        }
        JsonObject object = value.asObject()
        JsonValue? codeValue = object.getOrNull("code")
        if codeValue == null || !codeValue.isNumber() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcError: invalid code"))
        }
        JsonNumber codeNumberValue = codeValue.asNumber()
        if codeNumberValue == null || !codeNumberValue.isInteger() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcError: invalid code"))
        }
        Result<Long, Error> codeNumber = codeNumberValue.asLong()
        if codeNumber.isErr() { return Err(codeNumber.error()) }
        Result<Int, Error> narrowedCode = toIntChecked(codeNumber.value())
        if narrowedCode.isErr() { return Err(narrowedCode.error()) }
        JsonValue? messageValue = object.getOrNull("message")
        if messageValue == null || !messageValue.isString() || messageValue.asString() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcError: invalid message"))
        }
        JsonValue? data = object.getOrNull("data")
        if data == null {
            return Ok(new JsonRpcError(narrowedCode.value(), messageValue.asString()))
        }
        return Ok(new JsonRpcError(narrowedCode.value(), messageValue.asString(), data))
    }

    Int code() { return _code }
    String message() { return _message }
    JsonValue? data() { return _data }
    Bool hasData() { return _data != null }

    JsonRpcError withData(JsonValue data) {
        if data == null { throw "JsonRpcError.withData: null" }
        return new JsonRpcError(_code, _message, data)
    }

    JsonValue toJsonValue() {
        JsonObject object = new JsonObject()
        object.set("code", JsonValue.number(new JsonNumber(str(_code))))
        object.set("message", JsonValue.string(_message))
        if _data != null { object.set("data", _data) }
        return JsonValue.object(object)
    }

    String describe() { return str(_code) + " " + _message }
}
```

> `toIntChecked` 是设计层窄化辅助：JSON 错误码只允许 32 位整数；超出 `Int` 范围返回 `InvalidArgument`，不得静默截断。
