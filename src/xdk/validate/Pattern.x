// @Pattern: the String field must match the regex (xdk.text Regex).
package xdk.validate
import xdk.annotations

@Retention(Source)
@Target(Field)
@annotation Pattern {
    final String value = ""
}
