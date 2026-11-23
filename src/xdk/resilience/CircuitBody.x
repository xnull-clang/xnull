package xdk.resilience
import xdk.errors
import xdk.runtime
import xdk.tasks
import xdk.time

class CircuitBreaker {
    final Int _failureThreshold
    final Long _openMillis
    final Int _halfOpenMaxCalls
    final RuntimeMonitor _monitor
    CircuitState _state
    Int _failureCount
    Long _openedAtMono
    Int _halfOpenInFlight

    CircuitBreaker(Int failureThreshold, Long openMillis, Int halfOpenMaxCalls) {
        if failureThreshold < 1 || openMillis < 1 || halfOpenMaxCalls < 1 {
            throw "CircuitBreaker: invalid configuration"
        }
        self._failureThreshold = failureThreshold
        self._openMillis = openMillis
        self._halfOpenMaxCalls = halfOpenMaxCalls
        self._monitor = new RuntimeMonitor()
        self._state = CircuitState.Closed
        self._failureCount = 0
        self._openedAtMono = 0
        self._halfOpenInFlight = 0
    }

    CircuitBreaker(Int failureThreshold) {
        if failureThreshold < 1 { throw "CircuitBreaker: invalid threshold" }
        self._failureThreshold = failureThreshold
        self._openMillis = 30000
        self._halfOpenMaxCalls = 1
        self._monitor = new RuntimeMonitor()
        self._state = CircuitState.Closed
        self._failureCount = 0
        self._openedAtMono = 0
        self._halfOpenInFlight = 0
    }

    Int failureThreshold() { return self._failureThreshold }
    Long openMillis() { return self._openMillis }
    Int halfOpenMaxCalls() { return self._halfOpenMaxCalls }

    Void _refresh() {
        if self._state == CircuitState.Open && nowMono() - self._openedAtMono >= self._openMillis {
            self._state = CircuitState.HalfOpen
            self._failureCount = 0
            self._halfOpenInFlight = 0
            self._monitor.notifyAll()
        }
    }

    CircuitState state() {
        self._monitor.enter()
        self._refresh()
        CircuitState result = self._state
        self._monitor.exit()
        return result
    }

    Int failureCount() {
        self._monitor.enter()
        Int result = self._failureCount
        self._monitor.exit()
        return result
    }

    Void reset() {
        self._monitor.enter()
        self._state = CircuitState.Closed
        self._failureCount = 0
        self._openedAtMono = 0
        self._halfOpenInFlight = 0
        self._monitor.notifyAll()
        self._monitor.exit()
    }

    Void trip() {
        self._monitor.enter()
        self._state = CircuitState.Open
        self._failureCount = self._failureThreshold
        self._openedAtMono = nowMono()
        self._halfOpenInFlight = 0
        self._monitor.notifyAll()
        self._monitor.exit()
    }

    Result<Unit, Error> tryAcquire(Context context) {
        if context == null { throw "CircuitBreaker.tryAcquire: null context" }
        self._monitor.enter()
        if context.isCancelled() {
            self._monitor.exit()
            return Err(resilienceError(ErrorKind.Cancelled, "circuit breaker cancelled"))
        }
        self._refresh()
        if self._state == CircuitState.Open {
            self._monitor.exit()
            return Err(resilienceError(ErrorKind.Unavailable, "circuit breaker is open"))
        }
        if self._state == CircuitState.HalfOpen {
            if self._halfOpenInFlight >= self._halfOpenMaxCalls {
                self._monitor.exit()
                return Err(resilienceError(ErrorKind.Unavailable, "circuit breaker half-open is busy"))
            }
            self._halfOpenInFlight = self._halfOpenInFlight + 1
        }
        self._monitor.exit()
        return Ok()
    }

    Void _releaseHalfOpen() {
        self._monitor.enter()
        if self._state == CircuitState.HalfOpen && self._halfOpenInFlight > 0 {
            self._halfOpenInFlight = self._halfOpenInFlight - 1
        }
        self._monitor.exit()
    }

    Void recordSuccess() {
        self._monitor.enter()
        if self._state == CircuitState.HalfOpen {
            self._state = CircuitState.Closed
            self._failureCount = 0
            self._halfOpenInFlight = 0
            self._openedAtMono = 0
            self._monitor.notifyAll()
        } else if self._state == CircuitState.Closed {
            self._failureCount = 0
        }
        self._monitor.exit()
    }

    Void recordFailure() {
        self._monitor.enter()
        if self._state == CircuitState.HalfOpen {
            self._state = CircuitState.Open
            self._openedAtMono = nowMono()
            self._halfOpenInFlight = 0
            self._monitor.notifyAll()
        } else if self._state == CircuitState.Closed {
            self._failureCount = self._failureCount + 1
            if self._failureCount >= self._failureThreshold {
                self._state = CircuitState.Open
                self._openedAtMono = nowMono()
                self._failureCount = self._failureThreshold
                self._monitor.notifyAll()
            }
        }
        self._monitor.exit()
    }

    Result<T, Error> execute<T>(Context context, Result<T, Error>() operation) {
        if context == null { throw "CircuitBreaker.execute: null context" }
        Result<Unit, Error> permit = self.tryAcquire(context)
        if permit.isErr() { return Err(permit.error()) }
        Result<T, Error> result = operation()
        if result.isOk() { self.recordSuccess(); return result }
        if resilienceCancelled(result.error()) {
            self._releaseHalfOpen()
        } else {
            self.recordFailure()
        }
        return result
    }
}
