package xdk2.api
import xdk.api
import xdk.errors
import xdk.codec
import xdk.net.http
import xdk.net.uri
import xdk.validate
import xdk.time

class TraceMiddleware implements ApiMiddleware {
    final String _label
    final List<String> _trace
    TraceMiddleware(String label, List<String> trace) {
        self._label = label
        self._trace = trace
    }
    Result<Unit, Error> handle(Context context, ApiContext exchange, ApiHandler next) {
        self._trace.push(self._label)
        return next.handle(context, exchange)
    }
}

class ShortMiddleware implements ApiMiddleware {
    final List<String> _trace
    ShortMiddleware(List<String> trace) { self._trace = trace }
    Result<Unit, Error> handle(Context context, ApiContext exchange, ApiHandler next) {
        self._trace.push("short")
        exchange.setStatus(204)
        return Ok()
    }
}

class MiddlewareStep implements ApiHandler {
    final ApiMiddleware _middleware
    final ApiHandler _next
    MiddlewareStep(ApiMiddleware middleware, ApiHandler next) {
        self._middleware = middleware
        self._next = next
    }
    Result<Unit, Error> handle(Context context, ApiContext exchange) {
        return self._middleware.handle(context, exchange, self._next)
    }
}

class TraceHandler implements ApiHandler {
    final List<String> _trace
    TraceHandler(List<String> trace) { self._trace = trace }
    Result<Unit, Error> handle(Context context, ApiContext exchange) {
        self._trace.push("handler")
        return Ok()
    }
}

class NoopHandler implements ApiHandler {
    Result<Unit, Error> handle(Context context, ApiContext exchange) { return Ok() }
}

class FakeAuthenticator implements Authenticator {
    final AuthScheme _scheme
    FakeAuthenticator(AuthScheme scheme) { self._scheme = scheme }
    AuthScheme scheme() { return self._scheme }
    String name() { return "basicAuth" }
    String parameterName() { return "" }
    String realm() { return "test" }
    Result<Unit, Error> authenticate(Context context, ApiContext exchange) {
        exchange.setPrincipal("alice")
        List<String> roles = ["admin"]
        exchange.setRoles(roles)
        return Ok()
    }
}

class RunningApiServer {
    final ApiServer _server
    final Context _cancel
    final TaskGroup _group
    final Task<Int> _task
    RunningApiServer(ApiServer server, Context parent) {
        self._server = server
        Context cancel = Context.withCancel(parent)
        self._cancel = cancel
        TaskGroup group = TaskGroup.create(cancel)
        self._group = group
        Task<Int> task = group.spawn((Context taskContext) -> {
            Result<Unit, Error> served = server.serve(taskContext)
            return Ok(0)
        })
        self._task = task
    }
    Void stop() {
        self._cancel.cancel()
        self._server.close()
        self._task.join()
        self._group.close()
    }
}

class ApiWire {
    final Int _status
    final String _head
    final String _body
    ApiWire(Int status, String head, String body) {
        self._status = status
        self._head = head
        self._body = body
    }
    Int status() { return self._status }
    String body() { return self._body }
    String header(String name) {
        String wanted = name.toLower() + ":"
        List<String> lines = self._head.split("\r\n")
        Int index = 1
        while index < lines.length() {
            String line = lines.get(index)
            if line.toLower().startsWith(wanted) {
                return line.substring(wanted.length(), line.length() - wanted.length()).trim()
            }
            index = index + 1
        }
        return ""
    }
    Bool hasHeader(String name) { return self.header(name) != "" }
}

class TextHandler implements ApiHandler {
    final String _text
    TextHandler(String text) { self._text = text }
    Result<Unit, Error> handle(Context context, ApiContext exchange) {
        return exchange.respondTextWithStatus(context, 200, self._text)
    }
}

class PrincipalTextHandler implements ApiHandler {
    Int _marker
    PrincipalTextHandler() { self._marker = 1 }
    Result<Unit, Error> handle(Context context, ApiContext exchange) {
        String name = exchange.principalName() as String
        return exchange.respondTextWithStatus(context, 200, name)
    }
}

class DenyAuthenticator implements Authenticator {
    final ErrorKind _kind
    final AuthScheme _scheme
    final String _name
    final String _parameterName
    final String _realm
    DenyAuthenticator(ErrorKind kind, AuthScheme scheme, String name,
                      String parameterName, String realm) {
        self._kind = kind
        self._scheme = scheme
        self._name = name
        self._parameterName = parameterName
        self._realm = realm
    }
    AuthScheme scheme() { return self._scheme }
    String name() { return self._name }
    String parameterName() { return self._parameterName }
    String realm() { return self._realm }
    Result<Unit, Error> authenticate(Context context, ApiContext exchange) {
        return Err(new BasicError(self._kind, "denied"))
    }
}

class FailMiddleware implements ApiMiddleware {
    final ErrorKind _kind
    FailMiddleware(ErrorKind kind) { self._kind = kind }
    Result<Unit, Error> handle(Context context, ApiContext exchange, ApiHandler next) {
        return Err(new BasicError(self._kind, "middleware failure"))
    }
}

static Bool apiWireContains(ApiWire response, String needle) {
    return response.body().indexOf(needle) >= 0
}

