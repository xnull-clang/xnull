// xdk.mcp —— MCP 消息模型核心（M22.3）
//
import xdk.jsonrpc
// 实现 ProtocolVersion/Capability/ServerInfo/ClientInfo/Content/Resource/
// Prompt/Tool/ToolResult/Session；传输/客户端/服务端/registry 留 M22.4。
package xdk.mcp
import xdk.errors
import xdk.codec

// ---------- McpProtocolVersion ----------
enum McpProtocolVersion {
    V2024_11_05,
    V2025_03_26,
    V2025_06_18,
    V2025_11_25,
    V2026_07_28,
    Unknown,
}

String mcpProtocolVersionText(McpProtocolVersion version) {
    if version == McpProtocolVersion.V2024_11_05 { return "2024-11-05" }
    if version == McpProtocolVersion.V2025_03_26 { return "2025-03-26" }
    if version == McpProtocolVersion.V2025_06_18 { return "2025-06-18" }
    if version == McpProtocolVersion.V2025_11_25 { return "2025-11-25" }
    if version == McpProtocolVersion.V2026_07_28 { return "2026-07-28" }
    return "unknown"
}

McpProtocolVersion parseMcpProtocolVersion(String text) {
    if text == null { throw "parseMcpProtocolVersion: null" }
    if text == "2024-11-05" { return McpProtocolVersion.V2024_11_05 }
    if text == "2025-03-26" { return McpProtocolVersion.V2025_03_26 }
    if text == "2025-06-18" { return McpProtocolVersion.V2025_06_18 }
    if text == "2025-11-25" { return McpProtocolVersion.V2025_11_25 }
    if text == "2026-07-28" { return McpProtocolVersion.V2026_07_28 }
    return McpProtocolVersion.Unknown
}

Bool isLegacyMcpProtocolVersion(McpProtocolVersion version) {
    return version != McpProtocolVersion.V2026_07_28 &&
        version != McpProtocolVersion.Unknown
}

Bool isModernMcpProtocolVersion(McpProtocolVersion version) {
    return version == McpProtocolVersion.V2026_07_28
}

McpProtocolVersion latestMcpProtocolVersion() { return McpProtocolVersion.V2026_07_28 }

Bool isSupportedMcpProtocolVersion(McpProtocolVersion version) {
    return version != McpProtocolVersion.Unknown
}

// ---------- McpCapability ----------
enum McpCapability {
    Tools,
    ToolsListChanged,
    Resources,
    ResourcesListChanged,
    ResourcesSubscribe,
    Prompts,
    PromptsListChanged,
    Logging,
    Completions,
    Tasks,
    Sampling,
    SamplingTools,
    Roots,
    Elicitation,
    ElicitationForm,
    ElicitationUrl,
    Extensions,
    Experimental,
    Unknown,
}

String mcpCapabilityName(McpCapability capability) {
    if capability == McpCapability.Tools { return "tools" }
    if capability == McpCapability.ToolsListChanged { return "tools.listChanged" }
    if capability == McpCapability.Resources { return "resources" }
    if capability == McpCapability.ResourcesListChanged { return "resources.listChanged" }
    if capability == McpCapability.ResourcesSubscribe { return "resources.subscribe" }
    if capability == McpCapability.Prompts { return "prompts" }
    if capability == McpCapability.PromptsListChanged { return "prompts.listChanged" }
    if capability == McpCapability.Logging { return "logging" }
    if capability == McpCapability.Completions { return "completions" }
    if capability == McpCapability.Tasks { return "tasks" }
    if capability == McpCapability.Sampling { return "sampling" }
    if capability == McpCapability.SamplingTools { return "sampling.tools" }
    if capability == McpCapability.Roots { return "roots" }
    if capability == McpCapability.Elicitation { return "elicitation" }
    if capability == McpCapability.ElicitationForm { return "elicitation.form" }
    if capability == McpCapability.ElicitationUrl { return "elicitation.url" }
    if capability == McpCapability.Extensions { return "extensions" }
    if capability == McpCapability.Experimental { return "experimental" }
    return "unknown"
}

McpCapability mcpCapabilityParent(McpCapability capability) {
    if capability == McpCapability.ToolsListChanged { return McpCapability.Tools }
    if capability == McpCapability.ResourcesListChanged ||
        capability == McpCapability.ResourcesSubscribe { return McpCapability.Resources }
    if capability == McpCapability.PromptsListChanged { return McpCapability.Prompts }
    if capability == McpCapability.SamplingTools { return McpCapability.Sampling }
    if capability == McpCapability.ElicitationForm ||
        capability == McpCapability.ElicitationUrl { return McpCapability.Elicitation }
    return capability
}

Result<McpCapability, Error> parseMcpCapability(String text) {
    if text == null { throw "parseMcpCapability: null" }
    Int index = 0
    while index < allMcpCapabilities().length() {
        McpCapability value = allMcpCapabilities().get(index)
        if mcpCapabilityName(value) == text { return Ok(value) }
        index = index + 1
    }
    return Err(new BasicError(ErrorKind.InvalidArgument, "unknown MCP capability: " + text))
}

Bool isClientMcpCapability(McpCapability capability) {
    if capability == McpCapability.Sampling || capability == McpCapability.SamplingTools ||
        capability == McpCapability.Roots || capability == McpCapability.Elicitation ||
        capability == McpCapability.ElicitationForm ||
        capability == McpCapability.ElicitationUrl ||
        capability == McpCapability.Tasks || capability == McpCapability.Extensions ||
        capability == McpCapability.Experimental { return true }
    return false
}

Bool isServerMcpCapability(McpCapability capability) {
    if capability == McpCapability.Tools || capability == McpCapability.ToolsListChanged ||
        capability == McpCapability.Resources ||
        capability == McpCapability.ResourcesListChanged ||
        capability == McpCapability.ResourcesSubscribe ||
        capability == McpCapability.Prompts || capability == McpCapability.PromptsListChanged ||
        capability == McpCapability.Logging || capability == McpCapability.Completions ||
        capability == McpCapability.Tasks || capability == McpCapability.Extensions ||
        capability == McpCapability.Experimental { return true }
    return false
}

List<McpCapability> allMcpCapabilities() {
    List<McpCapability> result = []
    result.push(McpCapability.Tools)
    result.push(McpCapability.ToolsListChanged)
    result.push(McpCapability.Resources)
    result.push(McpCapability.ResourcesListChanged)
    result.push(McpCapability.ResourcesSubscribe)
    result.push(McpCapability.Prompts)
    result.push(McpCapability.PromptsListChanged)
    result.push(McpCapability.Logging)
    result.push(McpCapability.Completions)
    result.push(McpCapability.Tasks)
    result.push(McpCapability.Sampling)
    result.push(McpCapability.SamplingTools)
    result.push(McpCapability.Roots)
    result.push(McpCapability.Elicitation)
    result.push(McpCapability.ElicitationForm)
    result.push(McpCapability.ElicitationUrl)
    result.push(McpCapability.Extensions)
    result.push(McpCapability.Experimental)
    return result
}

JsonObject mcpCapabilitiesJson(Set<McpCapability> capabilities) {
    if capabilities == null { throw "mcpCapabilitiesJson: null" }
    JsonObject result = new JsonObject()
    List<McpCapability> all = allMcpCapabilities()
    Int index = 0
    while index < all.length() {
        McpCapability capability = all.get(index)
        if capabilities.has(capability) {
            McpCapability parent = mcpCapabilityParent(capability)
            String parentName = mcpCapabilityName(parent)
            String top = parentName
            if parent != capability {
                Int dot = parentName.length()
                top = parentName
            }
            JsonValue? existing = result.getOrNull(top)
            JsonObject childObject = new JsonObject()
            if existing != null {
                JsonValue actual = existing as JsonValue
                childObject = actual.asObject() as JsonObject
            } else {
                result.set(top, Json.object())
                JsonValue created = result.getOrNull(top) as JsonValue
                childObject = created.asObject() as JsonObject
            }
            if parent != capability {
                String child = mcpCapabilityName(capability).substring(
                    mcpCapabilityName(parent).length() + 1,
                    mcpCapabilityName(capability).length() -
                    mcpCapabilityName(parent).length() - 1)
                childObject.set(child, Json.bool(true))
            }
        }
        index = index + 1
    }
    if capabilities.has(McpCapability.Elicitation) &&
        !capabilities.has(McpCapability.ElicitationForm) &&
        !capabilities.has(McpCapability.ElicitationUrl) {
        JsonValue? elicitation = result.getOrNull("elicitation")
        if elicitation != null {
            JsonValue actualElicitation = elicitation as JsonValue
            JsonObject elicitationObject = actualElicitation.asObject() as JsonObject
            elicitationObject.set("form", Json.bool(true))
        }
    }
    return result
}

Result<Set<McpCapability>, Error> parseMcpCapabilities(JsonObject capabilities) {
    if capabilities == null { throw "parseMcpCapabilities: null" }
    Set<McpCapability> result = []
    List<String> keys = capabilities.keys()
    Int index = 0
    while index < keys.length() {
        String top = keys.get(index)
        McpCapability maybeParent = mcpCapabilityFromNameOrNull(top)
        if maybeParent != McpCapability.Unknown {
            McpCapability parent = maybeParent
            JsonValue? raw = capabilities.getOrNull(top)
            if raw == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "MCP capability must be object: " + top))
            }
            JsonValue actualRaw = raw as JsonValue
            if !actualRaw.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "MCP capability must be object: " + top))
            }
            result.add(parent)
            JsonObject childObject = actualRaw.asObject() as JsonObject
            List<String> childKeys = childObject.keys()
            Int childIndex = 0
            while childIndex < childKeys.length() {
                String child = childKeys.get(childIndex)
                McpCapability maybeChild = mcpChildCapability(parent, child)
                if maybeChild != McpCapability.Unknown { result.add(maybeChild) }
                childIndex = childIndex + 1
            }
            if top == "elicitation" && childKeys.length() == 0 {
                result.add(McpCapability.ElicitationForm)
            }
        }
        index = index + 1
    }
    return Ok(result)
}

McpCapability mcpCapabilityFromNameOrNull(String text) {
    Int index = 0
    List<McpCapability> all = allMcpCapabilities()
    while index < all.length() {
        McpCapability value = all.get(index)
        if mcpCapabilityName(value) == text { return value }
        index = index + 1
    }
    return McpCapability.Unknown
}

