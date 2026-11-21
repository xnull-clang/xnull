import xdk.log

static Int main() {
    Logger l = new Logger("app", Level.Info)
    l.debug("hidden")
    l.info("started")
    l.warn("careful")
    l.error("bad")
    Logger d = new Logger("dbg", Level.Debug)
    d.debug("visible")
    Logger fieldBase = new Logger("field", Level.Info)
    Logger fieldLogger = fieldBase.withField("component", "core")
    fieldLogger.info("with field")
    MemorySink memory = new MemorySink()
    Logger captured = new Logger("mem", Level.Warn)
    Logger capturedSink = captured.withSink(memory)
    Logger capturedField = capturedSink.withField("k", "v")
    capturedField.info("hidden")
    capturedField.warn("to memory")
    List<String> lines = memory.lines()
    print(lines.length())
    print(lines.get(0))
    return 0
}
