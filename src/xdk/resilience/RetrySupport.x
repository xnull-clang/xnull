package xdk.resilience
import xdk.errors
import xdk.runtime
import xdk.tasks
import xdk.time

class Retry {
    private Retry() { }

    static Bool _sleepCancellable(Context context, Long millis) {
        if millis <= 0 { return !context.isCancelled() }
        Result<Unit, Error> slept = sleepContext(context, durationOfMillis(millis))
        return slept.isOk()
    }

    static Result<T, Error> execute<T>(Context context, RetryPolicy policy,
                                      Result<T, Error>() operation) {
        if context == null || policy == null { throw "Retry.execute: null context or policy" }
        Int attempt = 1
        while true {
            if context.isCancelled() { return Err(resilienceError(ErrorKind.Cancelled, "retry cancelled")) }
            Result<T, Error> result = operation()
            if result.isOk() { return result }
            Error error = result.error()
            if resilienceCancelled(error) { return result }
            if !policy.shouldRetry(error, attempt) { return result }
            Long delay = policy.delayFor(attempt)
            if !Retry._sleepCancellable(context, delay) { return Err(resilienceError(ErrorKind.Cancelled, "retry cancelled")) }
            attempt = attempt + 1
        }
    }

    static Result<T, Error> executeWith<T>(Context context, RetryPolicy policy,
                                           Double() randomUnit,
                                           Result<T, Error>() operation,
                                           Bool(Error) isRetryable) {
        if context == null || policy == null { throw "Retry.executeWith: null context or policy" }
        Int attempt = 1
        while true {
            if context.isCancelled() { return Err(resilienceError(ErrorKind.Cancelled, "retry cancelled")) }
            Result<T, Error> result = operation()
            if result.isOk() { return result }
            Error error = result.error()
            if resilienceCancelled(error) { return result }
            if !isRetryable(error) { return result }
            if !policy.shouldRetry(error, attempt) { return result }
            Long delay = policy.delayForJittered(attempt, randomUnit())
            if !Retry._sleepCancellable(context, delay) { return Err(resilienceError(ErrorKind.Cancelled, "retry cancelled")) }
            attempt = attempt + 1
        }
    }
}
