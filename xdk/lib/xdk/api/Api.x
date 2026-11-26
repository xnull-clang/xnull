// xdk.api —— API 基础类型（M23.1）
//
// 实现 ProblemDetails/AuthScheme/CorsPolicy/RateLimitPolicy；
// ApiContext/Route/Router/Server/OpenAPI/SSE 留 M23.2/M23.3。
package xdk.api
import xdk.errors
import xdk.codec
import xdk.net.http
import xdk.net.uri
import xdk.validate
import xdk.runtime

// ---------- 管线协议 ----------
protocol ApiHandler {
    Result<Unit, Error> handle(Context context, ApiContext exchange);
}

protocol ApiMiddleware {
    Result<Unit, Error> handle(Context context, ApiContext exchange, ApiHandler next);
}

protocol Authenticator {
    AuthScheme scheme();
    String name();
    String parameterName();
    String realm();
    Result<Unit, Error> authenticate(Context context, ApiContext exchange);
}

// ---------- ProblemDetails ----------
class ProblemDetails {
    final String _type
    final String _title
    final Int _status
    final String _detail
    final String _instance
    final JsonObject _extensions

    ProblemDetails(Int status) {
        if status < 100 || status > 599 { throw "ProblemDetails: invalid status" }
        self._status = status
        self._type = "about:blank"
        String reason = HttpStatus.of(status).reason()
        if reason == "" { self._title = "HTTP " + str(status) }
        else { self._title = reason }
        self._detail = ""
        self._instance = ""
        self._extensions = new JsonObject()
    }

    private ProblemDetails(String type, String title, Int status, String detail,
                           String instance, JsonObject extensions) {
        self._type = type
        self._title = title
        self._status = status
        self._detail = detail
        self._instance = instance
        self._extensions = extensions.copy()
    }

    static ProblemDetails of(Int status) { return new ProblemDetails(status) }

    static ProblemDetails fromValidation(List<ValidationError> errors) {
        if errors == null { throw "ProblemDetails.fromValidation: null errors" }
        JsonValue itemsValue = Json.array()
        JsonArray items = itemsValue.asArray() as JsonArray
        Int index = 0
        while index < errors.length() {
            ValidationError error = errors.get(index)
            JsonObject item = new JsonObject()
            item.set("field", Json.string(error.path()))
            item.set("code", Json.string(error.code()))
            item.set("detail", Json.string(error.message()))
            items.add(apiJsonObject(item))
            index = index + 1
        }
        ProblemDetails problem = ProblemDetails.of(422)
            .withType("urn:xdk:api:validation")
            .withTitle("Validation failed")
            .withDetail(str(errors.length()) + " validation error(s)")
        return problem.extension("errors", itemsValue)
    }

    String type() { return self._type }
    String title() { return self._title }
    Int status() { return self._status }
    String detail() { return self._detail }
    String instance() { return self._instance }
    JsonObject extensions() { return self._extensions.copy() }

    ProblemDetails withType(String type) {
        if type == null || type == "" { throw "ProblemDetails.withType: empty type" }
        if type.indexOf("\n") >= 0 || type.indexOf("\r") >= 0 {
            throw "ProblemDetails.withType: multiline"
        }
        return new ProblemDetails(type, self._title, self._status, self._detail,
            self._instance, self._extensions)
    }

    ProblemDetails withTitle(String title) {
        if title == null || title == "" { throw "ProblemDetails.withTitle: empty title" }
        if title.indexOf("\n") >= 0 || title.indexOf("\r") >= 0 {
            throw "ProblemDetails.withTitle: multiline"
        }
        return new ProblemDetails(self._type, title, self._status, self._detail,
            self._instance, self._extensions)
    }

    ProblemDetails withDetail(String detail) {
        if detail == null { throw "ProblemDetails.withDetail: null" }
        return new ProblemDetails(self._type, self._title, self._status, detail,
            self._instance, self._extensions)
    }

    ProblemDetails withInstance(String instance) {
        if instance == null { throw "ProblemDetails.withInstance: null" }
        return new ProblemDetails(self._type, self._title, self._status, self._detail,
            instance, self._extensions)
    }

    ProblemDetails extension(String name, JsonValue value) {
        if name == null || name == "" { throw "ProblemDetails.extension: empty name" }
        if name.indexOf("\n") >= 0 || name.indexOf("\r") >= 0 {
            throw "ProblemDetails.extension: multiline name"
        }
        if name == "type" || name == "title" || name == "status" ||
            name == "detail" || name == "instance" {
            throw "ProblemDetails.extension: reserved name"
        }
        if value == null { throw "ProblemDetails.extension: null value" }
        JsonObject next = self._extensions.copy()
        next.set(name, value)
        return new ProblemDetails(self._type, self._title, self._status, self._detail,
            self._instance, next)
    }

    JsonObject toJson() {
        JsonObject object = new JsonObject()
        object.set("type", Json.string(self._type))
        object.set("title", Json.string(self._title))
        object.set("status", Json.number(str(self._status)))
        if self._detail != "" { object.set("detail", Json.string(self._detail)) }
        if self._instance != "" { object.set("instance", Json.string(self._instance)) }
        List<String> keys = self._extensions.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            object.set(key, self._extensions.getOr(key, Json.nullValue()))
            index = index + 1
        }
        return object
    }

    JsonValue toJsonValue() { return apiJsonObject(self.toJson()) }
    Bool isClientError() { return self._status >= 400 && self._status <= 499 }
    Bool isServerError() { return self._status >= 500 && self._status <= 599 }

    Bool equals(ProblemDetails other) {
        if other == null { return false }
        return self._type == other.type() && self._title == other.title() &&
            self._status == other.status() && self._detail == other.detail() &&
            self._instance == other.instance() &&
            Json.stringify(self.toJsonValue()) == Json.stringify(other.toJsonValue())
    }

    ProblemDetails copy() {
        return new ProblemDetails(self._type, self._title, self._status,
            self._detail, self._instance, self._extensions)
    }

    String describe() { return str(self._status) + " " + self._title }
    String toString() { return self.describe() }
}