McpCapability mcpChildCapability(McpCapability parent, String child) {
    if parent == McpCapability.Tools && child == "listChanged" {
        return McpCapability.ToolsListChanged
    }
    if parent == McpCapability.Resources && child == "listChanged" {
        return McpCapability.ResourcesListChanged
    }
    if parent == McpCapability.Resources && child == "subscribe" {
        return McpCapability.ResourcesSubscribe
    }
    if parent == McpCapability.Prompts && child == "listChanged" {
        return McpCapability.PromptsListChanged
    }
    if parent == McpCapability.Sampling && child == "tools" {
        return McpCapability.SamplingTools
    }
    if parent == McpCapability.Elicitation && child == "form" {
        return McpCapability.ElicitationForm
    }
    if parent == McpCapability.Elicitation && child == "url" {
        return McpCapability.ElicitationUrl
    }
    return McpCapability.Unknown
}

Set<McpCapability> copyMcpCapabilities(Set<McpCapability> source) {
    Set<McpCapability> result = []
    List<McpCapability> all = allMcpCapabilities()
    Int index = 0
    while index < all.length() {
        if source.has(all.get(index)) { result.add(all.get(index)) }
        index = index + 1
    }
    return result
}

Set<McpCapability> normalizeMcpCapabilities(Set<McpCapability> source, Bool server) {
    Set<McpCapability> result = []
    List<McpCapability> all = allMcpCapabilities()
    Int index = 0
    while index < all.length() {
        McpCapability value = all.get(index)
        if source.has(value) {
            if server && !isServerMcpCapability(value) {
                throw "McpServerInfo: client capability not allowed"
            }
            if !server && !isClientMcpCapability(value) {
                throw "McpClientInfo: server capability not allowed"
            }
            result.add(value)
            result.add(mcpCapabilityParent(value))
        }
        index = index + 1
    }
    return result
}

// ---------- McpResource ----------
class McpResource {
    final String _uri
    final String _name
    final String _title
    final String _description
    final String _mimeType
    final Long? _sizeBytes

    McpResource(String uri, String name) {
        if !McpResource.isValidMcpResourceUri(uri) { throw "McpResource: invalid uri" }
        if name == null { throw "McpResource: null name" }
        self._uri = uri
        self._name = name
        self._title = ""
        self._description = ""
        self._mimeType = ""
        self._sizeBytes = null
    }

    McpResource(String uri, String name, String title, String description,
                String mimeType, Long? sizeBytes) {
        if !McpResource.isValidMcpResourceUri(uri) { throw "McpResource: invalid uri" }
        if name == null { throw "McpResource: null name" }
        if sizeBytes != null && (sizeBytes as Long) < 0 as Long {
            throw "McpResource: negative size"
        }
        self._uri = uri
        self._name = name
        self._title = title
        self._description = description
        self._mimeType = mimeType
        self._sizeBytes = sizeBytes
    }

    static Bool isValidMcpResourceUri(String uri) {
        if uri == null || uri == "" { return false }
        Int index = 0
        while index < uri.length() {
            Int code = uri.get(index)
            if code == 32 || code == 9 || code == 10 || code == 13 { return false }
            index = index + 1
        }
        return true
    }

    String uri() { return self._uri }
    String name() { return self._name }
    String title() { return self._title }
    String description() { return self._description }
    String mimeType() { return self._mimeType }
    Long? sizeBytes() { return self._sizeBytes }
    Bool hasSize() { return self._sizeBytes != null }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        object.set("uri", Json.string(self._uri))
        if self._name != "" { object.set("name", Json.string(self._name)) }
        if self._title != "" { object.set("title", Json.string(self._title)) }
        if self._description != "" { object.set("description", Json.string(self._description)) }
        if self._mimeType != "" { object.set("mimeType", Json.string(self._mimeType)) }
        if self._sizeBytes != null {
            object.set("size", Json.number(str(self._sizeBytes as Long)))
        }
        return object
    }

    static Result<McpResource, Error> parse(JsonValue value) {
        if value == null { throw "McpResource.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpResource: not an object"))
        }
        JsonObject object = value.asObject() as JsonObject
        JsonValue? uriValue = object.getOrNull("uri")
        if uriValue == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpResource: invalid uri"))
        }
        JsonValue actualUri = uriValue as JsonValue
        if !actualUri.isString() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpResource: invalid uri"))
        }
        String uri = actualUri.asString() as String
        if !McpResource.isValidMcpResourceUri(uri) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpResource: invalid uri"))
        }
        String name = mcpString(object, "name", "")
        String title = mcpString(object, "title", "")
        String description = mcpString(object, "description", "")
        String mimeType = mcpString(object, "mimeType", "")
        Long? sizeBytes = null
        JsonValue? sizeValue = object.getOrNull("size")
        if sizeValue != null {
            JsonValue actualSize = sizeValue as JsonValue
            if !actualSize.isNumber() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpResource: invalid size"))
            }
            JsonNumber number = actualSize.asNumber() as JsonNumber
            if !number.isInteger() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpResource: invalid size"))
            }
            Result<Long, Error> parsed = number.asLong()
            if parsed.isErr() || parsed.value() < 0 as Long {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpResource: invalid size"))
            }
            sizeBytes = parsed.value()
        }
        return Ok(new McpResource(uri, name, title, description, mimeType, sizeBytes))
    }

    Bool equals(McpResource other) {
        if other == null { return false }
        if self._uri != other.uri() || self._name != other.name() ||
            self._title != other.title() || self._description != other.description() ||
            self._mimeType != other.mimeType() { return false }
        if self._sizeBytes == null { return other.sizeBytes() == null }
        return other.sizeBytes() != null &&
            (self._sizeBytes as Long) == (other.sizeBytes() as Long)
    }

    String describe() { return self._uri + " size=" + str(self._sizeBytes) }
}

// ---------- McpContent ----------
class McpContent {
    final String _kind
    final String? _text
    final String? _data
    final String? _mimeType
    final McpResource? _resource
    final String? _blob

    private McpContent(String kind, String? text, String? data, String? mimeType,
                       McpResource? resource, String? blob) {
        self._kind = kind
        self._text = text
        self._data = data
        self._mimeType = mimeType
        self._resource = resource
        self._blob = blob
    }

    static McpContent text(String text) {
        if text == null { throw "McpContent.text: null" }
        return new McpContent("text", text, null, null, null, null)
    }

    static McpContent image(String data, String mimeType) {
        if data == null || data == "" { throw "McpContent.image: empty data" }
        if mimeType == null || mimeType == "" { throw "McpContent.image: empty mimeType" }
        return new McpContent("image", null, data, mimeType, null, null)
    }

    static McpContent audio(String data, String mimeType) {
        if data == null || data == "" { throw "McpContent.audio: empty data" }
        if mimeType == null || mimeType == "" { throw "McpContent.audio: empty mimeType" }
        return new McpContent("audio", null, data, mimeType, null, null)
    }

    static McpContent resourceLink(McpResource resource) {
        if resource == null { throw "McpContent.resourceLink: null resource" }
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
        if blob == null || blob == "" { throw "McpContent.embeddedBlob: empty blob" }
        return new McpContent("resource", null, null, null, resource, blob)
    }

    static McpContent resourceText(McpResource resource, String text) {
        if resource == null { throw "McpContent.resourceText: null resource" }
        if text == null { throw "McpContent.resourceText: null text" }
        return new McpContent("resource_content", text, null, null, resource, null)
    }

    static McpContent resourceBlob(McpResource resource, String blob) {
        if resource == null { throw "McpContent.resourceBlob: null resource" }
        if blob == null || blob == "" { throw "McpContent.resourceBlob: empty blob" }
        return new McpContent("resource_content", null, null, null, resource, blob)
    }

    String kind() { return self._kind }
    Bool isText() { return self._kind == "text" }
    Bool isImage() { return self._kind == "image" }
    Bool isAudio() { return self._kind == "audio" }
    Bool isResourceLink() { return self._kind == "resource_link" }
    Bool isResource() { return self._kind == "resource" }
    Bool isResourceContent() { return self._kind == "resource_content" }
    String? textValue() { return self._text }
    String? data() { return self._data }
    String? mimeType() {
        if self._resource != null {
            McpResource resource = self._resource as McpResource
            return resource.mimeType()
        }
        return self._mimeType
    }
    McpResource? resource() { return self._resource }
    String? blob() { return self._blob }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        if self.isResourceContent() {
            McpResource resource = self._resource as McpResource
            object.set("uri", Json.string(resource.uri()))
            object.set("mimeType", Json.string(resource.mimeType()))
            if self._text != null { object.set("text", Json.string(self._text as String)) }
            if self._blob != null { object.set("blob", Json.string(self._blob as String)) }
            return object
        }
        object.set("type", Json.string(self._kind))
        if self.isText() { object.set("text", Json.string(self._text as String)) }
        if self.isImage() || self.isAudio() {
            object.set("data", Json.string(self._data as String))
            object.set("mimeType", Json.string(self._mimeType as String))
        }
        if self.isResourceLink() {
            McpResource resource = self._resource as McpResource
            JsonObject resourceObject = resource.toJson()
            List<String> keys = resourceObject.keys()
            Int index = 0
            while index < keys.length() {
                String key = keys.get(index)
                object.set(key, resourceObject.getOr(key, Json.nullValue()))
                index = index + 1
            }
        }
        if self.isResource() {
            McpResource resource = self._resource as McpResource
            JsonValue resourceValue = Json.object()
            JsonObject resourceObject = resourceValue.asObject() as JsonObject
            JsonObject meta = resource.toJson()
            List<String> keys = meta.keys()
            Int index = 0
            while index < keys.length() {
                String key = keys.get(index)
                resourceObject.set(key, meta.getOr(key, Json.nullValue()))
                index = index + 1
            }
            if self._text != null {
                resourceObject.set("text", Json.string(self._text as String))
            }
            if self._blob != null {
                resourceObject.set("blob", Json.string(self._blob as String))
            }
            object.set("resource", resourceValue)
        }
        return object
    }

    static Result<McpContent, Error> parse(JsonValue value) {
        if value == null { throw "McpContent.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpContent: not an object"))
        }
        JsonObject object = value.asObject() as JsonObject
        JsonValue? typeValue = object.getOrNull("type")
        if typeValue == null {
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
                JsonValue actualText = textValue as JsonValue
                if !actualText.isString() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpContent: text must be string"))
                }
                return Ok(McpContent.resourceText(resource.value(),
                    actualText.asString() as String))
            }
            if blobValue != null {
                JsonValue actualBlob = blobValue as JsonValue
                if !actualBlob.isString() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "McpContent: invalid blob"))
                }
                return Ok(McpContent.resourceBlob(resource.value(),
                    actualBlob.asString() as String))
            }
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpContent: missing text or blob"))
        }
        JsonValue actualType = typeValue as JsonValue
        if !actualType.isString() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpContent: invalid type"))
        }
        String kind = actualType.asString() as String
        if kind == "text" {
            String text = mcpString(object, "text", "")
            return Ok(McpContent.text(text))
        }
        if kind == "image" || kind == "audio" {
            String data = mcpString(object, "data", "")
            String mime = mcpString(object, "mimeType", "")
            if mime == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: missing mimeType"))
            }
            if kind == "image" { return Ok(McpContent.image(data, mime)) }
            return Ok(McpContent.audio(data, mime))
        }
        if kind == "resource_link" {
            Result<McpResource, Error> resource = McpResource.parse(value)
            if resource.isErr() { return Err(resource.error()) }
            return Ok(McpContent.resourceLink(resource.value()))
        }
        if kind == "resource" {
            JsonValue? resourceValue = object.getOrNull("resource")
            if resourceValue == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: missing resource"))
            }
            Result<McpResource, Error> resource = McpResource.parse(resourceValue as JsonValue)
            if resource.isErr() { return Err(resource.error()) }
            JsonValue? textValue = object.getOrNull("text")
            JsonValue? blobValue = object.getOrNull("blob")
            if textValue != null && blobValue != null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpContent: text and blob are exclusive"))
            }
            if textValue != null {
                JsonValue actualTextValue = textValue as JsonValue
                return Ok(McpContent.embeddedText(resource.value(),
                    actualTextValue.asString() as String))
            }
            if blobValue != null {
                JsonValue actualBlobValue = blobValue as JsonValue
                return Ok(McpContent.embeddedBlob(resource.value(),
                    actualBlobValue.asString() as String))
            }
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpContent: missing text or blob"))
        }
        return Err(new BasicError(ErrorKind.InvalidArgument, "McpContent: unknown type"))
    }

    String describe() { return "content " + self._kind }
}

