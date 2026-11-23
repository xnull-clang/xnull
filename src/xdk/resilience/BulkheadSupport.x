package xdk.resilience
import xdk.errors
import xdk.runtime
import xdk.tasks
import xdk.time

class Bulkhead {
    final Int _maxConcurrent
    final RuntimeMonitor _monitor
    Int _inFlight
    Bool _closed

    Bulkhead(Int maxConcurrent) {
        if maxConcurrent < 1 { throw "Bulkhead: maxConcurrent < 1" }
        self._maxConcurrent = maxConcurrent
        self._monitor = new RuntimeMonitor()
        self._inFlight = 0
        self._closed = false
    }

    Int maxConcurrent() { return self._maxConcurrent }

    Int inFlight() {
        self._monitor.enter()
        Int result = self._inFlight
        self._monitor.exit()
        return result
    }

    Bool isClosed() {
        self._monitor.enter()
        Bool result = self._closed
        self._monitor.exit()
        return result
    }

    Result<Unit, Error> acquire(Context context) {
        if context == null { throw "Bulkhead.acquire: null context" }
        self._monitor.enter()
        while true {
            if self._closed {
                self._monitor.exit()
                return Err(resilienceError(ErrorKind.Unavailable, "bulkhead is closed"))
            }
            if context.isCancelled() {
                self._monitor.exit()
                return Err(resilienceError(ErrorKind.Cancelled, "bulkhead cancelled"))
            }
            if self._inFlight < self._maxConcurrent {
                self._inFlight = self._inFlight + 1
                self._monitor.exit()
                return Ok()
            }
            Bool woken = self._monitor.waitContext(context)
            if !woken {
                self._monitor.exit()
                return Err(resilienceError(ErrorKind.Cancelled, "bulkhead cancelled"))
            }
        }
    }

    Bool tryAcquire() {
        self._monitor.enter()
        if self._closed || self._inFlight >= self._maxConcurrent {
            self._monitor.exit()
            return false
        }
        self._inFlight = self._inFlight + 1
        self._monitor.exit()
        return true
    }

    Bool release() {
        self._monitor.enter()
        if self._inFlight <= 0 {
            self._monitor.exit()
            return false
        }
        self._inFlight = self._inFlight - 1
        self._monitor.notifyAll()
        self._monitor.exit()
        return true
    }

    Result<T, Error> execute<T>(Context context, Result<T, Error>() operation) {
        if context == null { throw "Bulkhead.execute: null context" }
        Result<Unit, Error> acquired = self.acquire(context)
        if acquired.isErr() { return Err(acquired.error()) }
        Result<T, Error> result = operation()
        self.release()
        return result
    }

    Void close() {
        self._monitor.enter()
        self._closed = true
        self._monitor.notifyAll()
        self._monitor.exit()
    }

    Result<Unit, Error> awaitIdle(Context context) {
        if context == null { throw "Bulkhead.awaitIdle: null context" }
        self._monitor.enter()
        while self._inFlight > 0 {
            if context.isCancelled() {
                self._monitor.exit()
                return Err(resilienceError(ErrorKind.Cancelled, "bulkhead await cancelled"))
            }
            Bool woken = self._monitor.waitContext(context)
            if !woken {
                self._monitor.exit()
                return Err(resilienceError(ErrorKind.Cancelled, "bulkhead await cancelled"))
            }
        }
        self._monitor.exit()
        return Ok()
    }

    Result<Unit, Error> closeAndAwait(Context context) {
        self.close()
        return self.awaitIdle(context)
    }
}
