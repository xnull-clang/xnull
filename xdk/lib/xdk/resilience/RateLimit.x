// @RateLimit: generate a RateLimiter acquire + method wrapper.
package xdk.resilience
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation RateLimit {
    final String name = ""
    final Int permits = 1
    final Long perMillis = 1000
}
