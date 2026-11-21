# `McpPrompt`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpPrompt` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `McpContent`、`JsonObject`、`JsonValue`、`List`、`Map`、`Set` |

---

## 1. 定位

MCP prompt：模板定义（名称、标题、描述、参数）或解析结果（角色+内容消息）。

不做：模板渲染引擎、参数默认值、消息注入防护、LLM 调用、图标。

---

## 2. 设计逻辑

- 同一 class 承载 `prompts/list` 的模板元数据与 `prompts/get` 的解析结果；`_resolved` 区分。
- 模板消息为空；解析结果必须至少有一条消息。
- 参数用三个平行结构：`_argumentNames` 保序、`_argumentDescriptions` 提供描述、`_requiredArguments` 标记必填；避免额外 `McpPromptArgument` 类型。
- 消息角色与内容用两个等长列表；角色只允许 `user`/`assistant`。
- 参数名唯一；必填集合必须是参数名子集。
- 构造后不可变；列表/Map/Set 返回副本；可共享。
- 参数 title、图标、annotations 为 X；当前不建模。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空 |
| `_title` | `String` | final | 可为空 |
| `_description` | `String` | final | 可为空 |
| `_argumentNames` | `List<String>` | final | 保序；唯一 |
| `_argumentDescriptions` | `Map<String,String>` | final | 仅含已知参数 |
| `_requiredArguments` | `Set<String>` | final | 参数名子集 |
| `_messages` | `List<McpContent>` | final | 模板为空；解析结果非空 |
| `_messageRoles` | `List<String>` | final | 与 messages 等长；user/assistant |
| `_resolved` | `Bool` | final | 是否 prompts/get 结果 |

不变量：name 非空；参数名唯一；required ⊆ names；descriptions 键 ⊆ names；messages 与 roles 等长；resolved 时 messages 非空且 roles 合法；模板时两者为空。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpPrompt(String name)` | name | 非空 | 空/null → panic |
| `McpPrompt(String name, String title, String description, List<String> argumentNames, Map<String,String> argumentDescriptions, Set<String> requiredArguments)` | 六参数 | 参数名唯一；required/descriptions 为子集 | 非法 → panic |
| `McpPrompt(String name, String title, String description, List<String> argumentNames, Map<String,String> argumentDescriptions, Set<String> requiredArguments, List<String> messageRoles, List<McpContent> messages)` | 八参数 | 同上；消息非空；角色合法；等长 | 非法 → panic |
| `parse(JsonValue value)` | value | JSON Object | 非法 → `InvalidArgument` |

`parse` 同时接受模板形态和 `prompts/get` 结果形态；有 `messages` 即视为 resolved。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 名称 | 无 | `String` | 无 |
| `title` | 标题 | 无 | `String` | 无 |
| `description` | 描述 | 无 | `String` | 无 |
| `argumentNames` | 参数名副本 | 无 | `List<String>` | 无 |
| `argumentCount` | 参数数 | 无 | `Int` | 无 |
| `argumentDescription` | 参数描述 | `String name` | `String` | 未知 → panic |
| `isArgumentRequired` | 是否必填 | `String name` | `Bool` | null → panic |
| `messages` | 消息内容副本 | 无 | `List<McpContent>` | 无 |
| `messageCount` | 消息数 | 无 | `Int` | 无 |
| `messageRole` | 第 n 条角色 | `Int index` | `String` | 越界 → panic |
| `isResolved` | 是否解析结果 | 无 | `Bool` | 无 |
| `toJson` | JSON 对象 | 无 | `JsonObject` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<McpPrompt, Error>` | `InvalidArgument` |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `argumentDescription` 对未知参数是合同错误；调用方先用 `argumentNames` 判断。
- `toJson` 模板形态写 `name/title/description/arguments`；resolved 形态额外写 `messages`。
- `parse` 对重复参数、required 非 Bool、未知角色、消息/角色不匹配返回 `InvalidArgument`。
- `describe` 只输出名称、参数数、消息数，不输出消息文本。

---

## 8. 使用的技术

- 不可变值对象；
- 平行列表/映射/集合；
- 角色校验；
- JSON 构建/解析。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、List、Map、Set、Result；
- 运行时：无；
- 接口：`McpContent`、`JsonObject`、`JsonValue`、`JsonArray`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`McpContent`、`JsonObject`、`JsonValue`、`JsonArray`、`List`、`Map`、`Set`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；`arguments`/`messages` 返回副本；`McpContent` 元素不可变；无资源；可共享；无锁。

---

## 12. 示例与反例

正确：`new McpPrompt("code_review")` 模板；`parse` `prompts/get` 结果得到 resolved。  
反例：模板带消息；resolved 没有消息；角色用 `"system"`；参数重复；required 含未知参数；把 prompt 内容直接拼进系统提示而不审查。

---