static Bool isKnownMcpProtocolVersionText(String text) {
    return text == "2024-11-05" || text == "2025-03-26" || text == "2025-06-18" ||
        text == "2025-11-25" || text == "2026-07-28"
}

static String mcpString(JsonObject object, String name, String fallback) {
    JsonValue? value = object.getOrNull(name)
    if value == null { return fallback }
    JsonValue actual = value as JsonValue
    if !actual.isString() { return fallback }
    return actual.asString() as String
}

// ---------- McpServerInfo ----------
class McpServerInfo {
    final String _name
    final String _title
    final String _version
    final String _description
    final String _websiteUrl
    final Set<McpCapability> _capabilities
    final List<String> _protocolVersions
    final String _instructions

    McpServerInfo(String name, String version) {
        if name == null || name == "" { throw "McpServerInfo: empty name" }
        if version == null || version == "" { throw "McpServerInfo: empty version" }
        self._name = name
        self._title = ""
        self._version = version
        self._description = ""
        self._websiteUrl = ""
        Set<McpCapability> emptyCaps = []
        self._capabilities = emptyCaps
        List<String> defaultVersions = []
        defaultVersions.push("2026-07-28")
        defaultVersions.push("2025-11-25")
        self._protocolVersions = defaultVersions
        self._instructions = ""
    }

    McpServerInfo(String name, String title, String version, String description,
                  String websiteUrl, Set<McpCapability> capabilities,
                  List<McpProtocolVersion> protocolVersions, String instructions) {
        if name == null || name == "" { throw "McpServerInfo: empty name" }
        if version == null || version == "" { throw "McpServerInfo: empty version" }
        if protocolVersions == null || protocolVersions.length() == 0 {
            throw "McpServerInfo: empty protocol versions"
        }
        self._name = name
        self._title = title
        self._version = version
        self._description = description
        self._websiteUrl = websiteUrl
        self._capabilities = normalizeMcpCapabilities(capabilities, true)
        List<String> versionTexts = []
        Int versionIndex = 0
        while versionIndex < protocolVersions.length() {
            versionTexts.push(mcpProtocolVersionText(protocolVersions.get(versionIndex)))
            versionIndex = versionIndex + 1
        }
        self._protocolVersions = versionTexts
        self._instructions = instructions
    }

    String name() { return self._name }
    String title() { return self._title }
    String version() { return self._version }
    String description() { return self._description }
    String websiteUrl() { return self._websiteUrl }
    Set<McpCapability> capabilities() { return copyMcpCapabilities(self._capabilities) }
    List<String> protocolVersionTexts() { return self._protocolVersions.copy() }
    String instructions() { return self._instructions }

    Bool supports(McpCapability capability) { return self._capabilities.has(capability) }

    Bool supportsProtocolVersion(McpProtocolVersion version) {
        String text = mcpProtocolVersionText(version)
        Int index = 0
        while index < self._protocolVersions.length() {
            if self._protocolVersions.get(index) == text { return true }
            index = index + 1
        }
        return false
    }

    McpProtocolVersion preferredProtocolVersion() {
        return parseMcpProtocolVersion(self._protocolVersions.get(0))
    }

    JsonObject toIdentityJson() {
        JsonObject object = new JsonObject()
        object.set("name", Json.string(self._name))
        if self._title != "" { object.set("title", Json.string(self._title)) }
        object.set("version", Json.string(self._version))
        if self._description != "" { object.set("description", Json.string(self._description)) }
        if self._websiteUrl != "" { object.set("websiteUrl", Json.string(self._websiteUrl)) }
        return object
    }

    JsonObject toJson() {
        JsonObject object = self.toIdentityJson()
        object.set("capabilities", mcpObjectValue(mcpCapabilitiesJson(self._capabilities)))
        JsonValue versions = Json.array()
        JsonArray array = versions.asArray() as JsonArray
        Int index = 0
        while index < self._protocolVersions.length() {
            array.add(Json.string(self._protocolVersions.get(index)))
            index = index + 1
        }
        object.set("supportedVersions", versions)
        if self._instructions != "" { object.set("instructions", Json.string(self._instructions)) }
        return object
    }

    static Result<McpServerInfo, Error> parse(JsonValue value) {
        if value == null { throw "McpServerInfo.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpServerInfo: not an object"))
        }
        JsonObject outer = value.asObject() as JsonObject
        JsonObject object = outer
        JsonValue? nested = outer.getOrNull("serverInfo")
        if nested != null {
            JsonValue actualNested = nested as JsonValue
            if !actualNested.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpServerInfo: invalid serverInfo"))
            }
            object = actualNested.asObject() as JsonObject
        }
        String name = mcpString(object, "name", "")
        String version = mcpString(object, "version", "")
        if name == "" || version == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpServerInfo: name/version required"))
        }
        Set<McpCapability> capabilities = []
        JsonValue? capsValue = object.getOrNull("capabilities")
        if capsValue != null {
            JsonValue actualCaps = capsValue as JsonValue
            if !actualCaps.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpServerInfo: invalid capabilities"))
            }
            Result<Set<McpCapability>, Error> parsedCaps =
                parseMcpCapabilities(actualCaps.asObject() as JsonObject)
            if parsedCaps.isErr() { return Err(parsedCaps.error()) }
            capabilities = parsedCaps.value()
        }
        List<McpProtocolVersion> versions = []
        JsonValue? versionsValue = object.getOrNull("supportedVersions")
        if versionsValue != null {
            JsonValue actualVersions = versionsValue as JsonValue
            if !actualVersions.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpServerInfo: invalid versions"))
            }
            JsonArray array = actualVersions.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                JsonValue entry = array.get(index)
                if !entry.isString() {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "McpServerInfo: invalid version"))
                }
                String versionText = entry.asString() as String
                if !isKnownMcpProtocolVersionText(versionText) {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "invalid protocol version"))
                }
                versions.push(parseMcpProtocolVersion(versionText))
                index = index + 1
            }
        }
        if versions.length() == 0 {
            versions.push(McpProtocolVersion.V2026_07_28)
            versions.push(McpProtocolVersion.V2025_11_25)
        }
        return Ok(new McpServerInfo(name, mcpString(object, "title", ""), version,
            mcpString(object, "description", ""), mcpString(object, "websiteUrl", ""),
            capabilities, versions, mcpString(object, "instructions", "")))
    }

    Bool equals(McpServerInfo other) {
        if other == null { return false }
        return self._name == other.name() && self._title == other.title() &&
            self._version == other.version() && self._description == other.description() &&
            self._websiteUrl == other.websiteUrl() &&
            mcpSameCapabilities(self._capabilities, other.capabilities()) &&
            mcpSameVersions(self._protocolVersions, other.protocolVersionTexts()) &&
            self._instructions == other.instructions()
    }

    String describe() { return "server " + self._name + " " + self._version }
}

// ---------- McpClientInfo ----------
class McpClientInfo {
    final String _name
    final String _title
    final String _version
    final String _description
    final String _websiteUrl
    final Set<McpCapability> _capabilities
    final List<String> _protocolVersions
    final String _instructions

    McpClientInfo(String name, String version) {
        if name == null || name == "" { throw "McpClientInfo: empty name" }
        if version == null || version == "" { throw "McpClientInfo: empty version" }
        self._name = name
        self._title = ""
        self._version = version
        self._description = ""
        self._websiteUrl = ""
        Set<McpCapability> emptyCaps = []
        self._capabilities = emptyCaps
        List<String> defaultVersions = []
        defaultVersions.push("2026-07-28")
        defaultVersions.push("2025-11-25")
        self._protocolVersions = defaultVersions
        self._instructions = ""
    }