static JsonValue apiJsonObject(JsonObject object) {
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

// ---------- AuthScheme ----------
enum AuthScheme {
    Basic,
    Bearer,
    ApiKeyHeader,
    ApiKeyQuery,
    ApiKeyCookie,
}

String authSchemeName(AuthScheme scheme) {
    if scheme == AuthScheme.Basic { return "basic" }
    if scheme == AuthScheme.Bearer { return "bearer" }
    if scheme == AuthScheme.ApiKeyHeader { return "api-key-header" }
    if scheme == AuthScheme.ApiKeyQuery { return "api-key-query" }
    return "api-key-cookie"
}

String authSchemeOpenApiType(AuthScheme scheme) {
    if scheme == AuthScheme.Basic || scheme == AuthScheme.Bearer { return "http" }
    return "apiKey"
}

String authSchemeOpenApiLocation(AuthScheme scheme) {
    if scheme == AuthScheme.ApiKeyQuery { return "query" }
    if scheme == AuthScheme.ApiKeyCookie { return "cookie" }
    return "header"
}

String authSchemeChallenge(AuthScheme scheme, String realm) {
    if realm == null { throw "authSchemeChallenge: null realm" }
    if realm.indexOf("\"") >= 0 || realm.indexOf("\\") >= 0 ||
        realm.indexOf("\n") >= 0 || realm.indexOf("\r") >= 0 {
        throw "authSchemeChallenge: invalid realm"
    }
    if scheme == AuthScheme.Basic {
        if realm == "" { return "Basic" }
        return "Basic realm=\"" + realm + "\""
    }
    if scheme == AuthScheme.Bearer { return "Bearer" }
    return ""
}

// ---------- CorsPolicy ----------
class CorsPolicy {
    final List<String> _allowedOrigins
    final List<HttpMethod> _allowedMethods
    final List<String> _allowedHeaders
    final List<String> _exposedHeaders
    Bool _allowCredentials
    Long _maxAgeSeconds

    CorsPolicy() {
        List<String> origins = []
        self._allowedOrigins = origins
        self._allowedMethods = [HttpMethod.Get, HttpMethod.Post, HttpMethod.Put,
            HttpMethod.Patch, HttpMethod.Delete, HttpMethod.Head, HttpMethod.Options]
        List<String> headers = []
        self._allowedHeaders = headers
        List<String> exposed = []
        self._exposedHeaders = exposed
        self._allowCredentials = false
        self._maxAgeSeconds = 0 as Long
    }

    CorsPolicy allowOrigin(String origin) {
        if origin == null || origin == "" { throw "CorsPolicy.allowOrigin: empty origin" }
        if origin.indexOf("\n") >= 0 || origin.indexOf("\r") >= 0 {
            throw "CorsPolicy.allowOrigin: multiline origin"
        }
        if origin == "*" && self._allowCredentials {
            throw "CorsPolicy.allowOrigin: wildcard with credentials"
        }
        Int index = 0
        while index < self._allowedOrigins.length() {
            if self._allowedOrigins.get(index) == origin { return self }
            index = index + 1
        }
        self._allowedOrigins.push(origin)
        return self
    }

    CorsPolicy allowOrigins(List<String> origins) {
        if origins == null { throw "CorsPolicy.allowOrigins: null" }
        Int index = 0
        while index < origins.length() {
            self.allowOrigin(origins.get(index))
            index = index + 1
        }
        return self
    }

    CorsPolicy allowAnyOrigin() { return self.allowOrigin("*") }
    List<String> allowedOrigins() { return self._allowedOrigins.copy() }

    Bool isOriginAllowed(String origin) {
        if origin == null || origin == "" { return false }
        Int index = 0
        while index < self._allowedOrigins.length() {
            String value = self._allowedOrigins.get(index)
            if value == "*" || value == origin { return true }
            index = index + 1
        }
        return false
    }

    CorsPolicy allowMethod(HttpMethod method) {
        Int index = 0
        while index < self._allowedMethods.length() {
            if self._allowedMethods.get(index) == method { return self }
            index = index + 1
        }
        self._allowedMethods.push(method)
        return self
    }

    List<HttpMethod> allowedMethods() { return self._allowedMethods.copy() }

    CorsPolicy allowHeader(String name) {
        if !isValidHeaderName(name) { throw "CorsPolicy.allowHeader: invalid name" }
        if name == "*" && self._allowCredentials {
            throw "CorsPolicy.allowHeader: wildcard with credentials"
        }
        if !hasHeader(self._allowedHeaders, name) { self._allowedHeaders.push(name) }
        return self
    }

    CorsPolicy allowAnyHeader() { return self.allowHeader("*") }
    List<String> allowedHeaders() { return self._allowedHeaders.copy() }

    CorsPolicy exposeHeader(String name) {
        if !isValidHeaderName(name) { throw "CorsPolicy.exposeHeader: invalid name" }
        if !hasHeader(self._exposedHeaders, name) { self._exposedHeaders.push(name) }
        return self
    }

    List<String> exposedHeaders() { return self._exposedHeaders.copy() }

    CorsPolicy allowCredentials(Bool value) {
        if value && (containsValue(self._allowedOrigins, "*") ||
            containsValue(self._allowedHeaders, "*")) {
            throw "CorsPolicy.allowCredentials: wildcard already configured"
        }
        self._allowCredentials = value
        return self
    }

    Bool isAllowCredentials() { return self._allowCredentials }

    CorsPolicy maxAgeSeconds(Long value) {
        if value < 0 as Long { throw "CorsPolicy.maxAgeSeconds: invalid" }
        self._maxAgeSeconds = value
        return self
    }

    Long getMaxAgeSeconds() { return self._maxAgeSeconds }

    Bool isMethodAllowed(HttpMethod method) {
        Int index = 0
        while index < self._allowedMethods.length() {
            if self._allowedMethods.get(index) == method { return true }
            index = index + 1
        }
        return false
    }

    Bool isHeaderAllowed(String name) {
        if name == null { return false }
        Int index = 0
        while index < self._allowedHeaders.length() {
            String value = self._allowedHeaders.get(index)
            if value == "*" || value.toLower() == name.toLower() { return true }
            index = index + 1
        }
        return false
    }

    Map<String, String> actualHeaders(String origin) {
        Map<String, String> headers = [:]
        if !self.isOriginAllowed(origin) { return headers }
        if containsValue(self._allowedOrigins, "*") {
            headers.put("Access-Control-Allow-Origin", "*")
        } else {
            headers.put("Access-Control-Allow-Origin", origin)
            headers.put("Vary", "Origin")
        }
        if self._allowCredentials {
            headers.put("Access-Control-Allow-Credentials", "true")
        }
        if self._exposedHeaders.length() > 0 {
            headers.put("Access-Control-Expose-Headers", self._exposedHeaders.join(", "))
        }
        return headers
    }

    Map<String, String> preflightHeaders(String origin, HttpMethod requestMethod,
                                         List<String> requestHeaders) {
        Map<String, String> headers = [:]
        if !self.isOriginAllowed(origin) { return headers }
        if !self.isMethodAllowed(requestMethod) { return headers }
        Int index = 0
        while index < requestHeaders.length() {
            if !self.isHeaderAllowed(requestHeaders.get(index)) { return headers }
            index = index + 1
        }
        headers.put("Access-Control-Allow-Origin",
            containsValue(self._allowedOrigins, "*") ? "*" : origin)
        headers.put("Vary", "Origin, Access-Control-Request-Method, Access-Control-Request-Headers")
        headers.put("Access-Control-Allow-Methods", joinHttpMethods(self._allowedMethods))
        if requestHeaders.length() > 0 {
            headers.put("Access-Control-Allow-Headers", requestHeaders.join(", "))
        }
        if self._allowCredentials {
            headers.put("Access-Control-Allow-Credentials", "true")
        }
        if self._maxAgeSeconds > 0 as Long {
            headers.put("Access-Control-Max-Age", str(self._maxAgeSeconds))
        }
        return headers
    }

    CorsPolicy copy() {
        CorsPolicy result = new CorsPolicy()
        result._allowedOrigins.clear()
        Int index = 0
        while index < self._allowedOrigins.length() {
            result._allowedOrigins.push(self._allowedOrigins.get(index))
            index = index + 1
        }
        result._allowedMethods.clear()
        index = 0
        while index < self._allowedMethods.length() {
            result._allowedMethods.push(self._allowedMethods.get(index))
            index = index + 1
        }
        index = 0
        while index < self._allowedHeaders.length() {
            result._allowedHeaders.push(self._allowedHeaders.get(index))
            index = index + 1
        }
        index = 0
        while index < self._exposedHeaders.length() {
            result._exposedHeaders.push(self._exposedHeaders.get(index))
            index = index + 1
        }
        result._allowCredentials = self._allowCredentials
        result._maxAgeSeconds = self._maxAgeSeconds
        return result
    }
}

static String joinHttpMethods(List<HttpMethod> methods) {
    List<String> names = []
    Int index = 0
    while index < methods.length() {
        names.push(httpMethodName(methods.get(index)))
        index = index + 1
    }
    return names.join(", ")
}

static Bool containsValue(List<String> values, String target) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == target { return true }
        index = index + 1
    }
    return false
}

static Bool hasHeader(List<String> values, String name) {
    Int index = 0
    while index < values.length() {
        if values.get(index).toLower() == name.toLower() { return true }
        index = index + 1
    }
    return false
}

static Bool isValidHeaderName(String name) {
    if name == null || name == "" { return false }
    if name.indexOf("\n") >= 0 || name.indexOf("\r") >= 0 { return false }
    if name == "*" { return true }
    Int index = 0
    while index < name.length() {
        Int code = name.get(index)
        Bool token = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
            (code >= 97 && code <= 122) || code == 45 || code == 95
        if !token { return false }
        index = index + 1
    }
    return true
}

// ---------- RateLimitPolicy ----------
class RateLimitPolicy {
    final Int _limit
    final Long _windowMillis
    final RuntimeMonitor _monitor
    final Map<String, Int> _counts
    final Map<String, Long> _windowStarts
    Bool _includeRoute
    String? _keyHeader
    Int _maximumKeys

    RateLimitPolicy(Int limit, Long windowMillis) {
        if limit <= 0 || windowMillis <= 0 as Long {
            throw "RateLimitPolicy: invalid limit or window"
        }
        self._limit = limit
        self._windowMillis = windowMillis
        self._monitor = new RuntimeMonitor()
        Map<String, Int> counts = [:]
        self._counts = counts
        Map<String, Long> starts = [:]
        self._windowStarts = starts
        self._includeRoute = true
        self._keyHeader = null
        self._maximumKeys = 1024
    }

    Int limit() { return self._limit }
    Long windowMillis() { return self._windowMillis }
    Bool isIncludeRoute() { return self._includeRoute }
    String? getKeyHeader() { return self._keyHeader }
    Int getMaximumKeys() { return self._maximumKeys }

    RateLimitPolicy withIncludeRoute(Bool value) {
        self._includeRoute = value
        return self
    }

    RateLimitPolicy withKeyHeader(String name) {
        if name == null || name == "" || name.indexOf("\n") >= 0 ||
            name.indexOf("\r") >= 0 {
            throw "RateLimitPolicy.withKeyHeader: invalid"
        }
        self._keyHeader = name
        return self
    }

    RateLimitPolicy withoutKeyHeader() {
        self._keyHeader = null
        return self
    }

    RateLimitPolicy withMaximumKeys(Int value) {
        if value <= 0 { throw "RateLimitPolicy.withMaximumKeys: invalid" }
        self._maximumKeys = value
        return self
    }

    Bool allow(String key) {
        String actualKey = key
        if actualKey == null || actualKey == "" { actualKey = "default" }
        self._monitor.enter()
        Long now = nowMono()
        Int count = 0
        if self._counts.has(actualKey) { count = self._counts.getOr(actualKey, 0) }
        Long start = now
        if self._windowStarts.has(actualKey) {
            start = self._windowStarts.getOr(actualKey, now)
            if now - start >= self._windowMillis {
                count = 0
                start = now
                self._windowStarts.put(actualKey, start)
            }
        } else {
            if self._counts.keys().length() >= self._maximumKeys {
                self._monitor.exit()
                return false
            }
            self._windowStarts.put(actualKey, start)
        }
        if count >= self._limit {
            self._monitor.exit()
            return false
        }
        self._counts.put(actualKey, count + 1)
        self._monitor.exit()
        return true
    }

    RateLimitPolicy copy() {
        RateLimitPolicy result = new RateLimitPolicy(self._limit, self._windowMillis)
        result._includeRoute = self._includeRoute
        result._keyHeader = self._keyHeader
        result._maximumKeys = self._maximumKeys
        return result
    }
}


// ---------- ApiOptions ----------
class ApiOptions {
    final List<ApiMiddleware> _middleware
    Authenticator? _authenticator
    RateLimitPolicy? _rateLimitPolicy
    CorsPolicy? _corsPolicy
    Long _maximumBodyBytes
    Long _sseBufferBytes
    Bool _includeErrorDetail
    Bool _autoOptions
    String _problemTypeBase
    OpenApiBuilder? _openApiBuilder
    String _openApiPath

    ApiOptions() {
        List<ApiMiddleware> middleware = []
        self._middleware = middleware
        self._authenticator = null
        self._rateLimitPolicy = null
        self._corsPolicy = null
        self._maximumBodyBytes = 8388608 as Long
        self._sseBufferBytes = 1048576 as Long
        self._includeErrorDetail = false
        self._autoOptions = true
        self._problemTypeBase = ""
        self._openApiBuilder = null
        self._openApiPath = "/openapi.json"
    }

    ApiOptions use(ApiMiddleware middleware) {
        if middleware == null { throw "ApiOptions.use: null middleware" }
        self._middleware.push(middleware)
        return self
    }

    List<ApiMiddleware> middleware() { return self._middleware.copy() }

    ApiOptions authenticator(Authenticator value) {
        if value == null { throw "ApiOptions.authenticator: null" }
        self._authenticator = value
        return self
    }

    Authenticator? getAuthenticator() { return self._authenticator }

    ApiOptions rateLimitPolicy(RateLimitPolicy value) {
        if value == null { throw "ApiOptions.rateLimitPolicy: null" }
        self._rateLimitPolicy = value
        return self
    }

    RateLimitPolicy? getRateLimitPolicy() { return self._rateLimitPolicy }

