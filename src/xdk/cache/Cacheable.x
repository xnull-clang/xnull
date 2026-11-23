// @Cacheable: generate an explicit cache-read wrapper for a Result-returning method.
package xdk.cache
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation Cacheable {
    final String value = ""
    final String key = ""
}
