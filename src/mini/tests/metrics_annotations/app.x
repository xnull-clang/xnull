package app.metrics
import xdk.metrics
import xdk.errors
import xdk.time

static Error runFailure() {
    return new BasicError(ErrorKind.Network, "operation failed")
}

class Service {
    Int successes
    Int failures
    Service() {
        self.successes = 0
        self.failures = 0
    }

    @Metered("op.success")
    Result<Int, Error> success(Int id) {
        self.successes = self.successes + 1
        sleepMs(5)
        return Ok(id)
    }

    @Metered("", "us")
    Result<Int, Error> failure(Int id) {
        self.failures = self.failures + 1
        sleepMs(5)
        return Err(runFailure())
    }
}

static Int main() { return 0 }