    ApiOptions corsPolicy(CorsPolicy value) {
        if value == null { throw "ApiOptions.corsPolicy: null" }
        self._corsPolicy = value
        return self
    }

    CorsPolicy? getCorsPolicy() { return self._corsPolicy }

    ApiOptions maximumBodyBytes(Long value) {
        if value <= 0 as Long { throw "ApiOptions.maximumBodyBytes: invalid" }
        self._maximumBodyBytes = value
        return self
    }

    Long getMaximumBodyBytes() { return self._maximumBodyBytes }

    ApiOptions sseBufferBytes(Long value) {
        if value <= 0 as Long { throw "ApiOptions.sseBufferBytes: invalid" }
        self._sseBufferBytes = value
        return self
    }

    Long getSseBufferBytes() { return self._sseBufferBytes }

    ApiOptions includeErrorDetail(Bool value) {
        self._includeErrorDetail = value
        return self
    }

    Bool isIncludeErrorDetail() { return self._includeErrorDetail }

    ApiOptions autoOptions(Bool value) {
        self._autoOptions = value
        return self
    }

    Bool isAutoOptions() { return self._autoOptions }

    ApiOptions problemTypeBase(String value) {
        if value == null { throw "ApiOptions.problemTypeBase: null" }
        if value != "" {
            Bool valid = value.startsWith("urn:") || value.startsWith("http://") ||
                value.startsWith("https://")
            if !valid || value.endsWith("/") {
                throw "ApiOptions.problemTypeBase: invalid prefix"
            }
        }
        self._problemTypeBase = value
        return self
    }

    String getProblemTypeBase() { return self._problemTypeBase }

    ApiOptions openApi(OpenApiBuilder value) {
        if value == null { throw "ApiOptions.openApi: null builder" }
        self._openApiBuilder = value
        return self
    }

    OpenApiBuilder? openApiBuilder() { return self._openApiBuilder }

    ApiOptions openApiPath(String value) {
        if value == null { throw "ApiOptions.openApiPath: null" }
        if value != "" {
            if !value.startsWith("/") || value.indexOf("?") >= 0 ||
                value.indexOf("#") >= 0 {
                throw "ApiOptions.openApiPath: invalid path"
            }
            if value.endsWith("/") && value != "/" {
                throw "ApiOptions.openApiPath: trailing slash"
            }
        }
        self._openApiPath = value
        return self
    }

    String getOpenApiPath() { return self._openApiPath }

    ApiOptions copy() {
        ApiOptions result = new ApiOptions()
        Int index = 0
        while index < self._middleware.length() {
            result._middleware.push(self._middleware.get(index))
            index = index + 1
        }
        result._authenticator = self._authenticator
        result._rateLimitPolicy = self._rateLimitPolicy
        if self._corsPolicy != null {
            CorsPolicy actualCors = self._corsPolicy as CorsPolicy
            result._corsPolicy = actualCors.copy()
        }
        result._maximumBodyBytes = self._maximumBodyBytes
        result._sseBufferBytes = self._sseBufferBytes
        result._includeErrorDetail = self._includeErrorDetail
        result._autoOptions = self._autoOptions
        result._problemTypeBase = self._problemTypeBase
        result._openApiBuilder = self._openApiBuilder
        result._openApiPath = self._openApiPath
        return result
    }
}

// ---------- ApiRoute ----------
class ApiRoute {
    final HttpMethod _method
    final String _pattern
    final ApiHandler _handler
    final List<String> _pathParameterNames
    final Bool _hasWildcard
    final List<ApiMiddleware> _middleware
    Authenticator? _authenticator
    RateLimitPolicy? _rateLimitPolicy
    Bool _rateLimitDisabled
    Bool _publicAccess
    Validator? _requestValidator
    JsonValue? _requestSchema
    String? _operationName
    String? _summary
    String? _description
    final List<String> _tags
    final JsonArray _queryParameters
    final JsonArray _headerParameters
    final List<Int> _responseCodes
    final Map<Int, String> _responseDescriptions
    final Map<Int, JsonValue> _responseSchemas

    ApiRoute(HttpMethod method, String pattern, ApiHandler handler) {
        if pattern == null || handler == null {
            throw "ApiRoute: null argument"
        }
        if method == HttpMethod.Connect { throw "ApiRoute: CONNECT is not supported" }
        if !pattern.startsWith("/") {
            throw "ApiRoute: pattern must start with slash"
        }
        if pattern != "/" && pattern.endsWith("/") {
            throw "ApiRoute: pattern trailing slash"
        }
        if pattern.indexOf("?") >= 0 || pattern.indexOf("#") >= 0 {
            throw "ApiRoute: pattern has query or fragment"
        }
        List<String> names = []
        Bool wildcard = false
        List<String> segments = apiSplitSegments(pattern)
        Int index = 0
        while index < segments.length() {
            String segment = segments.get(index)
            if segment == "" { throw "ApiRoute: empty pattern segment" }
            if segment == "*" {
                if index != segments.length() - 1 {
                    throw "ApiRoute: wildcard must be final"
                }
                wildcard = true
            } else if segment.indexOf("{") >= 0 || segment.indexOf("}") >= 0 {
                if !(segment.startsWith("{") && segment.endsWith("}")) {
                    throw "ApiRoute: parameter must occupy full segment"
                }
                String name = segment.substring(1, segment.length() - 2)
                if !apiValidParameterName(name) {
                    throw "ApiRoute: invalid parameter name"
                }
                if apiContainsString(names, name) {
                    throw "ApiRoute: duplicate parameter name"
                }
                names.push(name)
            } else if segment.indexOf("*") >= 0 {
                throw "ApiRoute: wildcard must occupy full segment"
            }
            index = index + 1
        }
        self._method = method
        self._pattern = pattern
        self._handler = handler
        self._pathParameterNames = names
        self._hasWildcard = wildcard
        List<ApiMiddleware> middleware = []
        self._middleware = middleware
        self._authenticator = null
        self._rateLimitPolicy = null
        self._rateLimitDisabled = false
        self._publicAccess = false
        self._requestValidator = null
        self._requestSchema = null
        self._operationName = null
        self._summary = null
        self._description = null
        List<String> tags = []
        self._tags = tags
        self._queryParameters = new JsonArray()
        self._headerParameters = new JsonArray()
        List<Int> responseCodes = []
        self._responseCodes = responseCodes
        Map<Int, String> responseDescriptions = [:]
        self._responseDescriptions = responseDescriptions
        Map<Int, JsonValue> responseSchemas = [:]
        self._responseSchemas = responseSchemas
    }

    HttpMethod method() { return self._method }
    String pattern() { return self._pattern }
    ApiHandler handler() { return self._handler }
    List<String> pathParameterNames() { return self._pathParameterNames.copy() }

    Bool matchesPath(String path) { return self.extractPathParameters(path).isOk() }

    Result<Map<String, String>, Error> extractPathParameters(String path) {
        if path == null || !path.startsWith("/") {
            return Err(new BasicError(ErrorKind.NotFound, "route did not match"))
        }
        List<String> patternSegments = apiSplitSegments(self._pattern)
        List<String> pathSegments = apiSplitSegments(path)
        Int fixedCount = patternSegments.length()
        if self._hasWildcard { fixedCount = fixedCount - 1 }
        if self._hasWildcard {
            if pathSegments.length() < fixedCount {
                return Err(new BasicError(ErrorKind.NotFound, "route did not match"))
            }
        } else if patternSegments.length() != pathSegments.length() {
            return Err(new BasicError(ErrorKind.NotFound, "route did not match"))
        }
        Map<String, String> result = [:]
        Int index = 0
        while index < fixedCount {
            String patternSegment = patternSegments.get(index)
            String pathSegment = pathSegments.get(index)
            if pathSegment == "" {
                return Err(new BasicError(ErrorKind.NotFound, "empty path segment"))
            }
            if patternSegment.startsWith("{") && patternSegment.endsWith("}") {
                String name = patternSegment.substring(1, patternSegment.length() - 2)
                Result<String, Error> decoded = percentDecode(pathSegment)
                if decoded.isErr() { return Err(decoded.error()) }
                String value = decoded.value()
                if value == "" {
                    return Err(new BasicError(ErrorKind.NotFound, "empty path parameter"))
                }
                result.put(name, value)
            } else if patternSegment != pathSegment {
                return Err(new BasicError(ErrorKind.NotFound, "route did not match"))
            }
            index = index + 1
        }
        if self._hasWildcard {
            Int rest = fixedCount
            while rest < pathSegments.length() {
                if pathSegments.get(rest) == "" {
                    return Err(new BasicError(ErrorKind.NotFound, "empty path segment"))
                }
                rest = rest + 1
            }
        }
        return Ok(result)
    }

    ApiRoute middleware(ApiMiddleware value) {
        if value == null { throw "ApiRoute.middleware: null" }
        self._middleware.push(value)
        return self
    }

    ApiRoute prependMiddleware(ApiMiddleware value) {
        if value == null { throw "ApiRoute.prependMiddleware: null" }
        List<ApiMiddleware> next = []
        next.push(value)
        Int index = 0
        while index < self._middleware.length() {
            next.push(self._middleware.get(index))
            index = index + 1
        }
        self._middleware.clear()
        index = 0
        while index < next.length() {
            self._middleware.push(next.get(index))
            index = index + 1
        }
        return self
    }

    List<ApiMiddleware> getMiddleware() { return self._middleware.copy() }

    ApiRoute authenticator(Authenticator value) {
        if value == null { throw "ApiRoute.authenticator: null" }
        self._authenticator = value
        return self
    }

    Authenticator? getAuthenticator() { return self._authenticator }

    ApiRoute publicAccess() { self._publicAccess = true; return self }
    Bool isPublicAccess() { return self._publicAccess }

    ApiRoute rateLimitPolicy(RateLimitPolicy value) {
        if value == null { throw "ApiRoute.rateLimitPolicy: null" }
        self._rateLimitPolicy = value
        return self
    }

    RateLimitPolicy? getRateLimitPolicy() { return self._rateLimitPolicy }

    ApiRoute withoutRateLimit() { self._rateLimitDisabled = true; return self }
    Bool isRateLimitDisabled() { return self._rateLimitDisabled }

    ApiRoute requestValidator(Validator value) {
        if value == null { throw "ApiRoute.requestValidator: null" }
        self._requestValidator = value
        return self
    }

