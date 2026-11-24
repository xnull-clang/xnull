package xdk.metrics
import xdk.errors
import xdk.runtime
import xdk.math
import xdk.time
import xdk.stats
import xdk.tasks
import xdk.io

enum MetricKind {
    Unknown,
    Counter,
    Gauge,
    Histogram,
    Timer,
}

String metricKindName(MetricKind kind) {
    if kind == MetricKind.Counter { return "counter" }
    if kind == MetricKind.Gauge { return "gauge" }
    if kind == MetricKind.Histogram { return "histogram" }
    if kind == MetricKind.Timer { return "timer" }
    return "unknown"
}

enum MetricsFormat {
    Unknown,
    Text,
    Json,
    Prometheus,
}

String metricsFormatName(MetricsFormat format) {
    if format == MetricsFormat.Text { return "text" }
    if format == MetricsFormat.Json { return "json" }
    if format == MetricsFormat.Prometheus { return "prometheus" }
    return "unknown"
}

static Bool metricHasChar(String text, String value) {
    return text.indexOf(value) >= 0
}

static Bool metricNameValid(String name) {
    if name == null || name == "" { return false }
    if metricHasChar(name, " ") || metricHasChar(name, "\t") { return false }
    if metricHasChar(name, "\n") || metricHasChar(name, "\r") { return false }
    if metricHasChar(name, "{") || metricHasChar(name, "}") { return false }
    if metricHasChar(name, "\"") || metricHasChar(name, ",") { return false }
    return true
}

static Bool metricLabelKeyValid(String key) {
    if !metricNameValid(key) { return false }
    if metricHasChar(key, "=") { return false }
    return true
}

static Void metricCheckName(String owner, String name) {
    if !metricNameValid(name) { throw owner + ": invalid name" }
}

static Map<String, String> metricCopyLabels(String owner, Map<String, String> labels, Bool forbidLe) {
    if labels == null { throw owner + ": null labels" }
    Map<String, String> copy = [:]
    List<String> keys = labels.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        String found = labels.getOr(key, metricMissingLabel())
        if !metricLabelKeyValid(key) { throw owner + ": invalid label key" }
        if forbidLe && key == "le" { throw owner + ": reserved label le" }
        if found == metricMissingLabel() { throw owner + ": null label value" }
        copy.put(key, found)
        index = index + 1
    }
    return copy
}

static String metricMissingLabel() {
    return "__xdk_metrics_missing_label__"
}

static Map<String, String> metricCopyMap(Map<String, String> labels) {
    Map<String, String> copy = [:]
    List<String> keys = labels.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        copy.put(key, labels.getOr(key, ""))
        index = index + 1
    }
    return copy
}

static List<Metric> metricEmptySeries() {
    List<Metric> result = []
    return result
}

static Map<String, String> metricEmptyLabels() {
    Map<String, String> labels = [:]
    return labels
}

static Bool metricLabelsEqual(Map<String, String> left, Map<String, String> right) {
    if left.length() != right.length() { return false }
    List<String> keys = left.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        if !right.has(key) { return false }
        if left.getOr(key, metricMissingLabel()) != right.getOr(key, metricMissingLabel()) { return false }
        index = index + 1
    }
    return true
}

static Bool metricBoundariesEqual(List<Double> left, List<Double> right) {
    if left.length() != right.length() { return false }
    Int index = 0
    while index < left.length() {
        if left.get(index) != right.get(index) { return false }
        index = index + 1
    }
    return true
}

static Int metricCharRank(String text) {
    String order = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz./-"
    Int index = order.indexOf(text)
    if index < 0 { return order.length() }
    return index
}

static Int metricCompareStrings(String left, String right) {
    Int common = left.length()
    if right.length() < common { common = right.length() }
    Int index = 0
    while index < common {
        Int leftRank = metricCharRank(left.substring(index, 1))
        Int rightRank = metricCharRank(right.substring(index, 1))
        if leftRank < rightRank { return -1 }
        if leftRank > rightRank { return 1 }
        index = index + 1
    }
    if left.length() < right.length() { return -1 }
    if left.length() > right.length() { return 1 }
    return 0
}

static Bool metricLessString(String left, String right) {
    return metricCompareStrings(left, right) < 0
}