    McpClientInfo(String name, String title, String version, String description,
                  String websiteUrl, Set<McpCapability> capabilities,
                  List<McpProtocolVersion> protocolVersions, String instructions) {
        if name == null || name == "" { throw "McpClientInfo: empty name" }
        if version == null || version == "" { throw "McpClientInfo: empty version" }
        if protocolVersions == null || protocolVersions.length() == 0 {
            throw "McpClientInfo: empty protocol versions"
        }
        self._name = name
        self._title = title
        self._version = version
        self._description = description
        self._websiteUrl = websiteUrl
        self._capabilities = normalizeMcpCapabilities(capabilities, false)
        List<String> versionTexts = []
        Int versionIndex = 0
        while versionIndex < protocolVersions.length() {
            versionTexts.push(mcpProtocolVersionText(protocolVersions.get(versionIndex)))
            versionIndex = versionIndex + 1
        }
        self._protocolVersions = versionTexts
        self._instructions = instructions
    }

    String name() { return self._name }
    String title() { return self._title }
    String version() { return self._version }
    String description() { return self._description }
    String websiteUrl() { return self._websiteUrl }
    Set<McpCapability> capabilities() { return copyMcpCapabilities(self._capabilities) }
    List<String> protocolVersionTexts() { return self._protocolVersions.copy() }
    String instructions() { return self._instructions }

    Bool supports(McpCapability capability) { return self._capabilities.has(capability) }

    Bool supportsProtocolVersion(McpProtocolVersion version) {
        String text = mcpProtocolVersionText(version)
        Int index = 0
        while index < self._protocolVersions.length() {
            if self._protocolVersions.get(index) == text { return true }
            index = index + 1
        }
        return false
    }

    McpProtocolVersion preferredProtocolVersion() {
        return parseMcpProtocolVersion(self._protocolVersions.get(0))
    }

    JsonObject toIdentityJson() {
        JsonObject object = new JsonObject()
        object.set("name", Json.string(self._name))
        if self._title != "" { object.set("title", Json.string(self._title)) }
        object.set("version", Json.string(self._version))
        if self._description != "" { object.set("description", Json.string(self._description)) }
        if self._websiteUrl != "" { object.set("websiteUrl", Json.string(self._websiteUrl)) }
        return object
    }

    JsonObject toJson() {
        JsonObject object = self.toIdentityJson()
        object.set("capabilities", mcpObjectValue(mcpCapabilitiesJson(self._capabilities)))
        JsonValue versions = Json.array()
        JsonArray array = versions.asArray() as JsonArray
        Int index = 0
        while index < self._protocolVersions.length() {
            array.add(Json.string(self._protocolVersions.get(index)))
            index = index + 1
        }
        object.set("supportedVersions", versions)
        if self._instructions != "" { object.set("instructions", Json.string(self._instructions)) }
        return object
    }

    static Result<McpClientInfo, Error> parse(JsonValue value) {
        if value == null { throw "McpClientInfo.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpClientInfo: not an object"))
        }
        JsonObject outer = value.asObject() as JsonObject
        JsonObject object = outer
        JsonValue? nested = outer.getOrNull("clientInfo")
        if nested != null {
            JsonValue actualNested = nested as JsonValue
            if !actualNested.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpClientInfo: invalid clientInfo"))
            }
            object = actualNested.asObject() as JsonObject
        }
        String name = mcpString(object, "name", "")
        String version = mcpString(object, "version", "")
        if name == "" || version == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpClientInfo: name/version required"))
        }
        Set<McpCapability> capabilities = []
        JsonValue? capsValue = object.getOrNull("capabilities")
        if capsValue != null {
            JsonValue actualCaps = capsValue as JsonValue
            if !actualCaps.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpClientInfo: invalid capabilities"))
            }
            Result<Set<McpCapability>, Error> parsedCaps =
                parseMcpCapabilities(actualCaps.asObject() as JsonObject)
            if parsedCaps.isErr() { return Err(parsedCaps.error()) }
            capabilities = parsedCaps.value()
        }
        List<McpProtocolVersion> versions = []
        JsonValue? versionsValue = object.getOrNull("supportedVersions")
        if versionsValue != null {
            JsonValue actualVersions = versionsValue as JsonValue
            if !actualVersions.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpClientInfo: invalid versions"))
            }
            JsonArray array = actualVersions.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                JsonValue entry = array.get(index)
                if !entry.isString() {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "McpClientInfo: invalid version"))
                }
                String versionText = entry.asString() as String
                if !isKnownMcpProtocolVersionText(versionText) {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "invalid protocol version"))
                }
                versions.push(parseMcpProtocolVersion(versionText))
                index = index + 1
            }
        }
        if versions.length() == 0 {
            versions.push(McpProtocolVersion.V2026_07_28)
            versions.push(McpProtocolVersion.V2025_11_25)
        }
        return Ok(new McpClientInfo(name, mcpString(object, "title", ""), version,
            mcpString(object, "description", ""), mcpString(object, "websiteUrl", ""),
            capabilities, versions, mcpString(object, "instructions", "")))
    }

    Bool equals(McpClientInfo other) {
        if other == null { return false }
        return self._name == other.name() && self._title == other.title() &&
            self._version == other.version() && self._description == other.description() &&
            self._websiteUrl == other.websiteUrl() &&
            mcpSameCapabilities(self._capabilities, other.capabilities()) &&
            mcpSameVersions(self._protocolVersions, other.protocolVersionTexts()) &&
            self._instructions == other.instructions()
    }

    String describe() { return "client " + self._name + " " + self._version }
}

static JsonValue mcpObjectValue(JsonObject object) {
    JsonValue value = Json.object()
    JsonObject target = value.asObject() as JsonObject
    List<String> keys = object.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        target.set(key, object.getOr(key, Json.nullValue()))
        index = index + 1
    }
    return value
}

static Bool mcpSameCapabilities(Set<McpCapability> left, Set<McpCapability> right) {
    List<McpCapability> all = allMcpCapabilities()
    Int index = 0
    while index < all.length() {
        McpCapability value = all.get(index)
        if left.has(value) != right.has(value) { return false }
        index = index + 1
    }
    return true
}

static Bool mcpSameVersions(List<String> left, List<String> right) {
    if left.length() != right.length() { return false }
    Int index = 0
    while index < left.length() {
        if left.get(index) != right.get(index) { return false }
        index = index + 1
    }
    return true
}

// ---------- McpPrompt ----------
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

    McpPrompt(String name, String title, String description, List<String> argumentNames,
              Map<String, String> argumentDescriptions, Set<String> requiredArguments,
              List<String> messageRoles, List<McpContent> messages) {
        if name == null || name == "" { throw "McpPrompt: empty name" }
        if argumentNames == null || argumentDescriptions == null ||
            requiredArguments == null || messageRoles == null || messages == null {
            throw "McpPrompt: null argument"
        }
        if messageRoles.length() != messages.length() {
            throw "McpPrompt: roles/messages length mismatch"
        }
        Int index = 0
        while index < messages.length() {
            if messages.get(index) == null { throw "McpPrompt: null message" }
            if messageRoles.get(index) != "user" && messageRoles.get(index) != "assistant" {
                throw "McpPrompt: invalid role"
            }
            index = index + 1
        }
        self._name = name
        self._title = title
        self._description = description
        self._argumentNames = argumentNames.copy()
        self._argumentDescriptions = argumentDescriptions
        self._requiredArguments = requiredArguments
        self._messageRoles = messageRoles.copy()
        self._messages = messages.copy()
        self._resolved = messages.length() > 0
    }

    static McpPrompt template(String name) {
        List<String> names = []
        Map<String, String> descriptions = [:]
        Set<String> required = []
        List<String> roles = []
        List<McpContent> messages = []
        return new McpPrompt(name, "", "", names, descriptions, required, roles, messages)
    }

    String name() { return self._name }
    String title() { return self._title }
    String description() { return self._description }
    List<String> argumentNames() { return self._argumentNames.copy() }
    Int argumentCount() { return self._argumentNames.length() }
    List<McpContent> messages() { return self._messages.copy() }
    Int messageCount() { return self._messages.length() }
    String messageRole(Int index) { return self._messageRoles.get(index) }
    Bool isResolved() { return self._resolved }

    String argumentDescription(String name) {
        if !self._argumentDescriptions.has(name) {
            throw "McpPrompt.argumentDescription: unknown argument"
        }
        return self._argumentDescriptions.getOr(name, "")
    }

    Bool isArgumentRequired(String name) { return self._requiredArguments.has(name) }

    McpPrompt resolve(Map<String, String> values) {
        if values == null { throw "McpPrompt.resolve: null values" }
        List<McpContent> resolvedMessages = []
        Int index = 0
        while index < self._messages.length() {
            McpContent message = self._messages.get(index)
            if message.isText() {
                String text = message.textValue() as String
                List<String> keys = values.keys()
                Int keyIndex = 0
                while keyIndex < keys.length() {
                    String key = keys.get(keyIndex)
                    text = text.replace("{" + key + "}", values.getOr(key, ""))
                    keyIndex = keyIndex + 1
                }
                resolvedMessages.push(McpContent.text(text))
            } else {
                resolvedMessages.push(message)
            }
            index = index + 1
        }
        return new McpPrompt(self._name, self._title, self._description,
            self._argumentNames, self._argumentDescriptions, self._requiredArguments,
            self._messageRoles, resolvedMessages)
    }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        object.set("name", Json.string(self._name))
        if self._title != "" { object.set("title", Json.string(self._title)) }
        if self._description != "" { object.set("description", Json.string(self._description)) }
        if self._argumentNames.length() > 0 {
            JsonValue arguments = Json.array()
            JsonArray array = arguments.asArray() as JsonArray
            Int index = 0
            while index < self._argumentNames.length() {
                String name = self._argumentNames.get(index)
                JsonValue entry = Json.object()
                JsonObject argument = entry.asObject() as JsonObject
                argument.set("name", Json.string(name))
                if self._argumentDescriptions.has(name) {
                    argument.set("description", Json.string(self._argumentDescriptions.getOr(name, "")))
                }
                if self._requiredArguments.has(name) { argument.set("required", Json.bool(true)) }
                array.add(entry)
                index = index + 1
            }
            object.set("arguments", arguments)
        }
        if self._resolved {
            JsonValue messages = Json.array()
            JsonArray array = messages.asArray() as JsonArray
            Int index = 0
            while index < self._messages.length() {
                JsonValue entry = Json.object()
                JsonObject message = entry.asObject() as JsonObject
                message.set("role", Json.string(self._messageRoles.get(index)))
                message.set("content", mcpObjectValue(self._messages.get(index).toJson()))
                array.add(entry)
                index = index + 1
            }
            object.set("messages", messages)
        }
        return object
    }

    static Result<McpPrompt, Error> parse(JsonValue value) {
        if value == null { throw "McpPrompt.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpPrompt: not an object"))
        }
        JsonObject object = value.asObject() as JsonObject
        String name = mcpString(object, "name", "")
        if name == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpPrompt: empty name"))
        }
        List<String> argumentNames = []
        Map<String, String> descriptions = [:]
        Set<String> required = []
        JsonValue? argsValue = object.getOrNull("arguments")
        if argsValue != null {
            JsonValue actualArgs = argsValue as JsonValue
            if !actualArgs.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpPrompt: invalid arguments"))
            }
            JsonArray array = actualArgs.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                JsonValue entry = array.get(index)
                if !entry.isObject() {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "McpPrompt: invalid argument"))
                }
                JsonObject argument = entry.asObject() as JsonObject
                String argumentName = mcpString(argument, "name", "")
                if argumentName == "" { return Err(new BasicError(ErrorKind.InvalidArgument,
                    "McpPrompt: empty argument")) }
                argumentNames.push(argumentName)
                String argumentDescription = mcpString(argument, "description", "")
                if argumentDescription != "" { descriptions.put(argumentName, argumentDescription) }
                JsonValue? requiredValue = argument.getOrNull("required")
                if requiredValue != null {
                    JsonValue actualRequired = requiredValue as JsonValue
                    if !actualRequired.isBool() {
                        return Err(new BasicError(ErrorKind.InvalidArgument, "McpPrompt: invalid required"))
                    }
                    if actualRequired.asBool() as Bool { required.add(argumentName) }
                }
                index = index + 1
            }
        }
        List<String> roles = []
        List<McpContent> messages = []
        JsonValue? messagesValue = object.getOrNull("messages")
        if messagesValue != null {
            JsonValue actualMessages = messagesValue as JsonValue
            if !actualMessages.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpPrompt: invalid messages"))
            }
            JsonArray array = actualMessages.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                JsonValue entry = array.get(index)
                if !entry.isObject() {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "McpPrompt: invalid message"))
                }
                JsonObject message = entry.asObject() as JsonObject
                String role = mcpString(message, "role", "")
                JsonValue? contentValue = message.getOrNull("content")
                if contentValue == null {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "McpPrompt: missing content"))
                }
                Result<McpContent, Error> content = McpContent.parse(contentValue as JsonValue)
                if content.isErr() { return Err(content.error()) }
                roles.push(role)
                messages.push(content.value())
                index = index + 1
            }
        }
        return Ok(new McpPrompt(name, mcpString(object, "title", ""),
            mcpString(object, "description", ""), argumentNames, descriptions, required,
            roles, messages))
    }

    String describe() { return "prompt " + self._name + " args=" + str(self._argumentNames.length()) }
}