    Validator? getRequestValidator() { return self._requestValidator }

    ApiRoute requestSchema(JsonValue value) {
        if value == null { throw "ApiRoute.requestSchema: null" }
        self._requestSchema = value
        return self
    }

    JsonValue? getRequestSchema() { return self._requestSchema }

    ApiRoute operationName(String value) {
        if value == null || value == "" {
            throw "ApiRoute.operationName: empty"
        }
        self._operationName = value
        return self
    }

    String? getOperationName() { return self._operationName }

    ApiRoute summary(String value) {
        if value == null { throw "ApiRoute.summary: null" }
        self._summary = value
        return self
    }

    String? getSummary() { return self._summary }

    ApiRoute description(String value) {
        if value == null { throw "ApiRoute.description: null" }
        self._description = value
        return self
    }

    String? getDescription() { return self._description }

    ApiRoute tag(String value) {
        if value == null || value == "" { throw "ApiRoute.tag: empty" }
        if !apiContainsString(self._tags, value) { self._tags.push(value) }
        return self
    }

    List<String> getTags() { return self._tags.copy() }

    ApiRoute queryParameter(String name, String description, Bool required,
                            JsonValue schema) {
        if !isValidHeaderName(name) {
            throw "ApiRoute.queryParameter: invalid name"
        }
        if description == null || schema == null {
            throw "ApiRoute.queryParameter: null argument"
        }
        self._queryParameters.add(apiParameterObject(name, "query", description,
            required, schema))
        return self
    }

    JsonArray getQueryParameters() { return self._queryParameters.copy() }

    ApiRoute headerParameter(String name, String description, Bool required,
                             JsonValue schema) {
        if !isValidHeaderName(name) {
            throw "ApiRoute.headerParameter: invalid name"
        }
        if description == null || schema == null {
            throw "ApiRoute.headerParameter: null argument"
        }
        self._headerParameters.add(apiParameterObject(name, "header", description,
            required, schema))
        return self
    }

    JsonArray getHeaderParameters() { return self._headerParameters.copy() }

    ApiRoute response(Int status, String description) {
        return self.responseWithSchema(status, description, null)
    }

    ApiRoute responseWithSchema(Int status, String description, JsonValue? schema) {
        if status < 100 || status > 599 {
            throw "ApiRoute.response: invalid status"
        }
        if description == null { throw "ApiRoute.response: null description" }
        if !apiContainsInt(self._responseCodes, status) {
            self._responseCodes.push(status)
        }
        self._responseDescriptions.put(status, description)
        if schema != null { self._responseSchemas.put(status, schema) }
        return self
    }

    List<Int> getResponseCodes() { return self._responseCodes.copy() }

    String getResponseDescription(Int status) {
        if !self._responseDescriptions.has(status) { return "" }
        return self._responseDescriptions.getOr(status, "")
    }

    JsonValue? getResponseSchema(Int status) {
        if !self._responseSchemas.has(status) { return null }
        return self._responseSchemas.getOr(status, Json.nullValue())
    }

    ApiRoute copy() {
        ApiRoute result = new ApiRoute(self._method, self._pattern, self._handler)
        Int index = 0
        while index < self._middleware.length() {
            result._middleware.push(self._middleware.get(index))
            index = index + 1
        }
        result._authenticator = self._authenticator
        result._rateLimitPolicy = self._rateLimitPolicy
        result._rateLimitDisabled = self._rateLimitDisabled
        result._publicAccess = self._publicAccess
        result._requestValidator = self._requestValidator
        result._requestSchema = self._requestSchema
        result._operationName = self._operationName
        result._summary = self._summary
        result._description = self._description
        index = 0
        while index < self._tags.length() {
            result._tags.push(self._tags.get(index))
            index = index + 1
        }
        index = 0
        while index < self._queryParameters.length() {
            result._queryParameters.add(self._queryParameters.get(index))
            index = index + 1
        }
        index = 0
        while index < self._headerParameters.length() {
            result._headerParameters.add(self._headerParameters.get(index))
            index = index + 1
        }
        index = 0
        while index < self._responseCodes.length() {
            Int code = self._responseCodes.get(index)
            result._responseCodes.push(code)
            result._responseDescriptions.put(code, self._responseDescriptions.getOr(code, ""))
            if self._responseSchemas.has(code) {
                result._responseSchemas.put(code, self._responseSchemas.getOr(code,
                    Json.nullValue()))
            }
            index = index + 1
        }
        return result
    }
}

// ---------- ApiRouter ----------
class ApiRouter {
    final String _prefix
    final List<ApiRoute> _routes
    final List<ApiMiddleware> _middleware

    ApiRouter() {
        self._prefix = ""
        List<ApiRoute> routes = []
        self._routes = routes
        List<ApiMiddleware> middleware = []
        self._middleware = middleware
    }

    ApiRouter(String prefix) {
        if prefix == null { throw "ApiRouter: null prefix" }
        if prefix != "" && !prefix.startsWith("/") {
            throw "ApiRouter: prefix must start with slash"
        }
        if prefix != "" && prefix != "/" && prefix.endsWith("/") {
            throw "ApiRouter: prefix trailing slash"
        }
        if prefix.indexOf("?") >= 0 || prefix.indexOf("#") >= 0 {
            throw "ApiRouter: prefix has query or fragment"
        }
        if prefix == "/" { self._prefix = "" } else { self._prefix = prefix }
        List<ApiRoute> routes = []
        self._routes = routes
        List<ApiMiddleware> middleware = []
        self._middleware = middleware
    }

    Result<ApiRoute, Error> route(HttpMethod method, String pattern,
                                  ApiHandler handler) {
        if pattern == null || handler == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null route argument"))
        }
        if method == HttpMethod.Connect {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "CONNECT is not supported"))
        }
        Result<Unit, Error> valid = apiValidateRoutePattern(pattern)
        if valid.isErr() { return Err(valid.error()) }
        String fullPattern = self.combine(pattern)
        if self.hasRoute(method, fullPattern) {
            return Err(new BasicError(ErrorKind.AlreadyExists, "duplicate route"))
        }
        ApiRoute route = new ApiRoute(method, fullPattern, handler)
        self._routes.push(route)
        return Ok(route)
    }

    Bool hasRoute(HttpMethod method, String pattern) {
        Int index = 0
        while index < self._routes.length() {
            ApiRoute route = self._routes.get(index)
            if route.method() == method && route.pattern() == pattern { return true }
            index = index + 1
        }
        return false
    }

    String combine(String pattern) {
        if self._prefix == "" { return pattern }
        if pattern == "/" { return self._prefix }
        return self._prefix + pattern
    }

    Result<ApiRoute, Error> get(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Get, pattern, handler)
    }

    Result<ApiRoute, Error> post(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Post, pattern, handler)
    }

    Result<ApiRoute, Error> put(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Put, pattern, handler)
    }

    Result<ApiRoute, Error> patch(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Patch, pattern, handler)
    }

    Result<ApiRoute, Error> delete(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Delete, pattern, handler)
    }

    Result<ApiRoute, Error> head(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Head, pattern, handler)
    }

    Result<ApiRoute, Error> options(String pattern, ApiHandler handler) {
        return self.route(HttpMethod.Options, pattern, handler)
    }

    ApiRouter use(ApiMiddleware value) {
        if value == null { throw "ApiRouter.use: null middleware" }
        self._middleware.push(value)
        return self
    }

    List<ApiMiddleware> middleware() { return self._middleware.copy() }

    String prefix() { return self._prefix }
    Int routeCount() { return self._routes.length() }

    List<ApiRoute> routes() {
        List<ApiRoute> result = []
        Int index = 0
        while index < self._routes.length() {
            result.push(self._routes.get(index).copy())
            index = index + 1
        }
        return result
    }

    ApiRoute? match(HttpMethod method, String path) {
        if path == null || !path.startsWith("/") { return null }
        Int index = 0
        while index < self._routes.length() {
            ApiRoute route = self._routes.get(index)
            if route.method() == method && route.pattern() == path { return route }
            index = index + 1
        }
        if method == HttpMethod.Head {
            index = 0
            while index < self._routes.length() {
                ApiRoute route = self._routes.get(index)
                if route.method() == HttpMethod.Get && route.pattern() == path {
                    return route
                }
                index = index + 1
            }
        }
        Int bestIndex = -1
        Int bestStatic = -1
        Int bestPriority = -1
        index = 0
        while index < self._routes.length() {
            ApiRoute route = self._routes.get(index)
            Int priority = 0
            if route.method() == method {
                priority = 2
            } else if method == HttpMethod.Head && route.method() == HttpMethod.Get {
                priority = 1
            }
            if priority > 0 {
                if route.matchesPath(path) {
                    Int staticCount = apiStaticSegmentCount(route.pattern())
                    Bool better = false
                    if staticCount > bestStatic {
                        better = true
                    } else if staticCount == bestStatic {
                        if priority > bestPriority { better = true }
                    }
                    if better {
                        bestIndex = index
                        bestStatic = staticCount
                        bestPriority = priority
                    }
                }
            }
            index = index + 1
        }
        if bestIndex < 0 { return null }
        return self._routes.get(bestIndex)
    }

    List<HttpMethod> allowedMethods(String path) {
        List<HttpMethod> result = []
        if path == null || !path.startsWith("/") { return result }
        Int index = 0
        while index < self._routes.length() {
            ApiRoute route = self._routes.get(index)
            if route.matchesPath(path) {
                if apiIndexOfMethod(result, route.method()) < 0 {
                    result.push(route.method())
                }
                if route.method() == HttpMethod.Get &&
                    apiIndexOfMethod(result, HttpMethod.Head) < 0 {
                    result.push(HttpMethod.Head)
                }
            }
            index = index + 1
        }
        return result
    }
}

// ---------- ApiContext ----------
class ApiContext {
    final HttpExchange _exchange
    final ApiOptions _options
    final HttpHeaders _responseHeaders
    ApiRoute? _route
    Map<String, String> _pathParameters
    Int _status
    Bool _responseStarted
    Bool _bodyRead
    Bytes? _bodyBytes
    Bool _bodyJsonParsed
    JsonValue? _bodyJson
    String? _principalName
    List<String> _roles
    JsonObject _attributes
    Bool _closed

