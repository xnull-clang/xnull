package xdk.auth
import xdk.errors
import xdk.tasks

enum AuthScheme {
    Unknown,
    Jwt,
    Bearer,
    ApiKey,
    Basic,
    Anonymous,
}

String authSchemeName(AuthScheme scheme) {
    if scheme == AuthScheme.Jwt { return "jwt" }
    if scheme == AuthScheme.Bearer { return "bearer" }
    if scheme == AuthScheme.ApiKey { return "api_key" }
    if scheme == AuthScheme.Basic { return "basic" }
    if scheme == AuthScheme.Anonymous { return "anonymous" }
    return "unknown"
}

Result<AuthScheme, Error> parseAuthScheme(String text) {
    if text == null { throw "parseAuthScheme: null" }
    String value = text.toLower()
    if value == "jwt" { return Ok(AuthScheme.Jwt) }
    if value == "bearer" { return Ok(AuthScheme.Bearer) }
    if value == "api_key" || value == "api-key" || value == "apikey" { return Ok(AuthScheme.ApiKey) }
    if value == "basic" { return Ok(AuthScheme.Basic) }
    if value == "anonymous" { return Ok(AuthScheme.Anonymous) }
    return Err(new BasicError(ErrorKind.InvalidArgument, "unsupported auth scheme: " + text))
}

static Error authError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

static Map<String, String> authCopyMap(Map<String, String> source) {
    Map<String, String> copy = [:]
    List<String> keys = source.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        copy.put(key, source.getOr(key, ""))
        index = index + 1
    }
    return copy
}

static Map<String, String> authEmptyMap() {
    Map<String, String> empty = [:]
    return empty
}

class Credential {
    final AuthScheme _scheme
    final String _value

    Credential(AuthScheme scheme, String value) {
        if scheme == null || scheme == AuthScheme.Unknown { throw "Credential: null scheme" }
        if value == null || value == "" { throw "Credential: empty value" }
        self._scheme = scheme
        self._value = value
    }

    AuthScheme scheme() { return self._scheme }
    String value() { return self._value }

    String describe() {
        String prefix = self._value
        if prefix.length() > 4 { prefix = prefix.substring(0, 4) }
        return authSchemeName(self._scheme) + "(len=" + str(self._value.length()) + ",prefix=" + prefix + ")"
    }

    static Credential jwt(String token) { return new Credential(AuthScheme.Jwt, token) }
    static Credential bearer(String token) { return new Credential(AuthScheme.Bearer, token) }
    static Credential apiKey(String value) { return new Credential(AuthScheme.ApiKey, value) }
}

class Principal {
    final String _subject
    final AuthScheme _scheme
    final List<String> _roles
    final List<String> _permissions
    final Map<String, String> _claims

    private Principal(String subject, AuthScheme scheme, List<String> roles,
                      List<String> permissions, Map<String, String> claims) {
        self._subject = subject
        self._scheme = scheme
        self._roles = roles
        self._permissions = permissions
        self._claims = claims
    }

    static Principal authenticated(String subject, AuthScheme scheme) {
        if subject == null || subject == "" { throw "Principal.authenticated: empty subject" }
        if scheme == null || scheme == AuthScheme.Unknown || scheme == AuthScheme.Anonymous {
            throw "Principal.authenticated: invalid scheme"
        }
        List<String> roles = []
        List<String> permissions = []
        return new Principal(subject, scheme, roles, permissions, authEmptyMap())
    }

    static Principal anonymous() {
        List<String> roles = []
        List<String> permissions = []
        return new Principal("", AuthScheme.Anonymous, roles, permissions, authEmptyMap())
    }

    String subject() { return self._subject }
    AuthScheme scheme() { return self._scheme }
    List<String> roles() { return self._roles.copy() }
    List<String> permissions() { return self._permissions.copy() }
    Map<String, String> claims() { return authCopyMap(self._claims) }
    Bool isAuthenticated() { return self._scheme != AuthScheme.Anonymous }

