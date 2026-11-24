#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
PLATFORM="$ROOT/src/toolchain/annotation_platform.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/metrics.manifest.json" --generated-dir "$TMP/generated" >"$TMP/generate.log" 2>&1
diff -u "$HERE/generated/MetricsGenerated.x" "$TMP/generated/MetricsGenerated.x"
grep -q 'AN2303' "$TMP/generate.log"

grep -q '^import xdk.metrics$' "$TMP/generated/MetricsGenerated.x"
grep -q 'Service_successMetered(Service target, Registry registry, Int id)' "$TMP/generated/MetricsGenerated.x"
grep -q 'registry.timer("op.success")' "$TMP/generated/MetricsGenerated.x"
grep -q 'registry.timer("Service.failure")' "$TMP/generated/MetricsGenerated.x"
grep -q 'unitName "us" is not applied' "$TMP/generated/MetricsGenerated.x"
grep -q 'timer[0-9]*.stop(started[0-9]*)' "$TMP/generated/MetricsGenerated.x"

mkdir -p "$TMP/project/generated"
cp "$HERE/run.x" "$TMP/project/run.x"
cp "$TMP/generated/MetricsGenerated.x" "$TMP/project/generated/MetricsGenerated.x"
"$ROOT/src/cli/xnull" --bootstrap --engine=mini build "$TMP/project/run.x" -o "$TMP/run" >"$TMP/build.log" 2>&1
"$TMP/run" >"$TMP/run.out"
diff -u "$HERE/run.out" "$TMP/run.out"

python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/metrics.manifest.json" --generated-dir "$HERE/generated" >/dev/null

python3 "$PLATFORM" generate --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
    --manifest "$HERE/metrics.manifest.json" --generated-dir "$TMP/generated2" >/dev/null 2>&1
cmp "$TMP/generated/MetricsGenerated.x" "$TMP/generated2/MetricsGenerated.x"

expect_check_fail() {
    name="$1"
    if python3 "$PLATFORM" check --entry "$HERE/app.x" --xdk-root "$ROOT/src/xdk" \
        --manifest "$HERE/metrics.manifest.json" --generated-dir "$TMP/$name" >"$TMP/$name.log" 2>&1; then
        echo "metrics_annotations: $name unexpectedly passed" >&2
        exit 1
    fi
}

cp -R "$HERE/generated" "$TMP/drift"
printf '\n// drift\n' >>"$TMP/drift/MetricsGenerated.x"
expect_check_fail drift

cp -R "$HERE/generated" "$TMP/missing"
rm "$TMP/missing/MetricsGenerated.x"
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
        --manifest "$HERE/metrics.manifest.json" --generated-dir "$TMP/out_$name" >"$TMP/$name.log" 2>&1; then
        echo "metrics_annotations: $name accepted" >&2
        exit 1
    fi
    grep -q "$expected" "$TMP/$name.log"
}

case_fail bad_return 'AN2301' 'package app.metrics
import xdk.metrics
class A {
    @Metered("a")
    Bool run() { return true }
}
static Int main() { return 0 }'

case_fail type_target 'AN2302' 'package app.metrics
import xdk.metrics
@Metered("a")
class A { }
static Int main() { return 0 }'

case_fail static_method 'AN2304' 'package app.metrics
import xdk.metrics
class A {
    @Metered("a")
    static Result<Int, Error> run() { return Ok(1) }
}
static Int main() { return 0 }'

echo "metrics_annotations: PASS"