    ApiContext(HttpExchange exchange, ApiOptions options) {
        if exchange == null || options == null { throw "ApiContext: null argument" }
        self._exchange = exchange
        self._options = options
        self._responseHeaders = new HttpHeaders()
        self._route = null
        Map<String, String> pathParameters = [:]
        self._pathParameters = pathParameters
        self._status = 200
        self._responseStarted = false
        self._bodyRead = false
        self._bodyBytes = null
        self._bodyJsonParsed = false
        self._bodyJson = null
        self._principalName = null
        List<String> roles = []
        self._roles = roles
        self._attributes = new JsonObject()
        self._closed = false
    }

    HttpRequest request() { return self._exchange.request() }
    HttpMethod method() { return self._exchange.request().method() }
    Uri uri() { return self._exchange.request().uri() }
    String path() { return self._exchange.request().uri().path() }
    HttpHeaders headers() { return self._exchange.request().headers() }

    String? header(String name) {
        if name == null { throw "ApiContext.header: null name" }
        return self._exchange.request().headers().getOrNull(name)
    }

    Query query() { return self._exchange.request().uri().query() }

    String? queryParameter(String name) {
        if name == null { throw "ApiContext.queryParameter: null name" }
        return self._exchange.request().uri().query().getOrNull(name)
    }

    List<String> queryParameterAll(String name) {
        if name == null { throw "ApiContext.queryParameterAll: null name" }
        return self._exchange.request().uri().query().getAll(name)
    }

    String? pathParameter(String name) {
        if name == null { return null }
        if !self._pathParameters.has(name) { return null }
        return self._pathParameters.getOr(name, "")
    }

    Map<String, String> pathParameters() { return apiCopyStringMap(self._pathParameters) }
    ApiRoute? route() { return self._route }

    ApiContext attachRoute(ApiRoute route, Map<String, String> pathParameters) {
        if route == null || pathParameters == null {
            throw "ApiContext.attachRoute: null argument"
        }
        if self._route != null { throw "ApiContext.attachRoute: already attached" }
        self._route = route.copy()
        self._pathParameters = apiCopyStringMap(pathParameters)
        return self
    }

    Bool isAuthenticated() { return self._principalName != null }
    String? principalName() { return self._principalName }

    ApiContext setPrincipal(String value) {
        if value == null || value == "" {
            throw "ApiContext.setPrincipal: empty principal"
        }
        if self._principalName != null {
            throw "ApiContext.setPrincipal: already authenticated"
        }
        self._principalName = value
        return self
    }

    List<String> roles() { return self._roles.copy() }

    ApiContext setRoles(List<String> values) {
        if values == null { throw "ApiContext.setRoles: null roles" }
        if self._principalName == null {
            throw "ApiContext.setRoles: principal not set"
        }
        Int index = 0
        while index < values.length() {
            if values.get(index) == "" {
                throw "ApiContext.setRoles: empty role"
            }
            index = index + 1
        }
        self._roles.clear()
        index = 0
        while index < values.length() {
            self._roles.push(values.get(index))
            index = index + 1
        }
        return self
    }

    Bool hasRole(String role) {
        if role == null { return false }
        return apiContainsString(self._roles, role)
    }

    JsonValue? attribute(String name) {
        if name == null { return null }
        return self._attributes.getOrNull(name)
    }

    ApiContext setAttribute(String name, JsonValue value) {
        if name == null || name == "" {
            throw "ApiContext.setAttribute: empty name"
        }
        if value == null { throw "ApiContext.setAttribute: null value" }
        self._attributes.set(name, value)
        return self
    }

    JsonObject attributes() { return self._attributes.copy() }

    Int status() { return self._status }

    ApiContext setStatus(Int value) {
        if value < 100 || value > 599 { throw "ApiContext.setStatus: invalid status" }
        if self.isResponseStarted() {
            throw "ApiContext.setStatus: response already started"
        }
        self._status = value
        return self
    }

    HttpHeaders responseHeaders() { return self._responseHeaders.copy() }

    ApiContext setHeader(String name, String value) {
        if self.isResponseStarted() {
            throw "ApiContext.setHeader: response already started"
        }
        self._responseHeaders.set(name, value)
        return self
    }

    ApiContext addHeader(String name, String value) {
        if self.isResponseStarted() {
            throw "ApiContext.addHeader: response already started"
        }
        self._responseHeaders.add(name, value)
        return self
    }

    Result<Bytes, Error> bodyBytes(Context context) {
        if context == null { throw "ApiContext.bodyBytes: null context" }
        if self._closed { return Err(apiUnavailable("api context")) }
        if self._bodyRead {
            Bytes cached = self._bodyBytes as Bytes
            return Ok(copy(cached))
        }
        Long? contentLength = self._exchange.request().headers().contentLength()
        if contentLength != null {
            Long actualLength = contentLength as Long
            if actualLength > self._options.getMaximumBodyBytes() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "request body exceeds limit"))
            }
        }
        Result<Bytes, Error> read = self._exchange.request().body().readAll(
            self._options.getMaximumBodyBytes())
        if read.isErr() { return Err(read.error()) }
        self._bodyBytes = read.value()
        self._bodyRead = true
        return Ok(copy(read.value()))
    }

    Result<String, Error> bodyText(Context context) {
        if context == null { throw "ApiContext.bodyText: null context" }
        Result<Bytes, Error> read = self.bodyBytes(context)
        if read.isErr() { return Err(read.error()) }
        return Ok(read.value().toString())
    }

    Result<JsonValue, Error> bodyJson(Context context) {
        if context == null { throw "ApiContext.bodyJson: null context" }
        if self._bodyJsonParsed { return Ok(self._bodyJson as JsonValue) }
        Result<Bytes, Error> read = self.bodyBytes(context)
        if read.isErr() { return Err(read.error()) }
        Bytes data = read.value()
        if data.length() == 0 {
            self._bodyJson = Json.nullValue()
            self._bodyJsonParsed = true
            return Ok(Json.nullValue())
        }
        MediaType? requestType = self._exchange.request().headers().contentType()
        if requestType == null {
            return Err(new BasicError(ErrorKind.Unsupported, "request body has no media type"))
        }
        MediaType actualType = requestType as MediaType
        if !actualType.isJson() {
            return Err(new BasicError(ErrorKind.Unsupported, "request body is not JSON"))
        }
        Result<JsonValue, Error> parsed = Json.parse(data.toString())
        if parsed.isErr() { return Err(parsed.error()) }
        self._bodyJson = parsed.value()
        self._bodyJsonParsed = true
        return Ok(parsed.value())
    }

    Result<Unit, Error> respondJson(Context context, JsonValue value) {
        return self.respondJsonWithStatus(context, self._status, value)
    }

    Result<Unit, Error> respondJsonWithStatus(Context context, Int status,
                                              JsonValue value) {
        if context == null || value == null {
            throw "ApiContext.respondJson: null argument"
        }
        return self.send(context, status, "application/json; charset=utf-8",
            Json.toBytes(value))
    }

    Result<Unit, Error> respondText(Context context, String text) {
        return self.respondTextWithStatus(context, self._status, text)
    }

    Result<Unit, Error> respondTextWithStatus(Context context, Int status,
                                              String text) {
        if context == null || text == null {
            throw "ApiContext.respondText: null argument"
        }
        return self.send(context, status, "text/plain; charset=utf-8",
            fromUtf8(text))
    }

    Result<Unit, Error> respondEmpty(Context context, Int status) {
        if context == null { throw "ApiContext.respondEmpty: null context" }
        return self.send(context, status, "", Bytes.empty())
    }

    Result<Unit, Error> respondProblem(Context context, ProblemDetails problem) {
        if context == null || problem == null {
            throw "ApiContext.respondProblem: null argument"
        }
        return self.send(context, problem.status(),
            "application/problem+json; charset=utf-8",
            Json.toBytes(problem.toJsonValue()))
    }

    Bool isResponseStarted() {
        return self._responseStarted || self._exchange.isResponded()
    }

    Bool isResponded() { return self.isResponseStarted() }
    Bool isClosed() { return self._closed }

    Result<Unit, Error> close() {
        if self._closed { return Ok() }
        self._closed = true
        return self._exchange.close()
    }

    Result<Unit, Error> send(Context context, Int status, String contentType,
                             Bytes data) {
        if context == null || data == null { throw "ApiContext.send: null argument" }
        if status < 100 || status > 599 { throw "ApiContext.send: invalid status" }
        if self._closed { return Err(apiUnavailable("api context")) }
        if self.isResponseStarted() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "response already started"))
        }
        Bool noBodyStatus = status == 204 || status == 304
        Bool headRequest = self.method() == HttpMethod.Head
        HttpHeaders headers = new HttpHeaders()
        List<HttpHeader> entries = self._responseHeaders.entries()
        Int index = 0
        while index < entries.length() {
            HttpHeader entry = entries.get(index)
            headers.add(entry.name(), entry.value())
            index = index + 1
        }
        if contentType != "" { headers.set("Content-Type", contentType) }
        HttpBody body = HttpBody.empty()
        if !noBodyStatus && !headRequest { body = HttpBody.fromBytes(data) }
        if !noBodyStatus { headers.set("Content-Length", str(data.length())) }
        HttpResponse response = HttpResponse.of(status).withHeaders(headers).withBody(body)
        self._status = status
        self._responseStarted = true
        return self._exchange.respond(response)
    }
}

// ---------- helpers ----------
static List<String> apiSplitSegments(String path) {
    List<String> result = []
    if path == "/" { return result }
    String text = path
    if text.startsWith("/") { text = text.substring(1, text.length() - 1) }
    if text == "" { return result }
    List<String> parts = text.split("/")
    Int index = 0
    while index < parts.length() {
        result.push(parts.get(index))
        index = index + 1
    }
    return result
}

static Bool apiValidParameterName(String name) {
    if name == "" { return false }
    Int index = 0
    while index < name.length() {
        Int code = name.get(index)
        Bool alpha = (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
        Bool digit = code >= 48 && code <= 57
        if index == 0 {
            if !alpha { return false }
        } else if !alpha && !digit && code != 95 {
            return false
        }
        index = index + 1
    }
    return true
}

static Bool apiContainsString(List<String> values, String target) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == target { return true }
        index = index + 1
    }
    return false
}

