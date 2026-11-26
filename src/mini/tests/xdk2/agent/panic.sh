#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/agent-panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.agent
import xdk.agent
import xdk.metrics
import xdk.trace
import xdk.log
import xdk.runtime
import xdk.errors

static MetricFamily panicFamily() {
    List<MetricSample> samples = []
    return new MetricFamily("requests", MetricKind.Counter, "help", "1", samples)
}

static SpanContext panicContext() {
    Map<String, String> baggage = [:]
    return new SpanContext("0123456789abcdef0123456789abcdef",
        "0123456789abcdef", null, true, baggage)
}

static Int main(String[] args) {
    String name = args.get(0)
    if name == "metricFamily" {
        TelemetryRecord value = TelemetryRecord.metric(null, 1 as Long, 1 as Long)
    } else if name == "metricTimestamp" {
        TelemetryRecord value = TelemetryRecord.metric(panicFamily(), -1 as Long, 1 as Long)
    } else if name == "spanName" {
        Map<String, String> attributes = [:]
        List<SpanEvent> events = []
        TelemetryRecord value = TelemetryRecord.span("", panicContext(),
            SpanKind.Server, SpanStatus.Ok, 1 as Long, attributes, events, 1 as Long,
            1 as Long)
    } else if name == "spanContext" {
        Map<String, String> attributes = [:]
        List<SpanEvent> events = []
        TelemetryRecord value = TelemetryRecord.span("x", null, SpanKind.Server,
            SpanStatus.Ok, 1 as Long, attributes, events, 1 as Long, 1 as Long)
    } else if name == "spanDuration" {
        Map<String, String> attributes = [:]
        List<SpanEvent> events = []
        TelemetryRecord value = TelemetryRecord.span("x", panicContext(),
            SpanKind.Server, SpanStatus.Ok, -1 as Long, attributes, events, 1 as Long,
            1 as Long)
    } else if name == "spanKind" {
        Map<String, String> attributes = [:]
        List<SpanEvent> events = []
        TelemetryRecord value = TelemetryRecord.span("x", panicContext(),
            SpanKind.Unknown, SpanStatus.Ok, 1 as Long, attributes, events, 1 as Long,
            1 as Long)
    } else if name == "logNull" {
        TelemetryRecord value = TelemetryRecord.log(null)
    } else if name == "batchKind" {
        Map<String, String> resource = [:]
        List<TelemetryRecord> records = []
        TelemetryBatch value = new TelemetryBatch(TelemetryKind.Unknown, resource,
            records, 0, 1 as Long)
    } else if name == "batchDropped" {
        Map<String, String> resource = [:]
        List<TelemetryRecord> records = []
        TelemetryBatch value = new TelemetryBatch(TelemetryKind.Metrics, resource,
            records, -1, 1 as Long)
    } else if name == "batchTimestamp" {
        Map<String, String> resource = [:]
        List<TelemetryRecord> records = []
        TelemetryBatch value = new TelemetryBatch(TelemetryKind.Metrics, resource,
            records, 0, -1 as Long)
    } else if name == "batchResource" {
        Map<String, String> resource = [:]
        resource.put("bad=key", "v")
        List<TelemetryRecord> records = []
        TelemetryBatch value = new TelemetryBatch(TelemetryKind.Metrics, resource,
            records, 0, 1 as Long)
    } else if name == "batchMismatch" {
        Map<String, String> resource = [:]
        List<TelemetryRecord> records = []
        TelemetryRecord record = TelemetryRecord.metric(panicFamily(), 1 as Long,
            1 as Long)
        records.push(record)
        TelemetryBatch value = new TelemetryBatch(TelemetryKind.Logs, resource,
            records, 0, 1 as Long)
    } else if name == "batchSplit" {
        Map<String, String> resource = [:]
        List<TelemetryRecord> records = []
        TelemetryBatch batch = new TelemetryBatch(TelemetryKind.Metrics, resource,
            records, 0, 1 as Long)
        List<TelemetryBatch> value = batch.split(0)
    } else if name == "batchDropNegative" {
        Map<String, String> resource = [:]
        List<TelemetryRecord> records = []
        TelemetryBatch batch = new TelemetryBatch(TelemetryKind.Metrics, resource,
            records, 0, 1 as Long)
        TelemetryBatch value = batch.withAdditionalDropped(-1)
    } else if name == "healthName" {
        AgentHealth value = new AgentHealth("", "api", 1)
    } else if name == "healthCount" {
        AgentHealth value = new AgentHealth("h", "api", -1)
    } else if name == "healthReady" {
        AgentHealth health = new AgentHealth("h", "api", 1)
        health.markReady(2)
    } else if name == "healthDrop" {
        AgentHealth health = new AgentHealth("h", "api", 1)
        health.recordDrop(-1)
    } else if name == "healthFailure" {
        AgentHealth health = new AgentHealth("h", "api", 1)
        health.recordFailure(null)
    } else if name == "healthUnhealthy" {
        AgentHealth health = new AgentHealth("h", "api", 1)
        health.markUnhealthy(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1; marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "agent panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "agent panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic metricFamily "TelemetryRecord.metric: null family"
check_panic metricTimestamp "TelemetryRecord: negative timestamp"
check_panic spanName "TelemetryRecord: empty name"
check_panic spanContext "TelemetryRecord.span: invalid context"
check_panic spanDuration "TelemetryRecord.span: negative duration"
check_panic spanKind "TelemetryRecord.span: null kind/status"
check_panic logNull "TelemetryRecord.log: null record"
check_panic batchKind "TelemetryBatch: invalid kind"
check_panic batchDropped "TelemetryBatch: negative dropped"
check_panic batchTimestamp "TelemetryBatch: negative timestamp"
check_panic batchResource "TelemetryBatch: invalid resource key"
check_panic batchMismatch "TelemetryBatch: record kind mismatch"
check_panic batchSplit "TelemetryBatch.split: maximumRecords <= 0"
check_panic batchDropNegative "TelemetryBatch.withAdditionalDropped: negative"
check_panic healthName "AgentHealth: empty name"
check_panic healthCount "AgentHealth: negative pipeline count"
check_panic healthReady "AgentHealth.markReady: ready out of range"
check_panic healthDrop "AgentHealth.recordDrop: negative"
check_panic healthFailure "AgentHealth.recordFailure: null"
check_panic healthUnhealthy "AgentHealth.markUnhealthy: null"
echo "agent_panic: PASS"
