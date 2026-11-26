package xdk2.mcp
import xdk.mcp
import xdk.codec
import xdk.errors

static Int main() {
    print("versions=" + mcpProtocolVersionText(McpProtocolVersion.V2024_11_05) + "," +
        mcpProtocolVersionText(McpProtocolVersion.V2025_03_26) + "," +
        mcpProtocolVersionText(McpProtocolVersion.V2025_06_18) + "," +
        mcpProtocolVersionText(McpProtocolVersion.V2025_11_25) + "," +
        mcpProtocolVersionText(McpProtocolVersion.V2026_07_28) + "," +
        str(isLegacyMcpProtocolVersion(McpProtocolVersion.V2024_11_05)) + "," +
        str(isModernMcpProtocolVersion(McpProtocolVersion.V2026_07_28)) + "," +
        mcpProtocolVersionText(latestMcpProtocolVersion()))
    McpProtocolVersion parsedVersion = parseMcpProtocolVersion("2025-11-25")
    print("version-parse=" + str(parsedVersion != McpProtocolVersion.Unknown) + "," +
        mcpProtocolVersionText(parsedVersion) + "," +
        str(parseMcpProtocolVersion("2025-1-1") == McpProtocolVersion.Unknown) + "," +
        str(isSupportedMcpProtocolVersion(McpProtocolVersion.V2024_11_05)))

    print("capability=" + mcpCapabilityName(McpCapability.ToolsListChanged) + "," +
        mcpCapabilityName(mcpCapabilityParent(McpCapability.ResourcesSubscribe)) + "," +
        mcpCapabilityName(McpCapability.ElicitationUrl) + "," +
        str(isServerMcpCapability(McpCapability.Tools)) + "," +
        str(isClientMcpCapability(McpCapability.Sampling)) + "," +
        str(isServerMcpCapability(McpCapability.Sampling)))
    Set<McpCapability> caps = Set.of(McpCapability.Tools, McpCapability.ToolsListChanged,
        McpCapability.Elicitation, McpCapability.ElicitationForm)
    JsonObject capsJson = mcpCapabilitiesJson(caps)
    Result<Set<McpCapability>, Error> parsedCaps = parseMcpCapabilities(capsJson)
    print("capability-json=" + str(parsedCaps.isOk()) + "," +
        str(parsedCaps.value().has(McpCapability.Tools)) + "," +
        str(parsedCaps.value().has(McpCapability.ToolsListChanged)) + "," +
        str(parsedCaps.value().has(McpCapability.ElicitationForm)))

    McpServerInfo server = new McpServerInfo("weather", "1.0.0")
    Set<McpCapability> serverCaps = Set.of(McpCapability.Tools, McpCapability.ToolsListChanged)
    List<McpProtocolVersion> versions = []
    versions.push(McpProtocolVersion.V2026_07_28)
    versions.push(McpProtocolVersion.V2025_11_25)
    McpServerInfo fullServer = new McpServerInfo("weather", "Weather", "1.0.0",
        "forecast", "https://example.test", serverCaps, versions, "Use tools")
    McpServerInfo parsedServer = McpServerInfo.parse(jsonObjectValue(fullServer.toJson())).value()
    print("server=" + server.name() + "," + str(server.supports(McpCapability.Tools)) + "," +
        str(fullServer.supports(McpCapability.ToolsListChanged)) + "," +
        str(fullServer.supportsProtocolVersion(McpProtocolVersion.V2026_07_28)) + "," +
        mcpProtocolVersionText(fullServer.preferredProtocolVersion()) + "," +
        str(parsedServer.equals(fullServer)) + "," + parsedServer.describe())

    Set<McpCapability> clientCaps = Set.of(McpCapability.Sampling,
        McpCapability.SamplingTools, McpCapability.Roots)
    McpClientInfo client = new McpClientInfo("client", "Client", "2.0.0", "", "",
        clientCaps, versions, "")
    McpClientInfo parsedClient = McpClientInfo.parse(jsonObjectValue(client.toJson())).value()
    print("client=" + str(client.supports(McpCapability.SamplingTools)) + "," +
        str(parsedClient.equals(client)) + "," + client.describe())

    McpResource resource = new McpResource("file:///tmp/a.txt", "a.txt", "A", "text",
        "text/plain", 12 as Long)
    McpResource parsedResource = McpResource.parse(jsonObjectValue(resource.toJson())).value()
    print("resource=" + resource.uri() + "," + str(resource.hasSize()) + "," +
        str(parsedResource.equals(resource)))

    McpContent textContent = McpContent.text("hello")
    McpContent imageContent = McpContent.image("aGVsbG8=", "image/png")
    McpContent linkContent = McpContent.resourceLink(resource)
    McpContent embedded = McpContent.embeddedText(resource, "body")
    McpContent bare = McpContent.resourceText(resource, "bare")
    print("content=" + textContent.kind() + "," + imageContent.kind() + "," +
        linkContent.kind() + "," + embedded.kind() + "," + bare.kind() + "," +
        str(textContent.isText()) + "," + str(embedded.isResource()) + "," +
        str(bare.isResourceContent()))
    McpContent parsedText = McpContent.parse(jsonObjectValue(textContent.toJson())).value()
    McpContent parsedImage = McpContent.parse(jsonObjectValue(imageContent.toJson())).value()
    McpContent parsedLink = McpContent.parse(jsonObjectValue(linkContent.toJson())).value()
    McpContent parsedBare = McpContent.parse(jsonObjectValue(bare.toJson())).value()
    print("content-roundtrip=" + str(parsedText.isText()) + "," +
        str(parsedImage.isImage()) + "," + str(parsedLink.isResourceLink()) + "," +
        str(parsedBare.isResourceContent()) + "," +
        str((parsedBare.textValue() as String) == "bare"))

    List<String> argumentNames = ["name"]
    Map<String, String> descriptions = [:]
    descriptions.put("name", "user name")
    Set<String> required = Set.of("name")
    List<String> roles = ["user"]
    List<McpContent> messages = [McpContent.text("Hello {name}")]
    McpPrompt prompt = new McpPrompt("greet", "Greeting", "say hi", argumentNames,
        descriptions, required, roles, messages)
    Map<String, String> values = [:]
    values.put("name", "Ada")
    McpPrompt resolved = prompt.resolve(values)
    McpPrompt parsedPrompt = McpPrompt.parse(jsonObjectValue(prompt.toJson())).value()
    print("prompt=" + prompt.name() + "," + str(prompt.isResolved()) + "," +
        prompt.argumentDescription("name") + "," + str(prompt.isArgumentRequired("name")) +
        "," + (resolved.messages().get(0).textValue() as String) + "," +
        str(parsedPrompt.isResolved()) + "," + str(parsedPrompt.messageCount()))

    JsonValue schema = Json.object()
    McpTool tool = new McpTool("get_weather", "Weather", "get", schema, null,
        true, false, true, false)
    McpTool parsedTool = McpTool.parse(jsonObjectValue(tool.toJson())).value()
    print("tool=" + tool.name() + "," + str(tool.readOnlyHint()) + "," +
        str(tool.hasOutputSchema()) + "," + str(parsedTool.name() == "get_weather") +
        "," + str(McpTool.parse(Json.object()).isErr()))

    List<McpContent> resultContents = [textContent, imageContent]
    McpToolResult result = new McpToolResult(resultContents, schema, false)
    McpToolResult parsedResult = McpToolResult.parse(jsonObjectValue(result.toJson())).value()
    print("tool-result=" + str(result.contentCount()) + "," +
        str(result.hasStructuredContent()) + "," + str(result.isError()) + "," +
        str(parsedResult.contentCount()) + "," +
        str(parsedResult.hasStructuredContent()))

    McpSession modernSession = new McpSession(McpProtocolVersion.V2026_07_28,
        server, client, "session-1", true, true, true)
    McpSession legacySession = new McpSession(McpProtocolVersion.V2025_11_25,
        server, client, "legacy-1", false, true, true)
    print("session=" + str(modernSession.isModern()) + "," +
        str(legacySession.isLegacy()) + "," +
        str(modernSession.serverSupports(McpCapability.Tools)) + "," +
        str(modernSession.clientSupports(McpCapability.Sampling)) + "," +
        str(modernSession.hasSessionIdentifier()) + "," + modernSession.describe())
    return 0
}

static JsonValue jsonObjectValue(JsonObject object) {
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
