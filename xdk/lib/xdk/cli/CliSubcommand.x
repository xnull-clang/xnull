package xdk.cli
import xdk.annotations

@Retention(Source)
@Target(Type)
@annotation CliSubcommand {
    final String parent = ""
    final String name = ""
    final String summary = ""
}
