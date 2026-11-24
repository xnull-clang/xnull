#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.metrics
import xdk.metrics
import xdk.time
import xdk.math
import xdk.tasks
import xdk.io

class PanicExporter implements Exporter {
    MetricsFormat format() { return 1 as MetricsFormat }
    Bool isOpen() { return true }
    Result<Unit, Error> export(Context context, Registry registry, Writer writer) {
        if context == null || registry == null || writer == null {
            throw "PanicExporter.export: null argument"
        }
        return Ok()
    }
    Result<Unit, Error> flush() { return Ok() }
    Result<Unit, Error> close() { return Ok() }
}

static Map<String, String> labels(String key, String value) {
    Map<String, String> result = [:]
    result.put(key, value)
    return result
}

static List<Double> unorderedBounds() {
    List<Double> result = []
    result.push(10.0)
    result.push(5.0)
    return result
}

static Double bigFinite() {
    Double value = 1.0
    Int index = 0
    while index < 1023 {
        value = value * 2.0
        index = index + 1
    }
    return value
}

static List<MetricSample> wrongFamilySamples() {
    Map<String, String> empty = [:]
    List<MetricSample> result = []
    result.push(new MetricSample("other", empty, 1.0, 1))
    return result
}

static Int main(String[] args) {
    String name = args.get(0)
    if name == "sampleName" {
        Map<String, String> empty = [:]
        MetricSample sample = new MetricSample("bad name", empty, 1.0, 1)
    } else if name == "sampleTimestamp" {
        Map<String, String> empty = [:]
        MetricSample sample = new MetricSample("sample", empty, 1.0, -1)
    } else if name == "sampleLabelKey" {
        MetricSample sample = new MetricSample("sample", labels("bad key", "v"), 1.0, 1)
    } else if name == "sampleNullLabels" {
        MetricSample sample = new MetricSample("sample", null, 1.0, 1)
    } else if name == "familyName" {
        List<MetricSample> empty = []
        MetricFamily family = new MetricFamily("bad name", MetricKind.Counter, "", "", empty)
    } else if name == "familySample" {
        MetricFamily family = new MetricFamily("family", MetricKind.Counter, "", "", wrongFamilySamples())
    } else if name == "counterNegative" {
        Counter counter = new Counter("counter")
        counter.add(-1.0)
    } else if name == "counterNaN" {
        Counter counter = new Counter("counter")
        counter.add(NaN())
    } else if name == "counterOverflow" {
        Counter counter = new Counter("counter")
        counter.add(bigFinite())
        counter.add(bigFinite())
    } else if name == "gaugeNonFinite" {
        Gauge gauge = new Gauge("gauge")
        gauge.set(NaN())
    } else if name == "gaugeOverflow" {
        Gauge gauge = new Gauge("gauge")
        gauge.set(bigFinite())
        gauge.add(bigFinite())
    } else if name == "histogramNaN" {
        List<Double> bounds = []
        Histogram histogram = new Histogram("histogram", bounds)
        histogram.observe(NaN())
    } else if name == "histogramBounds" {
        Histogram histogram = new Histogram("histogram", unorderedBounds())
    } else if name == "histogramLe" {
        Map<String, String> badLabels = labels("le", "5")
        List<Double> bounds = []
        Histogram histogram = new Histogram("histogram", "", "", badLabels, bounds)
    } else if name == "timerNegative" {
        MetricTimer timer = new MetricTimer("timer")
        timer.observe(new Duration(-1))
    } else if name == "timerStart" {
        MetricTimer timer = new MetricTimer("timer")
        timer.stop(-1)
    } else if name == "timerPercentile" {
        MetricTimer timer = new MetricTimer("timer")
        timer.percentile(NaN())
    } else if name == "registryName" {
        Registry registry = new Registry()
        registry.counter("")
    } else if name == "registryRegisterNull" {
        Registry registry = new Registry()
        registry.register(null)
    } else if name == "timerUnit" {
        MetricTimer timer = new MetricTimer("timer", "", "seconds", labels("a", "b"))
    } else if name == "exporterContext" {
        PanicExporter exporter = new PanicExporter()
        Registry registry = new Registry()
        Writer writer = new Writer()
        exporter.export(null, registry, writer)
    } else if name == "exporterRegistry" {
        PanicExporter exporter = new PanicExporter()
        Context context = Context.background()
        Writer writer = new Writer()
        exporter.export(context, null, writer)
    } else if name == "exporterWriter" {
        PanicExporter exporter = new PanicExporter()
        Context context = Context.background()
        Registry registry = new Registry()
        exporter.export(context, registry, null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || {
    cat "$TMP/build.err" >&2
    exit 1
}
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && {
        echo "metrics panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$name.err" || {
        echo "metrics panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}
check_panic sampleName "MetricSample: invalid name"
check_panic sampleTimestamp "MetricSample: negative timestamp"
check_panic sampleLabelKey "MetricSample: invalid label key"
check_panic sampleNullLabels "MetricSample: null labels"
check_panic familyName "MetricFamily: invalid name"
check_panic familySample "MetricFamily: sample name does not belong to family"
check_panic counterNegative "Counter.add: negative delta"
check_panic counterNaN "Counter.add: non-finite delta"
check_panic counterOverflow "Counter.add: overflow"
check_panic gaugeNonFinite "Gauge.set: non-finite value"
check_panic gaugeOverflow "Gauge.add: overflow"
check_panic histogramNaN "Histogram.observe: NaN"
check_panic histogramBounds "BucketHistogram: boundaries must be strictly increasing"
check_panic histogramLe "Histogram: reserved label le"
check_panic timerNegative "MetricTimer.observe: negative duration"
check_panic timerStart "MetricTimer.stop: negative start"
check_panic timerPercentile "MetricTimer.percentile: non-finite percentile"
check_panic registryName "Registry.counter: invalid name"
check_panic registryRegisterNull "Registry.register: null metric"
check_panic timerUnit "MetricTimer: unit must be ms"
check_panic exporterContext "PanicExporter.export: null argument"
check_panic exporterRegistry "PanicExporter.export: null argument"
check_panic exporterWriter "PanicExporter.export: null argument"
echo "metrics_panic: PASS"
