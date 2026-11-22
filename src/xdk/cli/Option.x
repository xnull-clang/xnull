package xdk.cli
import xdk.annotations

@Retention(Source)
@Target(Field)
@annotation Option {
    final String name = ""
    final String short = ""
    final String help = ""
    final Bool required = false
}
