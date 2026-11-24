package app.authhttp
import xdk.auth
import xdk.errors
import xdk.jwt
import xdk.net.http

static Error businessFailure() {
    return new BasicError(ErrorKind.Io, "boom")
}

@Auth("jwt")
class UserApi {
    @RequireRole("admin")
    Result<String, Error> adminOnly() { return Ok("admin") }

    @RequireRole("admin")
    Result<String, Error> failing() { return Err(businessFailure()) }

    @AllowAnonymous
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

static Int main() { return 0 }
