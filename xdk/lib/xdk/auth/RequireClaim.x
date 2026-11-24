package xdk.auth
import xdk.annotations

@Target(Method)
@Retention(Source)
@Repeatable
@annotation RequireClaim {
    final String name
    final String value
}