// ---------- McpTool ----------
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
        if !McpTool.isValidMcpToolName(name) { throw "McpTool: invalid name" }
        if inputSchema == null || !inputSchema.isObject() {
            throw "McpTool: inputSchema must be object"
        }
        self._name = name
        self._title = ""
        self._description = ""
        self._inputSchema = inputSchema
        self._outputSchema = null
        self._readOnlyHint = false
        self._destructiveHint = true
        self._idempotentHint = false
        self._openWorldHint = true
    }

    McpTool(String name, String title, String description, JsonValue inputSchema,
            JsonValue? outputSchema, Bool readOnlyHint, Bool destructiveHint,
            Bool idempotentHint, Bool openWorldHint) {
        if !McpTool.isValidMcpToolName(name) { throw "McpTool: invalid name" }
        if inputSchema == null || !inputSchema.isObject() {
            throw "McpTool: inputSchema must be object"
        }
        if outputSchema != null {
            JsonValue actualOutputSchema = outputSchema as JsonValue
            if !actualOutputSchema.isObject() {
                throw "McpTool: outputSchema must be object"
            }
        }
        self._name = name
        self._title = title
        self._description = description
        self._inputSchema = inputSchema
        self._outputSchema = outputSchema
        self._readOnlyHint = readOnlyHint
        self._destructiveHint = destructiveHint
        self._idempotentHint = idempotentHint
        self._openWorldHint = openWorldHint
    }

    static Bool isValidMcpToolName(String name) {
        if name == null || name.length() < 1 || name.length() > 128 { return false }
        Int index = 0
        while index < name.length() {
            Int code = name.get(index)
            Bool alnum = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
                (code >= 97 && code <= 122)
            if !alnum && code != 95 && code != 45 && code != 46 { return false }
            index = index + 1
        }
        return true
    }

    String name() { return self._name }
    String title() { return self._title }
    String description() { return self._description }
    JsonValue inputSchema() { return self._inputSchema }
    JsonValue? outputSchema() { return self._outputSchema }
    Bool hasOutputSchema() { return self._outputSchema != null }
    Bool readOnlyHint() { return self._readOnlyHint }
    Bool destructiveHint() { return self._destructiveHint }
    Bool idempotentHint() { return self._idempotentHint }
    Bool openWorldHint() { return self._openWorldHint }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        object.set("name", Json.string(self._name))
        if self._title != "" { object.set("title", Json.string(self._title)) }
        if self._description != "" { object.set("description", Json.string(self._description)) }
        object.set("inputSchema", self._inputSchema)
        if self._outputSchema != null {
            object.set("outputSchema", self._outputSchema as JsonValue)
        }
        JsonValue annotations = Json.object()
        JsonObject hint = annotations.asObject() as JsonObject
        hint.set("readOnlyHint", Json.bool(self._readOnlyHint))
        hint.set("destructiveHint", Json.bool(self._destructiveHint))
        hint.set("idempotentHint", Json.bool(self._idempotentHint))
        hint.set("openWorldHint", Json.bool(self._openWorldHint))
        object.set("annotations", annotations)
        return object
    }

    static Result<McpTool, Error> parse(JsonValue value) {
        if value == null { throw "McpTool.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpTool: not an object"))
        }
        JsonObject object = value.asObject() as JsonObject
        String name = mcpString(object, "name", "")
        if !McpTool.isValidMcpToolName(name) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpTool: invalid name"))
        }
        JsonValue? schemaValue = object.getOrNull("inputSchema")
        if schemaValue == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpTool: inputSchema must be object"))
        }
        JsonValue actualSchema = schemaValue as JsonValue
        if !actualSchema.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpTool: inputSchema must be object"))
        }
        JsonValue? outputSchema = null
        JsonValue? outputValue = object.getOrNull("outputSchema")
        if outputValue != null {
            JsonValue actualOutput = outputValue as JsonValue
            if !actualOutput.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpTool: outputSchema must be object"))
            }
            outputSchema = actualOutput
        }
        Bool readOnly = false
        Bool destructive = true
        Bool idempotent = false
        Bool openWorld = true
        JsonValue? annotationsValue = object.getOrNull("annotations")
        if annotationsValue != null {
            JsonValue actualAnnotations = annotationsValue as JsonValue
            if actualAnnotations.isObject() {
                JsonObject annotations = actualAnnotations.asObject() as JsonObject
                JsonValue? valueReadOnly = annotations.getOrNull("readOnlyHint")
                if valueReadOnly != null { JsonValue actual = valueReadOnly as JsonValue; readOnly = actual.asBool() as Bool }
                JsonValue? valueDestructive = annotations.getOrNull("destructiveHint")
                if valueDestructive != null { JsonValue actual = valueDestructive as JsonValue; destructive = actual.asBool() as Bool }
                JsonValue? valueIdempotent = annotations.getOrNull("idempotentHint")
                if valueIdempotent != null { JsonValue actual = valueIdempotent as JsonValue; idempotent = actual.asBool() as Bool }
                JsonValue? valueOpenWorld = annotations.getOrNull("openWorldHint")
                if valueOpenWorld != null { JsonValue actual = valueOpenWorld as JsonValue; openWorld = actual.asBool() as Bool }
            }
        }
        return Ok(new McpTool(name, mcpString(object, "title", ""),
            mcpString(object, "description", ""), schemaValue as JsonValue, outputSchema,
            readOnly, destructive, idempotent, openWorld))
    }

    String describe() { return "tool " + self._name + " output=" + str(self.hasOutputSchema()) }
}

// ---------- McpToolResult ----------
class McpToolResult {
    final List<McpContent> _contents
    final JsonValue? _structuredContent
    final Bool _isError

    McpToolResult(List<McpContent> contents) {
        if contents == null { throw "McpToolResult: null contents" }
        self._contents = contents.copy()
        self._structuredContent = null
        self._isError = false
    }

    McpToolResult(List<McpContent> contents, JsonValue? structuredContent, Bool isError) {
        if contents == null { throw "McpToolResult: null contents" }
        self._contents = contents.copy()
        self._structuredContent = structuredContent
        self._isError = isError
    }

    List<McpContent> contents() { return self._contents.copy() }
    Int contentCount() { return self._contents.length() }
    JsonValue? structuredContent() { return self._structuredContent }
    Bool hasStructuredContent() { return self._structuredContent != null }
    Bool isError() { return self._isError }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        JsonValue content = Json.array()
        JsonArray array = content.asArray() as JsonArray
        Int index = 0
        while index < self._contents.length() {
            array.add(mcpObjectValue(self._contents.get(index).toJson()))
            index = index + 1
        }
        object.set("content", content)
        if self._structuredContent != null {
            object.set("structuredContent", self._structuredContent as JsonValue)
        }
        if self._isError { object.set("isError", Json.bool(true)) }
        return object
    }

    static Result<McpToolResult, Error> parse(JsonValue value) {
        if value == null { throw "McpToolResult.parse: null value" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpToolResult: not an object"))
        }
        JsonObject object = value.asObject() as JsonObject
        List<McpContent> contents = []
        JsonValue? contentValue = object.getOrNull("content")
        if contentValue != null {
            JsonValue actualContent = contentValue as JsonValue
            if !actualContent.isArray() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpToolResult: invalid content"))
            }
            JsonArray array = actualContent.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                Result<McpContent, Error> parsed = McpContent.parse(array.get(index))
                if parsed.isErr() { return Err(parsed.error()) }
                contents.push(parsed.value())
                index = index + 1
            }
        }
        JsonValue? structured = object.getOrNull("structuredContent")
        Bool isError = false
        JsonValue? errorValue = object.getOrNull("isError")
        if errorValue != null {
            JsonValue actualError = errorValue as JsonValue
            if !actualError.isBool() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "McpToolResult: invalid isError"))
            }
            isError = actualError.asBool() as Bool
        }
        return Ok(new McpToolResult(contents, structured, isError))
    }

    String describe() { return "toolResult contents=" + str(self._contents.length()) + " error=" + str(self._isError) }
}

