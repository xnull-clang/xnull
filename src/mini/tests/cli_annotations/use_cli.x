package app.cli
import xdk.cli
import generated.CliGenerated
import models
static Int main() {
    Command tree = cliCommandTree()
    print(tree.name)
    print(tree.summary)
    Command status = tree.children().get(0)
    print(status.name)
    print(status.options.length())
    print(status.options.get(0).name)
    print(status.options.get(0).shortName)
    print(status.options.get(1).required)
    print(status.help().indexOf("Verbose output") >= 0)
    print(tree.help().indexOf("Status") >= 0)
    print(cliPositionalHelp().get(0).indexOf("target") >= 0)
    List<String> rawArgs = ["status", "--verbose", "--format", "json", "target"]
    Result<CommandMatch, Error> matched = tree.parse(new Args(rawArgs))
    print(matched.isOk())
    print(matched.value().command)
    print(matched.value().arguments.has("--format"))
    return 0
}
