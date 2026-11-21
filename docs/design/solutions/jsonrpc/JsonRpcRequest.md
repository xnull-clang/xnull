# `JsonRpcRequest`

| 项 | 值 |
| --- | --- |
| 类型 | `class JsonRpcRequest` |
| 包 | `xdk.jsonrpc` |
| 稳定性 | `preview` |
| 依赖 | `JsonRpcId`、`JsonValue`、`JsonObject`、`Error` |

---

## 1. 定位

JSON-RPC 2.0 请求或通知：方法名、可选参数、可选 id；请求期望响应，通知不期望响应。

不做：方法分派、参数校验、传输、批量、超时、重试、认证。

---

## 2. 设计逻辑

- 单一 class 同时表示请求与通知：两者共享 `jsonrpc`/`method`/`params`，唯一差异是 id 是否存在。
- `_identifier` 可空：null 表示通知；不用 `JsonRpcId` 的 null 哨兵，避免“空 id”与“无 id”混淆。
- 显式 JSON `null` id 不放宽为通知：JSON-RPC 2.0 不鼓励 null id，MCP 更禁止；`parse` 直接拒绝。
- `_parameters` 保留 `JsonValue`，允许按位置（Array）和按名称（Object）；MCP 只使用 Object。
- 构造后不可变；`withParameters` 返回新对象，不修改原对象。
- 不在此类型内置 `_meta`；MCP 的 `_meta` 是 `params` 的保留成员，由 `xdk.mcp` 解释。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_identifier` | `JsonRpcId?` | final | null=通知 |
| `_method` | `String` | final | 非空方法名 |
| `_parameters` | `JsonValue?` | final | null=省略 params；否则 Object/Array |

不变量：`_method` 非空；`_parameters` 为 null 或 Object/Array；通知没有 id；请求 id 非 null。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JsonRpcRequest(String method)` | method | 非空 | 空/null → panic |
| `JsonRpcRequest(String method, JsonValue parameters)` | method/parameters | 非空；parameters 为 Object/Array | 非法 → panic |
| `JsonRpcRequest(JsonRpcId identifier, String method)` | identifier/method | identifier 非 null；method 非空 | 非法 → panic |
| `JsonRpcRequest(JsonRpcId identifier, String method, JsonValue parameters)` | 三参数 | parameters 为 Object/Array | 非法 → panic |
| `parse(JsonValue value)` | value | JSON Object | 其他 → `InvalidArgument` |

`parse` 对缺少 `method`、`jsonrpc != "2.0"`、params 类型错误、id 为 null/小数/对象返回 `InvalidArgument`；对方法名首尾空白不自动修剪，保留原值。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `identifier` | id 或 null | 无 | `JsonRpcId?` | 无 |
| `hasIdentifier` | 是否有 id | 无 | `Bool` | 无 |
| `isNotification` | 是否通知 | 无 | `Bool` | 无 |
| `method` | 方法名 | 无 | `String` | 无 |
| `parameters` | 参数或 null | 无 | `JsonValue?` | 无 |
| `hasParameters` | 是否带参数 | 无 | `Bool` | 无 |
| `withParameters` | 替换参数 | `JsonValue parameters` | `JsonRpcRequest` | null → panic |
| `toJsonValue` | JSON 对象 | 无 | `JsonValue` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<JsonRpcRequest, Error>` | `InvalidArgument` |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `toJsonValue` 总是写 `"jsonrpc":"2.0"`；有 id 时写 `id`；有 params 时原样写 `params`。
- `withParameters` 保留 id 与方法；传 null 是合同错误，不用 null 表示“删除参数”；删除参数请构造新通知/请求。
- `describe` 只输出方法名与 id 是否存在，不输出参数内容，避免日志泄密。
- `parse` 不校验方法名是否已注册；分派失败由 Peer/MCP 层返回 `MethodNotFound`。

---

## 8. 使用的技术

- 不可变值对象；
- 可空 id；
- JSON 值树；
- 严格解析。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Result；
- 运行时：无；
- 接口：`JsonRpcId`、`JsonValue`、`JsonObject`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`JsonRpcId`、`JsonValue`、`JsonObject`、`JsonKind`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；`parameters` 返回内部 JSON 值的引用，但 `JsonValue` 包装不可变，内部 Object/Array 可变；需要独立修改时调用方自行 `copy`。无资源；可共享；无锁。

---

## 12. 示例与反例

正确：`new JsonRpcRequest(new JsonRpcId(1L), "tools/list", Json.object())`。  
反例：用 null id 表示通知；把 params 传成 String；解析后修改原 JSON 对象并期望请求同步变化；把方法名空串当合法。

---

## 13. 测试/场景义务

请求/通知构造；id 缺失与 null 区分；params 省略/Object/Array；非法 params；`jsonrpc` 缺失/错误；空方法名；withParameters 独立性；toJsonValue 往返；describe 不含参数。

---

## 14. XNull 伪代码

```xnull
class JsonRpcRequest {
    final JsonRpcId? _identifier
    final String _method
    final JsonValue? _parameters