// ---------- McpSession ----------
class McpSession {
    final McpProtocolVersion _protocolVersion
    final McpServerInfo _serverInfo
    final McpClientInfo _clientInfo
    final String _sessionIdentifier
    final Bool _modern
    final Bool _initialized
    final Bool _open

    McpSession(McpProtocolVersion protocolVersion, McpServerInfo serverInfo,
               McpClientInfo clientInfo, String sessionIdentifier, Bool modern,
               Bool initialized, Bool open) {
        if protocolVersion == null || serverInfo == null || clientInfo == null ||
            sessionIdentifier == null {
            throw "McpSession: null argument"
        }
        if modern != isModernMcpProtocolVersion(protocolVersion) {
            throw "McpSession: modern flag mismatch"
        }
        self._protocolVersion = protocolVersion
        self._serverInfo = serverInfo
        self._clientInfo = clientInfo
        self._sessionIdentifier = sessionIdentifier
        self._modern = modern
        self._initialized = initialized
        self._open = open
    }

    McpProtocolVersion protocolVersion() { return self._protocolVersion }
    McpServerInfo serverInfo() { return self._serverInfo }
    McpClientInfo clientInfo() { return self._clientInfo }
    String sessionIdentifier() { return self._sessionIdentifier }
    Bool hasSessionIdentifier() { return self._sessionIdentifier != "" }
    Bool isModern() { return self._modern }
    Bool isLegacy() { return !self._modern }
    Bool isInitialized() { return self._initialized }
    Bool isOpen() { return self._open }
    Bool serverSupports(McpCapability capability) { return self._serverInfo.supports(capability) }
    Bool clientSupports(McpCapability capability) { return self._clientInfo.supports(capability) }
    String describe() { return "mcp session " + mcpProtocolVersionText(self._protocolVersion) + " modern=" + str(self._modern) }
}

// ---------- McpTransport protocol ----------
protocol McpTransport {
    Result<JsonRpcResponse, Error> request(Context context, JsonRpcRequest request,
        Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler);
    Result<Unit, Error> selectProtocolVersion(Context context, McpProtocolVersion version);
    Result<Unit, Error> notify(Context context, JsonRpcRequest notification);
    Result<JsonRpcRequest, Error> receive(Context context);
    Result<Unit, Error> respond(Context context, JsonRpcResponse response);
    Result<Unit, Error> acknowledge(Context context);
    Result<Unit, Error> cancel(Context context, JsonRpcId identifier, String reason);
    String? sessionIdentifier();
    Result<Unit, Error> close();
    Bool isOpen();
}


// ---------- Stdio transport helpers ----------
protocol McpReader {
    Result<String?, Error> readLine(Context context);
}

protocol McpWriter {
    Bool isOpen();
    Result<Unit, Error> writeAll(Context context, Bytes data);
    Result<Unit, Error> flush();
}

class McpStdioTransport implements McpTransport {
    final McpReader _input
    final McpWriter _output
    final Long _maximumMessageBytes
    final Bool _ownsStreams
    Bool _open

    McpStdioTransport(McpReader input, McpWriter output) {
        if input == null || output == null { throw "McpStdioTransport: null stream" }
        self._input = input
        self._output = output
        self._maximumMessageBytes = 8388608 as Long
        self._ownsStreams = false
        self._open = true
    }

    McpStdioTransport(McpReader input, McpWriter output, Long maximumMessageBytes,
                      Bool ownsStreams, Int maximumConcurrentRequests) {
        if input == null || output == null { throw "McpStdioTransport: null stream" }
        if maximumMessageBytes <= 0 as Long { throw "McpStdioTransport: non-positive maximum" }
        if maximumConcurrentRequests != 1 { throw "McpStdioTransport: concurrency unsupported" }
        self._input = input
        self._output = output
        self._maximumMessageBytes = maximumMessageBytes
        self._ownsStreams = ownsStreams
        self._open = true
    }

    Result<JsonRpcResponse, Error> request(Context context, JsonRpcRequest request,
            Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler) {
        if !self._open { return Err(new BasicError(ErrorKind.Unavailable, "mcp stdio closed")) }
        if !request.hasIdentifier() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "mcp: request requires id"))
        }
        Result<Unit, Error> written = self.writeMessage(context, request.toJson())
        if written.isErr() { return Err(written.error()) }
        while true {
            Result<String?, Error> line = self._input.readLine(context)
            if line.isErr() { return Err(line.error()) }
            String? value = line.value()
            if value == null {
                return Err(new BasicError(ErrorKind.Unavailable, "mcp stdio EOF"))
            }
            Result<JsonValue, Error> parsed = Json.parse(value as String)
            if parsed.isErr() {
                return Err(new BasicError(ErrorKind.DataCorrupted, "mcp stdio: bad json"))
            }
            JsonValue message = parsed.value()
            if message.isObject() {
                JsonObject object = message.asObject() as JsonObject
                if object.has("result") || object.has("error") {
                    Result<JsonRpcResponse, Error> response = JsonRpcResponse.parse(message)
                    if response.isErr() { return Err(response.error()) }
                    JsonRpcId? receivedId = response.value().identifier()
                    if receivedId == null {
                        return Err(new BasicError(ErrorKind.DataCorrupted, "mcp stdio: missing id"))
                    }
                    JsonRpcId actualReceivedId = receivedId as JsonRpcId
                    JsonRpcId actualRequestId = request.identifier() as JsonRpcId
                    if !actualReceivedId.equals(actualRequestId) {
                        return Err(new BasicError(ErrorKind.DataCorrupted, "mcp stdio: id mismatch"))
                    }
                    return Ok(response.value())
                }
            }
            Result<JsonRpcRequest, Error> received = JsonRpcRequest.parse(message)
            if received.isErr() { return Err(received.error()) }
            if received.value().hasIdentifier() {
                return Err(new BasicError(ErrorKind.Unsupported, "mcp stdio: server request"))
            }
            notificationHandler(context, received.value())
        }
    }

    Result<Unit, Error> selectProtocolVersion(Context context, McpProtocolVersion version) {
        if !self._open { return Err(new BasicError(ErrorKind.Unavailable, "mcp stdio closed")) }
        return Ok()
    }

    Result<Unit, Error> notify(Context context, JsonRpcRequest notification) {
        if !self._open { return Err(new BasicError(ErrorKind.Unavailable, "mcp stdio closed")) }
        if notification.hasIdentifier() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "mcp: notification has id"))
        }
        return self.writeMessage(context, notification.toJson())
    }

    Result<JsonRpcRequest, Error> receive(Context context) {
        if !self._open { return Err(new BasicError(ErrorKind.Unavailable, "mcp stdio closed")) }
        Result<String?, Error> line = self._input.readLine(context)
        if line.isErr() { return Err(line.error()) }
        String? value = line.value()
        if value == null { return Err(new BasicError(ErrorKind.Unavailable, "mcp stdio EOF")) }
        Result<JsonValue, Error> parsed = Json.parse(value as String)
        if parsed.isErr() { return Err(new BasicError(ErrorKind.DataCorrupted, "mcp stdio: bad json")) }
        return JsonRpcRequest.parse(parsed.value())
    }

    Result<Unit, Error> respond(Context context, JsonRpcResponse response) {
        if !self._open { return Err(new BasicError(ErrorKind.Unavailable, "mcp stdio closed")) }
        return self.writeMessage(context, response.toJson())
    }

    Result<Unit, Error> acknowledge(Context context) { return Ok() }

    Result<Unit, Error> cancel(Context context, JsonRpcId identifier, String reason) {
        if identifier == null { throw "McpStdioTransport.cancel: null id" }
        JsonRpcRequest notification = JsonRpcRequest.notification("notifications/cancelled")
        return self.notify(context, notification)
    }

    String? sessionIdentifier() { return null }
    Bool isOpen() { return self._open }

    Result<Unit, Error> close() {
        self._open = false
        return Ok()
    }

    private Result<Unit, Error> writeMessage(Context context, JsonValue value) {
        if !self._output.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "mcp stdio output closed"))
        }
        String line = Json.stringify(value)
        Result<Unit, Error> written = self._output.writeAll(context, fromUtf8(line + "\n"))
        if written.isErr() { return Err(written.error()) }
        return self._output.flush()
    }
}

// ---------- Handler slots ----------
class McpToolHandlerSlot {
    final Result<McpToolResult, Error>(Context, JsonValue) _handler
    McpToolHandlerSlot(Result<McpToolResult, Error>(Context, JsonValue) handler) {
        self._handler = handler
    }
    Result<McpToolResult, Error> run(Context context, JsonValue arguments) {
        return self._handler(context, arguments)
    }
}

class McpResourceHandlerSlot {
    final Result<McpContent, Error>(Context, String) _handler
    McpResourceHandlerSlot(Result<McpContent, Error>(Context, String) handler) {
        self._handler = handler
    }
    Result<McpContent, Error> run(Context context, String uri) { return self._handler(context, uri) }
}

class McpPromptHandlerSlot {
    final Result<McpPrompt, Error>(Context, Map<String, String>) _handler
    McpPromptHandlerSlot(Result<McpPrompt, Error>(Context, Map<String, String>) handler) {
        self._handler = handler
    }
    Result<McpPrompt, Error> run(Context context, Map<String, String> arguments) {
        return self._handler(context, arguments)
    }
}

// ---------- McpServer ----------
class McpServer {
    final McpServerInfo _serverInfo
    final List<McpTool> _tools
    final List<McpToolHandlerSlot> _toolHandlers
    final List<McpResource> _resources
    final List<McpResourceHandlerSlot> _resourceHandlers
    final List<McpPrompt> _prompts
    final List<McpPromptHandlerSlot> _promptHandlers
    Bool _open

