# `McpContent`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpContent` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `McpResource`、`JsonObject`、`JsonValue`、`Error` |

---

## 1. 定位

MCP 内容块：文本、图像、音频、资源链接、内嵌资源、资源读取内容；用于工具结果、prompt 消息和资源读取。

不做：MIME 嗅探、Base64 解码、图像缩放、内容审查、annotations（X）。

---

## 2. 设计逻辑

- 单一 class + `_kind` 字符串，避免为五种内容各建子类；与 `JsonValue` 的单一树策略一致。
- 每种 kind 只允许对应字段非 null；构造工厂校验，parse 再校验。
- 图像/音频 `_data` 保存 Base64 文本；本类型不解码、不校验像素/采样率。
- 资源链接使用 `McpResource` 元数据；内嵌资源使用 `McpResource` + `_text` 或 `_blob`。
- `resource_content` 表示 `resources/read` 的裸内容对象：`{uri,mimeType,text|blob}`，不带 `type` 包装；与工具结果里的 `{"type":"resource","resource":...}` 区分。
- 内嵌资源的 `McpResource.name` 允许为空（MCP 的内嵌内容不要求 name）；资源列表项由服务端保证 name。
- `_blob` 保存 Base64 文本；`_text` 与 `_blob` 互斥。
- 构造后不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `String` | final | `text`/`image`/`audio`/`resource_link`/`resource`/`resource_content` |
| `_text` | `String?` | final | 文本或内嵌文本 |
| `_data` | `String?` | final | 图像/音频 Base64 |
| `_mimeType` | `String?` | final | 图像/音频 MIME |
| `_resource` | `McpResource?` | final | 链接/内嵌资源元数据 |
| `_blob` | `String?` | final | 内嵌二进制 Base64 |

不变量：

- `text`：`_text != null`；其余负载为 null。
- `image`/`audio`：`_data`、`_mimeType` 非空；其余负载为 null。
- `resource_link`：`_resource != null`；`_text`/`_data`/`_mimeType`/`_blob` 为 null。
- `resource`：`_resource != null`；`_text` 与 `_blob` 恰有一个非 null；`_data`/`_mimeType` 为 null。
- `resource_content`：`_resource != null`；`_text` 与 `_blob` 恰有一个非 null；`_data`/`_mimeType` 为 null；wire 形态是裸 `{uri,mimeType,text|blob}`。
- kind 只能是六个值之一。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 工厂 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `text(String text)` | text | 非 null | null → panic |
| `image(String data, String mimeType)` | data/mimeType | 非空 | 非法 → panic |
| `audio(String data, String mimeType)` | data/mimeType | 非空 | 非法 → panic |
| `resourceLink(McpResource resource)` | resource | 非 null；uri/name 非空 | 非法 → panic |
| `embeddedText(McpResource resource, String text)` | resource/text | resource.uri/mimeType 非空；text 非 null | 非法 → panic |
| `embeddedBlob(McpResource resource, String blob)` | resource/blob | resource.uri/mimeType 非空；blob 非空 | 非法 → panic |
| `resourceText(McpResource resource, String text)` | resource/text | resource.uri/mimeType 非空；text 非 null | 非法 → panic |
| `resourceBlob(McpResource resource, String blob)` | resource/blob | resource.uri/mimeType 非空；blob 非空 | 非法 → panic |
| `parse(JsonValue value)` | value | JSON Object | 非法 → `InvalidArgument` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 内容类型 | 无 | `String` | 无 |
| `isText` | 是否文本 | 无 | `Bool` | 无 |
| `isImage` | 是否图像 | 无 | `Bool` | 无 |
| `isAudio` | 是否音频 | 无 | `Bool` | 无 |
| `isResourceLink` | 是否资源链接 | 无 | `Bool` | 无 |
| `isResource` | 是否内嵌资源 | 无 | `Bool` | 无 |
| `isResourceContent` | 是否资源读取内容 | 无 | `Bool` | 无 |
| `text` | 文本 | 无 | `String?` | 无 |
| `data` | Base64 数据 | 无 | `String?` | 无 |
| `mimeType` | MIME | 无 | `String?` | 无 |
| `resource` | 资源元数据 | 无 | `McpResource?` | 无 |
| `blob` | 内嵌 Base64 | 无 | `String?` | 无 |
| `toJson` | JSON 对象 | 无 | `JsonObject` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<McpContent, Error>` | `InvalidArgument` |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `mimeType` 对资源链接/内嵌资源返回 `_resource.mimeType()`；其余返回 `_mimeType`。
- `toJson` 对资源链接写 `uri/name/title/description/mimeType`；对内嵌资源写 `resource` 对象（`uri/mimeType/text|blob`）；对 `resource_content` 写裸 `uri/mimeType/text|blob`。
- `parse` 对未知 `type`、缺失字段、`text` 与 `blob` 同时存在、空 Base64 返回 `InvalidArgument`；无 `type` 但含 `uri` 的对象按 `resource_content` 解析。
- `describe` 只输出 kind 与资源 URI 的 scheme，不输出 data/text。

---

## 8. 使用的技术

- 标签联合；
- 静态工厂；
- Base64 文本载荷；
- JSON 构建/解析。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Result；
- 运行时：无；
- 接口：`McpResource`、`JsonObject`、`JsonValue`、`JsonKind`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`McpResource`、`JsonObject`、`JsonValue`、`JsonKind`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；`resource()` 返回 `McpResource` 引用（不可变）；`data`/`text`/`blob` 返回 String 引用；无资源；可共享；无锁。

---

## 12. 示例与反例

正确：`McpContent.text("ok")`；`McpContent.image(base64, "image/png")`；`McpContent.embeddedText(resource, "body")`。  
反例：文本块带 mimeType；图像块没有 mimeType；资源链接没有 name；内嵌资源同时给 text 与 blob；把 Base64 当原始字节。

---

## 13. 测试/场景义务

六个 kind 构造/JSON 往返；资源读取裸内容；空文本；空 Base64；缺失 mimeType；资源链接 name；内嵌 text/blob 互斥；parse 未知 type；describe 不泄密；大内容由传输限制。

---

## 14. XNull 伪代码

```xnull
class McpContent {
    final String _kind
    final String? _text
    final String? _data
    final String? _mimeType
    final McpResource? _resource
    final String? _blob

