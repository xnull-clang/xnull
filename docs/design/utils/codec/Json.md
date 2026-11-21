# `Json`

| 项 | 值 |
| --- | --- |
| 类型 | `class Json` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | `JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`JsonOptions`、`Reader`、`Error` |

---

## 1. 定位

JSON 静态入口：文本/字节/Reader 解析、生成、对象/数组解析、路径读取。

不做：对象映射、JSON Schema、JSON Pointer 完整规范、流式 SAX。

---

## 2. 设计逻辑

- 无实例状态；构造器私有。
- `parse*` 返回 `JsonValue`；`parseObject`/`parseArray` 校验 kind。
- `stringify`/`pretty` 由运行时格式化原语；数字保留原始文本。
- `get` 路径由运行时原语；`getString/Int/Bool` 返回 Result。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态命名空间；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Json()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 文本解析 | `String` | `Result<JsonValue, Error>` | `DataCorrupted` |
| `parse` | 带选项 | `String, JsonOptions` | `Result<JsonValue, Error>` | 同上 |
| `parseBytes` | 字节解析 | `Bytes` | `Result<JsonValue, Error>` | 同上 |
| `parseObject` | 对象解析 | `String` | `Result<JsonObject, Error>` | 同上/`InvalidArgument` |
| `parseArray` | 数组解析 | `String` | `Result<JsonArray, Error>` | 同上 |
| `parseReader` | Reader 解析 | `Context, Reader` | `Result<JsonValue, Error>` | `Io`/`DataCorrupted`/`Cancelled` |
| `stringify` | 生成 | `JsonValue` | `String` | 无 |
| `stringifyPretty` | 美化 | `JsonValue` | `String` | 无 |
| `toBytes` | UTF-8 字节 | `JsonValue` | `Bytes` | 无 |
| `get` | 路径读取 | `JsonValue, String` | `JsonValue?` | 无 |
| `getString` | 字符串 | `JsonValue, String` | `Result<String, Error>` | `NotFound`/`InvalidArgument` |
| `getInt` | Int | `JsonValue, String` | `Result<Int, Error>` | 同上 |
| `getBool` | Bool | `JsonValue, String` | `Result<Bool, Error>` | 同上 |
| `object` | 空对象值 | 无 | `JsonValue` | 无 |
| `array` | 空数组值 | 无 | `JsonValue` | 无 |
| `string` | 字符串值 | `String` | `JsonValue` | null → panic |
| `number` | 数字值 | `String` | `JsonValue` | 非法 → panic |
| `bool` | 布尔值 | `Bool` | `JsonValue` | 无 |
| `nullValue` | null 值 | 无 | `JsonValue` | 无 |

---

## 8. 使用的技术

- JSON 解析/格式化；
- 路径读取；
- 值树构造。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Result；
- 运行时：`parseJsonRaw`、`formatJsonRaw`、`parseJsonReaderRaw`、`jsonGetPathRaw`、`toInt`、`toUtf8`、`fromUtf8`；
- 接口：`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`JsonOptions`、`Reader`、`Context`、`Error`。

---

## 10. 依赖的特性/接口/类

`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`JsonOptions`、`Reader`、`Context`、`Error`、JSON 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发；返回新值树。

---

## 12. 示例与反例

正确：`Json.parseObject(text)`；`Json.getInt(v,"port")`。  
反例：把对象当数组；忽略 Result；期望数字转 Double 不丢精度。

---

## 13. 测试/场景义务

对象/数组/标量；深/超深；注释/尾逗号；非法；pretty；路径读取；Reader 取消。

---

## 14. XNull 伪代码

```xnull
class Json {
    private Json() {
    }

    static Result<JsonValue, Error> parse(String text) {
        return Json.parse(text, new JsonOptions())
    }

    static Result<JsonValue, Error> parse(String text, JsonOptions options) {
        if text == null || options == null { throw "Json.parse: null argument" }
        return parseJsonRaw(text, options.copy())
    }

    static Result<JsonValue, Error> parseBytes(Bytes data) {
        if data == null { throw "Json.parseBytes: null" }
        return Json.parse(toUtf8(data))
    }

    static Result<JsonObject, Error> parseObject(String text) {
        Result<JsonValue, Error> value = Json.parse(text)
        if value.isErr() { return Err(value.error()) }
        if !value.value().isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JSON is not object"))
        }
        return Ok(value.value().asObject() as JsonObject)
    }

    static Result<JsonArray, Error> parseArray(String text) {
        Result<JsonValue, Error> value = Json.parse(text)
        if value.isErr() { return Err(value.error()) }
        if !value.value().isArray() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "JSON is not array"))
        }
        return Ok(value.value().asArray() as JsonArray)
    }

    static Result<JsonValue, Error> parseReader(Context context, Reader reader) {
        if context == null || reader == null { throw "Json.parseReader: null argument" }
        return parseJsonReaderRaw(context, reader)
    }

    static String stringify(JsonValue value) {
        if value == null { throw "Json.stringify: null" }
        return formatJsonRaw(value, false)
    }

    static String stringifyPretty(JsonValue value) {
        if value == null { throw "Json.stringifyPretty: null" }
        return formatJsonRaw(value, true)
    }

    static Bytes toBytes(JsonValue value) { return fromUtf8(Json.stringify(value)) }

    static JsonValue? get(JsonValue value, String path) {
        if value == null || path == null { return null }
        return jsonGetPathRaw(value, path)
    }

    static Result<String, Error> getString(JsonValue value, String path) {
        JsonValue? found = Json.get(value, path)
        if found == null { return Err(new BasicError(ErrorKind.NotFound, "path not found")) }
        if !found.isString() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "not string"))
        }
        return Ok(found.asString() as String)
    }

    static Result<Int, Error> getInt(JsonValue value, String path) {
        JsonValue? found = Json.get(value, path)
        if found == null { return Err(new BasicError(ErrorKind.NotFound, "path not found")) }
        if !found.isNumber() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "not number"))
        }
        Result<Long, Error> parsed = (found.asNumber() as JsonNumber).asLong()
        if parsed.isErr() { return Err(parsed.error()) }
        Long value = parsed.value()
        if value < -2147483648 || value > 2147483647 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "int overflow"))
        }
        return Ok(toInt(value))
    }

    static Result<Bool, Error> getBool(JsonValue value, String path) {
        JsonValue? found = Json.get(value, path)
        if found == null { return Err(new BasicError(ErrorKind.NotFound, "path not found")) }
        if !found.isBool() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "not bool"))
        }
        return Ok(found.asBool() as Bool)
    }

    static JsonValue object() { return JsonValue.object(new JsonObject()) }
    static JsonValue array() { return JsonValue.array(new JsonArray()) }
    static JsonValue string(String text) { return JsonValue.string(text) }
    static JsonValue number(String raw) { return JsonValue.number(new JsonNumber(raw)) }
    static JsonValue bool(Bool value) { return JsonValue.bool(value) }
    static JsonValue nullValue() { return JsonValue.nullValue() }
}
```

> `parseJsonRaw`、`formatJsonRaw`、`parseJsonReaderRaw`、`jsonGetPathRaw`、`toInt` 是运行时 JSON 原语；不是 XDK 公共类型。
