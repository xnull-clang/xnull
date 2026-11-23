package app.cli
import xdk.cli
import xdk.errors
import generated.CliGenerated
import models

static Result<CommandMatch, Error> parseArgs(Command tree, List<String> raw) {
    return tree.parse(new Args(raw))
}

static Int main() {
    Command tree = cliCommandTree()
    Command status = tree.children().get(0)

    List<String> shortRaw = ["-v", "status", "target"]
    Result<CommandMatch, Error> shortMatch = parseArgs(tree, shortRaw)
    print("short-before=" + str(shortMatch.isOk()))
    if shortMatch.isOk() {
        print("short-before-command=" + shortMatch.value().command + "," +
            str(shortMatch.value().arguments.has("--verbose")) + "," +
            shortMatch.value().positionals().get(0))
    }

    List<String> formatRaw = ["--format", "json", "status", "target"]
    Result<CommandMatch, Error> formatMatch = parseArgs(tree, formatRaw)
    print("format-before=" + str(formatMatch.isOk()))
    if formatMatch.isOk() {
        print("format-before-command=" + formatMatch.value().command)
    }

    List<String> missingRaw = ["status"]
    Result<CommandMatch, Error> missing = parseArgs(tree, missingRaw)
    print("missing-pos=" + str(missing.isErr()) + "," + str(missing.error().kind() == ErrorKind.InvalidArgument))
    print("missing-pos-message=" + missing.error().describe())

    List<String> extraRaw = ["status", "target", "1", "true", "extra"]
    Result<CommandMatch, Error> extra = parseArgs(tree, extraRaw)
    print("extra-pos=" + str(extra.isErr()) + "," + str(extra.error().describe()))

    List<String> terminatorRaw = ["status", "target", "--", "-x"]
    Result<CommandMatch, Error> terminator = parseArgs(tree, terminatorRaw)
    print("terminator=" + str(terminator.isOk()))
    if terminator.isOk() {
        print("terminator-pos=" + str(terminator.value().positionals().length()) + "," +
            terminator.value().positionals().get(1))
    }

    List<String> unknownRaw = ["status", "--bogus", "target"]
    Result<CommandMatch, Error> unknown = parseArgs(tree, unknownRaw)
    print("unknown-option=" + str(unknown.isErr()) + "," + unknown.error().describe())

    List<String> missingValueRaw = ["status", "target", "--format"]
    Result<CommandMatch, Error> missingValue = parseArgs(tree, missingValueRaw)
    print("missing-option-value=" + str(missingValue.isErr()) + "," + missingValue.error().describe())

    List<String> bindRaw = ["status", "--verbose", "--format", "json", "--count", "7",
        "--ratio", "1.5", "target", "3", "true"]
    Result<CommandMatch, Error> bindMatch = parseArgs(tree, bindRaw)
    print("bind-match=" + str(bindMatch.isOk()))
    Result<StatusSub, Error> bound = StatusSubBind(bindMatch.value())
    print("bind=" + str(bound.isOk()))
    if bound.isOk() {
        StatusSub value = bound.value()
        print("bind-values=" + value.target + "," + str(value.level) + "," + str(value.enabled) + "," +
            str(value.verbose) + "," + value.format + "," + str(value.count) + "," + str(value.ratio))
    }

    List<String> badNumberRaw = ["status", "--count", "nope", "target"]
    Result<CommandMatch, Error> badNumberMatch = parseArgs(tree, badNumberRaw)
    Result<StatusSub, Error> badNumber = StatusSubBind(badNumberMatch.value())
    print("bad-option-number=" + str(badNumber.isErr()) + "," + badNumber.error().describe())

    List<String> badIntRaw = ["status", "target", "x"]
    Result<CommandMatch, Error> badIntMatch = parseArgs(tree, badIntRaw)
    Result<StatusSub, Error> badInt = StatusSubBind(badIntMatch.value())
    print("bad-positional-int=" + str(badInt.isErr()) + "," + badInt.error().describe())

    List<String> badBoolRaw = ["status", "target", "3", "yes"]
    Result<CommandMatch, Error> badBoolMatch = parseArgs(tree, badBoolRaw)
    Result<StatusSub, Error> badBool = StatusSubBind(badBoolMatch.value())
    print("bad-positional-bool=" + str(badBool.isErr()) + "," + badBool.error().describe())

    List<String> emptyRaw = []
    List<String> emptyPositionals = []
    CommandMatch emptyMatch = new CommandMatch(new Args(emptyRaw), "status", emptyPositionals)
    Result<StatusSub, Error> missingBound = StatusSubBind(emptyMatch)
    print("bind-missing=" + str(missingBound.isErr()) + "," + missingBound.error().describe())

    print("help-positional=" + str(status.help().indexOf("<target>") >= 0) + "," +
        str(status.help().indexOf("Target name") >= 0))
    print("positional-help=" + str(status.positionalHelp().length()) + "," +
        status.positionalHelp().get(0))
    ArgSpec spec = new ArgSpec("file", "Input file", true)
    ArgSpec optional = new ArgSpec("rest", "Extra", false)
    print("argspec=" + spec.describe() + "," + optional.describe())
    Args oldArgs = new Args(shortRaw)
    print("old-positionals=" + str(oldArgs.positionals().length()))
    return 0
}