static List<String> metricSortedStrings(List<String> values) {
    List<String> result = values.copy()
    Int current = 1
    while current < result.length() {
        String value = result.get(current)
        Int position = current - 1
        while position >= 0 && metricLessString(value, result.get(position)) {
            result.set(position + 1, result.get(position))
            position = position - 1
        }
        result.set(position + 1, value)
        current = current + 1
    }
    return result
}

class MetricSample {
    final String _name
    final Map<String, String> _labels
    final Double _value
    final Long _timestampMono

    MetricSample(String name, Map<String, String> labels, Double value, Long timestampMono) {
        if !metricNameValid(name) { throw "MetricSample: invalid name" }
        if labels == null { throw "MetricSample: null labels" }
        if timestampMono < 0 { throw "MetricSample: negative timestamp" }
        Map<String, String> copy = metricCopyLabels("MetricSample", labels, false)
        self._name = name
        self._labels = copy
        self._value = value
        self._timestampMono = timestampMono
    }

    String name() { return self._name }
    Map<String, String> labels() { return metricCopyMap(self._labels) }
    Double value() { return self._value }
    Long timestampMono() { return self._timestampMono }

    MetricSample withValue(Double value) {
        return new MetricSample(self._name, self._labels, value, self._timestampMono)
    }

    Bool equals(MetricSample other) {
        if other == null { return false }
        if self._name != other._name { return false }
        if self._timestampMono != other._timestampMono { return false }
        if isNaN(self._value) != isNaN(other._value) { return false }
        if !isNaN(self._value) && self._value != other._value { return false }
        return metricLabelsEqual(self._labels, other._labels)
    }

    String toString() {
        List<String> keys = metricSortedStrings(self._labels.keys())
        String text = self._name
        if keys.length() > 0 {
            text = text + "{"
            Int index = 0
            while index < keys.length() {
                if index > 0 { text = text + "," }
                String key = keys.get(index)
                text = text + key + "=\"" + self._labels.getOr(key, "") + "\""
                index = index + 1
            }
            text = text + "}"
        }
        return text + " " + str(self._value) + " " + str(self._timestampMono)
    }
}

class MetricFamily {
    final String _name
    final MetricKind _kind
    final String _help
    final String _unit
    final List<MetricSample> _samples

    MetricFamily(String name, MetricKind kind, String help, String unitText, List<MetricSample> samples) {
        if !metricNameValid(name) { throw "MetricFamily: invalid name" }
        if kind == null || kind == MetricKind.Unknown { throw "MetricFamily: null kind" }
        if help == null { throw "MetricFamily: null help" }
        if unitText == null { throw "MetricFamily: null unit" }
        if samples == null { throw "MetricFamily: null samples" }
        List<MetricSample> copy = []
        Int index = 0
        while index < samples.length() {
            MetricSample sample = samples.get(index)
            if sample == null { throw "MetricFamily: null sample" }
            if sample.name() != name && !sample.name().startsWith(name + "_") {
                throw "MetricFamily: sample name does not belong to family"
            }
            copy.push(sample)
            index = index + 1
        }
        self._name = name
        self._kind = kind
        self._help = help
        self._unit = unitText
        self._samples = copy
    }

    String name() { return self._name }
    MetricKind kind() { return self._kind }
    String help() { return self._help }
    String unit() { return self._unit }
    List<MetricSample> samples() { return self._samples.copy() }
    Int sampleCount() { return self._samples.length() }
    Bool isEmpty() { return self._samples.length() == 0 }

    String toString() {
        return metricKindName(self._kind) + " " + self._name + " (" + str(self._samples.length()) + " samples)"
    }
}

protocol Metric {
    String name();
    MetricKind kind();
    String help();
    String unit();
    Map<String, String> labels();
    MetricFamily snapshot();
    void reset();
}

protocol Exporter {
    MetricsFormat format();
    Result<Unit, Error> export(Context context, Registry registry, Writer writer);
    Result<Unit, Error> flush();
    Result<Unit, Error> close();
    Bool isOpen();
}

class Counter implements Metric {
    final String _name
    final String _help
    final String _unit
    final Map<String, String> _labels
    final RuntimeMonitor _monitor
    Double _value

