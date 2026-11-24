package xdk.auth
import xdk.annotations

@Target(Type, Method)
@Retention(Source)
@annotation Auth {
    final String scheme = ""
}