    Bool hasRole(String role) {
        if role == null { throw "Principal.hasRole: null" }
        Int index = 0
        while index < self._roles.length() {
            if self._roles.get(index) == role { return true }
            index = index + 1
        }
        return false
    }

    Bool hasPermission(String permission) {
        if permission == null { throw "Principal.hasPermission: null" }
        Int index = 0
        while index < self._permissions.length() {
            if self._permissions.get(index) == permission { return true }
            index = index + 1
        }
        return false
    }

    String? claimOrNull(String name) {
        if name == null { throw "Principal.claimOrNull: null" }
        if !self._claims.has(name) { return null }
        return self._claims.getOr(name, "")
    }

    Principal withRole(String role) {
        if role == null || role == "" { throw "Principal.withRole: empty" }
        List<String> roles = self._roles.copy()
        if !self.hasRole(role) { roles.push(role) }
        List<String> permissions = self._permissions.copy()
        return new Principal(self._subject, self._scheme, roles, permissions, authCopyMap(self._claims))
    }

    Principal withPermission(String permission) {
        if permission == null || permission == "" { throw "Principal.withPermission: empty" }
        List<String> roles = self._roles.copy()
        List<String> permissions = self._permissions.copy()
        if !self.hasPermission(permission) { permissions.push(permission) }
        return new Principal(self._subject, self._scheme, roles, permissions, authCopyMap(self._claims))
    }

    Principal withClaim(String name, String value) {
        if name == null || name == "" || value == null { throw "Principal.withClaim: invalid" }
        List<String> roles = self._roles.copy()
        List<String> permissions = self._permissions.copy()
        Map<String, String> claims = authCopyMap(self._claims)
        claims.put(name, value)
        return new Principal(self._subject, self._scheme, roles, permissions, claims)
    }

    Principal copy() {
        List<String> roles = self._roles.copy()
        List<String> permissions = self._permissions.copy()
        return new Principal(self._subject, self._scheme, roles, permissions, authCopyMap(self._claims))
    }

    String describe() {
        return self._subject + "(" + authSchemeName(self._scheme) + ",roles=" +
            str(self._roles.length()) + ",permissions=" + str(self._permissions.length()) + ")"
    }
}

protocol Authenticator {
    AuthScheme scheme();
    Result<Principal, Error> authenticate(Context context, Credential credential);
}

class AuthService {
    final List<Authenticator> _authenticators

    private AuthService(List<Authenticator> authenticators) {
        self._authenticators = authenticators
    }

    static AuthService create(List<Authenticator> authenticators) {
        if authenticators == null { throw "AuthService.create: null list" }
        List<Authenticator> copy = []
        Int index = 0
        while index < authenticators.length() {
            Authenticator candidate = authenticators.get(index)
            if candidate == null { throw "AuthService.create: null authenticator" }
            AuthScheme scheme = candidate.scheme()
            Int scan = 0
            while scan < copy.length() {
                if copy.get(scan).scheme() == scheme {
                    throw "AuthService.create: duplicate scheme: " + authSchemeName(scheme)
                }
                scan = scan + 1
            }
            copy.push(candidate)
            index = index + 1
        }
        return new AuthService(copy)
    }

    Result<Principal, Error> authenticate(Context context, Credential credential) {
        if context == null || credential == null { throw "AuthService.authenticate: null argument" }
        if context.isCancelled() {
            return Err(authError(ErrorKind.Cancelled, "authentication cancelled"))
        }
        Int index = 0
        while index < self._authenticators.length() {
            Authenticator candidate = self._authenticators.get(index)
            if candidate.scheme() == credential.scheme() {
                return candidate.authenticate(context, credential)
            }
            index = index + 1
        }
        return Err(authError(ErrorKind.Unsupported,
            "no authenticator for scheme: " + authSchemeName(credential.scheme())))
    }

    List<Authenticator> authenticators() { return self._authenticators.copy() }
}