static ApiWire apiWire(Context parent, Int port, String method, String path,
                       String extraHeaders, String body) {
    TcpStream stream = TcpStream.connect(parent,
        SocketAddress.parse("127.0.0.1:" + str(port)).value()).value()
    String wire = method + " " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\n" +
        "Connection: close\r\n" + extraHeaders
    if body != "" { wire = wire + "Content-Length: " + str(body.length()) + "\r\n" }
    wire = wire + "\r\n" + body
    stream.writeAll(parent, Bytes.fromString(wire))
    String response = ""
    while true {
        Bytes buffer = Bytes.alloc(4096)
        Result<Int, Error> count = stream.read(parent, buffer)
        if count.isErr() { break }
        if count.value() == 0 { break }
        String chunk = buffer.slice(0, count.value()).toString()
        response = response + chunk
    }
    stream.close()
    Int firstEnd = response.indexOf("\r\n")
    String firstLine = response.substring(0, firstEnd)
    List<String> parts = firstLine.split(" ")
    Int status = parseInt(parts.get(1)).value()
    Int headEnd = response.indexOf("\r\n\r\n")
    String head = response.substring(0, headEnd)
    String responseBody = ""
    if headEnd + 4 < response.length() {
        responseBody = response.substring(headEnd + 4, response.length() - headEnd - 4)
    }
    return new ApiWire(status, head, responseBody)
}

