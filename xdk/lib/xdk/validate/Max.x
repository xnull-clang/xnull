// @Max: numeric upper bound; for String fields it is the maximum length.
package xdk.validate
import xdk.annotations

@Retention(Source)
@Target(Field)
@annotation Max {
    final Long value = 0
}
