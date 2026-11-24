// @Metered: generate an explicit duration wrapper around a Result-returning method.
package xdk.metrics
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation Metered {
    final String name = ""
    final String unitName = ""
}