    JsonRpcRequest(String method) {
        if method == null || method == "" {
            throw "JsonRpcRequest: empty method"
        }
        _identifier = null
        _method = method
        _parameters = null
    }

    JsonRpcRequest(String method, JsonValue parameters) {
        if method == null || method == "" {
            throw "JsonRpcRequest: empty method"
        }
        if parameters == null || (!parameters.isObject() && !parameters.isArray()) {
            throw "JsonRpcRequest: params must be object or array"
        }
        _identifier = null
        _method = method
        _parameters = parameters
    }

    JsonRpcRequest(JsonRpcId identifier, String method) {
        if identifier == null { throw "JsonRpcRequest: null identifier" }
        if method == null || method == "" {
            throw "JsonRpcRequest: empty method"
        }
        _identifier = identifier
        _method = method
        _parameters = null
    }

    JsonRpcRequest(JsonRpcId identifier, String method, JsonValue parameters) {
        if identifier == null { throw "JsonRpcRequest: null identifier" }
        if method == null || method == "" {
            throw "JsonRpcRequest: empty method"
        }
        if parameters == null || (!parameters.isObject() && !parameters.isArray()) {
            throw "JsonRpcRequest: params must be object or array"
        }
        _identifier = identifier
        _method = method
        _parameters = parameters
    }

    static Result<JsonRpcRequest, Error> parse(JsonValue value) {
        if value == null { throw "JsonRpcRequest.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcRequest: not an object"))
        }
        JsonObject object = value.asObject()
        JsonValue? version = object.getOrNull("jsonrpc")
        if version == null || !version.isString() || version.asString() != "2.0" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcRequest: jsonrpc must be 2.0"))
        }
        JsonValue? methodValue = object.getOrNull("method")
        if methodValue == null || !methodValue.isString() || methodValue.asString() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcRequest: invalid method"))
        }
        JsonValue? parameters = object.getOrNull("params")
        if parameters != null && !parameters.isObject() && !parameters.isArray() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcRequest: params must be object or array"))
        }
        JsonValue? identifierValue = object.getOrNull("id")
        if identifierValue == null {
            return Ok(new JsonRpcRequest(methodValue.asString()).withOptionalParameters(parameters))
        }
        if identifierValue.isNull() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "JsonRpcRequest: null id"))
        }
        Result<JsonRpcId, Error> identifier = JsonRpcId.parse(identifierValue)
        if identifier.isErr() { return Err(identifier.error()) }
        if parameters == null {
            return Ok(new JsonRpcRequest(identifier.value(), methodValue.asString()))
        }
        return Ok(new JsonRpcRequest(identifier.value(), methodValue.asString(), parameters))
    }

    private JsonRpcRequest withOptionalParameters(JsonValue? parameters) {
        if parameters == null { return self }
        return new JsonRpcRequest(_method, parameters)
    }

    JsonRpcId? identifier() { return _identifier }
    Bool hasIdentifier() { return _identifier != null }
    Bool isNotification() { return _identifier == null }
    String method() { return _method }
    JsonValue? parameters() { return _parameters }
    Bool hasParameters() { return _parameters != null }

    JsonRpcRequest withParameters(JsonValue parameters) {
        if parameters == null { throw "JsonRpcRequest.withParameters: null" }
        if _identifier == null {
            return new JsonRpcRequest(_method, parameters)
        }
        return new JsonRpcRequest(_identifier, _method, parameters)
    }

    JsonValue toJsonValue() {
        JsonObject object = new JsonObject()
        object.set("jsonrpc", JsonValue.string("2.0"))
        if _identifier != null { object.set("id", _identifier.toJsonValue()) }
        object.set("method", JsonValue.string(_method))
        if _parameters != null { object.set("params", _parameters) }
        return JsonValue.object(object)
    }

    String describe() {
        if _identifier == null { return "notification " + _method }
        return "request " + _method + " " + _identifier.describe()
    }
}
```

> 伪代码中的 `withOptionalParameters` 是私有辅助构造路径；它不接收 `null` 作为参数值，只在 `params` 缺失时返回原通知。
