package xdk.jwt
import xdk.auth
import xdk.bytes
import xdk.errors
import xdk.tasks
import xdk.codec

class JwtAuthenticator implements Authenticator {
    final Bytes _secret
    final JwtOptions _options

    JwtAuthenticator(Bytes secret, JwtOptions options) {
        if secret == null || options == null { throw "JwtAuthenticator: null argument" }
        if secret.length() == 0 { throw "JwtAuthenticator: empty secret" }
        self._secret = copy(secret)
        self._options = options
    }

    static JwtAuthenticator forSecret(Bytes secret) {
        return new JwtAuthenticator(secret, new JwtOptions())
    }

    AuthScheme scheme() { return AuthScheme.Jwt }

    Result<Principal, Error> authenticate(Context context, Credential credential) {
        if context == null || credential == null { throw "JwtAuthenticator.authenticate: null argument" }
        if context.isCancelled() { return Err(jwtAuthError(ErrorKind.Cancelled, "authentication cancelled")) }
        if credential.scheme() != AuthScheme.Jwt {
            return Err(jwtAuthError(ErrorKind.InvalidArgument, "credential scheme mismatch"))
        }
        Result<JwtClaims, Error> verified = Jwt.verify(credential.value(), self._secret, self._options)
        if verified.isErr() { return Err(verified.error()) }
        if context.isCancelled() { return Err(jwtAuthError(ErrorKind.Cancelled, "authentication cancelled")) }
        JwtClaims claims = verified.value()
        String? subject = claims.subject()
        if subject == null || (subject as String) == "" {
            return Err(jwtAuthError(ErrorKind.PermissionDenied, "missing sub"))
        }
        List<String> roles = jwtAuthList(claims.getOrNull("roles"))
        List<String> permissions = jwtAuthList(claims.getOrNull("permissions"))
        JsonValue? scopeValue = claims.getOrNull("scope")
        if scopeValue != null {
            JsonValue scope = scopeValue as JsonValue
            if scope.isString() {
                jwtAuthAppendText(permissions, scope.asString() as String, " ")
            }
        }
        Map<String, String> snapshot = jwtAuthClaims(claims)
        Principal principal = Principal.authenticated(subject as String, AuthScheme.Jwt)
        Int index = 0
        while index < roles.length() {
            principal = principal.withRole(roles.get(index))
            index = index + 1
        }
        index = 0
        while index < permissions.length() {
            principal = principal.withPermission(permissions.get(index))
            index = index + 1
        }
        List<String> keys = snapshot.keys()
        index = 0
        while index < keys.length() {
            String key = keys.get(index)
            principal = principal.withClaim(key, snapshot.getOr(key, ""))
            index = index + 1
        }
        return Ok(principal)
    }

    String describe() { return "JwtAuthenticator(scheme=jwt)" }
}

static Error jwtAuthError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

static Bool jwtAuthContains(List<String> values, String value) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == value { return true }
        index = index + 1
    }
    return false
}

static Void jwtAuthAppend(List<String> values, String value) {
    if value == null { return }
    String text = value.trim()
    if text == "" { return }
    if !jwtAuthContains(values, text) { values.push(text) }
}

static Void jwtAuthAppendText(List<String> values, String text, String separator) {
    List<String> parts = text.split(separator)
    Int index = 0
    while index < parts.length() {
        jwtAuthAppend(values, parts.get(index))
        index = index + 1
    }
}

static List<String> jwtAuthList(JsonValue? value) {
    List<String> result = []
    if value == null { return result }
    JsonValue actual = value as JsonValue
    if actual.isString() {
        String text = actual.asString() as String
        if text.indexOf(",") >= 0 {
            jwtAuthAppendText(result, text, ",")
        } else {
            jwtAuthAppendText(result, text, " ")
        }
        return result
    }
    if actual.isArray() {
        JsonArray array = actual.asArray() as JsonArray
        Int index = 0
        while index < array.length() {
            JsonValue item = array.get(index)
            if item.isString() { jwtAuthAppend(result, item.asString() as String) }
            index = index + 1
        }
    }
    return result
}

static String? jwtAuthScalar(JsonValue value) {
    if value.isNull() { return null }
    if value.isString() { return value.asString() as String }
    if value.isNumber() {
        JsonNumber number = value.asNumber() as JsonNumber
        return number.raw()
    }
    if value.isBool() {
        if value.asBool() as Bool { return "true" }
        return "false"
    }
    return null
}

static String? jwtAuthArrayText(JsonValue value) {
    if !value.isArray() { return null }
    JsonArray array = value.asArray() as JsonArray
    String text = ""
    Int index = 0
    while index < array.length() {
        String? item = jwtAuthScalar(array.get(index))
        if item != null {
            if text != "" { text = text + "," }
            text = text + (item as String)
        }
        index = index + 1
    }
    return text
}

static Map<String, String> jwtAuthClaims(JwtClaims claims) {
    Map<String, String> result = [:]
    JsonObject object = claims.toJson()
    List<String> keys = object.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        JsonValue? value = object.getOrNull(key)
        if value != null {
            JsonValue actual = value as JsonValue
            String? text = jwtAuthScalar(actual)
            if text == null && actual.isArray() { text = jwtAuthArrayText(actual) }
            if text != null { result.put(key, text as String) }
        }
        index = index + 1
    }
    return result
}
