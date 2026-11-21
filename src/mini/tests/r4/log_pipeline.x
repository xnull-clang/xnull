// R4 evidence B8: filter predicate, redaction hook, deterministic sampler.
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
    FixedClock clock = new FixedClock(1700000000000, 123)
    MemorySink sink = new MemorySink()
    Logger base = new Logger("svc", Level.Debug)
    Logger configured = base.withClock(clock).withSink(sink)

    // Filter predicate: rejects a message substring before reaching the sink.
    Logger filtered = configured.withFilter(
        new PredicateFilter((LogRecord record) -> record.message.indexOf("drop") < 0))
    filtered.info("keep-one")
    filtered.info("drop-one")
    filtered.warn("keep-two")
    print(sink.lines().length())
    print(recordText(sink.captured().get(0)))
    print(recordText(sink.captured().get(1)))

    // Redaction hook: message and field values go through the same redactor.
    sink.clear()
    Logger redacted = configured.withRedactor(new ReplaceRedactor("secret", "[redacted]"))
    redacted.info("token secret")
    Logger redactedField = redacted.withField("password", "secret")
    redactedField.warn("second")
    print(sink.lines().get(0))
    print(sink.lines().get(1))

    // Deterministic sampler: every second accepted record.
    sink.clear()
    EveryNSampler sampler = new EveryNSampler(2)
    Logger sampled = configured.withSampler(sampler)
    sampled.info("s1")
    sampled.info("s2")
    sampled.info("s3")
    sampled.info("s4")
    print(sink.lines().length())
    print(sink.lines().get(0))
    print(sink.lines().get(1))
    print(sampler.count())

    // Composition order: level -> filter -> sampler -> redactor -> sink.
    sink.clear()
    EveryNSampler composed = new EveryNSampler(2)
    Logger pipeline = configured
        .withFilter(new PredicateFilter((LogRecord record) -> record.level == Level.Warn))
        .withSampler(composed)
        .withRedactor(new ReplaceRedactor("secret", "***"))
    pipeline.info("secret level-drop")
    pipeline.warn("secret one")
    pipeline.warn("secret two")
    print(sink.lines().length())
    print(sink.lines().get(0))
    print(composed.count())
    return 0
}
