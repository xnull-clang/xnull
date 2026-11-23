// @CacheEvict: generate an explicit invalidate + method wrapper.
package xdk.cache
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation CacheEvict {
    final String value = ""
    final String key = ""
}
