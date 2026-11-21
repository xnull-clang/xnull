# `McpClientInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpClientInfo` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `McpCapability`、`McpProtocolVersion`、`JsonObject`、`JsonValue`、`Set`、`List` |

---

## 1. 定位

客户端身份与能力描述：名称、标题、版本、描述、网站、客户端能力、支持的协议版本。

不做：用户身份、OAuth 客户端注册、模型选择、采样实现、roots 内容。

---

## 2. 设计逻辑

- 与 `McpServerInfo` 对称：身份 + 能力 + 支持版本；但客户端能力只允许 sampling/roots/elicitation/tasks/extensions/experimental。
- modern 每个请求的 `_meta.io.modelcontextprotocol/clientInfo` 只使用身份字段；能力单独放在 `clientCapabilities`。
- legacy `initialize` 使用 `clientInfo` + `capabilities`，版本由请求的 `protocolVersion` 单独发送。
- 默认支持版本列表包含 latest 与两个 legacy 版本，允许客户端回退；调用方可显式覆盖。
- 子能力归一为“子能力 + 父能力”；不可变；列表/集合返回副本。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空 |
| `_title` | `String` | final | 可为空 |
| `_version` | `String` | final | 非空 |
| `_description` | `String` | final | 可为空 |
| `_websiteUrl` | `String` | final | 可为空 |
| `_capabilities` | `Set<McpCapability>` | final | 只含客户端能力；含父能力 |
| `_protocolVersions` | `List<McpProtocolVersion>` | final | 非空；顺序即偏好 |

不变量：name/version 非空；能力为客户端能力；版本非空；集合/列表返回副本。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpClientInfo(String name, String version)` | name/version | 非空 | 空/null → panic |
| `McpClientInfo(String name, String title, String version, String description, String websiteUrl, Set<McpCapability> capabilities, List<McpProtocolVersion> protocolVersions)` | 全字段 | name/version 非空；能力为客户端；版本非空 | 非法 → panic |
| `parse(JsonValue value)` | value | JSON Object | 非法 → `InvalidArgument` |

`parse` 接受完整描述对象，或含 `clientInfo` 的结果/请求对象；缺失 `capabilities` 视为空；缺失版本时使用默认版本列表。

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
| `supports` | 是否声明能力 | `McpCapability capability` | `Bool` | null → panic |
| `supportsProtocolVersion` | 是否支持版本 | `McpProtocolVersion version` | `Bool` | null → panic |
| `preferredProtocolVersion` | 首选版本 | 无 | `McpProtocolVersion` | 无 |
| `toIdentityJson` | 身份 JSON | 无 | `JsonObject` | 无 |
| `toCapabilitiesJson` | 能力 JSON | 无 | `JsonObject` | 无 |
| `toJson` | 完整 JSON | 无 | `JsonObject` | 无 |
| `parse` | 解析 JSON | `JsonValue value` | `Result<McpClientInfo, Error>` | `InvalidArgument` |
| `describe` | 诊断文本 | 无 | `String` | 无 |

说明：

- `preferredProtocolVersion` 返回列表第一个；`McpClient.initialize` 取它与服务端交集。
- `toIdentityJson` 只写 `name/title/version/description/websiteUrl`。
- `toCapabilitiesJson` 直接调用 `mcpCapabilitiesJson`。
- `toJson` 写身份 + `capabilities` + `supportedVersions`。
- `parse` 不把 `clientInfo` 当认证依据；身份是自报的显示信息。

---

## 8. 使用的技术

- 不可变值对象；
- 集合归一；
- 版本偏好列表；
- JSON 构建/解析。

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

正确：`new McpClientInfo("xdk-agent", "1.0.0")`；显式声明 `ElicitationForm`。  
反例：客户端声明 `Tools`；把用户令牌放进 `clientInfo`；把 `name` 当唯一认证主体；版本列表为空。

---

## 13. 测试/场景义务

最小/完整构造；客户端能力校验；子能力归一；默认版本列表；preferred；toJson 往返；parse 两种形态；缺失 capabilities/versions；未知字段；identity JSON 不含能力。

---

## 14. XNull 伪代码

```xnull
class McpClientInfo {
    final String _name
    final String _title
    final String _version
    final String _description
    final String _websiteUrl
    final Set<McpCapability> _capabilities
    final List<McpProtocolVersion> _protocolVersions