static Int apiIndexOfMethod(List<HttpMethod> values, HttpMethod target) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == target { return index }
        index = index + 1
    }
    return -1
}

static Int apiStaticSegmentCount(String pattern) {
    List<String> segments = apiSplitSegments(pattern)
    Int count = 0
    Int index = 0
    while index < segments.length() {
        String segment = segments.get(index)
        if segment != "" && segment != "*" &&
            !(segment.startsWith("{") && segment.endsWith("}")) {
            count = count + 1
        }
        index = index + 1
    }
    return count
}

static Result<Unit, Error> apiValidateRoutePattern(String pattern) {
    if pattern == null || pattern == "" {
        return Err(new BasicError(ErrorKind.InvalidArgument, "empty route pattern"))
    }
    if !pattern.startsWith("/") {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "route pattern must start with slash"))
    }
    if pattern != "/" && pattern.endsWith("/") {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "route pattern trailing slash"))
    }
    if pattern.indexOf("?") >= 0 || pattern.indexOf("#") >= 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "route pattern has query or fragment"))
    }
    List<String> names = []
    List<String> segments = apiSplitSegments(pattern)
    Int index = 0
    while index < segments.length() {
        String segment = segments.get(index)
        if segment == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty route pattern segment"))
        }
        if segment == "*" {
            if index != segments.length() - 1 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "wildcard must be final"))
            }
        } else if segment.indexOf("{") >= 0 || segment.indexOf("}") >= 0 {
            if !(segment.startsWith("{") && segment.endsWith("}")) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "route parameter must occupy a full segment"))
            }
            String name = segment.substring(1, segment.length() - 2)
            if !apiValidParameterName(name) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "invalid route parameter name"))
            }
            if apiContainsString(names, name) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "duplicate route parameter name"))
            }
            names.push(name)
        } else if segment.indexOf("*") >= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "wildcard must occupy a full segment"))
        }
        index = index + 1
    }
    return Ok()
}

static JsonValue apiParameterObject(String name, String location, String description,
                                    Bool required, JsonValue schema) {
    JsonObject parameter = new JsonObject()
    parameter.set("name", Json.string(name))
    parameter.set("in", Json.string(location))
    parameter.set("required", Json.bool(required))
    parameter.set("description", Json.string(description))
    parameter.set("schema", schema)
    return apiJsonObject(parameter)
}

static Bool apiContainsInt(List<Int> values, Int target) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == target { return true }
        index = index + 1
    }
    return false
}

static Map<String, String> apiCopyStringMap(Map<String, String> source) {
    Map<String, String> result = [:]
    List<String> keys = source.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        result.put(key, source.getOr(key, ""))
        index = index + 1
    }
    return result
}

static Error apiUnavailable(String message) {
    return new BasicError(ErrorKind.Unavailable, message)
}

// ---------- OpenApiDocument ----------
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
        self._openapi = openapi
        self._info = info.copy()
        self._jsonSchemaDialect = jsonSchemaDialect
        self._servers = servers.copy()
        self._paths = paths.copy()
        self._webhooks = webhooks.copy()
        self._components = components.copy()
        self._security = security.copy()
        self._tags = tags.copy()
        self._externalDocs = externalDocs
    }

    static Result<OpenApiDocument, Error> parse(String text) {
        if text == null { throw "OpenApiDocument.parse: null text" }
        Result<JsonValue, Error> parsed = Json.parse(text)
        if parsed.isErr() { return Err(parsed.error()) }
        return OpenApiDocument.fromJson(parsed.value())
    }

    static Result<OpenApiDocument, Error> fromJson(JsonValue value) {
        if value == null || !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OpenApiDocument: root must be object"))
        }
        JsonObject root = value.asObject() as JsonObject
        JsonValue? openapiValue = root.getOrNull("openapi")
        if openapiValue == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "OpenApiDocument: missing openapi"))
        }
        JsonValue actualOpenapi = openapiValue as JsonValue
        if !actualOpenapi.isString() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "OpenApiDocument: openapi not string"))
        }
        String openapi = actualOpenapi.asString() as String
        if openapi == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "OpenApiDocument: empty openapi"))
        }
        JsonValue? infoValue = root.getOrNull("info")
        if infoValue == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "OpenApiDocument: missing info"))
        }
        JsonValue actualInfo = infoValue as JsonValue
        if !actualInfo.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "OpenApiDocument: info not object"))
        }
        JsonObject info = actualInfo.asObject() as JsonObject
        String title = apiStringField(info, "title", "")
        String version = apiStringField(info, "version", "")
        if title == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "OpenApiDocument: empty title"))
        }
        if version == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "OpenApiDocument: empty version"))
        }
        String? dialect = null
        JsonValue? dialectValue = root.getOrNull("jsonSchemaDialect")
        if dialectValue != null {
            JsonValue actualDialect = dialectValue as JsonValue
            if !actualDialect.isString() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenApiDocument: jsonSchemaDialect not string"))
            }
            dialect = actualDialect.asString() as String
        }
        JsonObject paths = new JsonObject()
        JsonValue? pathsValue = root.getOrNull("paths")
        if pathsValue != null {
            JsonValue actualPaths = pathsValue as JsonValue
            if !actualPaths.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenApiDocument: paths not object"))
            }
            JsonObject parsedPaths = actualPaths.asObject() as JsonObject
            paths = parsedPaths.copy()
        }
        JsonObject webhooks = new JsonObject()
        JsonValue? webhooksValue = root.getOrNull("webhooks")
        if webhooksValue != null {
            JsonValue actualWebhooks = webhooksValue as JsonValue
            if !actualWebhooks.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenApiDocument: webhooks not object"))
            }
            JsonObject parsedWebhooks = actualWebhooks.asObject() as JsonObject
            webhooks = parsedWebhooks.copy()
        }
        JsonObject components = new JsonObject()
        JsonValue? componentsValue = root.getOrNull("components")
        if componentsValue != null {
            JsonValue actualComponents = componentsValue as JsonValue
            if !actualComponents.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenApiDocument: components not object"))
            }
            JsonObject parsedComponents = actualComponents.asObject() as JsonObject
            components = parsedComponents.copy()
        }
        JsonArray servers = apiArrayField(root, "servers")
        JsonArray security = apiArrayField(root, "security")
        JsonArray tags = apiArrayField(root, "tags")
        JsonObject? externalDocs = null
        JsonValue? externalValue = root.getOrNull("externalDocs")
        if externalValue != null {
            JsonValue actualExternal = externalValue as JsonValue
            if !actualExternal.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "OpenApiDocument: externalDocs not object"))
            }
            JsonObject parsedExternal = actualExternal.asObject() as JsonObject
            externalDocs = parsedExternal.copy()
        }
        return Ok(new OpenApiDocument(openapi, info, dialect, servers, paths, webhooks,
            components, security, tags, externalDocs))
    }

    String version() { return self._openapi }
    JsonObject info() { return self._info.copy() }
    String infoTitle() { return apiStringField(self._info, "title", "") }
    String infoVersion() { return apiStringField(self._info, "version", "") }
    String? jsonSchemaDialect() { return self._jsonSchemaDialect }
    JsonArray servers() { return self._servers.copy() }
    JsonObject paths() { return self._paths.copy() }
    JsonObject webhooks() { return self._webhooks.copy() }
    JsonObject components() { return self._components.copy() }
    JsonArray security() { return self._security.copy() }
    JsonArray tags() { return self._tags.copy() }

    JsonObject? externalDocs() {
        if self._externalDocs == null { return null }
        JsonObject actual = self._externalDocs as JsonObject
        return actual.copy()
    }

    Bool hasPath(String path) {
        if path == null { throw "OpenApiDocument.hasPath: null path" }
        return self._paths.has(path)
    }

    JsonObject? pathItem(String path) {
        if path == null { throw "OpenApiDocument.pathItem: null path" }
        JsonValue? value = self._paths.getOrNull(path)
        if value == null { return null }
        JsonValue actual = value as JsonValue
        if !actual.isObject() { return null }
        JsonObject item = actual.asObject() as JsonObject
        return item.copy()
    }

    Int operationCount() {
        Int count = 0
        List<String> keys = self._paths.keys()
        Int index = 0
        while index < keys.length() {
            JsonValue? value = self._paths.getOrNull(keys.get(index))
            if value != null {
                JsonValue actual = value as JsonValue
                if actual.isObject() {
                    JsonObject item = actual.asObject() as JsonObject
                    if item.has("get") { count = count + 1 }
                    if item.has("put") { count = count + 1 }
                    if item.has("post") { count = count + 1 }
                    if item.has("delete") { count = count + 1 }
                    if item.has("options") { count = count + 1 }
                    if item.has("head") { count = count + 1 }
                    if item.has("patch") { count = count + 1 }
                    if item.has("trace") { count = count + 1 }
                }
            }
            index = index + 1
        }
        return count
    }

    JsonObject toJson() {
        JsonObject root = new JsonObject()
        root.set("openapi", Json.string(self._openapi))
        root.set("info", apiJsonObject(self._info))
        if self._jsonSchemaDialect != null {
            root.set("jsonSchemaDialect", Json.string(self._jsonSchemaDialect as String))
        }
        if self._servers.length() > 0 { root.set("servers", apiJsonArray(self._servers)) }
        root.set("paths", apiJsonObject(self._paths))
        if self._webhooks.length() > 0 {
            root.set("webhooks", apiJsonObject(self._webhooks))
        }
        if self._components.length() > 0 {
            root.set("components", apiJsonObject(self._components))
        }
        if self._security.length() > 0 { root.set("security", apiJsonArray(self._security)) }
        if self._tags.length() > 0 { root.set("tags", apiJsonArray(self._tags)) }
        if self._externalDocs != null {
            JsonObject actualExternal = self._externalDocs as JsonObject
            root.set("externalDocs", apiJsonObject(actualExternal))
        }
        return root
    }

    JsonValue toJsonValue() { return apiJsonObject(self.toJson()) }

    String toJsonText(Bool pretty) {
        if pretty { return Json.stringifyPretty(self.toJsonValue()) }
        return Json.stringify(self.toJsonValue())
    }

    OpenApiDocument copy() {
        OpenApiDocument? result = null
        Result<OpenApiDocument, Error> parsed = OpenApiDocument.fromJson(self.toJsonValue())
        if parsed.isOk() { result = parsed.value() }
        return result as OpenApiDocument
    }
}

