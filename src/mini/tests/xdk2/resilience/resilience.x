package xdk2.resilience
import xdk.resilience
import xdk.errors
import xdk.tasks
import xdk.time

class RetryState {
    Int calls
    RetryState() { self.calls = 0 }
}

static Error ioError(String message) {
    return new BasicError(ErrorKind.Io, message)
}

static Int main() {
    Context context = Context.background()
    CircuitBreaker breaker = new CircuitBreaker(2, 40, 1)
    print("circuit-initial=" + circuitStateName(breaker.state()) + "," + str(breaker.failureCount()))
    Result<Int, Error> firstFailure = breaker.execute(context, () -> {
        return Err(ioError("boom"))
    })
    print("circuit-first=" + str(firstFailure.isErr()) + "," + circuitStateName(breaker.state()))
    Result<Int, Error> secondFailure = breaker.execute(context, () -> {
        return Err(ioError("boom"))
    })
    print("circuit-open=" + circuitStateName(breaker.state()) + "," + str(breaker.failureCount()))
    Result<Unit, Error> openRejected = breaker.tryAcquire(context)
    print("circuit-reject=" + str(openRejected.isErr()) + "," + str(openRejected.error().kind() == ErrorKind.Unavailable))
    sleepMs(60)
    print("circuit-half=" + circuitStateName(breaker.state()))
    Result<Unit, Error> probe = breaker.tryAcquire(context)
    Result<Unit, Error> secondProbe = breaker.tryAcquire(context)
    print("circuit-probe=" + str(probe.isOk()) + "," + str(secondProbe.isErr()))
    breaker.recordSuccess()
    print("circuit-closed=" + circuitStateName(breaker.state()) + "," + str(breaker.failureCount()))

    RateLimiter limiter = new RateLimiter(50.0, 1.0)
    print("rate-initial=" + str(limiter.tryAcquireMany(1)) + "," + str(limiter.tryAcquire()))
    TaskGroup rateGroup = TaskGroup.create(Context.background())
    Task<Int> rateTask = rateGroup.spawn(() -> {
        Result<Unit, Error> acquired = limiter.acquire(Context.background())
        if acquired.isErr() { return Ok(0) }
        return Ok(1)
    })
    sleepMs(40)
    Result<Int, TaskError> rateJoined = rateTask.join()
    print("rate-wait=" + str(rateJoined.isOk()) + "," + str(rateJoined.value()) + "," + str(limiter.availablePermits() >= 0.0))
    rateGroup.close()
    Context rateCancelled = Context.background()
    rateCancelled.cancel()
    Result<Unit, Error> rateCancelledResult = limiter.acquire(rateCancelled)
    print("rate-cancel=" + str(rateCancelledResult.error().kind() == ErrorKind.Cancelled))

    Bulkhead bulkhead = new Bulkhead(1)
    Result<Unit, Error> bulkFirst = bulkhead.acquire(context)
    print("bulk-first=" + str(bulkFirst.isOk()) + "," + str(bulkhead.tryAcquire()) + "," + str(bulkhead.inFlight()))
    TaskGroup bulkGroup = TaskGroup.create(Context.background())
    Task<Int> bulkWait = bulkGroup.spawn(() -> {
        Result<Unit, Error> acquired = bulkhead.acquire(Context.background())
        if acquired.isErr() { return Ok(0) }
        bulkhead.release()
        return Ok(1)
    })
    sleepMs(20)
    bulkhead.release()
    Result<Int, TaskError> bulkJoined = bulkWait.join()
    print("bulk-wait=" + str(bulkJoined.isOk()) + "," + str(bulkJoined.value()) + "," + str(bulkhead.inFlight()))
    bulkGroup.close()
    Result<Int, Error> bulkExecute = bulkhead.execute(context, () -> {
        return Ok(11)
    })
    print("bulk-execute=" + str(bulkExecute.isOk()) + "," + str(bulkExecute.value()))
    bulkhead.close()
    Result<Unit, Error> bulkClosed = bulkhead.acquire(context)
    print("bulk-closed=" + str(bulkClosed.error().kind() == ErrorKind.Unavailable) + "," + str(bulkhead.isClosed()))

    RetryPolicy retryPolicy = new RetryPolicy()
    retryPolicy = retryPolicy.withMaxAttempts(3).withInitialDelayMillis(1).withMaxDelayMillis(5).withJitter(0.0)
    RetryState retryState = new RetryState()
    Result<Int, Error> retry = Retry.execute(context, retryPolicy, () -> {
        retryState.calls = retryState.calls + 1
        if retryState.calls < 3 { return Err(new BasicError(ErrorKind.Network, "retry")) }
        return Ok(7)
    })
    print("retry-success=" + str(retry.isOk()) + "," + str(retry.value()) + "," + str(retryState.calls))
    RetryState exhaustedState = new RetryState()
    Result<Int, Error> exhausted = Retry.execute(context, retryPolicy, () -> {
        exhaustedState.calls = exhaustedState.calls + 1
        return Err(new BasicError(ErrorKind.Network, "retry"))
    })
    print("retry-exhausted=" + str(exhausted.isErr()) + "," + str(exhaustedState.calls))
    RetryState nonRetryState = new RetryState()
    Result<Int, Error> nonRetry = Retry.execute(context, retryPolicy, () -> {
        nonRetryState.calls = nonRetryState.calls + 1
        return Err(new BasicError(ErrorKind.InvalidArgument, "no retry"))
    })
    print("retry-nonretryable=" + str(nonRetry.isErr()) + "," + str(nonRetryState.calls))
    RetryPolicy jitterPolicy = new RetryPolicy()
    jitterPolicy = jitterPolicy.withInitialDelayMillis(100).withMaxDelayMillis(1000).withMultiplier(2.0).withJitter(0.5)
    print("retry-jitter=" + str(jitterPolicy.delayForJittered(1, 0.0)) + "," + str(jitterPolicy.delayForJittered(1, 1.0)))
    RetryState cancelRetryState = new RetryState()
    Result<Int, Error> cancelRetry = Retry.execute(context, retryPolicy, () -> {
        cancelRetryState.calls = cancelRetryState.calls + 1
        return Err(new BasicError(ErrorKind.Cancelled, "cancel"))
    })
    print("retry-cancel-error=" + str(cancelRetry.error().kind() == ErrorKind.Cancelled) + "," + str(cancelRetryState.calls))
    RetryState withState = new RetryState()
    Result<Int, Error> withResult = Retry.executeWith(context, retryPolicy, () -> {
        return 0.0
    }, () -> {
        withState.calls = withState.calls + 1
        return Err(new BasicError(ErrorKind.Network, "with"))
    }, (Error error) -> {
        return true
    })
    print("retry-with=" + str(withResult.isErr()) + "," + str(withState.calls))

    Result<Int, Error> fast = Timeout.execute(context, 100, (Context child) -> {
        return Ok(5)
    })
    print("timeout-fast=" + str(fast.isOk()) + "," + str(fast.value()))
    Result<Int, Error> slow = Timeout.execute(context, 20, (Context child) -> {
        sleepMs(80)
        return Ok(6)
    })
    print("timeout-slow=" + str(slow.isErr()) + "," + str(slow.error().kind() == ErrorKind.Timeout))
    Context timeoutCancelled = Context.background()
    timeoutCancelled.cancel()
    Result<Int, Error> timedCancel = Timeout.execute(timeoutCancelled, 100, (Context child) -> {
        return Ok(1)
    })
    print("timeout-cancel=" + str(timedCancel.error().kind() == ErrorKind.Cancelled))
    Result<Int, Error> invalidTimeout = Timeout.execute(context, 0, (Context child) -> {
        return Ok(1)
    })
    print("timeout-invalid=" + str(invalidTimeout.error().kind() == ErrorKind.InvalidArgument))

    Result<Int, Error> fallback = Fallback.execute(context, () -> {
        return Err(ioError("primary"))
    }, (Error error) -> {
        return Ok(9)
    })
    print("fallback=" + str(fallback.isOk()) + "," + str(fallback.value()))
    Result<Int, Error> primaryOnly = Fallback.execute(context, () -> {
        return Ok(3)
    }, (Error error) -> {
        return Ok(9)
    })
    print("fallback-primary=" + str(primaryOnly.value()))
    Result<Int, Error> fallbackCancelled = Fallback.execute(context, () -> {
        return Err(new BasicError(ErrorKind.Cancelled, "cancel"))
    }, (Error error) -> {
        return Ok(9)
    })
    print("fallback-cancel=" + str(fallbackCancelled.error().kind() == ErrorKind.Cancelled))
    Result<Int, Error> conditional = Fallback.executeIf(context, () -> {
        return Err(ioError("primary"))
    }, (Error error) -> {
        return Ok(10)
    }, (Error error) -> {
        return false
    })
    print("fallback-if=" + str(conditional.isErr()) + "," + str(conditional.error().kind() == ErrorKind.Io))
    return 0
}
