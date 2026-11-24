package xdk2.metrics
import xdk.metrics
import xdk.time
import xdk.math

static List<String> labelList(String key, String value) {
    List<String> result = []
    result.push(key)
    result.push(value)
    return result
}

static Map<String, String> labelsOf(String key, String value) {
    Map<String, String> result = [:]
    result.put(key, value)
    return result
}

static Map<String, String> twoLabels(String firstKey, String firstValue, String secondKey, String secondValue) {
    Map<String, String> result = [:]
    result.put(firstKey, firstValue)
    result.put(secondKey, secondValue)
    return result
}

static List<Double> boundaryList() {
    List<Double> result = []
    result.push(5.0)
    result.push(10.0)
    return result
}

static Int main() {
    Counter counter = new Counter("requests", "Requests", "1", labelsOf("method", "GET"))
    print("counter-init=" + str(counter.get()))
    counter.inc()
    counter.add(5.0)
    print("counter-add=" + str(counter.get()))
    MetricFamily counterFamily = counter.snapshot()
    print("counter-snapshot=" + counterFamily.name() + "," + metricKindName(counterFamily.kind()) + "," +
        str(counterFamily.sampleCount()) + "," + str(counterFamily.samples().get(0).timestampMono() >= 0))
    print("counter-meta=" + counter.name() + "," + counter.help() + "," + counter.unit() + "," +
        counter.labels().getOr("method", ""))
    counter.reset()
    print("counter-reset=" + str(counter.get()))

    Gauge gauge = new Gauge("depth")
    gauge.set(10.0)
    gauge.add(2.0)
    gauge.sub(5.0)
    print("gauge=" + str(gauge.get()))
    gauge.set(-3.0)
    print("gauge-negative=" + str(gauge.get()))
    gauge.reset()
    print("gauge-reset=" + str(gauge.get()))

    Histogram histogram = new Histogram("latency", boundaryList())
    print("histogram-empty=" + str(isNaN(histogram.min())) + "," + str(isNaN(histogram.max())) + "," +
        str(isNaN(histogram.mean())) + "," + str(isNaN(histogram.percentile(50.0))))
    histogram.observe(-1.0)
    histogram.observe(5.0)
    histogram.observe(10.0)
    histogram.observe(12.0)
    print("histogram=" + str(histogram.count()) + "," + str(histogram.sum()) + "," + str(histogram.min()) + "," +
        str(histogram.max()) + "," + str(histogram.mean()))
    print("histogram-p=" + str(histogram.percentile(0.0)) + "," + str(histogram.percentile(50.0)) + "," +
        str(histogram.percentile(95.0)) + "," + str(histogram.percentile(100.0)))
    print("histogram-buckets=" + str(histogram.buckets().length()) + "," + str(histogram.buckets().get(0).count()) +
        "," + str(histogram.buckets().get(1).count()) + "," + str(histogram.buckets().get(2).count()))
    histogramFamilyCheck(histogram)
    List<Double> boundsCopy = histogram.boundaries()
    boundsCopy.push(99.0)
    print("histogram-bounds=" + str(histogram.boundaries().length()))
    histogram.reset()
    print("histogram-reset=" + str(histogram.count()) + "," + str(isNaN(histogram.min())))

    MetricTimer configuredTimer = new MetricTimer("configured", "Configured", "ms", labelsOf("route", "/"))
    MetricTimer legacyTimer = new MetricTimer("legacy", "Legacy", labelsOf("route", "/"))
    print("timer-config=" + configuredTimer.help() + "," + configuredTimer.unit() + "," +
        configuredTimer.labels().getOr("route", "") + "," + legacyTimer.help() + "," + legacyTimer.unit())
    MetricTimer timer = new MetricTimer("operation")
    print("timer-empty=" + str(timer.count()) + "," + str(timer.total().millis()) + "," + str(isNaN(timer.mean())) +
        "," + str(isNaN(timer.max())) + "," + str(isNaN(timer.percentile(50.0))))
    timer.observe(new Duration(10))
    timer.observe(new Duration(20))
    timer.observe(new Duration(30))
    print("timer=" + str(timer.count()) + "," + str(timer.total().millis()) + "," + str(timer.mean()) + "," +
        str(timer.max()))
    print("timer-p=" + str(timer.percentile(0.0)) + "," + str(timer.percentile(50.0)) + "," +
        str(timer.percentile(95.0)) + "," + str(timer.percentile(100.0)))
    MetricFamily timerFamily = timer.snapshot()
    print("timer-snapshot=" + str(timerFamily.sampleCount()) + "," + timerFamily.samples().get(0).name() + "," +
        timerFamily.samples().get(2).name())
    Long started = timer.start()
    Duration elapsed = timer.stop(started)
    print("timer-stop=" + str(elapsed.millis() >= 0) + "," + str(timer.count()))
    timer.reset()
    print("timer-reset=" + str(timer.count()) + "," + str(timerSnapshotCount(timer)))

    Map<String, String> firstLabels = labelsOf("a", "1")
    Map<String, String> secondLabels = twoLabels("b", "2", "a", "3")
    MetricSample sample = new MetricSample("sample", firstLabels, 1.5, 7)
    MetricSample same = new MetricSample("sample", firstLabels, 1.5, 7)
    MetricSample changed = sample.withValue(2.5)
    MetricSample reordered = new MetricSample("sample", secondLabels, 1.5, 7)
    print("sample=" + sample.name() + "," + str(sample.value()) + "," + str(sample.timestampMono()) + "," +
        str(sample.equals(same)) + "," + str(sample.equals(changed)))
    print("sample-with=" + str(changed.value()) + "," + str(changed.timestampMono()))
    Map<String, String> labelsCopy = sample.labels()
    labelsCopy.put("a", "9")
    print("sample-labels=" + sample.labels().getOr("a", ""))
    Map<String, String> nanLabels = [:]
    MetricSample nan1 = new MetricSample("nan", nanLabels, NaN(), 1)
    MetricSample nan2 = new MetricSample("nan", nanLabels, NaN(), 1)
    print("sample-nan=" + str(nan1.equals(nan2)))
    Map<String, String> sortedLabels = twoLabels("k2", "b", "k1", "a")
    MetricSample sorted = new MetricSample("s", sortedLabels, 1.0, 2)
    print("sample-toString=" + str(sorted.toString().startsWith("s{k1=\"a\",k2=\"b\"}")))

    List<MetricSample> familySamples = []
    familySamples.push(sample)
    MetricFamily family = new MetricFamily("sample", MetricKind.Counter, "Help", "1", familySamples)
    print("family=" + family.name() + "," + metricKindName(family.kind()) + "," + family.help() + "," +
        family.unit() + "," + str(family.sampleCount()) + "," + str(family.isEmpty()) + "," +
        str(family.samples().length()))
    List<MetricSample> emptyFamilySamples = []
    MetricFamily emptyFamily = new MetricFamily("empty", MetricKind.Gauge, "", "", emptyFamilySamples)
    print("family-empty=" + str(emptyFamily.isEmpty()) + "," + str(emptyFamily.sampleCount()) + "," +
        emptyFamily.toString())
    List<MetricSample> familyCopy = family.samples()
    familyCopy.clear()
    print("family-copy=" + str(family.sampleCount()))

    print("format=" + metricsFormatName(MetricsFormat.Text) + "," + metricsFormatName(MetricsFormat.Json) + "," +
        metricsFormatName(MetricsFormat.Prometheus) + "," + metricKindName(MetricKind.Counter) + "," +
        metricKindName(MetricKind.Gauge) + "," + metricKindName(MetricKind.Histogram) + "," +
        metricKindName(MetricKind.Timer))

    Metric metric = counter
    print("metric=" + metric.name() + "," + metricKindName(metric.kind()) + "," +
        str(metric.labels().length()) + "," + str(metric.snapshot().sampleCount()))

    Registry registry = new Registry()
    Result<Counter, Error> firstCounter = registry.counter("http_requests")
    Result<Counter, Error> secondCounter = registry.counter("http_requests")
    print("registry-counter=" + str(firstCounter.isOk()) + "," + str(secondCounter.isOk()) + "," +
        str(firstCounter.value() == secondCounter.value()))
    Result<Gauge, Error> gaugeResult = registry.gauge("queue")
    Result<Gauge, Error> kindConflict = registry.gauge("http_requests")
    print("registry-gauge=" + str(gaugeResult.isOk()) + "," + str(kindConflict.isErr()) + "," +
        errorKindName(kindConflict.error().kind()))
    Result<Histogram, Error> histogramResult = registry.histogram("request_ms", boundaryList())
    List<Double> otherBounds = []
    otherBounds.push(1.0)
    Result<Histogram, Error> boundsConflict = registry.histogram("request_ms", otherBounds)
    print("registry-histogram=" + str(histogramResult.isOk()) + "," + str(boundsConflict.isErr()) + "," +
        errorKindName(boundsConflict.error().kind()))
    Result<MetricTimer, Error> timerResult = registry.timer("elapsed")
    Result<MetricTimer, Error> timerAgain = registry.timer("elapsed")
    print("registry-timer=" + str(timerResult.isOk()) + "," + str(timerResult.value() == timerAgain.value()))

    Counter labeled = new Counter("http_requests", "", "", labelsOf("method", "GET"))
    Result<Unit, Error> added = registry.register(labeled)
    Metric? byLabels = registry.getLabeled("http_requests", labelsOf("method", "GET"))
    Metric? wrongLabels = registry.getLabeled("http_requests", labelsOf("method", "POST"))
    print("registry-labels=" + str(added.isOk()) + "," + str(byLabels != null) + "," + str(wrongLabels == null))
    Metric? emptySeries = registry.get("http_requests")
    print("registry-get=" + str(emptySeries != null))

    Counter metadata = new Counter("http_requests", "different", "", labelsOf("method", "PUT"))
    Result<Unit, Error> metadataConflict = registry.register(metadata)
    print("registry-metadata=" + str(metadataConflict.isErr()) + "," +
        errorKindName(metadataConflict.error().kind()))

    List<String> names = registry.names()
    print("registry-names=" + str(names.length()) + "," + names.get(0) + "," + names.get(names.length() - 1))

    List<MetricFamily> families = registry.snapshot()
    print("registry-snapshot=" + str(families.length()) + "," + families.get(0).name())
    print("registry-snapshot-count=" + str(families.get(0).sampleCount()))

    Bool removedLabel = registry.removeLabeled("http_requests", labelsOf("method", "GET"))
    Bool removedMissing = registry.removeLabeled("http_requests", labelsOf("method", "GET"))
    print("registry-remove-labels=" + str(removedLabel) + "," + str(removedMissing) + "," +
        str(registry.getLabeled("http_requests", labelsOf("method", "GET")) == null))
    Bool removedFamily = registry.remove("queue")
    print("registry-remove=" + str(removedFamily) + "," + str(registry.get("queue") == null))

    Counter kept = new Counter("kept")
    Result<Unit, Error> keptAdded = registry.register(kept)
    Counter previous = firstCounter.value()
    registry.clear()
    previous.inc()
    print("registry-clear=" + str(registry.names().length()) + "," + str(previous.get()))

    Map<String, String> copiedLabels = labelsOf("k", "v")
    Counter copyCheck = new Counter("copy_check", "", "", copiedLabels)
    copiedLabels.put("k", "changed")
    print("labels-copy=" + copyCheck.labels().getOr("k", ""))
    return 0
}

static Void histogramFamilyCheck(Histogram histogram) {
    MetricFamily family = histogram.snapshot()
    print("histogram-snapshot=" + str(family.sampleCount()) + "," + family.samples().get(0).name() + "," +
        family.samples().get(0).labels().getOr("le", "") + "," +
        str(family.samples().get(0).value()) + "," +
        family.samples().get(2).labels().getOr("le", ""))
}

static Int timerSnapshotCount(MetricTimer timer) {
    return timer.snapshot().sampleCount()
}