## 13. 测试/场景义务

最小模板；完整参数；重复参数；required 子集；descriptions 子集；resolved 消息/角色等长；非法角色；空消息 resolved；toJson 两种形态；parse 模板/get；describe 不泄密。

---

## 14. XNull 伪代码

```xnull
class McpPrompt {
    final String _name
    final String _title
    final String _description
    final List<String> _argumentNames
    final Map<String, String> _argumentDescriptions
    final Set<String> _requiredArguments
    final List<String> _messageRoles
    final List<McpContent> _messages
    final Bool _resolved

    McpPrompt(String name) {
        if name == null || name == "" { throw "McpPrompt: empty name" }
        _name = name
        _title = ""
        _description = ""
        _argumentNames = []
        _argumentDescriptions = new Map<String, String>()
        _requiredArguments = new Set<String>()
        _messageRoles = []
        _messages = []
        _resolved = false
    }

    McpPrompt(String name, String title, String description,
              List<String> argumentNames, Map<String, String> argumentDescriptions,
              Set<String> requiredArguments) {
        if name == null || name == "" { throw "McpPrompt: empty name" }
        validatePromptArguments(argumentNames, argumentDescriptions, requiredArguments)
        _name = name
        _title = title
        _description = description
        _argumentNames = argumentNames.copy()
        _argumentDescriptions = argumentDescriptions.copy()
        _requiredArguments = requiredArguments.copy()
        _messageRoles = []
        _messages = []
        _resolved = false
    }

    McpPrompt(String name, String title, String description,
              List<String> argumentNames, Map<String, String> argumentDescriptions,
              Set<String> requiredArguments, List<String> messageRoles,
              List<McpContent> messages) {
        if name == null || name == "" { throw "McpPrompt: empty name" }
        validatePromptArguments(argumentNames, argumentDescriptions, requiredArguments)
        if messages == null || messages.length() == 0 {
            throw "McpPrompt: resolved prompt needs messages"
        }
        if messageRoles == null || messageRoles.length() != messages.length() {
            throw "McpPrompt: roles/messages length mismatch"
        }
        Int index = 0
        while index < messageRoles.length() {
            if messageRoles.get(index) != "user" && messageRoles.get(index) != "assistant" {
                throw "McpPrompt: invalid role"
            }
            if messages.get(index) == null {
                throw "McpPrompt: null message"
            }
            index = index + 1
        }
        _name = name
        _title = title
        _description = description
        _argumentNames = argumentNames.copy()
        _argumentDescriptions = argumentDescriptions.copy()
        _requiredArguments = requiredArguments.copy()
        _messageRoles = messageRoles.copy()
        _messages = messages.copy()
        _resolved = true
    }

    static void validatePromptArguments(List<String> argumentNames,
                                        Map<String, String> argumentDescriptions,
                                        Set<String> requiredArguments) {
        if argumentNames == null || argumentDescriptions == null || requiredArguments == null {
            throw "McpPrompt: null arguments"
        }
        Set<String> seen = new Set<String>()
        Int index = 0
        while index < argumentNames.length() {
            String name = argumentNames.get(index)
            if name == null || name == "" {
                throw "McpPrompt: empty argument name"
            }
            if seen.has(name) { throw "McpPrompt: duplicate argument" }
            seen.add(name)
            index = index + 1
        }
        List<String> descriptionNames = argumentDescriptions.keys()
        index = 0
        while index < descriptionNames.length() {
            if !seen.has(descriptionNames.get(index)) {
                throw "McpPrompt: description for unknown argument"
            }
            index = index + 1
        }
        List<String> requiredNames = requiredArguments.toList()
        index = 0
        while index < requiredNames.length() {
            if !seen.has(requiredNames.get(index)) {
                throw "McpPrompt: required unknown argument"
            }
            index = index + 1
        }
    }

    static Result<McpPrompt, Error> parse(JsonValue value) {
        if value == null { throw "McpPrompt.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpPrompt: not an object"))
        }
        JsonObject object = value.asObject()
        JsonValue? nameValue = object.getOrNull("name")
        if nameValue == null || !nameValue.isString() || nameValue.asString() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpPrompt: invalid name"))
        }
        String title = ""
        JsonValue? titleValue = object.getOrNull("title")
        if titleValue != null && titleValue.isString() { title = titleValue.asString() }
        String description = ""
        JsonValue? descriptionValue = object.getOrNull("description")
        if descriptionValue != null && descriptionValue.isString() {
            description = descriptionValue.asString()
        }
        List<String> argumentNames = []
        Map<String, String> argumentDescriptions = new Map<String, String>()
        Set<String> requiredArguments = new Set<String>()
        JsonValue? argumentsValue = object.getOrNull("arguments")
        if argumentsValue != null {
            if !argumentsValue.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpPrompt: arguments must be array"))
            }
            JsonArray array = argumentsValue.asArray()
            Int index = 0
            while index < array.length() {
                JsonValue item = array.get(index)
                if !item.isObject() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpPrompt: argument must be object"))
                }
                JsonObject argument = item.asObject()
                JsonValue? argumentName = argument.getOrNull("name")
                if argumentName == null || !argumentName.isString()
                    || argumentName.asString() == "" {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpPrompt: invalid argument name"))
                }
                String name = argumentName.asString()
                if argumentNames.contains(name) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpPrompt: duplicate argument"))
                }
                argumentNames.push(name)
                JsonValue? argumentDescription = argument.getOrNull("description")
                if argumentDescription != null && argumentDescription.isString() {
                    argumentDescriptions.put(name, argumentDescription.asString())
                }
                JsonValue? requiredValue = argument.getOrNull("required")
                if requiredValue != null {
                    if !requiredValue.isBool() {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "McpPrompt: required must be boolean"))
                    }
                    if requiredValue.asBool() { requiredArguments.add(name) }
                }
                index = index + 1
            }
        }
        List<String> messageRoles = []
        List<McpContent> messages = []
        JsonValue? messagesValue = object.getOrNull("messages")
        if messagesValue != null {
            if !messagesValue.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpPrompt: messages must be array"))
            }
            JsonArray array = messagesValue.asArray()
            Int index = 0
            while index < array.length() {
                JsonValue item = array.get(index)
                if !item.isObject() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpPrompt: message must be object"))
                }
                JsonObject message = item.asObject()
                JsonValue? roleValue = message.getOrNull("role")
                if roleValue == null || !roleValue.isString()
                    || (roleValue.asString() != "user" && roleValue.asString() != "assistant") {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpPrompt: invalid role"))
                }
                JsonValue? contentValue = message.getOrNull("content")
                if contentValue == null {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpPrompt: missing content"))
                }
                Result<McpContent, Error> content = McpContent.parse(contentValue)
                if content.isErr() { return Err(content.error()) }
                messageRoles.push(roleValue.asString())
                messages.push(content.value())
                index = index + 1
            }
        }
        if messages.length() == 0 {
            return Ok(new McpPrompt(nameValue.asString(), title, description,
                argumentNames, argumentDescriptions, requiredArguments))
        }
        return Ok(new McpPrompt(nameValue.asString(), title, description,
            argumentNames, argumentDescriptions, requiredArguments,
            messageRoles, messages))
    }

    String name() { return _name }
    String title() { return _title }
    String description() { return _description }
    List<String> argumentNames() { return _argumentNames.copy() }
    Int argumentCount() { return _argumentNames.length() }
    String argumentDescription(String name) {
        if name == null { throw "McpPrompt.argumentDescription: null" }
        if !_argumentDescriptions.has(name) {
            throw "McpPrompt.argumentDescription: unknown argument"
        }
        return _argumentDescriptions.get(name)
    }
    Bool isArgumentRequired(String name) {
        if name == null { throw "McpPrompt.isArgumentRequired: null" }
        return _requiredArguments.has(name)
    }
    List<McpContent> messages() { return _messages.copy() }
    Int messageCount() { return _messages.length() }
    String messageRole(Int index) {
        if index < 0 || index >= _messageRoles.length() {
            throw "McpPrompt.messageRole: out of range"
        }
        return _messageRoles.get(index)
    }
    Bool isResolved() { return _resolved }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        object.set("name", JsonValue.string(_name))
        if _title != "" { object.set("title", JsonValue.string(_title)) }
        if _description != "" { object.set("description", JsonValue.string(_description)) }
        JsonArray arguments = new JsonArray()
        Int index = 0
        while index < _argumentNames.length() {
            String name = _argumentNames.get(index)
            JsonObject argument = new JsonObject()
            argument.set("name", JsonValue.string(name))
            if _argumentDescriptions.has(name) {
                argument.set("description", JsonValue.string(_argumentDescriptions.get(name)))
            }
            if _requiredArguments.has(name) {
                argument.set("required", JsonValue.bool(true))
            }
            arguments.add(JsonValue.object(argument))
            index = index + 1
        }
        if !_resolved && arguments.length() > 0 {
            object.set("arguments", JsonValue.array(arguments))
        }
        if _resolved {
            JsonArray messages = new JsonArray()
            index = 0
            while index < _messages.length() {
                JsonObject message = new JsonObject()
                message.set("role", JsonValue.string(_messageRoles.get(index)))
                message.set("content", JsonValue.object(_messages.get(index).toJson()))
                messages.add(JsonValue.object(message))
                index = index + 1
            }
            object.set("messages", JsonValue.array(messages))
        }
        return object
    }

    String describe() {
        return "prompt " + _name + " arguments=" + str(_argumentNames.length())
            + " messages=" + str(_messages.length())
    }
}
```
