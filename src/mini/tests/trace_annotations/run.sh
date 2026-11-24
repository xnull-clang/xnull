#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/trace.manifest.json" --generated-dir "$TMP/generated"
diff -u "$HERE/generated/TraceGenerated.x" "$TMP/generated/TraceGenerated.x"

grep -q '^import xdk.trace$' "$TMP/generated/TraceGenerated.x"
grep -q 'Service_successTraced(Service target, Tracer tracer, Int id)' "$TMP/generated/TraceGenerated.x"
grep -q 'tracer.startSpan("custom.success")' "$TMP/generated/TraceGenerated.x"
grep -q 'tracer.startSpan("Service.failure")' "$TMP/generated/TraceGenerated.x"
grep -q 'span.recordError(failure)' "$TMP/generated/TraceGenerated.x"
grep -q 'span.end()' "$TMP/generated/TraceGenerated.x"

mkdir -p "$TMP/project/generated"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$TMP/generated/TraceGenerated.x" "$TMP/project/generated/TraceGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/trace.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/trace.manifest.json" --generated-dir "$TMP/generated2"
cmp "$TMP/generated/TraceGenerated.x" "$TMP/generated2/TraceGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/trace.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "trace_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/TraceGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/TraceGenerated.x"
expect_check_fail missing

cp -R "$HERE/generated" "$TMP/extra"
printf '// extra\n' >"$TMP/extra/Extra.x"
expect_check_fail extra

case_fail() {
    name="$1"
    expected="$2"
    src="$3"
    printf '%s\n' "$src" >"$TMP/$name.x"
    if python3 "$PLATFORM" generate --entry "$TMP/$name.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/trace.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "trace_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_fail bad_return 'AN2401' 'package app.trace
import xdk.trace
class A {
    @Traced("a")
    Bool run() { return true }
}
static Int main() { return 0 }'

case_fail static_method 'AN2404' 'package app.trace
import xdk.trace
class A {
    @Traced("a")
    static Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

echo "trace_annotations: PASS"
