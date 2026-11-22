package app.cli
import xdk.cli

@CliCommand("root", "Root")
class RootCommand { }

@CliSubcommand("root", "status", "Status")
class StatusSub {
    @Option("--verbose", "v", "Verbose output")
    Bool verbose
    @Option("--format", "", "Output format", true)
    String format
    @Arg("target", "Target name", true)
    String target
}
