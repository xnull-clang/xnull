// @Column maps a row field to a column name.
package xdk.sql
import xdk.annotations

@Retention(Source)
@Target(Field)
@annotation Column {
    final String value = ""
}