// ---------- OpenApiBuilder ----------
class OpenApiBuilder {
    final String _title
    final String _version
    String _summary
    String _description
    String _termsOfService
    JsonObject? _contact
    JsonObject? _license
    String _jsonSchemaDialect
    final JsonArray _servers
    final JsonArray _tags
    final JsonObject _schemas
    final JsonObject _responses
    final JsonObject _parameters
    final JsonObject _securitySchemes
    final JsonArray _security
    final JsonObject _paths
    final JsonObject _webhooks
    JsonObject? _externalDocs
    final List<ApiRouter> _includedRouters
    final Map<String, Int> _operationNames

    OpenApiBuilder(String title, String version) {
        if title == null || title == "" {
            throw "OpenApiBuilder: empty title"
        }
        if version == null || version == "" {
            throw "OpenApiBuilder: empty version"
        }
        if apiHasLineBreak(title) || apiHasLineBreak(version) {
            throw "OpenApiBuilder: title/version has line break"
        }
        self._title = title
        self._version = version
        self._summary = ""
        self._description = ""
        self._termsOfService = ""
        self._contact = null
        self._license = null
        self._jsonSchemaDialect = ""
        self._servers = new JsonArray()
        self._tags = new JsonArray()
        self._schemas = new JsonObject()
        self._responses = new JsonObject()
        self._parameters = new JsonObject()
        self._securitySchemes = new JsonObject()
        self._security = new JsonArray()
        self._paths = new JsonObject()
        self._webhooks = new JsonObject()
        self._externalDocs = null
        List<ApiRouter> routers = []
        self._includedRouters = routers
        Map<String, Int> names = [:]
        self._operationNames = names
    }

    OpenApiBuilder summary(String value) {
        if value == null { throw "OpenApiBuilder.summary: null" }
        self._summary = value
        return self
    }

    OpenApiBuilder description(String value) {
        if value == null { throw "OpenApiBuilder.description: null" }
        self._description = value
        return self
    }

    OpenApiBuilder termsOfService(String value) {
        if value == null || value == "" {
            throw "OpenApiBuilder.termsOfService: empty"
        }
        self._termsOfService = value
        return self
    }

    OpenApiBuilder contact(String name, String url, String email) {
        if name == null || url == null || email == null {
            throw "OpenApiBuilder.contact: null"
        }
        if apiHasLineBreak(name) || apiHasLineBreak(url) || apiHasLineBreak(email) {
            throw "OpenApiBuilder.contact: line break"
        }
        JsonObject value = new JsonObject()
        if name != "" { value.set("name", Json.string(name)) }
        if url != "" { value.set("url", Json.string(url)) }
        if email != "" { value.set("email", Json.string(email)) }
        self._contact = value
        return self
    }

    OpenApiBuilder license(String name, String identifier, String url) {
        if name == null || name == "" || identifier == null || url == null {
            throw "OpenApiBuilder.license: null or empty"
        }
        JsonObject value = new JsonObject()
        value.set("name", Json.string(name))
        if identifier != "" { value.set("identifier", Json.string(identifier)) }
        if url != "" { value.set("url", Json.string(url)) }
        self._license = value
        return self
    }

    OpenApiBuilder jsonSchemaDialect(String uri) {
        if uri == null || uri == "" {
            throw "OpenApiBuilder.jsonSchemaDialect: empty"
        }
        self._jsonSchemaDialect = uri
        return self
    }

    OpenApiBuilder externalDocs(String url, String description) {
        if url == null || url == "" || description == null {
            throw "OpenApiBuilder.externalDocs: invalid"
        }
        JsonObject value = new JsonObject()
        value.set("url", Json.string(url))
        if description != "" { value.set("description", Json.string(description)) }
        self._externalDocs = value
        return self
    }

    OpenApiBuilder server(String url, String description) {
        if url == null || url == "" || description == null {
            throw "OpenApiBuilder.server: invalid"
        }
        JsonObject value = new JsonObject()
        value.set("url", Json.string(url))
        if description != "" { value.set("description", Json.string(description)) }
        self._servers.add(apiJsonObject(value))
        return self
    }

    OpenApiBuilder tag(String name, String description) {
        if name == null || name == "" || description == null {
            throw "OpenApiBuilder.tag: invalid"
        }
        JsonObject value = new JsonObject()
        value.set("name", Json.string(name))
        if description != "" { value.set("description", Json.string(description)) }
        self._tags.add(apiJsonObject(value))
        return self
    }

    OpenApiBuilder httpSecurityScheme(String name, AuthScheme scheme,
                                      String description) {
        if name == null || name == "" || description == null {
            throw "OpenApiBuilder.httpSecurityScheme: invalid"
        }
        if scheme != AuthScheme.Basic && scheme != AuthScheme.Bearer {
            throw "OpenApiBuilder.httpSecurityScheme: not HTTP scheme"
        }
        JsonObject value = new JsonObject()
        value.set("type", Json.string("http"))
        value.set("scheme", Json.string(authSchemeName(scheme)))
        if description != "" { value.set("description", Json.string(description)) }
        self._securitySchemes.set(name, apiJsonObject(value))
        return self
    }

    OpenApiBuilder apiKeySecurityScheme(String name, AuthScheme scheme,
                                        String parameterName, String description) {
        if name == null || name == "" || parameterName == null ||
            parameterName == "" || description == null {
            throw "OpenApiBuilder.apiKeySecurityScheme: invalid"
        }
        if scheme == AuthScheme.Basic || scheme == AuthScheme.Bearer {
            throw "OpenApiBuilder.apiKeySecurityScheme: not API key scheme"
        }
        JsonObject value = new JsonObject()
        value.set("type", Json.string("apiKey"))
        value.set("in", Json.string(authSchemeOpenApiLocation(scheme)))
        value.set("name", Json.string(parameterName))
        if description != "" { value.set("description", Json.string(description)) }
        self._securitySchemes.set(name, apiJsonObject(value))
        return self
    }

    OpenApiBuilder securitySchemeFor(Authenticator authenticator, String description) {
        if authenticator == null { throw "OpenApiBuilder.securitySchemeFor: null" }
        AuthScheme scheme = authenticator.scheme()
        if scheme == AuthScheme.Basic || scheme == AuthScheme.Bearer {
            return self.httpSecurityScheme(authenticator.name(), scheme, description)
        }
        return self.apiKeySecurityScheme(authenticator.name(), scheme,
            authenticator.parameterName(), description)
    }

    OpenApiBuilder globalSecurity(String schemeName, List<String> scopes) {
        if schemeName == null || schemeName == "" || scopes == null {
            throw "OpenApiBuilder.globalSecurity: invalid"
        }
        JsonObject requirement = new JsonObject()
        requirement.set(schemeName, apiStringArray(scopes))
        self._security.add(apiJsonObject(requirement))
        return self
    }

    OpenApiBuilder componentSchema(String name, JsonValue schema) {
        if name == null || name == "" || schema == null {
            throw "OpenApiBuilder.componentSchema: invalid"
        }
        self._schemas.set(name, schema)
        return self
    }

    OpenApiBuilder componentResponse(String name, JsonValue response) {
        if name == null || name == "" || response == null {
            throw "OpenApiBuilder.componentResponse: invalid"
        }
        self._responses.set(name, response)
        return self
    }

    OpenApiBuilder componentParameter(String name, JsonValue parameter) {
        if name == null || name == "" || parameter == null {
            throw "OpenApiBuilder.componentParameter: invalid"
        }
        self._parameters.set(name, parameter)
        return self
    }

    OpenApiBuilder webhook(String name, JsonValue pathItem) {
        if name == null || name == "" || pathItem == null {
            throw "OpenApiBuilder.webhook: invalid"
        }
        self._webhooks.set(name, pathItem)
        return self
    }