    private McpContent(String kind, String? text, String? data,
                       String? mimeType, McpResource? resource, String? blob) {
        _kind = kind
        _text = text
        _data = data
        _mimeType = mimeType
        _resource = resource
        _blob = blob
    }

    static McpContent text(String text) {
        if text == null { throw "McpContent.text: null" }
        return new McpContent("text", text, null, null, null, null)
    }

    static McpContent image(String data, String mimeType) {
        if data == null || data == "" { throw "McpContent.image: empty data" }
        if mimeType == null || mimeType == "" {
            throw "McpContent.image: empty mimeType"
        }
        return new McpContent("image", null, data, mimeType, null, null)
    }

    static McpContent audio(String data, String mimeType) {
        if data == null || data == "" { throw "McpContent.audio: empty data" }
        if mimeType == null || mimeType == "" {
            throw "McpContent.audio: empty mimeType"
        }
        return new McpContent("audio", null, data, mimeType, null, null)
    }

    static McpContent resourceLink(McpResource resource) {
        if resource == null { throw "McpContent.resourceLink: null resource" }
        if resource.name() == "" { throw "McpContent.resourceLink: empty name" }
        return new McpContent("resource_link", null, null, null, resource, null)
    }

    static McpContent embeddedText(McpResource resource, String text) {
        if resource == null { throw "McpContent.embeddedText: null resource" }
        if resource.uri() == "" || resource.mimeType() == "" {
            throw "McpContent.embeddedText: resource uri/mimeType required"
        }
        if text == null { throw "McpContent.embeddedText: null text" }
        return new McpContent("resource", text, null, null, resource, null)
    }

    static McpContent embeddedBlob(McpResource resource, String blob) {
        if resource == null { throw "McpContent.embeddedBlob: null resource" }
        if resource.uri() == "" || resource.mimeType() == "" {
            throw "McpContent.embeddedBlob: resource uri/mimeType required"
        }
        if blob == null || blob == "" {
            throw "McpContent.embeddedBlob: empty blob"
        }
        return new McpContent("resource", null, null, null, resource, blob)
    }

    static McpContent resourceText(McpResource resource, String text) {
        if resource == null { throw "McpContent.resourceText: null resource" }
        if resource.uri() == "" || resource.mimeType() == "" {
            throw "McpContent.resourceText: resource uri/mimeType required"
        }
        if text == null { throw "McpContent.resourceText: null text" }
        return new McpContent("resource_content", text, null, null, resource, null)
    }

    static McpContent resourceBlob(McpResource resource, String blob) {
        if resource == null { throw "McpContent.resourceBlob: null resource" }
        if resource.uri() == "" || resource.mimeType() == "" {
            throw "McpContent.resourceBlob: resource uri/mimeType required"
        }
        if blob == null || blob == "" {
            throw "McpContent.resourceBlob: empty blob"
        }
        return new McpContent("resource_content", null, null, null, resource, blob)
    }

