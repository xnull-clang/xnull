package app.svc
import xdk.resilience
import xdk.errors
import xdk.time

static Error networkError() {
    return new BasicError(ErrorKind.Network, "retry")
}

static Error guardedError() {
    return new BasicError(ErrorKind.Io, "guarded")
}

class Service {
    Int attempts
    Int guardedCalls
    Service() {
        self.attempts = 0
        self.guardedCalls = 0
    }

    @Retryable(3, 1)
    Result<Int, Error> flaky(Int succeedAt) {
        self.attempts = self.attempts + 1
        if self.attempts < succeedAt {
            return Err(networkError())
        }
        return Ok(self.attempts)
    }

    @TimeoutPolicy(20)
    Result<Int, Error> slow(Bool sleepy) {
        if sleepy { sleepMs(80) }
        return Ok(7)
    }

    @CircuitBreakerPolicy("svc", 2)
    Result<Int, Error> guarded(Bool fail) {
        self.guardedCalls = self.guardedCalls + 1
        if fail { return Err(guardedError()) }
        return Ok(42)
    }

    @RateLimit("svc", 1, 1000)
    Result<Int, Error> limited() {
        return Ok(5)
    }
}

static Int main() { return 0 }
