// @Audited: generate an explicit audit wrapper for a Result-returning method.
package xdk.audit
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation Audited {
    final String action = ""
}
