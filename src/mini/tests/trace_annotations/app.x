package app.trace
import xdk.trace
import xdk.errors

static Error traceFailure() {
    return new BasicError(ErrorKind.Timeout, "operation timed out")
}

class Service {
    Int successes
    Int failures
    Service() {
        self.successes = 0
        self.failures = 0
    }

    @Traced("custom.success")
    Result<Int, Error> success(Int id) {
        self.successes = self.successes + 1
        return Ok(id)
    }

    @Traced
    Result<Int, Error> failure(Int id) {
        self.failures = self.failures + 1
        return Err(traceFailure())
    }
}

static Int main() { return 0 }