static Int main() {
    ProblemDetails notFound = ProblemDetails.of(404)
    ProblemDetails detailed = notFound.withType("urn:example:not-found")
        .withDetail("missing")
        .withInstance("/users/42")
        .extension("request_id", Json.string("abc"))
    JsonObject json = detailed.toJson()
    JsonValue typeValue = json.getOr("type", Json.nullValue())
    String typeText = typeValue.asString() as String
    print("problem=" + str(notFound.status()) + "," + notFound.title() + "," +
        str(notFound.isClientError()) + "," + str(notFound.isServerError()) + "," +
        typeText + "," +
        str(json.has("detail")) + "," + str(json.has("instance")) + "," +
        str(json.has("request_id")) + "," + detailed.describe())

    List<ValidationError> validationErrors = [new ValidationError("name", "required", "name is required")]
    ProblemDetails validationProblem = ProblemDetails.fromValidation(validationErrors)
    JsonObject validationJson = validationProblem.toJson()
    JsonValue? errorsValue = validationJson.getOrNull("errors")
    JsonValue actualErrors = errorsValue as JsonValue
    JsonArray errorsArray = actualErrors.asArray() as JsonArray
    print("validation=" + str(validationProblem.status()) + "," +
        validationProblem.title() + "," + str(errorsArray.length()) + "," +
        str(validationProblem.copy().equals(validationProblem)))

    print("auth=" + authSchemeName(AuthScheme.Basic) + "," +
        authSchemeName(AuthScheme.ApiKeyQuery) + "," +
        authSchemeOpenApiType(AuthScheme.Bearer) + "," +
        authSchemeOpenApiLocation(AuthScheme.ApiKeyCookie) + "," +
        authSchemeOpenApiLocation(AuthScheme.Bearer) + "," +
        authSchemeChallenge(AuthScheme.Basic, "") + "," +
        authSchemeChallenge(AuthScheme.Basic, "api") + "," +
        authSchemeChallenge(AuthScheme.Bearer, "x") + "," +
        authSchemeChallenge(AuthScheme.ApiKeyHeader, ""))

    CorsPolicy cors = new CorsPolicy()
    cors.allowOrigin("https://app.example").allowOrigin("https://admin.example")
    cors.allowMethod(HttpMethod.Post).allowHeader("Content-Type").allowHeader("Authorization")
    cors.exposeHeader("X-Rate-Limit").allowCredentials(true).maxAgeSeconds(600 as Long)
    print("cors=" + str(cors.isOriginAllowed("https://app.example")) + "," +
        str(cors.isOriginAllowed("https://other.example")) + "," +
        str(cors.allowedMethods().length()) + "," + str(cors.isHeaderAllowed("content-type")) +
        "," + str(cors.isAllowCredentials()) + "," + str(cors.getMaxAgeSeconds()))
    Map<String, String> actual = cors.actualHeaders("https://app.example")
    print("cors-actual=" + actual.getOr("Access-Control-Allow-Origin", "") + "," +
        actual.getOr("Access-Control-Allow-Credentials", "") + "," +
        actual.getOr("Access-Control-Expose-Headers", ""))
    List<String> requestedHeaders = ["Content-Type"]
    Map<String, String> preflight = cors.preflightHeaders("https://app.example",
        HttpMethod.Post, requestedHeaders)
    Map<String, String> rejected = cors.preflightHeaders("https://other.example",
        HttpMethod.Post, requestedHeaders)
    List<String> forbiddenHeaders = ["X-Unknown"]
    Map<String, String> forbidden = cors.preflightHeaders("https://app.example",
        HttpMethod.Post, forbiddenHeaders)
    print("cors-preflight=" + str(preflight.keys().length() > 0) + "," +
        preflight.getOr("Access-Control-Allow-Methods", "") + "," +
        preflight.getOr("Access-Control-Max-Age", "") + "," +
        str(rejected.keys().length()) + "," + str(forbidden.keys().length()))

    RateLimitPolicy rate = new RateLimitPolicy(2, 50 as Long)
    Bool first = rate.allow("client")
    Bool second = rate.allow("client")
    Bool third = rate.allow("client")
    Bool other = rate.allow("other")
    sleepMs(60 as Long)
    Bool afterWindow = rate.allow("client")
    print("rate=" + str(first) + "," + str(second) + "," + str(third) + "," +
        str(other) + "," + str(afterWindow) + "," + str(rate.limit()) + "," +
        str(rate.windowMillis()) + "," + str(rate.isIncludeRoute()))

    RateLimitPolicy bounded = new RateLimitPolicy(5, 1000 as Long)
    bounded.withMaximumKeys(1)
    Bool keyOne = bounded.allow("one")
    Bool keyTwo = bounded.allow("two")
    boolTestPrint(keyOne, keyTwo)
    RateLimitPolicy rateCopy = rate.copy()
    print("rate-copy=" + str(rateCopy.allow("client")) + "," + str(rateCopy.limit()) + "," +
        str(rateCopy.getMaximumKeys()))

    ApiOptions apiOptions = new ApiOptions()
    List<String> globalTrace = []
    ApiMiddleware globalMiddleware = new TraceMiddleware("global", globalTrace)
    apiOptions.use(globalMiddleware).maximumBodyBytes(16 as Long)
        .includeErrorDetail(true).autoOptions(false)
        .problemTypeBase("urn:test:api")
    ApiOptions apiOptionsCopy = apiOptions.copy()
    print("options=" + str(apiOptions.middleware().length()) + "," +
        str(apiOptions.getMaximumBodyBytes()) + "," +
        str(apiOptions.isIncludeErrorDetail()) + "," +
        str(apiOptions.isAutoOptions()) + "," + apiOptions.getProblemTypeBase() + "," +
        str(apiOptions.getSseBufferBytes()))
    print("options-copy=" + str(apiOptionsCopy.middleware().length()) + "," +
        str(apiOptionsCopy.getMaximumBodyBytes()) + "," +
        apiOptionsCopy.getProblemTypeBase())

    NoopHandler noop = new NoopHandler()
    ApiRoute userRoute = new ApiRoute(HttpMethod.Get, "/users/{userId}/posts/{postId}", noop)
    ApiRoute wildcardRoute = new ApiRoute(HttpMethod.Get, "/files/*", noop)
    Result<Map<String, String>, Error> extracted = userRoute.extractPathParameters(
        "/users/42/posts/7")
    Map<String, String> parameters = extracted.value()
    print("route=" + userRoute.pattern() + "," +
        str(userRoute.pathParameterNames().length()) + "," +
        parameters.getOr("userId", "") + "," + parameters.getOr("postId", "") + "," +
        str(userRoute.matchesPath("/users/42/posts/7")) + "," +
        str(userRoute.matchesPath("/users/42")) + "," +
        str(wildcardRoute.matchesPath("/files/a/b.txt")) + "," +
        str(wildcardRoute.matchesPath("/other/a")))

    ApiRouter router = new ApiRouter("/api")
    Result<ApiRoute, Error> stored = router.get("/users/{id}", noop)
    Result<ApiRoute, Error> duplicate = router.get("/users/{id}", noop)
    router.get("/users/me", noop)
    router.post("/users", noop)
    ApiRoute? matchedStatic = router.match(HttpMethod.Get, "/api/users/me")
    ApiRoute? matchedParam = router.match(HttpMethod.Get, "/api/users/42")
    ApiRoute? matchedHead = router.match(HttpMethod.Head, "/api/users/me")
    List<HttpMethod> allowed = router.allowedMethods("/api/users/me")
    ApiRoute staticRoute = matchedStatic as ApiRoute
    ApiRoute paramRoute = matchedParam as ApiRoute
    ApiRoute headRoute = matchedHead as ApiRoute
    print("router=" + router.prefix() + "," + str(router.routeCount()) + "," +
        str(stored.isOk()) + "," + errorKindName(duplicate.error().kind()) + "," +
        staticRoute.pattern() + "," + paramRoute.pattern() + "," +
        headRoute.pattern() + "," + str(allowed.length()) + "," +
        httpMethodName(allowed.get(0)) + "," + httpMethodName(allowed.get(1)))

    List<String> trace = []
    TraceHandler traceHandler = new TraceHandler(trace)
    ApiMiddleware outer = new TraceMiddleware("outer", trace)
    ApiMiddleware inner = new TraceMiddleware("inner", trace)
    ApiHandler innerStep = new MiddlewareStep(inner, traceHandler)
    ApiHandler outerStep = new MiddlewareStep(outer, innerStep)
    HttpExchange middlewareExchange = apiTestExchange(HttpMethod.Get, "/mw", "", null)
    ApiContext middlewareContext = new ApiContext(middlewareExchange, new ApiOptions())
    Result<Unit, Error> middlewareResult = outerStep.handle(Context.background(),
        middlewareContext)
    print("middleware=" + trace.join(",") + "," + str(middlewareResult.isOk()))

    List<String> shortTrace = []
    ApiMiddleware shortCircuit = new ShortMiddleware(shortTrace)
    ApiHandler shortStep = new MiddlewareStep(shortCircuit, traceHandler)
    HttpExchange shortExchange = apiTestExchange(HttpMethod.Get, "/short", "", null)
    ApiContext shortContext = new ApiContext(shortExchange, new ApiOptions())
    Result<Unit, Error> shortResult = shortStep.handle(Context.background(), shortContext)
    print("middleware-short=" + shortTrace.join(",") + "," + str(shortResult.isOk()) + "," +
        str(shortContext.status()))

    HttpExchange bodyExchange = apiTestExchange(HttpMethod.Post,
        "/api/users?id=7", "application/json", "{\"name\":\"a\"}")
    ApiContext bodyContext = new ApiContext(bodyExchange, new ApiOptions())
    Result<String, Error> bodyText = bodyContext.bodyText(Context.background())
    Int firstLength = bodyContext.bodyBytes(Context.background()).value().length()
    Int secondLength = bodyContext.bodyBytes(Context.background()).value().length()
    Result<JsonValue, Error> bodyJson = bodyContext.bodyJson(Context.background())
    print("context=" + httpMethodName(bodyContext.method()) + "," + bodyContext.path() + "," +
        (bodyContext.queryParameter("id") as String) + "," +
        (bodyContext.header("Content-Type") as String) + "," + bodyText.value())
    print("context-body=" + str(firstLength) + "," + str(secondLength) + "," +
        Json.stringify(bodyJson.value()) + "," + str(bodyContext.isResponseStarted()))

    ApiOptions smallOptions = new ApiOptions()
    smallOptions.maximumBodyBytes(4 as Long)
    HttpExchange largeExchange = apiTestExchange(HttpMethod.Post, "/large", "", "12345")
    ApiContext largeContext = new ApiContext(largeExchange, smallOptions)
    Result<Bytes, Error> largeBody = largeContext.bodyBytes(Context.background())
    print("context-limit=" + errorKindName(largeBody.error().kind()))

    HttpExchange stateExchange = apiTestExchange(HttpMethod.Get, "/state", "", null)
    ApiContext stateContext = new ApiContext(stateExchange, new ApiOptions())
    stateContext.setStatus(201).setHeader("X-Test", "1").addHeader("X-Test", "2")
    HttpHeaders responseHeaders = stateContext.responseHeaders()
    Result<Unit, Error> jsonResponse = stateContext.respondJson(Context.background(),
        Json.string("ok"))
    print("context-state=" + str(stateContext.status()) + "," +
        str(responseHeaders.getAll("X-Test").length()) + "," +
        errorKindName(jsonResponse.error().kind()) + "," +
        str(stateContext.isResponseStarted()) + "," + str(stateContext.isResponded()))

    HttpExchange problemExchange = apiTestExchange(HttpMethod.Get, "/problem", "", null)
    ApiContext problemContext = new ApiContext(problemExchange, new ApiOptions())
    ProblemDetails missing = ProblemDetails.of(404).withDetail("gone")
    Result<Unit, Error> problemResponse = problemContext.respondProblem(Context.background(),
        missing)
    print("context-problem=" + str(problemResponse.isErr()) + "," +
        str(problemContext.status()) + "," + str(problemContext.isResponseStarted()))

    FakeAuthenticator authenticator = new FakeAuthenticator(AuthScheme.Basic)
    HttpExchange authExchange = apiTestExchange(HttpMethod.Get, "/auth", "", null)
    ApiContext authContext = new ApiContext(authExchange, new ApiOptions())
    Result<Unit, Error> authenticated = authenticator.authenticate(Context.background(),
        authContext)
    print("auth=" + authSchemeName(authenticator.scheme()) + "," + authenticator.name() + "," +
        authenticator.realm() + "," + (authContext.principalName() as String) + "," +
        authContext.roles().get(0) + "," + str(authContext.hasRole("admin")) + "," +
        str(authenticated.isOk()))

    HttpExchange attachExchange = apiTestExchange(HttpMethod.Get, "/api/users/9", "", null)
    ApiContext attachContext = new ApiContext(attachExchange, new ApiOptions())
    Result<Map<String, String>, Error> attachParameters =
        userRoute.extractPathParameters("/users/9/posts/3")
    attachContext.attachRoute(userRoute, attachParameters.value())
    ApiRoute attachedRoute = attachContext.route() as ApiRoute
    print("attach=" + attachedRoute.pattern() + "," +
        (attachContext.pathParameter("userId") as String))

    HttpExchange closeExchange = apiTestExchange(HttpMethod.Get, "/close", "", null)
    ApiContext closeContext = new ApiContext(closeExchange, new ApiOptions())
    Result<Unit, Error> closed = closeContext.close()
    Result<Bytes, Error> afterClose = closeContext.bodyBytes(Context.background())
    print("close=" + str(closed.isOk()) + "," + str(closeContext.isClosed()) + "," +
        errorKindName(afterClose.error().kind()) + "," +
        str(closeContext.close().isOk()))

    RateLimitPolicy routeRate = new RateLimitPolicy(3, 1000 as Long)
    ApiRoute configured = new ApiRoute(HttpMethod.Get, "/configured", noop)
    configured.middleware(outer).prependMiddleware(inner).publicAccess()
        .withoutRateLimit().operationName("getConfigured")
        .authenticator(authenticator).rateLimitPolicy(routeRate)
        .requestValidator(Rules.required())
    JsonValue schema = Json.object()
    configured.requestSchema(schema)
    ApiRoute configuredCopy = configured.copy()
    configuredCopy.operationName("copyConfigured")
    print("route-config=" + str(configured.getMiddleware().length()) + "," +
        str(configured.isPublicAccess()) + "," + str(configured.isRateLimitDisabled()) +
        "," + (configured.getOperationName() as String) + "," +
        str(configured.getAuthenticator() != null) + "," +
        str(configured.getRateLimitPolicy() != null) + "," +
        str(configured.getRequestValidator() != null) + "," +
        str(configured.getRequestSchema() != null) + "," +
        (configuredCopy.getOperationName() as String))
    print("route-config-mw=" + str(configured.getMiddleware().length()))

    String minimalDoc = "{\"openapi\":\"3.1.0\",\"info\":{\"title\":\"Minimal\",\"version\":\"1.0\"}}"
    Result<OpenApiDocument, Error> parsedDocument = OpenApiDocument.parse(minimalDoc)
    OpenApiDocument minimal = parsedDocument.value()
    print("doc-parse=" + minimal.version() + "," + minimal.infoTitle() + "," +
        minimal.infoVersion() + "," + str(minimal.operationCount()) + "," +
        str(minimal.hasPath("/none")) + "," + str(minimal.pathItem("/none") == null))

    Result<OpenApiDocument, Error> badRoot = OpenApiDocument.parse("[]")
    Result<OpenApiDocument, Error> badInfo = OpenApiDocument.parse(
        "{\"openapi\":\"3.1.0\",\"info\":[]}")
    Result<OpenApiDocument, Error> badVersion = OpenApiDocument.parse(
        "{\"openapi\":\"\",\"info\":{\"title\":\"t\",\"version\":\"1\"}}")
    Result<OpenApiDocument, Error> badJson = OpenApiDocument.parse("{")
    print("doc-errors=" + errorKindName(badRoot.error().kind()) + "," +
        errorKindName(badInfo.error().kind()) + "," +
        errorKindName(badVersion.error().kind()) + "," +
        errorKindName(badJson.error().kind()))

    String multiDoc = "{\"openapi\":\"3.1.0\",\"info\":{\"title\":\"M\",\"version\":\"1\"}," +
        "\"paths\":{\"/a\":{\"get\":{},\"post\":{},\"patch\":{}},\"/b\":{\"head\":{}}}}"
    OpenApiDocument multi = OpenApiDocument.parse(multiDoc).value()
    OpenApiDocument multiCopy = multi.copy()
    print("doc-count=" + str(multi.operationCount()) + "," +
        str(multiCopy.operationCount()) + "," +
        str(multi.toJsonText(false).length()) + "," +
        str(multi.toJsonText(true).indexOf("\n") >= 0))

    OpenApiBuilder docBuilder = new OpenApiBuilder("Pipeline", "2.0.0")
    docBuilder.summary("Api summary").description("Api description")
        .termsOfService("https://example/terms")
        .contact("Ada", "https://example", "ada@example")
        .license("MIT", "MIT", "https://opensource.org/licenses/MIT")
        .jsonSchemaDialect("https://json-schema.org/draft/2020-12/schema")
        .externalDocs("https://example/docs", "External docs")
        .server("https://api.example", "prod").tag("users", "Users")
        .httpSecurityScheme("basicAuth", AuthScheme.Basic, "basic")
        .apiKeySecurityScheme("apiKey", AuthScheme.ApiKeyHeader, "X-API-Key", "key")
    List<String> globalScopes = []
    docBuilder.globalSecurity("basicAuth", globalScopes)
    JsonValue componentUser = Json.object()
    docBuilder.componentSchema("User", componentUser)
    JsonValue componentNotFound = Json.object()
    docBuilder.componentResponse("NotFound", componentNotFound)
    JsonValue componentLimit = Json.object()
    docBuilder.componentParameter("Limit", componentLimit)
    JsonValue webhookItem = Json.object()
    docBuilder.webhook("userCreated", webhookItem)

    NoopHandler docNoop = new NoopHandler()
    ApiRoute docRoute = new ApiRoute(HttpMethod.Get, "/users/{id}", docNoop)
    docRoute.summary("Get user").description("Fetch one user").tag("users")
        .operationName("getUserById")
    JsonValue userSchema = Json.object()
    docRoute.requestSchema(userSchema)
    docRoute.queryParameter("limit", "max results", false, Json.object())
    docRoute.headerParameter("X-Trace", "trace id", false, Json.object())
    docRoute.responseWithSchema(200, "User found", Json.object())
    docRoute.response(404, "Not found")
    Result<Unit, Error> docAdded = docBuilder.addRoute(docRoute)
    ApiRoute duplicateRoute = new ApiRoute(HttpMethod.Get, "/users/{id}", docNoop)
    duplicateRoute.operationName("otherName")
    Result<Unit, Error> docDuplicate = docBuilder.addRoute(duplicateRoute)
    ApiRoute duplicateName = new ApiRoute(HttpMethod.Post, "/users", docNoop)
    duplicateName.operationName("getUserById")
    Result<Unit, Error> docDuplicateName = docBuilder.addRoute(duplicateName)
    ApiRoute autoRoute = new ApiRoute(HttpMethod.Post, "/users", docNoop)
    Result<Unit, Error> docAuto = docBuilder.addRoute(autoRoute)
    print("builder-add=" + str(docAdded.isOk()) + "," +
        errorKindName(docDuplicate.error().kind()) + "," +
        errorKindName(docDuplicateName.error().kind()) + "," +
        str(docAuto.isOk()) + "," + str(docBuilder.operationCount()))

    ApiRouter docRouter = new ApiRouter("/v1")
    docRouter.get("/ping", docNoop)
    Result<Unit, Error> routerAdded = docBuilder.addRouter(docRouter)
    Result<Unit, Error> routerAgain = docBuilder.addRouter(docRouter)
    print("builder-router=" + str(routerAdded.isOk()) + "," +
        str(routerAgain.isOk()) + "," + str(docBuilder.operationCount()))

    Result<OpenApiDocument, Error> builtDocument = docBuilder.build()
    OpenApiDocument apiDocument = builtDocument.value()
    JsonObject apiJson = apiDocument.toJson()
    JsonValue componentsValue = apiJson.getOr("components", Json.nullValue())
    JsonObject components = componentsValue.asObject() as JsonObject
    JsonValue schemasValue = components.getOr("schemas", Json.nullValue())
    JsonObject schemas = schemasValue.asObject() as JsonObject
    JsonValue pathsValue = apiJson.getOr("paths", Json.nullValue())
    JsonObject paths = pathsValue.asObject() as JsonObject
    print("builder-doc=" + apiDocument.version() + "," +
        str(apiDocument.operationCount()) + "," + str(apiDocument.hasPath("/users/{id}")) +
        "," + str(apiDocument.hasPath("/v1/ping")) + "," +
        str(schemas.has("ProblemDetails")) + "," + str(paths.length()) + "," +
        str(apiDocument.toJsonText(true).indexOf("\n") >= 0) + "," +
        str(apiDocument.tags().length()) + "," + str(apiDocument.servers().length()))

    JsonObject userItem = apiDocument.pathItem("/users/{id}") as JsonObject
    JsonValue userOperationValue = userItem.getOr("get", Json.nullValue())
    JsonObject userOperation = userOperationValue.asObject() as JsonObject
    JsonValue responsesValue = userOperation.getOr("responses", Json.nullValue())
    JsonObject responses = responsesValue.asObject() as JsonObject
    JsonValue parametersValue = userOperation.getOr("parameters", Json.nullValue())
    JsonArray operationParameters = parametersValue.asArray() as JsonArray
    print("builder-operation=" +
        (userOperation.getOr("operationId", Json.nullValue()).asString() as String) + "," +
        str(responses.has("200")) + "," + str(responses.has("404")) + "," +
        str(responses.has("default")) + "," + str(operationParameters.length()) + "," +
        str(userOperation.has("requestBody")))

    ApiOptions openApiOptions = new ApiOptions()
    openApiOptions.openApi(docBuilder).openApiPath("/docs.json")
    ApiOptions openApiCopy = openApiOptions.copy()
    print("options-openapi=" + str(openApiOptions.openApiBuilder() != null) + "," +
        openApiOptions.getOpenApiPath() + "," +
        str(openApiCopy.openApiBuilder() != null) + "," +
        openApiCopy.getOpenApiPath())
    openApiOptions.openApiPath("")
    print("options-openapi-off=" + openApiOptions.getOpenApiPath())

    ApiRouter basicRouter = new ApiRouter()
    basicRouter.get("/hello", new TextHandler("hello"))
    ApiOptions basicOptions = new ApiOptions()
    ApiServer basicServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19140").value(), basicRouter, basicOptions).value()
    RunningApiServer basicRunning = new RunningApiServer(basicServer, Context.background())
    sleepMs(40)
    ApiWire basicGet = apiWire(Context.background(), 19140, "GET", "/hello", "", "")
    ApiWire basicMissing = apiWire(Context.background(), 19140, "GET", "/missing", "", "")
    ApiWire basicPost = apiWire(Context.background(), 19140, "POST", "/hello", "", "")
    ApiWire basicOptionsWire = apiWire(Context.background(), 19140, "OPTIONS", "/hello", "", "")
    ApiWire basicHead = apiWire(Context.background(), 19140, "HEAD", "/hello", "", "")
    print("server-basic=" + str(basicGet.status()) + "," + basicGet.body() + "," +
        str(basicMissing.status()) + "," + str(basicPost.status()) + "," +
        str(basicPost.header("allow").indexOf("GET") >= 0) + "," +
        str(basicOptionsWire.status()) + "," +
        str(basicOptionsWire.header("allow").indexOf("OPTIONS") >= 0) + "," +
        str(basicHead.status()) + "," + str(basicHead.body().length()) + "," +
        str(basicServer.routeCount()) + "," + basicServer.localAddress().text() + "," +
        str(basicServer.openApiDocument() == null))
    basicRunning.stop()
    print("server-closed=" + str(basicServer.isOpen()) + "," + str(basicServer.close().isOk()))

    ApiRouter authRouter = new ApiRouter()
    DenyAuthenticator challengeAuth = new DenyAuthenticator(ErrorKind.InvalidArgument,
        AuthScheme.Basic, "basicAuth", "", "realm1")
    ApiRoute protectedRoute = authRouter.get("/protected", new TextHandler("no")).value()
    protectedRoute.authenticator(challengeAuth)
    DenyAuthenticator forbiddenAuth = new DenyAuthenticator(ErrorKind.PermissionDenied,
        AuthScheme.Bearer, "bearerAuth", "", "")
    ApiRoute forbiddenRoute = authRouter.get("/forbidden", new TextHandler("no")).value()
    forbiddenRoute.authenticator(forbiddenAuth)
    DenyAuthenticator keyAuth = new DenyAuthenticator(ErrorKind.NotFound,
        AuthScheme.ApiKeyHeader, "apiKeyAuth", "X-API-Key", "")
    ApiRoute keyRoute = authRouter.get("/apikey", new TextHandler("no")).value()
    keyRoute.authenticator(keyAuth)
    authRouter.get("/public", new TextHandler("public")).value().publicAccess()
    authRouter.get("/who", new PrincipalTextHandler())
    ApiOptions authOptions = new ApiOptions()
    FakeAuthenticator allowAuth = new FakeAuthenticator(AuthScheme.Basic)
    authOptions.authenticator(allowAuth)
    ApiServer authServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19141").value(), authRouter, authOptions).value()
    RunningApiServer authRunning = new RunningApiServer(authServer, Context.background())
    sleepMs(40)
    ApiWire authProtected = apiWire(Context.background(), 19141, "GET", "/protected", "", "")
    ApiWire authForbidden = apiWire(Context.background(), 19141, "GET", "/forbidden", "", "")
    ApiWire authKey = apiWire(Context.background(), 19141, "GET", "/apikey", "", "")
    ApiWire authPublic = apiWire(Context.background(), 19141, "GET", "/public", "", "")
    ApiWire authWho = apiWire(Context.background(), 19141, "GET", "/who", "", "")
    print("server-auth=" + str(authProtected.status()) + "," +
        authProtected.header("www-authenticate") + "," + str(authForbidden.status()) + "," +
        str(authKey.status()) + "," + str(authKey.hasHeader("www-authenticate")) + "," +
        str(authPublic.status()) + "," + authPublic.body() + "," + str(authWho.status()) + "," +
        authWho.body())
    authRunning.stop()

    ApiRouter rateRouter = new ApiRouter()
    RateLimitPolicy rateOne = new RateLimitPolicy(1, 1000 as Long)
    ApiRoute limitedRoute = rateRouter.get("/limited", new TextHandler("ok")).value()
    limitedRoute.rateLimitPolicy(rateOne)
    rateRouter.get("/free", new TextHandler("free")).value().withoutRateLimit()
    ApiOptions rateOptions = new ApiOptions()
    rateOptions.rateLimitPolicy(new RateLimitPolicy(10, 1000 as Long))
    ApiServer rateServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19142").value(), rateRouter, rateOptions).value()
    RunningApiServer rateRunning = new RunningApiServer(rateServer, Context.background())
    sleepMs(40)
    ApiWire rateFirst = apiWire(Context.background(), 19142, "GET", "/limited", "", "")
    ApiWire rateSecond = apiWire(Context.background(), 19142, "GET", "/limited", "", "")
    ApiWire rateFreeFirst = apiWire(Context.background(), 19142, "GET", "/free", "", "")
    ApiWire rateFreeSecond = apiWire(Context.background(), 19142, "GET", "/free", "", "")
    print("server-rate=" + str(rateFirst.status()) + "," + str(rateSecond.status()) + "," +
        rateSecond.header("retry-after") + "," + str(rateSecond.hasHeader("retry-after")) +
        "," + str(rateFreeFirst.status()) + "," + str(rateFreeSecond.status()))
    rateRunning.stop()

    ApiRouter rateKeyRouter = new ApiRouter()
    RateLimitPolicy keyPolicy = new RateLimitPolicy(1, 2000 as Long)
    keyPolicy.withKeyHeader("X-Client")
    ApiRoute keyLimitedRoute = rateKeyRouter.get("/keyed", new TextHandler("ok")).value()
    keyLimitedRoute.rateLimitPolicy(keyPolicy)
    ApiServer keyServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19143").value(), rateKeyRouter, new ApiOptions()).value()
    RunningApiServer keyRunning = new RunningApiServer(keyServer, Context.background())
    sleepMs(40)
    ApiWire keyA = apiWire(Context.background(), 19143, "GET", "/keyed",
        "X-Client: a\r\n", "")
    ApiWire keyB = apiWire(Context.background(), 19143, "GET", "/keyed",
        "X-Client: b\r\n", "")
    ApiWire keyA2 = apiWire(Context.background(), 19143, "GET", "/keyed",
        "X-Client: a\r\n", "")
    print("server-rate-key=" + str(keyA.status()) + "," + str(keyB.status()) + "," +
        str(keyA2.status()) + "," + str(keyA2.hasHeader("retry-after")))
    keyRunning.stop()

    ApiRouter corsRouter = new ApiRouter()
    corsRouter.get("/cors", new TextHandler("cors")).value()
    CorsPolicy serverCors = new CorsPolicy()
    serverCors.allowOrigin("https://app.example").allowHeader("Content-Type")
    ApiOptions corsOptions = new ApiOptions()
    corsOptions.corsPolicy(serverCors)
    ApiServer corsServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19144").value(), corsRouter, corsOptions).value()
    RunningApiServer corsRunning = new RunningApiServer(corsServer, Context.background())
    sleepMs(40)
    ApiWire corsOk = apiWire(Context.background(), 19144, "OPTIONS", "/cors",
        "Origin: https://app.example\r\n" +
        "Access-Control-Request-Method: POST\r\n" +
        "Access-Control-Request-Headers: Content-Type\r\n", "")
    ApiWire corsBad = apiWire(Context.background(), 19144, "OPTIONS", "/cors",
        "Origin: https://evil.example\r\nAccess-Control-Request-Method: POST\r\n", "")
    ApiWire corsActual = apiWire(Context.background(), 19144, "GET", "/cors",
        "Origin: https://app.example\r\n", "")
    ApiWire corsActualBad = apiWire(Context.background(), 19144, "GET", "/cors",
        "Origin: https://evil.example\r\n", "")
    print("server-cors=" + str(corsOk.status()) + "," +
        corsOk.header("access-control-allow-origin") + "," +
        str(corsOk.header("access-control-allow-methods").indexOf("POST") >= 0) + "," +
        str(corsBad.status()) + "," + str(corsActual.status()) + "," +
        corsActual.header("access-control-allow-origin") + "," +
        str(corsActualBad.hasHeader("access-control-allow-origin")))
    corsRunning.stop()

    ApiRouter middlewareRouter = new ApiRouter()
    List<String> serverTrace = []
    ApiMiddleware serverGlobalTrace = new TraceMiddleware("global", serverTrace)
    ApiMiddleware serverRouterTrace = new TraceMiddleware("router", serverTrace)
    ApiMiddleware serverRouteTrace = new TraceMiddleware("route", serverTrace)
    ApiRoute tracedRoute = middlewareRouter.get("/trace", new TraceHandler(serverTrace)).value()
    tracedRoute.middleware(serverRouteTrace)
    middlewareRouter.use(serverRouterTrace)
    ApiOptions middlewareOptions = new ApiOptions()
    middlewareOptions.use(serverGlobalTrace)
    ApiServer middlewareServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19145").value(), middlewareRouter,
        middlewareOptions).value()
    RunningApiServer middlewareRunning = new RunningApiServer(middlewareServer,
        Context.background())
    sleepMs(40)
    ApiWire middlewareWire = apiWire(Context.background(), 19145, "GET", "/trace", "", "")
    print("server-middleware=" + str(middlewareWire.status()) + "," +
        serverTrace.join(","))
    middlewareRunning.stop()

    ApiRouter failRouter = new ApiRouter()
    ApiRoute failRoute = failRouter.get("/fail", new TextHandler("no")).value()
    failRoute.middleware(new FailMiddleware(ErrorKind.Internal))
    ApiServer failServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19146").value(), failRouter, new ApiOptions()).value()
    RunningApiServer failRunning = new RunningApiServer(failServer, Context.background())
    sleepMs(40)
    ApiWire failWire = apiWire(Context.background(), 19146, "GET", "/fail", "", "")
    print("server-fail=" + str(failWire.status()) + "," +
        str(apiWireContains(failWire, "urn:xdk:api:internal")) + "," +
        str(apiWireContains(failWire, "middleware failure")))
    failRunning.stop()

    ApiOptions detailOptions = new ApiOptions()
    detailOptions.includeErrorDetail(true)
    ApiServer detailServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19150").value(), failRouter, detailOptions).value()
    RunningApiServer detailRunning = new RunningApiServer(detailServer, Context.background())
    sleepMs(40)
    ApiWire detailWire = apiWire(Context.background(), 19150, "GET", "/fail", "", "")
    print("server-detail=" + str(detailWire.status()) + "," +
        str(apiWireContains(detailWire, "middleware failure")))
    detailRunning.stop()

    ApiRouter validateRouter = new ApiRouter()
    ApiRoute validatedRoute = validateRouter.post("/validated",
        new TextHandler("valid")).value()
    validatedRoute.requestValidator(Rules.required())
    ApiServer validateServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19147").value(), validateRouter,
        new ApiOptions()).value()
    RunningApiServer validateRunning = new RunningApiServer(validateServer,
        Context.background())
    sleepMs(40)
    ApiWire invalidBody = apiWire(Context.background(), 19147, "POST", "/validated",
        "Content-Type: application/json\r\n", "")
    ApiWire malformedBody = apiWire(Context.background(), 19147, "POST", "/validated",
        "Content-Type: application/json\r\n", "{")
    print("server-validate=" + str(invalidBody.status()) + "," +
        str(invalidBody.body().indexOf("validation") >= 0) + "," +
        str(malformedBody.status()))
    validateRunning.stop()

    ApiRouter openApiRouter = new ApiRouter()
    openApiRouter.get("/listed", new TextHandler("listed"))
    OpenApiBuilder serverBuilder = new OpenApiBuilder("Server", "1.0.0")
    ApiOptions serverOpenApiOptions = new ApiOptions()
    serverOpenApiOptions.openApi(serverBuilder).openApiPath("/openapi.json")
    ApiServer openApiServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19148").value(), openApiRouter,
        serverOpenApiOptions).value()
    RunningApiServer openApiRunning = new RunningApiServer(openApiServer,
        Context.background())
    sleepMs(40)
    ApiWire openApiWire = apiWire(Context.background(), 19148, "GET", "/openapi.json", "", "")
    ApiWire listedWire = apiWire(Context.background(), 19148, "GET", "/listed", "", "")
    print("server-openapi=" + str(openApiWire.status()) + "," +
        openApiWire.header("content-type") + "," +
        str(apiWireContains(openApiWire, "\"openapi\":\"3.1.0\"")) + "," +
        str(apiWireContains(openApiWire, "/listed")) + "," +
        str(openApiServer.openApiDocument() != null) + "," + str(listedWire.status()))
    openApiRunning.stop()

    ApiRouter httpRouter = new ApiRouter()
    httpRouter.get("/ping", new TextHandler("pong"))
    httpRouter.post("/echo", new TextHandler("echoed"))
    ApiServer httpServer = ApiServer.bind(Context.background(),
        SocketAddress.parse("127.0.0.1:19149").value(), httpRouter,
        new ApiOptions()).value()
    RunningApiServer httpRunning = new RunningApiServer(httpServer, Context.background())
    sleepMs(40)
    HttpClient httpClient = new HttpClient()
    HttpResponse pingResponse = httpClient.request(Context.background(),
        new HttpRequest(HttpMethod.Get,
            Uri.parse("http://127.0.0.1:19149/ping").value())).value()
    HttpRequest echoRequest = new HttpRequest(HttpMethod.Post,
        Uri.parse("http://127.0.0.1:19149/echo").value())
    echoRequest = echoRequest.withHeader("Content-Type", "application/json")
    echoRequest = echoRequest.withBody(HttpBody.fromText("{\"x\":1}"))
    HttpResponse echoResponse = httpClient.request(Context.background(), echoRequest).value()
    httpClient.close()
    print("server-http=" + str(pingResponse.status().code()) + "," +
        pingResponse.body().readText(1024 as Long).value() + "," +
        str(echoResponse.status().code()) + "," +
        echoResponse.body().readText(1024 as Long).value())
    httpRunning.stop()
    return 0
}

static HttpExchange apiTestExchange(HttpMethod method, String target,
                                     String contentType, String? body) {
    Result<Uri, Error> parsed = Uri.parse(target)
    Uri uri = parsed.value()
    HttpRequest request = new HttpRequest(method, uri)
    if contentType != "" { request = request.withHeader("Content-Type", contentType) }
    if body != null { request = request.withBody(HttpBody.fromText(body as String)) }
    return new HttpExchange(request, 0 as Int64)
}

static Void boolTestPrint(Bool keyOne, Bool keyTwo) {
    print("rate-keys=" + str(keyOne) + "," + str(keyTwo))
}
