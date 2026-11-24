package app.authannotations
import xdk.auth
import xdk.errors

static Error businessFailure() {
    return new BasicError(ErrorKind.Io, "business failure")
}

@Auth("jwt")
class UserApi {
    Int calls
    UserApi() { self.calls = 0 }

    @RequireRole("admin")
    Result<Int, Error> roleOnly(Int id) {
        self.calls = self.calls + 1
        return Ok(id)
    }

    @RequirePermission("user:read")
    Result<Int, Error> permissionOnly(Int id) {
        self.calls = self.calls + 1
        return Ok(id)
    }

    @RequireClaim("tenant", "acme")
    Result<Int, Error> claimOnly(Int id) {
        self.calls = self.calls + 1
        return Ok(id)
    }

    @AllowAnonymous
    Result<Int, Error> open(Int id) {
        self.calls = self.calls + 1
        return Ok(id)
    }

    @RequireRole("admin")
    @RequirePermission("user:read")
    Result<Int, Error> combined(Int id) {
        self.calls = self.calls + 1
        return Ok(id)
    }

    @Auth("api_key")
    @RequireRole("admin")
    Result<Int, Error> apiKeyOnly(Int id) {
        self.calls = self.calls + 1
        return Ok(id)
    }

    @RequireRole("admin")
    Result<Int, Error> businessFail(Int id) {
        self.calls = self.calls + 1
        return Err(businessFailure())
    }
}

static Int main() { return 0 }
