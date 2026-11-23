// @Sql declares a DAO method and its SQL text. The package implementation
// already occupies Sql.x, so the annotation lives in this sibling file.
package xdk.sql
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation Sql {
    final String value = ""
}