    McpClientInfo(String name, String version) {
        if name == null || name == "" {
            throw "McpClientInfo: empty name"
        }
        if version == null || version == "" {
            throw "McpClientInfo: empty version"
        }
        _name = name
        _title = ""
        _version = version
        _description = ""
        _websiteUrl = ""
        _capabilities = new Set<McpCapability>()
        _protocolVersions = [latestMcpProtocolVersion(),
            McpProtocolVersion.V2025_11_25, McpProtocolVersion.V2025_06_18]
    }

    McpClientInfo(String name, String title, String version, String description,
                  String websiteUrl, Set<McpCapability> capabilities,
                  List<McpProtocolVersion> protocolVersions) {
        if name == null || name == "" {
            throw "McpClientInfo: empty name"
        }
        if version == null || version == "" {
            throw "McpClientInfo: empty version"
        }
        if capabilities == null { throw "McpClientInfo: null capabilities" }
        if protocolVersions == null || protocolVersions.length() == 0 {
            throw "McpClientInfo: empty protocol versions"
        }
        List<McpCapability> capabilityValues = capabilities.toList()
        Int capabilityIndex = 0
        while capabilityIndex < capabilityValues.length() {
            if !isClientMcpCapability(capabilityValues.get(capabilityIndex)) {
                throw "McpClientInfo: server capability on client"
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
    }

    static Result<McpClientInfo, Error> parse(JsonValue value) {
        if value == null { throw "McpClientInfo.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpClientInfo: not an object"))
        }
        JsonObject outer = value.asObject()
        JsonValue? identityValue = outer.getOrNull("clientInfo")
        JsonObject identity = outer
        if identityValue != null {
            if !identityValue.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpClientInfo: clientInfo must be object"))
            }
            identity = identityValue.asObject()
        }
        JsonValue? nameValue = identity.getOrNull("name")
        JsonValue? versionValue = identity.getOrNull("version")
        if nameValue == null || !nameValue.isString() || nameValue.asString() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpClientInfo: invalid name"))
        }
        if versionValue == null || !versionValue.isString() || versionValue.asString() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpClientInfo: invalid version"))
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
                    "McpClientInfo: capabilities must be object"))
            }
            Result<Set<McpCapability>, Error> parsedCapabilities =
                parseMcpCapabilities(capabilitiesValue.asObject())
            if parsedCapabilities.isErr() { return Err(parsedCapabilities.error()) }
            capabilities = parsedCapabilities.value()
            List<McpCapability> values = capabilities.toList()
            Int index = 0
            while index < values.length() {
                if !isClientMcpCapability(values.get(index)) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpClientInfo: server capability on client"))
                }
                index = index + 1
            }
        }
        List<McpProtocolVersion> versions = []
        JsonValue? versionsValue = outer.getOrNull("supportedVersions")
        if versionsValue != null {
            if !versionsValue.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpClientInfo: supportedVersions must be array"))
            }
            JsonArray array = versionsValue.asArray()
            Int index = 0
            while index < array.length() {
                JsonValue item = array.get(index)
                if !item.isString() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpClientInfo: version must be string"))
                }
                Result<McpProtocolVersion, Error> parsedVersion =
                    parseMcpProtocolVersion(item.asString())
                if parsedVersion.isErr() { return Err(parsedVersion.error()) }
                versions.push(parsedVersion.value())
                index = index + 1
            }
        }
        if versions.length() == 0 {
            versions.push(latestMcpProtocolVersion())
            versions.push(McpProtocolVersion.V2025_11_25)
            versions.push(McpProtocolVersion.V2025_06_18)
        }
        return Ok(new McpClientInfo(nameValue.asString(), title,
            versionValue.asString(), description, websiteUrl, capabilities, versions))
    }

    String name() { return _name }
    String title() { return _title }
    String version() { return _version }
    String description() { return _description }
    String websiteUrl() { return _websiteUrl }
    Set<McpCapability> capabilities() { return _capabilities.copy() }
    List<McpProtocolVersion> protocolVersions() { return _protocolVersions.copy() }
    Bool supports(McpCapability capability) {
        if capability == null { throw "McpClientInfo.supports: null" }
        return _capabilities.has(capability)
    }
    Bool supportsProtocolVersion(McpProtocolVersion version) {
        if version == null { throw "McpClientInfo.supportsProtocolVersion: null" }
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
        return object
    }

    String describe() {
        return "client " + _name + " " + _version + " versions="
            + str(_protocolVersions.length()) + " capabilities=" + str(_capabilities.length())
    }
}
```
