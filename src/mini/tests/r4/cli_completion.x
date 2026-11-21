import xdk.cli

static Int main() {
    List<String> raw = ["-ab", "pos", "--", "-c", "--name", "late"]
    Args a = new Args(raw)
    print(a.has("--name"))
    List<String> pos = a.positionals()
    print(pos.length())
    print(pos.get(0))
    print(pos.get(1))
    print(pos.get(2))
    List<String> known = ["-a", "-b"]
    Args expanded = a.expandShortFlags(known)
    print(expanded.has("-a"))
    print(expanded.has("-b"))
    List<String> duplicateRaw = ["--k", "one", "--k=two", "--k", "three"]
    Args duplicate = new Args(duplicateRaw)
    print(duplicate.value("--k"))
    print(duplicate.lastValue("--k"))
    print(duplicate.values("--k").length())

    OptionSpec verboseSpec = new OptionSpec("--verbose", false, "verbose output", false)
    OptionSpec verbose = verboseSpec.withShort("-v")
    OptionSpec allSpec = new OptionSpec("--all", false, "all entries", false)
    OptionSpec all = allSpec.withShort("-a")
    List<OptionSpec> rootOptions = []
    rootOptions.push(verbose)
    rootOptions.push(all)
    Command root = new Command("demo", "demo tool", rootOptions)
    OptionSpec outputSpec = new OptionSpec("--output", true, "output path", false)
    OptionSpec output = outputSpec.withShort("-o")
    List<OptionSpec> childOptions = []
    childOptions.push(output)
    Command run = new Command("run", "run task", childOptions)
    root.add(run)

    List<String> bundleRaw = ["-va"]
    Args bundle = new Args(bundleRaw)
    Result<CommandMatch, Error> matched = root.parse(bundle)
    print(matched.isOk())
    print(matched.value().arguments.has("--verbose"))
    print(matched.value().arguments.has("--all"))
    print(completionBash(root))
    return 0
}
