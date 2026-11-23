package app.svc
import xdk.resilience
import xdk.errors
import xdk.time
import generated.ResilienceGenerated

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
    Result<Int, Error> flaky(Int succeedAt) {
        self.attempts = self.attempts + 1
        if self.attempts < succeedAt {
            return Err(networkError())
        }
        return Ok(self.attempts)
    }
    Result<Int, Error> slow(Bool sleepy) {
        if sleepy { sleepMs(80) }
        return Ok(7)
    }
    Result<Int, Error> guarded(Bool fail) {
        self.guardedCalls = self.guardedCalls + 1
        if fail { return Err(guardedError()) }
        return Ok(42)
    }
    Result<Int, Error> limited() {
        return Ok(5)
    }
}

static Int main() {
    Context context = Context.background()
    Service service = new Service()
    Result<Int, Error> retry = Service_flakyRetry(service, context, 3)
    print("retry-success=" + str(retry.isOk()) + "," + str(retry.value()) + "," + str(service.attempts))
    Service exhaustedService = new Service()
    Result<Int, Error> exhausted = Service_flakyRetry(exhaustedService, context, 99)
    print("retry-exhausted=" + str(exhausted.isErr()) + "," + errorKindName(exhausted.error().kind()) + "," + str(exhaustedService.attempts))

    Result<Int, Error> slow = Service_slowTimeout(service, context, true)
    print("timeout-slow=" + str(slow.isErr()) + "," + errorKindName(slow.error().kind()))
    Result<Int, Error> fast = Service_slowTimeout(service, context, false)
    print("timeout-fast=" + str(fast.isOk()) + "," + str(fast.value()))

    CircuitBreaker breaker = new CircuitBreaker(2, 30, 1)
    Result<Int, Error> firstCircuit = Service_guardedCircuit(service, context, breaker, true)
    Result<Int, Error> secondCircuit = Service_guardedCircuit(service, context, breaker, true)
    Result<Int, Error> rejected = Service_guardedCircuit(service, context, breaker, true)
    print("circuit-open=" + str(firstCircuit.isErr()) + "," + str(secondCircuit.isErr()) + "," +
        str(rejected.error().kind() == ErrorKind.Unavailable) + "," + str(service.guardedCalls))
    sleepMs(50)
    Result<Int, Error> probe = Service_guardedCircuit(service, context, breaker, false)
    print("circuit-probe=" + str(probe.isOk()) + "," + str(probe.value()) + "," + circuitStateName(breaker.state()))

    RateLimiter limiter = new RateLimiter(1.0, 1.0)
    Result<Int, Error> rateFirst = Service_limitedRate(service, context, limiter)
    Context rateCancelled = Context.background()
    rateCancelled.cancel()
    Result<Int, Error> rateSecond = Service_limitedRate(service, rateCancelled, limiter)
    print("rate-first=" + str(rateFirst.isOk()) + "," + str(rateFirst.value()))
    print("rate-cancel=" + errorKindName(rateSecond.error().kind()))
    return 0
}
