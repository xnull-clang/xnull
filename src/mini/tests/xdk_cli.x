import xdk.cli

static Int main(String[] args) {
    Args a = new Args(args)
    print(a.length())
    print(a.has("--name"))
    print(a.has("--missing"))
    print(a.value("--name"))
    print(a.valueOr("--missing", "fallback"))
    List<String> pos = a.positionals()
    print(pos.length())
    if pos.length() > 0 {
        print(pos.get(0))
    }
    print(usage("demo", "--name <name> [files]"))
    print(exitCodeFor("usage"))
    List<OptionSpec> rootOptions = []
    rootOptions.push(new OptionSpec("--verbose", false, "verbose output", false))
    Command root = new Command("demo", "demo tool", rootOptions)
    List<OptionSpec> childOptions = []
    childOptions.push(new OptionSpec("--output", true, "output path", true))
    Command run = new Command("run", "run task", childOptions)
    root.add(run)
    print(root.children().length())
    List<String> commandArgv = ["run", "--output", "x"]
    Args commandArgs = new Args(commandArgv)
    Result<CommandMatch, Error> matched = root.parse(commandArgs)
    print(matched.isOk())
    print(matched.value().command)
    print(root.help())
    List<String> missingArgv = ["run"]
    Args missingArgs = new Args(missingArgv)
    Result<CommandMatch, Error> missing = root.parse(missingArgs)
    print(missing.isErr())
    return 0
}
