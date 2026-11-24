// @Traced: generate an explicit span wrapper for a Result-returning method.
package xdk.trace
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation Traced {
    final String name = ""
}
