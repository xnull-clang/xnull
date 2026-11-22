// @HttpRoute declares a handler method and its method/path template.
package xdk.net.http
import xdk.annotations

@Retention(Source)
@Target(Method)
@annotation HttpRoute {
    final String path = ""
    final HttpMethod method = HttpMethod.Get
}
