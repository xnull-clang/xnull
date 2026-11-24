package xdk2.auth
import xdk.auth
import xdk.errors
import xdk.tasks

static Error authFailure() {
    return new BasicError(ErrorKind.PermissionDenied, "bad credential")
}

class FakeAuthenticator implements Authenticator {
    final AuthScheme _scheme
    final Bool _fail

    FakeAuthenticator(AuthScheme scheme, Bool fail) {
        self._scheme = scheme
        self._fail = fail
    }

    AuthScheme scheme() { return self._scheme }

    Result<Principal, Error> authenticate(Context context, Credential credential) {
        if self._fail { return Err(authFailure()) }
        Principal principal = Principal.authenticated("user-" + authSchemeName(self._scheme), self._scheme)
        principal = principal.withRole("reader").withPermission("read")
        principal = principal.withClaim("credential", credential.value())
        return Ok(principal)
    }
}

static Int main() {
    print("scheme=" + authSchemeName(AuthScheme.Jwt) + "," + authSchemeName(AuthScheme.ApiKey) + "," +
        authSchemeName(AuthScheme.Anonymous) + "," + str(parseAuthScheme("BEARER").isOk()) + "," +
        str(parseAuthScheme("api-key").isOk()) + "," + str(parseAuthScheme("none").isErr()))

    Credential jwt = Credential.jwt("abcdefghijklmnop")
    Credential bearer = Credential.bearer("token-value")
    Credential api = Credential.apiKey("key-value")
    print("credential=" + authSchemeName(jwt.scheme()) + "," + authSchemeName(bearer.scheme()) + "," +
        authSchemeName(api.scheme()) + "," + jwt.describe() + "," + str(jwt.describe().indexOf("abcdefghijklmnop") < 0))

    Principal principal = Principal.authenticated("alice", AuthScheme.Jwt)
    principal = principal.withRole("admin").withRole("admin").withPermission("read").withPermission("write")
    principal = principal.withClaim("tenant", "t1")
    Principal copy = principal.copy()
    Map<String, String> claims = copy.claims()
    claims.put("tenant", "changed")
    print("principal=" + principal.subject() + "," + authSchemeName(principal.scheme()) + "," +
        str(principal.isAuthenticated()) + "," + str(principal.roles().length()) + "," +
        str(principal.permissions().length()) + "," + str(principal.hasRole("admin")) + "," +
        str(principal.hasPermission("read")) + "," + str(principal.claimOrNull("tenant")) + "," +
        str(principal.claims().getOr("tenant", "")))
    Principal anonymous = Principal.anonymous()
    print("anonymous=" + str(anonymous.isAuthenticated()) + "," + anonymous.subject() + "," +
        str(anonymous.roles().length()) + "," + str(anonymous.claimOrNull("x") == null))

    List<Authenticator> authenticators = []
    authenticators.push(new FakeAuthenticator(AuthScheme.Jwt, false))
    authenticators.push(new FakeAuthenticator(AuthScheme.ApiKey, false))
    AuthService service = AuthService.create(authenticators)
    Context context = Context.background()
    Result<Principal, Error> authenticated = service.authenticate(context, jwt)
    print("service=" + str(authenticated.isOk()) + "," + authenticated.value().subject() + "," +
        str(authenticated.value().hasRole("reader")) + "," + str(service.authenticators().length()))
    Result<Principal, Error> unsupported = service.authenticate(context, bearer)
    print("unsupported=" + str(unsupported.isErr()) + "," + errorKindName(unsupported.error().kind()))
    Context cancelled = Context.background()
    cancelled.cancel()
    Result<Principal, Error> cancelledResult = service.authenticate(cancelled, jwt)
    print("cancelled=" + errorKindName(cancelledResult.error().kind()))

    List<Authenticator> failing = []
    failing.push(new FakeAuthenticator(AuthScheme.Jwt, true))
    AuthService failingService = AuthService.create(failing)
    Result<Principal, Error> failure = failingService.authenticate(context, jwt)
    print("failure=" + errorKindName(failure.error().kind()) + "," + failure.error().describe())

    List<Authenticator> snapshot = service.authenticators()
    snapshot.clear()
    print("snapshot=" + str(service.authenticators().length()))
    return 0
}
