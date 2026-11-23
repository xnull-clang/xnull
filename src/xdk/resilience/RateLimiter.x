package xdk.resilience
import xdk.errors
import xdk.runtime
import xdk.tasks
import xdk.time

class RateLimiter {
    final Double _permitsPerSecond
    final Double _capacity
    final RuntimeMonitor _monitor
    Double _tokens
    Long _lastRefillMono

    RateLimiter(Double permitsPerSecond, Double burstCapacity) {
        if !(permitsPerSecond > 0.0) { throw "RateLimiter: permitsPerSecond must be positive" }
        if !(burstCapacity >= 1.0) { throw "RateLimiter: burstCapacity must be at least 1" }
        self._permitsPerSecond = permitsPerSecond
        self._capacity = burstCapacity
        self._tokens = burstCapacity
        self._lastRefillMono = nowMono()
        self._monitor = new RuntimeMonitor()
    }

    RateLimiter(Double permitsPerSecond) {
        if !(permitsPerSecond > 0.0) { throw "RateLimiter: permitsPerSecond must be positive" }
        self._permitsPerSecond = permitsPerSecond
        self._capacity = 1.0
        self._tokens = 1.0
        self._lastRefillMono = nowMono()
        self._monitor = new RuntimeMonitor()
    }

    Double permitsPerSecond() { return self._permitsPerSecond }
    Double burstCapacity() { return self._capacity }

    Void _refill() {
        Long now = nowMono()
        Long elapsed = now - self._lastRefillMono
        if elapsed > 0 {
            Double added = (elapsed as Double) * self._permitsPerSecond / 1000.0
            self._tokens = self._tokens + added
            if self._tokens > self._capacity { self._tokens = self._capacity }
            self._lastRefillMono = now
        }
    }

    Double availablePermits() {
        self._monitor.enter()
        self._refill()
        Double result = self._tokens
        self._monitor.exit()
        return result
    }

    Result<Unit, Error> acquire(Context context) {
        return self.acquireMany(context, 1)
    }

    Result<Unit, Error> acquireMany(Context context, Int permits) {
        if context == null { throw "RateLimiter.acquireMany: null context" }
        if permits < 1 { throw "RateLimiter.acquireMany: permits < 1" }
        if (permits as Double) > self._capacity {
            return Err(resilienceError(ErrorKind.InvalidArgument, "permits exceed burst capacity"))
        }
        while true {
            if context.isCancelled() {
                return Err(resilienceError(ErrorKind.Cancelled, "rate limiter cancelled"))
            }
            self._monitor.enter()
            self._refill()
            if self._tokens >= (permits as Double) {
                self._tokens = self._tokens - (permits as Double)
                self._monitor.notifyAll()
                self._monitor.exit()
                return Ok()
            }
            Double missing = (permits as Double) - self._tokens
            Long waitMillis = ((missing * 1000.0 / self._permitsPerSecond) as Long) + 1
            if waitMillis < 1 { waitMillis = 1 }
            self._monitor.exit()
            Result<Unit, Error> slept = sleepContext(context, durationOfMillis(waitMillis))
            if slept.isErr() {
                return Err(resilienceError(ErrorKind.Cancelled, "rate limiter cancelled"))
            }
        }
    }

    Bool tryAcquire() {
        return self.tryAcquireMany(1)
    }

    Bool tryAcquireMany(Int permits) {
        if permits < 1 { throw "RateLimiter.tryAcquireMany: permits < 1" }
        if (permits as Double) > self._capacity { return false }
        self._monitor.enter()
        self._refill()
        if self._tokens < (permits as Double) {
            self._monitor.exit()
            return false
        }
        self._tokens = self._tokens - (permits as Double)
        self._monitor.notifyAll()
        self._monitor.exit()
        return true
    }
}
