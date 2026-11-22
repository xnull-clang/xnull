// @Query binds a handler parameter from the request query string.
package xdk.net.http
import xdk.annotations

@Retention(Source)
@Target(Parameter)
@annotation Query {
    final String value = ""
}
