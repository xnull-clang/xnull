package xdk.auth
import xdk.annotations

@Target(Method)
@Retention(Source)
@Repeatable
@annotation RequirePermission {
    final String value
}
