// @Table sets a persistent table name (alternative to @Entity).
package xdk.db
import xdk.annotations

@Retention(Source)
@Target(Type)
@annotation Table {
    final String name = ""
}