    Counter(String name, String help, String unitText, Map<String, String> labels) {
        metricCheckName("Counter", name)
        if help == null { throw "Counter: null help" }
        if unitText == null { throw "Counter: null unit" }
        Map<String, String> copy = metricCopyLabels("Counter", labels, false)
        self._name = name
        self._help = help
        self._unit = unitText
        self._labels = copy
        self._monitor = new RuntimeMonitor()
        self._value = 0.0
    }

    Counter(String name) {
        metricCheckName("Counter", name)
        self._name = name
        self._help = ""
        self._unit = ""
        self._labels = metricEmptyLabels()
        self._monitor = new RuntimeMonitor()
        self._value = 0.0
    }

    String name() { return self._name }
    MetricKind kind() { return MetricKind.Counter }
    String help() { return self._help }
    String unit() { return self._unit }
    Map<String, String> labels() { return metricCopyMap(self._labels) }

    void inc() { self.add(1.0) }

    void add(Double delta) {
        if !isFinite(delta) { throw "Counter.add: non-finite delta" }
        if delta < 0.0 { throw "Counter.add: negative delta" }
        self._monitor.enter()
        Double next = self._value + delta
        if !isFinite(next) {
            self._monitor.exit()
            throw "Counter.add: overflow"
        }
        self._value = next
        self._monitor.exit()
    }

    Double get() {
        self._monitor.enter()
        Double value = self._value
        self._monitor.exit()
        return value
    }

    void reset() {
        self._monitor.enter()
        self._value = 0.0
        self._monitor.exit()
    }

    MetricFamily snapshot() {
        self._monitor.enter()
        Double value = self._value
        self._monitor.exit()
        Long timestamp = nowMono()
        List<MetricSample> samples = []
        samples.push(new MetricSample(self._name, self._labels, value, timestamp))
        return new MetricFamily(self._name, MetricKind.Counter, self._help, self._unit, samples)
    }
}

class Gauge implements Metric {
    final String _name
    final String _help
    final String _unit
    final Map<String, String> _labels
    final RuntimeMonitor _monitor
    Double _value

    Gauge(String name, String help, String unitText, Map<String, String> labels) {
        metricCheckName("Gauge", name)
        if help == null { throw "Gauge: null help" }
        if unitText == null { throw "Gauge: null unit" }
        Map<String, String> copy = metricCopyLabels("Gauge", labels, false)
        self._name = name
        self._help = help
        self._unit = unitText
        self._labels = copy
        self._monitor = new RuntimeMonitor()
        self._value = 0.0
    }

    Gauge(String name) {
        metricCheckName("Gauge", name)
        self._name = name
        self._help = ""
        self._unit = ""
        self._labels = metricEmptyLabels()
        self._monitor = new RuntimeMonitor()
        self._value = 0.0
    }

    String name() { return self._name }
    MetricKind kind() { return MetricKind.Gauge }
    String help() { return self._help }
    String unit() { return self._unit }
    Map<String, String> labels() { return metricCopyMap(self._labels) }

    void set(Double value) {
        if !isFinite(value) { throw "Gauge.set: non-finite value" }
        self._monitor.enter()
        self._value = value
        self._monitor.exit()
    }

    Double get() {
        self._monitor.enter()
        Double value = self._value
        self._monitor.exit()
        return value
    }

    void add(Double delta) {
        if !isFinite(delta) { throw "Gauge.add: non-finite delta" }
        self._monitor.enter()
        Double next = self._value + delta
        if !isFinite(next) {
            self._monitor.exit()
            throw "Gauge.add: overflow"
        }
        self._value = next
        self._monitor.exit()
    }

    void sub(Double delta) {
        if !isFinite(delta) { throw "Gauge.sub: non-finite delta" }
        self._monitor.enter()
        Double next = self._value - delta
        if !isFinite(next) {
            self._monitor.exit()
            throw "Gauge.sub: overflow"
        }
        self._value = next
        self._monitor.exit()
    }

    void reset() {
        self._monitor.enter()
        self._value = 0.0
        self._monitor.exit()
    }

    MetricFamily snapshot() {
        self._monitor.enter()
        Double value = self._value
        self._monitor.exit()
        Long timestamp = nowMono()
        List<MetricSample> samples = []
        samples.push(new MetricSample(self._name, self._labels, value, timestamp))
        return new MetricFamily(self._name, MetricKind.Gauge, self._help, self._unit, samples)
    }
}

