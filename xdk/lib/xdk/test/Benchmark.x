// @Benchmark: expose a no-argument benchmark method as an explicit Test entry.
package xdk.test
import xdk.annotations

@Retention(Runtime)
@Target(Method)
@annotation Benchmark {
    final String name = ""
}
