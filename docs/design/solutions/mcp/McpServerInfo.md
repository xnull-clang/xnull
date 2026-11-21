# `McpServerInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpServerInfo` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `McpCapability`、`McpProtocolVersion`、`JsonObject`、`JsonValue`、`Set`、`List` |

---

## 1. 定位

服务端身份与能力描述：名称、标题、版本、描述、网站、能力集合、支持的协议版本、instructions。

不做：工具/资源/prompt 内容、认证、网络地址、健康状态、服务器运行时。

---

## 2. 设计逻辑

- 一个类型同时服务 modern `server/discover` 结果与 legacy `initialize` 结果：modern 支持多版本列表，legacy 取第一个/唯一版本。
- `McpServerInfo` 是服务端“声明”，不是“实际可用列表”；实际注册项由 `McpServer` 决定。
- 构造函数把子能力归一为“子能力 + 父能力”，避免调用方只写 `ToolsListChanged` 而 `supports(Tools)` 为 false。
- 能力集合只允许服务端能力；客户端能力（sampling/roots/elicitation）在构造时拒绝。
- 协议版本列表非空；modern 可列多个，legacy 协商后只保留一个。最小构造默认支持 latest 与 `2025-11-25`，便于同时服务 modern/legacy 客户端。
- 不可变；列表/集合返回副本；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空 |
| `_title` | `String` | final | 可为空 |
| `_version` | `String` | final | 非空 |
| `_description` | `String` | final | 可为空 |
| `_websiteUrl` | `String` | final | 可为空 |
| `_capabilities` | `Set<McpCapability>` | final | 只含服务端能力；含父能力 |
| `_protocolVersions` | `List<McpProtocolVersion>` | final | 非空 |
| `_instructions` | `String` | final | 可为空 |

不变量：name/version 非空；capabilities 非 null 且均为服务端能力；protocolVersions 非空；集合/列表返回副本。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpServerInfo(String name, String version)` | name/version | 非空 | 空/null → panic |
| `McpServerInfo(String name, String title, String version, String description, String websiteUrl, Set<McpCapability> capabilities, List<McpProtocolVersion> protocolVersions, String instructions)` | 全字段 | name/version 非空；能力为服务端；版本非空 | 非法 → panic |
| `parse(JsonValue value)` | value | JSON Object | 非法 → `InvalidArgument` |

`parse` 接受两种形态：完整描述对象，或含 `serverInfo` 的 discover/initialize 结果对象；缺失 `capabilities` 视为空；缺失版本时使用 latest 与 `2025-11-25`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 名称 | 无 | `String` | 无 |
| `title` | 显示标题 | 无 | `String` | 无 |
| `version` | 版本 | 无 | `String` | 无 |
| `description` | 描述 | 无 | `String` | 无 |
| `websiteUrl` | 网站 | 无 | `String` | 无 |
| `capabilities` | 能力副本 | 无 | `Set<McpCapability>` | 无 |
| `protocolVersions` | 版本副本 | 无 | `List<McpProtocolVersion>` | 无 |
| `instructions` | 使用说明 | 无 | `String` | 无 |
| `supports` | 是否声明能力 | `McpCapability capability` | `Bool` | null → panic |
| `supportsProtocolVersion` | 是否支持版本 | `McpProtocolVersion version` | `Bool` | null → panic |
| `preferredProtocolVersion` | 首选版本 | 无 | `McpProtocolVersion` | 无 |
| `toIdentityJson` | 身份 JSON | 无 | `JsonObject` | 无 |
| `toCapabilitiesJson` | 能力 JSON | 无 | `JsonObject` | 无 |
| `toJson` | 完整 JSON | 无 | `JsonObject` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<McpServerInfo, Error>` | `InvalidArgument` |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `preferredProtocolVersion` 返回列表第一个；构造函数保留调用方顺序，`McpClient` 负责选择交集。
- `supports` 只查集合；构造函数已补父能力。
- `toIdentityJson` 只写 `name/title/version/description/websiteUrl`，用于 `serverInfo` 字段。
- `toCapabilitiesJson` 直接调用 `mcpCapabilitiesJson`。
- `toJson` 写身份 + `capabilities` + `supportedVersions` + `instructions`。
- `parse` 不信任 `serverInfo` 以外的字段；未知字段忽略。

---

## 8. 使用的技术

- 不可变值对象；
- 集合归一；
- 版本列表；
- JSON 对象构建/解析。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Set、List、Result；
- 运行时：无；
- 接口：`McpCapability`、`McpProtocolVersion`、`JsonObject`、`JsonValue`、`JsonArray`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`McpCapability`、`McpProtocolVersion`、`mcpCapabilitiesJson`、`parseMcpCapabilities`、`JsonObject`、`JsonValue`、`JsonArray`、`Set`、`List`。

