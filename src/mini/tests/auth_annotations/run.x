package app.authannotations
import xdk.auth
import xdk.errors
import generated.AuthGenerated

static Error businessFailure() {
    return new BasicError(ErrorKind.Io, "business failure")
}

class UserApi {
    Int calls
    UserApi() { self.calls = 0 }
    Result<Int, Error> roleOnly(Int id) { self.calls = self.calls + 1; return Ok(id) }
    Result<Int, Error> permissionOnly(Int id) { self.calls = self.calls + 1; return Ok(id) }
    Result<Int, Error> claimOnly(Int id) { self.calls = self.calls + 1; return Ok(id) }
    Result<Int, Error> open(Int id) { self.calls = self.calls + 1; return Ok(id) }
    Result<Int, Error> combined(Int id) { self.calls = self.calls + 1; return Ok(id) }
    Result<Int, Error> apiKeyOnly(Int id) { self.calls = self.calls + 1; return Ok(id) }
    Result<Int, Error> businessFail(Int id) { self.calls = self.calls + 1; return Err(businessFailure()) }
}

static Principal admin() {
    Principal principal = Principal.authenticated("alice", AuthScheme.Jwt)
    principal = principal.withRole("admin").withPermission("user:read").withClaim("tenant", "acme")
    return principal
}

static String failureMessage(Result<Int, Error> result) {
    return result.error().describe()
}

static Int main() {
    UserApi api = new UserApi()
    Principal adminPrincipal = admin()
    print("role=" + str(UserApi_roleOnlyAuthorized(api, adminPrincipal, 1).isOk()) + "," +
        str(UserApi_permissionOnlyAuthorized(api, adminPrincipal, 1).isOk()) + "," +
        str(UserApi_claimOnlyAuthorized(api, adminPrincipal, 1).isOk()) + "," +
        str(UserApi_combinedAuthorized(api, adminPrincipal, 1).isOk()) + "," +
        str(api.open(1).isOk()) + "," + str(api.calls))

    Result<Int, Error> nullPrincipal = UserApi_roleOnlyAuthorized(api, null, 2)
    Result<Int, Error> anonymous = UserApi_roleOnlyAuthorized(api, Principal.anonymous(), 2)
    print("auth=" + errorKindName(nullPrincipal.error().kind()) + "," +
        str(failureMessage(nullPrincipal).indexOf("authentication required") >= 0) + "," +
        errorKindName(anonymous.error().kind()))

    Principal apiKey = Principal.authenticated("service", AuthScheme.ApiKey).withRole("admin")
    Result<Int, Error> wrongScheme = UserApi_roleOnlyAuthorized(api, apiKey, 3)
    Result<Int, Error> apiKeyOk = UserApi_apiKeyOnlyAuthorized(api, apiKey, 3)
    Result<Int, Error> apiKeyWrong = UserApi_apiKeyOnlyAuthorized(api, adminPrincipal, 3)
    print("scheme=" + errorKindName(wrongScheme.error().kind()) + "," +
        str(failureMessage(wrongScheme).indexOf("authentication scheme required: jwt") >= 0) + "," +
        str(apiKeyOk.isOk()) + "," + errorKindName(apiKeyWrong.error().kind()))

    Principal noRole = Principal.authenticated("bob", AuthScheme.Jwt).withPermission("user:read")
    Result<Int, Error> missingRole = UserApi_roleOnlyAuthorized(api, noRole, 4)
    Principal noPermission = Principal.authenticated("bob", AuthScheme.Jwt).withRole("admin")
    Result<Int, Error> missingPermission = UserApi_permissionOnlyAuthorized(api, noPermission, 4)
    Result<Int, Error> missingClaim = UserApi_claimOnlyAuthorized(api, noPermission, 4)
    Principal wrongClaim = noPermission.withClaim("tenant", "other")
    Result<Int, Error> wrongClaimResult = UserApi_claimOnlyAuthorized(api, wrongClaim, 4)
    print("missing=" + errorKindName(missingRole.error().kind()) + "," +
        str(failureMessage(missingRole).indexOf("missing role: admin") >= 0) + "," +
        str(failureMessage(missingPermission).indexOf("missing permission: user:read") >= 0) + "," +
        str(failureMessage(missingClaim).indexOf("missing claim: tenant") >= 0) + "," +
        str(failureMessage(wrongClaimResult).indexOf("missing claim: tenant") >= 0))

    Result<Int, Error> combined = UserApi_combinedAuthorized(api, noPermission.withPermission("user:read"), 5)
    Result<Int, Error> business = UserApi_businessFailAuthorized(api, adminPrincipal, 5)
    print("and=" + str(combined.isOk()) + "," + errorKindName(business.error().kind()) + "," +
        str(failureMessage(business).indexOf("business failure") >= 0))
    return 0
}