    McpServer(McpServerInfo serverInfo) {
        if serverInfo == null { throw "McpServer: null serverInfo" }
        self._serverInfo = serverInfo
        self._tools = []
        self._toolHandlers = []
        self._resources = []
        self._resourceHandlers = []
        self._prompts = []
        self._promptHandlers = []
        self._open = true
    }

    Result<Unit, Error> registerTool(McpTool tool,
            Result<McpToolResult, Error>(Context, JsonValue) handler) {
        if tool == null { throw "McpServer.registerTool: null tool" }
        Int index = 0
        while index < self._tools.length() {
            if self._tools.get(index).name() == tool.name() {
                return Err(new BasicError(ErrorKind.AlreadyExists, "duplicate tool: " + tool.name()))
            }
            index = index + 1
        }
        self._tools.push(tool)
        self._toolHandlers.push(new McpToolHandlerSlot(handler))
        return Ok()
    }

    Result<Unit, Error> registerResource(McpResource resource,
            Result<McpContent, Error>(Context, String) handler) {
        if resource == null { throw "McpServer.registerResource: null resource" }
        self._resources.push(resource)
        self._resourceHandlers.push(new McpResourceHandlerSlot(handler))
        return Ok()
    }

    Result<Unit, Error> registerPrompt(McpPrompt prompt,
            Result<McpPrompt, Error>(Context, Map<String, String>) handler) {
        if prompt == null { throw "McpServer.registerPrompt: null prompt" }
        self._prompts.push(prompt)
        self._promptHandlers.push(new McpPromptHandlerSlot(handler))
        return Ok()
    }

    McpServerInfo serverInfo() { return self._serverInfo }
    Bool isOpen() { return self._open }

    Result<JsonRpcResponse, Error> handleRequest(Context context, JsonRpcRequest request) {
        if context == null || request == null { throw "McpServer.handleRequest: null argument" }
        if !self._open { return Err(new BasicError(ErrorKind.Unavailable, "mcp server closed")) }
        JsonRpcId? identifier = request.identifier()
        if identifier == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "mcp server: notification requires serve"))
        }
        JsonRpcId actualId = identifier as JsonRpcId
        String method = request.method()
        if method == "initialize" {
            JsonObject result = new JsonObject()
            result.set("protocolVersion", Json.string("2026-07-28"))
            result.set("serverInfo", mcpObjectValue(self._serverInfo.toIdentityJson()))
            result.set("capabilities", mcpObjectValue(mcpCapabilitiesJson(
                self._serverInfo.capabilities())))
            return Ok(JsonRpcResponse.success(actualId, mcpObjectValue(result)))
        }
        if method == "ping" {
            return Ok(JsonRpcResponse.success(actualId, mcpObjectValue(new JsonObject())))
        }
        if method == "tools/list" {
            JsonValue tools = Json.array()
            JsonArray array = tools.asArray() as JsonArray
            Int index = 0
            while index < self._tools.length() {
                array.add(mcpObjectValue(self._tools.get(index).toJson()))
                index = index + 1
            }
            JsonObject result = new JsonObject()
            result.set("tools", tools)
            return Ok(JsonRpcResponse.success(actualId, mcpObjectValue(result)))
        }
        if method == "resources/list" {
            JsonValue resources = Json.array()
            JsonArray array = resources.asArray() as JsonArray
            Int index = 0
            while index < self._resources.length() {
                array.add(mcpObjectValue(self._resources.get(index).toJson()))
                index = index + 1
            }
            JsonObject result = new JsonObject()
            result.set("resources", resources)
            return Ok(JsonRpcResponse.success(actualId, mcpObjectValue(result)))
        }
        if method == "prompts/list" {
            JsonValue prompts = Json.array()
            JsonArray array = prompts.asArray() as JsonArray
            Int index = 0
            while index < self._prompts.length() {
                array.add(mcpObjectValue(self._prompts.get(index).toJson()))
                index = index + 1
            }
            JsonObject result = new JsonObject()
            result.set("prompts", prompts)
            return Ok(JsonRpcResponse.success(actualId, mcpObjectValue(result)))
        }
        if method == "tools/call" {
            JsonValue? params = request.params()
            if params == null {
                return Ok(JsonRpcResponse.failure(actualId, JsonRpcError.invalidParams("")))
            }
            JsonValue actualParams = params as JsonValue
            if !actualParams.isObject() {
                return Ok(JsonRpcResponse.failure(actualId, JsonRpcError.invalidParams("")))
            }
            JsonObject object = actualParams.asObject() as JsonObject
            String name = mcpString(object, "name", "")
            JsonValue arguments = object.getOr("arguments", mcpObjectValue(new JsonObject()))
            Int index = 0
            while index < self._tools.length() {
                if self._tools.get(index).name() == name {
                    McpToolHandlerSlot handler = self._toolHandlers.get(index)
                    Result<McpToolResult, Error> result = handler.run(context, arguments)
                    if result.isErr() {
                        return Ok(JsonRpcResponse.failure(actualId,
                            JsonRpcError.internalError("tool execution failed")))
                    }
                    return Ok(JsonRpcResponse.success(actualId,
                        mcpObjectValue(result.value().toJson())))
                }
                index = index + 1
            }
            return Ok(JsonRpcResponse.failure(actualId, JsonRpcError.methodNotFound(name)))
        }
        if method == "resources/read" {
            JsonValue? params = request.params()
            if params == null {
                return Ok(JsonRpcResponse.failure(actualId, JsonRpcError.invalidParams("")))
            }
            JsonValue actualParams = params as JsonValue
            if !actualParams.isObject() {
                return Ok(JsonRpcResponse.failure(actualId, JsonRpcError.invalidParams("")))
            }
            JsonObject object = actualParams.asObject() as JsonObject
            String uri = mcpString(object, "uri", "")
            Int index = 0
            while index < self._resources.length() {
                if self._resources.get(index).uri() == uri {
                    McpResourceHandlerSlot handler = self._resourceHandlers.get(index)
                    Result<McpContent, Error> result = handler.run(context, uri)
                    if result.isErr() {
                        return Ok(JsonRpcResponse.failure(actualId,
                            JsonRpcError.internalError("resource read failed")))
                    }
                    return Ok(JsonRpcResponse.success(actualId,
                        mcpObjectValue(result.value().toJson())))
                }
                index = index + 1
            }
            return Ok(JsonRpcResponse.failure(actualId, JsonRpcError.invalidParams("unknown resource")))
        }
        if method == "prompts/get" {
            JsonValue? params = request.params()
            if params == null {
                return Ok(JsonRpcResponse.failure(actualId, JsonRpcError.invalidParams("")))
            }
            JsonValue actualParams = params as JsonValue
            if !actualParams.isObject() {
                return Ok(JsonRpcResponse.failure(actualId, JsonRpcError.invalidParams("")))
            }
            JsonObject object = actualParams.asObject() as JsonObject
            String name = mcpString(object, "name", "")
            Map<String, String> arguments = [:]
            Int index = 0
            while index < self._prompts.length() {
                if self._prompts.get(index).name() == name {
                    McpPromptHandlerSlot handler = self._promptHandlers.get(index)
                    Result<McpPrompt, Error> result = handler.run(context, arguments)
                    if result.isErr() {
                        return Ok(JsonRpcResponse.failure(actualId,
                            JsonRpcError.internalError("prompt resolve failed")))
                    }
                    return Ok(JsonRpcResponse.success(actualId,
                        mcpObjectValue(result.value().toJson())))
                }
                index = index + 1
            }
            return Ok(JsonRpcResponse.failure(actualId, JsonRpcError.methodNotFound(name)))
        }
        return Ok(JsonRpcResponse.failure(actualId, JsonRpcError.methodNotFound(method)))
    }

    Result<Unit, Error> serve(Context context, McpTransport transport) {
        if context == null || transport == null { throw "McpServer.serve: null argument" }
        while self._open && !context.isCancelled() && transport.isOpen() {
            Result<JsonRpcRequest, Error> received = transport.receive(context)
            if received.isErr() {
                if context.isCancelled() { return Err(new BasicError(ErrorKind.Cancelled, "mcp server cancelled")) }
                self._open = false
                return Ok()
            }
            JsonRpcRequest request = received.value()
            Result<JsonRpcResponse, Error> handled = self.handleRequest(context, request)
            if handled.isOk() {
                Result<Unit, Error> responded = transport.respond(context, handled.value())
                if responded.isErr() { return Err(responded.error()) }
            } else if request.hasIdentifier() {
                JsonRpcId identifier = request.identifier() as JsonRpcId
                transport.respond(context, JsonRpcResponse.failure(identifier,
                    JsonRpcError.internalError("request failed")))
            }
        }
        return Ok()
    }

    Result<Unit, Error> close() { self._open = false; return Ok() }
}

// ---------- McpClient ----------
class McpClient {
    final McpTransport _transport
    final McpClientInfo _clientInfo
    final Set<String> _allowedTools
    final Bool _requireConfirmation
    McpSession? _session
    Long _nextId
    List<McpTool> _tools
    List<McpResource> _resources
    List<McpPrompt> _prompts
    Bool _open

    McpClient(McpTransport transport, McpClientInfo clientInfo,
              Set<String> allowedTools, Bool requireConfirmation) {
        if transport == null || clientInfo == null || allowedTools == null {
            throw "McpClient: null argument"
        }
        self._transport = transport
        self._clientInfo = clientInfo
        self._allowedTools = allowedTools
        self._requireConfirmation = requireConfirmation
        self._session = null
        self._nextId = 1 as Long
        self._tools = []
        self._resources = []
        self._prompts = []
        self._open = true
    }

    McpSession? session() { return self._session }
    Bool isOpen() { return self._open && self._transport.isOpen() }

