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
