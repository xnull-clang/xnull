package app.authhttp
import xdk.auth
import xdk.errors
import xdk.jwt
import xdk.net.http
import xdk.net.uri
import xdk.tasks
import generated.AuthGenerated

static Error businessFailure() {
    return new BasicError(ErrorKind.Io, "boom")
}

class UserApi {
    Result<String, Error> adminOnly() { return Ok("admin") }
    Result<String, Error> failing() { return Err(businessFailure()) }
    Result<String, Error> publicEcho() { return Ok("public") }
}

static AuthService authService() {
    Bytes secret = Bytes.fromString("auth-http-secret")
    List<Authenticator> values = []
    values.push(JwtAuthenticator.forSecret(secret))
    return AuthService.create(values)
}

static Int statusOf(Result<String, Error> result) {
    if result.isOk() { return 200 }
    if result.error().kind() == ErrorKind.PermissionDenied { return 403 }
    return 500
}

static Int handle(HttpRequest request, UserApi api) {
    if request.uri().path() == "/public" {
        Result<String, Error> publicResult = api.publicEcho()
        if publicResult.isOk() { return 200 }
        return 500
    }
    String? authorization = request.headers().getOrNull("authorization")
    if authorization == null { return 401 }
    Result<Credential, Error> credential = AuthHeaders.bearer(authorization as String)
    if credential.isErr() { return 401 }
    AuthService service = authService()
    Result<Principal, Error> principal = service.authenticate(Context.background(), credential.value())
    if principal.isErr() { return 401 }
    if request.uri().path() == "/fail" {
        return statusOf(UserApi_failingAuthorized(api, principal.value()))
    }
    return statusOf(UserApi_adminOnlyAuthorized(api, principal.value()))
}

static List<String> adminRoles() {
    List<String> roles = []
    roles.push("admin")
    return roles
}

static List<String> noRoles() {
    List<String> roles = []
    return roles
}

static String makeToken(String secretText, String subject, List<String> roles, Long expiresAt) {
    JwtClaims claims = new JwtClaims()
    claims.set("sub", Json.string(subject))
    JsonValue roleValue = Json.array()
    JsonArray roleArray = roleValue.asArray() as JsonArray
    Int index = 0
    while index < roles.length() {
        roleArray.add(Json.string(roles.get(index)))
        index = index + 1
    }
    claims.set("roles", roleValue)
    claims.set("exp", Json.number(str(expiresAt)))
    JwtHeader header = new JwtHeader(JwtAlgorithm.Hs256)
    return Jwt.encode(header, claims, Bytes.fromString(secretText)).value()
}

static HttpRequest requestFor(String path, String? authorization) {
    HttpRequest request = new HttpRequest(HttpMethod.Get, Uri.parse("http://localhost" + path).value())
    if authorization != null {
        request = request.withHeader("Authorization", authorization as String)
    }
    return request
}

static Int main() {
    UserApi api = new UserApi()
    Long now = nowWall() / 1000
    String adminToken = makeToken("auth-http-secret", "admin", adminRoles(), now + 300)
    String noRoleToken = makeToken("auth-http-secret", "user", noRoles(), now + 300)
    String expiredToken = makeToken("auth-http-secret", "admin", adminRoles(), now - 100)
    String badToken = makeToken("wrong-secret", "admin", adminRoles(), now + 300)

    print("http=" + str(handle(requestFor("/admin", "Bearer " + adminToken), api)) + "," +
        str(handle(requestFor("/admin", null), api)) + "," +
        str(handle(requestFor("/admin", "Basic abc"), api)) + "," +
        str(handle(requestFor("/admin", "Bearer " + noRoleToken), api)) + "," +
        str(handle(requestFor("/admin", "Bearer " + expiredToken), api)) + "," +
        str(handle(requestFor("/admin", "Bearer " + badToken), api)))
    print("public=" + str(handle(requestFor("/public", null), api)) + "," +
        str(handle(requestFor("/public", "Bearer " + badToken), api)))
    print("fail=" + str(handle(requestFor("/fail", "Bearer " + adminToken), api)))
    print("headers=" + str(AuthHeaders.bearer("Bearer " + adminToken).isOk()) + "," +
        str(AuthHeaders.bearer("bearer " + adminToken).isOk()) + "," +
        str(AuthHeaders.bearer("Token " + adminToken).isErr()) + "," +
        str(AuthHeaders.bearer("Bearer   ").isErr()) + "," +
        AuthHeaders.apiKey("key").describe())
    return 0
}