class Histogram implements Metric {
    final String _name
    final String _help
    final String _unit
    final Map<String, String> _labels
    final List<Double> _boundaries
    final BucketHistogram _delegate
    final RuntimeMonitor _monitor

    Histogram(String name, String help, String unitText, Map<String, String> labels,
              List<Double> boundaries) {
        metricCheckName("Histogram", name)
        if help == null { throw "Histogram: null help" }
        if unitText == null { throw "Histogram: null unit" }
        if boundaries == null { throw "Histogram: null boundaries" }
        Map<String, String> copy = metricCopyLabels("Histogram", labels, true)
        List<Double> bounds = boundaries.copy()
        self._name = name
        self._help = help
        self._unit = unitText
        self._labels = copy
        self._boundaries = bounds
        self._delegate = new BucketHistogram(bounds)
        self._monitor = new RuntimeMonitor()
    }

    Histogram(String name, List<Double> boundaries) {
        metricCheckName("Histogram", name)
        if boundaries == null { throw "Histogram: null boundaries" }
        List<Double> bounds = boundaries.copy()
        self._name = name
        self._help = ""
        self._unit = ""
        self._labels = metricEmptyLabels()
        self._boundaries = bounds
        self._delegate = new BucketHistogram(bounds)
        self._monitor = new RuntimeMonitor()
    }

    String name() { return self._name }
    MetricKind kind() { return MetricKind.Histogram }
    String help() { return self._help }
    String unit() { return self._unit }
    Map<String, String> labels() { return metricCopyMap(self._labels) }

    void observe(Double value) {
        if isNaN(value) { throw "Histogram.observe: NaN" }
        self._monitor.enter()
        self._delegate.observe(value)
        self._monitor.exit()
    }

    Long count() {
        self._monitor.enter()
        Long value = self._delegate.count()
        self._monitor.exit()
        return value
    }

    Double sum() {
        self._monitor.enter()
        Double value = self._delegate.sum()
        self._monitor.exit()
        return value
    }

    Double min() {
        self._monitor.enter()
        Double value = self._delegate.min()
        self._monitor.exit()
        return value
    }

    Double max() {
        self._monitor.enter()
        Double value = self._delegate.max()
        self._monitor.exit()
        return value
    }

    Double mean() {
        self._monitor.enter()
        Double value = self._delegate.mean()
        self._monitor.exit()
        return value
    }

    Double percentile(Double percentileValue) {
        if !isFinite(percentileValue) { throw "Histogram.percentile: non-finite percentile" }
        self._monitor.enter()
        Double value = self._delegate.percentile(percentileValue)
        self._monitor.exit()
        return value
    }

    List<HistogramBucket> buckets() {
        self._monitor.enter()
        List<HistogramBucket> value = self._delegate.buckets()
        self._monitor.exit()
        return value
    }

    List<Double> boundaries() { return self._boundaries.copy() }

    void reset() {
        self._monitor.enter()
        self._delegate.reset()
        self._monitor.exit()
    }

    MetricFamily snapshot() {
        self._monitor.enter()
        Long count = self._delegate.count()
        Double total = self._delegate.sum()
        List<HistogramBucket> bucketList = self._delegate.buckets()
        self._monitor.exit()
        Long timestamp = nowMono()
        List<MetricSample> samples = []
        Long cumulative = 0
        Int index = 0
        while index < bucketList.length() {
            HistogramBucket bucket = bucketList.get(index)
            cumulative = cumulative + bucket.count()
            Map<String, String> bucketLabels = metricCopyMap(self._labels)
            if bucket.upper() == null {
                bucketLabels.put("le", "+Inf")
            } else {
                bucketLabels.put("le", str(bucket.upper() as Double))
            }
            samples.push(new MetricSample(self._name + "_bucket", bucketLabels,
                                          cumulative as Double, timestamp))
            index = index + 1
        }
        samples.push(new MetricSample(self._name + "_sum", self._labels, total, timestamp))
        samples.push(new MetricSample(self._name + "_count", self._labels, count as Double, timestamp))
        return new MetricFamily(self._name, MetricKind.Histogram, self._help, self._unit, samples)
    }
}

