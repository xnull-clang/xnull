package xdk.resilience
import xdk.errors
import xdk.runtime
import xdk.tasks
import xdk.time

class Fallback {
    private Fallback() { }

    static Result<T, Error> execute<T>(Context context, Result<T, Error>() primary,
                                       Result<T, Error>(Error) fallback) {
        if context == null { throw "Fallback.execute: null context" }
        if context.isCancelled() { return Err(resilienceError(ErrorKind.Cancelled, "fallback cancelled")) }
        Result<T, Error> result = primary()
        if result.isOk() { return result }
        if resilienceCancelled(result.error()) { return result }
        if context.isCancelled() { return Err(resilienceError(ErrorKind.Cancelled, "fallback cancelled")) }
        return fallback(result.error())
    }

    static Result<T, Error> executeIf<T>(Context context, Result<T, Error>() primary,
                                         Result<T, Error>(Error) fallback,
                                         Bool(Error) shouldFallback) {
        if context == null { throw "Fallback.executeIf: null context" }
        if context.isCancelled() { return Err(resilienceError(ErrorKind.Cancelled, "fallback cancelled")) }
        Result<T, Error> result = primary()
        if result.isOk() { return result }
        if resilienceCancelled(result.error()) { return result }
        if context.isCancelled() { return Err(resilienceError(ErrorKind.Cancelled, "fallback cancelled")) }
        if !shouldFallback(result.error()) { return result }
        return fallback(result.error())
    }
}
