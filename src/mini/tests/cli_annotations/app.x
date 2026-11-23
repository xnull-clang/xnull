package app.cli
import xdk.cli

@CliCommand("root", "Root")
class RootCommand { }

@CliSubcommand("root", "status", "Status")
class StatusSub {
    @Option("--verbose", "v", "Verbose output")
    Bool verbose
    @Option("--format", "", "Output format")
    String format
    @Option("--count", "", "Retry count")
    Long count
    @Option("--ratio", "", "Ratio")
    Double ratio
    @Arg("target", "Target name", true)
    String target
    @Arg("level", "Level", false)
    Int level
    @Arg("enabled", "Enabled", false)
    Bool enabled
}
