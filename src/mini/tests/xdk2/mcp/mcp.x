package xdk2.mcp
import xdk.mcp
import xdk.codec
import xdk.errors

static Error loopUnsupported() {
    return new BasicError(ErrorKind.Unsupported, "loopback receive")
}

class LoopbackTransport implements McpTransport {
    McpServer server
    Bool open
    LoopbackTransport(McpServer owner) { self.server = owner; self.open = true }
    Result<JsonRpcResponse, Error> request(Context context, JsonRpcRequest request,
            Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler) {
        return self.server.handleRequest(context, request)
    }
    Result<Unit, Error> selectProtocolVersion(Context context, McpProtocolVersion version) { return Ok() }
    Result<Unit, Error> notify(Context context, JsonRpcRequest notification) { return Ok() }
    Result<JsonRpcRequest, Error> receive(Context context) {
        return Err(loopUnsupported())
    }
    Result<Unit, Error> respond(Context context, JsonRpcResponse response) { return Ok() }
    Result<Unit, Error> acknowledge(Context context) { return Ok() }
    Result<Unit, Error> cancel(Context context, JsonRpcId identifier, String reason) { return Ok() }
    String? sessionIdentifier() { return null }
    Result<Unit, Error> close() { self.open = false; return Ok() }
    Bool isOpen() { return self.open }
}

class McpMemoryReader implements McpReader {
    List<String> lines
    Int index
    McpMemoryReader(List<String> values) { self.lines = values.copy(); self.index = 0 }
    Result<String?, Error> readLine(Context context) {
        if self.index >= self.lines.length() { return Ok(null) }
        String value = self.lines.get(self.index)
        self.index = self.index + 1
        return Ok(value)
    }
}