    Result<McpSession, Error> initialize(Context context) {
        if context == null { throw "McpClient.initialize: null context" }
        JsonObject params = new JsonObject()
        params.set("protocolVersion", Json.string("2026-07-28"))
        params.set("clientInfo", mcpObjectValue(self._clientInfo.toIdentityJson()))
        JsonRpcRequest request = JsonRpcRequest.requestWithParams(
            JsonRpcId.ofNumber(self._nextId), "initialize", mcpObjectValue(params))
        self._nextId = self._nextId + 1 as Long
        Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler =
            (Context c, JsonRpcRequest r) -> {
                return Ok()
            }
        Result<JsonRpcResponse, Error> response = self._transport.request(context,
            request, notificationHandler)
        if response.isErr() { return Err(response.error()) }
        Result<JsonValue, Error> result = self._responseResult(response.value())
        if result.isErr() { return Err(result.error()) }
        JsonValue resultValue = result.value()
        String versionText = mcpString(resultValue.asObject() as JsonObject,
            "protocolVersion", "2026-07-28")
        McpProtocolVersion version = parseMcpProtocolVersion(versionText)
        McpServerInfo serverInfo = McpServerInfo.parse(resultValue).value()
        McpSession session = new McpSession(version, serverInfo, self._clientInfo,
            "", isModernMcpProtocolVersion(version), true, true)
        self._session = session
        JsonRpcRequest initialized = JsonRpcRequest.notification("notifications/initialized")
        self._transport.notify(context, initialized)
        return Ok(session)
    }

    Result<List<McpTool>, Error> listTools(Context context) {
        Result<JsonValue, Error> result = self.call("tools/list", new JsonObject(), context)
        if result.isErr() { return Err(result.error()) }
        JsonValue value = result.value()
        if !value.isObject() { return Err(new BasicError(ErrorKind.DataCorrupted, "tools/list result")) }
        JsonObject valueObject = value.asObject() as JsonObject
        JsonValue? toolsValue = valueObject.getOrNull("tools")
        if toolsValue == null {
            return Err(new BasicError(ErrorKind.DataCorrupted, "tools/list missing tools"))
        }
        JsonValue actualTools = toolsValue as JsonValue
        if !actualTools.isArray() {
            return Err(new BasicError(ErrorKind.DataCorrupted, "tools/list missing tools"))
        }
        JsonArray array = actualTools.asArray() as JsonArray
        List<McpTool> tools = []
        Int index = 0
        while index < array.length() {
            Result<McpTool, Error> parsed = McpTool.parse(array.get(index))
            if parsed.isErr() { return Err(parsed.error()) }
            tools.push(parsed.value())
            index = index + 1
        }
        self._tools = tools
        return Ok(tools)
    }

    Result<List<McpResource>, Error> listResources(Context context) {
        Result<JsonValue, Error> result = self.call("resources/list", new JsonObject(), context)
        if result.isErr() { return Err(result.error()) }
        JsonValue value = result.value()
        if !value.isObject() { return Err(new BasicError(ErrorKind.DataCorrupted, "resources/list result")) }
        JsonObject valueObject = value.asObject() as JsonObject
        JsonValue? resourcesValue = valueObject.getOrNull("resources")
        if resourcesValue == null {
            return Err(new BasicError(ErrorKind.DataCorrupted, "resources/list missing resources"))
        }
        JsonValue actualResources = resourcesValue as JsonValue
        if !actualResources.isArray() {
            return Err(new BasicError(ErrorKind.DataCorrupted, "resources/list missing resources"))
        }
        JsonArray array = actualResources.asArray() as JsonArray
        List<McpResource> resources = []
        Int index = 0
        while index < array.length() {
            Result<McpResource, Error> parsed = McpResource.parse(array.get(index))
            if parsed.isErr() { return Err(parsed.error()) }
            resources.push(parsed.value())
            index = index + 1
        }
        self._resources = resources
        return Ok(resources)
    }

    Result<List<McpPrompt>, Error> listPrompts(Context context) {
        Result<JsonValue, Error> result = self.call("prompts/list", new JsonObject(), context)
        if result.isErr() { return Err(result.error()) }
        JsonValue value = result.value()
        if !value.isObject() { return Err(new BasicError(ErrorKind.DataCorrupted, "prompts/list result")) }
        JsonObject valueObject = value.asObject() as JsonObject
        JsonValue? promptsValue = valueObject.getOrNull("prompts")
        if promptsValue == null {
            return Err(new BasicError(ErrorKind.DataCorrupted, "prompts/list missing prompts"))
        }
        JsonValue actualPrompts = promptsValue as JsonValue
        if !actualPrompts.isArray() {
            return Err(new BasicError(ErrorKind.DataCorrupted, "prompts/list missing prompts"))
        }
        JsonArray array = actualPrompts.asArray() as JsonArray
        List<McpPrompt> prompts = []
        Int index = 0
        while index < array.length() {
            Result<McpPrompt, Error> parsed = McpPrompt.parse(array.get(index))
            if parsed.isErr() { return Err(parsed.error()) }
            prompts.push(parsed.value())
            index = index + 1
        }
        self._prompts = prompts
        return Ok(prompts)
    }

    Result<McpToolResult, Error> callTool(Context context, String name, JsonValue arguments) {
        if context == null || name == null || arguments == null {
            throw "McpClient.callTool: null argument"
        }
        if !self._allowedTools.has(name) {
            return Err(new BasicError(ErrorKind.PermissionDenied, "tool not allowed: " + name))
        }
        if self._requireConfirmation {
            return Err(new BasicError(ErrorKind.PermissionDenied, "tool confirmation required: " + name))
        }
        JsonObject params = new JsonObject()
        params.set("name", Json.string(name))
        params.set("arguments", arguments)
        Result<JsonValue, Error> result = self.call("tools/call", params, context)
        if result.isErr() { return Err(result.error()) }
        return McpToolResult.parse(result.value())
    }

    Result<McpContent, Error> readResource(Context context, String uri) {
        if context == null || uri == null { throw "McpClient.readResource: null argument" }
        JsonObject params = new JsonObject()
        params.set("uri", Json.string(uri))
        Result<JsonValue, Error> result = self.call("resources/read", params, context)
        if result.isErr() { return Err(result.error()) }
        return McpContent.parse(result.value())
    }

    Result<McpPrompt, Error> getPrompt(Context context, String name,
                                       Map<String, String> arguments) {
        if context == null || name == null || arguments == null {
            throw "McpClient.getPrompt: null argument"
        }
        JsonObject params = new JsonObject()
        params.set("name", Json.string(name))
        JsonValue argsValue = Json.object()
        JsonObject argsObject = argsValue.asObject() as JsonObject
        List<String> keys = arguments.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            argsObject.set(key, Json.string(arguments.getOr(key, "")))
            index = index + 1
        }
        params.set("arguments", argsValue)
        Result<JsonValue, Error> result = self.call("prompts/get", params, context)
        if result.isErr() { return Err(result.error()) }
        return McpPrompt.parse(result.value())
    }

    Result<Unit, Error> cancel(Context context, JsonRpcId identifier, String reason) {
        return self._transport.cancel(context, identifier, reason)
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        return self._transport.close()
    }

    private Result<JsonValue, Error> call(String method, JsonObject params, Context context) {
        JsonRpcRequest request = JsonRpcRequest.requestWithParams(
            JsonRpcId.ofNumber(self._nextId), method, mcpObjectValue(params))
        self._nextId = self._nextId + 1 as Long
        Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler =
            (Context c, JsonRpcRequest r) -> {
                return Ok()
            }
        Result<JsonRpcResponse, Error> response = self._transport.request(context,
            request, notificationHandler)
        if response.isErr() { return Err(response.error()) }
        return self._responseResult(response.value())
    }

    private Result<JsonValue, Error> _responseResult(JsonRpcResponse response) {
        if !response.isSuccess() {
            JsonRpcError? error = response.errorOrNull()
            if error != null {
                JsonRpcError actual = error as JsonRpcError
                return Err(new BasicError(ErrorKind.Internal, actual.describe()))
            }
            return Err(new BasicError(ErrorKind.Internal, "mcp: missing response result"))
        }
        JsonValue? result = response.resultOrNull()
        if result == null {
            return Err(new BasicError(ErrorKind.DataCorrupted, "mcp: missing result"))
        }
        return Ok(result as JsonValue)
    }
}

// ---------- McpRegistry ----------
class McpRegistry {
    final Map<String, McpTransport> _transports
    final Set<String> _connected
    Bool _open

    McpRegistry() {
        Map<String, McpTransport> transports = [:]
        self._transports = transports
        Set<String> connected = []
        self._connected = connected
        self._open = true
    }

    Result<Unit, Error> register(String name, McpTransport transport) {
        if name == null || name == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpRegistry.register: empty name"))
        }
        if transport == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "McpRegistry.register: null transport"))
        }
        if !self._open { return Err(new BasicError(ErrorKind.Unavailable, "mcp registry")) }
        if self._transports.has(name) {
            return Err(new BasicError(ErrorKind.AlreadyExists, "McpRegistry: duplicate name"))
        }
        self._transports.put(name, transport)
        return Ok()
    }

    Bool unregister(String name) {
        if name == null { throw "McpRegistry.unregister: null" }
        if self._connected.has(name) { return false }
        return self._transports.remove(name)
    }

    Bool contains(String name) {
        if name == null { throw "McpRegistry.contains: null" }
        return self._transports.has(name)
    }

    List<String> names() { return self._transports.keys() }

    Result<McpClient, Error> connect(Context context, String name, McpClientInfo clientInfo) {
        if context == null || name == null || clientInfo == null {
            throw "McpRegistry.connect: null argument"
        }
        if !self._open { return Err(new BasicError(ErrorKind.Unavailable, "mcp registry")) }
        if !self._transports.has(name) {
            return Err(new BasicError(ErrorKind.NotFound, "McpRegistry: not found"))
        }
        if self._connected.has(name) {
            return Err(new BasicError(ErrorKind.AlreadyExists, "McpRegistry: already connected"))
        }
        McpTransport transport = self._transports.getOr(name, null)
        Set<String> allowed = []
        McpClient client = new McpClient(transport, clientInfo, allowed, false)
        self._connected.add(name)
        return Ok(client)
    }

    Bool isConnected(String name) {
        if name == null { throw "McpRegistry.isConnected: null" }
        return self._connected.has(name)
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        List<String> keys = self._transports.keys()
        Int index = 0
        while index < keys.length() {
            String name = keys.get(index)
            if !self._connected.has(name) {
                McpTransport transport = self._transports.getOr(name, null)
                transport.close()
            }
            index = index + 1
        }
        self._transports.clear()
        self._connected.clear()
        return Ok()
    }

    Bool isOpen() { return self._open }
}
