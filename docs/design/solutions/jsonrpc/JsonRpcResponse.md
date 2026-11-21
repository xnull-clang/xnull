# `JsonRpcResponse`

| 项 | 值 |
| --- | --- |
| 类型 | `class JsonRpcResponse` |
| 包 | `xdk.jsonrpc` |
| 稳定性 | `preview` |
| 依赖 | `JsonRpcId`、`JsonRpcError`、`JsonValue`、`Error` |

---

## 1. 定位

JSON-RPC 2.0 响应：成功结果或错误；通过 id 关联原请求。

不做：请求构造、方法分派、传输、批量、重试、错误恢复策略。

---

## 2. 设计逻辑

- 响应只有两种形态：`result` 或 `error`；用 `_hasResult` 区分“结果键存在且值为 null”和“没有结果”。
- `_identifier` 可空：仅当原始请求 id 无法读取（解析错误/非法请求）时，错误响应的 id 为 null。
- 成功响应禁止 `error`；错误响应禁止 `result`；构造与 parse 都强制互斥。
- 结果保留 `JsonValue` 原树；不在本类型做 MCP 语义解释。
- 构造后不可变；可共享；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_identifier` | `JsonRpcId?` | final | 通常非 null；解析失败时可为 null |
| `_hasResult` | `Bool` | final | true=成功响应 |
| `_result` | `JsonValue?` | final | 成功值；可为 JSON null |
| `_error` | `JsonRpcError?` | final | 错误；与 result 互斥 |

不变量：`_hasResult` 为 true 时 `_result != null` 且 `_error == null`；为 false 时 `_error != null` 且 `_result == null`。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `success(JsonRpcId identifier, JsonValue result)` | identifier/result | 非 null | null → panic |
| `failure(JsonRpcId? identifier, JsonRpcError error)` | identifier/error | error 非 null；identifier 可为 null | error null → panic |
| `parse(JsonValue value)` | value | JSON Object | 非法 → `InvalidArgument` |

私有构造统一校验互斥；外部只能通过两个静态入口创建。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `identifier` | 关联 id | 无 | `JsonRpcId?` | 无 |
| `hasIdentifier` | 是否有 id | 无 | `Bool` | 无 |
| `isSuccess` | 是否成功 | 无 | `Bool` | 无 |
| `hasResult` | 是否有 result 键 | 无 | `Bool` | 无 |
| `result` | 结果值 | 无 | `JsonValue?` | 无 |
| `error` | 错误值 | 无 | `JsonRpcError?` | 无 |
| `toJsonValue` | JSON 对象 | 无 | `JsonValue` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<JsonRpcResponse, Error>` | `InvalidArgument` |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `isSuccess` 等价于 `_hasResult`；错误响应 `result()` 返回 null，成功响应 `error()` 返回 null。
- `parse` 必须看到且只看到一个 `result`/`error` 键；两个都有或都没有 → `InvalidArgument`。
- 错误响应 id 缺失或显式为 null 都映射为 `_identifier == null`；成功响应 id 缺失 → `InvalidArgument`。
- `toJsonValue` 对错误响应写 `id:null` 仅当 `_identifier == null`；这是 JSON-RPC 规定的未知 id 形态。
- `describe` 只输出 id 与成功/错误码，不输出 result/error.data。

---

## 8. 使用的技术

- 互斥标签；
- 可空关联 id；
- JSON 值树；
- 严格解析。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：无；
- 接口：`JsonRpcId`、`JsonRpcError`、`JsonValue`、`JsonObject`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`JsonRpcId`、`JsonRpcError`、`JsonValue`、`JsonObject`、`JsonKind`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；`result`/`error` 返回内部引用；`JsonValue` 包装不可变，内部 Object/Array 可变；需要修改时调用方自行 `copy`。无资源；可共享；无锁。

---

## 12. 示例与反例

