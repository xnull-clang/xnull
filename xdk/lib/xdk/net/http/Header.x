// @Header binds a handler parameter from an HTTP request header.
package xdk.net.http
import xdk.annotations

@Retention(Source)
@Target(Parameter)
@annotation Header {
    final String value = ""
}
