package xdk.cli
import xdk.annotations

@Retention(Source)
@Target(Field)
@annotation Arg {
    final String name = ""
    final String help = ""
    final Bool required = false
}