正确：`JsonRpcResponse.success(identifier, Json.object())`；`JsonRpcResponse.failure(null, JsonRpcError.parseError("bad json"))`。  
反例：同时设置 result 与 error；用 null result 表示错误；成功响应不带 id；把 error.data 直接写入日志。

---

## 13. 测试/场景义务

成功/错误构造；result 为 JSON null；result 与 error 互斥；id 缺失/显式 null；parse 两个键/无键；错误码保留；toJsonValue 往返；describe 不泄密。

---

## 14. XNull 伪代码

```xnull
class JsonRpcResponse {
    final JsonRpcId? _identifier
    final Bool _hasResult
    final JsonValue? _result
    final JsonRpcError? _error

    private JsonRpcResponse(JsonRpcId? identifier, Bool hasResult,
                            JsonValue? result, JsonRpcError? error) {
        _identifier = identifier
        _hasResult = hasResult
        _result = result
        _error = error
    }

    static JsonRpcResponse success(JsonRpcId identifier, JsonValue result) {
        if identifier == null { throw "JsonRpcResponse.success: null identifier" }
        if result == null { throw "JsonRpcResponse.success: null result" }
        return new JsonRpcResponse(identifier, true, result, null)
    }

    static JsonRpcResponse failure(JsonRpcId? identifier, JsonRpcError error) {
        if error == null { throw "JsonRpcResponse.failure: null error" }
        return new JsonRpcResponse(identifier, false, null, error)
    }

    static Result<JsonRpcResponse, Error> parse(JsonValue value) {
        if value == null { throw "JsonRpcResponse.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcResponse: not an object"))
        }
        JsonObject object = value.asObject()
        JsonValue? version = object.getOrNull("jsonrpc")
        if version == null || !version.isString() || version.asString() != "2.0" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcResponse: jsonrpc must be 2.0"))
        }
        JsonValue? resultValue = object.getOrNull("result")
        JsonValue? errorValue = object.getOrNull("error")
        if resultValue != null && errorValue != null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcResponse: result and error are exclusive"))
        }
        if resultValue == null && errorValue == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcResponse: missing result and error"))
        }
        JsonRpcId? identifier = null
        JsonValue? identifierValue = object.getOrNull("id")
        if identifierValue != null && !identifierValue.isNull() {
            Result<JsonRpcId, Error> parsedId = JsonRpcId.parse(identifierValue)
            if parsedId.isErr() { return Err(parsedId.error()) }
            identifier = parsedId.value()
        }
        if resultValue != null {
            if identifier == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "JsonRpcResponse: success requires id"))
            }
            return Ok(JsonRpcResponse.success(identifier, resultValue))
        }
        Result<JsonRpcError, Error> parsedError = JsonRpcError.parse(errorValue)
        if parsedError.isErr() { return Err(parsedError.error()) }
        return Ok(JsonRpcResponse.failure(identifier, parsedError.value()))
    }

    JsonRpcId? identifier() { return _identifier }
    Bool hasIdentifier() { return _identifier != null }
    Bool isSuccess() { return _hasResult }
    Bool hasResult() { return _hasResult }
    JsonValue? result() { return _result }
    JsonRpcError? error() { return _error }

    JsonValue toJsonValue() {
        JsonObject object = new JsonObject()
        object.set("jsonrpc", JsonValue.string("2.0"))
        if _identifier == null {
            object.set("id", JsonValue.nullValue())
        } else {
            object.set("id", _identifier.toJsonValue())
        }
        if _hasResult {
            if _result == null {
                throw "JsonRpcResponse: missing result invariant"
            }
            object.set("result", _result)
        } else {
            if _error == null {
                throw "JsonRpcResponse: missing error invariant"
            }
            object.set("error", _error.toJsonValue())
        }
        return JsonValue.object(object)
    }

    String describe() {
        if _hasResult {
            if _identifier == null { return "response ok" }
            return "response ok " + _identifier.describe()
        }
        if _identifier == null { return "response error " + _error.describe() }
        return "response error " + _identifier.describe() + " " + _error.describe()
    }
}
```
