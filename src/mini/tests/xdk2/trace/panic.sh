#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.trace
import xdk.trace
import xdk.errors
import xdk.math
import xdk.time

static Map<String, String> labels(String key, String value) {
    Map<String, String> result = [:]
    result.put(key, value)
    return result
}

static SpanContext validContext() {
    return new SpanContext("4bf92f3577b34da6a3ce929d0e0e4736", "00f067aa0ba902b7",
        null, true, labels("a", "b"))
}

static Int main(String[] args) {
    String name = args.get(0)
    if name == "contextNull" {
        SpanContext context = new SpanContext(null, "00f067aa0ba902b7", null, true, labels("a", "b"))
    } else if name == "eventName" {
        SpanEvent event = new SpanEvent("", 1, labels("a", "b"))
    } else if name == "eventTime" {
        SpanEvent event = new SpanEvent("event", -1, labels("a", "b"))
    } else if name == "eventNull" {
        SpanEvent event = new SpanEvent("event", 1, null)
    } else if name == "samplerNaN" {
        Sampler sampler = Sampler.ratio(NaN())
    } else if name == "samplerHigh" {
        Sampler sampler = Sampler.ratio(1.5)
    } else if name == "samplerNull" {
        Bool sampled = Sampler.alwaysOn().shouldSample(null)
    } else if name == "optionsService" {
        TraceOptions options = new TraceOptions()
        options.serviceName("   ")
    } else if name == "optionsAttributes" {
        TraceOptions options = new TraceOptions()
        options.maxAttributes(1025)
    } else if name == "optionsSampler" {
        TraceOptions options = new TraceOptions()
        options.sampler(null)
    } else if name == "spanName" {
        TraceOptions options = new TraceOptions()
        Tracer tracer = Tracer.create(options).value()
        Span span = tracer.startSpan("")
    } else if name == "spanParent" {
        TraceOptions options = new TraceOptions()
        Tracer tracer = Tracer.create(options).value()
        SpanContext invalid = new SpanContext("bad", "00f067aa0ba902b7", null, true, labels("a", "b"))
        Span span = tracer.startSpanFromKind("child", invalid, SpanKind.Internal)
    } else if name == "spanAttribute" {
        TraceOptions options = new TraceOptions()
        Tracer tracer = Tracer.create(options).value()
        Span span = tracer.startSpan("span")
        span.setAttribute("", "value")
    } else if name == "spanEvent" {
        TraceOptions options = new TraceOptions()
        Tracer tracer = Tracer.create(options).value()
        Span span = tracer.startSpan("span")
        span.addEvent("", labels("a", "b"))
    } else if name == "w3cInject" {
        W3cPropagator propagator = new W3cPropagator()
        Map<String, String> carrier = [:]
        propagator.inject(null, carrier)
    } else if name == "tracerInject" {
        TraceOptions options = new TraceOptions()
        Tracer tracer = Tracer.create(options).value()
        tracer.inject(validContext(), null)
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
        echo "trace panic: $name did not fail" >&2
        exit 1
    }
    grep -Fq "$marker" "$TMP/$name.err" || {
        echo "trace panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}
check_panic contextNull "SpanContext: null argument"
check_panic eventName "SpanEvent: invalid name"
check_panic eventTime "SpanEvent: negative timestamp"
check_panic eventNull "SpanEvent: null argument"
check_panic samplerNaN "Sampler.ratio: value outside [0,1]"
check_panic samplerHigh "Sampler.ratio: value outside [0,1]"
check_panic samplerNull "Sampler.shouldSample: null context"
check_panic optionsService "TraceOptions.serviceName: invalid"
check_panic optionsAttributes "TraceOptions.maxAttributes: outside 0..1024"
check_panic optionsSampler "TraceOptions.sampler: null"
check_panic spanName "Tracer.startSpanKind: invalid name"
check_panic spanParent "Tracer.startSpanFromKind: invalid parent"
check_panic spanAttribute "Span.setAttribute: empty key"
check_panic spanEvent "Span.addEvent: invalid name"
check_panic w3cInject "W3cPropagator.inject: null argument"
check_panic tracerInject "Tracer.inject: null argument"
echo "trace_panic: PASS"
