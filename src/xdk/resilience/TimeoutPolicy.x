// @TimeoutPolicy: generate a Timeout.execute wrapper.
package xdk.resilience
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation TimeoutPolicy {
    final Long timeoutMillis = 1000
}