class MetricTimer implements Metric {
    final String _name
    final String _help
    final String _unit
    final Map<String, String> _labels
    final Summary _summary
    final RuntimeMonitor _monitor

    MetricTimer(String name, String help, String unitText, Map<String, String> labels) {
        metricCheckName("MetricTimer", name)
        if help == null { throw "MetricTimer: null help" }
        if unitText == null { throw "MetricTimer: null unit" }
        if unitText != "" && unitText != "ms" { throw "MetricTimer: unit must be ms" }
        Map<String, String> copy = metricCopyLabels("MetricTimer", labels, false)
        self._name = name
        self._help = help
        self._unit = "ms"
        self._labels = copy
        self._summary = new Summary()
        self._monitor = new RuntimeMonitor()
    }

    MetricTimer(String name, String help, Map<String, String> labels) {
        metricCheckName("MetricTimer", name)
        if help == null { throw "MetricTimer: null help" }
        Map<String, String> copy = metricCopyLabels("MetricTimer", labels, false)
        self._name = name
        self._help = help
        self._unit = "ms"
        self._labels = copy
        self._summary = new Summary()
        self._monitor = new RuntimeMonitor()
    }

    MetricTimer(String name) {
        metricCheckName("MetricTimer", name)
        self._name = name
        self._help = ""
        self._unit = "ms"
        self._labels = metricEmptyLabels()
        self._summary = new Summary()
        self._monitor = new RuntimeMonitor()
    }

    String name() { return self._name }
    MetricKind kind() { return MetricKind.Timer }
    String help() { return self._help }
    String unit() { return self._unit }
    Map<String, String> labels() { return metricCopyMap(self._labels) }

    void observe(Duration duration) {
        if duration == null { throw "MetricTimer.observe: null duration" }
        Long millis = duration.millis()
        if millis < 0 { throw "MetricTimer.observe: negative duration" }
        self._monitor.enter()
        self._summary.observe(millis as Double)
        self._monitor.exit()
    }

    Long start() { return nowMono() }

    Duration stop(Long startMono) {
        if startMono < 0 { throw "MetricTimer.stop: negative start" }
        Long elapsed = nowMono() - startMono
        if elapsed < 0 { elapsed = 0 }
        Duration duration = new Duration(elapsed)
        self.observe(duration)
        return duration
    }

    Long count() {
        self._monitor.enter()
        Long value = self._summary.count()
        self._monitor.exit()
        return value
    }

    Duration total() {
        self._monitor.enter()
        Double value = self._summary.sum()
        self._monitor.exit()
        if value > 9223372036854775807.0 { throw "MetricTimer.total: overflow" }
        return new Duration(value as Long)
    }

    Double mean() {
        self._monitor.enter()
        Double value = self._summary.mean()
        self._monitor.exit()
        return value
    }

    Double max() {
        self._monitor.enter()
        Double value = self._summary.max()
        self._monitor.exit()
        return value
    }

    Double percentile(Double percentileValue) {
        if !isFinite(percentileValue) { throw "MetricTimer.percentile: non-finite percentile" }
        self._monitor.enter()
        Double value = self._summary.quantile(percentileValue / 100.0)
        self._monitor.exit()
        return value
    }

    void reset() {
        self._monitor.enter()
        self._summary.reset()
        self._monitor.exit()
    }

    MetricFamily snapshot() {
        self._monitor.enter()
        Long count = self._summary.count()
        Double total = self._summary.sum()
        Double maximum = 0.0
        if count > 0 { maximum = self._summary.max() }
        self._monitor.exit()
        Long timestamp = nowMono()
        List<MetricSample> samples = []
        samples.push(new MetricSample(self._name + "_count", self._labels, count as Double, timestamp))
        samples.push(new MetricSample(self._name + "_sum", self._labels, total, timestamp))
        if count > 0 {
            samples.push(new MetricSample(self._name + "_max", self._labels, maximum, timestamp))
        }
        return new MetricFamily(self._name, MetricKind.Timer, self._help, self._unit, samples)
    }
}

class Registry {
    final Map<String, List<Metric>> _families
    final RuntimeMonitor _monitor

    Registry() {
        Map<String, List<Metric>> families = [:]
        self._families = families
        self._monitor = new RuntimeMonitor()
    }

