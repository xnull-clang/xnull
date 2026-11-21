# `OpenApiDocument`

| 项 | 值 |
| --- | --- |
| 类型 | `class OpenApiDocument` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `JsonValue`、`JsonObject`、`JsonArray`、`JsonKind`、`Json`、`Error` |

---

## 1. 定位

OpenAPI 3.1 文档的不可变快照：读取 `openapi`/`info`/`jsonSchemaDialect`/`servers`/`paths`/`webhooks`/`components`/`security`/`tags`/`externalDocs`，序列化为 JSON。

不做：完整 OpenAPI 校验、`$ref` 解析、YAML 读写、代码生成、文档 UI。

---

## 2. 设计逻辑

- 构造时校验最低限度的 3.1 结构与必填字段；其余对象保留为 JSON 树。
- 文档版本必须是 `3.1.x`；`info.title` 与 `info.version` 非空。
- `paths` 与 `webhooks` 在 3.1 中都可选；本类统一保存为空对象，序列化时输出 `paths`。
- `components` 保存为对象；builder 负责写入 `schemas`/`securitySchemes`/`responses`/`parameters`。
- 所有 getter 返回浅拷贝；嵌套 JsonValue 按只读约定共享。
- `toJson` 按稳定顺序输出；`toJsonText` 使用 `xdk.codec.Json`。
- `operationCount` 只统计 path item 的标准 HTTP 方法键。
- 无 close；可共享；不可变快照。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_openapi` | `String` | 3.1.x |
| `_info` | `JsonObject` | 必填 |
| `_jsonSchemaDialect` | `String?` | 可选 |
| `_servers` | `JsonArray` | 可空数组 |
| `_paths` | `JsonObject` | 默认空对象 |
| `_webhooks` | `JsonObject` | 默认空对象 |
| `_components` | `JsonObject` | 默认空对象 |
| `_security` | `JsonArray` | 可空数组 |
| `_tags` | `JsonArray` | 可空数组 |
| `_externalDocs` | `JsonObject?` | 可选 |

不变量：openapi 以 `3.1.` 开头；info 含非空 title/version；paths/webhooks/components 非 null；数组非 null；不可变。

---

## 4. 生命周期

`parse`/`fromJson` 创建；无 close；不可变；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `parse(String text)` | JSON 文本 | 非 null | `DataCorrupted`/`InvalidArgument` |
| `fromJson(JsonValue value)` | JSON 值 | 对象 | `InvalidArgument` |

构造器私有；业务代码使用 `parse`/`fromJson` 或 `OpenApiBuilder.build`。

---

## 6. 字段表

见 §3；字段私有；构造时复制顶层对象。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析 JSON 文档 | `String text` | `Result<OpenApiDocument, Error>` | `DataCorrupted`/`InvalidArgument` |
| `fromJson` | 从 JSON 值构建 | `JsonValue value` | `Result<OpenApiDocument, Error>` | `InvalidArgument` |
| `version` | OpenAPI 版本 | 无 | `String` | 无 |
| `info` | info 副本 | 无 | `JsonObject` | 无 |
| `infoTitle` | 文档标题 | 无 | `String` | 无 |
| `infoVersion` | 文档版本 | 无 | `String` | 无 |
| `jsonSchemaDialect` | schema 方言 | 无 | `String?` | 无 |
| `servers` | servers 副本 | 无 | `JsonArray` | 无 |
| `paths` | paths 副本 | 无 | `JsonObject` | 无 |
| `webhooks` | webhooks 副本 | 无 | `JsonObject` | 无 |
| `components` | components 副本 | 无 | `JsonObject` | 无 |
| `security` | security 副本 | 无 | `JsonArray` | 无 |
| `tags` | tags 副本 | 无 | `JsonArray` | 无 |
| `externalDocs` | externalDocs 副本 | 无 | `JsonObject?` | 无 |
| `hasPath` | 是否含路径 | `String path` | `Bool` | 无 |
| `pathItem` | path item 副本 | `String path` | `JsonObject?` | 无 |
| `operationCount` | 操作数 | 无 | `Int` | 无 |
| `toJson` | JSON 对象 | 无 | `JsonObject` | 无 |
| `toJsonValue` | JSON 值 | 无 | `JsonValue` | 无 |
| `toJsonText` | JSON 文本 | `Bool pretty` | `String` | 无 |
| `copy` | 复制 | 无 | `OpenApiDocument` | 无 |

说明：

- `parse` 要求顶层对象；数组/标量返回 `InvalidArgument`。
- `fromJson` 只做最低限度校验；不验证每个 operation/response/schema。
- `version` 返回原始 `openapi` 字符串。
- `jsonSchemaDialect` 缺失返回 null，不返回空串哨兵。
- `pathItem` 缺失返回 null。
- `operationCount` 对每个 path item 统计 `get/put/post/delete/options/head/patch/trace`。
- `toJson` 输出 `openapi`/`info`/`paths`，其余字段非空时输出。
- `toJsonText` 的 `pretty=true` 使用缩进格式。
- `copy` 独立顶层对象；嵌套 JsonValue 仍是共享只读引用。

---

## 8. 使用的技术

- JSON 树快照；
- 最低限度结构校验；
- 稳定序列化顺序；
- 操作计数；
- 浅拷贝。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、List、Result；
- 运行时：`Json.parseObject`、`Json.stringify`、`Json.stringifyPretty`；
- 接口：`JsonValue`、`JsonObject`、`JsonArray`、`JsonKind`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Json`、`JsonValue`、`JsonObject`、`JsonArray`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变快照；getter 返回副本；嵌套 JsonValue 只读共享；可共享；无资源；无取消点；相等按引用身份。

