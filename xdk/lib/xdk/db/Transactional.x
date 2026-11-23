// @Transactional wraps a DAO method in a database transaction.
package xdk.db
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation Transactional {
    final Bool readOnly = false
}
