// @CircuitBreakerPolicy: generate a CircuitBreaker.execute wrapper.
package xdk.resilience
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation CircuitBreakerPolicy {
    final String name = ""
    final Int failureThreshold = 5
}