    static Result<McpContent, Error> parse(JsonValue value) {
        if value == null { throw "McpContent.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpContent: not an object"))
        }
        JsonObject object = value.asObject()
        JsonValue? typeValue = object.getOrNull("type")
        if typeValue == null {
            if !object.has("uri") {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: missing type"))
            }
            Result<McpResource, Error> resource = McpResource.parse(value)
            if resource.isErr() { return Err(resource.error()) }
            if resource.value().mimeType() == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: resource content requires mimeType"))
            }
            JsonValue? textValue = object.getOrNull("text")
            JsonValue? blobValue = object.getOrNull("blob")
            if textValue != null && blobValue != null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: text and blob are exclusive"))
            }
            if textValue != null {
                if !textValue.isString() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpContent: text must be string"))
                }
                return Ok(McpContent.resourceText(resource.value(), textValue.asString()))
            }
            if blobValue != null {
                if !blobValue.isString() || blobValue.asString() == "" {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpContent: invalid blob"))
                }
                return Ok(McpContent.resourceBlob(resource.value(), blobValue.asString()))
            }
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpContent: missing text or blob"))
        }
        if !typeValue.isString() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpContent: invalid type"))
        }
        String kind = typeValue.asString()
        if kind == "text" {
            JsonValue? textValue = object.getOrNull("text")
            if textValue == null || !textValue.isString() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: missing text"))
            }
            return Ok(McpContent.text(textValue.asString()))
        }
        if kind == "image" || kind == "audio" {
            JsonValue? dataValue = object.getOrNull("data")
            JsonValue? mimeValue = object.getOrNull("mimeType")
            if dataValue == null || !dataValue.isString() || dataValue.asString() == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: missing data"))
            }
            if mimeValue == null || !mimeValue.isString() || mimeValue.asString() == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: missing mimeType"))
            }
            if kind == "image" {
                return Ok(McpContent.image(dataValue.asString(), mimeValue.asString()))
            }
            return Ok(McpContent.audio(dataValue.asString(), mimeValue.asString()))
        }
        if kind == "resource_link" {
            Result<McpResource, Error> resource = McpResource.parse(value)
            if resource.isErr() { return Err(resource.error()) }
            if resource.value().name() == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: resource_link requires name"))
            }
            return Ok(McpContent.resourceLink(resource.value()))
        }
        if kind == "resource" {
            JsonValue? resourceValue = object.getOrNull("resource")
            if resourceValue == null || !resourceValue.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: missing resource"))
            }
            Result<McpResource, Error> resource = McpResource.parse(resourceValue)
            if resource.isErr() { return Err(resource.error()) }
            if resource.value().mimeType() == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: embedded resource requires mimeType"))
            }
            JsonValue? textValue = resourceValue.asObject().getOrNull("text")
            JsonValue? blobValue = resourceValue.asObject().getOrNull("blob")
            if textValue != null && blobValue != null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: text and blob are exclusive"))
            }
            if textValue != null {
                if !textValue.isString() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpContent: text must be string"))
                }
                return Ok(McpContent.embeddedText(resource.value(), textValue.asString()))
            }
            if blobValue != null {
                if !blobValue.isString() || blobValue.asString() == "" {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpContent: invalid blob"))
                }
                return Ok(McpContent.embeddedBlob(resource.value(), blobValue.asString()))
            }
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpContent: missing text or blob"))
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "McpContent: unknown type " + kind))
    }

    String kind() { return _kind }
    Bool isText() { return _kind == "text" }
    Bool isImage() { return _kind == "image" }
    Bool isAudio() { return _kind == "audio" }
    Bool isResourceLink() { return _kind == "resource_link" }
    Bool isResource() { return _kind == "resource" }
    Bool isResourceContent() { return _kind == "resource_content" }
    String? text() { return _text }
    String? data() { return _data }
    String? mimeType() {
        if _mimeType != null { return _mimeType }
        if _resource != null { return _resource.mimeType() }
        return null
    }
    McpResource? resource() { return _resource }
    String? blob() { return _blob }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        if _kind != "resource_content" {
            object.set("type", JsonValue.string(_kind))
        }
        if _kind == "text" {
            object.set("text", JsonValue.string(_text))
        } else if _kind == "image" || _kind == "audio" {
            object.set("data", JsonValue.string(_data))
            object.set("mimeType", JsonValue.string(_mimeType))
        } else if _kind == "resource_link" {
            object.set("uri", JsonValue.string(_resource.uri()))
            object.set("name", JsonValue.string(_resource.name()))
            if _resource.title() != "" {
                object.set("title", JsonValue.string(_resource.title()))
            }
            if _resource.description() != "" {
                object.set("description", JsonValue.string(_resource.description()))
            }
            object.set("mimeType", JsonValue.string(_resource.mimeType()))
        } else if _kind == "resource" {
            JsonObject resourceObject = new JsonObject()
            resourceObject.set("uri", JsonValue.string(_resource.uri()))
            resourceObject.set("mimeType", JsonValue.string(_resource.mimeType()))
            if _text != null {
                resourceObject.set("text", JsonValue.string(_text))
            } else {
                resourceObject.set("blob", JsonValue.string(_blob))
            }
            object.set("resource", JsonValue.object(resourceObject))
        } else {
            object.set("uri", JsonValue.string(_resource.uri()))
            object.set("mimeType", JsonValue.string(_resource.mimeType()))
            if _text != null {
                object.set("text", JsonValue.string(_text))
            } else {
                object.set("blob", JsonValue.string(_blob))
            }
        }
        return object
    }

    String describe() {
        if _resource == null { return "content " + _kind }
        return "content " + _kind + " " + _resource.uri()
    }
}
```
