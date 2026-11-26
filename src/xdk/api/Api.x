// xdk.api —— API 基础类型（M23.1）
//
// 实现 ProblemDetails/AuthScheme/CorsPolicy/RateLimitPolicy；
// ApiContext/Route/Router/Server/OpenAPI/SSE 留 M23.2/M23.3。
package xdk.api
import xdk.errors
import xdk.codec
import xdk.net.http
import xdk.validate
import xdk.runtime

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
        if method == null { throw "CorsPolicy.allowMethod: null" }
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