    Result<Counter, Error> counter(String name) {
        metricCheckName("Registry.counter", name)
        Metric? existing = self.get(name)
        if existing != null {
            Metric found = existing as Metric
            if found.kind() != MetricKind.Counter {
                return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.counter: name conflict for " + name))
            }
            return Ok(found as Counter)
        }
        Counter created = new Counter(name)
        Result<Unit, Error> added = self.register(created)
        if added.isErr() { return Err(added.error()) }
        Metric? stored = self.get(name)
        if stored == null {
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.counter: name conflict for " + name))
        }
        Metric storedMetric = stored as Metric
        if storedMetric.kind() != MetricKind.Counter {
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.counter: name conflict for " + name))
        }
        return Ok(storedMetric as Counter)
    }

    Result<Gauge, Error> gauge(String name) {
        metricCheckName("Registry.gauge", name)
        Metric? existing = self.get(name)
        if existing != null {
            Metric found = existing as Metric
            if found.kind() != MetricKind.Gauge {
                return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.gauge: name conflict for " + name))
            }
            return Ok(found as Gauge)
        }
        Gauge created = new Gauge(name)
        Result<Unit, Error> added = self.register(created)
        if added.isErr() { return Err(added.error()) }
        Metric? stored = self.get(name)
        if stored == null {
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.gauge: name conflict for " + name))
        }
        Metric storedMetric = stored as Metric
        if storedMetric.kind() != MetricKind.Gauge {
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.gauge: name conflict for " + name))
        }
        return Ok(storedMetric as Gauge)
    }

    Result<Histogram, Error> histogram(String name, List<Double> boundaries) {
        metricCheckName("Registry.histogram", name)
        if boundaries == null { throw "Registry.histogram: null boundaries" }
        Metric? existing = self.get(name)
        if existing != null {
            Metric found = existing as Metric
            if found.kind() != MetricKind.Histogram {
                return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.histogram: name conflict for " + name))
            }
            Histogram current = existing as Histogram
            if !metricBoundariesEqual(current.boundaries(), boundaries) {
                return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.histogram: boundaries conflict for " + name))
            }
            return Ok(current)
        }
        Histogram created = new Histogram(name, boundaries)
        Result<Unit, Error> added = self.register(created)
        if added.isErr() { return Err(added.error()) }
        Metric? stored = self.get(name)
        if stored == null {
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.histogram: name conflict for " + name))
        }
        Metric storedMetric = stored as Metric
        if storedMetric.kind() != MetricKind.Histogram {
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.histogram: name conflict for " + name))
        }
        Histogram result = stored as Histogram
        if !metricBoundariesEqual(result.boundaries(), boundaries) {
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.histogram: boundaries conflict for " + name))
        }
        return Ok(result)
    }

    Result<MetricTimer, Error> timer(String name) {
        metricCheckName("Registry.timer", name)
        Metric? existing = self.get(name)
        if existing != null {
            Metric found = existing as Metric
            if found.kind() != MetricKind.Timer {
                return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.timer: name conflict for " + name))
            }
            return Ok(found as MetricTimer)
        }
        MetricTimer created = new MetricTimer(name)
        Result<Unit, Error> added = self.register(created)
        if added.isErr() { return Err(added.error()) }
        Metric? stored = self.get(name)
        if stored == null {
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.timer: name conflict for " + name))
        }
        Metric storedMetric = stored as Metric
        if storedMetric.kind() != MetricKind.Timer {
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.timer: name conflict for " + name))
        }
        return Ok(storedMetric as MetricTimer)
    }

