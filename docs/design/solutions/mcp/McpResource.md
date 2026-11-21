# `McpResource`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpResource` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `JsonObject`、`JsonValue`、`Error` |

---

## 1. 定位

MCP 资源元数据：URI、名称、标题、描述、MIME、字节大小。

不做：资源内容读取、URI 模板、文件系统访问、权限校验、annotations（X）。

---

## 2. 设计逻辑

- 资源由 URI 唯一标识；不假设 `file://`，允许 `https://`、`git://`、自定义 scheme。
- `name` 在资源列表中必填；内嵌资源内容可能没有 name，因此构造函数允许空串，由 `McpContent`/服务端上下文约束。
- `mimeType` 未知时为空串；不用 `application/octet-stream` 冒充已知类型。
- `sizeBytes` 可空：未知大小不能用 0 表示；非空时必须 ≥0。
- 构造后不可变；无 close；可共享。
- URI 只做词法校验（非空、无控制字符/空白）；scheme 语义与路径安全由应用负责。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_uri` | `String` | final | 非空；无控制/空白 |
| `_name` | `String` | final | 可为空（仅内嵌内容） |
| `_title` | `String` | final | 可为空 |
| `_description` | `String` | final | 可为空 |
| `_mimeType` | `String` | final | 可为空 |
| `_sizeBytes` | `Long?` | final | null 或 ≥0 |

不变量：uri 非空且无控制/空白；size null 或 ≥0；不可变。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpResource(String uri, String name)` | uri/name | uri 非空；name 可为空 | 非法 → panic |
| `McpResource(String uri, String name, String title, String description, String mimeType, Long? sizeBytes)` | 全字段 | uri 非空；size null/≥0 | 非法 → panic |
| `parse(JsonValue value)` | value | JSON Object | 非法 → `InvalidArgument` |

`parse` 对缺失 `uri`、非 String uri、负 size 返回 `InvalidArgument`；缺失 name/mimeType 取空串；缺失 size 取 null。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `uri` | 资源 URI | 无 | `String` | 无 |
| `name` | 名称 | 无 | `String` | 无 |
| `title` | 标题 | 无 | `String` | 无 |
| `description` | 描述 | 无 | `String` | 无 |
| `mimeType` | MIME | 无 | `String` | 无 |
| `sizeBytes` | 字节大小 | 无 | `Long?` | 无 |
| `hasSize` | 是否已知大小 | 无 | `Bool` | 无 |
| `toJson` | JSON 对象 | 无 | `JsonObject` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<McpResource, Error>` | `InvalidArgument` |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `toJson` 总是写 `uri`；name 非空才写；`title`/`description`/`mimeType` 非空才写；size 非 null 才写。
- `parse` 忽略 `type` 等上层内容字段；可安全用于 `resource_link` 与内嵌资源对象。
- `describe` 只输出 URI 与 size，不输出内容。

---

## 8. 使用的技术

- 不可变值对象；
- URI 词法校验；
- 可空大小；
- JSON 构建/解析。

---

## 9. 需要的支撑

- 语言：class、String、Long、Bool、Result；
- 运行时：无；
- 接口：`JsonObject`、`JsonValue`、`JsonNumber`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`JsonObject`、`JsonValue`、`JsonNumber`、`JsonKind`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；无资源；可共享；无锁；字符串返回引用（不可变）。

---

## 12. 示例与反例

正确：`new McpResource("file:///project/README.md", "README.md")`；未知 size 用 null。  
反例：用空 URI；把未知 size 写成 0；把 `mimeType` 猜测为 `application/octet-stream`；用 URI 直接打开文件而不做路径校验。

---

## 13. 测试/场景义务

最小/完整构造；空 URI；控制字符/空白；空 name（内嵌）；负 size；size 0；toJson 往返；parse 缺失/非法 uri；忽略未知字段；describe 不泄密。

---

## 14. XNull 伪代码

```xnull
class McpResource {
    final String _uri
    final String _name
    final String _title
    final String _description
    final String _mimeType
    final Long? _sizeBytes

    McpResource(String uri, String name) {
        if !isValidMcpResourceUri(uri) { throw "McpResource: invalid uri" }
        if name == null { throw "McpResource: null name" }
        _uri = uri
        _name = name
        _title = ""
        _description = ""
        _mimeType = ""
        _sizeBytes = null
    }

    McpResource(String uri, String name, String title, String description,
                String mimeType, Long? sizeBytes) {
        if !isValidMcpResourceUri(uri) { throw "McpResource: invalid uri" }
        if name == null { throw "McpResource: null name" }
        if sizeBytes != null && sizeBytes < 0 {
            throw "McpResource: negative size"
        }
        _uri = uri
        _name = name
        _title = title
        _description = description
        _mimeType = mimeType
        _sizeBytes = sizeBytes
    }

    static Bool isValidMcpResourceUri(String uri) {
        if uri == null || uri == "" { return false }
        Int index = 0
        while index < uri.length() {
            String character = uri.substring(index, index + 1)
            if character == " " || character == "\t"
                || character == "\n" || character == "\r" {
                return false
            }
            index = index + 1
        }
        return true
    }

    static Result<McpResource, Error> parse(JsonValue value) {
        if value == null { throw "McpResource.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpResource: not an object"))
        }
        JsonObject object = value.asObject()
        JsonValue? uriValue = object.getOrNull("uri")
        if uriValue == null || !uriValue.isString()
            || !isValidMcpResourceUri(uriValue.asString()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpResource: invalid uri"))
        }
        String name = ""
        JsonValue? nameValue = object.getOrNull("name")
        if nameValue != null && nameValue.isString() { name = nameValue.asString() }
        String title = ""
        JsonValue? titleValue = object.getOrNull("title")
        if titleValue != null && titleValue.isString() { title = titleValue.asString() }
        String description = ""
        JsonValue? descriptionValue = object.getOrNull("description")
        if descriptionValue != null && descriptionValue.isString() {
            description = descriptionValue.asString()
        }
        String mimeType = ""
        JsonValue? mimeValue = object.getOrNull("mimeType")
        if mimeValue != null && mimeValue.isString() { mimeType = mimeValue.asString() }
        Long? sizeBytes = null
        JsonValue? sizeValue = object.getOrNull("size")
        if sizeValue != null {
            if !sizeValue.isNumber() || !sizeValue.asNumber().isInteger() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpResource: invalid size"))
            }
            Result<Long, Error> parsedSize = sizeValue.asNumber().asLong()
            if parsedSize.isErr() { return Err(parsedSize.error()) }
            if parsedSize.value() < 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpResource: negative size"))
            }
            sizeBytes = parsedSize.value()
        }
        return Ok(new McpResource(uriValue.asString(), name, title, description,
            mimeType, sizeBytes))
    }

    String uri() { return _uri }
    String name() { return _name }
    String title() { return _title }
    String description() { return _description }
    String mimeType() { return _mimeType }
    Long? sizeBytes() { return _sizeBytes }
    Bool hasSize() { return _sizeBytes != null }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        object.set("uri", JsonValue.string(_uri))
        if _name != "" { object.set("name", JsonValue.string(_name)) }
        if _title != "" { object.set("title", JsonValue.string(_title)) }
        if _description != "" { object.set("description", JsonValue.string(_description)) }
        if _mimeType != "" { object.set("mimeType", JsonValue.string(_mimeType)) }
        if _sizeBytes != null {
            object.set("size", JsonValue.number(new JsonNumber(str(_sizeBytes))))
        }
        return object
    }

    String describe() {
        return "resource " + _uri + " size=" + str(_sizeBytes)
    }
}
```