    Result<Unit, Error> addRouter(ApiRouter router) {
        if router == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null router"))
        }
        if apiIndexOfRouter(self._includedRouters, router) >= 0 { return Ok() }
        List<ApiRoute> routes = router.routes()
        Int index = 0
        while index < routes.length() {
            Result<Unit, Error> added = self.addRoute(routes.get(index))
            if added.isErr() { return Err(added.error()) }
            index = index + 1
        }
        self._includedRouters.push(router)
        return Ok()
    }

    Result<Unit, Error> addRoute(ApiRoute route) {
        if route == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null route"))
        }
        JsonObject item = new JsonObject()
        JsonValue? itemValue = self._paths.getOrNull(route.pattern())
        if itemValue != null {
            JsonValue actualItem = itemValue as JsonValue
            if !actualItem.isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "path item is not an object"))
            }
            JsonObject parsedItem = actualItem.asObject() as JsonObject
            item = parsedItem.copy()
        }
        String method = httpMethodName(route.method()).toLower()
        if item.has(method) {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "duplicate path operation"))
        }
        String? explicitName = route.getOperationName()
        String operationName = self.generateOperationName(route)
        if explicitName != null {
            String actualExplicit = explicitName as String
            if self._operationNames.has(actualExplicit) {
                return Err(new BasicError(ErrorKind.AlreadyExists,
                    "duplicate operationId"))
            }
            operationName = actualExplicit
        }
        self._operationNames.put(operationName, 1)
        JsonArray parameters = new JsonArray()
        List<String> pathNames = route.pathParameterNames()
        Int pathIndex = 0
        while pathIndex < pathNames.length() {
            JsonObject schema = new JsonObject()
            schema.set("type", Json.string("string"))
            JsonObject parameter = new JsonObject()
            parameter.set("name", Json.string(pathNames.get(pathIndex)))
            parameter.set("in", Json.string("path"))
            parameter.set("required", Json.bool(true))
            parameter.set("schema", apiJsonObject(schema))
            parameters.add(apiJsonObject(parameter))
            pathIndex = pathIndex + 1
        }
        JsonArray queryParameters = route.getQueryParameters()
        Int parameterIndex = 0
        while parameterIndex < queryParameters.length() {
            parameters.add(queryParameters.get(parameterIndex))
            parameterIndex = parameterIndex + 1
        }
        JsonArray headerParameters = route.getHeaderParameters()
        parameterIndex = 0
        while parameterIndex < headerParameters.length() {
            parameters.add(headerParameters.get(parameterIndex))
            parameterIndex = parameterIndex + 1
        }
        JsonObject operation = new JsonObject()
        String? summary = route.getSummary()
        if summary != null && (summary as String) != "" {
            operation.set("summary", Json.string(summary as String))
        }
        String? description = route.getDescription()
        if description != null && (description as String) != "" {
            operation.set("description", Json.string(description as String))
        }
        operation.set("operationId", Json.string(operationName))
        List<String> routeTags = route.getTags()
        if routeTags.length() > 0 {
            operation.set("tags", apiStringArray(routeTags))
        }
        if parameters.length() > 0 {
            operation.set("parameters", apiJsonArray(parameters))
        }
        JsonValue? requestSchema = route.getRequestSchema()
        if requestSchema != null {
            JsonValue schemaValue = requestSchema as JsonValue
            JsonObject media = new JsonObject()
            media.set("schema", schemaValue)
            JsonObject content = new JsonObject()
            content.set("application/json", apiJsonObject(media))
            JsonObject requestBody = new JsonObject()
            requestBody.set("required", Json.bool(true))
            requestBody.set("content", apiJsonObject(content))
            operation.set("requestBody", apiJsonObject(requestBody))
        }
        JsonObject responses = new JsonObject()
        List<Int> responseCodes = route.getResponseCodes()
        if responseCodes.length() == 0 { responseCodes.push(200) }
        Int responseIndex = 0
        while responseIndex < responseCodes.length() {
            Int status = responseCodes.get(responseIndex)
            String responseDescription = route.getResponseDescription(status)
            if responseDescription == "" {
                responseDescription = HttpStatus.of(status).reason()
            }
            if responseDescription == "" {
                responseDescription = "HTTP " + str(status)
            }
            JsonObject response = new JsonObject()
            response.set("description", Json.string(responseDescription))
            JsonValue? responseSchema = route.getResponseSchema(status)
            if responseSchema != null && status != 204 && status != 304 {
                JsonValue schemaValue = responseSchema as JsonValue
                JsonObject media = new JsonObject()
                media.set("schema", schemaValue)
                JsonObject content = new JsonObject()
                content.set("application/json", apiJsonObject(media))
                response.set("content", apiJsonObject(content))
            }
            responses.set(str(status), apiJsonObject(response))
            responseIndex = responseIndex + 1
        }
        if !responses.has("default") {
            JsonObject reference = new JsonObject()
            reference.set("$ref", Json.string("#/components/schemas/ProblemDetails"))
            JsonObject media = new JsonObject()
            media.set("schema", apiJsonObject(reference))
            JsonObject content = new JsonObject()
            content.set("application/problem+json", apiJsonObject(media))
            JsonObject problem = new JsonObject()
            problem.set("description", Json.string("Problem details"))
            problem.set("content", apiJsonObject(content))
            responses.set("default", apiJsonObject(problem))
        }
        operation.set("responses", apiJsonObject(responses))
        if route.isPublicAccess() {
            operation.set("security", apiJsonArray(new JsonArray()))
        } else if route.getAuthenticator() != null {
            Authenticator authenticator = route.getAuthenticator() as Authenticator
            self.securitySchemeFor(authenticator, "Route authentication")
            JsonObject requirement = new JsonObject()
            requirement.set(authenticator.name(), apiJsonArray(new JsonArray()))
            JsonArray security = new JsonArray()
            security.add(apiJsonObject(requirement))
            operation.set("security", apiJsonArray(security))
        }
        item.set(method, apiJsonObject(operation))
        self._paths.set(route.pattern(), apiJsonObject(item))
        return Ok()
    }

    Int operationCount() { return self._operationNames.length() }

    Result<OpenApiDocument, Error> build() {
        if !self._schemas.has("ProblemDetails") {
            JsonObject properties = new JsonObject()
            JsonObject typeProperty = new JsonObject()
            typeProperty.set("type", Json.string("string"))
            typeProperty.set("format", Json.string("uri-reference"))
            properties.set("type", apiJsonObject(typeProperty))
            JsonObject titleProperty = new JsonObject()
            titleProperty.set("type", Json.string("string"))
            properties.set("title", apiJsonObject(titleProperty))
            JsonObject statusProperty = new JsonObject()
            statusProperty.set("type", Json.string("integer"))
            statusProperty.set("minimum", Json.number("100"))
            statusProperty.set("maximum", Json.number("599"))
            properties.set("status", apiJsonObject(statusProperty))
            JsonObject detailProperty = new JsonObject()
            detailProperty.set("type", Json.string("string"))
            properties.set("detail", apiJsonObject(detailProperty))
            JsonObject instanceProperty = new JsonObject()
            instanceProperty.set("type", Json.string("string"))
            instanceProperty.set("format", Json.string("uri-reference"))
            properties.set("instance", apiJsonObject(instanceProperty))
            JsonArray required = new JsonArray()
            required.add(Json.string("type"))
            required.add(Json.string("title"))
            required.add(Json.string("status"))
            JsonObject schema = new JsonObject()
            schema.set("type", Json.string("object"))
            schema.set("properties", apiJsonObject(properties))
            schema.set("required", apiJsonArray(required))
            self._schemas.set("ProblemDetails", apiJsonObject(schema))
        }
        JsonObject info = new JsonObject()
        info.set("title", Json.string(self._title))
        info.set("version", Json.string(self._version))
        if self._summary != "" { info.set("summary", Json.string(self._summary)) }
        if self._description != "" { info.set("description", Json.string(self._description)) }
        if self._termsOfService != "" {
            info.set("termsOfService", Json.string(self._termsOfService))
        }
        if self._contact != null {
            JsonObject actualContact = self._contact as JsonObject
            info.set("contact", apiJsonObject(actualContact))
        }
        if self._license != null {
            JsonObject actualLicense = self._license as JsonObject
            info.set("license", apiJsonObject(actualLicense))
        }
        JsonObject root = new JsonObject()
        root.set("openapi", Json.string("3.1.0"))
        root.set("info", apiJsonObject(info))
        if self._jsonSchemaDialect != "" {
            root.set("jsonSchemaDialect", Json.string(self._jsonSchemaDialect))
        }
        if self._servers.length() > 0 { root.set("servers", apiJsonArray(self._servers)) }
        root.set("paths", apiJsonObject(self._paths))
        if self._webhooks.length() > 0 {
            root.set("webhooks", apiJsonObject(self._webhooks))
        }
        JsonObject components = new JsonObject()
        if self._schemas.length() > 0 {
            components.set("schemas", apiJsonObject(self._schemas))
        }
        if self._responses.length() > 0 {
            components.set("responses", apiJsonObject(self._responses))
        }
        if self._parameters.length() > 0 {
            components.set("parameters", apiJsonObject(self._parameters))
        }
        if self._securitySchemes.length() > 0 {
            components.set("securitySchemes", apiJsonObject(self._securitySchemes))
        }
        if components.length() > 0 {
            root.set("components", apiJsonObject(components))
        }
        if self._security.length() > 0 { root.set("security", apiJsonArray(self._security)) }
        if self._tags.length() > 0 { root.set("tags", apiJsonArray(self._tags)) }
        if self._externalDocs != null {
            JsonObject actualExternal = self._externalDocs as JsonObject
            root.set("externalDocs", apiJsonObject(actualExternal))
        }
        return OpenApiDocument.fromJson(apiJsonObject(root))
    }

    private String generateOperationName(ApiRoute route) {
        String method = httpMethodName(route.method()).toLower()
        String base = method
        List<String> segments = apiSplitSegments(route.pattern())
        Int index = 0
        while index < segments.length() {
            String segment = segments.get(index)
            if segment == "*" {
                base = base + "_wildcard"
            } else if segment.startsWith("{") && segment.endsWith("}") {
                String name = segment.substring(1, segment.length() - 2)
                base = base + "_" + apiSanitizeName(name)
            } else {
                base = base + "_" + apiSanitizeName(segment)
            }
            index = index + 1
        }
        String candidate = base
        Int suffix = 2
        while self._operationNames.has(candidate) {
            candidate = base + "_" + str(suffix)
            suffix = suffix + 1
        }
        return candidate
    }
}

// ---------- OpenAPI helpers ----------
static String apiStringField(JsonObject object, String name, String fallback) {
    JsonValue? value = object.getOrNull(name)
    if value == null { return fallback }
    JsonValue actual = value as JsonValue
    if !actual.isString() { return fallback }
    return actual.asString() as String
}

static JsonArray apiArrayField(JsonObject object, String name) {
    JsonArray result = new JsonArray()
    JsonValue? value = object.getOrNull(name)
    if value == null { return result }
    JsonValue actual = value as JsonValue
    if !actual.isArray() { return result }
    JsonArray source = actual.asArray() as JsonArray
    Int index = 0
    while index < source.length() {
        result.add(source.get(index))
        index = index + 1
    }
    return result
}

static JsonValue apiJsonArray(JsonArray source) {
    JsonValue arrayValue = Json.array()
    JsonArray array = arrayValue.asArray() as JsonArray
    Int index = 0
    while index < source.length() {
        array.add(source.get(index))
        index = index + 1
    }
    return arrayValue
}

static JsonValue apiStringArray(List<String> values) {
    JsonArray array = new JsonArray()
    Int index = 0
    while index < values.length() {
        array.add(Json.string(values.get(index)))
        index = index + 1
    }
    return apiJsonArray(array)
}

static Bool apiHasLineBreak(String text) {
    return text.indexOf("\n") >= 0 || text.indexOf("\r") >= 0
}

static String apiSanitizeName(String text) {
    String result = ""
    Int index = 0
    while index < text.length() {
        Int code = text.get(index)
        Bool alpha = (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
        Bool digit = code >= 48 && code <= 57
        if alpha || digit {
            result = result + text.substring(index, 1)
        } else if code == 95 || code == 45 {
            if !result.endsWith("_") { result = result + "_" }
        }
        index = index + 1
    }
    if result == "" { return "root" }
    return result
}

static Int apiIndexOfRouter(List<ApiRouter> routers, ApiRouter target) {
    Int index = 0
    while index < routers.length() {
        if routers.get(index) == target { return index }
        index = index + 1
    }
    return -1
}