class McpMemoryWriter implements McpWriter {
    Bytes data
    Bool open
    McpMemoryWriter() { self.data = Bytes.fromString(""); self.open = true }
    Bool isOpen() { return self.open }
    Result<Unit, Error> writeAll(Context context, Bytes source) {
        Int index = 0
        while index < source.length() { self.data.push(source.get(index)); index = index + 1 }
        return Ok()
    }
    Result<Unit, Error> flush() { return Ok() }
}

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

    McpServerInfo loopServerInfo = new McpServerInfo("loop", "1.0.0")
    McpServer loopServer = new McpServer(loopServerInfo)
    JsonValue inputSchema = Json.object()
    McpTool echoTool = new McpTool("echo", inputSchema)
    Result<Unit, Error> echoToolRegister = loopServer.registerTool(echoTool,
        (Context toolContext, JsonValue arguments) -> {
            List<McpContent> contents = [McpContent.text("echo")]
            return Ok(new McpToolResult(contents))
        })
    McpResource loopResource = new McpResource("file:///loop.txt", "loop.txt",
        "", "", "text/plain", null)
    Result<Unit, Error> loopResourceRegister = loopServer.registerResource(loopResource,
        (Context resourceContext, String uri) -> Ok(McpContent.resourceText(loopResource, "body")))
    List<String> promptNames = []
    Map<String, String> promptDescriptions = [:]
    Set<String> promptRequired = []
    List<String> promptRoles = []
    List<McpContent> promptMessages = []
    McpPrompt loopPrompt = new McpPrompt("hello", "", "", promptNames,
        promptDescriptions, promptRequired, promptRoles, promptMessages)
    Result<Unit, Error> loopPromptRegister = loopServer.registerPrompt(loopPrompt,
        (Context promptContext, Map<String, String> arguments) -> Ok(loopPrompt))
    print("server-register=" + str(echoToolRegister.isOk()) + "," +
        str(loopResourceRegister.isOk()) + "," + str(loopPromptRegister.isOk()) + "," +
        str(loopServer.registerTool(echoTool, (Context c, JsonValue a) -> {
            List<McpContent> contents = [McpContent.text("dup")]
            return Ok(new McpToolResult(contents))
        }).isErr()))

    LoopbackTransport loopTransport = new LoopbackTransport(loopServer)
    Set<String> allowedTools = Set.of("echo")
    McpClientInfo loopClientInfo = new McpClientInfo("loop-client", "1.0.0")
    McpClient loopClient = new McpClient(loopTransport, loopClientInfo, allowedTools, false)
    Result<McpSession, Error> initialized = loopClient.initialize(Context.background())
    Result<List<McpTool>, Error> listedTools = loopClient.listTools(Context.background())
    JsonValue callArguments = Json.object()
    Result<McpToolResult, Error> called = loopClient.callTool(Context.background(), "echo",
        callArguments)
    Result<McpContent, Error> read = loopClient.readResource(Context.background(),
        "file:///loop.txt")
    Map<String, String> promptArguments = [:]
    Result<McpPrompt, Error> gotPrompt = loopClient.getPrompt(Context.background(), "hello",
        promptArguments)
    print("client-server=" + str(initialized.isOk()) + "," +
        mcpProtocolVersionText(initialized.value().protocolVersion()) + "," +
        str(listedTools.isOk()) + "," + str(listedTools.value().length()) + "," +
        str(called.isOk()) + "," + str(called.value().contentCount()) + "," +
        str(read.isOk()) + "," + str(gotPrompt.isOk()))

    Set<String> noTools = []
    McpClient deniedClient = new McpClient(loopTransport, loopClientInfo, noTools, false)
    Result<McpToolResult, Error> denied = deniedClient.callTool(Context.background(), "echo",
        callArguments)
    Set<String> confirmedTools = Set.of("echo")
    McpClient confirmClient = new McpClient(loopTransport, loopClientInfo, confirmedTools, true)
    Result<McpToolResult, Error> confirmed = confirmClient.callTool(Context.background(), "echo",
        callArguments)
    print("client-allow=" + errorKindName(denied.error().kind()) + "," +
        errorKindName(confirmed.error().kind()))

    McpRegistry registry = new McpRegistry()
    LoopbackTransport registryTransport = new LoopbackTransport(loopServer)
    Result<Unit, Error> registered = registry.register("loop", registryTransport)
    Result<Unit, Error> duplicateRegister = registry.register("loop", registryTransport)
    Result<McpClient, Error> connected = registry.connect(Context.background(), "loop",
        loopClientInfo)
    Result<McpClient, Error> connectedAgain = registry.connect(Context.background(), "loop",
        loopClientInfo)
    print("registry=" + str(registered.isOk()) + "," +
        errorKindName(duplicateRegister.error().kind()) + "," + str(connected.isOk()) + "," +
        errorKindName(connectedAgain.error().kind()) + "," +
        str(registry.contains("loop")) + "," + str(registry.isConnected("loop")) + "," +
        str(registry.names().length()))
    Result<Unit, Error> registryClose = registry.close()
    print("registry-close=" + str(registryClose.isOk()) + "," +
        str(registryClose.isOk()) + "," + str(registry.isOpen()))

    McpMemoryWriter stdioWriter = new McpMemoryWriter()
    List<String> stdioLines = []
    McpMemoryReader stdioReader = new McpMemoryReader(stdioLines)
    McpStdioTransport stdio = new McpStdioTransport(stdioReader, stdioWriter)
    JsonRpcRequest stdioNotification = JsonRpcRequest.notification("ping")
    Result<Unit, Error> stdioNotify = stdio.notify(Context.background(), stdioNotification)
    String stdioText = stdioWriter.data.toString()
    print("stdio-notify=" + str(stdioNotify.isOk()) + "," +
        str(stdioText.indexOf("\"method\":\"ping\"") >= 0) + "," +
        str(stdioText.indexOf("\n") >= 0))

    List<String> responseLines = ["{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}"]
    McpMemoryReader responseReader = new McpMemoryReader(responseLines)
    McpMemoryWriter responseWriter = new McpMemoryWriter()
    McpStdioTransport responder = new McpStdioTransport(responseReader, responseWriter)
    JsonRpcRequest stdioRequest = JsonRpcRequest.request(JsonRpcId.ofNumber(1 as Long), "initialize")
    Result<Unit, Error>(Context, JsonRpcRequest) stdioHandler =
        (Context handlerContext, JsonRpcRequest handlerRequest) -> {
            return Ok()
        }
    Result<JsonRpcResponse, Error> stdioResponse = responder.request(Context.background(),
        stdioRequest, stdioHandler)
    print("stdio-request=" + str(stdioResponse.isOk()) + "," +
        str(stdioResponse.isOk() && stdioResponse.value().isSuccess()) + "," +
        str(responder.close().isOk()) + "," + str(responder.close().isOk()) + "," +
        str(responder.isOpen()))

    McpMemoryWriter receiveWriter = new McpMemoryWriter()
    List<String> receiveLines = ["{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}"]
    McpMemoryReader receiveReader = new McpMemoryReader(receiveLines)
    McpStdioTransport receiver = new McpStdioTransport(receiveReader, receiveWriter)
    Result<JsonRpcRequest, Error> receivedRequest = receiver.receive(Context.background())
    print("stdio-receive=" + str(receivedRequest.isOk()) + "," +
        receivedRequest.value().method())
    return 0
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
