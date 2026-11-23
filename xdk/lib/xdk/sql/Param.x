// @Param binds a DAO parameter to a named SQL placeholder.
package xdk.sql
import xdk.annotations

@Retention(Source)
@Target(Parameter)
@annotation Param {
    final String value = ""
}