---

## 11. 所有权与并发

不可变；`capabilities()`/`protocolVersions()` 返回副本；`toJson` 返回新对象；无资源；可共享；无锁。

---

## 12. 示例与反例

正确：`new McpServerInfo("weather", "1.0.0")`；带 `Tools`/`ToolsListChanged` 的完整构造。  
反例：声明 `Sampling`（客户端能力）；版本列表为空；只声明子能力不补父能力；把 `serverInfo` 的 name 当唯一标识做认证。

---

## 13. 测试/场景义务

最小/完整构造；空 name/version；客户端能力拒绝；空版本列表拒绝；子能力归一；supports/supportsProtocolVersion；preferred；toJson 往返；parse 两种形态；未知字段；instructions 为空。

---

## 14. XNull 伪代码

```xnull
class McpServerInfo {
    final String _name
    final String _title
    final String _version
    final String _description
    final String _websiteUrl
    final Set<McpCapability> _capabilities
    final List<McpProtocolVersion> _protocolVersions
    final String _instructions

    McpServerInfo(String name, String version) {
        if name == null || name == "" {
            throw "McpServerInfo: empty name"
        }
        if version == null || version == "" {
            throw "McpServerInfo: empty version"
        }
        _name = name
        _title = ""
        _version = version
        _description = ""
        _websiteUrl = ""
        _capabilities = new Set<McpCapability>()
        _protocolVersions = [latestMcpProtocolVersion(), McpProtocolVersion.V2025_11_25]
        _instructions = ""
    }

    McpServerInfo(String name, String title, String version, String description,
                  String websiteUrl, Set<McpCapability> capabilities,
                  List<McpProtocolVersion> protocolVersions, String instructions) {
        if name == null || name == "" {
            throw "McpServerInfo: empty name"
        }
        if version == null || version == "" {
            throw "McpServerInfo: empty version"
        }
        if capabilities == null { throw "McpServerInfo: null capabilities" }
        if protocolVersions == null || protocolVersions.length() == 0 {
            throw "McpServerInfo: empty protocol versions"
        }
        List<McpCapability> capabilityValues = capabilities.toList()
        Int capabilityIndex = 0
        while capabilityIndex < capabilityValues.length() {
            if !isServerMcpCapability(capabilityValues.get(capabilityIndex)) {
                throw "McpServerInfo: client capability on server"
            }
            capabilityIndex = capabilityIndex + 1
        }
        Set<McpCapability> normalized = capabilities.copy()
        capabilityIndex = 0
        while capabilityIndex < capabilityValues.length() {
            normalized.add(mcpCapabilityParent(capabilityValues.get(capabilityIndex)))
            capabilityIndex = capabilityIndex + 1
        }
        _name = name
        _title = title
        _version = version
        _description = description
        _websiteUrl = websiteUrl
        _capabilities = normalized
        _protocolVersions = protocolVersions.copy()
        _instructions = instructions
    }

    static Result<McpServerInfo, Error> parse(JsonValue value) {
        if value == null { throw "McpServerInfo.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpServerInfo: not an object"))
        }
        JsonObject outer = value.asObject()
        JsonValue? identityValue = outer.getOrNull("serverInfo")
        JsonObject identity = outer
        if identityValue == null {
            JsonValue? metaValue = outer.getOrNull("_meta")
            if metaValue != null && metaValue.isObject() {
                identityValue = metaValue.asObject().getOrNull(
                    "io.modelcontextprotocol/serverInfo")
            }
        }
        if identityValue != null {
            if !identityValue.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpServerInfo: serverInfo must be object"))
            }
            identity = identityValue.asObject()
        }
        JsonValue? nameValue = identity.getOrNull("name")
        JsonValue? versionValue = identity.getOrNull("version")
        if nameValue == null || !nameValue.isString() || nameValue.asString() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpServerInfo: invalid name"))
        }
        if versionValue == null || !versionValue.isString() || versionValue.asString() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpServerInfo: invalid version"))
        }
        String title = ""
        JsonValue? titleValue = identity.getOrNull("title")
        if titleValue != null && titleValue.isString() { title = titleValue.asString() }
        String description = ""
        JsonValue? descriptionValue = identity.getOrNull("description")
        if descriptionValue != null && descriptionValue.isString() {
            description = descriptionValue.asString()
        }
        String websiteUrl = ""
        JsonValue? websiteValue = identity.getOrNull("websiteUrl")
        if websiteValue != null && websiteValue.isString() {
            websiteUrl = websiteValue.asString()
        }
        Set<McpCapability> capabilities = new Set<McpCapability>()
        JsonValue? capabilitiesValue = outer.getOrNull("capabilities")
        if capabilitiesValue != null {
            if !capabilitiesValue.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpServerInfo: capabilities must be object"))
            }
            Result<Set<McpCapability>, Error> parsedCapabilities =
                parseMcpCapabilities(capabilitiesValue.asObject())
            if parsedCapabilities.isErr() { return Err(parsedCapabilities.error()) }
            capabilities = parsedCapabilities.value()
            List<McpCapability> values = capabilities.toList()
            Int index = 0
            while index < values.length() {
                if !isServerMcpCapability(values.get(index)) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpServerInfo: client capability on server"))
                }
                index = index + 1
            }
        }
        List<McpProtocolVersion> versions = []
        JsonValue? versionsValue = outer.getOrNull("supportedVersions")
        if versionsValue != null {
            if !versionsValue.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpServerInfo: supportedVersions must be array"))
            }
            JsonArray array = versionsValue.asArray()
            Int index = 0
            while index < array.length() {
                JsonValue item = array.get(index)
                if !item.isString() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpServerInfo: version must be string"))
                }
                Result<McpProtocolVersion, Error> parsedVersion =
                    parseMcpProtocolVersion(item.asString())
                if parsedVersion.isErr() { return Err(parsedVersion.error()) }
                versions.push(parsedVersion.value())
                index = index + 1
            }
            if versions.length() == 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpServerInfo: empty supportedVersions"))
            }
        } else {
            JsonValue? versionText = outer.getOrNull("protocolVersion")
            if versionText != null && versionText.isString() {
                Result<McpProtocolVersion, Error> parsedVersion =
                    parseMcpProtocolVersion(versionText.asString())
                if parsedVersion.isErr() { return Err(parsedVersion.error()) }
                versions.push(parsedVersion.value())
            } else {
                versions.push(latestMcpProtocolVersion())
                versions.push(McpProtocolVersion.V2025_11_25)
            }
        }
        String instructions = ""
        JsonValue? instructionsValue = outer.getOrNull("instructions")
        if instructionsValue != null && instructionsValue.isString() {
            instructions = instructionsValue.asString()
        }
        return Ok(new McpServerInfo(nameValue.asString(), title,
            versionValue.asString(), description, websiteUrl,
            capabilities, versions, instructions))
    }

    String name() { return _name }
    String title() { return _title }
    String version() { return _version }
    String description() { return _description }
    String websiteUrl() { return _websiteUrl }
    Set<McpCapability> capabilities() { return _capabilities.copy() }
    List<McpProtocolVersion> protocolVersions() { return _protocolVersions.copy() }
    String instructions() { return _instructions }
    Bool supports(McpCapability capability) {
        if capability == null { throw "McpServerInfo.supports: null" }
        return _capabilities.has(capability)
    }
    Bool supportsProtocolVersion(McpProtocolVersion version) {
        if version == null { throw "McpServerInfo.supportsProtocolVersion: null" }
        Int index = 0
        while index < _protocolVersions.length() {
            if _protocolVersions.get(index) == version { return true }
            index = index + 1
        }
        return false
    }
    McpProtocolVersion preferredProtocolVersion() { return _protocolVersions.get(0) }

    JsonObject toIdentityJson() {
        JsonObject object = new JsonObject()
        object.set("name", JsonValue.string(_name))
        if _title != "" { object.set("title", JsonValue.string(_title)) }
        object.set("version", JsonValue.string(_version))
        if _description != "" { object.set("description", JsonValue.string(_description)) }
        if _websiteUrl != "" { object.set("websiteUrl", JsonValue.string(_websiteUrl)) }
        return object
    }

    JsonObject toCapabilitiesJson() { return mcpCapabilitiesJson(_capabilities) }

    JsonObject toJson() {
        JsonObject object = self.toIdentityJson()
        object.set("capabilities", JsonValue.object(self.toCapabilitiesJson()))
        JsonArray versions = new JsonArray()
        Int index = 0
        while index < _protocolVersions.length() {
            versions.add(JsonValue.string(mcpProtocolVersionText(_protocolVersions.get(index))))
            index = index + 1
        }
        object.set("supportedVersions", JsonValue.array(versions))
        if _instructions != "" { object.set("instructions", JsonValue.string(_instructions)) }
        return object
    }

    String describe() {
        return "server " + _name + " " + _version + " versions="
            + str(_protocolVersions.length()) + " capabilities=" + str(_capabilities.length())
    }
}
```
