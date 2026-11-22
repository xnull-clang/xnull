// @Min: numeric lower bound; for String fields it is the minimum length.
package xdk.validate
import xdk.annotations

@Retention(Source)
@Target(Field)
@annotation Min {
    final Long value = 0
}
