import xdk.log

class FixedClock implements Clock {
    Long wall
    Long mono

    FixedClock(Long wall0, Long mono0) {
        self.wall = wall0
        self.mono = mono0
    }

    Long wallMs() {
        return self.wall
    }

    Long monoMs() {
        return self.mono
    }
}

static Int main() {
    FixedClock clock = new FixedClock(1700000000000, 500)
    MemorySink sink = new MemorySink()
    Logger base = new Logger("svc", Level.Info)
    Logger timed = base.withClock(clock)
    Logger logger = timed.withSink(sink)
    logger.info("ready")
    logger.debug("hidden")
    Logger fieldLogger = logger.withField("k", "v")
    fieldLogger.info("field")
    List<LogRecord> records = sink.captured()
    print(records.length())
    print(records.get(0).timestampMs)
    print(records.get(0).monotonicMs)
    print(records.get(0).timestamp())
    print(records.get(0).monotonic())
    print(records.get(0).level == Level.Info)
    print(recordText(records.get(0)))
    print(recordTextWithTime(records.get(0)))
    print(sink.lines().get(0))
    print(records.get(1).timestampMs)
    print(recordText(records.get(1)))
    return 0
}
