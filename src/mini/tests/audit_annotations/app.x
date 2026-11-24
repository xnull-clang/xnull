package app.audit
import xdk.audit
import xdk.errors

static Error auditFailure() {
    return new BasicError(ErrorKind.Network, "audit failure")
}

class Service {
    Int successes
    Int failures
    Service() {
        self.successes = 0
        self.failures = 0
    }

    @Audited("user.login")
    Result<Int, Error> login(Int id) {
        self.successes = self.successes + 1
        return Ok(id)
    }

    @Audited("user.fail")
    Result<Int, Error> fail(Int id) {
        self.failures = self.failures + 1
        return Err(auditFailure())
    }
}

static Int main() { return 0 }
