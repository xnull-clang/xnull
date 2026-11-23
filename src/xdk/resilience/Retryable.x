// @Retryable: generate a Retry.execute wrapper for a Result-returning method.
package xdk.resilience
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation Retryable {
    final Int maxAttempts = 3
    final Long initialDelayMillis = 100
}