    Result<Unit, Error> register(Metric metric) {
        if metric == null { throw "Registry.register: null metric" }
        if !metricNameValid(metric.name()) { throw "Registry.register: invalid name" }
        String name = metric.name()
        self._monitor.enter()
        if !self._families.has(name) {
            List<Metric> series = []
            series.push(metric)
            self._families.put(name, series)
            self._monitor.exit()
            return Ok()
        }
        List<Metric> series = self._families.getOr(name, metricEmptySeries())
        Metric first = series.get(0)
        if first.kind() != metric.kind() {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.register: kind conflict for " + name))
        }
        if first.help() != metric.help() || first.unit() != metric.unit() {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.register: metadata conflict for " + name))
        }
        if first.kind() == MetricKind.Histogram {
            Histogram existing = first as Histogram
            Histogram candidate = metric as Histogram
            if !metricBoundariesEqual(existing.boundaries(), candidate.boundaries()) {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.AlreadyExists, "Registry.register: boundaries conflict for " + name))
            }
        }
        Map<String, String> incomingLabels = metric.labels()
        Int index = 0
        while index < series.length() {
            Metric current = series.get(index)
            if metricLabelsEqual(current.labels(), incomingLabels) {
                self._monitor.exit()
                return Ok()
            }
            index = index + 1
        }
        series.push(metric)
        self._monitor.exit()
        return Ok()
    }

    Metric? get(String name) {
        if name == null { throw "Registry.get: null name" }
        self._monitor.enter()
        Metric? result = null
        if self._families.has(name) {
            List<Metric> series = self._families.getOr(name, metricEmptySeries())
            Int index = 0
            while index < series.length() {
                Metric current = series.get(index)
                if current.labels().length() == 0 {
                    result = current
                    break
                }
                index = index + 1
            }
        }
        self._monitor.exit()
        return result
    }

    Metric? getLabeled(String name, Map<String, String> labels) {
        if name == null { throw "Registry.getLabeled: null name" }
        if labels == null { throw "Registry.getLabeled: null labels" }
        self._monitor.enter()
        Metric? result = null
        if self._families.has(name) {
            List<Metric> series = self._families.getOr(name, metricEmptySeries())
            Int index = 0
            while index < series.length() {
                Metric current = series.get(index)
                if metricLabelsEqual(current.labels(), labels) {
                    result = current
                    break
                }
                index = index + 1
            }
        }
        self._monitor.exit()
        return result
    }

    Bool remove(String name) {
        if name == null { throw "Registry.remove: null name" }
        self._monitor.enter()
        Bool removed = self._families.remove(name)
        self._monitor.exit()
        return removed
    }

    Bool removeLabeled(String name, Map<String, String> labels) {
        if name == null { throw "Registry.removeLabeled: null name" }
        if labels == null { throw "Registry.removeLabeled: null labels" }
        self._monitor.enter()
        Bool removed = false
        if self._families.has(name) {
            List<Metric> series = self._families.getOr(name, metricEmptySeries())
            Int index = 0
            while index < series.length() {
                Metric current = series.get(index)
                if metricLabelsEqual(current.labels(), labels) {
                    series.remove(index)
                    removed = true
                    break
                }
                index = index + 1
            }
            if series.length() == 0 { self._families.remove(name) }
        }
        self._monitor.exit()
        return removed
    }

    List<String> names() {
        self._monitor.enter()
        List<String> result = self._families.keys()
        self._monitor.exit()
        return metricSortedStrings(result)
    }

    List<MetricFamily> snapshot() {
        self._monitor.enter()
        List<String> familyNames = self._families.keys()
        Map<String, List<Metric>> copied = [:]
        Int index = 0
        while index < familyNames.length() {
            String name = familyNames.get(index)
            copied.put(name, self._families.getOr(name, metricEmptySeries()).copy())
            index = index + 1
        }
        self._monitor.exit()
        List<String> ordered = metricSortedStrings(familyNames)
        List<MetricFamily> result = []
        index = 0
        while index < ordered.length() {
            String name = ordered.get(index)
            List<Metric> series = copied.getOr(name, metricEmptySeries())
            List<MetricSample> samples = []
            MetricKind kind = MetricKind.Unknown
            String help = ""
            String unitText = ""
            Bool first = true
            Int seriesIndex = 0
            while seriesIndex < series.length() {
                MetricFamily family = series.get(seriesIndex).snapshot()
                if first {
                    kind = family.kind()
                    help = family.help()
                    unitText = family.unit()
                    first = false
                }
                List<MetricSample> familySamples = family.samples()
                Int sampleIndex = 0
                while sampleIndex < familySamples.length() {
                    samples.push(familySamples.get(sampleIndex))
                    sampleIndex = sampleIndex + 1
                }
                seriesIndex = seriesIndex + 1
            }
            if !first {
                result.push(new MetricFamily(name, kind, help, unitText, samples))
            }
            index = index + 1
        }
        return result
    }

    void clear() {
        self._monitor.enter()
        self._families.clear()
        self._monitor.exit()
    }
}