---

## 12. 示例与反例

正确：

```text
OpenApiDocument document = OpenApiDocument.parse(text).value()
Int operations = document.operationCount()
JsonObject paths = document.paths()
```

反例：

- 把 3.0 文档当 3.1 接受；
- 修改 `paths()` 返回值期望文档变化；
- 用 `jsonSchemaDialect()` 的空串判断缺失；
- 期望 `$ref` 被解析；
- 期望完整规范校验。

---

## 13. 测试/场景义务

3.1.0/3.1.1；3.0 拒绝；缺 openapi/info/title/version；paths 缺失；webhooks；servers/tags/security 类型错误；components；jsonSchemaDialect；pathItem/hasPath；operationCount 多方法/非方法键；toJson 顺序；pretty；copy 独立。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
class OpenApiDocument {
    final String _openapi
    final JsonObject _info
    final String? _jsonSchemaDialect
    final JsonArray _servers
    final JsonObject _paths
    final JsonObject _webhooks
    final JsonObject _components
    final JsonArray _security
    final JsonArray _tags
    final JsonObject? _externalDocs

    private OpenApiDocument(String openapi, JsonObject info, String? jsonSchemaDialect,
                            JsonArray servers, JsonObject paths, JsonObject webhooks,
                            JsonObject components, JsonArray security, JsonArray tags,
                            JsonObject? externalDocs) {
        _openapi = openapi
        _info = info.copy()
        _jsonSchemaDialect = jsonSchemaDialect
        _servers = servers.copy()
        _paths = paths.copy()
        _webhooks = webhooks.copy()
        _components = components.copy()
        _security = security.copy()
        _tags = tags.copy()
        if externalDocs != null {
            _externalDocs = externalDocs.copy()
        } else {
            _externalDocs = null
        }
    }

    static Result<OpenApiDocument, Error> parse(String text) {
        if text == null { throw "OpenApiDocument.parse: null text" }
        Result<JsonObject, Error> parsed = Json.parseObject(text)
        if parsed.isErr() { return Err(parsed.error()) }
        return OpenApiDocument.fromJson(JsonValue.object(parsed.value()))
    }

