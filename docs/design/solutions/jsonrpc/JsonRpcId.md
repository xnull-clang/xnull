# `JsonRpcId`

| 项 | 值 |
| --- | --- |
| 类型 | `class JsonRpcId` |
| 包 | `xdk.jsonrpc` |
| 稳定性 | `preview` |
| 依赖 | `JsonValue`、`JsonNumber`、`Error` |

---

## 1. 定位

JSON-RPC 2.0 请求/响应关联标识：String 或整数；用于匹配请求与响应。

不做：`null` id、浮点 id、UUID 生成、全局 id 分配、跨连接去重。

---

## 2. 设计逻辑

- 为什么是 class 而不是 enum：id 是开放值域，不能用固定枚举。
- 为什么不用单一 `String`：整数 id 必须在响应中保持整数形态，不能被格式化成字符串。
- 字段 `_textKind` 区分两种负载；两个负载字段都为 final，构造后不变。
- `wireText` 提供稳定键，供传输层关联待完成请求；String 与整数可能视觉相同，因此内部比较先看 kind。
- `parse` 只接受 JSON String 或整数 Number；小数为 `InvalidArgument`。
- 空 String 在 JSON-RPC 2.0 合法但不推荐；本类型接受空串，文档与测试明确其行为，不用空串表示缺失。
- 值语义：`equals`/`hashCode` 按 kind + 负载；可作 `Map` 键。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_textValue` | `String` | final | String 负载；整数 id 时为空串 |
| `_numberValue` | `Long` | final | 整数负载；String id 时为 0 |
| `_textKind` | `Bool` | final | true=String，false=整数 |

不变量：`_textValue`/`_numberValue` 非 null；`_textKind` 只决定一个负载有效；String 负载可为空串；整数负载为完整 `Long` 范围。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JsonRpcId(String value)` | value | 非 null；可为空串 | null → panic |
| `JsonRpcId(Long value)` | value | 任意 64 位整数 | 无 |
| `parse(JsonValue value)` | value | String 或整数 Number | 其他 → `InvalidArgument` |

`parse` 对 null、Bool、小数、Array、Object 返回 `InvalidArgument`；不抛异常。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `isText` | 是否 String id | 无 | `Bool` | 无 |
| `isInteger` | 是否整数 id | 无 | `Bool` | 无 |
| `textValue` | String 负载 | 无 | `String` | 非 String → panic |
| `numberValue` | 整数负载 | 无 | `Long` | 非整数 → panic |
| `wireText` | 稳定文本 | 无 | `String` | 无 |
| `toJsonValue` | JSON 值 | 无 | `JsonValue` | 无 |
| `equals` | 值相等 | `JsonRpcId other` | `Bool` | null → panic |
| `hashCode` | 哈希 | 无 | `Int` | 无 |
| `describe` | 诊断文本 | 无 | `String` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<JsonRpcId, Error>` | `InvalidArgument` |

说明：

- `wireText` 对 String 返回原串，对整数返回十进制文本；仅用于诊断/关联键，不代替 `toJsonValue`。
- `equals` 要求 kind 相同且负载相同：String `"1"` 与整数 `1` 不相等。
- `hashCode` 使用 kind 与 `wireText` 组合，避免 String/整数碰撞。
- `describe` 输出 `id:"..."` 或 `id:123`；不输出请求参数。
- `parse` 对整数先检查 `isInteger`，再 `asLong`；溢出返回 `InvalidArgument`。

---

## 8. 使用的技术

- 标签联合（kind + 两个负载槽）；
- 值语义；
- 稳定文本键；
- Result 解析。

---

## 9. 需要的支撑

- 语言：class、String、Long、Bool、Result；
- 运行时：`str(Long)`、`parseLong`；
- 接口：`JsonValue`、`JsonNumber`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`JsonValue`、`JsonNumber`、`JsonKind`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；无资源；可共享；无锁；可安全作为 `Map` 键。`toJsonValue` 返回新 JSON 值，不与原 id 共享可变容器。

---

## 12. 示例与反例

正确：`new JsonRpcId("req-1")`；`new JsonRpcId(42L)`；`JsonRpcId.parse(JsonValue.string("a"))`。  
反例：用 `null` 表示通知（通知应省略 id）；把 `"42"` 与 `42L` 当同一个 id；用 `Double` 构造 id；把空串当缺失。

---

## 13. 测试/场景义务

String/整数构造；空串；Long 最小/最大值；parse 六种 JSON kind；小数拒绝；溢出拒绝；equals/hashCode 的 kind 区分；wireText 往返；toJsonValue 保持整数形态。

---

## 14. XNull 伪代码

```xnull
class JsonRpcId {
    final String _textValue
    final Long _numberValue
    final Bool _textKind

    JsonRpcId(String value) {
        if value == null { throw "JsonRpcId: null text" }
        _textValue = value
        _numberValue = 0L
        _textKind = true
    }

    JsonRpcId(Long value) {
        _textValue = ""
        _numberValue = value
        _textKind = false
    }

    static Result<JsonRpcId, Error> parse(JsonValue value) {
        if value == null { throw "JsonRpcId.parse: null value" }
        if value.isString() {
            return Ok(new JsonRpcId(value.asString()))
        }
        if value.isNumber() {
            JsonNumber number = value.asNumber()
            if !number.isInteger() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "JsonRpcId: fractional number"))
            }
            Result<Long, Error> parsed = number.asLong()
            if parsed.isErr() { return Err(parsed.error()) }
            return Ok(new JsonRpcId(parsed.value()))
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "JsonRpcId: expected string or integer"))
    }

    Bool isText() { return _textKind }
    Bool isInteger() { return !_textKind }

    String textValue() {
        if !_textKind { throw "JsonRpcId.textValue: not text" }
        return _textValue
    }

    Long numberValue() {
        if _textKind { throw "JsonRpcId.numberValue: not integer" }
        return _numberValue
    }

    String wireText() {
        if _textKind { return _textValue }
        return str(_numberValue)
    }

    JsonValue toJsonValue() {
        if _textKind { return JsonValue.string(_textValue) }
        return JsonValue.number(new JsonNumber(str(_numberValue)))
    }

    Bool equals(JsonRpcId other) {
        if other == null { throw "JsonRpcId.equals: null other" }
        if _textKind != other.isText() { return false }
        if _textKind { return _textValue == other.textValue() }
        return _numberValue == other.numberValue()
    }

    Int hashCode() {
        if _textKind { return _textValue.hashCode() }
        return _numberValue.hashCode()
    }

    String describe() {
        if _textKind { return "id:" + _textValue }
        return "id:" + str(_numberValue)
    }
}
```
