// @Entity declares a persistent entity and its table name.
package xdk.db
import xdk.annotations

@Retention(Source)
@Target(Type)
@annotation Entity {
    final String table = ""
}
