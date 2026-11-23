// @CsvName maps a serializable field to a CSV column name.
package xdk.codec
import xdk.annotations

@Retention(Source)
@Target(Field)
@annotation CsvName {
    final String value = ""
}