    static Result<OpenApiDocument, Error> fromJson(JsonValue value) {
        if value == null { throw "OpenApiDocument.fromJson: null value" }
        if value.kind() != JsonKind.Object {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OpenAPI document must be an object"))
        }
        JsonObject root = value.asObject() as JsonObject
        JsonValue? versionValue = root.getOrNull("openapi")
        if versionValue == null || versionValue.asString() == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OpenAPI document missing openapi"))
        }
        String version = versionValue.asString() as String
        if !version.startsWith("3.1.") {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OpenAPI document must be 3.1.x"))
        }
        JsonValue? infoValue = root.getOrNull("info")
        if infoValue == null || infoValue.asObject() == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OpenAPI document missing info"))
        }
        JsonObject info = (infoValue.asObject() as JsonObject).copy()
        JsonValue? title = info.getOrNull("title")
        JsonValue? infoVersion = info.getOrNull("version")
        if title == null || title.asString() == null || (title.asString() as String) == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OpenAPI info.title missing"))
        }
        if infoVersion == null || infoVersion.asString() == null
            || (infoVersion.asString() as String) == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OpenAPI info.version missing"))
        }
        String? dialect = null
        JsonValue? dialectValue = root.getOrNull("jsonSchemaDialect")
        if dialectValue != null {
            if dialectValue.asString() == null || (dialectValue.asString() as String) == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenAPI jsonSchemaDialect invalid"))
            }
            dialect = dialectValue.asString() as String
        }
        JsonObject paths = new JsonObject()
        JsonValue? pathsValue = root.getOrNull("paths")
        if pathsValue != null {
            if pathsValue.asObject() == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenAPI paths must be an object"))
            }
            paths = (pathsValue.asObject() as JsonObject).copy()
        }
        JsonObject webhooks = new JsonObject()
        JsonValue? webhooksValue = root.getOrNull("webhooks")
        if webhooksValue != null {
            if webhooksValue.asObject() == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenAPI webhooks must be an object"))
            }
            webhooks = (webhooksValue.asObject() as JsonObject).copy()
        }
        JsonObject components = new JsonObject()
        JsonValue? componentsValue = root.getOrNull("components")
        if componentsValue != null {
            if componentsValue.asObject() == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenAPI components must be an object"))
            }
            components = (componentsValue.asObject() as JsonObject).copy()
        }
        JsonArray servers = new JsonArray()
        JsonValue? serversValue = root.getOrNull("servers")
        if serversValue != null {
            if serversValue.asArray() == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenAPI servers must be an array"))
            }
            servers = (serversValue.asArray() as JsonArray).copy()
        }
        JsonArray security = new JsonArray()
        JsonValue? securityValue = root.getOrNull("security")
        if securityValue != null {
            if securityValue.asArray() == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenAPI security must be an array"))
            }
            security = (securityValue.asArray() as JsonArray).copy()
        }
        JsonArray tags = new JsonArray()
        JsonValue? tagsValue = root.getOrNull("tags")
        if tagsValue != null {
            if tagsValue.asArray() == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenAPI tags must be an array"))
            }
            tags = (tagsValue.asArray() as JsonArray).copy()
        }
        JsonObject? externalDocs = null
        JsonValue? externalValue = root.getOrNull("externalDocs")
        if externalValue != null {
            if externalValue.asObject() == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenAPI externalDocs must be an object"))
            }
            externalDocs = (externalValue.asObject() as JsonObject).copy()
        }
        return Ok(new OpenApiDocument(version, info, dialect, servers, paths,
            webhooks, components, security, tags, externalDocs))
    }

    String version() { return _openapi }
    JsonObject info() { return _info.copy() }

    String infoTitle() {
        return _info.getOr("title", JsonValue.string("")).asString() as String
    }

    String infoVersion() {
        return _info.getOr("version", JsonValue.string("")).asString() as String
    }

    String? jsonSchemaDialect() { return _jsonSchemaDialect }
    JsonArray servers() { return _servers.copy() }
    JsonObject paths() { return _paths.copy() }
    JsonObject webhooks() { return _webhooks.copy() }
    JsonObject components() { return _components.copy() }
    JsonArray security() { return _security.copy() }
    JsonArray tags() { return _tags.copy() }

    JsonObject? externalDocs() {
        if _externalDocs == null { return null }
        return (_externalDocs as JsonObject).copy()
    }

    Bool hasPath(String path) {
        if path == null { return false }
        return _paths.has(path)
    }

    JsonObject? pathItem(String path) {
        if path == null { return null }
        JsonValue? item = _paths.getOrNull(path)
        if item == null || item.asObject() == null { return null }
        return (item.asObject() as JsonObject).copy()
    }

    Int operationCount() {
        List<String> methodNames = ["get", "put", "post", "delete",
            "options", "head", "patch", "trace"]
        Int count = 0
        List<String> pathNames = _paths.keys()
        Int pathIndex = 0
        while pathIndex < pathNames.length() {
            JsonValue? itemValue = _paths.getOrNull(pathNames.get(pathIndex))
            if itemValue != null && itemValue.asObject() != null {
                JsonObject item = itemValue.asObject() as JsonObject
                Int methodIndex = 0
                while methodIndex < methodNames.length() {
                    if item.has(methodNames.get(methodIndex)) {
                        count = count + 1
                    }
                    methodIndex = methodIndex + 1
                }
            }
            pathIndex = pathIndex + 1
        }
        return count
    }

    JsonObject toJson() {
        JsonObject result = new JsonObject()
        result.set("openapi", JsonValue.string(_openapi))
        result.set("info", JsonValue.object(_info.copy()))
        if _jsonSchemaDialect != null {
            result.set("jsonSchemaDialect",
                JsonValue.string(_jsonSchemaDialect as String))
        }
        if _servers.length() > 0 {
            result.set("servers", JsonValue.array(_servers.copy()))
        }
        result.set("paths", JsonValue.object(_paths.copy()))
        if _webhooks.length() > 0 {
            result.set("webhooks", JsonValue.object(_webhooks.copy()))
        }
        if _components.length() > 0 {
            result.set("components", JsonValue.object(_components.copy()))
        }
        if _security.length() > 0 {
            result.set("security", JsonValue.array(_security.copy()))
        }
        if _tags.length() > 0 {
            result.set("tags", JsonValue.array(_tags.copy()))
        }
        if _externalDocs != null {
            result.set("externalDocs", JsonValue.object(
                (_externalDocs as JsonObject).copy()))
        }
        return result
    }

    JsonValue toJsonValue() { return JsonValue.object(self.toJson()) }

    String toJsonText(Bool pretty) {
        if pretty { return Json.stringifyPretty(self.toJsonValue()) }
        return Json.stringify(self.toJsonValue())
    }

    OpenApiDocument copy() {
        return new OpenApiDocument(_openapi, _info, _jsonSchemaDialect,
            _servers, _paths, _webhooks, _components, _security, _tags,
            _externalDocs)
    }
}
```
