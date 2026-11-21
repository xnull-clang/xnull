# `McpTool`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpTool` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `JsonObject`、`JsonValue`、`Error` |

---

## 1. 定位

MCP 工具定义：名称、标题、描述、输入 Schema、可选输出 Schema、行为注解。

不做：工具执行、参数校验、Schema 编译、权限判定、图标、任务执行策略。

---

## 2. 设计逻辑

- 工具定义是服务端声明；执行由 `McpServer` 的注册 handler 负责。
- `inputSchema`/`outputSchema` 保存 JSON Schema 原树；本包不实现 JSON Schema 校验（X/工具层）。
- 名称按 MCP 建议限制为 1–128 字符，字符集 `[A-Za-z0-9_.-]`；空格/逗号/控制字符拒绝。
- 注解是**不可信提示**：`readOnlyHint` 不能替代确认；`destructiveHint` 默认 true。
- 构造后不可变；JSON 返回新对象；可共享。
- 图标、annotations 的时间/受众字段 X；当前只保留四个布尔行为提示。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 1–128，合法字符集 |
| `_title` | `String` | final | 可为空 |
| `_description` | `String` | final | 可为空 |
| `_inputSchema` | `JsonValue` | final | 必须为 Object |
| `_outputSchema` | `JsonValue?` | final | null 或 Object |
| `_readOnlyHint` | `Bool` | final | 默认 false |
| `_destructiveHint` | `Bool` | final | 默认 true |
| `_idempotentHint` | `Bool` | final | 默认 false |
| `_openWorldHint` | `Bool` | final | 默认 true |

不变量：名称合法；Schema 为 Object；布尔字段非 null；不可变。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpTool(String name, JsonValue inputSchema)` | name/inputSchema | 名称合法；Schema 为 Object | 非法 → panic |
| `McpTool(String name, String title, String description, JsonValue inputSchema, JsonValue? outputSchema, Bool readOnlyHint, Bool destructiveHint, Bool idempotentHint, Bool openWorldHint)` | 全字段 | 同上；outputSchema 为 null/Object | 非法 → panic |
| `parse(JsonValue value)` | value | JSON Object | 非法 → `InvalidArgument` |

名称校验：长度 1–128；只允许 ASCII 字母、数字、`_`、`-`、`.`；不允许前导/尾随空格；不自动修剪。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 工具名 | 无 | `String` | 无 |
| `title` | 显示标题 | 无 | `String` | 无 |
| `description` | 描述 | 无 | `String` | 无 |
| `inputSchema` | 输入 Schema | 无 | `JsonValue` | 无 |
| `outputSchema` | 输出 Schema | 无 | `JsonValue?` | 无 |
| `hasOutputSchema` | 是否有输出 Schema | 无 | `Bool` | 无 |
| `readOnlyHint` | 只读提示 | 无 | `Bool` | 无 |
| `destructiveHint` | 破坏性提示 | 无 | `Bool` | 无 |
| `idempotentHint` | 幂等提示 | 无 | `Bool` | 无 |
| `openWorldHint` | 开放世界提示 | 无 | `Bool` | 无 |
| `toJson` | JSON 对象 | 无 | `JsonObject` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<McpTool, Error>` | `InvalidArgument` |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `toJson` 写 `name`、可选 `title`/`description`、`inputSchema`、可选 `outputSchema`、`annotations` 四个布尔。
- `parse` 对缺失 `name`/`inputSchema`、非 Object Schema、非法名称返回 `InvalidArgument`。
- `parse` 对缺失 `annotations` 使用默认值；未知字段忽略。
- `describe` 只输出名称与是否有输出 Schema，不输出 Schema 内容。

---

## 8. 使用的技术

- 不可变值对象；
- 名称词法校验；
- JSON Schema 原树；
- 布尔注解。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、Result；
- 运行时：无；
- 接口：`JsonObject`、`JsonValue`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`JsonObject`、`JsonValue`、`JsonKind`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；`inputSchema`/`outputSchema` 返回内部 JSON 引用；无资源；可共享；无锁。

---

## 12. 示例与反例

正确：`new McpTool("get_weather", schema)`；`parse` 服务端返回的 `tools/list` 项。  
反例：用 `"get weather"` 作名称；把 `inputSchema` 设成 null；相信 `readOnlyHint` 跳过确认；把 Schema 当已编译验证器。

---

## 13. 测试/场景义务

最小/完整构造；名称长度 0/1/128/129；非法字符；前导/尾随空格；inputSchema 非 Object；outputSchema null/Object；注解默认值；toJson 往返；parse 缺失字段；describe 不泄密。

---

## 14. XNull 伪代码

