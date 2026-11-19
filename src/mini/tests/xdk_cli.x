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
    return 0
}
