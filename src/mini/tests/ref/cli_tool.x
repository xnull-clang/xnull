// Reference CLI tool: subcommands, config FileSource, structured log, time.
import xdk.cli
import xdk.config
import xdk.log
import xdk.time
import xdk.errors

static Int main(String[] args) {
    List<OptionSpec> configOptions = []
    configOptions.push(new OptionSpec("--config", true, "path to key=value config", true))

    List<OptionSpec> rootOptions = []
    Command root = new Command("demo", "reference CLI tool", rootOptions)
    Command run = new Command("run", "load config and report", configOptions)
    List<OptionSpec> helpOptions = []
    Command help = new Command("help", "show command help", helpOptions)
    root.add(run)
    root.add(help)

    Args arguments = new Args(args)
    Result<CommandMatch, Error> matched = root.parse(arguments)
    if matched.isErr() {
        print(matched.error().kind() == ErrorKind.InvalidArgument)
        return 0
    }

    String command = matched.value().command
    if command == "help" {
        print(root.help())
        return 0
    }

    String path = arguments.value("--config")
    Config config = new Config("ref")
    FileSource source = new FileSource(path)
    Result<Unit, Error> applied = config.apply(source)
    if applied.isErr() {
        print(applied.error().kind() == ErrorKind.NotFound)
        return 0
    }
    print(config.getOr("app.name", "?"))
    print(config.getOr("app.port", "?"))

    MemorySink sink = new MemorySink()
    Logger logger = new Logger("ref", Level.Info)
    Logger sinkLogger = logger.withSink(sink)
    Logger fieldLogger = sinkLogger.withField("component", "cli")
    fieldLogger.info("loaded")
    print(sink.lines().get(0))

    DateTime stamp = dateTimeFromTimestamp(1700000000000)
    print(stamp.format("yyyy-MM-dd HH:mm:ss"))
    return 0
}