```xnull
class McpTool {
    final String _name
    final String _title
    final String _description
    final JsonValue _inputSchema
    final JsonValue? _outputSchema
    final Bool _readOnlyHint
    final Bool _destructiveHint
    final Bool _idempotentHint
    final Bool _openWorldHint

    McpTool(String name, JsonValue inputSchema) {
        if !isValidMcpToolName(name) { throw "McpTool: invalid name" }
        if inputSchema == null || !inputSchema.isObject() {
            throw "McpTool: inputSchema must be object"
        }
        _name = name
        _title = ""
        _description = ""
        _inputSchema = inputSchema
        _outputSchema = null
        _readOnlyHint = false
        _destructiveHint = true
        _idempotentHint = false
        _openWorldHint = true
    }

    McpTool(String name, String title, String description, JsonValue inputSchema,
            JsonValue? outputSchema, Bool readOnlyHint, Bool destructiveHint,
            Bool idempotentHint, Bool openWorldHint) {
        if !isValidMcpToolName(name) { throw "McpTool: invalid name" }
        if inputSchema == null || !inputSchema.isObject() {
            throw "McpTool: inputSchema must be object"
        }
        if outputSchema != null && !outputSchema.isObject() {
            throw "McpTool: outputSchema must be object"
        }
        _name = name
        _title = title
        _description = description
        _inputSchema = inputSchema
        _outputSchema = outputSchema
        _readOnlyHint = readOnlyHint
        _destructiveHint = destructiveHint
        _idempotentHint = idempotentHint
        _openWorldHint = openWorldHint
    }

    static Bool isValidMcpToolName(String name) {
        if name == null || name.length() < 1 || name.length() > 128 {
            return false
        }
        Int index = 0
        while index < name.length() {
            String character = name.substring(index, index + 1)
            Bool letter = character >= "A" && character <= "Z"
            Bool lower = character >= "a" && character <= "z"
            Bool digit = character >= "0" && character <= "9"
            if !letter && !lower && !digit
                && character != "_" && character != "-" && character != "." {
                return false
            }
            index = index + 1
        }
        return true
    }

    static Result<McpTool, Error> parse(JsonValue value) {
        if value == null { throw "McpTool.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpTool: not an object"))
        }
        JsonObject object = value.asObject()
        JsonValue? nameValue = object.getOrNull("name")
        if nameValue == null || !nameValue.isString()
            || !isValidMcpToolName(nameValue.asString()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpTool: invalid name"))
        }
        JsonValue? schemaValue = object.getOrNull("inputSchema")
        if schemaValue == null || !schemaValue.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpTool: inputSchema must be object"))
        }
        JsonValue? outputValue = object.getOrNull("outputSchema")
        if outputValue != null && !outputValue.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpTool: outputSchema must be object"))
        }
        String title = ""
        JsonValue? titleValue = object.getOrNull("title")
        if titleValue != null && titleValue.isString() { title = titleValue.asString() }
        String description = ""
        JsonValue? descriptionValue = object.getOrNull("description")
        if descriptionValue != null && descriptionValue.isString() {
            description = descriptionValue.asString()
        }
        Bool readOnly = false
        Bool destructive = true
        Bool idempotent = false
        Bool openWorld = true
        JsonValue? annotationsValue = object.getOrNull("annotations")
        if annotationsValue != null {
            if !annotationsValue.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpTool: annotations must be object"))
            }
            JsonObject annotations = annotationsValue.asObject()
            JsonValue? readValue = annotations.getOrNull("readOnlyHint")
            if readValue != null && readValue.isBool() { readOnly = readValue.asBool() }
            JsonValue? destructiveValue = annotations.getOrNull("destructiveHint")
            if destructiveValue != null && destructiveValue.isBool() {
                destructive = destructiveValue.asBool()
            }
            JsonValue? idempotentValue = annotations.getOrNull("idempotentHint")
            if idempotentValue != null && idempotentValue.isBool() {
                idempotent = idempotentValue.asBool()
            }
            JsonValue? openValue = annotations.getOrNull("openWorldHint")
            if openValue != null && openValue.isBool() { openWorld = openValue.asBool() }
        }
        return Ok(new McpTool(nameValue.asString(), title, description,
            schemaValue, outputValue, readOnly, destructive, idempotent, openWorld))
    }

    String name() { return _name }
    String title() { return _title }
    String description() { return _description }
    JsonValue inputSchema() { return _inputSchema }
    JsonValue? outputSchema() { return _outputSchema }
    Bool hasOutputSchema() { return _outputSchema != null }
    Bool readOnlyHint() { return _readOnlyHint }
    Bool destructiveHint() { return _destructiveHint }
    Bool idempotentHint() { return _idempotentHint }
    Bool openWorldHint() { return _openWorldHint }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        object.set("name", JsonValue.string(_name))
        if _title != "" { object.set("title", JsonValue.string(_title)) }
        if _description != "" { object.set("description", JsonValue.string(_description)) }
        object.set("inputSchema", _inputSchema)
        if _outputSchema != null { object.set("outputSchema", _outputSchema) }
        JsonObject annotations = new JsonObject()
        annotations.set("readOnlyHint", JsonValue.bool(_readOnlyHint))
        annotations.set("destructiveHint", JsonValue.bool(_destructiveHint))
        annotations.set("idempotentHint", JsonValue.bool(_idempotentHint))
        annotations.set("openWorldHint", JsonValue.bool(_openWorldHint))
        object.set("annotations", JsonValue.object(annotations))
        return object
    }

    String describe() {
        return "tool " + _name + " output=" + str(_outputSchema != null)
    }
}
```
