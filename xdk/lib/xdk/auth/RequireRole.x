package xdk.auth
import xdk.annotations

@Target(Method)
@Retention(Source)
@Repeatable
@annotation RequireRole {
    final String value
}
